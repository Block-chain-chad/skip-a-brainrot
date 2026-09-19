-- GiftClient: hold E on another player to offer them the brainrot in your hand,
-- and the little popup that asks the receiver whether they want it.
--
-- THE PROMPTS ARE BUILT LOCALLY, on purpose. ProximityPrompt.Enabled is a
-- replicated property, so a server-owned prompt is enabled for EVERYONE at once --
-- and "only show this while YOU are holding a brainrot" is a per-viewer question.
-- Each client therefore makes its own prompts on everyone else's character and
-- gates them against its own hands. A locally-made prompt still raises Triggered
-- locally, which is all this needs: the actual gift goes over a remote and the
-- server re-checks every part of it.
--
-- Nothing here can move an item. It asks; GiftService decides.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local modules = ReplicatedStorage:WaitForChild("Modules")

local T = require(modules:WaitForChild("UIKit"):WaitForChild("Tokens"))
local UI = require(modules.UIKit:WaitForChild("Builders"))
local okSound, SoundKit = pcall(function() return require(modules.SoundKit) end)
if not okSound then SoundKit = nil end

local offerRemote = remotes:WaitForChild("GiftOffer")
local promptRemote = remotes:WaitForChild("GiftPrompt")
local respondRemote = remotes:WaitForChild("GiftRespond")

---------------------------------------------------------------- held item
-- Same test the server makes, for the same reason: a Tool tagged BrainrotTool is
-- what "holding a brainrot" means anywhere in this game.
local function heldTool()
	local char = player.Character
	if not char then return nil end
	for _, t in ipairs(char:GetChildren()) do
		if t:IsA("Tool") and t:GetAttribute("BrainrotTool") then return t end
	end
	return nil
end

---------------------------------------------------------------- prompts on others
local prompts = {}   -- [Player] = ProximityPrompt

local function removePrompt(other)
	local p = prompts[other]
	if p then
		p:Destroy()
		prompts[other] = nil
	end
end

local function attachPrompt(other)
	if other == player then return end
	local char = other.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	if prompts[other] and prompts[other].Parent == root then return end
	removePrompt(other)

	local p = Instance.new("ProximityPrompt")
	p.Name = "GiftPrompt"
	p.ActionText = "Gift Brainrot"
	p.ObjectText = other.DisplayName
	-- HOLD, not tap: you walk past other players constantly, and a tap prompt on a
	-- moving target is an accidental giveaway of whatever is in your hand.
	p.HoldDuration = 0.9
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p.Enabled = false   -- turned on only while holding something, see the watcher
	p.Parent = root

	p.Triggered:Connect(function(who)
		if who ~= player then return end
		local tool = heldTool()
		if not tool then return end
		offerRemote:FireServer(other, tool:GetAttribute("Uid"))
	end)

	prompts[other] = p
end

local function watch(other)
	if other == player then return end
	attachPrompt(other)
	other.CharacterAdded:Connect(function()
		task.wait(0.5)   -- let the rig assemble before parenting to its root
		attachPrompt(other)
	end)
	other.CharacterRemoving:Connect(function() removePrompt(other) end)
end

for _, other in ipairs(Players:GetPlayers()) do watch(other) end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(removePrompt)

-- One watcher for every prompt: cheap, and it means a prompt attached late (a
-- player who joined while we were holding something) still gets the right state.
task.spawn(function()
	while true do
		task.wait(0.25)
		local holding = heldTool() ~= nil
		for other, p in pairs(prompts) do
			if p.Parent then
				p.Enabled = holding
			else
				prompts[other] = nil
			end
		end
	end
end)

---------------------------------------------------------------- receiver popup
-- Deliberately SMALL and corner-anchored rather than a modal over the middle of
-- the screen: a gift arrives unprompted, often mid-throw, and stealing the whole
-- screen for something you did not ask for is worse than the gift is good.
local gui = Instance.new("ScreenGui")
gui.Name = "GiftPromptUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 15
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

