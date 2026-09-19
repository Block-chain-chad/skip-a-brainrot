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
		ShopReady = true,
		DisplayName = "Forest",
		-- The name on this stall's proximity prompt. EggHandler writes it on every
		-- boot, so this is the ONE place a world's egg keeper is named -- the text
		-- authored on the prompt in Studio is overwritten and cannot drift.
		Keeper = "Gino the Egg Keeper",
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

	-- === WORLD 2 -- SCAFFOLDED 2026-08-23, DELIBERATELY NOT LIVE ==============
	-- `Active = false` is load-bearing, not a note to self. EggHandler's buy handler
	-- already refuses anything whose world is not Active ("That egg is not
	-- available"), and Validate/ObtainablePetIds skip inactive worlds, so this block
	-- can sit here fully written and cost nothing until its pets exist.
	--
	-- WHY IT IS HERE AT ALL: the art and the shop were ALREADY BUILT and shipping.
	-- ReplicatedStorage.EggModels.Tundra holds TundraEgg1..5 at the same fidelity as
	-- the Forest eggs (346-451 parts each), and
	-- Workspace.GameWorld.FrozenTundra.Hub.Stalls."Frost Eggs" is a finished stall
	-- whose five displays are named below. Only this DATA was missing -- and its
	-- absence is exactly what made the Frozen Tundra stall open world 1's catalogue,
	-- because the client falls back to its load-time WORLD_ID.
	--
	-- TO SHIP: fill each Table with three pets from PetConfig -- worst to best,
	-- weights summing to 100, no pet appearing in two eggs (the Forest rules above
	-- apply verbatim) -- then set Active = true. Validate() asserts at boot on a
	-- short, misweighted or unknown-pet table, so a half-finished flip fails loudly
	-- instead of quietly selling nothing.
	Tundra = {
		-- HELD SHUT ON PURPOSE (2026-08-24). The data below is finished -- the fifteen
		-- tundra pets exist, the pools are real, Validate() passes on them and the shop
		-- shell can draw them. It is off because the next publish is a HOTFIX for the
		-- Bag/Sell crash (see BrainrotThumb's capability note) and shipping an entire
		-- unreviewed world alongside a hotfix is two decisions wearing one coat.
		--
		-- To open World 2: set BOTH of these true. Nothing else needs to change --
		-- that is the whole point of the two flags, and both directions are tested.
		-- Active = the SERVER will sell it (Validate() then covers this world, and its
		-- pets count toward ObtainablePetIds).
		Active = false,
		-- ShopReady = the CLIENT shell can render it. EggShopClient builds a full set
		-- of cards for every id in ShopWorldIds() at load and toggles which set is
		-- visible, so with this false the Tundra cards are simply never built and the
		-- Frozen Tundra stall reads "Coming Soon" instead of opening world 1's
		-- catalogue. Verified working in both states before it was turned off.
		ShopReady = false,
		DisplayName = "Frozen Tundra",
		-- The Frost Eggs stall's NPC has no name yet -- its model is literally
		-- "NPC" -- so this names the SHOP rather than inventing a character to sit
		-- beside Gino. Write a keeper's name here when there is one and the prompt
		-- picks it up on the next boot, no code change.
		Keeper = "Frozen Tundra Eggs",
		-- Names are the five displays already standing on the stall, ordered cheapest
		-- to best so Frostheart closes this set the way Heartwood closes the Forest
		-- one. Prices CONTINUE the Forest curve rather than inventing a new one: that
		-- ladder steps about 1.38x a rung (60/85/115/160/220), so this picks up from
		-- 220 at the same ratio. They are a defensible starting point, not a balance
		-- decision -- worth checking against world 2 income before launch.
		Eggs = {
			-- Same rules as the Forest world above, verbatim: THREE pets per egg, NO
			-- overlap, each egg's three a CONSECUTIVE run of PetConfig's tundra roster,
			-- rows WORST TO BEST so the last row is simultaneously the rarest and the
			-- strongest. The fifteen divide exactly across the five eggs.
			{ Id = "TundraFrostcap",   Name = "Frostcap Egg",   Price = 305,  Model = "TundraEgg1",
			  Table = { { "Waddlebert", 60 }, { "Frostnip", 30 }, { "Snowpuff", 10 } } },
			{ Id = "TundraRimeplate",  Name = "Rimeplate Egg",  Price = 420,  Model = "TundraEgg2",
			  Table = { { "Blubberton", 58 }, { "Mr. Frostbite", 31 }, { "Sir Chunkers", 11 } } },
			{ Id = "TundraWhiteout",   Name = "Whiteout Egg",   Price = 580,  Model = "TundraEgg3",
			  Table = { { "Hootsicle", 56 }, { "Tuskwald", 32 }, { "Jinglehoof", 12 } } },
			{ Id = "TundraAurora",     Name = "Aurora Egg",     Price = 800,  Model = "TundraEgg4",
			  Table = { { "Grumblehorn", 55 }, { "Narwhalini Tuskarino", 33 }, { "Yetini Snowlini", 12 } } },
			{ Id = "TundraFrostheart", Name = "Frostheart Egg", Price = 1105, Model = "TundraEgg5",
			  Table = { { "Glacio Frostalini", 54 }, { "Mammothini Woolarino", 38 }, { "Aurora Serpentini", 8 } } },
		},
	},
}

-- === Bundle pricing ========================================================
-- The shop sells eggs x1 / x3 / x10, and bulk is discounted. BOTH sides have to
-- agree on the number or the card advertises one price while the server debits
-- another, so this is the single definition: EggShopClient renders it and
-- EggHandler charges it. Rounded to a whole Emerald -- the currency has no
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
		-- An INACTIVE world is scaffolding: its pools are allowed to be empty while its
		-- pets are still being designed, and EggHandler refuses to sell from it anyway.
		-- Skipping it is what lets an unfinished world be committed WITHOUT taking the
		-- server down at boot. The instant Active flips true every assert below applies
		-- again, so a premature flip still fails loudly and immediately.
		if w.Active then
			for _, egg in ipairs(w.Eggs) do
				local sum = 0
				for _, row in ipairs(egg.Table) do
					assert(PetConfig.IdFor(row[1]), egg.Id .. " references unknown pet: " .. tostring(row[1]))
					sum += row[2]
				end
				assert(sum == 100, egg.Id .. " weights sum to " .. sum .. ", want 100")
			end
		end
	end
	return true
end

-- Every pet that is actually obtainable, for the shop's "where does this drop"
-- copy and for tests that assert the roster and the tables have not drifted.
function M.ObtainablePetIds()
	local ids = {}
	for _, w in pairs(M.WORLDS) do
		-- inactive worlds are not a source of pets yet -- counting them would tell the
		-- shop's "where does this drop" copy about eggs nobody can buy
		if w.Active then
		for _, egg in ipairs(w.Eggs) do
			for _, row in ipairs(egg.Table) do
				local id = PetConfig.IdFor(row[1])
				if id then ids[id] = true end
			end
		end
		end
	end
	return ids
end

-- ------------------------------------------------------------- the shop shell
-- The world the egg shop shows when nothing has told it otherwise. It is also
-- the starting world, so a player who never leaves it never sees a switch.
M.DEFAULT_WORLD = "Forest"

-- Worlds the egg SHOP SHELL can actually draw, in a stable order -- default
-- first, then alphabetical. TWO flags gate a world and they answer different
-- questions; do not collapse them:
--     Active     -- the SERVER will sell it. The data is real and Validate()
--                   holds it to the same asserts as every other world.
--     ShopReady  -- the CLIENT shell can render it. A world is Active and not
--                   ShopReady while its pets, art or copy are still landing.
-- EggShopClient builds one full set of cards per id returned here, ONCE, at
-- load -- so every id added here costs five more cards' worth of instances.
function M.ShopWorldIds()
	local out = {}
	for id, w in pairs(M.WORLDS) do
		if w.Active and w.ShopReady ~= false and id ~= M.DEFAULT_WORLD then
			out[#out + 1] = id
		end
	end
	table.sort(out)
	local d = M.WORLDS[M.DEFAULT_WORLD]
	if d and d.Active and d.ShopReady ~= false then
		table.insert(out, 1, M.DEFAULT_WORLD)
	end
	return out
end

-- Every shop-ready egg as one flat list, in ShopWorldIds order. The shop wires
-- its buy buttons and its card animation off THIS rather than off one world's
-- Eggs, so a card belonging to a world that is not currently on screen is
-- still wired and still correct the moment it is swapped in.
function M.ShopEggs()
	local out = {}
	for _, id in ipairs(M.ShopWorldIds()) do
		for _, egg in ipairs(M.WORLDS[id].Eggs) do out[#out + 1] = egg end
	end
	return out
end

-- Which world an egg id belongs to. Egg ids are globally unique (ForestShard,
-- TundraFrostcap) -- the property that lets the shop keep every world's cards
-- in ONE registry -- so the buy and hatch paths can name their world from the
-- EGG rather than from whichever world the shell happens to be showing.
function M.WorldIdOfEgg(eggId)
	for id, w in pairs(M.WORLDS) do
		for _, egg in ipairs(w.Eggs) do
			if egg.Id == eggId then return id end
		end
	end
	return nil
end

return M