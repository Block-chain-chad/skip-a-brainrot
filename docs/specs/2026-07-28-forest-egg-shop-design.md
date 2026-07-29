# Forest Egg Shop + Darrels + Pet System — Design

Date: 2026-07-28 · Approved by: user (chat) · Status: spec for review

## Summary

Wire the dormant EggStall into a real feature: **5 tiered gacha eggs** bought with a new
premium currency (**darrels** 💎), hatching **10 forest-exclusive brainrots** designed by the
user. Ship the full **pet system** (hatch/equip/follow/boost) disabled behind a flag, with
content arriving later. Everything is **world-keyed** — Forest is World 1 of a planned series.

User's stated economy goal: *"harder to progress but still keep players engaged."*

## Decisions made with the user (2026-07-28)

| Question | Decision |
|---|---|
| What hatches | Egg-exclusive brainrots + boost pets (hybrid) |
| Pet slots | 3 equipped free, **6 with a gamepass** (id TBD by user) |
| Content source | User-supplied designs (chart + OBJ); pets designed later by user |
| Brainrot egg currency | Darrels: quests, daily quests, Robux dev products |
| Pet egg currency | Regular cash |
| Egg mechanics | **5 tiered gacha eggs**, published odds, no pity |
| Event window | Forest = World 1 of future multiple worlds; config-keyed, no hard end date |
| Economy scaling | **Rescale chart incomes into existing tier bands** (top-of-band anchors) |
| Architecture | **Approach B** — self-contained subsystem, narrow seams |

## Source art (vendored at `docs/design-handoff/forest-eggs/`)

- `forest-brainrot-chart.html` — user's Claude-designed chart: 10 creatures, names/tiers/prices.
- `forest-brainrots-sprite.png` — extracted 5×2 render sheet (voxel style), build reference.
- `eggs_forest_set.obj` — 10 egg meshes (~5k faces each). **Eggs #6–10 are the forest eggs**
  (Shard / Drip / Horned / Rune / Crown, by decoration groups); #1–5 reserved (likely pet eggs).
- `eggs_forest_set.mtl` — found in Downloads root 2026-07-28, vendored beside the OBJ.
  All 31 referenced materials defined with authored colors. (User also has candy / elemental /
  goof / machine / vault egg sets staged for future worlds — not vendored, not in scope.)

## 1 · Player experience

- EggStall's existing `PromptPart.EggPrompt` ("Open Eggs") opens the **Egg Shop** panel
  (UITheme cafe/candy style). 5 eggs displayed with price and **full odds table always visible**
  (Roblox policy requires published odds for paid random items — mandatory, not optional).
- Darrel balance shown in-panel; a "How do I get darrels?" row points at quests/daily/Robux.
- Hatch: egg model shakes → shard groups separate → creature pops out spinning with the
  RarityFX ladder treatment. Compact (< 4 s), skippable by click.
- Hatched creatures are normal brainrots: pads, income, sell, trade, backpack, Index — with a
  **FOREST EGG** source badge in the Index instead of throw availability.

## 2 · Economy

### Creatures (chart ladder, re-anchored to top-of-band)

| # | Name | Tier | $/s | Found in |
|---|---|---|---|---|
| 1 | Cervolino Antlerino | Epic | 800 | Shard |
| 2 | Fanghetto Palunko | Epic | 870 | Shard, Drip |
| 3 | Strigolino Hootini | Epic | 950 | Shard, Drip |
| 4 | Rospino Bavaglio | Legendary | 4,800 | Drip, Horned |
| 5 | Corvacchio Beccarino | Legendary | 5,400 | Horned |
| 6 | Ceppone Zampalunga | Legendary | 6,000 | Horned, Rune |
| 7 | Alcione Trombettone | Mythic | 25,000 | Rune, Crown |
| 8 | Lucciolone Pantanini | Mythic | 29,000 | Rune, Crown |
| 9 | Gufocervo Stiltini | Mythic | 33,000 | Rune, Crown |
| 10 | Muschione Cornaluna | Secret | 60,000 | Crown only |

