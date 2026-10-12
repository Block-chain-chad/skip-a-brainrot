Label from @skip-a-brainrot/ui. Use via `window.SkipABrainrotUI.Label` (bundle loaded from the root `_ds_bundle.js`).

# Label

Display text with the heavy outline stroke. Port of `UI.label`.

## The ramp

| Variant | Size / stroke | Used for |
|---|---|---|
| `panelTitle` | 32 / 3 | the header title |
| `buttonL` | 24 / 2.5 | large button labels |
| `buttonM` | 20 / 2 | standard button labels |
| `value` | 22 / 2 | currency and numeric values |
| `cardLabel` | 17 / 2 | card and tile names |
| `chip` | 14 / 1.5 | small tags and counts |
| `railLabel` | 20 / 4 | nav-rail labels |
| `meta` | 14 / 0 | body copy — **the only unstroked step** |

Every stroked step is Fredoka One; `meta` is Nunito. Use `meta` for any sentence
longer than a few words — stroked text at paragraph length is unreadable.

## Which surface it sits on

`on` is the important prop. It defaults to `dark` — white text with the stroke,
correct on `row`/`slot`/`track` and over the world.

On the light gray window, tabs, or a pale card, pass `on="light"`:

```jsx
<Label variant="cardLabel" on="light">Golden Crate</Label>
```

That switches to dark ink **and drops the stroke**. Both halves matter: the stroke
is near-black, so around near-black ink it merges with the fill and closes the
glyphs into a smear. Never set a dark colour while leaving the stroke on.

`color` overrides the colour `on` picked (for gold `--sb-text-accent`, say)
without touching the stroke.

## Props

```ts
interface LabelProps {
  /** Which step of the type ramp to render. */
  variant?: "value" | "panelTitle" | "buttonL" | "buttonM" | "cardLabel" | "chip" | "railLabel" | "meta";
  /** Which surface the label sits on. `dark` (default) — white text with the outline stroke, for `row`/`slot`/`track` surface */
  on?: "dark" | "light";
  /** Overrides the colour picked by `on`. Does not change the stroke. */
  color?: string;
  children?: React.ReactNode;
  className?: string;
  id?: string;
  style?: CSSProperties;
}
```
