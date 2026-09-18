--!strict
-- CatchCinematic.Config — every tunable for the Massive catch cinematic.
-- DEBUG: set workspace attribute "CinematicTimescale" (number) during Play to
-- rescale every duration live (0.25 = quarter speed); read at sequence start.
local Config = {}

Config.DEBUG_TIMESCALE = 1.0

-- THE ROUTING TABLE (spec S4, locked). Evaluated top to bottom on the CONFIRMED
-- grant; the first match wins; nil means "no cut -- play a pop". Mutation never
-- appears here: Golden/Diamond and the other ten are visual variants only (S3.8).
-- Server (ThrowHandler, IceFishingEvent) and client (RevealRouter, CinematicClient,
-- Bridge) all read this one function.
function Config.CUT_FOR(rarity: string?, size: string?): string?
	if size == "Massive" and rarity == "God" then return "MassiveGod" end
	if size == "Massive" then return "Massive" end
	if size == "Huge" then return "Huge" end
	if rarity == "God" then return "God" end
	if rarity == "Secret" then return "Secret" end
	if rarity == "Mythic" then return "Mythic" end
	return nil
end

Config.SPECTATOR_RADIUS = 250          -- studs from EndPos; beyond = ignore entirely
Config.SKIP = { delay = 1.0, holdSeconds = 0.45, exitFadeSeconds = 0.18 }

-- revealCatch can grant NOTHING (player left mid-flight; a vaulted/unique/limited
-- fallback pool came up empty), and then ThrowResult never fires. Seconds from the
-- bonk -- the Sequencer scales it by run.stretch so the deadline always lands at
-- the same PLACE in the cut. The sequencer parks the clock just short of the
-- eruption while it waits, so a late grant delays the creature rather than showing
-- one the player may not own.
-- 3.0 -> 6.0 with the v2 retune (2026-08-09): the eruption moved 3.65 -> 6.35, so a
-- 3.0s deadline expired mid-DREAD and every genuine failure wound down before the
-- suspense had even built. 6.0 has to cover the dread (1.60-5.60) for the wind-down
-- to read at all; it lands in the silence, a hair short of the eruption -- exactly
-- the position the clock-park protects. A real grant arrives within milliseconds of
-- the bonk, so the only thing this costs a genuine failure is a fuller wind-down.
Config.CANCEL_TIMEOUT = 6.0

-- Beat tables live at the top of each cut module (Cuts.Massive.BEATS, Cuts.Huge.BEATS,
-- ...) since the 2026-09-17 reveal build; this module holds framework-wide tunables.

Config.CAMERA = {
	fovBase = 70, fovPunchHi = 95, fovPunchSettle = 78, fovPunchDur = 0.5,
	outboundHeight = 6,            -- studs above surface on the low fly-out
	hoverDistMult = 1.15,          -- x max(model width, depth), same as MassiveEmergence
	hoverHeightFrac = 0.42,        -- eye height as fraction of model height
	heroDistMult = 0.95, heroHeightFrac = 0.18, orbitDegrees = 45,
	returnBlendSeconds = 0.8,
	zoomPunchScale = 0.86,         -- hype-beat punch: dist multiplier per punch
	-- CutKit.farFraming, the pulled-back SCALE shot: distance = max(height*farHeightMult,
	-- width*farDistMult) + pad; eye sits farHeightFrac of the height above the water (low).
	farDistMult = 1.3, farHeightMult = 1.8, farHeightFrac = 0.12,
}
Config.SHAKE = {
	dreadRampTo = 0.4, eruption = 1.0, riseSustain = 0.10,
	traumaDecayPerSec = 1.4, maxOffset = 0.9, maxRollDeg = 1.2,
}
-- The rock after the final skip contact: sinks, tumbling slowly, then hides. (The
-- ricochet / second-bonk joke was removed 2026-09-17 with the comedy layer.)
Config.ROCK = { sinkSeconds = 0.8, sinkDepth = 2.0, spinRadPerSec = 2.0 }
Config.WATER = {
	stillWater = true,             -- glassy-still: zero local WaterWaveSize/Speed
	rippleTrainCount = 5, rippleMaxRadiusMult = 3.2, rippleAccel = 1.6,
	suctionDipStuds = 1.1, shadowMaxMult = 1.4,
	domeHeightFrac = 0.14, domeRiseSeconds = 0.42,
	columnHeightMult = 2.6, columnSeconds = 0.7,
	cascadeSeconds = 7.0, debrisBurst = 24,
}
Config.PARTICLES = {          -- rate multiplier + live-particle budget per tier
	high = { mult = 1.0, budget = 1200 },
	low  = { mult = 0.25, budget = 300 },
}
Config.POSTFX = {
	hypeSaturation = 0.35, hypeContrast = 0.12, hypeBloomIntensity = 0.9,
	blurSizeHigh = 8, blurSizeLow = 0,          -- blur dropped entirely on low
	flashSeconds = 0.08, easeBackSeconds = 1.2,
}
Config.REDUCED_MOTION = { shakeMult = 0.25, allowFlash = false }
Config.HYPE = { bannerScalePop = 1.35 }
-- Sound slots. "kit:<name>" resolves through SoundKit.play; raw ids through SoundKit.playId.
Config.ASSETS = {
	finalSkip      = "kit:splashBig",      -- the last skip contact: same cue as every other throw's landing
	rumbleLoop     = "rbxassetid://1837834264", -- APM "REVERSE HARD STOP-Noise Build 03", 4.0s build
	massiveRumble  = "rbxassetid://1837834264", -- was rumbleLoop; TODO: replace with a 2.5s low build
	bassDrop       = "kit:catchBigHit",
	waterExplosion = "kit:splashBig",
	roar           = "kit:catchGod",      -- TODO: replace -- creature roar, ~2-3s
	massiveRoar    = "kit:catchGod",      -- TODO: replace -- creature roar, ~2-3s
	bannerHit      = "kit:catchBigHit",
	cardWhoosh     = "kit:catchSparkle",
	VOLUMES = {
		finalSkip = 0.68, rumbleLoop = 0.8, massiveRumble = 0.8, bassDrop = 0.9, waterExplosion = 0.8,
		roar = 0.7, massiveRoar = 0.7, bannerHit = 0.6, cardWhoosh = 0.4,
	},
}

-- Quality tier: "low" on touch devices or when the player opted down; else "high".
function Config.qualityFor(player: Player): string
	local UIS = game:GetService("UserInputService")
	if player:GetAttribute("CinematicLowQuality") == true then return "low" end
	if UIS.TouchEnabled and not UIS.KeyboardEnabled then return "low" end
	return "high"
end

function Config.timescale(): number
	local o = workspace:GetAttribute("CinematicTimescale")
	return (type(o) == "number" and o > 0) and o or Config.DEBUG_TIMESCALE
end

return Config
