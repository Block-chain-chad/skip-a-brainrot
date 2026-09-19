# C — Global NPC Base Kit ("SR-Rig v1")

**Lane:** NPC-01 · **Phase 2 design package** · 2026-09-19 · design only — nothing built, nothing in Studio.
**Decisions honoured:** procedural / Motor6D-driven motion for the prototypes (no uploaded AnimationIds); one reusable skeleton; AnimationController-compatible; modular idle/gesture data; distance/offscreen culling; a clean hook for uploaded clips later.

Source tags as in the Phase 1 report: `[code]` verified in the live-script mirror, `[doc]` a prior team audit, `[studio]` needs the Studio window (see E).

---

## C0. What the kit is, in one paragraph

Every human NPC is the **same skeleton** (R15 joint and part names on Motor6D, `HumanoidRootPart` anchored, no Humanoid, no physics) wearing **one of three shared body-mesh sets**, a **7-part cube face** driven by an expression table, **hair/hat and clothing overlays welded to named bones**, and **props welded to named grip attachments**. All motion is produced on the **client** by one LocalScript (`NpcLifeClient`) that evaluates **data-defined idle layers and gestures** from `NpcMotionConfig` and writes them into each joint's `C0`. When uploaded animation assets become possible, the same pack tables gain `asset` fields and a second pose source plays them through the rig's `Animator` — nothing about the rig, the data layout, the culling or the face changes. Story brainrots use the same driver with a creature profile and no skeleton.

---

## C1. Rig structure

### C1.1 Instance tree (exact)

```
<RootModel>                         -- the code-contract name (e.g. StupidGianluca) or the stall's child "NPC"
│  PrimaryPart = HumanoidRootPart
│  tag  NpcBody
│  attr NpcRig = "SR1", NpcTier = 1|2|3, NpcPack = "Villager", NpcWorld = "Valley",
│       NpcBodyType = "standard"|"stout"|"slight", NpcScale = 1.0, NpcFace = "friendly"
│  ModelStreamingMode = Atomic      -- a body never streams in half-dressed
├─ HumanoidRootPart   Part 2×2×1 · Transparency 1 · Anchored TRUE · CanCollide/CanQuery/CanTouch false
│    RootAttachment
│    (Gianluca only: TalkPrompt stays here — existing contract)
├─ LowerTorso         MeshPart  ·  Motor6D "Root"          (Part0 HumanoidRootPart, Part1 LowerTorso)
│    WaistFrontAttachment · WaistBackAttachment · WaistCenterAttachment
├─ UpperTorso         MeshPart  ·  Motor6D "Waist"         (Part0 LowerTorso)
│    NeckAttachment · LeftCollarAttachment · RightCollarAttachment · BodyFrontAttachment · BodyBackAttachment
├─ Head               MeshPart  ·  Motor6D "Neck"          (Part0 UpperTorso)
│    HatAttachment · HairAttachment · FaceFrontAttachment · FaceCenterAttachment · CameraAnchor (Tier 3)
├─ LeftUpperArm       MeshPart  ·  Motor6D "LeftShoulder"  (Part0 UpperTorso)
├─ LeftLowerArm       MeshPart  ·  Motor6D "LeftElbow"     (Part0 LeftUpperArm)
├─ LeftHand           MeshPart  ·  Motor6D "LeftWrist"     (Part0 LeftLowerArm) · LeftGripAttachment
├─ RightUpperArm / RightLowerArm / RightHand   (RightShoulder / RightElbow / RightWrist) · RightGripAttachment
├─ LeftUpperLeg       MeshPart  ·  Motor6D "LeftHip"       (Part0 LowerTorso)
├─ LeftLowerLeg       MeshPart  ·  Motor6D "LeftKnee"      (Part0 LeftUpperLeg)
├─ LeftFoot           MeshPart  ·  Motor6D "LeftAnkle"     (Part0 LeftLowerLeg)
├─ RightUpperLeg / RightLowerLeg / RightFoot   (RightHip / RightKnee / RightAnkle)
├─ AnimationController          -- no Animator child until the track source is enabled (C7.7)
├─ Face   (Folder)  EyeL EyeR PupilL PupilR BrowL BrowR Mouth — Parts, each with Motor6D "FaceJoint" (Part0 Head, Part1 itself)
├─ Hair   (Folder)  0–2 MeshParts, WeldConstraint → Head
├─ Outfit (Folder)  overlay MeshParts, WeldConstraint → the part named in attr Bone
└─ Props  (Folder)  MeshParts/Parts, WeldConstraint → the part named in attr Grip (RightHand / LeftHand / UpperTorso / LowerTorso)
```

