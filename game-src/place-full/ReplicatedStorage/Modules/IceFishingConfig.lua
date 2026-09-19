-- IceFishingConfig: the tundra BLIZZARD ICE-FISHING event, one place for every number.
--
-- WORLD 2 ONLY. Every hour (aligned to the real clock, on the :00) a blizzard freezes
-- the Frozen Tundra lake for 20 minutes: the invisible LakeBarrier drops, a walkable ice
-- sheet covers the water, fishing holes are augered through it, and every tundra player
-- swaps their rock satchel for a rod. When it thaws, anyone still out on the ice is sent
-- back to their tundra camp, the satchel comes back and the lake returns to normal.
-- See ServerScriptService.Modules.IceFishingEvent for the loop and build, and
-- StarterPlayerScripts.IceFishingClient for the banner, the walk-up prompt and the cast.
--
-- The exclusive fishing brainrots are wired (2026-08-21): RollCatch below reads the real
-- pool -- BrainrotConfigTundra entries carrying Origin = "IceFishing" -- and picks one,
-- weighted by that entry's FishWeight. See RollCatch's own comment for the shape.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BrainrotConfigTundra = require(ReplicatedStorage.Modules.BrainrotConfigTundra)

local IceFishingConfig = {}

-- ===== NAME ==================================================================
-- What the BANNER calls this event -- "TUNDRA INCOMING", "TUNDRA -- ICE FISHING OPEN".
-- One place, because it is read by the player in two strings and nowhere else.
--
-- The internal names deliberately do NOT follow it. IceFishingEvent, IceFishingConfig,
-- the IceFishing rig folder, the IceFishingState/Cast/Reel remotes and the
-- IceFishingActive attribute are all load-bearing: the client looks the holes up by that
-- folder name, and ThrowHandler and ClientMain both gate World-2 throwing on that
-- attribute. Renaming them buys nothing a player can see and breaks three files.
IceFishingConfig.EVENT_NAME = "TUNDRA"

-- ===== TIMING ================================================================
-- Real-clock aligned: the freeze begins at the top of each hour (os.time() multiple of
-- 3600) and the warning banner shows WARN_SECONDS before that. FREEZE_SECONDS is the
-- length of the window. Kept well under an hour so there is always clear lake between.
IceFishingConfig.WARN_SECONDS   = 25
IceFishingConfig.FREEZE_SECONDS = 20 * 60      -- 20 minutes frozen
IceFishingConfig.PERIOD_SECONDS = 60 * 60      -- one blizzard per real-clock hour

-- ===== HEIGHTS ===============================================================
-- Measured off the live world, and the three of them are locked together:
--
--   ICE_TOP    2003.2  the walking surface. The tundra dock deck tops out at 2002.45,
--                      so this is a 0.75-stud step off the boards -- walk-on, no ramp.
--   WATER_Y    2000    the terrain water plane under the lake.
--   ICE_BOTTOM 1998.5  1.5 studs UNDER the water, so the sheet sits IN the lake instead
--                      of hovering over it. The old 2-stud slab floated and you could
--                      see a band of open water under its edge from the dock.
--
-- POOL_Y is the water surface inside an augered hole, 0.7 below the ice. It is bounded
-- at BOTH ends and the window is narrow:
--
--   too low  -- TERRAIN WATER RENDERS OVER ANY PART WHOSE TOP SITS NEAR ITS OWN PLANE,
--              so a pool below about 2001.5 gets eaten at grazing angles and the hole
--              half-fills with bright lake blue. Measured: 2001.25 fails.
--   too deep -- at 2001.7 (1.5 down) the near rim occluded the water from standing
--              height and the hole read as a thin dark slit you could walk past. Real
--              hole water sits just under the surface anyway, because the sheet floats.
--
-- 2002.5 clears the terrain-water plane by a full 2.5 studs and still leaves a visible
-- 0.7 of bore. It also lifts the float, which RodService.CastLine puts at POOL_Y + 0.35.
-- Re-check the hole from standing height after moving this either way.
IceFishingConfig.ICE_TOP    = 2003.2
IceFishingConfig.ICE_BOTTOM = 1998.5
IceFishingConfig.WATER_Y    = 2000
IceFishingConfig.POOL_Y     = 2002.5

