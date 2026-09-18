# Brainrot Build Standard

**Measured:** 2026-09-17 in the live place *Skip Rocks For Brainrots! [ALPHA!]* (PlaceId 78783087742939), Edit mode, plus prior measured sessions cited inline.
**Purpose:** the construction and performance bar every NEW brainrot (new world, event, exclusive) must meet. Designs must be original; construction must match this standard.
**Companion:** `docs/brainrot-lexicon.md` describes the retired July recipe system, not the shipping models — see §1.4.

---

## 0. TL;DR

- The game has **three construction styles** live at once. The **imported `.glb` pack (148 models)** is the performance reference the owner calls "fine". The **66 voxel models** (every Tundra Epic+ brainrot) are the AI-built style and are **25x heavier in instances** (median 270 BaseParts vs 11). The July **primitive-recipe system** (`BrainrotLooks`/`BrainrotBodyBuilder`) is dead code.
- The standard is therefore the **pack profile minus its import cruft**: a handful of MeshParts with flat colours, one face/detail overlay, a small particle kit on an invisible host, zero scripts, zero physics, zero animation data — measured budgets in §2.
- A new brainrot is a **content drop, not a code change**: a Model named exactly as its config entry, in `ReplicatedStorage.BrainrotModels`, with a `HeightScale` attribute and a `PrimaryPart`. The spawner, index, bag, sell list, catch reveal and idle motion all pick it up by name.
- Golden/Diamond and Huge/Massive are **not separate models** — they are applied at spawn (recolour/effects and `ScaleTo`). Never author variant models.
- One measurement is still open: **triangles per pack mesh** (§4). Every render counter in this Studio is frozen while it sits minimised; it is a 60-second job with Studio in the foreground.

---

## 1. Audit of the existing brainrots

### 1.1 Where they live and who reads them

| Thing | Location | Notes |
|---|---|---|
| Model templates | `ReplicatedStorage.BrainrotModels` (215 Models, flat folder, no sub-folders) | Model name == config `Name`. Read by the server spawner AND the client (Index silhouettes, bag/sell thumbnails via `BrainrotThumb`, `CatchReveal`/`PullCeremony`, `CatchCinematic.BrainrotRig`). |
| Plot LOD templates | `ReplicatedStorage.BrainrotModelsPlot` (43 Models) | Coarser rebuilds of the heaviest voxel models. `BrainrotSpawner.templateFor` prefers this folder; a miss falls through to the authored model. Only plots use it — close-up surfaces always read `BrainrotModels`. |
| Rosters | `Modules.BrainrotConfig` (Valley, 162), `Modules.BrainrotConfigTundra` (Tundra, 110; 57 names shared with Valley) | Entry: `{ Name, Rarity, CashPerSecond, Weight, [Origin], [FixedChance], [VoiceId], [Motion] }`. Weights sum to 100000 per tier. |
| World wiring | `Modules.WorldProgression` | *"THIS IS THE ONLY FILE THAT HAS TO CHANGE TO ADD A WORLD."* `Gardens` (World 3) and `Trading` currently alias to Valley. Adding a world = two config tables + one line. |
| Spawner | `ServerScriptService.Modules.BrainrotSpawner` | Clones template → fits to pad → trims → welds → tags. Fallback when no model: tier-coloured Neon cube. |
| Rarity ladder | `Modules.RarityConfig`, `RarityConfigTundra` | Common → Uncommon → Rare → Epic → Legendary → Mythic → Secret → God (no "Divine"). |
| Colour mutations | `Modules.MutationConfig` + `MutationFX` + `MutationVisuals` | Golden, Diamond, Rainbow + 8 weather variants. Applied to the spawned clone. |
| Size mutations | `Modules.SizeConfig` | Huge 1.65x / Massive 4.95x via `Model:ScaleTo` on the fitted clone. Stack with colour mutations. |
| Idle motion | `StarterPlayerScripts.BrainrotIdleClient` | One Heartbeat for every `BrainrotBody`-tagged Model; distance LOD + FX gate. Nothing per-model. |
| Mutation motion | `StarterPlayerScripts.MutationMotionClient` | One Heartbeat for every `MutationBody`-tagged Model. |
| Save data | `PlayerDataManager` (`data.Brainrots[i] = { Name, Mutation, Size, Uid, PadIndex, ... }`) | Inventory references brainrots **by config Name**. Renaming a name requires a `PlayerDataManager.RENAMES` entry or owned items become unspawnable. |

