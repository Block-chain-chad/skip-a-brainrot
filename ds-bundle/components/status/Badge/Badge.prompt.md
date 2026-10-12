Badge from @skip-a-brainrot/ui. Use via `window.SkipABrainrotUI.Badge` (bundle loaded from the root `_ds_bundle.js`).

# Badge

The red notification pill that rides on a nav-rail item or a tab. Port of
`UI.badge` — pill radius, red gradient, 3.5px outline, 30px minimum so a single
digit stays circular.

`value` is coerced to a string, so counts and overflow labels both work:

```jsx
<Badge value={3} />
<Badge value="9+" />
```

`NavRailItem` positions one for you via its `badge` prop; place it yourself only
when badging something else.

## Props

```ts
interface BadgeProps {
  /** Coerced to a string, so `3` and `"9+"` both work. */
  value: string | number;
  className?: string;
  id?: string;
  style?: CSSProperties;
  children?: React.ReactNode;
}
```
