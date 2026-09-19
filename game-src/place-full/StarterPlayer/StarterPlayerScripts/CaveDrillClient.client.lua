-- CaveDrillClient: the ice drill on the shore outside Elder Tung's tundra hut.
--
-- CLIENT-SIDE ON PURPOSE, all of it. The drill has three different appearances -- a heap
-- of salvage, a finished rig, a running rig over an open shaft -- and which one is
-- correct depends on how far THIS player has got through TundraQuest. One shared server
-- model cannot be a pile of scrap for one player and a working drill for the player
-- standing next to them, so it is drawn locally, exactly like the cellar hatch
-- (see CellarDoorClient for the same argument made about a door).
--
-- Everything here is driven by the TundraState push. There is no server object beyond
-- Workspace.GameWorld.FrozenTundra.DrillSite, an invisible anchor part that says WHERE --
-- so the site can be dragged in Studio without a script edit.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(modules:WaitForChild("TundraQuestConfig"))
local stateRemote = remotes:WaitForChild("TundraState")

local okSound, SoundKit = pcall(function() return require(modules.SoundKit) end)
if not okSound then SoundKit = nil end

-- Which stage each appearance starts at, resolved from the config by Id so reordering
-- the arc cannot silently show the wrong thing.
local I_PARTS = Config.IndexOfId.Parts
local I_FUEL  = Config.IndexOfId.Fuel

-- PALETTE. World 2's lighting is a strong blue wash (TundraAtmosphere), and the first
-- pass used a mid grey for the steelwork -- which came out the same blue as the icebergs
-- behind it, so the rig had no silhouette at all. Everything structural is now near-black
-- iron with brass and rust picking out the moving parts: warm colours are the only ones
-- that survive that wash.
local STEEL = Color3.fromRGB(46, 50, 58)
local DARK  = Color3.fromRGB(28, 30, 36)
local BRASS = Color3.fromRGB(198, 148, 62)
local WOOD  = Color3.fromRGB(74, 48, 30)
local RUST  = Color3.fromRGB(134, 72, 42)
local GLOW  = Color3.fromRGB(120, 226, 255)

local site, rig, mode
local spinConn

