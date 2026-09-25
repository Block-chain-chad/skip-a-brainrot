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
local TMAX = Vector3.new(-7400, 2250, -6700)   -- the lake runs to z -6870 (fixed 2026-09-19)

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

-- UNDER A ROOF (ITEM 10): the hosts ride 50-82 studs above the player and particles do not
-- collide, so snow fell straight through the Warmhouse roof onto the hearth. One upward ray every
-- 0.25 s; with anything solid overhead (the Warmhouse, the Cellar Pass bore) the fall and the
-- ground drift switch off and the flakes already in the air are cleared.
local ROOF_CHECK, ROOF_REACH = 0.25, 60
local roofParams = RaycastParams.new()
roofParams.FilterType = Enum.RaycastFilterType.Exclude
roofParams.IgnoreWater = true
local roofClock, covered = 0, false

local active = false
local breathClock = 0
local function setActive(on)
	if on == active then return end
	active = on
	for _, h in ipairs(ALL) do h.emitter.Enabled = on and not covered end
end
setActive(false)

local function setCovered(on)
	if on == covered then return end
	covered = on
	for _, h in ipairs(ALL) do
		h.emitter.Enabled = active and not on
		if on then h.emitter:Clear() end
	end
end

-- ===== WEATHER EVENTS IN THE TUNDRA (ITEM 11b) =====
-- The weather kits are WeatherClient's and run in every world. Two things they cannot do here,
-- so this script does them, inside the Tundra only:
--   * STORM SNOW: during Blizzard and Sandstorm the Tundra's own fall and ground drift run at
--     storm strength. A Tundra sandstorm reads as spindrift: little new snow falling, a lot of
--     driven ground snow.
--   * CENTREPIECES: the valley builds its aurora ribbons and its blood moon at valley
--     coordinates, 11,000 studs from here. These are Tundra ones (aurora curtains; the valley's
--     Neon disc in a glow shell), built only while that event runs and the player is in the
--     Tundra, faded in and out, and removed when either stops. Client-side: 0 world parts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local STORM = {
	Blizzard  = { fall = 5,   fallSpeed = 2.4, wind = Vector3.new(30, -16, 10), drift = 3, driftSpeed = 1.6 },
	Sandstorm = { fall = 1.5, fallSpeed = 1.8, wind = Vector3.new(40, -6, 14),  drift = 5, driftSpeed = 2.2 },
}
local base = {}   -- [emitter] = its calm values, to put back when the storm ends
for _, h in ipairs(ALL) do
	base[h.emitter] = { Rate = h.emitter.Rate, Speed = h.emitter.Speed, Acceleration = h.emitter.Acceleration }
end
local stormNow = nil
local function setStorm(name)
	if name == stormNow then return end
	stormNow = name
	local s = name and STORM[name]
	for _, h in ipairs(FALL) do
		local b = base[h.emitter]
		h.emitter.Rate = b.Rate * (s and s.fall or 1)
		h.emitter.Speed = s and NumberRange.new(b.Speed.Min * s.fallSpeed, b.Speed.Max * s.fallSpeed) or b.Speed
		h.emitter.Acceleration = s and s.wind or b.Acceleration
	end
	for _, h in ipairs(DRIFT) do
		local b = base[h.emitter]
		h.emitter.Rate = b.Rate * (s and s.drift or 1)
		h.emitter.Speed = s and NumberRange.new(b.Speed.Min * s.driftSpeed, b.Speed.Max * s.driftSpeed) or b.Speed
	end
end

