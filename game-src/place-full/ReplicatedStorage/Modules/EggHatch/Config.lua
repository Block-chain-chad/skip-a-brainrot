--!strict
-- EggHatch.Config: every number the hatch presentation uses, in one place.
-- Times are seconds at speed 1; the controller multiplies them by the run's speed, so a
-- future "fast hatch" / "auto hatch" setting is one multiplier, never a second timeline.
--
-- DIRECTION (owner, 2026-09-21): fast, physical, responsive. The egg carries the
-- anticipation through squash/stretch, rotation, easing and timing -- not through
-- effects. Common..Epic get the same standard hatch; Legendary and above enhance the
-- POST-HATCH reveal (bigger pop, ring, sparkles, longer hold, stronger sting) and never
-- make the egg wobble longer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)

local Config = {}

-- 1 = authored pace. Controller.setSpeed writes this; opts.speed on a single play
-- multiplies on top.
Config.SPEED = 1

-- ------------------------------------------------------------------ stage
Config.STAGE = {
	distance = 7.0,        -- studs in front of the camera the eggs are staged at
	minDistance = 3.2,     -- never closer than this (a wall right in front of the camera)
	clearance = 0.9,       -- keep this far in front of whatever the forward ray hits
	veilIn = 0.18,         -- grade / DoF ramp in
	veilOut = 0.24,        -- ...and out
	hudHideAt = 0.10,      -- HUD guis switch off this long into the ramp (under it)
	dofFar = 0.7,          -- DepthOfField far intensity at full grade
	dofRadiusMult = 0.55,  -- in-focus radius as a fraction of the stage distance
	characterFade = true,  -- the local character fades out of the shot
	fovPunchMax = 4,       -- degrees, hard cap on any camera FOV punch
	lightBrightness = 0.55,-- the stage fill light (the grade pulls the world down; this keeps the eggs lit)
	lightRange = 14,
}

-- ScreenGuis that stay on during a hatch. Everything else in PlayerGui that is
-- Enabled is switched off under the grade and back on under it.
Config.HUD_KEEP = {
	EggHatchUI = true, ToastGui = true, TeleportCurtain = true, Messages = true,
	Freecam = true, CatchCinematicUI = true, CatchPopUI = true, EggShopUI = true,
}

-- ------------------------------------------------------------------ layout
-- Screen fractions: x in [-0.5, 0.5] of the width, y in [-0.5, 0.5] of the height
-- (+ is up). `frac` is the egg's on-screen HEIGHT as a fraction of the viewport
-- height; `z` is a stage-depth nudge in studs (negative = nearer the camera).
Config.LAYOUT = {
	[1] = {
		frac = 0.34, phoneFrac = 0.40, shortFrac = 0.36,
		slots = { { x = 0.00, y = 0.08, z = 0 } },
		plateScale = 1.0,
	},
	[3] = {
		frac = 0.27, phoneFrac = 0.31, shortFrac = 0.29,
		-- a shallow arc: the outer two sit a little back and a little higher
		slots = {
			{ x = -0.27, y = 0.09, z = 0.5 },
			{ x = 0.00, y = 0.06, z = -0.3 },
			{ x = 0.27, y = 0.09, z = 0.5 },
		},
		plateScale = 0.82,
	},
	[10] = {
		frac = 0.18, phoneFrac = 0.20, shortFrac = 0.18,
		slots = {
			{ x = -0.36, y = 0.27, z = 0.6 }, { x = -0.18, y = 0.25, z = 0.2 }, { x = 0.00, y = 0.24, z = 0 },
			{ x = 0.18, y = 0.25, z = 0.2 }, { x = 0.36, y = 0.27, z = 0.6 },
			{ x = -0.36, y = -0.12, z = 0.6 }, { x = -0.18, y = -0.14, z = 0.2 }, { x = 0.00, y = -0.15, z = 0 },
			{ x = 0.18, y = -0.14, z = 0.2 }, { x = 0.36, y = -0.12, z = 0.6 },
		},
		plateScale = 0.62,
	},
}

-- ------------------------------------------------------------------ beats (x1)
-- Relative to the egg's own enter time. 1.30 s from the egg entering to the shell
-- popping; the reward is readable by ~1.55 and named at 1.62.
Config.BEATS = {
	enter = 0.00, enterLen = 0.16,     -- pops into the foreground, rising a little
	settle = 0.16, settleLen = 0.18,   -- lands: squash, then a small stretch back
	-- the lean/wobble keyframes: { time, degrees }. Two controlled leans, then a
	-- faster alternating wobble that builds, back to upright.
	lean = {
		{ 0.32, 0 }, { 0.43, -21 }, { 0.55, 21 }, { 0.64, -19 }, { 0.72, 17 },
		{ 0.79, -14 }, { 0.86, 12 }, { 0.92, 0 },
	},
	squash = 0.94, squashLen = 0.13,   -- compression: the wind-up
	shake = 1.07, shakeLen = 0.22,     -- rapid shake, stretching taller as it goes
	pop = 1.30,                        -- the shell POPS
	-- after the pop
	reward = 0.02,                     -- the creature emerges
	plate = 0.32,                      -- name + rarity
	celebrate = 0.40,
}
Config.BATCH_OFFSET = 0.04        -- seconds between eggs in a batch (tiny, never robotic)
Config.BATCH_RAREST_EXTRA = 0.06  -- the rarest egg of a Legendary+ batch pops last by this
Config.PLATE_STAGGER = 0.08       -- between plates in a batch
Config.TAP_GRACE = 0.20           -- taps are ignored this long after the plates land
Config.EXIT = 0.18                -- clean exit: rewards + plates scale out over this

