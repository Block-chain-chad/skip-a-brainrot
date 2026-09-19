--[[ ==========================================================================
QuestTrackerClient -- the tracked NPC quests, as compact adventure objectives.
---------------------------------------------------------------------------
UI ROUND 3 (2026-09-19). The "Quest Log" (tabs, a letter-ladder rail, outlined
text floating on the world, a 3px cyan line for progress) is retired; the file
before this one is ServerStorage.AuditBackups.PreUIRound3_2026_09_19.

WHAT IT IS NOW. A short stack of UIKit.QuestCard cards at the middle-right --
NPC badge, quest name, ONE objective, a chunky bar with the numbers on it, and a
state chip when the real server state says "go back to him" / "claim" / "done".
Desktop shows as many WHOLE cards as the room between the Goals bar and the
bottom-right control column takes (up to three) and a "+N MORE" pill in the
header past that; a phone shows one card and a "1 / 3" pill that cycles.
Collapsed (the persisted `questsHidden` setting, the J key, the header chevron,
or a tap on a card) keeps only the objective and the bar.

WHAT DID NOT CHANGE, because other scripts lean on it:
  * QUESTS below is still the whole data model: one table entry per questline,
    each read through the same three payload keys (State / Step / Of) plus an
    optional Objective(payload) composer. Adding an NPC is one entry.
  * `questsHidden` is the same persisted setting (SettingsService whitelists
    it; HudToggleClient writes it too and folds the Goals bar on it), J toggles
    it, the ScreenGui is still "QuestTrackerUI" and the root frame "Tracker"
    (HudToggleClient reads both).
  * SideRail owns this ScreenGui's `Enabled` while a rail panel is open.
  * The bottom-reserve clamp: the stack never runs into the bottom-right
    control column (HIDE UI / RIDE / Luck / Sprint).

SERVER TRUTH ONLY. A card only says RETURN / CLAIM / COMPLETE when the payload
says so (see the `kind` per stage and the Ready/Met/Done flags); progress only
moves when Step moves. Nothing here fakes a beat.

WHOLE CARDS, MEASURED. QuestCard.measure() says how tall a card will be from
the same props that draw it, so render() fits whole cards to the room it has
and the list never cuts one at its edge. No second layout pass, no hidden
holders.

PERFORMANCE. Event driven: renders on the state remotes, on the collapse
toggles and on device changes. The only animation is TweenService on Size /
Position (fill, pop, slide-in) and two task.delay beats for the completion.
No RenderStepped, no Heartbeat, no viewports.
========================================================================== ]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local modules = ReplicatedStorage:WaitForChild("Modules")
local UIKit = modules:WaitForChild("UIKit")
local PC = require(UIKit:WaitForChild("PanelChrome"))
local S = require(UIKit:WaitForChild("SpecTheme"))
local QuestCard = require(UIKit:WaitForChild("QuestCard"))
local Platform = require(modules:WaitForChild("Platform"))
local HudLayout = require(modules:WaitForChild("HudLayout"))
local TundraQuestConfig = require(modules:WaitForChild("TundraQuestConfig"))
local MichelQuestConfig = require(modules:WaitForChild("MichelQuestConfig"))
local okSound, SoundKit = pcall(function() return require(modules:WaitForChild("SoundKit")) end)
if not okSound then SoundKit = nil end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local saveRemote = remotes:WaitForChild("SettingsSave")

---------------------------------------------------------------- geometry
local CARD_W = QuestCard.WIDTH
local HEADER_H = 30
local CARD_GAP = 8
local RIGHT_PAD = 18
-- How far in from the right edge. On touch the right edge is the jump button's
-- corner band, so the stack sits inside Platform.TouchCorner(); desktop keeps 18.
local function rightPad(): number
	if Platform.IsTouch then return Platform.TouchCorner() + 12 end
	return RIGHT_PAD
end
-- DESKTOP: below the cash pill (12..58), the weather pill (72..110) and the
-- Goals bar (QuestBarClient, 165..227). The stack climbs from TOP_Y when the
-- room below is short, but never above TOP_Y_FLOOR -- the Goals bar's slot.
local TOP_Y = 264
local TOP_Y_FLOOR = 240
-- The bottom-right column, in RENDERED pixels: HudToggle's HIDE UI sits 262
-- above the bottom edge on desktop (RIDE / Luck / Sprint stacked under it),
-- plus the 12px gap rightPad uses. Re-swept 2026-09-19 (929x784 and 1891x785
-- viewports: column top at viewH-262 on both).
local BOTTOM_RESERVE_PX = 274
-- PHONE (iPhone 16 sim, 733x371, measured 2026-09-19): the control column is
-- at the TOP right there (HIDE UI / RIDE / Sprint, y -2..162) with the Goals
-- bar under it (QuestBarClient: TOP_OFFSET 165, 62 tall at Widget scale), so
-- the stack starts under the Goals bar and runs to the bottom edge, x inside
-- the jump band. The throw cluster (MainUI.ThrowFrame) rises into that lane
-- while the player is at the water, so the phone stack yields to it -- see the
-- watcher at the bottom. A SHORT phone (Platform.IsShortPhone, < 340 tall) has
-- no lane left under the Goals bar at all, so the stack stays away there --
-- the same call the previous tracker made for its rail.
local GOALS_BAR_TOP, GOALS_BAR_H = 165, 62
local function phoneTopY(s: number): number
	return GOALS_BAR_TOP + math.ceil(GOALS_BAR_H * s) + 8
end
local PHONE_BOTTOM_PAD = 8
local CARD_H_FALLBACK = 121            -- before any card is measured: head + objective + chip
local MAX_SCROLL = 500                 -- a "SHOW ALL" list scrolls past this
local MAX_SHOW_DESKTOP = 3

---------------------------------------------------------------- NPC identity
-- The reusable input the cards take. Accents are the SAME pairs each NPC's
-- dialogue ribbon already wears (GianlucaClient / CatDialogueClient /
-- TungQuestClient / MichelQuestConfig), so the card and the conversation are
-- recognisably the same character. Icons are IconArt keys that exist today --
-- nothing here is an uploaded asset id.
local NPC = {
	Gianluca = { name = "Gianluca",   initial = "G", accent = { Color3.fromRGB(255, 216, 96), Color3.fromRGB(238, 148, 24) }, icon = "keyGianluca" },
	Maxwell  = { name = "Maxwell",    initial = "M", accent = { Color3.fromRGB(226, 150, 226), Color3.fromRGB(146, 68, 168) }, icon = "crown" },
	Tung     = { name = "Elder Tung", initial = "T", accent = { Color3.fromRGB(198, 150, 96),  Color3.fromRGB(146, 98, 54) },  icon = "keyCellar" },
	TungIce  = { name = "Elder Tung", initial = "T", accent = { Color3.fromRGB(198, 150, 96),  Color3.fromRGB(146, 98, 54) },  icon = "bolt" },
	Michel   = { name = "Michael",    initial = "M", accent = { Color3.fromRGB(226, 176, 62),  Color3.fromRGB(196, 146, 48) },  icon = "tag" },
}

---------------------------------------------------------------- quests
-- One entry per questline. Steps are keyed by the server's State number; a
-- State above the highest key means finished, below the lowest means not
-- started. Each step carries:
--   Title      the quest name on the card
--   Objective  the one line under it (may hold %d/%d, which the card strips --
--              the bar carries the numbers)
--   Kind       "objective" (a bar), "return" (RETURN TO <npc>), "claim"
--              (CLAIM FROM <npc>) -- what the chip says, from the stage alone
--   Step/Of    fallbacks when the payload carries no numbers
-- `Objective(payload, step)` composes a richer line from the payload (Tung's
-- per-tier counts, Tundra's parts); `KindOf(payload, step)` lets a payload flag
-- (Tung/Michael `Ready`, Tundra `Met`) upgrade a stage to RETURN live.
local QUESTS = {
	{
		Id = "Gianluca", Npc = NPC.Gianluca, Remote = "GianlucaState",
		Steps = {
			[1] = { Title = "The Secret Chim", Objective = "Find the Secret Chim", Kind = "objective", HasProgress = false },
			[2] = { Title = "The Secret Chim", Objective = "Take the Chim back to Gianluca", Kind = "return", HasProgress = false },
		},
	},
	{
		Id = "Maxwell", Npc = NPC.Maxwell, Remote = "MaxwellState",
		Steps = {
			[1] = { Title = "Maxwell's Secret", Objective = "Collect every Secret brainrot", Kind = "objective", Step = 0, Of = 11 },
			[2] = { Title = "Maxwell's Secret", Objective = "Reach Rebirth 25", Kind = "objective", Step = 0, Of = 25 },
			[3] = { Title = "Maxwell's Secret", Objective = "Claim your prize from Maxwell", Kind = "claim", HasProgress = false },
		},
	},
	{
		Id = "Tung", Npc = NPC.Tung, Remote = "TungState",
		Steps = {
			[1] = { Title = "The Cellar Key", Objective = "Hand brainrots over to Elder Tung", Kind = "objective", Step = 0, Of = 12 },
			[2] = { Title = "The Cellar Key", Objective = "You are holding the rest \u{2014} finish the list", Kind = "return", Step = 0, Of = 12 },
		},
		-- three per-rarity counts in one line; Have is the DELIVERED count, capped server-side
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
			return table.concat(bits, "  \u{00B7}  ")
		end,
	},
	{
		Id = "TundraCave", Npc = NPC.TungIce, Remote = "TundraState",
		-- built FROM the config: stages carry their own titles, tracks and kinds
		Steps = (function()
			local t = {}
			for i, s in ipairs(TundraQuestConfig.Stages) do
				t[i] = {
					Title = s.Title, Objective = s.Track or s.Title,
					Kind = (s.Kind == "talk") and "return" or "objective",
					HasProgress = (s.Kind ~= "talk"),
					Step = 0, Of = (s.Kind == "count" and s.Target) or (s.Kind == "gather" and TundraQuestConfig.PartTotal) or 1,
				}
			end
			return t
		end)(),
		Objective = function(payload, step)
			if type(payload.Parts) == "table" and #payload.Parts > 0 then
				local bits = {}
				for _, p in ipairs(payload.Parts) do
					bits[#bits + 1] = ("%s %d/%d"):format(p.Plural or p.Label or p.Id, p.Have or 0, p.Need or 0)
				end
				return table.concat(bits, "  \u{00B7}  ")
			end
			return nil
		end,
		-- a counter stage the server already counts as met is a visit away from done
		KindOf = function(payload, step)
			if step.Kind == "objective" and payload.Met == true then return "return" end
			return step.Kind
		end,
	},
	{
		Id = "Michel", Npc = NPC.Michel, Remote = "MichelState",
		Steps = {
			[1] = { Title = "Eagles Quest", Objective = "Bring Michael mutated Tung Tung Tung Sahurs", Kind = "objective", Step = 0, Of = MichelQuestConfig.Count },
			[2] = { Title = "Eagles Quest", Objective = "You are holding the rest \u{2014} finish the hand-over", Kind = "return", Step = 0, Of = MichelQuestConfig.Count },
		},
	},
}

for _, q in ipairs(QUESTS) do
	local top = 0
	for stage in pairs(q.Steps) do
		if stage > top then top = stage end
	end
	q.TopStage = top
end

-- "Catch %d/%d brainrots in the Frozen Tundra" -> "Catch brainrots in the
-- Frozen Tundra": the bar carries the numbers, the line carries the verb.
local function stripCounts(text: string): string
	local s = text:gsub("%s*%%d%s*/%s*%%d%s*", " ")
	s = s:gsub("%s+", " ")
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

---------------------------------------------------------------- state
local live = {}                  -- [questId] = { title, objective, current, required, hasProgress, kind, done, completing }
local cards = {}                 -- [questId] = { card, holder }
local collapsed = Platform.IsPhone
local userTouched = false
local expanded = {}              -- [questId] = true: a tap opened this card while collapsed
local showAll = false            -- desktop "+N MORE" pressed
local phoneIndex = 1             -- which quest the single phone card shows
local firstCardH = CARD_H_FALLBACK   -- measured height of the card at the top of the stack
local throwUp = false            -- phone: the throw cluster owns the lane right now
local render                     -- forward

---------------------------------------------------------------- shell
local gui = Instance.new("ScreenGui")
gui.Name = "QuestTrackerUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 4           -- under the rail (6) and under MainUI (5): gameplay controls win their pixels
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets end)
gui:SetAttribute("NoPolish", true)
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Tracker"
root.AnchorPoint = Vector2.new(1, 0)
root.Position = UDim2.new(1, -rightPad(), 0, TOP_Y)
root.Size = UDim2.fromOffset(CARD_W, 0)
root.AutomaticSize = Enum.AutomaticSize.Y
root.BackgroundTransparency = 1
root.Visible = false             -- nothing to track yet
root.Parent = gui

local scale = Instance.new("UIScale")
scale.Name = "DeviceScale"
scale.Parent = root
Platform.Watch(function() scale.Scale = Platform.Widget() end)

local rootList = Instance.new("UIListLayout")
rootList.FillDirection = Enum.FillDirection.Vertical
rootList.SortOrder = Enum.SortOrder.LayoutOrder
rootList.Padding = UDim.new(0, 6)
rootList.Parent = root

-- A tap target that clears Roblox's 44px floor ON THE GLASS whatever scale the
-- stack wears (0.6 on a phone would leave a 44-authored pad at 26px). Same
-- pattern as QuestBarClient's DismissHit and the scooter card. Desktop keeps
-- the control's own footprint.
local function touchPad(parent: GuiObject, name: string, z: number): TextButton
	local hit = Instance.new("TextButton")
	hit.Name = name
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.AnchorPoint = Vector2.new(0.5, 0.5)
	hit.Position = UDim2.fromScale(0.5, 0.5)
	hit.ZIndex = z
	hit.Parent = parent
	Platform.Watch(function()
		if not Platform.IsTouch then
			hit.Size = UDim2.fromScale(1, 1)
			return
		end
		local s = math.max(Platform.Widget(), 0.01)
		local need = math.ceil(HudLayout.MIN_TOUCH / s)
		hit.Size = UDim2.fromOffset(math.max(need, parent.Size.X.Offset), math.max(need, parent.Size.Y.Offset))
	end)
	return hit
end

-- ===== header: "QUESTS" + the more/next pill + the collapse chevron =====
local header = Instance.new("Frame")
header.Name = "Header"
header.LayoutOrder = 1
header.Size = UDim2.new(1, 0, 0, HEADER_H)
header.BackgroundTransparency = 1
header.Parent = root

local hTitle = PC.shout({
	name = "Title", text = "QUESTS", size = 17, color = Color3.new(1, 1, 1), strokeColor = S.Outline,
	align = Enum.TextXAlignment.Left,
	frameSize = UDim2.new(0, 0, 1, 0), position = UDim2.fromOffset(8, 0),
	zIndex = 6, parent = header,
})
hTitle.AutomaticSize = Enum.AutomaticSize.X   -- the word's own width, not the row's (HudAudit footprint)

local chevron = PC.plate({
	name = "Collapse",
	size = UDim2.fromOffset(28, 28),
	position = UDim2.new(1, -2, 0.5, 0), anchor = Vector2.new(1, 0.5),
	colors = { S.Surface.RowTop, S.Surface.RowBottom }, radius = 10, outline = 3, strokeColor = S.Outline,
	zIndex = 6, parent = header, gloss = false,
})
local chevronGlyph = PC.shout({ name = "Glyph", text = "\u{25BE}", size = 16, color = S.Surface.ReadInk, strokeColor = Color3.new(1, 1, 1), zIndex = 8, parent = chevron })
local chevronHit = touchPad(chevron, "CollapseHit", 9)
PC.bindPressFeedback(chevronHit)

-- "+2 MORE" / "SHOW FEWER" on desktop, "1 / 3  >" on a phone: the affordance for
-- the quests that are not on screen lives in the header, so it never costs the
-- stack a row (a phone has ~95px on the glass for the whole thing).
local morePill = PC.button({
	kind = "secondary", text = "+1 MORE", name = "More",
	size = UDim2.fromOffset(104, 26), textSize = 13, radius = 10, outline = 3,
	zIndex = 6, parent = header,
})
morePill.AnchorPoint = Vector2.new(1, 0.5)
-- 18 clear of the chevron so the two touch pads (44px on the glass each) do
-- not overlap at phone scale
morePill.Position = UDim2.new(1, -(28 + 18), 0.5, 0)
morePill.Visible = false
local moreHit = touchPad(morePill, "MoreHit", 9)

-- ===== list =====
local listWrap = Instance.new("ScrollingFrame")
listWrap.Name = "List"
listWrap.LayoutOrder = 2
listWrap.Size = UDim2.new(1, 0, 0, 0)
listWrap.BackgroundTransparency = 1
listWrap.BorderSizePixel = 0
listWrap.ScrollBarThickness = 0
listWrap.CanvasSize = UDim2.new()
listWrap.AutomaticCanvasSize = Enum.AutomaticSize.Y
listWrap.ScrollingDirection = Enum.ScrollingDirection.Y
listWrap.ElasticBehavior = Enum.ElasticBehavior.Never
listWrap.Parent = root

local cardsLayout = Instance.new("UIListLayout")
cardsLayout.FillDirection = Enum.FillDirection.Vertical
cardsLayout.SortOrder = Enum.SortOrder.LayoutOrder
cardsLayout.Padding = UDim.new(0, CARD_GAP)
cardsLayout.Parent = listWrap

---------------------------------------------------------------- helpers
local function typeScale(): number
	return Platform.IsPhone and 1.35 or 1
end

-- RETURN / CLAIM first (something to do right now), then the rest in table order
local function priority(e): number
	if e.completing then return 0 end
	if e.kind == "return" or e.kind == "claim" then return 1 end
	return 2
end

local function activeList()
	local out = {}
	for _, q in ipairs(QUESTS) do
		local e = live[q.Id]
		if e and (not e.done or e.completing) then
			table.insert(out, { quest = q, entry = e })
		end
	end
	table.sort(out, function(a, b)
		local pa, pb = priority(a.entry), priority(b.entry)
		if pa ~= pb then return pa < pb end
		return a.entry.order < b.entry.order
	end)
	return out
end

local function playSound(key: string, volume: number)
	if not SoundKit then return end
	pcall(function() SoundKit.play(key, nil, { volume = volume }) end)
end

-- The props one card draws from -- shared by the build, the repaint and the
-- measure so all three agree. A phone card with a chip drops its bar: the chip
-- already says the stage is done, and the phone's lane is ~95px on the glass.
local function cardProps(q, e)
	local hasProgress = e.hasProgress
	if Platform.IsPhone and (e.kind == "return" or e.kind == "claim" or e.kind == "complete") then
		hasProgress = false
	end
	-- a card is a button (tap = expand): on touch it may never render under
	-- Roblox's 44px floor, whatever scale the stack wears
	local minHeight = 0
	if Platform.IsTouch then
		minHeight = math.ceil(HudLayout.MIN_TOUCH / math.max(Platform.Widget(), 0.01))
	end
	return {
		title = e.title, objective = e.objective,
		current = e.current, required = e.required, hasProgress = hasProgress,
		kind = e.kind, returnTo = q.Npc.name,
		compact = collapsed and not expanded[q.Id] and not e.completing,
		typeScale = typeScale(), minHeight = minHeight,
	}
end

---------------------------------------------------------------- cards
-- Each card sits in a holder so a NEW card can slide in (the holder is what the
-- list lays out; the card's own Position tweens inside it).
local function ensureCard(quest, entry)
	local rec = cards[quest.Id]
	if rec then return rec end
	local holder = Instance.new("Frame")
	holder.Name = quest.Id .. "Holder"
	holder.Size = UDim2.new(1, 0, 0, 0)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.BackgroundTransparency = 1
	holder.Parent = listWrap
	local props = cardProps(quest, entry)
	props.name = quest.Id .. "Card"
	props.parent = holder
	props.zIndex = 5
	props.npc = quest.Npc
	local card = QuestCard.new(props)
	-- the arrival: 26px in from the right with a Back ease, once
	card.root.Position = UDim2.fromOffset(26, 0)
	TweenService:Create(card.root, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(0, 0) }):Play()
	card.Activated:Connect(function()
		-- a tap opens a collapsed card (or folds an open one) for this session
		if expanded[quest.Id] then expanded[quest.Id] = nil else expanded[quest.Id] = true end
		userTouched = true
		render()
	end)
	rec = { card = card, holder = holder, order = entry.order }
	cards[quest.Id] = rec
	return rec
end

local function dropCard(id: string)
	local rec = cards[id]
	if not rec then return end
	cards[id] = nil
	-- leave the way it came: out to the right, then gone
	local tw = TweenService:Create(rec.card.root, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromOffset(CARD_W + 40, 0) })
	tw.Completed:Connect(function() rec.holder:Destroy() end)
	tw:Play()
end

---------------------------------------------------------------- layout clamp
-- Authored px the list may use between the stack's top and the reserve at the
-- bottom, and the y the stack starts at. A pure function of the viewport and
-- the measured top card, so render can decide HOW MANY cards fit before
-- anything is built (a card cut in half by a list edge is what this avoids).
local function listRoom(): (number, number)
	local s = (scale.Scale > 0) and scale.Scale or 1
	local viewH = Platform.Viewport.Y - Platform.Insets().Top
	local chrome = HEADER_H + 6
	local floorPx, topY
	if Platform.IsPhone then
		floorPx = viewH - PHONE_BOTTOM_PAD
		topY = phoneTopY(s)
	else
		floorPx = viewH - BOTTOM_RESERVE_PX
		topY = TOP_Y
		-- at least ONE whole card always fits: the stack climbs (down to
		-- TOP_Y_FLOOR) before it would ever cut a card at the reserve line
		local needPx = (chrome + firstCardH) * s
		if topY + needPx > floorPx then
			topY = math.max(TOP_Y_FLOOR, floorPx - needPx)
		end
	end
	return ((floorPx - topY) / s) - chrome, topY
end

local function relayout()
	local s = (scale.Scale > 0) and scale.Scale or 1
	local content = cardsLayout.AbsoluteContentSize.Y / s
	local room, topY = listRoom()
	root.Position = UDim2.new(1, -rightPad(), 0, topY)
	-- the normal stack is sized to the whole cards render() chose; only a
	-- "SHOW ALL" list is allowed to be taller than the room, and it scrolls.
	-- A phone's one card can outgrow its lane (a two-line objective plus a
	-- chip): there the list stays inside the lane and scrolls instead.
	local cap = Platform.IsPhone and math.max(room, 40) or math.max(room, firstCardH)
	if showAll then cap = math.min(MAX_SCROLL, cap) end
	local capped = math.min(content, cap)
	-- +2 authored px: the content comes back fractional once the device scale
	-- has been divided out, and a list floored a pixel short of its card shaves
	-- the card's bottom stroke (seen on the phone sim: list 41, card 42.1)
	listWrap.Size = UDim2.new(1, 0, 0, math.ceil(capped) + 2)
	local scrolls = content > capped + 1
	listWrap.ScrollingEnabled = scrolls
	listWrap.ScrollBarThickness = scrolls and 3 or 0
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() pcall(relayout) end)
cardsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() pcall(relayout) end)
Platform.Watch(function() pcall(relayout) end)

