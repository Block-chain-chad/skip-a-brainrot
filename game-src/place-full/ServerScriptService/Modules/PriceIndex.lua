-- PriceIndex
-- Real price discovery for the 12 market stalls.
--
-- Every completed stall sale is a public, timestamped observation of what a
-- player ACTUALLY paid. Collect enough of them and the game can publish its own
-- honest value for an item, instead of leaving players to trust off-platform
-- "value lists" that anyone with a Discord can edit.
--
-- Three rules keep the published number honest:
--   1. MEDIAN, never mean. One whale overpaying 100x drags a mean a long way;
--      it moves a median by exactly one rank.
--   2. MIN_SAMPLES before anything is published at all. One trade is an
--      anecdote, not a price, so Get() returns nil until the sample is real.
--   3. ONE vote per counterparty PAIR. Wash trading is two accounts passing an
--      item back and forth at a fake price to manufacture a "value". The pair
--      key is UNORDERED on purpose: A->B and B->A are the same pair, which is
--      precisely the shape wash trading takes.
--
-- Storage degrades gracefully. Studio has no API access unless it is explicitly
-- enabled, so every DataStore call is pcall-wrapped exactly like the rest of the
-- game; when the store is unavailable the index just runs in memory for the life
-- of the server and nothing errors.

local DataStoreService = game:GetService("DataStoreService")

local PriceIndex = {}

local WINDOW = 7 * 24 * 60 * 60  -- 7-day rolling window, in seconds
local MIN_SAMPLES = 5            -- below this, Get() publishes no price at all
local MAX_PRICE = 1e12           -- sanity ceiling; a poisoned entry never lands
local MAX_PER_PAIR = 3           -- stored observations per pair, per item
local MAX_OBS_PER_ITEM = 120     -- hard storage cap per item; oldest dropped
local NUM_SHARDS = 16            -- items bucket into shards: few keys, few requests
local FLUSH_SECONDS = 120        -- write shards that have new observations
local REFRESH_SECONDS = 600      -- re-read every shard, to see other servers' sales
local FAILS_BEFORE_BACKOFF = 3
local BACKOFF_SECONDS = 300

-- read-only, for anything that wants to explain the number to a player
PriceIndex.WindowDays = 7
PriceIndex.MinSamples = MIN_SAMPLES

local store
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("BrainrotSkip_PriceIndex_v1")
	end)
	store = ok and result or nil
end

-- index[itemKey] = { { T = unixTime, P = price, B = buyerUserId, S = sellerUserId }, ... }
-- kept sorted by T ascending, so list[1] is always the oldest
local index = {}
-- pending[itemKey] = { obs, ... } -- recorded, not yet written to the store
local pending = {}
local pendingCount = 0

local storeFails = 0
local backoffUntil = 0
local warned = false
local busy = false

-- Mutation is part of the identity: a Golden copy and a plain copy are two
-- different markets and must never share a price.
local function itemKey(name, mutation)
	return name .. "|" .. (mutation or "-")
end

-- UNORDERED. This is the whole anti-wash mechanism: swapping who is buying and
-- who is selling must not buy you a second vote.
local function pairKey(a, b)
	if a <= b then
		return a .. ":" .. b
	end
	return b .. ":" .. a
end

local function shardOf(key)
	local h = 5381
	for i = 1, #key do
		h = (h * 33 + string.byte(key, i)) % 2147483647
	end
	return (h % NUM_SHARDS) + 1
end

local function shardName(shard)
	return "Idx_v1_" .. shard
end

local function storeReady()
	return store ~= nil and os.clock() >= backoffUntil
end

local function noteFailure(what, err)
	storeFails += 1
	if storeFails >= FAILS_BEFORE_BACKOFF then
		storeFails = 0
		backoffUntil = os.clock() + BACKOFF_SECONDS
		if not warned then
			warned = true
			warn(("[PriceIndex] DataStore unavailable (%s: %s); running in memory only"):format(what, tostring(err)))
		end
	end
end

local function noteSuccess()
	storeFails = 0
	warned = false -- so a genuine later outage is still reported once
end

-- Rejects anything malformed or out of the window. Stored data is untrusted:
-- it may be from an older schema, or hand-edited, and must never throw here.
local function validObs(o, cutoff, now)
	return type(o) == "table"
		and type(o.T) == "number" and o.T == o.T and o.T >= cutoff and o.T <= now + 86400
		and type(o.P) == "number" and o.P == o.P and o.P > 0 and o.P <= MAX_PRICE
		and type(o.B) == "number" and type(o.S) == "number" and o.B ~= o.S
