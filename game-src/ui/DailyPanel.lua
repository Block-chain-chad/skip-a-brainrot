--!strict
-- DailyPanel: kit README §3.4 + §5 "Daily" Daily Rewards panel -- a
-- GameHUDPanels consumer module (StarterPlayer.StarterPlayerScripts.
-- GameHUDPanels.DailyPanel).
--
-- Contract (kit README section: ctx from GameHUDClient), identical to
-- PassPanel/GoalsPanel:
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
--       Rewards = DAILY_REWARDS verbatim, a 30-ENTRY escalating table (NOT
--         7 -- see the kit-vs-data note below), milestone spikes on cycle
--         days 7/14/21/30, indices 1..7 are literally {500,1000,2500,5000,
--         10000,25000,100000}.
--   remotes.DailyClaim  -- RemoteEvent, client -> server, FireServer() with
--     NO ARGUMENTS (verbatim: `remotes.DailyClaim:FireServer()`). Server
--     validates LastClaimDay and, on success, re-sends DailyState with the
--     new Streak/NextDay/JustClaimed. NEVER flip a card's state locally --
--     only the next DailyState push may change what a card renders as.
--
-- KIT-VS-DATA: the kit's Daily screen (§3.4/§5 + captures/daily.png) is
-- drawn for a plain 7-day week (a fixed "Day 1..Day 7" row, day 7 = the
-- once-only GRAND finale). The real game ships a 30-DAY escalating cycle
-- that repeats forever (streakDayFor wraps `% #DAILY_REWARDS`), i.e. the
-- exact same "kit assumed a smaller ladder than the game actually has"
-- situation PassPanel's report documents for SeasonConfig (kit says 50
-- tiers, game ships 25) -- but Daily's kit layout is a FIXED 7-card row with
-- no scroll (unlike Pass's horizontal ScrollingFrame track), so there is no
-- literal "show all 30" option that still matches kit geometry.
-- Resolution: the 7 cards are a ROLLING WEEKLY WINDOW aligned to whichever
-- week of the 30-day cycle NextDay currently falls in --
--   weekBase = floor((NextDay - 1) / 7) * 7   (0, 7, 14, 21, or 28)
--   slot i (1..7) shows raw day (weekBase + i), reward-table index
--   wrapDay(weekBase + i) = ((weekBase + i - 1) % #Rewards) + 1
-- wrapDay only affects the ragged tail past day 30 (weekBase=28 gives raw
-- days 29..35, wrapping 31..35 back to reward indices 1..5) -- the CLAIMED/
-- TODAY/LOCKED comparison below always uses the RAW (unwrapped) day number
-- against NextDay, which is safe because weekBase is derived FROM NextDay
-- (NextDay always falls inside [weekBase+1, weekBase+7] by construction, so
-- no cross-cycle ambiguity), while the WRAPPED index is what's shown on the
-- card and used to look up the reward value -- this keeps every card's
-- number and dollar amount always real/current regardless of how deep into
-- the 30-day cycle the player is, rather than freezing the row at a
-- perpetually-stale literal days-1-7 view once the player passes day 7.
-- GRAND rainbow-ring/ribbon treatment (kit §3.4/§5) is MILESTONE-based (post-
-- review FIX 1), not positional: gated on MILESTONES[wrapDay(slotDay)] --
-- the server's real 7/14/21/30 milestone days (legacy DailyRewardClient's own
-- table, copied verbatim) -- so it can land on ANY slot 1..7 depending on
-- where NextDay's window falls (e.g. NextDay=30 puts the real GRAND on slot
-- 2, raw day 30, not slot 7). A window can also contain ZERO milestones
-- (e.g. NextDay=22..28 -> weekBase 21 -> raw days 22..28 hit none of
-- 7/14/21/30) -- correctly, no card gets the ring/ribbon that render.
--
-- CLAIMED/TODAY/LOCKED adaptation (kit §5 Daily): the kit's literal formula
-- is `day < streakDay -> CLAIMED`, `day == streakDay and not claimedToday
-- -> TODAY`, `else LOCKED` -- written for a model where streakDay itself
-- advances the instant you claim. This server's NextDay does NOT advance on
-- claim (it stays equal to the day just banked; only Claimable flips to
-- false) -- so day==streakDay-but-already-claimed must resolve to CLAIMED,
-- not fall through to kit's literal "else LOCKED". Adapted here as:
--   isClaimed = slotDay < NextDay or (slotDay == NextDay and not Claimable)
--   isToday   = slotDay == NextDay and Claimable
--   isLocked  = not isClaimed and not isToday
-- (claimedToday = not Claimable, matching ctx.state.daily's own field name).
--
-- FreezeAvailable/UsedFreeze ARE part of the real payload (captured into
-- `state` below for completeness) but the kit gives Daily no UI slot for a
-- streak-freeze mechanic at all -- not rendered, a deliberate kit-exact
-- scope decision (same class as PassPanel leaving Skip hidden for a missing
-- gamepass id).
--
-- MODULE-TOP-LEVEL CAPTURE (race fix): GameHUDPanels modules are required
-- once, early, during GameHUDClient's startup panelsFolder loop -- but
-- Build(ctx) itself only runs LAZILY on first panel open. DailyRewardHandler
-- fires its ONE unprompted join-time DailyState push ~1s after profile load,
-- which typically lands well before a player ever opens this panel -- a
-- listener registered INSIDE Build() would permanently miss it (there is no
-- pull/request path for this remote, see above), leaving the panel stuck on
-- its zero/placeholder paint until the player's first claim. Fixed by
-- connecting remotes.DailyState.OnClientEvent at MODULE TOP LEVEL (below,
-- outside Build) -- this runs at require() time, before that 1s server
-- delay can possibly elapse -- capturing into `capturedState` regardless of
-- whether Build() has run yet. Build() seeds its render-facing `state` from
-- whatever already arrived (via applyServerState(capturedState, false) --
-- the `false` suppresses claim-resolve motion for what is a catch-up paint,
-- not a live claim) and registers itself for all future pushes.
--
-- Claim-resolve motion (kit README §4): scrim fades in 120ms -> check pops
-- 220ms Back/Out -> reward icon flies to the coin pill 380ms Quint/Out, then
-- "the pill's own pop handles the counter" -- GameHUDClient's applyCash()
-- already pops coinPill whenever Cash increases via remotes.DataUpdated, so
-- no cash-pill code is needed here at all, just the flight. T.tween.pop and
-- T.tween.fly match the 220ms Back/Out and 380ms Quint/Out legs exactly; the
-- 120ms scrim fade has no matching T.tween entry (same class of untokenised
-- kit-timing gap GoalsPanel's own refresh chip colours document) so it's a
-- literal TweenInfo. ONE generation counter (claimMotionGen) guards the
-- whole scrim->check->fly chain's delayed callbacks, same convention
-- EggShopClient's playReveal()/skip() uses for its shake->crack->creature
-- phases -- it is decorative-only: render() below already paints the true
-- CLAIMED state immediately and unconditionally from server data, the
-- motion just layers a transient flourish on top of that already-correct
-- card.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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

-- Quote-copied verbatim from GoalsPanel (same formula, same reasoning: pure
-- so it's trivially probeable against a known epoch; os.time() is UTC-based
-- in Roblox and matches DarrelService.utcDay/SeasonPassHandler.currentDay's
-- own `math.floor(os.time() / 86400)` day math; the outer `% 86400` matters
-- because a naive `86400 - (t % 86400)` reads 86400 ("24:00:00") at the
-- exact instant t lands ON a day boundary instead of 0 ("00:00:00")).
local function nextMidnightRemaining(t: number): number
	return (86400 - (t % 86400)) % 86400
end

-- FIX 1 (post-review): the server's real GRAND-tier milestone days --
-- copied verbatim from the legacy DailyRewardClient's own table. Spacing is
-- 7,7,7,9 (NOT a flat "every 7th day"), so a fixed "slot 7 of the window"
-- treatment drifts off the real milestones after week 3 -- see renderCards()
-- below, which gates isGrand on MILESTONES[wrapDay(slotDay)] instead of a
-- literal `i == 7`.
local MILESTONES = { [7] = true, [14] = true, [21] = true, [30] = true }

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

	----------------------------------------------------------- geometry (kit README §3.4, exact where tokenised)
	local PANEL_W = T.size.panelWidth.daily -- 900
	local HEADER_H = T.size.headerHeight -- 92
	local BODY_TOP = HEADER_H + 12
	local BODY_PAD = T.pad.panelWide -- 18 ("padding 18 on Daily", kit §3)
	local STREAK_ROW_H = 44 -- matches the "Day N" chip's own height44
	local ROW_GAP = T.pad.gap -- 12 (kit gives no explicit streak-row-to-cards gap; reusing the shared spacing-scale token, same convention PassPanel/GoalsPanel use for their own untokenised gaps)
	local CARD_H = T.size.dayCard -- 196
	local CARD_GAP = T.pad.gap -- 12 ("Row of cards, gap 12")
	local BODY_CONTENT_H = STREAK_ROW_H + ROW_GAP + CARD_H
	local BODY_H = BODY_PAD * 2 + BODY_CONTENT_H
	local GROUP_H = BODY_TOP + BODY_H

	-- days 1-6 flex:1, day 7 flex:1.45 (kit §3.4) -- usable width after 6 gaps, split by flex ratio
	local BODY_INNER_W = PANEL_W - BODY_PAD * 2
	local USABLE_CARDS_W = BODY_INNER_W - CARD_GAP * 6
	local FLEX_UNITS = 6 + 1.45
	local UNIT_W = USABLE_CARDS_W / FLEX_UNITS
	local CARD_W_NORMAL = UNIT_W
	local CARD_W_GRAND = UNIT_W * 1.45

	----------------------------------------------------------- module-local state (server-confirmed only)
	local state = { Streak = 0, NextDay = 1, Rewards = {} :: { number }, Claimable = false, FreezeAvailable = false }
	local cardFrames: { [number]: Frame } = {} -- rewardIdx (1..#Rewards) -> currently-rendered card Frame, rebuilt every render()
	local claimMotionGen = 0
	-- FIX 2: every live instance a claim-resolve motion has created (scrim/
	-- check/coin), keyed by the generation that created it -- lets the
	-- wrapper Visible watcher below force-destroy an in-flight flourish's
	-- instances immediately on panel close instead of waiting for its own
	-- delayed cleanup (the coin in particular is parented to the ScreenGui,
	-- OUTSIDE wrapper's hierarchy, so it is not even hidden by wrapper.
	-- Visible = false on its own -- it would otherwise keep visibly flying
	-- across the screen after the panel closes).
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

	----------------------------------------------------------- header (common shell, README §3) -- default gold, Daily has no override
	local header = UI.surface(panelCol, UDim2.fromOffset(PANEL_W, HEADER_H), "gold", T.radius.panel, T.stroke.panel)
	header.Name = "Header"
	header.Position = UDim2.fromOffset(0, 0)
	header.ZIndex = 12
	UI.gloss(header, T.radius.panel)
	UI.hardShadow(header, T.shadowOffset.panel, T.radius.panel)

	local headerIcon = UI.artSlot(header, UDim2.fromOffset(62, 62), T.icons.daily)
	headerIcon.Name = "SectionIcon"
	headerIcon.AnchorPoint = Vector2.new(0, 0.5)
	headerIcon.Position = UDim2.new(0, 12, 0.5, 0)
	headerIcon.ZIndex = header.ZIndex + 2

	local headerTitle = UI.label(header, "Daily Rewards", "panelTitle", T.color.white)
	headerTitle.Name = "Title"
	headerTitle.AnchorPoint = Vector2.new(0, 0.5)
	headerTitle.Position = UDim2.new(0, 12 + 62 + 14, 0.5, 0)
	headerTitle.ZIndex = header.ZIndex + 2

	local closeBtn = UI.button(header, "X", "red", UDim2.fromOffset(T.size.closeButton.X, T.size.closeButton.Y), "buttonL")
	closeBtn.Name = "CloseButton"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -12, 0.5, 0)
	closeBtn.ZIndex = header.ZIndex + 2

	-- RESETS IN chip (kit §3.4: "height 58, radius 14, #3B4731 -> #26301F").
	-- Width has no explicit kit spec -- ad hoc 190, same class of gap
	-- GoalsPanel's own refresh chip documents (untokenised colour + width).
	local TIMER_W, TIMER_H = 190, 58
	local timerChip = Instance.new("Frame")
	timerChip.Name = "ResetsInChip"
	timerChip.AnchorPoint = Vector2.new(1, 0.5)
	timerChip.Position = UDim2.new(1, -12 - T.size.closeButton.X - 14, 0.5, 0)
	timerChip.Size = UDim2.fromOffset(TIMER_W, TIMER_H)
	timerChip.BackgroundColor3 = T.color.white
	timerChip.BorderSizePixel = 0
	timerChip.ZIndex = header.ZIndex + 2
	timerChip.Parent = header
	UI.corner(timerChip, T.radius.inner) -- FIX 4: kit §3.4 says radius 14 (T.radius.inner) in its own comment above -- was T.radius.small (12), contradicting it
	local timerGradient = Instance.new("UIGradient")
	timerGradient.Rotation = 90
	timerGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, T.hex("#3B4731")),
		ColorSequenceKeypoint.new(1, T.hex("#26301F")),
	})
	timerGradient.Parent = timerChip
	UI.stroke(timerChip, T.stroke.control)

	local timerLabel = UI.label(timerChip, "RESETS IN", "meta", T.color.textMuted)
	timerLabel.Name = "ResetsInLabel"
	timerLabel.AnchorPoint = Vector2.new(0, 0.5)
	timerLabel.Position = UDim2.new(0, 12, 0.5, -12)
	timerLabel.Size = UDim2.new(1, -24, 0, 16)
	timerLabel.AutomaticSize = Enum.AutomaticSize.None
	timerLabel.TextXAlignment = Enum.TextXAlignment.Left
	timerLabel.ZIndex = timerChip.ZIndex + 1

	local timerValue = UI.label(timerChip, "00:00:00", "cardLabel", T.color.white)
	timerValue.Name = "ResetsInValue"
	timerValue.AnchorPoint = Vector2.new(0, 0.5)
	timerValue.Position = UDim2.new(0, 12, 0.5, 12)
	timerValue.Size = UDim2.new(1, -24, 0, 22)
	timerValue.AutomaticSize = Enum.AutomaticSize.None
	timerValue.TextXAlignment = Enum.TextXAlignment.Left
	timerValue.ZIndex = timerChip.ZIndex + 1

	----------------------------------------------------------- body (common shell, README §3 -- padding 18 on Daily)
	-- Hand-rolled instead of UI.panel() because UI.panel() hardcodes
	-- T.pad.panel (16) on all four sides; Daily's kit-specified 18 has no
	-- override param on the shared builder (editing UIKit.Builders itself
	-- would ripple into every other panel's body padding -- out of scope,
	-- same reasoning PassPanel/GoalsPanel give for their own kit-vs-shared-
	-- Builders gaps).
	local body = UI.surface(panelCol, UDim2.fromOffset(PANEL_W, BODY_H), "panel", T.radius.panel, T.stroke.panel)
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

	----------------------------------------------------------- streak row
	local streakRow = Instance.new("Frame")
	streakRow.Name = "StreakRow"
	streakRow.Position = UDim2.fromOffset(0, 0)
	streakRow.Size = UDim2.new(1, 0, 0, STREAK_ROW_H)
	streakRow.BackgroundTransparency = 1
	streakRow.ZIndex = 14
	streakRow.Parent = body

	local loginLabel = UI.label(streakRow, "Login streak", "buttonM", T.color.white)
	loginLabel.Name = "LoginStreakLabel"
	loginLabel.AnchorPoint = Vector2.new(0, 0.5)
	loginLabel.Position = UDim2.new(0, 0, 0.5, 0)
	loginLabel.Size = UDim2.fromOffset(200, 30)
	loginLabel.AutomaticSize = Enum.AutomaticSize.None
	loginLabel.TextXAlignment = Enum.TextXAlignment.Left
	loginLabel.ZIndex = 15

	-- "Day N" chip: shows state.NextDay (the reward-cycle slot currently
	-- highlighted TODAY/about-to-claim in the card row below), not the raw
	-- uncapped Streak counter -- keeps the chip's number and the row's
	-- highlighted card's own "Day N" label always in visual agreement,
	-- matching the reference capture (chip "Day 4" <-> the Day 4 card is the
	-- one with the green ring). A raw Streak (e.g. "Day 37" after five
	-- 30-day cycles) would desync from whichever card is actually glowing.
	local DAY_CHIP_W, DAY_CHIP_H = 110, 44
	local dayChip = UI.surface(streakRow, UDim2.fromOffset(DAY_CHIP_W, DAY_CHIP_H), "goldSmall", T.radius.inner, T.stroke.control)
	dayChip.Name = "DayChip"
	dayChip.AnchorPoint = Vector2.new(0, 0.5)
	dayChip.Position = UDim2.new(0, 210, 0.5, 0)
	dayChip.ZIndex = 15
	UI.gloss(dayChip, T.radius.inner)
	local dayChipLabel = UI.label(dayChip, "Day 1", "value", T.color.white)
	dayChipLabel.Name = "DayChipLabel"
	dayChipLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	dayChipLabel.Position = UDim2.fromScale(0.5, 0.5)
	dayChipLabel.Size = UDim2.fromScale(1, 1)
	dayChipLabel.AutomaticSize = Enum.AutomaticSize.None
	dayChipLabel.TextXAlignment = Enum.TextXAlignment.Center
	dayChipLabel.ZIndex = dayChip.ZIndex + 2

	local hintLabel = UI.label(streakRow, "Miss a day and the streak restarts at Day 1", "meta", T.color.textMuted)
	hintLabel.Name = "HintLabel"
	hintLabel.AnchorPoint = Vector2.new(1, 0.5)
	hintLabel.Position = UDim2.new(1, 0, 0.5, 0)
	hintLabel.Size = UDim2.fromOffset(430, 20)
	hintLabel.AutomaticSize = Enum.AutomaticSize.None
	hintLabel.TextXAlignment = Enum.TextXAlignment.Right
	hintLabel.ZIndex = 15

	----------------------------------------------------------- cards row
	local cardsRow = Instance.new("Frame")
	cardsRow.Name = "CardsRow"
	cardsRow.Position = UDim2.fromOffset(0, STREAK_ROW_H + ROW_GAP)
	cardsRow.Size = UDim2.new(1, 0, 0, CARD_H)
	cardsRow.BackgroundTransparency = 1
	cardsRow.ZIndex = 14
	cardsRow.Parent = body

	local cardsList = Instance.new("UIListLayout")
	cardsList.FillDirection = Enum.FillDirection.Horizontal
	cardsList.SortOrder = Enum.SortOrder.LayoutOrder
	cardsList.Padding = UDim.new(0, CARD_GAP)
	cardsList.Parent = cardsRow

	----------------------------------------------------------- day-card state overlays (kit §5 Daily -- own numbers, distinct from PassPanel's Pass-tier overlay)
	local function buildClaimedOverlay(card: Frame)
		local overlay = Instance.new("Frame")
		overlay.Name = "ClaimedOverlay"
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.BackgroundColor3 = Color3.fromRGB(8, 12, 5) -- FIX 5: kit Daily spec value rgba(8,12,5) -- was Color3.fromRGB(12,18,8), an off-kit approximation
		overlay.BackgroundTransparency = 0.38 -- kit §5 Daily "overlay .62" opacity -> transparency = 1-0.62
		overlay.BorderSizePixel = 0
		overlay.ZIndex = card.ZIndex + 6
		overlay.Parent = card
		UI.corner(overlay, T.radius.control)

		local check = Instance.new("Frame")
		check.Name = "CheckCircle"
		check.AnchorPoint = Vector2.new(0.5, 0.5)
		check.Position = UDim2.fromScale(0.5, 0.5)
		check.Size = UDim2.fromOffset(56, 56) -- kit §5 Daily "56px check" (Pass's own CLAIMED check is 62px)
		check.BackgroundColor3 = T.color.white
		check.BorderSizePixel = 0
		check.ZIndex = overlay.ZIndex + 1
		check.Parent = overlay
		UI.corner(check, 28)
		UI.gradient(check, T.gradient.green)
		UI.stroke(check, T.stroke.control)

		local mark = UI.label(check, "\u{2713}", "buttonL", T.color.white)
		mark.Name = "Check"
		mark.AnchorPoint = Vector2.new(0.5, 0.5)
		mark.Position = UDim2.fromScale(0.5, 0.5)
		mark.Size = UDim2.fromScale(1, 1)
		mark.AutomaticSize = Enum.AutomaticSize.None
		mark.TextXAlignment = Enum.TextXAlignment.Center
		mark.TextSize = 30
		mark.ZIndex = check.ZIndex + 1
	end

	local function buildLockedOverlay(card: Frame)
		local overlay = Instance.new("Frame")
		overlay.Name = "LockedOverlay"
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.BackgroundColor3 = Color3.fromRGB(8, 12, 5) -- FIX 5: kit Daily spec value rgba(8,12,5) -- was Color3.fromRGB(12,18,8), an off-kit approximation
		overlay.BackgroundTransparency = 0.58 -- kit §5 Daily "overlay .42" opacity -> transparency = 1-0.42
		overlay.BorderSizePixel = 0
		overlay.ZIndex = card.ZIndex + 6
		overlay.Parent = card
		UI.corner(overlay, T.radius.control)

		local glyph = UI.label(overlay, "\u{1F512}", "cardLabel", T.color.white)
		glyph.Name = "LockGlyph"
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.fromScale(0.5, 0.5)
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.AutomaticSize = Enum.AutomaticSize.None
		glyph.TextXAlignment = Enum.TextXAlignment.Center
		glyph.TextSize = 44 -- kit §5 Daily "centred 44px lock"
		glyph.ZIndex = overlay.ZIndex + 1
	end

	local function buildClaimPill(card: Frame)
		-- kit §5 Daily "CLAIM at bottom -16" -- protrudes BELOW the card
		-- (unlike PassPanel's inset "-8" claim pill), so the reward label is
		-- hidden for this state to give it room (same convention PassPanel's
		-- CLAIMABLE state hides its qty chip).
		local pill = UI.button(card, "CLAIM", "green", UDim2.new(1, -16, 0, 44), "buttonM") -- FIX 3: kit states.md Daily spec pins CLAIM pill height at 44 (also the touch minimum) -- T.size.claimPill is 38, shared with other panels' claim pills; hardcoded here per review, not changing the shared token (would ripple into every other panel)
		pill.Name = "ClaimPill"
		pill.AnchorPoint = Vector2.new(0.5, 1)
		pill.Position = UDim2.new(0.5, 0, 1, 16)
		pill.ZIndex = card.ZIndex + 6
		-- The ONE DailyClaim:FireServer call site in this module, fired with
		-- NO ARGUMENTS (verbatim signature). No local state mutation here --
		-- the card only re-renders CLAIMED once the server pushes a fresh
		-- DailyState with Claimable == false.
		pill.MouseButton1Click:Connect(function()
			ctx.remotes.DailyClaim:FireServer()
		end)
	end

	----------------------------------------------------------- day card builder
	local function buildDayCard(slot: Frame, slotDay: number, rewardIdx: number, isGrand: boolean)
		local w = isGrand and CARD_W_GRAND or CARD_W_NORMAL
		local card = UI.surface(slot, UDim2.fromOffset(w, CARD_H), "row", T.radius.control, T.stroke.control)
		card.Name = "DayCard" .. rewardIdx
		card.ZIndex = 15
		UI.hardShadow(card, T.shadowOffset.control, T.radius.control)

		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 8)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.Parent = card

		local dayLabel = UI.label(card, "Day " .. tostring(rewardIdx), "cardLabel", T.color.white)
		dayLabel.Name = "DayLabel"
		dayLabel.Position = UDim2.fromOffset(0, 0)
		dayLabel.Size = UDim2.new(1, 0, 0, 24)
		dayLabel.AutomaticSize = Enum.AutomaticSize.None
		dayLabel.TextXAlignment = Enum.TextXAlignment.Center
		dayLabel.ZIndex = card.ZIndex + 2

		local art = UI.artSlot(card, UDim2.new(1, 0, 1, -(24 + 6 + 20 + 6)), nil)
		art.Name = "ArtSlot" -- day1..7.png still-placeholder slots (README §6.2) -- no per-day art exists yet
		art.Position = UDim2.new(0, 0, 0, 24 + 6)
		art.ZIndex = card.ZIndex + 1

		local rewardLabel = UI.label(card, shortCash(state.Rewards[rewardIdx] or 0), "chip", T.color.textAccent)
		rewardLabel.Name = "RewardLabel"
		rewardLabel.AnchorPoint = Vector2.new(0, 1)
		rewardLabel.Position = UDim2.new(0, 0, 1, 0)
		rewardLabel.Size = UDim2.new(1, 0, 0, 20)
		rewardLabel.AutomaticSize = Enum.AutomaticSize.None
		rewardLabel.TextXAlignment = Enum.TextXAlignment.Center
		rewardLabel.ZIndex = card.ZIndex + 2

		cardFrames[rewardIdx] = card

		-- kit §5 Daily adaptation -- see module header note.
		local isClaimed = slotDay < state.NextDay or (slotDay == state.NextDay and not state.Claimable)
		local isToday = slotDay == state.NextDay and state.Claimable

		if isClaimed then
			buildClaimedOverlay(card)
		elseif isToday then
			UI.claimRing(card)
			buildClaimPill(card)
			rewardLabel.Visible = false
		else
			buildLockedOverlay(card)
		end

		if isGrand then
			UI.rainbowRing(card, 20)
			local ribbon = UI.ribbon(card, "GRAND", "GRAND") -- RIBBON_VARIANT.GRAND = "purple"
			ribbon.Name = "GrandRibbon"
			ribbon.AnchorPoint = Vector2.new(0, 0)
			ribbon.Position = UDim2.new(0, -6, 0, -10) -- kit §3.4 "top -10 / left -6"
			ribbon.ZIndex = card.ZIndex + 8
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
			-- FIX 1: milestone-true GRAND, not positional -- gate on the SAME
			-- wrapped reward index the card's reward-value lookup/label use, so
			-- the ring/ribbon follows the real milestone wherever it falls in
			-- this window (see MILESTONES + header note above).
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
		dayChipLabel.Text = "Day " .. tostring(state.NextDay)
		renderCards()
	end

	----------------------------------------------------------- claim-resolve motion (kit README §4 -- see module header note)
	local function playClaimResolveMotion(claimedDayIdx: number)
		local card = cardFrames[claimedDayIdx]
		if not card then
			return -- the window has scrolled off this day; render() already shows the true state, just skip the flourish
		end

		claimMotionGen += 1
		local myGen = claimMotionGen
		local myInstances: { Instance } = {} -- FIX 2: every live instance this generation creates (scrim/check/coin), so a mid-flight panel close can force-destroy them immediately
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
			table.insert(myInstances, check) -- FIX 2
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

			TweenService:Create(checkScale, T.tween.pop, { Scale = 1 }):Play() -- kit §4 "check pops 220ms Back/Out" -- T.tween.pop verbatim

			task.delay(T.tween.pop.Time, function()
				if myGen ~= claimMotionGen or not card.Parent then
					return
				end

				-- fly the reward icon to the coin pill (kit §4 "380ms
				-- Quint/Out" -- T.tween.fly verbatim). Parented directly into
				-- the ScreenGui (NOT into ctx.host, which lives inside the
				-- UIScale-scaled canvas) so its Position can use ctx.
				-- pillAnchor's/card's real screen-space AbsolutePosition 1:1,
				-- with no scale-factor conversion needed.
				local screenGui = ctx.host:FindFirstAncestorOfClass("ScreenGui")
				if screenGui then
					local fromCenter = card.AbsolutePosition + card.AbsoluteSize / 2
					local coin = UI.artSlot(screenGui, UDim2.fromOffset(40, 40), T.icons.coin)
					coin.Name = "DailyClaimFlyCoin"
					coin.AnchorPoint = Vector2.new(0.5, 0.5)
					coin.Position = UDim2.fromOffset(fromCenter.X, fromCenter.Y)
					coin.ZIndex = T.zindex.toast
					coin.Parent = screenGui
					table.insert(myInstances, coin) -- FIX 2: parented to the ScreenGui, NOT under card/wrapper -- the one instance not hidden by wrapper.Visible = false on its own, so it must be tracked + force-destroyed on close
					local target = ctx.pillAnchor("coin")
					local flyTween = TweenService:Create(coin, T.tween.fly, {
						Position = UDim2.fromOffset(target.X, target.Y),
						Size = UDim2.fromOffset(16, 16),
					})
					-- generation-guarded (EggShopClient's skip() pattern):
					-- each flight owns its own `coin` instance and always
					-- destroys it on arrival regardless of myGen -- the guard
					-- exists so nothing else tied to "the current flourish"
					-- (e.g. a future landing sound/pop) ever fires against a
					-- flight a newer claim has already superseded.
					flyTween.Completed:Connect(function()
						if coin and coin.Parent then
							coin:Destroy()
						end
						motionInstancesByGen[myGen] = nil -- FIX 2: natural completion -- coin outlives scrim/check by design (380ms fly vs 120ms fades), so it is the true last step of the flow
					end)
					flyTween:Play()
				else
					motionInstancesByGen[myGen] = nil -- FIX 2: no ScreenGui found, no coin flight -- scrim/check are the whole flow, clear now
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

		-- kit README §5 client state shape -- keep the shared ctx.state.daily
		-- table current for any other consumer (same convention PassPanel/
		-- GoalsPanel use for ctx.state.pass/ctx.state.goals).
		ctx.state.daily.streakDay = state.NextDay
		ctx.state.daily.claimedToday = not state.Claimable

		render()

		if allowMotion and s.JustClaimed then
			playClaimResolveMotion(state.NextDay)
		end
	end

	-- Catch-up seed from whatever the module-top-level listener already
	-- captured (allowMotion=false: this is a paint, never a live claim -- see
	-- module header note on the capture race).
	if capturedState then
		applyServerState(capturedState, false)
	end
	table.insert(liveCallbacks, function(s)
		applyServerState(s, true)
	end)

	----------------------------------------------------------- refresh countdown (1s loop, STRICTLY gated on wrapper.Visible -- quote-copied gating pattern from GoalsPanel)
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
		countdownRunning = false -- loop above checks this + wrapper.Visible every iteration and exits on its own
	end

	----------------------------------------------------------- wiring
	closeBtn.MouseButton1Click:Connect(function()
		ctx.closePanel()
	end)

	-- NOTE: unlike PassPanel/GoalsPanel's SeasonState, there is no
	-- remotes.DailyState:FireServer() refresh request to make here -- the
	-- server never listens for one (see module header note). Visibility only
	-- needs to drive the countdown loop; state itself arrives passively via
	-- the module-top-level listener above.
	wrapper:GetPropertyChangedSignal("Visible"):Connect(function()
		if wrapper.Visible then
			startCountdown()
		else
			stopCountdown()
			-- FIX 2: a mid-flight claim-resolve motion (scrim/check parented
			-- under `card`, coin parented directly under the ScreenGui --
			-- see playClaimResolveMotion) does NOT get hidden by the panel
			-- closing on its own: the coin in particular lives OUTSIDE the
			-- wrapper's hierarchy entirely (parented to the ScreenGui so its
			-- Position can use raw AbsolutePosition), so it would otherwise
			-- keep visibly flying across the screen after the player closes
			-- the panel. Bump the generation so every in-flight delayed
			-- continuation (check-pop stage, fly stage, Completed handler)
			-- sees a stale myGen and no-ops, AND destroy every currently-
			-- tracked live motion instance immediately rather than waiting
			-- for its own delayed cleanup to get around to it.
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

	render() -- initial paint (zero/seeded state) before this line's caller (openPanel) even shows the frame

	return wrapper
end

return DailyPanel
