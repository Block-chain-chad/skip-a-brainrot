--[[ ==========================================================================
GameHUDClient -- the new HUD shell: 1350x775 canvas, currency cluster, left
nav rail (v2, moved 2026-07-30 per user decision), panel host + registration
protocol, legacy retirements, ESC.
---------------------------------------------------------------------------
This is the integration point five later tasks build against. The contract:

	ctx = {
		Tokens, Builders,        -- ReplicatedStorage.Modules.UIKit, straight through
		remotes,                 -- ReplicatedStorage.Remotes
		host,                    -- Frame every panel module parents its own panel into
		openPanel(id),           -- show/build the panel registered under `id`
		closePanel(),            -- close whatever panel is open
		setBadge(id, n),         -- notification badge on the matching rail item
		pillAnchor(which),       -- "coin"|"gem" -> Vector2 screen position of that
		                         -- pill (Task 7 uses this for reward-fly targets)
		state,                   -- shared client state table, kit README section 5
	}

Panel registration: every ModuleScript dropped into the sibling GameHUDPanels
folder is required at startup and must return { Id = "bag", Build = function(ctx)
-> Frame }. A module with no Build/Id, or a require() that errors, is skipped
silently -- panels arrive in later tasks, GameHUDPanels is empty right now.

All geometry below is offset px against the 1350x775 design canvas (kit
README section 1), scaled uniformly by ONE UIScale/fit() pair -- every other
HUD element hangs off the same `root` Frame so nothing needs its own resize
listener.
========================================================================== ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService") -- Bug B fix: GetGuiInset() compensation, see Canvas below
local TextService = game:GetService("TextService") -- Bug A fix: measures pill text width, see buildPill below

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local modules = ReplicatedStorage:WaitForChild("Modules")

local UIKit = modules:WaitForChild("UIKit")
local T = require(UIKit:WaitForChild("Tokens"))
local UI = require(UIKit:WaitForChild("Builders"))
local SideRail = require(modules:WaitForChild("SideRail"))
-- The six rail buttons are raw Instance.new TextButtons: they bypass every
-- styled constructor, so they were silent. Same SfxWired attribute key the
-- constructors use, so a control that is BOTH built here and styled elsewhere
-- can still only ever get one connection -- no double clicks.
local SoundKit = require(modules:WaitForChild("SoundKit"))
-- Fetch the whole sound set once, at join. PreloadAsync yields inside SoundKit's
-- own task.spawn, so this never blocks the HUD build.
task.spawn(function() pcall(SoundKit.preload) end)
local CLICK_VOLUME = 0.12
local function wireClick(btn, soundName)
	if btn:GetAttribute("SfxWired") then return end
	btn:SetAttribute("SfxWired", true)
	btn.MouseButton1Click:Connect(function()
		pcall(SoundKit.play, soundName or "uiClick", nil, { volume = CLICK_VOLUME })
	end)
end
-- The kit's nav icons, redrawn from GUI primitives (see UIKit.IconArt) for as
-- long as Tokens.icons is empty. pcall'd on purpose: a missing or broken
-- IconArt must not take the whole HUD down with it -- the rail just falls back
-- to its emoji stand-in.
local okIconArt, IconArt = pcall(function()
	return require(UIKit:WaitForChild("IconArt", 5))
end)
if not okIconArt then IconArt = nil end

---------------------------------------------------------------- canvas
local gui = Instance.new("ScreenGui")
gui.Name = "GameHUD"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 7
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Canvas"
root.AnchorPoint = Vector2.new(0.5, 0.5)
-- HUD RESCUE (2026-07-31) -- this canvas is CENTRED, with no inset
-- compensation, and that is deliberate. The compensation that used to live
-- here (`0.5, GuiInset().Y`) rested on a misread: AbsolutePosition inside an
-- IgnoreGuiInset=true ScreenGui is reported MINUS the topbar inset, so the
-- probe that saw Canvas.AbsolutePosition.Y = -57.3 was looking at a canvas
-- that was already perfectly centred. Adding the inset back pushed the whole
-- canvas 58px DOWN, which is what clipped the Settings rail item off the
-- bottom of the screen. Re-measured live before this fix: viewport 1891x772,
-- gui.AbsoluteSize 1891x772 (so the ScreenGui really is the full window),
-- GuiInset (0,58), Canvas.AbsolutePosition (273,0) -- reported 0 while its
-- true screen y was 58, exactly the -inset skew.
root.Size = UDim2.fromOffset(T.size.canvas.X, T.size.canvas.Y)
root.Position = UDim2.fromScale(0.5, 0.5)
root.BackgroundTransparency = 1
root.ZIndex = T.zindex.panel + 1 -- above Scrim (25), below Chrome (30)
root.Parent = gui

---------------------------------------------------------------- chrome layer
-- HUD RESCUE (2026-07-31): the user's complaint -- nav rail and currency
-- pills floating ~270px inboard instead of hugging the left edge of the
-- screen -- was the letterboxed canvas behaving exactly as designed. At the
-- measured 1891x772 viewport the 1350x775 canvas scales by 0.996 and renders
-- 1345 wide, so it CENTRES with its left edge at screen x=273. Anything
-- anchored to the canvas edge inherits that 273px offset.
--
-- So the HUD splits in two: modals stay on the centred canvas (a modal
-- SHOULD be centred), while HUD chrome -- currency cluster and nav rail --
-- moves onto this second layer, which is not letterboxed and spans the real
-- screen. Its UIScale runs at the identical factor, so everything on it
-- keeps the size it had; only the anchor changes.
--
-- Size is assigned in offset px as viewport/scale, so once this layer's own
-- UIScale multiplies it back up it covers exactly the safe area: full width,
-- top of screen + topbar inset down to the bottom. That keeps every child's
-- offsets in kit design px. The inset offset here is a real one (unlike the
-- canvas's above): these children hug the top-left corner, which is where
-- Roblox's own topbar buttons live.
local chrome = Instance.new("Frame")
chrome.Name = "Chrome"
chrome.AnchorPoint = Vector2.new(0, 0)
chrome.BackgroundTransparency = 1
chrome.ZIndex = T.zindex.rail -- 30: above the canvas, so the rail stays visible over open panels
chrome.Parent = gui

-- Uniform fit-to-viewport scale (kit README section 1). Exactly ONE
-- connection drives this for the whole HUD -- both layers and everything
-- under them -- so nothing else needs its own resize listener.
local canvasScale = Instance.new("UIScale")
canvasScale.Parent = root

local chromeScale = Instance.new("UIScale")
chromeScale.Parent = chrome

-- Assigned once the rail exists, further down: the rail centres itself
-- within the chrome layer's height, and that height is viewport-dependent,
-- so it has to be recomputed on every fit().
local layoutRail = nil

local function fit()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local vp = camera.ViewportSize
	local scale = math.min(vp.X / T.size.canvas.X, vp.Y / T.size.canvas.Y)
	canvasScale.Scale = scale
	chromeScale.Scale = scale

	-- Re-read every pass rather than once at construction: GetGuiInset() can
	-- still return 0 at the instant this script first runs, before Roblox has
	-- populated the topbar inset.
	local inset = GuiService:GetGuiInset().Y
	chrome.Position = UDim2.fromOffset(0, inset)
	chrome.Size = UDim2.fromOffset(vp.X / scale, math.max(vp.Y - inset, 1) / scale)

	if layoutRail then layoutRail() end
end
fit()
do
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
end
-- Covers the case where GetGuiInset() raced boot AND ViewportSize never
-- changes again this session (a fixed window), so nothing else re-runs fit().
task.delay(1, fit)

---------------------------------------------------------------- scrim
-- HUD RESCUE (2026-07-31): a sibling of the canvas, not a child of it. As a
-- child it only ever darkened the canvas, leaving the letterbox bars (273px
-- down each side at the measured 1891x772) bright behind an open modal.
local scrim = Instance.new("Frame")
scrim.Name = "Scrim"
scrim.Size = UDim2.fromScale(1, 1)
scrim.BackgroundColor3 = T.scrim
scrim.BackgroundTransparency = T.scrimAlpha
scrim.BorderSizePixel = 0
scrim.Visible = false
scrim.ZIndex = T.zindex.panel -- 25: below Canvas (26), so panels sit above it
scrim.Parent = gui

---------------------------------------------------------------- panel host
-- Panel Build(ctx) functions parent their own (e.g. 960-wide) panel Frame
-- into this host and centre themselves within it.
--
-- HUD RESCUE (2026-07-31): the host now fills the whole canvas, so those
-- panels land dead centre. It used to carry T.size.panelRightGutter (132) of
-- left padding to reserve the nav rail, which pushed every modal 54px right
-- of centre -- and the rail does not live on this canvas any more (see the
-- chrome layer). No collision either way: a 960-wide panel on the 1350 design
-- canvas leaves 195px gutters, clear of the rail's 116px column even when the
-- canvas spans the full screen width.
local host = Instance.new("Frame")
host.Name = "PanelHost"
host.Size = UDim2.fromScale(1, 1)
host.BackgroundTransparency = 1
host.Visible = false
host.ZIndex = T.zindex.panel + 1 -- 26: directly above the scrim, per brief Step 2
host.Parent = root

---------------------------------------------------------------- shared state
-- Forward-declared so the currency cluster / rail sections below can close
-- over them, and so `ctx` exists (as a table reference) before openPanel is
-- ever CALLED, even though its fields are filled in further down.
local ctx = {}

local state = {
	screen = "none", -- "none" | "pass" | "backpack" | "settings" | "daily" | "index" | "goals"
	pass = { level = 0, xp = 0, xpNeed = 0, passOwned = false, claimedFree = {}, claimedPass = {} },
	backpack = { tab = "Brainrots", selectedUid = nil, items = {} },
	settings = { music = 1, sfx = 1, quality = "Medium", toggles = {} },
	daily = { streakDay = 1, claimedToday = false },
	goals = { tab = "Daily", quests = {} },
	index = { filter = "All", entries = {} },
}

local panelModules = {}   -- id -> { Id, Build }
local panelInstances = {} -- id -> built Frame
local currentPanelId = nil
local railItems = {}      -- id -> { frame, glow, scale, claim }
local railBadges = {}     -- id -> badge Frame

-- FIX F3 (2026-07-30 fix wave): generation counter guarding closePanel's
-- delayed hide callback -- same claimMotionGen idiom DailyPanel's claim-
-- resolve motion uses. Bumped on EVERY openPanel and closePanel call; the
-- task.delay(panelClose.Time, ...) callback below captures its own gen and
-- no-ops unless it's still current when it fires.
local closeGen = 0

local openPanel, closePanel, setBadge, pillAnchor -- assigned below, exposed via ctx

local ID_TO_SCREEN = {
	bag = "backpack", pass = "pass", daily = "daily",
	goals = "goals", index = "index", settings = "settings",
}

---------------------------------------------------------------- number format
-- Same abbreviation family DarrelHUDClient uses (NumberFormat.Short),
-- replicated locally per the brief rather than requiring that module.
local UNITS = {
	{ 1e18, "Qi" }, { 1e15, "Qa" }, { 1e12, "T" },
	{ 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" },
}
local function trunc2(x) return math.floor(x * 100) / 100 end
local function shortNumber(n)
	if type(n) ~= "number" or n ~= n then return "0" end
	if n == math.huge then return "\u{221E}" end
	if n == -math.huge then return "-\u{221E}" end
	local sign = n < 0 and "-" or ""
	n = math.abs(n)
	for _, unit in ipairs(UNITS) do
		if n >= unit[1] then
			return sign .. string.format("%.2f%s", trunc2(n / unit[1]), unit[2])
		end
	end
	return sign .. tostring(math.floor(n))
end

local function playPop(popScale)
	popScale.Scale = 0.85
	TweenService:Create(popScale, T.tween.pop, { Scale = 1 }):Play()
end

---------------------------------------------------------------- icon fallback
-- HUD RESCUE (2026-07-31): the kit's 8 icon PNGs are not imported yet, so
-- every Tokens.icons entry is still "" and UI.artSlot renders an unfilled
-- slot as a bare dark rounded box. Six of those stacked down the rail read
-- as "the UI is broken" -- which is how the live HUD looked. Until the ids
-- land, an unfilled slot gets the kit's chunky treatment (goldSmall
-- gradient + gloss on the rail's larger tiles) and a big centred emoji
-- standing in for the art. A slot whose id IS filled is left completely
-- alone, so pasting real ids into Tokens.icons silently retires all of this
-- with no further edit here.
-- Glyphs checked one by one against this build's emoji font on a throwaway
-- board in Play (same discipline the SFX work uses for audio: never pick by
-- name alone). U+1FA99 COIN, the obvious choice for the cash pill, renders
-- as an EMPTY BOX in Roblox -- it is Emoji 12.0 and the bundled font predates
-- it -- so cash uses U+1F4B0 MONEY BAG, which renders. Every other glyph here
-- was confirmed rendering at TextSize 90. If you add one, prove it the same
-- way before trusting it.
local GLYPH = {
	bag = "\u{1F392}", pass = "\u{1F3AB}", daily = "\u{1F4C5}",
	goals = "\u{1F4CB}", index = "\u{1F4D6}", settings = "\u{2699}",
	coin = "\u{1F4B0}", gem = "\u{1F48E}",
	-- darrel has no kit PNG and never will (he is ours, not the kit's), so this
	-- is only reached if IconArt itself fails to load; the diamond is the same
	-- stand-in the currency used before he had a face.
	darrel = "\u{1F48E}",
}

local function glyphFallback(slot, key, textSize, plated)
	local id = T.icons[key]
	if id and id ~= "" then return nil end -- real art imported: leave the slot untouched
	if plated then
		slot.BackgroundTransparency = 0
		slot.BackgroundColor3 = T.color.white
		UI.gradient(slot, T.gradient.goldSmall)
		UI.gloss(slot, T.radius.small)
	end
	local glyph = Instance.new("TextLabel")
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.Text = GLYPH[key] or "?"
	glyph.TextSize = textSize
	glyph.TextColor3 = T.color.white
	glyph.TextXAlignment = Enum.TextXAlignment.Center
	glyph.TextYAlignment = Enum.TextYAlignment.Center
	-- Deliberately NOT T.font.display: FredokaOne carries no emoji glyphs, and
	-- the default face falls back to the system emoji font cleanly.
	glyph.ZIndex = slot.ZIndex + 2 -- above UI.gloss's Gloss/Shade (slot.ZIndex + 1)
	glyph.Parent = slot
	return glyph
end

---------------------------------------------------------------- currency cluster
-- Top 18 / left 18, gap 12 (kit README 3.7). Hidden while any panel is open.
local currencyCluster = Instance.new("Frame")
currencyCluster.Name = "CurrencyCluster"
currencyCluster.Position = UDim2.fromOffset(18, 18)
currencyCluster.Size = UDim2.new(0, 0, 0, T.size.currencyPill)
currencyCluster.AutomaticSize = Enum.AutomaticSize.X
currencyCluster.BackgroundTransparency = 1
currencyCluster.ZIndex = T.zindex.currency
currencyCluster.Parent = chrome -- screen edge, not canvas edge (see the chrome layer)

local clusterList = Instance.new("UIListLayout")
clusterList.FillDirection = Enum.FillDirection.Horizontal
clusterList.VerticalAlignment = Enum.VerticalAlignment.Center
clusterList.SortOrder = Enum.SortOrder.LayoutOrder
clusterList.Padding = UDim.new(0, 12)
clusterList.Parent = currencyCluster

-- Pill height 54, radius 999, stroke 4, padding 0 18 0 6, 38px circular icon
-- slot (stroke 3) + value 24 (kit README 3.7).
--
-- Bug A fix (ui-overhaul checkpoint-1 fix wave): UI.gloss's Gloss/Shade
-- frames are Scale=1-of-parent decorative overlays, not flex items -- they
-- used to sit directly on `pill` alongside a horizontal UIListLayout that
-- swept them into the same row as IconSlot/Value (an undefined layout combo
-- once `pill` also carried AutomaticSize.X -- measured AbsoluteSize.X ~5700
-- in Play, see task-4-report.md). Builders' UI.gloss() itself is untouched
-- (panels depend on its current behaviour); instead the padding + list
-- layout + icon/value now live in a `Content` wrapper Frame that fills
-- `pill`, so Gloss/Shade stay untouched full-bleed siblings on `pill` and
-- never enter anyone's layout. `pill` itself is now explicitly sized --
-- icon + list gaps + measured text width + the kit's own padding --
-- recomputed via sizePillToValue() every time the value label's text
-- changes, with NO AutomaticSize anywhere on the pill.
local PILL_ICON_W = 38
local PILL_GAP = 8
local PILL_PAD_LEFT, PILL_PAD_RIGHT = 6, 18

local function sizePillToValue(pill, value)
	local spec = T.text.value
	local textWidth = TextService:GetTextSize(
		value.Text, spec[1], Enum.Font.FredokaOne, Vector2.new(1000, spec[1] + 24)
	).X
	local width = PILL_PAD_LEFT + PILL_ICON_W + PILL_GAP + textWidth + PILL_PAD_RIGHT
	pill.Size = UDim2.fromOffset(width, T.size.currencyPill)
end

-- `iconKey` names the pill (GemPill etc, which pillAnchor and the panels' coin
-- flight resolve against) while `artKey` chooses the artwork. They differ for
-- the second pill: it is the kit's "gem" slot structurally, but the currency it
-- counts is darrels, so it wears Darrel's face rather than a generic diamond.
local function buildPill(order, gradientKey, iconKey, artKey)
	artKey = artKey or iconKey
	local pill = Instance.new("Frame")
	pill.Name = iconKey:sub(1, 1):upper() .. iconKey:sub(2) .. "Pill"
	pill.LayoutOrder = order
	pill.Size = UDim2.new(0, 0, 0, T.size.currencyPill) -- real width set below by sizePillToValue
	pill.BackgroundColor3 = T.color.white
	pill.BorderSizePixel = 0
	pill.ZIndex = T.zindex.currency
	pill.Parent = currencyCluster
	UI.corner(pill, T.radius.pill)
	UI.gradient(pill, T.gradient[gradientKey])
	UI.stroke(pill, T.stroke.control)
	UI.gloss(pill, T.radius.pill) -- Gloss/Shade land directly on `pill`, outside Content's layout

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.ZIndex = pill.ZIndex + 2 -- above Gloss/Shade (frame.ZIndex+1 in UI.gloss)
	content.Parent = pill

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, PILL_PAD_LEFT)
	pad.PaddingRight = UDim.new(0, PILL_PAD_RIGHT)
	pad.Parent = content

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, PILL_GAP)
	list.Parent = content

	-- The kit's own coin/gem artwork carries its keyline and its rim, so with
	-- IconArt supplying it the slot is a bare transparent host -- no dark disc,
	-- no extra stroke. Only an imported image id still needs the art-slot
	-- treatment (circular crop + stroke) to sit right in the pill.
	local icon: GuiObject
	local iconId = T.icons[artKey]
	if iconId and iconId ~= "" then
		icon = UI.artSlot(content, UDim2.fromOffset(PILL_ICON_W, PILL_ICON_W), iconId)
		local iconCorner = icon:FindFirstChildOfClass("UICorner")
		if iconCorner then iconCorner.CornerRadius = UDim.new(1, 0) end -- circular, not the art-slot default
		UI.stroke(icon, 3)
	else
		local host = Instance.new("Frame")
		host.Size = UDim2.fromOffset(PILL_ICON_W, PILL_ICON_W)
		host.BackgroundTransparency = 1
		host.Parent = content
		icon = host
		if IconArt and IconArt.has(artKey) then
			IconArt.draw(host, artKey, PILL_ICON_W, content.ZIndex + 1)
		else
			glyphFallback(host, artKey, 24, false) -- last resort, unplated
		end
	end
	icon.Name = "IconSlot"
	icon.LayoutOrder = 1
	icon.ZIndex = content.ZIndex + 1

	local value = UI.label(content, "0", "value", T.color.white)
	value.Name = "Value"
	value.LayoutOrder = 2
	value.ZIndex = content.ZIndex + 1
	value.TextYAlignment = Enum.TextYAlignment.Center

	local popScale = Instance.new("UIScale")
	popScale.Parent = pill

	sizePillToValue(pill, value)

	return pill, value, popScale
end

local coinPill, coinValueLabel, coinPop = buildPill(1, "goldSmall", "coin")
local gemPill, gemValueLabel, gemPop = buildPill(2, "gem", "gem", "darrel")

local cash, darrels = 0, 0
local hasCashLoaded, hasDarrelsLoaded = false, false

-- alive pass #2: gains COUNT UP over 0.35s (Quint/Out via a tweened
-- NumberValue); spends snap instantly -- counting down reads as slow loss.
-- Retarget rule: a new value mid-count starts from the number currently
-- DISPLAYED, never the stale target. The pill has no AutomaticSize (Bug A),
-- so width re-tracks on every tick of the count.
-- COUNT-UP DRIVER.
--
-- CLAUDE.md says never lerp in a RunService loop for something a tween can do.
-- Measured in this place, a tween CANNOT do this. TweenService animates
-- GuiObject properties -- Frame.Size tweens fine, which is what drives the quest
-- bar fill -- but does NOT animate non-GuiObject instances. UIScale.Scale,
-- NumberValue.Value and Sound.Volume were each probed live and each sat at
-- whatever value it was last set to while its tween "ran". So a NumberValue
-- tween drove nothing, and the pill only ever updated via the snap path.
--
-- Stepped write on a task loop instead, token-guarded so a new target supersedes
-- the previous driver rather than two fighting over the label. The tuned
-- Quint-out shape is applied by hand, so the feel matches what was specified.
local function makeTicker(pillFrame, valueLabel, duration)
	local shown = 0
	local token = 0
	local function paint(v)
		valueLabel.Text = shortNumber(math.floor(v))
		sizePillToValue(pillFrame, valueLabel)
	end
	return function(target, animate)
		token += 1
		local myToken = token
		if not animate then
			shown = target
			paint(target)
			return
		end
		-- retarget from where the number VISIBLY is, so a burst of payouts
		-- chases one moving target and can never step backwards
		local from = shown
		local span = target - from
		local secs = duration or 0.35
		task.spawn(function()
			local t0 = os.clock()
			while true do
				if myToken ~= token then return end
				local a = math.clamp((os.clock() - t0) / secs, 0, 1)
				shown = from + span * (1 - (1 - a) ^ 5)   -- Quint out
				paint(shown)
				if a >= 1 then break end
				task.wait()
			end
			if myToken == token then shown = target; paint(target) end
		end)
	end
end
-- =========================== CASH GAIN FEEDBACK ===========================
-- A payout used to change the total silently. Now: the pill pops in the
-- direction of the change, and an increase floats a "+N" off the pill.
--
-- INCOME vs EVENT. IncomeLoop fires CashTick every 0.35s and nothing else on
-- the server fires it (verified), so CashTick IS the income channel and
-- DataUpdated carries the deliberate payouts -- catches, sales, claims. That
-- split needs no server change and is the whole reason this can batch income
-- without batching the things the player actually did.
--   income -> accumulate, at most one float per second, NO sound
--   event  -> float immediately, WITH the cash sound
-- Back-out and Quad-out written as plain functions, because the engine's
-- EasingStyle is only reachable through TweenInfo and tweens do not drive
-- UIScale here. c1/c3 are the standard Back constants.
local function easeBackOut(a)
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (a - 1) ^ 3 + c1 * (a - 1) ^ 2
end
local function easeQuadOut(a) return 1 - (1 - a) ^ 2 end
local POP_UP   = { from = 1.14, time = 0.26, ease = easeBackOut }
local POP_DOWN = { from = 0.92, time = 0.18, ease = easeQuadOut }
local FLOAT_RISE   = 38     -- px travelled
local FLOAT_TIME   = 0.75   -- seconds to travel it
local FLOAT_FADE_AT = 0.45  -- seconds before fade begins
local FLOAT_POOL   = 4      -- hard cap; the oldest is recycled, never a 5th instance
local INCOME_BATCH = 1.0    -- seconds of income folded into a single float

-- Same measured limitation as the ticker: a TweenService tween on UIScale.Scale
-- does not run in this place (probed live -- the scale sat at its start value
-- for the whole tween). Stepped, token-guarded, easing applied by hand so the
-- specified Back-out / Quad-out shapes survive.
local popToken = {}
local function playPopDir(popScale, spec)
	popToken[popScale] = (popToken[popScale] or 0) + 1
	local myToken = popToken[popScale]
	local from = spec.from
	local secs = spec.time
	local ease = spec.ease
	popScale.Scale = from
	task.spawn(function()
		local t0 = os.clock()
		while true do
			if popToken[popScale] ~= myToken then return end
			local a = math.clamp((os.clock() - t0) / secs, 0, 1)
			popScale.Scale = from + (1 - from) * ease(a)
			if a >= 1 then break end
			task.wait()
		end
		if popToken[popScale] == myToken then popScale.Scale = 1 end
	end)
end

-- POOLED. Four labels are built once and reused forever; a burst of payouts
-- recycles the oldest rather than allocating, so the pool size IS the cap.
local floatPool, floatNext = {}, 1
for i = 1, FLOAT_POOL do
	local l = UI.label(coinPill, "", "chip", T.color.textAccent)
	l.Name = "CashGain" .. i
	l.AnchorPoint = Vector2.new(0, 0.5)
	l.AutomaticSize = Enum.AutomaticSize.XY
	l.Visible = false
	l.ZIndex = coinPill.ZIndex + 6
	floatPool[i] = { label = l, token = 0 }
end

local function floatGain(amount)
	if amount < 1 then return end
	local slot = floatPool[floatNext]
	floatNext = floatNext % FLOAT_POOL + 1
	slot.token += 1
	local myToken = slot.token
	local l = slot.label

	l.Text = "+" .. shortNumber(math.floor(amount))
	l.TextTransparency = 0
	for _, d in ipairs(l:GetChildren()) do
		if d:IsA("UIStroke") then d.Transparency = 0 end
	end
	-- starts low and right of the pill and rises past it: reads as the payout
	-- travelling INTO the counter. Kept off the pill's own footprint so it
	-- never covers the number it is describing.
	l.Position = UDim2.new(1, 10, 0.5, 20)
	l.Visible = true

	TweenService:Create(l, TweenInfo.new(FLOAT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(1, 10, 0.5, 20 - FLOAT_RISE) }):Play()
	task.delay(FLOAT_FADE_AT, function()
		if slot.token ~= myToken then return end   -- recycled early: leave it to its new owner
		local fade = TweenInfo.new(FLOAT_TIME - FLOAT_FADE_AT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(l, fade, { TextTransparency = 1 }):Play()
		for _, d in ipairs(l:GetChildren()) do
			if d:IsA("UIStroke") then TweenService:Create(d, fade, { Transparency = 1 }):Play() end
		end
	end)
	task.delay(FLOAT_TIME + 0.05, function()
		if slot.token == myToken then l.Visible = false end
	end)
end

-- income accumulator: one float per INCOME_BATCH at most, no sound
local incomePending, incomeFlushQueued = 0, false
local function queueIncomeFloat(delta)
	incomePending += delta
	if incomeFlushQueued then return end
	incomeFlushQueued = true
	task.delay(INCOME_BATCH, function()
		incomeFlushQueued = false
		local n = incomePending
		incomePending = 0
		if n >= 1 then floatGain(n) end
	end)
end

local tickCash = makeTicker(coinPill, coinValueLabel, 0.45)   -- U2 tuning
local tickDarrels = makeTicker(gemPill, gemValueLabel)         -- gem pill untouched this round

-- source: "income" (CashTick, IncomeLoop's 0.35s tick) or "event" (a payout the
-- player caused). Defaults to "event" so any future caller is loud, not silent.
local function applyCash(n, source)
	if typeof(n) ~= "number" then return end
	local prev = cash
	cash = n
	local gained = hasCashLoaded and n > prev
	tickCash(n, gained)
	if hasCashLoaded then
		if n > prev then
			playPopDir(coinPop, POP_UP)
			local delta = n - prev
			if source == "income" then
				queueIncomeFloat(delta)          -- batched, silent
			else
				floatGain(delta)                 -- immediate
				SoundKit.play("cash", nil, { volume = 0.22 })
			end
		elseif n < prev then
			playPopDir(coinPop, POP_DOWN)        -- spending reads as a dip, not a bounce
		end
	end
	hasCashLoaded = true
end

local function applyDarrels(n)
	if typeof(n) ~= "number" then return end
	local prev = darrels
	darrels = n
	tickDarrels(n, hasDarrelsLoaded and n > prev)
	if hasDarrelsLoaded and n > prev then playPop(gemPop) end
	hasDarrelsLoaded = true
end

remotes.DataUpdated.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end
	if payload.Cash ~= nil then applyCash(payload.Cash, "event") end
end)

-- THE REAL DEFECT THIS ROUND FIXES. IncomeLoop fires CashTick every 0.35s, and
-- the visible pill was never subscribed to it -- only ClientMain (whose label
-- GameHUDClient retires) and TradeClient/MerchantClient were. So a stocked plot
-- earned continuously while the pill the player actually looks at sat still
-- until some unrelated event happened to fire DataUpdated.
remotes.CashTick.OnClientEvent:Connect(function(n)
	applyCash(n, "income")
end)

-- Bug C2 fix (gem seed redesign, round-2): applies unconditionally whenever
-- the payload carries a real number -- no latch/flag coordinating this with
-- the startup retry loop below. Whichever lands last (this push, or a
-- successful retry-loop pull) simply overwrites gemPill; last write wins.
remotes.DarrelUpdate.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end
	if typeof(payload.Darrels) == "number" then
		applyDarrels(payload.Darrels)
	end
end)

-- Startup pulls, mirroring DarrelHUDClient/EggShopClient's own join-time
-- invoke pattern: the push above can race this script's listener connecting.
task.spawn(function()
	local ok, snap = pcall(function() return remotes.GetInitialData:InvokeServer() end)
	if ok and typeof(snap) == "table" then applyCash(snap.Cash) end
end)

-- Bug C3 fix (gem seed, round-4 -- ACTUAL ROOT CAUSE). The previous two
-- redesigns both tuned the RETRY logic (latch -> latch-free, 3x2s -> 5x2s),
-- but the loop was never retrying at all: it "succeeded" on attempt 1, a
-- fraction of a second after join, and returned for good.
--
-- DarrelService.M.Get is `local data = PDM.Get(player); return data and
-- data.Darrels or 0`, and PlayerDataManager.Get is a plain
-- `cache[player.UserId]` lookup that stays nil until the async DataStore
-- load lands. So any pull that beats the profile load returns a PLACEHOLDER
-- {Darrels = 0}, and `typeof(res.Darrels) == "number"` is perfectly true of
-- 0 -- a "valid" result indistinguishable from this pill's own seed text,
-- which is exactly why it always looked like the pull never landed. Nothing
-- corrected it afterwards either: DarrelService.Init's join-time push is
-- itself guarded by `if data then`, so it no-ops on the same unloaded
-- profile and DarrelUpdate never fires at join at all.
--
-- The response already carries an unambiguous loaded/not-loaded
-- discriminator: M.GetDailyState returns nil for an unloaded profile (`if
-- not data then return nil end`) and a real table once loaded -- driven by
-- the very same `data` nil-check that produces the placeholder 0. So keep
-- pulling until `Daily` proves the profile is loaded, applying whatever came
-- back on every pass (so a player whose real balance IS 0 still displays
-- immediately), and stop the instant the value is known to be real.
task.spawn(function()
	for attempt = 1, 20 do
		local ok, res = pcall(function() return remotes.DarrelState:InvokeServer() end)
		if ok and typeof(res) == "table" and typeof(res.Darrels) == "number" then
			applyDarrels(res.Darrels)
			if typeof(res.Daily) == "table" then
				return -- profile is loaded; this value is real
			end
		end
		task.wait(1)
	end
end)

---------------------------------------------------------------- nav rail
-- v2 spec (kit README 3.7, pixel-adjudicated against captures/hud.png):
-- inset 10, vertically centred, gap 6 -- NO button plate, the icon
-- floats bare. Item column width 106: 66x66 icon, label directly under it
-- (T.text.railLabel: Fredoka One 20 / stroke 4). Active state = an 88px
-- radial gold glow behind the icon (T.size.railGlow / T.color.activeGlow),
-- not a ring around a plate that no longer exists. Notification badge:
-- top -6 / right 12 relative to the item column. Hover translateY(-3) +
-- scale(1.03), press translateY(+2) + scale(0.99) (kit README section 4).
--
-- ui(3-fix1) user decision (2026-07-30): the rail moves to the LEFT edge
-- of the canvas -- the kit drew it on the right. Reading the Tokens side
-- setting keeps the edge choice data-driven, so a future flip only touches
-- Tokens.lua; T.size.railInset still supplies the inset distance either way.
local RAIL_ON_LEFT = (T.size.railSide == "left")

-- Vertically centred BELOW the currency cluster's band, not across the whole
-- layer: the pills occupy y 18-72 and the rail shares their left edge, so it
-- centres within [96, layer height - 72] instead.
--
-- HUD RESCUE (2026-07-31): that band is measured against the LIVE viewport
-- (via the chrome layer) rather than the 775px design canvas, and the rail
-- scales down when the band is shorter than the column it has to hold. The
-- old constant assumed the full design height was always available; on the
-- measured 1891x772 window the real band is ~549px against a 618px column,
-- so the rail overflowed the bottom of the screen and took the Settings item
-- with it. The bottom reserve is what keeps it clear of WheelClient's
-- bottom-left FastSpinToggle (measured live at x[22..190] y[702..748]
-- true-screen, deliberately parked under the rail there -- see WheelClient's
-- "Bug E fix" comment). Those two columns overlap horizontally by ~82px, so
-- the vertical gap is the only thing separating them: a 72px reserve measured
-- out at 2.5px of clearance, which is not a margin, it is a coincidence. 88
-- puts the rail's bottom at ~683 for ~19px of real gap, and costs only ~2px
-- off each icon (56.6px rendered, still well clear of the kit's 44px minimum
-- touch target).
local RAIL_TOP_CLEARANCE = 96
local RAIL_BOTTOM_RESERVE = 88
local RAIL_ICON_GAP = 6
local RAIL_LABEL_H = 26
-- claim halo: a shade wider than the icon so it reads as a rim of gold
-- around the art, not a plate behind it
local RAIL_CLAIM_D = T.size.railIcon + 10

local RAIL_ORDER = {
	{ id = "bag", label = "Bag" },
	{ id = "pass", label = "Pass" },
	{ id = "daily", label = "Daily" },
	{ id = "goals", label = "Goals" },
	{ id = "index", label = "Index" },
	{ id = "settings", label = "Settings" },
}

-- USER LAYOUT (2026-07-30): two columns of three instead of one column of six,
-- filled COLUMN-FIRST -- Bag/Pass/Daily down the left, Goals/Index/Settings
-- beside them. Anchored to the TOP of the band rather than centred in it, so
-- the left column keeps the on-screen position it already had. Three rows of
-- full-size items is 306px against a ~532px band, so railScale sits back at
-- 1.0 and the icons render at the kit's intended 66px again.
local RAIL_ROWS = 3
local RAIL_COLS = math.ceil(#RAIL_ORDER / RAIL_ROWS)
local RAIL_ITEM_H = T.size.railIcon + RAIL_ICON_GAP + RAIL_LABEL_H
local RAIL_W = RAIL_COLS * T.size.railItem + (RAIL_COLS - 1) * T.size.railGap
local RAIL_H = RAIL_ROWS * RAIL_ITEM_H + (RAIL_ROWS - 1) * T.size.railGap

local rail = Instance.new("Frame")
rail.Name = "NavRail"
rail.AnchorPoint = if RAIL_ON_LEFT then Vector2.new(0, 0) else Vector2.new(1, 0)
rail.Size = UDim2.fromOffset(RAIL_W, RAIL_H)
rail.BackgroundTransparency = 1
rail.ZIndex = T.zindex.rail
rail.Parent = chrome -- screen edge, not canvas edge (see the chrome layer)

-- Shrink-to-fit, so the rail can never run off the bottom of the screen the
-- way it did before this rescue. 1.0 on any window tall enough for the kit's
-- full-size grid; below that it scales down, from the top-left, instead of
-- overflowing.
local railScale = Instance.new("UIScale")
railScale.Parent = rail

-- Fills the local forward-declared next to fit(), which calls this on every
-- viewport change -- the band depends on the live viewport height.
layoutRail = function()
	local band = math.max(chrome.Size.Y.Offset - RAIL_TOP_CLEARANCE - RAIL_BOTTOM_RESERVE, 1)
	railScale.Scale = math.min(1, band / RAIL_H)
	if RAIL_ON_LEFT then
		rail.Position = UDim2.new(0, T.size.railInset, 0, RAIL_TOP_CLEARANCE)
	else
		rail.Position = UDim2.new(1, -T.size.railInset, 0, RAIL_TOP_CLEARANCE)
	end
end
layoutRail()

-- Placed by hand rather than by a UIListLayout: the grid is column-first,
-- which no single FillDirection expresses, and a layout-managed child ignores
-- writes to its Position -- which had quietly been making the hover/press
-- translate below a no-op (only the scale half of it was landing).
for order, cfg in ipairs(RAIL_ORDER) do
	local col = math.floor((order - 1) / RAIL_ROWS)
	local row = (order - 1) % RAIL_ROWS

	local item = Instance.new("Frame")
	item.Name = cfg.id .. "Item"
	item.LayoutOrder = order
	item.Position = UDim2.fromOffset(
		col * (T.size.railItem + T.size.railGap),
		row * (RAIL_ITEM_H + T.size.railGap)
	)
	item.Size = UDim2.fromOffset(T.size.railItem, RAIL_ITEM_H)
	item.BackgroundTransparency = 1
	item.ZIndex = T.zindex.rail
	item.Parent = rail

	local itemScale = Instance.new("UIScale")
	itemScale.Parent = item

	-- v2: no button plate -- the icon floats directly on the item column,
	-- top-aligned, with the label directly under it. USER (2026-07-30): and no
	-- gold tile behind the art either. The slot is now a bare transparent host;
	-- what goes in it is the kit's own icon artwork, matching captures/hud.png.
	local icon = Instance.new("Frame")
	icon.Name = "IconSlot"
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 0)
	icon.Size = UDim2.fromOffset(T.size.railIcon, T.size.railIcon)
	icon.BackgroundTransparency = 1
	icon.ZIndex = item.ZIndex + 2
	icon.Parent = item

	local iconId = T.icons[cfg.id]
	if iconId and iconId ~= "" then
		-- imported art always wins once the ids land in Tokens
		local img = Instance.new("ImageLabel")
		img.Name = "Art"
		img.Size = UDim2.fromScale(1, 1)
		img.BackgroundTransparency = 1
		img.Image = iconId
		img.ScaleType = Enum.ScaleType.Fit
		img.ZIndex = icon.ZIndex + 1
		img.Parent = icon
	elseif IconArt and IconArt.has(cfg.id) then
		IconArt.draw(icon, cfg.id, T.size.railIcon, icon.ZIndex + 1)
	else
		glyphFallback(icon, cfg.id, 40, false) -- last resort, unplated
	end

	local label = UI.label(item, cfg.label, "railLabel", T.color.white)
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 0)
	-- RAIL_ICON_GAP is the kit's smallest spacing-scale step -- README 3.7
	-- gives no explicit icon-label gap ("label directly under it"). Both
	-- constants feed layoutRail's height math too, so they stay in sync.
	label.Position = UDim2.new(0.5, 0, 0, T.size.railIcon + RAIL_ICON_GAP)
	label.Size = UDim2.new(1, 0, 0, RAIL_LABEL_H)
	label.AutomaticSize = Enum.AutomaticSize.None
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.ZIndex = item.ZIndex + 2

	-- Active state (kit README 3.7): "88px radial gold glow behind the
	-- icon, rgba(255,232,122,.75) centre -> transparent at 72%". Roblox's
	-- UIGradient has no radial mode, so this approximates the falloff with
	-- concentric circles (opaque centre, fading outward, capped ~72% of
	-- the radius) instead of a texture asset -- same non-native-primitive
	-- workaround convention as UI.rainbowRing above.
	local glow = Instance.new("Frame")
	glow.Name = "ActiveGlow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.new(0.5, 0, 0, T.size.railIcon / 2)
	glow.Size = UDim2.fromOffset(T.size.railGlow, T.size.railGlow)
	glow.BackgroundTransparency = 1
	glow.Visible = false
	glow.ZIndex = item.ZIndex + 1 -- behind the icon (item.ZIndex+2), above the transparent item bg
	glow.Parent = item

	local GLOW_RINGS = { -- {diameter fraction of railGlow, transparency} outer -> inner
		{ 0.70, 0.90 },
		{ 0.50, 0.72 },
		{ 0.30, 0.50 },
		{ 0.14, 0.25 }, -- innermost/most opaque, ~= rgba(255,232,122,.75)
	}
	for i, ringSpec in ipairs(GLOW_RINGS) do
		local d = T.size.railGlow * ringSpec[1]
		local glowRing = Instance.new("Frame")
		glowRing.Name = "Ring" .. i
		glowRing.AnchorPoint = Vector2.new(0.5, 0.5)
		glowRing.Position = UDim2.fromScale(0.5, 0.5)
		glowRing.Size = UDim2.fromOffset(d, d)
		glowRing.BackgroundColor3 = T.color.activeGlow
		glowRing.BackgroundTransparency = ringSpec[2]
		glowRing.BorderSizePixel = 0
		glowRing.ZIndex = glow.ZIndex
		glowRing.Parent = glow
		UI.corner(glowRing, d / 2)
	end

	-- Claim halo (U3 port): SideRail's claim arbitration paints onto this --
	-- see attachClaimSurface below the loop. A single soft gold disc behind
	-- the icon. Visible/BackgroundTransparency are owned by SideRail: shown
	-- at rest alpha while claimable, breathed by its shared Heartbeat driver
	-- while this button holds pulse priority. Per-frame property writes, no
	-- TweenService (BackgroundTransparency tweens do not run in this place).
	local claimHalo = Instance.new("Frame")
	claimHalo.Name = "ClaimHalo"
	claimHalo.AnchorPoint = Vector2.new(0.5, 0.5)
	claimHalo.Position = UDim2.new(0.5, 0, 0, T.size.railIcon / 2)
	claimHalo.Size = UDim2.fromOffset(RAIL_CLAIM_D, RAIL_CLAIM_D)
	claimHalo.BackgroundColor3 = T.color.activeGlow
	claimHalo.BackgroundTransparency = 0.35
	claimHalo.BorderSizePixel = 0
	claimHalo.Visible = false
	claimHalo.ZIndex = item.ZIndex + 1 -- behind the icon, beside ActiveGlow
	claimHalo.Parent = item
	UI.corner(claimHalo, RAIL_CLAIM_D / 2)

	-- Hit target: invisible button covering icon + label -- comfortably
	-- above the 44px minimum touch target regardless of the 66px icon
	-- alone (kit README section 2: "touch targets never below 44 px").
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.ZIndex = item.ZIndex + 10
	hit.Parent = item
	wireClick(hit, "uiClick")

	-- Base position captured lazily on first use, not at build time: `item`
	-- is a UIListLayout child and its list-computed Position isn't
	-- guaranteed resolved yet in the same tick these instances are built,
	-- but MouseEnter only ever fires after real rendering has happened.
	local restPos = nil
	local function basePos()
		restPos = restPos or item.Position
		return restPos
	end

	hit.MouseEnter:Connect(function()
		TweenService:Create(itemScale, T.tween.hover, { Scale = 1.03 }):Play()
		TweenService:Create(item, T.tween.hover, { Position = basePos() - UDim2.fromOffset(0, 3) }):Play()
	end)
	hit.MouseLeave:Connect(function()
		TweenService:Create(itemScale, T.tween.hover, { Scale = 1.0 }):Play()
		TweenService:Create(item, T.tween.hover, { Position = basePos() }):Play()
	end)
	hit.MouseButton1Down:Connect(function()
		TweenService:Create(itemScale, T.tween.press, { Scale = 0.99 }):Play()
		TweenService:Create(item, T.tween.press, { Position = basePos() + UDim2.fromOffset(0, 2) }):Play()
	end)
	hit.MouseButton1Up:Connect(function()
		TweenService:Create(itemScale, T.tween.press, { Scale = 1.03 }):Play()
		TweenService:Create(item, T.tween.press, { Position = basePos() - UDim2.fromOffset(0, 3) }):Play()
	end)
	hit.MouseButton1Click:Connect(function()
		if currentPanelId == cfg.id then
			closePanel()
		else
			openPanel(cfg.id)
		end
	end)

	railItems[cfg.id] = { frame = item, glow = glow, scale = itemScale, claim = claimHalo }
