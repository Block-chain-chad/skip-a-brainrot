-- SessionLock: makes a profile owned by exactly one live server at a time, and is the
-- ONE place every write to a player's DataStore key goes through.
--
-- WHY THIS EXISTS. World 2 is moving to its own Place in this universe, so a player
-- will cross servers mid-session. Both places read the same DataStore key, and the
-- destination server can finish its load BEFORE the origin server's save lands. The
-- player then arrives as their older self while everything they spent still exists --
-- that is the classic cross-place duplication bug, and with trading, booth sales and
-- a price index it would poison the economy rather than just inconvenience one player.
--
-- The fix is to make the read and the claim ONE transaction. Everything here goes
-- through UpdateAsync on the same key PlayerDataManager uses, because a lock kept
-- anywhere else can always disagree with the profile it is supposed to be guarding.
--
-- Returning nil from an UpdateAsync transform cancels the write. That is how a claim
-- refuses without touching the stored profile.
--
-- WRITES (2026-09-21 data-safety hotfix). Three rules, all enforced in here:
--   1. One transaction per profile at a time (`hold` below). An autosave, a trade's save
--      and the leave write can no longer overlap or land out of order.
--   2. Save refuses once the profile has been released. A late write used to re-stamp
--      the lock on a profile the next server was already claiming -- which is what
--      "profile held by another live server" on nearly every Studio Stop -> Play was.
--   3. The periodic write is a FULL save of the live profile (StartAutosave), staggered
--      across players, and refreshing the lock is a side effect of it. The old
--      heartbeat wrote `oldData` back with a fresh timestamp: it kept the lock alive and
--      persisted nothing, so a crashed server lost the whole session.
local DataStoreService = game:GetService("DataStoreService")

local M = {}

-- MUST match PlayerDataManager exactly, or the lock guards nothing.
local STORE_NAME = "BrainrotSkip_PlayerData_v1"
local KEY_PREFIX = "Player_"
local store = DataStoreService:GetDataStore(STORE_NAME)

local JOB = game.JobId ~= "" and game.JobId or ("studio-" .. tostring(os.clock()))
local PLACE = game.PlaceId

-- A server that crashes never releases its lock, so a lock has to be able to die of
-- old age. 90s is three times the autosave interval: a live server always refreshes
-- well inside the window, a dead one is reclaimable within a minute and a half.
local STALE_AFTER = 90
local CLAIM_TRIES = 6

-- Read live, never cached, so a test can shrink them; production leaves these alone.
M.Tuning = {
	AutosaveEvery = 30, -- seconds between periodic writes of ONE profile. This is also the
	                    -- lock refresh, so it must stay well under STALE_AFTER (3x margin).
	Tick = 1,           -- how often the loop looks for a profile that is due
	MinGap = 6,         -- never write one profile twice inside this window: DataStore queues
	                    -- same-key writes closer than 6s, and a trade's save that just landed
	                    -- makes the periodic one pointless anyway
	RetryAfter = 10,    -- a periodic write that failed is retried after this, not next tick
	BudgetFloor = 10,   -- UpdateAsync budget the loop leaves for trades, receipts and leaves
	ClaimWait = 2,      -- between claim attempts while another server holds the profile
	SaveBackoff = 0.4,  -- base wait between write attempts (x attempt number)
	HoldTimeout = 15,   -- how long a write waits for an in-flight one on the same profile
}

local function key(userId) return KEY_PREFIX .. userId end
local function held(sess)
	return sess and sess.job and sess.job ~= JOB and (os.time() - (sess.t or 0)) < STALE_AFTER
end
local function stamp() return { job = JOB, t = os.time(), place = PLACE } end

M.owned = {}          -- [userId] = true while this server holds the lock
M.nextDue = {}        -- [userId] = os.clock() at which the next periodic write is due
M.lastWrite = {}      -- [userId] = os.clock() of the last write that landed, any path
M.closing = false     -- set by ReleaseAll: the loop starts no new writes once shutdown began

-- Per-profile turnstile. UpdateAsync on one key from two threads is not ordered: the
-- second call can land first, and then the stale state wins. A profile's writes wait
-- for each other instead. The timeout is only for a DataStore call that has hung --
-- the caller decides whether to go ahead without the turnstile (Release does, Save
-- does not).
local busy = {}
local function hold(userId)
	local deadline = os.clock() + M.Tuning.HoldTimeout
	while busy[userId] do
		if os.clock() > deadline then return false end
		task.wait(0.05)
	end
	busy[userId] = true
	return true
