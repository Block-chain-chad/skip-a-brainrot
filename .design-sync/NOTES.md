# design-sync notes — Skip a Brainrot

## What this syncs

`ui-web/` is a **web mirror** of the in-game UI kit, not a shipped web product.
The game is Roblox Luau; claude.ai/design only consumes React, so the kit was
ported so the design agent can mock panels on-brand before they are built in Studio.

Sources of truth, in order:

| Web file | Ported from |
|---|---|
| `ui-web/src/tokens.ts` | `game-src/place-full/ReplicatedStorage/Modules/UIKit/Tokens.lua` |
| `ui-web/src/styles.css` | `UIKit/Builders.lua` (the four composed effects) |
| `ui-web/src/components/*.tsx` | `UIKit/Builders.lua` + `UITheme.lua` |
| `ui-web/src/components/Icon.tsx` | `docs/design-handoff/ui-kit/design_handoff_game_ui/icons/*.svg` (generated) |
| `ui-web/src/fonts/` | Fredoka One + Nunito, the families `game-ui-reference.html` uses |

## Build gotchas

- **CSS changes need a FULL `package-build.mjs` run.** `lib/preview-rebuild.mjs`
  rebuilds preview JS only — it does **not** refresh `_ds_bundle.css`, so a
  stylesheet edit silently doesn't appear in the recapture. Cost one confusing
  round; check with `grep <new-selector> ds-bundle/_ds_bundle.css`.
- **`src/styles.css` must NOT `@import './fonts.css'`.** The converter copies the
  font sheet to `fonts/fonts.css` and imports it from the root `styles.css`, but
  copies `styles.css` verbatim as `_ds_bundle.css` — so a source-level import
  resolves to a nonexistent `ds-bundle/fonts.css` and fails `[CSS_IMPORT_MISSING]`.
  `src/index.css` exists for direct package consumers and pulls in both.
- **Never name Roblox-only fonts in the web stack.** `'Gotham Bold'` in the
  font-family list fires `[FONT_MISSING]` — nothing can ship it, and it resolves
  only on a machine that happens to have it licensed. Roblox renders GothamBold
  engine-side regardless.
- **`react-dom@18` is required** for `_vendor/` (the preview cards load React from
  there). React 19 dropped the UMD builds the converter reads.
- **Playwright ↔ chromium pinning on this machine:** cached builds are
  `chromium-1208` and `chromium-1234`. Use **playwright 1.62.0** (pins 1234) or
  1.58.0 (pins 1208). Anything else fails `Executable doesn't exist`.
- **Windows EPERM on `rm ds-bundle`** hit once at the converter's clean step.
  `rm -rf ds-bundle` from the shell and re-run; it has not recurred.
- **`title` collides with `HTMLAttributes`.** Any component taking a `title` prop
  needs `Omit<HTMLAttributes<…>, 'title'>` or `tsc` errors TS2430.

## Design findings (from the grading loop)

- **Dark ink and the outline stroke cannot coexist.** The stroke is near-black, so
  around near-black text it merges with the fill and closes the glyphs into a
  smear. `Label` grew `on="light"`, which switches to dark ink **and** drops the
  stroke together. Caught only by looking at the render — every numeric check passed.
- **Rings animate the gradient, not the geometry.** `UI.rainbowRing` tweens
  `UIGradient.Rotation`. Animating `transform: rotate()` instead spins the rounded
  square itself and throws its corners off-axis. The CSS uses an `@property`
  angle in the conic gradient so the ring stays put.
- **Icon SVGs all declare `id="a"` / `id="b"`.** Inlining two on one page makes the
  second one's `url(#a)` resolve to the first one's gradient. `scripts/gen-icons.mjs`
  namespaces every id per icon — do not hand-edit `Icon.tsx`, re-run the script.
- Icon art carries the **older `#16170F` outline**, not `Tokens.lua`'s current
  `#202020`. Deliberate: the SVGs predate the 2026-08-04 restyle and the game
  ships them as they are.

## Known render warns

None outstanding. The 12 `[GRID_OVERFLOW]` warns from the first full validate were
resolved with `cardMode: "column"` in `cfg.overrides` and do not recur.

## Re-sync risks

- **The mirror does not track the Luau automatically.** If `Tokens.lua`,
  `Builders.lua` or `UITheme.lua` change in-game, `ui-web/` keeps the old values
  until someone ports the change. Before a re-sync, diff those three files against
  what `tokens.ts` and `styles.css` claim. This is the single biggest staleness risk.
- `Icon.tsx` is generated. Re-run
  `node scripts/gen-icons.mjs ../docs/design-handoff/ui-kit/design_handoff_game_ui/icons src/components/Icon.tsx`
  after any SVG edit, then rebuild.
- Fonts were fetched from Google Fonts once; `src/fonts/` and `src/fonts.css` are
  committed, so re-syncs need no network for them.
- `UIStyle.lua` (643 lines: plate, sticker, stickerBadge, popIn/popOut) and
  `UITheme`'s candy* family are **not** mirrored — they are older/parallel style
  layers. If a panel starts using them again, they need porting.
- Only the **current** style is mirrored. The legacy cream palette that the
  2026-08-04 guide replaced survives in `tokens.ts` only as the `cream` alias,
  pointing at the window gray exactly as the Luau does.
