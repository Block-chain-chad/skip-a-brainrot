Icon from @skip-a-brainrot/ui. Use via `window.SkipABrainrotUI.Icon` (bundle loaded from the root `_ds_bundle.js`).

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

## Props

```ts
interface IconProps {
  /** Which icon to render. */
  name: "bag" | "coin" | "daily" | "eggs" | "gem" | "goals" | "index" | "pass" | "plot" | "settings" | "shops" | "skip";
  /** Width and height in px. Defaults to filling its container. */
  size?: number;
  className?: string;
  id?: string;
  style?: CSSProperties;
  children?: React.ReactNode;
  /** Allows getting a ref to the component instance. Once the component unmounts, React will set `ref.current` to `null` (or  */
  ref?: string | ((instance: SVGSVGElement) => void | DO_NOT_USE_OR_YOU_WILL_BE_FIRED_CALLBACK_REF_RETURN_VALUES[keyof DO_NOT_USE_OR_YOU_WILL_BE_FIRED_CALLBACK_REF_RETURN_VALUES]) | RefObject<SVGSVGElement>;
}
```
