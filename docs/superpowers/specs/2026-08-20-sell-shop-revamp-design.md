# Sell shop revamp — Marco's counter

Date: 2026-08-20
Status: design approved, not yet implemented

## Problem

Marco's sell panel (`StarterGui.MainUI.SellFrame`, built inline in `ClientMain`) is a flat
scrolling list, one row per brainrot *species*. Measured against a live save:

- **104 rows**, 84px each — roughly **8,700px of scroll**, alphabetical, with no search, sort or
  filter.
- Each row crams a 56px 3D icon, a name, a four-clause subtitle and two stacked buttons into a
  text column of about **296px**.
- **630 unplaced copies** sit behind those 104 rows, and a copy's value spans **1x–760x** within a
  single species (mutation 1–95 × size 1/3/8). One row cannot express that.
- **76% of rows survive a SELL ALL** (81 of 106 species), because bulk sell deliberately skips
  mutated copies — with nothing in the UI saying so.

Owner verdict: "It looks really bad. I would be so confused and frustrated."

Two structural problems sit underneath the layout:

1. The panel is built inline in `ClientMain`, which is **at Luau's hard ceiling of 200 locals per
   function** — three added `require` lines broke the whole script earlier the same day. A richer
   panel cannot be built there.
2. It is the last consumer of the legacy `UITheme.bazaar*` pack. Every other panel moved to
   `UIKit`/`PanelChrome` under `GameHUDPanels`.

## Goals

- One counter that sells **brainrots and pets**, extensible to a third category.
- The common visit — clearing duplicate junk — becomes one confident, safe action.
- Any individual copy stays findable and sellable at its true value.
- The advertised price can never disagree with the price paid.

## Non-goals

- **Charms are out of scope.** `CharmConfig` is a 16-entry *design spec*, not mechanics: its
  `Config` field is a descriptive string (`"SellAdd = 0.35, IncomeAdd = -0.10"`) and `Hook` is a
  note naming where it would wire in. There is no charm inventory and no charm sell path anywhere
  in the codebase. Selling charms requires implementing charms as ownable items first — a separate
  project.
- Not changing `SELL_MULTIPLIER` (40) or the pricing formula. Those were settled on 2026-08-20:
  intrinsic parity, `base × Mutations.Mult × Sizes.Mult × 40`.
- Not touching trading, the booth, or fusion.

## Architecture

### New: `StarterPlayer.StarterPlayerScripts.GameHUDPanels.SellPanel`

The panel moves out of `ClientMain` into its own module beside `BackpackPanel`, on
`UIKit`/`PanelChrome`. `ClientMain` retains only the stall prompt binding and a call to
`SellPanel.Open(part)`. Preserved from the current implementation:

- `SideRail.registerPanel(...)` — the single-open panel registry.
- The Heartbeat auto-close when the player walks more than 20 studs from a sell stall.
- Marco's `MerchantDialog` intro before the panel opens.

### New: `ReplicatedStorage.Modules.SellValue`

Single owner of every sell price. Exports:

- `SellValue.MULTIPLIER` — 40.
- `SellValue.BaseRate(name)` — species base cash/sec, built once from `BrainrotConfig` merged with
  every `WorldProgression` pool. Returns nil for a name present in no config (the ghosts).
- `SellValue.OfBrainrot(entry)` — `floor(BaseRate(entry.Name) × Mutations.Mult(entry.Mutation) ×
  Sizes.Mult(entry.Size) × MULTIPLIER)`; nil when the name is unpriceable.
- `SellValue.OfPet(petId)` — wraps `PetConfig.SellValue`.

Rationale: this logic currently exists twice, added to both `SellHandler` and `ClientMain` on
2026-08-20. That duplication is precisely the bug class being fixed — a row advertising one number
while the server pays another. Both sides consuming one module makes the mismatch structurally
impossible rather than merely tested against.

Player-level multipliers (rebirth, upgrades, pets, gamepass) stay **out** of sell value: they
belong to the player, not the item, and including them would make one brainrot worth different
amounts to different sellers.

## UI

### Tabs

`Brainrots` / `Pets`. A third tab slot is left in the layout for charms.

### Quick sell bar

One action at the top of each tab. Its set is defined precisely and narrowly:

> unplaced, not favourited, no mutation, **no size**

The bar shows live count and total before commitment, and routes through a confirm dialog — the
bulk action is irreversible.

Deliberately **not** bucketed by price threshold: "under $100" is junk at one player's scale and a
fortune at another's. The bar sells *duplicates*, not *cheap things*.

