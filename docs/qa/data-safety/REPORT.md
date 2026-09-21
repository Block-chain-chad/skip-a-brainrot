# Data-safety hotfix — C1 (session progress lost on crash) and C2 (new profile loads with Cash = nil)

Branch `claude/data-safety-hotfix-143003` (work for `data-safety-hotfix`), 2026-09-21. Scope: the
two player-data findings only. Investigated against the **live** place (PlaceVersion 2449, Team
Create 78783087742939), not the mirror — the mirror at the branch base still carried the
pre-SessionLock `PlayerDataManager` and no `SessionLock` at all, so the first two commits on the
branch are byte-exact syncs of the live scripts the hotfix touches (h31 hashes in the commit
messages), and the hotfix diff sits on top of those.

Files: [`SessionLock.lua`](../../../game-src/place-full/ServerScriptService/Modules/SessionLock.lua) ·
[`PlayerDataManager.lua`](../../../game-src/place-full/ServerScriptService/Modules/PlayerDataManager.lua) ·
[`Main.server.lua`](../../../game-src/place-full/ServerScriptService/Main.server.lua) ·
[`RebirthHandler.lua`](../../../game-src/place-full/ServerScriptService/Modules/RebirthHandler.lua) ·
[`ThrowHandler.lua`](../../../game-src/place-full/ServerScriptService/Modules/ThrowHandler.lua) ·
harness [`tools/studio-bridge/data-safety/`](../../../tools/studio-bridge/data-safety/README.md).

## 1. C1 — confirmed

**What the audit said:** persistent data is not periodically saved; the SessionLock heartbeat
refreshes the lock but never persists the live cache.

**What the code does (live, before the fix):**

- `PlayerDataManager.Save` is called from exactly these places: `TradeHandler`, `BoothHandler`,
  `GiftService`, `StealService`, `EggHandler`, `ProductRegistry` (Robux receipts), `TungQuest`,
  `TundraQuest`, `MichelQuest`, and `Main`'s `BindToClose`. Leaving goes through
  `PlayerDataManager.Remove → SessionLock.Release` (a full write). Nothing else writes.
- Throws and catches (`ThrowHandler`), income (`IncomeLoop`), upgrades, rock purchases, plot
  spots, sells, fusions, offerings, **rebirth**, daily rewards, wheel spins, season pass, quests,
  pets, tutorial reward: all in-memory only until the player leaves or the server shuts down.
- `SessionLock.StartHeartbeat` (every 30 s per owned profile) ran
  `local d = oldData or data; d.__session = {...}; return d` — it re-wrote **whatever was already
  in storage** with a fresh timestamp. The live cache (`data`) was only used when storage was
  empty, which cannot happen after a claim. So the heartbeat kept the lock alive and persisted
  nothing.
- **Root cause:** there was no periodic persistence path at all. A crash (or any server death
  that skips `PlayerRemoving`/`BindToClose`) lost the entire session since the last transactional
  save — for most players, everything since they joined.
- **Seen live** (read-only `GetAsync` of the owner's key from the Server DM during their own
  playtest, 2026-09-21, pre-hotfix code, two samples 51 s apart):

  | sample | uptime | stored `Cash` | stored `LastSeen` | stored `__session.t` | live leaderstat `Cash` |
  |---|---|---|---|---|---|
  | 1 | 279 s | 229,978,638,709,570,140 | 1790021965 (91 min ago) | 1790027438 (1 s ago) | 230,108,037,207,728,200 |
  | 2 | 329 s | 229,978,638,709,570,140 | 1790021965 (92 min ago) | 1790027469 (21 s ago) | 230,108,037,207,728,200 |

  The lock timestamp advanced by one heartbeat between the samples; the stored profile did not,
  and it already trailed the live one by 1.3 × 10¹⁴ cash, with a `LastSeen` from the previous
  full write 91 minutes earlier.

