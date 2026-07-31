-- MintRegistry: verifiable identity for the brainrots that are worth arguing over.
--
-- Every catch worth tracking is stamped with a SERIAL -- its mint number inside
-- its own (Name, Mutation) class -- and each class carries a live EXISTS count
-- (minted minus burned). Together they turn "a Golden Cappuccino Assassino" into
-- "#47, and only 312 still exist": a number a trade can actually be argued
-- against, and the thing that makes a rare catch feel OWNED rather than farmed.
--
-- ========================= WHY IT IS BUILT THIS WAY ==========================
-- Two requirements pull against each other:
--
--   1. A serial must be unique across EVERY live server. Two servers both handing
--      out #47 for the same class destroys the entire point of a serial.
--   2. The catch path must never yield on, or fail because of, a DataStore. A
--      player who lands a Secret gets their Secret -- the serial is a garnish.
--
-- So serials are NOT allocated one call at a time. Each server RESERVES a block
-- of serials per class in a single UpdateAsync, then hands them out from memory
-- with zero yields, refilling the block in the background before it runs dry.
-- The stored allocator high-water mark (`a`) only ever moves forward, so two
-- servers can never be handed overlapping blocks -- that is what buys uniqueness
-- without a round trip per catch.
--
-- Deliberate consequence: a server that reserves 4 and uses 1 leaves a gap, so
-- serial numbers can run slightly AHEAD of the true mint count. That is the right
-- trade -- Get() reports honest minted/exists counts separately, a gap in the
-- numbering costs nothing, whereas a duplicate serial or a catch stuck behind a
-- DataStore call would cost everything. Gaps are kept small two ways: block size
-- tracks observed demand, and unused block tails are handed BACK at shutdown
-- (safe, because the rollback only applies when nobody else has allocated since).
--
-- Every DataStore touch is pcall'd and the module is fail-open: in Studio without
-- API access every call errors, and the correct behaviour there is simply that no
-- serials appear. Mint() returns nil, nothing throws, nothing blocks a catch, and
-- a global backoff stops a dead store from being hammered.
--
-- WIRING -- ServerScriptService.Main needs:
--     local MintRegistry = require(ServerScriptService.Modules.MintRegistry)
--     MintRegistry.Init()
-- Init() is idempotent AND self-starts on first use, so a missed wire-up costs
-- nothing; the explicit call just makes the lifecycle obvious next to the others.

local DataStoreService = game:GetService("DataStoreService")

local MintRegistry = {}

--================================= tuning ==================================--
local STORE_NAME     = "BrainrotMint_v1"
local FLUSH_INTERVAL = 60    -- seconds between flushes of dirty classes
local RESERVE_MIN    = 4     -- smallest serial block a class may reserve
local RESERVE_MAX    = 64    -- largest, so one hot class cannot hoard numbers
local REFILL_AT      = 1     -- reserve the next block once this many remain
local REQUEST_GAP    = 0.35  -- min seconds between DataStore calls (budget guard)
local KEY_COOLDOWN   = 6     -- DataStore throttles repeat WRITES to the same key
local KEY_BACKOFF    = 20    -- per-class cooldown after a failed request
local MAX_KEYS       = 600   -- soft cap on cached classes
local CLOSE_DEADLINE = 20    -- seconds we are willing to spend inside BindToClose
local CLOSE_LANES    = 8     -- parallel requests during shutdown

-- Classes worth a serial: the top tiers, or ANY mutation. Commons would
-- flood the store with keys nobody will ever quote in a trade.
local TRACKED_TIERS = { Legendary = true, Mythic = true, Secret = true, God = true }

--============================== store handle ===============================--
-- GetDataStore itself throws when the place has no API access, so even this is
-- guarded. A nil store means "registry offline": every public call still answers,
-- just without numbers.
local store
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then store = result end
end

--================================= state ===================================--
-- cache[key] = {
--   Key, Minted, Burned,        -- global totals as of the last successful sync
--   Used, PendingBurn,          -- committed locally, not yet written
--   Next, BlockEnd,             -- the serial block we are handing out from
--   PendNext, PendEnd,          -- spare block, promoted when the active one dries
--   Want,                       -- block size requested on the next request
--   Demand,                     -- mints since the last reservation (block sizing)
--   Known, Busy, Touch,
--   NextTry,                    -- backoff after a FAILURE (gated keys are dropped)
--   NoWriteBefore,              -- same-key write throttle (gated keys are requeued)
-- }
local cache = {}
local keyCount = 0

local queue, queued = {}, {}
local started = false
local closing = false
local failStreak = 0
local globalGate = 0   -- os.clock() before which we make no DataStore calls at all
local warned = false

