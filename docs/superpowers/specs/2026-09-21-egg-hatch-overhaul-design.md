# Egg Hatch + Egg Visual Overhaul — design

Date: 2026-09-21 · Branch: `egg-hatch-overhaul` (worktree branch `claude/egg-hatch-visual-overhaul-f1269c`) · Status: working design, written before the build

## 1. What the live system does today (Phase 1 findings)

Egg purchase → reward is server-authoritative and correct: `EggHandler` (SSS.Modules) debits the
bundle price (`EggConfig.BundleCost`), rolls per egg (`EggHandler.RollFor`), grants through
`PetHandler.Grant`, and fires `Remotes.EggResult` with
`{ Ok, EggId, Name, Rarity, PetUid, PetId, Results = { {Name, Rarity, PetUid, PetId}... }, Source? }`.
Reward eggs (SeasonPassHandler, PetHandler.FlushPendingEggs, WheelHandler crate) fire the same
payload with `Source = "reward"`. Eggs hatch PETS (`PetConfig`, tiers Rare/Epic/Legendary/
Mythic/Secret); pet models live in `ReplicatedStorage.PetModels.<Model>`.

Presentation lives inside `StarterPlayerScripts.EggShopClient` (253k chars):

- **x1** — `playReveal` (a 1:1 build of an Aug-13 design handoff: black stage, ViewportFrame,
  voxel egg, TAP TO HATCH, 2.2 s wobble → split → card). **It has thrown on every single hatch
  since 2026-08-26**: line 3564 reads `Platform.Viewport` but `Platform` is only required inside
  three `do` blocks, so it is `nil` at that scope
  (`EggShopClient:3564: attempt to index nil with 'Viewport'`). A x1 purchase therefore shows
  NOTHING — the pet lands silently in the bag. Verified live in Play with a synthetic result.
- **x3 / x10** — `playMultiReveal`: a blur, "3 EGGS OPENED!", three rarity cards with the pet,
  NAME and RARITY all popping in at once, Skip button, HUD fully visible. This is the "instant
  result cards" the brief describes.
- HUD handling: x1 hard-disables every ScreenGui + all CoreGui + the topbar; x3 leaves the HUD.
- Egg art: `ReplicatedStorage.EggModels.<World>.<Key>` are 346–451-part voxel lattices
  (`VoxelEgg`/`EggPalettes`), five per world, same silhouette, colour-only identity. The
  stall displays (`Workspace.GameWorld.EggStall."<Name> Egg"`, Frost Eggs stall in the
  Tundra hub) are separate 80–235-part builds, sparkle floaters, 2–47 neon parts each.

## 2. Goals (from the brief) → decisions

| Brief | Decision |
|---|---|
| A real hatch sequence, reward not spoiled | New `EggHatch` presentation controller; name/rarity plates are created only after the reward model is on screen |
| Egg becomes the focus, world/HUD recede, sense of place kept | **World-space stage in front of the camera** (not a ViewportFrame): veil 55–75 % + DepthOfField far blur + character faded; non-essential ScreenGuis switched off *under* the veil and back on *under* it, so nothing pops |
| 1x ≈ 1.5–2.0 s, wobble with personality, crack buildup, final shake, burst, reveal, then text | Beat timeline in `EggHatch.Config` (appear 0.00, settle 0.15, wobbles 0.30/0.55/0.80, crack 1.00, shake 1.20, hatch 1.45, plate +0.40); eased curves, rock about the base, blocky crack lines + light leak, 5 rigid fragments + particle burst |
| 3x = three real eggs in a shallow arc, small offsets | Same timeline, three `EggRig`s at screen-fraction positions, 0.10 s offsets, rarest egg last; x10 = two rows of five, same rules |
| Rarity ladder Common…God, Golden/Diamond modifiers, Huge/Massive sizes | `Config.PRESETS` keyed by rarity (buildup extension, veil depth, burst, sting, camera punch, celebration); modifiers = chip + `MutationFX`; sizes = reward scale 1.35× / 1.8× + tag |
| Camera controlled, no motion sickness | Camera is **never taken over**: the stage follows the camera each frame (`BindToRenderStep` after Camera); FOV punch ≤ 3° (God 5°) with the base FOV restored |
| Sound ladder | SoundKit names only: `eggStrain`/`eggCrack1-3`/`eggCrumble*`/`eggSplit` + `catch<Tier>` stings + `catchBigHit`/`catchSparkle` layers |
| Better eggs, silhouette over glow, low part counts | New procedural `EggArt` recipes (10 eggs, 14–34 parts each, ≤ 2 neon parts, real materials), one recipe drives the shop card, the stall display and the hatch rig |
| Mobile | Everything laid out in screen fractions from `Platform.Viewport`/`Platform.Insets()`, plates use the kit's text floor, phone tested on the iPhone 16 emulation |
| Future speed/skip/auto | `Controller.play(result, { speed })`, `Controller.skip()`, `Controller.setSpeed()`; timeline is data, beats are functions of `t` |
| Do not change backend | `EggHandler`, `PetHandler`, `EggConfig`, saving, currency untouched |

## 3. Architecture

