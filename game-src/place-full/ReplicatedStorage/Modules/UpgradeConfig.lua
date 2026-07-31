-- Permanent, repeatable upgrades sold by Enzo the Upgrader.
local M = {}

-- ===================== EXTENDED FOR MID/LATE GAME (2026-07-28) =====================
-- The original 4 upgrades were all MaxLevel 8 and topped out around $57M (Income) --
-- trivial next to the extended rock ladder (21 rocks up to VoidHeart $2T). This pass
-- lengthens each ladder into the mid/late game WITHOUT changing any existing level's
-- meaning or price:
--
--   * Levels 0..7 are untouched. BasePrice, Growth and PerLevel are unchanged, so
--     every level a current player already bought costs and does exactly what it did.
--     No saved Upgrades table needs migrating.
--   * A soft "knee" kicks in at the old cap (Knee = 8). At or above the knee the price
--     grows by GrowthLate (a gentler ~2.1-2.3x) instead of the steep early Growth, so
--     the new levels are a real money sink but a "moderate" one -- reachable in a
--     session or two of established play, not a wall. Income (the primary sink) runs
--     longest, to L16 (~$114B to fully max); Luck stops at L12 so total throw-luck
--     inflation stays modest (top Lucky Charm 1.96x, up from 1.64x).
--
-- Early levels stay cheap on purpose (3000-5000): the first upgrades a new player can
-- afford should not gate the opening hour.
M.List = {
	{ Id = "Luck",    Name = "Lucky Charm",     Icon = "\u{1F340}", Desc = "Better rarity rolls",  MaxLevel = 12, BasePrice = 4000, Growth = 3.70, GrowthLate = 2.30, Knee = 8, PerLevel = 0.08 },
	{ Id = "Power",   Name = "Strong Arm",      Icon = "\u{1F4AA}", Desc = "Skip rocks farther",   MaxLevel = 12, BasePrice = 3000, Growth = 3.55, GrowthLate = 2.30, Knee = 8, PerLevel = 0.05 },
	{ Id = "Income",  Name = "Golden Touch",    Icon = "\u{1F4B0}", Desc = "Brainrots earn more",  MaxLevel = 16, BasePrice = 5000, Growth = 3.80, GrowthLate = 2.25, Knee = 8, PerLevel = 0.10 },
	{ Id = "Offline", Name = "Campfire Keeper", Icon = "\u{26FA}",  Desc = "Bank more while away", MaxLevel = 12, BasePrice = 3000, Growth = 3.30, GrowthLate = 2.10, Knee = 8, PerLevel = 0.50 },
}

M.ById = {}
for _, u in ipairs(M.List) do M.ById[u.Id] = u end

function M.Level(upgrades, id)
	return (upgrades and upgrades[id]) or 0
end

-- cost to go from `level` -> level+1, or nil if maxed.
-- Below the knee the steep early Growth applies (so existing level prices are
-- unchanged); at/above the knee a gentler GrowthLate takes over for the mid/late
-- extension. Continuous at the knee: price there equals BasePrice*Growth^Knee.
function M.Price(id, level)
	local u = M.ById[id]
	if not u or level >= u.MaxLevel then return nil end
	local knee = u.Knee or u.MaxLevel
	if level < knee then
		return math.floor(u.BasePrice * (u.Growth ^ level))
	end
	local kneePrice = u.BasePrice * (u.Growth ^ knee)
	local lateGrowth = u.GrowthLate or u.Growth
	return math.floor(kneePrice * (lateGrowth ^ (level - knee)))
end

function M.Mult(upgrades, id)
	local u = M.ById[id]
	if not u then return 1 end
	return 1 + M.Level(upgrades, id) * u.PerLevel
end

function M.IncomeMult(upgrades) return M.Mult(upgrades, "Income") end

-- Offline earnings are deliberately stingy until the player invests in Campfire
-- Keeper. Two separate dials, both driven by that upgrade's level:
--   HOURS -- how long the camp keeps banking after you leave
--   RATE  -- what share of your live income it banks (never the full amount)
-- Level 0 = 30m at 6.5%; level 12 (max) = 12h30m at 66.5%.
M.OfflineBaseHours     = 0.5
M.OfflineHoursPerLevel  = 1
M.OfflineBaseRate       = 0.065
M.OfflineRatePerLevel   = 0.05

function M.OfflineHours(upgrades)
	return M.OfflineBaseHours + M.Level(upgrades, "Offline") * M.OfflineHoursPerLevel
end

function M.OfflineRate(upgrades)
	return M.OfflineBaseRate + M.Level(upgrades, "Offline") * M.OfflineRatePerLevel
end

return M
