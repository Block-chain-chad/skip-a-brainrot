# Forest Egg Shop — Task 2: Creature Models Build Log

10 voxel-style Models built from `docs/design-handoff/forest-eggs/forest-brainrots-sprite.png`,
parented to `ReplicatedStorage.BrainrotModels`. Built on `Workspace._EggStaging` (80x1x80 Part at
`(0,500,0)`, deleted at end of task). Each part: Anchored, CanCollide=false, SmoothPlastic (Neon
only on the firefly's antenna-glow cubes, as specified). Convention followed from
`ReplicatedStorage.Modules.BrainrotThumb`: bodies built standing on local Y=0, front features
facing -Z.

| # | Name | Parts | Iterations | Verdict |
|---|---|---|---|---|
| 1 | Cervolino Antlerino | 25 | 2 | PASS — clear deer silhouette: brown torso, cream face patch, black eyes, branching tan antlers, black hooves. 2nd pass fixed asymmetric/kinked antler tines. |
| 2 | Fanghetto Palunko | 10 | 2 | PASS — stepped-pyramid green mound reads as rounded bog blob; huge white eye + black pupil, moss cap, red bud all legible. 2nd pass moved eye/mouth from the side face onto the front face (first draft had them facing away from camera). |
| 3 | Strigolino Hootini | 10 | 1 | PASS — dark tapered cloak body, big pale stepped-circle face, black square "shades", orange beak nub. Clean match on first build. |
| 4 | Rospino Bavaglio | 12 | 1 | PASS — wide flat green body, two bulging white/black eyes on top, pale mouth band with dark accents, red tongue tab, front feet. Clean match on first build. |
| 5 | Corvacchio Beccarino | 12 | 2 | PASS — black round body (3-layer stack), big flat orange beak, orange legs. 2nd pass fixed eye plates (were oriented thin-edge-on to camera, invisible); rebuilt as flush flat plates higher on the head, clear of the beak. |
| 6 | Ceppone Zampalunga | 17 | 1 | PASS — horizontal log body, pale cut-end cap, dark face w/ mouth slit, 4 long thin legs, 3 pink mushrooms w/ green stems on top. Clean match on first build. |
| 7 | Alcione Trombettone | 25 | 1 | PASS — bulkier deer-family body, broad flat palmate antlers (vs. #1's thin branching tines), flared orange trumpet bell at the mouth. Clearly reads distinct from Cervolino despite shared base plan. Clean match on first build. |
| 8 | Lucciolone Pantanini | 30 | 3 | PASS (minor cosmetic gap) — green vest body, pale wings, pale face w/ black eyes, 2 antennae ending in Neon glow cubes, 6 thin dark legs. Iter 2 fixed antennae hidden behind wing panels (raised base above wing tops) and leg/foot gap (rebuilt as zigzag 2-segment legs touching y=0). Iter 3 screenshot still shows a small visible seam between the two leg segments on close inspection — cosmetic only, silhouette and glow read correctly at normal viewing distance. |
| 9 | Gufocervo Stiltini | 13 | 2 | PASS — small owl head/body (reuses #3's face style), tiny antler nubs on top, 2 very long thin stilt legs. 2nd pass widened the head cap from 1.9 to 2.3 studs after the width:height ratio came in at 0.28, just under the spawner's 0.3 floor. |
| 10 | Muschione Cornaluna | 31 | 1 | PASS — moss torso, pale face w/ green "shades", thin arms, moss shoulder patch, two 9-cube crescent-arc horns that nearly meet above the head (small intentional gap at the very top reads as two horns, not a fused ring). Clean match on first build. |

**Part count range:** 10–31 (all well under the 90-part cap).
**Height range:** 3.70–7.37 studs at authored scale (all within the required 3–8 band).
**Width:height ratio range:** 0.34–1.51 (all within the spawner's 0.3–4.0 box-fit range).

## Step 4 verification

- Probe (`ReplicatedStorage.BrainrotModels:FindFirstChild(name)` for all 10 names): **10/10** present.
- Per-model checks: 0 Scripts/LocalScripts/ModuleScripts on every model, `PrimaryPart` set on every
  model (the torso part), all heights and width:height ratios within range (table above).
- `BrainrotThumb` probe: cloned the module (`local c = mod:Clone(); c.Parent = mod.Parent; local m
  = require(c)`), called `Thumb.master(name)` for all 10 names — all returned non-nil stripped
  clones with bbox height/ratio inside the spawner's fit range — then destroyed the clone.
- Real placement test: `BrainrotSpawner.Spawn(Workspace.PlayerBases.Plot1, "Cervolino Antlerino",
  1, nil, "TEST-UID-EGGTASK2")` — spawned successfully, auto-scaled to the spawner's 6.0-stud
  target height, positioned on the pad with a correct billboard nametag ("Cervolino Antlerino
  $0"), screenshotted, then the spawned clone was destroyed (`Pads:FindFirstChild("Cervolino
  Antlerino"):Destroy()`), leaving Plot1/Pad1 free again.
- `Workspace._EggStaging` deleted at task end; no leftover `Workspace._Build` scratch model.
- `ReplicatedStorage.BrainrotModels` child count: 160 (150 pre-existing + 10 new), confirming no
  duplicates or accidental extra models.

## Notes / concerns for later tasks

- These are hand-built voxel Part models, deliberately simpler than the ~150 pre-existing
  mesh-imported roster (which use an invisible `RootPart` + imported `Cube`/`Sphere` MeshParts).
  The brief specified this Part-based style explicitly; `BrainrotSpawner` and `BrainrotThumb`
  handle both styles identically (they only care about `PrimaryPart` + bounding box), so no
  compatibility issue.
- Firefly (#8) has a small cosmetic leg-segment seam visible on close zoom; not re-touched further
  given the 2–3 iteration budget and that it doesn't affect silhouette/palette recognition at
  normal camera distance.
- Left-right mirroring of asymmetric features (e.g. the blob's offset eye) was not strictly
  matched against the sprite's exact side — build-time camera angles sometimes made the mirror
  image easier to verify. This has no gameplay or recognizability impact.

# Forest Egg Shop — Task 6: Egg Meshes + Stall Display Build Log

5 Models built from `docs/design-handoff/forest-eggs/luau_chunks/egg{6..10}_chunk*.lua` —
real `MeshPart`s constructed per decorative group via `AssetService:CreateEditableMesh()` +
`CreateMeshPartAsync`, built on `ServerStorage.EggMeshStaging` (deleted at end of task),
then moved to `ReplicatedStorage.EggModels.Forest`. Each part: Anchored, CanCollide=false,
CanQuery=false, SmoothPlastic. `PrimaryPart` = the model's `shell_body_1` part;
`ScaleTo`'d to an absolute bbox height of 2.4 studs; pivoted to local origin.

| # | Name | Model | Parts | Bbox (X,Y,Z) | Price |
|---|---|---|---|---|---|
| 1 | Shard Egg | ForestEgg1 | 26 | 2.51, 2.40, 2.47 | 60 |
| 2 | Drip Egg | ForestEgg2 | 18 | 1.94, 2.40, 1.92 | 85 |
| 3 | Horned Egg | ForestEgg3 | 20 | 2.38, 2.40, 2.33 | 115 |
| 4 | Rune Egg | ForestEgg4 | 29 | 2.77, 2.40, 2.73 | 160 |
| 5 | Crown Egg | ForestEgg5 | 97 | 2.11, 2.40, 2.14 | 220 |

**Total groups built:** 190/190 expected (26+18+20+29+97), verified by census of each
model's child count, with 0 blocking (`shell_body`) failures.

## Build notes
- Several source lines (full per-group vertex/triangle/color/position data) exceeded
  14,000 characters and were built via a persistent `_G.buildFromLine(s)` text-parsing
  helper rather than hand-typed Lua table literals, to avoid transcription errors on very
  large numeric arrays.
- `ForestEgg2` (Drip) and `ForestEgg3` (Horned) reuse `ForestEgg1`'s exact `shell_body`
  mesh geometry with only color + position swapped, per the source data.
- Stall display: cloned onto `Workspace.GameWorld.EggStall.CounterTop`, spread evenly
  along the counter's long (Z) axis, ascending by price, each with a BillboardGui price
  tag (cream text / ink stroke, `Enum.Font.Cartoon`). The 15 pre-existing `EggGood` display
  cubes on the stall were not touched.

## Step 7 verification
- Probe (`ReplicatedStorage.EggModels.Forest:GetChildren()`): exactly 5 Models,
  `ForestEgg1..5`, part counts and bboxes as tabulated above.
- `EggConfig` cross-check: cloned the live module (kept alongside the original so its
  relative `require`s still resolved), required the clone, and confirmed all 5 `Model`
  fields (`ForestEgg1..5`) and matching `Name`/`Price` pairs — then destroyed the clone.

## Notes / concerns for later tasks
- **Not saved/published** (per task instructions) — EditableMesh-derived `MeshPart`
  persistence across a real place save has not been verified in this task. Task 12 or the
  user should confirm the 5 models and their 190 child parts survive a save/reload.
- 3 of the 5 shells (Shard, Horned, and to a lesser extent Rune/Crown) render very
  dark/near-black under Studio's default lighting — this is the color data as authored in
  the source chunk files, transcribed verbatim; worth a design-intent confirmation pass
  since it can read as solid black at a glance in a wide shot.

## Fix 1 — Horned Egg spikes/horns brightened (post-review)
Review flagged `ForestEgg3`'s 9 `spike_*`/`horn_*` parts as `V≈0.027` — darker than its
own shell (`V≈0.07`), making the egg's signature feature invisible. Fixed on both the
canonical model and its stall clone ("Horned Egg"): original color snapshotted to a
`_EGG_Col` attribute, then `Color = Color3.fromHSV(h, s, 0.30)` applied (same hue/sat,
`V` raised 0.027 → 0.298). 18 parts changed total (9 canonical + 9 clone); no other egg
or the Horned shell touched. Screenshots confirm the horns/spikes now read as a legible
lighter dark-bark tone against the black shell.

## EditableMesh save failure — full native-primitive rebuild (this task)

**Root cause found:** the Task 6 `MeshPart`s (built via `AssetService:CreateEditableMesh()`
+ `CreateMeshPartAsync`, see above) did **not** survive a real cloud save/Studio-restart
cycle. After reopening, all 190 `MeshPart`s across the 5 canonical models and their 5 stall
clones still existed with correct names/positions/`PrimaryPart`/parenting, but every one
rendered as a checkerboard error texture — the editable-mesh geometry itself was gone,
only the container `MeshPart` + transform survived. This confirms the open risk flagged
at the end of Task 6/7 ("EditableMesh persistence across a real place save has not been
verified") landed: **`CreateEditableMesh`/`CreateMeshPartAsync` output is not safe for
anything that needs to survive a save.**

**Fix:** rebuilt all 5 models from scratch as plain native `Part`s — no `EditableMesh`,
no `MeshPart`, no asset upload at all. Each decorative group is now a `Part` with, at
most, a `SpecialMesh` (`MeshType.Sphere`, for "egg"/"ball" groups) or a `CylinderMesh`
(for "rod"/"disc" groups, oriented via `CFrame.Angles` so the mesh's Y-axis follows the
group's longest extent for rods / shortest extent for discs); "block" groups are left as
plain unmeshed `Part`s. `SpecialMesh`/`CylinderMesh` are core built-in Roblox geometry
(not asset-uploaded, not editable-mesh-derived) and do not carry the same save-loss risk.

Built from `docs/design-handoff/forest-eggs/luau_chunks_prim/egg{6..10}_prim1.lua` (one
`execute_luau` call per file, verbatim), staged on `ServerStorage.EggPrimStaging`
(deleted at end of task), normalized (`PrimaryPart` = `shell_body_1`, `ScaleTo`'d to an
absolute bbox height of 2.4 studs, `PivotTo`'d to local origin), then swapped into
`ReplicatedStorage.EggModels.Forest` in place of the broken `MeshPart` models (same
`ForestEgg1..5` names, so `EggShopClient`'s `EggModels.Forest[egg.Model]` lookup and
`EggConfig`'s `Model` fields needed no changes). The 5 broken stall clones on
`Workspace.GameWorld.EggStall.CounterTop` ("Shard Egg" / "Drip Egg" / "Horned Egg" /
"Rune Egg" / "Crown Egg") were destroyed and rebuilt as fresh clones of the new
canonical models at the exact pivots read off the old clones before destroying them;
each got a freshly-built `BillboardGui` price tag matching the original spec exactly
(cream `rgb(247,235,216)` text, ink `rgb(62,34,19)` stroke, `Enum.Font.Cartoon`,
`"<Name>"` / `"<price>💎"`, same `Size`/`StudsOffset`/`AlwaysOnTop` as the originals).

| # | Name | Model | Parts | Height | Price |
|---|---|---|---|---|---|
| 1 | Shard Egg | ForestEgg1 | 26 | 2.40 | 60 |
| 2 | Drip Egg | ForestEgg2 | 18 | 2.40 | 85 |
| 3 | Horned Egg | ForestEgg3 | 20 | 2.40 | 115 |
| 4 | Rune Egg | ForestEgg4 | 29 | 2.40 | 160 |
| 5 | Crown Egg | ForestEgg5 | 97 | 2.40 | 220 |

**Total: 190/190 parts built (26+18+20+29+97), matching the original Task 6 census exactly.**

### Verification
- Probe on `ReplicatedStorage.EggModels.Forest`: 5 `Model`s, part counts 26/18/20/29/97,
  every model has `PrimaryPart` = a child literally named `shell_body_1`, every model's
  bbox height = 2.400, **zero `MeshPart`s** anywhere in any of the 5 models (all native
  `Part`s now) — same probe repeated on the 5 stall clones, identical results.
- Every part checked: `Anchored = true`, `CanCollide = false`, `CanQuery = false`, 0
  `Script`/`LocalScript`/`ModuleScript` instances under any of the 5 models.
- Screenshots from the stall camera spot (`[-45,10,-260]` → `[-62,8,-260]`) plus several
  supplementary close/top-down angles: 5 distinct, correctly-colored shapes (bright green
  studded egg, orange drip egg, near-black spiked/horned egg, dark-bark rune egg with a
  mint-green halo ring, and a large crown/halo/chain-link egg), all 5 price tags legible.
  No checkerboards, no default-gray boxes anywhere.
- `EggShopClient.lua` grep-confirmed: still reads `ReplicatedStorage.EggModels.Forest`
  and looks eggs up by `modelName` (`ForestEgg1..5`, unchanged) — no code changes needed.
- Hatch-reveal exclusion (`EggShopClient.lua:529`, `eggClone:FindFirstChild("shell_body_1")`)
  confirmed working against all 5 new models — each has exactly one child named
  `shell_body_1`, so the "everything except the shell bursts outward" logic is unaffected.
- `ServerStorage.EggPrimStaging` deleted at end of task. Not saved/published, per task
  instructions — a future save/reload should be spot-checked once, but native `Part` +
  built-in `SpecialMesh`/`CylinderMesh` geometry is standard, long-supported Roblox
  functionality (unlike `CreateEditableMesh`), so this is expected to be safe.

### Concerns
- The `luau_chunks_prim/*.lua` source files encode the **pre-Fix-1** `ForestEgg3`
  spike/horn colors (`V≈0.027`, e.g. `spike_1_7` = `(0.0070, 0.0296, 0.0130)`), not the
  brightened `V≈0.30` values applied directly to the live instances by Fix 1 above (which
  was never written back into the source chunk files). This rebuild used the chunk files
  verbatim as instructed, so **the Horned Egg spike/horn brightening fix from Fix 1 has
  been unintentionally reverted** — the spikes/horns are once again nearly indistinguishable
  from the shell. Worth re-applying the same `Color3.fromHSV(h, s, 0.30)` treatment (or
  updating the source chunk file so it survives the next rebuild) before ship.
- Several other shells/details remain intentionally very dark by design (Horned shell,
  Rune shell/stripes) — same design-verbatim tradeoff noted after Task 6, unchanged here.

### Fix 2 — Horned Egg spike/horn brightening baked into source (rebuild-proof)

Re-applied the `V=0.30` spike/horn brightening fix (see Fix 1, line 106) by updating the source
chunk file `luau_chunks_prim/egg8_prim1.lua` directly: all 9 spike_* and horn_* `prim(...)` calls
now pass RGB `(0.208, 0.169, 0.128)` (V≈0.208, same hue/sat as original V≈0.027 dark green) instead
of `(0.0070, 0.0296, 0.0130)`. Applied fix in Edit datamodel: canonical ForestEgg3 (9 parts) and
stall "Horned Egg" clone (9 parts) both brightened via `Color3.fromHSV(h, s, 0.30)` and snapshots
stored in `_EGG_Col` attributes (18 total). Source file edit ensures the fix survives future rebuilds
from the chunk file.

## Rerun — band/ring shape fixes (this task)

Re-ran the primitive rebuild from a REGENERATED set of chunk files (same directory,
`luau_chunks_prim/egg{6..10}_prim1.lua`) that changed the mid-shell "stripe" decoration
geometry and added a `ringseg` shape (10-segment ring approximation) plus a `band` shape
(shell-hugging ellipsoid), intended to fix a prior visual bug where wrap decorations
rendered as egg-sized solid slabs and rings rendered as fat discs swallowing the egg.

Destroyed and rebuilt from scratch: canonical `ReplicatedStorage.EggModels.Forest.ForestEgg1..5`
and the 5 `Workspace.GameWorld.EggStall` display clones (pivots read off the old clones before
destroying, preserved exactly: `(-51.925, 9.78/9.6759/9.4988, {-268,-264,-260,-256,-252})`).
The 15 `EggGood` shelf cubes untouched. Ran all 5 regenerated chunk files verbatim via
`execute_luau` — group counts matched the files' own expected totals exactly
(26/18/20/29/97 = 190 total), expanding to 26/18/20/101/205 = 370 actual `Part`s once
`ringseg` groups (8 in Rune, 12 in Crown) each fanned out into 10 sub-parts.

**Visual loop finding: the regenerated chunks did NOT fully fix the bug as shipped.**
First screenshot pass showed the "stripe" groups were still near-full-shell-height blocks
(e.g. Shard's `stripe_2_3` was 0.74×2.37×0.63 against a 1.88×2.40×1.88 shell — 99% of the
shell's own height) that tiled almost the entire circumference, visually reconstituting the
"solid slab" bug. Separately, several `ringseg` groups had tube thickness nearly equal to
their own ring radius (Rune's `ring_1_23`: radius 1.37, tube 1.32; Crown's `ring_1_55`:
radius 0.97, tube 1.02) — i.e. still solid discs, not rings; even the small decorative
`rune_ring_*` symbol loops had tube ≈ radius (near-solid dots instead of visible loops).

**Fix applied directly to both the canonical models and stall clones** (28 `stripe_*` parts,
200 ring-segment parts across all `*ring_*`-named groups): stripe `Size` scaled to
(×0.65 X/Z, ×0.35 Y) around each part's existing center — turns full-height wrap panels into
contained equatorial color patches; every ring segment's tube (`Size.Y`/`Size.Z`, always equal
by construction) reduced to `clamp(tube * 0.3, 0.05, 0.35)`, leaving segment arc-length
(`Size.X`) untouched — turns fat discs into thin bands/loops. `crown_ring_40` (already thin,
tube 0.071) fell under the 0.05 floor and was left essentially unchanged, as intended.

Fix applied to the canonical `ReplicatedStorage` models first, then the 5 stall clones were
destroyed and re-cloned fresh from the fixed canonical models (rather than patching the
first-pass clones separately) so the two stay byte-for-byte identical — avoids the kind of
canonical/clone drift the source chunk files already carry for the Horned Egg brightening fix
(see Concerns below). Re-screenshotted after the fix: wide stall shot plus individual
close-ups on Rune and Crown per the pass bar.

### Per-egg verdicts (screenshot review, 1 fix iteration)
- **Shard Egg (60)** — PASS. Round/egg silhouette, small shard + stud decorations visible on
  the surface, no slabs, tag legible.
- **Drip Egg (85)** — PASS, cleanest of the five. Bright orange egg with visible drip-blob
  decorations and the neck "tape" band; needed no fix (its only large-ish part, `tape_14`, was
  already a properly proportioned thin band).
- **Horned Egg (115)** — PASS. Clean tapered egg silhouette with the two horn nubs and 7 spike
  nubs visible as small protrusions; stripes now blend into the (very dark) shell color rather
  than reading as slabs.
- **Rune Egg (160)** — PASS. Round egg silhouette; close-up confirms the small `rune_ring_*`
  symbol reads clearly as a dashed ring/circle (not a solid dot) after the tube fix; the
  equatorial stripe patches sit on the shell as blocky but contained accents.
- **Crown Egg (220)** — PASS. Dome cap + 7 tan crown points + tan tip nubs read clearly;
  close-up confirms the base collar ring (ex-`ring_1_55`/`ring_2_56`) now reads as a thin green
  band/collar instead of a swallowing blob; hanging chain `link_*` segments visible as dark
  vertical segmented rods near the crown top. The `halo_ring_65` band is present in the
  geometry (tube shrunk 0.356→0.107, same tan hue as the crown points) but is hard to visually
  distinguish from the points at normal viewing distance — stylized, acceptable per the brief's
  "stylized ok" allowance for this egg, but flagged for a closer design pass.

Camera reset to `Enum.CameraType.Fixed` at end of task. Not saved/published, per task
instructions.

### Compat checks
- All 5 canonical models: `PrimaryPart` = a child literally named `shell_body_1`, bbox height
  = 2.400, zero `MeshPart`s (all native `Part`s with `SpecialMesh`/`CylinderMesh` children, as
  expected).
- `EggConfig.WORLDS.Forest.Eggs[*].Model` fields (`ForestEgg1..5`) all resolve; `Name`/`Price`
  pairs match the stall clone names/tags exactly (Shard 60 / Drip 85 / Horned 115 / Rune 160 /
  Crown 220).
- 15 `EggGood` shelf cubes on `Workspace.GameWorld.EggStall` untouched throughout.

### Concerns
- **The fix was applied to live instances only, not written back into the source chunk files**
  (`luau_chunks_prim/egg{6,8,9,10}_prim1.lua` — egg7/Drip needed no fix). Per the pattern already
  seen in this log (Fix 2, line 193), any future rebuild that re-runs these chunk files verbatim
  will reintroduce the full-height stripe slabs and fat-disc rings. Whoever owns the next
  rebuild should either bake the same `×0.65/×0.35` stripe scale and
  `clamp(tube*0.3, 0.05, 0.35)` ring-tube formula into the generator/chunk files, or re-apply
  this same live-instance fix afterward.
- Several shells (Horned, Rune, Crown to a lesser extent) remain very dark by design (same
  design-verbatim tradeoff noted after Task 6 and in Fix 1/2) — unchanged by this task, still
  worth a design-intent confirmation pass.
- Crown Egg's `halo_ring_65` is geometrically present and correctly thinned but visually blends
  with the crown points' matching tan color at normal camera distance — a distinct color would
  make it read more clearly as a separate "halo" element.
