-- Valley ambience: drifting leaves, sun motes, and shafts that know it is night.
--
-- CLIENT-SIDE BY DESIGN. None of this is gameplay, nobody needs to agree on where a
-- leaf is, and replicating ~55 moving parts from the server for every player would be
-- pure waste. Everything here is local and costs the server nothing.
--
-- Leaves are a RECYCLED POOL, not spawn-and-destroy. 55 parts are created once and
-- reused forever; creating and destroying parts at this rate is what makes weather
-- effects tank framerate.
--
-- Only sparkles_main and smoke_main resolve as particle textures in this place, so the
-- motes use sparkles and the leaves are real (small, thin) parts instead of a particle
-- texture we do not have.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer

-- BoundsGuard's Valley region, so ambience stops at the same line the world does
local VMIN = Vector3.new(-325, -140, -460)
local VMAX = Vector3.new(330, 460, 1060)

local LEAVES = 55
local SPAWN_ABOVE = 46          -- canopy height above the player
local SPREAD = 90               -- how far around the player leaves appear

local LEAF_COLOURS = {
	Color3.fromRGB(96, 142, 62), Color3.fromRGB(132, 166, 70),
	Color3.fromRGB(206, 158, 66), Color3.fromRGB(180, 116, 54),
	Color3.fromRGB(150, 178, 84),
}

local folder = Instance.new("Folder")
folder.Name = "ValleyAmbienceFX"
folder.Parent = workspace

local rng = Random.new(os.clock() * 1000 % 100000)

local leaves = {}
local function makeLeaf()
	local p = Instance.new("Part")
	p.Name = "Leaf"
	p.Size = Vector3.new(rng:NextNumber(0.7, 1.15), 0.06, rng:NextNumber(0.45, 0.8))
	p.Color = LEAF_COLOURS[rng:NextInteger(1, #LEAF_COLOURS)]
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.CastShadow = false
	p.Parent = folder
	return { part = p, y = 0, speed = 0, phase = 0, amp = 0, spin = 0, x = 0, z = 0, floor = 0 }
end

local function reseed(leaf, centre)
	local a = rng:NextNumber(0, math.pi * 2)
	local r = rng:NextNumber(8, SPREAD)
	leaf.x = centre.X + math.cos(a) * r
	leaf.z = centre.Z + math.sin(a) * r
	leaf.y = centre.Y + SPAWN_ABOVE + rng:NextNumber(0, 24)
	leaf.speed = rng:NextNumber(3.5, 7.5)
	leaf.phase = rng:NextNumber(0, math.pi * 2)
	leaf.amp = rng:NextNumber(1.2, 3.4)
	leaf.spin = rng:NextNumber(-2.2, 2.2)
	-- one raycast per reseed, not per frame: find where this leaf should land
	local hit = workspace:Raycast(Vector3.new(leaf.x, leaf.y, leaf.z), Vector3.new(0, -500, 0))
	leaf.floor = hit and hit.Position.Y or (centre.Y - 20)
end

for i = 1, LEAVES do leaves[i] = makeLeaf() end

-- sun motes: a few emitters that ride along with the player, so specks always catch
-- the light near the camera without needing to cover the whole valley
local motes = {}
for i = 1, 3 do
	local host = Instance.new("Part")
	host.Name = "MoteHost"
	host.Size = Vector3.new(70, 1, 70)
	host.Transparency = 1
	host.Anchored, host.CanCollide, host.CanQuery, host.CanTouch = true, false, false, false
	host.Parent = folder
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(255, 240, 196))
	e.LightEmission = 0.9
	e.Lifetime = NumberRange.new(4, 9)
	e.Speed = NumberRange.new(0.4, 1.6)
	e.SpreadAngle = Vector2.new(80, 80)
	e.Acceleration = Vector3.new(0.6, -0.5, 0.3)
	e.Drag = 1.5
	e.Rate = 9
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.28),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.45),
		NumberSequenceKeypoint.new(0.8, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Parent = host
	motes[i] = { host = host, emitter = e, offset = Vector3.new(0, 12 + i * 9, 0) }
end

-- Fireflies: the night counterpart to the sun motes. Same trick -- emitters that ride
-- with the player -- but low to the ground, slower, and gated on darkness instead of
-- daylight, so dusk hands over from one to the other rather than having both or neither.
local flies = {}
for i = 1, 3 do
	local host = Instance.new("Part")
	host.Name = "FireflyHost"
	host.Size = Vector3.new(64, 1, 64)
	host.Transparency = 1
	host.Anchored, host.CanCollide, host.CanQuery, host.CanTouch = true, false, false, false
	host.Parent = folder
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(214, 255, 150)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 230, 96)),
	})
	e.LightEmission = 1
	e.Lifetime = NumberRange.new(3.5, 7)
	e.Speed = NumberRange.new(0.6, 2.2)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, 0.4, 0)
	e.Drag = 2.5
	e.Rate = 0
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.25, 0.34),
		NumberSequenceKeypoint.new(0.75, 0.30),
		NumberSequenceKeypoint.new(1, 0),
	})
	-- blink rather than glide: fireflies read wrong as steady dots
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.18, 0.15),
		NumberSequenceKeypoint.new(0.36, 0.85),
		NumberSequenceKeypoint.new(0.55, 0.1),
		NumberSequenceKeypoint.new(0.78, 0.8),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Parent = host
	flies[i] = { host = host, emitter = e, offset = Vector3.new(0, 1.5 + i * 2.5, 0) }
