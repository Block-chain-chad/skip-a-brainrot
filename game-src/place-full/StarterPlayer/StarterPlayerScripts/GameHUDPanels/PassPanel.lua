--!strict
-- PassPanel: the SEASON PASS panel -- a GameHUDPanels consumer module
-- (StarterPlayer.StarterPlayerScripts.GameHUDPanels.PassPanel).
--
-- REFORMAT 2026-08-07 (design: docs/design-handoff/season-pass/). This was a
-- HORIZONTAL filmstrip: three stacked rows -- free cards / tier badges / gold pass
-- cards -- scrolling sideways, plus a "Max Rewards" column floating outside the
-- body. It is now the design's LADDER: three columns, FREE TRACK | TIER | PREMIUM
-- TRACK, scrolling VERTICALLY through all 50 tiers, so a player reads one tier
-- ACROSS (what do I get here, free vs premium) instead of one track ALONG.
--
-- Two real bugs died with the old layout:
--
--   * THE PANEL IS FINALLY 960 WIDE. T.size.panelWidth.pass has always said 960,
--     but the old build was 960 + 14 gap + 196 side column = 1170 and hung 90px off
--     a 4:3 tablet. The side column is gone -- the MILESTONE row shows the top
--     reward of BOTH tracks, which is the only thing those two preview cards were
--     for -- so the token is true for the first time and GameHUDClient's panelFitW
--     floor (960, see GameHUDClient:165-180) fits it exactly, with zero effect on
--     any other panel's scale.
--
--   * FREE REWARD TEXT WAS INVISIBLE. The old card flipped its own gradient to flat
--     white, then coloured its text with CARD_TEXT -- an undefined global left
--     behind by the 2026-08-04 style repair, which re-declared CARD_BORDER and
--     BODY_INK but missed that one. UI.label falls back to T.color.white when its
--     colour argument is nil, so every free reward name was white on white. That
--     whole code path is deleted; state now picks the surface kind UP FRONT rather
--     than recolouring a built card's gradient afterwards.
--
-- Contract (kit README section: ctx from GameHUDClient):
--   return { Id = "pass", Build = function(ctx) -> Frame }
-- Build is called ONCE lazily on first open; the shell parents the returned Frame
-- into ctx.host and owns Visible toggling on every open/close after that -- this
-- module never sets its own Parent and never drives its own open/close animation.
--
-- Data contract (read StarterPlayer.StarterPlayerScripts.SeasonClient +
-- ServerScriptService.Modules.SeasonPassHandler FULLY before writing this):
--   remotes.SeasonState  -- RemoteEvent, bidirectional
--     client -> server: SeasonState:FireServer()  (no args; requests a refresh)
--     server -> client: SeasonState:FireClient(player, {
--         XP = number,             -- cumulative season XP
--         Claimed = { [tostring(tier)] = true, ... },
--         QuestIds = { string, ... },   -- not consumed by this panel (Goals' job)
--         Progress = { [id] = { P = number, D = boolean }, ... }, -- ditto
--         Day = number,
--     })
--   remotes.SeasonClaim  -- RemoteEvent
--     client -> server: SeasonClaim:FireServer(tier, track)
--     Server validates level/ownership and, on success, re-sends SeasonState with
--     the new Claimed table. NEVER flip Claimed locally -- only the next
--     SeasonState push may change what a card renders as.
--
-- BOTH TRACKS ARE REAL DATA NOW. The header this replaces said SeasonConfig was
-- "free track only for now" and shipped "one Cash reward per tier (no separate
-- free/pass reward items)". Both went stale on 2026-08-07 when the track was
-- extended to 50 tiers: SeasonConfig.Tiers and .PassTiers are 50 entries each,
-- TierFor(track, i) reads either without the caller branching, and
-- DescribeReward(def) is the ONE place that turns a tier into something
-- displayable. Every reward string on this panel comes from it.
--
-- WHAT IS DELIBERATELY INERT, and why. All three follow the precedent set by the
-- egg shop's BUY EMERALDS and the Charm Codex's EQUIP: draw the control in full,
-- wire nothing, let it come alive on its own when the missing id appears.
--   * UNLOCK PREMIUM -- GamepassConfig's SeasonPass entry is still GamepassId = 0,
--     so GamepassService.Owns is false for everyone and SeasonPassHandler refuses
--     track == "pass" server-side anyway. The premium column therefore renders
--     LOCKED for every player and unlocks by itself the moment a real id is pasted
--     in. The price on the button is READ FROM GamepassConfig, not hardcoded, so
--     the button cannot drift from what the pass actually costs. (The design says
--     799 R$; the catalog says 399. The catalog wins -- it is the thing players
--     are actually charged.)
--   * SKIP TIER -- no tier-skip dev product exists anywhere in this game, so its
--     price is the design's 79 R$ with nothing behind it.
--   * The countdown chip and the footer end-date -- SeasonConfig.SEASON.Ends is
--     nil. They are OMITTED rather than faked; see the note in SeasonConfig.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting") -- the backdrop BlurEffect lives here
local modules = ReplicatedStorage:WaitForChild("Modules")
local SeasonConfig = require(modules:WaitForChild("SeasonConfig"))
-- Egg tiers show the REAL egg model in a ViewportFrame rather than a flat icon.
-- Same helper the Index and Backpack grids use for brainrots/pets.
local BrainrotThumb = require(modules:WaitForChild("BrainrotThumb"))
-- Emerald tiers draw the EMERALD icon, which is a vector drawing rather than an
-- image id. pcall'd like ClientMain does: a missing icon module must cost the
-- icon, not the whole panel.
local okIconArt, IconArt = pcall(function()
	return require(modules:WaitForChild("UIKit"):WaitForChild("IconArt"))
end)
if not okIconArt then IconArt = nil end
-- Same treatment: the premium button's price comes from the live catalog, but a
-- missing catalog must not take the panel down with it.
local okPasses, GamepassConfig = pcall(function()
	return require(modules:WaitForChild("GamepassConfig"))
end)
if not okPasses then GamepassConfig = nil end

-- Id is "passInner", NOT "pass": since 2026-08-07 the season pass is a TAB inside
-- ProgressPanel rather than its own rail tile. See the matching note in GoalsPanel.
local PassPanel = { Id = "passInner" }

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

