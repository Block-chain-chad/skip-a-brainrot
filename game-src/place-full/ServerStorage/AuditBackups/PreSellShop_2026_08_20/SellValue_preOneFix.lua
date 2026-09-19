--!strict
-- SellValue: the ONE definition of what a thing is worth when sold.
--
-- Before this module the formula lived in SellHandler AND in ClientMain, and the
-- two drifted -- the sell row advertised a species base price while the server
-- paid a per-copy price. Any future consumer must call this rather than
-- recompute; that is the whole point of the file.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local WorldProgression = require(ReplicatedStorage.Modules.WorldProgression)
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)
local Sizes = require(ReplicatedStorage.Modules.SizeConfig)
local PetConfig = require(ReplicatedStorage.Modules.PetConfig)

local SellValue = {}

SellValue.MULTIPLIER = 40

-- EVERY WORLD. Built from BrainrotConfig alone this covers World 1 only, which
-- priced the tundra/gardens exclusives at nil. Valley first so a shared name
-- keeps its World 1 rate.
local rateByName: { [string]: number } = {}
for _, entry in ipairs(BrainrotConfig) do
	rateByName[entry.Name] = entry.CashPerSecond
end
for _, worldName in ipairs(WorldProgression.List()) do
	local world = WorldProgression.Resolve(worldName)
	for _, e in ipairs((world and world.Pool) or {}) do
		if rateByName[e.Name] == nil then
			rateByName[e.Name] = e.CashPerSecond
		end
	end
end

function SellValue.BaseRate(name: string): number?
	return rateByName[name]
end

-- Intrinsic value of ONE copy. Mutation and size are the two axes that belong to
-- the item; IncomeLoop's rebirth/upgrade/pet/pass multipliers belong to the
-- PLAYER and are excluded on purpose -- folding them in would make one brainrot
-- worth different amounts to different sellers.
-- Floors per COPY so a summed total is an exact integer (see the 2026-08-19
-- float-dust note in GrantCash).
function SellValue.OfBrainrot(entry): number?
	local base = rateByName[entry.Name]
	if base == nil then return nil end
	return math.floor(base
		* Mutations.Mult(entry.Mutation)
		* Sizes.Mult(entry.Size)
		* SellValue.MULTIPLIER)
end

function SellValue.OfPet(petId: string): number
	return PetConfig.SellValue(petId)
end

-- The bulk-safety predicate, in ONE place so the quick-sell bar, per-species
-- SELL ALL and the server agree by construction.
-- Sized copies are held back as well as mutated ones (owner decision
-- 2026-08-20): a plain Massive is 8x, and no bulk button should ever take that.
function SellValue.IsBulkEligible(entry): boolean
	if entry.Fav then return false end
	if entry.PadIndex ~= nil then return false end
	if entry.Mutation ~= nil then return false end
	if entry.Size ~= nil then return false end
	return rateByName[entry.Name] ~= nil
end

-- Selection rules live here, not in the handler, so the client can show exactly
-- what the server will take without duplicating the logic.
-- `name` nil = every species (the quick-sell set); a name = that species only.
-- Returns the chosen entries plus how many were held back for being favourited,
-- placed, mutated, oversized or unpriceable.
function SellValue.SelectBulk(entries, name: string?)
	local chosen, held = {}, 0
	for _, e in ipairs(entries) do
		if name == nil or e.Name == name then
			if SellValue.IsBulkEligible(e) then
				chosen[#chosen + 1] = e
			else
				held += 1
			end
		end
	end
	return chosen, held
end

-- The least valuable UNFAVOURITED, UNPLACED copy of one species, ranked by full
-- value. Ranking by Mutations.Mult alone was size-blind and could hand over the
-- Massive instead of the plain copy.
function SellValue.SelectCheapest(entries, name: string)
	local best, bestValue
	for _, e in ipairs(entries) do
		if e.Name == name and e.PadIndex == nil and not e.Fav then
			local v = SellValue.OfBrainrot(e)
			if v ~= nil and (bestValue == nil or v < bestValue) then
				best, bestValue = e, v
			end
		end
	end
	return best
end

return SellValue