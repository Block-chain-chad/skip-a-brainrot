---
category: Controls
---

# TabBar

The segment control panels use to switch sections. The selected tab swaps to the
gold gradient and gains the `activeRing` (#FFD84D) outline outside its stroke.

```jsx
<TabBar
  value={tab}
  onSelect={setTab}
  tabs={[
    { id: 'brainrots', label: 'Brainrots' },
    { id: 'pets', label: 'Pets' },
    { id: 'keys', label: 'Keys' },
  ]}
/>
```

Tab labels are Title Case, unlike buttons, which are ALL CAPS. Keep the set to
about four — the game's widest panel is 960px and tabs sit inside its padding.
