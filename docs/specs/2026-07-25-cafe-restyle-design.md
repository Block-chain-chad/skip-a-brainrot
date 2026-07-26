# Cafe Restyle — Design

**Date:** 2026-07-25
**Status:** Approved (user said "go" 2026-07-25)
**Scope:** Art direction only. Zero gameplay change.

## Goal

Make "Skip a Brainrot" read as **bubbly / cozy-cartoon**, matching the look and feel of
the Roblox game **[☕] Own a Cafe** (universeId `8935993972`, placeId `131906518201863`).

The user's words: *"I like where the cabin is, the plots, the dock. But if you could just
change the materials and make it all bubbly vibes."*

## Non-goals

- **Nothing moves.** Cabin, plots, dock, shops, throw zone, trading island all keep their
  exact positions. This is explicitly not a layout change.
- **No gameplay, economy, data-schema or remote changes.** Every button keeps its current
  behaviour. If a change alters what a control *does*, it is out of scope.
- Not a world rebuild. Terrain geometry (the heightmap valley, lake, mountains) is kept;
  only its *colours and materials* are in play.

## Reference

Own a Cafe: launched 2025-10-13, ~1,891 concurrent players, 937k visits, 10.6k favourites,
updated 2026-07-26. Actively maintained, so it is a safe style to chase.

### Extracted style recipe

Read from two in-game screenshots supplied by the user (the "Hire Friends" panel and an
NPC dialogue prompt):

| Element | Treatment |
|---|---|
| Panel body | Cream, **light** — approx `rgb(247,235,216)` |
| Header | Solid warm-brown bar, approx `rgb(192,117,46)`, faint coffee-bean pattern |
| Outline | Thick **dark brown** approx `rgb(62,34,19)` on every shape *and* every glyph. Never black. |
| Corner radius | Generous, applied everywhere |
| Card | Cream `rgb(245,220,192)`, dark-brown outline, rounded |
| Buttons | Colour carries meaning: green confirm `rgb(79,194,79)`, gold primary CTA `rgb(245,193,58)` with diagonal stripes, pink close `rgb(240,71,155)` |
| Text | Rounded bubbly font, always stroked; italic for flavour lines |
| Header icon | Chunky icon left of the title |
| World | Flat saturated green, no texture detail, chunky low-poly conifers, soft shadows |

Colour values are eyeballed from screenshots and will be tuned against the real thing
during Stage 5.

## Current state

### The lucky part

`ReplicatedStorage.Modules.UITheme` already implements most of this recipe under
`UITheme.Camp`: heavy outlines on shapes and glyphs, one accent colour per card carried
through border + title + sunburst, chunky overhanging header, two-tone gradients, fat
pills. Twelve ScreenGuis were already converted onto it on 2026-07-24 (`ClientMain`,
`SideRail`, `SeasonClient`, `DailyRewardClient`, `QuestClient`, `IndexClient`,
`RebirthClient`, `FusionClient`, `OfflineEarningsClient`, `ToastClient`,
`RareCatchClient`, `LuckHUDClient`).

So the cafe conversion is a **token and helper swap inside one module**, not a rewrite.
Four deltas:

1. Panels are dark → make them cream
2. Ink is black → make it dark brown
3. Ribbon headers → solid header bar
4. Sunbursts behind icons → removed

### Known current values

- Terrain `SetMaterialColor`: Grass `(94,110,56)`, LeafyGrass `(74,101,54)`,
  Rock `(138,136,132)`, Ground `(120,100,74)`, Snow `(236,240,245)`, Sand `(198,186,158)`
- Water: `WaterColor(10,92,118)`, Transparency `0.13`, Reflectance `0.22`
- Lighting: ClockTime ~14, Brightness `2.1`, ExposureCompensation `0`,
  ColorShift_Top `(255,244,224)`, OutdoorAmbient `(150,156,148)`, Ambient `(80,100,120)`,
  Atmosphere Density `0.05`, Haze `0.5`, GlobalShadows on, ShadowSoftness `0.2`,
  GeographicLatitude `41`; Bloom + SunRays + DepthOfField + ColorCorrection present
- Trees: `TreeCandidateA` clones — ~618 in `GameWorld.Forest`, more in
  `GameWorld.MountainForest` and `GameWorld.Scenery`, plus 5 per plot camp
- Dock: `GameWorld.SkipDock`, WoodPlanks warm oak `(150,110,68)`, deck top y3.4

### Known blockers

- **Two competing style systems.** `ReplicatedStorage.Modules.UIStyle` (the collaborator's,
  newer) and `UITheme.Camp` (ours) both exist. `SideRail` has already been moved onto
  `UIStyle`. One must be chosen as canonical before Stage 5, or the restyle will be undone
  by whoever edits next. **This is a conversation with the collaborator, not a code fix.**
- **Studio MCP is not connected in this session.** Nothing can be changed until the user
  toggles Assistant settings → MCP Servers → "Enable Studio as MCP server" off then on.