end

-- U3 port: these rail buttons are the claim surface now -- the legacy
-- LeftRail this used to happen on is hidden permanently further down this
-- file. SideRail's central arbitration (priority table + PULSE_MAX cap)
-- still decides WHO pulses; it just paints onto these halos. Rebirth is
-- deliberately absent: it has no button on this rail, so its claim cue has
-- no visible home yet. Type-guarded so an older SideRail (two sessions edit
-- this place) can never hard-error the HUD build.
local CLAIM_SOURCE = { daily = "Daily", goals = "Goals", pass = "Season" }
if type(SideRail.attachClaimSurface) == "function" then
	for id, tileName in pairs(CLAIM_SOURCE) do
		local entry = railItems[id]
		if entry and entry.claim then
			SideRail.attachClaimSurface(tileName, entry.claim)
		end
	end
end

---------------------------------------------------------------- panel control
local function updateActiveGlow()
	for id, item in pairs(railItems) do
		item.glow.Visible = (id == currentPanelId)
	end
end

-- Bug D fix (ui-overhaul checkpoint-1 fix wave): kit-styled "COMING SOON"
-- placeholder mounted into `host` when openPanel(id) is called for an id
-- with no registered module yet (GameHUDPanels is empty this checkpoint --
-- panels arrive in later tasks). Destroyed on close (closePanel) or the
-- instant a later openPanel call swaps to a different id -- never left
-- orphaned in host.
local placeholderWrapper = nil
local placeholderFrame = nil
local placeholderForId = nil

