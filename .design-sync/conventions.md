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
