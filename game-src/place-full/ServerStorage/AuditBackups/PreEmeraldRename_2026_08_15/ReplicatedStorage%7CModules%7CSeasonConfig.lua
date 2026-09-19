-- SeasonConfig: daily-quest pool + season pass tiers. Shared by SeasonPassHandler
-- (progress/awards) and SeasonClient (display). Quests rotate daily (UTC), same
-- 3 for every player. Free track only for now — premium track needs a gamepass id.
local M = {}

-- Event names fired by SeasonPassHandler.Notify
M.QuestPool = {
	{ Id = "Throw20",  Name = "Skip 20 rocks",             Icon = "\u{1FAA8}", Event = "Throw",      Target = 20, XP = 100 },
	{ Id = "Throw50",  Name = "Skip 50 rocks",             Icon = "\u{1FAA8}", Event = "Throw",      Target = 50, XP = 250 },
	{ Id = "Perfect5", Name = "Land 5 PERFECT skips",     Icon = "\u{2B50}", Event = "Perfect",    Target = 5,  XP = 150 },
	{ Id = "Rare3",    Name = "Catch 3 Rare or better",    Icon = "\u{1F48E}", Event = "RareCatch",  Target = 3,  XP = 150 },
	{ Id = "Epic1",    Name = "Catch an Epic or better",   Icon = "\u{1F52E}", Event = "EpicCatch",  Target = 1,  XP = 200 },
	{ Id = "Fuse1",    Name = "Fuse at the campfire",      Icon = "\u{1F525}", Event = "Fuse",       Target = 1,  XP = 200 },
	{ Id = "Daily1",   Name = "Claim the daily reward",    Icon = "\u{1F381}", Event = "DailyClaim", Target = 1,  XP = 50 },
}

M.PoolById = {}
for _, q in ipairs(M.QuestPool) do M.PoolById[q.Id] = q end

-- same 3 quests for everyone on a given UTC day
function M.QuestsForDay(day)
	local rng = Random.new(day)
	local pool = table.clone(M.QuestPool)
	for i = #pool, 2, -1 do
		local j = rng:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	return { pool[1], pool[2], pool[3] }
end

--[[ 50 tiers, 250 XP each.

Every tier used to pay CASH and nothing else, so the whole track read as one
long number going up and the starred milestones were only bigger numbers. The
cash curve stays as the backbone -- it is still what drives progression -- but
the track now also hands out things cash cannot buy:

  * every 5th tier (the ones the UI already stars) gives an EGG
  * tiers in between pay DARRELS, BOOSTS and TITLES, so the premium currency
    has a route onto the track that is not Robux

Kinds, and what SeasonPassHandler.claimTier ACTUALLY does with each. This list
is exhaustive: claimTier has no other branch, and any Kind it does not
recognise falls into its final `else` and grants r.Amount -- which on a
non-cash reward is nil, i.e. zero. A new Kind here without a matching branch
there is a SILENT DUD TIER, so do not add one.
  Cash     Amount        -> PlayerDataManager.GrantCash
  Darrels  Amount        -> DarrelService.Award
  Egg      Id, Qty?      -> hatched Qty times; refunds the darrel price per fail
  Boost    Stat, Minutes -> EXTENDS data.Boosts[Stat], never replaces it
  Tag      Id            -> data.Tags[Id], and worn immediately

(An earlier version of this block documented Rock and Pet kinds. claimTier has
never had a branch for either -- they would have hit the `else` and paid zero.
Neither track has ever listed one, so nothing was ever actually broken.)

SEASON LENGTH: 50 x 250 = 12,500 XP. The quest pool averages 157 XP across its
7 quests and hands out 3 a day, so clearing all three daily tops the track in
~26.5 days -- a calendar month, which is what a season should be. At 25 tiers
it was 13.3 days. That is why XP_PER_TIER stays at 250: doubling the tier count
turned a short track into a properly season-length one rather than a slog.
]]
M.XP_PER_TIER = 250

-- SEASON IDENTITY -- display only. Added 2026-08-07 with the PassPanel reformat,
-- whose header/footer name the season ("SEASON 01 · STILL WATER · 50 TIERS").
-- Nothing here feeds progression, rewards or claims: it is chrome.
--
-- Ends is UNIX seconds and is DELIBERATELY nil. The design shows "18 DAYS LEFT"
-- and "ENDS 04 SEP", but this game has never had a season end date, and the one
-- date-like thing nearby -- SupplySchedule.SEASONS[1].Starts -- is a different
-- concept (when brainrots retire from the catch pool), is an explicit far-future
-- PLACEHOLDER, and is dormant pre-launch. A countdown derived from it would be
-- fiction. While Ends is nil, PassPanel omits the countdown chip and the footer
-- date entirely rather than inventing one; set a real timestamp here and both
-- appear on their own.
M.SEASON = {
	Number = 1,
	Name = "Still Water",
	Id = "SEASON_01_STILL_WATER",
	Ends = nil,
}

