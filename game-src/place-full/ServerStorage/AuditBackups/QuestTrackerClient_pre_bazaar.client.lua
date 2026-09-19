--[[ ==========================================================================
QuestTrackerClient -- the QUEST LOG: a docked panel of active NPC quests that
collapses to a thin vertical rail.
---------------------------------------------------------------------------
Rebuilt 2026-08-12 to the "Quest Log HUD" design handoff. The old presentation
(flat 286x72 log rows, GAP = 0, no collapse) is in
ServerStorage.AuditBackups.QuestTrackerClient_pre_questlog.

WHAT CAME FROM THE HANDOFF, and what could not:

  * The card's left-edge bar is GREEN when a quest is tracked and RED when it is not
    (owner call). The handoff specified accent/dead-brown there; see the trackOn note
    in the colour table for why it became a status light instead.
  * Hard corners everywhere (radius 0), the amber accent, the serif-display /
    mono-label contrast, and every colour token are reproduced exactly.
  * FONTS ARE SUBSTITUTED. Cinzel / IBM Plex Sans / IBM Plex Mono are Google
    fonts and Roblox cannot load them, so this uses the nearest built-ins:
    Merriweather (serif display), Gotham (body), RobotoMono (meta labels). The
    handoff explicitly allows this as long as the serif/mono contrast survives.
  * LETTER-SPACING DOES NOT EXIST on a Roblox TextLabel. The tracked caps
    labels are spaced by inserting real spaces between characters (`spaced`),
    which is the only mechanism available.
  * NO backdrop blur and NO drop shadow: Roblox has neither for Frames. The
    panel uses the specified fill at its specified alpha.
  * VERTICAL TEXT for the rail label is one TextLabel per character stacked by
    a UIListLayout -- there is no writing-mode.

THE COLLAPSE IS THE ONE THE GAME ALREADY HAD. `questsHidden` is a real
persisted setting (SettingsService whitelists it; HudToggleClient writes it via
SettingsSave), and it used to mean "slide the tracker off the right edge". It
now means "show the rail instead of the panel", which is the handoff's
behaviour -- the state, the save and HudToggleClient's button are unchanged, so
a saved preference carries straight over and the HUD button still works.

TRACKING WITHOUT A JOURNAL. The handoff pairs the tracker with a quest-journal
modal whose TRACK QUEST button owns the `tracked` flag. That modal is not built
(the game has no per-quest description, rewards or location to fill it with), so
CLICKING A CARD TOGGLES TRACKED here instead. That keeps the three tabs, the
accent bar and the rail badge all meaning what the handoff says they mean.

DONE is inferred, not configured: a quest's Steps table is keyed by stage, so a
state ABOVE the highest key is finished and a state below the lowest is one not
started yet. That needs no extra data per quest and cannot drift.

TYPOGRAPHY OPT-OUT: this tracker sets NoPolish on its ScreenGui. UIPolish forces
every label under PlayerGui to white FredokaOne AND re-asserts it on any
FontFace/TextColor3 change.

Adding a new NPC quest is still one entry in QUESTS below and nothing else.
========================================================================== ]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TundraQuestConfig = require(ReplicatedStorage.Modules:WaitForChild("TundraQuestConfig"))
local MichelQuestConfig = require(ReplicatedStorage.Modules:WaitForChild("MichelQuestConfig"))
local Platform = require(ReplicatedStorage.Modules:WaitForChild("Platform"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local saveRemote = remotes:WaitForChild("SettingsSave")

---------------------------------------------------------------- design tokens
local C = {
	panelBg    = Color3.fromRGB(16, 14, 13),
	borderSub  = Color3.fromRGB(42, 37, 31),
	borderPan  = Color3.fromRGB(50, 44, 37),
	borderCard = Color3.fromRGB(69, 60, 49),
	borderRail = Color3.fromRGB(91, 78, 61),
	borderBtn  = Color3.fromRGB(56, 49, 42),
	borderBtnH = Color3.fromRGB(107, 92, 71),
	hoverFill  = Color3.fromRGB(29, 26, 22),
	-- WHITE, ALL OF IT (owner call). The handoff's cream/tan ink was replaced with the
	-- game's white so the panel matches every other label in the experience. The
	-- hierarchy the tan tones used to carry is now carried by TextTransparency instead
	-- (see DIM below) -- still white, just quieter, rather than a different colour.
	textPri    = Color3.fromRGB(255, 255, 255),
	textCard   = Color3.fromRGB(255, 255, 255),
	textSec    = Color3.fromRGB(255, 255, 255),
	textRail   = Color3.fromRGB(255, 255, 255),
	textMuted  = Color3.fromRGB(255, 255, 255),
	textMut2   = Color3.fromRGB(255, 255, 255),
	textFaint  = Color3.fromRGB(255, 255, 255),
	textFain2  = Color3.fromRGB(255, 255, 255),
	glyphInk   = Color3.fromRGB(255, 255, 255),
	trackBg    = Color3.fromRGB(36, 31, 26),
	barIdle    = Color3.fromRGB(58, 51, 42),
	-- THE TRACKED BAR IS A STATUS LIGHT, NOT AN ACCENT (owner call, 2026-08-12).
	-- The handoff used the amber accent for a tracked quest and a dead brown for an
	-- untracked one, which reads as "emphasised / not emphasised". Green and red read as
	-- ON and OFF, which is what the bar actually means -- and it is the one control on
	-- the card, so it should say plainly which state a click just put you in. Values are
	-- UITheme.Palette's own green1/red2, so it matches every other yes/no in the game.
	trackOn    = Color3.fromRGB(96, 222, 128),
	trackOff   = Color3.fromRGB(220, 60, 54),
	accent     = Color3.fromRGB(216, 162, 74),
	railBadge  = Color3.fromRGB(20, 18, 15),
}
local PANEL_ALPHA = 0.10
local RAIL_ALPHA  = 0.14

-- THE HOUSE FONT, NOT THE HANDOFF'S (owner call, 2026-08-12: "change the font to the
-- font we use on everything else"). The handoff asked for Cinzel + IBM Plex Mono and
-- explicitly allowed substituting the game's own faces; the game's own face is the one
-- UIPolish force-sets on every label in the experience, so all three roles collapse onto
-- it. Text is WHITE for the same reason -- see the WHITE note in the colour table.
local FONT_DISPLAY = Enum.Font.FredokaOne
local FONT_BODY    = Enum.Font.FredokaOne
local FONT_MONO    = Enum.Font.FredokaOne

-- How far the secondary text is knocked back now that everything is the same white.
local DIM = { meta = 0.42, step = 0.22, tabIdle = 0.42, chevron = 0.3 }

-- YOU MAY TRACK THREE. The tracked set is the thing the rail badge counts and the thing
-- TRACKED filters to, so leaving it unbounded made both of them meaningless once a few
-- questlines were live -- "tracked" ended up meaning "exists".
local MAX_TRACKED = 3

-- MAX_LIST IS DELIBERATELY SHORTER THAN THE PANEL COULD BE (320, was 460). The list is a
-- ScrollingFrame, and a cap taller than the content means it never scrolls -- the panel
-- just grew and ALL was a wall of cards. At 320 the list holds about three cards and
-- anything beyond that scrolls under the mouse wheel, which is what ALL is for.
local PANEL_W, RAIL_W, MAX_LIST, RIGHT_PAD = 348, 52, 320, 18
-- "a tad bit smaller" (owner, 2026-08-12). Applied as one factor on the existing device
-- UIScale rather than by re-tuning thirty offsets, so the whole panel keeps its authored
-- proportions and this is a single number to dial if it wants another nudge.
local SIZE_TRIM = 0.85
-- The panel hangs from TOP_Y and grows DOWNWARD, so a long quest list walked straight
-- into the bottom-right cluster (Sprint, bag, and the daily/luck chips). TOP_Y itself
-- cannot simply be raised -- 264 already sits directly under the goals bar (190..252).
-- So the LIST gets clamped instead: whatever is left between the panel's header and the
-- reserved strip at the bottom of the screen, and it scrolls past that.
-- Measured live rather than guessed: the bottom-right cluster is HudToggle, the Luck
-- chip and Sprint, stacked from the bottom in FIXED pixels (they occupied y 364..502 on
-- a 518-tall window). So the reserve is in RENDERED pixels, not authored units -- an
-- authored reserve would shrink with the device scale exactly when space is tightest.
local BOTTOM_RESERVE_PX = 165
-- One compact card. Measured against a 1530x518 window, which is the tightest case the
-- panel has to survive: at 110 the panel could not shrink enough to clear the HUD toggle
-- and it sat 18px into it.
local MIN_LIST = 78
-- On a short window even the header cannot fit below TOP_Y, so the panel is allowed to
-- slide UP toward the goals bar. It stops at 200: above that it would cover the weather
-- pill (72..110) and the cash pill.
local TOP_Y_FLOOR = 150
-- Below the cash pill (12..58), the weather pill (72..110) and the goals bar
-- (QuestBarClient, 190..252). The handoff's top:88 assumes an empty screen.
local TOP_Y = 264

---------------------------------------------------------------- quests
-- Kind drives the tag colour: MAIN = accent, SIDE = #8B8171, ERRAND = #6D6558.
local QUESTS = {
	{
		Id = "Gianluca", Npc = "Stupid Gianluca", Remote = "GianlucaState", Kind = "MAIN",
		Steps = {
			[1] = { Title = "Catch the Secret Chim", Step = 1, Of = 2 },
			[2] = { Title = "Take the Chim back",    Step = 2, Of = 2 },
		},
	},
	{
		Id = "Maxwell", Npc = "Maxwell", Remote = "MaxwellState", Kind = "MAIN",
		Steps = {
			[1] = { Title = "Collect every Secret", Step = 0, Of = 11 },
			[2] = { Title = "Reach Rebirth 25",     Step = 0, Of = 25 },
			[3] = { Title = "Claim your prize from Maxwell", Step = 1, Of = 1 },
		},
	},
	{
		Id = "Tung", Npc = "Elder Tung", Remote = "TungState", Kind = "SIDE",
		Steps = {
			[1] = { Title = "Deliver brainrots to Tung", Step = 0, Of = 12 },
			[2] = { Title = "Finish the list with Tung", Step = 0, Of = 12 },
		},
		-- Tung's quota is three per-rarity counts, which one n/m cannot describe.
		-- Have is the DELIVERED count, capped server-side; math.min is belt-and-braces.
		Objective = function(payload)
			local t = payload and payload.Tiers
			if not t then return nil end
			local bits = {}
			for _, tier in ipairs({ "Epic", "Legendary", "Mythic" }) do
				local e = t[tier]
				if e then
					local need = e.Need or 0
					bits[#bits + 1] = ("%s %d/%d"):format(tier, math.min(e.Have or 0, need), need)
				end
			end
			if #bits == 0 then return nil end
			return table.concat(bits, ", ")
		end,
	},
	{
		Id = "TundraCave", Npc = "Elder Tung", Remote = "TundraState", Kind = "MAIN",
		-- Built FROM the config, not retyped: stages carry their own titles.
		Steps = (function()
			local t = {}
			for i, s in ipairs(TundraQuestConfig.Stages) do
				t[i] = { Title = s.Title, Step = 0, Of = (s.Kind == "count" and s.Target) or 1 }
			end
			return t
		end)(),
		-- three shapes of objective in one arc, composed from what the payload carries
		Objective = function(payload)
			if type(payload.Parts) == "table" and #payload.Parts > 0 then
				local bits = {}
				for _, p in ipairs(payload.Parts) do
					bits[#bits + 1] = ("%s %d/%d"):format(p.Plural or p.Label or p.Id, p.Have or 0, p.Need or 0)
				end
				return table.concat(bits, ", ")
			end
			local track = payload.Track
			if type(track) ~= "string" then return nil end
			if track:find("%%d") then
				local ok, line = pcall(string.format, track, tonumber(payload.Step) or 0, tonumber(payload.Of) or 0)
				if ok then return line end
				return nil
			end
			return track
		end,
	},
	{
		-- Id is an internal key; he is "Michael" everywhere the player reads him.
		Id = "Michel", Npc = "Michael", Remote = "MichelState", Kind = "ERRAND",
		Steps = {
			[1] = { Title = "Bring Michael mutated Sahurs", Step = 0, Of = MichelQuestConfig.Count },
			[2] = { Title = "Finish the " .. MichelQuestConfig.QuestLabel, Step = 0, Of = MichelQuestConfig.Count },
		},
	},
}

-- highest stage each quest defines, so "state above this" == finished
for _, q in ipairs(QUESTS) do
	local top = 0
	for stage in pairs(q.Steps) do
		if stage > top then top = stage end
	end
	q.TopStage = top
end

local KIND_INK = { MAIN = C.accent, SIDE = C.textMut2, ERRAND = C.textFain2 }

---------------------------------------------------------------- helpers
-- The only letter-spacing Roblox offers. Short uppercase labels ONLY.
local function spaced(s)
	local out = {}
	for _, ch in utf8.codes(s) do table.insert(out, utf8.char(ch)) end
	return table.concat(out, " ")
end

local function px(n) return UDim2.fromOffset(n, n) end

local function stroke(obj, colour, thickness)
	local s = Instance.new("UIStroke")
	s.Color = colour
	s.Thickness = thickness or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = obj
	return s
end

local function pad(obj, t, r, b, l)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, t)
	p.PaddingRight = UDim.new(0, r)
	p.PaddingBottom = UDim.new(0, b)
	p.PaddingLeft = UDim.new(0, l)
	p.Parent = obj
	return p
end

local function text(parent, str, font, size, colour, xAlign)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Text = str
	l.Font = font
	l.TextSize = size
	l.TextColor3 = colour
	l.TextXAlignment = xAlign or Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Parent = parent
	return l
end

local function tweenColour(obj, prop, colour, seconds)
	TweenService:Create(obj, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ [prop] = colour }):Play()
end

-- 140ms on small controls, 150ms on cards, 160ms on the rail border
local function hoverTint(button, apply, restore, seconds)
	local t = seconds or 0.14
	button.MouseEnter:Connect(function() apply(t) end)
	button.MouseLeave:Connect(function() restore(t) end)
end

---------------------------------------------------------------- state
local limitFlashUntil = 0      -- while > os.clock(), the header shows the cap warning
local collapsed = false        -- mirrors the persisted `questsHidden` setting
local tab = "TRACKED"          -- TRACKED | ALL | DONE
local userTouched = false
local live = {}                -- [questId] = { title, objective, step, of, done }
-- An EXPLICIT set, not "everything except these". With a cap of three, defaulting to
-- tracked would have every quest in breach the moment a fourth questline went live, and
-- there is no sensible way to choose which three to drop after the fact. Quests are
-- auto-tracked as they arrive instead, while there is still room (see the wiring below).
local trackedOn = {}           -- [questId] = true

local function isTracked(id) return trackedOn[id] == true end

local function visibleList()
	local out = {}
	for _, q in ipairs(QUESTS) do
		local e = live[q.Id]
		if e then
			local ok
			if tab == "TRACKED" then ok = isTracked(q.Id) and not e.done
			elseif tab == "ALL" then ok = not e.done
			else ok = e.done end
			if ok then table.insert(out, { quest = q, entry = e }) end
		end
	end
	return out
end

local function trackedCount()
	local n = 0
	for _, q in ipairs(QUESTS) do
		local e = live[q.Id]
		if e and not e.done and isTracked(q.Id) then n += 1 end
	end
	return n
end

local function completedCount()
	local n = 0
	for _, q in ipairs(QUESTS) do
		local e = live[q.Id]
		if e and e.done then n += 1 end
	end
	return n
end

---------------------------------------------------------------- shell
local gui = Instance.new("ScreenGui")
gui.Name = "QuestTrackerUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 4           -- under the rail (6), over MainUI (0)
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets end)
gui:SetAttribute("NoPolish", true)
gui.Parent = playerGui

-- Anchored top-right so the panel grows DOWN and leftwards; the gap to the
-- screen edge stays constant whatever it is scaled to. HudToggleClient reads
-- this frame by name ("Tracker") to anchor its quest button.
local root = Instance.new("Frame")
root.Name = "Tracker"
root.AnchorPoint = Vector2.new(1, 0)
root.Position = UDim2.new(1, -RIGHT_PAD, 0, TOP_Y)
root.Size = UDim2.fromOffset(PANEL_W, 0)
root.AutomaticSize = Enum.AutomaticSize.Y
root.BackgroundTransparency = 1
root.Parent = gui

local scale = Instance.new("UIScale")
scale.Name = "DeviceScale"
scale.Parent = root
Platform.Watch(function() scale.Scale = Platform.Widget() * SIZE_TRIM end)

---------------------------------------------------------------- panel
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(PANEL_W, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = C.panelBg
panel.BackgroundTransparency = PANEL_ALPHA
panel.BorderSizePixel = 0
panel.Parent = root
stroke(panel, C.borderPan, 1)

local panelList = Instance.new("UIListLayout")
panelList.FillDirection = Enum.FillDirection.Vertical
panelList.SortOrder = Enum.SortOrder.LayoutOrder
panelList.Parent = panel

-- ===== header =====
local header = Instance.new("Frame")
header.Name = "Header"
header.LayoutOrder = 1
header.Size = UDim2.new(1, 0, 0, 46)
header.BackgroundTransparency = 1
header.BorderSizePixel = 0
header.Parent = panel

local headerRule = Instance.new("Frame")
headerRule.AnchorPoint = Vector2.new(0, 1)
headerRule.Position = UDim2.new(0, 0, 1, 0)
headerRule.Size = UDim2.new(1, 0, 0, 1)
headerRule.BackgroundColor3 = C.borderSub
headerRule.BorderSizePixel = 0
headerRule.Parent = header

local hTitle = text(header, spaced("QUEST LOG"), FONT_DISPLAY, 14, C.textSec)
hTitle.Position = UDim2.fromOffset(16, 0)
hTitle.Size = UDim2.fromOffset(150, 46)

local hCount = text(header, "", FONT_MONO, 10, C.textFaint)
hCount.Position = UDim2.fromOffset(168, 0)
hCount.Size = UDim2.fromOffset(118, 46)
hCount.TextTransparency = DIM.meta

local collapseBtn = Instance.new("TextButton")
collapseBtn.Name = "Collapse"
collapseBtn.AnchorPoint = Vector2.new(1, 0.5)
collapseBtn.Position = UDim2.new(1, -16, 0.5, 0)
collapseBtn.Size = px(26)
collapseBtn.BackgroundTransparency = 1
collapseBtn.BorderSizePixel = 0
collapseBtn.Text = "\u{203A}"
collapseBtn.Font = FONT_MONO
collapseBtn.TextSize = 12
collapseBtn.TextColor3 = C.glyphInk
collapseBtn.AutoButtonColor = false
collapseBtn.Parent = header
local collapseStroke = stroke(collapseBtn, C.borderBtn, 1)

-- ===== tabs =====
local tabsRow = Instance.new("Frame")
tabsRow.Name = "Tabs"
tabsRow.LayoutOrder = 2
tabsRow.Size = UDim2.new(1, 0, 0, 37)
tabsRow.BackgroundTransparency = 1
tabsRow.BorderSizePixel = 0
tabsRow.Parent = panel
pad(tabsRow, 10, 12, 0, 12)

local tabsLayout = Instance.new("UIListLayout")
tabsLayout.FillDirection = Enum.FillDirection.Horizontal
tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabsLayout.Padding = UDim.new(0, 2)
tabsLayout.Parent = tabsRow

local tabButtons = {}
for i, name in ipairs({ "TRACKED", "ALL", "DONE" }) do
	local b = Instance.new("TextButton")
	b.Name = name
	b.LayoutOrder = i
	b.Size = UDim2.new(1 / 3, -2, 1, 0)
	b.BackgroundTransparency = 1
	b.BorderSizePixel = 0
	b.Text = spaced(name)
	b.Font = FONT_MONO
	b.TextSize = 10
	b.TextColor3 = C.textMut2
	b.AutoButtonColor = false
	b.Parent = tabsRow

	local base = Instance.new("Frame")
	base.Name = "Baseline"
	base.AnchorPoint = Vector2.new(0, 1)
	base.Position = UDim2.new(0, 0, 1, 0)
	base.Size = UDim2.new(1, 0, 0, 1)
	base.BackgroundColor3 = C.borderSub
	base.BorderSizePixel = 0
	base.Parent = b

	local underline = Instance.new("Frame")
	underline.Name = "Underline"
	underline.AnchorPoint = Vector2.new(0, 1)
	underline.Position = UDim2.new(0, 0, 1, 0)
	underline.Size = UDim2.new(1, 0, 0, 1)
	underline.BackgroundColor3 = C.accent
	underline.BorderSizePixel = 0
	underline.Visible = false
	underline.ZIndex = 2
	underline.Parent = b

	tabButtons[name] = { button = b, underline = underline }
end

-- ===== list =====
local listWrap = Instance.new("ScrollingFrame")
listWrap.Name = "List"
listWrap.LayoutOrder = 3
listWrap.Size = UDim2.new(1, 0, 0, 0)
listWrap.BackgroundTransparency = 1
listWrap.BorderSizePixel = 0
listWrap.ScrollBarThickness = 3
listWrap.ScrollBarImageColor3 = C.textFain2
listWrap.ScrollBarImageTransparency = 0.2
listWrap.CanvasSize = UDim2.new()
listWrap.AutomaticCanvasSize = Enum.AutomaticSize.Y
listWrap.ScrollingDirection = Enum.ScrollingDirection.Y
listWrap.Parent = panel
pad(listWrap, 12, 12, 12, 12)

local cardsLayout = Instance.new("UIListLayout")
cardsLayout.FillDirection = Enum.FillDirection.Vertical
cardsLayout.SortOrder = Enum.SortOrder.LayoutOrder
cardsLayout.Padding = UDim.new(0, 8)
cardsLayout.Parent = listWrap

local emptyLabel = text(listWrap, spaced("NOTHING HERE YET"), FONT_MONO, 11, C.textFain2,
	Enum.TextXAlignment.Center)
emptyLabel.Name = "Empty"
emptyLabel.Size = UDim2.new(1, 0, 0, 56)
emptyLabel.TextTransparency = DIM.meta
emptyLabel.Visible = false
emptyLabel.LayoutOrder = 999

-- ===== footer =====
local footer = Instance.new("Frame")
footer.Name = "Footer"
footer.LayoutOrder = 4
footer.Size = UDim2.new(1, 0, 0, 34)
footer.BackgroundTransparency = 1
footer.BorderSizePixel = 0
footer.Parent = panel

local footerRule = Instance.new("Frame")
footerRule.Size = UDim2.new(1, 0, 0, 1)
footerRule.BackgroundColor3 = C.borderSub
footerRule.BorderSizePixel = 0
footerRule.Parent = footer

local fLeft = text(footer, spaced("J \u{00B7} TOGGLE"), FONT_MONO, 10, C.textFain2)
fLeft.Position = UDim2.fromOffset(16, 0)
fLeft.Size = UDim2.fromOffset(160, 34)
fLeft.TextTransparency = DIM.meta

local fRight = text(footer, "", FONT_MONO, 10, C.textFain2, Enum.TextXAlignment.Right)
fRight.AnchorPoint = Vector2.new(1, 0)
fRight.Position = UDim2.new(1, -16, 0, 0)
fRight.Size = UDim2.fromOffset(160, 34)
fRight.TextTransparency = DIM.meta

---------------------------------------------------------------- rail
local rail = Instance.new("TextButton")
rail.Name = "Rail"
rail.AnchorPoint = Vector2.new(1, 0)
rail.Position = UDim2.new(1, 0, 0, 0)
rail.Size = UDim2.fromOffset(RAIL_W, 0)
rail.AutomaticSize = Enum.AutomaticSize.Y
rail.BackgroundColor3 = C.panelBg
rail.BackgroundTransparency = RAIL_ALPHA
rail.BorderSizePixel = 0
rail.Text = ""
rail.AutoButtonColor = false
rail.Visible = false
rail.Parent = root
local railStroke = stroke(rail, C.borderPan, 1)
pad(rail, 16, 0, 20, 0)

local railList = Instance.new("UIListLayout")
railList.FillDirection = Enum.FillDirection.Vertical
railList.HorizontalAlignment = Enum.HorizontalAlignment.Center
railList.SortOrder = Enum.SortOrder.LayoutOrder
railList.Padding = UDim.new(0, 18)
railList.Parent = rail

local railBadge = Instance.new("TextLabel")
railBadge.Name = "Badge"
railBadge.LayoutOrder = 1
railBadge.Size = px(24)
railBadge.BackgroundColor3 = C.accent
railBadge.BorderSizePixel = 0
railBadge.Text = "0"
railBadge.Font = FONT_MONO
railBadge.TextSize = 11
railBadge.TextColor3 = C.railBadge
railBadge.Parent = rail

-- writing-mode: vertical-rl has no equivalent, so this is one label per glyph
local railLabel = Instance.new("Frame")
railLabel.Name = "Label"
railLabel.LayoutOrder = 2
railLabel.Size = UDim2.new(0, RAIL_W, 0, 0)
railLabel.AutomaticSize = Enum.AutomaticSize.Y
railLabel.BackgroundTransparency = 1
railLabel.Parent = rail

local railLabelList = Instance.new("UIListLayout")
railLabelList.FillDirection = Enum.FillDirection.Vertical
railLabelList.HorizontalAlignment = Enum.HorizontalAlignment.Center
railLabelList.SortOrder = Enum.SortOrder.LayoutOrder
railLabelList.Padding = UDim.new(0, 4)   -- stands in for the 0.34em tracking
railLabelList.Parent = railLabel

do
	local i = 0
	for _, ch in utf8.codes("QUEST LOG") do
		i += 1
		local glyph = utf8.char(ch)
		local l = text(railLabel, glyph == " " and "" or glyph, FONT_DISPLAY, 12, C.textRail,
			Enum.TextXAlignment.Center)
		l.LayoutOrder = i
		l.Size = UDim2.new(1, 0, 0, glyph == " " and 6 or 13)
	end
end

local railChevron = text(rail, "\u{2039}", FONT_MONO, 11, C.textMut2, Enum.TextXAlignment.Center)
railChevron.Name = "Chevron"
railChevron.LayoutOrder = 3
railChevron.Size = UDim2.new(1, 0, 0, 14)
railChevron.TextTransparency = DIM.chevron

---------------------------------------------------------------- cards
local cardUi = {}

local function buildCard(quest, order)
	local card = Instance.new("TextButton")
	card.Name = quest.Id .. "Card"
	card.LayoutOrder = order
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = C.hoverFill
	card.BackgroundTransparency = 1
	card.BorderSizePixel = 0
	card.Text = ""
	card.AutoButtonColor = false
	card.Visible = false
	card.Parent = listWrap
	local cardStroke = stroke(card, C.borderSub, 1)
	pad(card, 12, 12, 13, 15)

	-- 2px accent bar on the left edge, backed out through the padding
	local accentBar = Instance.new("Frame")
	accentBar.Name = "Accent"
	accentBar.Position = UDim2.new(0, -15, 0, -12)
	accentBar.Size = UDim2.new(0, 2, 1, 25)
	accentBar.BackgroundColor3 = C.accent
	accentBar.BorderSizePixel = 0
	accentBar.ZIndex = 2
	accentBar.Parent = card

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.BackgroundTransparency = 1
	body.Parent = card

	local bodyList = Instance.new("UIListLayout")
	bodyList.FillDirection = Enum.FillDirection.Vertical
	bodyList.SortOrder = Enum.SortOrder.LayoutOrder
	bodyList.Parent = body

	local titleRow = Instance.new("Frame")
	titleRow.Name = "TitleRow"
	titleRow.LayoutOrder = 1
	titleRow.Size = UDim2.new(1, 0, 0, 0)
	titleRow.AutomaticSize = Enum.AutomaticSize.Y
	titleRow.BackgroundTransparency = 1
	titleRow.Parent = body

	local kindTag = Instance.new("TextLabel")
	kindTag.Name = "Kind"
	kindTag.AnchorPoint = Vector2.new(1, 0)
	kindTag.Position = UDim2.new(1, 0, 0, 0)
	kindTag.AutomaticSize = Enum.AutomaticSize.X
	kindTag.Size = UDim2.fromOffset(0, 17)
	kindTag.BackgroundTransparency = 1
	kindTag.BorderSizePixel = 0
	kindTag.Text = spaced(quest.Kind)
	kindTag.Font = FONT_MONO
	kindTag.TextSize = 9
	kindTag.TextColor3 = KIND_INK[quest.Kind] or C.textMut2
	kindTag.Parent = titleRow
	pad(kindTag, 3, 7, 3, 7)
	local kindStroke = stroke(kindTag, KIND_INK[quest.Kind] or C.textMut2, 1)
	kindStroke.Transparency = 0.67          -- the handoff's <kindColor>55 alpha

	local title = text(titleRow, "", FONT_DISPLAY, 14, C.textCard)
	title.Name = "Title"
	title.Size = UDim2.new(1, -84, 0, 0)
	title.AutomaticSize = Enum.AutomaticSize.Y
	title.TextWrapped = true
	title.TextYAlignment = Enum.TextYAlignment.Top
	title.LineHeight = 1.35

	local stepLine = text(body, "", FONT_BODY, 12, C.textMuted)
	stepLine.Name = "Step"
	stepLine.LayoutOrder = 2
	stepLine.Size = UDim2.new(1, 0, 0, 0)
	stepLine.AutomaticSize = Enum.AutomaticSize.Y
	stepLine.TextWrapped = true
	stepLine.TextYAlignment = Enum.TextYAlignment.Top
	stepLine.LineHeight = 1.5
	local stepPad = Instance.new("UIPadding")
	stepPad.PaddingTop = UDim.new(0, 8)
	stepPad.Parent = stepLine
	stepLine.TextTransparency = DIM.step

	local progRow = Instance.new("Frame")
	progRow.Name = "Progress"
	progRow.LayoutOrder = 3
	progRow.Size = UDim2.new(1, 0, 0, 13)
	progRow.BackgroundTransparency = 1
	progRow.Parent = body
	local progPad = Instance.new("UIPadding")
	progPad.PaddingTop = UDim.new(0, 10)
	progPad.Parent = progRow

	local trackBar = Instance.new("Frame")
	trackBar.Name = "Track"
	trackBar.AnchorPoint = Vector2.new(0, 0.5)
	trackBar.Position = UDim2.new(0, 0, 0.5, 0)
	trackBar.Size = UDim2.new(1, -46, 0, 3)
	trackBar.BackgroundColor3 = C.trackBg
	trackBar.BorderSizePixel = 0
	trackBar.Parent = progRow

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = C.accent
	fill.BorderSizePixel = 0
	fill.Parent = trackBar

	local progLabel = text(progRow, "", FONT_MONO, 10, C.textFaint, Enum.TextXAlignment.Right)
	progLabel.Name = "Label"
	progLabel.AnchorPoint = Vector2.new(1, 0.5)
	progLabel.Position = UDim2.new(1, 0, 0.5, 0)
	progLabel.Size = UDim2.fromOffset(40, 13)
	progLabel.TextTransparency = DIM.meta

	hoverTint(card, function(t)
		TweenService:Create(card, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 0 }):Play()
		tweenColour(cardStroke, "Color", C.borderCard, t)
	end, function(t)
		TweenService:Create(card, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }):Play()
		tweenColour(cardStroke, "Color", C.borderSub, t)
	end, 0.15)

	return { root = card, accent = accentBar, title = title, step = stepLine,
		fill = fill, progress = progLabel }
end

---------------------------------------------------------------- render
local function renderTabs()
	for name, t in pairs(tabButtons) do
		local active = (name == tab)
		t.underline.Visible = active
		-- every tab is the same white now, so the active one is the SOLID one
		t.button.TextTransparency = active and 0 or DIM.tabIdle
	end
end

local function relayout()
	-- MIND THE UNITS. AbsoluteContentSize is in RENDERED pixels (the device scale and the
	-- size trim have already been applied to it), while MAX_LIST and the Size we write are
	-- authored offsets that get scaled afterwards. Comparing the two directly made the
	-- effective cap MAX_LIST / scale -- about 376 instead of 320 at the current trim -- so
	-- the list ran taller than intended and ALL still did not scroll.
	local s = (scale.Scale > 0) and scale.Scale or 1
	local content = (cardsLayout.AbsoluteContentSize.Y / s) + 24   -- + 12px padding each side

	-- Room left below the header, in AUTHORED units (same units as MAX_LIST). The chrome
	-- above the list -- header, tabs, paddings -- is measured rather than guessed:
	-- panel height minus list height is invariant no matter what we set the list to, so
	-- reading last frame's values here is stable, and on the very first pass the list is
	-- still 0 tall which makes the subtraction exactly the chrome.
	local viewH = gui.AbsoluteSize.Y
	local chrome = (panel.AbsoluteSize.Y - listWrap.AbsoluteSize.Y) / s
	if chrome <= 0 or chrome ~= chrome then chrome = 130 end

	-- UNITS. root.Position is an offset on the ROOT, which sits OUTSIDE the DeviceScale,
	-- so topY is in real pixels. chrome/content/MAX_LIST are authored units INSIDE that
	-- scale, so they only become pixels after multiplying by s. Mixing the two left the
	-- panel 3px into the cluster, so every comparison below is done in PIXELS.
	local floorPx = viewH - BOTTOM_RESERVE_PX          -- panel bottom must not pass this
	local topY = TOP_Y
	local needPx = (chrome + MIN_LIST) * s
	if topY + needPx > floorPx then
		topY = math.max(TOP_Y_FLOOR, floorPx - needPx)
	end
	root.Position = UDim2.new(1, -RIGHT_PAD, 0, topY)

	-- room left for the list, converted back into authored units for listWrap.Size
	local room = ((floorPx - topY) / s) - chrome
	local capped = math.min(content, MAX_LIST, math.max(MIN_LIST, room))

	listWrap.Size = UDim2.new(1, 0, 0, capped)
	listWrap.ScrollingEnabled = content > capped
	listWrap.ScrollBarThickness = (content > capped) and 3 or 0
end

gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	-- the clamp above is viewport-dependent, so it has to be recomputed on resize
	pcall(relayout)
end)

