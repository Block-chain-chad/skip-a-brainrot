# E — NpcForge: data-driven NPC construction

**Lane:** NPC-01 · Phase 2.5 · 2026-09-19 · architecture spec (no code committed to `game-src`). Written so another developer can implement it without this conversation.

**Principle:** an NPC is a **recipe** (a Lua table) that references library ids. `NpcForge.Build(recipeId)` turns the recipe into a Model at build time in Studio. Runtime code (`NpcLifeClient`) reads the same data modules for motion, faces and LOD. **No per-NPC scripts, no per-NPC code paths.** Adding an NPC = adding a recipe; adding a look = adding a library entry.

## E1. Modules and where they live

| Module | Location | Kind | Read by |
|---|---|---|---|
| `NpcRigSpec` | `ReplicatedStorage.Modules.NpcKit.NpcRigSpec` | data | NpcForge, NpcLifeClient (joint list, rest pivots) |
| `NpcFaceConfig` | `…NpcKit.NpcFaceConfig` | data | NpcForge (build face), NpcLifeClient (expressions) |
| `NpcLibrary` | `…NpcKit.NpcLibrary` | data | NpcForge (meshes, props, hair, overlays) |
| `NpcFamilies` | `…NpcKit.NpcFamilies` | data | NpcForge (colour sets, default overlays) |
| `NpcWorldThemes` | `…NpcKit.NpcWorldThemes` | data | NpcForge (palette shifts, accents, light rules) |
| `NpcMotionConfig` | `…NpcKit.NpcMotionConfig` | data | NpcLifeClient (packs, gestures, `USE_TRACKS`) |
| `NpcLodProfiles` | `…NpcKit.NpcLodProfiles` | data | NpcLifeClient |
| `NpcCharacters` | `…NpcKit.NpcCharacters` (folder of ModuleScripts, one per character) | data | NpcForge; NpcLifeClient reads only the attributes the forge stamped |
| `NpcMotion` | `…NpcKit.NpcMotion` | pure functions | NpcLifeClient |
| `NpcLifeClient` | `StarterPlayer.StarterPlayerScripts.NpcLifeClient` | LocalScript | — |
| `NpcForge` | `ServerStorage.NpcForge` | ModuleScript, **build-time only** | command bar / MCP in Edit mode |
| `NpcBudget` | `ServerStorage.NpcBudget` | ModuleScript, build-time | NpcForge (gate) |
| `NpcAnimations` | `ReplicatedStorage.NpcAnimations` | Folder (KeyframeSequences, later) | NpcLifeClient (`TrackSource`) |
| staging | `ServerStorage.NpcStaging.<World>` | Folder | humans + placement steps |

Loading rule at build time: the MCP sandbox cannot `require` place modules (`BrainrotForge` header `[code]`) — `NpcForge` uses the same `loadModule()` (require → fallback `loadstring(Source)`) for the data modules.

## E2. Type definitions (Luau, documentation-grade)

