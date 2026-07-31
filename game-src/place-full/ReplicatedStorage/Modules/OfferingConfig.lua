-- OfferingConfig: burning a brainrot into the campfire ('Offering') grants a small
-- PERMANENT luck bonus with diminishing returns.
--
-- Why this exists: fusion is the only brainrot sink and it cannot cover Commons
-- (it needs 5 identical name+mutation and stops at the top mutation). Offerings
-- are the sink that scales with the faucet -- every tier can be burned, and the
-- reward is deliberately sub-linear so burning stays worthwhile forever without
-- ever becoming a better luck source than rocks and upgrades.
local M = {}

-- sqrt growth: doubling your offerings does NOT double the bonus
M.PER_OFFERING = 0.010   -- 1% luck per sqrt(offering)
M.MAX_BONUS    = 0.50    -- hard ceiling: +50% luck, reached at 2500 offerings

-- multiplicative luck factor, always >= 1
function M.LuckMult(offerings)
	offerings = tonumber(offerings) or 0
	if offerings <= 0 then return 1 end
	local bonus = math.min(M.PER_OFFERING * math.sqrt(offerings), M.MAX_BONUS)
	return 1 + bonus
end

-- how many more burns until the next visible 1% step (for UI feedback)
function M.NextStepAt(offerings)
	offerings = tonumber(offerings) or 0
	local current = math.floor(M.PER_OFFERING * math.sqrt(offerings) * 100)
	local target = (current + 1) / (M.PER_OFFERING * 100)
	return math.max(1, math.ceil(target * target) - offerings)
end

return M
