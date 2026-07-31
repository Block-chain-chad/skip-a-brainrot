--!strict
-- data_schema.lua — table shapes the UI binds to, plus the remote contract.
-- Server owns every reward-bearing field. The client only renders and sends intent.

export type Rarity = "common" | "rare" | "epic" | "legend" | "mythic"

export type Reward = {
	id: string,                -- "gems_25", "crate_supply", "tag_warlord"
	kind: "currency" | "item" | "cosmetic" | "boost" | "crate",
	name: string,              -- shown on the card: "25 Gems", "Supply Crate"
	amount: number,            -- rendered as "x25"; 1 renders as "x1"
	icon: string,              -- rbxassetid://…  (see README asset table for sizes)
	rarity: Rarity?,           -- drives frame colour where a frame is shown
}

export type PassTier = {
	tier: number,              -- 1..50
	freeReward: Reward?,       -- nil = empty cell on the free track
	passReward: Reward?,
	milestone: boolean?,       -- true on 10/20/30/40/50 -> rainbow ring treatment
}

export type PassState = {
	season: number,
	level: number,             -- highest tier unlocked
	xp: number,                -- progress inside the current tier
	xpNeed: number,            -- xp required for the next tier
	passOwned: boolean,
	claimedFree: { [number]: boolean },
	claimedPass: { [number]: boolean },
	endsAtUnix: number,
}

export type Quest = {
	id: string,
	scope: "daily" | "weekly" | "season",
	title: string,             -- "Win 3 skirmishes"
	goal: number,
	progress: number,
	reward: Reward,
	claimed: boolean,
	refreshAtUnix: number,
}

export type DailyDay = {
	day: number,               -- 1..7
	reward: Reward,
	grand: boolean,            -- day 7 -> rainbow ring + GRAND ribbon
}

export type DailyState = {
	streakDay: number,         -- day the player is on
	claimedToday: boolean,
	resetsAtUnix: number,
}

export type IndexEntry = {
	id: string,
	name: string,
	category: "units" | "vehicles" | "buildings",
	icon: string,
	discovered: boolean,
	seen: boolean,             -- discovered but not yet viewed -> NEW ribbon
}

export type BackpackItem = {
	uid: string,               -- unique instance id
	id: string,                -- catalogue id
	name: string,
	category: "weapons" | "units" | "boosts" | "skins",
	rarity: Rarity,
	qty: number,
	equipped: boolean,
	stats: { { key: string, value: string } },  -- rendered in listed order
}

export type BackpackState = {
	items: { BackpackItem },
	capacity: number,          -- header reads "#items / capacity slots"
}

export type Settings = {
	music: number,             -- 0..100
	sfx: number,               -- 0..100
	quality: number,           -- 0 = Low, 1 = Medium, 2 = High
	screenShake: boolean,
	damageNumbers: boolean,
	autoClaim: boolean,
	showOtherPlayers: boolean,
}

