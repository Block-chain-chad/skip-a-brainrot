-- DevQuest: developer-only shortcuts for Elder Tung's tundra arc, and for Michel's.
--
-- WHY IT EXISTS. The arc is 300 catches, then 20 Mythics, then eight salvage drops, then
-- ten Secrets. Playing it honestly to check a single line of dialogue is hours of
-- skipping, so every stage needs a way to be stood in front of directly. Michael's quest
-- (`/tq michel`) is here for exactly the same reason and is if anything worse: he wants
-- five MUTATED copies of a Mythic, which is not a thing anyone can reach on purpose.
-- (The verb stays `michel` -- it matches the module and remote names. See the naming
-- note at the top of MichelQuestConfig.)
--
-- Same split, and the same reasoning, as DevWeather: the client turns typed text into a
-- RemoteEvent call and has no authority at all; the allowlist is HERE, in
-- ServerScriptService, where no client can read or reach it. The rewards this can hand
-- out are large (a stage jump pays every reward it skips past is NOT true -- see below --
-- but a jump to Done does stamp the cave unlock), so the gate matters.
--
-- A jump deliberately does NOT pay the rewards of the stages it skips: this is for
-- reaching a piece of content, not for granting money, and a command that quietly paid
-- 180 million would be an odd thing to leave in a live place.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local InventoryHandler = require(ServerScriptService.Modules.InventoryHandler)
local TundraQuest = require(ServerScriptService.Modules.TundraQuest)
local Config = require(ReplicatedStorage.Modules.TundraQuestConfig)
local MichelQuest = require(ServerScriptService.Modules.MichelQuest)
local MichelConfig = require(ReplicatedStorage.Modules.MichelQuestConfig)

local remotes = ReplicatedStorage.Remotes

-- Same list as DevWeather. Kept separate rather than shared so revoking one command set
-- does not silently revoke the other.
local ALLOWED = {
	[125861722] = true,   -- yeep1234
}

local DevQuest = {}

local function isDev(player)
	if ALLOWED[player.UserId] then return true end
	if game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId then
		return true
	end
	return false
end

local function reply(player, ok, msg)
	local r = remotes:FindFirstChild("PurchaseResult")
	if r then r:FireClient(player, { Success = ok, Message = msg }) end
end

