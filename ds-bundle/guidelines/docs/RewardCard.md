---
category: Content
---

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