---------------------------------------------------------------- build helpers
local function newPart(parent, name, size, cf, colour, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = material or Enum.Material.Metal
	p.Anchored = true
	p.CanCollide = false      -- local geometry: colliding with it would desync from the server's idea of the world
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- site-local placement, so every measurement below reads as "x studs right, y up, z out"
local function at(x, y, z, ry, rx, rz)
	return site.CFrame * CFrame.new(x, y, z)
		* CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
end

local function clearRig()
	if spinConn then spinConn:Disconnect(); spinConn = nil end
	if rig then rig:Destroy(); rig = nil end
end

---------------------------------------------------------------- the three appearances
-- SALVAGE: what the site looks like while the player is still out on the ice finding
-- pieces. A frame he has already sunk into the ice, and a crate to put the rest in --
-- so the objective has somewhere to point at rather than being an abstract counter.
local function buildSalvage(parent)
	newPart(parent, "Pad", Vector3.new(11, 0.4, 11), at(0, 0.2, 0), Color3.fromRGB(196, 214, 226), Enum.Material.Ice)
	for i = -1, 1, 2 do
		newPart(parent, "Skid", Vector3.new(0.9, 0.7, 9), at(i * 3.2, 0.75, 0), DARK)
	end
	newPart(parent, "Deck", Vector3.new(8, 0.5, 9.4), at(0, 1.35, 0), WOOD, Enum.Material.WoodPlanks)
	-- the salvage stage keeps the deck whole: nothing has been drilled through it yet
	-- a single upright, leaning, clearly unfinished
	newPart(parent, "Upright", Vector3.new(0.8, 8, 0.8), at(-2.6, 5.4, -1.2, 0, 0, 9), STEEL)
	newPart(parent, "Crate", Vector3.new(3, 2.4, 2.6), at(4.4, 1.2, 3.2, 22), WOOD, Enum.Material.WoodPlanks)
	newPart(parent, "CrateLid", Vector3.new(3.2, 0.3, 2.8), at(4.4, 2.5, 3.2, 22), RUST, Enum.Material.Wood)
	-- loose scrap in the snow
	for i = 1, 5 do
		local a = (i / 5) * math.pi * 2
		newPart(parent, "Scrap", Vector3.new(1.1, 0.25, 1.1),
			at(math.cos(a) * 5.4, 0.5, math.sin(a) * 5.4, i * 37, 0, 6), RUST)
	end
	newPart(parent, "Tarp", Vector3.new(6, 0.2, 5), at(-0.5, 1.7, 1.2, 6), Color3.fromRGB(72, 84, 74), Enum.Material.Fabric)
end

-- RIG: the assembled drill. `augerHolder` is returned so the running state can spin it
-- without rebuilding anything.
local function buildRig(parent)
	newPart(parent, "Pad", Vector3.new(11, 0.4, 11), at(0, 0.2, 0), Color3.fromRGB(196, 214, 226), Enum.Material.Ice)
	for i = -1, 1, 2 do
		newPart(parent, "Skid", Vector3.new(0.9, 0.7, 9), at(i * 3.2, 0.75, 0), DARK)
	end
	-- DECK IS OPEN AT THE FRONT. It used to be one 9.4-deep slab, which meant the shaft
	-- the whole questline exists to open was drilled directly UNDER the drill's own
	-- platform and could not be seen at all. Rear platform plus two side rails: the auger
	-- and the hole it makes are framed by the rig instead of hidden by it.
	newPart(parent, "DeckRear", Vector3.new(8, 0.5, 5.0), at(0, 1.35, -2.2), WOOD, Enum.Material.WoodPlanks)
	for i = -1, 1, 2 do
		newPart(parent, "DeckRail", Vector3.new(1.6, 0.5, 4.6), at(i * 3.2, 1.35, 2.4), WOOD, Enum.Material.WoodPlanks)
	end
	newPart(parent, "DeckLip", Vector3.new(8, 0.5, 0.8), at(0, 1.35, 4.3), WOOD, Enum.Material.WoodPlanks)

	-- derrick: two uprights, a crossbar and two braces. Taller than the first pass -- next
	-- to a 17-stud hut a 12-stud rig read as a handcart, and this is supposed to be the
	-- machine that opens World 3.
	for i = -1, 1, 2 do
		newPart(parent, "Upright", Vector3.new(0.85, 15, 0.85), at(i * 3.0, 9.1, -1.4), STEEL)
		newPart(parent, "Brace", Vector3.new(0.5, 7.4, 0.5), at(i * 2.1, 4.8, 0.9, 0, 0, i * 26), STEEL)
		newPart(parent, "Rung", Vector3.new(6.6, 0.35, 0.35), at(0, 5.0 + i * 2.6, -1.4), RUST)
	end
	newPart(parent, "Rung", Vector3.new(6.6, 0.35, 0.35), at(0, 10.4, -1.4), RUST)
	newPart(parent, "Crossbar", Vector3.new(7.4, 0.8, 0.9), at(0, 16.4, -1.4), STEEL)
	newPart(parent, "Pulley", Vector3.new(2.2, 2.2, 0.6), at(0, 16.4, -1.4, 0, 0, 90), BRASS)
	newPart(parent, "Cable", Vector3.new(0.18, 6.0, 0.18), at(0, 13.2, -1.4), Color3.fromRGB(30, 28, 28))
	newPart(parent, "Lamp", Vector3.new(0.9, 0.9, 0.9), at(0, 15.3, -0.4), Color3.fromRGB(255, 214, 150), Enum.Material.Neon)

	-- engine: block, flywheel, belt, exhaust
	newPart(parent, "Engine", Vector3.new(3.4, 2.6, 3.0), at(0, 2.9, -3.0), DARK)
	newPart(parent, "Flywheel", Vector3.new(2.6, 2.6, 0.5), at(2.0, 2.9, -3.0, 0, 0, 90), BRASS)
	newPart(parent, "Belt", Vector3.new(0.25, 5.4, 0.9), at(2.0, 4.6, -3.0, 0, 0, 12), Color3.fromRGB(36, 34, 34), Enum.Material.Fabric)
	newPart(parent, "Exhaust", Vector3.new(0.7, 4.2, 0.7), at(-1.4, 5.2, -3.2), RUST)
	newPart(parent, "ExhaustCap", Vector3.new(1.1, 0.4, 1.1), at(-1.4, 7.4, -3.2), DARK)

	-- the five cogs and two gears, mounted where the player can see what they salvaged.
	-- Payoff matters: a counter that filled up should turn into something visible.
	for i = 1, 5 do
		newPart(parent, "Cog", Vector3.new(1.15, 1.15, 0.32),
			at(-2.1 + (i - 1) * 0.95, 3.9 + ((i % 2 == 0) and 0.5 or 0), -4.55, 0, 0, 90 + i * 11), BRASS)
	end
	for i = -1, 1, 2 do
		newPart(parent, "Gear", Vector3.new(2.1, 2.1, 0.4), at(i * 2.4, 1.9, -4.55, 0, 0, 90), STEEL)
	end

	newPart(parent, "Lever", Vector3.new(0.28, 2.6, 0.28), at(2.7, 3.0, 0.6, 0, 0, -22), STEEL)
	newPart(parent, "LeverKnob", Vector3.new(0.6, 0.6, 0.6), at(3.2, 4.2, 0.6), Color3.fromRGB(184, 66, 58), Enum.Material.SmoothPlastic)

	-- AUGER, in its own model: the running state rotates this and nothing else.
	local auger = Instance.new("Model")
	auger.Name = "Auger"
	auger.Parent = parent
	local shaft = newPart(auger, "Shaft", Vector3.new(1.1, 12, 1.1), at(0, 6.8, 1.6), DARK)
	auger.PrimaryPart = shaft
	-- Flights: flat plates stepped round the shaft read as a helix once it turns, and cost
	-- ten parts instead of a mesh. Alternating brass and iron so the rotation is legible --
	-- a single-colour helix spinning at 4.5 rad/s just looks like a blurred pole.
	for i = 0, 9 do
		newPart(auger, "Flight", Vector3.new(3.2, 0.26, 1.05),
			at(0, 1.9 + i * 1.05, 1.6, i * 40, 0, 15),
			(i % 2 == 0) and BRASS or STEEL)
	end
	newPart(auger, "Bit", Vector3.new(2.0, 1.8, 2.0), at(0, 1.1, 1.6), Color3.fromRGB(120, 128, 140))
	newPart(auger, "Tip", Vector3.new(0.9, 1.3, 0.9), at(0, 0.25, 1.6), Color3.fromRGB(176, 184, 196))
	return auger
end

-- THE BREAKTHROUGH, at site-local Z+12 -- in front of the rig, not under it.
--
-- Why the way down is a PORTAL and not a carved hole: the tundra floor is three big
-- collidable slabs (Ground.IceShelf 1992..1997, ShelfDeep 1986..1993, DeepBaseDeep
-- 1966..1974), not terrain. Cutting them with SubtractAsync does produce a visible hole,
-- but the union's collision mesh fills a hole that small straight back in -- you would see
-- a shaft and still stand on it. Carving the terrain does nothing at all, because the
-- terrain is not what you are standing on there.
--
-- Drawing it client-side also gets the gating for free: this only ever runs in "running"
-- mode, so the way down does not exist for anyone who has not powered the drill.
local HOLE_Z = 12
local introPlayed = false

local function buildShaft(parent)
	local origin = at(0, 0, HOLE_Z)

	-- the shaft of light that IS the way down
	local col = newPart(parent, "PortalColumn", Vector3.new(11, 15, 11), at(0, 7.5, HOLE_Z),
		Color3.fromRGB(96, 226, 110), Enum.Material.Neon)
	col.Shape = Enum.PartType.Cylinder
	col.CFrame = at(0, 7.5, HOLE_Z) * CFrame.Angles(0, 0, math.rad(90))
	col.Transparency = 1

	local pool = newPart(parent, "PortalPool", Vector3.new(12, 0.4, 12), at(0, 0.25, HOLE_Z),
		Color3.fromRGB(150, 245, 160), Enum.Material.Neon)
	pool.Shape = Enum.PartType.Cylinder
	pool.CFrame = at(0, 0.25, HOLE_Z) * CFrame.Angles(0, 0, math.rad(90))
	pool.Transparency = 1

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(96, 226, 110)
	light.Brightness = 0
	light.Range = 34
	light.Shadows = false
	light.Parent = pool

	-- broken ice thrown up around the rim
	local shards = {}
	for i = 1, 10 do
		local a = (i / 10) * math.pi * 2
		local s = newPart(parent, "IceShard", Vector3.new(0.9, 2.2, 0.9),
			at(math.cos(a) * 6.8, 0.2, HOLE_Z + math.sin(a) * 6.8, i * 23, 0, 16 * ((i % 2 == 0) and 1 or -1)),
			Color3.fromRGB(186, 214, 232), Enum.Material.Ice)
		s.Transparency = 1
		shards[i] = s
	end

	-- the sign, floating over the portal, green
	local anchor = newPart(parent, "SignAnchor", Vector3.new(1, 1, 1), at(0, 1, HOLE_Z), Color3.new(1,1,1))
	anchor.Transparency = 1
	local board = Instance.new("BillboardGui")
	board.Name = "ShaftSign"
	board.Size = UDim2.fromOffset(250, 56)
	board.StudsOffsetWorldSpace = Vector3.new(0, 12, 0)
	board.AlwaysOnTop = false
	board.MaxDistance = 140
	board.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(96, 226, 110)
	label.TextTransparency = 1
	label.Text = "LUSH GARDENS"
	label.Parent = board
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(10, 44, 16)
	st.Thickness = 2.5
	st.Parent = label

	-- snow thrown up as the bit bites
	local burstHost = newPart(parent, "BurstHost", Vector3.new(1, 1, 1), at(0, 0.5, HOLE_Z), Color3.new(1,1,1))
	burstHost.Transparency = 1
	local snow = Instance.new("ParticleEmitter")
	snow.Texture = "rbxasset://textures/particles/smoke_main.dds"
	snow.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(206, 232, 244))
	snow.Lifetime = NumberRange.new(0.7, 1.5)
	snow.Speed = NumberRange.new(18, 34)
	snow.SpreadAngle = Vector2.new(46, 46)
	snow.Acceleration = Vector3.new(0, -58, 0)
	snow.Rotation = NumberRange.new(0, 360)
	snow.RotSpeed = NumberRange.new(-180, 180)
	snow.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0.2) })
	snow.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	snow.Rate = 0
	snow.Parent = burstHost

	local function reveal(t)
		TweenService:Create(col,  TweenInfo.new(t), { Transparency = 0.55 }):Play()
		TweenService:Create(pool, TweenInfo.new(t), { Transparency = 0.15 }):Play()
		TweenService:Create(light, TweenInfo.new(t), { Brightness = 3.2 }):Play()
		TweenService:Create(label, TweenInfo.new(t), { TextTransparency = 0 }):Play()
		for _, s in ipairs(shards) do
			TweenService:Create(s, TweenInfo.new(t), { Transparency = 0 }):Play()
		end
	end

	if introPlayed then
		-- already broken through earlier this session: just show it
		reveal(0.01)
	else
		introPlayed = true
		task.spawn(function()
			-- 1) the bit bites: snow flies for a beat before anything opens
			snow.Rate = 260
			if SoundKit then pcall(function() SoundKit.play("Impact", burstHost) end) end
			task.wait(1.6)
			-- 2) a shockwave ring across the ice
			local ring = newPart(parent, "CrackRing", Vector3.new(4, 0.3, 4), at(0, 0.3, HOLE_Z),
				Color3.fromRGB(210, 245, 255), Enum.Material.Neon)
			ring.Shape = Enum.PartType.Cylinder
			ring.CFrame = at(0, 0.3, HOLE_Z) * CFrame.Angles(0, 0, math.rad(90))
			ring.Transparency = 0.2
			TweenService:Create(ring, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = Vector3.new(4, 30, 30), Transparency = 1 }):Play()
			task.delay(0.85, function() if ring then ring:Destroy() end end)
			-- 3) the way down opens
			snow.Rate = 90
			reveal(0.9)
			task.wait(1.2)
			snow.Rate = 26   -- settles to a light spray off the bit
		end)
	end