-- Bug D2 fix (placeholder shadow leak, round-2): UI.panel() parents its
-- HardShadow as a SIBLING of the panel Frame (into whatever `parent`
-- UI.panel was called with -- see UIKit.Builders' UI.hardShadow:
-- `sh.Parent = frame.Parent`), not as a child of the panel.
-- destroyPlaceholder() used to destroy only placeholderFrame (the panel),
-- leaving that sibling shadow behind every time -- one orphaned
-- `HardShadow` accumulating in `host` per open/close cycle
-- (task-4-report.md Round-2 Check D). Fix: destroy the wrapper Frame that
-- now hosts both (see buildPlaceholder below), taking panel + shadow
-- together in one call.
local function destroyPlaceholder()
	if placeholderWrapper then
		placeholderWrapper:Destroy()
		placeholderWrapper = nil
		placeholderFrame = nil
		placeholderForId = nil
	end
end

local function buildPlaceholder(id)
	local screenName = ID_TO_SCREEN[id] or id
	local width = T.size.panelWidth[screenName] or 700

	-- Bug D2 fix: mount the placeholder inside a transparent, full-size
	-- wrapper Frame parented into `host`, and build UI.panel() INSIDE that
	-- wrapper instead of directly into `host` -- the panel and its sibling
	-- HardShadow (see UI.panel/UI.hardShadow in UIKit.Builders) both land
	-- inside the wrapper this way, so destroyPlaceholder() destroying the
	-- wrapper takes both with it.
	local wrapper = Instance.new("Frame")
	wrapper.Name = "PlaceholderWrapper"
	wrapper.Size = UDim2.fromScale(1, 1)
	wrapper.BackgroundTransparency = 1
	wrapper.ZIndex = host.ZIndex
	wrapper.Parent = host
	placeholderWrapper = wrapper

	local panel = UI.panel(wrapper, UDim2.fromOffset(width, 566))
	panel.Name = "PlaceholderPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 16)
	list.Parent = panel

	local title = UI.label(panel, id, "panelTitle", T.color.white)
	title.Name = "PanelTitleLabel"
	title.LayoutOrder = 1
	title.TextXAlignment = Enum.TextXAlignment.Center

	local comingSoon = UI.label(panel, "COMING SOON", "buttonL", T.color.white)
	comingSoon.Name = "ComingSoonLabel"
	comingSoon.LayoutOrder = 2
	comingSoon.TextXAlignment = Enum.TextXAlignment.Center

	return panel
