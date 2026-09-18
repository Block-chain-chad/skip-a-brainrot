-- ToastClient -- the ONLY renderer for {Success, Message} server replies.
-- (BUILD SPEC v2 §7.4, USER DECISION U3)
--
-- Before this script, ClientMain's PurchaseResult/SellResult handlers were empty comment
-- bodies, so every server message in the game was silently discarded. Without a renderer
-- every TryLike rejection string goes nowhere and the like feature cannot be QA'd.
--
-- RemoteEvents support multiple connections, so ClientMain's existing (empty) handlers are
-- harmless and are deliberately left untouched -- zero edits to ClientMain from this file.
--
-- PS99 restyle (field study delta 9, f028/f029): no plates, no cards -- toasts are naked
-- yellow bubble text with a dark-navy Contextual glyph stroke, centered lower-mid screen,
-- max 3 MESSAGES on screen at once (each wrapping to as many rows as its own sentence
-- needs -- see the no-truncate note in push()), newest REPLACES oldest (no scroll
-- animation), ~3.5s life + quick fade.
-- showItemToast() below is a DORMANT "New Item!" tile builder (f002/f038) awaiting
-- item-shaped payloads -- no current remote carries icon/asset/name data.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local MAX_LINES = 3       -- MESSAGES held on screen, not rows of text: one wrapped message
                          -- can occupy several rows and still counts as a single entry
local HOLD = 3.2          -- on-screen life before the fade (PS99 ~3-4s)
local FADE = 0.3
-- LINE_W is a MAXIMUM width (see the stack sizing below) and LINE_H a MINIMUM height
-- (see AutomaticSize in push) -- neither is a fixed rect any more.
local LINE_W, LINE_H = 640, 34

local TEXT_YELLOW = Color3.fromHex("FFE94A")   -- PS99 buff-line yellow
local TEXT_RED = Color3.fromHex("FF6B81")      -- pink-red = negative (failure lines)
local INK_NAVY = Color3.fromHex("313D4F")      -- Contextual glyph ink over the world
local SHOUT_FONT = Enum.Font.LuckiestGuy       -- the game's bubble/Shout face

local screen = Instance.new("ScreenGui")
screen.Name = "ToastGui"
screen.DisplayOrder = 60
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

-- lower-mid screen, grows UPWARD. The 0.78 scale anchor alone landed the lines ON the
-- throw cluster (measured 2026-08-17 at 929x763: toast line Y 516-550 vs charge bar
-- 533-551 and AUTO button top 481 -- "BASE CLAIMED!" printed across the charge bar in
-- the field study). The cluster is a PIXEL-fixed stack (~115px: bar+button+AUTO+gaps)
-- hung from the same 0.78 line, so a -140 pixel offset clears it, with margin, at
-- every viewport size -- scale would only clear it at one aspect.
local stack = Instance.new("Frame")
stack.Name = "Stack"
stack.AnchorPoint = Vector2.new(0.5, 1)
stack.Position = UDim2.new(0.5, 0, 0.78, -140)
-- WIDTH IS A CAP, NOT A FIXED RECT. This was a hard 640px, which is wider than the whole
-- canvas on a handset -- so on a phone the wrapping added below would have had no room to
-- wrap INTO and a long sentence would have run off both edges instead of folding. Scale
-- minus a 32px margin, capped at LINE_W, keeps the authored 640 look on a desktop and
-- keeps every character on screen on a small viewport.
stack.Size = UDim2.new(1, -32, 0, 0)
stack.BackgroundTransparency = 1
stack.AutomaticSize = Enum.AutomaticSize.Y
stack.Parent = screen

local widthCap = Instance.new("UISizeConstraint")
widthCap.MaxSize = Vector2.new(LINE_W, math.huge)   -- Y left free so the stack still auto-grows
widthCap.Parent = stack

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 2)
layout.VerticalAlignment = Enum.VerticalAlignment.Top
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = stack

local live = {}     -- array of active toast lines, oldest first
local seq = 0

