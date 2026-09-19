--!strict
--------------------------------------------------------------------------------
-- CharmConfig -- the Charm Codex data contract
--------------------------------------------------------------------------------
--
-- ##########################################################################
-- ##  PLACEHOLDER CONTENT. THE REAL CHARMS DO NOT EXIST YET.              ##
-- ##########################################################################
--
-- Every entry below was transcribed from the 2026-08-07 design video (a
-- layout mock) and from the `charms-final.md` spec. The user has said three
-- separate times that the charms are NOT designed yet. Treat every name,
-- number and line of copy here as a stand-in whose only job is to give the
-- panel something real-shaped to render.
--
-- EDITING THIS FILE IS THE ENTIRE JOB OF CHANGING THE ROSTER.
--   The panel derives everything from this module: the grid, the category
--   tabs, the "N IN THE SET" kicker, the "N SHOWN" counter, and the
--   combination maths. Add a 17th charm and the panel shows 17 and recomputes
--   C(17,3) = 680 by itself. Delete four and it shows 12. No UI file should
--   ever contain a charm name, a roster count, a grid dimension, or the
--   number 560. If you are about to type one of those into a UI script, the
--   number belongs here instead and you should reach it through a helper at
--   the bottom of this file.
--
-- NOTHING HERE IS WIRED TO ANYTHING.
--   No charm changes a stat. There is no charm system: no ownership, no
--   equipping, no server resolution, no save data, no remotes. `Config` and
--   `Hook` are DOCUMENTATION strings -- they describe what an implementation
--   would have to do, and the detail panel renders them verbatim as text.
--   Nothing parses or executes them. Building the charm system is out of
--   scope for this task and for the panel tasks that follow it.
--
--------------------------------------------------------------------------------
-- NAMING COLLISION RULING: this system keeps the word "charm".
--------------------------------------------------------------------------------
--
-- The game already contains "charm" in two unrelated places. Both were read
-- in full before choosing:
--
--   1. UpgradeConfig.List[1] = { Id = "Luck", Name = "Lucky Charm", ... }
--      "Lucky Charm" is the DISPLAY NAME of upgrade #1, sold by Enzo the
--      Upgrader. It is a 12-level integer stat upgrade stored as
--      data.Upgrades.Luck. It is not an item, is not ownable, and has no
--      instance identity. BackpackPanel's own header note says exactly this.
--
--   2. MerchantConfig "CharmSeller" -- NPC Lil Miss, Kind = "Charm", stalls
--      CharmStall (Valley) and TundraCharmStall (Tundra), blurb "Little
--      trinkets. They bring their own luck.", four lines of dialogue about
--      collecting charms. PLUS BackpackPanel's "Charms" backpack tab, which
--      today ships as an EMPTY-STATE branch only because -- in its own words
--      -- there is "NO discrete owned charm data shape anywhere".
--
-- RULING: keep "charm". This system IS #2. The Charms backpack tab and Lil
-- Miss's charm stall are already-built, already-shipped, player-facing
-- scaffolding waiting for exactly this data, and the design video titles the
-- panel "CHARM CODEX". Renaming the system to "talisman" would strand a
-- shipped tab, a merchant, two world stalls and four lines of NPC dialogue in
-- order to rename the thing that was never the conflict.
--
-- The real collision is #1, and it is one string in one file. If it ever
-- bites, the correct fix is at THAT end: rename the Luck upgrade's display
-- name in UpgradeConfig to something Enzo-flavoured. That is a deliberate,
-- separate, player-facing change and is deliberately NOT done here.
--
--   => "Lucky Charm" (an upgrade LEVEL) and the charms below (collectible
--      ITEMS) are separate, unrelated systems. Do not "unify" them. Nothing
--      in this file reads or writes data.Upgrades.
--
-- The video's eyebrow reads "TALISMANS", not "CHARMS". That is flavour, not a
-- rename -- the same header block says "CHARM CODEX" one line below it. It is
-- preserved as Display.Kicker so the panel can render it without any UI file
-- hard-coding the word.
--
-- SECOND COLLISION, found while checking the first and worth knowing: the
-- spec's charm "Strong Arm" collides EXACTLY with UpgradeConfig.List[2].Name
-- ("Strong Arm", the Power upgrade). The design video already fixes it by
-- renaming that charm "The Ironbound Arm". Every video rename is preserved
-- below, and WasCalled keeps the old name the detail panel prints beside the
-- Id.
--
--------------------------------------------------------------------------------
-- PROVENANCE -- what is transcribed design vs. what is invented placeholder
--------------------------------------------------------------------------------
--
--   * All 16 Names, Categories, Effect labels and Sigils come from the video
--     grid. The array order below IS the video's grid order (row-major), and
--     the detail panel's "01/16" counter is that 1-based position.
--   * 7 of the 16 have a fully-populated detail panel somewhere in the video
--     (indices 1, 2, 3, 5, 6, 7, 8). For those, Flavour / Gain / Trade /
--     Config / Source / Hook / Note are transcribed VERBATIM from the frames.
--   * The other 9 take Gain / Config / Source / Hook / Note from
--     charms-final.md, and have an INVENTED Flavour line. Each is tagged
--     `-- flavour: INVENTED` on its own line, and all 9 ids are listed in
--     M.InventedFlavour at the bottom so this is machine-checkable too.
--   * NO Trade was ever invented. A downside is a balance decision and the
--     charms are not designed yet, so where the video did not show a TRADE
--     row, Trade is nil and the panel omits the row entirely.
--   * Sigil is a pure function of Category in the design (see
--     M.SigilForCategory). That was not stated anywhere -- it was derived from
--     the grid and holds for all 16. It is stored per-charm anyway, because
--     the type requires it and because a future roster may want an exception.
--
-- ENCODING: every non-ASCII character in a string value is written as a
-- \u{...} escape rather than pasted in raw. This is the convention
-- MerchantConfig and LuckHUDClient already use, and it makes the file immune
-- to a write path that mangles UTF-8. Comments are ASCII-only for the same
-- reason. The five that appear below, so you can keep the style when you
-- replace these entries:
--
--     \u{00D7}  x   multiplication sign      "Mutation chance x2"
--     \u{2212}  -   true minus sign          "Sell value -10%"
--     \u{00B7}  .   middle dot separator     "Shop . in-game cash"
--     \u{2192}  ->  right arrow              "40 -> 54"
--     \u{2014}  --  em dash
--
-- Plain ASCII is fine too if you would rather not bother -- nothing depends
-- on the typography. It is here only because the design video uses it.
--------------------------------------------------------------------------------

