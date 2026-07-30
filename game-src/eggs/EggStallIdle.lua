--[[
	EggStallIdle.lua
	Server-side idle animation for the 5 Forest Egg display models on
	Workspace.GameWorld.EggStall (Shard Egg / Drip Egg / Horned Egg / Rune Egg / Crown Egg).

	Reproduces the motion seen in the animated design reference video:
	  - Egg bodies: gentle vertical bob (no yaw), desynced periods 3.5-5.5s.
	  - Circling energy rings (Rune's single ring, Crown's two rings): precess --
	    tilted ~22 degrees off horizontal, with the tilt axis itself slowly
	    rotating around the world Y axis. Crown's two rings run ~9s/~12s in
	    opposite directions.
	  - Crown's halo+crown assembly (crown_ring/crown_point/crown_tip/halo_ring/
	    link parts): hovers 0.35 studs above its authored spot with a slow bob
	    + slow yaw, moving as one rigid unit.
	  - Shard/Drip/Horned eggs: 3-4 of their smallest shard_* (falling back to
	    stud_* if a given egg doesn't have enough shard_* parts) are detached
	    from the body and sent into slow desynced orbits around the shell.

	Only touches CFrames (transforms) on already-built, Anchored, CanCollide=false
	parts -- no geometry/color changes here (Part A recolor was applied directly
	to instances, separately). Price-tag BillboardGuis are re-adorned to a static
	anchor part at setup so they never move with the body bob.

	Survives egg model replacement (e.g. a purchase/restock swapping the display
	clone) via a ChildAdded listener on EggStall that re-resolves and re-caches
	the replacement model.

	Recolor targets applied (see game-src/eggs/models-build-log.md for the full
	verification pass) live only as instance Color/Material changes plus a
	snapshot on each changed part's "_EGG_Col2" attribute -- nothing here.
]]

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local TAU = math.pi * 2
local BOB_AMP = 0.1
local PROXIMITY_RANGE = 60
local PROXIMITY_CHECK_EVERY = 10

-- ===== Per-egg animation configuration ================================

local EGG_CONFIG = {
	["Shard Egg"] = {
		bodyFamilies = {shell_body = true, stripe = true, stud = true},
		floatFamilyOrder = {"shard", "stud"},
		floatCount = 3,
		bobPeriod = 4.0,
	},
	["Drip Egg"] = {
		bodyFamilies = {shell_body = true, drip = true, tape = true},
		floatFamilyOrder = {"shard", "stud"},
		floatCount = 4,
		bobPeriod = 4.6,
	},
	["Horned Egg"] = {
		bodyFamilies = {shell_body = true, stripe = true, spike = true, horn = true},
		floatFamilyOrder = {"shard", "stud"},
		floatCount = 4,
		bobPeriod = 5.2,
	},
	["Rune Egg"] = {
		bodyFamilies = {shell_body = true, stripe = true, rune_ring = true, rune_bar = true, shard = true},
		ringFamilies = {ring = true},
		ringSpecs = {
			{period = 10, tilt = 22, dir = 1},
		},
		bobPeriod = 3.8,
	},
	["Crown Egg"] = {
		bodyFamilies = {shell_body = true, cap = true, cap_drip = true, stripe = true, rune_ring = true, rune_bar = true, shard = true},
		ringFamilies = {ring = true},
		ringSpecs = {
			{period = 9, tilt = 22, dir = 1},
			{period = 12, tilt = 22, dir = -1},
		},
		crownAssemblyFamilies = {crown_ring = true, crown_point = true, crown_tip = true, halo_ring = true, link = true},
		crownHover = 0.35,
		crownBobAmp = 0.1,
		crownBobPeriod = 8,
		crownYawPeriod = 14,
		bobPeriod = 5.0,
	},
}

-- ===== Helpers ==========================================================

-- Collapses a part name down to its decorative "family", e.g.
-- "rune_ring_1_9_s3" -> "rune_ring", "shard_1_22" -> "shard".
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

