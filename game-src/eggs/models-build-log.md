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
