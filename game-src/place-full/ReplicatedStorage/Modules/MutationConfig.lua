-- MutationConfig: rare stacking variants that multiply a brainrot's cash/sec.
-- Shared by ThrowHandler (roll), IncomeLoop (multiplier), FusionHandler (ladder)
-- and the client (display).
--
-- ===================== RAINBOW & GLITCHED: NOW CATCHABLE =======================
-- UPDATE 2026-08-22 (owner's call): the fusion system is being retired, so Rainbow
-- and Glitched are CATCHABLE from an ordinary throw in ANY lake at a rare rate --
-- see their entries in Mutations.List below (FusionOnly removed, Chance set). The
-- historical fusion-only rationale is kept below for context but no longer applies.
-- ============================ (was) FUSION-ONLY ================================
-- Rainbow and Glitched are the two most desirable mutations in the game, and as
-- of this change they do NOT drop from a throw at all. `FusionOnly = true` makes
-- Roll() skip them. The only way to get one is to climb the fusion ladder in
-- ServerScriptService.Modules.FusionHandler (5 identical UNPLACED copies of the
-- same brainrot -> 1 copy at the next tier):
--
--     nil -> Golden -> Diamond -> Rainbow -> Glitched      (Glitched is terminal)
--
-- WHY:
--  * Supply. While they dropped natively their supply was unbounded -- anyone
--    who threw long enough eventually got one, so time-at-keyboard rather than
--    effort set the price, and every copy was worth exactly the next. Making
--    them fusion-only turns them into goods CAPPED BY EFFORT: fusing all the
--    way up from plain copies, one Rainbow costs 125 copies of the SAME
--    brainrot (5 -> Golden, 25 -> Diamond, 125 -> Rainbow) and one Glitched
--    costs 625. That is a real, countable price floor a trade can be argued
--    against. Natural Golden (13.5%) and Diamond (5.5%) drops shorten the
--    climb, which is precisely why those two keep their rates -- they are the
--    raw material the ladder eats.
--  * It gives fusion a reason to exist. Before, fusion topped out at Rainbow,
--    which you could also simply find, so the sink was optional flavour that a
--    patient player could ignore. Now it is the ONLY door to the top two tiers,
--    so the duplicate brainrots players already drown in finally have somewhere
--    to go, and every fuse permanently destroys 5 items.
--  * The ceiling still rises with skill, not grind alone: you may only fuse
--    copies of the SAME brainrot, so a Glitched Secret stays a genuinely
--    different achievement from a Glitched common.
--
-- DELIBERATELY NOT DELETED from Mutations.List. Existing player-owned Rainbow
-- and Glitched copies -- and every one fused from here on -- still need Mult(),
-- Color(), Rarity() and the ByName lookup to resolve. Deleting the entries would
-- silently drop those brainrots to x1 cash with no tint. The entries stay; only
-- Roll() changes, declaratively, via the FusionOnly flag.
--
-- Weather is unaffected. Mutations.Events maps each weather event to its OWN
-- mutation (Wet / Sandy / Electric / Frozen / Aurora / Celestial / Demon /
-- Angel); none of those is Rainbow or Glitched, so no live event can force-roll
-- a fusion-only variant. If a future event is ever pointed at one, it would
-- bypass this cap entirely -- don't.
-- ==============================================================================
local Mutations = {}

-- Rarity ladder, weakest to strongest (Rarity = position in that order):
--   1 Gold  2 Diamond  3 Wet  4 Sandy  5 Rainbow  6 Electric
--   7 Frozen  8 Aurora  9 Celestial  10 Glitched  11 Demon  12 Angel
-- The four "base" variants sit at ladder slots 1/2/5/10. Golden/Diamond are the
-- common base drops; Rainbow (5) and Glitched (10) are catchable anywhere at a rare
-- rate (2026-08-22). Base mults are now 2/5/12/31; event variants interpolate between
-- these on the ladder. (High tier was trimmed 2026-08-22: Rainbow 15->12, Glitched
-- 50->31, and the event variants down with them.)
Mutations.List = {
	{ Name = "Golden",   Rarity = 1,  Mult = 2,  Chance = 0.135,  Color = Color3.fromRGB(255, 215, 60) },
	{ Name = "Diamond",  Rarity = 2,  Mult = 5,  Chance = 0.055,  Color = Color3.fromRGB(120, 230, 255) },
	-- CATCHABLE ANYWHERE (2026-08-22): Rainbow and Glitched now drop from an ordinary
	-- throw in any lake at a rare rate -- no weather, no fusion required (fusion retired).
	-- They are the two rarest BASE drops (Rainbow rarer than Diamond, Glitched rarest of
	-- all), so a big catch can happen anywhere. Mults trimmed with the rest of the high
	-- tier (Rainbow 15->12, Glitched 50->31).
	{ Name = "Rainbow",  Rarity = 5,  Mult = 12, Chance = 0.0145, Color = Color3.fromRGB(255, 120, 220) },
	{ Name = "Glitched", Rarity = 10, Mult = 31, Chance = 0.0025, Color = Color3.fromRGB(150, 255, 130) },
}

-- Event-exclusive mutations: each can only roll while its own weather event is
-- live, at the fixed chance below. Deliberately kept OUT of Mutations.List so
-- they never appear on an ordinary catch, and so the fusion ladder (which is an
-- explicit map in FusionHandler) is unaffected -- these are terminal rewards.
-- Chance here is CONDITIONAL: the odds while that event is live. It is tuned so
-- the EFFECTIVE per-catch rate falls at every rung of the ladder, Gold down to
-- Angel. The two columns differ a lot because a rare event is live only a sliver
-- of the session -- Shooting Star runs ~3.8% of the time, so Celestial needs a
-- higher in-event chance just to stay commoner than Glitched. The "eff" comment
-- is the real drop rate; the raw Chance column is NOT the ladder.
--
-- These are calibrated against the WeatherHandler cycle: 180s Clear + 20s warning
-- + a 4-7min event (330s avg), so an event is live ~62% of the time. Change any
-- of those durations and these need recomputing, or the ladder breaks.
Mutations.Events = {
	["Fog"]           = { Name = "Wet",       Rarity = 3,  Mult = 7,  Chance = 0.211, Color = Color3.fromRGB(90, 170, 255) },   -- eff 3.50%
	["Sandstorm"]     = { Name = "Sandy",     Rarity = 4,  Mult = 10, Chance = 0.166, Color = Color3.fromRGB(214, 176, 112) },  -- eff 2.30%
	["Thunderstorm"]  = { Name = "Electric",  Rarity = 6,  Mult = 14, Chance = 0.060, Color = Color3.fromRGB(255, 240, 100) },  -- eff 0.70%
	["Blizzard"]      = { Name = "Frozen",    Rarity = 7,  Mult = 17, Chance = 0.063, Color = Color3.fromRGB(172, 236, 255) },  -- eff 0.52%
	["Aurora"]        = { Name = "Aurora",    Rarity = 8,  Mult = 21, Chance = 0.066, Color = Color3.fromRGB(120, 255, 190) },  -- eff 0.40%
	["Shooting Star"] = { Name = "Celestial", Rarity = 9,  Mult = 26, Chance = 0.084, Color = Color3.fromRGB(198, 210, 255) },  -- eff 0.32%
	["Blood Moon"]    = { Name = "Demon",     Rarity = 11, Mult = 36, Chance = 0.051, Color = Color3.fromRGB(220, 48, 48) },    -- eff 0.070%
	["Golden Hour"]   = { Name = "Angel",     Rarity = 12, Mult = 42, Chance = 0.032, Color = Color3.fromRGB(255, 242, 190) },  -- eff 0.018%
}

Mutations.ByName = {}
for _, m in ipairs(Mutations.List) do
	Mutations.ByName[m.Name] = m
end
-- event variants share the same lookup, so Mult()/Color() work for both
for _, m in pairs(Mutations.Events) do
	Mutations.ByName[m.Name] = m
end

-- returns a mutation Name, or nil for an ordinary catch.
-- boost (>1, from weather events) scales the odds of every base variant.
-- eventName (the live weather event) gives that event's own mutation first
-- refusal at its exact listed chance -- boost is NOT applied there, since those
-- odds are already tuned per event and would otherwise double-dip.
-- The `if not m.FusionOnly` guard below is now vacuous (no List entry sets it
-- anymore -- Rainbow/Glitched became catchable 2026-08-22) but is kept as a cheap
-- safety net. Each base variant contributes its absolute Chance to the cumulative
-- total; the leftover probability is "no mutation".
function Mutations.Roll(boost, eventName)
	local ev = eventName and Mutations.Events[eventName]
	if ev and math.random() < ev.Chance then
		return ev.Name
	end
	boost = boost or 1
	local r = math.random()
	local cum = 0
	for _, m in ipairs(Mutations.List) do
		if not m.FusionOnly then
			cum += math.min(m.Chance * boost, 0.5)
			if r < cum then return m.Name end
		end
	end
	return nil
end

function Mutations.Mult(name)
	local m = name and Mutations.ByName[name]
	return m and m.Mult or 1
end

function Mutations.Color(name)
	local m = name and Mutations.ByName[name]
	return m and m.Color or nil
end

-- position on the rarity ladder (1 = weakest, 12 = strongest); 0 = no mutation
function Mutations.Rarity(name)
	local m = name and Mutations.ByName[name]
	return m and m.Rarity or 0
end

-- every variant, weakest -> strongest; handy for UI listings and sorting
Mutations.Order = {}
for _, m in pairs(Mutations.ByName) do table.insert(Mutations.Order, m) end
table.sort(Mutations.Order, function(a, b) return a.Rarity < b.Rarity end)

return Mutations