local M = {}

--------------------------------------------------------------------------------
-- TYPES
--------------------------------------------------------------------------------

export type Charm = {
	Id: string,            -- "CHARM_GOLDEN_YOLK"
	Name: string,          -- "The Gilded Yolk"
	WasCalled: string?,    -- "Golden Yolk"
	Category: string,      -- must appear in M.Categories
	Effect: string,        -- short grid label, e.g. "EGG LUCK"
	Flavour: string,       -- the italic line
	Gain: string,          -- GAIN row
	Trade: string?,        -- TRADE row; nil = no downside, omit the row entirely
	TradeProposed: boolean?,  -- must be non-nil whenever Trade is non-nil
	Config: string,        -- CONFIG row, e.g. "EggTailBias = 0.5, SellAdd = -0.10"
	Source: string,        -- SOURCE row
	Hook: string,          -- HOOK row
	Note: string?,         -- the blue note box
	Locked: boolean?,      -- true for the four Round C charms
	Sigil: string,         -- "square" | "diamond" | "circle" | "ring"
}

export type Category = {
	Key: string,           -- matches Charm.Category, or "ALL"
	Label: string,         -- tab label exactly as the video renders it
	All: boolean?,         -- true only for the ALL pseudo-category
}

export type Slot = {
	Index: number,
	Unlock: string,        -- the small caps line under the slot
	Locked: boolean?,      -- true = not earnable, excluded from the slot count
}

--------------------------------------------------------------------------------
-- CATEGORIES -- array order IS the video's tab order.
-- "ALL" is a filter key, not a charm category: no charm carries it.
--------------------------------------------------------------------------------

