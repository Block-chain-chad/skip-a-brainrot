RarityTile from @skip-a-brainrot/ui. Use via `window.SkipABrainrotUI.RarityTile` (bundle loaded from the root `_ds_bundle.js`).

# RarityTile

A backpack or index tile: the dark slot gradient with a 4px rarity-coloured inner
frame. Port of `UI.rarityFrame`, plus the two attention rings the game layers on
top of it.

## Rarity colours

`common` #C9CCC2 · `rare` #3FA9F5 · `epic` #A855F7 · `legend` #FFB200

These four are the *rarity* axis. Mutations (Golden, Glitched) are a **separate**
axis and are shown with the rainbow ring, not by changing the rarity colour.

## Rings

- `claimable` — the pulsing green ring, for a reward that can be collected now.
- `rainbow` — the cycling ring the game uses for mutated catches.

Both are decoration over the tile; they do not change its size.

```jsx
<RarityTile rarity="legend" size={118} rainbow>
  <Icon name="coin" size={70} />
</RarityTile>
```

The backpack grid uses `size={118}` with an 11px gap.

## Props

```ts
interface RarityTileProps {
  /** Colours the 4px inner frame. */
  rarity?: "common" | "rare" | "epic" | "legend";
  /** Square edge length in px. The backpack grid uses 118. */
  size?: number;
  /** Adds the pulsing green claimable ring. */
  claimable?: boolean;
  /** Adds the cycling rainbow ring used for mutations. */
  rainbow?: boolean;
  children?: React.ReactNode;
  className?: string;
  id?: string;
  style?: CSSProperties;
}
```
