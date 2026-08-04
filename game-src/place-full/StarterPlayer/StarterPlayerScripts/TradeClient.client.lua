-- TradeClient (Trading Center section) — side-by-side trade window in the
-- game's chunky UIKit skin, structured after the user's reference video:
-- player header chips, YOUR OFFER / THEIR OFFER slot grids with a "+" tile
-- opening an OFFER ITEMS picker, cash row, status line, DECLINE/ACCEPT,
-- a big centre 3-2-1 countdown that never covers the offers, and a
-- TRADE SUCCESSFUL popup listing exactly what you received.
-- Server contract unchanged: TradeRequest / TradeRespond / TradeAction /
-- TradeState {Incoming,Sent,Active,Countdown,Completed,Closed,Error}.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local BrainrotConfig = require(Modules:WaitForChild("BrainrotConfig"))
local RarityConfig = require(Modules:WaitForChild("RarityConfig"))
local UIKit = Modules:WaitForChild("UIKit")
local T = require(UIKit:WaitForChild("Tokens"))
local UI = require(UIKit:WaitForChild("Builders"))
local Thumb = require(Modules:WaitForChild("BrainrotThumb"))
local formatNumber = require(Modules:WaitForChild("NumberFormat")).Short

local infoByName = {}
for _, e in ipairs(BrainrotConfig) do infoByName[e.Name] = e end
local tierByName, tierOrder = {}, {}
for i, t in ipairs(RarityConfig) do tierByName[t.Name] = t; tierOrder[t.Name] = i end

local SUFFIX = { k = 1e3, m = 1e6, b = 1e9, t = 1e12 }
local function parseAmount(text)
	text = string.gsub(string.lower(text or ""), "[%s,$]", "")
	local num, suffix = string.match(text, "^(%d+%.?%d*)(%a?)$")
	if not num then return nil end
	local mult = suffix == "" and 1 or SUFFIX[suffix]
	if not mult then return nil end
	return math.floor(tonumber(num) * mult)
end

-- ===== data mirror =====
local myCash = 0
local myCounts = {}
local currentTrade = nil
local refreshTradeUI, refreshPicker

local function applySnapshot(snapshot)
	if not snapshot then return end
	myCash = snapshot.Cash or myCash
	myCounts = {}
	for _, e in ipairs(snapshot.Brainrots or {}) do
		myCounts[e.Name] = (myCounts[e.Name] or 0) + 1
	end
	if refreshTradeUI then refreshTradeUI() end
	if refreshPicker then refreshPicker() end
end
remotes.DataUpdated.OnClientEvent:Connect(applySnapshot)
remotes.CashTick.OnClientEvent:Connect(function(c) myCash = c end)
task.spawn(function() applySnapshot(remotes.GetInitialData:InvokeServer()) end)

-- ===== canvas =====
local gui = Instance.new("ScreenGui")
gui.Name = "TradeUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 8
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local scrim = Instance.new("Frame")
scrim.Name = "Scrim"
scrim.Size = UDim2.fromScale(1, 1)
scrim.BackgroundColor3 = T.scrim
scrim.BackgroundTransparency = T.scrimAlpha
scrim.BorderSizePixel = 0
scrim.Visible = false
scrim.ZIndex = 1
scrim.Parent = gui

local root = Instance.new("Frame")
root.Name = "Canvas"
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.5)
root.Size = UDim2.fromOffset(T.size.canvas.X, T.size.canvas.Y)
root.BackgroundTransparency = 1
root.ZIndex = 2
root.Parent = gui
local canvasScale = Instance.new("UIScale")
canvasScale.Parent = root
local function fit()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize
	canvasScale.Scale = math.min(vp.X / T.size.canvas.X, vp.Y / T.size.canvas.Y)
end
fit()
do
	local cam = workspace.CurrentCamera
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(fit) end
end
task.delay(1, fit)

-- ===== toast =====
local toastFrame = UI.surface(root, UDim2.fromOffset(460, 54), "row", T.radius.control, T.stroke.control)
toastFrame.AnchorPoint = Vector2.new(0.5, 0)
toastFrame.Position = UDim2.new(0.5, 0, 0, 84)
toastFrame.Visible = false
toastFrame.ZIndex = 45
local toastLabel = UI.label(toastFrame, "", "buttonM")
toastLabel.Size = UDim2.fromScale(1, 1)
toastLabel.AutomaticSize = Enum.AutomaticSize.None
toastLabel.TextXAlignment = Enum.TextXAlignment.Center
toastLabel.TextScaled = true
toastLabel.ZIndex = 46
do
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = T.text.buttonM[1]
	c.Parent = toastLabel
