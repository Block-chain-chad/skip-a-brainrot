-- NpcRigSpec -- SR-Rig v1: the one skeleton every human NPC shares.
--
-- Data only. Sizes, offsets and joint pivots are in HumanoidRootPart space
-- (front = -Z, right = +X, up = +Y), studs, scale 1. NpcForge builds the rig
-- from this; NpcLife reads the joint list and classes from it at runtime.
--
-- Joint frames are NOT stored as C0/C1 -- they are derived from the pivot and
-- the two part centres (JointFrames below), so a size tweak in one table can
-- never leave a C0 that disagrees with the part it belongs to.
--
-- Written in Lua 5.1-compatible syntax on purpose: the disk-side harness
-- (tools/npc_kit) loads these modules under a plain Lua VM before anything
-- reaches Studio. Luau accepts everything here unchanged.

local NpcRigSpec = {}
NpcRigSpec.Version = 2

local function V(x, y, z) return Vector3.new(x, y, z) end

-- The root: an invisible anchored HRP that MerchantDialog frames on
-- (target = HRP + 0.5 * HRP.Size.Y), plus the optional interaction collider
-- (decision D-1: tight to the body, its own collision group, Tier 2/3 only).
NpcRigSpec.Root = {
	HrpSize = V(2, 2, 1),
	HrpHeight = 3.0,            -- HRP centre above the ground plane
	HeadOffset = 1.45,          -- head centre above the HRP centre (the portrait line)
	Collider = {
		Name = "Collider",
		Size = V(1.6, 4.4, 1.2),  -- tight: inside the shoulder width, feet to chin; never a wall
		Offset = V(0, -0.30, 0),
	},
	CollisionGroup = "NpcBody", -- registered by NpcForge; collides with Default (players) only
}

-- Part layout for the `standard` body. Every other body type is this table
-- with a few sizes swapped (see BODY_TYPE_OVERRIDES). `mirror = true` rows
-- are authored for the RIGHT side and generated for the left by negating x.
local STANDARD_PARTS = {
	{ name = "LowerTorso",    size = V(1.90, 0.70, 1.00), offset = V(0, -0.25, 0), shadow = true },
	{ name = "UpperTorso",    size = V(2.20, 1.30, 1.10), offset = V(0,  0.40, 0), shadow = true },
	{ name = "Head",          size = V(1.50, 1.55, 1.35), offset = V(0,  1.45, 0), shadow = true },
	{ name = "RightUpperArm", size = V(0.75, 1.00, 0.75), offset = V(1.45,  0.55, 0), mirror = "LeftUpperArm" },
	{ name = "RightLowerArm", size = V(0.70, 0.90, 0.70), offset = V(1.45, -0.38, 0), mirror = "LeftLowerArm" },
	{ name = "RightHand",     size = V(0.75, 0.70, 0.75), offset = V(1.45, -1.15, 0), mirror = "LeftHand" },
	{ name = "RightUpperLeg", size = V(0.80, 1.00, 0.80), offset = V(0.50, -1.05, 0), mirror = "LeftUpperLeg" },
	{ name = "RightLowerLeg", size = V(0.75, 0.90, 0.75), offset = V(0.50, -1.95, 0), mirror = "LeftLowerLeg" },
	{ name = "RightFoot",     size = V(0.80, 0.60, 1.10), offset = V(0.50, -2.70, -0.15), mirror = "LeftFoot" },
}

