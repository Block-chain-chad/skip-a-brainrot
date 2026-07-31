-- WeatherClient: event banner + countdown + a full ambient visual kit per event.
-- Every event restyles the whole sky (time of day, atmosphere, bloom, sun rays)
-- so an active event is obvious from the world alone, not just the banner.
-- All of this is client-local: Lighting edits here never touch the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

-- Forward declarations: restoreVisuals is defined ABOVE all the per-event VFX sections but
-- has to tear each of them down. Without these, every call in restoreVisuals resolves to a
-- nil GLOBAL and errors the moment weather returns to Clear.
local clearAurora, clearBloodMoon, clearHalos

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local function new(cls, props, parent)
	local o = Instance.new(cls)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

-- client-local sky tint
local cc = new("ColorCorrectionEffect", { Name = "WeatherCC", TintColor = Color3.new(1, 1, 1), Saturation = 0, Brightness = 0 }, Lighting)

local gui = new("ScreenGui", { Name = "WeatherUI", ResetOnSpawn = false, DisplayOrder = 8 }, player:WaitForChild("PlayerGui"))
local banner = new("Frame", {
	Name = "WeatherBanner", Visible = false, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 72),
	Size = UDim2.new(0, 420, 0, 44), BackgroundColor3 = Color3.fromRGB(20, 24, 34), BackgroundTransparency = 0.1,
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 10) }, banner)
local bStroke = new("UIStroke", { Color = Color3.fromRGB(120, 200, 255), Thickness = 2 }, banner)
local title = new("TextLabel", { Position = UDim2.new(0, 14, 0, 5), Size = UDim2.new(1, -28, 0, 20), BackgroundTransparency = 1, Text = "", Font = Enum.Font.GothamBlack, TextSize = 16, TextColor3 = Color3.fromRGB(255, 255, 255), TextXAlignment = Enum.TextXAlignment.Left }, banner)
local sub = new("TextLabel", { Position = UDim2.new(0, 14, 0, 24), Size = UDim2.new(1, -28, 0, 16), BackgroundTransparency = 1, Text = "", Font = Enum.Font.GothamMedium, TextSize = 12.5, TextColor3 = Color3.fromRGB(170, 220, 255), TextXAlignment = Enum.TextXAlignment.Left }, banner)
local timeLbl = new("TextLabel", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.new(0, 60, 0, 26), BackgroundTransparency = 1, Text = "", Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = Color3.fromRGB(255, 220, 120) }, banner)

-- ===== ambient visual kits =====
local sky   = Lighting:FindFirstChildOfClass("Sky")
local atmo  = Lighting:FindFirstChildOfClass("Atmosphere")
local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
local rays  = Lighting:FindFirstChildOfClass("SunRaysEffect")

-- snapshot the untouched look so Clear can put everything back exactly
local BASE = {
	Light = {
		ClockTime = Lighting.ClockTime, Brightness = Lighting.Brightness,
		ExposureCompensation = Lighting.ExposureCompensation,
		Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
		FogColor = Lighting.FogColor, FogEnd = Lighting.FogEnd,
	},
	Atmo = atmo and { Density = atmo.Density, Haze = atmo.Haze, Glare = atmo.Glare,
	                  Color = atmo.Color, Decay = atmo.Decay } or nil,
	Bloom = bloom and { Intensity = bloom.Intensity, Size = bloom.Size, Threshold = bloom.Threshold } or nil,
	Rays  = rays and { Intensity = rays.Intensity, Spread = rays.Spread } or nil,
	MoonSize = sky and sky.MoonAngularSize or nil,
}

local function tw(obj, props, t)
	if not obj then return end
	TweenService:Create(obj, TweenInfo.new(t or 2.0, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), props):Play()
end

local C = Color3.fromRGB

-- Sound assets, declared ahead of KITS because the kits reference them by name.
-- All ProSoundEffects (Roblox first-party), so playback rights hold in the live
-- game. They parent to SoundService, which makes them 2D/global rather than
-- positional -- ambience should not fall off as the player walks around.
local AUDIO = {
	Rain    = "rbxassetid://9112853286",  -- Rain Heavy 2, 48.8s loop
	Thunder = "rbxassetid://9113169432",  -- deep distant booms, 6.8s one-shot
	Wind    = "rbxassetid://9113286969",  -- Barstow wind, low howl, 37s loop
	Drone   = "rbxassetid://9119807233",  -- falling-pitch synth drone, 49.2s loop
	Airy    = "rbxassetid://9125742262",  -- airy whooshing swells, 33.2s loop
}