--------------------------------------------------------------------- remotes
-- ReplicatedStorage/Remotes/*
-- All claim paths are RemoteFunctions so the UI can show a failure reason.
--
--  ClaimPassTier(tier: number, track: "free" | "pass") -> { ok: boolean, reason: string?, state: PassState }
--  SkipTiers(count: number)                            -> { ok, reason, state }   -- charges gems
--  ClaimDaily()                                        -> { ok, reason, state: DailyState }
--  ClaimQuest(questId: string)                         -> { ok, reason, quests: { Quest } }
--  EquipItem(uid: string)                              -> { ok, reason, items: { BackpackItem } }
--  BuyPass()                                           -- client calls MarketplaceService:PromptProductPurchase
--  SetSetting(key: string, value: any)                 -> { ok }
--
-- Server -> client pushes: PassStateChanged, QuestsChanged, DailyChanged,
-- BackpackChanged, CurrencyChanged { coins, gems }.
--
-- Rejection reasons the UI already has copy for:
--   "locked"        tier > level
--   "needs_pass"    pass track without ownership
--   "already"       already claimed
--   "no_funds"      skip / purchase without enough gems
--   "not_ready"     quest progress < goal, or daily already claimed today

--------------------------------------------------------------------- defaults
local M = {}

M.SKIP_COST_PER_TIER = 5      -- Skip button label: (xpNeed - xp) * SKIP_COST_PER_TIER
M.PASS_PRICE_GEMS = 799
M.TIER_COUNT = 50
M.DAILY_CYCLE = 7

-- Season 1 sample ladder (first 6 tiers + the tier-50 finale shown in the mock).
M.season1 = {
	{ tier = 1,
	  freeReward = { id = "gems_25", kind = "currency", name = "25 Gems", amount = 25, icon = "" },
	  passReward = { id = "gems_50", kind = "currency", name = "50 Gems", amount = 50, icon = "" } },
	{ tier = 2,
	  freeReward = { id = "tag_recruit", kind = "cosmetic", name = "Recruit Tag", amount = 1, icon = "" },
	  passReward = { id = "tag_warlord", kind = "cosmetic", name = "Warlord Tag", amount = 1, icon = "", rarity = "epic" } },
	{ tier = 3,
	  freeReward = { id = "crate_supply", kind = "crate", name = "Supply Crate", amount = 1, icon = "", rarity = "rare" },
	  passReward = { id = "crate_elite", kind = "crate", name = "Elite Crate", amount = 1, icon = "", rarity = "epic" } },
	{ tier = 4,
	  freeReward = { id = "gems_25", kind = "currency", name = "25 Gems", amount = 25, icon = "" },
	  passReward = { id = "gems_50", kind = "currency", name = "50 Gems", amount = 50, icon = "" } },
	{ tier = 5,
	  freeReward = { id = "banner_01", kind = "cosmetic", name = "Banner Flag", amount = 1, icon = "" },
	  passReward = { id = "boost_coin2x", kind = "boost", name = "x2 Coin Boost", amount = 1, icon = "", rarity = "rare" } },
	{ tier = 6,
	  freeReward = { id = "coins_500", kind = "currency", name = "500 Coins", amount = 1, icon = "" },
	  passReward = { id = "skin_base_01", kind = "cosmetic", name = "Base Skin", amount = 1, icon = "", rarity = "legend" } },
	{ tier = 50, milestone = true,
	  freeReward = { id = "tier50_free", kind = "cosmetic", name = "Max Reward", amount = 1, icon = "", rarity = "mythic" },
	  passReward = { id = "tier50_pass", kind = "cosmetic", name = "Max Reward", amount = 1, icon = "", rarity = "mythic" } },
}

-- Pure view-state resolver — the single source of truth for card visuals.
-- Returns "locked" | "claimable" | "claimed".
function M.tierState(state: PassState, tier: number, track: "free" | "pass"): string
	local claimed = if track == "free" then state.claimedFree else state.claimedPass
	if claimed[tier] then return "claimed" end
	if tier > state.level then return "locked" end
	if track == "pass" and not state.passOwned then return "locked" end
	return "claimable"
end

function M.questState(q: Quest): string
	if q.claimed then return "claimed" end
	if q.progress >= q.goal then return "claimable" end
	return "in_progress"
end

function M.dayState(d: DailyDay, s: DailyState): string
	if d.day < s.streakDay or (d.day == s.streakDay and s.claimedToday) then return "claimed" end
	if d.day == s.streakDay then return "today" end
	return "locked"
end

--------------------------------------------------------------------- egg shop
export type EggPool = {
	petId: string,
	name: string,
	rarity: Rarity,
	icon: string,
	weight: number,          -- raw drop weight; UI shows weight/total, luck-adjusted
}

export type Egg = {
	id: string,              -- "egg_rune"
	name: string,            -- "Rune Egg"
	biome: string,           -- "forest" | "desert" | "frost"
	price: number,           -- in coins
	rarity: Rarity,          -- the egg's own tier -> frame colour on the row
	icon: string,
	unlockLevel: number?,    -- nil = always available; set -> row shows "Forest Lv N"
	pool: { EggPool },
}

export type EggShopState = {
	biome: string,
	coins: number,
	unlockedBiomes: { [string]: boolean },
	biomeLevel: { [string]: number },
	luckMultiplier: number,  -- 1.25 renders as the "LUCK +25%" chip
	discovered: { [string]: boolean },  -- petId -> true; false hides the odds tile behind "?"
}

--  OpenEgg(eggId: string, qty: number) -> { ok, reason, results: { EggPool }, coins: number }
--    reasons: "locked" | "no_funds" | "bad_qty" | "biome_locked"
--  Server rolls every result; the client only animates what comes back.

function M.eggRowState(egg: Egg, s: EggShopState): string
	if egg.unlockLevel and (s.biomeLevel[egg.biome] or 0) < egg.unlockLevel then return "locked" end
	if s.coins < egg.price then return "too_poor" end
	return "buyable"
end

-- Luck-adjusted display odds. Luck lifts rare+ weights only, then renormalises,
-- so the percentages the player sees always add up to 100.
function M.displayOdds(pool: { EggPool }, luck: number): { { petId: string, pct: number } }
	local boosted, total = {}, 0
	for _, p in ipairs(pool) do
		local w = if p.rarity == "common" then p.weight else p.weight * luck
		table.insert(boosted, { petId = p.petId, w = w })
		total += w
	end
	local out = {}
	for _, b in ipairs(boosted) do
		table.insert(out, { petId = b.petId, pct = (b.w / total) * 100 })
	end
	return out
end

M.EGG_QUANTITIES = { 1, 3, 10 }

return M
