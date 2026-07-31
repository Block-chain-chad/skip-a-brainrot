-- ============================================================================
-- GamepassConfig -- Robux gamepasses (monetization). SHARED so a future shop UI
-- can read names / icons / prices straight from here.
--
-- NOTHING here is surfaced in-game yet: no shop UI, and no purchase prompt fires
-- on its own. This is just the catalog + effect definitions that the server's
-- GamepassService reads.
--
-- >>> TO ACTIVATE A PASS <<<
--   1. Create the pass on the Creator Dashboard:
--        Creations > (this game) > Monetization > Passes > Create a Pass
--   2. Copy its Pass ID.
--   3. Paste it as GamepassId below (replacing the 0).
--   GamepassId == 0 means "not created yet": GamepassService skips the pass
--   entirely (never calls UserOwnsGamePassAsync with a bogus id, never grants its
--   effect) -- same convention as PetConfig.PET_SLOTS_GAMEPASS_ID.
--
-- Effects (read by GamepassService):
--   numbers  -> multipliers, STACKED (product) across all owned passes:
--               CashMult, LuckMult, PowerMult, ChargeMult
--   booleans -> feature flags: AutoCollect, VIP
-- Wiring effects into gameplay is a later step: GamepassService exposes
-- CashMult(player) / LuckMult(player) / HasFlag(player, flag) etc., ready to fold
-- into IncomeLoop / ThrowHandler (which already have LuckMult/IncomeMult seams).
-- ============================================================================
local M = {}

M.List = {
	{ Key = "Cash2x",      GamepassId = 0, Name = "2x Cash",      Icon = "\u{1F4B0}", Desc = "Double all brainrot income",          RobuxPrice = 199, Effects = { CashMult = 2 } },
	{ Key = "Luck2x",      GamepassId = 0, Name = "2x Luck",      Icon = "\u{1F340}", Desc = "Double your rarity luck on throws",    RobuxPrice = 249, Effects = { LuckMult = 2 } },
	{ Key = "SuperArm",    GamepassId = 0, Name = "Super Arm",    Icon = "\u{1F4AA}", Desc = "Skip rocks much farther",             RobuxPrice = 149, Effects = { PowerMult = 2 } },
	{ Key = "FastCharge",  GamepassId = 0, Name = "Fast Charge",  Icon = "\u{26A1}",  Desc = "Charge your throw meter faster",      RobuxPrice = 99,  Effects = { ChargeMult = 1.75 } },
	{ Key = "AutoCollect", GamepassId = 0, Name = "Auto Collect", Icon = "\u{1F9F2}", Desc = "Automatically collect brainrot cash", RobuxPrice = 299, Effects = { AutoCollect = true } },
	{ Key = "VIP",         GamepassId = 0, Name = "VIP",          Icon = "\u{2B50}",  Desc = "1.5x cash & luck, plus a VIP tag",    RobuxPrice = 499, Effects = { CashMult = 1.5, LuckMult = 1.5, VIP = true } },
}

M.ByKey = {}
for _, g in ipairs(M.List) do M.ByKey[g.Key] = g end

-- id -> config (ids are 0 until you fill them in above)
function M.ByGamepassId(id)
	for _, g in ipairs(M.List) do
		if g.GamepassId == id then return g end
	end
	return nil
end

return M