end

function openPanel(id)
	pcall(SoundKit.play, "panelOpen", nil, { volume = CLICK_VOLUME })
	closeGen += 1 -- FIX F3: invalidate any in-flight closePanel hide callback
	local mod = panelModules[id]

	-- Bug D fix: the shell (host/scrim/currency-hide/single-open) must engage
	-- even when no panel module is registered for `id` yet -- every id used to
	-- early-return before ANY of this ran, silently disabling both this
	-- checkpoint's expected "empty shell opens" feedback and SideRail's
	-- legacy-closing behaviour (both hang off host's Visible transition -- see
	-- the watcher near the bottom of this file). Only the panel CONTENT is
	-- conditional now; the shell state changes below are unconditional.
	if currentPanelId and currentPanelId ~= id then
		if panelInstances[currentPanelId] then
			panelInstances[currentPanelId].Visible = false
		end
		if placeholderForId == currentPanelId then
			destroyPlaceholder()
		end
	end

	local frame
	if mod then
		if not panelInstances[id] then
			local ok, built = pcall(mod.Build, ctx)
			if not ok or typeof(built) ~= "Instance" then return end
			built.Parent = host
			built.Visible = false
			panelInstances[id] = built
		end
		frame = panelInstances[id]
	else
		if placeholderForId ~= id then
			destroyPlaceholder()
			placeholderFrame = buildPlaceholder(id)
			placeholderForId = id
		end
		frame = placeholderFrame
	end

	currentPanelId = id
	state.screen = ID_TO_SCREEN[id] or id
	host.Visible = true
	currencyCluster.Visible = false

	frame.Visible = true
	local scale = frame:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = frame
	end
	scale.Scale = 0.92
	TweenService:Create(scale, T.tween.panelOpen, { Scale = 1 }):Play()

	scrim.Visible = true
	scrim.BackgroundTransparency = 1
	TweenService:Create(scrim, T.tween.scrim, { BackgroundTransparency = T.scrimAlpha }):Play()

	updateActiveGlow()
