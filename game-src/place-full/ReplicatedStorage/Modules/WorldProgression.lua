-- WorldProgression: which rarity ladder and which catch pool each world uses.
--
-- THIS IS THE ONLY FILE THAT HAS TO CHANGE TO ADD A WORLD. Gameplay code asks for a
-- world by name and gets its tables; it never names a world itself. Adding World 3 means
-- writing two config tables and adding one line here.
--
-- Keys are BoundsGuard's region names, because that is already the game's single
-- definition of where each world is (PlayerDataManager.PlayerWorld returns them).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Mods = ReplicatedStorage.Modules

local M = {}

M.Default = "Valley"

M.Worlds = {
	Valley = {
		Label = "The Valley",
		Rarities = require(Mods.RarityConfig),
		Pool = require(Mods.BrainrotConfig),
		-- what Rocco's stall in this world stocks
		Rocks = require(Mods.RockConfig),
		-- The valley roster is on the weekly Vault & Tide rotation, so its availability
		-- is decided by SupplySchedule.
		UsesSupplySchedule = true,
	},
	Tundra = {
		Label = "Frozen Tundra",
		Rarities = require(Mods.RarityConfigTundra),
		Pool = require(Mods.BrainrotConfigTundra),
		Rocks = require(Mods.RockConfigTundra),
		-- The tundra roster is NOT on the rotation. SupplySchedule.IsObtainable returns
		-- false for any name it does not know, so leaving this on would reject all 67
		-- entries and every tundra catch would come back nil. QUEST_ONLY and VAULTED are
		-- still honoured -- see RarityRoll.
		UsesSupplySchedule = false,
	},
	-- The trading island has no throwing of its own. It resolves to the valley so that a
	-- throw there (or any future world without its own pool) can never return nil.
	Trading = { Alias = "Valley" },
	-- World 3 skips on the valley's ladder rather than a roster of its own. Without an
	-- entry here WorldProgression.Resolve returns nil, worldHasCatches goes false, and
	-- ThrowHandler stamps CatchesEnabled = false on every Gardens ThrowZone -- so the
	-- client refuses the charge before it starts. Give it its own Rarities/Pool/Rocks
	-- later and this alias is the only line that changes.
	Gardens = { Alias = "Valley" },
}

-- Never returns nil: an unknown or missing world falls back to the default, because a
-- nil pool at catch time would mean a player throws a rock and receives nothing.
function M.Resolve(worldName)
	local w = worldName and M.Worlds[worldName]
	if w and w.Alias then w = M.Worlds[w.Alias] end
	return w or M.Worlds[M.Default]
end

function M.NameFor(worldName)
	local w = worldName and M.Worlds[worldName]
	if w and w.Alias then return w.Alias end
	return (w and worldName) or M.Default
end

-- ================================= ROCKS =================================
-- A ROCK IS ONLY USABLE IN THE WORLD THAT SELLS IT (2026-08-15). You skip valley
-- rocks in the valley and tundra rocks in the tundra; carrying a maxed world-1 rock
-- into world 2 buys you nothing there, and each world's ladder is climbed from its
-- own bottom rung. This REPLACED the earlier rule, under which an owned rock worked
-- everywhere -- so anything that looks like it assumes a rock travels is stale.
--
-- Three different questions, and confusing them is a bug:
--
--   RocksFor(world)  the SHELF: what that world's stall stocks, and equally what may
--                    be THROWN there. Both gates ask this one -- ShopHandler for
--                    buying and equipping, ThrowHandler for the stone that actually
--                    leaves your hand.
--   RockById(id)     what an owned rock IS -- price, reach, luck, colour -- wherever
--                    it is being LOOKED AT. Merged across every world on purpose: the
--                    bag, the index and the shop rows all have to render a tundra rock
--                    while its owner is standing in the valley. Resolving an owned Id
--                    must always come through here; reading only RockConfig would
--                    resolve a tundra rock to nil and silently demote its owner to
--                    Pebble. Merged is NOT a licence to throw it anywhere -- that is
--                    what StocksRock is for.
--   BestOwnedIn(...) which of your rocks you actually throw in a given world.
--
-- Aliased worlds share their target's shelf, so valley rocks are the Gardens' and the
-- Trading island's rocks too -- neither has a stall of its own to stock.
function M.RocksFor(worldName)
	local w = M.Resolve(worldName)
	return (w and w.Rocks) or M.Worlds[M.Default].Rocks
end