-- 1240 -> "1,240". The progress readout is the one place the design shows a raw
-- XP number rather than shortCash's compact form.
local function comma(n: number): string
	local s = tostring(math.floor(n or 0))
	local out = (s:reverse():gsub("(%d%d%d)", "%1,")):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

-- The design's subtitle under each reward name. Derived from the reward KIND, so
-- it cannot drift from what the tier actually hands over.
local function subtitleFor(rw, seasonNumber: number): string
	if rw.kind == "Cash" then
		return "INSTANT PAYOUT"
	elseif rw.kind == "Emeralds" then
		return "GEMS" -- the currency is Gems (was PREMIUM CURRENCY)
	elseif rw.kind == "Egg" then
		return "HATCHERY"
	elseif rw.kind == "Boost" then
		return string.format("%d MINUTES", rw.minutes or 0)
	elseif rw.kind == "Tag" then
		return string.format("SEASON %02d TITLE", seasonNumber)
	end
	return ""
end

-- opts.embedded -- see the note on GoalsPanel.Build; same contract, same reason.
-- 2026-08-10 INNER RESTYLE (design_handoff_hud_upgrade, PROGRESS/SEASON):
-- sheet's ladder -- gold TIER plate + gold tier spine, 44-tall XP bar with
-- the count on the track, violet UNLOCK plate instead of a caption, free
-- track green / locked premium inert with greyed art, CLAIMED as a word.
-- All state machine / claim wiring untouched.
-- 2026-08-16 FIELD STUDY DELTA 8 (PS99 f072/f073, the only boxed cards in
-- their game are these state tiles) supersedes the claimed/locked treatments
-- above -- see buildRewardCard: claimed = green tile + darker-green edge +
-- "Claimed!" strip, locked = silver tile + strip, art never desaturated.
local UIKitFolder = game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("UIKit")
local PC = require(UIKitFolder:WaitForChild("PanelChrome"))
local S = require(UIKitFolder:WaitForChild("SpecTheme"))
local Toast = require(UIKitFolder:WaitForChild("Toast")) -- round 2: claim confirmation toast

