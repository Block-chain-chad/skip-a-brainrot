# TRADING WORLD REWORK — Inspection Report & Phase 2 Plans (lane TW-01)

**Date:** 2026-09-19 · **Branch:** `trading-world-rework` (worktree `../skip-a-brainrot-trading-world`, base `source-sync-audit` @ `b29c541`) · **Supersedes:** the Phase 1B draft of the same day · **Phase 1 report:** `docs/TRADING-WORLD-REWORK-PHASE1.md` (approved; Concept 1 — Brainrot Grand Exchange — selected).
**Studio session:** read-only, Edit mode, PlaceId `78783087742939`, one instance. Every call was a read (`GetChildren`, properties, attributes, `ReadVoxels`, raycasts, `#Source` hashes) or a screen capture with a temporary camera. **Nothing was moved, deleted, created, edited, saved or published. No greybox was started.**
**Economy canon received:** Gems are the marketplace currency (earned from daily quests and Robux). Booth loop: list → choose gem price → buyer pays that exact amount → seller receives it → ownership transfers safely. Gem acquisition rates, Robux gem pricing, quest rewards, rarity odds, Golden/Diamond and Huge/Massive values are **not** touched by anything below.

Compass: **N = +Z, S = −Z, E = −X, W = +X.** Island centre C = (8000, 2002.4, 8000). P = the plaza datum y 2002.4. All coordinates absolute.

---

## 1. Read-only Studio findings

### 1.1 Corrections to what the docs said

| Documented | Live (2026-09-19) | Consequence |
|---|---|---|
| `TradingWorld` / `TradingCenter` are Models, `ModelStreamingMode = Persistent` | **Both are Folders.** A Folder has no streaming mode. | The Persistent contract never existed. Server binding works regardless (the server sees everything); `TradeClient` just waits for the zone to stream in on arrival. The new build sets streaming per model deliberately. |
| 12 booths, verified 12/12 on 2026-08-09 | **Six booths: `Booth7`–`Booth12`** (`Booths` = 96 descendants = 6 × 15 + 6). | Booth1–6 were removed after 2026-08-09 by an unlogged edit. `BoothHandler` adopts six and warns for nothing missing. Source for the lost six: `ServerStorage.PreCove_Backup_2026_08_02.TradingCenter_OLD` (218 descendants). |
| `HubPortal` at (7981, 2006, 7830), west side of the deck | **`HubPortal.PortalTouch` at (8000, 2006, 7815.7)**, 8.4×11.2×2.8, on the axis, **2.3 studs behind `TRADE_POS` (8000, 2004.6, 7818)** | Step backward on arrival and you go home. Marginal at the arrival frame itself (touch part ends z 7817.1, root part starts 7817.0). The new Landing separates them by 22 studs. |
| Seabed terrain under the island | **No solid terrain at any probe** (9 columns X 7400–8700, Z 7500–8500). Water only, surface **y 1999.5**. The "seabed" is `Island.Seabed`, a Part (cylinder r120, top 1999.0). | The island is parts in a terrain ocean. Zero terrain work in Phase 2. |
| `StandPrompt` reach 10 | **`MaxActivationDistance = 8`**, `ObjectText "Market Stand"`, hold 0.3 | The server-made `BuyPrompt` is the one with reach 10. |
| Boards "W", Index gate "E" | `SaleBoards` at (7897, 8000) = **−X**, `IndexGate` at (8103, 8000) = **+X** | The cove docs used the opposite E/W wording; coordinates win. |

### 1.2 Measured geometry

