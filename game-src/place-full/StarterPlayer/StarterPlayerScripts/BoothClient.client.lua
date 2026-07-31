-- BoothClient (Trading Center section)
-- UI for the market stands: manage your own stand's listings, and confirm
-- purchases at other players' stands. BoothHandler enforces all the rules.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

-- ===== my data mirror (display only) =====
local myCounts = {}
local renderManage -- (declared later)

local function applySnapshot(snapshot)
	if not snapshot then return end
	myCounts = {}
	for _, entry in ipairs(snapshot.Brainrots or {}) do
		myCounts[entry.Name] = (myCounts[entry.Name] or 0) + 1
	end
	if renderManage then renderManage() end
end
remotes.DataUpdated.OnClientEvent:Connect(applySnapshot)
task.spawn(function()
	applySnapshot(remotes.GetInitialData:InvokeServer())
end)

-- ===== tiny UI helpers =====
local function new(className, props, parent)
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

local function clearFrames(container)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextButton") then child:Destroy() end
	end
end

local gui = new("ScreenGui", { Name = "BoothUI", ResetOnSpawn = false, DisplayOrder = 6 }, player:WaitForChild("PlayerGui"))

-- ===== toast =====
local toast = new("TextLabel", {
	Name = "Toast", Visible = false,
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 100), Size = UDim2.new(0, 400, 0, 36),
	BackgroundColor3 = PAL.Ink, BackgroundTransparency = 0.1,
	TextSize = 14, Text = "",
}, gui)
UIStyle.pill(toast)
UIStyle.stroke(toast, PAL.Booth, 3)
UIStyle.bubbleText(toast, PAL.Booth, true)
local toastToken = 0
local function showToast(message)
	toastToken += 1
	local token = toastToken
	toast.Text = message
	toast.Visible = true
	task.delay(3.5, function()
		if token == toastToken then toast.Visible = false end
	end)
end