-- ===== THE LAKE (Frozen Tundra SkipArea) =====================================
IceFishingConfig.LAKE_CENTER = Vector3.new(-8000, 2003.2, -7339)  -- x, ICE_TOP, z
IceFishingConfig.SKIP_AREA_PATH = { "GameWorld", "FrozenTundra", "SkipArea" }
IceFishingConfig.BARRIER_FOLDER = "LakeBarrier"
IceFishingConfig.RIG_FOLDER     = "IceFishing"   -- spawned under SkipArea during a freeze

-- THE LAKE IS A LENS, NOT A RECTANGLE. Raycast off the real terrain water: it is 380
-- studs across at the middle and pinches to about 60 where it meets the dock. The sheet
-- used to be one 388 x 948 slab, so at both ends it lay across the shoreline and the
-- rocks -- and the bank out there sits at y 2002, BELOW the ice, so an overhang shows.
-- Instead the sheet is one strip per band below, each cut to that band's water width.
--
-- The bands are adaptive: 8-stud probes merged while the span held within 10 studs, so
-- they are fine where the lake pinches and one long band across the wide middle. The
-- first band starts at the dock's north fascia (-7789.7) rather than under the deck --
-- ICE_TOP is 0.75 above the deck, so a strip tucked underneath would push up through the
-- boards. z-bands abut exactly (no overlap, or coplanar top faces z-fight); SHORE_OVERRUN
-- grows each strip SIDEWAYS only, to tuck it a few studs under the bank.
IceFishingConfig.SHORE_OVERRUN = 3
IceFishingConfig.LAKE_PROFILE = {
	-- THE DOCK FLANKS. The profile used to begin at the dock's north fascia (-7789.7), on
	-- the reasoning that a strip tucked under the deck would push up through the boards --
	-- ICE_TOP is 0.75 above the deck. True, but the dock is only 57 studs wide and the lake
	-- is 120 there, so it left OPEN WATER down both sides of the pier: measured at z -7792
	-- to about -7806, x -8060..-8028 to the west and -7972..-7936 to the east. You could
	-- see it from the deck and step straight into it.
	-- These two strips fill exactly that, and stop dead on the deck's own faces. The x
	-- values are pre-compensated for SHORE_OVERRUN (3), which grows every strip sideways:
	-- -8031.3 + 3 = -8028.3 and -7968.7 - 3 = -7971.7 are the deck's west and east edges,
	-- so the ice meets the pier with no seam and no overlap. Measure the deck again before
	-- touching these. They share a z range, which is fine -- bands may not overlap in Z,
	-- and these do not overlap each other in X.
	{ z0 = -7806, z1 = -7789.5, x0 = -8057,   x1 = -8031.3 },   -- west of the dock
	{ z0 = -7806, z1 = -7789.5, x0 = -7968.7, x1 = -7935 },     -- east of the dock
	{ z0 = -7789.5, z1 = -7773.5, x0 = -8084, x1 = -7916 },
	{ z0 = -7773.5, z1 = -7757.5, x0 = -8098, x1 = -7904 },
	{ z0 = -7757.5, z1 = -7733.5, x0 = -8114, x1 = -7886 },
	{ z0 = -7733.5, z1 = -7709.5, x0 = -8128, x1 = -7872 },
	{ z0 = -7709.5, z1 = -7677.5, x0 = -8142, x1 = -7858 },
	{ z0 = -7677.5, z1 = -7637.5, x0 = -8154, x1 = -7846 },
	{ z0 = -7637.5, z1 = -7589.5, x0 = -8164, x1 = -7836 },
	{ z0 = -7589.5, z1 = -7525.5, x0 = -8176, x1 = -7824 },
	{ z0 = -7525.5, z1 = -7469.5, x0 = -8188, x1 = -7812 },
	{ z0 = -7469.5, z1 = -7157.5, x0 = -8190, x1 = -7810 },
	{ z0 = -7157.5, z1 = -7117.5, x0 = -8178, x1 = -7822 },
	{ z0 = -7117.5, z1 = -7077.5, x0 = -8170, x1 = -7830 },
	{ z0 = -7077.5, z1 = -7037.5, x0 = -8162, x1 = -7838 },
	{ z0 = -7037.5, z1 = -7013.5, x0 = -8150, x1 = -7850 },
	{ z0 = -7013.5, z1 = -6989.5, x0 = -8134, x1 = -7860 },
	{ z0 = -6989.5, z1 = -6957.5, x0 = -8130, x1 = -7872 },
	{ z0 = -6957.5, z1 = -6933.5, x0 = -8116, x1 = -7884 },
	{ z0 = -6933.5, z1 = -6909.5, x0 = -8102, x1 = -7898 },
	{ z0 = -6909.5, z1 = -6901.5, x0 = -8082, x1 = -7918 },
	{ z0 = -6901.5, z1 = -6885.5, x0 = -8069, x1 = -7923 },
	{ z0 = -6885.5, z1 = -6877.5, x0 = -8038, x1 = -7956 },
	{ z0 = -6877.5, z1 = -6869.5, x0 = -8028, x1 = -7972 },
}

