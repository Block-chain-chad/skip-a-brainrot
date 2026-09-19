-- RodFxClient -- draws the ice-fishing rod's water FX at RENDER RATE.
--
-- WHY THIS EXISTS. The splash when a float lands and the duck when a fish takes it used
-- to be TweenService calls inside RodService, on the server, against ANCHORED parts. A
-- server tween on an anchored part does not replicate as a tween: it replicates as CFrame
-- writes at roughly 20Hz with nothing interpolating between them, so a 0.16s bobber duck
-- arrives as about three steps and a 0.75s ripple grow as about fifteen. Both read as a
-- stutter. This is the identical defect the thrown rock had ("when i go to throw a rock
-- its very chopped", 2026-08-10) and it gets the identical fix ClientMain used there --
-- the server keeps the authority and every client draws the motion locally.
--
-- FIRED AT EVERY CLIENT, not just the caster, so a second player standing at the hole
-- still sees the take. Each one tweens the bobber it already has replicated; a client
-- moving an anchored part locally does not replicate back, and the server no longer
-- writes those CFrames, so the two cannot fight. Purely cosmetic -- the catch is decided
-- in IceFishingEvent, and a client that never received this simply sees no splash.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- WATER AUDIO. These belong here rather than in IceFishingClient because they are world
-- events, not private UI feedback -- a second player standing at the hole should hear
-- your float land and hear the fish take it. Parented to the Bobber, so they carry
-- position and roll off with distance the way ThrowHandler's skip splashes do.
-- `splash` is the same 0.39s id the thrown rock uses for a skip.
local SoundKit = require(game:GetService("ReplicatedStorage").Modules:WaitForChild("SoundKit"))
local SPLASH_VOL, TUG_VOL, TUG_PITCH = 0.30, 0.22, 1.25

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local fxRemote = remotes:WaitForChild("RodFx", 30)
if not fxRemote then return end

local LINE_NAME = "CastLine"

-- A ring on the water that grows and fades: what the float landing and each bite tug
-- actually read as from standing height. Parented to the CastLine model so it is torn
-- down with the line rather than outliving the cast.
local function ripple(parent, pos)
	if not parent or not parent.Parent then return end
	local r = Instance.new("Part")
	r.Name = "Ripple"
	r.Anchored = true
	r.CanCollide = false; r.CanQuery = false; r.CanTouch = false
	r.Size = Vector3.new(1.2, 0.08, 1.2)
	r.CFrame = CFrame.new(pos)
	r.Color = Color3.fromRGB(198, 226, 242)
	r.Material = Enum.Material.SmoothPlastic
	r.Transparency = 0.35
	Instance.new("CylinderMesh").Parent = r
	r.Parent = parent
	TweenService:Create(r, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(9, 0.08, 9), Transparency = 1,
	}):Play()
	task.delay(0.85, function() if r.Parent then r:Destroy() end end)
end

local function tug(folder)
	local bob = folder:FindFirstChild("Bobber")
	local stem = folder:FindFirstChild("BobberStem")
	if not bob or not stem then return end
	local bobHome, stemHome = bob.CFrame, stem.CFrame
	local down = CFrame.new(0, -0.55, 0)
	local info = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 2, true)
	TweenService:Create(bob, info, { CFrame = bobHome * down }):Play()
	TweenService:Create(stem, info, { CFrame = stemHome * down }):Play()
	ripple(folder, bob.Position)
	task.delay(0.34, function()
		if folder.Parent and bob.Parent then ripple(folder, bob.Position) end
	end)
end

fxRemote.OnClientEvent:Connect(function(character, kind, pos)
	if typeof(character) ~= "Instance" then return end
	local folder = character:FindFirstChild(LINE_NAME)
	if not folder then return end
	local bob = folder:FindFirstChild("Bobber")
	if kind == "tug" then
		tug(folder)
		-- smaller and higher than the cast: the float ducking under, not hitting the water
		if bob then SoundKit.play("splash", bob, { volume = TUG_VOL, speed = TUG_PITCH }) end
	elseif kind == "ripple" and typeof(pos) == "Vector3" then
		ripple(folder, pos)
		if bob then SoundKit.play("splash", bob, { volume = SPLASH_VOL }) end
	end
end)