end

local function addRunningFX(parent, auger)
	local exhaust = parent:FindFirstChild("ExhaustCap")
	if exhaust then
		local steam = Instance.new("ParticleEmitter")
		steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
		steam.Rate = 9
		steam.Lifetime = NumberRange.new(1.6, 2.8)
		steam.Speed = NumberRange.new(4, 7)
		steam.SpreadAngle = Vector2.new(7, 7)
		steam.Acceleration = Vector3.new(0.6, 2.2, 0.2)
		steam.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 3.6) })
		steam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.5),
			NumberSequenceKeypoint.new(1, 1) })
		steam.Color = ColorSequence.new(Color3.fromRGB(226, 232, 238), Color3.fromRGB(180, 190, 200))
		steam.Parent = exhaust
	end
	local bit = auger and auger:FindFirstChild("Bit")
	if bit then
		local chips = Instance.new("ParticleEmitter")
		chips.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		chips.Rate = 26
		chips.Lifetime = NumberRange.new(0.5, 1.1)
		chips.Speed = NumberRange.new(7, 13)
		chips.SpreadAngle = Vector2.new(60, 60)
		chips.Acceleration = Vector3.new(0, -22, 0)
		chips.LightEmission = 0.7
		chips.Color = ColorSequence.new(Color3.fromRGB(214, 240, 255), GLOW)
		chips.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0) })
		chips.Parent = bit
	end
	local engine = parent:FindFirstChild("Engine")
	if engine then
		local hum = Instance.new("Sound")
		hum.Name = "DrillHum"
		hum.SoundId = "rbxassetid://3763470680"   -- the same bed the braziers use; a low loop
		hum.Volume = 0.22
		hum.Looped = true
		hum.PlaybackSpeed = 0.55                  -- pitched down, so it reads as machinery
		hum.RollOffMinDistance = 10
		hum.RollOffMaxDistance = 90
		hum.Parent = engine
		hum:Play()
	end