M.Categories = {
	{ Key = "ALL",       Label = "ALL", All = true },
	{ Key = "MILESTONE", Label = "MILESTONE" },
	{ Key = "QUEST",     Label = "QUEST" },
	{ Key = "WORLD",     Label = "WORLD" },
	{ Key = "SEASON",    Label = "SEASON" },
} :: { Category }

-- Observed 1:1 mapping in the video grid. Kept as data so a future editor can
-- see the convention rather than having to reverse it out of 16 entries again.
M.SigilForCategory = {
	MILESTONE = "diamond",
	QUEST     = "circle",
	WORLD     = "square",
	SEASON    = "ring",
}

--------------------------------------------------------------------------------
-- SLOTS -- exactly as the video's loadout strip shows them.
-- The slot COUNT is never written down anywhere else. Anything that needs
-- "3" calls M.UnlockableSlotCount(); anything that needs "4" uses #M.Slots.
--------------------------------------------------------------------------------

-- 2026-08-11 (user decision): the same 3-free / 5-premium shape as pets
-- (PetConfig.SLOTS_FREE / SLOTS_PREMIUM) -- three earnable slots, and the
-- gamepass adds slots 4 AND 5. The pass itself is still the owner's call
-- (id undecided), so both stay Locked until it exists.
M.Slots = {
	{ Index = 1, Unlock = "FIRST RARE CATCH" },
	{ Index = 2, Unlock = "REBIRTH 1" },
	{ Index = 3, Unlock = "FIRST MYTHIC CATCH" },
	{ Index = 4, Unlock = "GAMEPASS \u{00B7} +2 SLOTS", Locked = true },
	{ Index = 5, Unlock = "GAMEPASS \u{00B7} +2 SLOTS", Locked = true },
} :: { Slot }

--------------------------------------------------------------------------------
-- THE ROSTER
--
-- Array order = video grid order (row-major) = display order = the "NN/16"
-- counter in the detail panel. Reordering this array reorders the grid; no
-- index is stored on the entries, so reordering can never desync anything.
--------------------------------------------------------------------------------

