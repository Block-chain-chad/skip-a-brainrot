-- PetVisualsClient: every equipped pet's body -- built, walked and animated here.
--
-- WHY THE CLIENT. This used to live in PetHandler: a server-cloned model welded
-- into one rigid lump, dragged along behind the player by an AlignPosition, with a
-- single sine bob on the follow attachment. That is the whole reason equipped pets
-- read as luggage rather than as creatures -- a server rig can only afford to move
-- the ROOT, so a pet could never take a step, lean into a turn, or look at
-- anything. Animating a skeleton means writing joints every frame, which is free
-- locally and unaffordable over the wire.
--
-- The server now publishes only WHAT is equipped, as a Player attribute
-- (PetConfig.LOADOUT_ATTR, pipe-separated pet Ids in slot order). Attributes
-- replicate to every client, so everyone still sees everyone's pets, and late
-- joiners get the state with no handshake. Nothing about a pet's body was ever
-- server-authoritative: pets have no collision, no hitbox and no gameplay reach.
--
-- WHERE THE SKELETON COMES FROM. Nothing is hand-authored per pet. The .glb import
-- left a real anatomy in the hierarchy -- anatomy.leg_1r, anatomy.tail,
-- anatomy.ears.ear_l, anatomy.wings.wing_1r, anatomy.head -- consistently across
-- all 15 models, so buildRig discovers limbs by walking that tree and hangs a
-- Motor6D on each one. A pet with no legs (snail, moth) simply produces no leg
-- joints and its gait never asks for any. That is what keeps this from being 15
-- special cases, and what makes pet #16 animate the day it is imported.
--
-- All models face -Z natively (verified across the whole roster: the head sits at
-- negative Z in every one of them), which is already Roblox's LookVector, so there
-- is no per-model orientation fixup anywhere below.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PetConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PetConfig"))

local LOADOUT_ATTR = PetConfig.LOADOUT_ATTR

local ANIM_RANGE = 160     -- studs from camera; past this a pet is parked, never animated
local PARK_HZ = 5          -- position updates per second for a parked pet
local TRAIL_KEEP = 30      -- studs of path history kept; must exceed the furthest slot Back
local TRAIL_STEP = 0.35    -- studs of travel before a new breadcrumb is recorded
local TELEPORT = 60        -- studs moved in one frame that means "teleported", not "ran"
local RUN_SPEED = 16       -- studs/s treated as full speed for gait blending
local GROUND_DROP = 40     -- studs the ground probe reaches below the pet

local rigFolder = Instance.new("Folder")
rigFolder.Name = "PetRigsClient"
rigFolder.Parent = Workspace

---------------------------------------------------------------- ground probing
-- One shared RaycastParams, refreshed when the player list changes rather than
-- rebuilt per ray: at six pets a player that would be a new table every frame.
-- Characters are excluded so a pet never stands on its owner's head, and the rig
-- folder is excluded so pets never stand on each other.
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function refreshRayFilter()
	local list = { rigFolder }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = list
end
refreshRayFilter()

---------------------------------------------------------------- small maths
local function wrapPi(a)
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- Frame-rate independent easing: the fraction of the remaining gap to close this
-- frame. A raw `lerp(a, b, k)` makes every follow speed a function of FPS, which is
-- exactly how a follower looks correct in Studio and drifts on a 30fps phone.
local function ease(dt, rate)
	return 1 - math.exp(-rate * dt)
end

-- Stable per-pet stagger. Never math.random: two players standing side by side with
-- the same pet must not be able to tell that their pets were seeded differently,
-- and a rebuild must not visibly re-roll the animation.
local function phaseFor(petId, slot)
	local h = slot * 97
	for i = 1, #petId do
		h = (h * 31 + string.byte(petId, i)) % 8192
	end
	return (h % 628) * 0.01
end

