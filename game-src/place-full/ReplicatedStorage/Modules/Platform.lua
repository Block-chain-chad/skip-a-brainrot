--!strict
-- Platform: the one place that answers "what device is this, and how big should
-- the UI be on it".
--
-- 2026-08-05. Before this module the game had NO platform detection anywhere:
-- TouchEnabled, GamepadEnabled, GetPlatform, LastInputType and
-- IsTenFootInterface returned zero hits across every script in the place. The
-- game rendered one desktop-shaped UI at every size, and 27 client scripts each
-- rolled their own scale maths. Two rival formulas had grown up:
--
--   fit-a-canvas     math.min(vp.X / 1350, vp.Y / 775)     GameHUD, Trade, Booth,
--                                                          EggShop, every UIKit panel
--   scale-by-height  math.clamp(vp.Y / 900, 0.8, 1.25)     UIStyle, SideRail
--
-- BOTH are kept, as Fit() and Height(), because they are not interchangeable --
-- a fixed-size panel has to fit the screen or it clips, whereas HUD furniture
-- only wants to track height. What changes is that both now run through one
-- per-device boost and one set of safe insets, so a phone gets chunkier UI and
-- a console gets TV-safe margins without any call site having to know that.
--
-- Usage from a client script:
--   local Platform = require(ReplicatedStorage.Modules.Platform)
--   Platform.Bind(canvasScale, 1350, 775)   -- keeps this UIScale correct forever
--   Platform.PrepareGui(screenGui)          -- notch / safe-area handling
--   Platform.Watch(function() layout() end) -- re-run on any device change
--
-- Bind/Watch fire immediately AND on every later change (rotation, window
-- resize, a controller being picked up mid-session), so callers never need
-- their own ViewportSize listener.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type Class = "Console" | "Phone" | "Tablet" | "Desktop"
export type Insets = { Top: number, Bottom: number, Left: number, Right: number }

local Platform = {}

-- Design canvas the UIKit panels are authored against (Tokens.size.canvas).
Platform.DESIGN_X = 1350
Platform.DESIGN_Y = 775

-- Per-class multiplier applied on top of the raw fit.
--   Phone   a 6" screen held at 30cm needs proportionally MUCH bigger controls
--           than a monitor; a straight fit makes text unreadable and buttons
--           smaller than a fingertip (Roblox's own guidance is a 44px minimum
--           touch target, which a 0.35 fit on a 1350-wide canvas will not hit).
--   Tablet  same argument, weaker.
--   Console rendered on a TV several metres away -- the "10-foot interface".
-- 2026-08-05 second pass, from a real handset screenshot: 1.34 was not enough.
-- Measured on a 750x361 phone at the old boost, the currency value rendered at
-- 13.6px and the luck chip at 15px -- unreadable at arm's length. The design
-- text is 22px, so the chrome layer needs ~0.79 to land near 17px. Raising the
-- boost alone would have made the furniture bigger too, which was ALREADY the
-- complaint, so it is paired with the footprint caps in GameHUDClient's rail
-- and ClientMain's tab bar: bigger text, smaller blocks.
local BOOST: { [string]: number } = {
	Desktop = 1.00,
	Tablet  = 1.12,
	Phone   = 1.70,
	Console = 1.20,
}

-- A phone is not "touch" -- a tablet is touch too. Split on the SHORT edge so
-- the answer does not flip when the device rotates.
local PHONE_SHORT_EDGE = 600

-- Consoles overscan: TVs clip the outer few percent of the signal. Everything
-- interactive has to stay inside the title-safe area.
local TV_SAFE = 0.035

-- Roblox's own touch controls sit bottom-left (thumbstick) and bottom-right
-- (jump). Reserve that band so game UI never lands underneath them.
local TOUCH_CONTROL_BAND = 140

