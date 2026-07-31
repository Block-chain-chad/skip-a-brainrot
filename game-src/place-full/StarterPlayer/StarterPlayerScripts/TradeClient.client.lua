-- TradeClient (Trading Center section)
-- Builds the trading UI and talks to TradeHandler on the server.
-- The server owns every rule; this script is only buttons and display.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local BrainrotConfig = require(Modules:WaitForChild("BrainrotConfig"))
local RarityConfig = require(Modules:WaitForChild("RarityConfig"))
local UIStyle = require(Modules:WaitForChild("UIStyle"))
local PAL = UIStyle.Palette

local infoByName = {}
for _, entry in ipairs(BrainrotConfig) do
	infoByName[entry.Name] = entry
end
local tierByName = {}
for _, tier in ipairs(RarityConfig) do
	tierByName[tier.Name] = tier
end

-- canonical abbreviator, K through Qi -- see Modules.NumberFormat
local formatNumber = require(ReplicatedStorage.Modules.NumberFormat).Short

-- ===== my data mirror (display only; the server is the authority) =====
local myCash = 0
local myCounts = {} -- [brainrot name] = how many I own
local currentTrade = nil -- latest TradeState while the window is open

local refreshTradeUI -- (declared later)
local updateMyCashLabel

local function applySnapshot(snapshot)
	if not snapshot then return end
	myCash = snapshot.Cash or myCash
	myCounts = {}
	for _, entry in ipairs(snapshot.Brainrots or {}) do
		myCounts[entry.Name] = (myCounts[entry.Name] or 0) + 1
	end
	if refreshTradeUI then refreshTradeUI() end
end

remotes.DataUpdated.OnClientEvent:Connect(applySnapshot)
remotes.CashTick.OnClientEvent:Connect(function(newCash)
	myCash = newCash
	if updateMyCashLabel then updateMyCashLabel() end
end)
task.spawn(function()
	applySnapshot(remotes.GetInitialData:InvokeServer())
end)

-- ===== tiny UI helper =====
local function new(className, props, parent)
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

local gui = new("ScreenGui", { Name = "TradeUI", ResetOnSpawn = false, DisplayOrder = 5 }, player:WaitForChild("PlayerGui"))

-- ===== toast (small message at the top) =====
local toast = new("TextLabel", {
	Name = "Toast", Visible = false,
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62), Size = UDim2.new(0, 380, 0, 36),
	BackgroundColor3 = PAL.Ink, BackgroundTransparency = 0.1,
	TextSize = 14, Text = "",
}, gui)
UIStyle.pill(toast)
UIStyle.stroke(toast, PAL.Trade, 3)
UIStyle.bubbleText(toast, PAL.Trade, true)

local toastToken = 0
local function showToast(message)
	toastToken += 1
	local token = toastToken
	toast.Text = message
	toast.Visible = true
	task.delay(3, function()
		if token == toastToken then toast.Visible = false end
	end)
end

-- ===== incoming request popup =====
local requestFrame = new("Frame", {
	Name = "RequestFrame", Visible = false,
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 110), Size = UDim2.new(0, 320, 0, 100),
}, gui)
UIStyle.stylePanel(requestFrame, PAL.Trade)
local requestLabel = new("TextLabel", {
	Position = UDim2.new(0, 10, 0, 8), Size = UDim2.new(1, -20, 0, 36), BackgroundTransparency = 1,
	TextSize = 15, Text = "", TextWrapped = true,
}, requestFrame)
UIStyle.bubbleText(requestLabel, PAL.Trade, true)
local acceptButton = new("TextButton", {
	Position = UDim2.new(0, 24, 1, -44), Size = UDim2.new(0, 128, 0, 34),
	TextSize = 15, Text = "ACCEPT",
}, requestFrame)
UIStyle.styleButton(acceptButton, PAL.Trade)
UIStyle.attachHoverPress(acceptButton)
local declineButton = new("TextButton", {
	Position = UDim2.new(1, -152, 1, -44), Size = UDim2.new(0, 128, 0, 34),
	TextSize = 15, Text = "DECLINE",
}, requestFrame)
UIStyle.styleButton(declineButton, PAL.Red)
UIStyle.attachHoverPress(declineButton)

