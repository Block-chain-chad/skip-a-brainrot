-- DATA-SAFETY HOTFIX TEST HARNESS (C1 periodic persistence / C2 profile normalisation).
--
-- Runs inside Studio's Edit-mode execute_luau VM against a MOCK DataStoreService, so no
-- test ever reads or writes a production key. The module sources under test arrive as
-- strings (pulled from the local bridge, see README.md) and are loaded with loadstring
-- into an environment whose `game` hands out the fake DataStoreService, a fake
-- Workspace (no PlayerBases -> no plot side effects) and captures BindToClose; `os.time`
-- is a shared fake clock so lock staleness can be driven; everything else is real.
--
--   fn(variant, sources)   variant = "live" | "new"
--                          sources = { SessionLock = <src>, PlayerDataManager = <src> }
--
-- Returns a text report. Tests that need APIs the live variant does not have report
-- "n/a" there; that is expected -- the live run exists to show which tests FAIL before
-- the fix.
local variant, SRC = ...
assert(type(SRC) == "table" and SRC.SessionLock and SRC.PlayerDataManager, "harness: sources missing")

local HS = game:GetService("HttpService")
local realWarn = warn

-- Fast tunings for the new module (read live by the loop). Production is 30/1/6/10.
local TUNING = {
	AutosaveEvery = 0.5, Tick = 0.1, MinGap = 0.1, RetryAfter = 0.4, BudgetFloor = 10,
	ClaimWait = 0.1, SaveBackoff = 0.05, HoldTimeout = 2,
}

--============================ fake DataStoreService ============================--
local function newFakeDSS()
	local dss = { stores = {}, budget = 1000 }
	function dss:GetDataStore(name)
		if self.stores[name] then return self.stores[name] end
		local s = { name = name, data = {}, log = {}, writes = 0, updates = 0,
			failNext = 0, failAlways = false, latency = 0 }
		local function decode(str) if str == nil then return nil end return HS:JSONDecode(str) end
		function s:UpdateAsync(key, fn)
			self.updates += 1
			if self.latency > 0 then task.wait(self.latency) end
			if self.failAlways or self.failNext > 0 then
				if self.failNext > 0 then self.failNext -= 1 end
				error("502: API Services rejected request with error. (fake DataStore)")
			end
			local old = decode(self.data[key])
			local new = fn(old)
			if new ~= nil then
				self.data[key] = HS:JSONEncode(new)
				self.writes += 1
				table.insert(self.log, { key = key, t = os.clock(),
					job = new.__session and new.__session.job or false, cash = new.Cash })
			end
			return decode(self.data[key])
		end
		function s:GetAsync(key) return decode(self.data[key]) end
		function s:SetAsync(key, v) self.data[key] = HS:JSONEncode(v) end
		self.stores[name] = s
		return s
	end
	function dss:GetRequestBudgetForRequestType() return self.budget end
	return dss
end

--============================ module loader ============================--
local function loadModule(name, source, env)
	local fn, err = loadstring(source, "=" .. name)
	assert(fn, ("compile %s: %s"):format(name, tostring(err)))
	setfenv(fn, setmetatable(env, { __index = getfenv(0) }))
	return fn()
end

local servers = {}   -- every server made, so their loops can be stopped at the end

