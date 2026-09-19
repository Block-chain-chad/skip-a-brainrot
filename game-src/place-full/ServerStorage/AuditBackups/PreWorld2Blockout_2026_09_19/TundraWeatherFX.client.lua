-- Frozen Tundra weather: falling snow and wind-driven ground drift.
--
-- OPTIMISATION, which is the whole point of this file. The old rig was 27 static emitters
-- spread across the map at a combined 702 particles/sec. Every one of them simulated
-- whether a player was near it or not, and it STILL left gaps, because covering a
-- 900-stud map with fixed emitters means either huge waste or holes.
--
-- Emitters that follow the camera cover the map by definition and only ever simulate what
-- can be seen. ~100/sec beats 702/sec and looks denser, because all of it is in frame.
--
-- Client-side: snow is not gameplay, nobody has to agree where a flake is, and replicating
-- it from the server would multiply the cost by the player count for no benefit.
--
-- Everything switches off outside the Tundra region, so World 1 pays nothing at all.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

-- matches BoundsGuard's Tundra region
local TMIN = Vector3.new(-8600, 1850, -8600)
local TMAX = Vector3.new(-7400, 2250, -7400)

local folder = Instance.new("Folder")
folder.Name = "TundraWeatherFX"
folder.Parent = workspace

local function host(name, size, offset)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Transparency = 1
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Parent = folder
	return { part = p, offset = offset }
end

-- ---- falling snow: three layers at different heights so it has depth ----
local FALL = {}
for i = 1, 3 do
	local h = host("SnowHost" .. i, Vector3.new(150, 1, 150), Vector3.new(0, 34 + i * 16, 0))
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARK
	e.Color = ColorSequence.new(Color3.fromRGB(235, 243, 255))
	e.LightEmission = 0.25
	e.Lifetime = NumberRange.new(5, 8)
	e.Rate = 22
	e.Speed = NumberRange.new(2, 5)
	e.EmissionDirection = Enum.NormalId.Bottom
	-- a steady slant, so the snow and the ground drift agree about the wind
	e.Acceleration = Vector3.new(5, -9, 2)
	e.Drag = 1.6
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-45, 45)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.42),
		NumberSequenceKeypoint.new(1, 0.55),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.1, 0.25),
		NumberSequenceKeypoint.new(0.85, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Parent = h.part
	h.emitter = e
	FALL[i] = h
end

-- ---- ground drift: low, fast, horizontal. This is what sells "wind" ----
local DRIFT = {}
for i = 1, 2 do
	local h = host("DriftHost" .. i, Vector3.new(120, 1, 120), Vector3.new(0, 1.2 + i * 1.6, 0))
	local e = Instance.new("ParticleEmitter")
	e.Texture = SMOKE
	e.Color = ColorSequence.new(Color3.fromRGB(226, 236, 250))
	e.LightEmission = 0.1
	e.Lifetime = NumberRange.new(1.6, 3.2)
	e.Rate = 16
	e.Speed = NumberRange.new(14, 26)
	e.SpreadAngle = Vector2.new(9, 9)
	-- almost flat: ground drift travels, it does not fall
	e.Acceleration = Vector3.new(16, 0.6, 6)
	e.Drag = 2.2
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.4),
		NumberSequenceKeypoint.new(0.4, 5),
		NumberSequenceKeypoint.new(1, 7),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.72),
		NumberSequenceKeypoint.new(0.75, 0.82),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Parent = h.part
	h.emitter = e
	DRIFT[i] = h
end

-- ---- frozen breath ----
-- Parented to the head rather than a following host, because it has to move with the
-- player's actual head, not their root. Puffs rather than a stream: emitted on a timer
-- so it reads as breathing.
local breath
local function ensureBreath(char)
	local head = char and char:FindFirstChild("Head")
	if not head then return nil end
	if breath and breath.Parent == head then return breath end
	local a2 = Instance.new("Attachment")
	a2.Name = "BreathAt"
	a2.Position = Vector3.new(0, -0.1, -0.7)
	a2.Parent = head
	local e = Instance.new("ParticleEmitter")
	e.Texture = SMOKE
	e.Color = ColorSequence.new(Color3.fromRGB(228, 238, 250))
	e.LightEmission = 0.2
	e.Lifetime = NumberRange.new(0.9, 1.5)
	e.Speed = NumberRange.new(2.5, 4)
	e.SpreadAngle = Vector2.new(14, 14)
	e.Acceleration = Vector3.new(0, 1.2, 0)
	e.Drag = 3.5
	e.Rate = 0                        -- puffed manually, never streamed
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1.9),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0.68),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Parent = a2
	breath = e
	return e
end

local ALL = {}
for _, h in ipairs(FALL) do table.insert(ALL, h) end
for _, h in ipairs(DRIFT) do table.insert(ALL, h) end

local function inTundra(p)
	return p.X >= TMIN.X and p.X <= TMAX.X and p.Y >= TMIN.Y and p.Y <= TMAX.Y
		and p.Z >= TMIN.Z and p.Z <= TMAX.Z
end

local active = false
local breathClock = 0
local function setActive(on)
	if on == active then return end
	active = on
	for _, h in ipairs(ALL) do h.emitter.Enabled = on end
end
setActive(false)

RunService.RenderStepped:Connect(function()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then setActive(false); return end
	local here = root.Position
	setActive(inTundra(here))
	if not active then return end
	breathClock += 1
	if breathClock >= 150 then         -- roughly every 2.5s at 60fps
		breathClock = 0
		local e = ensureBreath(char)
		if e then e:Emit(3) end
	end

	for _, h in ipairs(ALL) do
		h.part.CFrame = CFrame.new(here + h.offset)
	end
end)
