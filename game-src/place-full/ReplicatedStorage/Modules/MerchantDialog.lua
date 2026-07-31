-- MerchantDialog: a small NPC dialogue box shown when you press E at a merchant,
-- right before the shop opens. Reusable across clients.
--   MerchantDialog.Show(npcName, lines, accent, onDone)
-- advances through `lines`; on the last line the button opens the shop by calling
-- onDone(). onDone is dropped if the player LEAVEs or walks away (Hide()).
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local CF = UITheme.Camp
local FONT = UITheme.Font
local BODY = Enum.Font.GothamMedium
local player = Players.LocalPlayer

local M = {}
local gui, box, namePlate, nameText, lineText, contBtn, contText
local lines, idx, onDone, anchorPart, finalLabel

local function build()
	if gui and gui.Parent then return end
	gui = Instance.new("ScreenGui")
	gui.Name = "MerchantDialogUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 12
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	box = Instance.new("Frame")
	box.Name = "DialogBox"
	box.AnchorPoint = Vector2.new(0.5, 1)
	box.Position = UDim2.new(0.5, 0, 1, -150)
	box.Size = UDim2.fromOffset(560, 132)
	box.Visible = false
	box.ZIndex = 10
	box.Parent = gui
	UITheme.campPanel(box)

	-- accent name plate (overhangs the top-left). A UIGradient on the plate does
	-- NOT tint a CHILD label, so the name text stays clean cream.
	namePlate = Instance.new("Frame")
	namePlate.AnchorPoint = Vector2.new(0, 1)
	namePlate.Position = UDim2.new(0, 20, 0, 14)
	namePlate.Size = UDim2.fromOffset(250, 34)
	namePlate.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	namePlate.BorderSizePixel = 0
	namePlate.ZIndex = 13
	namePlate.Parent = box
	UITheme.corner(namePlate, 9)
	UITheme.ink(namePlate, 3)
	nameText = Instance.new("TextLabel")
	nameText.Size = UDim2.fromScale(1, 1)
	nameText.BackgroundTransparency = 1
	nameText.Font = FONT
	nameText.TextSize = 17
	nameText.TextColor3 = CF.cream
	nameText.ZIndex = 14
	nameText.Parent = namePlate
	UITheme.inkText(nameText, 2.4)

	lineText = Instance.new("TextLabel")
	lineText.AnchorPoint = Vector2.new(0.5, 0)
	lineText.Position = UDim2.new(0.5, 0, 0, 40)
	lineText.Size = UDim2.new(1, -44, 0, 42)
	lineText.BackgroundTransparency = 1
	lineText.Font = BODY
	lineText.TextSize = 17
	lineText.TextColor3 = Color3.fromRGB(255, 255, 255)
	lineText.TextWrapped = true
	lineText.TextXAlignment = Enum.TextXAlignment.Left
	lineText.TextYAlignment = Enum.TextYAlignment.Top
	lineText.ZIndex = 13
	lineText.Parent = box
	UITheme.inkText(lineText, 1.6)

	contBtn = Instance.new("TextButton")
	contBtn.AnchorPoint = Vector2.new(1, 1)
	contBtn.Position = UDim2.new(1, -16, 1, -12)
	contBtn.Size = UDim2.fromOffset(190, 40)
	contBtn.Text = ""
	contBtn.ZIndex = 13
	contBtn.Parent = box
	UITheme.campButton(contBtn, CF.pine1, CF.pine2)
	contText = Instance.new("TextLabel")
	contText.Size = UDim2.fromScale(1, 1)
	contText.BackgroundTransparency = 1
	contText.Font = FONT
	contText.TextSize = 16
	contText.TextColor3 = CF.cream
	contText.ZIndex = 15
	contText.Parent = contBtn
	UITheme.inkText(contText, 2.2)

	local leaveBtn = Instance.new("TextButton")
	leaveBtn.AnchorPoint = Vector2.new(0, 1)
	leaveBtn.Position = UDim2.new(0, 16, 1, -12)
	leaveBtn.Size = UDim2.fromOffset(120, 40)
	leaveBtn.Text = ""
	leaveBtn.ZIndex = 13
	leaveBtn.Parent = box
	UITheme.campButton(leaveBtn, CF.panelTop, CF.panelBot)
	local leaveText = Instance.new("TextLabel")
	leaveText.Size = UDim2.fromScale(1, 1)
	leaveText.BackgroundTransparency = 1
	leaveText.Font = FONT
	leaveText.TextSize = 15
	leaveText.TextColor3 = CF.muted
	leaveText.Text = "LEAVE"
	leaveText.ZIndex = 15
	leaveText.Parent = leaveBtn
	UITheme.inkText(leaveText, 2)
	leaveBtn.Activated:Connect(function() M.Hide() end)

	-- walk away from the merchant -> dismiss the dialogue
	RunService.Heartbeat:Connect(function()
		if not (box and box.Visible and anchorPart) then return end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - anchorPart.Position).Magnitude > 24 then M.Hide() end
	end)

	contBtn.Activated:Connect(function()
		if not lines then return end
		if idx < #lines then
			idx += 1
			lineText.Text = lines[idx]
			contText.Text = (idx < #lines) and "NEXT \u{25B6}" or finalLabel
		else
			local d = onDone
			M.Hide()
			if d then d() end
		end
	end)
end

function M.Show(npcName, dlgLines, accent, done, anchor, finalTxt)
	build()
	anchorPart = anchor
	finalLabel = finalTxt or "OPEN SHOP \u{25B6}"
	lines = (type(dlgLines) == "table" and #dlgLines > 0) and dlgLines or { "..." }
	idx = 1
	onDone = done
	nameText.Text = npcName or "Merchant"
	UITheme.gradient(namePlate, (accent and accent[1]) or CF.amber1, (accent and accent[2]) or CF.amber2, 90)
	lineText.Text = lines[1]
	contText.Text = (#lines > 1) and "NEXT \u{25B6}" or finalLabel
	box.Visible = true
	local s = box:FindFirstChild("PopScale") or Instance.new("UIScale")
	s.Name = "PopScale"; s.Parent = box; s.Scale = 0.85
	TweenService:Create(s, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function M.IsOpen()
	return box ~= nil and box.Visible
end

function M.Hide()
	onDone = nil
	lines = nil
	anchorPart = nil
	if box then box.Visible = false end
end

return M