-- instant=true is the REPLACE path: a line displaced by a newer one vanishes on the
-- spot with no scroll/fade (PS99 f028/f029); the natural end-of-life path fades out
local function dismiss(entry, instant)
	if entry.dismissed then return end
	entry.dismissed = true
	for i, e in ipairs(live) do
		if e == entry then table.remove(live, i) break end
	end
	if instant then
		entry.line:Destroy()
		return
	end
	local info = TweenInfo.new(FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(entry.line, info, { TextTransparency = 1 }):Play()
	TweenService:Create(entry.stroke, info, { Transparency = 1 }):Play()
	Debris:AddItem(entry.line, FADE + 0.05)
end

local function push(success, message)
	-- REPLACE, not scroll: a 4th line removes the oldest on the spot (PS99 f028/f029)
	while #live >= MAX_LINES do
		dismiss(live[1], true)
	end

	seq += 1
	local line = Instance.new("TextLabel")
	line.Name = "Toast" .. seq
	-- fills the stack, which is the thing carrying the width cap
	line.Size = UDim2.new(1, 0, 0, LINE_H)
	-- AutomaticSize treats the Size above as a MINIMUM on the automatic axis, so a
	-- one-line toast keeps its authored 34px rect and only a longer one grows.
	line.AutomaticSize = Enum.AutomaticSize.Y
	line.BackgroundTransparency = 1
	line.BorderSizePixel = 0
	line.Font = SHOUT_FONT
	line.TextSize = 26
	line.TextColor3 = success and TEXT_YELLOW or TEXT_RED
	line.TextXAlignment = Enum.TextXAlignment.Center
	-- NEVER TRUNCATE A MESSAGE (2026-08-24, owner: "make it say the full sentence and
	-- apply this everywhere"). This file is the ONE renderer for every { Success, Message }
	-- reply in the game -- 50+ producers feed it -- and TextTruncate.AtEnd inside a fixed
	-- 640x34 rect was throwing away exactly the half of the sentence carrying the payload.
	--
	-- Reported against the cellar hatch. ServerScriptService.CellarDoor's refusal measures
	-- 1205px of LuckiestGuy 26 against that 640px single row, so
	--   "\u{1F512} The cellar takes TWO keys. You still need Elder Tung's Cellar Key AND 1
	--    of Gianluca's keys."
	-- arrived as "...You still need" and an ellipsis: the player was told a requirement
	-- existed and never told what it was, and that door is the gate to the entire
	-- underground, so there is nowhere else in the game to read it. NOT cellar-specific --
	-- six of the seven longest messages sampled overflowed the same rect, including the
	-- unlock SUCCESS line and Rocco's wrong-shelf refusal.
	--
	-- Wrapping is what makes the sentence survive; AutomaticSize above is what makes room
	-- for it. The stack is anchored at its BOTTOM edge (AnchorPoint 0.5, 1), so extra rows
	-- push UPWARD into empty screen -- a tall toast can never walk down over the throw
	-- cluster that the -140 offset was measured to clear.
	line.TextTruncate = Enum.TextTruncate.None
	line.TextWrapped = true
	line.Text = message
	line.LayoutOrder = seq
	line:SetAttribute("NoPolish", true)   -- UIPolish must not force this font/colour
	line.Parent = stack

	-- naked bubble text: the ONLY chrome is the Contextual glyph ink (no plate, no box)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Color = INK_NAVY
	stroke.Thickness = 2.8
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = line

	-- quick fade-in on the spot; PS99 lines appear in place, they never slide
	line.TextTransparency = 1
	stroke.Transparency = 1
	local inInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(line, inInfo, { TextTransparency = 0 }):Play()
	TweenService:Create(stroke, inInfo, { Transparency = 0 }):Play()

	local entry = { line = line, stroke = stroke, dismissed = false }
	table.insert(live, entry)

	task.delay(HOLD, function() dismiss(entry) end)
end

----------------------------------------------------------------------------------------
-- DORMANT: "New Item!" tile toasts (PS99 f002/f038 -- yellow outlined label above a
-- colour-coded ~100px rounded tile, queueing horizontally when several arrive).
-- Every wired remote below only ever carries { Success, Message } -- no icon/asset/name
-- fields -- so NOTHING calls this yet. When a producer starts sending item data, wire:
--   showItemToast({ Name = "Golden Rock", Icon = "rbxassetid://...", Rarity = "Rare" })
----------------------------------------------------------------------------------------

local RARITY_TILE_COLORS = {               -- keys lowercased on lookup
	common = Color3.fromHex("9AA7B5"),     -- grey = idle/basic
	uncommon = Color3.fromHex("58C15C"),   -- green
	rare = Color3.fromHex("4FA6FF"),
	epic = Color3.fromHex("A66BFF"),
	legendary = Color3.fromHex("FF8A2B"),  -- orange, NOT gold: gold = real money only
	mythic = Color3.fromHex("FF5C8A"),
	god = Color3.fromHex("7FF6FF"),
}
local NEUTRAL_TILE = Color3.fromHex("647E9C")   -- cool neutral when rarity is unknown

local MAX_TILES = 5
local TILE_SIZE = 100
local TILE_HOLD = 3.6

local itemRow       -- lazy: not built until the first item toast is requested
local liveTiles = {}

local function ensureItemRow()
	if itemRow then return itemRow end
	itemRow = Instance.new("Frame")
	itemRow.Name = "ItemRow"
	itemRow.AnchorPoint = Vector2.new(0.5, 1)
	itemRow.Position = UDim2.new(0.5, 0, 0.62, -150)   -- sits above the text lines (which sit at 0.78 scale -140px -- see the stack note)
	itemRow.Size = UDim2.new(0, 0, 0, TILE_SIZE + 34)
	itemRow.AutomaticSize = Enum.AutomaticSize.X
	itemRow.BackgroundTransparency = 1
	itemRow.Parent = screen
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.VerticalAlignment = Enum.VerticalAlignment.Bottom
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Padding = UDim.new(0, 10)
	row.Parent = itemRow
	return itemRow
end

local function bubbleLabel(text, size)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = SHOUT_FONT
	l.TextSize = size
	l.TextColor3 = TEXT_YELLOW
	l.Text = text
	l:SetAttribute("NoPolish", true)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Color = INK_NAVY
	s.Thickness = 2.5
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = l
	return l
end

-- item = { Name = string?, Icon = "rbxassetid://..."?, Rarity or Family = string? }
local function showItemToast(item)
	if type(item) ~= "table" then return end
	local row = ensureItemRow()
	while #liveTiles >= MAX_TILES do
		local old = table.remove(liveTiles, 1)
		if old then old:Destroy() end
	end

	seq += 1
	local slot = Instance.new("Frame")
	slot.Name = "Item" .. seq
	slot.Size = UDim2.new(0, TILE_SIZE, 0, TILE_SIZE + 34)
	slot.BackgroundTransparency = 1
	slot.LayoutOrder = seq
	slot.Parent = row

	local header = bubbleLabel("New Item!", 20)
	header.Size = UDim2.new(1, 0, 0, 26)
	header.Parent = slot

	local key = string.lower(tostring(item.Rarity or item.Family or ""))
	local family = RARITY_TILE_COLORS[key] or NEUTRAL_TILE

	local tile = Instance.new("Frame")
	tile.Name = "Tile"
	tile.AnchorPoint = Vector2.new(0.5, 1)
	tile.Position = UDim2.new(0.5, 0, 1, 0)
	tile.Size = UDim2.new(0, TILE_SIZE, 0, TILE_SIZE)
	tile.BackgroundColor3 = family:Lerp(Color3.fromHex("1E2733"), 0.45)   -- darkened fill
	tile.BorderSizePixel = 0
	tile.Parent = slot
	local tileCorner = Instance.new("UICorner")
	tileCorner.CornerRadius = UDim.new(0, 14)
	tileCorner.Parent = tile
	local border = Instance.new("UIStroke")
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Color = family                  -- the border carries the family colour
	border.Thickness = 3
	border.Parent = tile

	if type(item.Icon) == "string" and item.Icon ~= "" then
		local icon = Instance.new("ImageLabel")
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.new(1, -12, 1, -12)
		icon.Position = UDim2.new(0, 6, 0, 6)
		icon.Image = item.Icon
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = tile
	elseif type(item.Name) == "string" then
		local nameLabel = bubbleLabel(item.Name, 16)
		nameLabel.Size = UDim2.new(1, -8, 1, -8)
		nameLabel.Position = UDim2.new(0, 4, 0, 4)
		nameLabel.TextWrapped = true
		nameLabel.Parent = tile
	end

	table.insert(liveTiles, slot)
	task.delay(TILE_HOLD, function()
		for i, s in ipairs(liveTiles) do
			if s == slot then table.remove(liveTiles, i) break end
		end
		local info = TweenInfo.new(FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(tile, info, { BackgroundTransparency = 1 }):Play()
		for _, d in ipairs(slot:GetDescendants()) do
			if d:IsA("TextLabel") then
				TweenService:Create(d, info, { TextTransparency = 1 }):Play()
			elseif d:IsA("ImageLabel") then
				TweenService:Create(d, info, { ImageTransparency = 1 }):Play()
			elseif d:IsA("UIStroke") then
				TweenService:Create(d, info, { Transparency = 1 }):Play()
			end
		end
		Debris:AddItem(slot, FADE + 0.05)
	end)
end

-- keep the dormant builder referenced so wiring later is a one-line change and the
-- linter does not flag it; this is NOT a call
local _dormantItemToastBuilder = showItemToast

-- Payload guard: every producer in this game uses { Success = bool, Message = string },
-- but a malformed/absent field must never throw inside a remote handler.
local function show(res)
	if type(res) ~= "table" or type(res.Message) ~= "string" then return end
	push(res.Success == true, res.Message)
end

for _, name in ipairs({ "PurchaseResult", "SellResult", "LikeResult" }) do
	local r = remotes:WaitForChild(name, 10)
	if r then
		r.OnClientEvent:Connect(show)
	else
		warn("[ToastClient] remote missing: " .. name)
	end
end