-- GROWTH RATE, and why it is 1.28 (2026-08-07, when this went 25 -> 50 tiers).
--
-- At the old 1.38 the curve was tuned to END at tier 25: $800 -> $3.64M, almost
-- exactly StarcastIron ($3.7M), i.e. the rock a ~13-day player is reaching for.
-- Run that same rate on to tier 50 and 1.38^49 is ~7.1 million, so the top tier
-- would pay $11.4 BILLION -- more than VoidHeart, the most expensive thing in
-- the game. Extending the loop alone does not make a longer track, it makes a
-- broken one.
--
-- 1.28 keeps the SAME property at the new endpoint: tier 50 pays $287M, which
-- lands between VoidstoneShard ($135M) and BrainrotCore ($460M) -- the top of
-- the world-1 rock ladder, and what a ~26-day player is reaching for -- while
-- staying well under CometCore ($1.5B), because RockConfig is explicit that the
-- cosmic rocks are where the real grind now lives and the pass must not fund
-- them. Tier 1 is untouched at $800, still exactly FlatSkipper's price.
--
-- THE COST: tier 25 drops $3.64M -> $598.6k. That is unavoidable -- any single
-- exponential from $800 that holds tier 25 at $3.64M IS 1.38 -- and it is the
-- right trade anyway, because tier 25 is no longer the finale, it is the
-- midpoint. Tiers already CLAIMED are unaffected: the grant has happened and
-- data.SeasonClaimed only records that it did. This changes unclaimed tiers.
local CASH_GROWTH = 1.28

local function cashFor(i)
	local cash = math.floor(800 * (CASH_GROWTH ^ (i - 1)) / 100 + 0.5) * 100
	if i % 5 == 0 then cash = cash * 2 end
	return cash
end

-- Name-plate titles. Ids are stable (they are save keys); Label is what a player
-- actually sees over their head.
M.TAGS = {
	-- EXCLUSIVE, creators only. Deliberately not on either reward track and never
	-- written into data.Tags -- see the ADMIN block below for why that matters.
	Admin        = { Label = "\u{2B50} ADMIN", Exclusive = true },
	ProSkipper   = { Label = "Pro Rock Skipper" },
	BrainrotFan  = { Label = "Brainrot Enthusiast" },
	StoneWhisper = { Label = "Stone Whisperer" },
	CampfireLord = { Label = "Campfire Legend" },
	-- Tiers 38 and 48, added with the 26-50 half (2026-08-07). The four titles
	-- above are all spoken for at tiers 13 and 23 on one track or the other, and
	-- data.Tags[Id] = true is idempotent -- re-granting an owned title deeper in
	-- the track would be a dud tier, not a reward. Free pair first, then the two
	-- the paid track gets in the same two slots.
	SkipMaster     = { Label = "Skip Master" },
	SeasonVeteran  = { Label = "Season Veteran" },
	RockLegend     = { Label = "Rock Legend" },
	EternalSkipper = { Label = "Eternal Skipper" },
	-- DAILY LOGIN, day 5 of DailyRewardConfig's week. Lives here rather than in
	-- that file because SeasonPassHandler validates every Tag grant against THIS
	-- table and pays cash instead for an id it does not recognise -- a daily tag
	-- defined anywhere else would silently never be granted.
	--
	-- The week repeats, and data.Tags[Id] = true is idempotent, so from the second
	-- week onward this would be a dud day. DailyRewardConfig therefore gives day 5
	-- a cash Fallback, which the daily granter pays once the title is already
	-- owned -- see the note on that entry.
	CampRegular    = { Label = "Camp Regular" },
	-- THE VIP GAMEPASS (2026-08-09). Not on either reward track and not claimable:
	-- SeasonPassHandler.SyncPassTags grants it from pass OWNERSHIP, on join and again
	-- the moment the pass is bought. It lives here for the same reason CampRegular
	-- does -- every Tag grant in the game is validated against THIS table, and a tag
	-- id defined anywhere else is silently never granted.
	--
	-- NOT Exclusive: that flag means "creators only, never written to a save", which
	-- would refuse the grant outright. A bought title is owned like any other.
	VIPPass        = { Label = "\u{2B50} VIP" },
}