### Eggs and odds (server-authoritative; displayed verbatim in shop)

| Egg | Price | Odds |
|---|---|---|
| Shard | 60💎 | Cervolino 50 / Fanghetto 32 / Strigolino 18 |
| Drip | 85💎 | Fanghetto 34 / Strigolino 36 / Rospino 30 |
| Horned | 115💎 | Rospino 45 / Corvacchio 35 / Ceppone 20 |
| Rune | 160💎 | Ceppone 40 / Alcione 30 / Lucciolone 20 / Gufocervo 10 |
| Crown | 220💎 | Alcione 34 / Lucciolone 30 / Gufocervo 30 / **Muschione 6** |

### Darrel faucet (harder-but-engaged target: ~10–14💎/day active)

- **3 rotating daily egg-quests** (new, DarrelService-owned; e.g. "skip 25 rocks",
  "catch an Epic+", "collect $50k campfire cash") → 8–12💎/day total.
- **Login-streak milestones** (existing DailyRewardHandler): +5💎 at day 3, +15💎 at day 7.
- **One-time goals** (existing QuestHandler): 20–40💎 on selected milestones.
- **Robux packs** (dev products, ids TBD by user): 80💎 / 180💎 / 400💎 / 1000💎.
- F2P pace: first Shard ≈ day 5; Crown ≈ 3 weeks. Tunable in one config table.

## 3 · Architecture (Approach B)

New files, single-purpose, narrow seams:

| Module | Location | Purpose |
|---|---|---|
| `EggConfig` | ReplicatedStorage.Modules | World registry: `WORLDS.Forest = { Active, Eggs, Creatures }`. Pure data. |
| `EggHandler` | SSS.Modules | Buy → validate → deduct → roll → grant. No yields inside the commit. |
| `DarrelService` | SSS.Modules | Balance/earn/spend, daily egg-quests, streak/goal hooks. |
| `ProductRegistry` | SSS.Modules | **The game's single `ProcessReceipt`**, table-driven; darrel packs first, extensible (wheel spins later). Idempotent via PurchaseId dedupe. |
| `PetConfig` | ReplicatedStorage.Modules | Pet defs + `ENABLED = false` flag. Placeholder until user's pet chart. |
| `PetHandler` | SSS.Modules | Hatch/equip/unequip, follow rigs, boost math. |
| `EggShopClient` | StarterPlayerScripts | Shop panel, odds table, hatch reveal, darrel HUD chip. |

Remotes (new, under `ReplicatedStorage.Remotes`): `EggShopState`, `EggBuy`, `EggResult`,
`PetEquip`, `DarrelUpdate`.

### Integration seams (everything else untouched)

- **BrainrotConfig**: +10 entries with **`Weight = 0`** (the documented load-bearing pattern used
  by Chim/Pete/Maxwell) + `Source = "ForestEgg"`. Throws can never roll them; pads/income/
  sell/trade/index work with zero new code.