**Adjacent finding, inside the save/shutdown flow (fixed here because it is the same flow):**
`Main.server.lua` bound a second `BindToClose` that called `PlayerDataManager.Save` for every
player, in parallel with `PlayerDataManager`'s own `BindToClose` (`SessionLock.ReleaseAll`).
Roblox runs bound functions in parallel ("Bound functions are called in parallel and run at the
same time" — DataModel docs), `Save` unconditionally re-stamped `__session`, and `Release` cleared
it — so whichever write landed last decided whether the next server found the profile **locked
by a dead JobId** for up to 90 s. That is the "back-to-back Studio playtests keep loading a
read-only profile" note in `docs/HANDOFF-2026-08-04.md`, and it was reproducing while this was
being written: the owner's playtest at 2026-09-21 ~14:10 logged
`[PlayerDataManager] prohacks_sorry: profile held by another live server -- read-only session`
— a whole session in which nothing could save.

## 2. C2 — confirmed

**What the audit said:** `SessionLock.Claim` stores `{ __sessionNew = true }` for a brand-new
player; if that first session ends abnormally, the next load treats the marker as an existing
profile, the backfill does not recreate `Cash`, and `AddEarnings`/`GrantCash` then operate on nil.

**Exact lifecycle (live, before the fix):**

1. First join: `Claim` finds no key → writes `{ __sessionNew = true, __session = {job, t, place} }`
   (a marker, so the lock has somewhere to live) and reports `"new"`. `Load` ignores the marker and
   builds the cache from `defaultData()` — correct in memory, but **storage holds the marker**.
2. The marker is only replaced by the first full write: a transactional `Save`, or the leave
   write. The heartbeat re-writes the marker (`oldData`) with a fresh timestamp.
3. First session dies without a clean release (crash; or a `BindToClose` cut off) → storage still
   holds the marker, locked by the dead JobId.
4. Next join, after the 90 s stale window: `oldData ~= nil` → status `"ok"` → `Load` runs the
   backfill ledger over the marker. The ledger restores **58 of the 60** `defaultData()` fields;
   the two it never mentions are `Cash` and `EquippedTag` (whose default is nil anyway). Nothing
   strips `__sessionNew`. The leaderstat is guarded (`math.floor(data.Cash or 0)`), so the join
   looks normal.
5. First earning: `AddEarnings`/`GrantCash` do `data.Cash += amount` → *attempt to perform
   arithmetic (add) on nil and number*. `RebirthHandler.SendState` (`data.Cash >= cost`, every
   3 s for every player, no pcall) throws and kills that refresh loop server-wide. Every purchase
   path comparing `Cash` breaks for that player. (`IncomeLoop` pcalls per player, so income for
   *other* players survives.)

Within the 90 s window after the crash the rejoin instead gets a `"locked"` → read-only session
(existing, documented design; unchanged here).

**Root cause:** two halves. (a) A brand-new profile's first stored value was a marker, not a
profile, and only luck (a full write before the first crash) turned it into one. (b) The
load-time backfill was a hand-maintained list with no catch-all against the current schema, so
any field without a line — `Cash` — was silently left missing.

## 3. Design

### C1 — periodic persistence (`SessionLock` + `PlayerDataManager`)

Adapted to what exists: `SessionLock` was already the single choke point for every write to the
profile key, and it already ran a 30 s per-profile loop. That loop is now a **full save of the
live profile**, and the lock refresh is a side effect of it.

- **Cadence:** each owned profile is written every **30 s** (`Tuning.AutosaveEvery`; three times
  under `STALE_AFTER = 90`, the same margin the old heartbeat had). Same request count as before —
  one `UpdateAsync` per player per 30 s — but every one of them now persists progress. Worst-case
  loss on a crash: 30 s of play (6 s + one tick after a milestone).
- **Stagger:** one loop for the server, ticking every second; each tick writes the **one**
  profile that has waited longest (two or three only on a server with more players than seconds
  in the interval: `ceil(players × tick / interval)`). A profile's first periodic write is
  scheduled at a random point in the second three quarters of the interval, so a join burst does
  not become a save burst. N players cost N writes per 30 s spread across the 30 s.
- **No overlap, no reordering:** every transaction on a profile (`Claim`, `Save`, `Release`,
  periodic) goes through a per-profile turnstile (`hold`/`drop`). A trade's save waits for an
  in-flight periodic write; a leave write waits for both; a rejoin on the same server waits for
  the leave write. `IsWriting(userId)` exposes it.
- **Ownership:** `Save` refuses (`false, "unowned"`) unless this server owns the profile —
  checked before *and after* taking the turnstile — and the transaction itself still refuses if
  another live server holds the lock (`"stolen"`). `Release` drops ownership *before* its write,
  so nothing can re-stamp the lock behind the final write (teleport window, shutdown).
- **Milestones (queued, not inline):** `PlayerDataManager.RequestSave(player)` marks the profile
  due for the next tick (coalescing; still subject to the 6 s per-profile minimum gap). Wired to:
  rebirth (`RebirthHandler`), a capped-mint catch (`ThrowHandler`, after `LimitedStock.TryClaim`
  has consumed a universe-wide slot), plot-spot purchase (`TryBuySpot`, up to $50B). The inline
  transactional saves (trades, booth, gifts, steals, eggs, receipts, three quests) are unchanged —
  they already persisted correctly and their callers depend on the returned boolean.
- **Shutdown:** one `BindToClose`, in `PlayerDataManager`: stop the loop, then one final write per
  owned profile that also hands the lock back (`ReleaseAll`). `Main`'s parallel `Save`-all is
  removed with a comment explaining why. `PlayerRemoving` is unchanged in shape (`Remove →
  Release`), now with the same three-attempt retry the saves have.
- **`LastSeen`:** stamped by every full write (periodic, leave, shutdown) through
  `prepareForWrite`, the way `Save` always stamped it. The leave write had silently stopped
  stamping it when SessionLock replaced `Save` in `Remove` — see §7.
- **Failure handling:** a write that fails leaves the in-memory profile untouched (the transform
  only reads it; nothing from the DataStore is ever assigned into the cache); inline saves keep
  their 3 attempts with backoff (0.4 s × attempt); a failed periodic write is retried after 10 s
  instead of next tick; the loop leaves a floor of 10 `UpdateAsync` budget for transactional
  saves and steps aside when starved; a hung transaction is waited on for at most 15 s.
- **Tunables** live in `SessionLock.Tuning` and are read live (tests shrink them; production
  values are the ones above).

### C2 — profile normalisation (`PlayerDataManager`)

- **At the source:** `SessionLock.Claim(userId, defaults)` now stores a **real default profile**
  (`defaultData()`) for a key that does not exist, and returns it. A brand-new player's storage is
  complete from the first transaction on; no marker is ever written again.
- **On every load:** the backfill ledger moved verbatim into `normalize(data, who)` (exposed as
  `PlayerDataManager.Normalize`), followed by a catch-all: every key of `defaultData()` that is
  still `nil` gets a deep copy of its default. Only absent keys are touched — an existing value,
  including 0, is never replaced; tables are copied so profiles never share one. `Cash` is
  additionally forced numeric (a non-number is `tonumber`-ed or set to 0, with a warning). The
  ledger runs first so its smarter defaults (the `LifetimeEarned` estimate, the `WorldsVisited`
  inference from `TundraQuest`) keep precedence.
- **Legacy `__sessionNew` markers** already in storage from pre-hotfix first sessions are handled
  explicitly: after the catch-all has turned the marker into a complete default profile the
  marker key is stripped and a warning names the player. That is what the marker always meant.
- `Load(player)` is now `LoadProfile(userId, who)` (claim + normalise, pure) plus the wiring
  (cache, leaderstats, plot refresh) — so the load path is unit-testable without a `Player`.

## 4. Tests

All tests run inside Studio's Edit-mode exec VM against a **mock DataStoreService** (in-memory
JSON round trip, injectable failures/latency, write log); the module sources are loaded with
`loadstring` into an environment whose `game` hands out the fake, `Workspace` has no
`PlayerBases`, `BindToClose` is captured and `os.time` is driveable. **No production key is
touched.** The Play-mode checks that follow use the owner's real profile the way any Studio
playtest does (a claim on join, saves, a release on stop) — nothing destructive.

