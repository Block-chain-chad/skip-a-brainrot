# Sell List Thumbnails + Close Button X — Design

**Date:** 2026-07-27
**Status:** Approved (user approved the ladder of changes and the UIStyle decision 2026-07-27)
**Scope:** Client UI only. Zero server, remote, economy or data-schema change.

## Goal

Two small, independent fixes the user asked for:

1. **Show the actual brainrots when selling.** The sell list identifies each brainrot by name and a flat coloured circle. Every other inventory surface in the game now shows a real 3D model.
2. **Make the close button's X visible.** The user's words: *"right now its just a red circle."*

## Non-goals

- No change to what selling *does* — prices, multipliers, the sell remote and its server validation are untouched.
- No restyle of the panels themselves. The close button keeps its position, size, colour and behaviour; only the glyph changes.
- Not a fix for panels that have no close button at all. Every panel in scope already has one; it is merely invisible.

---

## Part 1 — The close button X

### Root cause, established by proof board not by reading

`UITheme.styleClose` sets `btn.Text = "\u{2715}"` (✕, U+2715). **That character does not render in this Roblox build.** The button therefore draws as a bare red circle.

Proved with a live proof board of five candidates on identical plain-red buttons, screenshotted in Play:

| Glyph | Result |
|---|---|
| `\u{2715}` ✕ — **currently shipped** | **blank** |
| `\u{00D7}` × | renders, thin |
| `X` (ASCII) | renders, clean |
| `\u{2716}` ✖ | renders, bold |
| two rotated `Frame`s | renders, thickest — **chosen** |

**An earlier diagnosis was wrong and is worth recording.** `IndexClient:245` carries the comment `-- keep GothamBold from styleClose: FredokaOne has no U+2715 glyph`. That treated the problem as font-specific and "fixed" it by pinning GothamBold. The board was rendered *in GothamBold* and still came out blank, so U+2715 is missing there too and that workaround never worked. **Do not re-fix this by switching fonts.**

A second theory — that `M.gradient`'s `UIGradient` was multiplying the white glyph down to red, a documented trap in this codebase — was also tested and **disproved**: a variant with the glyph on a child `TextLabel`, which a parent gradient cannot touch, was equally blank.

### The change

`UITheme.styleClose` stops setting `Text` and draws the X as **two rotated `Frame`s**. Not a glyph, so it cannot depend on a font or a Roblox version again.

- Bars sized **relative to the button**, so the same code is correct at `UITheme`'s 30px and `UIStyle`'s 34px.
- **Idempotent:** any previously created bars are cleared first, so a second `styleClose` call cannot stack them.
- Bars must not intercept input — the button itself stays the click target.
- Colour stays white against the red fill, matching today's intent.

### Blast radius

`UITheme.styleClose` has **7 call sites covering 8 panels**, all of which inherit the fix with no per-panel edits: `RebirthClient`, `QuestClient` (Goals), `DailyRewardClient`, `FusionClient`, `IndexClient`, `MerchantClient`, and `ClientMain` — the last is one call site in a loop that styles **two** panels, Shop and Sell.

**9 panels in total** are fixed once `UIStyle` is included.

`SeasonClient` goes through **`UIStyle.styleClose`** — the collaborator's separate module, carrying its own copy of the same `"\u{2715}"` bug. The user approved fixing it too, as a self-contained one-function change. It gets its own copy of the bar-drawing rather than a cross-module dependency, because making the collaborator's module depend on ours is an architectural decision that needs their agreement, not a bug fix.

⚠️ `IndexClient:244-245` sets `closeBtn.ZIndex = 18` *after* `styleClose` because `styleClose` forces ZIndex 6. The new bars must sit above the button at whatever ZIndex the caller later chooses — derive their ZIndex from the button's at draw time, and accept that a caller raising the button afterwards is an existing pattern that must keep working.

---

## Part 2 — Brainrots in the sell list

`buildSellList` in `ClientMain` builds one `UITheme.accentCard` row per distinct unplaced brainrot. The row's 56px icon tile holds a sunburst backdrop plus a flat 34px circle coloured by rarity.

### The change

Replace the flat circle with a real 3D model via **`BrainrotThumb.add(icon, name, opts)`** — the same shared module the backpack grid and the catch reveal already use. No new machinery.

- The sunburst backdrop tile stays; only the circle is replaced.
- **The tier colour moves to the icon tile's border.** Today the circle is the row's only rarity cue, so replacing it would lose the tier read entirely. Putting rarity on the border is exactly what the backpack grid does, which also makes the two views consistent.
- Row height, layout, ordering, counts, prices and the sell buttons are untouched.

### Why this is cheap

`BrainrotThumb.master(name)` caches one stripped master per name and hands out clones, and the sell list only ever shows distinct *names* (it groups duplicates by name with an `×N` count), so the viewport count is bounded by the number of distinct unplaced brainrots — far below the 58-viewport backpack grid that measured a ~2% FPS cost.

---

## Failure modes

| Failure | Handling |
|---|---|
| **No model for that name** — `BrainrotThumb.master` returns nil. `Maxwell` is the only such entry of 151, but the roster changes. | Fall back to today's flat coloured circle. A missing model must never blank the row or break selling. |
| A row is rebuilt while its viewport exists | `buildSellList` already destroys and rebuilds all child Frames; the viewport dies with its row. No registry to leak. |
| `styleClose` called twice on one button | Bars cleared before redraw; cannot stack. |
| A caller raises the close button's ZIndex after styling (IndexClient does) | Bars derive ZIndex from the button at draw time and sit above it. |

## Verification

Both changes are **visual**, so both are verified by screenshot, not by reading properties back. Two hard-won constraints from the catch-reveal work apply directly:

- Properties written every frame cannot be read back by the tooling — irrelevant here since nothing animates, but the general rule stands: **look at it**.
- Studio must be in Edit mode to install and Play mode to see it.

Checks:
1. Open all **9** panels and confirm a visible X — the 8 on `UITheme` (Rebirth, Goals, Daily, Fusion, Index, Merchant, Shop, Sell) plus Season on `UIStyle`.
2. Confirm each X still *closes* its panel — the bars must not have stolen the click.
3. Open the Sell panel with a mixed inventory and confirm models render, one per distinct name, with the tier colour readable on the border.
4. Confirm the `Maxwell` fallback renders a coloured circle rather than an empty tile.
5. Zero console errors across the sweep.
