-- QuestHandler: a Goals board of one-time milestone rewards. Fully data-driven
-- (polls player data), so it needs no hooks into the throw/sell/plot handlers.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local remotes = ReplicatedStorage.Remotes

local RARITY_ORDER = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6, Secret = 7, God = 8 }
local rarityByName = {}
for _, b in ipairs(BrainrotConfig) do rarityByName[b.Name] = b.Rarity end

-- data helpers
local function bestRarity(data)
	local best = 0
	for _, e in ipairs(data.Brainrots) do
		best = math.max(best, RARITY_ORDER[rarityByName[e.Name] or "Common"] or 1)
	end
	return best
end
local function totalBrainrots(data) return #data.Brainrots end
local function filledPads(data)
	local n = 0
	for _, e in ipairs(data.Brainrots) do if e.PadIndex then n += 1 end end
	return n
end
local function maxDupe(data)
	local counts, m = {}, 0
	for _, e in ipairs(data.Brainrots) do
		counts[e.Name] = (counts[e.Name] or 0) + 1
		m = math.max(m, counts[e.Name])
	end
	return m
end

-- ordered goal list (id, description, reward, met(data))
local QUESTS = {
	{ id = "uncommon",  desc = "Catch an Uncommon+ brainrot", reward = 1500,  met = function(d) return bestRarity(d) >= 2 end },
	{ id = "own5",      desc = "Own 5 brainrots",             reward = 4000,  met = function(d) return totalBrainrots(d) >= 5 end },
	{ id = "cash25k",   desc = "Reach $25,000 cash",          reward = 6000,  met = function(d) return d.Cash >= 25000 end },
	{ id = "rare",      desc = "Catch a Rare+ brainrot",      reward = 10000, met = function(d) return bestRarity(d) >= 3 end },
	{ id = "dupe3",     desc = "Own 3 of the same brainrot",  reward = 8000,  met = function(d) return maxDupe(d) >= 3 end },
	{ id = "pads10",    desc = "Fill 10 plot spots",          reward = 18000, met = function(d) return filledPads(d) >= 10 end },
	{ id = "epic",      desc = "Catch an Epic+ brainrot",     reward = 30000, met = function(d) return bestRarity(d) >= 4 end },
	{ id = "cash250k",  desc = "Reach $250,000 cash",         reward = 40000, met = function(d) return d.Cash >= 250000 end },
	{ id = "legendary", desc = "Catch a Legendary+ brainrot", reward = 75000, met = function(d) return bestRarity(d) >= 5 end },
	{ id = "mythic",    desc = "Catch a Mythic+ brainrot",    reward = 200000,met = function(d) return bestRarity(d) >= 6 end },
}

local QuestHandler = {}

function QuestHandler.SendState(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local list = {}
	for _, q in ipairs(QUESTS) do
		list[#list + 1] = {
			Id = q.id, Desc = q.desc, Reward = q.reward,
			Met = q.met(data) == true,
			Claimed = data.Quests[q.id] == true,
		}
	end
	remotes.QuestState:FireClient(player, list)
end

local function claim(player, questId)
	if typeof(questId) ~= "string" then return end
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local quest
	for _, q in ipairs(QUESTS) do if q.id == questId then quest = q break end end
	if not quest then return end
	if data.Quests[questId] then return end        -- already claimed
	if not quest.met(data) then return end          -- goal not reached
	data.Quests[questId] = true
	PlayerDataManager.GrantCash(data, quest.reward)
	PlayerDataManager.PushUpdate(player)
	QuestHandler.SendState(player)
end

function QuestHandler.Init()
	remotes.QuestClaim.OnServerEvent:Connect(claim)

	local function onJoin(player)
		task.spawn(function()
			local tries = 0
			while not PlayerDataManager.Get(player) and tries < 60 do task.wait(0.1); tries += 1 end
			if PlayerDataManager.Get(player) then
				task.wait(1)
				QuestHandler.SendState(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, p in ipairs(Players:GetPlayers()) do onJoin(p) end

	-- refresh 'Met' flags periodically as players progress
	task.spawn(function()
		while true do
			task.wait(3)
			for _, p in ipairs(Players:GetPlayers()) do QuestHandler.SendState(p) end
		end
	end)

	print("QuestHandler online")
end

return QuestHandler