-- ===== ICE PALETTE ===========================================================
-- Frozen, not sci-fi: pale near-white ice, Snow for drifts, Ice for the linear detail
-- (cracks, scoured patches). Nothing here emits light.
-- THE ICE IS THE MID-TONE, THE SNOW IS THE HIGHLIGHT. This started at 214,234,246 --
-- nearly white -- and the lake read as a flat white plane no matter how much detail went
-- on it, because white drifts on a white base have no edge under Roblox's flat outdoor
-- light. Dropping the sheet to a blue-grey mid-tone gives everything laid on top of it
-- somewhere to read FROM, and it is also what a swept frozen lake actually looks like:
-- the wind-scoured ice is darker than the snow drifted over it.
--
-- Grey-blue, not cyan. The terrain water is 20,105,175 -- far darker and far more
-- saturated -- so this cannot be mistaken for open water, which is the failure mode that
-- bit the Ice-material panels twice.
IceFishingConfig.ICE_COLOR   = Color3.fromRGB(188, 210, 230)
IceFishingConfig.SNOW_COLOR  = Color3.fromRGB(246, 251, 255)
-- THE VALUE STRUCTURE. One colour across 380 x 920 studs reads as a white plane no matter
-- how much detail is scattered on it, so the surface is built from broad tonal fields in
-- these three tones plus SNOW_COLOR: bright fresh drift, cool wind-packed, and the blue
-- shade that sits in every hollow. They are close together on purpose -- this is a value
-- structure, not a colour scheme, and anything more separated stops reading as snow.
IceFishingConfig.SNOW_COOL  = Color3.fromRGB(224, 238, 250)
IceFishingConfig.SNOW_SHADE = Color3.fromRGB(196, 216, 234)
IceFishingConfig.SNOW_DEEP  = Color3.fromRGB(168, 192, 216)
IceFishingConfig.BARE_COLOR  = Color3.fromRGB(170, 196, 220)
IceFishingConfig.CRACK_COLOR = Color3.fromRGB(150, 186, 212)
IceFishingConfig.CHUNK_COLOR = Color3.fromRGB(226, 242, 252)
-- HOW DARK THE HOLE CAN ACTUALLY GET. The tundra runs an Atmosphere at Density 0.26 and
-- HAZE 1.9 -- a deliberate snowy haze for the whole world -- which washes everything
-- toward pale blue no matter how close it is. Measured by flagging these parts pure
-- magenta: they came back PINK. So dark water here is a contrast trick, not a colour:
-- these are set as dark as is useful, the darkest tone covers most of the visible pool
-- (see the PoolMid/PoolDeep sizes in buildHole), and the snow collar right around the rim
-- does the rest by being as bright as possible. Do not chase this by touching the
-- Atmosphere -- it is the look of the whole world, not of this event.
-- The pool ramp: FIVE steps, and all of them dark. This was three tones inside 20 of
-- each other (12,30,44 / 6,17,27 / 2,8,14) and the haze above closed even that, so the
-- hole read as a flat black sticker rather than water. Widening the ramp DOWNWARD is
-- what fixed it -- the shelf was also tried the other way, lifted to a wet teal with
-- real Reflectance, and it read as a glowing blue portal, which this world does not do.
-- BoreWet is the wet ring right at the waterline and is the lightest of the five; the
-- rest step down to a near-black core that gives the eye a true darkest point.
-- buildHole stacks them innermost-HIGHEST; see the note there before reordering.
IceFishingConfig.WET_COLOR   = Color3.fromRGB(46, 76, 96)    -- BoreWet, the waterline ring
IceFishingConfig.POOL_COLOR  = Color3.fromRGB(22, 46, 62)    -- shelf water
IceFishingConfig.POOL_MID    = Color3.fromRGB(11, 27, 39)
IceFishingConfig.POOL_DEEP   = Color3.fromRGB(5, 13, 21)
IceFishingConfig.POOL_CORE   = Color3.fromRGB(2, 6, 10)

