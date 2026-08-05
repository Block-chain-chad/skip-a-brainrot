--!strict
-- SettingsPanel: kit README §3.3 Settings panel -- a GameHUDPanels consumer
-- module (StarterPlayer.StarterPlayerScripts.GameHUDPanels.SettingsPanel).
--
-- Contract (same as every other panel in this family -- see GoalsPanel):
--   return { Id = "settings", Build = function(ctx) -> Frame }
-- Build is called ONCE lazily on first open; the shell (GameHUDClient) parents
-- the returned Frame into ctx.host and owns Visible toggling on every
-- open/close after that -- this module never sets its own Parent or drives
-- its own open/close animation.
--
-- 2026-08-04 RESTYLE (1d/1e sweep): visual-only pass to the shipped cream
-- recipe (reference: DailyPanel) -- orange header #ffb02e -> #ff7d00
-- (Settings' per-panel accent), cream body (padding stays EXACTLY
-- T.pad.panel 16 per side -- the BODY_H/BODY_INNER_W math below depends on
-- it, do NOT copy DailyPanel's panelWide 18), white row cards with 3px
-- #e5d3ac borders and #4a3416 labels, cream-readable redeem feedback
-- colours, and a per-panel backdrop BlurEffect ("SettingsPanelBlur").
-- Every control keeps its kit look (slider tracks/knobs, quality tab
-- buttons, toggle switches, rarity chips, footer buttons, the dark redeem
-- box), and ALL wiring -- saves, seams, applySettings, the drag machine --
-- is byte-identical to the previous version.
--
-- ============================================================================
-- SCOPE (task-10-brief, kit README §3.3 MINUS Reset Data):
--   AUDIO    -- Music / Sound FX sliders. Live SoundKit.SetCategoryVolume
--              during drag, SettingsSave:FireServer on release (click-to-set
--              behaves the same way: InputBegan sets + previews once,
--              InputEnded fires the save even with zero movement).
--   GRAPHICS -- Low/Medium/High segmented quality control. Client-local only
--              (kit gives it no server-authoritative effect beyond
--              persistence): toggles Lighting.Bloom/SunRays Enabled,
--              nil-guarded (see applyQuality below).
--   GAMEPLAY -- two real toggles, each bridged into an EXISTING mechanism
--              rather than invented fresh -- see "REAL SEAM" 1/2 below:
--                fastSpin        -> WheelClient's own `fastSpin` local
--                hideOwnBanners  -> RareCatchClient's own-catch banner
--   FOOTER   -- Redeem Code only (Reset Data intentionally absent, per
--              brief). See REDEEM CODE DEVIATION below -- this reuses a
--              REAL, already-live remote instead of the stub the brief's
--              literal text describes.
--
-- ============================================================================
-- REDEEM CODE DEVIATION (read before touching this section again):
-- The task brief asks for a brand-new stub RemoteFunction named "RedeemCode"
-- under ReplicatedStorage.Remotes that always answers `false, "Invalid
-- code"`. That name is NOT free: ReplicatedStorage.Remotes.RedeemCode
-- already exists, as a RemoteEvent, wired end-to-end to a REAL promo-code
-- system --
--   ServerScriptService.Modules.DailyRewardHandler.redeemCode(player, code)
--   ServerScriptService.Modules.CodeConfig (4 live codes: WELCOME, BRAINROT,
--     LAKETAHOE, SKIPMASTER)
--   StarterPlayer.StarterPlayerScripts.DailyRewardClient (the legacy Daily
--     HUD's own REDEEM box, still live)
-- Two problems with following the brief literally: (1) Roblox allows two
-- sibling instances with the same Name, so creating a SECOND "RedeemCode"
-- (a RemoteFunction) next to the real one makes every future
-- `remotes.RedeemCode` / `remotes:WaitForChild("RedeemCode")` lookup in the
-- game ambiguous by insertion order; (2) a stub that always fails would be a
-- real functional regression the instant a player types a genuine code
-- (e.g. "WELCOME") into this NEW panel instead of the old Daily UI and gets
-- told it's invalid. So this panel's footer fires the EXISTING RedeemCode
-- RemoteEvent directly (remotes.RedeemCode:FireServer(code) /
-- .OnClientEvent for the {Success, Message} reply) -- nothing new was
-- created server-side for redemption. Documented in task-10-report.md.
--
-- QUALITY ENUM DEVIATION: the brief spells the quality whitelist
-- {"Low","Med","High"}, but StarterPlayerScripts.GameHUDClient's own
-- ctx.state.settings default (shipped Task 3, already live) is
-- `quality = "Medium"`, and the kit's own settings.png capture labels the
-- middle button "Medium" in full. SettingsService validates "Medium" (not
-- "Med") for the same reason -- see that module's own header comment.
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService") -- FIX F4 (2026-07-30 fix wave): shared slider-release watcher, see buildSliderRow

local player = Players.LocalPlayer
local modules = ReplicatedStorage:WaitForChild("Modules")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local SoundKit = require(modules:WaitForChild("SoundKit"))
-- tier names + colours for the per-rarity Skip Catch Animation chips
local RarityConfig = require(modules:WaitForChild("RarityConfig"))

-- Bounded wait (matches ToastClient's own `WaitForChild(name, 10)` -- see
-- StarterPlayerScripts.ToastClient): SettingsSave is SELF-HEAL created by
-- SettingsService.Init() server-side, which only runs during Play. A bare
-- unbounded WaitForChild here would hang forever if this module is ever
-- require()'d outside Play (e.g. an Edit-mode compile probe), since nothing
-- will ever create the remote in that context.
local settingsSaveRemote = remotes:WaitForChild("SettingsSave", 5)
if not settingsSaveRemote then
	warn("[SettingsPanel] SettingsSave remote missing (no server this session?) -- saves will no-op")
end
local function fireSave(tbl)
	if settingsSaveRemote then
		settingsSaveRemote:FireServer(tbl)
	end
end

local SettingsPanel = { Id = "settings" }

local QUALITY_OPTIONS = { "Low", "Medium", "High" }
local QUALITY_SET = { Low = true, Medium = true, High = true }

----------------------------------------------------------- mock palette (1d/1e sweep 2026-08-04; ink and controls stay the kit's)
local HEADER_TOP = Color3.fromHex("#ffb02e") -- Settings' per-panel accent: neutral orange
local HEADER_BOT = Color3.fromHex("#ff7d00")
local CARD_BORDER = Color3.fromHex("#e5d3ac") -- white row-card border on cream
local BODY_INK = Color3.fromHex("#4a3416") -- body-text-on-cream (same ink DailyPanel's hintLabel uses)
local MSG_GREEN = Color3.fromHex("#3fae1f") -- redeem success on cream (DailyPanel's CHECK_GREEN)
local MSG_RED = Color3.fromHex("#A8140F") -- redeem failure on cream (the kit red gradient's bottom stop)

----------------------------------------------------------- GRAPHICS: client-local Lighting toggles, nil-guarded
-- Confirmed live before writing this: game.Lighting currently has NEITHER a
-- BloomEffect NOR a SunRaysEffect instance (only ColorCorrectionEffect +
-- Sky) -- so today every quality level below is a no-op in practice, on
-- purpose: FindFirstChildOfClass returns nil and both branches skip. The
-- moment a lighting artist adds those effects to Lighting, this starts
-- working with no code change. Low = both off, Medium = Bloom on/SunRays
-- off, High = both on (task brief).
local function applyQuality(quality)
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	local bloomOn = quality == "Medium" or quality == "High"
	local sunRaysOn = quality == "High"
	if bloom then
		bloom.Enabled = bloomOn
	end
	if sunRays then
		sunRays.Enabled = sunRaysOn
	end
end

----------------------------------------------------------- REAL SEAM 1: fastSpin -> WheelClient
-- WheelClient (StarterPlayerScripts.WheelClient) is a LocalScript, not a
-- ModuleScript -- it returns nothing, so nothing can require() it or reach
-- into its module-local `fastSpin` variable directly. Bridged instead
-- through a client-local Instance Attribute on the player (no server round
-- trip needed for the RUNTIME effect, matching WheelClient's own
-- "client-local comfort setting... no server call" comment for what the
-- attribute drives). WheelClient was given a matching edit (see its own
-- "fast spin" section) to read/listen on this SAME attribute instead of
-- only its in-wheel toggle button, so both controls stay in sync no matter
-- which one the player uses. `player` is nil-guarded here since this
-- function can run in a probe/Edit-mode context where LocalPlayer is nil.
local function applyFastSpin(on)
	if player then
		player:SetAttribute("FastSpinPref", on == true)
	end
end

----------------------------------------------------------- REAL SEAM 2: hideOwnBanners -> RareCatchClient
-- RareCatchClient's rareCatch.OnClientEvent handler now checks this SAME
-- attribute before enqueueing a banner for a catch that was YOURS (see its
-- own "UIKIT (Task 10)" comment) -- other players' banners are completely
-- unaffected, this only ever suppresses your own. Cheap seam: one added
-- guard clause there, no restructuring of its sound/queue logic.
local function applyHideOwnBanners(on)
	if player then
		player:SetAttribute("HideOwnBanners", on == true)
	end
end

----------------------------------------------------------- REAL SEAM 3: skipReveal -> CatchRevealClient / ClientMain
-- Per-rarity catch-animation skip (user request 2026-08-04, v2 -- "just
-- skip the actual catch animation... for whatever rarity they desire"):
-- the Pull ceremony is skipped only for the rarities the player picked;
-- ClientMain's text card announces those catches instead. One boolean
-- attribute per tier (SkipRevealCommon .. SkipRevealGod), read at time of
-- use, so a mid-session change covers the very next catch. The v1 camera
-- skip is gone on purpose -- the tracking camera always flies again.
local function applySkipReveal(t)
	if not player then return end
	t = type(t) == "table" and t or {}
	for _, tier in ipairs(RarityConfig) do
		player:SetAttribute("SkipReveal" .. tier.Name, t[tier.Name] == true)
	end
end

----------------------------------------------------------- top-level settings apply (require-time wiring, correctly outside Build -- same pattern IndexPanel's `discovered` uses)
-- Applied the instant a Settings payload is known, whether or not this panel
-- has EVER been opened -- audio volume / quality / the two gameplay seams
-- above all need to take effect on join, not only after a player happens to
-- visit Settings. `applied` also seeds the panel's own controls on first
-- Build (see below), and `onAppliedChanged` (assigned inside Build once the
-- widgets exist) keeps them in sync if a payload lands again afterward.
local applied = { music = 0.7, sfx = 1, quality = "Medium", fastSpin = false, hideOwnBanners = false, skipReveal = {} }
local onAppliedChanged = nil

local function applySettings(s)
	if typeof(s) ~= "table" then
		return
	end
	if typeof(s.music) == "number" then
		applied.music = math.clamp(s.music, 0, 1)
		SoundKit.SetCategoryVolume("music", applied.music)
	end
	if typeof(s.sfx) == "number" then
		applied.sfx = math.clamp(s.sfx, 0, 1)
		SoundKit.SetCategoryVolume("sfx", applied.sfx)
	end
	if typeof(s.quality) == "string" and QUALITY_SET[s.quality] then
		applied.quality = s.quality
		applyQuality(applied.quality)
	end
	if typeof(s.fastSpin) == "boolean" then
		applied.fastSpin = s.fastSpin
		applyFastSpin(applied.fastSpin)
	end
	if typeof(s.hideOwnBanners) == "boolean" then
		applied.hideOwnBanners = s.hideOwnBanners
		applyHideOwnBanners(applied.hideOwnBanners)
	end
	if typeof(s.skipReveal) == "table" then
		applied.skipReveal = s.skipReveal
		applySkipReveal(applied.skipReveal)
	elseif s.skipAnimations == true and next(applied.skipReveal) == nil then
		-- v1 migration: the short-lived single Skip Animations toggle becomes
		-- "skip every rarity", so a player who had it ON keeps the behavior
		-- until they touch the chips (which then persists the new shape)
		local all = {}
		for _, tier in ipairs(RarityConfig) do all[tier.Name] = true end
		applied.skipReveal = all
		applySkipReveal(all)
	end
	if onAppliedChanged then
		onAppliedChanged()
	end
end

remotes.DataUpdated.OnClientEvent:Connect(function(snap)
	if typeof(snap) == "table" then
		applySettings(snap.Settings)
	end
end)
task.spawn(function()
	local ok, snap = pcall(function()
		return remotes.GetInitialData:InvokeServer()
	end)
	if ok and typeof(snap) == "table" then
		applySettings(snap.Settings)
	end
end)

----------------------------------------------------------- Build
function SettingsPanel.Build(ctx)
	local T = ctx.Tokens
	local UI = ctx.Builders

	----------------------------------------------------------- geometry (kit README §3.3, exact where tokenised)
	local PANEL_W = T.size.panelWidth.settings -- 700
	local HEADER_H = T.size.headerHeight -- 92
	local BODY_TOP = HEADER_H + 12
	local BODY_INNER_W = PANEL_W - T.pad.panel * 2 -- 668

	local SECTION_HEADER_H = 24
	local SLIDER_ROW_H = 54 -- kit "Slider row height 54"
	local SEGMENT_ROW_H = 54 -- kit "three equal buttons height 54"
	local TOGGLE_ROW_H = 52 -- kit "Toggle row height 52"
	local SKIPREV_ROW_H = 86 -- label line + 8 rarity chips (no kit spec; two-line row)
	local FOOTER_H = 58 -- kit "Redeem Code... height 58"
	local GAP = T.pad.gapTight -- 8, kit "Body padding 16, gap 8"
	local ITEM_COUNT = 10 -- 3 section headers + 2 sliders + 1 segmented + 2 toggles + 1 rarity row + 1 footer
	local BODY_CONTENT_H = (SECTION_HEADER_H + SLIDER_ROW_H * 2) -- AUDIO
		+ (SECTION_HEADER_H + SEGMENT_ROW_H) -- GRAPHICS
		+ (SECTION_HEADER_H + TOGGLE_ROW_H * 2 + SKIPREV_ROW_H) -- GAMEPLAY
		+ FOOTER_H
		+ GAP * (ITEM_COUNT - 1)
	local BODY_H = T.pad.panel * 2 + BODY_CONTENT_H
	local GROUP_H = BODY_TOP + BODY_H

	----------------------------------------------------------- root
	local wrapper = Instance.new("Frame")
	wrapper.Name = "SettingsPanel"
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

	----------------------------------------------------------- header (common shell, README §3 -- kit gold shell, 1d/1e orange)
	local header = UI.surface(panelCol, UDim2.fromOffset(PANEL_W, HEADER_H), "gold", T.radius.panel, T.stroke.panel)
	header.Name = "Header"
	header.Position = UDim2.fromOffset(0, 0)
	header.ZIndex = 12
	-- 1d/1e sweep (2026-08-04): §3.3 gave Settings no special colour, but the
	-- cream restyle assigns each panel its own accent -- Settings is neutral
	-- orange #ffb02e -> #ff7d00. UI.surface has no orange kind, so the "gold"
	-- call above stays as the seed shell and its gradient is recoloured in
	-- place (same pattern DailyPanel's purple header uses).
	local headerGrad = header:FindFirstChildOfClass("UIGradient")
	if headerGrad then
		headerGrad.Color = ColorSequence.new(HEADER_TOP, HEADER_BOT)
	end
	UI.gloss(header, T.radius.panel)
	UI.hardShadow(header, T.shadowOffset.panel, T.radius.panel)

	local headerIcon = UI.artSlot(header, UDim2.fromOffset(62, 62), T.icons.settings)
	headerIcon.Name = "SectionIcon"
	headerIcon.AnchorPoint = Vector2.new(0, 0.5)
	headerIcon.Position = UDim2.new(0, 12, 0.5, 0)
	headerIcon.ZIndex = header.ZIndex + 1

	local headerTitle = UI.label(header, "Settings", "panelTitle", T.color.white)
	headerTitle.Name = "Title"
	headerTitle.AnchorPoint = Vector2.new(0, 0.5)
	headerTitle.Position = UDim2.new(0, 12 + 62 + 14, 0.5, 0)
	headerTitle.ZIndex = header.ZIndex + 2

	local closeBtn = UI.button(header, "X", "red", UDim2.fromOffset(T.size.closeButton.X, T.size.closeButton.Y), "buttonL")
	closeBtn.Name = "CloseButton"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -12, 0.5, 0)
	closeBtn.ZIndex = header.ZIndex + 2
	closeBtn.MouseButton1Click:Connect(function()
		ctx.closePanel()
	end)

	----------------------------------------------------------- body (common shell, README §3 -- 1d/1e sweep 2026-08-04: cream, was the kit dark panel)
	-- UI.panel bundled THREE things -- the dark "panel" surface, its
	-- hardShadow, and a baked-in 16px UIPadding -- so the cream swap has to
	-- recreate all three explicitly. The padding is EXACTLY T.pad.panel (16)
	-- per side, NOT DailyPanel's panelWide (18): BODY_H above is
	-- `T.pad.panel * 2 + BODY_CONTENT_H` and BODY_INNER_W is
	-- `PANEL_W - T.pad.panel * 2`, so a copied 18 would overflow the 10-item
	-- list stack by 4px and desync every row's width math.
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

	local bodyList = Instance.new("UIListLayout")
	bodyList.FillDirection = Enum.FillDirection.Vertical
	bodyList.SortOrder = Enum.SortOrder.LayoutOrder
	bodyList.Padding = UDim.new(0, GAP)
	bodyList.Parent = body

	----------------------------------------------------------- shared list-slot helper
	-- HardShadow-in-UIListLayout trap (see GoalsPanel/PassPanel reports):
	-- UI.hardShadow / UI.button both parent a shadow sibling to the VISUAL
	-- element's OWN parent, not to any wrapper -- if that parent is
	-- `body` itself (list-managed), the shadow becomes an extra, untracked
	-- list item and throws off the vertical stack. Every row below is built
	-- inside its own non-list-managed "slot" Frame (the actual list item),
	-- exactly like every other panel in this family does.
	local order = 0
	local function listSlot(h)
		order += 1
		local slot = Instance.new("Frame")
		slot.Name = "Slot" .. order
		slot.LayoutOrder = order
		slot.Size = UDim2.new(1, 0, 0, h)
		slot.BackgroundTransparency = 1
		slot.ZIndex = 14
		slot.Parent = body
		return slot
	end

	local function sectionHeader(text)
		local slot = listSlot(SECTION_HEADER_H)
		-- 1d/1e sweep (2026-08-04): was T.color.textAccent -- that gold was
		-- tuned for the old dark panel and nearly vanishes on cream even with
		-- the cardLabel ink stroke; #4a3416 is the mock's body-on-cream ink.
		local l = UI.label(slot, text, "cardLabel", BODY_INK)
		l.Name = "SectionHeader"
		l.Size = UDim2.new(1, 0, 1, 0)
		l.AutomaticSize = Enum.AutomaticSize.None
		l.TextXAlignment = Enum.TextXAlignment.Left
		-- kit wants 18/stroke3; cardLabel is 20/stroke3 (closest tokenised
		-- style, same class of kit-vs-Builders gap other panels document) --
		-- only TextSize is overridden, the stroke already matches exactly.
		l.TextSize = 18
		l.ZIndex = 15
	end

	----------------------------------------------------------- shared white-card recolor (1d/1e sweep 2026-08-04)
	-- The three row cards (slider/toggle/skip-reveal) flip from the kit's
	-- dark "row" surface to the mock's white card: flat white + soft #e5d3ac
	-- border. Recolor-in-place on the surface's OWN children -- the row
	-- gradient is destroyed (Builders' surface base BackgroundColor3 is
	-- already white underneath it) and the EXISTING UIStroke is recoloured;
	-- NEVER call UI.stroke a second time on the card (that would stack two
	-- strokes). Controls ON the cards -- tracks, knobs, switches, chips --
	-- keep their kit looks; dark chips read fine on cream (DailyPanel's dark
	-- timer pill is the shipped precedent).
	local function whiteCard(card: Frame)
		local grad = card:FindFirstChildOfClass("UIGradient")
		if grad then
			grad:Destroy()
		end
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = CARD_BORDER
		end
	end

	----------------------------------------------------------- FIX F4 shared drag-end watcher
	-- (2026-07-30 fix wave) track.InputEnded (used inside buildSliderRow below)
	-- only fires while the release happens over the track itself -- releasing
	-- off-track (drag the knob out past the row's edge, then let go) never
	-- fires it, leaving that row's local `dragging` stuck true and the slider
	-- visually "stuck" to the mouse/touch forever after. ONE shared
	-- UserInputService.InputEnded connection (preferred over a connection per
	-- row -- a global-service connection per row would leak across Build()
	-- calls with nothing to unwind) watches for the release everywhere; each
	-- row registers/unregisters its own end-drag closure in
	-- `activeDragEnders` for exactly as long as it's the one being dragged.
	-- Disconnected via the panel wrapper's Destroying -- `wrapper` is this
	-- module's one root Instance (per its own header comment, "this module
	-- never sets its own Parent"), created above.
	local activeDragEnders = {} -- row key -> function() ends that row's drag + fires the save
	local uisInputEndedConn = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		for _, endDrag in pairs(activeDragEnders) do
			endDrag()
		end
	end)
	wrapper.Destroying:Connect(function()
		uisInputEndedConn:Disconnect()
	end)

	----------------------------------------------------------- slider row (AUDIO)
	local function buildSliderRow(labelText, key, initialValue)
		local slot = listSlot(SLIDER_ROW_H)
		-- 1d/1e sweep (2026-08-04): white card via whiteCard; strokeW 3 (was
		-- T.stroke.control 4 -- the soft #e5d3ac border reads lighter than
		-- ink). The card hardShadow is gone -- cream-body cards are shadowless
		-- in the shipped Daily look, and `slot` isn't list-managed so the drop
		-- can't disturb the stack (the knob keeps ITS shadow; it's a control).
		local card = UI.surface(slot, UDim2.new(1, 0, 1, 0), "row", T.radius.inner, 3)
		card.Name = "SliderRow_" .. key
		card.ZIndex = 15
		whiteCard(card)

		local ROW_PAD_X = 14 -- kit gives no explicit slider-row padding; spacing-scale token, same class of ad hoc gap other panels document
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, ROW_PAD_X)
		pad.PaddingRight = UDim.new(0, ROW_PAD_X)
		pad.Parent = card

		local CONTENT_W = BODY_INNER_W - ROW_PAD_X * 2
		local LABEL_W, VALUE_W, INNER_GAP = 150, 56, T.pad.gap -- kit "label column 150" / "value column 56"
		local TRACK_W = CONTENT_W - LABEL_W - VALUE_W - INNER_GAP * 2

		local label = UI.label(card, labelText, "cardLabel", BODY_INK) -- 1d/1e sweep (2026-08-04): was white -- white-on-white after the card flip
		label.Name = "Label"
		label.AnchorPoint = Vector2.new(0, 0.5)
		label.Position = UDim2.new(0, 0, 0.5, 0)
		label.Size = UDim2.new(0, LABEL_W, 0, 24)
		label.AutomaticSize = Enum.AutomaticSize.None
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.ZIndex = 16

		local track, fill = UI.track(card, UDim2.new(0, TRACK_W, 0, 26), "green", T.radius.pill)
		track.Name = "Track"
		track.AnchorPoint = Vector2.new(0, 0.5)
		track.Position = UDim2.new(0, LABEL_W + INNER_GAP, 0.5, 0)
		track.ZIndex = 16

		-- Knob is parented to `card`, NOT `track` -- UI.track sets
		-- ClipsDescendants=true on the track (for the fill's rounded-corner
		-- mask), so a knob living inside it would get visually clipped in
		-- half at both 0% and 100% (it's meant to overlap the track's rounded
		-- ends, per the capture). Positioned in card-local offset space
		-- instead, computed from the SAME track geometry.
		local knob = Instance.new("Frame")
		knob.Name = "Knob"
		knob.AnchorPoint = Vector2.new(0.5, 0.5)
		knob.Size = UDim2.fromOffset(34, 34) -- kit "knob 34x34 circle"
		knob.BackgroundColor3 = T.color.white
		knob.BorderSizePixel = 0
		knob.ZIndex = 17
		knob.Parent = card
		UI.corner(knob, 17)
		UI.gradient(knob, T.gradient.knob) -- kit "#FFF0A8->#FFC531"
		UI.stroke(knob, T.stroke.control)
		UI.hardShadow(knob, 3, 17) -- kit "hard shadow 0 3" -- knob's parent (`card`) isn't list-managed, so no wrapper trap here

		local valueLabel = UI.label(card, "0%", "cardLabel", BODY_INK) -- 1d/1e sweep (2026-08-04): on the white card now
		valueLabel.Name = "Value"
		valueLabel.AnchorPoint = Vector2.new(1, 0.5)
		valueLabel.Position = UDim2.new(1, 0, 0.5, 0)
		valueLabel.Size = UDim2.new(0, VALUE_W, 0, 24)
		valueLabel.AutomaticSize = Enum.AutomaticSize.None
		valueLabel.TextXAlignment = Enum.TextXAlignment.Right
		valueLabel.ZIndex = 16

		local dragging = false
		local pct = math.clamp(initialValue or 0, 0, 1)

		local function render()
			UI.setFill(fill, pct, false)
			knob.Position = UDim2.new(0, LABEL_W + INNER_GAP + pct * TRACK_W, 0.5, 0)
			valueLabel.Text = tostring(math.floor(pct * 100 + 0.5)) .. "%"
		end
		render()

		local function updateFromInput(input)
			local size = track.AbsoluteSize.X
			if size <= 0 then
				return
			end
			local rel = (input.Position.X - track.AbsolutePosition.X) / size
			pct = math.clamp(rel, 0, 1)
			render()
			SoundKit.SetCategoryVolume(key, pct) -- live preview during drag/click
		end

		-- Click-to-set + drag, per kit §3.3 ("Click-to-set on the track; drag =
		-- same math on InputChanged"): InputBegan both starts the drag AND
		-- previews the click position; InputEnded fires the save even with
		-- zero movement (a plain click). endDrag is shared between the on-track
		-- InputEnded below and the module-level shared UIS.InputEnded watcher
		-- (FIX F4) that catches an off-track release this row's own track would
		-- otherwise never see.
		local function endDrag()
			if not dragging then
				return
			end
			dragging = false
			activeDragEnders[key] = nil
			fireSave({ [key] = pct })
		end

		track.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				activeDragEnders[key] = endDrag
				updateFromInput(input)
			end
		end)
		track.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				updateFromInput(input)
			end
		end)
		track.InputEnded:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
				endDrag()
			end
		end)

		return {
			setValue = function(v)
				if dragging then
					return -- don't fight a live drag with a server echo
				end
				pct = math.clamp(v or 0, 0, 1)
				render()
			end,
		}
	end

	----------------------------------------------------------- segmented quality row (GRAPHICS)
	local function buildSegmentedRow()
		local slot = listSlot(SEGMENT_ROW_H)
		local SEG_GAP = T.pad.gapTight -- 8; kit gives no explicit segment gap
		local segW = (BODY_INNER_W - SEG_GAP * 2) / 3

		local buttons, rings, glows = {}, {}, {}
		for i, q in ipairs(QUALITY_OPTIONS) do
			-- kit-token gap (same class Task 6/7 already logged, deferred): UI.button
			-- hardcodes T.radius.control (16), kit wants 14 here -- not fixed, per
			-- the already-deferred "Builders radius-param follow-up".
			local btn = UI.button(slot, q, "tab", UDim2.fromOffset(segW, SEGMENT_ROW_H), "buttonM")
			btn.Name = "Quality" .. q
			btn.Position = UDim2.fromOffset((i - 1) * (segW + SEG_GAP), 0)
			btn.ZIndex = 15
			buttons[q] = btn

			-- glow (kit "+ 12px glow"): one soft rounded-rect halo, 12px outset
			-- each side, behind the button.
			local glow = Instance.new("Frame")
			glow.Name = "Glow"
			glow.AnchorPoint = Vector2.new(0.5, 0.5)
			glow.Position = UDim2.fromScale(0.5, 0.5)
			glow.Size = UDim2.new(1, 24, 1, 24)
			glow.BackgroundColor3 = T.color.activeGlow
			glow.BackgroundTransparency = 0.72
			glow.BorderSizePixel = 0
			glow.Visible = false
			glow.ZIndex = btn.ZIndex - 1
			glow.Parent = btn
			UI.corner(glow, T.radius.control + 12)
			glows[q] = glow

			-- active ring: kit "4 px #FFD84D ring inset -4 (radius 16)" -- same
			-- static-selection convention GoalsPanel's own tab ring uses.
			local ring = Instance.new("Frame")
			ring.Name = "ActiveRing"
			ring.Size = UDim2.new(1, 8, 1, 8)
			ring.Position = UDim2.fromOffset(-4, -4)
			ring.BackgroundTransparency = 1
			ring.Visible = false
			ring.ZIndex = btn.ZIndex + 3
			ring.Parent = btn
			UI.corner(ring, 16)
			local ringStroke = Instance.new("UIStroke")
			ringStroke.Thickness = 4
			ringStroke.Color = T.color.activeRing
			ringStroke.Parent = ring
			rings[q] = ring
		end

		local current = "Medium"
		local function render()
			for q in pairs(buttons) do
				rings[q].Visible = (q == current)
				glows[q].Visible = (q == current)
			end
		end
		render()

		for q, btn in pairs(buttons) do
			btn.MouseButton1Click:Connect(function()
				if current == q then
					return
				end
				current = q
				render()
				applyQuality(current) -- immediate client-local preview
				fireSave({ quality = current })
			end)
		end

		return {
			setValue = function(q)
				if QUALITY_SET[q] and q ~= current then
					current = q
					render()
				end
			end,
		}
	end

	----------------------------------------------------------- toggle row (GAMEPLAY)
	local function buildToggleRow(labelText, initialOn, onToggle)
		local slot = listSlot(TOGGLE_ROW_H)
		local card = UI.surface(slot, UDim2.new(1, 0, 1, 0), "row", T.radius.inner, 3)
		card.Name = "ToggleRow"
		card.ZIndex = 15
		whiteCard(card) -- 1d/1e sweep (2026-08-04): white card, no hardShadow -- see buildSliderRow's note; the switch keeps its full kit look

		local ROW_PAD_X = 14
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, ROW_PAD_X)
		pad.PaddingRight = UDim.new(0, ROW_PAD_X)
		pad.Parent = card

		local SWITCH_W, SWITCH_H = 86, 38 -- kit "switch 86x38"

		local label = UI.label(card, labelText, "cardLabel", BODY_INK) -- 1d/1e sweep (2026-08-04): was white -- white-on-white after the card flip
		label.Name = "Label"
		label.AnchorPoint = Vector2.new(0, 0.5)
		label.Position = UDim2.new(0, 0, 0.5, 0)
		label.Size = UDim2.new(1, -(SWITCH_W + T.pad.gap), 0, 24)
		label.AutomaticSize = Enum.AutomaticSize.None
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.ZIndex = 16

		local switch = Instance.new("TextButton")
		switch.Name = "Switch"
		switch.Text = ""
		switch.AutoButtonColor = false
		switch.AnchorPoint = Vector2.new(1, 0.5)
		switch.Position = UDim2.new(1, 0, 0.5, 0)
		switch.Size = UDim2.fromOffset(SWITCH_W, SWITCH_H)
		switch.BackgroundColor3 = T.color.white
		switch.BorderSizePixel = 0
		switch.ZIndex = 16
		switch.Parent = card
		UI.corner(switch, T.radius.pill)
		local switchGradient = Instance.new("UIGradient")
		switchGradient.Rotation = 90
		switchGradient.Parent = switch
		UI.stroke(switch, T.stroke.control)

		-- OFF inset shadow (kit "OFF... with inset shadow") -- same trick
		-- UI.track uses for its own inset shadow; only shown in the OFF state.
		local inset = Instance.new("Frame")
		inset.Name = "InsetShadow"
		inset.Size = UDim2.new(1, 0, 0, 4)
		inset.BackgroundColor3 = Color3.new(0, 0, 0)
		inset.BackgroundTransparency = 0.55
		inset.BorderSizePixel = 0
		inset.ZIndex = switch.ZIndex + 1
		inset.Parent = switch
		UI.corner(inset, T.radius.pill)

		-- "ON"/"OFF" chip label. FontFace, never the legacy .Font property with
		-- a Font-struct value (T.font.* are Font structs, not Enum.Font -- the
		-- exact crash class Task 8/9 logged and fixed elsewhere in this family).
		local switchLabel = Instance.new("TextLabel")
		switchLabel.Name = "StateLabel"
		switchLabel.BackgroundTransparency = 1
		switchLabel.Size = UDim2.new(0, 40, 1, 0)
		switchLabel.FontFace = T.font.display
		switchLabel.TextSize = T.text.chip[1]
		switchLabel.RichText = false
		switchLabel.TextYAlignment = Enum.TextYAlignment.Center
		switchLabel.ZIndex = switch.ZIndex + 2
		switchLabel.Parent = switch
		local switchLabelStroke = Instance.new("UIStroke")
		switchLabelStroke.Thickness = T.text.chip[2]
		switchLabelStroke.Color = T.color.outline
		switchLabelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		switchLabelStroke.LineJoinMode = Enum.LineJoinMode.Round
		switchLabelStroke.Parent = switchLabel

		local knob = Instance.new("Frame")
		knob.Name = "Knob"
		knob.AnchorPoint = Vector2.new(0.5, 0.5)
		knob.Size = UDim2.fromOffset(36, 36) -- kit "36 px white knob" (ON); OFF reuses the same size, colour only differs
		knob.BackgroundColor3 = T.color.white
		knob.BorderSizePixel = 0
		knob.ZIndex = switch.ZIndex + 2
		knob.Parent = switch
		UI.corner(knob, 18)
		local knobGradient = Instance.new("UIGradient")
		knobGradient.Rotation = 90
		knobGradient.Parent = knob
		UI.stroke(knob, T.stroke.hairline)

		-- kit-token gap (same class GoalsPanel's own header-plate colours
		-- document): no T.gradient entry matches these two OFF-state pairs.
		local OFF_TOP, OFF_BOT = T.hex("#5A6748"), T.hex("#3A452C")
		local KNOB_OFF_TOP, KNOB_OFF_BOT = T.hex("#C9CCC2"), T.hex("#9AA28E")

		local on = initialOn == true
		local function render()
			inset.Visible = not on
			if on then
				switchGradient.Color = T.gradient.green
				knobGradient.Color = ColorSequence.new(T.color.white)
				knob.AnchorPoint = Vector2.new(1, 0.5)
				knob.Position = UDim2.new(1, -1, 0.5, 0)
				switchLabel.Text = "ON"
				switchLabel.TextColor3 = T.color.white
				switchLabel.AnchorPoint = Vector2.new(0, 0.5)
				switchLabel.Position = UDim2.new(0, 11, 0.5, 0)
				switchLabel.TextXAlignment = Enum.TextXAlignment.Left
			else
				switchGradient.Color = ColorSequence.new(OFF_TOP, OFF_BOT)
				knobGradient.Color = ColorSequence.new(KNOB_OFF_TOP, KNOB_OFF_BOT)
				knob.AnchorPoint = Vector2.new(0, 0.5)
				knob.Position = UDim2.new(0, 1, 0.5, 0)
				switchLabel.Text = "OFF"
				switchLabel.TextColor3 = T.color.textMuted
				switchLabel.AnchorPoint = Vector2.new(1, 0.5)
				switchLabel.Position = UDim2.new(1, -11, 0.5, 0)
				switchLabel.TextXAlignment = Enum.TextXAlignment.Right
			end
		end
		render()

		switch.MouseButton1Click:Connect(function()
			on = not on
			render()
			if onToggle then
				onToggle(on)
			end
		end)

		return {
			setValue = function(v)
				on = v == true
				render()
			end,
		}
	end

	----------------------------------------------------------- skip-catch-animation row (GAMEPLAY): 8 per-rarity chips
	-- A filled chip = that rarity's Pull ceremony is skipped (the fast text
	-- card shows instead). Chips wear their tier colour when ON and the
	-- toggle family's OFF greens when not, so the row reads with the same
	-- vocabulary as the switches above it.
	local function buildSkipRevealRow()
		local slot = listSlot(SKIPREV_ROW_H)
		local card = UI.surface(slot, UDim2.new(1, 0, 1, 0), "row", T.radius.inner, 3)
		card.Name = "SkipRevealRow"
		card.ZIndex = 15
		whiteCard(card) -- 1d/1e sweep (2026-08-04): white card, no hardShadow -- see buildSliderRow's note; all 8 chips keep their tier/OFF looks

		local ROW_PAD_X = 14
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, ROW_PAD_X)
		pad.PaddingRight = UDim.new(0, ROW_PAD_X)
		pad.Parent = card

		local label = UI.label(card, "Skip Catch Animation", "cardLabel", BODY_INK) -- 1d/1e sweep (2026-08-04): was white -- white-on-white after the card flip
		label.Name = "Label"
		label.Position = UDim2.new(0, 0, 0, 8)
		label.Size = UDim2.new(1, 0, 0, 22)
		label.AutomaticSize = Enum.AutomaticSize.None
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.ZIndex = 16

		local chipRow = Instance.new("Frame")
		chipRow.Name = "Chips"
		chipRow.BackgroundTransparency = 1
		chipRow.Position = UDim2.new(0, 0, 0, 36)
		chipRow.Size = UDim2.new(1, 0, 0, 40)
		chipRow.ZIndex = 16
		chipRow.Parent = card
		local chipList = Instance.new("UIListLayout")
		chipList.FillDirection = Enum.FillDirection.Horizontal
		chipList.SortOrder = Enum.SortOrder.LayoutOrder
		chipList.Padding = UDim.new(0, 6)
		chipList.Parent = chipRow

		local CHIP_W = math.floor((BODY_INNER_W - ROW_PAD_X * 2 - 6 * (#RarityConfig - 1)) / #RarityConfig)
		local SHORT = { Common = "COM", Uncommon = "UNC", Rare = "RARE", Epic = "EPIC",
			Legendary = "LEG", Mythic = "MYTH", Secret = "SEC", God = "GOD" }
		local OFF_TOP, OFF_BOT = T.hex("#5A6748"), T.hex("#3A452C")

		-- Trailing save: SettingsService silently drops saves within 0.5s of the
		-- last one, and chip-picking is exactly the rapid-click case -- so the
		-- attribute applies instantly per click, and ONE save (the full table)
		-- fires 0.6s after the last click. Token pattern, newest wins.
		local saveToken = 0
		local function queueSave()
			saveToken += 1
			local my = saveToken
			task.delay(0.6, function()
				if my ~= saveToken then return end
				local copy = {}
				for _, tier in ipairs(RarityConfig) do copy[tier.Name] = applied.skipReveal[tier.Name] == true end
				fireSave({ skipReveal = copy })
			end)
		end

		local chips = {}
		local function paintChip(tierName)
			local c = chips[tierName]
			if not c then return end
			local on = applied.skipReveal[tierName] == true
			if on then
				c.gradient.Color = ColorSequence.new(c.color, c.color:Lerp(Color3.new(0, 0, 0), 0.35))
				c.label.TextColor3 = T.color.white
			else
				c.gradient.Color = ColorSequence.new(OFF_TOP, OFF_BOT)
				c.label.TextColor3 = T.color.textMuted
			end
			c.inset.Visible = not on
		end

		for i, tier in ipairs(RarityConfig) do
			local chip = Instance.new("TextButton")
			chip.Name = tier.Name .. "Chip"
			chip.Text = ""
			chip.AutoButtonColor = false
			chip.LayoutOrder = i
			chip.Size = UDim2.fromOffset(CHIP_W, 34)
			chip.BackgroundColor3 = T.color.white
			chip.BorderSizePixel = 0
			chip.ZIndex = 17
			chip.Parent = chipRow
			UI.corner(chip, T.radius.control)
			local grad = Instance.new("UIGradient")
			grad.Rotation = 90
			grad.Parent = chip
			UI.stroke(chip, T.stroke.hairline)

			local inset = Instance.new("Frame")
			inset.Name = "InsetShadow"
			inset.Size = UDim2.new(1, 0, 0, 3)
			inset.BackgroundColor3 = Color3.new(0, 0, 0)
			inset.BackgroundTransparency = 0.55
			inset.BorderSizePixel = 0
			inset.ZIndex = 18
			inset.Parent = chip
			UI.corner(inset, T.radius.control)

			local chipLabel = Instance.new("TextLabel")
			chipLabel.Name = "Word"
			chipLabel.BackgroundTransparency = 1
			chipLabel.Size = UDim2.new(1, -6, 1, 0)
			chipLabel.Position = UDim2.new(0, 3, 0, 0)
			chipLabel.FontFace = T.font.display
			chipLabel.TextScaled = true
			chipLabel.RichText = false
			chipLabel.Text = SHORT[tier.Name] or string.upper(tier.Name)
			chipLabel.ZIndex = 19
			chipLabel.Parent = chip
			local cap = Instance.new("UITextSizeConstraint")
			cap.MaxTextSize = T.text.chip[1]
			cap.Parent = chipLabel
			local ink = Instance.new("UIStroke")
			ink.Thickness = T.text.chip[2]
			ink.Color = T.color.outline
			ink.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			ink.LineJoinMode = Enum.LineJoinMode.Round
			ink.Parent = chipLabel

			chips[tier.Name] = { gradient = grad, label = chipLabel, inset = inset, color = tier.Color }
			paintChip(tier.Name)

			chip.MouseButton1Click:Connect(function()
				applied.skipReveal[tier.Name] = not (applied.skipReveal[tier.Name] == true)
				paintChip(tier.Name)
				applySkipReveal(applied.skipReveal)
				queueSave()
			end)
		end

		return {
			setValue = function()
				for _, tier in ipairs(RarityConfig) do paintChip(tier.Name) end
			end,
		}
	end

	----------------------------------------------------------- footer: Redeem Code (Reset Data intentionally absent -- see module header)
	local function buildFooter()
		local slot = listSlot(FOOTER_H)
		local btn = UI.button(slot, "Redeem Code", "blue", UDim2.new(1, 0, 1, 0), "buttonM")
		btn.Name = "RedeemCodeButton"
		btn.ZIndex = 15

		-- Inline input row (kit: "opening an inline TextBox row"), hidden until
		-- the button is pressed. Reuses this SAME slot rather than growing the
		-- panel -- the button hides while the row is open, so the footer never
		-- changes height and nothing above it has to relayout.
		local inputRow = Instance.new("Frame")
		inputRow.Name = "RedeemInputRow"
		inputRow.Size = UDim2.new(1, 0, 1, 0)
		inputRow.BackgroundTransparency = 1
		inputRow.Visible = false
		inputRow.ZIndex = 15
		inputRow.Parent = slot

		local GO_W = 84
		local BOX_W = BODY_INNER_W - GO_W - T.pad.gapTight

		local box = Instance.new("TextBox")
		box.Name = "CodeBox"
		box.Size = UDim2.new(0, BOX_W, 1, 0)
		box.BackgroundColor3 = T.color.white
		box.BorderSizePixel = 0
		box.Text = ""
		box.PlaceholderText = "Enter code\u{2026}"
		box.PlaceholderColor3 = T.color.textMuted
		box.TextColor3 = T.color.white
		box.FontFace = T.font.ui -- FontFace, not .Font (Font-struct crash class -- see Switch label comment above)
		box.TextSize = 16
		box.ClearTextOnFocus = false
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.ZIndex = 15
		box.Parent = inputRow
		UI.corner(box, T.radius.inner)
		UI.gradient(box, T.gradient.track)
		UI.stroke(box, T.stroke.control)
		local boxPad = Instance.new("UIPadding")
		boxPad.PaddingLeft = UDim.new(0, 12)
		boxPad.PaddingRight = UDim.new(0, 12)
		boxPad.Parent = box

		local goBtn = UI.button(inputRow, "GO", "green", UDim2.fromOffset(GO_W, FOOTER_H), "buttonM")
		goBtn.Name = "GoButton"
		goBtn.Position = UDim2.fromOffset(BOX_W + T.pad.gapTight, 0)
		goBtn.ZIndex = 15

		-- 1d/1e sweep (2026-08-04): msg floats on the transparent inputRow,
		-- i.e. directly on the cream body -- textMuted was a dark-panel pick.
		local msg = UI.label(inputRow, "", "meta", BODY_INK)
		msg.Name = "Message"
		msg.AnchorPoint = Vector2.new(0, 1)
		msg.Position = UDim2.new(0, 2, 0, -4)
		msg.Size = UDim2.new(1, -4, 0, 16)
		msg.AutomaticSize = Enum.AutomaticSize.None
		msg.TextXAlignment = Enum.TextXAlignment.Left
		msg.ZIndex = 16

		btn.MouseButton1Click:Connect(function()
			btn.Visible = false
			inputRow.Visible = true
		end)

		-- REAL, existing remote -- see module header REDEEM CODE DEVIATION.
		-- Nothing new was created server-side; this fires the SAME RemoteEvent
		-- the legacy DailyRewardClient's own REDEEM box already uses.
		local function submit()
			local code = box.Text
			if typeof(code) ~= "string" or #code:gsub("%s+", "") == 0 then
				return
			end
			remotes.RedeemCode:FireServer(code)
		end
		goBtn.MouseButton1Click:Connect(submit)
		box.FocusLost:Connect(function(enterPressed)
			if enterPressed then
				submit()
			end
		end)

		remotes.RedeemCode.OnClientEvent:Connect(function(r)
			if typeof(r) ~= "table" or typeof(r.Message) ~= "string" then
				return
			end
			msg.Text = r.Message
			-- 1d/1e sweep (2026-08-04): both originals were light-on-dark
			-- picks (claimRing #7CE04A / salmon #FF8A7A) that wash out on
			-- cream; colours only, the Success/Message handling is untouched.
			msg.TextColor3 = r.Success == true and MSG_GREEN or MSG_RED
			if r.Success == true then
				box.Text = ""
			end
		end)
	end

	----------------------------------------------------------- assemble
	sectionHeader("AUDIO")
	local musicCtl = buildSliderRow("Music", "music", applied.music)
	local sfxCtl = buildSliderRow("Sound FX", "sfx", applied.sfx)

	sectionHeader("GRAPHICS")
	local qualityCtl = buildSegmentedRow()
	qualityCtl.setValue(applied.quality)

	sectionHeader("GAMEPLAY")
	local fastSpinCtl = buildToggleRow("Fast Spin", applied.fastSpin, function(on)
		applied.fastSpin = on
		applyFastSpin(on)
		fireSave({ fastSpin = on })
	end)
	local hideBannersCtl = buildToggleRow("Hide My Catch Banners", applied.hideOwnBanners, function(on)
		applied.hideOwnBanners = on
		applyHideOwnBanners(on)
		fireSave({ hideOwnBanners = on })
	end)
	local skipRevealCtl = buildSkipRevealRow()

	buildFooter()

	----------------------------------------------------------- kit README §5 client state shape -- kept in sync for parity with every other panel's own ctx.state.<id> writes, even though nothing else currently reads it
	local function syncState()
		if ctx.state and ctx.state.settings then
			ctx.state.settings.music = applied.music
			ctx.state.settings.sfx = applied.sfx
			ctx.state.settings.quality = applied.quality
			ctx.state.settings.toggles = ctx.state.settings.toggles or {}
			ctx.state.settings.toggles.fastSpin = applied.fastSpin
			ctx.state.settings.toggles.hideOwnBanners = applied.hideOwnBanners
			ctx.state.settings.toggles.skipReveal = applied.skipReveal
		end
	end
	syncState()

	----------------------------------------------------------- re-sync every control if a settings payload lands again after Build (e.g. loaded late, or a re-push)
	onAppliedChanged = function()
		musicCtl.setValue(applied.music)
		sfxCtl.setValue(applied.sfx)
		qualityCtl.setValue(applied.quality)
		fastSpinCtl.setValue(applied.fastSpin)
		hideBannersCtl.setValue(applied.hideOwnBanners)
		skipRevealCtl.setValue()
		syncState()
	end

	----------------------------------------------------------- backdrop blur (1d/1e sweep 2026-08-04: dim + blur behind the panel)
	-- Same per-panel BlurEffect recipe as DailyPanel: the shell owns the dim
	-- scrim, the blur is per-panel, created/destroyed on Visible. The NAME is
	-- unique per panel -- setBlur create/destroys by name in Lighting, so a
	-- shared name would let one panel's close destroy another's live blur.
	-- Size is SET, never tweened (BlurEffect.Size is not on the proven tween
	-- whitelist here). Lighting is already imported at module top for
	-- applyQuality; this block only ever touches its OWN named BlurEffect, so
	-- it cannot interact with the Bloom/SunRays lookups (different classes).
	local BLUR_NAME = "SettingsPanelBlur"
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

	-- Settings has no per-open refresh, countdown or motion to drive, so this
	-- watcher is minimal AND NEW (the panel previously had no Visible watcher
	-- at all) -- view-only, additive; the closeBtn/Destroying wiring above is
	-- untouched.
	wrapper:GetPropertyChangedSignal("Visible"):Connect(function()
		setBlur(wrapper.Visible)
	end)

	-- Belt-and-braces (same review catch DailyPanel carries): any path that
	-- hides the HOST while this wrapper stays Visible (legacy single-open
	-- force-closes, future shell changes) must still kill the global
	-- BlurEffect -- it post-processes the whole screen regardless of GUI
	-- visibility. Restore it when the host returns and we're still the
	-- visible panel.
	ctx.host:GetPropertyChangedSignal("Visible"):Connect(function()
		if not ctx.host.Visible then
			setBlur(false)
		elseif wrapper.Visible then
			setBlur(true)
		end
	end)

	return wrapper
end

return SettingsPanel