end

---------------------------------------------------------------- render
local function render(next_)
	if next_ == mode then return end
	mode = next_
	clearRig()
	if not site or mode == "none" then return end

	rig = Instance.new("Model")
	rig.Name = "CaveDrill"
	rig.Parent = Workspace

	if mode == "salvage" then
		buildSalvage(rig)
		return
	end

	local auger = buildRig(rig)
	if mode == "built" then return end

	-- running
	buildShaft(rig)
	addRunningFX(rig, auger)
	local spin, base = 0, auger:GetPivot()
	spinConn = RunService.Heartbeat:Connect(function(dt)
		if not (auger and auger.Parent) then return end
		spin += dt * 4.5
		auger:PivotTo(base * CFrame.Angles(0, spin, 0))
	end)
end

local function modeFor(payload)
	local stage = tonumber(payload.State) or 0
	if payload.Done then return "running" end
	if stage >= I_FUEL then return "built" end
	if stage >= I_PARTS then return "salvage" end
	return "none"
end

---------------------------------------------------------------- cutscenes
-- Both cutscenes take the camera, so both must give it back no matter what happens in
-- between -- a stuck Scriptable camera is unrecoverable without rejoining.
local function withCamera(seconds, body)
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local oldType, oldCF, oldSubject = cam.CameraType, cam.CFrame, cam.CameraSubject
	cam.CameraType = Enum.CameraType.Scriptable
	local ok, err = pcall(body, cam)
	if not ok then warn("[CaveDrillClient] cutscene failed: " .. tostring(err)) end
	task.delay(seconds, function()
		cam.CameraType = oldType == Enum.CameraType.Scriptable and Enum.CameraType.Custom or oldType
		cam.CameraSubject = oldSubject
		cam.CFrame = oldCF
	end)