-- ===== manage window =====
local manageFrame = new("Frame", {
	Name = "ManageFrame", Visible = false,
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 460, 0, 472),
}, gui)
UIStyle.stylePanel(manageFrame, PAL.Booth)
local manageTitle = new("TextLabel", { Text = "\u{1F3EA} YOUR STAND" }, manageFrame)
UIStyle.styleHeader(manageTitle, PAL.Booth)
manageTitle.TextSize = 18
local listedLabel = new("TextLabel", {
	Position = UDim2.new(0, 12, 0, 56), Size = UDim2.new(1, -24, 0, 16), BackgroundTransparency = 1,
	TextSize = 12,
	Text = "LISTED ITEMS (0/3)", TextXAlignment = Enum.TextXAlignment.Left,
}, manageFrame)
UIStyle.bubbleText(listedLabel, PAL.Booth, true)
local listedList = new("ScrollingFrame", {
	Position = UDim2.new(0, 12, 0, 76), Size = UDim2.new(1, -24, 0, 96),
	BackgroundColor3 = PAL.Cream, BackgroundTransparency = 0.25, BorderSizePixel = 0, ScrollBarThickness = 4,
	AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(0, 0, 0, 0),
}, manageFrame)
UIStyle.corner(listedList, 10)
new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, listedList)
local invHintLabel = new("TextLabel", {
	Position = UDim2.new(0, 12, 0, 180), Size = UDim2.new(1, -24, 0, 16), BackgroundTransparency = 1,
	TextSize = 12,
	Text = "YOUR BRAINROTS \u{2014} click one to pick it", TextXAlignment = Enum.TextXAlignment.Left,
}, manageFrame)
UIStyle.bubbleText(invHintLabel, PAL.Booth, true)
local invGrid = new("ScrollingFrame", {
	Position = UDim2.new(0, 12, 0, 200), Size = UDim2.new(1, -24, 0, 112),
	BackgroundColor3 = PAL.Cream, BackgroundTransparency = 0.25, BorderSizePixel = 0, ScrollBarThickness = 4,
	AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(0, 0, 0, 0),
}, manageFrame)
UIStyle.corner(invGrid, 10)
new("UIGridLayout", {
	CellSize = UDim2.new(0, 138, 0, 28), CellPadding = UDim2.new(0, 4, 0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, invGrid)
local selectedLabel = new("TextLabel", {
	Position = UDim2.new(0, 12, 0, 318), Size = UDim2.new(1, -24, 0, 18), BackgroundTransparency = 1,
	TextSize = 13,
	Text = "Selected: \u{2014}", TextXAlignment = Enum.TextXAlignment.Left,
}, manageFrame)
UIStyle.bubbleText(selectedLabel, PAL.Booth, true)
local priceBox = new("TextBox", {
	Position = UDim2.new(0, 12, 0, 342), Size = UDim2.new(0, 140, 0, 30),
	BackgroundColor3 = PAL.Cream, TextColor3 = PAL.Ink,
	Font = UIStyle.Fonts.Body, TextSize = 13, Text = "", PlaceholderText = "price in $",
	PlaceholderColor3 = Color3.fromRGB(150, 140, 125),
	ClearTextOnFocus = false,
}, manageFrame)
UIStyle.corner(priceBox, 8)
UIStyle.stroke(priceBox, PAL.Booth, 2)
local listButton = new("TextButton", {
	Position = UDim2.new(0, 160, 0, 342), Size = UDim2.new(0, 150, 0, 30),
	TextSize = 13, Text = "LIST FOR SALE",
}, manageFrame)
UIStyle.styleButton(listButton, PAL.Booth)
UIStyle.attachHoverPress(listButton)
local unclaimButton = new("TextButton", {
	Position = UDim2.new(0, 12, 1, -46), Size = UDim2.new(0, 150, 0, 34),
	TextSize = 13, Text = "UNCLAIM STAND",
}, manageFrame)
UIStyle.styleButton(unclaimButton, PAL.Red)
UIStyle.attachHoverPress(unclaimButton)
local closeButton = new("TextButton", {
	Position = UDim2.new(1, -112, 1, -46), Size = UDim2.new(0, 100, 0, 34),
	TextSize = 13, Text = "CLOSE",
}, manageFrame)
UIStyle.styleButton(closeButton, PAL.Grey)
UIStyle.attachHoverPress(closeButton)

local myListings = {}
local maxListings = 3
local selectedName = nil

renderManage = function()
	if not manageFrame.Visible then return end

	-- drop a selection that the player no longer owns (sold/traded it away)
	if selectedName and not myCounts[selectedName] then
		selectedName = nil
		selectedLabel.Text = "Selected: \u{2014}"
	end

	listedLabel.Text = ("LISTED ITEMS (%d/%d)"):format(#myListings, maxListings)
	clearFrames(listedList)
	for _, listing in ipairs(myListings) do
		local info = infoByName[listing.Name]
		local tier = info and tierByName[info.Rarity]
		local row = new("Frame", {
			Size = UDim2.new(1, -6, 0, 30),
		}, listedList)
		UIStyle.styleCard(row, PAL.Booth)
		UIStyle.corner(row, 8)
		local rowStroke = row:FindFirstChild("UIStyleStrokeBorder")
		if rowStroke then rowStroke.Thickness = 2 end
		local swatch = new("Frame", {
			Position = UDim2.new(0, 6, 0.5, -7), Size = UDim2.new(0, 14, 0, 14),
			BackgroundColor3 = tier and tier.Color or Color3.fromRGB(255, 255, 255),
		}, row)
		UIStyle.corner(swatch, 5)
		new("TextLabel", {
			Position = UDim2.new(0, 26, 0, 0), Size = UDim2.new(1, -186, 1, 0), BackgroundTransparency = 1,
			TextColor3 = PAL.Ink, Font = UIStyle.Fonts.Body, TextSize = 13,
			Text = listing.Name,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		}, row)
		local priceLabel = new("TextLabel", {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -84, 0.5, 0), Size = UDim2.new(0, 70, 0, 20),
			TextSize = 12, Text = "$" .. formatNumber(listing.Price),
		}, row)
		UIStyle.goldAmount(priceLabel)
		local removeButton = new("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.new(0, 72, 0, 22),
			TextSize = 11, Text = "REMOVE",
		}, row)
		UIStyle.styleButton(removeButton, PAL.Red)
		UIStyle.corner(removeButton, 8)
		UIStyle.attachHoverPress(removeButton)
		removeButton.MouseButton1Click:Connect(function()
			remotes.BoothList:FireServer({ Action = "Remove", Id = listing.Id })
		end)
	end

	-- inventory grid: owned minus already listed
	clearFrames(invGrid)
	local listedOf = {}
	for _, listing in ipairs(myListings) do
		listedOf[listing.Name] = (listedOf[listing.Name] or 0) + 1
	end
	local names = {}
	for name in pairs(myCounts) do table.insert(names, name) end
	table.sort(names)
	for _, name in ipairs(names) do
		local available = (myCounts[name] or 0) - (listedOf[name] or 0)
		local info = infoByName[name]
		local tier = info and tierByName[info.Rarity]
		local isSelected = selectedName == name
		local cell = new("TextButton", {
			Font = UIStyle.Fonts.Body, TextSize = 12,
			Text = name .. "  x" .. available,
			AutoButtonColor = available > 0,
		}, invGrid)
		UIStyle.corner(cell, 8)
		if isSelected then
			cell.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			UIStyle.gradient(cell, PAL.Booth)
			UIStyle.bubbleText(cell, PAL.Booth, true)
		else
			cell.BackgroundColor3 = available > 0 and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(225, 220, 210)
			cell.TextColor3 = available > 0 and PAL.Ink or Color3.fromRGB(150, 145, 135)
		end
		new("UIStroke", { Color = tier and tier.Color or Color3.fromRGB(120, 120, 130), Thickness = isSelected and 3 or 2, LineJoinMode = Enum.LineJoinMode.Round }, cell)
		if available > 0 then
			UIStyle.attachHoverPress(cell)
			cell.MouseButton1Click:Connect(function()
				selectedName = name
				selectedLabel.Text = "Selected: " .. name
				renderManage()
			end)
		else
			UIStyle.attachHoverPress(cell, false)
		end
	end
end

listButton.MouseButton1Click:Connect(function()
	if not selectedName then
		showToast("Pick a brainrot from the grid first.")
		return
	end
	local price = tonumber(priceBox.Text)
	if not price or price < 1 then
		showToast("Type a price (at least $1) in the price box.")
		return
	end
	remotes.BoothList:FireServer({ Action = "Add", Name = selectedName, Price = price })
end)
unclaimButton.MouseButton1Click:Connect(function()
	remotes.BoothList:FireServer({ Action = "Unclaim" })
	selectedName = nil
	selectedLabel.Text = "Selected: \u{2014}"
	UIStyle.popOut(manageFrame)
end)
closeButton.MouseButton1Click:Connect(function()
	selectedName = nil
	selectedLabel.Text = "Selected: \u{2014}"
	UIStyle.popOut(manageFrame)
end)

-- ===== buy confirm popup =====
local buyFrame = new("Frame", {
	Name = "BuyFrame", Visible = false,
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 330, 0, 134),
}, gui)
UIStyle.stylePanel(buyFrame, PAL.Booth)
local buyLabel = new("TextLabel", {
	Position = UDim2.new(0, 12, 0, 10), Size = UDim2.new(1, -24, 0, 56), BackgroundTransparency = 1,
	TextSize = 15, Text = "",
	TextWrapped = true,
}, buyFrame)
UIStyle.bubbleText(buyLabel, PAL.Booth, true)
local buyButton = new("TextButton", {
	Position = UDim2.new(0, 24, 1, -46), Size = UDim2.new(0, 130, 0, 34),
	TextSize = 15, Text = "BUY",
}, buyFrame)
UIStyle.styleButton(buyButton, PAL.Booth)
UIStyle.attachHoverPress(buyButton)
local cancelBuyButton = new("TextButton", {
	Position = UDim2.new(1, -154, 1, -46), Size = UDim2.new(0, 130, 0, 34),
	TextSize = 15, Text = "CANCEL",
}, buyFrame)
UIStyle.styleButton(cancelBuyButton, PAL.Grey)
UIStyle.attachHoverPress(cancelBuyButton)

