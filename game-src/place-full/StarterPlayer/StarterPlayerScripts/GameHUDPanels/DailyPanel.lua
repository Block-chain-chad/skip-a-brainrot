--!strict
-- DailyPanel: Daily Rewards panel -- a GameHUDPanels consumer module
-- (StarterPlayer.StarterPlayerScripts.GameHUDPanels.DailyPanel).
--
-- 2026-08-04 RESTYLE (user handoff "Roblox game theme UI redesign", option
-- 1e): the visual recipe is now the mock's -- purple header, cream body,
-- centred dark "NEXT REWARD IN" timer pill, and STATE-COLOURED day cards
-- (green claimed card + corner check, gold glowing TODAY card + pink tag +
-- breathing CLAIM, lavender locked card + corner lock, rainbow MEGA GIFT
-- milestone) -- replacing the kit's dark overlay treatment. ALL data wiring,
-- the rolling 30-day window math, the claim-resolve motion and the countdown
-- are unchanged from the previous version; read the sections below before
-- assuming anything about the data model.
-- Deliberate deviations from the mock, called out in the round report:
--   - kit family header (92px, icon + title + in-header close) kept instead
--     of the mock's 58px header + overlapping close circle -- family
--     consistency with every other GameHUDPanels panel;
--   - outlines use the kit's ink #16170F (vs mock #1c1333 -- same near-black,
--     the mock's real mandate was "no brown #2e1a08");
--   - no hourglass emoji in the timer pill (STYLE_GUIDE: no emoji as icons);
--   - the task-11 USER DECISION streak count ("N day streak!") survives in
--     the timer row's right slot; the old "Day N" gold chip is dropped (the
--     TODAY card carries the day number now).
--
-- Contract (identical to PassPanel/GoalsPanel):
--   return { Id = "daily", Build = function(ctx) -> Frame }
-- Build is called ONCE lazily on first open; the shell parents the returned
-- Frame into ctx.host and owns Visible toggling on every open/close after
-- that -- this module never sets its own Parent or drives its own open/close
-- animation.
--
-- Data contract (read StarterPlayer.StarterPlayerScripts.DailyRewardClient +
-- ServerScriptService.Modules.DailyRewardHandler FULLY before writing this):
--   remotes.DailyState  -- RemoteEvent, SERVER -> CLIENT PUSH ONLY. Unlike
--     SeasonState (PassPanel/GoalsPanel), there is NO OnServerEvent listener
--     for DailyState anywhere in DailyRewardHandler -- FireServer() on it
--     would reach nobody. The server pushes it exactly twice per event:
--       (a) once at join, ~1s after the player's profile loads (Init.onJoin)
--       (b) once per successful claim (see DailyClaim below)
--     Payload: { Claimable: boolean, Streak: number, NextDay: number,
--       Rewards: {number}, FreezeAvailable: boolean, JustClaimed: number?,
--       UsedFreeze: boolean? }
--       Streak = the real, UNCAPPED consecutive-day counter (data.DailyStreak).
--       NextDay = streakDayFor(...) result, ALWAYS in [1, #Rewards] -- the
--         reward-cycle index of the day about to be claimed (Claimable=true)
--         or, once claimed, the day that WAS just claimed (Claimable=false;
--         the server does NOT advance NextDay on claim -- see the CLAIMED/
--         TODAY/LOCKED note below).
--       Rewards = DAILY_REWARDS verbatim, a 30-ENTRY escalating table,
--         milestone spikes on cycle days 7/14/21/30.
--   remotes.DailyClaim  -- RemoteEvent, client -> server, FireServer() with
--     NO ARGUMENTS (verbatim: `remotes.DailyClaim:FireServer()`). Server
--     validates LastClaimDay and, on success, re-sends DailyState with the
--     new Streak/NextDay/JustClaimed. NEVER flip a card's state locally --
--     only the next DailyState push may change what a card renders as.
--
-- ROLLING WEEKLY WINDOW (mock draws a plain 7-day week; the game ships a
-- repeating 30-day cycle): the 7 cards are a window aligned to whichever
-- week of the 30-day cycle NextDay currently falls in --
--   weekBase = floor((NextDay - 1) / 7) * 7   (0, 7, 14, 21, or 28)
--   slot i (1..7) shows raw day (weekBase + i), reward-table index
--   wrapDay(weekBase + i) = ((weekBase + i - 1) % #Rewards) + 1
-- wrapDay only affects the ragged tail past day 30. The CLAIMED/TODAY/LOCKED
-- comparison always uses the RAW (unwrapped) day number against NextDay
-- (safe: weekBase is derived FROM NextDay so NextDay always falls inside
-- [weekBase+1, weekBase+7]), while the WRAPPED index is what's shown on the
-- card and used for the reward lookup.
-- MEGA GIFT (mock's day-7 card) is MILESTONE-based, not positional: gated on
-- MILESTONES[wrapDay(slotDay)] -- the server's real 7/14/21/30 milestone
-- days -- so it can land on ANY slot 1..7 depending on the window, and a
-- window can contain zero milestones.
--
-- CLAIMED/TODAY/LOCKED adaptation: NextDay does NOT advance on claim (it
-- stays equal to the day just banked; only Claimable flips) -- so:
--   isClaimed = slotDay < NextDay or (slotDay == NextDay and not Claimable)
--   isToday   = slotDay == NextDay and Claimable
--   isLocked  = not isClaimed and not isToday
--
-- FreezeAvailable/UsedFreeze ARE part of the real payload (captured into
-- `state` below for completeness) but neither the kit nor the mock gives
-- Daily a streak-freeze UI slot -- not rendered, deliberate scope decision.
--
-- MODULE-TOP-LEVEL CAPTURE (race fix): GameHUDPanels modules are required
-- once, early, during GameHUDClient's startup panelsFolder loop -- but
-- Build(ctx) itself only runs LAZILY on first panel open. DailyRewardHandler
-- fires its ONE unprompted join-time DailyState push ~1s after profile load,
-- which typically lands well before a player ever opens this panel -- a
-- listener registered INSIDE Build() would permanently miss it (there is no
-- pull/request path for this remote, see above). Fixed by connecting
-- remotes.DailyState.OnClientEvent at MODULE TOP LEVEL (below, outside
-- Build), capturing into `capturedState` regardless of whether Build() has
-- run yet. Build() seeds from whatever already arrived (allowMotion=false:
-- a catch-up paint, not a live claim).
--
-- Claim-resolve motion: scrim fades in 120ms -> check pops 220ms Back/Out
-- (T.tween.pop) -> coin flies to the coin pill 380ms Quint/Out
-- (T.tween.fly); GameHUDClient's applyCash() already pops the coin pill on
-- the DataUpdated cash increase, so no cash-pill code is needed here. ONE
-- generation counter (claimMotionGen) guards the chain's delayed callbacks;
-- decorative-only -- render() paints the true CLAIMED state immediately from
-- server data. This matches the mock's "CLAIM: fly a coin burst toward the
-- currency counter and bump the counter" behavior note verbatim.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local GuiService = game:GetService("GuiService") -- FIX F6: GetGuiInset() compensation for the fly-to-pill coin, see playClaimResolveMotion

local DailyPanel = { Id = "daily" }

local function shortCash(n: number): string
	n = math.floor(n or 0)
	if n >= 1e9 then
		return string.format("$%.1fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("$%.1fM", n / 1e6)
	elseif n >= 1e3 then
		return string.format("$%.0fK", n / 1e3)
	end
	return "$" .. tostring(n)
end

local function formatHMS(totalSeconds: number): string
	totalSeconds = math.max(0, math.floor(totalSeconds))
	local h = totalSeconds // 3600
	local m = (totalSeconds % 3600) // 60
	local s = totalSeconds % 60
	return string.format("%02d:%02d:%02d", h, m, s)
end

-- Pure so it's trivially probeable; os.time() is UTC-based in Roblox and
-- matches the server's `math.floor(os.time() / 86400)` day math; the outer
-- `% 86400` keeps an exact day boundary reading 0 rather than 86400.
local function nextMidnightRemaining(t: number): number
	return (86400 - (t % 86400)) % 86400
end

-- The server's real milestone days (spacing 7,7,7,9 -- NOT a flat "every
-- 7th"), copied verbatim from the legacy DailyRewardClient's table.
local MILESTONES = { [7] = true, [14] = true, [21] = true, [30] = true }

----------------------------------------------------------------- mock palette (option 1e; ink stays the kit's)
local CLAIMED_BG = Color3.fromHex("#e9f7e4")
local CLAIMED_BORDER = Color3.fromHex("#bfe3b1")
local CLAIMED_TEXT = Color3.fromHex("#6da35e")
local TODAY_TOP = Color3.fromHex("#fff8dc")
local TODAY_BOT = Color3.fromHex("#ffe9a8")
local TODAY_TEXT = Color3.fromHex("#8a6410")
local TODAY_GLOW = Color3.fromHex("#ffd23e")
local LOCKED_BG = Color3.fromHex("#eae4f2")
local LOCKED_BORDER = Color3.fromHex("#cfc4dd")
local LOCKED_TEXT = Color3.fromHex("#8d81a3")
local LOCK_BADGE = Color3.fromHex("#5c5470")
local MEGA_TEXT = Color3.fromHex("#8f2fe0")
local TAG_PINK = Color3.fromHex("#ff3d7a")
local TIMER_BG = Color3.fromHex("#281608")
local TIMER_GOLD = Color3.fromHex("#ffd23e")
local HEADER_TOP = Color3.fromHex("#b06bff")
local HEADER_BOT = Color3.fromHex("#6c1fd6")
local CHECK_GREEN = Color3.fromHex("#3fae1f")

----------------------------------------------------------------- module-top-level capture (see header note)
local remotesTop = ReplicatedStorage:WaitForChild("Remotes")
local capturedState = nil
local liveCallbacks: { (any) -> () } = {}
remotesTop.DailyState.OnClientEvent:Connect(function(s)
	if typeof(s) ~= "table" then
		return
	end
	capturedState = s
	for _, cb in ipairs(liveCallbacks) do
		cb(s)
	end
end)

function DailyPanel.Build(ctx)
	local T = ctx.Tokens
	local UI = ctx.Builders

	----------------------------------------------------------- geometry
	local PANEL_W = T.size.panelWidth.daily -- 800 (mock 1e; was 900 pre-restyle)
	local HEADER_H = T.size.headerHeight -- 92
	local BODY_TOP = HEADER_H + 12
	local BODY_PAD = T.pad.panelWide -- 18
	local TIMER_ROW_H = 44 -- mock's centred timer-pill line (was the streak row)
	local ROW_GAP = T.pad.gap -- 12
	local CARD_H = T.size.dayCard -- 196
	local CARD_GAP = 10 -- mock 1e "gap 10" (was T.pad.gap 12)
	local BODY_CONTENT_H = TIMER_ROW_H + ROW_GAP + CARD_H
	local BODY_H = BODY_PAD * 2 + BODY_CONTENT_H
	local GROUP_H = BODY_TOP + BODY_H

	-- mock 1e: normal cards flex evenly, the milestone card is wider (118 vs
	-- 84 at reference scale = 1.40; the pre-restyle 1.45 is kept -- same read)
	local BODY_INNER_W = PANEL_W - BODY_PAD * 2
	local USABLE_CARDS_W = BODY_INNER_W - CARD_GAP * 6
	local FLEX_UNITS = 6 + 1.45
	local UNIT_W = USABLE_CARDS_W / FLEX_UNITS
	local CARD_W_NORMAL = UNIT_W
	local CARD_W_GRAND = UNIT_W * 1.45

	----------------------------------------------------------- module-local state (server-confirmed only)
	local state = { Streak = 0, NextDay = 1, Rewards = {} :: { number }, Claimable = false, FreezeAvailable = false }
	local cardFrames: { [number]: Frame } = {} -- rewardIdx -> currently-rendered card Frame, rebuilt every render()
	local claimMotionGen = 0
	-- Every live instance a claim-resolve motion has created (scrim/check/
	-- coin), keyed by generation -- lets the wrapper Visible watcher below
	-- force-destroy an in-flight flourish immediately on panel close (the
	-- coin is parented to the ScreenGui, OUTSIDE wrapper's hierarchy).
	local motionInstancesByGen: { [number]: { Instance } } = {}

	----------------------------------------------------------- root
	local wrapper = Instance.new("Frame")
	wrapper.Name = "DailyPanel"
	wrapper.Size = UDim2.fromScale(1, 1)
	wrapper.BackgroundTransparency = 1
	wrapper.ZIndex = 10

	local panelCol = Instance.new("Frame")
	panelCol.Name = "PanelColumn"
	panelCol.AnchorPoint = Vector2.new(0.5, 0.5)
	panelCol.Position = UDim2.fromScale(0.5, 0.5)
	panelCol.Size = UDim2.fromOffset(PANEL_W, GROUP_H)
	panelCol.BackgroundTransparency = 1
	panelCol.ZIndex = 10
	panelCol.Parent = wrapper

	----------------------------------------------------------- header (kit family shell, mock 1e purple)
	local header = UI.surface(panelCol, UDim2.fromOffset(PANEL_W, HEADER_H), "gold", T.radius.panel, T.stroke.panel)
	header.Name = "Header"
	header.Position = UDim2.fromOffset(0, 0)
	header.ZIndex = 12
	-- mock 1e header gradient #b06bff -> #6c1fd6 -- recolor the surface's
	-- gradient in place (UI.surface has no purple kind; same recolor pattern
	-- the timer chip always used)
	local headerGrad = header:FindFirstChildOfClass("UIGradient")
	if headerGrad then
		headerGrad.Color = ColorSequence.new(HEADER_TOP, HEADER_BOT)
	end
	UI.gloss(header, T.radius.panel)
	UI.hardShadow(header, T.shadowOffset.panel, T.radius.panel)

	local headerIcon = UI.artSlot(header, UDim2.fromOffset(62, 62), T.icons.daily)
	headerIcon.Name = "SectionIcon"
	headerIcon.AnchorPoint = Vector2.new(0, 0.5)
	headerIcon.Position = UDim2.new(0, 12, 0.5, 0)
	headerIcon.ZIndex = header.ZIndex + 2

	local headerTitle = UI.label(header, "DAILY REWARDS", "panelTitle", T.color.white)
	headerTitle.Name = "Title"
	headerTitle.AnchorPoint = Vector2.new(0, 0.5)
	headerTitle.Position = UDim2.new(0, 12 + 62 + 14, 0.5, 0)
	headerTitle.ZIndex = header.ZIndex + 2

	local closeBtn = UI.button(header, "X", "red", UDim2.fromOffset(T.size.closeButton.X, T.size.closeButton.Y), "buttonL")
	closeBtn.Name = "CloseButton"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -12, 0.5, 0)
	closeBtn.ZIndex = header.ZIndex + 2

	----------------------------------------------------------- body (mock 1e cream)
	local body = UI.surface(panelCol, UDim2.fromOffset(PANEL_W, BODY_H), "cream", T.radius.panel, T.stroke.panel)
	body.Name = "Body"
	body.Position = UDim2.fromOffset(0, BODY_TOP)
	body.ZIndex = 12
	UI.hardShadow(body, T.shadowOffset.panel, T.radius.panel)
	local bodyPad = Instance.new("UIPadding")
	bodyPad.PaddingTop = UDim.new(0, BODY_PAD)
	bodyPad.PaddingBottom = UDim.new(0, BODY_PAD)
	bodyPad.PaddingLeft = UDim.new(0, BODY_PAD)
	bodyPad.PaddingRight = UDim.new(0, BODY_PAD)
	bodyPad.Parent = body

	----------------------------------------------------------- timer row (mock 1e: centred dark pill; streak hint keeps its user-decided slot on the right)
	local timerRow = Instance.new("Frame")
	timerRow.Name = "TimerRow"
	timerRow.Position = UDim2.fromOffset(0, 0)
	timerRow.Size = UDim2.new(1, 0, 0, TIMER_ROW_H)
	timerRow.BackgroundTransparency = 1
	timerRow.ZIndex = 14
	timerRow.Parent = body

	local TIMER_W, TIMER_H = 280, 40
	local timerChip = Instance.new("Frame")
	timerChip.Name = "TimerChip"
	timerChip.AnchorPoint = Vector2.new(0.5, 0.5)
	timerChip.Position = UDim2.new(0.5, 0, 0.5, 0)
	timerChip.Size = UDim2.fromOffset(TIMER_W, TIMER_H)
	timerChip.BackgroundColor3 = TIMER_BG
	timerChip.BackgroundTransparency = 0.1 -- mock rgba(40,22,8,.9); static, never tweened
	timerChip.BorderSizePixel = 0
	timerChip.ZIndex = 14
	timerChip.Parent = timerRow
	UI.corner(timerChip, T.radius.pill)
	local timerStroke = Instance.new("UIStroke")
	timerStroke.Thickness = 2.5
	timerStroke.Color = Color3.fromRGB(255, 255, 255)
	timerStroke.Transparency = 0.1 -- mock 2.5px white(.9) ring
	timerStroke.Parent = timerChip

	local timerLabel = UI.label(timerChip, "NEXT REWARD IN", "meta", T.color.white)
	timerLabel.Name = "TimerLabel"
	timerLabel.AnchorPoint = Vector2.new(0, 0.5)
	timerLabel.Position = UDim2.new(0, 16, 0.5, 0)
	timerLabel.Size = UDim2.fromOffset(150, 18)
	timerLabel.AutomaticSize = Enum.AutomaticSize.None
	timerLabel.TextXAlignment = Enum.TextXAlignment.Left
	timerLabel.TextTransparency = 0.25 -- mock white-75%
	timerLabel.ZIndex = 15

	local timerValue = UI.label(timerChip, "00:00:00", "cardLabel", TIMER_GOLD)
	timerValue.Name = "TimerValue"
	timerValue.AnchorPoint = Vector2.new(1, 0.5)
	timerValue.Position = UDim2.new(1, -16, 0.5, 0)
	timerValue.Size = UDim2.fromOffset(100, 22)
	timerValue.AutomaticSize = Enum.AutomaticSize.None
	timerValue.TextXAlignment = Enum.TextXAlignment.Right
	timerValue.ZIndex = 15

	-- USER DECISION (task 11), kept through the restyle: the raw uncapped
	-- streak count, right-aligned in this row. #4a3416 -- the mock's own
	-- body-text-on-cream colour (white was for the old dark panel surface).
	local hintLabel = UI.label(timerRow, "", "meta", Color3.fromHex("#4a3416"))
	hintLabel.Name = "HintLabel"
	hintLabel.AnchorPoint = Vector2.new(1, 0.5)
	hintLabel.Position = UDim2.new(1, 0, 0.5, 0)
	hintLabel.Size = UDim2.fromOffset(220, 20)
	hintLabel.AutomaticSize = Enum.AutomaticSize.None
	hintLabel.TextXAlignment = Enum.TextXAlignment.Right
	hintLabel.ZIndex = 15

	----------------------------------------------------------- cards row
	local cardsRow = Instance.new("Frame")
	cardsRow.Name = "CardsRow"
	cardsRow.Position = UDim2.fromOffset(0, TIMER_ROW_H + ROW_GAP)
	cardsRow.Size = UDim2.new(1, 0, 0, CARD_H)
	cardsRow.BackgroundTransparency = 1
	cardsRow.ZIndex = 14
	cardsRow.Parent = body

	local cardsList = Instance.new("UIListLayout")
	cardsList.FillDirection = Enum.FillDirection.Horizontal
	-- centred, not left-aligned: a zero-milestone window (e.g. days 22..28)
	-- has no wide grand card, and the flex math leaves ~42px of slack that
	-- read as a left-shifted row (review catch)
	cardsList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	cardsList.SortOrder = Enum.SortOrder.LayoutOrder
	cardsList.Padding = UDim.new(0, CARD_GAP)
	cardsList.Parent = cardsRow

	----------------------------------------------------------- card furniture (mock 1e states)
	-- OVERHANG FURNITURE IS PARENTED TO THE SLOT, NOT THE CARD (review catch):
	-- the card carries an 8px UIPadding for its labels, and UIPadding shifts
	-- ALL children -- badges/tags meant to overhang the card's edge were being
	-- pulled 8px inward. The slot has identical bounds to the card (same size,
	-- centred) and no padding, so slot-relative offsets land exactly on the
	-- card's true edges.
	-- Corner badge (mock: 24px circle at top -9 / right -7, 2.5px white ring)
	-- shared by CLAIMED (green check) and LOCKED (plum lock).
	local function buildCornerBadge(card: Frame, fill: Color3, glyphText: string)
		local badge = Instance.new("Frame")
		badge.Name = "CornerBadge"
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.new(1, 8, 0, -8)
		badge.Size = UDim2.fromOffset(28, 28)
		badge.BackgroundColor3 = fill
		badge.BorderSizePixel = 0
		badge.ZIndex = card.ZIndex + 8
		badge.Parent = card.Parent -- the slot; see the furniture note above
		UI.corner(badge, 14)
		local ring = Instance.new("UIStroke")
		ring.Thickness = 2.5
		ring.Color = Color3.fromRGB(255, 255, 255)
		ring.Parent = badge
		local glyph = UI.label(badge, glyphText, "chip", T.color.white)
		glyph.Name = "Glyph"
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.fromScale(0.5, 0.5)
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.AutomaticSize = Enum.AutomaticSize.None
		glyph.TextXAlignment = Enum.TextXAlignment.Center
		glyph.TextSize = 15
		glyph.ZIndex = badge.ZIndex + 1
	end

	-- TODAY's pink tag pill, centred over the card's top edge (mock: -13).
	local function buildTodayTag(card: Frame)
		local tag = Instance.new("Frame")
		tag.Name = "TodayTag"
		tag.AnchorPoint = Vector2.new(0.5, 0.5)
		tag.Position = UDim2.new(0.5, 0, 0, -13)
		tag.Size = UDim2.fromOffset(64, 24)
		tag.BackgroundColor3 = TAG_PINK
		tag.BorderSizePixel = 0
		tag.ZIndex = card.ZIndex + 8
		tag.Parent = card.Parent -- the slot; see the furniture note above
		UI.corner(tag, 10)
		local ring = Instance.new("UIStroke")
		ring.Thickness = 2.5
		ring.Color = Color3.fromRGB(255, 255, 255)
		ring.Parent = tag
		local word = UI.label(tag, "TODAY", "chip", T.color.white)
		word.Name = "Word"
		word.AnchorPoint = Vector2.new(0.5, 0.5)
		word.Position = UDim2.fromScale(0.5, 0.5)
		word.Size = UDim2.fromScale(1, 1)
		word.AutomaticSize = Enum.AutomaticSize.None
		word.TextXAlignment = Enum.TextXAlignment.Center
		word.TextSize = 12
		word.ZIndex = tag.ZIndex + 1
	end

	local function buildClaimPill(card: Frame)
		-- CLAIM protrudes below the card; height 44 = the touch minimum. The
		-- mock's 1.4s pulse rides Size (AnchorPoint 0.5,1: width grows about
		-- the centre, height grows upward -- no position compensation) because
		-- UIScale tweens do not run in this place.
		local pill = UI.button(card, "CLAIM", "green", UDim2.new(1, -16, 0, 44), "buttonM")
		pill.Name = "ClaimPill"
		pill.AnchorPoint = Vector2.new(0.5, 1)
		pill.Position = UDim2.new(0.5, 0, 1, 16)
		pill.ZIndex = card.ZIndex + 6
		TweenService:Create(pill,
			TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Size = UDim2.new(1, -8, 0, 47) }):Play()
		-- The ONE DailyClaim:FireServer call site in this module, fired with
		-- NO ARGUMENTS. No local state mutation -- the card only re-renders
		-- CLAIMED once the server pushes a fresh DailyState.
		pill.MouseButton1Click:Connect(function()
			ctx.remotes.DailyClaim:FireServer()
		end)
	end

	----------------------------------------------------------- day card builder (mock 1e state-coloured cards)
	local function buildDayCard(slot: Frame, slotDay: number, rewardIdx: number, isGrand: boolean)
		local w = isGrand and CARD_W_GRAND or CARD_W_NORMAL

		-- kit adaptation of the mock states -- see module header note
		local isClaimed = slotDay < state.NextDay or (slotDay == state.NextDay and not state.Claimable)
		local isToday = slotDay == state.NextDay and state.Claimable

		-- TODAY's gold glow: a static halo frame behind the card (the mock's
		-- box-shadow ring; layered-frame convention, no blur primitives here)
		if isToday then
			local halo = Instance.new("Frame")
			halo.Name = "TodayHalo"
			halo.AnchorPoint = Vector2.new(0.5, 0.5)
			halo.Position = UDim2.new(0.5, 0, 0.5, 0)
			halo.Size = UDim2.fromOffset(w + 12, CARD_H + 12)
			halo.BackgroundColor3 = TODAY_GLOW
			halo.BackgroundTransparency = 0.45
			halo.BorderSizePixel = 0
			halo.ZIndex = 14
			halo.Parent = slot
			UI.corner(halo, T.radius.control + 4)
		end

		local card = Instance.new("Frame")
		card.Name = "DayCard" .. rewardIdx
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.Position = UDim2.new(0.5, 0, 0.5, 0)
		card.Size = UDim2.fromOffset(w, CARD_H)
		card.BorderSizePixel = 0
		card.ZIndex = 15
		card.Parent = slot
		UI.corner(card, T.radius.control)

		-- state colouring (mock 1e)
		local textColor: Color3
		if isToday then
			card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			local grad = Instance.new("UIGradient")
			grad.Rotation = 90
			grad.Color = ColorSequence.new(TODAY_TOP, TODAY_BOT)
			grad.Parent = card
			UI.stroke(card, 3.5) -- ink border
			textColor = TODAY_TEXT
		elseif isClaimed then
			card.BackgroundColor3 = CLAIMED_BG
			local st = UI.stroke(card, 3)
			st.Color = CLAIMED_BORDER
			textColor = CLAIMED_TEXT
		elseif isGrand then
			card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			UI.stroke(card, 3)
			textColor = MEGA_TEXT
		else
			card.BackgroundColor3 = LOCKED_BG
			local st = UI.stroke(card, 3)
			st.Color = LOCKED_BORDER
			textColor = LOCKED_TEXT
		end
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 8)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.Parent = card

		local dayLabel = UI.label(card, "DAY " .. tostring(rewardIdx), "cardLabel", textColor)
		dayLabel.Name = "DayLabel"
		dayLabel.Position = UDim2.fromOffset(0, 0)
		dayLabel.Size = UDim2.new(1, 0, 0, 24)
		dayLabel.AutomaticSize = Enum.AutomaticSize.None
		dayLabel.TextXAlignment = Enum.TextXAlignment.Center
		dayLabel.ZIndex = card.ZIndex + 2

		-- coin art (kit icon, not emoji); dimmed for claimed/locked per mock.
		-- UI.artSlot returns the ImageLabel ITSELF, not a container.
		local art = UI.artSlot(card, UDim2.new(1, 0, 1, -(24 + 6 + 20 + 6)), T.icons.coin)
		art.Name = "ArtSlot"
		art.Position = UDim2.new(0, 0, 0, 24 + 6)
		art.ZIndex = card.ZIndex + 1
		if isClaimed then
			art.ImageTransparency = 0.5
		elseif not isToday and not isGrand then
			art.ImageTransparency = 0.55
		end

		local rewardLabel = UI.label(card, shortCash(state.Rewards[rewardIdx] or 0), "chip", textColor)
		rewardLabel.Name = "RewardLabel"
		rewardLabel.AnchorPoint = Vector2.new(0, 1)
		rewardLabel.Position = UDim2.new(0, 0, 1, 0)
		rewardLabel.Size = UDim2.new(1, 0, 0, 20)
		rewardLabel.AutomaticSize = Enum.AutomaticSize.None
		rewardLabel.TextXAlignment = Enum.TextXAlignment.Center
		rewardLabel.ZIndex = card.ZIndex + 2

		cardFrames[rewardIdx] = card

		if isClaimed then
			buildCornerBadge(card, CHECK_GREEN, "\u{2713}")
		elseif isToday then
			buildTodayTag(card)
			buildClaimPill(card)
			rewardLabel.Visible = false
		elseif not isGrand then
			-- mock's day-7 card wears no lock badge -- the rainbow treatment
			-- IS its locked look
			buildCornerBadge(card, LOCK_BADGE, "\u{1F512}")
		end

		if isGrand then
			-- mock day-7 MEGA GIFT: rainbow border (shared-Heartbeat ring) +
			-- purple lettering; the gift art replaces the coin. Ring rides the
			-- slot (unpadded, same bounds) per the furniture note above.
			UI.rainbowRing(slot, T.radius.control + 2)
			art.Image = T.icons.daily
			local mega = UI.label(card, "MEGA GIFT", "chip", MEGA_TEXT)
			mega.Name = "MegaLabel"
			mega.AnchorPoint = Vector2.new(0.5, 1)
			mega.Position = UDim2.new(0.5, 0, 1, -20)
			mega.Size = UDim2.new(1, 0, 0, 18)
			mega.AutomaticSize = Enum.AutomaticSize.None
			mega.TextXAlignment = Enum.TextXAlignment.Center
			mega.ZIndex = card.ZIndex + 2
			-- a milestone that is ALSO the claimable TODAY: the breathing CLAIM
			-- pill owns the card's foot -- hide the lettering rather than let
			-- the pill slice it (review catch; same convention as rewardLabel)
			mega.Visible = not isToday
		end
	end

	----------------------------------------------------------- card row render (rolling weekly window -- see module header note)
	local function renderCards()
		for _, c in ipairs(cardsRow:GetChildren()) do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		table.clear(cardFrames)

		local cycleLen = math.max(#state.Rewards, 1)
		local function wrapDay(d: number): number
			return ((d - 1) % cycleLen) + 1
		end
		local weekBase = math.floor((state.NextDay - 1) / 7) * 7

		for i = 1, 7 do
			local slotDay = weekBase + i
			local rewardIdx = wrapDay(slotDay)
			-- milestone-true MEGA GIFT, not positional -- gated on the SAME
			-- wrapped reward index the reward lookup uses
			local isGrand = MILESTONES[rewardIdx] == true

			local slot = Instance.new("Frame")
			slot.Name = "DaySlot" .. i
			slot.LayoutOrder = i
			slot.Size = UDim2.fromOffset(isGrand and CARD_W_GRAND or CARD_W_NORMAL, CARD_H)
			slot.BackgroundTransparency = 1
			slot.ZIndex = 15
			slot.Parent = cardsRow

			buildDayCard(slot, slotDay, rewardIdx, isGrand)
		end
	end

	local function render()
		if state.Streak and state.Streak > 0 then
			hintLabel.Text = tostring(state.Streak) .. " day streak!"
		else
			hintLabel.Text = ""
		end
		renderCards()
	end

	----------------------------------------------------------- claim-resolve motion (unchanged through the restyle -- see module header note)
	local function playClaimResolveMotion(claimedDayIdx: number)
		local card = cardFrames[claimedDayIdx]
		if not card then
			return -- window scrolled off this day; render() already shows the true state
		end

		claimMotionGen += 1
		local myGen = claimMotionGen
		local myInstances: { Instance } = {}
		motionInstancesByGen[myGen] = myInstances

		local scrim = Instance.new("Frame")
		scrim.Name = "ClaimMotionScrim"
		scrim.Size = UDim2.fromScale(1, 1)
		scrim.BackgroundColor3 = Color3.fromRGB(10, 14, 6)
		scrim.BackgroundTransparency = 1
		scrim.BorderSizePixel = 0
		scrim.ZIndex = card.ZIndex + 10
		scrim.Parent = card
		table.insert(myInstances, scrim)
		UI.corner(scrim, T.radius.control)
		TweenService:Create(scrim, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 0.4,
		}):Play()

		task.delay(0.12, function()
			if myGen ~= claimMotionGen or not card.Parent then
				return
			end

			local check = Instance.new("Frame")
			check.Name = "ClaimMotionCheck"
			check.AnchorPoint = Vector2.new(0.5, 0.5)
			check.Position = UDim2.fromScale(0.5, 0.5)
			check.Size = UDim2.fromOffset(56, 56)
			check.BackgroundColor3 = T.color.white
			check.BorderSizePixel = 0
			check.ZIndex = scrim.ZIndex + 1
			check.Parent = card
			table.insert(myInstances, check)
			UI.corner(check, 28)
			UI.gradient(check, T.gradient.green)
			UI.stroke(check, T.stroke.control)
			local checkScale = Instance.new("UIScale")
			checkScale.Scale = 0.4
			checkScale.Parent = check
			local mark = UI.label(check, "\u{2713}", "buttonL", T.color.white)
			mark.AnchorPoint = Vector2.new(0.5, 0.5)
			mark.Position = UDim2.fromScale(0.5, 0.5)
			mark.Size = UDim2.fromScale(1, 1)
			mark.AutomaticSize = Enum.AutomaticSize.None
			mark.TextXAlignment = Enum.TextXAlignment.Center
			mark.TextSize = 30
			mark.ZIndex = check.ZIndex + 1

			TweenService:Create(checkScale, T.tween.pop, { Scale = 1 }):Play()

			task.delay(T.tween.pop.Time, function()
				if myGen ~= claimMotionGen or not card.Parent then
					return
				end

				-- fly the coin to the pill (parented to the ScreenGui so raw
				-- AbsolutePosition maps 1:1; FIX F6 inset compensation)
				local screenGui = ctx.host:FindFirstAncestorOfClass("ScreenGui")
				if screenGui then
					local insetY = GuiService:GetGuiInset().Y
					local fromCenter = card.AbsolutePosition + card.AbsoluteSize / 2
					local coin = UI.artSlot(screenGui, UDim2.fromOffset(40, 40), T.icons.coin)
					coin.Name = "DailyClaimFlyCoin"
					coin.AnchorPoint = Vector2.new(0.5, 0.5)
					coin.Position = UDim2.fromOffset(fromCenter.X, fromCenter.Y + insetY)
					coin.ZIndex = T.zindex.toast
					coin.Parent = screenGui
					table.insert(myInstances, coin)
					local target = ctx.pillAnchor("coin")
					local flyTween = TweenService:Create(coin, T.tween.fly, {
						Position = UDim2.fromOffset(target.X, target.Y + insetY),
						Size = UDim2.fromOffset(16, 16),
					})
					flyTween.Completed:Connect(function()
						if coin and coin.Parent then
							coin:Destroy()
						end
						motionInstancesByGen[myGen] = nil
					end)
					flyTween:Play()
				else
					motionInstancesByGen[myGen] = nil
				end

				TweenService:Create(scrim, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					BackgroundTransparency = 1,
				}):Play()
				task.delay(0.12, function()
					if scrim and scrim.Parent then
						scrim:Destroy()
					end
				end)
				if check and check.Parent then
					check:Destroy()
				end
			end)
		end)
	end

	----------------------------------------------------------- data wiring (server-confirmed only)
	local function applyServerState(s, allowMotion: boolean)
		if typeof(s) ~= "table" then
			return
		end
		state.Streak = s.Streak or 0
		state.NextDay = s.NextDay or 1
		state.Rewards = s.Rewards or state.Rewards
		state.Claimable = s.Claimable == true
		state.FreezeAvailable = s.FreezeAvailable == true

		ctx.state.daily.streakDay = state.NextDay
		ctx.state.daily.claimedToday = not state.Claimable

		render()

		if allowMotion and s.JustClaimed then
			playClaimResolveMotion(state.NextDay)
		end
	end

	if capturedState then
		applyServerState(capturedState, false)
	end
	table.insert(liveCallbacks, function(s)
		applyServerState(s, true)
	end)

	----------------------------------------------------------- refresh countdown (1s loop, gated on wrapper.Visible)
	local countdownRunning = false
	local function tickCountdown()
		timerValue.Text = formatHMS(nextMidnightRemaining(os.time()))
	end
	local function startCountdown()
		if countdownRunning then
			return
		end
		countdownRunning = true
		task.spawn(function()
			while countdownRunning and wrapper.Visible do
				tickCountdown()
				task.wait(1)
			end
			countdownRunning = false
		end)
	end
	local function stopCountdown()
		countdownRunning = false
	end

	----------------------------------------------------------- backdrop blur (mock 1d/1e: dim + blur(3px) behind the panel)
	-- The shell owns the dim scrim; the blur is per-panel. Created/destroyed
	-- on Visible (covers close, force-close and ESC alike). Size is SET, not
	-- tweened -- BlurEffect.Size is not on the proven tween whitelist here.
	local BLUR_NAME = "DailyPanelBlur"
	local function setBlur(on: boolean)
		local existing = Lighting:FindFirstChild(BLUR_NAME)
		if on and not existing then
			local blur = Instance.new("BlurEffect")
			blur.Name = BLUR_NAME
			blur.Size = 8
			blur.Parent = Lighting
		elseif not on and existing then
			existing:Destroy()
		end
	end

	----------------------------------------------------------- wiring
	closeBtn.MouseButton1Click:Connect(function()
		ctx.closePanel()
	end)

	-- No refresh request to make on open: the server never listens for one
	-- (see module header). Visibility drives the countdown, the blur, and
	-- in-flight claim-motion cleanup.
	wrapper:GetPropertyChangedSignal("Visible"):Connect(function()
		if wrapper.Visible then
			startCountdown()
			setBlur(true)
		else
			stopCountdown()
			setBlur(false)
			-- force-destroy any in-flight claim flourish (the coin lives
			-- OUTSIDE wrapper's hierarchy and would keep flying otherwise)
			claimMotionGen += 1
			for gen, instances in pairs(motionInstancesByGen) do
				for _, inst in ipairs(instances) do
					if inst and inst.Parent then
						inst:Destroy()
					end
				end
				motionInstancesByGen[gen] = nil
			end
		end
	end)

	-- Belt-and-braces for the blur/countdown teardown (review catch): the
	-- shell's openPanel now hides every other panel unconditionally, but any
	-- path that hides the HOST while this wrapper stays Visible (legacy
	-- single-open force-closes, future shell changes) must still kill the
	-- global BlurEffect -- it post-processes the whole screen regardless of
	-- GUI visibility.
	ctx.host:GetPropertyChangedSignal("Visible"):Connect(function()
		if not ctx.host.Visible then
			setBlur(false)
			stopCountdown()
		elseif wrapper.Visible then
			setBlur(true)
			startCountdown()
		end
	end)

	render() -- initial paint (zero/seeded state) before openPanel shows the frame

	return wrapper
end

return DailyPanel
