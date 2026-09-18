# Voxel Egg in Blender — Frost Elemental Pass

**Date:** 2026-08-15
**Status:** Pass A delivered (egg look + idle effects). Pass B (hatch animation) not started.
**Scratchpad:** `egg_build.py` — parameterised, re-runnable, `still` / `turntable` / `bare` modes.

## Goal

Recreate the voxel egg style from `voxel_egg.py` in Blender, add world-elemental effects,
and use Blender as the previz surface for the hatch animation. Nothing ships from Blender
directly — it is a design surface whose output is a **target** for Roblox work.

## Why Blender at all

The geometry pipeline already works better in Python-to-Luau (it emits real Parts with no
upload gate). Blender earns its place for two things only:

1. **It is a real renderer.** Motion and lighting can be judged offline, at ~1s/frame, with
   no Studio, no playtest, no Team Create collaborators, no owner publish step.
2. **It bakes textures**, which upload cleanly via `upload_image` — the one asset class that
   crosses into Roblox without a manual import.

Blender is *not* used for: mesh authoring (needs manual File > Import 3D), animation export
(AnimationIds must be published by the place owner), or UI.

## Decisions

### Geometry is a verbatim port, not a lookalike

`build()` reproduces `voxel_egg.py` exactly: 16 × 12 grid, `CELL = 5.30/16`, seam at
`int(16*0.44)`, profile `HALF * (1-t²)^(0.5 if t>0 else 0.36) * (1-0.14t)`, hash jitter
`±0.4` cells, 62% grey-patch chance, 2-wide seam teeth `(ix//2 + iz)%2`. This keeps the
Blender egg and the Roblox egg the same object, so look decisions transfer.

### Cap and cradle are separate objects from the start

Split on the same `seamOf()` cut the Luau uses. Costs nothing now and makes the pass-B hatch
animation free. Measured: cap 176 boxes / cradle 186 (362 total, vs ~357 documented).

### Display subdivides; the recipe does not

`build()` keeps Roblox's vertical column merge (Roblox pays per Part). `to_cells()` then
splits merged columns back into CELL-tall cubes **for rendering only**.

Reason: the original Python renderer faked Roblox's per-part shading by outlining every box
(`edge = col * 0.90`), and the note on that render says a flat fill "made v3 read far flatter
than the reference". Blender merged each column into one smooth strip and lost every seam.
Roblox shades each Part independently, so the cell seams *are* visible in-engine —
subdividing in Blender reproduces the true read. Adds `CELL_SHRINK = 0.988` plus a 0.010
bevel so each voxel catches the key.

### Pebbles are axis-aligned, not free-rotated

The Roblox recipe orients pebbles to the surface normal. Ported directly into Blender they
read as **tan sticky notes** — a free-rotated cube inside an otherwise perfectly grid-aligned
voxel body breaks the language and catches the key on one large flat face.

Changed to fully axis-aligned, sized ~0.9–1.3 cells, outer face landing at `r + 0.35` cells
so half the cube stays buried. Reads as an embedded nugget.

**This is a divergence from the Roblox build and should be ported back** — the same failure
is likely visible in-engine.

### Effects are made of cubes

Snow, shards, ice spikes and the frost ring are all cube geometry, never round sprites. Two
reasons: it stays in the game's art language, and **cubes are the only thing that can enter
the hatch ViewportFrame**, which draws BaseParts only.

### Structure beats scatter

First effects pass was scattered floating specks and read as dust. What made it read as frost
was **geometry erupting from the ground** — stepped, tapered ice spikes around the base,
taller nearer the egg. Floating particles say "dust"; ground geometry says the egg is *doing*
this.

Spike angles are **stratified** (`(i + jitter)/N * tau`), not uniformly random — uniform
sampling clumped them into a wall on one side. Spikes between camera and egg are damped by
`1 - 0.58 * max(0, -sin(ang))` so they frame the egg instead of eating its base.

## Portability

