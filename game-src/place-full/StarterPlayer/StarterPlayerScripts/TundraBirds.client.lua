-- Frozen Tundra ambience: skeins of seabirds crossing the sky.
--
-- CLIENT-SIDE AND WORLD 2 ONLY, the same shape as TundraWeatherFX: the birds are
-- pure decoration, nothing about them needs to agree between players, and a server
-- that replicated ~20 moving parts per flock to everyone would be paying for scenery.
-- Everything switches off outside the Tundra region, so World 1 pays nothing at all.
--
-- ALTITUDE IS NOT ARBITRARY. The hub dome's roof plate sits at about Y 2068 over ice
-- at 2002. Anything flying below that is inside the dome -- invisible from the plaza
-- and clipping through the roof from outside. The band below clears it.
--
-- NO CALL SOUND. SoundKit has no bird id (checked: 45 ids, nothing avian), and a
-- made-up rbxassetid either fails to load or plays something unrelated. Add one to
-- SoundKit.Ids and this file can play it on spawn -- see CALL_ID below.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

-- matches BoundsGuard's Tundra region, like TundraAtmosphere and TundraWeatherFX
local MIN = Vector3.new(-8600, 1850, -8600)
local MAX = Vector3.new(-7400, 2250, -6700)

local ICE_Y      = 2002
-- WORLD 2 REBUILD (2026-09-21): the caldera walls now stand 2090-2150 -- right across the
-- old 2080-2120 band, which only had to clear the dome roof -- so flocks flew through
-- cliffs. The band now clears the tallest wall, and pickLine below also refuses any line
-- that still meets terrain (the rim and the Sundered Peak rise higher, outside the walls).
local ALT_MIN    = ICE_Y + 168     -- 2170: over the tallest caldera wall (2150)
local ALT_MAX    = ICE_Y + 208     -- 2210: under the rim (2230+)
local GAP_MIN    = 22              -- seconds between flocks
local GAP_MAX    = 55
local FLOCK_MIN  = 3
local FLOCK_MAX  = 7
local SPEED_MIN  = 52
local SPEED_MAX  = 84
local CROSS      = 620             -- how far a flock travels, start to finish
local PASS_MIN   = 40              -- how close the line passes to the player, in studs
local PASS_MAX   = 150
local CALL_ID    = nil             -- e.g. "birdCall" once SoundKit has one

local BODY  = Color3.fromRGB(58, 64, 76)
local WING  = Color3.fromRGB(82, 90, 104)

local rng = Random.new()

local folder = Instance.new("Folder")
folder.Name = "TundraBirds"
folder.Parent = Workspace

local function inTundra(p)
	return p.X >= MIN.X and p.X <= MAX.X
		and p.Y >= MIN.Y and p.Y <= MAX.Y
		and p.Z >= MIN.Z and p.Z <= MAX.Z
end

local function part(name, size, colour)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = colour
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Locked = true
	return p
end

-- One bird: a stubby body and two wings driven by CFrame every frame. No welds and
-- no Motor6Ds -- three anchored parts repositioned together is cheaper than a rig,
-- and at this distance the silhouette is all that reads anyway.
local function makeBird(parent)
	local body = part("Body", Vector3.new(0.6, 0.5, 2.2), BODY)
	body.Parent = parent
	local l = part("WingL", Vector3.new(2.6, 0.14, 1.0), WING)
	l.Parent = parent
	local r = part("WingR", Vector3.new(2.6, 0.14, 1.0), WING)
	r.Parent = parent
	return {
		body = body, l = l, r = r,
		phase = rng:NextNumber(0, math.pi * 2),
		flap  = rng:NextNumber(6.5, 9.0),      -- radians/sec
		-- each bird holds its slot in the V with a little drift of its own
		bob   = rng:NextNumber(0.6, 1.6),
		bobHz = rng:NextNumber(0.5, 1.1),
	}
end

local active = nil        -- the flock currently crossing, if any
local nextAt = 0