end
local function drop(userId) busy[userId] = nil end

-- True while a transaction on this profile is in flight (diagnostics and tests).
function M.IsWriting(userId) return busy[userId] == true end

local function scheduled(userId, delay)
	local now = os.clock()
	M.lastWrite[userId] = now
	M.nextDue[userId] = now + delay
end

-- Claim the profile and return it in the same transaction.
-- `defaults` builds a brand-new profile; it is called inside the transform (possibly
-- more than once, UpdateAsync retries on conflict) and must be pure.
-- Returns: data, status   where status is "ok" | "new" | "locked" | "error"
-- On "locked" or "error" the caller MUST treat the session as read-only.
function M.Claim(userId, defaults)
	if M.closing then return nil, "error" end     -- joining a server that is going down
	if not hold(userId) then
		-- a leave write for the same profile has hung (rejoin on the same server); the
		-- load cannot wait forever, and the transaction below re-reads whatever landed
		warn(("[SessionLock] claim for %d went ahead past a stuck write"):format(userId))
	end
	local out, status
	for attempt = 1, CLAIM_TRIES do
		local ok, err = pcall(function()
			store:UpdateAsync(key(userId), function(oldData)
				if oldData and held(oldData.__session) then
					status = "locked"
					return nil                       -- cancel: someone else is live on this profile
				end
				local d = oldData
				if d == nil then
					status = "new"
					-- A REAL default profile, not a marker. The marker this used to write
					-- ({ __sessionNew = true }) was replaced only by the first full save,
					-- so a first session that died before saving left it in storage, and
					-- the next load took it for an existing profile with no Cash.
					d = (defaults and defaults()) or {}
				else
					status = "ok"
				end
				d.__session = stamp()
				out = d
				return d
			end)
		end)
		if ok and status ~= "locked" then
			M.owned[userId] = true
			-- First periodic write lands somewhere in the second three quarters of the
			-- interval, so a join burst (server start) does not turn into a save burst.
			scheduled(userId, M.Tuning.AutosaveEvery * (0.25 + 0.75 * math.random()))
			drop(userId)
			return out, status
		end
		if not ok then
			status = "error"
			warn(("[SessionLock] claim error for %d: %s"):format(userId, tostring(err)))
		end
		if attempt < CLAIM_TRIES then task.wait(M.Tuning.ClaimWait) end
	end
	drop(userId)
	return nil, status or "error"
end

-- Write the profile, but only while we still hold the lock. If another server has
-- taken it we are the stale session and writing would roll their progress back.
-- Returns true when the write landed. On false the second value says why:
--   "nosave"  read-only session (load failed or profile held elsewhere)
--   "unowned" this server has released the profile (teleport window, after shutdown)
--   "busy"    a transaction on this profile hung past HoldTimeout
--   "stolen"  another live server holds the profile now
--   "error"   the DataStore refused three attempts
function M.Save(userId, data)
	if not data or data.__noSave then return false, "nosave" end
	if not M.owned[userId] then return false, "unowned" end
	if not hold(userId) then return false, "busy" end
	if not M.owned[userId] then drop(userId); return false, "unowned" end   -- released while we waited
	local wrote, reason = false, "error"
	for attempt = 1, 3 do
		wrote = false
		local ok, err = pcall(function()
			store:UpdateAsync(key(userId), function(oldData)
				if oldData and held(oldData.__session) then
					reason = "stolen"
					return nil                       -- lock stolen: refuse, do not clobber
				end
				data.__session = stamp()
				wrote = true
				return data
			end)
		end)
		if ok then break end
		if attempt == 3 then
			warn(("[SessionLock] save FAILED for %d: %s"):format(userId, tostring(err)))
		else
			task.wait(M.Tuning.SaveBackoff * attempt)
		end
	end
	if wrote then scheduled(userId, M.Tuning.AutosaveEvery) end
	drop(userId)
	if wrote then return true end
	return false, reason
end

-- Ask the loop to write this profile on its next tick (a milestone: rebirth, a capped
-- mint, a big purchase). Cheaper than an inline Save and coalesces: ten milestones in
-- one second are one write.
function M.MarkDue(userId)
	if M.owned[userId] then M.nextDue[userId] = 0 end
