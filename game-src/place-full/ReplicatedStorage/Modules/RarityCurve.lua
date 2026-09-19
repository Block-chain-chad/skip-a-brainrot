-- RarityCurve: probabilistic rarity. DISTANCE unlocks higher tiers and shifts the odds
-- toward them; LUCK shifts them further; higher tiers are geometrically rarer and nothing
-- is guaranteed. Shared so ThrowHandler (the real roll) and LuckHUDClient (the displayed
-- odds) read IDENTICAL numbers -- change a tunable here and both move together.
--
-- PER-WORLD. Each world has its own ladder (see WorldProgression), so the curve is built
-- per world and cached. The apex tier -- the one with an infinite band -- is NOT part of
-- the curve: the curve tops out below it, and ThrowHandler gives the apex its shot by
-- routing a top-of-curve roll through RarityRoll.PickInTier(ApexIndex). That is how
-- Secret Pete works in the valley and how Glitched works in the tundra.
--
-- The module-level functions are World 1 (the default) so every existing caller --
-- LuckHUDClient especially -- keeps working untouched.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldProgression = require(ReplicatedStorage.Modules.WorldProgression)

local RarityCurve = {}

-- === TUNABLES (retune difficulty here) ===
RarityCurve.TIER_STEP = 0.40        -- each higher tier's base weight is this x the previous. LOWER = rarer top tiers.
RarityCurve.RAMP = 160              -- studs for a tier to fade from 0 -> full weight past its unlock distance
-- how strongly access-luck shifts the curve toward higher tiers.
-- RESCALED for ADDITIVE luck (ThrowHandler): accessLuck is now a SUM of bonuses, so a
-- maxed setup lands near +7 (or ~+11 with a placed Maxwell) instead of the old
-- multiplicative ~x20/x100. This factor was 0.18 against those big numbers; at 0.55 a
-- typical maxed additive luck gives about the same top-tier tilt (lf ~4.4) the old
-- ~x20 luck did, while the runaway Maxwell/pet stacks no longer blow the curve open.
-- This is THE knob for how much luck matters vs distance -- raise to make luck count more.
RarityCurve.LUCK_INFLUENCE = 0.55

-- Per-world, per-tier weight multipliers. Nudges a SPECIFIC tier's odds up without
-- touching the global TIER_STEP (which would move every tier, Secret included). Unlisted
-- worlds and unlisted tiers default to 1.0, so this is purely additive tuning. The tier
-- index is the position in that world's RarityConfig (Valley: 5=Legendary, 6=Mythic,
-- 7=Secret). VALLEY-ONLY on purpose: World 1 should feel more generous for new players --
-- Legendary/Mythic land a bit more often -- while Secret is left at 1.0 so the chase tier
-- stays as rare as before. The Tundra has NO entry, so World 2 keeps its full grind.
-- NOTE: because the roll is normalised, boosting Legendary/Mythic does shave a few points
-- off Secret at the very top of the curve (maxed luck + a perfect ~900m throw); everywhere
-- a new or mid-game player actually plays, Secret is unchanged.
RarityCurve.TIER_BIAS = {
	-- Legendary/Mythic get a MODEST lift over baseline (World 1 feels a bit kinder), while
	-- Secret is pushed slightly BELOW baseline (x0.90) so it stays a genuinely rare chase.
	-- An earlier pass lifted Leg/Myth much harder (1.5/1.25) -- that read too easy, so this
	-- is the dialled-back version. Tundra still has no entry -> World 2 grind untouched.
	Valley = { [5] = 1.30, [6] = 0.42, [7] = 0.062 }, -- Legendary x1.30, Mythic x0.42, Secret x0.062
	-- SECRET CUT (2026-08-12). Was 0.90, which put Secret on ~31% of maxed throws
	-- (luck +7) and ~49% with a placed Maxwell -- measured, not estimated. The cause is
	-- the weight formula's lf^(i-1): at tier 7 that is luck to the SIXTH power, so a
	-- luck factor of 4.3 multiplies Secret's weight by ~6,321x and swamps the 0.4^6
	-- rarity step. Cutting the per-tier bias is the world-scoped knob for this -- it
	-- leaves TIER_STEP and LUCK_INFLUENCE alone, so World 2 is untouched.
	--
	-- MYTHIC CUT (2026-08-19). The Secret cut above did NOT reduce how often World 1
	-- hands out a top-tier catch -- it MOVED it down one rung. The roll is normalised,
	-- so the ~39 points Secret gave up at luck 11 were redistributed across the tiers
	-- that were left, and Mythic (the largest remaining weight at 900 studs) absorbed
	-- 23.6 of them: 31.02% -> 54.63%. Measured, not estimated.
	--
	-- The bug is SATURATION, not generosity. Rocks and luck are SUPPOSED to make the
	-- high rarities easier -- that is the core loop -- so this is deliberately not a
	-- flattening. At 1.12 the ladder inverted at the top (Mythic 54.6% vs Legendary
	-- 24.4%), which leaves a maxed player with nothing above them to chase. At 0.42 it
	-- reads Legendary 39.1% -> Mythic 33.0% -> Secret 9.5%: still ~82% Legendary-or-
	-- better for a maxed setup, but the prize varies.
	--
	-- Luck gets STEEPER, not weaker. Mythic across luck 1 -> 11 at 900 studs goes from
	-- 80x (0.69 -> 54.63) to 127x (0.26 -> 33.00); Secret from 528x to 793x. Distance
	-- stays a real lever too -- Secret is 1.7% at 800 studs against 9.5% at 900.
	--
	-- [7] moved 0.10 -> 0.062 in the SAME pass and for the same normalisation reason:
	-- cutting Mythic alone would have pushed Secret back up to ~11.5% at luck 11. The
	-- pair is solved together so Secret lands exactly where it already was (9.51% at
	-- luck 11) and slightly lower mid-ladder. Retune [6] and [7] TOGETHER or Secret
	-- will drift as a side effect.
}

