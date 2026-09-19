-- TundraQuest: Elder Tung's World 2 arc -- two trials, then the dig to the ancient cave.
--
-- The shape of it lives in ReplicatedStorage.Modules.TundraQuestConfig; this module is
-- the authority on where a given player IS in it. Read that file first, then this one.
--
-- STATE. data.TundraQuest is an INDEX into TundraQuestConfig.Stages:
--   0                  not accepted (he has not been spoken to)
--   1..Config.Count    working on that stage
--   Config.DONE        finished; CaveUnlocked stamped, cave access granted
--
-- WHY PROGRESS IS COUNTED, NOT DERIVED. Every counter here (catches, Mythics, Secrets,
-- salvage) only ever goes UP and is never rebuilt from the inventory. "Catch 300" has to
-- survive selling all 300 -- the valley questline learned this the hard way, where a
-- held-count read 0/5 again the instant the player handed the five over.
--
--   data.TundraProgress = { Catches = n, Mythics = n, Secrets = n }
--   data.TundraParts    = { Cog = n, Gear = n, Drillhead = n }
--   data.TundraDry      = partless skips in a row, for the salvage pity
--
-- Counters tick only while THEIR OWN stage is live. A player who caught a thousand
-- brainrots before ever meeting him still owes three hundred: the trial is something you
-- go and do, not an audit of what you happened to have done already.
--
-- WHERE THE DRILL IS. Nowhere on the server. It is drawn per-client by
-- StarterPlayerScripts.CaveDrillClient off the state pushed from here, for the same
-- reason the cellar hatch is (see CellarDoorClient): one shared world model cannot be
-- half-built for one player and running for another.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local EmeraldService = require(ServerScriptService.Modules.EmeraldService)
local Config = require(ReplicatedStorage.Modules.TundraQuestConfig)

local remotes = ReplicatedStorage.Remotes

local TundraQuest = {}

local function getRemote(name, class)
	local r = remotes:FindFirstChild(name)
	if not r then r = Instance.new(class); r.Name = name; r.Parent = remotes end
	return r
end
local talkRemote  = getRemote("TundraTalk", "RemoteEvent")
local stateRemote = getRemote("TundraState", "RemoteEvent")

local function notify(player, ok, msg)
	local r = remotes:FindFirstChild("PurchaseResult")
	if r then r:FireClient(player, { Success = ok, Message = msg }) end
end

-- === DATA ====================================================================
local function stageIndex(data)
	local n = math.floor(tonumber(data.TundraQuest) or 0)
	if n < 0 then n = 0 end
	if n > Config.DONE then n = Config.DONE end
	if data.TundraQuest ~= n then data.TundraQuest = n end
	return n
end

local function progress(data)
	local p = data.TundraProgress
	if type(p) ~= "table" then p = {}; data.TundraProgress = p end
	for _, s in ipairs(Config.Stages) do
		if s.Counter then p[s.Counter] = math.max(0, math.floor(tonumber(p[s.Counter]) or 0)) end
	end
	return p
end

local function parts(data)
	local t = data.TundraParts
	if type(t) ~= "table" then t = {}; data.TundraParts = t end
	for _, p in ipairs(Config.Parts) do
		t[p.Id] = math.clamp(math.floor(tonumber(t[p.Id]) or 0), 0, p.Count)
	end
	return t
end

