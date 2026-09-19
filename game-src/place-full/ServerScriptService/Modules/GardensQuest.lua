-- GardensQuest: "The Old Orders" -- Elder Tung's World 3 arc, read by the Keeper.
--
-- The shape lives in ReplicatedStorage.Modules.GardensQuestConfig; this module is the
-- authority on where a given player IS in it. Read that file first, then this one. It is
-- a structural copy of TundraQuest, with three additions: a stage kind that waits on a
-- FLAG (the crypt key), a count stage that only ticks while an attribute is set (the
-- bell), and a talk remote that names WHICH World 3 character was spoken to.
--
-- STATE. data.GardensQuest is an INDEX into GardensQuestConfig.Stages:
--   0                  not accepted (the Keeper has not been spoken to)
--   1..Config.Count    working on that stage
--   Config.DONE        finished; RocketUnlocked stamped, rocket access granted
--
--   data.GardensProgress = { Catches = n, BellCatches = n }
--   data.GardensRelics   = { Banner = n, Helm = n, Horn = n }
--   data.GardensDry      = relicless skips in a row, for the pity
--   data.GardensCaches   = { [cacheId] = true }  written by the cache pickups
--   data.CryptKey        = true once the Deserter has handed it over
--
-- Counters tick only while THEIR OWN stage is live and are never rebuilt from the
-- inventory -- the same rule the tundra learned the hard way.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local EmeraldService = require(ServerScriptService.Modules.EmeraldService)
local Config = require(ReplicatedStorage.Modules.GardensQuestConfig)

local remotes = ReplicatedStorage.Remotes

local GardensQuest = {}

local function getRemote(name, class)
	local r = remotes:FindFirstChild(name)
	if not r then r = Instance.new(class); r.Name = name; r.Parent = remotes end
	return r
end
local talkRemote  = getRemote("GardensTalk", "RemoteEvent")
local stateRemote = getRemote("GardensState", "RemoteEvent")

local function notify(player, ok, msg)
	local r = remotes:FindFirstChild("PurchaseResult")
	if r then r:FireClient(player, { Success = ok, Message = msg }) end
end

-- === DATA ====================================================================
local function stageIndex(data)
	local n = math.floor(tonumber(data.GardensQuest) or 0)
	if n < 0 then n = 0 end
	if n > Config.DONE then n = Config.DONE end
	if data.GardensQuest ~= n then data.GardensQuest = n end
	return n
end

local function progress(data)
	local p = data.GardensProgress
	if type(p) ~= "table" then p = {}; data.GardensProgress = p end
	for _, s in ipairs(Config.Stages) do
		if s.Counter then p[s.Counter] = math.max(0, math.floor(tonumber(p[s.Counter]) or 0)) end
	end
	return p
end

local function relics(data)
	local t = data.GardensRelics
	if type(t) ~= "table" then t = {}; data.GardensRelics = t end
	for _, r in ipairs(Config.Relics) do
		t[r.Id] = math.clamp(math.floor(tonumber(t[r.Id]) or 0), 0, r.Count)
	end
	return t
end

local function caches(data)
	local c = data.GardensCaches
	if type(c) ~= "table" then c = {}; data.GardensCaches = c end
	return c
end

local function cacheCount(data)
	local n = 0
	for _ in pairs(caches(data)) do n += 1 end
	return n
end