-- THE CORNER SQUARES THOSE CONTROLS ACTUALLY OCCUPY (2026-08-26).
--
-- The band above is a full-width strip, and it is deliberately SHORTER than the
-- controls are tall -- 112px on a phone -- because spending 150px of a 390px
-- screen across its whole width is ruinous. That compromise is fine, but it left
-- the true corner geometry undefined, so every caller that needed it invented
-- its own number: HudToggleClient's jump clamp used 140, LuckHUDClient's chip
-- used 130, ScooterButtonClient stacked on constants copied from LuckHUD, and
-- the layout audit used 150. The layout therefore believed it had cleared a zone
-- the audit still reported as occupied, and neither was checkable against the
-- other -- which is how a sprint button that sits 59% under the jump control
-- survived several rounds of "fixing" the corner.
--
-- One definition. HudLayout keeps UI out of these squares; HudAudit reports UI
-- that lands in them. They cannot disagree any more.
local TOUCH_CORNER_PHONE = 150
local TOUCH_CORNER_TABLET = 190

----------------------------------------------------------------- state
local changed = Instance.new("BindableEvent")
Platform.Changed = changed.Event

Platform.Class = "Desktop" :: Class
Platform.IsDesktop = true
Platform.IsPhone = false
Platform.IsTablet = false
Platform.IsConsole = false
Platform.IsTouch = false
Platform.IsGamepad = false
Platform.Boost = 1
Platform.Viewport = Vector2.new(1280, 720)

-- Forces a device class regardless of what the hardware reports. Two uses:
-- testing a layout you are not holding, and working around Studio's device
-- simulator, whose emulated TouchEnabled / MouseEnabled / KeyboardEnabled
-- flags LATCH -- verified 2026-08-05, they read true for every device after
-- the first switch in a session, so the simulator alone cannot exercise these
-- paths.
--
-- Kept as an ATTRIBUTE on ReplicatedStorage rather than a field on this table,
-- because a module table is per-require: Studio's command bar gets its own
-- copy of this module, so setting a field there changed nothing for the
-- running HUD (that cost me a confusing test round). An attribute is one piece
-- of shared state every copy reads, and it can be flipped from the command bar
-- or straight from the Properties panel:
--   game.ReplicatedStorage:SetAttribute("PlatformOverride", "Phone")
-- Client-set attributes do not replicate, so this stays a local preview.
local OVERRIDE_ATTR = "PlatformOverride"
local VALID: { [string]: boolean } = { Console = true, Phone = true, Tablet = true, Desktop = true }

local function overrideClass(): Class?
	local v = ReplicatedStorage:GetAttribute(OVERRIDE_ATTR)
	return (typeof(v) == "string" and VALID[v]) and (v :: Class) or nil
end

-- VIEWPORT OVERRIDE (2026-08-26). The class override above lets a developer say
-- "pretend this is a phone", but it cannot say "pretend this screen is 844x390"
-- -- and SIZE is what the phone bugs are actually about. Studio's viewport stays
-- monitor-shaped whatever the device simulator claims, so every scale in this
-- module (Fit, FitPanel, Height, Widget, Budget) went on being evaluated against
-- ~1920x1080 while ostensibly testing a handset. A layout that overflows a
-- 390px-tall screen looks perfect under those conditions.
--
-- That is the reason phone regressions in this place have historically only been
-- found from player screenshots: there was no way to reproduce one at a desk.
-- With this, an audit can walk real device sizes without leaving Edit mode:
--   game.ReplicatedStorage:SetAttribute("ViewportOverride", Vector2.new(844, 390))
--   game.ReplicatedStorage:SetAttribute("ViewportOverride", nil)   -- back to real
--
-- Client-set attributes do not replicate, so this stays a local preview, exactly
-- like PlatformOverride.
local VIEWPORT_ATTR = "ViewportOverride"

local function overrideViewport(): Vector2?
	local v = ReplicatedStorage:GetAttribute(VIEWPORT_ATTR)
	if typeof(v) == "Vector2" and v.X > 1 and v.Y > 1 then return v end
	return nil
end

local function viewport(): Vector2
	local forced = overrideViewport()
	if forced then return forced end
	local cam = Workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	-- ViewportSize reads (1, 1) for a frame or two during boot; trusting it then
	-- produces a scale of ~0.001 and a HUD that never recovers, because most
	-- call sites only compute once.
	if not vp or vp.X <= 1 or vp.Y <= 1 then return Vector2.new(1280, 720) end
	return vp