--[[ ADMIN TAG ELIGIBILITY.

The admin tag is unobtainable BY CONSTRUCTION rather than by being rare:

  * no reward track lists it, and claimTier refuses to grant any Exclusive tag
  * it is never written into data.Tags, so there is nothing to duplicate, trade,
    roll back into, or edit a save to obtain
  * the equip remote checks IsCreator(player.UserId) instead of ownership, and
    that runs SERVER-side on every equip

So the worst a spoofed client can do is draw the row for itself; the server will
not wear it. The id list being readable is fine -- it is an allowlist, not a
secret.

The place OWNER is picked up automatically (only when the place is owned by a
user rather than a group, since a group's CreatorId is the group id and would
match nobody). Add co-creators' UserIds here.
]]
M.CREATOR_IDS = {
	-- 1234567890,  -- example: a co-creator
}

function M.IsCreator(userId: number?): boolean
	local id = tonumber(userId)
	if not id then return false end
	if game.CreatorType == Enum.CreatorType.User and id == game.CreatorId then
		return true
	end
	for _, allowed in ipairs(M.CREATOR_IDS) do
		if allowed == id then return true end
	end
	return false
end

-- Boost durations. The daily wheel hands out 10 minutes; the pass is a much
-- longer grind, so the free track pays 30 and the paid one 60. Both feed the
-- SAME data.Boosts expiry the wheel writes, so they stack with it and with the
-- existing 1.3x multiplier rather than inventing a parallel system.
local BOOST_FREE_MIN, BOOST_PASS_MIN = 30, 60
-- Tiers 26-50 double both. One clean step up at the halfway mark, and the
-- free:pass ratio stays exactly 2x, which is the whole point of the paid column.
local BOOST_FREE_LONG, BOOST_PASS_LONG = 60, 120

-- Tiers NOT listed fall through to cash. Egg ids are checked against EggConfig
-- and tag ids against M.TAGS at claim time, so a typo degrades to cash rather
-- than granting nothing.
--
-- The spread is deliberate: something different every few tiers, and the same
-- KIND gets more generous the deeper you go (darrels 20 -> 80, eggs Shard ->
-- Crown), so tier 24 never feels like tier 4.
local FREE_SPECIALS = {
	[2]  = { Kind = "Darrels", Amount = 20 },
	[4]  = { Kind = "Boost",   Stat = "Luck",  Minutes = BOOST_FREE_MIN },
	[5]  = { Kind = "Egg",     Id = "ForestShard" },
	[7]  = { Kind = "Darrels", Amount = 30 },
	[8]  = { Kind = "Boost",   Stat = "Power", Minutes = BOOST_FREE_MIN },
	[10] = { Kind = "Egg",     Id = "ForestDrip" },
	[12] = { Kind = "Darrels", Amount = 45 },
	[13] = { Kind = "Tag",     Id = "ProSkipper" },
	[14] = { Kind = "Boost",   Stat = "Luck",  Minutes = BOOST_FREE_MIN },
	[15] = { Kind = "Egg",     Id = "ForestHorned" },
	[17] = { Kind = "Darrels", Amount = 60 },
	[18] = { Kind = "Boost",   Stat = "Power", Minutes = BOOST_FREE_MIN },
	[20] = { Kind = "Egg",     Id = "ForestRune" },
	[22] = { Kind = "Darrels", Amount = 80 },
	[23] = { Kind = "Tag",     Id = "BrainrotFan" },
	[25] = { Kind = "Egg",     Id = "ForestCrown" },

	-- ===== TIERS 26-50 (2026-08-07) =====
	-- The special tiers here are literally the first half's plus 25, so the back
	-- half keeps the same rhythm -- something different every 2-3 tiers, an egg on
	-- every starred milestone -- instead of reading as a bolted-on extension.
	-- What changes is the SIZE. Darrels carry on climbing ~1.32x a step from 80;
	-- boosts double; and the egg ladder has nowhere left to go, so the eggs climb
	-- in QUANTITY -- exactly how pass tier 25 already handled topping out.
	[27] = { Kind = "Darrels", Amount = 105 },
	[29] = { Kind = "Boost",   Stat = "Luck",  Minutes = BOOST_FREE_LONG },
	[30] = { Kind = "Egg",     Id = "ForestCrown", Qty = 2 },
	[32] = { Kind = "Darrels", Amount = 140 },
	[33] = { Kind = "Boost",   Stat = "Power", Minutes = BOOST_FREE_LONG },
	[35] = { Kind = "Egg",     Id = "ForestCrown", Qty = 3 },
	[37] = { Kind = "Darrels", Amount = 185 },
	[38] = { Kind = "Tag",     Id = "SkipMaster" },
	[39] = { Kind = "Boost",   Stat = "Luck",  Minutes = BOOST_FREE_LONG },
	[40] = { Kind = "Egg",     Id = "ForestCrown", Qty = 4 },
	[42] = { Kind = "Darrels", Amount = 245 },
	[43] = { Kind = "Boost",   Stat = "Power", Minutes = BOOST_FREE_LONG },
	[45] = { Kind = "Egg",     Id = "ForestCrown", Qty = 6 },
	[47] = { Kind = "Darrels", Amount = 320 },
	[48] = { Kind = "Tag",     Id = "SeasonVeteran" },
	[50] = { Kind = "Egg",     Id = "ForestCrown", Qty = 8 },
}

