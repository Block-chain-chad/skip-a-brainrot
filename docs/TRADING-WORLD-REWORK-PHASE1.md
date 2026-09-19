# TRADING WORLD REWORK REPORT — Phase 1 (lane TW-01)

**Game:** Skip Rocks for Brainrots (PlaceId `78783087742939`, universe `10549950910`)
**Lane:** TW-01 — Trading World full rework · **Phase:** 1 (audit + design, no build)
**Date:** 2026-09-19 · **Branch:** `trading-world-rework` (worktree `../skip-a-brainrot-trading-world`, based on `source-sync-audit` @ `b29c541` — the 2026-09-19 byte-exact mirror of PlaceVersion 2353)
**Studio:** NOT touched. Nothing deleted, moved or edited in the live place. This report is built from the repo mirror and the project docs only.

Companion files: `docs/trading-world/grand-exchange-layout.svg` (top-down district layout) · `docs/trading-world/npc-roles-for-npc01.md` (the NPC-01 handoff, also reproduced in §B.1.5).

---

## 0. Read this first — the six findings that change the plan

1. **The Trading Island is currently HELD BACK.** `ReplicatedStorage.Modules.WorldTravelConfig` carries `ComingSoon = true` on the `Trading` destination (2026-08-23, owner note: *"the trading centre isnt great right now"*). The Worlds board draws COMING SOON, fast travel refuses everyone, and the valley `TradePortal` turns walkers away (`TeleportService.passesLock` checks `IsDestComingSoon` first). **No player can reach the island today**, so a full visual rebuild carries almost no live-player risk — and "shipping" the rework is literally deleting one line. `TradeHandler`/`BoothHandler` are left running and reachable only from inside the island.
2. **Booths and trades are denominated in Cash (`$`), not Gems.** Every path — `BoothHandler` (`buyerData.Cash -= listing.Price`, `PlayerDataManager.GrantCash(seller…)`), `BoothClient` (`"$" .. formatNumber(price)`), `TradeHandler` (`offer.Cash`) — is Cash, in the mirror synced 2026-09-19. The brief's "GEM PRICE" is therefore either a planned economy change (belongs to the economy owner, not TW-01) or an assumption. **Decision D1.** Everything in this design is currency-agnostic: "the price" is one big number plus one currency glyph, whichever currency the owner picks.
3. **Huge/Massive is LOST by every name-based transfer.** `BrainrotMover.Take(giver, data, name)` (used by booth sales and P2P trades) builds the transfer record as `{ Name, Mutation, Serial, MintedAt }` — no `Size`. `TakeByUid` (used by gifting) carries `Size`. So a Massive brainrot sold at a stand arrives as a normal-size copy, and `Take` also cannot avoid picking the Huge copy when several copies share a name. The brief asks booths to show the Huge/Massive modifier; today the listing cannot even know it. **Decision D2 — economy owner.** Not fixed here.
4. **The repo holds scripts only.** Terrain, models, booths, decorations and GUI instances are not in git (see `game-src/place-full/README.md`). The world-object inventory below is reconstructed from `docs/superpowers/specs/2026-08-02-skippers-cove-design.md`, `docs/cove-rebuild-woah-2026-08-09.md` and every script that names an object. Exact part counts, current positions and anything moved since 2026-08-09 need one read-only Studio pass — the exact list is in §C.2.
5. **The mirror drifts.** `ui-foundation`'s copy of the trading stack is stale (its `BoothHandler` predates the 2026-08-09 boot-hang fix; its `BoundsGuard` lacks two regions). This audit uses `source-sync-audit` (490/496 live scripts byte-identical on 2026-09-19). Before Phase 2 touches any script, re-verify byte counts live (team rule in `game-src/place-full/README.md`).
6. **Sibling lanes are live on the same place right now:** `npc-01-character-overhaul` (worktree `../skip-a-brainrot-npc`), `world3-refinement`, `source-sync-audit`, Pete's `ui-foundation` (dirty working tree), and the World 2 blockout (Studio-only, `ServerStorage.World2Blockout`). This lane's branch touches only `docs/`.

---

# PART A — AUDIT OF THE CURRENT TRADING WORLD

Compass used in this report (same as the World 2 masterplan): **N = +Z, S = −Z, E = −X, W = +X.** Island centre **C = (8000, 2002.4, 8000)**. A player standing at the arrival point facing north has −X on their right hand and +X on their left. Every height is a walkable surface unless stated.

## A.1 Current Trading World structure

The Trading World is **Skipper's Cove** — a circular island in a terrain ocean, 8,000 studs from the valley, rebuilt on 2026-08-09 after the original island was lost (only the 2026-08-02 demolition made it into a save; the cove rebuild did not — see `docs/cove-rebuild-woah-2026-08-09.md`). It is the third "world" in a one-place, four-region game (`Valley`, `Trading`, `Tundra`, `Gardens`).

### A.1.1 DataModel hierarchy (from docs + script references — part counts as of 2026-08-09, unverified since)

```
Workspace.GameWorld
├─ TradingWorld            Model, ModelStreamingMode = Persistent   (~520 parts island geometry)
│  ├─ (seabed r120, plaza disc r62 top y2002.4, glass water ring r62–88 top y2002.0,
│  │   outer sand ring r88–118, CoveBarrier r121 invisible wall with a south gap,
│  │   4 arched bridges r58–92, MARKET arch pillars z7942, cliff cove N 40°–140° + 2 waterfalls,
│  │   palms, tiki torches, arrival deck r150–192 S + causeway)
│  ├─ SaleBoards           (W) three surfboard boards: TOP SALES / TOP TRADERS / RECENT SALES — PLACEHOLDER TEXT, no feed
│  ├─ IndexGate            (E) coral ring gate + `IndexGatePrompt` — NOT wired to anything
│  ├─ GroupChest / SocialBottle / VIP islet chest   props with `ClaimSpot` parts — claim logic NEVER wired (owner blocks Group/VIP ids)
│  ├─ EternalSkip          Model: Stone + Ring1–3 + Script `SkipLoop` (glowing stone orbiting r68 at 26°/s, splash rings)
│  └─ CoveDressing         Model (~296 parts, cap 1,800) + Script `CoveDriver` (the ONE Heartbeat for all dressing motion)
│       ├─ colossal crossed "tusk" arch over the causeway (z7878, apex +62)
│       ├─ 6-drum spire on the north cliff (8000, 8140), crown stone d17 at +148, sky beam to +900
│       ├─ 6 brainrot guardian statues (36–42 studs) on 8-stud plinths at r138, angles 0/60/120/180/240/300, breathing Highlights
│       ├─ 32 neon underglow chords in the water ring, 8 bobbing float stones, pooled 8-ring wake trail (WakePool, runtime only)
│       ├─ 12 rim bulbs + core bulb (hull read through the water), 16-part foam collar at r119 y1999.7
│       ├─ 7 orbiting islets (r50–92, +64…+112, 0.9°/s, CanCollide false)
│       └─ monuments: IndexGate pillars/halo, chest podiums + colour beams (Group blue / Social green / VIP gold) with PointLights, boards pavilion
├─ TradingCenter           Model, Persistent — restored from ServerStorage.PreCove_Backup_2026_08_02
│  ├─ TradeZone            Part 26×26×26 at (8000, 2007, 8000) — the gazebo — P2P trade requires BOTH players inside
│  ├─ (gazebo geometry)
│  └─ Booths               Folder
│      └─ Booth1…Booth12   Models on an arc r103, 35°–145°, facing centre. Each: attribute BoothIndex (1–12),
│                           Counter (BasePart) ▸ StandPrompt (ProximityPrompt), Display1/2/3 (BaseParts), SignBoard ▸ SurfaceGui ▸ TextLabel
└─ Portals
   └─ HubPortal            Model ▸ PortalTouch (attribute Dest = "Hub") at (7981, 2006, 7830), −X side of the arrival deck
                           (the cove doc calls this "west"; in this report's compass −X is EAST — coordinates win)

Workspace (Valley side): GameWorld.Portals.TradePortal ▸ PortalTouch (Dest = "Trade", PlaceName / ComingSoonMessage / RefuseX-Y-Z attributes)
```

### A.1.2 Coordinate-sensitive constants (all live in code — the world must fit them, or they must be edited in a coordinated round)

| Constant | Where | Value | Meaning |
|---|---|---|---|
| `TRADE_POS` | `ServerScriptService.TeleportService` L19 | `(8000, 2004.6, 7818)`, look `+Z` | Arrival point for the valley portal, the Worlds board and `TeleportTo("Trade")`. Ground must exist under it. |
| `HUB_POS` | same, L20 | `(24, 6, -16)`, look `−X` | Where `HubPortal` (Dest=Hub) puts you back in the valley. |
| `REGIONS.Trading` | `Modules.BoundsGuard` | `Min (7300, 1930, 7375)` → `Max (8790, 2110, 8725)` | Server containment box. Anything walkable outside it rubber-bands the player to the valley SpawnLocation after 2 strikes (0.5 s). The region **name** `"Trading"` is also the world id `PlayerDataManager.PlayerWorld` returns — `WorldTravelConfig`, `TeleportService.NAV`/`campWorld` and `WorldProgression` key on it. |
| `WorldProgression.Trading` | `Modules.WorldProgression` | `{ Alias = "Valley" }` | The island has no throw pool or rock shelf of its own. |
| `C`, `WAKE_RADIUS` | `TradingWorld.CoveDressing.CoveDriver` | `(8000, 2002, 8000)`, 400 | Dressing animation sleeps with nobody within 400 studs of C. |
| `CX, CZ, R, WATER_Y` | `TradingWorld.EternalSkip.SkipLoop` | `8000, 8000, 68, 2002.0` | Orbit centre/radius/water height of the Eternal Skip. |
| `BUY_RADIUS` | `Modules.BoothHandler` | 26 studs from `Counter` | Buyer must stand within 26 studs of the booth's Counter for `BoothBuy` to pass. |
| `BuyPrompt.MaxActivationDistance` | `BoothHandler.refreshDisplays` | 10 | Walk-up reach of a listing. |
| Terrain water surface | measured 2026-08-09 | y ≈ 1999.5 | The island sits in a terrain ocean shared with the main map. Terrain and `Lighting` are global — never edit them for this world. |

