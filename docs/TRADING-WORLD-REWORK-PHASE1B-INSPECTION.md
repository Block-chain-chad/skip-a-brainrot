# TRADING WORLD REWORK — Phase 1B: Studio inspection + migration plans (lane TW-01)

**Date:** 2026-09-19 · **Branch:** `trading-world-rework` · **Follows:** `docs/TRADING-WORLD-REWORK-PHASE1.md` (approved; Concept 1 selected)
**Studio session:** read-only, Edit mode, PlaceId `78783087742939`. Every call was a read (`GetChildren`, properties, attributes, `ReadVoxels`, raycasts, byte counts). **Nothing was moved, deleted, edited, saved or published.** The capture tool set the editor camera temporarily; the 3D view rendered black because Studio was not the foreground window (the same "render frozen while backgrounded" the 2026-08-09 log hit) — captures are the one open item, see §1.4.

Decisions received: **D1 = Gems** (booths are a player-to-player gem transfer tied to the sale; do not convert back to Cash; do not change gem faucets, Robux prices, quest rewards or fees). **D2 = fix Size loss before launch** (all ownership transfers preserve the complete identity). **D9 = launch blocker, document only.** **D4 = restate, do not infer.**

---

## 1. What the existing Trading World actually looks like (measured)

### 1.1 Corrections to the Phase 1 picture

| Phase 1 assumption (from docs) | Live Studio (2026-09-19) | Consequence |
|---|---|---|
| `TradingWorld` / `TradingCenter` are Models with `ModelStreamingMode = Persistent` | **Both are Folders.** `ModelStreamingMode` does not exist on a Folder; the island streams like anything else. | The "Persistent" contract is not real today. Booth/zone binding works because the server sees everything; `TradeClient`'s `WaitForChild("TradeZone")` simply waits until the zone streams in on arrival. The new build decides streaming explicitly (§2.2). |
| 12 booths, `BoothIndex` 1–12, verified 12/12 on 2026-08-09 | **6 booths exist: `Booth7`–`Booth12`** (`Booths` folder = 96 descendants = 6 × 15 + 6). Booth1–6 are gone. | `BoothHandler` adopts 6 and warns for nothing (missing booths are simply absent). Whatever removed 1–6 happened after 2026-08-09 and was never logged — rollback source for them is `ServerStorage.PreCove_Backup_2026_08_02.TradingCenter_OLD` (218 descendants). |
| `HubPortal` at (7981, 2006, 7830), west of the deck | **`HubPortal.PortalTouch` is at (8000, 2006, 7815.7)** — 8.4×11.2×2.8, on the axis, **2.3 studs behind `TRADE_POS` (8000, 2004.6, 7818)**. | A player who steps backward on arrival touches the way home. Marginal on arrival itself (the touch part ends at z 7817.1, the root part starts at 7817). The new Landing separates arrival and return by ≥ 8 studs. |
| Terrain seabed under the island | **No solid terrain anywhere probed** (9 columns, X 7400–8700, Z 7500–8500): only water, surface **y 1999.5** everywhere. The "seabed" is a Part (`Island.Seabed`, cylinder r120, top y 1999.0). | The island is parts floating in a terrain ocean. No terrain work in Phase 2; the water is free. |
| `StandPrompt` reach 10 | `StandPrompt.MaxActivationDistance = 8`, `ObjectText "Market Stand"`, hold 0.3 | `BuyPrompt` (server-made) is the one with reach 10. |

### 1.2 Datums and geometry (absolute; N = +Z, E = −X)

