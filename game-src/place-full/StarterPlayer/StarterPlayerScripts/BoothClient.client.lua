-- BoothClient (Trading Center section) — Grow-a-Garden-style booth flow in the
-- game's own chunky UIKit skin (Tokens/Builders, same system as the HUD and
-- Egg Shop). Three screens:
--   MY STAND      owner panel: listing cards + CREATE LISTING tile + Unclaim
--   PICK AN ITEM  inventory picker: tabs / search / sort / detail column w/ price
--   BUY ITEM      buyer confirm modal (thumbnail + "buy from @X?" + price)
-- BoothHandler enforces every rule; this script is buttons and display only.
-- Remote contract unchanged: BoothList {Add/Remove/Unclaim}, BoothBuy, BoothState.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

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
local SideRail = require(Modules:WaitForChild("SideRail")) -- single-open coordination

local infoByName = {}
for _, entry in ipairs(BrainrotConfig) do infoByName[entry.Name] = entry end
local tierByName, tierOrder = {}, {}
for i, tier in ipairs(RarityConfig) do
	tierByName[tier.Name] = tier
	tierOrder[tier.Name] = i
end

-- "1.5k" / "2m" style price entry, because prices here run into the millions
local SUFFIX = { k = 1e3, m = 1e6, b = 1e9, t = 1e12 }
local function parsePrice(text)
	text = string.gsub(string.lower(text or ""), "[%s,%$]", "")
	local num, suffix = string.match(text, "^(%d+%.?%d*)(%a?)$")
	if not num then return nil end
	local mult = suffix == "" and 1 or SUFFIX[suffix]
	if not mult then return nil end
	return math.floor(tonumber(num) * mult)
end

-- ===== my data mirror (display only; the server is the authority) =====
local myCounts = {}
local renderStand, renderPicker -- declared later

local function applySnapshot(snapshot)
	if not snapshot then return end
	myCounts = {}
	for _, entry in ipairs(snapshot.Brainrots or {}) do
		myCounts[entry.Name] = (myCounts[entry.Name] or 0) + 1
	end
	if renderStand then renderStand() end
	if renderPicker then renderPicker() end
end
remotes.DataUpdated.OnClientEvent:Connect(applySnapshot)
task.spawn(function()
	applySnapshot(remotes.GetInitialData:InvokeServer())
end)

-- ===== canvas: same 1350x775 fit pattern as GameHUDClient =====
local gui = Instance.new("ScreenGui")
gui.Name = "BoothUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 9
-- this place's ScreenGuis default to Global z-indexing, which buries children
-- under their z-raised parents; the whole kit assumes Sibling
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

local scrim = Instance.new("Frame")
scrim.Name = "Scrim"
scrim.Size = UDim2.fromScale(1, 1)
scrim.BackgroundColor3 = T.scrim
scrim.BackgroundTransparency = 1 -- PS99 blur-never-dim (2026-08-17): BoothBlur (see refreshScrim) carries the separation; frame kept as the refreshScrim choke handle
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
-- 2026-08-05 cross-platform: same maths, routed through Modules.Platform so
-- it also re-fires on rotation and on a device change. See TradeClient.
local Platform = require(ReplicatedStorage.Modules:WaitForChild("Platform"))
Platform.Bind(canvasScale, T.size.canvas.X, T.size.canvas.Y)

-- ===== toast (UIKit row pill, top centre) =====
local toastFrame = UI.surface(root, UDim2.fromOffset(460, 54), "row", T.radius.control, T.stroke.control)
toastFrame.AnchorPoint = Vector2.new(0.5, 0)
toastFrame.Position = UDim2.new(0.5, 0, 0, 84)
toastFrame.Visible = false
toastFrame.ZIndex = 40
local toastLabel = UI.label(toastFrame, "", "buttonM")
toastLabel.Size = UDim2.fromScale(1, 1)
toastLabel.AutomaticSize = Enum.AutomaticSize.None
toastLabel.TextXAlignment = Enum.TextXAlignment.Center
toastLabel.TextScaled = true
toastLabel.ZIndex = 41
do
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = T.text.buttonM[1]
	c.Parent = toastLabel
