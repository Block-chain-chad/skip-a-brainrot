-- LeaderboardHandler: three global top-50 boards, shared across every server.
--
-- Boards: lifetime cash EARNED, lifetime TIME PLAYED, lifetime BRAINROTS CAUGHT.
-- Each is an OrderedDataStore, which is the only Roblox primitive that can sort across
-- servers. A plain DataStore cannot answer "who are the top 50" at all.
--
-- ============================ HOW IT STAYS CHEAP ============================
-- Two loops, both slow on purpose:
--   PUBLISH  every PUBLISH_EVERY seconds, write the online players' three stats.
--   FETCH    every FETCH_EVERY seconds, pull the top 50 of each board and repaint.
-- Nothing here runs on the throw path, the income tick, or any player action. A busy
-- server writes 3 keys per player per publish, which sits far inside the
-- 60 + 10*players per minute budget even with a full lobby.
--
-- OrderedDataStore only stores INTEGERS (int64). Every value is floored before it is
-- written; TotalEarned is a double in Lua and would silently fail the write otherwise.
--
-- ============================== FAILURE POLICY ==============================
-- Fail SOFT and stay quiet. A leaderboard is decoration: if DataStores are down (or
-- the place has no API access, which is the default in a fresh Studio session) the
-- boards show "no data yet" and everything else in the game carries on. Every request
-- is pcall'd, and a global backoff stops a dead endpoint being hammered.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)

local M = {}

--================================= tuning ==================================--
local TOP_N          = 50
local PUBLISH_EVERY  = 120   -- seconds between writing online players' stats
local FETCH_EVERY    = 60    -- seconds between re-reading the top 50
local TIME_TICK      = 10    -- seconds of playtime credited per tick
local FAIL_BACKOFF   = 45    -- seconds to stand down after a DataStore error

-- Bump the version suffix to reset a board. Old keys are simply orphaned.
M.BOARDS = {
	{
		Id    = "Earned",
		-- v2: was TotalEarned, which counts PRODUCTION only and so read ~$400B low for
		-- anyone who had sold a brainrot. LifetimeEarned counts every source.
		Store = "LB_Earned_v2",
		Title = "TOP EARNERS",
		Icon  = "\u{1F4B0}",
		Field = "LifetimeEarned",
		Format = "cash",
	},
	{
		Id    = "Time",
		Store = "LB_Time_v1",
		Title = "MOST TIME PLAYED",
		Icon  = "\u{23F1}",
		Field = "TimePlayed",
		Format = "duration",
	},
	{
		Id    = "Caught",
		Store = "LB_Caught_v1",
		Title = "MOST BRAINROTS CAUGHT",
		Icon  = "\u{1F3A3}",
		Field = "BrainrotsCaught",
		Format = "count",
	},
}

--================================== state ==================================--
local stores = {}          -- [boardId] = OrderedDataStore
local cached = {}          -- [boardId] = { { Rank, UserId, Name, Value }, ... }
local nameCache = {}       -- [userId] = display name
local gate = 0             -- os.clock() before which we make no requests at all
local lastFetch = 0        -- os.clock() of the last SUCCESSFUL refresh, for the countdown
local warned = false
local started = false
local listeners = {}       -- functions called with (boardId, rows) after every fetch

-- GetOrderedDataStore itself throws when the place has no API access, so even
-- acquiring the handles is guarded. A nil store means that board stays empty.
for _, b in ipairs(M.BOARDS) do
	local ok, s = pcall(function()
		return DataStoreService:GetOrderedDataStore(b.Store)
	end)
	if ok then stores[b.Id] = s end
	cached[b.Id] = {}
end

local function offline(err)
	gate = os.clock() + FAIL_BACKOFF
	if not warned then
		warned = true
		warn("[LeaderboardHandler] DataStore unavailable (" .. tostring(err)
			.. "); boards will stay empty until it recovers")
	end
end

--============================== value display ==============================--
-- Kept here rather than in NumberFormat: "3d 04h" is a leaderboard-only shape, and
-- NumberFormat.Short is about cash magnitudes.
local function formatDuration(seconds)
	seconds = math.max(math.floor(tonumber(seconds) or 0), 0)
	local d = math.floor(seconds / 86400)
	local h = math.floor((seconds % 86400) / 3600)
	local m = math.floor((seconds % 3600) / 60)
	if d > 0 then return ("%dd %02dh"):format(d, h) end
	if h > 0 then return ("%dh %02dm"):format(h, m) end
	return ("%dm"):format(m)
end

local function formatCount(n)
	n = math.floor(tonumber(n) or 0)
	-- thousands separators; a catch count never needs abbreviating
	local s = tostring(n)
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