local function render()
	local shown = visibleList()
	local seen = {}
	for i, item in ipairs(shown) do
		seen[item.quest.Id] = true
		local ui, e = cardUi[item.quest.Id], item.entry
		ui.root.Visible = true
		ui.root.LayoutOrder = i
		ui.title.Text = e.title
		ui.step.Text = e.objective
		ui.accent.BackgroundColor3 = isTracked(item.quest.Id) and C.trackOn or C.trackOff
		local pct = (e.of > 0) and math.clamp(e.step / e.of, 0, 1) or 0
		ui.fill.Size = UDim2.new(pct, 0, 1, 0)
		ui.progress.Text = ("%d/%d"):format(e.step, e.of)
	end
	for id, ui in pairs(cardUi) do
		if not seen[id] then ui.root.Visible = false end
	end

	emptyLabel.Visible = (#shown == 0)
	if os.clock() < limitFlashUntil then
		-- a refusal has to read as a refusal, so this one transient line is red rather
		-- than the panel's white. It reverts on the next render after 1.8s.
		hCount.Text = spaced(("TRACK %d MAX"):format(MAX_TRACKED))
		hCount.TextColor3 = C.trackOff
		hCount.TextTransparency = 0
	else
		hCount.Text = ("%d %s"):format(#shown, #shown == 1 and "ENTRY" or "ENTRIES")
		hCount.TextColor3 = C.textFaint
		hCount.TextTransparency = DIM.meta
	end
	fRight.Text = spaced(("%d COMPLETED"):format(completedCount()))
	railBadge.Text = tostring(trackedCount())
	renderTabs()
	relayout()
end

---------------------------------------------------------------- collapse
local function applyCollapsed()
	panel.Visible = not collapsed
	rail.Visible = collapsed
	root.Size = UDim2.fromOffset(collapsed and RAIL_W or PANEL_W, 0)
	if not collapsed then
		-- the handoff's mount animation: fade + 6px rise, 180ms ease-out
		panel.Position = UDim2.fromOffset(0, 6)
		TweenService:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(0, 0) }):Play()
	end