end
local toastToken = 0
local function showToast(msg)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = msg
	toastFrame.Visible = true
	task.delay(3.2, function() if token == toastToken then toastFrame.Visible = false end end)
end

-- shells: visibility handles that keep UI.panel's sibling hard shadow contained
local function makeShell(name, w, h, z)
	local shell = Instance.new("Frame")
	shell.Name = name
	shell.AnchorPoint = Vector2.new(0.5, 0.5)
	shell.Position = UDim2.fromScale(0.5, 0.5)
	shell.Size = UDim2.fromOffset(w, h)
	shell.BackgroundTransparency = 1
	shell.Visible = false
	shell.ZIndex = z or 10
	shell.Parent = root
	local p = UI.panel(shell, UDim2.fromOffset(w, h))
	p.Name = "Surface"
	return shell, p
end

local function refreshScrim()
	local any = false
	for _, f in ipairs(root:GetChildren()) do
		if f:GetAttribute("Modal") and f.Visible then any = true end
	end
	scrim.Visible = any
end

local function addArt(parent, name, size, position)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = size
	holder.Position = position or UDim2.fromOffset(0, 0)
	holder.ZIndex = (parent.ZIndex or 1) + 1
	holder.Parent = parent
	if not Thumb.add(holder, name, { size = UDim2.fromScale(1, 1) }) then
		local info = infoByName[name]
		local tier = info and tierByName[info.Rarity]
		local sw = Instance.new("Frame")
		sw.Size = UDim2.fromScale(0.62, 0.62)
		sw.AnchorPoint = Vector2.new(0.5, 0.5)
		sw.Position = UDim2.fromScale(0.5, 0.5)
		sw.BackgroundColor3 = tier and tier.Color or T.color.white
		sw.ZIndex = holder.ZIndex
		sw.Parent = holder
		UI.corner(sw, T.radius.art)
		UI.stroke(sw, T.stroke.hairline)
	end
	return holder
end

local function tierStroke(card, name)
	local info = infoByName[name]
	local tier = info and tierByName[info.Rarity]
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundTransparency = 1
	f.ZIndex = (card.ZIndex or 1) + 2
	f.Parent = card
	UI.corner(f, T.radius.slot)
	local s = Instance.new("UIStroke")
	s.Thickness = 3
	s.Color = tier and tier.Color or T.color.rarityCommon
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = f
end

-- ===== incoming request popup =====
local reqShell, reqPanel = makeShell("RequestPanel", 520, 200, 15)
reqShell:SetAttribute("Modal", true)
local reqLabel = UI.label(reqPanel, "", "buttonM")
reqLabel.Position = UDim2.fromOffset(4, 8)
reqLabel.AutomaticSize = Enum.AutomaticSize.None
reqLabel.Size = UDim2.fromOffset(480, 56)
reqLabel.TextWrapped = true
local reqAccept = UI.button(reqPanel, "ACCEPT", "green", UDim2.fromOffset(220, 56), "buttonL")
reqAccept.Position = UDim2.fromOffset(4, 96)
local reqDecline = UI.button(reqPanel, "DECLINE", "red", UDim2.fromOffset(220, 56), "buttonL")
reqDecline.Position = UDim2.fromOffset(252, 96)
local requestToken = 0
local incomingFromUserId = nil
reqAccept.MouseButton1Click:Connect(function()
	reqShell.Visible = false; refreshScrim()
	remotes.TradeRespond:FireServer(true, incomingFromUserId)
end)
reqDecline.MouseButton1Click:Connect(function()
	reqShell.Visible = false; refreshScrim()
	remotes.TradeRespond:FireServer(false, incomingFromUserId)
end)

-- ===== nearby players panel (right edge, not modal) =====
local nearShell, nearPanel = makeShell("NearbyPanel", 280, 330, 8)
nearShell.AnchorPoint = Vector2.new(1, 0.5)
nearShell.Position = UDim2.new(1, -10, 0.5, 0)
local nearTitle = UI.label(nearPanel, "TRADING", "buttonL")
nearTitle.Position = UDim2.fromOffset(2, 0)
local nearHint = UI.label(nearPanel, "", "meta", T.color.textMuted)
nearHint.Position = UDim2.fromOffset(2, 44)
nearHint.AutomaticSize = Enum.AutomaticSize.None
nearHint.Size = UDim2.fromOffset(244, 30)
nearHint.TextWrapped = true
local nearList = Instance.new("ScrollingFrame")
nearList.BackgroundTransparency = 1
nearList.BorderSizePixel = 0
nearList.Position = UDim2.fromOffset(0, 80)
nearList.Size = UDim2.new(1, 0, 1, -84)
nearList.ScrollBarThickness = 6
nearList.ScrollBarImageColor3 = T.color.scrollThumb
nearList.AutomaticCanvasSize = Enum.AutomaticSize.Y
nearList.CanvasSize = UDim2.new(0, 0, 0, 0)
nearList.Parent = nearPanel
do
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, 10)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = nearList
end

