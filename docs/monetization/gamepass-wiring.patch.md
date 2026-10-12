# Gamepass wiring patch — folding GamepassService multipliers into gameplay

**Status: PROPOSED — no game file has been edited.** Every edit below is written against the
live mirror under `game-src\place-full\` as of 2026-08-04. Line numbers are the current file's
and will shift if anything lands above them; the `before` blocks are exact, so match on text.

Design rules used throughout:

- **Fail-neutral.** Every `GamepassService` accessor returns `1` (or `false`) when the ownership
  cache is cold, when all `GamepassId`s are still `0`, or before `Init()` runs. So every edit here
  is safe to land *today*, ahead of real pass ids — exactly like the `PetHandler.IncomeMult`
  seam it copies (`PetConfig.ENABLED=false` ⇒ neutral 1x).
- **Inline, matching the PetHandler seam style.** Multipliers are appended inline in the existing
  product expressions (`* GamepassService.CashMult(player)`), not hoisted into new locals.
- **Init order is already fine.** `Main.server.lua` requires GamepassService at :41 and calls
  `GamepassService.Init()` at :146, *after* `IncomeLoop.Init()` (:100) and `ThrowHandler.Init()`
  (:95) — harmless, because the accessors are fail-neutral pre-Init and the income loop /
  throw remote only evaluate them per-tick / per-throw, by which time the cache is warm.
- **No circular requires.** GamepassService requires only `ReplicatedStorage.Modules.GamepassConfig`,
  so IncomeLoop / ThrowHandler requiring it is safe.

Multiplier → seam map (summary):

| Effect | Pass(es) | Seam |
|---|---|---|
| CashMult | Cash2x ×2, VIP ×1.5 | IncomeLoop :119 (accrual), :139 (displayed rate), OfflineEarningsHandler :47 + EnsureCached join guard (Edit 1.4) |
| LuckMult | Luck2x ×2, VIP ×1.5 | ThrowHandler :670 `accessLuck` (the tier-roll input) |
| PowerMult | SuperArm ×2 | ThrowHandler :641 `distance` (inside the clamp) |
| ChargeMult | FastCharge ×1.75 | client-owned — GamepassService publishes a Player attribute; ClientMain :1158 consumes it |
| AutoCollect | AutoCollect | IncomeLoop campfire block :169-176 (`onFire` override) — **not** the :143 walk-up path |
| VIP (tag) | VIP | no gameplay seam; its CashMult/LuckMult ride the two rows above. Tag/chat badge = separate UI task |

---

## 0. New requires

### Edit 0.1 — IncomeLoop.lua : 11 (after the PetHandler require)

File: `game-src\place-full\ServerScriptService\Modules\IncomeLoop.lua`

Before:
```lua
local PetHandler = require(ServerScriptService.Modules.PetHandler)
```

After:
```lua
local PetHandler = require(ServerScriptService.Modules.PetHandler)
local GamepassService = require(ServerScriptService.Modules.GamepassService)
```

Rationale: IncomeLoop needs `CashMult` and `HasFlag`; GamepassService has no back-reference, so no require cycle.

### Edit 0.2 — ThrowHandler.lua : 29 (after the PetHandler require)

File: `game-src\place-full\ServerScriptService\Modules\ThrowHandler.lua`

Before:
```lua
local PetHandler = require(ServerScriptService.Modules.PetHandler)
```

After:
```lua
local PetHandler = require(ServerScriptService.Modules.PetHandler)
local GamepassService = require(ServerScriptService.Modules.GamepassService)
```

Rationale: ThrowHandler needs `LuckMult` and `PowerMult`.

---

## 1. CashMult — Cash2x (×2) and VIP (×1.5), stacked as a product

### Edit 1.1 — IncomeLoop.lua : 119 (accrual)

File: `game-src\place-full\ServerScriptService\Modules\IncomeLoop.lua`

Before:
```lua
							e.Pending = (e.Pending or 0) + (cashPerSecondByName[e.Name] or 0) * Mutations.Mult(e.Mutation) * rebirthMult * upMult * PetHandler.IncomeMult(player) * dt
```

After:
```lua
							e.Pending = (e.Pending or 0) + (cashPerSecondByName[e.Name] or 0) * Mutations.Mult(e.Mutation) * rebirthMult * upMult * PetHandler.IncomeMult(player) * GamepassService.CashMult(player) * dt
