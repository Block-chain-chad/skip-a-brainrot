Ribbon from @skip-a-brainrot/ui. Use via `window.SkipABrainrotUI.Ribbon` (bundle loaded from the root `_ds_bundle.js`).

# Ribbon

The small pill tag on a card corner. Port of `UI.ribbon`.

| Variant | Gradient | Means |
|---|---|---|
| `EQUIPPED` | green | currently equipped |
| `GRAND` | purple | the grand prize on a ladder |
| `NEW` | red | newly acquired, unseen |

The variant name is the default label, which is how the game uses it. Override
`children` for a related tag that should keep the same colour meaning
(`<Ribbon variant="GRAND">GRAND PRIZE</Ribbon>`).

Position it yourself over the card corner:

```jsx
<div style={{ position: 'relative' }}>
  <RarityTile rarity="legend" size={104}><Icon name="coin" size={62} /></RarityTile>
  <span style={{ position: 'absolute', bottom: -8, left: 10 }}>
    <Ribbon variant="EQUIPPED" />
  </span>
</div>
```

## Props

```ts
interface RibbonProps {
  /** Picks the gradient: EQUIPPED green, GRAND purple, NEW red. */
  variant?: "EQUIPPED" | "GRAND" | "NEW";
  /** Defaults to the variant name, which is how the game uses it. */
  children?: React.ReactNode;
  className?: string;
  id?: string;
  style?: CSSProperties;
}
```
