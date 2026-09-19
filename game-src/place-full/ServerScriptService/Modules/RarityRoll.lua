local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldProgression = require(ReplicatedStorage.Modules.WorldProgression)
local Waves = require(ReplicatedStorage.Modules.BrainrotWaves)
local SupplySchedule = require(ReplicatedStorage.Modules.SupplySchedule)
local LimitedStock = require(script.Parent.LimitedStock)

-- PER WORLD. Each world has its own ladder and its own catch pool (see WorldProgression),
-- so every cache here is keyed by world. Nothing in this file names a world.
--
-- Pools are CACHED, not static: availability changes over time (weekly tide flips,
-- seasonal retirements), when a capped name sells out, and when the emergency override
-- tables flip. The cache key captures exactly those inputs, so pools rebuild at
-- boundaries and never in between -- a per-throw scan over the roster stays off the
-- hot path.
local state = {}     -- [world] = { pools, totals, fixed, key }

local function poolKey()
	-- OverrideKey folds in the FORCE_ON/VAULTED emergency levers so a runtime flip
	-- rebuilds pools immediately instead of hiding until the next boundary.
	local key = SupplySchedule.PeriodKey() .. "#" .. Waves.OverrideKey()
	-- SoldOut is stale-tolerant (<=60s) and never yields, so folding it into the key
	-- costs a dozen table lookups. TryClaim at reveal time stays the authority.
	local sold = {}
	for name in pairs(LimitedStock.MAX) do
		if LimitedStock.SoldOut(name) then
			sold[#sold + 1] = name
		end
	end
	table.sort(sold)
	return key .. "|" .. table.concat(sold, "|")
end

-- Availability, which is world-dependent. A world on the rotation asks SupplySchedule;
-- a world that is not still honours the two override tables, because "quest reward only"
-- and "vaulted" are statements about an ITEM, not about a schedule.
local function isLive(entry, world)
	if world.UsesSupplySchedule then
		if not Waves.IsObtainable(entry.Name) then return false end
	else
		if Waves.QUEST_ONLY[entry.Name] then return false end
		if Waves.VAULTED[entry.Name] then return false end
		if entry.QuestOnly then return false end
	end
	return not LimitedStock.SoldOut(entry.Name)
end

local function rebuild(worldName)
	local world = WorldProgression.Resolve(worldName)
	local s = { pools = {}, totals = {}, fixed = {}, anyTier = {}, key = poolKey() }
	for _, entry in ipairs(world.Pool) do
		if isLive(entry, world) then
			if entry.AnyTier and entry.FixedChance then
				-- Rolled once per THROW by the caller, not once per tier reached -- so it
				-- goes in its own list and deliberately NOT in s.fixed. An entry in both
				-- would get two independent tickets on a throw that happened to land on
				-- its own tier, which is the bug this split exists to prevent.
				s.anyTier[#s.anyTier + 1] = entry
			elseif entry.FixedChance then
				local f = s.fixed[entry.Rarity]
				if not f then f = {}; s.fixed[entry.Rarity] = f end
				f[#f + 1] = entry
			else
				local p = s.pools[entry.Rarity]
				if not p then p = {}; s.pools[entry.Rarity] = p end
				p[#p + 1] = entry
				s.totals[entry.Rarity] = (s.totals[entry.Rarity] or 0) + (entry.Weight or 0)
			end
		end
	end
	return s
end

local function ensure(worldName)
	local key = WorldProgression.NameFor(worldName)
	local s = state[key]
	if not s or s.key ~= poolKey() then
		s = rebuild(key)
		state[key] = s
	end
	return s, WorldProgression.Resolve(key)
end

-- A weighted entry's odds are Weight / (live tier total), so they move whenever a wave
-- changes which names are live. FixedChance entries are rolled on their own, BEFORE the
-- pool, so "1 in N rolls" stays literally true across every future wave. Their Weight is
-- never summed and never used.
local function rollFixed(s, tierName)
	local fixed = s.fixed[tierName]
	if not fixed then return nil end
	for _, entry in ipairs(fixed) do
		if not LimitedStock.SoldOut(entry.Name) and math.random() < entry.FixedChance then
			return entry
		end
	end
	return nil
end

local RarityRoll = {}

--[[ Entries that ignore the distance ladder completely: flat odds on every throw,
whatever tier it would otherwise have landed on. Returned rather than rolled here
because the two things that decide the outcome -- the thrower's luck, and whether
this particular player has already retired the entry -- are per-player, and this
module's state is per-world and shared by everyone on the server. ThrowHandler
owns the roll; this owns which entries are live and eligible to be in it.

Already filtered by isLive, so a vaulted, quest-only or sold-out name never
reaches the caller. ]]
function RarityRoll.AnyTierEntries(worldName)
	local s = ensure(worldName)
	return s.anyTier
end

-- The tier row an AnyTier winner should be revealed at. Its Rarity field names a
-- tier by name, and every downstream consumer -- the reveal colour, the mutation
-- band, MintRegistry -- wants the ladder ROW, not the string. Nil for a world whose
-- ladder has no such tier, which the caller must treat as "do not award".
function RarityRoll.TierByName(tierName, worldName)
	local _, world = ensure(worldName)
	for _, tier in ipairs(world.Rarities) do
		if tier.Name == tierName then return tier end
	end
	return nil
end

function RarityRoll.TierForDistance(distance, worldName)
	local ladder = WorldProgression.Resolve(worldName).Rarities
	for _, tier in ipairs(ladder) do
		if distance >= tier.MinDistance and distance < tier.MaxDistance then
			return tier
		end
	end
	return ladder[#ladder]
end

-- Index of the tier a RAW distance reaches (no luck). The equipped rock decides your
-- reach; luck buys promotions on top (see ThrowHandler).
function RarityRoll.TierIndexForDistance(distance, worldName)
	local ladder = WorldProgression.Resolve(worldName).Rarities
	for i = #ladder, 1, -1 do
		if distance >= ladder[i].MinDistance then return i end
	end
	return 1
end

-- Weighted pick within one tier, restricted to the CURRENTLY OBTAINABLE names, after
-- giving that tier's fixed-odds entries their independent roll.
-- Never returns a nil entry: an empty tier falls back down to the nearest tier that has
-- any, so a bad quota can never hand a player a nil catch.
-- skipFixed: used by the reveal-time fallback, when a limited item was rolled but its
-- last slot had already gone to another server. Re-rolls an ordinary catch for the tier.
function RarityRoll.PickInTier(tierIndex, skipFixed, worldName)
	local s, world = ensure(worldName)
	local ladder = world.Rarities
	tierIndex = math.clamp(tierIndex, 1, #ladder)
	for i = tierIndex, 1, -1 do
		local tier = ladder[i]
		local jackpot = not skipFixed and rollFixed(s, tier.Name) or nil
		if jackpot then return jackpot, tier end
		local pool = s.pools[tier.Name]
		local totalWeight = s.totals[tier.Name]
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
	return nil, ladder[1]
end

function RarityRoll.RollForDistance(distance, worldName)
	local s, world = ensure(worldName)
	local tier = RarityRoll.TierForDistance(distance, worldName)
	local pool = s.pools[tier.Name]
	local totalWeight = s.totals[tier.Name]
	if not pool or #pool == 0 then return nil, tier end
	if not totalWeight or totalWeight <= 0 then return nil, tier end
	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, entry in ipairs(pool) do
		cumulative += entry.Weight
		if roll <= cumulative then return entry, tier end
	end
	return pool[#pool], tier
end

-- for audits / tooling
function RarityRoll.Debug(worldName)
	local s, world = ensure(worldName)
	local rows = {}
	for _, tier in ipairs(world.Rarities) do
		rows[#rows + 1] = {
			Tier = tier.Name,
			Pool = s.pools[tier.Name] and #s.pools[tier.Name] or 0,
			Weight = s.totals[tier.Name] or 0,
			Fixed = s.fixed[tier.Name] and #s.fixed[tier.Name] or 0,
			-- not per-tier: the same count repeats on every row, since these are rolled
			-- once per throw rather than per tier
			AnyTier = #s.anyTier,
		}
	end
	return rows
end

return RarityRoll