end

function closePanel()
	if not currentPanelId then return end   -- guard FIRST: no sound for a no-op close
	pcall(SoundKit.play, "panelClose", nil, { volume = CLICK_VOLUME })
	closeGen += 1 -- FIX F3: bump on every close too, so a close->reopen->close
	-- sequence never lets an earlier close's delayed callback act on a later state
	local myCloseGen = closeGen
	local id = currentPanelId
	local frame = panelInstances[id]
	if not frame and placeholderForId == id then
		frame = placeholderFrame
	end
	currentPanelId = nil
	state.screen = "none"
	currencyCluster.Visible = true
	updateActiveGlow()

	if frame then
		local scale = frame:FindFirstChildOfClass("UIScale")
		if scale then
			TweenService:Create(scale, T.tween.panelClose, { Scale = 0.95 }):Play()
		end
	end
	TweenService:Create(scrim, T.tween.panelClose, { BackgroundTransparency = 1 }):Play()

	-- FIX F3 (2026-07-30 fix wave): this callback used to run unconditionally,
	-- so a close->reopen within panelClose.Time (e.g. a rail double-click) hid
	-- the freshly reopened panel out from under the player -- openPanel bumps
	-- closeGen too, so myCloseGen goes stale the instant any open/close call
	-- happens after this one, and the callback no-ops instead of touching
	-- state that no longer belongs to it.
	task.delay(T.tween.panelClose.Time, function()
		if myCloseGen ~= closeGen then return end
		if frame then frame.Visible = false end
		if placeholderForId == id then
			destroyPlaceholder()
		end
		if not currentPanelId then
			scrim.Visible = false
			host.Visible = false
		end
	end)
