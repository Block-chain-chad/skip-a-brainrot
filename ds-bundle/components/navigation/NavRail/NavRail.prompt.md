NavRail from @skip-a-brainrot/ui. Use via `window.SkipABrainrotUI.NavRail` (bundle loaded from the root `_ds_bundle.js`).

# NavRail

The HUD's destination rail — two columns of three, on the **left** edge of the
1350x775 canvas.

The geometry is pixel-adjudicated and load-bearing: `railItem` 106 wide,
`railGap` 6, `railInset` 10, so two columns end at x=228. A 960px panel centred on
the canvas starts at x=195 — which is why no panel goes wider than 960.

```jsx
<NavRail rows={3}>
  <NavRailItem icon="shops" label="Shops" />
  <NavRailItem icon="bag" label="Bag" badge={3} />
  <NavRailItem icon="index" label="Index" />
  <NavRailItem icon="pass" label="Pass" active />
</NavRail>
```

`rows` sets how many items stack before wrapping into the next column.

## Props

```ts
interface NavRailProps {
  /** How many items stack vertically before wrapping into the next column. */
  rows?: number;
  /** `NavRailItem` children. */
  children?: React.ReactNode;
  className?: string;
  id?: string;
  style?: CSSProperties;
}
```
