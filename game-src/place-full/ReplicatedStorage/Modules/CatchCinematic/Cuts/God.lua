--!strict
-- CatchCinematic.Cuts.God -- HEAVEN. 5.0s, skippable to `arrival`. The water glows
-- gold, a beam shoots into the sky, the EXCLUSIVE choir hits, and the creature
-- descends from the light (spec S6.3). The beam/choir/descent/arrival handlers are
-- reused by Cuts.MassiveGod, anchored on run.beamBase when it is set.
local folder = script.Parent.Parent
local Config = require(folder:WaitForChild("Config"))
local CutKit = require(folder:WaitForChild("CutKit"))
local Types = require(folder:WaitForChild("Types"))
local BeamFX = require(folder:WaitForChild("BeamFX"))
local AuraFX = require(folder:WaitForChild("AuraFX"))
local Shared = require(script.Parent:WaitForChild("Shared"))
type Run = Types.Run

local God = {}

-- ===== TUNABLES (spec S6.3) =====
God.BEATS = {
	{ name = "bonk",    t0 = 0.00, t1 = 0.30 },  -- UI hidden; world goes quiet
	{ name = "rumble",  t0 = 0.30, t1 = 0.50 },
	{ name = "glow",    t0 = 0.50, t1 = 0.80 },  -- water glows gold/white; one massive ripple
	{ name = "tilt",    t0 = 0.80, t1 = 1.00 },  -- gold particles rise; camera tilts up
	{ name = "beam",    t0 = 1.00, t1 = 1.30 },  -- beam water->sky; environment gold
	{ name = "choir",   t0 = 1.30, t1 = 2.00 },  -- the exclusive choir; beam holds
	{ name = "descent", t0 = 2.00, t1 = 3.50 },  -- REVEAL: creature descends inside the beam
	{ name = "arrival", t0 = 3.50, t1 = 3.80 },  -- flash, GOD, gold shockwave
	{ name = "linger",  t0 = 3.80, t1 = 4.80 },  -- float; beam fades; choir tails
	{ name = "handoff", t0 = 4.80, t1 = 5.00 },
}
God.GOLD = Color3.fromRGB(255, 226, 120)
God.WHITE_GOLD = Color3.fromRGB(255, 245, 210)
God.BEAM_HEIGHT = 400
God.BEAM_RADIUS_MULT = 0.6     -- x the creature's largest horizontal extent
God.DESCENT_HEIGHT_MULT = 6    -- x the creature's height: where the descent starts
God.TINT = Color3.fromRGB(255, 236, 190)
God.SUNRAYS = 0.35

local function beamBase(run: Run): Vector3
	return run.beamBase or run.surface
end

local function enterBonk(run: Run)
	if run.water then
		run.water:stillWater()
		run.water:bonkRing()
	end
	if run.audio then
		run.audio:play("finalSkip", { where = run.surface })
		if not run.spectator then
			run.audio:silence()
		end
	end
	if run.cam then
		local eye, focus = CutKit.heroFraming(run)
		run.heroEye, run.heroFocus = eye, focus
		run.cam:flyTo(CFrame.lookAt(eye, run.surface), 0.8 * run.stretch, false)
	end
end

local function enterRumble(run: Run)
	if run.audio then
		run.audio:play("godRumble", { where = run.surface, speed = run.speed })
	end
	if run.shake then
		run.shake:setSustain(0.15)
	end
end

local function enterGlow(run: Run)
	if run.water then
		run.water:glowBelow(God.WHITE_GOLD, CutKit.beatSeconds(run))
		run.water:rippleTrain(1)
	end
end

local function enterTilt(run: Run)
	if run.cam then
		-- skyward framing: low eye, looking up the beam line
		local ext = run.extents :: Vector3
		local eye = run.surface - run.horiz * (math.max(ext.X, ext.Z) * 1.6 + CutKit.VIEW_DIST_PAD) + Vector3.new(0, 3, 0)
		local focus = run.surface + Vector3.new(0, ext.Y * 2.5, 0)
		run.skyEye, run.skyFocus = eye, focus
		run.cam:flyTo(CFrame.lookAt(eye, focus), 0.9 * run.stretch, false)
	end
	if run.audio then
		run.audio:play("beamRise", { where = run.surface })
	end
end

local function enterBeam(run: Run)
	local ext = run.extents :: Vector3
	local beam = BeamFX.new(run.stage, beamBase(run), God.GOLD, God.BEAM_HEIGHT, math.max(ext.X, ext.Z) * God.BEAM_RADIUS_MULT, run.quality)
	run.beam = beam
	CutKit.track(run, function()
		beam:cleanup()
	end)
	beam:fire(CutKit.beatSeconds(run))
	if run.water then
		run.water:godrays(beamBase(run), ext.Y * 2.0, God.GOLD)
	end
	if run.post then
		run.post:tint(God.TINT, 0.6 * run.stretch)
		run.post:sunRays(God.SUNRAYS, 0.6 * run.stretch)
		run.post:hypeOn(0.6 * run.stretch)
	end
	if run.shake then
		run.shake:add(0.4)
	end
