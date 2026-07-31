-- WheelClient: the daily spin wheel.
--
-- Walk into the ring by the wheel and the full-screen wheel comes up on its own; walk
-- away and it goes. The physical wheel in the world spins in step with it, so bystanders
-- see it turn too.
--
-- This script decides NOTHING. The server rolls, pays out, and broadcasts which slot won;
-- every client animates to that slot locally. A laggy client cannot stall anyone else.
--
-- The wedges are drawn, not an image asset: a fan of thin bars inside a circular mask (a
-- square Frame with a 0.5 UICorner and ClipsDescendants), which clips their square ends
-- to a clean circle. Note GuiObject.Rotation pivots about an object's CENTRE, not its
-- AnchorPoint -- so every radial piece is centred at half its length along its own ray.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local WheelConfig = require(ReplicatedStorage.Modules.WheelConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local SideRail = require(ReplicatedStorage.Modules.SideRail)
local SoundKit = require(ReplicatedStorage.Modules.SoundKit)

local spunRemote  = remotes:WaitForChild("WheelSpun")
local stateRemote = remotes:WaitForChild("WheelState")
local spinRemote  = remotes:WaitForChild("WheelSpin")

local SLOTS = WheelConfig.SLOTS
local N = #SLOTS
local SEG = 360 / N

local WHEEL_PX   = 700
local R          = WHEEL_PX / 2
-- Raised from 560. Everything sized in RAW PIXELS against the disc -- the bezel
-- ring, the hub, the pointer, and the per-wedge label width/text caps -- goes
-- through wk(), so a bigger WHEEL_PX scales the whole wheel uniformly instead of
-- leaving a 560px-tuned hub and pointer marooned in the middle of a wider disc.
-- Radial POSITIONS already derive from R, so those follow on their own.
local WHEEL_K    = WHEEL_PX / 560
local function wk(px) return math.floor(px * WHEEL_K + 0.5) end
local WINDUP_T   = 0.55
local WINDUP_DEG = 22
local SPIN_T     = 7.5    -- tuned longer for a more decisive settle-and-pop feel (Task 3)
local SPIN_T_FAST = 2.6   -- Fast Spin comfort setting -- see fastSpin below
local TURNS      = 9
-- Raised from 0.055. The gap is now the FLOOR ON CLICK LENGTH, not just a rate
-- cap: below the sample's own duration each click is cut off and retriggered,
-- which buzzes instead of ticking. 0.085 > the 0.097s tap's audible body and
-- still runs ~12 clicks/sec, which is plenty fast for a wheel.
local TICK_GAP   = 0.085
local TOAST_HOLD = 5.0

local NEAR, FAR  = 15, 21     -- hysteresis: open inside NEAR, close outside FAR

local INK = UITheme.Candy.ink

local function new(cls, props, parent)
	local o = Instance.new(cls)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

-- heavy black outline on everything, which is what makes the reference readable
local function stroke(o, thickness)
	new("UIStroke", {
		Color = INK, Thickness = thickness or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, o)
	return o
end

--=================================== shell =================================--
-- Task 4 fix: IgnoreGuiInset was true so Title/Close could "use the full
-- screen", but measured live it did the opposite -- this build's real
-- GuiInset is 58px (not the classic 36), and AbsolutePosition under
-- IgnoreGuiInset=true is reported NET of that inset, so Root rendered at
-- AbsolutePosition (0,-58): reaching UP INTO the real topbar and MainUI's
-- cash-pill/tab-bar band instead of clearing it (confirmed via
-- GuiService:GetGuiInset() and a live screenshot -- Title and Close were
-- genuinely overlapping that HUD, not just off by a few px). false matches
-- the convention MainUI/QuestTrackerUI already use and removes the need to
-- hand-correct every position by the inset. Costs ~58px of height, which
-- was never safely usable anyway. See TOP_MARGIN / Cluster below.
local gui = new("ScreenGui", {
	Name = "WheelUI", ResetOnSpawn = false, DisplayOrder = 12,
	IgnoreGuiInset = false, Enabled = true,
}, player:WaitForChild("PlayerGui"))

local root = new("Frame", {
	Name = "Root", BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1), Visible = false,
}, gui)
SideRail.registerPanel(root)   -- single-open: the wheel and rail panels close one another

-- Dim the world behind the wheel. Without it the saturated wedges compete with grass,
-- trees and the rest of the HUD and the whole thing reads as noise.
new("Frame", {
	Name = "Scrim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 0, Active = true,
}, root)

-- Task 4: Title/Holder/SpinBtn/Sub used to be positioned independently --
-- Title and Holder centred on ROOT's own 50%/50%, SpinBtn/Sub anchored to
-- root's BOTTOM edge. That fell apart once IgnoreGuiInset's real behaviour
-- was measured (see the ScreenGui comment above): Title collided with
-- MainUI's teleport-tab bar, and nothing guaranteed the button/sub-label had
-- room below the wheel on a short viewport. Cluster holds all four as one
-- group, stacked top-down, with a single UIScale that shrinks the WHOLE
-- group (never grows past 1x) to fit between TOP_MARGIN and the bottom of
-- the screen -- verified live at multiple viewport sizes (see the Task 4
-- report).
local TOP_MARGIN = 100          -- clears the real topbar + MainUI's cash pill / tab bar
-- Clears MainUI's BAG-open and Sprint buttons AND Roblox's own default Tool
-- hotbar (the numbered slots showing held brainrots) -- found live: none of
-- these are suppressed while the wheel is open, and an early pass let
-- DetailsPanel's "below" mode reach the true bottom edge of the screen and
-- sit on top of the numbered slots. The native hotbar isn't readable from a
-- script (it lives in protected CoreGui, not PlayerGui), so this is a
-- measured-by-eye reserve, not a queried one.
local BOTTOM_HUD_RESERVE = 90
-- Deeper reserve for DetailsPanel's below-mode ONLY: LuckHUDClient parks its
-- luck chip at Position (1,-14,1,-78) with size 128x34, so the chip's top
-- edge sits ~112px above the bottom of the screen -- taller than the 90px
-- BOTTOM_HUD_RESERVE band. 128 clears the chip with margin.
local DETAILS_BOTTOM_RESERVE = 128
local TITLE_H, SPIN_H, SUB_H = 56, 64, 28
local GAP_TITLE, GAP_SPIN, GAP_SUB = 8, 14, 8
local CLUSTER_H = TITLE_H + GAP_TITLE + WHEEL_PX + GAP_SPIN + SPIN_H + GAP_SUB + SUB_H
-- The fit used to be hard-capped at 1x ("never grows past 1x"), which left the
-- wheel smaller than a tall monitor could comfortably hold. Allow a modest
-- upscale instead -- still capped, because UIScale magnifies the ink strokes
-- along with everything else and past ~1.2 they start to read heavy.
local MAX_SCALE = 1.2
-- Reserved below the cluster for DetailsPanel's "collapse below the wheel"
-- mode (see layoutDetails). Found live: without this, the cluster's own
-- shrink-to-fit filled the ENTIRE available band at 1380x793, leaving
-- DetailsPanel a negative height in below-mode -- Roblox happily accepts a
-- negative Size.Y and the panel just silently misrenders. Reserving this
-- up front, even on viewports where the panel ends up beside the wheel
-- instead (where it goes unused), is simpler and safer than making Cluster's
-- own fit depend on DetailsPanel's beside/below decision.
local DETAILS_BELOW_RESERVE = 110

local cluster = new("Frame", {
	Name = "Cluster", BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, TOP_MARGIN),
	Size = UDim2.fromOffset(WHEEL_PX + 160, CLUSTER_H),
}, root)
local clusterScale = new("UIScale", { Scale = 1 }, cluster)