end

function setBadge(id, n)
	local item = railItems[id]
	if not item then return end
	if not n or n <= 0 then
		if railBadges[id] then
			railBadges[id]:Destroy()
			railBadges[id] = nil
		end
		return
	end
	local text = (n > 99) and "99+" or tostring(n)
	if railBadges[id] then
		local label = railBadges[id]:FindFirstChild("Value")
		if label then label.Text = text end
	else
		-- v2 (kit README 3.7): min-width 34, height 34, stroke 4, hard
		-- shadow 0 3, value 19, at top -6 / right 12 relative to the item
		-- column -- UI.badge ships the v1 defaults (30/30, stroke 3.5, no
		-- shadow, text 16), overridden here rather than in the shared builder.
		local b = UI.badge(item.frame, text)
		b.Size = UDim2.fromOffset(0, 34)
		local sizeConstraint = b:FindFirstChildOfClass("UISizeConstraint")
		if sizeConstraint then sizeConstraint.MinSize = Vector2.new(34, 34) end
		local badgeStroke = b:FindFirstChildOfClass("UIStroke")
		if badgeStroke then badgeStroke.Thickness = 4 end
		local valueLabel = b:FindFirstChild("Value")
		if valueLabel then valueLabel.TextSize = 19 end
		b.AnchorPoint = Vector2.new(1, 0)
		b.Position = UDim2.new(1, -12, 0, -6)
		b.ZIndex = T.zindex.rail + 15
		UI.hardShadow(b, 3, T.radius.pill)
		railBadges[id] = b
	end