function PassPanel.Build(ctx, opts)
	local EMBEDDED = (type(opts) == "table" and opts.embedded == true)
	local T = ctx.Tokens
	local UI = ctx.Builders

	local SEASON = SeasonConfig.SEASON or { Number = 1, Name = "Season", Id = "SEASON", Ends = nil }

	----------------------------------------------------------- geometry (960 x 700)
	-- 700 is PANEL_FIT_H in GameHUDClient; 960 is its panelFitW floor. Staying
	-- inside BOTH means this panel never clips and never shrinks another panel.
	local PANEL_W = T.size.panelWidth.pass -- 960
	-- Embedded, the header's 102px comes off the GROUP rather than out of the body:
	-- BODY_H below is PANEL_H - BODY_TOP - footer, so shrinking both together leaves
	-- the ladder exactly the height it has always been (560).
	local PANEL_H = 700
	local PAD = T.pad.panel -- 16
	local HEADER_H = T.size.headerHeight -- 92
	local BODY_TOP = EMBEDDED and 0 or (HEADER_H + 10) -- 102
	if EMBEDDED then PANEL_H = PANEL_H - (HEADER_H + 10) end
	local FOOTER_H = 30
	local FOOTER_GAP = 8
	local BODY_H = PANEL_H - BODY_TOP - FOOTER_H - FOOTER_GAP -- 560
	local INNER_W = PANEL_W - PAD * 2 -- 928
	local INNER_H = BODY_H - PAD * 2 -- 528

	local PROGRESS_H = 96 -- sheet: tier plate 200x96
	-- round 2.5: 62 -> 54. The tallest thing in the row is the 48px UNLOCK button;
	-- the 8px this gives back goes to the ladder below.
	local COLHEAD_H = 54
	local LADDER_TOP = PROGRESS_H + 10 + COLHEAD_H + 6 -- 166
	local LADDER_H = INNER_H - LADDER_TOP -- 362

	-- The vertical scrollbar sits INSIDE the scroll frame's width, so the row
	-- content -- and therefore the column headers above it, which must line up --
	-- is measured against the width minus the bar.
	local SCROLLBAR_W = 10
	local LADDER_W = INNER_W - SCROLLBAR_W -- 918
	local TIER_COL_W = 108 -- sheet: the tier spine column
	local COL_GAP = 16
	local CARD_W = math.floor((LADDER_W - TIER_COL_W - COL_GAP * 2) / 2) -- 399
	local FREE_X = 0
	local TIER_X = CARD_W + COL_GAP -- 415
	local PASS_X = TIER_X + TIER_COL_W + COL_GAP -- 519
	-- round 2.5: the sheet's 104 + 12 showed three tiers of fifty at once on a
	-- 1080p desktop (round 2 QA). 82 + 8 shows four, with the row's contents --
	-- a 60 plate, name over caption, a 54 CLAIM -- still sitting in clear air.
	local ROW_H = 82
	local ROW_GAP = 8
	local MILESTONE_H = 26

	-- Reward-card internals
	local PLATE = 60 -- sheet: icon 66; 60 keeps 11px of row above and below it
	local PLATE_X = 10
	local TEXT_X = PLATE_X + PLATE + 12 -- 82
	local ACTION_W = 96
	-- Measured against the WIDEST action the column can carry (the PREMIUM padlock
	-- chip, ACTION_W + 30), not the bare button width: the old 199 ran 20px under
	-- that chip, which is where the truncated egg names were disappearing to.
	local TEXT_W = CARD_W - TEXT_X - (ACTION_W + 30) - 16 -- 175
	local NAME_Y, SUB_Y = 13, 43

	----------------------------------------------------------- module-local state (server-confirmed only)
	local state = { XP = 0, Claimed = {}, PassClaimed = {}, PassOwned = false }

	----------------------------------------------------------- root
	local wrapper = Instance.new("Frame")
	wrapper.Name = "PassPanel"
	wrapper.Size = UDim2.fromScale(1, 1)
	wrapper.BackgroundTransparency = 1
	wrapper.ZIndex = 10

	-- One column now. The old build wrapped this in a Group that also held a
	-- 196px SideColumn floating outside the body; that is what made the panel's
	-- real footprint 1170 while it advertised 960.
	local group = Instance.new("Frame")
	group.Name = "Group"
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromScale(0.5, 0.5)
	group.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	group.BackgroundTransparency = 1
	group.ZIndex = 10
	group.Parent = wrapper

	----------------------------------------------------------- header
	local header = UI.surface(group, UDim2.fromOffset(PANEL_W, HEADER_H), "header", T.radius.panel, T.stroke.panel)
	header.Name = "Header"
	header.Position = UDim2.fromOffset(0, 0)
	header.ZIndex = 12
	-- built then hidden when embedded -- see the matching note in GoalsPanel
	header.Visible = not EMBEDDED
	UI.gloss(header, T.radius.panel)
	UI.hardShadow(header, T.shadowOffset.panel, T.radius.panel)
	-- UI.hardShadow parents the shadow as a SIBLING of the header, so hiding the
	-- header alone left a 700x68 navy slab behind the progress row once the body
	-- went light (round 2); the shadow follows the header's visibility
	if EMBEDDED then
		local hs = group:FindFirstChild("HardShadow")
		if hs and hs:IsA("GuiObject") then hs.Visible = false end
	end

	local headerIcon = UI.artSlot(header, UDim2.fromOffset(62, 62), T.icons.pass)
	headerIcon.Name = "SectionIcon"
	headerIcon.AnchorPoint = Vector2.new(0, 0.5)
	headerIcon.Position = UDim2.new(0, 12, 0.5, 0)
	headerIcon.ZIndex = header.ZIndex + 2

	local TITLE_X = 12 + 62 + 14 -- 88

	-- HEADER BUDGET. Four controls share the right side with the title block, and
	-- 960 is not generous. The first cut of this panel estimated the button widths
	-- and SKIP TIER ended up UNDER the kicker by 39px on the live panel -- so these
	-- are each label's real rendered TextBounds (148 / 239 / 63 design px, measured
	-- in a Play session) plus 16px of padding, not guesses. The title block then
	-- takes whatever is left and carries TextTruncate, so a longer season name
	-- shortens the kicker instead of colliding with a button again.
	local BTN_H = 56
	local BTN_GAP = 10
	local CLOSE_W = T.size.closeButton.X -- 74
	local QUESTS_W = 80
	local PREMIUM_W = 256
	local SKIP_W = 164
	local closeR = 12
	local questsR = closeR + CLOSE_W + BTN_GAP -- 96
	local premiumR = questsR + QUESTS_W + BTN_GAP -- 186
	local skipR = premiumR + PREMIUM_W + BTN_GAP -- 452
	local TITLE_W = PANEL_W - skipR - SKIP_W - 14 - TITLE_X -- 242

	-- Kicker above the title: SEASON 01 . STILL WATER . 50 TIERS. Text is set in
	-- render() because the tier count is read from SeasonConfig, not assumed.
	local kicker = UI.label(header, "", "meta", T.color.white)
	kicker.Name = "Kicker"
	kicker.Position = UDim2.fromOffset(TITLE_X, 14)
	kicker.Size = UDim2.fromOffset(TITLE_W, 20)
	kicker.AutomaticSize = Enum.AutomaticSize.None
	kicker.TextTruncate = Enum.TextTruncate.AtEnd
	kicker.TextTransparency = 0.25
	kicker.ZIndex = header.ZIndex + 2

	local headerTitle = UI.label(header, "SEASON PASS", "panelTitle", T.color.white)
	headerTitle.Name = "Title"
	headerTitle.Position = UDim2.fromOffset(TITLE_X, 34)
	headerTitle.Size = UDim2.fromOffset(TITLE_W, 42)
	headerTitle.AutomaticSize = Enum.AutomaticSize.None
	headerTitle.TextTruncate = Enum.TextTruncate.AtEnd
	headerTitle.ZIndex = header.ZIndex + 2

	local closeBtn = UI.button(header, "X", "red", UDim2.fromOffset(CLOSE_W, T.size.closeButton.Y), "buttonL")
	closeBtn.Name = "CloseButton"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -closeR, 0.5, 0)
	closeBtn.ZIndex = header.ZIndex + 2

	local questsBtn = UI.button(header, "Quests", "purple", UDim2.fromOffset(QUESTS_W, BTN_H), "buttonM")
	questsBtn.Name = "QuestsButton"
	questsBtn.AnchorPoint = Vector2.new(1, 0.5)
	questsBtn.Position = UDim2.new(1, -questsR, 0.5, 0)
	questsBtn.ZIndex = header.ZIndex + 2

	-- INERT (see module header). Price read from the catalog so it cannot drift.
	local passPrice = 399
	if GamepassConfig and GamepassConfig.ByKey and GamepassConfig.ByKey.SeasonPass then
		passPrice = GamepassConfig.ByKey.SeasonPass.RobuxPrice or passPrice
	end
	local premiumBtn = UI.button(header, "UNLOCK PREMIUM  " .. passPrice .. " R$", "gold", UDim2.fromOffset(PREMIUM_W, BTN_H), "buttonM")
	premiumBtn.Name = "UnlockPremiumButton"
	premiumBtn.AnchorPoint = Vector2.new(1, 0.5)
	premiumBtn.Position = UDim2.new(1, -premiumR, 0.5, 0)
	premiumBtn.ZIndex = header.ZIndex + 2

	local skipBtn = UI.button(header, "SKIP TIER  79 R$", "blue", UDim2.fromOffset(SKIP_W, BTN_H), "buttonM")
	skipBtn.Name = "SkipTierButton"
	skipBtn.AnchorPoint = Vector2.new(1, 0.5)
	skipBtn.Position = UDim2.new(1, -skipR, 0.5, 0)
	skipBtn.ZIndex = header.ZIndex + 2

	----------------------------------------------------------- body
	-- 2026-09-18 UI ROUND 2. The dark navy override (2026-08-14 "olive revert",
	-- retinted cool navy) is gone: this tab sits inside the SAME Progress shell as
	-- Goals, and Goals is a light body with white rows -- a navy sheet on the
	-- second tab was the one panel in the game that broke the white-chrome
	-- language. Embedded, the body is transparent so the shared shell's pale
	-- ground shows through; standalone it keeps the kit window surface. Every
	-- ink below is the dark family (S.Surface.ReadInk / ReadSub).
	--
	-- Still NOT UI.panel: UI.panel bundles surface + hardShadow + a UIPadding of
	-- T.pad.panel, and every horizontal measurement in this file (INNER_W, and
	-- LADDER_W under it) is taken against T.pad.panel specifically -- so the
	-- padding stays hand-built to keep that relationship visible at the top of
	-- the geometry block rather than buried in a builder.
	local body = UI.surface(group, UDim2.fromOffset(PANEL_W, BODY_H), "window", T.radius.panel, T.stroke.panel)
	body.Name = "Body"
	body.Position = UDim2.fromOffset(0, BODY_TOP)
	body.ZIndex = 12
	if EMBEDDED then
		body.BackgroundTransparency = 1
		local bg = body:FindFirstChildOfClass("UIGradient")
		if bg then bg:Destroy() end
		local bs = body:FindFirstChildOfClass("UIStroke")
		if bs then bs:Destroy() end
	else
		UI.hardShadow(body, T.shadowOffset.panel, T.radius.panel)
	end
	local bodyPad = Instance.new("UIPadding")
	bodyPad.PaddingTop = UDim.new(0, PAD)
	bodyPad.PaddingBottom = UDim.new(0, PAD)
	bodyPad.PaddingLeft = UDim.new(0, PAD)
	bodyPad.PaddingRight = UDim.new(0, PAD)
	bodyPad.Parent = body

	local INK = S.Surface.ReadInk
	local SUB = S.Surface.ReadSub

	----------------------------------------------------------- progress row
	local progressRow = Instance.new("Frame")
	progressRow.Name = "ProgressRow"
	progressRow.Position = UDim2.fromOffset(0, 0)
	progressRow.Size = UDim2.new(1, 0, 0, PROGRESS_H)
	progressRow.BackgroundTransparency = 1
	progressRow.ZIndex = 14
	progressRow.Parent = body

	local TIER_PILL_W = 200
	local tierPill = PC.plate({
		name = "TierPill",
		size = UDim2.fromOffset(TIER_PILL_W, PROGRESS_H),
		colors = S.Role.Gold,
		radius = 22,
		outline = 6,
		zIndex = 14,
		parent = progressRow,
	})
	local tierCaption = PC.shout({
		name = "TierCaption", text = "TIER", size = 20,
		frameSize = UDim2.new(1, 0, 0, 22),
		position = UDim2.new(0, 0, 0, 12),
		zIndex = tierPill.ZIndex + 2, parent = tierPill,
	})
	local tierValue = PC.shout({
		name = "TierValue", text = "0 / 0", size = 38,
		frameSize = UDim2.new(1, 0, 0, 42),
		position = UDim2.new(0, 0, 0, 40),
		zIndex = tierPill.ZIndex + 2, parent = tierPill,
	})

	local STATUS_W = 300
	local XP_X = TIER_PILL_W + 16
	local XP_W = INNER_W - XP_X - 16 - STATUS_W -- 450

	local xpCaption = PC.read({
		name = "XPCaption", text = "", size = 20, color = INK,
		frameSize = UDim2.fromOffset(XP_W, 24), position = UDim2.fromOffset(XP_X, 0),
		zIndex = 14, parent = progressRow,
	})

	-- sheet: XP bar 44 tall, the count ON the track
	local xpTrack, xpFill = UI.track(progressRow, UDim2.fromOffset(XP_W, 44), "gold", 22)
	xpTrack.Name = "XPTrack"
	xpTrack.Position = UDim2.fromOffset(XP_X, 28)
	xpTrack.ZIndex = 14

	local xpLabel = PC.shout({
		name = "XPLabel", text = "0 / 0", size = 20,
		zIndex = xpTrack.ZIndex + 3, parent = xpTrack,
	})

	-- Right-hand status stack. A UIListLayout centres whatever is present, which
	-- is what lets the countdown line simply NOT EXIST while SEASON.Ends is nil
	-- without leaving a hole where it would have been.
	local statusCol = Instance.new("Frame")
	statusCol.Name = "StatusColumn"
	statusCol.Position = UDim2.fromOffset(INNER_W - STATUS_W, 0)
	statusCol.Size = UDim2.fromOffset(STATUS_W, PROGRESS_H)
	statusCol.BackgroundTransparency = 1
	statusCol.ZIndex = 14
	statusCol.Parent = progressRow

	local statusList = Instance.new("UIListLayout")
	statusList.FillDirection = Enum.FillDirection.Vertical
	statusList.SortOrder = Enum.SortOrder.LayoutOrder
	statusList.HorizontalAlignment = Enum.HorizontalAlignment.Right
	statusList.VerticalAlignment = Enum.VerticalAlignment.Center
	statusList.Padding = UDim.new(0, 4)
	statusList.Parent = statusCol

	local daysLabel: TextLabel? = nil
	if type(SEASON.Ends) == "number" then
		daysLabel = PC.shout({
			name = "DaysLeft", text = "", size = 22, color = S.TitleInk.goals, strokeColor = Color3.new(1, 1, 1),
			align = Enum.TextXAlignment.Right, frameSize = UDim2.new(1, 0, 0, 26), zIndex = 14, parent = statusCol,
		})
		daysLabel.LayoutOrder = 1
	end

	-- READY is the number a player is looking for; it gets the shout weight
	local claimStatus = PC.shout({
		name = "ClaimStatus", text = "0 READY", size = 26, color = S.Role.Positive[2], strokeColor = Color3.new(1, 1, 1),
		align = Enum.TextXAlignment.Right, frameSize = UDim2.new(1, 0, 0, 30), zIndex = 14, parent = statusCol,
	})
	claimStatus.LayoutOrder = 2

	local claimedStatus = PC.read({
		name = "ClaimedStatus", text = "0 CLAIMED", size = 18, color = SUB,
		align = Enum.TextXAlignment.Right, frameSize = UDim2.new(1, 0, 0, 22), zIndex = 14, parent = statusCol,
	})
	claimedStatus.LayoutOrder = 3

	local xpSources = PC.read({
		name = "XPSources", text = "XP from quests, rebirths and daily login", size = 16, color = SUB,
		align = Enum.TextXAlignment.Right, frameSize = UDim2.new(1, 0, 0, 20), zIndex = 14, parent = statusCol,
	})
	xpSources.LayoutOrder = 4

	----------------------------------------------------------- column headers
	-- Two identity chips over the two tracks -- FREE (green, everyone) and
	-- PREMIUM (purple, the paid track) -- with the gold UNLOCK <price> R$ button
	-- riding the premium column. Real money is gold with the Robux mark
	-- (handoff §4); the track identity is what the chips carry.
	local colHead = Instance.new("Frame")
	colHead.Name = "ColumnHeaders"
	colHead.Position = UDim2.fromOffset(0, PROGRESS_H + 10)
	colHead.Size = UDim2.fromOffset(LADDER_W, COLHEAD_H)
	colHead.BackgroundTransparency = 1
	colHead.ZIndex = 14
	colHead.Parent = body

	local ROBUX = "\u{E002}"
	local function trackChip(name: string, text: string, x: number, ramp: { Color3 })
		local chip = PC.statePlate({
			name = name, text = text, colors = ramp,
			size = UDim2.fromOffset(150, 44),
			position = UDim2.new(0, x, 0.5, 0), anchor = Vector2.new(0, 0.5),
			textSize = 22, zIndex = 15, parent = colHead,
		})
		return chip
	end
	trackChip("FreeChip", "FREE", FREE_X, S.Role.Positive)
	local premiumChip = trackChip("PremiumChip", "PREMIUM", PASS_X, S.Role.Purple)

	-- INERT until GamepassConfig's SeasonPass id is real (see the module header);
	-- the price is read from the catalog so it cannot drift from what is charged.
	local unlockBtn = PC.button({
		kind = "gold", text = "UNLOCK " .. ROBUX .. tostring(passPrice), name = "UnlockButton",
		size = UDim2.fromOffset(200, 48), textSize = 22, radius = 16, outline = 3,
		position = UDim2.new(0, PASS_X + CARD_W, 0.5, 0), anchor = Vector2.new(1, 0.5),
		zIndex = 15, parent = colHead,
	})
	local retroNote = PC.read({
		name = "RetroNote", text = "unlocks every tier you already passed", size = 15, color = SUB,
		align = Enum.TextXAlignment.Right,
		frameSize = UDim2.fromOffset(CARD_W - 160, 18), position = UDim2.new(0, PASS_X + 160, 1, -2), anchor = Vector2.new(0, 1),
		zIndex = 15, parent = colHead,
	})
	retroNote.Visible = false -- the footer already says it; kept for a taller header

	----------------------------------------------------------- ladder
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Ladder"
	scroll.Position = UDim2.fromOffset(0, LADDER_TOP)
	scroll.Size = UDim2.fromOffset(INNER_W, LADDER_H)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = SCROLLBAR_W - 4
	scroll.ScrollBarImageColor3 = S.OutlineSoft
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

	-- A claim in flight: the button goes busy and the confirming SeasonState (the
	-- ONLY thing that flips a card to CLAIMED) fires the reward toast. Cleared on
	-- every state push so a lost reply never pins a stale note.
	local pendingClaim: { tier: number, track: string, text: string }? = nil

	----------------------------------------------------------- reward card
	-- The state machine picks the surface kind BEFORE the card is built (kit
	-- README section 5); nothing here mutates a built card's colours.
	--
	--   claimable  green tile, CLAIM button (kit positive)
	--   claimed    pale green tile, check + CLAIMED
	--   reached but track locked (premium without the pass)  violet tile + padlock
	--   unreached  white tile, dimmed art, "TIER n" marker
	local function buildRewardCard(row: Frame, tier: number, track: string)
		local isPass = track == "pass"

		local claimMap = (isPass and state.PassClaimed or state.Claimed) or {}
		local trackOpen = (not isPass) or state.PassOwned == true
		local reached = state.XP >= SeasonConfig.ThresholdFor(tier)
		local claimed = trackOpen and (claimMap[tostring(tier)] == true)
		-- Premium is gated on the gamepass ON TOP of the XP threshold, so a player
		-- who has passed tier 30 still sees the premium column locked until they
		-- own it -- and then sees all 30 waiting, which is the "RETROACTIVE"
		-- promise in the footer.
		local passLocked = isPass and not trackOpen
		local claimable = trackOpen and reached and not claimed

		local ramp
		local edge: Color3 = S.OutlineSoft
		if claimable then
			-- a LIGHT green tile, so the green CLAIM button is the one saturated thing on it
			ramp = { Color3.fromHex("E6FBDF"), Color3.fromHex("CFF3C3") }
			edge = S.Role.Positive[2]
		elseif claimed then
			ramp = { Color3.fromHex("E9FBE6"), Color3.fromHex("D2F3CC") } -- settled: pale green
			edge = Color3.fromHex("A9DDA0")
		elseif passLocked then
			ramp = S.Action.VioletRow -- the paid track, still closed
			edge = Color3.fromHex("CDB7E8")
		else
			ramp = { S.Surface.RowTop, S.Surface.RowBottom }
		end

		local card = PC.plate({
			name = (isPass and "Pass" or "Free") .. "Card" .. tier,
			size = UDim2.fromOffset(CARD_W, ROW_H),
			position = UDim2.fromOffset(isPass and PASS_X or FREE_X, 0),
			colors = ramp,
			strokeColor = edge,
			radius = 22,
			outline = 3,
			zIndex = 15,
			parent = row,
			gloss = false,
		})

		local tierDef = SeasonConfig.TierFor(track, tier)
		local rw = SeasonConfig.DescribeReward(tierDef)

		----------------------------------------------------- art plate
		local plate = PC.plate({
			name = "ArtPlate",
			size = UDim2.fromOffset(PLATE, PLATE),
			position = UDim2.new(0, PLATE_X, 0.5, 0),
			anchor = Vector2.new(0, 0.5),
			colors = { Color3.new(1, 1, 1), Color3.fromHex("E4EDF7") },
			radius = 18,
			outline = 3,
			strokeColor = S.OutlineSoft,
			zIndex = card.ZIndex + 1,
			parent = card,
			gloss = false,
		})

		local art
		local eggMaster = (rw.kind == "Egg") and rw.model and BrainrotThumb.eggMaster(rw.model) or nil
		if eggMaster then
			art = BrainrotThumb.addMaster(plate, eggMaster, {
				size = UDim2.new(1, -8, 1, -8),
				position = UDim2.new(0, 4, 0, 4),
				zIndex = plate.ZIndex + 1,
			})
		end
		if not art and rw.kind == "Emeralds" and IconArt and IconArt.has("emerald") then
			-- the gem has its OWN drawn icon -- the one on the HUD currency pill
			local box = PLATE - 12
			local host = Instance.new("Frame")
			host.Name = "GemIcon"
			host.AnchorPoint = Vector2.new(0.5, 0.5)
			host.Position = UDim2.fromScale(0.5, 0.5)
			host.Size = UDim2.fromOffset(box, box)
			host.BackgroundTransparency = 1
			host.ZIndex = plate.ZIndex + 1
			host.Parent = plate
			IconArt.draw(host, "emerald", box, host.ZIndex + 1)
			art = host
		end
		if not art and rw.glyph then
			-- Boost and tag tiers have no model and no icon art, so they get a
			-- centred glyph.
			local g = Instance.new("TextLabel")
			g.Name = "Glyph"
			g.AnchorPoint = Vector2.new(0.5, 0.5)
			g.Position = UDim2.fromScale(0.5, 0.5)
			g.Size = UDim2.new(1, -12, 1, -12)
			g.BackgroundTransparency = 1
			g.Font = Enum.Font.FredokaOne
			g.TextScaled = true
			g.Text = rw.glyph
			g.ZIndex = plate.ZIndex + 1
			g:SetAttribute("NoPolish", true) -- emoji must not be recoloured/outlined
			g.Parent = plate
			art = g
		end
		if not art then
			art = UI.artSlot(plate, UDim2.new(1, -12, 1, -12), T.icons[rw.icon] or T.icons.coin)
			art.AnchorPoint = Vector2.new(0.5, 0.5)
			art.Position = UDim2.fromScale(0.5, 0.5)
			art.ZIndex = plate.ZIndex + 1
		end
		art.Name = "ArtSlot"
		-- locked art stays FULL-COLOUR (field study delta 8): the tile alone says
		-- "locked"; the reward itself is always worth seeing

		----------------------------------------------------- name + subtitle
		local rewardText
		local eggQty = 0
		if rw.kind == "Cash" then
			rewardText = shortCash(rw.amount) .. " Cash"
		elseif rw.kind == "Egg" then
			-- An egg tier can hand over more than one; pass tier 50 gives twelve.
			-- round 2.5: DescribeReward's text ALREADY carries " x<qty>" for a
			-- multi-egg tier, so appending it again here printed "Heartwood Egg x2
			-- x2" and then truncated to "Heartwood Egg..." in both columns (round 2
			-- QA). The name is now the bare egg name and the count is a pip on the
			-- art plate -- the bag's own idiom for "how many" -- so it never has to
			-- fit in the same 175px as the name. "x" not the multiplication sign:
			-- this game has been bitten by glyphs the shipped fonts cannot render.
			eggQty = tonumber(rw.qty) or 1
			rewardText = (rw.text or ""):gsub("%s+x%d+$", "")
		elseif rw.kind == "Emeralds" then
			rewardText = "+" .. tostring(rw.amount or 0) .. " Gems"
		else
			rewardText = rw.text
		end

		if eggQty > 1 then
			local pip = PC.statePlate({
				name = "QtyPip", text = "x" .. tostring(eggQty), colors = S.Role.Gold,
				size = UDim2.fromOffset(eggQty >= 10 and 38 or 32, 20),
				position = UDim2.new(1, 6, 1, 4), anchor = Vector2.new(1, 1),
				textSize = 13, zIndex = plate.ZIndex + 3, parent = plate,
			})
			pip.Name = "QtyPip"
		end

		local name = PC.read({
			name = "NameLabel", text = rewardText, size = 24, color = INK,
			frameSize = UDim2.fromOffset(TEXT_W, 28), position = UDim2.fromOffset(TEXT_X, NAME_Y),
			zIndex = card.ZIndex + 2, parent = card,
		})
		name.TextTruncate = Enum.TextTruncate.AtEnd

		local sub = PC.read({
			name = "SubLabel", text = subtitleFor(rw, SEASON.Number), size = 17,
			color = if claimable then Color3.fromHex("1F6E2A") else SUB,
			frameSize = UDim2.fromOffset(TEXT_W, 22), position = UDim2.fromOffset(TEXT_X, SUB_Y),
			zIndex = card.ZIndex + 2, parent = card,
		})
		sub.TextTruncate = Enum.TextTruncate.AtEnd

		----------------------------------------------------- action
		if claimable then
			local claimBtn = PC.button({
				kind = "positive", text = "CLAIM", name = "ClaimButton",
				size = UDim2.fromOffset(ACTION_W + 16, 54), textSize = 24, radius = 16, outline = 3,
				position = UDim2.new(1, -12, 0.5, 0), anchor = Vector2.new(1, 0.5),
				zIndex = card.ZIndex + 6, parent = card,
			})
			-- The ONE SeasonClaim:FireServer call site in this module. No local
			-- state mutation here -- the card only re-renders CLAIMED once the
			-- server pushes a fresh SeasonState with Claimed[tier] == true. The
			-- button goes BUSY meanwhile (auto-clears after 10s with a warning).
			claimBtn.Activated:Connect(function()
				if claimBtn:GetAttribute("UIBusy") == true then return end
				PC.setBusy(claimBtn, true, { timeout = 8 })
				-- the toast keeps the count the card moved onto its pip
				pendingClaim = { tier = tier, track = track, text = rewardText .. (if eggQty > 1 then " x" .. tostring(eggQty) else "") }
				-- track tells the server WHICH column; it re-checks gamepass
				-- ownership itself, so a spoofed "pass" here still cannot claim
				-- the paid track.
				ctx.remotes.SeasonClaim:FireServer(tier, track)
			end)
		elseif claimed then
			local mark = PC.statePlate({
				name = "ClaimedMark", text = "\u{2713} CLAIMED", colors = { Color3.fromHex("C9EFC2"), Color3.fromHex("B2E4A8") },
				size = UDim2.fromOffset(ACTION_W + 26, 40),
				position = UDim2.new(1, -12, 0.5, 0), anchor = Vector2.new(1, 0.5),
				textSize = 18, zIndex = card.ZIndex + 2, parent = card,
			})
			local ml = mark:FindFirstChild("Label")
			if ml and ml:IsA("TextLabel") then ml.TextColor3 = Color3.fromHex("1F6E2A") end
		elseif passLocked then
			-- the paid track: a padlock chip; the column's UNLOCK button is the way in
			PC.statePlate({
				name = "LockMarker", text = "\u{1F512} PREMIUM", colors = { Color3.fromHex("E4D3F7"), Color3.fromHex("D3BCF0") },
				size = UDim2.fromOffset(ACTION_W + 30, 40),
				position = UDim2.new(1, -12, 0.5, 0), anchor = Vector2.new(1, 0.5),
				textSize = 17, zIndex = card.ZIndex + 2, parent = card,
			})
		else
			-- an open-but-unreached rung names the requirement
			PC.statePlate({
				name = "LockMarker", text = "TIER " .. tier,
				size = UDim2.fromOffset(ACTION_W + 10, 40),
				position = UDim2.new(1, -12, 0.5, 0), anchor = Vector2.new(1, 0.5),
				textSize = 18, zIndex = card.ZIndex + 2, parent = card,
			})
			-- unreached rewards sit back a little so the reachable ones lead
			plate.BackgroundTransparency = 0.35
			name.TextTransparency = 0.25
			sub.TextTransparency = 0.25
		end
	end

	local function buildTierPill(row: Frame, tier: number, isNext: boolean)
		-- the tier spine: a gold plate column, the one vertical rhythm holding both
		-- tracks together. The NEXT tier to reach wears the blue selection ring --
		-- "you are here" in the kit's own grammar (blue = navigation).
		local badge = PC.plate({
			name = "TierBadge" .. tier,
			size = UDim2.fromOffset(TIER_COL_W, ROW_H - 6), -- round 2.5: rides the row height (was a fixed 88 over a 104 row)
			position = UDim2.new(0, TIER_X + TIER_COL_W / 2, 0.5, 0),
			anchor = Vector2.new(0.5, 0.5),
			colors = S.Role.Gold,
			radius = 22,
			outline = 5,
			zIndex = 15,
			parent = row,
		})
		PC.shout({
			name = "TierNumber", text = tostring(tier), size = 32,
			zIndex = badge.ZIndex + 2, parent = badge,
		})
		if isNext then
			local ring = Instance.new("Frame")
			ring.Name = "HereRing"
			ring.BackgroundTransparency = 1
			ring.Position = UDim2.fromOffset(-6, -6)
			ring.Size = UDim2.new(1, 12, 1, 12)
			ring.ZIndex = badge.ZIndex + 1
			ring.Parent = badge
			local rc = Instance.new("UICorner")
			rc.CornerRadius = UDim.new(0, 28)
			rc.Parent = ring
			local rs = Instance.new("UIStroke")
			rs.Thickness = 4
			rs.Color = S.Role.Selection
			rs.Parent = ring
			PC.shout({
				name = "NextTag", text = "NEXT", size = 13, color = Color3.new(1, 1, 1), strokeColor = S.Outline,
				frameSize = UDim2.fromOffset(TIER_COL_W, 16), position = UDim2.new(0, 0, 1, -18),
				zIndex = badge.ZIndex + 3, parent = badge,
			})
		end
	end

	-- Full-width divider that announces the final tier, per the design.
	local function buildMilestone(order: number, tier: number)
		local strip = Instance.new("Frame")
		strip.Name = "Milestone" .. tier
		strip.LayoutOrder = order
		strip.Size = UDim2.fromOffset(LADDER_W, MILESTONE_H)
		strip.BackgroundTransparency = 1
		strip.ZIndex = 15
		strip.Parent = scroll

		PC.shout({
			name = "MilestoneLabel", text = "MILESTONE \u{00B7} TIER " .. tier, size = 20,
			color = S.TitleInk.goals, strokeColor = Color3.new(1, 1, 1),
			frameSize = UDim2.fromScale(1, 1), zIndex = strip.ZIndex + 2, parent = strip,
		})
	end

	local function clearLadder()
		for _, c in ipairs(scroll:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
	end

	-- Row count is driven by SeasonConfig.Tiers, never a literal, so a config
	-- change resizes the ladder on its own.
	local function renderLadder(nextTier: number): (number, number)
		clearLadder()
		local tierCount = #SeasonConfig.Tiers
		local readyCount, claimedCount = 0, 0
		for tier = 1, tierCount do
			if tier == tierCount then
				buildMilestone(tier * 10 - 5, tier)
			end

			local row = Instance.new("Frame")
			row.Name = "TierRow" .. tier
			row.LayoutOrder = tier * 10
			row.Size = UDim2.fromOffset(LADDER_W, ROW_H)
			row.BackgroundTransparency = 1
			row.ZIndex = 15
			row.Parent = scroll

			buildRewardCard(row, tier, "free")
			buildTierPill(row, tier, tier == nextTier)
			buildRewardCard(row, tier, "pass")

			local reached = state.XP >= SeasonConfig.ThresholdFor(tier)
			if state.Claimed[tostring(tier)] == true then
				claimedCount += 1
			elseif reached then
				readyCount += 1
			end
			if state.PassOwned then
				if state.PassClaimed[tostring(tier)] == true then
					claimedCount += 1
				elseif reached then
					readyCount += 1
				end
			end
		end
		return readyCount, claimedCount
	end

	-- Gate for the rail-badge write below: render() also runs once at Build time
	-- with the all-zero placeholder state, and that zero used to DESTROY the
	-- correct join-time badge SeasonClient had already painted.
	local hasServerState = false

	local function render()
		local xpPerTier = SeasonConfig.XP_PER_TIER
		local tierCount = #SeasonConfig.Tiers
		local tierNow = math.min(math.floor(state.XP / xpPerTier), tierCount)
		local intoTier = state.XP - tierNow * xpPerTier

		kicker.Text = string.format("SEASON %02d   %s   %d TIERS", SEASON.Number, string.upper(SEASON.Name), tierCount)
		tierValue.Text = string.format("%d / %d", tierNow, tierCount)
		if tierNow >= tierCount then
			-- At the cap intoTier is 0, so the arithmetically-correct
			-- "0 / 250 to tier 50" renders an EMPTY bar and reads like no
			-- progress at the exact moment the track is finished.
			xpCaption.Text = string.format("Season XP  %s / %s  \u{00B7}  track complete", comma(state.XP), comma(tierCount * xpPerTier))
			xpLabel.Text = "MAX"
			UI.setFill(xpFill, 1, true)
		else
			xpCaption.Text = string.format("Season XP  %s / %s to tier %d", comma(intoTier), comma(xpPerTier), tierNow + 1)
			xpLabel.Text = string.format("%d / %d", intoTier, xpPerTier)
			UI.setFill(xpFill, xpPerTier > 0 and (intoTier / xpPerTier) or 0, true)
		end

		if daysLabel then
			local left = math.max(0, math.ceil(((SEASON.Ends :: number) - os.time()) / 86400))
			daysLabel.Text = string.format("%d DAYS LEFT", left)
		end

		-- a claim that the server has now confirmed (the card flips to CLAIMED in
		-- renderLadder below) gets its reward toast here, from the state push
		if pendingClaim and hasServerState then
			local claimMap = (pendingClaim.track == "pass" and state.PassClaimed or state.Claimed) or {}
			if claimMap[tostring(pendingClaim.tier)] == true then
				Toast.show({ text = "CLAIMED: " .. string.upper(pendingClaim.text), tone = "reward" })
			end
			pendingClaim = nil
		end

		local readyCount, claimedCount = renderLadder(math.min(tierNow + 1, tierCount))
		claimStatus.Text = string.format("%d READY", readyCount)
		claimedStatus.Text = string.format("%d CLAIMED", claimedCount)

		-- Kit README section 5 client state shape -- keep the shared ctx.state.pass
		-- table current for any other consumer.
		ctx.state.pass.level = tierNow
		ctx.state.pass.xp = intoTier
		ctx.state.pass.xpNeed = xpPerTier
		ctx.state.pass.claimedFree = state.Claimed
		if hasServerState then
			ctx.setBadge("pass", readyCount)
		end
	end

	----------------------------------------------------------- footer
	local footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.Position = UDim2.fromOffset(0, BODY_TOP + BODY_H + FOOTER_GAP)
	footer.Size = UDim2.fromOffset(PANEL_W, FOOTER_H)
	footer.BackgroundTransparency = 1
	footer.ZIndex = 12
	footer.Parent = group

	-- 2026-08-17 round-12 catch (probed live): both footer labels were
	-- strokeless WHITE sitting directly on the f5f8fc shell Body -- invisible.
	-- Dark ink per the light-surface rule; the existing TextTransparency
	-- knock-backs carry the hierarchy exactly as they did for white-on-dark.
	local footerNote = UI.label(footer, "Buying premium unlocks every tier you have already passed -- nothing is missed.", "meta", T.color.textOnLight)
	footerNote.Name = "FooterNote"
	footerNote.AnchorPoint = Vector2.new(0, 0.5)
	footerNote.Position = UDim2.new(0, 4, 0.5, 0)
	footerNote.TextTransparency = 0.25
	footerNote.ZIndex = 13

	local footerId = SEASON.Id
	if type(SEASON.Ends) == "number" then
		footerId = footerId .. "   ENDS " .. string.upper(os.date("!%d %b", SEASON.Ends :: number))
	end
	local footerTag = UI.label(footer, footerId, "meta", T.color.textOnLight)
	footerTag.Name = "FooterTag"
	footerTag.AnchorPoint = Vector2.new(1, 0.5)
	footerTag.Position = UDim2.new(1, -4, 0.5, 0)
	footerTag.TextTransparency = 0.35
	footerTag.ZIndex = 13

	----------------------------------------------------------- backdrop blur
	-- DailyPanel's setBlur block with a UNIQUE name -- questsBtn transitions Pass
	-- -> Goals, and setBlur destroys by NAME in Lighting, so a shared name would
	-- let one panel's close kill the other's live blur. The shell owns the dim
	-- scrim; the blur is per-panel. Size is SET, not tweened -- BlurEffect.Size is
	-- not on the proven tween whitelist in this place.
	local BLUR_NAME = "PassPanelBlur"
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
	closeBtn.MouseButton1Click:Connect(function()
		ctx.closePanel()
	end)
	questsBtn.MouseButton1Click:Connect(function()
		ctx.openPanel("goals")
	end)
	-- skipBtn and premiumBtn are deliberately unwired -- see the module header.

	-- Server-confirmed only: the ONLY place `state` is written is here, from a
	-- SeasonState push. No click handler in this module ever assigns into
	-- state.Claimed / state.XP.
	--
	-- PassOwned / PassClaimed are read DEFENSIVELY: SendState does not send them
	-- today, so they stay false/empty and the premium column stays locked. The
	-- day SeasonPassHandler starts sending them -- which is what pasting a real
	-- gamepass id will require -- this panel already understands them.
	ctx.remotes.SeasonState.OnClientEvent:Connect(function(s)
		if typeof(s) ~= "table" then
			return
		end
		hasServerState = true
		state.XP = s.XP or 0
		state.Claimed = s.Claimed or {}
		state.PassClaimed = s.PassClaimed or {}
		state.PassOwned = s.PassOwned == true
		render()
	end)

	-- Request a fresh state every time this panel becomes visible (mirrors
	-- SeasonClient's own open-time refresh) -- covers both the very first open
	-- (Build is lazy, called from inside openPanel) and every reopen. Visibility
	-- also drives the backdrop blur, additively.
	wrapper:GetPropertyChangedSignal("Visible"):Connect(function()
		if wrapper.Visible then
			ctx.remotes.SeasonState:FireServer()
			setBlur(true)
		else
			setBlur(false)
		end
	end)

	-- Belt-and-braces for the blur teardown: any path that hides the HOST while
	-- this wrapper stays Visible must still kill the global BlurEffect -- it
	-- post-processes the whole screen regardless of GUI visibility -- and restore
	-- it when the host returns with this panel still the visible one.
	ctx.host:GetPropertyChangedSignal("Visible"):Connect(function()
		if not ctx.host.Visible then
			setBlur(false)
		elseif wrapper.Visible then
			setBlur(true)
		end
	end)

	render() -- initial paint (zero state) before the first server response lands

	return wrapper
end

return PassPanel