end

local function setCollapsed(v, save)
	collapsed = v and true or false
	applyCollapsed()
	if save then
		userTouched = true
		saveRemote:FireServer({ questsHidden = collapsed })
	end
end

collapseBtn.Activated:Connect(function() setCollapsed(true, true) end)
rail.Activated:Connect(function() setCollapsed(false, true) end)

hoverTint(collapseBtn, function(t)
	tweenColour(collapseStroke, "Color", C.borderBtnH, t)
	collapseBtn.TextColor3 = C.textPri
end, function(t)
	tweenColour(collapseStroke, "Color", C.borderBtn, t)
	collapseBtn.TextColor3 = C.glyphInk
end)

hoverTint(rail, function(t) tweenColour(railStroke, "Color", C.borderRail, t) end,
	function(t) tweenColour(railStroke, "Color", C.borderPan, t) end, 0.16)

ContextActionService:BindAction("QuestLogToggle", function(_, state)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	setCollapsed(not collapsed, true)
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.J)

---------------------------------------------------------------- tabs
for name, t in pairs(tabButtons) do
	t.button.Activated:Connect(function()
		tab = name
		render()
	end)
	hoverTint(t.button, function()
		if tab ~= name then t.button.TextTransparency = 0.15 end
	end, function()
		if tab ~= name then t.button.TextTransparency = DIM.tabIdle end
	end)
