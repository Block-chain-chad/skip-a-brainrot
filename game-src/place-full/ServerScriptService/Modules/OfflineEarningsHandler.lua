-- Offline earnings: on join, pay out a SHARE of what the placed brainrots would
-- have earned while away, over a limited window. Both the share and the window
-- start low and are raised by the "Campfire Keeper" upgrade. Cash is awarded immediately
-- at load; the popup payload is held until the client reports ready (remotes fired
-- before the client connects its listener would be lost).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)
local RebirthConfig = require(ReplicatedStorage.Modules.RebirthConfig)
local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)

local remotes = ReplicatedStorage.Remotes

local MIN_AWAY_SECONDS = 60 -- ignore quick rejoins

local cashPerSecondByName = {}
for _, entry in ipairs(BrainrotConfig) do
	cashPerSecondByName[entry.Name] = entry.CashPerSecond
end

local pendingPopup = {} -- [userId] = payload

local OfflineEarningsHandler = {}

function OfflineEarningsHandler.OnJoin(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local last = data.LastSeen or 0
	if last <= 0 then return end
	local elapsed = os.time() - last
	if elapsed < MIN_AWAY_SECONDS then return end

	-- both the window and the share are gated behind Campfire Keeper
	local capSeconds = math.floor(UpgradeConfig.OfflineHours(data.Upgrades) * 3600)
	local rate = UpgradeConfig.OfflineRate(data.Upgrades)
	local counted = math.min(elapsed, capSeconds)

	local rebirthMult = RebirthConfig.IncomeMult(data.Rebirths)
	local upMult = UpgradeConfig.IncomeMult(data.Upgrades)
	local cps = 0
	for _, e in ipairs(data.Brainrots) do
		if e.PadIndex then
			cps += (cashPerSecondByName[e.Name] or 0) * Mutations.Mult(e.Mutation) * rebirthMult * upMult
		end
	end

	local payout = math.floor(cps * counted * rate)
	if payout < 1 then return end

	PlayerDataManager.AddEarnings(player, payout, data)
	PlayerDataManager.PushUpdate(player)
	pendingPopup[player.UserId] = {
		Payout = payout,
		Seconds = counted,
		Capped = elapsed > capSeconds,
		CapSeconds = capSeconds,
		Rate = rate,
	}
end

function OfflineEarningsHandler.Init()
	-- client fires this remote once its popup UI is listening
	remotes.OfflineEarnings.OnServerEvent:Connect(function(player)
		local payload = pendingPopup[player.UserId]
		if payload then
			pendingPopup[player.UserId] = nil
			remotes.OfflineEarnings:FireClient(player, payload)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		pendingPopup[player.UserId] = nil
	end)
	print("OfflineEarningsHandler online")
end

return OfflineEarningsHandler
