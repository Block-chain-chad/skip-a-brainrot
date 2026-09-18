-- MassiveEmergence: the cutscene a SIZE-mutated catch earns.
--
-- Storyboard beats B1-B3 from the approved Catch Ceremony plan, which were designed but
-- never built ("silhouette-in-pillar rise, camera work"). A Huge or Massive is rare enough
-- to deserve the takeover the plan always wanted:
--
--   B1 ANTICIPATION  camera cuts to the water where the stone broke the surface; the lake
--                    glows in the tier colour before anything appears (the Genshin tell)
--   B2 ERUPTION      geyser + ring, screen shake, bass hit
--   B3 THE RISE      the ACTUAL creature rises out of the water as a black silhouette,
--                    turning slowly, then the colours snap on at full height
--
-- It runs IN FRONT of PullCeremony and hands back cleanly, so the existing takeover /
-- odds-climb / stamp all still play afterwards and nothing about them had to change.
--
-- WHY THE REAL MODEL AND NOT A STAND-IN: these are Parts, so a clone costs nothing to
-- silhouette (Color black, then tween back). A ViewportFrame would have been cheaper still
-- but it cannot sit IN the world, and the whole point is that the thing comes out of the
-- actual lake the player just threw into.
--
-- FAILS SOFT EVERYWHERE. No SplashPos, no model, no camera -> return false and the caller
-- carries on to the ordinary reveal. A cutscene must never eat a catch.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Sizes = require(ReplicatedStorage.Modules.SizeConfig)
local okKit, SoundKit = pcall(function() return require(ReplicatedStorage.Modules.SoundKit) end)
if not okKit then SoundKit = nil end

local M = {}

-- Per-size drama. Huge gets a brisk version; Massive gets the full hold.
local BEATS = {
	Huge    = { anticipate = 0.55, erupt = 0.30, rise = 1.10, hold = 0.45, shake = 2.0 },
	Massive = { anticipate = 0.90, erupt = 0.40, rise = 1.90, hold = 0.90, shake = 4.0 },
}

local RISE_EASE = TweenInfo.new(1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function playSound(name, vol)
	if SoundKit then pcall(SoundKit.play, name, nil, { volume = vol }) end
end

-- a flat expanding ring on the water surface
local function ring(parent, pos, colour, size, life)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.4, 2, 2)
	p.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	p.Color = colour; p.Material = Enum.Material.Neon
	-- starts already half-faded and dies to nothing: a cylinder is a FILLED disc, so a
	-- solid one reads as a pink pancake on the lake rather than a shockwave ring
	p.Transparency = 0.55
	p.Parent = parent
	TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.4, size, size),
		Transparency = 1,
	}):Play()
	Debris:AddItem(p, life + 0.1)
	return p
end