end

local function enterChoir(run: Run)
	-- THE EXCLUSIVE SLOT. Only Cuts.God and Cuts.MassiveGod may play godChoir.
	if run.audio then
		run.audio:unsilence()
		run.audio:play("godChoir")
	end
end

local function enterDescent(run: Run)
	local ext = run.extents :: Vector3
	run.descentHeight = ext.Y * God.DESCENT_HEIGHT_MULT
	if run.brain then
		Shared.faceCamera(run)
		run.brain:markBreached()
		run.breached = true
		run.brain:setDescent(0, run.descentHeight)
	end
	Shared.rimHighlight(run, God.GOLD)
	local centre = run.surface + Vector3.new(0, ext.Y * 0.5, 0)
	local aura = AuraFX.new(run.stage, centre, God.GOLD, math.max(ext.X, ext.Y, ext.Z) * 0.7, run.quality, run.rng)
	run.aura = aura
	CutKit.track(run, function()
		aura:cleanup()
	end)
	if run.cam and run.skyEye then
		run.cam:lookHover(run.skyEye, run.skyFocus)
	end
end

local function updateDescent(run: Run, p: number)
	if run.brain and not run.skipping then
		run.brain:setDescent(p, run.descentHeight or 30)
	end
	if run.aura then
		local ext = run.extents :: Vector3
		local y = (run.descentHeight or 30) * (1 - (0.5 - 0.5 * math.cos(math.pi * p)))
		run.aura:setPos(run.surface + Vector3.new(0, ext.Y * 0.5 + y, 0))
		run.aura:update(run.t, 0.6)
	end
	if run.cam and run.skyEye then
		-- follow the creature down: focus slides from the sky point to the hero focus
		local eye, focus = CutKit.heroFraming(run)
		local f = (run.skyFocus :: Vector3):Lerp(focus, p)
		local e = (run.skyEye :: Vector3):Lerp(eye, p * p)
		run.cam:lookHover(e, f)
	end
end

local function enterArrival(run: Run)
	if run.brain then
		run.brain:setDescent(1, run.descentHeight or 30)
	end
	if run.post then
		run.post:flash()
	end
	if run.hype then
		run.hype:banner(run.cut.bannerText, God.GOLD)
		run.hype:nameText(run.displayName)
	end
	if run.water then
		local ext = run.extents :: Vector3
		run.water:shockRing(God.GOLD, math.max(ext.X, ext.Z) * 6, 1.2 * run.stretch)
	end
	if run.audio then
		run.audio:play("goldShockwave", { where = run.surface })
	end
	if run.shake then
		run.shake:add(0.9)
	end
end

local function enterLinger(run: Run)
	if run.beam then
		run.beam:fade(CutKit.beatSeconds(run))
	end
	if run.aura then
		run.aura:fade(CutKit.beatSeconds(run) * 0.8)
	end
	if run.post then
		run.post:easeBack(CutKit.beatSeconds(run))
	end
	if run.shake then
		run.shake:setSustain(0)
	end
end

local function updateLinger(run: Run, p: number)
	if run.brain and not run.skipping then
		run.brain:setDescent(1 - 0.01 * math.sin(p * math.pi * 2), run.descentHeight or 30)
	end
	if run.aura then
		run.aura:update(run.t)
	end
end

God.handlers = {
	bonk    = { enter = enterBonk },
	rumble  = { enter = enterRumble },
	glow    = { enter = enterGlow },
	tilt    = { enter = enterTilt },
	beam    = { enter = enterBeam },
	choir   = { enter = enterChoir },
	descent = { enter = enterDescent, update = updateDescent },
	arrival = { enter = enterArrival },
	linger  = { enter = enterLinger, update = updateLinger },
	handoff = Shared.handoff,
}
God.everyFrame = Shared.everyFrameRock
God.build = function(run: Run): boolean
	return Shared.build(run, nil)
end
function God.onSkip(run: Run)
	if run.hype then
		run.hype:interrupt()
		run.hype:hideSkipPrompt()
	end
	if run.water then
		run.water:cleanup()
	end
	if not run.beam then
		enterBeam(run)
	end
	if run.beam then
		run.beam:fade(0.1)
	end
	if not run.aura then
		enterDescent(run)
	end
	if run.brain then
		run.brain:setDescent(1, run.descentHeight or 30)
	end
	if run.post then
		run.post:easeBack(0.2)
	end
	if run.audio then
		run.audio:unsilence()
	end
	if run.shake then
		run.shake:setSustain(0)
	end
	if run.cam then
		local eye, focus = CutKit.heroFraming(run)
		run.cam:lookHover(eye, focus)
	end
end
function God.onCancel(run: Run)
	if run.beam then
		run.beam:cleanup()
		run.beam = nil
	end
	if run.aura then
		run.aura:cleanup()
		run.aura = nil
	end
end
God.name = "God"
God.beats = God.BEATS
God.revealBeat = "descent"
God.skippable = true
God.skipTo = "arrival"
God.bannerText = "GOD"

return God
