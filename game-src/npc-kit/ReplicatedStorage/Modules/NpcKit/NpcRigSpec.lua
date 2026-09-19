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
NpcRigSpec.Version = 1

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

NpcRigSpec.BodyTypes = {
	standard = buildBodyType("standard"),
	stout = buildBodyType("stout"),
	slight = buildBodyType("slight"),
}

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

function NpcRigSpec.PartByName(bodyTypeId, partName)
	local bt = NpcRigSpec.BodyTypes[bodyTypeId]
	if not bt then return nil end
	for _, p in ipairs(bt.parts) do if p.name == partName then return p end end
	return nil
end

-- C0/C1 for a joint: pivot expressed in each part's own space. Part0 may be
-- the HRP (centre = origin).
function NpcRigSpec.JointFrames(bodyTypeId, jointName)
	local bt = NpcRigSpec.BodyTypes[bodyTypeId]
	assert(bt, "NpcRigSpec: unknown body type " .. tostring(bodyTypeId))
	for _, j in ipairs(bt.joints) do
		if j.name == jointName then
			local c0centre = (j.part0 == "HumanoidRootPart") and V(0, 0, 0) or NpcRigSpec.PartByName(bodyTypeId, j.part0).offset
			local c1centre = NpcRigSpec.PartByName(bodyTypeId, j.part1).offset
			local c0 = CFrame.new(j.pivot.X - c0centre.X, j.pivot.Y - c0centre.Y, j.pivot.Z - c0centre.Z)
			local c1 = CFrame.new(j.pivot.X - c1centre.X, j.pivot.Y - c1centre.Y, j.pivot.Z - c1centre.Z)
			return c0, c1, j
		end
	end
	error("NpcRigSpec: unknown joint " .. tostring(jointName))
end

-- Total standing height, for budgets and the portrait check.
function NpcRigSpec.Height(bodyTypeId)
	local head = NpcRigSpec.PartByName(bodyTypeId or "standard", "Head")
	return NpcRigSpec.Root.HrpHeight + head.offset.Y + head.size.Y / 2
end

return NpcRigSpec