```

Rationale: this is the single source of truth for live income; the gamepass folds in beside the pet mult, ahead of `dt`.

### Edit 1.2 — IncomeLoop.lua : 139 (displayed rate) — **includes the pre-existing drift fix**

> **KNOWN DRIFT, fixed here:** :139 already disagrees with :119 — the accrual applies
> `PetHandler.IncomeMult(player)` and the billboard's cash/sec line does not, so any player with
> an income pet sees a rate slower than what they actually earn. This edit adds **both** the
> missing pet mult and the new gamepass mult so display and accrual use the identical product.
> These two lines have drifted once already; keep their factor lists character-for-character
> parallel (everything except `* dt`) in any future edit.

Before:
```lua
									local cps = (cashPerSecondByName[e.Name] or 0) * Mutations.Mult(e.Mutation) * rebirthMult * upMult
```

After:
```lua
									local cps = (cashPerSecondByName[e.Name] or 0) * Mutations.Mult(e.Mutation) * rebirthMult * upMult * PetHandler.IncomeMult(player) * GamepassService.CashMult(player)
```

Rationale: the billboard rate must be the same product the accrual uses, or the HUD lies about earnings.

### Edit 1.3 — OfflineEarningsHandler.lua : 47 (offline payout accrual) — recommended

File: `game-src\place-full\ServerScriptService\Modules\OfflineEarningsHandler.lua`

This is a **third accrual site** the task grep surfaced: offline pay rebuilds the same cps
product. "Double all brainrot income" (the Cash2x description) should cover it, or a Cash2x
owner's offline popup pays half the rate their billboards advertise.

Requires adding at :8-14 (with the other requires):
```lua
local GamepassService = require(ServerScriptService.Modules.GamepassService)
```

Before:
```lua
			cps += (cashPerSecondByName[e.Name] or 0) * Mutations.Mult(e.Mutation) * rebirthMult * upMult
```

After:
```lua
			cps += (cashPerSecondByName[e.Name] or 0) * Mutations.Mult(e.Mutation) * rebirthMult * upMult * GamepassService.CashMult(player)
```

Rationale: offline income is still "brainrot income"; without this the pass silently excludes it.

> Note this line deliberately does NOT get `PetHandler.IncomeMult` — see Drift appendix item D2
> for why that omission is flagged but left as a separate decision.

### Edit 1.4 — GamepassService.EnsureCached: closing the join race (required by Edit 1.3)

**Why Edit 1.3 needs this.** Offline pay is computed exactly once per session, on the join path:
`Main.server.lua:71-75` runs `PlayerDataManager.Load(player)` then `OfflineEarningsHandler.OnJoin(player)`
synchronously in one PlayerAdded handler. GamepassService's own PlayerAdded handler `task.spawn`s
`refresh`, which makes up to **6 sequential `UserOwnsGamePassAsync` web calls** and only writes
`owned[player]` after the last one resolves (`GamepassService.lua:34-42`). One DataStore `GetAsync`
racing six web calls loses on most joins — so without this edit, a Cash2x/VIP buyer would plausibly
get 1x offline pay on **every** join, forever, not "once". The income loop and throw path don't
care (they re-read every tick/throw and self-heal within seconds); the one-shot join payout does.

**Why a blocking `EnsureCached` and not an incremental cache write.** The alternative — have
`refresh` publish `owned[player] = set` first and fill `set[g.Key] = true` inside the loop — only
converts a *nil* cache into an *empty-then-partial* one: `CashMult` still returns 1 (or a partial
product) until the final web call lands, so the join race survives, just harder to see. Blocking
at the single consumer that is one-shot AND already on a yielding path closes it completely, costs
the hot paths nothing, and fails neutral (returns `false` after timeout ⇒ 1x pay, never an error).

#### Edit 1.4a — GamepassService.lua : 29-30 (session flag)

File: `game-src\place-full\ServerScriptService\Modules\GamepassService.lua`

Before:
```lua
-- owned[player] = { [Key] = true }. Session cache; cleared on leave.
local owned = {}
```

After:
```lua
-- owned[player] = { [Key] = true }. Session cache; cleared on leave.
local owned = {}
-- cached[player] = true once this session's FIRST refresh has fully resolved.
-- Read by EnsureCached so one-shot join-time consumers never see a cold cache.
local cached = {}
```

Rationale: `owned[player] == nil` cannot distinguish "not refreshed yet" from "cleared"; a dedicated flag can.

> The matching `cached[player] = true` publish lands inside **Edit 4.1's** after-block — the two
> edits touch the same `refresh` tail, and an exact-match applier must see one edit per region.

#### Edit 1.4b — GamepassService.lua : 78-80 (the blocking accessor)

Before:
```lua
-- Open the Robux purchase prompt (call from a future shop UI / remote). No-op
-- for a pass that has not been created yet.
function GamepassService.Prompt(player, key)
```

After:
```lua
-- Block until this session's first ownership refresh has resolved (true), or the
-- player left / the timeout passed (false). For ONE-SHOT join-time consumers only
-- (offline pay) -- it YIELDS, so never call it from the income loop or a throw.
function GamepassService.EnsureCached(player, timeout)
	local deadline = os.clock() + (timeout or 10)
	while not cached[player] and player.Parent and os.clock() < deadline do
		task.wait(0.1)
	end
	return cached[player] == true
