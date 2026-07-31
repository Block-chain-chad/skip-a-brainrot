-- DailyRewardHandler — 30-day login streak calendar with escalating cash rewards,
-- a once-a-week streak-freeze grace (one missed day forgiven), and promo codes.
-- Self-contained: reads DailyStreak / LastClaimDay / LastFreezeDay / RedeemedCodes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local CodeConfig = require(ServerScriptService.Modules.CodeConfig)
local SeasonPassHandler = require(ServerScriptService.Modules.SeasonPassHandler)
local remotes = ReplicatedStorage.Remotes

-- reward per streak-day (1..30), milestone spikes on days 7/14/21/30; cycle repeats
local DAILY_REWARDS = {
	500, 1000, 2500, 5000, 10000, 25000, 100000,
	2000, 4000, 8000, 15000, 30000, 60000, 250000,
	10000, 20000, 40000, 75000, 150000, 300000, 750000,
	25000, 50000, 100000, 200000, 400000, 800000, 1500000, 3000000, 10000000,
}

local FREEZE_COOLDOWN_DAYS = 7

local DailyRewardHandler = {}

local function currentDay()
	return math.floor(os.time() / 86400) -- whole UTC days since epoch
end

local function streakDayFor(streak)
	return ((streak - 1) % #DAILY_REWARDS) + 1
end

local function freezeAvailable(data, today)
	return today - (data.LastFreezeDay or 0) >= FREEZE_COOLDOWN_DAYS
end

-- what streak the next claim WOULD be (mirrors claim(); freeze forgives ONE missed day)
local function projectStreak(data, today)
	local gap = today - data.LastClaimDay
	if gap <= 0 then
		return data.DailyStreak
	elseif gap == 1 then
		return data.DailyStreak + 1
	elseif gap == 2 and freezeAvailable(data, today) then
		return data.DailyStreak + 1
	end
	return 1
end

function DailyRewardHandler.SendState(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local today = currentDay()
	remotes.DailyState:FireClient(player, {
		Claimable = data.LastClaimDay < today,
		Streak = data.DailyStreak,
		NextDay = streakDayFor(projectStreak(data, today)),
		Rewards = DAILY_REWARDS,
		FreezeAvailable = freezeAvailable(data, today),
	})
end

local function claim(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local today = currentDay()
	if data.LastClaimDay >= today then return end -- already claimed today (also guards spam)

	local gap = today - data.LastClaimDay
	local usedFreeze = false
	if gap == 1 then
		data.DailyStreak += 1
	elseif gap == 2 and freezeAvailable(data, today) then
		data.DailyStreak += 1
		data.LastFreezeDay = today
		usedFreeze = true
	else
		data.DailyStreak = 1
	end
	data.LastClaimDay = today
	local day = streakDayFor(data.DailyStreak)
	local reward = DAILY_REWARDS[day]
	PlayerDataManager.GrantCash(data, reward)
	SeasonPassHandler.Notify(player, "DailyClaim", 1)
	PlayerDataManager.PushUpdate(player)
	remotes.DailyState:FireClient(player, {
		Claimable = false,
		Streak = data.DailyStreak,
		NextDay = day,
		Rewards = DAILY_REWARDS,
		JustClaimed = reward,
		UsedFreeze = usedFreeze,
		FreezeAvailable = freezeAvailable(data, today),
	})
end

local function redeemCode(player, code)
	local data = PlayerDataManager.Get(player)
	if not data or typeof(code) ~= "string" then return end
	code = code:upper():gsub("%s+", "")
	if #code == 0 or #code > 30 then return end

	local def = CodeConfig[code]
	if not def then
		remotes.RedeemCode:FireClient(player, { Success = false, Message = "Invalid code!" })
		return
	end
	data.RedeemedCodes = data.RedeemedCodes or {}
	if data.RedeemedCodes[code] then
		remotes.RedeemCode:FireClient(player, { Success = false, Message = "Code already redeemed!" })
		return
	end
	data.RedeemedCodes[code] = true
	PlayerDataManager.GrantCash(data, def.Cash or 0)
	PlayerDataManager.PushUpdate(player)
	remotes.RedeemCode:FireClient(player, { Success = true, Message = ("Code redeemed: +$%d!"):format(def.Cash or 0) })
end

function DailyRewardHandler.Init()
	remotes.DailyClaim.OnServerEvent:Connect(claim)
	remotes.RedeemCode.OnServerEvent:Connect(redeemCode)

	local function onJoin(player)
		task.spawn(function()
			local tries = 0
			while not PlayerDataManager.Get(player) and tries < 60 do
				task.wait(0.1); tries += 1
			end
			if PlayerDataManager.Get(player) then
				task.wait(1) -- let the client build its UI
				DailyRewardHandler.SendState(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, p in ipairs(Players:GetPlayers()) do onJoin(p) end

	print("DailyRewardHandler online")
end

return DailyRewardHandler
