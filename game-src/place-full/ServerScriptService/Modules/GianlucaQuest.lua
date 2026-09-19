-- GianlucaQuest: the "find Gianluca's Secret Chim" questline.
--   1. Talk to Gianluca (client dialogue) -> GianlucaTalk fires -> quest goes ACTIVE.
--   2. Find the SecretChim in the world and take it -> grants the Mythic "Chim".
--   3. Bring the Chim BACK to Gianluca -> he takes it and gives you a Key.
--      (the handover only requires that you HOLD an unplaced Chim -- it does not
--       care which of the three stages you are nominally on)
--
-- State lives in data.ChimQuest:
--   0 = not started   1 = active (searching)
--   2 = holding the Chim   3 = handed it over, Key claimed
--
-- >>> STATE 3 IS ALSO A PERMANENT RETIREMENT. <<<
-- Chim's BrainrotConfig entry carries RetiredBy = "ChimQuest", RetiredAt = 3, and
-- ThrowHandler refuses to roll a name whose retirement field has reached its value.
-- So the handover on line ~122 does two things at once: it pays the Key, and it
-- takes Chim off the table for that player forever. Anything that ever rewinds this
-- number below 3 makes Chim catchable again -- which is exactly what the test hook
-- at the bottom is for, and is the reason it is a hook rather than something a
-- player action can reach.
--
-- THIS MODULE IS NO LONGER THE ONLY SOURCE. It used to be: the entry carried
-- Weight = 0 and no FixedChance, so no throw could produce one at any distance or
-- luck, and grantChim below was the single door in. Since 2026-08-19 Chim is
-- AnyTier + FixedChance, caught at flat odds on any throw anywhere -- so the
-- quest pickup and a lucky skip are two independent routes to the same one-off
-- item, and Unique = true is what keeps them from stacking.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local InventoryHandler = require(ServerScriptService.Modules.InventoryHandler)
local BrainrotMover = require(ServerScriptService.Modules.BrainrotMover)

local remotes = ReplicatedStorage.Remotes
local REWARD_NAME = "Chim"
local KEYS_PER_HANDOVER = 1

local GianlucaQuest = {}

local function getRemote(name, class)
	local r = remotes:FindFirstChild(name)
	if not r then r = Instance.new(class); r.Name = name; r.Parent = remotes end
	return r
end
local talkRemote = getRemote("GianlucaTalk", "RemoteEvent")
local stateRemote = getRemote("GianlucaState", "RemoteEvent")

local function sendState(player, note)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	stateRemote:FireClient(player, { State = data.ChimQuest or 0, Note = note })
end
GianlucaQuest.SendState = sendState

