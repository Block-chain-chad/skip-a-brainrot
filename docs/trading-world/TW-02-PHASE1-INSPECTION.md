# TW-02 — Trading World Full Rework V2: Phase 1 inspection (read-only)

**Date:** 2026-09-20 · **Branch:** `trading-world-rework` (worktree `../skip-a-brainrot-trading-world`, HEAD `b1292b3`) · **Lane:** TW-02 (supersedes TW-01's Grand Exchange concept; keeps TW-01's contracts, backups and rollback tooling) · **Studio:** PlaceId `78783087742939`, PlaceVersion **2449** (TW-01's snapshot was 2353 — other lanes have published ~96 versions since), Edit mode, one instance.

**Every call in this pass was a read** (`GetChildren`, properties, attributes, `ReadVoxels`, script reads, greps, four screen captures with a temporary camera). **Nothing was created, moved, deleted, edited, saved or published. No greybox was started.**

**Brief received (owner, 2026-09-20):** "The Riverside Trading Settlement" — destroy the circular-island / central-structure / booths-around-the-centre composition (both the live cove island *and* TW-01's Grand Exchange staging build are that composition), build a dense hand-built riverside settlement with streets, elevation, water, an Old Bridge landmark, stalls built into buildings, integrated NPC locations; preserve the trading backend untouched; Gems are the marketplace currency; seven phases, Phase 1 = this report.

Compass (unchanged from TW-01): **N = +Z, S = −Z, E = −X, W = +X.** The live island centre is C = (8000, 2002.4, 8000). P = 2002.4 is the plaza datum. Terrain water surface is y ≈ 2000 across the whole Trading box (ocean of Terrain water, no solid terrain anywhere in the box).

---

## 1. Current Trading World hierarchy (live, PlaceVersion 2449)

Two compositions exist side by side under `Workspace.GameWorld` — both are circular hubs (aerial capture from (8250, 2420, 7560) → (8250, 2002, 8000) shows two discs in open water).

### 1.1 The live island ("Skipper's Cove", closed to players)

| Container | Class | Descendants | Contents |
|---|---|---|---|
| `GameWorld.TradingWorld` | **Folder** | 913 (618 BaseParts, 1 **unanchored** stray `Part`, 2 scripts, 15 lights, 20 SurfaceGuis, 6 emitters, 6 Highlights) | `CoveBarrier` 14 · `Island` 34 (Seabed cylinder r120, Plaza disc Ø124 top P, 16 `RingWater` Glass chords **CanCollide false**, 16 `OuterRing`) · `ArrivalDeck` 27 (`DeckTop` 46×2.4×44 at z 7830, `ArrivalPad` Ø12 top 2002.8 under `TRADE_POS`, lamps) · `IndexGate` 15 · `TikiTorches` 24 · `MarketArch` 11 · `Causeway` 14 (7 studs wide) · `RewardChests` 51 · `SaleBoards` 42 · `Palms` 100 · `CliffCove` 28 · `Bridges` 60 · `EternalSkip` Model 10 (holds `SkipLoop`) · stray `Part` · `CoveDressing` Model 468 (holds `CoveDriver`; six `Guardians` colossi at r ≈ 138, 214 desc; `SkippersSpire` 904-stud beam; `ColossalArch`; `WorldEdge`; `Monuments`; `FloatingIslets`) |
| `GameWorld.TradingCenter` | **Folder** | 122 (81 BaseParts, 0 scripts, 14 SurfaceGuis) | `Booths` Folder 96 = **six booths `Booth7`–`Booth12`** (`BoothIndex` 7–12) · gazebo: `Floor` 56×1×56 (buried), `Podium`, `PodiumRing`, 4 `Pillar` + 4 `PillarCap`, `BeamN/E/S/W`, 4 `Trim`, `SignBoard` "🔄 TRADING CENTER" · **`TradeZone`** 26×26×26 at (8000, 2007, 8000) |
| `GameWorld.Portals.HubPortal` | Model (24) | | `PortalTouch` 8.4×11.2×2.8 at (8000, 2006, 7815.7), `Dest = "Hub"` — **2.3 studs behind `TRADE_POS`**: a step backwards on arrival sends the player home |
| Bounding box | | | `TradingWorld` X 7626–8374 · Z 7806–8154 (Y to 2532 with the spire); `TradingCenter` X 7912–8047 · Z 7972–8113 |

### 1.2 TW-01's Grand Exchange staging build (never cut over)

| Container | Class | Descendants | Contents |
|---|---|---|---|
| `GameWorld.TradingWorld_GE` (attr `Staging = true`) | Model | 1,263 (1,197 BaseParts, 0 scripts, 19 lights, 17 SurfaceGuis) | `ExchangeHall` 600 · `Base` 246 · `ArcadeWest` 123 · `Vault` 98 · `Causeway` 52 · `GreatArch` 34 · `Records` 26 · `Totems` 20 · `Landing` 17 · `Piers` 14 · `NpcPosts` 11 · `GrandGem` 10 — centred (8500, 2002.4, 8000), bbox X 8290–8710 · Z 7784–8192 |
| `GameWorld.TradingCenter_GE` (attr `Staging = true`) | Model | 158 (109 BaseParts, 12 SurfaceGuis) | `Booths` 156 = `Booth1`–`Booth12` (`BoothIndex` 1–12, contracts identical to the live six) · `TradeZone` 46×22×46 at (8500, 2006, 8000) |
| `ServerStorage.TradingWorldBuild.Generator` | ModuleScript 38,097 B | | the GE generator (`ClearAll, Base, Landing, Causeway, GreatArch, Records, Hall, Gem, Totems, Arcade, Booths, TradeZone, Vault, Piers, NpcPosts, Contracts, Stats, BuildCheckpoint1, BuildAll`) — build-time only, nothing requires it |

Both GE containers sit inside the BoundsGuard Trading box, so they occupy space the new settlement would use.

### 1.3 Backups and rollback already in place (verified present)

- `.rbxl`: `C:\Users\m\Coding\skip-a-brainrot-backups\SkipRocks_78783087742939_pre-GE_2026-09-19.rbxl` (PlaceVersion 2353 — **stale by 96 versions**; a fresh one is needed before Phase 2).
- `ServerStorage.TradingWorldBackups_2026_09_19`: `TradingWorld_Original` (911), `TradingCenter_Original` (122), `HubPortal_Original` (24), `SnapshotJSON`, and `Rollback` (`Verify()`, `Restore()`, `Restore({force=true})`, `Drill()` — drill passed 2026-09-19; it destroys `*_GE` and restores the three originals plus the two island scripts).
- `ServerStorage.AuditBackups.PreGrandExchange_2026_09_19`: sources of `SkipLoop`, `CoveDriver`, `CenterpieceSpinner`, `TeleportService`, `BoundsGuard`, `WorldTravelConfig` (disabled stubs).
- `ServerStorage.PreCove_Backup_2026_08_02.TradingCenter_OLD` (218): the pre-cove stands including the lost `Booth1`–`Booth6`.

Studio-wide baseline: 58,613 BaseParts in `Workspace` (LushGardens alone is 54,649 descendants). TW-01's Trading World budget was ~4,500 parts / 48 local lights / 20 emitters / 10 Highlights; the live island uses 699 parts and the GE 1,306.

## 2. Current booth architecture (the exact contract, read from the live `BoothHandler`)

One booth = one `Model` under `GameWorld.TradingCenter.Booths` (a **Folder**; `TradingCenter` itself is a **Folder** — keep both classes, every consumer uses `FindFirstChild`). Contract objects and how the code touches them:

| Object | Read/written by | Exact use |
|---|---|---|
| booth `Model`, attribute **`BoothIndex`** (number) | `BoothHandler.Init` L267–284 | `booths[idx] = { index, model, ownerUserId, listings }`, enumerated **once at server boot** from `Booths:GetChildren()` — stands added after boot are never seen |
| **`Counter`** (BasePart) | L165, L190–192, L223 | `booth.model.Counter` is indexed **directly** (not `FindFirstChild`) in `releaseBooth` / `onStandPrompt`; `BUY_RADIUS = 26` studs measured from `Counter.Position` |
| **`Counter.StandPrompt`** (ProximityPrompt) | L272–281 | `Triggered` → claim / manage / "belongs to X"; `ActionText` rewritten `"Claim Stand"` ↔ `"Manage Stand"`. Live values: reach 8, hold 0.3, `ObjectText "Market Stand"`, no line-of-sight, key E |
| **`Display1`, `Display2`, `Display3`** (BaseParts) | L107, L121 | `MAX_LISTINGS = 3`; slot k's cube spawns at `Display{k}.CFrame * CFrame.new(0, 1.7, 0)` (the anchor's own orientation is inherited) |
| **`SignBoard`** (BasePart) ▸ SurfaceGui ▸ first `TextLabel` | `setSign` L47–56 | text rewritten to `"<NAME>'S STAND"` / `"AVAILABLE STAND"` on claim / release; every SurfaceGui child is written |
| runtime **`ListingDisplay`** (Neon 1.8³ Part, direct child of the booth model) + BillboardGui + **`BuyPrompt`** (attrs `BoothIndex, ListingId, ItemName, Price, SellerName`; reach 10) | `refreshDisplays` L99–158 | destroyed and rebuilt on every change and by the 3-s prune tick; never pre-authored |
| `TradingCenter.TradeZone` (ONE BasePart) | `TradeHandler.isInTradeZone` L33–43; `TradeClient` L790+ | box test in the part's object space with **+6 Y slack**; both traders must be inside to execute; the client re-binds on `ChildAdded`/`ChildRemoved` of `TradingCenter` (streaming-safe) — so it must stay a **direct child** of `TradingCenter` |

Live booth body (`Booth7`, for reference): `Base` 12×1×8, `Counter` 10×3.2×2.2 at y 2004.9, three `Display` pads 1.6×0.4×1.6 at y ≈ 2006.7 spaced 3.4, `SignBoard` 9.6×1.9×0.4 at y 2009.6 (SurfaceGui face Front, GothamBlack, #FFDC5A), `BackWall` 11×7×0.8, `PostL/PostR`, `Awning` 12.6×0.5×7.6. Everything except the six contract names is free.

**Client side has zero geometry dependency:** `BoothClient` listens to `ProximityPromptService.PromptTriggered` for any prompt named `BuyPrompt` and reads its attributes; the stand-management window is opened by the server's `BoothState {Phase="Manage"}` after the `StandPrompt` fires.

## 3. Trading scripts / modules (all live, all byte-matched to the mirror on 2026-09-19; `BoothHandler` re-read in full today and unchanged)

**Server** (`ServerScriptService`, `Main` calls each `Init()` synchronously — order: … `TradeHandler` → `BoothHandler` → …):
- `Modules.BoothHandler` (518 lines) — stands: claim / manage / list / remove / unclaim / buy / release-on-leave / 3-s prune. All state **in server memory**; nothing persisted.
- `Modules.TradeHandler` — P2P trades (request → offers → confirm → 3-s countdown → swap), `TradeZone` gate, name-based offers, `Cash` sweetener.
- `Modules.BrainrotMover` — `Take / TakeByUid / Give / CountOwned / WithinUniqueCap / InfoByName / TierByName` (the item half of every transfer).
- `Modules.InventoryHandler.SyncBackpack`, `Modules.PriceIndex` (`RecordSale` → DataStore `BrainrotSkip_PriceIndex_v1`, 7-day medians), `Modules.PlayerDataManager` (`Get / Save / PushUpdate / GrantCash`; fields `Cash`, `Darrels` = Gems), `Modules.EmeraldService` (`Award / TrySpend` — **not yet called by any booth or trade code**), `ItemStatsService`, `ReplicatedStorage.Modules.BagConfig`, `MutationConfig`.
- `TeleportService` (arrival, portals, `travelToWorld`), `Modules.BoundsGuard` (region `Trading`), `Modules.WorldTravelService`, `ReplicatedStorage.Modules.WorldTravelConfig` (`ComingSoon`), `CenterpieceSpinner` (spins any part with attribute `Spin` under `GameWorld.TradingWorld`; tolerates none).
- Inside the world: `TradingWorld.EternalSkip.SkipLoop` (orbiting skipping stone, r68 about C), `TradingWorld.CoveDressing.CoveDriver` (tag-driven dressing motion, 400-stud gate).

**Client** (`StarterPlayer.StarterPlayerScripts`): `BoothClient` (stand window, picker, price box, buy confirm), `TradeClient` (trade window, `TradeZone` watcher, nearby-players list), `IndexClient` (price index panel), `InteractionPromptClient` (draws every ProximityPrompt), `GameHUDPanels.WorldsPanel` (the Worlds board row).

**Remotes** (`ReplicatedStorage.Remotes`): `BoothState`, `BoothList`, `BoothBuy`, `TradeRequest`, `TradeRespond`, `TradeAction`, `TradeState`, `TeleportTo`, `EmeraldUpdate`, `EmeraldState`, `GetItemStats`. Names and shapes are untouched by this rework.

## 4. Gem transaction system — what is actually live

**The booth purchase debits Cash today, not Gems.** Live `BoothHandler`:

- L393 `if buyerData.Cash < listing.Price then toast("Not enough cash — that costs $…")`
- L427 `buyerData.Cash -= listing.Price` · L428 `PlayerDataManager.GrantCash(sellerData, listing.Price)`
- L309–310 price bounds `1 … MAX_PRICE = 1e9`, toasts in `$`; L133 / L142 / L457 / L458 billboard, prompt and toasts in `$`; `BoothClient` L661 shows `"$"`; `TradeHandler` carries a `Cash` sweetener (`SetCash`).

Gems exist and are sound: `data.Darrels` (integer, no cap, HUD word "Gems", glyph 💎), `EmeraldService.Award(player, n, reason)` / `TrySpend(player, n, reason)` — non-yielding, integer-only, no partial debit, both push `EmeraldUpdate`. The Cash → Gems marketplace migration is **ECON-01's** (owner decisions logged 2026-09-19 in `docs/trading-world/econ-01-dependencies.md` §6: marketplace = GEMS ONLY, trade sweetener = GEMS ONLY, bounds 1 … 1,000,000, `TrySpend`'s unguarded `%d` print after the debit is a **launch blocker** that must be fixed with it, D4 = (c) server writes `ItemName, Rarity, Mutation, Size, Serial, Price, Currency, SellerName, SellerUserId` on `BuyPrompt` and stops building the billboard). **None of it has landed**; ECON-01 has no named owner yet.

Consequence for this rework: the brief's loop ("Gems transfer correctly") is a *target state* that only ECON-01 can make true. TW-02 preserves the backend exactly as it is, and builds the stall presentation so it needs **no change** when ECON-01 lands: the client plate reads `BuyPrompt.Price` and a `Currency` attribute (💎 when `"Gems"`, `$` fallback while absent) and never parses money out of text.

## 5. Listing system (as it works today)

1. Owner fires `BoothList {Action="Add", Name, Price}` → server checks: profile loaded (`__noSave` refused), `Name` in `BrainrotMover.InfoByName`, `#listings < 3`, price `tonumber` / not NaN / floored / 1 ≤ p ≤ 1e9, `countListed + 1 ≤ CountOwned(name)` → `listings[]` gets `{ Id = nextListingId++, Name, Price }` → `refreshDisplays` + `pushManageState`.
2. Listings are **name-based**; the exact copy handed over is whichever `BrainrotMover.Take` picks (least `Mutations.Mult` copy). The tag shows `"<Mutation> <Name> #<Serial>"`. **`Size` (Huge/Massive) is dropped on every transfer path except the raid thief insert** (ECON-01 E5).
3. `Remove` by `Id`; `Unclaim` → `releaseBooth` (clears listings, sign back to "AVAILABLE STAND", prompt back to "Claim Stand").
4. Buy: `BoothBuy(boothIndex, listingId)` → listing exists · seller online (else `releaseBooth`, **no toast to the buyer**) · not self · buyer within 26 studs of `Counter` · both profiles loaded · bag space · `Cash ≥ Price` · seller still owns one · unique cap → **no-yield window**: `Take` → `Give` → `SyncBackpack` ×2 → debit/credit → `table.remove` → `PriceIndex.RecordSale` → refresh → `PushUpdate` ×2 → `Save` ×2 (a failed save logs `[BoothAudit] SAVE FAILED …` and retries every 30 s; **never rolled back**).
5. Prune every 3 s: drop listings the owner no longer owns; re-resolve tags.
6. `PlayerRemoving` → `releaseBooth`. Server restart → everything gone (nothing persists but completed-sale prices in `PriceIndex`).

## 6. Booth ID dependencies

- `BoothIndex` is the key of `booths[idx]` **and** the `BoothIndex` attribute the server writes on every `BuyPrompt`, which the client echoes back in `BoothBuy`. It must be a **number**, unique per stand.
- **Finding (new today): `BoothIndex` must be contiguous from 1.** `boothOwnedBy` (L170) and the prune tick (L474) walk `booths` with `ipairs`, which stops at the first hole. The live island has only 7–12, so on a live server `boothOwnedBy` returns nil for everyone: "you already have a stand" never fires (one player can claim every stand), `BoothList Add/Remove/Unclaim` all fall out at `if not booth then return end`, the prune never runs, and `PlayerRemoving` never releases a stand. Nobody has hit it because the world is closed. The GE build (1–12) would have been correct by accident. **The new settlement issues `BoothIndex` 1 … N with no gaps — a generator self-check, not a convention.**
- The `Booths` folder is enumerated at boot only; the count is free (TW-01 planned 30; the brief targets a world that feels full at 15–25 players).
- `ServerStorage.PreCove_Backup_2026_08_02.TradingCenter_OLD` still holds the original `Booth1`–`Booth6` bodies — not needed (the contract is six names and one attribute; the shells are rebuilt anyway).

## 7. Teleport / spawn dependencies

| Dependency | Value / rule | Owner |
|---|---|---|
| `TeleportService.TRADE_POS` | `Vector3.new(8000, 2004.6, 7818)`, facing `FORWARD` (+Z); every route into the world lands here (`portalDests.Trade`, `travelToWorld("Trading")`, the dead `TeleportTo("Trade")` branch L203–204). Needs walkable ground within ~2 studs below (today `ArrivalPad` top 2002.8). **Keep the constant** (owner decision D8; the file is Beast's in-flight lane, +46 B live vs mirror — `TUNDRA_LOOK` is live). | Beast / owner |
| `GameWorld.Portals.<Model>.PortalTouch` attr `Dest` | any portal model under `Portals` binds on `ChildAdded`; `HubPortal` (`Dest = "Hub"`) is the way home. It may be **re-pivoted freely** (attributes unchanged) — and must be, off the arrival axis. | TW-02 (pivot only) |
| `Portals.TradePortal` (valley, (0, 11, −303)) | the only door in; `ComingSoonMessage`; **untouched** (Duck's lane) | Duck |
| `BoundsGuard` region `Trading` | X 7300–8790 · Y 1930–2110 · Z 7375–8725 (1,490 × 180 × 1,350 studs); every walkable surface must stay inside with margin, or players are rubber-banded to the valley spawn. Not edited. | shared |
| `WorldTravelConfig` | `{ Id = "Trading", Region = "Trading", Dest = "Trade", ComingSoon = true }` — the world stays shut through the rebuild; deleting that one line opens every door. Not edited. | owner |
| `Workspace.SpawnLocation` | (0, 33, −180), the only spawn; death anywhere → valley. Not edited. | never |
| `WorldProgression.Trading = { Alias = "Valley" }`, NAV buttons (Skip/Shops/Plot resolve to the valley from the island) | no geometry | — |
| `StreamingEnabled = true` | radii are plugin-security (unreadable from the command bar) — read from the Properties panel before the playtest; a dense settlement with obscured sightlines suits streaming, and any client dressing binds on `DescendantAdded` (the `TradeClient` pattern) | — |

## 8. What can safely be removed

| Remove | Count | Why |
|---|---|---|
| `GameWorld.TradingWorld_GE` + `GameWorld.TradingCenter_GE` (whole) | 1,306 parts | TW-01's Grand Exchange — the "giant central structure + booths around the centre" composition the brief rejects; never cut over; nothing references it; clones/rollback don't depend on it |
| `ServerStorage.TradingWorldBuild.Generator` | 1 module | superseded by the TW-02 generator (kept only until the new one exists, then deleted; its `mk / model / light / booth / Contracts` helpers are the seed of the new one) |
| `TradingWorld.Island`, `Bridges`, `Causeway`, `MarketArch`, `CliffCove`, `Palms`, `TikiTorches`, `SaleBoards`, `IndexGate`, `RewardChests`, `CoveBarrier`, `ArrivalDeck`, the stray unanchored `Part` | ~500 parts | the beach-island identity; nothing reads any of it (owner already approved dropping chests and IndexGate) |
| `TradingWorld.CoveDressing` incl. `CoveDriver`, `SkippersSpire` (904-stud beam), `ColossalArch`, `WorldEdge`, `Monuments`, `FloatingIslets`, `WaterDressing`, `AmbienceAnchors` | 254 desc | replaced by settlement dressing and (Phase 6) a `SettlementDriver` on the same conventions |
| `CoveDressing.Guardians` (six colossal Brainrot statues at r138, 214 desc, 6 Highlights) | 6 models | **decision needed** — TW-01 kept them; the new brief says "DO NOT use giant decorative statues". See §11 |
| `TradingCenter` gazebo (`Floor`, `Podium`, `PodiumRing`, pillars, beams, trims, `SignBoard`) | 21 parts | the central structure |
| `Booth7`–`Booth12` **bodies** | 6 models | replaced by stall shells inside buildings (same six contract names, indices reissued 1 … N) |
| `EternalSkip` + `SkipLoop` | 10 | **decision needed** (keep as river DNA, retuned, or retire) — see §11 |

## 9. What must remain (exact)

1. `Workspace.GameWorld` · `GameWorld.TradingCenter` (**Folder**, name) · `TradingCenter.Booths` (**Folder**, name) · `TradingCenter.TradeZone` (**one** BasePart, direct child; position/size free; ±6 Y slack in code).
2. Per stand: `Model` with numeric **`BoothIndex` 1 … N contiguous** · `Counter` (BasePart) · `Counter.StandPrompt` (ProximityPrompt; keep reach 8 / hold 0.3 / `ObjectText "Market Stand"`; `ActionText` may be authored `"Claim Stand"` — the server overwrites it) · `Display1`, `Display2`, `Display3` (BaseParts; the cube lands 1.7 studs above each, in the anchor's frame — so anchors are level, and 1.7 + 0.9 of cube must clear counters/awnings) · `SignBoard` (BasePart) ▸ SurfaceGui ▸ TextLabel (the server writes it; face it toward the street). `ListingDisplay` / `BuyPrompt` are never pre-authored.
3. `GameWorld.TradingWorld` (**Folder**, name — `CenterpieceSpinner` looks for it; contents replaceable).
4. `GameWorld.Portals.HubPortal` with `PortalTouch` `Dest = "Hub"` (re-pivoted, attributes unchanged); `Portals.TradePortal` untouched.
5. Walkable ground under `TRADE_POS` (8000, 2004.6, 7818); arrival facing +Z.
6. Everything walkable inside BoundsGuard `Trading`, with margin.
7. Untouched files: `BoothHandler`, `TradeHandler`, `BrainrotMover`, `GiftService`, `StealService`, `FusionHandler`, `OfferingHandler`, `PriceIndex`, `ItemStatsService`, `EmeraldService`, `PlayerDataManager`, `BagConfig`, `SizeConfig`, `MutationConfig`, `ProductRegistry`, every quest/season config, every remote (ECON-01); `BoothClient`, `TradeClient`, `IndexClient`, `WorldsPanel`, `UIKit.*`, `InteractionPrompt*`, `NumberFormat` (Pete); `TeleportService`, `BoundsGuard`, `WorldTravelConfig`, `WorldTravelService`, `WorldProgression`, `Main` (shared); `Lighting` globals and existing children, `Terrain`, `Workspace.SpawnLocation`, `PlayerBases`, every other world folder, NPC-01 rigs and assets.
8. The 2026-09-19 backups and `Rollback` module (they restore the *old* island; a new set is made for the new one before cutover).

## 10. Risks

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | **Currency premise.** The brief assumes a Gems marketplace; the live backend is Cash. If TW-02 built gem plates against `$` data, the presentation would lie. | High (design) | Presentation reads `BuyPrompt.Price` + `Currency` attribute with a `$` fallback; the world never hard-codes the currency; ECON-01 E1/E13 flip it with no world edit. Launch still gated on ECON-01 (`TrySpend` blocker). |
| R2 | **`BoothIndex` holes silently break claim/unclaim/prune/leave** (§6). | High (correctness) | Contiguous 1 … N enforced by the generator's `Contracts()` self-check; probe V-series re-runs the full loop on the new stands. |
| R3 | **Other lanes are publishing** (96 versions in a day). Any script TW-02 touches (`SkipLoop`, a new driver, generator) can be overwritten by a Team Create session or overwrite theirs; a Play start mid-generation leaves a half-built world. | Medium | Build in a quiet Edit window with the owner; generator idempotent (`ClearAll()` → rebuild); re-run the mirror byte-check on the 39 trading-stack scripts right before Phase 2; every touched script mirrored byte-exact with a `_MANIFEST.txt` diff. |
| R4 | **`TeleportService` is Beast's in-flight file** (+46 B live vs mirror). The `TeleportTo("Trade")` server branch still bypasses `ComingSoon` (no client fires it). | Medium | `TRADE_POS` kept, no edit; the E12 gate stays ECON-01's integration task. |
| R5 | **`HubPortal` sits 2.3 studs behind the arrival point** — walking backwards on arrival exits the world. | Medium (UX) | New arrival dock places the way home off-axis and in view (a boat / boathouse door beside the landing), ≥ 15 studs from `TRADE_POS`. |
| R6 | **Density vs. the 45–60 s crossing target inside a 1,490 × 1,350 box** — a settlement that spreads to fill the box kills density. | Medium (design) | Footprint capped ≈ 520 × 420 studs (path length 900–1,200 studs through winding streets, not straight-line); the blockout's Phase 3 walk test measures it. |
| R7 | **Mobile navigation** with elevation and narrow alleys (camera clipping in covered spaces, stairs too steep). | Medium | Stairs ≤ 1:2 with 4-stud treads, alleys ≥ 8 wide, covered spaces ≥ 12 high, no mandatory jumps; Studio Device Simulator (iphone_16) captures in Phase 3 and 7. |
| R8 | **Performance**: 58.6k parts already in `Workspace`; dense architecture invites part bloat. | Medium | Budget carried from TW-01: ≤ 4,500 parts for the whole world, ≤ 48 local lights (Range ≤ 60), ≤ 20 emitters, ≤ 10 Highlights, ≤ 2 Workspace scripts, no unions, reusable kit pieces; `Stats()` printed after every generator run. |
| R9 | **Streaming** removes/recreates the whole world per visit; a client-side stall dressing that captures instances once goes dead. | Low | `DescendantAdded` binding (the `TradeClient` / `StallPrompt` pattern); the `Booths` folder is server-enumerated so the backend is unaffected. |
| R10 | **NPC-01 lane** may have started placing rigs on TW-01's `NpcPost_*` marks (11 roles incl. two Vault guards that have no Vault any more). | Low–Medium | Roles re-homed into settlement locations (§12); posts re-issued only after the blockout is approved; `npc-roles-for-npc01.md` updated then, not before. |
| R11 | **Guardians decision** — keeping six 30–90-stud colossi contradicts "no giant statues"; removing them drops six Highlights and 214 parts of finished art. | Low | §11 D2. |
| R12 | **Stale `.rbxl`** — the only full-place backup predates 96 published versions. | Low | Owner saves a fresh `.rbxl` (File → Download a Copy) at the start of the Phase 2 window; Studio clones + `Rollback` re-made for the new build before any cutover. |

## 11. Decisions needed before Phase 2 (with TW-02's recommendation)

| # | Decision | Options | Recommendation |
|---|---|---|---|
| **D1** | **Where to build.** | (a) **In place** on the existing datums: delete both GE containers, remove the old island's geometry from `Workspace` (its clones + `Rollback` stay in `ServerStorage`), build the settlement around `TRADE_POS` and `HubPortal`; or (b) stage at an offset beside the old island and cut over later (TW-01's method — but a 500-stud settlement does not fit beside the island inside the BoundsGuard box, and every coordinate is shifted at cutover). | **(a).** The world is closed, the old island is backed up three ways with a drilled rollback, and the owner already approved replacing it whole. Phase 3's arrival test needs the real `TRADE_POS` and `HubPortal`. |
| **D2** | **The six Guardians.** | (a) retire all six (they are the cove's identity); (b) keep one as a **relic** — a fallen colossus head / fragment half-buried in Collector's Row, at relic scale, the only survivor of "before the settlement"; (c) keep all six (TW-01's decision). | **(b)** — one fragment is environmental storytelling; six colossi ring the map like a theme park and are exactly the "giant decorative statue" the brief forbids. |
| **D3** | **Stall count for v1.** | 12 / **18** / 24 (generator parameter; `BoothIndex` 1 … N contiguous either way). | **18**, distributed by neighbourhood (Lower Market Street 7 · Waterfront 4 · Upper Market 4 · Old Bridge 2 · Collector's Row 1), so 15–25 players with a third of them selling fills the streets without a single empty row. |
| **D4** | **Currency boundary.** | (a) TW-02 builds presentation only; ECON-01 does the Cash → Gems edit (E1/E13); or (b) fold the E1 edit into TW-02. | **(a).** The gems edit must ship with the `TrySpend` blocker fix and the transfer contract (E4/E5) in one economy PR; a world lane should not open `BoothHandler`. The stall plate is currency-agnostic. |
| **D5** | **Eternal Skip.** | keep (retuned from a circle to a run along the river bay) / retire. | **Keep** — a stone forever skipping down the river is Skip Rocks DNA, not a system. If the river geometry makes the orbit look wrong in the blockout, retire it then. |
| **D6** | **P2P `TradeZone` placement.** | one small social square (e.g. under the Old Bridge's south arch) / the arrival dock / the whole Lower Market Street. | A small square by the water at the Lower Market / Waterfront split (≈ 40 × 40 × 22) — traders meet somewhere visible, not in the road. |

## 12. Phase 2 approach (for approval — nothing started)

- **Method:** one build-time ModuleScript, `ServerStorage.TradingWorldBuild.SettlementGenerator` (replacing `Generator`), run from the command bar in Edit mode section by section, every section `pcall`-guarded, idempotent (`ClearAll()` then rebuild), one numbers table at the top, `Contracts()` self-check (`OK N/N stands; BoothIndex contiguous; one TradeZone; ground under TRADE_POS; HubPortal ≥ 15 studs off-axis; all parts inside BoundsGuard with ≥ 60 margin`), `Stats()` (parts / lights / emitters / scripts / bbox) after every run. Greybox materials only (SmoothPlastic / Concrete / a dark WoodPlanks for walkable surfaces so the walk test reads levels), no dressing, no lights beyond what the test needs, no scripts in `Workspace` except a kept `SkipLoop` if D5 = keep.
- **Output:** `GameWorld.TradingWorld` (Folder, rebuilt contents: `Land`, `Water`, `ArrivalDock`, `MarketEntrance`, `LowerMarket`, `Waterfront`, `UpperMarket`, `OldBridge`, `CollectorsRow`, `Stairs`, `NpcSpots`) and `GameWorld.TradingCenter` (Folder: `Booths` with `Booth1` … `BoothN` stall modules placed inside the building shells, `TradeZone`). Every stand shares one reusable module (`Counter` + `StandPrompt` + three `Display` anchors + `SignBoard`) dropped into different shells (window, counter under stairs, dockside, bridge-side, under an awning).
- **Footprint:** the settlement runs **along the water on the X axis** (a riverside town is long, not round), ≈ 520 × 420 studs, centred near the old island so `TRADE_POS` is the south-west arrival dock and the Old Bridge crosses the river inlet toward Collector's Row; ground datum P = 2002.4 for the Lower Market, +8 … +14 for the Upper Market, water at y 2000 (Terrain) with part water only where the blockout needs a wadeable edge.
- **Checks before Phase 3:** the aerial capture must not read as a circle / plaza / hub; the walk test (Phase 3 questions) is run on the greybox with the Device Simulator; the booth loop is probed on the new stands (claim → list → buy → transfer → unclaim → leave) with two accounts or the `DataUpdated` seam before any architecture pass.
- **Backups first:** fresh `.rbxl` by the owner; `ServerStorage.TradingWorldBackups_<date>` re-made (old island already cloned; the GE is not worth cloning — it is regenerable from `Generator` and is in the 2026-09-19 `.rbxl`); `Rollback.Verify()` run before the first `ClearAll()`.

---

*Stopped for the owner's decisions D1–D6 and approval of §12. Nothing in Studio was modified.*
