# First 10 minutes — Phase 1 inspection (2026-09-21)

Read-only trace of a truly fresh profile (`PlayerDataManager.defaultData()`: Cash 0,
OwnedRocks {Pebble}, 12 pads, TutorialDone false, LastSeen 0, DailyStreak 0) through
the live scripts. Every number below is read from the code or computed from the live
config modules in Studio (`RarityCurve.For("Valley")`, `SellValue`, `BrainrotConfig`).

Live-vs-mirror check (2026-09-21, Studio Play session, `#Source`): TutorialClient,
GameHUDClient, ClientMain, MerchantClient, OfflineEarningsClient, Main, QuestHandler,
DailyRewardHandler, ShopHandler, ThrowHandler, RockConfig, UpgradeConfig, SellValue,
BagConfig, RarityCurve, BrainrotConfig are byte-count identical to this branch's mirror.
QuestBarClient (20374 live / 19762 mirror), QuestTrackerClient (33814 / 59456),
LuckHUDClient, BackpackPanel and MerchantDialog carry the UI round 3/4 work that lives
on `ui-foundation`, not on this branch — anything touching those must start from the
live Source.

## World geometry that sets the clock

| thing | position | distance from spawn |
|---|---|---|
| SpawnLocation | (0, 33, -180) | — |
| nearest free valley plots (Plot3 / Plot4) | (-42, 3.5, -84) / (40, 3.5, -83) | ~105 studs, on the way to the dock |
| ThrowZone (the dock) | (0, 16, 21), 60x26x18 | ~200 studs (13 s walk at 16 studs/s) |
| Rocco ShopStall / Marco SellStall | (24, 8, -303) / (-24, 8, -302) | ~125 studs behind spawn (lodge) |
| Enzo UpgradeStall | (56, 8, -260) | lodge |
| Elder Tung | (-95, 10, 72) | ~270 studs; ~340 from the lodge |

The server refuses a throw until the player owns a plot (`ThrowHandler`: "Claim a base
first!"); the throw button reads GET A PLOT FIRST and, when tapped without one,
teleports the player to a free plot and claims it (`TeleportTo("OpenPlot")`).

## Timeline of a fresh join (current)

### 0–30 s
1. **Profile loads** (`Main` PlayerAdded → Load → PushUpdate). Cash 0.
2. **t+~1.0 s: DAILY CALENDAR auto-opens** as a full HUD panel with backdrop blur
   (`GameHUDClient` join sequence, "THE DAILY CALENDAR IS THE FIRST THING A PLAYER SEES",
   owner decision 2026-08-07; no rail tile exists; auto-claim on dismiss). Day 1 = $500.
3. **t+~1.5 s: TUTORIAL card glides in** bottom-left (`TutorialClient`, MainUI
   DisplayOrder 5 — UNDER the GameHUD panel/blur at 7). Card = "WELCOME TO SKIP A
   BRAINROT" + a 2-paragraph body + LET'S GO (20 s AFK auto-advance).
4. **Goals bar** (right edge, `QuestBarClient`) appears with the first Goals-board entry:
   **"Catch an Uncommon+ brainrot 0/2"** — list order wins the 0% tie. With Pebble
   (25 studs, Uncommon band starts at 100) this is *unreachable*; after the first catch
   it reads 1/2 (50 %) and stays the lead goal until the third catch.
5. Always-on chrome: nav rail (Bag, Goals, Worlds, Shop, Settings, Rebirth), currency
   cluster (cash + gems), teleport tabs (SKIP / SHOPS / PLOT), luck chip, HIDE UI,
   sprint. Quest tracker (NPC quests) is hidden with 0 entries (round-3 version).
   No offline-earnings card (LastSeen 0). Toast channel: "Base claimed!" later.
6. Player closes/claims the calendar (auto-claim on close: +$500) → sees the tutorial
   intro → LET'S GO → **STEP 1/9 CLAIM YOUR BASE** (beacon + ground chevrons to the
   nearest free plot). Walk ~105 studs, touch the platform → "Base claimed!" toast.

### 30 s–2 min
7. **STEP 2 SKIP A ROCK** — beacon on the dock, ~100 more studs. HOLD TO SKIP →
   release. Pebble: distance 25 (±2 variance, ×1.1 perfect), 2 skips, 1.15 s flight.
   Every throw catches (no miss chance); 100 % Common at < 100 studs.
   `StoneThrown` → step 3 shows for the flight; `ThrowResult` → **CatchPop** (0.9 s,
   top-centre: NEW BRAINROT! / name / COMMON / "1 in N of its tier"). Distance is NOT
   shown anywhere in the default reveal (only the legacy ResultFrame prints it, and only
   for rarities whose reveal is switched off).
8. **STEP 4 PUT IT ON YOUR BASE** — copy says "Open your Bag and tap the brainrot";
   the walk-over green EquipBestPad at the plot entrance also does it (confirm panel →
   EquipBest). Walk back ~100 studs.
9. **STEP 5 COLLECT YOUR CASH** — stand in the campfire ring; one Common banks
   ~1.3 $/s, so this pays a few dollars.