| Effect | World stall | Hatch ViewportFrame |
|---|---|---|
| Voxel shell + pebbles | Ships as-is (Parts) | Ships as-is (Parts) |
| Ice spikes (ground) | Ships as-is (Parts) | Ships as-is (Parts) |
| Frost ring plates | Ships as-is (Parts) | Ships as-is (Parts) |
| Drifting snow cubes | Parts, or ParticleEmitter | Parts only — must be moved by script |
| Emissive glow on snow/ice | Neon material | Neon material |
| Cold underglow | PointLight | **Does not port** — no Lights in viewports |
| Volumetric mist | ParticleEmitter approximation | **Does not port** |
| Cycles bounce light / AgX grade | **Does not port** | **Does not port** |

### Albedo ceiling

Blender authors at full world brightness. The hatch ViewportFrame clips anything over albedo
~205 to flat white, losing all face shading. **Multiply the palette by 0.724 before porting
to the viewport.** The world stall does not need this.

Frost palette authored: base `(206,227,241)`, greys `(160,186,206)/(178,200,217)/(146,172,195)`,
pebbles `(216,200,156)` / `(168,152,112)`.

## The full set — 10 eggs (`egg_set.py`)

Effects are **per egg**, not per world. World-level elemental effects separate Forest from
Tundra but leave the five eggs inside a world identical, which is the job the deleted
decorations used to do.

Each egg carries: palette (base / 3 greys / 2 pebble tones), a ground-growth kind, mote
colour and density, underglow colour and energy, mist colour and density, frost-ring colour.
Tier 1→5 scales aura intensity, so the ladder reads as rarity.

Ground growth is one stepped-column generator with different proportions:
`spike` (tapered), `thorn` (sharp), `tuft` (low clump), `reed` (thin tall), `root` (low wide),
`plate` (flat slab), `curtain` (tall thin sheet).

| Egg | Tier | Body | Growth | Aura |
|---|---|---|---|---|
| Mossy | 1 | moss green | tufts | soft green motes |
| Reedwater | 2 | teal | reeds | pale droplets |
| Bramble | 3 | warm brown | thorns | dim amber |
| Hollow | 4 | grey-lilac | ghost spikes | violet wisps |
| Heartwood | 5 | red-brown | roots | orange embers, strong glow |
| Frostcap | 1 | slate blue + white cap | ice spikes | light snow |
| Rimeplate | 2 | desaturated steel | flat plates | pale grey |
| Aurora | 3 | violet, green/magenta patches | green curtains | violet motes |
| Whiteout | 4 | near white | white spikes | heavy blizzard |
| Frostheart | 5 | deep saturated blue | tall ice spikes | blue, strongest glow |

### Two corrections this pass forced

**Tundra needed hue separation, not lightness separation.** Every Tundra name is a frost word,
so the first attempt gave five shades of the same pale blue — Frostcap, Rimeplate and Whiteout
were indistinguishable. Fixed by pushing them apart in hue (slate / steel / violet / white /
deep blue) and adding an optional `cap=(colour, from_fraction)` band so Frostcap earns its
name literally. Forest never had this problem because its names already map to different hues.

**Bramble at base `(140,124,104)` was too dark** — the voxel seams stopped reading and it was a
brown blob beside four legible eggs. Lifted to `(172,150,122)`.

## Open questions

- Warm tan pebbles are carried over from the forest egg. They give the frost egg its only warm
  contrast, but an ice-crystal pebble is the more literal choice. Not yet tested.
- EEVEE Next does not render the volumetric mist in the turntable; the Cycles still does. Not
  chased, because mist does not port to the viewport anyway.
- Per-egg decorations (neon spikes, rainbow rings) are **not** reproduced here. The premise of
  this pass is that elemental effects carry egg identity instead, letting the shell stay clean
  voxel like the reference. That premise is untested against the requirement that the five
  eggs per world stay distinguishable from each other.

## Pass B — hatch animation (not started)

Reference timeline, measured frame-by-frame from the user's clip at 30fps:

| t | event |
|---|---|
| 0.00 | egg pops in, background snaps dark |
| 0.00–0.60 | scale up |
| 0.60–2.20 | idle wobble, amplitude ramping ~2.7 Hz |
| 2.20 | flash, background snaps bright |
| 2.47 | shell splits (68% of full gap within 130 ms) |
| 3.07 | top launches and shatters |
| 3.40 | reveal |
| 4.23 | settled |

Cap/cradle are already separate objects, so the split is a transform on two existing objects.
