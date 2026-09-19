-- GardensQuestClient: "The Old Orders", front end -- the Keeper's conversation only.
--
-- The tracker row is QuestTrackerClient's (it reads GardensState like every other
-- questline), the toasts are ToastClient's (PurchaseResult), the other World 3 voices are
-- GardensNpcClient's, and the cutscenes belong to StoryCinematic when that module exists.
-- All of them listen to the same GardensState push independently.
--
-- Nothing here decides anything: the server sends a stage index, this file looks up what
-- the Keeper says at that index, and pressing the button tells the server the player
-- spoke to him. Structural copy of TundraQuestClient with one difference: accepting the
-- orders opens the first page straight away, so the first beat is read once, not twice.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local modules = ReplicatedStorage:WaitForChild("Modules")

local MerchantDialog = require(modules:WaitForChild("MerchantDialog"))
local Config = require(modules:WaitForChild("GardensQuestConfig"))

local talkRemote = remotes:WaitForChild("GardensTalk")
local stateRemote = remotes:WaitForChild("GardensState")

-- PLACEHOLDER display name (board P6): the role is "Keeper"; Balkan names him.
local KEEPER_NAME = "The Keeper"
local ACCENT = Config.Accent

-- Optional: the story cinematic module (Plan 5). Absent today, so every use is guarded.
local StoryCinematic = nil
do
	local m = modules:FindFirstChild("StoryCinematic")
	if m then
		local ok, mod = pcall(require, m)
		if ok and type(mod) == "table" and type(mod.Play) == "function" then StoryCinematic = mod end
	end
end

---------------------------------------------------------------- state
local state = {
	State = 0, Step = 0, Of = 0, Met = false, Done = false,
	StageId = "None", Kind = nil, Parts = nil, Caches = 0, CryptKey = false,
}
local anchorPart

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
	if stage.Kind == "flag" then
		return ("The trader's caches: %d of %d."):format(state.Caches or 0, Config.CachesForKey)
	end
	return nil
end

local function push(lines, text)
	if type(text) == "string" and text ~= "" then lines[#lines + 1] = text end
end

local function fireTalk()
	talkRemote:FireServer(Config.NpcRole)
end

---------------------------------------------------------------- the conversation
local function speak()
	local lines = {}

	if state.Done then
		push(lines, Config.Finished)
		MerchantDialog.Show(KEEPER_NAME, lines, ACCENT, nil, anchorPart, "OK \u{25B6}")
		return
	end

	if state.State == Config.NONE then
		-- The offer is the introduction alone; the first page arrives on the "accept"
		-- note below, so the player reads it once.
		push(lines, Config.Intro)
		MerchantDialog.Show(KEEPER_NAME, lines, ACCENT, fireTalk, anchorPart, "READ THE ORDERS \u{25B6}")
		return
	end

	local stage = Config.ByIndex[state.State]
	if not stage then
		MerchantDialog.Show(KEEPER_NAME, { Config.Intro }, ACCENT, nil, anchorPart, "OK \u{25B6}")
		return
	end

	if stage.Kind == "talk" then
		push(lines, stage.Say)
		MerchantDialog.Show(KEEPER_NAME, lines, ACCENT, fireTalk, anchorPart,
			stage.Cutscene and "STAND BACK \u{25B6}" or "CONTINUE \u{25B6}")
		return
	end

	if stage.Kind == "flag" then
		if state.Met then
			-- the key is in hand: a line for THAT, so Done is read once, after the press
			push(lines, stage.Ready or stage.Done)
			MerchantDialog.Show(KEEPER_NAME, lines, ACCENT, fireTalk, anchorPart, "STAND BACK \u{25B6}")
		else
			push(lines, (state.Caches or 0) > 0 and (stage.Nag or stage.Say) or stage.Say)
			push(lines, progressLine())
			MerchantDialog.Show(KEEPER_NAME, lines, ACCENT, nil, anchorPart, "OK \u{25B6}")
		end
		return
	end

	-- A grind stage already SATISFIED (a lowered quota, a dev jump): never nag for
	-- something already done.
	if state.Met then
		push(lines, stage.Done)
		MerchantDialog.Show(KEEPER_NAME, lines, ACCENT, fireTalk, anchorPart, "CONTINUE \u{25B6}")
		return
	end

	-- A grind stage in progress: the briefing on the first visit, the nag after.
	push(lines, (state.Step or 0) > 0 and (stage.Nag or stage.Say) or stage.Say)
	push(lines, progressLine())
	MerchantDialog.Show(KEEPER_NAME, lines, ACCENT, nil, anchorPart, "OK \u{25B6}")
end

---------------------------------------------------------------- the prompt
-- STREAMING: the Keep is 16,000 studs from spawn, so the prompt is created, destroyed
-- and created again as the player comes and goes. Scan once, then watch the folder.
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
	local lg = gw and gw:WaitForChild("LushGardens", 60)
	if not lg then
		warn("[GardensQuestClient] no GameWorld.LushGardens -- is World 3 in the place?")
		return
	end
	for _, d in ipairs(lg:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == Config.PromptName then bindPrompt(d) end
	end
	lg.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") and d.Name == Config.PromptName then bindPrompt(d) end
	end)
end)

---------------------------------------------------------------- state in
stateRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end
	for _, k in ipairs({ "State", "Step", "Of", "Met", "Done", "StageId", "Kind", "Parts", "Title", "Track", "Caches", "CryptKey" }) do
		state[k] = payload[k]
	end
	state.State = tonumber(payload.State) or 0

	local note = payload.Note
	local isCut = type(note) == "string" and note:sub(1, 9) == "cutscene:"

	if note == "accept" then
		-- The orders were accepted: read the first page now, in the same breath.
		local first = Config.ByIndex[1]
		if first then
			task.delay(0.15, function()
				MerchantDialog.Show(KEEPER_NAME, { first.Say }, ACCENT, fireTalk, anchorPart, "CONTINUE \u{25B6}")
			end)
		end
		return
	end

	if note == "advance" or isCut then
		local cleared = payload.Cleared and Config.ByIndex[Config.IndexOfId[payload.Cleared]]
		local nextStage = Config.ByIndex[state.State]
		local lines = {}
		push(lines, cleared and cleared.Done)
		if payload.Done then
			push(lines, Config.Finished)
		else
			push(lines, nextStage and nextStage.Say)
		end
		-- A cutscene owns the screen: play it if the module exists, and wait for it
		-- either way before the Keeper speaks again.
		local wait = 0.15
		if isCut then
			wait = Config.CutsceneWait
			if StoryCinematic then
				local ok, seconds = pcall(StoryCinematic.Play, note:sub(10))
				if ok and type(seconds) == "number" then wait = seconds + 0.5 end
			end
		end
		if #lines > 0 then
			task.delay(wait, function()
				MerchantDialog.Show(KEEPER_NAME, lines, ACCENT, nil, anchorPart, "OK \u{25B6}")
			end)
		end
	end
end)