-- Each kit is a full look. Night events tween ClockTime up through 24 rather than
-- down through 0 so the transition reads as a sunset instead of a rewind.
local KITS = {
	["Fog"] = {
		light = { ClockTime = 11.2, Brightness = 1.45, ExposureCompensation = 0.05,
		          Ambient = C(120, 126, 132), OutdoorAmbient = C(168, 174, 180),
		          FogColor = C(203, 210, 218), FogEnd = 430 },
		atmo  = { Density = 0.55, Haze = 4.6, Glare = 0.05, Color = C(206, 213, 221), Decay = C(188, 198, 210) },
		bloom = { Intensity = 0.45, Size = 20, Threshold = 1.1 },
		rays  = { Intensity = 0.02, Spread = 0.4 },
		cc    = { TintColor = C(216, 223, 231), Saturation = -0.45, Contrast = -0.10, Brightness = 0.01 },
		moon  = nil,
		-- barely-there muffled air; fog is near-silent, so this stays under everything
		sounds = { { Id = AUDIO.Wind, Volume = 0.08, Speed = 0.55 } },
	},
	["Thunderstorm"] = {
		light = { ClockTime = 15.0, Brightness = 0.85, ExposureCompensation = -0.10,
		          Ambient = C(48, 54, 70), OutdoorAmbient = C(72, 80, 98),
		          FogColor = C(84, 94, 116), FogEnd = 900 },
		atmo  = { Density = 0.42, Haze = 2.7, Glare = 0.0, Color = C(118, 130, 155), Decay = C(70, 80, 104) },
		bloom = { Intensity = 0.7, Size = 24, Threshold = 1.0 },
		rays  = { Intensity = 0.0, Spread = 0.2 },
		cc    = { TintColor = C(150, 170, 212), Saturation = -0.30, Contrast = 0.14, Brightness = -0.04 },
		loop  = "lightning",
		sounds = { { Id = AUDIO.Rain, Volume = 0.28 } },   -- thunder cracks fire from the lightning loop
		particles = {
			Span = 46, Height = 26, Ahead = 30,
			Emitter = {
				Rate = 1800, Lifetime = NumberRange.new(0.8, 1.1), Speed = NumberRange.new(48, 62),
				EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(6, 6),
				Acceleration = Vector3.new(-5, -95, 0), Drag = 0,
				Size = NumberSequence.new(1.0),
				Squash = NumberSequence.new(8),          -- stretch the blob into a raindrop streak
				Color = ColorSequence.new(C(205, 226, 255)),
				Transparency = NumberSequence.new(0.1),
				LightEmission = 0.6, LockedToPart = false, Rotation = NumberRange.new(0, 0),
			},
		},
	},
	["Aurora"] = {
		-- same moonlight lift as Shooting Star, but keeping the green cast: the aurora itself
		-- is the feature, so this only raises the floor enough to make the map readable.
		light = { ClockTime = 23.6, Brightness = 1.35, ExposureCompensation = 0.18,
		          Ambient = C(58, 86, 96), OutdoorAmbient = C(92, 128, 142),
		          -- 1400 clipped the aurora ribbons, which sit at z 1568-2169. Raised so they
		          -- render at full strength instead of fading into fog.
		          FogColor = C(30, 60, 70), FogEnd = 2600 },
		moon  = 16,
		atmo  = { Density = 0.34, Haze = 1.7, Glare = 0.7, Color = C(92, 196, 172), Decay = C(58, 120, 200) },
		bloom = { Intensity = 1.7, Size = 42, Threshold = 0.68 },
		rays  = { Intensity = 0.05, Spread = 1.0 },
		cc    = { TintColor = C(140, 255, 210), Saturation = 0.50, Contrast = 0.10, Brightness = 0.02 },
		loop  = "aurora",
		sounds = { { Id = AUDIO.Airy, Volume = 0.13, Speed = 0.8 } },   -- ethereal shimmer
	},
	["Blood Moon"] = {
		light = { ClockTime = 23.9, Brightness = 1.15, ExposureCompensation = 0.10,
		          Ambient = C(72, 18, 18), OutdoorAmbient = C(98, 26, 26),
		          -- FogEnd was 760, which hid the custom blood moon entirely: it sits ~2800
		          -- studs out, and Fog is a hard distance cull on real geometry. Roblox's own
		          -- skybox moon was immune because the sky is not fogged; a real part is not.
		          -- Atmosphere Density 0.46 + Haze 2.3 below still carry the heavy murk without
		          -- culling the moon, or the whole map, at 760 studs.
		          FogColor = C(88, 18, 18), FogEnd = 3200 },
		atmo  = { Density = 0.46, Haze = 2.3, Glare = 0.5, Color = C(152, 40, 40), Decay = C(120, 18, 18) },
		bloom = { Intensity = 1.5, Size = 34, Threshold = 0.75 },
		rays  = { Intensity = 0.04, Spread = 0.8 },
		cc    = { TintColor = C(255, 118, 108), Saturation = 0.28, Contrast = 0.20, Brightness = -0.02 },
		-- 0 hides Roblox's skybox moon. It is drawn as part of the sky, so it has no world
		-- position and nothing can be fired from it -- spawnBloodMoon builds a real one
		-- instead, and two moons in the sky would look broken.
		moon  = 0,
		loop  = "pulse",
		sounds = { { Id = AUDIO.Drone, Volume = 0.17, Speed = 0.85 } },   -- low ominous drone
	},
	["Golden Hour"] = {
		loop  = "halo",   -- gives every player a halo for the duration
		light = { ClockTime = 17.55, Brightness = 2.6, ExposureCompensation = 0.30,
		          Ambient = C(122, 92, 56), OutdoorAmbient = C(202, 152, 92),
		          FogColor = C(255, 196, 130), FogEnd = 2200 },
		atmo  = { Density = 0.30, Haze = 2.1, Glare = 1.0, Color = C(255, 206, 142), Decay = C(255, 158, 78) },
		bloom = { Intensity = 1.45, Size = 30, Threshold = 0.80 },
		rays  = { Intensity = 0.28, Spread = 1.0 },
		cc    = { TintColor = C(255, 214, 150), Saturation = 0.22, Contrast = 0.06, Brightness = 0.03 },
	},
	["Shooting Star"] = {
		-- MOONLIT, not pitch black. Roblox has exactly ONE directional light -- the sun/moon,
		-- placed by ClockTime -- so there is no second "moonlight" object to add. Moonlight IS
		-- Brightness (the moon's own directional contribution at this ClockTime) plus the
		-- Ambient/OutdoorAmbient fill, tinted blue-white. Raised from 0.95 / (26,30,52) /
		-- (40,46,78), which lit almost nothing and left the lake and mountains unreadable.
		-- A bigger moon is set below so the light has a visible source in frame.
		light = { ClockTime = 23.4, Brightness = 1.6, ExposureCompensation = 0.22,
		          Ambient = C(62, 74, 104), OutdoorAmbient = C(104, 118, 155),
		          FogColor = C(22, 30, 58), FogEnd = 2600 },
		moon  = 20,   -- a full moon to justify the light, without Blood Moon's swollen 34
		-- deliberately the CLEAREST sky of any event, so the streaks read sharply
		atmo  = { Density = 0.16, Haze = 0.4, Glare = 0.9, Color = C(120, 140, 210), Decay = C(30, 40, 90) },
		bloom = { Intensity = 1.9, Size = 26, Threshold = 0.62 },
		rays  = { Intensity = 0.03, Spread = 0.6 },
		cc    = { TintColor = C(186, 208, 255), Saturation = 0.14, Contrast = 0.18, Brightness = 0.01 },
		loop  = "meteors",
		-- no bed here: the per-meteor whooshes carry it, and silence sells "clear night"
	},
	["Sandstorm"] = {
		light = { ClockTime = 13.4, Brightness = 1.35, ExposureCompensation = 0.0,
		          Ambient = C(126, 92, 52), OutdoorAmbient = C(186, 140, 84),
		          FogColor = C(196, 146, 86), FogEnd = 340 },
		atmo  = { Density = 0.60, Haze = 5.2, Glare = 0.5, Color = C(214, 162, 96), Decay = C(176, 118, 56) },
		bloom = { Intensity = 0.7, Size = 22, Threshold = 0.95 },
		rays  = { Intensity = 0.08, Spread = 0.7 },
		cc    = { TintColor = C(236, 176, 104), Saturation = 0.18, Contrast = 0.10, Brightness = -0.01 },
		-- same wind asset as Blizzard, pitched down so it reads gritty, not icy
		sounds = { { Id = AUDIO.Wind, Volume = 0.26, Speed = 0.72 } },
		-- === GRANULAR SAND (low-poly) ===
		-- This used to be 900 five-stud soft blobs, which read as brown HAZE rather than
		-- sand -- and the haze was already being done for free by atmo.Haze 5.2 + FogEnd
		-- 340 above, so the emitter was paying ~1,400 live quads to duplicate it.
		--
		-- Now it emits small, tumbling GRAINS and lets the atmosphere carry the dust wall.
		-- Three things give the granular look, and all three are also what make it cheap:
		--   small + opaque  each grain is ~0.45 studs with an opaque core, so it reads as a
		--                   discrete speck rather than a wisp. NOTE: a hard-edged SQUARE
		--                   grain is NOT reachable with a built-in texture -- Texture = ""
		--                   renders nothing at all (tested), and of the built-in particle
		--                   textures only sparkles_main (star-shaped) and smoke_main (round)
		--                   resolve. smoke_main is the round one; at 0.45 studs its alpha
		--                   falloff is a pixel or two wide, so it still reads granular. For
		--                   true faceted squares you need an uploaded 8x8 white square --
		--                   swap Texture below and nothing else has to change.
		--   LightEmission 0 sand is not self-lit. Removing the glow also drops these out
		--                   of the additive pass. LightInfluence 1 lets scene light land
		--                   on them so they sit in the world instead of floating on top.
		--   Squash 0        no stretch. A compact grain + fast RotSpeed tumble is what sells
		--                   "grit", where a stretched streak sells "rain".
		--
		-- Budget: Rate 320 x ~1.2s mean life = ~385 live quads, down from ~1,440. Keep the
		-- product of Rate and Lifetime near this if you retune; that product IS the cost.
		-- Size/Color carry per-particle ENVELOPES (the 3rd keypoint arg) so grains vary
		-- individually -- that is free variety, where a second emitter would double cost.
		particles = {
			-- Height/Speed are a PAIR, and getting it wrong is the classic failure here: the
			-- plate emits downward, so a low plate plus a fast launch means every grain crosses
			-- camera height in a fraction of a second and spends the rest of its life below the
			-- view. Sand should rip ACROSS you, not drop past you -- so the plate sits high and
			-- the launch is SLOW, letting the +X Acceleration below build the sideways streak.
			-- Grains descend ~15 studs over their life, i.e. they linger at eye level.
			Span = 70, Height = 15, Ahead = 22,
			Emitter = {
				Texture = "rbxasset://textures/particles/smoke_main.dds",
				Rate = 320, Lifetime = NumberRange.new(0.9, 1.5), Speed = NumberRange.new(10, 22),
				EmissionDirection = Enum.NormalId.Bottom,
				SpreadAngle = Vector2.new(35, 35),        -- a directed sheet, not a cloud
				Acceleration = Vector3.new(70, -14, 24), -- driven sideways, but grains do fall
				Drag = 0.5,                              -- heavy: they lose speed, dust would not
				Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.45, 0.25),
					NumberSequenceKeypoint.new(1, 0.30, 0.18) }),
				Squash = NumberSequence.new(0),
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, C(226, 190, 132)),
					ColorSequenceKeypoint.new(0.5, C(198, 152, 96)),
					ColorSequenceKeypoint.new(1, C(214, 170, 112)) }),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.12, 0.08),
					NumberSequenceKeypoint.new(0.82, 0.18), NumberSequenceKeypoint.new(1, 1) }),
				LightEmission = 0, LightInfluence = 1, LockedToPart = false,
				Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-260, 260),    -- fast tumble = grit, not drift
			},
		},
	},
	["Blizzard"] = {
		light = { ClockTime = 10.4, Brightness = 1.9, ExposureCompensation = 0.24,
		          Ambient = C(150, 166, 186), OutdoorAmbient = C(196, 212, 232),
		          FogColor = C(226, 238, 252), FogEnd = 300 },
		atmo  = { Density = 0.58, Haze = 4.8, Glare = 0.2, Color = C(228, 240, 253), Decay = C(196, 214, 236) },
		bloom = { Intensity = 1.1, Size = 28, Threshold = 0.85 },
		rays  = { Intensity = 0.04, Spread = 0.5 },
		cc    = { TintColor = C(214, 232, 255), Saturation = -0.34, Contrast = -0.05, Brightness = 0.06 },
		sounds = { { Id = AUDIO.Wind, Volume = 0.34, Speed = 1.06 } },   -- higher, colder howl
		particles = {
			Span = 58, Height = 24, Ahead = 26,
			Emitter = {
				Rate = 1400, Lifetime = NumberRange.new(2.2, 3.2), Speed = NumberRange.new(10, 18),
				EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(40, 40),
				Acceleration = Vector3.new(-30, -12, 10),  -- wind-driven, not straight down
				Drag = 1.5,
				Size = NumberSequence.new(0.85),
				Color = ColorSequence.new(C(255, 255, 255)),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.15),
					NumberSequenceKeypoint.new(0.85, 0.2), NumberSequenceKeypoint.new(1, 1) }),
				LightEmission = 0.5, LockedToPart = false,
				Rotation = NumberRange.new(-180, 180), RotSpeed = NumberRange.new(-90, 90),
			},
		},
	},
}

