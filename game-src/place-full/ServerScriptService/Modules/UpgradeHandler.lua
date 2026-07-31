local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
local remotes = ReplicatedStorage.Remotes

local UpgradeHandler = {}

function UpgradeHandler.Init()
	remotes.BuyUpgrade.OnServerEvent:Connect(function(player, upgradeId)
		local data = PlayerDataManager.Get(player)
		if not data or typeof(upgradeId) ~= "string" then return end
		local def = UpgradeConfig.ById[upgradeId]
		if not def then return end

		data.Upgrades = data.Upgrades or {}
		local level = data.Upgrades[upgradeId] or 0
		local result = remotes:FindFirstChild("PurchaseResult")

		if level >= def.MaxLevel then
			if result then result:FireClient(player, { Success = false, Message = def.Name .. " is maxed out!" }) end
			return
		end
		local price = UpgradeConfig.Price(upgradeId, level)
		if not price then return end
		if data.Cash < price then
			if result then result:FireClient(player, { Success = false, Message = "Need $" .. price .. " for " .. def.Name }) end
			return
		end

		data.Cash -= price
		data.Upgrades[upgradeId] = level + 1
		if result then result:FireClient(player, { Success = true, Message = def.Name .. " Lv." .. (level + 1) .. "!" }) end
		PlayerDataManager.PushUpdate(player)
	end)
	print("UpgradeHandler online")
end

return UpgradeHandler
