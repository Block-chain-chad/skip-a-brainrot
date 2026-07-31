-- TungQuest: Tung Tung Tung Sahur's questline -> the on-ramp to World 2.
-- Tung hates brainrots. Accept, then CAPTURE a quota by rarity (5 Epic / 5 Legendary
-- / 2 Mythic -- see TungQuestConfig) via skip-rock catches; claim to unlock the
-- portal in his cellar (sets data.TungPortalUnlocked). The portal / World 2 are
-- future work -- this only sets the flag. Mirrors the MaxwellQuest pattern
-- (state machine + Talk/State remotes, server-authoritative).
--
-- SERVER LOGIC ONLY: no dialogue/tracker UI yet. The `TungTalk` RemoteEvent and the
-- TungQuest.Accept/Claim functions are the seam a future NPC-prompt/dialogue wires
-- into; `TungState` is pushed for a future tracker.
--
-- State in data.TungQuest:
--   0 = not accepted   1 = capturing (progress in data.TungCatch by tier)
--   2 = quota met, reward ready   3 = done, cellar portal unlocked
-- Counters in data.TungCatch = { Epic, Legendary, Mythic } tick on catch while == 1.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local TungQuestConfig = require(ReplicatedStorage.Modules.TungQuestConfig)

local remotes = ReplicatedStorage.Remotes

local TungQuest = {}

local function getRemote(name, class)
	local r = remotes:FindFirstChild(name)
	if not r then r = Instance.new(class); r.Name = name; r.Parent = remotes end
	return r
end
local talkRemote  = getRemote("TungTalk", "RemoteEvent")
local stateRemote = getRemote("TungState", "RemoteEvent")

local function freshCounts() return { Epic = 0, Legendary = 0, Mythic = 0 } end

-- true once every tier quota is satisfied
local function quotaMet(data)
	local c = data.TungCatch or {}
	for _, r in ipairs(TungQuestConfig.Requirements) do
		if (c[r.Tier] or 0) < r.Count then return false end
	end
	return true
end

-- Push the whole quest picture (for a future dialogue/tracker). Step/Of = total
-- captures / total needed so a generic tracker pill can show one number.
local function sendState(player, note)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local c = data.TungCatch or {}
	local have, need, tiers = 0, 0, {}
	for _, r in ipairs(TungQuestConfig.Requirements) do
		local got = math.min(c[r.Tier] or 0, r.Count)
		have += got; need += r.Count
		tiers[r.Tier] = { Have = got, Need = r.Count }
	end
	stateRemote:FireClient(player, {
		State = data.TungQuest or 0,
		Tiers = tiers,
		Step = have, Of = need,
		Unlocked = data.TungPortalUnlocked and true or false,
		Note = note,
	})
end
TungQuest.SendState = sendState

-- advance 1 -> 2 once the whole quota is met
local function checkQuotaGate(player, data)
	if (data.TungQuest or 0) == 1 and quotaMet(data) then
		data.TungQuest = 2
		PlayerDataManager.PushUpdate(player)
		return true
	end
	return false
end

-- accept: 0 -> 1 (offered to anyone who talks to Tung)
local function accept(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	if (data.TungQuest or 0) == 0 then
		data.TungQuest = 1
		if type(data.TungCatch) ~= "table" then data.TungCatch = freshCounts() end
		PlayerDataManager.PushUpdate(player)
	end
	checkQuotaGate(player, data)
	sendState(player)
end
TungQuest.Accept = accept

-- claim: 2 -> 3, unlock the cellar portal flag
local function claim(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	checkQuotaGate(player, data)
	if (data.TungQuest or 0) ~= 2 then sendState(player); return end
	data.TungQuest = 3
	data.TungPortalUnlocked = true
	PlayerDataManager.PushUpdate(player)
	sendState(player, "portal")
end
TungQuest.Claim = claim

-- Called from ThrowHandler.revealCatch for EVERY catch (guarded by pcall there),
-- with tierName = the rarity tier. Counts toward the quota while the quest is active.
function TungQuest.NotifyCatch(player, tierName)
	local data = PlayerDataManager.Get(player)
	if not data or (data.TungQuest or 0) ~= 1 then return end
	local need = TungQuestConfig.ByTier[tierName]
	if not need then return end                       -- not a tracked tier
	if type(data.TungCatch) ~= "table" then data.TungCatch = freshCounts() end
	if (data.TungCatch[tierName] or 0) >= need then return end   -- this tier already full
	data.TungCatch[tierName] = (data.TungCatch[tierName] or 0) + 1
	if checkQuotaGate(player, data) then
		sendState(player, "quota")                    -- just completed the whole list
	else
		PlayerDataManager.PushUpdate(player)
		sendState(player, "capture")
	end
end

function TungQuest.Init()
	talkRemote.OnServerEvent:Connect(function(player, action)
		if action == "claim" then claim(player) else accept(player) end
	end)
	local function onJoin(player)
		task.spawn(function()
			local tries = 0
			while not PlayerDataManager.Get(player) and tries < 60 do task.wait(0.1); tries += 1 end
			local data = PlayerDataManager.Get(player)
			if data then
				task.wait(1)
				checkQuotaGate(player, data)
				sendState(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, p in ipairs(Players:GetPlayers()) do onJoin(p) end
	print("TungQuest online")
end

return TungQuest