end

function pillAnchor(which)
	local pill = (which == "gem") and gemPill or coinPill
	if not pill then return Vector2.new(0, 0) end
	return pill.AbsolutePosition + pill.AbsoluteSize / 2
end

ctx.Tokens = T
ctx.Builders = UI
ctx.remotes = remotes
ctx.host = host
ctx.openPanel = openPanel
ctx.closePanel = closePanel
ctx.setBadge = setBadge
ctx.pillAnchor = pillAnchor
ctx.state = state

---------------------------------------------------------------- panel registration
-- Every ModuleScript dropped into the sibling GameHUDPanels folder is
-- required at startup. { Id, Build } expected; anything else (or a require
-- that errors) is skipped silently -- the folder is empty until later tasks.
local panelsFolder = script.Parent:WaitForChild("GameHUDPanels")
for _, m in ipairs(panelsFolder:GetChildren()) do
	if m:IsA("ModuleScript") then
		local ok, mod = pcall(require, m)
		if ok and type(mod) == "table" and type(mod.Build) == "function" and type(mod.Id) == "string" then
			panelModules[mod.Id] = mod
		end
	end
end

---------------------------------------------------------------- ESC
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Escape then
		closePanel()
	end
end)

---------------------------------------------------------------- SideRail single-open integration
-- Legacy surfaces (wheel, egg shop, fusion, shop/sell, daily, quests, season,
-- index, backpack, merchant...) and the new HUD close one another.
SideRail.registerPanel(host)

