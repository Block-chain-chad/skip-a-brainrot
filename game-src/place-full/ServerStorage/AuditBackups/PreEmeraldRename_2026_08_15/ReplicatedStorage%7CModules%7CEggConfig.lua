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
		-- THREE pets per egg, NO OVERLAP (2026-08-06). The 15 roster pets divide
		-- exactly across the five eggs, so every pet has one home and a shop card can
		-- show a whole egg in three rows. Rows run WORST TO BEST, and each egg's three
		-- pets are a CONSECUTIVE run of PetConfig's roster -- which is what makes the
		-- last row simultaneously the rarest AND the strongest. The shop card's
		-- "RAREST" row states exactly that, so reordering either list on its own turns
		-- that line into a lie; change the two together.
		--
		-- Previous shape (pre-2026-08-06) overlapped each egg with the next by one or
		-- two pets. That was dropped with the move to per-pet boosts: an overlapped
		-- pet would have had to be worth the same in a cheap egg and an expensive one.
		-- Weights are per-egg percentages; Validate asserts each row sums to 100.
		Eggs = {
			-- Display names re-themed 2026-08-13 (Mossy/Reedwater/Bramble/Hollow/Heartwood,
			-- from world1_eggs_all.glb). Ids and Model keys deliberately unchanged: Ids are
			-- referenced by SeasonConfig rewards and Model keys by the EggModels folder.
			{ Id = "ForestShard",  Name = "Mossy Egg",  Price = 60,  Model = "ForestEgg1",
			  Table = { { "Moss Larva", 60 }, { "Pebble Snout", 30 }, { "Leaf Frog", 10 } } },
			{ Id = "ForestDrip",   Name = "Reedwater Egg", Price = 85,  Model = "ForestEgg2",
			  Table = { { "Reed Duck", 58 }, { "Toad Pup", 31 }, { "Acornel", 11 } } },
			{ Id = "ForestHorned", Name = "Bramble Egg", Price = 115, Model = "ForestEgg3",
			  Table = { { "Sap Snail", 56 }, { "Bramble Bear", 32 }, { "Mossback", 12 } } },
			{ Id = "ForestRune",   Name = "Hollow Egg",  Price = 160, Model = "ForestEgg4",
			  Table = { { "Glow Moth", 55 }, { "Hollow Owl", 33 }, { "Vine Coil", 12 } } },
			{ Id = "ForestCrown",  Name = "Heartwood Egg", Price = 220, Model = "ForestEgg5",
			  Table = { { "Spirit Fawn", 54 }, { "Elder Stag", 38 }, { "Heartwood Guardian", 8 } } },
		},
	},
}

-- === Bundle pricing ========================================================
-- The shop sells eggs x1 / x3 / x10, and bulk is discounted. BOTH sides have to
-- agree on the number or the card advertises one price while the server debits
-- another, so this is the single definition: EggShopClient renders it and
-- EggHandler charges it. Rounded to a whole Darrel -- the currency has no
-- fractions, and rounding in one shared place is what stops the client's
-- displayed subtotal and the server's debit from ever differing by a point.
M.BUNDLE_DISCOUNT = { [1] = 1.00, [3] = 0.95, [10] = 0.88 }

-- Cost of `qty` of `egg`, or nil when qty is not one the picker offers. Returning
-- nil rather than clamping is deliberate: EggHandler whitelists the quantity
-- against this table, so an unknown qty is REFUSED instead of quietly becoming 1.
function M.BundleCost(egg, qty)
	local mult = M.BUNDLE_DISCOUNT[qty]
	if not egg or not mult then return nil end
	return math.floor(egg.Price * qty * mult + 0.5)
end

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