-- 380 rather than 330, and the title WRAPS rather than truncating: Roblox display
-- names run long, and at 330 "BigFrogTerryBruh wants to give you" clipped to
-- "...wants to give..." -- which loses the one piece of information that decides
-- whether you want the gift at all, namely who it is from.
local CARD_W, CARD_H = 380, 168
local card = UI.surface(gui, UDim2.fromOffset(CARD_W, CARD_H), "panel", T.radius.panel, T.stroke.panel)
card.Name = "GiftCard"
card.AnchorPoint = Vector2.new(0.5, 0)
card.Position = UDim2.new(0.5, 0, 0, 96)
card.ZIndex = 40
UI.gloss(card, T.radius.panel)
UI.hardShadow(card, T.shadowOffset.panel, T.radius.panel)

local cardScale = Instance.new("UIScale")
cardScale.Parent = card

local title = UI.label(card, "", "buttonM", T.color.white)
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.new(0.5, 0, 0, 12)
title.Size = UDim2.new(1, -24, 0, 44)
title.AutomaticSize = Enum.AutomaticSize.None
title.TextXAlignment = Enum.TextXAlignment.Center
title.TextWrapped = true
title.ZIndex = card.ZIndex + 2

local itemLabel = UI.label(card, "", "cardLabel", T.color.claimRing)
itemLabel.Name = "Item"
itemLabel.AnchorPoint = Vector2.new(0.5, 0)
itemLabel.Position = UDim2.new(0.5, 0, 0, 58)
itemLabel.Size = UDim2.new(1, -24, 0, 36)
itemLabel.AutomaticSize = Enum.AutomaticSize.None
itemLabel.TextXAlignment = Enum.TextXAlignment.Center
itemLabel.TextWrapped = true
itemLabel.ZIndex = card.ZIndex + 2

-- 2 x 166 + 3 x 14 padding fits the 380 card exactly
local BTN_W, BTN_H = 166, 44
local function btnSlot(name, anchorX, x)
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(anchorX, 1)
	f.Position = UDim2.new(anchorX, x, 1, -14)
	f.Size = UDim2.fromOffset(BTN_W, BTN_H)
	f.BackgroundTransparency = 1
	f.ZIndex = card.ZIndex + 2
	f.Parent = card
	return f
end

local noBtn = UI.button(btnSlot("NoSlot", 0, 14), "NO", "tab", UDim2.fromOffset(BTN_W, BTN_H))
noBtn.ZIndex = card.ZIndex + 3
local yesBtn = UI.button(btnSlot("YesSlot", 1, -14), "ACCEPT", "green", UDim2.fromOffset(BTN_W, BTN_H))
yesBtn.ZIndex = card.ZIndex + 3

local function hide()
	gui.Enabled = false
end

local function show(payload)
	title.Text = ("%s wants to give you"):format(tostring(payload.From))
	itemLabel.Text = payload.Mutation and (payload.Mutation .. " " .. payload.Name) or tostring(payload.Name)
	gui.Enabled = true
	cardScale.Scale = 0.88
	TweenService:Create(cardScale, T.tween.panelOpen, { Scale = 1 }):Play()
	if SoundKit then pcall(function() SoundKit.play("panelOpen", nil, { volume = 0.16 }) end) end
end

-- Answering closes the card immediately. The server owns the outcome and toasts
-- it, so there is nothing here worth waiting on -- and a card that lingers after
-- a click reads as the button not having worked.
yesBtn.Activated:Connect(function()
	hide()
	respondRemote:FireServer(true)
end)
noBtn.Activated:Connect(function()
	hide()
	respondRemote:FireServer(false)
end)

promptRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end
	if payload.Expired then
		-- the offer lapsed server-side; take the card away rather than leave a button
		-- that would answer an offer that no longer exists
		hide()
		return
	end
	show(payload)
end)
