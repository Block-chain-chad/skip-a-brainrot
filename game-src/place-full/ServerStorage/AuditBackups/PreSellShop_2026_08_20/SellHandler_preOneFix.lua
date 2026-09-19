local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local InventoryHandler = require(ServerScriptService.Modules.InventoryHandler)
local MintRegistry = require(ServerScriptService.Modules.MintRegistry)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local WorldProgression = require(ReplicatedStorage.Modules.WorldProgression)
-- canonical abbreviator, K through Sp -- see Modules.NumberFormat
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local SellValue = require(ReplicatedStorage.Modules.SellValue)

-- EVERY WORLD (fixed 2026-08-07). Built from BrainrotConfig alone, this priced the 30
-- tundra-exclusive brainrots at nil -- they would have sold for nothing.
-- Valley first so a shared name keeps its World 1 rarity.
-- Pricing itself now lives entirely in SellValue (2026-08-20, sell shop revamp);
-- rarityByName survives here ONLY because MintRegistry.Burn still needs a rarity
-- to gate its tracked-mint check on.
local rarityByName = {}
for _, entry in ipairs(BrainrotConfig) do
	rarityByName[entry.Name] = entry.Rarity
end
for _, worldName in ipairs(WorldProgression.List()) do
	local world = WorldProgression.Resolve(worldName)
	for _, e in ipairs((world and world.Pool) or {}) do
		if rarityByName[e.Name] == nil then
			rarityByName[e.Name] = e.Rarity
		end
	end
end

local remotes = ReplicatedStorage.Remotes

local SellHandler = {}

function SellHandler.Init()
	remotes.SellBrainrot.OnServerEvent:Connect(function(player, payload)
		local data = PlayerDataManager.Get(player)
		if not data then return end
		if typeof(payload) ~= "table" then return end

		-- READ-ONLY SESSION GUARD. A failed DataStore load serves a DEFAULT
		-- profile and every write is discarded at logout, so selling here would
		-- destroy the brainrot and hand back cash that never persists.
		-- PetHandler.Sell has always guarded this; this path did not.
		if data.__noSave then
			remotes.SellResult:FireClient(player, { Success = false,
				Message = "Your profile did not load \u{2014} rejoin before selling." })
			return
		end

		local mode = payload.Mode
		local chosen, held = {}, 0
		if type(payload.Uids) == "table" then
			local want = {}
			for _, u in ipairs(payload.Uids) do want[u] = true end
			for _, e in ipairs(data.Brainrots) do
				if want[e.Uid] and e.PadIndex == nil and not e.Fav
					and SellValue.OfBrainrot(e) ~= nil then
					chosen[#chosen + 1] = e
				end
			end
		elseif mode == "Duplicates" then
			chosen, held = SellValue.SelectBulk(data.Brainrots, nil)
		elseif mode == "All" then
			if typeof(payload.Name) ~= "string" then return end
			chosen, held = SellValue.SelectBulk(data.Brainrots, payload.Name)
		else
			if typeof(payload.Name) ~= "string" then return end
			local one = SellValue.SelectCheapest(data.Brainrots, payload.Name)
			if one then chosen[1] = one end
		end

		if #chosen == 0 then
			remotes.SellResult:FireClient(player, { Success = false,
				Message = held > 0
					and ("Nothing there to bulk sell \u{2014} %d copies are mutated, oversized or locked. Sell those one at a time."):format(held)
					or "You don't own anything sellable there." })
			return
		end

		local sellSet = {}
		for _, e in ipairs(chosen) do sellSet[e] = true end
		local totalValue, totalSold = 0, 0
		local remaining = {}
		for _, entry in ipairs(data.Brainrots) do
			if sellSet[entry] then
				totalSold += 1
				totalValue += (SellValue.OfBrainrot(entry) or 0)
				PlayerDataManager.DrainPending(player, entry, data)
				if MintRegistry.IsTracked(rarityByName[entry.Name], entry.Mutation) then
					pcall(MintRegistry.Burn, entry.Name, entry.Mutation, 1)
				end
			else
				remaining[#remaining + 1] = entry
			end
		end
		data.Brainrots = remaining
		PlayerDataManager.GrantCash(data, totalValue)

		remotes.SellResult:FireClient(player, {
			Success = true,
			Message = ("Sold %d for %s%s"):format(totalSold, NumberFormat.Cash(totalValue),
				held > 0 and (" (" .. held .. " mutated or oversized kept)") or ""),
			Amount = totalValue,
		})
		InventoryHandler.SyncBackpack(player)
		PlayerDataManager.PushUpdate(player)
	end)
end

return SellHandler
