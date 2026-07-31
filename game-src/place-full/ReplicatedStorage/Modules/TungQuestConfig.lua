-- TungQuestConfig -- Tung Tung Tung Sahur's questline: the on-ramp to World 2.
-- Tung HATES brainrots; he wants you to CAPTURE a quota of them (by skip-rock
-- catch), and in return he opens the portal in his cellar. Server state machine
-- lives in ServerScriptService.Modules.TungQuest; this shared config is the data a
-- future dialogue/quest-tracker UI reads. (Server logic only for now -- no UI yet.)
local M = {}

M.NpcName = "Tung Tung Tung Sahur"

-- Capture quota by RARITY tier. "capture" = a throw-catch of that tier made while
-- the quest is active (counted via the ThrowHandler catch hook, which passes the
-- tier name). Edit freely.
M.Requirements = {
	{ Tier = "Epic",      Count = 5 },
	{ Tier = "Legendary", Count = 5 },
	{ Tier = "Mythic",    Count = 2 },
}

-- Reward: this flag on player data grants access to the cellar portal. The portal
-- and World 2 do not exist yet -- this flag is the seam they will gate on.
M.RewardFlag = "TungPortalUnlocked"

-- Flavour text for the future dialogue.
M.Intro = "Those brainrots... I HATE them. Capture them for me and I'll open the portal in my cellar."
M.Nag   = "Keep capturing. The portal stays shut until my list is done."
M.Ready = "That's the lot. Come -- the portal in my cellar is yours to open."
M.Done  = "The portal is open. What lies beyond is your problem now."

M.ByTier = {}
for _, r in ipairs(M.Requirements) do M.ByTier[r.Tier] = r.Count end

return M
