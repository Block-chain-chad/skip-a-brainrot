local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local BrainrotSpawner = require(script.Parent.BrainrotSpawner)

local dataStore = DataStoreService:GetDataStore("BrainrotSkip_PlayerData_v1")

local BASE_SPOTS = 12
local MAX_SPOTS = 16
local SPOT_PRICES = { [13] = 10000, [14] = 50000, [15] = 250000, [16] = 1000000 }

-- Saves outlive renames: BrainrotConfig entries must never be DELETED, but they
-- can be RENAMED, and every save written before a rename still holds the old
-- string. Those records resolve to nil in every entryByName lookup -- the item
-- can't be placed, sold, or traded -- so they are walked forward once per load.
local RENAMES = {
	["Cappuccino Assassino"] = "Ammazzacaffe Nerissimo", -- 2026-07-24 IP scrub of the roster
}

local PlayerDataManager = {}
PlayerDataManager.cache = {} -- [userId] = data table

-- canonical abbreviator, K through Qi -- see Modules.NumberFormat
local formatShort = require(ReplicatedStorage.Modules.NumberFormat).Short

local function defaultData()
	return {
		Cash = 0,
		OwnedRocks = { Pebble = true },
		EquippedRock = "Pebble",
		Brainrots = {}, -- array of { Name = string, PadIndex = number?, Mutation = string? }
		UnlockedSpots = BASE_SPOTS,
		-- daily login rewards
		DailyStreak = 0,
		LastClaimDay = 0,
		LastFreezeDay = 0, -- last day the streak-freeze grace was used
		RedeemedCodes = {}, -- [CODE] = true
		-- daily quests
		Quests = {}, -- [questId] = { claimed = bool }
		QuestDay = 0,
		-- prestige
		Rebirths = 0,
		-- brainrot index: [name] = true once caught
		Discovered = {},
		-- purchased upgrade levels: [id] = level
		Upgrades = {},
		-- first-time onboarding shown?
		TutorialDone = false,
		-- rolling id so each brainrot can own a Backpack tool
		NextUid = 1,
		-- unix time of last save, for offline earnings
		LastSeen = 0,
		-- brainrots burned into the campfire as Offerings (permanent luck, diminishing)
		Offerings = 0,
		-- season pass
		SeasonXP = 0,
		SeasonClaimed = {}, -- [tostring(tier)] = true
		SeasonQuests = {}, -- [questId] = { P = n, D = bool }, resets daily
		SeasonQuestDay = 0,
		-- === camp board (2026-07-24) ===
		TotalEarned = 0,      -- lifetime cash PRODUCED by this player's brainrots; survives rebirth
		PlotLikes = 0,        -- lifetime likes received on this player's camp
		LikedPlayers = {},    -- [tostring(otherUserId)] = true : camps I have already liked
		-- === global leaderboards (2026-07-25) ===
		LifetimeEarned = 0,   -- ALL money ever received, from every source. This is what the
		                      -- leaderboard means by "earned"; TotalEarned above is narrower
		                      -- (production only) and must stay that way, because the camp
		                      -- board and offline earnings are built on it.
		TimePlayed = 0,       -- lifetime seconds in game. Accumulated on a timer rather than
		                      -- measured on leave: Main's PlayerRemoving saves before any
		                      -- later-Init'd handler could flush a session length.
		BrainrotsCaught = 0,  -- lifetime CATCHES. Trades, booth buys and offerings deliberately
		                      -- do not count -- this is meant to measure throwing, not acquiring.
		-- === daily wheel (2026-07-25) ===
		LastSpinAt = 0,       -- os.time() of the last free spin; 0 means never spun
		Boosts = {},          -- ["Luck"|"Power"] = os.time() the boost expires. Real-time, so a
		                      -- 10 minute boost does not pause when the player logs off.
	}
end

function PlayerDataManager.Get(player)
	return PlayerDataManager.cache[player.UserId]
end

function PlayerDataManager.GetPlot(player)
	local plotsFolder = Workspace:FindFirstChild("PlayerBases")
	if not plotsFolder then return nil end
	for _, plot in ipairs(plotsFolder:GetChildren()) do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			return plot
		end
	end
	return nil
end

function PlayerDataManager.TakeUid(data)
	data.NextUid = data.NextUid or 1
	local id = data.NextUid
	data.NextUid = id + 1
	return id
end