```lua
--!strict
-- ===== BaseRig ===============================================================
export type JointSpec = { name: string, part0: string, part1: string, c0: CFrame, c1: CFrame }
export type PartSpec  = { name: string, size: Vector3, offset: Vector3, mesh: string?, castShadow: boolean? }
export type BodyType  = { id: "standard" | "stout" | "slight", parts: { PartSpec }, joints: { JointSpec },
                          attachments: { [string]: { part: string, offset: Vector3 } } }
-- NpcRigSpec.BodyTypes[id] ; NpcRigSpec.Root = { hrpSize = Vector3.new(2,2,1), hrpHeight = 3.0, headOffset = 1.45,
--                              collider = { size = Vector3.new(2.2,5,1.4), offset = Vector3.new(0,-0.5,0) } }

-- ===== Face ==================================================================
export type FacePart   = { name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material }
export type Expression = { [string]: { x: number?, y: number?, sizeX: number?, sizeY: number?, browOuterUp: number?, rotZ: number? } }
-- NpcFaceConfig.Parts : { FacePart } ; NpcFaceConfig.Expressions[id] : Expression (keys = face part names or "Brow"/"Eye"/"Pupil" for both sides)
-- NpcFaceConfig.Blink = { every = {3,6}, duration = 0.12 } ; NpcFaceConfig.Gaze = { range = 20, dot = 0.3, x = 0.06, y = 0.04, hz = 10 }
-- NpcFaceConfig.Talk  = { mouthY = {0.07, 0.16}, hz = {6,8}, burst = {1.5,2.5}, rest = 0.5 }

-- ===== Library ===============================================================
export type MeshRef  = { meshId: string } | { forge: string }            -- uploaded id, or a forge batch part name (pre-import)
export type LibEntry = {
	id: string,                       -- "HatFloppyPinned"
	kind: "hair" | "hat" | "beard" | "overlay" | "prop" | "body",
	mesh: MeshRef?,                   -- nil = a Part recipe (below)
	partRecipe: { { name: string, shape: "Block" | "Cylinder" | "Ball", size: Vector3, offset: CFrame, colorRole: string? } }?,
	slot: string?,                    -- overlays: the bone name; hair/hat/beard: the attachment name
	grip: ("RightHand" | "LeftHand" | "Back" | "Waist" | "ShoulderL" | "ShoulderR")?,   -- props
	offset: CFrame?,                  -- from the slot attachment / bone centre, authored on `standard`
	fit: { stout: CFrame?, slight: CFrame? }?,   -- per-body-type correction, else identity
	colorRole: string,                -- which family colour paints it ("accent", "leather", ...)
	planted: boolean?,                -- props: counters root tilt on that arm
	light: { range: number, brightness: number, color: Color3 }?,   -- props: at most one
	tris: number,                     -- measured at import; budget input
}
-- NpcLibrary.Entries[id] : LibEntry

-- ===== Families / Themes =====================================================
export type ColorSet = { [string]: Color3 }   -- roles: skin, hair, base, accent, seam, leather, metal, boot, trouser, ...
export type Family = { id: string, colors: ColorSet, bodyRoles: { [string]: string },   -- body part name -> colour role
                       defaultOverlays: { string } }
-- NpcFamilies[id]
export type WorldTheme = { id: "Valley" | "Tundra" | "Gardens" | "Trading", shift: { sat: number, val: number }?,
                           accent: Color3, defaultFamilyByRole: { [string]: string }, lightsAllowed: boolean,
                           replaceOverlay: { [string]: string }? }   -- e.g. Tundra: CloakYoke -> FurCollar
-- NpcWorldThemes[id]

-- ===== AnimationProfile ======================================================
export type Layer   = { joint: string, axis: string, kind: "sine" | "sineAbs" | "snap" | "pulse" | "follow" | "counter" | "track",
                        amp: number?, period: number?, phase: number?, ease: number?, source: string?, gain: number?,
                        every: {number}?, duration: number?, priority: number?, asset: string?, sequence: string? }
export type Gesture = { weight: number, cooldown: {number}, duration: number, hold: boolean?, priority: number?,
                        keys: { { t: number, [string]: { [string]: number } } }, asset: string?, sequence: string? }
export type Pack    = { idle: { Layer }, gestures: { [string]: Gesture }, greet: string?, talk: { [string]: Gesture | Layer }?,
                        layersWithTracks: boolean? }
-- NpcMotionConfig.Packs[id] ; NpcMotionConfig.USE_TRACKS : boolean

-- ===== LODProfile ============================================================
export type Band = { maxDist: number, procEvery: number, gestures: boolean, face: boolean, lights: boolean, trackSpeed: number }
export type LodProfile = { bands: { Band }, offscreenDot: number, maxAnimated: number }
-- NpcLodProfiles[tierId] ; NpcLodProfiles.Global = { maxAnimated = 12, rankEvery = 10 }

-- ===== Character recipe (CharacterOverrides) =================================
export type Recipe = {
	id: string,                       -- "Gianluca"
	rootName: string,                 -- the code-contract model name ("StupidGianluca") or "NPC"
	tier: 1 | 2 | 3,
	world: string,                    -- theme id
	kind: "human" | "creature",
	-- human
	bodyType: ("standard" | "stout" | "slight")?,
	scale: number?,
	family: string?,
	colors: ColorSet?,                -- overrides on top of the family
	face: string?,                    -- default expression
	faceExtras: { string }?,          -- "Scar", "Nose"
	hair: string?, hat: string?, beard: string?,
	overlays: { string | { id: string, color: (Color3 | string)?, offset: CFrame? } }?,   -- color: explicit, or a colour-role name
	props: { string | { id: string, grip: string?, color: (Color3 | string)? } }?,        -- grip: an attachment-grip name, or another prop's id (welds onto it)
	restPose: { [string]: { [string]: number } }?,   -- joint -> semantic axis -> degrees
	collider: boolean?,
	-- creature
	species: string?,                 -- BrainrotModels template name (cloned, never modified)
	storyLayer: { { part: string, size: Vector3, color: Color3, material: Enum.Material?, shape: ("Block" | "Cylinder" | "Ball")?,
	               bone: string, boneFallback: string?, offset: CFrame } }?,   -- bone may name an earlier storyLayer part (Medal on HarnessPlate)
	wear: { sat: number, val: number }?, recolorRoles: { [string]: Color3 }?, stripFx: boolean?,
	stance: { pitch: number?, roll: number?, yaw: number?, sink: number? }?,
	-- shared
	pack: string, packOverrides: { [string]: any }?, profile: string?,
	lod: (1 | 2 | 3)?,                -- defaults to tier
	contracts: { keepChildren: { string }?, promptPart: string?, moveChildrenTo: string? }?,
}
-- NpcCharacters/<Id>.lua returns one Recipe
```