-- how much of the sheet is dressed: drifts, wind-scoured panels, cracks, pressure
-- ridges, frozen-in floes and the rubble along the bank. Costs about 250 anchored parts.
IceFishingConfig.DRIFTS  = 48
IceFishingConfig.PANELS  = 22
IceFishingConfig.CRACKS  = 26
IceFishingConfig.FLOES   = 12
IceFishingConfig.RUBBLE  = 44
-- Second detail pass. SASTRUGI are the wind-carved snow ripples that give the surface a
-- grain underfoot (the tundra map already names its shore ones Sastruga) and TRAIL is the
-- packed path worn from the dock out to the first pair of holes.
IceFishingConfig.SASTRUGI = 74
IceFishingConfig.TRAIL    = 24
IceFishingConfig.SPINDRIFT = 5
-- Third pass, and the one that actually changed how the lake reads. FIELDS are the broad
-- tonal patches described above; HUMMOCKS are snow-covered swells that give the sheet
-- topography instead of being a plane; BERM is the snow banked against the shore, which
-- both frames the lake and hides the stepped edge of the strips; MIST is the low fog that
-- gives the far end of the lake any depth at all.
IceFishingConfig.FIELDS   = 30
IceFishingConfig.HUMMOCKS = 18
IceFishingConfig.BERM     = 46
IceFishingConfig.MIST     = 7
-- One wind bearing for the whole lake: sastrugi align to it, spindrift blows along it and
-- each hole's snow banks downwind of it. Without a shared bearing the detail reads as a
-- field of unrelated random props instead of one weather system.
IceFishingConfig.WIND_ANGLE = math.rad(28)

-- Each hole gets a little camp: a lantern post visible from across the ice, a crate and a
-- bucket. Lantern colour is the tundra's own lantern warm, NOT a cold glow -- it is the
-- one warm thing out on the lake and it should read that way.
IceFishingConfig.LANTERN_COLOR = Color3.fromRGB(255, 232, 176)
IceFishingConfig.WOOD_COLOR    = Color3.fromRGB(122, 86, 54)
IceFishingConfig.WOOD_DARK     = Color3.fromRGB(84, 58, 36)

-- Half-extents used to decide who is standing OUT ON THE LAKE at thaw (for the kick).
-- A shade inside the ring so someone on the dock lip is not swept up with the fishers.
IceFishingConfig.LAKE_HALF_X = 195
IceFishingConfig.LAKE_HALF_Z = 470
IceFishingConfig.ICE_MIN_Y   = 2001            -- above this y (and inside XZ) = on the ice

-- ===== FISHING HOLES =========================================================
-- Offsets from LAKE_CENTER on the XZ plane. dz negative = toward the dock (south),
-- positive = out toward the far ice. The first pair sits close to the dock so there is
-- always a hole in sight the moment you step onto the ice.
--
-- HOLE_RADIUS is the real radius of the cut -- the sheet is genuinely subtracted, so a
-- hole is an opening you look down through, not a dark disc painted on top. Keep every
-- hole inside its band's water width in LAKE_PROFILE or the cut will hang off the ice.
IceFishingConfig.HOLE_RADIUS = 9
IceFishingConfig.HOLE_REACH  = 17     -- how close you must stand for the prompt to offer
IceFishingConfig.HOLES = {
	{ dx = -70,  dz = -420 }, { dx = 70,  dz = -420 },
	{ dx = -95,  dz = -300 }, { dx = 95,  dz = -300 },
	{ dx = -110, dz = -110 }, { dx = 110, dz = -110 },
	{ dx = 0,    dz = 40 },
	{ dx = -95,  dz = 210 },  { dx = 95,  dz = 210 },
	{ dx = 0,    dz = 370 },
}