Conventions:
- Each body Motor6D lives **in its Part1** (`Head.Neck`, `UpperTorso.Waist`, `LowerTorso.Root`, `LeftUpperArm.LeftShoulder` …) — the R15 layout every rig tool expects.
- `C0` = the joint pivot in Part0 space, `C1` = the same pivot in Part1 space. The **rest pose** is authored in `C0/C1`; the driver captures `rest[joint] = C0` at adopt time and writes `C0 = rest * offset` (C7.3). `Transform` is left to the Animator — the game already measured that an Animator overwrites `Transform` in every phase but `Stepped` `[code: ClientMain]`; writing `C0` sidesteps that entirely and lets authored tracks compose on top later.
- Every part except the HRP is **unanchored** and held only by its Motor6D. With the root anchored the assembly is kinematic: no simulation, no drift, no welds-by-distance, no constraints — the failure modes `NpcRigLife` fought `[code]`.
- Flags on every part: `CanCollide/CanQuery/CanTouch = false`, `Massless = true`, `CastShadow = true` only on Head/UpperTorso/LowerTorso (silhouette shadow, cheap), `false` elsewhere.
- **No Humanoid.** The legacy scripts (`NpcRigLife`, `NpcBodyLife`, `NpcPropLife`) key on `FindFirstChildOfClass("Humanoid")` `[code]` and therefore never touch an SR-Rig; `MerchantDialog.portraitSubject` and `NpcFocusClient.targetOf` accept a model that owns a `HumanoidRootPart` `[code]`, which this does. Coexistence is by construction.

### C1.2 Proportions — `standard` body type, scale 1, ground at y = 0

| Part | Size X × Y × Z (studs) | Centre y | Joint pivot (height, x) |
|---|---|---|---|
| HumanoidRootPart | 2.00 × 2.00 × 1.00 | 3.00 | — |
| LowerTorso | 1.90 × 0.70 × 1.00 | 2.75 | Root @ 3.00 |
| UpperTorso | 2.20 × 1.30 × 1.10 | 3.40 | Waist @ 3.10 |
| Head | 1.50 × 1.55 × 1.35 | 4.45 | Neck @ 4.00 |
| Upper arm (L/R) | 0.75 × 1.00 × 0.75 | 3.55 | Shoulder @ 3.95, x ±1.45 |
| Lower arm | 0.70 × 0.90 × 0.70 | 2.62 | Elbow @ 3.05 |
| Hand | 0.75 × 0.70 × 0.75 | 1.85 | Wrist @ 2.17 |
| Upper leg (L/R) | 0.80 × 1.00 × 0.80 | 1.95 | Hip @ 2.40, x ±0.50 |
| Lower leg | 0.75 × 0.90 × 0.75 | 1.05 | Knee @ 1.45 |
| Foot | 0.80 × 0.60 × 1.10 | 0.30 | Ankle @ 0.60 |

- Total height **5.23 studs**, **3.4 heads tall**; head sinks 0.38 into the shoulders (neck almost absent — deliberate).
- **Portrait line:** head centre is **1.45 studs above the HRP centre**, matching the ≈ 1.48 measured on the current rigs `[code: NpcBodyLife]` and what `MerchantDialog` frames (`target = HRP + HRP.Size.Y × 0.50` `[code]`). Any character that is much taller or shorter uses `Model:ScaleTo` on the whole root model, never a moved head.
- Rest pose: arms hang with shoulders rolled 8° outward (no torso clipping), elbows 6° bent, feet 0.15 apart, head level.

| Body type | Differences from `standard` | Used for |
|---|---|---|
| `stout` | UpperTorso 2.50 × 1.30 × 1.25, LowerTorso 2.20 × 0.70 × 1.10, upper arms 0.85 wide | merchants, guards, the Appraiser |
| `slight` | UpperTorso 1.90 × 1.25 × 0.95, LowerTorso 1.70 × 0.65 × 0.90, arms 0.65 wide | scavengers, youths, elders (`ScaleTo 0.95` + stooped overlay) |
| child | `slight` at `NpcScale 0.78` | Tino |

