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
-- Bug B fix (ui-overhaul checkpoint-1 fix wave): same class of IgnoreGuiInset
-- gotcha WheelClient's own Task 4 fix documents (StarterPlayerScripts.
-- WheelClient, search "IgnoreGuiInset", ~lines 79-89) -- but this canvas needs
-- to truly span the FULL screen (the kit is edge-to-edge), so unlike Wheel's
-- fix (set IgnoreGuiInset=false, hand-correct positions elsewhere) this keeps
-- IgnoreGuiInset=true and compensates the centring instead. Measured live
-- (task-4-report.md Check 2): Canvas.AbsolutePosition was (0,-57.3) in a
-- 1379x793 viewport against AbsoluteSize (1379,791.6) -- solving
-- (V-2I)/2 - S/2 = -57.3 for I gives exactly 58, matching Wheel's own
-- measured GuiInset for this build. That means the shortfall is a FULL
-- GuiInset().Y, not half of one: Scale(0.5,0.5) here resolves against a
-- parent height that's already net the inset on top of AnchorPoint's own
-- centring. Adding the inset back as a raw Y offset (unaffected by
-- canvasScale, since UIScale below scales root's own rendered SIZE, not the
-- Position offset computed against root's parent) restores true (0,0)
-- full-screen centring.
root.Position = UDim2.new(0.5, 0, 0.5, GuiService:GetGuiInset().Y)
root.Size = UDim2.fromOffset(T.size.canvas.X, T.size.canvas.Y)
root.BackgroundTransparency = 1
root.Parent = gui

-- Uniform fit-to-viewport scale (kit README section 1). Exactly ONE
-- connection drives this for the whole HUD -- currency, rail, scrim and the
-- panel host all live under `root`, so nothing else needs its own listener.
local canvasScale = Instance.new("UIScale")
canvasScale.Parent = root

local function fit()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local vp = camera.ViewportSize
	canvasScale.Scale = math.min(vp.X / T.size.canvas.X, vp.Y / T.size.canvas.Y)
end
fit()
do
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
end

---------------------------------------------------------------- scrim
local scrim = Instance.new("Frame")
scrim.Name = "Scrim"
scrim.Size = UDim2.fromScale(1, 1)
scrim.BackgroundColor3 = T.scrim
scrim.BackgroundTransparency = T.scrimAlpha
scrim.BorderSizePixel = 0
scrim.Visible = false
scrim.ZIndex = T.zindex.panel
scrim.Parent = root

---------------------------------------------------------------- panel host
-- Common shell (kit README section 3): padding-left 132 reserves the nav
-- rail (now on the LEFT per the 2026-07-30 user decision), padding-right
-- 24. Panel Build(ctx) functions parent their own (e.g. 960-wide) panel
-- Frame into this host and centre themselves within it.
local host = Instance.new("Frame")
host.Name = "PanelHost"
host.Position = UDim2.fromOffset(T.size.panelRightGutter, 0)
host.Size = UDim2.new(1, -(T.size.panelRightGutter + 24), 1, 0)
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
local railItems = {}      -- id -> { frame, glow, scale }
local railBadges = {}     -- id -> badge Frame

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

---------------------------------------------------------------- currency cluster
-- Top 18 / left 18, gap 12 (kit README 3.7). Hidden while any panel is open.
local currencyCluster = Instance.new("Frame")
currencyCluster.Name = "CurrencyCluster"
currencyCluster.Position = UDim2.fromOffset(18, 18)
currencyCluster.Size = UDim2.new(0, 0, 0, T.size.currencyPill)
currencyCluster.AutomaticSize = Enum.AutomaticSize.X
currencyCluster.BackgroundTransparency = 1
currencyCluster.ZIndex = T.zindex.currency
currencyCluster.Parent = root

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

local function buildPill(order, gradientKey, iconKey)
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

	local icon = UI.artSlot(content, UDim2.fromOffset(PILL_ICON_W, PILL_ICON_W), T.icons[iconKey])
	icon.Name = "IconSlot"
	icon.LayoutOrder = 1
	icon.ZIndex = content.ZIndex + 1
	local iconCorner = icon:FindFirstChildOfClass("UICorner")
	if iconCorner then iconCorner.CornerRadius = UDim.new(1, 0) end -- circular, not the art-slot default
	UI.stroke(icon, 3)

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
local gemPill, gemValueLabel, gemPop = buildPill(2, "gem", "gem")

local cash, darrels = 0, 0
local hasCashLoaded, hasDarrelsLoaded = false, false
-- Bug C fix: guards the startup retry below against a race with
-- DarrelUpdate -- set true the instant EITHER path lands a real value so the
-- other stops touching gemPill.
local darrelSeeded = false

local function applyCash(n)
	if typeof(n) ~= "number" then return end
	local prev = cash
	cash = n
	coinValueLabel.Text = shortNumber(n)
	sizePillToValue(coinPill, coinValueLabel) -- Bug A fix: pill has no AutomaticSize, recompute on every value change
	if hasCashLoaded and n > prev then playPop(coinPop) end
	hasCashLoaded = true
end

local function applyDarrels(n)
	if typeof(n) ~= "number" then return end
	local prev = darrels
	darrels = n
	gemValueLabel.Text = shortNumber(n)
	sizePillToValue(gemPill, gemValueLabel) -- Bug A fix: pill has no AutomaticSize, recompute on every value change
	if hasDarrelsLoaded and n > prev then playPop(gemPop) end
	hasDarrelsLoaded = true
end

remotes.DataUpdated.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end
	if payload.Cash ~= nil then applyCash(payload.Cash) end
end)

