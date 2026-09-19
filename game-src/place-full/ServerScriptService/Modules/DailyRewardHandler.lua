-- DailyRewardHandler — SEVEN-DAY login streak week, a once-a-week streak-freeze
-- grace (one missed day forgiven), and promo codes.
-- Reads DailyStreak / LastClaimDay / LastFreezeDay / RedeemedCodes.
--
-- The week used to be 30 days of escalating CASH and nothing else. It is now
-- seven MIXED days -- cash, a Luck boost, emeralds, a title, eggs -- authored in
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
-- NO BagConfig REQUIRE ANY MORE (2026-08-26). The bag check this file used to
-- run before stamping a claim has moved down into GrantReward's Egg branch,
-- which PARKS what will not fit instead of refusing it -- see the long note in
-- claim() below for why the daily week, unlike the season track, cannot afford
-- to back out of a claim. (The comment that stood here also named the wrong day:
-- the egg is day 7, not day 5.)
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

	-- === A FULL PET BAG PARKS THE EGG DAY, IT DOES NOT REFUSE IT (2026-08-26) ===
	-- This block USED to call SeasonPassHandler.PetSpaceNeeded here and bail before
	-- stamping anything, reasoning that "the day stays claimable ... they can claim
	-- it the moment they sell a pet". THAT PREMISE WAS FALSE FOR THIS CALLER.
	--
	-- The rule it came from is still right for the SEASON TRACK, and claimTier
	-- still enforces it: a tier you refuse today is still sitting in the Goals
	-- panel tomorrow, so backing out costs the player nothing. A DAILY CARD HAS NO
	-- SECOND ENTRANCE. Its rail tile was removed on 2026-08-07 (see the "NO DAILY
	-- TILE" note in GameHUDClient) and the calendar now opens only at join.
	--
	-- Worse: GameHUDClient's AUTO-CLAIM ON DISMISS -- the net that exists precisely
	-- so closing the panel cannot forfeit the day -- fires this same remote, hit
	-- this same refuse, and returned silently behind a panel that was already
	-- closing. A full bag therefore ATE the day and, once the gap reached 2, burned
	-- the streak freeze or reset the streak outright: the exact outcome both of
	-- those decisions were written to prevent.
	--
	-- So the daily week now does what the wheel's crate does. Claim, then let
	-- GrantReward's Egg branch park whatever will not fit into data.PendingEggs and
	-- say so on the toast channel. PetHandler.FlushPendingEggs hands them over the
	-- moment room appears -- every sale, every rejoin, and the Bag's own claim
	-- button -- so the reward is DEFERRED rather than lost, and the streak survives
	-- a full bag.
	--
	-- GrantReward's contract is still met. A committed claim still always delivers:
	-- parking IS delivery, on exactly the terms the wheel already ships.

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
