-- BackpackClient: a real inventory panel for your uncollected brainrots.
--
-- WHY THIS EXISTS: every unplaced brainrot is a Roblox Tool, and the default
-- hotbar only shows ten. A player holding 100+ simply cannot reach most of
-- their collection. This groups identical copies into one card with a count,
-- so a hundred items become a readable dozen rows.
--
-- Clicking a card EQUIPS that brainrot, which makes the character hold it out
-- (see InventoryHandler.buildHeld on the server). Clicking again puts it away.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("MainUI")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local SideRail = require(ReplicatedStorage.Modules.SideRail)
local shorten = require(ReplicatedStorage.Modules.NumberFormat).Short
local BrainrotThumb = require(ReplicatedStorage.Modules.BrainrotThumb)
local RarityFX = require(ReplicatedStorage.Modules.RarityFX)
local PetConfig = require(ReplicatedStorage.Modules.PetConfig)

local CF = UITheme.Camp
local FONT = UITheme.Font

local infoByName, tierByName = {}, {}
for _, e in ipairs(BrainrotConfig) do infoByName[e.Name] = e end
for _, t in ipairs(RarityConfig) do tierByName[t.Name] = t end

---------------------------------------------------------------- open button
-- The bag sits WITH the hotbar now rather than on the side rail. The bottom of
-- the screen is the inventory: six brainrot slots, and this is the door to the
-- rest of the collection.
local openBtn = Instance.new("TextButton")
openBtn.Name = "BackpackOpen"
openBtn.AnchorPoint = Vector2.new(1, 1)
-- anchored just LEFT of the six hotbar slots, which sit centred at the bottom
openBtn.Position = UDim2.new(0.5, -238, 1, -12)
openBtn.Size = UDim2.fromOffset(118, 54)
openBtn.Text = ""
openBtn.ZIndex = 9
openBtn.Parent = gui
UITheme.campButton(openBtn, CF.wood1, CF.wood2)

local openLabel = Instance.new("TextLabel")
openLabel.Size = UDim2.fromScale(1, 1)
openLabel.BackgroundTransparency = 1
openLabel.Font = FONT
openLabel.TextSize = 18
openLabel.TextColor3 = CF.onDark
openLabel.Text = "\u{1F392} BAG"
openLabel.ZIndex = 10
openLabel.Parent = openBtn
UITheme.inkText(openLabel, 2.2)

---------------------------------------------------------------- panel
local frame = Instance.new("Frame")
frame.Name = "BackpackFrame"
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.new(0.5, 0, 0.5, 0)
frame.Size = UDim2.fromOffset(756, 604)
frame.Visible = false
frame.ZIndex = 10
frame.Parent = gui
UITheme.campPanel(frame)
SideRail.registerPanel(frame)

-- Short-viewport guard: shrink and push the panel down so it never covers the
-- top TabBar band (146px) and keeps a 40px bottom margin. Anchor stays (0.5, 0.5).
local FRAME_H = 604
local hudScale = Instance.new("UIScale")
hudScale.Name = "HudFixScale"
hudScale.Parent = frame
local function relayout()
	local vh = gui.AbsoluteSize.Y
	if vh <= 0 then return end
	local s = math.min(1, (vh - 146 - 40) / FRAME_H)
	hudScale.Scale = s
	-- clamp so the panel's top edge sits at or below the 146px band
	frame.Position = UDim2.new(0.5, 0, 0.5, math.max(0, 146 + FRAME_H * s / 2 - vh / 2))
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
relayout()

local ribbon, title = UITheme.ribbon(frame, "BACKPACK", 0.62)

---------------------------------------------------------------- tabs
-- Two sections in one bag. They share the panel chrome and the grid; only what
-- build() puts in the grid differs. Brainrots are placeable and earn; pets are
-- equippable and multiply.
local MODE_BRAINROTS, MODE_PETS = "Brainrots", "Pets"
local mode = MODE_BRAINROTS
local tabButtons = {}