M.Charms = {

	-- 01 -------------------------------------------------- video panel, verbatim
	{
		Id = "CHARM_GOLDEN_YOLK",
		Name = "The Gilded Yolk",
		WasCalled = "Golden Yolk",
		Category = "WORLD",
		Effect = "EGG LUCK",
		Flavour = "Split from a clutch that never hatched. What it draws out, it takes back at the counter.",
		Gain = "Egg hatch weights bias \u{00D7}1.5 toward the rarest entry in the table, re-normalised so the list still sums to 100.",
		Trade = "Sell value \u{2212}10%.",
		TradeProposed = true,
		Config = "EggTailBias = 0.5, SellAdd = -0.10",
		Source = "Shop \u{00B7} in-game cash",
		Hook = "EggHandler:76-100 \u{2192} EggConfig.WORLDS[w].Eggs[i].Table",
		Note = "Must re-weight toward the tail, not multiply flat \u{2014} a flat multiplier breaks EggConfig.Validate and the published-odds guarantee. Show the modified odds client-side.",
		Sigil = "square",
	},

	-- 02 -------------------------------------------------- video panel, verbatim
	{
		Id = "CHARM_HOT_STREAK",
		Name = "Ember Cadence",
		WasCalled = "Hot Streak",
		Category = "MILESTONE",
		Effect = "GREEN WINDOW",
		Flavour = "Rhythm is a kind of fire. It dies the moment you look away.",
		Gain = "+8% power per consecutive perfect release, to a cap of +40%. Resets on a miss.",
		-- No TRADE row in the video, by an explicit design note. Left nil.
		Config = "PerfectChainAdd = 0.08, PerfectChainCap = 0.40",
		Source = "First Legendary catch",
		Hook = "ThrowHandler:534 \u{2014} per-session",
		Note = "Left clean on purpose. It already asks something of the player, so a downside would tax skill twice.",
		Sigil = "diamond",
	},

	-- 03 -------------------------------------------------- video panel, verbatim
	{
		Id = "CHARM_MERCHANTS_KNOT",
		Name = "The Ledger Knot",
		WasCalled = "Merchant's Knot",
		Category = "WORLD",
		Effect = "SELL VALUE",
		Flavour = "Tied by a merchant who counted every coin twice and trusted neither count.",
		Gain = "Sell value +35%. SELL_MULTIPLIER 40 \u{2192} 54.",
		Trade = "Placed income \u{2212}10%.",
		TradeProposed = true,
		Config = "SellAdd = 0.35, IncomeAdd = -0.10",
		Source = "Shop \u{00B7} in-game cash",
		Hook = "SellHandler:35",
		Note = "Deliberate mirror of The Miser's Purse \u{2014} sell high and earn slow, or earn high and sell cheap. Running both cancels out, which is the point.",
		Sigil = "square",
	},

	-- 04 ------------------------------------- no video panel; spec + invented line
	{
		Id = "CHARM_SCHOLARS_SEAL",
		Name = "The Vellum Seal",
		WasCalled = "Scholar's Seal",
		Category = "QUEST",
		Effect = "QUEST XP",
		Flavour = "Every lesson was written down. Not all of them were meant for you.",  -- flavour: INVENTED
		Gain = "Quest XP +50%.",
		Config = "QuestXpAdd = 0.50",
		Source = "Maxwell quest",
		Hook = "QuestHandler:78 \u{2192} SeasonXP",
		Sigil = "circle",
	},

	-- 05 -------------------------------------------------- video panel, verbatim
	{
		Id = "CHARM_COIN_PURSE",
		Name = "The Miser's Purse",
		WasCalled = "Coin Purse",
		Category = "MILESTONE",
		Effect = "INCOME",
		Flavour = "Still heavy. Still not enough.",
		Gain = "Placed brainrot income +30%.",
		Trade = "Sell value \u{2212}10%.",
		TradeProposed = true,
		Config = "IncomeAdd = 0.30, SellAdd = -0.10",
		Source = "First Epic catch",
		Hook = "IncomeLoop",
		-- The video showed no note box for this one. Left nil.
		Sigil = "diamond",
	},

	-- 06 -------------------------------------------------- video panel, verbatim
	{
		Id = "CHARM_STRONG_ARM",
		Name = "The Ironbound Arm",
		WasCalled = "Strong Arm",   -- collides with UpgradeConfig's Power upgrade; see header
		Category = "QUEST",
		Effect = "DISTANCE",
		Flavour = "Bound so tightly the arm forgot it was ever able to tire.",
		Gain = "Throw distance +20%. Distance hard-gates rarity bands, so this is a reach charm before it is a power charm.",
		Trade = "Charge time \u{00D7}1.25.",
		TradeProposed = true,
		Config = "DistanceAdd = 0.20, ChargeScale = 1.25",
		Source = "Gianluca quest",
		Hook = "ThrowHandler:559-564",
		Sigil = "circle",
	},

	-- 07 -------------------------------------------------- video panel, verbatim
	{
		Id = "CHARM_FOUR_LEAF",
		Name = "The Fourfold Leaf",
		WasCalled = "Four-Leaf",
		Category = "WORLD",
		Effect = "ACCESS LUCK",
		Flavour = "Four leaves. Four chances. One of them was never yours.",
		Gain = "Access luck +35%. lf = 1 + 0.35 \u{00D7} 0.18 = 1.063, compounding as lf^(i\u{2212}1) \u{2014} +44% relative weight on Secret, +28% Legendary, +14% Epic.",
		-- Deliberately no TRADE row: this is the reference charm. See Note.
		Config = "LuckAdd = 0.35",
		Source = "The wheel",
		Hook = "accessLuck \u{2192} RarityCurve.Weights",
		Note = "The reference charm \u{2014} kept clean so every other number in the set can be priced against it.",
		Sigil = "square",
	},

	-- 08 -------------------------------------------------- video panel, verbatim
	{
		Id = "CHARM_MUTATION_LENS",
		Name = "The Warping Lens",
		WasCalled = "Mutation Lens",
		Category = "QUEST",
		Effect = "MUTATION",
		Flavour = "Look long enough at a shell and the shell begins to look back.",
		Gain = "Mutation chance \u{00D7}2. Golden 13.5% \u{2192} 27%, Diamond 5.5% \u{2192} 11%.",
		Trade = "Access luck \u{2212}12%.",
		TradeProposed = true,
		Config = "MutationAdd = 1.00, LuckAdd = -0.12",
		Source = "Tung quest",
		Hook = "MutationConfig.Roll",
		Note = "Mutations multiply income independently of tier, so trading tier luck for mutation odds is a real axis change, not a downgrade.",
		Sigil = "circle",
	},

	-- 09 ------------------------------------- no video panel; spec + invented line
	{
		Id = "CHARM_PROSPECTORS_EYE",
		Name = "The Prospector's Eye",
		WasCalled = "Prospector's Eye",
		Category = "MILESTONE",
		Effect = "TIER RAMP",
		Flavour = "It sees the seam before the seam is there.",  -- flavour: INVENTED
		Gain = "A newly unlocked tier reaches full odds in 80 studs instead of 160.",
		Config = "RampScale = 0.50",
		Source = "First Rare catch",
		Hook = "RarityCurve.RAMP \u{2014} per-player scalar",
		Note = "RAMP = 160 means the rock that finally crosses into a new band has near-zero weight until 160 studs past the edge, so the purchase that should feel like an unlock feels like nothing happened. This turns the worst moment in the progression into the best one.",
		Sigil = "diamond",
	},

	-- 10 ------------------------------------- no video panel; spec + invented line
	{
		Id = "CHARM_STORM_CHASER",
		Name = "Stormcaller's Token",
		WasCalled = "Storm Chaser",
		Category = "WORLD",
		Effect = "WEATHER LUCK",
		Flavour = "It only wakes when the sky does.",  -- flavour: INVENTED
		Gain = "Access luck +70%, but only during a weather event.",
		Config = "LuckAdd = 0.70, RequiresWeather = true",
		Source = "Hidden in the world",
		Hook = "WeatherHandler \u{2014} referenced at ThrowHandler:228",
		Note = "WeatherHandler was not in the export the spec was written against. Confirm what a weather event actually exposes server-side before trusting this number.",
		Sigil = "square",
	},

	-- 11 ------------------------------------- no video panel; spec + invented line
	{
		Id = "CHARM_FULL_HOUSE",
		Name = "The Full Table",
		WasCalled = "Full House",
		Category = "MILESTONE",
		Effect = "PAD INCOME",
		Flavour = "A full table earns. An empty chair remembers.",  -- flavour: INVENTED
		Gain = "Placed income +50% while every unlocked pad is filled.",
		Config = "IncomeAdd = 0.50, RequiresFullPads = true",
		Source = "First Mythic catch",
		Hook = "IncomeLoop \u{2014} count vs data.UnlockedSpots",
		Note = "Gives \"fill the plot\" a payoff beyond arithmetic.",
		Sigil = "diamond",
	},

	-- 12 ------------------------------------- no video panel; spec + invented line
	{
		Id = "CHARM_DARRELS_FAVOUR",
		Name = "Darrel's Regard",
		WasCalled = "Darrel's Favour",
		Category = "WORLD",
		Effect = "DARRELS",
		Flavour = "Darrel notices what you bring him. Darrel notices what you don't.",  -- flavour: INVENTED
		Gain = "+5 Gems for each brainrot you catch that you do not already own.",
		Config = "DarrelsPerNew = 5",
		Source = "Darrel NPC",
		Hook = "BrainrotMover.CountOwned \u{2192} DarrelService.Award",
		Note = "Milestone rather than trickle: bounded at roughly 805 Darrels across 161 species, un-farmable, and it slows on its own as the index fills. The rate is still an open decision in the spec.",
		Sigil = "square",
	},

	-- ------------------------------------------------------------------------
	-- 13-16: THE ROUND C FOUR. Locked = true.
	--
	-- Blocked STRUCTURALLY, not by effort. All four key off something the throw
	-- does not know yet: bounce count (13, 14, 15) or charge time (16). Per
	-- charms-final.md, the rock's rarity is rolled BEFORE the bounce count
	-- exists -- the outcome is decided before the rock is thrown -- so a
	-- "+luck per bounce" charm has nothing to read. Round C's deterministic
	-- re-sim reverses that order. Build these before it and you build them
	-- twice.
	--
	-- LINE NUMBERS: the spec cites ThrowHandler:559-626 (rarity roll) and :380
	-- (nContacts). Both are STALE against the live ThrowHandler, where
	-- nContacts now sits near :420 inside spawnSkippingStone. The ORDERING
	-- claim above is the spec's and was NOT re-verified here. Re-check it
	-- against live code before building Round C -- it is quoted as rationale,
	-- not asserted as current fact.
	--
	-- These four are also the entire SEASON category and the only "ring"
	-- sigils, which is how the grid tells them apart at a glance.
	-- ------------------------------------------------------------------------

	-- 13 ------------------------------------- no video panel; spec + invented line
	{
		Id = "CHARM_SKIPPING_STONE",
		Name = "The Skipping Shard",
		WasCalled = "Skipping Stone",
		Category = "SEASON",
		Effect = "BOUNCE LUCK",
		Flavour = "Broken off something that skipped further than it had any right to.",  -- flavour: INVENTED
		Gain = "+6% access luck per bounce past the 4th.",
		Config = "BounceLuckPer = 0.06, BounceLuckFrom = 4",
		Source = "Season drop \u{2014} not yet earnable",
		Hook = "Blocked: needs Round C deterministic re-sim",
		Locked = true,
		Sigil = "ring",
	},

	-- 14 ------------------------------------- no video panel; spec + invented line
	{
		Id = "CHARM_FLAT_EDGE",
		Name = "The Flatstone Edge",
		WasCalled = "Flat Edge",
		Category = "SEASON",
		Effect = "BOUNCE CAP",
		Flavour = "Ground flat by water that was never in a hurry.",  -- flavour: INVENTED
		Gain = "Bounce cap 8 \u{2192} 11.",
		-- TradeProposed = false: this downside is part of the SPEC's own design,
		-- not one of the video's PROPOSED additions. The flag is what lets the
		-- panel tell those two apart -- see the note on M.Verify below.
		Trade = "Throw distance \u{2212}15%.",
		TradeProposed = false,
		Config = "BounceCapAdd = 3, DistanceAdd = -0.15",
		Source = "Season drop \u{2014} not yet earnable",
		Hook = "Blocked: needs Round C deterministic re-sim",
		Locked = true,
		Sigil = "ring",
	},

	-- 15 ------------------------------------- no video panel; spec + invented line
	{
		Id = "CHARM_HEAVY_HEART",
		Name = "The Leaden Heart",
		WasCalled = "Heavy Heart",
		Category = "SEASON",
		Effect = "DISTANCE",
		Flavour = "It wants to travel. It does not want to stay.",  -- flavour: INVENTED
		Gain = "Throw distance +20%.",
		Trade = "Bounce cap 8 \u{2192} 6.",
		TradeProposed = false,   -- spec's own design, not a video PROPOSED addition
		Config = "DistanceAdd = 0.20, BounceCapAdd = -2",
		Source = "Season drop \u{2014} not yet earnable",
		Hook = "Blocked: needs Round C deterministic re-sim",
		Note = "Deliberate opposite of The Flatstone Edge. Distance hard-gates rarity bands, so this is a real fork: reach a higher tier, or roll better inside the one you can already reach.",
		Locked = true,
		Sigil = "ring",
	},

	-- 16 ------------------------------------- no video panel; spec + invented line
	{
		Id = "CHARM_PATIENT_STONE",
		Name = "The Patient Stone",
		WasCalled = "Patient Stone",
		Category = "SEASON",
		Effect = "CHARGE LUCK",
		Flavour = "It has waited longer than you have. It can wait longer still.",  -- flavour: INVENTED
		Gain = "+4% access luck per second of charge, to a cap of +40%.",
		Trade = "Charge time \u{00D7}2.",
		TradeProposed = false,   -- spec's own design, not a video PROPOSED addition
		Config = "ChargeLuckPer = 0.04, ChargeLuckCap = 0.40, ChargeScale = 2.00",
		Source = "Season drop \u{2014} not yet earnable",
		Hook = "Blocked: needs Round C deterministic re-sim",
		Locked = true,
		Sigil = "ring",
	},

} :: { Charm }

