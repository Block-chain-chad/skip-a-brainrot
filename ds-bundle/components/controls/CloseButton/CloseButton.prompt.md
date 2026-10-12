CloseButton from @skip-a-brainrot/ui. Use via `window.SkipABrainrotUI.CloseButton` (bundle loaded from the root `_ds_bundle.js`).

# CloseButton

The 74x66 red close control at the right end of every panel header. Port of
`UITheme.styleClose` / `closeGlyph`.

The X is drawn as two stroked bars rather than a text glyph, so it keeps its
weight at any size and never depends on a font loading.

```jsx
<CloseButton onClick={close} />
```

`Panel` and `PanelHeader` render this automatically when given `onClose` — reach
for it directly only when composing a header by hand.

## Props

```ts
interface CloseButtonProps {
  className?: string;
  id?: string;
  style?: CSSProperties;
  children?: React.ReactNode;
}
```
