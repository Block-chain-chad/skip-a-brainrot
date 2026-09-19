# A — Gianluca Build Manifest (Prototype A, implementation-exact)

**Lane:** NPC-01 · Phase 2.5 · 2026-09-19 · disk-side spec; nothing built in Studio; the live `StupidGianluca` is not replaced.
Source of truth for shapes/colours: Phase 2 spec A; for the rig: Phase 2 kit C (SR-Rig v1). This manifest is what `NpcForge.Build("Gianluca")` (doc E) must produce, part for part.

Classification key: **[KIT]** reusable global kit · **[GIA]** Gianluca-specific · **[OPT]** optional polish.

## A1. Coordinate conventions (used by every table below)

- Character space = `HumanoidRootPart` space: **front = −Z, right = +X, up = +Y.** All positions are offsets from the HRP centre in studs at scale 1.
- Ground is at HRP y −3.00. Total height 5.23.
- Every Motor6D lives in its **Part1**; `C0` = pivot in Part0 space, `C1` = pivot in Part1 space; rest pose = `Transform` identity. With axis-aligned rest parts, `C0 = CFrame.new(pivot − Part0.centre)`, `C1 = CFrame.new(pivot − Part1.centre)`.

## A2. Exact hierarchy

```
StupidGianluca                       Model   [contract name — unchanged]   PrimaryPart = HumanoidRootPart
│  Tag: NpcBody
│  Attributes: NpcRig="SR1" NpcTier=2 NpcPack="Villager" NpcWorld="Valley" NpcBodyType="standard"
│              NpcScale=1 NpcFace="worried" NpcId="Gianluca" NpcFamily="ranger"
│  ModelStreamingMode = Atomic
├─ HumanoidRootPart   Part      2.00×2.00×1.00   @ (0, 0, 0)     Transparency 1  Anchored ✔   [KIT]
│    ├─ TalkPrompt     ProximityPrompt  [EXISTING INSTANCE, re-parented from the old HRP — never recreated]   [GIA]
│    └─ RootAttachment
├─ Collider           Part      1.60×4.40×1.20   @ (0, −0.30, 0) Transparency 1  Anchored ✔  CanCollide ✔  CollisionGroup NpcBody  [KIT, D-1: tight to the body]
├─ LowerTorso         MeshPart  1.90×0.70×1.00   @ (0, −0.25, 0)                                       [KIT]
│    ├─ Root           Motor6D   Part0 HumanoidRootPart   C0 (0, 0, 0)       C1 (0, +0.25, 0)
│    ├─ WaistCenterAttachment (0,0,0) · WaistFrontAttachment (0,0,−0.5) · WaistBackAttachment (0,0,+0.5)
├─ UpperTorso         MeshPart  2.20×1.30×1.10   @ (0, +0.40, 0)                                       [KIT]
│    ├─ Waist          Motor6D   Part0 LowerTorso         C0 (0, +0.35, 0)   C1 (0, −0.30, 0)
│    ├─ NeckAttachment (0,+0.65,0) · BodyFrontAttachment (0,0,−0.55) · BodyBackAttachment (0,0,+0.55)
│    ├─ LeftCollarAttachment (−0.90,+0.65,0) · RightCollarAttachment (+0.90,+0.65,0)
├─ Head               MeshPart  1.50×1.55×1.35   @ (0, +1.45, 0)                                       [KIT]
│    ├─ Neck           Motor6D   Part0 UpperTorso         C0 (0, +0.60, 0)   C1 (0, −0.45, 0)
│    ├─ HatAttachment (0,+0.775,0) · HairAttachment (0,+0.775,0) · FaceFrontAttachment (0,0,−0.675) · FaceCenterAttachment (0,0,0)
├─ RightUpperArm      MeshPart  0.75×1.00×0.75   @ (+1.45, +0.55, 0)                                   [KIT]
│    └─ RightShoulder  Motor6D   Part0 UpperTorso         C0 (+1.45, +0.55, 0)  C1 (0, +0.40, 0)
├─ RightLowerArm      MeshPart  0.70×0.90×0.70   @ (+1.45, −0.38, 0)                                   [KIT]
│    └─ RightElbow     Motor6D   Part0 RightUpperArm      C0 (0, −0.50, 0)   C1 (0, +0.43, 0)
├─ RightHand          MeshPart  0.75×0.70×0.75   @ (+1.45, −1.15, 0)                                   [KIT]
│    ├─ RightWrist     Motor6D   Part0 RightLowerArm      C0 (0, −0.45, 0)   C1 (0, +0.32, 0)
│    └─ RightGripAttachment (0, −0.10, −0.20)  (palm centre, +Z out of the fist)
├─ LeftUpperArm / LeftLowerArm / LeftHand        mirrored (x → −x); joints LeftShoulder / LeftElbow / LeftWrist; LeftGripAttachment
├─ RightUpperLeg      MeshPart  0.80×1.00×0.80   @ (+0.50, −1.05, 0)                                   [KIT]
│    └─ RightHip       Motor6D   Part0 LowerTorso         C0 (+0.50, −0.35, 0)  C1 (0, +0.45, 0)
├─ RightLowerLeg      MeshPart  0.75×0.90×0.75   @ (+0.50, −1.95, 0)                                   [KIT]
│    └─ RightKnee      Motor6D   Part0 RightUpperLeg      C0 (0, −0.50, 0)   C1 (0, +0.40, 0)
├─ RightFoot          MeshPart  0.80×0.60×1.10   @ (+0.50, −2.70, −0.15)  (toes lead by 0.15)          [KIT]
│    └─ RightAnkle     Motor6D   Part0 RightLowerLeg      C0 (0, −0.45, 0)   C1 (0, +0.30, +0.15)
├─ LeftUpperLeg / LeftLowerLeg / LeftFoot        mirrored; LeftHip / LeftKnee / LeftAnkle
├─ AnimationController                           (no Animator child until tracks are enabled)          [KIT]
├─ Face               Folder                                                                          [KIT]
│    ├─ EyeR    Part 0.30×0.32×0.16 @ head-rel (+0.33, +0.10, −0.645)   Motor6D FaceJoint (Part0 Head)
│    ├─ EyeL    Part 0.30×0.32×0.16 @ (−0.33, +0.10, −0.645)             FaceJoint
│    ├─ PupilR  Part 0.14×0.16×0.06 @ (+0.33, +0.08, −0.74)              FaceJoint
│    ├─ PupilL  Part 0.14×0.16×0.06 @ (−0.33, +0.08, −0.74)              FaceJoint
│    ├─ BrowR   Part 0.36×0.09×0.08 @ (+0.33, +0.36, −0.68)              FaceJoint
│    ├─ BrowL   Part 0.36×0.09×0.08 @ (−0.33, +0.36, −0.68)              FaceJoint
│    └─ Mouth   Part 0.34×0.07×0.06 @ (0, −0.30, −0.68)                  FaceJoint
├─ Hair               Folder
│    ├─ HairTousled   MeshPart  ≈1.62×0.70×1.48 @ HairAttachment, WeldConstraint → Head              [KIT]
│    └─ HatFloppyPinned MeshPart ≈2.30×0.95×2.30 @ HatAttachment, WeldConstraint → Head             [KIT]
├─ Outfit             Folder   (each: WeldConstraint → the part in attribute Bone)
│    ├─ TunicHem      MeshPart 2.10×0.60×1.15  Bone LowerTorso  @ (0, −0.45, 0)                       [KIT]
│    ├─ CloakYoke     MeshPart 2.40×0.55×1.25  Bone UpperTorso  @ (0, +0.75, 0)                       [KIT]
│    ├─ ScarfTail     MeshPart 0.45×1.60×0.20  Bone UpperTorso  @ (+0.85, −0.05, −0.62)  (hangs off the right collar) [KIT]
│    ├─ ToolBeltCollar MeshPart 2.15×0.30×1.20 Bone LowerTorso  @ (0, −0.05, 0)  (empty Chim collar modelled on the left hip) [GIA]
│    ├─ BracerR       MeshPart 0.80×0.50×0.80  Bone RightLowerArm @ (+1.45, −0.30, 0)                [KIT]
│    └─ BracerL       MeshPart 0.80×0.50×0.80  Bone LeftLowerArm  @ (−1.45, −0.30, 0)                [KIT]
└─ Props              Folder
     ├─ Cane          MeshPart ≈0.38×1.95×0.38  Grip RightHand  pivot = knob @ RightGripAttachment; shaft hangs −Y 1.75; tip at ground [KIT]
     └─ Bell          Part     0.30×0.28×0.30   WeldConstraint → Cane, @ knob +(0.22, −0.05, −0.10) on a 0.12 loop        [GIA]
```