-- ===== camera-tracked precipitation (rain / snow / dust) =====
-- One emitter on an invisible plate that rides above the camera, so weather
-- follows the player instead of being baked into one spot in the world.
local rigPart, rigConn

local function stopParticles()
	if rigConn then rigConn:Disconnect(); rigConn = nil end
	if rigPart then rigPart:Destroy(); rigPart = nil end
end

local function startParticles(spec)
	stopParticles()
	local p = Instance.new("Part")
	p.Name = "WeatherRig"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Transparency, p.CastShadow = 1, false
	p.Size = Vector3.new(spec.Span or 80, 1, spec.Span or 80)
	p.Parent = Workspace

	local e = Instance.new("ParticleEmitter")
	for k, v in pairs(spec.Emitter) do e[k] = v end
	e.Parent = p
	rigPart = p

	-- The plate must sit AHEAD of the camera, not just above it: parked directly
	-- overhead, everything it emits falls behind the view frustum and is invisible.
	local h, ahead = spec.Height or 26, spec.Ahead or 30
	rigConn = RunService.RenderStepped:Connect(function()
		local cam = Workspace.CurrentCamera
		if cam and rigPart and rigPart.Parent then
			local look = cam.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			flat = flat.Magnitude > 0.05 and flat.Unit or Vector3.new(0, 0, -1)
			rigPart.CFrame = CFrame.new(cam.CFrame.Position + flat * ahead + Vector3.new(0, h, 0))
		end
	end)
end

-- ===== event audio playback =====
local sndFolder = Workspace:FindFirstChild("__WeatherAudio")
if not sndFolder then
	sndFolder = Instance.new("Folder")
	sndFolder.Name = "WeatherAudio"
	sndFolder.Parent = SoundService
end

local activeLoops = {}

local function stopAudio()
	for _, s in ipairs(activeLoops) do
		if s and s.Parent then
			TweenService:Create(s, TweenInfo.new(1.4), { Volume = 0 }):Play()
			local snd = s
			task.delay(1.6, function()
				if snd and snd.Parent then snd:Stop(); snd:Destroy() end
			end)
		end
	end
	table.clear(activeLoops)
end

local function startAudio(list)
	stopAudio()
	for _, spec in ipairs(list or {}) do
		local s = Instance.new("Sound")
		s.SoundId = spec.Id
		s.Looped = true
		s.Volume = 0                      -- fade in, never snap on
		s.PlaybackSpeed = spec.Speed or 1
		s.Parent = sndFolder
		s:Play()
		TweenService:Create(s, TweenInfo.new(2.0), { Volume = spec.Volume }):Play()
		table.insert(activeLoops, s)
	end
end

