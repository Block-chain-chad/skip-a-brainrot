PanelHeader from @skip-a-brainrot/ui. Use via `window.SkipABrainrotUI.PanelHeader` (bundle loaded from the root `_ds_bundle.js`).

# PanelHeader

The 92px red header bar — the only red surface a panel is allowed. It carries an
optional 64px icon, the title in the `panelTitle` step, and the close control.

`Panel` renders this for you when you pass `title`. Use `PanelHeader` directly
only when you are composing a window out of `Surface` by hand.

```jsx
<Surface kind="panel" shadowed keyline style={{ width: 560, overflow: 'hidden' }}>
  <PanelHeader icon="pass" title="Season Pass" onClose={close} />
</Surface>
```

The parent needs `overflow: hidden` or the header's square top corners will
overhang the panel's 8px radius.

## Props

```ts
interface PanelHeaderProps {
  /** Header copy, set in the panelTitle step. */
  title: React.ReactNode;
  /** Optional 64px icon at the left end. */
  icon?: "bag" | "coin" | "daily" | "eggs" | "gem" | "goals" | "index" | "pass" | "plot" | "settings" | "shops" | "skip";
  /** Renders the close control and wires it. Omit for a header with no close. */
  onClose?: () => void;
  className?: string;
  id?: string;
  style?: CSSProperties;
  children?: React.ReactNode;
}
```