end

local function countPair(list, key)
	local n = 0
	for _, o in ipairs(list) do
		if pairKey(o.B, o.S) == key then
			n += 1
		end
	end
	return n
end

-- Prunes everything outside the 7-day window, folds `adds` in, and enforces the
-- storage caps. Pure and NON-YIELDING: this runs inside UpdateAsync's transform,
-- which Roblox may call more than once when another server writes first. Called
-- with adds = nil it is simply "prune to the window", which is what load does.
local function mergeShard(old, adds)
	local now = os.time()
	local cutoff = now - WINDOW
	local out = {}

	if type(old) == "table" then
		for key, list in pairs(old) do
			if type(key) == "string" and type(list) == "table" then
				local kept = {}
				for _, o in ipairs(list) do
					if validObs(o, cutoff, now) then
						table.insert(kept, o)
					end
				end
				if #kept > 0 then
					out[key] = kept
				end
			end
		end
	end

	if adds then
		for key, list in pairs(adds) do
			local dest = out[key]
			if not dest then
				dest = {}
				out[key] = dest
			end
			for _, o in ipairs(list) do
				local pk = pairKey(o.B, o.S)
				if validObs(o, cutoff, now) and countPair(dest, pk) < MAX_PER_PAIR then
					table.insert(dest, o)
				end
			end
		end
	end

	for key, list in pairs(out) do
		table.sort(list, function(a, b) return a.T < b.T end)
		while #list > MAX_OBS_PER_ITEM do
			table.remove(list, 1)
		end
		if #list == 0 then
			out[key] = nil
		end
	end

	return out
end

local function applyPending()
	for key, list in pairs(pending) do
		local dest = index[key]
		if not dest then
			dest = {}
			index[key] = dest
		end
		for _, o in ipairs(list) do
			table.insert(dest, o)
		end
		table.sort(dest, function(a, b) return a.T < b.T end)
	end
end

-- Rebuilds the whole in-memory view from the store, pruning anything older than
-- 7 days as it goes. On ANY failure it abandons the rebuild and keeps whatever
-- is already in memory -- a flaky read must never blank a working index.
local function loadAll()
	if not storeReady() then return end
	local fresh = {}
	for shard = 1, NUM_SHARDS do
		local ok, result = pcall(function()
			return store:GetAsync(shardName(shard))
		end)
		if not ok then
			noteFailure("load", result)
			return
		end
		if type(result) == "table" then
			for key, list in pairs(mergeShard(result, nil)) do
				fresh[key] = list
			end
		end
	end
	noteSuccess()
	index = fresh
	applyPending() -- observations not yet written are still ours to report
end

local function requeue(key, list)
	local dest = pending[key]
	if not dest then
		dest = {}
		pending[key] = dest
	end
	for _, o in ipairs(list) do
		if #dest < MAX_OBS_PER_ITEM then
			table.insert(dest, o)
			pendingCount += 1
		end
	end
end

local function flush()
	if pendingCount == 0 or not storeReady() then return end

	-- Detach BEFORE the first yield. UpdateAsync yields, and a sale landing
	-- during that yield must go into a fresh queue, not into the table the
	-- transform is already reading (and that we are about to clear).
	local outgoing = pending
	pending = {}
	pendingCount = 0

	local byShard = {}
	for key, list in pairs(outgoing) do
		local shard = shardOf(key)
		local bucket = byShard[shard]
		if not bucket then
			bucket = {}
			byShard[shard] = bucket
		end
		bucket[key] = list
	end

	for shard, adds in pairs(byShard) do
		local merged
		local ok, err = pcall(function()
			store:UpdateAsync(shardName(shard), function(old)
				merged = mergeShard(old, adds)
				return merged
			end)
		end)
		if ok and merged then
			noteSuccess()
			-- The merged shard is the freshest view we have of these items: it
			-- also contains sales other servers wrote since our last read.
			for key, list in pairs(merged) do
				index[key] = list
			end
		else
			noteFailure("flush", err)
			for key, list in pairs(adds) do
				requeue(key, list) -- try again next cycle; still readable in memory meanwhile
			end
		end
	end
end

-- One lock so a periodic flush and a periodic reload can never interleave and
-- half-overwrite each other, and so nothing in here can ever throw at a caller.
local function guarded(fn)
	if busy then return false end
	busy = true
	local ok, err = pcall(fn)
	busy = false
	if not ok then
		warn("[PriceIndex] " .. tostring(err))
	end
	return true
end

