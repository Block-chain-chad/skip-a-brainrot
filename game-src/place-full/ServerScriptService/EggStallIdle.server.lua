--[[
	EggStallIdle.lua
	Server-side idle animation for the 5 Forest Egg display models on
	Workspace.GameWorld.EggStall (Mossy Egg / Reedwater Egg / Bramble Egg / Hollow Egg / Heartwood Egg).
	Re-themed 2026-08-13 with the world1_eggs_all.glb rebuild. Every egg now shares one part
	vocabulary: shell_body + themed decorations bob together, "sparkle" parts orbit as floaters,
	and the halo/cross/rainbow rings (24 "_sN" box segments each, pre-tilted in the model) spin
	about Y with tilt 0 -- the baked-in tilt makes the yaw spin read as a precession wobble.
]]

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local TAU = math.pi * 2
local BOB_AMP = 0.1
local PROXIMITY_RANGE = 60
local PROXIMITY_CHECK_EVERY = 10

-- ringSpecs pair with ring GROUPS sorted alphabetically by group key, so the order is
-- always: cross_ring, halo_ring, rainbow_ring (whichever of those the egg has).
local EGG_CONFIG = {
	["Mossy Egg"] = {
		bodyFamilies = {shell_body = true, moss = true, fleck = true, pebble = true, stem = true, leaf = true, aura_shell = true, ray = true},
		ringFamilies = {halo_ring = true},
		ringSpecs = {
			{period = 10, tilt = 0, dir = 1},
		},
		floatFamilyOrder = {"sparkle"},
		floatCount = 3,
		bobPeriod = 4.0,
	},
	["Reedwater Egg"] = {
		bodyFamilies = {shell_body = true, submerged = true, waterline = true, droplet = true, reed_stalk = true, cattail = true, pad = true, aura_shell = true, ray = true},
		ringFamilies = {halo_ring = true},
		ringSpecs = {
			{period = 11, tilt = 0, dir = -1},
		},
		floatFamilyOrder = {"sparkle"},
		floatCount = 4,
		bobPeriod = 4.6,
	},
	["Bramble Egg"] = {
		bodyFamilies = {shell_body = true, seam_bead = true, vine_seg = true, thorn = true, chip = true, moth = true, moth_wing = true, aura_shell = true, ray = true},
		ringFamilies = {cross_ring = true, halo_ring = true},
		ringSpecs = {
			{period = 12, tilt = 0, dir = -1},
			{period = 9, tilt = 0, dir = 1},
		},
		floatFamilyOrder = {"sparkle"},
		floatCount = 4,
		bobPeriod = 5.2,
	},
	["Hollow Egg"] = {
		bodyFamilies = {shell_body = true, wisp = true, vein = true, shard = true, frost_crown = true, aura_shell = true, ray = true},
		ringFamilies = {cross_ring = true, halo_ring = true, rainbow_ring = true},
		ringSpecs = {
			{period = 12, tilt = 0, dir = -1},
			{period = 9, tilt = 0, dir = 1},
			{period = 16, tilt = 0, dir = 1},
		},
		floatFamilyOrder = {"sparkle"},
		floatCount = 4,
		bobPeriod = 3.8,
	},
	["Heartwood Egg"] = {
		bodyFamilies = {shell_body = true, grain = true, seam_bead = true, plate = true, root = true, antler = true, antler_tip = true, aura_shell = true, ray = true},
		ringFamilies = {cross_ring = true, halo_ring = true, rainbow_ring = true},
		ringSpecs = {
			{period = 10, tilt = 0, dir = -1},
			{period = 8, tilt = 0, dir = 1},
			{period = 14, tilt = 0, dir = -1},
		},
		floatFamilyOrder = {"sparkle"},
		floatCount = 5,
		bobPeriod = 5.0,
	},
}

local function familyOf(name)
	local base = name
	local changed = true
	while changed do
		local newBase = base:gsub("_s%d+$", ""):gsub("_%d+$", "")
		changed = newBase ~= base
		base = newBase
	end
	return base