-- Joints: pivot in HRP space, authored for the right side; left is generated.
local STANDARD_JOINTS = {
	{ name = "Root",          part0 = "HumanoidRootPart", part1 = "LowerTorso",    pivot = V(0, 0, 0) },
	{ name = "Waist",         part0 = "LowerTorso",       part1 = "UpperTorso",    pivot = V(0, 0.10, 0) },
	{ name = "Neck",          part0 = "UpperTorso",       part1 = "Head",          pivot = V(0, 1.00, 0) },
	-- shoulder pivot at the TORSO EDGE (where the arm meets the body), as R15 places it -- a pivot on the
	-- arm's own centre line sits outside the torso and opens the armpit on every spread (test_forge_npc)
	{ name = "RightShoulder", part0 = "UpperTorso",       part1 = "RightUpperArm", pivot = V(1.10, 0.95, 0),  mirror = "LeftShoulder" },
	{ name = "RightElbow",    part0 = "RightUpperArm",    part1 = "RightLowerArm", pivot = V(1.45, 0.05, 0),  mirror = "LeftElbow" },
	{ name = "RightWrist",    part0 = "RightLowerArm",    part1 = "RightHand",     pivot = V(1.45, -0.83, 0), mirror = "LeftWrist" },
	{ name = "RightHip",      part0 = "LowerTorso",       part1 = "RightUpperLeg", pivot = V(0.50, -0.60, 0), mirror = "LeftHip" },
	{ name = "RightKnee",     part0 = "RightUpperLeg",    part1 = "RightLowerLeg", pivot = V(0.50, -1.55, 0), mirror = "LeftKnee" },
	{ name = "RightAnkle",    part0 = "RightLowerLeg",    part1 = "RightFoot",     pivot = V(0.50, -2.40, 0), mirror = "LeftAnkle" },
}

-- Attachments, per part, in PART space (Roblox standard names so the prop kit,
-- the portrait and any rig tool agree). BeardAttachment is ours.
NpcRigSpec.Attachments = {
	HumanoidRootPart = { RootAttachment = V(0, 0, 0) },
	LowerTorso = { WaistCenterAttachment = V(0, 0, 0), WaistFrontAttachment = V(0, 0, -0.5), WaistBackAttachment = V(0, 0, 0.5) },
	UpperTorso = { NeckAttachment = V(0, 0.65, 0), BodyFrontAttachment = V(0, 0, -0.55), BodyBackAttachment = V(0, 0, 0.55),
		LeftCollarAttachment = V(-0.90, 0.65, 0), RightCollarAttachment = V(0.90, 0.65, 0) },
	Head = { HatAttachment = V(0, 0.775, 0), HairAttachment = V(0, 0.775, 0), FaceFrontAttachment = V(0, 0, -0.675),
		FaceCenterAttachment = V(0, 0, 0), BeardAttachment = V(0, -0.45, -0.55) },
	RightHand = { RightGripAttachment = V(0, -0.10, -0.20) },
	LeftHand = { LeftGripAttachment = V(0, -0.10, -0.20) },
}

-- Which attachment a prop grip name resolves to.
NpcRigSpec.Grips = {
	RightHand = { part = "RightHand", attachment = "RightGripAttachment" },
	LeftHand  = { part = "LeftHand",  attachment = "LeftGripAttachment" },
	Back      = { part = "UpperTorso", attachment = "BodyBackAttachment" },
	Waist     = { part = "LowerTorso", attachment = "WaistBackAttachment" },
	WaistFront = { part = "LowerTorso", attachment = "WaistFrontAttachment" },
	ShoulderL = { part = "UpperTorso", attachment = "LeftCollarAttachment" },
	ShoulderR = { part = "UpperTorso", attachment = "RightCollarAttachment" },
	Hair      = { part = "Head", attachment = "HairAttachment" },
	Hat       = { part = "Head", attachment = "HatAttachment" },
	Beard     = { part = "Head", attachment = "BeardAttachment" },
}

