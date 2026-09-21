# TW-02 — Final detail pass, the Old Riverside Market Gateway, and Phase 6 lighting (v14)

**Date:** 2026-09-21 · **Lane:** TW-02 · **Status:** BUILT AND VERIFIED (finishing procedure A–J) — stopped for the owner's visual review; no further gameplay phase started · **Studio:** PlaceId `78783087742939`; nothing published.

Built on the approved architecture pass (`d9cc3c1`, v10) without rebuilding it: every building, stall, street, level, route, `TradeZone`, `TRADE_POS` datum and NPC spot is the approved number. This pass only *added* to it — detail parts, the gateway, the dressing, the lanterns — plus the changes listed in §7.

| Field | Value |
|---|---|
| GENERATOR | `ServerStorage.TradingWorldBuild.SettlementGenerator` VERSION 14, 120,620 B, h31 `bda65ce2` — mirrored byte-exact, `_MANIFEST.txt` updated. Same two renderers over the same data (`G.DETAIL=false` still rebuilds the approved greybox). `ClearAll()` → `BuildAll()` idempotent; each section is a Model with `TW2 = true`. |
| NEW OUTSIDE THE WORLD FOLDERS | `StarterPlayer.StarterPlayerScripts.TradingAtmosphere` (LocalScript, 2,152 B, h31 `de60a22c`, in the manifest) and `Lighting.TradingGrade` (ColorCorrectionEffect, disabled at rest). That is the whole footprint outside `GameWorld.TradingWorld` / `TradingCenter` / `Portals.HubPortal`. No economy, UI, booth, trade, teleport or shared script touched. |
| COUNTS | **2,545 BaseParts** (v10 1,989 · greybox 456) against the 4,500 cap. **37 PointLights** (35 lanterns, the portal veil, the kept `EternalSkip`), **2 ParticleEmitters** (both inside the gateway arch), 39 Neon parts (35 lantern cores + `EternalSkip`'s 4), 28 SurfaceGuis (18 stall signs, the gate sign's two faces, the gateway tablet, the guild tablet, three trade signs × 2 faces), 0 BillboardGuis, 0 meshes/unions, 1 script (`EternalSkip.SkipLoop`, kept). 1,809 of 2,545 parts are non-colliding decoration. |
| CONTRACTS | `Contracts()` → **OK 18/18 stalls**, `BoothIndex` 1…18 contiguous, one `TradeZone`, ground under `TRADE_POS` = `DockDeck`, `HubPortal.PortalTouch` present with `Dest = "Hub"`. All 18 signs read the temporary "CLAIM STALL"; **no currency string exists anywhere in the generator or on any sign**. |

## 1. Final detail pass (step A)

