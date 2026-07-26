# Bounded Supply — "The Vault & The Tide"

**Game:** Skip a Brainrot (Roblox)
**Date:** 2026-07-25
**Status:** Approved design, pending implementation plan

## Goal

Brainrots cannot hold trade value while every name is catchable in unlimited
numbers forever. Give the 213-name roster bounded supply, tiered by rarity, so
existing copies can become scarcer over time — feeding the Trading Center —
without ever touching what players already own.

## What already exists (reused, not rebuilt)

- **MintRegistry** (`ServerScriptService.Modules.MintRegistry`) — global
  serials + live exists-counts for Legendary/Mythic/Secret and all mutations.
- **LimitedStock** (`ServerScriptService.Modules.LimitedStock`) — atomic,
  fail-closed, universe-wide mint caps. Currently only Secret Pete (cap 5).
- **BrainrotWaves** (`ReplicatedStorage.Modules.BrainrotWaves`) — catchability
  gate consulted by exactly two callers: `RarityRoll` (server, per roll) and
  `IndexClient` (UI). Currently `RELEASE_ALL = true`.

## Tier policy (decided)

| Tier | Pool | Mechanism |
|---|---|---|
| Common, Uncommon | — | Always catchable. Never gated. |
| Rare, Epic | ~half live at a time | **The Tide**: weekly A/B rotation. Away names always come back. |
| Legendary (24), Mythic (18) | shrinks/refreshes | **The Vault**: seasonal batch retirement (permanent) + seasonal debuts of new names. |
| Secret (11 + Pete) | born finite | **Hard mint caps**, ladder 500 → 25 (Pete stays 5). Sold out = trade-only forever. |

Ownership is never touched: vaulting/rotation/caps gate *catching* only.
Placed brainrots, saves, trades, and market stands work unchanged for retired
names — retired names become the Trading Center's premium inventory.

## Architecture

One new shared module is the single source of truth for time-based
availability; everything else consults it or is pure config.

### 1. `ReplicatedStorage.Modules.SupplySchedule` (new)

Deterministic from the UTC clock (`os.time()`); no DataStore, no publish
needed for scheduled changes. Every server and client independently computes
the same answer.

- **`SEASONS`** — authored table, explicit UTC start dates ~8 weeks apart:
  ```lua
  SEASONS = {
    { Starts = <utc>, Retire = { "Name", ... }, Debut = { "Name", ... } },
  }
  ```
  Semantics: a season's `Debut` names become catchable when the season
  **starts**; its `Retire` names stop being catchable when the season **ends**
  (so the whole season is the "last chance" window, with countdown).
  **Pre-launch dormancy (amended 2026-07-25 — the game is not public yet):**
  before `SEASONS[1].Starts` the schedule is dormant — no tide, no retiring
  countdowns, everything catchable (caps still apply). Season 1's `Starts` is
  authored as a far-future placeholder and set to the real go-live Monday at
  launch; the whole economy wakes up with the actual player base, so nothing
  can retire before the public ever had a chance to catch it.
  Season 1's retire batch (mid-ladder
  picks, so neither a tier's weakest nor its apex leaves first):
  Legendary — *Sovrano Pancetta*, *Console Grattugia*; Mythic — *Idolo
  Cappelletto*. Season 1 has no debuts; debuts begin when newly authored
  names exist.
- **The Tide (Rare + Epic)** — once per season a shuffle seeded by the season
  index splits each tier into Set A and Set B (odd-size tiers put the extra
  name in A). Week index = `floor((now − Season1Start) / 604800)`; even index
  → A is live, odd → B. (Deliberately not ISO week numbers: ISO's occasional
  week 53 would put two A-weeks back to back.) Guarantees every name is live
  at least every other week, and lets players plan ("B-week").
- **API:**
  - `IsObtainable(name) → bool`
  - `StatusOf(name) → status, timestamp` where status ∈
    `live | away | retiring | vaulted | unreleased | capped`
    (`away` = tide, returns next week; `retiring` = leaves at season end;
    `unreleased` = debuts at a future season start; `capped` = has a mint cap,
    UI pairs it with the sold-out count from the server snapshot).
    Precedence when several could apply: `unreleased` > `vaulted` >
    `retiring` > `away` > `capped` > `live`. Sold-out is deliberately NOT a
    schedule status — the schedule is clock-pure and identical on client and
    server; sold-out comes only from LimitedStock (server) via the snapshot.
  - `NextChange() → timestamp` (next tide flip or season boundary, for UI)