end

local function groupKeyOf(name)
	return (name:gsub("_s%d+$", ""))
end

local function partVolume(part)
	local size = part.Size
	return size.X * size.Y * size.Z
end

local resolved = {}

local function makeAnchor(model, priceTag)
	if not priceTag then return end
	local existingAnchor = model:FindFirstChild("PriceTagAnchor")
	if existingAnchor then
		priceTag.Adornee = existingAnchor
		return
	end
	local adornee = priceTag.Adornee
	if not adornee then return end

	local anchor = Instance.new("Part")
	anchor.Name = "PriceTagAnchor"
	anchor.Size = Vector3.new(0.05, 0.05, 0.05)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Anchored = true
	anchor.CFrame = adornee.CFrame
	anchor.Parent = model
	priceTag.Adornee = anchor
end

-- The egg price tags shipped with MaxDistance = inf, the only GUIs in the game with no
-- cap at all (every other sign is 47-220), so they stayed legible from clear across the
-- map. They also bled into each other badly: the eggs sit in a straight line 4 studs
-- apart, and a 160px billboard is about 3.2 studs wide, so viewed ALONG the row the
-- gaps foreshorten toward nothing while each tag keeps its full width -- the five names
-- rendered as one unreadable smear. Three things fix it together:
--   * a real MaxDistance, so they only appear when you are at the stall
--   * a smaller tag, which shrinks both the text and the footprint
--   * alternating heights, which is the only one that survives an edge-on viewing angle
-- Done here rather than on the instances so any egg added later is covered too.
local TAG_MAX_DISTANCE = 45
local TAG_SIZE = UDim2.fromOffset(88, 40)
local TAG_BASE_Y = 1.7          -- the offset the tags already used
-- THREE levels, not two. With a 2-cycle, eggs 1 and 3 still share a row only 8 studs
-- apart and still collide at a shallow angle; a 3-cycle guarantees no neighbour ever
-- shares a row, and same-row pairs end up 12 studs apart.
local TAG_STAGGER_LEVELS = 3
local TAG_STAGGER_STEP = 0.95
local NAME_MAX_TEXT = 15
local PRICE_MAX_TEXT = 14

local function capText(label, maxSize)
	if not label then return end
	-- TextScaled with no constraint means a short name renders BIGGER than a long one,
	-- so capping also makes the row visually consistent, not just smaller.
	local c = label:FindFirstChildOfClass("UITextSizeConstraint")
	if not c then
		c = Instance.new("UITextSizeConstraint")
		c.Parent = label
	end
	c.MaxTextSize = maxSize
end

local function styleTag(model, priceTag)
	if not priceTag then return end
	priceTag.MaxDistance = TAG_MAX_DISTANCE
	priceTag.Size = TAG_SIZE
	capText(priceTag:FindFirstChild("NameLabel"), NAME_MAX_TEXT)
	capText(priceTag:FindFirstChild("PriceLabel"), PRICE_MAX_TEXT)

	-- Stagger by position in the row (sorted along Z) rather than by creation order, so
	-- the pattern is stable no matter what order the models happen to be parented in.
	local parent = model.Parent
	if not parent then return end
	local row = {}
	for _, c in ipairs(parent:GetChildren()) do
		if c:IsA("Model") and c.Name:find("Egg") and c:FindFirstChildOfClass("BillboardGui") then
			table.insert(row, c)
		end
	end
	table.sort(row, function(a, b) return a:GetPivot().Position.Z < b:GetPivot().Position.Z end)
	local idx = 1
	for i, c in ipairs(row) do
		if c == model then idx = i break end
	end
	local level = (idx - 1) % TAG_STAGGER_LEVELS
	priceTag.StudsOffset = Vector3.new(0, TAG_BASE_Y + level * TAG_STAGGER_STEP, 0)
end