-- One "server": its own SessionLock (+ PlayerDataManager) instance, its own JobId.
local function newServer(dss, clock, opts)
	opts = opts or {}
	local S = { bound = {}, warnings = {}, name = opts.name or "srv" }
	local fakeWorkspace = { FindFirstChild = function() return nil end }
	local fakeGame = setmetatable({
		JobId = "", PlaceId = 78783087742939,
		GetService = function(_, n)
			if n == "DataStoreService" then return dss end
			if n == "Workspace" then return fakeWorkspace end
			return game:GetService(n)
		end,
		BindToClose = function(_, fn) table.insert(S.bound, fn) end,
	}, { __index = function(_, k) return game[k] end })
	local fakeOs = setmetatable({ time = function() return clock.t end }, { __index = os })
	-- loops that never look at `closing` (the live heartbeat) are parked for good through
	-- their wait once the run is over: a yield nothing resumes, so no error reaches the console
	local fakeTask = setmetatable({ wait = function(t)
		local r = task.wait(t)
		if S.killed then coroutine.yield() end
		return r
	end }, { __index = task })
	local function fakeWarn(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		local m = table.concat(parts, " ")
		table.insert(S.warnings, m)
		if opts.echo then realWarn("[" .. S.name .. "] " .. m) end
	end
	S.SL = loadModule("SessionLock", SRC.SessionLock,
		{ game = fakeGame, os = fakeOs, warn = fakeWarn, task = fakeTask, script = { Name = "SessionLock" } })
	if S.SL.Tuning then for k, v in pairs(TUNING) do S.SL.Tuning[k] = v end end
	if opts.withPDM then
		local stubs = {
			BrainrotSpawner = { RestoreAll = function() end },
			BoundsGuard = { RegionName = function() return "Valley" end },
			BagConfig = { BrainrotSpace = function() return 0 end, PetSpace = function() return 0 end },
			NumberFormat = { Short = function(n) return tostring(n) end },
			SessionLock = S.SL,
		}
		local fakeScript = { Name = "PlayerDataManager",
			Parent = { SessionLock = "SessionLock", BrainrotSpawner = "BrainrotSpawner", BoundsGuard = "BoundsGuard" } }
		local function fakeRequire(x)
			local name = typeof(x) == "Instance" and x.Name or x
			return assert(stubs[name], "no stub for " .. tostring(name))
		end
		S.PDM = loadModule("PlayerDataManager", SRC.PlayerDataManager,
			{ game = fakeGame, os = fakeOs, warn = fakeWarn, script = fakeScript, require = fakeRequire })
	end
	function S.hasWarning(pattern)
		for _, w in ipairs(S.warnings) do if w:find(pattern) then return true end end
		return false
	end
	function S.stop()
		S.SL.closing = true
		if not S.SL.Tuning then S.killed = true end   -- live heartbeat: no closing flag to honour
	end
	table.insert(servers, S)
	return S
end

--============================ test runner ============================--
local results, passed, failed, na = {}, 0, 0, 0
local function record(name, status, msg)
	table.insert(results, ("%-4s %s%s"):format(status, name, msg and ("  -- " .. msg) or ""))
	if status == "PASS" then passed += 1 elseif status == "FAIL" then failed += 1 else na += 1 end
end
local NA = {}   -- sentinel thrown by a test that cannot run on this variant
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then record(name, "PASS")
	elseif err == NA then record(name, "n/a", "needs the hotfix API (variant=" .. variant .. ")")
	else record(name, "FAIL", tostring(err)) end
end
local function expect(cond, msg) if not cond then error(msg or "expectation failed", 2) end end
local function needsNew(S) if not (S.SL.Tuning and S.PDM and S.PDM.LoadProfile) then error(NA) end end
local function waitUntil(pred, timeout)
	local deadline = os.clock() + (timeout or 3)
	while os.clock() < deadline do
		if pred() then return true end
		task.wait(0.05)
	end
	return pred()
end
local function deepEqual(a, b, path)
	path = path or "root"
	if type(a) ~= type(b) then return false, path .. ": " .. type(a) .. " vs " .. type(b) end
	if type(a) ~= "table" then
		if a == b then return true end
		return false, path .. ": " .. tostring(a) .. " vs " .. tostring(b)
	end
	for k, v in pairs(a) do
		local ok, why = deepEqual(v, b[k], path .. "." .. tostring(k))
		if not ok then return false, why end
	end
	for k in pairs(b) do
		if a[k] == nil then return false, path .. "." .. tostring(k) .. ": missing on left" end
	end
	return true
end
local function strip(t)   -- copy without the lock stamp, for comparisons
	local out = {}
	for k, v in pairs(t) do if k ~= "__session" then out[k] = v end end
	return out
end
local function player(uid) return { UserId = uid, Name = "tester" .. uid } end
local function join(S, uid)   -- what Load does minus the Player instance
	needsNew(S)
	local data = S.PDM.LoadProfile(uid, "tester" .. uid)
	S.PDM.cache[uid] = data
	return data
end
local function writesFor(store, key, since)
	local n = 0
	for _, e in ipairs(store.log) do if e.key == key and e.t >= (since or 0) then n += 1 end end
	return n
end

local STORE = "BrainrotSkip_PlayerData_v1"
local U = 900000000   -- fake user ids; never a real player

--============================ C2: profile lifecycle ============================--
test("T1 brand-new player joins normally: stored profile is complete from the first transaction", function()
	local dss, clock = newFakeDSS(), { t = 1700000000 }
	local S = newServer(dss, clock, { withPDM = true, name = "A" })
	local store = dss:GetDataStore(STORE)
	local uid = U + 1
	if S.PDM.LoadProfile then
		local data = join(S, uid)
		expect(data.__noSave == nil, "session must be writable")
		expect(data.Cash == 0, "cache Cash must be 0, got " .. tostring(data.Cash))
	else
		local _, status = S.SL.Claim(uid)
		expect(status == "new", "status " .. tostring(status))
	end
	expect(S.SL.owned[uid] == true, "profile must be owned after the claim")
	local stored = store:GetAsync("Player_" .. uid)
	expect(stored ~= nil, "claim must have written the key")
	expect(stored.__session and stored.__session.job == S.SL.JobId, "lock stamped by this server")
	expect(stored.__sessionNew == nil, "no marker may be stored (was: " .. tostring(stored.__sessionNew) .. ")")
	expect(type(stored.Cash) == "number" and stored.Cash == 0, "stored Cash must be 0, got " .. tostring(stored.Cash))
	expect(type(stored.Brainrots) == "table", "stored Brainrots missing")
end)

test("T2 brand-new player earns Cash and the periodic write persists it", function()
	local dss, clock = newFakeDSS(), { t = 1700000000 }
	local S = newServer(dss, clock, { withPDM = true, name = "A" })
	local store = dss:GetDataStore(STORE)
	local uid = U + 2
	local data = join(S, uid)
	expect(S.PDM.AddEarnings(nil, 250, data) == 250, "AddEarnings must credit 250")
	expect(data.Cash == 250, "cache Cash 250")
	local landed = waitUntil(function() local st = store:GetAsync("Player_" .. uid); return st and st.Cash == 250 end, 4)
	expect(landed, "periodic write never persisted Cash=250 (stored " .. tostring((store:GetAsync("Player_" .. uid) or {}).Cash) .. ")")
end)

test("T3 first server dies before a clean release: what is left in storage", function()
	local dss, clock = newFakeDSS(), { t = 1700000000 }
	local A = newServer(dss, clock, { withPDM = true, name = "A" })
	local store = dss:GetDataStore(STORE)
	local uid = U + 3
	if A.PDM.LoadProfile then join(A, uid) else A.SL.Claim(uid) end
	A.stop()   -- the crash: no Release, no BindToClose, loop dead
	local stored = store:GetAsync("Player_" .. uid)
	expect(stored.__session and stored.__session.job == A.SL.JobId, "dead server's lock is still on the profile")
	expect(type(stored.Cash) == "number", "a crashed first session must still leave a Cash field in storage (got " .. tostring(stored.Cash) .. ")")
end)

test("T4a rejoin inside the stale window: read-only, never a broken profile", function()
	local dss, clock = newFakeDSS(), { t = 1700000000 }
	local A = newServer(dss, clock, { withPDM = true, name = "A" })
	local uid = U + 4
	if A.PDM.LoadProfile then join(A, uid) else A.SL.Claim(uid) end
	A.stop()
	local B = newServer(dss, clock, { withPDM = true, name = "B" })
	needsNew(B)
	local data = B.PDM.LoadProfile(uid, "rejoin")
	expect(data.__noSave == true, "must be a read-only session while A's lock is fresh")
	expect(type(data.Cash) == "number", "read-only defaults still carry Cash")
	expect(B.hasWarning("held by another live server"), "must warn about the held profile")
	expect(B.SL.owned[uid] == nil, "B must not own the profile")
end)

test("T4b rejoin after the stale window: profile loads with Cash and every default field", function()
	local dss, clock = newFakeDSS(), { t = 1700000000 }
	local A = newServer(dss, clock, { withPDM = true, name = "A" })
	local uid = U + 5
	if A.PDM.LoadProfile then join(A, uid) else A.SL.Claim(uid) end
	A.stop()
	clock.t += 91
	local B = newServer(dss, clock, { withPDM = true, name = "B" })
	needsNew(B)
	local data = B.PDM.LoadProfile(uid, "rejoin")
	expect(data.__noSave == nil, "takeover of a stale lock must give a writable session")
	expect(type(data.Cash) == "number" and data.Cash == 0, "Cash must be 0 (got " .. tostring(data.Cash) .. ")")
	for k in pairs(B.PDM.DefaultData()) do
		expect(data[k] ~= nil, "default field missing after load: " .. k)
	end
	expect(B.PDM.AddEarnings(nil, 5, data) == 5, "earning must work on the rejoined profile")
	expect(B.PDM.GrantCash(data, 5) == 5, "GrantCash must work on the rejoined profile")
	expect(data.Cash == 10, "Cash 10 after two grants")
end)

test("T4c legacy { __sessionNew } marker left by a pre-hotfix first session loads as a new player", function()
	local dss, clock = newFakeDSS(), { t = 1700000000 }
	local store = dss:GetDataStore(STORE)
	local uid = U + 6
	-- exactly what the old Claim wrote for a brand-new player, then abandoned by a crash
	store:SetAsync("Player_" .. uid, { __sessionNew = true, __session = { job = "dead-server", t = clock.t - 200, place = 1 } })
	local B = newServer(dss, clock, { withPDM = true, name = "B" })
	needsNew(B)
	local data = B.PDM.LoadProfile(uid, "marker")
	expect(data.__noSave == nil, "stale marker lock must be taken over")
	expect(data.__sessionNew == nil, "marker must be stripped")
	expect(type(data.Cash) == "number" and data.Cash == 0, "Cash must be 0 (got " .. tostring(data.Cash) .. ")")
	for k in pairs(B.PDM.DefaultData()) do expect(data[k] ~= nil, "default field missing: " .. k) end
	expect(B.hasWarning("session marker"), "must log that a marker profile was met")
	expect(B.PDM.AddEarnings(nil, 7, data) == 7 and data.Cash == 7, "earning must work")
	B.PDM.cache[uid] = data
	local landed = waitUntil(function() local st = store:GetAsync("Player_" .. uid); return st and st.Cash == 7 and st.__sessionNew == nil end, 4)
	expect(landed, "periodic write must replace the marker with the real profile")
end)

test("T5 old profile missing Cash: Cash restored, everything else kept", function()
	local dss, clock = newFakeDSS(), { t = 1700000000 }
	local store = dss:GetDataStore(STORE)
	local uid = U + 7
	store:SetAsync("Player_" .. uid, { Brainrots = { { Name = "Tim Cheese", Uid = 1, PadIndex = 2 } }, NextUid = 2,
		Rebirths = 3, Discovered = { ["Tim Cheese"] = true }, LifetimeEarned = 900 })
	local S = newServer(dss, clock, { withPDM = true, name = "A" })
	needsNew(S)
	local data = S.PDM.LoadProfile(uid, "oldsave")
	expect(data.Cash == 0, "Cash must default to 0 (got " .. tostring(data.Cash) .. ")")
	expect(data.Rebirths == 3, "Rebirths kept")
	expect(#data.Brainrots == 1 and data.Brainrots[1].Name == "Tim Cheese" and data.Brainrots[1].PadIndex == 2, "brainrots kept")
	expect(data.LifetimeEarned == 900, "LifetimeEarned kept (not re-estimated)")
end)

test("T6 old profile missing other safe defaults: restored without touching what exists", function()
	local dss, clock = newFakeDSS(), { t = 1700000000 }
	local store = dss:GetDataStore(STORE)
	local uid = U + 8
	store:SetAsync("Player_" .. uid, { Cash = 42, Keys = 1 })
	local S = newServer(dss, clock, { withPDM = true, name = "A" })
	needsNew(S)
	local data = S.PDM.LoadProfile(uid, "oldsave")
	expect(data.Cash == 42, "Cash 42 kept")
	expect(data.Keys == 1, "Keys kept")
	expect(type(data.Pets) == "table" and type(data.Settings) == "table", "Pets/Settings restored")
	expect(data.WorldsVisited and data.WorldsVisited.Valley == true, "WorldsVisited restored")
	expect(data.TundraParts and data.TundraParts.Cog == 0, "TundraParts restored")
	expect(data.OwnedRocks and data.OwnedRocks.Pebble == true and data.EquippedRock == "Pebble", "rocks restored")
	for k in pairs(S.PDM.DefaultData()) do expect(data[k] ~= nil, "default field missing: " .. k) end
	-- defaults must be copies: two profiles never share a table
	local data2 = S.PDM.LoadProfile(uid + 1000, "other")
	expect(data.Pets ~= data2.Pets and data.OwnedRocks ~= data2.OwnedRocks, "default tables must be per-profile copies")
end)

test("T7 normal established profile loads unchanged", function()
	local dss, clock = newFakeDSS(), { t = 1700000000 }
	local store = dss:GetDataStore(STORE)
	local uid = U + 9
	local S = newServer(dss, clock, { withPDM = true, name = "A" })
	needsNew(S)
	local seed = S.PDM.DefaultData()
	seed.Cash = 1234; seed.LastSeen = clock.t - 50; seed.TotalEarned = 5000; seed.LifetimeEarned = 6000
	store:SetAsync("Player_" .. uid, seed)
	local data = S.PDM.LoadProfile(uid, "vet")
	local same, why = deepEqual(strip(HS:JSONDecode(HS:JSONEncode(seed))), strip(data))
	expect(same, "loaded profile differs from stored: " .. tostring(why))
end)

test("T8 established profile with changed values keeps every one of them", function()
	local dss, clock = newFakeDSS(), { t = 1700000000 }
	local store = dss:GetDataStore(STORE)
	local uid = U + 10
	local S = newServer(dss, clock, { withPDM = true, name = "A" })
	needsNew(S)
	local seed = S.PDM.DefaultData()
	seed.Cash = 5000; seed.Rebirths = 7; seed.Settings = { music = 0.3, fastSpin = true }
	seed.Upgrades = { StrongArm = 4 }; seed.OwnedRocks = { Pebble = true, Granite = true }; seed.EquippedRock = "Granite"
	seed.Keys = 2; seed.WorldsVisited = { Valley = true, Tundra = true }; seed.TutorialDone = true
	seed.Brainrots = { { Name = "Tim Cheese", Uid = 4, Mutation = "Golden" } }; seed.NextUid = 5
	seed.Discovered = { ["Tim Cheese"] = true }; seed.DailyStreak = 9; seed.Darrels = 77
	store:SetAsync("Player_" .. uid, seed)
	local data = S.PDM.LoadProfile(uid, "vet")
	expect(data.Cash == 5000, "Cash 5000 must remain 5000 (got " .. tostring(data.Cash) .. ")")
	expect(data.Rebirths == 7 and data.Keys == 2 and data.Darrels == 77 and data.DailyStreak == 9, "counters kept")
	expect(data.Settings.music == 0.3 and data.Settings.fastSpin == true, "settings kept")
	expect(data.Upgrades.StrongArm == 4, "upgrades kept")
	expect(data.OwnedRocks.Granite == true and data.EquippedRock == "Granite", "rocks kept")
	expect(data.WorldsVisited.Tundra == true and data.TutorialDone == true, "flags kept")
	expect(data.Brainrots[1].Mutation == "Golden" and data.NextUid == 5, "inventory kept")
	local same, why = deepEqual(strip(HS:JSONDecode(HS:JSONEncode(seed))), strip(data))
	expect(same, "loaded profile differs from stored: " .. tostring(why))
end)

--============================ session lock / two servers ============================--
test("T9a two servers, live lock: second claim refused, its saves are no-ops, first server unaffected", function()
	local dss, clock = newFakeDSS(), { t = 1700000000 }
	local store = dss:GetDataStore(STORE)
	local uid = U + 11
	local A = newServer(dss, clock, { name = "A" })
	local B = newServer(dss, clock, { name = "B" })
	local dataA, stA = A.SL.Claim(uid, function() return { Cash = 0 } end)
	expect(stA == "new" or stA == "ok", "A claims: " .. tostring(stA))
	local dataB, stB = B.SL.Claim(uid, function() return { Cash = 0 } end)
	expect(stB == "locked" and dataB == nil, "B must be refused while A is live (got " .. tostring(stB) .. ")")
	expect(B.SL.Save(uid, { Cash = 999 }) == false, "B's save must be refused")
	expect(store:GetAsync("Player_" .. uid).Cash ~= 999, "B must not have written")
	dataA = dataA or { Cash = 0 }
	dataA.Cash = 5
	expect(A.SL.Save(uid, dataA) == true, "A's save lands")
	expect(store:GetAsync("Player_" .. uid).Cash == 5, "A's data stored")
	expect(A.SL.Release(uid, dataA) == true, "A releases")
	expect(store:GetAsync("Player_" .. uid).__session == nil, "released profile is unlocked")
	local dataB2, stB2 = B.SL.Claim(uid)
	expect(stB2 == "ok" and dataB2 and dataB2.Cash == 5, "B claims the released profile with A's data")
end)

test("T9b stale lock taken over: the old server's later save is refused as stolen", function()
	local dss, clock = newFakeDSS(), { t = 1700000000 }
	local store = dss:GetDataStore(STORE)
	local uid = U + 12
	local A = newServer(dss, clock, { name = "A" })
	local B = newServer(dss, clock, { name = "B" })
	local dataA = select(1, A.SL.Claim(uid, function() return { Cash = 1 } end)) or { Cash = 1 }
	clock.t += 91   -- A's lock ages out (it "crashed" without releasing)
	local dataB, stB = B.SL.Claim(uid)
	expect(stB == "ok", "B takes over a stale lock (got " .. tostring(stB) .. ")")
	dataB.Cash = 50
	expect(B.SL.Save(uid, dataB) == true, "B saves")
	dataA.Cash = 99
	local ok, why = A.SL.Save(uid, dataA)
	expect(ok == false, "A's save must be refused after the takeover")
	if A.SL.Tuning then expect(why == "stolen", "reason must be 'stolen' (got " .. tostring(why) .. ")") end
	local stored = store:GetAsync("Player_" .. uid)
	expect(stored.Cash == 50 and stored.__session.job == B.SL.JobId, "B's data and lock remain")
	expect(dataA.Cash == 99, "A's in-memory profile untouched by the refusal")
end)

test("T9c teleport window: after Release a late save cannot re-lock; a re-claim can", function()
	local dss, clock = newFakeDSS(), { t = 1700000000 }
	local store = dss:GetDataStore(STORE)
	local uid = U + 13
	local A = newServer(dss, clock, { name = "A" })
	local data = select(1, A.SL.Claim(uid, function() return { Cash = 3 } end)) or { Cash = 3 }
	expect(A.SL.Release(uid, data) == true, "release")
	local ok, why = A.SL.Save(uid, data)
	expect(ok == false, "save after release must be refused (would re-lock the profile under the destination server)")
	expect(store:GetAsync("Player_" .. uid).__session == nil, "profile must stay unlocked")
	local _, st = A.SL.Claim(uid)
	expect(st == "ok", "TeleportAsync failed -> reclaim works (got " .. tostring(st) .. ")")
	expect(A.SL.Save(uid, data) == true, "saves work again after the reclaim")
end)

--============================ C1: periodic persistence ============================--
test("T10 periodic write persists the LIVE profile while the player plays (and refreshes the lock)", function()
	local dss, clock = newFakeDSS(), { t = 1700000000 }
	local store = dss:GetDataStore(STORE)
	local uid = U + 14
	local S = newServer(dss, clock, { withPDM = true, name = "A" })
	local data
	if S.PDM.LoadProfile then data = join(S, uid)
	else
		S.SL.Claim(uid); data = S.PDM.DefaultData and S.PDM.DefaultData() or { Cash = 0 }
		S.PDM.cache[uid] = data
	end
	data.Cash = 100
	local t0 = os.clock()
	-- live variant: heartbeat every 30s, so give it 35s to show what it writes
	local horizon = S.SL.Tuning and 3 or 35
	local landed = waitUntil(function() local st = store:GetAsync("Player_" .. uid); return st and st.Cash == 100 end, horizon)
	local stored = store:GetAsync("Player_" .. uid)
	expect(landed, ("live Cash=100 never reached storage within %ds (stored Cash=%s, writes=%d)"):format(horizon, tostring(stored and stored.Cash), writesFor(store, "Player_" .. uid, t0)))
	expect(stored.__session and stored.__session.job == S.SL.JobId, "lock still ours after the periodic write")
	data.Cash = 200
	expect(waitUntil(function() local st = store:GetAsync("Player_" .. uid); return st and st.Cash == 200 end, 3), "second change persisted")
	expect(store:GetAsync("Player_" .. uid).LastSeen == clock.t, "LastSeen stamped by the periodic write")
end)

test("T11 player leaves during an in-flight periodic write: leave write lands last, profile unlocked, late save refused", function()
	local dss, clock = newFakeDSS(), { t = 1700000000 }
	local store = dss:GetDataStore(STORE)
	local uid = U + 15
	local S = newServer(dss, clock, { withPDM = true, name = "A" })
	needsNew(S)
	local data = join(S, uid)
	data.Cash = 11
	store.latency = 0.3
	S.SL.MarkDue(uid)
	expect(waitUntil(function() return S.SL.IsWriting(uid) end, 2), "periodic write should be in flight")
	local autosaveT, removeT
	local writesBefore = #store.log
	task.spawn(function() S.PDM.Remove(player(uid)); removeT = os.clock() end)
	task.wait(0.05)
	data.Cash = 12   -- the player did one more thing before the leave write ran
	expect(waitUntil(function() return removeT ~= nil end, 3), "Remove must finish")
	store.latency = 0
	local entries = {}
	for i = writesBefore + 1, #store.log do table.insert(entries, store.log[i]) end
	expect(#entries == 2, "expected the periodic write then the leave write, got " .. #entries)
	expect(entries[1].job == S.SL.JobId and entries[2].job == false, "periodic write (locked) then leave write (unlocked), in that order")
	local stored = store:GetAsync("Player_" .. uid)
	expect(stored.__session == nil and stored.Cash == 12, ("final storage must be unlocked with the last state (session=%s cash=%s)"):format(tostring(stored.__session), tostring(stored.Cash)))
	expect(S.PDM.cache[uid] == nil and S.SL.owned[uid] == nil, "cache and ownership dropped")
	local ok, why = S.SL.Save(uid, data)
	expect(ok == false and why == "unowned", "a late save after the leave must be refused (" .. tostring(why) .. ")")
	expect(store:GetAsync("Player_" .. uid).__session == nil, "still unlocked")
end)

test("T12 BindToClose after a recent periodic write: final write, unlocked, and a parallel Save cannot re-lock", function()
	local dss, clock = newFakeDSS(), { t = 1700000000 }
	local store = dss:GetDataStore(STORE)
	local uid = U + 16
	local S = newServer(dss, clock, { withPDM = true, name = "A" })
	needsNew(S)
	local data = join(S, uid)
	data.Cash = 77
	expect(waitUntil(function() local st = store:GetAsync("Player_" .. uid); return st and st.Cash == 77 end, 3), "periodic write first")
	data.Cash = 78
	expect(#S.bound == 1, "PlayerDataManager binds exactly one BindToClose (got " .. #S.bound .. ")")
	local closed = false
	store.latency = 0.2   -- the shutdown write yields, so the parallel Save below truly overlaps it
	task.spawn(function() S.bound[1](); closed = true end)
	-- the old Main BindToClose, running IN PARALLEL as Roblox does: Save for every player
	local ok = S.PDM.Save(player(uid))
	expect(ok == false, "a Save racing the shutdown write must be refused")
	expect(waitUntil(function() return closed end, 3), "shutdown handler must finish")
	store.latency = 0
	local stored = store:GetAsync("Player_" .. uid)
	expect(stored.__session == nil, "profile must be UNLOCKED after shutdown (a parallel Save re-locked it before)")
	expect(stored.Cash == 78, "final state written (got " .. tostring(stored.Cash) .. ")")
	expect(stored.LastSeen == clock.t, "LastSeen stamped by the shutdown write")
	expect(S.SL.closing == true, "periodic loop stopped")
	expect(S.PDM.Save(player(uid)) == false, "no save may land after shutdown")
	expect(store:GetAsync("Player_" .. uid).__session == nil, "still unlocked")
end)

test("T13 DataStore write failure: reported, in-memory profile untouched, next write succeeds", function()
	local dss, clock = newFakeDSS(), { t = 1700000000 }
	local store = dss:GetDataStore(STORE)
	local uid = U + 17
	local S = newServer(dss, clock, { withPDM = true, name = "A" })
	needsNew(S)
	local data = join(S, uid)
	S.SL.nextDue[uid] = os.clock() + 100   -- park the periodic loop: this test counts attempts
	data.Cash = 500
	store.failAlways = true
	local ok, why = S.PDM.Save(player(uid))
	expect(ok == false, "save must report failure")
	expect(why == "error", "reason 'error' (got " .. tostring(why) .. ")")
	expect(S.hasWarning("save FAILED"), "failure warned")
	expect(data.Cash == 500 and data.__noSave == nil and S.SL.owned[uid] == true, "profile and ownership intact after the failure")
	expect(store:GetAsync("Player_" .. uid).Cash == 0, "storage untouched by the failed write")
	store.failAlways = false
	expect(S.PDM.Save(player(uid)) == true and store:GetAsync("Player_" .. uid).Cash == 500, "next write lands")
	-- and a failing LEAVE write: reported, ownership dropped, nothing corrupted
	store.failAlways = true
	local released = S.SL.Release(uid, data)
	expect(released == false and S.hasWarning("release FAILED"), "release failure reported")
	expect(store:GetAsync("Player_" .. uid).Cash == 500, "storage still holds the last good write")
	store.failAlways = false
end)

test("T14 retry: a transient failure is retried inline; a failed periodic write is retried after RetryAfter", function()
	local dss, clock = newFakeDSS(), { t = 1700000000 }
	local store = dss:GetDataStore(STORE)
	local uid = U + 18
	local S = newServer(dss, clock, { withPDM = true, name = "A" })
	needsNew(S)
	local data = join(S, uid)
	S.SL.nextDue[uid] = os.clock() + 100   -- park the periodic loop: this test counts attempts
	data.Cash = 9
	store.failNext = 1
	local before = store.updates
	expect(S.PDM.Save(player(uid)) == true, "one transient failure must be absorbed by the retry")
	expect(store.updates - before == 2, "exactly two attempts (got " .. (store.updates - before) .. ")")
	expect(store:GetAsync("Player_" .. uid).Cash == 9, "stored after retry")
	-- periodic path: all three inline attempts fail, then the loop's own retry lands
	data.Cash = 10
	store.failNext = 3
	local tFail = os.clock()
	S.SL.MarkDue(uid)
	expect(waitUntil(function() return S.hasWarning("autosave for " .. uid .. " did not land") end, 3), "periodic failure must be logged")
	local st = store:GetAsync("Player_" .. uid)
	expect(st.Cash == 9, "storage keeps the last good state after the failed periodic write")
	local landedAt
	expect(waitUntil(function()
		local now = store:GetAsync("Player_" .. uid)
		if now and now.Cash == 10 then landedAt = landedAt or os.clock(); return true end
		return false
	end, 4), "periodic retry must eventually land")
	expect(landedAt - tFail >= S.SL.Tuning.RetryAfter * 0.9, ("retry came too early: %.2fs after the failure (RetryAfter=%.2f)"):format(landedAt - tFail, S.SL.Tuning.RetryAfter))
end)

test("T15 six players: periodic writes are staggered, one per tick, every profile covered", function()
	local dss, clock = newFakeDSS(), { t = 1700000000 }
	local store = dss:GetDataStore(STORE)
	local S = newServer(dss, clock, { withPDM = true, name = "A" })
	needsNew(S)
	S.SL.Tuning.AutosaveEvery = 1.0   -- 6 players / 1s interval / 0.1s tick -> 1 write per tick
	local uids, datas = {}, {}
	for i = 1, 6 do
		local uid = U + 100 + i
		uids[i] = uid
		datas[i] = join(S, uid)
		datas[i].Cash = 1000 + i
	end
	local since = os.clock()
	task.wait(S.SL.Tuning.AutosaveEvery + 1.2)   -- headroom: an unfocused Studio ticks slower
	local entries = {}
	for _, e in ipairs(store.log) do if e.t > since then table.insert(entries, e) end end
	table.sort(entries, function(a, b) return a.t < b.t end)
	for i, uid in ipairs(uids) do
		expect(writesFor(store, "Player_" .. uid, since) >= 1, "player " .. i .. " never written")
		expect(store:GetAsync("Player_" .. uid).Cash == 1000 + i, "player " .. i .. " state persisted")
	end
	local minGap, maxPerWindow = math.huge, 0
	for i = 2, #entries do minGap = math.min(minGap, entries[i].t - entries[i - 1].t) end
	expect(#entries >= 6, "at least one write per player (got " .. #entries .. ")")
	expect(minGap >= S.SL.Tuning.Tick * 0.8, ("writes not staggered: two landed %.3fs apart (tick %.2fs)"):format(minGap, S.SL.Tuning.Tick))
	-- the same six players cost the same request count as the old heartbeat: ~1 write per player per interval
	expect(#entries <= 6 * 2 + 1, "write count must stay near one per player per interval (got " .. #entries .. ")")
end)

test("T16 rejoin on the same server while the leave write is in flight loads the state that write carries", function()
	local dss, clock = newFakeDSS(), { t = 1700000000 }
	local store = dss:GetDataStore(STORE)
	local uid = U + 19
	local S = newServer(dss, clock, { withPDM = true, name = "A" })
	needsNew(S)
	local data = join(S, uid)
	data.Cash = 123
	store.latency = 0.3
	local removed = false
	task.spawn(function() S.PDM.Remove(player(uid)); removed = true end)
	task.wait(0.05)
	expect(S.SL.IsWriting(uid), "leave write in flight")
	local data2 = S.PDM.LoadProfile(uid, "rejoin")   -- must queue behind the leave write
	store.latency = 0
	expect(removed, "the claim must not run ahead of the leave write")
	expect(data2.__noSave == nil and data2.Cash == 123, "rejoin sees the state the leave write carried (got Cash=" .. tostring(data2.Cash) .. ")")
	expect(S.SL.owned[uid] == true, "rejoined profile is owned")
end)

test("T17 budget floor: the periodic loop steps aside when the UpdateAsync budget is starved, transactional saves still work", function()
	local dss, clock = newFakeDSS(), { t = 1700000000 }
	local store = dss:GetDataStore(STORE)
	local uid = U + 20
	local S = newServer(dss, clock, { withPDM = true, name = "A" })
	needsNew(S)
	local data = join(S, uid)
	dss.budget = 2   -- below BudgetFloor
	data.Cash = 31
	S.SL.MarkDue(uid)
	task.wait(0.6)
	expect(store:GetAsync("Player_" .. uid).Cash == 0, "periodic loop must not write while starved")
	expect(S.PDM.Save(player(uid)) == true, "a transactional save still goes through")
	dss.budget = 1000
	data.Cash = 32
	expect(waitUntil(function() return store:GetAsync("Player_" .. uid).Cash == 32 end, 3), "loop resumes when the budget is back")
end)

--============================ wrap up ============================--
for _, S in ipairs(servers) do S.stop() end
task.wait(0.3)   -- let every loop observe `closing`

local header = ("DATA-SAFETY HARNESS  variant=%s  PASS=%d FAIL=%d n/a=%d"):format(variant, passed, failed, na)
return header .. "\n" .. table.concat(results, "\n")
