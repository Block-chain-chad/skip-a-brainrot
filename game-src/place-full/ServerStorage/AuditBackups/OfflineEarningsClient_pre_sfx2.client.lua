-- "While you were away" popup: asks the server for any pending offline payout once ready
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local offlineRemote = remotes:WaitForChild("OfflineEarnings")
local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local P = UITheme.Palette
local CF = UITheme.Camp
local FONT = UITheme.Font
local BODY = Enum.Font.GothamMedium

-- canonical abbreviator, K through Qi -- see Modules.NumberFormat
local formatNumber = require(ReplicatedStorage.Modules.NumberFormat).Short

local function formatDuration(sec)
	local h = math.floor(sec / 3600)
	local m = math.floor((sec % 3600) / 60)
	if h > 0 then return ("%dh %dm"):format(h, m) end
	if m > 0 then return ("%dm"):format(m) end
	return ("%ds"):format(sec)
end

local gui = Instance.new("ScreenGui")
gui.Name = "OfflineEarningsUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 10
gui.Parent = player:WaitForChild("PlayerGui")

local function showPopup(payload)
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.new(0.5, 0, 0.42, 0)
	card.Size = UDim2.new(0, 400, 0, 236)
	card.BackgroundColor3 = P.white
	card.BorderSizePixel = 0
	card.ZIndex = 10
	card.Parent = gui
	UITheme.campPanel(card)

	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = card
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	-- carved-wood banner that overhangs the card top
	local ribbon, header = UITheme.ribbon(card, "WHILE YOU WERE AWAY", 0.88)
	header.TextSize = 26

	local amount = Instance.new("TextLabel")
	amount.BackgroundTransparency = 1
	amount.Size = UDim2.new(1, -32, 0, 52)
	amount.Position = UDim2.new(0, 16, 0, 52)
	amount.Font = FONT
	amount.TextSize = 42
	amount.TextColor3 = CF.cream
	amount.Text = "+$" .. formatNumber(payload.Payout)
	amount.ZIndex = 12
	amount.Parent = card
	UITheme.inkText(amount, 4)

	local detail = Instance.new("TextLabel")
	detail.BackgroundTransparency = 1
	detail.Size = UDim2.new(1, -40, 0, 44)
	detail.Position = UDim2.new(0, 20, 0, 108)
	detail.Font = BODY
	detail.TextSize = 13
	detail.TextColor3 = CF.muted
	detail.TextWrapped = true
	local txt = ("Your camp earned cash for %s."):format(formatDuration(payload.Seconds))
	if payload.Capped then
		txt ..= " (Cap reached \u{2014} upgrade Camp Keeper at Enzo's to earn longer!)"
	end
	detail.Text = txt
	detail.ZIndex = 12
	detail.Parent = card
	UITheme.inkText(detail, 1.6)

	local ok = Instance.new("TextButton")
	ok.AnchorPoint = Vector2.new(0.5, 1)
	ok.Position = UDim2.new(0.5, 0, 1, -14)
	ok.Size = UDim2.new(0, 176, 0, 46)
	ok.Text = "COLLECT!"
	ok.ZIndex = 12
	ok.Parent = card
	UITheme.campButton(ok, CF.pine1, CF.pine2)
	ok.TextSize = 19

	ok.MouseButton1Click:Connect(function()
		local tw = TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.5 })
		tw:Play()
		tw.Completed:Wait()
		card:Destroy()
	end)
end

offlineRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" or typeof(payload.Payout) ~= "number" then return end
	showPopup(payload)
end)

-- tell the server we're ready to receive the pending payout (if any)
task.wait(2)
offlineRemote:FireServer()
