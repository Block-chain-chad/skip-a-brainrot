---
category: Status
---

# ProgressTrack

The inset progress bar: a dark recessed track with an inner top shadow and a
gradient fill that animates over 400ms. Port of `UI.track` + `UI.setFill`.

`progress` is 0–1 and is clamped, matching the Luau builder.

```jsx
<ProgressTrack progress={0.62} fill="gold" height={22} />
```

`fill` takes any gradient name from the token set — the game uses `gold` for
level and pass XP, `green` for quest completion.

For a labelled bar, put the labels beside it and let the track flex:

```jsx
<div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
  <Label variant="meta">Level 12</Label>
  <ProgressTrack progress={0.45} style={{ flex: 1 }} />
</div>
```