end

-- Open the Robux purchase prompt (call from a future shop UI / remote). No-op
-- for a pass that has not been created yet.
function GamepassService.Prompt(player, key)
```

Rationale: polls the flag rather than restructuring refresh; timeout + `player.Parent` guard mean it can never hang the join path past 10s or leak a wait on a leaver.

#### Edit 1.4c — GamepassService.lua : 90 (cleanup)

Before:
```lua
	Players.PlayerRemoving:Connect(function(p) owned[p] = nil end)
```

After:
```lua
	Players.PlayerRemoving:Connect(function(p) owned[p] = nil; cached[p] = nil end)
```

Rationale: the flag must die with the session or a rejoin would trust a stale "warm" verdict.

#### Edit 1.4d — OfflineEarningsHandler.lua : 40-42 (the call site)

File: `game-src\place-full\ServerScriptService\Modules\OfflineEarningsHandler.lua`

Before:
```lua
	local counted = math.min(elapsed, capSeconds)

	local rebirthMult = RebirthConfig.IncomeMult(data.Rebirths)
```

After:
```lua
	local counted = math.min(elapsed, capSeconds)

	-- The ownership cache is rebuilt by up to 6 sequential web calls racing this
	-- join's single DataStore read, and the payout below is computed exactly once
	-- per session -- so block until the cache is warm. This path already yields
	-- (profile load); worst case is the 10s timeout, then fail-neutral 1x.
	GamepassService.EnsureCached(player)

	local rebirthMult = RebirthConfig.IncomeMult(data.Rebirths)
```

Rationale: the wait lives at the one consumer that needs it, so every other GamepassService caller stays non-blocking.

---

## 2. LuckMult — Luck2x (×2) and VIP (×1.5)

**Where the roll actually happens:** the tier roll is `curve.RollTierIndex(distance, accessLuck)`
at ThrowHandler :692. Its luck input is the `accessLuck` product at :670-676 — that is the roll
site, so that is the seam. (RarityCurve / RarityRoll are pure math; do not touch them.)

**Decision — accessLuck, not the mutation line.** ThrowHandler splits luck into two systems:
`accessLuck` (WHICH brainrot you catch, :670) and the mutation boost (`weatherMut * clamp(...) *
PetHandler.LuckMult(player)`, :786, which decides Golden/Diamond). The pass copy reads "Double
your rarity luck on throws", which is unambiguously tier access — so it lands in `accessLuck`
next to offerings, wheel boost and placed-pet luck, NOT in the mutation product. (Rebirth luck
is deliberately excluded from accessLuck so a permanent grind can't run away with tier access;
gamepass luck is a bounded one-time purchase, ×3 worst case, same class as offerings — it belongs
in access.)

### Edit 2.1 — ThrowHandler.lua : 670-676

File: `game-src\place-full\ServerScriptService\Modules\ThrowHandler.lua`

Before:
```lua
		local accessLuck = rock.Luck
			* UpgradeConfig.Mult(data.Upgrades, "Luck")
			* OfferingConfig.LuckMult(data.Offerings)
			* PlayerDataManager.BoostMult(data, "Luck")
			* petLuck
			* (perfect and PERFECT_LUCK_MULT or 1)
			* (isAuto and AUTO_LUCK_MULT or 1)