-- Logs one completed sale. Returns true if it was accepted as an observation.
-- NEVER YIELDS: it only touches memory, so it is safe to call from inside a
-- no-yield critical section such as the booth buy path.
function PriceIndex.RecordSale(name, mutation, price, buyerUserId, sellerUserId)
	if type(name) ~= "string" or name == "" then return false end
	if mutation ~= nil and type(mutation) ~= "string" then return false end

	price = tonumber(price)
	if not price or price ~= price or price == math.huge then return false end
	price = math.floor(price)
	if price < 1 or price > MAX_PRICE then return false end

	if type(buyerUserId) ~= "number" or buyerUserId ~= buyerUserId then return false end
	if type(sellerUserId) ~= "number" or sellerUserId ~= sellerUserId then return false end
	buyerUserId, sellerUserId = math.floor(buyerUserId), math.floor(sellerUserId)
	-- "selling to yourself" is wash trading in its simplest form, not a price
	if buyerUserId == sellerUserId then return false end

	local key = itemKey(name, mutation)
	local now = os.time()
	local obs = { T = now, P = price, B = buyerUserId, S = sellerUserId }

	local list = index[key]
	if not list then
		list = {}
		index[key] = list
	end
	-- oldest first, so everything that has aged out sits at the front
	while #list > 0 and list[1].T < now - WINDOW do
		table.remove(list, 1)
	end
	-- past the per-pair cap the extra rows are dead weight: Get() collapses a
	-- pair to a single vote anyway, so storing more only feeds a wash-trader's
	-- ability to bloat the shard.
	if countPair(list, pairKey(buyerUserId, sellerUserId)) >= MAX_PER_PAIR then
		return false
	end
	table.insert(list, obs)
	while #list > MAX_OBS_PER_ITEM do
		table.remove(list, 1)
	end

	local queue = pending[key]
	if not queue then
		queue = {}
		pending[key] = queue
	end
	table.insert(queue, obs)
	pendingCount += 1
	return true
end

-- Returns median, sampleCount for the last 7 days.
-- Returns nil, sampleCount while the sample is below MIN_SAMPLES -- the count is
-- still handed back so a UI can honestly say "3 of 5 sales needed" rather than
-- inventing a price. Never yields.
function PriceIndex.Get(name, mutation)
	if type(name) ~= "string" then return nil, 0 end
	if mutation ~= nil and type(mutation) ~= "string" then return nil, 0 end

	local list = index[itemKey(name, mutation)]
	if not list then return nil, 0 end

	local cutoff = os.time() - WINDOW
	local live = {}
	for _, o in ipairs(list) do
		if o.T >= cutoff then
			table.insert(live, o)
		end
	end
	table.sort(live, function(a, b) return a.T < b.T end)

	-- One vote per counterparty pair, and it is their EARLIEST trade. Keeping
	-- the earliest rather than the latest matters: it means a pair cannot keep
	-- re-trading to steer the value of the single vote they are allowed.
	local seen, prices = {}, {}
	for _, o in ipairs(live) do
		local pk = pairKey(o.B, o.S)
		if not seen[pk] then
			seen[pk] = true
			table.insert(prices, o.P)
		end
	end

	local n = #prices
	if n < MIN_SAMPLES then
		return nil, n
	end

	table.sort(prices)
	local mid = math.floor(n / 2)
	local median
	if n % 2 == 1 then
		median = prices[mid + 1]
	else
		median = (prices[mid] + prices[mid + 1]) / 2
	end
	return math.floor(median + 0.5), n
end

function PriceIndex.Init()
	-- Non-blocking on purpose: Main runs every Init() in sequence, so a cold
	-- DataStore read must not hold up the rest of the server's boot. Until the
	-- first load lands Get() reports "not enough data", which is already the
	-- right answer for a server that has not seen any sales yet.
	--
	-- Flush and reload share ONE coroutine so they can never overlap.
	task.spawn(function()
		guarded(loadAll)
		local sinceRefresh = 0
		while true do
			task.wait(FLUSH_SECONDS)
			guarded(flush)
			sinceRefresh += FLUSH_SECONDS
			if sinceRefresh >= REFRESH_SECONDS then
				sinceRefresh = 0
				guarded(loadAll)
			end
		end
	end)

	game:BindToClose(function()
		local waited = 0
		while busy and waited < 5 do
			task.wait(0.1)
			waited += 0.1
		end
		guarded(flush) -- don't lose the last few sales on shutdown
	end)

	print(("PriceIndex online (%d-day median, min %d sales)"):format(PriceIndex.WindowDays, MIN_SAMPLES))
end

return PriceIndex
