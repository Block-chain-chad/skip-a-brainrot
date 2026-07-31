local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local ThrowHandler = require(ServerScriptService.Modules.ThrowHandler)
local ShopHandler = require(ServerScriptService.Modules.ShopHandler)

local UpgradeHandler = require(ServerScriptService.Modules.UpgradeHandler)
local InventoryHandler = require(ServerScriptService.Modules.InventoryHandler)
local IncomeLoop = require(ServerScriptService.Modules.IncomeLoop)
local SellHandler = require(ServerScriptService.Modules.SellHandler)
local TradeHandler = require(ServerScriptService.Modules.TradeHandler)
local BoothHandler = require(ServerScriptService.Modules.BoothHandler)
local DailyRewardHandler = require(ServerScriptService.Modules.DailyRewardHandler)
local QuestHandler = require(ServerScriptService.Modules.QuestHandler)
local RebirthHandler = require(ServerScriptService.Modules.RebirthHandler)
local WeatherHandler = require(ServerScriptService.Modules.WeatherHandler)
local OfflineEarningsHandler = require(ServerScriptService.Modules.OfflineEarningsHandler)
local FusionHandler = require(ServerScriptService.Modules.FusionHandler)
local OfferingHandler = require(ServerScriptService.Modules.OfferingHandler)
local MintRegistry = require(ServerScriptService.Modules.MintRegistry)
local PriceIndex = require(ServerScriptService.Modules.PriceIndex)
local SeasonPassHandler = require(ServerScriptService.Modules.SeasonPassHandler)
local PlotBoardHandler = require(ServerScriptService.Modules.PlotBoardHandler)
local LimitedStock = require(ServerScriptService.Modules.LimitedStock)
local LeaderboardHandler = require(ServerScriptService.Modules.LeaderboardHandler)
local LeaderboardBoards = require(ServerScriptService.Modules.LeaderboardBoards)
local WheelHandler = require(ServerScriptService.Modules.WheelHandler)
local DevWeather = require(ServerScriptService.Modules.DevWeather)
local GianlucaQuest = require(ServerScriptService.Modules.GianlucaQuest)
local MaxwellQuest = require(ServerScriptService.Modules.MaxwellQuest)
local DarrelService = require(ServerScriptService.Modules.DarrelService)
local ProductRegistry = require(ServerScriptService.Modules.ProductRegistry)
local EggHandler = require(ServerScriptService.Modules.EggHandler)
local BoundsGuard = require(ServerScriptService.Modules.BoundsGuard)
local PetHandler = require(ServerScriptService.Modules.PetHandler)

local GamepassService = require(ServerScriptService.Modules.GamepassService)
local remotes = ReplicatedStorage.Remotes

remotes.GetInitialData.OnServerInvoke = function(player)
	local data = PlayerDataManager.Get(player)
	local timeout = 0
	while not data and timeout < 5 do
		task.wait(0.1)
		timeout += 0.1
		data = PlayerDataManager.Get(player)
	end
	return PlayerDataManager.Snapshot(player)
end

-- Sold-out truth for the Index cap badges. Server-side because LimitedStock
-- is; the schedule half of supply status is computed client-side
-- (SupplySchedule is shared and clock-pure). Cheap: 12 table reads, no
-- DataStore touch -- LimitedStock's own 60s refresher keeps the counts warm.
local supplyRemote = Instance.new("RemoteFunction")
supplyRemote.Name = "GetSupplySnapshot"
supplyRemote.Parent = remotes
supplyRemote.OnServerInvoke = function()
	local out = {}
	for name, cap in pairs(LimitedStock.MAX) do
		local remaining = LimitedStock.Remaining(name)
		out[name] = { cap = cap, minted = remaining and (cap - remaining) or nil }
	end
	return out
end

Players.PlayerAdded:Connect(function(player)
	PlayerDataManager.Load(player)
	PlayerDataManager.PushUpdate(player)
	OfflineEarningsHandler.OnJoin(player)
end)

remotes.TutorialComplete.OnServerEvent:Connect(function(player)
	local data = PlayerDataManager.Get(player)
	if data and not data.TutorialDone then
		data.TutorialDone = true
		PlayerDataManager.PushUpdate(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	PlayerDataManager.Remove(player)
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		PlayerDataManager.Save(player)
	end
end)

ThrowHandler.Init()
ShopHandler.Init()
UpgradeHandler.Init()
InventoryHandler.Init()
SellHandler.Init()
IncomeLoop.Init()
TradeHandler.Init()
BoothHandler.Init()
DailyRewardHandler.Init()
QuestHandler.Init()
RebirthHandler.Init()
WeatherHandler.Init()
OfflineEarningsHandler.Init()
FusionHandler.Init()
OfferingHandler.Init()
MintRegistry.Init()
PriceIndex.Init()
SeasonPassHandler.Init()
PlotBoardHandler.Init()
-- must run before the first throw can be revealed: until the global mint count is
-- read, LimitedStock.SoldOut() answers false and the cap is not yet enforced
LimitedStock.Init()
-- data first: Boards registers an OnUpdate callback with Handler, and paints from the
-- cache immediately if a fetch has already landed
LeaderboardHandler.Init()
LeaderboardBoards.Init()
WheelHandler.Init()
-- after WeatherHandler.Init(), since the command drives it
DevWeather.Init()
GianlucaQuest.Init()
MaxwellQuest.Init()
DarrelService.Init()
-- Roblox allows exactly one MarketplaceService.ProcessReceipt assignment for the whole
-- game; ProductRegistry.Init() is that single assignment site. See its header.
ProductRegistry.Init()
-- Server-side backstop behind Workspace.GameWorld.ValleyBarrier: the wall stops every
-- reachable speed, but a client that sets its own velocity can punch a corner, and only
-- the server can undo that. See the header in BoundsGuard.
BoundsGuard.Init()
-- After BoundsGuard: EggConfig.Validate() (called from EggHandler.Init) asserts on a bad
-- egg-table typo, and that must not take the containment guard down with it.
EggHandler.Init()
-- Task 11: pet system, shipped disabled (PetConfig.ENABLED=false). The LuckMult/IncomeMult
-- seams in ThrowHandler/IncomeLoop are already wired live and neutral; Init() only wires
-- the PetEquip remote and the CharacterAdded/Died follow-rig lifecycle.
PetHandler.Init()

-- Monetization: Robux gamepass ownership + effects. Headless (no UI/prompts);
-- inert until real ids are filled into ReplicatedStorage.Modules.GamepassConfig.
GamepassService.Init()
-- Handle players already in-game (e.g. Studio test start)
for _, player in ipairs(Players:GetPlayers()) do
	if not PlayerDataManager.Get(player) then
		PlayerDataManager.Load(player)
		PlayerDataManager.PushUpdate(player)
		OfflineEarningsHandler.OnJoin(player)
	end
end

print("Skip a Brainrot: server systems online")