end
local toastToken = 0
local function showToast(message)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = message
	toastFrame.Visible = true
	task.delay(3.5, function()
		if token == toastToken then toastFrame.Visible = false end
	end)
end

-- ===== shared state =====
local myListings = {}
local maxListings = 3
local selectedName = nil          -- picker selection
local standSearch, pickerSearch = "", ""
local standSort, pickerSort = "PRICE", "NAME"   -- stand: PRICE/NAME · picker: NAME/RARITY/VALUE
local PANEL_W, PANEL_H = 940, 566

-- PS99 blur-never-dim (2026-08-17): booth screens separate from the world with
-- a backdrop blur, cloned from GameHUDClient's HUDPanelBlur recipe under a
-- UNIQUE name so cross-script destroys can't collide. Instant on/off -- NEVER
-- tween a BlurEffect (TweenService silently no-ops on non-GuiObjects here).
local function setBoothBlur(on)
	local Lighting = game:GetService("Lighting")
	local existing = Lighting:FindFirstChild("BoothBlur")
	if on and not existing then
		local blur = Instance.new("BlurEffect")
		blur.Name = "BoothBlur"
		blur.Size = 10
		blur.Parent = Lighting
	elseif not on and existing then
		existing:Destroy()
	end
end

local function refreshScrim()
	local anyOpen = false
	for _, f in ipairs(root:GetChildren()) do
		if (f.Name == "StandPanel" or f.Name == "PickerPanel" or f.Name == "BuyPanel") and f.Visible then
			anyOpen = true
		end
	end
	scrim.Visible = anyOpen
	setBoothBlur(anyOpen)
end

-- panel scaffold: an invisible SHELL (the visibility handle) holding the panel
-- surface. UI.panel's hard shadow is a sibling that does NOT track Visible, so
-- hiding a bare panel strands its black shadow on screen; inside a shell, the
-- shadow hides with everything else. Returns shell, panel, title, close.
local function makePanel(name, w, h, titleText)
	local shell = Instance.new("Frame")
	shell.Name = name
	shell.AnchorPoint = Vector2.new(0.5, 0.5)
	shell.Position = UDim2.fromScale(0.5, 0.5)
	shell.Size = UDim2.fromOffset(w, h)
	shell.BackgroundTransparency = 1
	shell.Visible = false
	shell.ZIndex = 10
	shell.Parent = root
	local p = UI.panel(shell, UDim2.fromOffset(w, h))
	p.Name = "Surface"
	local title = UI.label(p, titleText, "panelTitle")
	title.Position = UDim2.fromOffset(4, 0)
	local close = UI.button(p, "X", "red", UDim2.fromOffset(T.size.closeButton.X, T.size.closeButton.Y), "buttonL")
	close.Position = UDim2.fromOffset(w - 2 * T.pad.panel - T.size.closeButton.X, -2)
	return shell, p, title, close
end

-- track-styled TextBox (search bars, price box)
local function makeTextBox(parent, size, placeholder)
	local shell = UI.surface(parent, size, "track", T.radius.inner, T.stroke.hairline)
	local box = Instance.new("TextBox")
	box.BackgroundTransparency = 1
	box.Size = UDim2.new(1, -20, 1, 0)
	box.Position = UDim2.fromOffset(10, 0)
	box.Text = ""
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = T.color.textMutedOnDark
	box.TextColor3 = T.color.white
	box.FontFace = T.font.ui
	box.TextSize = 18
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.ClearTextOnFocus = false
	box.ClipsDescendants = true
	box.ZIndex = (shell.ZIndex or 1) + 1
	box.Parent = shell
	return shell, box
