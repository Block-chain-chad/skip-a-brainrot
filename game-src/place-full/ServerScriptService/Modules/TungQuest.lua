-- TungQuest: Elder Tung's questline -> the on-ramp to World 2.
--
-- Tung hates brainrots. He wants TWELVE handed over -- 5 Epic, 5 Legendary, 2 Mythic --
-- and the player chooses which ones, A FEW AT A TIME. Hand over one Epic today and four
-- more tomorrow; each tier ticks off permanently as it fills, and the cellar Key is paid
-- on the hand-over that completes the last one.
--
-- WHY PROGRESS IS STORED. Earlier passes derived progress from what the player was
-- HOLDING, which was right while the delivery was all-or-nothing but is wrong now: once
-- Tung has taken five Epics they are gone from the inventory, so a held-count would
-- read 0/5 again the moment they were delivered. data.TungGiven is therefore the
-- authority for progress, and it only ever goes up.
--   data.TungGiven = { Epic = n, Legendary = n, Mythic = n }   -- capped at the quota
-- What the player is HOLDING is still computed live, but only to answer "can you finish
-- this right now" and to fill the picker -- never as progress.
--
-- STATE. data.TungQuest is 0 / 1 / 3; 2 is DERIVED and never stored:
--   0 not accepted
--   1 collecting
--   2 everything still owed is in hand right now (one more visit finishes it)
--   3 delivered in full; cellar Key granted, portal flag set
-- data.TungCatch is vestigial (kept so old saves load); nothing reads it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local TungQuestConfig = require(ReplicatedStorage.Modules.TungQuestConfig)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)
local InventoryHandler = require(ServerScriptService.Modules.InventoryHandler)

-- name -> rarity / cash-per-second, so held brainrots can be bucketed and priced
local rarityByName, cpsByName = {}, {}
for _, e in ipairs(BrainrotConfig.List or BrainrotConfig) do
	rarityByName[e.Name] = e.Rarity
	cpsByName[e.Name] = e.CashPerSecond or 0
end

local remotes = ReplicatedStorage.Remotes
local REQS = TungQuestConfig.Requirements
local TOTAL = TungQuestConfig.Total

local ST_NONE, ST_COLLECTING, ST_READY, ST_DONE = 0, 1, 2, 3

local TungQuest = {}

local function getRemote(name, class)
	local r = remotes:FindFirstChild(name)
	if not r then r = Instance.new(class); r.Name = name; r.Parent = remotes end
	return r
end
local talkRemote  = getRemote("TungTalk", "RemoteEvent")
local stateRemote = getRemote("TungState", "RemoteEvent")

local function notify(player, ok, msg)
	local r = remotes:FindFirstChild("PurchaseResult")
	if r then r:FireClient(player, { Success = ok, Message = msg }) end
end

local function freshCounts() return { Epic = 0, Legendary = 0, Mythic = 0 } end

-- === STATE ====================================================================
-- Reads data.TungQuest and migrates the older encodings in place.
--
-- The short-lived staged version used 1..3 for "collecting the nth tier" and 4 for done,
-- which collides with this module's 3 = done. TungPortalUnlocked is the tiebreak: only
-- the finished path ever set it, so a 3 without it is a staged save mid-quest and goes
-- back to collecting.
local function storedState(data)
	local st = tonumber(data.TungQuest) or 0
	if st >= 4 then
		st = ST_DONE
	elseif st == 3 and not data.TungPortalUnlocked then
		st = ST_COLLECTING
	elseif st == 2 then
		st = ST_COLLECTING
	elseif st < 0 then
		st = ST_NONE
	end
	if data.TungQuest ~= st then data.TungQuest = st end
	return st
end

-- data.TungGiven, created on demand and clamped. A profile from before partial
-- hand-overs existed has no counters at all, so a finished one is backfilled to the
-- full quota rather than asking that player to deliver twelve more.
local function given(data)
	local g = data.TungGiven
	if type(g) ~= "table" then
		g = freshCounts()
		data.TungGiven = g
	end
	local done = (tonumber(data.TungQuest) or 0) >= ST_DONE
	for _, r in ipairs(REQS) do
		local n = tonumber(g[r.Tier]) or 0
		if done then n = r.Count end
		g[r.Tier] = math.clamp(math.floor(n), 0, r.Count)
	end
	return g
end
TungQuest.Given = given