## A.2 Current booth system (`BoothHandler` server ▸ `BoothClient` client)

**Server authority is total** — "EVERY rule is enforced here on the server. The client UI can only ask." Summary of the live logic (not to be changed by this lane):

- **Claim.** `StandPrompt.Triggered` on an unowned booth → `booth.ownerUserId = player.UserId`, sign becomes `"<DISPLAYNAME>'S STAND"`, prompt text `"Manage Stand"`, owner gets `BoothState {Phase="Manage", Open=true}`. One booth per player (`boothOwnedBy`). Triggering someone else's booth → toast *"This stand belongs to X. Hold E on a display item to buy it."*
- **List.** `BoothList {Action="Add", Name, Price}`: profile must have loaded (`__noSave` refused), `Name` must exist in `BrainrotMover.InfoByName`, `#listings < MAX_LISTINGS (3)`, price integer `1 … MAX_PRICE (1e9)`, and `countListed+1 ≤ CountOwned`. **Listings are NAME-based** (`{Id, Name, Price}`), not Uid-based: the sale hands over whichever copy `BrainrotMover.Take` resolves (least `Mutations.Mult`). The display label re-resolves that copy's mutation + serial (`"Golden Tim Cheese #12"`) so buyers see what they will actually get. `Remove {Id}` and `Unclaim` also here.
- **Display.** `refreshDisplays` destroys and rebuilds, per listing slot `i`: a Neon Part `ListingDisplay` 1.8³ coloured by rarity tier at `Display<i>.CFrame * CFrame.new(0, 1.7, 0)`, a `BillboardGui` 130×40 px `AlwaysOnTop` with `"<label>\n$<price>"`, and a `ProximityPrompt` `BuyPrompt` (`ActionText "Buy for $…"`, `ObjectText <label>`, hold 0.3 s, reach 10, no line-of-sight) carrying attributes `BoothIndex, ListingId, ItemName, Price, SellerName`. **The server never connects `BuyPrompt.Triggered`** — the client listens on `ProximityPromptService.PromptTriggered`, shows a confirm modal, then fires `BoothBuy`.
- **Buy.** `BoothBuy(boothIndex, listingId)`: listing exists → seller present (else booth released) → not self → buyer within `BUY_RADIUS` → both profiles loaded → **bag space** (`BagConfig.HasBrainrotSpace`, 2026-08-20) → `Cash ≥ Price` → seller still owns one → unique cap. Then, with no yields: `Take` → `Give` → `SyncBackpack` both → `buyerData.Cash -= Price`, `GrantCash(seller)` → listing removed → `PriceIndex.RecordSale(record.Name, record.Mutation, Price, buyer, seller)` → refresh, `PushUpdate` both, `Save` both (audit line `[BoothAudit] SAVE FAILED …` + 30 s background retry if a save fails; **never rolled back**) → toasts to both.
- **Housekeeping.** `PlayerRemoving` → `releaseBooth` (listings dropped, sign `"AVAILABLE STAND"`, prompt `"Claim Stand"`). A 3 s prune tick drops listings the owner no longer owns and rebuilds tags whose resolved copy changed. **Nothing about a booth persists** — ownership and listings are in-memory per server.
- **Boot safety (2026-08-09).** `Init` uses `FindFirstChild` throughout and *stands down with a warn* if `GameWorld.TradingCenter.Booths` is missing or a booth lacks `Counter.StandPrompt`. (The `ui-foundation` mirror still shows the old `WaitForChild` version that hung the whole server boot at `Main:157` — every Init after `BoothHandler.Init()` never ran. Do not copy from that branch.)

**Client (`BoothClient`, 28,403 B, UIKit Tokens/Builders skin):** three screens — MY STAND (listing cards, CREATE LISTING tile, UNCLAIM), CREATE LISTING (inventory picker with tabs BRAINROTS / PETS "SOON", search, NAME/RARITY/VALUE sort, detail column with a `"price (e.g. 2.5k)"` box + LIST IT!), BUY ITEM (thumbnail, *"Are you sure you want to buy this item from @X?"*, price chip, CANCEL/CONFIRM). Registered with `SideRail` as the single-open group `"booth"`; opens a `BoothBlur` BlurEffect in `Lighting`. Booth UI panels are **Pete's UI lane** (the ui-foundation spec lists "Sell/Trade/Egg/Booth/Fusion cards" as future migrations onto `BrainrotCard`); TW-01 must not restyle them.

## A.3 Current trading systems

| System | Files | What it does | World dependency |
|---|---|---|---|
| **Player stands (booths)** | `Modules.BoothHandler`, `BoothClient` | §A.2 | `GameWorld.TradingCenter.Booths.*` contracts |
| **P2P trade** | `Modules.TradeHandler` (19,566 B), `TradeClient` (33,232 B) | Request (20 s timeout, one pending per target) → both build offers (name-based items + `Cash`, capped at owned) → any change un-confirms both → both confirm → 3 s countdown → server swaps (unique cap + bag space pre-flight, `Take`/`Give` per item, cash netted) → `Save` both, audit line, never rolled back. Remotes `TradeRequest / TradeRespond / TradeAction {AddItem, RemoveItem, SetCash, Confirm, Unconfirm, Cancel} / TradeState {Incoming, Sent, Active, Countdown, Completed, Closed, Error}`. | **Both players must be inside `GameWorld.TradingCenter.TradeZone`** (server box test, ±6 studs Y slack). The client polls every 0.3 s, and while you stand in the zone it shows a *"Pick a player to trade with"* list of every other player in the zone (*"Waiting for players to reach the gazebo…"* when alone). No ProximityPrompt is involved. |
| **Gifting** | `Modules.GiftService` (10,541 B) | Hold E on a player while holding a brainrot Tool → they accept → one-way transfer via `TakeByUid` (carries Size). | None — works anywhere. A social feature the new world can host without code. |
| **Price index** | `Modules.PriceIndex` (12,835 B) | 7-day rolling **median** of what players actually paid at stands, per `Name|Mutation`, `MIN_SAMPLES = 5` counterparty pairs before anything is published, one vote per unordered buyer/seller pair (anti-wash), 16 DataStore shards. | Fed only by `BoothHandler` sales. |
| **Item stats window** | `ServerScriptService.ItemStatsService` | `GetItemStats:InvokeServer({{Name, Mutation}…})` → `{Tracked, Minted, Exists, Price, Samples}` per key + `{WindowDays, MinSamples}`; ≤ 40 items per call, token bucket 6 / refill 1.5 s. Consumed by the Index panel. | None. **This is the existing, approved price-truth system** — any "market prices" board in the new world can read it without inventing values. |
| **Value boards** | `Modules.LeaderboardHandler` (`BOARDS`: TOP EARNERS / MOST TIME PLAYED / MOST BRAINROTS CAUGHT), `Modules.LeaderboardBoards` | Boards are **built at runtime in the valley lodge** (`BOARD_Z = -240`, folder `GameWorld.Leaderboards`, `LAYOUT_VERSION`); server-painted SurfaceGuis, repaint per fetch. | The island's `SaleBoards` are placeholders; no code paints them. |
| **Collection / Index** | `IndexClient`, `IndexPanel` | Brainrot Index panel (HUD). | The island's `IndexGate` prompt is not wired to it. |
| **Travel** | `TeleportService`, `Modules.WorldTravelConfig`, `Modules.WorldTravelService`, `GameHUDPanels.WorldsPanel`, `TeleportFadeClient` | Walk-through `PortalTouch` parts under `GameWorld.Portals` (any model, attribute `Dest`), `TeleportTo` remote (nav buttons + Worlds board), world curtain fade for far hops (`CURTAIN_IN 0.22 s`, hold `SETTLE 3.55 s` after arrival, fade out 0.35 s), `RequestStreamAroundAsync` before the hop. | `TRADE_POS`, `HubPortal`, region name `Trading`. |
| **Containment** | `Modules.BoundsGuard` | §A.1.2. Return point = the valley `SpawnLocation` (there is no per-world respawn; World 2 lane notes this is "being fixed separately"). | Region box. |
| **Cash / Gems** | `PlayerDataManager` (`Cash`), `Modules.EmeraldService` (gems; player-facing word "Gems", internal keys `Darrels`/`Emeralds`) | — | Booth/trade use `Cash` only (Finding 2). |

## A.4 Current player flow

1. **Getting there** — three doors, all landing at `TRADE_POS (8000, 2004.6, 7818)` facing north: the valley `TradePortal` (walk-through; refused with `ComingSoonMessage` while held back), the Worlds board row *"Trading Island — Booths, deals and other campers."* (TRAVEL button → `TeleportTo("Trading")` → `travelToWorld` → `CanTravel` → refused while `ComingSoon`), and the raw `TeleportTo("Trade")` branch (nav destination; **not gated by ComingSoon** — see D9). Far hops get the black curtain: 0.22 s in, stream wait ≤ 3 s, **3.55 s hold after arrival**, 0.35 s out — so the player's first sight of the island is a fade-in roughly 4 s after they touched the portal.
2. **Arrival** — on the arrival deck off-island (S), facing the causeway; the tusk arch, spire, sky beam, islets, guardians, gate and chest beams compose on the x = 8000 axis (verified numerically 2026-08-09).
3. **Walk in** — causeway → under the arch → south bridge over the water ring → plaza → gazebo (`TradeZone`) at the centre. Booths are on the far (north) side of the outer ring, r103, 35°–145°, i.e. **the booths are the furthest thing from arrival** (~285 studs of walking, ~14 s at WalkSpeed 21, before the first stand).
4. **Booth as seller** — hold E on a free `Counter.StandPrompt` → MY STAND opens → CREATE LISTING → pick → type price → LIST IT! → the neon cube + tag + BuyPrompt appear on `Display<i>`. Walk away; the stand keeps selling; a toast tells you when something sells. Leaving the game releases the stand.
5. **Booth as buyer** — walk within 10 studs of a cube, hold E → BUY ITEM modal → CONFIRM → `BoothBuy` → toast.
6. **P2P trade** — both stand in the gazebo box → pick a name from the nearby list → accept → build offers → confirm → 3-2-1 → done.
7. **Leaving** — walk back to `HubPortal` on the deck's −X (east) side (Dest=Hub → `(24, 6, -16)` in the valley), or press any nav button (Skip / Shops / Plot all resolve to valley coordinates for the `Trading` region), or die (respawn is the valley SpawnLocation).

