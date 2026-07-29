-- EggConfig — single source of truth for eggs. The server ROLLS from these
-- tables and the client DISPLAYS them, so shown odds can never drift from
-- real odds (Roblox requires published odds for paid random items).
local BrainrotConfig = require(script.Parent.BrainrotConfig)

local M = {}

M.WORLDS = {
	Forest = {
		Active = true,
		DisplayName = "Forest",
		Eggs = {
			{ Id = "ForestShard",  Name = "Shard Egg",  Price = 60,  Model = "ForestEgg1",
			  Table = { { "Cervolino Antlerino", 50 }, { "Fanghetto Palunko", 32 }, { "Strigolino Hootini", 18 } } },
			{ Id = "ForestDrip",   Name = "Drip Egg",   Price = 85,  Model = "ForestEgg2",
			  Table = { { "Fanghetto Palunko", 34 }, { "Strigolino Hootini", 36 }, { "Rospino Bavaglio", 30 } } },
			{ Id = "ForestHorned", Name = "Horned Egg", Price = 115, Model = "ForestEgg3",
			  Table = { { "Rospino Bavaglio", 45 }, { "Corvacchio Beccarino", 35 }, { "Ceppone Zampalunga", 20 } } },
			{ Id = "ForestRune",   Name = "Rune Egg",   Price = 160, Model = "ForestEgg4",
			  Table = { { "Ceppone Zampalunga", 40 }, { "Alcione Trombettone", 30 }, { "Lucciolone Pantanini", 20 }, { "Gufocervo Stiltini", 10 } } },
			{ Id = "ForestCrown",  Name = "Crown Egg",  Price = 220, Model = "ForestEgg5",
			  Table = { { "Alcione Trombettone", 34 }, { "Lucciolone Pantanini", 30 }, { "Gufocervo Stiltini", 30 }, { "Muschione Cornaluna", 6 } } },
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

function M.Validate()
	local live = {}
	for _, e in ipairs(BrainrotConfig.List or BrainrotConfig) do live[e.Name] = true end
	for worldId, w in pairs(M.WORLDS) do
		for _, egg in ipairs(w.Eggs) do
			local sum = 0
			for _, row in ipairs(egg.Table) do
				assert(live[row[1]], egg.Id .. " references unknown creature: " .. tostring(row[1]))
				sum += row[2]
			end
			assert(sum == 100, egg.Id .. " weights sum to " .. sum .. ", want 100")
		end
	end
	return true
end

return M
