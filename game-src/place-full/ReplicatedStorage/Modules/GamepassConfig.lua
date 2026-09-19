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
	-- LIVE since 2026-08-09, the first real id in this file. Effect is wired: IncomeLoop
	-- multiplies its accrual (and the plot billboards) by GamepassService.CashMult.
	{ Key = "Cash2x",      GamepassId = 1941043397, Name = "2x Cash",      Icon = "\u{1F4B0}", Desc = "Double all brainrot income",          RobuxPrice = 199, Effects = { CashMult = 2 } },
	{ Key = "Luck2x",      GamepassId = 1943671354, Name = "2x Luck",      Icon = "\u{1F340}", Desc = "Double your rarity luck on throws",    RobuxPrice = 249, Effects = { LuckMult = 2 } },
	{ Key = "SuperArm",    GamepassId = 1941661376, Name = "Super Arm",    Icon = "\u{1F4AA}", Desc = "Skip rocks much farther",             RobuxPrice = 149, Effects = { PowerMult = 2 } },
	{ Key = "FastCharge",  GamepassId = 1940599374, Name = "Fast Charge",  Icon = "\u{26A1}",  Desc = "Charge your throw meter faster",      RobuxPrice = 99,  Effects = { ChargeMult = 1.75 } },
	{ Key = "AutoCollect", GamepassId = 1941097296, Name = "Auto Collect", Icon = "\u{1F9F2}", Desc = "Automatically collect brainrot cash", RobuxPrice = 299, Effects = { AutoCollect = true } },
	-- AUTO SKIP (2026-08-09). The AUTO button on the throw minigame, which used to be
	-- free for everyone. ClientMain gates it on this pass -- but ONLY once GamepassId
	-- is real: while it sits at 0 the button stays free exactly as it was, because a
	-- gate on a pass nobody can buy is just a removed feature.
	--
	-- It stays a PENALISED mode either way (ThrowHandler's AUTO_LUCK_MULT 0.55 and its
	-- distance tax): this pass sells the convenience of not holding the button, not a
	-- better throw. Deliberate -- the penalty is what stops an overnight session
	-- out-earning someone actually playing, and Robux must not buy round that.
	{ Key = "AutoSkip",    GamepassId = 1941445331, Name = "Auto Skip",    Icon = "\u{1F501}", Desc = "Skip rocks hands-free with the AUTO button", RobuxPrice = 199, Effects = { AutoSkip = true } },
	-- Unlocks the PAID column of the season pass (SeasonConfig.PassTiers). It has
	-- no Effects: it is not a multiplier, it just gates which track a player may
	-- claim from -- SeasonPassHandler checks GamepassService.Owns(player, "SeasonPass").
	-- While GamepassId is 0 nobody owns it, so the paid column stays locked for
	-- everyone and the free track is unaffected.
	-- 699, not the 399 this file used to say: the price was raised on the dashboard and
	-- Roblox charges what the PASS says. Read back from GetProductInfo, not assumed.
	{ Key = "SeasonPass",  GamepassId = 1940137399, Name = "Season Pass",  Icon = "\u{1F3AB}", Desc = "Unlock the paid season reward track", RobuxPrice = 699, Effects = {} },
	-- VIP (effects wired 2026-08-09). CashMult and LuckMult are no longer decorative:
	-- IncomeLoop multiplies its accrual by GamepassService.CashMult and ThrowHandler
	-- folds LuckMult into its rarity roll. Scooter is a feature flag ScooterService
	-- reads to hand out the VIP ride.
	-- 399, down from the 499 this file used to say -- same reason as Season Pass above.
	{ Key = "VIP",         GamepassId = 1940899409, Name = "VIP",          Icon = "\u{2B50}",  Desc = "1.5x cash & luck, plus the electric scooter", RobuxPrice = 399, Effects = { CashMult = 1.5, LuckMult = 1.5, VIP = true, Scooter = true } },
	-- PET FOLLOW SLOTS 6-8 (2026-08-19, owner-supplied ids). One pass per slot.
	-- Effects is EMPTY on purpose: these are not multipliers, they raise a cap --
	-- PetHandler asks GamepassService.Owns() for each key, exactly the way
	-- SeasonPassHandler gates the paid track. Registering them here rather than
	-- checking MarketplaceService inside PetHandler is what buys the ownership
	-- cache, the creator/dev overrides and the buy-it-mid-session refresh for free.
	--
	-- They are sold IN ORDER (the Bag only offers the next locked slot) because a
	-- player's slot count is a COUNT, not a set -- see PetConfig.CapFor. Buying
	-- pass 8 alone off the store page therefore grants slot 6, not slot 8; the
	-- count self-corrects as the others are bought. Prices mirror
	-- PetConfig.SLOT_ROBUX, and Roblox charges what the PASS says, not this file.
	-- NAMED FOR THE DASHBOARD, KEYED FOR THE SLOT. The passes are listed on Roblox
	-- as "Pet slot 1/2/3" and each is described there as "Unlocks an extra pet
	-- slot" -- so a pass grants +1 slot, it is NOT bound to a numbered slot. Extra
	-- slot 1 therefore opens follow slot 6, extra 2 opens 7, extra 3 opens 8. Keys
	-- carry the EXTRA number so they read the same as the store listing; the slot
	-- they open is PetConfig.SLOT_ROBUX's business.
	--
	-- PRICES READ BACK FROM GetProductInfo 2026-08-19, not assumed -- the three
	-- placeholder figures inherited from the old developer-product block (199/349/
	-- 599) were all wrong. Roblox charges what the PASS says; this number only
	-- drives what the UI PRINTS, so a mismatch is the button lying about the price.
	{ Key = "PetSlotExtra1", GamepassId = 1955658646, Name = "Pet Slot 1", Icon = "\u{1F43E}", Desc = "Unlocks an extra pet slot", RobuxPrice = 200, Effects = {} },
	{ Key = "PetSlotExtra2", GamepassId = 1955322608, Name = "Pet Slot 2", Icon = "\u{1F43E}", Desc = "Unlocks an extra pet slot", RobuxPrice = 350, Effects = {} },
	{ Key = "PetSlotExtra3", GamepassId = 1954536668, Name = "Pet Slot 3", Icon = "\u{1F43E}", Desc = "Unlocks an extra pet slot", RobuxPrice = 500, Effects = {} },
	-- 2x BACKPACK (2026-08-23). DOUBLES the brainrot bag's whole cap tier -- the 225
	-- ceiling becomes 450 (and the low base doubles too). Effects is EMPTY on purpose:
	-- like the season/pet-slot passes it raises a CAP, not a multiplier. The wiring:
	-- Main's OnRefreshed hook sets data.BagX2 = GamepassService.Owns(player, "BackpackX2"),
	-- and BagConfig.BrainrotCap doubles when that flag is set (server enforcement AND the
	-- Bag's displayed number). INERT until GamepassId is real: create the pass on the
	-- Creator Dashboard, paste its id below (replacing the 0). RobuxPrice only drives what
	-- a shop UI would PRINT -- Roblox charges what the pass itself says.
	{ Key = "BackpackX2",  GamepassId = 0, Name = "2x Backpack",  Icon = "\u{1F392}", Desc = "Double your brainrot bag space (up to 450)", RobuxPrice = 249, Effects = {} },
}

M.ByKey = {}
for _, g in ipairs(M.List) do M.ByKey[g.Key] = g end

-- id -> config (ids are 0 until you fill them in above)
-- 0 is the "not created yet" sentinel, NOT a real pass id, so it must never
-- match: with several passes still at 0, a lookup of 0 would otherwise return
-- whichever unconfigured pass happens to sit first in the list and grant it.
function M.ByGamepassId(id)
	if type(id) ~= "number" or id <= 0 then return nil end
	for _, g in ipairs(M.List) do
		if g.GamepassId == id then return g end
	end
	return nil
end

return M