-- The PAID track is the SAME SHAPE, better at every step: the next egg up the
-- Forest ladder, double-length boosts, its own two tags, ~1.5x darrels and cash.
-- A pass owner is not getting a different track, they are getting this one
-- tuned up -- which is why the tier NUMBERS line up one-to-one.
local PASS_SPECIALS = {
	[2]  = { Kind = "Darrels", Amount = 35 },
	[4]  = { Kind = "Boost",   Stat = "Luck",  Minutes = BOOST_PASS_MIN },
	[5]  = { Kind = "Egg",     Id = "ForestDrip" },
	[7]  = { Kind = "Darrels", Amount = 55 },
	[8]  = { Kind = "Boost",   Stat = "Power", Minutes = BOOST_PASS_MIN },
	[10] = { Kind = "Egg",     Id = "ForestHorned" },
	[12] = { Kind = "Darrels", Amount = 80 },
	[13] = { Kind = "Tag",     Id = "StoneWhisper" },
	[14] = { Kind = "Boost",   Stat = "Luck",  Minutes = BOOST_PASS_MIN },
	[15] = { Kind = "Egg",     Id = "ForestRune" },
	[17] = { Kind = "Darrels", Amount = 105 },
	[18] = { Kind = "Boost",   Stat = "Power", Minutes = BOOST_PASS_MIN },
	[20] = { Kind = "Egg",     Id = "ForestCrown" },
	[22] = { Kind = "Darrels", Amount = 140 },
	[23] = { Kind = "Tag",     Id = "CampfireLord" },
	-- top of the egg ladder already, so the step up is a second one
	[25] = { Kind = "Egg",     Id = "ForestCrown", Qty = 2 },

	-- ===== TIERS 26-50 (2026-08-07) =====
	-- One-to-one with the free table above and better at every step, same as the
	-- first half: ~1.5x darrels, double-length boosts, ~1.5x the Heartwood eggs, and
	-- its own two titles in the same two slots. Both tracks stay strictly
	-- increasing in their own right, so nothing deeper ever reads as a downgrade.
	[27] = { Kind = "Darrels", Amount = 160 },
	[29] = { Kind = "Boost",   Stat = "Luck",  Minutes = BOOST_PASS_LONG },
	[30] = { Kind = "Egg",     Id = "ForestCrown", Qty = 3 },
	[32] = { Kind = "Darrels", Amount = 210 },
	[33] = { Kind = "Boost",   Stat = "Power", Minutes = BOOST_PASS_LONG },
	[35] = { Kind = "Egg",     Id = "ForestCrown", Qty = 5 },
	[37] = { Kind = "Darrels", Amount = 280 },
	[38] = { Kind = "Tag",     Id = "RockLegend" },
	[39] = { Kind = "Boost",   Stat = "Luck",  Minutes = BOOST_PASS_LONG },
	[40] = { Kind = "Egg",     Id = "ForestCrown", Qty = 6 },
	[42] = { Kind = "Darrels", Amount = 370 },
	[43] = { Kind = "Boost",   Stat = "Power", Minutes = BOOST_PASS_LONG },
	[45] = { Kind = "Egg",     Id = "ForestCrown", Qty = 9 },
	[47] = { Kind = "Darrels", Amount = 480 },
	[48] = { Kind = "Tag",     Id = "EternalSkipper" },
	[50] = { Kind = "Egg",     Id = "ForestCrown", Qty = 12 },
}