-- No backdrop panel here. An earlier version of this file added a big opaque
-- CandyPanel behind Holder to give the wheel a card to sit on -- it broke the
-- wheel instead: WheelUI.ZIndexBehavior is GLOBAL (every descendant sorts by
-- its own ZIndex across the WHOLE tree; hierarchy does not matter), Bezel,
-- Mask and all 240+ wedge bars sit at ZIndex 1, and the opaque panel at
-- ZIndex 2 painted over every one of them -- the wheel rendered as a blank
-- white slab with only the Z>=10 chrome (hub, pointer, title, chips) visible
-- on top. The reference has no card behind the wheel either: it floats on
-- the dimmed Scrim (above), and the candy identity reads through the rim,
-- title, buttons and chips instead.
--
-- CHECK ANY NEW OPAQUE ELEMENT'S ZINDEX AGAINST GLOBAL SORTING BEFORE ADDING
-- IT. Anything opaque at ZIndex >= 2 silently buries part of the wheel, with
-- no error to catch it -- verify with a live screenshot, not just a read.
local holder = new("Frame", {
	Name = "Holder", BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, TITLE_H + GAP_TITLE),
	Size = UDim2.fromOffset(WHEEL_PX, WHEEL_PX),
}, cluster)
local holderScale = new("UIScale", { Scale = 1 }, holder)

-- Scales the whole cluster down (never up past 1x) to fit between the real
-- topbar/MainUI HUD band (TOP_MARGIN) and the bottom of the screen. UIScale
-- scales around the object's own Position/AnchorPoint reference point --
-- Cluster's AnchorPoint is (0.5, 0), top-centre, so shrinking narrows and
-- shortens it without ever moving its top edge.
-- These two live up here rather than down beside layoutDetails because
-- layoutCluster now needs them, and a local declared LATER in the same scope is
-- not captured as an upvalue -- it silently resolves as a nil global.
local DETAILS_W = 250
local RIGHT_HUD_RESERVE = 264   -- tracker band is 238 wide; effective clearance (reserve - 24) must exceed it

-- Set by layoutCluster, obeyed by layoutDetails. The two MUST agree: if
-- layoutCluster gives away DETAILS_BELOW_RESERVE for a below-panel and
-- layoutDetails then puts the panel beside, the wheel is needlessly small; the
-- other way round hands the panel a negative height (see the reserve's comment).
-- So the call is made once, here, and layoutDetails does not re-derive it.
local detailsBelow = false

local function besideFitsAt(scale)
	local vw = root.AbsoluteSize.X
	local wheelHalf = (WHEEL_PX + wk(54)) * 0.5 * scale
	return (vw - (vw / 2 + wheelHalf + 24 + DETAILS_W)) >= RIGHT_HUD_RESERVE - 24
end

local function layoutCluster()
	-- DETAILS_BELOW_RESERVE is only ever USED when the panel collapses below the
	-- wheel, but it used to be subtracted unconditionally -- so on a wide desktop,
	-- where the panel sits BESIDE the wheel, 110px of height was reserved for
	-- nothing and the disc shrank to pay for it. On a 717px-tall window that one
	-- reserve was costing about a third of the wheel. Try the no-reserve fit first
	-- and only fall back when the panel demonstrably cannot fit beside.
	local function fitFor(reserve)
		local avail = math.max(1, root.AbsoluteSize.Y - TOP_MARGIN - BOTTOM_HUD_RESERVE - reserve)
		return math.min(MAX_SCALE, avail / CLUSTER_H), avail
	end
	local scale, available = fitFor(0)
	detailsBelow = not besideFitsAt(scale)
	if detailsBelow then
		scale, available = fitFor(DETAILS_BELOW_RESERVE)
	end
	clusterScale.Scale = scale
	local extra = math.max(0, available - CLUSTER_H * scale)
	cluster.Position = UDim2.new(0.5, 0, 0, TOP_MARGIN + extra / 2)
end
layoutCluster()
root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutCluster)

-- Chunky candy rim: gradient + ink stroke directly on this Bezel, which was
-- already correctly placed in the hierarchy (unlike the removed CandyPanel
-- above). Left at its original implicit ZIndex (1, tied with Mask) -- that
-- pairing already worked before any of this restyle, so it is untouched.
-- NOT UITheme.candyPanel: that helper's M.corner call would overwrite the
-- UDim.new(0.5, 0) corner below with a small pixel radius and turn this ring
-- into a rounded square.
local bezel = new("Frame", {
	Name = "Bezel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(WHEEL_PX + wk(54), WHEEL_PX + wk(54)),
	BackgroundColor3 = UITheme.Candy.panelTop, BorderSizePixel = 0,
}, holder)
new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, bezel)
new("UIStroke", {
	Color = UITheme.Candy.ink, Thickness = UITheme.Candy.stroke,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border, LineJoinMode = Enum.LineJoinMode.Round,
}, bezel)
UITheme.gradient(bezel, UITheme.Candy.panelTop, UITheme.Candy.panelBot, 90)