end

-- item art: real 3D thumb, or tier-coloured swatch fallback
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
		sw.Size = UDim2.fromScale(0.6, 0.6)
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
	s.Thickness = 4
	s.Color = tier and tier.Color or T.color.rarityCommon
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = f
	return f
end

local function clearChildren(container)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextButton") then child:Destroy() end
	end
end

-- =====================================================================
-- PANEL 1: MY STAND
-- =====================================================================
local standShell, standPanel, standTitle, standClose = makePanel("StandPanel", PANEL_W, PANEL_H, "MY STAND")
local INNER_W = PANEL_W - 2 * T.pad.panel

local standSearchShell, standSearchBox = makeTextBox(standPanel, UDim2.fromOffset(280, 50), "Search here...")
standSearchShell.Position = UDim2.fromOffset(300, 6)
local standSortBtn = UI.button(standPanel, "PRICE", "blue", UDim2.fromOffset(160, 50), "buttonM")
standSortBtn.Position = UDim2.fromOffset(596, 6)

local standBody = UI.surface(standPanel, UDim2.fromOffset(INNER_W, 358), "subPanel", T.radius.inner, T.stroke.control)
standBody.Position = UDim2.fromOffset(0, 78)
local standGrid = Instance.new("ScrollingFrame")
standGrid.BackgroundTransparency = 1
standGrid.BorderSizePixel = 0
standGrid.Position = UDim2.fromOffset(12, 12)
standGrid.Size = UDim2.new(1, -24, 1, -24)
standGrid.ScrollBarThickness = 6
standGrid.ScrollBarImageColor3 = T.color.scrollThumb
standGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y
standGrid.CanvasSize = UDim2.new(0, 0, 0, 0)
standGrid.ZIndex = standBody.ZIndex + 1
standGrid.Parent = standBody
do
	local g = Instance.new("UIGridLayout")
	g.CellSize = UDim2.fromOffset(160, 200)
	g.CellPadding = UDim2.fromOffset(T.pad.gridGap, T.pad.gridGap)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.Parent = standGrid
end

local standHint = UI.label(standPanel, "Buyers hold E on your stand displays to buy", "meta", T.color.textMuted)
standHint.Position = UDim2.fromOffset(4, PANEL_H - 2 * T.pad.panel - 44)
local unclaimBtn = UI.button(standPanel, "UNCLAIM", "red", UDim2.fromOffset(190, 54), "buttonM")
unclaimBtn.Position = UDim2.fromOffset(INNER_W - 190, PANEL_H - 2 * T.pad.panel - 58)

-- =====================================================================
-- PANEL 2: PICK AN ITEM (create listing)
-- =====================================================================
local pickerShell, pickerPanel, pickerTitle, pickerClose = makePanel("PickerPanel", PANEL_W, PANEL_H, "CREATE LISTING")

local pickerSearchShell, pickerSearchBox = makeTextBox(pickerPanel, UDim2.fromOffset(250, 50), "Search here...")
pickerSearchShell.Position = UDim2.fromOffset(330, 6)
local pickerSortBtn = UI.button(pickerPanel, "NAME", "blue", UDim2.fromOffset(160, 50), "buttonM")
pickerSortBtn.Position = UDim2.fromOffset(596, 6)

-- left tab column, GaG style (one live category today; pets arrive with the
-- pets-in-trading backend pass)
local tabBrainrots = UI.button(pickerPanel, "BRAINROTS", "tab", UDim2.fromOffset(150, 54), "buttonM")
tabBrainrots.Position = UDim2.fromOffset(0, 78)
do -- active ring on the live tab
	local ring = Instance.new("UIStroke")
	ring.Thickness = T.stroke.chip
	ring.Color = T.color.activeRing
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Parent = tabBrainrots
end
local tabPets = UI.button(pickerPanel, "PETS", "disabled", UDim2.fromOffset(150, 54), "buttonM")
tabPets.Position = UDim2.fromOffset(0, 144)
UI.ribbon(tabPets, "SOON", "NEW").Position = UDim2.fromOffset(96, -10)
tabPets.MouseButton1Click:Connect(function()
	showToast("Pet trading is coming soon!")
end)

