--!strict
-- PassPanel: kit README §3.1 Season Pass panel -- a GameHUDPanels consumer
-- module (StarterPlayer.StarterPlayerScripts.GameHUDPanels.PassPanel).
--
-- 1d/1e sweep (2026-08-04), following DailyPanel's shipped cream recipe:
-- the body flips from the kit's dark panel to the mock's cream (hand-built
-- UIPadding stays T.pad.panel 16 per side -- NOT Daily's panelWide 18 --
-- because ROW_CONTENT_W and the xpTrack flex width are measured against
-- 16); FREE reward cards flip to flat white + 3px #e5d3ac border + #4a3416
-- ink and wear Daily's corner-badge lock / claimed-green treatments; a
-- per-panel backdrop BlurEffect ("PassPanelBlur") rides the Visible
-- watcher. The HEADER IS DELIBERATELY UNTOUCHED -- gold IS this panel's
-- assigned accent (purple went to Daily) -- and so is every gold/olive/
-- dark piece of chrome: pass cards, ticket/level/tier badges, the rotated
-- label blocks, the dark XP track, the disabled CTA and the side column
-- (which floats OUTSIDE the cream body over the dimmed world, so its
-- white text stays white). ZERO wiring changed: remotes, state writes,
-- the hasServerState badge gate and the render flow are byte-identical.
--
-- Contract (kit README section: ctx from GameHUDClient):
--   return { Id = "pass", Build = function(ctx) -> Frame }
-- Build is called ONCE lazily on first open; the shell parents the returned
-- Frame into ctx.host and owns Visible toggling on every open/close after
-- that -- this module never sets its own Parent or drives its own open/close
-- animation.
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
--     client -> server: SeasonClaim:FireServer(tier: number)
--     Server validates level/ownership and, on success, re-sends SeasonState
--     with the new Claimed table. NEVER flip Claimed locally -- only the
--     next SeasonState push may change what a card renders as.
--
-- IMPORTANT game-data note (this is why the panel deviates from a literal
-- two-track reading of the kit): ReplicatedStorage.Modules.SeasonConfig's own
-- header comment says "Free track only for now -- premium track needs a
-- gamepass id," SeasonPassHandler/PlayerDataManager have no `passOwned` field
-- anywhere, and SendState's payload never includes one either. The kit's
-- LOCKED/CLAIMABLE/CLAIMED state machine (README §5) still applies exactly --
-- passOwned is simply always false in this build, so every Season Pass (gold)
-- column card is permanently LOCKED and carries no claim wiring; only the
-- Free (white) column reads live unlock/claim state and is wired to
-- SeasonClaim. This mirrors the disabled "COMING SOON" bottom CTA, which is
-- gated on that same missing gamepass id per the task spec. SeasonConfig
-- ships one Cash reward per tier (no separate free/pass reward items), so
-- both columns render that tier's Cash value; the Season Pass column is a
-- locked preview of the same number until a real premium reward table and
-- gamepass exist.
--
-- SeasonConfig rewards are scalar cash -> quantity chip renders x1;
-- revisit when itemized rewards exist.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting") -- 1d/1e sweep: the backdrop BlurEffect lives here
local modules = ReplicatedStorage:WaitForChild("Modules")
local SeasonConfig = require(modules:WaitForChild("SeasonConfig"))

local PassPanel = { Id = "pass" }

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