## E3. Example recipes

### E3.1 Gianluca (human, Tier 2)

```lua
return {
	id = "Gianluca", rootName = "StupidGianluca", tier = 2, world = "Valley", kind = "human",
	bodyType = "standard", scale = 1.0, family = "ranger",
	colors = { hair = Color3.fromRGB(92,58,36), accent = Color3.fromRGB(168,58,86), hat = Color3.fromRGB(108,160,80) },
	face = "worried",
	hair = "HairTousled", hat = "HatFloppyPinned",
	overlays = { "TunicHem", "CloakYoke", { id = "ScarfTail", color = "accent" }, "ToolBeltCollar", "BracerR", "BracerL" },
	props = { { id = "Cane", grip = "RightHand" }, { id = "Bell", grip = "Cane" } },   -- "Bell" welds to the Cane entry
	restPose = { Waist = { bend = 4 }, RightShoulder = { spread = 10 }, LeftShoulder = { spread = 10 }, RightElbow = { swing = 6 }, LeftElbow = { swing = 6 } },
	collider = true,
	pack = "Villager",
	packOverrides = { ["idle.breathe.period"] = 2.9, ["idle.breathe.amp"] = 1.8, ["idle.weightShift.amp"] = 4, ["idle.weightShift.period"] = 7,
	                  ["idle.look.amp"] = 28, ["idle.look.period"] = 5.0, ["idle.handsOnHips"] = false,
	                  ["gestures.minorGesture"] = "scratchBrim", ["gestures.ringBell"] = true, greet = "ringBell" },
	contracts = { promptPart = "HumanoidRootPart", keepChildren = { "TalkPrompt" }, moveChildrenTo = "GianlucaCamp" },
}
```

### E3.2 A Tier 1 villager (all defaults)

```lua
return { id = "Villager_Valley_01", rootName = "NPC", tier = 1, world = "Valley", kind = "human",
	bodyType = "standard", family = "village", face = "friendly", hair = "HairCrop", overlays = { "Vest", "Belt" }, pack = "Background" }
```
Ten lines is a whole background NPC. Distinctness comes from `family`, `hair`, one overlay and the theme.

### E3.3 The Veteran (creature, Tier 3)

