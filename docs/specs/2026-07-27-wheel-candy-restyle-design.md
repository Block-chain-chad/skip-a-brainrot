# Wheel Candy Restyle + Buyable Spins — Design

**Date:** 2026-07-27
**Status:** Approved (user approved art direction, wheel-first ordering, scope and the details-panel decision 2026-07-27)
**Scope:** Phase 1 is client-only. Phases 2–3 add a per-player spin balance and a Robux product.

## Goal

The user's words: *"our wheel looks too basic."* Rebuild the daily spin wheel in the **candy / Pet-Simulator** visual direction supplied in their design handoff, add the information the reference shows (per-segment odds, a details panel), and add buyable extra spins.

## Origin of the art direction

The user supplied `Roblox Brainrot Game UI.zip` — a full design handoff (`design_handoff_brainrot_ui/`) with a README and three HTML mockups built specifically for this game. **Build from v3**, the bright/candy treatment. Plus separate reference screenshots of another game's "Crystal Wheel".

**The handoff is a whole-game UI redesign** — HUD plus eight modal panels. This spec covers **only the wheel**. Two of its panels (egg hatching, gems) describe systems this game does not have and are out of scope entirely. The handoff contains **no wheel**; the wheel references are the user's separate screenshots. The user's note on those: *"They don't need to necessarily be that spiky and popping."*

### The art-direction decision, and the revert path

The handoff's palette (sky blue, white panels, Luckiest Guy) is a **different direction from the cafe restyle** completed days earlier (cream, warm-brown ink, Own a Cafe reference, five stages). The user chose **"go full candy and if we don't like it just revert it back."**

That revert requirement is honoured **by not overwriting anything**:

- Candy lives as a **new `UITheme.Candy` token table plus additive helpers**, beside the existing `Camp`.
- **`Camp` and every current caller are untouched**, so nothing on screen changes except the wheel.
- Reverting phase 1 = reverting `WheelClient`. No global refactor to unpick.

Rolling candy out to the other 12 clients would mean changing how each reads its colours. That is a separate decision to make **after** looking at the wheel, not a speculative refactor now.

## Non-goals

- **No change to `WheelConfig`'s numbers.** Odds, payouts, cooldown and boost values stay exactly as they are. Displayed odds are *derived from* the existing weights so display can never drift from reality.
- No change to the other panels, the cafe world art, or `UITheme.Camp`.
- Not the handoff's HUD, shop, inventory, upgrades, rebirth, gamepasses, daily or hatch panels.
- **The jackpot slot stays flat cash.** Turning it into a random top-tier brainrot pool was considered and explicitly deferred: it collides with Secret mint caps and the vault/tide schedule, and belongs in its own spec.

## Current state

| Slot | Payout | Weight |
|---|---|---|
| SMALL CASH | +$1,000 | 35 |
| BIG CASH | +$10,000 | 25 |
| LUCK BOOST | +30% for 10 min | 15 |
| POWER BOOST | +30% for 10 min | 15 |
| HUGE CASH | +$100,000 | 9 |
| JACKPOT | +$2,500,000 | 1 |

`COOLDOWN` 86400s (24h), `BOOST_MULT` 1.3, `BOOST_TIME` 600s, `TOTAL_WEIGHT` 100 — so weights are already percentages.

- `StarterPlayerScripts.WheelClient` — 557 lines, draws everything. Emoji icons (💵🍀💰🏆💪💎), flat segments, **no pointer**.
- `ServerScriptService.Modules.WheelHandler` — the free daily spin, `Init()` called from `Main`. Phase 2 extends this rather than adding a system.

---

## Phase 1 — restyle (client-only, nothing blocked)

### Tokens

From the handoff's documented set:

| Token | Value |
|---|---|
| Ink / outline | `#10131f`, 6px on every element |
| Panel shell | `#ffffff → #cfe0f5` vertical |
| Chunky shadow | solid offset, **no blur**: `0 6–16px 0 #0a0d16` |
| Corner radius | 24–32 on panels, 14–18 on chips |
| Danger / close | `#ff5c7a → #a3123a` |
| Positive green | `#a3ff4f → #3d9e18` |

The **chunky solid shadow is the load-bearing detail** — it is what makes the mockups read as toy-like and three-dimensional. Roblox has no `box-shadow`, so it is drawn as an offset dark `Frame` behind each element, not a blurred image.

⚠️ **These pixel values come from a 1920-wide web mockup and are starting points, not targets.** A 6px `UIStroke` at Roblox UI scale is heavy, and Roblox strokes render differently from CSS borders. Outline thickness, shadow offset and corner radii all get **tuned by eye against a screenshot**, exactly as the cafe restyle's numbers were. The *relationships* are what must hold: outline thick enough to read as a comic outline, shadow solid and unblurred, radius generous.