end

local function classify(vp: Vector2): Class
	local forced = overrideClass()
	if forced then return forced end
	-- A FAKED SIZE IMPLIES ITS DEVICE. Without this, setting ViewportOverride to a
	-- handset size on a dev machine still classified Desktop, so Boost stayed 1.0,
	-- IsTouch stayed false and Insets().Bottom collapsed to 0 -- i.e. the preview
	-- reported a 667x375 screen while exercising every desktop code path, which is
	-- the same trap PlatformOverride's own note describes. Size and class move
	-- together unless a class was asked for explicitly.
	if overrideViewport() then
		if math.min(vp.X, vp.Y) < PHONE_SHORT_EDGE then return "Phone" end
		if math.min(vp.X, vp.Y) < 900 then return "Tablet" end
		return "Desktop"
	end
	if GuiService:IsTenFootInterface() then return "Console" end
	-- STUDIO DEVICE SIMULATOR (2026-08-18). The sim LATCHES its input flags --
	-- it reports TouchEnabled AND MouseEnabled AND KeyboardEnabled together --
	-- so the strict rule below always fell through to Desktop and the phone
	-- layout could never be seen without the PlatformOverride attribute. Every
	-- phone bug this project shipped was invisible for exactly that reason.
	--
	-- In STUDIO ONLY, trust touch + the viewport instead: a live client never
	-- takes this branch, so real players keep the strict classification below
	-- unchanged. This is a test-surface fix, not a behaviour change.
	if RunService:IsStudio() and UserInputService.TouchEnabled then
		return (math.min(vp.X, vp.Y) < PHONE_SHORT_EDGE) and "Phone" or "Tablet"
	end
	-- Touch alone is not enough: a laptop with a touchscreen and a Windows
	-- tablet both report TouchEnabled but are desktop-shaped. A real handset
	-- has NEITHER a mouse nor a keyboard, so require both to be absent rather
	-- than leaning on one flag -- MouseEnabled is the more reliable of the two
	-- in practice, and needing both means a single wrong reading cannot
	-- misclassify the device on its own.
	local uis = UserInputService
	if uis.TouchEnabled and not (uis.MouseEnabled and uis.KeyboardEnabled) then
		return (math.min(vp.X, vp.Y) < PHONE_SHORT_EDGE) and "Phone" or "Tablet"
	end
	return "Desktop"
end

local function refresh(): boolean
	local vp = viewport()
	local class = classify(vp)
	local dirty = (class ~= Platform.Class) or (vp ~= Platform.Viewport)
		or (UserInputService.GamepadEnabled ~= Platform.IsGamepad)
	Platform.Viewport = vp
	Platform.Class = class
	Platform.IsConsole = class == "Console"
	Platform.IsPhone = class == "Phone"
	Platform.IsTablet = class == "Tablet"
	Platform.IsDesktop = class == "Desktop"
	-- AN EXPLICIT OVERRIDE MUST IMPLY TOUCH.
	-- IsTouch used to read TouchEnabled alone, so setting
	-- PlatformOverride = "Phone" on a dev machine gave IsPhone = true but
	-- IsTouch = FALSE -- there is no touchscreen. Every `if Platform.IsTouch`
	-- branch was therefore skipped while ostensibly testing a phone: the
	-- long-press card tooltips, EggShop's tapMode, Builders' TOUCH_ONLY press
	-- feedback, and (measured) Insets().Bottom collapsing to 0 instead of the
	-- 140px TOUCH_CONTROL_BAND, so nothing was held clear of the thumbstick.
	-- The override reported a phone and quietly tested the desktop paths.
	--
	-- Forced only when the class was ASKED FOR, so live clients are unchanged:
	-- with no override this is the original expression exactly.
	local forcedClass = overrideClass()
	if forcedClass ~= nil then
		Platform.IsTouch = (forcedClass == "Phone" or forcedClass == "Tablet")
	elseif overrideViewport() ~= nil then
		-- Same reasoning as the class implication in classify(): a faked handset
		-- size that leaves IsTouch false silently tests the desktop branches.
		Platform.IsTouch = (class == "Phone" or class == "Tablet")
	else
		Platform.IsTouch = UserInputService.TouchEnabled and not Platform.IsDesktop
	end
	Platform.IsGamepad = UserInputService.GamepadEnabled
	Platform.Boost = BOOST[class] or 1
	return dirty
