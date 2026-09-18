--!strict
-- CatchCinematic.Cuts.Massive -- THE BEAST. The Massive catch cinematic's beat table,
-- handlers and rig construction (spec S6.5, re-paced to the owner's blueprint
-- 2026-09-17). Conducted by Takeover; this module never touches Camera.CameraType,
-- ScreenGui.Enabled or Lighting -- it drives run.cam / run.post.
--
-- Emotional progression: final skip -> quiet/dread -> increasingly disturbed water ->
-- underwater silhouette/eyes -> slow physical emergence -> huge splash -> camera
-- pulls far enough back to establish the enormous scale -> MASSIVE -> aftermath ->
-- restore. Intimidating, not comedic: no meme layer, no second bonk.
local Workspace = game:GetService("Workspace")

local folder = script.Parent.Parent
local Config = require(folder:WaitForChild("Config"))
local CutKit = require(folder:WaitForChild("CutKit"))
local Types = require(folder:WaitForChild("Types"))
local WaterFX = require(folder:WaitForChild("WaterFX"))
local RockRig = require(folder:WaitForChild("RockRig"))
local BrainrotRig = require(folder:WaitForChild("BrainrotRig"))
type Run = Types.Run

local Massive = {}

-- ===== TUNABLES (this cut's own; spec S6.5) =====
-- t = 0 is the final skip contact. Dread (still -> silhouette) ~2.6s; emergence +
-- pull-back ~3.4s; total 10.6s.
Massive.BEATS = {
	{ name = "bonk",       t0 = 0.00, t1 = 0.50 },  -- I   the rock; camera starts toward the water
	{ name = "still",      t0 = 0.50, t1 = 1.00 },  -- II  nothing
	{ name = "ripple",     t0 = 1.00, t1 = 2.00 },  -- II  tiny ripple, then bigger
	{ name = "disturbed",  t0 = 2.00, t1 = 2.50 },  -- II  violent water, rumble
	{ name = "silhouette", t0 = 2.50, t1 = 3.10 },  -- III darkens; silhouette, eyes
	{ name = "emergence",  t0 = 3.10, t1 = 4.10 },  -- IV  slow rise, huge splash
	{ name = "scale",      t0 = 4.10, t1 = 6.50 },  -- V   camera pulls WAY back
	{ name = "banner",     t0 = 6.50, t1 = 7.20 },  -- VI  MASSIVE
	{ name = "aftermath",  t0 = 7.20, t1 = 9.50 },  -- VII settle
	{ name = "handoff",    t0 = 9.50, t1 = 10.60 }, -- VII streak into bag; restore
}
Massive.EMERGENCE_RISE_TO = 0.5     -- fraction of the rise done by the end of `emergence`
Massive.RIPPLE_SLOW_FRAC = 0.35     -- ripple beat: how far the train gets by its end
Massive.SHADOW_AT_SILHOUETTE = 1.0  -- suctionAndShadow progress reached by the silhouette's end

-- ===== helpers =====
local function calmAngry(run: Run)
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

-- Aim the creature so the rise's slow turn (0.6*pi inside setRise) lands square on
-- the camera.
local function faceCamera(run: Run)
	if not run.brain then
		return
	end
	if run.heroEye == nil then
		local eye, focus = CutKit.heroFraming(run)
		run.heroEye, run.heroFocus = eye, focus
	end
	local aim = (run.heroEye or (run.surface + run.horiz * -40)) - run.surface
	run.brain:setFacing(math.atan2(aim.X, aim.Z) - math.pi * 0.6)
end

-- ===== beat handlers =====
local function enterBonk(run: Run)
	if run.water then
		run.water:stillWater()
		run.water:bonkRing()
	end
	if run.audio then
		run.audio:play("finalSkip", { where = run.surface })
		if not run.spectator then
			run.audio:duckAmbient(0.35, 0.25 * run.stretch)
		end
	end
	if run.shake then
		run.shake:add(0.35)
	end
	if run.cam then
		local c = Config.CAMERA
		local eye = run.surface - run.horiz * CutKit.TRAVEL_BACK_STUDS + Vector3.new(0, c.outboundHeight or 6, 0)
		run.travelEye = eye
		-- the fly-out spans bonk + still: up to the ripple beat
		local secs = CutKit.beatT0(run, "ripple", 1.0) * run.stretch
		run.cam:flyTo(CFrame.lookAt(eye, run.surface), secs, true)
	end
end

local function enterStill(run: Run)
	-- Nothing. Glassy water is the beat.
end

local function updateRipple(run: Run, p: number)
	if run.water then
		run.water:rippleTrain(p * Massive.RIPPLE_SLOW_FRAC)
	end
end

local function enterDisturbed(run: Run)
	if run.audio then
		-- speed = run.speed so a debug timescale pitches the build instead of letting
		-- a 1x clip bleed over the silhouette.
		run.audio:play("massiveRumble", { where = run.surface, speed = run.speed })
	end
	if run.cam then
		local eye = run.travelEye or (run.surface - run.horiz * CutKit.TRAVEL_BACK_STUDS + Vector3.new(0, 6, 0))
		run.cam:lookHover(eye, run.surface)
	end
end

local function updateDisturbed(run: Run, p: number)
	if run.water then
		run.water:rippleTrain(Massive.RIPPLE_SLOW_FRAC + p * (1 - Massive.RIPPLE_SLOW_FRAC))
		run.water:suctionAndShadow(p * 0.5)
	end
	if run.shake then
		run.shake:setSustain((Config.SHAKE.dreadRampTo or 0.4) * p)
	end
end

local function enterSilhouette(run: Run)
	if run.brain then
		run.brain:stageBelow()
		faceCamera(run)
		-- glowing eyes under the surface where the model has eye parts; the aura rim
		-- carries the read for the models that don't (enterEmergence).
		run.eyesApplied = run.brain:angryEyes()
	end
end

local function updateSilhouette(run: Run, p: number)
	if run.water then
		run.water:suctionAndShadow(0.5 + p * 0.5 * Massive.SHADOW_AT_SILHOUETTE)
	end
	if run.shake then
		run.shake:setSustain((Config.SHAKE.dreadRampTo or 0.4) + 0.2 * p)
	end
end

local function enterEmergence(run: Run)
	if run.water then
		run.water:erupt(run.extents)
	end
	if run.brain then
		run.brain:markBreached()
		run.breached = true
	end
	if run.model then
		pcall(function()
			local rim = Instance.new("Highlight")
			rim.Name = "CinematicAura"
			rim.FillTransparency = 1
			rim.OutlineColor = run.eyesApplied and run.rarityColor or Color3.fromRGB(255, 45, 25)
			rim.OutlineTransparency = 0.25
			rim.DepthMode = Enum.HighlightDepthMode.Occluded
			rim.Parent = run.model
		end)
	end
	if run.post then
		run.post:flash()
	end
	if run.audio then
		run.audio:play("bassDrop", { where = run.surface })
		run.audio:play("waterExplosion", { where = run.surface })
		run.audio:play("massiveRoar", { where = run.surface })
	end
	if run.shake then
		run.shake:add(Config.SHAKE.eruption or 1.0)
	end
	if run.cam then
		local c = Config.CAMERA
		run.cam:punchFOV(c.fovPunchHi or 95, c.fovBase or 70, 0.45 * run.stretch)
		local eye, focus = CutKit.heroFraming(run)
		run.heroEye, run.heroFocus = eye, focus
		run.cam:lookHover(eye, focus)
	end
end

local function updateEmergence(run: Run, p: number)
	if run.brain and not run.skipping then
		run.brain:setRise(p * Massive.EMERGENCE_RISE_TO)
	end
end

local function enterScale(run: Run)
	if run.brain then
		run.brain:revealColors(0.6 * run.stretch)
	end
	if run.water and run.model then
		run.water:cascade(run.model, run.waterCfg.cascadeSeconds or 2.0)
	end
	if run.shake then
		run.shake:setSustain(Config.SHAKE.riseSustain or 0.10)
	end
	if run.cam then
		-- THE PULL-BACK: fly from the hero framing to the far framing over the whole
		-- beat, so the creature keeps growing in the frame as the camera retreats.
		local eye, focus = CutKit.farFraming(run)
		run.farEye, run.farFocus = eye, focus
		run.cam:flyTo(CFrame.lookAt(eye, focus), CutKit.beatSeconds(run), false)
	end
end

local function updateScale(run: Run, p: number)
	if run.brain and not run.skipping then
		run.brain:setRise(Massive.EMERGENCE_RISE_TO + p * (1 - Massive.EMERGENCE_RISE_TO))
	end
end

local function enterBanner(run: Run)
	calmAngry(run)
	if run.hype then
		run.hype:banner(run.cut.bannerText, run.rarityColor)
		run.hype:nameText(run.displayName)
	end
	if run.audio then
		run.audio:play("bannerHit", { where = run.surface })
	end
	if run.shake then
		run.shake:add(0.3)
	end
	if run.cam and run.farEye then
		run.cam:lookHover(run.farEye, run.farFocus)
	end
end

local function enterAftermath(run: Run)
	if run.shake then
		run.shake:setSustain(0.04)
	end
	if run.cam and run.farFocus then
		local ext = run.extents :: Vector3
		local dist = (run.farEye - run.farFocus).Magnitude
		run.cam:orbit(run.farFocus, 18, CutKit.beatSeconds(run), dist, ext.Y * (Config.CAMERA.farHeightFrac or 0.35))
	end
end

local function enterHandoff(run: Run)
	calmAngry(run)
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

Massive.handlers = {
	bonk       = { enter = enterBonk },
	still      = { enter = enterStill },
	ripple     = { update = updateRipple },
	disturbed  = { enter = enterDisturbed, update = updateDisturbed },
	silhouette = { enter = enterSilhouette, update = updateSilhouette },
	emergence  = { enter = enterEmergence, update = updateEmergence },
	scale      = { enter = enterScale, update = updateScale },
	banner     = { enter = enterBanner },
	aftermath  = { enter = enterAftermath },
	handoff    = { enter = enterHandoff, update = updateHandoff },
}

function Massive.everyFrame(run: Run)
	if run.rock then
		run.rock:update(run.t)
	end
end

-- Skip lands on `banner`: everything the skipped beats would have left behind, set
-- directly under the darkest frame of the dip. Never a hard cut.
function Massive.onSkip(run: Run)
	if run.hype then
		run.hype:interrupt()
		run.hype:hideSkipPrompt()
	end
	if run.water then
		run.water:cleanup()
	end
	calmAngry(run)
	if run.brain then
		run.brain:markBreached()
		run.breached = true
		run.brain:setRise(1)
		run.brain:revealColors(0.05)
	end
	if run.shake then
		run.shake:setSustain(0)
	end
	if run.audio then
		run.audio:unsilence()
	end
	if run.post then
		run.post:easeBack(0.2)
	end
	if run.cam then
		local eye, focus = CutKit.farFraming(run)
		run.farEye, run.farFocus = eye, focus
		run.cam:lookHover(eye, focus)
	end
end

function Massive.build(run: Run): boolean
	local stage = run.stage :: Folder
	local brain = BrainrotRig.new(stage, run.name, run.size or "Massive", run.surface)
	if not brain then
		warn("[Cuts.Massive] declining: no model for '" .. tostring(run.name) .. "'")
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

Massive.calmAngry = calmAngry
Massive.faceCamera = faceCamera
Massive.name = "Massive"
Massive.beats = Massive.BEATS
Massive.revealBeat = "emergence"
Massive.skippable = true
Massive.skipTo = "banner"
Massive.bannerText = "MASSIVE"

return Massive