| Thing | Measured | Note |
|---|---|---|
| Plaza disc `Island.Plaza` | cylinder Ø124 (r62), **top y 2002.4** (raycast at C hits it at 2002.4) | walkable |
| Water ring `Island.RingWater` ×16 | Glass, Transparency 0.35, **CanCollide false**, top y 2002.0, r ≈ 62–88 | **a fall trap**: no collision, seabed 3.4 studs below; bridges are the only crossings |
| Outer ring `Island.OuterRing` ×16 blocks 30×4.8×47 | top **y 2002.4**, r ≈ 88–118 | walkable; booths stand here |
| Gazebo (`TradingCenter`) | `Floor` 56×1×56 top **y 2000.0** (buried 2.4 under the plaza), `Podium` top 2005.6, four pillars 28 tall, sign "🔄 TRADING CENTER" 30×5 at y 2033 | the gazebo floor is invisible inside the plaza disc |
| `TradeZone` | 26×26×26 at (8000, 2007, 8000), look −Z, anchored, CanCollide false, transparent | as documented |
| Booths 7–12 | counters 10×3.2×2.2 at y ≈ 2005; `Display1–3` plinths 1.6×0.4×1.6 at y ≈ 2006.8 (cube lands at ≈ 2008.5, head height); `SignBoard` 9.6×1.9×0.4 at y ≈ 2009.7, SurfaceGui Face Back, 50 px/stud, TextScaled; booth pivots pitched ≈ 11° (the models lean); positions (x, z): B7 (8040, 8101) · B8 (8018, 8107) · B9 (7984, 8109) · B10 (7935, 8079) · B11 (7959, 8103) · B12 (7920, 8064) — angles 68°–141° about +X, r 103–110 | the northern half of the documented 35°–145° arc |
| Arrival deck `ArrivalDeck` | `DeckTop` 46×2.4×44 at (8000, 2001.2, 7830) → top 2002.4, z 7808–7852; `ArrivalPad` cylinder Ø12 top **2002.8** at (8000, ·, 7818); 4.4-stud `DeckEdge` cylinders = a 1-stud lip, jumpable; two lamp posts | `TRADE_POS` drops the character 1.8 studs onto the pad — correct |
| Causeway | **7 studs wide**, planks z 7852–7882 rising 2002.8 → 2003.8 → 2002.8, rope rails | narrow for a 60-player server |
| Market arch | at **z 7942** (south bridge, r 58 — the plaza entry), pillars 12.6 tall, "MARKET" sign 16×4.2 at y 2018 | the cove doc's "north" arch is on the south approach |
| Colossal tusk arch | `CoveDressing.ColossalArch` 71×69×11 centred (8000, 2032, 7878), apex ≈ y 2066 | over the causeway |
| Spire | `SkippersSpire` at (8000, ·, 8140), 904 studs tall (beam to y 2902) | north cliff |
| Guardians | six statues at **r ≈ 138**: `Guardian_TungTungTungSahur` (8138, 8000) 0° · `Guardian_BombardiroCrocodilo` (8063, 8109) 60°, **87×48×76** · `Guardian_LaVaccaSaturnoSaturnita` (7931, 8120) 120° · `Guardian_TralaleroTralala` (7862, 8000) 180° · `Guardian_BrrBrrPatapim` (7931, 7881) 240° · `Guardian_BallerinaCappuccina` (8069, 7881) 300°; 214 descendants total, six breathing Highlights | **reusable as-is** (see §2) |
| `CoveBarrier` | 14 invisible walls 2×40×50 on r ≈ 121, top y 2038.4, open on the south | the Landing deck sits outside it |
| `EternalSkip` | stone + 3 rings at r68 | the orbit crosses the new promenade; retune `R` |
| `CoveDressing` totals | 468 descendants: WaterDressing 40, FloatingIslets 42 (up to y 2164), ColossalArch 55, SkippersSpire 19, AmbienceAnchors 10, WorldEdge 30, Guardians 214, Monuments 49 (beams to y 2151), `CoveDriver`; tags in use CoveOrbit 7 · CoveSpin 2 · CoveBreatheT 2 · CoveBreatheH 6 · CoveBob 8 · CoveAmbience 5 · CoveFallScroll 0 | |
| `TradingWorld` totals | 913 descendants: **618 BaseParts** (5 MeshParts, 58 Neon), 15 lights, 6 emitters, 6 Highlights, 20 SurfaceGuis, 6 Sounds, 2 Scripts (`SkipLoop`, `CoveDriver` — both mirrored) | |
| `TradingCenter` totals | 122 descendants: 81 BaseParts (23 Neon), 14 SurfaceGuis, 0 scripts | |
| Stray | `TradingWorld.Part` 4×1×2 at (8091, 2038.9, 8080), **unanchored**, CanCollide true, no attributes | junk; delete in Phase 2 |
| `Spin`-attribute parts | **none** — `CenterpieceSpinner` runs an empty list every Heartbeat | reuse the attribute for the Grand Gem |

### 1.3 Server, streaming, lighting, spawn, travel (measured)