local mask = new("Frame", {
	Name = "Mask", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(30, 32, 38),
	BorderSizePixel = 0, ClipsDescendants = true,
}, holder)
new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, mask)

local spinner = new("Frame", {
	Name = "Spinner", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
}, mask)

--================================== wedges =================================--
local function radial(frame, angleDeg, len)
	local a = math.rad(angleDeg)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, math.sin(a) * len / 2, 0.5, -math.cos(a) * len / 2)
	frame.Rotation = angleDeg
end

local barsBySlot = {}
local iconChipsBySlot = {}
local BAR_STEP = 1.5
local barW = math.ceil(2 * R * math.sin(math.rad(BAR_STEP) / 2)) + 3

for i, slot in ipairs(SLOTS) do
	barsBySlot[i] = {}
	for b = 0, math.floor(SEG / BAR_STEP) - 1 do
		local bar = new("Frame", {
			Name = ("S%dB%d"):format(i, b), Size = UDim2.fromOffset(barW, R),
			BackgroundColor3 = slot.Colour, BorderSizePixel = 0,
		}, spinner)
		radial(bar, (i - 1) * SEG + b * BAR_STEP + BAR_STEP / 2, R)
		table.insert(barsBySlot[i], bar)
	end
end

-- divider spokes
for i = 1, N do
	local sp = new("Frame", {
		Name = "Spoke" .. i, Size = UDim2.fromOffset(wk(5), R),
		BackgroundColor3 = Color3.fromRGB(240, 242, 246), BorderSizePixel = 0, ZIndex = 4,
	}, spinner)
	radial(sp, (i - 1) * SEG, R)
end

-- Per-wedge text stack, laid out at three radii like the reference: big name on the
-- outer arc, icon and value in the belly, percentage near the hub.
-- A wedge is only 2*r*tan(SEG/2) wide at radius r, so a label sized for the rim will
-- spill into its neighbours near the hub -- which is exactly what happened first pass:
-- the values and percentages piled up into an unreadable knot around the centre. Every
-- label is now capped to the width actually available where it sits.
local TAN_HALF = math.tan(math.rad(SEG / 2))
local function wedgeWidth(rr) return 2 * rr * TAN_HALF * 0.86 end

-- Odds are DERIVED, never typed -- Weight / TOTAL_WEIGHT -- so a future
-- re-weighting of WheelConfig can't make a displayed number lie. Shared by
-- the on-wheel Pct label and the details panel so both can never disagree.
local function oddsTextFor(slot)
	local pct = (slot.Weight / WheelConfig.TOTAL_WEIGHT) * 100
	return (pct >= 10 and ("%d%%"):format(pct + 0.5))
		or (pct >= 1 and ("%.0f%%"):format(pct))
		or ("%.2f%%"):format(pct)
end

for i, slot in ipairs(SLOTS) do
	local mid = (i - 1) * SEG + SEG / 2
	local a = math.rad(mid)
	local function at(rr, w, h)
		return UDim2.new(0.5, math.sin(a) * rr, 0.5, -math.cos(a) * rr),
			UDim2.fromOffset(math.min(w, wedgeWidth(rr)), h)
	end

	local p, s = at(R * 0.76, wk(215), wk(44))
	local name = new("TextLabel", {
		Name = "Name" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = p, Size = s,
		BackgroundTransparency = 1, Rotation = mid, Text = slot.Name,
		Font = Enum.Font.FredokaOne, TextScaled = true,
		TextColor3 = slot.Text or Color3.fromRGB(255, 255, 255), ZIndex = 6,
	}, spinner)
	new("UITextSizeConstraint", { MaxTextSize = wk(30) }, name)
	stroke(name, 3)

	-- 76, down from 86: with only 6 slots the wedge is 139px wide at this radius,
	-- so the chip was never width-clamped and sat there as a 108px square -- louder
	-- than the name and payout it belongs to. 95px still reads as an object.
	p, s = at(R * 0.40, wk(76), wk(76))
	-- Icon in a rounded gradient chip so it reads as an object, not loose text.
	-- The chip carries Rotation = mid (candyPanel doesn't touch Rotation, only
	-- fill/corner/stroke); the icon label nested inside it is Rotation = 0
	-- because GuiObject.Rotation rotates an object AND its descendants together --
	-- giving the label its own `mid` too would double the rotation and skew it.
	local iconChip = new("Frame", {
		Name = "IconChip" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = p, Size = s,
		Rotation = mid, ZIndex = 6,
	}, spinner)
	UITheme.candyPanel(iconChip, wk(16))
	new("TextLabel", {
		Name = "Icon" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.82, 0.82), BackgroundTransparency = 1, Rotation = 0, Text = slot.Icon,
		Font = Enum.Font.FredokaOne, TextScaled = true, ZIndex = 6,
	}, iconChip)
	iconChipsBySlot[i] = iconChip

	p, s = at(R * 0.60, wk(170), wk(30))
	local val = new("TextLabel", {
		Name = "Val" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = p, Size = s,
		BackgroundTransparency = 1, Rotation = mid, Text = slot.Value,
		Font = Enum.Font.FredokaOne, TextScaled = true,
		TextColor3 = slot.Text or Color3.fromRGB(255, 255, 255), ZIndex = 6,
	}, spinner)
	new("UITextSizeConstraint", { MaxTextSize = wk(21) }, val)
	stroke(val, 2.5)

	p, s = at(R * 0.205, wk(70), wk(26))
	local oddsLabel = new("TextLabel", {
		Name = "Pct" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = p, Size = s,
		BackgroundTransparency = 1, Rotation = mid, Text = oddsTextFor(slot),
		Font = UITheme.Candy.font, TextScaled = true,
		TextColor3 = slot.Text or Color3.fromRGB(255, 255, 255), ZIndex = 6,
	}, spinner)
	new("UITextSizeConstraint", { MaxTextSize = wk(19) }, oddsLabel)
	new("UIStroke", {
		Color = UITheme.Candy.ink, Thickness = 2.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, LineJoinMode = Enum.LineJoinMode.Round,
	}, oddsLabel)
end