## A.5 Current scripts and configs (live-synced 2026-09-19 unless marked)

`hash|bytes` are from `game-src/place-full/_MANIFEST.txt` on `source-sync-audit` (h31 method). "Owner" = which lane may edit it in Phase 2.

| DataModel path | Class | hash / bytes | Role for the Trading World | Owner |
|---|---|---|---|---|
| `ServerScriptService.Modules.BoothHandler` | Module | `f95dbd9f` / 20,288 | Stand claim / list / buy / prune / release; builds the in-world listing displays | **Economy — frozen** for TW-01 (presentation-only change under D4 needs approval) |
| `ServerScriptService.Modules.TradeHandler` | Module | `0429f8d4` / 19,566 | P2P trade; `isInTradeZone` box test | Economy — frozen |
| `ServerScriptService.Modules.BrainrotMover` | Module | `865aafef` / 6,910 | `Take` (name), `TakeByUid`, `Give`, unique cap, pad visuals | Economy — frozen (D2 lives here) |
| `ServerScriptService.Modules.GiftService` | Module | `a951ed86` / 10,541 | Hold-E gifting | Economy — frozen |
| `ServerScriptService.Modules.PriceIndex` | Module | `5959f866` / 12,835 | Median sale prices | Economy — frozen |
| `ServerScriptService.ItemStatsService` | Script | `87110039` / 5,194 | `GetItemStats` RemoteFunction | Economy — frozen (read-only consumer OK) |
| `ServerScriptService.Modules.BoundsGuard` | Module | `e45e2980` / 7,566 | `Trading` region box | Shared — edit only if the new island exceeds the box (it should not) |
| `ServerScriptService.TeleportService` | Script | `4f230a48` / 26,939 | `TRADE_POS`, portal binding, curtain, ComingSoon refusal | Shared — one constant may change under D8 |
| `ReplicatedStorage.Modules.WorldTravelConfig` | Module | `2ec1f5d9` / 5,571 | Worlds board row + the `ComingSoon` gate | Owner — the ship switch |
| `ServerScriptService.Modules.WorldTravelService` | Module | `d6eb74e0` / 7,345 | visited set, `CanTravel`, `Refresh` | Shared — no change expected |
| `ReplicatedStorage.Modules.WorldProgression` | Module | `8992521b` / 8,870 | `Trading = { Alias = "Valley" }` | No change |
| `ServerScriptService.Main` | Script | `aaeb3c06` / 12,193 | Init order: `TradeHandler.Init()` L156, `BoothHandler.Init()` L157, `BoundsGuard.Init()` L205 | No change |
| `ServerScriptService.CenterpieceSpinner` | Script | `2a895c83` / 854 | Spins + bobs any BasePart under `GameWorld.TradingWorld` with attribute `Spin` (RunService.Heartbeat, no sleep gate) | TW-01 may reuse the attribute; script itself is legacy-fine |
| `Workspace.GameWorld.TradingWorld.CoveDressing.CoveDriver` | Script | `8414e863` / 7,706 | The single dressing driver: tags `CoveOrbit / CoveSpin / CoveBreatheT / CoveBreatheH / CoveBob / CoveFallScroll / CoveAmbience`, 400-stud sleep gate, `WorkCount`/`Awake` probe attributes | TW-01 — replace with an equivalent single driver (same conventions) |
| `Workspace.GameWorld.TradingWorld.EternalSkip.SkipLoop` | Script | `73841159` / 1,615 | Eternal Skip orbit | TW-01 — keep, retire, or edit `R`/`WATER_Y` |
| `StarterPlayer.StarterPlayerScripts.BoothClient` | LocalScript | `52c720f7` / 28,403 | Booth UI | Pete (UI) |
| `StarterPlayer.StarterPlayerScripts.TradeClient` | LocalScript | `7edf18ca` / 33,232 | Trade UI + zone polling + nearby list | Pete (UI) |
| `StarterPlayer.StarterPlayerScripts.GameHUDPanels.WorldsPanel` | Module | `f56c5f5e` / 9,257 | Worlds board row (glyph 🤝, tint `(236,188,104)`) | Pete (UI) |
| `StarterPlayer.StarterPlayerScripts.TeleportFadeClient` | LocalScript | `78176afb` / 7,161 | World-hop curtain | No change |
| `StarterPlayer.StarterPlayerScripts.NpcFocusClient` | LocalScript | `050ac5f0` / 4,206 | The one shared NPC/prompt Highlight (budgeted for the engine Highlight cap) | NPC-01 / UI |
| `ReplicatedStorage.Modules.UIKit.InteractionPrompt` (+ `InteractionPromptClient`) | Module / LocalScript | round-3, in flight in `ui-foundation` | Walk-up prompt styling; `VERB_BY_NAME.StandPrompt = "CLAIM"`; `BuyPrompt` falls through to ActionText → "BUY" | Pete (UI) — new prompt names in the world must be registered there |
| `ReplicatedStorage.Modules.StallPrompt` | Module | `28e3de89` / 3,361 | Streaming-safe prompt binding pattern (StreamingEnabled is ON; parts stream out and back as NEW instances) | Pattern to reuse for any client-side booth dressing |
| `ReplicatedStorage.Modules.SizeConfig` / `BagConfig` | Module | `bb352fd5` / 3,542 · `7ef6c502` / 6,387 | Huge 1.65× / Massive 4.95× (D2); bag cap pre-flight | Economy |
| `ServerScriptService.Modules.LeaderboardHandler` / `LeaderboardBoards` | Module | `1f8e6026` / 9,701 · `a2d1100e` / 18,649 | Board data; boards built at fixed valley coords | Balkan / shared — D5 |
| `ServerScriptService.Modules.EmeraldService` | Module | `c5e8e009` / 20,194 | Gems | Economy |

**Remotes touched by the trading stack** (all under `ReplicatedStorage.Remotes`): `BoothState`, `BoothList`, `BoothBuy`, `TradeRequest`, `TradeRespond`, `TradeAction`, `TradeState`, `TeleportTo`, `TeleportFade`, `WorldTravelState`, `GetItemStats` (RemoteFunction), `GetInitialData` (RF), `DataUpdated`, `CashTick`, `PurchaseResult` (used as the generic notify), gifting's own remotes. **None of these change in this rework.**

**Studio-only backups that matter:** `ServerStorage.PreCove_Backup_2026_08_02` (the OLD island incl. `TradingCenter_OLD` with its Booths), `ServerStorage.AuditBackups.TeleportService_pre_coverebuild`, `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15` (BoothHandler/Main pre-rename), `ServerStorage.World2Backups_2026_09_19.Rollback` (the house pattern for a rollback script).

## A.6 – A.8 Object classification

Every major object, classified per the brief. "Contract" = the exact name/attribute/structure code depends on.

### A.6 FUNCTIONAL — MUST PRESERVE (name, structure and behaviour exactly; position free unless noted)