-- The 9 ids whose Flavour line is invented placeholder copy rather than
-- transcribed design. Kept beside the roster so it can be checked, and so a
-- future editor can see at a glance which lines are free to throw away.
M.InventedFlavour = {
	CHARM_SCHOLARS_SEAL   = true,
	CHARM_PROSPECTORS_EYE = true,
	CHARM_STORM_CHASER    = true,
	CHARM_FULL_HOUSE      = true,
	CHARM_DARRELS_FAVOUR  = true,
	CHARM_SKIPPING_STONE  = true,
	CHARM_FLAT_EDGE       = true,
	CHARM_HEAVY_HEART     = true,
	CHARM_PATIENT_STONE   = true,
}

--------------------------------------------------------------------------------
-- DISPLAY STRINGS
--
-- Every fixed string the panel chrome needs, so no UI file invents one. The
-- COMPOSED lines (kicker, loadout, counter) are functions further down, never
-- constants -- that is what stops "16", "3" and "560" being baked into a UI
-- script where a roster edit could not reach them.
--------------------------------------------------------------------------------

M.Display = {
	Kicker          = "TALISMANS",     -- the video's eyebrow word; see naming ruling
	Title           = "CHARM CODEX",
	LoadoutLabel    = "LOADOUT",
	StackingLabel   = "STACKING RULE",
	StackingFormula = "final = base \u{00D7} (1 + a + b + c)",
	StackingNote    = "Additive within the charm layer, applied once. Never chain.",
	SlotEmpty       = "Empty",
	SlotLocked      = "Locked",
	StatusLive      = "LIVE",
	StatusBlocked   = "BLOCKED",
	ProposedTag     = "PROPOSED",
	RowGain         = "GAIN",
	RowTrade        = "TRADE",
	RowConfig       = "CONFIG",
	RowSource       = "SOURCE",
	RowHook         = "HOOK",
}

