-- CellarDoor: the padlocked hatch on the grass west of the fishing hut.
--
-- TWO KEYS, as of this pass. The hatch is the gate to the dungeon and to the Frozen
-- Tundra portal beyond it, so it now costs BOTH questline rewards:
--     * Elder Tung's Cellar Key -- the HasCellarKey player attribute (or a Tool named
--       KEY_NAME). Not a currency: you have it or you don't.
--     * one of Stupid Gianluca's Keys -- data.Keys, and it is SPENT on the way in.
-- The Tundra portal used to charge that Gianluca key itself; that lock is gone (its
-- PortalTouch no longer carries RequiresKey) and the cost moved here, so there is ONE
-- gate to the whole underground rather than two in a row.
--
-- Paid once, open forever: the spend stamps data.CellarUnlocked and every later trip is
-- free FOR THAT PLAYER.
--
-- PER-PLAYER. This script never touches the leaves or the padlock. It validates the
-- keys and fires the CellarDoor remote to that ONE player; StarterPlayerScripts.
-- CellarDoorClient swings the hatch LOCALLY on their machine only, so a keyholder
-- cannot walk a friend down the ladder. Local changes to a workspace part never
-- replicate up and nothing here writes to those parts, so each client's hatch is
-- independent.
--
-- The BACKSTOP below is what is actually authoritative. Local geometry is by definition
-- tamperable, so a position check runs server-side: anyone underground without the
-- entitlement is put back on the grass.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)

local cellar   = workspace:WaitForChild("GameWorld"):WaitForChild("Cellar")
local entrance = cellar:WaitForChild("Entrance")
local padlock  = entrance:WaitForChild("Padlock")
local prompt   = padlock.Body:WaitForChild("CellarPrompt")

local KEY_NAME    = cellar:GetAttribute("RequiredKey") or "Cellar Key"
local GIANLUCA_KEYS = 1              -- how many of data.Keys the way in costs
local UNLOCK_FLAG = "CellarUnlocked" -- stamped on the profile once paid

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local doorRemote = remotes:FindFirstChild("CellarDoor")
if not doorRemote then
	doorRemote = Instance.new("RemoteEvent")
	doorRemote.Name = "CellarDoor"
	doorRemote.Parent = remotes
end

local function notify(player, ok, message)
	local remote = remotes:FindFirstChild("PurchaseResult")
	if remote then
		remote:FireClient(player, { Success = ok, Message = message })
	end
end

-- Elder Tung's half. Runtime attribute, or the Tool, exactly as before.
local function hasTungKey(player)
	if player:GetAttribute("HasCellarKey") then return true end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack and backpack:FindFirstChild(KEY_NAME) then return true end
	local char = player.Character
	if char and char:FindFirstChild(KEY_NAME) then return true end
	return false
end

local function gianlucaKeys(player)
	local data = PlayerDataManager.Get(player)
	return data and (tonumber(data.Keys) or 0) or 0
end

local function alreadyPaid(player)
	local data = PlayerDataManager.Get(player)
	return data and data[UNLOCK_FLAG] == true
end

-- READ-ONLY. Used by the trespass backstop, which runs twice a second and must never
-- spend anything -- that is why the paying path is a separate function.
local function mayBeDownThere(player)
	if alreadyPaid(player) then return true end
	return hasTungKey(player) and gianlucaKeys(player) >= GIANLUCA_KEYS
end

-- Spends the Gianluca key and stamps the profile. Returns true if the way is open.
local function tryUnlock(player)
	if alreadyPaid(player) then return true end

	local hasTung = hasTungKey(player)
	local keys = gianlucaKeys(player)
	if not hasTung or keys < GIANLUCA_KEYS then
		-- name the MISSING half rather than a flat refusal: two different quests hand
		-- these out and "you need a key" would not say which one to go and do
		local missing
		if not hasTung and keys < GIANLUCA_KEYS then
			missing = ("Elder Tung's %s AND %d of Gianluca's keys"):format(KEY_NAME, GIANLUCA_KEYS)
		elseif not hasTung then
			missing = ("Elder Tung's %s"):format(KEY_NAME)
		else
			missing = ("%d of Gianluca's keys (you have %d)"):format(GIANLUCA_KEYS, keys)
		end
		notify(player, false, ("\u{1F512} The cellar takes TWO keys. You still need %s."):format(missing))
		return false
	end

	local data = PlayerDataManager.Get(player)
	if not data then return false end
	data.Keys = keys - GIANLUCA_KEYS
	data[UNLOCK_FLAG] = true
	PlayerDataManager.PushUpdate(player)
	notify(player, true, "\u{1F513} Both keys turn. The cellar is open to you \u{2014} for good.")
	return true
end

-- Who has already had it swing open. Re-sent on respawn so a keyholder who dies
-- underground does not come back to a hatch their own client thinks is shut.
--
-- SEEDED FROM THE PROFILE, not just from what happened this session. data.CellarUnlocked
-- is stamped the moment both keys are spent and never cleared, so a player who has paid
-- should find the hatch already open on every future join. Without the seed below this
-- table started empty each session and they had to walk up and trigger the prompt again
-- every single time -- it cost them nothing, but it read as the door having re-locked.
local opened = {}

local function markOpenIfPaid(player)
	-- the profile may not be loaded the instant they join; wait briefly for it
	task.spawn(function()
		for _ = 1, 40 do
			if PlayerDataManager.Get(player) then break end
			task.wait(0.25)
		end
		if player.Parent and alreadyPaid(player) then
			opened[player] = true
			if player.Character then doorRemote:FireClient(player, "already") end
		end
	end)
end

prompt.Triggered:Connect(function(player)
	if opened[player] then
		doorRemote:FireClient(player, "already")
		return
	end
	if tryUnlock(player) then
		opened[player] = true
		doorRemote:FireClient(player, "open")
	else
		doorRemote:FireClient(player, "rattle")
	end
end)

Players.PlayerRemoving:Connect(function(player) opened[player] = nil end)

local function hookRespawn(player)
	player.CharacterAdded:Connect(function()
		task.wait(1.5)
		if opened[player] then doorRemote:FireClient(player, "already") end
	end)
end
Players.PlayerAdded:Connect(function(player)
	hookRespawn(player)
	markOpenIfPaid(player)
end)
for _, p in ipairs(Players:GetPlayers()) do
	hookRespawn(p)
	markOpenIfPaid(p)
end

--=========================== SERVER-SIDE BACKSTOP ==========================--
-- The one check that does not depend on client geometry. Anyone below the hatch line
-- inside the cellar's footprint without the entitlement is lifted back onto the grass.
local cellarCF, cellarSize = cellar:GetBoundingBox()
local MIN = cellarCF.Position - cellarSize * 0.5
local MAX = cellarCF.Position + cellarSize * 0.5
local entranceCF = entrance:GetPivot()
local CEIL = entranceCF.Position.Y - 2.5                    -- just under the hatch leaves
local EJECT = entranceCF.Position + Vector3.new(0, 4, -7)   -- the apron, south of the hatch

local function inCellar(pos)
	return pos.Y < CEIL
		and pos.X > MIN.X and pos.X < MAX.X
		and pos.Z > MIN.Z and pos.Z < MAX.Z
end

task.spawn(function()
	while true do
		task.wait(0.5)
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and inCellar(hrp.Position) and not mayBeDownThere(player) then
				hrp.CFrame = CFrame.new(EJECT)
				notify(player, false, "The cellar is locked to whoever earned both keys.")
			end
		end
	end
end)

print(("CellarDoor online (per-player, needs '%s' + %d Gianluca key)"):format(KEY_NAME, GIANLUCA_KEYS))