local tabBar = Instance.new("Frame")
tabBar.Name = "TabBar"
tabBar.Size = UDim2.fromOffset(316, 32)
tabBar.AnchorPoint = Vector2.new(0.5, 0)
tabBar.Position = UDim2.new(0.5, 0, 0, 50)
tabBar.BackgroundTransparency = 1
tabBar.ZIndex = 13
tabBar.Parent = frame

local function makeTab(text, which, x)
	local b = Instance.new("TextButton")
	b.Name = which .. "Tab"
	b.Size = UDim2.fromOffset(154, 32)
	b.Position = UDim2.fromOffset(x, 0)
	b.Text = ""
	b.ZIndex = 14
	b.Parent = tabBar
	UITheme.campButton(b, CF.wood1, CF.wood2)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextSize = 15
	l.TextColor3 = CF.cream
	l.Text = text
	l.ZIndex = 15
	l.Parent = b
	UITheme.inkText(l, 2)
	tabButtons[which] = b
	return b
end
makeTab("\u{1F9E0} BRAINROTS", MODE_BRAINROTS, 0)
makeTab("\u{1F43E} PETS", MODE_PETS, 162)

local counter = Instance.new("TextLabel")
counter.Size = UDim2.new(1, -40, 0, 20)
counter.Position = UDim2.new(0, 20, 0, 88)
counter.BackgroundTransparency = 1
counter.Font = FONT
counter.TextSize = 14
counter.TextColor3 = CF.cream
counter.TextXAlignment = Enum.TextXAlignment.Center
counter.ZIndex = 13
counter.Parent = frame
UITheme.inkText(counter, 2)

local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(1, -40, 0, 16)
hint.Position = UDim2.new(0, 20, 0, 108)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 12
hint.TextColor3 = CF.muted
hint.Text = "click a brainrot to hold it \u{2022} then aim at an empty spot on your base and click to place"
hint.ZIndex = 13
hint.Parent = frame
UITheme.inkText(hint, 1.6)

local list = Instance.new("ScrollingFrame")
-- y/height account for the tab bar added above: 128 clears tabs + counter + hint,
-- and -188 keeps the CLOSE button's 38px band at the bottom clear.
list.Size = UDim2.new(1, -28, 1, -188)
list.Position = UDim2.new(0, 14, 0, 128)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.ScrollBarImageColor3 = CF.cream
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ZIndex = 12
list.Parent = frame
-- CELL drives everything below: the tile is a square 3D render with two text
-- lines under it, the way a pet grid reads.
local CELL = Vector2.new(112, 136)
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromOffset(CELL.X, CELL.Y)
grid.CellPadding = UDim2.fromOffset(6, 6)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
grid.Parent = list

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(150, 38)
closeBtn.AnchorPoint = Vector2.new(0.5, 1)
closeBtn.Position = UDim2.new(0.5, 0, 1, -12)
closeBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Text = ""
closeBtn.ZIndex = 13
closeBtn.Parent = frame
UITheme.campButton(closeBtn, CF.wood1, CF.wood2)
local closeLabel = Instance.new("TextLabel")
closeLabel.Size = UDim2.fromScale(1, 1)
closeLabel.BackgroundTransparency = 1
closeLabel.Font = FONT
closeLabel.TextSize = 17
closeLabel.TextColor3 = CF.cream
closeLabel.Text = "CLOSE"
closeLabel.ZIndex = 14
closeLabel.Parent = closeBtn
UITheme.inkText(closeLabel, 2.2)

---------------------------------------------------------------- state
local owned = {}        -- array of { Name, Mutation, Uid }
local equippedUid = nil
local pets = {}         -- array of { Uid, Id } straight from the snapshot
local petSlots = {}     -- equipped pet Uids, server-authoritative
local selectedPetUid = nil   -- which pet's stat sheet is open, nil = the grid

local function isPetEquipped(uid)
	for _, u in ipairs(petSlots) do
		if u == uid then return true end
	end
	return false
end

local function findTool(uid)
	for _, container in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
		if container then
			for _, t in ipairs(container:GetChildren()) do
				if t:IsA("Tool") and t:GetAttribute("Uid") == uid then return t end
			end
		end
	end
	return nil
