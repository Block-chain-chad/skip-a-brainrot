-- CameraWatchdog -- last-resort rescue for a camera nobody is driving.
--
-- WHY THIS EXISTS. Five separate systems take the camera in this game: the throw
-- tracking camera in ClientMain, CatchReveal, MassiveEmergence, CameraRig (the Massive
-- catch cinematic) and CaveDrillClient. Each sets CameraType = Scriptable, drives
-- CFrame from a render step, and restores on its own schedule. Every one of them
-- already coerces a saved Scriptable back to Custom, so the obvious handoff bugs are
-- covered -- but with five owners and overlapping timers, ANY missed restore (an
-- error thrown mid-teardown, a disconnect that never fires, a coroutine killed by a
-- respawn) strands the camera as Scriptable with no writer. The player is then stuck
-- staring at wherever it was last parked, usually out at a rock's landing point, with
-- no way back except rejoining.
--
-- Rather than keep hunting individual races, this watches for the terminal state
-- itself: Scriptable, and NOT MOVING. A live cinematic moves the camera every frame,
-- so a still Scriptable camera means whoever owned it is gone.
--
-- THRESHOLD. The longest legitimate takeover is the Massive catch cut at ~10.7s, and
-- that one is in constant motion anyway. 6 seconds of a completely motionless
-- Scriptable camera is far outside anything the game does on purpose.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local STILL_SECONDS = 6.0      -- motionless-and-Scriptable before we step in
local MOVE_EPSILON  = 0.05     -- studs; below this the camera counts as parked
local CHECK_EVERY   = 0.5

local stillFor = 0
local lastPos = nil
local rescues = 0

local function rescue(cam)
	local char = player.Character
	local hum = char and char:FindFirstChildWhichIsA("Humanoid")
	-- Custom with a dead subject is still a dead camera, so fix the subject FIRST.
	local subj = cam.CameraSubject
	if hum and (subj == nil or not subj:IsDescendantOf(Workspace)) then
		cam.CameraSubject = hum
	end
	cam.CameraType = Enum.CameraType.Custom
	rescues = rescues + 1
	warn(("[CameraWatchdog] camera was Scriptable and motionless for %.0fs with no owner -- "
		.. "restored to Custom (rescue #%d). If this fires in normal play, some camera "
		.. "owner is failing to restore."):format(STILL_SECONDS, rescues))
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < CHECK_EVERY then return end
	local step = acc
	acc = 0

	local cam = Workspace.CurrentCamera
	if not cam then return end

	if cam.CameraType ~= Enum.CameraType.Scriptable then
		stillFor = 0
		lastPos = nil
		return
	end

	local pos = cam.CFrame.Position
	if lastPos and (pos - lastPos).Magnitude < MOVE_EPSILON then
		stillFor += step
		if stillFor >= STILL_SECONDS then
			rescue(cam)
			stillFor = 0
			lastPos = nil
		end
	else
		stillFor = 0
	end
	lastPos = pos
end)

-- A respawn should never leave the player looking at the old scene.
player.CharacterAdded:Connect(function(char)
	task.wait(0.35)   -- let the default camera script take its turn first
	local cam = Workspace.CurrentCamera
	if cam and cam.CameraType == Enum.CameraType.Scriptable then
		local hum = char:FindFirstChildWhichIsA("Humanoid")
		if hum then cam.CameraSubject = hum end
		cam.CameraType = Enum.CameraType.Custom
		warn("[CameraWatchdog] camera was still Scriptable after respawn -- restored to Custom")
	end
	stillFor = 0
	lastPos = nil
end)

print("CameraWatchdog online (rescues a Scriptable camera left motionless for "
	.. STILL_SECONDS .. "s, and after any respawn)")
