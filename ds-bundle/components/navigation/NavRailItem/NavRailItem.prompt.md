NavRailItem from @skip-a-brainrot/ui. Use via `window.SkipABrainrotUI.NavRailItem` (bundle loaded from the root `_ds_bundle.js`).

# NavRailItem

One rail destination: a bare 66px icon floating in a 106px column with its label
underneath in the `railLabel` step (20px, 4px stroke).

## No plate

The v2 rail has **no button plate**. v1's 98x88 gold plate was dropped, and the
active state became an 88px radial gold glow (`activeGlow` #FFE87A at 75%) rather
than a stroked ring. `Tokens.lua` flags its own shipped v1 numbers as stale — the
values here follow the v2 spec.

Do not add a background, border or plate behind a rail icon.

```jsx
<NavRailItem icon="pass" label="Pass" active badge="9+" />
```

Exactly one item should be `active` at a time.

## Props

```ts
interface NavRailItemProps {
  /** Icon for this destination. */
  icon: "bag" | "coin" | "daily" | "eggs" | "gem" | "goals" | "index" | "pass" | "plot" | "settings" | "shops" | "skip";
  /** Label under the icon, set in the railLabel step (20px, 4px stroke). */
  label: string;
  /** Lights the 88px radial gold glow behind the icon. */
  active?: boolean;
  /** Renders a notification pill on the icon's top-right. */
  badge?: string | number;
  className?: string;
  id?: string;
  style?: CSSProperties;
}
```
