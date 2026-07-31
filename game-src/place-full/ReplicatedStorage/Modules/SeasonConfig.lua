-- SeasonConfig: daily-quest pool + season pass tiers. Shared by SeasonPassHandler
-- (progress/awards) and SeasonClient (display). Quests rotate daily (UTC), same
-- 3 for every player. Free track only for now — premium track needs a gamepass id.
local M = {}

-- Event names fired by SeasonPassHandler.Notify
M.QuestPool = {
	{ Id = "Throw20",  Name = "Skip 20 rocks",             Icon = "\u{1FAA8}", Event = "Throw",      Target = 20, XP = 100 },
	{ Id = "Throw50",  Name = "Skip 50 rocks",             Icon = "\u{1FAA8}", Event = "Throw",      Target = 50, XP = 250 },
	{ Id = "Perfect5", Name = "Land 5 PERFECT skips",     Icon = "\u{2B50}", Event = "Perfect",    Target = 5,  XP = 150 },
	{ Id = "Rare3",    Name = "Catch 3 Rare or better",    Icon = "\u{1F48E}", Event = "RareCatch",  Target = 3,  XP = 150 },
	{ Id = "Epic1",    Name = "Catch an Epic or better",   Icon = "\u{1F52E}", Event = "EpicCatch",  Target = 1,  XP = 200 },
	{ Id = "Fuse1",    Name = "Fuse at the campfire",      Icon = "\u{1F525}", Event = "Fuse",       Target = 1,  XP = 200 },
	{ Id = "Daily1",   Name = "Claim the daily reward",    Icon = "\u{1F381}", Event = "DailyClaim", Target = 1,  XP = 50 },
}

M.PoolById = {}
for _, q in ipairs(M.QuestPool) do M.PoolById[q.Id] = q end

-- same 3 quests for everyone on a given UTC day
function M.QuestsForDay(day)
	local rng = Random.new(day)
	local pool = table.clone(M.QuestPool)
	for i = #pool, 2, -1 do
		local j = rng:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	return { pool[1], pool[2], pool[3] }
end

-- 25 tiers, 250 XP each; cash escalates with milestone spikes every 5th tier
M.XP_PER_TIER = 250
M.Tiers = {}
for i = 1, 25 do
	local cash = math.floor(800 * (1.38 ^ (i - 1)) / 100 + 0.5) * 100
	if i % 5 == 0 then cash = cash * 2 end
	M.Tiers[i] = { XP = M.XP_PER_TIER, Cash = cash, Milestone = i % 5 == 0 }
end

-- cumulative XP needed to unlock tier i
function M.ThresholdFor(i)
	return i * M.XP_PER_TIER
end

return M