end

local function toggleHold(uid)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local tool = findTool(uid)
	if not tool then
		-- Only six brainrots have a Tool at any moment (InventoryHandler caps the
		-- hotbar). Anything else has no Tool to equip, so ask the server to swap it
		-- into a slot -- it evicts the oldest and equips this one.
		remotes.EquipBrainrot:FireServer(uid)
		equippedUid = uid
		return
	end
	if tool.Parent == char then
		hum:UnequipTools()
		equippedUid = nil
	else
		hum:EquipTool(tool)
		equippedUid = uid
	end
end

---------------------------------------------------------------- rows
local keyCount = 0

-- Gianluca's Key is DISPLAY ONLY. It is deliberately not a Tool: it cannot be
-- equipped, held, dropped or activated. It exists as a profile counter
-- (data.Keys) and shows up here purely so the player can see they have it.
-- Pinned above the brainrots with LayoutOrder -1, and given no hit target, so
-- there is nothing to click and nothing to "use" yet.
local function buildKeyTile()
	if keyCount <= 0 then return end
	local accent = Color3.fromRGB(255, 205, 70)
	local card, outer = UITheme.accentCard(list, accent, 12)
	outer.LayoutOrder = -1
	outer.ZIndex = 12
	card.ZIndex = 13

	local glyph = Instance.new("TextLabel")
	glyph.Size = UDim2.new(1, -8, 0, 84)
	glyph.Position = UDim2.new(0, 4, 0, 4)
	glyph.BackgroundTransparency = 1
	glyph.Font = FONT
	glyph.TextSize = 44
	glyph.Text = "\u{1F511}"
	glyph.ZIndex = 15
	glyph.Parent = card

	local val = Instance.new("TextLabel")
	val.Size = UDim2.new(1, -8, 0, 20)
	val.Position = UDim2.new(0, 4, 0, 90)
	val.BackgroundTransparency = 1
	val.Font = FONT
	val.TextSize = 15
	val.TextColor3 = CF.ink
	val.Text = "\u{00D7}" .. keyCount
	val.ZIndex = 16
	val.Parent = card
	UITheme.inkText(val, 1.8)

	local nm = Instance.new("TextLabel")
	nm.Size = UDim2.new(1, -8, 0, 18)
	nm.Position = UDim2.new(0, 4, 0, 110)
	nm.BackgroundTransparency = 1
	nm.Font = Enum.Font.GothamMedium
	nm.TextSize = 11
	nm.TextColor3 = CF.muted
	nm.TextTruncate = Enum.TextTruncate.AtEnd
	nm.Text = "Gianluca's Key"
	nm.ZIndex = 16
	nm.Parent = card
end

---------------------------------------------------------------- pet stat sheet
-- Built once and reused. Sits ABOVE the grid rather than replacing it, so closing is
-- instant and the scroll position behind it survives.
local sheet = Instance.new("Frame")
sheet.Name = "PetSheet"
sheet.Size = UDim2.new(1, -28, 1, -188)
sheet.Position = UDim2.new(0, 14, 0, 128)
sheet.BackgroundColor3 = CF.wood2
sheet.BorderSizePixel = 0
sheet.Visible = false
sheet.ZIndex = 25
sheet.Parent = frame
UITheme.corner(sheet, 12)
UITheme.ink(sheet, 3)

local sheetThumb = Instance.new("Frame")
sheetThumb.Name = "Thumb"
sheetThumb.Size = UDim2.fromOffset(150, 150)
sheetThumb.Position = UDim2.fromOffset(18, 18)
sheetThumb.BackgroundTransparency = 1
sheetThumb.ZIndex = 26
sheetThumb.Parent = sheet

local function sheetText(name, y, size, colour, font)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = UDim2.new(1, -196, 0, size + 8)
	l.Position = UDim2.fromOffset(182, y)
	l.BackgroundTransparency = 1
	l.Font = font or FONT
	l.TextSize = size
	l.TextColor3 = colour
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.ZIndex = 27
	l.Parent = sheet
	UITheme.inkText(l, 2)
	return l