-- Axis-aligned extents of one part, honouring its rotation. Sizes alone would
-- under-report any part the importer left at an angle, and the pivots below are
-- picked off these boxes.
local function growBox(lo, hi, part)
	local cf, h = part.CFrame, part.Size * 0.5
	local rx, ry, rz = cf.RightVector, cf.UpVector, cf.LookVector
	local e = Vector3.new(
		math.abs(rx.X) * h.X + math.abs(ry.X) * h.Y + math.abs(rz.X) * h.Z,
		math.abs(rx.Y) * h.X + math.abs(ry.Y) * h.Y + math.abs(rz.Y) * h.Z,
		math.abs(rx.Z) * h.X + math.abs(ry.Z) * h.Y + math.abs(rz.Z) * h.Z)
	local p = cf.Position
	return lo:Min(p - e), hi:Max(p + e)
end

local function nearestInBox(point, lo, hi)
	return Vector3.new(
		math.clamp(point.X, lo.X, hi.X),
		math.clamp(point.Y, lo.Y, hi.Y),
		math.clamp(point.Z, lo.Z, hi.Z))
end

---------------------------------------------------------------- limb discovery
-- The importer names the FIRST instance of a mesh "<thing>_Node" and every later
-- copy just "<thing>", while the MeshPart inside keeps the original name -- which
-- is why both ears contain a part called "ear_r" and only the enclosing Model says
-- which side it is. So every rule below reads MODEL names, never part names.
local function stripNode(name)
	return (name:gsub("_Node$", ""))
end

local function chainOf(part, root)
	local chain, n = {}, part.Parent
	while n and n ~= root do
		table.insert(chain, 1, stripNode(n.Name):lower())
		n = n.Parent
	end
	return chain
end

-- Anything on the skull. Kept as an explicit set rather than "everything near the
-- head" because the roster is consistent enough to name, and a spatial rule would
-- swallow the shoulders of the short-necked pets.
local HEAD_GROUPS = {
	head = true, snout = true, muzzle = true, muzzle_tip = true, jaw = true,
	nose = true, nostril_r = true, nostril_l = true, lip_r = true, lip_l = true,
	eyes = true, cap = true, beak = true, bill = true, bill_split = true,
	ruff = true, frill = true, antler_r = true, antler_l = true,
}
local HEAD_PREFIXES = { "grin", "antenna", "stalk_", "tooth", "fang", "whisker", "horn", "brow" }

