---
category: Content
---

# Medallion

The small round token that carries a tier number, a day index or a count. Port of
`UITheme.medallion`.

Unlike the buttons, it uses a half-transparent white hairline and a gloss cap
rather than the heavy outline — it is a marker, not a control.

```jsx
<Medallion size={58}>7</Medallion>
<Medallion color="#3FA9F5">2</Medallion>
```

`RewardCard` renders its own tier medallion; use this one for day cards, streak
counters and standalone markers.