function PlayerDataManager.FindFreePad(data)
	local used = {}
	for _, entry in ipairs(data.Brainrots) do
		if entry.PadIndex then
			used[entry.PadIndex] = true
		end
	end
	local limit = math.min(data.UnlockedSpots or BASE_SPOTS, MAX_SPOTS)
	for i = 1, limit do
		if not used[i] then
			return i
		end
	end
	return nil
end

-- Show/refresh which plot spots are open vs locked (with buy prompts) for the owner
function PlayerDataManager.RefreshPlotSpots(player)
	local data = PlayerDataManager.cache[player.UserId]
	local plot = PlayerDataManager.GetPlot(player)
	if not data or not plot then return end
	local pads = plot:FindFirstChild("Pads")
	if not pads then return end
	local unlocked = data.UnlockedSpots or BASE_SPOTS

	for i = 1, MAX_SPOTS do
		local pad = pads:FindFirstChild("Pad" .. i)
		if pad then
			local oldGui = pad:FindFirstChild("LockGui")
			if oldGui then oldGui:Destroy() end
			local oldPrompt = pad:FindFirstChildOfClass("ProximityPrompt")
			if oldPrompt then oldPrompt:Destroy() end

			if i <= unlocked then
				pad.Color = Color3.fromRGB(80, 80, 90)
				pad.Material = Enum.Material.Metal
				pad.Transparency = 0
			else
				pad.Color = ((i == unlocked + 1) and Color3.fromRGB(74, 62, 44) or Color3.fromRGB(46, 40, 46))
				pad.Material = Enum.Material.Slate
				pad.Transparency = ((i == unlocked + 1) and 0 or 0.45)
				local price = SPOT_PRICES[i] or 0
				local isNext = (i == unlocked + 1)

				local gui = Instance.new("BillboardGui")
				gui.Name = "LockGui"
				gui.Size = UDim2.new(0, 130, 0, 46)
				gui.StudsOffset = Vector3.new(0, 3, 0)
				gui.AlwaysOnTop = true
				gui.Parent = pad
				local label = Instance.new("TextLabel")
				label.Size = UDim2.new(1, 0, 1, 0)
				label.BackgroundTransparency = 1
				label.TextColor3 = isNext and Color3.fromRGB(255, 220, 90) or Color3.fromRGB(132, 132, 148)
				label.TextStrokeTransparency = 0
				label.Font = Enum.Font.GothamBold
				label.TextScaled = true
				label.Text = isNext and ("\u{1F512} Buy Spot\n$" .. formatShort(price)) or ("\u{1F512} $" .. formatShort(price) .. "\nUnlock #" .. (unlocked + 1) .. " first")
				label.Parent = gui

				if isNext then
					local prompt = Instance.new("ProximityPrompt")
					prompt.Name = "BuySpotPrompt"
					prompt.ActionText = "Buy ($" .. formatShort(price) .. ")"
					prompt.ObjectText = "Plot Spot " .. i
					prompt.HoldDuration = 0.3
					prompt.MaxActivationDistance = 14
					prompt.RequiresLineOfSight = false
					prompt.Parent = pad
					prompt.Triggered:Connect(function(triggerPlayer)
						if triggerPlayer == player then
							PlayerDataManager.TryBuySpot(player)
						end
					end)
				end
			end
		end
	end
end

function PlayerDataManager.TryBuySpot(player)
	local data = PlayerDataManager.cache[player.UserId]
	if not data then return end
	local unlocked = data.UnlockedSpots or BASE_SPOTS
	local nextSpot = unlocked + 1
	if nextSpot > MAX_SPOTS then return end
	local price = SPOT_PRICES[nextSpot]
	if not price then return end

	local result = ReplicatedStorage.Remotes:FindFirstChild("PurchaseResult")
	if data.Cash < price then
		if result then
			result:FireClient(player, { Success = false, Message = "Need $" .. formatShort(price) .. " to unlock spot " .. nextSpot })
		end
		return
	end

	data.Cash -= price
	data.UnlockedSpots = nextSpot
	PlayerDataManager.RefreshPlotSpots(player)
	if result then
		result:FireClient(player, { Success = true, Message = "Unlocked plot spot " .. nextSpot .. "!" })
	end
	PlayerDataManager.PushUpdate(player)
end