```

After:
```lua
		local accessLuck = rock.Luck
			* UpgradeConfig.Mult(data.Upgrades, "Luck")
			* OfferingConfig.LuckMult(data.Offerings)
			* PlayerDataManager.BoostMult(data, "Luck")
			* petLuck
			* GamepassService.LuckMult(player)                -- Luck2x / VIP gamepasses
			* (perfect and PERFECT_LUCK_MULT or 1)
			* (isAuto and AUTO_LUCK_MULT or 1)
```

Rationale: accessLuck is the exact value `RollTierIndex` consumes at :692, so one factor here covers every tier roll (pity and apex routing included).

> **Display consequence:** LuckHUDClient mirrors this product and will now under-report — see
> Section 6 and Drift appendix.

---

## 3. PowerMult — SuperArm (×2)

**Seam:** the `distance` product at ThrowHandler :641-645. Deliberately **inside the
`math.clamp(..., 0, MAX_TOTAL_DISTANCE)`**, like every other power source (upgrades, rebirth,
wheel boost): the 900-stud cap and therefore the tier gates still hold, and the auto penalty at
:649-651 stays *outside* the clamp exactly as its long comment demands — SuperArm on auto still
tops out at 720 studs and cannot reach Secret/God.

### Edit 3.1 — ThrowHandler.lua : 641-645

File: `game-src\place-full\ServerScriptService\Modules\ThrowHandler.lua`

Before:
```lua
		local distance = math.clamp(power * rock.MaxDistance
			* UpgradeConfig.Mult(data.Upgrades, "Power")
			* RebirthConfig.PowerMult(data.Rebirths)          -- prestige throw power
			* PlayerDataManager.BoostMult(data, "Power")      -- timed daily-wheel boost
			* (perfect and PERFECT_DISTANCE_MULT or 1) + variance, 0, MAX_TOTAL_DISTANCE)
```

After:
```lua
		local distance = math.clamp(power * rock.MaxDistance
			* UpgradeConfig.Mult(data.Upgrades, "Power")
			* RebirthConfig.PowerMult(data.Rebirths)          -- prestige throw power
			* PlayerDataManager.BoostMult(data, "Power")      -- timed daily-wheel boost
			* GamepassService.PowerMult(player)               -- Super Arm gamepass
			* (perfect and PERFECT_DISTANCE_MULT or 1) + variance, 0, MAX_TOTAL_DISTANCE)
```

Rationale: joins the other permanent power sources inside the clamp, so the 900 cap, tier gates and the post-clamp auto tax all keep their current meaning.

---

## 4. ChargeMult — FastCharge (×1.75)

**There is no server seam for this in ThrowHandler — and that is correct.** The server receives
a finished `power` in `[0,1]` (:597-599); charge *speed* lives entirely client-side in
ClientMain's charge block (`chargePeriod` rolled at :1158, `power = clamp(t / chargePeriod, 0, 1)`
at :1507-1508). So the wiring is: GamepassService **publishes ownership as a Player attribute**,
and ClientMain divides its fill period by it. Two properties make this safe:

- A client spoofing the attribute only changes how fast *its own bar fills* — power is clamped
  server-side and the server-issued sweet-spot band is unchanged, so nothing trust-bearing moves.
- The per-charge anti-macro re-roll (`CYCLE_MIN_MULT..CYCLE_MAX_MULT`) is preserved: dividing the
  whole rolled period by a constant keeps the randomization ratio intact.
- FastCharge does **not** raise throw rate: the server's `THROW_COOLDOWN` (1.05s, :527) and the
  one-stone-in-flight lock still govern cadence. The pass only reaches high power sooner.

### Edit 4.1 — GamepassService.lua : 42 (end of `refresh`)

File: `game-src\place-full\ServerScriptService\Modules\GamepassService.lua`

Before:
```lua
	owned[player] = set
