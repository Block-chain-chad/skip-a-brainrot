RewardCard from @skip-a-brainrot/ui. Use via `window.SkipABrainrotUI.RewardCard` (bundle loaded from the root `_ds_bundle.js`).

# RewardCard

One rung of the Season Pass ladder — a 178x186 card with its tier medallion
overhanging the top edge.

## Tracks

`free` uses the pale free-card gradient; `pass` uses the gold pass-card one. The
Pass panel shipped a 3-column ladder on 2026-08-08: tier, free reward, pass reward.

## States

- `claimable` — pulsing green ring, collectable now
- `claimed` — desaturated, ring dropped
- `locked` — dimmed behind a scrim, tier not reached

These are mutually exclusive in practice; a claimed card is never also claimable.

```jsx
<RewardCard tier={7} track="pass" label="Golden Crate" claimable>
  <Icon name="eggs" />
</RewardCard>
```

Give the row some top padding — the tier medallion overhangs the card by 14px.

## Props

```ts
interface RewardCardProps {
  /** Tier number in the medallion at the card's top edge. */
  tier: string | number;
  /** Reward name under the art. */
  label: React.ReactNode;
  /** `pass` uses the gold pass-card gradient; `free` uses the pale free-card one. */
  track?: "pass" | "free";
  /** Desaturates the card and drops the claim ring. */
  claimed?: boolean;
  /** Dims the card behind a scrim — the tier is not reached yet. */
  locked?: boolean;
  /** Pulsing green ring: this reward is claimable right now. */
  claimable?: boolean;
  /** The reward art — usually an `ArtSlot` or `Icon`. */
  children?: React.ReactNode;
  className?: string;
  id?: string;
  style?: CSSProperties;
}
```
