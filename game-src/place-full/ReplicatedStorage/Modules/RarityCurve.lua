-- RarityCurve: probabilistic rarity. DISTANCE unlocks higher tiers and shifts the odds
-- toward them; LUCK shifts them further; higher tiers are geometrically rarer and nothing
-- is guaranteed. Shared so ThrowHandler (the real roll) and LuckHUDClient (the displayed
-- odds) read IDENTICAL numbers -- change a tunable here and both move together.
--
-- God (Secret Pete) is NOT part of the curve: he is an independent FixedChance handled in
-- RarityRoll.PickInTier. The curve tops out at Secret; ThrowHandler gives Pete his shot by
-- routing a top-of-curve roll through PickInTier(GodIndex).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)

local RarityCurve = {}

-- === TUNABLES (retune difficulty here) ===
RarityCurve.TIER_STEP = 0.40        -- each higher tier's base weight is this x the previous. LOWER = rarer top tiers.
RarityCurve.RAMP = 160              -- studs for a tier to fade from 0 -> full weight past its unlock distance
RarityCurve.LUCK_INFLUENCE = 0.18   -- how strongly access-luck shifts the curve toward higher tiers

-- The curve covers the distance-banded tiers (Common..Secret). God has an infinite band
-- (MaxDistance == huge) and is excluded. Each tier's unlock distance = its MinDistance,
-- read from RarityConfig so the curve tracks the roster automatically.
local UNLOCK = {}
local TOP = 0
for i, t in ipairs(RarityConfig) do
	if t.MaxDistance ~= math.huge then
		UNLOCK[i] = t.MinDistance
		TOP = i
	end
end
RarityCurve.TopTier = TOP        -- highest tier index the curve can roll (Secret)
RarityCurve.GodIndex = TOP + 1   -- God's index, for Pete's independent FixedChance shot

-- Per-tier weights at a distance + access luck. Weight 0 means that tier is not unlocked.
function RarityCurve.Weights(distance, accessLuck)
	local lf = 1 + (math.max(accessLuck or 1, 1) - 1) * RarityCurve.LUCK_INFLUENCE
	local w = {}
	for i = 1, TOP do
		if distance < UNLOCK[i] then
			w[i] = 0
		else
			local ramp = math.clamp((distance - UNLOCK[i]) / RarityCurve.RAMP, 0, 1)
			w[i] = ramp * (RarityCurve.TIER_STEP ^ (i - 1)) * (lf ^ (i - 1))
		end
	end
	return w
end

-- Normalized probability per tier (index 1..TopTier). For the luck HUD.
function RarityCurve.Probabilities(distance, accessLuck)
	local w = RarityCurve.Weights(distance, accessLuck)
	local sum = 0
	for i = 1, TOP do sum += w[i] end
	local p = {}
	for i = 1, TOP do p[i] = (sum > 0) and (w[i] / sum) or 0 end
	if sum <= 0 then p[1] = 1 end   -- thrown nowhere: treat as Common
	return p
end

-- Roll a tier INDEX (1..TopTier) from the weighted distribution.
function RarityCurve.RollTierIndex(distance, accessLuck)
	local w = RarityCurve.Weights(distance, accessLuck)
	local sum = 0
	for i = 1, TOP do sum += w[i] end
	if sum <= 0 then return 1 end
	local r = math.random() * sum
	local c = 0
	for i = 1, TOP do
		c += w[i]
		if r <= c then return i end
	end
	return TOP
end

return RarityCurve
