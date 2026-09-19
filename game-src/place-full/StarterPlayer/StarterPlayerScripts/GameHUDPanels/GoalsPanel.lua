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
-- 2026-08-05 GLITCH PASS (reported: the quests "glitch out and look weird").
-- FIVE defects, four layout + one hard crash. No new styling:
--   0. WHITE TEXT ON WHITE CARDS. The style replacement above was only half
--      applied: it deleted CARD_BORDER/BODY_INK but left all four cream-sweep
--      override blocks calling them, and the STYLE REPLACEMENT REPAIR that
--      followed stopped the resulting nil-global crash the cheap way -- by
--      re-declaring both constants as their guide successors (outline / WHITE
--      ink) and leaving the override blocks running. So every quest card, tab
--      chip and icon slot was still being force-painted PURE WHITE by those
--      leftovers, while the labels on them had just been flipped to white:
--      quest titles and tab names rendered invisible, readable only by their
--      contextual stroke. Finished the pass the way its own header always
--      said it would go -- the overrides are DELETED, so the surfaces inherit
--      Tokens' dark row/slot/tab families and white labels land on dark cards
--      -- and retinted the two header-furniture Frames + the scroll thumb,
--      which were still carrying the OLD GREEN header's palette onto the new
--      red one. CARD_BORDER/BODY_INK have no call sites left and are gone.
--   1. Every Claim button rendered OUTSIDE its row. buildActionButton called
--      registerBob(slot) before buildQuestRow had positioned the slot, so the
--      bob driver snapshotted the default (0,0) as its base and then rewrote
--      Position from that base every frame, overriding the real
--      AnchorPoint(1,0.5)/Position(1,0,0.5,0). Measured live: the button
--      landed 72px LEFT of the panel's own left edge and 17px above its row,
--      bobbing over the nav rail. registerBob now runs in buildQuestRow,
--      after positioning. (Same trap, same fix, as UI.button's own `rest`.)
--   2. stopBobDriver left the last frame's offset frozen on screen.
--   3. The scroll bar drew ON TOP of the action buttons once a tab had more
--      than VISIBLE_ROWS quests (rows were sized to the scroll's full width).
--   4. Reward chips were measured per-row, so every row's progress track
--      ended at a different x and the rows read as ragged. One width per tab.
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
--   DAILY  -- ServerScriptService.Modules.EmeraldService + remotes.EmeraldUpdate
--            (RemoteEvent, server->client push) / remotes.EmeraldState
--            (RemoteFunction, client->server pull, self-healing).
--     Both deliver the SAME shape: { Darrels = number, Daily = DailyState? }
--     DailyState = { Day = number, Quests = { { Id, Text, Reward, Target,
--       Progress, Claimed }, ... } }  (exactly 3 entries; EmeraldService
--     .slateFor(day) picks 3 from a 6-quest pool, same slate for everyone)
--     `Daily` is nil until the player's profile has loaded server-side --
--     EmeraldState's OnServerInvoke returns { Darrels = M.Get(player) (which
--     is 0 for an unloaded profile), Daily = M.GetDailyState(player) (which
--     is nil for an unloaded profile) }. A pull landing before the profile
--     loads is therefore a PLACEHOLDER, not real data -- GameHUDClient's own
--     startup-pull loop treats `typeof(res.Daily) == "table"` as the
--     loaded/not-loaded discriminator and keeps retrying until it sees a
--     table (see GameHUDClient ~line 374, "Bug C3 fix", and
--     task-4-report.md). This module reuses the exact same discriminator.
--     Server AUTO-CLAIMS (EmeraldService.Notify claims + awards the instant
--     Progress reaches Target, before ever pushing state) -- so the client
--     NEVER sees Progress>=Target with Claimed==false, and there is no
--     Daily claim remote at all. Reward currency is Darrels (the gem
--     pill's currency).
--
--   WEEKLY (2026-08-09) -- the SAME EmeraldService and the same two remotes, a
--            second field beside Daily: payload.Weekly = { Week, EndsAt,
--            Quests = { { Id, Kind, Text, Darrels, XP, Target, Progress,
--            Claimed }, ... } }, 3 entries, one slate for everyone, rolling
--            over MONDAY 00:00 UTC rather than at midnight.
--     Harder than the daily slate and pays TWO currencies at once -- emeralds
--     AND season XP -- which is why its rows carry two reward chips where
--     every other tab carries one (see RowVM.Reward2*). Auto-claimed server
--     side exactly like Daily, so there is no weekly claim remote either and
--     no row on this tab is ever actionable. EndsAt is unix seconds at the
--     next rollover, taken from the server rather than recomputed here so the
--     countdown cannot drift from the boundary that actually resets the slate.
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
-- renders "HH:MM:SS" to the next UTC midnight -- both Daily's emerald slate
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

-- Id is "goalsInner", NOT "goals": since 2026-08-07 this panel is a TAB inside
-- ProgressPanel rather than a rail destination of its own, and ProgressPanel is
-- what now answers to "goals". Both modules live in this folder and the registry
-- is keyed by Id, so sharing one would have them silently overwrite each other.
-- Nothing opens "goalsInner"; it registers harmlessly and is built by its host.
local GoalsPanel = { Id = "goalsInner" }

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

-- The weekly slate runs for seven days, and "163:12:04" is not an answer anyone
-- reads. Days split off the front; under a day this IS formatHMS, so the chip does
-- not change shape on the last day of the week.
local function formatDHMS(totalSeconds: number): string
	totalSeconds = math.max(0, math.floor(totalSeconds))
	local d = totalSeconds // 86400
	if d > 0 then
		return string.format("%dd %s", d, formatHMS(totalSeconds % 86400))
	end
	return formatHMS(totalSeconds)
end

-- Progress reads as a plain count for things you DO (rocks skipped, brainrots
-- caught) and as MONEY for the Collect quests: "$250K / $1.0M" rather than
-- "250000 / 1000000", which at weekly targets is seven digits against seven
-- digits in a 24px label. Kind comes straight off the server's own pool row
-- (EmeraldService.GetDailyState / GetWeeklyState). Returning nil is meaningful --
-- it falls the row back to its default "%d / %d".
local function questMeta(kind: string?, progress: number, target: number): string?
	if kind == "Collect" then
		return string.format("%s / %s", shortCash(progress), shortCash(target))
	end
	return nil
end

-- Pure so it's trivially probeable against a known epoch: nextMidnightRemaining(t)
-- for any t returns seconds until the next UTC day boundary. os.time() is
-- UTC-based in Roblox (server + client agree), matching EmeraldService.utcDay
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
-- on the light-grey window body -- the title is on the dark cool header, every
-- other label is on a dark slot, chip or progress track -- so the guide's
-- T.color.textOnWindow has no use site here and is not referenced.
local HEADER_TOP = Color3.fromHex("#42536B") -- PS99 cool header (was the red #F96B57)
local HEADER_BOT = Color3.fromHex("#2E3B4F")
local SLOT_TOP = Color3.fromHex("#3A4656") -- PS99 cool dark row, ONLY for the hand-built header furniture (icon plate + refresh chip)
local SLOT_BOT = Color3.fromHex("#2A3543")

-- opts.embedded: built as a tab inside ProgressPanel rather than as a panel in its
-- own right. It keeps its whole header (so nothing below has to change) but hides
-- it and starts the body at the top -- the host supplies the one header and the one
-- close button, and two stacked headers is exactly what a merged tab must not look
-- like.
-- 2026-08-10 INNER RESTYLE (design_handoff_hud_upgrade, PROGRESS/GOALS):
-- the embedded view now builds from the sheet's PanelChrome parts -- white
-- 140-tall rows on the shell's light ground, 80-tall gold/neutral sub-tabs,
-- violet reward chips (emeralds are violet everywhere), 210x82 state plates,
-- and the count ON the progress track. All VM/render/data code untouched.
local UIKitFolder = game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("UIKit")
local PC = require(UIKitFolder:WaitForChild("PanelChrome"))
local S = require(UIKitFolder:WaitForChild("SpecTheme"))

function GoalsPanel.Build(ctx, opts)
	local EMBEDDED = (type(opts) == "table" and opts.embedded == true)
	local T = ctx.Tokens
	local UI = ctx.Builders
	-- (The 2026-08-04 STYLE REPLACEMENT REPAIR's CARD_BORDER / BODY_INK
	-- re-declarations lived here. They existed only to keep the leftover
	-- cream-sweep override blocks from crashing on a nil global; those blocks
	-- are gone now -- see defect 0 in the module header -- so both constants
	-- have no call sites and are deleted with them.)
	-- Emerald's drawn face, for the Daily tab's reward chips. Not part of ctx
	-- (which carries only the kit's own Tokens/Builders), and pcall'd so a
	-- missing module costs an icon rather than the whole panel.
	local okIconArt, IconArt = pcall(function()
		return require(game:GetService("ReplicatedStorage").Modules.UIKit.IconArt)
	end)
	if not okIconArt then IconArt = nil end

	----------------------------------------------------------- geometry (kit README §3.6, exact where tokenised)
	-- panelWidth.goals is the SHELL's box (1140) since the HUD upgrade; the
	-- embedded content fits the shell body's inner width instead.
	local PANEL_W = EMBEDDED and 1020 or 860
	local HEADER_H = T.size.headerHeight -- 92
	local BODY_TOP = EMBEDDED and 0 or (HEADER_H + 12)
	local TAB_H = 80 -- sheet: body sub-tabs, visibly junior to the header pair
	local TAB_GAP = T.pad.gap -- 12 (kit gives no explicit tab gap; reusing the shared spacing-scale token, same convention PassPanel's reward-card column gap uses)
	-- RESET STRIP (2026-08-09). The header's REFRESH chip is real but INVISIBLE in
	-- the shipping layout: this panel hides its whole header when embedded in
	-- ProgressPanel, which is the only way it is ever opened. So the countdown gets a
	-- home inside the body, where it can actually be read.
	--
	-- It is paid for exactly: 4px off TAB_H plus the headroom this panel already had
	-- inside ProgressPanel's 598px content box (it stood at 580). New total 596.
	local RESET_H, RESET_GAP = 26, 6
	local TABS_TO_ROWS_GAP = 12
	local ROW_H = 140 -- sheet: quest row 140 tall
	local ROW_GAP = 16
	local ROWS_VIEWPORT_H = 428 -- fits the 1140x800 shell body; taller lists scroll
	local BODY_CONTENT_H = TAB_H + RESET_GAP + RESET_H + TABS_TO_ROWS_GAP + ROWS_VIEWPORT_H
	local BODY_H = T.pad.panel * 2 + BODY_CONTENT_H
	local GROUP_H = BODY_TOP + BODY_H

	local ICON_W = 78
	local ROW_GAP_INNER = 10 -- kit "gap 10" between icon / centre column / reward chip / action button
	local ACTION_W, ACTION_H = 210, 82 -- sheet: state plate 210x82
	local CHIP_H = 82                  -- sheet: reward chip 150x82
	local CHIP_MIN_W = 150
	local CHIP_ICON_W = 34
	local CHIP_PAD_L, CHIP_PAD_R, CHIP_GAP = 12, 14, 8
	local ROW_PAD_X = 16
	-- The rows scroll reserves its own bar width (VerticalScrollBarInset,
	-- below) instead of floating the bar over the rows: with a full slate of
	-- quests the bar used to land ON TOP of the right-hand action buttons,
	-- because the rows were sized to the scroll's whole width. Counted here so
	-- the row flex math and the reserved strip can never drift apart.
	local SCROLLBAR_W = 10
	local ROW_CONTENT_W = PANEL_W - T.pad.panel * 2 - SCROLLBAR_W - ROW_PAD_X * 2

	----------------------------------------------------------- module-local state (server-confirmed only)
	-- A profile that last had Season open would otherwise restore a tab that no longer
	-- exists, leaving the panel blank with no tab lit.
	local activeTab = ctx.state.goals.tab or "Daily"
	-- Kept in step with TAB_DEFS by hand: that list is declared with the tab row a
	-- few hundred lines down and this runs first.
	if activeTab ~= "Daily" and activeTab ~= "Weekly" and activeTab ~= "Goals" then
		activeTab = "Daily"
		ctx.state.goals.tab = activeTab
	end
	local dailyQuests: { any } = {}
	-- Unix seconds at the next daily rollover, from the server. Unlike the weekly one
	-- this HAS an exact local fallback (see resetCountdown), because midnight UTC is
	-- the same boundary computed either way.
	local dailyEndsAt: number? = nil
	local weeklyQuests: { any } = {}
	-- Unix seconds at the next weekly rollover, from the server. nil until the first
	-- payload lands, which is exactly when the countdown must NOT show a weekly
	-- number it would have had to invent.
	local weeklyEndsAt: number? = nil
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
	-- Built either way and merely HIDDEN when embedded: everything below refers to
	-- `header` and its children, so skipping the build would mean auditing several
	-- hundred lines for nil. Hidden it costs one invisible frame; with BODY_TOP at 0
	-- the body sits over the top of it and draws normally.
	header.Visible = not EMBEDDED
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

	-- icon-slot backing plate -- kit-token gap, see module header. Style
	-- replacement: the cream sweep's light-green pair (#DFF7D2 -> #B9EBA2)
	-- tracked a GREEN header that no longer exists -- the half-finished pass
	-- left it sitting on the new red one. It is the guide's dark slot pair
	-- now, matching every other slot in the panel. Structure untouched.
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
	iconPlateGradient.Color = ColorSequence.new(SLOT_TOP, SLOT_BOT)
	iconPlateGradient.Parent = iconPlate
	UI.stroke(iconPlate, T.stroke.control)

	local headerIcon = UI.artSlot(iconPlate, UDim2.new(1, 2, 1, 2), T.icons.goals)
	headerIcon.Name = "SectionIcon"
	headerIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	headerIcon.Position = UDim2.fromScale(0.5, 0.5)
	-- PS99 sticker treatment (2026-08-16): 52px -> 64px on the 62px plate,
	-- slight overhang + the lone-icon tilt, matching the nav rail's sticker
	-- language. artSlot is an ImageLabel and neither the plate nor the
	-- header clips, so both the overhang and the rotation draw in full.
	headerIcon.Rotation = -6
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

	-- refresh chip -- kit-token gap, see module header. Style replacement:
	-- the cream sweep's dark-green pair (#1E6E10 -> #124708) + pale-green
	-- label tracked the old green header and was left behind on the red one.
	-- The guide's dark slot pair + a muted label now. It STAYS a dark chip:
	-- header furniture, the same archetype as DailyPanel's dark timer pill --
	-- never flipped light. The white countdown value below stays white for
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
	refreshGradient.Color = ColorSequence.new(SLOT_TOP, SLOT_BOT)
	refreshGradient.Parent = refreshChip
	UI.stroke(refreshChip, T.stroke.control)

	local refreshLabel = UI.label(refreshChip, "REFRESH", "meta", T.color.textMutedOnDark)
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
	local body = UI.surface(panelCol, UDim2.fromOffset(PANEL_W, BODY_H), "window", T.radius.panel, T.stroke.panel)
	body.Name = "Body"
	body.Position = UDim2.fromOffset(0, BODY_TOP)
	body.ZIndex = 12
	if EMBEDDED then
		-- pure layout box: ProgressPanel's spec body is the visible ground
		body.BackgroundTransparency = 1
		local bg = body:FindFirstChildOfClass("UIGradient")
		if bg then bg:Destroy() end
		local bs = body:FindFirstChildOfClass("UIStroke")
		if bs then bs:Destroy() end
	else
		UI.hardShadow(body, T.shadowOffset.panel, T.radius.panel)
	end
	local bodyPad = Instance.new("UIPadding")
	bodyPad.PaddingTop = UDim.new(0, T.pad.panel)
	bodyPad.PaddingBottom = UDim.new(0, T.pad.panel)
	bodyPad.PaddingLeft = UDim.new(0, T.pad.panel)
	bodyPad.PaddingRight = UDim.new(0, T.pad.panel)
	bodyPad.Parent = body

	----------------------------------------------------------- tabs
	-- SEASON TAB REMOVED (2026-08-06, owner's call). Season progress still exists and
	-- still pays out on its own -- SeasonPassHandler grants XP automatically and the
	-- Pass panel owns tier claiming -- this panel just no longer shows a read-only
	-- mirror of it. The renderSeason path and the SeasonState listener are left in
	-- place but unreachable: RENDERERS is only ever indexed by a tab id, and Season is
	-- no longer one.
	--
	-- WEEKLY joined on 2026-08-09, between the two: the tabs run shortest period
	-- first, so Daily -> Weekly -> the one-time milestones. TAB_W below is derived
	-- from the count, so adding it re-divided the row on its own.
	local TAB_DEFS = { "Daily", "Weekly", "Goals" }
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
	-- derived from the tab count rather than hardcoded /3, so dropping a tab widens
	-- the remaining two instead of leaving a third of the row empty
	local TAB_W = (BODY_INNER_W - TAB_GAP * (#TAB_DEFS - 1)) / #TAB_DEFS

	for i, id in ipairs(TAB_DEFS) do
		local btn = PC.pill({
			name = "Tab" .. id,
			text = id,
			colors = S.Action.Neutral,
			size = UDim2.fromOffset(TAB_W, TAB_H),
			position = UDim2.fromOffset((i - 1) * (TAB_W + TAB_GAP), 0),
			textSize = 26,
			radius = 24,
			zIndex = 14,
			parent = tabsRow,
		})
		tabButtons[id] = btn

		-- Style replacement (2026-08-04), FINISHED 2026-08-05: the cream
		-- sweep's white-chip override lived here and is DELETED, not
		-- retargeted -- T.gradient.tab is already the guide's chip, UI.stroke
		-- already paints the kit ink outline, and UI.button already labels in
		-- white. Leaving it in place is what made the tab names invisible:
		-- it forced the chip white while BODY_INK (repaired to white for the
		-- dark cards) painted the label white on top of it. The identical
		-- leftover was on the icon slot, the row card and the row title.

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

	----------------------------------------------------------- reset countdown strip
	-- Right-aligned under the tabs, muted, and small on purpose: it is a reference
	-- number, not a call to action, and the rows are what the eye should land on.
	-- Text and visibility are driven by tickCountdown further down -- this only
	-- reserves the line.
	local resetLabel = PC.read({
		name = "ResetStrip",
		text = "",
		size = 22,
		color = Color3.fromHex("3D5570"),
		align = Enum.TextXAlignment.Right,
		frameSize = UDim2.new(1, 0, 0, RESET_H),
		position = UDim2.fromOffset(0, TAB_H + RESET_GAP),
		zIndex = 14,
		parent = body,
	})

	----------------------------------------------------------- rows scroll region
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "RowsScroll"
	scroll.Position = UDim2.fromOffset(0, TAB_H + RESET_GAP + RESET_H + TABS_TO_ROWS_GAP)
	scroll.Size = UDim2.new(1, 0, 0, ROWS_VIEWPORT_H)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = SCROLLBAR_W
	-- Inset the canvas by the bar rather than overlaying it on the rows.
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	-- Style replacement: the cream sweep's tan thumb (#c9b585) was chosen to
	-- sit on cream. The guide's dark slot grey reads cleanly on the
	-- light-grey window body. Cosmetic only.
	scroll.ScrollBarImageColor3 = S.Outline
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
		local textW = TextService:GetTextSize(text, 24, Enum.Font.FredokaOne, Vector2.new(1000, 60)).X
		return math.max(CHIP_MIN_W, CHIP_PAD_L + CHIP_ICON_W + CHIP_GAP + textW + CHIP_PAD_R)
	end

	-- widthOverride: every row on a tab is built at the SAME chip width (the
	-- widest that tab needs -- see the renderers), so the progress tracks to
	-- their left all end on one vertical line instead of stepping in and out
	-- row by row with the length of the reward text.
	local function buildRewardChip(parent: Frame, iconKey: string, text: string, widthOverride: number?): (Frame, number)
		local w = math.max(measureChipWidth(text), widthOverride or 0)
		-- sheet: reward chip 150x82, violet -- emeralds are violet everywhere
		local chip = PC.plate({
			name = "RewardChip",
			size = UDim2.fromOffset(w, CHIP_H),
			colors = S.Action.Violet,
			radius = 18,
			outline = 4,
			zIndex = parent.ZIndex + 1,
			parent = parent,
			gloss = false,
		})

		-- "emerald" has no Tokens.icons entry (he is not part of the kit), so an
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

		local value = PC.read({
			name = "Value", text = text, size = 24,
			color = Color3.fromHex("4A2E63"), -- violet ink on the violet chip
			parent = chip,
		})
		value.AnchorPoint = Vector2.new(0, 0.5)
		value.Position = UDim2.new(0, CHIP_PAD_L + CHIP_ICON_W + CHIP_GAP, 0.5, 0)
		value.Size = UDim2.new(1, -(CHIP_PAD_L + CHIP_ICON_W + CHIP_GAP + CHIP_PAD_R), 0, 24)
		value.AutomaticSize = Enum.AutomaticSize.None
		value.TextXAlignment = Enum.TextXAlignment.Left
		value.ZIndex = chip.ZIndex + 1

		return chip, w
	end

	local function buildIconSlot(parent: Frame, imageId: string?, emoji: string?, order: number?): Frame
		-- PS99 sticker treatment (2026-08-16): the nav rail's sticker language
		-- brought inside -- bigger art with a slight overhang of the tile, and
		-- a tilt that alternates per row (even order -6, odd +5; -6 when there
		-- is no order, i.e. a lone icon). Rotation goes on the GLYPH/ART only,
		-- never on the slot plate. Applied here at BUILD time so the renderers'
		-- clearRows + rebuild keeps the treatment on every re-render.
		-- SCROLL-MASK FIX (2026-08-18, same bug class as ShopPanel's): the
		-- engine NEVER clips a rotated GuiObject, so rows scrolled out of
		-- RowsScroll left their tilted glyphs floating over the panel chrome.
		-- The tilt now lives inside a NON-rotated "Sticker" CanvasGroup on the
		-- slot plate: the rotation is rasterized into the group's own rect,
		-- which the ScrollingFrame clips like any plain frame. The group runs
		-- 16px past the 78px tile (an ~82px square at ~6 degrees needs ~90px)
		-- so the sticker overhang still shows -- but only INSIDE the scroll
		-- area.
		local tilt = (order == nil or order % 2 == 0) and -6 or 5
		local slot = PC.plate({
			name = "IconSlot",
			size = UDim2.fromOffset(ICON_W, ICON_W),
			colors = { Color3.fromHex("BFD6EC"), Color3.fromHex("8FB2D4") },
			radius = 20,
			outline = 5,
			zIndex = parent.ZIndex + 1,
			parent = parent,
		})
		-- The cream sweep's white-mini-card override is deleted here too (see
		-- the tab chips above for why it had to go): T.gradient.slot IS the
		-- guide's dark slot. Art / emoji structure untouched.
		local sticker = Instance.new("CanvasGroup")
		sticker.Name = "Sticker"
		sticker.BackgroundTransparency = 1
		sticker.BorderSizePixel = 0
		sticker.Size = UDim2.fromOffset(ICON_W + 16, ICON_W + 16)
		sticker.Position = UDim2.fromScale(0.5, 0.5)
		sticker.AnchorPoint = Vector2.new(0.5, 0.5)
		sticker.ZIndex = slot.ZIndex + 1
		sticker.Parent = slot
		if emoji then
			local glyph = UI.label(sticker, emoji, "buttonL", T.color.white)
			glyph.Name = "Glyph"
			glyph.AnchorPoint = Vector2.new(0.5, 0.5)
			glyph.Position = UDim2.fromScale(0.5, 0.5)
			-- Sticker: fill the tile (the slight overhang is the point) and
			-- let TextScaled size the emoji to the label instead of buttonL's
			-- fixed TextSize. Emoji ignore TextColor3/strokes, so size and
			-- rotation are the only levers here. Sized in OFFSETS against the
			-- 78px tile (~82px, the old 1.05 scale) because the parent is now
			-- the larger Sticker canvas; rotation stays on the glyph, INSIDE
			-- the non-rotated group.
			glyph.Size = UDim2.fromOffset(ICON_W + 4, ICON_W + 4)
			glyph.TextScaled = true
			glyph.Rotation = tilt
			glyph.AutomaticSize = Enum.AutomaticSize.None
			glyph.TextXAlignment = Enum.TextXAlignment.Center
			glyph.ZIndex = sticker.ZIndex + 1
		else
			local art = UI.artSlot(sticker, UDim2.fromOffset(ICON_W + 4, ICON_W + 4), imageId)
			art.Name = "Art"
			art.AnchorPoint = Vector2.new(0.5, 0.5)
			art.Position = UDim2.fromScale(0.5, 0.5)
			-- Sticker: 70px -> 82px on the 78px tile (slight overhang) + the
			-- per-row tilt. artSlot is a flat ImageLabel (PNG, not a viewport),
			-- so rotation is safe and stays readable. Sized in OFFSETS (the old
			-- tile-relative scale would track the larger Sticker canvas);
			-- rotation stays on the art, INSIDE the non-rotated group.
			art.Rotation = tilt
			art.ZIndex = sticker.ZIndex + 1
		end
		return slot
	end

	-- "claimed" is built by hand (not UI.button) because UI.button forces
	-- white label text for every non-"disabled" variant, and a Claimed state
	-- needs a muted label -- unreachable through UI.button's variant map.
	-- That reason predates the restyle and survives it. PS99 cool
	-- (2026-08-16): built on PC.statePlate with S.Action.Inert at 0.15
	-- BackgroundTransparency -- S.Action.Neutral's light blend at 0.4
	-- washed the white CLAIMED text out. The old soft-green claimed trio
	-- (#e9f7e4/#bfe3b1/#6da35e) is deleted: zero call sites.
	local function buildClaimedButton(parent: Frame): Frame
		-- 2026-08-17: inherits statePlate's pale-inert default (grey ink + white
		-- halo via the luminance gate), so the legibility transparency dance
		-- above is history -- a claimed chip no longer wears button chrome
		local b = PC.statePlate({
			name = "ClaimedButton",
			text = "CLAIMED",
			size = UDim2.fromOffset(ACTION_W, ACTION_H),
			zIndex = parent.ZIndex + 1,
			parent = parent,
		})
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
			local btn = PC.pill({
				name = "ClaimButton",
				text = "CLAIM",
				colors = S.Action.Go, -- green means go, once (sheet rule 6)
				size = UDim2.fromOffset(ACTION_W, ACTION_H),
				textSize = 30,
				zIndex = slot.ZIndex + 1,
				parent = slot,
			})
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
			local btn = PC.pill({
				name = "ViewButton",
				text = "VIEW",
				-- PS99 colour grammar: gold is reserved for real money; an act
				-- button is green, full stop (was S.Action.Gold)
				colors = S.Action.Go,
				size = UDim2.fromOffset(ACTION_W, ACTION_H),
				textSize = 30,
				zIndex = parent.ZIndex + 1,
				parent = parent,
			})
			if onView then
				btn.MouseButton1Click:Connect(onView)
			end
			return btn
		else -- "inprogress"
			-- 2026-08-17: pale-inert default (the old NEUTRAL ramp was still
			-- button chrome on a non-button; the row's progress bar carries the
			-- in-progress story)
			local btn = PC.statePlate({
				name = "InProgressButton",
				text = "IN PROGRESS",
				size = UDim2.fromOffset(ACTION_W, ACTION_H),
				zIndex = parent.ZIndex + 1,
				parent = parent,
			})
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
		-- Optional SECOND reward chip, for a quest that pays two currencies at once.
		-- Only the weekly slate does (emeralds + season XP); leave these nil and the
		-- row is laid out exactly as it always was.
		Reward2IconKey: string?,
		Reward2Text: string?,
		Action: string, -- "claim" | "inprogress" | "claimed" | "view"
		ChipW: number?, -- shared reward-chip width for the whole tab
		Chip2W: number?, -- ditto for the second chip
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

		local card = PC.plate({
			name = "Card",
			size = UDim2.new(1, 0, 1, 0),
			colors = { S.Surface.RowTop, S.Surface.RowBottom },
			radius = 26,
			outline = 6,
			zIndex = 15,
			parent = slot,
			gloss = false,
		})
		-- T.gradient.row IS the guide's dark card, so the cream sweep's
		-- white-card override is deleted here as well (see the tab chips).
		-- The UI.hardShadow call stays DROPPED -- never created, not
		-- destroyed post-hoc (hardShadow wires Position/Destroying
		-- connections that must not be half-torn); the guide's flat dark
		-- cards separate on their ink outline alone.

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, ROW_PAD_X)
		pad.PaddingRight = UDim.new(0, ROW_PAD_X)
		pad.Parent = card

		local icon = buildIconSlot(card, vm.Icon, vm.Emoji, order)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 0, 0.5, 0)

		local reward, chipW = buildRewardChip(card, vm.RewardIconKey, vm.RewardText, vm.ChipW)
		reward.AnchorPoint = Vector2.new(1, 0.5)
		reward.Position = UDim2.new(1, -(ACTION_W + ROW_GAP_INNER), 0.5, 0)

		-- The second chip sits to the LEFT of the first, so the row still reads
		-- icon -> what you are doing -> what you get -> the button; the centre column
		-- is what gives up the width. `chipCol` is the whole reward block including
		-- its inner gap, which is what the centre column has to subtract.
		local chipCol = chipW
		if vm.Reward2Text then
			local reward2, chip2W = buildRewardChip(card, vm.Reward2IconKey or "coin", vm.Reward2Text, vm.Chip2W)
			reward2.Name = "RewardChip2"
			reward2.AnchorPoint = Vector2.new(1, 0.5)
			reward2.Position = UDim2.new(1, -(ACTION_W + ROW_GAP_INNER + chipW + ROW_GAP_INNER), 0.5, 0)
			chipCol += chip2W + ROW_GAP_INNER
		end

		local action, bobFrame = buildActionButton(card, vm.Action, vm.OnClaim, vm.OnClaim)
		action.AnchorPoint = Vector2.new(1, 0.5)
		action.Position = UDim2.new(1, 0, 0.5, 0)
		-- Only now that AnchorPoint/Position are final -- see buildActionButton.
		if bobFrame then
			registerBob(bobFrame)
		end

		local centerX = ICON_W + ROW_GAP_INNER
		local centerW = ROW_CONTENT_W - ICON_W - ROW_GAP_INNER - chipCol - ROW_GAP_INNER - ACTION_W - ROW_GAP_INNER
		local centerCol = Instance.new("Frame")
		centerCol.Name = "CenterColumn"
		centerCol.AnchorPoint = Vector2.new(0, 0.5)
		centerCol.Position = UDim2.new(0, centerX, 0.5, 0)
		centerCol.Size = UDim2.fromOffset(math.max(centerW, 40), 80) -- title 38 + 8 gap + track 34 (sheet)
		centerCol.BackgroundTransparency = 1
		centerCol.ZIndex = 15
		centerCol.Parent = card

		-- White on the guide's dark card (its ink contextual text stroke
		-- stays), same as the meta label further down on the progress track
		-- and the reward chip's value: every label in a row now sits on a
		-- dark sub-surface, so they all share one colour.
		local title = PC.read({
			name = "Title", text = vm.Title, size = 30,
			frameSize = UDim2.new(1, 0, 0, 36),
			position = UDim2.fromOffset(0, 0),
			zIndex = 16, parent = centerCol,
		})
		title.TextTruncate = Enum.TextTruncate.AtEnd

		local track, fill = UI.track(centerCol, UDim2.new(1, 0, 0, 34), "green", 17)
		track.Name = "ProgressTrack"
		track.Position = UDim2.fromOffset(0, 46)
		track.ZIndex = 16
		local pct = vm.Target > 0 and (vm.Progress / vm.Target) or 0
		UI.setFill(fill, pct, false)

		-- sheet: the count sits ON the track, centred, 20px shout, 2px stroke
		local metaText = vm.MetaOverride or string.format("%d / %d", vm.Progress, vm.Target)
		PC.shout({
			name = "MetaLabel", text = metaText, size = 20,
			zIndex = track.ZIndex + 3, parent = track,
		})
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
	-- Index list sorted so rows that are still actionable (not done) come first and
	-- done rows sink to the bottom; original (server) order is the tiebreak, since
	-- table.sort is not stable. Shared by the Daily and Weekly tabs (round 2).
	local function actionableFirst(list, isDone: (any) -> boolean): { number }
		local ordered = {}
		for i in ipairs(list) do
			ordered[i] = i
		end
		table.sort(ordered, function(a, b)
			local da, db = isDone(list[a]), isDone(list[b])
			if da ~= db then
				return not da
			end
			return a < b
		end)
		return ordered
	end

	local function renderDaily()
		clearRows()
		-- One chip width for the whole tab: the widest reward it has to show.
		local chipW = 0
		for _, q in ipairs(dailyQuests) do
			chipW = math.max(chipW, measureChipWidth("+" .. tostring(q.Reward or 0)))
		end
		-- round 2: the rows a player can still act on lead; auto-claimed (done)
		-- rows sink to the bottom. Stable within each bucket (server order).
		for row, idx in ipairs(actionableFirst(dailyQuests, function(q) return q.Claimed == true end)) do
			local q = dailyQuests[idx]
			buildQuestRow(row, {
				ChipW = chipW,
				Icon = T.icons.goals,
				Title = q.Text or "",
				Progress = q.Progress or 0,
				Target = q.Target or 1,
				MetaOverride = questMeta(q.Kind, q.Progress or 0, q.Target or 1),
				RewardIconKey = "emerald", -- daily egg-quests pay gems (the drawn gem icon)
				RewardText = "+" .. tostring(q.Reward or 0),
				Action = q.Claimed and "claimed" or "inprogress",
			})
		end
	end

	-- The one tab whose rows pay TWO currencies. Both chip widths are measured
	-- across the whole tab, the same way every other tab measures its single chip,
	-- so the progress tracks still all end on one vertical line.
	--
	-- No claim path, by design: EmeraldService auto-claims a weekly the instant its
	-- target is reached, exactly as it does a daily, so a row is either in progress
	-- or already paid and there is nothing here for a button to do.
	local function renderWeekly()
		clearRows()
		local chipW, chip2W = 0, 0
		for _, q in ipairs(weeklyQuests) do
			chipW = math.max(chipW, measureChipWidth("+" .. tostring(q.Darrels or 0)))
			chip2W = math.max(chip2W, measureChipWidth("+" .. tostring(q.XP or 0) .. " XP"))
		end
		for row, idx in ipairs(actionableFirst(weeklyQuests, function(q) return q.Claimed == true end)) do
			local q = weeklyQuests[idx]
			buildQuestRow(row, {
				ChipW = chipW,
				Chip2W = chip2W,
				Icon = T.icons.goals,
				Title = q.Text or "",
				Progress = q.Progress or 0,
				Target = q.Target or 1,
				MetaOverride = questMeta(q.Kind, q.Progress or 0, q.Target or 1),
				RewardIconKey = "emerald",
				RewardText = "+" .. tostring(q.Darrels or 0),
				-- "pass" is the season-track icon, the same key the (retired) Season tab
				-- used for an XP reward -- so XP looks like XP wherever it is shown.
				Reward2IconKey = "pass",
				Reward2Text = "+" .. tostring(q.XP or 0) .. " XP",
				Action = q.Claimed and "claimed" or "inprogress",
			})
		end
	end

	-- A goal pays either Cash (gold coin pill) or Darrels (gem pill); QuestHandler
	-- tells us which per goal via RewardKind, defaulting to Cash for every goal that
	-- predates the mixed-currency ladder.
	local function goalRewardIcon(q)
		return (q.RewardKind == "Emeralds") and "emerald" or "coin"
	end
	local function goalRewardText(q)
		if q.RewardKind == "Emeralds" then
			return "+" .. tostring(q.Reward or 0)
		end
		return shortCash(q.Reward or 0)
	end

	local function renderGoals()
		clearRows()
		local chipW = 0
		for _, q in ipairs(goalsQuests) do
			chipW = math.max(chipW, measureChipWidth(goalRewardText(q)))
		end
		-- Completed-but-unclaimed goals float to the TOP (2026-08-22): a player
		-- notified that a goal is done should not have to scroll to find its
		-- CLAIM button. Everything else keeps its original server order, so a
		-- goal drops back to its original spot the instant it is claimed (its
		-- action flips off "claim" and it leaves the float bucket). Stable
		-- ordering: table.sort is not stable, so sort an INDEX list with the
		-- original position as the tiebreaker rather than sorting the quests.
		-- round 2: three buckets -- CLAIM first, then the progression in server
		-- order (the next goals to work toward), then CLAIMED at the bottom -- so
		-- the most actionable reward is always at the top of the list.
		local function isClaimable(q): boolean
			return q.Met == true and q.Claimed ~= true
		end
		local function bucketOf(q): number
			if isClaimable(q) then return 0 end
			if q.Claimed == true then return 2 end
			return 1
		end
		local ordered = {}
		for i in ipairs(goalsQuests) do
			ordered[i] = i
		end
		table.sort(ordered, function(a, b)
			local ba, bb = bucketOf(goalsQuests[a]), bucketOf(goalsQuests[b])
			if ba ~= bb then
				return ba < bb
			end
			return a < b -- otherwise keep original order (stable tiebreak)
		end)
		for row, idx in ipairs(ordered) do
			local q = goalsQuests[idx]
			local met = q.Met == true
			local claimed = q.Claimed == true
			buildQuestRow(row, {
				ChipW = chipW,
				Icon = T.icons.goals,
				Title = q.Desc or "",
				Progress = met and 1 or 0,
				Target = 1,
				MetaOverride = claimed and "CLAIMED" or (met and "COMPLETE" or "LOCKED"),
				RewardIconKey = goalRewardIcon(q),
				RewardText = goalRewardText(q),
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

	local RENDERERS = { Daily = renderDaily, Weekly = renderWeekly, Goals = renderGoals, Season = renderSeason }

	-- Forward reference: switchTab re-ticks the refresh chip so a tab change shows
	-- the right clock at once rather than up to a second later (Daily counts to
	-- midnight, Weekly to Monday). The countdown itself is built further down.
	local tickCountdownRef = function() end

	local function updateTabVisuals()
		-- sheet: selected sub-tab = gold, unselected = neutral (no ring).
		-- BackgroundColor3 moves WITH the gradient (2026-08-11): UIGradient
		-- MULTIPLIES the background, so gold-over-the-neutral-base the tab was
		-- built with rendered olive.
		for id, btn in pairs(tabButtons) do
			local g = btn:FindFirstChildOfClass("UIGradient")
			local active = (id == activeTab)
			local c = active and S.Role.Neutral or S.Role.Disabled -- 2026-09-18 UI foundation: blue = navigation (was delta 7 green)
			btn.BackgroundColor3 = c[1]
			if g then g.Color = ColorSequence.new(c[1], c[2]) end
			-- pale-Neutral sweep: the light Neutral fill cannot carry white bubble
			-- text -- neutral = dark ink + white halo, active green = white ink +
			-- navy edge (mirrors pill()'s build-time luminance gate)
			local label = btn:FindFirstChild("Label")
			if label and label:IsA("TextLabel") then
				label.TextColor3 = active and Color3.new(1, 1, 1) or S.Surface.ReadInk
				local labelStroke = label:FindFirstChildOfClass("UIStroke")
				if labelStroke then
					labelStroke.Color = active and S.Outline or Color3.new(1, 1, 1)
				end
			end
			local ring = tabRings[id]
			if ring then ring.Visible = false end
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
		tickCountdownRef()
	end

	for id, btn in pairs(tabButtons) do
		btn.MouseButton1Click:Connect(function()
			switchTab(id)
		end)
	end
	updateTabVisuals()

	----------------------------------------------------------- refresh countdown (1s loop, STRICTLY gated on wrapper.Visible)
	local countdownRunning = false

	-- SECONDS LEFT ON THE ACTIVE TAB, and its caption -- or nil for a tab that does
	-- not reset at all. Each tab counts down to ITS OWN boundary: a clock reading
	-- 07:12:33 over a weekly slate with six days left is worse than no clock.
	local function resetCountdown(): (string?, number?)
		if activeTab == "Daily" then
			-- The server's EndsAt when it has spoken. The local fallback is not an
			-- approximation: EmeraldService's daily boundary IS midnight UTC, which is
			-- exactly what nextMidnightRemaining computes.
			return "DAILY RESETS IN",
				dailyEndsAt and (dailyEndsAt - os.time()) or nextMidnightRemaining(os.time())
		elseif activeTab == "Weekly" then
			-- NO local fallback here, deliberately. The Monday boundary is the server's
			-- (EmeraldService shifts the epoch off its Thursday), and re-deriving that
			-- shift client-side is precisely how a countdown ends up disagreeing with
			-- the reset it is counting down to. Until the payload lands, no strip.
			if not weeklyEndsAt then return nil, nil end
			return "WEEKLY RESETS IN", weeklyEndsAt - os.time()
		end
		-- Goals are one-time milestones. Nothing to count down to.
		return nil, nil
	end

	local function tickCountdown()
		local caption, left = resetCountdown()
		if caption and left then
			local clock = formatDHMS(left)
			resetLabel.Text = caption .. "  " .. clock
			resetLabel.Visible = true
			refreshValue.Text = clock
		else
			resetLabel.Visible = false
			-- the header chip is shared across tabs and has no per-tab state to show
			-- here, so it keeps the daily value it always had
			refreshValue.Text = formatHMS(nextMidnightRemaining(os.time()))
		end
	end
	tickCountdownRef = tickCountdown
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

	----------------------------------------------------------- data wiring (server-confirmed only)
	local function applyDaily(daily)
		if typeof(daily) ~= "table" then
			return
		end
		dailyQuests = daily.Quests or {}
		dailyEndsAt = tonumber(daily.EndsAt)
		if activeTab == "Daily" then
			renderDaily()
			tickCountdown()
		end
	end

	-- Same remote, same push, second field. Weekly arrives with every Daily because
	-- EmeraldService builds both into one payload -- there is no separate weekly pull.
	local function applyWeekly(week)
		if typeof(week) ~= "table" then
			return
		end
		weeklyQuests = week.Quests or {}
		weeklyEndsAt = tonumber(week.EndsAt)
		if activeTab == "Weekly" then
			renderWeekly()
			tickCountdown()
		end
	end

	ctx.remotes.EmeraldUpdate.OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" then
			applyDaily(payload.Daily)
			applyWeekly(payload.Weekly)
		end
	end)

	-- Pull once per open, same load-discriminator pattern GameHUDClient's own
	-- startup loop uses (task-4-report.md): EmeraldState:InvokeServer() before
	-- the player's profile has loaded returns a real table whose `Daily`
	-- field is nil (a placeholder, not real data) -- keep retrying until
	-- `Daily` comes back as a table instead of trusting the first response.
	-- `Daily` stays the load discriminator even now the response carries Weekly too:
	-- both are built from the same profile, so a table in one means a table in the
	-- other, and testing the field that has always been the tell keeps this loop
	-- honest against an older server that has no weekly slate at all.
	local function pullEmeraldState()
		task.spawn(function()
			for _ = 1, 20 do
				if not wrapper.Visible then
					return
				end
				local ok, res = pcall(function()
					return ctx.remotes.EmeraldState:InvokeServer()
				end)
				if ok and typeof(res) == "table" and typeof(res.Daily) == "table" then
					applyDaily(res.Daily)
					applyWeekly(res.Weekly)
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
	local function onShown()
		ctx.remotes.SeasonState:FireServer()
		pullEmeraldState()
		ensureBobDriver()
		startCountdown()
		setBlur(true)
	end

	local function onHidden()
		stopBobDriver()
		stopCountdown()
		setBlur(false)
	end

	wrapper:GetPropertyChangedSignal("Visible"):Connect(function()
		if wrapper.Visible then onShown() else onHidden() end
	end)

	--[[ THE WRAPPER'S OWN SIGNAL NEVER FIRES ON A NORMAL OPEN (fixed 2026-08-09).

	This panel is a TAB inside ProgressPanel, and that module reveals its children
	with `f.Visible = (def.Id == active)`. Goals is its DEFAULT tab, so the first
	paint assigns `true` to a frame that is ALREADY true -- and Roblox raises no
	changed signal for a write that changes nothing. The wrapper then stays true for
	the rest of the session, because closing the panel hides the HOST, not this frame.

	So the pull that fills Daily and Weekly never ran on an open, and both tabs came
	up empty every time. The only way to see a daily quest at all was to switch to
	SEASON PASS and back -- the one action that genuinely toggles this frame. (Goals
	looked fine throughout and hid the bug: its milestones arrive on QuestHandler's
	unprompted 3s push, so that tab needs nothing from an open.)

	The HOST's signal is the one that actually tracks open and close, so it drives the
	same routine. It also still does the job it was added for -- killing the blur when
	anything hides the host while this wrapper stays visible, since a BlurEffect
	post-processes the whole screen regardless of GUI visibility.
	]]
	ctx.host:GetPropertyChangedSignal("Visible"):Connect(function()
		if ctx.host.Visible then
			if wrapper.Visible then onShown() end
		else
			onHidden()
		end
	end)

	switchTab(activeTab) -- initial paint (zero/stale state) before the first server response lands

	-- THE VERY FIRST OPEN fires neither signal: the shell builds this panel lazily, at
	-- which point the host is already visible and the wrapper has always been. Deferred
	-- so it reads the state the shell has finished setting up, and guarded so a panel
	-- built off-screen never raises the blur.
	task.defer(function()
		if ctx.host.Visible and wrapper.Visible then onShown() end
	end)

	return wrapper
end

return GoalsPanel
