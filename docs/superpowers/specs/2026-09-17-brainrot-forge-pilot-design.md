# Brainrot Forge — pilot design

**Game:** Skip Rocks For Brainrots! (PlaceId 78783087742939)
**Date:** 2026-09-17
**Status:** Approved by the user (construction target, upload path, batch scope, world and concepts all chosen in-session); implementation plan next.
**Depends on:** `docs/brainrot-build-standard.md` (the measured standard this pipeline enforces).

## Goal

Ship a repeatable pipeline that turns an **original** brainrot design into a template that matches the game's construction standard — the imported pack's cost profile (~11 BaseParts, ~57 descendants, zero scripts/physics/animation) — while keeping the owner-approved **voxel look** of the game's own 66 originals. Prove it on three Frozen Tundra brainrots (Epic, Legendary, Secret), verified end to end through the real spawner, Index, bag, catch reveal and both mutation axes.

## Decisions made with the user

| Decision | Choice | Why |
|---|---|---|
| Construction target | Voxel look **baked into MeshParts** | The 66 originals are your own voxel art, exploded into 130–1,100 Parts only because mesh upload was impossible from code. A mesh gives the same silhouette at pack cost (25x fewer instances). |
| Upload path | **File > Import 3D** (user-driven, one `.glb` per batch) | Every scripted route is closed and was re-verified today: `AssetService:CreateAssetAsync` → "not available yet"; `AssetImportService` unreachable from the exec sandbox; `CreateMeshPartAsync` gives `MeshId ""` (never replicates or saves). |
| First batch | 3 brainrots, one per band | Prove design → bake → import → gate → in-game before designing a world. |
| World | Frozen Tundra (World 2) | Where all the originals live; Epic+ there is exactly the heavy voxel population; not on the supply schedule. |
| Colour handling | **One MeshPart per colour role**, `MeshPart.Color` flat | Exactly the pack's method; `MutationFX` recolours per part (Rainbow's spectrum-across-parts, Diamond, Golden) and would degrade on a single vertex-coloured mesh. |
| Roster entry | Appended to `BrainrotConfigTundra` with `Weight = 0`, `Origin = "Forge"` | The roster's proven "exists but never rolls from a throw" idiom (Secret Pete, fish). Live catch pool is untouched until the owner sets weights. |
| Effects | Only Legendary+; every emitter a `Clone()` of a `BrainrotFX` kit | Owner ruling of 2026-09-03; hand-authored emitters were "super laggy". |

## Concepts (original; checked against both rosters and the lexicon)

| Band | Name | Concept | Exaggerated feature | Palette | Motion / FX |
|---|---|---|---|---|---|
| Epic | **Guantone Brontolone** | a chunky knitted mitten standing on two stubby boots, face on the palm, heavy unibrow | one giant thumb it waves like an arm | red wool, cream cuff, dark brow/boots | `hover`; no FX |
| Legendary | **Alce Lampadario** | a squat moose whose antlers are an icicle chandelier | antlers twice the body width, candle tips | brown body, pale muzzle, ice-blue antlers, warm tips | `hover`; `glow` + `flare` kits at the tips |
| Secret | **Nonno Ghiacciaio** | a mountain-shaped grandfather whose snow beard is the whole lower body, tiny legs below, a wool cap on top | the beard | slate-blue ice, white beard, one gold accent | `shiver`; `aura` kit, Secret intensity 1.15 |

Names are Italian-nonsense in the roster's voice, collide with nothing in `BrainrotConfig`, `BrainrotConfigTundra`, `PetConfig` or `PlayerDataManager.RENAMES`, and depict no existing meme.

## Architecture

```
tools/brainrot_forge/ (Python, repo)                Studio (build-time modules, ServerStorage)
  designs/<name>.py ──▶ voxel.py (VoxelModel)         BrainrotForge.Assemble(importedRoot, manifestJson)
        │                    │                            │ rename, colour, flags, RootPart, attributes,
        │                    ▼                            │ parent under exact name, refuse overwrite
        │              bake.py (exposed faces →           ▼
        │              greedy quads per colour)      ReplicatedStorage.BrainrotModels["<Name>"]
        │                    │                            │
        ▼                    ▼                            ▼
  render.py (PNG previews)  export_glb.py            BrainrotBudget.review(model)  ──▶ PASS/WARN/FAIL vs pack
        │                    │ pilot_batch.glb + manifest.json
        ▼                    ▼
  user approves looks   user: File > Import 3D  ──▶ Workspace.AuxScene (importer output)
```

