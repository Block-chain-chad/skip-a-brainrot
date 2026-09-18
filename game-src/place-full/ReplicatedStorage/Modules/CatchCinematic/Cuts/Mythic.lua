--!strict
-- CatchCinematic.Cuts.Mythic -- POWER. 1.7s, not skippable. The water erupts and
-- the creature explodes out of the splash in a red energy burst (spec S6.1).
local folder = script.Parent.Parent
local Config = require(folder:WaitForChild("Config"))
local CutKit = require(folder:WaitForChild("CutKit"))
local Types = require(folder:WaitForChild("Types"))
local Shared = require(script.Parent:WaitForChild("Shared"))
type Run = Types.Run

local Mythic = {}

-- ===== TUNABLES (spec S6.1) =====
Mythic.BEATS = {
	{ name = "bonk",     t0 = 0.00, t1 = 0.15 },  -- UI hidden; local "slow" = FOV tighten + duck
	{ name = "ripple",   t0 = 0.15, t1 = 0.25 },  -- deep bass, ripple expands
	{ name = "eruption", t0 = 0.25, t1 = 0.50 },  -- REVEAL: erupt, breach, red ring, flash, shake
	{ name = "settle",   t0 = 0.50, t1 = 0.60 },
	{ name = "banner",   t0 = 0.60, t1 = 1.50 },  -- MYTHIC; red rim + particles; float
	{ name = "handoff",  t0 = 1.50, t1 = 1.70 },
}
Mythic.RED = Color3.fromRGB(255, 50, 50)
Mythic.TIGHT_FOV = 58
Mythic.RING_RADIUS_MULT = 2.2   -- x the creature's largest horizontal extent

local function enterBonk(run: Run)
	if run.water then
		run.water:stillWater()
		run.water:bonkRing()
	end
	if run.audio then
		run.audio:play("finalSkip", { where = run.surface })
		if not run.spectator then
			run.audio:duckAmbient(0.25, 0.12 * run.stretch)
		end
	end
	if run.cam then
		-- the "gameplay slows" read, done locally: a tighten toward the water
		run.cam:punchFOV(Mythic.TIGHT_FOV, Config.CAMERA.fovBase or 70, 0.5 * run.stretch)
		local eye, focus = CutKit.heroFraming(run)
		run.heroEye, run.heroFocus = eye, focus
		run.cam:flyTo(CFrame.lookAt(eye, focus), 0.25 * run.stretch, true)
	end
end

local function enterRipple(run: Run)
	if run.audio then
		run.audio:play("mythicBass", { where = run.surface })
	end
end

local function updateRipple(run: Run, p: number)
	if run.water then
		run.water:rippleTrain(p)
	end
end

local function enterEruption(run: Run)
	if run.brain then
		Shared.faceCamera(run)
		run.brain:markBreached()
		run.breached = true
		run.brain:revealColors(0.15 * run.stretch)
	end
	if run.water then
		run.water:erupt(run.extents)
		local ext = run.extents :: Vector3
		run.water:shockRing(Mythic.RED, math.max(ext.X, ext.Z) * Mythic.RING_RADIUS_MULT, 0.45 * run.stretch)
	end
	Shared.rimHighlight(run, Mythic.RED)
	if run.post then
		run.post:flash()
	end
	if run.audio then
		run.audio:play("waterExplosion", { where = run.surface })
	end
	if run.shake then
		run.shake:add(1.0)
	end
	if run.cam and run.heroEye then
		run.cam:lookHover(run.heroEye, run.heroFocus)
	end
end

local function updateEruption(run: Run, p: number)
	if run.brain and not run.skipping then
		run.brain:setRise(p)
	end
end

local function enterSettle(run: Run)
	if run.brain then
		run.brain:setRise(1)
	end
	if run.shake then
		run.shake:setSustain(0.08)
	end
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
		run.shake:add(0.25)
	end
end

local function updateBanner(run: Run, p: number)
	-- small float on the creature; the rim stays red for the whole beat
	if run.brain and not run.skipping then
		run.brain:setRise(1 - 0.02 * math.sin(p * math.pi * 2))
	end
end

Mythic.handlers = {
	bonk     = { enter = enterBonk },
	ripple   = { enter = enterRipple, update = updateRipple },
	eruption = { enter = enterEruption, update = updateEruption },
	settle   = { enter = enterSettle },
	banner   = { enter = enterBanner, update = updateBanner },
	handoff  = Shared.handoff,
}
Mythic.everyFrame = Shared.everyFrameRock
Mythic.build = function(run: Run): boolean
	return Shared.build(run, nil)
end
Mythic.name = "Mythic"
Mythic.beats = Mythic.BEATS
Mythic.revealBeat = "eruption"
Mythic.skippable = false
Mythic.bannerText = "MYTHIC"

return Mythic