end

---------------------------------------------------------------- wiring
for order, quest in ipairs(QUESTS) do
	cardUi[quest.Id] = buildCard(quest, order)
	-- stands in for the journal's TRACK QUEST button (see the header note)
	cardUi[quest.Id].root.Activated:Connect(function()
		if isTracked(quest.Id) then
			trackedOn[quest.Id] = nil
		elseif trackedCount() >= MAX_TRACKED then
			-- REFUSE rather than silently dropping someone else's quest. Which one to
			-- evict is a decision only the player can make, so say no and let them.
			limitFlashUntil = os.clock() + 1.8
			task.delay(1.85, render)
		else
			trackedOn[quest.Id] = true
		end
		render()
	end)

	local remote = remotes:WaitForChild(quest.Remote, 30)
	if remote then
		remote.OnClientEvent:Connect(function(payload)
			if typeof(payload) ~= "table" then return end
			local state = tonumber(payload.State) or 0
			local step = quest.Steps[state]

			if not step then
				-- above the highest authored stage = finished, and it stays in the log
				-- for the DONE tab; below the lowest = never started, so not an entry
				if state > quest.TopStage then
					local prev = live[quest.Id]
					live[quest.Id] = {
						title = (prev and prev.title) or quest.Npc,
						objective = "All objectives complete",
						step = (prev and prev.of) or 1,
						of = (prev and prev.of) or 1,
						done = true,
					}
				else
					live[quest.Id] = nil
				end
				render()
				return
			end

			local sNum = tonumber(payload.Step) or step.Step
			local sOf  = tonumber(payload.Of) or step.Of
			local custom
			if type(quest.Objective) == "function" then
				local ok, res = pcall(quest.Objective, payload, step)
				if ok and type(res) == "string" then custom = res end
			end

			local isNew = (live[quest.Id] == nil)
			live[quest.Id] = {
				title = step.Title,
				objective = custom or ("%s  %d/%d"):format(step.Title, sNum, sOf),
				step = sNum, of = sOf, done = false,
			}
			-- auto-track it while there is room, so a player who never touches a card
			-- still has their first three quests tracked rather than an empty TRACKED tab
			if isNew and trackedCount() < MAX_TRACKED then trackedOn[quest.Id] = true end
			render()
		end)
	end
