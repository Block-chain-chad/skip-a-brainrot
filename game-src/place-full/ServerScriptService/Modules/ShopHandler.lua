local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local RockConfig = require(ReplicatedStorage.Modules.RockConfig)

local rockById = {}
local rockIndexById = {}
for i, rock in ipairs(RockConfig) do
	rockById[rock.Id] = rock
	rockIndexById[rock.Id] = i   -- ladder position, for the sequential-unlock check
end

local remotes = ReplicatedStorage.Remotes

local ShopHandler = {}

function ShopHandler.Init()
	remotes.BuyRock.OnServerEvent:Connect(function(player, rockId)
		local data = PlayerDataManager.Get(player)
		if not data then return end
		local rock = rockById[rockId]
		if not rock then
			remotes.PurchaseResult:FireClient(player, { Success = false, Message = "Unknown rock." })
			return
		end
		if data.OwnedRocks[rockId] then
			remotes.PurchaseResult:FireClient(player, { Success = false, Message = "Already owned." })
			return
		end
		-- SEQUENTIAL UNLOCK: you must own the previous rock in the ladder before buying this
		-- one. Authoritative here; MerchantClient also greys out locked rocks for clarity.
		local idx = rockIndexById[rockId]
		if idx and idx > 1 then
			local prev = RockConfig[idx - 1]
			if not data.OwnedRocks[prev.Id] then
				remotes.PurchaseResult:FireClient(player, { Success = false, Message = "Unlock the " .. prev.Id .. " first!" })
				return
			end
		end
		if data.Cash < rock.Price then
			remotes.PurchaseResult:FireClient(player, { Success = false, Message = "Not enough Cash." })
			return
		end

		data.Cash -= rock.Price
		data.OwnedRocks[rockId] = true
		data.EquippedRock = rockId

		remotes.PurchaseResult:FireClient(player, { Success = true, Message = "Bought and equipped " .. rockId .. "!" })
		PlayerDataManager.PushUpdate(player)
	end)

	remotes.EquipRock.OnServerEvent:Connect(function(player, rockId)
		local data = PlayerDataManager.Get(player)
		if not data then return end
		if not data.OwnedRocks[rockId] then
			remotes.PurchaseResult:FireClient(player, { Success = false, Message = "You don't own that rock." })
			return
		end
		data.EquippedRock = rockId
		remotes.PurchaseResult:FireClient(player, { Success = true, Message = "Equipped " .. rockId .. "!" })
		PlayerDataManager.PushUpdate(player)
	end)
end

return ShopHandler
