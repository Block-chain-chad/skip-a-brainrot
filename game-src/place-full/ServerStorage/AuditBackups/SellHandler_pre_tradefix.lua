local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local InventoryHandler = require(ServerScriptService.Modules.InventoryHandler)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)

local SELL_MULTIPLIER = 40

local cashPerSecondByName = {}
for _, entry in ipairs(BrainrotConfig) do
	cashPerSecondByName[entry.Name] = entry.CashPerSecond
end

local remotes = ReplicatedStorage.Remotes

local SellHandler = {}

function SellHandler.Init()
	remotes.SellBrainrot.OnServerEvent:Connect(function(player, payload)
		local data = PlayerDataManager.Get(player)
		if not data then return end
		if typeof(payload) ~= "table" or typeof(payload.Name) ~= "string" then return end

		local cashPerSecond = cashPerSecondByName[payload.Name]
		if not cashPerSecond then
			remotes.SellResult:FireClient(player, { Success = false, Message = "Unknown brainrot." })
			return
		end

		local sellValueEach = cashPerSecond * SELL_MULTIPLIER
		local mode = payload.Mode == "All" and "All" or "One"

		-- Only brainrots sitting in the inventory can be sold. A placed one is
		-- earning on the base and must be picked up first (hold E on it), which
		-- is what clears its PadIndex. This also means selling never has to tear
		-- down a pad model -- if it is sellable, there is no model to remove.
		local totalSold, placedSkipped = 0, 0
		local remaining = {}
		for _, entry in ipairs(data.Brainrots) do
			local sellable = entry.Name == payload.Name and entry.PadIndex == nil
			if sellable and (mode == "All" or totalSold == 0) then
				totalSold += 1
				PlayerDataManager.DrainPending(player, entry, data)
			else
				if entry.Name == payload.Name and entry.PadIndex then placedSkipped += 1 end
				table.insert(remaining, entry)
			end
		end
		data.Brainrots = remaining

		if totalSold == 0 then
			local msg = placedSkipped > 0
				and ("That " .. payload.Name .. " is on your base \u{2014} pick it up first (hold E on it).")
				or ("You don't own any " .. payload.Name .. ".")
			remotes.SellResult:FireClient(player, { Success = false, Message = msg })
			return
		end

		local totalValue = totalSold * sellValueEach
		PlayerDataManager.GrantCash(data, totalValue)

		remotes.SellResult:FireClient(player, {
			Success = true,
			Message = "Sold " .. totalSold .. "x " .. payload.Name .. " for $" .. totalValue,
			Amount = totalValue,
		})

		-- the sold entries are gone from data; rebuild the Backpack so their Tools
		-- go with them. Without this the tool lingers and the brainrot still looks
		-- like it is in the inventory.
		InventoryHandler.SyncBackpack(player)
		PlayerDataManager.PushUpdate(player)
	end)
end

return SellHandler
