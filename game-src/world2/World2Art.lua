--!nocheck
--[[
World2Art -- BUILD-TIME ONLY art pass for World 2 (Frozen Tundra), on top of the greybox.

Installed at ServerStorage.World2Blockout.Art. Nothing in the game requires it. Run in Edit mode:

    local A = loadstring(game:GetService("ServerStorage").World2Blockout.Art.Source)()
    A.BuildPeak()      -- the Sundered Peak, a PERSISTENT part model (see below)
    A.BuildNest()      -- Michael's nest at the lookout gallery's west end (moves Michel once)
    ...

Every Build* step owns one folder under Workspace.GameWorld.FrozenTundra.Art and rebuilds it
from scratch, so a step can be re-run after editing numbers. Terrain steps stay outside the lake
zone (World2Blockout's LAKE_BANDS + LAKE_MARGIN) and refuse any write that would reach it.

Compass as in the blockout: N = +Z (up-lake), E = -X, W = +X. Heights are absolute Y.

WHY THE PEAK IS PARTS, NOT TERRAIN. workspace.StreamingEnabled is on and the peak stands
1,500-1,900 studs from the town: measured in Play (2026-09-21), none of its terrain -- nor the
north wall or the falls -- exists on a client standing at the Frostgate. Terrain cannot be made
persistent, so the landmark is a Model with ModelStreamingMode = Persistent (about 80 parts).
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local T = Workspace.Terrain
local MAT = Enum.Material

local M = {}
M.VERSION = 1

local D = 2002   -- datum surface (town floor, lake banks)

-- the blockout generator owns the lake-zone geometry; read it rather than copy it
local function blockout()
	return loadstring(ServerStorage.World2Blockout.Generator.Source)()
end

-- ============================================================== PALETTE
local C = {
	rock = Color3.fromRGB(86, 96, 110),        -- cold blue-grey rock
	rockDark = Color3.fromRGB(58, 66, 78),     -- split faces, shadowed rock
	rockLight = Color3.fromRGB(118, 128, 140),
	snow = Color3.fromRGB(240, 245, 252),
	ice = Color3.fromRGB(200, 232, 250),
	iceDeep = Color3.fromRGB(150, 196, 226),
	timber = Color3.fromRGB(150, 112, 76),
	timberDark = Color3.fromRGB(92, 64, 42),
	timberGrey = Color3.fromRGB(122, 108, 94),  -- weathered
	rope = Color3.fromRGB(196, 170, 120),
	brass = Color3.fromRGB(198, 148, 62),
	gold = Color3.fromRGB(236, 190, 70),
	scarfRed = Color3.fromRGB(196, 58, 52),
	scarfBlue = Color3.fromRGB(64, 110, 190),
	warm = Color3.fromRGB(255, 206, 128),
	lamp = Color3.fromRGB(255, 196, 120),
	straw = Color3.fromRGB(176, 142, 86),
}
M.C = C

-- ============================================================== PART HELPERS
-- Decoration defaults: anchored, no touch, no query, collision only when asked, shadows only
-- for big pieces. Every art part is stamped WorldArt so a performance pass can find them.
local function part(parent, name, size, cf, color, material, opts)
	opts = opts or {}
	local p = Instance.new(opts.class or "Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or MAT.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = opts.collide == true
	p.CanTouch = false
	p.CanQuery = opts.collide == true or opts.query == true
	p.CastShadow = (opts.shadow == true) or (opts.shadow == nil and math.max(size.X, size.Y, size.Z) >= 16)
	if opts.transparency then p.Transparency = opts.transparency end
	if opts.shape and p:IsA("Part") then p.Shape = opts.shape end
	p:SetAttribute("WorldArt", true)
	p.Parent = parent
	return p
end
M.Part = part

local function folder(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function light(p, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = p
	return l
end
M.Light = light

-- one of the game's own faceted rock meshes (the skipping stones), scaled to `size`
local function rock(parent, name, kind, size, cf, color, material, opts)
	opts = opts or {}
	local src = ReplicatedStorage.RockMeshes:FindFirstChild(kind) or ReplicatedStorage.RockMeshes.chunk
	local m = src:Clone()
	m.Name = name
	for _, c in ipairs(m:GetChildren()) do c:Destroy() end
	m.Size = size
	m.CFrame = cf
	m.Color = color
	m.Material = material or MAT.Slate
	m.Anchored = true
	m.CanCollide = opts.collide == true
	m.CanTouch = false
	m.CanQuery = opts.collide == true
	m.CastShadow = opts.shadow ~= false and math.max(size.X, size.Y, size.Z) >= 16
	pcall(function() m.CollisionFidelity = Enum.CollisionFidelity.Box end)
	m:SetAttribute("WorldArt", true)
	m.Parent = parent
	return m
end
M.Rock = rock

-- The art root: Workspace.GameWorld.FrozenTundra.Art, one subfolder per step.
local function artRoot()
	local ft = Workspace.GameWorld.FrozenTundra
	local a = ft:FindFirstChild("Art")
	if not a then
		a = Instance.new("Folder")
		a.Name = "Art"
		a:SetAttribute("ArtVersion", M.VERSION)
		a.Parent = ft
	end
	return a
end
local function freshFolder(name)
	local a = artRoot()
	local old = a:FindFirstChild(name)
	if old then old:Destroy() end
	return folder(a, name)
end

-- ============================================================== LOW-POLY SHAPES
-- A faceted pyramid from four CornerWedgeParts. A CornerWedge's vertical edge sits at its
-- local (+X, -Z) corner (measured 2026-09-21), so each quadrant is yawed until that corner
-- points at the apex. The four extents let the apex sit off-centre, which is what stops a
-- range of these from looking like a row of tents.
--   ext = { xNeg, xPos, zNeg, zPos }   yaw = extra turn of the whole pyramid (degrees)
local QUADS = {
	{ sx = -1, sz = 1, yaw = 0 },
	{ sx = 1, sz = 1, yaw = 90 },
	{ sx = 1, sz = -1, yaw = 180 },
	{ sx = -1, sz = -1, yaw = 270 },
}
local function pyramid(parent, name, apexX, apexZ, baseY, height, ext, yaw, color, material)
	local frame = CFrame.new(apexX, baseY, apexZ) * CFrame.Angles(0, math.rad(yaw or 0), 0)
	local parts = {}
	for _, q in ipairs(QUADS) do
		local w = (q.sx < 0) and ext[1] or ext[2]
		local d = (q.sz < 0) and ext[3] or ext[4]
		local turned = (q.yaw == 90 or q.yaw == 270)
		local size = turned and Vector3.new(d, height, w) or Vector3.new(w, height, d)
		local cf = frame * CFrame.new(q.sx * w / 2, height / 2, q.sz * d / 2) * CFrame.Angles(0, math.rad(q.yaw), 0)
		table.insert(parts, part(parent, name, size, cf, color, material or MAT.Slate, { class = "CornerWedgePart", shadow = false }))
	end
	return parts
end
M.Pyramid = pyramid

-- a snow cap over the top `frac` of a pyramid: same apex, a hair taller and wider, so its
-- faces sit just outside the rock's instead of z-fighting with them
local function snowCap(parent, name, apexX, apexZ, baseY, height, ext, yaw, frac)
	local h = height * frac
	local grow = 1.04
	local capExt = { ext[1] * frac * grow, ext[2] * frac * grow, ext[3] * frac * grow, ext[4] * frac * grow }
	return pyramid(parent, name, apexX, apexZ, baseY + height - h * grow + h * (grow - 1) * 0.5, h * grow, capExt, yaw, C.snow, MAT.Snow)
end

-- ============================================================== THE SUNDERED PEAK
-- Two masses split down the lake's axis (x -8000), the Frozen Falls in the gap, shoulders
-- running out to the rim. Stands behind the north wall (z -6872..-6700), beyond the bounds.
M.PEAK = {
	-- { apexX, apexZ, baseY, height, {xNeg, xPos, zNeg, zPos}, yaw, capFrac or nil, colour }
	-- Sized for the TOWN, not the dock: from the Warming Circle the north wall (2150) hides
	-- everything under about y 2205 at this distance, so the summits have to clear 2900 to
	-- read as a hero mass rather than a ridge on the horizon.
	{ -7860, -6470, 2100, 840, { 175, 345, 265, 290 }, 8, 0.28 },     -- west summit (tallest)
	{ -7958, -6560, 2100, 660, { 60, 185, 160, 185 }, 4, 0.20, "dark" }, -- west split face
	{ -7715, -6520, 2100, 580, { 160, 205, 205, 230 }, -12, 0.25 },   -- west sub-summit
	{ -7585, -6425, 2100, 340, { 140, 195, 185, 205 }, 20, 0.30 },    -- west shoulder
	{ -7440, -6440, 2080, 220, { 170, 215, 195, 215 }, -8, 0.35 },    -- west rim shoulder
	{ -8150, -6455, 2100, 760, { 320, 160, 255, 275 }, -6, 0.28 },    -- east summit
	{ -8042, -6570, 2100, 620, { 170, 60, 160, 185 }, -4, 0.20, "dark" }, -- east split face
	{ -8310, -6515, 2100, 530, { 195, 150, 195, 220 }, 15, 0.25 },    -- east sub-summit
	{ -8420, -6425, 2100, 320, { 170, 140, 170, 195 }, -18, 0.30 },   -- east shoulder
	{ -8560, -6445, 2080, 210, { 205, 170, 195, 215 }, 10, 0.35 },    -- east rim shoulder
}

function M.BuildPeak()
	local f = freshFolder("SunderedPeak")
	local model = Instance.new("Model")
	model.Name = "SunderedPeak"
	-- PERSISTENT: always on every client, whatever the streaming radius (see the header)
	pcall(function() model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent end)
	model.Parent = f
	for i, s in ipairs(M.PEAK) do
		local color = (s[8] == "dark") and C.rockDark or C.rock
		pyramid(model, "Rock" .. i, s[1], s[2], s[3], s[4], s[5], s[6], color, MAT.Slate)
		if s[7] then snowCap(model, "Snow" .. i, s[1], s[2], s[3], s[4], s[5], s[6], s[7]) end
	end
	-- the Frozen Falls: ice columns down the split, a splash mound at their foot
	local falls = {
		{ -8000, 2640, 30, 540, -6612, 0 },
		{ -8017, 2560, 18, 460, -6606, 3 },
		{ -7984, 2590, 20, 490, -6604, -3 },
		{ -8008, 2420, 14, 320, -6598, 5 },
		{ -7991, 2400, 12, 300, -6597, -5 },
	}
	for i, c in ipairs(falls) do
		local x, topY, w, h, z, lean = c[1], c[2], c[3], c[4], c[5], c[6]
		part(model, "Fall" .. i, Vector3.new(w, h, 12), CFrame.new(x, topY - h / 2, z) * CFrame.Angles(0, 0, math.rad(lean)), (i == 1) and C.ice or C.iceDeep, MAT.Ice, { shadow = false })
	end
	pyramid(model, "FallsFoot", -8000, -6600, 2100, 70, { 70, 70, 40, 40 }, 0, C.ice, MAT.Ice)
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
	return ("SunderedPeak: %d parts, persistent"):format(n)
end

-- The terrain peak and falls the blockout put here (World2Blockout.Outside) are replaced by
-- the model above. Only that box is cleared: the rim shoulders either side and the north wall
-- inside the bounds are left alone.
function M.ClearTerrainPeak()
	local B = blockout()
	B.Fill(-8360, -7640, 1966, 2700, -6700, -6300, MAT.Air)
	return "terrain peak cleared (x -8360..-7640, z -6700..-6300)"
end

-- ============================================================== MICHAEL'S NEST
-- Michael perched on the tower's broken top was out of his prompt's reach from the summit
-- and, even from the lookout gallery, ABOVE the camera: a ProximityPrompt is only shown while
-- its part is on screen, so a player walking the gallery never saw his "Talk". His nest now
-- sits at the gallery's west end and he faces the ramp: a player walking in faces him, at eye
-- level, the whole way. Only his model's pivot moves; FrozenTundra.Michel, MichelPrompt and
-- the quest are untouched.
M.NEST = {
	centre = Vector3.new(-7697, 2074, -7988.5),   -- on the gallery deck (top 2074), west end
	face = Vector3.new(1, 0, 0),                  -- toward the ramp top (+X)
}

function M.BuildNest()
	local f = freshFolder("EaglesNest")
	local c = M.NEST.centre
	-- the nest: a rough ring of sticks with a straw lining, sitting on the deck
	local rng = Random.new(914)
	for i = 1, 26 do
		local a = (i / 26) * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
		local r = rng:NextNumber(2.6, 3.3)
		local len = rng:NextNumber(3.2, 4.8)
		local pos = c + Vector3.new(math.cos(a) * r, 0.45 + rng:NextNumber(0, 0.9), math.sin(a) * r)
		local cf = CFrame.lookAt(pos, pos + Vector3.new(-math.sin(a), rng:NextNumber(-0.25, 0.25), math.cos(a)))
			* CFrame.Angles(0, 0, rng:NextNumber(0, math.pi))
		part(f, "Stick", Vector3.new(0.35, 0.35, len), cf, (i % 3 == 0) and C.timberGrey or C.timberDark, MAT.Wood, { shadow = false })
	end
	part(f, "Lining", Vector3.new(0.6, 5.2, 5.2), CFrame.new(c + Vector3.new(0, 0.35, 0)) * CFrame.Angles(0, 0, math.rad(90)), C.straw, MAT.Fabric, { shape = Enum.PartType.Cylinder, shadow = false })
	-- a perch log across the nest for him to stand on
	part(f, "PerchLog", Vector3.new(6.4, 0.9, 0.9), CFrame.new(c + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, math.rad(90), 0), C.timberDark, MAT.Wood, { collide = true, shadow = false, shape = Enum.PartType.Cylinder })
	-- the "borrowed things": two scarves, a lantern, a golden spoon, a coin or two
	part(f, "ScarfRed", Vector3.new(0.25, 0.6, 4.2), CFrame.new(c + Vector3.new(-2.6, 1.0, 1.2)) * CFrame.Angles(math.rad(20), math.rad(25), math.rad(60)), C.scarfRed, MAT.Fabric, { shadow = false })
	part(f, "ScarfBlue", Vector3.new(0.25, 0.5, 3.6), CFrame.new(c + Vector3.new(2.1, 0.9, -2.0)) * CFrame.Angles(math.rad(-15), math.rad(-40), math.rad(70)), C.scarfBlue, MAT.Fabric, { shadow = false })
	local lantern = part(f, "Lantern", Vector3.new(0.9, 1.3, 0.9), CFrame.new(c + Vector3.new(-2.2, 1.35, -2.2)) * CFrame.Angles(0, 0, math.rad(12)), C.lamp, MAT.SmoothPlastic, { shadow = false })
	part(f, "LanternCap", Vector3.new(1.0, 0.25, 1.0), lantern.CFrame * CFrame.new(0, 0.75, 0), C.timberDark, MAT.Metal, { shadow = false })
	light(lantern, C.warm, 12, 0.9)
	part(f, "SpoonHandle", Vector3.new(0.18, 0.12, 2.2), CFrame.new(c + Vector3.new(1.6, 0.95, 1.9)) * CFrame.Angles(0, math.rad(35), math.rad(8)), C.gold, MAT.Metal, { shadow = false })
	part(f, "SpoonBowl", Vector3.new(0.7, 0.25, 0.9), CFrame.new(c + Vector3.new(2.3, 0.95, 2.8)) * CFrame.Angles(0, math.rad(35), 0), C.gold, MAT.Metal, { shadow = false })
	for i, off in ipairs({ Vector3.new(0.6, 0.8, 2.6), Vector3.new(-0.9, 0.8, 2.4), Vector3.new(-3.0, 0.8, -0.4) }) do
		part(f, "Coin", Vector3.new(0.12, 0.7, 0.7), CFrame.new(c + off) * CFrame.Angles(math.rad(80), 0, math.rad(90)), C.gold, MAT.Metal, { shape = Enum.PartType.Cylinder, shadow = false })
	end
	-- the brass telescope on a tripod at the gallery's south rail, aimed at the camps
	local tri = c + Vector3.new(6, 0, -3.5)
	for k = 0, 2 do
		local a = k * math.pi * 2 / 3
		local foot = tri + Vector3.new(math.cos(a) * 1.4, 0, math.sin(a) * 1.4)
		local top = tri + Vector3.new(0, 3.2, 0)
		part(f, "TripodLeg", Vector3.new(0.18, 0.18, (top - foot).Magnitude), CFrame.lookAt((foot + top) / 2, top), C.timberDark, MAT.Wood, { shadow = false })
	end
	local aim = (Vector3.new(-8000, 2010, -7975) - (tri + Vector3.new(0, 3.4, 0))).Unit
	local tube = part(f, "Telescope", Vector3.new(0.55, 0.55, 3.4), CFrame.lookAt(tri + Vector3.new(0, 3.4, 0), tri + Vector3.new(0, 3.4, 0) + aim), C.brass, MAT.Metal, { shadow = false })
	part(f, "TelescopeLens", Vector3.new(0.8, 0.8, 0.35), tube.CFrame * CFrame.new(0, 0, -1.8), C.brass, MAT.Metal, { shadow = false })
	return "nest built at " .. tostring(c)
end

-- Moves Michel onto the perch, once (stamped ArtNest). Feet on the perch log, facing +X.
function M.MoveMichael()
	local ft = Workspace.GameWorld.FrozenTundra
	local michel = ft:FindFirstChild("Michel")
	if not michel then return "no Michel" end
	if michel:GetAttribute("ArtNest") then return "already on the nest" end
	local c = M.NEST.centre
	local cf, size = michel:GetBoundingBox()
	local bottom = cf.Position.Y - size.Y / 2
	local piv = michel:GetPivot()
	-- turn about his own pivot so his look faces NEST.face, then drop his feet onto the log (top 2075.55)
	local look = piv.LookVector
	local yaw = math.atan2(-M.NEST.face.X, -M.NEST.face.Z) - math.atan2(-look.X, -look.Z)
	local turned = CFrame.new(piv.Position) * CFrame.Angles(0, yaw, 0) * (piv - piv.Position)
	local perchTop = c.Y + 1.1 + 0.45
	local target = CFrame.new(c.X, 0, c.Z) * (turned - Vector3.new(turned.Position.X, 0, turned.Position.Z))
	target = target + Vector3.new(0, perchTop - bottom, 0)
	michel:PivotTo(target)
	michel:SetAttribute("ArtNest", true)
	return ("Michael moved to the nest: pivot %s look %s"):format(tostring(michel:GetPivot().Position), tostring(michel:GetPivot().LookVector))
end

-- ============================================================== TERRAIN, LAKE-SAFE
-- Every terrain write goes through here. Its world AABB (rotation included) is tested against
-- each IceFishingConfig lake band grown by the blockout's LAKE_MARGIN on every side; a write
-- that would reach one is skipped and counted, never clipped. The lake fingerprint is checked
-- by the caller after each step.
local lakeBoxes
local function lakeZone()
	if lakeBoxes then return lakeBoxes end
	local B = blockout()
	local m = B.LAKE_MARGIN
	lakeBoxes = {}
	for i, b in ipairs(B.LAKE_BANDS) do
		local z0 = (i == 1) and B.LAKE_SOUTH_Z or b.z0
		table.insert(lakeBoxes, { b.x0 - m, b.x1 + m, z0 - m, b.z1 + m })
	end
	return lakeBoxes
end
local function aabbOf(cf, size)
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	local mn, mx = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
		local c = cf * Vector3.new(sx * hx, sy * hy, sz * hz)
		mn = Vector3.new(math.min(mn.X, c.X), math.min(mn.Y, c.Y), math.min(mn.Z, c.Z))
		mx = Vector3.new(math.max(mx.X, c.X), math.max(mx.Y, c.Y), math.max(mx.Z, c.Z))
	end end end
	return mn, mx
end
local waterBoxes
local function waterZone()
	if waterBoxes then return waterBoxes end
	local B = blockout()
	waterBoxes = {}
	for i, b in ipairs(B.LAKE_BANDS) do
		local z0 = (i == 1) and B.LAKE_SOUTH_Z or b.z0
		table.insert(waterBoxes, { b.x0, b.x1, z0, b.z1 })
	end
	return waterBoxes
end
local HIGH_OK = 2040   -- wholly above this, a write may overhang the margin strip (never the water)
local function lakeSafe(mn, mx)
	local zones = (mn.Y >= HIGH_OK) and waterZone() or lakeZone()
	for _, b in ipairs(zones) do
		if mx.X > b[1] and mn.X < b[2] and mx.Z > b[3] and mn.Z < b[4] then return false end
	end
	return true
end
M.LakeSafe = lakeSafe
local stats = { written = 0, skipped = 0 }
local function tFill(cf, size, material)
	local mn, mx = aabbOf(cf, size)
	if not lakeSafe(mn, mx) then stats.skipped += 1 return false end
	T:FillBlock(cf, size, material)
	stats.written += 1
	return true
end
local function tWedge(cf, size, material)
	local mn, mx = aabbOf(cf, size)
	if not lakeSafe(mn, mx) then stats.skipped += 1 return false end
	T:FillWedge(cf, size, material)
	stats.written += 1
	return true
end
local function tBall(center, r, material)
	if not lakeSafe(center - Vector3.new(r, r, r), center + Vector3.new(r, r, r)) then stats.skipped += 1 return false end
	T:FillBall(center, r, material)
	stats.written += 1
	return true
end
M.TFill, M.TWedge, M.TBall = tFill, tWedge, tBall

-- AIR only, for cuts in the lake cliffs. Those faces sit on the margin line, which runs through
-- the middle of a 4-stud voxel cell; an air box that stops on the line only half-empties that
-- cell, and a half-full cell still renders as a skin of the old face in front of the cut. So a
-- lake-cliff cut runs 2.5 studs past the face -- allowed only wholly above y 2004 and never
-- within 12 studs of open water (the water tops out at 2000 and lies 16 studs off the face).
local function tAirLake(cf, size)
	local mn, mx = aabbOf(cf, size)
	if mn.Y < 2004 then stats.skipped += 1 return false end
	for _, b in ipairs(waterZone()) do
		if mx.X > b[1] - 12 and mn.X < b[2] + 12 and mx.Z > b[3] - 12 and mn.Z < b[4] + 12 then
			stats.skipped += 1
			return false
		end
	end
	T:FillBlock(cf, size, MAT.Air)
	stats.written += 1
	return true
end

-- ============================================================== THE CALDERA WALLS
-- The greybox walls are long flat slabs with a ruler-straight top. This pass works along each
-- visible face -- base polyline, outward normal, floor and top heights -- and adds relief that
-- reads at player height: rock buttresses standing out of the face, snow drifted against its
-- foot, cornices overhanging the top, a glacier icefall now and then, and notches that break
-- the skyline. Faces that meet the lake zone ("carve" faces) only get cut INTO: grooves and
-- top notches, never anything standing out toward the water.
--   { name, {ax, az}, {bx, bz}, normal {nx, nz}, floorY, topY, opts }
--   opts.carve   -- lake-adjacent: cut grooves only
--   opts.skip    -- list of {t0, t1} fractions along the face to leave alone (ramps, doors)
--   opts.nodrift -- no drifts at the foot (the foot is a path or a ramp)
--   opts.small   -- a low face (the 20-stud ledges): smaller pieces, closer together
M.FACES = {
	{ "SouthEast",  { -8212, -8345 }, { -8114, -8345 }, { 0, 1 }, 2002, 2090, {} },
	{ "SouthWest",  { -7886, -8345 }, { -7755, -8345 }, { 0, 1 }, 2002, 2090, {} },
	{ "OverWarm",   { -8114, -8345 }, { -7886, -8345 }, { 0, 1 }, 2044, 2090, { nodrift = true } },
	{ "SEBlock",    { -8212, -8345 }, { -8212, -8270 }, { 1, 0 }, 2002, 2090, {} },
	{ "HighLedge",  { -8245, -8205 }, { -8245, -7700 }, { 1, 0 }, 2002, 2022, { small = true } },
	{ "EastGlacier",{ -8330, -8210 }, { -8330, -7768 }, { 1, 0 }, 2022, 2110, { nodrift = true } },
	{ "NookSouth",  { -8420, -7764 }, { -8330, -7764 }, { 0, 1 }, 2022, 2110, {} },
	{ "NookEast",   { -8420, -7764 }, { -8420, -7560 }, { 1, 0 }, 2022, 2110, { skip = { { 0.18, 0.32 } } } },
	{ "DigShelf",   { -8200, -7700 }, { -8200, -7562 }, { 1, 0 }, 2002, 2022, { small = true, skip = { { 0.0, 0.62 } } } },
	{ "WestLedge",  { -7755, -8345 }, { -7755, -7506 }, { -1, 0 }, 2002, 2022, { small = true, skip = { { 0.16, 0.29 }, { 0.33, 0.38 } } } },
	{ "WestGlacier",{ -7670, -8345 }, { -7670, -7424 }, { -1, 0 }, 2022, 2110, { nodrift = true, skip = { { 0.28, 0.43 } } } },
	{ "NorthEast",  { -8356, -6872 }, { -8048, -6872 }, { 0, -1 }, 2002, 2150, { carve = true } },
	{ "NorthWest",  { -7952, -6872 }, { -7644, -6872 }, { 0, -1 }, 2002, 2150, { carve = true } },
}

local function dressFace(f, rng)
	local A, B = Vector3.new(f[2][1], 0, f[2][2]), Vector3.new(f[3][1], 0, f[3][2])
	local nrm = Vector3.new(f[4][1], 0, f[4][2]).Unit
	local y0, y1 = f[5], f[6]
	local o = f[7] or {}
	local len = (B - A).Magnitude
	local along = (B - A).Unit
	local tall = y1 - y0
	local function skipped(t)
		for _, r in ipairs(o.skip or {}) do if t >= r[1] and t <= r[2] then return true end end
		return false
	end
	local function faceCF(pos) return CFrame.lookAt(pos, pos + nrm) end   -- -Z = out of the face
	local d = 0
	while d < len do
		local step = o.small and rng:NextNumber(18, 34) or rng:NextNumber(28, 56)
		local t = d / len
		local base = A + along * d
		if not skipped(t) then
			if o.carve then
				-- a groove cut into the face, open to the sky, and a notch off the top edge
				local w = rng:NextNumber(10, 22)
				local depth = rng:NextNumber(5, 11)
				local from = y0 + rng:NextNumber(8, 30)
				local c = base - nrm * (depth / 2 - 0.5) + Vector3.new(0, (from + y1 + 6) / 2, 0)
				tFill(faceCF(c) * CFrame.Angles(0, math.rad(rng:NextNumber(-10, 10)), 0), Vector3.new(w, (y1 + 6) - from, depth), MAT.Air)
				if rng:NextNumber() < 0.5 then
					local nw = rng:NextNumber(14, 30)
					local nd = rng:NextNumber(6, 14)
					local c2 = base - nrm * (nd / 2) + along * rng:NextNumber(-10, 10) + Vector3.new(0, y1 - nd * 0.4, 0)
					tFill(faceCF(c2) * CFrame.Angles(math.rad(rng:NextNumber(-20, 20)), 0, math.rad(rng:NextNumber(-25, 25))), Vector3.new(nw, nd, nd * 1.6), MAT.Air)
				end
			elseif o.small then
				-- a low ledge face: boulders half-buried in it, not boxes stuck to it
				local r = rng:NextNumber(3.5, 8)
				local c = base + nrm * (r * rng:NextNumber(0.15, 0.45)) + Vector3.new(0, y0 + r * rng:NextNumber(0.3, 1.2), 0)
				local pick = rng:NextNumber()
				tBall(c, r, (pick < 0.5) and MAT.Slate or (pick < 0.8) and MAT.Rock or MAT.Basalt)
				if rng:NextNumber() < 0.5 then
					tBall(c + along * (r * rng:NextNumber(0.8, 1.4)) + Vector3.new(0, r * rng:NextNumber(-0.3, 0.5), 0), r * rng:NextNumber(0.5, 0.8), MAT.Slate)
				end
				-- snow collected on the ledge top above it
				if rng:NextNumber() < 0.6 then
					tBall(base - nrm * 2 + Vector3.new(0, y1 - 1, 0), rng:NextNumber(4, 7), MAT.Snow)
				end
				if not o.nodrift and rng:NextNumber() < 0.55 then
					local dw = rng:NextNumber(10, 20)
					local dh = rng:NextNumber(3, 6)
					local dd = dh * rng:NextNumber(1.6, 2.4)
					local dc = base + along * (r + dw / 2) + nrm * (dd / 2) + Vector3.new(0, y0 + dh / 2 - 2, 0)
					tWedge(CFrame.lookAt(dc, dc + nrm), Vector3.new(dw, dh, dd), MAT.Snow)
				end
			else
				-- a rock buttress standing out of the face, rooted 8 studs into it: two or three
				-- stacked segments, each narrower and turned its own way, so it reads as rock
				-- that has sheared and slumped rather than a column bolted to the wall
				local w = rng:NextNumber(14, 32)
				local out = rng:NextNumber(4, 12)
				local h = tall * rng:NextNumber(0.45, 1.0)
				local segs = (h > 40) and 3 or 2
				local shares = (segs == 3) and { 0.48, 0.32, 0.20 } or { 0.62, 0.38 }
				local y = y0 - 1
				local mat = (rng:NextNumber() < 0.7) and MAT.Slate or MAT.Rock
				local topCF, topW, topOut
				for k = 1, segs do
					local sh = h * shares[k]
					local sw = w * (1 - 0.18 * (k - 1)) * rng:NextNumber(0.9, 1.1)
					local so = out * (1 - 0.15 * (k - 1))
					local c = base + along * rng:NextNumber(-3, 3) + nrm * (so / 2 - 4) + Vector3.new(0, y + sh / 2, 0)
					local cf = faceCF(c) * CFrame.Angles(math.rad(rng:NextNumber(-6, 6)), math.rad(rng:NextNumber(-16, 16)), math.rad(rng:NextNumber(-5, 5)))
					tFill(cf, Vector3.new(sw, sh + 2, so + 8), mat)
					if rng:NextNumber() < 0.4 then
						tBall(c + nrm * (so / 2) + along * rng:NextNumber(-sw / 3, sw / 3), sw * rng:NextNumber(0.22, 0.34), mat)
					end
					y += sh
					topCF, topW, topOut = cf * CFrame.new(0, sh / 2 + 1, 0), sw, so
				end
				-- snow on its top shoulder
				if topCF then tFill(topCF, Vector3.new(topW * 0.9, 3, topOut + 7), MAT.Snow) end
				-- a snow-covered ledge across the face now and then
				if rng:NextNumber() < 0.3 then
					local lw = rng:NextNumber(20, 40)
					local ly = y0 + tall * rng:NextNumber(0.3, 0.7)
					local lc = base + along * (w / 2 + lw / 2) + nrm * 0.5 + Vector3.new(0, ly, 0)
					tFill(faceCF(lc) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-6, 6))), Vector3.new(lw, 3, 5), MAT.Snow)
				end
				-- now and then a glacier icefall beside it
				if not o.small and rng:NextNumber() < 0.22 then
					local iw = rng:NextNumber(6, 12)
					local ih = tall * rng:NextNumber(0.5, 0.9)
					local ic = base + along * (w / 2 + iw / 2 + 2) + nrm * 0.5 + Vector3.new(0, y0 + ih / 2, 0)
					tFill(faceCF(ic), Vector3.new(iw, ih, 5), MAT.Glacier)
				end
				-- a cornice overhanging the top edge
				if rng:NextNumber() < 0.45 then
					local cw = rng:NextNumber(18, 44)
					local co = rng:NextNumber(3, 6)
					local cc = base + along * rng:NextNumber(-8, 8) + nrm * (co / 2 - 2) + Vector3.new(0, y1 - 2.5, 0)
					tFill(faceCF(cc) * CFrame.Angles(0, math.rad(rng:NextNumber(-8, 8)), 0), Vector3.new(cw, 4, co + 4), MAT.Snow)
				end
				-- a notch off the skyline
				if rng:NextNumber() < 0.35 then
					local nw = rng:NextNumber(10, 24)
					local nd = rng:NextNumber(4, 9)
					local c2 = base + along * rng:NextNumber(-12, 12) - nrm * (nd / 2 - 1) + Vector3.new(0, y1 - nd * 0.35, 0)
					tFill(faceCF(c2) * CFrame.Angles(math.rad(rng:NextNumber(-18, 18)), 0, math.rad(rng:NextNumber(-22, 22))), Vector3.new(nw, nd, nd * 1.5), MAT.Air)
				end
				-- snow drifted against the foot, between buttresses
				if not o.nodrift and rng:NextNumber() < 0.6 then
					local dw = o.small and rng:NextNumber(10, 20) or rng:NextNumber(18, 36)
					local dh = o.small and rng:NextNumber(3, 6) or rng:NextNumber(5, 11)
					local dd = dh * rng:NextNumber(1.6, 2.4)
					local dc = base + along * (w / 2 + dw / 2) + nrm * (dd / 2) + Vector3.new(0, y0 + dh / 2 - 2, 0)
					-- a wedge rises toward its local +Z: point that back at the face
					tWedge(CFrame.lookAt(dc, dc + nrm), Vector3.new(dw, dh, dd), MAT.Snow)
				end
			end
		end
		d += step
	end
end

function M.BuildWalls()
	stats.written, stats.skipped = 0, 0
	local rng = Random.new(20260921)
	for _, f in ipairs(M.FACES) do dressFace(f, rng) end
	return ("walls: %d terrain writes, %d skipped at the lake margin"):format(stats.written, stats.skipped)
end

-- The greybox massifs are Glacier bodies on a Basalt foot, and Glacier's terrain colour is a
-- teal (150, 220, 216) that is global to the place -- it cannot be retinted for World 2 alone.
-- Slate (110, 122, 128) is the cold blue-grey the caldera wants, so the wall bodies change
-- over. Kept as Glacier: the Blue Hollow, the Cellar Pass ice tunnel, the Frozen Falls
-- curtain and apron. (BuildWalls runs after this, so its icefalls stay Glacier too.)
M.RESKIN_KEEP = {
	{ -7640, -7420, 1960, 2120, -7310, -7080 },   -- the Blue Hollow and the ice arch
	{ -8330, -8200, 2020, 2060, -8400, -8250 },   -- the Cellar Pass tunnel and portal chamber
	{ -8050, -7950, 1990, 2440, -6880, -6690 },   -- the Frozen Falls notch, curtain and apron
}
function M.ReskinWalls()
	local keep = M.RESKIN_KEEP
	local n = 0
	local function overlaps(x0, x1, z0, z1)
		for _, k in ipairs(keep) do
			if x1 > k[1] and x0 < k[2] and z1 > k[5] and z0 < k[6] then return true end
		end
		return false
	end
	local function swap(x0, x1, z0, z1)
		T:ReplaceMaterial(Region3.new(Vector3.new(x0, 2008, z0), Vector3.new(x1, 2160, z1)):ExpandToGrid(4), 4, MAT.Glacier, MAT.Slate)
		n += 1
	end
	-- 256-stud tiles; a tile that touches a keep box is done in 16-stud columns instead
	for x0 = -8600, -7401, 256 do
		for z0 = -8600, -6701, 256 do
			local x1, z1 = math.min(x0 + 256, -7400), math.min(z0 + 256, -6700)
			if not overlaps(x0, x1, z0, z1) then
				swap(x0, x1, z0, z1)
			else
				for cx = x0, x1 - 1, 16 do
					for cz = z0, z1 - 1, 16 do
						if not overlaps(cx, cx + 16, cz, cz + 16) then swap(cx, cx + 16, cz, cz + 16) end
					end
				end
			end
		end
	end
	return ("reskin: %d regions Glacier -> Slate (y 2008..2160)"):format(n)
end

-- The cliffs along both lake shores stand exactly on the lake margin and follow the stepped
-- band outline, so they read as a staircase of flat slabs -- and they are what a player looks at
-- while skipping. They are CUT, never added to: grooves into the face and notches off the
-- skyline; and snow cornices along the top edge, which overhang only the margin strip and only
-- above HIGH_OK.
function M.BuildLakeWalls()
	stats.written, stats.skipped = 0, 0
	local B = blockout()
	local m = B.LAKE_MARGIN
	local rng = Random.new(6872)
	local TOP = 2110
	for side = -1, 1, 2 do    -- -1: the east shore (x < lake), +1: the west shore
		local stepLeft = rng:NextNumber(1, 3)   -- stretches until the next skyline step-down
		for i, b in ipairs(B.LAKE_BANDS) do
			local zStart = (side < 0) and -7560 or -7420
			local z0, z1 = math.max(b.z0, zStart), b.z1
			if z1 > z0 then
				local faceX = (side < 0) and (b.x0 - m) or (b.x1 + m)
				local nrm = Vector3.new((side < 0) and 1 or -1, 0, 0)   -- points at the water
				local function faceCF(pos) return CFrame.lookAt(pos, pos + nrm) end
				-- Cuts end EXACTLY on the face, which is the margin line, and are only ever
				-- turned in the plane of the face: any yaw would swing a corner into the margin.
				-- Seen from the dock these faces run almost along the line of sight, so what
				-- reads is the PLAN outline: whole stretches are cut back, full height, and
				-- the fins between them catch the light.
				local z = z0
				while z < z1 - 2 do
					local stretch = math.min(rng:NextNumber(26, 80), z1 - z)
					local zc = z + stretch / 2
					local base = Vector3.new(faceX, 0, zc)
					if rng:NextNumber() < 0.55 then
						local back = rng:NextNumber(6, 22)
						local c = base - nrm * (back / 2 - 1.25) + Vector3.new(0, (2005 + TOP + 8) / 2, 0)
						tAirLake(faceCF(c), Vector3.new(stretch - 2, (TOP + 8) - 2005, back + 2.5))
						-- the new face gets a glacier skin now and then
						if rng:NextNumber() < 0.3 then
							tFill(faceCF(base - nrm * (back + 1.5) + Vector3.new(0, (2012 + TOP) / 2, 0)), Vector3.new(stretch * 0.5, TOP - 2012, 4), MAT.Glacier)
						end
					else
						-- a stretch left standing gets a gully
						local w = rng:NextNumber(10, 22)
						local depth = rng:NextNumber(10, 20)
						local from = 2002 + rng:NextNumber(12, 40)
						local c = base - nrm * (depth / 2 - 1.25) + Vector3.new(0, (from + TOP + 6) / 2, 0)
						tAirLake(faceCF(c), Vector3.new(w, (TOP + 6) - from, depth + 2.5))
					end
					-- a skyline step: the cliff top dropped along this stretch, snow on the step
					stepLeft -= 1
					if stepLeft <= 0 then
						local drop = rng:NextNumber(16, 45)
						local back = rng:NextNumber(40, 80)
						local sc = base - nrm * (back / 2 - 1.25) + Vector3.new(0, TOP - drop / 2 + 3, 0)
						tAirLake(faceCF(sc), Vector3.new(stretch, drop + 6, back + 2.5))
						tFill(faceCF(base - nrm * (back / 2 + 1) + Vector3.new(0, TOP - drop - 1, 0)), Vector3.new(stretch - 2, 3, back - 2), MAT.Snow)
						stepLeft = rng:NextNumber(1, 3)
					end
					-- a snow cornice lip over the face (above HIGH_OK, into the margin strip only)
					if rng:NextNumber() < 0.45 then
						local cw = math.min(stretch, rng:NextNumber(14, 30))
						local co = rng:NextNumber(3, 5)
						local cc = Vector3.new(faceX, TOP - 1.5, zc) + nrm * (co / 2 - 1.5)
						tFill(faceCF(cc), Vector3.new(cw, 4, co + 3), MAT.Snow)
					end
					z += stretch
				end
			end
		end
	end
	return ("lake walls: %d cuts/lips, %d skipped"):format(stats.written, stats.skipped)
end

-- ============================================================== GROUND
-- the terrain surface under (x, z), looked for within +-reach of `near`; nil if none there
local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { T }
local function groundAt(x, z, near, reach)
	reach = reach or 10
	local hit = Workspace:Raycast(Vector3.new(x, near + reach, z), Vector3.new(0, -2 * reach, 0), terrainOnly)
	if hit then return hit.Position.Y, hit.Material end
	return nil
end
M.GroundAt = groundAt
local function onGround(x, z, near) return Vector3.new(x, groundAt(x, z, near or D, 12) or (near or D), z) end
M.OnGround = onGround

-- a timber (or any) beam from a to b
local function beam(parent, name, a, b, thick, color, material, opts)
	return part(parent, name, Vector3.new(thick, thick, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), color, material or MAT.Wood, opts or { shadow = false })
end
M.Beam = beam

-- ============================================================== PATHS (terrain paint)
-- The greybox paths were flat strips laid on the snow; the art pass paints them INTO the ground:
-- ReplaceMaterial of Snow only, one 4-stud voxel column at a time, at the height a raycast finds,
-- so paint can never raise, lower or add terrain. Cobblestone for the town's street and the
-- Warming Circle, Sandstone for every road and trail -- picked against Mud, Ground, Limestone
-- and Pavement in eye-level samples (2026-09-21): Limestone and Pavement vanish on the snow,
-- Ground is busy, Mud is heavy. Edges wander a little (noise), like trodden paths do.
-- Nothing is painted inside the lake guard, nor within 8 studs of the dock and the ThrowZone.
--   { name, material, width, { { x, z, surface y }, ... } }
M.PATHS = {
	{ "Avenue", MAT.Cobblestone, 22, { { -8000, -8150, 2002 }, { -8000, -7822, 2002 } } },
	-- a spur from the Avenue to each camp, up its terrace ramp (foot 60 studs from the camp's
	-- centre, terrace edge at 42, +5)
	{ "SpurPlot7", MAT.Sandstone, 8, { { -8011, -8065, 2002 }, { -8065, -8065, 2002 }, { -8083, -8065, 2007 } } },
	{ "SpurPlot8", MAT.Sandstone, 8, { { -8011, -7975, 2002 }, { -8065, -7975, 2002 }, { -8083, -7975, 2007 } } },
	{ "SpurPlot9", MAT.Sandstone, 8, { { -8011, -7885, 2002 }, { -8065, -7885, 2002 }, { -8083, -7885, 2007 } } },
	{ "SpurPlot10", MAT.Sandstone, 8, { { -7989, -7885, 2002 }, { -7935, -7885, 2002 }, { -7917, -7885, 2007 } } },
	{ "SpurPlot11", MAT.Sandstone, 8, { { -7989, -7975, 2002 }, { -7935, -7975, 2002 }, { -7917, -7975, 2007 } } },
	{ "SpurPlot12", MAT.Sandstone, 8, { { -7989, -8065, 2002 }, { -7935, -8065, 2002 }, { -7917, -8065, 2007 } } },
	{ "EastRoad", MAT.Sandstone, 12, { { -8045, -8195, 2002 }, { -8215, -8180, 2002 }, { -8215, -7832, 2002 } } },
	{ "WestRoad", MAT.Sandstone, 12, { { -7955, -8195, 2002 }, { -7785, -8180, 2002 }, { -7785, -7832, 2002 } } },
	{ "Promenade", MAT.Sandstone, 12, { { -8215, -7832, 2002 }, { -7785, -7832, 2002 } } },
	{ "EastShore", MAT.Sandstone, 10, { { -8215, -7832, 2002 }, { -8195, -7760, 2002 }, { -8192, -7708, 2002 } } },
	{ "DigRamp", MAT.Sandstone, 9, { { -8192, -7708, 2002 }, { -8192, -7626, 2022 } } },
	{ "DigTrail", MAT.Sandstone, 8, { { -8192, -7626, 2022 }, { -8238, -7660, 2022 }, { -8290, -7700, 2022 }, { -8349, -7700, 2022 } } },
	{ "WestShore", MAT.Sandstone, 10, { { -7785, -7832, 2002 }, { -7800, -7760, 2002 }, { -7805, -7680, 2002 }, { -7790, -7600, 2002 }, { -7770, -7530, 2002 }, { -7757, -7490, 2002 }, { -7752, -7470, 2002 } } },
	-- round the south side of Nico's lodge to the Squeeze's mouth: the shore path ends at his door
	-- and the canyon opens behind the lodge, so without this nothing leads you there (walked in
	-- Play 2026-09-21: a player heading straight for the mouth walks into the lodge's back wall)
	{ "NicoToSqueeze", MAT.Sandstone, 7, { { -7757, -7490, 2002 }, { -7730, -7496, 2002 }, { -7706, -7490, 2002 }, { -7692, -7470, 2002 } } },
	{ "Squeeze", MAT.Sandstone, 6, { { -7692, -7470, 2002 }, { -7650, -7452, 1999 }, { -7620, -7420, 1996 }, { -7596, -7380, 1993 }, { -7572, -7330, 1990 }, { -7560, -7292, 1987 }, { -7550, -7262, 1984 } } },
	{ "Frostgate", MAT.Sandstone, 10, { { -8240, -8262, 2030 }, { -8218, -8238, 2030 }, { -8196, -8222, 2030 } } },
	{ "FrostgateDescent", MAT.Sandstone, 12, { { -8196, -8222, 2030 }, { -8138, -8222, 2016 }, { -8114, -8222, 2016 }, { -8050, -8200, 2002 } } },
	{ "FrostgateEast", MAT.Sandstone, 8, { { -8240, -8262, 2030 }, { -8270, -8232, 2030 }, { -8285, -8214, 2030 } } },
	{ "LedgeRamp", MAT.Sandstone, 9, { { -8285, -8214, 2030 }, { -8285, -8182, 2022 } } },
	{ "HighLedge", MAT.Sandstone, 9, { { -8285, -8182, 2022 }, { -8290, -8150, 2022 }, { -8290, -7712, 2022 } } },
	{ "CragRamp", MAT.Sandstone, 9, { { -7768, -8190, 2002 }, { -7768, -8126, 2022 } } },
	{ "CragLedge", MAT.Sandstone, 7, { { -7768, -8126, 2022 }, { -7745, -8118, 2022 }, { -7745, -8080, 2022 } } },
	{ "CragSummit", MAT.Sandstone, 7, { { -7685, -8049, 2048 }, { -7662, -8042, 2048 } } },
}
M.CIRCLE = { x = -8000, z = -8195, r = 40 }
M.TENTS = { { -7858, -8233, 18 }, { -7812, -8240, -38 } }   -- the expedition camp's two tents
M.NO_PAINT = { { -8040, -7960, -7828, -7780 } }   -- x0, x1, z0, z1: the dock and the ThrowZone, +8

local function noPaint(x, z)
	for _, b in ipairs(M.NO_PAINT) do
		if x > b[1] and x < b[2] and z > b[3] and z < b[4] then return true end
	end
	return false
end

function M.BuildTerrainPaths()
	stats.written, stats.skipped = 0, 0
	local miss = 0
	local done = {}
	local function tile(cx, cz, expectY, mat)
		local k = cx .. "," .. cz
		if done[k] then return end
		done[k] = true
		if noPaint(cx, cz) then stats.skipped += 1 return end
		local y = groundAt(cx, cz, expectY, 6)
		if not y then miss += 1 return end
		local mn, mx = Vector3.new(cx - 2, y - 5, cz - 2), Vector3.new(cx + 2, y + 1, cz + 2)
		if not lakeSafe(mn, mx) then stats.skipped += 1 return end
		T:ReplaceMaterial(Region3.new(mn, mx):ExpandToGrid(4), 4, MAT.Snow, mat)
		stats.written += 1
	end
	-- the Circle first, so where a road meets it the cobbles win
	local c = M.CIRCLE
	for gx = math.floor((c.x - c.r - 4) / 4) * 4 + 2, c.x + c.r + 4, 4 do
		for gz = math.floor((c.z - c.r - 4) / 4) * 4 + 2, c.z + c.r + 4, 4 do
			local d = Vector2.new(gx - c.x, gz - c.z).Magnitude
			if d <= c.r + math.noise(gx * 0.07, gz * 0.07, 3.1) * 5 then tile(gx, gz, D, MAT.Cobblestone) end
		end
	end
	for _, path in ipairs(M.PATHS) do
		local mat, w, pts = path[2], path[3], path[4]
		for i = 1, #pts - 1 do
			local a, b = Vector2.new(pts[i][1], pts[i][2]), Vector2.new(pts[i + 1][1], pts[i + 1][2])
			local ya, yb = pts[i][3], pts[i + 1][3]
			local ab = b - a
			local lo = Vector2.new(math.min(a.X, b.X) - w, math.min(a.Y, b.Y) - w)
			local hi = Vector2.new(math.max(a.X, b.X) + w, math.max(a.Y, b.Y) + w)
			for gx = math.floor(lo.X / 4) * 4 + 2, hi.X, 4 do
				for gz = math.floor(lo.Y / 4) * 4 + 2, hi.Y, 4 do
					local q = Vector2.new(gx, gz)
					local t = math.clamp((q - a):Dot(ab) / ab:Dot(ab), 0, 1)
					local half = w / 2 + math.noise(gx * 0.09, gz * 0.09, 7.7) * 3
					if (q - (a + ab * t)).Magnitude <= half then tile(gx, gz, ya + (yb - ya) * t, mat) end
				end
			end
		end
	end
	return ("paths: %d columns painted, %d held back (lake guard / dock), %d found no ground"):format(stats.written, stats.skipped, miss)
end

-- ============================================================== THE TOWN (Frostwatch)
-- The game's fire, built the way the lodge hearths and the skip-area brazier are: a small Neon
-- ember bed with a Fire in it and one warm PointLight (the house values), plus logs.
local function campfire(parent, pos, lightRange, lightBright)
	local f = folder(parent, "Campfire")
	for k = 0, 4 do
		local a = k / 5 * math.pi * 2 + 0.3
		local foot = pos + Vector3.new(math.cos(a) * 2.6, 0.3, math.sin(a) * 2.6)
		local top = pos + Vector3.new(math.cos(a) * 0.45, 3.2, math.sin(a) * 0.45)
		beam(f, "Log", foot, top, 0.8, C.timberDark)
	end
	local bed = part(f, "Embers", Vector3.new(3.2, 0.5, 3.2), CFrame.new(pos + Vector3.new(0, 0.25, 0)), Color3.fromRGB(214, 110, 52), MAT.Neon, { shadow = false })
	local fire = Instance.new("Fire")
	fire.Size = 7
	fire.Heat = 9
	fire.Color = Color3.fromRGB(236, 139, 70)
	fire.SecondaryColor = Color3.fromRGB(139, 80, 55)
	fire.Parent = bed
	light(bed, Color3.fromRGB(255, 168, 88), lightRange or 34, lightBright or 1.6)
	return f
end
M.Campfire = campfire

local STONE = Color3.fromRGB(122, 116, 108)   -- warm grey: the palette's rock greys read blue on snow
local function stoneRing(parent, centre, r, n, size, seed)
	local rng = Random.new(seed)
	for i = 1, n do
		local a = (i / n) * math.pi * 2 + rng:NextNumber(-0.12, 0.12)
		local sz = size * rng:NextNumber(0.8, 1.2)
		rock(parent, "RingStone", (i % 2 == 0) and "chunk" or "rounded", Vector3.new(sz, sz * 0.75, sz),
			CFrame.new(centre + Vector3.new(math.cos(a) * r, sz * 0.2, math.sin(a) * r)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			STONE, MAT.Slate, { shadow = false })
	end
end
M.StoneRing = stoneRing

local function logBench(parent, pos, yaw)
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yaw), 0)
	part(parent, "Bench", Vector3.new(7.5, 1.3, 1.3), cf * CFrame.new(0, 1.8, 0), C.timber, MAT.Wood, { collide = true, shape = Enum.PartType.Cylinder, shadow = false })
	for _, sx in ipairs({ -2.6, 2.7 }) do
		part(parent, "BenchStump", Vector3.new(1.3, 1.25, 1.3), cf * CFrame.new(sx, 0.62, 0), C.timberDark, MAT.Wood, { shadow = false })
	end
end
M.LogBench = logBench

local function woodpile(parent, pos, yaw)
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yaw), 0)
	for _, row in ipairs({ { n = 4, y = 0.45 }, { n = 3, y = 1.2 }, { n = 2, y = 1.95 } }) do
		for i = 1, row.n do
			local z = (i - (row.n + 1) / 2) * 0.88
			part(parent, "Firewood", Vector3.new(4.2, 0.85, 0.85), cf * CFrame.new(0, row.y, z), (i % 2 == 0) and C.timber or C.timberDark, MAT.Wood,
				{ shape = Enum.PartType.Cylinder, shadow = false })
		end
	end
end
M.Woodpile = woodpile

-- the cooking tripod over a fire: three iron legs, a hook, a pot
local IRON = Color3.fromRGB(48, 48, 52)
local function tripod(parent, pos)
	local apex = pos + Vector3.new(0, 6.6, 0)
	for k = 0, 2 do
		local a = k / 3 * math.pi * 2 + 0.5
		beam(parent, "TripodLeg", pos + Vector3.new(math.cos(a) * 3.4, 0, math.sin(a) * 3.4), apex, 0.26, IRON, MAT.Metal)
	end
	part(parent, "PotHook", Vector3.new(0.14, 1.8, 0.14), CFrame.new(apex - Vector3.new(0, 0.9, 0)), IRON, MAT.Metal, { shadow = false })
	part(parent, "Pot", Vector3.new(2, 2.2, 2.2), CFrame.new(apex - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.rad(90)), IRON, MAT.Metal,
		{ shape = Enum.PartType.Cylinder, shadow = false })
end

-- words on both faces of a board
local function boardText(board, text, maxDist, pad)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local g = Instance.new("SurfaceGui")
		g.Face = face
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = 40
		g.LightInfluence = 0.7
		g.MaxDistance = maxDist
		g.Parent = board
		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, -2 * pad, 1, -pad)
		t.Position = UDim2.fromOffset(pad, pad / 2)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.TextColor3 = Color3.fromRGB(255, 242, 216)
		t.TextStrokeTransparency = 0.4
		t.TextStrokeColor3 = Color3.fromRGB(58, 38, 22)
		t.Text = text
		t.Parent = g
	end