remotes.DarrelUpdate.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end
	darrelSeeded = true -- Bug C fix: a real push beats the startup retry loop to it
	applyDarrels(payload.Darrels)
end)

-- Startup pulls, mirroring DarrelHUDClient/EggShopClient's own join-time
-- invoke pattern: the push above can race this script's listener connecting.
task.spawn(function()
	local ok, snap = pcall(function() return remotes.GetInitialData:InvokeServer() end)
	if ok and typeof(snap) == "table" then applyCash(snap.Cash) end
end)

-- Bug C fix: DarrelState's startup pull returned nil once in Play testing --
-- pcall swallows a server-side "data not loaded yet" failure with no retry,
-- leaving GemPill stuck at the seed value ("0") for the rest of the session
-- unless a real balance change later fires DarrelUpdate (task-4-report.md).
-- Bounded retry: up to 3 attempts, 2s apart, bailing out the instant a value
-- lands here OR DarrelUpdate wins the race (darrelSeeded guards both).
task.spawn(function()
	for attempt = 1, 3 do
		if darrelSeeded then return end
		local ok, res = pcall(function() return remotes.DarrelState:InvokeServer() end)
		if darrelSeeded then return end
		if ok and typeof(res) == "table" and typeof(res.Darrels) == "number" then
			darrelSeeded = true
			applyDarrels(res.Darrels)
			return
		end
		if attempt < 3 then task.wait(2) end
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

-- Vertically centred BELOW the currency cluster's band, not across the
-- whole canvas: the cluster's pills occupy y 18-72, and with the rail now
-- sharing the left edge its column must clear them -- centring within
-- [96, canvas height] keeps the rail's top edge no higher than y 96.
local RAIL_TOP_CLEARANCE = 96
local RAIL_CENTER_Y = (RAIL_TOP_CLEARANCE + T.size.canvas.Y) / 2

local RAIL_ORDER = {
	{ id = "bag", label = "Bag" },
	{ id = "pass", label = "Pass" },
	{ id = "daily", label = "Daily" },
	{ id = "goals", label = "Goals" },
	{ id = "index", label = "Index" },
	{ id = "settings", label = "Settings" },
}

local rail = Instance.new("Frame")
rail.Name = "NavRail"
if RAIL_ON_LEFT then
	rail.AnchorPoint = Vector2.new(0, 0.5)
	rail.Position = UDim2.new(0, T.size.railInset, 0, RAIL_CENTER_Y)
else
	rail.AnchorPoint = Vector2.new(1, 0.5)
	rail.Position = UDim2.new(1, -T.size.railInset, 0, RAIL_CENTER_Y)
end
rail.Size = UDim2.fromOffset(T.size.railItem, 0)
rail.AutomaticSize = Enum.AutomaticSize.Y
rail.BackgroundTransparency = 1
rail.ZIndex = T.zindex.rail
rail.Parent = root

local railList = Instance.new("UIListLayout")
railList.FillDirection = Enum.FillDirection.Vertical
railList.HorizontalAlignment = Enum.HorizontalAlignment.Center
railList.SortOrder = Enum.SortOrder.LayoutOrder
railList.Padding = UDim.new(0, T.size.railGap)
railList.Parent = rail

for order, cfg in ipairs(RAIL_ORDER) do
	local item = Instance.new("Frame")
	item.Name = cfg.id .. "Item"
	item.LayoutOrder = order
	item.Size = UDim2.new(0, T.size.railItem, 0, 0)
	item.AutomaticSize = Enum.AutomaticSize.Y
	item.BackgroundTransparency = 1
	item.ZIndex = T.zindex.rail
	item.Parent = rail

	local itemScale = Instance.new("UIScale")
	itemScale.Parent = item

	-- v2: no button plate -- the icon floats directly on the item column,
	-- top-aligned; the label sits directly under it.
	local icon = UI.artSlot(item, UDim2.fromOffset(T.size.railIcon, T.size.railIcon), T.icons[cfg.id])
	icon.Name = "IconSlot"
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 0)
	icon.ZIndex = item.ZIndex + 2

	local label = UI.label(item, cfg.label, "railLabel", T.color.white)
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 0)
	-- 6px: kit's smallest spacing-scale step -- README 3.7 gives no explicit
	-- icon-label gap ("label directly under it").
	label.Position = UDim2.new(0.5, 0, 0, T.size.railIcon + 6)
	label.Size = UDim2.new(1, 0, 0, 26)
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

	railItems[cfg.id] = { frame = item, glow = glow, scale = itemScale }
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
local placeholderFrame = nil
local placeholderForId = nil

