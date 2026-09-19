-- QuestHandler: a Goals board of one-time milestone rewards. Fully data-driven
-- (polls player data), so it needs no hooks into the throw/sell/plot handlers.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local DarrelService = require(ServerScriptService.Modules.DarrelService)
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
-- Counts a SET or an ARRAY: the profile stores some collections either way
-- (OwnedRocks is keyed by id, Pets can be a list). Guessing wrong would just report
-- 0 and leave a goal permanently incomplete, so this handles both shapes.
local function countAny(t)
	if type(t) ~= "table" then return 0 end
	local n = #t
	if n > 0 then return n end
	for _, v in pairs(t) do
		if v ~= false and v ~= nil then n += 1 end
	end
	return n
end
local function mutatedCount(data)
	local n = 0
	for _, e in ipairs(data.Brainrots) do
		if e.Mutation and e.Mutation ~= "" then n += 1 end
	end
	return n
end
local function lifetimeCash(data)
	return math.max(tonumber(data.LifetimeEarned) or 0, tonumber(data.TotalEarned) or 0, tonumber(data.Cash) or 0)
end

-- ordered goal list (id, description, reward, met(data))
-- Every goal now carries cur(data) + target alongside met(). The protocol could
-- previously only say yes/no, so "fill 10 plot spots" transmitted Met = false
-- whether you had 0 or 9 -- there was nothing a progress bar could read.
--
-- met() is KEPT and still authoritative for claiming: cur/target are for display
-- only, so a display bug can never hand out a reward. The two agree by
-- construction (met is cur >= target) but claim never consults cur.
local QUESTS = {
	{ id = "uncommon",  desc = "Catch an Uncommon+ brainrot", reward = 1500,  target = 2,
	  cur = bestRarity,      met = function(d) return bestRarity(d) >= 2 end },
	{ id = "own5",      desc = "Own 5 brainrots",             reward = 4000,  target = 5,
	  cur = totalBrainrots,  met = function(d) return totalBrainrots(d) >= 5 end },
	{ id = "cash25k",   desc = "Reach $25,000 cash",          reward = 6000,  target = 25000,
	  cur = function(d) return d.Cash end,   met = function(d) return d.Cash >= 25000 end },
	{ id = "rare",      desc = "Catch a Rare+ brainrot",      reward = 10000, target = 3,
	  cur = bestRarity,      met = function(d) return bestRarity(d) >= 3 end },
	{ id = "dupe3",     desc = "Own 3 of the same brainrot",  reward = 8000,  target = 3,
	  cur = maxDupe,         met = function(d) return maxDupe(d) >= 3 end },
	{ id = "pads10",    desc = "Fill 10 plot spots",          reward = 18000, target = 10,
	  cur = filledPads,      met = function(d) return filledPads(d) >= 10 end },
	{ id = "epic",      desc = "Catch an Epic+ brainrot",     reward = 30000, target = 4,
	  cur = bestRarity,      met = function(d) return bestRarity(d) >= 4 end },
	{ id = "cash250k",  desc = "Reach $250,000 cash",         reward = 40000, target = 250000,
	  cur = function(d) return d.Cash end,   met = function(d) return d.Cash >= 250000 end },
	{ id = "legendary", desc = "Catch a Legendary+ brainrot", reward = 75000, target = 5,
	  cur = bestRarity,      met = function(d) return bestRarity(d) >= 5 end },
	{ id = "mythic",    desc = "Catch a Mythic+ brainrot",    reward = 200000,target = 6,
	  cur = bestRarity,      met = function(d) return bestRarity(d) >= 6 end },

	-- ==================== EXTENDED LADDER (2026-08-06) ====================
	-- `kind` picks the payout currency: "Cash" (the gold coin pill -- the default, and
	-- what every goal above pays) or "Darrels" (the gem pill, DarrelService's currency,
	-- which until now only the Daily tab ever paid out).
	-- The two are interleaved on purpose so the board alternates a gold payout with a
	-- gem one rather than reading as two separate lists.
	{ id = "rocks5",     desc = "Own 5 different rocks",        reward = 120000,   target = 5,
	  cur = function(d) return countAny(d.OwnedRocks) end,
	  met = function(d) return countAny(d.OwnedRocks) >= 5 end },
	{ id = "mutated",    desc = "Catch a mutated brainrot",     reward = 60,  kind = "Darrels", target = 1,
	  cur = mutatedCount,    met = function(d) return mutatedCount(d) >= 1 end },
	{ id = "own25",      desc = "Own 25 brainrots",             reward = 300000,   target = 25,
	  cur = totalBrainrots,  met = function(d) return totalBrainrots(d) >= 25 end },
	{ id = "discover25", desc = "Discover 25 brainrots",        reward = 75,  kind = "Darrels", target = 25,
	  cur = function(d) return countAny(d.Discovered) end,
	  met = function(d) return countAny(d.Discovered) >= 25 end },
	{ id = "pads16",     desc = "Fill 16 plot spots",           reward = 500000,   target = 16,
	  cur = filledPads,      met = function(d) return filledPads(d) >= 16 end },
	{ id = "secret",     desc = "Catch a Secret+ brainrot",     reward = 750000,   target = 7,
	  cur = bestRarity,      met = function(d) return bestRarity(d) >= 7 end },
	{ id = "cash10m",    desc = "Reach $10,000,000 cash",       reward = 900000,   target = 10000000,
	  cur = function(d) return d.Cash end,   met = function(d) return d.Cash >= 10000000 end },
	{ id = "rebirth1",   desc = "Rebirth for the first time",   reward = 50,  kind = "Darrels", target = 1,
	  cur = function(d) return tonumber(d.Rebirths) or 0 end,
	  met = function(d) return (tonumber(d.Rebirths) or 0) >= 1 end },
	{ id = "rocks10",    desc = "Own 10 different rocks",       reward = 2500000,  target = 10,
	  cur = function(d) return countAny(d.OwnedRocks) end,
	  met = function(d) return countAny(d.OwnedRocks) >= 10 end },
	{ id = "pets3",      desc = "Own 3 pets",                   reward = 80,  kind = "Darrels", target = 3,
	  cur = function(d) return countAny(d.Pets) end,
	  met = function(d) return countAny(d.Pets) >= 3 end },
	{ id = "own50",      desc = "Own 50 brainrots",             reward = 6000000,  target = 50,
	  cur = totalBrainrots,  met = function(d) return totalBrainrots(d) >= 50 end },
	{ id = "key1",       desc = "Earn a Gianluca key",          reward = 40,  kind = "Darrels", target = 1,
	  cur = function(d) return tonumber(d.Keys) or 0 end,
	  met = function(d) return (tonumber(d.Keys) or 0) >= 1 end },
	{ id = "discover75", desc = "Discover 75 brainrots",        reward = 200, kind = "Darrels", target = 75,
	  cur = function(d) return countAny(d.Discovered) end,
	  met = function(d) return countAny(d.Discovered) >= 75 end },
	{ id = "rebirth5",   desc = "Rebirth 5 times",              reward = 250, kind = "Darrels", target = 5,
	  cur = function(d) return tonumber(d.Rebirths) or 0 end,
	  met = function(d) return (tonumber(d.Rebirths) or 0) >= 5 end },
	{ id = "earned1b",   desc = "Earn $1,000,000,000 lifetime", reward = 40000000, target = 1000000000,
	  cur = lifetimeCash,    met = function(d) return lifetimeCash(d) >= 1000000000 end },
}

local QuestHandler = {}

function QuestHandler.SendState(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local list = {}
	for _, q in ipairs(QUESTS) do
		-- Cur is clamped to Target for display so a bar can never overfill (you can
		-- hold $9m against a $25k goal). Met stays exactly as it was -- everything
		-- already reading this payload is unaffected.
		local target = q.target or 1
		local cur = math.clamp(tonumber(q.cur and q.cur(data)) or 0, 0, target)
		list[#list + 1] = {
			Id = q.id, Desc = q.desc, Reward = q.reward,
			-- defaulted, so every existing goal and any client that ignores this field
			-- behaves exactly as before
			RewardKind = q.kind or "Cash",
			Met = q.met(data) == true,
			Claimed = data.Quests[q.id] == true,
			Cur = cur, Target = target,
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
	-- Paid in the goal's own currency. GrantCash is the single funnel for lifetime
	-- earnings; Darrels go through DarrelService, the only authority on that balance,
	-- which pushes its own HUD update.
	if quest.kind == "Darrels" then
		DarrelService.Award(player, quest.reward, "goal:" .. questId)
	else
		PlayerDataManager.GrantCash(data, quest.reward)
	end
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