- `Players.MaxPlayers = 60`, `PreferredPlayers = 60`.
- `workspace.StreamingEnabled = true`; the radii are plugin-security properties and could not be read from the command context (`StreamingMinRadius is not a valid member` from a command-bar thread). Read them from the Properties panel when the owner is at the machine; assume defaults (min 64 / target 1024) until then.
- `Lighting` (global, shared by every world): ClockTime 14 at edit time (a `DayNightCycle` script runs live), Brightness 2.42, ExposureCompensation 0.14, Ambient (88,100,94), OutdoorAmbient (139,151,157), Atmosphere density 0.22 / haze 0.30 / glare 0.12, ColorCorrection (contrast 0.13, saturation 0.12) enabled, Bloom 0.45 / threshold 1.0, SunRays enabled, FogEnd 2500, Sky "Sunny Day". **Two per-world grades already exist and are disabled at rest: `Lighting.TundraGrade` and `Lighting.GardensGrade`** (ColorCorrectionEffects). `StarterPlayerScripts.TundraAtmosphere` is the pattern: a client script fades a private ColorCorrection + `ExposureCompensation` + Atmosphere while the player is inside the world's BoundsGuard box, and never touches `Brightness` (WeatherClient owns it). A `TradingGrade` + `TradingAtmosphere` pair is the right way to give the Exchange its own warm, higher-contrast look without editing globals (Phase 3, pattern-conformant).
- Only one `SpawnLocation` in the place: `Workspace.SpawnLocation` at (0, 33, −180), Neutral. Dying anywhere returns you to the valley.
- Portals under `GameWorld.Portals`: `TradePortal` (valley, (0, 11.2, −303.1), `Dest = "Trade"`, `PlaceName = "the Trading Island"`, `ComingSoonMessage = "🤝 Trading is coming soon — the island is shut for work."`, no `RefuseX`) · `HubPortal` (island, `Dest = "Hub"`) · `TundraPortal` · `TundraReturnPortal` (`Dest = "Dungeon"`) · `DepthsPortal` (`Dest = "Gardens"`, `RequiresFlag = "CaveUnlocked"`) · `GardensReturnPortal` (`Dest = "Tundra"`). **Exactly one portal leads to the island.**
- Backups present: `ServerStorage.PreCove_Backup_2026_08_02` (`TradingCenter_OLD` 218, `HubPortal_OLD` 24, `Decor_OLD` 270, four `IslandBarrier` parts), `AuditBackups.TeleportService_pre_coverebuild`, `World2Backups_2026_09_19.Rollback`; `AuditBackups` has 107 children.
- Mirror check (h31 hash + bytes, 39 trading-stack scripts): **38 identical to `source-sync-audit`**; `TeleportService` differs live (`ab7f1a65|26985` vs mirror `4f230a48|26939`, +46 bytes — the World 2 lane's in-flight edit; lines 197–230 quoted in §13 are read live). `UIKit.InteractionPrompt` / `InteractionPromptClient` are round-3 files not yet on this branch. `InteractionPromptClient` does not special-case `BuyPrompt`; it styles every prompt generically (verb from `VERB_BY_NAME`, else the first word of `ActionText` → "BUY").
- Scripts referencing `TradingWorld`: only `SkipLoop`, `CenterpieceSpinner`, and a `BoundsGuard` comment. No atmosphere or night-light script touches the island.

### 1.4 Captures — open item

Three `screen_capture` calls (arrival frame, aerial ×2) returned the HUD over a black viewport: the editor camera moved (the view cube rotated) but the scene did not render, which is what the build-standard doc describes for a backgrounded Studio. **Action for the owner:** bring Studio to the foreground (not minimised, viewport visible) and say so; TW-01 then takes the six viewpoints (`docs/cove-rebuild-woah-2026-08-09.md` "Five shots" + aerial + one booth close-up) into `docs/trading-world/captures/2026-09-19/`. Nothing else in this report depends on them.

---

## 2. What can be fully deleted / replaced

Everything under `GameWorld.TradingWorld` and `GameWorld.TradingCenter` except the contract objects in §3. Concretely, with the measured counts:

| Delete/replace | Count | Why |
|---|---|---|
| `Island` (Seabed, Plaza, 16 RingWater, 16 OuterRing) | 34 parts | replaced by the Exchange island (§4); the non-collide water ring is a navigation trap |
| `Bridges` (60), `CliffCove` (27), `Palms` (90), `TikiTorches` (18), `MarketArch` (7), `SaleBoards` (12), `IndexGate` (15), `RewardChests` (35), `CoveBarrier` (14), `Causeway` (14) | 292 parts | beach identity; placeholders nothing reads; barrier ring conflicts with the new edge |
| `ArrivalDeck` (25) | 25 parts | re-skinned as the Landing; the `ArrivalPad` position (8000, 2002.8, 7818) is kept as the arrival datum |
| `CoveDressing`: WaterDressing, FloatingIslets, ColossalArch, SkippersSpire, AmbienceAnchors, WorldEdge, Monuments, `CoveDriver` | 254 descendants + driver | replaced by the Exchange dressing and `ExchangeDriver`; the islets and the 900-stud beam are the wrong landmark hierarchy |
| `TradingCenter` gazebo (Floor, Podium, PodiumRing, 4 Pillars + caps, 4 beams, 4 Trim, SignBoard) | 21 parts | replaced by the Exchange Hall |
| `Booth7`–`Booth12` bodies | 6 models | replaced by the arcade module (same contracts) |
| stray unanchored `TradingWorld.Part` | 1 | junk |
| `EternalSkip` | keep or retire (D12 default keep) | orbit retuned to the moat |

**Keep and reuse (zero build cost):** `CoveDressing.Guardians` — the six colossi already stand at r ≈ 138 on plinths with breathing Highlights, exactly the ring the design wants; they move under the new dressing container unchanged (their `CoveBreatheH` tags keep working because the new driver keeps the tag names). Guardian roster to keep or recast: Tung Tung Tung Sahur, Bombardiro Crocodilo, La Vacca Saturno Saturnita, Tralalero Tralala, Brr Brr Patapim, Ballerina Cappuccina.

---

## 3. Functional objects that must survive (unchanged from Phase 1 §A.6, corrected by the inspection)

| Object | Contract | Correction |
|---|---|---|
| `GameWorld.TradingCenter` **(Folder)** and `GameWorld.TradingWorld` **(Folder)** | names | They are Folders, not Models. Keep them Folders (renaming the class is pointless; every script uses `FindFirstChild`). Streaming is decided per child model instead (§2.2 of Phase 1 → §14 build order). |
| `TradingCenter.TradeZone` | name, one box part | may move/grow |
| `TradingCenter.Booths.<Model>` × N with `BoothIndex` | as Phase 1 | N free; the six survivors are replaced, indices reissued 1…N |
| `Counter` + `Counter.StandPrompt` (reach 8, hold 0.3, `ObjectText "Market Stand"`) | names | keep the prompt's reach/hold as authored |
| `Display1/2/3` (plinth tops so the cube lands at eye height: plinth top ≈ P + 4.4 today) | names | |
| `SignBoard` ▸ SurfaceGui ▸ TextLabel | names/classes | |
| `Portals.HubPortal` ▸ `PortalTouch` (`Dest = "Hub"`) | attribute-driven | **must be moved off the arrival axis** |
| walkable surface under `TRADE_POS` (8000, 2004.6, 7818) | | the `ArrivalPad` datum is kept |
| `BoundsGuard` Trading box | unchanged | the new island's outer barrier r150 and Landing sit well inside |
| `Lighting`, `Terrain`, `SpawnLocation` | never edited | |

---

## 4. Updated Grand Exchange top-down layout

`docs/trading-world/grand-exchange-layout.svg` regenerated with the measured facts. Changes from the Phase 1 drawing:

1. **Colossi at r138** (the existing six, kept in place) instead of r130.
2. **Barrier ring at r150** (the old r121 `CoveBarrier` goes) plus a U-wall around the Landing; the moat's outer stone ring ends at r124, so nothing walkable is within 26 studs of the barrier.
3. **`HubPortal` moved to the Landing's −X edge** at (7978, 2006, 7818), facing +X — 22 studs from the arrival pad, visible on arrival, off the walking line. **`HubPortalVault`** at (8000, +6, 8186) behind the Reliquary.
4. **Moat water is `CanCollide = true`**, top at P − 1 (y 2001.4): wading, never a pit. The old Glass ring taught the lesson.
5. Everything else as Phase 1 §B.1.12: Landing (deck z 7790–7846 at y 2002.4, pad 2002.8) → causeway 24 wide (was 7) → Great Arch z 7930 → Records/Ticker r72–90 → promenade r48–66 → hall r44 → arcades r68–84 → Vault z 8092–8182 (+6).

Heights: plaza P = **2002.4** (unchanged from the measured plaza, so `TRADE_POS`, `BoundsGuard` and the water all stay valid), floor P − 1.6, balcony P + 12, crown P + 30, Vault P + 6, gem P + 36. Highest walkable y 2032.4 (box allows 2110).

## 5. Recommended spawn point

**Keep `TRADE_POS = (8000, 2004.6, 7818)`, facing +Z.** Reasons: no `TeleportService` edit (that file is in flight in the World 2 lane); the measured `ArrivalPad` already sits 1.8 studs under it; from there the Great Arch apex reads at 26° elevation and the Grand Gem at 11° through the arch opening — the composed frame. The Landing deck extends 28 studs ahead of the pad and 28 behind, so the fade-in never shows an edge. If D8 later wants arrivals further south for a longer approach, the only change is that one constant.

## 6. TradeZone placement

`TradingCenter.TradeZone` = one Part **46 × 22 × 46** centred **(8000, 2006.0, 8000)**, look −Z, anchored, CanCollide false, Transparency 1 — covering the sunken Exchange Floor (r22, top y 2000.8), both ring steps (r22–28) and the first 2 studs of promenade, and Y 1995–2017 (+6 slack in code → 1989–2023: the balcony at 2014.4 is inside the Y band but outside the X/Z footprint, so nobody on the balcony shows up in the floor's nearby list). Same name, same parent, same single-box math; the only code that cares (`TradeHandler.isInTradeZone`, `TradeClient.characterInZone`) reads it live.

## 7. Booth district layout

Unchanged in principle from Phase 1 §B.1.4, restated with the measured booth ergonomics:

- **30 stands**: West Arcade `BoothIndex` 1–12 (about +X, θ = −60° + 10.909°·k), East Arcade 13–24 (mirror about −X), Vault 25–30. `MaxPlayers` is 60; 30 stands is one per two players, 2.5× today's six, and the generator takes N (14 per arcade at ±63° is the next step up).
- **Module** (authored once, cloned): counter 11×2×3.4 on r68 with `StandPrompt` (reach 8, hold 0.3, `ObjectText "Market Stand"` — as today); three plinths at local x −3.4 / 0 / +3.4 whose tops sit at **P + 4.4** so the server's cube and its tag land at **P + 6.1**, the same eye height the live booths use; marquee `SignBoard` 9.6×1.9 → **12×3 at P + 6.5**, SurfaceGui Face toward the promenade, 50 px/stud, TextScaled (the server already writes the owner's name into it); back wall r72–78, colonnade roof at +9, banner mast, one SurfaceLight per two stands.
- Listing plate / model / mast colour = the D4 layer (§14).

## 8. Exact browsing loop

Start at the S junction totem (8000, P, 7940), walk the gold stripe at r58 **clockwise** (−X first, i.e. into the East Arcade — the arch's right-hand side as you arrive): stands 13 → 24 north-bound along the east crescent (130 studs, ~6 s), N junction (8000, P, 8066) with the Vault ramp straight ahead (optional 24-stud spur up to stands 25–30 and back), then the West Arcade south-bound 1 → 12 (130 studs, ~6 s), back to the S junction. **Total ≈ 390 studs ≈ 19 s at WalkSpeed 21 (25 s with the Vault spur); every stand's three displays are 6–10 studs from the stripe, inside `BuyPrompt` reach (10) and `BUY_RADIUS` (26); no step, no bridge, no water, no door.** The order 13→24 then 1→12 is deliberate so the numbering reads as one continuous loop from the arrival side.

## 9. Social / flex district placement

- **Exchange Floor steps** r22–28 (amphitheatre) and the **balcony** r36–44 at +12: the audience for trades.
- **Observation Crown** r40–46 at +30: panorama; reached by two curved ramps from the balcony.
- **Records terrace** r72–90 flanking the arch: −X side boards (TOP EARNERS / MOST TIME / MOST CAUGHT — D5), +X side MARKET PRICES ticker (client, `GetItemStats`) + HOW TO TRADE.
- **Skipper's Pier** (+X, r84→124) and **Colossus Walk** (−X, r84→124): benches over the moat, under Tung Tung Tung Sahur and Tralalero Tralala respectively (both are already there).
- **The Vault** (north, +6): six premium stands, the Reliquary (SECRET, GOD, GOLDEN, DIAMOND, MASSIVE alcoves with colossal statues built by the guardian technique), four spotlit **flex pedestals** at the entrance (hold a brainrot, stand in the light), Curator NPC.
- Hidden ledge under the causeway bridge at water level (moat is wadeable, so it is reachable and escapable).

## 10. NPC placement requirements for NPC-01

Unchanged: `docs/trading-world/npc-roles-for-npc01.md` (nine roles, seven for v1, standing spots, interactions, visual needs, props, the `NpcPost_<Role>` anchor contract). One measured refinement: the Exchange Host at (8000, P, 7948) stands where today's MARKET arch pillars are (z 7942) — clear ground once the arch is replaced, and 18 studs inside the Great Arch (z 7930), which is where an arrival's first step lands them face to face.

---

## 11. Cash → Gems migration plan (D1)

### 11.1 What Gems are in this codebase (inspected, unchanged by this lane)

- **Balance:** `data.Darrels` (integer, default 0, **no cap**). Player-facing word is "Gems"; the HUD chip `EmeraldHUDClient` draws `"\u{1F48E} " .. NumberFormat.Short(n)` (💎 glyph).
- **The only authority:** `ServerScriptService.Modules.EmeraldService` — `Award(player, n, reason)` and `TrySpend(player, n, reason)`, both **non-yielding**, both integer-only (`floor`, reject NaN/inf/≤0), both push `EmeraldUpdate` + `PlayerDataManager.PushUpdate`. `TrySpend` returns false when `Darrels < n` (no partial debit). There is **no player-to-player transfer primitive**; a booth sale will be `TrySpend(buyer)` + `Award(seller)` in one yield-free window.
- **Faucets (do not change):** daily quests 16–40 gems per quest (a 3-quest slate ≈ 86/day), weekly quests 22–52 (5-quest slate ≈ 188/week), perfect throws 2 gems each capped at **60/day** (`PERFECT_DAILY_CAP`), Michel quest, Tundra quest, season-pass tiers, raid consolation; **Robux packs** (`EmeraldPackConfig`, live developer products): 80 gems R$99 · 180 gems R$199 · 400 gems R$399 · 1000 gems R$899 (≈ 0.8–1.1 gems per Robux). An active free player earns roughly **150–200 gems/day**; the biggest pack is 1,000.
- **Sinks:** eggs (`EggHandler`, `TrySpend` then grant, refund on failure), raids (`StealService`), season-pass unlocks, pets — plus, after D1, booths.
- **Caps/limits that matter for booth pricing:** no balance cap; no per-day spend cap; no fee. The scale is thousands, not billions: `MAX_PRICE = 1e9` (cash) is meaningless for gems and the `1.5k / 2m / 1b / 1t` price-entry suffixes invite mistakes. Proposal: `MAX_GEM_PRICE = 1,000,000` (still absurd, but bounds `formatMoney` and typos; the owner picks — this is validation, not a rate) and price entry accepts plain integers and `k` only.
- **Policy note (owner to confirm, no code):** gems are Robux-backed, so a 1-gem listing of a Common brainrot is a de facto gem-gifting channel between accounts. That is the loop the owner wants ("player-to-player gem transfer tied to the sale"); the existing anti-wash rule in `PriceIndex` (one vote per unordered pair) already keeps such trades from setting market prices, and every purchase is server-logged (`[Emeralds]` print lines + `[BoothAudit]`).

### 11.2 The safe purchase sequence (server, `BoothHandler.BoothBuy`, no yields from the first check to the last write)

```
1  listing exists (by Id)                     → "just sold or removed"
2  seller online                               → release booth
3  buyer ~= seller                             → refused (kept: the current system forbids it)
4  buyer within BUY_RADIUS of Counter          → "walk up"
5  both profiles loaded, neither __noSave      → refused
6  bag space (BagConfig.HasBrainrotSpace)      → refused, nothing moved
7  seller still owns listing.Uid (D2)          → prune listing, "no longer available"
8  unique cap                                  → refused
9  price re-validated: integer, 1 ≤ p ≤ MAX_GEM_PRICE, p == listing.Price (server copy) 
10 EmeraldService.TrySpend(buyer, p, "booth:"..id)   -- DEBIT FIRST, server-authoritative; false → "Not enough Gems", nothing moved
11 record = BrainrotMover.TakeByUid(seller, sellerData, listing.Uid)
   if not record → EmeraldService.Award(buyer, p, "booth-refund") ; warn ; return    -- the EggHandler refund pattern; cannot fail (integer > 0)
12 BrainrotMover.Give(buyer, buyerData, record)     -- total, carries the full identity (D2)
13 EmeraldService.Award(seller, p, "booth-sale:"..id)  -- CREDIT
14 table.remove(booth.listings, pos) ; PriceIndex.RecordSale(...) ; SyncBackpack both ; refreshDisplays ; pushManageState
15 PushUpdate both ; Save both ; on a failed Save: [BoothAudit] line + retrySave (never roll back), exactly as today
```

Why this order: steps 1–9 are pure reads; step 10 is the only step that can legitimately fail after the reads, and it fails *before* anything moves. Between 10 and 13 nothing yields, so a second `BoothBuy` for the same listing in the same frame runs after step 14 and hits step 1 ("just sold") — duplicate purchases are impossible without a lock. A `TakeByUid` miss at 11 (the copy vanished between 7 and 11 is impossible without a yield, but the guard stays) refunds through `Award`, which cannot fail on a positive integer. Gems never move on a refused purchase; the seller is credited only after the buyer holds the item; the listing is removed before any yield; both saves and the audit line are unchanged in shape.

### 11.3 Every script/config that changes (and what does not)

| File | Change | Owner |
|---|---|---|
| `ServerScriptService.Modules.BoothHandler` | require `EmeraldService`; replace `buyerData.Cash < listing.Price` / `Cash -=` / `GrantCash` with the §11.2 sequence; `MAX_PRICE` → `MAX_GEM_PRICE`; every `"$"` string (lines 133, 142, 310, 394, 457, 458 and the `[BoothAudit]` format at 450) → gem wording (`"💎 " .. NumberFormat.Short(p)` or the `\u{1F48E}` glyph the HUD uses); the `BuyPrompt` attribute `Price` stays a number; add attribute `Currency = "Gems"` so any display layer never guesses. `formatMoney` (a local copy) → `NumberFormat.Short`. | economy |
| `StarterPlayer.StarterPlayerScripts.BoothClient` | `"$"` → 💎 at lines 447, 575 (the `$/s` there is income — leave), 661; price box placeholder `"price (e.g. 2.5k)"` → `"gems (e.g. 250)"`; `parsePrice` suffixes limited to `k` (drop `m/b/t`); toasts already come from the server. | Pete (UI) |
| `ReplicatedStorage.Modules.NumberFormat` | nothing (the `"$" ..` helper at line 61 stays for cash surfaces) | — |
| `ServerScriptService.Modules.PriceIndex` | store name `BrainrotSkip_PriceIndex_v1` → `_v2` (cash-era observations must not seed gem medians); `MAX_PRICE` sanity ceiling 1e12 → 1e7; optional: key `Name|Mutation|Size` (D2) so a Massive is its own market | economy |
| `ServerScriptService.ItemStatsService` | nothing (numbers only) | — |
| `StarterPlayer.StarterPlayerScripts.IndexClient` | line 411 `"PAID $%s (%d sales/%dd)"` → `"PAID 💎%s …"` | Pete (UI) |
| `ServerScriptService.Modules.EmeraldService` | **nothing** — `Award`/`TrySpend` already have the exact semantics; only new `reason` strings appear in its logs | — |
| `ServerScriptService.Modules.PlayerDataManager` | nothing (`Darrels` exists; `GrantCash` simply stops being called by booths) | — |
| `ServerScriptService.Modules.TradeHandler` + `TradeClient` | **D1b — not decided.** P2P trades still carry a `Cash` sweetener (`SetCash`, `offer.Cash`, netted at execute). Options: keep Cash in trades (booths only migrate), migrate trades to Gems too (`TrySpend`/`Award` netting, same shape), or remove currency from trades. Recommendation: migrate (one gem economy on the island), as a **separate second step** so booths can ship first. | owner |
| `ReplicatedStorage.Modules.EmeraldPackConfig`, `ProductRegistry`, quest configs, `SeasonConfig` | **nothing** (faucets untouched per the owner) | — |
| `docs/trading-world/*` price-plate spec | glyph = 💎, number = `NumberFormat.Short` | TW-01 |

**Migration risk:** low. Listings and trade sessions are in-memory (nothing persisted to convert); the world is held back (no live listings exist); the only persistent artefact is the `PriceIndex` store, handled by the `_v2` rename. **Exploit surface:** unchanged or smaller — the client still only "asks"; price, balance, ownership and radius are server-checked; the debit is the same non-yielding primitive the egg shop uses. **Test cases** are in §12.5 (shared with D2, since one PR carries both).

---

## 12. Huge / Massive preservation fix plan (D2)

### 12.1 The complete identity of a brainrot (canonical entry, `ThrowHandler` L1287–1301)

`data.Brainrots[i] = { Name, Mutation, Size, Uid, PadIndex, Pending, Serial?, MintedAt? }` plus owner-side flags written elsewhere (`PlotFav` = raid/sell lock). Fields split into:

- **Identity — must travel with the item:** `Name` (base identity → rarity via `BrainrotConfig`), `Mutation` (Golden / Diamond / Rainbow / weather), `Size` (Huge / Massive / nil), `Serial` + `MintedAt` (mint identity for tracked classes).
- **Owner-side — reset for the receiver:** `Uid` (a **per-profile counter**, `PlayerDataManager.TakeUid` = `data.NextUid++`), `PadIndex`, `Pending` (accrued income, drained on take), `PlotFav`.

**Why the Uid cannot be carried across owners:** it is an inventory handle unique only within one profile; the receiver's counter may already have issued the same number, and every tool/prompt/pad on the receiver's side addresses entries by that per-player Uid. The item's *global* identity is `(Name, Mutation, Serial, MintedAt)` for tracked classes; for untracked classes there is none today. Recommendation: keep issuing a fresh per-owner `Uid` on receipt (as `Give` does) and carry the identity fields; if a global id is wanted for provenance, add an additive `Guid` (`HttpService:GenerateGUID(false)`) at every insert site — optional, separate approval, no gameplay effect.

### 12.2 Current broken path (all of it)

| Path | Selector | Record built with `Size`? | Entry written with `Size`? | Result |
|---|---|---|---|---|
| Booth sale | `BrainrotMover.Take(name)` — least-`Mutations.Mult` copy, **size ignored** | **no** (`{Name, Mutation, Serial, MintedAt}`) | **no** (`Give` writes `{Name, Mutation, Serial, MintedAt, PadIndex, Pending, Uid}`) | seller may lose the Massive copy; buyer gets a normal one |
| P2P trade | `Take(name)` | no | no | same |
| Gift | `TakeByUid` — exact copy | **yes** | **no** — `Give` passes `record.Size` only to `BrainrotSpawner.Spawn` (the visual) | receiver sees a Massive on the pad until rejoin/respawn, then it is normal: **the "Uid path preserves Size" belief is only true for the visual** |
| Steal (raid) | `TakeByUid` | yes | thief: **yes** (`StealService.toBag` writes `Size`); victim put-back on unique-cap failure: `Give` → **no** | thief keeps it; a returned item loses Size |
| Fusion | name + mutation match, unplaced copies | consumes; fused entry has no `Size` | — | can consume a Huge copy silently |
| Offering | name, least-mult, size ignored | consumes | — | can burn a Huge copy silently |
| Sell stall | Uid, or name via `SellValue.SelectCheapest` which **refuses mutated/oversized copies** | — | — | **correct — the precedent** |
| Quest rewards / Michel / Gianluca / Maxwell / DevQuest | `Give({Name})` or direct inserts | n/a | n/a | fine (no size) |

### 12.3 Correct path

1. **One identity copier.** `BrainrotMover.IdentityOf(entry)` returns `{ Name, Mutation, Size, Serial, MintedAt }` from an explicit `IDENTITY_FIELDS` whitelist; `Take`, `TakeByUid`, `Give` and `StealService.toBag` all build from it. A future identity field is added in exactly one line.
2. **`Give` writes the identity into the entry**, not just the visual: `{ ...IdentityOf(record), PadIndex, Pending = 0, Uid = TakeUid(receiver) }` and still passes `Size` to `Spawn`.
3. **No name-based transfer.** Booth listings become `{ Id, Uid, Name, Price }` (`BoothList Add` carries `Uid`; the server verifies the Uid is owned, unplaced, not `PlotFav`, and not already listed); `BoothBuy` uses `TakeByUid(listing.Uid)`. Trade offers become sets of Uids (`Items[uid] = true`; `AddItem {Uid}`), executed with `TakeByUid`. `Take(name)` is retired from both, and if it must stay for any legacy caller it adopts the sell stall's rule: **never pick a mutated or oversized copy by name** (`SellValue.SelectCheapest` semantics).
4. **Fusion and Offering** adopt the same rule (skip `Size ~= nil` and mutated copies unless the client targets a Uid) — same lane, small edit, and it closes the last silent consumer.
5. **Display truth:** `refreshDisplays` resolves the listing's exact entry by Uid and writes `Rarity`, `Mutation`, `Size`, `Serial` attributes on `BuyPrompt` — the only source any plate may read. Until this ships, no size label anywhere.
6. **PriceIndex key** gains `|Size` (a Golden Massive is its own market) in the `_v2` store that D1 creates anyway.

### 12.4 Files affected, risk, compatibility

| File | Change |
|---|---|
| `Modules.BrainrotMover` | `IdentityOf`; `Take`/`TakeByUid` build records from it; `Give` writes it; `Take` (if kept) skips mutated/oversized copies |
| `Modules.BoothHandler` | Uid-based listings; `TakeByUid`; prune tick checks the Uid still exists/unplaced; `BuyPrompt` identity attributes; refuse listing a `PlotFav` copy |
| `Modules.TradeHandler` | Uid-based offers; `TakeByUid`; `offerDetails` from the entry; unique-cap/bag pre-flight by name still works (count by `Name`) |
| `Modules.StealService` | `toBag` via `IdentityOf` (already correct in effect) |
| `Modules.FusionHandler`, `Modules.OfferingHandler` | skip oversized/mutated copies in name-based selection |
| `Modules.PriceIndex` | `|Size` in the key (with `_v2`) |
| `BoothClient`, `TradeClient` (Pete) | pickers become per-copy (Uid) — the Bag already renders per-Uid `BrainrotCard`s, so the kit exists; show the copy's mutation/size on the card |
| `Modules.BagConfig`, `ThrowHandler`, `PlayerDataManager` | nothing |

**Migration risk:** low — no save migration (`Size == nil` is already "normal"; nothing persisted references listings/offers). **Backward compatibility:** every existing entry keeps working; `Give` still accepts a bare name for quest rewards; old `BoothList`/`TradeAction` payloads without `Uid` are refused server-side (the world is held back, so no live client sends them). Do not change rarity odds, `SizeConfig` chances or multipliers — none of this touches them.

### 12.5 Test cases (Studio Play, two test accounts or the `DataUpdated` seam)

| # | Scenario | Expect |
|---|---|---|
| T1 | Seller owns Massive X and normal X; lists the Massive by Uid; buyer buys | buyer's entry has `Size = "Massive"`; still Massive after buyer rejoins; seller keeps the normal one; seller's gems +p, buyer's −p |
| T2 | Same via P2P trade (offer the Massive Uid) | receiver's saved entry keeps `Size`; both saves succeed |
| T3 | Gift the held Massive | receiver's saved entry keeps `Size` (fails today) |
| T4 | Raid steals a Massive; thief at unique cap → put-back | victim's returned entry keeps `Size` (fails today) |
| T5 | Golden + Massive stack | both fields survive every path |
| T6 | Serial/MintedAt | survive every path (regression) |
| T7 | Old save, `Size = nil` | unaffected |
| T8 | List a `PlotFav` copy | refused with a toast |
| T9 | Listed Uid gifted away | listing pruned within 3 s; buyer gets "no longer available" |
| T10 | Two buyers, same listing, same frame | one succeeds; other gets "just sold"; exactly one debit, one credit |
| T11 | Buyer has p−1 gems | refused, no debit, listing intact |
| T12 | `TakeByUid` returns nil after the debit (forced in a test seam) | buyer refunded, `[BoothAudit]` warn, listing pruned |
| T13 | Either profile `__noSave` | refused before any gem moves |
| T14 | buyer == seller | refused |
| T15 | Price 0, 1.5, NaN, > `MAX_GEM_PRICE`, "2m" | refused at listing time |
| T16 | Bag full / unique cap | refused before the debit |
| T17 | Save fails after a sale | audit line carries gems; retry loop; no rollback |
| T18 | `BuyPrompt` attributes | `Rarity`, `Mutation`, `Size`, `Serial`, `Price`, `Currency = "Gems"`, `SellerName`, `SellerUserId` present and correct |
| T19 | Fusion/Offering with only Huge copies spare | refused, not consumed |
| T20 | PriceIndex `_v2` | fresh store; keys carry `|Size`; medians ignore cash-era data |

---

## 13. ComingSoon / teleport bypass fix plan (D9)

**Exact bypass path (read live, `ServerScriptService.TeleportService` L197–230):**

```
remotes.TeleportTo.OnServerEvent → destination == "Trade" → teleportCharacter(player, TRADE_POS, FORWARD)   -- L203–204
```

No `WorldTravelConfig.IsDestComingSoon("Trade")`, no `CanTravel`, no `passesLock`. The other two doors are gated: the walk-through `TradePortal` goes through `passesLock` (ComingSoon checked first, refuse message from the touch part's attribute), and the Worlds board's `TeleportTo("Trading")` goes through `travelToWorld → WorldTravelService.CanTravel → IsUnlocked`, which returns false for a `ComingSoon` world. **No live client fires `TeleportTo("Trade")`** (grep: `ClientMain` fires only `Throw`, `Shops`, `Plot`, `OpenPlot`; the Worlds panel fires world ids) — the branch is dead code that a spoofed `RemoteEvent:FireServer("Trade")` can still reach. `BoundsGuard` then keeps such a player on the island (the Trading region is valid), so they can claim stands and trade while the world is "closed".

**Scripts affected:** `ServerScriptService.TeleportService` only (`WorldTravelConfig` already exposes `IsDestComingSoon`). The file is currently being edited by the World 2 lane (+46 bytes live vs mirror) — coordinate the edit through that lane or wait for it to land.

**Safest enforcement point:** a single server-side gate where a *portal destination* is resolved, applied to all three doors: `local function destOpen(destName) return not WorldTravelConfig.IsDestComingSoon(destName) end`, called (a) in `passesLock` (already), (b) in `travelToWorld` (already via `CanTravel`), and (c) in the `TeleportTo` handler before the `"Trade"` teleport — or, better, **delete the `"Trade"` branch outright** (nothing uses it; `"Trading"` via the board is the supported route) and add the same `destOpen` check inside `teleportCharacter`'s two remaining world-hop callers as a belt-and-braces. Recommendation: delete the branch **and** keep the check in `passesLock`/`travelToWorld`; add a `warn` when an unknown destination string arrives so future bypass attempts are visible in the server log.

**Server-authoritative?** Yes, and it must stay so: the gate is a server read of a shared config; the client never decides. The same config line that opens the world for the board opens it for the portal, so there is one switch.

---

## 14. Exact D4 decision — restated verbatim from the Phase 1 report (§C.1)

> | **D4** | **Listing presentation layer.** (a) client-only `BoothDressingClient` reading replicated instances (no server change — recommended), or (b) a presentation-only edit to `BoothHandler.refreshDisplays` (bigger billboard, `MaxDistance`, tier word) — touches a frozen economy file. | Owner + economy | (a). |

**Options now that D1 and D2 reopen `BoothHandler` anyway:**

- **(a) Client-only overlay** — `BoothDressingClient` hides the server's 130×40 billboard locally and draws the plate, model and mast colour from `BuyPrompt` attributes and `ListingDisplay.Color`. No further server change. Weakness: rarity/mutation/size must be parsed out of `ItemName` text unless D2's attributes land, and the server keeps building a GUI nobody sees.
- **(b) Server presentation edit** — `refreshDisplays` draws a bigger billboard with `MaxDistance`, tier word, mutation/size lines. Weakness: presentation code inside the economy module; every visual tweak is an economy-file edit; no 3D model preview (the server should not clone 218-model previews for everyone).
- **(c) Split: server = data, client = presentation (recommended now).** During the D1/D2 edit the server stops creating the BillboardGui and the Neon cube and instead writes the identity attributes (`ItemName, Rarity, Mutation, Size, Serial, Price, Currency, SellerName, SellerUserId`) on `BuyPrompt` (and keeps `ListingDisplay` as an invisible anchor part so the prompt has a parent and `BUY_RADIUS` maths is unchanged). `BoothDressingClient` renders everything: the price plate (💎 + `NumberFormat.Short`, `MaxDistance` 120), the locally cloned `BrainrotModels` preview with `MutationFX` and `ScaleTo` for size, the mast state (vacant/open/full). Size and mutation labels come only from the attributes D2 writes, so an honest label is structurally impossible to fake. Cost: one client script (TW-01) + ~30 lines in `refreshDisplays` (economy, in the same PR as D1/D2).

**Recommendation: (c).** Your call — TW-01 will not proceed on D4 until you pick (a), (b) or (c).

---

## 15. Phase 2 build order (for approval — nothing started)

Two tracks run in parallel; the world track never touches an economy file, the economy track never touches geometry.

**Track W — world (TW-01, Studio + generator):**
1. Owner saves a `.rbxl`; snapshot per Phase 1 §A.14 step 1 (clones into `ServerStorage.TradingWorldBackups_2026-09-XX`, script sources into `AuditBackups.PreGrandExchange_…`, `docs/trading-world/snapshot-….md` with every measured CFrame from §1).
2. `ServerStorage.TradingWorldBuild.Generator` v1 — numbers table, `ClearAll()`, `Contracts()` self-check (`OK 30/30`), output to `GameWorld.TradingWorld_GE` / `TradingCenter_GE`.
3. Landing (re-skin of the deck at the same datums), causeway 24 wide, Great Arch, banner masts; `HubPortal` relocation is a **Portals** edit (attribute-driven) done at cutover.
4. Exchange Hall: sunken floor, steps, pylons, arches, balcony, crown, ramps, gem anchor with `Spin`, `TradeZone_GE`.
5. Arcade module × 24 + Vault module × 6 with contracts; totems; lane stripe.
6. Records terrace (static boards), piers, rim, wadeable moat, outer ring, barrier r150, Landing U-wall; move `Guardians` under the new dressing container (unchanged).
7. `ExchangeDriver` (CoveDriver conventions, `C`, 400-stud gate) and `SkipLoop` constants (`R = 106`, `WATER_Y = 2001.4`) — mirrored byte-exact; delete the stray unanchored part.
8. `TradingWorldBackups_….Rollback` written; **revert drill on the greybox (V10)**.
9. Cutover rename (owner present), Play probes V1–V15, phone captures, mirror push, `_MANIFEST.txt` diff.
10. Hand `NpcPost_*` marks to NPC-01; hand the D4 attribute contract to Pete for the Booth/Trade pickers.

**Track E — economy (economy owner, separate branch, one PR in three commits):**
1. D2 identity fix (`IdentityOf`, `Give`, Uid-based listings/offers, Fusion/Offering guards, `BuyPrompt` attributes) with tests T1–T9, T18–T19.
2. D1 gems (§11.2 sequence, wording, `MAX_GEM_PRICE`, `PriceIndex _v2` with `|Size`) with tests T10–T17, T20. D1b (trades) after the owner decides.
3. D9 gate (`TeleportService`, after the World 2 lane's edit lands).
Then Pete: `BoothClient` / `TradeClient` per-copy pickers and gem wording; `IndexClient` label.

**Launch gate (owner):** Track W probes green + Track E tests green + NPC-01 v1 roles placed + the `WorldsPanel` row copy → delete `ComingSoon = true`.

---

*End of Phase 1B. Stopped for approval. Studio untouched.*