Part count: HRP 1 + Collider 1 + body 15 + face 7 + hair/hat 2 + outfit 6 + props 2 = **34 BaseParts** (33 without the Collider). Joints: 15 body + 7 face = **22 Motor6D**; welds: 2 hair + 6 outfit + 2 props = 10 `WeldConstraint`.

## A3. Naming conventions

| Thing | Rule | Example |
|---|---|---|
| Root model | the existing code-contract name; never a "new" name | `StupidGianluca` |
| Body parts / joints | exact R15 names (parts) and R15 joint names (Motor6D) | `LeftUpperArm`, `LeftShoulder` |
| Face parts | `Eye{L,R}`, `Pupil{L,R}`, `Brow{L,R}`, `Mouth`, optional `Scar`, `Nose`; joints all named `FaceJoint` | |
| Overlays | PascalCase noun + side suffix where sided; attribute `Bone` names the parent bone | `BracerR`, `Bone = "RightLowerArm"` |
| Hair / hat | `Hair<Module>`, `Hat<Module>` | `HatFloppyPinned` |
| Props | PascalCase noun; attribute `Grip` ∈ `RightHand · LeftHand · Back · Waist · ShoulderL · ShoulderR` | `Cane`, `Grip = "RightHand"` |
| Attachments | Roblox standard names only (A2) | `RightGripAttachment` |
| Attributes on the root | `Npc*` prefix, documented in doc E | `NpcPack` |
| Tags | `NpcBody` only | |