-- Camp board state lives as attributes on the plot Model; the client renders it.
local function refreshPlotBoard(plot, player)
	if not plot then return end
	if not player then
		plot:SetAttribute("OwnerName", "")
		plot:SetAttribute("TotalEarned", 0)
		plot:SetAttribute("PlotLikes", 0)
		return
	end
	local d = PlayerDataManager.cache[player.UserId]
	plot:SetAttribute("OwnerName", string.sub(player.DisplayName or player.Name, 1, 18))
	plot:SetAttribute("TotalEarned", math.floor((d and d.TotalEarned) or 0))
	plot:SetAttribute("PlotLikes", math.floor((d and d.PlotLikes) or 0))
end

local function releasePlot(player)
	local plot = PlayerDataManager.GetPlot(player)
	if not plot then return end
	local pads = plot:FindFirstChild("Pads")
	if pads then
		for _, child in ipairs(pads:GetChildren()) do
			if not child.Name:match("^Pad%d+$") then
				child:Destroy() -- brainrot models
			else
				local lock = child:FindFirstChild("LockGui")
				if lock then lock:Destroy() end
				local prompt = child:FindFirstChildOfClass("ProximityPrompt")
				if prompt then prompt:Destroy() end
			end
		end
	end
	plot:SetAttribute("Claimed", false)
	plot:SetAttribute("OwnerUserId", 0)
	refreshPlotBoard(plot, nil)
	local campfire = plot:FindFirstChild("Campfire")
	if campfire then
		campfire:SetAttribute("Banked", 0)
	end
end

function PlayerDataManager.Snapshot(player)
	local data = PlayerDataManager.cache[player.UserId]
	if not data then return nil end
	return {
		Cash = data.Cash,
		OwnedRocks = data.OwnedRocks,
		EquippedRock = data.EquippedRock,
		Brainrots = data.Brainrots,
		UnlockedSpots = data.UnlockedSpots,
		Discovered = data.Discovered,
		Upgrades = data.Upgrades,
		TutorialDone = data.TutorialDone,
		Rebirths = data.Rebirths,
		TotalEarned = data.TotalEarned,
		Offerings = data.Offerings,
		PlotLikes = data.PlotLikes,
		LikedPlayers = data.LikedPlayers,
	}
end

function PlayerDataManager.Load(player)
	local data
	local ok, result = pcall(function()
		return dataStore:GetAsync("Player_" .. player.UserId)
	end)
	if ok and result then
		data = result
		if not data.OwnedRocks then data.OwnedRocks = { Pebble = true } end
		if not data.EquippedRock then data.EquippedRock = "Pebble" end
		if not data.Brainrots then data.Brainrots = {} end
		if not data.UnlockedSpots then data.UnlockedSpots = BASE_SPOTS end
		if not data.DailyStreak then data.DailyStreak = 0 end
		if not data.LastClaimDay then data.LastClaimDay = 0 end
		if not data.Quests then data.Quests = {} end
		if not data.QuestDay then data.QuestDay = 0 end
		if not data.Rebirths then data.Rebirths = 0 end
		if not data.Discovered then data.Discovered = {} end
		if not data.Upgrades then data.Upgrades = {} end
		if data.TutorialDone == nil then data.TutorialDone = false end
		if not data.LastSeen then data.LastSeen = 0 end
		if not data.LastFreezeDay then data.LastFreezeDay = 0 end
		if not data.RedeemedCodes then data.RedeemedCodes = {} end
		if not data.SeasonXP then data.SeasonXP = 0 end
		if not data.SeasonClaimed then data.SeasonClaimed = {} end
		if not data.SeasonQuests then data.SeasonQuests = {} end
		if not data.SeasonQuestDay then data.SeasonQuestDay = 0 end
		if type(data.Offerings) ~= "number" then data.Offerings = 0 end
		if type(data.TotalEarned) ~= "number" then data.TotalEarned = 0 end
		if type(data.PlotLikes) ~= "number" then data.PlotLikes = 0 end
		if type(data.LikedPlayers) ~= "table" then data.LikedPlayers = {} end
		if type(data.LifetimeEarned) ~= "number" then
			-- One-time estimate for saves predating this field. Money already SPENT is not
			-- recoverable from anything stored, so take the best available floor: you have
			-- earned at least what you are holding, and at least what you produced.
			data.LifetimeEarned = math.max(tonumber(data.Cash) or 0, tonumber(data.TotalEarned) or 0)
		end
		if type(data.TimePlayed) ~= "number" then data.TimePlayed = 0 end
		if type(data.BrainrotsCaught) ~= "number" then data.BrainrotsCaught = 0 end
		if type(data.LastSpinAt) ~= "number" then data.LastSpinAt = 0 end
		if type(data.Boosts) ~= "table" then data.Boosts = {} end
		data.NextUid = data.NextUid or 1
		for _, e in ipairs(data.Brainrots) do
			if RENAMES[e.Name] then e.Name = RENAMES[e.Name] end
			if not e.Uid then e.Uid = data.NextUid; data.NextUid += 1 end
			-- Discovery backfill: the Discovered flag was never written before
			-- 2026-07-25, so owning a copy is the only proof the catch happened.
			data.Discovered[e.Name] = true
		end
		-- Renames must walk EVERY place a config name is persisted. Ancient saves
		-- carry Discovered keys written by an early build (the writer was later
		-- lost in a refactor), so old names can lurk here even when no owned
		-- record does.
		for oldName, newName in pairs(RENAMES) do
			if data.Discovered[oldName] then
				data.Discovered[oldName] = nil
				data.Discovered[newName] = true
			end
		end
	elseif ok then
		data = defaultData()                 -- genuinely a new player: empty read, no error
	else
		data = defaultData()
		data.__noSave = true                 -- DataStore READ FAILED: never overwrite the real profile
		warn("[PlayerDataManager] load failed for " .. player.Name .. "; session is read-only")
	end
	PlayerDataManager.cache[player.UserId] = data

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local cashStat = Instance.new("NumberValue")
	cashStat.Name = "Cash"
	cashStat.Value = data.Cash
	cashStat.Parent = leaderstats
	leaderstats.Parent = player

	PlayerDataManager.RefreshPlotSpots(player)

	return data
