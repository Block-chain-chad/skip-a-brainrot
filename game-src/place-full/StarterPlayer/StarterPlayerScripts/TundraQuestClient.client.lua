-- TundraQuestClient: Elder Tung's World 2 arc, front end.
--
-- This script owns the CONVERSATION only. The tracker row is QuestTrackerClient's (it
-- reads TundraState like every other questline), the toasts are ToastClient's (the server
-- sends them as ordinary PurchaseResult messages), and the drill out on the ice belongs
-- to CaveDrillClient. All three listen to the same TundraState push independently, so
-- none of them has to know the others exist.
--
-- The arc is authored in ReplicatedStorage.Modules.TundraQuestConfig. Nothing here
-- decides anything: the server sends a stage index, this file looks up what he says at
-- that index, and pressing the button just tells the server the player spoke to him.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local modules = ReplicatedStorage:WaitForChild("Modules")

local MerchantDialog = require(modules:WaitForChild("MerchantDialog"))
local Config = require(modules:WaitForChild("TundraQuestConfig"))

local talkRemote = remotes:WaitForChild("TundraTalk")
local stateRemote = remotes:WaitForChild("TundraState")

-- his own wood-brown accent, the same pair the valley questline gives him, so both
-- conversations are recognisably the same old man
local TUNG = { Color3.fromRGB(198, 150, 96), Color3.fromRGB(146, 98, 54) }
local NAME = Config.NpcName

---------------------------------------------------------------- state
local state = {
	State = 0, Step = 0, Of = 0, Met = false, Done = false,
	StageId = "None", Kind = nil, Parts = nil,
}
local anchorPart

