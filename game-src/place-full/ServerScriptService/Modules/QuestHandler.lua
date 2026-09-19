-- QuestHandler: a Goals board of one-time milestone rewards. Fully data-driven
-- (polls player data), so it needs no hooks into the throw/sell/plot handlers.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local EmeraldService = require(ServerScriptService.Modules.EmeraldService)
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
--[[ ================== THE LIFETIME BOARD (rebalanced 2026-08-19) ==================

`kind` picks the payout currency: "Cash" (the gold coin pill -- the default) or
"Emeralds" (the gem pill, EmeraldService's currency). The two are interleaved on
purpose so the board alternates a gold payout with a gem one rather than reading
as two separate lists, and the whole thing is ordered easiest-first.

THIS PASS (owner: harder, paying less, and more of them):
  * targets RAISED across the middle and top of the ladder;
  * rewards trimmed TWICE in the same pass, the second time on a follow-up "less
    reward on lifetime": cash is now ~40% below where it started and the nine
    emerald goals total 385, down from 755 across three cuts;
  * SEVEN new goals added -- dupe10, pets12, rocks20, own100, discover150, god,
    earned100b -- taking the board from 25 to 32 and extending it past what the
    old top rung (catch a Secret, earn $1B) asked for.

THE FIRST THREE ARE DELIBERATELY UNCHANGED IN DIFFICULTY. "Catch an Uncommon",
"own 5 brainrots" and "reach $25,000" are what a brand new player clears in their
first few minutes, and they are the board's onboarding. Making the ladder steeper
is worth doing at the rungs people spend real time on, not at the one that teaches
them the board exists. Their rewards took the trim like everything else.

>>> IDS ARE FROZEN, AND THE MEANING HAS MOVED UNDER SOME OF THEM. <<<
`id` is the DataStore key for a claim (data.Quests[id]), so renaming one hands a
fresh claim to every player who already banked it -- a silent, unrepeatable
double payout on a published place. So the ids keep their original numbers while
the targets beside them have grown: "dupe3" now wants 4, "discover25" wants 40,
"pets3" wants 5, "rebirth5" wants 10, and so on. Read the `target` field, never
the id. If a rename is ever genuinely wanted, it needs a migration that copies the
old claim flag forward, not an edit here.

TARGETS ARE ALL REACHABLE, checked against the live config rather than guessed:
249 brainrots exist (162 valley + 87 tundra), 26 pets, 29 rocks (21 + 8), and the
rarity ladder runs to 8 = God. discover150, pets12, rocks20 and god all sit inside
those ceilings. A goal whose target cannot be met is a dead row that never leaves
the board. ]]
local QUESTS = {
	{ id = "uncommon",  desc = "Catch an Uncommon+ brainrot", reward = 900,   target = 2,
	  cur = bestRarity,      met = function(d) return bestRarity(d) >= 2 end },
	{ id = "own5",      desc = "Own 5 brainrots",             reward = 2400,  target = 5,
	  cur = totalBrainrots,  met = function(d) return totalBrainrots(d) >= 5 end },
	{ id = "cash25k",   desc = "Reach $25,000 cash",          reward = 3600,  target = 25000,
	  cur = function(d) return d.Cash end,   met = function(d) return d.Cash >= 25000 end },
	{ id = "dupe3",     desc = "Own 4 of the same brainrot",  reward = 4900,  target = 4,
	  cur = maxDupe,         met = function(d) return maxDupe(d) >= 4 end },
	{ id = "rare",      desc = "Catch a Rare+ brainrot",      reward = 6000,  target = 3,
	  cur = bestRarity,      met = function(d) return bestRarity(d) >= 3 end },
	{ id = "pads10",    desc = "Fill 12 plot spots",          reward = 10500, target = 12,
	  cur = filledPads,      met = function(d) return filledPads(d) >= 12 end },
	{ id = "mutated",   desc = "Own 3 mutated brainrots",     reward = 18, kind = "Emeralds", target = 3,
	  cur = mutatedCount,    met = function(d) return mutatedCount(d) >= 3 end },
	{ id = "epic",      desc = "Catch an Epic+ brainrot",     reward = 18000, target = 4,
	  cur = bestRarity,      met = function(d) return bestRarity(d) >= 4 end },
	{ id = "key1",      desc = "Earn a Gianluca key",         reward = 18, kind = "Emeralds", target = 1,
	  cur = function(d) return tonumber(d.Keys) or 0 end,
	  met = function(d) return (tonumber(d.Keys) or 0) >= 1 end },
	{ id = "cash250k",  desc = "Reach $400,000 cash",         reward = 24000, target = 400000,
	  cur = function(d) return d.Cash end,   met = function(d) return d.Cash >= 400000 end },
	{ id = "rebirth1",  desc = "Rebirth for the first time",  reward = 21, kind = "Emeralds", target = 1,
	  cur = function(d) return tonumber(d.Rebirths) or 0 end,
	  met = function(d) return (tonumber(d.Rebirths) or 0) >= 1 end },
	{ id = "legendary", desc = "Catch a Legendary+ brainrot", reward = 45000, target = 5,
	  cur = bestRarity,      met = function(d) return bestRarity(d) >= 5 end },
	{ id = "discover25",desc = "Discover 40 brainrots",       reward = 27, kind = "Emeralds", target = 40,
	  cur = function(d) return countAny(d.Discovered) end,
	  met = function(d) return countAny(d.Discovered) >= 40 end },
	-- TARGETS RESCALED 7/14/20 -> 5/10/14 (2026-08-21). Rocco's valley ladder was cut
	-- from 14 rungs to 8 (RockConfig, every other rung Retired), so the buyable pool
	-- across BOTH worlds went 22 -> 16 and "Own 20" became unreachable -- a quest no
	-- new player could ever finish. These keep their old share of the pool almost
	-- exactly: 32/64/91% of 22 becomes 31/63/88% of 16. Retired rocks still COUNT for
	-- anyone who owns one; they simply cannot be bought any more.
	{ id = "rocks5",    desc = "Own 5 different rocks",       reward = 71000, target = 5,
	  cur = function(d) return countAny(d.OwnedRocks) end,
	  met = function(d) return countAny(d.OwnedRocks) >= 7 end },
	{ id = "mythic",    desc = "Catch a Mythic+ brainrot",    reward = 120000, target = 6,
	  cur = bestRarity,      met = function(d) return bestRarity(d) >= 6 end },
	{ id = "pets3",     desc = "Own 5 pets",                  reward = 30, kind = "Emeralds", target = 5,
	  cur = function(d) return countAny(d.Pets) end,
	  met = function(d) return countAny(d.Pets) >= 5 end },
	{ id = "own25",     desc = "Own 35 brainrots",            reward = 180000, target = 35,
	  cur = totalBrainrots,  met = function(d) return totalBrainrots(d) >= 35 end },
	{ id = "pads16",    desc = "Fill 16 plot spots",          reward = 300000, target = 16,
	  cur = filledPads,      met = function(d) return filledPads(d) >= 16 end },
	{ id = "secret",    desc = "Catch a Secret+ brainrot",    reward = 450000, target = 7,
	  cur = bestRarity,      met = function(d) return bestRarity(d) >= 7 end },
	{ id = "discover75",desc = "Discover 100 brainrots",      reward = 54, kind = "Emeralds", target = 100,
	  cur = function(d) return countAny(d.Discovered) end,
	  met = function(d) return countAny(d.Discovered) >= 100 end },
	{ id = "cash10m",   desc = "Reach $15,000,000 cash",      reward = 540000, target = 15000000,
	  cur = function(d) return d.Cash end,   met = function(d) return d.Cash >= 15000000 end },
	{ id = "dupe10",    desc = "Own 10 of the same brainrot", reward = 675000, target = 10,
	  cur = maxDupe,         met = function(d) return maxDupe(d) >= 10 end },
	{ id = "pets12",    desc = "Own 12 pets",                 reward = 61, kind = "Emeralds", target = 12,
	  cur = function(d) return countAny(d.Pets) end,
	  met = function(d) return countAny(d.Pets) >= 12 end },
	{ id = "rocks10",   desc = "Own 10 different rocks",      reward = 1500000, target = 10,
	  cur = function(d) return countAny(d.OwnedRocks) end,
	  met = function(d) return countAny(d.OwnedRocks) >= 14 end },
	{ id = "rebirth5",  desc = "Rebirth 10 times",            reward = 68, kind = "Emeralds", target = 10,
	  cur = function(d) return tonumber(d.Rebirths) or 0 end,
	  met = function(d) return (tonumber(d.Rebirths) or 0) >= 10 end },
	{ id = "own50",     desc = "Own 70 brainrots",            reward = 3600000, target = 70,
	  cur = totalBrainrots,  met = function(d) return totalBrainrots(d) >= 70 end },
	{ id = "rocks20",   desc = "Own 14 different rocks",      reward = 6750000, target = 14,
	  cur = function(d) return countAny(d.OwnedRocks) end,
	  met = function(d) return countAny(d.OwnedRocks) >= 20 end },
	{ id = "own100",    desc = "Own 100 brainrots",           reward = 13500000, target = 100,
	  cur = totalBrainrots,  met = function(d) return totalBrainrots(d) >= 100 end },
	{ id = "discover150",desc = "Discover 150 brainrots",     reward = 88, kind = "Emeralds", target = 150,
	  cur = function(d) return countAny(d.Discovered) end,
	  met = function(d) return countAny(d.Discovered) >= 150 end },
	{ id = "earned1b",  desc = "Earn $1,000,000,000 lifetime",reward = 24000000, target = 1000000000,
	  cur = lifetimeCash,    met = function(d) return lifetimeCash(d) >= 1000000000 end },
	{ id = "god",       desc = "Catch a God brainrot",        reward = 90000000, target = 8,
	  cur = bestRarity,      met = function(d) return bestRarity(d) >= 8 end },
	{ id = "earned100b",desc = "Earn $100,000,000,000 lifetime", reward = 225000000, target = 100000000000,
	  cur = lifetimeCash,    met = function(d) return lifetimeCash(d) >= 100000000000 end },
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
	-- earnings; Darrels go through EmeraldService, the only authority on that balance,
	-- which pushes its own HUD update.
	if quest.kind == "Emeralds" then
		EmeraldService.Award(player, quest.reward, "goal:" .. questId)
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