end
```

After:
```lua
	owned[player] = set
	cached[player] = true   -- first full refresh resolved; see EnsureCached (Edit 1.4)
	-- publish client-consumed effects (charge speed is client-owned; luck/power feed the HUD)
	player:SetAttribute("GpChargeMult", GamepassService.ChargeMult(player))
	player:SetAttribute("GpLuckMult", GamepassService.LuckMult(player))
	player:SetAttribute("GpPowerMult", GamepassService.PowerMult(player))
end
```

Rationale: the client cannot require a ServerScriptService module, so ownership crosses the boundary the same way WeatherLuck does — as replicated attributes. (`GamepassService.X` is resolvable here because the table local is declared above `refresh` and the call happens at runtime, post-load; the `multOf` local is NOT in scope at this point in the file.) This after-block also carries Edit 1.4's `cached[player] = true` line — one edit per file region, so an exact-match applier never sees two edits fighting over the same `before` text.

### Edit 4.2 — GamepassService.lua : 97-99 (mid-session purchase)

Before:
```lua
		if g then
			owned[player] = owned[player] or {}
			owned[player][g.Key] = true
		end
```

After:
```lua
		if g then
			owned[player] = owned[player] or {}
			owned[player][g.Key] = true
			player:SetAttribute("GpChargeMult", GamepassService.ChargeMult(player))
			player:SetAttribute("GpLuckMult", GamepassService.LuckMult(player))
			player:SetAttribute("GpPowerMult", GamepassService.PowerMult(player))
		end
```

Rationale: a pass bought mid-session must take effect on the very next charge, not the next join.

### Edit 4.3 — ClientMain.client.lua : 1156-1158 (inside `startCharge`)

File: `game-src\place-full\StarterPlayer\StarterPlayerScripts\ClientMain.client.lua`

Before:
```lua
	-- roll this charge's own bar speed (see CYCLE_MIN_MULT above)
	chargeStart = os.clock()
	chargePeriod = CYCLE_SECONDS * (CYCLE_MIN_MULT + math.random() * (CYCLE_MAX_MULT - CYCLE_MIN_MULT))
```

After:
```lua
	-- roll this charge's own bar speed (see CYCLE_MIN_MULT above). Fast Charge gamepass
	-- divides the fill period (server-published attribute; nil/1 when not owned).
	chargeStart = os.clock()
	chargePeriod = CYCLE_SECONDS * (CYCLE_MIN_MULT + math.random() * (CYCLE_MAX_MULT - CYCLE_MIN_MULT))
		/ (player:GetAttribute("GpChargeMult") or 1)
```

Rationale: a shorter `chargePeriod` is exactly "the bar fills 1.75x faster"; reading the attribute per charge means a mid-session purchase applies on the next wind-up with no listener needed. (`player` is ClientMain's existing LocalPlayer local — see :1132.)

> **Playtest note (product observation, not a bug):** the sweet-spot band is fixed-width in
> POWER space (`BAND_WIDTH = 0.07`), so a 1.75x faster sweep shrinks the band's TIME window
> 1.75x — from roughly 77ms to ~44ms at the nominal 1.1s period. FastCharge buyers charge
> faster but land perfects *harder*. That may be acceptable tension (speed vs precision), but
> it is a paid pass making one skill check stiffer — watch it in playtest and, if it reads as
> a downgrade, widen `BAND_WIDTH` client+server by the same factor for pass holders.

---

## 5. AutoCollect flag

**Chosen seam: the campfire block, not the :143 walk-up path.** Two candidates existed:

- *Rejected:* `WALKUP_COLLECT` at IncomeLoop :143 (`if WALKUP_COLLECT and hrp and e.Pending >= 1
  and (mPos - hrp.Position).Magnitude <= BRAINROT_RANGE`). Even flag-gated per player, it is still
  proximity-gated to 7 studs *per brainrot model* — the player would have to walk their pads,
  which is not "auto". It also reverses USER DECISION U1 ("the campfire is now the collector").
- *Chosen:* force `onFire` in the campfire block. One line buys the entire existing machine —
  the `COLLECT_INTERVAL` 2s gulp cadence, `collectAll`, the Darrel "Collect" notify, the
  `CampfireCollected` client cue with its `accum`/cooldown batching, and the `Banked` attribute
  bookkeeping — with zero new code paths to break.

### Edit 5.1 — IncomeLoop.lua : 169-176 (after the cylinder test)

File: `game-src\place-full\ServerScriptService\Modules\IncomeLoop.lua`

Before:
```lua
						local onFire = false
						if hrp then
							local dx = hrp.Position.X - campfire.Position.X
							local dz = hrp.Position.Z - campfire.Position.Z
							local dy = math.abs(hrp.Position.Y - campfire.Position.Y)
							onFire = (dx * dx + dz * dz) <= CAMPFIRE_RADIUS * CAMPFIRE_RADIUS
								and dy <= CAMPFIRE_Y_BAND
						end