end

function PlayerDataManager.SyncLeaderstat(player)
	local data = PlayerDataManager.cache[player.UserId]
	if not data then return end
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local cashStat = leaderstats:FindFirstChild("Cash")
		if cashStat then
			cashStat.Value = data.Cash
		end
	end
end

-- Single funnel for lifetime earnings. Cash grants that are NOT production
-- (trades, booth sales, daily/quest/season/codes, sell) must not call this.
-- Returns the amount actually credited (0 on failure) so callers can verify.
function PlayerDataManager.AddEarnings(player, amount, dataOpt)
	-- `player and` guard: every spec'd caller passes dataOpt so this short-circuits,
	-- but without it a nil player throws instead of returning 0. See DEVIATIONS.
	local data = dataOpt or (player and PlayerDataManager.cache[player.UserId])
	if not data or type(amount) ~= "number" or amount ~= amount or amount <= 0 then return 0 end
	data.Cash += amount
	data.TotalEarned = (data.TotalEarned or 0) + amount
	data.LifetimeEarned = (data.LifetimeEarned or 0) + amount
	return amount
end

-- The funnel for every NON-production cash grant: sells, booth proceeds, daily rewards,
-- codes, quests, season pass. Exists so LifetimeEarned stays honest without widening
-- AddEarnings, whose narrower meaning other systems depend on.
--
-- Spending must NOT go through here -- subtract from data.Cash directly, the way
-- BoothHandler does for the buyer.
-- Multiplier from a timed wheel boost, or 1 when none is running. Reads os.time() every
-- call rather than caching, so an expiring boost stops mattering mid-session with no
-- tick or cleanup task anywhere.
function PlayerDataManager.BoostMult(data, stat)
	if not data or type(data.Boosts) ~= "table" then return 1 end
	local expiry = tonumber(data.Boosts[stat])
	if not expiry or os.time() >= expiry then return 1 end
	local WheelConfig = require(game:GetService("ReplicatedStorage").Modules.WheelConfig)
	return WheelConfig.BOOST_MULT
end

-- Seconds left on a boost, or 0. For the HUD.
function PlayerDataManager.BoostRemaining(data, stat)
	if not data or type(data.Boosts) ~= "table" then return 0 end
	local expiry = tonumber(data.Boosts[stat])
	if not expiry then return 0 end
	return math.max(0, expiry - os.time())
end

function PlayerDataManager.GrantCash(data, amount)
	if not data or type(amount) ~= "number" or amount ~= amount or amount <= 0 then return 0 end
	data.Cash += amount
	data.LifetimeEarned = (data.LifetimeEarned or 0) + amount
	return amount
end