end
local sheetName   = sheetText("Name", 20, 22, CF.cream)
local sheetRarity = sheetText("Rarity", 50, 16, CF.cream)
local sheetLuck   = sheetText("Luck", 84, 18, CF.cream)
local sheetMoney  = sheetText("Money", 110, 18, CF.cream)
local sheetSlots  = sheetText("Slots", 140, 13, CF.muted, Enum.Font.GothamMedium)

local equipBtn = Instance.new("TextButton")
equipBtn.Name = "EquipBtn"
equipBtn.Size = UDim2.fromOffset(190, 40)
equipBtn.Position = UDim2.fromOffset(182, 172)
equipBtn.Text = ""
equipBtn.ZIndex = 27
equipBtn.Parent = sheet
UITheme.campButton(equipBtn, CF.pine1, CF.pine2)
local equipLabel = Instance.new("TextLabel")
equipLabel.Size = UDim2.fromScale(1, 1)
equipLabel.BackgroundTransparency = 1
equipLabel.Font = FONT
equipLabel.TextSize = 16
equipLabel.TextColor3 = CF.cream
equipLabel.Text = "EQUIP"
equipLabel.ZIndex = 28
equipLabel.Parent = equipBtn
UITheme.inkText(equipLabel, 2.2)

local backBtn = Instance.new("TextButton")
backBtn.Name = "BackBtn"
backBtn.Size = UDim2.fromOffset(110, 34)
backBtn.AnchorPoint = Vector2.new(0, 1)
backBtn.Position = UDim2.new(0, 18, 1, -14)
backBtn.Text = ""
backBtn.ZIndex = 27
backBtn.Parent = sheet
UITheme.campButton(backBtn, CF.wood1, CF.wood2)
local backLabel = Instance.new("TextLabel")
backLabel.Size = UDim2.fromScale(1, 1)
backLabel.BackgroundTransparency = 1
backLabel.Font = FONT
backLabel.TextSize = 15
backLabel.TextColor3 = CF.cream
backLabel.Text = "\u{25C0} BACK"
backLabel.ZIndex = 28
backLabel.Parent = backBtn
UITheme.inkText(backLabel, 2)

local build   -- forward: the sheet's buttons rebuild the grid behind them

-- Trims 2.00 -> "2" and 1.50 -> "1.5" WITHOUT eating the zero in a whole number:
-- the naive tostring(v):gsub("%.?0+$", "") turns "10" into "1", which quietly
-- advertised the Secret pet's 10x money boost as 1x. Format to 2dp first so there is
-- always a decimal point, then only strip zeros behind it.
local function trimNum(v)
	local s = string.format("%.2f", v)
	s = s:gsub("0+$", "")
	s = s:gsub("%.$", "")
	return s
end

local function petRecord(uid)
	for _, p in ipairs(pets) do
		if p.Uid == uid then return p end
	end
	return nil
end