Coverage check (today): **every roster name has a model, every model is in a roster** (0 orphans either way). 36 models carry a `BrainrotFxHost` (the Sep-03 effects). 214 of 215 models carry a `MaterialVariant` reference (see §1.3 for why that is not what it looks like).

### 1.2 Three construction styles, measured

Population split of `ReplicatedStorage.BrainrotModels`: **148 rigged-mesh (pack) · 66 voxel · 1 primitive (`Chim`) · 1 static mesh (`Maxwell`)**. Per-style percentiles (n = models):

| Metric (per model) | **Pack** n=148 (min / p25 / **p50** / p75 / p90 / max) | **Voxel** n=66 | **Plot LOD** n=43 |
|---|---|---|---|
| BaseParts | 4 / 9 / **11** / 15 / 19 / 39 | 34 / 172 / **270** / 352 / 668 / 1106 | 25 / 52 / **88** / 106 / 143 / 551 |
| …of which visible | 2 / 5 / **8** / 11 / 14 / 36 | 32 / 170 / **268** / 350 / 668 / 1104 | 23 / 50 / **87** / 105 / 141 / 549 |
| …of which invisible scaffold | 2 / 3 / **3** / 3 / 6 / 10 | 0–3 (FX hosts) | 0–3 |
| MeshParts | 2 / 5 / **8** / 11 / 14 / 36 | 0 | 0 |
| Total descendants | 21 / 44 / **57** / 74 / 111 / 197 | 37 / 172 / **275** / 357 / 668 / 1111 | 28 / 58 / **90** / 109 / 148 / 557 |
| ParticleEmitters | 0 / 0 / **4** / 8 / 16 / 31 | 0 / 0 / **4** / 5 / 6 / 7 (36 of 66 have any) | 0 / 0 / 5 / 6 / 6 / 7 |
| Particles alive (Σ rate × mean lifetime) | 0 / 0 / **43** / 83 / 152 / 929 | 0 / 0 / 29 / 44 / 52 / 67 | 0 / 0 / 33 / 46 / 56 / 67 |
| SurfaceAppearance | 0 / 1 / **1** / 1 / 1 / 3 (ColorMap only, AlphaMode Overlay) | 0 | 0 |
| Neon parts | 0 / 0 / **0** / 0 / 0 / 3 | 0 / 0 / **0** / 16 / 28 / 679 | 0 / 0 / 4 / 17 / 23 / 489 |
| Partially transparent parts | 0 (max 1) | 0 | 0 |
| Attachments + Bones | 8 / 21 / **29** / 37 / 52 / 158 (rig import; unused) | 0 | 0 |
| Motor6D | one per MeshPart (rig import; **0 animations exist**) | 0 | 0 |
| Beams / Trails / Lights / Highlights | 4 models have beams (max 12), 3 have trails (max 8), 0 lights, 1 highlight | 1 light, else 0 | 0 |
| Scripts / LocalScripts / ModuleScripts | **0 / 0 / 0** | 0 / 0 / 0 | 0 / 0 / 0 |
| Unions / Constraints / Humanoids / AnimationControllers | **0** | 0 | 0 |
| Materials (all parts) | Plastic 946 · SmoothPlastic 859 · Neon 11 | Plastic 18,474 · Neon 1,727 | Plastic 3,125 · Neon 870 |
| Mesh flags | RenderFidelity Automatic, CollisionFidelity Box, DoubleSided on 3 of 1,293 | — | — |
| TextureID on MeshParts | 5 of 1,293 (colour comes from `MeshPart.Color`, ~8 distinct colours per model) | — | — |
| Anchoring in template | all unanchored (rig) — spawner fixes | anchored | anchored |