-- Body types: the same skeleton, a few sizes swapped. Pivots do not move --
-- a stout torso is wider, not taller -- so every clip and every gesture fits.
local BODY_TYPE_OVERRIDES = {
	standard = {},
	stout = {
		UpperTorso = { size = V(2.50, 1.30, 1.25) },
		LowerTorso = { size = V(2.20, 0.70, 1.10) },
		RightUpperArm = { size = V(0.85, 1.00, 0.85), offset = V(1.60, 0.55, 0) },
		RightLowerArm = { offset = V(1.60, -0.38, 0) },
		RightHand = { offset = V(1.60, -1.15, 0) },
	},
	slight = {
		UpperTorso = { size = V(1.90, 1.25, 0.95) },
		LowerTorso = { size = V(1.70, 0.65, 0.90) },
		RightUpperArm = { size = V(0.65, 1.00, 0.65), offset = V(1.30, 0.55, 0) },
		RightLowerArm = { size = V(0.62, 0.90, 0.62), offset = V(1.30, -0.38, 0) },
		RightHand = { offset = V(1.30, -1.15, 0) },
	},
}
-- stout/slight arms sit further out / in: elbow/wrist pivots follow the arm's centre x,
-- the shoulder pivot follows the torso's edge.
local JOINT_X_BY_TYPE = { standard = 1.45, stout = 1.60, slight = 1.30 }
local SHOULDER_X_BY_TYPE = { standard = 1.10, stout = 1.25, slight = 0.95 }

local function mirrorV(v) return V(-v.X, v.Y, v.Z) end