end
M.BoardText = boardText

-- a sign board shaped as an arrow; `cf` is the board's centre with +X pointing where it points
local function signBoard(parent, cf, text, w)
	local b = part(parent, "SignBoard", Vector3.new(w, 1.25, 0.25), cf, C.timber, MAT.Wood, { shadow = false })
	part(parent, "SignTip", Vector3.new(0.88, 0.88, 0.25), cf * CFrame.new(w / 2, 0, 0) * CFrame.Angles(0, 0, math.rad(45)), C.timber, MAT.Wood, { shadow = false })
	boardText(b, text, 120, 4)
	return b
end

-- the town signpost: one arrow per destination, each turned to point AT it
local function signpost(parent, pos, entries, seed)
	local rng = Random.new(seed)
	part(parent, "SignPost", Vector3.new(0.9, 12.5, 0.9), CFrame.new(pos + Vector3.new(0, 6.25, 0)), C.timberDark, MAT.Wood, { collide = true, shadow = false })
	part(parent, "SignPostCap", Vector3.new(1.3, 0.45, 1.3), CFrame.new(pos + Vector3.new(0, 12.7, 0)), C.snow, MAT.Snow, { shadow = false })
	for i, e in ipairs(entries) do
		local dir = Vector3.new(e[2].X - pos.X, 0, e[2].Z - pos.Z).Unit
		local w = e[3]
		local cf = CFrame.fromMatrix(pos + Vector3.new(0, 12 - i * 1.45, 0) + dir * (w / 2 + 0.3), dir, Vector3.yAxis)
		signBoard(parent, cf * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-3, 3))), e[1], w)
	end