-- ===== ROD ===================================================================
-- A worn rod, same idea as the rock sling -- and it REPLACES the sling for the length of
-- the event (RockSlingService.SetHidden), so a tundra player carries a rod or a satchel,
-- never both. Server-built so everyone sees it. Dimensions are fractions of the wearer's
-- torso (set in RodService), so only colours/materials live here.
IceFishingConfig.ROD_SHAFT_COLOR = Color3.fromRGB(120, 80, 44)   -- kept: older callers
IceFishingConfig.ROD_LINE_COLOR  = Color3.fromRGB(235, 245, 255)
IceFishingConfig.ROD_REEL_COLOR  = Color3.fromRGB(70, 74, 82)
-- The blank is DARKER than the grip on purpose. A rod that is one wood colour end to end
-- reads as a broom handle; the dark taper against a pale cork grip is most of what makes
-- the silhouette say "fishing rod" at gameplay distance, before any of the detail lands.
IceFishingConfig.ROD_BLANK_COLOR = Color3.fromRGB(66, 50, 40)
IceFishingConfig.ROD_TIP_COLOR   = Color3.fromRGB(44, 34, 28)
IceFishingConfig.ROD_GRIP_COLOR  = Color3.fromRGB(196, 158, 104)
IceFishingConfig.ROD_METAL_COLOR = Color3.fromRGB(158, 164, 176)

-- ===== ROCK STATS -> ROD =====================================================
-- The equipped rock's REACH sets how fast a bite comes (a longer-reaching rock fishes
-- faster) and its LUCK will feed catch rarity once the pool exists. Reach is clamped to
-- the ladder's real span (Pebble 25 .. the 900 cap) and mapped linearly onto the bite band.
IceFishingConfig.REACH_MIN, IceFishingConfig.REACH_MAX = 25, 900
IceFishingConfig.BITE_SLOW, IceFishingConfig.BITE_FAST = 5.5, 2.0   -- seconds, worst -> best reach

-- ===== CAST TIMING ===========================================================
-- Shared by the three places that must agree or the animation desyncs from the fiction:
-- ClientMain's cast pose (the reach, wind-back and flick), IceFishingEvent (when the line
-- and float actually appear, and when the hook minigame is allowed to start) and
-- IceFishingClient (which holds its panel on "Casting..." until then).
--
-- CAST_LEAD must match the flick key in ClientMain's SEQ.cast: it is the moment the rod
-- tip stops travelling, so it is the moment the float can believably hit the water.
-- Everything downstream is timed from there rather than from the button press, so a cast
-- never eats into HOOK_TIMEOUT.
IceFishingConfig.CAST_LEAD  = 0.56   -- cast starts -> float hits the water, minigame starts
IceFishingConfig.SET_TIME   = 0.45   -- float ducking under -> the catch reveal
IceFishingConfig.STOW_DELAY = 2.20   -- resolved -> the rod goes back on your back. Must
                                     -- outlast the catch sequence (1.92s) or the rod
                                     -- vanishes out of the character's hands mid-reel.

-- ===== WALK-UP CASTING =======================================================
-- There is no button and no keypress to START fishing: stand by a hole and the character
-- casts on its own. DWELL stops a cast firing at everyone who merely runs past a hole,
-- and RECAST_WAIT is the beat between one fish being landed (or lost) and the line going
-- back out, so standing at a hole fishes it on a loop. The only input in the whole loop
-- is the click that hooks the fish.
IceFishingConfig.CAST_DWELL  = 0.35
IceFishingConfig.RECAST_WAIT = 1.40

-- CHARGE-TO-CAST: casting is a hold-and-release, like winding up a rock throw -- hold to
-- fill the meter, release to cast the line. CAST_CHARGE_TIME is a full wind-up; releasing
-- under MIN_CAST_POWER is treated as a mis-tap and does not cast. (This replaces the old
-- auto-cast-on-dwell; CAST_DWELL is now unused but kept for reference.)
IceFishingConfig.CAST_CHARGE_TIME = 0.85
IceFishingConfig.MIN_CAST_POWER   = 0.15