-- ===== trade window =====
local W, H = 1080, 640
local tradeShell, tradePanel = makeShell("TradePanel", W, H, 10)
tradeShell:SetAttribute("Modal", true)
local INNER = W - 2 * T.pad.panel
local tradeTitle = UI.label(tradePanel, "TRADING", "panelTitle")
tradeTitle.Position = UDim2.fromOffset(4, -4)
local tradeClose = UI.button(tradePanel, "X", "red", UDim2.fromOffset(T.size.closeButton.X, T.size.closeButton.Y), "buttonL")
tradeClose.Position = UDim2.fromOffset(INNER - T.size.closeButton.X, -4)

local SIDE_W = 500
local function playerChip(x)
	local chip = UI.surface(tradePanel, UDim2.fromOffset(SIDE_W, 56), "row", T.radius.inner, T.stroke.hairline)
	chip.Position = UDim2.fromOffset(x, 66)
	local med = UI.surface(chip, UDim2.fromOffset(42, 42), "slot", T.radius.small, T.stroke.hairline)
	med.Position = UDim2.fromOffset(7, 7)
	local letter = UI.label(med, "?", "cardLabel")
	letter.Size = UDim2.fromScale(1, 1)
	letter.AutomaticSize = Enum.AutomaticSize.None
	letter.TextXAlignment = Enum.TextXAlignment.Center
	letter.ZIndex = med.ZIndex + 1
	local nameL = UI.label(chip, "?", "cardLabel")
	nameL.Position = UDim2.fromOffset(60, 4)
	local atL = UI.label(chip, "", "meta", T.color.textMuted)
	atL.Position = UDim2.fromOffset(60, 30)
	local cnt = UI.label(chip, "0/12", "value", T.color.textAccent)
	cnt.AnchorPoint = Vector2.new(1, 0.5)
	cnt.Position = UDim2.new(1, -14, 0.5, 0)
	return { chip = chip, letter = letter, nameL = nameL, atL = atL, cnt = cnt }
end
local youChip = playerChip(0)
local themChip = playerChip(INNER - SIDE_W)

local SLOTS = 12
local function offerGrid(x, headerText)
	local head = UI.label(tradePanel, headerText, "cardLabel", T.color.textMuted)
	head.Position = UDim2.fromOffset(x + 4, 130)
	local body = UI.surface(tradePanel, UDim2.fromOffset(SIDE_W, 268), "subPanel", T.radius.inner, T.stroke.control)
	body.Position = UDim2.fromOffset(x, 158)
	local slots = {}
	for i = 1, SLOTS do
		local col = (i - 1) % 4
		local row = math.floor((i - 1) / 4)
		local s = UI.surface(body, UDim2.fromOffset(112, 76), "slot", T.radius.slot, T.stroke.hairline)
		s.Position = UDim2.fromOffset(12 + col * 120, 12 + row * 84)
		s.ZIndex = body.ZIndex + 1
		slots[i] = s
	end
	return { head = head, body = body, slots = slots }
end
local yourGrid = offerGrid(0, "YOUR OFFER")
local theirGrid = offerGrid(INNER - SIDE_W, "THEIR OFFER")

-- big centre countdown: sits in the gap BETWEEN the grids, hides nothing
local countLabel = UI.label(tradePanel, "", "panelTitle", T.color.textAccent)
countLabel.AnchorPoint = Vector2.new(0.5, 0.5)
countLabel.Position = UDim2.new(0.5, 0, 0, 280)
countLabel.TextSize = 96
countLabel.Visible = false
countLabel.ZIndex = 12

-- cash row
local cashShellF = UI.surface(tradePanel, UDim2.fromOffset(220, 48), "track", T.radius.inner, T.stroke.hairline)
cashShellF.Position = UDim2.fromOffset(0, 438)
local cashBox = Instance.new("TextBox")
cashBox.BackgroundTransparency = 1
cashBox.Size = UDim2.new(1, -20, 1, 0)
cashBox.Position = UDim2.fromOffset(10, 0)
cashBox.Text = ""
cashBox.PlaceholderText = "cash  (e.g. 10k)"
cashBox.PlaceholderColor3 = T.color.textMuted
cashBox.TextColor3 = T.color.textAccent
cashBox.FontFace = T.font.ui
cashBox.TextSize = 18
cashBox.TextXAlignment = Enum.TextXAlignment.Left
cashBox.ClearTextOnFocus = false
cashBox.ZIndex = cashShellF.ZIndex + 1
cashBox.Parent = cashShellF
local setCashBtn = UI.button(tradePanel, "SET CASH", "gold", UDim2.fromOffset(150, 48), "buttonM")
setCashBtn.Position = UDim2.fromOffset(232, 438)
local yourCashL = UI.label(tradePanel, "", "value", T.color.textAccent)
yourCashL.Position = UDim2.fromOffset(398, 448)
local theirCashL = UI.label(tradePanel, "", "value", T.color.textAccent)
theirCashL.AnchorPoint = Vector2.new(1, 0)
theirCashL.Position = UDim2.fromOffset(INNER, 448)