end
M.Signpost = signpost

-- a street lantern: timber post, braced arm, a lamp hanging toward `armDir` (SmoothPlastic plus
-- one PointLight -- the lighting rule: no Neon lamps under Bloom)
local function lanternPost(parent, pos, armDir, lit)
	local cf = CFrame.lookAt(pos, pos + armDir)   -- -Z = along the arm
	part(parent, "Post", Vector3.new(0.9, 11, 0.9), cf * CFrame.new(0, 5.5, 0), C.timberDark, MAT.Wood, { collide = true, shadow = false })
	part(parent, "PostCap", Vector3.new(1.25, 0.4, 1.25), cf * CFrame.new(0, 11.2, 0), C.snow, MAT.Snow, { shadow = false })
	part(parent, "Arm", Vector3.new(0.45, 0.45, 3.1), cf * CFrame.new(0, 10.3, -1.35), C.timberDark, MAT.Wood, { shadow = false })
	beam(parent, "Brace", (cf * CFrame.new(0, 8.7, -0.45)).Position, (cf * CFrame.new(0, 10.1, -1.9)).Position, 0.28, C.timberDark)
	part(parent, "Chain", Vector3.new(0.12, 0.7, 0.12), cf * CFrame.new(0, 9.75, -2.55), IRON, MAT.Metal, { shadow = false })
	part(parent, "LampCap", Vector3.new(1.15, 0.3, 1.15), cf * CFrame.new(0, 9.3, -2.55), IRON, MAT.Metal, { shadow = false })
	local lamp = part(parent, "Lamp", Vector3.new(0.85, 1.15, 0.85), cf * CFrame.new(0, 8.6, -2.55), C.lamp, MAT.SmoothPlastic, { shadow = false })
	part(parent, "LampBase", Vector3.new(1.0, 0.2, 1.0), cf * CFrame.new(0, 7.95, -2.55), IRON, MAT.Metal, { shadow = false })
	if lit then light(lamp, C.warm, 18, 0.8) end
	return lamp
end
M.LanternPost = lanternPost

local function crate(parent, pos, size, yaw, color)
	local cf = CFrame.new(pos + Vector3.new(0, size / 2, 0)) * CFrame.Angles(0, math.rad(yaw), 0)
	part(parent, "Crate", Vector3.new(size, size, size), cf, color or C.timber, MAT.WoodPlanks, { collide = true, shadow = size >= 4 })
	for _, y in ipairs({ size / 2 - 0.18, -size / 2 + 0.18 }) do
		part(parent, "CrateBand", Vector3.new(size + 0.08, 0.28, size + 0.08), cf * CFrame.new(0, y, 0), C.timberDark, MAT.Wood, { shadow = false })
	end
end
M.Crate = crate

local function sled(parent, pos, yaw, load)
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yaw), 0)
	for _, sx in ipairs({ -1.6, 1.6 }) do
		part(parent, "Runner", Vector3.new(0.35, 0.35, 8), cf * CFrame.new(sx, 0.2, 0), C.timberDark, MAT.Wood, { shadow = false })
		beam(parent, "RunnerTip", (cf * CFrame.new(sx, 0.2, -3.9)).Position, (cf * CFrame.new(sx, 1.4, -4.6)).Position, 0.35, C.timberDark)
		for _, z in ipairs({ -2.4, 0.2, 2.8 }) do
			part(parent, "Stanchion", Vector3.new(0.3, 0.7, 0.3), cf * CFrame.new(sx, 0.7, z), C.timberDark, MAT.Wood, { shadow = false })
		end
	end
	part(parent, "SledDeck", Vector3.new(3.7, 0.3, 6.6), cf * CFrame.new(0, 1.15, 0.2), C.timber, MAT.WoodPlanks, { shadow = false })
	if load then
		part(parent, "SledLoad", Vector3.new(2.9, 1.9, 3.6), cf * CFrame.new(0, 2.25, 1.1), Color3.fromRGB(96, 110, 84), MAT.Fabric, { shadow = false })
		part(parent, "SledRope", Vector3.new(3.0, 0.14, 0.14), cf * CFrame.new(0, 3.22, 0.5), C.rope, MAT.Fabric, { shadow = false })
		part(parent, "SledRope", Vector3.new(3.0, 0.14, 0.14), cf * CFrame.new(0, 3.22, 1.8), C.rope, MAT.Fabric, { shadow = false })
	end
end
M.Sled = sled

