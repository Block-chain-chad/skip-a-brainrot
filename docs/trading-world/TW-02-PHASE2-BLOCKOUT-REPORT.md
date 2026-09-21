# TW-02 — Phase 2 blockout + Phase 3 walk test (Riverside Trading Settlement, greybox v3)

**Date:** 2026-09-20 · **Lane:** TW-02 · **Status:** BLOCKOUT BUILT IN PLACE, WALK-TESTED — **layout APPROVED by the owner 2026-09-20** (keep the current scale; Phase 5 architecture may start) · **Studio:** PlaceId `78783087742939`, PlaceVersion 2449 at the start of the window; nothing published; the old island and the Grand Exchange are one call from restoration (below).

Owner decisions applied (2026-09-20): **D1 build in place** · **D2 keep one Guardian as a relic** (a fallen colossus head in Collector's Row; the six statues retired with the island) · **D3 18 stalls** · defaults: D4 currency boundary stays with ECON-01, D5 Eternal Skip kept (retargeted into the bay), D6 `TradeZone` over the Fork Square + Guild House arcade.

| Field | Value |
|---|---|
| GENERATOR | `ServerStorage.TradingWorldBuild.SettlementGenerator` (ModuleScript, 50,690 B, h31 `39ac62ad`, VERSION 3), mirrored byte-exact at `game-src/place-full/ServerStorage/TradingWorldBuild/SettlementGenerator.lua`; `_MANIFEST.txt` updated. `loadstring(Source)()` → `RetireLegacy()` (once) · `ClearAll()` · `BuildAll()` · `Contracts()` · `Stats()`. Idempotent: `ClearAll()` removes only sections carrying attribute `TW2 = true`. |
| OUTPUT | `GameWorld.TradingWorld` (Folder): `Land, Cliffs, ArrivalDock, MarketEntrance, LowerMarket, Waterfront, UpperMarket, OldBridge, CollectorsRow, Stairs, Roads, Barrier, NpcSpots` + the kept `EternalSkip`. `GameWorld.TradingCenter` (Folder): `Booths` (18 modules) + `TradeZone`. |
| COUNTS | **456 BaseParts**, 76 Models, 18 SurfaceGuis (the stall signs), 0 BillboardGuis, 0 WedgeParts, 4 Neon (the kept skipping stone), **1 light, 1 script** (both the kept `EternalSkip`), 0 emitters. bbox X 7830–8191 · Y 1992–2078 · Z 7796–8362; BoundsGuard margins W 599 / E 530 / N 363 / S 421 / top 32. |
| CONTRACTS | `Contracts()` → **OK 18/18 stalls**, `BoothIndex` 1…18 contiguous, one `TradeZone`, ground under `TRADE_POS` = `DockDeck` at y 2002.8 (the old pad's datum), `HubPortal` 24.2 studs from `TRADE_POS`. Play boot: `BoothHandler` adopted 18 stands, 18 `Claim Stand` prompts live. |
| SCRIPT EDITS | `SkipLoop` constants only (`CX, CZ, R = 8150, 7878, 40`, `WATER_Y = 2000.0`; h31 `73841159` → `d41bed3b`, 1,615 B unchanged) — mirrored. No economy, UI or shared file touched. |

## 1. Backups and rollback (state before anything was removed)

- `ServerStorage.TradingWorldBackups_2026_09_20`: `GE_TradingWorld_GE` (1,263 desc) and `GE_TradingCenter_GE` (158) — clones of TW-01's Grand Exchange staging build, verified equal before the live containers were destroyed; `Legacy_TradingWorld` (902 desc, 14 children: the whole cove island incl. `CoveDressing` with the six Guardians and `CoveDriver`, now inert) and `Legacy_TradingCenter` (122 desc: gazebo + `Booth7`–`Booth12` + the old `TradeZone`) — **moved, not deleted**.
- `ServerStorage.TradingWorldBackups_2026_09_19` (TW-01): `TradingWorld_Original` / `TradingCenter_Original` / `HubPortal_Original` still fingerprint-match (`Rollback.Verify()` run before the retirement: `0876cade` / `0250b41b` / `d5dc7a59`), plus `Rollback.Restore()`.
- `HubPortal` keeps its original pivot in attribute `TW2_OriginalPivot`; attributes untouched.
- **To put the old island back:** `G.ClearAll()`, re-parent the two `Legacy_*` folders' children into `GameWorld.TradingWorld` / `TradingCenter`, `HubPortal:PivotTo(HubPortal:GetAttribute("TW2_OriginalPivot"))`, revert the four `SkipLoop` constants — or run the 2026-09-19 `Rollback.Restore()`.
- Fresh `.rbxl` saved after layout approval (File → Download a Copy, 2026-09-20 20:04): `C:\Users\m\Coding\skip-a-brainrot-backups\SkipRocks_78783087742939_pre-TW02-arch_2026-09-20.rbxl` (11,124,387 B, `<roblox!` binary, sha256 `5098e27d2efb393f79c6e8fed481ef5a663b0baf653d9cd05c1f6f5b18678f8a`) — captures the approved greybox v3 with the legacy island and the GE clones in ServerStorage.

## 2. The layout (design frame: origin = ground under `TRADE_POS` (8000, 2002.4, 7818); x = west (+X), z = north (+Z))

Levels: dock +0.4 · Lower Market 0 · quay −0.8 · Upper Market +12 (back terrace +14) · causeway / bridge deck / abutment square +8 · Collector's Row −1.4 · water −2.4 (Terrain).

| District | What is there (greybox masses) | Stalls |
|---|---|---|
| **Arrival Dock** (z −22…24) | 28 × 40 plank deck under `TRADE_POS`, six posts, a side jetty with a moored boat, the **Boathouse** (open-fronted, east of the deck) holding the re-pivoted `HubPortal` — the way home is 24 studs to the right of arrival, off the axis, in view. Route B starts here: a boardwalk on posts west along the shore. | — |
| **Market Entrance** (z 24…62) | Harbourmaster (2 storeys, upper floor overhangs the street and the boardwalk, hanging sign) and Customs House (1½ storeys, hip roof, awning) pinch the way north to 20 studs. No overhead beam — the gap keeps the bridge tower visible. | #1 under the Customs awning |
| **Lower Market Street** (z 38…262) | 215-stud street with two bends (centreline x 0 → 12 → 4 → −12; width 12–24), 9 buildings a side with different heights/roofs: B3's upper floors bridge alley A2; B4's balcony; B5's external stair; the courtyard (40 × 42, tree, alley A4); the Gem Broker's kiosk; the **Fork Square** (36 × 26, well) closed by the **Guild House** whose open arcade is the covered market corner. | #2 window, #3 under balcony, #4 under stair, #5 window, #6 courtyard awning, #7 opening |
| **Waterfront** (quay x 70…92 / 86, z 24…400) | Quay 22 studs wide, stepping in to 16 at z 210; seven sheds/warehouses are the *backs* of the west block; alleys A1/A2/A3 and lane L1 (under an arch) connect it to the street; bay pier with a boat, river-mouth pier, three water stairs, the Tanners' Yard (hidden yard off A3), the hoist warehouse. Ends at the **Bridge Steps** (24-long stair up the abutment's west face). The fishing pocket under the causeway (dead end, Angler). | #12 in the boat shed, #13 lean-to, #14 under S4's balcony, #15 S6 window |
| **Upper Market** (terrace +12, x −142…−54, z 230…372) | Reached by a two-flight stair up the terrace wall from the Fork Square (rise 7 + 5). Edge street along the parapet with the **Overlook** (cantilevered, view west over the yard to the water), U1/U2 (balcony over the street)/Curio House (arcade, Curator), upper lane to the back terrace (+14, U4), then down 4 studs onto the **causeway** — a raised road on a wall, warehouses' upper fronts on one side, parapet over the river quay on the other. | #8 opening, #9 Curio arcade, #10 back-terrace awning, #11 warehouse upper front on the causeway |
| **Old Bridge** (x 4…18, z 366…456) | Abutment square (+8), 14-wide deck on a central pier with a cutwater, **two shop cabins cantilevered over the water** (their counters open onto the deck), parapets, the **gate tower** on the north abutment (road passage through it, lantern to +76 = 2078 world) — the landmark, visible from the dock's vanishing point, the Upper street, the whole quay and the river mouth. Then the north stub: embankment, ramp, and a **closed gate** (the road north is shut — a future world hook). | #16 east cabin, #17 west cabin |
| **Collector's Row** (north bank, −1.4) | From the stub a stair drops west, turns back, and passes **under the bridge road through a vault** into a 9-wide sunken lane between old buildings; dead-ends under a timber overhang at the **relic** — the half-buried colossus head. | #18 RN2's opening |

Other: cliffs close the east, the gorge (the river comes out of rock; `GorgeEnd` walls it), and the north; invisible barriers close the bay (x 134) and the south; `TradeZone` 52 × 22 × 46 over the Fork Square + arcade; 11 `NpcSpot_*` posts (Harbourmaster, Ferryman, GemBroker, AttendantFork, TraderA/B, Curator, AttendantBridge, Angler, BridgeWarden, Collector) with `Role / Tier / Note` attributes — visible teal posts in the greybox.

**Stall module** (one definition, 18 placements): `Counter` 8 × 3 × 2.4 (`StandPrompt` inside, reach 8 / hold 0.3 / "Market Stand") · `Display1/2/3` on the counter top (level; the server's cube lands at +4.9, head height) · `SignBoard` a 4.6 × 1.5 hanging sign at +7 (SurfaceGui › TextLabel authored **"CLAIM STALL"**; the server rewrites it to `"X'S STAND"` / `"AVAILABLE STAND"` on claim/release — the wording lives in `BoothHandler` (ECON-01) or is restyled by the Phase 4 client layer) · a dark `Niche` flush with the wall so the stall reads as an opening · shell extras per placement (awning + posts, window lintel + jambs, nothing for balcony/understair/arcade/bridge shells). Attributes `District`, `Shell` on each model.

## 3. Aerial check (Phase 2 gate)

Captures from (8010, 2560, 7900) → (8010, 2002, 8100) and low oblique from (8130, 2300, 7700): an elongated block of varied roofs along the water, a river cut with a bridge and tower, a smaller north bank, cliffs on the east, a stepped quay on the west with a pier, the dock at the south. **No circle, no plaza, no hub, no central structure.** The one machine-looking trait — a straight rectangular shoreline — was broken up in v2 (shore apron only in front of the dock, boardwalk on posts, quay stepping in at z 210, stepped north bank); the rest of the shoreline's character is Phase 5 work (quay walls, rocks, a beach south-east).

## 4. Phase 3 walk test (Play, one character, WalkSpeed 20 on this account — 16 is the default)

Route A, `Humanoid:MoveTo` waypoint by waypoint, real physics: dock → gate 1.9 s → three street legs 7.4 s → Fork 10.8 s → stair A/landing/stair B (all climbed, y 2013.3 → 2018.3) 13.8 s → edge street north 18.5 s → causeway 21.9 s → square 23.2 s → deck north end 25.6 s → stub 26.4 s → stair down to the Row 27.8 s → the relic **32.2 s**. No stuck, no jump needed, every ramp ≤ 25°. Route B (boardwalk → quay → Bridge Steps → bridge → Row) is ~690 studs, the same order.

| Question | Answer from the walk |
|---|---|
| FROM SPAWN: do I know where to go? | Yes — the gate is the only opening; the dock is water on three sides; the way home is visibly a boathouse to the right. |
| AFTER 10 s: trading activity seen? | Stall #1 is 22 studs from arrival (1.9 s), #2 and #5 within 5 s. |
| AFTER 20 s: another route/district found? | Alley A4 → courtyard at 5 s, alley A1 → quay at 4 s, the Fork at 10.8 s (three ways out). Route B is visible from the dock (the boardwalk). |
| FROM MARKET STREET: orient without seeing everything? | Yes — the street bends twice; the bridge tower shows above the far rooflines; the Upper Market's parapet/balconies above right; water glimpsed down the alleys left. |
| FROM UPPER MARKET: depth? | Overlook: parapet (foreground) → yard tree and roofs (midground) → bay and horizon (background); edge street north: the tower and cabins over the causeway. |
| AT OLD BRIDGE: the landmark? | The tower with its passage and lantern, the cabins, water both sides, the gorge cliffs and the north bank — yes. |

**Findings fixed in v2/v3 during the test:** the street's second bend put the road centreline inside B10's face (stall #7's counter became the path → moved the centreline to x +4 at z 190) · an open cavity under the north stub ramp visible from inside the vault (stepped fill added) · Collector's Row widened 8 → 9 for the third-person camera · the tower's lantern raised (+68 → +76) and B5 lowered (22 → 18) so the tower actually shows from the dock · quay narrowed 34 → 22/16.

**Open (owner call):** the crossing is **32 s at WalkSpeed 20 (≈ 40 s at the default 16)** against the brief's 45–60 s. The generator makes a stretch cheap (one more street block + a longer edge street and Row ≈ +5–6 s), but every added stud thins the density the brief also asks for. Recommendation: keep this scale, since the routes already wind and the sightlines are controlled; revisit after Phase 5 if the dressed world still feels small.

## 5. Not built yet (by design — later phases)

No lights, props, vegetation beyond three tree masses, textures, windows/doors, real stair treads, water dressing, quay walls, boats beyond blockout masses; the `BoothDressingClient` (D4 (c) presentation) and `NpcSpot` invisibility come with Phase 4/5; NPC rigs are NPC-01's. The stall counters are 3 studs tall and a humanoid can climb onto one — Phase 5 gives them a lip/rail or 3.4-stud height. `CoveDriver` is retired with the island; a `SettlementDriver` (lantern sway, boat bob) is Phase 6.

## 6. Captures taken (reproducible; the tool returns images, writes no files; Studio must be foregrounded — it was minimized once and returned black frames until restored)

| View | Camera → look-at (world) | Shows |
|---|---|---|
| Aerial top-down | (8010, 2560, 7900) → (8010, 2002, 8100) | town mass, river cut, north bank, cliffs, dock, pier |
| Low oblique SW | (8130, 2300, 7700) / (8170, 2140, 7760) → (7990, 2002, 8080) | stepped quay, roofscape, tower at the far end |
| Spawn | (8000, 2008, 7808) → (8000, 2011, 7900) | dock, gate between the two entrance buildings, stall #1 awning, tower at the vanishing point, boathouse/portal right |
| Gate → street | (8002, 2009, 7862) → (8010, 2010, 7960) | first bend, stalls #2 and #5 in windows, compression |
| Fork Square | (7992, 2010, 8040) → (7970, 2012, 8075) | Guild House arcade, well, NPC posts, the Upper stair on the terrace wall, kiosk |
| Upper edge street | (7940, 2020, 8090) → (7950, 2018, 8200) | stall #8 in U1, parapet, U2 balcony, the tower ahead |
| Bridge Steps square | (8030, 2016, 8180) → (8011, 2020, 8270) | cabins, deck, tower with passage and lantern, gorge |
| Collector's Row | (8018, 2005.5, 8284) → (7950, 2004, 8284) | vault passage → sunken lane → stall #18 → overhang/relic |
| River-mouth vista | (8098, 2006, 8150) → (8011, 2014, 8250) | quay, hoist warehouse, the whole bridge across the water |
| Play: arrival, Row, Overlook, deck | player camera | as §4 |

---

*Stopped for layout approval. Phase 4 (booth loop probes on the new stands with two accounts / the `DataUpdated` seam) and Phase 5 (architecture) wait for it.*
