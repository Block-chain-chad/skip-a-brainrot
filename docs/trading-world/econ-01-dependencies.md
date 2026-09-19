# ECON-01 — Trading Economy / Transfer Integrity: dependency list from TW-01

**Date:** 2026-09-19 · **From:** TW-01 (Trading World rework) · **To:** ECON-01 (opens after the current integration / delta-sync gate) · **Status:** requirements only — no shared economy code has been edited by TW-01.

Decisions received from the owner: booth listings use Gems; direct P2P trades may include Gems; Cash is not a player-to-player currency; no mixed Cash + Gem sweeteners at launch; the unified identity contract is directionally approved; the ComingSoon bypass is a launch blocker fixed in the integration pass, not by TW-01; `MAX_GEM_PRICE` is not locked until the audit below is reviewed.

Source detail: `docs/TRADING-WORLD-REWORK-PHASE1B-INSPECTION.md` §7 (payment audit), §8 (transfer contract), §9 (bypass), §11 (D4).

## 1. Gem economy audit (inputs for choosing the listing bounds)

All numbers read from the mirror files that byte-matched live on 2026-09-19 (`EmeraldService`, `EmeraldPackConfig`, `SeasonConfig`, `EggConfig`, `StealConfig`, `MichelQuestConfig`, `TundraQuestConfig`, `DailyRewardConfig`, `NumberFormat`, `SessionLock`, `PlayerDataManager`).