-- THE AURORA: two curtains of light flanking the Sundered Peak. Placed by shot. The peak fills
-- the sky ahead to ~35 degrees from the dock (28 from the hub) and the canyon walls hide the
-- sides below ~20, so the curtains hang over the drop beyond each wall and run up the valley
-- toward the peak, where the eye already goes. Each is a row of vertical rays, one Beam per ray,
-- bright at the foot and fading upward, irregularly spaced and sized, with a slow wave of
-- brightness running along the row. The colours are fixed: WeatherClient's hue cycle on the
-- screen tint (WeatherCC) walks them through the valley's four hues along with everything else.
-- NOT THE VALLEY'S RIBBONS: measured in the Tundra, a distant beam is drawn with fewer segments
-- than it was given, so a transparency profile that is 1 at both ends collapses to 1 all the way
-- along and the ribbon vanishes (the valley's smoke texture never showed at range either). Rays
-- here carry 64 segments and a foot of 0.92: visible out past 1,200 studs.
local CURTAINS = {
	-- left of the peak from the dock: the long, tall one
	{ seed = 7, height = 470, gain = 2.0, hills = 3.2, path = {
		Vector3.new(-7110, 2440, -8650), Vector3.new(-7060, 2450, -8100), Vector3.new(-7150, 2465, -7550),
		Vector3.new(-7070, 2480, -7000), Vector3.new(-7170, 2500, -6450), Vector3.new(-7110, 2520, -5950) } },
	-- right of it: shorter and fainter, so the pair is not a mirror image
	{ seed = 19, height = 360, gain = 1.6, hills = 4.1, path = {
		Vector3.new(-8870, 2430, -8400), Vector3.new(-8930, 2445, -7900), Vector3.new(-8850, 2460, -7400),
		Vector3.new(-8920, 2475, -6900), Vector3.new(-8860, 2490, -6400) } },
}
local RAY_GAP, RAY_WIDTH = { 20, 50 }, { 40, 125 }   -- studs, each ray picks in the range
local RAY_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.92), NumberSequenceKeypoint.new(0.03, 0.36),
	NumberSequenceKeypoint.new(0.12, 0.42), NumberSequenceKeypoint.new(0.45, 0.76),
	NumberSequenceKeypoint.new(1, 1),
})
local RAY_COLOUR = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(165, 255, 205)),
	ColorSequenceKeypoint.new(0.45, Color3.fromRGB(105, 235, 200)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 130, 255)),
})
-- THE BLOOD MOON: the valley's is 650 studs across at ~2,800, about 13 degrees of sky. Same size
-- here, low over the drop beyond the right-hand wall, clear of the peak from the hub, dock and ice.
local MOON_AT, MOON_SIZE = Vector3.new(-9100, 2813, -5895), 513
local FX_FADE = 4            -- seconds for a centrepiece to fade in or out
local fxFolder, fxKind, fxRibbons, fxDisc, fxGlow = nil, nil, {}, nil, nil
local fxClock, fxLevel, fxTick = 0, 0, 0
local function clearFx()
	if fxFolder then fxFolder:Destroy() end
	fxFolder, fxKind, fxRibbons, fxDisc, fxGlow = nil, nil, {}, nil, nil
	fxLevel = 0
end
local function fxPart(name, size, cf)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Parent = fxFolder
	return p
