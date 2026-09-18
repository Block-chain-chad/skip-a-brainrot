--!strict
-- CatchCinematic.Config — every tunable for the Massive catch cinematic.
-- DEBUG: set workspace attribute "CinematicTimescale" (number) during Play to
-- rescale every duration live (0.25 = quarter speed); read at sequence start.
local Config = {}

Config.DEBUG_TIMESCALE = 1.0

-- Which sizes trigger the cinematic from a REAL catch. Server reads this too.
-- "full" = 17.9s sequence, "trimmed" = HUGE_TRIM variant, "none" = existing behavior.
-- Huge stays "none" until the owner picks after the side-by-side demo.
Config.SIZES = { Massive = "full", Huge = "none" } :: { [string]: string }

-- After the handoff beat: run the existing PullCeremony too? (comparison pending)
-- Live override for the demo: workspace attribute "CinematicCeremonyAfter" (boolean).
Config.RUN_PULL_CEREMONY_AFTER = false

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

-- Beat boundaries in seconds from the bonk (t=0 = the final skip contact).
-- RETUNED v2 2026-08-09, owner feedback watching v1 live: "too fast, no suspense,
-- the brainrot doesn't emerge slowly like a beast." Dread 1.6->3.5s, silence
-- 0.45->0.75s, rise 2->5s. Total 10.7 -> 15.9s. The skip prompt covers repeat views.
Config.BEATS = {
	{ name = "bonk",     t0 = 0.00, t1 = 0.35 },
	{ name = "travel",   t0 = 0.35, t1 = 1.60 },
	{ name = "dread",    t0 = 1.60, t1 = 5.60 },  -- 4.0s: the length of the suspense build
	{ name = "silence",  t0 = 5.60, t1 = 6.35 },  -- DO NOT shorten or soften
	{ name = "eruption", t0 = 6.35, t1 = 7.20 },
	{ name = "rise",     t0 = 7.20, t1 = 13.70 },
	{ name = "hype",     t0 = 13.70, t1 = 16.20 },
	{ name = "handoff",  t0 = 16.20, t1 = 17.90 },
}
Config.SECOND_BONK_T = 10.6

-- Trimmed Huge cut (~4.3s): no silence, no hype. Same beat names, new bounds.
Config.HUGE_TRIM = {
	{ name = "bonk",     t0 = 0.00, t1 = 0.30 },
	{ name = "travel",   t0 = 0.30, t1 = 1.00 },
	{ name = "dread",    t0 = 1.00, t1 = 1.80 },
	{ name = "eruption", t0 = 1.80, t1 = 2.40 },
	{ name = "rise",     t0 = 2.40, t1 = 3.60 },
	{ name = "handoff",  t0 = 3.60, t1 = 4.30 },
}

Config.CAMERA = {
	fovBase = 70, fovPunchHi = 95, fovPunchSettle = 78, fovPunchDur = 0.5,
	outboundHeight = 6,            -- studs above surface on the low fly-out
	hoverDistMult = 1.15,          -- x max(model width, depth), same as MassiveEmergence
	hoverHeightFrac = 0.42,        -- eye height as fraction of model height
	heroDistMult = 0.95, heroHeightFrac = 0.18, orbitDegrees = 45,
	returnBlendSeconds = 0.8,
	zoomPunchScale = 0.86,         -- hype-beat punch: dist multiplier per punch
}
Config.SHAKE = {
	dreadRampTo = 0.4, eruption = 1.0, riseSustain = 0.10,
	traumaDecayPerSec = 1.4, maxOffset = 0.9, maxRollDeg = 1.2,
}
Config.ROCK = {
	ricochetApex = 120,            -- absurdly high, on purpose. Do not "fix".
	ricochetLateral = 6, spinRadPerSec = 9.0,
	plinkPauseSeconds = 0.35,      -- hang above the head before the second bonk
	tumbleSeconds = 0.8,
}
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
Config.HYPE = {
	bannerScalePop = 1.35,
	-- ABSOLUTE cinematic seconds, and they MUST land inside the hype beat
	-- (13.70-16.20): updateHype is their only caller, so a time outside that
	-- window never fires at all. This ONE array gates BOTH the camera's three
	-- zoom punches AND HypeUI's meme fly-ins -- RETIME IT WHENEVER Config.BEATS
	-- MOVES (the v2 retune left 6.9/7.5/8.2 behind and silently lost both).
	zoomPunchTimes = { 13.9, 14.6, 15.3 },
	memeTexts = { "NO SHOT", "ABSOLUTE UNIT", "HE'S REAL", "W CATCH", "SHEEEESH", "CAUGHT LIVE" },
	confettiBurst = 90, speedLineCount = 14,
}
-- Sound slots. "kit:<name>" resolves through SoundKit.play; raw ids through SoundKit.playId.
Config.ASSETS = {
	bonkClonk      = "rbxassetid://122682383632262", -- snappy cartoon bonk, 0.65s (owner picked #2 on the audition board)
	rumbleLoop     = "rbxassetid://1837834264", -- APM "REVERSE HARD STOP-Noise Build 03", 4.0s: builds and hard-stops exactly at the silence beat
	bassDrop       = "kit:catchBigHit",
	waterExplosion = "kit:splashBig",
	roar           = "kit:catchGod",      -- TODO: replace — creature roar, ~2-3s
	plink          = "kit:catchCommon",   -- the second bonk: tiny, comically quiet
	memeAudio      = "kit:catchSecret",   -- TODO: replace — the heel-turn meme track (owner upload)
	cardWhoosh     = "kit:catchSparkle",
	VOLUMES = {
		bonkClonk = 0.85, rumbleLoop = 0.8, bassDrop = 0.9, waterExplosion = 0.8,
		roar = 0.7, plink = 0.18, memeAudio = 0.6, cardWhoosh = 0.4,
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