local pickerBody = UI.surface(pickerPanel, UDim2.fromOffset(494, 358), "subPanel", T.radius.inner, T.stroke.control)
pickerBody.Position = UDim2.fromOffset(162, 78)
local pickerGrid = Instance.new("ScrollingFrame")
pickerGrid.BackgroundTransparency = 1
pickerGrid.BorderSizePixel = 0
pickerGrid.Position = UDim2.fromOffset(12, 12)
pickerGrid.Size = UDim2.new(1, -24, 1, -24)
pickerGrid.ScrollBarThickness = 6
pickerGrid.ScrollBarImageColor3 = T.color.scrollThumb
pickerGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y
pickerGrid.CanvasSize = UDim2.new(0, 0, 0, 0)
pickerGrid.ZIndex = pickerBody.ZIndex + 1
pickerGrid.Parent = pickerBody
do
	local g = Instance.new("UIGridLayout")
	g.CellSize = UDim2.fromOffset(140, 168)
	g.CellPadding = UDim2.fromOffset(T.pad.gridGap, T.pad.gridGap)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.Parent = pickerGrid
end
local pickerEmpty = UI.label(pickerBody, "No items found", "buttonM", T.color.textMuted)
pickerEmpty.AnchorPoint = Vector2.new(0.5, 0.5)
pickerEmpty.Position = UDim2.fromScale(0.5, 0.5)
pickerEmpty.Visible = false
pickerEmpty.ZIndex = pickerBody.ZIndex + 1

-- right detail column
local detail = UI.surface(pickerPanel, UDim2.fromOffset(240, 358), "slot", T.radius.inner, T.stroke.control)
detail.Position = UDim2.fromOffset(668, 78)
local detailArtHolder = Instance.new("Frame")
detailArtHolder.Name = "DetailArt"
detailArtHolder.BackgroundTransparency = 1
detailArtHolder.Size = UDim2.fromOffset(150, 130)
detailArtHolder.Position = UDim2.fromOffset(45, 12)
detailArtHolder.ZIndex = detail.ZIndex + 1
detailArtHolder.Parent = detail
local detailName = UI.label(detail, "Pick an item", "cardLabel")
detailName.AnchorPoint = Vector2.new(0.5, 0)
detailName.Position = UDim2.new(0.5, 0, 0, 146)
detailName.AutomaticSize = Enum.AutomaticSize.None
detailName.Size = UDim2.new(1, -16, 0, 26)
detailName.TextXAlignment = Enum.TextXAlignment.Center
detailName.TextScaled = true
detailName.ZIndex = detail.ZIndex + 1
local detailMeta = UI.label(detail, "", "meta", T.color.textMuted)
detailMeta.AnchorPoint = Vector2.new(0.5, 0)
detailMeta.Position = UDim2.new(0.5, 0, 0, 176)
detailMeta.AutomaticSize = Enum.AutomaticSize.None
detailMeta.Size = UDim2.new(1, -16, 0, 20)
detailMeta.TextXAlignment = Enum.TextXAlignment.Center
detailMeta.ZIndex = detail.ZIndex + 1
local priceShell, priceBox = makeTextBox(detail, UDim2.fromOffset(208, 52), "price  (e.g. 2.5k)")
priceShell.Position = UDim2.fromOffset(16, 224)
priceBox.TextColor3 = T.color.textAccentOnDark
local listBtn = UI.button(detail, "LIST IT!", "green", UDim2.fromOffset(208, 56), "buttonL")
listBtn.Position = UDim2.fromOffset(16, 288)

