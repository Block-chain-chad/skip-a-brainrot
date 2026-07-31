-- BrainrotWaves: catchability gate. Since 2026-07-25 this is a thin adapter
-- over SupplySchedule (the Vault & Tide clock) -- kept so its two callers
-- (RarityRoll, IndexClient) never had to change imports, and so the two manual
-- override tables survive as the levers of last resort:
--   FORCE_ON[name] -- always catchable, beats the schedule (never quota-gated)
--   VAULTED[name]  -- never catchable again, beats EVERYTHING incl. FORCE_ON
-- The old quota/spread wave machinery is gone: time-based scheduling replaced
-- it (see docs/specs/2026-07-25-bounded-supply-design.md in the repo).

local SupplySchedule = require(script.Parent.SupplySchedule)
local BrainrotConfig = require(script.Parent.BrainrotConfig)

local M = {}

-- Questline-reward items (BrainrotConfig QuestOnly = true, e.g. Maxwell) are NEVER
-- catchable via a throw -- their only source is the quest grant, which inserts them
-- directly and bypasses the roll. Excluding them here drops them from the roll pool
-- entirely AND makes the Index show them as not-catchable. Static config, so it needs
-- no OverrideKey entry.
M.QUEST_ONLY = {}
for _, e in ipairs(BrainrotConfig) do
	if e.QuestOnly then M.QUEST_ONLY[e.Name] = true end
end

M.FORCE_ON = {
	["Secret Pete"] = true,   -- fixed-odds apex; his gate is LimitedStock's cap
}
M.VAULTED = {}

function M.IsObtainable(name)
	if M.QUEST_ONLY[name] then return false end   -- quest-reward-only: never catchable via throw
	if M.VAULTED[name] then return false end
	if M.FORCE_ON[name] then return true end
	return SupplySchedule.IsObtainable(name)
end

-- Deterministic fingerprint of the override tables, for RarityRoll's pool
-- cache key: an emergency VAULTED flip must invalidate pools NOW, not at the
-- next weekly flip. Sorted, so iteration order can never wobble the string.
function M.OverrideKey()
	local keys = {}
	for n in pairs(M.FORCE_ON) do keys[#keys + 1] = "+" .. n end
	for n in pairs(M.VAULTED) do keys[#keys + 1] = "-" .. n end
	table.sort(keys)
	return table.concat(keys, ";")
end

-- for the Index UI: currently catchable vs total authored
function M.Counts()
	local live = 0
	for _, e in ipairs(BrainrotConfig) do
		if M.IsObtainable(e.Name) then live += 1 end
	end
	return live, #BrainrotConfig
end

return M