--------------------------------------------------------------------------------
-- HELPERS
--
-- All of these read M.Charms / M.Slots at CALL TIME rather than closing over a
-- private upvalue. That is deliberate: it means a test (or a future feature)
-- can swap the roster and every derived number follows, which is exactly the
-- property the combination maths is supposed to have. It also means there is
-- no cached index to fall out of sync when someone reorders the array. With 16
-- entries a linear scan costs nothing.
--------------------------------------------------------------------------------

function M.Count(): number
	return #M.Charms
end

-- Slots a player can actually earn. Slot 4 is a gamepass and still an open
-- decision, so it does not count toward the loadout maths.
function M.UnlockableSlotCount(): number
	local n = 0
	for _, s in ipairs(M.Slots) do
		if not s.Locked then n += 1 end
	end
	return n
end

function M.CharmById(id: string): Charm?
	for _, c in ipairs(M.Charms) do
		if c.Id == id then return c end
	end
	return nil
end

function M.IndexOf(id: string): number?
	for i, c in ipairs(M.Charms) do
		if c.Id == id then return i end
	end
	return nil
end

-- "ALL" returns the whole roster. Any other key returns exact matches, so an
-- unknown key correctly returns an empty list rather than everything.
function M.Filter(categoryKey: string): { Charm }
	local out = {}
	for _, c in ipairs(M.Charms) do
		if categoryKey == "ALL" or c.Category == categoryKey then
			table.insert(out, c)
		end
	end
	return out
