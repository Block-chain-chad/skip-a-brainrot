-- BagConfig -- HOW MUCH YOU CAN CARRY, and the one place that answers it.
--
-- Two separate bags, and they are NOT the same thing as pet EQUIP slots:
--   * the PET bag   (data.Pets)      -- hatched egg pets you own. Base 25.
--   * the BRAINROT bag (data.Brainrots) -- every brainrot you own. Base 75 (2026-08-23:
--     lowered from 150; upgrade ladder shortened to top out at 225, doubled to 450 by
--     the 2x Backpack gamepass).
--   * equip slots (data.PetSlots)    -- how many of your pets may FOLLOW you at
--     once. That is PetConfig's business (SLOTS_FREE / SLOT_PRICES), not this
--     file's, and the two limits are deliberately independent: a full bag does
--     not stop you re-arranging your loadout.
--
-- SHARED, in ReplicatedStorage, for the same reason PetConfig.StackedMult is:
-- the Bag panel has to print the identical "17 / 25" the server enforces, and a
-- client-side copy of the rule is exactly how the HUD and the server drift apart.
-- Every capacity question in the game goes through this module -- the server for
-- the real refusal, the client only ever to DRAW the number.
--
-- CAPACITY IS AN UPGRADE, bought from Enzo. The ladders live in
-- UpgradeConfig.List (ids "PetBag" and "BrainrotBag", one per bag, deliberately
-- two separate purchases) and the per-level step lives here, next to the base,
-- so "what is my cap" is one addition in one place.
--
-- COUNTING RULE: the brainrot cap counts your WHOLE collection, placed copies
-- included. A brainrot standing on your plot is still yours and still in
-- data.Brainrots -- and the Bag's own header has always counted it that way
-- ("N brainrots . M/12 on plot"). Anything else would make the number the panel
-- prints disagree with the number the server enforces.

local BagConfig = {}

-- === Bases ====================================================================
-- What a brand-new profile carries with zero upgrades bought.
BagConfig.PET_BASE = 25
BagConfig.BRAINROT_BASE = 75

-- === Upgrade ladders ==========================================================
-- Ids MUST match UpgradeConfig.List entries; PER_LEVEL is what one level adds.
-- The MaxLevel that ends each ladder is UpgradeConfig's (15 pets, 6 brainrots), which
-- puts the ceilings at 100 pets and 225 brainrots -- or 450 brainrots for a player who
-- owns the 2x Backpack gamepass (see BrainrotCap's `doubled`).
BagConfig.PET_UPGRADE_ID = "PetBag"
BagConfig.PET_PER_LEVEL = 5
BagConfig.BRAINROT_UPGRADE_ID = "BrainrotBag"
BagConfig.BRAINROT_PER_LEVEL = 25

local function level(upgrades, id)
	if type(upgrades) ~= "table" then return 0 end
	return tonumber(upgrades[id]) or 0
end

-- `upgrades` is data.Upgrades on the server and snapshot.Upgrades on the client
-- -- the same table either way, which is the whole point of this living here.
function BagConfig.PetCap(upgrades)
	return BagConfig.PET_BASE + level(upgrades, BagConfig.PET_UPGRADE_ID) * BagConfig.PET_PER_LEVEL
end

-- `doubled` = the player owns the 2x Backpack gamepass. It DOUBLES the whole tier
-- (base + upgrades), so the 225 ceiling becomes 450 and the low base doubles too. The
-- server passes it from GamepassService (via data.BagX2, set in Main's OnRefreshed
-- hook); the client passes the same flag off the snapshot. Defaults false/nil, so every
-- existing caller keeps its old single-cap behaviour with no change.
function BagConfig.BrainrotCap(upgrades, doubled)
	local base = BagConfig.BRAINROT_BASE + level(upgrades, BagConfig.BRAINROT_UPGRADE_ID) * BagConfig.BRAINROT_PER_LEVEL
	return doubled and base * 2 or base
end

-- === Counting =================================================================
-- Tolerant of a missing/!table field on purpose: these run on the hot grant paths
-- (every catch, every hatch) and a nil inventory must read as "empty bag", never
-- error out and take the catch with it.
function BagConfig.PetCount(data)
	if type(data) ~= "table" or type(data.Pets) ~= "table" then return 0 end
	return #data.Pets
end

function BagConfig.BrainrotCount(data)
	if type(data) ~= "table" or type(data.Brainrots) ~= "table" then return 0 end
	return #data.Brainrots
end

-- Free slots left, never negative. An over-cap bag is a legitimate state -- a
-- quest reward is allowed to overfill (see the note in PlayerDataManager's
-- sanitize) and lowering a cap is never done, but clamping here means every
-- caller can treat this as "how many more fit" without a second max().
function BagConfig.PetSpace(data)
	local upgrades = type(data) == "table" and data.Upgrades or nil
	return math.max(0, BagConfig.PetCap(upgrades) - BagConfig.PetCount(data))
end

function BagConfig.BrainrotSpace(data)
	local upgrades = type(data) == "table" and data.Upgrades or nil
	-- data.BagX2 = owns the 2x Backpack gamepass (server-derived each session). Read here
	-- so EVERY enforcement path (HasBrainrotSpace -> this) doubles the cap automatically.
	local doubled = type(data) == "table" and data.BagX2 == true
	return math.max(0, BagConfig.BrainrotCap(upgrades, doubled) - BagConfig.BrainrotCount(data))
end

-- `n` defaults to 1. Written as "is there room for n more" rather than a bare
-- boolean on the cap so the egg shop's x3/x10 bundles ask the question once
-- instead of looping.
function BagConfig.HasPetSpace(data, n)
	return BagConfig.PetSpace(data) >= (tonumber(n) or 1)
end

function BagConfig.HasBrainrotSpace(data, n)
	return BagConfig.BrainrotSpace(data) >= (tonumber(n) or 1)
end

-- === Player-facing copy =======================================================
-- ONE wording for "your bag is full", so the egg shop, the wheel, the season
-- track and the catch path all say the same thing and all name the same fix.
-- Enzo is the only place capacity is sold, so every message points at him.
function BagConfig.PetFullMessage(data)
	return ("Your pet bag is full (%d/%d) \u{2014} sell a pet in your Bag, or buy more space from Enzo.")
		:format(BagConfig.PetCount(data), BagConfig.PetCap(type(data) == "table" and data.Upgrades or nil))
end

function BagConfig.BrainrotFullMessage(data)
	local doubled = type(data) == "table" and data.BagX2 == true
	return ("Your brainrot bag is full (%d/%d) \u{2014} sell some at the Sell Stall, or buy more space from Enzo.")
		:format(BagConfig.BrainrotCount(data), BagConfig.BrainrotCap(type(data) == "table" and data.Upgrades or nil, doubled))
end

return BagConfig
