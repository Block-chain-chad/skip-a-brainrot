Surface from @skip-a-brainrot/ui. Use via `window.SkipABrainrotUI.Surface` (bundle loaded from the root `_ds_bundle.js`).

# Surface

The base card every other component is built on — a port of `UI.surface`. It
composes the four effects the whole kit is made of: a vertical gradient, a thick
near-black outer stroke, optionally a hard offset shadow, and optionally the
top gloss strip with its bottom shade.

## Kinds

| Kind | Gradient | Used for |
|---|---|---|
| `panel` | #D6D6D6 → #A9A9A9 | the window body |
| `subPanel` | #C4C4C4 → #9C9C9C | a section inside a window |
| `row` | #4A4A4A → #363636 | list rows |
| `slot` | #4A4A4A → #363636 | inventory slots (8px radius) |
| `tab` | #BEBEBE → #9C9C9C | unselected segments |
| `track` | #2E2E2E → #3A3A3A | recessed bar backgrounds |

Light text sits on `row`/`slot`/`track`; dark `--sb-text-on-window` sits on
`panel`/`subPanel`/`tab`.

```jsx
<Surface kind="subPanel" shadowed keyline style={{ width: 320, height: 120 }} />
```

Reach for `Panel` instead when you want the full window with its header.

## Props

```ts
interface SurfaceProps {
  /** Which gradient family this surface uses. */
  kind?: "slot" | "tab" | "panel" | "subPanel" | "row" | "track";
  /** Adds the hard offset shadow — a copy of the shape pushed down Y in outline colour. */
  shadowed?: boolean;
  /** Adds the guide's 2px white inner keyline just under the outer stroke. */
  keyline?: boolean;
  /** Adds the top gloss strip and bottom shade. */
  gloss?: boolean;
  children?: React.ReactNode;
  className?: string;
  id?: string;
  style?: CSSProperties;
}
```