-- hub and pointer live OUTSIDE the spinner so they hold still while it turns
local hub = new("Frame", {
	Name = "Hub", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(wk(76), wk(76)), BackgroundColor3 = Color3.fromRGB(206, 196, 176),
	BorderSizePixel = 0, ZIndex = 10,
}, holder)
new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, hub)
stroke(hub, 5)

-- Candy pointer: a downward-pointing marker built the same way as the shape it
-- replaces (a square rotated 45 deg, clipped to its lower half by a
-- ClipsDescendants frame) but actually sized so the clip does something -- the
-- old clip frame (60px) was bigger than the diamond's own diagonal (~59px), so
-- it clipped nothing and the "pointer" rendered as a whole, easy-to-miss white
-- diamond sitting ON the wheel face rather than a marker above the rim.
--
-- Where it sits is not a guess: spin()'s `target = -((index - 1) * SEG + SEG /
-- 2)` lands the winning slot's wedge centre at rotation 0, i.e. straight up --
-- so 12 o'clock is the mathematically correct landing angle, confirmed by
-- reading the spin maths below, not assumed.
local PTR_SIDE = wk(46)                     -- diamond side length before its 45 deg turn
local PTR_HALF_DIAG = PTR_SIDE * 0.71   -- centre-to-tip distance once rotated
local PTR_TIP_Y = -wk(18)                   -- tip position: the bezel overhangs the wheel
                                         -- disc by wk(54)/2 px at any WHEEL_PX, so
                                         -- -wk(18) rests just inside the metal rim
local ptrHolder = new("Frame", {
	Name = "Pointer", AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, PTR_TIP_Y - PTR_HALF_DIAG),
	Size = UDim2.fromOffset(wk(80), PTR_HALF_DIAG + wk(14)), -- +14: room for the tip and its shadow's peek
	BackgroundTransparency = 1, ZIndex = 13, ClipsDescendants = true,
}, holder)
-- candyShadow isn't used here: it copies Size/Position/AnchorPoint but not
-- Rotation, so on a 45-degree-rotated diamond it would draw an axis-aligned
-- rounded square behind it -- visibly mismatched. Built by hand instead, same
-- rotated-diamond technique, offset down and clipped by the same ptrHolder.
local ptrShadow = new("Frame", {
	Name = "PointerShadow", AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(PTR_SIDE, PTR_SIDE),
	Rotation = 45, BackgroundColor3 = UITheme.Candy.shadow, BorderSizePixel = 0, ZIndex = 12,
}, ptrHolder)
local ptrTri = new("Frame", {
	Name = "Tri", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.fromOffset(PTR_SIDE, PTR_SIDE), Rotation = 45,
	BackgroundColor3 = UITheme.Candy.gold1, BorderSizePixel = 0, ZIndex = 13,
}, ptrHolder)
UITheme.gradient(ptrTri, UITheme.Candy.gold1, UITheme.Candy.gold2, 90)
-- Task 4 tune: LineJoinMode.Round was rounding off the clipped diamond's
-- bottom apex (a genuinely sharp 90 degree corner geometrically -- the clip
-- keeps exactly the bottom half of a square rotated 45 deg, which is a true
-- triangle) enough to read as a soft rounded blob rather than a pointer.
-- Miter preserves the sharp corner exactly.
new("UIStroke", {
	Color = UITheme.Candy.ink, Thickness = UITheme.Candy.stroke,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border, LineJoinMode = Enum.LineJoinMode.Miter,
}, ptrTri)
-- The ptrHolder clip slices the diamond's top half away, and UIStroke
-- outlines the FULL square, not the clipped shape -- so the cut top edge
-- rendered open/strokeless. PtrCap closes it with an inked bar the same
-- thickness as the stroke, spanning the diamond's clipped width.
new("Frame", {
	Name = "PtrCap", AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.fromOffset(PTR_SIDE * 1.42 + 6, UITheme.Candy.stroke),
	BackgroundColor3 = UITheme.Candy.ink, BorderSizePixel = 0, ZIndex = 13,
}, ptrHolder)

--================================== chrome =================================--
local title = new("TextLabel", {
	Name = "Title", AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(520, TITLE_H),
	BackgroundTransparency = 1, Text = "DAILY SPIN", Font = UITheme.Candy.font,
	TextScaled = true, TextColor3 = Color3.fromRGB(255, 176, 46), ZIndex = 14,
}, cluster)
new("UITextSizeConstraint", { MaxTextSize = 56 }, title)
stroke(title, 5)

-- Screen-corner-pinned, NOT a Cluster child, so it stays a full 56px tappable
-- target even when the cluster shrinks. TOP_MARGIN keeps it clear of MainUI's
-- cash pill without WheelClient needing to read MainUI's own instances.
local closeBtn = new("TextButton", {
	Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -22, 0, TOP_MARGIN - 4),
	Size = UDim2.fromOffset(56, 56), Text = "", Font = Enum.Font.FredokaOne,
	TextScaled = true, TextColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundColor3 = Color3.fromRGB(224, 58, 58), AutoButtonColor = true, ZIndex = 14,
}, root)
new("UICorner", { CornerRadius = UDim.new(0, 12) }, closeBtn)
stroke(closeBtn, 4)
-- Draws the X as two rotated Frames (UITheme.closeGlyph), not text -- the
-- glyph U+2715 does not render in this Roblox build. Deliberately NOT
-- UITheme.styleClose: this button's 56px size, position and red are custom
-- to the wheel and styleClose would reset them to the 30px standard.
UITheme.closeGlyph(closeBtn)

-- Candy colour pairs for the three button states. refreshButton() below
-- swaps these via UITheme.setColors (updates the UIGradient candyButton
-- attaches) rather than spinBtn.BackgroundColor3 directly -- once a
-- UIGradient sits on an object it paints the fill, so a lone BackgroundColor3
-- write has no visible effect.
local SPIN_READY_1, SPIN_READY_2 = UITheme.Candy.green1, UITheme.Candy.green2
local SPIN_BUSY_1,  SPIN_BUSY_2  = Color3.fromRGB(178, 182, 192), Color3.fromRGB(140, 144, 154)
local SPIN_WAIT_1,  SPIN_WAIT_2  = Color3.fromRGB(150, 154, 164), Color3.fromRGB(110, 114, 124)

local spinBtn = new("TextButton", {
	Name = "SpinBtn", AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, TITLE_H + GAP_TITLE + WHEEL_PX + GAP_SPIN),
	Size = UDim2.fromOffset(320, SPIN_H),
	Text = "SPIN", TextScaled = true, ZIndex = 14,
}, cluster)
new("UITextSizeConstraint", { MaxTextSize = 36 }, spinBtn)
UITheme.candyButton(spinBtn, SPIN_READY_1, SPIN_READY_2, 16)

local subLabel = new("TextLabel", {
	Name = "Sub", AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, TITLE_H + GAP_TITLE + WHEEL_PX + GAP_SPIN + SPIN_H + GAP_SUB),
	Size = UDim2.fromOffset(520, SUB_H), BackgroundTransparency = 1, Text = "",
	Font = Enum.Font.FredokaOne, TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 255, 255), ZIndex = 14,
}, cluster)
new("UITextSizeConstraint", { MaxTextSize = 22 }, subLabel)
stroke(subLabel, 3)

local banner = new("Frame", {
	Name = "Banner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.16, 0),
	Size = UDim2.fromOffset(560, 84), BackgroundColor3 = Color3.fromRGB(20, 24, 30),
	BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, ZIndex = 16,
}, root)
new("UICorner", { CornerRadius = UDim.new(0, 16) }, banner)
local bannerStroke = new("UIStroke", { Color = INK, Thickness = 4, Transparency = 1 }, banner)
local bannerScale = new("UIScale", { Scale = 1 }, banner)
local bannerText = new("TextLabel", {
	Name = "Text", Size = UDim2.new(1, -24, 1, -18), Position = UDim2.new(0, 12, 0, 9),
	BackgroundTransparency = 1, Text = "", Font = Enum.Font.FredokaOne, TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 208, 70), ZIndex = 17,
}, banner)
new("UITextSizeConstraint", { MaxTextSize = 40 }, bannerText)
stroke(bannerText, 3.5)

local toastToken = 0
local function showResult(text, colour)
	toastToken += 1
	local mine = toastToken
	bannerText.Text = text
	bannerText.TextColor3 = colour or Color3.fromRGB(255, 208, 70)
	banner.Visible = true
	banner.BackgroundTransparency = 0.1
	bannerStroke.Transparency = 0
	bannerText.TextTransparency = 0
	bannerScale.Scale = 0.6
	TweenService:Create(bannerScale, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }):Play()
	task.delay(TOAST_HOLD, function()
		if mine ~= toastToken then return end
		local ti = TweenInfo.new(0.5)
		TweenService:Create(bannerText, ti, { TextTransparency = 1 }):Play()
		TweenService:Create(banner, ti, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(bannerStroke, ti, { Transparency = 1 }):Play()
		task.delay(0.55, function() if mine == toastToken then banner.Visible = false end end)
	end)
end

--================================== details =================================--
-- A panel beside the wheel listing all six slots rarest-first (so the jackpot
-- reads as the headline), each row built from WheelConfig -- never hardcoded --
-- sharing oddsTextFor() with the on-wheel Pct label so the two can never
-- disagree. Positioned off root.AbsoluteSize (tracks the real viewport, since
-- root fills the screen) rather than fixed pixels, and re-laid-out on resize
-- so it collapses BELOW the wheel instead of overlapping it on a narrow one.
-- All rows are ZIndex 14 -- CHECKED against Global ZIndexBehavior (see the
-- CandyPanel removal note above): this panel sits beside/below the wheel,
-- never over its disc, so the Z tie with Title/Close/SpinBtn (also 14) never
-- overlaps on screen.
local detailsPanel = new("Frame", {
	Name = "DetailsPanel", BackgroundTransparency = 1, ZIndex = 14, ClipsDescendants = true,
}, root)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 8),
	HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
}, detailsPanel)

local rarestFirst = {}
for i = 1, N do rarestFirst[i] = i end
table.sort(rarestFirst, function(a, b) return SLOTS[a].Weight < SLOTS[b].Weight end)

for order, slotIdx in ipairs(rarestFirst) do
	local slot = SLOTS[slotIdx]
	local row = new("Frame", {
		Name = "Row" .. slotIdx, LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 56), ZIndex = 14,
	}, detailsPanel)
	UITheme.candyPanel(row, 14)

	local chip = new("Frame", {
		Name = "Chip", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(44, 44), ZIndex = 15,
	}, row)
	UITheme.candyPanel(chip, 12)
	new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8), BackgroundTransparency = 1, Text = slot.Icon,
		Font = Enum.Font.FredokaOne, TextScaled = true, ZIndex = 16,
	}, chip)

	new("TextLabel", {
		Name = "Payout", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 58, 0.28, 0),
		Size = UDim2.new(1, -66, 0, 22), BackgroundTransparency = 1, Text = slot.Value,
		Font = UITheme.Candy.font, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UITheme.Candy.ink, ZIndex = 15,
	}, row)
	new("TextLabel", {
		Name = "Odds", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 58, 0.74, 0),
		Size = UDim2.new(1, -66, 0, 18), BackgroundTransparency = 1, Text = oddsTextFor(slot),
		Font = UITheme.Candy.font, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(96, 102, 116), ZIndex = 15,
	}, row)
end

-- Beside the wheel when there's real room; collapses BELOW it otherwise.
-- Task 4 fix: the old check only asked "is there room symmetric around the
-- wheel" and had no idea QuestTrackerUI reserves a band hugging the right
-- edge -- so at common desktop widths (1380 included) it chose "beside" and
-- landed squarely on the quest tracker card. RIGHT_HUD_RESERVE encodes that
-- band (QuestTrackerClient's own comment: CARD_W 214 + its holder's own
-- padding, 14px right margin -- see StarterPlayerScripts.QuestTrackerClient)
-- so "beside" only wins when it demonstrably clears it, with margin to
-- spare. Wheel centre/radius are derived from the layout constants and
-- clusterScale (see the pop-immunity note inside layoutDetails), not from
-- Holder/Bezel Absolute* reads -- those go stale mid-pop while holderScale
-- tweens the wheel open.
local function layoutDetails()
	local vw, vh = root.AbsoluteSize.X, root.AbsoluteSize.Y
	-- Pop-immunity: derive the wheel's centre and radius from stable geometry
	-- (layout constants scaled by clusterScale) rather than Holder/Bezel
	-- Absolute* reads -- holderScale's open-pop tween (0.82 -> 1) briefly
	-- shrinks those live values, letting a mid-pop relayout misplace the panel.
	local centerX = vw / 2
	local centerY = (cluster.AbsolutePosition.Y - root.AbsolutePosition.Y) + (TITLE_H + GAP_TITLE + WHEEL_PX * 0.5) * clusterScale.Scale
	local wheelHalf = (WHEEL_PX + wk(54)) * 0.5 * clusterScale.Scale
	local clusterBottom = (cluster.AbsolutePosition.Y - root.AbsolutePosition.Y) + cluster.AbsoluteSize.Y
	-- beside-vs-below comes from layoutCluster (see detailsBelow), not re-derived
	-- here -- the two must not be able to disagree.
	if not detailsBelow then
		detailsPanel.AnchorPoint = Vector2.new(0, 0.5)
		detailsPanel.Position = UDim2.new(0, centerX + wheelHalf + 24, 0, centerY)
		detailsPanel.Size = UDim2.fromOffset(DETAILS_W, math.min(N * 64, vh - BOTTOM_HUD_RESERVE - 20))
	else
		detailsPanel.AnchorPoint = Vector2.new(0.5, 0)
		detailsPanel.Position = UDim2.new(0, centerX, 0, clusterBottom + 16)
		-- floor of 50 (not just clamped to >=0): DETAILS_BELOW_RESERVE above keeps
		-- this comfortably positive in practice, but never let a tight/unusual
		-- viewport hand this a negative Size.Y -- see the reserve's own comment.
		-- Bottom bound is (vh - DETAILS_BOTTOM_RESERVE), NOT vh, so this clears
		-- the native hotbar / Bag / Sprint row AND LuckHUDClient's luck chip.
		local h = math.max(50, math.min(N * 60, (vh - DETAILS_BOTTOM_RESERVE) - clusterBottom - 16))
		-- Snap to whole rows (56px row + 8px list padding = 64 per extra row)
		-- so ClipsDescendants never leaves the last visible row half-cut.
		if h >= 56 then h = 56 + math.floor((h - 56) / 64) * 64 end
		detailsPanel.Size = UDim2.new(0.86, 0, 0, h)
	end
end
layoutDetails()
root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutDetails)
holder:GetPropertyChangedSignal("AbsolutePosition"):Connect(layoutDetails)

--================================ fast spin =================================--
-- Client-local comfort setting only: no server call, no data field, resets on
-- rejoin -- acceptable for a comfort toggle, and avoids a schema migration in
-- a shared file. spin() reads `fastSpin` once at the start of each spin, not
-- live, so toggling mid-flight can't change the timing of a spin already
-- underway.
local fastSpin = false
local FAST_OFF_1, FAST_OFF_2 = Color3.fromRGB(150, 154, 164), Color3.fromRGB(110, 114, 124)
local FAST_ON_1,  FAST_ON_2  = UITheme.Candy.gold1, UITheme.Candy.gold2

-- moved: left nav rail now occupies the upper-left column (ui overhaul).
-- Bug E fix (ui-overhaul checkpoint-1 fix wave): the old Position (22,80)
-- put this toggle squarely inside NavRail.bagItem.Hit (x[10.2..118.5]
-- y[71.4..171.5], task-4-report.md Check 3/4) -- confirmed live, a Bag click
-- while the wheel was open toggled Fast Spin instead of hitting Bag. Moved to
-- the bottom-left, anchored off root's BOTTOM edge instead (root's bottom
-- always equals the true screen bottom regardless of GuiInset, since only
-- the TOP is inset-clipped -- see the ScreenGui comment up top): with
-- AnchorPoint(0,1) + Position(0,22,1,-24) the toggle's top edge sits at
-- root-local (rootHeight-70), clearing NavRail's own measured bottom
-- (702.7 true-screen / ~644.7 root-local at this build's 58px inset) by
-- ~20px, with ~24px left to the true screen bottom below it. Nowhere near
-- MainUI.SprintButton (x[1225..1363] y[669..719]) or LuckHUD.LuckChip
-- (x[1237..1365] y[623..657]) either -- both sit on the opposite (right)
-- side of the screen.
local fastToggle = new("TextButton", {
	Name = "FastSpinToggle", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 22, 1, -24),
	Size = UDim2.fromOffset(168, 46), Text = "FAST SPIN: OFF", TextScaled = true, ZIndex = 14,
}, root)
new("UITextSizeConstraint", { MaxTextSize = 20 }, fastToggle)
UITheme.candyButton(fastToggle, FAST_OFF_1, FAST_OFF_2, 14)

fastToggle.Activated:Connect(function()
	fastSpin = not fastSpin
	if fastSpin then
		fastToggle.Text = "FAST SPIN: ON"
		UITheme.setColors(fastToggle, FAST_ON_1, FAST_ON_2)
	else
		fastToggle.Text = "FAST SPIN: OFF"
		UITheme.setColors(fastToggle, FAST_OFF_1, FAST_OFF_2)
	end
end)

--================================== sounds =================================--
-- Ids live in SoundKit, never here. The two REPEATING sounds keep one long-lived
-- instance each and get restarted, instead of going through SoundKit.play(): a
-- single spin crosses ~100 wedge boundaries, and play() clones a Sound per call,
-- so ticking through it would litter a hundred instances per spin for no gain.
-- The one-shot landing stings do go through play(), which is what it is for.
local sg = game:GetService("SoundService")
local tickSound = new("Sound", { SoundId = SoundKit.Ids.wheelTick, Volume = 0.40 }, sg)
local windSound = new("Sound", { SoundId = SoundKit.Ids.wheelWind, Volume = 0.50 }, sg)

-- Which wedge is the jackpot is DERIVED -- the rarest slot wins the fanfare --
-- for the same reason the odds are derived a few hundred lines up: a re-weighting
-- in WheelConfig must not be able to leave the fanfare firing on the wrong wedge.
local JACKPOT_INDEX = 1
for i, s in ipairs(SLOTS) do
	if s.Weight < SLOTS[JACKPOT_INDEX].Weight then JACKPOT_INDEX = i end
end

-- Flat 2D on purpose: this happened to YOU. The world wheel spins for bystanders
-- to watch, but they should not hear another player's payout across the plaza.
local function playLanding(index)
	if index == JACKPOT_INDEX then
		SoundKit.play("wheelJackpotHit", nil, { volume = 0.5 })
		SoundKit.play("wheelJackpot", nil, { volume = 0.55 })
	else
		SoundKit.play("wheelWin", nil, { volume = 0.45 })
	end
end

--=============================== world wheel ===============================--
-- Kept in sync so bystanders see the prop turn too. Bound with WaitForChild because the
-- model's parts and its SurfaceGui children stream in separately.
local worldWheel, worldSpinner, worldPointer, worldPtrBase
local function resolveWorld(model)
	if not model or not model.Parent then return end
	local face = model:WaitForChild("Face", 20)
	local wsg = face and face:WaitForChild("WheelFace", 20)
	local wmask = wsg and wsg:WaitForChild("Mask", 20)
	local sp = wmask and wmask:WaitForChild("Spinner", 20)
	if not sp then return end
	worldWheel, worldSpinner = model, sp
	worldPointer = model:FindFirstChild("Pointer")
	worldPtrBase = worldPointer and worldPointer.CFrame or nil
end

task.spawn(function()
	local gw = Workspace:WaitForChild("GameWorld", 30)
	if not gw then return end
	gw.ChildAdded:Connect(function(c)
		if c.Name == "DailyWheel" then task.spawn(resolveWorld, c) end
	end)
	local existing = gw:FindFirstChild("DailyWheel")
	if existing then task.spawn(resolveWorld, existing) end
end)

--================================= the spin ================================--
local spinToken = 0
local spinning = false
local cooldown, luckLeft, powerLeft = 0, 0, 0
local lastSync = os.clock()

local function ease(t)
	local KICK = 0.12
	if t < KICK then
		local u = t / KICK
		return (u * u) * KICK * 0.55
	end
	local u = (t - KICK) / (1 - KICK)
	-- ^6 rather than ^5: a slightly harder tail deceleration so the spin
	-- visibly settles into the pointer instead of coasting to a stop (Task 3).
	return KICK * 0.55 + (1 - KICK * 0.55) * (1 - (1 - u) ^ 6)
end

local function hms(sec)
	sec = math.max(0, math.floor(sec))
	local h = math.floor(sec / 3600)
	local m = math.floor((sec % 3600) / 60)
	local s = sec % 60
	if h > 0 then return ("%dh %02dm"):format(h, m) end
	if m > 0 then return ("%dm %02ds"):format(m, s) end
	return ("%ds"):format(s)
end

local function refreshButton()
	if spinning then
		spinBtn.Text = "SPINNING..."
		UITheme.setColors(spinBtn, SPIN_BUSY_1, SPIN_BUSY_2)
	elseif cooldown > 0 then
		spinBtn.Text = "NEXT SPIN " .. hms(cooldown)
		UITheme.setColors(spinBtn, SPIN_WAIT_1, SPIN_WAIT_2)
	else
		spinBtn.Text = "SPIN"
		UITheme.setColors(spinBtn, SPIN_READY_1, SPIN_READY_2)
	end
	local bits = {}
	if luckLeft > 0 then table.insert(bits, ("\u{1F340} LUCK %s"):format(hms(luckLeft))) end
	if powerLeft > 0 then table.insert(bits, ("\u{1F4AA} POWER %s"):format(hms(powerLeft))) end
	subLabel.Text = (#bits > 0) and table.concat(bits, "    ") or "one free spin every 24 hours"
end

local function flashWinner(index, myToken)
	local bars = barsBySlot[index]
	if not bars then return end
	local base = SLOTS[index].Colour
	local hot = Color3.new(math.min(base.R + 0.45, 1), math.min(base.G + 0.45, 1), math.min(base.B + 0.45, 1))
	for _ = 1, 3 do
		if myToken ~= spinToken then break end
		for _, b in ipairs(bars) do
			if b.Parent then TweenService:Create(b, TweenInfo.new(0.16), { BackgroundColor3 = hot }):Play() end
		end
		task.wait(0.17)
		if myToken ~= spinToken then break end
		for _, b in ipairs(bars) do
			if b.Parent then TweenService:Create(b, TweenInfo.new(0.16), { BackgroundColor3 = base }):Play() end
		end
		task.wait(0.17)
	end
	task.wait(0.18)
	for _, b in ipairs(bars) do if b.Parent then b.BackgroundColor3 = base end end
end

-- Landing pop: a brief scale bounce on the winning slot's icon chip, alongside
-- flashWinner's colour flash above -- together, the "brief scale/brightness
-- kick" a settled landing calls for.
local function popWinner(index)
	local chip = iconChipsBySlot[index]
	if not chip then return end
	local sc = chip:FindFirstChildOfClass("UIScale") or new("UIScale", { Scale = 1 }, chip)
	sc.Scale = 1
	TweenService:Create(sc, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1.35 }):Play()
	task.delay(0.14, function()
		TweenService:Create(sc, TweenInfo.new(0.30, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
			{ Scale = 1 }):Play()
	end)
end

local function spin(index, onDone)
	spinToken += 1
	local myToken = spinToken
	spinning = true
	refreshButton()
	-- Read once per spin, not live -- toggling Fast Spin mid-flight must not
	-- change the timing of a spin already underway.
	local spinT = fastSpin and SPIN_T_FAST or SPIN_T

	local startRot = spinner.Rotation
	local target = -((index - 1) * SEG + SEG / 2)
	while target > startRot - 360 * TURNS do target -= 360 end

	local windTo = startRot + WINDUP_DEG
	local wind = TweenService:Create(spinner,
		TweenInfo.new(WINDUP_T, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = windTo })
	if worldSpinner and worldSpinner.Parent then
		TweenService:Create(worldSpinner,
			TweenInfo.new(WINDUP_T, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = windTo }):Play()
	end
	wind:Play()
	windSound:Play()
	wind.Completed:Wait()
	if myToken ~= spinToken then return end

	local from, span = windTo, target - windTo
	local t0, lastTick, pendingTick = os.clock(), 0, false
	local lastBoundary = math.floor((-from) / SEG)
	local kick, lastFrame = 0, os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if myToken ~= spinToken then conn:Disconnect() return end
		local nowT = os.clock()
		local dt = math.min(nowT - lastFrame, 0.1)
		lastFrame = nowT
		local t = math.clamp((nowT - t0) / spinT, 0, 1)
		local rot = from + span * ease(t)
		spinner.Rotation = rot
		if worldSpinner and worldSpinner.Parent then worldSpinner.Rotation = rot end

		local boundary = math.floor((-rot) / SEG)
		if boundary ~= lastBoundary then
			lastBoundary = boundary
			pendingTick = true
			kick = 15 * (1 - t) + 4
		end
		-- A crossing that lands while the throttle is closed is REMEMBERED, not
		-- dropped. The throttle is here to cap the click RATE, but the old form
		-- only clicked on a crossing that happened to fall outside the window --
		-- so the fast first half of the spin, where crossings come every few ms,
		-- was silent. Measured: a 7.5s spin made 7 clicks for 54 wedge crossings.
		-- Holding the crossing instead runs the ratchet at the TICK_GAP cadence
		-- while the wheel is fast, and it spaces out to one click per wedge on its
		-- own as the wheel slows -- which is the accelerating-ratchet sound a real
		-- prize wheel makes, and it lets the pitch ramp below actually be heard.
		if pendingTick and nowT - lastTick >= TICK_GAP then
			pendingTick = false
			lastTick = nowT
			-- Widened from 1.45->1.00. The deceleration is the whole point of a wheel
			-- ratchet and a 0.45 span was too narrow to hear; 1.55->0.85 drops most of
			-- an octave across the spin, so the wheel audibly runs down.
			tickSound.PlaybackSpeed = 1.55 - 0.70 * t + (math.random() - 0.5) * 0.06
			tickSound:Play()
		end
		-- spring back over time; snapping back next frame made it invisible
		kick = kick * math.exp(-dt * 11)
		ptrTri.Rotation = 45 - kick
		if worldPointer and worldPointer.Parent and worldPtrBase then
			worldPointer.CFrame = worldPtrBase * CFrame.Angles(0, 0, math.rad(-kick))
		end

		if t >= 1 then
			conn:Disconnect()
			spinner.Rotation = target % 360
			if worldSpinner and worldSpinner.Parent then worldSpinner.Rotation = target % 360 end
			ptrTri.Rotation = 45
			if worldPointer and worldPointer.Parent and worldPtrBase then worldPointer.CFrame = worldPtrBase end
			playLanding(index)
			spinning = false
			refreshButton()
			task.spawn(flashWinner, index, myToken)
			task.spawn(popWinner, index)
			if onDone then onDone() end
		end
	end)
end

--============================== open and close =============================--
local isOpen = false
local function setOpen(on)
	if isOpen == on then return end
	isOpen = on
	if on then
		root.Visible = true
		holderScale.Scale = 0.82
		TweenService:Create(holderScale, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }):Play()
		stateRemote:FireServer()
	else
		root.Visible = false
	end
end

closeBtn.Activated:Connect(function() setOpen(false) end)

spinBtn.Activated:Connect(function()
	if spinning or cooldown > 0 then return end
	spinning = true
	refreshButton()
	spinRemote:FireServer()
	task.delay(8, function() if spinning then spinning = false; refreshButton() end end)
end)

-- Auto-open on approach, with hysteresis so standing on the boundary does not strobe the
-- UI. Closing is suppressed mid-spin so the wheel cannot vanish while it is still turning.
local manualClose = false
task.spawn(function()
	while true do
		task.wait(0.25)
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local anchor = worldWheel and (worldWheel.PrimaryPart or worldWheel:FindFirstChild("Base"))
		if hrp and anchor then
			local d = (hrp.Position - anchor.Position).Magnitude
			if d <= NEAR and not isOpen and not manualClose then
				setOpen(true)
			elseif d > FAR then
				manualClose = false
				if isOpen and not spinning then setOpen(false) end
			end
		end
	end
end)
-- pressing X should not immediately reopen while still standing in the ring
closeBtn.Activated:Connect(function() manualClose = true end)

-- WheelBoard puts a real ProximityPrompt on the wheel ("SpinPrompt", E, reach
-- 14) -- but nothing on the client had ever listened to it, so pressing E did
-- nothing at all. That hid for a long time because the auto-open ring (NEAR =
-- 15) is slightly WIDER than the prompt's own 14-stud reach, so the UI was
-- almost always already open by the time the prompt even appeared. It matters
-- after a manual close: manualClose latches until you walk back out past FAR,
-- and the prompt is the intended way back in. So clear the latch and open.
local ProximityPromptService = game:GetService("ProximityPromptService")
ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player then return end
	if prompt.Name ~= "SpinPrompt" then return end
	manualClose = false
	setOpen(true)
end)

--================================== remotes ================================--
spunRemote.OnClientEvent:Connect(function(index, whoName, text)
	if type(index) ~= "number" or not SLOTS[index] then return end
	local mine = (whoName == player.Name)
	spin(index, function()
		if mine then
			showResult("YOU WON  " .. tostring(text or ""), SLOTS[index].Colour)
		elseif whoName then
			showResult(tostring(whoName) .. " won " .. tostring(text or ""), SLOTS[index].Colour)
		end
	end)
end)

stateRemote.OnClientEvent:Connect(function(s)
	if type(s) ~= "table" then return end
	cooldown = tonumber(s.Cooldown) or 0
	luckLeft = tonumber(s.LuckLeft) or 0
	powerLeft = tonumber(s.PowerLeft) or 0
	lastSync = os.clock()
	if s.Error then showResult(tostring(s.Error), Color3.fromRGB(255, 120, 110)); spinning = false end
	if not s.Result then refreshButton() end
end)

task.spawn(function()
	while true do
		task.wait(1)
		local dt = os.clock() - lastSync
		lastSync = os.clock()
		if cooldown > 0 then cooldown = math.max(0, cooldown - dt) end
		if luckLeft > 0 then luckLeft = math.max(0, luckLeft - dt) end
		if powerLeft > 0 then powerLeft = math.max(0, powerLeft - dt) end
		if not spinning then refreshButton() end
	end
end)

refreshButton()
task.delay(2, function() stateRemote:FireServer() end)