-- A flight line that stays in open sky: a few random headings and heights, keeping the
-- first whose path -- and the V's width either side of it -- meets no terrain. nil if
-- none does; that flock is skipped and the next one is only a gap away.
local skyParams = RaycastParams.new()
skyParams.FilterType = Enum.RaycastFilterType.Include
skyParams.FilterDescendantsInstances = { Workspace.Terrain }

local function pickLine(origin)
	for _ = 1, 8 do
		-- a line that passes the player rather than through them
		local heading = rng:NextNumber(0, math.pi * 2)
		local dir = Vector3.new(math.cos(heading), 0, math.sin(heading))
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local offset = side * (rng:NextNumber(PASS_MIN, PASS_MAX) * (rng:NextInteger(0, 1) == 0 and 1 or -1))
		local alt = rng:NextNumber(ALT_MIN, ALT_MAX)
		local centre = Vector3.new(origin.X, alt, origin.Z) + offset
		local start = centre - dir * (CROSS / 2)
		local clear = true
		for _, s in ipairs({ 0, -22, 22 }) do
			if Workspace:Raycast(start + side * s, dir * CROSS, skyParams) then clear = false; break end
		end
		if clear then return dir, side, start end
	end
	return nil
end

local function spawnFlock(origin)
	local dir, side, start = pickLine(origin)
	if not dir then return nil end

	local model = Instance.new("Model")
	model.Name = "Skein"
	model.Parent = folder

	local n = rng:NextInteger(FLOCK_MIN, FLOCK_MAX)
	local birds = {}
	for i = 1, n do
		local b = makeBird(model)
		-- V formation: alternate sides, each rank further back and wider out
		local rank = math.floor((i - 1) / 2) + ((i == 1) and 0 or 1)
		local sgn = (i % 2 == 0) and 1 or -1
		b.slot = (i == 1) and Vector3.zero
			or (side * (sgn * rank * rng:NextNumber(3.2, 4.6)) - dir * (rank * rng:NextNumber(3.6, 5.2)))
		birds[#birds+1] = b
	end

	return {
		model = model, birds = birds, dir = dir, start = start,
		speed = rng:NextNumber(SPEED_MIN, SPEED_MAX),
		t = 0,
		life = CROSS / rng:NextNumber(SPEED_MIN, SPEED_MAX),
	}
end

local function clearFlock()
	if active then
		active.model:Destroy()
		active = nil
	end
end

RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not inTundra(hrp.Position) then
		clearFlock()
		nextAt = os.clock() + rng:NextNumber(4, 10)   -- a beat after arriving, not instantly
		return
	end

	if not active then
		if os.clock() >= nextAt then
			active = spawnFlock(hrp.Position)
			-- no clear line this time: try again shortly, not every frame
			if not active then nextAt = os.clock() + rng:NextNumber(4, 8) end
		end
		return
	end

	active.t += dt
	local travelled = active.speed * active.t
	if travelled > CROSS then
		clearFlock()
		nextAt = os.clock() + rng:NextNumber(GAP_MIN, GAP_MAX)
		return
	end

	local lead = active.start + active.dir * travelled
	local t = os.clock()
	for _, b in ipairs(active.birds) do
		local pos = lead + b.slot + Vector3.new(0, math.sin(t * b.bobHz + b.phase) * b.bob, 0)
		-- bank very slightly, so the flock is not a rigid grid sliding across the sky
		local roll = math.sin(t * b.bobHz * 0.7 + b.phase) * 0.12
		local cf = CFrame.lookAt(pos, pos + active.dir) * CFrame.Angles(0, 0, roll)
		b.body.CFrame = cf
		-- wings beat in opposition around the body's long axis
		local beat = math.sin(t * b.flap + b.phase) * 0.85
		b.l.CFrame = cf * CFrame.new(-1.5, 0.05, 0) * CFrame.Angles(0, 0, beat)
		b.r.CFrame = cf * CFrame.new(1.5, 0.05, 0) * CFrame.Angles(0, 0, -beat)
	end
end)

player.CharacterRemoving:Connect(clearFlock)