-- fire-and-forget one-shot (thunder crack, meteor whoosh)
local function playOneShot(id, volume, speed, cutAfter)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = speed or 1
	s.Parent = sndFolder
	s:Play()
	if cutAfter then
		TweenService:Create(s, TweenInfo.new(0.35), { Volume = 0 }):Play()
		task.delay(cutAfter + 0.4, function() if s.Parent then s:Destroy() end end)
	else
		s.Ended:Once(function() if s.Parent then s:Destroy() end end)
		task.delay(12, function() if s.Parent then s:Destroy() end end)   -- safety net
	end
end

local fxToken = 0

-- ===== shooting stars: neon streaks with trails, arcing across the night sky =====
local function launchMeteor()
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local base = cam.CFrame.Position
	local ang = math.random() * math.pi * 2
	local from = base + Vector3.new(math.cos(ang) * 320, math.random(190, 250), math.sin(ang) * 320)
	local to   = base + Vector3.new(math.cos(ang + 2.4) * 320, math.random(110, 160), math.sin(ang + 2.4) * 320)

	local m = Instance.new("Part")
	m.Name = "Meteor"
	m.Shape = Enum.PartType.Ball
	m.Size = Vector3.new(2.2, 2.2, 2.2)
	m.Anchored, m.CanCollide, m.CanQuery, m.CanTouch = true, false, false, false
	m.CastShadow = false
	m.Material = Enum.Material.Neon
	m.Color = Color3.fromRGB(255, 250, 225)
	m.CFrame = CFrame.new(from)
	m.Parent = Workspace

	local a0 = Instance.new("Attachment", m); a0.Position = Vector3.new(0, 1.1, 0)
	local a1 = Instance.new("Attachment", m); a1.Position = Vector3.new(0, -1.1, 0)
	local tr = Instance.new("Trail")
	tr.Attachment0, tr.Attachment1 = a0, a1
	tr.Lifetime = 0.75
	tr.LightEmission = 1
	tr.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	tr.Color = ColorSequence.new(Color3.fromRGB(190, 220, 255), Color3.fromRGB(255, 240, 200))
	tr.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	tr.Parent = m

	-- short airy whoosh, pitched up so it reads as a streak rather than a swell
	playOneShot(AUDIO.Airy, 0.16, 2.6, 0.7)

	TweenService:Create(m, TweenInfo.new(1.15, Enum.EasingStyle.Linear), { CFrame = CFrame.new(to) }):Play()
	task.delay(1.15, function()
		m.Transparency = 1
		task.delay(0.85, function() if m then m:Destroy() end end)
	end)
end

local function restoreVisuals()
	fxToken += 1
	stopParticles()
	clearAurora()      -- immediate, rather than waiting up to 3s for the hue loop to notice
	clearBloodMoon()
	clearHalos()
	stopAudio()
	tw(Lighting, BASE.Light, 2.4)
	if atmo and BASE.Atmo then tw(atmo, BASE.Atmo, 2.4) end
	if bloom and BASE.Bloom then tw(bloom, BASE.Bloom, 2.4) end
	if rays and BASE.Rays then tw(rays, BASE.Rays, 2.4) end
	if sky and BASE.MoonSize then sky.MoonAngularSize = BASE.MoonSize end
	tw(cc, { TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0, Brightness = 0 }, 1.8)
end

-- ============================== AURORA CURTAINS ==============================
-- The Aurora event previously only cycled the ColorCorrection tint, so the "aurora" was
-- a full-screen colour wash with nothing in the sky to look at. These are real ribbons.
--
-- Client-local, in their own Workspace folder like CampfireBankVFX -- never parented into
-- anything replicated, and costing zero network traffic. Neon so they light themselves
-- without needing a light source, and fixed in WORLD space rather than tracking the
-- camera: an aurora that follows you reads as a screen effect, not a sky.
--
-- Placed north over the lake (+Z), which is the direction players face while skipping.
local auroraFolder = nil
local AURORA_HUES = { C(140, 255, 210), C(120, 210, 255), C(196, 140, 255), C(150, 255, 170) }

-- ============================ AURORA CHARACTER AURA ===========================
-- "an ethereal blue and green light emanating from the player character". Two halves: a
-- PointLight that genuinely lights the ground and the player's own model, and motes
-- drifting up off them so the glow has visible substance instead of being a flat wash.
--
-- Attached to an Attachment on the HumanoidRootPart rather than to the part itself, so a
-- single Destroy takes the whole effect with it and leaves nothing on the character.
-- Applied to EVERY player, not just the local one -- seeing other people glow is most of
-- what makes this feel like weather rather than a personal screen effect.
local AURA_NAME = "AuroraAura"
local AURA_BLUE, AURA_GREEN = C(120, 205, 255), C(140, 255, 205)

local function clearAuroraAura()
	for _, plr in ipairs(game:GetService("Players"):GetPlayers()) do
		local ch = plr.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		local old = hrp and hrp:FindFirstChild(AURA_NAME)
		if old then old:Destroy() end
	end
end