-- =====================================================================
-- PANEL 3: BUY ITEM modal
-- =====================================================================
local buyShell, buyPanel, buyTitle, buyClose = makePanel("BuyPanel", 620, 400, "BUY ITEM")

-- SINGLE-OPEN, as one "booth" group: the listing picker opens over the stand and
-- the buy confirmation over either, so these three must not close each other --
-- only everything outside the booth. Safe to register (unlike Trade's nearby
-- list): standShell is only re-opened by an explicit BoothState event carrying
-- Open=true, never by a polling loop, so nothing here fights the registry.
SideRail.registerPanel(standShell, "booth")
SideRail.registerPanel(pickerShell, "booth")
SideRail.registerPanel(buyShell, "booth")
buyShell.ZIndex = 20
local buyCard = UI.surface(buyPanel, UDim2.fromOffset(170, 190), "slot", T.radius.control, T.stroke.control)
buyCard.Position = UDim2.fromOffset(10, 92)
local buyQuestion = UI.label(buyPanel, "", "buttonM")
buyQuestion.Position = UDim2.fromOffset(206, 96)
buyQuestion.AutomaticSize = Enum.AutomaticSize.None
buyQuestion.Size = UDim2.fromOffset(372, 110)
buyQuestion.TextWrapped = true
buyQuestion.TextXAlignment = Enum.TextXAlignment.Left
buyQuestion.TextYAlignment = Enum.TextYAlignment.Top
local buyPriceChip = UI.surface(buyPanel, UDim2.fromOffset(230, 52), "track", T.radius.pill, T.stroke.hairline)
buyPriceChip.Position = UDim2.fromOffset(206, 216)
local buyPriceLabel = UI.label(buyPriceChip, "", "value", T.color.textAccentOnDark)
buyPriceLabel.Size = UDim2.fromScale(1, 1)
buyPriceLabel.AutomaticSize = Enum.AutomaticSize.None
buyPriceLabel.TextXAlignment = Enum.TextXAlignment.Center
buyPriceLabel.ZIndex = buyPriceChip.ZIndex + 1
local buyCancel = UI.button(buyPanel, "CANCEL", "red", UDim2.fromOffset(260, 60), "buttonL")
buyCancel.Position = UDim2.fromOffset(10, 292)
local buyConfirm = UI.button(buyPanel, "CONFIRM", "green", UDim2.fromOffset(260, 60), "buttonL")
buyConfirm.Position = UDim2.fromOffset(318, 292)

