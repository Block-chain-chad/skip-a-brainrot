---
category: Surfaces
---

# AccentCard

A card whose border is one accent colour and whose interior is a pale tint of that
same hue — the "one accent per card" read the panels are built around. Port of
`UITheme.accentCard`.

The tint comes from `accentFill()`, which keeps the hue, collapses saturation and
raises value, so dark body text stays readable on any accent.

```jsx
<AccentCard accent="#3FA9F5" style={{ width: 176, height: 150 }}>
  <Icon name="eggs" size={54} />
  <Label variant="cardLabel" color="var(--sb-text-on-window)">Rare</Label>
</AccentCard>
```

Note the radial rays these cards used to sit on are retired — `UITheme.sunburst`
now paints a flat accent wash, so this component is where per-card colour lives.
Content is stacked in a column with an 8px gap and 12px padding.
