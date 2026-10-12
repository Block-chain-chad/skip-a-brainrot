--!strict
-- CatchCinematic.Cuts.Mythic -- POWER. ~2.1s, not skippable.
--
-- REBUILT 2026-09-21 (reward-pacing pass). The first build had the creature simply
-- appear inside a glass eruption column under a flat red disc, with a 0.2s handoff
-- that snapped the camera home mid-blend. The new shape:
--
--   the result resolves -> the music ducks -> a very short tension beat (still water,
--   the camera settles on the spot) -> a CONCENTRATED POINT OF ENERGY forms at the
--   surface (sparkles converging, a light growing, a glow under the water, the deep
--   bass) -> a controlled UPWARD PULSE: the creature rises through a fountain of
--   sparks and foam, a ring runs out across the water, one short flash, a shake ->
--   settle, rim-lit in tier red, sparkles orbiting to FRAME it -> MYTHIC and the name
--   -> streak into the bag with the HUD returning under the camera's glide home.
--
-- No column around the creature, no disc, nothing covering it: the brainrot is the
-- reward and is visible from the first frame of its rise to the last frame of the cut.
local folder = script.Parent.Parent
local Config = require(folder:WaitForChild("Config"))
local CutKit = require(folder:WaitForChild("CutKit"))
local Types = require(folder:WaitForChild("Types"))
local AuraFX = require(folder:WaitForChild("AuraFX"))
local Shared = require(script.Parent:WaitForChild("Shared"))
type Run = Types.Run

local Mythic = {}

-- ===== TUNABLES (owner brief 2026-09-21, target 1.7-2.2s) =====
Mythic.BEATS = {
	{ name = "bonk",    t0 = 0.00, t1 = 0.22 },  -- result resolves; music ducks; camera settles; still water
	{ name = "gather",  t0 = 0.22, t1 = 0.62 },  -- energy point forms; deep bass
	{ name = "burst",   t0 = 0.62, t1 = 0.92 },  -- REVEAL: upward pulse, the creature rises through it
	{ name = "settle",  t0 = 0.92, t1 = 1.02 },
	{ name = "banner",  t0 = 1.02, t1 = 1.72 },  -- MYTHIC + name; rim + framing sparkles; float
	{ name = "handoff", t0 = 1.72, t1 = 2.12 },  -- streak into bag; HUD back; camera home
}
Mythic.RED = Color3.fromRGB(255, 50, 50)
Mythic.TIGHT_FOV = 62
Mythic.RING_RADIUS_MULT = 1.9   -- x the creature's largest horizontal extent
Mythic.DIM = Color3.fromRGB(196, 190, 204)   -- restrained environment dim (a cool tint, not a blackout)

local function enterBonk(run: Run)
	if run.water then
		run.water:stillWater()
		run.water:bonkRing()
	end
	if run.audio then
		run.audio:play("finalSkip", { where = run.surface })
		if not run.spectator then
			run.audio:duckAmbient(Config.MUSIC_DUCK.Mythic or 0.25, 0.18 * run.stretch)
		end
	end
	if run.post then
		run.post:tint(Mythic.DIM, 0.3 * run.stretch)
	end
	if run.cam then
		-- the "gameplay slows" read, done locally: a tighten toward the water
		run.cam:punchFOV(Mythic.TIGHT_FOV, Config.CAMERA.fovBase or 70, 0.9 * run.stretch)
		local eye, focus = CutKit.heroFraming(run)
		run.heroEye, run.heroFocus = eye, focus
		-- from wherever the stone camera parked (ThrowCam's handoff), a short settle
		-- that finishes during the gather; nothing re-targets the camera until the burst
		run.cam:flyTo(CFrame.lookAt(eye, focus), 0.45 * run.stretch, false)
	end
end

local function enterGather(run: Run)
	local ext = run.extents :: Vector3
	if run.water then
		run.water:energyPoint(Mythic.RED, math.max(math.max(ext.X, ext.Z) * 0.9, 4), CutKit.beatSeconds(run))
	end
	if run.audio then
		run.audio:play("mythicBass", { where = run.surface })
	end
	if run.shake then
		run.shake:setSustain(0.05)
	end
end

local function updateGather(run: Run, p: number)
	if run.water then
		run.water:rippleTrain(p * 0.6)
	end
end

local function enterBurst(run: Run)
	if run.brain then
		Shared.faceCamera(run)
		run.brain:markBreached()
		run.breached = true
		run.brain:revealColors(0.12 * run.stretch)
	end
	if run.water then
		run.water:pulseUp(Mythic.RED, run.extents)
		local ext = run.extents :: Vector3
		run.water:shockRing(Mythic.RED, math.max(ext.X, ext.Z) * Mythic.RING_RADIUS_MULT, 0.5 * run.stretch)
	end
	Shared.rimHighlight(run, Mythic.RED)
	if run.post then
		run.post:flash()
	end
	if run.audio then
		run.audio:play("waterExplosion", { where = run.surface })
	end
	if run.shake then
		run.shake:add(0.7)
	end
	if run.cam and run.heroEye then
		-- the settle flight has landed on this exact pose: hover adds only its breath
		run.cam:lookHover(run.heroEye, run.heroFocus)
	end
end

local function updateBurst(run: Run, p: number)
	if run.brain and not run.skipping then
		-- ease-out rise: fast off the water, settling into the hover
		run.brain:setRise(1 - (1 - p) ^ 2)
	end
end

local function enterSettle(run: Run)
	if run.brain then
		run.brain:setRise(1)
	end
	if run.shake then
		run.shake:setSustain(0.06)
	end
	-- sparkles orbiting the creature: frame it, never cover it (AuraFX with no disc)
	local ext = run.extents :: Vector3
	local centre = run.surface + Vector3.new(0, ext.Y * 0.5, 0)
	local aura = AuraFX.new(run.stage, centre, Mythic.RED, math.max(ext.X, ext.Y, ext.Z) * 0.75, run.quality, run.rng, { disc = false })
	run.aura = aura
	CutKit.track(run, function()
		aura:cleanup()
	end)
end

local function enterBanner(run: Run)
	if run.hype then
		run.hype:banner(run.cut.bannerText, Mythic.RED)
		run.hype:nameText(run.displayName)
	end
	if run.audio then
		run.audio:play("bannerHit", { where = run.surface })
	end
	if run.shake then
		run.shake:add(0.22)
	end
end

local function updateBanner(run: Run, p: number)
	-- small float on the creature; the rim stays red for the whole beat
	if run.brain and not run.skipping then
		run.brain:setRise(1 - 0.02 * math.sin(p * math.pi * 2))
	end
	if run.aura then
		run.aura:update(run.t, 1)
	end
end

local function exitBanner(run: Run)
	if run.aura then
		run.aura:fade(0.3 * run.stretch)
	end
end

Mythic.handlers = {
	bonk    = { enter = enterBonk },
	gather  = { enter = enterGather, update = updateGather },
	burst   = { enter = enterBurst, update = updateBurst },
	settle  = { enter = enterSettle },
	banner  = { enter = enterBanner, update = updateBanner, exit = exitBanner },
	handoff = Shared.handoff,
}
Mythic.everyFrame = Shared.everyFrameRock
Mythic.build = function(run: Run): boolean
	return Shared.build(run, nil)
end
Mythic.onCancel = function(run: Run)
	if run.aura then
		run.aura:cleanup()
		run.aura = nil
	end
end
Mythic.name = "Mythic"
Mythic.beats = Mythic.BEATS
Mythic.revealBeat = "burst"
Mythic.skippable = false
Mythic.bannerText = "MYTHIC"

return Mythic
