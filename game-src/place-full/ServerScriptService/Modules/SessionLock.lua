-- SessionLock: makes a profile owned by exactly one live server at a time.
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
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local M = {}

-- MUST match PlayerDataManager exactly, or the lock guards nothing.
local STORE_NAME = "BrainrotSkip_PlayerData_v1"
local KEY_PREFIX = "Player_"
local store = DataStoreService:GetDataStore(STORE_NAME)

local JOB = game.JobId ~= "" and game.JobId or ("studio-" .. tostring(os.clock()))
local PLACE = game.PlaceId

-- A server that crashes never releases its lock, so a lock has to be able to die of
-- old age. 90s is comfortably longer than the 30s heartbeat: a live server always
-- refreshes well inside the window, a dead one is reclaimable within a minute and a half.
local STALE_AFTER = 90
local HEARTBEAT = 30
local CLAIM_TRIES = 6
local CLAIM_WAIT = 2

-- STUDIO-ONLY TEST SEAM (2026-09-21, onboarding round). A Studio playtest always
-- loads the Studio account's REAL profile, so a truly fresh profile -- and a
-- rejoin against it -- could not be tested without touching the real save. In
-- Studio only, a non-empty string in the ServerStorage attribute
-- `ProfileKeySuffix` is appended to the key (`Player_<uid>_qa1`), which is a
-- separate row in the same store: fresh when it does not exist, persistent
-- across Play sessions, and never the owner's real row. Live servers never read
-- the attribute (IsStudio() is false there), and an empty/absent attribute is
-- the unchanged key. CLEAR THE ATTRIBUTE (set it to nil) when a test session is
-- over: it lives in the place file, and a leftover suffix would quietly load the
-- wrong profile in the owner's next playtest.
local function keySuffix()
	if not RunService:IsStudio() then return "" end
	local s = ServerStorage:GetAttribute("ProfileKeySuffix")
	return (type(s) == "string") and s or ""
end
local function key(userId) return KEY_PREFIX .. userId .. keySuffix() end
local function held(sess)
	return sess and sess.job and sess.job ~= JOB and (os.time() - (sess.t or 0)) < STALE_AFTER
end

M.owned = {}          -- [userId] = true while this server holds the lock

-- Claim the profile and return it in the same transaction.
-- Returns: data, status   where status is "ok" | "new" | "locked" | "error"
-- On "locked" or "error" the caller MUST treat the session as read-only.
function M.Claim(userId)
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
					d = { __sessionNew = true }      -- marker only; caller supplies real defaults
				else
					status = "ok"
				end
				d.__session = { job = JOB, t = os.time(), place = PLACE }
				out = d
				return d
			end)
		end)
		if ok and status ~= "locked" then
			M.owned[userId] = true
			return out, status
		end
		if not ok then
			status = "error"
			warn(("[SessionLock] claim error for %d: %s"):format(userId, tostring(err)))
		end
		if attempt < CLAIM_TRIES then task.wait(CLAIM_WAIT) end
	end
	return nil, status or "error"
end

-- Write the profile, but only while we still hold the lock. If another server has
-- taken it we are the stale session and writing would roll their progress back.
function M.Save(userId, data)
	if not data or data.__noSave then return false end
	local wrote = false
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			store:UpdateAsync(key(userId), function(oldData)
				if oldData and held(oldData.__session) then
					return nil                       -- lock stolen: refuse, do not clobber
				end
				data.__session = { job = JOB, t = os.time(), place = PLACE }
				wrote = true
				return data
			end)
		end)
		if ok then return wrote end
		if attempt == 3 then
			warn(("[SessionLock] save FAILED for %d: %s"):format(userId, tostring(err)))
		else
			task.wait(0.4 * attempt)
		end
	end
	return false
end

-- Final write + hand the profile back. Call this BEFORE TeleportAsync, and await it,
-- so the destination server's Claim finds an unlocked profile with current data.
function M.Release(userId, data)
	local released = false
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
	if not ok then
		warn(("[SessionLock] release error for %d: %s"):format(userId, tostring(err)))
	end
	M.owned[userId] = nil
	return released
end

-- Keeps our locks from ageing out while the player is still here. Cheap: one
-- UpdateAsync per player per 30s, well inside DataStore budgets.
function M.StartHeartbeat(getData)
	task.spawn(function()
		while true do
			task.wait(HEARTBEAT)
			for userId in pairs(M.owned) do
				local data = getData and getData(userId)
				if data and not data.__noSave then
					pcall(function()
						store:UpdateAsync(key(userId), function(oldData)
							if oldData and held(oldData.__session) then return nil end
							local d = oldData or data
							d.__session = { job = JOB, t = os.time(), place = PLACE }
							return d
						end)
					end)
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
-- comfortably fits for any realistic server size.
function M.ReleaseAll(getData)
	local ids = {}
	for userId in pairs(M.owned) do table.insert(ids, userId) end
	for _, userId in ipairs(ids) do
		local data = getData and getData(userId)
		pcall(M.Release, userId, data)
	end
	return #ids
end

M.JobId = JOB
M.StaleAfter = STALE_AFTER
return M
