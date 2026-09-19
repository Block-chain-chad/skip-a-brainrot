--!strict
-- DailyPanel: Daily Rewards panel -- a GameHUDPanels consumer module
-- (StarterPlayer.StarterPlayerScripts.GameHUDPanels.DailyPanel).
--
-- 2026-08-18 PS99 RE-SHELL (last legacy panel standing -- and the one that
-- AUTO-OPENS at join): the legacy header band (UI.surface "header" + in-band
-- red close) and the UI.surface "window" body are RETIRED for the ONE
-- PanelChrome shell every other GameHUD panel wears -- white rounded shell,
-- NO header band, bubble title straddling the top border, tilted daily-gift
-- sticker crossing the corner, pink-red rounded-square close overlapping the
-- corner, watermark, soft-edged body. Content (timer chip, hint, the 7 day
-- cards, claim wiring, coin-fly, countdown, blur watchers) is MOUNTED
-- UNCHANGED into shell.body -- only coordinates and ZIndex are rebased
-- (content floor = shell.z + 2, above the shell's watermark at z+1; card
-- furniture stays card-relative). shell.root carries NoPolish, so every
-- label below now keeps its AUTHORED ink -- the retuned day-card state
-- palette finally renders as written instead of UIPolish's forced white,
-- the same treatment every other shell panel gets (Builders' luminance gate
-- still strokes light fills). Phone pass: day number 17->20, reward label
-- 14->16, TODAY tag 12->13, MEGA lettering 14->16 -- content polish only,
-- no layout restructuring. ZERO wiring/remote/data changes.
--
-- 2026-08-04 STYLE REPLACEMENT (user's "Roblox Simulator UI Style Guide",
-- Pet-Sim inspired) -- supersedes the 1d/1e cream chrome below. THREE colour
-- decisions, nothing structural:
--   header  : T.gradient.header, the guide's red -- was the 1e purple
--             #b06bff -> #6c1fd6, built as a "gold" surface and recoloured
--             in place; "header" is a real surface kind now, so that dance
--             is gone (one gradient, one stroke, no leftovers);
--   body    : surface kind "window" (guide light gray #D6D6D6 -> #A9A9A9)
--             -- was kind "cream", which is now only a legacy alias;
--   hint    : T.color.textOnWindow -- was the hardcoded cream-ink #4a3416.
-- Everything else in this file is COLOURED IDENTITY and survives verbatim:
-- the four day-card states (claimed green, TODAY gold, locked lavender, MEGA
-- purple + rainbow ring), the pink TODAY tag, the green CLAIM pill, the dark
-- timer pill. The only literal GEOMETRY left is the mock's day-card furniture
-- (card stroke 3/3.5, badge/tag corners 14/10, glyph text sizes) -- already
-- inside the guide's 3-4px outline and 8-14 corner bands, so it stands; every
-- other radius/stroke/type here rides the retuned tokens. ZERO wiring, data
-- or motion changes.
--
-- 2026-08-04 RESTYLE (user handoff "Roblox game theme UI redesign", option
-- 1e): the visual recipe is the mock's -- accent header, panel body,
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
--   - outlines use the kit's ink T.color.outline (#202020 since the style
--     replacement, was #16170F; vs mock #1c1333 -- same near-black, the
--     mock's real mandate was "no brown #2e1a08");
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
--       Rewards: {RewardDef}, FreezeAvailable: boolean, JustClaimed: RewardDef?,
--       UsedFreeze: boolean? }
--       Streak = the real, UNCAPPED consecutive-day counter (data.DailyStreak).
--       NextDay = streakDayFor(...) result, ALWAYS in [1, #Rewards] -- the
--         reward-cycle index of the day about to be claimed (Claimable=true)
--         or, once claimed, the day that WAS just claimed (Claimable=false;
--         the server does NOT advance NextDay on claim -- see the CLAIMED/
--         TODAY/LOCKED note below).
--       Rewards = DailyRewardConfig.Days verbatim: SEVEN TYPED rewards, not the
--         old 30 cash numbers. Each is { Kind = "Cash"|"Emeralds"|"Boost"|"Tag"|
--         "Egg", ... } and is rendered through DailyRewardConfig.Describe, so a
--         card cannot advertise something the server does not pay. JustClaimed
--         is the reward TABLE now and is only ever tested for truthiness here.
--         Everything below sizes off #Rewards, so the week being 7 long makes
--         the rolling window exactly one page and wrapDay a no-op.
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

-- The week itself: what each day pays AND how a card describes it. Shared with
-- the server, which grants from the same table.
local DailyRewardConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DailyRewardConfig"))
-- Egg rewards pose the real MODEL and the emerald has its own drawn vector icon --
-- both exactly as PassPanel does it, so the two reward surfaces match.
local BrainrotThumb = require(ReplicatedStorage.Modules.BrainrotThumb)
local okIconArt, IconArt = pcall(function()
	return require(ReplicatedStorage.Modules.UIKit.IconArt)
end)
if not okIconArt then IconArt = nil end

-- PS99 shell (2026-08-18): the shared white chrome + its theme constants
local PC = require(ReplicatedStorage.Modules.UIKit.PanelChrome)
local S = require(ReplicatedStorage.Modules.UIKit.SpecTheme)

local DailyPanel = { Id = "daily" }

-- (the cash abbreviator that used to live here is gone: rewards are typed now and
-- DailyRewardConfig.Describe formats every kind, cash included)

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

----------------------------------------------------------------- mock palette (option 1e day-card STATES; ink rides T.color.outline)
-- STYLE REPLACEMENT (2026-08-04, Pet-Sim guide): every hex still standing
-- here is a STATE IDENTITY the guide explicitly leaves alone -- it is data
-- about which day you're looking at, not panel chrome. The two chrome
-- entries that used to sit in this block, HEADER_TOP/HEADER_BOT (the 1e
-- purple header), are DELETED: the header takes T.gradient.header now.
-- Read TODAY_TOP/TODAY_BOT as GOLD, not as the retired cream -- they are
-- cream-adjacent by accident of the gold wash, and they stay.
local CLAIMED_BG = Color3.fromHex("#e9f7e4")
local CLAIMED_BORDER = Color3.fromHex("#9CCB8E") -- darkened so claimed cards keep a visible border on the white PS99 body
local CLAIMED_TEXT = Color3.fromHex("#6da35e")
local TODAY_TOP = Color3.fromHex("#fff8dc") -- TODAY gold wash (identity), NOT chrome cream
local TODAY_BOT = Color3.fromHex("#ffe9a8") -- ditto
local TODAY_TEXT = Color3.fromHex("#8a6410") -- ink on the gold card, stays dark for legibility
local TODAY_GLOW = Color3.fromHex("#ffd23e")
local LOCKED_BG = Color3.fromHex("#E4E9F1") -- cool locked fill; the old lilac dissolved into the white PS99 body
local LOCKED_BORDER = Color3.fromHex("#B9C4D4") -- cool locked border to match
local LOCKED_TEXT = Color3.fromHex("#8d81a3")
local LOCK_BADGE = Color3.fromHex("#5c5470")
local MEGA_TEXT = Color3.fromHex("#8f2fe0")
local TAG_PINK = Color3.fromHex("#ff3d7a")
local TIMER_BG = Color3.fromHex("#2A3543") -- dark timer pill; PS99 cool navy (row dark family), was the warm brown
local TIMER_GOLD = Color3.fromHex("#ffd23e")
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

	----------------------------------------------------------- geometry (PS99 shell box)
	local C = S.Chrome
	local PANEL_W = T.size.panelWidth.daily -- 800 (mock 1e; was 900 pre-restyle)
	local BODY_PAD = C.BodyPadding -- 22: the shell body's OWN UIPadding (was T.pad.panelWide 18)
	local TIMER_ROW_H = 44 -- mock's centred timer-pill line (was the streak row)
	local ROW_GAP = T.pad.gap -- 12
	local CARD_H = T.size.dayCard -- 196
	local CARD_GAP = 10 -- mock 1e "gap 10" (was T.pad.gap 12)
	local BODY_CONTENT_H = TIMER_ROW_H + ROW_GAP + CARD_H
	local BODY_H = BODY_PAD * 2 + BODY_CONTENT_H -- 296: exactly wraps the two content rows
	-- the shell's vertical furniture on top of that: 18 ShellPadding top+bottom,
	-- 112 header band, 16 header->body gap (all S.Chrome) -- 460 total, well
	-- under GameHUDClient's 700 fit-height floor, so the host fit is unchanged
	local SHELL_H = C.ShellPadding * 2 + C.HeaderHeight + C.RowGap + BODY_H

	-- mock 1e: normal cards flex evenly, the milestone card is wider (118 vs
	-- 84 at reference scale = 1.40; the pre-restyle 1.45 is kept -- same read)
	-- inner width loses the shell padding AND the body padding now
	local BODY_INNER_W = PANEL_W - C.ShellPadding * 2 - BODY_PAD * 2 -- 720
	local USABLE_CARDS_W = BODY_INNER_W - CARD_GAP * 6
	local FLEX_UNITS = 6 + 1.45
	local UNIT_W = USABLE_CARDS_W / FLEX_UNITS
	local CARD_W_NORMAL = UNIT_W
	local CARD_W_GRAND = UNIT_W * 1.45

	----------------------------------------------------------- module-local state (server-confirmed only)
	local state = { Streak = 0, NextDay = 1, Rewards = {} :: { any }, Claimable = false, FreezeAvailable = false }
	local cardFrames: { [number]: Frame } = {} -- rewardIdx -> currently-rendered card Frame, rebuilt every render()
	local claimMotionGen = 0
	-- Every live instance a claim-resolve motion has created (scrim/check/
	-- coin), keyed by generation -- lets the wrapper Visible watcher below
	-- force-destroy an in-flight flourish immediately on panel close (the
	-- coin is parented to the ScreenGui, OUTSIDE wrapper's hierarchy).
	local motionInstancesByGen: { [number]: { Instance } } = {}

	----------------------------------------------------------- shell (PS99 white chrome)
	-- ONE PC.shell replaces the legacy header band + window body. key "daily"
	-- is the openPanel id; S.TitleInk.daily (gift orange) is registered in
	-- SpecTheme as this panel's title identity so a keyed title resolves
	-- orange, never the default cyan (the current shell letters large-panel
	-- titles white per the field study -- the identity rides the sticker).
	-- No ShellFor entry for daily, so the box is passed explicitly: 800 wide
	-- to match T.size.panelWidth.daily -- the host fit is untouched.
	local shell = PC.shell({
		name = "DailyPanel",
		title = "DAILY REWARDS",
		key = "daily",
		icon = T.icons.daily, -- the rail's daily gift asset (UIKit.Tokens)
		size = Vector2.new(PANEL_W, SHELL_H),
		scroll = false, -- one fixed card row; nothing scrolls
		listLayout = false, -- content is hand-positioned, not a list
	})
	-- openPanel treats the returned Frame as opaque (Visible toggling + the
	-- RestPosition glide work on any Frame) -- shell.root is that Frame now,
	-- and every Visible watcher below rides this alias unchanged.
	local wrapper = shell.root
	local body = shell.body -- carries the shell's own BodyPadding UIPadding
	-- Content z floor: the shell's watermark draws at shell.z+1 over the body
	-- fill, so content starts at shell.z+2 -- the same convention the other
	-- shell consumers use. Card furniture stays card-relative below it.
	local Z_CONTENT = shell.z + 2

	----------------------------------------------------------- timer row (mock 1e: centred dark pill; streak hint keeps its user-decided slot on the right)
	local timerRow = Instance.new("Frame")
	timerRow.Name = "TimerRow"
	timerRow.Position = UDim2.fromOffset(0, 0)
	timerRow.Size = UDim2.new(1, 0, 0, TIMER_ROW_H)
	timerRow.BackgroundTransparency = 1
	timerRow.ZIndex = Z_CONTENT
	timerRow.Parent = body

	local TIMER_W, TIMER_H = 280, 40
	local timerChip = Instance.new("Frame")
	timerChip.Name = "TimerChip"
	timerChip.AnchorPoint = Vector2.new(0.5, 0.5)
	timerChip.Position = UDim2.new(0.5, 0, 0.5, 0)
	timerChip.Size = UDim2.fromOffset(TIMER_W, TIMER_H)
	timerChip.BackgroundColor3 = TIMER_BG
	timerChip.BackgroundTransparency = 0.1 -- .9 alpha from the mock; static, never tweened (colour is now the PS99 navy TIMER_BG)
	timerChip.BorderSizePixel = 0
	timerChip.ZIndex = Z_CONTENT
	timerChip.Parent = timerRow
	UI.corner(timerChip, T.radius.pill)
	local timerStroke = Instance.new("UIStroke")
	timerStroke.Thickness = 2.5
	timerStroke.Color = Color3.fromHex("313D4F")
	timerStroke.Transparency = 0.1 -- 2.5px outline-navy(.9) ring; the mock's white ring was white-on-white on the PS99 body
	timerStroke.Parent = timerChip

	local timerLabel = UI.label(timerChip, "NEXT REWARD IN", "meta", T.color.white)
	timerLabel.Name = "TimerLabel"
	timerLabel.AnchorPoint = Vector2.new(0, 0.5)
	timerLabel.Position = UDim2.new(0, 16, 0.5, 0)
	timerLabel.Size = UDim2.fromOffset(150, 18)
	timerLabel.AutomaticSize = Enum.AutomaticSize.None
	timerLabel.TextXAlignment = Enum.TextXAlignment.Left
	timerLabel.TextTransparency = 0.25 -- mock white-75%
	timerLabel.ZIndex = Z_CONTENT + 1

	local timerValue = UI.label(timerChip, "00:00:00", "cardLabel", TIMER_GOLD)
	timerValue.Name = "TimerValue"
	timerValue.AnchorPoint = Vector2.new(1, 0.5)
	timerValue.Position = UDim2.new(1, -16, 0.5, 0)
	timerValue.Size = UDim2.fromOffset(100, 22)
	timerValue.AutomaticSize = Enum.AutomaticSize.None
	timerValue.TextXAlignment = Enum.TextXAlignment.Right
	timerValue.ZIndex = Z_CONTENT + 1

	-- USER DECISION (task 11), kept through the restyle: the raw uncapped
	-- streak count, right-aligned in this row. STYLE REPLACEMENT (2026-08-04,
	-- Pet-Sim guide): T.color.textOnWindow, was the hardcoded cream-ink
	-- #4a3416. This is the ONE label in the panel sitting directly on the body
	-- surface, so it stays DARK -- the guide's white-on-dark rule is for text
	-- on the dark slots, and white here would dissolve into the white PS99 body.
	local hintLabel = UI.label(timerRow, "", "meta", T.color.textOnWindow)
	hintLabel.Name = "HintLabel"
	hintLabel.AnchorPoint = Vector2.new(1, 0.5)
	hintLabel.Position = UDim2.new(1, 0, 0.5, 0)
	hintLabel.Size = UDim2.fromOffset(220, 20)
	hintLabel.AutomaticSize = Enum.AutomaticSize.None
	hintLabel.TextXAlignment = Enum.TextXAlignment.Right
	hintLabel.ZIndex = Z_CONTENT + 1

	----------------------------------------------------------- cards row
	local cardsRow = Instance.new("Frame")
	cardsRow.Name = "CardsRow"
	cardsRow.Position = UDim2.fromOffset(0, TIMER_ROW_H + ROW_GAP)
	cardsRow.Size = UDim2.new(1, 0, 0, CARD_H)
	cardsRow.BackgroundTransparency = 1
	cardsRow.ZIndex = Z_CONTENT
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
		word.TextSize = 13 -- phone pass 2026-08-18: was 12, the one sub-14 label on the card
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
		-- ...but 44 there is DESIGN px, and this panel renders under a UIScale, so
		-- the pill measured 42x33 ON SCREEN on a phone-classed client -- under the
		-- minimum on both axes, on the one button the whole panel exists for.
		-- UI.touchMin grows it until it lands on 44 for real (no-op off touch).
		--
		-- The pulse must START from whatever size that settles on: written against
		-- the authored 44/47 it would drag the pill straight back down and undo the
		-- floor on its first cycle. It is cancelled and re-made on each solve, so a
		-- rotation re-fits it too (one cycle may run at the old size in between).
		local pulse: Tween? = nil
		UI.touchMin(pill, 44, function(p)
			if pulse then pulse:Cancel() end
			local grown = p.Size
			pulse = TweenService:Create(p,
				TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Size = UDim2.new(grown.X.Scale, grown.X.Offset + 8, grown.Y.Scale, grown.Y.Offset + 3) })
			pulse:Play()
		end)
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
			halo.ZIndex = Z_CONTENT
			halo.Parent = slot
			UI.corner(halo, T.radius.control + 4)
		end

		local card = Instance.new("Frame")
		card.Name = "DayCard" .. rewardIdx
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.Position = UDim2.new(0.5, 0, 0.5, 0)
		card.Size = UDim2.fromOffset(w, CARD_H)
		card.BorderSizePixel = 0
		card.ZIndex = Z_CONTENT + 1
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
		dayLabel.TextSize = 20 -- phone pass 2026-08-18: cardLabel's 17 was the row's muddiest read at the 677px fit
		dayLabel.ZIndex = card.ZIndex + 2

		-- REWARD ART + LABEL, both driven by the shared week config so a card can
		-- never advertise something the server does not pay.
		--
		-- Four ways to dress a card, tried in order of how specific the art is: a
		-- posed egg MODEL, the emerald's drawn vector icon, an uploaded kit PNG, and
		-- finally an emoji for the kinds with no art at all. Which reward takes
		-- which is decided in DailyRewardConfig.Describe -- see its note.
		local look = DailyRewardConfig.Describe(state.Rewards[rewardIdx])
		local ART_SIZE = UDim2.new(1, 0, 1, -(24 + 6 + 20 + 6))
		local ART_Y = 24 + 6
		-- dimmed for claimed/locked per mock
		local dim = isClaimed and 0.5 or ((not isToday and not isGrand) and 0.55 or 0)

		local placed = false

		-- 1. THE REAL EGG, posed in a viewport -- the same helper the pass uses, so
		-- day 7 shows the thing it is actually promising rather than an emoji.
		if look.Model then
			local master = BrainrotThumb.eggMaster(look.Model)
			if master then
				local vp = BrainrotThumb.addMaster(card, master, {
					size = ART_SIZE,
					position = UDim2.new(0, 0, 0, ART_Y),
					zIndex = card.ZIndex + 1,
				})
				if vp then
					vp.Name = "ArtEgg"
					placed = true
				end
			end
		end

		-- 2. THE EMERALD's drawn icon. IconArt.draw BAKES its shapes to the pixel size
		-- it is handed, so it needs a fixed-size host, not a scaling one. A
		-- CanvasGroup carries the claimed/locked dim: the art is a tree of frames and
		-- strokes, and GroupTransparency fades the lot in one property.
		if not placed and look.Draw and IconArt and IconArt.has(look.Draw) then
			-- Two frames, because the two requirements fight: the art needs a FIXED
			-- pixel box (draw bakes to it), but it has to sit centred in an art area
			-- that is sized in SCALE. So an outer frame takes the art area's bounds and
			-- the fixed box is centred inside it -- top-aligning it instead left the
			-- icon riding high with a gap under it.
			local area = Instance.new("Frame")
			area.Name = "ArtDrawn"
			area.Position = UDim2.new(0, 0, 0, ART_Y)
			area.Size = ART_SIZE
			area.BackgroundTransparency = 1
			area.ZIndex = card.ZIndex + 1
			area.Parent = card

			local box = 88
			local host = Instance.new("CanvasGroup")
			host.Name = "Art"
			host.AnchorPoint = Vector2.new(0.5, 0.5)
			host.Position = UDim2.fromScale(0.5, 0.5)
			host.Size = UDim2.fromOffset(box, box)
			host.BackgroundTransparency = 1
			host.GroupTransparency = dim
			host.ZIndex = area.ZIndex
			host.Parent = area
			IconArt.draw(host, look.Draw, box, host.ZIndex + 1)
			placed = true
		end

		-- 3. an uploaded kit PNG
		if not placed and look.Icon and T.icons[look.Icon] then
			-- UI.artSlot returns the ImageLabel ITSELF, not a container.
			local art = UI.artSlot(card, ART_SIZE, T.icons[look.Icon])
			art.Name = "ArtSlot"
			art.Position = UDim2.new(0, 0, 0, ART_Y)
			art.ZIndex = card.ZIndex + 1
			art.ImageTransparency = dim
			placed = true
		end

		-- 4. emoji, the last resort
		if not placed then
			local glyph = UI.label(card, look.Glyph or "\u{2753}", "panelTitle", textColor)
			glyph.Name = "ArtGlyph"
			glyph.Position = UDim2.new(0, 0, 0, ART_Y)
			glyph.Size = ART_SIZE
			glyph.AutomaticSize = Enum.AutomaticSize.None
			glyph.TextXAlignment = Enum.TextXAlignment.Center
			glyph.TextYAlignment = Enum.TextYAlignment.Center
			glyph.TextScaled = true
			glyph.TextTransparency = dim
			glyph.ZIndex = card.ZIndex + 1
		end

		local rewardLabel = UI.label(card, look.Text, "chip", textColor)
		rewardLabel.Name = "RewardLabel"
		rewardLabel.AnchorPoint = Vector2.new(0, 1)
		rewardLabel.Position = UDim2.new(0, 0, 1, 0)
		rewardLabel.Size = UDim2.new(1, 0, 0, 20)
		rewardLabel.AutomaticSize = Enum.AutomaticSize.None
		rewardLabel.TextXAlignment = Enum.TextXAlignment.Center
		rewardLabel.TextSize = 16 -- phone pass 2026-08-18: up from chip's 14
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
			-- purple lettering. Ring rides the slot (unpadded, same bounds) per the
			-- furniture note above.
			--
			-- The generic gift icon that used to be forced on here is GONE: day 7
			-- pays eggs and the card already wears the egg glyph from Describe(),
			-- which says what you actually get. Forcing it also crashed outright
			-- once rewards became typed -- a glyph card has no ImageLabel to assign.
			UI.rainbowRing(slot, T.radius.control + 2)
			local mega = UI.label(card, "MEGA GIFT", "chip", MEGA_TEXT)
			mega.Name = "MegaLabel"
			mega.AnchorPoint = Vector2.new(0.5, 1)
			mega.Position = UDim2.new(0.5, 0, 1, -20)
			mega.Size = UDim2.new(1, 0, 0, 18)
			mega.AutomaticSize = Enum.AutomaticSize.None
			mega.TextXAlignment = Enum.TextXAlignment.Center
			mega.TextSize = 16 -- phone pass 2026-08-18: matches rewardLabel's bump
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
			slot.ZIndex = Z_CONTENT
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
		scrim.BackgroundColor3 = Color3.fromRGB(10, 18, 32) -- cool near-black scrim (was the warm green-black)
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
		-- centralised 2026-08-17: GameHUDClient owns the one shared HUDPanelBlur
		-- (blur-never-dim); a second per-panel BlurEffect only stacked on top
		do return end
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
	-- the shell's close (pink-red rounded square overlapping the corner).
	-- Activated, not MouseButton1Click -- it covers touch and gamepad too.
	shell.close.Activated:Connect(function()
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