local function statusLine(data)
	local i = tonumber(data.TundraQuest) or 0
	if i == 0 then return "stage 0 -- not accepted" end
	if i >= Config.DONE then return "DONE -- cave unlocked" end
	local s = Config.ByIndex[i]
	local p = data.TundraProgress or {}
	if s.Kind == "count" then
		return ("stage %d (%s): %d/%d"):format(i, s.Id, p[s.Counter] or 0, s.Target)
	elseif s.Kind == "gather" then
		local parts, bits = data.TundraParts or {}, {}
		for _, def in ipairs(Config.Parts) do
			bits[#bits + 1] = ("%s %d/%d"):format(def.Id, parts[def.Id] or 0, def.Count)
		end
		return ("stage %d (%s): %s"):format(i, s.Id, table.concat(bits, ", "))
	end
	return ("stage %d (%s): talk to him"):format(i, s.Id)
end

-- Fill whatever the CURRENT stage is asking for, so the next press of E advances it.
local function fill(data)
	local i = tonumber(data.TundraQuest) or 0
	local s = Config.ByIndex[i]
	if not s then return false end
	if s.Kind == "count" then
		data.TundraProgress = data.TundraProgress or {}
		data.TundraProgress[s.Counter] = s.Target
		return true
	elseif s.Kind == "gather" then
		data.TundraParts = data.TundraParts or {}
		for _, def in ipairs(Config.Parts) do data.TundraParts[def.Id] = def.Count end
		return true
	end
	return false   -- a talk stage is already "full"; it needs him, not a counter
end

-- Stage index from a number OR a stage Id ("parts", "fuel", ...), case-insensitively.
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

local function handle(player, line)
	local data = PlayerDataManager.Get(player)
	if not data then reply(player, false, "your profile has not loaded yet") return end

	local verb, rest = line:match("^(%S*)%s*(.*)$")
	verb = (verb or ""):lower()

	if verb == "" or verb == "status" then
		reply(player, true, "[tq] " .. statusLine(data))
		TundraQuest.SendState(player)
		return
	end

	if verb == "unlock" then
		-- The arc refuses to start until the VALLEY questline is finished, because the
		-- cellar is the only way here. Testing in the tundra without having played that
		-- through needs this.
		data.TungPortalUnlocked = true
		PlayerDataManager.PushUpdate(player)
		reply(player, true, "[tq] cellar questline marked complete -- Tung will talk to you")

	elseif verb == "reset" then
		data.TundraQuest = 0
		data.TundraProgress = { Catches = 0, Mythics = 0, Secrets = 0 }
		data.TundraParts = { Cog = 0, Gear = 0, Drillhead = 0 }
		data.TundraDry = 0
		data[Config.RewardFlag] = false
		player:SetAttribute(Config.KeyAttribute, nil)
		PlayerDataManager.PushUpdate(player)
		reply(player, true, "[tq] reset to stage 0")

	elseif verb == "catch" then
		-- Fires the REAL throw hook, so this exercises the tier counting and the salvage
		-- roll exactly as a landed skip would -- including the pity streak. Needed because
		-- the honest route to one salvage drop is several minutes of throwing, and the
		-- route to a Secret is considerably longer than that.
		local word, count = rest:match("^(%S*)%s*(%S*)$")
		local tier = (word ~= "" and word) or "Common"
		tier = tier:sub(1, 1):upper() .. tier:sub(2):lower()
		local n = math.clamp(math.floor(tonumber(count) or 1), 1, 400)
		for _ = 1, n do
			TundraQuest.NotifyCatch(player, tier, "Tundra")
		end
		reply(player, true, ("[tq] simulated %d %s catch(es) -- %s"):format(n, tier, statusLine(data)))

	elseif verb == "fill" then
		if fill(data) then
			PlayerDataManager.PushUpdate(player)
			reply(player, true, "[tq] current stage filled -- " .. statusLine(data))
		else
			reply(player, false, "[tq] nothing to fill on " .. statusLine(data))
		end

	elseif verb == "michel" then
		-- Michel's own shortcuts. `give` mints entries in EXACTLY the shape ThrowHandler
		-- and GianlucaQuest use (Name/PadIndex/Pending/Mutation/Uid off TakeUid), so a
		-- granted copy is indistinguishable from a caught one to every other system --
		-- otherwise this would be testing something the game never produces.
		local sub, arg = rest:match("^(%S*)%s*(%S*)$")
		sub = (sub or ""):lower()

		if sub == "reset" then
			data.MichelQuest = 0
			data.MichelGiven = 0
			PlayerDataManager.PushUpdate(player)
			reply(player, true, "[tq] Michael reset to not-accepted")

		elseif sub == "give" then
			local n = math.clamp(math.floor(tonumber(arg) or MichelConfig.Count), 1, 20)
			-- a spread of mutations rather than five Goldens, so the picker's
			-- colour-by-mutation and its cheapest-first ordering are both exercised
			local muts = { "Golden", "Diamond", "Frozen", "Rainbow", "Celestial" }
			data.Brainrots = data.Brainrots or {}
			for i = 1, n do
				table.insert(data.Brainrots, {
					Name = MichelConfig.Brainrot,
					PadIndex = nil,
					Pending = 0,
					Mutation = muts[((i - 1) % #muts) + 1],
					Uid = PlayerDataManager.TakeUid(data),
				})
			end
			pcall(InventoryHandler.SyncBackpack, player)
			PlayerDataManager.PushUpdate(player)
			reply(player, true, ("[tq] granted %d mutated %s"):format(n, MichelConfig.Brainrot))

		elseif sub == "status" or sub == "" then
			reply(player, true, ("[tq] Michael: state %d, delivered %d/%d")
				:format(tonumber(data.MichelQuest) or 0, tonumber(data.MichelGiven) or 0, MichelConfig.Count))

		else
			reply(player, false, "[tq] usage: /tq michel <status|reset|give [n]>")
		end

		-- his own state channel, not Tung's; the tail call below would push the wrong one
		MichelQuest.SendState(player)
		return

	elseif verb == "stage" or verb == "goto" then
		local index = resolveStage(rest:match("^%S*"))
		if not index then
			local ids = {}
			for _, s in ipairs(Config.Stages) do ids[#ids + 1] = s.Id end
			reply(player, false, "[tq] stage <0-" .. Config.DONE .. "|" .. table.concat(ids, "|") .. "|done>")
			return
		end
		data.TundraQuest = index
		data.TungPortalUnlocked = true
		-- Land ON the stage rather than past it: counters for the target stage are zeroed
		-- so its bar starts empty, and everything before it is treated as satisfied.
		data.TundraProgress = data.TundraProgress or {}
		for _, s in ipairs(Config.Stages) do
			if s.Counter then
				data.TundraProgress[s.Counter] = (Config.IndexOfId[s.Id] < index) and s.Target or 0
			end
		end
		data.TundraParts = data.TundraParts or {}
		local partsIndex = Config.IndexOfId.Parts
		for _, def in ipairs(Config.Parts) do
			data.TundraParts[def.Id] = (index > partsIndex) and def.Count or 0
		end
		if index >= Config.DONE then
			data[Config.RewardFlag] = true
			player:SetAttribute(Config.KeyAttribute, true)
		else
			data[Config.RewardFlag] = false
			player:SetAttribute(Config.KeyAttribute, nil)
		end
		PlayerDataManager.PushUpdate(player)
		reply(player, true, "[tq] " .. statusLine(data))

	else
		reply(player, false,
			"[tq] usage: /tq | /tq unlock | /tq stage <n|id|done> | /tq fill | /tq catch <tier> <n> | /tq reset"
			.. " | /tq michel <status|reset|give [n]>")
		return
	end

	TundraQuest.SendState(player)
end

function DevQuest.Init()
	local request = remotes:FindFirstChild("DevQuestRequest")
	if not request then
		request = Instance.new("RemoteEvent")
		request.Name = "DevQuestRequest"
		request.Parent = remotes
	end

	request.OnServerEvent:Connect(function(player, arg)
		-- gate before parsing, and silence for non-devs: an "unauthorised" reply would
		-- advertise the command to anyone who guesses it
		if not isDev(player) then return end
		if typeof(arg) ~= "string" then arg = "" end
		local ok, err = pcall(handle, player, (arg:gsub("^%s+", ""):gsub("%s+$", "")))
		if not ok then
			warn("[DevQuest] " .. tostring(err))
			reply(player, false, "[tq] error: " .. tostring(err))
		end
	end)

	print("DevQuest online (/tq)")
end

return DevQuest
