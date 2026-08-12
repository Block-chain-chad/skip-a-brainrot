---
category: Surfaces
---

# Panel

The game's window — a port of `UI.panel`. Light gray vertical gradient, 4px
outline, a 2px white inner keyline, and a hard offset shadow.

Pass `title` and it grows the red header bar; omit it and the panel is a bare
surface you fill yourself.

## The one-header rule

The 2026-08-04 style guide allows **exactly one red surface per panel** — the
header. That is what makes it read as a title bar against the gray body. Do not
add a second red element inside a panel; use the dark row/slot gradients for
interior structure instead.

## Widths

The game's panels are fixed-width on a 1350x775 canvas: Settings 700, Daily 800,
Goals 860, Index 940, Eggs 940, Pass 960, Backpack 960. A panel wider than ~960
collides with the nav rail, which occupies the left edge out to x=228.

```jsx
<Panel title="Goals" icon="goals" width={860} onClose={close}>
  <QuestRow title="Catch 10 brainrots" progress={0.4} caption="4 / 10" />
</Panel>
```

Body children are stacked in a column with a 12px gap and 16px padding. For grids
(backpack tiles, ladder rungs), wrap them in your own `display: grid` element.