local function applyVisible(n: number)
	root.Visible = n > 0 and not (Platform.IsPhone and (throwUp or Platform.IsShortPhone()))
end

---------------------------------------------------------------- render
render = function()
	local list = activeList()
	local n = #list
	applyVisible(n)
	if n == 0 then
		for id in pairs(cards) do dropCard(id) end
		morePill.Visible = false
		return
	end
	if phoneIndex > n then phoneIndex = 1 end

	-- heights first: the fit below and the climb in listRoom both need them
	local heights = {}
	for i, item in ipairs(list) do
		heights[i] = QuestCard.measure(cardProps(item.quest, item.entry))
	end
	firstCardH = (Platform.IsPhone and heights[phoneIndex]) or heights[1] or CARD_H_FALLBACK

	-- which of them are on screen: as many WHOLE cards as the room allows, up to
	-- three on desktop, one on a phone; the rest go behind the pill
	local shown = {}
	if Platform.IsPhone then
		table.insert(shown, list[phoneIndex])
	else
		local maxShow = MAX_SHOW_DESKTOP
		if not showAll then
			local room = listRoom()
			local used, fit = 0, 0
			for i = 1, math.min(n, maxShow) do
				local need = used + ((fit > 0) and CARD_GAP or 0) + heights[i]
				if need > room and fit > 0 then break end
				used, fit = need, fit + 1
			end
			maxShow = fit
		end
		for i, item in ipairs(list) do
			if showAll or i <= maxShow then table.insert(shown, item) end
		end
	end

	local seen = {}
	for i, item in ipairs(shown) do
		local q, e = item.quest, item.entry
		seen[q.Id] = true
		local rec = ensureCard(q, e)
		rec.holder.LayoutOrder = i
		local props = cardProps(q, e)
		rec.card.set(props, e.animate == true)
		e.animate = false
		rec.card.setCompact(props.compact)
	end
	for id in pairs(cards) do
		if not seen[id] then dropCard(id) end
	end

	-- header
	chevronGlyph.Text = collapsed and "\u{25B8}" or "\u{25BE}"
	local lbl = morePill:FindFirstChild("Label")
	if Platform.IsPhone then
		morePill.Visible = n > 1
		if lbl then lbl.Text = string.format("%d / %d  \u{25B8}", phoneIndex, n) end
	else
		local hidden = n - #shown
		morePill.Visible = (hidden > 0) or (showAll and n > 1)
		if lbl then
			if showAll then lbl.Text = "SHOW FEWER" else lbl.Text = string.format("+%d MORE", hidden) end
		end
	end
	relayout()
