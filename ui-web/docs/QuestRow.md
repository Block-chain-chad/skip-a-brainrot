---
category: Content
---

# QuestRow

An 88px goal row: art, title over an inset progress bar, and an action at the
right end. This is the Goals panel's repeating unit.

```jsx
<QuestRow
  title="Catch 10 brainrots"
  progress={0.4}
  caption="4 / 10"
  art={<Icon name="skip" size={56} />}
  action={<Button variant="green" size="sm">CLAIM</Button>}
/>
```

The row renders its own `ProgressTrack` (green, 18px) — do not nest another.

Match the action to the state: `variant="disabled"` while incomplete, `green`
once claimable, and a `<Ribbon>DONE</Ribbon>` after claiming.