function M.FormatValue(kind, value)
	if kind == "duration" then return formatDuration(value) end
	if kind == "count" then return formatCount(value) end
	local NumberFormat = require(game:GetService("ReplicatedStorage").Modules.NumberFormat)
	return "$" .. NumberFormat.Short(value)
end

--=============================== name lookup ===============================--
-- Yields on a miss. Only ever called from the fetch loop, never from a player action.
local function nameFor(userId)
	local hit = nameCache[userId]
	if hit then return hit end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if not ok or type(name) ~= "string" then
		-- an online player is authoritative and free; otherwise show the id
		local plr = Players:GetPlayerByUserId(userId)
		name = plr and plr.Name or ("User " .. tostring(userId))
		if not plr then return name end   -- do NOT cache a fallback: retry next fetch
	end
	nameCache[userId] = name
	return name
end

--================================ publishing ===============================--
-- One player's three stats. Values only ever move up, so a stale write from a laggy
-- server cannot lower a score -- SetAsync is fine and UpdateAsync would cost double.
local function publishPlayer(player)
	local data = PlayerDataManager.Get(player)
	if not data or data.__noSave then return end   -- read-only session: never publish
	for _, b in ipairs(M.BOARDS) do
		local store = stores[b.Id]
		local value = math.floor(tonumber(data[b.Field]) or 0)
		if store and value > 0 then
			local ok, err = pcall(function()
				store:SetAsync(tostring(player.UserId), value)
			end)
			if not ok then offline(err); return end
		end
	end
end

function M.PublishAll()
	if os.clock() < gate then return end
	for _, player in ipairs(Players:GetPlayers()) do
		publishPlayer(player)
	end
end

--================================= fetching ================================--
local function fetchBoard(b)
	local store = stores[b.Id]
	if not store then return nil end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, TOP_N)   -- false = descending
	end)
	if not ok then offline(pages); return nil end

	local ok2, page = pcall(function() return pages:GetCurrentPage() end)
	if not ok2 then offline(page); return nil end

	local rows = {}
	for i, entry in ipairs(page) do
		local userId = tonumber(entry.key)
		if userId then
			rows[#rows + 1] = {
				Rank = i,
				UserId = userId,
				Name = nameFor(userId),
				Value = entry.value,
			}
		end
	end
	return rows
end

-- Seconds until the next scheduled refresh, for the on-board countdown. Counts from the
-- last SUCCESSFUL fetch, so during a DataStore outage it keeps ticking over rather than
-- freezing on a number that has stopped meaning anything.
function M.SecondsUntilRefresh()
	if lastFetch == 0 then return FETCH_EVERY end
	local left = FETCH_EVERY - (os.clock() - lastFetch)
	-- wrap instead of clamping at 0: a slow fetch should not park the display on "0s"
	if left < 0 then left = left % FETCH_EVERY end
	return left
end

function M.RefreshInterval()
	return FETCH_EVERY
end

function M.Refresh()
	if os.clock() < gate then return end
	for _, b in ipairs(M.BOARDS) do
		local rows = fetchBoard(b)
		if rows then
			cached[b.Id] = rows
			lastFetch = os.clock()
			warned = false
			for _, fn in ipairs(listeners) do
				pcall(fn, b.Id, rows)
			end
		end
	end
end

-- current top-50 for a board; never nil, possibly empty
function M.Get(boardId)
	return cached[boardId] or {}
end

-- called with (boardId, rows) after every successful fetch, and once on registration
-- so a board added later paints immediately instead of waiting a full cycle
function M.OnUpdate(fn)
	table.insert(listeners, fn)
	for _, b in ipairs(M.BOARDS) do
		if #(cached[b.Id] or {}) > 0 then pcall(fn, b.Id, cached[b.Id]) end
	end
end

--=================================== init ==================================--
function M.Init()
	if started then return end
	started = true

	-- playtime: credited in small increments rather than measured across a session,
	-- so a crash, a rejoin, or Main saving before us can cost at most TIME_TICK seconds
	task.spawn(function()
		while true do
			task.wait(TIME_TICK)
			for _, player in ipairs(Players:GetPlayers()) do
				local data = PlayerDataManager.Get(player)
				if data then
					data.TimePlayed = (data.TimePlayed or 0) + TIME_TICK
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(PUBLISH_EVERY)
			pcall(M.PublishAll)
		end
	end)

	task.spawn(function()
		task.wait(2)             -- let the first players load in before the first read
		while true do
			pcall(M.Refresh)
			task.wait(FETCH_EVERY)
		end
	end)

	-- last write before they go, so a long session is not lost to the publish interval
	Players.PlayerRemoving:Connect(function(player)
		pcall(publishPlayer, player)
	end)

	print("LeaderboardHandler online")
end

return M