end

function M.HasCategory(key: string): boolean
	for _, cat in ipairs(M.Categories) do
		if cat.Key == key then return true end
	end
	return false
end

-- C(n, k), computed. Never the literal 560. Multiply-then-divide in this order
-- keeps every intermediate an exact integer, so no rounding drift for any
-- roster size this panel will ever see.
local function choose(n: number, k: number): number
	if k < 0 or k > n then return 0 end
	if k == 0 or k == n then return 1 end
	k = math.min(k, n - k)
	local result = 1
	for i = 1, k do
		result = result * (n - k + i) / i
	end
	return math.floor(result + 0.5)
end

-- How many distinct loadouts exist: choose(roster size, earnable slot count).
-- 16 charms and 3 slots gives 560. Change either and this follows on its own.
function M.Combinations(): number
	return choose(M.Count(), M.UnlockableSlotCount())
end

--------------------------------------------------------------------------------
-- COMPOSED LINES -- the panel's chrome text, built from the data above.
--------------------------------------------------------------------------------

-- "TALISMANS \u{00B7} 16 IN THE SET \u{00B7} 3 SLOTS"
function M.KickerLine(): string
	return string.format(
		"%s \u{00B7} %d IN THE SET \u{00B7} %d SLOTS",
		M.Display.Kicker, M.Count(), M.UnlockableSlotCount()
	)