local function ensureAura(character)
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	local existing = hrp:FindFirstChild(AURA_NAME)
	if existing then return existing:FindFirstChildOfClass("PointLight") end

	local holder = Instance.new("Attachment")
	holder.Name = AURA_NAME
	holder.Position = Vector3.new(0, -0.4, 0)
	holder.Parent = hrp

	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Color = AURA_GREEN
	light.Brightness = 2.1
	light.Range = 18
	light.Shadows = false          -- a shadow-casting light on a moving player is expensive
	light.Parent = holder

	-- Motes. sparkles_main is one of only TWO built-in particle textures that actually
	-- resolve in this place -- the rest render nothing at all, which is exactly how the
	-- sandstorm shipped invisible once -- so it is the safe choice here.
	local p = Instance.new("ParticleEmitter")
	p.Name = "Motes"
	p.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	p.Rate = 16
	p.Lifetime = NumberRange.new(1.7, 2.9)
	p.Speed = NumberRange.new(1.6, 4.2)
	p.EmissionDirection = Enum.NormalId.Top
	p.SpreadAngle = Vector2.new(38, 38)
	p.Acceleration = Vector3.new(0, 2.2, 0)   -- keeps rising, so it reads as emanating
	p.Drag = 1.2
	p.Rotation = NumberRange.new(0, 360)
	p.RotSpeed = NumberRange.new(-45, 45)
	p.LightEmission = 1
	p.LightInfluence = 0
	p.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.25, 0.65, 0.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	p.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.18, 0.25),
		NumberSequenceKeypoint.new(0.75, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	p.Color = ColorSequence.new(AURA_BLUE, AURA_GREEN)
	p.Parent = holder

	return light
end

-- assigns to the forward-declared local above
function clearAurora()
	if auroraFolder then
		auroraFolder:Destroy()
		auroraFolder = nil
	end
	-- Folded in here rather than tracked separately, so EVERY existing teardown path
	-- (restoreVisuals, releaseMine, an event cut short) takes the character glow with it.
	clearAuroraAura()
end

-- BEAMS, not parts. A flat Neon part has HARD RECTANGULAR EDGES -- the first attempt at
-- this rendered as coloured billboards hanging in the sky, with the seams plainly visible,
-- because nothing about a box says "aurora". A Beam is the right primitive: it is a curved
-- ribbon with a transparency gradient along its length, it can carry a soft texture for
-- vertical falloff, and FaceCamera keeps it presenting broadside from anywhere on the map.
local function spawnAuroraCurtains()
	clearAurora()
	auroraFolder = new("Folder", { Name = "AuroraVFX" }, Workspace)
	local ribbons = {}
	-- DISTANCE AND SCALE MATTER MORE THAN ANYTHING ELSE HERE.
	-- First attempt sat them at z~780, y~350 with 110-186 stud widths. From the dock that
	-- is only ~550 studs out, so each ribbon filled the frame as a flat horizontal band
	-- across the middle of the view -- huge, close, and nothing like an aurora.
	-- Now pushed out past the north wall and lifted high: from the dock (z~20) a ribbon at
	-- z~1800 / y~700 sits about 21 degrees up, which reads as distant sky. Widths roughly
	-- halved to match, since apparent size is what was wrong, not the geometry.
	--
	-- NINE ribbons, each built from TWO stacked beams on the same attachments: a wide soft
	-- HALO and a narrow bright CORE. That layering is the biggest upgrade over the previous
	-- single-beam version, which read as five flat coloured smears -- a real aurora has a
	-- hot bright edge with a diffuse bloom around it, and one beam cannot be both at once.
	-- The two breathe out of phase, so the sheet looks like it is folding, not just pulsing.
	--
	-- Ribbons are also yawed off each other and offset in X now, instead of all lying dead
	-- flat on the same axis: from the shore that gives the sheet depth rather than the look
	-- of stacked venetian blinds.
	for i = 1, 9 do
		-- Pulled in from z 1420-2365 / y 600-980 and brightened. At that range they were
		-- technically in frame from the dock but read as almost nothing: faint wisps lost
		-- against the night sky, with the far ribbons sitting close to FogEnd (2600). The
		-- original attempt failed the other way at z~780 / y~350, where each ribbon filled
		-- the frame as a flat band -- so this sits deliberately between the two.
		local y = 540 + i * 40 + math.random(-28, 28)
		local z = 1250 + i * 95 + math.random(-80, 80)
		local host = Instance.new("Part")
		host.Name = "AuroraRibbon"
		host.Size = Vector3.new(0.2, 0.2, 0.2)
		host.Transparency = 1
		host.Anchored, host.CanCollide, host.CanQuery, host.CanTouch = true, false, false, false
		host.CastShadow, host.Locked = false, true
		host.CFrame = CFrame.new(math.random(-260, 260), y, z)
			* CFrame.Angles(0, math.rad(math.random(-26, 26)), 0)
		host.Parent = auroraFolder

		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(-820 - math.random(0, 240), 0, 0)
		a0.Parent = host
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(820 + math.random(0, 240), math.random(-70, 70), 0)
		a1.Parent = host

		local cA = AURORA_HUES[(i % #AURORA_HUES) + 1]
		local cB = AURORA_HUES[((i + 1) % #AURORA_HUES) + 1]
		-- opposing curve sizes bow the ribbon into an S rather than a straight band, and both
		-- layers share the value so the core sits INSIDE the halo instead of drifting off it
		local curve = math.random(110, 260)

		local halo = Instance.new("Beam")
		halo.Name = "Halo"
		halo.Attachment0, halo.Attachment1 = a0, a1
		halo.Width0 = 64 + math.random(0, 52)
		halo.Width1 = 64 + math.random(0, 52)
		halo.CurveSize0, halo.CurveSize1 = curve, -curve
		-- a soft blob texture stretched along the beam gives the VERTICAL falloff a beam's
		-- own transparency curve cannot: that curve only varies along the length.
		halo.Texture = "rbxasset://textures/particles/smoke_main.dds"
		halo.TextureMode = Enum.TextureMode.Stretch
		halo.TextureLength = 1
		halo.TextureSpeed = 0.03 + math.random() * 0.04   -- slow drift along the ribbon
		halo.LightEmission = 1
		halo.LightInfluence = 0
		halo.FaceCamera = true
		-- fade to nothing at both ends so the ribbon has no visible start or finish
		halo.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.24, 0.52),
			NumberSequenceKeypoint.new(0.5, 0.38),
			NumberSequenceKeypoint.new(0.76, 0.52),
			NumberSequenceKeypoint.new(1, 1),
		})
		halo.Color = ColorSequence.new(cA, cB)
		halo.Parent = host

		local core = Instance.new("Beam")
		core.Name = "Core"
		core.Attachment0, core.Attachment1 = a0, a1
		core.Width0 = halo.Width0 * 0.30
		core.Width1 = halo.Width1 * 0.30
		core.CurveSize0, core.CurveSize1 = curve, -curve
		core.Texture = "rbxasset://textures/particles/smoke_main.dds"
		core.TextureMode = Enum.TextureMode.Stretch
		core.TextureLength = 1
		core.TextureSpeed = halo.TextureSpeed * 1.6
		core.LightEmission = 1
		core.LightInfluence = 0
		core.FaceCamera = true
		core.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.30, 0.18),
			NumberSequenceKeypoint.new(0.5, 0.05),
			NumberSequenceKeypoint.new(0.70, 0.18),
			NumberSequenceKeypoint.new(1, 1),
		})
		core.Color = ColorSequence.new(cB, cA)   -- inverted, so core and halo never match
		core.Parent = host

		ribbons[#ribbons + 1] = {
			beam = halo, core = core, phase = math.random() * math.pi * 2,
			w0 = halo.Width0, w1 = halo.Width1,
			cw0 = core.Width0, cw1 = core.Width1,
			curve = curve,
		}
	end
	-- hand the folder back so a loop tears down ITS OWN aurora. Leaving Aurora and
	-- re-entering within 3s otherwise let the old hue loop's cleanup destroy the NEW
	-- ribbons, and the event would run with an empty sky.
	return ribbons, auroraFolder
end