Pack anatomy (identical across all 148): `Model` → **`RootPart`** (invisible, PrimaryPart, body-sized) + **`FakeRootPart`** (invisible, carries the Bone tree) + **`VfxInstance`** (invisible, body-sized, hosts the aura emitters) + N `MeshPart`s each joined to `FakeRootPart` by a `Motor6D`, each flat-coloured, one carrying a ColorMap-only `SurfaceAppearance` for the face/detail. Mesh names are Blender defaults (`Cube.001`, `Plane`, `Circle.002`) — hand-modelled low-poly.

The pack's aura recipe (measured off `Carrotini Brainini`, reused verbatim by `BrainrotFX`): 3 `LockedToPart` emitters at `Speed 0`, `ZOffset -1`, alpha `1 → 0.68 → 1` on `VfxInstance`, plus a small high part with `glow` + `flare` (`LightEmission 1`, Rate ~3). Particle size is *smaller than the body* (1.6–2.3 studs on a ~6-stud body).

### 1.3 Which style is the standard, and why

**The pack is the standard.** Evidence:
- Owner, 2026-09-03 (recorded in `Modules.BrainrotFX` header): the hand-authored effects pass made the game *"super laggy"* and was removed; *"the 149 imported pack models carry 890 emitters between them and the owner says those are fine."* The Sep-03 effects on our 36 Legendary+ voxel models are therefore **clones of pack emitters** at roughly half the pack's per-model budget.
- `game-src/VoxelFace.lua` calls the pack *"the reference pack"* and matches its baked-in faces.
- The pack is 25x cheaper per body in instances than the voxel style (11 vs 270 BaseParts; 57 vs 275 descendants), and every per-instance cost in this game scales with that: replication/streaming (a far body seats with 2 of ~1,000 descendants delivered), spawn time (12 heavy bodies 121 ms → 34 ms with LOD), memory, the spawner's tiny-cull and weld passes, the idle client's per-part LOD blanking.

**What actually lagged (so nobody re-chases it).** Measured 2026-08-25 (`roblox-plot-brainrot-perf`): the multiplayer frame collapse was `BrainrotIdleClient` calling `Model:PivotTo()` every Heartbeat on bodies whose every part was anchored with no welds — O(parts) Lua CFrame writes per body per frame. Fix shipped in `BrainrotSpawner` (weld to PrimaryPart, anchor only the root): 25.6 Hz → 54.9 Hz at max load. Eliminated as causes *by measurement*: raw instance count (+20k parts = 2.8% Heartbeat), render (30k parts at a locked 60 fps, GPU idle), emitters/billboards/lights. Since then: the plot-LOD folder and tiny-cull halved plot instance counts; the idle client's far-plot LOD bug was fixed 2026-09-03 (far bodies now blank 97% of parts and switch emitters off).

**Why voxel is still the wrong construction for NEW brainrots even after that fix:** the bug made part count catastrophic; fixing it made part count merely linear. A 300–1,100-part body still costs 25–100x a pack body everywhere instance count matters, and *"only 3.8% of authored parts are fully buried"* / *"shell-only rebuilds come out heavier"* — there is **no part saving left inside the voxel style** (three independent coarsening attempts were rejected on look, `roblox-plot-lod-models`). The only way to keep a voxel *look* at pack *cost* is to bake the voxel body into a MeshPart (see §5).

**Do not confuse the aesthetic ruling with the construction ruling.** The owner has approved the *authored voxel look* three times and rejected coarser voxels each time. That is a look preference; it says nothing about part count. The pack proves the look/cost split: its geometry lives in meshes (GPU-side, one draw call per part), not in instances.

### 1.4 Dead and stale things to know about