local function setupModel(eggName, model)
	local cfg = EGG_CONFIG[eggName]
	if not cfg then return end

	local state = {
		model = model,
		bobPeriod = cfg.bobPeriod,
		bobPhase = math.random() * TAU,
		bodyParts = {},
		floaters = {},
		rings = {},
		crownAssembly = nil,
	}

	local byFamily = {}
	local byGroup = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "PriceTagAnchor" then
			local fam = familyOf(d.Name)
			byFamily[fam] = byFamily[fam] or {}
			table.insert(byFamily[fam], d)

			local gk = groupKeyOf(d.Name)
			local g = byGroup[gk]
			if not g then
				g = {family = fam, parts = {}}
				byGroup[gk] = g
			end
			table.insert(g.parts, d)
		end
	end

	local excluded = {}

	if cfg.floatFamilyOrder and cfg.floatCount and cfg.floatCount > 0 then
		local pool = {}
		for _, fam in ipairs(cfg.floatFamilyOrder) do
			if #pool >= cfg.floatCount then break end
			local famParts = {}
			for _, p in ipairs(byFamily[fam] or {}) do
				table.insert(famParts, p)
			end
			table.sort(famParts, function(a, b) return partVolume(a) < partVolume(b) end)
			for _, p in ipairs(famParts) do
				if #pool >= cfg.floatCount then break end
				table.insert(pool, p)
			end
		end

		local shell = model.PrimaryPart or (byFamily.shell_body and byFamily.shell_body[1])
		local shellCenter = shell and shell.Position or model:GetPivot().Position
		local shellSize = shell and shell.Size or Vector3.new(2, 2, 2)
		local shellHalfWidth = (shellSize.X + shellSize.Z) / 4
		local orbitRadius = shellHalfWidth + 0.35

		local n = #pool
		for i, p in ipairs(pool) do
			excluded[p] = true
			local heightFrac = n > 1 and (i - 1) / (n - 1) or 0.5
			local height = shellCenter.Y + (heightFrac - 0.5) * shellSize.Y * 0.5
			table.insert(state.floaters, {
				part = p,
				shellCenter = shellCenter,
				height = height,
				radius = orbitRadius,
				period = 6 + (n > 1 and (i - 1) * (3 / (n - 1)) or 0),
				phase = (i - 1) * (TAU / math.max(n, 1)),
				spinRate = 0.6 + i * 0.15,
			})
		end
	end

	if cfg.ringFamilies then
		local ringGroups = {}
		for gk, g in pairs(byGroup) do
			if cfg.ringFamilies[g.family] then
				table.insert(ringGroups, {key = gk, group = g})
			end
		end
		table.sort(ringGroups, function(a, b) return a.key < b.key end)

		for i, entry in ipairs(ringGroups) do
			local g = entry.group
			local spec = cfg.ringSpecs and cfg.ringSpecs[i]
			if spec then
				local sum = Vector3.new()
				for _, p in ipairs(g.parts) do
					sum = sum + p.Position
					excluded[p] = true
				end
				local center = sum / #g.parts
				local flatCF = CFrame.new(center)
				local localParts = {}
				for _, p in ipairs(g.parts) do
					table.insert(localParts, {part = p, cf = flatCF:ToObjectSpace(p.CFrame)})
				end
				table.insert(state.rings, {
					parts = localParts,
					center = center,
					tilt = math.rad(spec.tilt),
					period = spec.period,
					dir = spec.dir,
					phase = math.random() * TAU,
				})
			end
		end
	end

	if cfg.crownAssemblyFamilies then
		local parts = {}
		local sumX, sumZ, minY, count = 0, 0, math.huge, 0
		for fam in pairs(cfg.crownAssemblyFamilies) do
			for _, p in ipairs(byFamily[fam] or {}) do
				table.insert(parts, p)
				excluded[p] = true
				sumX = sumX + p.Position.X
				sumZ = sumZ + p.Position.Z
				minY = math.min(minY, p.Position.Y)
				count = count + 1
			end
		end
		if count > 0 then
			local pivot0 = CFrame.new(sumX / count, minY, sumZ / count)
			local localParts = {}
			for _, p in ipairs(parts) do
				table.insert(localParts, {part = p, cf = pivot0:ToObjectSpace(p.CFrame)})
			end
			state.crownAssembly = {
				parts = localParts,
				pivot0 = pivot0,
				hover = cfg.crownHover,
				bobAmp = cfg.crownBobAmp,
				bobPeriod = cfg.crownBobPeriod,
				yawPeriod = cfg.crownYawPeriod,
				phase = math.random() * TAU,
			}
		end
	end

	if cfg.bodyFamilies then
		for fam in pairs(cfg.bodyFamilies) do
			for _, p in ipairs(byFamily[fam] or {}) do
				if not excluded[p] then
					table.insert(state.bodyParts, {part = p, cf0 = p.CFrame})
				end
			end
		end
	end

	local priceTag = model:FindFirstChildOfClass("BillboardGui")
	makeAnchor(model, priceTag)
	styleTag(model, priceTag)

	resolved[eggName] = state
