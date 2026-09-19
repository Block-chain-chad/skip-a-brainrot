-- DarrelService -- the ONLY authority on darrel balance. Award/TrySpend never yield.
local Players = game:GetService("Players")
local PDM = require(script.Parent.PlayerDataManager)
local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")

local M = {}

-- DAILY QUEST PAYOUT (2026-08-06, user call): 20 darrels for the easiest quest
-- up to 50 for the hardest. Rewards are DERIVED from a difficulty score rather
-- than typed in one by one, so a new quest only has to declare how hard it is
-- and the payout follows the same curve as everything else.
--
-- Difficulty is 0 (easiest in the pool) to 1 (hardest). The ordering below is
-- the one the previous rewards already implied -- they ran 3/4/5 darrels on the
-- same easy/medium/hard split -- so this rescales the existing balance rather
-- than re-judging it.
local DARRELS_MIN, DARRELS_MAX = 20, 50

-- Takes its endpoints rather than closing over the daily pair: the WEEKLY pool
-- further down pays on this same curve, between different numbers, in two
-- currencies. One curve, three sets of endpoints.
local function rewardFor(min: number, max: number, difficulty: number): number
	local t = math.clamp(difficulty, 0, 1)
	return math.floor(min + (max - min) * t + 0.5)
end

local QUEST_POOL = {
	-- passive: the campfire earns this on its own, so it is the floor
	{ Id = "collect50k", Kind = "Collect", Target = 50000,  Difficulty = 0.00, Text = "Collect $50k from the campfire" },
	-- active but short
	{ Id = "throw25",    Kind = "Throw",   Target = 25,     Difficulty = 0.15, Text = "Skip 25 rocks" },
	-- luck-gated: one good throw, but you cannot grind it down reliably
	{ Id = "catchEpic",  Kind = "Catch",   Target = 1,      Difficulty = 0.50, Text = "Catch an Epic or better" },
	-- 5x the passive one
	{ Id = "collect250k",Kind = "Collect", Target = 250000, Difficulty = 0.70, Text = "Collect $250k from the campfire" },
	-- 2.4x the short throw quest -- a real time sink
	{ Id = "throw60",    Kind = "Throw",   Target = 60,     Difficulty = 0.80, Text = "Skip 60 rocks" },
	-- hardest: 3x the Epic catch AND luck-gated on every one of them
	{ Id = "catch3",     Kind = "Catch",   Target = 3,      Difficulty = 1.00, Text = "Catch 3 Epic+ brainrots" },
}

-- Resolved once at load so Notify() and GetDailyState() keep reading q.Reward
-- exactly as before -- neither needed a change.
for _, q in ipairs(QUEST_POOL) do
	q.Reward = rewardFor(DARRELS_MIN, DARRELS_MAX, q.Difficulty)
end

