QuestRow from @skip-a-brainrot/ui. Use via `window.SkipABrainrotUI.QuestRow` (bundle loaded from the root `_ds_bundle.js`).

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

## Props

```ts
interface QuestRowProps {
  /** What the player has to do. */
  title: React.ReactNode;
  /** 0–1. Drives the inset bar. */
  progress: number;
  /** Progress caption, e.g. "4 / 10". Rendered in the unstroked meta step. */
  caption?: React.ReactNode;
  /** Art or icon at the left end. */
  art?: React.ReactNode;
  /** Usually a `Button` — or a `Ribbon` once the quest is done. */
  action?: React.ReactNode;
  className?: string;
  id?: string;
  style?: CSSProperties;
  children?: React.ReactNode;
}
```
