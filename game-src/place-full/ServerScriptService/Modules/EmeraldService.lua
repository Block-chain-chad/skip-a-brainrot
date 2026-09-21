-- EmeraldService -- the ONLY authority on emerald balance. Award/TrySpend never yield.
local Players = game:GetService("Players")
local PDM = require(script.Parent.PlayerDataManager)
local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")

local M = {}

-- DAILY QUEST PAYOUT: 16 emeralds for the easiest quest up to 40 for the hardest.
--
-- TRIMMED TWICE ON 2026-08-19, both times because the owner still read the gain as
-- high: 30-70 -> 22-52 -> 16-40. For scale, a 3-quest slate paid ~153 emeralds a
-- day when this pass started and pays ~86 now. The weekly pair below tracked both
-- cuts; QuestHandler's lifetime board took its own.
--
-- THE TARGETS GOT EASIER IN THE SAME PASS (owner: "make daily goals a little
-- easier") -- see QUEST_POOL. That is deliberately the opposite direction to the
-- payout, and the two are not in tension: a daily should be something you clear
-- while playing normally rather than a chore you grind, and the emerald faucet is
-- then throttled by what each clear PAYS. Easier to finish, worth less.
--
-- The Michael quest is deliberately untouched.
-- Rewards are DERIVED from a difficulty score rather
-- than typed in one by one, so a new quest only has to declare how hard it is
-- and the payout follows the same curve as everything else.
--
-- Difficulty is 0 (easiest in the pool) to 1 (hardest). The ordering below is
-- the one the previous rewards already implied -- they ran 3/4/5 emeralds on the
-- same easy/medium/hard split -- so this rescales the existing balance rather
-- than re-judging it.
local EMERALDS_MIN, EMERALDS_MAX = 16, 40

-- Takes its endpoints rather than closing over the daily pair: the WEEKLY pool
-- further down pays on this same curve, between different numbers, in two
-- currencies. One curve, three sets of endpoints.
local function rewardFor(min: number, max: number, difficulty: number): number
	local t = math.clamp(difficulty, 0, 1)
	return math.floor(min + (max - min) * t + 0.5)
end

--[[ TARGETS CUT ~40% on 2026-08-19 (owner: "make daily goals a little easier").

IDS ARE UNCHANGED even though the numbers in them have moved, and here that is a
correctness point rather than tidiness: Id is the key in the per-day Claimed map,
so renaming collect50k -> collect30k would leave a player who had ALREADY cleared
it today holding a claim under the old key, and the next Notify would pay them a
second time for the same quest. Frozen ids cost a stale name for one day; renaming
them costs a double payout. Read Target, not the Id.

Difficulty is untouched -- it is a RANKING within the pool, not an absolute, and
the pool's internal ordering did not change when every rung came down together. ]]
local QUEST_POOL = {
	-- passive: the campfire earns this on its own, so it is the floor
	{ Id = "collect50k", Kind = "Collect", Target = 30000,  Difficulty = 0.00, Text = "Collect $30k from the campfire" },
	-- active but short
	{ Id = "throw25",    Kind = "Throw",   Target = 15,     Difficulty = 0.15, Text = "Skip 15 rocks" },
	-- luck-gated: one good throw, but you cannot grind it down reliably. Already the
	-- smallest target a Catch quest can have, so this rung could only get cheaper by
	-- paying less, which it does.
	{ Id = "catchEpic",  Kind = "Catch",   Target = 1,      Difficulty = 0.50, Text = "Catch an Epic or better" },
	-- 5x the passive one
	{ Id = "collect250k",Kind = "Collect", Target = 150000, Difficulty = 0.70, Text = "Collect $150k from the campfire" },
	-- 2.7x the short throw quest -- still the day's time sink, just a shorter one
	{ Id = "throw60",    Kind = "Throw",   Target = 40,     Difficulty = 0.80, Text = "Skip 40 rocks" },
	-- hardest: 2x the Epic catch AND luck-gated on both
	{ Id = "catch3",     Kind = "Catch",   Target = 2,      Difficulty = 1.00, Text = "Catch 2 Epic+ brainrots" },
}

-- Resolved once at load so Notify() and GetDailyState() keep reading q.Reward
-- exactly as before -- neither needed a change.
for _, q in ipairs(QUEST_POOL) do
	q.Reward = rewardFor(EMERALDS_MIN, EMERALDS_MAX, q.Difficulty)
end

--[[ ===================== WEEKLY QUESTS (2026-08-09, user call) =====================

The daily engine on a seven-day period, at targets one sitting cannot clear, and
paying BOTH currencies: emeralds like the dailies, season XP like the season
quests. That pairing is the entire reason to run a weekly on top of a daily -- one
that paid the same thing in a bigger number would just be a slower daily.

They ride the EXISTING Notify call sites (ThrowHandler's Throw and Catch,
IncomeLoop's Collect), so no other handler had to learn anything: a weekly is
counted by the same event that already feeds the daily beside it. A new Kind here
needs a matching EmeraldService.Notify call wherever that thing happens, exactly as
the daily pool does -- there is no auto-discovery.

DIFFICULTY IS JUDGED THE SAME WAY the daily pool judges it: 0 is what the game
hands you for turning up, 1 is what you have to go looking for. The two scales are
not comparable across pools -- a 0.00 weekly is far past a 1.00 daily -- which is
why the endpoints are separate constants rather than a multiplier on the daily
ones.
]]
-- CUT HARD on 2026-08-09 (owner's call: weeklies were paying too many emeralds).
-- Was 100-250 over a 3-quest slate, ~500 emeralds a week. At 30-70 over a 5-quest
-- slate a full clear is ~250, comfortably under the ~700 a week of dailies pays --
-- so the weekly is a bonus layer on the currency rather than the main tap for it.
-- The XP is what makes a weekly worth doing.
-- Bumped 2026-08-18 (40-90 from 30-70, user call) alongside the daily bump above;
-- a full 5-quest clear was then ~325/week, still under the daily faucet.
-- TRIMMED TWICE ON 2026-08-19 with the daily pair (owner: emerald gain is too
-- high): 40-90 -> 30-68 -> 22-52. A full 5-quest clear is ~188/week, so the weekly
-- stays what it has been since the 2026-08-09 cut: a bonus layer on the currency
-- rather than the main tap for it.
--
-- WEEKLY TARGETS ARE NOT PART OF THE EASING. "Make daily goals a little easier"
-- was about the dailies; a weekly is supposed to be the thing you cannot clear in
-- one sitting, and softening it would collapse the distinction the two pools exist
-- to draw.
--
-- THE XP PAIR BELOW IS NOT PART OF THIS CUT. Only emeralds were called too
-- generous, and the two currencies keep separate endpoints precisely so one can be
-- retuned without the other -- moving XP here would quietly reprice the season.
local WEEKLY_EMERALDS_MIN, WEEKLY_EMERALDS_MAX = 22, 52
-- XP is deliberately restrained against the season track. SeasonConfig sizes a
-- season at 12,500 XP / ~26.5 days from the daily quest pool alone, and calls that
-- length the point. A full weekly clear at these endpoints is ~660 XP, about 2.6
-- tiers, which pulls a season in by 2-3 days rather than rewriting it. This pair
-- and the emerald pair above are the dial if that is not the trade you want.
-- Trimmed with the slate going 3 -> 5 (2026-08-09) so the weekly XP total barely
-- moved: 3 x ~220 was ~660, 5 x ~146 is ~730.
local WEEKLY_XP_MIN, WEEKLY_XP_MAX = 90, 200

-- Ids carry a "w" so a weekly can never read as a daily in an audit line, even
-- though the two Claimed maps are separate tables.
-- NINE entries for a FIVE-quest slate (2026-08-09). The count matters: picking 5
-- from 6 gave nearly the same week twice running, and five of nine still leaves
-- four out. It also spans FIVE kinds rather than three, so a week asks you to do
-- several different things instead of the same thing at three sizes -- Perfect and
-- Fuse were added to EmeraldService.Notify's callers for exactly this (ThrowHandler
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
	q.Darrels = rewardFor(WEEKLY_EMERALDS_MIN, WEEKLY_EMERALDS_MAX, q.Difficulty)
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
			warn("[Emeralds] SeasonPassHandler unavailable -- weekly quests will pay emeralds but no XP")
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
	remotes.EmeraldUpdate:FireClient(player, {
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
	-- leave-save still banks the emeralds -- Roblox's retry then grants AGAIN.
	-- The UI pushes are best-effort; tostring() the balance because %d throws on
	-- non-integer-representable values and a corrupted save can put one here.
	local ok, err = pcall(function()
		print(("[Emeralds] +%d -> %s %s (%s)"):format(n, tostring(data.Darrels), player.Name, reason))
		push(player, data); PDM.PushUpdate(player)
	end)
	if not ok then warn("[Emeralds] post-award notify failed: " .. tostring(err)) end
	return true
end

function M.TrySpend(player, n, reason)  -- NO YIELDS between check and deduct
	local data = PDM.Get(player); if not data then return false end
	n = math.floor(n)
	if n <= 0 or n ~= n or data.Darrels < n then return false end
	data.Darrels -= n
	print(("[Emeralds] -%d -> %d %s (%s)"):format(n, data.Darrels, player.Name, reason))
	push(player, data); PDM.PushUpdate(player)
	return true
end

-- PERFECT-THROW BONUS (2026-08-18, user call): a perfect skip pays a couple of
-- emeralds, so being good at the core mechanic feeds the gem currency directly.
-- Called from ThrowHandler's `perfect` branch, which is SERVER-JUDGED and forced
-- false for auto/AFK throws -- so this cannot be macro-farmed, the same guarantee
-- the weekly Perfect quests already ride on.
--
-- CAPPED PER UTC DAY because a perfect lands every few seconds for a skilled
-- player; uncapped, a couple of emeralds each would dwarf the daily+weekly quest
-- faucet this whole module keeps deliberately restrained. The cap resets on the
-- SAME UTC-day boundary as the dailies (utcDay above). Set PERFECT_DAILY_CAP = 0
-- to remove the cap; set PERFECT_EMERALDS = 3 to pay three per perfect.
local PERFECT_EMERALDS = 2
local PERFECT_DAILY_CAP = 60

function M.AwardPerfect(player)
	local data = PDM.Get(player); if not data or data.__noSave then return false end
	if PERFECT_EMERALDS < 1 then return false end
	local d = utcDay()
	-- Own counter, own day-bucket: never reads or writes the quest ledgers, so the
	-- cap and quest progress can never corrupt each other.
	if not data.PerfectPay or data.PerfectPay.Day ~= d then
		data.PerfectPay = { Day = d, Paid = 0 }
	end
	local pp = data.PerfectPay
	local pay = PERFECT_EMERALDS
	if PERFECT_DAILY_CAP > 0 then
		if pp.Paid >= PERFECT_DAILY_CAP then return false end
		pay = math.min(pay, PERFECT_DAILY_CAP - pp.Paid)
	end
	if pay < 1 then return false end
	-- Count it only once the award actually lands, so a failed Award never eats cap.
	if M.Award(player, pay, "perfect") then
		pp.Paid += pay
		return true
	end
	return false
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
			-- the emeralds must land whether or not that module is reachable.
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

	-- Pull path for initial state: EmeraldUpdate's join-time push (above) can race
	-- a client listener that hasn't connected yet, so EggShopClient also INVOKES
	-- this once at startup and once on panel open instead of relying on the push
	-- alone (Task 3 -> Task 7 controller-approved extension). Self-heal instead of
	-- WaitForChild: an unbounded yield here would stall Main's entire synchronous
	-- Init chain if the instance ever went missing.
	local emeraldState = remotes:FindFirstChild("EmeraldState")
	if not emeraldState then
		emeraldState = Instance.new("RemoteFunction")
		emeraldState.Name = "EmeraldState"
		emeraldState.Parent = remotes
	end
	emeraldState.OnServerInvoke = function(player)
		return { Darrels = M.Get(player), Daily = M.GetDailyState(player), Weekly = M.GetWeeklyState(player) }
	end
end

return M