-- a stashed World 2 prop (the old village's tents), cloned onto the ground at (x, z)
local function stashed(parent, path, x, z, yaw, drop)
	local node = ServerStorage.World2Backups_2026_09_19.RemovedFromWorkspace
	for n in path:gmatch("[^%.]+") do node = node and node:FindFirstChild(n) end
	if not node then return nil end
	local m = node:Clone()
	for _, d in ipairs(m:GetDescendants()) do
		if drop and drop[d.Name] then d:Destroy() end
	end
	m:PivotTo(CFrame.new(x, D, z) * CFrame.Angles(0, math.rad(yaw), 0))
	local bb, sz = m:GetBoundingBox()
	local g = groundAt(x, z, D, 12) or D
	m:PivotTo(m:GetPivot() + Vector3.new(0, g - (bb.Y - sz.Y / 2) - 0.25, 0))
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			if d.Material == MAT.Neon then d.Material = MAT.SmoothPlastic end   -- no Neon lamps under Bloom
			if math.max(d.Size.X, d.Size.Y, d.Size.Z) < 8 then d.CastShadow = false end
			d.CanTouch = false
			d:SetAttribute("WorldArt", true)
		elseif d:IsA("Light") then
			d.Brightness = math.min(d.Brightness, 0.6)
			d.Shadows = false
		end
	end
	m.Parent = parent
	return m
end
M.Stashed = stashed

-- the town gate over the Avenue's mouth: two posts, a double lintel, knee braces, the name board
local function archway(parent, x0, x1, z, text)
	local f = folder(parent, "Archway")
	local g0, g1 = onGround(x0, z), onGround(x1, z)
	local top = math.max(g0.Y, g1.Y) + 16
	for i, g in ipairs({ g0, g1 }) do
		local inward = (i == 1) == (x1 > x0) and 1 or -1   -- toward the other post
		part(f, "GatePost", Vector3.new(1.8, top - g.Y + 1, 1.8), CFrame.new(g.X, (g.Y + top + 1) / 2 - 0.5, z), C.timberDark, MAT.Wood, { collide = true, shadow = true })
		part(f, "PostCap", Vector3.new(2.3, 0.5, 2.3), CFrame.new(g.X, top + 1.25, z), C.snow, MAT.Snow, { shadow = false })
		beam(f, "KneeBrace", Vector3.new(g.X, top - 4.5, z), Vector3.new(g.X + inward * 3.6, top - 0.6, z), 0.7, C.timberDark)
	end
	local span = math.abs(x1 - x0)
	local mid = (x0 + x1) / 2
	part(f, "Lintel", Vector3.new(span + 4.5, 1.6, 1.8), CFrame.new(mid, top, z), C.timberDark, MAT.Wood, { shadow = true })
	part(f, "LintelLower", Vector3.new(span - 1.8, 0.9, 1.2), CFrame.new(mid, top - 1.9, z), C.timber, MAT.Wood, { shadow = false })
	part(f, "LintelSnow", Vector3.new(span + 4, 0.55, 1.9), CFrame.new(mid, top + 1.05, z), C.snow, MAT.Snow, { shadow = false })
	for _, dx in ipairs({ -4.6, 4.6 }) do
		part(f, "SignChain", Vector3.new(0.14, 1.9, 0.14), CFrame.new(mid + dx, top - 3.3, z), IRON, MAT.Metal, { shadow = false })
	end
	local board = part(f, "NameBoard", Vector3.new(12.5, 2.7, 0.35), CFrame.new(mid, top - 5.5, z), C.timber, MAT.WoodPlanks, { shadow = false })
	part(f, "NameBoardSnow", Vector3.new(12.5, 0.3, 0.45), CFrame.new(mid, top - 4.02, z), C.snow, MAT.Snow, { shadow = false })
	boardText(board, text, 260, 8)
	return f
end

function M.BuildTown()
	local f = freshFolder("Town")
	local cc = onGround(M.CIRCLE.x, M.CIRCLE.z)

	-- the Warming Circle: a stone-ringed fire with a cooking pot, three benches, a woodpile
	local circle = folder(f, "WarmingCircle")
	stoneRing(circle, cc, 4.4, 11, 1.5, 11)
	campfire(circle, cc, 34, 1.6)
	tripod(circle, cc)
	for _, b in ipairs({ { 38, 11.5, 4 }, { 146, 12.5, -5 }, { 292, 11, 2 } }) do
		local a = math.rad(b[1])
		logBench(circle, onGround(cc.X + math.cos(a) * b[2], cc.Z + math.sin(a) * b[2]), -b[1] + 90 + b[3])
	end
	woodpile(circle, onGround(cc.X + math.cos(math.rad(214)) * 15, cc.Z + math.sin(math.rad(214)) * 15), -214)

	-- the signpost at the Circle's north-east edge, where the roads split
	signpost(circle, onGround(-8030, -8166), {
		{ "EAGLE'S CRAG", Vector3.new(-7700, 0, -8005), 6.4 },
		{ "THE DOCK", Vector3.new(-8000, 0, -7818), 5.2 },
		{ "NICO'S POINT", Vector3.new(-7731, 0, -7470), 6.4 },
		{ "ELDER'S DIG", Vector3.new(-8370, 0, -7700), 6 },
		{ "WARMHOUSE", Vector3.new(-8000, 0, -8250), 5.8 },
		{ "TO THE VALLEY", Vector3.new(-8114, 0, -8222), 6.6 },
	}, 5)

	-- the Avenue: a gate at its mouth, then lanterns staggered down both sides
	archway(f, -8015, -7985, -8140, "FROSTWATCH")
	local av = folder(f, "AvenueLanterns")
	for _, l in ipairs({ { -8015, -8098 }, { -7985, -8036 }, { -8015, -7968 }, { -7985, -7902 }, { -8015, -7846 } }) do
		lanternPost(av, onGround(l[1], l[2]), Vector3.new((l[1] < -8000) and 1 or -1, 0, 0), true)
	end

	-- the expedition's camp, between the Warmhouse and the crag ramp: two old tents, a cold
	-- fire pit, supplies, a loaded sled
	local camp = folder(f, "ExpeditionCamp")
	for _, t in ipairs(M.TENTS) do
		stashed(camp, "Village.Tent", t[1], t[2], t[3], { TentBank = true })   -- BuildTownTerrain banks real snow round them
	end
	local pit = onGround(-7836, -8224)
	stoneRing(camp, pit, 2.6, 8, 1.1, 23)
	for k = 0, 2 do
		local a = k * 2.1 + 0.4
		part(camp, "CharredLog", Vector3.new(0.7, 0.7, 3.2), CFrame.new(pit + Vector3.new(math.cos(a) * 0.6, 0.35, math.sin(a) * 0.6)) * CFrame.Angles(0, a, math.rad(8)),
			Color3.fromRGB(44, 38, 34), MAT.Wood, { shadow = false })
	end
	part(camp, "Ash", Vector3.new(0.25, 3.6, 3.6), CFrame.new(pit + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(96, 96, 100), MAT.Slate,
		{ shape = Enum.PartType.Cylinder, shadow = false })
	local stack = onGround(-7874, -8214)
	crate(camp, stack, 4.2, 12)
	crate(camp, onGround(-7869, -8217.5), 3.4, 40)
	crate(camp, stack + Vector3.new(0.3, 4.2, 0.2), 2.7, -8, C.timberGrey)
	crate(camp, onGround(-7799, -8219), 3.6, 25)
	sled(camp, onGround(-7826, -8207), 74, true)
	return "town: circle, signpost, gate, 5 lanterns, expedition camp"
end

-- ============================================================== THE FROSTGATE
-- a timber fence: posts every `every` studs on the ground, two continuous rails, snow caps
local function fence(parent, a, b, height, every)
	local len = (b - a).Magnitude
	local n = math.max(1, math.floor(len / every + 0.5))
	local tops = {}
	for i = 0, n do
		local q = a:Lerp(b, i / n)
		local g = onGround(q.X, q.Z, q.Y)
		part(parent, "FencePost", Vector3.new(0.8, height + 0.6, 0.8), CFrame.new(g + Vector3.new(0, (height + 0.6) / 2 - 0.6, 0)), C.timberDark, MAT.Wood, { collide = true, shadow = false })
		part(parent, "FenceCap", Vector3.new(1.05, 0.3, 1.05), CFrame.new(g + Vector3.new(0, height + 0.15, 0)), C.snow, MAT.Snow, { shadow = false })
		table.insert(tops, g)
	end
	local ga, gb = tops[1], tops[#tops]
	for _, h in ipairs({ height * 0.45, height * 0.88 }) do
		beam(parent, "FenceRail", ga + Vector3.new(0, h, 0), gb + Vector3.new(0, h, 0), 0.35, C.timber, MAT.Wood, { collide = true, shadow = false })
	end
end
M.Fence = fence

function M.BuildFrostgate()
	local f = freshFolder("Frostgate")
	-- the overlook's two open edges, where the greybox had flat rails (same lines, same gaps:
	-- the descent leaves through the corner between them, the ledge ramp past the north rail's end)
	fence(f, Vector3.new(-8245, 2030, -8212.6), Vector3.new(-8191, 2030, -8212.6), 3.4, 6)
	fence(f, Vector3.new(-8190.6, 2030, -8262), Vector3.new(-8190.6, 2030, -8233), 3.4, 6)
	return "frostgate: overlook fence"
end

-- ============================================================== THE WARMHOUSE
-- The greybox hall stays as the working shell (its walls, the floor, and the five stalls inside).
-- The art pass dresses it: a lean-to roof rising to the cliff it is built into, a timber frame
-- and a stone plinth on the facade, a porch over the door, framed windows, the name board,
-- lanterns at the door, taller chimneys with a little smoke, icicles on the eave.
M.WARMHOUSE = { x0 = -8112, x1 = -7888, zFront = -8250, cliffZ = -8345, h = 36, doorX0 = -8014, doorX1 = -7986, doorH = 20 }
local LOGWALL = Color3.fromRGB(150, 104, 70)   -- a redder brown: a plain one reads green in the facade's blue shade
local PANE = Color3.fromRGB(156, 92, 40)       -- deep amber Neon: glows warm, stays under Bloom's threshold

local function smoke(parent, at)
	local anchor = part(parent, "SmokeAt", Vector3.new(1, 1, 1), CFrame.new(at), C.snow, MAT.SmoothPlastic, { transparency = 1, shadow = false })
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Rate = 2.5
	e.Lifetime = NumberRange.new(6, 9)
	e.Speed = NumberRange.new(3, 5)
	e.SpreadAngle = Vector2.new(10, 10)
	e.Acceleration = Vector3.new(1.4, 0.6, 0.4)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 13) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	e.Color = ColorSequence.new(Color3.fromRGB(222, 226, 232))
	e.RotSpeed = NumberRange.new(-12, 12)
	e.Rotation = NumberRange.new(0, 360)
	e.LightInfluence = 0.8
	e.Parent = anchor
	return e
end

local function wallLantern(parent, pos, outward)
	local cf = CFrame.lookAt(pos, pos + outward)   -- -Z = away from the wall
	part(parent, "Bracket", Vector3.new(0.35, 0.35, 1.8), cf * CFrame.new(0, 1.1, -0.9), IRON, MAT.Metal, { shadow = false })
	part(parent, "LampCap", Vector3.new(1.1, 0.3, 1.1), cf * CFrame.new(0, 0.75, -1.7), IRON, MAT.Metal, { shadow = false })
	local lamp = part(parent, "Lamp", Vector3.new(0.85, 1.15, 0.85), cf * CFrame.new(0, 0, -1.7), C.lamp, MAT.SmoothPlastic, { shadow = false })
	part(parent, "LampBase", Vector3.new(1.0, 0.2, 1.0), cf * CFrame.new(0, -0.65, -1.7), IRON, MAT.Metal, { shadow = false })
	light(lamp, C.warm, 16, 0.9)
end

function M.BuildWarmhouse()
	local W = M.WARMHOUSE
	local f = freshFolder("Warmhouse")
	local zF = W.zFront + 0.9          -- the facade faces +Z (the town); its frame stands proud of the wall
	local eave = D + W.h               -- 2038: the flat roof's underside
	local gb = Workspace.GameWorld.FrozenTundra:FindFirstChild("Greybox")
	local shell = gb and gb:FindFirstChild("Warmhouse")
	if shell then
		for _, q in ipairs(shell:GetDescendants()) do
			if q:IsA("BasePart") and q.Name:match("^Wall") then
				q.Color = LOGWALL
				-- the greybox roof slab starts 0.05 above the wall tops: sky showed through the slit,
				-- a hairline of light round the whole hall. Close it (once) from below.
				local top = q.Position.Y + q.Size.Y / 2
				if math.abs(top - eave) < 0.02 then
					q.Size += Vector3.new(0, 0.1, 0)
					q.Position += Vector3.new(0, 0.05, 0)
				end
			end
			if q:IsA("BasePart") and q.Name == "WarmWindow" then q.Material = MAT.Neon; q.Color = PANE; q.Transparency = 0 end
		end
	end

	-- the timber frame: posts between the windows and at the door, the eave beam, the door-head beam
	for _, x in ipairs({ -8111, -8062.5, -8013.9, -7986.1, -7937.5, -7889 }) do
		part(f, "FramePost", Vector3.new(2.2, W.h, 2.2), CFrame.new(x, D + W.h / 2, zF), C.timberDark, MAT.Wood, { collide = true, shadow = true })
	end
	part(f, "EaveBeam", Vector3.new(W.x1 - W.x0 + 3, 2, 2.4), CFrame.new((W.x0 + W.x1) / 2, eave - 1, zF + 0.1), C.timberDark, MAT.Wood, { shadow = true })
	part(f, "HeadBeam", Vector3.new(W.x1 - W.x0 + 2, 1.6, 2.0), CFrame.new((W.x0 + W.x1) / 2, D + W.doorH + 0.8, zF + 0.1), C.timber, MAT.Wood, { shadow = false })
	-- the stone plinth, broken at the door, and along the two side walls to the cliff
	for _, run in ipairs({ { W.x0 - 0.5, W.doorX0 - 1.6 }, { W.doorX1 + 1.6, W.x1 + 0.5 } }) do
		part(f, "Plinth", Vector3.new(run[2] - run[1], 2.8, 1.8), CFrame.new((run[1] + run[2]) / 2, D + 1.2, W.zFront + 0.6), STONE, MAT.Slate, { collide = true, shadow = false })
	end
	for _, x in ipairs({ W.x0 - 0.6, W.x1 + 0.6 }) do
		part(f, "Plinth", Vector3.new(1.8, 2.8, W.zFront - W.cliffZ), CFrame.new(x, D + 1.2, (W.zFront + W.cliffZ) / 2), STONE, MAT.Slate, { collide = true, shadow = false })
		part(f, "CornerPost", Vector3.new(2.2, W.h, 2.2), CFrame.new(x, D + W.h / 2, W.cliffZ + 1.5), C.timberDark, MAT.Wood, { collide = true, shadow = true })
	end

	-- framed windows round the greybox's four warm panes
	for _, x in ipairs({ -8080, -8045, -7955, -7920 }) do
		local y0, y1 = D + 10, D + 16
		local zc = W.zFront + 0.75
		part(f, "WindowHead", Vector3.new(16, 0.9, 1.1), CFrame.new(x, y1 + 0.45, zc), C.timberDark, MAT.Wood, { shadow = false })
		part(f, "WindowSill", Vector3.new(16.6, 0.8, 1.6), CFrame.new(x, y0 - 0.4, zc + 0.2), C.timberDark, MAT.Wood, { shadow = false })
		for _, sx in ipairs({ -1, 1 }) do
			part(f, "WindowJamb", Vector3.new(0.9, y1 - y0, 1.1), CFrame.new(x + sx * 7.45, (y0 + y1) / 2, zc), C.timberDark, MAT.Wood, { shadow = false })
		end
		part(f, "Mullion", Vector3.new(0.45, y1 - y0, 0.8), CFrame.new(x, (y0 + y1) / 2, zc), C.timberDark, MAT.Wood, { shadow = false })
		part(f, "Transom", Vector3.new(14, 0.4, 0.8), CFrame.new(x, (y0 + y1) / 2 + 0.6, zc), C.timberDark, MAT.Wood, { shadow = false })
		part(f, "SillSnow", Vector3.new(16.2, 0.35, 1.5), CFrame.new(x, y0 + 0.17, zc + 0.25), C.snow, MAT.Snow, { shadow = false })
	end

	-- the porch over the door, on two log posts, snow on it
	local pz0, pz1 = W.zFront + 0.5, W.zFront + 12.5   -- at the wall, the outer edge
	local hi, lo = D + W.doorH + 6.5, D + W.doorH + 3
	local run = pz1 - pz0
	local slope = math.atan2(hi - lo, run)
	local pcf = CFrame.new(-8000, (hi + lo) / 2, (pz0 + pz1) / 2) * CFrame.Angles(slope, 0, 0)   -- local +Z (outward) drops
	part(f, "PorchRoof", Vector3.new(38, 0.8, run / math.cos(slope)), pcf, C.timberDark, MAT.WoodPlanks, { shadow = true })
	part(f, "PorchSnow", Vector3.new(37.4, 0.7, run / math.cos(slope) - 0.4), pcf * CFrame.new(0, 0.72, 0), C.snow, MAT.Snow, { shadow = false })
	part(f, "PorchFascia", Vector3.new(38.4, 1.1, 0.9), CFrame.new(-8000, lo - 0.3, pz1 + 0.1), C.timber, MAT.Wood, { shadow = false })
	for _, x in ipairs({ -8017.5, -7982.5 }) do
		part(f, "PorchPost", Vector3.new(1.5, lo - D, 1.5), CFrame.new(x, D + (lo - D) / 2, pz1 - 1), C.timberDark, MAT.Wood, { collide = true, shadow = false })
		beam(f, "PorchBrace", Vector3.new(x, lo - 3.5, pz1 - 1), Vector3.new(x, lo - 0.6, pz1 - 4.2), 0.55, C.timberDark)
	end

	-- the name board on the facade over the porch, and a lantern either side of the door
	local nb = part(f, "NameBoard", Vector3.new(34, 5.2, 0.6), CFrame.new(-8000, D + 31, W.zFront + 2.5), C.timber, MAT.WoodPlanks, { shadow = false })
	part(f, "NameBoardRim", Vector3.new(35.2, 6.4, 0.4), CFrame.new(-8000, D + 31, W.zFront + 2.15), C.timberDark, MAT.Wood, { shadow = false })
	boardText(nb, "THE WARMHOUSE", 320, 12)
	for _, x in ipairs({ -8021.5, -7978.5 }) do
		wallLantern(f, Vector3.new(x, D + 13, W.zFront + 0.2), Vector3.new(0, 0, 1))
	end

	-- the lean-to roof: rises from the eave to the cliff (a WedgePart rises toward its local +Z,
	-- so +Z is turned to face the cliff), snow-covered, a timber fascia along the front, timber
	-- gable ends
	local rz0, rz1 = W.zFront + 2.0, W.cliffZ - 1   -- the eave overhangs the facade by 2
	local rise = 12
	local base = eave + 2.5                       -- on top of the greybox roof slab and its snow
	local rcf = CFrame.new((W.x0 + W.x1) / 2, base + rise / 2, (rz0 + rz1) / 2) * CFrame.Angles(0, math.rad(180), 0)
	part(f, "RoofSnow", Vector3.new(W.x1 - W.x0 + 3, rise, rz0 - rz1), rcf, C.snow, MAT.Snow, { class = "WedgePart", shadow = true })
	for _, x in ipairs({ W.x0 - 2.1, W.x1 + 2.1 }) do
		part(f, "Gable", Vector3.new(1.2, rise, rz0 - rz1), CFrame.new(x, base + rise / 2, (rz0 + rz1) / 2) * CFrame.Angles(0, math.rad(180), 0),
			C.timberDark, MAT.WoodPlanks, { class = "WedgePart", shadow = false })
	end
	part(f, "Fascia", Vector3.new(W.x1 - W.x0 + 5, 2.2, 1.4), CFrame.new((W.x0 + W.x1) / 2, base - 0.4, W.zFront + 2.4), C.timberDark, MAT.Wood, { shadow = false })
	-- icicles under the eave, irregular
	local rng = Random.new(41)
	local x = W.x0 + rng:NextNumber(3, 9)
	while x < W.x1 - 3 do
		if x < W.doorX0 - 6 or x > W.doorX1 + 6 then
			local len = rng:NextNumber(1.4, 4.2)
			part(f, "Icicle", Vector3.new(0.5, len, 0.5), CFrame.new(x, base - 1.5 - len / 2, W.zFront + 2.6) * CFrame.Angles(0, rng:NextNumber(0, 3), 0),
				C.ice, MAT.Ice, { shadow = false })
		end
		x += rng:NextNumber(7, 19)
	end

	-- the chimneys, taller now the roof rises (they are at the cliff end), capped, smoking
	for _, cx in ipairs({ -8070, -7930 }) do
		part(f, "ChimneyTop", Vector3.new(11, 10, 11), CFrame.new(cx, D + 50 + 5, -8324), STONE, MAT.Slate, { shadow = true })
		part(f, "ChimneyCap", Vector3.new(13, 1, 13), CFrame.new(cx, D + 60.5, -8324), Color3.fromRGB(88, 84, 80), MAT.Slate, { shadow = false })
		smoke(f, Vector3.new(cx, D + 62, -8324))
	end
	return "warmhouse dressed"
end

-- The hall's inside is kept clear of terrain: the wall dressing's bulges on the cliff face it is
-- built into came through its back wall (279 cells along z -8354..-8334, measured 2026-09-21).
function M.ClearWarmhouseInterior()
	stats.written, stats.skipped = 0, 0
	local W = M.WARMHOUSE
	-- out to the side walls' OUTER faces and up through the ceiling's cell: a half-cleared voxel
	-- cell leaves its surface right on the wall's inner face, where it flickers
	local x0, x1, z0, z1 = W.x0, W.x1, -8383, W.zFront - 2
	local y0, y1 = D + 0.6, D + W.h + 2
	tFill(CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), Vector3.new(x1 - x0, y1 - y0, z1 - z0), MAT.Air)
	return ("warmhouse interior kept clear (%d write)"):format(stats.written)
end

-- Inside: roof beams on wall posts, a central hearth under an iron hood with benches and a rug,
-- the eight hall lamps as hanging lanterns (same places and light as the greybox lamps, a touch
-- dimmer), and banners on the walls. Nothing stands in front of a stall or its prompt.
function M.BuildWarmhouseInterior()
	local W = M.WARMHOUSE
	local f = freshFolder("WarmhouseInterior")
	local ceil = D + W.h
	local zBack, zFront = -8383, W.zFront - 2
	-- beams across the hall, and the posts that carry them against the front and back walls
	for _, x in ipairs({ -8084, -8056, -8028, -7972, -7944, -7916 }) do
		part(f, "RoofBeam", Vector3.new(2, 2.2, zFront - zBack), CFrame.new(x, ceil - 1.1, (zBack + zFront) / 2), C.timberDark, MAT.Wood, { shadow = false })
		for _, z in ipairs({ zFront - 0.9, zBack + 0.9 }) do
			part(f, "WallPost", Vector3.new(1.8, W.h, 1.8), CFrame.new(x, D + W.h / 2, z), C.timberDark, MAT.Wood, { collide = true, shadow = false })
		end
	end
	part(f, "RidgeBeam", Vector3.new(W.x1 - W.x0 - 4, 2, 2), CFrame.new((W.x0 + W.x1) / 2, ceil - 3.2, -8317), C.timberDark, MAT.Wood, { shadow = false })

	-- the hearth: a stone surround, the fire, an iron hood and flue, benches, a rug
	local hp = Vector3.new(-8000, D + 0.05, -8315)
	local hearth = folder(f, "Hearth")
	stoneRing(hearth, hp, 5.2, 13, 1.7, 31)
	campfire(hearth, hp, 36, 1.8)
	pyramid(hearth, "Hood", hp.X, hp.Z, D + 17, 6, { 6.5, 6.5, 6.5, 6.5 }, 0, IRON, MAT.Metal)
	part(hearth, "Flue", Vector3.new(ceil - (D + 22.5), 2.4, 2.4), CFrame.new(hp.X, (D + 22.5 + ceil) / 2, hp.Z) * CFrame.Angles(0, 0, math.rad(90)), IRON, MAT.Metal,
		{ shape = Enum.PartType.Cylinder, shadow = false })
	part(hearth, "RugBorder", Vector3.new(30, 0.12, 24), CFrame.new(hp + Vector3.new(0, 0.06, 0)), Color3.fromRGB(214, 196, 160), MAT.Fabric, { shadow = false })
	part(hearth, "Rug", Vector3.new(28, 0.16, 22), CFrame.new(hp + Vector3.new(0, 0.1, 0)), Color3.fromRGB(122, 46, 42), MAT.Fabric, { shadow = false })
	for _, b in ipairs({ { 28, 12.5, 3 }, { 118, 12, -4 }, { 206, 12.5, 2 }, { 298, 12, -3 } }) do
		local a = math.rad(b[1])
		logBench(hearth, hp + Vector3.new(math.cos(a) * b[2], 0.15, math.sin(a) * b[2]), -b[1] + 90 + b[3])
	end

	-- the hall lamps, as hanging lanterns on chains from the beams' height
	for _, x in ipairs({ -8070, -8025, -7975, -7930 }) do
		for _, z in ipairs({ -8290, -8345 }) do
			local y = D + 28
			part(f, "Chain", Vector3.new(0.16, ceil - (y + 1.2), 0.16), CFrame.new(x, (y + 1.2 + ceil) / 2, z), IRON, MAT.Metal, { shadow = false })
			part(f, "LampCap", Vector3.new(1.9, 0.45, 1.9), CFrame.new(x, y + 1.15, z), IRON, MAT.Metal, { shadow = false })
			local lamp = part(f, "Lamp", Vector3.new(1.4, 1.9, 1.4), CFrame.new(x, y, z), C.lamp, MAT.SmoothPlastic, { shadow = false })
			part(f, "LampBase", Vector3.new(1.7, 0.3, 1.7), CFrame.new(x, y - 1.1, z), IRON, MAT.Metal, { shadow = false })
			light(lamp, C.warm, 40, 1.1)
		end
	end

	-- banners: Frostwatch blue with a cream band, on a rod; two per side wall, two on the back
	local function banner(cf)
		part(f, "BannerRod", Vector3.new(6.4, 0.35, 0.35), cf * CFrame.new(0, 6.3, 0), C.timberDark, MAT.Wood, { shadow = false })
		part(f, "Banner", Vector3.new(5, 12, 0.18), cf, Color3.fromRGB(46, 90, 158), MAT.Fabric, { shadow = false })
		part(f, "BannerBand", Vector3.new(5.02, 1.1, 0.2), cf * CFrame.new(0, -3.6, 0), Color3.fromRGB(226, 212, 180), MAT.Fabric, { shadow = false })
	end
	for _, z in ipairs({ -8292, -8336 }) do
		banner(CFrame.new(W.x0 + 2.2, D + 22, z) * CFrame.Angles(0, math.rad(90), 0))
		banner(CFrame.new(W.x1 - 2.2, D + 22, z) * CFrame.Angles(0, math.rad(-90), 0))
	end
	for _, x in ipairs({ -8070, -7930 }) do
		banner(CFrame.new(x, D + 22, zBack + 0.2))
	end
	return "warmhouse interior dressed"
end

-- ============================================================== SITE TERRAIN (snow)
-- Snow banked round Elder Tung's hut: along its back and sides, never across the door or the porch.
function M.BuildSiteTerrain()
	stats.written, stats.skipped = 0, 0
	local rng = Random.new(2022)
	local c = Vector3.new(-8374, 0, -7700)
	-- the hut is ~16 deep (x) by ~20 wide (z); its door faces +X
	local ring = {}
	for z = -7711, -7689, 3.6 do table.insert(ring, Vector3.new(-8384, 0, z)) end              -- back
	for x = -8382, -8368, 3.6 do table.insert(ring, Vector3.new(x, 0, -7712)); table.insert(ring, Vector3.new(x, 0, -7688)) end   -- sides
	for _, q in ipairs(ring) do
		local g = onGround(q.X, q.Z, 2022)
		local r = rng:NextNumber(2.2, 3.1)
		tBall(g + Vector3.new(0, -r * 0.5, 0), r, MAT.Snow)
	end
	return ("site terrain: %d banks round the hut"):format(stats.written)
end

-- ============================================================== TOWN TERRAIN (snow)
-- Low wind drifts on the open town floor, snow banked round the tents, faint plough ridges along
-- the Avenue. Snow only, small (a mound tops out at ~2.5 studs), only on the datum floor, never on
-- a path, a plot terrace, the Circle, a building or a prop -- and every write lake-guarded.
M.KEEP_CLEAR = {   -- x0, x1, z0, z1
	{ -8167, -8083, -8105, -8025 }, { -8167, -8083, -8015, -7935 }, { -8167, -8083, -7925, -7845 },   -- Plots 7-9
	{ -7917, -7833, -7925, -7845 }, { -7917, -7833, -8015, -7935 }, { -7917, -7833, -8105, -8025 },   -- Plots 10-12
	{ -8114, -7886, -8389, -8238 },   -- the Warmhouse and its porch
	{ -8062, -8034, -8168, -8110 },   -- leaderboards
	{ -7972, -7938, -8145, -8110 },   -- the wheel
	{ -7890, -7780, -8255, -8198 },   -- the expedition camp
	{ -8040, -7960, -7840, -7780 },   -- the dock and the ThrowZone
	{ -8036, -8024, -8172, -8160 },   -- the signpost
	{ -8020, -7980, -8146, -8134 },   -- the town gate
}
local function inKeepClear(x, z, margin)
	for _, b in ipairs(M.KEEP_CLEAR) do
		if x > b[1] - margin and x < b[2] + margin and z > b[3] - margin and z < b[4] + margin then return true end
	end
	return false
end
local function nearPath(x, z, extra)
	local q = Vector2.new(x, z)
	if (q - Vector2.new(M.CIRCLE.x, M.CIRCLE.z)).Magnitude < M.CIRCLE.r + extra then return true end
	for _, path in ipairs(M.PATHS) do
		local pts = path[4]
		for i = 1, #pts - 1 do
			local a, b = Vector2.new(pts[i][1], pts[i][2]), Vector2.new(pts[i + 1][1], pts[i + 1][2])
			local ab = b - a
			local t = math.clamp((q - a):Dot(ab) / ab:Dot(ab), 0, 1)
			if (q - (a + ab * t)).Magnitude < path[3] / 2 + 3 + extra then return true end
		end
	end
	return false
end
M.NearPath = nearPath

function M.BuildTownTerrain()
	stats.written, stats.skipped = 0, 0
	local rng = Random.new(20260922)
	-- snow banked round each tent's foot (the tent model's own flat collar is dropped)
	for _, t in ipairs(M.TENTS) do
		local g = onGround(t[1], t[2])
		for k = 0, 6 do
			local a = k / 7 * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
			local r = rng:NextNumber(2.4, 3.2)
			tBall(g + Vector3.new(math.cos(a) * 6, -r * 0.55, math.sin(a) * 6), r, MAT.Snow)
		end
	end
	-- wind drifts, long along the up-lake wind (+-20 degrees), at least 38 studs apart
	local drifts = {}
	local tries = 0
	while #drifts < 32 and tries < 900 do
		tries += 1
		local x, z = rng:NextNumber(-8236, -7764), rng:NextNumber(-8336, -7700)
		local y = groundAt(x, z, D, 4)
		local ok = y and math.abs(y - D) < 1.2 and not inKeepClear(x, z, 9) and not nearPath(x, z, 8)
		if ok then
			for _, d in ipairs(drifts) do
				if (d - Vector2.new(x, z)).Magnitude < 38 then ok = false break end
			end
		end
		if ok then
			table.insert(drifts, Vector2.new(x, z))
			local yaw = math.rad(rng:NextNumber(-20, 20))
			local dir = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
			local len = rng:NextNumber(16, 36)
			local n = math.max(3, math.floor(len / 7))
			local peak = rng:NextNumber(5.5, 8)
			for i = 0, n - 1 do
				local t = i / (n - 1)
				local r = peak * (0.55 + 0.45 * math.sin(t * math.pi))
				local c = Vector3.new(x, y, z) + dir * ((t - 0.5) * len) + Vector3.new(0, -r * 0.72, 0)
				-- only if this ball's own footprint stays clear too
				if not nearPath(c.X, c.Z, r * 0.7) and not inKeepClear(c.X, c.Z, r * 0.7) then tBall(c, r, MAT.Snow) end
			end
		end
	end
	-- plough ridges along both sides of the Avenue, gapped at the camp spurs and now and then
	local ridges = 0
	for _, side in ipairs({ -1, 1 }) do
		local z = -8106
		while z < -7836 do
			local atSpur = math.abs(z + 8065) < 13 or math.abs(z + 7975) < 13 or math.abs(z + 7885) < 13
			local atPost = false
			for _, l in ipairs({ -8098, -8036, -7968, -7902, -7846 }) do
				if math.abs(z - l) < 3 then atPost = true end
			end
			if not atSpur and not atPost and math.noise(z * 0.045, side * 3.3) > -0.25 then
				local r = rng:NextNumber(2.2, 2.9)
				local off = 11 + 4.2 + math.noise(z * 0.08, side) * 1.2
				local g = onGround(-8000 + side * off, z)
				if tBall(g + Vector3.new(0, -r * 0.62, 0), r, MAT.Snow) then ridges += 1 end
			end
			z += 3.2
		end
	end
	return ("town terrain: %d drifts, %d ridge balls, %d writes, %d held back by the lake guard"):format(#drifts, ridges, stats.written, stats.skipped)
end

-- ============================================================== STASH PLACEMENT
-- A stashed model turned by `yawDelta` about its own centre, its centre moved to (x, z), and
-- dropped until the part named `foot` stands on the ground. Same rules as `stashed`.
local function placeStash(parent, path, x, z, yawDelta, foot, near, drop)
	local node = ServerStorage.World2Backups_2026_09_19.RemovedFromWorkspace
	for n in path:gmatch("[^%.]+") do node = node and node:FindFirstChild(n) end
	if not node then return nil end
	local m = node:Clone()
	for _, d in ipairs(m:GetDescendants()) do
		if drop and drop[d.Name] then d:Destroy() end
	end
	local bb = m:GetBoundingBox()
	m:PivotTo(CFrame.new(x, bb.Y, z) * CFrame.Angles(0, math.rad(yawDelta), 0) * CFrame.new(-bb.Position) * m:GetPivot())
	local f = m:FindFirstChild(foot, true)
	local g = groundAt(x, z, near or D, 14) or (near or D)
	local bottom = f and (f.Position.Y - f.Size.Y / 2) or (m:GetBoundingBox().Y - select(2, m:GetBoundingBox()).Y / 2)
	m:PivotTo(m:GetPivot() + Vector3.new(0, g - bottom - 0.15, 0))
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			if d.Material == MAT.Neon then d.Material = MAT.SmoothPlastic end   -- no Neon lamps under Bloom
			if math.max(d.Size.X, d.Size.Y, d.Size.Z) < 8 then d.CastShadow = false end
			d.CanTouch = false
			d:SetAttribute("WorldArt", true)
		elseif d:IsA("Light") then
			d.Brightness = math.min(d.Brightness, 0.8)
			d.Shadows = false
		end
	end
	m.Parent = parent
	return m
end
M.PlaceStash = placeStash

-- a small fish: a rounded rock mesh for the body, a wedge tail
local function fish(parent, cf, len, color)
	rock(parent, "FishBody", "rounded", Vector3.new(len, len * 0.36, len * 0.22), cf, color, MAT.SmoothPlastic, { shadow = false })
	part(parent, "FishTail", Vector3.new(len * 0.08, len * 0.34, len * 0.28), cf * CFrame.new(-len * 0.56, 0, 0) * CFrame.Angles(0, math.rad(90), 0),
		color, MAT.SmoothPlastic, { class = "WedgePart", shadow = false })
end
local FISH = { Color3.fromRGB(150, 168, 186), Color3.fromRGB(176, 150, 118), Color3.fromRGB(128, 150, 168) }

-- ============================================================== ELDER'S DIG
local OLD_BRASS = Color3.fromRGB(140, 104, 48)

-- the point on `target`'s surface met by a ray from `origin` along `dir`, and its normal
local function surfaceOf(target, origin, dir)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { target }
	local hit = Workspace:Raycast(origin, dir, rp)
	if hit then return hit.Position, hit.Normal end
	return nil
end
-- Elder Tung's own hut from the old tundra comes back as his station: same character, same
-- belongings (the sahur bat included). It is turned so its door opens west onto the greybox
-- porch, towards the drill and where Tung stands. Around it the dig tells its story: the
-- listening horn aimed at the Crack, the Crack itself roped off, the ancient stone, scaffolding
-- on the glacier wall, tools. Nothing is placed on the drill site, the shaft trigger, or Tung.
function M.BuildDig()
	local f = freshFolder("EldersDig")
	-- its six "Drift" parts were flat snow slabs for the old ground (two landed on the porch):
	-- BuildSiteTerrain banks real snow round it instead
	placeStash(f, "ElderHut", -8374, -7700, -45, "Plinth", 2022, { Drift = true })

	-- the listening horn: a timber stand, a brass horn stepping out to a bell, aimed down at the Crack
	local hornAt = onGround(-8370, -7741, 2022)
	local aim = (Vector3.new(-8361, hornAt.Y, -7748) - hornAt)
	local yaw = math.atan2(-aim.X, -aim.Z)
	local frame = CFrame.new(hornAt) * CFrame.Angles(0, yaw, 0)
	for _, sx in ipairs({ -1.4, 1.4 }) do
		beam(f, "HornLeg", (frame * CFrame.new(sx, 0, 1.2)).Position, (frame * CFrame.new(sx * 0.3, 5.2, 0)).Position, 0.45, C.timberDark)
		beam(f, "HornLeg", (frame * CFrame.new(sx, 0, -1.2)).Position, (frame * CFrame.new(sx * 0.3, 5.2, 0)).Position, 0.45, C.timberDark)
	end
	local tube = frame * CFrame.new(0, 5.5, 0) * CFrame.Angles(math.rad(-22), 0, 0)   -- tilted down toward -Z (the aim)
	local steps = { { 1.0, 3.0 }, { 1.6, 2.4 }, { 2.4, 1.8 }, { 4.2, 0.9 } }       -- diameter, length
	local z = 1.2
	for i, st in ipairs(steps) do
		z -= st[2] / 2
		part(f, (i == #steps) and "HornBell" or "HornTube", Vector3.new(st[2], st[1], st[1]), tube * CFrame.new(0, 0, z) * CFrame.Angles(0, math.rad(90), 0),
			OLD_BRASS, MAT.Metal, { shape = Enum.PartType.Cylinder, shadow = false })
		z -= st[2] / 2
	end
	part(f, "HornEarpiece", Vector3.new(1.4, 0.7, 0.7), tube * CFrame.new(0, 0.4, 2.1) * CFrame.Angles(0, math.rad(90), math.rad(40)), OLD_BRASS, MAT.Metal,
		{ shape = Enum.PartType.Cylinder, shadow = false })

	-- the Crack: a jagged dark rift in the shelf, roped off on stakes
	local rng = Random.new(808)
	local pts = {}
	for i = 0, 7 do
		table.insert(pts, Vector3.new(-8361 + rng:NextNumber(-1.6, 1.6), 0, -7761 + i * 4.1))
	end
	for i = 1, #pts - 1 do
		local a, b = onGround(pts[i].X, pts[i].Z, 2022), onGround(pts[i + 1].X, pts[i + 1].Z, 2022)
		local w = rng:NextNumber(0.9, 1.9)
		part(f, "Crack", Vector3.new(w, 0.12, (b - a).Magnitude + 0.6), CFrame.lookAt((a + b) / 2 + Vector3.new(0, 0.05, 0), b + Vector3.new(0, 0.05, 0)),
			Color3.fromRGB(20, 28, 40), MAT.SmoothPlastic, { shadow = false })
		part(f, "CrackIce", Vector3.new(w + 1.4, 0.08, (b - a).Magnitude + 1.2), CFrame.lookAt((a + b) / 2 + Vector3.new(0, 0.02, 0), b + Vector3.new(0, 0.02, 0)),
			Color3.fromRGB(120, 178, 214), MAT.Ice, { shadow = false })
	end
	local stakes = { { -8366.5, -7764 }, { -8355.5, -7764 }, { -8355.5, -7729 }, { -8366.5, -7729 } }
	local tops = {}
	for _, st in ipairs(stakes) do
		local g = onGround(st[1], st[2], 2022)
		part(f, "Stake", Vector3.new(0.4, 3.4, 0.4), CFrame.new(g + Vector3.new(0, 1.5, 0)) * CFrame.Angles(math.rad(rng:NextNumber(-5, 5)), 0, math.rad(rng:NextNumber(-5, 5))),
			C.timberDark, MAT.Wood, { shadow = false })
		table.insert(tops, g + Vector3.new(0, 2.9, 0))
	end
	for i = 1, #tops do
		local a, b = tops[i], tops[i % #tops + 1]
		beam(f, "Rope", a, b, 0.14, C.rope, MAT.Fabric)
		part(f, "RopeFlag", Vector3.new(0.05, 0.7, 0.9), CFrame.lookAt((a + b) / 2 - Vector3.new(0, 0.45, 0), b - Vector3.new(0, 0.45, 0)) * CFrame.Angles(0, math.rad(90), 0),
			C.scarfRed, MAT.Fabric, { shadow = false })
	end

	-- the ancient stone: a standing stone of stacked faceted rock, glyphs cut into the face it
	-- turns to the dig (set onto the mesh's real surface by raycast), snow on its shoulders
	local sp = onGround(-8420, -7700, 2022)
	local SLAB = Color3.fromRGB(132, 126, 118)
	local body = rock(f, "AncientStone", "chunk", Vector3.new(10, 22, 13), CFrame.new(sp + Vector3.new(0, 9.5, 0)) * CFrame.Angles(math.rad(2), math.rad(8), math.rad(-3)),
		SLAB, MAT.Slate, { collide = true, shadow = true })
	rock(f, "AncientStoneTop", "angular", Vector3.new(8.5, 7, 11), CFrame.new(sp + Vector3.new(0.6, 21.5, 0.4)) * CFrame.Angles(math.rad(-6), math.rad(20), math.rad(5)),
		SLAB, MAT.Slate, { collide = true, shadow = true })
	for k = 1, 3 do
		local a = k * 2.2
		rock(f, "Rubble", "chunk", Vector3.new(2.6, 1.8, 2.2) * rng:NextNumber(0.8, 1.3), CFrame.new(sp + Vector3.new(math.cos(a) * 6.5, 0.5, math.sin(a) * 7.5)) * CFrame.Angles(0, a, 0.2),
			SLAB, MAT.Slate, { shadow = false })
	end
	for i, yy in ipairs({ 6.5, 9.5, 12.5, 15.5 }) do
		local at, n = surfaceOf(body, sp + Vector3.new(14, yy, (i % 2 == 0) and 1.2 or -1.2), Vector3.new(-14, 0, 0))
		if at then
			for g = -1, 1, 2 do   -- two strokes per glyph, crossed at a slant
				part(f, "Glyph", Vector3.new(0.12, 1.7 - (i % 2) * 0.4, 0.26), CFrame.lookAt(at + n * 0.03, at + n) * CFrame.Angles(0, math.rad(90), math.rad(g * (18 + i * 6))),
					Color3.fromRGB(46, 44, 42), MAT.SmoothPlastic, { shadow = false })
			end
		end
	end
	part(f, "StoneSnow", Vector3.new(6, 0.7, 8), CFrame.new(sp + Vector3.new(0.6, 25.1, 0.4)) * CFrame.Angles(math.rad(-6), math.rad(20), math.rad(5)), C.snow, MAT.Snow, { shadow = false })

	-- scaffolding against the nook's south wall, where the glacier is being cut back
	local sc = Vector3.new(-8398, 0, -7757)
	local g0 = onGround(sc.X, sc.Z, 2022).Y
	for _, dx in ipairs({ -7, 7 }) do
		for _, dz in ipairs({ -2.5, 2.5 }) do
			part(f, "ScaffoldPole", Vector3.new(0.6, 17, 0.6), CFrame.new(sc.X + dx, g0 + 8.5, sc.Z + dz), C.timberDark, MAT.Wood, { collide = true, shadow = false })
		end
	end
	for _, h in ipairs({ 6, 12 }) do
		part(f, "ScaffoldDeck", Vector3.new(15, 0.4, 5.6), CFrame.new(sc.X, g0 + h, sc.Z), C.timber, MAT.WoodPlanks, { collide = true, shadow = true })
	end
	beam(f, "ScaffoldBrace", Vector3.new(sc.X - 7, g0 + 0.5, sc.Z + 2.8), Vector3.new(sc.X + 7, g0 + 11.5, sc.Z + 2.8), 0.35, C.timberDark)
	for r = 1, 5 do   -- a ladder up the west end
		part(f, "LadderRung", Vector3.new(0.25, 0.25, 2.2), CFrame.new(sc.X + 7.8, g0 + r * 2.2, sc.Z), C.timber, MAT.Wood, { shadow = false })
	end
	for _, dz in ipairs({ -1.1, 1.1 }) do
		part(f, "LadderRail", Vector3.new(0.3, 12, 0.3), CFrame.new(sc.X + 7.8, g0 + 6, sc.Z + dz), C.timberDark, MAT.Wood, { shadow = false })
	end

	-- tools and supplies by the hut: crates, a pickaxe against them, a lit post at the porch corner
	crate(f, onGround(-8388, -7722, 2022), 3.6, 14)
	crate(f, onGround(-8384, -7724, 2022), 3, 50, C.timberGrey)
	local pk = onGround(-8386, -7719.5, 2022)
	part(f, "PickHandle", Vector3.new(0.3, 4.4, 0.3), CFrame.new(pk + Vector3.new(0, 2.1, 0)) * CFrame.Angles(math.rad(16), 0, 0), C.timber, MAT.Wood, { shadow = false })
	part(f, "PickHead", Vector3.new(0.3, 0.4, 3.2), CFrame.new(pk + Vector3.new(0, 4.2, -0.6)) * CFrame.Angles(math.rad(16), 0, 0), IRON, MAT.Metal, { shadow = false })
	lanternPost(f, onGround(-8363, -7719, 2022), Vector3.new(0, 0, 1), true)   -- off the drill's camera side
	return "dig: elder's hut, horn, crack, stone, scaffold"
end

-- ============================================================== NICO'S POINT
-- Nico's greybox lodge stays the shell and is dressed like the Warmhouse: log walls, a gable roof
-- over the flat one, a warm window, the door framed and lit, the stove chimney smoking. Around it:
-- his trophy fish, his rods, two drying racks, and the jetty on pilings with a lamp at its end and
-- a punt tied alongside. No new systems: it is the fisherman's place, dressed.
function M.BuildNico()
	local f = freshFolder("NicosPoint")
	local gb = Workspace.GameWorld.FrozenTundra:FindFirstChild("Greybox")
	local shell = gb and gb:FindFirstChild("NicosPoint")
	local lodge = shell and shell:FindFirstChild("NicosLodge")
	if lodge then
		for _, q in ipairs(lodge:GetDescendants()) do
			if q:IsA("BasePart") and q.Name:match("^Wall") then q.Color = LOGWALL end
		end
	end
	local x0, x1, z0, z1, h = -7746, -7716, -7482, -7458, 14
	local top = D + h + 2.5                      -- above the greybox roof slab and its snow
	local zm = (z0 + z1) / 2
	local half = (z1 - z0) / 2 + 1.5              -- eave overhang 1.5
	local rise = 7
	local slope = math.atan2(rise, half)
	local planeLen = math.sqrt(half * half + rise * rise)
	for _, sd in ipairs({ -1, 1 }) do
		local cf = CFrame.new((x0 + x1) / 2, top + rise / 2, zm + sd * half / 2) * CFrame.Angles(sd * slope, 0, 0)
		part(f, "Roof", Vector3.new(x1 - x0 + 3, 0.8, planeLen + 0.4), cf, C.timberDark, MAT.WoodPlanks, { shadow = true })
		part(f, "RoofSnow", Vector3.new(x1 - x0 + 2.6, 0.7, planeLen), cf * CFrame.new(0, 0.72, 0), C.snow, MAT.Snow, { shadow = false })
	end
	part(f, "Ridge", Vector3.new(x1 - x0 + 3.4, 0.9, 0.9), CFrame.new((x0 + x1) / 2, top + rise + 0.2, zm), C.timberDark, MAT.Wood, { shadow = false })
	-- the gable ends fill the triangle under the roof planes over the wall's half-depth; a board
	-- under each closes the strip down to the flat roof's snow
	local gh = rise * (half - 1.5) / half
	for _, gx in ipairs({ x0 - 0.6, x1 + 0.6 }) do
		for _, sd in ipairs({ -1, 1 }) do
			-- a WedgePart rises toward its local +Z: the south half rises north (+Z), the north half south
			part(f, "Gable", Vector3.new(1, gh, half - 1.5), CFrame.new(gx, top + (rise - gh) + gh / 2 - 0.35, zm + sd * (half - 1.5) / 2) * CFrame.Angles(0, (sd < 0) and 0 or math.pi, 0),
				LOGWALL, MAT.WoodPlanks, { class = "WedgePart", shadow = false })
		end
		part(f, "GableBase", Vector3.new(1, 1.0, z1 - z0), CFrame.new(gx, top + 0.3, zm), LOGWALL, MAT.WoodPlanks, { shadow = false })
	end
	for _, cx in ipairs({ x0 - 0.4, x1 + 0.4 }) do
		for _, cz in ipairs({ z0 - 0.4, z1 + 0.4 }) do
			part(f, "CornerPost", Vector3.new(1.6, h, 1.6), CFrame.new(cx, D + h / 2, cz), C.timberDark, MAT.Wood, { collide = true, shadow = false })
		end
	end
	-- the door (east wall, 8 wide, 10 high), framed, a lantern beside it
	for _, dz in ipairs({ -4.6, 4.6 }) do
		part(f, "DoorJamb", Vector3.new(1.4, 10.6, 1.2), CFrame.new(x0 - 0.5, D + 5.3, zm + dz), C.timberDark, MAT.Wood, { collide = true, shadow = false })
	end
	part(f, "DoorLintel", Vector3.new(1.4, 1.2, 10.6), CFrame.new(x0 - 0.5, D + 10.6, zm), C.timberDark, MAT.Wood, { shadow = false })
	wallLantern(f, Vector3.new(x0 - 0.2, D + 8.5, zm + 6.2), Vector3.new(-1, 0, 0))
	-- a warm window on the north wall, facing the clearing
	local wz = z1 + 0.35
	part(f, "WindowPane", Vector3.new(6, 4, 0.3), CFrame.new(-7731, D + 7, wz), PANE, MAT.Neon, { shadow = false })
	for _, e in ipairs({ { 0, 2.4, 7.2, 0.8 }, { 0, -2.4, 7.6, 0.9 } }) do
		part(f, "WindowFrame", Vector3.new(e[3], e[4], 0.9), CFrame.new(-7731 + e[1], D + 7 + e[2], wz + 0.2), C.timberDark, MAT.Wood, { shadow = false })
	end
	for _, dx in ipairs({ -3.3, 3.3 }) do
		part(f, "WindowFrame", Vector3.new(0.8, 4.2, 0.9), CFrame.new(-7731 + dx, D + 7, wz + 0.2), C.timberDark, MAT.Wood, { shadow = false })
	end
	part(f, "WindowMullion", Vector3.new(0.4, 4, 0.6), CFrame.new(-7731, D + 7, wz + 0.2), C.timberDark, MAT.Wood, { shadow = false })
	-- the stove chimney: a cap and smoke where the greybox had a glowing block
	part(f, "ChimneyCap", Vector3.new(7, 0.8, 7), CFrame.new(-7727, D + 24.4, -7463), Color3.fromRGB(88, 84, 80), MAT.Slate, { shadow = false })
	smoke(f, Vector3.new(-7727, D + 25.5, -7463))

	-- trophies on the board by the door, rods in the rack
	for i, fz in ipairs({ -7480.2, -7478, -7475.8 }) do
		fish(f, CFrame.new(-7747.3, D + 7 + (i % 2) * 1.6, fz) * CFrame.Angles(0, math.rad(90), 0), 1.9 + i * 0.25, FISH[i])
	end
	for i, rz in ipairs({ -7461.5, -7460, -7458.6 }) do
		local foot = onGround(-7749, rz)
		beam(f, "FishingRod", foot + Vector3.new(0, 0.2, 0), foot + Vector3.new(-1.2 + i * 0.3, 9.5, 0.4), 0.16, C.timber, MAT.Wood)
		part(f, "Reel", Vector3.new(0.35, 0.7, 0.7), CFrame.new(foot + Vector3.new(-0.2, 2.2, 0.1)) * CFrame.Angles(0, math.rad(90), 0), IRON, MAT.Metal,
			{ shape = Enum.PartType.Cylinder, shadow = false })
	end

	-- two drying racks on the clearing's north side, fish hanging from the bars
	for _, rk in ipairs({ { -7741, -7447, 8 }, { -7724, -7444.5, -6 } }) do
		local c = onGround(rk[1], rk[2])
		local cf = CFrame.new(c) * CFrame.Angles(0, math.rad(rk[3]), 0)
		for _, sx in ipairs({ -3.4, 3.4 }) do
			beam(f, "RackLeg", (cf * CFrame.new(sx, 0, -1.3)).Position, (cf * CFrame.new(sx, 6.4, 0)).Position, 0.4, C.timberDark)
			beam(f, "RackLeg", (cf * CFrame.new(sx, 0, 1.3)).Position, (cf * CFrame.new(sx, 6.4, 0)).Position, 0.4, C.timberDark)
		end
		part(f, "RackBar", Vector3.new(8, 0.35, 0.35), cf * CFrame.new(0, 6.3, 0), C.timber, MAT.Wood, { shadow = false })
		for k = 1, 4 do
			local fx = -2.6 + (k - 1) * 1.75
			part(f, "FishCord", Vector3.new(0.06, 0.7, 0.06), cf * CFrame.new(fx, 5.85, 0), C.rope, MAT.Fabric, { shadow = false })
			fish(f, cf * CFrame.new(fx, 4.6, 0) * CFrame.Angles(0, 0, math.rad(90)), 1.6 + (k % 2) * 0.3, FISH[(k % 3) + 1])
		end
	end

	-- the jetty: pilings under both edges, a lamp at the end, a punt tied alongside
	for _, px in ipairs({ -7756, -7772, -7788, -7804, -7810.5 }) do
		for _, pz in ipairs({ -7474.7, -7465.3 }) do
			part(f, "Piling", Vector3.new(0.9, 8.6, 0.9), CFrame.new(px, D - 3.9, pz), C.timberDark, MAT.Wood, { shadow = false })
		end
	end
	lanternPost(f, Vector3.new(-7808.5, D + 0.4, -7466.2), Vector3.new(0, 0, -1), true)
	-- the jetty ends at the shore (the water starts at x -7812, where the lake barrier stands), so
	-- the punt floats just past its end, tied to the last piling
	local punt = CFrame.new(-7824, 2000.35, -7478.5) * CFrame.Angles(0, math.rad(12), 0)
	part(f, "PuntBottom", Vector3.new(8, 0.35, 2.8), punt, C.timberGrey, MAT.WoodPlanks, { shadow = false })
	for _, sz in ipairs({ -1.45, 1.45 }) do
		part(f, "PuntSide", Vector3.new(8, 1.1, 0.3), punt * CFrame.new(0, 0.6, sz) * CFrame.Angles(math.rad(sz > 0 and -14 or 14), 0, 0), C.timberGrey, MAT.WoodPlanks, { shadow = false })
	end
	for _, sx in ipairs({ -4.05, 4.05 }) do
		part(f, "PuntEnd", Vector3.new(0.3, 1.0, 3.2), punt * CFrame.new(sx, 0.55, 0), C.timberGrey, MAT.WoodPlanks, { shadow = false })
	end
	part(f, "PuntSeat", Vector3.new(1.2, 0.25, 2.8), punt * CFrame.new(0.6, 0.85, 0), C.timber, MAT.Wood, { shadow = false })
	part(f, "Oar", Vector3.new(6.5, 0.18, 0.18), punt * CFrame.new(0.2, 1.05, 0.6) * CFrame.Angles(0, math.rad(12), 0), C.timber, MAT.Wood, { shadow = false })
	beam(f, "MooringLine", (punt * CFrame.new(3.9, 1, -1.2)).Position, Vector3.new(-7810.5, D + 0.6, -7474.9), 0.12, C.rope, MAT.Fabric)
	part(f, "RopeCoil", Vector3.new(0.5, 1.8, 1.8), CFrame.new(-7770, D + 0.65, -7468.2) * CFrame.Angles(0, 0, math.rad(90)), C.rope, MAT.Fabric, { shape = Enum.PartType.Cylinder, shadow = false })
	part(f, "Bucket", Vector3.new(1.3, 1.4, 1.4), CFrame.new(-7761, D + 1.1, -7472.8) * CFrame.Angles(0, 0, math.rad(90)), IRON, MAT.Metal, { shape = Enum.PartType.Cylinder, shadow = false })
	return "nico's point dressed"
end

-- ============================================================== THE SQUEEZE
-- Nico's canyon is a slot 12 studs wide under walls 200 high: without light it is black at eye
-- level. Six lanterns down its length, on alternating sides, arms over the path; a sign at the mouth.
function M.BuildSqueeze()
	local f = freshFolder("TheSqueeze")
	local pts = blockout().SQUEEZE
	local sd = 1
	for i = 1, #pts - 1 do
		local a, b = Vector3.new(pts[i][1], pts[i][3], pts[i][2]), Vector3.new(pts[i + 1][1], pts[i + 1][3], pts[i + 1][2])
		local dir = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Unit
		local perp = Vector3.new(-dir.Z, 0, dir.X)
		local mid = a:Lerp(b, 0.5)
		local at = mid + perp * sd * 4.2
		local lamp = lanternPost(f, onGround(at.X, at.Z, mid.Y), -perp * sd, true)
		-- down here the lamp itself is the waymark: a deep amber Neon (dim enough to stay under
		-- Bloom's threshold) and a stronger light than the street lamps
		lamp.Material = MAT.Neon
		lamp.Color = Color3.fromRGB(176, 112, 54)
		local pl = lamp:FindFirstChildOfClass("PointLight")
		if pl then pl.Range = 26; pl.Brightness = 1.4 end
		sd = -sd
	end
	signpost(f, onGround(-7704.5, -7476), { { "BLUE HOLLOW", Vector3.new(-7650, 0, -7452), 6.4 } }, 9)   -- beside the path from Nico's
	return "squeeze: 6 lanterns, sign"
end

-- ============================================================== THE BLUE HOLLOW
-- Ice crystals in clusters round the cavern (two carry a cold light), and the Warm Eye made to read
-- as warm: steam off the open water, a low amber glow in it, broken ice round its rim.
function M.BuildHollow()
	local f = freshFolder("BlueHollow")
	local rng = Random.new(1982)
	local clusters = { { -7600, -7120, true }, { -7470, -7130 }, { -7460, -7240, true }, { -7605, -7250 }, { -7490, -7108 }, { -7545, -7098 }, { -7612, -7186 } }
	for _, cl in ipairs(clusters) do
		local base = onGround(cl[1], cl[2], 1982)
		local n = rng:NextInteger(4, 6)
		local biggest
		for k = 1, n do
			local a = rng:NextNumber(0, math.pi * 2)
			local r = (k == 1) and 0 or rng:NextNumber(1.8, 5)
			local hgt = ((k == 1) and rng:NextNumber(12, 17) or rng:NextNumber(4, 11)) * 1.5
			local w = hgt * rng:NextNumber(0.2, 0.3)
			local lean = (k == 1) and rng:NextNumber(-6, 6) or rng:NextNumber(10, 28)
			local at = base + Vector3.new(math.cos(a) * r, hgt * 0.42, math.sin(a) * r)
			local cf = CFrame.new(at) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, math.rad(-lean)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
			local c = rock(f, "Crystal", "crystal", Vector3.new(w, hgt, w * 0.9), cf,
				Color3.fromRGB(rng:NextInteger(130, 170), rng:NextInteger(196, 226), rng:NextInteger(236, 252)), MAT.Ice, { shadow = false })
			if k == 1 then biggest = c end
		end
		-- (no crystal lights: the cavern is lit blue by its own ice; two tried, not worth a light each)
	end
	-- the Warm Eye
	local eye = Vector3.new(-7525, 1983.5, -7165)
	local anchor = part(f, "WarmEyeGlow", Vector3.new(1, 1, 1), CFrame.new(eye - Vector3.new(0, 0.8, 0)), C.warm, MAT.SmoothPlastic, { transparency = 1, shadow = false })
	light(anchor, Color3.fromRGB(255, 176, 110), 16, 0.7)
	local steam = Instance.new("ParticleEmitter")
	steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
	steam.Rate = 5
	steam.Lifetime = NumberRange.new(3, 5)
	steam.Speed = NumberRange.new(1.5, 3)
	steam.SpreadAngle = Vector2.new(25, 25)
	steam.Acceleration = Vector3.new(0, 0.6, 0)
	steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 9) })
	steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.3, 0.45), NumberSequenceKeypoint.new(1, 1) })
	steam.Color = ColorSequence.new(Color3.fromRGB(236, 240, 246))
	steam.Rotation = NumberRange.new(0, 360)
	steam.RotSpeed = NumberRange.new(-20, 20)
	steam.LightInfluence = 0.6
	steam.Parent = anchor
	for k = 0, 6 do
		local a = k / 7 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local r = rng:NextNumber(6.2, 7.6)
		local g = onGround(eye.X + math.cos(a) * r, eye.Z + math.sin(a) * r, 1983)
		rock(f, "RimIce", "flat", Vector3.new(rng:NextNumber(2.6, 4.2), 0.5, rng:NextNumber(1.8, 3)),
			CFrame.new(g + Vector3.new(0, 0.15, 0)) * CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), -a, math.rad(rng:NextNumber(-10, 10))),
			Color3.fromRGB(196, 228, 246), MAT.Ice, { shadow = false })
	end
	-- Nico's shanty: a lamp at its door
	wallLantern(f, Vector3.new(-7596.2, 1982 + 6.5, -7222), Vector3.new(-1, 0, 0))
	return "hollow: crystals, warm eye"