--[[ ===================== WEEKLY QUESTS (2026-08-09, user call) =====================

The daily engine on a seven-day period, at targets one sitting cannot clear, and
paying BOTH currencies: darrels like the dailies, season XP like the season
quests. That pairing is the entire reason to run a weekly on top of a daily -- one
that paid the same thing in a bigger number would just be a slower daily.

They ride the EXISTING Notify call sites (ThrowHandler's Throw and Catch,
IncomeLoop's Collect), so no other handler had to learn anything: a weekly is
counted by the same event that already feeds the daily beside it. A new Kind here
needs a matching DarrelService.Notify call wherever that thing happens, exactly as
the daily pool does -- there is no auto-discovery.

DIFFICULTY IS JUDGED THE SAME WAY the daily pool judges it: 0 is what the game
hands you for turning up, 1 is what you have to go looking for. The two scales are
not comparable across pools -- a 0.00 weekly is far past a 1.00 daily -- which is
why the endpoints are separate constants rather than a multiplier on the daily
ones.
]]
-- CUT HARD on 2026-08-09 (owner's call: weeklies were paying too many darrels).
-- Was 100-250 over a 3-quest slate, ~500 darrels a week. At 30-70 over a 5-quest
-- slate a full clear is ~250, comfortably under the ~700 a week of dailies pays --
-- so the weekly is a bonus layer on the currency rather than the main tap for it.
-- The XP is what makes a weekly worth doing.
local WEEKLY_DARRELS_MIN, WEEKLY_DARRELS_MAX = 30, 70
-- XP is deliberately restrained against the season track. SeasonConfig sizes a
-- season at 12,500 XP / ~26.5 days from the daily quest pool alone, and calls that
-- length the point. A full weekly clear at these endpoints is ~660 XP, about 2.6
-- tiers, which pulls a season in by 2-3 days rather than rewriting it. This pair
-- and the darrel pair above are the dial if that is not the trade you want.
-- Trimmed with the slate going 3 -> 5 (2026-08-09) so the weekly XP total barely
-- moved: 3 x ~220 was ~660, 5 x ~146 is ~730.
local WEEKLY_XP_MIN, WEEKLY_XP_MAX = 90, 200

-- Ids carry a "w" so a weekly can never read as a daily in an audit line, even
-- though the two Claimed maps are separate tables.
-- NINE entries for a FIVE-quest slate (2026-08-09). The count matters: picking 5
-- from 6 gave nearly the same week twice running, and five of nine still leaves
-- four out. It also spans FIVE kinds rather than three, so a week asks you to do
-- several different things instead of the same thing at three sizes -- Perfect and
-- Fuse were added to DarrelService.Notify's callers for exactly this (ThrowHandler
-- and FusionHandler, beside the SeasonPassHandler.Notify calls already there).
local WEEKLY_POOL = {
	-- the campfire earns most of this on its own over seven days, so it is the floor
	{ Id = "wCollect1m", Kind = "Collect", Target = 1000000, Difficulty = 0.00, Text = "Collect $1M from the campfire" },
	-- 2.5x the hardest daily throw: a couple of real sessions
	{ Id = "wThrow150",  Kind = "Throw",   Target = 150,     Difficulty = 0.15, Text = "Skip 150 rocks" },
	-- skill, not time: an auto-skip cannot land one of these (ThrowHandler refuses a
	-- perfect on any auto throw), so these two are the quests AFK cannot touch
	{ Id = "wPerfect15", Kind = "Perfect", Target = 15,      Difficulty = 0.30, Text = "Land 15 PERFECT skips" },
	{ Id = "wFuse3",     Kind = "Fuse",    Target = 3,       Difficulty = 0.40, Text = "Fuse 3 times at the campfire" },
	-- luck-gated all the way up, like the daily Epic quests
	{ Id = "wCatch10",   Kind = "Catch",   Target = 10,      Difficulty = 0.50, Text = "Catch 10 Epic+ brainrots" },
	{ Id = "wCollect5m", Kind = "Collect", Target = 5000000, Difficulty = 0.65, Text = "Collect $5M from the campfire" },
	{ Id = "wPerfect40", Kind = "Perfect", Target = 40,      Difficulty = 0.75, Text = "Land 40 PERFECT skips" },
	{ Id = "wThrow400",  Kind = "Throw",   Target = 400,     Difficulty = 0.85, Text = "Skip 400 rocks" },
	-- hardest in the pool: 2.5x the Epic catch weekly AND luck-gated on every one
	{ Id = "wCatch25",   Kind = "Catch",   Target = 25,      Difficulty = 1.00, Text = "Catch 25 Epic+ brainrots" },
}

for _, q in ipairs(WEEKLY_POOL) do
	q.Darrels = rewardFor(WEEKLY_DARRELS_MIN, WEEKLY_DARRELS_MAX, q.Difficulty)
	q.XP = rewardFor(WEEKLY_XP_MIN, WEEKLY_XP_MAX, q.Difficulty)
end

-- LAZY, and it has to be. SeasonPassHandler requires THIS module at its own load
-- (for Award), so requiring it back at module scope is a cycle that takes the
-- server boot down with it. By the time a weekly completes, both modules are long
-- since loaded and require() is a cache hit. Cached as `false` on failure so a
-- missing module costs a pcall once, not once per event.
local seasonMod = nil
local function season()
	if seasonMod == nil then
		local ok, mod = pcall(require, script.Parent.SeasonPassHandler)
		seasonMod = (ok and type(mod) == "table") and mod or false
		if not seasonMod then
			warn("[Darrels] SeasonPassHandler unavailable -- weekly quests will pay darrels but no XP")
		end
	end
	return seasonMod or nil
end

--[[ THE TWO SCHEDULES, both on the wall clock in UTC (os.time() is UTC in Roblox,
so the server and every client agree without a timezone anywhere):

  DAILY   resets at 00:00 UTC every day
  WEEKLY  resets at 00:00 UTC every MONDAY

Both states carry an `EndsAt` in unix seconds, so the panel's countdown reads the
server's own boundary instead of recomputing this arithmetic and drifting from it.
]]
local DAY_SECONDS = 86400
local function utcDay() return math.floor(os.time() / DAY_SECONDS) end
local function dayEndsAt(day) return (day + 1) * DAY_SECONDS end

-- WEEKS START MONDAY 00:00 UTC. The unix epoch is a THURSDAY, so the obvious
-- os.time() // 604800 would roll a week's slate over on Thursday morning; the
-- four-day shift puts the boundary on Monday. Same UTC basis as utcDay, so the two
-- periods can never disagree about when "now" is.
local WEEK_SECONDS = 7 * 86400
local WEEK_SHIFT = 4 * 86400
local function utcWeek() return math.floor((os.time() - WEEK_SHIFT) / WEEK_SECONDS) end
-- Unix seconds at which `week` rolls over. Sent to the client so its countdown
-- reads off the server's own boundary instead of recomputing this shift.
local function weekEndsAt(week) return (week + 1) * WEEK_SECONDS + WEEK_SHIFT end

-- 3 deterministic picks per UTC day (same slate for everyone; no Math.random at module scope)
local function slateFor(day)
	local rng = Random.new(day * 7919)
	local pool = table.clone(QUEST_POOL)
	local picks = {}
	for _ = 1, 3 do table.insert(picks, table.remove(pool, rng:NextInteger(1, #pool))) end
	return picks
end

-- Same idea, DIFFERENT multiplier. Sharing the daily seed would correlate the two
-- draws, and a week whose weekly quests are the same things as that day's dailies
-- is a week with nothing extra in it.
--
-- FIVE picks since 2026-08-09 (owner's call), which is also exactly what the panel
-- shows without scrolling -- GoalsPanel's VISIBLE_ROWS is 5.
local WEEKLY_SLATE_SIZE = 5
local function weeklySlateFor(week)
	local rng = Random.new(week * 104729 + 17)
	local pool = table.clone(WEEKLY_POOL)
	local picks = {}
	for _ = 1, math.min(WEEKLY_SLATE_SIZE, #pool) do
		table.insert(picks, table.remove(pool, rng:NextInteger(1, #pool)))
	end
	return picks
end

local function daily(data)
	local d = utcDay()
	if not data.DarrelDaily or data.DarrelDaily.Day ~= d then
		data.DarrelDaily = { Day = d, Progress = {}, Claimed = {} }
	end
	return data.DarrelDaily
end

local function weekly(data)
	local w = utcWeek()
	if not data.DarrelWeekly or data.DarrelWeekly.Week ~= w then
		data.DarrelWeekly = { Week = w, Progress = {}, Claimed = {} }
	end
	return data.DarrelWeekly
end

local function push(player, data)
	remotes.DarrelUpdate:FireClient(player, {
		Darrels = data.Darrels,
		Daily = M.GetDailyState(player),
		-- Additive: every existing reader takes the fields it knows by name, so a
		-- client built before the weekly slate existed is unaffected by it.
		Weekly = M.GetWeeklyState(player),
	})
end

function M.Get(player)
	local data = PDM.Get(player); return data and data.Darrels or 0
end

function M.Award(player, n, reason)
	local data = PDM.Get(player); if not data then return false end
	if type(n) ~= "number" then return false end
	n = math.floor(n); if n < 1 or n ~= n or n == math.huge then return false end
	data.Darrels += n
	-- MONEY INVARIANT (Robux receipts): nothing after the mutation above may throw.
	-- A throw here would skip ProductRegistry's ReceiptLog insert while the
	-- leave-save still banks the darrels -- Roblox's retry then grants AGAIN.
	-- The UI pushes are best-effort; tostring() the balance because %d throws on
	-- non-integer-representable values and a corrupted save can put one here.
	local ok, err = pcall(function()
		print(("[Darrels] +%d -> %s %s (%s)"):format(n, tostring(data.Darrels), player.Name, reason))
		push(player, data); PDM.PushUpdate(player)
	end)
	if not ok then warn("[Darrels] post-award notify failed: " .. tostring(err)) end
	return true
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

	-- ONE EVENT, TWO LEDGERS. Weekly progress is counted separately rather than
	-- derived from the daily counter: that one is wiped at every UTC midnight, so a
	-- weekly total read off it would reset six times a week and "Skip 400 rocks"
	-- could never be finished at all.
	--
	-- Auto-claimed on the spot, exactly like the daily above -- there is no weekly
	-- claim remote and the client never sees Progress >= Target with Claimed false.
	local ww = weekly(data)
	ww.Progress[kind] = (ww.Progress[kind] or 0) + (n or 1)
	for _, q in ipairs(weeklySlateFor(ww.Week)) do
		if q.Kind == kind and not ww.Claimed[q.Id] and (ww.Progress[kind] or 0) >= q.Target then
			ww.Claimed[q.Id] = true
			local reason = "weekly:" .. q.Id
			M.Award(player, q.Darrels, reason)
			-- XP second and guarded: data.SeasonXP belongs to SeasonPassHandler, and
			-- the darrels must land whether or not that module is reachable.
			local sp = season()
			if sp and sp.AwardXP then
				pcall(sp.AwardXP, player, q.XP, reason)
			end
		end
	end
end

function M.GetDailyState(player)
	local data = PDM.Get(player); if not data then return nil end
	local dd = daily(data)
	local out = { Day = dd.Day, EndsAt = dayEndsAt(dd.Day), Quests = {} }
	for _, q in ipairs(slateFor(dd.Day)) do
		-- Kind rides along so the panel can format a Collect target as money rather
		-- than as a seven-digit integer. Display only; nothing branches on it here.
		table.insert(out.Quests, { Id = q.Id, Kind = q.Kind, Text = q.Text, Reward = q.Reward, Target = q.Target,
			Progress = math.min(dd.Progress[q.Kind] or 0, q.Target), Claimed = dd.Claimed[q.Id] == true })
	end
	return out
end

-- Shaped like GetDailyState so the panel's row renderer barely has to care which
-- one it is holding, with two additions: the reward is split into its two
-- currencies (Darrels / XP -- "Reward" would have had to mean one of them), and
-- EndsAt carries the week boundary so the client's countdown does not recompute
-- the Monday shift and drift from the server that owns it.
function M.GetWeeklyState(player)
	local data = PDM.Get(player); if not data then return nil end
	local ww = weekly(data)
	local out = { Week = ww.Week, EndsAt = weekEndsAt(ww.Week), Quests = {} }
	for _, q in ipairs(weeklySlateFor(ww.Week)) do
		table.insert(out.Quests, { Id = q.Id, Kind = q.Kind, Text = q.Text,
			Darrels = q.Darrels, XP = q.XP, Target = q.Target,
			Progress = math.min(ww.Progress[q.Kind] or 0, q.Target), Claimed = ww.Claimed[q.Id] == true })
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

	-- Pull path for initial state: DarrelUpdate's join-time push (above) can race
	-- a client listener that hasn't connected yet, so EggShopClient also INVOKES
	-- this once at startup and once on panel open instead of relying on the push
	-- alone (Task 3 -> Task 7 controller-approved extension). Self-heal instead of
	-- WaitForChild: an unbounded yield here would stall Main's entire synchronous
	-- Init chain if the instance ever went missing.
	local darrelState = remotes:FindFirstChild("DarrelState")
	if not darrelState then
		darrelState = Instance.new("RemoteFunction")
		darrelState.Name = "DarrelState"
		darrelState.Parent = remotes
	end
	darrelState.OnServerInvoke = function(player)
		return { Darrels = M.Get(player), Daily = M.GetDailyState(player), Weekly = M.GetWeeklyState(player) }
	end
end

return M
