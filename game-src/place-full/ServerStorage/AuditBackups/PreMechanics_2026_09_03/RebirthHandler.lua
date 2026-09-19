-- RebirthHandler: prestige. Wipes CASH and your ROCK collection only -- brainrots
-- and their plot placements are kept -- in exchange for a small permanent stack of
-- money / luck / throw-power (applied in IncomeLoop + ThrowHandler via RebirthConfig).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local MaxwellQuest = require(ServerScriptService.Modules.MaxwellQuest)
local RebirthConfig = require(ReplicatedStorage.Modules.RebirthConfig)
local remotes = ReplicatedStorage.Remotes

local RebirthHandler = {}

function RebirthHandler.SendState(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local r = data.Rebirths or 0
	remotes.RebirthState:FireClient(player, {
		Rebirths = r,
		Cost = RebirthConfig.Cost(r),
		IncomeMult = RebirthConfig.IncomeMult(r),
		LuckMult = RebirthConfig.LuckMult(r),
		PowerMult = RebirthConfig.PowerMult(r),
		NextIncomeMult = RebirthConfig.IncomeMult(r + 1),
		NextLuckMult = RebirthConfig.LuckMult(r + 1),
		NextPowerMult = RebirthConfig.PowerMult(r + 1),
		CanAfford = data.Cash >= RebirthConfig.Cost(r),
	})
end

local function doRebirth(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local r = data.Rebirths or 0
	local cost = RebirthConfig.Cost(r)
	local result = remotes:FindFirstChild("PurchaseResult")
	if data.Cash < cost then
		if result then result:FireClient(player, { Success = false, Message = "Not enough cash to rebirth." }) end
		RebirthHandler.SendState(player)
		return
	end

	-- the prestige sacrifice: cash and the rock collection, nothing else.
	-- Brainrots stay exactly where they are, still placed and still earning.
	data.Cash = 0
	data.OwnedRocks = { Pebble = true }
	data.EquippedRock = "Pebble"
	data.Rebirths = r + 1

	PlayerDataManager.PushUpdate(player)
	RebirthHandler.SendState(player)
	-- Maxwell's step 2 is "reach Rebirth 15"; let his questline react to the new total.
	pcall(MaxwellQuest.NotifyRebirth, player)
	if result then
		result:FireClient(player, { Success = true, Message = "\u{2B50} Rebirth " .. data.Rebirths .. "! Permanent boost unlocked." })
	end
end

function RebirthHandler.Init()
	remotes.RebirthRequest.OnServerEvent:Connect(doRebirth)

	local function onJoin(player)
		task.spawn(function()
			local tries = 0
			while not PlayerDataManager.Get(player) and tries < 60 do task.wait(0.1); tries += 1 end
			if PlayerDataManager.Get(player) then task.wait(1); RebirthHandler.SendState(player) end
		end)
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, p in ipairs(Players:GetPlayers()) do onJoin(p) end

	-- refresh CanAfford as cash grows
	task.spawn(function()
		while true do
			task.wait(3)
			for _, p in ipairs(Players:GetPlayers()) do RebirthHandler.SendState(p) end
		end
	end)

	print("RebirthHandler online")
end

return RebirthHandler
