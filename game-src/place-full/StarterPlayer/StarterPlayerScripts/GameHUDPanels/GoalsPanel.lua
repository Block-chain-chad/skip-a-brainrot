--!strict
-- GoalsPanel: kit README §3.6 Goals panel -- a GameHUDPanels consumer module
-- (StarterPlayer.StarterPlayerScripts.GameHUDPanels.GoalsPanel).
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
-- (#5B1D8C -> #3A0F5C bg, #E7C8FF label). Built via T.hex(...) (part of
-- Tokens' own public surface, same helper Tokens.lua uses internally to
-- build every other gradient) rather than a raw Color3 literal, so this
-- still reads as "Tokens/Builders only" per the task brief. Quest-row
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
-- quest row is wrapped in a non-list-managed "RowSlot" container that holds
-- both the visual row card AND its UI.hardShadow sibling -- the vertical
-- UIListLayout driving the rows scroll only ever sees one child per quest,
-- never the untracked shadow Frame UI.hardShadow parents alongside it.
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

function GoalsPanel.Build(ctx)
	local T = ctx.Tokens
	local UI = ctx.Builders
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
	local ROW_CONTENT_W = PANEL_W - T.pad.panel * 2 - ROW_PAD_X * 2

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

	----------------------------------------------------------- header (common shell, README §3) -- purple, quest surface
	local header = UI.surface(panelCol, UDim2.fromOffset(PANEL_W, HEADER_H), "purple", T.radius.panel, T.stroke.panel)
	header.Name = "Header"
	header.Position = UDim2.fromOffset(0, 0)
	header.ZIndex = 12
	UI.gloss(header, T.radius.panel)
	UI.hardShadow(header, T.shadowOffset.panel, T.radius.panel)

	-- icon-slot backing plate (#F0D2FF -> #DDB2F6, kit-token gap -- see module header)
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
		ColorSequenceKeypoint.new(0, T.hex("#F0D2FF")),
		ColorSequenceKeypoint.new(1, T.hex("#DDB2F6")),
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

	-- refresh chip (#5B1D8C -> #3A0F5C bg, #E7C8FF label -- kit-token gap, see module header)
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
		ColorSequenceKeypoint.new(0, T.hex("#5B1D8C")),
		ColorSequenceKeypoint.new(1, T.hex("#3A0F5C")),
	})
	refreshGradient.Parent = refreshChip
	UI.stroke(refreshChip, T.stroke.control)

	local refreshLabel = UI.label(refreshChip, "REFRESH", "meta", T.hex("#E7C8FF"))
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

	----------------------------------------------------------- body (common shell, README §3)
	local body = UI.panel(panelCol, UDim2.fromOffset(PANEL_W, BODY_H))
	body.Name = "Body"
	body.Position = UDim2.fromOffset(0, BODY_TOP)
	body.ZIndex = 12

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
	scroll.ScrollBarThickness = 10
	scroll.ScrollBarImageColor3 = T.color.scrollThumb
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

	local function buildRewardChip(parent: Frame, iconKey: string, text: string): (Frame, number)
		local w = measureChipWidth(text)
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
	-- white label text for every non-"disabled" variant, but the kit's
	-- Claimed state needs the muted #9FAE8B (T.color.textClaimed) label on
	-- the subPanel-gradient (#4A5840->#2E3825) background -- an exact
	-- token match kit §3.6 happens to share with the existing subPanel
	-- surface kind, just not reachable through UI.button's variant map.
	local function buildClaimedButton(parent: Frame): Frame
		local b = Instance.new("Frame")
		b.Name = "ClaimedButton"
		b.Size = UDim2.fromOffset(ACTION_W, ACTION_H)
		b.BackgroundColor3 = T.color.white
		b.BorderSizePixel = 0
		b.ZIndex = parent.ZIndex + 1
		b.Parent = parent
		UI.corner(b, T.radius.control)
		UI.gradient(b, T.gradient.subPanel)
		UI.stroke(b, T.stroke.control)
		local l = UI.label(b, "Claimed \u{2713}", "cardLabel", T.color.textClaimed)
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
			registerBob(slot)
			return slot
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
		OnClaim: (() -> ())?,
	}

	local function buildQuestRow(order: number, vm: RowVM)
		-- HardShadow-in-UIListLayout trap (see PassPanel report bug 3): the
		-- real card + its UI.hardShadow sibling both live inside this
		-- non-list-managed RowSlot, so rowsList's vertical UIListLayout only
		-- ever counts ONE child per quest.
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
		UI.hardShadow(card, T.shadowOffset.control, T.radius.control)

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, ROW_PAD_X)
		pad.PaddingRight = UDim.new(0, ROW_PAD_X)
		pad.Parent = card

		local icon = buildIconSlot(card, vm.Icon, vm.Emoji)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 0, 0.5, 0)

		local reward, chipW = buildRewardChip(card, vm.RewardIconKey, vm.RewardText)
		reward.AnchorPoint = Vector2.new(1, 0.5)
		reward.Position = UDim2.new(1, -(ACTION_W + ROW_GAP_INNER), 0.5, 0)

		local action = buildActionButton(card, vm.Action, vm.OnClaim, vm.OnClaim)
		action.AnchorPoint = Vector2.new(1, 0.5)
		action.Position = UDim2.new(1, 0, 0.5, 0)

		local centerX = ICON_W + ROW_GAP_INNER
		local centerW = ROW_CONTENT_W - ICON_W - ROW_GAP_INNER - chipW - ROW_GAP_INNER - ACTION_W - ROW_GAP_INNER
		local centerCol = Instance.new("Frame")
		centerCol.Name = "CenterColumn"
		centerCol.AnchorPoint = Vector2.new(0, 0.5)
		centerCol.Position = UDim2.new(0, centerX, 0.5, 0)
		centerCol.Size = UDim2.fromOffset(math.max(centerW, 40), 56)
		centerCol.BackgroundTransparency = 1
		centerCol.ZIndex = 15
		centerCol.Parent = card

		local title = UI.label(centerCol, vm.Title, "cardLabel", T.color.white)
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
	end

	----------------------------------------------------------- per-tab renderers
	local function renderDaily()
		clearRows()
		for i, q in ipairs(dailyQuests) do
			buildQuestRow(i, {
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
		for i, q in ipairs(goalsQuests) do
			local met = q.Met == true
			local claimed = q.Claimed == true
			buildQuestRow(i, {
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
		local order = 0
		for _, qid in ipairs(seasonIds) do
			local def = SeasonConfig.PoolById[qid]
			if def then
				order += 1
				local pr = seasonProgress[qid] or { P = 0, D = false }
				buildQuestRow(order, {
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
	-- snapshot, starts the bob driver + countdown. QuestState has no
	-- client-fire request path (QuestHandler only pushes on join + its own
	-- 3s poll) so Goals milestones rely on that passive push alone.
	wrapper:GetPropertyChangedSignal("Visible"):Connect(function()
		if wrapper.Visible then
			ctx.remotes.SeasonState:FireServer()
			pullDarrelDaily()
			ensureBobDriver()
			startCountdown()
		else
			stopBobDriver()
			stopCountdown()
		end
	end)

	switchTab(activeTab) -- initial paint (zero/stale state) before the first server response lands

	return wrapper
end

return GoalsPanel
