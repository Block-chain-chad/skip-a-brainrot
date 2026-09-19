-- MichelQuest: Michael the eagle's questline in the Frozen Tundra.
--
-- (He is "Michael" to the player and Michel* in code -- see the naming note at the top of
-- MichelQuestConfig. data.MichelQuest and data.MichelGiven are persisted keys.)
--
-- Michael wants FIVE Tung Tung Tung Sahurs, every one of them MUTATED, and pays 1000
-- emeralds for the set. The player chooses which copies to give up, A FEW AT A TIME --
-- the same shape as TungQuest, and for the same reason: the hand-over DESTROYS the
-- items, so picking blind would mean losing an Angel to a quest that would have taken
-- the Golden sitting next to it.
--
-- WHY PROGRESS IS STORED. data.MichelGiven is the authority and only ever goes up.
-- Deriving progress from what the player is HOLDING is wrong the moment a delivery
-- lands: the brainrots are gone from the inventory, so a held-count would read 0/5
-- again. What is held is still computed live, but only to answer "can you finish this
-- right now" and to fill the picker -- never as progress.
--
-- STATE. data.MichelQuest is 0 / 1 / 3; 2 is DERIVED and never stored:
--   0 not accepted
--   1 collecting
--   2 everything still owed is in hand right now (one more visit finishes it)
--   3 delivered in full; emeralds paid
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local EmeraldService = require(ServerScriptService.Modules.EmeraldService)
local InventoryHandler = require(ServerScriptService.Modules.InventoryHandler)
local BrainrotMover = require(ServerScriptService.Modules.BrainrotMover)
local CFG = require(ReplicatedStorage.Modules.MichelQuestConfig)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)

local NEED = CFG.Count
local remotes = ReplicatedStorage.Remotes
local ST_NONE, ST_COLLECTING, ST_READY, ST_DONE = 0, 1, 2, 3

local MichelQuest = {}

local function getRemote(name, class)
	local r = remotes:FindFirstChild(name)
	if not r then r = Instance.new(class); r.Name = name; r.Parent = remotes end
	return r
end
local talkRemote  = getRemote("MichelTalk", "RemoteEvent")
local stateRemote = getRemote("MichelState", "RemoteEvent")

local function notify(player, ok, msg)
	local r = remotes:FindFirstChild("PurchaseResult")
	if r then r:FireClient(player, { Success = ok, Message = msg }) end
end

-- cash/sec by name, so the auto-pick can order candidates least-valuable-first
local cpsByName = {}
for _, e in ipairs(BrainrotConfig.List or BrainrotConfig) do
	cpsByName[e.Name] = e.CashPerSecond or 0
end
local function valueOf(entry)
	return (cpsByName[entry.Name] or 0) * Mutations.Mult(entry.Mutation)
end

-- === STATE ====================================================================
-- 2 is a LIVE reading, not a save value: it means "the rest is in your bag right now",
-- which stops being true the moment the player sells one. Storing it would strand a
-- profile in a state the inventory no longer supports.
local function storedState(data)
	local st = tonumber(data.MichelQuest) or 0
	if st >= ST_DONE then
		st = ST_DONE
	elseif st == ST_READY then
		st = ST_COLLECTING
	elseif st < ST_NONE then
		st = ST_NONE
	end
	if data.MichelQuest ~= st then data.MichelQuest = st end
	return st
end

-- Delivered count, clamped. A profile marked done is backfilled to the full quota rather
-- than asking that player to deliver five more.
local function given(data)
	local n = math.floor(tonumber(data.MichelGiven) or 0)
	if (tonumber(data.MichelQuest) or 0) >= ST_DONE then n = NEED end
	n = math.clamp(n, 0, NEED)
	if data.MichelGiven ~= n then data.MichelGiven = n end
	return n
end
MichelQuest.Given = given

-- How many qualifying brainrots are HELD (unplaced) vs PLACED on a pad. Only unplaced
-- can be handed over -- one on a pad is earning income, the same line Elder Tung's and
-- Gianluca's hand-overs draw.
local function heldPlaced(data)
	local held, placed = 0, 0
	for _, e in ipairs(data.Brainrots or {}) do
		if CFG.Accepts(e) then
			if e.PadIndex == nil then held += 1 else placed += 1 end
		end
	end
	return held, placed
end

-- "quota" drives the client's one-off "you can finish this now" popup, so it must fire
-- on the FALSE -> TRUE edge only; the watcher below re-pushes state every couple of
-- seconds while the player stands there holding the rest.
local wasReady = {}

