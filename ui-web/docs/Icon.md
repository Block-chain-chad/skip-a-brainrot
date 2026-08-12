---
category: Content
---

# Icon

The game's HUD icon set, inlined as SVG.

`bag` · `coin` · `daily` · `eggs` · `gem` · `goals` · `index` · `pass` · `plot` ·
`settings` · `shops` · `skip`

This is the same art whose 512px PNG exports are the live `rbxassetid` icons in
`Tokens.lua`, so an icon here matches what the game renders.

```jsx
<Icon name="coin" size={42} />
```

Without `size` the icon fills its container. `iconNames` exports the full list if
you need to enumerate them.

Note these icons carry the older #16170F outline rather than the current #202020
— they predate the 2026-08-04 restyle, and the game ships them as they are.
