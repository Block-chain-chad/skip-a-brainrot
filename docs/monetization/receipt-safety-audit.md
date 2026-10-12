# Receipt Safety Audit — ProductRegistry / DarrelService / PlayerDataManager

**Date:** 2026-08-04
**Scope:** every ordering in which a player can be charged Robux and not granted, or granted twice.
**Files audited (all paths relative to `game-src\place-full\`):**

- `ServerScriptService\Modules\ProductRegistry.lua` (76 lines)
- `ServerScriptService\Modules\DarrelService.lua` (111 lines)
- `ServerScriptService\Modules\PlayerDataManager.lua` (806 lines)
- `ServerScriptService\Main.server.lua` (join/leave/BindToClose wiring)

**Roblox ground rules assumed** (per MarketplaceService docs):

1. Robux is deducted at purchase time, *before* `ProcessReceipt` ever runs.
2. `PurchaseGranted` permanently closes the receipt — Roblox never redelivers it (unless the response itself was lost, see F3).
3. `NotProcessedYet` **and** an *error thrown inside the callback* both cause Roblox to retry: periodically, on the player's next purchase, and on next join — indefinitely.
4. Roblox does not formally guarantee it won't call the callback concurrently; same-session redelivery of one `PurchaseId` must be handled by the game.

**Core invariant the design relies on** (documented at `ProductRegistry.lua:54-57`): the darrel grant and the `ReceiptLog` entry live in the same in-memory table and are persisted in the same `UpdateAsync` write, so they vanish together or persist together. Every finding below is a place where that invariant can be broken.

---

## F1 — HIGH (double grant): `Award` mutates the balance *before* throw-capable side effects, and `ProcessReceipt` has no error boundary

**Where:**
- `ProductRegistry.lua:49` — `grant(player, data, def)` called bare, no `pcall`.
- `ProductRegistry.lua:50` — `ReceiptLog` insert happens only *after* `grant` returns.
- `DarrelService.lua:47-49` — `data.Darrels += n` (line 47) runs before `push(player, data)` and `PDM.PushUpdate(player)` (line 49), both of which can throw.
- `DarrelService.lua:37` — `remotes.DarrelUpdate:FireClient(...)` is a **direct index**: if the `DarrelUpdate` RemoteEvent is ever missing/renamed, this line errors. (`DarrelService.Init` self-heals `DarrelState` at lines 99-104 for exactly this reason, but `DarrelUpdate` gets no such treatment.) `PDM.PushUpdate` (`PlayerDataManager.lua:717`) likewise direct-indexes `Remotes.DataUpdated` and calls `FireClient`, which can error against a player mid-disconnect.

**The interleaving that dupes:**

```
1. Roblox delivers receipt R (player already charged).
2. ProcessReceipt: player found, data found, R not in ReceiptLog, def found.
3. grant() -> DarrelService.Award:
     line 47: data.Darrels += 400          <- GRANT IS NOW IN MEMORY
     line 49: push() THROWS                <- missing remote / FireClient error /
                                              any future edit to push/PushUpdate
4. Error unwinds through grant() and ProcessReceipt — line 50 (log insert)
   and line 52 (Save) NEVER RUN. Roblox records the errored callback as
   NotProcessedYet and schedules a retry.
5. Player keeps playing; leaves. Main.server.lua:86 -> PDM.Remove -> Save
   persists Darrels = old+400 WITH NO ReceiptLog ENTRY for R.
6. Next join: Roblox retries R. table.find misses (log has no R).
   Award runs again -> +400 again.
7. If the throw was deterministic (missing remote), repeat: +400 per retry,
   every session, forever — each session's leave-save banks the inflated
   balance while the log entry keeps getting skipped.
```

Charged once, granted twice (or N times). This is the only path found where the "grant and log travel together" invariant is broken in the *dupe* direction: the balance mutation escapes via the leave-save while the log entry does not.

**Proposed patch (primary — make `Award` unable to throw after the mutation):**

`DarrelService.lua:44-50`, before:

```lua
function M.Award(player, n, reason)
	local data = PDM.Get(player); if not data then return end
	n = math.floor(n); if n <= 0 or n ~= n then return end
	data.Darrels += n
	print(("[Darrels] +%d -> %d %s (%s)"):format(n, data.Darrels, player.Name, reason))
	push(player, data); PDM.PushUpdate(player)
end
```

After:

```lua
function M.Award(player, n, reason)
	local data = PDM.Get(player); if not data then return false end
	n = math.floor(n); if n <= 0 or n ~= n then return false end
	data.Darrels += n
	print(("[Darrels] +%d -> %d %s (%s)"):format(n, data.Darrels, player.Name, reason))
	-- UI pushes are best-effort. A throw here must never unwind past the
	-- balance mutation: ProcessReceipt would see an errored callback, skip the
	-- ReceiptLog insert, and Roblox's retry would re-run the grant (dupe).
	pcall(push, player, data)
	pcall(PDM.PushUpdate, player)
	return true
end
```

**Belt-and-braces at the call site** (`ProductRegistry.lua:49`), before:

```lua
	if not grant(player, data, def) then return Enum.ProductPurchaseDecision.NotProcessedYet end
```

After:

```lua
	local ok, granted = pcall(grant, player, data, def)
	if not ok then
		-- A throw here may or may not have mutated the balance; log loudly so a
		-- human can reconcile. Do NOT log the receipt as granted.
		warn("[ProductRegistry] grant errored for " .. tostring(info.ProductId) .. ": " .. tostring(granted))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not granted then return Enum.ProductPurchaseDecision.NotProcessedYet end
```

Note the `pcall` alone does **not** fix the dupe (if `grant` threw after mutating, `NotProcessedYet` still re-grants on retry) — the `Award`-side fix is the real one; the call-site `pcall` just converts an uncontrolled unwind into a logged, deliberate decision. Also note `push` is called from `M.Init`'s `PlayerAdded` handler and `TrySpend`; making it non-fatal there too is strictly an improvement.

---

## F2 — HIGH, latent (permanent loss): `grant()` cannot observe `Award` failure — a silent no-op gets logged and saved as granted, and the dedupe makes it unrecoverable

**Where:**
- `DarrelService.lua:45` — `if not data then return end` (bare return, no signal).
- `DarrelService.lua:46` — `if n <= 0 or n ~= n then return end` (bare return).
- `ProductRegistry.lua:16-19` — `grant` returns `true` for `Type == "Darrels"` **unconditionally**, ignoring `Award`'s (absent) result.
- `ProductRegistry.lua:50-59` — the receipt is then logged and saved, and `PurchaseGranted` returned.
- `ProductRegistry.lua:35-43` — every future retry hits the dedupe branch and returns `PurchaseGranted` again. There is no code path that can ever re-attempt the grant.

**The interleaving that loses the purchase permanently:**

```
1. A product is registered with Amount = 0 (or negative, or NaN) — one typo in
   a future M.Register call, or a PACK_IDS/PACK_AMOUNTS parallel-array edit
   that shifts an index (ProductRegistry.lua:68-72).
2. Player buys it. Charged.
3. Award hits line 46, returns silently. Nothing credited.
4. grant() returns true anyway. ReceiptLog gets the PurchaseId. Save succeeds.
   PurchaseGranted returned.
5. Roblox closes the receipt. The dedupe branch answers PurchaseGranted to any
   redelivery. The player is charged forever with zero darrels, and NO retry,
   rejoin, or server fix can ever grant it — the log says it already happened.
```

This is the worst failure class in the file: **charged, never granted, unrecoverable by retry.** It is currently unreachable — live amounts are 80/180/400/1000, and the `data == nil` arm can't fire because there are no yields between `ProcessReceipt`'s own `PDM.Get` (line 31) and `Award`'s (see "verified safe" section) — but it is one config edit away, and the failure it produces is the one kind the whole design exists to prevent. (`Amount = nil` from an array-length mismatch takes the F1 path instead: `math.floor(nil)` throws at `DarrelService.lua:46` — *before* the mutation, so it retries safely, but forever, per F4.)

**Proposed patch:** `Award` returns a boolean (already shown in F1's After); `grant` propagates it, and `Register` validates amounts at wiring time.

`ProductRegistry.lua:15-21`, before:

```lua
local function grant(player, data, def)
	if def.Type == "Darrels" then
		DarrelService.Award(player, def.Amount, "robux:" .. def.Amount)
		return true
	end
	return false
end
```

After:

```lua
local function grant(player, data, def)
	if def.Type == "Darrels" then
		-- Award returns false on any refusal (no data, bad amount). Logging a
		-- receipt whose grant silently no-opped would be a PERMANENT loss: the
		-- dedupe branch answers PurchaseGranted to every retry forever.
		return DarrelService.Award(player, def.Amount, "robux:" .. tostring(def.Amount)) == true
	end
	return false
end
```

`ProductRegistry.lua:9-13`, before:

```lua
function M.Register(productId, def)
	if productId == 0 then return end  -- placeholder: inert until the user creates real ids
	assert(PRODUCTS[productId] == nil, "duplicate product id " .. productId)
	PRODUCTS[productId] = def
end
```

After:

```lua
function M.Register(productId, def)
	if productId == 0 then return end  -- placeholder: inert until the user creates real ids
	assert(PRODUCTS[productId] == nil, "duplicate product id " .. productId)
	assert(type(def) == "table" and type(def.Type) == "string", "bad def for product " .. productId)
	assert(type(def.Amount) == "number" and def.Amount > 0 and def.Amount == def.Amount,
		"bad Amount for product " .. productId)  -- a zero/NaN amount would charge Robux and grant nothing, permanently
	PRODUCTS[productId] = def
end
```

---

## F3 — MEDIUM (double grant): the 50-entry `ReceiptLog` FIFO trim can evict a granted `PurchaseId` that Roblox later redelivers

**Where:** `ProductRegistry.lua:51` — `if #data.ReceiptLog > 50 then table.remove(data.ReceiptLog, 1) end`.

**The interleaving that dupes:**

```
1. Purchase P: granted, logged, saved. ProcessReceipt returns PurchaseGranted —
   but the server crashes at exactly that boundary (or the response to Roblox
   is otherwise lost). Roblox never records the grant; P stays pending.
   [The save DID land — darrels and P's log entry are both persisted.]
2. Roblox retries P "periodically, on next purchase, and on next join". Under
   normal load the very next retry hits the dedupe branch (line 35) and closes
   P correctly. BUT if retries keep failing to close it (e.g. the dedupe
   branch's Save at line 37 keeps failing during a DataStore outage, so every
   retry returns NotProcessedYet), P can stay pending across sessions.
3. Player makes 50 more purchases (any mix; across any number of sessions).
   Each insert at line 50 + trim at line 51 pushes P toward index 1 and
   finally evicts it.
4. Roblox retries P once more. table.find misses. Full re-grant: +Amount a
   second time. Charged once, granted twice.
```

The window requires a lost `PurchaseGranted` ack **and** 50 subsequent purchases before the retry lands — narrow, but it is precisely the whale-shaped player (many purchases) who both maximizes the eviction rate and represents the most Robux at stake. A count-capped FIFO bounds memory by evicting exactly the entries the dedupe exists to keep.

**Proposed patch:** key by `PurchaseId` with a timestamp and prune by *age* instead of count. Roblox's retry horizon is bounded in practice, so a 30-day window is both safe and smaller than 50 array entries for most players. Handles the legacy array shape in place.

`ProductRegistry.lua:34-51` (both branches), before:

```lua
	local key = tostring(info.PurchaseId)
	if table.find(data.ReceiptLog, key) then
		...
	end
	...
	table.insert(data.ReceiptLog, key)
	if #data.ReceiptLog > 50 then table.remove(data.ReceiptLog, 1) end
```

After:

```lua
	local key = tostring(info.PurchaseId)
	-- Migrate the legacy array-of-keys shape (pre-audit saves) once, in place.
	if data.ReceiptLog[1] ~= nil then
		local migrated = {}
		for _, k in ipairs(data.ReceiptLog) do migrated[k] = os.time() end
		data.ReceiptLog = migrated
	end
	if data.ReceiptLog[key] then
		...same dedupe branch...
	end
	...
	data.ReceiptLog[key] = os.time()
	-- Prune by AGE, never by count: evicting a still-pending PurchaseId is a
	-- guaranteed double grant on Roblox's redelivery. 30 days comfortably
	-- exceeds any observed retry horizon.
	local cutoff = os.time() - 30 * 86400
	for k, t in pairs(data.ReceiptLog) do
		if type(t) ~= "number" or t < cutoff then data.ReceiptLog[k] = nil end
	end
```

(If changing the stored shape is unappealing, the one-line alternative — raise 50 to 500 — shrinks the window roughly 10x for negligible storage cost; a `PurchaseId` is a short string.)

---

## F4 — MEDIUM (charged, pending indefinitely): unknown product ids return `NotProcessedYet` forever — and today *every* id is unknown

**Where:**
- `ProductRegistry.lua:44-48` — unknown id: `warn(...)` then `NotProcessedYet`.
- `ProductRegistry.lua:68` — `PACK_IDS = { 0, 0, 0, 0 }`; `Register` (line 10) drops id 0, so `PRODUCTS` is **empty** in the shipped mirror.
- Also reachable via `grant` returning `false` for an unrecognized `def.Type` (`ProductRegistry.lua:20, 49`) — same loop, same analysis.

**Behavior confirmed:** yes, Roblox retries `NotProcessedYet` indefinitely (periodically in-session, on the next purchase, and on every subsequent join). So the answer to "is that safe?" is: **it is the correct choice, and it is the *only* correct choice** — returning `PurchaseGranted` for an id the server cannot grant would eat the Robux permanently (F2's failure class). The pending receipt is fully recoverable: the moment a deploy registers the id, the next retry grants it. Nothing is lost.

What *is* wrong with the current state:

1. **The player experience during the gap is "charged, got nothing," with no bound on the gap.** Grepped the whole mirror: there is **no `PromptProductPurchase` call anywhere yet**, so today no player can actually be charged — but the buy-spins design (blocked on owner dev-product ids) is queued, and the failure mode arms itself the moment a prompt ships before, or with a typo in, the `PACK_IDS` fill-in. The parallel arrays at lines 68-69 make an off-by-one (id 3 gets amount 4's value, or an id paired with a wrong amount) easy.
2. **Nobody is watching.** A single `warn` per retry (line 46) in server logs is the only signal that real Robux is sitting in limbo.

**Proposed patch** (keep the decision, add the guard rails), `ProductRegistry.lua:44-48`, before:

```lua
	local def = PRODUCTS[info.ProductId]
	if not def then
		warn("[ProductRegistry] unknown product id " .. tostring(info.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
```

After:

```lua
	local def = PRODUCTS[info.ProductId]
	if not def then
		-- CORRECT and REQUIRED: NotProcessedYet keeps the receipt alive so a
		-- deploy that registers this id grants it retroactively on the next
		-- retry. Never return PurchaseGranted here — that eats the Robux forever.
		-- But this state means a real charge is in limbo, so make it loud:
		warn(("[ProductRegistry] UNKNOWN PRODUCT %s purchased by %d — Robux charged, grant pending until this id is Registered!")
			:format(tostring(info.ProductId), info.PlayerId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
```

Plus two process rules for whoever fills in `PACK_IDS`:

- Replace the parallel arrays with paired literals so an id and its amount cannot drift: `local PACKS = { {id = 0, amount = 80}, {id = 0, amount = 180}, ... }`.
- The (future) client prompt site must only ever `PromptProductPurchase` ids that came from the server's registry (e.g. expose `M.IsRegistered(id)` or send the pack list to the client from `PRODUCTS`), so an unregistered id can never be prompted at all.

---

## F5 — MEDIUM-LOW (session-long charged-not-granted, plus broad data loss): fast-rejoin race — `PDM.Remove` nils the *new* session's cache after its save-yield

**Where:** `PlayerDataManager.lua:749-753`:

```lua
function PlayerDataManager.Remove(player)
	releasePlot(player)
	PlayerDataManager.Save(player)          -- yields: up to 3 UpdateAsync + 1.2s of task.wait
	PlayerDataManager.cache[player.UserId] = nil   -- unconditional
end
```

`Save` can yield for several seconds during DataStore retries (lines 732-744). If the player rejoins the **same server** inside that window (crash-kick + auto-rejoin makes this realistic), `PlayerAdded -> Load` (Main.server.lua:71-72) installs the new session's data at `PlayerDataManager.lua:620` — and then the old `Remove` resumes and **nils it** (line 752).

**Receipt consequence:** every `ProcessReceipt` for the rest of that session hits `data == nil` at `ProductRegistry.lua:31-32` and returns `NotProcessedYet`. The purchase is *safe* (Roblox keeps retrying; it grants next session) but the player is charged and sees nothing for the whole session. Worse, beyond receipts: the entire session runs on a nil profile — and the eventual leave-save no-ops (`Save` line 727-728 returns false on nil cache), so all progress that session is silently lost too.

**Proposed patch**, `PlayerDataManager.lua:749-753`, before:

```lua
function PlayerDataManager.Remove(player)
	releasePlot(player)                 -- stop accepting likes BEFORE the SetAsync yield
	PlayerDataManager.Save(player)
	PlayerDataManager.cache[player.UserId] = nil
end
```

After:

```lua
function PlayerDataManager.Remove(player)
	releasePlot(player)                 -- stop accepting likes BEFORE the SetAsync yield
	local departing = PlayerDataManager.cache[player.UserId]
	PlayerDataManager.Save(player)
	-- Only clear the slot if it still holds THIS session's table. If the player
	-- rejoined during the save-yield, Load already installed a fresh profile
	-- here — nilling it would strand the new session (and its receipts) on nil.
	if PlayerDataManager.cache[player.UserId] == departing then
		PlayerDataManager.cache[player.UserId] = nil
	end
end
```

(Residual: the new session's `Load` may have read a snapshot *predating* the in-flight leave-save, briefly resurrecting pre-save state. That is a general last-writer-wins hazard outside receipt scope; for receipts it is covered because the log entry and the grant still travel together in whichever write wins.)

---

## F6 — LOW / verified safe by design: `__noSave` read-only profiles

**Where:**
- `PlayerDataManager.lua:613-619` — `__noSave = true` **only** when the DataStore *read threw*; an empty successful read is a genuine new player and saves normally.
- `ProductRegistry.lua:32` — `if not data or data.__noSave then return Enum.ProductPurchaseDecision.NotProcessedYet end`.
- `PlayerDataManager.lua:729` — `Save` refuses `__noSave` profiles, so nothing downstream can accidentally persist one.

**Analysis:** a receipt arriving for a no-save player is rejected **before** any grant or log mutation — the darrels are never credited in memory, so nothing "evaporates"; there is simply nothing to evaporate. The player is charged, sees nothing for the rest of the read-only session, and Roblox's indefinite retry grants it on the next session whose load succeeds, against the real profile. **Charged-with-delay, never lost, never duped.** This ordering (gate `__noSave` *before* `grant`, not after) is exactly right — flipping lines 32 and 49 would recreate F2's permanent-loss class. Only note: the player gets no explanation in-session; if the buy-spins UI ships, consider having the client grey out Robux buttons when the session is read-only (the server already knows).

Also verified in the same pass — the crash/leave orderings the design claims to handle, confirmed correct:

| Ordering | What happens | Verdict |
|---|---|---|
| Player leaves before receipt delivery | `GetPlayerByUserId` nil at `:30` → `NotProcessedYet` → retried next join | Safe |
| Player leaves *during* `ProcessReceipt`'s `Save` yield | Grant+log already in the shared cached table; `Remove`'s own save (Main:86 → `:751`) persists both; if the racing `Remove` nils the cache first, `Save` at `:52` returns false → `NotProcessedYet` → next-session retry hits the dedupe branch → `PurchaseGranted`, no second `Award` | Safe, no dupe |
| Server crash after grant, before save | Grant and log were memory-only and die together (`:54-57` rationale) → retry re-grants once | Safe — exactly one net grant |
| Server crash after save, before Roblox records `PurchaseGranted` | Retry finds key in loaded log (`:35`) → dedupe branch → `Save` → `PurchaseGranted`; `Award` is never re-run | Safe, no dupe (except via F3's trim) |
| Save succeeds but "grant failed" | Cannot happen in the loss direction today — grant precedes save, same table, one atomic `UpdateAsync`. The two divergence paths are F1 (darrels persisted without log → dupe) and F2 (log persisted without darrels → permanent loss) | Covered above |
| Same-session redelivery / concurrent callback for one `PurchaseId` | No yields anywhere between the `table.find` check (`:35`) and the log insert (`:50`) — `grant`/`Award`/`push`/`FireClient`/`print` never yield — so check-and-log is atomic; a second delivery either sees the key (dedupe) or arrives after a failed save in a state identical to the first attempt | Safe |
| Dedupe branch with in-memory-only log entry (first save failed, same-session retry) | `:35` finds the key, `:37` re-saves, confirms only once persisted | Correct — this branch exists for exactly this case |

---

## F7 — LOW (robustness/ops, not a loss path): retry amplification and BindToClose budget

1. **Dedupe-branch save on every retry** (`ProductRegistry.lua:37`): during a DataStore outage, each Roblox retry burns 3 `UpdateAsync` attempts plus ~1.2s of `task.wait` inside the callback. Harmless for correctness (that loop is what makes the crash orderings above safe) but it stacks with the platform's own retry cadence against an already-throttled DataStore. Optional: rate-limit to one save attempt per player per ~30s inside this branch, returning `NotProcessedYet` in between.
2. **BindToClose saves sequentially** (`Main.server.lua:89-93`): each `Save` can take multiple seconds under retry; with a full server the ~30s shutdown budget can expire mid-list, dropping final saves for later players. For receipts this is *self-consistent* (an unsaved grant dies with its unsaved log entry → retry re-grants next session, per the `:54-57` invariant) — but wrap each in `task.spawn` and count down with an event to save everyone in parallel:

```lua
game:BindToClose(function()
	local players = Players:GetPlayers()
	local remaining = #players
	if remaining == 0 then return end
	local done = Instance.new("BindableEvent")
	for _, player in ipairs(players) do
		task.spawn(function()
			PlayerDataManager.Save(player)
			remaining -= 1
			if remaining == 0 then done:Fire() end
		end)
	end
	done.Event:Wait()
end)
```

---

## Summary (by severity)

| # | Severity | Direction | One line |
|---|---|---|---|
| F1 | HIGH | Granted twice | `Award` increments the balance before throw-capable UI pushes with no `pcall` anywhere above it; a throw skips the `ReceiptLog` insert, the leave-save banks the darrels anyway, and Roblox's retry grants again — repeatable every session if the throw is deterministic. |
| F2 | HIGH (latent) | Charged, never granted, **unrecoverable** | `grant()` ignores `Award`'s outcome and `Award` fails silently, so a zero/NaN-amount registration logs and saves the receipt as granted with nothing credited — and the dedupe branch then answers `PurchaseGranted` to every retry forever. |
| F3 | MEDIUM | Granted twice | The 50-entry FIFO trim can evict a granted `PurchaseId` whose `PurchaseGranted` ack Roblox lost, after which the redelivery re-grants in full. |
| F4 | MEDIUM | Charged, pending indefinitely | Unknown ids (today: *all* ids — `PACK_IDS = {0,0,0,0}` leaves `PRODUCTS` empty) return `NotProcessedYet` forever, which is the correct and recoverable choice, but the charge sits in limbo with only a `warn` watching until someone registers the id. |
| F5 | MEDIUM-LOW | Charged, deferred a session (plus general data loss) | Rejoin during `Remove`'s save-yield gets its fresh cache nil'd, stranding the whole session (receipts included) on a nil profile. |
| F6 | LOW / safe | Charged, deferred | `__noSave` sessions reject receipts *before* any mutation — delayed to the next healthy session, never lost; ordering verified correct. |
| F7 | LOW / ops | — | Dedupe-branch save amplification under outage; sequential `BindToClose` can overrun the 30s budget (self-consistent for receipts, still worth parallelizing). |

**Bottom line:** the core save-before-confirm design and its documented invariant (`ProductRegistry.lua:54-57`) are sound — every plain crash/leave ordering resolves to exactly one grant. The two HIGH findings are the two ways code *around* the invariant can break it: an error escaping `Award` after the mutation (dupe), and a silent `Award` no-op being recorded as granted (permanent loss). Both fixes are small and should land before `PACK_IDS` is ever filled with real ids.