end

----------------------------------------------------------------- scale
-- Fit a fixed design canvas inside the viewport. DELIBERATELY UNBOOSTED.
--
-- A fit is already the largest scale at which the canvas fits, so multiplying
-- it by anything above 1 overflows the screen by exactly that factor -- and no
-- clamp rescues it. Measured while building this: a 1350x775 canvas on a
-- 414x896 phone fits at 0.307; the 1.34 phone boost took it to 0.411, which
-- renders 555px of canvas across 414px of screen. The device boost therefore
-- lives on Height() and FitPanel(), neither of which can overflow.
--
-- Desktop behaviour is byte-identical to the formula this replaced.
function Platform.Fit(designX: number?, designY: number?): number
	local vp = Platform.Viewport
	local dx = designX or Platform.DESIGN_X
	local dy = designY or Platform.DESIGN_Y
	return math.clamp(math.min(vp.X / dx, vp.Y / dy), 0.2, 1.7)
end

-- Fit a PANEL rather than the whole canvas, so a fixed-size modal fills a small
-- screen instead of floating in the middle of it at postage-stamp size.
--
-- This is the change that actually makes phones playable. Panels are authored
-- 800-960 wide inside a 1350-wide canvas, so fitting the canvas spends ~30% of
-- the width on empty gutters -- affordable on a 1920 monitor, not on a 414px
-- handset. Fitting the panel's own box recovers it: on a 896x414 phone the
-- 960x684 backpack panel goes from 0.307 to 0.571, i.e. 1.9x bigger.
--
-- Never returns less than Fit(), so no caller shrinks by adopting it, and
-- desktop is pinned to the canvas fit so monitors keep exactly today's look.
function Platform.FitPanel(panelW: number, panelH: number, margin: number?): number
	local vp = Platform.Viewport
	local m = margin or 0.06
	local canvas = Platform.Fit()
	if Platform.IsDesktop then return canvas end
	local fit = math.min(vp.X / (panelW * (1 + m * 2)), vp.Y / (panelH * (1 + m * 2)))
	return math.clamp(math.max(fit, canvas), 0.2, 1.7)
end

-- The scale-by-height family (UIStyle / SideRail). Same defaults they shipped
-- with, so desktop is pixel-identical; the boost only moves phone and console.
function Platform.Height(base: number?, minScale: number?, maxScale: number?): number
	local b = base or 900
	local lo = minScale or 0.8
	local hi = maxScale or 1.25
	-- Floors matter more than the boost here. A 414-tall phone lands on the
	-- 0.8 floor either way, which is the SAME furniture size a 720p desktop
	-- gets -- so a HUD button ends up 38px on a handset, under Roblox's 44px
	-- minimum touch target. Raising the floor is what actually makes it
	-- thumb-sized; the boost only does useful work on taller screens.
	-- ...but a FLAT floor is the wrong shape for that argument (2026-08-24).
	-- 1.0 said "never smaller than the full desktop design size" on a device that
	-- may only have 430px of height in total, so this family stopped tracking the
	-- viewport at all below ~530px: a 600x420 UIStyle panel drew 420px tall on a
	-- 430px screen. That is the "pop ups cover the whole screen" report, and the
	-- floor was causing it -- the raw formula had already asked for 0.81 and been
	-- overruled. The floor still exists, because small furniture does have to stay
	-- thumb-sized, but it now tracks the screen: it can only hold a widget UP on a
	-- device that has the room to hold it up.
	if Platform.IsPhone then
		lo = math.max(lo, math.clamp(Platform.Viewport.Y / 520, 0.72, 1.0))
		hi = math.max(hi, 1.35)
	end
	if Platform.IsTablet then lo = math.max(lo, 0.9) end
	if Platform.IsConsole then lo, hi = math.max(lo, 1.0), math.max(hi, 1.45) end
	return math.clamp((Platform.Viewport.Y / b) * Platform.Boost, lo, hi)