-- ------------------------------------------------------------------ rarity presets
-- Post-hatch emphasis only. `pop` is the reward's overshoot, `bounce` a second smaller
-- bounce, `hold` how long the reward sits after its plate before the run auto-ends.
export type Preset = {
	rank: number, veil: number, hold: number, pop: number, bounce: number, ring: boolean,
	ringSize: number, confetti: number, orbit: boolean, punch: number, kick: number,
	flash: number, light: number, sting: string, stingVol: number, layers: { { any } },
	plateSlam: boolean,
}
local function preset(t: { [string]: any }): Preset
	return t :: any
end
Config.PRESETS = {
	Common    = preset({ rank = 1, veil = 0.50, hold = 0.75, pop = 1.10, bounce = 0.00, ring = false, ringSize = 0, confetti = 0, orbit = false, punch = 0.5, kick = 0.35, flash = 0, light = 0.9, sting = "catchCommon", stingVol = 0.18, layers = {}, plateSlam = false }),
	Uncommon  = preset({ rank = 2, veil = 0.52, hold = 0.75, pop = 1.12, bounce = 0.00, ring = false, ringSize = 0, confetti = 0, orbit = false, punch = 0.6, kick = 0.4, flash = 0, light = 0.9, sting = "catchUncommon", stingVol = 0.16, layers = {}, plateSlam = false }),
	Rare      = preset({ rank = 3, veil = 0.54, hold = 0.80, pop = 1.14, bounce = 0.00, ring = true, ringSize = 1.0, confetti = 0, orbit = false, punch = 0.8, kick = 0.5, flash = 0, light = 1.0, sting = "catchRare", stingVol = 0.22, layers = {}, plateSlam = false }),
	Epic      = preset({ rank = 4, veil = 0.56, hold = 0.85, pop = 1.16, bounce = 0.04, ring = true, ringSize = 1.1, confetti = 0, orbit = false, punch = 1.0, kick = 0.6, flash = 0, light = 1.1, sting = "catchEpic", stingVol = 0.24, layers = {}, plateSlam = true }),
	Legendary = preset({ rank = 5, veil = 0.62, hold = 1.10, pop = 1.24, bounce = 0.06, ring = true, ringSize = 1.3, confetti = 16, orbit = true, punch = 1.8, kick = 1.0, flash = 0.22, light = 1.3, sting = "catchLegend", stingVol = 0.30, layers = { { "catchBigHit", 0.24, 0.05 } }, plateSlam = true }),
	Mythic    = preset({ rank = 6, veil = 0.68, hold = 1.30, pop = 1.28, bounce = 0.07, ring = true, ringSize = 1.5, confetti = 26, orbit = true, punch = 2.4, kick = 1.3, flash = 0.30, light = 1.5, sting = "catchMythic", stingVol = 0.34, layers = { { "catchBigHit", 0.28, 0.05 }, { "catchDrama", 0.18, 0.0 } }, plateSlam = true }),
	Secret    = preset({ rank = 7, veil = 0.76, hold = 1.60, pop = 1.32, bounce = 0.08, ring = true, ringSize = 1.7, confetti = 36, orbit = true, punch = 3.0, kick = 1.6, flash = 0.40, light = 1.7, sting = "catchSecret", stingVol = 0.38, layers = { { "catchBigHit", 0.32, 0.05 }, { "catchDrama", 0.24, 0.0 } }, plateSlam = true }),
	God       = preset({ rank = 8, veil = 0.84, hold = 2.00, pop = 1.36, bounce = 0.09, ring = true, ringSize = 2.0, confetti = 48, orbit = true, punch = 4.0, kick = 2.0, flash = 0.55, light = 1.9, sting = "catchGod", stingVol = 0.42, layers = { { "catchBigHit", 0.36, 0.05 }, { "catchDrama", 0.26, 0.0 }, { "catchSparkle", 0.28, 0.6 } }, plateSlam = true }),
}

function Config.presetFor(rarity: string?): Preset
	return Config.PRESETS[rarity or ""] or Config.PRESETS.Rare
end

-- Tier colours are the game's (RarityConfig), so the hatch speaks the same colour as
-- the bag, the index and every card.
Config.RARITY_COLOUR = {} :: { [string]: Color3 }
Config.RARITY_RANK = {} :: { [string]: number }
for i, t in ipairs(RarityConfig) do
	Config.RARITY_COLOUR[t.Name] = t.Color
	Config.RARITY_RANK[t.Name] = i
end
Config.FALLBACK_COLOUR = Color3.fromRGB(200, 200, 200)

function Config.colourFor(rarity: string?): Color3
	return Config.RARITY_COLOUR[rarity or ""] or Config.FALLBACK_COLOUR
end

-- Size classes scale the REWARD only (Massive > Huge), and tag the plate.
Config.SIZE_SCALE = { Huge = 1.35, Massive = 1.8 }

-- Sound ladder. Everything is a SoundKit name; nothing here is an asset id.
Config.SOUND = {
	enter = { "wheelWind", 0.20, 1.1 },
	land = { "place", 0.10, 1.2 },
	knock = { "wheelTick", 0.14, 0.9 },       -- on the leans, pitched up as they build
	squash = { "eggCrack1", 0.22, 1.0 },     -- the wind-up snap
	shake = { "eggCrack2", 0.24, 1.08 },     -- something gave
	pop = { "eggSplit", 0.30, 1.1 },         -- the shell
	popLayer = { "catchUncommon", 0.22, 1.25 }, -- the cartoon bloop that makes it a POP
	plate = { "catchSparkle", 0.16, 1.0 },
	dismiss = { "panelClose", 0.08, 1.0 },
}

return Config
