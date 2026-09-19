-- DailyRewardHandler — SEVEN-DAY login streak week, a once-a-week streak-freeze
-- grace (one missed day forgiven), and promo codes.
-- Reads DailyStreak / LastClaimDay / LastFreezeDay / RedeemedCodes.
--
-- The week used to be 30 days of escalating CASH and nothing else. It is now
-- seven MIXED days -- cash, a Luck boost, darrels, a title, eggs -- authored in
-- ReplicatedStorage.Modules.DailyRewardConfig so the panel renders from the same
-- table the server pays from.
--
-- GRANTING IS NOT DONE HERE. Every payout goes through
-- SeasonPassHandler.GrantReward, the same switch the season track uses, so a
-- reward Kind is implemented exactly once. See SeasonConfig's header for the
-- exhaustive Kind list and the silent-dud warning that motivates sharing it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local CodeConfig = require(ServerScriptService.Modules.CodeConfig)
local SeasonPassHandler = require(ServerScriptService.Modules.SeasonPassHandler)
local DailyRewardConfig = require(ReplicatedStorage.Modules.DailyRewardConfig)
local remotes = ReplicatedStorage.Remotes

-- The week, authored in the shared config. Seven TYPED rewards now, not thirty
-- numbers; streakDayFor() below cycles the streak back through them, so day 8 is
-- day 1 again. Everything downstream sizes itself off #DAILY_REWARDS, including
-- the panel's card row, so the length lives in one place.
local DAILY_REWARDS = DailyRewardConfig.Days

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

	-- LastClaimDay is already written, so the claim is committed and the grant must
	-- not be able to no-op -- GrantReward holds that contract for every Kind and
	-- falls back to this day's Fallback cash if a branch cannot deliver (an egg
	-- that will not hatch, a title the player already owns).
	SeasonPassHandler.GrantReward(player, data, reward, (reward and reward.Fallback) or 0,
		("daily day %d"):format(day), "daily:day" .. day)

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