-- What is still owed, in his words. Kept out of the dialogue table because it has to be
-- rebuilt from the live payload every time the box opens.
local function progressLine()
	local stage = Config.ByIndex[state.State]
	if not stage then return nil end
	if type(state.Parts) == "table" and #state.Parts > 0 then
		local bits = {}
		for _, p in ipairs(state.Parts) do
			bits[#bits + 1] = ("%s %d/%d"):format(p.Plural or p.Label, p.Have or 0, p.Need or 0)
		end
		return "Still short: " .. table.concat(bits, ", ") .. "."
	end
	if stage.Kind == "count" then
		return ("So far: %d of %d."):format(state.Step or 0, state.Of or 0)
	end
	return nil
end

local function push(lines, text)
	if type(text) == "string" and text ~= "" then lines[#lines + 1] = text end
end

---------------------------------------------------------------- the conversation
-- One entry point, four shapes. Which one you get is decided entirely by the stage the
-- SERVER says you are on -- this never advances anything on its own, it only asks.
local function speak()
	local lines = {}

	if state.Done then
		push(lines, Config.Finished)
		MerchantDialog.Show(NAME, lines, TUNG, nil, anchorPart, "OK \u{25B6}")
		return
	end

	if state.State == Config.NONE then
		-- The offer. Both lines matter: the greeting establishes he remembers you from
		-- the valley, the first trial is the actual ask.
		push(lines, Config.Intro)
		push(lines, Config.Stages[1].Say)
		MerchantDialog.Show(NAME, lines, TUNG, function()
			talkRemote:FireServer()
		end, anchorPart, "PROVE YOURSELF \u{25B6}")
		return
	end

	local stage = Config.ByIndex[state.State]
	if not stage then
		-- A payload from a newer server than this client. Say something rather than
		-- opening an empty box.
		MerchantDialog.Show(NAME, { Config.Intro }, TUNG, nil, anchorPart, "OK \u{25B6}")
		return
	end

	if stage.Kind == "talk" then
		-- A story beat: he is waiting for the player to turn up, and pressing the button
		-- is what makes it happen.
		push(lines, stage.Say)
		MerchantDialog.Show(NAME, lines, TUNG, function()
			talkRemote:FireServer()
		end, anchorPart, stage.Cutscene and "STAND BACK \u{25B6}" or "CONTINUE \u{25B6}")
		return
	end

	-- A grind stage that is already SATISFIED. Normally the server has advanced it
	-- before the player gets back here (a finished counter does not wait for him), but
	-- it can still be reached -- a quota lowered under a live save, or a dev jump -- and
	-- being nagged for something you have already done is the worst version of this box.
	if state.Met then
		push(lines, stage.Done)
		MerchantDialog.Show(NAME, lines, TUNG, function()
			talkRemote:FireServer()
		end, anchorPart, "CONTINUE \u{25B6}")
		return
	end

	-- A grind stage still in progress. First visit gets the briefing; later ones get the
	-- nag, because re-reading the full instructions every time you walk past is what
	-- makes an NPC feel like a menu.
	push(lines, (state.Step or 0) > 0 and (stage.Nag or stage.Say) or stage.Say)
	push(lines, progressLine())
	MerchantDialog.Show(NAME, lines, TUNG, nil, anchorPart, "OK \u{25B6}")
end

---------------------------------------------------------------- the prompt
-- STREAMING. This place has workspace.StreamingEnabled, and the hut is 8000 studs from
-- spawn: a player in the valley has the ElderTungTundra MODEL (containers replicate) and
-- none of its parts. A one-shot scan at join therefore finds nothing and gives up before
-- the player has ever been to World 2 -- which is exactly what the first version did.
--
-- So: scan once for the case where we are already there, and then WATCH. Streaming
-- destroys and recreates the instance rather than reparenting it, so every arrival is a
-- fresh prompt that has to be bound again.
--
-- Scoped to the tundra folder rather than Workspace: a DescendantAdded on Workspace fires
-- for every part that streams in anywhere in the game.
local function bindPrompt(prompt)
	local host = prompt.Parent
	if not host then return end
	anchorPart = host:IsA("BasePart") and host or host:FindFirstChildWhichIsA("BasePart")
	prompt.Triggered:Connect(function(who)
		if who == player then speak() end
	end)
end

task.spawn(function()
	local gw = Workspace:WaitForChild("GameWorld", 60)
	local ft = gw and gw:WaitForChild("FrozenTundra", 60)
	if not ft then
		warn("[TundraQuestClient] no GameWorld.FrozenTundra -- is World 2 in the place?")
		return
	end
	for _, d in ipairs(ft:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == Config.PromptName then bindPrompt(d) end
	end
	ft.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") and d.Name == Config.PromptName then bindPrompt(d) end
	end)
end)

---------------------------------------------------------------- state in
stateRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end
	for _, k in ipairs({ "State", "Step", "Of", "Met", "Done", "StageId", "Kind", "Parts", "Title", "Track" }) do
		state[k] = payload[k]
	end
	state.State = tonumber(payload.State) or 0

	-- A talk stage that just resolved rolls straight into the next line of the same
	-- conversation: he finishes the beat, then briefs the next one. Without this the box
	-- closes on "stand back" and the player has to press E again to be told why.
	local note = payload.Note
	if note == "advance" or (type(note) == "string" and note:sub(1, 9) == "cutscene:") then
		local cleared = payload.Cleared and Config.ByIndex[Config.IndexOfId[payload.Cleared]]
		local nextStage = Config.ByIndex[state.State]
		local lines = {}
		push(lines, cleared and cleared.Done)
		if payload.Done then
			push(lines, Config.Finished)
		else
			push(lines, nextStage and nextStage.Say)
		end
		if #lines > 0 then
			-- A cutscene owns the screen, so the box waits for it rather than talking
			-- over the top of the drill being built.
			local delay = (type(note) == "string" and note:sub(1, 9) == "cutscene:") and 6.5 or 0.15
			task.delay(delay, function()
				MerchantDialog.Show(NAME, lines, TUNG, nil, anchorPart, "OK \u{25B6}")
			end)
		end
	end
end)
