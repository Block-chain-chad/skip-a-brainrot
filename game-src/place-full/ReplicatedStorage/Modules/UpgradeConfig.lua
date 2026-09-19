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

	-- === BAG SPACE (2026-08-20) ==================================================
	-- The two carry limits, sold as ordinary Enzo upgrades so they inherit the whole
	-- existing pipeline for free: MerchantClient renders them, BuyUpgrade charges for
	-- them, and data.Upgrades persists them. TWO SEPARATE PURCHASES on purpose (owner,
	-- 2026-08-20) -- pet space and brainrot space are different problems bought at
	-- different times, and one shared "bag" level would let brainrot pressure pay for
	-- pet room.
	--
	-- Unit = "count" marks these as the odd pair out: PerLevel here is SLOTS ADDED,
	-- not a fraction of a multiplier, so the shop's "+40%" stock line would read
	-- "+500%" for a level of Deep Pockets. EffectText below is what every surface
	-- must print instead -- see its note.
	--
	-- BASES ARE NOT HERE. 25 pets / 150 brainrots live in BagConfig with the counting
	-- rule, so a cap is one addition in one file; these rows only own the STEP and the
	-- price. No Knee: with Knee absent M.Price falls back to MaxLevel, so the single
	-- Growth below applies across the whole ladder (no late-game bend, unlike the four
	-- stat upgrades above -- these are already priced for the mid game at level 0).
	--
	-- Ceilings: pets 25 + 15x5 = 100, brainrots 75 + 6x25 = 225 (450 with the 2x Backpack
	-- gamepass). 2026-08-23 (owner's call): brainrot start lowered 150->75 and the ladder
	-- shortened 14->6 levels so it tops out at 225; pet ladder unchanged. Prices
	-- (BasePrice/Growth) are untouched -- the ladder is just shorter now, so it's a smaller
	-- total sink; retune BasePrice if the first level feels steep at the new low base.
	{ Id = "PetBag",      Name = "Critter Satchel", Icon = "\u{1F43E}", Desc = "Carry more pets",       MaxLevel = 15, BasePrice = 25000, Growth = 1.85, PerLevel = 5,  Unit = "count", Noun = "pet slots" },
	{ Id = "BrainrotBag", Name = "Deep Pockets",    Icon = "\u{1F392}", Desc = "Carry more brainrots", MaxLevel = 6, BasePrice = 60000, Growth = 1.90, PerLevel = 25, Unit = "count", Noun = "bag slots" },
	-- LOCKS (2026-08-20): each level lets you protect one more placed brainrot from
	-- raids -- the walk-up pink-glow lock in PlotFavoriteService. Count-unit like the
	-- two bag rows above, so the shop already prints "+N locks" and charges for it.
	{ Id = "Lock",        Name = "Padlock",         Icon = "\u{1F512}", Desc = "Protect more brainrots from raids", MaxLevel = 10, BasePrice = 750000, Growth = 2.50, PerLevel = 1,  Unit = "count", Noun = "locks" },
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

-- What a level of this upgrade has bought you, as the shop prints it.
--
-- EXISTS BECAUSE PerLevel IS TWO DIFFERENT UNITS. The four stat upgrades store a
-- fraction of a multiplier (0.08 = +8% per level) and the two bag upgrades store a
-- whole COUNT of slots (25 = +25 per level). MerchantClient used to format the
-- stock line as `+%d%%` off PerLevel directly, which reads correctly for the first
-- four and prints "+2500%" for a level of Deep Pockets. Formatting lives here, next
-- to the field it formats, so a new upgrade in a third unit is one row plus one
-- branch rather than a hunt through every surface that draws a card.
function M.EffectText(id, level)
	local u = type(id) == "table" and id or M.ById[id]
	if not u then return "" end
	level = tonumber(level) or 0
	if u.Unit == "count" then
		return ("+%d %s"):format(level * u.PerLevel, u.Noun or "slots")
	end
	return ("+%d%%"):format(math.floor(level * u.PerLevel * 100 + 0.5))
end

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

-- FAVORITE / LOCK CAPACITY: how many placed brainrots a player may lock (the raid-
-- proof pink glow, PlotFavoriteService). ONE free to start so the feature is
-- discoverable, then +PerLevel per Padlock level bought from Enzo.
M.FavoriteBaseCap = 1
function M.FavoriteCap(upgrades)
	local u = M.ById["Lock"]
	local per = (u and u.PerLevel) or 1
	return M.FavoriteBaseCap + M.Level(upgrades, "Lock") * per
end

return M