-- status + footer
local statusL = UI.label(tradePanel, "", "buttonM")
statusL.AnchorPoint = Vector2.new(0.5, 0)
statusL.Position = UDim2.new(0.5, 0, 0, 500)
statusL.AutomaticSize = Enum.AutomaticSize.None
statusL.Size = UDim2.fromOffset(700, 30)
statusL.TextXAlignment = Enum.TextXAlignment.Center
local warnL = UI.label(tradePanel, "Be wary of scams! Never trade outside this window.", "meta", T.color.textMuted)
warnL.Position = UDim2.fromOffset(0, 560)
warnL.AutomaticSize = Enum.AutomaticSize.None
warnL.Size = UDim2.fromOffset(300, 40)
warnL.TextWrapped = true
local declineBtn = UI.button(tradePanel, "DECLINE", "red", UDim2.fromOffset(240, 56), "buttonL")
declineBtn.Position = UDim2.fromOffset(320, 544)
local acceptBtn = UI.button(tradePanel, "ACCEPT", "green", UDim2.fromOffset(240, 56), "buttonL")
acceptBtn.Position = UDim2.fromOffset(588, 544)
local acceptLabel = acceptBtn:FindFirstChildOfClass("TextLabel")

-- ===== OFFER ITEMS picker overlay =====
local pickShell, pickPanel = makeShell("PickerPanel", 760, 560, 20)
pickShell:SetAttribute("Modal", true)
local pickTitle = UI.label(pickPanel, "OFFER ITEMS", "panelTitle")
pickTitle.Position = UDim2.fromOffset(4, -4)
local pickClose = UI.button(pickPanel, "X", "red", UDim2.fromOffset(T.size.closeButton.X, T.size.closeButton.Y), "buttonL")
pickClose.Position = UDim2.fromOffset(760 - 2 * T.pad.panel - T.size.closeButton.X, -4)
local pickSearchShell = UI.surface(pickPanel, UDim2.fromOffset(280, 48), "track", T.radius.inner, T.stroke.hairline)
pickSearchShell.Position = UDim2.fromOffset(0, 70)
local pickSearchBox = Instance.new("TextBox")
pickSearchBox.BackgroundTransparency = 1
pickSearchBox.Size = UDim2.new(1, -20, 1, 0)
pickSearchBox.Position = UDim2.fromOffset(10, 0)
pickSearchBox.Text = ""
pickSearchBox.PlaceholderText = "Search here..."
pickSearchBox.PlaceholderColor3 = T.color.textMuted
pickSearchBox.TextColor3 = T.color.white
pickSearchBox.FontFace = T.font.ui
pickSearchBox.TextSize = 18
pickSearchBox.TextXAlignment = Enum.TextXAlignment.Left
pickSearchBox.ClearTextOnFocus = false
pickSearchBox.ZIndex = pickSearchShell.ZIndex + 1
pickSearchBox.Parent = pickSearchShell
local pickSortBtn = UI.button(pickPanel, "NAME", "gold", UDim2.fromOffset(150, 48), "buttonM")
pickSortBtn.Position = UDim2.fromOffset(292, 70)
local pickBody = UI.surface(pickPanel, UDim2.fromOffset(728, 380), "subPanel", T.radius.inner, T.stroke.control)
pickBody.Position = UDim2.fromOffset(0, 132)
local pickGrid = Instance.new("ScrollingFrame")
pickGrid.BackgroundTransparency = 1
pickGrid.BorderSizePixel = 0
pickGrid.Position = UDim2.fromOffset(12, 12)
pickGrid.Size = UDim2.new(1, -24, 1, -24)
pickGrid.ScrollBarThickness = 6
pickGrid.ScrollBarImageColor3 = T.color.scrollThumb
pickGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y
pickGrid.CanvasSize = UDim2.new(0, 0, 0, 0)
pickGrid.ZIndex = pickBody.ZIndex + 1
pickGrid.Parent = pickBody
do
	local g = Instance.new("UIGridLayout")
	g.CellSize = UDim2.fromOffset(128, 150)
	g.CellPadding = UDim2.fromOffset(T.pad.gridGap, T.pad.gridGap)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.Parent = pickGrid