local function showSheet(uid)
	local rec = petRecord(uid)
	local def = rec and PetConfig.Pets[rec.Id]
	if not def then
		selectedPetUid = nil
		sheet.Visible = false
		return
	end
	selectedPetUid = uid

	local luck, income = PetConfig.BoostsFor(rec.Id)
	local accent = PetConfig.RARITY_COLOUR[def.Rarity] or CF.wood1
	sheetName.Text = def.Name
	sheetRarity.Text = def.Rarity:upper()
	sheetRarity.TextColor3 = accent
	sheetLuck.Text = ("\u{1F340}  LUCK  %sx"):format(trimNum(luck))
	sheetMoney.Text = ("\u{1F4B0}  MONEY  %sx"):format(trimNum(income))

	local cap = PetConfig.SLOTS_FREE
	sheetSlots.Text = ("equipped %d / %d  \u{2022}  boosts stack while equipped"):format(#petSlots, cap)

	local equipped = isPetEquipped(uid)
	-- a full slot bar must not look clickable when it cannot do anything
	local blocked = (not equipped) and #petSlots >= cap
	if blocked then
		equipLabel.Text = ("SLOTS FULL (%d/%d)"):format(#petSlots, cap)
		UITheme.setColors(equipBtn, Color3.fromRGB(150, 154, 164), Color3.fromRGB(110, 114, 124))
	else
		equipLabel.Text = equipped and "UNEQUIP" or "EQUIP"
		UITheme.setColors(equipBtn, equipped and CF.wood1 or CF.pine1, equipped and CF.wood2 or CF.pine2)
	end
	equipBtn:SetAttribute("Blocked", blocked)

	-- 3D render of the creature, rebuilt each time so it matches the selection
	for _, c in ipairs(sheetThumb:GetChildren()) do c:Destroy() end
	local vp = BrainrotThumb.add(sheetThumb, def.Name, {
		size = UDim2.fromScale(1, 1),
		position = UDim2.fromScale(0, 0),
		zIndex = 27,
	})
	if not vp then
		local sw = Instance.new("Frame")
		sw.Size = UDim2.fromScale(1, 1)
		sw.BackgroundColor3 = accent
		sw.BackgroundTransparency = 0.45
		sw.BorderSizePixel = 0
		sw.ZIndex = 27
		sw.Parent = sheetThumb
		UITheme.corner(sw, 10)
	end
	sheet.Visible = true
end

local function hideSheet()
	selectedPetUid = nil
	sheet.Visible = false
end

backBtn.MouseButton1Click:Connect(hideSheet)
equipBtn.MouseButton1Click:Connect(function()
	if not selectedPetUid then return end
	if equipBtn:GetAttribute("Blocked") then return end
	-- Server decides. petSlots is only ever written from the snapshot the server pushes
	-- back, so the tick and the slot count can never claim something it refused.
	remotes.PetEquip:FireServer(selectedPetUid, not isPetEquipped(selectedPetUid))
end)

---------------------------------------------------------------- pet grid
local function buildPets()
	counter.Text = ("%d PETS  \u{00B7}  %d / %d EQUIPPED"):format(#pets, #petSlots, PetConfig.SLOTS_FREE)
	hint.Text = "click a pet to see its stats \u{2022} equip it and it follows you around"

	if #pets == 0 then
		local empty = Instance.new("TextLabel")
		empty.Name = "EmptyNote"
		empty.Size = UDim2.new(1, -40, 0, 60)
		empty.Position = UDim2.new(0, 20, 0.5, -30)
		empty.BackgroundTransparency = 1
		empty.Font = FONT
		empty.TextSize = 16
		empty.TextColor3 = CF.muted
		empty.Text = "no pets yet \u{2014} hatch an egg at the Egg Stall"
		empty.ZIndex = 14
		empty.Parent = frame
		return
	end

	-- rarest first, then name, so the best pet is the first thing you see
	local rank = {}
	for i, r in ipairs(PetConfig.RARITY_ORDER) do rank[r] = i end
	local order = table.clone(pets)
	table.sort(order, function(a, b)
		local da, db = PetConfig.Pets[a.Id], PetConfig.Pets[b.Id]
		local ra = da and rank[da.Rarity] or 99
		local rb = db and rank[db.Rarity] or 99
		if ra ~= rb then return ra < rb end
		local na = da and da.Name or a.Id
		local nb = db and db.Name or b.Id
		if na ~= nb then return na < nb end
		return tostring(a.Uid) < tostring(b.Uid)
	end)

	for i, p in ipairs(order) do
		local def = PetConfig.Pets[p.Id]
		if def then
			local accent = PetConfig.RARITY_COLOUR[def.Rarity] or CF.wood1
			local luck, income = PetConfig.BoostsFor(p.Id)
			local card, outer = UITheme.accentCard(list, accent, 12)
			outer.LayoutOrder = i
			outer.ZIndex = 12
			card.ZIndex = 13
			RarityFX.attach(outer, card, def.Rarity, accent, i * 0.37)

			local vp = BrainrotThumb.add(card, def.Name, {
				size = UDim2.new(1, -8, 0, 84),
				position = UDim2.new(0, 4, 0, 4),
				zIndex = 14,
			})
			if not vp then
				local sw = Instance.new("Frame")
				sw.Size = UDim2.new(1, -8, 0, 84)
				sw.Position = UDim2.new(0, 4, 0, 4)
				sw.BackgroundColor3 = accent
				sw.BackgroundTransparency = 0.5
				sw.BorderSizePixel = 0
				sw.ZIndex = 14
				sw.Parent = card
				UITheme.corner(sw, 8)
			end

			local val = Instance.new("TextLabel")
			val.Size = UDim2.new(1, -8, 0, 20)
			val.Position = UDim2.new(0, 4, 0, 90)
			val.BackgroundTransparency = 1
			val.Font = FONT
			val.TextSize = 13
			val.TextColor3 = CF.ink
			val.Text = ("%sx \u{1F340}  %sx \u{1F4B0}"):format(trimNum(luck), trimNum(income))
			val.ZIndex = 16
			val.Parent = card
			UITheme.inkText(val, 1.8)

			local nm = Instance.new("TextLabel")
			nm.Size = UDim2.new(1, -8, 0, 18)
			nm.Position = UDim2.new(0, 4, 0, 110)
			nm.BackgroundTransparency = 1
			nm.Font = Enum.Font.GothamMedium
			nm.TextSize = 11
			nm.TextColor3 = CF.muted
			nm.TextTruncate = Enum.TextTruncate.AtEnd
			nm.Text = def.Name
			nm.ZIndex = 16
			nm.Parent = card

			if isPetEquipped(p.Uid) then
				local tick = Instance.new("TextLabel")
				tick.Size = UDim2.fromOffset(24, 24)
				tick.Position = UDim2.new(1, -28, 0, 4)
				tick.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				tick.BorderSizePixel = 0
				tick.Font = FONT
				tick.TextSize = 15
				tick.TextColor3 = CF.onDark
				tick.Text = "\u{2713}"
				tick.ZIndex = 17
				tick.Parent = card
				UITheme.corner(tick, 12)
				UITheme.gradient(tick, CF.pine1, CF.pine2, 90)
				UITheme.ink(tick, 2)
				UITheme.inkText(tick, 2)
			end

			local hit = Instance.new("TextButton")
			hit.Size = UDim2.fromScale(1, 1)
			hit.BackgroundTransparency = 1
			hit.Text = ""
			hit.ZIndex = 18
			hit.Parent = card
			hit.MouseButton1Click:Connect(function() showSheet(p.Uid) end)
		end
	end
end

local function buildBrainrots()
	buildKeyTile()
	hint.Text = "click a brainrot to hold it \u{2022} then aim at an empty spot on your base and click to place"

	-- group identical copies: a hundred items becomes a readable dozen rows
	local groups, order = {}, {}
	for _, item in ipairs(owned) do
		local key = (item.Mutation or "") .. "|" .. item.Name
		local g = groups[key]
		if not g then
			g = { Name = item.Name, Mutation = item.Mutation, count = 0, uids = {} }
			groups[key] = g
			order[#order + 1] = g
		end
		g.count += 1
		g.uids[#g.uids + 1] = item.Uid
	end

	-- richest first, so the best thing you own is always the first thing you see
	table.sort(order, function(a, b)
		local ia = infoByName[a.Name]
		local ib = infoByName[b.Name]
		local va = (ia and ia.CashPerSecond or 0) * Mutations.Mult(a.Mutation)
		local vb = (ib and ib.CashPerSecond or 0) * Mutations.Mult(b.Mutation)
		if va ~= vb then return va > vb end
		return a.Name < b.Name
	end)

	counter.Text = ("%d BRAINROTS  \u{00B7}  %d KINDS"):format(#owned, #order)

	if #order == 0 then
		local empty = Instance.new("TextLabel")
		empty.Name = "EmptyNote"
		empty.Size = UDim2.new(1, -40, 0, 60)
		empty.Position = UDim2.new(0, 20, 0.5, -30)
		empty.BackgroundTransparency = 1
		empty.Font = FONT
		empty.TextSize = 16
		empty.TextColor3 = CF.muted
		empty.Text = "nothing here yet \u{2014} go skip some rocks"
		empty.ZIndex = 14
		empty.Parent = frame
		return
	end

	for i, g in ipairs(order) do
		local info = infoByName[g.Name]
		local tier = info and tierByName[info.Rarity]
		local accent = tier and tier.Color or CF.wood1
		local each = (info and info.CashPerSecond or 0) * Mutations.Mult(g.Mutation)

		local isHeld = false
		for _, uid in ipairs(g.uids) do if uid == equippedUid then isHeld = true end end

		-- the rarity colour IS the border: across a grid this dense that is what
		-- carries the tier read, where a text label would be unreadable
		local card, outer = UITheme.accentCard(list, accent, 12)
		outer.LayoutOrder = i
		outer.ZIndex = 12
		card.ZIndex = 13

		-- Rare and up get glow / shimmer / sparkles / a cycling border. Common and
		-- Uncommon deliberately get nothing, which is what makes the rest read as
		-- special. The phase offset stops the whole grid pulsing in lockstep.
		RarityFX.attach(outer, card, info and info.Rarity, accent, i * 0.37)

		-- the actual 3D brainrot, which is the whole point of the grid
		local vp = BrainrotThumb.add(card, g.Name, {
			size = UDim2.new(1, -8, 0, 84),
			position = UDim2.new(0, 4, 0, 4),
			zIndex = 14,
		})
		if not vp then
			-- no model for this name: a flat rarity swatch keeps the tile
			-- readable instead of leaving a hole
			local sw = Instance.new("Frame")
			sw.Size = UDim2.new(1, -8, 0, 84)
			sw.Position = UDim2.new(0, 4, 0, 4)
			sw.BackgroundColor3 = accent
			sw.BackgroundTransparency = 0.5
			sw.BorderSizePixel = 0
			sw.ZIndex = 14
			sw.Parent = card
			UITheme.corner(sw, 8)
		end

		local val = Instance.new("TextLabel")
		val.Size = UDim2.new(1, -8, 0, 20)
		val.Position = UDim2.new(0, 4, 0, 90)
		val.BackgroundTransparency = 1
		val.Font = FONT
		val.TextSize = 15
		val.TextColor3 = CF.ink
		val.Text = "$" .. shorten(each) .. "/s"
		val.ZIndex = 16
		val.Parent = card
		UITheme.inkText(val, 1.8)

		local nm = Instance.new("TextLabel")
		nm.Size = UDim2.new(1, -8, 0, 18)
		nm.Position = UDim2.new(0, 4, 0, 110)
		nm.BackgroundTransparency = 1
		nm.Font = Enum.Font.GothamMedium
		nm.TextSize = 11
		nm.TextColor3 = CF.muted
		nm.TextTruncate = Enum.TextTruncate.AtEnd
		nm.Text = (g.Mutation and (g.Mutation .. " ") or "") .. g.Name
		nm.ZIndex = 16
		nm.Parent = card

		-- stack count, only when you own more than one
		if g.count > 1 then
			local chip = Instance.new("TextLabel")
			chip.Size = UDim2.fromOffset(34, 20)
			chip.Position = UDim2.new(0, 4, 0, 4)
			chip.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			chip.BorderSizePixel = 0
			chip.Font = FONT
			chip.TextSize = 13
			chip.TextColor3 = CF.onDark
			chip.Text = "\u{00D7}" .. g.count
			chip.ZIndex = 17
			chip.Parent = card
			UITheme.corner(chip, 7)
			UITheme.gradient(chip, CF.wood1, CF.wood2, 90)
			UITheme.ink(chip, 2)
			UITheme.inkText(chip, 2)
		end

		-- green tick on the one you are holding, same read as the reference grid
		if isHeld then
			local tick = Instance.new("TextLabel")
			tick.Size = UDim2.fromOffset(24, 24)
			tick.Position = UDim2.new(1, -28, 0, 4)
			tick.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			tick.BorderSizePixel = 0
			tick.Font = FONT
			tick.TextSize = 15
			tick.TextColor3 = CF.onDark
			tick.Text = "\u{2713}"
			tick.ZIndex = 17
			tick.Parent = card
			UITheme.corner(tick, 12)
			UITheme.gradient(tick, CF.pine1, CF.pine2, 90)
			UITheme.ink(tick, 2)
			UITheme.inkText(tick, 2)
		end

		-- whole tile is the button: a grid cell is a big, forgiving hit target
		local hit = Instance.new("TextButton")
		hit.Size = UDim2.fromScale(1, 1)
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.ZIndex = 18
		hit.Parent = card
		hit.MouseButton1Click:Connect(function()
			toggleHold(g.uids[1])
			build()
		end)
	end
end

-- Shared teardown + dispatch. `build` was forward-declared above so the stat sheet's
-- buttons could call it before it existed.
function build()
	for _, c in ipairs(list:GetChildren()) do
		if not c:IsA("UIGridLayout") then c:Destroy() end
	end
	RarityFX.reset()
	local note = frame:FindFirstChild("EmptyNote")
	if note then note:Destroy() end

	if mode == MODE_PETS then
		buildPets()
	else
		buildBrainrots()
	end
end

local function setMode(which)
	mode = which
	hideSheet()
	for id, btn in pairs(tabButtons) do
		local on = (id == which)
		UITheme.setColors(btn, on and CF.pine1 or CF.wood1, on and CF.pine2 or CF.wood2)
	end
	build()
	list.CanvasPosition = Vector2.new(0, 0)
end
for id, btn in pairs(tabButtons) do
	btn.MouseButton1Click:Connect(function() setMode(id) end)
end

---------------------------------------------------------------- wiring
local function applySnapshot(snap)
	if typeof(snap) ~= "table" or not snap.Brainrots then return end
	keyCount = math.max(0, math.floor(tonumber(snap.Keys) or 0))

	-- Pets are server-authoritative: both the roster and what is equipped come straight
	-- from the snapshot, so an equip the server refused never renders as equipped here.
	pets = {}
	for _, p in ipairs(snap.Pets or {}) do
		if p.Uid and p.Id then pets[#pets + 1] = { Uid = p.Uid, Id = p.Id } end
	end
	petSlots = {}
	for _, u in ipairs(snap.PetSlots or {}) do petSlots[#petSlots + 1] = u end

	owned = {}
	for _, e in ipairs(snap.Brainrots) do
		-- only UNPLACED copies live in the backpack; placed ones are on the base
		if not e.PadIndex and e.Uid then
			owned[#owned + 1] = { Name = e.Name, Mutation = e.Mutation, Uid = e.Uid }
		end
	end
	if frame.Visible then
		build()
		-- keep an open stat sheet honest after an equip round-trip
		if selectedPetUid then showSheet(selectedPetUid) end
	end
end

local function setOpen(open)
	frame.Visible = open
	if open then
		-- setMode does the tab recolour, the rebuild, AND the scroll reset that
		-- AutomaticCanvasSize would otherwise carry over between openings (which used to
		-- open the grid already scrolled with the top row cut in half).
		setMode(mode)
	end
end

openBtn.Activated:Connect(function() setOpen(not frame.Visible) end)
closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)

task.spawn(function()
	local ok, snap = pcall(function() return remotes.GetInitialData:InvokeServer() end)
	if ok then applySnapshot(snap) end
end)
remotes.DataUpdated.OnClientEvent:Connect(applySnapshot)

-- keep the HOLDING state honest if the player unequips with the hotbar or dies
local function watchCharacter(char)
	char.ChildRemoved:Connect(function(c)
		if c:IsA("Tool") and c:GetAttribute("Uid") == equippedUid then
			equippedUid = nil
			if frame.Visible then build() end
		end
	end)
end
if player.Character then watchCharacter(player.Character) end
player.CharacterAdded:Connect(function(char)
	equippedUid = nil
	watchCharacter(char)
end)