### C1.3 Attachment set (names are the Roblox standard so tools and the prop kit agree)

`RootAttachment` (HRP) · `WaistCenter/Front/BackAttachment` (LowerTorso) · `NeckAttachment`, `LeftCollarAttachment`, `RightCollarAttachment`, `BodyFrontAttachment`, `BodyBackAttachment` (UpperTorso) · `HatAttachment`, `HairAttachment`, `FaceFrontAttachment`, `FaceCenterAttachment` (Head) · `LeftGripAttachment`, `RightGripAttachment` (Hands, palm-centre, +Z out of the fist) · Tier 3 only: `CameraAnchor` (Head, 0.4 studs in front of the face, for cutscene framing).

---

## C2. Shared meshes

One colour per MeshPart (the forge's own rule: "a role is a MeshPart"), so an outfit is mostly a **colour set**; overlays exist only where the silhouette changes.

| Mesh | Shared by | Count |
|---|---|---|
| `Head` | every human (Tier 3 may replace) | 1 |
| `UpperTorso_standard/_stout/_slight` | per body type | 3 |
| `LowerTorso_standard/_stout/_slight` | per body type | 3 |
| `UpperArm_standard/_stout/_slight` (symmetric — same mesh both sides) | per body type | 3 |
| `LowerArm`, `Hand` (mitt, symmetric) | every human | 2 |
| `UpperLeg`, `LowerLeg`, `Foot` (symmetric) | every human | 3 |
| **Total base meshes** | | **15** |

Symmetric limb meshes are authored mirror-symmetric about their own centre so left and right use one asset (Roblox cannot negative-scale a mesh).

### C2.1 Mesh production route (prototype vs final)

| Route | How | Fits | Recommended for |
|---|---|---|---|
| **Forge-voxel** (in-house, no Blender) | author each body type as one `VoxelModel` whose *roles are the 15 segments* (`tools/brainrot_forge/voxel.py`; pitch 0.2, ~26 cells tall) or block it out as Parts in Studio and run `ingest_parts.py` → `bake.py` → `export_glb.py` → File › Import 3D → `NpcForge.AssembleHuman` (C9) | the Darrel bust / tundra-brainrot voxel look the owner has approved three times `[doc]`; greedy meshing keeps a segment at a few hundred triangles | **the prototypes** |
| **Modelled low-poly** | Blender (or AI mesh + decimation) → GLB with the 15 named objects → Import 3D → same assembler | the pack's smoother "Blender primitives" look | a later polish pass; a content swap, no rig/driver change |

Tooling deltas for the forge route (Phase 3, small): an `npc` gate profile in `voxel.py` (`MAX_ROLES` 16 instead of 10, `MIN_BODY_SHARE` off, height gate 24–30 cells) and a segment-pivot field in the manifest so the assembler knows each joint's pivot. The bake/export/import steps are unchanged.

---

## C3. Face system ("VoxelFace-H")

Seven Parts under `Face`, each on a `FaceJoint` Motor6D to the Head, following `VoxelFace`'s three rules `[code]`: **cube eyes, recessed, sized off the head**. No decals, no textures, no uploads. Expression = a table of per-part offsets; blink and talk are size writes; gaze is a pupil offset.

### C3.1 Parts (relative to the Head centre; head front face at z = −0.675)

| Part | Size | Rest centre (x, y, z) | Colour | Notes |
|---|---|---|---|---|
| `EyeL` / `EyeR` | 0.30 × 0.32 × 0.16 | (∓0.33, +0.10, −0.62) | white (252,252,252) | recessed: only the front 0.05 proud of the head |
| `PupilL` / `PupilR` | 0.14 × 0.16 × 0.06 | (∓0.33, +0.08, −0.71) | ink (16,14,20) | gaze moves these |
| `BrowL` / `BrowR` | 0.36 × 0.09 × 0.08 | (∓0.33, +0.36, −0.66) | hair colour | rotation about Z = emotion |
| `Mouth` | 0.34 × 0.07 × 0.06 | (0, −0.30, −0.66) | (60,34,30) | width/height = emotion; height oscillates while talking |

Optional 8th part `Scar` (0.06 × 0.40 × 0.04, dark, across one cheek) for `battle-worn`; the elder set adds a `Nose` bump (0.16 cube). Materials `SmoothPlastic` (eyes), `Plastic` (brows, mouth).

### C3.2 Expression table (brow rotation: + = outer end up; per side)

| Expression | BrowL / BrowR rot | Brow y | Eye sizeY | Pupil y | Mouth sizeX | Mouth y | Mouth sizeY |
|---|---|---|---|---|---|---|---|
| `friendly` | +8 / +8 | +0.36 | 0.32 | +0.08 | 0.44 | −0.28 | 0.07 |
| `worried` | −16 / −16 (inner ends up) | +0.40 | 0.34 | +0.06 | 0.24 | −0.33 | 0.10 |
| `stern` | +14 / +14 (inner ends down) | +0.30 | 0.26 | +0.08 | 0.36 | −0.31 | 0.06 |
| `suspicious` | +16 / −4 (one low, one high) | +0.28 / +0.40 | 0.22 / 0.30 | pupils x −0.04 | 0.30 (rot +8°) | −0.31 | 0.06 |
| `old` | 0 / 0, brow sizeY 0.12 | +0.32 | 0.22 (heavy lids) | +0.06 | 0.30 | −0.34 | 0.07 |
| `tired` | +2 / +2 | +0.30 | 0.20 | +0.04 | 0.28 | −0.34 | 0.06 |
| `excited` | +6 / +6 | +0.44 | 0.36 | +0.08, pupils 0.16 square | 0.46 | −0.27 | 0.14 (open) |
| `battle-worn` | `stern` + `Scar` part | | 0.26 | | 0.36 | −0.31 | 0.06 |
| `talking-<expr>` | same brows | | | | ×1.05 | | oscillates 0.07 ↔ 0.16 at 6–8 Hz, irregular |
| `eyes-closed` | as current | | 0.05 | pupils hidden (0.01) | | | |

The one thing a single-bar mouth cannot draw is smile/frown curvature; brows and mouth width carry the emotion exactly as they do on the creatures. If the owner wants curvature later, `Mouth` becomes three parts (centre + two 25°-rotatable ends) — a table change, not a system change.

### C3.3 Face behaviours (driver, near band only)

- **Blink:** every 3–6 s (hashed), `EyeL/R.Size.Y → 0.05` and pupils `→ 0.01` for 0.12 s.
- **Gaze:** when the local player is within 20 studs and in front (dot > 0.3), pupils shift toward the player's head, clamped x ±0.06 / y ±0.04, updated at 10 Hz. NPCs that are looking at you is the cheapest "alive" signal in the kit.
- **Talk:** while the NPC is in conversation (C7.6), mouth height oscillates and the `talking-` variant is applied; restored on end.
- **Set expression:** `NpcFace` attribute; the driver applies the table on change (event-driven — zero per-frame cost when idle).

---

## C4. Hair / headwear slots

Two slots, both welded to `Head`: **Hair** (`HairAttachment`) and **Hat** (`HatAttachment`). One mesh each; hair meshes are cut to clear the face parts (nothing crosses the brow line lower than y +0.48). Hood counts as Hat. Beards are a Hair-slot *second* mesh welded at the jaw (so any head can age).

| Module | Meshes (launch set) |
|---|---|
| short | crop · side-part · curls |
| long | straight-back · side braid · bun-with-fall |
| messy | tousled · wind-swept |
| tied | ponytail · top-knot · headscarf-tied |
| old / grey | thinning · swept-back · chest beard · chin beard · mustache |
| helmets | round miner's (+lamp) · open-face guard · dented kettle · pilot cap |
| hats | wide ranger brim · **floppy brim, one side pinned** · knit cap · fur-trim hood · flat cap · straw trader's hat · jeweller's visor |

≈ 20 meshes total; budget 1 hair + 1 hat (+1 beard) per NPC.

---

## C5. Clothing families

A family = **a colour set for the 15 body parts** + **an overlay list**. Overlays are MeshParts welded to one bone (`Bone` attribute), cut 0.05–0.10 studs proud of the body, one colour each.

### C5.1 Overlay slots

| `Bone` | Overlay pieces |
|---|---|
| UpperTorso | vest · jacket body · tunic hem-top · cuirass plate · apron bib · cloak yoke (+scarf variant) · collar · sash · pauldron (L/R) |
| LowerTorso | tunic hem / coat skirt (front, back) · belt · tool belt (+pouches) · kilt · apron skirt · satchel strap |
| Upper arm L/R | sleeve cuff · arm wrap · rolled-sleeve edge |
| Lower arm L/R | bracer · glove cuff · bandage |
| Upper leg L/R | knee pad · trouser patch |
| Foot L/R | boot top · sandal strap |
| Head | hood · goggles-on-brow · headlamp band |

### C5.2 Families (colour sets: skin · base cloth · accent · seam · leather/metal)

| Family | Colours | Typical overlays | World |
|---|---|---|---|
| village | tan (214,176,138) · cream (238,226,200) · berry (168,58,86) or leaf (108,160,80) · walnut (74,50,30) · leather (134,96,58) | vest, belt, rolled sleeve, sandal strap | 1 |
| ranger | tan · moss (98,140,70) · cream · dark bark (58,40,24) · leather | tunic hem, cloak yoke, bracer, boot top, tool belt | 1 |
| merchant | tan · shop colour (Rocco gold 255,216,96 / Enzo violet 198,142,255 / Marco amber / Gino cream / Lil Miss pink 232,150,176) · ivory · walnut · leather | apron bib + skirt, sleeve cuff, sash | 1 base; 2 and 3 cuts |
| winter | pale (228,206,186) · blue-grey (96,116,140) · fur cream (226,214,196) · charcoal (44,46,52) · leather | jacket body + fur collar, coat skirt, glove cuff, boot top, hood | 2 |
| engineer | tan · oil-blue (58,84,110) · brass (196,150,72) · charcoal · leather | apron bib, bracer, tool belt, goggles-on-brow | 2, 3 |
| castle | pale · slate (108,112,120) · brass · iron (96,98,104) · leather | cuirass plate, pauldron, kilt, bracer | 3 |
| underground survivor | pale-grey (206,196,186) · patched grey (118,118,112) / ochre (190,146,72) · rust (150,74,44) · soot (52,50,48) · leather | tunic (patched), arm wrap, knee pad, satchel strap, headlamp band | 3 |
| miner | pale-grey · ochre · lamp brass · soot · leather | leather apron skirt, bracer, boot top, headlamp band | 3 |
| scavenger | pale-grey · two mismatched accents (rust + grey) · soot · leather | torn-hem jacket, tool belt, bandage, goggles-on-brow | 3 |
| noble | pale · deep jewel (64,42,110) · gold (255,196,64) · midnight (28,26,40) · — | cloak yoke, sash, high collar, long coat skirt | Trading, 3 (Keeper) |
| trader | tan · shell white (245,250,250) / turquoise (54,224,214) · gold · coral (255,116,96) · — | gem-studded vest, sash, satchel strap, sleeve cuff | Trading |

Caps: ≤ 4 overlays on Tier 1, ≤ 6 on Tier 2, ≤ 9 on Tier 3. "Patched" is modelled into one mesh, never extra parts.

---

## C6. Prop attachment system

- A prop is a MeshPart or a ≤ 3-part assembly whose **pivot is its grip point**. It carries attribute `Grip = "RightHand" | "LeftHand" | "UpperTorso" | "LowerTorso"` and is placed at the matching attachment (`RightGripAttachment`, `LeftGripAttachment`, `BodyBackAttachment`, `WaistBackAttachment`) then **welded** (`WeldConstraint`) to that part.
- Props are never anchored and never written per frame: **the arm carries them**. This retires `NpcPropLife`'s approach (server, per-frame, anchored parts) `[code]`.
- Lights: at most one `PointLight` per lantern, `Enabled` by the driver only ≤ 70 studs (the brainrot FX rule `[doc]`).
- Kit (launch): lantern ×3 sizes · sword (+ sheathed) · spear · book/ledger · pickaxe · backpack (patched / trader) · map/scroll · staff · walking cane (+ bell variant) · wrench · hammer · satchel · spyglass · gem pouch · gem tray (+ scale) · shop props: rock, potion vial, coin stack, egg, charm. ≈ 22 meshes.

---

## C7. Animation driver — `NpcLifeClient`

### C7.1 Files

| Instance | Kind | Role |
|---|---|---|
| `ReplicatedStorage.Modules.NpcKit.NpcRigSpec` | ModuleScript (data) | joint list, rest-pivot table per body type, attachment names, face part spec |
| `ReplicatedStorage.Modules.NpcKit.NpcMotionConfig` | ModuleScript (data) | packs: idle layers, gestures, greet, talk, creature presets; `USE_TRACKS` flag |
| `ReplicatedStorage.Modules.NpcKit.NpcFaceConfig` | ModuleScript (data) | the expression table (C3.2) |
| `ReplicatedStorage.Modules.NpcKit.NpcMotion` | ModuleScript (pure functions) | evaluate layers/gestures at time *t* → `{ [joint] = CFrame offset }` |
| `StarterPlayer.StarterPlayerScripts.NpcLifeClient` | LocalScript | registry, bands, one Heartbeat, pose sources, face, hooks |
| `ServerStorage.NpcForge` | ModuleScript (build-time) | assembles rigs (C9); never required at runtime |
| Server at runtime | — | **nothing** |

### C7.2 Registry and lifecycle

- `CollectionService:GetTagged("NpcBody")` + `GetInstanceAddedSignal/RemovedSignal` (the `BrainrotIdleClient` pattern `[code]`).
- Adopt: read attributes; resolve joints by name; capture `rest[joint] = C0`; resolve face parts; compute `phase = hash(model.Name, pivot.Position)` (identical on every client, stable across sessions — `BrainrotIdleClient.phaseFor` verbatim).
- Drop on tag removed or `AncestryChanged` to nil; a body that streams back in is a new instance and is re-adopted with a fresh rest capture.

### C7.3 Pose sources (the swap hook)

```
PoseSource (interface)
  :begin(entry)         -- called on adopt
  :evaluate(entry, t, dt, band) -> { [jointName] = CFrame }   -- offsets in pivot space
  :playGesture(entry, gestureDef) / :isBusy(entry)
  :finish(entry)

ProceduralSource   -- Phase 2/3: evaluates NpcMotionConfig layers + keyframe gestures; applies via joint.C0 = rest * offset
TrackSource        -- later: for any layer/gesture carrying `asset` (rbxassetid) or `sequence` (a KeyframeSequence in
                   --        ReplicatedStorage.NpcAnimations, registered per client with KeyframeSequenceProvider),
                   --        creates the Animator under the AnimationController and plays a track (Transform).
```

Selection rule per layer/gesture: `if NpcMotionConfig.USE_TRACKS and def.asset (or def.sequence) then TrackSource else ProceduralSource`. Both may be live on one rig: tracks own `Transform`, the procedural layers own `C0`; they compose (`joint = Part0 * C0 * Transform * C1⁻¹`). A pack may set `layersWithTracks = false` to silence its procedural idle once an authored idle exists. **Flipping `USE_TRACKS` and adding ids is the entire migration.**

### C7.4 Pack data format (`NpcMotionConfig`)

```lua
local D = math.rad
M.Packs.Villager = {
  idle = {   -- always-on layers, summed per joint
    { joint = "Waist",  axis = "pitch", amp = D(1.5), period = 3.4, kind = "sine" },                 -- breathe (chest lift)
    { joint = "Neck",   axis = "pitch", amp = D(-0.4), period = 3.4, kind = "sine" },                -- head stays level
    { joint = "Root",   axis = "roll",  amp = D(2.5), period = 9.0, kind = "sine" },                 -- weight shift
    { joint = "Root",   axis = "y",     amp = 0.03,   period = 9.0, kind = "sine", phase = 0.25 },
    { joint = "LeftHip",  axis = "roll", amp = D(-2.5), period = 9.0, kind = "sine" },               -- legs stay planted
    { joint = "RightHip", axis = "roll", amp = D(-2.5), period = 9.0, kind = "sine" },
    { joint = "Neck",   axis = "yaw",   amp = D(22),  period = 6.5, kind = "snap", ease = 0.18 },    -- look around (snap-and-hold)
    { joint = "Waist",  axis = "yaw",   follow = "Neck.yaw", gain = 0.3 },                           -- body follows the head a little
  },
  gestures = {  -- scheduled by weight, cooldown range in seconds; keys are smoothstep-eased; degrees / studs
    minorGesture = { weight = 2, cooldown = {12, 20}, duration = 1.2,
      keys = { {t=0}, {t=0.4, RightShoulder={pitch=-25}, RightElbow={pitch=-40}}, {t=0.8, RightShoulder={pitch=-25}, RightElbow={pitch=-40}}, {t=1.2} } },
    handsOnHips = { weight = 1, cooldown = {20, 40}, duration = 6.0, hold = true,
      keys = { {t=0}, {t=0.6, LeftShoulder={pitch=-20, roll=35}, LeftElbow={pitch=-95}, RightShoulder={pitch=-20, roll=-35}, RightElbow={pitch=-95}}, {t=5.4, ...same}, {t=6.0} } },
    talkGesture = {...}, inspectItem = {...}, glanceAtLandmark = {...},
  },
  greet = "wave",                       -- played once on PromptShown
  talk  = { nod = {...}, armGesture = {...}, every = {4, 7} },
  -- future: any entry may add  asset = "rbxassetid://…"  or  sequence = "Villager_idle"
}
```

Axes: `pitch/yaw/roll` (degrees, about the joint pivot) and `x/y/z` (studs). Kinds: `sine`, `snap` (snap-and-hold with hashed targets — Michael's bird pattern `[code: NpcIdle.snapYaw]`), `follow` (a fraction of another layer), `pulse` (a bump every `period` seconds, for shivers/settles). Gestures are keyframe lists; missing joints hold their previous value; the last key returns everything to zero unless `hold`.

Packs at launch: `Background`, `Villager`, `Guard`, `Merchant`, `Survivor`, `Creature` (brainrot presets `bob/sway/hover/spin/shiver/breathe/glance`), plus per-character `Story_<Name>` packs for Tier 3.

### C7.5 Scheduler

- One `Heartbeat`. Every 10 frames: rank bodies by camera distance, assign bands (C8), pick the animated set (nearest ≤ 12).
- Per animated body per frame: `offsets = source:evaluate(...)`; for each joint `C0 = rest[joint] * offsets[joint]` (≤ 8 joints touched by a pack; untouched joints are skipped entirely).
- Gestures: when no gesture is running and the cooldown has elapsed, pick by weight with the hashed RNG (deterministic across clients). Gesture offsets add to idle offsets.
- Everything is **absolute from the captured rest** — never read-current-and-add (the drift bug both `NpcIdle` and `NpcBodyLife` document `[code]`).

### C7.6 Hooks into existing systems (no edits to locked files)

| Event | Source | Driver behaviour |
|---|---|---|
| walk-up | `ProximityPromptService.PromptShown(prompt)` — resolve the prompt's root model; if tagged `NpcBody` | play `pack.greet` once; set gaze priority; `PromptHidden` → return to idle |
| conversation start | `PromptTriggered` on that prompt **and** `PlayerGui.MerchantDialogUI.DialogRoot.Visible` becomes true within 1 s `[code: MerchantDialog builds exactly this ScreenGui/Frame]` | set `talking` on that NPC: talking face, mouth oscillation, talk gestures; band forced to *near* |
| conversation end | `DialogRoot.Visible` → false, or distance > 24 studs (the dialogue's own walk-away rule) | clear `talking`, restore expression |
| portrait | `MerchantDialog` copies live part CFrames each frame | works unchanged — joints move the parts in world space |
| outline | `NpcFocusClient` adorns the `NPC` child / HRP-owning model | unchanged |
| custom prompt pill | `InteractionPromptClient` | unchanged (it reads prompts, not bodies) |
| expression from quest state | quest clients may set attribute `NpcFace` on the model (e.g. Gianluca `excited` on `Note == "key"`) — an optional one-line addition in *unlocked* files, never required | apply table |

### C7.7 Future track source — what is pre-wired now

- `AnimationController` is already in the rig; the Animator is created on first `LoadAnimation`.
- Pack entries accept `asset` / `sequence`; `USE_TRACKS` defaults `false`.
- `ReplicatedStorage.NpcAnimations` (Folder) is reserved for `KeyframeSequence`s exported from the Animation Editor **into the place**, registered per client via `KeyframeSequenceProvider:RegisterKeyframeSequence` — a no-upload path to test *before* any account decision (Studio checklist E-11).
- Uploaded ids, when the owner account can provide them, go in the same fields. **Nothing is uploaded from the wrong account in any phase.**

### C7.8 Coexistence and retirement

- Legacy: Humanoid rigs only (`NpcRigLife/BodyLife/PropLife`), path-listed part models (`NpcIdle`). New: `NpcBody`-tagged models only. A body is never in both.
- Each migrated NPC removes one entry from the legacy scripts' reach automatically (no Humanoid → skipped). When the last Humanoid NPC is gone the four server scripts are disabled, then deleted (Phase 5 of the Phase 1 order).

---

## C8. LOD / culling rules

| Band (distance from the local camera) | Tracks | Procedural layers | Gestures | Face | Lights |
|---|---|---|---|---|---|
| in conversation / prompt shown | full | every frame | on + talk set | blink, gaze, talk | on |
| ≤ 40 | full | every frame | on | blink, gaze | on |
| 40–90 | full | every 2nd frame | on | none | on (≤ 70) |
| 90–140 | `AdjustSpeed(0.5)` | every 4th frame | off | none | off |
| > 140, or off-screen (`WorldToViewportPoint` outside + dot < −0.2) | `AdjustSpeed(0)` (pose held) | off | off | none | off |
| streamed out | dropped | — | — | — | — |

- Budget: **≤ 12 bodies animated per frame** (nearest first); the rest hold their last pose (the `BUDGET` rule `[code: BrainrotIdleClient]`).
- Per body per frame ceiling: ≤ 8 `C0` writes, ≤ 2 running tracks; face writes only on events.
- Server: never animates, never writes NPC CFrames. Replication cost of the whole NPC cast: **zero per frame.**
- Determinism: phases and gesture picks hashed, so all clients see the same performance without any network traffic.

---

## C9. Build-time assembler — `NpcForge` (ServerStorage, never at runtime)

`NpcForge.AssembleHuman(importRoot, spec) → Model` (modelled on `BrainrotForge.Assemble` `[code]`):
1. Find the 15 named segment parts under the import root (or a Parts blockout), verify names/count.
2. Create `HumanoidRootPart`, set sizes/positions from `NpcRigSpec` for the body type, set flags.
3. Create the 15 Motor6Ds with `C0/C1` from the pivot table; parent each in its Part1.
4. Add attachments (C1.3), the `Face` folder with the 7 parts + `FaceJoint`s at rest, `AnimationController`, folders `Hair/Outfit/Props`.
5. Apply the family colour set; weld the requested overlays/hair/props by `Bone`/`Grip`.
6. Set attributes and the `NpcBody` tag; `PrimaryPart`; `ModelStreamingMode = Atomic`.
7. Run `NpcBudget.report` (the `BrainrotBudget` pattern + `motor6d`, `animationController`, `faceParts`, `overlays`, `props`, `lights`) — **FAIL blocks parenting into any world folder.**
8. Park the result in `ServerStorage.NpcStaging.<World>` — placement into a world is a separate, owner-approved step (or another lane's).

`NpcForge.AssembleCreature(templateName, storyLayerSpec)` does the brainrot equivalent (B-spec).

---

## C10. Budgets (revised from Phase 1 — the face is 7 parts, so the caps moved)

| Per NPC | Tier 1 | Tier 2 | Tier 3 |
|---|---|---|---|
| BaseParts total | ≤ 30 | ≤ 38 | ≤ 50 |
| of which base body + face | 16 + 7 = 23 | 23 | 23 (+ bespoke head) |
| overlays + hair/hat + props | ≤ 7 | ≤ 15 | ≤ 27 |
| non-library meshes (bespoke) | 0 | ≤ 3 | ≤ 8 |
| triangles | ≤ 5k | ≤ 9k | ≤ 16k |
| emitters / lights | 0 / 0 | ≤ 2 / ≤ 1 | ≤ 6 / ≤ 1 |
| scripts | 0 | 0 | 0 |
| Motor6D | 22 (15 body + 7 face) | 22 | ≤ 27 |

Per world: ≤ 24 bodies live, ≤ 12 animated per frame, ≤ 1,200 NPC BaseParts, ≤ 8 NPC lights.

---

## C11. Out of scope for the kit (deliberately)

Walking/pathing (no Humanoid, no NavMesh — the World 3 audit already rules it out `[doc]`), catalog `Shirt/Pants/Accessory`, dynamic heads, per-NPC scripts, server-side motion, Highlights on NPCs, and any edit to the round-3 locked UI files.