end

-- ============================================================== EAGLE'S CRAG
-- the rope bridge gets its four posts (the greybox planks and hand ropes stay)
function M.BuildCrag()
	local f = freshFolder("EaglesCrag")
	for _, z in ipairs({ -8062.6, -8047.4 }) do
		for _, x in ipairs({ -7690, -7680 }) do
			local g = onGround(x, z, 2047, 4)
			part(f, "BridgePost", Vector3.new(0.7, 2049.9 - g.Y + 0.6, 0.7), CFrame.new(x, (g.Y + 2049.9) / 2 - 0.3, z), C.timberDark, MAT.Wood, { collide = true, shadow = false })
			part(f, "PostCap", Vector3.new(0.95, 0.25, 0.95), CFrame.new(x, 2050.05, z), C.snow, MAT.Snow, { shadow = false })
		end
	end
	return "crag: bridge posts"
end

-- ============================================================== PERFORMANCE (mobile)
-- The relocated ruins (the wrecked galleon, the broken watchtower) came over with every part
-- touchable, queryable and shadow-casting. Nothing scripts against them (checked 2026-09-21), so:
-- no touch on any of them, no shadow from anything smaller than 4 studs, no query where there
-- is no collision. Collision itself is left as it was: players walk the tower's ramp and deck.
function M.TuneRuins()
	local ruins = Workspace.GameWorld.FrozenTundra:FindFirstChild("Ruins")
	if not ruins then return "ruins: none" end
	local n = { touch = 0, shadow = 0, query = 0 }
	for _, d in ipairs(ruins:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.CanTouch then d.CanTouch = false; n.touch += 1 end
			if d.CastShadow and math.max(d.Size.X, d.Size.Y, d.Size.Z) < 4 then d.CastShadow = false; n.shadow += 1 end
			if d.CanQuery and not d.CanCollide then d.CanQuery = false; n.query += 1 end
		end
	end
	return ("ruins: touch off %d, small shadows off %d, query off %d"):format(n.touch, n.shadow, n.query)
end

-- Greybox pieces the art pass has replaced. Run after the Build* steps; the generator's
-- BuildParts brings every one of them back if the art is ever taken off again.
M.RETIRED = {
	"Frostwatch",              -- the path strips, the Circle disc, bonfire, signpost, lanterns
	"EaglesCrag/CragTrail",
	"CellarPass/RailN",        -- the Frostgate's flat rails (BuildFrostgate's fence)
	"CellarPass/RailW",
	"Warmhouse/Hearth",        -- the flat glowing hearth box (BuildWarmhouseInterior's hearth)
	"Warmhouse/Lamp",          -- the eight lamp boxes (its hanging lanterns)
	"EldersDig/EldersStation", -- the station box: Elder Tung's own hut stands there now
	"EldersDig/Chimney",
	"EldersDig/ListeningHorn",
	"EldersDig/TheCrack",
	"EldersDig/AncientStone",
	"NicosPoint/StoveGlow",    -- the glowing block on Nico's chimney (a cap and smoke now)
	"TheSqueeze",              -- Nico's three placeholder lanterns (six lit ones now)
	"BlueHollow/Crystal",      -- the five glacier sticks (crystal clusters now)
}
function M.RetireGreybox()
	local gb = Workspace.GameWorld.FrozenTundra:FindFirstChild("Greybox")
	if not gb then return "greybox: none" end
	local n = 0
	for _, path in ipairs(M.RETIRED) do
		local top, child = path:match("^([^/]+)/?(.*)$")
		local node = gb:FindFirstChild(top)
		if node then
			if child == "" then
				n += #node:GetChildren()
				node:Destroy()
			else
				for _, c in ipairs(node:GetChildren()) do
					if c.Name == child then n += 1; c:Destroy() end
				end
			end
		end
	end
	for _, d in ipairs(gb:GetDescendants()) do
		if d.Parent and d:GetAttribute("GreyboxLabel") then n += 1; d:Destroy() end
	end
	return ("greybox: %d replaced pieces and labels removed"):format(n)
end

-- Terrain from scratch: the blockout's greybox terrain (lake-safe, fingerprint-checked in
-- 2026-09-19), then every art terrain step in order. Walls are additive, so iterating on them
-- means rebuilding under them; this is how.
function M.RebuildTerrain()
	local B = blockout()
	B.ClearAll(); B.Floor(); B.Massifs(); B.Features(); B.Carves(); B.HollowAndFalls(); B.Ramps(); B.Outside()
	local out = { "greybox terrain rebuilt" }
	table.insert(out, M.ClearTerrainPeak())
	table.insert(out, M.ReskinWalls())
	table.insert(out, M.BuildWalls())
	table.insert(out, M.BuildLakeWalls())
	table.insert(out, M.ClearWarmhouseInterior())
	table.insert(out, M.BuildTerrainPaths())
	table.insert(out, M.BuildTownTerrain())
	table.insert(out, M.BuildSiteTerrain())
	return table.concat(out, "; ")
