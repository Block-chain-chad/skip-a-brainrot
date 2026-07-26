-- SupplySchedule: the single source of truth for WHEN each brainrot is catchable.
-- Clock-pure: everything derives from server-synced UTC time + this authored
-- config, so every server and every client independently agrees with no
-- DataStore and no publish.
--   Common/Uncommon: always live.
--   Rare/Epic:       "the Tide" -- a permanent per-name A/B split; even
--                    week-index -> A live, odd -> B. Every name is live at
--                    least every other week, and players can plan around it.
--   Legendary/Mythic: "the Vault" -- seasons retire authored batches forever
--                    (a season's Retire list leaves when the NEXT season
--                    starts, so the whole season is the last-chance window).
--   Secret:          always live but hard-capped (LimitedStock owns the
--                    counts; CAPPED below only tells the UI which names to badge).
-- PRE-LAUNCH DORMANCY: until SEASONS[1].Starts the schedule is inert -- no
-- tide, no countdowns, everything catchable. The game is not public yet, and
-- nothing may retire before the public could ever catch it.
-- Ownership is NEVER gated here: this module answers "can it be CAUGHT now",
-- nothing else.

local RunService = game:GetService("RunService")
local BrainrotConfig = require(script.Parent.BrainrotConfig)

local M = {}

local WEEK = 604800

M.SEASONS = {
	{
		-- SET THIS WHEN YOU LAUNCH: the real go-live Monday 00:00 UTC. Until
		-- then it is a far-future placeholder and the whole schedule is DORMANT.
		Starts = 1798761600, -- PLACEHOLDER: 2027-01-01 00:00 UTC
		Retire = { "Sovrano Pancetta", "Console Grattugia", "Idolo Cappelletto" },
		Debut = {},
	},
	{
		-- keep exactly 8 weeks (4838400s) after Season 1 when moving the date
		Starts = 1803600000, -- PLACEHOLDER: Season 1 + 8 weeks
		Retire = {},
		Debut = {},
	},
}

-- Names with a hard mint cap (LimitedStock.MAX must list exactly these).
-- Duplicated here as a name SET only, because this module is shared and the
-- counts live server-side.
M.CAPPED = {
	["Secret Pete"] = true,
	["Il Papa Meteorite"] = true, ["Il Tiranno Eclissi"] = true,
	["La Sentinella Vuoto"] = true, ["Sua Altezza Galassia"] = true,
	["Il Verdetto Supernova"] = true, ["La Cattedrale Cometa"] = true,
	["Il Colosso Equinozio"] = true, ["Il Firmamento Ribollente"] = true,
	["L'Ammiraglio Nebulosa"] = true, ["La Genesi Corazzata"] = true,
	["Sua Grazia Abisso"] = true,
}

local TIDE = { Rare = true, Epic = true }

--============================ injectable clock ==============================--
-- Server-synchronised UNIX time on BOTH peers. os.time() on a client reads the
-- DEVICE clock, which players can skew by minutes -- the Index would then
-- disagree with the server near every boundary. GetServerTimeNow is epoch-based
-- and synced for clients, and equals wall time on the server.
local function realNow()
	return workspace:GetServerTimeNow()
end
local now = realNow
-- Studio-only: tests step the clock across week and season boundaries instead
-- of waiting eight weeks. A nil fn restores the real clock.
function M.SetClock(fn)
	if RunService:IsStudio() then
		now = fn or realNow
	end
end

--=============================== authored maps ==============================--
local entryByName = {}
for _, e in ipairs(BrainrotConfig) do
	entryByName[e.Name] = e
end

local debutSeasonOf = {}   -- [name] = season index it debuts in
local retireSeasonOf = {}  -- [name] = season index whose END retires it
for k, season in ipairs(M.SEASONS) do
	for _, n in ipairs(season.Debut) do debutSeasonOf[n] = k end
	for _, n in ipairs(season.Retire) do retireSeasonOf[n] = k end
end

-- A retire list needs a NEXT season to define when it triggers; the final
-- authored season's Retire can never fire. Loud, because silently-immortal
-- "retirements" would be a lie in the Index.
if #M.SEASONS[#M.SEASONS].Retire > 0 then
	warn("[SupplySchedule] the final season's Retire list can never trigger -- author the next season row")
end