end

-- `out` is studs on the SEAWARD side of the site, so every shot looks back at the rig
-- with the hut behind it. That backdrop is deliberate -- it places the machine next to
-- the man who wanted it built. Shooting the other way was tried and is wrong: the site
-- is only 26 studs from the hut, so a camera pulled "back" any useful distance ends up
-- inside the hut wall, filming planks.
local function siteShot(height, out, side)
	local target = site.CFrame * Vector3.new(0, 6, 1.5)
	return CFrame.lookAt(site.CFrame * Vector3.new(side or 0, height, out), target)
end

local function playBuild()
	if not site then return end
	withCamera(6.4, function(cam)
		cam.CFrame = siteShot(4, 26, -14)
		TweenService:Create(cam, TweenInfo.new(6.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ CFrame = siteShot(11, 19, 15) }):Play()
	end)

	-- The rig assembles: every part drops in from above with its own small delay, so it
	-- reads as being built rather than switched on.
	clearRig()
	mode = "built"
	rig = Instance.new("Model")
	rig.Name = "CaveDrill"
	rig.Parent = Workspace
	buildRig(rig)

	local pieces = {}
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("BasePart") then pieces[#pieces + 1] = d end
	end
	-- bottom-up, so the deck lands before the derrick that stands on it
	table.sort(pieces, function(a, b) return a.Position.Y < b.Position.Y end)
	for i, p in ipairs(pieces) do
		local final = p.CFrame
		p.CFrame = final * CFrame.new(0, 34 + i * 0.6, 0)
		p.Transparency = 1
		task.delay(0.35 + i * 0.055, function()
			if not p.Parent then return end
			p.Transparency = 0
			TweenService:Create(p, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ CFrame = final }):Play()
			if SoundKit and i % 3 == 0 then
				pcall(function() SoundKit.play("wheelTick", nil, { volume = 0.16, speed = 0.7 }) end)
			end
		end)
	end