Nothing runs at game time. The spawner, idle client, mutation code, thumbnails and reveal are untouched — the template is a content drop that satisfies the existing contract (§2.7 of the standard).

## Components

### 1. `tools/brainrot_forge/voxel.py` — the design representation
- `VoxelModel(name, rarity, world, pitch=0.2)` holding `cells: dict[(x,y,z) -> role]` on an integer lattice (y up, feet at y=0, x/z centred on 0), `palette: dict[role -> "#RRGGBB"]`, `motion`, `fx`, `height_scale`, `width_scale`, `material` (`"Plastic"` | `"SmoothPlastic"`, default SmoothPlastic like the pack's coloured parts).
- Shape helpers used by the design scripts: `box`, `stepped_ellipsoid` (terraced, never smooth), `cylinder_y`, `wedge_stairs`, `mirror_x`, `carve`, `eyes(head_box, unit, recess=1)` implementing the `VoxelFace` rules (cube eyes, recessed one voxel, sized off the head not the model).
- Design language checks (`validate()`): ≤ 10 roles; height 25–45 voxels (5–9 studs at 0.2, matching the existing set); one role must cover ≥ 40 % of cells (a body, not confetti); eyes present.

### 2. `tools/brainrot_forge/bake.py` — voxels → meshes
- Emits only faces whose neighbour cell is empty. Greedy-merges coplanar same-role faces per (axis, sign, slice) into rectangles. Each rectangle = 4 unshared vertices, 2 triangles, one flat normal, planar UVs `u = a / 2, v = b / 2` in studs (so the owner's `BrainrotTile`, 2 cells per texture, tiles at 1.0 stud exactly as on Part bodies).
- Output: `{ role -> Mesh(positions, normals, uvs, indices) }` in studs, model origin at floor centre, front facing **−Z**: `BrainrotThumb.DEFAULT_DIR = (0.9, 0.45, −1)` places every thumbnail/reveal camera on the −Z side looking back at the centre (verified in source; the fish authored head-at-+Z showed their backs for exactly this reason). If the importer mirrors Z, the exporter flips it — checked on the first import.
- Budget pre-gate: refuses > 10 roles, > 8,000 triangles per model, > 2,000 per role; reports triangles per role.

### 3. `tools/brainrot_forge/export_glb.py` — batch file + manifest
- Minimal glTF 2.0 binary writer (stdlib only): one mesh + one node per role, node/mesh/material named `"<Model Name>__<role>"`, `baseColorFactor` set (the importer ignores it without a texture — colour is re-applied from the manifest, the proven fix), indices uint32, 4-byte aligned chunks.
- `manifest.json` per batch: pitch, and per model: rarity, world, roles → hex, part names, `heightScale`, `widthScale`, `motion`, `material`, `fx` recipe or null, bbox in studs, triangle counts.
- Round-trip reader used by the tests (also useful to ingest the forest `.glb` art later).

### 4. `tools/brainrot_forge/render.py` — approve before importing
- Software render of the *baked faces* (exactly what Roblox will draw): front-quarter view from above, sun-style shading per face normal, on a neutral sky. Two images per model: 512 px close-up and a **plot-distance strip** (the body scaled to how tall 6 studs reads at 40 studs on a 1080p screen, ~116 px) so silhouette readability is judged at the real gameplay distance. Batch contact sheet for the three.

### 5. `tools/brainrot_forge/designs/*.py` — the three pilots
One deterministic function per brainrot returning a `VoxelModel`. No randomness (looks must be identical for every player and every rebuild). Each ends with `model.validate()`.

### 6. `ServerStorage.BrainrotForge` (Luau ModuleScript, build-time; mirrored to `game-src/BrainrotForge.lua`)
`Assemble(importedRoot: Instance, manifestJson: string, opts?: {replace: boolean, tile: boolean}) -> Model[]`
1. Parses the manifest; for each model collects the imported MeshParts by exact `"<Name>__<role>"` name under `importedRoot` (the importer wraps a file as `Workspace.AuxScene > <root node>`). A missing part is an error for that model (nothing partial is parented).
2. Builds `Model "<Name>"`: MeshParts renamed to the role, `Color` from the palette, `Anchored = true`, `CanCollide/CanQuery/CanTouch = false`, `CastShadow = false`, `CollisionFidelity = Box`. Surface: when `opts.tile` (default true — visual check item) `Material = Plastic` **and** `MaterialVariant = "BrainrotTile"` (a variant only applies when the part's `Material` equals its `BaseMaterial`, which is Plastic for the tile); when not tiled, `Material = SmoothPlastic` and no variant. `RenderFidelity` is never written (plugin-tier; the standard forbids it).
3. Adds `RootPart`: invisible (Transparency 1) Part sized to the bounding box at its centre, `PrimaryPart`.
4. Attributes `HeightScale`, `WidthScale` from the manifest (Tundra ladder: Epic 1.30, Legendary 1.36, Secret 1.46).
5. FX: `BrainrotFX.apply(model, rarity)` reads `BrainrotFX.RECIPES[model.Name]`, so a new brainrot's effects are **recipe entries added to the module source** (`ReplicatedStorage.Modules.BrainrotFX`, mirrored to `game-src/BrainrotFX.lua`), each `E(kit, color, extra)` using only existing KITS (`glow`, `flare`, `aura1-3`, `snow`, `cubes`, `specs`, …). The manifest's `fx` field holds exactly those entries so the source edit is generated, not hand-typed; `Assemble` then calls `BrainrotFX.apply(model, rarity)` (hosts `BrainrotFxHost/Crown/Base`, sizes pre-divided by `bbox.Y/6`, rarity intensity Legendary 0.85 / Mythic 1 / Secret 1.15 / God 1.3). Budget ≤ 6 emitters, ≤ 80 alive. Runtime injection into `BrainrotFX.RECIPES` is not used — `applyAll` would silently skip the model on the next refresh.
6. Parents to `ReplicatedStorage.BrainrotModels`. **Refuses** if a model of that name already exists unless `opts.replace`, in which case the existing one is moved to `ServerStorage.AuditBackups.BrainrotForge_<Name>_<yyyy-mm-dd>` first. Every step is `pcall`ed per model; on failure that model's partial instances are destroyed and the error names the step.
7. Returns the models and runs `BrainrotBudget.review` on each, printing the verdict.

### 7. `ServerStorage.BrainrotBudget` (Luau ModuleScript, build-time; mirrored to `game-src/BrainrotBudget.lua`)
- `report(model) -> table` — every counter in §3 of the standard (descendants, BaseParts, visible/invisible, MeshParts, Parts, unions, wedges, attachments, bones, Motor6D, welds, WeldConstraints, constraints, ParticleEmitters, particlesAlive, trails, beams, lights, highlights, scripts, LocalScripts, ModuleScripts, decals, textures, textureIds, SurfaceAppearances and their maps, material histogram, MaterialVariants, neon, transparent, CanCollide, unanchored, CastShadow, sounds, BillboardGuis, humanoids, AnimationControllers, uniqueMeshIds, hasPrimaryPart, attributes).
- `compare(model) -> rows` — each counter beside `BASELINE.pack` (p50/p90 measured 2026-09-17, baked in as constants) and `CAPS` (§2.1), with `PASS` (≤ p50/typical), `WARN` (≤ max), `FAIL` (> max, or any forbidden object > 0).
- `review(model) -> string` — a text table plus the nine comparison questions answered from the numbers; 8 and 9 print as "human check" reminders.
- `baseline(folder, predicate) -> table` — recomputes percentiles from a folder so the constants can be refreshed (and so the pack vs voxel split is reproducible: `predicate = has MeshPart and Motor6D`).
- `triangles(model)` — reads `SceneAnalysisService:GetTriangleCompositionAsync()` for the model cloned alone into empty sky, minus baseline; returns nil with a clear message when the counters are frozen (Studio unfocused).

### 8. Roster edit
Three entries appended inside their tier blocks in `ReplicatedStorage.Modules.BrainrotConfigTundra`, anchored on a fresh live read (the module is collaborator-edited): `{ Name, Rarity, CashPerSecond, Weight = 0, Origin = "Forge" }` with CashPerSecond placed between existing neighbours in the tier's band — Guantone Brontolone **108,000** (Termosino 105k / Ghiacciolo 112k), Alce Lampadario **230,000** (Pattinatore 221k / Mammuto 240k), Nonno Ghiacciaio **900,000** (Ombra Bianca 850k / Titano 1M). `Motion = "shiver"` on Nonno Ghiacciaio only. Nothing else in the config changes; tier weight sums stay at their current totals. Compile-gated with `loadstring(script.Source)` before and after.

## Data flow (one batch)

1. `python -m brainrot_forge build pilot` → `out/pilot/pilot_batch.glb`, `manifest.json`, `previews/*.png`, a console budget table per model (roles, triangles, height in studs).
2. User approves previews (or design scripts are adjusted and step 1 re-run — seconds).
3. User: Studio → File > Import 3D → `pilot_batch.glb` → default settings → `Workspace.AuxScene` appears.
4. `execute_luau`: `require(ServerStorage.BrainrotForge).Assemble(workspace.AuxScene, <manifest json>)` → three models in `BrainrotModels`, budget reviews printed.
5. Roster edit (§8). Compile gate.
6. Verification (below). Owner saves the place (all place edits are unsaved until then — project convention).

## Verification plan (the user's steps 8–12)

- **Budget:** `BrainrotBudget.review` on each pilot must be PASS on every row against pack p90; printed beside `report` for Tralalero Tralala, Chimpanzini Bananini, Las Capuchinas, Los Crocodillitos (pack) and Zero Assoluto, Yeti Cappuccino, Valanga Ruggente (voxel) so the difference is visible in one table.
- **Round trip:** Play mode, `BrainrotSpawner.Spawn(plot, name, pad)` on a test plot for each pilot, plain / `Golden` / `Massive`; confirm on the **client** DataModel that the placed body has real `MeshId`s (not `""`), the weld+root anchoring, `BrainrotBody` tag, `Motion` attribute; walk to 70+ studs and back to confirm the LOD blank/restore and FX gate.
- **Surfaces:** Index silhouette + discovered tile, bag and sell-list thumbnails (`BrainrotThumb.master(name)` non-nil), catch reveal (`CatchReveal.play` with a faked `ThrowResult`, the documented test technique), no console errors.
- **Look:** screenshots for the user from the player viewpoint at pad distance; the user is the visual verifier (Studio must be foregrounded for any capture). `BrainrotTile` on meshes is a visual check item: keep or turn `opts.tile` off per the owner's eye.
- **Triangles:** in the same foreground session, measure the four pack samples and the three pilots with `BrainrotBudget.triangles`; write the numbers into the standard's §2.2 and replace its provisional caps.
- **Save-state:** `SessionLock` — wait ≥ 90 s between playtests; never call `PDM.Load` by hand.

## Error handling

- Bake refuses over-budget designs with the offending number; nothing is exported.
- Assemble is all-or-nothing per model, never overwrites without `replace` (and then backs up), never writes `RenderFidelity`, never touches anything outside the folder it creates.
- Roster edit anchored on a live read; if the anchor is not found verbatim the edit is not attempted.
- Any Studio step that errors leaves the place in its prior state; the importer's `AuxScene` is left in place until the user has seen the assembled result, then deleted.

## Testing

- Python (`pytest`): unit tests for `voxel` shape helpers and `validate`; `bake` — a single cube → 6 quads / 12 triangles, a 2×2×1 slab → 6 quads, a two-role model produces no interior faces and no shared faces, UV planes map to studs/2; `export_glb` — round-trip through the reader (names, counts, positions, alignment); `render` — produces a non-empty PNG of the expected size.
- Luau (command bar, Edit mode): `BrainrotBudget.report` on `Tralalero Tralala` reproduces today's census row (8 BaseParts, 5 MeshParts, 3 invisible, 6 emitters); `compare` on Valanga Ruggente FAILs on BaseParts and PASSes on scripts; `Assemble` on a synthetic import (plain Parts named `Test__body`, `Test__eye`) builds the model, sets every flag, refuses the second run without `replace`, and cleans up on a forced error.
- Play-mode verification as listed above; results recorded in the plan's execution log and the standard's §4.

## Out of scope (follow-ups, not the pilot)

- Converting the 66 existing voxel models (the forest set can go straight from its `.glb` files; the Tundra/fish sets from Part dumps via an `ingest_parts` step — same bake).
- World 3 (Gardens) roster; effects at Common–Epic; any change to spawner / idle / mutation / thumbnail code; the stale `game-src/README.md` and lexicon rewrite (flagged in the standard).