```

After:
```lua
						local onFire = false
						if hrp then
							local dx = hrp.Position.X - campfire.Position.X
							local dz = hrp.Position.Z - campfire.Position.Z
							local dy = math.abs(hrp.Position.Y - campfire.Position.Y)
							onFire = (dx * dx + dz * dz) <= CAMPFIRE_RADIUS * CAMPFIRE_RADIUS
								and dy <= CAMPFIRE_Y_BAND
						end
						-- Auto Collect gamepass: the campfire gulps for its owner wherever they
						-- stand -- same cadence, cue and Banked bookkeeping as standing in it.
						if not onFire and GamepassService.HasFlag(player, "AutoCollect") then
							onFire = true
						end
```

Rationale: reuses every downstream behavior (interval, cue batching, Darrel notify, Banked writes) instead of building a parallel collect path that could drift from the campfire one.

Behavioral notes (intended, but worth a playtest look):

1. The `CampfireCollected` cue toast will fire (throttled to one per 2s gulp, as today) while the
   player is anywhere on the map. That IS the pass's feedback ("your campfire collected $N"); if
   it reads odd, the cue client script can grow a quieter variant later — no server change.
2. The campfire's money-pile visual (`Banked` attribute) will sit at ~0 for AutoCollect owners,
   because the hoard is swept every 2s. Inherent to auto-collect; not a bug.
3. `cs.inside` latches true permanently for owners, so the `fresh` first-contact flourish fires
   once per session — fine.
4. Collection still requires the plot + campfire to exist and only sweeps **placed** brainrots
   (`e.PadIndex`), same as standing in the fire; no hrp dependency was added.
5. **Playtest note:** because no hrp/character is required, AutoCollect holders keep collecting
   while dead or respawning (the override runs on every tick the plot exists). Almost certainly
   fine — it's a 2s-cadence sweep of their own pending cash — but it is a behavior the campfire
   never had, so eyeball it once in Play.

---

## 6. Display parity for the new multipliers (recommended follow-up, display-only)

The Luck HUD mirrors ThrowHandler's formulas by construction ("keep the two in sync or this panel
starts lying" — LuckHUDClient :24). Edits 2.1 and 3.1 make it lie for pass owners unless it learns
the attributes published in Edit 4.1. These edits are optional to ship the passes, but shipping
without them re-creates exactly the :119/:139 class of drift, one layer up.

### Edit 6.1 — LuckHUDClient.client.lua : 223 (rarity luck product)

File: `game-src\place-full\StarterPlayer\StarterPlayerScripts\LuckHUDClient.client.lua`

Before:
```lua
	local rarityLuck = rock.Luck * upgradeLuck * offeringLuck * petLuck
```

After:
```lua
	local gpLuck = player:GetAttribute("GpLuckMult") or 1     -- Luck2x / VIP gamepasses (server-set)
	local rarityLuck = rock.Luck * upgradeLuck * offeringLuck * petLuck * gpLuck
```

Rationale: keeps the HUD's headline equal to the server's accessLuck (Edit 2.1) for pass owners.

### Edit 6.2 — LuckHUDClient.client.lua : 247-249 (breakdown row, after the pet row)

Before:
```lua
	if petLuck > 1.0001 then
		addRow("Pets on base", ("\u{00D7}%.2f"):format(petLuck), CF.pine1, CF.pine1)
	end
```

After:
```lua
	if petLuck > 1.0001 then
		addRow("Pets on base", ("\u{00D7}%.2f"):format(petLuck), CF.pine1, CF.pine1)
	end
	if gpLuck > 1.0001 then
		addRow("Gamepasses", ("\u{00D7}%.2f"):format(gpLuck), CF.amber1, CF.amber1)
	end
