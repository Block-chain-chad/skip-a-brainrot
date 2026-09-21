# TW-02 — Phase 5 architecture pass (v10): what was built per district, and the changes to the approved greybox

**Date:** 2026-09-20 · **Lane:** TW-02 · **Status:** ARCHITECTURE PASS BUILT AND WALK-TESTED — stopped before the final detail pass for the owner's review (as instructed) · **Studio:** PlaceId `78783087742939`, Edit mode; nothing published.

Preconditions met first: layout approved at the current scale; fresh `.rbxl` saved (`SkipRocks_78783087742939_pre-TW02-arch_2026-09-20.rbxl`, sha256 `5098e27d…8f8a`); Phase 2 committed (`d19b8d3`).

| Field | Value |
|---|---|
| GENERATOR | `ServerStorage.TradingWorldBuild.SettlementGenerator` VERSION 10, 95,119 B, h31 `78f3186c` — mirrored byte-exact, `_MANIFEST.txt` updated. **Two renderers, one set of numbers:** `G.DETAIL = false` rebuilds the approved greybox from the same tables; `G.DETAIL = true` (default) renders the architecture. `ClearAll()` → `BuildAll()` is idempotent. |
| COUNTS | **1,989 BaseParts** (greybox 456) against the 4,500 cap; 76 Models; 20 SurfaceGuis (18 stall signs + the gate sign's two faces); 0 BillboardGuis; **1 light, 1 script** (both the kept `EternalSkip`); 0 emitters, 0 unions, 0 meshes. By section: LowerMarket 690 · Booths 264 · Waterfront 212 · UpperMarket 203 · OldBridge 167 · MarketEntrance 129 · CollectorsRow 108 · Stairs 67 · Cliffs 41 · ArrivalDock 36 · Roads 27 · Land 26. Bbox unchanged (X 7826–8191 · Z 7796–8364); BoundsGuard margins ≥ 361. |
| CONTRACTS | `Contracts()` → **OK 18/18 stalls**, `BoothIndex` 1…18 contiguous, one `TradeZone`, ground under `TRADE_POS` = `DockDeck` at 2002.8, `HubPortal` 24.2 studs off. All 18 stands share one `stallContract()` — `Counter` + `StandPrompt`, level `Display1/2/3`, `SignBoard ▸ SurfaceGui ▸ TextLabel`. No economy, UI or shared script touched; **no currency string exists anywhere in the generator** (the signs still say the temporary "CLAIM STALL"; `BoothHandler` overwrites them on claim/release). |
| MATERIALS | Concrete (stucco plaster, eight muted tones), Cobblestone / Limestone (stone, plinths, quays, copings), Slate + WoodPlanks (roofs, seven sets), Wood / WoodPlanks (frames, jetties, shutters, doors, decks, cladding), Fabric (six faded cloths: awnings, canopies, drapes, washing), Metal (iron: sign brackets, chains, straps, bollards, lamp posts, cages), Grass (tree canopies, planter bushes), Brick (planters, some chimneys), SmoothPlastic only for dark glass (Reflectance 0.14). No Neon, no white/yellow/cyan in the architecture. |

## 1. The building kit (one `archBuilding()`, 45 buildings, no two alike)

Every building keeps its greybox footprint, height, roof type and rise. Per building the spec now carries `style` (plaster / stone / timber / mixed = plaster over timber frame / stoneMixed = stone ground floor, framed plaster above), `front` and visible `sides`, `shopU` (the stall's span, kept clear of doors and windows), `doorU`, `chimney`, `dormer`, `winFront/winSide`, and a name-seeded RNG that jitters window spacing, drops ~10 % of windows, folds shutters open or shut, leans braces left or right, and moves chimneys — so repeated *pieces* never produce repeated *layouts*.

Pieces: stone plinth on every plastered wall (proud, 2.2 tall) · body · jettied upper floor with sill beam and pitched **brackets from the wall to the jetty edge** · corner posts, floor beams, studs and one brace on framed façades (on the jetty plane where the storey overhangs) · gable roofs with 1.3-stud eaves, ridge beam and eave boards; hip roofs from four slopes; flat roofs with parapet + limestone coping + slate deck; sheds · chimney with cap (stone or brick) · dormer with its own gable and glazing (five buildings) · windows: timber (or stone) frame, dark glass, limestone sill, shutters (upper floors, ~65 %) · door: frame, plank leaf, stone step, lintel, never where a stall is · balconies: plank deck, rail, balusters, posts (B4, S4, U2) · open-fronted sheds with beam and posts (Boathouse, S1).

## 2. Per district

**Arrival Dock.** Plank deck with rope rails on iron-strap posts, bollards, a proper boat (hull, bow, gunwales, thwart), the jetty, a boardwalk on posts along the shore, the timber Boathouse (open front, plank shed roof) holding the way home. *Not restyled:* the legacy `HubPortal` arch (neon cyan/yellow) still stands in the boathouse — Phase 6/7 item, attributes untouched.

**Market Entrance.** Harbourmaster: framed plaster upper floor jettied 3 studs over the street and the boardwalk on brackets, dormer, chimney, the hanging "RIVERSIDE MARKET" sign on an iron arm (two faces). Customs House: cobblestone, hip roof, stone-framed windows, a stone gate post opposite. Stall #1 (covered family) against its wall. No overhead beam: the gate tower's cupola is visible at the vanishing point from the dock.

**Lower Market Street.** Cobbled road with a darker gutter line down its bends; 19 buildings — B2 ochre plaster, flat; B3 framed, three storeys, dormer, its upper floors bridging alley A2; B4 plaster hip with the balcony; B5 framed with the external plank stair (12 treads, balusters, sloped rail) and stall #4 beneath it; the Guild House with stone arcade columns (base and cap), jettied framed upper, dormer; the stone Broker's kiosk; the well with its stone rim, posts and little slate roof; two trees (trunk + three canopy spheres); yard wall. Storefront family ×4 (#2, #5, #6, #7): dark shop interior, timber jambs and lintel, fascia sign, folding shutters swung open, stone step, cloth awning on some. Covered family ×3 (#1, #3, #4): posts + sloped cloth + side cloth where nothing else covers them, shelf board, crate, hanging sign on chain.

**Waterfront.** Quay in cobblestone with a limestone coping; irregular bollards and standing barrels along the edge; nets; two piers on posts with rope; three boats; water stairs as real steps into the water; the lane-L1 stone arch (9 blocks) replacing the greybox lintel; sheds in plank cladding, S7 stone with the hoist beam. Dock family ×4: #12 a bench inside the open boat shed, #13 a plank lean-to on posts with rope and crate, #14 under S4's balcony, #15 S6's hatch. Basket and crate props belong to the family, not the street.

**Upper Market.** Terrace faces in cobblestone with limestone copings and two buttresses on the Fork Square wall; the Fork stair in real treads (10 + 7) with a low sloped stone parapet; the edge street cobbled; planters with bushes on the parapet; the Overlook on stone brackets with a bench; the Curio House stone-below/framed-above with dormer and arcade columns; U4 timber on the back terrace. Terrace family: #8 a seven-block stone arch on piers with a carved plaque (the contract sign as a stone tablet); canopy family: #9 under a cloth between the arcade columns, #10 a four-post cloth canopy with valance on the back terrace; loading family: #11 an upper loading door with hoist beam, strut and rope, one leaf open.

**Old Bridge.** Two nine-block stone arches under the deck on the central pier, spandrel walls, pointed cutwaters both sides; cobbled deck; stone parapets with limestone coping and three iron lamp posts (lights come at Phase 6); the two cabins plank-clad on timber struts, gable roofs, a chimney; the gate tower — cobblestone base with a vaulted passage (nine-block arches at both ends, springing 5.2 above the deck), framed plaster upper storey (two beams, five studs, two braces per road face, two windows), stone cap, slate roof, and a timber lantern cupola with an iron cage; the warden's door in the passage; the north stub with sloped parapets and the closed timber gate with iron straps in a stone arch. Bridge family ×2: hatch openings with a plank hood on struts, jambs, sign off the eave.

**Collector's Row.** The vault under the road (7.4 studs headroom); the sunken cobbled lane; RN buildings in stone / timber / plaster; the relic head in limestone with an eye and moss; a washing line of odd cloths across the lane; the timber end-overhang on posts; rope rails at the west end. Collector family ×1: black timber jambs and lintel with iron straps, a dark drape, a hook with a cage, the sign hung crooked.

**Cliffs and land.** Every cliff run is a base mass plus two to four leaning slate blocks of different heights — no flat planes. Ground slabs limestone, squares in three cobble tones, Tanners' Yard darker.

## 3. Traversal after the pass (Play mode, WalkSpeed 20, `Humanoid:MoveTo` on real treads)

Route A dock → relic **33.7 s** (every stair climbed: Fork 7 + 5, causeway, bridge, tower passage, the Row stair; all logged standing on the intended surfaces). Route B dock → boardwalk → quay → Bridge Steps → deck → Row **35.6 s**. Also verified: the Row loop **back out** (relic → stair → deck), the fishing pocket down and back up, the courtyard via alley A4 in and out, alley A2 under B3 to the quay, the upper lane to the back terrace and back. Mobile-safe: no ramp steeper than 27°, no tread taller than 0.75, alleys ≥ 7, lanes ≥ 9.

## 4. Changes to the approved greybox (owner to confirm)

1. **Collector's Row stair moved north of the lane** (from z 462–470 to z 470–478, descending west along the embankment; RN1 shortened to z 480–500). The approved greybox had the stair *in* the lane's own strip, so the only way into the Row was over the vault road and a 9.4-stud drop, with no way back up — real treads made the flaw solid. Now: down the stair, turn, walk east under the vault, and climb back out the same way. The lane itself, the vault, the relic and stall #18 are where they were.
2. **Tower passage arches** were placed 5.2 above the datum instead of above the deck (head height in the passage) — fixed, headroom 11.7–12.
3. **Causeway parapet gap** narrowed to the pocket stair's head (was 4 studs wider than the stair — a hidden drop); the pocket stair got a sloped outer parapet.
4. Stair side rails are **low sloped parapets**, not walls (a first version blocked the Bridge Steps from the quay side).
5. Jettied buildings' upper-storey windows and frames are generated on the **jetty plane** (a first version put them inside the overhang); brackets now run wall-to-edge.
6. Tower upper storey +4 studs so the cupola clears the Guild House roof from the dock again (the greybox's plain block was taller than the finished tower).
7. Palette warmed and darkened (plaster, stone, coping) — the first render read blue-white under the current global lighting.

Nothing else moved: every footprint, level, street width, stall position, `TradeZone`, NPC spot, portal and `TRADE_POS` datum is the approved v3 number.

## 5. Deferred to the final detail pass / later phases (by instruction)

Phase 5b (after this review): structural braces on stone buildings' timber parts, gable-end barge boards on the buildings whose gables face the street, corner quoins on the stone houses, kerb lines at building fronts, a few more sheds' side doors, the legacy `HubPortal` arch restyled as the ferry landing (attributes untouched). Phase 6: lanterns and warm local light (the iron lamp posts, sign brackets and cupola cage are already placed to take them), vegetation beyond the three tree masses, cloth on more awnings, water dressing, ambient sound; `NpcSpot` posts made invisible; a `SettlementDriver` (lantern sway, boat bob) on `CoveDriver`'s conventions. Phase 7: mobile captures, performance numbers, deletion pass.

## 6. Captures (Studio must be foregrounded and rendering; after a Play stop the viewport can freeze at 0 fps until the viewport is clicked)

Aerial SW (8150, 2130, 7740) → (7990, 2010, 8060) · Spawn (8000, 2008, 7806) → (8000, 2011, 7900) · Gate → street (8003, 2009, 7864) → (8010, 2010, 7960) · Harbourmaster face (7982, 2016, 7842) → (8014, 2014, 7864) · Fork Square (7994, 2011, 8036) → (7966, 2013, 8076) · Upper edge street (7940, 2020, 8092) → (7952, 2018, 8200) · Bridge from the square (8012, 2016, 8196) → (8011, 2030, 8268) · Collector's Row (8000, 2005.5, 8286) → (7950, 2005, 8284) · Quay (8094, 2006, 7900) → (8072, 2008, 7990).

---

*Stopped for the owner's review of the per-district architecture and the greybox changes in §4. The final detail pass, then Phase 6, follow approval.*