end

-- Scale for EDGE-ANCHORED HUD furniture (currency pills, nav rail, toggles) as
-- opposed to a centred fixed canvas. Boosting is safe here precisely because
-- there is no canvas to overflow: the layer is re-sized to the viewport every
-- pass, so a bigger scale just means chunkier furniture hugging the same edges.
-- Desktop boost is 1.0, so desktop is unchanged.
function Platform.Chrome(designX: number?, designY: number?): number
	return math.clamp(Platform.Fit(designX, designY) * Platform.Boost, 0.2, 1.9)
end

-- BLOCK SCALE: geometry only, deliberately UNBOOSTED (2026-08-27).
--
-- Chrome() above multiplies the fit by the device boost, and on a phone that
-- boost is 1.70 -- which very nearly cancels the smaller fit. Measured on a real
-- handset reporting 867x399:
--
--   Desktop 1920x1080   Fit 1.394   Chrome 1.394
--   Phone    867x399    Fit 0.515   Chrome 0.875
--
-- The screen lost 63% of its height and the chrome only shrank by 37%, so every
-- block in it took roughly twice the share of the screen it takes on a monitor.
-- A 6-tile nav rail that costs 72% of a desktop's usable height wanted 202% of a
-- phone's. That is the whole of "the GUI doesn't adjust to the size of the
-- screen" -- the boost was never wrong about TEXT, it was applied to everything.
--
-- The boost exists for a real reason (a 22px design label renders 11px at a raw
-- phone fit, which is the unreadability this module's own notes were fixing), so
-- it is kept -- for TYPE. Blocks get this instead: the honest fit, plus a small
-- comfort margin so touch targets stay reachable. Pair it with
-- HudLayout.CompensateType so glyphs keep their Chrome()-sized rendering while
-- the boxes around them shrink. Desktop is unchanged: boost is 1.0 there and
-- this returns exactly Fit().
function Platform.Block(designX: number?, designY: number?): number
	local f = Platform.Fit(designX, designY)
	local comfort = 1
	if Platform.IsPhone then comfort = 1.15
	elseif Platform.IsTablet then comfort = 1.05
	elseif Platform.IsConsole then comfort = 1.10 end
	return math.clamp(f * comfort, 0.2, 1.9)
end

-- How much bigger type has to be authored so that, once Block() has scaled the
-- layer, glyphs still land at the size Chrome() would have produced. 1.0 on
-- desktop. Feed this to HudLayout.CompensateType.
function Platform.TypeCompensation(designX: number?, designY: number?): number
	local b = Platform.Block(designX, designY)
	if b <= 0.001 then return 1 end
	return Platform.Chrome(designX, designY) / b
end

-- Scale for a legacy HUD widget that was authored at fixed px with NO viewport
-- fit at all -- the quest tracker is the worst offender at 286x216 design px,
-- which is 38% x 60% of a 750x361 phone screen before anything else is drawn.
-- 1.0 on desktop, so those widgets are untouched there.
-- 2026-08-24: PROPORTIONAL, NOT A PER-CLASS CONSTANT. This was the one scale in
-- the module that ignored the viewport completely -- every phone got 0.70 whether
-- it reported 667x307 or 1280x590 -- so the quest tracker's 286x216 design box
-- took 49% of the height on the small one and 26% on the large one. A widget
-- wants a fixed SHARE of the screen, and tracking the canvas height is what gives
-- it one. Tuned so a 430px-tall handset still lands on ~0.70: the device this
-- constant was originally measured against does not move.
function Platform.Widget(): number
	local h = Platform.Viewport.Y / Platform.DESIGN_Y
	if Platform.IsPhone then return math.clamp(h * 1.25, 0.42, 0.78) end
	if Platform.IsTablet then return math.clamp(h * 1.10, 0.60, 0.95) end
	if Platform.IsConsole then return 1.15 end
	return 1
end

-- THE SCREEN-FRACTION PRIMITIVE. "This box is designW x designH in design px and
-- may occupy at most fracW of the screen's width and fracH of its height -- what
-- scale does that allow?"
--
-- Every footprint cap in this game was written inline as its own copy of this
-- arithmetic against its own hand-picked pair of fractions, which is how they
-- drifted far enough apart to sum past 100% of a handset screen. New call sites
-- should ask here instead of growing a seventh copy.
--
-- `chain` is the scale the box ALREADY wears from enclosing UIScales (design px
-- -> screen px); pass 1 if there is none. Only ever returns <= 1: a budget is a
-- ceiling, never a licence to grow.
function Platform.Budget(designW: number, designH: number, fracW: number, fracH: number, chain: number?): number
	local vp = Platform.Viewport
	local c = math.max(chain or 1, 0.001)
	local w = (designW > 0) and ((vp.X * fracW / c) / designW) or 1
	local h = (designH > 0) and ((vp.Y * fracH / c) / designH) or 1
	return math.clamp(math.min(w, h, 1), 0.05, 1)
end

-- A phone short enough that the bottom-right column CANNOT HOLD THREE CONTROLS.
--
-- Not a taste threshold -- arithmetic. That column runs from the topbar to the
-- jump button, i.e. vp.Y - Insets().Top - TouchCorner(). On the owner's 700x310
-- handset that is 134px, and three controls at Roblox's 44px touch floor need
-- 44*3 + two gaps + the edge pad = 160 at the very tightest. Something has to
-- leave the column, and no amount of shrinking fixes it without going under the
-- touch floor -- which is the one thing that must not give.
--
-- 340 is the cutoff because the shortest screen where three DO fit is ~360
-- (measured: 165px of band against 160px of need, with 5px to spare).
function Platform.IsShortPhone(): boolean
	return Platform.IsPhone and Platform.Viewport.Y < 340
end

-- Landscape is height-poor and width-rich; portrait is the reverse. Layouts that
-- have to pick a shape from that were reading the viewport directly to do it.
function Platform.IsLandscape(): boolean
	return Platform.Viewport.X >= Platform.Viewport.Y
end

-- Side, in px, of the square each core touch control claims in its bottom
-- corner. 0 when there are no touch controls. See the note by the constants.
function Platform.TouchCorner(): number
	if not Platform.IsTouch then return 0 end
	local base = Platform.IsPhone and TOUCH_CORNER_PHONE or TOUCH_CORNER_TABLET
	-- PROPORTIONAL, because Roblox's own controls are (2026-08-27).
	--
	-- A flat 150px reserve is 38% of a 399px-tall handset and 42% of a 360px one --
	-- and the engine does not draw a 150px jump button on a small screen, it scales
	-- its controls with the display like everything else. Reserving the same
	-- absolute band on every device therefore takes the most space exactly where
	-- there is least: measured at 800x360, three stacked 44px controls needed 164px
	-- of a 152px band and the corner had eaten the difference.
	--
	-- Clamped either side of the measured base so this stays a correction to it
	-- rather than a new guess -- it cannot collapse to nothing on a tiny viewport
	-- or run away on a tall one.
	return math.clamp(Platform.Viewport.Y * 0.38, base * 0.72, base * 1.12)
end

-- The two corner rects, in the same space Insets() describes: measured from the
-- bottom-left and bottom-right of the usable screen area.
-- Returns { { name, x, y, w, h }, ... } relative to a box of the given size.
function Platform.TouchControlRects(boxW: number, boxH: number)
	local side = Platform.TouchCorner()
	if side <= 0 then return {} end
	return {
		{ name = "thumbstick", x = 0, y = boxH - side, w = side, h = side },
		{ name = "jump", x = boxW - side, y = boxH - side, w = side, h = side },
	}
end

----------------------------------------------------------------- safe area
-- Pixels that game UI must stay clear of on each edge: the Roblox topbar, TV
-- overscan on console, and the band the touch thumbstick / jump button occupy.
function Platform.Insets(): Insets
	local topLeft, bottomRight = GuiService:GetGuiInset()
	local vp = Platform.Viewport
	local i: Insets = {
		Top = topLeft.Y,
		Left = topLeft.X,
		Bottom = bottomRight.Y,
		Right = bottomRight.X,
	}
	if Platform.IsConsole then
		i.Top += vp.Y * TV_SAFE
		i.Bottom += vp.Y * TV_SAFE
		i.Left += vp.X * TV_SAFE
		i.Right += vp.X * TV_SAFE
	elseif Platform.IsTouch then
		i.Bottom = math.max(i.Bottom, TOUCH_CONTROL_BAND * (Platform.IsPhone and 0.8 or 1))
	end
	return i
end

-- Notch / rounded-corner handling is the engine's job; it just has to be asked.
-- Every ScreenGui in this place was left on the default, so on a notched phone
-- the HUD ran underneath the cutout.
function Platform.PrepareGui(gui: ScreenGui, ignoreTopbar: boolean?)
	pcall(function()
		gui.ScreenInsets = ignoreTopbar and Enum.ScreenInsets.DeviceSafeInsets
			or Enum.ScreenInsets.CoreUISafeInsets
	end)
end

function Platform.SetOverride(class: Class?)
	ReplicatedStorage:SetAttribute(OVERRIDE_ATTR, class)
end

function Platform.GetOverride(): Class?
	return overrideClass()
end

-- Pretend the screen is a given size. Pass nil to return to the real viewport.
-- Setting a size also implies its device class unless one was asked for
-- explicitly, so a caller does not have to set both to get a coherent preview.
function Platform.SetViewportOverride(size: Vector2?)
	ReplicatedStorage:SetAttribute(VIEWPORT_ATTR, size)
end

function Platform.GetViewportOverride(): Vector2?
	return overrideViewport()
end

-- Reference sizes for the devices this game actually ships to, in landscape.
-- Taken from the handsets that appear in the place's own bug screenshots.
-- NOTE ON UNITS. Roblox reports ViewportSize in DEVICE-INDEPENDENT units on
-- mobile, not raw pixels. A handset whose screenshot is 2600x1196 reports about
-- 867x399 (a 3x scale factor). Sizing intuitions taken from a screenshot's pixel
-- dimensions are therefore off by that factor, and a HUD that looks reasonable
-- at "2600 wide" is being drawn on a canvas a third of that. Every entry here is
-- in the units the engine actually reports.
Platform.TEST_SIZES = {
	-- SHORTEST FIRST, and this one is the reference device (2026-08-26).
	--
	-- Back-computed from an owner screenshot: the HIDE UI pill is authored 112 wide
	-- (HudLayout.ChipWidth on a phone) and measured 320px across a 1999px-wide
	-- capture, so that handset reports about 700x310 -- FIFTY pixels shorter than
	-- the shortest entry this list had. Every budget in the game was therefore tuned
	-- against a screen taller than the one the bug reports come from, and the
	-- bottom-right column wanting 160px of a 134px band could audit clean on all six
	-- older profiles while visibly overflowing in the capture.
	--
	-- A device list is only as good as its worst entry. Add shorter ones here before
	-- tuning anything against them.
	{ name = "Phone short",  size = Vector2.new(700, 310) },   -- owner capture, 1999x886 @2.857
	{ name = "Phone small",  size = Vector2.new(667, 375) },   -- iPhone SE
	{ name = "Phone hidpi",  size = Vector2.new(867, 399) },   -- measured from a real player screenshot (2600x1196 @3x)
	{ name = "Phone tall",   size = Vector2.new(844, 390) },   -- iPhone 14
	{ name = "Phone wide",   size = Vector2.new(956, 440) },   -- iPhone 15 Pro Max
	{ name = "Phone budget", size = Vector2.new(800, 360) },   -- common Android
	-- PORTRAIT. Added 2026-09-17, and until then this list was ENTIRELY LANDSCAPE:
	-- every profile above is wider than it is tall.
	--
	-- StarterGui.ScreenOrientation is Sensor (the engine default -- no script in
	-- the place has ever set it), so a player holding the phone upright GETS
	-- portrait, and nothing had ever measured one. The consequence showed up the
	-- moment these entries existed: the 1350x775 design canvas is fitted on its
	-- WIDTH in portrait, so it collapses to 390x223 on a 390x844 screen and every
	-- HUD panel rides it down to about a quarter of the screen's height.
	--
	-- An axis a device list never covers is worse than a size it never covers,
	-- because every footprint budget in this game is written "height is the scarce
	-- axis" -- which is true only in landscape.
	{ name = "Phone portrait small", size = Vector2.new(375, 667) },  -- iPhone SE upright
	{ name = "Phone portrait",       size = Vector2.new(390, 844) },  -- iPhone 14 upright
	{ name = "Phone portrait max",   size = Vector2.new(430, 932) },  -- iPhone 15 Pro Max upright
	{ name = "Tablet",       size = Vector2.new(1180, 820) },  -- iPad Air
	{ name = "Tablet 4:3",   size = Vector2.new(1024, 768) },  -- iPad landscape
	{ name = "Tablet portrait", size = Vector2.new(768, 1024) },
	-- LAPTOPS, with an EXPLICIT class. The implied-class rule in classify() splits
	-- on the SHORT edge, and a 1366x768 laptop's short edge is 768 -- the same as
	-- an iPad's. Under a preview it would be audited as a Tablet (touch insets,
	-- 1.12 boost) when a real one is plainly a Desktop. Live clients are
	-- unaffected: with no override, classify() never reaches the implied branch.
	{ name = "Laptop 720p",  size = Vector2.new(1280, 720),  class = "Desktop" },
	{ name = "Laptop 768p",  size = Vector2.new(1366, 768),  class = "Desktop" },
	{ name = "Desktop",      size = Vector2.new(1920, 1080) },
}