local function buildBodyType(id)
	local ov = BODY_TYPE_OVERRIDES[id]
	assert(ov, "NpcRigSpec: unknown body type " .. tostring(id))
	local parts, joints = {}, {}
	for _, p in ipairs(STANDARD_PARTS) do
		local o = ov[p.name] or {}
		local row = { name = p.name, size = o.size or p.size, offset = o.offset or p.offset, shadow = p.shadow or false }
		parts[#parts + 1] = row
		if p.mirror then
			parts[#parts + 1] = { name = p.mirror, size = row.size, offset = mirrorV(row.offset), shadow = row.shadow }
		end
	end
	local armX = JOINT_X_BY_TYPE[id]
	for _, j in ipairs(STANDARD_JOINTS) do
		local pivot = j.pivot
		if j.name == "RightShoulder" then
			pivot = V(SHOULDER_X_BY_TYPE[id], pivot.Y, pivot.Z)
		elseif j.name == "RightElbow" or j.name == "RightWrist" then
			pivot = V(armX, pivot.Y, pivot.Z)
		end
		joints[#joints + 1] = { name = j.name, part0 = j.part0, part1 = j.part1, pivot = pivot }
		if j.mirror then
			local p0 = j.part0:gsub("^Right", "Left")
			local p1 = j.part1:gsub("^Right", "Left")
			joints[#joints + 1] = { name = j.mirror, part0 = p0, part1 = p1, pivot = mirrorV(pivot) }
		end
	end
	return { id = id, parts = parts, joints = joints }
end

-- ===== PROFILES (V2.5, D-22) ===================================================
-- A profile is a PARAMETER table the skeleton is built from bottom-up (feet on y = 0,
-- legs set the hip height, torso stacks on the hips, head on the neck; the HRP stays
-- at HrpHeight so the MerchantDialog portrait line keeps working). p2 is the default
-- human BodyProfile; a recipe's bodyOverrides scales the parameters per character
-- (height, headScale, shoulderWidth, torsoMass, limbThickness, legLength) before the
-- build, so one rig system yields many body shapes. Numbers = the approved study P2.
NpcRigSpec.Profiles = {
	p2 = {
		head = V(1.72, 1.72, 1.58), ut = V(2.10, 1.25, 1.10), lt = V(1.85, 0.70, 1.00),
		ua = V(0.80, 0.92, 0.80), la = V(0.82, 0.85, 0.82), hand = V(0.90, 0.62, 0.88),
		ul = V(0.85, 1.00, 0.85), ll = V(0.78, 0.80, 0.78), foot = V(0.85, 0.50, 1.20),
		legX = 0.52, armGap = 0.05, shoulderDrop = 0.16, footForward = 0.12, neckGap = 0.16,
	},
}
NpcRigSpec.OverrideKeys = { "height", "headScale", "shoulderWidth", "torsoMass", "limbThickness", "legLength" }

local function scaleV(v, sx, sy, sz) return V(v.X * sx, v.Y * sy, v.Z * sz) end

-- Apply multiplier overrides (1 = as authored) to a copy of the profile parameters.
local function overrideParams(src, ov)
	ov = ov or {}
	local h = ov.height or 1            -- every vertical dimension
	local hs = ov.headScale or 1
	local sw = ov.shoulderWidth or 1    -- upper torso width (the arms follow the torso edge)
	local tm = ov.torsoMass or 1        -- torso width + depth
	local lt = ov.limbThickness or 1    -- limb / hand / foot width + depth
	local ll = ov.legLength or 1
	local p = {}
	p.head = scaleV(src.head, hs, hs * h, hs)
	p.ut = scaleV(src.ut, sw * tm, h, tm)
	p.lt = scaleV(src.lt, tm, h, tm)
	p.ua = scaleV(src.ua, lt, h, lt)
	p.la = scaleV(src.la, lt, h, lt)
	p.hand = scaleV(src.hand, lt, h, lt)
	p.ul = scaleV(src.ul, lt, h * ll, lt)
	p.ll = scaleV(src.ll, lt, h * ll, lt)
	p.foot = scaleV(src.foot, lt, h, lt)
	p.legX = src.legX * math.sqrt(tm)
	p.armGap = src.armGap
	p.shoulderDrop = src.shoulderDrop * h
	p.footForward = src.footForward
	p.neckGap = src.neckGap * h
	return p
end

-- Build a body-type table from parameters (the same stacking as the study's make_profile).
function NpcRigSpec.BuildProfile(id, params)
	local q = params
	local hrpY = NpcRigSpec.Root.HrpHeight
	local parts, joints = {}, {}
	local function part(name, size, x, y, z, shadow)
		parts[#parts + 1] = { name = name, size = size, offset = V(x, y - hrpY, z), shadow = shadow or false }
	end
	local pivots = {}
	local function pivot(name, x, y, z) pivots[name] = V(x, y - hrpY, z) end
	-- legs
	local ankle = q.foot.Y * 0.75
	local llBottom = ankle - 0.10
	local knee = llBottom + q.ll.Y - 0.05
	local ulBottom = knee - 0.08
	local hip = ulBottom + q.ul.Y - 0.08
	for _, side in ipairs({ { "Right", 1 }, { "Left", -1 } }) do
		local x = side[2] * q.legX
		part(side[1] .. "Foot", q.foot, x, q.foot.Y / 2, -q.footForward)
		part(side[1] .. "LowerLeg", q.ll, x, llBottom + q.ll.Y / 2, 0)
		part(side[1] .. "UpperLeg", q.ul, x, ulBottom + q.ul.Y / 2, 0)
		pivot(side[1] .. "Ankle", x, ankle, 0)
		pivot(side[1] .. "Knee", x, knee, 0)
		pivot(side[1] .. "Hip", x, hip, 0)
	end
	-- torso
	local ltBottom = hip - 0.10
	local waist = ltBottom + q.lt.Y - 0.03
	local utBottom = waist - 0.07
	local neck = utBottom + q.ut.Y - 0.06
	part("LowerTorso", q.lt, 0, ltBottom + q.lt.Y / 2, 0, true)
	part("UpperTorso", q.ut, 0, utBottom + q.ut.Y / 2, 0, true)
	pivot("Root", 0, hrpY, 0)
	pivot("Waist", 0, waist, 0)
	pivot("Neck", 0, neck, 0)
	-- head (a short visible neck under it)
	local headBottom = neck + q.neckGap
	part("Head", q.head, 0, headBottom + q.head.Y / 2, 0, true)
	-- arms
	local utTop = utBottom + q.ut.Y
	local shoulderY = utTop - q.shoulderDrop
	for _, side in ipairs({ { "Right", 1 }, { "Left", -1 } }) do
		local sx = side[2]
		local ax = sx * (q.ut.X / 2 + q.ua.X / 2 + q.armGap)
		local uaTop = shoulderY + 0.14
		local elbow = uaTop - q.ua.Y + 0.06
		local laTop = elbow + 0.06
		local wrist = laTop - q.la.Y + 0.05
		local handTop = wrist + 0.05
		part(side[1] .. "UpperArm", q.ua, ax, uaTop - q.ua.Y / 2, 0)
		part(side[1] .. "LowerArm", q.la, ax, laTop - q.la.Y / 2, 0)
		part(side[1] .. "Hand", q.hand, ax, handTop - q.hand.Y / 2, 0)
		pivot(side[1] .. "Shoulder", sx * q.ut.X / 2, shoulderY, 0)
		pivot(side[1] .. "Elbow", ax, elbow, 0)
		pivot(side[1] .. "Wrist", ax, wrist, 0)
	end
	-- joints in the standard order (parent before child), same names / part pairs as v1
	for _, j in ipairs(STANDARD_JOINTS) do
		joints[#joints + 1] = { name = j.name, part0 = j.part0, part1 = j.part1, pivot = pivots[j.name] }
		if j.mirror then
			joints[#joints + 1] = { name = j.mirror, part0 = j.part0:gsub("^Right", "Left"), part1 = j.part1:gsub("^Right", "Left"), pivot = pivots[j.mirror] }
		end
	end
	-- the parts list in v1 order (torso, head, then limbs right/left) for stable iteration
	local order = { "LowerTorso", "UpperTorso", "Head", "RightUpperArm", "LeftUpperArm", "RightLowerArm", "LeftLowerArm", "RightHand", "LeftHand",
		"RightUpperLeg", "LeftUpperLeg", "RightLowerLeg", "LeftLowerLeg", "RightFoot", "LeftFoot" }
	local byName = {}
	for _, p in ipairs(parts) do byName[p.name] = p end
	local ordered = {}
	for _, n in ipairs(order) do ordered[#ordered + 1] = byName[n] end
	local head = byName.Head
	return { id = id, parts = ordered, joints = joints, profile = true,
		headOffset = head.offset.Y, height = hrpY + head.offset.Y + head.size.Y / 2 }
end

NpcRigSpec.BodyTypes = {
	standard = buildBodyType("standard"),
	stout = buildBodyType("stout"),
	slight = buildBodyType("slight"),
	p2 = NpcRigSpec.BuildProfile("p2", overrideParams(NpcRigSpec.Profiles.p2, nil)),
}
NpcRigSpec.DefaultBodyType = "p2"

-- Resolve(bodyTypeId, overrides) -> a body-type table. Overrides only apply to
-- profile-built types; the v1 literal types ignore them (and say so in .note).
function NpcRigSpec.Resolve(bodyTypeId, overrides)
	bodyTypeId = bodyTypeId or NpcRigSpec.DefaultBodyType
	local base = NpcRigSpec.BodyTypes[bodyTypeId]
	assert(base, "NpcRigSpec: unknown body type " .. tostring(bodyTypeId))
	local any = false
	for _, k in ipairs(NpcRigSpec.OverrideKeys) do
		if overrides and overrides[k] and overrides[k] ~= 1 then any = true end
	end
	if not any then return base end
	local params = NpcRigSpec.Profiles[bodyTypeId]
	if not params then
		local copy = {}
		for k, v in pairs(base) do copy[k] = v end
		copy.note = "bodyOverrides ignored: " .. bodyTypeId .. " is not a profile-built body type"
		return copy
	end
	local bt = NpcRigSpec.BuildProfile(bodyTypeId, overrideParams(params, overrides))
	bt.overrides = overrides
	return bt
end

-- Lookups the driver uses: joint class + side for the semantic axes (doc C1).
NpcRigSpec.JointClass = {}
NpcRigSpec.Side = {}
for _, j in ipairs(NpcRigSpec.BodyTypes.standard.joints) do
	local spine = (j.name == "Root" or j.name == "Waist" or j.name == "Neck")
	NpcRigSpec.JointClass[j.name] = spine and "spine" or "limb"
	if j.name:sub(1, 4) == "Left" then NpcRigSpec.Side[j.name] = -1 else NpcRigSpec.Side[j.name] = 1 end
end
NpcRigSpec.JointOrder = {}
for _, j in ipairs(NpcRigSpec.BodyTypes.standard.joints) do NpcRigSpec.JointOrder[#NpcRigSpec.JointOrder + 1] = j.name end

-- Creature rigs (story brainrots) have whatever joints the template has; the
-- driver classifies them by name so the same semantic axes apply.
function NpcRigSpec.ClassifyCreatureJoint(name)
	local n = name:lower()
	local side = 1
	if n:find("left") or n:sub(-1) == "l" or n:find("_l") then side = -1 end
	if n:find("head") or n:find("neck") or n:find("spine") or n:find("torso") then
		return "spine", side
	end
	return "limb", side
end

-- Body-type argument: an id ("standard", "p2") or a resolved table (NpcRigSpec.Resolve).
local function bodyTypeOf(x)
	if type(x) == "table" then return x end
	local bt = NpcRigSpec.BodyTypes[x or NpcRigSpec.DefaultBodyType]
	assert(bt, "NpcRigSpec: unknown body type " .. tostring(x))
	return bt
end
NpcRigSpec.BodyTypeOf = bodyTypeOf

function NpcRigSpec.PartByName(bodyType, partName)
	local bt = bodyTypeOf(bodyType)
	for _, p in ipairs(bt.parts) do if p.name == partName then return p end end
	return nil
end

-- C0/C1 for a joint: pivot expressed in each part's own space. Part0 may be
-- the HRP (centre = origin). centres (optional) maps a part name to the extra
-- offset of its MeshPart centre from the bone origin (a shell mesh is centred on
-- its own bounding box by the importer), so the frames stay pinned to the pivot.
function NpcRigSpec.JointFrames(bodyType, jointName, centres)
	local bt = bodyTypeOf(bodyType)
	centres = centres or {}
	local zero = V(0, 0, 0)
	for _, j in ipairs(bt.joints) do
		if j.name == jointName then
			local c0centre = (j.part0 == "HumanoidRootPart") and zero or NpcRigSpec.PartByName(bt, j.part0).offset
			local c1centre = NpcRigSpec.PartByName(bt, j.part1).offset
			local e0 = centres[j.part0] or zero
			local e1 = centres[j.part1] or zero
			local c0 = CFrame.new(j.pivot.X - c0centre.X - e0.X, j.pivot.Y - c0centre.Y - e0.Y, j.pivot.Z - c0centre.Z - e0.Z)
			local c1 = CFrame.new(j.pivot.X - c1centre.X - e1.X, j.pivot.Y - c1centre.Y - e1.Y, j.pivot.Z - c1centre.Z - e1.Z)
			return c0, c1, j
		end
	end
	error("NpcRigSpec: unknown joint " .. tostring(jointName))
end

-- Total standing height, for budgets and the portrait check.
function NpcRigSpec.Height(bodyType)
	local head = NpcRigSpec.PartByName(bodyTypeOf(bodyType or "standard"), "Head")
	return NpcRigSpec.Root.HrpHeight + head.offset.Y + head.size.Y / 2
end

-- Head centre above the HRP (the portrait line): 1.45 on the v1 types, the profile's own on p2.
function NpcRigSpec.HeadOffset(bodyType)
	local bt = bodyTypeOf(bodyType or "standard")
	if bt.headOffset then return bt.headOffset end
	return NpcRigSpec.Root.HeadOffset
end

return NpcRigSpec