-- ===== PERFECT CAST (the sweet-spot timing bonus) ============================
-- Release the charge INSIDE the sweet-spot band and the whole cast fishes at PERFECT_LUCK_MULT
-- luck -- it lifts the bite rarity (RollBite) and the eventual catch (RollCatch) together.
-- This is the ice-fishing cousin of the skip-rock perfect throw (ThrowHandler): the band is
-- ISSUED BY THE SERVER per charge, single-use and aged, so the client only ever DRAWS it --
-- it can neither declare its own casts perfect nor replay one good band across casts.
--
-- WHY THE BAND IS NOT AT THE TOP. The charge is a hold, so the lazy input is "hold to full".
-- If the band sat at power = 1 that lazy hold would be perfect every time and the 2x would be
-- baseline, not a reward for timing -- the exact trap the skip-rock band fell into. It rolls
-- inside PERFECT_BAND_LO..PERFECT_BAND_HI and never reaches 1, so a perfect means releasing
-- EARLY, on purpose, trading a little cast power for the luck. (Cast power is cosmetic here --
-- bite speed comes from rock REACH, not power -- so the only thing you trade is the timing.)
IceFishingConfig.PERFECT_LUCK_MULT  = 2.0
IceFishingConfig.PERFECT_BAND_LO    = 0.55   -- earliest the band's LEFT edge may roll
IceFishingConfig.PERFECT_BAND_HI    = 0.80   -- latest the band's left edge may roll (max+width stays < 1)
IceFishingConfig.PERFECT_BAND_WIDTH = 0.10   -- band width as a fraction of the meter
IceFishingConfig.PERFECT_BAND_MAX_AGE = 30   -- seconds a charge may idle before perfect stops counting

function IceFishingConfig.BiteTime(reach)
	local r = math.clamp((reach or 25), IceFishingConfig.REACH_MIN, IceFishingConfig.REACH_MAX)
	local t = (r - IceFishingConfig.REACH_MIN) / (IceFishingConfig.REACH_MAX - IceFishingConfig.REACH_MIN)
	return IceFishingConfig.BITE_SLOW + (IceFishingConfig.BITE_FAST - IceFishingConfig.BITE_SLOW) * t
end

-- ===== HOOK MINIGAME =========================================================
-- After the line is cast, a marker sweeps a bar (like the skip power meter) and a green
-- BITE zone sits at a random spot on it; you click when the marker is over the green to
-- hook the fish. A better rock (more REACH) WIDENS the green, so a stronger rod is easier
-- to land; miss the green -- or run out of time -- and the fish gets away. The marker
-- animation lives on the client; the server decides where the green is and judges the
-- reported click, so the timing feel is client-smooth but the outcome is server-owned.
IceFishingConfig.GREEN_MIN_W   = 0.11   -- green width (fraction of the bar) at REACH_MIN
IceFishingConfig.GREEN_MAX_W   = 0.26   -- ...and at the 900 reach cap: a wider, easier green
-- 2.2 was too quick to read: at a 0.26-wide green the marker crossed the whole zone
-- in under a third of a second, so landing one felt like a reflex check rather than
-- timing. 3.1 keeps the same green widths and the same 7s timeout -- only the sweep
-- slows -- so it reads as more generous without changing any of the odds.
IceFishingConfig.MARKER_PERIOD = 3.1    -- seconds for a full left -> right -> left sweep (higher = slower/easier)
IceFishingConfig.HOOK_TIMEOUT  = 7      -- seconds to land a click before the fish gives up

function IceFishingConfig.GreenWidth(reach)
	local r = math.clamp((reach or IceFishingConfig.REACH_MIN), IceFishingConfig.REACH_MIN, IceFishingConfig.REACH_MAX)
	local t = (r - IceFishingConfig.REACH_MIN) / (IceFishingConfig.REACH_MAX - IceFishingConfig.REACH_MIN)
	return IceFishingConfig.GREEN_MIN_W + (IceFishingConfig.GREEN_MAX_W - IceFishingConfig.GREEN_MIN_W) * t
end

