-- DailyRewardConfig -- the seven-day login week: what each day pays, and how a
-- day card describes itself.
--
-- SHARED ON PURPOSE. The server (ServerScriptService.Modules.DailyRewardHandler)
-- grants from Days; the panel (GameHUDPanels.DailyPanel) renders from Describe.
-- One table, so the card can never advertise something the server does not pay.
--
-- REWARD KINDS are SeasonPassHandler.GrantReward's, not a second vocabulary --
-- the daily calendar and the season track share that one granter, so a Kind is
-- implemented once. The exhaustive list lives in SeasonConfig's header:
--   Cash     Amount
--   Darrels  Amount
--   Boost    Stat, Minutes    -- EXTENDS data.Boosts[Stat], stacks with the wheel
--   Tag      Id               -- must exist in SeasonConfig.TAGS or it pays cash
--   Egg      Id | Random, Qty -- hatched; a failed hatch refunds the darrel price
-- A Kind not in that list falls through to the granter's `else` and pays
-- r.Amount, which on a non-cash reward is nil -- i.e. a silent dud. Do not invent
-- one here without adding a branch there.
--
-- THE WEEK REPEATS. streakDayFor() cycles the streak back through these seven, so
-- every entry has to still be worth claiming on week ten. That is what Fallback
-- is for: a day whose reward cannot land twice (the Tag, which is idempotent)
-- names the cash it pays instead once the player already owns it.
local M = {}

-- Day 5's title. Defined in SeasonConfig.TAGS because the granter validates every
-- Tag id against that table and quietly pays cash for one it does not recognise.
M.TagId = "CampRegular"

M.Days = {
	-- 1-2 ease in on cash, at the old curve's opening numbers
	{ Kind = "Cash",    Amount = 500,                        Fallback = 500 },
	{ Kind = "Cash",    Amount = 1000,                       Fallback = 1000 },
	-- An hour of Luck. The season track's own late-game boost is 60 minutes, so
	-- this is deliberately generous -- it is the midweek reason to come back, and
	-- it EXTENDS any boost already running rather than replacing it.
	{ Kind = "Boost",   Stat = "Luck", Minutes = 60,         Fallback = 2500 },
	-- Premium currency without Robux. 30 is the season's tier-7 darrel payout, and
	-- half a Mossy Egg (60) -- a fortnight of dailies buys one, which is a nudge
	-- toward the egg shop rather than a replacement for it.
	{ Kind = "Darrels", Amount = 30,                         Fallback = 5000 },
	-- The title. Only lands ONCE ever; Fallback is what every later week pays --
	-- see the note above and the already-owned branch in GrantReward.
	{ Kind = "Tag",     Id = M.TagId,                        Fallback = 15000 },
	{ Kind = "Cash",    Amount = 25000,                      Fallback = 25000 },
	-- The payoff. Random, so each of the three is its own draw across the Forest
	-- ladder (Shard 60 -> Crown 220) instead of three of the same egg.
	--
	-- DisplayEgg is DISPLAY ONLY and never granted: with Random there is no single
	-- egg to show, so the card poses the top of the ladder (Crown) as the promise.
	{ Kind = "Egg",     Random = true, Qty = 3, World = "Forest",
	  DisplayEgg = "ForestCrown", Fallback = 100000 },
}

M.CycleLength = #M.Days

-- === DISPLAY ==================================================================
-- Kept beside the rewards so a change to the week cannot leave a card describing
-- the old one.
--
-- A card uses whichever ONE of these it is handed, in this order:
--   Model  a real egg MODEL, posed in a ViewportFrame (BrainrotThumb) -- the
--          same way the season pass draws its egg tiers
--   Draw   a vector icon drawn by UIKit.IconArt, which is where the DARREL's own
--          art lives. T.icons.gem is a generic purple gem and is NOT the darrel;
--          PassPanel makes the same point and the same choice.
--   Icon   a UIKit Tokens.icons key (uploaded PNG art)
--   Glyph  an emoji, the last resort for kinds with no art at all (the Luck
--          boost and the title). Inventing an asset id for art that does not
--          exist renders a blank square, which is worse than an emoji.
local ICON_CASH = "coin"

-- EggConfig is required LAZILY behind a pcall: it pulls in PetConfig, and this
-- module is loaded by the server and the client at very different times.
-- SeasonConfig.eggInfo does the same dance for the same reason.
local eggCache
local function eggModel(id: string?): string?
	if not id then return nil end
	if eggCache == nil then
		local ok, mod = pcall(require, script.Parent.EggConfig)
		eggCache = ok and mod or false
	end
	if not eggCache then return nil end
	local egg = eggCache.GetEgg("Forest", id)
	return egg and egg.Model or nil
end

local function shortCash(n: number): string
	n = math.floor(tonumber(n) or 0)
	if n >= 1e9 then return string.format("$%.1fB", n / 1e9) end
	if n >= 1e6 then return string.format("$%.1fM", n / 1e6) end
	if n >= 1e3 then return string.format("$%.0fK", n / 1e3) end
	return "$" .. tostring(n)
end
M.ShortCash = shortCash

-- Returns { Text = string, Icon = string?, Glyph = string? } for one reward.
-- Never returns nil: an unrecognised Kind still gets a card rather than a hole.
function M.Describe(r)
	if type(r) ~= "table" then return { Text = "?", Icon = ICON_CASH } end

	if r.Kind == "Cash" then
		return { Text = shortCash(r.Amount), Icon = ICON_CASH }

	elseif r.Kind == "Darrels" then
		-- the darrel's OWN drawn icon, the one on the HUD currency pill
		return { Text = tostring(math.floor(tonumber(r.Amount) or 0)), Draw = "darrel" }

	elseif r.Kind == "Boost" then
		local mins = tonumber(r.Minutes) or 30
		local stat = tostring(r.Stat or "Luck"):upper()
		-- whole hours read as "1H", anything else stays in minutes
		local span = (mins >= 60 and mins % 60 == 0)
			and string.format("%dH", mins // 60)
			or string.format("%dM", mins)
		return { Text = span .. " " .. stat, Glyph = "\u{1F340}" }

	elseif r.Kind == "Tag" then
		return { Text = "TITLE", Glyph = "\u{1F3F7}\u{FE0F}" }

	elseif r.Kind == "Egg" then
		local qty = math.max(1, math.floor(tonumber(r.Qty) or 1))
		-- a named egg poses itself; a Random one poses whatever DisplayEgg promises
		local model = eggModel(r.Id or r.DisplayEgg)
		return {
			Text = (qty > 1) and (qty .. " EGGS") or "EGG",
			Model = model,
			Glyph = "\u{1F95A}",   -- only reached if the model is missing
		}
	end

	return { Text = "?", Icon = ICON_CASH }
end

return M