## A4. Materials

| Part group | Material | Colour (RGB) | Class |
|---|---|---|---|
| Head, hands, lower arms | Plastic | skin 214,176,138 | [KIT] |
| UpperTorso, upper arms, TunicHem | Plastic | moss 98,140,70 | [KIT] |
| LowerTorso, ToolBeltCollar, BracerL/R | Plastic | leather 134,96,58 | [KIT] |
| Upper legs | Plastic | walnut 74,50,30 | [KIT] |
| Lower legs / feet | Plastic | boot 110,78,46 / dark boot 86,60,36 | [KIT] |
| CloakYoke | Plastic | cream 238,226,200 | [KIT] |
| ScarfTail | Plastic | berry 168,58,86 | [KIT] |
| HatFloppyPinned | Plastic | leaf 108,160,80 | [KIT] |
| HairTousled, BrowL/R | Plastic | chestnut 92,58,36 | [KIT] |
| EyeL/R | SmoothPlastic | 252,252,252 | [KIT] |
| PupilL/R | SmoothPlastic | 16,14,20 | [KIT] |
| Mouth | Plastic | 60,34,30 | [KIT] |
| Cane | Plastic | walnut 74,50,30 | [KIT] |
| Bell | SmoothPlastic | brass 196,150,72 | [GIA] |
| Collider, HRP | — | Transparency 1 | [KIT] |

Twelve colours, no textures, no Neon, no reflectance.

## A5. Face expressions (data; values are `FaceJoint.C0` deltas from rest and part sizes)

Default `worried`; `talking-worried` while in dialogue; `eyes-closed` on blink. Values are in Phase 2 kit C3.2 and are reproduced in `NpcFaceConfig` (doc E). Gianluca-specific: none beyond the default; **[OPT]** `excited` on the Chim hand-over needs one attribute write in `GianlucaClient` (quest client — decision D-3).

Brow sign rule (so the table is side-agnostic): `browOuterUp` is authored once; the forge applies `rotZ = +browOuterUp` on `BrowR` and `−browOuterUp` on `BrowL`.

## A6. Attachment points used

`RightGripAttachment` (cane) · `HairAttachment`, `HatAttachment` (hair, hat) · `RightCollarAttachment` (scarf anchor reference; the scarf is welded to UpperTorso) · `RootAttachment` (TalkPrompt host is the HRP itself, not an attachment).

## A7. Approximate dimensions — silhouette envelope

Width across the hat brim 2.30; across the shoulders (with yoke) 2.40; depth 1.35 (head) / 1.25 (yoke); height 5.23 + hat crown 0.35 = **5.58**; cane tip 0.15 in front of the right foot.

## A8. Triangle budget

| Component | Estimate (forge-voxel, greedy-merged) | Cap |
|---|---|---|
| 15 body meshes | ≈ 2,400 (limbs 60–200 each, head ≈ 450, torso ≈ 350) | |
| Face (7 boxes) | 84 | |
| Hair + hat | ≈ 500 | |
| 6 overlays | ≈ 600 | |
| Cane + bell | ≈ 150 | |
| **Total** | **≈ 3.7k** | **9k (Tier 2)** |

## A9. Collision / query / touch / anchoring rules

| Part | Anchored | CanCollide | CanQuery | CanTouch | CastShadow | Massless |
|---|---|---|---|---|---|---|
| HumanoidRootPart | **true** | false | false | false | false | — |
| Collider [decision D-1] | true | **true** | false | false | false | — |
| all body MeshParts | false (held by Motor6D) | false | false | false | Head/UpperTorso/LowerTorso **true**, rest false | true |
| Face parts | false (FaceJoint) | false | false | false | false | true |
| Hair / hat / overlays / props | false (WeldConstraint) | false | false | false | hat **true**, rest false | true |