-- ============================== LIGHTNING STRIKES ==============================
-- Thunderstorm used to be a screen-wide Brightness flash and a thunder crack with no
-- bolt anywhere. This draws a jagged bolt from the clouds down to a real ground point.
--
-- Client-local and short-lived (~0.1s visible), so ~11 parts per strike and a strike
-- every 3.5-11s. Nothing replicates and nothing accumulates.
-- opts.origin : start the bolt HERE instead of directly overhead (Blood Moon fires from
--               the moon itself, which is ~2000 studs away, not 300 above the impact)
-- opts.color  : bolt / light / ring tint, so a blood moon strike can be red
local function strikeLightning(opts)
	opts = opts or {}
	local col = opts.color or Color3.fromRGB(226, 238, 255)
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local base = cam.CFrame.Position

	-- somewhere around the player, far enough to read as distant weather
	local ang = math.random() * math.pi * 2
	local dist = 150 + math.random() * 300
	local gx, gz = base.X + math.cos(ang) * dist, base.Z + math.sin(ang) * dist

	-- find the real ground/water height so the bolt terminates ON something
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { Workspace:FindFirstChild("AuroraVFX") }
	params.IgnoreWater = false
	local hit = Workspace:Raycast(Vector3.new(gx, 600, gz), Vector3.new(0, -1200, 0), params)
	local groundY = hit and hit.Position.Y or 0
	local impact = Vector3.new(gx, groundY, gz)

	local folder = new("Folder", { Name = "BoltVFX" }, Workspace)
	local top = opts.origin
		or (impact + Vector3.new(math.random(-40, 40), 300, math.random(-40, 40)))
	-- segment count scales with length: 11 over 300 studs is jagged, but 11 over a
	-- 2000-stud moon strike would be near-straight lines
	local SEGMENTS = math.clamp(math.floor((top - impact).Magnitude / 28), 11, 34)
	local prev = top
	for s = 1, SEGMENTS do
		local f = s / SEGMENTS
		-- jitter shrinks toward the ground so the bolt converges on the impact point
		local spread = (1 - f) * 26
		local target = top:Lerp(impact, f)
			+ Vector3.new(math.random(-100, 100) / 100 * spread, 0, math.random(-100, 100) / 100 * spread)
		if s == SEGMENTS then target = impact end
		local mid = (prev + target) / 2
		local len = (target - prev).Magnitude
		local w = (opts.width or 1.5) - f * 0.7     -- tapers as it descends
		local seg = Instance.new("Part")
		seg.Size = Vector3.new(w, w, len)
		seg.CFrame = CFrame.lookAt(mid, target)
		seg.Anchored, seg.CanCollide, seg.CanQuery, seg.CanTouch = true, false, false, false
		seg.CastShadow, seg.Locked = false, true
		seg.Material = Enum.Material.Neon
		seg.Color = col
		seg.Transparency = 0.05
		seg.Parent = folder
		prev = target
	end

	-- ground flash: a real light plus an expanding scorch ring, so the strike LANDS
	local flashHost = Instance.new("Part")
	flashHost.Size = Vector3.new(0.2, 0.2, 0.2)
	flashHost.CFrame = CFrame.new(impact + Vector3.new(0, 2, 0))
	flashHost.Transparency = 1
	flashHost.Anchored, flashHost.CanCollide, flashHost.CanQuery, flashHost.CanTouch = true, false, false, false
	flashHost.CastShadow, flashHost.Locked = false, true
	flashHost.Parent = folder
	local pl = Instance.new("PointLight")
	pl.Color = col
	pl.Range = 110
	pl.Brightness = 9
	pl.Shadows = false                              -- same reason as the splash lights
	pl.Parent = flashHost
	TweenService:Create(pl, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Brightness = 0 }):Play()

	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 4, 4)
	ring.CFrame = CFrame.new(impact + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Material = Enum.Material.Neon
	ring.Color = col
	ring.Transparency = 0.3
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch = true, false, false, false
	ring.CastShadow, ring.Locked = false, true
	ring.Parent = folder
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.2, 46, 46), Transparency = 1 }):Play()

	-- the bolt itself is only visible for a moment; the light and ring outlive it
	task.delay(0.09, function()
		for _, seg in ipairs(folder:GetChildren()) do
			if seg:IsA("Part") and seg ~= flashHost and seg ~= ring then
				TweenService:Create(seg, TweenInfo.new(0.13), { Transparency = 1 }):Play()
			end
		end
	end)
	Debris:AddItem(folder, 0.9)
	return impact
end

-- ================================= BLOOD MOON =================================
-- A custom moon rather than Roblox's. The kit used to just set MoonAngularSize = 34 and
-- let the red ColorCorrection tint it, but that moon is part of the skybox: it has no
-- world position, so nothing can be fired FROM it. This is a real object, which means the
-- lightning can originate at the moon and strike the ground.
-- The kit sets moon = 0 to hide Roblox's, so there is only ever one moon in the sky.
local bloodMoonFolder, bloodMoonPos = nil, nil

-- assigns to the forward-declared local at the top of the file
function clearBloodMoon()
	if bloodMoonFolder then bloodMoonFolder:Destroy(); bloodMoonFolder = nil end
	bloodMoonPos = nil
end

local function spawnBloodMoon()
	clearBloodMoon()
	bloodMoonFolder = new("Folder", { Name = "BloodMoonVFX" }, Workspace)
	-- north and high, so it hangs over the lake in the direction players face while skipping
	bloodMoonPos = Vector3.new(0, 1500, 2200)
	local moon = Instance.new("Part")
	moon.Name = "BloodMoon"
	moon.Shape = Enum.PartType.Ball
	moon.Size = Vector3.new(650, 650, 650)
	moon.CFrame = CFrame.new(bloodMoonPos)
	moon.Anchored, moon.CanCollide, moon.CanQuery, moon.CanTouch = true, false, false, false
	moon.CastShadow, moon.Locked = false, true
	moon.Material = Enum.Material.Neon
	moon.Color = Color3.fromRGB(196, 30, 26)
	moon.Parent = bloodMoonFolder
	-- a larger, fainter shell reads as atmospheric bloom around the disc
	local halo = moon:Clone()
	halo.Name = "BloodMoonGlow"
	halo.Size = Vector3.new(880, 880, 880)
	halo.Color = Color3.fromRGB(150, 16, 14)
	halo.Transparency = 0.62
	halo.Parent = bloodMoonFolder
	return bloodMoonFolder
end

-- ================================= GOLDEN HOUR =================================
-- A halo over every character's head. Built from a ring of small Neon spheres because
-- Roblox has no torus primitive -- a flat cylinder would be a disc, not a halo, and a mesh
-- would mean guessing at an asset id. 12 spheres is enough to read as a continuous ring
-- at head scale while staying cheap with several players on screen.
-- Anchored and repositioned each frame rather than welded: welding to a live character
-- fights its physics assembly, and this way a respawn simply drops the stale entry.
local haloFolder = nil
local haloRings = {}
-- Tuned against a screenshot: 12 beads of 0.34 at radius 1.45 read as fat orbs ORBITING
-- the head rather than a halo, because Golden Hour runs Bloom at 1.45 and Neon beads bloom
-- well past their actual size. More, smaller beads on a tighter ring, sitting higher.
local HALO_BEADS = 16
local HALO_RADIUS = 1.12

-- assigns to the forward-declared local at the top of the file
function clearHalos()
	if haloFolder then haloFolder:Destroy(); haloFolder = nil end
	haloRings = {}
end

