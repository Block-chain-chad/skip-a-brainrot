---
category: Content
---

# ArtSlot

The square art well a brainrot render, pet or reward image sits in. Port of
`UI.artSlot`.

An **empty string** `src` is treated as "no art" and shows the placeholder fill —
the kit deviation the Luau builder documents, because an un-uploaded icon
rendering as an invisible slot reads as a broken panel.

```jsx
<ArtSlot size={104} src={brainrot.image} alt={brainrot.name} />
<ArtSlot size={104}><Icon name="eggs" size={68} /></ArtSlot>
```

Children render only when there is no `src`, which makes an `Icon` a natural
stand-in while art is pending.

Use `RarityTile` instead when the slot needs a rarity frame.