end

-- Final write + hand the profile back. Call this BEFORE TeleportAsync, and await it,
-- so the destination server's Claim finds an unlocked profile with current data.
-- Ownership is dropped BEFORE the write: from that moment Save refuses, so nothing can
-- re-stamp the lock behind this write.
function M.Release(userId, data)
	if not hold(userId) then
		warn(("[SessionLock] release for %d went ahead past a stuck write"):format(userId))
	end
	M.owned[userId] = nil
	M.nextDue[userId] = nil
	M.lastWrite[userId] = nil
	local released, lastErr = false, nil
	for attempt = 1, 3 do
		released, lastErr = false, nil
		local ok, err = pcall(function()
			store:UpdateAsync(key(userId), function(oldData)
				if oldData and held(oldData.__session) then return nil end
				local d = data or oldData
				if not d then return nil end
				if not d.__noSave then
					d.__session = nil                    -- unlocked, ready for the next server
					released = true
					return d
				end
				return nil
			end)
		end)
		if ok then break end
		lastErr = err
		if attempt < 3 then task.wait(M.Tuning.SaveBackoff * attempt) end
	end
	if lastErr and not released then
		warn(("[SessionLock] release FAILED for %d: %s"):format(userId, tostring(lastErr)))
	end
	drop(userId)
	return released
end

-- The periodic writer. One loop for the server; each tick it writes the ONE profile
-- that has waited longest (two or three only on a server with more players than
-- seconds in the interval), so N players cost N writes per interval spread over the
-- interval rather than a burst. `prepare(userId)` hands back the live profile to write,
-- or nil to skip.
--
-- Failure is contained: a write that does not land leaves the in-memory profile
-- exactly as it was (the transform only reads it), is retried after RetryAfter, and a
-- profile whose lock was stolen is refused inside the transaction like any other save.
function M.StartAutosave(prepare)
	task.spawn(function()
		while not M.closing do
			task.wait(M.Tuning.Tick)
			if M.closing then break end
			local now = os.clock()
			local count, due = 0, {}
			for userId in pairs(M.owned) do
				count += 1
				if (M.nextDue[userId] or 0) <= now
					and not busy[userId]
					and now - (M.lastWrite[userId] or 0) >= M.Tuning.MinGap then
					table.insert(due, userId)
				end
			end
			if #due > 0 then
				table.sort(due, function(a, b) return (M.nextDue[a] or 0) < (M.nextDue[b] or 0) end)
				local perTick = math.max(1, math.ceil(count * M.Tuning.Tick / M.Tuning.AutosaveEvery))
				for i = 1, math.min(perTick, #due) do
					if M.closing then break end
					local budget = DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
					if budget < M.Tuning.BudgetFloor then
						break   -- starved: leave what is left for trades and receipts, look again next tick
					end
					local userId = due[i]
					local data = prepare and prepare(userId)
					if data and not data.__noSave and M.owned[userId] then
						local ok, why = M.Save(userId, data)
						if not ok and M.owned[userId] then
							M.nextDue[userId] = os.clock() + M.Tuning.RetryAfter
							warn(("[SessionLock] autosave for %d did not land (%s); retry in %ss")
								:format(userId, tostring(why), tostring(M.Tuning.RetryAfter)))
						end
					end
				end
			end
		end
	end)
end

-- SHUTDOWN. Without this, a server that stops (including Studio's Stop button, which
-- does fire BindToClose) leaves its locks looking live for the full stale window, and the
-- next session to load that profile gets a read-only one. In Studio that is every single
-- Stop -> Play cycle, because JobId is empty there so each run counts as a new server.
--
-- Roblox gives BindToClose up to 30s; releasing N profiles is N UpdateAsync calls, so this
-- comfortably fits for any realistic server size. The loop is told to stop first, and
-- Release drops ownership before its write, so no periodic or transactional save can
-- land after the final one.
function M.ReleaseAll(prepare)
	M.closing = true
	local ids = {}
	for userId in pairs(M.owned) do table.insert(ids, userId) end
	for _, userId in ipairs(ids) do
		local data = prepare and prepare(userId)
		pcall(M.Release, userId, data)
	end
	return #ids
end

M.JobId = JOB
M.StaleAfter = STALE_AFTER
return M
