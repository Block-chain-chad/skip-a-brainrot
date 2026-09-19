-- GardensNpcClient: the eight World 3 voices that are not the Keeper.
--
-- ONE client for all of them, driven by GardensNpcConfig: bind every prompt named
-- <Role>Prompt under GameWorld.LushGardens, and when it fires, show that role's lines for
-- the arc's current bucket. The Deserter is the only one with a server-side effect (the
-- crypt key); everyone else is flavour and never fires a remote.
--
-- The bucket comes from GardensState (the Keeper's arc), so a player who has never met
-- the Keeper gets the "Before" lines everywhere, and the whole town moves on together as
-- the pages are read. On a red night (WeatherName == "Blood Moon") every role swaps to
-- its BloodMoon bucket -- board P18-mod: subtle, no machine talk.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local modules = ReplicatedStorage:WaitForChild("Modules")

local MerchantDialog = require(modules:WaitForChild("MerchantDialog"))
local Npc = require(modules:WaitForChild("GardensNpcConfig"))
local Quest = require(modules:WaitForChild("GardensQuestConfig"))

local talkRemote = remotes:WaitForChild("GardensTalk")
local stateRemote = remotes:WaitForChild("GardensState")

---------------------------------------------------------------- state
local arc = { State = 0, Done = false, Caches = 0, CryptKey = false }
local anchorByRole = {}       -- [roleId] = BasePart the portrait frames
local promptToRole = {}       -- [promptName] = roleId
for roleId, def in pairs(Npc.Roles) do promptToRole[def.PromptName] = roleId end

local function isRedNight()
	return ReplicatedStorage:GetAttribute(Npc.WeatherAttr) == Npc.BloodMoonName
end

-- Which lines a role speaks right now. The Scavenger and the Deserter have extra
-- buckets that depend on the payload rather than the stage.
local function linesFor(roleId)
	local def = Npc.Roles[roleId]
	if not def then return nil, nil end
	if isRedNight() and def.Lines.BloodMoon then
		return def.Lines.BloodMoon, nil
	end
	local bucket = Npc.BucketFor(arc.State, arc.Done)
	if roleId == "Scavenger" and bucket == "Late" and (arc.Caches or 0) < Quest.CachesForKey then
		return def.Lines.LateShort or def.Lines.Late, nil
	end
	if roleId == "Deserter" and bucket == "Late" then
		if arc.CryptKey then return def.Lines.Key or def.Lines.Late, nil end
		-- the ask: the primary button sends the role to the server, which answers with
		-- note "key" or "deserternag" (handled below)
		return def.Lines.Late, def.Ask
	end
	return def.Lines[bucket] or def.Lines.Before, nil
end

local function speak(roleId)
	local def = Npc.Roles[roleId]
	if not def then return end
	local lines, ask = linesFor(roleId)
	if not lines or #lines == 0 then return end
	local onDone = nil
	if ask then
		onDone = function() talkRemote:FireServer(roleId) end
	end
	MerchantDialog.Show(def.Name, lines, def.Accent, onDone, anchorByRole[roleId], ask or "OK \u{25B6}")
end

---------------------------------------------------------------- prompts
local function bindPrompt(prompt)
	local roleId = promptToRole[prompt.Name]
	if not roleId then return end
	local host = prompt.Parent
	if not host then return end
	anchorByRole[roleId] = host:IsA("BasePart") and host or host:FindFirstChildWhichIsA("BasePart")
	prompt.Triggered:Connect(function(who)
		if who == player then speak(roleId) end
	end)
end

task.spawn(function()
	local gw = Workspace:WaitForChild("GameWorld", 60)
	local lg = gw and gw:WaitForChild("LushGardens", 60)
	if not lg then
		warn("[GardensNpcClient] no GameWorld.LushGardens -- is World 3 in the place?")
		return
	end
	for _, d in ipairs(lg:GetDescendants()) do
		if d:IsA("ProximityPrompt") and promptToRole[d.Name] then bindPrompt(d) end
	end
	lg.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") and promptToRole[d.Name] then bindPrompt(d) end
	end)
end)

---------------------------------------------------------------- state in
stateRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end
	arc.State = tonumber(payload.State) or 0
	arc.Done = payload.Done == true
	arc.Caches = tonumber(payload.Caches) or 0
	arc.CryptKey = payload.CryptKey == true

	-- The Deserter's answer to the ask, in his own words.
	local def = Npc.Roles.Deserter
	if payload.Note == "key" and def then
		task.delay(0.15, function()
			MerchantDialog.Show(def.Name, def.Lines.Key or def.Lines.Late, def.Accent, nil, anchorByRole.Deserter, "OK \u{25B6}")
		end)
	elseif payload.Note == "deserternag" and def then
		task.delay(0.15, function()
			MerchantDialog.Show(def.Name, def.Lines.NoKey or def.Lines.Late, def.Accent, nil, anchorByRole.Deserter, "OK \u{25B6}")
		end)
	end
end)