**Building kit (inside `archBuilding`, footprints unchanged).** Barge boards on every gable end that faces a visible side; corner quoins on the stone and stone-below fronts (Customs House, Broker's kiosk, Curio House, S7, the RN stone houses, the gate tower base); beam ends under every jetty sill; two iron straps on each storefront shutter; ~30 % of upper-floor windows are "lit" — a warm-tinted pane at 0.3 transparency and **no light source** (33 panes in total).

**Dressing section (67 parts).** Limestone kerbs down both sides of the Lower Market street (low sloped runs, walkable); three drains at the bends and a scupper on the quay; dock ironwork — cleats, mooring rings, a coiled line; crates under a tarp by the hoist warehouse (S7), an upturned boat on the boardwalk, a fish rack on the pier; a hand cart in the Tanners' Yard, a wheel leaning on the courtyard wall, barrels by the Broker's kiosk; a bench facing the well, a notice board by the gate, a bucket and rod at the fishing pocket. Trade signs as physical boards on iron brackets: BROKER (kiosk), CURIOS (Curio House), BOATS (boat shed), and a carved GUILD HOUSE tablet. No prices, no currency, nothing about Gems.

**Part count by section** (v10 → v14): LowerMarket 690 → 751 · Booths 264 → 280 · Waterfront 212 → 242 · Lanterns — → 226 · UpperMarket 203 → 206 · OldBridge 167 → 175 · MarketEntrance 129 → 154 · CollectorsRow 108 → 130 · Gateway — → 100 · Dressing — → 67 · Stairs 67 · Cliffs 41 · ArrivalDock 36 → 34 · Roads 27 · Land 26 · NpcSpots 11 · EternalSkip 4 · Barrier 3 · HubPortal 1.

## 2. The Old Riverside Market Gateway (steps B, C)

The functional portal is untouched: `GameWorld.Portals.HubPortal` still holds its one `PortalTouch` (8.4 × 11.2 × 2.8, `Dest = "Hub"`, `CanCollide` false); `TeleportService.setupPortal` binds only that part and was not edited. The Model was re-pivoted (the generator's `PlacePortal`, which also records `TW2_OriginalPivot` on first use) from the boathouse to the new gateway chamber: `PortalTouch` at world **(8000, 2008.4, 7797)** = design (0, 6.0, −21), thin axis across the arch, facing north. The 19 legacy decor parts (neon arch, rings, cyan/yellow trims) were **moved, not deleted**, to `ServerStorage.TradingWorldBackups_2026_09_20.HubPortal_LegacyDecor` (`RetirePortalDecor`).

**Architecture (100 parts, section `Gateway`, at the south end of the Arrival Dock, design x −17…17, z −26…−12).**
- Heavy stone base (y −6…0.4) in cobblestone with limestone copings and a worn threshold at deck level; the dock deck was shortened (see §7) so the gateway stands on its own masonry, in the water.
- Two piers, deliberately unequal: east pier x −11…−7, west pier x 7…12 with an added buttress (x 12…14.6) and a sloped stone top — the west side is visibly heavier. Quoins up both piers.
- Layered arch: an outer limestone arch (radius 7.6, eleven voussoirs) over an inner dark-stone arch (radius 6.1, nine voussoirs), keystone, spandrel shoulders, a string course, then the tablet band.
- The carved limestone tablet reads **TRADING WORLD** (Antique face, on a 10 × 2.2 stone slab — physical signage, not UI). The hanging "RIVERSIDE MARKET" sign at the Harbourmaster's is unchanged.
- Dark timber: a tie beam across the piers at y 12.7…13.7 with three iron straps and six bolts; a slate hood over the tablet band (gable, 4.4 rise) on eave beams with barge boards, six beam ends, two knee braces and **one** outer brace with its strap (west only — the asymmetry the brief asked for).
- Two iron lantern arms (x −9 and 9.5, y 9.1) carrying hanging lanterns — the two lamps a player sees on arrival.
- A chamber behind the arch (side walls x ±9…12, back wall z −26…−24.6, roof z −24.6…−18.8) so the energy is contained inside the masonry and reads as depth, not a billboard.

**Portal energy (restrained).** Three layers inside the chamber, all non-colliding: `PortalDepth` (a near-black navy back plane), `PortalSheen` (dark glass, transparency 0.5, reflectance 0.06), `PortalVeil` (transparency 0.9, a slightly cooler blue-grey) carrying the one portal light — colour (150, 178, 220), brightness 0.75, range 15, no shadows — so the gateway pool is a touch cooler than the lantern pools. `PortalMotes` holds the only two emitters in the world: "Motes" (5/s) and "Mist" (1.5/s), sized to the arch opening. No rainbow, no particle spray, no bloom, no neon outline, no crystals.

**Arrival composition.** The player still arrives at `TRADE_POS` facing north up the dock; the gate tower's cupola remains the vanishing point (nothing was added between the dock and the tower). The gateway is behind the arrival point, at the dock's south end, and is the first thing seen on turning round or on the way home.

## 3. Phase 6 lighting (step D)

**35 lanterns**, one `PointLight` each — warm (255, 198, 128), brightness 1.5, range 18, shadows off — in an open iron cage (`LanternGlass` core, cap, base, two bars) so the core is actually visible as lit. Four mounts: hanging from a wall arm, hooked under an eave or arch, on a lamp post, or bare on the bridge's iron posts. Placement is where people stand, trade and cross water, not on a grid:
- **Arrival / Gateway:** the two gateway arms; two posts at the dock corners.
- **Market Entrance / Lower Market (14):** over stalls #1–#7 and at the corners people turn — the Harbourmaster's and Customs House frontages, B3/B5, the Guild arcade hook, the lane arch hook, a post in Fork Square, the well side.
- **Waterfront (5):** quay hooks at the boat shed, S4/S6, S7's hoist, and a hang on the pier warehouse.
- **Upper Market (4):** Curio House hang, the back terrace hook, a post at the Overlook, a hang at the causeway head.
- **Old Bridge (5):** three bare lanterns on the existing iron posts, a hook in the tower passage, and the cupola beacon (brightness 1.3, range 34 — the only long-range light, so the tower reads from the dock at dusk).
- **Collector's Row / fishing pocket (3):** the vault hang, the Row hook, a short post at the pocket.

**Shop windows:** the 33 lit panes of §1 (tinted glass only, no lights) give the street its evening windows without a light per window.

**Day/night:** the existing `ServerScriptService.NightLights` (2 Hz, server-side) already lists `LanternGlass` as an outdoor host, so **every new lantern joins the cycle with no code**: 45 % at noon, full at night; the portal light holds the interior 55 % floor. That is what keeps "not every lamp bright" true by day. (At the time of the count the lanterns were at brightness 0.70 in Play — noon.)

**Local grade, not global.** `Lighting.TradingGrade` is a `ColorCorrectionEffect` that sits disabled; `StarterPlayerScripts.TradingAtmosphere` fades it in only while the player is inside the Trading World's box (7300…8790 × 1930…2110 × 7375…8725) — tint (255, 238, 214), brightness +0.015, contrast +0.06, saturation +0.05, 1.6 s fade — and back out on leaving. It never touches `Lighting.Brightness`, `ExposureCompensation`, the `Atmosphere`, bloom or the sky. No global blue, no bloom added.

## 4. Performance (step E)

2,545 parts of the 4,500 budget (+556 over v10: Lanterns 226, Gateway 100, Dressing 67, kit details 163). 1,809 parts non-colliding (every decorative name in the `DECO` set plus anything containing "Roof"). 37 lights, all shadowless; 2 emitters, both inside the gateway; 52 parts with partial transparency — 33 lit panes, 11 NPC-spot markers, the two portal layers, two nets, two cages, `EternalSkip`'s two rings — no stacked transparency. Bounding box X 7826–8191 · Y 1992–2074 · Z 7792–8364 (the gateway base adds 4 studs to the south); BoundsGuard margins W 599 · E 526 · N 361 · S 417.

## 5. Verification (steps F, G, H)

- **F — Full traversal** (Play, WalkSpeed 20, `Humanoid:MoveTo` on the real treads, after the gateway and dressing were in): dock → gateway landing → street → Fork → Upper → causeway → bridge → tower passage → Row stair → relic **34.5 s**; the Row loop back out and the return over the bridge to the dock **42.0 s** total. Kerbs, drains and lantern posts are on the edges and did not catch the walk. The changes after that test were the v13 lantern cage and the v14 marker transparency, both on non-colliding parts.
- **G — Portal teleport:** walking into the gateway arch from the dock fired `PortalTouch` → `HUB_POS` (24, 6.3, −16) in 0.8 s. Destination and attribute unchanged.
- **H — All 18 stalls:** each `Counter.StandPrompt` was held (0.3 s) in Play with the stall on screen; `BoothHandler` claimed, rewrote the sign, and released on `Unclaim` — 18/18. Two first-pass misses (#6, #18) were the test camera not looking at the prompt; both passed once aimed.
- **Contracts** re-checked at report time (Play server): 18 booths, contiguous, all parts of the contract present, one `TradeZone`, signs "CLAIM STALL" × 18.

## 6. Captures (step I)

`docs/trading-world/captures/phase6/` — 902 × 506 JPEG crops of the Studio viewport (Edit mode, current global lighting at Studio's default clock, the HUD as the Studio preview shows it; the camera set as `Scriptable` for every shot, since after a Play session the editor camera kept overriding a `Fixed` camera's rotation). The cameras are the Phase 5 report's nine viewpoints, so the two reports compare directly:

| # | Viewpoint | Camera → target | Files |
|---|---|---|---|
| 01 | Aerial SW | (8150, 2130, 7740) → (7990, 2010, 8060) | `before-01-aerial.jpg` · `after-01-aerial.jpg` |
| 02 | Arrival, facing north up the dock | (8000, 2008, 7806) → (8000, 2011, 7900) | `before-02-arrival.jpg` · `after-02-arrival.jpg` |
| 03 | The portal | before: the legacy arch in the boathouse, from the dock (8000, 2010, 7838) → (7979, 2010, 7830); after: the gateway from the dock (8000, 2011, 7834) → (8000, 2014, 7800) | `before-03-portal.jpg` · `after-03-gateway.jpg` |
| 04 | Gate → Lower Market street | (8003, 2009, 7864) → (8010, 2010, 7960) | `before-04-street.jpg` · `after-04-street.jpg` |
| 05 | Fork Square | (7994, 2011, 8036) → (7966, 2013, 8076) | `before-05-fork-square.jpg` · `after-05-fork-square.jpg` |
| 06 | Upper edge street | (7940, 2020, 8092) → (7952, 2018, 8200) | `before-06-upper-market.jpg` · `after-06-upper-market.jpg` |
| 07 | Old Bridge from the square | (8012, 2016, 8196) → (8011, 2030, 8268) | `before-07-old-bridge.jpg` · `after-07-old-bridge.jpg` |
| 08 | Collector's Row | (8000, 2005.5, 8286) → (7950, 2005, 8284) | `before-08-collectors-row.jpg` · `after-08-collectors-row.jpg` |
| 09 | Quay | (8094, 2006, 7900) → (8072, 2008, 7990) | `before-09-quay.jpg` · `after-09-quay.jpg` |

"Before" = the approved v10 state, approximated without a rebuild: the three new sections (`Gateway`, `Dressing`, `Lanterns`) were parked in `ServerStorage` and a clone of the legacy portal decor shown in the boathouse at its stored position, the nine shots taken, then everything put back — the world fingerprint (every part's name, position, size, colour, material, transparency, collision; every light; 2,746 rows) was `e15a89d1` before the swap and `e15a89d1` after it. The kit details of §1 (quoins, barge boards, beam ends, straps, lit panes) are inside the building sections, so they show in the before shots as well.

Not captured: a dusk shot — Play-mode captures come out black unless the Studio window is foregrounded, which the owner's own Play session made inappropriate at the time; the lanterns and their day/night swing are visible in any Play session once `ClockTime` passes 18.

## 7. Changes from the approved architecture (step J)

1. **Dock deck trimmed** from design z −22…18 to z −12…18 (`ArrivalDock`), the dock posts, rope-rail posts and bollards re-seated to the new south edge, so the gateway stands on its own stone base at the dock's south end. The arrival deck under `TRADE_POS` (z 0) is untouched.
2. **HubPortal moved** from the boathouse (design (−21, 5.6, 12), facing east) to the gateway chamber ((0, 6.0, −21), facing north). Same Model, same `PortalTouch`, same attributes; only the pivot. The legacy decor is in the backups folder; the boathouse remains as the open-fronted timber boat shed with its plank landing.
3. **Additive only, no footprint change:** the `Gateway`, `Dressing` and `Lanterns` sections; the kit details of §1; `Lighting.TradingGrade` + `TradingAtmosphere`.
4. **NPC-spot markers** (`NpcSpot_<Role>`, 1 × 4 × 1, `CanCollide` false, attributes `Role`/`Tier`/`Note`) are fully transparent in the detail render as of v14 (they were 0.6 in v10–v13) — the eleven positions and the attributes are unchanged, as planned in the Phase 5 report's Phase 6 list; the greybox render still shows them. This is the only generator change between v13 (the state every test in §5 ran on) and v14.

Not changed: all 18 stall positions and families, stall claiming, listing, pricing, purchasing and ownership logic, inventory connections, the trading backend, `TradeZone`, `TRADE_POS`, the portal destination, `HubPortal` functionality, district footprints, street widths, routes, NPC positions.

## 8. Backups and rollback

- `.rbxl`: `C:\Users\m\Coding\skip-a-brainrot-backups\SkipRocks_78783087742939_pre-TW02-arch_2026-09-20.rbxl` (sha256 `5098e27d…8f8a`, the state after Phase 2, before Phase 5).
- In Studio: `ServerStorage.TradingWorldBackups_2026_09_20` — `Legacy_TradingWorld`, `Legacy_TradingCenter`, `HubPortal_LegacyDecor` (19 parts), the Grand Exchange clones; `HubPortal` carries `TW2_OriginalPivot`.
- Back to v10: check out `d9cc3c1`'s generator, `ClearAll()` → `BuildAll()`, move the decor back into `HubPortal`, `PlacePortal()`; delete `Lighting.TradingGrade` and the `TradingAtmosphere` LocalScript.

---

*Stopped here for the owner's visual review of the environment, the gateway and the lighting. No further gameplay phase was started.*