local requestToken = 0
local incomingFromUserId = nil -- who the popup currently on screen is from
acceptButton.MouseButton1Click:Connect(function()
	requestFrame.Visible = false
	-- echo the requester id so the server won't pair us with a newer request
	-- that silently overwrote this one after the popup was drawn
	remotes.TradeRespond:FireServer(true, incomingFromUserId)
end)
declineButton.MouseButton1Click:Connect(function()
	requestFrame.Visible = false
	remotes.TradeRespond:FireServer(false, incomingFromUserId)
end)

-- ===== nearby players panel (shows while you stand in the Trading Center) =====
local nearbyFrame = new("Frame", {
	Name = "NearbyFrame", Visible = false,
	AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.new(0, 210, 0, 240),
}, gui)
UIStyle.stylePanel(nearbyFrame, PAL.Trade)
local nearbyTitle = new("TextLabel", {
	Position = UDim2.new(0, 0, 0, 6), Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1,
	TextSize = 15, Text = "\u{1F504} TRADING CENTER",
}, nearbyFrame)
UIStyle.bubbleText(nearbyTitle, PAL.Trade)
local nearbyHint = new("TextLabel", {
	Position = UDim2.new(0, 8, 0, 32), Size = UDim2.new(1, -16, 0, 28), BackgroundTransparency = 1,
	TextSize = 12,
	Text = "Pick a player to trade with:", TextWrapped = true,
}, nearbyFrame)
UIStyle.bubbleText(nearbyHint, PAL.Trade, true)
local nearbyList = new("ScrollingFrame", {
	Position = UDim2.new(0, 8, 0, 62), Size = UDim2.new(1, -16, 1, -70),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
	AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(0, 0, 0, 0),
}, nearbyFrame)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, nearbyList)

-- ===== trade window =====
local tradeFrame = new("Frame", {
	Name = "TradeFrame", Visible = false,
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 660, 0, 484),
}, gui)
UIStyle.stylePanel(tradeFrame, PAL.Trade)
local titleLabel = new("TextLabel", { Text = "TRADING" }, tradeFrame)
UIStyle.styleHeader(titleLabel, PAL.Trade)
titleLabel.TextSize = 18

local function makeOfferPanel(x)
	local panel = new("Frame", {
		Position = UDim2.new(0, x, 0, 54), Size = UDim2.new(0, 318, 0, 220),
	}, tradeFrame)
	UIStyle.styleCard(panel, PAL.Trade)
	local header = new("TextLabel", {
		Position = UDim2.new(0, 10, 0, 4), Size = UDim2.new(1, -20, 0, 22), BackgroundTransparency = 1,
		TextColor3 = PAL.Ink, Font = UIStyle.Fonts.Title, TextSize = 15, Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
	}, panel)
	local list = new("ScrollingFrame", {
		Position = UDim2.new(0, 8, 0, 30), Size = UDim2.new(1, -16, 0, 150),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(0, 0, 0, 0),
	}, panel)
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local cashLabel = new("TextLabel", {
		Position = UDim2.new(0, 8, 1, -34), Size = UDim2.new(0, 150, 0, 26),
		TextSize = 13, Text = "+ $0 cash",
	}, panel)
	UIStyle.goldAmount(cashLabel)
	return { header = header, list = list, cashLabel = cashLabel }
end

local yourPanel = makeOfferPanel(8)
local theirPanel = makeOfferPanel(334)

