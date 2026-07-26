local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local Waves = require(ReplicatedStorage.Modules.BrainrotWaves)
local SupplySchedule = require(ReplicatedStorage.Modules.SupplySchedule)
local LimitedStock = require(script.Parent.LimitedStock)

-- Pools are CACHED, not static: availability changes over time (weekly tide
-- flips, seasonal retirements), when a capped name sells out, and when the
-- emergency override tables flip. The cache key captures exactly those inputs,
-- so pools rebuild at boundaries and never in between -- a per-throw scan over
-- 214 entries stays off the hot path.
local poolsByTier, totalByTier, fixedByTier
local currentKey = nil

local function poolKey()
	-- OverrideKey folds in the FORCE_ON/VAULTED emergency levers so a runtime
	-- flip rebuilds pools immediately instead of hiding until the next boundary.
	local key = SupplySchedule.PeriodKey() .. "#" .. Waves.OverrideKey()
	-- SoldOut is stale-tolerant (<=60s) and never yields, so folding it into the
	-- key costs a dozen table lookups. TryClaim at reveal time stays the authority.
	local sold = {}
	for name in pairs(LimitedStock.MAX) do
		if LimitedStock.SoldOut(name) then
			sold[#sold + 1] = name
		end
	end
	table.sort(sold)
	return key .. "|" .. table.concat(sold, "|")
end

local function rebuildPools()
	poolsByTier, totalByTier, fixedByTier = {}, {}, {}
	for _, entry in ipairs(BrainrotConfig) do
		if Waves.IsObtainable(entry.Name) and not LimitedStock.SoldOut(entry.Name) then
			if entry.FixedChance then
				local f = fixedByTier[entry.Rarity]
				if not f then f = {}; fixedByTier[entry.Rarity] = f end
				f[#f + 1] = entry
			else
				local p = poolsByTier[entry.Rarity]
				if not p then p = {}; poolsByTier[entry.Rarity] = p end
				p[#p + 1] = entry
				totalByTier[entry.Rarity] = (totalByTier[entry.Rarity] or 0) + entry.Weight
			end
		end
	end
end

local function ensurePools()
	local key = poolKey()
	if key ~= currentKey then
		currentKey = key
		rebuildPools()
	end
end
ensurePools()

-- A weighted entry's odds are Weight / (live tier total), so they move whenever a
-- wave changes which names are live. FixedChance entries are rolled on their own,
-- BEFORE the pool, so "1 in 100,000 Secret rolls" stays literally true across every
-- future wave. Their Weight is never summed and never used.
-- SoldOut is the cheap non-yielding pre-check, so an exhausted item stops costing a
-- roll. It can be stale; the authoritative reservation happens at reveal time in
-- ThrowHandler, which is also the only place allowed to yield.
local function rollFixed(tierName)
	local fixed = fixedByTier[tierName]
	if not fixed then return nil end
	for _, entry in ipairs(fixed) do
		if not LimitedStock.SoldOut(entry.Name) and math.random() < entry.FixedChance then
			return entry
		end
	end
	return nil
end

local RarityRoll = {}

function RarityRoll.TierForDistance(distance)
	for _, tier in ipairs(RarityConfig) do
		if distance >= tier.MinDistance and distance < tier.MaxDistance then
			return tier
		end
	end
	return RarityConfig[#RarityConfig]
end

-- Index of the tier a RAW distance reaches (no luck). The equipped rock decides
-- your reach; luck buys promotions on top (see ThrowHandler).
function RarityRoll.TierIndexForDistance(distance)
	for i = #RarityConfig, 1, -1 do
		if distance >= RarityConfig[i].MinDistance then return i end
	end
	return 1
end

-- Weighted pick within one tier, restricted to the CURRENTLY OBTAINABLE names,
-- after giving that tier's fixed-odds entries their independent roll.
-- Never returns a nil entry: an empty tier falls back down to the nearest tier
-- that has any, so a bad quota can never hand a player a nil catch.
-- skipFixed: used by the reveal-time fallback, when a limited item was rolled but its
-- last slot had already gone to another server. Re-rolls an ordinary catch for the tier.
function RarityRoll.PickInTier(tierIndex, skipFixed)
	ensurePools()
	tierIndex = math.clamp(tierIndex, 1, #RarityConfig)
	for i = tierIndex, 1, -1 do
		local tier = RarityConfig[i]
		local jackpot = not skipFixed and rollFixed(tier.Name) or nil
		if jackpot then return jackpot, tier end
		local pool = poolsByTier[tier.Name]
		local totalWeight = totalByTier[tier.Name]
		if pool and #pool > 0 and totalWeight and totalWeight > 0 then
			local roll = math.random() * totalWeight
			local cumulative = 0
			for _, entry in ipairs(pool) do
				cumulative += entry.Weight
				if roll <= cumulative then return entry, tier end
			end
			return pool[#pool], tier
		end
	end
	return nil, RarityConfig[1]
end

function RarityRoll.RollForDistance(distance)
	local tier = RarityRoll.TierForDistance(distance)
	local pool = {}
	local totalWeight = 0
	for _, entry in ipairs(BrainrotConfig) do
		if entry.Rarity == tier.Name then
			table.insert(pool, entry)
			totalWeight += entry.Weight
		end
	end
	if #pool == 0 then return nil, tier end

	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, entry in ipairs(pool) do
		cumulative += entry.Weight
		if roll <= cumulative then
			return entry, tier
		end
	end
	return pool[#pool], tier
end

return RarityRoll