end

-- ============================================================== THE SKYLINE
-- BuildWalls dresses the FACES, and it works: probe raycasts find relief on 49 of 74
-- sample columns east and 109 of 154 west. What it never reaches is the massif TOP behind
-- the lip, and that top is a dead plane -- 74 of 74 samples at exactly y2110 across 440
-- studs. At any distance the face relief washes out and the only thing still reading is
-- that ruler-straight line, which is the "extruded box" tell. This pass breaks the top
-- itself: a wandering height line, notches taken clean through the lip, and a few crags
-- standing above the rim. Terrain only, so it costs no parts.
--
-- Cuts reach ~34 studs BACK from the face line on purpose. Shaving only the front edge
-- leaves the plateau behind it intact, and the silhouette is the plateau, not the edge.
M.SKY_FACES = { SouthEast = true, SouthWest = true, OverWarm = true, EastGlacier = true, WestGlacier = true }

function M.BuildSkyline()
	stats.written, stats.skipped = 0, 0
	local rng = Random.new(20260923)
	local steps, notches, crags = 0, 0, 0

	for _, f in ipairs(M.FACES) do
		local o = f[7] or {}
		if M.SKY_FACES[f[1]] and not o.carve then
			local A = Vector3.new(f[2][1], 0, f[2][2])
			local B = Vector3.new(f[3][1], 0, f[3][2])
			local nrm = Vector3.new(f[4][1], 0, f[4][2]).Unit
			local along = (B - A).Unit
			local run = (B - A).Magnitude
			local floorY, topY = f[5], f[6]
			-- never take more than a third of a wall's height: it has to stay a wall
			local maxDrop = math.min(25, (topY - floorY) * 0.33)
			local minDrop = math.min(10, maxDrop * 0.5)

			local function blocked(t)
				for _, s in ipairs(o.skip or {}) do
					if t >= s[1] - 0.03 and t <= s[2] + 0.03 then return true end
				end
				return false
			end
			-- an air box whose BOTTOM sits at bottomY, reaching 4 studs proud of the face
			-- and the rest of its depth back into the massif
			local function cutAt(centre, width, bottomY, depth)
				local c = centre - nrm * (depth / 2 - 4) + Vector3.new(0, bottomY + 60, 0)
				return tFill(CFrame.lookAt(c, c + nrm), Vector3.new(width, 120, depth), MAT.Air)
			end

			-- 1. THE WANDERING TOP. Irregular segments, each dropped its own amount, so the
			-- ridge never repeats at a spacing the eye can lock onto.
			local d = rng:NextNumber(0, 40)
			while d < run - 30 do
				local seg = rng:NextNumber(40, 120)
				local t = (d + seg * 0.5) / run
				if not blocked(t) then
					if cutAt(A + along * (d + seg * 0.5), seg, topY - rng:NextNumber(minDrop, maxDrop), 38) then
						steps += 1
					end
				end
				d += seg
			end

			-- 2. NOTCHES. Narrower and deeper, and taken right through the lip, so the gap
			-- shows sky instead of reading as a dip in one continuous ridge.
			local want = (run > 300) and 5 or 3
			for i = 1, want do
				local t = (i - 0.5) / want + rng:NextNumber(-0.06, 0.06)
				if t > 0.04 and t < 0.96 and not blocked(t) then
					local deep = math.min(rng:NextNumber(26, 44), maxDrop * 1.8)
					if cutAt(A + along * (t * run), rng:NextNumber(15, 30), topY - deep, 46) then
						notches += 1
					end
				end
			end

			-- 3. CRAGS above the rim, set well back from the lip so no path below narrows.
			local wantCrags = (run > 300) and 3 or 2
			for i = 1, wantCrags do
				local t = rng:NextNumber(0.08, 0.92)
				if not blocked(t) then
					local base = A + along * (t * run) - nrm * rng:NextNumber(10, 25)
					local h = rng:NextNumber(20, 45)
					local w = rng:NextNumber(10, 22)
					local c = base + Vector3.new(0, topY - 6 + h / 2, 0)
					local cf = CFrame.lookAt(c, c + nrm)
						* CFrame.Angles(math.rad(rng:NextNumber(-7, 7)), 0, math.rad(rng:NextNumber(-9, 9)))
					local mat = (rng:NextNumber() < 0.65) and MAT.Slate or MAT.Rock
					if tFill(cf, Vector3.new(w, h, w * rng:NextNumber(0.7, 1.1)), mat) then
						crags += 1
						tBall(c + Vector3.new(0, h * 0.45, 0), w * rng:NextNumber(0.3, 0.45), mat)
						tBall(c + Vector3.new(0, h * 0.55, 0), w * rng:NextNumber(0.22, 0.32), MAT.Snow)
					end
				end
			end
		end
	end
	return ("skyline: %d top steps, %d notches, %d crags (%d writes, %d skipped at the lake)")
		:format(steps, notches, crags, stats.written, stats.skipped)
end

-- ============================================================== WARMHOUSE AS THE HERO
-- The Warmhouse is already the biggest thing in the hub -- a 226x137 roof on 36-stud walls --
-- and it still vanishes, because RoofSnow is a near-white Snow slab lying on near-white ground
-- under a white sky. Size was never the problem, VALUE is. This pass gives the building a dark
-- outline, one tall smoking vertical, and warm light spilled where players are meant to walk.
--
-- It also dresses the EAST wall. The portal arrival sits at (-8243, 2036, -8283), which is east
-- of the building, so the face a player actually meets first is WallE -- and WallE had no door,
-- no window and nothing lit on it at all.
local WH_DOOR_X, WH_NORTH_Z = -8000, -8251
local WH_EAST_X = -8111