end

local function playStart()
	if not site then return end
	withCamera(6.4, function(cam)
		cam.CFrame = siteShot(9, 22, 12)
		TweenService:Create(cam, TweenInfo.new(3.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ CFrame = siteShot(3, 13, -4) }):Play()
		task.delay(3.3, function()
			TweenService:Create(cam, TweenInfo.new(2.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ CFrame = siteShot(14, 24, -18) }):Play()
		end)
	end)
	-- The rig is already standing; the beat is it STARTING, so it spins up first and the
	-- ice only gives way once it is at speed.
	if mode ~= "built" then render("built") end
	local auger = rig and rig:FindFirstChild("Auger")
	if auger then
		local spin, base, t = 0, auger:GetPivot(), 0
		if spinConn then spinConn:Disconnect() end
		spinConn = RunService.Heartbeat:Connect(function(dt)
			if not (auger and auger.Parent) then return end
			t = math.min(t + dt, 3.2)
			spin += dt * (0.4 + 4.1 * (t / 3.2))
			auger:PivotTo(base * CFrame.Angles(0, spin, 0))
		end)
	end
	task.delay(3.4, function()
		mode = nil          -- force the rebuild; render() short-circuits on an unchanged mode
		render("running")
	end)
end

---------------------------------------------------------------- wiring
-- STREAMING. workspace.StreamingEnabled is on and the site is 8000 studs from spawn, so
-- for most of a session DrillSite simply does not exist on this client -- and when the
-- player finally walks into World 2 it is CREATED, not reparented. The join state push
-- lands long before that.
--
-- Hence: hold the last payload, and (re)build every time the anchor appears. Without
-- this the drill is invisible to anyone who was not standing in the tundra at the moment
-- their quest state was sent, which is nearly everyone.
local pending

local function apply(payload)
	local note = payload.Note
	if note == "cutscene:DrillBuild" then
		playBuild()
		return
	elseif note == "cutscene:DrillStart" then
		playStart()
		return
	end
	render(modeFor(payload))
end

stateRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end
	pending = payload            -- always kept, so a re-stream can rebuild from it
	if not site then return end
	apply(payload)
end)

local function adopt(newSite)
	site = newSite
	mode = nil                   -- the rig belonged to the old anchor; force a rebuild
	clearRig()
	if not pending then return end
	-- A cutscene note that arrived before the anchor did is replayed as its RESULT, not
	-- as a cutscene: the moment has passed, and yanking the camera now -- possibly while
	-- the player is somewhere else entirely -- would be baffling.
	local p = table.clone(pending)
	p.Note = nil
	apply(p)
end

task.spawn(function()
	local gw = Workspace:WaitForChild("GameWorld", 60)
	local ft = gw and gw:WaitForChild("FrozenTundra", 60)
	if not ft then
		warn("[CaveDrillClient] no GameWorld.FrozenTundra -- the drill has nowhere to stand")
		return
	end
	local existing = ft:FindFirstChild("DrillSite")
	if existing then adopt(existing) end
	ft.ChildAdded:Connect(function(child)
		if child.Name == "DrillSite" and child:IsA("BasePart") then adopt(child) end
	end)
	ft.ChildRemoved:Connect(function(child)
		-- streamed back out: drop the local rig with it, or it is left hanging in a world
		-- the player has walked out of, with its anchor destroyed under it
		if child == site then
			site = nil
			mode = nil
			clearRig()
		end
	end)
end)
