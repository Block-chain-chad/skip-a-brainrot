--!strict
-- CatchCinematic.Cuts.MassiveGod -- ULTIMATE. ~12s, skippable to `finalReveal`. ONE
-- cohesive cinematic: the Massive emergence (Massive's handlers, compressed bounds)
-- flows into the God heaven sequence (God's handlers) through three beats only this
-- cut has: hush, ascend, and the final reveal at the water. The beam is anchored on
-- the creature (run.beamBase), never on the water. No second copy of either code path.
local folder = script.Parent.Parent
local Config = require(folder:WaitForChild("Config"))
local CutKit = require(folder:WaitForChild("CutKit"))
local Types = require(folder:WaitForChild("Types"))
local Shared = require(script.Parent:WaitForChild("Shared"))
local Massive = require(script.Parent:WaitForChild("Massive"))
local God = require(script.Parent:WaitForChild("God"))
type Run = Types.Run

local MassiveGod = {}

-- ===== TUNABLES (spec S6.6) =====
MassiveGod.BEATS = {
	{ name = "bonk",        t0 = 0.00, t1 = 0.40 },   -- I   Massive
	{ name = "ripple",      t0 = 0.40, t1 = 1.20 },   -- I   still + ripple compressed (own handler)
	{ name = "silhouette",  t0 = 1.20, t1 = 1.80 },   -- I   Massive
	{ name = "emergence",   t0 = 1.80, t1 = 2.80 },   -- I   REVEAL -- Massive
	{ name = "scale",       t0 = 2.80, t1 = 4.50 },   -- I   Massive (pull back, full rise)
	{ name = "hush",        t0 = 4.50, t1 = 5.50 },   -- II  unique: silence, stillness, tiny gold light grows
	{ name = "beam",        t0 = 5.50, t1 = 6.50 },   -- III God's beam, anchored on the rig; choir
	{ name = "ascend",      t0 = 6.50, t1 = 8.00 },   -- IV  unique: rises into the beam, vanishes, emptiness
	{ name = "descent",     t0 = 8.00, t1 = 10.00 },  -- V   God's descent at full Massive scale
	{ name = "finalReveal", t0 = 10.00, t1 = 10.80 }, -- VI  flash, gold shockwave, water explodes, MASSIVE GOD
	{ name = "return",      t0 = 10.80, t1 = 12.00 }, -- VII beam fades, water settles, streak, restore
}
MassiveGod.ASCEND_HEIGHT_MULT = 5   -- x creature height: how far it rises into the beam

-- Fades the creature into the light and back. f = 0 restores every part to the
-- transparency it had when the fade began, so a body's invisible scaffolding
-- (RootPart, FX hosts) never becomes a visible box, and a translucent part never
-- turns opaque.
local function setBodyTransparency(run: Run, f: number)
	if not run.model then
		return
	end
	if not run.bodyAlpha0 then
		local snap: { [BasePart]: number } = {}
		for _, d in ipairs(run.model:GetDescendants()) do
			if d:IsA("BasePart") then
				snap[d] = d.Transparency
			end
		end
		run.bodyAlpha0 = snap
	end
	for part, a0 in pairs(run.bodyAlpha0) do
		if part.Parent then
			part.Transparency = a0 + (1 - a0) * f
		end
	end
end

local function updateRipple(run: Run, p: number)
	if p < 0.05 and not run.rumbleStarted then
		run.rumbleStarted = true
		if run.audio then
			run.audio:play("massiveRumble", { where = run.surface, speed = run.speed })
		end
		if run.cam then
			local eye = run.travelEye or (run.surface - run.horiz * CutKit.TRAVEL_BACK_STUDS + Vector3.new(0, 6, 0))
			run.cam:lookHover(eye, run.surface)
		end
	end
	if run.water then
		run.water:rippleTrain(p)
		run.water:suctionAndShadow(p * 0.5)
	end
	if run.shake then
		run.shake:setSustain((Config.SHAKE.dreadRampTo or 0.4) * p)
	end
end

local function enterHush(run: Run)
	if run.audio then
		run.audio:silence()
	end
	if run.shake then
		run.shake:setSustain(0)
	end
	Shared.calmAngry(run)
	if run.brain then
		run.brain:setRise(1)
	end
	local ext = run.extents :: Vector3
	-- the beam will come FROM the creature: anchor on its head
	run.beamBase = run.brain and run.brain:headTop() or (run.surface + Vector3.new(0, ext.Y, 0))
	if run.water then
		run.water:glowBelow(God.WHITE_GOLD, CutKit.beatSeconds(run))
	end
	if run.cam then
		-- slow tilt up from the far framing toward the sky above the creature
		local eye = run.farEye or select(1, CutKit.farFraming(run))
		run.skyEye = eye
		run.skyFocus = (run.beamBase :: Vector3) + Vector3.new(0, ext.Y * 2.0, 0)
		run.cam:flyTo(CFrame.lookAt(eye, run.skyFocus), CutKit.beatSeconds(run), false)
	end
end

local function updateHush(run: Run, p: number)
	-- a tiny gold light above the creature grows: the beam itself, at a whisper,
	-- driven per frame from the clock. God's beam handler builds it (and the
	-- godrays/tint that come with it); setAlpha(0) immediately cancels its ramp so
	-- nothing shows until this beat says so.
	if p > 0.4 and not run.beam then
		God.handlers.beam.enter(run)
		if run.beam then
			run.beam:setAlpha(0)
		end
	end
	if run.beam then
		run.beam:setAlpha(0.06 * math.clamp((p - 0.4) / 0.6, 0, 1))
	end
end

local function enterBeam(run: Run)
	if run.beam then
		run.beam:fire(CutKit.beatSeconds(run))
	else
		God.handlers.beam.enter(run)
	end
	God.handlers.choir.enter(run)
	if run.post then
		run.post:tint(God.TINT, 0.6 * run.stretch)
		run.post:sunRays(God.SUNRAYS, 0.6 * run.stretch)
	end
end

local function enterAscend(run: Run)
	local ext = run.extents :: Vector3
	run.descentHeight = ext.Y * MassiveGod.ASCEND_HEIGHT_MULT
	Shared.rimHighlight(run, God.GOLD)
	if run.cam and run.skyEye then
		run.cam:lookHover(run.skyEye, run.skyFocus)
	end
end

local function updateAscend(run: Run, p: number)
	if run.brain and not run.skipping then
		-- reverse of the descent: alpha 1 (at the water) -> 0 (high in the beam)
		run.brain:setDescent(1 - p, run.descentHeight or 40)
		-- the last third: gone into the light
		if p > 0.66 then
			setBodyTransparency(run, (p - 0.66) / 0.34)
		end
	end
end

local function exitAscend(run: Run)
	-- a beat of emptiness: the creature is not in the world
	setBodyTransparency(run, 1)
end

local function enterDescent(run: Run)
	-- reappear above the player, then God's descent handler drives it down
	setBodyTransparency(run, 0)
	God.handlers.descent.enter(run)
	if run.cam then
		local eye, focus = CutKit.farFraming(run)
		run.skyEye = eye
		run.skyFocus = focus + Vector3.new(0, (run.descentHeight or 40), 0)
		run.cam:lookHover(run.skyEye, run.skyFocus)
	end
end

local function enterFinalReveal(run: Run)
	God.handlers.arrival.enter(run)
	if run.water then
		run.water:erupt(run.extents)
	end
	if run.audio then
		run.audio:play("waterExplosion", { where = run.surface })
	end
	if run.cam then
		local eye, focus = CutKit.farFraming(run)
		run.cam:lookHover(eye, focus)
	end
end

local function enterReturn(run: Run)
	if run.beam then
		run.beam:fade(CutKit.beatSeconds(run) * 0.6)
	end
	if run.aura then
		run.aura:fade(CutKit.beatSeconds(run) * 0.5)
	end
	Shared.handoff.enter(run)
end

MassiveGod.handlers = {
	bonk        = Massive.handlers.bonk,
	ripple      = { update = updateRipple },
	silhouette  = Massive.handlers.silhouette,
	emergence   = Massive.handlers.emergence,
	scale       = Massive.handlers.scale,
	hush        = { enter = enterHush, update = updateHush },
	beam        = { enter = enterBeam },
	ascend      = { enter = enterAscend, update = updateAscend, exit = exitAscend },
	descent     = { enter = enterDescent, update = God.handlers.descent.update },
	finalReveal = { enter = enterFinalReveal },
	["return"]  = { enter = enterReturn, update = Shared.handoff.update },
}
MassiveGod.everyFrame = Shared.everyFrameRock
MassiveGod.build = function(run: Run): boolean
	return Shared.build(run, "Massive")
end
function MassiveGod.onSkip(run: Run)
	Massive.onSkip(run)
	setBodyTransparency(run, 0)
	if run.beam then
		run.beam:fade(0.1)
	end
	if run.aura then
		run.aura:fade(0.1)
	end
	if run.brain then
		run.brain:setDescent(1, run.descentHeight or 40)
	end
end
MassiveGod.onCancel = God.onCancel
MassiveGod.name = "MassiveGod"
MassiveGod.beats = MassiveGod.BEATS
MassiveGod.revealBeat = "emergence"
MassiveGod.skippable = true
MassiveGod.skipTo = "finalReveal"
MassiveGod.bannerText = "MASSIVE GOD"

return MassiveGod