-- How many of each required tier the player is HOLDING (unplaced) vs PLACED on a pad.
-- Only unplaced can be handed over -- a brainrot on a pad is earning income (the same
-- line Gianluca's Chim handover draws).
local function heldPlaced(data)
	local out = {}
	for _, r in ipairs(REQS) do out[r.Tier] = { Held = 0, Placed = 0 } end
	for _, e in ipairs(data.Brainrots or {}) do
		local t = out[rarityByName[e.Name]]
		if t then
			if e.PadIndex == nil then t.Held += 1 else t.Placed += 1 end
		end
	end
	return out
end

-- The per-tier picture the dialogue, the picker and the tracker all read.
--
-- Have IS THE DELIVERED COUNT and is capped at Need by construction -- QuestTrackerClient
-- renders "Mythic 2/2" straight off these two numbers, and an uncapped held-count is
-- exactly what made it read "Mythic 6/2".
local function tiersFor(data)
	local g = given(data)
	local hp = heldPlaced(data)
	local out = {}
	for _, r in ipairs(REQS) do
		local delivered = g[r.Tier]
		local left = r.Count - delivered
		out[r.Tier] = {
			Have = delivered,
			Need = r.Count,
			Left = left,
			Held = hp[r.Tier].Held,
			Placed = hp[r.Tier].Placed,
		}
	end
	return out
end

-- everything still owed is in hand right now
local function canFinishNow(t)
	for _, r in ipairs(REQS) do
		local e = t[r.Tier]
		if e.Left > 0 and e.Held < e.Left then return false end
	end
	return true
end

local function isComplete(t)
	for _, r in ipairs(REQS) do
		if t[r.Tier].Left > 0 then return false end
	end
	return true
end

local function valueOf(entry)
	return (cpsByName[entry.Name] or 0) * Mutations.Mult(entry.Mutation)
end

-- "quota" fires the client's one-off "you can finish this now" popup, so it must only be
-- sent on the FALSE -> TRUE edge; the watcher below re-pushes state every couple of
-- seconds while the player stands there holding the rest.
local wasReady = {}

local function sendState(player, note)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local stored = storedState(data)
	local t = tiersFor(data)

	local step = 0
	for _, r in ipairs(REQS) do step += t[r.Tier].Have end

	local ready = (stored == ST_COLLECTING) and canFinishNow(t)
	local live = ready and ST_READY or stored

	if ready ~= wasReady[player] then
		wasReady[player] = ready
		if ready then note = note or "quota" end
	end

	stateRemote:FireClient(player, {
		State = live,
		Tiers = t,
		Step = step,
		Of = TOTAL,
		Ready = ready,
		Done = stored >= ST_DONE,
		Unlocked = data.TungPortalUnlocked and true or false,
		Keys = data.Keys or 0,
		Note = note,
	})
end
TungQuest.SendState = sendState

-- change signature for the watcher: state + delivered + what is in hand per tier
local function progressSignature(data)
	local t = tiersFor(data)
	local bits = { tostring(data.TungQuest or 0) }
	for _, r in ipairs(REQS) do
		local e = t[r.Tier]
		bits[#bits + 1] = ("%s%d.%d.%d"):format(r.Tier, e.Have, e.Held, e.Placed)
	end
	return table.concat(bits, "/")
end

-- === CELLAR KEY ===============================================================
-- CellarDoor's hasKey() reads this PLAYER attribute, and the hatch is drawn per-client,
-- so the door opens for the holder alone -- nobody can hold it open for a friend.
-- Runtime-only, so this runs on the final hand-over AND on join for anyone already
-- done, or a returning keyholder would find their own cellar locked again.
local CELLAR_ATTR = TungQuestConfig.KeyAttribute or "HasCellarKey"
local function grantCellarKey(player) player:SetAttribute(CELLAR_ATTR, true) end

-- === ACCEPT ===================================================================
local function accept(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	if storedState(data) == ST_NONE then
		data.TungQuest = ST_COLLECTING
		data.TungGiven = freshCounts()
		if type(data.TungCatch) ~= "table" then data.TungCatch = freshCounts() end
		PlayerDataManager.PushUpdate(player)
	end
	sendState(player)
end
TungQuest.Accept = accept

-- === DELIVERY =================================================================
-- The client sends the Uids it wants to give up -- ANY NUMBER of them, from one up to
-- whatever is still owed. Uid is per-player and unique, so this takes the EXACT copies
-- the player picked; BrainrotMover.Take resolves by name and would quietly substitute a
-- different copy than the one on the tile they clicked.
--
-- Returns an array of indices into data.Brainrots plus the per-tier counts, or
-- nil + a message to show.
local function resolveSelection(data, uids, t)
	if type(uids) ~= "table" then return nil, "Tung could not read that offer." end
	if #uids == 0 then return nil, "Pick at least one brainrot to hand over." end
	if #uids > TOTAL then
		return nil, ("Tung will not take more than %d at once."):format(TOTAL)
	end

	local indexByUid = {}
	for i, e in ipairs(data.Brainrots or {}) do
		if e.Uid then indexByUid[e.Uid] = i end
	end

	local counts, seen, idxs = {}, {}, {}
	for _, r in ipairs(REQS) do counts[r.Tier] = 0 end

	for _, raw in ipairs(uids) do
		local uid = tonumber(raw)
		if not uid then return nil, "Tung could not read that offer." end
		if seen[uid] then return nil, "The same brainrot was offered twice." end
		seen[uid] = true

		local i = indexByUid[uid]
		local entry = i and data.Brainrots[i]
		if not entry then return nil, "You no longer have one of those brainrots." end
		if entry.PadIndex ~= nil then return nil, TungQuestConfig.Placed end

		local tier = rarityByName[entry.Name]
		if counts[tier] == nil then
			return nil, ("Tung has no use for %s."):format(entry.Name)
		end
		counts[tier] += 1
		idxs[#idxs + 1] = i
	end

	-- never take more of a tier than is still owed: a sixth Epic is not a favour,
	-- it is an item destroyed for nothing
	for _, r in ipairs(REQS) do
		local left = t[r.Tier].Left
		if counts[r.Tier] > left then
			if left == 0 then
				return nil, ("Tung already has all the %s he wanted."):format(r.Tier)
			end
			return nil, ("Tung only needs %d more %s."):format(left, r.Tier)
		end
	end
	return idxs, counts
end

-- The "give him the cheapest" convenience button, and the fallback for a caller that
-- sends no selection at all. Fills as much of what is still owed as the player can
-- actually cover -- least valuable first, so a mutated copy is never taken while a
-- plain one of the same tier is sitting right there.
local function autoPick(data, t)
	local pool = {}
	for _, r in ipairs(REQS) do pool[r.Tier] = {} end
	for _, e in ipairs(data.Brainrots or {}) do
		if e.PadIndex == nil and e.Uid then
			local b = pool[rarityByName[e.Name]]
			if b then b[#b + 1] = e end
		end
	end
	local uids = {}
	for _, r in ipairs(REQS) do
		local b = pool[r.Tier]
		table.sort(b, function(x, y) return valueOf(x) < valueOf(y) end)
		for i = 1, math.min(t[r.Tier].Left, #b) do uids[#uids + 1] = b[i].Uid end
	end
	return uids
end

-- What is still owed, in words. Placement is a fixable mistake, so it gets its own line.
local function shortfallMessage(t)
	for _, r in ipairs(REQS) do
		local e = t[r.Tier]
		if e.Held < e.Left and e.Held + e.Placed >= e.Left then return TungQuestConfig.Placed end
	end
	local missing = {}
	for _, r in ipairs(REQS) do
		local e = t[r.Tier]
		if e.Left > 0 then missing[#missing + 1] = ("%d %s"):format(e.Left, r.Tier) end
	end
	if #missing == 0 then return TungQuestConfig.Done end
	return ("Tung is still waiting on %s."):format(table.concat(missing, ", "))
end
TungQuest.Shortfall = function(data) return shortfallMessage(tiersFor(data)) end

-- Server-authoritative and re-validated: the client's button is only ever a request.
local function deliver(player, uids)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local stored = storedState(data)
	if stored == ST_NONE then
		notify(player, false, "Talk to Elder Tung and take the job first.")
		sendState(player)
		return
	end
	if stored >= ST_DONE then
		notify(player, false, TungQuestConfig.Done)
		sendState(player)
		return
	end

	local t = tiersFor(data)

	-- no explicit selection = "you pick, cheapest first, as much as I can cover"
	if type(uids) ~= "table" or #uids == 0 then
		uids = autoPick(data, t)
		if #uids == 0 then
			notify(player, false, shortfallMessage(t))
			sendState(player)
			return
		end
	end

	local idxs, counts = resolveSelection(data, uids, t)
	if not idxs then
		notify(player, false, counts)   -- second return is the message on failure
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

	local g = given(data)
	for _, r in ipairs(REQS) do
		g[r.Tier] = math.min(r.Count, g[r.Tier] + (counts[r.Tier] or 0))
	end

	local after = tiersFor(data)
	local finished = isComplete(after)
	if finished then
		data.TungQuest = ST_DONE
		data.TungPortalUnlocked = true
		-- TUNG PAYS EXACTLY ONE KEY, AND IT IS HIS OWN (2026-08-15). This used to ALSO
		-- credit data.Keys -- Gianluca's spendable currency -- so finishing Tung handed
		-- the player BOTH halves of the cellar lock at once and Gianluca's questline was
		-- optional for getting underground. That is not the design: the hatch costs one
		-- key from EACH questline (see ServerScriptService.CellarDoor, which checks the
		-- HasCellarKey attribute AND spends 1 of data.Keys). data.Keys is Gianluca's alone.
		-- Safe to drop: no portal carries RequiresKey any more, so the cellar is the only
		-- thing in the game that spends data.Keys.
		grantCellarKey(player)
	end

	pcall(InventoryHandler.SyncBackpack, player)
	PlayerDataManager.PushUpdate(player)

	if finished then
		notify(player, true, ("\u{1F511} Tung took your last %d and gave you HIS cellar Key \u{2014} Gianluca holds the other one.")
			:format(taken))
	else
		-- name what is left, so a partial hand-over still tells you where you are
		local left = {}
		for _, r in ipairs(REQS) do
			local e = after[r.Tier]
			if e.Left > 0 then left[#left + 1] = ("%d %s"):format(e.Left, r.Tier) end
		end
		notify(player, true, ("Tung took %d. Still wants %s."):format(taken, table.concat(left, ", ")))
	end
	sendState(player, finished and "key" or "gave")

	-- items were destroyed: audit the write rather than trusting the autosave. Runs on
	-- EVERY hand-over now, not just the last -- a partial delivery that failed to save
	-- would lose the brainrots and the credit for them.
	local saved = PlayerDataManager.Save(player)
	if not saved then
		warn(("[TungQuest] SAVE FAILED after handover: %s uid=%d"):format(player.Name, player.UserId))
	end
end
TungQuest.Deliver = deliver

-- Called from ThrowHandler.revealCatch for every catch (pcall'd there). Progress is the
-- delivered count, so a catch changes nothing stored -- this just re-pushes state so the
-- dialogue and the picker move the instant a qualifying catch lands.
function TungQuest.NotifyCatch(player, tierName)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	if storedState(data) ~= ST_COLLECTING then return end
	if not TungQuestConfig.ByTier[tierName] then return end
	sendState(player, "capture")
end

function TungQuest.Init()
	-- one action per quarter second per player: a hand-over destroys items
	local lastAction = {}

	talkRemote.OnServerEvent:Connect(function(player, action, payload)
		local now = os.clock()
		if now - (lastAction[player] or 0) < 0.25 then return end
		lastAction[player] = now

		if action == "offer" or action == "claim" then
			if type(payload) == "table" and #payload > TOTAL then
				notify(player, false, ("Tung will not take more than %d at once."):format(TOTAL))
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
				given(data)   -- backfill the counters before anything reads them
				if storedState(data) >= ST_DONE then grantCellarKey(player) end
				task.wait(1)
				sendState(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, p in ipairs(Players:GetPlayers()) do onJoin(p) end

	-- WATCHER: possession changes via paths this module never sees (sell/place/trade/
	-- fuse/offer). Recompute a cheap signature and push only when it actually moves.
	local lastSig = {}
	task.spawn(function()
		while true do
			task.wait(2)
			for _, player in ipairs(Players:GetPlayers()) do
				local data = PlayerDataManager.Get(player)
				if data and storedState(data) == ST_COLLECTING then
					local sig = progressSignature(data)
					if lastSig[player] ~= sig then lastSig[player] = sig; sendState(player) end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastSig[player] = nil
		wasReady[player] = nil
	end)

	print(("TungQuest online (%d brainrots, player-picked, deliverable a few at a time)"):format(TOTAL))
end

return TungQuest