end
local function catmull(p0, p1, p2, p3, t)
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3)
end
-- where the rays stand: along a smooth curve through the path, one every RAY_GAP studs
local function rayFeet(path, rng)
	local line = {}
	for i = 1, #path - 1 do
		local p0, p1, p2, p3 = path[math.max(i - 1, 1)], path[i], path[i + 1], path[math.min(i + 2, #path)]
		for k = 0, 47 do table.insert(line, catmull(p0, p1, p2, p3, k / 48)) end
	end
	table.insert(line, path[#path])
	local feet, need, run = { line[1] }, rng:NextNumber(RAY_GAP[1], RAY_GAP[2]), 0
	for i = 2, #line do
		local a, b = line[i - 1], line[i]
		local len, pos = (b - a).Magnitude, 0
		while run + (len - pos) >= need do
			pos += need - run
			table.insert(feet, a:Lerp(b, pos / len))
			run, need = 0, rng:NextNumber(RAY_GAP[1], RAY_GAP[2])
		end
		run += len - pos
	end
	return feet
end
local function smoothstep(e0, e1, x)
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end
local function buildAurora()
	for _, c in ipairs(CURTAINS) do
		local rng = Random.new(c.seed)
		local host = fxPart("TundraAuroraCurtain", Vector3.new(0.2, 0.2, 0.2), CFrame.new(c.path[1]))
		host.Transparency = 1
		local feet = rayFeet(c.path, rng)
		for i, foot in ipairs(feet) do
			local u = (i - 1) / math.max(#feet - 1, 1)
			local taper = smoothstep(0, 0.12, u) * smoothstep(1, 0.88, u)   -- thins out at both ends
			local hills = math.noise(u * c.hills, c.seed * 0.37, 0.5) + 0.5  -- the top edge rises and falls
			local h = c.height * (0.5 + 0.8 * hills) * (0.4 + 0.6 * taper) * rng:NextNumber(0.8, 1.2)
			local base = foot + Vector3.new(0, math.noise(u * 11, 3.3, c.seed) * 16, 0)
			local a0 = Instance.new("Attachment")
			a0.Parent = host
			a0.WorldPosition = base
			local a1 = Instance.new("Attachment")
			a1.Parent = host
			a1.WorldPosition = base + Vector3.new(0, h, 0)
			local b = Instance.new("Beam")
			b.Attachment0, b.Attachment1 = a0, a1
			local w = RAY_WIDTH[1] + (RAY_WIDTH[2] - RAY_WIDTH[1]) * rng:NextNumber() ^ 1.6
			b.Width0, b.Width1 = w, w * rng:NextNumber(0.25, 0.8)
			b.LightEmission, b.LightInfluence = 1, 0
			b.FaceCamera = true
			b.Segments = 64
			b.Transparency = RAY_FADE
			b.Color = RAY_COLOUR
			b.Brightness = 0
			b.Parent = host
			-- each ray's own strength: the curtain's, thinned at its ends, varied ray to ray and in
			-- broad patches along the row
			local gain = c.gain * (0.3 + 0.7 * taper) * (0.45 + 0.8 * rng:NextNumber())
				* (0.6 + 0.6 * (math.noise(u * 4, c.seed, 2.2) + 0.5))
			table.insert(fxRibbons, { beam = b, u = u, gain = gain })
		end
	end
end
local function buildMoon()
	local disc = fxPart("TundraBloodMoon", Vector3.new(MOON_SIZE, MOON_SIZE, MOON_SIZE), CFrame.new(MOON_AT))
	disc.Shape = Enum.PartType.Ball
	disc.Material = Enum.Material.Neon
	disc.Color = Color3.fromRGB(196, 30, 26)
	disc.Transparency = 1
	-- the valley's glow shell, at the valley's proportion (880 around 650)
	local glow = disc:Clone()
	glow.Name = "TundraBloodMoonGlow"
	glow.Size = Vector3.new(MOON_SIZE, MOON_SIZE, MOON_SIZE) * (880 / 650)
	glow.Color = Color3.fromRGB(150, 16, 14)
	glow.Parent = fxFolder
	fxDisc, fxGlow = disc, glow
end
local function updateFx(dt, wanted)
	if wanted ~= fxKind then
		if fxKind and fxLevel > 0 then
			-- fade the old one out before it goes
			fxLevel = math.max(fxLevel - dt / FX_FADE, 0)
		else
			clearFx()
			if wanted then
				fxFolder = Instance.new("Folder")
				fxFolder.Name = "TundraSkyFX"
				fxFolder.Parent = workspace
				fxKind, fxClock, fxTick = wanted, 0, 1
				if wanted == "Aurora" then buildAurora() else buildMoon() end
			end
		end
	elseif fxKind then
		fxLevel = math.min(fxLevel + dt / FX_FADE, 1)
	end
	if not fxKind then return end
	fxClock += dt
	if fxKind == "Aurora" then
		-- 15 Hz is plenty for a wave this slow, and it keeps ~120 beams off the per-frame bill
		fxTick += dt
		if fxTick < 1 / 15 then return end
		fxTick = 0
		for _, r in ipairs(fxRibbons) do
			local wave = 0.5 + 0.5 * math.sin(r.u * 17 - fxClock * 0.8)   -- runs along the row
			local swell = math.sin(r.u * 6 + fxClock * 0.3)               -- slower, the other way
			r.beam.Brightness = r.gain * fxLevel * (0.6 + 0.4 * wave + 0.15 * swell)
		end
	elseif fxGlow then
		-- a slow breath in the glow shell, in step with the valley's 3.8 s red pulse
		local glow = 0.62 + 0.08 * math.sin(fxClock * (2 * math.pi / 3.8))
		fxGlow.Transparency = 1 - (1 - glow) * fxLevel
		fxDisc.Transparency = 1 - fxLevel
	end
end

RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then setActive(false); setStorm(nil); updateFx(dt, nil); return end
	local here = root.Position
	setActive(inTundra(here))
	if not active then setStorm(nil); updateFx(dt, nil); return end
	local weather = ReplicatedStorage:GetAttribute("WeatherName")
	setStorm(STORM[weather] and weather or nil)
	updateFx(dt, (weather == "Aurora" or weather == "Blood Moon") and weather or nil)
	roofClock += dt
	if roofClock >= ROOF_CHECK then
		roofClock = 0
		roofParams.FilterDescendantsInstances = { char, folder }
		setCovered(workspace:Raycast(here, Vector3.new(0, ROOF_REACH, 0), roofParams) ~= nil)
	end
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
