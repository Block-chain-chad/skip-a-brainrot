-- TungQuestConfig -- Elder Tung's questline: the on-ramp to World 2.
-- Tung HATES brainrots. He wants TWELVE handed over -- 5 Epic, 5 Legendary, 2 Mythic --
-- YOU choose which ones, and you can give them to him A FEW AT A TIME. Each tier ticks
-- off permanently as it fills; the cellar Key is paid on the hand-over that completes
-- the last one. The server state machine lives in ServerScriptService.Modules.TungQuest
-- (progress is stored in data.TungGiven); this shared config is what the dialogue, the
-- picker panel and the quest tracker read, so the quota can never be stated in two
-- places that disagree.
--
-- HISTORY: briefly three separate per-tier deliveries (2026-08-01), then one
-- all-or-nothing delivery of twelve. Both are gone -- it is incremental now.
local M = {}

M.NpcName = "Tung Tung Tung Sahur"

-- Delivery quota by RARITY tier. These are brainrots you must HOLD and then HAND OVER,
-- not merely a tally of catches.
--
-- That distinction is the whole point: progress used to be a stored counter ticked by
-- the ThrowHandler catch hook, which meant it could read 5/5 while the player had
-- already sold or placed every one of them -- there was nothing left to hand in.
-- Progress is counted live off the player's UNPLACED brainrots, so the number on the
-- tracker is always something they can actually deliver.
M.Requirements = {
	{ Tier = "Epic",      Count = 5 },
	{ Tier = "Legendary", Count = 5 },
	{ Tier = "Mythic",    Count = 2 },
}

M.ByTier = {}
M.Total = 0
for _, r in ipairs(M.Requirements) do
	M.ByTier[r.Tier] = r.Count
	M.Total += r.Count
end

-- NO GIANLUCA KEYS HERE, DELIBERATELY (2026-08-15). Tung pays his OWN cellar Key and
-- nothing else -- that is the KeyAttribute flag further down. There used to be an
-- M.RewardKeys = 1 that TungQuest added to data.Keys (Gianluca's spendable currency),
-- which meant finishing Tung alone satisfied BOTH halves of the cellar lock and made
-- Gianluca's questline optional for getting underground. The hatch is meant to cost one
-- key from EACH questline. The field is deleted rather than set to 0 so it cannot be
-- quietly switched back on.

-- Reward: this flag on player data grants access to the cellar portal. The portal
-- and World 2 do not exist yet -- this flag is the seam they will gate on.
M.RewardFlag = "TungPortalUnlocked"

-- Player attribute the cellar hatch latches on. PER-PLAYER by design: the hatch is
-- rendered client-side (see StarterPlayerScripts.CellarDoorClient) so it opens only
-- for whoever earned it, and a keyholder cannot walk a friend down the ladder.
M.KeyAttribute = "HasCellarKey"

-- Dialogue.
M.Intro  = "Those brainrots... I HATE them. Bring me twelve -- as many at a time as you like -- and I'll open the portal in my cellar."
M.Nag    = "Hand them over whenever you have some. The portal stays shut until my list is done."
M.Ready  = "You're carrying the rest of my list. Show me -- and choose carefully, I keep what you hand over."
M.Done   = "The portal is open. What lies beyond is your problem now."
M.Key    = "Take this. It opens the cellar -- YOUR cellar. It will not turn for anyone else."
-- Shown when the right brainrots exist but are sitting on the player's base, where they
-- cannot be handed over -- the same trap Gianluca's Chim handover warns about.
M.Placed = "Those are on your base, not in your hands. Go and pick them up."
-- The picker panel's own copy.
M.PickTitle = "Hand over to Elder Tung"
M.PickHint  = "Give him as many or as few as you like. Whatever you choose is gone for good."

return M