| Object | Contract | Why |
|---|---|---|
| `Workspace.GameWorld` | folder/model named exactly `GameWorld` | Every script walks `Workspace.GameWorld…` |
| `GameWorld.TradingCenter` (Model, Persistent) | name; `ModelStreamingMode = Persistent` | `BoothHandler.Init` (FindFirstChild chain), `TradeHandler.isInTradeZone`, `TradeClient` (`WaitForChild`) |
| `TradingCenter.TradeZone` (BasePart) | name; ONE box part — both server and client do `CFrame:PointToObjectSpace` + `Size/2` box math (Y slack ±6) | P2P trade gate + nearby-player list. **Position and size are free** (may be bigger; keep it a single box). |
| `TradingCenter.Booths` (Folder) | name | `BoothHandler.Init` enumerates its children |
| `Booths.<any name>` (Model) ×N | attribute `BoothIndex` (unique number) | Booth identity; N is free (12 today) |
| `<booth>.Counter` (BasePart) | name; must contain `StandPrompt` | Claim prompt; **`BUY_RADIUS` (26) is measured from `Counter.Position`** |
| `<booth>.Counter.StandPrompt` (ProximityPrompt) | name (also the `InteractionPrompt` verb key → "CLAIM") | Claim/Manage trigger; server rewrites `ActionText` |
| `<booth>.Display1`, `Display2`, `Display3` (BaseParts) | names; the listing cube spawns at `Display<i>.CFrame * CFrame.new(0, 1.7, 0)` | Listing anchors. `MAX_LISTINGS = 3`, so exactly three. Their CFrame orientation matters (the offset is in the anchor's local Y). |
| `<booth>.SignBoard` (BasePart) ▸ `SurfaceGui` ▸ `TextLabel` | names/classes; server writes `TextLabel.Text` (`"X'S STAND"` / `"AVAILABLE STAND"`) via `FindFirstChildOfClass` | Ownership signage — **this is the one in-world surface the server updates for free; make it big.** |
| Runtime children created by the server: `ListingDisplay` (Part) ▸ `BillboardGui` ▸ `TextLabel`, and `BuyPrompt` (ProximityPrompt with attributes `BoothIndex, ListingId, ItemName, Price, SellerName`) | must not be pre-authored (the server destroys every child named `ListingDisplay` on refresh) | Buy trigger — the client keys on `prompt.Name == "BuyPrompt"` + attributes |
| `GameWorld.Portals` (Folder/Model) | name | `TeleportService` scans it (`ChildAdded` too) |
| `Portals.HubPortal` ▸ `PortalTouch` (BasePart) | child named `PortalTouch` with attribute `Dest = "Hub"` (optional `RequiresKey / RequiresFlag / PlaceName / RefuseX-Y-Z / ComingSoonMessage`) | The way home. **Any number of portal models is allowed** — a second return portal is free. Position free. |
| Valley `Portals.TradePortal` ▸ `PortalTouch` (`Dest = "Trade"`) | untouched — Duck's World 1 lane | Entry |
| Ground under `TRADE_POS (8000, 2004.6, 7818)` | a walkable surface at ≈ y2004.6 (deck) within the region | Arrival. (Or change the constant — D8.) |
| `BoundsGuard.REGIONS.Trading` box | all walkable geometry inside `X 7300–8790, Y 1930–2110, Z 7375–8725`; keep a ≥ 40-stud margin (`X 7340–8750, Z 7415–8685, Y ≤ 2100`) | Containment; the region name `"Trading"` is the world id |
| `TradingWorld` (Model, Persistent) | name (the `CenterpieceSpinner` and `CoveDriver` look for it; `CoveDressing`'s driver parents under it); `ModelStreamingMode = Persistent` | Container. Contents are replaceable. |
| Terrain ocean + `Lighting` | never edited | Shared with the whole map |

### A.7 FUNCTIONAL — CAN RELOCATE (keep behaviour; position/size/count changes are allowed, some need a one-line script edit that must then be mirrored)

| Object | Free to move? | Note |
|---|---|---|
| Every booth model | yes — anywhere inside the region, any facing | Only the contracts above matter. Recommend Counter ≥ 12 studs from the neighbour so buy radii feel per-stand. |
| `TradeZone` | yes; may grow | Larger zone = longer nearby list on the client (polls every 0.3 s, rebuilds on change). Keep ≤ ~44×44. |
| `HubPortal` | yes | Attribute-driven; TeleportService rebinds on `ChildAdded`. |
| `TRADE_POS` | yes, with a one-line edit in `TeleportService` + mirror push + note in `BoundsGuard`'s comment | The 2026-08-09 rebuild already moved it once (`AuditBackups.TeleportService_pre_coverebuild`). |
| `EternalSkip` (+ `SkipLoop`) | yes, with `R` / `WATER_Y` edits | Or retire it (VISUAL — CAN REPLACE if not kept). |
| `CoveDressing.CoveDriver` | replace with a new single driver under the new dressing model | Keep the tag/attribute conventions and the sleep gate. |
| `CenterpieceSpinner` consumers (parts with attribute `Spin`) | yes | Reuse for the new centrepiece; no code. |
| `SaleBoards`, `IndexGate`, chests | yes / drop | Nothing reads them. |

### A.8 VISUAL — CAN REPLACE · LEGACY / POSSIBLY UNUSED · UNKNOWN — INVESTIGATE

**VISUAL — CAN REPLACE (everything below is decoration with no code dependency):** island geometry (seabed, plaza disc, glass water ring, sand rings, bridges, MARKET arch, cliffs, waterfalls, palms, tiki torches, arrival deck + causeway, CoveBarrier — rebuild a barrier ring of your own), the whole of `CoveDressing` (tusk arch, spire + sky beam, six guardian statues — reuse the *technique*: clones of `ReplicatedStorage.BrainrotModels`, scripts/humanoids/sounds stripped, scaled 36–42, breathing Highlights —, underglow chords, float stones, wake pool, hull bulbs, foam collar, islets, monument dressing, ambience anchors), the gazebo geometry around `TradeZone`, the 12 booth bodies (keep the contracts, replace the art), `SaleBoards`, `IndexGate` + `IndexGatePrompt`, `GroupChest` / `SocialBottle` / VIP chest + `ClaimSpot`s.

**LEGACY / POSSIBLY UNUSED:** `ServerScriptService.CenterpieceSpinner` (its "centerpiece gem" was lost with the old island; harmless — one Heartbeat with an empty list; reusable), `SaleBoards` placeholder text, `IndexGatePrompt`, chest `ClaimSpot`s (claim logic never wired; owner blocks Group/VIP ids), `TradingCenter_OLD` inside `ServerStorage.PreCove_Backup_2026_08_02` (keep as backup), the `ui-foundation` copies of `BoothHandler`/`BoundsGuard` (stale mirrors, superseded by `source-sync-audit`), the `pre_tradefix` AuditBackups.

**UNKNOWN — INVESTIGATE (needs the Studio read in §C.2):** (a) whether anything on the island moved/was added after 2026-08-09 (the World 2 and NPC lanes have been building since); (b) current part counts of `TradingWorld` / `CoveDressing` / `TradingCenter`; (c) `Players.MaxPlayers` (booth count sizing); (d) `workspace.StreamingMinRadius/StreamingTargetRadius` (does a 300-stud island stream whole?); (e) whether `NightLights` / `DayNightCycle` touch island parts; (f) whether `InteractionPromptClient` (round 3) already restyles `BuyPrompt` (affects the in-world price plate design); (g) exact `TradeZone` CFrame/Size and each `Display<i>` orientation; (h) whether the valley `TradePortal` carries `ComingSoonMessage` / `RefuseX-Y-Z`; (i) the six guardian statues' names (keep the same six or pick new icons); (j) whether `Lighting` has global `Atmosphere`/`ColorCorrection` that would fight a prestige palette.

## A.9 Current navigation issues

1. **Booths are the furthest thing from arrival** (~285 studs; the arc r103, 35°–145° is on the far side of the plaza from the south deck). A market should be the first thing you reach.
2. **No respawn on the island** — death, reset or a `BoundsGuard` strike returns the player to the valley SpawnLocation (8,000 studs away, another curtain hop to come back). Known, being fixed separately (World 2 lane note); the rework must not add drops/pits that make it worse.
3. **The gazebo is the only trade spot** — a 26³ box at the exact centre; two players who meet at a booth must walk to the middle to trade.
4. **Water ring + four bridges** force detours: from the arrival bridge to the booth arc you either cross the plaza and a second bridge or walk the outer ring.
5. **Single return portal** on the far (south) deck; from the booth arc that is ~300 studs back.
6. **Orbiting islets and the sky beam are eye-candy with no wayfinding role** — nothing on the island says "booths this way", "trade here", "home".
7. **`TeleportTo("Trade")` bypasses the ComingSoon gate** (D9) — not a navigation issue for players, but it means the held-back island is reachable by a spoofed remote.
8. Mobile: `TradeClient` and `BoothClient` scale a 1350×775 canvas through `Platform.Bind`; the in-world `BillboardGui` tags (130×40 px, `AlwaysOnTop`) do not scale for phones and overlap when three displays sit 2–3 studs apart.

## A.10 Current visual issues

1. **Identity is "beach cove", not "exchange".** Palms, tiki torches, surfboards, sand — a fine holiday island, but it reads as another progression world (World 2 is snow, World 3 is gardens, this is beach). Nothing says money, prestige or busy market.
2. **Listings are 1.8-stud Neon cubes** with a 130×40 billboard. Rarity is a cube colour; mutation is a text prefix; size is invisible; the brainrot itself is never shown in the world. From ten studs away three listings are three glowing dice.
3. **The price is the smallest thing on the stand** — `TextScaled` inside 40 px shared with the name; on the prompt it is `"Buy for $1.5M"` in the default ProximityPrompt style (or round-3's restyle).
4. **Booth signage is a single TextLabel** ("X'S STAND"); no rarity banner, no "OPEN"/"FULL" state, no seller avatar.
5. **The colossal tusk arch and the 148-stud spire dominate a 62-stud plaza** — scale drama at the edge, nothing at the centre except a gazebo; the landmark hierarchy is inverted (the biggest thing is the least useful).
6. **Chest podiums, colour beams, IndexGate halo, boards pavilion** are all *promises* (claims, index, boards) that do nothing — visual debt.
7. **No night identity** — `Lighting` is global and the valley has a day/night cycle; the island's local lights are a handful of PointLights on podiums and tiki torches.

## A.11 Current performance concerns

- **Two independent Heartbeat loops** on the island (`CoveDriver` — gated, and `SkipLoop` — ungated, runs 24/7 at 60 Hz even with nobody there) plus `CenterpieceSpinner` (ungated, empty list). Not heavy, but the rework should end with exactly one gated driver.
- **`BoothHandler.refreshDisplays` destroys and re-creates every display on every change** (3 s prune tick can rebuild). Fine at 12 booths; at 30 booths with a busy server it is still cheap (≤ 90 parts), but any client-side dressing must be robust to instances being replaced constantly (bind on `DescendantAdded`, not once).
- **`BillboardGui AlwaysOnTop` ×36 (12×3)** with no `MaxDistance` — every tag on the island is drawn from anywhere. At 30 booths that is 90 always-on-top labels; set a `MaxDistance` (≤ 120) on whatever replaces them.
- **`TradeClient` polls `Players:GetPlayers()` every 0.3 s while you stand in the zone** (client-side, per player, cheap).
- **Six breathing `Highlight`s (guardians)** + `NpcFocusClient`'s one. The engine caps simultaneously rendered Highlights (31; the project's own comment budgets 16). Any flex/showcase idea must stay under ~10 in this world.
- **Seven orbiting islets + 32 underglow chords + 8 float stones + wake pool** are per-frame CFrame writes replicated from the server — the sleep gate makes them free when the island is empty, but with players present that is ~50 replicated moving parts. Prefer client-side motion for pure decoration next time (server motion only where every player must see the same pose).
- **Streaming**: both containers are Persistent (correct for contracts) — but Persistent means the ~816 parts are always replicated to every client, including players who never visit. A bigger island should keep only the contract models Persistent and let dressing stream normally.
- Part budget the last build used: dressing cap 1,800, actual ~816 total.

## A.12 Current NPC roles

**None.** No script anchors an NPC in the Trading World (`NpcIdle` profiles: `GameWorld.ElderTung`, `GameWorld.FrozenTundra.Michel`, `GameWorld.SecretChim`; `NpcRigLife`/`NpcBodyLife`/`NpcPropLife` cover the fifteen shopkeepers in the valley/tundra/gardens), the 2026-08-02 spec places none, and the 2026-08-09 build added none. The island is unstaffed. NPC-01's systems (anchored R15 rigs, root-driven idles, prop idles, proximity gating at 90 studs) are the ones any Trading World NPC will use — the role requirements in §B.1.5 are written against them.

## A.13 Current booth-browsing weaknesses (measured against the brief's list)

| Brief requirement | Today | Gap |
|---|---|---|
| Seller identity | `SignBoard` text `"X'S STAND"`; `BuyPrompt.SellerName` in the confirm modal | No face/avatar, small sign, no "who is online" cue |
| Brainrot being sold | Neon cube coloured by tier | **The brainrot model is never shown in the world** (the confirm modal shows a `BrainrotThumb`) |
| Brainrot name | billboard line 1 (shared 40 px with the price) | Truncates long names; unreadable beyond ~15 studs |
| Rarity | cube colour only | No word, no tier badge |
| Golden / Diamond modifier | text prefix in the label (`"Golden X #12"`) | No colour/finish cue; label re-resolves every 3 s and can change under a buyer's cursor |
| Huge / Massive modifier | **not represented and not preserved by the sale** (Finding 3) | Blocked on D2 |
| Exact asking price | `"$1.5M"` on the billboard + `"Buy for $1.5M"` on the prompt | Small; abbreviated (`formatMoney` → `1.5M`) — "exact" only in the confirm modal's `formatNumber`; currency is Cash (D1) |
| Purchase interaction | hold E within 10 studs → modal → CONFIRM | OK; two-step by design |
| Browse dozens of listings quickly | 12 booths × 3 = 36 max, on a 106-stud arc r103 | Walk the arc, squint at cubes; no overview, no "what's for sale" board, no way to know a stand is empty before walking to it |
| Clear booth ownership | sign text | No empty/occupied colour state visible from afar |
| Show off | none | No flex surface at all |

## A.14 Rollback plan (snapshot strategy before ANY future deletion)

House pattern: World 2 uses `ServerStorage.World2Backups_<date>.Rollback` + `ServerStorage.World2Blockout.Generator` + `AuditBackups.PreWorld2Blockout_<date>` script copies. TW-01 follows it exactly.

**Step 0 — owner action, before Phase 2 opens Studio:** `File → Save to File As…` a `.rbxl` off Roblox (the README is explicit that this is the only complete restore point — models/terrain are not in git), and confirm `ServerStorage.PreCove_Backup_2026_08_02` still exists.

**Step 1 — snapshot in place (Edit mode, one command-bar chunk, nothing destroyed):** clone `GameWorld.TradingWorld`, `GameWorld.TradingCenter` and `GameWorld.Portals.HubPortal` into `ServerStorage.TradingWorldBackups_<date>` as `TradingWorld_Original`, `TradingCenter_Original`, `HubPortal_Original`; copy the `Source` of every script the round may touch (`TeleportService`, `BoundsGuard`, `WorldTravelConfig`, `SkipLoop`, `CoveDriver`, `CenterpieceSpinner`, and `BoothHandler` only if D4 chooses the server-side option) into `ServerStorage.AuditBackups.PreGrandExchange_<date>` (names percent-encoded per the mirror rule); record `TRADE_POS`, the `Trading` region box, `TradeZone` CFrame/Size and every `Booth<i>` CFrame + `BoothIndex` into `docs/trading-world/snapshot-<date>.md`; regenerate/diff `_MANIFEST.txt`.

**Step 2 — build beside, not over:** the new world is generated into a NEW container (`GameWorld.TradingWorld_GE` and `GameWorld.TradingCenter_GE`) by an idempotent generator (`ServerStorage.TradingWorldBuild.Generator`, versioned, `ClearAll()`), so the live containers stay bindable until cutover. Because `BoothHandler`/`TradeHandler` bind by the exact names `TradingCenter` / `Booths` / `TradeZone` at server start, the **cutover is a rename in Edit mode**: old `TradingCenter` → moved to the backup folder, `TradingCenter_GE` → `TradingCenter` (same for `TradingWorld`), then one playtest to confirm `[BoothHandler]` adopts N booths with no warn and `TradeClient` finds the zone.

**Step 3 — `ServerStorage.TradingWorldBackups_<date>.Rollback` (`.Restore()` in one step, mirroring the World 2 script):** destroys the `_GE` containers, restores the three `_Original` models under `GameWorld` with their original names, restores the saved script sources (with the same *"check first: if anyone has edited X since…"* guard), re-applies `ModelStreamingMode = Persistent`, and prints what it did. **Drill it once on the greybox before any art is added** (the 2026-08-09 round skipped its revert drill — V10 NOT RUN — do not repeat that).

**Step 4 — nothing ships until the owner deletes `ComingSoon = true`.** Because the world is held back, every Phase 2 playtest is team-only; the live audience never sees an intermediate state. Rollback after launch = the same `Restore()` + putting the `ComingSoon` line back.

**Never:** delete `PreCove_Backup_2026_08_02`; edit `Terrain` or `Lighting`; touch `PlayerBases`; save the place from an AI session (owner saves).

---

# PART B — THREE CONCEPTS FOR THE NEW TRADING WORLD

Shared ground rules for all three (derived from Part A):

- Same footprint centre `C = (8000, 2002.4, 8000)`; everything walkable inside `X 7340–8750 · Z 7415–8685 · Y ≤ 2100`. `TRADE_POS` and `HubPortal` kept unless a concept says otherwise.
- All booth contracts (§A.6) byte-identical; only the art around them changes. Booth count is parametric (`BoothIndex 1…N`); 24 + 6 is the working number pending `Players.MaxPlayers` (§C.2).
- No new economy, no recommended prices, no access gating that does not already exist. "Value" surfaces read `GetItemStats` (PriceIndex medians) or `LeaderboardHandler` data only.
- One gated server driver for decoration motion (CoveDriver conventions), local lights only, `Lighting`/`Terrain` untouched, emitters ≤ 20, Highlights ≤ 8, no `RenderStepped` decoration.
- Price surfaces are currency-agnostic: **one big number, one currency glyph** (`$` today — D1).

## B.1 Concept 1 — BRAINROT GRAND EXCHANGE  ★ recommended

### B.1.1 Theme
A grand exchange hall dropped into a brainrot world: an open stone rotunda with eight gold-banded pylons and a suspended Grand Gem, wrapped by two covered trading arcades, with a dark rarity-lit Vault behind it and colossal brainrot statues standing in the sea around the whole thing. Polished pale stone (SmoothPlastic, warm cream `238,226,200` / dark slate `52,50,58`), brass/gold trims (`255,196,64`), gem accents in the eight rarity colours from `RarityConfig`, banners, ticker boards, a controlled amount of Neon (gem cores, ticker text, arcade underlights). LemonPop's warm cream/gold reads the same in-world as it does in the HUD, so the world and the UI feel like one product. Nothing beachy survives except the water itself and the Eternal Skip.

### B.1.2 Spawn experience
`TRADE_POS` unchanged. The Landing is a polished 44×56 deck at y2004.6 with a gold inlay arrow pointing north and the return portal on its east side (existing `HubPortal`, kept where it is). Ahead: the Grand Causeway — 24 wide, 100 long, lined with seven pairs of banner masts (14 tall, gem-tipped, rarity-colour banners) converging on the **Great Arch** (span 36, apex +54 over the plaza, gem keystone). Through the arch: the Grand Gem and its sky beam, centred. Left and right of the deck: two colossi rising out of the moat. The curtain drops at ~3.6 s after the hop straight onto this frame.

### B.1.3 Central landmark — the Exchange Hall
- **Sunken Exchange Floor**: a 44-stud disc sunk 1.6 studs (top y2000.8, still above the 1999.5 waterline), gold compass-rose inlay, two ring steps up to the promenade. `TradeZone` = one box 46×46×22 centred (8000, y2006, 8000) — covers the whole floor and both steps. Everyone on the promenade, balcony and crown looks *down* onto the trades: the floor is a stage.
- **Eight pylons** (8×8×30) at r44 on the 22.5°+k·45° diagonals, so the four axial openings (N/S/E/W) are clear 45° arches. Gold bands, a gem lantern on each inner face at +26.
- **Balcony ring** at +12 (r36–44, 8 wide, gem balustrade), reached by two curved ramps (1:4, 48 long) hugging the drum on the E and W sides; four diagonal bridges from the balcony to the arcade roofs.
- **Observation Crown** at +30 on the ring beam (r40–46), two more curved ramps from the balcony. 360° view: arcades, Vault, colossi, the Eternal Skip circling the moat. Highest walkable point y2032.
- **The Grand Gem**: a 14-stud faceted gem (Neon teal core, gold cage) hanging at +36 over the floor, attribute `Spin` → `CenterpieceSpinner` already spins and bobs it (zero code). One PointLight (Range 60), one low-rate sparkle emitter, one Neon sky beam to +500 breathing on the driver (the spire's trick).
- **Ticker ring**: eight 7×2.5 SurfaceGui panels on the pylons' inner faces at balcony eye level (+14). Phase 2: static `GRAND EXCHANGE · 30 STANDS · FLOOR OPEN`. Phase 3 option (client-only, existing remote): a scrolling strip of PriceIndex medians (`GetItemStats`, 20 items per 30 s stays inside the token bucket; items with `Samples < MinSamples` show `"— (n of 5 sales)"` exactly as the Index does).

### B.1.4 Booth layout — the Trading Arcades (the economic heart)
- Two covered crescents, **West Arcade** (+X) and **East Arcade** (−X), each 12 booths on r68 spanning ±60° about its axis (booth k at angle −60° + 10.909°·k, pitch 12.95 studs → 11-wide module + 2 gap), every booth facing C. `BoothIndex` 1–12 west (south → north), 13–24 east.
- **The Promenade** (r48–66, 18 wide) is the browse lane; a gold inlay stripe at r58 marks it. From the stripe every display is 6–10 studs away — inside `BuyPrompt` reach (10) and `BUY_RADIUS` (26). One full loop of the promenade ≈ 390 studs ≈ **19 s at WalkSpeed 21, and passes all 24 stands once**. No stairs, no bridges, no water on the loop.
- **Booth module** (one Model, cloned 24× by the generator; contracts exactly as §A.6): `Counter` 11×2×3.4 on r68 with `StandPrompt`; three plinths `Display1/2/3` at local x −3.4 / 0 / +3.4, top at +1.0, so the server's cube/tag lands at +2.7 eye height; a 9×3 **marquee** `SignBoard` at +6.5 (the server writes `"X'S STAND"` / `"AVAILABLE STAND"` into it for free — make it the biggest text on the stand); a back wall r72–78, an arcade roof at +9 shared along the crescent (colonnade), a banner mast per stand; one warm SurfaceLight under the roof per two stands.
- **Reading a listing from the lane (D4 — the client dressing layer):** every fact the brief asks for is already on replicated instances the client can read — `BuyPrompt` attributes `ItemName` (carries the mutation prefix + serial), `Price`, `SellerName`, `BoothIndex`; `ListingDisplay.Color` (tier); `StandPrompt.ActionText` (`Claim Stand` = vacant). A `BoothDressingClient` LocalScript (`DescendantAdded` on `TradingCenter.Booths`, streaming-safe like `StallPrompt`) can, **with no server change**: hide the server's 130×40 billboard locally and draw a price plate — brainrot name on line one, rarity word + tier colour band, mutation chip (GOLDEN / DIAMOND …), and the price as the largest element with the currency glyph, `MaxDistance 120`; swap the Neon cube for a locally cloned, script-stripped `BrainrotModels` model on the plinth (MutationFX applied client-side, static or on the existing `BrainrotBody` idle driver with its distance LOD); light the stand's mast green (vacant) / gold (open) / white (full). Huge/Massive cannot be shown until D2 lands — the plate reserves a slot for it.
- **The Vault stands** (`BoothIndex` 25–30): six more booths, identical contracts, inside the Vault (§B.1.6) on tall plinths with alcove lighting. Same claim rules — first come, first served — nothing gates them (no such system exists); prestige is purely where they stand.

### B.1.5 Social spaces
- The **Exchange Floor steps** (two ring steps, r22–28) = amphitheatre seating around the trades.
- The **balcony** and **crown** = overlooks, screenshot spots, the "I'm just hanging out" place.
- **Skipper's Pier** (+X axis): a 10-wide jetty out over the moat to r124 with benches, watching the Eternal Skip go round (`SkipLoop` keeps its 26°/s; `R` becomes 106, `WATER_Y` the moat's top — a two-number edit, mirrored).
- **Colossus Walk** (−X axis): the mirror jetty under a colossus.
- **The Records Terrace** (flanking the arch on the south, r72–90): TOP EARNERS / MOST TIME PLAYED / MOST BRAINROTS CAUGHT on the −X side (D5 for the data feed), the MARKET PRICES ticker wall + a static HOW TO TRADE board on the +X side. First thing after the arch: "what's this place, what's it worth".
- A hidden ledge under the causeway bridge at water level (reached by dropping off the pier side; 1.6 studs up to climb back) with the old **Group / Social chests as pure props** if the owner still wants them advertised.

### B.1.6 Flex / rare area — the Vault
North gap of the promenade → a 16-wide ramp (1:4, 24 long) up to a +6 plateau → the **Vault portal** (dark slate arch at z8092, gem-lined, Secret-pink and God-gold rims). Inside (70×60, open sides so the camera never clips): a 20-wide nave with the six Vault stands in two facing rows; at the far end the **Reliquary** — five alcoves for SECRET, GOD, GOLDEN, DIAMOND and MASSIVE, each holding a colossal statue built with the guardian technique (a `BrainrotModels` clone, script-stripped, `ScaleTo`, `MutationFX` for the Golden/Diamond ones — all existing modules), one SpotLight + one low-rate emitter each, the God statue on a 20-stud crown plinth with one breathing Highlight. At the entrance: four **flex pedestals** — spotlit 6-stud discs with a dark polished backdrop, floor inlay FLEX. A player stands there holding a brainrot (the existing hold Tool) and the light does the rest. Zero code, zero gating, and it is where the Curator NPC lives.

### B.1.7 Verticality
Three levels, all ramps (1:4, 8+ wide), the only step on the whole island is the 1.6-stud exchange-floor step (ramped at N and S as well): **P** promenade + floor, **+12** balcony ring / arcade roofs (social), **+30** crown. The Vault plateau at +6. Nothing walkable above y2032; the region allows 2100.

### B.1.8 Lighting
`Lighting` untouched (the valley's day/night cycle runs here too, so the world is designed to read at night): the Grand Gem (1 PointLight), pylon gem lanterns (8), arcade roof SurfaceLights (12), arch keystone (2), Vault (5 alcoves + 4 pedestals + 2 portal = 11), Records terrace (2), piers (2) → **≈ 38 local lights, cap 48**, all Range ≤ 60 so at most ~12 are ever in range at once. Neon carries the rest: gem cores, ticker text, banner tips, the promenade stripe, moat underglow chords (kept from the cove, re-coloured gold/teal).

### B.1.9 VFX
Gem sparkle (1), Vault alcoves (5), arch keystone (2) = **8 emitters**; the sky beam and gem-lantern breathing on the driver (`CoveBreatheT`); banners on `CoveBob`-style sway; the Eternal Skip's splash rings + pooled wake (existing); Highlights: 6 colossi + 1 God statue = 7 (+ NpcFocus). No beams except the one sky beam; no weather.

### B.1.10 Navigation
- One axis: Landing → Causeway → Arch → Floor → Vault, all on x = 8000. The two arcades hang off the axis left and right.
- **District totems** at the four promenade junctions (S: EXCHANGE ↑ / ARCADES ← →, N: THE VAULT ↑, E/W: RECORDS / PIER) — 8-stud stone posts with a gem icon and a SurfaceGui word; floor inlay colour per district (gold = exchange, teal = arcades, pink/purple = vault, green = social).
- **Two ways home**: the existing `HubPortal` at the Landing and a second `Portals.HubPortalVault` (`Dest = "Hub"`, no code — TeleportService binds any `PortalTouch`) behind the Reliquary, so nobody walks 400 studs back.
- Mobile: all lanes ≥ 16 wide, no interiors narrower than 20, the Vault has open sides, the balcony has an outer balustrade only (camera can back out over the promenade).
- Depends on the separate world-respawn fix for "die on the island → come back to the island"; no pits, no drops > 2 studs anywhere.

### B.1.11 Performance cost (estimate — the generator will measure)
| Budget | Estimate | Cap |
|---|---|---|
| BaseParts (incl. MeshParts) | ~3,400 (Landing/causeway/masts 220 · arch 60 · hall 700 · 24 arcade modules ≈ 840 as Parts or ~300 as MeshPart modules · Vault 450 · records/ticker 120 · rim/moat/piers/outer 350 · colossi 6 × ~11 pack-style · dressing 600) | 4,500 |
| Local lights | ~38 | 48 |
| ParticleEmitters | 8 | 20 |
| Highlights | 7 (+1 NpcFocus) | 10 |
| Server scripts | `ExchangeDriver` (one gated Heartbeat) · `SkipLoop` (kept; add the same sleep gate) · `CenterpieceSpinner` (existing) | 3 |
| Client scripts | `BoothDressingClient` (D4) | 1 |
| SurfaceGuis | 24 marquees + 8 tickers + 3 boards + 2 info + 4 totems ≈ 41, static | — |
| BillboardGuis | server's 3 per stand (hidden locally by D4, or left as-is) | — |
| Replicated moving parts | gem (1), Eternal Skip (1 + 3 rings), sky beam alpha, ~14 banner sways — no orbiting islets | ≤ 25 |
| Streaming | `TradingCenter` Persistent (contracts); `TradingWorld` districts as Atomic models, not Persistent (§A.8 (d) to confirm) | — |

### B.1.12 Top-down district layout
See `docs/trading-world/grand-exchange-layout.svg` (N up). Coordinates are absolute (x, z), heights relative to P = 2002.4.

```
                            N (+Z)
                    ┌──────────────────┐   z 8092–8180   THE VAULT (+6): portal arch z8092,
                    │   RELIQUARY      │                  6 Vault stands (BoothIndex 25–30),
                    │  6 VAULT STANDS  │                  Reliquary alcoves z8150–8175,
                    │  4 FLEX PEDESTALS│                  HubPortalVault behind
                    └────────╥─────────┘
                        ramp ║ (r66→90, +6)
   WEST ARCADE (+X)    N junction totem          EAST ARCADE (−X)
   12 stands, r68      ┌─────────────┐          12 stands, r68
   BoothIndex 1–12  ╭──┤  BALCONY +12├──╮       BoothIndex 13–24
   (−60°…+60°     ╭─┤  │ ┌─────────┐ │  ├─╮     (−60°…+60° about −X)
    about +X)     │ │  │ │ EXCHANGE│ │  │ │
   PIER +X ═══════╡ │  │ │  FLOOR  │ │  │ ╞═══════ COLOSSUS WALK −X
   (r84→124)      │ │  │ │  −1.6   │ │  │ │        (r84→124)
                  ╰─┤  │ │TradeZone│ │  ├─╯
     promenade      ╰──┤ └─────────┘ ├──╯   promenade r48–66, lane stripe r58
     r48–66            │ 8 pylons r44│
                       └──────╥──────┘
              TICKER WALL     ║     RECORDS (3 boards)      r72–90, flanking the arch
               (+X side)  ══╬═════ GREAT ARCH z7930 (span 36, apex +54)
                              ║
                     CAUSEWAY ║ 24 wide, 14 banner masts, z7846–7930
                     over the MOAT (r96–116, water −2; Eternal Skip orbits r106)
                    ┌─────────╨─────────┐
                    │      LANDING      │  44×56 deck, y2004.6, TRADE_POS (8000, 2004.6, 7818)
                    │ [HubPortal] ●     │  HubPortal (7981, 2006, 7830)
                    └───────────────────┘
                            S (−Z)
   Colossi ×6 on plinths r130 at 0°/60°/120°/180°/240°/300° (none on the south sightline)
   Barrier ring r140 (+ U-wall around the Landing); outer stone ring r116–124
```

Key coordinates: Great Arch feet (7982 / 8018, P, 7930) · S junction totem (8000, P, 7940) · West Arcade booth k centre = `(8000 + 68·cos θk, P, 8000 + 68·sin θk)`, θk = −60° + 10.909°·k · East Arcade = mirror in x · N junction (8000, P, 8066) · Vault portal (8000, +6, 8092) · Vault stands (7976 | 8024, +6, 8104 / 8120 / 8136) · Reliquary crown plinth (8000, +6, 8165) · pier root (8084, P, 8000) · colossus k `(8000 + 130·cos(60k°), P, 8000 + 130·sin(60k°))`.

### B.1.13 Player route from spawn
0 s Landing (curtain lifts, frame = arch + gem + colossi) → 1–5 s causeway, banners flicking past, ticker light visible ahead → 5.5 s under the Great Arch (keystone gem overhead, sound swell) → 6–8 s Records terrace on the right, Ticker wall on the left, Exchange Host NPC greets on the axis → 8 s S junction totem: **ARCADES ← →  /  EXCHANGE ↑** → 9 s the sunken floor with live trades in it, balcony crowd above → 10 s+ pick an arcade.

### B.1.14 Booth browsing route
S junction → West Arcade clockwise (stands 1→12, 130 studs, ~6 s, every display within 6–10 studs of the lane stripe) → N junction (Vault glimpse; 24-stud ramp spur to the six Vault stands and back, optional) → East Arcade (13→24, ~6 s) → S junction. **Every stand seen exactly once in ~19–25 s; nothing hidden, no level change, no water.** The balcony above gives the "which stands are open" overview (mast colours) before committing to the loop.

### B.1.15 Landmark hierarchy
1. **The Grand Gem + sky beam** — visible from every point on the island and from the Landing; the "where is the centre" answer.
2. **The Great Arch** — the arrival frame and the S junction marker.
3. **The Exchange Hall drum** (pylons, gold crown ring) — the social hub silhouette.
4. **The Vault portal** — the rarity-lit doorway on the north axis.
5. **The six colossi** — the island's edge and its brainrot identity.
6. **District totems + floor inlays** — the local wayfinding layer.

### B.1.16 Trading World NPC role requirements (handoff to NPC-01)
TW-01 owns roles, purpose, count and placement; NPC-01 owns the characters. Interactions listed are **existing** behaviours only (the round-3 dialogue shell; walk-up prompts styled by `InteractionPrompt` — new prompt names need a `VERB_BY_NAME` entry from the UI lane). No quests, no new remotes. Placement coordinates are the standing spot; heights relative to P unless the Vault (+6) or balcony (+12).

| # | Role (working name) | Tier | Where (x, y, z) · facing | Personality | Required interaction | Visual needs | Prop ideas |
|---|---|---|---|---|---|---|---|
| 1 | **Exchange Host** ("Ledger") | T1 — must ship | (8000, P, 7948), just inside the Great Arch, facing S toward arrivals | Warm, brisk, floor-manager energy; talks like an auctioneer who has seen everything | `TalkPrompt` → dialogue: how a stand works (claim / list / price / buy), where the Vault is, where the prices board is. Dialogue only. | Formal exchange uniform in cream + gold; a sash in the eight rarity colours; readable from 40 studs | Clipboard/ledger, gold gavel, a bell on a stand beside him |
| 2 | **Gem Broker** | T1 — must ship (monetisation tie-in) | (8032, P, 7952) at the Ticker Wall, facing the axis | Smooth, fast-talking, counts on fingers | `TalkPrompt` → dialogue with an "OPEN SHOP" action that opens the existing Gems shop (`HudPanelRequest` seam) — **UI lane to confirm the dialogue shell supports an action button**; otherwise dialogue only | Sharp suit, gem monocle, teal/gold palette matching the Gems pill | Gem scale, velvet tray of gems, abacus |
| 3 | **Rare Brainrot Curator** | T2 | (8000, +6, 8148), Reliquary end of the Vault, facing S | Hushed, reverent, slightly unhinged collector | `TalkPrompt` → dialogue: what Secret/God/Golden/Diamond/Huge/Massive mean, points at the alcoves | Dark robe with pink/gold trim, white gloves, museum-guard cap | Magnifying glass, velvet rope stanchions, a display case |
| 4 | **Booth Attendant (West)** | T2 | (8036, P, 8062), north end of the West Arcade, facing the lane | Cheerful, helpful, "stands are free!" | `TalkPrompt` → dialogue: claiming a stand, the 3-listing cap, that leaving releases it | Arcade apron in teal, name tag | Broom, stack of empty price plates, a "VACANT" sign under one arm |
| 5 | **Booth Attendant (East)** | T2 | (7964, P, 8062), mirror | Grumpier twin of #4 | same | same, mirrored colours | Mop bucket, ledger |
| 6 | **Collector** | T3 | (7972, +12, 7972), SE balcony, leaning on the balustrade looking at the floor | Cryptic, always "looking for one more" | `TalkPrompt` → flavour dialogue about the market (no quest) | Long coat, travel bag covered in brainrot patches | Binoculars, a want-list poster |
| 7 | **Ambient Trader pair** | T3 | Exchange Floor steps (7988, −0.8, 8012) & (8012, −0.8, 8012), facing each other | Mid-haggle, animated | none (idle only) | Two contrasting merchant outfits | Contract scroll, gem pouch |
| 8 | **Ambient Pier Angler** | T3 (optional) | Skipper's Pier end (8120, P, 8000), facing the moat | Sleepy | none | Fisher hat, the game's own rod | Rod, bucket, a "skip stone" |
| 9 | **Vault Guards ×2** | T3 (optional) | (7986, +6, 8092) & (8014, +6, 8092) flanking the portal, facing S | Statue-still | none | Armoured, gem visors, symmetrical | Halberds with gem heads |

Recommended v1 count: **7** (roles 1–7); 8–9 optional. All static-anchored per NPC-01's rig standard; proximity-gated idles (`NpcIdle`, 90 studs). Nothing here may block a lane: every NPC stands off the promenade stripe and off the causeway axis.

### B.1.17 The first five seconds
The curtain lifts (~3.6 s after the hop) on a still frame: cream stone deck underfoot with a gold arrow; a corridor of banner masts pulling the eye to a 54-stud arch with a glowing keystone; through the arch, dead centre, the Grand Gem glinting with its beam climbing into the sky; behind it the gold crown ring of the hall and the tops of the pylons; on both edges, colossal brainrots knee-deep in the sea; warm arcade light spilling from left and right; ticker text scrolling on a wall by the arch; other players' names moving on the promenade. Ambience: market murmur and a distant bell (SoundKit ids only). The player's first input is a straight line forward.

### B.1.18 What makes it memorable
The **gem-through-the-arch** arrival; a **19-second loop past 24 lit stands** with prices you can read from the lane; a **sunken trade floor with an audience** on the steps and balcony; the **rarity-lit Vault** and its flex pedestals; the **crown panorama** with the Eternal Skip circling below; **your own name on a marquee** above your stand.

## B.2 Concept 2 — SKIPSTONE HARBOUR SOUK

- **Theme:** a lantern-lit harbour town at permanent dusk (local light does the dusk; `Lighting` untouched). Stone quays, timber piers, canvas awnings, hanging lanterns, gem-lit water. Cosy, atmospheric, a bit mysterious — the "night market" fantasy.
- **Spawn experience:** the Landing is a harbour steps landing; ahead a lighthouse on a rock with a rotating gem beam sweeping the water; the town rises to the left and right along two canals.
- **Central landmark:** the **Great Lighthouse** — 90 studs, spiral ramp outside it to a lantern room holding the gem beacon; a bell that the driver swings; at its foot the trade quay (`TradeZone`) on the water.
- **Booth layout:** stands on **moored barges** along a ring canal (r70), 24 barges, walked from a quay ring on the inside; Vault stands on a covered "Customs House" quay to the north.
- **Social spaces:** the tavern deck (seating over the water), canal bridges, lighthouse balcony, fishing pier.
- **Flex / rare area:** the **Captain's Deck** — a beached colossal galleon whose figurehead is a brainrot statue; rare stands in its hold, flex spots on its prow with a spotlight.
- **Verticality:** two levels — quay and upper boardwalk (+10) — plus the lighthouse spiral (+60, one long 1:6 ramp).
- **Lighting:** lantern-heavy — the risk. Lanterns must be Neon parts, with real lights only on the 16 canal posts and the lighthouse (≈ 24 lights).
- **VFX:** rotating beam (driver), bobbing water lanterns (driver, ~20 replicated bobs), fireflies (2 emitters), lighthouse beacon flare (1).
- **Navigation:** a ring canal browses fine (~same loop length as B.1) but every barge needs a gangway, which adds ~1-stud steps and narrow (8-wide) planks — worse on mobile; the lighthouse spiral is slow.
- **Performance cost:** ~3,000 parts, ~24 lights, ~5 emitters, one driver + `SkipLoop`; more replicated motion than B.1 (bobbing lanterns/barges). Medium.
- **Verdict:** best *hangout*, weakest *exchange*. It reads as another themed world (harbour) rather than a prestige destination, and the booths on barges fight the "scan many listings fast" goal.

## B.3 Concept 3 — THE SKYVAULT SPIRE

- **Theme:** a single vertical exchange tower — a 90-stud-wide open cylinder rising 80 studs, three stacked stand galleries around an atrium with the Grand Gem hanging down the centre, a crown observation deck on top. Polished dark stone, brass, floating light platforms. Maximum "wow per stud".
- **Spawn experience:** arrive at the tower's base plaza looking straight up the atrium at the gem; stands glowing in rings above.
- **Central landmark:** the tower itself; the trade floor is the atrium base (`TradeZone`).
- **Booth layout:** three galleries (P, +16, +32) of 8 stands each (24) plus a crown gallery of 6 (the Vault), all facing the atrium — you can *see* every stand from the floor, which is the concept's strongest browsing idea.
- **Social spaces:** the base plaza, gallery balconies, the crown deck.
- **Flex / rare area:** the crown — the six top stands + statue alcoves + flex pedestals on floating platforms.
- **Verticality:** the whole point — and the problem. A continuous 1:6 spiral ramp to +48 is ~900 studs of walking (≈ 43 s); anything faster needs elevators/teleport pads = new code.
- **Lighting:** the gem + one light ring per gallery (≈ 30 lights); tier-coloured gallery rims in Neon.
- **VFX:** gem, floating platforms on the driver, ascending sparkle column (2 emitters).
- **Navigation:** the third-person camera in a 12-wide gallery lane clips into the outer wall; the spiral is exhausting on mobile; "which gallery was that stand on?" is a real question. Fails the brief's "avoid excessive stairs / confusing maze" test unless we add teleport pads (code).
- **Performance cost:** ~3,800 parts (curved interior geometry is part-hungry), ~30 lights, 3 emitters, one driver; interior overdraw is the highest of the three. High.
- **Verdict:** the most photogenic and the worst to browse and to walk; only viable with new movement code, which is out of scope.

## B.4 Recommendation
**Build Concept 1.** It is the only one of the three whose booth district is a flat 19-second loop with every listing in reach of the lane, whose landmark is at the centre where the trades happen, and whose "prestige" comes from architecture and light rather than from another world theme. Concepts 2 and 3 each contribute one idea worth stealing later: the Souk's water lanterns for the moat, and the Spire's "see every stand from the floor" — which B.1's balcony already approximates.

---

# PART C — DECISIONS, STUDIO NEEDS, PHASE 2 PROPOSAL

## C.1 Decisions needed before Phase 2 (owner / other lanes)

| # | Decision | Owner | TW-01 default if no answer |
|---|---|---|---|
| **D1** | **Currency.** Booths and P2P trades are Cash (`$`) today; the brief says Gems. Keep Cash, or is a Gems switch planned (economy change in `BoothHandler` / `TradeHandler` / both clients / `PriceIndex` semantics)? | Owner + economy | Design stays currency-agnostic; every price surface is `<glyph> <number>` and the glyph is a single token to swap. |
| **D2** | **Size is dropped by name-based transfers** (`BrainrotMover.Take` omits `Size`; `TakeByUid` keeps it). Fix in the economy lane (Uid-based listings/offers, or carry `Size` in `Take` and prefer the smallest copy)? Until then no in-world Huge/Massive label can be honest. | Economy | Price plate reserves a size chip; left blank. |
| **D3** | **Stand count.** 24 arcade + 6 Vault proposed. Needs `Players.MaxPlayers`. `MAX_LISTINGS` stays 3. | Owner | 30 stands; the generator takes N as a parameter. |
| **D4** | **Listing presentation layer.** (a) client-only `BoothDressingClient` reading replicated instances (no server change — recommended), or (b) a presentation-only edit to `BoothHandler.refreshDisplays` (bigger billboard, `MaxDistance`, tier word) — touches a frozen economy file. | Owner + economy | (a). |
| **D5** | **Value boards.** `LeaderboardBoards.Build` hard-codes the lodge; painting three more boards on the island needs either a parameterised `Build` (small change in Balkan's module) or hand-authored boards with no live data. | Balkan / owner | Static boards in Phase 2; live feed as a Phase 3 item. |
| **D6** | **Recent-sales feed / sale bell.** `PriceIndex` exposes medians only; "RECENT SALES" or a world-wide sale chime needs one new server→client event. Want it? | Economy | Not built. |
| **D7** | **World-aware respawn** (die on the island → respawn on the island) — World 2 lane says it is "being fixed separately". TW-01 designs no drops and depends on that fix for launch quality. | Whoever owns it | Assumed to land before the island reopens. |
| **D8** | **Keep `TRADE_POS` / `HubPortal` where they are?** B.1 keeps both. Moving either is a one-line `TeleportService` edit + mirror push. | Owner | Keep. |
| **D9** | **`TeleportTo("Trade")` bypasses `ComingSoon`.** The nav branch teleports straight to `TRADE_POS` with no `IsDestComingSoon` check, so a spoofed remote reaches the held-back island today. One-line fix in `TeleportService` (not TW-01's file). | Owner | Reported only. |
| **D10** | **Budgets sign-off:** 4,500 parts / 48 lights / 20 emitters / 10 Highlights / one driver. | Owner | As stated. |
| **D11** | **Branch base.** `trading-world-rework` is based on `source-sync-audit` (freshest mirror, Balkan's approved sync) rather than `ui-foundation`. OK? | Owner / Balkan | Keep; docs-only so far. |
| **D12** | **Eternal Skip:** keep (moved to the moat, two numbers edited) or retire? | Owner | Keep. |
| **D13** | **Old chests / IndexGate:** carry the Group/Social chests over as props on the hidden ledge, or drop them until the ids exist? | Owner | Drop; add back as props on request. |

## C.2 If live Studio inspection is approved — exactly what TW-01 needs (read-only, one Edit-mode session, ~10 minutes)

1. `search_game_tree` / `inspect_instance` on `Workspace.GameWorld.TradingWorld`, `GameWorld.TradingCenter`, `GameWorld.Portals.HubPortal`, and the valley `GameWorld.Portals.TradePortal`: full child list one level deep, `GetDescendants()` counts (BaseParts / lights / emitters / Highlights / SurfaceGuis / scripts), `ModelStreamingMode`, every attribute, and the `CFrame`/`Size` of `TradeZone`, every `Booth<i>` pivot with its `BoothIndex`, each `Display<i>` CFrame (orientation matters), `Counter`, `SignBoard` SurfaceGui size, and the `PortalTouch` parts.
2. Any script under those containers not in the mirror (expected: none — Workspace has exactly three live scripts and all are mirrored).
3. `Players.MaxPlayers`; `workspace.StreamingEnabled`, `StreamingMinRadius`, `StreamingTargetRadius`, `StreamingIntegrityMode`.
4. `Lighting` children and key properties (ClockTime driver, Atmosphere, ColorCorrection, Bloom) — to know what the day/night cycle does to a cream/gold palette at night; whether `NightLights` / `DayNightCycle` reference any island part.
5. Terrain: confirm water surface height at (8000, ·, 8000) and the extent of terrain around the region (is there seabed voxel under the island or only water?).
6. Screen captures from the five 2026-08-09 camera positions (`docs/cove-rebuild-woah-2026-08-09.md`, "Five shots") plus one aerial — the visual audit the docs promised but never captured. Play mode not required.
7. Confirm `ServerStorage.PreCove_Backup_2026_08_02`, `AuditBackups.TeleportService_pre_coverebuild` and `World2Backups_2026_09_19.Rollback` exist (rollback dependencies).
8. Whether `InteractionPromptClient` (round 3) restyles `BuyPrompt` / `StandPrompt` today and what it draws (affects the price-plate design so the two never overlap).
9. The six guardian statues' model names (keep or recast).

Nothing in this list writes, moves or deletes anything, and none of it requires Play mode or Team Create control beyond a read.

## C.3 Proposed Phase 2 (for approval — not started)

**Scope:** greybox the Brainrot Grand Exchange beside the live island, verify every contract, capture it, revert-drill it. No art pass, no NPC models, no script edits outside the list below.

1. **Snapshot** exactly as §A.14 steps 0–1.
2. **Generator** `ServerStorage.TradingWorldBuild.Generator` (build-time only, `loadstring`-run in Edit mode like the World 2 generator; versioned; `ClearAll()`; every number in one table at the top): `Landing()`, `Causeway()`, `Arch()`, `Hall()`, `Arcades(N)`, `Vault()`, `Records()`, `Piers()`, `Rim()`, `Colossi()`, `Dressing()`, `Contracts()` (the booth modules, `TradeZone`, portals — verified against §A.6 by a self-check that prints `OK 30/30`), `Totems()`. Output into `GameWorld.TradingWorld_GE` + `GameWorld.TradingCenter_GE`.
3. **Driver** `TradingWorld_GE.ExchangeDressing.ExchangeDriver` — a copy of `CoveDriver` with the same tags, `C`, `WAKE_RADIUS`, probe attributes; `SkipLoop` gets `R`/`WATER_Y` updated and the same sleep gate. Both mirrored byte-exact per the team rule.
4. **Rollback** `ServerStorage.TradingWorldBackups_<date>.Rollback` written *before* the cutover, drilled once (V10).
5. **Cutover** (rename) only after the owner says so; then one Play session: `[BoothHandler]` prints no warn and adopts N stands; `TradeClient` shows the nearby list on the floor; arrival lands on the deck; `BoundsGuard` returns 0 corrections across a full walk of every lane and level; `WorkCount` delta 0 with nobody within 400 studs.
6. **Probes** (the cove's V1–V10 plus): V11 every `Display<i>` local +Y is world-up and its cube lands inside the stand's footprint; V12 walk the promenade with a 30-stand server: every `BuyPrompt` reachable from the lane stripe without leaving it; V13 phone viewport (`iphone_16`) captures of one stand and the price plate; V14 part/light/emitter/Highlight counts vs §B.1.11; V15 a Persistent/streaming read from a client 1,000 studs away.
7. **Captures** from the same five viewpoints + the lane + the balcony + the Vault, into `docs/trading-world/captures/<date>/`.
8. **D4 client dressing** only if approved, as its own task after the greybox is signed off.

**Out of Phase 2:** the art pass (Phase 3), NPC characters (NPC-01, placed on the §B.1.16 marks), booth/trade UI panels (Pete), any economy file, `Lighting`, `Terrain`, the `ComingSoon` line.

## C.4 Lane boundaries (what TW-01 will and will not touch)

| Will touch (Phase 2, with approval) | Will NOT touch |
|---|---|
| New containers `GameWorld.TradingWorld_GE` / `TradingCenter_GE` (then the rename), `ServerStorage.TradingWorldBuild.*`, `ServerStorage.TradingWorldBackups_<date>.*` | `BoothHandler`, `TradeHandler`, `BrainrotMover`, `GiftService`, `PriceIndex`, `ItemStatsService`, `PlayerDataManager`, `EmeraldService`, any remote |
| `TradingWorld.*.ExchangeDriver` (new), `EternalSkip.SkipLoop` (two constants + gate) | `BoothClient`, `TradeClient`, `WorldsPanel`, `InteractionPrompt*` (Pete) |
| `docs/trading-world/*`, this report | `WorldTravelConfig` (`ComingSoon` is the owner's switch), `TeleportService` (unless D8/D9 are handed to this lane), `BoundsGuard` (the island fits the box) |
| `GameWorld.Portals.HubPortalVault` (new model, attributes only) | `Lighting`, `Terrain`, `PlayerBases`, the valley `TradePortal` (Duck), anything under `FrozenTundra` (Beast), Gardens (World 3), NPC rigs/assets (NPC-01) |

---

*Phase 1 ends here. Nothing was built, deleted, moved or edited in Studio. Branch `trading-world-rework` holds this report, the layout SVG and the NPC-01 handoff.*
