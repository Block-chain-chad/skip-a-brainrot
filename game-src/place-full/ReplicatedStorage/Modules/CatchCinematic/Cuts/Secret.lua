--!strict
-- CatchCinematic.Cuts.Secret -- SUSPENSE. 3.0s, not skippable. The first rarity
-- with a genuine fake-out: nothing happens, it almost feels like the reveal failed,
-- then a pink glow under the water, then it launches (spec S6.2).
local folder = script.Parent.Parent
local Config = require(folder:WaitForChild("Config"))
local CutKit = require(folder:WaitForChild("CutKit"))
local Types = require(folder:WaitForChild("Types"))
local AuraFX = require(folder:WaitForChild("AuraFX"))
local Shared = require(script.Parent:WaitForChild("Shared"))
type Run = Types.Run

local Secret = {}

-- ===== TUNABLES (spec S6.2) =====
Secret.BEATS = {
	{ name = "bonk",    t0 = 0.00, t1 = 0.10 },
	{ name = "nothing", t0 = 0.10, t1 = 0.60 },  -- no creature, no card; ripples; near-silence
	{ name = "fakeout", t0 = 0.60, t1 = 1.00 },  -- ripples die; pink glow UNDER the water
	{ name = "launch",  t0 = 1.00, t1 = 1.20 },  -- REVEAL: splash, pink column, creature launches
	{ name = "spiral",  t0 = 1.20, t1 = 1.50 },  -- stops in front of the camera; pink spirals
	{ name = "banner",  t0 = 1.50, t1 = 2.50 },  -- SECRET; giant pink rift; slow rotation
	{ name = "handoff", t0 = 2.50, t1 = 3.00 },
}
Secret.PINK = Color3.fromRGB(255, 90, 220)
Secret.VIOLET = Color3.fromRGB(150, 60, 255)
Secret.HUSH_LEVEL = 0.05

local function enterBonk(run: Run)
	if run.water then
		run.water:stillWater()
		run.water:bonkRing()
	end
	if run.audio then
		run.audio:play("finalSkip", { where = run.surface })
	end
	if run.cam then
		local eye, focus = CutKit.heroFraming(run)
		run.heroEye, run.heroFocus = eye, focus
		run.cam:flyTo(CFrame.lookAt(eye, run.surface), 0.6 * run.stretch, false)
	end
end

local function enterNothing(run: Run)
	if run.audio and not run.spectator then
		run.audio:duckAmbient(Secret.HUSH_LEVEL, 0.4 * run.stretch)
	end
end

local function updateNothing(run: Run, p: number)
	if run.water then
		run.water:rippleTrain(p * 0.4)
	end
end

local function enterFakeout(run: Run)
	if run.water then
		run.water:glowBelow(Secret.VIOLET, CutKit.beatSeconds(run))
	end
	if run.audio then
		run.audio:play("secretHum", { where = run.surface })
	end
end

local function enterLaunch(run: Run)
	if run.brain then
		Shared.faceCamera(run)
		run.brain:markBreached()
		run.breached = true
		run.brain:revealColors(0.1 * run.stretch)
	end
	if run.water then
		run.water:erupt(run.extents)
		run.water:godrays(run.surface, (run.extents :: Vector3).Y * 1.6, Secret.PINK)
	end
	if run.audio then
		run.audio:unsilence()
		run.audio:play("secretLaunch", { where = run.surface })
		if not run.spectator then
			run.audio:restoreAmbient(0.3 * run.stretch)
		end
	end
	if run.shake then
		run.shake:add(0.8)
	end
	if run.post then
		run.post:flash()
	end
	if run.cam and run.heroEye then
		run.cam:lookHover(run.heroEye, run.heroFocus)
	end
end

local function updateLaunch(run: Run, p: number)
	if run.brain and not run.skipping then
		run.brain:setRise(p)
	end
end

local function enterSpiral(run: Run)
	Shared.rimHighlight(run, Secret.PINK)
	if run.brain then
		run.brain:setRise(1)
	end
	local ext = run.extents :: Vector3
	local centre = run.surface + Vector3.new(0, ext.Y * 0.5, 0)
	local aura = AuraFX.new(run.stage, centre, Secret.PINK, math.max(ext.X, ext.Y, ext.Z) * 0.9, run.quality, run.rng)
	run.aura = aura
	CutKit.track(run, function()
		aura:cleanup()
	end)
end

local function updateSpiral(run: Run, p: number)
	if run.aura then
		run.aura:update(run.t, p * 0.35)
	end
end

local function enterBanner(run: Run)
	if run.hype then
		run.hype:banner(run.cut.bannerText, Secret.PINK)
		run.hype:nameText(run.displayName)
	end
	if run.audio then
		run.audio:play("bannerHit", { where = run.surface })
	end
	if run.water and run.model then
		run.water:cascade(run.model, 0.8 * run.stretch)
	end
	if run.shake then
		run.shake:add(0.3)
	end
end

local function updateBanner(run: Run, p: number)
	if run.aura then
		run.aura:update(run.t, 1)
	end
	if run.brain and not run.skipping then
		-- slow rotation: setRise's yaw is alpha-driven, so drift alpha a hair for the turn
		run.brain:setRise(1 - 0.03 * math.sin(p * math.pi))
	end
end

local function exitBanner(run: Run)
	if run.aura then
		run.aura:fade(0.4 * run.stretch)
	end
end

Secret.handlers = {
	bonk    = { enter = enterBonk },
	nothing = { enter = enterNothing, update = updateNothing },
	fakeout = { enter = enterFakeout },
	launch  = { enter = enterLaunch, update = updateLaunch },
	spiral  = { enter = enterSpiral, update = updateSpiral },
	banner  = { enter = enterBanner, update = updateBanner, exit = exitBanner },
	handoff = Shared.handoff,
}
Secret.everyFrame = Shared.everyFrameRock
Secret.build = function(run: Run): boolean
	return Shared.build(run, nil)
end
Secret.onCancel = function(run: Run)
	if run.aura then
		run.aura:cleanup()
		run.aura = nil
	end
end
Secret.name = "Secret"
Secret.beats = Secret.BEATS
Secret.revealBeat = "launch"
Secret.skippable = false
Secret.bannerText = "SECRET"

return Secret