-- key -> which joint it becomes. Returns nil for the torso and for every decorative
-- family (fur, spots, stripes, spikes, shell, coils, segments, flowers, runes), all
-- of which ride the body rigidly.
local function groupKeyOf(chain)
	if chain[1] ~= "anatomy" then return nil end
	local g = chain[2]
	if not g then return nil end

	if g:match("^leg_%d[rl]$") or g:match("^hindleg_[rl]$") then return "leg:" .. g, "leg" end
	if g == "tail" then return "tail", "tail" end
	if g == "ears" then
		return "ear:" .. ((chain[3] or ""):match("([rl])$") or "r"), "ear"
	end
	if g == "wings" then
		return "wing:" .. ((chain[3] or ""):match("([rl])$") or "r"), "wing"
	end
	local armSide = g:match("^arm_([rl])") or g:match("^hand_([rl])")
	if armSide then return "arm:" .. armSide, "arm" end
	if g:match("^neck") then return "neck", "neck" end
	if g == "orbiters" or g == "halo" or g == "aura_disc" or g:match("^orbit_ring") then
		return "orbit", "orbit"
	end
	if HEAD_GROUPS[g] then return "head", "head" end
	for _, p in ipairs(HEAD_PREFIXES) do
		if g:sub(1, #p) == p then return "head", "head" end
	end
	return nil
end

---------------------------------------------------------------- rig construction
local function findSource(petId)
	local def = PetConfig.Pets[petId]
	local pets = ReplicatedStorage:FindFirstChild("PetModels")
	if pets and def then
		-- Model name first, then the display name: the import instructions say keep the
		-- .glb filename, but a model renamed to "Moss Larva" on the way in should still
		-- resolve rather than silently fall through to a cube.
		local hit = (def.Model and pets:FindFirstChild(def.Model)) or pets:FindFirstChild(def.Name)
		if hit then return hit end
	end
	-- The ten RETIRED stand-in pets are brainrots. A player who hatched one during
	-- testing still owns it, and it still deserves a body.
	local brainrots = ReplicatedStorage:FindFirstChild("BrainrotModels")
	return brainrots and def and brainrots:FindFirstChild(def.Name) or nil
end

-- Last resort when a pet's art is missing entirely, so "equipped" can never mean
-- "nothing visible happened".
local function buildAcorn()
	local model = Instance.new("Model")
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(1.6, 1.6, 1.6)
	ball.Color = Color3.fromRGB(139, 94, 60)
	ball.Material = Enum.Material.SmoothPlastic
	ball.Name = "body_shell"
	ball.Parent = model
	local cap = Instance.new("Part")
	cap.Size = Vector3.new(1.3, 0.5, 1.3)
	cap.Color = Color3.fromRGB(90, 60, 30)
	cap.Material = Enum.Material.SmoothPlastic
	cap.CFrame = ball.CFrame * CFrame.new(0, 0.85, 0)
	cap.Parent = model
	return model
end

local function jointBetween(parentHub, childHub, pivot)
	local m = Instance.new("Motor6D")
	m.Part0 = parentHub
	m.Part1 = childHub
	-- Both sides reference the SAME world point, so the rest pose is identity and
	-- `C0 = base * rot` rotates the child about `pivot` and nothing else.
	m.C0 = parentHub.CFrame:Inverse() * CFrame.new(pivot)
	m.C1 = childHub.CFrame:Inverse() * CFrame.new(pivot)
	m.Parent = parentHub
	return { motor = m, base = m.C0 }
end

-- Builds one animatable pet. Returns nil only if there is no geometry at all.
local function buildRig(petId, slot)
	local source = findSource(petId)
	local model = source and source:Clone() or buildAcorn()
	model.Name = "Pet_" .. petId

	-- Defensive strip: the art is pure geometry today, but a script, prompt or sound
	-- riding a clone that follows a player would be live once per pet per player.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("ProximityPrompt") or d:IsA("Sound")
			or d:IsA("ClickDetector") then
			d:Destroy()
		end
	end

	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			parts[#parts + 1] = d
		end
	end
	if #parts == 0 then model:Destroy() return nil end

	-- Scale BEFORE any joint or weld exists: every C0/C1 below is captured from live
	-- part CFrames, and scaling afterwards would leave the joints describing the
	-- pre-scale skeleton.
	do
		local _, size = model:GetBoundingBox()
		local largest = math.max(size.X, size.Y, size.Z)
		if largest > 0 then
			pcall(function() model:ScaleTo(math.clamp(PetConfig.PET_SIZE / largest, 0.05, 40)) end)
		end
	end

	-- Sort every part into its joint group; unclaimed parts are the torso.
	local groups = {}    -- key -> { kind = , parts = { } }
	local body = { kind = "body", parts = {} }
	for _, part in ipairs(parts) do
		local key, kind = groupKeyOf(chainOf(part, model))
		local g = body
		if key then
			g = groups[key]
			if not g then g = { kind = kind, parts = {} } groups[key] = g end
		end
		g.parts[#g.parts + 1] = part
	end
	-- A model with no torso left (every part claimed) would have nothing to hang the
	-- limbs off, so the head becomes the body and loses its own joint.
	if #body.parts == 0 and groups.head then
		body = groups.head
		body.kind = "body"
		groups.head = nil
	end
	if #body.parts == 0 then model:Destroy() return nil end

	-- Per group: the biggest part is the hub everything else welds to, plus the box
	-- the pivot gets picked from.
	local function finish(g)
		local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
		local hub, best
		for _, p in ipairs(g.parts) do
			lo, hi = growBox(lo, hi, p)
			local vol = p.Size.X * p.Size.Y * p.Size.Z
			if not best or vol > best then hub, best = p, vol end
		end
		g.hub, g.lo, g.hi = hub, lo, hi
		g.centre = (lo + hi) * 0.5
		for _, p in ipairs(g.parts) do
			if p ~= hub then
				local w = Instance.new("WeldConstraint")
				w.Part0, w.Part1 = hub, p
				w.Parent = p
			end
		end
	end
	finish(body)
	for _, g in pairs(groups) do finish(g) end

	-- The root is a stand-in part at the model's ground centre, NOT a real body part:
	-- every model keeps its PrimaryPart somewhere different (a shell, an antler ring),
	-- and yaw has to turn a pet about its own middle whatever the art did.
	local mLo, mHi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, p in ipairs(parts) do mLo, mHi = growBox(mLo, mHi, p) end
	local centre = (mLo + mHi) * 0.5

	local root = Instance.new("Part")
	root.Name = "PetRoot"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.CFrame = CFrame.new(centre.X, mLo.Y, centre.Z)
	root.Parent = model
	model.PrimaryPart = root

	-- Body pivots low in the torso so a lean tips the pet the way a leaning animal
	-- tips, rather than swinging its feet out from under it.
	local j = { legs = {}, ears = {}, wings = {}, arms = {} }
	j.body = jointBetween(root, body.hub, Vector3.new(centre.X, mLo.Y + (mHi.Y - mLo.Y) * 0.45, centre.Z))

	local neck = groups.neck
	if neck then
		j.neck = jointBetween(body.hub, neck.hub, nearestInBox(body.centre, neck.lo, neck.hi))
	end
	local headParent = neck and neck.hub or body.hub
	local headAnchor = neck and neck.centre or body.centre
	local head = groups.head
	if head then
		j.head = jointBetween(headParent, head.hub, nearestInBox(headAnchor, head.lo, head.hi))
	end

	for key, g in pairs(groups) do
		if g.kind == "leg" or g.kind == "arm" then
			-- top of the limb box is the hip/shoulder; a limb has to swing from where it
			-- meets the body, and its own centre would make it row from the knee
			local pivot = Vector3.new(g.centre.X, g.hi.Y, g.centre.Z)
			local entry = jointBetween(body.hub, g.hub, pivot)
			entry.front = pivot.Z < centre.Z          -- every model faces -Z
			entry.side = (pivot.X < centre.X) and -1 or 1
			-- Diagonal pairs, the way a quadruped actually walks: front-left moves with
			-- back-right. On a biped this degenerates to plain alternation.
			entry.phase = (entry.front == (entry.side > 0)) and 0 or math.pi
			table.insert(g.kind == "leg" and j.legs or j.arms, entry)
		elseif g.kind == "ear" or g.kind == "wing" then
			local parent = (g.kind == "ear") and (head and head.hub or body.hub) or body.hub
			local anchor = (g.kind == "ear") and (head and head.centre or body.centre) or body.centre
			local entry = jointBetween(parent, g.hub, nearestInBox(anchor, g.lo, g.hi))
			entry.side = key:sub(-1) == "l" and 1 or -1
			table.insert(g.kind == "ear" and j.ears or j.wings, entry)
		elseif g.kind == "tail" then
			j.tail = jointBetween(body.hub, g.hub, nearestInBox(body.centre, g.lo, g.hi))
		elseif g.kind == "orbit" then
			j.orbit = jointBetween(body.hub, g.hub, g.centre)
		end
	end

	-- Two shadow casters, not none and not 180: a pet with no shadow at all floats no
	-- matter how well it walks, and the contact shadow under the torso is the whole
	-- of that cue. The decorative parts contribute nothing but draw calls.
	body.hub.CastShadow = true
	if head then head.hub.CastShadow = true end

	local gait = PetConfig.GaitFor(petId)
	return {
		model = model,
		root = root,
		j = j,
		gait = gait,
		slot = PetConfig.FOLLOW_SLOTS[slot] or PetConfig.FOLLOW_SLOTS[#PetConfig.FOLLOW_SLOTS],
		phase = phaseFor(petId, slot),
		step = phaseFor(petId, slot),   -- start mid-stride so a fresh rig is not in lockstep
		pos = Vector3.zero,
		yaw = 0,
		speed = 0,
		groundY = nil,
		parkClock = 0,
		seeded = false,
	}
end

---------------------------------------------------------------- the walked path
-- Pets follow the path the player WALKED, not a fixed offset from where the player
-- is facing right now. That single choice is most of what makes a line of pets read
-- as walking WITH you: round a corner and they round the same corner, one after
-- another. The old rigid offsets meant a turn scythed every pet sideways through
-- the inside of the corner (and through any wall on it), which is a large part of
-- why the formation looked sloppy.
local Trail = {}
Trail.__index = Trail

function Trail.new(p)
	return setmetatable({ pts = { { p = p, d = 0 } }, len = 0 }, Trail)
end

function Trail:reset(p)
	table.clear(self.pts)
	self.pts[1] = { p = p, d = 0 }
	self.len = 0
end

function Trail:push(p)
	local pts = self.pts
	local step = (p - pts[#pts].p).Magnitude
	if step < TRAIL_STEP then return end
	self.len += step
	pts[#pts + 1] = { p = p, d = self.len }
	-- drop history no slot can still reach; without this the table grows for the
	-- whole life of the character
	while #pts > 2 and self.len - pts[2].d > TRAIL_KEEP do
		table.remove(pts, 1)
	end
end

-- The point `back` studs along the path behind the head, plus the direction of
-- travel there. Safe on a trail shorter than the slot asks for: a pet that has just
-- spawned simply sits at the oldest breadcrumb until the player has walked far
-- enough to have a path worth following.
function Trail:sample(back)
	local pts = self.pts
	local want = self.len - back
	if #pts == 1 or want <= pts[1].d then
		return pts[1].p, nil
	end
	for i = #pts, 2, -1 do
		local a, b = pts[i - 1], pts[i]
		if want >= a.d then
			local span = b.d - a.d
			local pos = a.p:Lerp(b.p, span > 0 and (want - a.d) / span or 0)
			local dir = b.p - a.p
			return pos, (dir.Magnitude > 1e-4) and dir.Unit or nil
		end
	end
	return pts[1].p, nil
end

---------------------------------------------------------------- placement
local DOWN = Vector3.new(0, -GROUND_DROP, 0)

local function groundAt(pet, x, z, fallbackY)
	-- Start the probe above the pet's LAST known ground rather than a fixed height, so
	-- a pet walking up a slope or a stair keeps finding the step in front of it.
	local from = Vector3.new(x, math.max(pet.groundY or fallbackY, fallbackY) + 6, z)
	local hit = Workspace:Raycast(from, DOWN, rayParams)
	return hit and hit.Position.Y or (pet.groundY or fallbackY)
end

local function stepPet(pet, dt, trail, owner)
	local slot = pet.slot
	local target, tangent = trail:sample(slot.Back)
	local dir = tangent or owner.look
	-- right-hand vector of a -Z look, so Side reads as "studs to the pet's right"
	local want = target + Vector3.new(-dir.Z, 0, dir.X) * slot.Side

	-- Never stand inside the owner. Walking backwards into your own pets used to push
	-- them straight through your torso, because their slot was defined relative to a
	-- player who was now standing on top of it.
	local away = Vector3.new(want.X - owner.pos.X, 0, want.Z - owner.pos.Z)
	local gap = away.Magnitude
	if gap < 3 then
		local push = (gap > 1e-3) and (away / gap) or -owner.look
		want = owner.pos + push * 3
	end

	local groundY = groundAt(pet, want.X, want.Z, owner.footY)
	pet.groundY = groundY

	if not pet.seeded then
		pet.pos = Vector3.new(want.X, groundY, want.Z)
		pet.prev = pet.pos
		pet.yaw = owner.yaw
		pet.seeded = true
		return
	end

	-- Vertical chases harder than lateral: the horizontal lag is the follow, and is
	-- supposed to be visible, but the same lag on Y would leave a pet hanging in the
	-- air behind every step down.
	local flat, vert = ease(dt, 9), ease(dt, 16)
	pet.pos = Vector3.new(
		pet.pos.X + (want.X - pet.pos.X) * flat,
		pet.pos.Y + (groundY - pet.pos.Y) * vert,
		pet.pos.Z + (want.Z - pet.pos.Z) * flat)
end

-- Pets on the same slot row share a trail point and would otherwise stand in each
-- other. One pass, worst case 15 pairs at a full six.
local SEPARATION = 2.7
local function separate(pets)
	for i = 1, #pets do
		for k = i + 1, #pets do
			local a, b = pets[i], pets[k]
			local d = Vector3.new(b.pos.X - a.pos.X, 0, b.pos.Z - a.pos.Z)
			local m = d.Magnitude
			if m < SEPARATION then
				local unit = (m > 1e-3) and (d / m) or Vector3.new(1, 0, 0)
				local push = unit * ((SEPARATION - m) * 0.5)
				a.pos -= push
				b.pos += push
			end
		end
	end
end

---------------------------------------------------------------- the animation
-- Everything here is derived from ONE number: how fast this pet is actually moving.
-- Nothing is triggered, nothing is a state machine, so there is no transition to
-- pop -- a pet eases into its walk and out of it because every gait term is scaled
-- by the same blend.
local function posePet(pet, dt, t, owner, full)
	pet.prev = pet.prev or pet.pos
	local vel = pet.pos - pet.prev
	pet.prev = pet.pos

	local speed = (dt > 0) and (Vector3.new(vel.X, 0, vel.Z).Magnitude / dt) or 0
	pet.speed += (speed - pet.speed) * ease(dt, 10)

	local g = pet.gait
	local kind = g.Kind
	local blend = math.clamp(pet.speed / RUN_SPEED, 0, 1)

	-- Face where it is GOING while it moves, and turn back to the owner once it stops
	-- -- a pet that always faced the player's own look direction was the tell that
	-- nothing was steering it.
	local wantYaw = pet.yaw
	if pet.speed > 1.2 then
		wantYaw = math.atan2(-vel.X, -vel.Z)
	else
		local toOwner = Vector3.new(owner.pos.X - pet.pos.X, 0, owner.pos.Z - pet.pos.Z)
		if toOwner.Magnitude > 0.25 then
			wantYaw = math.atan2(-toOwner.X, -toOwner.Z)
		end
	end
	pet.yaw += wrapPi(wantYaw - pet.yaw) * ease(dt, 7)

	-- Stride frequency from speed, so steps cover ground instead of running on the
	-- spot. Higher Stride = shorter, quicker steps.
	local hz = math.clamp(pet.speed * g.Stride / 5, 0, 4)
	if kind == "hop" then
		-- a hopper at rest still hops, just rarely and barely
		hz = math.max(hz, 0.3)
	end
	pet.step += dt * hz * math.pi * 2
	if pet.step > 1e6 then pet.step = pet.step % (math.pi * 2) end

	local s2 = math.sin(pet.step * 2)
	local breathe = math.sin(t * 1.7 + pet.phase)
	local idle = 1 - blend
	local lift, pitch, roll, sway = 0, 0, 0, 0

	if kind == "walk" then
		-- never negative: a body that dips below its resting height sinks its feet
		-- into the ground at the bottom of every stride
		lift = g.Bounce * (0.5 - 0.5 * math.cos(pet.step * 2)) * blend
		pitch = -g.Lean * blend + s2 * 0.035 * blend
		roll = math.sin(pet.step) * g.Roll * blend
		sway = math.sin(pet.step) * 0.05 * blend
	elseif kind == "hop" then
		local arc = math.abs(math.sin(pet.step))
		lift = g.Bounce * arc * (0.18 + 0.82 * blend)
		-- nose up on the way out of the arc, down on the way back into it
		pitch = math.cos(pet.step) * g.Lean * (0.35 + 0.65 * blend)
	elseif kind == "fly" then
		lift = g.Hover + math.sin(t * g.Flap * 3.14 + pet.phase) * g.Bounce
		pitch = -g.Lean * blend
		roll = math.sin(t * 1.3 + pet.phase) * g.Roll
	else -- slide: no legs to swing, so the whole body does the work
		lift = g.Hover + (0.5 - 0.5 * math.cos(pet.step * 2)) * g.Bounce * blend
		pitch = -g.Lean * blend
		roll = math.sin(pet.step) * g.Roll
		sway = math.sin(pet.step) * 0.12 * blend + idle * math.sin(t * 0.9 + pet.phase) * 0.05
	end

	-- Breathing, and only at rest: a standing pet with nothing moving on it is a
	-- prop, and this is the cheapest possible fix for that.
	lift += idle * (0.5 + 0.5 * breathe) * 0.045
	pitch += idle * breathe * 0.02

	pet.root.CFrame = CFrame.new(pet.pos.X, pet.pos.Y + lift, pet.pos.Z)
		* CFrame.Angles(0, pet.yaw + sway, 0)
	if not full then return end

	local j = pet.j
	j.body.motor.C0 = j.body.base * CFrame.Angles(pitch, 0, roll)

	for _, leg in ipairs(j.legs) do
		local a
		if kind == "hop" then
			-- tucked at the top of the arc, reaching at the bottom
			a = -0.75 * math.abs(math.sin(pet.step)) * (0.3 + 0.7 * blend) - 0.05
		elseif kind == "fly" then
			a = math.sin(t * 1.6 + pet.phase + leg.phase) * 0.12
		else
			a = math.sin(pet.step + leg.phase) * 0.55 * blend
		end
		leg.motor.C0 = leg.base * CFrame.Angles(a, 0, 0)
	end

	for _, arm in ipairs(j.arms) do
		-- arms counter the legs, which is what stops a biped reading as marching
		arm.motor.C0 = arm.base * CFrame.Angles(
			math.sin(pet.step + arm.phase + math.pi) * 0.42 * blend + idle * breathe * 0.05, 0, 0)
	end

	if j.tail then
		local wag = math.sin(pet.step + 0.8) * (0.10 + 0.26 * blend)
			+ idle * math.sin(t * 2.4 + pet.phase) * 0.16
		j.tail.motor.C0 = j.tail.base * CFrame.Angles(-0.10 * blend, wag, 0)
	end

	-- Two slow sines beating against each other, so the idle look-around never lands
	-- on a period a player can catch
	local lookAround = math.sin(t * 0.55 + pet.phase) * 0.30 + math.sin(t * 0.23 + pet.phase * 2) * 0.14
	if j.neck then
		j.neck.motor.C0 = j.neck.base * CFrame.Angles(
			-s2 * 0.04 * blend + idle * breathe * 0.03, lookAround * 0.45 * idle, 0)
	end
	if j.head then
		j.head.motor.C0 = j.head.base * CFrame.Angles(
			s2 * 0.06 * blend + idle * breathe * 0.025,
			lookAround * 0.55 * idle,
			idle * math.sin(t * 0.9 + pet.phase) * 0.05)
	end

	for _, ear in ipairs(j.ears) do
		local flop = math.sin(pet.step * 2 + pet.phase) * 0.22 * blend
			+ math.sin(t * 2.1 + pet.phase + (ear.side > 0 and 0.9 or 0)) * 0.07
		ear.motor.C0 = ear.base * CFrame.Angles(0, 0, flop * ear.side)
	end

	for _, wing in ipairs(j.wings) do
		local a
		if kind == "fly" then
			a = math.sin(t * g.Flap * 6.283 + pet.phase) * 0.8
		elseif g.Flap > 0 then
			a = math.sin(t * g.Flap * 6.283 + pet.phase) * 0.12 * (0.3 + 0.7 * blend)
		else
			a = math.sin(t * 1.2 + pet.phase) * 0.05
		end
		wing.motor.C0 = wing.base * CFrame.Angles(0, 0, a * wing.side)
	end

	if j.orbit then
		j.orbit.motor.C0 = j.orbit.base * CFrame.Angles(0, t * 0.9 + pet.phase, 0)
	end
end

---------------------------------------------------------------- lifecycle
-- [player] = { hrp, humanoid, trail, pets, loadout, token }
local states = {}

local function clearPets(st)
	-- bumping the token aborts any build still in flight for this state
	st.token += 1
	for _, pet in ipairs(st.pets) do
		pet.model:Destroy()
	end
	table.clear(st.pets)
end

local function drop(player)
	local st = states[player]
	if not st then return end
	clearPets(st)
	states[player] = nil
end

-- The ONE path that decides what is following a player. Called on every loadout
-- change and every spawn, and cheap to call spuriously: it returns immediately
-- unless the character or the loadout string actually changed.
local function sync(player)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local loadout = player:GetAttribute(LOADOUT_ATTR)
	if typeof(loadout) ~= "string" then loadout = "" end

	if not hrp or loadout == "" then
		drop(player)
		return
	end

	local st = states[player]
	if st and st.hrp == hrp and st.loadout == loadout then return end
	if st then clearPets(st) end

	st = st or { pets = {}, token = 0 }
	st.hrp = hrp
	st.humanoid = character:FindFirstChildOfClass("Humanoid")
	st.loadout = loadout
	st.trail = Trail.new(hrp.Position)
	states[player] = st

	local token = st.token
	task.spawn(function()
		local slot = 0
		for petId in loadout:gmatch("[^|]+") do
			slot += 1
			if slot > #PetConfig.FOLLOW_SLOTS then break end
			local pet = buildRig(petId, slot)
			-- Six ~100-part models built in one frame is a visible hitch, so each pet
			-- costs a frame. The token check is what keeps a rig from being adopted by
			-- a loadout that changed while we were welding the previous one.
			if st.token ~= token then
				if pet then pet.model:Destroy() end
				return
			end
			if pet then
				pet.model.Parent = rigFolder
				table.insert(st.pets, pet)
			end
			task.wait()
			if st.token ~= token then return end
		end
	end)
end

local function watch(player)
	player:GetAttributeChangedSignal(LOADOUT_ATTR):Connect(function()
		sync(player)
	end)
	player.CharacterAdded:Connect(function(character)
		task.spawn(function()
			character:WaitForChild("HumanoidRootPart", 10)
			refreshRayFilter()
			if player.Character == character then sync(player) end
		end)
	end)
	player.CharacterRemoving:Connect(function()
		drop(player)
		task.defer(refreshRayFilter)
	end)
	sync(player)
end

for _, p in ipairs(Players:GetPlayers()) do watch(p) end
Players.PlayerAdded:Connect(function(p)
	refreshRayFilter()
	watch(p)
end)
Players.PlayerRemoving:Connect(function(p)
	drop(p)
	task.defer(refreshRayFilter)
end)

---------------------------------------------------------------- the one loop
-- One Heartbeat for every pet of every player, the way FootstepClient and
-- BrainrotIdleClient do it: per-rig connections at six pets a player would be
-- dozens of callbacks a frame all doing identical work. Heartbeat rather than
-- RenderStepped because character physics has already run by then, so a pet reads
-- this frame's owner position instead of last frame's.
RunService.Heartbeat:Connect(function(dt)
	dt = math.min(dt, 0.1)
	local t = os.clock()
	local camera = Workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position or Vector3.zero

	for player, st in pairs(states) do
		local hrp = st.hrp
		if not hrp.Parent or (st.humanoid and st.humanoid.Health <= 0) then
			-- died or respawned out from under us; CharacterAdded rebuilds
			clearPets(st)
			states[player] = nil
		else
			local pos = hrp.Position
			if (pos - st.trail.pts[#st.trail.pts].p).Magnitude > TELEPORT then
				-- a spawn or a plot warp: re-seat rather than dragging a line of pets
				-- across the map at follow speed
				st.trail:reset(pos)
				for _, pet in ipairs(st.pets) do pet.seeded = false end
			else
				st.trail:push(pos)
			end

			local look = hrp.CFrame.LookVector
			look = Vector3.new(look.X, 0, look.Z)
			look = (look.Magnitude > 1e-3) and look.Unit or Vector3.new(0, 0, -1)
			local hipDrop = ((st.humanoid and st.humanoid.HipHeight) or 2) + hrp.Size.Y * 0.5
			local owner = {
				pos = pos,
				look = look,
				footY = pos.Y - hipDrop,
				yaw = math.atan2(-look.X, -look.Z),
			}

			local pets = st.pets
			for _, pet in ipairs(pets) do
				stepPet(pet, dt, st.trail, owner)
			end
			if #pets > 1 then separate(pets) end
			for _, pet in ipairs(pets) do
				pet.parkClock += dt
				local near = (pet.pos - camPos).Magnitude <= ANIM_RANGE
				if near or pet.parkClock >= 1 / PARK_HZ then
					posePet(pet, pet.parkClock, t, owner, near)
					pet.parkClock = 0
				end
			end
		end
	end
end)