### 4.1 Unit runs (Studio Edit-mode exec VM, mock DataStore) — 2026-09-21

Same harness, two source variants: `live` = the byte-exact pre-hotfix scripts (commit `a2eaf34`),
`new` = the hotfix. A `live` failure is the bug; `n/a` means the test needs an API the old code
does not have (`LoadProfile`, `Tuning`, `IsWriting`).

| # | brief case | test | live (before) | new (after) |
|---|---|---|---|---|
| 1 | brand-new player joins normally | T1 | **FAIL** — `{ __sessionNew = true }` stored, no `Cash` | PASS |
| 2 | brand-new player earns Cash | T2 | n/a | PASS — periodic write lands `Cash = 250` |
| 3 | first server dies before clean release | T3 | **FAIL** — storage holds a marker with `Cash = nil` | PASS — storage holds a complete profile, locked by the dead JobId |
| 4 | rejoin after the abnormal first session | T4a / T4b / T4c | n/a | PASS — read-only inside the 90 s window; after it `Cash = 0`, every default present, `AddEarnings`/`GrantCash` work; a legacy marker loads as a new player, is logged, and the next write replaces it |
| 5 | old profile missing Cash | T5 | n/a | PASS — `Cash = 0`, Rebirths/Brainrots/LifetimeEarned kept |
| 6 | old profile missing another safe default | T6 | n/a | PASS — Pets/Settings/WorldsVisited/TundraParts/rocks restored, per-profile copies |
| 7 | normal established profile | T7 | n/a | PASS — deep-equal through storage and load |
| 8 | established profile with changed values | T8 | n/a | PASS — `Cash = 5000` stays 5000; 12 changed fields preserved, deep-equal |
| 9 | two servers, same profile | T9a / T9b / T9c | PASS / PASS / **FAIL** — a save after `Release` re-locked the profile | PASS / PASS / PASS |
| 10 | autosave while playing | T10 | **FAIL** — 35 s, 1 write, stored `Cash = nil` (the heartbeat re-wrote the marker) | PASS — live `Cash` reaches storage, lock refreshed, `LastSeen` stamped |
| 11 | player leaves during/near autosave | T11, T16 | n/a | PASS — leave write waits for the in-flight periodic write and lands last, unlocked; late save refused `unowned`; same-server rejoin queues behind the leave write |
| 12 | BindToClose after recent autosave | T12 | n/a | PASS — final write, unlocked, `LastSeen` stamped, loop stopped; a parallel `Save` (old `Main` behaviour) refused |
| 13 | DataStore write failure | T13 | n/a | PASS — `false, "error"`, warned, cache and ownership intact, storage untouched, next write lands; failing leave write reported |
| 14 | retry behaviour | T14 | n/a | PASS — one transient failure absorbed in 2 attempts; a failed periodic write retried after `RetryAfter` |
| 15 | multi-player staggered autosaves | T15, T17 | n/a | PASS — six players, one write per tick (min spacing ≥ 0.8 × tick), all covered, ≈1 write per player per interval; loop steps aside under a starved budget while inline saves still go through |