end

local shafts = workspace:FindFirstChild("GameWorld")
shafts = shafts and shafts:FindFirstChild("LightShafts")
local shaftBase = {}
if shafts then
	for _, d in ipairs(shafts:GetChildren()) do
		if d:IsA("BasePart") then shaftBase[d] = d.Transparency end
	end
end

local function inValley(p)
	return p.X >= VMIN.X and p.X <= VMAX.X and p.Y >= VMIN.Y and p.Y <= VMAX.Y
		and p.Z >= VMIN.Z and p.Z <= VMAX.Z
end

-- Night bed. 2D rather than positional: it is the sound of the whole valley being
-- dark, not a sound coming from somewhere. Rises as Daylight falls, so it arrives with
-- the sunset instead of switching on at a threshold.
local SoundKit = require(game:GetService("ReplicatedStorage").Modules.SoundKit)
local nightBed = Instance.new("Sound")
nightBed.Name = "NightBed"
nightBed.SoundId = SoundKit.Ids.ambienceNight or ""
nightBed.Looped = true
nightBed.Volume = 0
nightBed.Parent = game:GetService("SoundService")
if nightBed.SoundId ~= "" then nightBed:Play() end

local active = true
local shaftTimer = 0

RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local here = root.Position
	local want = inValley(here)

	if want ~= active then
		active = want
		folder.Parent = active and workspace or nil
		for _, m in ipairs(motes) do m.emitter.Enabled = active end
		for _, f in ipairs(flies) do f.emitter.Enabled = active end
		if not active then return end
	end
	if not active then return end

	-- Sun motes and shafts only make sense while the sun is up. DayNightCycle publishes
	-- Daylight so both fade out together rather than glowing through the night.
	local daylight = Lighting:GetAttribute("Daylight")
	if type(daylight) ~= "number" then daylight = 1 end

	shaftTimer += dt
	if shaftTimer > 0.5 then          -- 2Hz is plenty for a slow fade over 84 parts
		shaftTimer = 0
		for part, base in pairs(shaftBase) do
			if part.Parent then
				part.Transparency = 1 - (1 - base) * daylight
			end
		end
		for _, m in ipairs(motes) do
			m.emitter.Rate = 9 * daylight
		end
		-- crickets and still air, loudest at midnight
		nightBed.Volume = 0.16 * (1 - daylight)
		local night = 1 - daylight
		for _, f in ipairs(flies) do
			f.emitter.Rate = 7 * night
		end
	end

	local t = os.clock()
	for _, leaf in ipairs(leaves) do
		if leaf.y <= leaf.floor then reseed(leaf, here) end
		leaf.y -= leaf.speed * dt
		local sway = math.sin(t * 1.4 + leaf.phase) * leaf.amp
		local drift = math.cos(t * 0.9 + leaf.phase) * leaf.amp * 0.6
		leaf.part.CFrame = CFrame.new(leaf.x + sway, leaf.y, leaf.z + drift)
			* CFrame.Angles(t * leaf.spin, t * leaf.spin * 0.7, t * leaf.spin * 0.4)
	end

	for i, m in ipairs(motes) do
		m.host.CFrame = CFrame.new(here + m.offset)
	end
	for _, f in ipairs(flies) do
		f.host.CFrame = CFrame.new(here + f.offset)
	end
end)

-- seed them spread through their fall so they do not all arrive as one curtain
task.defer(function()
	local char = player.Character or player.CharacterAdded:Wait()
	local root = char:WaitForChild("HumanoidRootPart")
	for i, leaf in ipairs(leaves) do
		reseed(leaf, root.Position)
		leaf.y = leaf.floor + (i / LEAVES) * SPAWN_ABOVE
	end
end)
