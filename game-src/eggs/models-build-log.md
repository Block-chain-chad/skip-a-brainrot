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

## Design-match pass — video-matched palette + idle animation (this task)

Matched the 5 display models (`Workspace.GameWorld.EggStall` clones + canonical
`ReplicatedStorage.EggModels.Forest.ForestEgg1..5`) against the user's animated design
reference video (49 extracted frames, `f_001.png` front view + `f_010/011/012.png`
overhead ring-angle views). Two parts: **A)** recolor to the design's lit palette,
**B)** a new idle-animation script reproducing the video's ring precession, floating
shards, and hovering crown.

### Part A — recolor

Every changed part's pre-existing color was snapshotted to a `_EGG_Col2` attribute
before overwriting (skipped if the attribute already existed), applied identically to
both the stall clone and the canonical `ForestEgg*` model. 738 parts changed total.

| Egg | Family | New Color | Material |
|---|---|---|---|
| Shard (1) | shell_body | rgb(96,144,78) | SmoothPlastic |
| Shard | stripe | rgb(198,220,180) | SmoothPlastic |
| Shard | stud, shard | rgb(222,236,150) | SmoothPlastic |
| Drip (2) | shell_body | rgb(228,158,64) | SmoothPlastic |
| Drip | drip, shard | rgb(190,120,40) | SmoothPlastic |
| Drip | tape | unchanged (not in design spec) | — |
| Horned (3) | shell_body | rgb(76,116,62) | SmoothPlastic |
| Horned | stripe | rgb(48,84,44) | SmoothPlastic |
| Horned | spike, horn | rgb(28,26,24) | SmoothPlastic |
| Horned | shard | rgb(110,190,70) | SmoothPlastic |
| Rune (4) | shell_body | rgb(62,46,36) | SmoothPlastic |
| Rune | stripe | rgb(40,30,23) | SmoothPlastic |
| Rune | rune_ring, rune_bar, ring, shard | rgb(110,235,205) | **Neon** |
| Crown (5) | shell_body | rgb(88,62,42) | SmoothPlastic |
| Crown | cap, cap_drip | rgb(96,150,80) | SmoothPlastic |
| Crown | stripe | rgb(58,42,30) | SmoothPlastic |
| Crown | rune_ring, rune_bar, ring | rgb(120,220,110) | **Neon** |
| Crown | crown_ring, crown_point, crown_tip, halo_ring, link | rgb(226,210,170) | SmoothPlastic |
| Crown | shard | rgb(96,150,80) | SmoothPlastic |

One deliberate deviation from the initial target list: Shard Egg's `stud_*`/`shard_*`
parts were pixel-sampled directly from `f_001.png` (Python/PIL, not eyeballed) at the
floating dots to the egg's left — sampled RGB clustered around (240-255, 245-255,
165-185), a pale yellow-lime, not the originally-suggested saturated bright green
(120,200,90). Used rgb(222,236,150) instead, close to the parts' pre-existing authored
color. All other families matched their initial target well within the ±20%-read
tolerance on direct visual comparison against the reference frames.

### Part B — idle animation

New `Script` at `game.ServerScriptService.EggStallIdle` (source snapshotted to
`game-src/eggs/EggStallIdle.lua`). Server-authoritative, `RunService.Heartbeat`-driven,
touches only `CFrame` (no geometry/size changes). Animates the 5 stall display models
only — the canonical `ForestEgg*` models are not touched by this script.

- **Body bob**: every egg's shell + attached shell decorations bob vertically
  (amplitude 0.1 stud, no yaw), desynced periods 3.8-5.2s across the 5 eggs.
