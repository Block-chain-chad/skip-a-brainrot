--[[ ==========================================================================
QuestTrackerClient -- the NPC quest tracker down the right-hand side.
---------------------------------------------------------------------------
Shows what an NPC has actually asked you to do, so the objective survives
closing the dialogue box.

LAYOUT: flat log rows, not cards. Each entry is

	[icon] Quest Title
	------------------------------
	Italic blurb from the NPC
	[ ] Objective (0/10)

Square-edged, dark and translucent, with GAP = 0 so stacked entries butt
together and read as ONE continuous panel rather than a column of separate
cards. Rounded corners are deliberately absent for the same reason -- at
zero gap they would show as notches between entries.

NOTE the description line is back. It was removed earlier as "a retelling of
the dialogue", but the reference layout this was matched to has one, so the
blurb per quest is authored in QUESTS below. Drop `Blurb` from an entry and
that row closes up on its own.

TYPOGRAPHY OPT-OUT: this tracker sets NoPolish on its ScreenGui. UIPolish
forces every label under PlayerGui to white FredokaOne AND re-asserts it on
any FontFace/TextColor3 change, so without that attribute the italic greys
here would be silently overwritten a frame after they were set.

Three entries are visible at once; a fourth turns the list into a scroller
rather than growing down the screen. The holder resizes to the number of
visible entries, so a single quest is a single row, not a tall empty box.

A completed quest is REMOVED, with no congratulation hold -- once the state
leaves the Steps table the row goes.

Adding a new NPC quest means adding an entry to QUESTS below and nothing else:
give it the state RemoteEvent it already fires, and a Steps table keyed by the
numeric stage that remote sends. A stage with no Steps entry (not started, or
finished) simply shows no card.

The right edge is deliberate: the top-centre belongs to the teleport tabs, the
top-right to the cash pill, the left to the feature rail, and the bottom-right
to Sprint / Luck. The middle-right band is the only free real estate.
========================================================================== ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIStyle = require(ReplicatedStorage.Modules.UIStyle)
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local P = UIStyle.Palette

-- GAP = 0 on purpose: see the layout note in the header.
local ENTRY_W, ENTRY_H, GAP, MAX_VISIBLE = 286, 72, 0, 3

-- Reference palette: near-black translucent plate, hairline rule, grey italic
-- blurb, near-white objective. Kept here rather than in UIStyle because nothing
-- else in the game uses this log-row language.
local PLATE      = Color3.fromRGB(14, 18, 26)
local PLATE_ALPHA = 0.22
local RULE       = Color3.fromRGB(255, 255, 255)
local RULE_ALPHA = 0.80
local TITLE_INK  = Color3.fromRGB(228, 232, 240)
local BLURB_INK  = Color3.fromRGB(150, 158, 174)
local OBJ_INK    = Color3.fromRGB(240, 244, 250)
local BOX_FILL   = Color3.fromRGB(30, 36, 48)

local QUESTS = {
	{
		Id = "Gianluca",
		Npc = "Stupid Gianluca",
		Remote = "GianlucaState",
		Accent = P.Gold,
		Glyph = "\u{1F50D}",
		Blurb = "Stupid Gianluca wants the Secret Chim found.",
		-- keyed by the State value GianlucaState sends (data.ChimQuest)
		Steps = {
			[1] = { Title = "Find the Secret Chim", Step = 1, Of = 2 },
			[2] = { Title = "Take the Chim back",   Step = 2, Of = 2 },
		},
	},
	{
		Id = "Maxwell",
		Npc = "Maxwell",
		Remote = "MaxwellState",
		Accent = P.Season,
		Glyph = "\u{1F3C6}",
		Blurb = "Maxwell is keeping score. Bring him everything.",
		-- keyed by data.MaxwellQuest. Progress comes LIVE from the payload
		-- (Step/Of), so "3/5" then "12/15" count up without rebuilding the row.
		Steps = {
			[1] = { Title = "Collect every Secret", Step = 0, Of = 11 },
			[2] = { Title = "Reach Rebirth 25",     Step = 0, Of = 25 },
			[3] = { Title = "Claim your prize from Maxwell", Step = 1, Of = 1 },
		},
	},
}

-- Italic is not reachable through Enum.Font, so the family asset is pulled off
-- the enum and rebuilt with an explicit weight + style. pcall'd because a future
-- engine change to Font.new must degrade to a plain font, not break the tracker.
local FAMILY = Font.fromEnum(Enum.Font.GothamMedium).Family
local function face(label, weight, italic, size, colour)
	local ok = pcall(function()
		label.FontFace = Font.new(FAMILY, weight,
			italic and Enum.FontStyle.Italic or Enum.FontStyle.Normal)
	end)
	if not ok then label.Font = Enum.Font.GothamMedium end
	label.TextSize = size
	label.TextColor3 = colour
end

---------------------------------------------------------------- shell
local gui = Instance.new("ScreenGui")
gui.Name = "QuestTrackerUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 4           -- under the rail (6), over MainUI (0)
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets end)
-- see the TYPOGRAPHY OPT-OUT note in the header: without this every label below
-- is rewritten to white FredokaOne by UIPolish, italics and greys included.
gui:SetAttribute("NoPolish", true)
gui.Parent = playerGui

local holder = Instance.new("ScrollingFrame")
holder.Name = "Tracker"
holder.AnchorPoint = Vector2.new(1, 0.5)
holder.Position = UDim2.new(1, -14, 0.40, 0)
holder.Size = UDim2.fromOffset(ENTRY_W + 10, 0)
holder.BackgroundTransparency = 1
holder.BorderSizePixel = 0
holder.ScrollBarThickness = 4
holder.ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255)
holder.ScrollBarImageTransparency = 0.35
holder.CanvasSize = UDim2.new()
holder.AutomaticCanvasSize = Enum.AutomaticSize.Y
holder.ScrollingDirection = Enum.ScrollingDirection.Y
holder.Parent = gui

