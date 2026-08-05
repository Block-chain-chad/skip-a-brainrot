--!strict
-- GoalsPanel: kit README §3.6 Goals panel -- a GameHUDPanels consumer module
-- (StarterPlayer.StarterPlayerScripts.GameHUDPanels.GoalsPanel).
--
-- 2026-08-04 STYLE REPLACEMENT (Pet-Sim guide) -- SUPERSEDES the 1d/1e cream
-- sweep this file used to carry. The guide's chrome is three greys and one
-- red: a light-grey WINDOW body (#D6D6D6 -> #A9A9A9) where cream was, a RED
-- header bar (#F96B57 -> #C84535) where Goals' assigned green was, and DARK
-- slots (#4A4A4A -> #363636) where the white-card-with-tan-border was. So
-- every quest-row card, tab chip and icon slot flips light -> dark, and their
-- labels flip from #4a3416 body ink back to WHITE. Those dark families now
-- live in Tokens (T.gradient.row/slot/tab, plus window/header), which means
-- this pass mostly DELETES the cream sweep's per-surface overrides rather
-- than retargeting them -- the surfaces inherit the guide by just being
-- UI.surface/UI.button calls again. Only the header pair and the two
-- hand-built pieces of header furniture still need literals.
-- KEPT AS-IS (identity, not chrome): the soft-green Claimed pill, the gold
-- active-tab ring, green Claim / blue VIEW / disabled In-progress buttons,
-- the dark inset progress tracks and reward chips with their white in-chip
-- labels, and the per-panel backdrop BlurEffect ("GoalsPanelBlur"). EVERY
-- remote, state table, tab switch, bob driver and countdown wire below is
-- untouched: this was a recolour pass, zero wiring changes.
--
-- (Historical, so the diff reads: the 1d/1e sweep this replaced put a GREEN
-- header #7be04e -> #3fae1f on a cream body with white cards, the tan
-- #e5d3ac card border and #4a3416 body ink.)
--
-- Contract (kit README section: ctx from GameHUDClient):
--   return { Id = "goals", Build = function(ctx) -> Frame }
-- Build is called ONCE lazily on first open; the shell parents the returned
-- Frame into ctx.host and owns Visible toggling on every open/close after
-- that -- this module never sets its own Parent or drives its own open/close
-- animation (same contract PassPanel documents/follows).
--
-- This panel consolidates THREE independent quest systems behind one set of
-- tabs (Daily / Goals / Season). Each system was read FULLY before writing
-- anything below; their shapes differ enough that no single data model can
-- represent all three -- each tab has its own fetch + render path, feeding
-- a shared row-builder. Recorded verbatim (see task-6-report.md for the
-- full trace):
--
--   DAILY  -- ServerScriptService.Modules.DarrelService + remotes.DarrelUpdate
--            (RemoteEvent, server->client push) / remotes.DarrelState
--            (RemoteFunction, client->server pull, self-healing).
--     Both deliver the SAME shape: { Darrels = number, Daily = DailyState? }
--     DailyState = { Day = number, Quests = { { Id, Text, Reward, Target,
--       Progress, Claimed }, ... } }  (exactly 3 entries; DarrelService
--     .slateFor(day) picks 3 from a 6-quest pool, same slate for everyone)
--     `Daily` is nil until the player's profile has loaded server-side --
--     DarrelState's OnServerInvoke returns { Darrels = M.Get(player) (which
--     is 0 for an unloaded profile), Daily = M.GetDailyState(player) (which
--     is nil for an unloaded profile) }. A pull landing before the profile
--     loads is therefore a PLACEHOLDER, not real data -- GameHUDClient's own
--     startup-pull loop treats `typeof(res.Daily) == "table"` as the
--     loaded/not-loaded discriminator and keeps retrying until it sees a
--     table (see GameHUDClient ~line 374, "Bug C3 fix", and
--     task-4-report.md). This module reuses the exact same discriminator.
--     Server AUTO-CLAIMS (DarrelService.Notify claims + awards the instant
--     Progress reaches Target, before ever pushing state) -- so the client
--     NEVER sees Progress>=Target with Claimed==false, and there is no
--     Daily claim remote at all. Reward currency is Darrels (the gem
--     pill's currency).
--
--   GOALS (one-time milestones) -- ServerScriptService.Modules.QuestHandler
--            + remotes.QuestState (RemoteEvent, server->client push only --
--            no client-fire request exists; server pushes on join and again
--            every 3s for every player) / remotes.QuestClaim (RemoteEvent,
--            client->server, fire with the quest id string).
--     QuestState's payload is the quest LIST ITSELF (not wrapped in a
--     table field): array of { Id, Desc, Reward, Met, Claimed }. There is
--     no Progress/Target pair -- QuestHandler's `met(data)` predicates are
--     opaque booleans (e.g. "own 5 brainrots"), so this tab's progress bar
--     synthesizes Target=1/Progress=(Met and 1 or 0) and labels the meta
--     text COMPLETE/LOCKED rather than inventing a fake "x / 1" counter.
--     Reward currency is Cash (the coin pill's currency). Full Claim flow:
--     QuestClaim:FireServer(q.Id) -> server validates -> re-sends
--     QuestState -> row re-renders CLAIMED. Never claimed locally.
--
--   SEASON -- ServerScriptService.Modules.SeasonPassHandler + remotes.
--            SeasonState (RemoteEvent, bidirectional: FireServer() with no
--            args requests a refresh; FireClient pushes state) -- same
--            remote PassPanel already reads.
--     SeasonState payload: { XP, Claimed = {[tostring(tier)]=true,...},
--       QuestIds = {string,...}, Progress = {[id]={P=number,D=boolean}},
--       Day }. Quest DEFINITIONS (display name, icon, target, XP reward)
--     are NOT in that payload -- only ids + raw progress numbers. The
--     definitions live in ReplicatedStorage.Modules.SeasonConfig.PoolById
--     (Id, Name, Icon [emoji glyph, not an image], Event, Target, XP),
--     shared/public exactly like PassPanel already requires SeasonConfig
--     for tier data. Season quests have NO separate claim step: XP is
--     granted automatically the instant a quest's progress hits its target
--     (SeasonPassHandler.Notify sets q.D=true and adds def.XP to
--     data.SeasonXP in the same call, before ever pushing state) --
--     the thing a player DOES claim is a Pass reward TIER (SeasonClaim,
--     Cash), which is PassPanel's job, not this row's. Per the task brief,
--     every Season row's action is therefore a "VIEW" button that opens the
--     Pass panel (ctx.openPanel("pass")) -- there is no SeasonQuestClaim
--     remote to invent, and inventing local claim state here would violate
--     the server-confirmed-only rule for no benefit (the reward already
--     landed the moment SeasonState reported it).
--
-- Kit-token gaps (documented, not fabricated): §3.6 names two colours with
-- no matching ReplicatedStorage.Modules.UIKit.Tokens entry -- the header
-- icon-slot backing (#F0D2FF -> #DDB2F6) and the refresh chip
-- (#5B1D8C -> #3A0F5C bg, #E7C8FF label). The 1d/1e sweep retinted both to
-- track whatever the header accent was (green); the style replacement
-- (2026-08-04, Pet-Sim guide) STOPS chasing the accent hue and drops both
-- onto the guide's one DARK SLOT family (#4A4A4A -> #363636) with white
-- labels. Reasoning: the guide names exactly one inset-on-chrome treatment,
-- both of these ARE inset-on-chrome (a backing plate and a dark pill), and a
-- red-tinted plate on a red header would have been an invented hue family the
-- guide never specifies -- the same fabrication this comment block exists to
-- prevent. It also retires two of the four ad-hoc palettes this file carried.
-- The T.icons PNGs were drawn for the kit's original dark surfaces, so the
-- goals icon reads on a dark plate by construction. Quest-row
-- reward-chip background has NO colour spec at all in §3.6 (only geometry:
-- "height 52, radius 12, 30px icon + value 20") -- rendered with the
-- `track` gradient (closest existing dark-inset token; the same family the
-- kit's own Daily/Index chips use, which are themselves an untokenized
-- #3B4731->#26301F this build has no exact match for either). Quest title
-- (§3.6 "title 22") and reward-chip / action-button value text ("value 20")
-- have no exact T.text entry either (nearest is `cardLabel` at 20/stroke3,
-- vs the kit's 22/20 with a slightly different stroke) -- same class of
-- "kit vs shared Builders/Tokens" gap PassPanel's report documents for its
-- CTA/CLAIM-pill radius; not fixed here for the same reason (editing the
-- shared Tokens module would ripple into every other panel, out of scope).
--
-- HardShadow-in-UIListLayout trap (see PassPanel's report, bug 3): each
-- quest row is wrapped in a non-list-managed "RowSlot" container so the
-- vertical UIListLayout driving the rows scroll only ever sees one child
-- per quest. Originally the wrapper hid the card's UI.hardShadow sibling
-- from the list; the 1d/1e sweep dropped that shadow and the style
-- replacement (2026-08-04, Pet-Sim guide) keeps it dropped -- the guide's
-- dark slots are flat, their 4px ink outline does the separating. The
-- wrapper STAYS regardless: it is the list's one-child-per-quest contract
-- and the only safe home for any future shadow/overhang siblings.
--
-- Idle-bob driver: exactly ONE Heartbeat connection drives every currently-
-- rendered Claim button's ±5px bob (kit README §4, T.tween.bobPeriod =
-- 1.4s), self-pruning entries whose frame was destroyed by a re-render --
-- same shared-driver convention UIKit.Builders' rainbow-ring/claim-ring use
-- ("ONE Heartbeat total, a registry pruned when the instance is gone").
-- Connected only while this panel is visible; disconnected the instant it
-- closes (see the wrapper Visible watcher near the bottom).
--
-- Refresh countdown: a SEPARATE 1-second task loop (not the bob Heartbeat)
-- renders "HH:MM:SS" to the next UTC midnight -- both Daily's darrel slate
-- and Season's quest slate roll over at UTC midnight, so one shared
-- countdown serves both; Goals milestones never roll over, but the header
-- chip is shared across all three tabs (kit's shell has ONE header, not
-- one per tab) so it always shows the same next-rollover value regardless
-- of which tab is active. STRICTLY gated on wrapper.Visible: the loop
-- checks `countdownRunning and wrapper.Visible` every iteration and the
-- Visible watcher flips `countdownRunning = false` the instant the panel
-- closes, so no tick ever fires while the panel is hidden.

local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting") -- 1d/1e sweep (2026-08-04): hosts the per-panel backdrop BlurEffect
local modules = ReplicatedStorage:WaitForChild("Modules")
local SeasonConfig = require(modules:WaitForChild("SeasonConfig"))

local GoalsPanel = { Id = "goals" }

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

-- Pure so it's trivially probeable against a known epoch: nextMidnightRemaining(t)
-- for any t returns seconds until the next UTC day boundary. os.time() is
-- UTC-based in Roblox (server + client agree), matching DarrelService.utcDay
-- / SeasonPassHandler.currentDay's own `math.floor(os.time() / 86400)` day
-- math. The outer `% 86400` matters: a naive `86400 - (t % 86400)` reads
-- 86400 ("24:00:00") at the exact instant t lands ON a day boundary instead
-- of 0 ("00:00:00") -- caught live by probing t = a known day boundary
-- (e.g. 86400*5) before this wrap was added.
local function nextMidnightRemaining(t: number): number
	return (86400 - (t % 86400)) % 86400
end

----------------------------------------------------------------- style replacement palette (2026-08-04, Pet-Sim guide)
-- Deliberately SHORT. Every card / slot / row / tab surface in this file is
-- built through UI.surface or UI.button, and Tokens' row/slot/tab families
-- are already the guide's dark grey -- so those surfaces need no literal at
-- all any more and the cream sweep's overrides on them are simply deleted.
-- What survives here is only what Tokens genuinely cannot supply: the header
-- accent (a per-panel decision the kit has no token for -- see the header
-- build) and the dark family for the two header-furniture Frames that are
-- hand-built rather than UI.surface'd.
--
-- GONE, on purpose: CARD_BORDER (#e5d3ac) and BODY_INK (#4a3416). Cards are
-- dark now, so their labels go back to WHITE (UI.label / UI.button's own
-- default) and their outlines back to the kit ink #202020 that UI.stroke
-- already paints from T.color.outline. Nothing in this panel sits directly
-- on the light-grey window body -- the title is on the red header, every
-- other label is on a dark slot, chip or progress track -- so the guide's
-- T.color.textOnWindow has no use site here and is not referenced.
local HEADER_TOP = Color3.fromHex("#F96B57")
local HEADER_BOT = Color3.fromHex("#C84535")
local SLOT_TOP = Color3.fromHex("#4A4A4A") -- guide dark slot, ONLY for the hand-built header furniture + the scroll thumb
local SLOT_BOT = Color3.fromHex("#363636")
-- Claimed trio: UNCHANGED by the style replacement. Soft-green "claimed" is
-- quest-state IDENTITY, not chrome -- exactly like the gold active-tab ring,
-- the green Claim button and the blue VIEW button, all of which also survive
-- the swap untouched. It reads better on the dark card than it did on white.
local CLAIMED_BG = Color3.fromHex("#e9f7e4")
local CLAIMED_BORDER = Color3.fromHex("#bfe3b1")
local CLAIMED_TEXT = Color3.fromHex("#6da35e")

function GoalsPanel.Build(ctx)
	local T = ctx.Tokens
	local UI = ctx.Builders

	-- STYLE REPLACEMENT REPAIR (2026-08-04): see the note in PassPanel -- the
	-- cream constants were deleted but several call sites survived, turning
	-- into nil globals that crashed Build behind openPanel's pcall (the panel
	-- just never opened). Re-declared as their guide successors:
	--   borders -> the guide's 4px #202020 outline
	--   ink     -> white, because these rows/cards are dark slots now
	local CARD_BORDER = T.color.outline
	local BODY_INK = T.color.white
	-- Darrel's drawn face, for the Daily tab's reward chips. Not part of ctx
	-- (which carries only the kit's own Tokens/Builders), and pcall'd so a
	-- missing module costs an icon rather than the whole panel.
	local okIconArt, IconArt = pcall(function()
		return require(game:GetService("ReplicatedStorage").Modules.UIKit.IconArt)
	end)
	if not okIconArt then IconArt = nil end

	----------------------------------------------------------- geometry (kit README §3.6, exact where tokenised)
	local PANEL_W = T.size.panelWidth.goals -- 860
	local HEADER_H = T.size.headerHeight -- 92
	local BODY_TOP = HEADER_H + 12
	local TAB_H = 56
	local TAB_GAP = T.pad.gap -- 12 (kit gives no explicit tab gap; reusing the shared spacing-scale token, same convention PassPanel's reward-card column gap uses)
	local TABS_TO_ROWS_GAP = 12
	local ROW_H = T.size.questRow -- 88
	local ROW_GAP = T.pad.rowGap -- 10, matches kit's row gap exactly
	local VISIBLE_ROWS = 5
	local ROWS_VIEWPORT_H = VISIBLE_ROWS * ROW_H + (VISIBLE_ROWS - 1) * ROW_GAP -- 480
	local BODY_CONTENT_H = TAB_H + TABS_TO_ROWS_GAP + ROWS_VIEWPORT_H
	local BODY_H = T.pad.panel * 2 + BODY_CONTENT_H
	local GROUP_H = BODY_TOP + BODY_H

	local ICON_W = 60
	local ROW_GAP_INNER = 10 -- kit "gap 10" between icon / centre column / reward chip / action button
	local ACTION_W, ACTION_H = 136, 60
	local CHIP_H = 52
	local CHIP_ICON_W = 30
	local CHIP_PAD_L, CHIP_PAD_R, CHIP_GAP = 10, 12, 8
	local ROW_PAD_X = 12 -- kit "padding 0 12"
	-- The rows scroll reserves its own bar width (VerticalScrollBarInset,
	-- below) instead of floating the bar over the rows: with a full slate of
	-- quests the bar used to land ON TOP of the right-hand action buttons,
	-- because the rows were sized to the scroll's whole width. Counted here so
	-- the row flex math and the reserved strip can never drift apart.
	local SCROLLBAR_W = 10
	local ROW_CONTENT_W = PANEL_W - T.pad.panel * 2 - SCROLLBAR_W - ROW_PAD_X * 2

	----------------------------------------------------------- module-local state (server-confirmed only)
	local activeTab = ctx.state.goals.tab or "Daily"
	local dailyQuests: { any } = {}
	local goalsQuests: { any } = {}
	local seasonIds: { string } = {}
	local seasonProgress: { [string]: any } = {}

	----------------------------------------------------------- root
	local wrapper = Instance.new("Frame")
	wrapper.Name = "GoalsPanel"
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

	----------------------------------------------------------- header (common shell, README §3) -- green since the 1d/1e sweep
	local header = UI.surface(panelCol, UDim2.fromOffset(PANEL_W, HEADER_H), "purple", T.radius.panel, T.stroke.panel)
	header.Name = "Header"
	header.Position = UDim2.fromOffset(0, 0)
	header.ZIndex = 12
	-- 1d/1e sweep (2026-08-04): Goals' accent is green (#7be04e -> #3fae1f);
	-- the "purple" kind above is only the seed gradient. Recolored IN PLACE --
	-- the exact FindFirstChildOfClass pattern DailyPanel's header ships (its
	-- purple has no UI.surface kind either). One UIGradient per surface, so
	-- the lookup is unambiguous.
	local headerGrad = header:FindFirstChildOfClass("UIGradient")
	if headerGrad then
		headerGrad.Color = ColorSequence.new(HEADER_TOP, HEADER_BOT)
	end
	UI.gloss(header, T.radius.panel)
	UI.hardShadow(header, T.shadowOffset.panel, T.radius.panel)

	-- icon-slot backing plate -- kit-token gap, see module header. 1d/1e sweep
	-- (2026-08-04): retinted from the purple pair (#F0D2FF -> #DDB2F6) to a
	-- light-green pair at the same lightness, so the plate keeps tracking the
	-- header accent the way it always did. Structure untouched.
	local iconPlate = Instance.new("Frame")
	iconPlate.Name = "SectionIconPlate"
	iconPlate.AnchorPoint = Vector2.new(0, 0.5)
	iconPlate.Position = UDim2.new(0, 12, 0.5, 0)
	iconPlate.Size = UDim2.fromOffset(62, 62)
	iconPlate.BackgroundColor3 = T.color.white
	iconPlate.BorderSizePixel = 0
	iconPlate.ZIndex = header.ZIndex + 1
	iconPlate.Parent = header
	UI.corner(iconPlate, T.radius.small)
	local iconPlateGradient = Instance.new("UIGradient")
	iconPlateGradient.Rotation = 90
	iconPlateGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, T.hex("#DFF7D2")),
		ColorSequenceKeypoint.new(1, T.hex("#B9EBA2")),
	})
	iconPlateGradient.Parent = iconPlate
	UI.stroke(iconPlate, T.stroke.control)

	local headerIcon = UI.artSlot(iconPlate, UDim2.new(1, -10, 1, -10), T.icons.goals)
	headerIcon.Name = "SectionIcon"
	headerIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	headerIcon.Position = UDim2.fromScale(0.5, 0.5)
	headerIcon.ZIndex = iconPlate.ZIndex + 2

	local headerTitle = UI.label(header, "Goals", "panelTitle", T.color.white)
	headerTitle.Name = "Title"
	headerTitle.AnchorPoint = Vector2.new(0, 0.5)
	headerTitle.Position = UDim2.new(0, 12 + 62 + 14, 0.5, 0)
	headerTitle.ZIndex = header.ZIndex + 2

	local closeBtn = UI.button(header, "X", "red", UDim2.fromOffset(T.size.closeButton.X, T.size.closeButton.Y), "buttonL")
	closeBtn.Name = "CloseButton"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -12, 0.5, 0)
	closeBtn.ZIndex = header.ZIndex + 2

	-- refresh chip -- kit-token gap, see module header. 1d/1e sweep
	-- (2026-08-04): dark purple (#5B1D8C -> #3A0F5C) retinted to dark green
	-- (#1E6E10 -> #124708) + pale-green label. It STAYS a dark chip: this is
	-- header furniture, the same archetype as DailyPanel's dark timer pill --
	-- never flipped white. The white countdown value below stays white for
	-- the same reason (it sits ON the dark chip).
	local REFRESH_W, REFRESH_H = 190, 58
	local refreshChip = Instance.new("Frame")
	refreshChip.Name = "RefreshChip"
	refreshChip.AnchorPoint = Vector2.new(1, 0.5)
	refreshChip.Position = UDim2.new(1, -12 - T.size.closeButton.X - 14, 0.5, 0)
	refreshChip.Size = UDim2.fromOffset(REFRESH_W, REFRESH_H)
	refreshChip.BackgroundColor3 = T.color.white
	refreshChip.BorderSizePixel = 0
	refreshChip.ZIndex = header.ZIndex + 2
	refreshChip.Parent = header
	UI.corner(refreshChip, T.radius.small)
	local refreshGradient = Instance.new("UIGradient")
	refreshGradient.Rotation = 90
	refreshGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, T.hex("#1E6E10")),
		ColorSequenceKeypoint.new(1, T.hex("#124708")),
	})
	refreshGradient.Parent = refreshChip
	UI.stroke(refreshChip, T.stroke.control)

	local refreshLabel = UI.label(refreshChip, "REFRESH", "meta", T.hex("#D6F5C8"))
	refreshLabel.Name = "RefreshLabel"
	refreshLabel.AnchorPoint = Vector2.new(0, 0.5)
	refreshLabel.Position = UDim2.new(0, 12, 0.5, -12)
	refreshLabel.Size = UDim2.new(1, -24, 0, 16)
	refreshLabel.AutomaticSize = Enum.AutomaticSize.None
	refreshLabel.TextXAlignment = Enum.TextXAlignment.Left
	refreshLabel.ZIndex = refreshChip.ZIndex + 1

	local refreshValue = UI.label(refreshChip, "00:00:00", "cardLabel", T.color.white)
	refreshValue.Name = "RefreshValue"
	refreshValue.AnchorPoint = Vector2.new(0, 0.5)
	refreshValue.Position = UDim2.new(0, 12, 0.5, 12)
	refreshValue.Size = UDim2.new(1, -24, 0, 22)
	refreshValue.AutomaticSize = Enum.AutomaticSize.None
	refreshValue.TextXAlignment = Enum.TextXAlignment.Left
	refreshValue.ZIndex = refreshChip.ZIndex + 1

	----------------------------------------------------------- body (common shell, README §3) -- cream since the 1d/1e sweep
	-- 1d/1e sweep (2026-08-04): UI.panel (dark "panel" surface) -> the cream
	-- surface DailyPanel ships. UI.panel BUNDLED the hard shadow and a 16px
	-- UIPadding, so both are rebuilt by hand below. The padding MUST stay
	-- T.pad.panel (16), NOT DailyPanel's panelWide (18): BODY_H, BODY_INNER_W
	-- -> TAB_W, and ROW_CONTENT_W are all measured against 16 -- copying
	-- Daily's 18 would shift every child 2px and overflow the row flex math.
	-- The panel outline keeps the kit ink stroke (the tan #e5d3ac border is
	-- for cards INSIDE the body only, per the cream recipe).
	local body = UI.surface(panelCol, UDim2.fromOffset(PANEL_W, BODY_H), "cream", T.radius.panel, T.stroke.panel)
	body.Name = "Body"
	body.Position = UDim2.fromOffset(0, BODY_TOP)
	body.ZIndex = 12
	UI.hardShadow(body, T.shadowOffset.panel, T.radius.panel)
	local bodyPad = Instance.new("UIPadding")
	bodyPad.PaddingTop = UDim.new(0, T.pad.panel)
	bodyPad.PaddingBottom = UDim.new(0, T.pad.panel)
	bodyPad.PaddingLeft = UDim.new(0, T.pad.panel)
	bodyPad.PaddingRight = UDim.new(0, T.pad.panel)
	bodyPad.Parent = body

	----------------------------------------------------------- tabs
	local TAB_DEFS = { "Daily", "Goals", "Season" }
	local tabsRow = Instance.new("Frame")
	tabsRow.Name = "Tabs"
	tabsRow.Position = UDim2.fromOffset(0, 0)
	tabsRow.Size = UDim2.new(1, 0, 0, TAB_H)
	tabsRow.BackgroundTransparency = 1
	tabsRow.ZIndex = 14
	tabsRow.Parent = body

	local tabButtons: { [string]: TextButton } = {}
	local tabRings: { [string]: Frame } = {}

	local BODY_INNER_W = PANEL_W - T.pad.panel * 2
	local TAB_W = (BODY_INNER_W - TAB_GAP * 2) / 3

	for i, id in ipairs(TAB_DEFS) do
		local btn = UI.button(tabsRow, id, "tab", UDim2.fromOffset(TAB_W, TAB_H), "buttonM")
		btn.Name = "Tab" .. id
		btn.Position = UDim2.fromOffset((i - 1) * (TAB_W + TAB_GAP), 0)
		btn.ZIndex = 14
		btn.Parent = tabsRow
		tabButtons[id] = btn

		-- 1d/1e sweep (2026-08-04): the olive "tab" chip goes white-card on
		-- the cream body -- recolored IN PLACE, zero wiring. NOTE the target:
		-- FindFirstChildOfClass on the BUTTON hits its border UIStroke; the
		-- label's contextual text stroke lives on the TextLabel child and
		-- stays ink (the same brown-ink-with-ink-stroke combo Daily's tinted
		-- card labels ship). Gloss/Shade strips stay: white gloss on white is
		-- invisible and the 0.82-transparency shade reads as a subtle bottom
		-- bevel. The gold active ring below is untouched -- it pops harder on
		-- white than it ever did on olive.
		local tabGrad = btn:FindFirstChildOfClass("UIGradient")
		if tabGrad then
			tabGrad.Color = ColorSequence.new(Color3.new(1, 1, 1))
		end
		local tabStroke = btn:FindFirstChildOfClass("UIStroke")
		if tabStroke then
			tabStroke.Color = CARD_BORDER
			tabStroke.Thickness = 3
		end
		local tabLabel = btn:FindFirstChildOfClass("TextLabel")
		if tabLabel then
			tabLabel.TextColor3 = BODY_INK
		end

		-- static active-state ring (kit README §3.6 "active gold ring") --
		-- same inset/radius convention as UIKit.Builders.claimRing, but NO
		-- pulse tween: this is a persistent selection indicator, not a
		-- claimable-now affordance.
		local ring = Instance.new("Frame")
		ring.Name = "ActiveRing"
		ring.Size = UDim2.new(1, 8, 1, 8)
		ring.Position = UDim2.fromOffset(-4, -4)
		ring.BackgroundTransparency = 1
		ring.Visible = false
		ring.ZIndex = btn.ZIndex + 3
		ring.Parent = btn
		UI.corner(ring, T.radius.control + 3)
		local ringStroke = Instance.new("UIStroke")
		ringStroke.Thickness = 4
		ringStroke.Color = T.color.activeRing
		ringStroke.Parent = ring
		tabRings[id] = ring
	end

	----------------------------------------------------------- rows scroll region
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "RowsScroll"
	scroll.Position = UDim2.fromOffset(0, TAB_H + TABS_TO_ROWS_GAP)
	scroll.Size = UDim2.new(1, 0, 0, ROWS_VIEWPORT_H)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = SCROLLBAR_W
	-- Inset the canvas by the bar rather than overlaying it on the rows.
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	-- 1d/1e sweep (2026-08-04): the kit's sage thumb all but vanished on
	-- cream; #c9b585 is the tan card-border's darker sibling. Cosmetic only.
	scroll.ScrollBarImageColor3 = Color3.fromHex("#c9b585")
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ElasticBehavior = Enum.ElasticBehavior.Never
	scroll.ZIndex = 14
	scroll.Parent = body

	local rowsList = Instance.new("UIListLayout")
	rowsList.FillDirection = Enum.FillDirection.Vertical
	rowsList.SortOrder = Enum.SortOrder.LayoutOrder
	rowsList.Padding = UDim.new(0, ROW_GAP)
	rowsList.Parent = scroll

	----------------------------------------------------------- idle-bob driver (ONE Heartbeat, shared by every rendered Claim button)
	local bobActive: { { frame: Frame, base: UDim2 } } = {}
	local bobConn: RBXScriptConnection? = nil

	local function stopBobDriver()
		if bobConn then
			bobConn:Disconnect()
			bobConn = nil
		end
		-- Park every live button back on its base position. The driver writes
		-- Position every frame, so whatever offset the final frame happened to
		-- write would otherwise stay frozen there -- a Claim button sitting a
		-- few px out of line with its neighbours from the moment the panel
		-- closes until the driver's next tick after it reopens.
		for i = #bobActive, 1, -1 do
			local e = bobActive[i]
			if e.frame.Parent then
				e.frame.Position = e.base
			else
				table.remove(bobActive, i)
			end
		end
	end

	local function ensureBobDriver()
		if bobConn or not wrapper.Visible then
			return
		end
		local clock = 0
		bobConn = RunService.Heartbeat:Connect(function(dt)
			if not wrapper.Visible then
				stopBobDriver()
				return
			end
			clock += dt
			for i = #bobActive, 1, -1 do
				local e = bobActive[i]
				if not e.frame.Parent then
					table.remove(bobActive, i) -- pruned: row rebuilt/destroyed since this entry registered
				else
					local off = math.sin(clock / T.tween.bobPeriod * (2 * math.pi)) * 5
					e.frame.Position = UDim2.new(e.base.X.Scale, e.base.X.Offset, e.base.Y.Scale, e.base.Y.Offset + off)
				end
			end
			if #bobActive == 0 then
				stopBobDriver()
			end
		end)
	end

	local function registerBob(frame: Frame)
		table.insert(bobActive, { frame = frame, base = frame.Position })
		ensureBobDriver()
	end

	----------------------------------------------------------- reward chip + icon slot + action button builders
	local function measureChipWidth(text: string): number
		local spec = T.text.cardLabel
		local textW = TextService:GetTextSize(text, spec[1], Enum.Font.FredokaOne, Vector2.new(1000, spec[1] + 24)).X
		return CHIP_PAD_L + CHIP_ICON_W + CHIP_GAP + textW + CHIP_PAD_R
	end

	-- widthOverride: every row on a tab is built at the SAME chip width (the
	-- widest that tab needs -- see the renderers), so the progress tracks to
	-- their left all end on one vertical line instead of stepping in and out
	-- row by row with the length of the reward text.
	local function buildRewardChip(parent: Frame, iconKey: string, text: string, widthOverride: number?): (Frame, number)
		local w = math.max(measureChipWidth(text), widthOverride or 0)
		local chip = UI.surface(parent, UDim2.fromOffset(w, CHIP_H), "track", T.radius.small, T.stroke.control)
		chip.Name = "RewardChip"
		chip.ZIndex = parent.ZIndex + 1

		-- "darrel" has no Tokens.icons entry (he is not part of the kit), so an
		-- artSlot would render an empty box here. Fall back to the drawn version
		-- the HUD pill and egg shop already use, keeping one face for the currency
		-- everywhere it is shown.
		local icon: GuiObject
		local iconId = T.icons[iconKey]
		if (iconId and iconId ~= "") or not (IconArt and IconArt.has(iconKey)) then
			icon = UI.artSlot(chip, UDim2.fromOffset(CHIP_ICON_W, CHIP_ICON_W), iconId)
		else
			local host = Instance.new("Frame")
			host.Size = UDim2.fromOffset(CHIP_ICON_W, CHIP_ICON_W)
			host.BackgroundTransparency = 1
			host.Parent = chip
			IconArt.draw(host, iconKey, CHIP_ICON_W, chip.ZIndex + 1)
			icon = host
		end
		icon.Name = "CurrencyIcon"
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, CHIP_PAD_L, 0.5, 0)
		icon.ZIndex = chip.ZIndex + 1

		local value = UI.label(chip, text, "cardLabel", T.color.white)
		value.Name = "Value"
		value.AnchorPoint = Vector2.new(0, 0.5)
		value.Position = UDim2.new(0, CHIP_PAD_L + CHIP_ICON_W + CHIP_GAP, 0.5, 0)
		value.Size = UDim2.new(1, -(CHIP_PAD_L + CHIP_ICON_W + CHIP_GAP + CHIP_PAD_R), 0, 24)
		value.AutomaticSize = Enum.AutomaticSize.None
		value.TextXAlignment = Enum.TextXAlignment.Left
		value.ZIndex = chip.ZIndex + 1

		return chip, w
	end

	local function buildIconSlot(parent: Frame, imageId: string?, emoji: string?): Frame
		local slot = UI.surface(parent, UDim2.fromOffset(ICON_W, ICON_W), "slot", T.radius.small, T.stroke.control)
		slot.Name = "IconSlot"
		slot.ZIndex = parent.ZIndex + 1
		-- 1d/1e sweep (2026-08-04): dark "slot" backing -> white mini-card.
		-- This is card-internal BACKING, not a currency chip (those stay dark
		-- below) -- and the very same goals icon already reads fine on the
		-- header's light plate. Season's full-colour emoji glyphs read fine on
		-- white too. Recolored in place; art/emoji structure untouched.
		local slotGrad = slot:FindFirstChildOfClass("UIGradient")
		if slotGrad then
			slotGrad.Color = ColorSequence.new(Color3.new(1, 1, 1))
		end
		local slotStroke = slot:FindFirstChildOfClass("UIStroke")
		if slotStroke then
			slotStroke.Color = CARD_BORDER
			slotStroke.Thickness = 3
		end
		if emoji then
			local glyph = UI.label(slot, emoji, "buttonL", T.color.white)
			glyph.Name = "Glyph"
			glyph.AnchorPoint = Vector2.new(0.5, 0.5)
			glyph.Position = UDim2.fromScale(0.5, 0.5)
			glyph.Size = UDim2.fromScale(1, 1)
			glyph.AutomaticSize = Enum.AutomaticSize.None
			glyph.TextXAlignment = Enum.TextXAlignment.Center
			glyph.ZIndex = slot.ZIndex + 1
		else
			local art = UI.artSlot(slot, UDim2.new(1, -8, 1, -8), imageId)
			art.Name = "Art"
			art.AnchorPoint = Vector2.new(0.5, 0.5)
			art.Position = UDim2.fromScale(0.5, 0.5)
			art.ZIndex = slot.ZIndex + 1
		end
		return slot
	end

	-- "claimed" is built by hand (not UI.button) because UI.button forces
	-- white label text for every non-"disabled" variant, and a Claimed state
	-- needs a muted label -- unreachable through UI.button's variant map.
	-- That reason predates the restyle and survives it. 1d/1e sweep
	-- (2026-08-04): the old dark subPanel chip (#4A5840->#2E3825 + #9FAE8B
	-- text) is now DailyPanel's claimed-card palette VERBATIM (#e9f7e4 bg /
	-- #bfe3b1 border / #6da35e text) so "claimed = soft green" is one
	-- language across every cream panel. Flat colour, so the old gradient is
	-- simply not created; still exactly ONE UI.stroke call on this Frame.
	local function buildClaimedButton(parent: Frame): Frame
		local b = Instance.new("Frame")
		b.Name = "ClaimedButton"
		b.Size = UDim2.fromOffset(ACTION_W, ACTION_H)
		b.BackgroundColor3 = CLAIMED_BG
		b.BorderSizePixel = 0
		b.ZIndex = parent.ZIndex + 1
		b.Parent = parent
		UI.corner(b, T.radius.control)
		local st = UI.stroke(b, 3)
		st.Color = CLAIMED_BORDER
		local l = UI.label(b, "Claimed \u{2713}", "cardLabel", CLAIMED_TEXT)
		l.Size = UDim2.fromScale(1, 1)
		l.AutomaticSize = Enum.AutomaticSize.None
		l.TextXAlignment = Enum.TextXAlignment.Center
		l.ZIndex = b.ZIndex + 1
		return b
	end

	-- kind: "claim" | "inprogress" | "claimed" | "view"
	local function buildActionButton(parent: Frame, kind: string, onClaim: (() -> ())?, onView: (() -> ())?): Frame
		if kind == "claim" then
			-- Bob offset is applied to this wrapper Frame's Position, NEVER
			-- to the button's own Position -- UI.button's hover/press tweens
			-- already animate the button's Position relative to (0,0) inside
			-- this wrapper, and driving both the wrapper AND the button off
			-- the same property every frame would make the two animations
			-- fight each other. Splitting them onto two different Instances'
			-- Position properties keeps hover/press and idle-bob independent.
			local slot = Instance.new("Frame")
			slot.Name = "ClaimBobSlot"
			slot.Size = UDim2.fromOffset(ACTION_W, ACTION_H)
			slot.BackgroundTransparency = 1
			slot.ZIndex = parent.ZIndex + 1
			slot.Parent = parent
			local btn = UI.button(slot, "Claim", "green", UDim2.fromOffset(ACTION_W, ACTION_H), "buttonM")
			btn.Position = UDim2.fromOffset(0, 0)
			btn.ZIndex = slot.ZIndex + 1
			-- The ONE QuestClaim:FireServer call site in this module. No
			-- local state mutation -- the row only re-renders CLAIMED once
			-- the server pushes a fresh QuestState with Claimed == true.
			if onClaim then
				btn.MouseButton1Click:Connect(onClaim)
			end
			-- NOT registered here: the caller has not positioned this slot yet.
			-- registerBob snapshots frame.Position as the bob's base, so
			-- registering now captures the default (0, 0) and the driver then
			-- overwrites the real position every frame -- which is exactly what
			-- shot every Claim button clean out of its row and left it bobbing
			-- off the left edge of the panel. Handed back to buildQuestRow,
			-- which registers it once it is in place.
			return slot, slot
		elseif kind == "claimed" then
			return buildClaimedButton(parent)
		elseif kind == "view" then
			local btn = UI.button(parent, "VIEW", "blue", UDim2.fromOffset(ACTION_W, ACTION_H), "buttonM")
			btn.Name = "ViewButton"
			btn.ZIndex = parent.ZIndex + 1
			if onView then
				btn.MouseButton1Click:Connect(onView)
			end
			return btn
		else -- "inprogress"
			local btn = UI.button(parent, "In progress", "disabled", UDim2.fromOffset(ACTION_W, ACTION_H), "cardLabel")
			btn.Name = "InProgressButton"
			btn.ZIndex = parent.ZIndex + 1
			return btn
		end
	end

	----------------------------------------------------------- quest row (shared by all 3 tabs)
	type RowVM = {
		Icon: string?,
		Emoji: string?,
		Title: string,
		Progress: number,
		Target: number,
		MetaOverride: string?,
		RewardIconKey: string,
		RewardText: string,
		Action: string, -- "claim" | "inprogress" | "claimed" | "view"
		ChipW: number?, -- shared reward-chip width for the whole tab
		OnClaim: (() -> ())?,
	}

	local function buildQuestRow(order: number, vm: RowVM)
		-- RowSlot wrapper (PassPanel report bug 3's HardShadow-in-UIListLayout
		-- trap): KEPT through the 1d/1e sweep even though the card's hard
		-- shadow is now gone -- the wrapper is the rows list's one-child-per-
		-- quest contract, and the only safe place to hang shadow-like or
		-- overhang siblings should any come back.
		local slot = Instance.new("Frame")
		slot.Name = "RowSlot" .. order
		slot.LayoutOrder = order
		slot.Size = UDim2.new(1, 0, 0, ROW_H)
		slot.BackgroundTransparency = 1
		slot.ZIndex = 15
		slot.Parent = scroll

		local card = UI.surface(slot, UDim2.new(1, 0, 1, 0), "row", T.radius.control, T.stroke.control)
		card.Name = "Card"
		card.ZIndex = 15
		-- 1d/1e sweep (2026-08-04): olive "row" card -> white card with the
		-- tan border, recolored IN PLACE (the surface's own gradient/stroke;
		-- one of each exists). The UI.hardShadow call is DROPPED -- never
		-- created, not destroyed post-hoc (hardShadow wires Position/
		-- Destroying connections that must not be half-torn) -- matching
		-- Daily's flat-on-cream card language.
		local cardGrad = card:FindFirstChildOfClass("UIGradient")
		if cardGrad then
			cardGrad.Color = ColorSequence.new(Color3.new(1, 1, 1))
		end
		local cardStroke = card:FindFirstChildOfClass("UIStroke")
		if cardStroke then
			cardStroke.Color = CARD_BORDER
			cardStroke.Thickness = 3
		end

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, ROW_PAD_X)
		pad.PaddingRight = UDim.new(0, ROW_PAD_X)
		pad.Parent = card

		local icon = buildIconSlot(card, vm.Icon, vm.Emoji)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 0, 0.5, 0)

		local reward, chipW = buildRewardChip(card, vm.RewardIconKey, vm.RewardText, vm.ChipW)
		reward.AnchorPoint = Vector2.new(1, 0.5)
		reward.Position = UDim2.new(1, -(ACTION_W + ROW_GAP_INNER), 0.5, 0)

		local action, bobFrame = buildActionButton(card, vm.Action, vm.OnClaim, vm.OnClaim)
		action.AnchorPoint = Vector2.new(1, 0.5)
		action.Position = UDim2.new(1, 0, 0.5, 0)
		-- Only now that AnchorPoint/Position are final -- see buildActionButton.
		if bobFrame then
			registerBob(bobFrame)
		end

		local centerX = ICON_W + ROW_GAP_INNER
		local centerW = ROW_CONTENT_W - ICON_W - ROW_GAP_INNER - chipW - ROW_GAP_INNER - ACTION_W - ROW_GAP_INNER
		local centerCol = Instance.new("Frame")
		centerCol.Name = "CenterColumn"
		centerCol.AnchorPoint = Vector2.new(0, 0.5)
		centerCol.Position = UDim2.new(0, centerX, 0.5, 0)
		centerCol.Size = UDim2.fromOffset(math.max(centerW, 40), 52) -- title 24 + 4 gap + track 24, so the pair sits dead centre in the row
		centerCol.BackgroundTransparency = 1
		centerCol.ZIndex = 15
		centerCol.Parent = card

		-- 1d/1e sweep (2026-08-04): the title reads against the white card
		-- now -- body ink, not white (its ink contextual text stroke stays,
		-- same as Daily's tinted card labels). The meta label further down
		-- stays WHITE: it sits on the dark/green progress track, a colored
		-- sub-surface, exactly like the reward chip's white value text.
		local title = UI.label(centerCol, vm.Title, "cardLabel", BODY_INK)
		title.Name = "Title"
		title.Position = UDim2.fromOffset(0, 0)
		title.Size = UDim2.new(1, 0, 0, 24)
		title.AutomaticSize = Enum.AutomaticSize.None
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextTruncate = Enum.TextTruncate.AtEnd
		title.ZIndex = 16

		local track, fill = UI.track(centerCol, UDim2.new(1, 0, 0, 24), "green", T.radius.pill)
		track.Name = "ProgressTrack"
		track.Position = UDim2.fromOffset(0, 28)
		track.ZIndex = 16
		local pct = vm.Target > 0 and (vm.Progress / vm.Target) or 0
		UI.setFill(fill, pct, false)

		local metaText = vm.MetaOverride or string.format("%d / %d", vm.Progress, vm.Target)
		local meta = UI.label(track, metaText, "meta", T.color.white)
		meta.Name = "MetaLabel"
		meta.AnchorPoint = Vector2.new(0.5, 0.5)
		meta.Position = UDim2.fromScale(0.5, 0.5)
		meta.Size = UDim2.fromScale(1, 1)
		meta.AutomaticSize = Enum.AutomaticSize.None
		meta.TextXAlignment = Enum.TextXAlignment.Center
		meta.ZIndex = track.ZIndex + 3
	end

	local function clearRows()
		for _, c in ipairs(scroll:GetChildren()) do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		-- Every registered bob belonged to a row that just went away. The
		-- driver prunes destroyed frames on its own next tick, but clearing
		-- here means a re-render never carries a frame's worth of dead entries
		-- and a tab switch off Goals lets the driver stop immediately.
		table.clear(bobActive)
	end

	----------------------------------------------------------- per-tab renderers
	local function renderDaily()
		clearRows()
		-- One chip width for the whole tab: the widest reward it has to show.
		local chipW = 0
		for _, q in ipairs(dailyQuests) do
			chipW = math.max(chipW, measureChipWidth("+" .. tostring(q.Reward or 0)))
		end
		for i, q in ipairs(dailyQuests) do
			buildQuestRow(i, {
				ChipW = chipW,
				Icon = T.icons.goals,
				Title = q.Text or "",
				Progress = q.Progress or 0,
				Target = q.Target or 1,
				RewardIconKey = "darrel", -- daily egg-quests pay darrels, not a generic gem
				RewardText = "+" .. tostring(q.Reward or 0),
				Action = q.Claimed and "claimed" or "inprogress",
			})
		end
	end

	local function renderGoals()
		clearRows()
		local chipW = 0
		for _, q in ipairs(goalsQuests) do
			chipW = math.max(chipW, measureChipWidth(shortCash(q.Reward or 0)))
		end
		for i, q in ipairs(goalsQuests) do
			local met = q.Met == true
			local claimed = q.Claimed == true
			buildQuestRow(i, {
				ChipW = chipW,
				Icon = T.icons.goals,
				Title = q.Desc or "",
				Progress = met and 1 or 0,
				Target = 1,
				MetaOverride = claimed and "CLAIMED" or (met and "COMPLETE" or "LOCKED"),
				RewardIconKey = "coin",
				RewardText = shortCash(q.Reward or 0),
				Action = claimed and "claimed" or (met and "claim" or "inprogress"),
				OnClaim = (met and not claimed) and function()
					ctx.remotes.QuestClaim:FireServer(q.Id)
				end or nil,
			})
		end
	end

	local function renderSeason()
		clearRows()
		local chipW = 0
		for _, qid in ipairs(seasonIds) do
			local d = SeasonConfig.PoolById[qid]
			if d then
				chipW = math.max(chipW, measureChipWidth("+" .. tostring(d.XP) .. " XP"))
			end
		end
		local order = 0
		for _, qid in ipairs(seasonIds) do
			local def = SeasonConfig.PoolById[qid]
			if def then
				order += 1
				local pr = seasonProgress[qid] or { P = 0, D = false }
				buildQuestRow(order, {
					ChipW = chipW,
					Emoji = def.Icon,
					Title = def.Name,
					Progress = pr.P or 0,
					Target = def.Target,
					MetaOverride = pr.D and "DONE" or nil,
					RewardIconKey = "pass",
					RewardText = "+" .. tostring(def.XP) .. " XP",
					Action = "view",
					OnClaim = function()
						ctx.openPanel("pass")
					end,
				})
			end
		end
	end

	local RENDERERS = { Daily = renderDaily, Goals = renderGoals, Season = renderSeason }

	local function updateTabVisuals()
		for id, btn in pairs(tabButtons) do
			tabRings[id].Visible = (id == activeTab)
			btn.ZIndex = (id == activeTab) and 15 or 14
		end
	end

	local function switchTab(id: string)
		if not RENDERERS[id] then
			return
		end
		activeTab = id
		ctx.state.goals.tab = id
		updateTabVisuals()
		RENDERERS[id]() -- instant content swap (kit README §4)
	end

	for id, btn in pairs(tabButtons) do
		btn.MouseButton1Click:Connect(function()
			switchTab(id)
		end)
	end
	updateTabVisuals()

	----------------------------------------------------------- refresh countdown (1s loop, STRICTLY gated on wrapper.Visible)
	local countdownRunning = false
	local function tickCountdown()
		refreshValue.Text = formatHMS(nextMidnightRemaining(os.time()))
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

	----------------------------------------------------------- backdrop blur (1d/1e sweep 2026-08-04: dim + blur behind the panel)
	-- Copied from DailyPanel: the shell owns the dim scrim; the blur is
	-- per-panel and UNIQUELY NAMED -- Pass's Quests button opens THIS panel
	-- over Pass's close, so a shared BlurEffect name would let one panel's
	-- teardown destroy the other's live blur (setBlur finds by name). Size is
	-- SET, never tweened -- BlurEffect.Size is not on the proven tween
	-- whitelist in this place.
	local BLUR_NAME = "GoalsPanelBlur"
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

	----------------------------------------------------------- data wiring (server-confirmed only)
	local function applyDaily(daily)
		if typeof(daily) ~= "table" then
			return
		end
		dailyQuests = daily.Quests or {}
		if activeTab == "Daily" then
			renderDaily()
		end
	end

	ctx.remotes.DarrelUpdate.OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" then
			applyDaily(payload.Daily)
		end
	end)

	-- Pull once per open, same load-discriminator pattern GameHUDClient's own
	-- startup loop uses (task-4-report.md): DarrelState:InvokeServer() before
	-- the player's profile has loaded returns a real table whose `Daily`
	-- field is nil (a placeholder, not real data) -- keep retrying until
	-- `Daily` comes back as a table instead of trusting the first response.
	local function pullDarrelDaily()
		task.spawn(function()
			for _ = 1, 20 do
				if not wrapper.Visible then
					return
				end
				local ok, res = pcall(function()
					return ctx.remotes.DarrelState:InvokeServer()
				end)
				if ok and typeof(res) == "table" and typeof(res.Daily) == "table" then
					applyDaily(res.Daily)
					return
				end
				task.wait(1)
			end
		end)
	end

	ctx.remotes.QuestState.OnClientEvent:Connect(function(quests)
		if typeof(quests) ~= "table" then
			return
		end
		goalsQuests = quests
		if activeTab == "Goals" then
			renderGoals()
		end
	end)

	-- Server-confirmed only: `seasonIds`/`seasonProgress` are only ever
	-- replaced wholesale from a SeasonState push, mirroring PassPanel's own
	-- state-writing discipline for the same remote.
	ctx.remotes.SeasonState.OnClientEvent:Connect(function(s)
		if typeof(s) ~= "table" then
			return
		end
		seasonIds = s.QuestIds or {}
		seasonProgress = s.Progress or {}
		if activeTab == "Season" then
			renderSeason()
		end
	end)

	----------------------------------------------------------- wiring
	closeBtn.MouseButton1Click:Connect(function()
		ctx.closePanel()
	end)

	-- Fires every time the panel becomes visible: refreshes Season (mirrors
	-- SeasonClient/PassPanel's own open-time refresh), pulls a fresh Daily
	-- snapshot, starts the bob driver + countdown, and (1d/1e sweep
	-- 2026-08-04) raises/kills the backdrop blur. QuestState has no
	-- client-fire request path (QuestHandler only pushes on join + its own
	-- 3s poll) so Goals milestones rely on that passive push alone.
	wrapper:GetPropertyChangedSignal("Visible"):Connect(function()
		if wrapper.Visible then
			ctx.remotes.SeasonState:FireServer()
			pullDarrelDaily()
			ensureBobDriver()
			startCountdown()
			setBlur(true)
		else
			stopBobDriver()
			stopCountdown()
			setBlur(false)
		end
	end)

	-- Belt-and-braces blur teardown (1d/1e sweep 2026-08-04; same review
	-- catch DailyPanel carries): any path that hides the HOST while this
	-- wrapper stays Visible (legacy single-open force-closes, future shell
	-- changes) must still kill the BlurEffect -- it post-processes the WHOLE
	-- screen regardless of GUI visibility. Blur only: the bob/countdown
	-- loops predate this watcher and keep their own wrapper.Visible gating.
	ctx.host:GetPropertyChangedSignal("Visible"):Connect(function()
		if not ctx.host.Visible then
			setBlur(false)
		elseif wrapper.Visible then
			setBlur(true)
		end
	end)

	switchTab(activeTab) -- initial paint (zero/stale state) before the first server response lands

	return wrapper
end

return GoalsPanel