local pendingBuy = nil

ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player then return end
	if prompt.Name ~= "BuyPrompt" then return end
	pendingBuy = {
		BoothIndex = prompt:GetAttribute("BoothIndex"),
		ListingId = prompt:GetAttribute("ListingId"),
	}
	buyLabel.Text = ("Buy %s for $%s from %s?"):format(
		tostring(prompt:GetAttribute("ItemName")),
		formatNumber(prompt:GetAttribute("Price") or 0),
		tostring(prompt:GetAttribute("SellerName"))
	)
	UIStyle.popIn(buyFrame)
end)

buyButton.MouseButton1Click:Connect(function()
	if pendingBuy then
		remotes.BoothBuy:FireServer(pendingBuy.BoothIndex, pendingBuy.ListingId)
		pendingBuy = nil
	end
	UIStyle.popOut(buyFrame)
end)
cancelBuyButton.MouseButton1Click:Connect(function()
	pendingBuy = nil
	UIStyle.popOut(buyFrame)
end)

-- ===== server messages =====
remotes.BoothState.OnClientEvent:Connect(function(state)
	if typeof(state) ~= "table" or typeof(state.Phase) ~= "string" then return end
	if state.Phase == "Manage" then
		myListings = state.Listings or {}
		maxListings = state.MaxListings or 3
		-- Only pop the window open when the owner actually asked for it. Background
		-- refreshes (a sale, a stale-listing cull) just update an already-open window.
		if state.Open and not manageFrame.Visible then
			UIStyle.popIn(manageFrame)
		end
		renderManage()
	elseif state.Phase == "Toast" then
		showToast(state.Message or "")
	end
end)