-- === STAGE MATHS =============================================================
-- One shape for every stage kind, so the tracker and the dialogue never have to know
-- which kind they are looking at: Cur/Of is always the bar, Met is always the gate.
local function stageView(data, index)
	local s = Config.ByIndex[index]
	if not s then return nil end
	if s.Kind == "count" then
		local cur = math.min(progress(data)[s.Counter] or 0, s.Target)
		return { Cur = cur, Of = s.Target, Met = cur >= s.Target }
	elseif s.Kind == "gather" then
		local have, all = parts(data), true
		local cur = 0
		local list = {}
		for _, p in ipairs(Config.Parts) do
			local n = have[p.Id] or 0
			cur += n
			if n < p.Count then all = false end
			list[#list + 1] = { Id = p.Id, Label = p.Label, Plural = p.Plural, Have = n, Need = p.Count }
		end
		return { Cur = cur, Of = Config.PartTotal, Met = all, Parts = list }
	end
	-- "talk": there is nothing to grind, it is met the moment it is his turn to speak
	return { Cur = 0, Of = 1, Met = true, Talk = true }
end

local function payReward(player, data, reward)
	if type(reward) ~= "table" then return end
	if reward.Cash and reward.Cash > 0 then
		PlayerDataManager.GrantCash(data, reward.Cash)
	end
	if reward.Keys and reward.Keys > 0 then
		data.Keys = (tonumber(data.Keys) or 0) + reward.Keys
	end
	-- Darrels go through EmeraldService: it is the only authority on that balance and it
	-- pushes its own HUD update, so awarding it by hand here would desync the gem pill.
	if reward.Darrels and reward.Darrels > 0 then
		pcall(EmeraldService.Award, player, reward.Darrels, "tundraquest")
	end
end

-- === CAVE ACCESS =============================================================
-- Runtime-only attribute, so it is re-granted on every join for anyone already finished
-- -- exactly like the cellar key, and for the same reason: a returning player must not
-- find their own shaft sealed.
local CAVE_ATTR = Config.KeyAttribute or "HasCaveAccess"
local function grantCaveAccess(player) player:SetAttribute(CAVE_ATTR, true) end

-- === STATE PUSH ==============================================================
local function buildPayload(data)
	local index = stageIndex(data)
	local done = index >= Config.DONE
	local view = (not done) and stageView(data, index) or nil
	local stage = Config.ByIndex[index]
	-- FIELD NAMES ARE THE TRACKER'S, NOT THIS MODULE'S. QuestTrackerClient reads every
	-- questline through the same three keys -- State (the numeric stage), Step and Of
	-- (live progress) -- and picking prettier names here would mean the row could never
	-- show a number.
	return {
		State = index,
		Step = view and view.Cur or 0,
		Of = view and view.Of or 0,
		StageId = stage and stage.Id or (done and "Done" or "None"),
		Kind = stage and stage.Kind or nil,
		Title = stage and stage.Title or nil,
		Track = stage and stage.Track or nil,
		Met = view and view.Met or false,
		Parts = view and view.Parts or nil,
		Stages = Config.Count,
		Done = done,
		Unlocked = data[Config.RewardFlag] and true or false,
	}
end

local function sendState(player, note, extra)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local payload = buildPayload(data)
	payload.Note = note
	if type(extra) == "table" then
		for k, v in pairs(extra) do payload[k] = v end
	end
	stateRemote:FireClient(player, payload)
end
TundraQuest.SendState = sendState

-- === ADVANCING ===============================================================
-- Finishing a stage pays its reward and moves the index on. Loops, because clearing a
-- "count" stage can leave the player standing on the next one already satisfied (he owes
-- ten Secrets and has been catching them the whole time), and stopping halfway would
-- leave a bar sitting full with nothing to press.
--
-- "talk" stages are NEVER auto-completed: they are the story beats, and they only happen
-- with him in the room. allowTalk is true only on the path that came from the prompt, and
-- it is spent on the FIRST completion -- one press of E is one beat. Without that, walking
-- in with the second trial already finished would clear the trial AND the greeting in the
-- same press, and the reveal the whole arc turns on would never be read.
local function completeStage(player, data, index)
	local stage = Config.ByIndex[index]
	if not stage then return end
	payReward(player, data, stage.Reward)
	data.TundraQuest = index + 1
	if stage.Unlock then
		data[Config.RewardFlag] = true
		grantCaveAccess(player)
	end
end

local function advance(player, data, allowTalk)
	local moved, cutscene = false, nil
	while true do
		local index = stageIndex(data)
		if index == Config.NONE or index >= Config.DONE then break end
		local stage = Config.ByIndex[index]
		local view = stageView(data, index)
		if not view.Met then break end
		if stage.Kind == "talk" and not allowTalk then break end
		completeStage(player, data, index)
		if stage.Cutscene then cutscene = stage.Cutscene end
		moved = true
		allowTalk = false
	end
	if moved then PlayerDataManager.PushUpdate(player) end
	return moved, cutscene
end

-- === TALKING =================================================================
local function interact(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end

	-- Belt-and-braces. The only route into the tundra is his own cellar, so this can
	-- only fail for a player teleported here by a test hook -- but a half-started arc
	-- would be worse than a refusal.
	if not data.TungPortalUnlocked then
		notify(player, false, Config.Locked)
		sendState(player, "locked")
		return
	end

	local index = stageIndex(data)
	if index >= Config.DONE then
		sendState(player, "finished")
		return
	end

	if index == Config.NONE then
		data.TundraQuest = 1
		progress(data)
		parts(data)
		PlayerDataManager.PushUpdate(player)
		sendState(player, "accept")
		return
	end

	local before = Config.ByIndex[index]
	local moved, cutscene = advance(player, data, true)
	if moved then
		sendState(player, cutscene and ("cutscene:" .. cutscene) or "advance", { Cleared = before.Id })
		if stageIndex(data) >= Config.DONE then
			-- The arc ends by destroying nothing and creating a permanent unlock, so the
			-- write is audited rather than left to the autosave.
			if not PlayerDataManager.Save(player) then
				warn(("[TundraQuest] SAVE FAILED after cave unlock: %s uid=%d")
					:format(player.Name, player.UserId))
			end
		end
	else
		sendState(player, "nag")
	end
end
TundraQuest.Interact = interact

-- === HOOKS ===================================================================
-- Called from ThrowHandler.revealCatch for EVERY landed skip (pcall'd there, so nothing
-- in here can cost a player their catch). One hook does both jobs because both are
-- "a skip finished in the tundra" and splitting them would mean two edits in the throw
-- path for one event.
local function bumpCounter(player, data, stage, n)
	local p = progress(data)
	p[stage.Counter] = math.min(stage.Target, (p[stage.Counter] or 0) + n)
	return p[stage.Counter] >= stage.Target
end

-- Which salvage to hand over. Weighted by what is still OUTSTANDING, so the single drill
-- head is not five times rarer than a cog just because there is one of it -- the last
-- item owed always has the whole weight to itself.
local function rollPart(have)
	local pool, total = {}, 0
	for _, p in ipairs(Config.Parts) do
		local left = p.Count - (have[p.Id] or 0)
		if left > 0 then
			pool[#pool + 1] = { id = p.Id, w = left }
			total += left
		end
	end
	if total == 0 then return nil end
	local r = math.random() * total
	for _, e in ipairs(pool) do
		r -= e.w
		if r <= 0 then return e.id end
	end
	return pool[#pool].id
end

function TundraQuest.NotifyCatch(player, tierName, world)
	if world ~= "Tundra" then return end
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local index = stageIndex(data)
	if index == Config.NONE or index >= Config.DONE then return end
	local stage = Config.ByIndex[index]
	if not stage then return end

	local note, extra = nil, nil

	if stage.Kind == "count" then
		-- Counters are named for what they count: Catches takes every catch, the tier
		-- counters only their own tier.
		local counts = (stage.Counter == "Catches")
			or (stage.Counter == "Mythics" and tierName == "Mythic")
			or (stage.Counter == "Secrets" and tierName == "Secret")
		if not counts then return end
		bumpCounter(player, data, stage, 1)
		note = "progress"
	elseif stage.Kind == "gather" then
		local have = parts(data)
		local dry = math.floor(tonumber(data.TundraDry) or 0)
		local lucky = (math.random() < Config.PartChance) or (dry + 1 >= Config.PartPity)
		local got = lucky and rollPart(have) or nil
		if got then
			have[got] = math.min(Config.PartById[got].Count, (have[got] or 0) + 1)
			data.TundraDry = 0
			note = "salvage"
			extra = { Salvage = got }
			local def = Config.PartById[got]
			notify(player, true, ("\u{2699} Your stone turned up a %s! (%d/%d)")
				:format(def.Label, have[got], def.Count))
		else
			data.TundraDry = dry + 1
			return   -- nothing changed worth a push; the stone landing is its own feedback
		end
	else
		return   -- a "talk" stage: skipping does not move it
	end

	-- A finished counter rolls straight into the next stage (and pays for the one just
	-- cleared) without needing him. Only the story beats need him.
	local moved = advance(player, data, false)
	if moved then
		-- The line the player sees is the stage's OWN sign-off, so a trial ending reads
		-- as him reacting rather than as a system message.
		notify(player, true, (stage.Done or "Done.") .. "  \u{2014} go and see Elder Tung.")
	end
	PlayerDataManager.PushUpdate(player)
	sendState(player, moved and "stagedone" or note, extra)
end

-- Rebirth/trade/etc. never touch this arc, so there is no watcher: everything that can
-- move it goes through the two entry points above.

function TundraQuest.Init()
	-- one action per quarter second per player, matching the valley questline's guard
	local lastAction = {}
	talkRemote.OnServerEvent:Connect(function(player)
		local now = os.clock()
		if now - (lastAction[player] or 0) < 0.25 then return end
		lastAction[player] = now
		interact(player)
	end)

	local function onJoin(player)
		task.spawn(function()
			local tries = 0
			while not PlayerDataManager.Get(player) and tries < 60 do task.wait(0.1); tries += 1 end
			local data = PlayerDataManager.Get(player)
			if data then
				progress(data); parts(data)
				if stageIndex(data) >= Config.DONE then grantCaveAccess(player) end
				-- Catch up anything that completed while they were away -- today that is
				-- only possible if the quota was lowered, but it costs nothing and means a
				-- retune never strands a player on a bar they have already cleared.
				advance(player, data, false)
				task.wait(1)
				sendState(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, p in ipairs(Players:GetPlayers()) do onJoin(p) end
	Players.PlayerRemoving:Connect(function(player) lastAction[player] = nil end)

	print(("TundraQuest online (%d stages, %d salvage parts)"):format(Config.Count, Config.PartTotal))
end

return TundraQuest