local ensureStarted   -- forward declaration; defined next to Init()

local function now()
	return os.clock()
end

--=============================== key naming ================================--
-- djb2, folded every step so it stays well inside float precision.
local function hash32(s)
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 4294967291
	end
	return h
end

-- DataStore keys cap at 50 characters. Names and mutations are alphanumeric with
-- spaces today, so the readable form survives untouched ("Tung Tung Sahur|Golden")
-- which makes the store legible when auditing supply by hand. Anything longer or
-- stranger falls back to a truncated form plus a hash so it stays collision-safe.
local function classKey(name, mutation)
	local raw = name .. "|" .. (mutation or "-")
	local safe = (raw:gsub("[^%w %-_%.|]", "_"))
	if #safe <= 50 then return safe end
	return string.sub(safe, 1, 39) .. "_" .. string.format("%010d", hash32(raw))
end

--============================== cache helpers ==============================--
-- Drop the coldest classes that hold nothing worth keeping (no unwritten mints,
-- no burns, no reserved block). Anything with unflushed state is never evicted --
-- losing it would lose real supply data.
local lastEvict = -math.huge
local function evictCold()
	-- Rate-limited: if every cached class is dirty there are no victims, and
	-- without this the sweep would re-run (and re-sort) on every single catch.
	-- Overshooting MAX_KEYS for a while is far cheaper than that.
	if now() - lastEvict < 30 then return end
	lastEvict = now()

	local victims = {}
	for _, entry in pairs(cache) do
		if not entry.Busy
			and (entry.Used or 0) == 0
			and (entry.PendingBurn or 0) == 0
			and not entry.Next
			and not entry.PendNext then
			victims[#victims + 1] = entry
		end
	end
	table.sort(victims, function(a, b) return a.Touch < b.Touch end)
	for i = 1, math.min(math.floor(MAX_KEYS * 0.25), #victims) do
		cache[victims[i].Key] = nil
		keyCount -= 1
	end
end

local function getEntry(name, mutation)
	if type(name) ~= "string" or name == "" then return nil end
	if type(mutation) ~= "string" or mutation == "" then mutation = nil end

	local key = classKey(name, mutation)
	local entry = cache[key]
	if not entry then
		if keyCount >= MAX_KEYS then evictCold() end
		entry = {
			Key = key, Minted = 0, Burned = 0,
			Used = 0, PendingBurn = 0,
			Want = 0, Demand = 0,
			Known = false, Busy = false, NextTry = 0,
			Touch = now(),
		}
		cache[key] = entry
		keyCount += 1
	end
	entry.Touch = now()
	return entry
end

local function enqueue(entry)
	if not store or closing then return end
	if now() < globalGate then return end   -- store is in backoff; do not pile up work
	if queued[entry.Key] then return end
	queued[entry.Key] = true
	queue[#queue + 1] = entry.Key
	ensureStarted()
end

local function remaining(entry)
	local n = 0
	if entry.Next and entry.BlockEnd then
		n += math.max(0, entry.BlockEnd - entry.Next + 1)
	end
	if entry.PendNext and entry.PendEnd then
		n += math.max(0, entry.PendEnd - entry.PendNext + 1)
	end
	return n
end

-- Ask for the next block. Sized at twice the demand seen since the last
-- reservation, so a class nobody catches stays at RESERVE_MIN (tiny gaps) while a
-- hot class stops needing a round trip every few catches.
local function wantBlock(entry)
	if entry.PendNext then return end          -- already holding a spare
	if (entry.Want or 0) > 0 then return end   -- already asked
	entry.Want = math.clamp(math.floor((entry.Demand or 0) * 2), RESERVE_MIN, RESERVE_MAX)
	enqueue(entry)
end

local function takeSerial(entry)
	if not (entry.Next and entry.BlockEnd and entry.Next <= entry.BlockEnd) then
		if entry.PendNext then
			entry.Next, entry.BlockEnd = entry.PendNext, entry.PendEnd
			entry.PendNext, entry.PendEnd = nil, nil
		end
	end
	if entry.Next and entry.BlockEnd and entry.Next <= entry.BlockEnd then
		local serial = entry.Next
		entry.Next = serial + 1
		entry.Used = (entry.Used or 0) + 1
		return serial
	end
	return nil
end

--============================== the one request ============================--
-- Commits everything this server owes for one class in a SINGLE UpdateAsync:
-- mints used, burns recorded, a new block reserved, and (on shutdown) unused
-- block tails handed back. Stored record is { a = allocated, m = minted, b = burned }.
local function processKey(key, isClose)
	local entry = cache[key]
	if not entry or not store then return end
	if entry.Busy then return end   -- the flush timer and BindToClose can collide

	local used = entry.Used or 0
	local burn = entry.PendingBurn or 0
	local want = entry.Want or 0

	-- On shutdown, give back serials we reserved but never issued. Taken BEFORE
	-- the yield and cleared immediately, so a catch landing mid-shutdown gets no
	-- serial rather than one we are in the middle of releasing.
	local ranges
	if isClose then
		want = 0
		ranges = {}
		if entry.PendNext and entry.PendNext <= entry.PendEnd then
			ranges[#ranges + 1] = { entry.PendNext, entry.PendEnd }
		end
		if entry.Next and entry.Next <= entry.BlockEnd then
			ranges[#ranges + 1] = { entry.Next, entry.BlockEnd }
		end
		entry.Next, entry.BlockEnd = nil, nil
		entry.PendNext, entry.PendEnd = nil, nil
	end

	local hasWork = used > 0 or burn > 0 or want > 0 or not entry.Known
		or (ranges ~= nil and #ranges > 0)
	if not hasWork then return end

	entry.Busy = true
	local result
	local ok, err = pcall(function()
		store:UpdateAsync(key, function(old)
			-- NOTE: this transform can be re-run on conflict, so it must derive
			-- everything from `old` plus the captured constants and must never
			-- mutate captured state (hence the local `taken` below).
			local a, m, b = 0, 0, 0
			if type(old) == "table" then
				a = tonumber(old.a) or 0
				m = tonumber(old.m) or 0
				b = tonumber(old.b) or 0
			end

			local changed = false
			if used > 0 then m += used; changed = true end
			if burn > 0 then b += burn; changed = true end
			if a < m then a = m; changed = true end

			-- roll the allocator back over any tail that is still the top of the
			-- range, repeatedly, so two adjacent blocks both come back
			if ranges and #ranges > 0 then
				local taken = {}
				local swept = true
				while swept do
					swept = false
					for i = 1, #ranges do
						local r = ranges[i]
						if not taken[i] and r[2] == a and (r[1] - 1) >= m then
							a = r[1] - 1
							taken[i] = true
							swept = true
							changed = true
						end
					end
				end
			end

			local blockStart, blockEnd
			if want > 0 then
				blockStart = a + 1
				blockEnd = a + want
				a = blockEnd
				changed = true
			end

			result = { a = a, m = m, b = b, s = blockStart, e = blockEnd }
			if not changed then return nil end   -- pure read: cancel the write
			return { a = a, m = m, b = b }
		end)
	end)
	entry.Busy = false

	if ok then
		failStreak = 0
		entry.NextTry = 0
		-- a pure read (nothing to commit) cancels the write, so it costs no quota
		-- and needs no cooldown; anything that actually wrote does
		if used > 0 or burn > 0 or want > 0 or (ranges ~= nil and #ranges > 0) then
			entry.NoWriteBefore = now() + KEY_COOLDOWN
		end
		-- subtract only what we actually committed: anything Mint/Burn added while
		-- the call was in flight stays pending for the next flush
		entry.Used = math.max(0, (entry.Used or 0) - used)
		entry.PendingBurn = math.max(0, (entry.PendingBurn or 0) - burn)
		if want > 0 then
			entry.Want = 0
			entry.Demand = 0
		end
		if result then
			entry.Minted = result.m
			entry.Burned = result.b
			entry.Known = true
			if result.s then
				if entry.Next and entry.BlockEnd and entry.Next <= entry.BlockEnd then
					entry.PendNext, entry.PendEnd = result.s, result.e
				else
					entry.Next, entry.BlockEnd = result.s, result.e
				end
			end
		end
	else
		failStreak += 1
		entry.NextTry = now() + KEY_BACKOFF
		globalGate = now() + math.min(4 * (2 ^ math.min(failStreak, 6)), 300)
		if not warned then
			warned = true
			warn("[MintRegistry] DataStore unavailable (" .. tostring(err)
				.. "); catches will be granted WITHOUT serials until it recovers")
		end
	end
end

--============================ background workers ===========================--
local function worker()
	while not closing do
		local key = table.remove(queue, 1)
		if not key then
			task.wait(0.5)
		else
			queued[key] = nil
			local entry = cache[key]
			if not entry or not store then
				task.wait(0.05)
			elseif now() < globalGate or now() < (entry.NextTry or 0) then
				-- failure backoff (up to 300s): DROP rather than requeue. The unflushed
				-- state stays on the entry and the flush timer picks it up again, so a
				-- dead store can never spin this loop.
				task.wait(0.25)
			elseif now() < (entry.NoWriteBefore or 0) then
				-- same-key write throttle (<=6s): requeue, since a block refill waiting a
				-- whole flush cycle would starve a hot class of serials. Bounded by
				-- KEY_COOLDOWN, so this cannot spin for long.
				queued[key] = true
				queue[#queue + 1] = key
				task.wait(0.15)
			else
				pcall(processKey, key, false)
				task.wait(REQUEST_GAP)
			end
		end
	end
end

local function flushLoop()
	while not closing do
		task.wait(FLUSH_INTERVAL)
		for _, entry in pairs(cache) do
			if (entry.Used or 0) > 0 or (entry.PendingBurn or 0) > 0 or (entry.Want or 0) > 0 then
				enqueue(entry)
			end
		end
	end
end

-- Shutdown flush. Bounded on purpose: BindToClose gets ~30s total and the rest of
-- the game needs some of it, so we work in parallel lanes against a deadline and
-- accept losing the tail rather than stalling the shutdown.
local function flushAll()
	if not store then return end
	closing = true

	local pending = {}
	for key, entry in pairs(cache) do
		if (entry.Used or 0) > 0
			or (entry.PendingBurn or 0) > 0
			or (entry.Next and entry.BlockEnd and entry.Next <= entry.BlockEnd)
			or (entry.PendNext and entry.PendEnd and entry.PendNext <= entry.PendEnd) then
			pending[#pending + 1] = key
		end
	end
	if #pending == 0 then return end

	local deadline = now() + CLOSE_DEADLINE
	local index = 0
	local active = 0
	for _ = 1, math.min(CLOSE_LANES, #pending) do
		active += 1
		task.spawn(function()
			while now() < deadline do
				index += 1                      -- no yield between these two lines,
				local key = pending[index]      -- so lanes never take the same key
				if not key then break end
				pcall(processKey, key, true)
			end
			active -= 1
		end)
	end
	while active > 0 and now() < deadline + 2 do
		task.wait(0.1)
	end
end

--================================ public API ===============================--

-- Is this catch worth a serial at all? Callers that BURN brainrots (fusion,
-- offerings) should gate MintRegistry.Burn on the same answer, so burns are only
-- recorded for classes that were actually minted.
function MintRegistry.IsTracked(rarityName, mutation)
	if type(mutation) == "string" and mutation ~= "" then return true end
	return TRACKED_TIERS[rarityName] == true
end

-- Warm a class's serial block WITHOUT yielding. Call this the moment you know
-- what is going to be caught; by the time Mint() runs the number is already in
-- memory. Optional -- Mint() works without it, it just misses more often.
function MintRegistry.Prepare(name, mutation)
	if not store then return end
	local entry = getEntry(name, mutation)
	if not entry then return end
	if remaining(entry) <= REFILL_AT then wantBlock(entry) end
end

-- Issue the next serial for this class, or nil if the registry has nothing
-- reserved (cold class, or DataStore down). NEVER yields and NEVER errors:
-- a nil return means "no serial this time", never "no catch this time".
function MintRegistry.Mint(name, mutation)
	local entry = getEntry(name, mutation)
	if not entry then return nil end

	local serial = takeSerial(entry)
	entry.Demand = (entry.Demand or 0) + 1   -- counts misses too, so a class that
	                                         -- keeps missing gets a bigger block
	if store and remaining(entry) <= REFILL_AT then wantBlock(entry) end
	return serial
end

-- Record that `count` (default 1) copies of this class were destroyed. Batched:
-- it only touches memory, and rides the next flush.
function MintRegistry.Burn(name, mutation, count)
	local entry = getEntry(name, mutation)
	if not entry then return end
	local n = math.floor(tonumber(count) or 1)
	if n < 1 then return end
	entry.PendingBurn = (entry.PendingBurn or 0) + n
end

-- minted, exists -- for display. Returns nil, nil when this class has never been
-- read successfully (cold cache or offline store) so UI can hide the line rather
-- than print a confident zero. A background read is kicked off, so asking again
-- shortly afterwards answers.
function MintRegistry.Get(name, mutation)
	local entry = getEntry(name, mutation)
	if not entry then return nil, nil end
	if not entry.Known then
		enqueue(entry)
		return nil, nil
	end
	local minted = entry.Minted + (entry.Used or 0)
	local burned = entry.Burned + (entry.PendingBurn or 0)
	return minted, math.max(0, minted - burned)
end

function MintRegistry.Init()
	if started then return end
	started = true
	task.spawn(worker)
	task.spawn(flushLoop)
	pcall(function()
		game:BindToClose(function()
			pcall(flushAll)
		end)
	end)
end

ensureStarted = function()
	if not started then MintRegistry.Init() end
end

return MintRegistry