-- ===== MULTI-STEP REEL =======================================================
-- Higher-rarity fish take MORE clicks to land, and the green SHRINKS with each successful
-- click, so the last pull of a big fish is the tightest. The number of clicks is decided
-- at cast time by what's biting (RollBite); the green starts at GreenWidth(reach) and is
-- multiplied by GREEN_SHRINK each step, floored at GREEN_MIN_FLOOR so it stays hittable.
IceFishingConfig.GREEN_SHRINK    = 0.72
IceFishingConfig.GREEN_MIN_FLOOR = 0.06
IceFishingConfig.REEL_STEPS = {   -- clicks to land, by rarity
	Common = 1, Uncommon = 1, Rare = 2, Epic = 2, Legendary = 3, Mythic = 3, Secret = 4,
}

-- STUB "what's on the line" roll. Picks a rarity (luck biases toward the rarer tiers) and
-- maps it to a click count. When the exclusive fishing brainrots land, replace the rarity
-- PICK with the real weighted pool but keep returning { Rarity, Steps } and the minigame
-- (and everything below) is unchanged.
IceFishingConfig.BITE_WEIGHTS = {
	{ "Common", 1000 }, { "Uncommon", 600 }, { "Rare", 340 }, { "Epic", 170 },
	{ "Legendary", 66 }, { "Mythic", 20 }, { "Secret", 5 },
}
function IceFishingConfig.RollBite(luck, reach)
	luck = math.max(luck or 1, 1)
	local weighted, total = {}, 0
	for i, e in ipairs(IceFishingConfig.BITE_WEIGHTS) do
		-- luck lifts the rarer tiers (i grows with rarity); Common (i=1) is never boosted
		local w = e[2] * (1 + (luck - 1) * (i - 1) * 0.06)
		weighted[i] = w
		total += w
	end
	local r, acc = math.random() * total, 0
	local name = IceFishingConfig.BITE_WEIGHTS[1][1]
	for i, e in ipairs(IceFishingConfig.BITE_WEIGHTS) do
		acc += weighted[i]
		if r <= acc then name = e[1]; break end
	end
	return { Rarity = name, Steps = IceFishingConfig.REEL_STEPS[name] or 1 }
end

-- ===== CATCH =================================================================
-- The real pool, grouped by rarity once at module load (same style as MutationConfig's
-- ByName / ThrowHandler's rockById): every BrainrotConfigTundra entry carrying
-- Origin = "IceFishing", bucketed under its Rarity. FishWeight sums to 1000 within a
-- populated tier (see BrainrotConfigTundra's header), so a fish's odds WITHIN its rarity
-- are FishWeight / 1000 -- RollBite above already decided the rarity itself.
local FISH_BY_RARITY = {}
for _, e in ipairs(BrainrotConfigTundra) do
	if e.Origin == "IceFishing" then
		FISH_BY_RARITY[e.Rarity] = FISH_BY_RARITY[e.Rarity] or {}
		table.insert(FISH_BY_RARITY[e.Rarity], e)
	end
end

-- Picks ONE fish of `rarity` (already rolled by RollBite, luck and all), weighted by
-- FishWeight. luck/reach are accepted -- RollBite's signature and the server's existing
-- call site both carry them -- but the pick itself does not re-read luck: rarity is where
-- luck already did its work, and re-applying it here would double-dip the same roll.
--
-- Returns the roster ENTRY itself (Name, Rarity, CashPerSecond, Weight = 0, Origin,
-- FishWeight) so the caller can grant a real fish straight off it, or nil if `rarity` has
-- no fish -- e.g. "God", which RollBite can never actually produce (BITE_WEIGHTS stops at
-- Secret) but which must still come back nil rather than error if ever asked for.
--
-- PURE: reads FISH_BY_RARITY (built once above, never mutated) and math.random only. No
-- writes, no yields -- safe for the client to call as well, exactly like RollBite.
function IceFishingConfig.RollCatch(rarity, luck, reach)
	local pool = FISH_BY_RARITY[rarity]
	if not pool or #pool == 0 then return nil end
	local total = 0
	for _, e in ipairs(pool) do total += (e.FishWeight or 0) end
	if total <= 0 then return nil end
	local r, acc = math.random() * total, 0
	for _, e in ipairs(pool) do
		acc += (e.FishWeight or 0)
		if r <= acc then return e end
	end
	return pool[#pool]   -- floating-point guard; never reached with FishWeight sums intact
end

return IceFishingConfig