| Object | Measurement |
|---|---|
| `Island.Plaza` | cylinder Ø124 (r62), **top y 2002.4** (raycast at C: 2002.4, `Island.Plaza`) |
| `Island.RingWater` ×16 | Glass chords 26×3×31.2, Transparency 0.35, **CanCollide false**, top 2002.0, r ≈ 62–88 — a moat you fall into; the seabed part is 3.4 below |
| `Island.OuterRing` ×16 | blocks 30×4.8×47, top **2002.4**, r ≈ 88–118 (raycast at Booth7's front: 2002.4, `OuterRing`) |
| `Bridges` | 60 parts, planks top **2004.0** (raycast at r75 east) |
| Gazebo (`TradingCenter`) | `Floor` 56×1×56 top **2000.0 — buried 2.4 studs inside the plaza disc**; `Podium` cylinder top 2005.6 (reads as a sand hump); 4 pillars 3×28×3 at (±20, ±20) with caps; 4 beams at y 2029.5; `SignBoard` 30×5×1 at (8000, 2033, 7980) "🔄 TRADING CENTER"; 4 floor trims; 21 parts, 23 Neon in the folder |
| `TradeZone` | 26×26×26 at (8000, 2007, 8000), look −Z, anchored, CanCollide false, Transparency 1 |
| Booths 7–12 | `Counter` 10×3.2×2.2 at y ≈ 2005.0; `Display1/2/3` 1.6×0.4×1.6 at y ≈ 2006.8, 3.4 apart (server cube lands ≈ 2008.5); `SignBoard` 9.6×1.9×0.4 at y ≈ 2009.7, SurfaceGui Face **Back**, 50 px/stud, TextScaled; bounding box 12.6×9.8×9.5 per booth; model pivots pitched ≈ 11° (the models lean); positions B7 (8040, 8101) · B8 (8018, 8107) · B9 (7984, 8109) · B10 (7935, 8079) · B11 (7959, 8103) · B12 (7920, 8064), i.e. 68°–141° about +X at r 103–110 — the northern half of the documented arc |
| `ArrivalDeck` | `DeckTop` 46×2.4×44 at (8000, 2001.2, 7830) → top 2002.4, z 7808–7852; `ArrivalPad` cylinder Ø12 top **2002.8** at (8000, ·, 7818) (raycast under `TRADE_POS`: 2002.8); 1-stud `DeckEdge` lip; two lamp posts with Neon globes |
| `Causeway` | planks 7×1.1×5.3 (**7 studs wide**) z 7852–7882, tops 2002.8 → 2003.8 → 2002.8 (a hump), rope rails |
| `MarketArch` | at z **7942** (south bridge, r58 — the plaza entrance), pillars 12.6 tall, "MARKET" sign 16×4.2 at y 2018 |
| `CoveDressing.ColossalArch` | 71×69×11 centred (8000, 2032, 7878), apex ≈ 2066, straddling the causeway |
| `CoveDressing.SkippersSpire` | (8000, ·, 8140), 904 studs tall (beam to y 2902) |
| `CoveDressing.Guardians` | six statues at **r ≈ 138** on plinths: `Guardian_TungTungTungSahur` (8138, 8000) 0°, 34×36×18 · `Guardian_BombardiroCrocodilo` (8063, 8109) 60°, **87×48×76** · `Guardian_LaVaccaSaturnoSaturnita` (7931, 8120) 120°, 36×50×36 · `Guardian_TralaleroTralala` (7862, 8000) 180°, 25×48×64 · `Guardian_BrrBrrPatapim` (7931, 7881) 240°, 51×40×24 · `Guardian_BallerinaCappuccina` (8069, 7881) 300°, 24×28×24; 214 descendants; six breathing Highlights (`CoveBreatheH`) |
| `CoveBarrier` | 14 invisible walls 2×40×50 on r ≈ 121, top 2038.4, open to the south |
| `EternalSkip` | stone + 3 rings, orbit r68 (`SkipLoop`, 26°/s) |
| Other dressing | WaterDressing 175×2.7×175 (40), FloatingIslets 58×155×175 to y 2164 (42), AmbienceAnchors (10), WorldEdge 249×60×249 (30), Monuments 46×255×102 with beams to y 2151 (49); tags CoveOrbit 7 · CoveSpin 2 · CoveBreatheT 2 · CoveBreatheH 6 · CoveBob 8 · CoveAmbience 5 · CoveFallScroll 0 |
| `Palms` 90 · `TikiTorches` 18 · `CliffCove` 27 (to y 2028) · `SaleBoards` 12 · `IndexGate` 15 · `RewardChests` 35 | all decorative, none read by code |
| Totals | `TradingWorld` 913 descendants: **618 BaseParts** (5 MeshParts, 58 Neon), 15 lights, 6 emitters, 6 Highlights, 20 SurfaceGuis, 6 Sounds, 2 scripts (`SkipLoop`, `CoveDriver`, both mirrored byte-exact). `TradingCenter` 122: 81 BaseParts, 14 SurfaceGuis, 0 scripts |
| Stray | `TradingWorld.Part` 4×1×2 at (8091, 2038.9, 8080), **unanchored**, CanCollide true, no attributes — junk |
| `Spin` attribute | on **no** part; `CenterpieceSpinner` spins an empty list every Heartbeat |

### 1.3 Server, streaming, lighting, spawn, portals, backups, mirror

- `Players.MaxPlayers = 60`, `PreferredPlayers = 60`.
- `workspace.StreamingEnabled = true`. The radii/integrity properties are plugin-security and could not be read from the command context; read them from the Properties panel later. Assume the defaults.
- `Lighting` (global): ClockTime 14 (a `DayNightCycle` runs live), Brightness 2.42, Exposure 0.14, Atmosphere (density 0.22, haze 0.30, glare 0.12), ColorCorrection (contrast 0.13, saturation 0.12), Bloom 0.45, SunRays on, FogEnd 2500, Sky "Sunny Day". **`Lighting.TundraGrade` and `Lighting.GardensGrade`** exist (ColorCorrectionEffects, disabled at rest); `StarterPlayerScripts.TundraAtmosphere` fades a private grade + `ExposureCompensation` + Atmosphere while the player is inside the world's BoundsGuard box, never touching `Brightness` (WeatherClient's) and never writing Atmosphere during a weather event. A `TradingGrade` + `TradingAtmosphere` pair on that pattern is how the Exchange gets its own look without editing globals (Phase 3).
- One `SpawnLocation` in the place: `Workspace.SpawnLocation` (0, 33, −180), Neutral. Death anywhere → the valley.
- `GameWorld.Portals`: `TradePortal` (valley, (0, 11.2, −303.1), `Dest = "Trade"`, `PlaceName = "the Trading Island"`, `ComingSoonMessage = "🤝 Trading is coming soon — the island is shut for work."`) · `HubPortal` (island, `Dest = "Hub"`) · `TundraPortal` · `TundraReturnPortal` (`Dest = "Dungeon"`) · `DepthsPortal` (`Dest = "Gardens"`, `RequiresFlag = "CaveUnlocked"`) · `GardensReturnPortal` (`Dest = "Tundra"`). **Exactly one door leads to the island.**
- Backups: `ServerStorage.PreCove_Backup_2026_08_02` (`TradingCenter_OLD` 218, `HubPortal_OLD` 24, `Decor_OLD` 270, 4 `IslandBarrier`), `AuditBackups.TeleportService_pre_coverebuild`, `World2Backups_2026_09_19.Rollback`; `AuditBackups` holds 107 children.
- Mirror byte-check (h31 + bytes) of 39 trading-stack scripts: **38 identical to `source-sync-audit`**; `TeleportService` is `ab7f1a65|26985` live vs `4f230a48|26939` in the mirror (+46 B, the World 2 lane's in-flight edit — the bypass lines quoted in §9 were read live). `UIKit.InteractionPrompt` / `InteractionPromptClient` are round-3 files not yet on this branch; `InteractionPromptClient` does not special-case `BuyPrompt` (generic: verb from `VERB_BY_NAME`, else the first word of `ActionText` → "BUY").
- Scripts referencing `TradingWorld`: `SkipLoop`, `CenterpieceSpinner`, a `BoundsGuard` comment. No client fires `TeleportTo("Trade")` (`ClientMain` fires only `Throw`, `Shops`, `Plot`, `OpenPlot`; the Worlds panel fires world ids).

## 2. Current Trading World screenshots and measurements

Six captures were taken once Studio was foregrounded (the first three attempts rendered black while it was backgrounded). The capture tool returns images to the session and does not write files; each view is reproducible from the camera below and is described here for the record.

| # | Camera → look-at | What it shows |
|---|---|---|
| 1 Arrival | (8000, 2007.6, 7812) → (8000, 2012, 8000) | Standing on the deck facing north: the pale-blue crossed tusk arch fills the frame, the 7-stud rope-railed causeway runs to the MARKET arch, the "🔄 TRADING CENTER" sign and gazebo pillars sit dead centre, two neon chest beams (yellow, green) rise behind, palms and the pink Patapim / black Tralalero colossi at the edges. Composition is on the axis, but the causeway reads as a narrow plank and the island as a beach. |
| 2 Aerial | (8000, 2260, 7700) → (8000, 2002, 8000) | The whole island: sand disc, teal water ring, four bridges, the square gazebo at the centre, six small stands on the north arc, the spire beam to the sky, green-capped cliffs north, MARKET arch at the south bridge, tusk arch over the causeway, the deck with the yellow arrival pad, six colossi on black plinths in the sea. Booths are the smallest things in the frame. |
| 3 Plaza → booths | (8000, 2008, 7990) → (8000, 2006, 8103) | From the podium (a sand mound in the foreground) toward the stands: four "AVAILABLE STAND" signs ~110 studs away, unreadable; La Vacca on its ring at right, Bombardiro at left, the spire drum behind. The browsing weakness in one frame. |
| 4 Booth close-up | (8002, 2010, 8082) → (8018, 2006, 8107) | Two wooden stalls with yellow canopies, navy "AVAILABLE STAND" boards, three cyan display pads on each counter, a waterfall and green-capped cliff behind. Generic market stall; nothing says rarity or price. |
| 5 Guardian line | (7950, 2006, 7920) → (7862, 2030, 8000) | Tralalero Tralala (blue shark with sneakers) rising from the sea at r138 beyond the SaleBoards pavilion (three dark surfboards under a coral-slat shade); water ring and palms in the foreground. |
| 6 Gazebo | (8000, 2007, 7948) → (8000, 2014, 8000) | The four pale pillars and wooden beams of an open frame (no roof), the podium hump, the invisible `TradeZone`; six tiny stands and the "JOIN THE CREW!" chest sign in the distance, waterfalls on the north cliff. |

Distances that matter, measured: deck pad → causeway start 34 studs · pad → MARKET arch 124 · pad → gazebo centre 182 · pad → nearest booth (B9 at (7984, 8109)) **≈ 291 studs on the walking line** (deck → causeway → south bridge → plaza → north bridge → outer ring) ≈ 14 s at WalkSpeed 21 · booth arc B12 → B7 ≈ 130 studs · bridge planks 2004.0 vs plaza 2002.4 (a 1.6-stud step at each end).

## 3. Functional objects that must survive

| Object | Contract (exact) | Note from the inspection |
|---|---|---|
| `Workspace.GameWorld` | name | |
| `GameWorld.TradingCenter` (**Folder**) | name; children below | Folder, not Model — leave the class alone; every consumer uses `FindFirstChild` |
| `TradingCenter.TradeZone` (Part) | name; ONE box; `CFrame:PointToObjectSpace` + `Size/2` box test with ±6 Y slack on server and client | position/size free |
| `TradingCenter.Booths` (Folder) | name; children enumerated at server start | |
| each booth Model | attribute `BoothIndex` (number, unique) | N free; six survivors are replaced, indices reissued 1…N |
| `booth.Counter` (BasePart) + `Counter.StandPrompt` (ProximityPrompt) | names; `BUY_RADIUS` 26 is measured from `Counter.Position`; keep reach 8 / hold 0.3 / `ObjectText "Market Stand"` as authored | |
| `booth.Display1`, `Display2`, `Display3` (BaseParts) | names; the listing cube spawns at `CFrame * CFrame.new(0, 1.7, 0)`; exactly three (`MAX_LISTINGS = 3`) | plinth tops at ≈ P + 4.4 put the cube at eye height today |
| `booth.SignBoard` (BasePart) ▸ SurfaceGui ▸ TextLabel | server writes the first TextLabel's `Text` (`"X'S STAND"` / `"AVAILABLE STAND"`) | keep the SurfaceGui's face toward the promenade |
| runtime `ListingDisplay` parts + `BuyPrompt` with attributes `BoothIndex, ListingId, ItemName, Price, SellerName` | never pre-authored; server destroys and rebuilds | the D4 layer reads these |
| `GameWorld.Portals.HubPortal` ▸ `PortalTouch` (`Dest = "Hub"`) | attribute-driven, any number of portal models, binds on `ChildAdded` | **relocate off the arrival axis** |
| walkable surface under `TRADE_POS` (8000, 2004.6, 7818) | ground within ~2 studs below | today `ArrivalPad` top 2002.8 |
| `BoundsGuard` Trading box X 7300–8790 · Y 1930–2110 · Z 7375–8725; region name `"Trading"` | keep all walkable geometry inside with ≥ 40 studs margin | the world id used by `PlayerWorld`, `WorldTravelConfig`, NAV |
| `GameWorld.TradingWorld` (**Folder**) | name (`CenterpieceSpinner`, `CoveDriver` look for it) | contents replaceable |
| `GameWorld.Portals.TradePortal` (valley) | untouched — Duck's lane | the only door in |
| `Lighting`, `Terrain`, `Workspace.SpawnLocation`, `PlayerBases` | never edited | |
| Remotes `BoothState / BoothList / BoothBuy / TradeRequest / TradeRespond / TradeAction / TradeState / TeleportTo / TeleportFade / WorldTravelState / GetItemStats / EmeraldUpdate` | unchanged names and shapes (payload *contents* change under D1/D2 — §7/§8) | |

## 4. What can be completely deleted / replaced

Everything under the two folders except §3's contracts — with the measured counts:

| Delete / replace | Count | Why |
|---|---|---|
| `Island` (Seabed, Plaza, 16 RingWater, 16 OuterRing) | 34 parts | replaced by the Exchange island; the non-collide water ring is a trap |
| `Bridges` 60 · `CliffCove` 27 · `Palms` 90 · `TikiTorches` 18 · `MarketArch` 7 · `SaleBoards` 12 · `IndexGate` 15 · `RewardChests` 35 · `CoveBarrier` 14 · `Causeway` 14 | 292 parts | beach identity; placeholders nothing reads; the barrier ring conflicts with the new edge; the causeway is 7 wide |
| `ArrivalDeck` | 25 parts | re-skinned as the Landing on the same datums (pad kept at (8000, 2002.8, 7818)) |
| `CoveDressing` — WaterDressing, FloatingIslets, ColossalArch, SkippersSpire, AmbienceAnchors, WorldEdge, Monuments, `CoveDriver` | 254 descendants + driver | replaced by the Exchange dressing + `ExchangeDriver`; the 900-stud beam and the islets invert the landmark hierarchy |
| `TradingCenter` gazebo (21 parts incl. the buried floor and the 30×5 sign) | 21 | replaced by the Exchange Hall |
| `Booth7`–`Booth12` bodies | 6 models | replaced by the arcade module (same contracts) |
| stray unanchored `TradingWorld.Part` | 1 | junk |
| `EternalSkip` | keep (D12 default) | orbit retuned to the moat (`R`, `WATER_Y`) |

**Keep in place, zero cost:** `CoveDressing.Guardians` (six colossi at r138 with breathing Highlights) — moved under the new dressing container unchanged; their `CoveBreatheH` tags keep working because `ExchangeDriver` keeps the tag names. Roster to keep or recast: Tung Tung Tung Sahur (+X), Bombardiro Crocodilo (60°), La Vacca Saturno Saturnita (120°), Tralalero Tralala (−X), Brr Brr Patapim (240°), Ballerina Cappuccina (300°).

## 5. Updated Grand Exchange plan (refined with the real measurements)

Layout drawing: `docs/trading-world/grand-exchange-layout.svg` (rev 2). P = 2002.4 everywhere below.

| Item | Proposal |
|---|---|
| **Exact spawn area** | `TRADE_POS` **unchanged** at (8000, 2004.6, 7818) facing +Z, dropping 1.8 studs onto a 12-stud arrival disc at top 2002.8 (the measured `ArrivalPad` datum, re-skinned) in the middle of the **Landing** — a 44 (x) × 56 (z) stone deck at y 2002.4, z 7790–7846, with a U-shaped barrier wall on its three sea sides and a gold inlay arrow north. Keeping the constant means no `TeleportService` edit (that file is in flight in the World 2 lane). |
| **Central Grand Exchange footprint** | The **Exchange Hall**: outer drum r48 (Ø96), eight pylons 8×8×30 at r44 on the 22.5° + k·45° diagonals (the four axial openings stay clear), spring line +18, arches to +30, gold crown ring at +30 (walkable r40–46), balcony ring r36–44 at +12, **sunken Exchange Floor r22 at P − 1.6 (y 2000.8, still 1.3 above the 1999.5 waterline)** with two ring steps r22–25 (−0.8) and r25–28 (P), ramped at N and S. Above the floor: the **Grand Gem**, 14 studs, at +36 with attribute `Spin` (the existing `CenterpieceSpinner` spins and bobs it — zero code), one PointLight (Range 60), one sparkle emitter, one Neon sky beam to +500 breathing on the driver. Eight ticker panels (7×2.5 SurfaceGuis) on the pylons' inner faces at +14. |
| **TradeZone location** | `TradingCenter.TradeZone` = one Part **46 × 22 × 46** centred **(8000, 2006.0, 8000)**, look −Z, anchored, CanCollide false, Transparency 1. Covers the floor, both steps and the first 2 studs of promenade; Y band 1995–2017 (+6 slack in code → 1989–2023), so the balcony (2014.4) is inside the Y band but outside the footprint — nobody up there appears in the floor's nearby list. Same name, parent, single-box math. |
| **Booth district** | Two covered crescents flanking the hall — **West Arcade** (+X) and **East Arcade** (−X) — counters on **r68**, backs at r80, colonnade roof at +9, each holding 12 stands; plus **six Vault stands** in the north hall. Full plan in §6. |
| **Booth count / spacing** | **30** (24 + 6). Arcade pitch **12.95 studs** (11-wide module + ~2 gap) = 120° per crescent (±60° about its axis). `MaxPlayers` is 60 → one stand per two players, 5× today's six. Generator parameter; 14 per arcade (±63°) is the next step. |
| **Browsing loop length** | Promenade r48–66 with the lane stripe at **r58**: one loop 2π·62 ≈ **390 studs ≈ 19 s** at WalkSpeed 21, every arcade stand's three displays 6–10 studs from the stripe (inside `BuyPrompt` reach 10 and `BUY_RADIUS` 26). Vault spur +24 studs each way (+2–3 s). No step, bridge, water or door on the loop. Versus today: 291 studs just to reach the first stand. |
| **Rare / Flex district** | **The Vault**, north: 16-wide 1:4 ramp from the N junction (8000, P, 8066) up to a +6 plateau (y 2008.4), portal arch at z 8092 (dark slate, Secret-pink and God-gold gem rims), a 70 × 90 hall z 8092–8182 with open sides (no camera clipping): six premium stands (`BoothIndex` 25–30) at (7976 | 8024, +6, 8104 / 8120 / 8136) facing a 20-wide nave; the **Reliquary** at z 8150–8175 — five alcoves SECRET · GOD · GOLDEN · DIAMOND · MASSIVE, each a colossal statue built the guardian way (`BrainrotModels` clone, script-stripped, `ScaleTo`, `MutationFX` for the Golden/Diamond ones), one SpotLight + one low-rate emitter each, the God statue on a 20-stud crown plinth with one breathing Highlight; four spotlit **flex pedestals** (6-stud discs, dark backdrop, floor inlay FLEX) at z 8098. No gating (none exists); prestige is position and light. |
| **Showcase / social area** | Records terrace r72–90 flanking the Great Arch: −X side three boards (TOP EARNERS / MOST TIME / MOST CAUGHT — data exists, wiring is D5), +X side the MARKET PRICES ticker (client-only, `GetItemStats` medians, honest "n of 5 sales" rows) and a static HOW TO TRADE board; the Exchange Floor steps (amphitheatre); **Skipper's Pier** (+X, r84→124) under Tung Tung Tung Sahur and **Colossus Walk** (−X, r84→124) under Tralalero Tralala, benches over the moat; the hidden ledge under the causeway bridge (moat is wadeable, so it is reachable and escapable); the Eternal Skip circling the moat at r106. |
| **Observation area** | Balcony ring r36–44 at +12 (two curved 1:4 ramps hugging the drum on the E and W sides, 48 long; four diagonal bridges to the arcade roofs) and the **Observation Crown** r40–46 at +30 (two more curved ramps from the balcony). Highest walkable y **2032.4** (box allows 2110). Also the Vault portal landing at +6 looks back down the axis. |
| **Major sightlines** | (1) Landing → north: causeway masts converge on the Great Arch (feet (7982 / 8018, P, 7930), span 36, apex +54 → **26° elevation from the pad**); through the opening, dead centre, the Grand Gem at +36 over C (**11° elevation**) with its beam; the hall's crown ring behind; the two nearest colossi (Patapim 240°, Ballerina 300°) flank the frame at ±60° — the same axis composition the current island has, with a real landmark at the end of it. (2) S junction → both arcades curve away left and right, every marquee visible in one pan. (3) Balcony → down onto the trades; across the drum to both arcades. (4) N junction → the Vault portal glowing pink/gold straight up the axis. (5) Crown → 360°: arcades, Vault, colossi, the Eternal Skip below, the Landing behind. (6) Pier ends → a colossus overhead and the island edge lit by the moat underglow. |
| **Main landmark** | The Grand Gem + sky beam, visible from the Landing and from every point on the island; hierarchy below it: Great Arch → Exchange Hall drum → Vault portal → six colossi → district totems + floor inlays. |
| **Teleport / return placement** | Entry: `TRADE_POS` as above. **`HubPortal` moved to the Landing's −X edge at (7978, 2006, 7818), facing +X** — 22 studs from the pad, in view on arrival, off the walking line, never behind you. **`HubPortalVault`** (new model, `Dest = "Hub"`, attributes only, no code — `TeleportService` binds any `PortalTouch` under `Portals`) at (8000, +6, 8186) behind the Reliquary so nobody walks 400 studs back. The valley `TradePortal` is untouched. |
| **NPC role locations** | Unchanged from the handoff (`docs/trading-world/npc-roles-for-npc01.md`, updated §10): Host (8000, P, 7948) · Gem Broker (8032, P, 7952) · Curator (8000, +6, 8148) · Attendants (8036 / 7964, P, 8062) · Collector (7972, +12, 7972) · Trader pair (7988 / 8012, −0.8, 8012) · optional Angler (8120, P, 8000) · optional Guards (7986 / 8014, +6, 8092). |
| **Edge** | rim r84–96 (P), **moat r96–116 with a CanCollide-true water part at P − 1** (wadeable, never a pit — the lesson of the current Glass ring), outer stone ring r116–124, six colossi kept at r138, barrier ring **r150** (+ the Landing's U-wall). Everything walkable is ≥ 130 studs inside the BoundsGuard box on every side. |
| **Budgets (unchanged)** | ~3,400 parts (cap 4,500 — today 699), ~38 local lights (cap 48 — today 15), 8 emitters (20 — today 6), 7 Highlights (10 — today 6), one gated `ExchangeDriver` + `SkipLoop` + `CenterpieceSpinner`, one optional client script (D4). |

## 6. Updated booth district plan (browsing is the priority)

**Arrangement.** Two crescents on r68 facing the centre. West Arcade stand k (k = 0…11) at angle θ = −60° + 10.909°·k about +X: `(8000 + 68·cos θ, P, 8000 + 68·sin θ)`, `BoothIndex` 1–12 south → north. East Arcade the mirror about −X, `BoothIndex` 13–24 south → north. Vault stands 25–30 as in §5.

**Module** (authored once, cloned 30×, contracts of §3 exactly):

| Part | Spec |
|---|---|
| `Counter` | 11 × 2 × 3.4, front face on r68, `StandPrompt` inside (reach 8, hold 0.3, `ObjectText "Market Stand"`) |
| `Display1/2/3` | 1.6 × 0.4 × 1.6 plinths at local x −3.4 / 0 / +3.4 on the counter line, **tops at P + 4.4** so the server's cube/tag and prompt land at **P + 6.1** — the eye height the live stands already use and that a 10-stud `BuyPrompt` reaches from the stripe |
| `SignBoard` | **12 × 3 marquee at P + 6.5**, SurfaceGui facing the promenade, 50 px/stud, TextScaled — the server writes `"X'S STAND"` / `"AVAILABLE STAND"` into it for free; make it the biggest text on the stand |
| Body | back wall r72–78, shared colonnade roof at +9 along the crescent, gold trim, banner mast per stand, one warm SurfaceLight per two stands under the roof |
| Floor | promenade r48–66 at P, gold lane stripe at r58; inlay teal on the arcade floor |

**Why this browses well:** from the stripe every display is 6–10 studs away; the marquee is readable from across the promenade (12 studs of text at 50 px/stud); the two crescents are the only things on the loop; a full pass is 19 s and passes each stand once; the balcony gives the "which stands are open" overview before you commit. Today: 6 stands 291 studs from arrival, 9.6-stud signs, cubes for items.

**What a listing shows (after D2, via D4):** Brainrot name · rarity word + tier colour band · GOLDEN / DIAMOND chip · HUGE / MASSIVE chip · **the gem price as the largest element** (💎 + `NumberFormat.Short`, the HUD's own glyph and formatter) · seller display name · a 3D preview of the exact copy (locally cloned `BrainrotModels` model with `MutationFX` and `ScaleTo`). Until D2's attributes exist, no size label is drawn anywhere — the plate can only show what `BuyPrompt` carries.

**Stand states readable from afar:** mast lit green = vacant (`StandPrompt.ActionText == "Claim Stand"`), gold = open, white = all three slots full (count of `ListingDisplay` children) — all derivable client-side from replicated instances.

## 7. Cash → Gems migration plan (documented against the live-identical mirror; nothing changed)

### 7.1 The ten facts requested

| # | Question | Today (file : line) |
|---|---|---|
| 1 | **Every server script involved in booth payment** | `ServerScriptService.Modules.BoothHandler` (the `BoothBuy` handler: every check, the debit `buyerData.Cash -= listing.Price` at L427, the credit `PlayerDataManager.GrantCash(sellerData, listing.Price)` at L428, `Save` both at L446–447, the `[BoothAudit]` line + `retrySave`); `Modules.PlayerDataManager` (`Cash` field, `GrantCash`, `Save`, `PushUpdate`, `Get`, `__noSave`); `Modules.BrainrotMover` (`Take`/`Give` — the item half); `Modules.InventoryHandler` (`SyncBackpack` both sides); `Modules.PriceIndex` (`RecordSale` after the swap); `ReplicatedStorage.Modules.BagConfig` (bag-space pre-flight). After migration `Modules.EmeraldService` (`TrySpend`, `Award`) replaces the two cash lines; nothing else joins. |
| 2 | **Every client script displaying the booth currency** | `BoothClient` L447 (listing card `"$" .. formatNumber(price)`), L661 (buy modal `"$" .. formatNumber(Price attr)`), L575 (`"$…/s"` — that is *income*, not currency, stays); server-authored strings that the client renders: the listing BillboardGui text (`BoothHandler` L133 `"\n$"`), `BuyPrompt.ActionText` (L142 `"Buy for $…"`, drawn by `InteractionPromptClient`), every toast (L310, L394, L457, L458); `IndexClient` L411 (`"PAID $%s (%d sales/%dd)"` — stall medians); `TradeClient` L499, L600, L601 (trade cash sweetener — D1b). |
| 3 | **Where buyer balance is validated** | Server only: `BoothHandler` L393 `if buyerData.Cash < listing.Price then … return end`, inside `BoothBuy`, after bag space and before ownership/unique-cap checks. The client never checks a balance (it only shows the confirm modal). |
| 4 | **Where seller payment occurs** | Server only: `BoothHandler` L428 `PlayerDataManager.GrantCash(sellerData, listing.Price)`, immediately after `Give` and `SyncBackpack`, before the listing is removed. |
| 5 | **Where prices are stored** | In server memory: `booths[idx].listings[i] = { Id, Name, Price }` (`BoothHandler`); copied outward to the owner via `BoothState {Phase="Manage", Listings}`, to the world via `BuyPrompt:SetAttribute("Price", …)` and the billboard text. Completed sale prices go to `PriceIndex` (DataStore `BrainrotSkip_PriceIndex_v1`, 7-day median per `Name|Mutation`). |
| 6 | **Whether prices persist** | **No.** Listings, prices and ownership of a stand are per-server memory: lost on server shutdown, on the seller leaving (`PlayerRemoving → releaseBooth`), on `Unclaim`, and on the 3-second prune. Only *completed* sale prices persist (PriceIndex). |
| 7 | **What happens on failure / disconnect** | Profile never loaded (`__noSave`): refused up front for either side. Seller gone at buy time: `releaseBooth` and a silent return (**the buyer gets no toast** — a small UX gap to fix in the same edit). Buyer disconnects mid-purchase: the handler runs to completion server-side (their data is still in memory until `PlayerRemoving`); the leave-save then persists the result. `Save` returns false after the swap: `[BoothAudit] SAVE FAILED …` with everything needed to hand-restore, then a 30-second background retry loop; **never rolled back** ("the other half may already be saved"). Server crash between the swap and a successful save on one side: that side's half is lost or duplicated — a documented, accepted risk of the existing design, unchanged by gems. |
| 8 | **Two buyers on the same listing** | Impossible to double-sell: from the first check to `table.remove(booth.listings, pos)` (L429) there is **no yield**, so the second `BoothBuy` runs only after the first finishes and hits `if not listing → toast "That item was just sold or removed."` (L353). No double debit, no double credit. The same property carries over to gems because `TrySpend` and `Award` are non-yielding. |
| 9 | **How stale listings are rejected** | Three layers: (a) the 3-second prune tick drops listings the owner no longer owns (`CountOwned(name) < listed`) and rebuilds tags whose resolved copy changed; (b) at buy time `CountOwned(sellerData, name) < 1` → listing removed, buyer toasted "no longer available"; (c) `PlayerRemoving` releases the whole stand. After D2 all three key on the listing's `Uid` (present, unplaced-or-allowed, not `PlotFav`) instead of a name count. |
| 10 | **Every change required** | §7.3. |

### 7.2 Gems as they exist (inspected; not changed)

`data.Darrels` (integer, default 0, **no cap**); player-facing word "Gems"; HUD glyph 💎 (`EmeraldHUDClient` draws `"\u{1F48E} " .. NumberFormat.Short(n)`). `EmeraldService` is the only authority: `Award(player, n, reason)` and `TrySpend(player, n, reason)`, both non-yielding, integer-only, both push `EmeraldUpdate` + `PlayerDataManager.PushUpdate`; `TrySpend` returns false when `Darrels < n`; no partial debit; no fee; no player-to-player primitive. Faucets (untouched): dailies 16–40 per quest (~86/day), weeklies 22–52 (~188/week), perfect throws 2 each capped 60/day, quest/season rewards; Robux packs 80 / 180 / 400 / 1000 gems for R$99 / 199 / 399 / 899. An active free player earns ~150–200 gems/day. Consequences for booths: prices live in the tens to thousands; `MAX_PRICE = 1e9` and the `m/b/t` price suffixes are cash-era. **Proposal (validation, not a rate — owner picks): `MAX_GEM_PRICE = 1,000,000`, suffix `k` only.** Gems are Robux-backed, so a 1-gem listing of a Common is a gem-gifting channel between accounts — the loop the owner wants; `PriceIndex`'s one-vote-per-pair rule keeps such trades from setting prices, and every gem move is logged (`[Emeralds] ±n`).

### 7.3 The migrated purchase — server-authoritative and atomic (no yields from the first check to the last write)

```
BoothBuy(buyer, boothIndex, listingId):
 1  listing by Id                              → "just sold or removed"
 2  seller online                               → releaseBooth; toast buyer (new)
 3  buyer ~= seller                             → refused (the current rule, kept)
 4  buyer within BUY_RADIUS of Counter          → "walk up"
 5  both profiles loaded, neither __noSave      → refused
 6  BagConfig.HasBrainrotSpace(buyerData, 1)    → refused, nothing moved
 7  seller's entry with listing.Uid exists and is transferable (§8)   → prune listing, "no longer available"
 8  unique cap (WithinUniqueCap by Name)        → refused
 9  price = listing.Price (the SERVER copy); integer; 1 ≤ price ≤ MAX_GEM_PRICE   → refused
10  EmeraldService.TrySpend(buyer, price, "booth:"..listingId)   -- DEBIT FIRST; false → "Not enough Gems", nothing moved
11  ok, record = BrainrotMover.Transfer(seller, sellerData, listing.Uid, buyer, buyerData, "booth:"..listingId)   (§8)
    if not ok → EmeraldService.Award(buyer, price, "booth-refund:"..listingId); warn; prune listing; return
12  EmeraldService.Award(seller, price, "booth-sale:"..listingId)   -- CREDIT
13  table.remove(booth.listings, pos); PriceIndex.RecordSale(record.Name, record.Mutation, record.Size, price, buyer.UserId, seller.UserId)
14  InventoryHandler.SyncBackpack both; refreshDisplays(booth); pushManageState(booth)
15  PushUpdate both; Save both; on a failed Save: [BoothAudit] line (now with gems) + retrySave — never roll back (as today)
```

Atomicity: 1–9 are reads; 10 is the only step that can fail after them and it fails *before* anything moves; 10–13 contain no yield, so nothing can interleave and the second buyer sees "just sold". A `Transfer` miss at 11 (impossible without a yield, guarded anyway) refunds through `Award`, which cannot fail on a positive integer — the buyer's gems are never consumed by a failed purchase; the seller is credited only after the buyer holds the item; the listing is removed before any yield; both saves and the audit line keep their shape. Server authority is unchanged: the client still only asks.

### 7.4 Every change, by file

| File | Change | Owner |
|---|---|---|
| `ServerScriptService.Modules.BoothHandler` | require `EmeraldService`; replace L393/L427/L428 with the §7.3 sequence; `MAX_PRICE` → `MAX_GEM_PRICE`; `formatMoney` → `NumberFormat.Short` with the 💎 glyph in the seven `$` strings (L133, L142, L310, L394, L450, L457, L458); `BuyPrompt` attribute `Currency = "Gems"`; toast the buyer when the seller is gone (step 2) | economy |
| `StarterPlayer.StarterPlayerScripts.BoothClient` | L447, L661 `"$"` → 💎; price box placeholder `"price (e.g. 2.5k)"` → `"gems (e.g. 250)"`; `parsePrice` suffixes `k` only (L34–43) | Pete (UI) |
| `ServerScriptService.Modules.PriceIndex` | store `BrainrotSkip_PriceIndex_v1` → `_v2` (cash-era observations must not seed gem medians); `MAX_PRICE` 1e12 → 1e7; key `Name|Mutation` → `Name|Mutation|Size` (§8) | economy |
| `StarterPlayer.StarterPlayerScripts.IndexClient` | L411 `"PAID $%s"` → `"PAID 💎%s"` | Pete (UI) |
| `ServerScriptService.ItemStatsService`, `Modules.EmeraldService`, `Modules.PlayerDataManager`, `EmeraldPackConfig`, `ProductRegistry`, quest/season configs | **nothing** | — |
| `Modules.TradeHandler` + `TradeClient` | **D1b — undecided.** Trades still carry a `Cash` sweetener (`SetCash`, `offer.Cash`, netted at execute, L118–119 + L293 audit, client L499/600/601). Keep Cash in trades, migrate to gems (recommended, as a second step: `TrySpend` both, `Award` both, same netting), or remove currency from trades. | owner |
| `docs/trading-world/*` | price plate = 💎 + `NumberFormat.Short` | TW-01 |

Migration risk: low — nothing about listings or offers is persisted; the world is held back so no live listing exists; the one persistent artefact (`PriceIndex`) is handled by the store rename. Exploit surface: unchanged or smaller — the debit is the same primitive the egg shop trusts.

## 8. Unified Brainrot transfer / Size-preservation plan

### 8.1 Identity fields on a Brainrot (canonical catch entry, `ThrowHandler` L1287–1301, plus flags written elsewhere)

| Field | Kind | Travels with the item? | Written by |
|---|---|---|---|
| `Name` | base identity (→ rarity via `BrainrotConfig`) | **yes** | every insert |
| `Mutation` | Golden / Diamond / Rainbow / weather variants | **yes** | catch, fusion |
| `Size` | Huge / Massive / nil (`SizeConfig`, independent axis) | **yes** | catch (`sizeVariant`), `StealService.toBag` |
| `Serial`, `MintedAt` | mint identity for tracked classes (`MintRegistry`) | **yes** | catch |
| `Uid` | **per-profile counter** (`PlayerDataManager.TakeUid` = `data.NextUid++`) | **no — reissued on receipt** | every insert |
| `PadIndex` | placement on the owner's camp | no — reset (free pad or nil) | spawner / placement |
| `Pending` | accrued income | no — drained to the giver first (`DrainPending`) | income loop |
| `PlotFav` | raid/sell lock ("never sell") | no — reset; and it **blocks** transfer | `PlotFavoriteService` |

Why the `Uid` cannot cross owners: it is unique only inside one profile; the receiver's counter may already have issued the same number, and every tool, prompt and pad on the receiver's side addresses entries by that per-player `Uid`. The item's global identity is `(Name, Mutation, Serial, MintedAt)` for tracked classes and `(Name, Mutation, Size)` otherwise. A global provenance id (`Guid = HttpService:GenerateGUID(false)` at every insert) is optional and additive — separate approval, no gameplay effect.

### 8.2 The broken paths and the working one (exact functions)

| Path | Selector | Record carries `Size`? | Receiver entry gets `Size`? | Net effect today |
|---|---|---|---|---|
| **Booth sale** — `BoothHandler.BoothBuy` L417/L422 | `BrainrotMover.Take(seller, data, name)`: least-`Mutations.Mult` copy by **name**, size ignored (ties = inventory order) | **no** (`{Name, Mutation, Serial, MintedAt}`, L90) | **no** — `Give` L146–154 inserts `{Name, Mutation, Serial, MintedAt, PadIndex, Pending, Uid}` and passes `record.Size` only to `BrainrotSpawner.Spawn` (the visual) | the seller may lose the Massive; the buyer gets a normal one |
| **Direct trade** — `TradeHandler.executeTrade` L170/L172 | `Take(name)` | no | no | same |
| **Gift** — `GiftService` L223/L228 | `TakeByUid` (the held Tool's Uid) | **yes** (L112–115) | **no** (`Give`) | the receiver sees a Massive on the pad until rejoin/respawn, then it is normal. **The "Uid path preserves Size" belief holds only for the visual.** |
| **Raid** — `StealService.doTransfer` L137 → `toBag` L116 | `TakeByUid` | yes | thief: **yes** (`toBag` writes `Size`); victim put-back on unique-cap failure L146 → `Give` → **no** | thief keeps it; a returned item loses Size |
| Fusion — `FusionHandler` L76 | name + mutation match, unplaced copies; fused entry L120 has no `Size` | consumes | — | can consume a Huge copy silently |
| Offering — `OfferingHandler` L78 | name, least-mult, size ignored | consumes | — | can burn a Huge copy silently |
| Sell stall — `SellHandler` L105 / `SellValue.SelectCheapest` | Uid, or name **refusing mutated/oversized copies** | — | — | **correct — the precedent** |
| Quest rewards (`Give({Name})`, direct inserts) | n/a | n/a | n/a | fine |

**Data lost today:** `Size` on every path except the raid's thief insert; on name-based paths also *which copy* (mutation is preserved only because `Take` prefers the least-mutated copy; a seller with two Golden copies of different sizes still cannot choose).

### 8.3 The unified ownership-transfer contract (recommended; not implemented)

```lua
-- BrainrotMover (proposed surface). ONE definition of what an item IS and ONE way to move it.
IDENTITY_FIELDS = { "Name", "Mutation", "Size", "Serial", "MintedAt" }   -- persistent identity: new modifiers are added HERE, once
OWNER_FIELDS    = { "Uid", "PadIndex", "Pending", "PlotFav" }            -- owner state: never copied, always reissued/reset

type TransferRecord = { Name: string, Mutation: string?, Size: string?, Serial: number?, MintedAt: number?,
                        FromUserId: number, FromUid: number, Reason: string }

IdentityOf(entry) -> table                    -- copies IDENTITY_FIELDS only (whitelist, so owner state can never leak)
IsTransferable(entry) -> ok, reason           -- false when entry.PlotFav (locked = never leaves); placed copies stay allowed as today
CanReceive(receiverData, record, outgoing) -> ok, reason   -- unique cap (WithinUniqueCap, netted) + bag space (BagConfig), PRE-FLIGHT
TakeByUid(giver, giverData, uid, reason) -> TransferRecord?   -- the ONLY take: drain Pending, remove pad visual on every camp, remove the entry
Give(receiver, receiverData, record) -> newUid                -- inserts { IdentityOf(record)…, PadIndex = FindFreePad or nil, Pending = 0, Uid = TakeUid } and spawns with record.Size
Transfer(giver, giverData, uid, receiver, receiverData, reason) -> ok, recordOrReason
   -- IsTransferable → CanReceive → TakeByUid → Give, with NO yield inside; if Give cannot run, Give the record back to the giver (cannot fail); one log line:
   -- [Transfer] reason=%s from=%d uid=%d -> to=%d newUid=%d name=%s mut=%s size=%s serial=%s
```

**Invariants every caller relies on:** (I1) no yield inside `Transfer`; (I2) the receiver's new entry equals `IdentityOf(giver's entry)` plus fresh owner fields — `Size`, `Mutation`, `Serial`, `MintedAt` are never dropped again because `Give` builds from the whitelist; (I3) the giver's entry is removed exactly once, by `Uid`; (I4) `Pending` is drained to the giver and the pad visual removed from every camp before removal; (I5) a `PlotFav` copy never transfers; (I6) the `Uid` never crosses owners — `FromUid`/`FromUserId` ride in the record for the audit line only; (I7) unknown future fields are *not* silently carried (adding a modifier is one line in `IDENTITY_FIELDS`, deliberately); (I8) `Take(name)` is retired from every transfer path; if a name-based *consumption* remains (fusion, offering) it adopts the sell stall's rule — never pick a mutated or oversized copy by name, refuse when only those exist.

**Ownership state after a transfer:** receiver — fresh `Uid`, `PadIndex` = a free pad on their camp or nil (bag), `Pending = 0`, `PlotFav = nil`, backpack Tool rebuilt (`SyncBackpack`); giver — entry gone, pad visual gone on every camp, `Pending` cashed in, backpack rebuilt.

**Callers after the change:** booth (`listing.Uid`), trade (offers = sets of Uids, `Items[uid] = true`, details from the entries), gift (already Uid), raid (`toBag` via `IdentityOf`; put-back via `Give`), quest rewards (`Give({Name})` still accepted). Listings: `{ Id, Uid, Name, Price, ListedAt }`, validated at `Add` (owned by seller, `IsTransferable`, not already listed), re-validated at buy (§7.3 step 7), pruned every 3 s when the Uid is gone or becomes `PlotFav`. `refreshDisplays` resolves the exact entry and writes `Rarity, Mutation, Size, Serial` on `BuyPrompt` — the only source a label may read (§11). `PriceIndex` keys gain `|Size` (a Golden Massive is its own market) in the `_v2` store D1 creates.

**Files:** `BrainrotMover` (the contract), `BoothHandler`, `TradeHandler`, `GiftService` (call `Transfer`), `StealService` (`IdentityOf` in `toBag`; put-back via `Give`), `FusionHandler` + `OfferingHandler` (skip oversized/mutated by name), `PriceIndex` (`|Size`) — economy; `BoothClient` + `TradeClient` pickers become per-copy like the Bag's `BrainrotCard` grid — Pete. **Migration risk:** low — no save migration (`Size = nil` already means normal; nothing persisted references listings or offers). **Backward compatibility:** every existing entry works; old `BoothList`/`TradeAction` payloads without a `Uid` are refused server-side, and no live client sends them while the island is held back. Rarity odds, `SizeConfig` chances and multipliers untouched.

**Test cases (Play, two accounts or the `DataUpdated` seam):** T1 Massive sold by Uid → buyer's saved entry keeps `Size` after rejoin, seller keeps the normal copy, gems ±p · T2 same via trade · T3 gift (fails today) · T4 raid put-back (fails today) · T5 Golden + Massive stack · T6 Serial/MintedAt regression · T7 old save with `Size = nil` · T8 listing a `PlotFav` copy refused · T9 listed Uid gifted away → pruned ≤ 3 s · T10 two buyers, one frame → one debit, one credit · T11 buyer short by one gem → refused, no debit · T12 forced `Transfer` miss after debit → refund + audit · T13 `__noSave` either side · T14 self-buy · T15 prices 0, 1.5, NaN, > max, "2m" · T16 bag full / unique cap before the debit · T17 save failure → audit with gems, retry, no rollback · T18 `BuyPrompt` carries `Rarity, Mutation, Size, Serial, Price, Currency, SellerName, SellerUserId` · T19 fusion/offering with only Huge spares → refused · T20 `PriceIndex _v2` empty, keys with `|Size`.

## 9. ComingSoon / teleport bypass plan

**Exact bypass (read live, `ServerScriptService.TeleportService` L197–230):**

```lua
remotes.TeleportTo.OnServerEvent:Connect(function(player, destination)
	…
	elseif destination == "Trade" then
		teleportCharacter(player, TRADE_POS, FORWARD)          -- L203–204: no gate of any kind
```

**Client/server path:** a client fires `ReplicatedStorage.Remotes.TeleportTo:FireServer("Trade")` (no shipped LocalScript does — `ClientMain` fires only `Throw`, `Shops`, `Plot`, `OpenPlot`; `WorldsPanel` fires world ids such as `"Trading"`) → the server handler above → `teleportCharacter` pivots the character to `TRADE_POS` on the server → `BoundsGuard` accepts the position (the Trading region is valid) → the player stands on the closed island and can claim stands and trade. The two intended doors are gated **server-side**: the walk-through `TradePortal` via `passesLock` (`WorldTravelConfig.IsDestComingSoon(dest)` is its first check, refusal text from the portal's `ComingSoonMessage`), and the Worlds board via `travelToWorld → WorldTravelService.CanTravel → IsUnlocked` (false for a `ComingSoon` world).

**Client-only or server-authoritative?** The gates that exist are **server-authoritative** (the `WorldsPanel`'s greyed row is cosmetic on top of a server refusal). The hole is not a client-only check — it is a **missing server check** on a third, dead route.

**Safest enforcement location:** inside `TeleportService`, at the one place every route resolves a portal destination. Concretely: (1) **delete the `"Trade"` branch** (L203–204) — nothing uses it, `"Trading"` through `travelToWorld` is the supported route; (2) keep `IsDestComingSoon` in `passesLock` and `CanTravel`; (3) add a defensive `if WorldTravelConfig.IsDestComingSoon(destName) then notify(...) return end` in `travelToWorld` *before* `CanTravel` for symmetry, and a `warn` for any unmatched destination string so future spoof attempts show in the server log. **Recommended fix = (1)+(3).** Server-authoritative by construction; one config line (`ComingSoon = true`) opens or shuts every door.

**Scripts affected:** `TeleportService` only (`WorldTravelConfig` already exports `IsDestComingSoon`). The file is currently being edited by the World 2 lane (+46 B live vs mirror) — the edit is applied through that lane or after it lands, then mirrored byte-exact per the team rule. Not applied in this pass.

## 10. Updated NPC-01 role handoff

`docs/trading-world/npc-roles-for-npc01.md` updated with an "Inspection update" block: roles, count and tiers **unchanged** (seven for v1: Exchange Host, Gem Broker, Rare Brainrot Curator, two Booth Attendants, Collector, Ambient Trader pair; optional Angler and two Vault Guards). Placement now confirmed against measured ground (P = 2002.4; the Vault plateau +6; the balcony +12). Two location notes from the inspection: the Host's mark (8000, P, 7948) is where today's MARKET arch pillars stand (z 7942) — clear ground once the arch is replaced, 18 studs inside the Great Arch; the Angler's pier end (8120, P, 8000) sits under the kept `Guardian_TungTungTungSahur` at (8138, 8000), and the Colossus Walk under `Guardian_TralaleroTralala` at (7862, 8000). District per role, purpose, interaction and tier are in the file; TW-01 defines nothing about appearance, rigs, faces, outfits, props' art or animation.

## 11. D4 — decision request

**Restated verbatim from the Phase 1 report, §C.1:**

> | **D4** | **Listing presentation layer.** (a) client-only `BoothDressingClient` reading replicated instances (no server change — recommended), or (b) a presentation-only edit to `BoothHandler.refreshDisplays` (bigger billboard, `MaxDistance`, tier word) — touches a frozen economy file. | Owner + economy | (a). |

**Available options and their consequences** (D1 and D2 now reopen `BoothHandler` anyway, which changes the trade-offs):

| Option | What it is | Consequences |
|---|---|---|
| **(a) Client-only overlay** | `BoothDressingClient` hides the server's 130×40 billboard locally and draws the plate, model preview and mast colour from `BuyPrompt` attributes + `ListingDisplay.Color`. `BoothHandler` untouched beyond D1/D2. | No further economy-file edit; ships independently of Pete's UI work. But rarity/mutation/size must be **parsed out of `ItemName` text** unless D2's attributes land (fragile; a size label is not possible at all until D2), the server keeps building a GUI and a Neon cube nobody sees (72 wasted BillboardGuis on a full server), and two systems draw the same stand. |
| **(b) Server presentation edit** | `refreshDisplays` draws a bigger billboard with `MaxDistance`, tier word, mutation/size lines. | Every visual tweak is an economy-file edit reviewed as such; no 3D preview (the server must not clone a 218-model preview for every client); replicated GUIs for every listing; presentation and money in one function forever. |
| **(c) Split: server = data, client = presentation** *(recommended)* | During the D1/D2 edit the server **stops** creating the BillboardGui and the Neon cube and instead writes identity attributes on `BuyPrompt` (`ItemName, Rarity, Mutation, Size, Serial, Price, Currency, SellerName, SellerUserId`) while keeping `ListingDisplay` as an invisible anchor part (so the prompt has a parent and `BUY_RADIUS` maths is unchanged). `BoothDressingClient` renders everything: price plate (💎 + `NumberFormat.Short`, `MaxDistance` 120), local `BrainrotModels` preview with `MutationFX` + `ScaleTo`, mast state. | ~30 lines in `refreshDisplays` land in the same economy PR as D1/D2 (one review, not two); the attributes are the **only** source of truth for labels, so an honest size/mutation label is structurally guaranteed and impossible before D2; zero replicated GUIs; the 3D preview costs each client only what it looks at; one client script (TW-01) that the UI lane can restyle later. Risk: the client script must be streaming-safe (`DescendantAdded` on `TradingCenter.Booths`, the `StallPrompt` pattern) and must degrade to "no plate" if an attribute is missing. |

**Recommendation: (c).** TW-01 does not proceed on any of the three until you choose.

## 12. Phase 2 implementation order (for approval — nothing started)

Two tracks in parallel; the world track never touches an economy file, the economy track never touches geometry.

**Track W — world (TW-01, Studio + generator, Edit windows only):**
1. Owner saves a `.rbxl` off Roblox. Snapshot per Phase 1 §A.14 step 1: clone `TradingWorld`, `TradingCenter`, `HubPortal` into `ServerStorage.TradingWorldBackups_<date>`; copy the `Source` of `TeleportService`, `BoundsGuard`, `WorldTravelConfig`, `SkipLoop`, `CoveDriver`, `CenterpieceSpinner` into `AuditBackups.PreGrandExchange_<date>`; write `docs/trading-world/snapshot-<date>.md` with every CFrame from §1; diff `_MANIFEST.txt`.
2. `ServerStorage.TradingWorldBuild.Generator` v1 — one numbers table, `ClearAll()`, `Contracts()` self-check printing `OK 30/30`, output into `GameWorld.TradingWorld_GE` / `TradingCenter_GE` beside the live island.
3. Landing (re-skin on the measured datums), causeway 24 wide with masts, Great Arch, totems.
4. Exchange Hall: sunken floor, steps, pylons, arches, balcony, crown, ramps, gem anchor with `Spin`, `TradeZone_GE` 46×22×46.
5. Arcade module × 24 + Vault module × 6 with contracts; lane stripe; Records terrace with static boards; piers; rim; wadeable moat; outer ring; barrier r150; Landing U-wall; `Guardians` moved under the new dressing container unchanged.
6. `ExchangeDriver` (CoveDriver conventions, `C`, 400-stud gate, same tag names) and `SkipLoop` constants (`R = 106`, `WATER_Y = 2001.4`) — mirrored byte-exact; delete the stray unanchored part.
7. `TradingWorldBackups_<date>.Rollback` written **before** cutover; **revert drill on the greybox (V10)**.
8. Cutover rename with the owner present (`TradingCenter` ↔ `_GE`, `TradingWorld` ↔ `_GE`, `HubPortal` re-pivoted, `HubPortalVault` added); Play probes V1–V15; phone captures; mirror push; `NpcPost_*` marks handed to NPC-01; the `BuyPrompt` attribute contract handed to Pete.

**Track E — economy (economy owner, separate branch, one PR in three commits):**
1. §8 contract (`IdentityOf`, `IsTransferable`, `CanReceive`, `Transfer`; `Give` writes identity; Uid-based listings and offers; fusion/offering guards; `BuyPrompt` attributes) — tests T1–T9, T18–T19.
2. §7 gems (purchase sequence, wording, `MAX_GEM_PRICE`, `PriceIndex _v2` with `|Size`) — tests T10–T17, T20. D1b (trades) when decided.
3. §9 gate in `TeleportService` after the World 2 lane's edit lands.
Then Pete: `BoothClient`/`TradeClient` per-copy pickers, gem wording, `IndexClient` label; then D4 (per your choice).

**Launch gate (owner):** Track W probes green · Track E tests green · NPC-01 v1 roles on their posts · `WorldsPanel` row copy → delete `ComingSoon = true`.

## 13. Risks / conflicts with active lanes

| Lane | Touchpoint | Risk | Mitigation |
|---|---|---|---|
| **Beast — World 2 (paused)** | `TeleportService` is +46 B live vs the mirror (their in-flight edit); their `PreWorld2Blockout_2026_09_19` backups and generator/rollback pattern | the D9 edit and any `TRADE_POS` change collide with their unpushed work | D9 waits for their push or goes through them; `TRADE_POS` is kept (no edit); TW-01's generator/rollback copy their conventions, no shared files |
| **Pete — UI / mobile / shop** | owns `BoothClient`, `TradeClient`, `IndexClient`, `WorldsPanel`, `InteractionPrompt*` (round-3 files in flight in `ui-foundation`'s dirty tree); the Booth/Trade cards are on their future `BrainrotCard` migration list | D1/D2 need per-copy (Uid) pickers and gem wording in their files; D4(c) needs them to consume the attribute contract; a simultaneous BrainrotCard migration of the same panels would double-edit | sequence: economy PR first (server accepts Uid payloads), then their UI change against the frozen attribute contract in §8/§11; TW-01 never edits their files |
| **NPC-01 — character overhaul** | worktree `../skip-a-brainrot-npc` at `86c6cf5`; will place rigs | they must not place anything on the **current** island (it is replaced whole) | posts are handed over only after Track W step 8; the handoff file says so |
| **Balkan — Bag round 4 (frozen) / source-sync** | this branch is based on `source-sync-audit`; the mirror rule (GitHub canonical, byte-exact pushes, `_MANIFEST.txt`) | merging `trading-world-rework` carries their three sync commits; every Studio script touched in Phase 2 must be pushed back byte-exact | docs-only so far; Phase 2 script edits (`ExchangeDriver`, `SkipLoop`) follow the rule with a manifest diff |
| **Duck — World 1** | owns the valley `TradePortal` (`Dest = "Trade"`, `ComingSoonMessage`) and the lodge where `LeaderboardBoards` are built | none if the portal keeps its attributes; D5 (boards on the island) touches `LeaderboardBoards.Build`, which they may be moving | D9 does not touch the portal; D5 stays static in Phase 2 |
| **World 3 refinement** | Gardens region X 6440–9560 · Y 900–1900 · Z −9560…−6440 | no spatial overlap with Trading (Z 7375–8725); `GardensReturnPortal` oddly sends to `Tundra` — not TW-01's | none |
| **Economy owner — unassigned** | `BoothHandler`, `TradeHandler`, `BrainrotMover`, `GiftService`, `StealService`, `FusionHandler`, `OfferingHandler`, `PriceIndex` | the Track E PR has no named owner in the lane list | owner to assign; TW-01 can draft the PR against §7–§9 if told to |
| **Shared `Lighting` / weather / day-night** | `WeatherClient` owns `Brightness` and Atmosphere during events; `DayNightCycle` runs | a `TradingGrade` that writes Atmosphere during an event flickers the sky | follow `TundraAtmosphere` exactly (private CC + `ExposureCompensation`; Atmosphere only when no event); Phase 3 |
| **Team Create / playtests** | the 2026-08-09 and 2026-09-19 logs show other sessions flipping Edit → Play with Edit windows as short as 2–54 s | generator runs and the cutover need a quiet Edit window; a Play start mid-generation leaves a half-built `_GE` | schedule builds with the owner; the generator is idempotent (`ClearAll()` then rebuild) |
| **Streaming** | radii unreadable from the command bar; both island folders stream normally | a client far away never has the island; `TradeClient` waits on `WaitForChild("TradeZone")` (fine); any client dressing must bind on `DescendantAdded` | D4(c) script uses the `StallPrompt` pattern; read the radii from the Properties panel before Track W step 8 |

---

*Stopped for approval. Nothing in Studio was modified; Phase 2 has not begun.*
