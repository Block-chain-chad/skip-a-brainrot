# D — Brainrot Veteran Build Manifest (Prototype B, conditional on E-13)

**Lane:** NPC-01 · Phase 2.5 · 2026-09-19 · disk-side spec. **Conditional:** the Bombardiro Crocodilo base is used only if Studio item E-13 confirms the template's structure supports the layer safely; otherwise the same manifest applies to the World 3 lane's replacement species (Path B, §D8).
**Hard rule:** the source collectible `ReplicatedStorage.BrainrotModels["Bombardiro Crocodilo"]` is **never modified**. The NPC is a clone; everything below happens on the clone in `ServerStorage.NpcStaging.Gardens`.

## D1. Two halves

| Half | What it is | Who may touch it |
|---|---|---|
| **BASE MODEL** | a `:Clone()` of the roster template, geometry/colours/face untouched except the global *worn* recolour (D4) | NpcForge only, by data |
| **VETERAN LAYER** | ≤ 8 additive parts + a stance + an idle profile, welded onto the clone | NpcForge only, by data (`VeteranLayer` recipe) |

## D2. BASE MODEL — preparation on the clone (identity untouched)

1. Clone the template; name the clone `VeteranBombardiro` (display name comes from `GardensNpcConfig.Roles.Veteran.Name`, not the model).
2. Strip runtime cruft exactly as `CatchCinematic.BrainrotRig` and the spawner do `[code]`: remove `Sound`s, scripts (there are none), and **all `ParticleEmitter`s / `BrainrotFxHost/Crown/Base` contents** — a war veteran has no Mythic aura (0 emitters, decision recorded in Phase 2 B8).
3. Keep the pack anatomy: `RootPart` (PrimaryPart) + `FakeRootPart` + the visible MeshParts on their Motor6Ds `[doc]`. **Anchor `RootPart` only**; weld `FakeRootPart` to `RootPart` (`WeldConstraint`) if the template does not already join them (E-13 tells); leave every MeshPart on its Motor6D so the driver can write `C0` on the head/wing if they are separate parts. All parts: `CanCollide/CanQuery/CanTouch = false`, `Massless = true`, `CastShadow = false` except the body mesh.
4. Do **not** add the `BrainrotBody` tag; add `NpcBody`; attributes `NpcRig = "Creature"`, `NpcTier = 3`, `NpcPack = "Creature"`, `NpcProfile = "Veteran"`, `NpcWorld = "Gardens"`, `NpcSpecies = "Bombardiro Crocodilo"`.
5. Scale: `Model:ScaleTo` to the plot fit (6.0 × `HeightScale`, width-limited at 9.5 — the spawner's math `[doc]`).
6. `PoseAnchor` attachment on `RootPart` (up axis for the breathe layer).

## D3. VETERAN LAYER — parts (max 8; priority order; drop from the bottom)

Sizes at the 6-stud fit; offsets are authored in **`RootPart` space** so the recipe re-applies to any fresh clone. Materials `Plastic` unless stated. All parts: `Anchored = false`, `WeldConstraint → Bone`, `CanCollide/CanQuery/CanTouch = false`, `CastShadow = false`, attribute `NpcStoryLayer = true`.

| # | Part | Size | Colour | Bone (weld target) | Offset (RootPart space, ≈) | Reads as |
|---|---|---|---|---|---|---|
| 1 | `WingSplint` | 0.18 × 2.20 × 0.50 | walnut 74,50,30 | left wing mesh if separate, else body | along the left wing's upper edge, tilted to the wing | the wing that never healed |
| 2 | `WingStrap` | 0.90 × 0.10 × 0.60 | soot 52,50,48 | same as 1 | across splint + wing, mid-span | bound, not decorative |
| 3 | `HarnessPlate` | 1.60 × 1.20 × 0.16 | iron 96,98,104 | body | chest, **6° askew** (roll), sunk 0.05 into the body | dented armour remnant |
| 4 | `HarnessStrap` | 0.35 × 1.40 × 0.10 | soot | body | from the plate's top-right over the right shoulder line | holds the plate |
| 5 | `GoggleBand` | 1.50 ⌀ × 0.12 (a thin cylinder Part) | soot | head mesh if separate, else body | around the crown, above the eyes | goggles pushed up |
| 6 | `GoggleLens` | 0.90 × 0.28 × 0.22 (one part, two lenses modelled as a bar) | smoked 70,72,80, SmoothPlastic | same as 5 | on the band, front | cracked = darker tint |
| 7 | `Medal` | 0.32 ⌀ × 0.06 | brass 196,150,72 | HarnessPlate | plate, lower-left | decorated; for what, unsaid |
| 8 | `SnoutChip` | 0.34 × 0.20 × 0.10 | 60,52,48 | snout mesh if separate, else body | flush with the snout tip, left side | damage, cause unanswered |

**Budget:** ≤ 8 parts · ≤ 600 added triangles (Part-built: ≈ 12 each → ≈ 100; if the splint/plate are forge-baked meshes: ≤ 600) · ≤ 4 new colours · 0 emitters · 0 lights · 0 Neon · 0 textures.

## D4. Damage / wear treatment (recolour, no geometry)

| Treatment | Rule | Condition |
|---|---|---|
| **worn materials** | every visible MeshPart `Color`: saturation −20 %, value −8 % (HSV, authored once by NpcForge from the template colours) | always |
| **scorch** | the tail role (or the rearmost separate MeshPart) → 60,52,48 | only if that part is separate (E-13) |
| **face** | `SurfaceAppearance.Color` tinted 0.85 on the face part (pack) or the face role repainted −15 % value (forge species); goggles sit above the brow so the eyes fall into shadow | always |
| **old paint** | one body role dulled a further −10 % saturation where a squadron mark would have been — **no mark drawn** (Bacon Head canon is from zero) | Path B only |

## D5. Altered stance (pose, not geometry)

- Model pivot: **pitch −12° (back), roll +6° toward the bound (left) wing**, then **sink −0.40 studs** so the underside is in the rubble/plinth (a World 3 scene prop).
- Facing: authored **30° off the tunnel axis** (placement is the World 3 lane's; the recipe stores yaw relative to the placement frame).
- `PoseAnchor` = the model's up after the tilt; the breathe layer moves along it.
- If the head is separate: rest `C0` turned 14° toward the tunnel (he watches it), so the glance layer works from that rest.

## D6. Idle profile (`Creature` pack, profile `Veteran`; kit C7 / package C)

| Layer | Joints | Value | Condition |
|---|---|---|---|
| breathe | whole model along `PoseAnchor` up (`RootPart` is anchored → the driver pivots the model with `PivotTo` from a captured base, the `BrainrotIdleClient` way) | 0.03 studs, `sine`, period 4.6 s | always |
| glance | head Motor6D `C0`: `turn` `snap` ±14°, period 11 s, `ease 0.3` | | head separate (E-13) |
| sag | wing Motor6D `C0`: `spread` −1.5° `sine` period 6 s | | wing separate |
| slow turn | head (or model) `track(player)` clamp ±40°, `smooth 2.2 s` on `PromptShown`; holds 4 s after `PromptHidden` | | always |
| talking | Neck-equivalent `bend` `pulse` +3° every 5–8 s; **no mouth animation** (pack face) | | while talking |

Amplitudes deliberately below the human pack's: stillness is the character.

## D7. Attachment strategy and reuse

- The layer is a **data recipe** (`VeteranLayer` in `NpcCharacters`, doc E): `{ part, size, color, material, bone, boneFallback = "Body", offset }`. NpcForge resolves `bone` against the clone's part names (E-13 gives the real names), falls back to the body mesh, positions in `RootPart` space, welds. No offsets are ever measured against the live plot body.
- **Reusable on other veteran brainrots:** `WingSplint`+`WingStrap` (any limb — the recipe's `bone` just changes), `HarnessPlate`+`HarnessStrap`+`Medal` (the "served under Tung" set), `GoggleBand`+`GoggleLens`, `SnoutChip` (any surface inset), the worn/scorch recolour rules, the sunk/askew stance rule, the `Veteran` idle profile.
- **Deserter** (`Il Disertore`): same recipe minus `Medal`, `HarnessStrap` shortened (cut), plus `BannerCloak` (1 draped part, faded dye) and `KeyCord` (1 prop); goggles *down* over the eyes; profile `Deserter` (glance toward exits, faster).
- **Ancient** (`Il Sussurro`): no armour parts; worn −35 %; ≤ 3 `CrystalGrowth` parts (cyan 158,234,238, SmoothPlastic, never Neon); one `BrowOverhang` part shadowing the eyes; profile `Ancient` (breathe 7 s only).

## D8. Path B — if E-13 fails the safety check

Safety check = **all** of: the template's MeshParts keep their Motor6Ds intact after cloning; `RootPart`/`FakeRootPart` exist; no part is a `Union`; the face is a `SurfaceAppearance` (tintable) or a colour role; triangle count at the fit ≤ 9k after the layer. If any fails, or the lane prefers a subtractive wound: the World 3 lane picks a **forge-baked species** with a separable wing/limb role (E-14), NpcForge re-bakes from the Part original with the wing role removed and the stump capped by `WingSplint`; every other row of this manifest applies unchanged.

## D9. Deliverable of the build (what lands in staging)

`ServerStorage.NpcStaging.Gardens.VeteranBombardiro` — clone + layer + stance + attributes, `BrainrotBudget.review` and `NpcBudget.report` both PASS, **no prompt** (the World 3 lane adds `VeteranPrompt` in a `PromptPart` at placement), no placement.