-- SideRail's own registerPanel watcher force-closes OTHER registered panels
-- the instant one of them opens -- including this host. When that happens
-- our bookkeeping (currentPanelId, currency cluster, active glow) needs to
-- resync even though it wasn't our own closePanel() that hid it.
host:GetPropertyChangedSignal("Visible"):Connect(function()
	if host.Visible or not currentPanelId then return end
	local id = currentPanelId
	local frame = panelInstances[id]
	if frame then frame.Visible = false end
	-- Bug D fix: SideRail's registry can force-close `host` (e.g. legacy egg
	-- shop opening) without ever going through closePanel() -- the placeholder
	-- needs the same cleanup here so it never survives host being hidden out
	-- from under it.
	if placeholderForId == id then
		destroyPlaceholder()
	end
	scrim.Visible = false
	currentPanelId = nil
	state.screen = "none"
	currencyCluster.Visible = true
	updateActiveGlow()
end)

-- Hide SideRail's own visual rail PERMANENTLY: its tiles stay functional
-- (registerPanel/single-open still runs for legacy panels) but invisible --
-- panel opening now goes through the new rail above only. No exported
-- no-op-safe call exists on SideRail for this, so this reaches into
-- PlayerGui.SideRailUI.LeftRail directly. SideRail's own updateRailVisibility
-- flips this frame back to Visible=true every time a registered panel closes
-- (anyOpen == false), so a one-shot Visible=false is not enough -- a watcher
-- re-hides it every time that happens. Disconnects nothing inside SideRail.
task.spawn(function()
	local sideRailUI = playerGui:WaitForChild("SideRailUI", 5)
	local leftRail = sideRailUI and sideRailUI:WaitForChild("LeftRail", 5)
	if not leftRail then return end
	leftRail.Visible = false
	leftRail:GetPropertyChangedSignal("Visible"):Connect(function()
		if leftRail.Visible then leftRail.Visible = false end
	end)
end)

---------------------------------------------------------------- legacy retirements
-- Runtime property sets, all WaitForChild-timeout + nil-guarded -- a
-- collaborator may have renamed or removed any of these, and a missing
-- legacy gui must never hard-error the new HUD.
local function retire(container, name, timeout)
	if not container then return end
	local inst = container:WaitForChild(name, timeout or 5)
	if not inst then return end
	if inst:IsA("ScreenGui") then
		inst.Enabled = false
	elseif inst:IsA("GuiObject") then
		inst.Visible = false
	end
end

-- HUD RESCUE (2026-07-31): every retirement now gets its OWN thread. They
-- used to run in sequence inside a single one, where a WaitForChild(name, 5)
-- for a gui that does not exist blocks the whole chain for the full timeout
-- -- and IndexUI genuinely does not exist in this build (verified live: no
-- IndexUI under PlayerGui, IndexClient parents into MainUI). So the legacy
-- cash pill, the old gem HUD and the old backpack button sat on top of the
-- new HUD for 5+ seconds after EVERY join; it showed up in back-to-back join
-- captures. Independent threads mean a missing gui only ever costs its own
-- thread the wait.
local function retireAsync(container, name, timeout)
	task.spawn(retire, container, name, timeout)
end

-- Daily / Quests / Season each own a ScreenGui.
retireAsync(playerGui, "DailyUI")
retireAsync(playerGui, "QuestUI")
retireAsync(playerGui, "SeasonUI")
-- IndexUI: known absent today (see above); kept per the brief in case a
-- future rename reintroduces it, and nil-guarded so absence is a no-op.
retireAsync(playerGui, "IndexUI")
retireAsync(playerGui, "DarrelHUD")

-- Backpack's panel/open-button are Frames inside MainUI, not their own
-- ScreenGui (confirmed by reading BackpackClient) -- MainUI itself stays up
-- (hotbar, cash pill host) and only these Frames retire.
task.spawn(function()
	local mainUI = playerGui:WaitForChild("MainUI", 5)
	if not mainUI then return end
	retireAsync(mainUI, "BackpackFrame")
	retireAsync(mainUI, "BackpackOpen")
	retireAsync(mainUI, "CashFrame")
end)