----------------------------------------------------------------- binding
-- Call fn now and on every device change. Returns a disconnect function.
function Platform.Watch(fn: (Class) -> ()): () -> ()
	local conn = changed.Event:Connect(function()
		fn(Platform.Class)
	end)
	fn(Platform.Class)
	return function() conn:Disconnect() end
end

-- Keep a UIScale tracking the fit-a-canvas formula for as long as it exists.
function Platform.Bind(scale: UIScale, designX: number?, designY: number?): () -> ()
	return Platform.Watch(function()
		if scale.Parent then scale.Scale = Platform.Fit(designX, designY) end
	end)
end

-- Same, for the scale-by-height family.
function Platform.BindHeight(scale: UIScale, base: number?, lo: number?, hi: number?): () -> ()
	return Platform.Watch(function()
		if scale.Parent then scale.Scale = Platform.Height(base, lo, hi) end
	end)
end

----------------------------------------------------------------- wiring
refresh()

if RunService:IsClient() then
	local function poke()
		if refresh() then changed:Fire() end
	end
	local function hookCamera()
		local cam = Workspace.CurrentCamera
		if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(poke) end
	end
	hookCamera()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		hookCamera()
		poke()
	end)
	ReplicatedStorage:GetAttributeChangedSignal(OVERRIDE_ATTR):Connect(function()
		refresh()
		changed:Fire()   -- always re-fire: an override is an explicit request
	end)
	ReplicatedStorage:GetAttributeChangedSignal(VIEWPORT_ATTR):Connect(function()
		refresh()
		changed:Fire()
	end)
	UserInputService.LastInputTypeChanged:Connect(poke)
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(poke)
	UserInputService:GetPropertyChangedSignal("KeyboardEnabled"):Connect(poke)
	UserInputService:GetPropertyChangedSignal("GamepadEnabled"):Connect(poke)
	-- ViewportSize can still be (1,1) on the first frame even after the camera
	-- exists, and a fixed window never fires the changed signal again -- so take
	-- one late reading the way GameHUDClient's own `task.delay(1, fit)` does.
	task.delay(1, poke)
	task.delay(3, poke)
end

return Platform
