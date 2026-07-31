-- MaxwellQuest: Maxwell the cat's secret questline. Unlocks at Rebirth 3 (below
-- that he only meows -- see CatDialogueClient). Two steps, then a reward:
--   Step 1: discover EVERY Secret-rarity brainrot in the index (one of each).
--   Step 2: reach Rebirth 25.
--   Reward: one God-rarity "Maxwell" brainrot (Unique, questline-only).
--
-- State lives in data.MaxwellQuest:
--   0 = not accepted (locked below Rebirth 3; offered at 3+)
--   1 = collecting Secrets -- progress = how many Secret names are in data.Discovered
--   2 = have every Secret -- now reach Rebirth 25
--   3 = reached Rebirth 25 -- reward ready to claim from Maxwell
--   4 = done, God Maxwell awarded
--
-- The client drives the dialogue (CatDialogueClient) and fires MaxwellTalk with an
-- action ("accept" for 0->1, "claim" for 3->4); the server validates every
-- transition. Progress is pushed back via MaxwellState so the dialogue and the
-- quest tracker always show the real, server-authoritative numbers.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local InventoryHandler = require(ServerScriptService.Modules.InventoryHandler)
local BrainrotMover = require(ServerScriptService.Modules.BrainrotMover)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)

local remotes = ReplicatedStorage.Remotes

local UNLOCK_REBIRTHS = 3      -- quest is offered at/above this rebirth count
local REBIRTHS_NEEDED = 25     -- rebirth milestone for step 2
local REWARD_NAME     = "Maxwell"  -- God-rarity questline reward (BrainrotConfig)