local cache = {}

-- Build (and remember) the curve for one world. Each tier's unlock distance is its
-- MinDistance, read straight from that world's ladder, so the curve tracks the roster.
function RarityCurve.For(worldName)
	local key = WorldProgression.NameFor(worldName)
	local c = cache[key]
	if c then return c end

	local ladder = WorldProgression.Resolve(key).Rarities
	local UNLOCK, TOP = {}, 0
	for i, t in ipairs(ladder) do
		if t.MaxDistance ~= math.huge then
			UNLOCK[i] = t.MinDistance
			TOP = i
		end
	end

	c = { World = key, Rarities = ladder, TopTier = TOP, ApexIndex = TOP + 1 }
	-- kept for callers written before worlds existed
	c.GodIndex = c.ApexIndex

	function c.Weights(distance, accessLuck)
		local lf = 1 + (math.max(accessLuck or 1, 1) - 1) * RarityCurve.LUCK_INFLUENCE
		local bias = RarityCurve.TIER_BIAS[key]   -- per-tier nudges for this world, or nil
		local w = {}
		for i = 1, TOP do
			if distance < UNLOCK[i] then
				w[i] = 0
			else
				local ramp = math.clamp((distance - UNLOCK[i]) / RarityCurve.RAMP, 0, 1)
				local b = (bias and bias[i]) or 1
				w[i] = ramp * (RarityCurve.TIER_STEP ^ (i - 1)) * (lf ^ (i - 1)) * b
			end
		end
		return w
	end

	function c.Probabilities(distance, accessLuck)
		local w = c.Weights(distance, accessLuck)
		local sum = 0
		for i = 1, TOP do sum += w[i] end
		local p = {}
		for i = 1, TOP do p[i] = (sum > 0) and (w[i] / sum) or 0 end
		if sum <= 0 then p[1] = 1 end   -- thrown nowhere: treat as Common
		return p
	end

	function c.RollTierIndex(distance, accessLuck)
		local w = c.Weights(distance, accessLuck)
		local sum = 0
		for i = 1, TOP do sum += w[i] end
		if sum <= 0 then return 1 end
		local r = math.random() * sum
		local acc = 0
		for i = 1, TOP do
			acc += w[i]
			if r <= acc then return i end
		end
		return TOP
	end

	cache[key] = c
	return c
end

-- ---- default-world passthrough, so pre-world callers are unaffected ----
local default = RarityCurve.For(WorldProgression.Default)
RarityCurve.TopTier = default.TopTier
RarityCurve.GodIndex = default.ApexIndex
RarityCurve.ApexIndex = default.ApexIndex
function RarityCurve.Weights(d, l) return default.Weights(d, l) end
function RarityCurve.Probabilities(d, l) return default.Probabilities(d, l) end
function RarityCurve.RollTierIndex(d, l) return default.RollTierIndex(d, l) end

return RarityCurve