-- Is this rock legal here -- the one question both gates ask.
-- WHAT THE STALL SELLS, as opposed to what the world's rocks ARE.
--
-- RocksFor stays COMPLETE on purpose: StocksRock, BestOwnedIn and ThrowHandler's
-- rockById all read it, and a rock missing from there silently demotes its owner to
-- Pebble (see RockConfig's "DO NOT RENAME IDS" note). Retiring a rock from sale must
-- not do that to someone who already bought it.
--
-- So retirement is a SHOP-side filter only: ShelfFor drops Retired rocks, and the shop
-- and its sequential-unlock chain re-link around them, while owners keep theirs and can
-- still equip and throw it.
function M.ShelfFor(worldName)
	local full = M.RocksFor(worldName)
	local shelf = {}
	for _, rock in ipairs(full) do
		if not rock.Retired then table.insert(shelf, rock) end
	end
	return shelf
end

function M.StocksRock(worldName, id)
	if not id then return false end
	for _, rock in ipairs(M.RocksFor(worldName)) do
		if rock.Id == id then return true end
	end
	return false
end

-- The free rock at the bottom of a world's shelf: what you throw there before you have
-- bought anything. EVERY shelf's first entry must be priced 0 for this reason -- Pebble
-- in the valley, GlacierShard in the tundra. A world whose first rock costs money would
-- strand an arriving player with nothing they are allowed to throw.
function M.StarterRock(worldName)
	return M.RocksFor(worldName)[1]
end

-- The best rock the player owns ON THIS WORLD'S SHELF. "Best" is simply the highest rung
-- reached, because both reach and luck ascend every ladder. Falls back to the starter, so
-- this never returns nil and a throw always has a stone.
function M.BestOwnedIn(worldName, ownedRocks)
	local shelf = M.RocksFor(worldName)
	local best
	for _, rock in ipairs(shelf) do
		if ownedRocks and ownedRocks[rock.Id] then best = rock end
	end
	return best or shelf[1]
end

local rockById, rockAll
local function indexRocks()
	if rockById then return end
	rockById, rockAll = {}, {}
	-- Default world first so its ladder keeps its order, then the rest by name for
	-- a stable result whatever the pairs() order happens to be.
	local names = { M.Default }
	local rest = {}
	for name, w in pairs(M.Worlds) do
		if name ~= M.Default and not w.Alias then rest[#rest + 1] = name end
	end
	table.sort(rest)
	for _, n in ipairs(rest) do names[#names + 1] = n end

	for _, name in ipairs(names) do
		local w = M.Worlds[name]
		for _, rock in ipairs((w and w.Rocks) or {}) do
			if not rockById[rock.Id] then
				rockById[rock.Id] = rock
				rockAll[#rockAll + 1] = rock
			end
		end
	end
end

function M.RockById(id)
	indexRocks()
	return rockById[id]
end

-- THE ONE PLACE A ROCK'S DISPLAY NAME COMES FROM (2026-08-22).
--
-- Ids are save keys and may never be renamed (see RockConfig's own DO NOT RENAME
-- note), so the pretty name players read lives in a separate `Name` field beside
-- Price/Luck. Every surface that prints a rock -- Rocco's shop card, the luck
-- HUD's breakdown row -- resolves it through here rather than printing the Id,
-- which is why they used to read "MeteoriteFragment" with no space in it.
--
-- Accepts either an Id string or a rock table, so a caller that already has the
-- row does not have to look it up again. Falls back to splitting the Id on its
-- capitals, so a rock added without a Name still reads as words rather than
-- breaking -- naming a new rock is a content decision, never a crash.
function M.RockName(rockOrId)
	local rock = rockOrId
	if type(rockOrId) == "string" then
		rock = M.RockById(rockOrId)
	end
	if type(rock) == "table" and type(rock.Name) == "string" and rock.Name ~= "" then
		return rock.Name
	end
	local id = (type(rock) == "table" and rock.Id) or rockOrId
	return (tostring(id or "Rock"):gsub("(%l)(%u)", "%1 %2"))
end

-- every rock in the game, valley ladder first
function M.AllRocks()
	indexRocks()
	return rockAll
end

-- Which world's shelf an Id belongs to, for the shop's server-side gate.
function M.WorldOfRock(id)
	for name, w in pairs(M.Worlds) do
		if not w.Alias then
			for _, rock in ipairs(w.Rocks or {}) do
				if rock.Id == id then return name end
			end
		end
	end
	return nil
end

-- Every world that has its own pool, for tooling and audits.
function M.List()
	local out = {}
	for name, w in pairs(M.Worlds) do
		if not w.Alias then out[#out + 1] = name end
	end
	table.sort(out)
	return out
end

return M