Display font: the handoff specifies Luckiest Guy, which Roblox does not have. Nearest available is `FredokaOne`; **`UITheme.Candy` carries its own font token** so the wheel does not depend on `UITheme.Font` (currently `Cartoon`, the cafe face).

### The wheel face

- Six segments in the colours already on each `WheelConfig` slot, heavy black separators, thick outer ring.
- **A pointer at the top.** Its absence is a large part of why the current wheel reads flat — nothing marks where the result lands.
- Each segment shows its **value and its odds** (35% / 25% / 15% / 15% / 9% / 1%), computed as `Weight / TOTAL_WEIGHT`.
- Each segment's emoji sits in a **gradient chip** rather than bare. Swapping to real `IconForge` renders later is a drop-in and needs no layout change.

### The spin

The current spin is the weakest part. Replace with a long **ease-out that decelerates and settles** onto the pointer, followed by a **landing pop** on the winning segment.

⚠️ **The result must stay server-authoritative.** `WheelHandler` decides the outcome; the animation only *displays* it. The client must never pick the landing segment — it must animate *to* the server's answer.

### Details panel

A panel **beside the wheel**, matching the reference's placement rather than a separate screen or a tab — so odds are readable while spinning, which is the whole point. Lists all six slots, each with its icon chip, payout and exact odds, ordered rarest-first so the jackpot reads as the headline. Justified on its own terms: the on-wheel text is small and rotated. Derived from `WheelConfig`, never hardcoded.

On narrow viewports it must not overlap the wheel — the handoff's own responsive rule applies: use `min(px, vw%)`-style sizing rather than fixed widths, and collapse the panel below the wheel rather than letting the two collide.

### Fast Spin toggle

Shortens the spin animation. **Client-local, no schema change** — it resets on rejoin. Persisting a comfort setting is not worth a server data migration.

---

## Phase 2 — buyable spins (builds fully, dormant until phase 3)

### The `ProcessReceipt` hazard — the reason this is designed now

**Roblox permits exactly one `MarketplaceService.ProcessReceipt` callback per game.** Assigning it twice silently breaks the first, and with it every purchase.

A grep confirms **the game currently has none**, so this work would be first and would effectively own it. It is therefore built as a **registry that dispatches by product id**, not as a wheel-specific handler:

- one module owns the single `ProcessReceipt` assignment;
- systems register a handler per product id;
- unknown ids return `NotProcessedYet` so a receipt is never silently eaten.

The catch-reveal skip upgrade is already planned, so this shape pays for itself immediately. (That upgrade is a **gamepass**, which uses `UserOwnsGamePassAsync` and does *not* go through `ProcessReceipt` — but anything consumable after it will.)

### Data

`WheelSpins` added to `PlayerDataManager` defaults with a `Load` migration — the same pattern `DailyStreak`, `Quests`, `QuestDay` and `Rebirths` already use in that file. `PlayerDataManager` is shared with the collaborator, so the change is additive and minimal.

### Rules

- **The server grants spins; the client never asserts one.** A client that can say "give me a spin" can say it repeatedly. Same rule that kept auto-sell server-side in the catch-reveal work.
- Spending a spin and rolling the result both stay inside `WheelHandler`.
- The free daily spin is unchanged and independent of the purchased balance.

### UI

Buy 1 / Buy 3 buttons built and visible, wired to a **placeholder product id**, inert until a real one exists. A clearly-marked constant, following the `SEASONS[1].Starts` dormancy precedent already in this codebase.

---

## Phase 3 — go live

The user creates the developer product on the Creator Dashboard and supplies the id. One constant changes. Nothing else.

## Failure modes

| Failure | Handling |
|---|---|
| Server result arrives late or not at all | The wheel does not begin its final deceleration until the server answers; on timeout it stops neutrally and shows an error rather than landing on a lie. |
| A second `ProcessReceipt` is added later by anyone | The registry owns the only assignment; adding a product means registering, not assigning. Documented at the assignment site. |
| Purchase granted twice (duplicate receipt) | Receipts are keyed and recorded before granting, per Roblox's own guidance. |
| Player leaves mid-spin | Client-side animation only; the grant already happened server-side. |
| Displayed odds drift from real odds | Impossible by construction — both read `WheelConfig.SLOTS[i].Weight`. |
| Candy tokens leak into cafe panels | `Candy` is a separate table; no existing caller reads it. |

## Verification

**Phase 1 is judged by eye, not by assertions** — the same rule the catch-reveal work established after two bugs whose numbers were all correct while the screen was wrong. Screenshots required of: the wheel idle, mid-spin, on a result, the details panel, and Fast Spin on vs off.

Plus:
1. Landed segment matches the server's result across several spins — the animation must never disagree with the grant.
2. Odds shown equal `Weight / TOTAL_WEIGHT` for all six slots.
3. Cooldown display correct when a spin is unavailable.
4. Zero console errors.
5. Phase 2 verified by granting spins server-side directly, since a real purchase cannot be tested without the product.