-- the column of light the creature rises inside
local function pillar(parent, pos, colour, height, radius)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(height, radius, radius)
	p.CFrame = CFrame.new(pos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	p.Color = colour; p.Material = Enum.Material.Neon
	p.Transparency = 1
	p.Parent = parent
	return p
end

-- Plays the cutscene. Returns true if it actually ran, false if it declined -- the caller
-- uses that to decide whether to add its own delay before the ordinary reveal.
function M.play(result)
	local size = result and result.Size
	local beats = size and BEATS[size]
	if not beats then return false end

	local splash = result.SplashPos
	if typeof(splash) ~= "Vector3" then return false end

	local template = ReplicatedStorage:FindFirstChild("BrainrotModels")
	template = template and template:FindFirstChild(result.Name)
	if not template then return false end

	local cam = Workspace.CurrentCamera
	if not cam then return false end

	local colour = result.RarityColor or Color3.fromRGB(255, 255, 255)
	local sizeColour = Sizes.Color(size) or colour

	local stage = Instance.new("Folder")
	stage.Name = "MassiveEmergenceStage"
	stage.Parent = Workspace

	-- Build the creature at the size it will actually be, sunk under the surface.
	local model = template:Clone()
	local _, extents = model:GetBoundingBox()
	local hs = math.clamp(template:GetAttribute("HeightScale") or 1, 0.7, 1.5)
	local width = math.max(extents.X, extents.Z)
	local fit = math.min((6.0 * hs) / extents.Y, 9.5 / math.max(width, 0.01)) * Sizes.Scale(size)
	model:ScaleTo(model:GetScale() * fit)
	local _, finalSize = model:GetBoundingBox()

	-- silhouette: remember every colour, then black everything out
	local originalColour = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false
			originalColour[d] = d.Color
			d.Color = Color3.fromRGB(6, 8, 12)
		end
	end
	model.Parent = stage

	local below = splash - Vector3.new(0, finalSize.Y * 1.05, 0)
	local above = splash + Vector3.new(0, finalSize.Y * 0.5 - finalSize.Y * 0.08, 0)
	local function placeAt(pos, yaw)
		local cf, _ = model:GetBoundingBox()
		model:PivotTo(model:GetPivot() * CFrame.Angles(0, yaw, 0) + (pos - cf.Position))
	end
	placeAt(below, 0)

	-- === B1 ANTICIPATION: cut to the water, glow the tier colour before anything shows ===
	-- NEVER hand back Scriptable (2026-08-09). ClientMain's stone-tracking camera holds
	-- CameraType = Scriptable from flight start until landing + 1.4s -- i.e. straight
	-- through the moment this cutscene starts on a real catch. Saving that and restoring
	-- it at the end parks the player in a frozen camera out at the landing point,
	-- permanently, because the tracking camera's own restore already fired mid-cutscene.
	-- Measured on a real forced-Huge throw: camera stranded Scriptable 884 studs away.
	-- The same reveal fabricated with no tracking camera restored fine, which is what
	-- isolated it. Custom is the only correct terminal state: this cutscene always ends
	-- by giving the player their camera back.
	-- ACCEPTED TRADE (parked): if a SECOND Massive's emergence fallback fires while a
	-- Sequencer cut is already running, this forces Custom at the end and cuts the
	-- running cut's last ~6s short. Needs two Massives inside 10.7s, and the terminal
	-- state stays recoverable -- strictly better than the frozen camera it prevents.
	local prevType, prevCF = cam.CameraType, cam.CFrame
	if prevType == Enum.CameraType.Scriptable then
		prevType = Enum.CameraType.Custom
	end
	cam.CameraType = Enum.CameraType.Scriptable
	-- Framed so the creature FILLS the shot. The first cut sat 1.9x its width away and it
	-- read as a small thing in a big lake -- the opposite of the intent.
	local viewDist = math.max(finalSize.X, finalSize.Z) * 1.15 + 10
	local eye = splash + Vector3.new(viewDist * 0.72, finalSize.Y * 0.42 + 4, viewDist * 0.72)
	cam.CFrame = CFrame.lookAt(eye, splash + Vector3.new(0, finalSize.Y * 0.34, 0))

	-- The pillar FRAMES the creature, it must not paint over it. A wide Neon cylinder at
	-- 0.82 washed the whole model in tier colour and buried the silhouette, so it is now
	-- narrower than the body and nearly clear -- read as a shaft of light behind it.
	local glow = pillar(stage, splash, colour, finalSize.Y * 2.2, math.max(finalSize.X, finalSize.Z) * 0.42)
	TweenService:Create(glow, TweenInfo.new(beats.anticipate), { Transparency = 0.93 }):Play()
	ring(stage, splash, colour, math.max(finalSize.X, finalSize.Z) * 1.6, beats.anticipate + 0.2)
	playSound("catchDrama", 0.5)
	task.wait(beats.anticipate)

	-- === B2 ERUPTION: geyser, rings, shake, bass ===
	playSound("catchBigHit", 0.75)
	for i = 1, 3 do
		ring(stage, splash, i % 2 == 0 and sizeColour or colour,
			math.max(finalSize.X, finalSize.Z) * (1.8 + i * 0.9), beats.erupt + 0.5 + i * 0.12)
	end
	local shakeUntil = os.clock() + beats.erupt + beats.rise * 0.5
	local shakeConn
	shakeConn = RunService.RenderStepped:Connect(function()
		if os.clock() > shakeUntil then shakeConn:Disconnect() return end
		local k = beats.shake * 0.06
		cam.CFrame = cam.CFrame * CFrame.new((math.random() - 0.5) * k, (math.random() - 0.5) * k, 0)
	end)
	task.wait(beats.erupt)

	-- === B3 THE RISE: the creature comes out of the water, turning ===
	local t0 = os.clock()
	local riseConn
	riseConn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - t0) / beats.rise, 0, 1)
		-- quint-out: bursts up, then settles
		local e = 1 - (1 - a) ^ 5
		placeAt(below:Lerp(above, e), a * math.pi * 1.25)
		if a >= 1 then riseConn:Disconnect() end
	end)
	task.wait(beats.rise)
	if riseConn.Connected then riseConn:Disconnect() end

	-- colours snap on at full height -- the moment it stops being a shape and becomes a thing
	playSound("catchBigHit", 0.55)
	for part, c in pairs(originalColour) do
		if part.Parent then
			TweenService:Create(part, TweenInfo.new(0.22), { Color = c }):Play()
		end
	end
	TweenService:Create(glow, TweenInfo.new(beats.hold), { Transparency = 1 }):Play()
	task.wait(beats.hold)

	-- hand the camera back exactly as found, then let the ordinary reveal run
	if shakeConn.Connected then shakeConn:Disconnect() end
	cam.CameraType = prevType
	cam.CFrame = prevCF
	stage:Destroy()
	return true
end

return M
