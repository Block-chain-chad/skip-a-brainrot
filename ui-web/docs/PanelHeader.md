---
category: Surfaces
---

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