-- === STAGE MATHS =============================================================
-- One shape for every stage kind: Cur/Of is always the bar, Met is always the gate.
local function stageView(data, index)
	local s = Config.ByIndex[index]
	if not s then return nil end
	if s.Kind == "count" then
		local cur = math.min(progress(data)[s.Counter] or 0, s.Target)
		return { Cur = cur, Of = s.Target, Met = cur >= s.Target }
	elseif s.Kind == "gather" then
		local have, all = relics(data), true
		local cur = 0
		local list = {}
		for _, r in ipairs(Config.Relics) do
			local n = have[r.Id] or 0
			cur += n
			if n < r.Count then all = false end
			list[#list + 1] = { Id = r.Id, Label = r.Label, Plural = r.Plural, Have = n, Need = r.Count }
		end
		return { Cur = cur, Of = Config.RelicTotal, Met = all, Parts = list }
	elseif s.Kind == "flag" then
		local has = data[s.Flag] == true
		return { Cur = has and 1 or 0, Of = 1, Met = has, Talk = true }
	end
	-- "talk": nothing to grind, met the moment it is the Keeper's turn to speak
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
	-- Gems go through EmeraldService: it owns that balance and pushes its own HUD
	-- update, so paying them by hand here would desync the gem pill.
	if reward.Darrels and reward.Darrels > 0 then
		pcall(EmeraldService.Award, player, reward.Darrels, "gardensquest")
	end
end

-- === ROCKET ACCESS ===========================================================
-- Runtime-only attribute, re-granted on every join for anyone already finished --
-- exactly like HasCaveAccess, and for the same reason.
local ROCKET_ATTR = Config.KeyAttribute or "HasRocketAccess"
local function grantRocketAccess(player) player:SetAttribute(ROCKET_ATTR, true) end

-- === STATE PUSH ==============================================================
local function buildPayload(data)
	local index = stageIndex(data)
	local done = index >= Config.DONE
	local view = (not done) and stageView(data, index) or nil
	local stage = Config.ByIndex[index]
	-- FIELD NAMES ARE THE TRACKER'S: State / Step / Of are what QuestTrackerClient reads
	-- for every questline; the rest is for the World 3 clients.
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
		Caches = cacheCount(data),
		CryptKey = data[Config.KeyFlag] == true,
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
GardensQuest.SendState = sendState

-- === ADVANCING ===============================================================
-- Finishing a stage pays its reward and moves the index on. Loops, because clearing a
-- count stage can leave the player on the next one already satisfied.
--
-- "talk" AND "flag" stages are NEVER auto-completed: they are the story beats, and they
-- only happen with the Keeper in the room. allowTalk is spent on the FIRST completion --
-- one press of E is one beat.
local function completeStage(player, data, index)
	local stage = Config.ByIndex[index]
	if not stage then return end
	payReward(player, data, stage.Reward)
	data.GardensQuest = index + 1
	if stage.Unlock then
		data[Config.RewardFlag] = true
		grantRocketAccess(player)
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
		if view.Talk and not allowTalk then break end
		completeStage(player, data, index)
		if stage.Cutscene then cutscene = stage.Cutscene end
		moved = true
		allowTalk = false
	end
	if moved then PlayerDataManager.PushUpdate(player) end
	return moved, cutscene
end

-- === TALKING =================================================================
-- The Keeper: the arc itself.
local function interactKeeper(player, data)
	-- The only way into the Gardens is the shaft the tundra arc opens, so this can only
	-- fail for a player teleported here by a test hook -- but a half-started arc would be
	-- worse than a refusal.
	if not data.CaveUnlocked then
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
		data.GardensQuest = 1
		progress(data)
		relics(data)
		PlayerDataManager.PushUpdate(player)
		sendState(player, "accept")
		return
	end

	local before = Config.ByIndex[index]
	local moved, cutscene = advance(player, data, true)
	if moved then
		sendState(player, cutscene and ("cutscene:" .. cutscene) or "advance", { Cleared = before.Id })
		if stageIndex(data) >= Config.DONE then
			-- The arc ends by creating a permanent unlock, so the write is audited rather
			-- than left to the autosave.
			if not PlayerDataManager.Save(player) then
				warn(("[GardensQuest] SAVE FAILED after rocket unlock: %s uid=%d")
					:format(player.Name, player.UserId))
			end
		end
	else
		sendState(player, "nag")
	end
end

-- The Deserter: hands over the crypt key once the Scavenger's price has been paid.
-- Everything else about him is client-side flavour; this is the one thing that has to
-- be true on the server.
local function interactDeserter(player, data)
	local index = stageIndex(data)
	local cryptIndex = Config.IndexOfId.Crypt
	if index ~= cryptIndex then
		sendState(player, "deserter")
		return
	end
	if data[Config.KeyFlag] == true then
		sendState(player, "key")
		return
	end
	if cacheCount(data) < Config.CachesForKey then
		sendState(player, "deserternag")
		return
	end
	data[Config.KeyFlag] = true
	PlayerDataManager.PushUpdate(player)
	notify(player, true, "\u{1F5DD} The Deserter hands you the crypt key.")
	sendState(player, "key")
end

local function interact(player, role)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	if role == nil or role == Config.NpcRole then
		interactKeeper(player, data)
	elseif role == "Deserter" then
		interactDeserter(player, data)
	else
		-- every other role is client-only flavour; a stray call is answered with the
		-- current state so a client that asked never waits on nothing
		sendState(player, "state")
	end
end
GardensQuest.Interact = interact

-- === HOOKS ===================================================================
-- Called from ThrowHandler.revealCatch for EVERY landed skip (pcall'd there, so nothing
-- in here can cost a player their catch).
local function bumpCounter(data, stage, n)
	local p = progress(data)
	p[stage.Counter] = math.min(stage.Target, (p[stage.Counter] or 0) + n)
	return p[stage.Counter] >= stage.Target
end

-- Which relic to hand over: weighted by what is still OUTSTANDING, so the single horn
-- is not three times rarer than a banner scrap just because there is one of it.
local function rollRelic(have)
	local pool, total = {}, 0
	for _, r in ipairs(Config.Relics) do
		local left = r.Count - (have[r.Id] or 0)
		if left > 0 then
			pool[#pool + 1] = { id = r.Id, w = left }
			total += left
		end
	end
	if total == 0 then return nil end
	local roll = math.random() * total
	for _, e in ipairs(pool) do
		roll -= e.w
		if roll <= 0 then return e.id end
	end
	return pool[#pool].id
end

function GardensQuest.NotifyCatch(player, tierName, world)
	if world ~= Config.WorldName then return end
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local index = stageIndex(data)
	if index == Config.NONE or index >= Config.DONE then return end
	local stage = Config.ByIndex[index]
	if not stage then return end

	local note, extra = nil, nil

	if stage.Kind == "count" then
		-- The bell: a gated counter only ticks while the attribute the Sentinel Hour
		-- service publishes is true. Read at reveal time, so a catch that LANDS as the
		-- bell stops does not count -- the player was told not to stand still.
		if stage.Gated and ReplicatedStorage:GetAttribute(stage.Gated) ~= true then return end
		bumpCounter(data, stage, 1)
		note = "progress"
	elseif stage.Kind == "gather" then
		local have = relics(data)
		local dry = math.floor(tonumber(data.GardensDry) or 0)
		local lucky = (math.random() < Config.RelicChance) or (dry + 1 >= Config.RelicPity)
		local got = lucky and rollRelic(have) or nil
		if got then
			have[got] = math.min(Config.RelicById[got].Count, (have[got] or 0) + 1)
			data.GardensDry = 0
			note = "salvage"
			extra = { Salvage = got }
			local def = Config.RelicById[got]
			notify(player, true, ("\u{1F3F7} Your stone turned up a %s! (%d/%d)")
				:format(def.Label, have[got], def.Count))
		else
			data.GardensDry = dry + 1
			return   -- nothing changed worth a push
		end
	else
		return   -- a talk or flag stage: skipping does not move it
	end

	-- A finished counter rolls straight into the next stage without the Keeper. Only
	-- the story beats need him.
	local moved = advance(player, data, false)
	if moved then
		notify(player, true, (stage.Done or "Done.") .. "  \u{2014} go and see the Keeper.")
	end
	PlayerDataManager.PushUpdate(player)
	sendState(player, moved and "stagedone" or note, extra)
end

-- Called by the cache pickups (a later plan) and by the dev verb. Returns true if the
-- cache was new. Caches are a SET keyed by id, so a pickup can fire twice safely.
function GardensQuest.AddCache(player, cacheId)
	if type(cacheId) ~= "string" or cacheId == "" then return false end
	local data = PlayerDataManager.Get(player)
	if not data then return false end
	local c = caches(data)
	if c[cacheId] then return false end
	c[cacheId] = true
	PlayerDataManager.PushUpdate(player)
	notify(player, true, ("\u{1F4E6} You found one of the trader's caches. (%d)"):format(cacheCount(data)))
	sendState(player, "cache")
	return true
end

function GardensQuest.Init()
	-- one action per quarter second per player, matching every other questline's guard
	local lastAction = {}
	talkRemote.OnServerEvent:Connect(function(player, role)
		local now = os.clock()
		if now - (lastAction[player] or 0) < 0.25 then return end
		lastAction[player] = now
		if role ~= nil and typeof(role) ~= "string" then return end
		interact(player, role)
	end)

	local function onJoin(player)
		task.spawn(function()
			local tries = 0
			while not PlayerDataManager.Get(player) and tries < 60 do task.wait(0.1); tries += 1 end
			local data = PlayerDataManager.Get(player)
			if data then
				progress(data); relics(data); caches(data)
				if stageIndex(data) >= Config.DONE then grantRocketAccess(player) end
				-- catch up anything that completed while they were away (a lowered quota)
				advance(player, data, false)
				task.wait(1)
				sendState(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, p in ipairs(Players:GetPlayers()) do onJoin(p) end
	Players.PlayerRemoving:Connect(function(player) lastAction[player] = nil end)

	print(("GardensQuest online (%d stages, %d relics)"):format(Config.Count, Config.RelicTotal))
end

return GardensQuest