```
Remotes.EggResult ──► EggShopClient (thin handler) ──► EggHatch.Controller.play(result, opts)
                                                          │
                       ┌──────────────────────────────────┼──────────────────────────┐
                       ▼                                  ▼                          ▼
                 EggHatch.Stage                     EggHatch.EggRig  (xN)       EggHatch.RewardRig (xN)
   veil gui · DoF · HUD trove · prompts ·       EggArt.buildRig(key) · wobble ·   PetModels clone · fit ·
   character fade · camera-follow folder ·      cracks · burst fragments           face camera · pop · idle
   input catcher · RevealActive · watchdog
                       │
                 EggHatch.Fx  (particles, lights, beam, UI flash/ring, confetti)   EggHatch.Plate (name + rarity + tags)
```

- `ReplicatedStorage.Modules.EggHatch.Controller` — public API, queue (one run at a time,
  later results wait), presets, layout, the master clock, beat dispatch, skip/end.
- `…EggHatch.Stage` — everything that must be restored, tracked in a LIFO trove:
  HUD `Enabled` flips, `ProximityPromptService.Enabled`, `DepthOfFieldEffect`, character
  `LocalTransparencyModifier`, `RevealActive` attribute, camera FOV, the veil gui, the stage
  folder. Kill switches: Humanoid.Died, CharacterAdded, a watchdog at `timelineEnd + 6 s`.
- `…EggHatch.EggRig` — one egg on the stage: pose driver (pop, settle, wobble, hop, shake,
  squash), crack stages, burst (shell → 5 fragments + decorations thrown, fade, cleanup).
- `…EggHatch.RewardRig` — the hatched pet: scaled to a target screen height, facing the
  camera (eye parts → HeadAttachment → pivot heuristic), pop-in, idle bob/sway, God descent.
- `…EggHatch.Fx` — pooled ParticleEmitters/PointLights/Beams on stage parts; UI flash + ring
  + confetti on the veil gui.
- `…EggHatch.Plate` — name + rarity chip (+ mutation/size tags) under each reward.
- `…EggHatch.Config` — every number: beats, presets, layout, HUD keep-list.
- `ReplicatedStorage.Modules.EggArt` — egg recipes + builders (`build(key, opts)`,
  `buildRig(key)`), consumed by the shop cards (via the existing `EggModels` folder, which is
  regenerated from the recipes), the stall displays and the hatch.

`EggShopClient` keeps the shop; its two ceremonies and the tap/skip plumbing are deleted and
replaced by a 40-line handler that hides the panel, calls the controller and restores the panel
on `onDone`. The x1 bug disappears with the code that carried it.

## 4. The 1x timeline (Common–Epic; seconds, `speed` scales all)

| t | beat |
|---|---|
| 0.00 | veil + DoF ramp (0.22 s); egg pops in (scale 0→1.06→1, Back-out 0.22 s); `eggStrain` bed low |
| 0.12 | HUD guis off under the veil; character fade; shop panel hidden |
| 0.15 | settle squash (y 0.94 → 1.0) |
| 0.30 | lean −9° (ease out/in), tiny hop |
| 0.55 | lean +11° |
| 0.80 | lean −14°, hop 6 % of height, squash on landing |
| 1.00 | crack stage 1 (40 % of crack segments), `eggCrack1`, light leak particles start, FOV +1° |
| 1.20 | final shake 0.26 s (12 Hz decaying, scale 0.94→1.06), crack stage 2, glow up, `eggCrack2` |
| 1.45 | HATCH: flash 0.12 s, shell hidden, 5 fragments + decorations fly (gravity, spin, fade 0.5 s), burst particles, `eggSplit` + tier sting, FOV punch, reward pops (0.28 s Back-out, +lift) |
| 1.85 | plate slides up under the reward: NAME then rarity chip (0.12 s later), `catchSparkle` |
| 1.95 | celebration burst (tier-scaled), veil eases to 80 % of peak |
| 3.0 | auto end (Common–Epic hold 1.1 s after the plate); tap after the plate ends early |

End: reward + plates fade (0.22 s), HUD guis back on under the veil, veil/DoF ramp out (0.28 s),
shop panel restored, character back, `RevealActive` cleared.

Preset deltas: Legendary +1 wobble (+0.25 s), stronger burst, FOV 2°, `catchLegend`+`catchBigHit`,
gold orbit sparkles; Mythic +2 wobbles, crimson pulse light, screen flash, `catchMythic`+`catchDrama`;
Secret veil 0.80, extra hover beat with pulsing light 0.6 s, `catchSecret`, magenta ring; God veil
0.85, sky beam + ground glow, 1.2 s buildup extension, reward descends from the beam, `catchGod`,
FOV 4°. Golden/Diamond add a coloured tag only. Huge/Massive scale the reward 1.35× / 1.8× and tag it.

## 5. Layout

All positions are screen fractions converted to stage-local offsets at the stage distance `D`
(default 7 studs, shortened by a forward raycast, min 3): `x = sx·D·tanH`, `y = sy·D·tanV`.
Egg height = `2·D·tanV·f` where `f` is the on-screen height fraction (x1 0.44 desktop / 0.50
phone; x3 0.30; x10 0.19). x3 arc: sx = −0.30/0/+0.30, centre egg +4 % larger and 0.3 stud nearer;
x10: two rows of five (sx −0.36…+0.36, sy ±0.17). Plates sit under each reward; on phones the
x10 plate text is clamped to the kit floor and names truncate.

## 6. Verification plan

Studio Play with synthetic `EggResult` payloads from the Server exec (`__eggqa` relay):
x1 per rarity, x3 mixed, x10, reward-source, back-to-back results, death mid-hatch, phone
emulation (iPhone 16), part/instance counts before/after 20 hatches (no leak), frame times.
Real purchase path exercised through the real shop (`fireBuy`) once the profile allows.