local list = Instance.new("UIListLayout")
list.FillDirection = Enum.FillDirection.Vertical
list.HorizontalAlignment = Enum.HorizontalAlignment.Left
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Padding = UDim.new(0, GAP)
list.Parent = holder

local cards = {}

-- Last visible count, so refreshHolder can tell "a quest appeared/finished" apart
-- from "a counter ticked". Only the former should move the view.
local lastShown = -1

-- Height follows the number of VISIBLE cards, capped at MAX_VISIBLE. UIListLayout
-- skips Visible=false children, so the canvas already measures only live cards --
-- this just stops the holder itself being a tall invisible box that eats clicks.
local function refreshHolder()
	local n = 0
	for _, ui in ipairs(cards) do
		if ui.root.Visible then n += 1 end
	end
	local shown = math.min(n, MAX_VISIBLE)
	local h = (shown > 0) and (shown * ENTRY_H + (shown - 1) * GAP) or 0
	holder.Size = UDim2.fromOffset(ENTRY_W + 10, h)
	holder.ScrollingEnabled = n > MAX_VISIBLE
	holder.ScrollBarThickness = (n > MAX_VISIBLE) and 4 or 0
	holder.Visible = n > 0

	local contentH = (n > 0) and (n * ENTRY_H + (n - 1) * GAP) or 0
	local maxScroll = math.max(0, contentH - h)

	if n ~= lastShown then
		-- The VISIBLE SET changed, so present from the top. This is not just tidiness:
		-- with AutomaticCanvasSize = Y the engine pins the view to the BOTTOM as the
		-- canvas grows, so the fourth quest appearing scrolled the first one off the
		-- top of the list -- measured CanvasPosition.Y = 72 on a fresh tracker.
		-- It also covers the shrink direction: a finished quest removes a row and
		-- would otherwise strand the view below the remaining content.
		lastShown = n
		holder.CanvasPosition = Vector2.new(0, 0)
	elseif holder.CanvasPosition.Y > maxScroll then
		-- Count unchanged -- this is a progress tick, and the player may have scrolled
		-- deliberately. Leave their position alone beyond keeping it in range.
		holder.CanvasPosition = Vector2.new(0, maxScroll)
	end
end