```lua
return {
	id = "VeteranBombardiro", rootName = "VeteranBombardiro", tier = 3, world = "Gardens", kind = "creature",
	species = "Bombardiro Crocodilo", stripFx = true, wear = { sat = -0.20, val = -0.08 },
	recolorRoles = { Tail = Color3.fromRGB(60,52,48) },      -- applied only if a part named Tail exists
	storyLayer = {
		{ part = "WingSplint",  size = Vector3.new(0.18,2.2,0.5),  color = Color3.fromRGB(74,50,30),  bone = "WingL",  boneFallback = "Body", offset = CFrame.new(-2.1, 1.1, 0.2) * CFrame.Angles(0,0,math.rad(-8)) },
		{ part = "WingStrap",   size = Vector3.new(0.9,0.1,0.6),   color = Color3.fromRGB(52,50,48),  bone = "WingL",  boneFallback = "Body", offset = CFrame.new(-2.0, 1.2, 0.2) },
		{ part = "HarnessPlate",size = Vector3.new(1.6,1.2,0.16),  color = Color3.fromRGB(96,98,104), bone = "Body",   offset = CFrame.new(0, 0.6, -1.4) * CFrame.Angles(0,0,math.rad(6)) },
		{ part = "HarnessStrap",size = Vector3.new(0.35,1.4,0.1),  color = Color3.fromRGB(52,50,48),  bone = "Body",   offset = CFrame.new(0.6, 1.3, -1.3) * CFrame.Angles(0,0,math.rad(-30)) },
		{ part = "GoggleBand",  size = Vector3.new(1.5,0.12,1.5),  color = Color3.fromRGB(52,50,48),  bone = "Head",   boneFallback = "Body", offset = CFrame.new(0, 2.4, -0.6), shape = "Cylinder" },
		{ part = "GoggleLens",  size = Vector3.new(0.9,0.28,0.22), color = Color3.fromRGB(70,72,80),  material = Enum.Material.SmoothPlastic, bone = "GoggleBand", offset = CFrame.new(0, 0.1, -0.75) },
		{ part = "Medal",       size = Vector3.new(0.32,0.32,0.06),color = Color3.fromRGB(196,150,72),material = Enum.Material.SmoothPlastic, bone = "HarnessPlate", offset = CFrame.new(-0.45,-0.3,-0.1), shape = "Cylinder" },
		{ part = "SnoutChip",   size = Vector3.new(0.34,0.2,0.1),  color = Color3.fromRGB(60,52,48),  bone = "Snout",  boneFallback = "Body", offset = CFrame.new(-0.3, 0.2, -2.6) },
	},
	stance = { pitch = -12, roll = 6, yaw = 30, sink = -0.4 },
	pack = "Creature", profile = "Veteran",
}
```
Offsets are placeholders until E-13 gives the real part names and bounds; the *shape* of the data is final.

## E4. `NpcForge.Build(recipeId, opts) → Model` — the algorithm

```
Build(recipe):
  0. validate(recipe)                       -- ids exist in the library/families/themes/packs; tier/lod valid; kind-specific fields present
  1. root = Model(recipe.rootName); root:SetAttribute every Npc* attribute; CollectionService:AddTag(root, "NpcBody"); ModelStreamingMode = Atomic
  2. if kind == "human":
       a. bt = NpcRigSpec.BodyTypes[recipe.bodyType]
       b. create HumanoidRootPart (size/height from NpcRigSpec.Root) at origin; anchored; invisible
       c. for each PartSpec: create MeshPart (mesh from NpcLibrary "body" entries or the forge import root passed in opts.importRoot); size, offset, flags
       d. for each JointSpec: Motor6D in part1 with c0/c1; apply recipe.restPose by baking semantic degrees into c0 (NpcMotion.offsetFor(joint, axes))
       e. attachments from bt.attachments (+ BeardAttachment)
       f. AnimationController
       g. face: NpcFaceConfig.Parts -> Parts + FaceJoint; apply Expressions[recipe.face]; add faceExtras
       h. colours: family = NpcFamilies[recipe.family]; theme = NpcWorldThemes[recipe.world]
            colorSet = family.colors  <- theme.shift  <- recipe.colors      (later wins)
            for each body part: Color = colorSet[family.bodyRoles[part]]
       i. hair/hat/beard: place at attachment, weld to Head, colour by role
       j. overlays: theme.replaceOverlay[id] or id; place by slot bone + offset (+ fit[bodyType]); WeldConstraint; colour by role or explicit
       k. props: place pivot on grip attachment (or on another prop when grip names a prop); WeldConstraint; Planted attribute; light per theme.lightsAllowed
       l. collider if recipe.collider (size/offset from NpcRigSpec.Root)
       m. scale: root:ScaleTo(recipe.scale)
     if kind == "creature":
       a. src = ReplicatedStorage.BrainrotModels[recipe.species]; assert(src); clone = src:Clone()   -- never touch src
       b. strip: Sounds, scripts, (stripFx) emitters/FX hosts contents; flags on every part; anchor RootPart only; weld FakeRootPart->RootPart if unjoined
       c. wear: recolour every visible MeshPart via HSV(recipe.wear); recolorRoles by part name if present
       d. storyLayer: for each row: resolve bone (bone -> boneFallback -> RootPart); create Part/MeshPart; CFrame = RootPart.CFrame * offset; WeldConstraint to bone; NpcStoryLayer=true
       e. scale to plot fit (6.0 * HeightScale, width 9.5); PoseAnchor attachment; stance baked into the model pivot (pitch/roll/yaw) and sink
  3. NpcBudget.report(root) -> must PASS for the tier (doc F); on FAIL: destroy root, return nil, errors
  4. parent to ServerStorage.NpcStaging[recipe.world]; return root
```