end
local pickEmpty = UI.label(pickBody, "No items found", "buttonM", T.color.textMuted)
pickEmpty.AnchorPoint = Vector2.new(0.5, 0.5)
pickEmpty.Position = UDim2.fromScale(0.5, 0.5)
pickEmpty.Visible = false
pickEmpty.ZIndex = pickBody.ZIndex + 1
local pickSearch, pickSort = "", "NAME"

-- ===== TRADE SUCCESSFUL popup =====
local doneShell, donePanel = makeShell("DonePanel", 660, 430, 30)
doneShell:SetAttribute("Modal", true)
local doneTitle = UI.label(donePanel, "TRADE SUCCESSFUL", "panelTitle", T.color.textAccent)
doneTitle.AnchorPoint = Vector2.new(0.5, 0)
doneTitle.Position = UDim2.new(0.5, 0, 0, 0)
local doneSub = UI.label(donePanel, "", "buttonM")
doneSub.AnchorPoint = Vector2.new(0.5, 0)
doneSub.Position = UDim2.new(0.5, 0, 0, 64)
local doneRow = Instance.new("Frame")
doneRow.BackgroundTransparency = 1
doneRow.AnchorPoint = Vector2.new(0.5, 0)
doneRow.Position = UDim2.new(0.5, 0, 0, 106)
doneRow.Size = UDim2.fromOffset(600, 150)
doneRow.Parent = donePanel
do
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.Padding = UDim.new(0, 10)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = l.Parent or doneRow
	l.Parent = doneRow