- `Modules.BrainrotLooks` (213 recipes) + `Modules.BrainrotBodyBuilder` (1,119 lines) + `ServerStorage.BrainrotModelFactory_RETIRED`: **dead code**. The roster they were written for was replaced by the pack on the same day they shipped (2026-07-25); `IndexClient` says the recipes *"match none of the current names"*, and every current name has a model so the fallback never fires. `game-src/README.md` and `docs/brainrot-lexicon.md` still describe this system as live — they are stale.
- `ServerStorage.BrainrotModels_PreVoxel` (10 models): the first Gardens set as 10–17-part primitives / 25–31-part early voxels, before they were rebuilt as 130–470-part voxels.
- The pack's 739 `MeshPart.MaterialVariant = "Custom Stud"` references (plus "Custom Stud Small", "Strawberry Stud Dark/Light") point at variants that **do not exist in this place** (only `MaterialService.BrainrotTile` exists) — they render as plain Plastic. `BrainrotTile` (ColorMap + NormalMap, StudsPerTile 2) is on 18,400 voxel parts only.
- `BrainrotModelsPlot` was emptied on 2026-08-28 ("authored everywhere") but the owner's save kept the 43 LOD models — they are live and preferred by the spawner today.
- 10 pack emitters on 4 models (Guerriro Digitale, Dug dug dug, Agarrini la Palini, Trippi Troppi Troppa Trippa) sit at an altered mid-alpha 0.30 from an earlier mistaken sweep; original values unrecoverable.

---

## 2. The Standard

Budgets are per **template model** (what goes in `ReplicatedStorage.BrainrotModels`). "Typical" = pack p50–p75; "Max" = pack p90 rounded, the line a budget report flags. Anything over Max needs a written reason and owner approval.

### 2.1 Object budget

