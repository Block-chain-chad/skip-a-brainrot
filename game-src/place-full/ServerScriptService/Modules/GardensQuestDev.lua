-- GardensQuestDev: developer shortcuts for "The Old Orders", reached as
-- `/tq gardens <verb>` through DevQuest (which owns the allowlist -- nothing here checks
-- who is asking, so it must only ever be called from there).
--
-- Same reasoning as DevQuest's own verbs: the arc is 150 catches, six relic drops, three
-- catches under a bell that rings once an hour, a key behind an exploration chain -- so
-- every stage needs a way to be stood in front of directly. A jump does NOT pay the
-- rewards of the stages it skips.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local GardensQuest = require(ServerScriptService.Modules.GardensQuest)
local Config = require(ReplicatedStorage.Modules.GardensQuestConfig)

local remotes = ReplicatedStorage.Remotes

local M = {}

local function reply(player, ok, msg)
	local r = remotes:FindFirstChild("PurchaseResult")
	if r then r:FireClient(player, { Success = ok, Message = msg }) end
end

local function cacheCount(data)
	local n = 0
	for _ in pairs(data.GardensCaches or {}) do n += 1 end
	return n
end

local function statusLine(data)
	local i = tonumber(data.GardensQuest) or 0
	if i == 0 then return "stage 0 -- not accepted" end
	if i >= Config.DONE then return "DONE -- rocket unlocked" end
	local s = Config.ByIndex[i]
	local p = data.GardensProgress or {}
	if s.Kind == "count" then
		return ("stage %d (%s): %d/%d%s"):format(i, s.Id, p[s.Counter] or 0, s.Target,
			s.Gated and (" [gated on " .. s.Gated .. "]") or "")
	elseif s.Kind == "gather" then
		local have, bits = data.GardensRelics or {}, {}
		for _, def in ipairs(Config.Relics) do
			bits[#bits + 1] = ("%s %d/%d"):format(def.Id, have[def.Id] or 0, def.Count)
		end
		return ("stage %d (%s): %s"):format(i, s.Id, table.concat(bits, ", "))
	elseif s.Kind == "flag" then
		return ("stage %d (%s): %s=%s, caches %d/%d"):format(i, s.Id, s.Flag,
			tostring(data[s.Flag] == true), cacheCount(data), Config.CachesForKey)
	end
	return ("stage %d (%s): talk to the Keeper"):format(i, s.Id)
end

local function resolveStage(word)
	local n = tonumber(word)
	if n then return math.clamp(math.floor(n), 0, Config.DONE) end
	if type(word) ~= "string" then return nil end
	local want = word:lower()
	if want == "done" then return Config.DONE end
	for id, index in pairs(Config.IndexOfId) do
		if id:lower() == want then return index end
	end
	return nil
end

-- Fill whatever the CURRENT stage is asking for, so the next press of E advances it.
local function fill(data)
	local i = tonumber(data.GardensQuest) or 0
	local s = Config.ByIndex[i]
	if not s then return false end
	if s.Kind == "count" then
		data.GardensProgress = data.GardensProgress or {}
		data.GardensProgress[s.Counter] = s.Target
		return true
	elseif s.Kind == "gather" then
		data.GardensRelics = data.GardensRelics or {}
		for _, def in ipairs(Config.Relics) do data.GardensRelics[def.Id] = def.Count end
		return true
	elseif s.Kind == "flag" then
		data[s.Flag] = true
		return true
	end
	return false   -- a talk stage is already "full"; it needs the Keeper
end

local function usage()
	return "[tq gardens] usage: /tq gardens | status | stage <n|id|done> | fill | " ..
		"catch <tier> <n> [bell] | caches <n> | key | reset"
end

function M.Handle(player, rest)
	local data = PlayerDataManager.Get(player)
	if not data then reply(player, false, "your profile has not loaded yet") return end

	local verb, tail = (rest or ""):match("^(%S*)%s*(.*)$")
	verb = (verb or ""):lower()

	if verb == "" or verb == "status" then
		reply(player, true, "[tq gardens] " .. statusLine(data))

	elseif verb == "reset" then
		data.GardensQuest = 0
		data.GardensProgress = { Catches = 0, BellCatches = 0 }
		data.GardensRelics = { Banner = 0, Helm = 0, Horn = 0 }
		data.GardensDry = 0
		data.GardensCaches = {}
		data[Config.KeyFlag] = false
		data[Config.RewardFlag] = false
		player:SetAttribute(Config.KeyAttribute, nil)
		PlayerDataManager.PushUpdate(player)
		reply(player, true, "[tq gardens] reset to stage 0")

	elseif verb == "stage" or verb == "goto" then
		local index = resolveStage(tail:match("^%S*"))
		if not index then
			local ids = {}
			for _, s in ipairs(Config.Stages) do ids[#ids + 1] = s.Id end
			reply(player, false, "[tq gardens] stage <0-" .. Config.DONE .. "|" .. table.concat(ids, "|") .. "|done>")
			return
		end
		data.GardensQuest = index
		data.CaveUnlocked = true   -- the arc refuses to start without the shaft
		-- Land ON the stage: its counters start empty, everything before it is satisfied.
		data.GardensProgress = data.GardensProgress or {}
		for _, s in ipairs(Config.Stages) do
			if s.Counter then
				data.GardensProgress[s.Counter] = (Config.IndexOfId[s.Id] < index) and s.Target or 0
			end
		end
		data.GardensRelics = data.GardensRelics or {}
		local relicsIndex = Config.IndexOfId.Relics
		for _, def in ipairs(Config.Relics) do
			data.GardensRelics[def.Id] = (index > relicsIndex) and def.Count or 0
		end
		data[Config.KeyFlag] = (index > Config.IndexOfId.Crypt)
		if index >= Config.DONE then
			data[Config.RewardFlag] = true
			player:SetAttribute(Config.KeyAttribute, true)
		else
			data[Config.RewardFlag] = false
			player:SetAttribute(Config.KeyAttribute, nil)
		end
		PlayerDataManager.PushUpdate(player)
		reply(player, true, "[tq gardens] " .. statusLine(data))

	elseif verb == "fill" then
		if fill(data) then
			PlayerDataManager.PushUpdate(player)
			reply(player, true, "[tq gardens] filled -- " .. statusLine(data))
		else
			reply(player, false, "[tq gardens] nothing to fill on a talk stage; go and see the Keeper")
		end

	elseif verb == "catch" then
		-- Fires the REAL hook, so this exercises the counting and the relic roll exactly
		-- as a landed Gardens skip would -- including the pity streak. `bell` raises the
		-- Sentinel attribute for the duration of the call only.
		local word, count, flag = tail:match("^(%S*)%s*(%S*)%s*(%S*)$")
		local tier = (word ~= "" and word) or "Common"
		tier = tier:sub(1, 1):upper() .. tier:sub(2):lower()
		local n = math.clamp(tonumber(count) or 1, 1, 200)
		local bell = (flag or ""):lower() == "bell"
		local attr = Config.SentinelAttr
		local was = ReplicatedStorage:GetAttribute(attr)
		if bell then ReplicatedStorage:SetAttribute(attr, true) end
		for _ = 1, n do
			GardensQuest.NotifyCatch(player, tier, Config.WorldName)
		end
		if bell then ReplicatedStorage:SetAttribute(attr, was) end
		reply(player, true, ("[tq gardens] %d x %s%s -- %s"):format(n, tier, bell and " (bell)" or "", statusLine(data)))

	elseif verb == "caches" then
		local n = math.clamp(tonumber(tail:match("^%S*")) or 1, 1, 8)
		for i = 1, n do GardensQuest.AddCache(player, "dev" .. i) end
		reply(player, true, ("[tq gardens] caches now %d"):format(cacheCount(data)))

	elseif verb == "key" then
		data[Config.KeyFlag] = true
		PlayerDataManager.PushUpdate(player)
		reply(player, true, "[tq gardens] crypt key granted")

	else
		reply(player, false, usage())
		return
	end

	GardensQuest.SendState(player)
end

return M