-- talking to Gianluca starts the hunt
local function startQuest(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	if (data.ChimQuest or 0) == 0 then
		data.ChimQuest = 1
		PlayerDataManager.PushUpdate(player)
	end
	sendState(player)
end

-- taking the chim grants the reward (only while the quest is active)
local function grantChim(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local st = data.ChimQuest or 0
	if st ~= 1 then
		if st == 0 then sendState(player, "hint") end   -- found it early: nudge them to Gianluca
		return
	end
	-- Unique cap, belt-and-braces. The ChimQuest state gate above already makes a second
	-- grant impossible, but a player could hold one received by TRADE while their own
	-- quest is still active -- and then this grant would be their second.
	if not BrainrotMover.WithinUniqueCap(REWARD_NAME,
		BrainrotMover.CountOwned(data, REWARD_NAME), 0, 1) then
		local result = remotes:FindFirstChild("PurchaseResult")
		if result then
			result:FireClient(player, { Success = false,
				Message = ("You already have a %s \u{2014} take it to Gianluca."):format(REWARD_NAME) })
		end
		return
	end
	table.insert(data.Brainrots, { Name = REWARD_NAME, PadIndex = nil, Pending = 0, Mutation = nil, Uid = PlayerDataManager.TakeUid(data) })
	if data.Discovered then data.Discovered[REWARD_NAME] = true end
	data.ChimQuest = 2
	InventoryHandler.SyncBackpack(player)
	PlayerDataManager.PushUpdate(player)
	sendState(player, "found")
end

-- handing the Chim back closes the questline and pays out the Key
local function handOver(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local result = remotes:FindFirstChild("PurchaseResult")

	-- Gated on POSSESSION, not on quest stage. The stage-2 check that used to live
	-- here assumed the only way to hold a Chim was this quest's own pickup prompt,
	-- which silently refused any Chim that arrived another way (a trade, an admin
	-- grant, a test override) -- the player would be standing there holding it while
	-- Gianluca insisted he'd lost it. The possession check below is the real
	-- authority and is the one that must not be bypassed; stage is just bookkeeping.

	-- Only an UNPLACED Chim can be handed over. A placed one is earning on a pad, and
	-- requiring pickup first is the same rule SellHandler uses -- it means the handover
	-- never has to tear down a pad model or reconcile a PadIndex.
	local idx, placedOnly = nil, false
	for i, e in ipairs(data.Brainrots) do
		if e.Name == REWARD_NAME then
			if e.PadIndex == nil then idx = i; break else placedOnly = true end
		end
	end
	if not idx then
		if result then
			result:FireClient(player, { Success = false, Message = placedOnly
				and ("Your " .. REWARD_NAME .. " is on your base \u{2014} unequip it in your Bag first.")
				or ("You don't have the " .. REWARD_NAME .. " to give him.") })
		end
		return
	end

	-- drain banked income BEFORE the entry disappears, or it is silently destroyed
	PlayerDataManager.DrainPending(player, data.Brainrots[idx], data)
	table.remove(data.Brainrots, idx)
	data.Keys = (data.Keys or 0) + KEYS_PER_HANDOVER
	data.ChimQuest = 3
	InventoryHandler.SyncBackpack(player)
	PlayerDataManager.PushUpdate(player)
	if result then
		result:FireClient(player, { Success = true,
			Message = ("\u{1F511} Gianluca took the Chim and gave you a Key! (%d)"):format(data.Keys) })
	end
	sendState(player, "key")
end

-- === TEST HOOK: one-shot questline reset =============================
-- Armed by setting ServerStorage.TestResetChimQuest to a username. Attributes
-- live in the place file, so this survives the Edit -> Play transition (a Lua
-- flag would not -- the server VM is rebuilt on Play).
--
-- Rewinds the questline to "holding the Chim": clears Keys, drops any UNPLACED
-- Chim already owned, then grants exactly one fresh Chim. Placed copies are
-- left alone -- deleting the data entry for one would orphan its pad model.
--
-- Consumed exactly once; the attribute is cleared the moment it fires.
local function maybeTestReset(player)
	local ServerStorage = game:GetService("ServerStorage")
	local who = ServerStorage:GetAttribute("TestResetChimQuest")
	if type(who) ~= "string" or who == "" then return end
	-- the attribute is "Username" or "Username#token" -- match on the name part only
	if (who:match("^([^#]+)") or who) ~= player.Name then return end
	local data = PlayerDataManager.Get(player)
	if not data then return end

	-- Fire once PER PROFILE, not once per server. Clearing the attribute alone is
	-- not enough: Play runs on a clone of the Edit datamodel, so the cleared value
	-- never writes back, and the reset would re-fire on every Play -- wiping the
	-- Key the player had just earned. The token is stamped on the profile, so
	-- re-arming means giving the attribute a NEW value (e.g. "Name#2").
	if data.ChimTestToken == who then return end
	data.ChimTestToken = who
	ServerStorage:SetAttribute("TestResetChimQuest", nil)

	local dropped = 0
	for i = #data.Brainrots, 1, -1 do
		local e = data.Brainrots[i]
		if e.Name == REWARD_NAME and e.PadIndex == nil then
			table.remove(data.Brainrots, i)
			dropped += 1
		end
	end
	data.Keys = 0
	data.ChimQuest = 2
	table.insert(data.Brainrots, {
		Name = REWARD_NAME, PadIndex = nil, Pending = 0, Mutation = nil,
		Uid = PlayerDataManager.TakeUid(data),
	})
	if data.Discovered then data.Discovered[REWARD_NAME] = true end
	InventoryHandler.SyncBackpack(player)
	PlayerDataManager.PushUpdate(player)
	sendState(player)
	warn(("[GianlucaQuest] TEST reset for %s: dropped %d old Chim, granted 1, Keys=0, stage=2")
		:format(player.Name, dropped))
end

function GianlucaQuest.Init()
	-- one remote, two actions. The pre-existing client fires with no arguments, so a
	-- nil/unknown action must keep meaning "talk" or old clients would break.
	talkRemote.OnServerEvent:Connect(function(player, action)
		if action == "handover" then
			handOver(player)
		else
			startQuest(player)
		end
	end)

	-- hook the chim's pickup prompt (server-authoritative grant)
	task.spawn(function()
		local gw = Workspace:WaitForChild("GameWorld")
		local chim = gw:WaitForChild("SecretChim", 30)
		local prompt = chim and chim:WaitForChild("ChimPrompt", 30)
		if prompt then
			prompt.Triggered:Connect(function(who) grantChim(who) end)
		end
	end)

	local function onJoin(player)
		task.spawn(function()
			local tries = 0
			while not PlayerDataManager.Get(player) and tries < 60 do task.wait(0.1); tries += 1 end
			if PlayerDataManager.Get(player) then
				task.wait(1)
				maybeTestReset(player)
				sendState(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, p in ipairs(Players:GetPlayers()) do onJoin(p) end

	print("GianlucaQuest online")
end

return GianlucaQuest