--============================== time helpers ================================--
local function seasonIndexAt(t)
	local idx = 1
	for k, season in ipairs(M.SEASONS) do
		if t >= season.Starts then idx = k end
	end
	return idx
end

-- A season "has ended" only when a NEXT season exists and has started; the
-- final authored season never ends (the schedule holds its final state).
local function seasonEndedAt(k, t)
	local nextSeason = M.SEASONS[k + 1]
	return nextSeason ~= nil and t >= nextSeason.Starts
end

local function weekIndexAt(t)
	return math.max(0, math.floor((t - M.SEASONS[1].Starts) / WEEK))
end

--================================ the tide ==================================--
-- Split membership is PER-NAME and PERMANENT, from a hash of the name alone.
-- Two rejected alternatives, both review-killed:
--   * per-season reshuffle -- at every season boundary ~half the away names
--     land away AGAIN (14 straight days), breaking the "live at least every
--     other week" guarantee and falsifying every RETURNS timestamp;
--   * positional shuffle over the roster -- appending ONE config entry moves
--     EXISTING names between sets mid-week.
-- djb2 folded mod a prime (the exact shape MintRegistry already ships): every
-- intermediate stays far below 2^53, so double math is exact and the answer is
-- identical on every client and server, forever.
local function inSetA(name)
	local h = 5381
	for i = 1, #name do
		h = (h * 33 + string.byte(name, i)) % 4294967291
	end
	return h % 2 == 0
end

--================================ public API ================================--

-- status, changeAt. Precedence: unreleased > vaulted > retiring > away >
-- capped > live. Sold-out is deliberately NOT a status here: this module is
-- clock-pure and shared; sold-out truth lives server-side in LimitedStock.
function M.StatusOf(name)
	local entry = entryByName[name]
	if not entry then return nil, nil end
	local t = now()
	local curIdx = seasonIndexAt(t)

	local debutIdx = debutSeasonOf[name]
	if debutIdx and t < M.SEASONS[debutIdx].Starts then
		return "unreleased", M.SEASONS[debutIdx].Starts
	end

	-- Pre-launch dormancy: until Season 1's authored start, the schedule is
	-- inert -- no tide, no countdowns, everything catchable (caps still shown).
	-- Sits AFTER the unreleased check so future debuts stay hidden pre-launch.
	if t < M.SEASONS[1].Starts then
		return M.CAPPED[name] and "capped" or "live", nil
	end

	local retireIdx = retireSeasonOf[name]
	if retireIdx then
		if seasonEndedAt(retireIdx, t) then
			return "vaulted", M.SEASONS[retireIdx + 1].Starts
		end
		if retireIdx == curIdx and M.SEASONS[curIdx + 1] then
			return "retiring", M.SEASONS[curIdx + 1].Starts
		end
	end

	if TIDE[entry.Rarity] then
		local wk = weekIndexAt(t)
		local wantA = (wk % 2 == 0)
		-- With a permanent split, "next flip" is always the true return time.
		if inSetA(name) ~= wantA then
			return "away", M.SEASONS[1].Starts + (wk + 1) * WEEK
		end
	end

	if M.CAPPED[name] then
		return "capped", nil
	end
	return "live", nil
end

function M.IsObtainable(name)
	local status = M.StatusOf(name)
	return status == "live" or status == "capped" or status == "retiring"
end

-- Unix time of the next instant ANY availability can change: the sooner of the
-- next tide flip and the next season boundary. For countdown UI.
function M.NextChange()
	local t = now()
	local nextFlip = M.SEASONS[1].Starts + (weekIndexAt(t) + 1) * WEEK
	for _, season in ipairs(M.SEASONS) do
		if season.Starts > t and season.Starts < nextFlip then
			nextFlip = season.Starts
		end
	end
	return nextFlip
end

-- Changes exactly when the answer of IsObtainable can change. RarityRoll keys
-- its pool cache on this so pools rebuild at boundaries and never in between.
function M.PeriodKey()
	local t = now()
	if t < M.SEASONS[1].Starts then return "pre" end
	return seasonIndexAt(t) .. ":" .. weekIndexAt(t) % 2
end

-- live, total -- for the Index header.
function M.Counts()
	local live = 0
	for _, e in ipairs(BrainrotConfig) do
		if M.IsObtainable(e.Name) then live += 1 end
	end
	return live, #BrainrotConfig
end

return M
