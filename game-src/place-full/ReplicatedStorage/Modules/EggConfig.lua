-- EggConfig — single source of truth for eggs. The server ROLLS from these
-- tables and the client DISPLAYS them, so shown odds can never drift from
-- real odds (Roblox requires published odds for paid random items).
-- Eggs hatch PETS (EggHandler grants into data.Pets, never onto a plot), so the
-- roll tables name pets and Validate checks them against PetConfig. Until
-- 2026-08-01 they named the ten forest BRAINROTS that were doubling as pets
-- before the real pet art existed, and this required BrainrotConfig instead.
local PetConfig = require(script.Parent.PetConfig)

local M = {}

M.WORLDS = {
	Forest = {
		Active = true,
		DisplayName = "Forest",
		-- Each egg overlaps the next by one or two pets, so spending up never
		-- makes the previous egg's best result unobtainable and every tier has a
		-- cheap-but-unlikely route as well as an expensive-but-likely one.
		-- Weights are per-egg percentages; Validate asserts each row sums to 100.
		Eggs = {
			{ Id = "ForestShard",  Name = "Shard Egg",  Price = 60,  Model = "ForestEgg1",
			  Table = { { "Moss Larva", 45 }, { "Pebble Snout", 33 }, { "Leaf Frog", 22 } } },
			{ Id = "ForestDrip",   Name = "Drip Egg",   Price = 85,  Model = "ForestEgg2",
			  Table = { { "Leaf Frog", 30 }, { "Reed Duck", 34 }, { "Toad Pup", 26 }, { "Acornel", 10 } } },
			{ Id = "ForestHorned", Name = "Horned Egg", Price = 115, Model = "ForestEgg3",
			  Table = { { "Toad Pup", 26 }, { "Acornel", 30 }, { "Sap Snail", 24 }, { "Bramble Bear", 20 } } },
			{ Id = "ForestRune",   Name = "Rune Egg",   Price = 160, Model = "ForestEgg4",
			  Table = { { "Bramble Bear", 28 }, { "Mossback", 30 }, { "Glow Moth", 22 }, { "Hollow Owl", 14 }, { "Vine Coil", 6 } } },
			{ Id = "ForestCrown",  Name = "Crown Egg",  Price = 220, Model = "ForestEgg5",
			  Table = { { "Hollow Owl", 26 }, { "Vine Coil", 26 }, { "Spirit Fawn", 22 }, { "Elder Stag", 20 }, { "Heartwood Guardian", 6 } } },
		},
	},
}

function M.GetWorld(worldId) return M.WORLDS[worldId] end

function M.GetEgg(worldId, eggId)
	local w = M.WORLDS[worldId]
	if not w then return nil end
	for _, egg in ipairs(w.Eggs) do
		if egg.Id == eggId then return egg, w end
	end
	return nil
end

-- Boot-time assert (EggHandler.Init calls it) -- a typo'd pet name must fail
-- loudly at server start, not silently refund a player mid-purchase.
function M.Validate()
	for _, w in pairs(M.WORLDS) do
		for _, egg in ipairs(w.Eggs) do
			local sum = 0
			for _, row in ipairs(egg.Table) do
				assert(PetConfig.IdFor(row[1]), egg.Id .. " references unknown pet: " .. tostring(row[1]))
				sum += row[2]
			end
			assert(sum == 100, egg.Id .. " weights sum to " .. sum .. ", want 100")
		end
	end
	return true
end

-- Every pet that is actually obtainable, for the shop's "where does this drop"
-- copy and for tests that assert the roster and the tables have not drifted.
function M.ObtainablePetIds()
	local ids = {}
	for _, w in pairs(M.WORLDS) do
		for _, egg in ipairs(w.Eggs) do
			for _, row in ipairs(egg.Table) do
				local id = PetConfig.IdFor(row[1])
				if id then ids[id] = true end
			end
		end
	end
	return ids
end

return M