local PASS_CASH_MULT = 1.5

-- 50 since 2026-08-07 (was 25). Every reader -- SeasonClient, PassPanel's card
-- count and its top-tier badge, SeasonPassHandler -- derives its count from
-- #M.Tiers or ThresholdFor(i), so this constant is the only place the length
-- lives. Checked: none of them hard-codes a tier count.
local TIER_COUNT = 50

local function buildTrack(specials, cashMult)
	local t = {}
	for i = 1, TIER_COUNT do
		local reward = specials[i]
		if not reward then
			reward = { Kind = "Cash", Amount = math.floor(cashFor(i) * cashMult / 100 + 0.5) * 100 }
		end
		t[i] = {
			XP = M.XP_PER_TIER,
			Reward = reward,
			Milestone = i % 5 == 0,
			-- Kept so nothing that still reads def.Cash breaks outright. It is 0 on a
			-- non-cash tier, which is why both clients now read Reward instead.
			Cash = (reward.Kind == "Cash") and reward.Amount or 0,
		}
	end
	return t
end

-- M.Tiers stays the FREE track under its old name: every existing reader
-- (SeasonPassHandler, SeasonClient, PassPanel's tier count) means the free one.
M.Tiers = buildTrack(FREE_SPECIALS, 1)
M.PassTiers = buildTrack(PASS_SPECIALS, PASS_CASH_MULT)

-- One lookup so callers never branch on the track name themselves.
function M.TierFor(track, i)
	local t = (track == "pass") and M.PassTiers or M.Tiers
	return t[i]
end

local function prettify(id)
	local s = tostring(id or ""):gsub("(%l)(%u)", "%1 %2")
	return s
end

-- Egg display name and MODEL name come from EggConfig so they can never drift
-- from the shop. Required lazily behind a pcall: EggConfig pulls in PetConfig,
-- and this module is required by server and client at very different times.
local eggCache
local function eggInfo(id)
	if eggCache == nil then
		local ok, mod = pcall(require, script.Parent.EggConfig)
		eggCache = ok and mod or false
	end
	if eggCache then
		local egg = eggCache.GetEgg("Forest", id)
		if egg then return egg.Name, egg.Model end
	end
	return prettify(id), nil
end

--[[ ONE place that turns a tier into something displayable, so SeasonClient and
PassPanel cannot drift apart on it. Returns:
  { kind, icon, amount?, id?, text? }
Cash returns `amount` and NO text -- each client has its own cash abbreviator
and should keep using it. Everything else returns ready-made `text`. ]]
function M.DescribeReward(def)
	local r = def and def.Reward or { Kind = "Cash", Amount = (def and def.Cash) or 0 }
	-- `icon` is a UIKit Tokens.icons KEY and only keys with real art are worth
	-- returning. Live keys: bag coin daily gem goals index pass settings. "gem"
	-- IS the darrel icon. Eggs need no icon key -- they draw their MODEL instead,
	-- which is what `model` is for (a child name under EggModels.Forest).
	if r.Kind == "Darrels" then
		return { kind = "Darrels", icon = "gem", amount = r.Amount, text = "+" .. tostring(r.Amount) }
	elseif r.Kind == "Egg" then
		local qty = r.Qty or 1
		local name, model = eggInfo(r.Id)
		return { kind = "Egg", icon = "coin", id = r.Id, qty = qty, model = model,
			text = name .. (qty > 1 and (" x" .. qty) or "") }
	elseif r.Kind == "Boost" then
		local isLuck = r.Stat == "Luck"
		return { kind = "Boost", icon = "coin", stat = r.Stat, minutes = r.Minutes,
			-- glyph, because there is no icon art for either boost. PassPanel draws
			-- this big and centred where a model would otherwise go.
			glyph = isLuck and "\u{1F340}" or "\u{1F4AA}",
			text = (isLuck and "Luck" or "Power") .. " " .. tostring(r.Minutes) .. "m" }
	elseif r.Kind == "Tag" then
		local def2 = M.TAGS[r.Id]
		return { kind = "Tag", icon = "coin", id = r.Id, glyph = "\u{1F3F7}",
			text = def2 and def2.Label or prettify(r.Id) }
	end
	return { kind = "Cash", icon = "coin", amount = r.Amount or 0 }
end

-- cumulative XP needed to unlock tier i
function M.ThresholdFor(i)
	return i * M.XP_PER_TIER
end

return M