local function sendState(player, note)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local stored = storedState(data)
	local have = given(data)
	local left = NEED - have
	local held, placed = heldPlaced(data)

	local ready = (stored == ST_COLLECTING) and left > 0 and held >= left
	local live = ready and ST_READY or stored

	if ready ~= wasReady[player] then
		wasReady[player] = ready
		if ready then note = note or "quota" end
	end

	stateRemote:FireClient(player, {
		State = live,
		-- Step/Of are what QuestTrackerClient renders straight into "(n/m)"
		Step = have,
		Of = NEED,
		Have = have,
		Need = NEED,
		Left = left,
		Held = held,
		Placed = placed,
		Ready = ready,
		Done = stored >= ST_DONE,
		Darrels = data.Darrels or 0,
		Note = note,
	})
end
MichelQuest.SendState = sendState

-- === ACCEPT ===================================================================
local function accept(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	if storedState(data) == ST_NONE then
		data.MichelQuest = ST_COLLECTING
		data.MichelGiven = 0
		PlayerDataManager.PushUpdate(player)
	end
	sendState(player)
end
MichelQuest.Accept = accept

-- === DELIVERY =================================================================
-- The client sends the Uids it wants to give up. Uid is per-player and unique, so this
-- takes the EXACT copies the player ticked -- resolving by name instead would quietly
-- substitute a different copy than the one on the tile they clicked, which with
-- mutations in play is the difference between a Golden and an Angel.
--
-- Returns an array of indices into data.Brainrots, or nil + a message to show.
local function resolveSelection(data, uids, left)
	if type(uids) ~= "table" then return nil, "Michael could not read that offer." end
	if #uids == 0 then return nil, "Pick at least one to hand over." end
	if #uids > NEED then
		return nil, ("Michael will not take more than %d at once."):format(NEED)
	end

	local indexByUid = {}
	for i, e in ipairs(data.Brainrots or {}) do
		if e.Uid then indexByUid[e.Uid] = i end
	end

	local seen, idxs = {}, {}
	for _, raw in ipairs(uids) do
		local uid = tonumber(raw)
		if not uid then return nil, "Michael could not read that offer." end
		if seen[uid] then return nil, "The same brainrot was offered twice." end
		seen[uid] = true

		local i = indexByUid[uid]
		local entry = i and data.Brainrots[i]
		if not entry then return nil, "You no longer have one of those." end
		if entry.PadIndex ~= nil then return nil, CFG.Placed end
		if not CFG.Accepts(entry) then
			return nil, ("Michael only takes MUTATED %ss."):format(CFG.Brainrot)
		end
		idxs[#idxs + 1] = i
	end

	-- never take more than is still owed: a sixth is not a favour, it is an item
	-- destroyed for nothing
	if #idxs > left then
		if left <= 0 then return nil, "Michael already has everything he asked for." end
		return nil, ("Michael only needs %d more."):format(left)
	end
	return idxs
end

-- The "give him the cheapest" convenience button, and the fallback for a caller that
-- sends no selection at all. Least valuable first, so an Angel is never taken while a
-- Golden is sitting right there.
local function autoPick(data, left)
	local pool = {}
	for _, e in ipairs(data.Brainrots or {}) do
		if e.Uid and e.PadIndex == nil and CFG.Accepts(e) then pool[#pool + 1] = e end
	end
	table.sort(pool, function(a, b) return valueOf(a) < valueOf(b) end)
	local uids = {}
	for i = 1, math.min(left, #pool) do uids[#uids + 1] = pool[i].Uid end
	return uids
end

-- What is still owed, in words. Placement is a fixable mistake, so it gets its own line.
local function shortfallMessage(left, held, placed)
	if left <= 0 then return CFG.Done end
	if held < left and held + placed >= left then return CFG.Placed end
	-- pluralise off the count: "1 mutated ... Sahur", "3 mutated ... Sahurs"
	return ("Michael is still waiting on %d mutated %s%s.")
		:format(left, CFG.Brainrot, left == 1 and "" or "s")
end
MichelQuest.Shortfall = function(data)
	local held, placed = heldPlaced(data)
	return shortfallMessage(NEED - given(data), held, placed)
end

-- Server-authoritative and re-validated: the client's button is only ever a request.
local function deliver(player, uids)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local stored = storedState(data)
	if stored == ST_NONE then
		notify(player, false, "Talk to Michael and take the job first.")
		sendState(player)
		return
	end
	if stored >= ST_DONE then
		notify(player, false, CFG.Done)
		sendState(player)
		return
	end

	local have = given(data)
	local left = NEED - have
	local held, placed = heldPlaced(data)

	-- no explicit selection = "you pick, cheapest first, as many as I can cover"
	if type(uids) ~= "table" or #uids == 0 then
		uids = autoPick(data, left)
		if #uids == 0 then
			notify(player, false, shortfallMessage(left, held, placed))
			sendState(player)
			return
		end
	end

	local idxs, err = resolveSelection(data, uids, left)
	if not idxs then
		notify(player, false, err)
		sendState(player)
		return
	end

	-- Descending, so each removal cannot shift an index still to be removed.
	table.sort(idxs, function(a, b) return a > b end)
	local taken = 0
	for _, i in ipairs(idxs) do
		local entry = data.Brainrots[i]
		if entry then
			PlayerDataManager.DrainPending(player, entry, data)   -- banked income is still theirs
			table.remove(data.Brainrots, i)
			taken += 1
		end
	end

	data.MichelGiven = math.min(NEED, have + taken)
	local finished = data.MichelGiven >= NEED
	if finished then data.MichelQuest = ST_DONE end

	-- PAID ONLY AFTER the items are gone and the state says done, so a second click that
	-- raced the first finds ST_DONE and is refused above rather than paying twice. The
	-- brainrot rides the SAME guard for the same reason -- it is the only way to mint one
	-- (BrainrotConfig: Weight = 0, QuestOnly = true), so a double-grant would be the only
	-- duplication route in the game.
	if finished then
		EmeraldService.Award(player, CFG.RewardEmeralds, "michel")
		-- Give is total and cannot refuse; it finds a free pad if there is one and otherwise
		-- leaves the item unplaced in the bag, which is the correct outcome either way.
		-- No WithinUniqueCap pre-flight because this entry is deliberately NOT Unique --
		-- see the BrainrotConfig note if that ever changes.
		if CFG.RewardBrainrot then
			BrainrotMover.Give(player, data, { Name = CFG.RewardBrainrot })
		end
	end

	pcall(InventoryHandler.SyncBackpack, player)
	PlayerDataManager.PushUpdate(player)

	if finished then
		notify(player, true, ("\u{1F985} Michael took your last %d, paid %d emeralds and handed you %s!")
			:format(taken, CFG.RewardEmeralds, CFG.RewardBrainrot or "nothing"))
	else
		local owed = NEED - data.MichelGiven
		notify(player, true, ("Michael took %d. He still wants %d more."):format(taken, owed))
	end
	sendState(player, finished and "reward" or "gave")

	-- items were destroyed AND emeralds were paid: audit the write rather than trusting
	-- the autosave. Runs on every hand-over, not just the last -- a partial delivery that
	-- failed to save would lose the brainrots and the credit for them.
	local saved = PlayerDataManager.Save(player)
	if not saved then
		warn(("[MichelQuest] SAVE FAILED after handover: %s uid=%d"):format(player.Name, player.UserId))
	end
end
MichelQuest.Deliver = deliver

function MichelQuest.Init()
	-- one action per quarter second per player: a hand-over destroys items
	local lastAction = {}

	talkRemote.OnServerEvent:Connect(function(player, action, payload)
		local now = os.clock()
		if now - (lastAction[player] or 0) < 0.25 then return end
		lastAction[player] = now

		if action == "offer" then
			if type(payload) == "table" and #payload > NEED then
				notify(player, false, ("Michael will not take more than %d at once."):format(NEED))
				return
			end
			deliver(player, type(payload) == "table" and payload or nil)
		else
			accept(player)
		end
	end)

	local function onJoin(player)
		task.spawn(function()
			local tries = 0
			while not PlayerDataManager.Get(player) and tries < 60 do task.wait(0.1); tries += 1 end
			local data = PlayerDataManager.Get(player)
			if data then
				given(data)   -- clamp/backfill the counter before anything reads it
				task.wait(1)
				sendState(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, p in ipairs(Players:GetPlayers()) do onJoin(p) end

	-- WATCHER: possession changes through paths this module never sees (catch/sell/place/
	-- trade/fuse/offer). Recompute a cheap signature and push only when it actually moves.
	-- This is also what makes a fresh catch light the quest up without ThrowHandler having
	-- to know Michel exists.
	local lastSig = {}
	task.spawn(function()
		while true do
			task.wait(2)
			for _, player in ipairs(Players:GetPlayers()) do
				local data = PlayerDataManager.Get(player)
				if data and storedState(data) == ST_COLLECTING then
					local held, placed = heldPlaced(data)
					local sig = ("%d.%d.%d"):format(given(data), held, placed)
					if lastSig[player] ~= sig then lastSig[player] = sig; sendState(player) end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastSig[player] = nil
		wasReady[player] = nil
	end)

	print(("MichelQuest online (%d mutated %s -> %d emeralds)")
		:format(NEED, CFG.Brainrot, CFG.RewardEmeralds))
end

return MichelQuest