### Decision: bulk actions hold back sized copies too — changes existing behaviour

Today's per-species SELL ALL tests `entry.Mutation == nil` and **never tests size**, so it sells a
plain Huge (3×) or plain Massive (8×) at bulk, alongside genuine 1× duplicates. Before 2026-08-20
that was invisible, because size did not affect price at all; now that it does, a bulk button that
sweeps up an 8× copy is a trap.

Resolved: **every bulk path — the quick sell bar and per-species SELL ALL — holds back any copy
with a mutation or a size.** Sized copies are sold from the drill-down, deliberately, like mutated
ones. The alternative (letting the quick sell bar match SELL ALL exactly) was rejected: matching a
rule that is itself unsafe is not a virtue.

This is a **behaviour change to an existing button**. Owner signed off 2026-08-20, choosing the
strict rule over leaving SELL ALL as it was.

The held-back count in the row subtitle and toast must therefore read "mutated or oversized", not
"mutated".

### Species grid

Art-first tiles reusing the Bag's established vocabulary — count badge, violet star when any copy
is mutated. Tapping a species opens a drill-down listing that species' copies, each priced
individually. This keeps 630 copies addressable without ever rendering 630 rows.

The drill-down supports **multi-select with a running total**, which is what the `Uids` payload form
exists to serve. Selling one copy is the degenerate case of selecting one — there is no separate
single-sell path to keep in sync. Favourited and placed copies appear in the list but are not
selectable, each labelled with the reason, so the server's refusal is never a surprise.

### Search

Filters the grid by name. 104 tiles still needs it.

### Unsellable items are shown, not hidden

Two names in the live save (`Gelatini Renna` uid 447, `Nevito Lupetto` uid 448 — the BagCell169/170
ghosts) exist in no config and have no price. Today they silently vanish from the list. They will
render greyed with "can't be sold": a player who counts 646 in the bag and 644 in the shop should
be told why.

## Server

### `SellBrainrot` payload forms

| Form | Meaning |
| --- | --- |
| `{ Name, Mode = "One" }` | existing — least valuable unfavourited copy, ranked by full value |
| `{ Name, Mode = "All" }` | existing, **semantics tightened** — unfavourited copies with no mutation *and* no size |
| `{ Uids = { ... } }` | new — precise multi-select from the drill-down; the only path that can sell a mutated or sized copy |
| `{ Mode = "Duplicates" }` | new — the quick sell set, same rule as `"All"` but across every species |

Every form prices per copy via `SellValue.OfBrainrot` and sums. No form may use a per-species price.

`IncludeMutated` is **retired**. It was the client's opt-in to bulk-sell mutated copies and no
caller ever set it, so the flag only ever served to make the zero-sold path confusing. Deliberate
selling of mutated or sized copies now goes through `Uids`, where the player has seen each copy's
individual price before selecting it.

### `PetHandler.SellMany(player, uids)`

New, so the pets tab can bulk-sell. Wraps the existing per-uid `PetHandler.Sell` guards — the
equipped-pet refusal and the `__noSave` check.

### `SellHandler` gets the `__noSave` guard

`PetHandler.Sell` already refuses to sell in a read-only session, because a failed DataStore load
serves a default profile and every write is discarded at logout. `SellHandler` has no such guard,
so a brainrot can today be destroyed for cash that evaporates on rejoin. This is a genuine
data-loss bug, independent of the redesign, and is fixed as part of it.

## Edge cases

- **Read-only session** — refuse both tabs, reusing `PetHandler`'s existing wording.
- **Favourited / placed copies** — already refused server-side; the UI shows them as held back so
  the refusal is never a surprise.
- **Unpriceable names** — excluded from every bulk set, shown greyed, never silently dropped.
- **Empty state** — nothing sellable reads as an invitation, not an error.
- **Partial failure in a multi-select** — report what sold and what did not, with the reason.

## Testing

- Pure logic (`SellValue`, the selection sets) unit-tested in Edit mode — the approach that caught
  every issue on 2026-08-20.
- Live panel verified through the `ProximityPrompt:InputHoldBegin()` trigger plus the same-rock
  `EquipRock` refresh (see the play-mode verification notes in memory).
- The invariant that matters, swept across the whole inventory: **advertised price == price paid**,
  for every button in every tab.

## Deferred, flagged

- `BrainrotMover.Take` shares the size-blind "least valuable" rule fixed in the sell path on
  2026-08-20. Same class of bug, different file.
- Charms as ownable items — blocks the third tab.
- The two ghost inventory entries need an owner data-cleanup decision.