Totals: `live` PASS 2 / FAIL 4 / n/a 15 · `new` **PASS 21 / FAIL 0**. Harness and exact exec
snippet: `tools/studio-bridge/data-safety/README.md`.

### 4.2 Not done — needs the owner

The hotfix is **not in the live place**. Applying it to the Team Create scripts
(`ServerScriptService.Modules.PlayerDataManager`, `.SessionLock`, `.RebirthHandler`,
`.ThrowHandler`, `ServerScriptService.Main`) was blocked by this session's permission mode
("production deploy"), so the two checks that need the live scripts changed are still open:

- **Play-mode smoke:** join on the owner's profile, watch the stored key's `LastSeen` /
  `__session.t` / `Cash` follow the live leaderstat every ~30 s (the read-only `GetAsync`
  probe used for the table in §1), and confirm no `[SessionLock]` / `[PlayerDataManager]`
  warnings in the server log.
- **Stop → Play:** after a Stop, the stored key must read `__session = nil`, and an immediate
  Play must load without `profile held by another live server`.

Ready to run once approved: a pre-edit backup into
`ServerStorage.AuditBackups.PreDataSafety_2026_09_21` and a push that pulls the five files from
the worktree bridge and **aborts if any live script has drifted** from the hashes the hotfix was
built on (PDM `7f09e949`, SessionLock `562e70d5`, Main `aaeb3c06`, RebirthHandler `3a9cd541`,
ThrowHandler `d0f17b4b`) — the onboarding lane has queued edits to three of them and is waiting
on this push, so the order matters.

## 5. Files changed

- `game-src/place-full/ServerScriptService/Modules/SessionLock.lua` — turnstile, ownership-gated
  `Save`, `Claim(userId, defaults)`, `Release` retries, `MarkDue`, `StartAutosave` (replaces
  `StartHeartbeat`), `ReleaseAll` stops the loop, `Tuning`, `IsWriting`.
- `game-src/place-full/ServerScriptService/Modules/PlayerDataManager.lua` — `normalize` (ledger
  + catch-all + marker handling), `LoadProfile`, `Load` split, `prepareForWrite`, `RequestSave`,
  `Remove`/`BindToClose` through `prepareForWrite`, `StartAutosave`, milestone in `TryBuySpot`;
  `Normalize`/`DefaultData` exposed for tests.
- `game-src/place-full/ServerScriptService/Main.server.lua` — parallel `BindToClose` `Save`-all
  removed (comment left in place).
- `game-src/place-full/ServerScriptService/Modules/RebirthHandler.lua` — queued milestone save
  after a rebirth.
- `game-src/place-full/ServerScriptService/Modules/ThrowHandler.lua` — queued milestone save
  after a capped (`LimitedStock`) mint lands in the inventory; the universe-wide slot is already
  spent by then, so a crash before the next periodic write would have destroyed a limited item.
- `tools/studio-bridge/data-safety/{harness.lua, stage.py, README.md, .gitignore}` — the tests.
- `docs/qa/data-safety/REPORT.md` — this report.

## 6. Compatibility

- Old profiles: only absent keys are filled; every existing value survives (T7/T8 deep-compare a
  full profile through storage and load). Migrations (renames, discovery backfill, estimates) run
  exactly as before, before the catch-all.