- **Ring precession**: Rune's single `ring_*` loop and Crown's two `ring_*` loops (the
  two concentric bands) precess — tilted 22° off horizontal, tilt-axis azimuth rotating
  around world Y. Rune period 10s; Crown's two rings 9s/12s in opposite directions.
  Each ring's 10 segment parts keep their original relative position/orientation
  (cached as a local `CFrame` inside the ring's own flat frame at setup), so precession
  only changes orientation, never the ring's true radius.
- **Crown halo+crown assembly**: `crown_ring`/`crown_point`/`crown_tip`/`halo_ring`/
  `link` parts move as one rigid unit — hovers 0.35 studs above its authored spot with
  a slow (8s) ±0.1 stud bob and a slow (14s) yaw.
- **Floating shards**: for Shard/Drip/Horned only, the smallest 3-4 parts (preferring
  the `shard_*` family — literally "floating shards" in the design — falling back to
  `stud_*` only if an egg doesn't have enough `shard_*` parts on its own; in practice
  all 3 eggs already had enough `shard_*` parts, so no `stud_*` was ever pulled) orbit
  the shell at `shellHalfWidth + 0.35` studs, heights staggered around mid-shell,
  periods 6-9s desynced, with a small continuous self-spin. Rune/Crown's `shard_*`
  parts are not floated (per spec, they stay attached and bob with the body).
- **Price tags**: each `PriceTag` `BillboardGui`'s `Adornee` was originally the shell
  part itself (which now bobs); at setup a small invisible `PriceTagAnchor` part is
  created at the tag's original world position and the `Adornee` is repointed to it, so
  tags never move even though the body does.
- **Perf/robustness**: base pivots/offsets cached once at setup, not re-read per frame;
  a 60-stud player-proximity gate is checked every 10th frame (animation pauses for
  eggs with no player nearby); a `stall.ChildAdded` listener re-resolves and re-caches
  any display model that gets replaced (e.g. a future restock/purchase swap), so the
  animation survives model replacement.

### Verification

Since `Script`s under `ServerScriptService` don't execute in Studio's Edit mode (only
during actual Play/server runtime), and the task's tooling contract forbade using
`start_stop_play` (Edit-only workflow, `get_studio_state` gate), the same driver logic
was additionally run live as ad-hoc `execute_luau` code (not saved, `_G`-scoped) so
`RunService.Heartbeat` would actually fire during this Edit session for verification.
The real `EggStallIdle` Script instance was left untouched in `ServerScriptService` —
it will run for real once the game is actually played.

- Two screenshots ~1.5s apart from the spec camera (`[-45,10,-260]` → `[-62,8,-260]`):
  Rune's ring visibly changed angle, Drip/Horned/Crown's floating shards visibly moved
  to different positions, all 5 price tags stayed pixel-identical between frames.
- Zero console errors/warnings across the whole live-preview run.
- After verification: preview `Heartbeat` connection disconnected, all animated parts
  restored to their authored resting `CFrame` (367 parts), `workspace.CurrentCamera.
  CameraType` reset to `Enum.CameraType.Fixed`.
- Not saved/published, per task instructions.

### Per-egg palette verdict (screenshot review vs. `f_001.png`)
- **Shard** — PASS. Mid-green shell + pale mint stripes read correctly; floating
  bits/shell dots corrected to pale yellow-lime after pixel-sampling (see above).
- **Drip** — PASS. Warm amber shell + darker-orange drip/shard accents, clean match.
- **Horned** — PASS. Green shell, darker-green stripes, near-black spikes/horns read
  as the intended dark-on-green silhouette (supersedes the old V=0.30 brighten fix).
- **Rune** — PASS. Dark brown shell, teal Neon rings/runes glow clearly against it.
- **Crown** — PASS. Brown-to-green shell, cream crown/halo/link assembly, green Neon
  rings; close-up confirms the cream crown_tip unification (was green) reads as one
  cohesive cream crown structure rather than two competing accent colors.

### Concerns
- The Rune/Crown ring radius (~1.37 studs) is nearly as wide as the shell itself
  (authored geometry, unchanged by this task) — at some precession phases the ring can
  visually flare out past the shell's silhouette more than a first glance at the
  reference frame suggests. Confirmed this matches the authored radius from the prior
  rebuild task's own log, not a bug introduced here.
- The recolor + `_EGG_Col2` snapshots and the `EggStallIdle` script are live-instance
  edits only (standard for this project's workflow); if a future rebuild re-runs the
  `luau_chunks_prim/*.lua` source chunks verbatim, both this recolor and the prior
  Horned brighten/stripe/ring-tube fixes would need to be re-applied (same caveat
  already on record from earlier entries in this log).
- Not save/reload-tested in this task (instructed not to save/publish).

## The Darrel bust — currency-mascot voxel character (this task)

Built "The Darrel" — a chunky-voxel character bust (face/shoulders only, no hands) as the
mascot for the game's premium currency (darrels), matching the game's forest-creature
construction conventions (stepped-width cube layers for a rounded head silhouette, flat
`SmoothPlastic` colors, no meshes/unions). Referenced `darrel_preview.png` (palette +
likeness: warm brown skin, round black-framed glasses, dark locs, mustache, backwards cap)
and `forest-brainrots-sprite.png` (style), plus inspected
`ReplicatedStorage.BrainrotModels["Strigolino Hootini"]` for its stacked-layer /
flat-eye-plate construction trick.

Built on a sky staging platform (`Workspace.DarrelStagingPlatform`, 12x1x12 Part at
`(0,500,0)`) with all 65 parts positioned relative to a local origin at the base of the
shoulders (world `(0,500.5,0)`), local +Z = face-forward. `PrimaryPart` = `HeadCore` (the
widest/eye-level head layer, ~2.2 studs wide). Every part: `Anchored=true`,
`CanCollide=false`, `CanQuery=false`, `Material=SmoothPlastic`.

**65 parts, 3 build iterations** (screenshots from `[6,503,6]`→`[0,503,0]` plus a
straight-front angle each pass):
- **Iter 1**: full build — warm-brown stepped head (jaw/cheek/eye-level/forehead/crown),
  charcoal cap dome + forehead strap band, round glasses (black frame + pale lens + bridge),
  mustache, 2-cube white grin, chin beard, ear + gold stud, 6-column-per-side dark locs,
  olive-grey crewneck shoulder stub. **Bugs found**: 4 corner-rounding nubs added to the cap
  dome's *top* surface rendered as ugly horn/spike bumps (rounding nubs only work at a
  boundary between two layers, not on an outermost exposed face); the locs' 6 columns had no
  gap between them and read as one solid black slab from the side rather than distinct
  twists; the ear/gold stud were fully hidden behind the loc column at the same X.
- **Iter 2**: removed the cap-dome top corner nubs (kept the dome smooth); gapped the loc
  columns (wider Z step, no more touching edges) with a small per-column X stagger so they
  read as separate twists instead of a wall; pulled the ear + stud outward past the locs'
  outer edge so the gold stud is visible from a 3/4 angle; lightened the cap-strap color for
  contrast. Also enlarged the chin beard, which overcorrected — it read as a single oversized
  black block dominating the lower face.
- **Iter 3**: shrank the chin beard back down to a small proportionate chin patch. Front and
  3/4 screenshots both confirmed: plain dark cap + visible forehead strap, big round pale-lens
  glasses, mustache, white grin, gold ear stud visible at an angle, dark locs framing both
  sides, warm-brown skin, olive-grey crewneck stub — reads clearly as "this person,
  brainrot-ified" and matches the forest-creature chunky-cube/flat-color style. **PASS.**

### Placement (incomplete — see Concerns)

Canonical copy reparented to `ReplicatedStorage.DarrelBust` (65 parts, unchanged from the
approved iter-3 build). A clone was mounted on `Workspace.GameWorld.EggStall.ShelfCap`
(base resting on the cap's top surface, `y = ShelfCap.Position.Y + ShelfCap.Size.Y/2 =
16.28`), rotated via a rigid `CFrame.fromMatrix` transform so the bust's local +Z (face)
points world +X — the same outward-facing direction as the stall's `NPC`/`Counter` (verified
`ShelfBack` sits at the most-negative X, `Counter` at the least-negative X, `NPC.LookVector`
≈ `(1,0,0)`). A `BillboardGui` ("DARREL" / "he watches the gems", cream `rgb(247,235,216)`
text with ink `rgb(62,34,19)` `UIStroke`, `Enum.Font.Cartoon`) was attached above
`PrimaryPart`.

First placement attempt (`Z=-250.9`, un-trimmed footprint) was checked against a full
bounds dump of every `EggStall` part: the "EGGS" `Sign` board (`Z[-267.5,-252.5]`,
`Y[16.23,18.83]`) is the only stall geometry at bust height (`ShelfPost`/`ShelfBoard`/
`Counter` all top out at `Y≈15.63`, below the cap). The bust's un-trimmed local-X footprint
(shoulders/locs/ear-stud, `-1.525` to `+1.60`) is ~3.13 studs wide, almost exactly filling
the 3.25-stud clear pocket between the `Sign`'s right edge (`-252.5`) and the `ShelfCap`'s
right edge (`-249.25`) — a wide-shot screenshot confirmed the bust visually overlapping the
Sign board. A fix was computed (de-stagger the locs to a flat `±1.25`, pull the ear/stud in
to `±1.25`/`1.34` with slightly smaller sizes, trimming the footprint to ~2.81 studs — giving
~0.2-stud clearance on both the Sign and the cap edge at `Z=-250.9`) and queued as the next
`execute_luau` call.

**The Roblox Studio MCP connection dropped before that fix call executed**
(`list_roblox_studios` returned zero connected instances afterward, and repeated
reconnect attempts failed) — this is a tooling/connection loss, not a design decision. Work
stopped here per the no-guessing-at-unrecoverable-state rule.

### Current actual in-place state (as of the disconnect)
- `ReplicatedStorage.DarrelBust` — canonical, approved 65-part build, **untrimmed**
  (original iter-3 footprint, ear/stud/locs not yet pulled in).
- `Workspace.GameWorld.EggStall.DarrelBust` — the **first** placement clone, at
  `Z=-250.9`, base on the `ShelfCap`, facing outward, with the `DarrelLabel` `BillboardGui`
  attached — **this clone's shoulders/locs/ear-stud overlap the "EGGS" `Sign` board**, per
  the math above and the wide confirmation screenshot.
- `Workspace.DarrelStagingPlatform` — **not deleted**; still present at `(0,500,0)`.
- `workspace.CurrentCamera.CameraType` — **not reset to `Fixed`**; camera cleanup never ran.
- Not saved/published (per instructions; also never reached that step).

### Concerns / next steps for whoever resumes
1. Re-open/reconnect Roblox Studio's MCP plugin, then re-run the queued fix: destroy
   `Workspace.GameWorld.EggStall.DarrelBust`, apply the ear/stud/loc trim to
   `ReplicatedStorage.DarrelBust` (see exact target values above), re-clone, re-place at the
   same `Z=-250.9` transform, re-attach the billboard, and re-screenshot wide to confirm the
   Sign no longer overlaps.
2. Delete `Workspace.DarrelStagingPlatform`.
3. Reset `workspace.CurrentCamera.CameraType = Enum.CameraType.Fixed`.
4. The bust currently sits at the stall's right end, close to both the `Sign`'s edge and the
   `ShelfCap`'s own edge — the available clear pocket is only ~3.25 studs against a ~2.8-3.1
   stud bust footprint, so there is very little margin either way. If a future redesign
   widens the bust (wider shoulders, longer locs stagger, etc.) it will not fit this pocket
   without shrinking it back down or picking a different mounting spot (e.g. centered higher
   above the Sign, or on the Counter instead of the ShelfCap).