-- =====================================================================
-- rendering
-- =====================================================================
renderStand = function()
	if not standShell.Visible then return end
	standTitle.Text = ("MY STAND  (%d/%d)"):format(#myListings, maxListings)
	clearChildren(standGrid)

	local shown = {}
	for _, listing in ipairs(myListings) do
		if standSearch == "" or string.find(string.lower(listing.Name), standSearch, 1, true) then
			table.insert(shown, listing)
		end
	end
	if standSort == "PRICE" then
		table.sort(shown, function(a, b) return a.Price > b.Price end)
	else
		table.sort(shown, function(a, b) return a.Name < b.Name end)
	end

	for order, listing in ipairs(shown) do
		local card = UI.surface(standGrid, UDim2.fromOffset(160, 200), "slot", T.radius.slot, T.stroke.hairline)
		card.LayoutOrder = order
		card.ZIndex = standGrid.ZIndex + 1
		tierStroke(card, listing.Name)
		addArt(card, listing.Name, UDim2.fromOffset(120, 104), UDim2.fromOffset(20, 10))
		local nameL = UI.label(card, listing.Name, "chip")
		nameL.AnchorPoint = Vector2.new(0.5, 0)
		nameL.Position = UDim2.new(0.5, 0, 0, 118)
		nameL.AutomaticSize = Enum.AutomaticSize.None
		nameL.Size = UDim2.new(1, -12, 0, 18)
		nameL.TextXAlignment = Enum.TextXAlignment.Center
		nameL.TextTruncate = Enum.TextTruncate.AtEnd
		nameL.ZIndex = card.ZIndex + 1
		local priceL = UI.label(card, "$" .. formatNumber(listing.Price), "cardLabel", T.color.textAccent)
		priceL.AnchorPoint = Vector2.new(0.5, 0)
		priceL.Position = UDim2.new(0.5, 0, 0, 138)
		priceL.ZIndex = card.ZIndex + 1
		local remove = UI.button(card, "REMOVE", "red", UDim2.fromOffset(120, 34), "chip")
		remove.Position = UDim2.fromOffset(20, 162)
		remove.ZIndex = card.ZIndex + 1
		remove.MouseButton1Click:Connect(function()
			remotes.BoothList:FireServer({ Action = "Remove", Id = listing.Id })
		end)
	end

	-- CREATE LISTING tile (or full-stand notice)
	local slotsLeft = maxListings - #myListings
	local createCell = Instance.new("Frame")
	createCell.Name = "CreateCell"
	createCell.BackgroundTransparency = 1
	createCell.Size = UDim2.fromOffset(160, 200)
	createCell.LayoutOrder = 1000
	createCell.ZIndex = standGrid.ZIndex + 1
	createCell.Parent = standGrid
	local create = UI.button(createCell, "", slotsLeft > 0 and "green" or "disabled", UDim2.fromOffset(160, 200), "buttonM")
	local plus = UI.label(create, "+", "panelTitle")
	plus.AnchorPoint = Vector2.new(0.5, 0)
	plus.Position = UDim2.new(0.5, 0, 0, 40)
	plus.ZIndex = create.ZIndex + 2
	local createL = UI.label(create, slotsLeft > 0 and "CREATE\nLISTING" or "STAND\nFULL", "cardLabel")
	createL.AnchorPoint = Vector2.new(0.5, 0)
	createL.Position = UDim2.new(0.5, 0, 0, 116)
	createL.AutomaticSize = Enum.AutomaticSize.None
	createL.Size = UDim2.new(1, -12, 0, 60)
	createL.TextXAlignment = Enum.TextXAlignment.Center
	createL.TextWrapped = true
	createL.ZIndex = create.ZIndex + 2
	if slotsLeft > 0 then
		create.MouseButton1Click:Connect(function()
			standShell.Visible = false
			pickerShell.Visible = true
			renderPicker()
			refreshScrim()
		end)
	end
end

renderPicker = function()
	if not pickerShell.Visible then return end
	clearChildren(pickerGrid)

	-- owned minus already-listed
	local listedOf = {}
	for _, listing in ipairs(myListings) do
		listedOf[listing.Name] = (listedOf[listing.Name] or 0) + 1
	end
	local names = {}
	for name, count in pairs(myCounts) do
		local available = count - (listedOf[name] or 0)
		if available > 0 and (pickerSearch == "" or string.find(string.lower(name), pickerSearch, 1, true)) then
			table.insert(names, { name = name, count = available })
		end
	end
	if pickerSort == "NAME" then
		table.sort(names, function(a, b) return a.name < b.name end)
	elseif pickerSort == "RARITY" then
		table.sort(names, function(a, b)
			local ia, ib = infoByName[a.name], infoByName[b.name]
			local ra = ia and tierOrder[ia.Rarity] or 0
			local rb = ib and tierOrder[ib.Rarity] or 0
			if ra ~= rb then return ra > rb end
			return a.name < b.name
		end)
	else -- VALUE (income per second)
		table.sort(names, function(a, b)
			local ca = infoByName[a.name] and infoByName[a.name].CashPerSecond or 0
			local cb = infoByName[b.name] and infoByName[b.name].CashPerSecond or 0
			if ca ~= cb then return ca > cb end
			return a.name < b.name
		end)
	end

	pickerEmpty.Visible = #names == 0
	if selectedName and not (myCounts[selectedName] and (myCounts[selectedName] - (listedOf[selectedName] or 0)) > 0) then
		selectedName = nil
	end

	for order, item in ipairs(names) do
		local isSelected = selectedName == item.name
		local cell = Instance.new("Frame")
		cell.Name = "Cell"
		cell.BackgroundTransparency = 1
		cell.Size = UDim2.fromOffset(140, 168)
		cell.LayoutOrder = order
		cell.ZIndex = pickerGrid.ZIndex + 1
		cell.Parent = pickerGrid
		local card = UI.button(cell, "", "tab", UDim2.fromOffset(140, 168), "chip")
		tierStroke(card, item.name)
		if isSelected then
			local ring = Instance.new("UIStroke")
			ring.Thickness = 5
			ring.Color = T.color.activeRing
			ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			ring.Parent = card
		end
		addArt(card, item.name, UDim2.fromOffset(104, 88), UDim2.fromOffset(18, 8))
		local nameL = UI.label(card, item.name, "chip")
		nameL.AnchorPoint = Vector2.new(0.5, 0)
		nameL.Position = UDim2.new(0.5, 0, 0, 102)
		nameL.AutomaticSize = Enum.AutomaticSize.None
		nameL.Size = UDim2.new(1, -10, 0, 18)
		nameL.TextXAlignment = Enum.TextXAlignment.Center
		nameL.TextTruncate = Enum.TextTruncate.AtEnd
		nameL.ZIndex = card.ZIndex + 1
		local countL = UI.label(card, "x" .. item.count, "cardLabel", T.color.textAccentOnDark)
		countL.AnchorPoint = Vector2.new(0.5, 0)
		countL.Position = UDim2.new(0.5, 0, 0, 126)
		countL.ZIndex = card.ZIndex + 1
		card.MouseButton1Click:Connect(function()
			selectedName = item.name
			renderPicker()
		end)
	end

	-- detail column
	for _, child in ipairs(detailArtHolder:GetChildren()) do child:Destroy() end
	if selectedName then
		addArt(detailArtHolder, selectedName, UDim2.fromScale(1, 1))
		detailName.Text = selectedName
		local info = infoByName[selectedName]
		local tier = info and tierByName[info.Rarity]
		detailMeta.Text = (info and info.Rarity or "?") .. "  -  $" .. formatNumber(info and info.CashPerSecond or 0) .. "/s"
		if tier then detailMeta.TextColor3 = tier.Color end
	else
		detailName.Text = "Pick an item"
		detailMeta.Text = ""
	end
end

-- ===== header controls =====
standSearchBox:GetPropertyChangedSignal("Text"):Connect(function()
	standSearch = string.lower(standSearchBox.Text)
	renderStand()
end)
pickerSearchBox:GetPropertyChangedSignal("Text"):Connect(function()
	pickerSearch = string.lower(pickerSearchBox.Text)
	renderPicker()
end)
standSortBtn.MouseButton1Click:Connect(function()
	standSort = standSort == "PRICE" and "NAME" or "PRICE"
	standSortBtn:FindFirstChildOfClass("TextLabel").Text = standSort
	renderStand()
end)
local PICKER_SORTS = { "NAME", "RARITY", "VALUE" }
pickerSortBtn.MouseButton1Click:Connect(function()
	local idx = table.find(PICKER_SORTS, pickerSort) or 1
	pickerSort = PICKER_SORTS[idx % #PICKER_SORTS + 1]
	pickerSortBtn:FindFirstChildOfClass("TextLabel").Text = pickerSort
	renderPicker()
end)

-- ===== open/close wiring =====
local function closeAll()
	standShell.Visible = false
	pickerShell.Visible = false
	buyShell.Visible = false
	selectedName = nil
	refreshScrim()
end
standClose.MouseButton1Click:Connect(closeAll)
pickerClose.MouseButton1Click:Connect(function()
	-- back to the stand, GaG-style (picker is a child screen, not a sibling)
	pickerShell.Visible = false
	standShell.Visible = true
	renderStand()
	refreshScrim()
end)
buyClose.MouseButton1Click:Connect(function()
	buyShell.Visible = false
	refreshScrim()
end)

unclaimBtn.MouseButton1Click:Connect(function()
	remotes.BoothList:FireServer({ Action = "Unclaim" })
	closeAll()
end)

listBtn.MouseButton1Click:Connect(function()
	if not selectedName then
		showToast("Pick an item from the grid first.")
		return
	end
	local price = parsePrice(priceBox.Text)
	if not price or price < 1 then
		showToast("Type a price - plain numbers or 2.5k / 1m style.")
		return
	end
	remotes.BoothList:FireServer({ Action = "Add", Name = selectedName, Price = price })
	priceBox.Text = ""
	selectedName = nil
	pickerShell.Visible = false
	standShell.Visible = true
	renderStand()
	refreshScrim()
end)

-- ===== buy flow (unchanged trigger: BuyPrompt on a stand display) =====
local pendingBuy = nil
ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player then return end
	if prompt.Name ~= "BuyPrompt" then return end
	pendingBuy = {
		BoothIndex = prompt:GetAttribute("BoothIndex"),
		ListingId = prompt:GetAttribute("ListingId"),
	}
	local itemName = tostring(prompt:GetAttribute("ItemName"))
	buyQuestion.Text = ("Are you sure you want to buy this item from @%s?"):format(tostring(prompt:GetAttribute("SellerName")))
	buyPriceLabel.Text = "$" .. formatNumber(prompt:GetAttribute("Price") or 0)
	for _, child in ipairs(buyCard:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	-- listing labels can carry a mutation prefix / serial suffix ("Golden X #12");
	-- the model lookup needs the bare config name
	local bareName = itemName
	if not infoByName[bareName] then
		for configName in pairs(infoByName) do
			if string.find(itemName, configName, 1, true) then bareName = configName break end
		end
	end
	tierStroke(buyCard, bareName)
	addArt(buyCard, bareName, UDim2.fromOffset(130, 120), UDim2.fromOffset(20, 14))
	local tag = UI.label(buyCard, itemName, "chip")
	tag.AnchorPoint = Vector2.new(0.5, 0)
	tag.Position = UDim2.new(0.5, 0, 0, 148)
	tag.AutomaticSize = Enum.AutomaticSize.None
	tag.Size = UDim2.new(1, -12, 0, 30)
	tag.TextXAlignment = Enum.TextXAlignment.Center
	tag.TextWrapped = true
	tag.ZIndex = buyCard.ZIndex + 1
	buyShell.Visible = true
	refreshScrim()
end)

buyConfirm.MouseButton1Click:Connect(function()
	if pendingBuy then
		remotes.BoothBuy:FireServer(pendingBuy.BoothIndex, pendingBuy.ListingId)
		pendingBuy = nil
	end
	buyShell.Visible = false
	refreshScrim()
end)
buyCancel.MouseButton1Click:Connect(function()
	pendingBuy = nil
	buyShell.Visible = false
	refreshScrim()
end)

-- ===== server messages =====
remotes.BoothState.OnClientEvent:Connect(function(state)
	if typeof(state) ~= "table" or typeof(state.Phase) ~= "string" then return end
	if state.Phase == "Manage" then
		myListings = state.Listings or {}
		maxListings = state.MaxListings or 3
		-- Only pop the panel open when the owner actually asked for it; background
		-- refreshes (a sale, a stale-listing cull) just update an open panel.
		if state.Open and not standShell.Visible and not pickerShell.Visible then
			standShell.Visible = true
			refreshScrim()
		end
		renderStand()
		renderPicker()
	elseif state.Phase == "Toast" then
		showToast(state.Message or "")
	end
end)