- **Injectable clock** — `SupplySchedule.SetClock(fn)`, Studio-only
  (`RunService:IsStudio()` guard), so tests can step across week and season
  boundaries.

### 2. `BrainrotWaves` becomes a thin adapter

Keeps its public API (`IsObtainable`, `Counts`) so `RarityRoll` and
`IndexClient` don't change imports; internally delegates to SupplySchedule.
The build-once `obtainable` table and `RELEASE_ALL` go away; `VAULTED` and
`FORCE_ON` remain as manual overrides of last resort (checked after the
schedule). `Counts()` becomes time-varying.

### 3. `LimitedStock` — Secret cap ladder (config only)

Extend `MAX` with the 11 rollable Secrets, caps stepping down the tier's
power ladder:

| Name | Cap |
|---|---|
| Il Papa Meteorite | 500 |
| Il Tiranno Eclissi | 400 |
| La Sentinella Vuoto | 320 |
| Sua Altezza Galassia | 250 |
| Il Verdetto Supernova | 200 |
| La Cattedrale Cometa | 150 |
| Il Colosso Equinozio | 120 |
| Il Firmamento Ribollente | 90 |
| L'Ammiraglio Nebulosa | 65 |
| La Genesi Corazzata | 45 |
| Sua Grazia Abisso | 25 |
| Secret Pete | 5 (unchanged) |

No code changes: the module is already atomic (UpdateAsync per key) and
fail-closed on DataStore errors.

### 4. `RarityRoll` — respect sold-out

The existing `IsObtainable` filter additionally skips names where
`LimitedStock.SoldOut(name)` is true (cheap, non-yielding, stale-tolerant —
`TryClaim` remains the authority at grant time, as it already is for Pete).
The claim path must also handle a weighted-roll Secret losing the
authoritative `TryClaim` race: reroll that throw excluding the sold-out name
rather than granting nothing.

### 5. Index UI — supply states

`IndexClient` gains per-name badges in the campfire UITheme style:

- `away` → "RETURNS <weekday>" chip
- `retiring` → "LEAVES <n>d <n>h" countdown chip (urgency accent)
- `vaulted` → "VAULTED" badge (owned copies still render normally)
- `unreleased` → hidden or "???" silhouette with "DEBUTS <date>"
- `capped` → "<remaining> OF <cap> LEFT", flipping to "SOLD OUT — <cap> EXIST"

Sold-out data is server-side, so one new RemoteFunction (`GetSupplySnapshot`)
returns `{ [name] = { cap, minted } }` for capped names; client refreshes it
on Index open, throttled. Everything else is computed client-side from
SupplySchedule.

## Future (explicitly supported, not built now)

**Seasonal-event limited-time brainrots**: a name with a `Debut` in one season
and `Retire` in the same (or next) season is a limited-time event brainrot —
e.g. a Halloween Mythic live for 10 days, then vaulted forever. The schema
above already expresses this; no redesign needed.

## Edge cases

- **Config entries are never deleted** (existing rule) — saves, trades, and
  the Index must keep resolving retired/vaulted names forever.
- **Boundary flips mid-throw** — the server's answer at resolve time wins;
  worst case one lucky last catch, never a broken one.
- **Clock skew** — transitions are fixed UTC instants computed identically
  everywhere; a few seconds of server/client disagreement only affects
  cosmetic countdowns.
- **Cap raced by two servers** — already solved: `TryClaim`'s UpdateAsync is
  atomic; loser rerolls (see §4).
- **Season table exhausted** — past the last authored season, the schedule
  holds its final state (last tide split keeps alternating; nothing further
  retires or debuts). Shipping the next season is a config edit.

## Testing

- **Schedule unit pass (Studio, injected clock):** step across week and season
  boundaries; assert tide membership alternates A/B with full coverage,
  retire/debut flips happen exactly at boundaries, determinism (same time →
  same sets), and Common/Uncommon are always live.
- **Roll integration:** with a mocked sold-out Secret and a retired Mythic,
  large-sample `RarityRoll` never returns either; tide-away names never roll.
- **UI check:** Index shows correct badges for each of the six states with
  the clock forced to interesting instants; play-test the snapshot remote.
- **Regression:** owned retired names still place, trade, and appear in the
  Index as owned.