- **Grants** go through `BrainrotMover.Give` — inherits the 2026-07-28 trade hardening
  (serials, unique-cap netting, mutation safety). Never through ThrowHandler; discovery and
  mint stats are not inflated (honors ThrowHandler's standing comment).
- **PetHandler.LuckMult(player)** → one multiplier read in ThrowHandler's rollDistance
  (same pattern as RebirthConfig.LuckMult / WeatherLuck). **PetHandler.IncomeMult(player)** →
  one multiplier read in IncomeLoop. These are the only two touches on shared gameplay files.
- **PlayerDataManager schema** (+defaults +nil-migration): `Darrels = 0`, `Pets = {}`,
  `PetSlots = {}`, `EggsOpened = {}`, `DarrelDaily = {}` (quest state), `ReceiptLog = {}`
  (recent PurchaseIds).
- **Main.Init**: register DarrelService, EggHandler, PetHandler, ProductRegistry.

### Pets v1 (shipped disabled)

- Save-side: pet entries `{ Uid, Id, Boost = { Type = "Luck"|"Income", Amount } }`.
- Slots: `SLOTS_FREE = 3`, `SLOTS_PREMIUM = 6` gated on `PET_SLOTS_GAMEPASS_ID` (placeholder 0 ⇒
  premium path inert until the user creates the gamepass).
- Boost stacking: additive within type — `mult = 1 + Σ Amount`.
- Follow rig: ≤10 Massless CanCollide-false parts per pet, AlignPosition hover-follow in
  offset slots behind the character. Perf budget: 6 pets × 6 players ≤ 360 parts worst case.
- `PetConfig.ENABLED = false` hides all pet UI and pet-egg purchases until content lands.
  Pet eggs will use OBJ eggs #1–5 and cost cash (prices TBD with the pet chart).

## 4 · Content build

- **10 creatures**: rebuilt as anchored voxel part-models from the sprite renders (front-3/4
  reference, symmetric completion), ~30–80 parts each, SmoothPlastic, cafe-saturated palette.
  Stored in `ReplicatedStorage.BrainrotModels` (1:1 with config, keeping the invariant).
  Name-collision check against RENAMES keys and live config names at build time (10 new names
  verified unique before insertion).
- **5 egg meshes**: user performs **File → Import 3D** on `eggs_forest_set.obj` once (their
  account, ~30 s). Builder then splits/parents eggs #6–10 into `ReplicatedStorage.EggModels.Forest`
  with shard groups preserved for the hatch animation. If the MTL stays missing, colors are
  authored from material names + the chart's palette.
- Shop display: the 5 eggs replace/augment the 15 static `EggGood` cubes on the stall shelves
  (EggGood cubes stay as ambient decor; real egg models go on the counter).

## 5 · Safety and edge cases

- Rolls are server-side (`Random.new()` per server, never client-influenced).
- Purchase commit is atomic: validate darrels → deduct → roll → Give, **no yields between**;
  Save called after, return-checked with the audit-log pattern from the trade hardening.
- `data.__noSave` sessions cannot buy eggs or receive darrel purchases (item-destruction guard,
  same as trades); Robux receipts for such sessions return `NotProcessedYet` so Roblox retries
  when the profile is healthy.
- `ProcessReceipt` is idempotent: PurchaseId checked against `ReceiptLog` before granting;
  log capped (ring buffer 50).
- If `BrainrotMover.Give` refuses (unique cap): darrels are refunded in the same commit and a
  toast explains why. No partial states.
- Odds shown in UI are generated from `EggConfig` (single source of truth) — display can never
  drift from server behavior.
- Egg quests award via one `DarrelService.Award(player, n, reason)` chokepoint (auditable).

## Out of scope (v1)

- Pet content (user's chart pending), pet-egg pricing, gamepass creation (user, on roblox.com),
  dev-product creation (user), World 2+, pity system (explicitly declined), trading darrels
  (never — currency stays untradeable), CatchReveal integration (egg reveal is its own compact
  animation).

## Open items

1. Gamepass id (+3 pet slots) and 4 dev-product ids (darrel packs) — user creates when ready;
   placeholders keep both paths inert.
2. Pet chart — user supplies later; `PetConfig.ENABLED` stays false until then.

## Acceptance criteria

1. Buying each of the 5 eggs with sufficient darrels hatches a creature from its published
   table; 10k-roll simulation per egg matches odds within ±1.5 pp.
2. Insufficient darrels → refusal toast, no deduction, no grant.
3. Hatched creature places on a pad, earns its exact $/s, sells, trades, and appears in the
   Index with the FOREST EGG badge; throws can never produce it (Weight = 0 verified).
4. Odds table in the shop matches `EggConfig` exactly.
5. Daily egg-quests award darrels once per UTC day; streak/goal hooks award once.
6. `ProcessReceipt` grants exactly once per PurchaseId (double-delivery test passes) and
   returns `NotProcessedYet` for `__noSave` sessions.
7. Pet system: with `ENABLED = false` nothing is visible; flipping it in Studio shows the
   equip UI and a placeholder pet follows with its boost measurably applied (test-only).
8. Zero console errors through a full buy→hatch→place→sell cycle in Play mode.