---------------------------------------------------------------- entry
-- One flat log row. No corners and no keyline: at GAP = 0 the rows have to meet
-- flush or the seams show, which is what makes the stack read as one panel.
local function buildEntry(quest, order)
	local row = Instance.new("Frame")
	row.Name = quest.Id .. "Entry"
	row.Size = UDim2.fromOffset(ENTRY_W, ENTRY_H)
	row.LayoutOrder = order
	row.BackgroundColor3 = PLATE
	row.BackgroundTransparency = PLATE_ALPHA
	row.BorderSizePixel = 0
	row.Visible = false
	row.Parent = holder

	local scale = Instance.new("UIScale")
	scale.Parent = row

	-- icon: small dark tile tinted with the quest accent, holding a glyph
	local box = Instance.new("Frame")
	box.Name = "IconTile"
	box.Size = UDim2.fromOffset(15, 15)
	box.Position = UDim2.fromOffset(10, 7)
	box.BackgroundColor3 = quest.Accent and quest.Accent.dark or BOX_FILL
	box.BorderSizePixel = 0
	box.Parent = row
	UIStyle.corner(box, 3)

	local glyph = Instance.new("TextLabel")
	glyph.Name = "Glyph"
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.BackgroundTransparency = 1
	glyph.Text = quest.Glyph or "\u{2605}"
	glyph.TextScaled = true
	glyph.TextColor3 = Color3.fromRGB(255, 255, 255)
	glyph.Parent = box

	-- title: bold italic, the reference's "Angler Quest" line
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -42, 0, 16)
	title.Position = UDim2.fromOffset(32, 6)
	title.BackgroundTransparency = 1
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Text = quest.Label or ((quest.Npc or "") .. " Quest")
	title.Parent = row
	face(title, Enum.FontWeight.Bold, true, 14, TITLE_INK)

	-- hairline rule under the title
	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.Size = UDim2.new(1, -20, 0, 1)
	rule.Position = UDim2.fromOffset(10, 26)
	rule.BackgroundColor3 = RULE
	rule.BackgroundTransparency = RULE_ALPHA
	rule.BorderSizePixel = 0
	rule.Parent = row

	-- blurb: grey italic flavour line
	local blurb = Instance.new("TextLabel")
	blurb.Name = "Blurb"
	blurb.Size = UDim2.new(1, -20, 0, 15)
	blurb.Position = UDim2.fromOffset(10, 31)
	blurb.BackgroundTransparency = 1
	blurb.TextXAlignment = Enum.TextXAlignment.Left
	blurb.TextTruncate = Enum.TextTruncate.AtEnd
	blurb.Text = quest.Blurb or ""
	blurb.Visible = (quest.Blurb ~= nil)
	blurb.Parent = row
	face(blurb, Enum.FontWeight.Medium, true, 12, BLURB_INK)

	-- objective: checkbox + "<text> (n/m)", progress inline as in the reference
	local tick = Instance.new("Frame")
	tick.Name = "Tick"
	tick.Size = UDim2.fromOffset(11, 11)
	tick.Position = UDim2.fromOffset(12, 51)
	tick.BackgroundColor3 = BOX_FILL
	tick.BorderSizePixel = 0
	tick.Parent = row
	UIStyle.corner(tick, 2)
	UIStyle.stroke(tick, Color3.fromRGB(255, 255, 255), 1)
	local ts = tick:FindFirstChildOfClass("UIStroke")
	if ts then ts.Transparency = 0.55 end

	local obj = Instance.new("TextLabel")
	obj.Name = "Objective"
	obj.Size = UDim2.new(1, -44, 0, 16)
	obj.Position = UDim2.fromOffset(31, 49)
	obj.BackgroundTransparency = 1
	obj.TextXAlignment = Enum.TextXAlignment.Left
	obj.TextTruncate = Enum.TextTruncate.AtEnd
	obj.Parent = row
	face(obj, Enum.FontWeight.Medium, false, 13, OBJ_INK)

	return { root = row, scale = scale, title = title, blurb = blurb, obj = obj }
end

---------------------------------------------------------------- show / hide
-- A gentle settle rather than the old Back-ease pop: a flat log row springing in
-- looked like a card, which is the language this layout moved away from.
local function show(ui)
	if not ui.root.Visible then
		ui.root.Visible = true
		ui.scale.Scale = 0.94
		TweenService:Create(ui.scale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1 }):Play()
	end
	refreshHolder()
end

-- Immediate, by request: a finished quest is simply gone. There is no completion
-- banner and no hold -- the row disappears the moment the state leaves Steps.
local function hide(ui)
	if not ui.root.Visible then return end
	ui.scale.Scale = 1
	ui.root.Visible = false
	refreshHolder()
end

---------------------------------------------------------------- wiring
for order, quest in ipairs(QUESTS) do
	local ui = buildEntry(quest, order)
	cards[#cards + 1] = ui
	local remote = remotes:WaitForChild(quest.Remote, 30)
	if remote then
		remote.OnClientEvent:Connect(function(payload)
			if typeof(payload) ~= "table" then return end
			local state = tonumber(payload.State) or 0
			local step = quest.Steps[state]

			-- No completion branch by design. Any state without a Steps entry -- not
			-- started, finished, or anything added later -- hides the row, so a quest
			-- vanishes the instant it is done.
			if not step then
				hide(ui)
				return
			end

			-- payload may carry live progress (Step/Of); fall back to the static config
			local sNum = tonumber(payload.Step) or step.Step
			local sOf  = tonumber(payload.Of) or step.Of
			ui.obj.Text = ("%s (%d/%d)"):format(step.Title, sNum, sOf)
			show(ui)
		end)
	end
end

refreshHolder()

-- Real NPC questlines are added to the QUESTS table above -- each one driven by
-- its own state RemoteEvent. The temporary local test quests that used to live
-- here (Marco / Rocco / Enzo / Gino / Test Five) were placeholders and have been
-- removed; the tracker scroller stays and will populate once real quests exist.