end

moreHit.Activated:Connect(function()
	if Platform.IsPhone then
		phoneIndex += 1
	else
		showAll = not showAll
	end
	userTouched = true
	render()
end)

---------------------------------------------------------------- collapse
local function setCollapsed(v: boolean, save: boolean)
	collapsed = v and true or false
	table.clear(expanded)
	if save then
		userTouched = true
		saveRemote:FireServer({ questsHidden = collapsed })
	end
	render()
end
chevronHit.Activated:Connect(function() setCollapsed(not collapsed, true) end)
ContextActionService:BindAction("QuestLogToggle", function(_, state)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	setCollapsed(not collapsed, true)
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.J)

---------------------------------------------------------------- wiring
for order, quest in ipairs(QUESTS) do
	local remote = remotes:WaitForChild(quest.Remote, 30)
	if remote then
		remote.OnClientEvent:Connect(function(payload)
			if typeof(payload) ~= "table" then return end
			local state = tonumber(payload.State) or 0
			local step = quest.Steps[state]
			local prev = live[quest.Id]

			if not step then
				if state > quest.TopStage then
					-- FINISHED. If the card is on screen, play the beat; otherwise
					-- (finished before this session, or never shown) there is
					-- nothing to dismiss.
					if prev and not prev.done and cards[quest.Id] then
						prev.done = true
						prev.completing = true
						prev.kind = "complete"
						playSound("wheelWin", 0.35)
						cards[quest.Id].card.playComplete(function()
							prev.completing = false
							if live[quest.Id] == prev then live[quest.Id] = nil end
							render()
						end, 1.2)
						render()
					else
						live[quest.Id] = nil
						render()
					end
				else
					live[quest.Id] = nil
					render()
				end
				return
			end

			local current = tonumber(payload.Step) or step.Step or 0
			local required = tonumber(payload.Of) or step.Of or 1
			local hasProgress = step.HasProgress ~= false and required > 0
			local kind = step.Kind or "objective"
			if type(quest.KindOf) == "function" then
				local ok, k = pcall(quest.KindOf, payload, step)
				if ok and type(k) == "string" then kind = k end
			end
			-- Tung / Michael: the server's own "everything owed is in hand" flag
			if payload.Ready == true and kind == "objective" then kind = "return" end

			local objective = stripCounts(step.Objective or step.Title or "")
			if type(quest.Objective) == "function" then
				local ok, res = pcall(quest.Objective, payload, step)
				if ok and type(res) == "string" and res ~= "" then objective = res end
			end
			local title = step.Title or ""

			local grew = prev ~= nil and not prev.done and current > (prev.current or 0) and required == (prev.required or required)
			live[quest.Id] = {
				order = order,
				title = title, objective = objective,
				current = current, required = required, hasProgress = hasProgress,
				kind = kind, done = false, completing = false,
				animate = prev ~= nil,
			}
			if grew then playSound("wheelTick", 0.25) end
			render()
		end)
	end