end

-- "3 slots \u{00D7} 16 charms = 560 combinations"
function M.LoadoutLine(): string
	return string.format(
		"%d slots \u{00D7} %d charms = %d combinations",
		M.UnlockableSlotCount(), M.Count(), M.Combinations()
	)
end

-- "16 SHOWN \u{00B7} 0/3 SLOTS USED"
function M.ShownLine(shown: number, slotsUsed: number): string
	return string.format(
		"%d SHOWN \u{00B7} %d/%d SLOTS USED",
		shown, slotsUsed, M.UnlockableSlotCount()
	)
end

-- "01/16"
function M.IndexLabel(id: string): string
	local i = M.IndexOf(id)
	if not i then return "" end
	return string.format("%02d/%02d", i, M.Count())
end

-- A locked charm is not earnable yet, so the detail panel's status chip should
-- not claim it is live.
function M.StatusLabel(charm: Charm): string
	if charm.Locked then return M.Display.StatusBlocked end
	return M.Display.StatusLive
end

function M.SigilFor(charm: Charm): string
	return charm.Sigil
end

--------------------------------------------------------------------------------
-- M.Verify() -- self-check for whoever replaces this roster.
--
-- Returns (ok: boolean, lines: { string }). Costs nothing to run and catches
-- the mistakes that are easy to make while swapping 16 entries: a duplicate
-- id, a category with no tab, a Trade with no PROPOSED flag.
--
-- The TradeProposed rule is the one worth understanding: the check is that the
-- flag is NON-NIL, not that it is true. A downside the design proposed but has
-- not committed to (TradeProposed = true) and one the spec settled on
-- (TradeProposed = false) look identical in the data otherwise, and the panel
-- must never print an unconfirmed downside as though it were final. Forgetting
-- the flag entirely is the failure this catches.
--------------------------------------------------------------------------------

function M.Verify(): (boolean, { string })
	local lines = {}
	local ok = true
	local function fail(fmt: string, ...): ()
		ok = false
		table.insert(lines, "FAIL  " .. string.format(fmt, ...))
	end

	local seenId, seenName = {}, {}
	for i, c in ipairs(M.Charms) do
		if seenId[c.Id] then fail("duplicate Id %s at index %d", c.Id, i) end
		if seenName[c.Name] then fail("duplicate Name %s at index %d", c.Name, i) end
		seenId[c.Id], seenName[c.Name] = true, true

		if not M.HasCategory(c.Category) then
			fail("%s has Category %s, which is not in M.Categories", c.Id, c.Category)
		end
		if c.Trade ~= nil and c.TradeProposed == nil then
			fail("%s has a Trade but no TradeProposed flag", c.Id)
		end
		if c.Trade == nil and c.TradeProposed ~= nil then
			fail("%s flags TradeProposed but has no Trade", c.Id)
		end
		local expected = M.SigilForCategory[c.Category]
		if expected and c.Sigil ~= expected then
			-- Not fatal: a future roster may want an exception. Still worth saying.
			table.insert(lines, string.format(
				"NOTE  %s uses sigil %s; category %s normally uses %s",
				c.Id, c.Sigil, c.Category, expected))
		end
	end

	if M.UnlockableSlotCount() < 1 then
		fail("no unlockable slots, so Combinations() is meaningless")
	end

	table.insert(lines, string.format(
		"%s  %d charms, %d/%d slots earnable, %d combinations",
		ok and "OK   " or "----", M.Count(), M.UnlockableSlotCount(), #M.Slots, M.Combinations()))

	return ok, lines
end

return M
