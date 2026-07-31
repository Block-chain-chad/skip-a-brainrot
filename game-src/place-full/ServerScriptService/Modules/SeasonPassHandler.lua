-- SeasonPassHandler: daily quests feed Season XP; XP unlocks a 25-tier reward track.
-- Other handlers report events via SeasonPassHandler.Notify / NotifyCatch (additive hooks).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local SeasonConfig = require(ReplicatedStorage.Modules.SeasonConfig)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)

local remotes = ReplicatedStorage.Remotes

local rarityIndexByName = {}
for i, tier in ipairs(RarityConfig) do rarityIndexByName[tier.Name] = i end

local SeasonPassHandler = {}

local function currentDay()
	return math.floor(os.time() / 86400)
end

-- reset quest progress when the UTC day rolls over
local function ensureDay(data)
	local today = currentDay()
	if data.SeasonQuestDay ~= today then
		data.SeasonQuestDay = today
		data.SeasonQuests = {}
	end
	return today
end

function SeasonPassHandler.SendState(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local today = ensureDay(data)
	local questIds, progress = {}, {}
	for _, def in ipairs(SeasonConfig.QuestsForDay(today)) do
		table.insert(questIds, def.Id)
		local q = data.SeasonQuests[def.Id]
		progress[def.Id] = { P = q and q.P or 0, D = q and q.D or false }
	end
	remotes.SeasonState:FireClient(player, {
		XP = data.SeasonXP or 0,
		Claimed = data.SeasonClaimed or {},
		QuestIds = questIds,
		Progress = progress,
		Day = today,
	})
end

function SeasonPassHandler.Notify(player, event, n)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local today = ensureDay(data)
	local changed = false
	for _, def in ipairs(SeasonConfig.QuestsForDay(today)) do
		if def.Event == event then
			local q = data.SeasonQuests[def.Id]
			if not q then q = { P = 0, D = false }; data.SeasonQuests[def.Id] = q end
			if not q.D then
				q.P = math.min(q.P + (n or 1), def.Target)
				if q.P >= def.Target then
					q.D = true
					data.SeasonXP = (data.SeasonXP or 0) + def.XP
				end
				changed = true
			end
		end
	end
	if changed then
		SeasonPassHandler.SendState(player)
	end
end

-- Rare = index 3+, Epic = index 4+ (both quests can progress from one catch)
function SeasonPassHandler.NotifyCatch(player, tierName)
	local idx = rarityIndexByName[tierName]
	if not idx then return end
	if idx >= 3 then SeasonPassHandler.Notify(player, "RareCatch", 1) end
	if idx >= 4 then SeasonPassHandler.Notify(player, "EpicCatch", 1) end
end

local function claimTier(player, tier)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	if typeof(tier) ~= "number" or tier ~= math.floor(tier) then return end
	local def = SeasonConfig.Tiers[tier]
	if not def then return end
	data.SeasonClaimed = data.SeasonClaimed or {}
	local key = tostring(tier) -- datastore-safe key
	if data.SeasonClaimed[key] then return end
	if (data.SeasonXP or 0) < SeasonConfig.ThresholdFor(tier) then return end
	data.SeasonClaimed[key] = true
	PlayerDataManager.GrantCash(data, def.Cash)
	PlayerDataManager.PushUpdate(player)
	SeasonPassHandler.SendState(player)
end

function SeasonPassHandler.Init()
	remotes.SeasonClaim.OnServerEvent:Connect(claimTier)
	-- client asks for state once its UI is listening
	remotes.SeasonState.OnServerEvent:Connect(function(player)
		SeasonPassHandler.SendState(player)
	end)
	print("SeasonPassHandler online")
end

return SeasonPassHandler
