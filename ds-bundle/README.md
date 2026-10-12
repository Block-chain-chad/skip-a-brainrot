# Building with the Skip a Brainrot HUD kit

This is the web mirror of a **Roblox game's** HUD (`ReplicatedStorage.Modules.UIKit`).
Designs built with it should look like the game: chunky cartoon panels, heavy
near-black outlines, hard offset shadows, stroked display type.

## Setup

**No provider or theme wrapper.** Components are plain elements styled by a global
stylesheet — import it once at the root and everything works:

```jsx
import '@skip-a-brainrot/ui/styles.css'
```

Nothing reads from React context. A component rendered anywhere is fully styled.

## The styling idiom: CSS custom properties

This system has **no utility classes and no style props**. You style your own
layout glue with `var(--sb-*)` tokens, and let components carry their own look.
Never invent a token name — if it isn't below, it doesn't exist.

**Colour** — `--sb-outline` (#202020, every stroke) · `--sb-white` ·
`--sb-text-on-window` (dark ink for the light panel) · `--sb-text-muted` ·
`--sb-text-accent` · `--sb-panel-top` / `--sb-panel-bottom` ·
`--sb-row-top` / `--sb-row-bottom` · `--sb-slot-top` / `--sb-slot-bottom` ·
`--sb-header-top` / `--sb-header-bottom` · `--sb-claim-ring` · `--sb-active-ring` ·
`--sb-active-glow` · `--sb-rarity-common` / `-rare` / `-epic` / `-legend` · `--sb-scrim`

**Gradients** (all vertical, top → bottom) — `--sb-grad-gold`, `-gold-small`,
`-green`, `-red`, `-blue`, `-purple`, `-gem`, `-panel`, `-sub-panel`, `-row`,
`-slot`, `-tab`, `-track`, `-header`, `-window`, `-free-card`, `-pass-card`,
`-disabled`, `-knob`, `-lock-badge`

**Geometry** — `--sb-stroke-panel` (4px) / `-control` (3px) / `-inner` (2px) ·
`--sb-radius-panel` (8) / `-control` (12) / `-slot` (8) / `-chip` (10) / `-pill` ·
`--sb-shadow-panel` (6) / `-control` (5) / `-chip` (4) ·
`--sb-pad-panel` (16) · `--sb-gap` (12) · `--sb-gap-tight` (8) · `--sb-grid-gap` (11)

**Type** — `--sb-font-display` (Fredoka One) · `--sb-font-ui` (Nunito)

## Rules that are load-bearing

- **One red surface per panel** — the header. Red anywhere else inside a window
  breaks the read that makes it a title bar. Use the dark row/slot gradients for
  interior structure.
- **Button labels are ALL CAPS.** Tab labels are Title Case.
- **`Label variant="meta"` is the only unstroked type step.** Any sentence longer
  than a few words uses it — stroked text at paragraph length is unreadable.
- **Text on the light window needs `<Label on="light">`.** That switches to dark
  ink and drops the stroke together. Setting a dark colour while leaving the
  stroke on merges the two into an unreadable smear — the stroke is near-black.
- **Panels are fixed-width** on a 1350x775 canvas: 700 Settings, 800 Daily,
  860 Goals, 940 Index/Eggs, 960 Pass/Backpack. Nothing goes wider than 960 — the
  nav rail owns the left edge out to x=228.
- **Nav-rail icons have no plate.** The active state is a radial gold glow, not a
  ring or a button background.
- **Rarity and mutation are different axes.** The four rarity colours are the
  frame; mutations show as the rainbow ring. Never recolour a rarity frame to mean
  "mutated".

## Where the truth lives

- `_ds/<folder>/styles.css` and its imports — every token above, with the Luau
  source each traces to in comments.
- `components/<group>/<Name>/<Name>.prompt.md` — per-component usage, variant
  meanings, and the composition patterns the game actually uses.
- Read those before styling. They beat any summary here.

## An idiomatic build

Library components for the controls; tokens for your own layout:

```jsx
<Panel title="Season Pass" icon="pass" width={960} onClose={close}>
  <TabBar value={tab} onSelect={setTab}
          tabs={[{ id: 'free', label: 'Free' }, { id: 'pass', label: 'Pass' }]} />

  <div style={{ display: 'flex', gap: 'var(--sb-grid-gap)', paddingTop: 18 }}>
    <RewardCard tier={6} track="free" label="250 Coins" claimed>
      <Icon name="coin" />
    </RewardCard>
    <RewardCard tier={7} track="pass" label="Golden Crate" claimable>
      <Icon name="eggs" />
    </RewardCard>
  </div>
</Panel>
```

# SkipABrainrotUI (@skip-a-brainrot/ui@1.0.0)

This design system is the published @skip-a-brainrot/ui React library, bundled as a single
browser global. All 21 components are the real upstream code.

## Where things are

- `_ds_bundle.js` — the whole-DS bundle at the project root; loads every component to `window.SkipABrainrotUI`. First line is a `/* @ds-bundle: … */` metadata header.
- `styles.css` — the single stylesheet entry: it `@import`s the tokens, fonts, and component styles (`_ds_bundle.css`). Link this one file.
- `components/<group>/<Name>/<Name>.prompt.md` (example JSX + variants), `<Name>.d.ts` (types), `<Name>.html` (variant grid).
- `tokens/*.css` — CSS custom properties, names verbatim from upstream.
- `fonts/` — `@font-face` files + `fonts.css` (when the package ships fonts).
- `guidelines/` — the design system's own usage guidance (21 doc(s), see `guidelines/index.md`). Read these before composing larger layouts.

For a specific component, `read_file("components/<group>/<Name>/<Name>.prompt.md")`.

## Loading

Add these two lines to your page once (React must be on the page first):

```html
<link rel="stylesheet" href="styles.css">
<script src="_ds_bundle.js"></script>
```

Components are then available at `window.SkipABrainrotUI.*`. Mount into a dedicated child node (e.g. `<div id="ds-root">`), not the host page's own React root, so the two trees don't collide:

```jsx
const { AccentCard } = window.SkipABrainrotUI;
ReactDOM.createRoot(document.getElementById('ds-root')).render(<AccentCard />);
```

## Tokens

79 CSS custom properties from @skip-a-brainrot/ui. Names are
preserved verbatim from upstream. They are declared inside `_ds_bundle.css` (this DS ships one compiled stylesheet rather than separate token files).

- **color** (6): `--sb-text-muted`, `--sb-text-accent`, `--sb-text-on-window`, …
- **spacing** (5): `--sb-pad-panel`, `--sb-gap`, `--sb-gap-tight`, …
- **typography** (2): `--sb-font-display`, `--sb-font-ui`
- **radius** (7): `--sb-radius-panel`, `--sb-radius-control`, `--sb-radius-inner`, …
- **shadow** (3): `--sb-shadow-panel`, `--sb-shadow-control`, `--sb-shadow-chip`
- **other** (56): `--sb-outline`, `--sb-keyline`, `--sb-panel-top`, …

## Components

### surfaces
- `AccentCard` — A card whose border is one accent colour and whose interior is a pale tint of
- `Panel` — The game's window: light gray vertical gradient, 4px outline, white inner
- `PanelHeader` — The single red header bar. The 2026-08-04 guide allows exactly ONE per panel 
- `Surface` — The base card surface every other component is built on: vertical gradient,

### content
- `ArtSlot` — The square art well a brainrot render, pet or reward image sits in.
- `CurrencyPill` — The 54px currency chip in the HUD's top strip: dark row gradient, pill radius,
- `Icon` — Renders one of the kit's icons as inline SVG.
- `Label` — Display text with the heavy outline stroke.
- `Medallion` — The small round token that carries a tier number, a day index or a count.
- `QuestRow` — An 88px goal row: art, title over an inset progress bar, and an action at the
- `RarityTile` — A backpack / index tile: dark slot surface with a 4px rarity-coloured inner
- `RewardCard` — One rung of the Season Pass ladder: a 178x186 card with its tier medallion

### status
- `Badge` — The red notification pill that rides on a nav-rail item or a tab.
- `ProgressTrack` — The inset progress bar: a dark recessed track with an inner top shadow and a
- `Ribbon` — The small pill tag that sits on a card corner.
- `Toast` — The transient message that flies into the top of the HUD  a reward landing,

### controls
- `Button` — The kit's primary control: gradient fill, 3px outline, hard offset shadow, and
- `CloseButton` — The 74x66 red close control that sits at the right end of every panel header.
- `TabBar` — The segment control panels use to switch sections. The selected tab swaps to

### navigation
- `NavRail` — The HUD's destination rail  two columns of three on the LEFT edge of the
- `NavRailItem` — One nav-rail destination: a bare 66px icon floating in a 106px column with its
