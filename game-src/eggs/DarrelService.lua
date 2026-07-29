-- DarrelService -- the ONLY authority on darrel balance. Award/TrySpend never yield.
local Players = game:GetService("Players")
local PDM = require(script.Parent.PlayerDataManager)
local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")

local M = {}

local QUEST_POOL = {
	{ Id = "throw25",   Kind = "Throw",   Target = 25,    Reward = 3, Text = "Skip 25 rocks" },
	{ Id = "throw60",   Kind = "Throw",   Target = 60,    Reward = 5, Text = "Skip 60 rocks" },
	{ Id = "catchEpic", Kind = "Catch",   Target = 1,     Reward = 4, Text = "Catch an Epic or better" },
	{ Id = "catch3",    Kind = "Catch",   Target = 3,     Reward = 5, Text = "Catch 3 Epic+ brainrots" },
	{ Id = "collect50k",Kind = "Collect", Target = 50000, Reward = 3, Text = "Collect $50k from the campfire" },
	{ Id = "collect250k",Kind = "Collect",Target = 250000,Reward = 5, Text = "Collect $250k from the campfire" },
}

local function utcDay() return math.floor(os.time() / 86400) end

-- 3 deterministic picks per UTC day (same slate for everyone; no Math.random at module scope)
local function slateFor(day)
	local rng = Random.new(day * 7919)
	local pool = table.clone(QUEST_POOL)
	local picks = {}
	for _ = 1, 3 do table.insert(picks, table.remove(pool, rng:NextInteger(1, #pool))) end
	return picks
end

local function daily(data)
	local d = utcDay()
	if not data.DarrelDaily or data.DarrelDaily.Day ~= d then
		data.DarrelDaily = { Day = d, Progress = {}, Claimed = {} }
	end
	return data.DarrelDaily
end

local function push(player, data)
	remotes.DarrelUpdate:FireClient(player, { Darrels = data.Darrels, Daily = M.GetDailyState(player) })
end

function M.Get(player)
	local data = PDM.Get(player); return data and data.Darrels or 0
end

function M.Award(player, n, reason)
	local data = PDM.Get(player); if not data then return end
	n = math.floor(n); if n <= 0 then return end
	data.Darrels += n
	print(("[Darrels] +%d -> %d %s (%s)"):format(n, data.Darrels, player.Name, reason))
	push(player, data); PDM.PushUpdate(player)
end

function M.TrySpend(player, n, reason)  -- NO YIELDS between check and deduct
	local data = PDM.Get(player); if not data then return false end
	n = math.floor(n)
	if n <= 0 or n ~= n or data.Darrels < n then return false end
	data.Darrels -= n
	print(("[Darrels] -%d -> %d %s (%s)"):format(n, data.Darrels, player.Name, reason))
	push(player, data); PDM.PushUpdate(player)
	return true
end

function M.Notify(player, kind, n)  -- mirrored beside SeasonPassHandler.Notify call sites
	local data = PDM.Get(player); if not data or data.__noSave then return end
	local dd = daily(data)
	dd.Progress[kind] = (dd.Progress[kind] or 0) + (n or 1)
	for _, q in ipairs(slateFor(dd.Day)) do
		if q.Kind == kind and not dd.Claimed[q.Id] and (dd.Progress[kind] or 0) >= q.Target then
			dd.Claimed[q.Id] = true
			M.Award(player, q.Reward, "daily:" .. q.Id)
		end
	end
end

function M.GetDailyState(player)
	local data = PDM.Get(player); if not data then return nil end
	local dd = daily(data)
	local out = { Day = dd.Day, Quests = {} }
	for _, q in ipairs(slateFor(dd.Day)) do
		table.insert(out.Quests, { Id = q.Id, Text = q.Text, Reward = q.Reward, Target = q.Target,
			Progress = math.min(dd.Progress[q.Kind] or 0, q.Target), Claimed = dd.Claimed[q.Id] == true })
	end
	return out
end

function M.Init()
	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			local data = PDM.Get(player)
			if data then push(player, data) end
		end)
	end)
end

return M