----------------------------------------------------------------- 1d/1e sweep palette (2026-08-04; ink stays the kit's)
-- Consumed ONLY by the FREE column and the scrollbar -- the gold pass
-- column keeps its kit tokens untouched. The claimed/lock constants are
-- DailyPanel's shipped mock values verbatim; #e5d3ac/#4a3416 are the
-- sweep's card-border / body-on-cream ink pair.
local CARD_BORDER = Color3.fromHex("#e5d3ac") -- soft border for white cards INSIDE the cream body (the body itself keeps the ink panel stroke)
local CARD_TEXT = Color3.fromHex("#4a3416") -- body ink on cream/white surfaces
local CLAIMED_BG = Color3.fromHex("#e9f7e4")
local CLAIMED_BORDER = Color3.fromHex("#bfe3b1")
local CLAIMED_TEXT = Color3.fromHex("#6da35e")
local CHECK_GREEN = Color3.fromHex("#3fae1f")
local LOCK_BADGE = Color3.fromHex("#5c5470") -- Daily's plum locked-badge fill
local SCROLL_THUMB_TAN = Color3.fromHex("#c9b585") -- darker sibling of CARD_BORDER, for the thumb on cream

function PassPanel.Build(ctx)
	local T = ctx.Tokens
	local UI = ctx.Builders

	----------------------------------------------------------- geometry (kit README §3.1, exact)
	local PANEL_W = T.size.panelWidth.pass -- 960
	local SIDE_W = 196
	local GAP_SIDE = 14
	local CARD_W, CARD_H = T.size.rewardCard.X, T.size.rewardCard.Y -- 178, 186
	local COL_GAP = T.pad.gridGap -- 11 (kit gives no explicit reward-card column gap; reusing the kit's own grid-gap token, same convention Backpack's grid uses)
	local ROW_GAP = 8
	local BADGE = T.size.tierBadge -- 58
	local HEADER_H = T.size.headerHeight -- 92
	local BODY_TOP = HEADER_H + 12
	local PROGRESS_H = 56
	local TRACK_MARGIN = 14
	local TRACK_H = CARD_H + ROW_GAP + BADGE + ROW_GAP + CARD_H -- 186+8+58+8+186 = 446
	local BODY_CONTENT_H = PROGRESS_H + TRACK_MARGIN + TRACK_H -- 516
	local BODY_H = T.pad.panel * 2 + BODY_CONTENT_H -- 548
	local CTA_H = 74
	local CTA_OVERLAP = 14
	local GROUP_H = BODY_TOP + BODY_H + CTA_H - CTA_OVERLAP -- 712
	local ROW_CONTENT_W = PANEL_W - T.pad.panel * 2 -- 928 (body's padded inner width)

	----------------------------------------------------------- module-local state (server-confirmed only)
	local state = { XP = 0, Claimed = {} }

	----------------------------------------------------------- root
	local wrapper = Instance.new("Frame")
	wrapper.Name = "PassPanel"
	wrapper.Size = UDim2.fromScale(1, 1)
	wrapper.BackgroundTransparency = 1
	wrapper.ZIndex = 10

	local group = Instance.new("Frame")
	group.Name = "Group"
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromScale(0.5, 0.5)
	group.Size = UDim2.fromOffset(PANEL_W + GAP_SIDE + SIDE_W, GROUP_H)
	group.BackgroundTransparency = 1
	group.ZIndex = 10
	group.Parent = wrapper

	local panelCol = Instance.new("Frame")
	panelCol.Name = "PanelColumn"
	panelCol.Position = UDim2.fromOffset(0, 0)
	panelCol.Size = UDim2.fromOffset(PANEL_W, GROUP_H)
	panelCol.BackgroundTransparency = 1
	panelCol.ZIndex = 10
	panelCol.Parent = group

	local sideCol = Instance.new("Frame")
	sideCol.Name = "SideColumn"
	sideCol.Position = UDim2.fromOffset(PANEL_W + GAP_SIDE, 0)
	sideCol.Size = UDim2.fromOffset(SIDE_W, GROUP_H)
	sideCol.BackgroundTransparency = 1
	sideCol.ZIndex = 10
	sideCol.Parent = group

	----------------------------------------------------------- header (common shell, README §3)
	local header = UI.surface(panelCol, UDim2.fromOffset(PANEL_W, HEADER_H), "gold", T.radius.panel, T.stroke.panel)
	header.Name = "Header"
	header.Position = UDim2.fromOffset(0, 0)
	header.ZIndex = 12
	UI.gloss(header, T.radius.panel)
	UI.hardShadow(header, T.shadowOffset.panel, T.radius.panel)

	local headerIcon = UI.artSlot(header, UDim2.fromOffset(62, 62), T.icons.pass)
	headerIcon.Name = "SectionIcon"
	headerIcon.AnchorPoint = Vector2.new(0, 0.5)
	headerIcon.Position = UDim2.new(0, 12, 0.5, 0)
	headerIcon.ZIndex = header.ZIndex + 2

	local headerTitle = UI.label(header, "Season Pass", "panelTitle", T.color.white)
	headerTitle.Name = "Title"
	headerTitle.AnchorPoint = Vector2.new(0, 0.5)
	headerTitle.Position = UDim2.new(0, 12 + 62 + 14, 0.5, 0)
	headerTitle.ZIndex = header.ZIndex + 2

	local closeBtn = UI.button(header, "X", "red", UDim2.fromOffset(T.size.closeButton.X, T.size.closeButton.Y), "buttonL")
	closeBtn.Name = "CloseButton"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -12, 0.5, 0)
	closeBtn.ZIndex = header.ZIndex + 2

	local questsBtn = UI.button(header, "Quests", "purple", UDim2.fromOffset(160, 66), "buttonL")
	questsBtn.Name = "QuestsButton"
	questsBtn.AnchorPoint = Vector2.new(1, 0.5)
	questsBtn.Position = UDim2.new(1, -12 - T.size.closeButton.X - 14, 0.5, 0)
	questsBtn.ZIndex = header.ZIndex + 2

	----------------------------------------------------------- body (mock 1d/1e cream -- restyled 2026-08-04)
	-- Was UI.panel (kit dark). UI.panel bundles THREE things -- the "panel"
	-- surface, a hardShadow and a UIPadding -- so the cream swap rebuilds
	-- all three by hand. Padding is T.pad.panel (16) per side, NOT
	-- DailyPanel's panelWide 18: ROW_CONTENT_W (928, geometry block above)
	-- and the xpTrack flex width below are measured against 16, so 18 would
	-- shift every child 2px and overflow the progress row. The cream
	-- surface KEEPS the ink T.stroke.panel border (#e5d3ac is only for
	-- cards INSIDE the body) and carries no gloss -- both per the shipped
	-- Daily recipe.
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

	----------------------------------------------------------- progress row
	local progressRow = Instance.new("Frame")
	progressRow.Name = "ProgressRow"
	progressRow.Position = UDim2.fromOffset(0, 0)
	progressRow.Size = UDim2.new(1, 0, 0, PROGRESS_H)
	progressRow.BackgroundTransparency = 1
	progressRow.ZIndex = 14
	progressRow.Parent = body

	local ticketSlot = UI.surface(progressRow, UDim2.fromOffset(62, PROGRESS_H), "goldSmall", T.radius.small, T.stroke.control)
	ticketSlot.Name = "TicketSlot"
	ticketSlot.Position = UDim2.fromOffset(0, 0)
	ticketSlot.ZIndex = 14
	UI.gloss(ticketSlot, T.radius.small)
	local ticketIcon = UI.artSlot(ticketSlot, UDim2.fromOffset(40, 34), T.icons.pass)
	ticketIcon.Name = "TicketIcon"
	ticketIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	ticketIcon.Position = UDim2.fromScale(0.5, 0.5)
	ticketIcon.ZIndex = ticketSlot.ZIndex + 2

	local LEVEL_W = 58
	local xpTrackW = ROW_CONTENT_W - 62 - 12 - LEVEL_W - 12 -- "flex:1" remainder (Skip is hidden -- excluded from the flex budget per spec)
	local xpTrack, xpFill = UI.track(progressRow, UDim2.fromOffset(xpTrackW, PROGRESS_H), "gold", T.radius.inner)
	xpTrack.Name = "XPTrack"
	xpTrack.Position = UDim2.fromOffset(62 + 12, 0)
	xpTrack.ZIndex = 14
	local xpLabel = UI.label(xpTrack, "0 / 0", "value", T.color.white)
	xpLabel.Name = "XPLabel"
	xpLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	xpLabel.Position = UDim2.fromScale(0.5, 0.5)
	xpLabel.Size = UDim2.fromScale(1, 1)
	xpLabel.AutomaticSize = Enum.AutomaticSize.None
	xpLabel.TextXAlignment = Enum.TextXAlignment.Center
	xpLabel.ZIndex = xpTrack.ZIndex + 3

	local levelBadge = UI.surface(progressRow, UDim2.fromOffset(LEVEL_W, PROGRESS_H), "goldSmall", T.radius.inner, T.stroke.control)
	levelBadge.Name = "LevelBadge"
	levelBadge.Position = UDim2.fromOffset(62 + 12 + xpTrackW + 12, 0)
	levelBadge.ZIndex = 14
	UI.gloss(levelBadge, T.radius.inner)
	local levelLabel = UI.label(levelBadge, "0", "value", T.color.white)
	levelLabel.Name = "LevelLabel"
	levelLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	levelLabel.Position = UDim2.fromScale(0.5, 0.5)
	levelLabel.Size = UDim2.fromScale(1, 1)
	levelLabel.AutomaticSize = Enum.AutomaticSize.None
	levelLabel.TextXAlignment = Enum.TextXAlignment.Center
	levelLabel.ZIndex = levelBadge.ZIndex + 2

	-- Skip button: HIDDEN per the task spec gate -- no tier-skip product id
	-- exists anywhere in this game's remotes/config. Built to kit geometry so
	-- it's ready the moment one ships; Visible=false until then.
	local skipBtn = UI.button(progressRow, "Skip", "green", UDim2.fromOffset(150, PROGRESS_H), "buttonM")
	skipBtn.Name = "SkipButton"
	skipBtn.Position = UDim2.fromOffset(62 + 12 + xpTrackW + 12 + LEVEL_W + 12, 0)
	skipBtn.ZIndex = 14
	skipBtn.Visible = false
	-- UI.button's non-disabled branch auto-parents a "HardShadow" sibling
	-- into skipBtn.Parent (progressRow) -- that sibling does NOT inherit
	-- skipBtn.Visible, so without this it would render as a stray dark
	-- rectangle even while the button itself is hidden.
	local skipShadow = progressRow:FindFirstChild("HardShadow")
	if skipShadow then
		skipShadow.Visible = false
	end

	----------------------------------------------------------- track area (label column + horizontal scroll)
	local trackArea = Instance.new("Frame")
	trackArea.Name = "TrackArea"
	trackArea.Position = UDim2.fromOffset(0, PROGRESS_H + TRACK_MARGIN)
	trackArea.Size = UDim2.new(1, 0, 0, TRACK_H)
	trackArea.BackgroundTransparency = 1
	trackArea.ZIndex = 14
	trackArea.Parent = body

	local LABEL_COL_W = 40
	local labelCol = Instance.new("Frame")
	labelCol.Name = "LabelColumn"
	labelCol.Position = UDim2.fromOffset(0, 0)
	labelCol.Size = UDim2.fromOffset(LABEL_COL_W, TRACK_H)
	labelCol.BackgroundTransparency = 1
	labelCol.ZIndex = 14
	labelCol.Parent = trackArea

	local freeBlock = UI.surface(labelCol, UDim2.fromOffset(LABEL_COL_W, 186), "freeLabel", T.radius.small, T.stroke.control)
	freeBlock.Name = "FreeLabelBlock"
	freeBlock.Position = UDim2.fromOffset(0, 0)
	freeBlock.ZIndex = 14
	local freeText = UI.label(freeBlock, "Free", "cardLabel", T.color.white)
	freeText.Name = "FreeLabelText"
	freeText.AnchorPoint = Vector2.new(0.5, 0.5)
	freeText.Position = UDim2.fromScale(0.5, 0.5)
	freeText.Size = UDim2.fromOffset(160, 30)
	freeText.AutomaticSize = Enum.AutomaticSize.None
	freeText.TextXAlignment = Enum.TextXAlignment.Center
	freeText.Rotation = -90
	freeText.ZIndex = freeBlock.ZIndex + 2

	local passBlock = UI.surface(labelCol, UDim2.fromOffset(LABEL_COL_W, 252), "passLabel", T.radius.small, T.stroke.control)
	passBlock.Name = "PassLabelBlock"
	passBlock.Position = UDim2.fromOffset(0, 186)
	passBlock.ZIndex = 14
	local passText = UI.label(passBlock, "Season Pass", "cardLabel", T.color.white)
	passText.Name = "PassLabelText"
	passText.AnchorPoint = Vector2.new(0.5, 0.5)
	passText.Position = UDim2.fromScale(0.5, 0.5)
	passText.Size = UDim2.fromOffset(220, 30)
	passText.AutomaticSize = Enum.AutomaticSize.None
	passText.TextXAlignment = Enum.TextXAlignment.Center
	passText.Rotation = -90
	passText.ZIndex = passBlock.ZIndex + 2

	local SCROLL_X = LABEL_COL_W + 10 -- "Track area gap 10" -- horizontal gap between the label column and the scroll region
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "TrackScroll"
	scroll.Position = UDim2.fromOffset(SCROLL_X, 0)
	scroll.Size = UDim2.new(1, -SCROLL_X, 0, TRACK_H)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollingDirection = Enum.ScrollingDirection.X
	scroll.ScrollBarThickness = 10
	scroll.ScrollBarImageColor3 = SCROLL_THUMB_TAN -- 1d/1e sweep: the kit's sage thumb was tuned for the dark panel and sat low-contrast on cream; cosmetic only
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.X
	scroll.ElasticBehavior = Enum.ElasticBehavior.Never
	scroll.ZIndex = 14
	scroll.Parent = trackArea

	local rowsList = Instance.new("UIListLayout")
	rowsList.FillDirection = Enum.FillDirection.Vertical
	rowsList.SortOrder = Enum.SortOrder.LayoutOrder
	rowsList.Padding = UDim.new(0, ROW_GAP)
	rowsList.Parent = scroll

	local function buildRow(name: string, order: number, height: number): (Frame, UIListLayout)
		local row = Instance.new("Frame")
		row.Name = name
		row.LayoutOrder = order
		row.Size = UDim2.new(0, 0, 0, height)
		row.AutomaticSize = Enum.AutomaticSize.X
		row.BackgroundTransparency = 1
		row.ZIndex = 14
		row.Parent = scroll
		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Horizontal
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Padding = UDim.new(0, COL_GAP)
		list.Parent = row
		return row, list
	end

	local freeRow = buildRow("FreeRow", 1, CARD_H)
	local badgeRow = buildRow("BadgeRow", 2, BADGE)
	local passRow = buildRow("PassRow", 3, CARD_H)

	----------------------------------------------------------- side column ("Max Rewards")
	local sideLabel = UI.label(sideCol, "Max Rewards", "value", T.color.white)
	sideLabel.Name = "MaxRewardsLabel"
	sideLabel.Position = UDim2.fromOffset(0, 0)
	sideLabel.Size = UDim2.new(1, 0, 0, 30)
	sideLabel.AutomaticSize = Enum.AutomaticSize.None
	sideLabel.TextXAlignment = Enum.TextXAlignment.Center
	sideLabel.ZIndex = 14

	local function buildTierPreview(order: number, track: string, footerText: string, footerColor: Color3)
		local unitH = 212 + 8 + 20 + 4 + 22
		local y = 30 + 12 + (order - 1) * (unitH + 14)
		local cardW = 176

		local card = UI.surface(sideCol, UDim2.fromOffset(cardW, 212), "panel", 15, T.stroke.control)
		card.Name = "TierPreview" .. order
		card.AnchorPoint = Vector2.new(0.5, 0)
		card.Position = UDim2.new(0.5, 0, 0, y)
		card.ZIndex = 14
		UI.rainbowRing(card, 15)

		local art = UI.artSlot(card, UDim2.new(1, -16, 1, -16), track == "pass" and T.icons.pass or T.icons.coin)
		art.Name = "ArtSlot"
		art.AnchorPoint = Vector2.new(0.5, 0.5)
		art.Position = UDim2.fromScale(0.5, 0.5)
		art.ZIndex = card.ZIndex + 2

		local tierCount = #SeasonConfig.Tiers -- derived, not a literal "50" -- the kit mockup's "50" is a 25-tier track's own max, this game ships 25
		local badge = UI.surface(card, UDim2.fromOffset(54, 54), "goldSmall", T.radius.inner, T.stroke.control)
		badge.Name = "TierBadge"
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.new(1, 12, 0, -12)
		badge.ZIndex = card.ZIndex + 4
		UI.gloss(badge, T.radius.inner)
		local badgeLabel = UI.label(badge, tostring(tierCount), "value", T.color.white)
		badgeLabel.Name = "TierBadgeLabel"
		badgeLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		badgeLabel.Position = UDim2.fromScale(0.5, 0.5)
		badgeLabel.Size = UDim2.fromScale(1, 1)
		badgeLabel.AutomaticSize = Enum.AutomaticSize.None
		badgeLabel.TextXAlignment = Enum.TextXAlignment.Center
		badgeLabel.ZIndex = badge.ZIndex + 2

		local qty = UI.label(sideCol, "x1", "chip", T.color.white)
		qty.Name = "Qty" .. order
		qty.AnchorPoint = Vector2.new(0.5, 0)
		qty.Position = UDim2.new(0.5, 0, 0, y + 212 + 8)
		qty.Size = UDim2.new(1, 0, 0, 20)
		qty.AutomaticSize = Enum.AutomaticSize.None
		qty.TextXAlignment = Enum.TextXAlignment.Center
		qty.ZIndex = 14

		local footer = UI.label(sideCol, footerText, "cardLabel", footerColor)
		footer.Name = "Footer" .. order
		footer.AnchorPoint = Vector2.new(0.5, 0)
		footer.Position = UDim2.new(0.5, 0, 0, y + 212 + 8 + 20 + 4)
		footer.Size = UDim2.new(1, 0, 0, 22)
		footer.AutomaticSize = Enum.AutomaticSize.None
		footer.TextXAlignment = Enum.TextXAlignment.Center
		footer.ZIndex = 14
	end

	buildTierPreview(1, "free", "Free", T.color.white)
	buildTierPreview(2, "pass", "Season Pass", T.color.textAccent)

	----------------------------------------------------------- bottom CTA (disabled -- no gamepass id yet, per spec)
	local CTA_W = 320
	local cta = UI.button(panelCol, "COMING SOON", "disabled", UDim2.fromOffset(CTA_W, CTA_H), "buttonL")
	cta.Name = "CTAButton"
	cta.AnchorPoint = Vector2.new(0.5, 0)
	cta.Position = UDim2.new(0.5, 0, 0, BODY_TOP + BODY_H - CTA_OVERLAP)
	cta.ZIndex = 16

	----------------------------------------------------------- reward-card state machine (kit README §5)
	local function buildLockBadge(card: Frame)
		local lock = UI.surface(card, UDim2.fromOffset(T.size.lockBadge, T.size.lockBadge), "lockBadge", 13, T.stroke.chip)
		lock.Name = "LockBadge"
		lock.AnchorPoint = Vector2.new(1, 0)
		lock.Position = UDim2.new(1, 8, 0, -8)
		lock.ZIndex = card.ZIndex + 6
		local glyph = UI.label(lock, "\u{1F512}", "chip", T.color.textOnLight)
		glyph.Name = "Glyph"
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.fromScale(0.5, 0.5)
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.AutomaticSize = Enum.AutomaticSize.None
		glyph.TextXAlignment = Enum.TextXAlignment.Center
		glyph.TextSize = 22
		glyph.ZIndex = lock.ZIndex + 1
	end

	-- 1d/1e sweep (2026-08-04): DailyPanel's 28px corner badge (2.5px white
	-- ring + glyph) for the FREE column's white cards -- plum lock when
	-- LOCKED, green check when CLAIMED (the kit's grey lockBadge stays on
	-- the gold pass column, where it has contrast). Parented to the CARD,
	-- not the slot: Daily's slot-parenting trick exists because ITS cards
	-- carry an 8px UIPadding that drags overhang furniture inward; these
	-- cards have no UIPadding, so card-relative offsets already land on the
	-- true edges (the kit lockBadge above banks on the same fact).
	local function buildCornerBadge(card: Frame, fill: Color3, glyphText: string)
		local badge = Instance.new("Frame")
		badge.Name = "CornerBadge"
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.new(1, 8, 0, -8)
		badge.Size = UDim2.fromOffset(28, 28)
		badge.BackgroundColor3 = fill
		badge.BorderSizePixel = 0
		badge.ZIndex = card.ZIndex + 8
		badge.Parent = card
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

	local function buildClaimPill(card: Frame, tier: number)
		local pill = UI.button(card, "CLAIM", "green", UDim2.new(1, -16, 0, T.size.claimPill), "buttonM")
		pill.Name = "ClaimPill"
		pill.AnchorPoint = Vector2.new(0.5, 1)
		pill.Position = UDim2.new(0.5, 0, 1, -8)
		pill.ZIndex = card.ZIndex + 6
		-- The ONE SeasonClaim:FireServer call site in this module. No local
		-- state mutation here -- the card only re-renders CLAIMED once the
		-- server pushes a fresh SeasonState with Claimed[tier] == true.
		pill.MouseButton1Click:Connect(function()
			ctx.remotes.SeasonClaim:FireServer(tier)
		end)
	end

	-- (buildClaimedOverlay -- the near-black rgba(12,18,8,.58) scrim + white
	-- check circle -- was removed in the 1d/1e sweep: CLAIMED is reachable
	-- from the free column only, and its treatment is now the claimed-green
	-- recolor inside buildRewardCard's state machine below.)

	local function buildRewardCard(parent: Frame, tier: number, def, track: string)
		local isPass = track == "pass"
		-- UI.hardShadow parents its shadow copy as a SIBLING of the frame you
		-- pass it (`sh.Parent = frame.Parent`, see UIKit.Builders). `parent`
		-- here is freeRow/passRow, which carries its own horizontal
		-- UIListLayout -- calling UI.hardShadow directly on `card` would drop
		-- an extra untracked Frame into that same list, silently doubling
		-- each row's item count and corrupting the 178-wide column layout.
		-- A non-list-managed `slot` wrapper (the actual list item) contains
		-- both `card` and its shadow sibling, keeping the row's child count
		-- exactly equal to the tier count.
		local slot = Instance.new("Frame")
		slot.Name = (isPass and "Pass" or "Free") .. "Slot" .. tier
		slot.LayoutOrder = tier
		slot.Size = UDim2.fromOffset(CARD_W, CARD_H)
		slot.BackgroundTransparency = 1
		slot.ZIndex = 15
		slot.Parent = parent

		local card = UI.surface(slot, UDim2.fromOffset(CARD_W, CARD_H), isPass and "passCard" or "freeCard", T.radius.control, T.stroke.control)
		card.Name = (isPass and "Pass" or "Free") .. "Card" .. tier
		card.ZIndex = 15
		if isPass then
			-- gold pass cards keep the full kit treatment (passCard gradient,
			-- ink stroke, hard shadow) -- they ARE the panel's accent.
			UI.hardShadow(card, T.shadowOffset.control, T.radius.control)
		else
			-- 1d/1e sweep (2026-08-04): the freeCard grey ramp read muddy on
			-- the cream body -- recolor the surface's OWN gradient/stroke in
			-- place (DailyPanel's header pattern; a UI.surface frame's only
			-- direct UIGradient/UIStroke children are its own, so
			-- FindFirstChildOfClass is unambiguous, and no second UI.stroke is
			-- ever attached). Flat white + 3px #e5d3ac soft border, and NO
			-- hard shadow: Daily's cream-body cards ship shadowless. The
			-- `slot` wrapper above stays regardless -- it is the row's
			-- child-count contract either way.
			local grad = card:FindFirstChildOfClass("UIGradient")
			if grad then
				grad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
			end
			local border = card:FindFirstChildOfClass("UIStroke")
			if border then
				border.Color = CARD_BORDER
				border.Thickness = 3
			end
		end

		-- 1d/1e sweep: free-column ink is the mock's body-on-cream #4a3416
		-- (textOnLight was tuned for the old grey ramp); the gold column
		-- keeps textOnGoldCard.
		local textColor = isPass and T.color.textOnGoldCard or CARD_TEXT

		local name = UI.label(card, shortCash(def.Cash), "cardLabel", textColor)
		name.Name = "NameLabel"
		name.Position = UDim2.new(0.5, 0, 0, 7)
		name.AnchorPoint = Vector2.new(0.5, 0)
		name.Size = UDim2.new(1, -16, 0, 24)
		name.AutomaticSize = Enum.AutomaticSize.None
		name.TextXAlignment = Enum.TextXAlignment.Center
		name.ZIndex = card.ZIndex + 2

		local art = UI.artSlot(card, UDim2.new(1, -16, 1, -70), track == "pass" and T.icons.pass or T.icons.coin)
		art.Name = "ArtSlot"
		art.AnchorPoint = Vector2.new(0.5, 0)
		art.Position = UDim2.new(0.5, 0, 0, 34)
		art.ZIndex = card.ZIndex + 1

		-- Quantity chip (kit README §3.1): SeasonConfig rewards are scalar
		-- cash -> quantity chip renders x1; revisit when itemized rewards
		-- exist. Visible in LOCKED/CLAIMED; hidden in CLAIMABLE (state
		-- machine below toggles it).
		local qty = UI.label(card, "x1", "value", textColor)
		qty.Name = "QtyChip"
		qty.AnchorPoint = Vector2.new(1, 1)
		qty.Position = UDim2.new(1, -8, 1, -6)
		qty.Size = UDim2.fromOffset(36, 18)
		qty.AutomaticSize = Enum.AutomaticSize.None
		qty.TextXAlignment = Enum.TextXAlignment.Right
		qty.ZIndex = card.ZIndex + 2

		-- state machine (README §5): LOCKED / CLAIMABLE / CLAIMED. The pass
		-- (gold) column is always LOCKED -- see the module header note on why
		-- passOwned has no backing data in this build.
		local unlocked = (not isPass) and (state.XP >= SeasonConfig.ThresholdFor(tier))
		local claimed = (not isPass) and (state.Claimed[tostring(tier)] == true)

		-- Same branches as ever ("isPass or not unlocked" merely split in two
		-- so each column wears its own lock) -- only the badge builders and
		-- the CLAIMED skin changed in the 1d/1e sweep. No wiring lives here
		-- beyond buildClaimPill's untouched SeasonClaim connect.
		if isPass then
			-- always LOCKED (no passOwned backing data -- module header). The
			-- kit's grey lockBadge keeps its contrast on gold: unchanged.
			buildLockBadge(card)
		elseif not unlocked then
			-- 1d/1e sweep: the grey kit badge goes near-invisible on the flat
			-- white card -- locked FREE cards wear Daily's plum corner lock.
			buildCornerBadge(card, LOCK_BADGE, "\u{1F512}")
		elseif not claimed then
			UI.claimRing(card)
			buildClaimPill(card, tier)
			qty.Visible = false -- CLAIMABLE: hide qty chip to give CLAIM pill room
		else
			-- CLAIMED -- free column only (gold can never get here, see above).
			-- 1d/1e sweep: the old near-black scrim overlay read heavy on a
			-- white card; adopt DailyPanel's claimed language instead -- soft
			-- green card, #bfe3b1 border, green corner check -- so "claimed =
			-- soft green" is one language across the cream panels. The recolor
			-- rides the SAME gradient/stroke instances the white flip above
			-- already touched (thickness is already 3 from that flip).
			local grad = card:FindFirstChildOfClass("UIGradient")
			if grad then
				grad.Color = ColorSequence.new(CLAIMED_BG)
			end
			local border = card:FindFirstChildOfClass("UIStroke")
			if border then
				border.Color = CLAIMED_BORDER
			end
			name.TextColor3 = CLAIMED_TEXT
			qty.TextColor3 = CLAIMED_TEXT
			buildCornerBadge(card, CHECK_GREEN, "\u{2713}")
		end
	end

	local function buildTierBadge(parent: Frame, tier: number)
		local col = Instance.new("Frame")
		col.Name = "BadgeCol" .. tier
		col.LayoutOrder = tier
		col.Size = UDim2.fromOffset(CARD_W, BADGE)
		col.BackgroundTransparency = 1
		col.ZIndex = 15
		col.Parent = parent

		local badge = UI.surface(col, UDim2.fromOffset(BADGE, BADGE), "goldSmall", T.radius.inner, T.stroke.control)
		badge.Name = "TierBadge"
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.Position = UDim2.fromScale(0.5, 0.5)
		badge.ZIndex = 15
		UI.gloss(badge, T.radius.inner)
		local label = UI.label(badge, tostring(tier), "value", T.color.white)
		label.Name = "TierNumber"
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.fromScale(1, 1)
		label.AutomaticSize = Enum.AutomaticSize.None
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.ZIndex = badge.ZIndex + 2
	end

	local function clearRow(row: Frame)
		for _, c in ipairs(row:GetChildren()) do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
	end

	-- Card count is driven by SeasonConfig.Tiers (currently 25), never a
	-- literal, so a future config change resizes the track automatically.
	local function renderTrack(): number
		clearRow(freeRow)
		clearRow(badgeRow)
		clearRow(passRow)
		local claimableCount = 0
		for tier, def in ipairs(SeasonConfig.Tiers) do
			buildRewardCard(freeRow, tier, def, "free")
			buildTierBadge(badgeRow, tier)
			buildRewardCard(passRow, tier, def, "pass")
			local unlocked = state.XP >= SeasonConfig.ThresholdFor(tier)
			local claimed = state.Claimed[tostring(tier)] == true
			if unlocked and not claimed then
				claimableCount += 1
			end
		end
		return claimableCount
	end

	-- Gate for the rail-badge write below: render() also runs once at Build
	-- time with the all-zero placeholder state, and that zero used to DESTROY
	-- the correct join-time badge SeasonClient had already painted (review
	-- catch) -- for the whole first-open server round trip on the rail that
	-- stays visible above open panels.
	local hasServerState = false

	local function render()
		local xpPerTier = SeasonConfig.XP_PER_TIER
		local tierCount = #SeasonConfig.Tiers
		local tierNow = math.min(math.floor(state.XP / xpPerTier), tierCount)
		local intoTier = state.XP - tierNow * xpPerTier

		xpLabel.Text = string.format("%d / %d", intoTier, xpPerTier)
		UI.setFill(xpFill, xpPerTier > 0 and (intoTier / xpPerTier) or 0, true)
		levelLabel.Text = tostring(tierNow)

		local claimableCount = renderTrack()

		-- Kit README §5 client state shape -- keep the shared ctx.state.pass
		-- table current for any other consumer (e.g. a future badge/summary).
		ctx.state.pass.level = tierNow
		ctx.state.pass.xp = intoTier
		ctx.state.pass.xpNeed = xpPerTier
		ctx.state.pass.claimedFree = state.Claimed
		if hasServerState then
			ctx.setBadge("pass", claimableCount)
		end
	end

	----------------------------------------------------------- backdrop blur (mock 1d/1e: dim + blur behind the panel)
	-- 1d/1e sweep (2026-08-04): DailyPanel's setBlur block with a UNIQUE
	-- name -- questsBtn transitions Pass -> Goals, and setBlur destroys by
	-- NAME in Lighting, so a shared name would let one panel's close kill
	-- the other's live blur. The shell owns the dim scrim; the blur is
	-- per-panel. Size is SET, not tweened -- BlurEffect.Size is not on the
	-- proven tween whitelist in this place.
	local BLUR_NAME = "PassPanelBlur"
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
	questsBtn.MouseButton1Click:Connect(function()
		ctx.openPanel("goals")
	end)

	-- Server-confirmed only: the ONLY place `state` is written is here, from
	-- a SeasonState push. No click handler in this module ever assigns into
	-- state.Claimed / state.XP.
	ctx.remotes.SeasonState.OnClientEvent:Connect(function(s)
		if typeof(s) ~= "table" then
			return
		end
		hasServerState = true
		state.XP = s.XP or 0
		state.Claimed = s.Claimed or {}
		render()
	end)

	-- Request a fresh state every time this panel becomes visible (mirrors
	-- SeasonClient's own open-time refresh) -- covers both the very first
	-- open (Build is lazy, called from inside openPanel) and every reopen.
	-- 1d/1e sweep (2026-08-04): visibility now ALSO drives the backdrop
	-- blur, additively -- the open-time FireServer refresh is untouched.
	wrapper:GetPropertyChangedSignal("Visible"):Connect(function()
		if wrapper.Visible then
			ctx.remotes.SeasonState:FireServer()
			setBlur(true)
		else
			setBlur(false)
		end
	end)

	-- Belt-and-braces for the blur teardown (DailyPanel review catch): any
	-- path that hides the HOST while this wrapper stays Visible (legacy
	-- single-open force-closes, future shell changes) must still kill the
	-- global BlurEffect -- it post-processes the whole screen regardless of
	-- GUI visibility -- and restore it when the host returns with this
	-- panel still the visible one.
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