local invHintLabel = new("TextLabel", {
	Position = UDim2.new(0, 8, 0, 280), Size = UDim2.new(1, -16, 0, 18), BackgroundTransparency = 1,
	TextSize = 12,
	Text = "YOUR BRAINROTS \u{2014} click to add to your offer (click a row in your offer to take it back)",
	TextXAlignment = Enum.TextXAlignment.Left,
}, tradeFrame)
UIStyle.bubbleText(invHintLabel, PAL.Trade, true)
local inventoryList = new("ScrollingFrame", {
	Position = UDim2.new(0, 8, 0, 302), Size = UDim2.new(1, -16, 0, 76),
	BackgroundColor3 = PAL.Cream, BackgroundTransparency = 0.25, BorderSizePixel = 0, ScrollBarThickness = 4,
	AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(0, 0, 0, 0),
}, tradeFrame)
UIStyle.corner(inventoryList, 12)
new("UIGridLayout", {
	CellSize = UDim2.new(0, 155, 0, 28), CellPadding = UDim2.new(0, 4, 0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, inventoryList)

local myCashLabel = new("TextLabel", {
	Position = UDim2.new(0, 8, 0, 386), Size = UDim2.new(0, 180, 0, 28),
	TextSize = 13, Text = "Your cash: $0",
}, tradeFrame)
UIStyle.goldAmount(myCashLabel)
local cashBox = new("TextBox", {
	Position = UDim2.new(0, 196, 0, 386), Size = UDim2.new(0, 130, 0, 28),
	BackgroundColor3 = PAL.Cream, TextColor3 = PAL.Ink,
	Font = UIStyle.Fonts.Body, TextSize = 13, Text = "", PlaceholderText = "cash amount",
	PlaceholderColor3 = Color3.fromRGB(150, 140, 125),
	ClearTextOnFocus = false,
}, tradeFrame)
UIStyle.corner(cashBox, 8)
UIStyle.stroke(cashBox, PAL.Trade, 2)
local offerCashButton = new("TextButton", {
	Position = UDim2.new(0, 334, 0, 386), Size = UDim2.new(0, 110, 0, 28),
	TextSize = 13, Text = "OFFER CASH",
}, tradeFrame)
UIStyle.styleButton(offerCashButton, PAL.Gold)
UIStyle.attachHoverPress(offerCashButton)

local statusLabel = new("TextLabel", {
	Position = UDim2.new(0, 8, 1, -44), Size = UDim2.new(0, 380, 0, 36), BackgroundTransparency = 1,
	TextSize = 14, Text = "",
	TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
}, tradeFrame)
UIStyle.bubbleText(statusLabel, PAL.Trade, true)
local cancelButton = new("TextButton", {
	Position = UDim2.new(1, -260, 1, -44), Size = UDim2.new(0, 104, 0, 34),
	TextSize = 15, Text = "CANCEL",
}, tradeFrame)
UIStyle.styleButton(cancelButton, PAL.Red)
UIStyle.attachHoverPress(cancelButton)
local confirmButton = new("TextButton", {
	Position = UDim2.new(1, -148, 1, -44), Size = UDim2.new(0, 140, 0, 34),
	TextSize = 15, Text = "CONFIRM",
}, tradeFrame)
UIStyle.styleButton(confirmButton, PAL.Grey)
UIStyle.attachHoverPress(confirmButton)

-- ===== rendering =====
local function clearFrames(container)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextButton") then child:Destroy() end
	end
end

local function sortedNames(items)
	local names = {}
	for name in pairs(items) do table.insert(names, name) end
	table.sort(names)
	return names
end

local function makeOfferRow(list, name, count, clickable)
	local info = infoByName[name]
	local tier = info and tierByName[info.Rarity]
	local row = new(clickable and "TextButton" or "Frame", {
		Size = UDim2.new(1, -6, 0, 26),
	}, list)
	if clickable then
		row.Text = ""
		row.AutoButtonColor = true
	end
	UIStyle.styleCard(row, PAL.Trade)
	UIStyle.corner(row, 8)
	local rowStroke = row:FindFirstChild("UIStyleStrokeBorder")
	if rowStroke then rowStroke.Thickness = 2 end
	local swatch = new("Frame", {
		Position = UDim2.new(0, 6, 0.5, -7), Size = UDim2.new(0, 14, 0, 14),
		BackgroundColor3 = tier and tier.Color or Color3.fromRGB(255, 255, 255),
	}, row)
	UIStyle.corner(swatch, 5)
	new("TextLabel", {
		Position = UDim2.new(0, 26, 0, 0), Size = UDim2.new(1, -32, 1, 0), BackgroundTransparency = 1,
		TextColor3 = PAL.Ink, Font = UIStyle.Fonts.Body, TextSize = 13,
		Text = name .. "  x" .. count, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, row)
	if clickable then
		UIStyle.attachHoverPress(row)
	end
	return row
end

updateMyCashLabel = function()
	myCashLabel.Text = "Your cash: $" .. formatNumber(myCash)
end

refreshTradeUI = function()
	if not currentTrade or not tradeFrame.Visible then return end
	local state = currentTrade

	titleLabel.Text = "TRADING WITH " .. string.upper(state.OtherName or "?")
	yourPanel.header.Text = state.You.Confirmed and "YOUR OFFER  \u{2713} CONFIRMED" or "YOUR OFFER"
	theirPanel.header.Text = (state.OtherName or "THEM") .. (state.Them.Confirmed and "  \u{2713} CONFIRMED" or "")

	clearFrames(yourPanel.list)
	for _, name in ipairs(sortedNames(state.You.Items)) do
		local row = makeOfferRow(yourPanel.list, name, state.You.Items[name], true)
		row.MouseButton1Click:Connect(function()
			remotes.TradeAction:FireServer({ Type = "RemoveItem", Name = name })
		end)
	end
	clearFrames(theirPanel.list)
	for _, name in ipairs(sortedNames(state.Them.Items)) do
		makeOfferRow(theirPanel.list, name, state.Them.Items[name], false)
	end

	yourPanel.cashLabel.Text = "+ $" .. formatNumber(state.You.Cash) .. " cash"
	theirPanel.cashLabel.Text = "+ $" .. formatNumber(state.Them.Cash) .. " cash"

	-- inventory grid: what I own minus what I already offered
	clearFrames(inventoryList)
	local names = {}
	for name in pairs(myCounts) do table.insert(names, name) end
	table.sort(names)
	for _, name in ipairs(names) do
		local available = (myCounts[name] or 0) - (state.You.Items[name] or 0)
		local info = infoByName[name]
		local tier = info and tierByName[info.Rarity]
		local cell = new("TextButton", {
			BackgroundColor3 = available > 0 and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(225, 220, 210),
			TextColor3 = available > 0 and PAL.Ink or Color3.fromRGB(150, 145, 135),
			Font = UIStyle.Fonts.Body, TextSize = 12,
			Text = name .. "  x" .. available,
			AutoButtonColor = available > 0,
		}, inventoryList)
		UIStyle.corner(cell, 8)
		new("UIStroke", { Color = tier and tier.Color or Color3.fromRGB(120, 120, 130), Thickness = 2, LineJoinMode = Enum.LineJoinMode.Round }, cell)
		if available > 0 then
			UIStyle.attachHoverPress(cell)
			cell.MouseButton1Click:Connect(function()
				remotes.TradeAction:FireServer({ Type = "AddItem", Name = name })
			end)
		else
			UIStyle.attachHoverPress(cell, false)
		end
	end

	updateMyCashLabel()
	cashBox.Text = state.You.Cash > 0 and tostring(state.You.Cash) or cashBox.Text

	confirmButton.Text = state.You.Confirmed and "UNCONFIRM" or "CONFIRM"
	-- confirmed = green gradient, unconfirmed = grey (instantly distinguishable)
	UIStyle.styleButton(confirmButton, state.You.Confirmed and PAL.Trade or PAL.Grey)

	if state.Phase == "Active" then
		if state.You.Confirmed and not state.Them.Confirmed then
			statusLabel.Text = "Waiting for " .. (state.OtherName or "them") .. " to confirm..."
		elseif state.Them.Confirmed and not state.You.Confirmed then
			statusLabel.Text = (state.OtherName or "They") .. " confirmed! Review the offer, then confirm."
		else
			statusLabel.Text = "Add brainrots or cash, then press CONFIRM."
		end
	end
end

-- ===== window open/close + countdown =====
local countdownToken = 0

local function closeTradeWindow()
	countdownToken += 1
	currentTrade = nil
	if tradeFrame.Visible then
		UIStyle.popOut(tradeFrame) -- hides the panel when the shrink finishes
	end
	cashBox.Text = "" -- don't carry a cash amount into the next trade
end

local function runCountdown(seconds)
	countdownToken += 1
	local token = countdownToken
	task.spawn(function()
		for remainingTime = seconds, 1, -1 do
			if token ~= countdownToken or not tradeFrame.Visible then return end
			statusLabel.Text = "\u{2713} Both confirmed \u{2014} trading in " .. remainingTime .. "... (CANCEL to stop)"
			task.wait(1)
		end
	end)
end

-- ===== server state updates =====
remotes.TradeState.OnClientEvent:Connect(function(state)
	if typeof(state) ~= "table" or typeof(state.Phase) ~= "string" then return end

	if state.Phase == "Incoming" then
		incomingFromUserId = state.FromUserId
		requestLabel.Text = "\u{1F504} " .. (state.FromName or "Someone") .. " wants to trade with you!"
		UIStyle.popIn(requestFrame)
		requestToken += 1
		local token = requestToken
		task.delay(state.Timeout or 20, function()
			if token == requestToken then requestFrame.Visible = false end
		end)

	elseif state.Phase == "Sent" then
		showToast("Trade request sent to " .. (state.ToName or "player") .. ".")

	elseif state.Phase == "Active" then
		countdownToken += 1 -- stops any countdown display
		requestFrame.Visible = false
		currentTrade = state
		tradeFrame.Visible = true
		refreshTradeUI()

	elseif state.Phase == "Countdown" then
		currentTrade = state
		tradeFrame.Visible = true
		refreshTradeUI()
		runCountdown(state.Seconds or 3)

	elseif state.Phase == "Completed" then
		closeTradeWindow()
		showToast("\u{2705} Trade complete!")

	elseif state.Phase == "Closed" then
		closeTradeWindow()
		showToast(state.Message or "Trade closed.")

	elseif state.Phase == "Error" then
		showToast(state.Message or "Trade error.")
	end
end)

-- ===== window buttons =====
confirmButton.MouseButton1Click:Connect(function()
	if not currentTrade then return end
	if currentTrade.You.Confirmed then
		remotes.TradeAction:FireServer({ Type = "Unconfirm" })
	else
		remotes.TradeAction:FireServer({ Type = "Confirm" })
	end
end)
cancelButton.MouseButton1Click:Connect(function()
	remotes.TradeAction:FireServer({ Type = "Cancel" })
end)

local function submitCash()
	local amount = tonumber(cashBox.Text)
	if not amount then
		showToast("Type a number in the cash box first.")
		return
	end
	remotes.TradeAction:FireServer({ Type = "SetCash", Amount = amount })
end
offerCashButton.MouseButton1Click:Connect(submitCash)
cashBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then submitCash() end
end)

-- ===== Trading Center zone + nearby players =====
local tradeZone
task.spawn(function()
	local gameWorld = Workspace:WaitForChild("GameWorld")
	local tradingCenter = gameWorld:WaitForChild("TradingCenter")
	tradeZone = tradingCenter:WaitForChild("TradeZone")
end)

local function characterInZone(character)
	if not tradeZone then return false end
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	local rel = tradeZone.CFrame:PointToObjectSpace(hrp.Position)
	local s = tradeZone.Size / 2
	return math.abs(rel.X) <= s.X and math.abs(rel.Z) <= s.Z and math.abs(rel.Y) <= s.Y + 6
end

local lastNearbyKey = nil -- nil forces the first pass to render the list
task.spawn(function()
	while true do
		task.wait(0.3)
		local inZone = characterInZone(player.Character)
		local showPanel = inZone and not tradeFrame.Visible
		if showPanel and not nearbyFrame.Visible then
			UIStyle.popIn(nearbyFrame)
		elseif not showPanel then
			nearbyFrame.Visible = false
		end
		if showPanel then
			local others = {}
			for _, otherPlayer in ipairs(Players:GetPlayers()) do
				if otherPlayer ~= player and characterInZone(otherPlayer.Character) then
					table.insert(others, otherPlayer)
				end
			end
			table.sort(others, function(a, b) return a.DisplayName < b.DisplayName end)

			local key = ""
			for _, otherPlayer in ipairs(others) do
				key = key .. otherPlayer.UserId .. ","
			end
			if key ~= lastNearbyKey then
				lastNearbyKey = key
				clearFrames(nearbyList)
				nearbyHint.Text = #others > 0 and "Pick a player to trade with:" or "Waiting for other players to enter the plaza..."
				for _, otherPlayer in ipairs(others) do
					local button = new("TextButton", {
						Size = UDim2.new(1, -6, 0, 32),
						TextSize = 14,
						Text = "\u{1F504} " .. otherPlayer.DisplayName,
					}, nearbyList)
					UIStyle.styleButton(button, PAL.Trade)
					UIStyle.attachHoverPress(button)
					button.MouseButton1Click:Connect(function()
						remotes.TradeRequest:FireServer(otherPlayer.UserId)
					end)
				end
			end
		else
			lastNearbyKey = nil
		end
	end
end)