Rules: every non-anchored part must have a joint/weld path to the HRP (NpcBudget check `orphanParts == 0`); nothing simulates because the root is anchored; no `Humanoid`, no constraints, no `BodyMover`s.

## A10. LOD behaviour (kit C8, Villager pack)

| Band | Tracks | Procedural | Gestures | Face |
|---|---|---|---|---|
| talking / prompt shown | — | every frame | talk set / greet | blink, gaze, mouth |
| ≤ 40 studs | — | every frame | on | blink, gaze |
| 40–90 | — | every 2nd frame | on | none |
| 90–140 | — | every 4th frame | off | none |
| > 140 / off-screen | — | off (pose held) | off | none |

He is one of ≤ 12 animated bodies; in the valley camp he is almost always in the near band, which is the point.

## A11. Dialogue / TalkPrompt compatibility

- `TalkPrompt` is the **existing instance**, moved into the new `HumanoidRootPart` by `NpcForge` (re-parenting keeps every property: `HoldDuration 0.5`, `MaxActivationDistance`, `RequiresLineOfSight`, `ActionText`, `ObjectText`). `GianlucaClient` does `gw:WaitForChild("StupidGianluca") › WaitForChild("HumanoidRootPart") › WaitForChild("TalkPrompt")` `[code]` — all three names hold.
- The new HRP is placed at the **old HRP's world CFrame** (E-2 records it), so range and facing are identical for the player.
- `MerchantDialog.Show("Gianluca", …, hrp, …)` anchors the walk-away check on the HRP `[code]` — unchanged.
- `InteractionPromptClient` draws the pill from the prompt — unchanged.
- The old scripts (`NpcRigLife/BodyLife/PropLife`) skip him automatically: no `Humanoid`.

## A12. Portrait compatibility

- `portraitSubject`: no `NPC` child → falls to "model owning a `HumanoidRootPart`" → the model itself `[code]`. If E-2 shows his crates/stall live *inside* `StupidGianluca`, `NpcForge` re-parents them to a sibling model `GianlucaCamp` (positions unchanged) so the portrait and the walk-up outline frame the person only — **a decision item (D-2)**, because it changes what the outline lights up.
- Framing: `target = HRP + 0.5 × HRP.Size.Y` = 1.0 stud above the root; head centre at +1.45 with a 1.55-tall head → head spans +0.68…+2.23; camera distance from `SPAN 4.6` at fov 26 → head-and-shoulders, as today.
- The clone filter keeps `BasePart/Model/Folder` and deletes `Motor6D`, `WeldConstraint`, `Attachment`, `AnimationController` `[code]`; every part is then anchored and driven by the per-frame CFrame copy — the rig, face and props all survive as loose posed parts. Face parts are plain Parts → kept.
- Pairing key is `name|position`; every part name in A2 is unique except mirrored pairs (`BracerL/R`), which differ in position. ✔

## A13. Component classification summary

| REUSABLE GLOBAL KIT | GIANLUCA-SPECIFIC | OPTIONAL POLISH |
|---|---|---|
| SR-Rig skeleton, 15 `standard` body meshes, Collider, face system + 8 expressions, `HairTousled`, `HatFloppyPinned`, `TunicHem`, `CloakYoke`, `ScarfTail`, `BracerL/R`, plain `ToolBelt` variant, `Cane`, ranger colour set, Villager pack, greet/talk hooks, LOD profile T2 | `ToolBeltCollar` (the empty Chim collar), `Bell`, `ringBell` gesture, Villager overrides (breathe 2.9 s, shift ±4°, look ±28°/5 s), rest lean +4°, `worried` default | `excited` beat on hand-over (needs D-3), bell sound (D-4), a second scarf colour role (berry + cream edge) if two-colour overlays are cheap, hat band as a separate colour |

## A14. Build order for `NpcForge` (what the recipe produces, in sequence)

1. Import the `standard` body GLB (15 named MeshParts) → `NpcForge.AssembleHuman` builds the skeleton (A2) at origin, HRP at (0, 3, 0).
2. Apply the `ranger` colour set, then Gianluca's colour overrides (A4).
3. Build the face at rest, apply `worried`.
4. Weld hair, hat, overlays, props from the library by `Bone`/`Grip` with the offsets in A2.
5. Apply the rest-pose overrides: Waist bend +4°, shoulders spread +10°, elbows swing +6° — written into the rest `C0` so the driver's "rest" is already his stance.
6. Set attributes/tag; `NpcBudget.report` → PASS required.
7. Park in `ServerStorage.NpcStaging.Valley.StupidGianluca` **without** the TalkPrompt (the live prompt is only moved at the live swap, Phase 3 gate 6).
