--!strict
-- CatchCinematic.Cuts.Shared -- handlers and construction every cut needs and no
-- cut owns: the handoff beat (streak into the bag + camera return), the standard
-- build (brain + optional rock + water), and the angry/calm rim helpers. Not a cut.
local Workspace = game:GetService("Workspace")
local folder = script.Parent.Parent
local Config = require(folder:WaitForChild("Config"))
local CutKit = require(folder:WaitForChild("CutKit"))
local Types = require(folder:WaitForChild("Types"))
local WaterFX = require(folder:WaitForChild("WaterFX"))
local RockRig = require(folder:WaitForChild("RockRig"))
local BrainrotRig = require(folder:WaitForChild("BrainrotRig"))
type Run = Types.Run

local Shared = {}

function Shared.calmAngry(run: Run)
	if run.brain then
		run.brain:calmEyes()
	end
	if run.model then
		local rim = run.model:FindFirstChild("CinematicAura")
		if rim and rim:IsA("Highlight") then
			rim.OutlineColor = run.rarityColor
		end
	end
end

-- A rarity/mutation-coloured outline on the creature for the rest of the cut.
-- Parented to the model inside the stage, so every teardown path destroys it.
function Shared.rimHighlight(run: Run, color: Color3)
	if not run.model then
		return
	end
	pcall(function()
		local old = run.model:FindFirstChild("CinematicAura")
		if old then
			old:Destroy()
		end
		local rim = Instance.new("Highlight")
		rim.Name = "CinematicAura"
		rim.FillTransparency = 1
		rim.OutlineColor = color
		rim.OutlineTransparency = 0.25
		rim.DepthMode = Enum.HighlightDepthMode.Occluded
		rim.Parent = run.model
	end)
end

-- Aim the creature so the rise's slow turn (0.6*pi inside setRise) lands square on
-- the camera.
function Shared.faceCamera(run: Run)
	if not run.brain then
		return
	end
	if run.heroEye == nil then
		local eye, focus = CutKit.heroFraming(run)
		run.heroEye, run.heroFocus = eye, focus
	end
	local aim = (run.heroEye or (run.surface + run.horiz * -40)) - run.surface
	-- FACE TO FACE (owner, 2026-09-18). Every roster model is authored facing -Z
	-- (BrainrotThumb's convention, and all 218 template pivots are pure yaws), and
	-- BrainrotRig poses as pivot0 * Angles(0, yaw, 0), so the posed front is
	-- (-sin yaw, 0, -cos yaw): yaw = atan2(-aim.X, -aim.Z) points it AT the camera.
	-- The old atan2(aim.X, aim.Z) pointed it dead away (measured 180 degrees at the
	-- banner on every cut). The 0.6*pi is setRise's part-turn, subtracted here so the
	-- creature finishes its emergence squared up to the player rather than starting so.
	run.brain:setFacing(math.atan2(-aim.X, -aim.Z) - math.pi * 0.6)
end

local function enterHandoff(run: Run)
	Shared.calmAngry(run)
	if run.shake then
		run.shake:setSustain(0)
	end
	if run.hype then
		run.hype:hideSkipPrompt()
	end
	if run.post then
		run.post:easeBack(run.postCfg.easeBackSeconds or 1.2)
	end
	if run.audio then
		run.audio:play("cardWhoosh", run.spectator and { where = run.surface } or nil)
		run.audio:restoreAmbient(0.6 * run.stretch)
	end
	local seconds = CutKit.beatSeconds(run) * 0.42
	if run.spectator then
		return
	end
	if run.brain then
		local target = Vector2.new(0.86, 0.92)
		if run.hype then
			local px = run.hype:bagTarget()
			local cam = Workspace.CurrentCamera
			local vs = cam and cam.ViewportSize or Vector2.new(1280, 720)
			if vs.X > 0 and vs.Y > 0 then
				target = Vector2.new(math.clamp(px.X / vs.X, 0, 1), math.clamp(px.Y / vs.Y, 0, 1))
			end
		end
		run.brain:compressAndStreak(target, seconds, function()
			if run.hype then
				run.hype:cardArrive(run.rarityColor)
			end
		end)
	end
	if run.cam then
		run.cam:returnToPlayer((Config.CAMERA.returnBlendSeconds or 0.8) * run.stretch, nil)
	end
end

local function updateHandoff(run: Run, p: number)
	if run.spectator and run.brain then
		run.brain:setRise(1 - p)
	end
end

Shared.handoff = { enter = enterHandoff, update = updateHandoff }

-- brain (declines when no model) + rock (only when the payload has one -- fishing
-- has none) + water. Cut-specific rigs are built by the cut after this returns.
-- The size handed to the rig is run.size or the cut's default; an unknown/nil size
-- scales 1x (SizeConfig.Scale is nil-safe) and run.size itself is left untouched so
-- the display name never gains a size the grant did not have.
function Shared.build(run: Run, defaultSize: string?): boolean
	local stage = run.stage :: Folder
	-- run.mutation rides in: the creature wears its confirmed mutation from the first
	-- revealed frame (spec S9) -- one MutationFX path for every cut, no per-mutation code.
	local brain = BrainrotRig.new(stage, run.name, run.size or defaultSize or "Normal", run.surface, run.mutation)
	if not brain then
		warn("[Cuts.Shared] declining: no model for '" .. tostring(run.name) .. "'")
		return false
	end
	run.brain = brain
	CutKit.track(run, function()
		brain:cleanup()
	end)
	CutKit.refreshGeometry(run)
	if run.payload.RockId ~= nil then
		local rock = RockRig.new(Config.ROCK, stage, run.payload.RockId, run.payload.RockColor, run.surface, run.rng)
		run.rock = rock
		CutKit.track(run, function()
			rock:cleanup()
		end)
	end
	local water = WaterFX.new(run.waterCfg, Config.PARTICLES, stage, run.surface, run.quality, run.rng)
	run.water = water
	CutKit.track(run, function()
		water:cleanup()
	end)
	return true
end

function Shared.everyFrameRock(run: Run)
	if run.rock then
		run.rock:update(run.t)
	end
end

return Shared