end
local doneCash = UI.label(donePanel, "", "value", T.color.textAccent)
doneCash.AnchorPoint = Vector2.new(0.5, 0)
doneCash.Position = UDim2.new(0.5, 0, 0, 268)
local doneClose = UI.button(donePanel, "CLOSE", "green", UDim2.fromOffset(260, 60), "buttonL")
doneClose.AnchorPoint = Vector2.new(0.5, 0)
doneClose.Position = UDim2.new(0.5, 0, 0, 324)
doneClose.MouseButton1Click:Connect(function()
	doneShell.Visible = false; refreshScrim()
end)
local function showTradeSuccess(received)
	for _, c in ipairs(doneRow:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	local names, total = {}, 0
	for name, count in pairs(received.Items or {}) do
		table.insert(names, name); total += count
	end
	table.sort(names, function(a, b)
		local ia, ib = infoByName[a], infoByName[b]
		local ra = ia and tierOrder[ia.Rarity] or 0
		local rb = ib and tierOrder[ib.Rarity] or 0
		return ra > rb
	end)
	doneSub.Text = total == 0 and "You received:" or ("You received %d item%s:"):format(total, total == 1 and "" or "s")
	local shown = 0
	for _, name in ipairs(names) do
		if shown >= 4 then
			local more = UI.label(doneRow, ("+%d more"):format(#names - 4), "cardLabel", T.color.textMuted)
			more.AutomaticSize = Enum.AutomaticSize.XY
			break
		end
		shown += 1
		local card = UI.surface(doneRow, UDim2.fromOffset(130, 150), "slot", T.radius.slot, T.stroke.hairline)
		card.ZIndex = donePanel.ZIndex + 1
		tierStroke(card, name)
		addArt(card, name, UDim2.fromOffset(96, 86), UDim2.fromOffset(17, 8))
		local nm = UI.label(card, name, "chip")
		nm.AnchorPoint = Vector2.new(0.5, 0)
		nm.Position = UDim2.new(0.5, 0, 0, 98)
		nm.AutomaticSize = Enum.AutomaticSize.None
		nm.Size = UDim2.new(1, -8, 0, 18)
		nm.TextXAlignment = Enum.TextXAlignment.Center
		nm.TextTruncate = Enum.TextTruncate.AtEnd
		nm.ZIndex = card.ZIndex + 1
		local ct = UI.label(card, "x" .. (received.Items[name] or 1), "cardLabel", T.color.textAccent)
		ct.AnchorPoint = Vector2.new(0.5, 0)
		ct.Position = UDim2.new(0.5, 0, 0, 118)
		ct.ZIndex = card.ZIndex + 1
	end
	if total == 0 and (received.Cash or 0) == 0 then
		doneSub.Text = "Trade complete!"
	end
	doneCash.Text = (received.Cash or 0) > 0 and ("+ $" .. formatNumber(received.Cash) .. " cash") or ""
	doneShell.Visible = true
	refreshScrim()
end

-- ===== rendering =====
local function fillSlot(slot, name, count, clickable)
	for _, c in ipairs(slot:GetChildren()) do
		-- clear EVERYTHING gui (labels included) or names from the previous render bleed through
		if c:IsA("GuiObject") then c:Destroy() end
	end
	if name == "+" then
		local b = Instance.new("TextButton")
		b.BackgroundTransparency = 1
		b.Size = UDim2.fromScale(1, 1)
		b.Text = ""
		b.ZIndex = slot.ZIndex + 1
		b.Parent = slot
		local plus = UI.label(b, "+", "panelTitle", T.color.textMuted)
		plus.AnchorPoint = Vector2.new(0.5, 0.5)
		plus.Position = UDim2.fromScale(0.5, 0.5)
		plus.ZIndex = b.ZIndex + 1
		return b
	elseif name then
		tierStroke(slot, name)
		addArt(slot, name, UDim2.fromOffset(64, 56), UDim2.fromOffset(24, 4))
		local nm = UI.label(slot, name, "chip")
		nm.AnchorPoint = Vector2.new(0.5, 0)
		nm.Position = UDim2.new(0.5, 0, 0, 58)
		nm.AutomaticSize = Enum.AutomaticSize.None
		nm.Size = UDim2.new(1, -6, 0, 14)
		nm.TextXAlignment = Enum.TextXAlignment.Center
		nm.TextTruncate = Enum.TextTruncate.AtEnd
		nm.ZIndex = slot.ZIndex + 1
		if count > 1 then
			local badge = UI.label(slot, "x" .. count, "chip", T.color.textAccent)
			badge.Position = UDim2.fromOffset(6, 2)
			badge.ZIndex = slot.ZIndex + 3
		end
		if clickable then
			local b = Instance.new("TextButton")
			b.BackgroundTransparency = 1
			b.Size = UDim2.fromScale(1, 1)
			b.Text = ""
			b.ZIndex = slot.ZIndex + 4
			b.Parent = slot
			return b
		end
	end
	return nil
end

local function renderSide(grid, side, mine)
	local names = {}
	for name in pairs(side.Items or {}) do table.insert(names, name) end
	table.sort(names)
	local slotIdx = 0
	for _, name in ipairs(names) do
		slotIdx += 1
		if slotIdx > SLOTS then break end
		local btn = fillSlot(grid.slots[slotIdx], name, side.Items[name], mine)
		if btn then
			btn.MouseButton1Click:Connect(function()
				remotes.TradeAction:FireServer({ Type = "RemoveItem", Name = name })
			end)
		end
	end
	if mine and slotIdx < SLOTS then
		slotIdx += 1
		local btn = fillSlot(grid.slots[slotIdx], "+", 0, true)
		if btn then
			btn.MouseButton1Click:Connect(function()
				refreshPicker()
				pickShell.Visible = true
				refreshScrim()
			end)
		end
	end
	for i = slotIdx + 1, SLOTS do
		fillSlot(grid.slots[i], nil, 0, false)
	end
	return #names
end

refreshTradeUI = function()
	if not currentTrade or not tradeShell.Visible then return end
	local st = currentTrade
	local other = st.OtherName or "?"
	tradeTitle.Text = "TRADING"
	youChip.nameL.Text = string.upper(player.DisplayName)
	youChip.atL.Text = "@" .. player.Name
	youChip.letter.Text = string.upper(string.sub(player.DisplayName, 1, 1))
	themChip.nameL.Text = string.upper(other)
	themChip.atL.Text = "@" .. other
	themChip.letter.Text = string.upper(string.sub(other, 1, 1))
	local yn = renderSide(yourGrid, st.You, true)
	local tn = renderSide(theirGrid, st.Them, false)
	youChip.cnt.Text = yn .. "/" .. SLOTS
	themChip.cnt.Text = tn .. "/" .. SLOTS
	yourGrid.head.Text = st.You.Confirmed and "YOUR OFFER  - ACCEPTED" or "YOUR OFFER"
	theirGrid.head.Text = st.Them.Confirmed and "THEIR OFFER  - ACCEPTED" or "THEIR OFFER"
	yourCashL.Text = (st.You.Cash or 0) > 0 and ("+ $" .. formatNumber(st.You.Cash)) or ""
	theirCashL.Text = (st.Them.Cash or 0) > 0 and ("+ $" .. formatNumber(st.Them.Cash)) or ""
	acceptLabel.Text = st.You.Confirmed and "UNACCEPT" or "ACCEPT"
	if st.Phase == "Active" then
		countLabel.Visible = false
		if st.You.Confirmed and not st.Them.Confirmed then
			statusL.Text = "Waiting for " .. other .. " to accept..."
		elseif st.Them.Confirmed and not st.You.Confirmed then
			statusL.Text = "PLAYER ACCEPTED, AWAITING YOUR DECISION..."
		else
			statusL.Text = "Add items or cash, then press ACCEPT."
		end
	end
end

refreshPicker = function()
	if not pickShell.Visible or not currentTrade then return end
	for _, c in ipairs(pickGrid:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	local offered = currentTrade.You.Items or {}
	local list = {}
	for name, count in pairs(myCounts) do
		local avail = count - (offered[name] or 0)
		if avail > 0 and (pickSearch == "" or string.find(string.lower(name), pickSearch, 1, true)) then
			table.insert(list, { name = name, count = avail })
		end
	end
	if pickSort == "NAME" then
		table.sort(list, function(a, b) return a.name < b.name end)
	elseif pickSort == "RARITY" then
		table.sort(list, function(a, b)
			local ra = infoByName[a.name] and tierOrder[infoByName[a.name].Rarity] or 0
			local rb = infoByName[b.name] and tierOrder[infoByName[b.name].Rarity] or 0
			if ra ~= rb then return ra > rb end
			return a.name < b.name
		end)
	else
		table.sort(list, function(a, b)
			local ca = infoByName[a.name] and infoByName[a.name].CashPerSecond or 0
			local cb = infoByName[b.name] and infoByName[b.name].CashPerSecond or 0
			if ca ~= cb then return ca > cb end
			return a.name < b.name
		end)
	end
	pickEmpty.Visible = #list == 0
	for order, item in ipairs(list) do
		local cell = Instance.new("Frame")
		cell.Name = "Cell"
		cell.BackgroundTransparency = 1
		cell.Size = UDim2.fromOffset(128, 150)
		cell.LayoutOrder = order
		cell.ZIndex = pickGrid.ZIndex + 1
		cell.Parent = pickGrid
		local card = UI.button(cell, "", "tab", UDim2.fromOffset(128, 150), "chip")
		card.ZIndex = cell.ZIndex
		tierStroke(card, item.name)
		addArt(card, item.name, UDim2.fromOffset(92, 78), UDim2.fromOffset(18, 6))
		local nm = UI.label(card, item.name, "chip")
		nm.AnchorPoint = Vector2.new(0.5, 0)
		nm.Position = UDim2.new(0.5, 0, 0, 90)
		nm.AutomaticSize = Enum.AutomaticSize.None
		nm.Size = UDim2.new(1, -8, 0, 16)
		nm.TextXAlignment = Enum.TextXAlignment.Center
		nm.TextTruncate = Enum.TextTruncate.AtEnd
		nm.ZIndex = card.ZIndex + 1
		local ct = UI.label(card, "x" .. item.count, "cardLabel", T.color.textAccent)
		ct.AnchorPoint = Vector2.new(0.5, 0)
		ct.Position = UDim2.new(0.5, 0, 0, 112)
		ct.ZIndex = card.ZIndex + 1
		card.MouseButton1Click:Connect(function()
			remotes.TradeAction:FireServer({ Type = "AddItem", Name = item.name })
		end)
	end
end
pickSearchBox:GetPropertyChangedSignal("Text"):Connect(function()
	pickSearch = string.lower(pickSearchBox.Text)
	refreshPicker()
end)
local PICK_SORTS = { "NAME", "RARITY", "VALUE" }
pickSortBtn.MouseButton1Click:Connect(function()
	local i = table.find(PICK_SORTS, pickSort) or 1
	pickSort = PICK_SORTS[i % #PICK_SORTS + 1]
	pickSortBtn:FindFirstChildOfClass("TextLabel").Text = pickSort
	refreshPicker()
end)
pickClose.MouseButton1Click:Connect(function()
	pickShell.Visible = false
	refreshScrim()
end)

-- ===== countdown (server Countdown phase, 3-2-1 in the centre gap) =====
local countdownToken = 0
local function runCountdown(seconds)
	countdownToken += 1
	local token = countdownToken
	task.spawn(function()
		for remaining = seconds, 1, -1 do
			if token ~= countdownToken or not tradeShell.Visible then
				countLabel.Visible = false
				return
			end
			countLabel.Text = tostring(remaining)
			countLabel.Visible = true
			statusL.Text = "Both accepted - trading in " .. remaining .. "...  (DECLINE to stop)"
			task.wait(1)
		end
		if token == countdownToken then countLabel.Visible = false end
	end)
end

local function closeTradeWindow()
	countdownToken += 1
	countLabel.Visible = false
	currentTrade = nil
	tradeShell.Visible = false
	pickShell.Visible = false
	cashBox.Text = ""
	refreshScrim()
end

-- ===== server state =====
remotes.TradeState.OnClientEvent:Connect(function(st)
	if typeof(st) ~= "table" or typeof(st.Phase) ~= "string" then return end
	if st.Phase == "Incoming" then
		incomingFromUserId = st.FromUserId
		reqLabel.Text = (st.FromName or "Someone") .. " wants to trade with you!"
		reqShell.Visible = true
		refreshScrim()
		requestToken += 1
		local token = requestToken
		task.delay(st.Timeout or 20, function()
			if token == requestToken and reqShell.Visible then
				reqShell.Visible = false; refreshScrim()
			end
		end)
	elseif st.Phase == "Sent" then
		showToast("Trade request sent to " .. (st.ToName or "player") .. ".")
	elseif st.Phase == "Active" then
		countdownToken += 1
		countLabel.Visible = false
		reqShell.Visible = false
		currentTrade = st
		tradeShell.Visible = true
		refreshScrim()
		refreshTradeUI()
		refreshPicker()
	elseif st.Phase == "Countdown" then
		currentTrade = st
		tradeShell.Visible = true
		refreshScrim()
		refreshTradeUI()
		statusL.Text = "Both accepted - trading..."
		runCountdown(st.Seconds or 3)
	elseif st.Phase == "Completed" then
		local received = currentTrade and {
			Items = currentTrade.Them.Items,
			Cash = currentTrade.Them.Cash,
		} or { Items = {}, Cash = 0 }
		closeTradeWindow()
		showTradeSuccess(received)
	elseif st.Phase == "Closed" then
		closeTradeWindow()
		showToast(st.Message or "Trade closed.")
	elseif st.Phase == "Error" then
		showToast(st.Message or "Trade error.")
	end
end)

-- ===== buttons =====
acceptBtn.MouseButton1Click:Connect(function()
	if not currentTrade then return end
	remotes.TradeAction:FireServer({ Type = currentTrade.You.Confirmed and "Unconfirm" or "Confirm" })
end)
local function declineTrade()
	remotes.TradeAction:FireServer({ Type = "Cancel" })
end
declineBtn.MouseButton1Click:Connect(declineTrade)
tradeClose.MouseButton1Click:Connect(declineTrade)
local function submitCash()
	local amount = parseAmount(cashBox.Text)
	if not amount then
		showToast("Type a cash amount - plain numbers or 10k / 1m style.")
		return
	end
	remotes.TradeAction:FireServer({ Type = "SetCash", Amount = amount })
end
setCashBtn.MouseButton1Click:Connect(submitCash)
cashBox.FocusLost:Connect(function(enter) if enter then submitCash() end end)

-- ===== trading-centre zone + nearby players =====
local tradeZone
task.spawn(function()
	local gw = Workspace:WaitForChild("GameWorld")
	local tc = gw:WaitForChild("TradingCenter")
	tradeZone = tc:WaitForChild("TradeZone")
end)
local function characterInZone(character)
	if not tradeZone then return false end
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	local rel = tradeZone.CFrame:PointToObjectSpace(hrp.Position)
	local s = tradeZone.Size / 2
	return math.abs(rel.X) <= s.X and math.abs(rel.Z) <= s.Z and math.abs(rel.Y) <= s.Y + 6
end
local lastNearbyKey = nil
task.spawn(function()
	while true do
		task.wait(0.3)
		local show = characterInZone(player.Character) and not tradeShell.Visible
		nearShell.Visible = show
		if show then
			local others = {}
			for _, other in ipairs(Players:GetPlayers()) do
				if other ~= player and characterInZone(other.Character) then
					table.insert(others, other)
				end
			end
			table.sort(others, function(a, b) return a.DisplayName < b.DisplayName end)
			local key = ""
			for _, o in ipairs(others) do key = key .. o.UserId .. "," end
			if key ~= lastNearbyKey then
				lastNearbyKey = key
				for _, c in ipairs(nearList:GetChildren()) do
					if c:IsA("Frame") then c:Destroy() end
				end
				nearHint.Text = #others > 0 and "Pick a player to trade with:" or "Waiting for players to reach the gazebo..."
				for order, other in ipairs(others) do
					local cell = Instance.new("Frame")
					cell.Name = "Cell"
					cell.BackgroundTransparency = 1
					cell.Size = UDim2.new(1, -12, 0, 54)
					cell.LayoutOrder = order
					cell.Parent = nearList
					local b = UI.button(cell, other.DisplayName, "green", UDim2.new(1, 0, 0, 48), "buttonM")
					b.MouseButton1Click:Connect(function()
						remotes.TradeRequest:FireServer(other.UserId)
					end)
				end
			end
		else
			lastNearbyKey = nil
		end
	end
end)