local function spawnHalos()
	clearHalos()
	haloFolder = new("Folder", { Name = "GoldenHaloVFX" }, Workspace)
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local head = char and char:FindFirstChild("Head")
		if head then
			local beads = {}
			for i = 1, HALO_BEADS do
				local b = Instance.new("Part")
				b.Name = "HaloBead"
				b.Shape = Enum.PartType.Ball
				b.Size = Vector3.new(0.21, 0.21, 0.21)
				b.Anchored, b.CanCollide, b.CanQuery, b.CanTouch = true, false, false, false
				b.CastShadow, b.Locked = false, true
				b.Material = Enum.Material.Neon
				b.Color = Color3.fromRGB(255, 214, 120)
				b.Parent = haloFolder
				beads[i] = b
			end
			-- one warm light for the whole ring, on the first bead
			local gl = Instance.new("PointLight")
			gl.Color = Color3.fromRGB(255, 206, 120)
			gl.Range = 13
			gl.Brightness = 1.7
			gl.Shadows = false
			gl.Parent = beads[1]
			haloRings[#haloRings + 1] = { head = head, beads = beads }
		end
	end
	return haloFolder
end

-- animated extras; each checks its token so a switching event cancels the old loop
local function runLoop(kind, tok, kit)
	if kind == "lightning" then
		task.spawn(function()
			while tok == fxToken do
				task.wait(math.random(35, 110) / 10)
				if tok ~= fxToken then return end
				for flash = 1, math.random(2, 3) do
					if tok ~= fxToken then return end
					-- Draw the BOLT on the first flash of the group only. The 2-3 flashes are
					-- one strike flickering, not separate strikes, so one bolt per group is
					-- what matches the sound and keeps the part count honest.
					if flash == 1 then
						pcall(strikeLightning)
					end
					Lighting.Brightness = 5.5
					cc.Brightness = 0.22
					task.wait(0.06)
					if tok ~= fxToken then return end
					Lighting.Brightness = kit.light.Brightness
					cc.Brightness = kit.cc.Brightness
					task.wait(math.random(5, 14) / 100)
				end
				-- light first, sound after: delay the crack like real distance
				local vol = 0.30 + math.random() * 0.12
				task.delay(math.random(25, 95) / 100, function()
					if tok == fxToken then playOneShot(AUDIO.Thunder, vol, 0.9 + math.random() * 0.25) end
				end)
			end
		end)
	elseif kind == "aurora" then
		local curtains, myFolder = spawnAuroraCurtains()
		local function releaseMine()
			if auroraFolder == myFolder then clearAurora() end
		end
		-- hue cycle: drives the screen tint, the atmosphere AND the curtains together, so the
		-- ribbons and the wash are always the same colour rather than fighting each other
		task.spawn(function()
			local i = 0
			while tok == fxToken do
				i += 1
				local col = AURORA_HUES[(i % #AURORA_HUES) + 1]
				tw(cc, { TintColor = col }, 3.0)
				if atmo then tw(atmo, { Color = col:Lerp(C(60, 120, 160), 0.5) }, 3.0) end
				for k, c in ipairs(curtains) do
					-- offset each ribbon a step along the hue list so the sheet reads as a
					-- gradient rather than one flat colour flipping. Beam.Color is a
					-- ColorSequence, which TweenService cannot interpolate, so assign it.
					local cA = AURORA_HUES[((i + k) % #AURORA_HUES) + 1]
					local cB = AURORA_HUES[((i + k + 1) % #AURORA_HUES) + 1]
					if c.beam.Parent then
						c.beam.Color = ColorSequence.new(cA, cB)
					end
					-- core takes the pair INVERTED, so the bright edge is never the same
					-- colour as the bloom around it
					if c.core and c.core.Parent then
						c.core.Color = ColorSequence.new(cB, cA)
					end
				end
				task.wait(3.0)
			end
			releaseMine()
		end)
		-- CHARACTER AURA: keep every player wrapped in the blue-green glow for as long as the
		-- event runs. A polling loop rather than CharacterAdded connections on purpose -- it
		-- covers respawns, late joiners and a character that streamed in after the event
		-- started with one code path, and there are no connections to leak on teardown.
		task.spawn(function()
			local Plrs = game:GetService("Players")
			local j = 0
			while tok == fxToken do
				j += 1
				-- ease the light between blue and green rather than snapping: this is the
				-- "ethereal" half, and a hard switch would read as a lamp being toggled
				local blend = (math.sin(j * 0.32) + 1) / 2
				local col = AURA_BLUE:Lerp(AURA_GREEN, blend)
				for _, plr in ipairs(Plrs:GetPlayers()) do
					local light = ensureAura(plr.Character)
					if light then
						tw(light, { Color = col, Brightness = 1.8 + blend * 0.9 }, 0.5)
					end
				end
				task.wait(0.5)
			end
			releaseMine()
		end)
		-- slow shimmer: gentle sway and a breathing transparency. Separate from the hue loop
		-- because it needs to run every frame, not every 3 seconds.
		task.spawn(function()
			while tok == fxToken do
				local t = os.clock()
				for _, c in ipairs(curtains) do
					if c.beam.Parent then
						-- breathe the ribbon's height; the texture drift handles lateral motion
						local w = math.sin(t * 0.28 + c.phase)
						c.beam.Width0 = c.w0 * (1 + w * 0.16)
						c.beam.Width1 = c.w1 * (1 - w * 0.16)
						-- Undulate the curve as well. Width alone only made the sheet fatter
						-- and thinner in place; moving the curve makes the ribbon actually
						-- travel, which is what sells it as an aurora rather than a sign.
						local s = math.sin(t * 0.17 + c.phase * 1.3)
						c.beam.CurveSize0 = c.curve * (1 + s * 0.35)
						c.beam.CurveSize1 = -c.curve * (1 - s * 0.35)
					end
					if c.core and c.core.Parent then
						-- core breathes on the OPPOSITE phase, so the bright edge slides
						-- within the bloom instead of the two moving as one slab
						local cw = math.sin(t * 0.28 + c.phase + math.pi)
						c.core.Width0 = c.cw0 * (1 + cw * 0.30)
						c.core.Width1 = c.cw1 * (1 - cw * 0.30)
						c.core.CurveSize0 = c.beam.CurveSize0
						c.core.CurveSize1 = c.beam.CurveSize1
					end
				end
				RunService.Heartbeat:Wait()
			end
			releaseMine()
		end)
	elseif kind == "meteors" then
		task.spawn(function()
			while tok == fxToken do
				task.wait(math.random(11, 30) / 10)
				if tok ~= fxToken then return end
				for _ = 1, math.random(1, 2) do
					if tok ~= fxToken then return end
					launchMeteor()
					task.wait(0.18)
				end
			end
		end)
	elseif kind == "pulse" then
		local myMoon = spawnBloodMoon()
		local function releaseMine()
			if bloodMoonFolder == myMoon then clearBloodMoon() end
		end
		-- the existing ominous brightness pulse
		task.spawn(function()
			while tok == fxToken do
				tw(cc, { Brightness = 0.05 }, 1.8); task.wait(1.9)
				if tok ~= fxToken then return end
				tw(cc, { Brightness = -0.04 }, 1.8); task.wait(1.9)
			end
			releaseMine()
		end)
		-- and the moon firing lightning at the ground
		task.spawn(function()
			while tok == fxToken do
				task.wait(math.random(30, 75) / 10)
				if tok ~= fxToken then break end
				-- Bolt originates AT the moon, so it visibly comes down out of it rather than
				-- from generic cloud height. Red to match, and wider because it is ~2000
				-- studs long -- a 1.5-stud bolt that far away would be invisible.
				pcall(function()
					strikeLightning({
						origin = bloodMoonPos,
						color = Color3.fromRGB(255, 64, 52),
						width = 5.5,
					})
				end)
				-- brief red flare, quieter than a Thunderstorm strike
				Lighting.Brightness = 2.6
				task.wait(0.07)
				if tok ~= fxToken then break end
				Lighting.Brightness = kit.light.Brightness
				local vol = 0.22 + math.random() * 0.10
				task.delay(math.random(30, 90) / 100, function()
					if tok == fxToken then playOneShot(AUDIO.Thunder, vol, 0.62 + math.random() * 0.14) end
				end)
			end
			releaseMine()
		end)
	elseif kind == "halo" then
		local myHalo = spawnHalos()
		task.spawn(function()
			while tok == fxToken do
				local t = os.clock()
				for _, ring in ipairs(haloRings) do
					local head = ring.head
					if head and head.Parent then
						-- sit above the head, tilted, and spin slowly
						local centre = head.Position + Vector3.new(0, 1.78 + math.sin(t * 1.3) * 0.06, 0)
						for i, b in ipairs(ring.beads) do
							if b.Parent then
								local a = (i / HALO_BEADS) * math.pi * 2 + t * 0.9
								b.Position = centre + Vector3.new(
									math.cos(a) * HALO_RADIUS,
									math.sin(a) * 0.11,          -- slight tilt
									math.sin(a) * HALO_RADIUS)
							end
						end
					end
				end
				RunService.Heartbeat:Wait()
			end
			if haloFolder == myHalo then clearHalos() end
		end)
	end
end

local function applyKit(name, accent)
	fxToken += 1
	local tok = fxToken
	local kit = KITS[name]
	if not kit then
		-- unknown event: fall back to the old gentle accent tint
		tw(cc, { TintColor = accent:Lerp(Color3.new(1, 1, 1), 0.55), Saturation = 0.08, Brightness = 0.02 }, 1.2)
		return
	end
	tw(Lighting, kit.light, 2.2)
	if atmo and kit.atmo then tw(atmo, kit.atmo, 2.2) end
	if bloom and kit.bloom then tw(bloom, kit.bloom, 2.2) end
	if rays and kit.rays then tw(rays, kit.rays, 2.2) end
	if sky then sky.MoonAngularSize = kit.moon or BASE.MoonSize end
	tw(cc, kit.cc, 2.2)
	if kit.particles then startParticles(kit.particles) else stopParticles() end
	startAudio(kit.sounds)
	if kit.loop then task.delay(2.2, function() if tok == fxToken then runLoop(kit.loop, tok, kit) end end) end
end

-- ===== incoming-event alert (20s heads-up before an event starts) =====
local alert = new("Frame", {
	Name = "WeatherAlert", Visible = false, AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 128), Size = UDim2.new(0, 470, 0, 62),
	BackgroundColor3 = Color3.fromRGB(16, 19, 28), BackgroundTransparency = 0.06,
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 12) }, alert)
local aStroke = new("UIStroke", { Color = Color3.fromRGB(255, 205, 90), Thickness = 2.5 }, alert)
local aTitle = new("TextLabel", {
	Position = UDim2.new(0, 16, 0, 7), Size = UDim2.new(1, -110, 0, 24), BackgroundTransparency = 1,
	Text = "", Font = Enum.Font.GothamBlack, TextSize = 18,
	TextColor3 = Color3.fromRGB(255, 255, 255), TextXAlignment = Enum.TextXAlignment.Left,
}, alert)
local aSub = new("TextLabel", {
	Position = UDim2.new(0, 16, 0, 33), Size = UDim2.new(1, -110, 0, 18), BackgroundTransparency = 1,
	Text = "", Font = Enum.Font.GothamMedium, TextSize = 13,
	TextColor3 = Color3.fromRGB(255, 214, 140), TextXAlignment = Enum.TextXAlignment.Left,
}, alert)
local aClock = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.new(0, 78, 0, 42),
	BackgroundTransparency = 1, Text = "", Font = Enum.Font.GothamBlack, TextSize = 30,
	TextColor3 = Color3.fromRGB(255, 205, 90),
}, alert)

local alertToken = 0
local function showAlert(s)
	alertToken += 1
	local tok = alertToken
	local accent = s.Tint and Color3.fromRGB(s.Tint[1], s.Tint[2], s.Tint[3]) or Color3.fromRGB(255, 205, 90)
	aStroke.Color = accent
	aClock.TextColor3 = accent
	aTitle.Text = (s.Emoji or "") .. "  " .. string.upper(s.Name or "") .. "  INCOMING"
	aSub.Text = s.MutName
		and ("chance at %s \u{00B7} \u{00D7}%s cash"):format(string.upper(s.MutName), tostring(s.MutMult or 1))
		or "get ready"
	alert.Visible = true
	alert.Size = UDim2.new(0, 415, 0, 62)
	TweenService:Create(alert, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, 470, 0, 62) }):Play()

	task.spawn(function()
		while tok == alertToken do
			local left = (s.StartsAt or 0) - os.time()
			if left <= 0 then break end
			aClock.Text = tostring(left)
			if left <= 5 then          -- pulse harder over the last 5 seconds
				aClock.TextSize = 37
				TweenService:Create(aClock, TweenInfo.new(0.45), { TextSize = 30 }):Play()
			end
			task.wait(0.25)
		end
		if tok == alertToken then alert.Visible = false end
	end)
end

local active

remotes.WeatherState.OnClientEvent:Connect(function(s)
	if typeof(s) ~= "table" then return end
	-- a warning is a heads-up only: no visuals, no audio, weather is still Clear
	if s.Warning then
		showAlert(s)
		return
	end
	alertToken += 1          -- event landed; kill any countdown still running
	alert.Visible = false
	active = s
	if s.IsEvent then
		local accent = s.Tint and Color3.fromRGB(s.Tint[1], s.Tint[2], s.Tint[3]) or Color3.fromRGB(120, 200, 255)
		title.Text = (s.Emoji or "") .. "  " .. string.upper(s.Name) .. "  EVENT"
		-- events no longer grant luck, so advertise the actual prize: the mutation
		if s.MutName then
			sub.Text = ("%s mutation \u{2014} %d%% chance \u{00B7} \u{00D7}%s cash  \u{2014}  live skips only!")
				:format(string.upper(s.MutName), math.floor((s.MutChance or 0) * 100 + 0.5), tostring(s.MutMult or 1))
		else
			sub.Text = "live skips only!"
		end
		bStroke.Color = accent
		banner.Visible = true
		-- pop-in
		banner.Size = UDim2.new(0, 380, 0, 44)
		TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0, 440, 0, 44) }):Play()
		applyKit(s.Name, accent)
	else
		banner.Visible = false
		restoreVisuals()
	end
end)

task.spawn(function()
	while true do
		task.wait(1)
		if active and active.IsEvent and active.EndsAt then
			local remaining = active.EndsAt - os.time()
			if remaining <= 0 then
				banner.Visible = false
			else
				timeLbl.Text = string.format("%d:%02d", math.floor(remaining / 60), remaining % 60)
			end
		end
	end
end)
