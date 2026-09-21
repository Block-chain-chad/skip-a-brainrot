# Onboarding — first 10 minutes — design (2026-09-21)

Owner brief: "SKIP ROCKS FOR BRAINROTS — FIRST 10 MINUTES OVERHAUL". Inspection:
`docs/onboarding/PHASE1-INSPECTION.md`. Decisions taken by the owner on 2026-09-21:
Rivertumble → $2,000; auto-claim a base at first join; the Daily Calendar waits for
the tutorial to end; a Studio-only profile-key suffix for fresh-profile testing.

Out of scope and untouched: Trading World, World 1 environment, egg hatch and catch
reveal presentation (CatchPop / RevealRouter), DataStore/save architecture (the seam
below is a Studio-only key suffix, inert live), brainrot model construction, the rest
of the economy.

## 1. Goal

A brand-new player, within ten minutes and mostly by playing, learns: how to skip a
rock; why distance matters; how brainrots are earned; what rarity means; where
brainrots are stored; why better rocks matter; what their next objective is.

Target flow (guideline, event-driven, never timer-driven):

| clock | beat |
|---|---|
| 0:00 | spawn, base already claimed, one card: SKIP YOUR FIRST ROCK |
| 0:15–0:30 | first throw |
| < 1:00 | first brainrot, "it's in your Bag" |
| 1–2 min | four more skips (core loop), first goal READY |
| ~1:30 | claim $2,400 in GOALS (broader goal list seen) |
| ~2:00 | open the Bag once |
| 2–4 min | place on the base (walk-over pad), collect at the campfire |
| 3–5 min | buy Rivertumble ($2,000) |
| 4–6 min | YOU'RE SET (+$3,000), calendar opens, next target stated |
| 6–10 min | fill 12 pads (goal pads10 $10,500), sell spares, save for Sevenskip |

## 2. Server — `ServerScriptService.Main`