```

Rationale: a paid multiplier that never appears in the breakdown looks broken to the buyer. (The insertion is exactly the three-line `if gpLuck` block after the existing `end`; nothing else changes.)

### Edit 6.3 — LuckHUDClient.client.lua : 277-282 (best-throw distance)

Before:
```lua
	local bestDist = math.min(
		rock.MaxDistance
			* UpgradeConfig.Mult(state.Upgrades, "Power")
			* RebirthConfig.PowerMult(state.Rebirths or 0)
			* PERFECT_DISTANCE_MULT,
		MAX_TOTAL_DISTANCE)
```

After:
```lua
	local bestDist = math.min(
		rock.MaxDistance
			* UpgradeConfig.Mult(state.Upgrades, "Power")
			* RebirthConfig.PowerMult(state.Rebirths or 0)
			* (player:GetAttribute("GpPowerMult") or 1)   -- Super Arm gamepass (server-set)
			* PERFECT_DISTANCE_MULT,
		MAX_TOTAL_DISTANCE)
```

Rationale: keeps the "BEST THROW" odds table aligned with what Edit 3.1 makes the server actually roll.

For live refresh, add attribute listeners next to the Weather ones at :323-327:

```lua
player:GetAttributeChangedSignal("GpLuckMult"):Connect(refresh)
player:GetAttributeChangedSignal("GpPowerMult"):Connect(refresh)
```

Rationale: a mid-session purchase should move the HUD the moment GamepassService republishes (Edit 4.2).

---

## 7. Not wired here (out of scope, on purpose)

- **VIP tag / chat badge** — the `VIP = true` flag has no gameplay seam; its CashMult 1.5 and
  LuckMult 1.5 are already carried by Edits 1.x and 2.1 (stacking multiplicatively with Cash2x /
  Luck2x per GamepassConfig's "STACKED (product)" contract, so Cash2x+VIP = ×3 cash). The visible
  tag is a UI/overhead-nameplate task with no multiplier involved.
- **Shop UI / purchase prompts** — `GamepassService.Prompt(player, key)` exists and is unused;
  a buy surface is a separate feature. Nothing in this patch prompts anyone.
- **RarityCurve / RarityRoll / Mutations** — deliberately untouched; all luck folds in at the
  single `accessLuck` input (Edit 2.1), so the shared curve math stays identical on client & server.

---

## Appendix — display/accrual drift observed while finding the seams

- **D1 (known, FIXED by Edit 1.2):** `IncomeLoop.lua:139` (billboard cash/sec) omits
  `PetHandler.IncomeMult(player)` that `:119` (accrual) applies — income-pet owners see an
  understated rate.
- **D2 (new finding, NOT patched):** `OfflineEarningsHandler.lua:47` rebuilds the income product
  as `cps * mutation * rebirthMult * upMult` — it too omits `PetHandler.IncomeMult`. Possibly
  intentional (follower pets arguably "aren't out" while offline) but nothing in either file says
  so; either fold it in or leave a comment declaring offline pay pet-free, so the next reader
  doesn't call it a bug. Edit 1.3 adds the gamepass mult there but deliberately leaves this
  decision open.
- **D3 (new finding, NOT patched — pre-existing):** `LuckHUDClient.client.lua:223` omits the
  timed daily-wheel Luck boost (`PlayerDataManager.BoostMult(data, "Luck")`) that the server
  applies at `ThrowHandler.lua:673`, and the file's own formula comment at `:38` documents the
  product without it. During a wheel Luck boost the HUD under-reports rarity luck.
- **D4 (new finding, NOT patched — pre-existing):** same file, `bestDist` at `:277-282` omits the
  wheel Power boost (`PlayerDataManager.BoostMult(data, "Power")`, server: `ThrowHandler.lua:644`),
  so the "BEST THROW" odds table is pessimistic while a Power boost is running.
- **D5 (would be created by this patch if Section 6 is skipped):** Edits 2.1/3.1 add gamepass
  luck/power server-side; LuckHUDClient cannot see them without the attributes from Edit 4.1 and
  the Section 6 edits. Ship Sections 2-4 and 6 together.

D3/D4 are one-line fixes in the same style as Section 6 but touch a *pre-existing* tuning
decision (BoostMult is client-invisible today), so they are reported, not patched — decide once,
then mirror the whole product.