end

---------------------------------------------------------------- saved preference
-- Follow the server until the player takes over (the first DataUpdated of a
-- session can carry a default Settings table). A phone always BOOTS collapsed;
-- a tap on the chevron or a card still opens it for the session.
local dataRemote = remotes:WaitForChild("DataUpdated")
dataRemote.OnClientEvent:Connect(function(snap)
	if userTouched then return end
	if typeof(snap) ~= "table" then return end
	local st = snap.Settings
	if typeof(st) ~= "table" then return end
	local want = (st.questsHidden == true) or Platform.IsPhone
	if want ~= collapsed then setCollapsed(want, false) end
end)

-- BOOT SAFETY NET (kept from the previous tracker). SideRail owns this
-- ScreenGui's `Enabled` while a rail panel is open; a stale disable on a fresh
-- session used to leave the tracker invisible until some panel was opened and
-- closed. One shot, only while the nav rail says nothing is open.
task.delay(4, function()
	if gui.Enabled then return end
	local hud = playerGui:FindFirstChild("GameHUD")
	local canvas = hud and hud:FindFirstChild("Canvas")
	local chrome = (canvas and canvas:FindFirstChild("Chrome")) or (hud and hud:FindFirstChild("Chrome"))
	local railFrame = chrome and chrome:FindFirstChild("NavRail")
	if railFrame and railFrame.Visible then gui.Enabled = true end
end)

-- PHONE: the throw cluster (charge groove + HOLD TO SKIP) rises into the
-- bottom lane at the water (ClientMain's touch lift, y ~241..313 on the sim),
-- which is where this stack lives on a phone. Yield while it is up; back the
-- moment it drops. One property signal, no polling.
task.spawn(function()
	local mainUi = playerGui:WaitForChild("MainUI", 15)
	local throwFrame = mainUi and mainUi:WaitForChild("ThrowFrame", 15)
	if not throwFrame then return end
	local function sync()
		throwUp = throwFrame.Visible
		applyVisible(#activeList())
	end
	throwFrame:GetPropertyChangedSignal("Visible"):Connect(sync)
	sync()
end)

Platform.Watch(function()
	-- the class can settle after boot (device sim, rotation): re-decide the
	-- phone default while the player has not expressed a preference, and
	-- rebuild the cards so their type compensation matches the class
	if Platform.IsPhone and not userTouched and not collapsed then
		collapsed = true
	end
	for id in pairs(cards) do
		local rec = cards[id]
		cards[id] = nil
		rec.holder:Destroy()
	end
	render()
end)

render()