| Object | Typical | Max | Notes |
|---|---|---|---|
| BaseParts total | 8–15 | **20** | Secret/God bespoke may reach 25; nothing ships above 40 (pack max 39). |
| Visible geometry parts | 5–11 | **14** | MeshParts and/or Parts that actually render. |
| Invisible scaffold parts | 1–3 | **4** | PrimaryPart hitbox + up to the three `BrainrotFX` hosts (§2.4). Transparency 1, nothing else. (Was 3 until 2026-09-17; a Mythic/Secret recipe uses all three hosts, and the pack's own p90 is 6.) |
| MeshParts | 4–11 | **14** | Body, head, limbs, accessory, face-plate. One mesh may be shared by several parts (limbs). |
| Total descendants | 20–60 | **80** | A new model has no rig cruft, so expect 20–40. |
| ParticleEmitters | 3–6 | **8** (Legendary+ up to 10) | Cloned from `BrainrotFX` kits, never invented. |
| Particles alive (Σ rate × lifetime) | 40–80 | **100** | `BrainrotFX` measured pack mean 95.7, ours 42.6. |
| Attachments | 0–6 | 8 | Only as emitter/accessory mount points. |
| SurfaceAppearance | 0–1 | **1** | ColorMap only, `AlphaMode = Overlay`, on one part (face/markings). |
| Beams | 0 | 2 | Only when the concept *is* the beam (pack: 4 of 148). |
| Trails, Lights, Highlights | **0** | 0 | Highlights are applied by `MutationFX` at spawn, never authored. |
| Unions (CSG) | **0** | 0 | |
| Scripts / LocalScripts / ModuleScripts | **0** | 0 | Motion is `BrainrotIdleClient`; effects are static instances. |
| Motor6D / Bones / Welds in template | **0** | 0 | Unless an animation is actually authored and approved. Spawner adds its own `WeldConstraint`s. |
| Constraints / Humanoid / AnimationController / Sounds / BillboardGui / SurfaceGui | **0** | 0 | `VoiceId` lives in config, not the model. |
| Neon parts | 0 | **3** | Glow is an emitter's job. |
| Partially transparent parts | 0 | 1 | |

### 2.2 Geometry

- **Construction unit is the MeshPart, not the Part.** Silhouette detail lives in the mesh; instance count stays flat no matter how detailed the body is.
- Low-poly, hand-modelled read (pack meshes are Blender primitives-and-extrusions). **Triangles, measured at the 6-stud plot fit (§4): pack bodies run 790–16,064, median ≈ 4,300.** Standard: **typical ≤ 4,500 per body, max 16,000**; forge-baked voxel bodies stay under 2,000 per MeshPart / 8,000 per model (the pilot measured 660 / 744 / 1,720). Never accept an AI-generated mesh at its default density without decimating.
- `RenderFidelity = Automatic` (never write it from a script — Plugin-tier, throws on a client), `CollisionFidelity = Box`, `DoubleSided = false`.
- One concept, one exaggerated feature, clean silhouette at **6 studs tall from 20–60 studs away** — that is the distance a plot body is seen from. Details under ~4% of the bounding box are culled by the spawner anyway (`TINY_SHARE`).
- Authored size does not matter on a plot: the spawner fits every model to `MODEL_HEIGHT 6.0 × HeightScale` and `MODEL_MAX_WIDTH 9.5 × WidthScale` (whichever bites first). Author at any comfortable scale, then set the attributes.
- Face = baked into the mesh/overlay, cube-eyed if voxel-styled (`VoxelFace` rules), never spheres on a blocky body.

### 2.3 Materials, textures, colour

- Materials: **Plastic** (matte) or **SmoothPlastic** — nothing else on the body. Neon ≤ 3 parts. No Metal/Glass/Foil/ForceField.
- Colour: flat `MeshPart.Color` per part, ~5–10 distinct colours per model, authored hex wins (no saturation floors). Rarity tint ladders from the lexicon are *not* the current practice.
- Textures: **0 `TextureID`s** on body meshes. At most **one** ColorMap-only `SurfaceAppearance` (Overlay) for the face or markings. No NormalMap / MetalnessMap / RoughnessMap (pack: 0 of 150). Resolution ≤ 512² until pack textures are measured.
- Emitter textures: reuse the pack's uploaded sprites (`BrainrotFX` KITS hold 36 named ones) — no new particle uploads.
- `MaterialVariant` on MeshParts only when the mesh was authored for it: a variant tiles by the mesh's UVs, so meshes with arbitrary UVs (the pack; its own "Custom Stud" references are dangling anyway) stay plain, while forge-baked meshes carry world-space planar UVs (1 UV unit = 2 studs = the tile's 2 cells) and may take `BrainrotTile` with `Material = Plastic` (the variant's base material — a variant is ignored on any other Material). Whether the tile reads well on meshes is a visual check item on the first import.

### 2.4 Effects

- Effects are **baked as static instances** into the template, on an invisible host part (`BrainrotFxHost` body-sized aura, `BrainrotFxCrown` above the head, `BrainrotFxBase` at the feet — `BrainrotFX` naming, so `BrainrotFX.stripAll()` can revert).
- Every emitter is a `Clone()` of a `BrainrotFX` kit (which are clones of pack emitters), retuned only in colour/rate/size. Rarity intensity multiplies Rate only: Legendary 0.85 · Mythic 1.0 · Secret 1.15 · God 1.3. Common–Epic ship with **no effects** in our set (pack has effects at every tier; our budget is half the pack's).
- Particle sizes are pre-divided by `bbox.Y / 6` because `Model:ScaleTo` scales `ParticleEmitter.Size` (measured 2x).
- The idle client switches emitters/beams/trails/lights **off beyond 70 studs**; do not author anything that must stay visible at range.

### 2.5 Physics and render flags

The spawner enforces these on every clone, and templates should already match so ViewportFrame/reveal clones behave the same:
`Anchored = true` on the PrimaryPart only after welding (template: all anchored is fine), `CanCollide = false`, `CanQuery = false`, `CanTouch = false`, `CastShadow = false`, no `Massless` tricks, no constraints, no physics. Brainrots never collide with anything — Huge/Massive overlap neighbours on purpose.

### 2.6 Animation

- **No animation data in the model.** Motion is `BrainrotIdleClient` (one Heartbeat for all bodies: `RANGE 120`, `BUDGET 80`, `LOD_FAR 70 / LOD_NEAR 60`, `LOD_KEEP 3`), preset by the model's `Motion` attribute (`hover` for the whole roster; a config entry may force `bob/sway/spin/shiver`). Phase is hashed from name + pad, never random.
- The 148 pack rigs (1,301 Motor6D, 3,524 Bones) have **zero animations**; they are import residue, not a feature to copy. New models ship rig-free.
- Mutation motion (hue cycles, halo bobs, ring spins) is `MutationMotionClient`, tag-driven, not per-model.

### 2.7 Organisation and integration (the content-drop contract)

1. `Model.Name` == the config `Name`, exactly (spawner, thumbs, index, save data all key on it). Unique across all worlds; if a Valley name also exists in Tundra it is the *same* brainrot.
2. Parent: `ReplicatedStorage.BrainrotModels` (flat). Heavy Part-built bodies may add a lighter twin of the same name in `BrainrotModelsPlot`; mesh-built bodies never need one.
3. `PrimaryPart` set to an invisible body-sized root (pack: `RootPart`). The spawner re-centres the pivot on the bounding box.
4. Attributes: `HeightScale` (required — rarity ladder below), `WidthScale` (optional, 0.35–1, for long low creatures), `FxVersion` (written by `BrainrotFX`). Authoring metadata (`Tier`, `PaletteV3`, `RealLengthM`) is harmless but not read by gameplay.
5. No tags on the template; the spawner adds `BrainrotBody` (+ `MutationBody` when mutated).
6. Config entry in the world's roster module `{ Name, Rarity, CashPerSecond, Weight }`, weights re-balanced so the tier still sums to 100000. Optional `Origin` (provenance note), `VoiceId` (verified-loading id only, never guessed), `Motion`.
7. Rarity is **only** in the config entry; the model carries no rarity. Golden/Diamond and Huge/Massive are spawn-time (`Mutation` / `Size` fields in the save entry) — **never author variant models**.
8. `HeightScale` ladder as shipped — Valley: C 0.85 · U 0.90 · R 0.95 · E 1.05 · L 1.15 · M 1.25 · S 1.35 · G 1.5. Tundra: C 1.05 · U 1.15 · R 1.25 · E 1.30 · L 1.36 · M 1.42 · S 1.46 · G 1.5. A new world picks its own ladder inside the 0.7–1.5 clamp.
9. Event/limited brainrots: Valley names go through `SupplySchedule` seasons (`Debut` / vault) and `LimitedStock` caps; Tundra bypasses the schedule. Any guest/event name must be individually removable (vaultable) without touching other content.

### 2.8 Variants, restated

| Variant axis | Mechanism | Model impact |
|---|---|---|
| Golden / Diamond / Rainbow / weather | `MutationFX.apply` recolours the model's own parts (hue/sat/value maths), swaps material, adds static highlights/emitters/lights/shells; the pack's add-on geometry (Angel 337 parts, Frozen 309 worst case) is additive. `MutationSkin` (voxel re-skin) is display-only. | **None** — same template. |
| Huge / Massive | `Sizes.Scale` 1.65x / 4.95x applied after the pad fit; income `Mult` 3 / 8. | **None** — same template, same triangles. |

---

## 3. Budget report (the gate every new brainrot runs through)

Spec for `BrainrotBudget` (a ModuleScript run from the command bar / MCP; not yet built — see §5):

`BrainrotBudget.report(model) → table` with: `descendants, baseParts, visibleParts, invisibleParts, meshParts, parts, unions, wedges, attachments, bones, motor6d, welds, weldConstraints, constraints, particleEmitters, particlesAlive, trails, beams, lights, highlights, scripts, localScripts, moduleScripts, decals, textures, textureIds, surfaceAppearances, surfaceAppearanceMaps, materialHistogram, materialVariants, neonParts, transparentParts, canCollideParts, unanchoredParts, castShadowParts, sounds, billboardGuis, humanoids, animationControllers, uniqueMeshIds, trianglesPerMesh (when measurable), hasPrimaryPart, attributes`.

`BrainrotBudget.compare(model)` → the same table beside the **pack p50 / p90** baselines from §1.2 and the caps from §2.1, and a **PASS / WARN / FAIL** per row (WARN above typical, FAIL above max or any non-zero forbidden object).

`BrainrotBudget.review(model)` prints the nine comparison questions with the answer the numbers give:
1. Object count reasonable? (BaseParts ≤ 20, descendants ≤ 80)
2. Geometry complexity reasonable? (MeshParts ≤ 14; triangles ≤ cap once measured)
3. Texture/material usage reasonable? (0 TextureIDs, ≤ 1 SurfaceAppearance, Plastic/SmoothPlastic only)
4. Unnecessary runtime effects? (emitters ≤ 8, alive ≤ 100, 0 trails/lights, ≤ 2 beams)
5. Unnecessary scripts? (0)
6. Physics unnecessarily? (0 constraints/joints, CanCollide false, anchored)
7. Performance profile similar to existing? (within pack p90 on every row)
8. Visually belongs? — human check, from 20–60 studs in Play mode
9. Completely original? — name/concept/silhouette checked against both rosters and the lexicon

---

## 4. Triangles (measured 2026-09-17)

Method: `ServerStorage.BrainrotBudget.triangles(model)` — the model cloned alone into empty sky at (0, 4000, 0), fitted to 6 studs, `SceneAnalysisService:GetTriangleCompositionAsync().Opaque` minus the empty-sky baseline, after a warm-up pass so first-time mesh downloads do not under-count (Las Capuchinas read 72 on its first pass and 16,064 once loaded). Requires Studio to be the visible window; the counters are frozen otherwise.

| Model | Style | Parts | Triangles |
|---|---|---|---|
| Chimpanzini Bananini | pack | 7 | 790 |
| Tung Tung Tung Sahur | pack | 6 | 824 |
| Lirilì Larilà | pack | 8 | 949 |
| Tralalero Tralala | pack | 8 | 1,448 |
| Bombardiro Crocodilo | pack | 6 | 4,291 |
| La Grande Combinasion | pack | 22 | 4,298 |
| Strawberry Elephant | pack | 12 | 5,554 |
| Carloo | pack | 28 | 6,320 |
| Los Crocodillitos | pack | 39 | 15,092 |
| Las Capuchinas | pack | 15 | 16,064 |
| **Guantone Brontolone** | forge | 7 | **660** |
| **Alce Lampadario** | forge | 11 | **744** |
| **Nonno Ghiacciaio** | forge | 10 | **1,720** |
| Zero Assoluto | voxel | 172 | 2,040 |
| Yeti Cappuccino | voxel | 463 | 4,116 |
| Valanga Ruggente | voxel | 1,106 | 8,196 |

Reading: the pack spends its budget on geometry (up to 16k triangles in a handful of draw calls); the voxel bodies spend it on instances (a 1,106-part body is only 8k triangles but 1,111 replicated descendants). The forge bodies are cheap on both axes. Still unmeasured: the pixel size of the pack's 150 ColorMaps (third-party assets; not downloadable without a login).

---

## 5. Decisions taken 2026-09-17 (see `docs/superpowers/specs/2026-09-17-brainrot-forge-pilot-design.md`)

- **Look:** the owner-approved voxel look, **baked into one MeshPart per colour role** (voxel silhouette at pack cost). The 66 existing originals were the owner's own voxel art (`forest-brainrots-voxel.zip`, `Ice fishing brainrot designs.zip`), exploded into Parts only because mesh upload from code was impossible — the same bake converts them later.
- **Mesh upload path:** `File > Import 3D`, user-driven, one `.glb` per batch. Re-verified today that every scripted route is closed: `AssetService:CreateAssetAsync` → "not available yet"; `AssetImportService` unreachable from the exec sandbox; `EditableMesh` without upload gives `MeshId ""` (never replicates or saves); Studio's AI `generate_mesh` uploads real meshes but cannot bake a designed body.
- **Budget gate:** `ServerStorage.BrainrotBudget` per §3, built as part of the pilot.
- **Effects at Common–Epic** for our originals: still owner's call (pack has them at every tier; ours only Legendary+). Pilot ships Epic without effects.