**Contracts step (live swap only, separate function `NpcForge.SwapLive(root, liveModel)` — never called by Build):** records the live HRP CFrame, backs the live model up to `ServerStorage.AuditBackups.NPC01_<name>_<date>`, re-parents `contracts.keepChildren` (e.g. `TalkPrompt`) into the new `promptPart`, moves non-body children to `contracts.moveChildrenTo` if set, pivots the new root to the recorded CFrame, parents it to the live parent, then destroys the backup's original only after the prompt is verified bound. This function exists so the swap is one audited call, but it runs only behind Phase 3 gate 6.

## E5. What NpcLifeClient reads from the built model (the runtime contract)

Only **attributes and names** — never the recipe module:

| Attribute / name | Used for |
|---|---|
| tag `NpcBody` | registry |
| `NpcRig` (`SR1` / `Creature`) | which joint set to look for |
| `NpcPack`, `NpcProfile`, `NpcPackOverrides` (JSON string stamped by the forge) | pack selection + overrides |
| `NpcTier` / `NpcLod` | band profile |
| `NpcFace` | expression (writable by quest clients later) |
| `NpcTalking` (runtime, set by the driver itself) | talk state |
| joint names (R15 or the creature's Motor6Ds), `Planted` on props, `PoseAnchor` | evaluation |

This keeps the runtime independent of build-time data: a built model is self-describing.

## E6. Validation (`NpcBudget` — the `BrainrotBudget` pattern with NPC rows)

`NpcBudget.report(model) → table` with: `baseParts, meshParts, parts, unions, motor6d, welds, attachments, orphanParts (non-anchored parts with no joint/weld path to an anchored root), anchoredNonRoot, humanoids, animationControllers, animators, faceParts, overlays, props, lights, emitters, highlights, scripts, decals, textures, surfaceAppearances, neonParts, transparentParts, canCollideParts, canQueryParts, canTouchParts, triangles (when measurable), descendants, hasPrimaryPart, tag, attributes`.
`NpcBudget.review(model, tier)` prints PASS/WARN/FAIL per row against doc F. Hard FAILs: any script, any Humanoid, `orphanParts > 0`, `canQueryParts > 0`, `canTouchParts > 0`, `canCollideParts > 1` (the Collider), Highlights > 0, missing tag/PrimaryPart, BaseParts above the tier cap.

## E7. Extending the system (the rules that keep it data-driven)

1. **New NPC** → one recipe module. If it needs a mesh that does not exist, the mesh goes into `NpcLibrary` first (with `tris` measured), then the recipe references it.
2. **New world** → one `NpcWorldThemes` entry (palette shift, accent, default families, overlay replacements). Existing recipes re-themed by changing `world`.
3. **New gesture / pack** → `NpcMotionConfig` only; the driver has no gesture names hard-coded.
4. **New expression** → `NpcFaceConfig.Expressions` only.
5. **Uploaded animations later** → add `asset`/`sequence` to entries; set `USE_TRACKS`.
6. **Never** add a script to an NPC, never special-case a recipe id in the driver, never read a recipe at runtime.

## E8. Tooling deltas required (Phase 3, disk-side, before any Studio build)

- `tools/brainrot_forge/voxel.py`: an `npc` profile (`MAX_ROLES 16`, `MIN_BODY_SHARE` off, height 24–30 cells at pitch 0.2).
- `tools/brainrot_forge/export_glb.py`: manifest `segments[]` with per-segment pivot so `NpcForge.AssembleHuman` can verify sizes against `NpcRigSpec`.
- New `tools/brainrot_forge/designs/npc_body_standard.py` (+ `_stout`, `_slight`): the 15-role body lattices.
- `ServerStorage.NpcForge`, `ServerStorage.NpcBudget`, the `NpcKit` data modules, `NpcLifeClient` — authored disk-side in `game-src/place-full/...` on this branch first, pushed to Studio only through the gated steps in doc H.
