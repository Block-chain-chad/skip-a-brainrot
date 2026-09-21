-- GianlucaClient (V2.5 production pass) -- the DROP-IN replacement for the live
-- StarterPlayerScripts.GianlucaClient, installed only at the gated live swap (STOP 5/6).
--
-- What stays exactly as the live script has it: the "find the Secret Chim" questline
-- (GianlucaTalk / GianlucaState remotes, data.ChimQuest stages 0-3, the hasChim gate
-- read from the data snapshot, the Chim hide-on-found and the collectible bob). What
-- changes: every line Gianluca speaks comes from NpcDialogue.Gianluca through NpcTalk
-- (data + logic, testable off-line), the box shows his real name and accent, and a
-- line tagged as a war memory nudges the body driver (NpcReaction attribute -> NpcLife).
--
-- Still one prompt connection, made once; MerchantDialog owns walk-away and respawn.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local MerchantDialog = require(ReplicatedStorage.Modules.MerchantDialog)
local NpcKit = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NpcKit")
local NpcTalk = require(NpcKit:WaitForChild("NpcTalk"))
local Dialogue = require(NpcKit:WaitForChild("NpcDialogue"):WaitForChild("Gianluca"))

local talkRemote = remotes:WaitForChild("GianlucaTalk")
local stateRemote = remotes:WaitForChild("GianlucaState")

local questState = 0
local memory = NpcTalk.NewMemory()      -- this session's relationship (met, cursors)
local gianluca = nil                    -- the character model, once found

-- Whether an UNPLACED Chim is in the inventory right now. Read from the data
-- snapshot rather than inferred from questState: a Chim can arrive by routes the
-- quest never sees (trade, test grant), and the server gates the handover on
-- possession too, so this keeps the dialogue honest about what he'll accept.
local hasChim = false
local dataRemote = remotes:WaitForChild("DataUpdated")
dataRemote.OnClientEvent:Connect(function(snapshot)
	if typeof(snapshot) ~= "table" or typeof(snapshot.Brainrots) ~= "table" then return end
	local found = false
	for _, e in ipairs(snapshot.Brainrots) do
		if e.Name == "Chim" and e.PadIndex == nil then found = true break end
	end
	hasChim = found
end)

-- the body driver's reaction hook (client-local: each player sees the beat on their own screen)
local function react(id)
	if gianluca and id then gianluca:SetAttribute("NpcReaction", id) end
end

local function showConversation(hrp)
	local r = NpcTalk.Next(Dialogue, memory, { questState = questState, hasChim = hasChim, userId = player.UserId })
	local onDone = nil
	if r.action == "start" then
		onDone = function() talkRemote:FireServer() end            -- the live server treats a bare fire as "begin the hunt"
	elseif r.action then
		onDone = function() talkRemote:FireServer(r.action) end    -- "handover"
	end
	MerchantDialog.Show(r.name, r.lines, r.accent, onDone, hrp, r.label)
	NpcTalk.Remember(memory, r)
	react(r.reaction)
end

-- talk prompt on Gianluca (the live prompt; never recreated here)
task.spawn(function()
	local gw = Workspace:WaitForChild("GameWorld")
	local gia = gw:WaitForChild("StupidGianluca", 30)
	local hrp = gia and gia:WaitForChild("HumanoidRootPart", 30)
	local prompt = hrp and hrp:WaitForChild("TalkPrompt", 30)
	if not prompt then return end
	gianluca = gia
	prompt.Triggered:Connect(function(who)
		if who ~= player then return end
		if MerchantDialog.IsOpen() then return end       -- repeat presses while the box is up do nothing
		showConversation(hrp)
	end)
end)

-- quest state + reward feedback
stateRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end
	questState = payload.State or questState
	if payload.Note == "key" then hasChim = false end
	local note = NpcTalk.Note(Dialogue, payload.Note)
	if note then
		MerchantDialog.Show(note.name, note.lines, note.accent, nil, nil, note.label)
	end
	if payload.Note == "found" then
		local chim = Workspace.GameWorld:FindFirstChild("SecretChim")
		if chim then
			chim.Transparency = 1
			for _, d in ipairs(chim:GetDescendants()) do
				if d:IsA("ProximityPrompt") then d.Enabled = false
				elseif d:IsA("ParticleEmitter") then d.Enabled = false
				elseif d:IsA("PointLight") then d.Enabled = false
				-- The chim is a 31-part creature parented UNDER the SecretChim root part,
				-- so hiding the root alone would leave its ears, whiskers and tail floating
				-- on the shore after it was taken.
				elseif d:IsA("BasePart") then d.Transparency = 1 end
			end
		end
	end
end)

-- Gentle bob + spin so the chim reads as a collectible (unchanged from the live script).
--
-- SecretChim is the creature's BODY part with the other 31 parts (ears, whiskers,
-- tail, eyes) parented under it. They are all ANCHORED and carried explicitly here
-- rather than welded: welding would hand a 32-part assembly to the physics engine
-- purely for a cosmetic bob, and this way the animation is local, exact, and cannot
-- drift or fall over. Offsets are captured once, relative to the root's rest CFrame.
task.spawn(function()
	local chim = Workspace.GameWorld:WaitForChild("SecretChim", 30)
	if not chim then return end
	local base = chim.CFrame
	local riders = {}
	for _, d in ipairs(chim:GetDescendants()) do
		if d:IsA("BasePart") then
			riders[#riders + 1] = { part = d, offset = base:ToObjectSpace(d.CFrame) }
		end
	end
	RunService.Heartbeat:Connect(function()
		if not chim.Parent or chim.Transparency >= 1 then return end
		local t = os.clock()
		local cf = CFrame.new(base.X, base.Y + math.sin(t * 2) * 0.35, base.Z)
			* CFrame.Angles(math.rad(20), t * 0.8, 0)
		chim.CFrame = cf
		for _, r in ipairs(riders) do
			r.part.CFrame = cf * r.offset
		end
	end)
end)
