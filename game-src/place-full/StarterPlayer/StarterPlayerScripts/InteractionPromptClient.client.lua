--[[ ==========================================================================
InteractionPromptClient -- draws every walk-up prompt with UIKit.InteractionPrompt
(UI round 3, 2026-09-19).
---------------------------------------------------------------------------
The world's 42 prompts (and the ones spawned later: plot pads, market stands,
raids) all ran Roblox's stock prompt UI. This script flips each Default-style
prompt to Style.Custom ON THIS CLIENT ONLY -- Style is a replicated property,
but a client-side write never leaves the client, so the server's prompt is
untouched: HoldDuration, distances, keys, Enabled and Triggered are all still
its own. Custom simply means the engine draws nothing and fires PromptShown /
PromptHidden / the hold events for us to draw against.

WHAT IS LEFT ALONE. Prompts that are ALREADY Custom belong to whoever made them
custom (PlotFavoriteClient's FavPrompt draws its own pink pill) and are skipped;
so is anything under a player's character.

DRIVEN OFF ProximityPromptService, never per-prompt connections: it fires for
every prompt in the game including ones that stream in later, so nothing has to
be registered. A prompt destroyed while shown (a claimed stand, a hatched egg)
never fires PromptHidden -- the AncestryChanged watch on each live board covers
that. Event driven throughout; no Heartbeat.
========================================================================== ]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local InteractionPrompt = require(ReplicatedStorage.Modules:WaitForChild("UIKit"):WaitForChild("InteractionPrompt"))

-- the boards live under one ScreenGui so they stand down with the rest of the
-- HUD (MerchantDialog's staging disables every ScreenGui while an NPC talks)
local host = Instance.new("ScreenGui")
host.Name = "InteractionPrompts"
host.ResetOnSpawn = false
host.DisplayOrder = 3       -- world UI: under every HUD surface
host:SetAttribute("NoPolish", true)
host.Parent = playerGui

local TAG = "KitPrompt"     -- set on the prompts this client re-styled

local function isOurs(prompt: ProximityPrompt): boolean
	if prompt.Name == "FavPrompt" then return false end
	if player.Character and prompt:IsDescendantOf(player.Character) then return false end
	return true
end

local function adopt(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then return end
	if prompt:GetAttribute(TAG) then return end
	if prompt.Style ~= Enum.ProximityPromptStyle.Default then return end   -- someone else's custom UI
	if not isOurs(prompt) then return end
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute(TAG, true)
end

for _, d in ipairs(Workspace:GetDescendants()) do adopt(d) end
Workspace.DescendantAdded:Connect(adopt)

---------------------------------------------------------------- live boards
local live = {}   -- [prompt] = { handle, conns }

local function drop(prompt)
	local rec = live[prompt]
	if not rec then return end
	live[prompt] = nil
	for _, c in ipairs(rec.conns) do c:Disconnect() end
	rec.handle.destroy()
end

local function inputTypeNow(): Enum.ProximityPromptInputType
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then return Enum.ProximityPromptInputType.Touch end
	if last == Enum.UserInputType.Gamepad1 or last == Enum.UserInputType.Gamepad2 then return Enum.ProximityPromptInputType.Gamepad end
	return Enum.ProximityPromptInputType.Keyboard
end

-- A BillboardGui does not stand down with its ScreenGui: MerchantDialog disables
-- every HUD gui while an NPC talks and the boards kept drawing over the
-- conversation (capture 2026-09-19). Mirror the host's Enabled onto each board.
local function syncEnabled()
	for _, rec in pairs(live) do rec.handle.board.Enabled = host.Enabled end
end
host:GetPropertyChangedSignal("Enabled"):Connect(syncEnabled)

ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
	if not prompt:GetAttribute(TAG) then return end
	if live[prompt] then drop(prompt) end
	local handle = InteractionPrompt.attach(prompt, inputType or inputTypeNow(), host)
	if not handle then return end
	handle.board.Enabled = host.Enabled
	local conns = {}
	-- a prompt that goes away while shown never fires PromptHidden
	table.insert(conns, prompt.AncestryChanged:Connect(function(_, parent)
		if parent == nil or not prompt:IsDescendantOf(Workspace) then drop(prompt) end
	end))
	table.insert(conns, prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not prompt.Enabled then drop(prompt) end
	end))
	table.insert(conns, prompt:GetAttributeChangedSignal("PromptState"):Connect(function() handle.setInput(inputTypeNow()) end))
	live[prompt] = { handle = handle, conns = conns }
end)

ProximityPromptService.PromptHidden:Connect(function(prompt)
	drop(prompt)
end)

ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
	local rec = live[prompt]
	if rec then rec.handle.holdBegin() end
end)

ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
	local rec = live[prompt]
	if rec then rec.handle.holdEnd() end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player then return end
	local rec = live[prompt]
	if rec then rec.handle.success() end
end)

-- a player who picks up a controller or taps the screen mid-session gets the
-- right cap on every board that is up
UserInputService.LastInputTypeChanged:Connect(function()
	local it = inputTypeNow()
	for _, rec in pairs(live) do rec.handle.setInput(it) end
end)

print("InteractionPromptClient online (kit walk-up prompts)")