-- Drains a brainrot entry's banked Pending into the owner's cash + lifetime
-- earnings. Call this immediately BEFORE removing or unplacing the entry.
function PlayerDataManager.DrainPending(player, entry, dataOpt)
	if not entry then return 0 end
	local pend = math.floor(entry.Pending or 0)
	entry.Pending = 0
	if pend < 1 then return 0 end
	return PlayerDataManager.AddEarnings(player, pend, dataOpt)
end

function PlayerDataManager.PushUpdate(player)
	PlayerDataManager.SyncLeaderstat(player)
	local data = PlayerDataManager.cache[player.UserId]
	if data and data.Discovered then
		-- Discovery is recorded HERE because every acquisition path (catch, trade,
		-- booth, fusion, wheel) already ends in a PushUpdate: one merge point
		-- instead of five handler edits. The set only ever grows, so selling or
		-- trading away your last copy can never un-discover a name.
		for _, e in ipairs(data.Brainrots) do
			data.Discovered[e.Name] = true
		end
	end
	local snapshot = PlayerDataManager.Snapshot(player)
	if snapshot then
		ReplicatedStorage.Remotes.DataUpdated:FireClient(player, snapshot)
	end
end

-- Returns true if the write landed. Callers that move items BETWEEN players
-- (trades, booth sales) must check this: two independent SetAsync calls with no
-- retry meant a failed giver-write plus a successful receiver-write duplicated
-- the item silently, and duped items poison the whole class because nobody can
-- tell an honest copy from a forged one.
function PlayerDataManager.Save(player)
	local data = PlayerDataManager.cache[player.UserId]
	if not data then return false end
	if data.__noSave then return false end  -- load failed; writing would wipe the real profile
	data.LastSeen = os.time()
	local key = "Player_" .. player.UserId
	for attempt = 1, 3 do
		-- UpdateAsync over SetAsync: it is transactional per key and retries on conflict
		local ok, err = pcall(function()
			dataStore:UpdateAsync(key, function()
				return data
			end)
		end)
		if ok then return true end
		if attempt == 3 then
			warn(("[PlayerDataManager] save FAILED for %s after 3 attempts: %s"):format(player.Name, tostring(err)))
		else
			task.wait(0.4 * attempt)
		end
	end
	return false
end

function PlayerDataManager.Remove(player)
	releasePlot(player)                 -- stop accepting likes BEFORE the SetAsync yield
	PlayerDataManager.Save(player)
	PlayerDataManager.cache[player.UserId] = nil
end

-- === Tycoon-style claiming: walk onto a free plot to claim it ===
function PlayerDataManager.ClaimPlotFor(player, plot)
	if not plot or plot:GetAttribute("Claimed") then return false end
	if PlayerDataManager.GetPlot(player) then return false end
	plot:SetAttribute("OwnerUserId", player.UserId)
	refreshPlotBoard(plot, player)
	plot:SetAttribute("Claimed", true)
	PlayerDataManager.RefreshPlotSpots(player)
	local data = PlayerDataManager.cache[player.UserId]
	if data and data.Brainrots then
		BrainrotSpawner.RestoreAll(plot, data.Brainrots)
	end
	if PlayerDataManager.OnPlotClaimed then PlayerDataManager.OnPlotClaimed(player) end
	local result = ReplicatedStorage.Remotes:FindFirstChild("PurchaseResult")
	if result then
		result:FireClient(player, { Success = true, Message = "Base claimed!" })
	end
	return true
end

local claimCooldown = {}
local function tryClaimByTouch(plot, hit)
	local character = hit and hit.Parent
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end
	if plot:GetAttribute("Claimed") then return end
	if PlayerDataManager.GetPlot(player) then return end
	if claimCooldown[player.UserId] then return end
	claimCooldown[player.UserId] = true
	task.delay(1, function() claimCooldown[player.UserId] = nil end)
	PlayerDataManager.ClaimPlotFor(player, plot)
end

do
	local plotsFolder = Workspace:FindFirstChild("PlayerBases")
	if plotsFolder then
		for _, plot in ipairs(plotsFolder:GetChildren()) do
			if plot:IsA("Model") then
				local pad = plot.PrimaryPart or plot:FindFirstChild("Platform")
				if pad then
					pad.Touched:Connect(function(hit) tryClaimByTouch(plot, hit) end)
				end
			end
		end
	end
end

return PlayerDataManager
