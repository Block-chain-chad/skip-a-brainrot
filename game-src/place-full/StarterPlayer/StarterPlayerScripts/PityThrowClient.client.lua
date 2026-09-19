-- Hype banner for a PITY-BOOSTED throw: when the player's dry-streak safety net fires
-- (see ThrowHandler + PityConfig), the server sends PityThrow at throw time and this
-- flashes "<TIER> PITY THROW!" as the rock flies -- the catch that lands will be at
-- least that tier.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local pityRemote = remotes:WaitForChild("PityThrow")
local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local SoundKit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundKit"))
local PITY_VOL = 0.34   -- peer of the perfect pop; the two never co-occur

local gui = Instance.new("ScreenGui")
gui.Name = "PityThrowUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 9
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

-- upper third, so it reads as "this throw is special" without covering the skip target
local holder = Instance.new("Frame")
holder.Name = "Banner"
holder.AnchorPoint = Vector2.new(0.5, 0.5)
holder.Position = UDim2.new(0.5, 0, 0.26, 0)
holder.Size = UDim2.fromOffset(600, 66)
holder.BackgroundTransparency = 1
holder.Visible = false
holder.Parent = gui
-- keep the tier COLOUR: UIPolish forces all text white unless an ancestor opts out
holder:SetAttribute("NoPolish", true)

local scale = Instance.new("UIScale")
scale.Parent = holder

local label = Instance.new("TextLabel")
label.Size = UDim2.fromScale(1, 1)
label.BackgroundTransparency = 1
label.Font = Enum.Font.FredokaOne
label.TextScaled = true
label.Text = ""
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.Parent = holder
local cap = Instance.new("UITextSizeConstraint")
cap.MaxTextSize = 42
cap.Parent = label
UITheme.inkText(label, 3.5)   -- chunky dark outline, matching the game's text

local token = 0
pityRemote.OnClientEvent:Connect(function(tierName, tierColor)
	if typeof(tierName) ~= "string" then return end
	token += 1
	local mine = token
	label.Text = ("\u{2728} %s PITY THROW! \u{2728}"):format(string.upper(tierName))
	label.TextColor3 = (typeof(tierColor) == "Color3") and tierColor or Color3.fromRGB(255, 226, 120)
	holder.Visible = true
	-- the dry-streak safety net firing is a gift, not a warning: a reward sting,
	-- reusing the wheel's existing win voice rather than inventing an id
	SoundKit.play("wheelWin", nil, { volume = PITY_VOL })
	scale.Scale = 0.55
	TweenService:Create(scale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(2.6, function()
		if token ~= mine then return end
		local tw = TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.55 })
		tw:Play()
		tw.Completed:Wait()
		if token == mine then holder.Visible = false end
	end)
end)
