---
category: Controls
---

# Button

The kit's primary control — a port of `UI.button` in `UIKit/Builders.lua`. Gradient
fill, 3px near-black outline, hard offset shadow, and a white gloss strip across
the top. It lifts 2px on hover and sinks 2px on press.

## Variants

Pick the variant by what the action *does*, not by how it should look — the game
keeps these meanings consistent across every panel:

| Variant | Used for |
|---|---|
| `gold` | the primary purchase or open action (Buy, Open Egg, Unlock) |
| `green` | claiming something the player has already earned |
| `red` | destructive or sell actions |
| `blue` | equip / select |
| `purple` | fusion and other special mechanics |
| `goldSmall` | a tighter gold for chips and small plates |
| `tab` | an unselected segment — prefer `TabBar` |
| `disabled` | a requirement is unmet |

## Sizes

`sm` 44px, `md` 60px (default), `lg` 72px with a heavier type step.

## Disabled

A disabled button keeps its outline but drops the shadow and gloss, matching the
Luau builder — a dead control that still looks pressable reads as a bug.

```jsx
<Button variant="green">CLAIM</Button>
<Button variant="green" disabled>CLAIMED</Button>
<Button variant="disabled">NOT ENOUGH COINS</Button>
```

Labels are set in ALL CAPS throughout the game.