end

---------------------------------------------------------------- saved preference
-- FOLLOW THE SERVER UNTIL THE PLAYER TAKES OVER -- the same latch HudToggleClient
-- uses, and for the same reason: the first DataUpdated of a session can arrive
-- before the profile has finished loading, carrying a default Settings table, so
-- latching onto the first snapshot brings a saved collapse up expanded.
local dataRemote = remotes:WaitForChild("DataUpdated")
dataRemote.OnClientEvent:Connect(function(snap)
	if userTouched then return end
	if typeof(snap) ~= "table" then return end
	local st = snap.Settings
	if typeof(st) ~= "table" then return end
	local want = (st.questsHidden == true)
	if want ~= collapsed then setCollapsed(want, false) end
end)

cardsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(relayout)

-- BOOT SAFETY NET. SideRail owns this ScreenGui's `Enabled` -- it hides the tracker while
-- any rail panel is open and restores it on close (SideRail.updateRailVisibility). That is
-- correct and this does not fight it. What it DOES catch is a STALE disable: on a fresh
-- session the tracker came up Enabled = false with no panel open and the nav rail plainly
-- visible, and because SideRail only re-runs that function on an open/close signal,
-- nothing ever turned it back on -- the whole quest log stayed invisible until some
-- unrelated panel happened to be opened and closed again.
--
-- One shot, a few seconds after boot, and only while the nav rail is showing -- which is
-- SideRail's own "nothing is open" tell -- so a genuinely open panel is left alone.
task.delay(4, function()
	if gui.Enabled then return end
	local hud = playerGui:FindFirstChild("GameHUD")
	local canvas = hud and hud:FindFirstChild("Canvas")
	local chrome = (canvas and canvas:FindFirstChild("Chrome")) or (hud and hud:FindFirstChild("Chrome"))
	local railFrame = chrome and chrome:FindFirstChild("NavRail")
	if railFrame and railFrame.Visible then gui.Enabled = true end
end)

applyCollapsed()
render()
