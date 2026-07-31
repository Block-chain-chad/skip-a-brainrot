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

local ribbon, title = UITheme.ribbon(frame, "BACKPACK", 0.62)

local counter = Instance.new("TextLabel")
counter.Size = UDim2.new(1, -40, 0, 20)
counter.Position = UDim2.new(0, 20, 0, 52)
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
hint.Position = UDim2.new(0, 20, 0, 72)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 12
hint.TextColor3 = CF.muted
hint.Text = "click a brainrot to hold it \u{2022} then aim at an empty spot on your base and click to place"
hint.ZIndex = 13
hint.Parent = frame
UITheme.inkText(hint, 1.6)

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -28, 1, -152)
list.Position = UDim2.new(0, 14, 0, 96)
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

local function build()
	for _, c in ipairs(list:GetChildren()) do
		if not c:IsA("UIGridLayout") then c:Destroy() end
	end

	RarityFX.reset()
	buildKeyTile()
	local note = frame:FindFirstChild("EmptyNote")
	if note then note:Destroy() end

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

---------------------------------------------------------------- wiring
local function applySnapshot(snap)
	if typeof(snap) ~= "table" or not snap.Brainrots then return end
	keyCount = math.max(0, math.floor(tonumber(snap.Keys) or 0))
	owned = {}
	for _, e in ipairs(snap.Brainrots) do
		-- only UNPLACED copies live in the backpack; placed ones are on the base
		if not e.PadIndex and e.Uid then
			owned[#owned + 1] = { Name = e.Name, Mutation = e.Mutation, Uid = e.Uid }
		end
	end
	if frame.Visible then build() end
end

local function setOpen(open)
	frame.Visible = open
	if open then
		build()
		-- AutomaticCanvasSize keeps the old scroll offset between openings, so the
		-- grid was opening already scrolled down with the top row cut in half
		list.CanvasPosition = Vector2.new(0, 0)
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