-- Collapses only the trailing ring-segment suffix, e.g. "ring_1_55_s3" ->
-- "ring_1_55". Used to bucket a ring/loop's 10 segments back into one group
-- while still telling "ring_1_55" (Crown's outer ring) apart from "ring_2_56"
-- (Crown's inner ring).
local function groupKeyOf(name)
	return (name:gsub("_s%d+$", ""))
end

local function partVolume(part)
	local size = part.Size
	return size.X * size.Y * size.Z
end

-- ===== Setup: resolve one display model into an animation state ========

local resolved = {} -- [eggName] = state

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

local function setupModel(eggName, model)
	local cfg = EGG_CONFIG[eggName]
	if not cfg then return end

	local state = {
		model = model,
		bobPeriod = cfg.bobPeriod,
		bobPhase = math.random() * TAU,
		bodyParts = {}, -- {part=, cf0=}
		floaters = {}, -- {part=, shellCenter=, height=, radius=, period=, phase=, spinRate=}
		rings = {}, -- {parts={{part=,cf=}}, center=, tilt=, period=, dir=, phase=}
		crownAssembly = nil, -- {parts={{part=,cf=}}, pivot0=, hover=, bobAmp=, bobPeriod=, yawPeriod=, phase=}
	}

	-- Bucket parts by family + ring-group key.
	local byFamily = {} -- family -> list of parts
	local byGroup = {} -- groupKey -> {family=, parts={}}
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

	local excluded = {} -- part -> true once claimed by float/ring/crown-assembly

	-- Floaters: smallest N parts, preferring the shard_* family (the design's
	-- literal "floating shards"); only dips into stud_* if an egg doesn't have
	-- enough shard_* parts on its own.
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
			local heightFrac = n > 1 and (i - 1) / (n - 1) or 0.5 -- 0..1 staggered around mid-shell
			local height = shellCenter.Y + (heightFrac - 0.5) * shellSize.Y * 0.5
			table.insert(state.floaters, {
				part = p,
				shellCenter = shellCenter,
				height = height,
				radius = orbitRadius,
				period = 6 + (n > 1 and (i - 1) * (3 / (n - 1)) or 0), -- 6..9s desynced
				phase = (i - 1) * (TAU / math.max(n, 1)),
				spinRate = 0.6 + i * 0.15,
			})
		end
	end

	-- Ring groups: precessing loops (tilted, tilt-axis rotates around Y).
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

	-- Crown halo+crown assembly: crown_ring/crown_point/crown_tip/halo_ring/link
	-- move together as one rigid hovering, slowly-yawing unit.
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

	-- Body: everything in bodyFamilies not already claimed by float/ring/crown.
	if cfg.bodyFamilies then
		for fam in pairs(cfg.bodyFamilies) do
			for _, p in ipairs(byFamily[fam] or {}) do
				if not excluded[p] then
					table.insert(state.bodyParts, {part = p, cf0 = p.CFrame})
				end
			end
		end
	end

	-- Price tag: re-adorn to a static anchor so it never bobs with the body.
	makeAnchor(model, model:FindFirstChildOfClass("BillboardGui"))

	resolved[eggName] = state
end

-- ===== Resolve stall + survive model replacement ========================

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

-- ===== Heartbeat driver ==================================================

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

		-- Body bob (vertical only -- no yaw).
		local bobY = BOB_AMP * math.sin((TAU * t / state.bobPeriod) + state.bobPhase)
		local bobOffset = Vector3.new(0, bobY, 0)
		for _, entry in ipairs(state.bodyParts) do
			if entry.part.Parent then
				entry.part.CFrame = entry.cf0 + bobOffset
			end
		end

		-- Ring precession: tilted loop, tilt-axis azimuth rotates around Y.
		for _, ring in ipairs(state.rings) do
			local spin = (TAU * t / ring.period) * ring.dir + ring.phase
			local ringCF = CFrame.new(ring.center) * CFrame.Angles(0, spin, 0) * CFrame.Angles(ring.tilt, 0, 0)
			for _, entry in ipairs(ring.parts) do
				if entry.part.Parent then
					entry.part.CFrame = ringCF * entry.cf
				end
			end
		end

		-- Crown halo+crown assembly: hover + slow bob + slow yaw, rigid unit.
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

		-- Floating shards: slow desynced orbits around the shell, tiny self-spin.
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