-- Step 1 is "have one of every Secret in your index" -- built from the config so it
-- tracks the roster automatically (currently the 11 Secret-rarity names).
local SECRET_NAMES = {}
for _, e in ipairs(BrainrotConfig) do
	if e.Rarity == "Secret" then SECRET_NAMES[#SECRET_NAMES + 1] = e.Name end
end
local SECRET_TOTAL = #SECRET_NAMES

-- how many distinct Secret names sit in the player's discovery index
local function countSecretsDiscovered(data)
	local d = data.Discovered
	if type(d) ~= "table" then return 0 end
	local n = 0
	for _, name in ipairs(SECRET_NAMES) do
		if d[name] then n += 1 end
	end
	return n
end

local MaxwellQuest = {}

local function getRemote(name, class)
	local r = remotes:FindFirstChild(name)
	if not r then r = Instance.new(class); r.Name = name; r.Parent = remotes end
	return r
end
local talkRemote  = getRemote("MaxwellTalk", "RemoteEvent")
local stateRemote = getRemote("MaxwellState", "RemoteEvent")

-- Push the whole quest picture. Step/Of are generic progress numbers the quest
-- tracker reads straight through for its pill, so the card shows live secrets x/N
-- then rebirth x/25 without the tracker needing to know anything Maxwell-specific.
local function sendState(player, note)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local st = data.MaxwellQuest or 0
	local secrets = countSecretsDiscovered(data)
	local rebirths = data.Rebirths or 0
	local step, of
	if st == 1 then step, of = secrets, SECRET_TOTAL
	elseif st == 2 then step, of = math.min(rebirths, REBIRTHS_NEEDED), REBIRTHS_NEEDED
	elseif st == 3 then step, of = 1, 1 end
	stateRemote:FireClient(player, {
		State = st,
		Secrets = secrets,
		SecretsNeeded = SECRET_TOTAL,
		Rebirths = rebirths,
		RebirthsNeeded = REBIRTHS_NEEDED,
		Unlock = UNLOCK_REBIRTHS,
		Step = step,
		Of = of,
		Note = note,
	})
end
MaxwellQuest.SendState = sendState

-- Advance state 2 -> 3 the instant the Rebirth bar is met. Called from every place
-- a rebirth total might already satisfy it (join, reaching step 2 while already
-- past 25, a fresh rebirth) so the player is never stuck on a bar they've cleared.
local function checkRebirthGate(player, data)
	if (data.MaxwellQuest or 0) == 2 and (data.Rebirths or 0) >= REBIRTHS_NEEDED then
		data.MaxwellQuest = 3
		PlayerDataManager.PushUpdate(player)
		return true
	end
	return false
end

-- Advance state 1 -> 2 once every Secret is in the index. Chains into the rebirth
-- gate so a maxed-out player can clear both at once.
local function checkSecretGate(player, data)
	if (data.MaxwellQuest or 0) == 1 and countSecretsDiscovered(data) >= SECRET_TOTAL then
		data.MaxwellQuest = 2
		PlayerDataManager.PushUpdate(player)
		checkRebirthGate(player, data)
		return true
	end
	return false
end

-- talking at Rebirth 3+ accepts the quest; talking any time re-checks both gates
-- (covers Secrets/rebirths gained via trades or offline, not just fresh catches).
local function accept(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	if (data.MaxwellQuest or 0) == 0 and (data.Rebirths or 0) >= UNLOCK_REBIRTHS then
		data.MaxwellQuest = 1
		PlayerDataManager.PushUpdate(player)
	end
	checkSecretGate(player, data)
	checkRebirthGate(player, data)
	sendState(player)
end

-- claiming the reward once the whole quest is cleared
local function claim(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	checkRebirthGate(player, data)
	if (data.MaxwellQuest or 0) ~= 3 then sendState(player); return end

	local result = remotes:FindFirstChild("PurchaseResult")
	-- Unique cap, belt-and-braces. The state gate already blocks a second claim, but
	-- a player could hold one from a trade while their own quest is still open.
	if not BrainrotMover.WithinUniqueCap(REWARD_NAME,
		BrainrotMover.CountOwned(data, REWARD_NAME), 0, 1) then
		if result then
			result:FireClient(player, { Success = false,
				Message = "You already have a Maxwell." })
		end
		data.MaxwellQuest = 4
		PlayerDataManager.PushUpdate(player)
		sendState(player)
		return
	end

	table.insert(data.Brainrots, {
		Name = REWARD_NAME, PadIndex = nil, Pending = 0, Mutation = nil,
		Uid = PlayerDataManager.TakeUid(data),
	})
	if data.Discovered then data.Discovered[REWARD_NAME] = true end
	data.MaxwellQuest = 4
	InventoryHandler.SyncBackpack(player)
	PlayerDataManager.PushUpdate(player)
	if result then
		result:FireClient(player, { Success = true,
			Message = "\u{1F408} Maxwell handed you the GOD Maxwell brainrot!" })
	end
	sendState(player, "reward")
end

-- called from ThrowHandler.revealCatch for EVERY catch (guarded by a pcall there).
-- ThrowHandler sets data.Discovered[name] BEFORE this runs, so a freshly-caught
-- Secret is already counted here.
function MaxwellQuest.NotifyCatch(player, tierName)
	if tierName ~= "Secret" then return end
	local data = PlayerDataManager.Get(player)
	if not data or (data.MaxwellQuest or 0) ~= 1 then return end
	if checkSecretGate(player, data) then
		sendState(player, "secretset")   -- just completed the whole set
	else
		sendState(player, "secret")      -- a Secret discovered; push new progress
	end
end

-- called from RebirthHandler right after a rebirth increments (guarded by a pcall)
function MaxwellQuest.NotifyRebirth(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	if checkRebirthGate(player, data) then
		sendState(player, "rebirthdone")
	else
		sendState(player)
	end
end

function MaxwellQuest.Init()
	talkRemote.OnServerEvent:Connect(function(player, action)
		if action == "claim" then
			claim(player)
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
				task.wait(1)
				checkSecretGate(player, data)    -- completed the set offline (trade etc.)
				checkRebirthGate(player, data)   -- crossed Rebirth 25 while away
				sendState(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, p in ipairs(Players:GetPlayers()) do onJoin(p) end

	print("MaxwellQuest online")
end

return MaxwellQuest
