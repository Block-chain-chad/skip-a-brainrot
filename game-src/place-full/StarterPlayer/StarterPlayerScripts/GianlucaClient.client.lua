-- GianlucaClient: "find the Secret Chim" questline. Hold E at Gianluca to talk;
-- he sends you to find the Chim hidden in the map; taking it grants the Chim; then
-- you bring it BACK to him and he trades you a Key for it.
-- Quest stages mirror data.ChimQuest: 0 not started, 1 searching, 2 holding the Chim,
-- 3 handed over and Key claimed.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local MerchantDialog = require(ReplicatedStorage.Modules.MerchantDialog)

local talkRemote = remotes:WaitForChild("GianlucaTalk")
local stateRemote = remotes:WaitForChild("GianlucaState")
local GOLD = { Color3.fromRGB(255, 216, 96), Color3.fromRGB(238, 148, 24) }

local questState = 0

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

-- talk prompt on Gianluca
task.spawn(function()
	local gw = Workspace:WaitForChild("GameWorld")
	local gia = gw:WaitForChild("StupidGianluca", 30)
	local hrp = gia and gia:WaitForChild("HumanoidRootPart", 30)
	local prompt = hrp and hrp:WaitForChild("TalkPrompt", 30)
	if not prompt then return end
	prompt.Triggered:Connect(function(who)
		if who ~= player then return end
		if hasChim then
			-- holding it: offer the trade whatever the stage says. The server
			-- re-checks possession, so this button can only ever ask.
			MerchantDialog.Show("Gianluca", {
				"MY CHIM!! You found it!! Give it back and I give you something better \u{2014} a KEY!",
			}, GOLD, function()
				talkRemote:FireServer("handover")
			end, hrp, "HAND OVER THE CHIM \u{25B6}")
		elseif questState >= 3 then
			MerchantDialog.Show("Gianluca", { "You found my Chim AND gave it back! GRAZIE, bambino!! Use that key well." }, GOLD, nil, hrp, "OK \u{25B6}")
		elseif questState == 1 then
			MerchantDialog.Show("Gianluca", { "Have you found my Chim yet?! It's out there somewhere!" }, GOLD, nil, hrp, "KEEP LOOKING \u{25B6}")
		else
			MerchantDialog.Show("Gianluca", { "ARRRGGGGHHHH!!!!! IM SO STUPID!! I CANT FIND MY SECRET CHIM!!" }, GOLD, function()
				talkRemote:FireServer()
			end, hrp, "HELP HIM FIND IT \u{25B6}")
		end
	end)
end)

-- quest state + reward feedback
stateRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end
	questState = payload.State or questState
	if payload.Note == "key" then
		hasChim = false
		MerchantDialog.Show("Gianluca", {
			"MY CHIM!! GRAZIE, bambino!! Thank you thank you THANK YOU!!",
			"Here \u{2014} you take this KEY. Is heavy, is old, is yours now. It opens something, I forget what. \u{1F511}",
		}, GOLD, nil, nil, "TAKE THE KEY \u{25B6}")
	elseif payload.Note == "found" then
		MerchantDialog.Show("\u{2728} SECRET CHIM \u{2728}", {
			"You got the SECRET CHIM! A Mythic brainrot, and the only one of its kind. Take it back to Gianluca \u{2014} he'll trade you a KEY for it.",
		}, GOLD, nil, nil, "AWESOME! \u{25B6}")
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
	elseif payload.Note == "hint" then
		MerchantDialog.Show("\u{2728} Secret Chim", {
			"Someone must be looking for this shiny thing... maybe ask around the camp?",
		}, GOLD, nil, nil, "OK \u{25B6}")
	end
end)

-- Gentle bob + spin so the chim reads as a collectible.
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