### 2–5 min
10. **STEP 6 SELL YOUR BRAINROTS** — Marco's stall in the lodge (~220 studs from the
    plot). A Common sells for 900 × cps ≈ **$1,152 average** (`SellValue.MULTIPLIER`
    = 900 since the 2026-09-03 mechanics pass). Selling the ONLY brainrot they own.
11. **STEP 7 BUY BETTER ROCKS** — gated on a real purchase (`OwnedRocks` signature
    change). Rocco's cheapest rock, Rivertumble (`SmoothStone`), costs **$12,000**.
    The player holds ≈ $500 (daily) + $1,152 (sale) + pennies ≈ **$1,700**.
    `Main`'s comment still says "the cheapest paid rock is 300" — the ladder was
    retuned in Studio after that (400 → 12,000 in the 2026-09-19 resync) and the
    tutorial was never revisited. **CONFIRMED: the reported ~$12,000 dead end.**
    After 90 s the card grows a "Skip This Step" button; that is the only way past.
12. **STEP 8 GRAB UPGRADES** — Enzo; completes on opening the stall (prompt trigger).
    Cheapest upgrade $3,000 (Strong Arm +5 % distance: 25 → 26 studs, useless here).
13. **STEP 9 TALK TO ELDER TUNG** — ~340 studs away. His quest = hand over
    5 Epic + 5 Legendary + 2 Mythic (Epic needs 360 studs; the first rock that reaches
    Uncommon costs $23,900). The "first quest" the tutorial hands over is many hours
    away.
14. **COMPLETE / YOU'RE SET** + $3,000 (`TUTORIAL_REWARD`).

### 5–10 min (post-tutorial, current)
The player has 1 Pebble, ~$4,500, one placed Common, a Goals bar pointing at an
unreachable goal, and a tracked NPC quest they cannot progress. Nothing tells them
that spare Commons sell for ~$1,150 each, that 12 placed Commons earn ~15 $/s, or
what the next rock does.

## Economy facts (measured)

- Common pool: 30 names, weighted avg **1.28 $/s**, avg sell **$1,152**. Uncommon avg
  7.65 $/s.
- Throw cycle with Pebble ≈ 3–4 s (charge + 1.15 s flight + 0.9 s pop; throw unlocks
  on `ThrowResult`). A player can catch 15–20 Commons/min; bag cap 75.
- Rock ladder at full power / perfect (×1.1), valley curve, rock's own luck:
  - Pebble 25 → 100 % Common. **Rivertumble $12,000 → 70/77 studs → 100 % Common**
    (its 1.15× luck changes nothing below 100 studs).
  - Sevenskip $23,900 → 110/121 → Uncommon **4.1 % / 7.5 %**.
  - Boulderfang $287,000 → 160/176 → Uncommon 16–20 %.
  - Nightglass $502,000 → 215/237 → Uncommon 29–32 %, Rare 2 %.
- Goals board (one-time rewards): uncommon $900 (unreachable early), **own5 $2,400**,
  cash25k $3,600, dupe3 $4,900, rare $6,000, **pads10 "Fill 12 plot spots" $10,500**.
- Daily: day 1 $500, day 2 $1,000. Tutorial completion $3,000.
- Upgrades: Strong Arm $3,000 (+5 %/lvl), Lucky Charm $4,000, Golden Touch $5,000.
- Passive income for a full fresh base (12 Commons) ≈ 15 $/s ≈ $920/min, collected
  only by standing in the campfire or walking over the brainrot.

## Findings (what breaks the first 10 minutes)

1. **Popup wall at join**: daily calendar (modal + blur) and the tutorial card arrive
   within 0.5 s of each other; the calendar covers the card.
2. **Tutorial dead end**: STEP 7 demands a $12,000 purchase with ~$1,700 in hand;
   "Skip This Step" is the designed workaround. The 08-20 rework priced the step at
   $300.
3. **Reading before playing**: a 2-paragraph intro + LET'S GO, then a walk to a plot,
   then a walk to the dock — first throw lands at ~45–60 s for a player who reads.
4. **No distance feedback**: the reveal never prints the distance; "farther = rarer"
   is only in the intro paragraph.
5. **Wrong first goal**: the Goals bar leads with "Catch an Uncommon+" (impossible on
   Pebble; 4 % on the $23,900 rock).
6. **Wrong first quest**: Elder Tung's Epic/Legendary/Mythic hand-over is the
   tutorial's finale and gets auto-tracked.
7. **Advanced stops in the mandatory ladder**: Enzo's upgrades (nothing useful under
   $3,000+ at this distance) and Tung.
8. **Rock shop says nothing a new player can use**: "Up to 70m • 1.15x luck" — no
   tier information, no reason.
9. **Selling — the actual early-game income (≈ $1,150 per throw) — is taught with a
   single sale and never connected to buying rocks**; placing is taught as "open the
   Bag and tap" although the walk-over pad exists.
10. **Rejoin mid-tutorial** restarts from the intro (no step persistence); steps gated
    on session flags (`caught`, `sold`, `bought`) must be redone even when the profile
    already proves them.
11. **Ladder shape** (out of scope, flagged): the first $36K of rocks buys no rarity
    change at all; the first Uncommon chance is 4–7 % at $23,900. Rivertumble's only
    visible payoff is 2 → 4 skips and the 60-stud tracking camera.