local function destroyPlaceholder()
	if placeholderFrame then
		placeholderFrame:Destroy()
		placeholderFrame = nil
		placeholderForId = nil
	end
end

local function buildPlaceholder(id)
	local screenName = ID_TO_SCREEN[id] or id
	local width = T.size.panelWidth[screenName] or 700
	local panel = UI.panel(host, UDim2.fromOffset(width, 566))
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
	if not currentPanelId then return end
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

	task.delay(T.tween.panelClose.Time, function()
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

task.spawn(function()
	-- Daily / Quests / Season each own a ScreenGui.
	retire(playerGui, "DailyUI")
	retire(playerGui, "QuestUI")
	retire(playerGui, "SeasonUI")
	-- IndexUI: expected NOT to exist as a separate ScreenGui in the current
	-- build (IndexClient parents into MainUI, like Backpack below) -- kept
	-- here per the brief in case a future rename reintroduces it; nil-guarded
	-- so its absence is silently skipped.
	retire(playerGui, "IndexUI")

	-- Backpack's panel/open-button are Frames inside MainUI, not their own
	-- ScreenGui (confirmed by reading BackpackClient) -- MainUI itself stays
	-- up (hotbar, cash pill host) and only these two Frames retire.
	local mainUI = playerGui:WaitForChild("MainUI", 5)
	if mainUI then
		retire(mainUI, "BackpackFrame")
		retire(mainUI, "BackpackOpen")
		retire(mainUI, "CashFrame")
	end

	retire(playerGui, "DarrelHUD")
end)