- **Stages 3 and 4 touch shared ground** — the throw area and terrain are the
  collaborator's section. They need a heads-up before either runs.

## The five stages

Each stage is independently shippable, verified in play, and revertible. The user reviews
after each and decides whether to continue.

### Stage 1 — Low-poly trees

Replace ~618 realistic pines with chunky low-poly cartoon trees. This carries more of the
"bubbly" read than anything else on the list.

- **Source:** free Creator Store low-poly nature pack (user's choice). Vet each candidate
  for part count before committing — 618 trees times a heavy model will destroy framerate.
  Target is a handful of parts per tree, `CanCollide = false`, no scripts, no meshes with
  huge texture memory.
- **Method:** swap the source model, re-run the existing raycast scatter (it already
  handles surface-seating, slope rejection, and water avoidance).
- **Touches:** `GameWorld.Forest`, `GameWorld.MountainForest`, `GameWorld.Scenery`, and the
  5 pines per plot camp.
- **Verify:** tree count matches before/after; no tree floating or buried; framerate in
  play is not worse; no tree intersects the dock, shops or plots.
- **Rollback:** keep the old `TreeCandidateA` model in ServerStorage; re-run scatter with it.

### Stage 2 — Flat cartoon lighting

Cartoon lighting is **low contrast**: bright ambient fill, soft shadows, minimal haze.

- Raise `Ambient` and `OutdoorAmbient` so shadows lift toward mid-grey rather than black
- Reduce contrast; keep `Brightness` near current so the scene does not blow out
- Increase `ShadowSoftness`; keep `Atmosphere.Density` low (the far-peak visibility fix
  from 2026-07-23 must not regress)
- Retune `ColorCorrection` toward higher saturation, lower contrast
- **Verify:** far peaks still visible; dock and camp read clearly; no blown highlights
- **Rollback:** ~10 properties, captured before the change and restored verbatim

### Stage 3 — Parts to SmoothPlastic

Sweep world Parts to `SmoothPlastic` with a soft saturated colour map. This is what kills
the "realistic" read on the dock, plots, shops and props.

- Explicitly **excluded**: anything whose material is load-bearing for gameplay or reading
  (Neon accents, water, invisible barriers/hitboxes, ProximityPrompt parts)
- **Requires collaborator heads-up** — touches the shared throw area
- **Verify:** no collision or `CanQuery` change; throw still works from every dock spot;
  prompts still fire
- **Rollback:** snapshot `{instance, Material, Color}` for every part touched before writing

### Stage 4 — Flatten terrain tints

- Brighten and saturate the `SetMaterialColor` palette toward the flat cartoon greens seen
  in the reference
- Set `LeafyGrass`'s material colour **equal to** `Grass` so the two read as one flat green.
  Explicitly *not* `ReplaceMaterial` — no voxel is rewritten, so this stays a pure colour
  change and reverts by restoring one value.
- Evaluate turning terrain decoration off
- **Requires collaborator heads-up**
- **Verify:** lake shore still reads; the dock water-pier carve is untouched; no terrain
  geometry regenerated (colour-only operations — no `WriteVoxels`, `FillBlock`, or
  `ReplaceMaterial`)
- **Rollback:** restore the six recorded material colours

### Stage 5 — Cafe UI and font

- **Font:** build a proof board in Studio rendering real menu strings in candidate Roblox
  fonts (FredokaOne, Grandstander, LuckiestGuy, Nunito, Bangers) side by side; screenshot;
  user picks. Do not guess the font from marketing art.
- **Tokens:** swap `UITheme.Camp` values — dark panel to cream, black ink to dark brown
- **Helpers:** `M.ribbon` gains (or is joined by) a solid header-bar variant; `M.sunburst`
  calls are retired from card icons
- **Propagation:** the 12 already-converted ScreenGuis inherit the change
- **Verify:** every ScreenGui still initialises with no load errors; all rail tiles present;
  each panel opens and its buttons still fire their existing handlers
- **Rollback:** the token table is one commit; revert it

## Risks

- **`UIGradient` tints the parent's own text.** Already burned us once. Keep gradients on
  the button and put text in a child `TextLabel`. `UITheme.campButton` is *not yet audited*
  for this on its dark/locked states — Stage 5 must sweep it.
- **`ClipsDescendants` does not clip rotated descendants.** Relevant if any rotated
  decoration survives into the cafe style.
- **Collaborator collision.** `yeep1234` is often live in the same Studio session. Stages
  touching shared areas must be announced, and no stage should run while they are editing
  the same objects.
- **Nothing is committed to git.** All UI code lives only in Studio; `game-src/` mirrors
  just 11 gameplay files. A bad stage cannot be recovered with `git checkout` — hence the
  explicit per-stage snapshot requirement.

## Out of scope

- Publishing. The game is still private and the `Brainrot pack1` IP problem is unresolved.
- The idle/offline-earnings layer discussed earlier as an Own a Cafe mechanic. That is a
  gameplay feature, tracked separately.