function M.BuildWarmhouseHero()
	local f = freshFolder("WarmhouseHero")
	local gb = Workspace.GameWorld.FrozenTundra:FindFirstChild("Greybox")
	local wh = gb and gb:FindFirstChild("Warmhouse")
	if not wh then return "Warmhouse greybox not found -- nothing done" end

	local changed = {}
	-- 1. VALUE. Darken the timber under the snow and pull the snow cap in, so a dark band of
	-- roof edge shows all the way round instead of white meeting white.
	local roof = wh:FindFirstChild("Roof")
	if roof then
		roof.Color = Color3.fromRGB(64, 45, 32)
		roof.Material = MAT.WoodPlanks
		changed[#changed + 1] = "roof darkened"
	end
	local snow = wh:FindFirstChild("RoofSnow")
	if snow then
		snow.Size = Vector3.new(snow.Size.X - 10, snow.Size.Y, snow.Size.Z - 10)
		changed[#changed + 1] = "roof snow inset 5 studs"
	end

	-- 2. OUTLINE. Fascia boards round all four eaves and a spine along the ridge. This is what
	-- actually separates the building from the snow at distance.
	local ex, ez = 113, 68.5      -- roof half-extents
	local cx, cz = -8000, -8317.5
	local fy = 2038.2
	local fascia = {
		{ "FasciaN", Vector3.new(ex * 2 + 4, 3.0, 2.2), Vector3.new(cx, fy, cz + ez) },
		{ "FasciaS", Vector3.new(ex * 2 + 4, 3.0, 2.2), Vector3.new(cx, fy, cz - ez) },
		{ "FasciaE", Vector3.new(2.2, 3.0, ez * 2 + 4), Vector3.new(cx - ex, fy, cz) },
		{ "FasciaW", Vector3.new(2.2, 3.0, ez * 2 + 4), Vector3.new(cx + ex, fy, cz) },
	}
	for _, b in ipairs(fascia) do
		part(f, b[1], b[2], CFrame.new(b[3]), C.timberDark, MAT.WoodPlanks, { shadow = false })
	end
	-- (the RidgeBeam that stood here was swallowed by the lean-to's snow wedge; BuildWarmhouseFront
	-- puts a visible crest on the roof's real top edge instead)

	-- 3. THE VERTICAL. The chimneys were 14 studs of pale slate, shorter than the wall they sit
	-- on. Raised and darkened, one of them smoking, they become the thing you pick out first.
	local smoked = false
	for _, n in ipairs({ "ChimneyW", "ChimneyE" }) do
		local ch = wh:FindFirstChild(n)
		if ch then
			ch.Size = Vector3.new(13, 30, 13)
			ch.Position = Vector3.new(ch.Position.X, 2054, ch.Position.Z)
			ch.Color = Color3.fromRGB(74, 78, 86)
			ch.Material = MAT.Slate
			part(f, n .. "Cap", Vector3.new(15.5, 1.8, 15.5),
				CFrame.new(ch.Position + Vector3.new(0, 15.4, 0)), C.timberDark, MAT.Slate, { shadow = false })
			if not smoked then
				smoked = true
				local a = Instance.new("Attachment")
				a.Position = Vector3.new(0, 15.5, 0)
				a.Parent = ch
				local e = Instance.new("ParticleEmitter")
				e.Name = "Smoke"
				e.Texture = "rbxasset://textures/particles/smoke_main.dds"
				e.Rate = 5
				e.Lifetime = NumberRange.new(5, 8)
				e.Speed = NumberRange.new(5, 8)
				e.SpreadAngle = Vector2.new(9, 9)
				e.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.25, 0.72),
					NumberSequenceKeypoint.new(1, 1),
				})
				e.Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 5),
					NumberSequenceKeypoint.new(1, 24),
				})
				e.Color = ColorSequence.new(Color3.fromRGB(226, 232, 240))
				e.LightEmission = 0.15
				e.Parent = a
			end
			changed[#changed + 1] = n .. " raised to 30"
		end
	end

	-- 4. WARM LIGHT WHERE THE PLAYER WALKS. Lanterns are the only warm thing in a blue-white
	-- plaza, so they read as "go here" from a long way off. Lights are not parts.
	local function lantern(name, pos, range)
		part(f, name .. "Post", Vector3.new(1.3, 8, 1.3), CFrame.new(pos - Vector3.new(0, 4.6, 0)),
			C.timberDark, MAT.WoodPlanks, { shadow = false })
		local lamp = part(f, name, Vector3.new(2.6, 3.0, 2.6), CFrame.new(pos),
			C.lamp, MAT.Neon, { shadow = false })
		local l = Instance.new("PointLight")
		l.Color = C.warm
		l.Brightness = 1.5
		l.Range = range or 34
		l.Shadows = false
		l.Parent = lamp
		return lamp
	end

	-- the door on the north wall, one either side of the 28-stud opening
	lantern("DoorLampE", Vector3.new(WH_DOOR_X - 17, 2012, WH_NORTH_Z + 2.4), 40)
	lantern("DoorLampW", Vector3.new(WH_DOOR_X + 17, 2012, WH_NORTH_Z + 2.4), 40)

	-- the EAST wall, the face the arrival looks at: two lanterns and a lit sign board, so the
	-- first thing framed by the tunnel mouth has somewhere warm to aim at
	lantern("ArrivalLampN", Vector3.new(WH_EAST_X - 2.6, 2012, -8285), 42)
	lantern("ArrivalLampS", Vector3.new(WH_EAST_X - 2.6, 2012, -8350), 42)
	part(f, "EastSignBoard", Vector3.new(1.0, 9, 26),
		CFrame.new(WH_EAST_X - 1.6, 2021, -8317.5), C.timberDark, MAT.WoodPlanks, { shadow = false })
	local glow = part(f, "EastSignGlow", Vector3.new(0.6, 6.5, 22),
		CFrame.new(WH_EAST_X - 2.3, 2021, -8317.5), C.warm, MAT.Neon, { shadow = false })
	local sl = Instance.new("PointLight")
	sl.Color = C.warm
	sl.Brightness = 1.2
	sl.Range = 46
	sl.Shadows = false
	sl.Parent = glow

	local n = 0
	for _, d in ipairs(f:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
	return ("warmhouse hero: %d parts added (%s)"):format(n, table.concat(changed, ", "))
end

-- ============================================================== THE ARRIVAL APPROACH
-- Everything a player meets in the first ten seconds of World 2, and it was the weakest
-- stretch in the world. Measured along the portal's own look direction
-- (TUNDRA_LOOK = 0.386, 0, 0.922) from TUNDRA_POS:
--
--   d 0..25   inside CellarPass, floor 2030, ceiling ~2044
--   d 25..76  OPEN SHELF, floor exactly 2030 the whole way -- 50 studs of blank
--   d 76..80  the drop, 2028 -> 2002
--   d 80+     the town flat at 2002
--
-- Two separate problems. First, all three existing RibLanterns sit at z -8334, -8313 and
-- -8291, which is BEHIND the arrival at z -8283: the tunnel a player actually walks
-- (z -8283 -> -8266) had no light in it at all, and the lanterns that exist are
-- SmoothPlastic at brightness 0.6 / range 14, so they neither glow nor carry. Second, the
-- shelf past the mouth is a flat plane with nothing on it, so there is no read on where to
-- go -- which is what MASTER saw as "a blank slope".
local AP_LOOK = Vector3.new(0.386, 0, 0.922).Unit
local AP_FROM = Vector3.new(-8243, 2034, -8283)
-- Lantern values are deliberately modest. The first pass ran 1.7-1.9 brightness at range
-- 32-36 and the tunnel walls washed out to a bright mint green, so the WALL read as the
-- light source instead of the lanterns. Warm pools on a cool wall, and the daylight at the
-- mouth stays the brightest thing in frame, which is what should pull the player out.
local AP_LAMP = Color3.fromRGB(255, 190, 120)
local AP_BRIGHT, AP_RANGE = 1.0, 20
-- Inside the bore the pools have to stay small, or the warm light floods the whole Slate wall
-- and it reads as a sand cave (ITEM 8 checkpoint): tighter and dimmer in the tunnel only.
local AP_TUNNEL_BRIGHT, AP_TUNNEL_RANGE = 0.85, 14
-- ITEM 9: those warm 255,190,120 pools turned the blue-grey Slate (110,122,128) tan -- "brown
-- dirt" at eye level. Inside the bore the lamps are a cool white so the rock reads as rock; the
-- warm AP_LAMP stays on the shelf posts outside, where it is the cue to walk out.
local AP_TUNNEL_LAMP = Color3.fromRGB(206, 212, 222)
local AP_TUNNEL_CORE = Color3.fromRGB(150, 162, 180)   -- a dim core: a bright cool Neon blew out white
-- and the far half of the bore went black between pools: each wall crystal carries a dim cold
-- fill (a light inside an existing mesh -- no new part, no new Neon head)
local AP_FILL, AP_FILL_BRIGHT, AP_FILL_RANGE = Color3.fromRGB(180, 196, 218), 0.3, 14
-- The shelf past the mouth is measured dead flat at y2030 (d 25..72). Everything on it is set
-- from that constant, NOT from a raycast: a raycast finds the rock the previous run left, so a
-- rebuild stacked a new lump on the old one every time (ITEM 8: lumps reached y2052 and the
-- lit posts floated 15 studs up). A fixed floor makes the step safe to re-run.
local AP_SHELF_Y = 2030

function M.BuildArrivalApproach()
	local f = freshFolder("ArrivalApproach")
	local side = Vector3.new(AP_LOOK.Z, 0, -AP_LOOK.X)   -- perpendicular, in the ground plane
	local function at(d, off)
		return AP_FROM + AP_LOOK * d + side * (off or 0)
	end
	-- A lantern is a Glass body with a small Neon core, never an all-Neon block: an all-Neon
	-- head blows out to a flat white square under the tundra grade (ITEM 7 audit, shot 1).
	local function lamp(name, pos, bright, range, col, coreCol)
		col = col or AP_LAMP
		local head = part(f, name, Vector3.new(1.7, 2.0, 1.7), CFrame.new(pos),
			col, MAT.Glass, { shadow = false, transparency = 0.35 })
		part(f, name .. "Core", Vector3.new(0.55, 0.75, 0.55), CFrame.new(pos),
			coreCol or col, MAT.Neon, { shadow = false })
		local l = Instance.new("PointLight")
		l.Color = col
		l.Brightness = bright or AP_BRIGHT
		l.Range = range or AP_RANGE
		l.Shadows = false
		l.Parent = head
		return head
	end

	-- 0. THE BORE. The CellarPass walls are Glacier, and Glacier's GLOBAL terrain colour reads
	-- as bright mint green under the tundra grade -- the tunnel looked like a moss tube (ITEM 7,
	-- shot 1). Material colours are shared with World 1 and the Gardens, so the colour is NOT
	-- changed; the bore's own voxels are switched to Slate instead, region-limited to the tunnel.
	Workspace.Terrain:ReplaceMaterial(
		Region3.new(Vector3.new(-8284, 2022, -8350), Vector3.new(-8218, 2054, -8252)):ExpandToGrid(4),
		4, MAT.Glacier, MAT.Slate)

	-- 1. LIGHT THE STRETCH THEY WALK. Three new lanterns hung off the tunnel ribs on the
	-- leg from the arrival out to the gate, plus a lift on the three that already exist.
	local relit = 0
	local cp = Workspace.GameWorld.FrozenTundra:FindFirstChild("CellarPass", true)
	if cp then
		for _, d in ipairs(cp:GetDescendants()) do
			if d.Name == "RibLantern" then
				d.Material = MAT.Glass
				d.Transparency = 0.35
				d.Color = AP_TUNNEL_LAMP
				part(f, "RibLanternCore", Vector3.new(0.45, 0.6, 0.45), CFrame.new(d.Position),
					AP_TUNNEL_CORE, MAT.Neon, { shadow = false })
				local l = d:FindFirstChildWhichIsA("Light", true)
				if l then
					l.Color = AP_TUNNEL_LAMP
					l.Brightness = AP_TUNNEL_BRIGHT
					l.Range = AP_TUNNEL_RANGE
					relit = relit + 1
				end
			end
		end
	end
	for i, d in ipairs({ 7, 15, 23 }) do
		local p = at(d, (i % 2 == 0) and 5.5 or -5.5)
		lamp("TunnelLamp" .. i, Vector3.new(p.X, 2040.6, p.Z), AP_TUNNEL_BRIGHT, AP_TUNNEL_RANGE,
			AP_TUNNEL_LAMP, AP_TUNNEL_CORE)
	end

	-- ICE IN THE BORE. The Slate reskin fixed the mint green but left no ice at all, and the brief
	-- is "Slate and ice blue". Terrain colours are global, so the ice comes from a few faceted
	-- crystal meshes growing out of the foot of the walls, catching the lamp pools.
	local wallRp = RaycastParams.new()
	wallRp.FilterType = Enum.RaycastFilterType.Exclude
	wallRp.FilterDescendantsInstances = { f }
	for i, spec in ipairs({ { 4, 1 }, { 9, -1 }, { 14, 1 }, { 18, -1 }, { 22, 1 }, { 26, -1 } }) do
		local c = at(spec[1], 0)
		local hit = Workspace:Raycast(Vector3.new(c.X, 2031.5, c.Z), side * spec[2] * 14, wallRp)
		if hit then
			local base = hit.Position - side * spec[2] * 0.9
			local h = 2.6 + (i % 3) * 1.1
			local cr = rock(f, "IceCrystal", "crystal", Vector3.new(h * 0.42, h, h * 0.42),
				CFrame.new(base.X, 2030 + h * 0.42, base.Z)
					* CFrame.Angles(0, math.rad(i * 47), math.rad(-spec[2] * 14)),
				(i % 2 == 0) and C.ice or C.iceDeep, MAT.Glass)
			cr.Transparency = 0.12
			local fill = Instance.new("PointLight")
			fill.Name = "CrystalFill"
			fill.Color = AP_FILL
			fill.Brightness = AP_FILL_BRIGHT
			fill.Range = AP_FILL_RANGE
			fill.Shadows = false
			fill.Parent = cr
		end
	end

	-- 2. THE SHELF. Rock set in two loose lines that CONVERGE on the descent, so the shelf
	-- reads as a way through rather than an open plain. Nothing sits on the walking line.
	--
	-- These are TERRAIN lumps, not Parts (MASTER, chunk C review). A Part boulder always
	-- shows flat faces and square corners however hard it is turned, which is the same tell
	-- as the old slab cliffs; overlapping FillBalls read as rock, cost nothing against the
	-- part budget, and use the same Slate the cliff faces already use.
	local rng = Random.new(90232)
	local boulders = 0
	for _, spec in ipairs({
		{ 34, -13 }, { 40, 12 }, { 47, -11.5 }, { 54, 10.5 },
		{ 60, -9.5 }, { 66, 9 }, { 71, -8.5 },
	}) do
		local p = at(spec[1], spec[2])
		local g = AP_SHELF_Y
		if g then
			local r = rng:NextNumber(4.0, 6.5)
			local c = Vector3.new(p.X, g + r * 0.10, p.Z)
			local mat = (rng:NextNumber() < 0.6) and MAT.Slate or MAT.Rock
			tBall(c, r, mat)
			-- two or three smaller lobes off the main mass, so no lump is a clean sphere
			for _ = 1, rng:NextInteger(2, 3) do
				tBall(c + Vector3.new(rng:NextNumber(-r, r) * 0.75,
					rng:NextNumber(-0.3, 0.5) * r, rng:NextNumber(-r, r) * 0.75),
					r * rng:NextNumber(0.45, 0.8), mat)
			end
			-- snow caught on the crown
			tBall(c + Vector3.new(0, r * 0.55, 0), r * rng:NextNumber(0.5, 0.75), MAT.Snow)
			boulders = boulders + 1
		end
	end

	-- 3. TWO LEANING MARKER POSTS, lit, one either side, at the point where the shelf
	-- gives way to the drop. These are the actual signpost: from the tunnel mouth they
	-- read as a gate you walk between.
	for i, off in ipairs({ -10, 10 }) do
		local p = at(69, off)
		local g = AP_SHELF_Y
		if g then
			local lean = (off < 0) and 7 or -7
			local base = Vector3.new(p.X, g, p.Z)
			part(f, "MarkerPost" .. i, Vector3.new(1.1, 11, 1.1),
				CFrame.new(base + Vector3.new(0, 5.2, 0)) * CFrame.Angles(0, 0, math.rad(lean)),
				C.timberDark, MAT.WoodPlanks, { shadow = false })
			lamp("MarkerLamp" .. i, base + Vector3.new(math.sin(math.rad(lean)) * -10, 10.6, 0))
		end
	end

	-- 4. DRIFTS. Two wedges of snow banked against the rock lines, so the shelf floor stops
	-- being one flat plane at exactly 2030.
	for _, spec in ipairs({ { 44, -15, 26 }, { 58, 14, 22 } }) do
		local p = at(spec[1], spec[2])
		local g = AP_SHELF_Y
		if g then
			local w, h = spec[3], rng:NextNumber(2.4, 3.6)
			local c = Vector3.new(p.X, g + h / 2 - 0.4, p.Z)
			tWedge(CFrame.lookAt(c, c + (spec[2] < 0 and side or -side)),
				Vector3.new(w, h, h * 2.6), MAT.Snow)
		end
	end

	local n = 0
	for _, d in ipairs(f:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
	return ("arrival approach: %d parts, %d terrain rock lumps, %d existing lanterns relit"):format(n, boulders, relit)
end

-- ============================================================== THE LAKE SHORE
-- Measured before touching it: on the x=-8000 line the land sits at 2002.4 right up to
-- z -7792, and the very next sample is 1978.5. That is a 24-stud vertical cliff hidden
-- under a water surface at y2000 -- there is no shore at all, and the dock simply bridges
-- the drop.
--
-- APPROACH, and it differs from the one in the plan on purpose. Cutting a shelf INTO the
-- bank would extend shallow water inland and move the waterline, which is exactly the
-- lake outline MASTER asked to keep fixed. Raising the BED instead leaves the outline and
-- the water surface untouched and still gives shallows you can read: the near-shore bed
-- comes up from 1978 to about 1996, so the water over it is 4 studs deep and reads pale,
-- then ramps back down to the original bed further out.
--
-- These writes go through Terrain:FillBlock DIRECTLY rather than the module's tFill. tFill
-- refuses anything inside the lake zone, which is right for every other pass in this file
-- and wrong here, because the lake bed IS the subject. Every write below is bounded to the
-- near-shore box and stays under y1999, so it can never touch the surface or the outline.
local SHORE_X0, SHORE_X1 = -8092, -7908      -- the stretch either side of the dock
local SHORE_Z_WATERLINE = -7788              -- first water voxel on the x=-8000 line
local SHORE_BED = 1978                       -- original bed
local SHORE_SHALLOW_TOP = 1996               -- raised bed: leaves ~4 studs of water

function M.BuildLakeShore()
	local f = freshFolder("LakeShore")
	local T = Workspace.Terrain
	local rng = Random.new(77404)
	local writes = 0

	-- 1. THE SHALLOW SHELF. A raised bed hugging the shore, then a ramp back down to the
	-- original depth so there is no step for a boat or a skipping stone to catch on.
	local shelfDepth = 30            -- how far out from the waterline the shallows reach
	local z0 = SHORE_Z_WATERLINE
	for x = SHORE_X0, SHORE_X1, 16 do
		-- the shelf wanders in and out so the shallows are not a drawn band
		local reach = shelfDepth * rng:NextNumber(0.72, 1.25)
		local top = SHORE_SHALLOW_TOP + rng:NextNumber(-1.2, 1.2)
		local cz = z0 + reach / 2
		T:FillBlock(
			CFrame.new(x + 8, (SHORE_BED + top) / 2, cz),
			Vector3.new(18, top - SHORE_BED, reach),
			(rng:NextNumber() < 0.7) and Enum.Material.Sand or Enum.Material.Rock)
		writes = writes + 1
		-- the ramp: a wedge running from the shelf lip back down to the old bed
		local rampLen = reach * rng:NextNumber(0.8, 1.3)
		local rc = Vector3.new(x + 8, (SHORE_BED + top) / 2, cz + reach / 2 + rampLen / 2)
		T:FillWedge(
			CFrame.lookAt(rc, rc - Vector3.new(0, 0, 1)) * CFrame.Angles(0, math.rad(180), 0),
			Vector3.new(18, top - SHORE_BED, rampLen),
			Enum.Material.Rock)
		writes = writes + 1
	end

	-- 2. THE ICE RIM. Broken Glacier lumps sitting ON the waterline, never a continuous
	-- lip -- a drawn line round a lake is its own kind of tell.
	local rim = 0
	for x = SHORE_X0, SHORE_X1, 11 do
		if rng:NextNumber() < 0.72 then
			local r = rng:NextNumber(2.4, 4.6)
			local z = z0 + rng:NextNumber(-2.5, 3.5)
			T:FillBall(Vector3.new(x + rng:NextNumber(-3, 3), 2000 + rng:NextNumber(-1.2, 0.4), z),
				r, Enum.Material.Glacier)
			rim = rim + 1
			writes = writes + 1
		end
	end

	-- 3. FLOES. The only parts in this chunk, because anything built from terrain at the
	-- waterline would displace water at the surface. Each floe is two or three thin DISCS
	-- jostled together rather than one rectangular plate -- a clean square tile floating on
	-- a lake reads as placed, the same way a square boulder does. Densest by the dock,
	-- thinning north.
	local floes = 0
	for i = 1, 10 do
		local t = (i - 1) / 9
		local z = z0 + 10 + t * 150 * rng:NextNumber(0.8, 1.2)     -- thinning north
		local x = rng:NextNumber(SHORE_X0 - 10, SHORE_X1 + 10)
		local w = rng:NextNumber(7, 17) * (1 - t * 0.4)
		for _ = 1, rng:NextInteger(2, 3) do
			local d = w * rng:NextNumber(0.45, 0.8)
			local off = Vector3.new(rng:NextNumber(-0.3, 0.3) * w, rng:NextNumber(-0.04, 0.08),
				rng:NextNumber(-0.3, 0.3) * w)
			-- a Cylinder's axis is its X; turned upright it lies flat as a disc
			part(f, "Floe", Vector3.new(0.7, d, d),
				CFrame.new(Vector3.new(x, 2000.1, z) + off) * CFrame.Angles(0, 0, math.rad(90)),
				C.ice, MAT.Glacier, { shadow = false, transparency = 0.08, shape = Enum.PartType.Cylinder })
		end
		floes = floes + 1
	end

	-- 4. SHORE ROCKS, as TERRAIN (MASTER's chunk C call on boulders applies here too).
	-- Each is placed from the MEASURED waterline at its own x, a few studs up the bank, so
	-- none of them reaches the water: the waterline is not straight -- it sits at z -7788 on
	-- the dock line but at -7800 a little either side.
	local wet = RaycastParams.new()
	wet.IgnoreWater = false
	local function landEdgeAt(x)
		for z = -7760, -7850, -1 do
			local r = Workspace:Raycast(Vector3.new(x, 2060, z), Vector3.new(0, -90, 0), wet)
			if r and r.Material ~= Enum.Material.Water then return z end
		end
		return nil
	end
	local rocks = 0
	for i = 1, 4 do
		local x = rng:NextNumber(SHORE_X0, SHORE_X1)
		local r = rng:NextNumber(2.6, 4.2)
		local edge = landEdgeAt(x)
		if edge then
			local c = Vector3.new(x, 2002 + r * 0.2, edge - r * 1.35 - 2)
			T:FillBall(c, r, Enum.Material.Slate)
			T:FillBall(c + Vector3.new(r * 0.6, -r * 0.2, -r * 0.3), r * 0.6, Enum.Material.Slate)
			T:FillBall(c + Vector3.new(0, r * 0.6, 0), r * 0.55, Enum.Material.Snow)
			writes = writes + 3
			rocks = rocks + 1
		end
	end

	local n = 0
	for _, d in ipairs(f:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
	return ("lake shore: %d terrain writes (%d rim lumps, %d terrain shore rocks), %d floes, %d parts total")
		:format(writes, rim, rocks, floes, n)
end

-- ============================================================== C3: THE DOCK APPROACH
-- The Avenue (x -8011..-7989) runs straight north to the dock foot at z -7804, and the
-- Promenade crosses it at z -7832 (-7838..-7826). The plan put C3 AT (-8000, -7836), which
-- is the middle of that crossing -- it would have blocked the main path to the skip dock.
-- Measured instead: the apron between the Promenade edge and the water is only ~18 studs
-- deep (water starts at z -7808 either side of the dock). So C3 is two small groups that
-- FLANK the dock foot and funnel the Promenade into it: a beached sled on the west side, a
-- fish-drying rack on the east, each with a terrain boulder or two.
--
-- Boulders here go through Terrain:FillBall directly, because the module's tBall keeps a
-- 16-stud margin off the lake and the whole apron is inside it. Each one is placed from the
-- measured waterline at its own x and kept at least 6 studs landward of it.
local C3_Z = -7818
local C3_AVENUE_HALF = 16          -- Avenue half-width 11, plus margin

local function c3Ground(x, z)
	local rp = RaycastParams.new()
	rp.IgnoreWater = true
	local r = Workspace:Raycast(Vector3.new(x, 2060, z), Vector3.new(0, -90, 0), rp)
	return r and r.Position.Y or nil
end
local function c3WaterStart(x)
	local wet = RaycastParams.new()
	wet.IgnoreWater = false
	for z = -7835, -7780, 1 do
		local r = Workspace:Raycast(Vector3.new(x, 2060, z), Vector3.new(0, -90, 0), wet)
		if r and r.Material == Enum.Material.Water then return z end
	end
	return nil
end

function M.BuildDockApproach()
	local f = freshFolder("DockApproach")
	local T = Workspace.Terrain
	local rng = Random.new(38113)
	local rocks = 0

	local function boulder(x, r, mat)
		local water = c3WaterStart(x)
		local g = 2002   -- the apron is measured flat at 2002; a raycast would find last run's boulder
		-- stay at least 6 studs landward of the water at this x
		local z = C3_Z
		if water and z + r > water - 6 then z = water - 6 - r end
		local c = Vector3.new(x, g + r * 0.15, z)
		T:FillBall(c, r, mat)
		T:FillBall(c + Vector3.new(r * 0.55, -r * 0.15, -r * 0.2), r * 0.6, mat)
		T:FillBall(c + Vector3.new(0, r * 0.55, 0), r * 0.5, Enum.Material.Snow)
		rocks = rocks + 1
	end

	-- WEST: a beached sled, nose-up on the bank, one runner sunk
	local sx = -8000 - C3_AVENUE_HALF - 18
	local sg = c3Ground(sx, C3_Z) or 2002
	local sled = CFrame.new(sx, sg + 0.9, C3_Z) * CFrame.Angles(math.rad(6), math.rad(-28), math.rad(-5))
	part(f, "SledDeck", Vector3.new(4.4, 0.35, 9), sled, C.timber, MAT.WoodPlanks, { collide = true, shadow = false })
	part(f, "SledRunnerL", Vector3.new(0.35, 0.9, 10.2), sled * CFrame.new(-1.9, -0.55, 0.3), C.timberDark, MAT.Wood, { shadow = false })
	part(f, "SledRunnerR", Vector3.new(0.35, 0.9, 10.2), sled * CFrame.new(1.9, -0.55, 0.3), C.timberDark, MAT.Wood, { shadow = false })
	part(f, "SledBack", Vector3.new(4.4, 2.2, 0.35), sled * CFrame.new(0, 1.1, 4.3) * CFrame.Angles(math.rad(-12), 0, 0), C.timber, MAT.WoodPlanks, { shadow = false })
	part(f, "SledSnow", Vector3.new(3.6, 0.3, 5.5), sled * CFrame.new(0, 0.3, -1.2), C.snow, MAT.Snow, { shadow = false })
	boulder(sx - 9, rng:NextNumber(3.2, 4.2), Enum.Material.Slate)
	boulder(sx + 7, rng:NextNumber(2.4, 3.0), Enum.Material.Glacier)

	-- EAST: a fish-drying rack, two A-frames and a pole, a catch hung to dry
	local rx = -8000 + C3_AVENUE_HALF + 17
	local rg = c3Ground(rx, C3_Z) or 2002
	for _, dx in ipairs({ -4.5, 4.5 }) do
		for _, lean in ipairs({ -14, 14 }) do
			part(f, "RackLeg", Vector3.new(0.45, 7.2, 0.45),
				CFrame.new(rx + dx, rg + 3.4, C3_Z) * CFrame.Angles(math.rad(lean), 0, 0),
				C.timberGrey, MAT.Wood, { shadow = false })
		end
	end
	part(f, "RackPole", Vector3.new(10.5, 0.4, 0.4), CFrame.new(rx, rg + 6.8, C3_Z), C.timberDark, MAT.Wood, { shadow = false })
	for i = 1, 4 do
		local fx = rx - 3.6 + (i - 1) * 2.4
		part(f, "DryingFish", Vector3.new(2.0, 0.55, 0.55),
			CFrame.new(fx, rg + 5.4 - (i % 2) * 0.3, C3_Z) * CFrame.Angles(0, 0, math.rad(90)),
			(i % 2 == 0) and C.brass or C.rockLight, MAT.SmoothPlastic, { shadow = false, shape = Enum.PartType.Cylinder })
	end
	boulder(rx + 9, rng:NextNumber(3.0, 4.0), Enum.Material.Slate)

	-- one lamp on the east side of the dock foot, same warm values as the arrival
	local lx = -8000 + C3_AVENUE_HALF + 2
	local lg = c3Ground(lx, C3_Z - 4) or 2002
	part(f, "DockLampPost", Vector3.new(1.1, 9, 1.1), CFrame.new(lx, lg + 4.5, C3_Z - 4), C.timberDark, MAT.WoodPlanks, { shadow = false })
	local head = part(f, "DockLamp", Vector3.new(1.7, 2.0, 1.7), CFrame.new(lx, lg + 9.6, C3_Z - 4),
		Color3.fromRGB(255, 190, 120), MAT.Neon, { shadow = false })
	local l = Instance.new("PointLight")
	l.Color = Color3.fromRGB(255, 190, 120); l.Brightness = 1.0; l.Range = 20; l.Shadows = false
	l.Parent = head

	local n = 0
	for _, d in ipairs(f:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
	return ("dock approach (C3): %d parts, %d terrain boulders"):format(n, rocks)
end

-- ============================================================== C4: THE DIG CAMP
-- The drill shelf is the one genuinely flat stretch on real ground: exactly y2022 for
-- 400 studs. The HighLedge path runs up the middle of it at x -8290 (9 wide), then at its
-- north end (z -7712) the DigTrail turns east to Tung's hut. The plan put C4 at
-- (-8296, -7906), which is ON that path. So C4 flanks the path instead: spoil heaps either
-- side, thickening toward the north end, and a small working camp -- winch, crates,
-- two lanterns -- at the turn, so the eye is carried up the shelf to where you turn for
-- the hut. Spoil heaps are terrain; only the man-made things are parts.
local C4_PATH_X = -8290
local C4_PATH_HALF = 9            -- path half-width 4.5, plus margin

function M.BuildDigCamp()
	local f = freshFolder("DigCamp")
	local rng = Random.new(61207)
	local heaps = 0
	local rp = RaycastParams.new()
	rp.IgnoreWater = true
	local function ground(x, z)
		local r = Workspace:Raycast(Vector3.new(x, 2060, z), Vector3.new(0, -90, 0), rp)
		return r and r.Position.Y or nil
	end

	-- spoil heaps, alternating sides, closer together toward the turn
	for _, s in ipairs({
		{ -7980, 1 }, { -7910, -1 }, { -7850, 1 }, { -7805, -1 }, { -7770, 1 }, { -7745, -1 },
	}) do
		local z, sideSign = s[1], s[2]
		local off = C4_PATH_HALF + rng:NextNumber(6, 13)
		local x = C4_PATH_X + sideSign * off
		local g = 2022   -- the drill shelf is measured flat at 2022; a raycast would find last run's heap
		if g then
			local r = rng:NextNumber(3.4, 5.6)
			local c = Vector3.new(x, g + r * 0.05, z)
			tBall(c, r, MAT.Rock)
			tBall(c + Vector3.new(sideSign * r * 0.5, -r * 0.2, r * 0.4), r * 0.65, MAT.Ground)
			tBall(c + Vector3.new(-sideSign * r * 0.3, -r * 0.25, -r * 0.5), r * 0.55, MAT.Slate)
			tBall(c + Vector3.new(0, r * 0.5, 0), r * 0.45, MAT.Snow)
			heaps = heaps + 1
		end
	end

	-- THE CAMP AT THE TURN. West of the path, facing the way you turn.
	local cx, cz = C4_PATH_X + C4_PATH_HALF + 8, -7728
	local cg = ground(cx, cz) or 2022
	-- winch: two posts, a drum, a crank
	for _, dz in ipairs({ -2.2, 2.2 }) do
		part(f, "WinchPost", Vector3.new(0.7, 5.2, 0.7), CFrame.new(cx, cg + 2.6, cz + dz),
			C.timberDark, MAT.WoodPlanks, { collide = true, shadow = false })
	end
	part(f, "WinchDrum", Vector3.new(3.8, 1.9, 1.9),
		CFrame.new(cx, cg + 4.3, cz) * CFrame.Angles(0, math.rad(90), 0),
		C.timber, MAT.Wood, { shadow = false, shape = Enum.PartType.Cylinder })
	part(f, "WinchCrank", Vector3.new(0.3, 0.3, 1.8), CFrame.new(cx - 1.1, cg + 4.3, cz + 3.1),
		C.brass, MAT.Metal, { shadow = false })
	part(f, "WinchRope", Vector3.new(0.18, 0.18, 9), CFrame.new(cx - 3.5, cg + 3.3, cz - 3) * CFrame.Angles(math.rad(12), math.rad(-38), 0),
		C.rope, MAT.Fabric, { shadow = false })
	-- a small stack of crates, the top one knocked askew
	local crates = {
		{ Vector3.new(cx + 5.2, cg + 1.5, cz - 3.4), 3.0, 8 },
		{ Vector3.new(cx + 7.9, cg + 1.3, cz - 1.6), 2.6, -11 },
		{ Vector3.new(cx + 6.3, cg + 4.2, cz - 2.7), 2.4, 23 },
	}
	for i, c in ipairs(crates) do
		part(f, "Crate" .. i, Vector3.new(c[2], c[2], c[2]),
			CFrame.new(c[1]) * CFrame.Angles(0, math.rad(c[3]), 0),
			(i == 3) and C.timberGrey or C.timber, MAT.WoodPlanks, { collide = i < 3, shadow = false })
	end
	-- two lanterns either side of the turn onto the DigTrail
	for i, spot in ipairs({ { C4_PATH_X + C4_PATH_HALF + 1, -7718 }, { C4_PATH_X - C4_PATH_HALF - 1, -7722 } }) do
		local g = ground(spot[1], spot[2]) or 2022
		part(f, "CampLampPost" .. i, Vector3.new(1.1, 9, 1.1), CFrame.new(spot[1], g + 4.5, spot[2]),
			C.timberDark, MAT.WoodPlanks, { shadow = false })
		local head = part(f, "CampLamp" .. i, Vector3.new(1.7, 2.0, 1.7), CFrame.new(spot[1], g + 9.6, spot[2]),
			Color3.fromRGB(255, 190, 120), MAT.Neon, { shadow = false })
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 190, 120); l.Brightness = 1.0; l.Range = 20; l.Shadows = false
		l.Parent = head
	end

	local n = 0
	for _, d in ipairs(f:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
	return ("dig camp (C4): %d parts, %d terrain spoil heaps"):format(n, heaps)
end

-- ============================================================== CAMP DRESSING
-- The six Tundra camps are baked place content, not built by any script. Two things in them read
-- as the "AI-built" tell (ITEM 7 audit): the CampSpire ice prisms -- square-section boxes that look
-- like flat slabs from most angles -- and the pale pad grid. This step rebuilds the spires as
-- faceted crystal clusters (the RockMeshes crystal, one part per crystal) from RECORDED positions,
-- so it still works when re-run after the originals are gone, with a different number kept per
-- camp so no two neighbouring camps match.
--   { x, y, z, width, height } -- the centre and size each CampSpire had
local CAMP_SPIRES = {
	[7] = { { -8113.5, 2016.1, -8034.9, 3.0, 19.3 }, { -8153.0, 2019.6, -8083.3, 4.1, 26.3 }, { -8098.7, 2017.5, -8037.7, 3.5, 22.2 },
		{ -8149.0, 2018.4, -8045.6, 3.8, 24.0 }, { -8118.8, 2019.8, -8100.8, 4.2, 26.7 } },
	[8] = { { -8146.4, 2016.6, -8000.6, 3.2, 20.4 }, { -8098.7, 2017.7, -7947.7, 3.5, 22.5 }, { -8153.6, 2016.6, -7963.5, 3.2, 20.2 },
		{ -8108.6, 2018.5, -8007.5, 3.8, 24.1 }, { -8122.8, 2018.2, -7942.9, 3.7, 23.5 } },
	[9] = { { -8126.0, 2017.3, -7918.4, 3.3, 21.3 }, { -8109.8, 2016.1, -7850.3, 3.0, 19.0 }, { -8154.6, 2019.3, -7893.6, 4.0, 25.2 },
		{ -8099.7, 2017.6, -7911.2, 3.5, 22.0 }, { -8143.1, 2017.7, -7858.4, 3.5, 22.1 } },
	[10] = { { -7898.2, 2017.8, -7909.0, 3.5, 22.3 }, { -7850.5, 2018.5, -7864.2, 3.7, 23.8 }, { -7838.9, 2019.3, -7896.4, 4.0, 25.3 },
		{ -7886.8, 2016.4, -7856.5, 3.1, 19.5 }, { -7886.8, 2020.3, -7919.4, 4.3, 27.3 } },
	[11] = { { -7862.8, 2018.1, -8009.3, 3.6, 23.1 }, { -7896.4, 2020.4, -7952.8, 4.4, 27.8 }, { -7899.4, 2017.4, -7997.8, 3.4, 21.8 },
		{ -7868.9, 2017.8, -7943.4, 3.6, 22.7 }, { -7839.6, 2019.0, -7961.4, 3.9, 24.9 } },
	[12] = { { -7891.8, 2019.4, -8093.9, 4.0, 25.6 }, { -7853.4, 2019.3, -8094.3, 4.0, 25.3 }, { -7896.4, 2016.9, -8042.8, 3.2, 20.6 },
		{ -7878.2, 2019.9, -8033.0, 4.2, 26.6 }, { -7845.1, 2016.9, -8041.7, 3.2, 20.5 } },
}
-- How many of each camp's five spots keep a cluster. Rows run 7-8-9 (east) and 12-11-10 (west),
-- and 7/12, 8/11, 9/10 face each other: no neighbour in either direction has the same count.
local CAMP_SPIRE_COUNT = { [7] = 5, [8] = 3, [9] = 4, [10] = 3, [11] = 5, [12] = 4 }
-- The UNCLAIMED pad look only. PlayerDataManager.refreshSpotsOn repaints a camp's pads (material
-- included) the moment it is owned, and that shared code is left exactly as it is.
local CAMP_PAD_COLOUR = Color3.fromRGB(104, 120, 138)

function M.BuildCampDressing()
	local bases = Workspace:FindFirstChild("PlayerBases")
	if not bases then return "no PlayerBases -- nothing done" end
	local crystals, removed, repainted = 0, 0, 0
	for plotN, spots in pairs(CAMP_SPIRES) do
		local plot = bases:FindFirstChild("Plot" .. plotN)
		local camp = plot and plot:FindFirstChild("TundraCamp")
		if camp then
			for _, d in ipairs(camp:GetDescendants()) do
				if d.Name == "CampSpire" and d:IsA("BasePart") then d:Destroy(); removed += 1 end
			end
			local old = camp:FindFirstChild("Crystals")
			if old then old:Destroy() end
			local f = Instance.new("Folder")
			f.Name = "Crystals"
			f.Parent = camp
			local rng = Random.new(5100 + plotN)
			for i = 1, math.min(CAMP_SPIRE_COUNT[plotN] or #spots, #spots) do
				local s = spots[i]
				local foot = Vector3.new(s[1], s[2] - s[5] / 2, s[3])
				local h = s[5] * rng:NextNumber(0.8, 0.95)
				local main = rock(f, "Crystal", "crystal", Vector3.new(h * 0.26, h, h * 0.26),
					CFrame.new(foot + Vector3.new(0, h * 0.46, 0))
						* CFrame.Angles(math.rad(rng:NextNumber(-6, 6)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-6, 6))),
					(i % 2 == 0) and C.ice or C.iceDeep, MAT.Ice)
				main.Transparency = 0.08
				crystals += 1
				-- one or two smaller shards leaning out of the same foot
				for _ = 1, (i % 2 == 0) and 1 or 2 do
					local sh = h * rng:NextNumber(0.35, 0.55)
					local a = math.rad(rng:NextNumber(0, 360))
					local off = Vector3.new(math.cos(a), 0, math.sin(a)) * h * 0.14
					local shard = rock(f, "Crystal", "crystal", Vector3.new(sh * 0.3, sh, sh * 0.3),
						CFrame.new(foot + off + Vector3.new(0, sh * 0.42, 0))
							* CFrame.Angles(0, a, 0) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(18, 32))),
						C.ice, MAT.Ice)
					shard.Transparency = 0.08
					crystals += 1
				end
			end
			local pads = plot:FindFirstChild("Pads")
			if pads and (plot:GetAttribute("OwnerUserId") or 0) == 0 then
				for _, pad in ipairs(pads:GetChildren()) do
					if pad:IsA("BasePart") and pad.Name:match("^Pad%d+$") then
						pad.Material = MAT.Slate
						pad.Color = CAMP_PAD_COLOUR
						repainted += 1
					end
				end
			end
		end
	end
	return ("camp dressing: %d spire prisms removed, %d crystals placed, %d unclaimed pads recoloured")
		:format(removed, crystals, repainted)
end

-- ============================================================== RUIN RUBBLE
-- Ruins.BrokenWatchtower carried 26 Slate cubes for rubble (1-2.5 studs), and they FLOATED about
-- 6.7 studs above the gallery floor (y ~2054.7 over ground at 2048). From the default camera on the
-- gallery -- the Tundra's highest walkable point -- they hung right in front of the lens and read as
-- big grey boxes (ITEM 7 audit, shot 8). They become six terrain rock piles on the actual ground.
local RUBBLE_PILES = {
	{ -7714.0, -8003.0, 3.0 }, { -7707.6, -8007.3, 3.0 }, { -7704.0, -7999.3, 2.4 },
	{ -7697.5, -8011.4, 2.6 }, { -7702.0, -8022.6, 3.2 }, { -7693.4, -8023.1, 3.0 },
}
local RUBBLE_GROUND = 2048   -- the gallery floor, measured; a fixed floor so a re-run cannot stack

function M.BuildRuinRubble()
	local ruins = Workspace.GameWorld.FrozenTundra:FindFirstChild("Ruins")
	local tower = ruins and ruins:FindFirstChild("BrokenWatchtower")
	local removed = 0
	if tower then
		for _, d in ipairs(tower:GetChildren()) do
			if d.Name == "Rubble" and d:IsA("BasePart") then d:Destroy(); removed += 1 end
		end
	end
	for i, p in ipairs(RUBBLE_PILES) do
		local c = Vector3.new(p[1], RUBBLE_GROUND + p[3] * 0.2, p[2])
		tBall(c, p[3], (i % 2 == 0) and MAT.Rock or MAT.Slate)
		tBall(c + Vector3.new(p[3] * 0.6, -p[3] * 0.25, p[3] * 0.3), p[3] * 0.6, MAT.Slate)
		tBall(c + Vector3.new(0, p[3] * 0.45, 0), p[3] * 0.5, MAT.Snow)
	end
	return ("ruin rubble: %d floating cube parts removed, %d terrain piles on the ground")
		:format(removed, #RUBBLE_PILES)
end

-- ============================================================== DOCK SNOW
-- The deck carried three flat Snow tiles -- a 56x7 strip across the dock foot and two small patches
-- -- that read as square white tiles laid on the planks (ITEM 7 audit, shot 4). They become a few
-- low terrain drifts. Every drift's lowest point stays above y2000.5, so no water voxel is touched
-- (the lake surface is 2000). The thin snow strips along the two rails stay: they read as snow
-- caught on the rail, not as tiles. Written with Terrain:FillBall directly, because the deck is
-- inside the lake margin that tBall refuses on purpose.
local DOCK_DRIFTS = {
	{ -8021, -7815, 2.4 }, { -8009, -7816, 1.8 }, { -7994, -7815, 2.0 }, { -7980, -7816, 2.4 },
	{ -8025, -7809, 1.8 }, { -7977, -7807, 1.6 },
}

function M.BuildDockSnow()
	local sa = Workspace.GameWorld.FrozenTundra:FindFirstChild("SkipArea")
	local dock = sa and sa:FindFirstChild("Dock")
	local removed = 0
	if dock then
		for _, d in ipairs(dock:GetDescendants()) do
			if d.Name == "Dust" and d:IsA("BasePart") and d.Size.X > 5 then d:Destroy(); removed += 1 end
		end
	end
	for _, p in ipairs(DOCK_DRIFTS) do
		Workspace.Terrain:FillBall(Vector3.new(p[1], 2000.6 + p[3], p[2]), p[3], MAT.Snow)
	end
	return ("dock snow: %d flat snow tiles removed, %d terrain drifts"):format(removed, #DOCK_DRIFTS)
end

-- ============================================================== CAMP VARIATION
-- ITEM 7 found the six camps identical side by side. Each camp now differs in tent canvas (no two
-- neighbours in a row or across the Avenue share a colour), in crystal count (CAMP_SPIRE_COUNT,
-- above) and in how its hearth is laid. The fire itself does NOT move: the functional Campfire part
-- sits at the camp centre, and CampfireBankClient's collect ring (r 5.6, which "EXACTLY matches
-- CAMPFIRE_RADIUS") and the tutorial both key off it. So the decorative hearth -- logs, stones,
-- embers, ash bed -- is turned about that same centre instead, by a different angle per camp.
local CAMP_TENT = {
	[7] = Color3.fromRGB(150, 70, 58), [8] = Color3.fromRGB(62, 84, 120), [9] = Color3.fromRGB(168, 128, 70),
	[10] = Color3.fromRGB(84, 98, 70), [11] = Color3.fromRGB(196, 182, 150), [12] = Color3.fromRGB(70, 68, 72),
}
local CAMP_FIRE_YAW = { [7] = 0, [8] = 40, [9] = 95, [10] = 150, [11] = 210, [12] = 275 }
local HEARTH = { FireBedAsh = true, FireLog = true, FireLogCharred = true, HearthStone = true, Ember = true }

function M.BuildCampVariation()
	local bases = Workspace:FindFirstChild("PlayerBases")
	if not bases then return "no PlayerBases -- nothing done" end
	local tents, turned = 0, 0
	for plotN, col in pairs(CAMP_TENT) do
		local plot = bases:FindFirstChild("Plot" .. plotN)
		local camp = plot and plot:FindFirstChild("TundraCamp")
		local fire = plot and plot:FindFirstChild("Campfire")
		if camp and fire then
			local tent = camp:FindFirstChild("Tent")
			if tent then
				for _, d in ipairs(tent:GetChildren()) do
					if d.Name == "Canvas" and d:IsA("BasePart") then
						d.Color = col
						tents += 1
					elseif d.Name == "Flap" and d:IsA("BasePart") then
						d.Color = col:Lerp(Color3.new(0, 0, 0), 0.18)
					end
				end
			end
			-- turn by the DIFFERENCE from what is already applied, so a re-run is a no-op
			local want = CAMP_FIRE_YAW[plotN] or 0
			local have = camp:GetAttribute("HearthYaw") or 0
			local delta = math.rad(want - have)
			if delta ~= 0 then
				local pivot = CFrame.new(fire.Position.X, 0, fire.Position.Z)
				local turn = pivot * CFrame.Angles(0, delta, 0) * pivot:Inverse()
				for _, d in ipairs(camp:GetChildren()) do
					if d:IsA("BasePart") and HEARTH[d.Name] then
						d.CFrame = turn * d.CFrame
						turned += 1
					end
				end
			end
			camp:SetAttribute("HearthYaw", want)
		end
	end
	return ("camp variation: %d tent canvases recoloured, %d hearth parts turned"):format(tents, turned)
end

-- ============================================================== SPUR DRIFTS
-- The ~90-stud strip between the Avenue and each camp row was one flat snow plane (ITEM 7, shots 6
-- and 7). Low drifts now run alongside each spur path and between them, so the ground breaks up and
-- the paths read as trodden lines through it. Every mound stays clear of the paths: its centre line
-- is 11-14 studs off a spur's (spurs are 8 wide) and it stops short of the Avenue (x -8016..-7984).
-- Set on the measured apron height 2002 -- a fixed floor, so a re-run never stacks.
local SPUR_Z = { -8065, -7975, -7885 }
local SPUR_MID_Z = { -8020, -7930 }

function M.BuildSpurDrifts()
	local rng = Random.new(66021)
	local ridges = 0
	local function ridge(x0, x1, z)
		local n = math.max(3, math.floor(math.abs(x1 - x0) / 6))
		for k = 0, n do
			local x = x0 + (x1 - x0) * (k / n)
			local r = rng:NextNumber(2.6, 4.2)
			tBall(Vector3.new(x + rng:NextNumber(-1.5, 1.5), 2002 - r * 0.35, z + rng:NextNumber(-1.2, 1.2)), r, MAT.Snow)
		end
		ridges += 1
	end
	for _, side in ipairs({ { -8030, -8082 }, { -7970, -7918 } }) do
		for _, z in ipairs(SPUR_Z) do
			ridge(side[1], side[2], z - rng:NextNumber(11, 14))
			ridge(side[1], side[2], z + rng:NextNumber(11, 14))
		end
		for _, z in ipairs(SPUR_MID_Z) do
			ridge(side[1] + (side[2] - side[1]) * 0.15, side[2], z + rng:NextNumber(-3, 3))
		end
	end
	return ("spur drifts: %d low snow ridges"):format(ridges)
end

-- ============================================================== ICE CAMP
-- Two fishing huts on the lake banks at the dock end of the ice field, so the field reads as a
-- place people fish from rather than a blank sheet (ITEM 7 audit, shot 5). On land, 19-24 studs
-- clear of the shore paths and clear of the ledges behind them, each facing the lake. Floor
-- heights come from the probe, fixed, so a re-run never stacks.
--   { x, z, ground y, facing (+1 = door toward +X) }
local ICE_HUTS = {
	{ -8218, -7735, 2002.0, 1 },    -- east bank
	{ -7782, -7705, 2001.5, -1 },   -- west bank
}

function M.BuildIceCamp()
	local f = freshFolder("IceCamp")
	for i, h in ipairs(ICE_HUTS) do
		-- local frame: +X points out through the door, toward the lake
		local base = CFrame.new(h[1], h[3], h[2]) * CFrame.Angles(0, h[4] > 0 and 0 or math.pi, 0)
		local W, D, H = 8, 7, 6.5
		local function p(name, size, off, col, mat, opts)
			return part(f, name .. i, size, base * off, col, mat, opts)
		end
		p("HutFloor", Vector3.new(D + 1, 0.6, W + 1), CFrame.new(0, 0.3, 0), C.timberDark, MAT.WoodPlanks, { collide = true })
		p("HutBack", Vector3.new(0.5, H, W), CFrame.new(-D / 2, H / 2 + 0.6, 0), C.timber, MAT.WoodPlanks, { collide = true })
		p("HutSideN", Vector3.new(D, H, 0.5), CFrame.new(0, H / 2 + 0.6, W / 2), C.timber, MAT.WoodPlanks, { collide = true })
		p("HutSideS", Vector3.new(D, H, 0.5), CFrame.new(0, H / 2 + 0.6, -W / 2), C.timber, MAT.WoodPlanks, { collide = true })
		-- the door wall: two jambs and a lintel, leaving a dark doorway facing the ice
		p("HutFrontN", Vector3.new(0.5, H, 2.5), CFrame.new(D / 2, H / 2 + 0.6, W / 2 - 1.25), C.timber, MAT.WoodPlanks, { collide = true })
		p("HutFrontS", Vector3.new(0.5, H, 2.5), CFrame.new(D / 2, H / 2 + 0.6, -W / 2 + 1.25), C.timber, MAT.WoodPlanks, { collide = true })
		p("HutLintel", Vector3.new(0.5, 1.6, 3.0), CFrame.new(D / 2, H - 0.2, 0), C.timber, MAT.WoodPlanks, {})
		-- a pitched roof in two planes, dark timber, with snow lying on one side
		for _, s in ipairs({ 1, -1 }) do
			p("HutRoof", Vector3.new(D + 1.6, 0.5, W / 2 + 1.4),
				CFrame.new(0, H + 1.9, s * (W / 4 + 0.3)) * CFrame.Angles(math.rad(s * 28), 0, 0),
				C.timberDark, MAT.WoodPlanks, {})
		end
		p("HutRoofSnow", Vector3.new(D + 1.2, 0.35, W / 2 + 1.0),
			CFrame.new(0, H + 2.35, W / 4 + 0.3) * CFrame.Angles(math.rad(28), 0, 0), C.snow, MAT.Snow, {})
		p("HutPipe", Vector3.new(3.2, 0.7, 0.7),
			CFrame.new(-D / 4, H + 3.2, -W / 4) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(70, 74, 82), MAT.Metal, { shape = Enum.PartType.Cylinder })
		local win = p("HutWindow", Vector3.new(0.3, 1.4, 1.8),
			CFrame.new(0, H * 0.62, W / 2 + 0.05) * CFrame.Angles(0, math.rad(90), 0),
			C.warm, MAT.Glass, { transparency = 0.25 })
		local l = Instance.new("PointLight")
		l.Color = C.warm
		l.Brightness = 0.8
		l.Range = 12
		l.Shadows = false
		l.Parent = win
	end
	local n = 0
	for _, d in ipairs(f:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
	return ("ice camp: %d fishing huts, %d parts"):format(#ICE_HUTS, n)
end

-- ============================================================== WARMHOUSE FRONT
-- From the plaza the facade was one 224-stud flat plank wall under a dead-level roof line, with
-- four flat Neon panes stuck on it (ITEM 7 audit, shot 3). This step gives the front a shape:
--   * a cross GABLE over the door, 56 wide, so the roof line peaks over the entrance;
--   * two canted BAY windows flanking the porch, on the two inner windows;
--   * ridge caps -- on the gable, and a dark crest along the lean-to roof's top edge (this
--     replaces WarmhouseHero's RidgeBeam, which the lean-to roof had swallowed whole);
--   * Glass fronts on the two outer windows, the warm pane glowing behind them.
-- The door (x -8014..-7986), the porch, the name board, the door lamps and the signpost are
-- not touched. Everything is set from fixed numbers, so a re-run is identical.
-- Run AFTER BuildWarmhouse and BuildWarmhouseHero: it removes the flat frames BuildWarmhouse
-- put on the two bay windows, and WarmhouseHero's hidden RidgeBeam.
local WF_GABLE = { x = -8000, w = 56, base = 2039.0, rise = 16, zFront = -8245.6, zBack = -8280 }
local WF_BAYS = { -8045, -7955 }
local WF_GLASS = { -8080, -7920 }
local WF_FRAME = { WindowHead = true, WindowSill = true, WindowJamb = true, Mullion = true, Transom = true, SillSnow = true }
local WF_GLASS_COL = Color3.fromRGB(206, 220, 230)
-- the lit room behind the glass: warm, but NOT Neon -- a Neon pane behind Glass still read as a
-- flat orange sticker (and Neon blows out under Bloom); a SurfaceLight gives it the glow instead
local WF_PANE = Color3.fromRGB(200, 132, 66)

function M.BuildWarmhouseFront()
	local f = freshFolder("WarmhouseFront")
	local ft = Workspace.GameWorld.FrozenTundra
	local wh = ft.Greybox:FindFirstChild("Warmhouse")
	if not wh then return "Warmhouse greybox not found -- nothing done" end
	local removed = 0

	-- 1. THE GABLE. A triangle of plank wall in front of the lean-to's eave, two pitched roof
	-- planes running back into the lean-to, a closed back triangle, dark barge boards on the
	-- rake so the peak reads against the snow and sky.
	local G = WF_GABLE
	local half = G.w / 2
	local a = math.atan2(G.rise, half)
	local slopeLen = math.sqrt(half * half + G.rise * G.rise) + 2.5
	local zEave = G.zFront + 2.5                      -- the roof overhangs the gable face by 2.5
	local depth = zEave - G.zBack
	local zMid = (zEave + G.zBack) / 2
	for _, z in ipairs({ G.zFront, G.zBack + 0.5 }) do
		for _, s in ipairs({ -1, 1 }) do
			-- a WedgePart rises toward its local +Z: yaw it so it rises toward the apex
			part(f, "GableWall", Vector3.new(1.0, G.rise, half),
				CFrame.new(G.x + s * half / 2, G.base + G.rise / 2, z) * CFrame.Angles(0, math.rad(-s * 90), 0),
				LOGWALL, MAT.WoodPlanks, { class = "WedgePart", shadow = true })
		end
	end
	part(f, "GableTie", Vector3.new(G.w + 3, 1.8, 1.8), CFrame.new(G.x, G.base + 0.2, G.zFront + 0.4), C.timberDark, MAT.Wood, { shadow = false })
	for _, s in ipairs({ -1, 1 }) do
		local mid = Vector3.new(G.x + s * half / 2, G.base + G.rise / 2, zMid)
		local plane = CFrame.new(mid) * CFrame.Angles(0, 0, -s * a) * CFrame.new(s * 1.25, 0.4, 0)
		part(f, "GableRoof", Vector3.new(slopeLen, 0.8, depth), plane, C.timberDark, MAT.WoodPlanks, { shadow = true })
		part(f, "GableRoofSnow", Vector3.new(slopeLen - 3.2, 0.5, depth - 3.5), plane * CFrame.new(-s * 0.4, 0.6, -1.2),
			C.snow, MAT.Snow, { shadow = false })
		part(f, "BargeBoard", Vector3.new(slopeLen + 0.4, 1.7, 0.9),
			CFrame.new(G.x + s * half / 2, G.base + G.rise / 2, zEave + 0.3) * CFrame.Angles(0, 0, -s * a) * CFrame.new(s * 1.25, 0.25, 0),
			C.timberDark, MAT.Wood, { shadow = false })
	end
	-- the gable's ridge cap: a square beam turned on its edge, so the peak has a crisp dark line
	part(f, "RidgeCap", Vector3.new(1.9, 1.9, depth + 0.8),
		CFrame.new(G.x, G.base + G.rise + 0.9, zMid + 0.3) * CFrame.Angles(0, 0, math.rad(45)), C.timberDark, MAT.Wood, { shadow = false })
	-- a small diamond window in the gable, lit from behind, framed and crossed
	local wc = CFrame.new(G.x, G.base + 6.6, G.zFront) * CFrame.Angles(0, 0, math.rad(45))
	part(f, "GableGlow", Vector3.new(4.4, 4.4, 0.2), wc * CFrame.new(0, 0, 0.55), WF_PANE:Lerp(Color3.new(1, 1, 1), 0.15), MAT.SmoothPlastic, { shadow = false })
	part(f, "GableGlass", Vector3.new(4.4, 4.4, 0.2), wc * CFrame.new(0, 0, 0.75), WF_GLASS_COL, MAT.Glass, { shadow = false, transparency = 0.4 })
	for _, e in ipairs({ { 0, 2.55, 5.8, 0.7 }, { 0, -2.55, 5.8, 0.7 }, { 2.55, 0, 0.7, 5.8 }, { -2.55, 0, 0.7, 5.8 } }) do
		part(f, "GableWindowFrame", Vector3.new(e[3], e[4], 0.6), wc * CFrame.new(e[1], e[2], 0.8), C.timberDark, MAT.Wood, { shadow = false })
	end
	part(f, "GableMuntin", Vector3.new(4.4, 0.3, 0.3), wc * CFrame.new(0, 0, 0.9), C.timberDark, MAT.Wood, { shadow = false })
	part(f, "GableMuntin", Vector3.new(0.3, 4.4, 0.3), wc * CFrame.new(0, 0, 0.9), C.timberDark, MAT.Wood, { shadow = false })

	-- 2. RIDGE CAP ON THE LEAN-TO. Its high edge is against the cliff (y 2052.5 at z -8346); a
	-- dark crest there gives the roof a top line from the plaza. WarmhouseHero's RidgeBeam sat
	-- at y2041.6 INSIDE the lean-to's snow wedge, invisible, so it goes.
	part(f, "CrestCap", Vector3.new(230, 2.0, 2.6), CFrame.new(-8000, 2052.9, -8345.4), C.timberDark, MAT.WoodPlanks, { shadow = false })
	local hero = ft.Art:FindFirstChild("WarmhouseHero")
	local rb = hero and hero:FindFirstChild("RidgeBeam")
	if rb then rb:Destroy(); removed += 1 end

	-- 3. THE BAYS. Canted: a 12-wide front and two 45-degree sides, 5 out from the wall, on a
	-- stone base, Glass all round, under a snow-covered hood. The warm pane on the wall behind
	-- is enlarged to fill the bay, so it reads as the lit room inside.
	local art = ft.Art:FindFirstChild("Warmhouse")
	local FW, P = 12, 5
	local z0 = -8249.9                                -- just proud of the wall face (-8250)
	local sideLen = P * math.sqrt(2)
	for _, bx in ipairs(WF_BAYS) do
		if art then
			for _, d in ipairs(art:GetChildren()) do
				if d:IsA("BasePart") and WF_FRAME[d.Name] and math.abs(d.Position.X - bx) < 9 then d:Destroy(); removed += 1 end
			end
		end
		for _, q in ipairs(wh:GetChildren()) do
			if q.Name == "WarmWindow" and math.abs(q.Position.X - bx) < 1 then
				q.Size = Vector3.new(19, 7.6, 0.6)
				q.Position = Vector3.new(bx, 2014.7, q.Position.Z)
			end
		end
		-- the three faces of the bay in plan: front, then the two canted sides
		local faces = {
			{ CFrame.new(bx, 0, z0 + P), FW },
		}
		for _, s in ipairs({ -1, 1 }) do
			faces[#faces + 1] = { CFrame.new(bx + s * (FW / 2 + P / 2), 0, z0 + P / 2) * CFrame.Angles(0, math.rad(s * 45), 0), sideLen }   -- local +Z faces outward
		end
		for _, fc in ipairs(faces) do
			local cf, w = fc[1], fc[2]
			local at = function(y, out) return cf * CFrame.new(0, y, out or 0) end
			part(f, "BayBase", Vector3.new(w + 0.3, 9, 1.2), at(2005.5, -0.6), STONE, MAT.Slate, { collide = true, shadow = false })
			part(f, "BaySill", Vector3.new(w + 0.6, 0.6, 1.8), at(2010.3, -0.3), C.timberDark, MAT.Wood, { shadow = false })
			part(f, "BayGlass", Vector3.new(w, 8, 0.3), at(2014.6, -0.3), WF_GLASS_COL, MAT.Glass, { shadow = false, transparency = 0.45 })
			part(f, "BayHead", Vector3.new(w + 0.6, 1.0, 1.2), at(2019.1, -0.4), C.timberDark, MAT.Wood, { shadow = false })
			part(f, "BayTransom", Vector3.new(w, 0.4, 0.5), at(2016.6, -0.2), C.timberDark, MAT.Wood, { shadow = false })
		end
		part(f, "BayMullion", Vector3.new(0.45, 8, 0.5), CFrame.new(bx, 2014.6, z0 + P - 0.2), C.timberDark, MAT.Wood, { shadow = false })
		for _, s in ipairs({ -1, 1 }) do
			part(f, "BayPost", Vector3.new(1.0, 8.2, 1.0), CFrame.new(bx + s * FW / 2, 2014.6, z0 + P - 0.3), C.timberDark, MAT.Wood, { shadow = false })
			part(f, "BayPost", Vector3.new(1.0, 8.2, 1.0), CFrame.new(bx + s * (FW / 2 + P), 2014.6, z0 + 0.4), C.timberDark, MAT.Wood, { shadow = false })
		end
		local floor = part(f, "BayFloor", Vector3.new(FW, 0.5, P), CFrame.new(bx, 2010.2, z0 + P / 2), C.timberDark, MAT.WoodPlanks, { shadow = false })
		light(floor, C.warm, 12, 0.6)   -- a little warm spill on the snow below the bay
		-- the hood: one pitched slab over the whole bay, dropping outward, snow on it
		local run = P + 1.6
		local b = math.atan2(3.2, run)
		local hood = CFrame.new(bx, 2019.6 + 1.6 + 0.3, z0 + run / 2) * CFrame.Angles(b, 0, 0)
		part(f, "BayRoof", Vector3.new(FW + 2 * P + 1.6, 0.6, run / math.cos(b)), hood, C.timberDark, MAT.WoodPlanks, { shadow = true })
		part(f, "BayRoofSnow", Vector3.new(FW + 2 * P + 0.6, 0.45, run / math.cos(b) - 1.0), hood * CFrame.new(0, 0.5, -0.3), C.snow, MAT.Snow, { shadow = false })
	end

	-- 4. GLASS ON THE WINDOWS. All four warm panes become a lit room (SmoothPlastic + a SurfaceLight,
	-- no longer Neon), and the two outer ones get a Glass pane in front that takes the sky's
	-- reflection, so each reads as a window rather than a sticker.
	for _, q in ipairs(wh:GetChildren()) do
		if q.Name == "WarmWindow" and q:IsA("BasePart") then
			q.Material = MAT.SmoothPlastic
			q.Color = WF_PANE
			local sl = q:FindFirstChild("PaneLight") or Instance.new("SurfaceLight")
			sl.Name = "PaneLight"
			sl.Face = Enum.NormalId.Back   -- +Z, out through the facade
			sl.Color = C.warm
			sl.Brightness = 1.2
			sl.Range = 12
			sl.Angle = 110
			sl.Shadows = false
			sl.Parent = q
		end
	end
	for _, x in ipairs(WF_GLASS) do
		part(f, "WindowGlass", Vector3.new(14, 6, 0.25), CFrame.new(x, 2015, -8249.45), WF_GLASS_COL, MAT.Glass, { shadow = false, transparency = 0.4 })
	end

	local n = 0
	for _, d in ipairs(f:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
	return ("warmhouse front: gable, %d bays, crest cap, %d glass windows -- %d parts, %d old parts removed")
		:format(#WF_BAYS, #WF_GLASS, n, removed)
end

return M