end

local function getStall()
	local gw = Workspace:FindFirstChild("GameWorld")
	return gw and gw:FindFirstChild("EggStall")
end

local function resolveAll()
	local stall = getStall()
	if not stall then return end

	for eggName in pairs(EGG_CONFIG) do
		local model = stall:FindFirstChild(eggName)
		if model then
			setupModel(eggName, model)
		end
	end

	stall.ChildAdded:Connect(function(child)
		if child:IsA("Model") and EGG_CONFIG[child.Name] then
			task.defer(function()
				if child.Parent then
					setupModel(child.Name, child)
				end
			end)
		end
	end)
end

resolveAll()

local frameCount = 0
local active = true

local function checkProximity()
	local stall = getStall()
	if not stall then
		active = false
		return
	end
	local origin = stall:GetPivot().Position
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - origin).Magnitude <= PROXIMITY_RANGE then
			active = true
			return
		end
	end
	active = false
end

RunService.Heartbeat:Connect(function()
	frameCount += 1
	if frameCount % PROXIMITY_CHECK_EVERY == 0 then
		checkProximity()
	end
	if not active then
		return
	end

	local t = os.clock()

	for eggName, state in pairs(resolved) do
		local model = state.model
		if not model or not model.Parent then
			resolved[eggName] = nil
			continue
		end

		local bobY = BOB_AMP * math.sin((TAU * t / state.bobPeriod) + state.bobPhase)
		local bobOffset = Vector3.new(0, bobY, 0)
		for _, entry in ipairs(state.bodyParts) do
			if entry.part.Parent then
				entry.part.CFrame = entry.cf0 + bobOffset
			end
		end

		for _, ring in ipairs(state.rings) do
			local spin = (TAU * t / ring.period) * ring.dir + ring.phase
			local ringCF = CFrame.new(ring.center) * CFrame.Angles(0, spin, 0) * CFrame.Angles(ring.tilt, 0, 0)
			for _, entry in ipairs(ring.parts) do
				if entry.part.Parent then
					entry.part.CFrame = ringCF * entry.cf
				end
			end
		end

		local ca = state.crownAssembly
		if ca then
			local hoverY = ca.hover + ca.bobAmp * math.sin((TAU * t / ca.bobPeriod) + ca.phase)
			local yaw = (TAU * t / ca.yawPeriod) + ca.phase
			local assemblyCF = ca.pivot0 * CFrame.new(0, hoverY, 0) * CFrame.Angles(0, yaw, 0)
			for _, entry in ipairs(ca.parts) do
				if entry.part.Parent then
					entry.part.CFrame = assemblyCF * entry.cf
				end
			end
		end

		for _, f in ipairs(state.floaters) do
			if f.part.Parent then
				local ang = (TAU * t / f.period) + f.phase
				local orbitCF = CFrame.new(f.shellCenter.X, f.height, f.shellCenter.Z)
					* CFrame.Angles(0, ang, 0)
					* CFrame.new(f.radius, 0, 0)
					* CFrame.Angles(t * f.spinRate, t * f.spinRate * 0.7, 0)
				f.part.CFrame = orbitCF
			end
		end
	end
end)