| Question | Finding |
|---|---|
| Current gem balances | **Not readable from Studio** without DataStore API access, and there is no gem leaderboard or aggregate (the boards are Earned / Time / Caught, all cash or counts). Balances are one integer field per profile, `data.Darrels`, default 0. TW-01 did not query player profiles. The envelope below is derived from the faucets instead. |
| Daily-quest gem rewards | 16–40 gems per quest on a difficulty curve (`EMERALDS_MIN/MAX`), 3-quest daily slate ≈ 86/day; weekly slate 22–52 × 5 ≈ 188/week (≈ 27/day); perfect throws 2 gems each, capped 60/day; daily login reward tier 30 gems (`DailyRewardConfig`, fallback 5,000 cash); season pass tiers 20 → 320 (valley ladder, ≈ 1,230 per 26.5-day season) or 35 → 480 (forest ladder, ≈ 1,915); one-offs: Michel quest **1,000**, Tundra quest 150 + 300, raid consolation 20. **Steady free income ≈ 250 gems/day for an active player (~90k/year); one-offs ≈ 1,450.** |
| Robux gem packs | 80 / 180 / 400 / 1,000 gems for R$99 / 199 / 399 / 899 (developer products, live) — ≈ 0.8–1.1 gems per Robux, unlimited repeat purchase. |
| Maximum normal balance possible | No cap anywhere. Free-only: ~5k in a month, ~90k in a year. Robux: unbounded — 100 Hoard packs = 100,000 gems for ≈ R$90k. Realistic population: most players 0–5k, heavy spenders 10k–100k. |
| Gem spending systems | Eggs 60–1,105 gems each (`EggConfig`; x3/x10 bundles discounted, up to ≈ 11k per purchase); season-pass egg tiers refund the egg price on a failed hatch; raids are Robux (79 / 499 / 1,999) not gems; pets, charms and shops per their configs. After D1: booth purchases and trade sweeteners. |
| DataStore type / limits | Profile saved whole through `SessionLock.Save → UpdateAsync` (one key per user, JSON); value limit 4 MB, nowhere near it; balances are Lua doubles — integers exact to 2^53 ≈ 9.0 × 10^15. |
| Numeric precision / robustness concerns | (1) `EmeraldService.TrySpend` deducts first and then prints with `%d` **outside a pcall** (L274); a non-integer `Darrels` (a corrupted or hand-edited save — the module's own comment admits the case) would throw *after* the debit and abort the caller — with booths that means gems gone, no item. `Award` already guards its print with `tostring` in a pcall. ECON-01: floor `Darrels` on load in `PlayerDataManager` and make `TrySpend`'s print safe before booths use it. (2) `NumberFormat.Short` truncates to two decimals (1,234 → "1.23K") — fine for browsing, wrong for confirmation. (3) `BoothHandler`'s price parse (`tonumber`, NaN check, floor, 1 ≤ p ≤ max) correctly rejects NaN, ±inf, negatives and fractions; keep it. (4) The client `parsePrice` accepts `k / m / b / t` suffixes — `m/b/t` are cash-era and invite six-figure typos. |
| Expected Secret / God / Huge / Massive prices | The game already prices rarity in Robux for raids: Default R$79, **Secret R$499, God R$1,999** — at ≈ 1.1 gems/R$ that is ≈ 90 / 550 / 2,200 gems. Income multipliers the market will price around: Golden ×2, Diamond ×5, Rainbow ×12, Glitched ×31; Huge ×3, Massive ×8 (they stack). Working expectation: Common–Epic 1–50 · Legendary 50–200 · Mythic 200–500 · Secret 500–3,000 · God 2,000–10,000 · Golden/Diamond/Huge multiply into tens of thousands · a Diamond Massive God or a Glitched top-tier could be asked at 100k+. |

**Recommendation (for approval, not implemented):**

- **Listing minimum: 1 gem** (integer).
- **Listing maximum: 1,000,000 gems** — ≈ 10× a heavy spender's plausible balance and ≈ 10× the most extreme stacked ask; blocks typo-scale numbers without ever binding a real sale. If the owner expects super-rare stacks to trade above that, 10,000,000 is the next safe stop; both are far inside double precision.
- **Input validation (server, `BoothList Add` and `TradeAction SetGems`):** integer only (`math.floor`, reject NaN/±inf/negative), `1 ≤ p ≤ MAX_GEM_PRICE`, the server copy of the price is what the buyer pays (never a client-sent number at buy time), listing price immutable once listed (remove + relist to change). Client entry: plain integers and `k` only (`2.5k` → 2,500), no `m/b/t`.
- **Display formatting:** browsing surfaces (price plate, marquee, stand cards) show `💎` + `NumberFormat.Short` (`1.23K`, `2.20K`, `12.50K`) — readable at a glance, and truncation means a price never reads *higher* than it is; **every purchase confirmation and every toast shows the exact integer with thousands separators** — e.g. `Buy Golden Tim Cheese for 12,500 Gems? You have 15,340 Gems → 2,840 after.` — which needs a new `NumberFormat.Exact(n)` (grouping) helper (Pete/ECON-01; the module has no grouping formatter today). Balance chip stays `NumberFormat.Short` as it is.

## 2. ECON-01 dependency list (final)

| # | ECON-01 owns | Requirement (from TW-01's audit) | Files | Report ref |
|---|---|---|---|---|
| E1 | Cash → Gem marketplace migration | `TrySpend(buyer)` before anything moves; `Award(seller)` after the buyer holds the item; refund via `Award` on a transfer miss; seven `$` strings → gem wording; `Currency = "Gems"` attribute on `BuyPrompt`; buyer toast when the seller has left (gap found) | `BoothHandler`, `BoothClient` (Pete), `IndexClient` (Pete) | §7.1, §7.3, §7.4 |
| E2 | Direct-trade gem sweetener | `SetCash` → `SetGems` (clamped to `Darrels`), netted at execute with `TrySpend`/`Award` both sides inside the no-yield window; no Cash sweetener at launch; client labels | `TradeHandler`, `TradeClient` (Pete) | §7.4 D1b |
| E3 | Atomic transaction logic | the §7.3 sequence; no yield from the first check to the last write; duplicate purchase impossible by construction; failure = nothing moved or a logged refund | `BoothHandler`, `TradeHandler` | §7.3 |
| E4 | Unified ownership-transfer contract | `IDENTITY_FIELDS` whitelist, `OWNER_FIELDS` reissued, `IdentityOf / IsTransferable / CanReceive / TakeByUid / Give / Transfer`, invariants I1–I8; every path (booth, trade, gift, raid, any future) goes through `Transfer` | `BrainrotMover`, `BoothHandler`, `TradeHandler`, `GiftService`, `StealService` | §8.3 |
| E5 | Huge/Massive preservation | `Give` writes `Size` into the saved entry (today it only reaches the visual); listings/offers by `Uid`; fusion/offering never consume an oversized copy by name | `BrainrotMover.Give`, `FusionHandler`, `OfferingHandler` | §8.2 |
| E6 | Golden/Diamond preservation | same mechanism (`Mutation` in the whitelist; today preserved only because `Take` prefers the least-mutated copy) | `BrainrotMover` | §8.1 |
| E7 | UID / GUID strategy | per-profile `Uid` reissued on receipt (documented why it cannot cross owners); optional additive `Guid` at every insert site for provenance | `PlayerDataManager.TakeUid`, `ThrowHandler`, insert sites | §8.1 |
| E8 | Marketplace price validation | min 1, max per §1 (approval pending), integer-only, server copy authoritative, `k`-only client entry | `BoothHandler`, `BoothClient` | §1 above |
| E9 | Transaction logging / exploit safeguards | `[Transfer]` line per move; `[Emeralds] ±n` already logged; `[BoothAudit]` keeps its shape with gems; radius, self-buy, `__noSave`, bag space, unique cap, `PlotFav` all server-side; `TrySpend` `%d` guard | `BoothHandler`, `EmeraldService` (print guard), `PlayerDataManager` (floor on load) | §7.3, §1 above |
| E10 | Stale listing handling | prune by `Uid` presence / transferability every 3 s; buy-time recheck; release on leave | `BoothHandler` | §7.1 (9) |
| E11 | Failure / rollback behaviour | keep "never roll back after the swap; audit + retry"; refund path before the swap; `TrySpend` cannot partially debit | `BoothHandler`, `TradeHandler` | §7.1 (7) |
| E12 | ComingSoon bypass (launch blocker) | **exact required server check:** in `ServerScriptService.TeleportService`, delete the `elseif destination == "Trade" then teleportCharacter(player, TRADE_POS, FORWARD)` branch (live L203–204); in `travelToWorld`, before `CanTravel`, `if WorldTravelConfig.IsDestComingSoon(dest.Dest) then notify(player, …coming soon…) return end`; `warn` on any unmatched destination string; `passesLock` keeps its existing `IsDestComingSoon` check. Server-authoritative; one config line gates every door. Apply only after Beast's in-flight `TeleportService` edit lands (+46 B live vs mirror). | `TeleportService` | §9 |
| E13 | Display data contract (if D4 = c) | server writes `ItemName, Rarity, Mutation, Size, Serial, Price, Currency, SellerName, SellerUserId` on `BuyPrompt`; stops creating the BillboardGui/Neon cube; keeps `ListingDisplay` as an invisible anchor | `BoothHandler.refreshDisplays` | §11 |
| E14 | PriceIndex | store `_v1 → _v2`, sanity ceiling 1e12 → 1e7, key `Name|Mutation|Size` | `PriceIndex`, `ItemStatsService` (unchanged), `IndexClient` label (Pete) | §7.4 |

Tests T1–T20 (§8.3 of the report) are the acceptance suite for E1–E11.

## 3. Files / systems TW-01 will own

- `GameWorld.TradingWorld_GE` and `GameWorld.TradingCenter_GE` during the build, then the renamed `TradingWorld` / `TradingCenter` after cutover: all geometry, the 30 booth modules (contracts exactly as today), `TradeZone` (the part), `NpcPosts`, dressing, totems, boards' geometry.
- `GameWorld.Portals.HubPortal` (re-pivot only, attributes unchanged) and the new `GameWorld.Portals.HubPortalVault` (attributes only).
- `ServerStorage.TradingWorldBuild.Generator`, `ServerStorage.TradingWorldBackups_<date>` (+ `Rollback`), `ServerStorage.AuditBackups.PreGrandExchange_<date>`.
- `Workspace.GameWorld.TradingWorld.*.ExchangeDriver` (new, CoveDriver conventions) and the two constants in `EternalSkip.SkipLoop`; consumers of `CenterpieceSpinner`'s `Spin` attribute (the script itself untouched).
- `BoothDressingClient` (client presentation only, **after** D4 is decided and only under (a) or (c)); `TradingAtmosphere` + a `Lighting.TradingGrade` child on the `TundraAtmosphere` pattern (Phase 3, needs the owner's nod because it adds a child under `Lighting`).
- `docs/TRADING-WORLD-*.md`, `docs/trading-world/*`, the shared brief doc.

## 4. Files / systems TW-01 must NOT touch

- **ECON-01:** `BoothHandler`, `TradeHandler`, `BrainrotMover`, `GiftService`, `StealService`, `FusionHandler`, `OfferingHandler`, `PriceIndex`, `ItemStatsService`, `EmeraldService`, `PlayerDataManager`, `BagConfig`, `SizeConfig`, `MutationConfig`, `EmeraldPackConfig`, `ProductRegistry`, every quest/season config, every `Remotes` shape.
- **Pete (UI):** `BoothClient`, `TradeClient`, `IndexClient`, `WorldsPanel`, `UIKit.*` incl. `InteractionPrompt`, `InteractionPromptClient`, `NumberFormat`, HUD chrome.
- **Shared / owner:** `TeleportService` (Beast in flight; E12 is ECON-01's), `BoundsGuard`, `WorldTravelConfig` (`ComingSoon` is the owner's switch), `WorldTravelService`, `WorldProgression`, `Main`.
- **Never:** `Lighting` globals and existing children, `Terrain`, `Workspace.SpawnLocation`, `PlayerBases`, the valley `GameWorld.Portals.TradePortal` (Duck), anything under `FrozenTundra` / `LushGardens` / the valley folders, NPC rigs and assets (NPC-01), the internals of the six `Guardians` (kept as-is).

## 5. Decisions still open (none blocks the greybox itself)

| Decision | Blocks | Default TW-01 assumes if silent |
|---|---|---|
| Integration gate (Duck World 1 checkpoint, Pete UI checkpoint, delta sync / combined QA) | the whole Phase 2 window | wait |
| A quiet Edit window + the owner's `.rbxl` save | greybox start | wait |
| D4 (a / b / c) | the display layer only (Track W step 9); not the geometry | none — no work on it |
| Listing bounds (§1) | ECON-01 E8; launch | none until approved |
| ECON-01 opening + owner | launch (not the greybox) | after the gate |
| D5 boards feed | nothing (static boards in Phase 2) | static |
| D8 `TRADE_POS` | nothing | keep |
| D12 Eternal Skip | nothing | keep, retune to the moat |
| D13 old chests / IndexGate | nothing | drop |
| NPC-01: does the dialogue shell support an action button (Gem Broker)? | role 2's interaction only | dialogue-only fallback |
| Streaming radii (Properties panel read) | Track W step 8 tuning | assume defaults |