- Session locks: same key, same `__session` shape, same 90 s stale rule, same `"locked"`
  read-only behaviour; `TeleportService`'s `Release → TeleportAsync → Claim` flow is unchanged and
  now protected against a late save re-locking the profile (T9c).
- Purchases/receipts: `ProductRegistry`'s `Save` → `PurchaseGranted` contract is unchanged
  (`PlayerDataManager.Save` still returns `true` only when the write landed; it now also returns a
  reason on `false`, which existing callers ignore).
- Trading/booth/gifting/steal/eggs/quests: unchanged call sites; their saves now wait for an
  in-flight periodic write (≤ one DataStore round trip) instead of racing it.
- Brainrots, currencies, quests, rebirth, inventory, pets: no schema change; `Cash`-nil sessions
  can no longer occur.
- Offline earnings: not touched, but its input changes — see §7.
- Studio: `Stop → Play` no longer produces a read-only session, because shutdown now ends with an
  unlocked profile (T12) — the ~90 s wait between playtests noted in the handoff is gone.

## 7. Things noticed, not fixed (outside scope)

Reported only because each one sits on the load/save path this hotfix changed:

- **`LastSeen` after a plain leave.** Before SessionLock, `Remove` called `Save`, which stamps
  `LastSeen`; since SessionLock, `Remove` called `Release` with the raw cache and `LastSeen` was
  only stamped by transactional saves and teleports. So a player's offline-earnings window was
  measured from their last *trade/receipt/quest* save, not from when they left (zero, i.e. no
  payout, for a player who never had one). The hotfix stamps `LastSeen` on every full write
  (periodic, leave, shutdown) because that is the field's documented meaning ("unix time of last
  save") and the periodic write *is* a save. Consequence for `OfflineEarningsHandler` (not
  touched): `elapsed` now measures from the last autosave/leave, so payouts get smaller for
  players who used to be paid from a stale timestamp and start appearing for players who never
  triggered a transactional save. Flagging it because it is a visible economy change; it is the
  correct one, but the owner should know.
- **Rejoin inside the 90 s stale window after a crash is still a read-only session** (existing
  design). With the profile now complete in storage this is only an inconvenience, not a broken
  profile; the window could be shortened, but that is a tuning decision, not a defect.
- **`ProductRegistry` receipt processed during a teleport window** (after `Release`, before the
  player has actually left): `Save` now refuses (`"unowned"`), so `ProcessReceipt` answers
  `NotProcessedYet` and Roblox retries at the destination — which is the safe answer (before, the
  save would have re-locked the profile under the destination server). Noted as a behaviour
  change, believed correct.
- **`PlayerDataManager` still holds an unused `dataStore` handle** (`GetDataStore` at the top);
  every read/write goes through SessionLock. Harmless; left alone.
- Everything in the brief's do-not-touch list (tutorial rock, rarity curve, teleport bypass,
  World 1, UI overlap, ReceiptLog capacity, dev allowlist, performance) was not looked at.


## 8. Diff summary

Commits on `claude/data-safety-hotfix-143003`, on top of `86c6cf5` (ui-foundation):

| commit | what |
|---|---|
| `a2eaf34` | chore(mirror): byte-exact live `PlayerDataManager` / `SessionLock` / `Main` (h31 `7f09e949` / `562e70d5` / `aaeb3c06`, PlaceVersion 2449) — the base the hotfix is built on |
| `fb62704` | chore(mirror): byte-exact live `RebirthHandler` (`3a9cd541`); `ThrowHandler` at HEAD already matched live (`d0f17b4b`) |
| `ba9621c` | **fix(data): periodic autosave + profile normalisation** — the hotfix |
| `8acf65d` | test(data): the mock-DataStore harness |
| (this) | docs(qa): this report |

Hotfix diff (`a2eaf34..ba9621c`, game-src only), ignoring the one-tab de-indent of the
migration ledger moved into `normalize` (`git diff -w`):

```
 Main.server.lua               |  12 +-
 Modules/PlayerDataManager.lua | 131 ++++++++++---
 Modules/RebirthHandler.lua    |  11 +-
 Modules/SessionLock.lua       | 210 +++++++++++++++++----
 Modules/ThrowHandler.lua      |   7 +
 5 files changed, 299 insertions(+), 72 deletions(-)      (raw: 411 / 184)
```

Nothing under Trading World, World 1, eggs, UI, balancing, models, tutorial or any other
gameplay system was touched; `RebirthHandler` and `ThrowHandler` each gained one guarded
`RequestSave` call and nothing else.