- **Auto-claim at first join.** After `PlayerDataManager.Load` + `PushUpdate`, if
  `data.TutorialDone ~= true` and `PlayerDataManager.GetPlot(player, "Valley")` is nil,
  pick the unclaimed `Workspace.PlayerBases` model with `World == "Valley"` nearest the
  `SpawnLocation` and call `PlayerDataManager.ClaimPlotFor(player, plot)`. No teleport.
  If no plot is free, do nothing (the client falls back to a CLAIM step). `ClaimPlotFor`
  already fires the "Base claimed!" toast; that toast is suppressed for this path (the
  tutorial's first card says it instead) by passing a `quiet` flag — a new optional
  third argument on `ClaimPlotFor`, default false, so every other caller is unchanged.
- **Stale comment** above `TUTORIAL_REWARD` corrected (cheapest paid rock = $2,000).
  Reward stays $3,000 (owner's number).
- `TutorialComplete` handling unchanged (one-way flag, reward only on `completed`).

## 3. Economy — `ReplicatedStorage.Modules.RockConfig`

- `SmoothStone` (Rivertumble) `Price = 12000` → `2000`. Nothing else in the ladder
  moves. Header gets a dated note: first rung repriced for onboarding (owner
  2026-09-21); Sevenskip is the first tier unlock and the post-tutorial target.

## 4. Goals — `ServerScriptService.Modules.QuestHandler` + `QuestBarClient`

- Tier goals (`uncommon`, `rare`, `epic`, `legendary`, `mythic`, `secret`, `god`):
  `cur` becomes binary — `met and target or 0`. A Common is no longer "1 of 2" toward
  an Uncommon, so the Goals bar's nearest-to-complete pick leads with `own5` (1/5)
  after the first catch instead of an unreachable goal. Rows in the Goals panel show
  0/2 until met (they already only claim on `met`).
- `QuestBarClient` (LIVE source, round-3 version — pull from Studio first): when the
  bar reads READY!, tapping it opens the Goals panel
  (`player:SetAttribute("HudPanelRequest", "goals")`). Dismiss glyph unchanged.

## 5. Rock shop copy — `StarterPlayer.StarterPlayerScripts.MerchantClient`

Rock card info line (was `"Up to 70m  •  1.15x luck"`):

```
Skips up to 70m  •  1.15x luck
Catches COMMON  •  Uncommon from 100m
```

`reach` = the highest `RarityConfig` tier with `MinDistance <= rock.MaxDistance`;
`next` = the tier after it (omit the second clause at the top of the ladder).
Tundra shelf uses that world's ladder via `WorldProgression.Resolve(world).Rarities`.
Nothing else on the card changes (price pill, EQUIP/EQUIPPED/LOCKED states, viewport).

## 6. Calendar sequencing — `GameHUDClient` join sequence

- The join push (`DailyState` → `openPanel("daily")`) is held while
  `player:GetAttribute("OnboardingActive") == true`. `TutorialClient` sets that
  attribute to true the moment it decides to run (join snapshot `TutorialDone == false`)
  and to false on finish AND on skip. The held push replays when the attribute drops:
  the handler keeps the last `DailyState` payload and re-enters the open path.
- Safety: a 10-minute ceiling from join clears the hold regardless. The existing
  30 s `releaseHandoff` (offline card) is untouched — a fresh profile has no offline
  card anyway, and a returning player's sequence is byte-for-byte the same as today.
- Order of the two scripts is not guaranteed, so `TutorialClient` sets
  `OnboardingActive` BEFORE its 1.5 s start delay, and `GameHUDClient` reads the
  attribute at push time (a late-connecting listener still sees a set attribute).

## 7. The tutorial — `StarterPlayer.StarterPlayerScripts.TutorialClient` (rewrite)

Same file, same card shell (glide, beacon, chevrons, progress track, NoPolish rules,
listener teardown), new ladder and new gating.

### 7.1 Ladder

Numbered steps as shown to the player (`STEP n / 8`). Each row: title / body /
cue / target / done-when. Copy is short; no paragraph anywhere.

0. (fallback, only when the server could not auto-claim) **CLAIM A BASE** —
   "Walk onto a free camp. It's yours." — beacon: nearest free valley plot —
   done: `myPlot() ~= nil`. Not numbered; the progress track ignores it.
1. **SKIP YOUR FIRST ROCK** — "Follow the arrows to the dock. HOLD the button, let go
   to skip." — beacon: `GameWorld.ThrowZone` — done: first `StoneThrown` for me.
2. **IT'S IN YOUR BAG** — "Every catch goes to your Bag. Skip again — catch 5."
   — cue: `"Last skip: 25m → COMMON. Uncommon starts at 100m."` (distance from the
   `StoneThrown` payload, tier from `ThrowResult`; band edge read from `RarityConfig`)
   — beacon: dock — Bag tile ring (see 7.3) for 4 s on entry — done: snapshot
   `#Brainrots >= 5` (`DataUpdated` or the join snapshot).
   The card advances on `ThrowResult` + 1.2 s so the reveal pop (0.9 s) is never
   covered by a card change; the card sits bottom-left, the pop top-centre.
3. **GOAL COMPLETE!** — "Open GOALS and claim your $2,400." — no world beacon; ring
   on the Goals rail tile — done: `QuestState` shows `own5` `Claimed == true`.
   (If the goal is somehow already claimed on join, the step is skipped.)
4. **OPEN YOUR BAG** — "Your brainrots are collected here. Take a look." — ring on
   the Bag tile — done: `player:GetAttribute("HudOpenPanel") == "backpack"` observed
   at any time after the step shows.
5. **PUT THEM ON YOUR BASE** — "Walk onto the green pad at your camp and confirm.
   Placed brainrots earn cash." — beacon: `myPlot().EquipBestPad` (falls back to the
   plot pivot) — done: any snapshot entry with `PadIndex`.
6. **COLLECT YOUR CASH** — "Stand in the campfire to collect what they earned." —
   beacon: `myPlot().Campfire` — done: `CampfireCollected`.
7. **BUY A BETTER ROCK** — "Rocco's Rivertumble skips 3x farther. $2,000 — you've
   earned it." — beacon: `ShopStall.PromptPart` — done: snapshot `OwnedRocks` has any
   id other than `Pebble`.
8. **YOU'RE SET** (finish beat, 6 s) — "Skip, catch, place, collect — that's the loop.
   Next: fill all 12 pads, sell spares to Marco, save $23.9K for Sevenskip — it
   reaches UNCOMMON." — `TutorialComplete:FireServer(true)`.

No "Skip This Step". "Skip Tutorial" stays on every numbered card (ends the ladder,
`TutorialComplete(false)`, no reward, `OnboardingActive` cleared).

### 7.2 Gating rules

- Every `done` reads durable state where it exists (join snapshot + `DataUpdated`:
  brainrot count, `PadIndex`, `OwnedRocks`; `QuestState`: claimed goals; plot
  attributes). Session-only events are used only for the two beats that have no
  durable trace (first throw, campfire collect).
- On start, the ladder fast-forwards past every step whose `done` is already true
  (rejoin resume). The card then shows the first open step.
- The 0.4 s poll keeps beacons on live targets and catches any `done` the listeners
  missed; it never advances on a timer.
- Rail rings: found by name (`GameHUD.*.NavRail.bagItem` / `goalsItem`), a stroked
  ring frame parented to the tile, pulsing via RenderStepped like the beacon; removed
  on step change. If the tile cannot be found within 5 s the ring is skipped (the
  copy still names the tile).

### 7.3 Post-tutorial hint (session one-shot)

After finish (not after skip), the first time a `DataUpdated` snapshot shows every
unlocked pad filled AND at least one unplaced brainrot, show one `UIKit.Toast`:
"Base full — spare brainrots sell for cash at Marco's stall (SHOPS)". Once per session.

### 7.4 Phone

The card keeps its 340×184 desktop box. On `Platform.IsPhone` it becomes 280×150,
body 12px, and sits bottom-left ABOVE the phone rail row (y from `HudLayout` rail
reserve + 8), never under `MainUI.ThrowFrame` (bottom-centre) — verified in the
iPhone 16 simulator. Short phones (`Platform.IsShortPhone()`) get the same box at
top-centre under the tab bar.

## 8. Test seam — `ServerScriptService.Modules.SessionLock`

`key(userId)` returns `KEY_PREFIX .. userId .. suffix` where `suffix` is
`ServerStorage:GetAttribute("ProfileKeySuffix")` when `RunService:IsStudio()` and the
attribute is a non-empty string; `""` otherwise. Live servers never read it. Used only
to run fresh profiles (`_qa1`, `_qa2`, …) and rejoin tests in Studio.

## 9. Files

Studio (source of truth) + mirror `game-src/place-full/...`:
`StarterPlayer/StarterPlayerScripts/TutorialClient.client.lua` (rewrite),
`.../GameHUDClient.client.lua` (join sequence only), `.../MerchantClient.client.lua`
(rock card info), `.../QuestBarClient.client.lua` (READY tap; from live source),
`ServerScriptService/Main.server.lua` (auto-claim, comment),
`ServerScriptService/Modules/QuestHandler.lua` (tier goal `cur`),
`ServerScriptService/Modules/PlayerDataManager.lua` (`ClaimPlotFor` quiet flag),
`ServerScriptService/Modules/SessionLock.lua` (seam),
`ReplicatedStorage/Modules/RockConfig.lua` (price).
Backups: `ServerStorage.AuditBackups.PreOnboarding_2026_09_21.<Name>_pre`.

## 10. Testing (fresh profile via the seam, Studio Play)

1. Join: no calendar; one card within 2 s; base claimed (toast suppressed); Goals bar
   shows own5 0/5 (not Uncommon); tracker hidden.
2. First throw within 30 s from a cold walk; catch pop uncovered; card → IT'S IN YOUR
   BAG with the distance cue.
3. Five catches → GOAL COMPLETE; Goals tile ring; claim → +$2,400; bar moves on.
4. Bag open advances; pad confirm places; campfire collects; Rocco sells Rivertumble
   at $2,000 with the new copy and the purchase advances; YOU'RE SET +$3,000; calendar
   opens after the finish beat and auto-claims on close.
5. Skip Tutorial mid-ladder: calendar opens, TutorialDone true, no reward.
6. Leave mid-ladder (after 5 catches, before the goal claim) → rejoin same suffix →
   ladder resumes at GOAL COMPLETE, base auto-claimed again.
7. Phone (iPhone 16 simulator): card clear of the rail row, tab bar, throw frame;
   HudAudit 0 overlaps involving the card.
8. Returning profile (real account, TutorialDone true): calendar at join exactly as
   before; no tutorial; no auto-claim.
