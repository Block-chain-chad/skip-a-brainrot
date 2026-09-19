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
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local WheelConfig = require(ReplicatedStorage.Modules.WheelConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local SideRail = require(ReplicatedStorage.Modules.SideRail)
local SoundKit = require(ReplicatedStorage.Modules.SoundKit)
local CrateCeremony = require(ReplicatedStorage.Modules.CrateCeremony)
-- pcall'd, like every other IconArt caller: a slot that cannot get its drawing
-- falls back to the glyph it always had, so a kit that fails to load costs a
-- picture rather than the wheel.
local okIconArt, IconArt = pcall(function()
	return require(ReplicatedStorage.Modules.UIKit.IconArt)
end)
if not okIconArt then IconArt = nil end

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

--[[ ONE ICON RULE, for both places this wheel draws a prize -- the wedge chip
and the prize list beside it. They MUST agree: two call sites drawing the same
slot two different ways is how the wheel ends up showing a picture the list
does not.

A slot with an `Art` key gets the game's own drawn artwork (UIKit.IconArt);
every other slot keeps its glyph, exactly as before. Only the emerald wedge
carries one today, so the wheel shows the same green stone the HUD pill, the
egg shop's wallet and every price row already show, instead of the blue
diamond emoji the currency stopped being.

AND IT IS NOT A VIEWPORT, which is the distinction that makes this safe here.
The long note at the wedge chip below is about IconForge, whose icons are 3D
MODELS: a ViewportFrame renders at its own pixel size with no anti-aliasing,
which is why those were pulled off these chips after three rounds of "the
pictures still look bad". IconArt draws with nested Frames -- ordinary GUI
geometry, anti-aliased by the same renderer as the rest of the HUD, and sharp
at 34px and 54px alike. Different mechanism, and the objection does not carry
over. ]]
local function paintIcon(holder, slot, size, z)
	if IconArt and slot.Art and IconArt.has(slot.Art) then
		local art = IconArt.draw(holder, slot.Art, size, z)
		if art then
			-- draw() bakes its shapes to `size` and parks the root at the holder's
			-- top-left; re-anchoring the root centres the drawing without disturbing
			-- anything inside it
			art.AnchorPoint = Vector2.new(0.5, 0.5)
			art.Position = UDim2.fromScale(0.5, 0.5)
			return art
		end
	end
	return new("TextLabel", {
		Name = "Glyph", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Text = slot.Icon, Font = Enum.Font.FredokaOne, TextScaled = true, ZIndex = z,
	}, holder)
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

-- The Scrim used to dim the world behind the wheel to 0.45 black. That black wash was
-- cut on request -- the wheel now sits straight over the live world. The frame STAYS,
-- fully transparent, because Active = true is what swallows clicks so a spin cannot
-- also fire something in the world behind it; deleting the frame would let input through.
new("Frame", {
	Name = "Scrim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 0, Active = true,
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

-- SHORT-VIEWPORT GUARD (2026-08-26).
-- TOP_MARGIN (100), BOTTOM_HUD_RESERVE (90) and DETAILS_BELOW_RESERVE (110) are
-- all authored as DESKTOP pixels and sum to 300. A landscape phone's usable box
-- is 302-382px tall, so on a handset the three of them consumed essentially the
-- whole screen and avail/CLUSTER_H collapsed with nothing bounding it. Measured
-- live, by pinning Root to each device's real box and letting its own
-- AbsoluteSize reflow fire:
--
--   800x360  scale 0.002   disc   2px   SPIN 1x0
--   667x375  scale 0.019   disc  15px   SPIN 6x1
--   844x390  scale 0.036   disc  28px   SPIN 12x2
--   956x440  scale 0.093   disc  72px   SPIN 30x6
--   1180x820 scale 0.526   disc 404px   SPIN 168x34
--
-- i.e. the wheel was invisible on every phone and sub-touch on tablet, while
-- desktop (0.94) was fine -- which is why nothing here ever looked wrong to
-- anyone testing in Studio.
--
-- Each reserve is therefore capped at a SHARE of the height actually available,
-- rather than spent as literal pixels on a box barely taller than their sum. The
-- min() keeps the authored value on any viewport tall enough to afford it: the
-- shares are chosen so the literal still wins at tablet height (762), so desktop
-- AND tablet are unchanged to the pixel and only genuinely short screens see the
-- proportional value. Verified before/after at all six profiles.
local TOP_SHARE, BOTTOM_SHARE, BELOW_SHARE = 0.14, 0.13, 0.16
-- Bounded floor. The collapse above was possible because nothing stopped the fit
-- going to zero. This is deliberately NOT a bare clamp: see the HUD doc's "a
-- floor can be the bug" -- clamping past the height the box can actually hold
-- would push the SPIN button off the bottom of the screen, which is worse than a
-- small wheel. So the floor is itself capped by the reserve-free fit, and the
-- details sliver (not the wheel) is what yields when the two compete.
local MIN_SCALE = 0.20

local function layoutCluster()
	local vh = root.AbsoluteSize.Y
	local top    = math.min(TOP_MARGIN, vh * TOP_SHARE)
	local bottom = math.min(BOTTOM_HUD_RESERVE, vh * BOTTOM_SHARE)
	local below  = math.min(DETAILS_BELOW_RESERVE, vh * BELOW_SHARE)
	-- DETAILS_BELOW_RESERVE is only ever USED when the panel collapses below the
	-- wheel, but it used to be subtracted unconditionally -- so on a wide desktop,
	-- where the panel sits BESIDE the wheel, 110px of height was reserved for
	-- nothing and the disc shrank to pay for it. On a 717px-tall window that one
	-- reserve was costing about a third of the wheel. Try the no-reserve fit first
	-- and only fall back when the panel demonstrably cannot fit beside.
	local function fitFor(reserve)
		local avail = math.max(1, vh - top - bottom - reserve)
		return math.min(MAX_SCALE, avail / CLUSTER_H), avail
	end
	local scale, available = fitFor(0)
	detailsBelow = not besideFitsAt(scale)
	if detailsBelow then
		scale, available = fitFor(below)
	end
	-- largest scale the box can hold once top/bottom are paid -- the floor may
	-- never exceed this
	local fitsMax = math.max(0, vh - top - bottom) / CLUSTER_H
	scale = math.clamp(scale, math.min(MIN_SCALE, fitsMax), MAX_SCALE)
	clusterScale.Scale = scale
	local extra = math.max(0, available - CLUSTER_H * scale)
	cluster.Position = UDim2.new(0.5, 0, 0, top + extra / 2)
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

-- Odds are DERIVED, never typed, so a future re-weighting of WheelConfig can't
-- make a displayed number lie. The maths moved INTO WheelConfig (OddsShort) once
-- the world plaque needed the same string -- three call sites computing their own
-- percentage is three chances for one of them to drift.
local function oddsTextFor(slot)
	return WheelConfig.OddsShort(slot)
end

-- Odds text is TIERED by rarity: rainbow on the 1%, diamond on the 9%, gold on the
-- two 15%s, plain white below that. The gradient does the work, so every odds
-- label is white with an ink outline underneath it -- a UIGradient MULTIPLIES the
-- text colour, so painting these on the old dark ink would have produced mud.
-- NO NEAR-WHITE STOPS. These sit on the white candy chip, and a UIGradient
-- MULTIPLIES the text colour -- a stop at (255,255,255) paints that part of the
-- glyph white on white and the top half of the digit simply vanishes. Every stop
-- below is saturated enough to read against the chip on its own.
local ODDS_GRADIENTS = {
	gold = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB(250, 196, 60)),
		ColorSequenceKeypoint.new(0.50, Color3.fromRGB(238, 164, 24)),
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(176, 104, 6)),
	}),
	diamond = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB(118, 214, 246)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(58, 178, 234)),
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(16, 116, 186)),
	}),
	-- the yellow stop is pulled down from (250,238,72): pure yellow is the one
	-- rainbow band that disappears against a near-white chip
	rainbow = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB(244, 62, 62)),
		ColorSequenceKeypoint.new(0.20, Color3.fromRGB(248, 150, 24)),
		ColorSequenceKeypoint.new(0.40, Color3.fromRGB(214, 196, 20)),
		ColorSequenceKeypoint.new(0.60, Color3.fromRGB(48, 196, 84)),
		ColorSequenceKeypoint.new(0.80, Color3.fromRGB(48, 148, 246)),
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(176, 74, 248)),
	}),
}

-- Paint a label with the slot's rarity gradient and nothing else. The rainbow /
-- diamond / gold treatment covers ALL of a wedge's lettering -- name, payout and
-- odds -- not just the percentage, so a rung reads as one tier at a glance.
--
-- The CALLER owns the outline here: Name and Value already carry their own
-- stroke, and a second UIStroke on the same label doubles the ink and closes up
-- the counters on small glyphs.
local function tintPrize(label, slot)
	local seq = slot.OddsStyle and ODDS_GRADIENTS[slot.OddsStyle]
	if not seq then return end
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	new("UIGradient", { Color = seq, Rotation = (slot.OddsStyle == "rainbow") and 0 or 90 }, label)
end

local function styleOdds(label, slot, strokeThickness)
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	new("UIStroke", {
		Color = UITheme.Candy.ink, Thickness = strokeThickness or 2.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, LineJoinMode = Enum.LineJoinMode.Round,
	}, label)
	local seq = slot.OddsStyle and ODDS_GRADIENTS[slot.OddsStyle]
	if seq then
		-- rainbow runs ACROSS the text so the whole spectrum is visible in "1%";
		-- gold and diamond run top-to-bottom, which is how a metal/gem sheen reads
		new("UIGradient", { Color = seq, Rotation = (slot.OddsStyle == "rainbow") and 0 or 90 }, label)
	end
end

for i, slot in ipairs(SLOTS) do
	local mid = (i - 1) * SEG + SEG / 2
	local a = math.rad(mid)
	local function at(rr, w, h)
		return UDim2.new(0.5, math.sin(a) * rr, 0.5, -math.cos(a) * rr),
			UDim2.fromOffset(math.min(w, wedgeWidth(rr)), h)
	end

	-- Radii pulled in one notch across the board to make room for the odds chip that
	-- now sits at R * 0.90: name 0.76 -> 0.71, value 0.60 -> 0.545, icon 0.40 -> 0.335.
	local p, s = at(R * 0.71, wk(215), wk(42))
	local name = new("TextLabel", {
		Name = "Name" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = p, Size = s,
		BackgroundTransparency = 1, Rotation = mid, Text = slot.Name,
		Font = Enum.Font.FredokaOne, TextScaled = true,
		TextColor3 = slot.Text or Color3.fromRGB(255, 255, 255), ZIndex = 6,
	}, spinner)
	new("UITextSizeConstraint", { MaxTextSize = wk(30) }, name)
	stroke(name, 3)
	tintPrize(name, slot)

	-- SIZE AND RADIUS ARE THE FIX for "too big and overlapping each other". Wedge
	-- width scales with radius -- wedgeWidth(r) is about 0.993 * r with six slots --
	-- so at R * 0.335 (r = 117) the wedge is only 116px across and a 95px chip left
	-- ~10px of clearance per side. Six chips that size, ringed that close to the hub,
	-- visually collide.
	-- 72px at R * 0.36 (r = 126, wedge 125px) leaves ~26px per side: over twice the
	-- gap, and the chip stops competing with the name and payout it belongs to.
	p, s = at(R * 0.36, wk(58), wk(58))
	--[[ NO PLATE BEHIND THE ICON (2026-08-19, owner: "remove the white boxes").

	This was a white candyPanel, and at wheel scale six of them read as stickers
	pasted onto the disc -- white squares breaking six saturated wedges into
	patches. The wedge's own colour is the background now.

	That is what the Name and Value labels a few radii further out have always
	done: white type, ink stroke, straight onto the paint. The icon was the odd
	one out. IconArt's drawings each carry the kit's heavy dark keyline on their
	outer silhouette, so they hold up against any wedge colour without a plate
	underneath -- including the gold crate on the yellow wedge, the closest pair.

	THE FRAME STAYS, transparent: it is the rotation carrier, and popWinner looks
	it up by name to scale it on a landing. It carries Rotation = mid, and the
	holder nested inside carries -mid, because GuiObject.Rotation rotates an
	object AND its descendants together -- giving the holder its own `mid` too
	would double the rotation and skew the drawing. ]]
	local iconChip = new("Frame", {
		Name = "IconChip" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = p, Size = s,
		BackgroundTransparency = 1, BorderSizePixel = 0,
		Rotation = mid, ZIndex = 6,
	}, spinner)
	-- same UIPolish opt-out as the details rows: the bolt glyph is 3-byte UTF-8 and
	-- slips through UIPolish's 4-byte emoji test, coming back white and outlined
	iconChip:SetAttribute("NoPolish", true)
	-- GLYPHS, NOT 3D RENDERS -- reverted 2026-08-18 after three rounds of "the
	-- pictures still look bad".
	--
	-- IconForge builds genuinely nicer art and it holds up when you blow it up, which
	-- is exactly how I kept talking myself into keeping it. It does not survive THIS
	-- slot: a ViewportFrame renders at its own pixel size with no anti-aliasing, and
	-- here that size is ~50px inside a chip which is itself rotated to the wedge
	-- angle. A six-part model at 50px is coloured mush, and the ink outline pass -- a
	-- second render of the whole model sitting behind the first -- shows through
	-- every gap between parts and reads as pieces sliding over one another.
	--
	-- A glyph is font-rendered: hinted, anti-aliased and unmistakable at 50px, which
	-- is the only property that matters at this size. The IconForge builders stay in
	-- that module for any surface big enough to earn them.
	--
	-- Nested in an unrotated holder because the chip carries Rotation = mid and
	-- GuiObject.Rotation rotates descendants WITH it.
	local iconInner = new("Frame", {
		Name = "IconInner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8), BackgroundTransparency = 1, Rotation = -mid, ZIndex = 7,
	}, iconChip)
	-- see paintIcon at the top: drawn art where the slot names some, glyph otherwise
	paintIcon(iconInner, slot, wk(43), 7)
	iconChipsBySlot[i] = iconChip

	-- Back to a one-line box (54 -> 34): the crate no longer lists its contents, so
	-- every value is a single line again and the extra height was only crowding the
	-- icon chip below it. Radial budget at R = 350, all clear of each other:
	--   icon  79..155   value 179..213   name 227..270   odds 296..334   rim 350
	p, s = at(R * 0.56, wk(170), wk(34))
	local val = new("TextLabel", {
		Name = "Val" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = p, Size = s,
		BackgroundTransparency = 1, Rotation = mid, Text = slot.Value,
		Font = Enum.Font.FredokaOne, TextScaled = true,
		TextColor3 = slot.Text or Color3.fromRGB(255, 255, 255), ZIndex = 6,
	}, spinner)
	new("UITextSizeConstraint", { MaxTextSize = wk(21) }, val)
	stroke(val, 2.5)
	tintPrize(val, slot)

	-- ODDS ON THE RIM (2026-08-18, owner: "fix the chances on the outside of the
	-- wheel"). These used to sit at R * 0.205 -- and wedge width scales with radius,
	-- so at that radius each label had about 71px to live in, right where all six
	-- converge on the hub. They piled into an unreadable knot in the middle of the
	-- wheel. At R * 0.90 the same wedge is ~313px wide, which is room for a proper
	-- chip, and the outer band was empty anyway.
	p, s = at(R * 0.90, wk(96), wk(38))
	-- The wheel's OTHER set of white boxes, removed with the icon plates above and
	-- for the same reason. styleOdds below already paints this label white, strokes
	-- it with the kit ink and lays the tier gradient over it -- the same treatment
	-- Name and Value get on the bare wedge -- so the percentage was always carrying
	-- its own readability and the plate behind it was decoration.
	local oddsChip = new("Frame", {
		Name = "Pct" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = p, Size = s,
		BackgroundTransparency = 1, BorderSizePixel = 0,
		Rotation = mid, ZIndex = 7,
	}, spinner)
	local oddsLabel = new("TextLabel", {
		Name = "PctText", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.72), BackgroundTransparency = 1, Rotation = 0,
		Text = oddsTextFor(slot), Font = UITheme.Candy.font, TextScaled = true, ZIndex = 8,
	}, oddsChip)
	new("UITextSizeConstraint", { MaxTextSize = wk(26) }, oddsLabel)
	styleOdds(oddsLabel, slot, 3)
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

-- BUY A SPIN (Robux). Sits BESIDE the spin button rather than under it, on purpose:
-- CLUSTER_H is computed from TITLE/wheel/SPIN/SUB and layoutCluster scales the whole
-- cluster to fit the viewport off that number, so a second row would silently shrink
-- the wheel on every short screen. The cluster is WHEEL_PX + 160 wide and spinBtn is
-- 320 centred, which leaves room on the right at the same Y for free.
--
-- SHOWN AS A PLACEHOLDER while the product does not exist (owner request), rather
-- than hidden. ProductId 0 is the game-wide "not created yet" sentinel (see
-- WheelConfig.PAID_SPIN) and ProductRegistry refuses to register it, so the button
-- genuinely cannot work yet -- but an invisible slot is impossible to design around
-- or to notice you still owe a Product ID. It is therefore drawn in the dead grey
-- the spin button uses on cooldown, so it reads as "not wired up" rather than as a
-- live button that eats clicks, and the Activated handler below says exactly where
-- to paste the id. Fill PAID.ProductId in and it turns green and works, with no
-- other edit anywhere.
local PAID = WheelConfig.PAID_SPIN
local paidLive = WheelConfig.IsPaidSpinLive()
local buyBtn = new("TextButton", {
	Name = "BuySpinBtn", AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 262, 0, TITLE_H + GAP_TITLE + WHEEL_PX + GAP_SPIN),
	Size = UDim2.fromOffset(180, SPIN_H),
	-- "R$" is how Roblox itself writes a Robux price in the purchase prompt this
	-- button opens, so the two agree at a glance.
	Text = ("R$ %d"):format(PAID.RobuxPrice),
	TextScaled = true, ZIndex = 14, Visible = true,
}, cluster)
new("UITextSizeConstraint", { MaxTextSize = 30 }, buyBtn)
if paidLive then
	UITheme.candyButton(buyBtn, Color3.fromRGB(86, 190, 92), Color3.fromRGB(52, 148, 62), 16)
else
	UITheme.candyButton(buyBtn, Color3.fromRGB(150, 154, 164), Color3.fromRGB(110, 114, 124), 16)
	-- a small corner tag, so it is unmistakably a slot waiting on setup and nobody
	-- ships it thinking the grey is a styling choice
	local tag = new("TextLabel", {
		Name = "SetupTag", AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.fromOffset(170, 15),
		BackgroundTransparency = 1, Text = "NEEDS PRODUCT ID",
		Font = Enum.Font.GothamBold, TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 226, 140), ZIndex = 15,
	}, buyBtn)
	new("UITextSizeConstraint", { MaxTextSize = 11 }, tag)
end

-- Activated is wired further down, next to spinBtn's, NOT here: `spinning` is not
-- declared until well below this point, so a closure written here would capture a
-- nil GLOBAL of that name instead of the local and its guard would never fire.

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

-- One definition of the row geometry. These were three separate literals (56 in
-- the row, 64 in the beside-mode height, 56/64 again in the below-mode snap), so
-- resizing a row meant finding all four and the panel clipped its last row when
-- one was missed.
local ROW_H = 60                  -- a details row
local ROW_PITCH = ROW_H + 8       -- + the UIListLayout padding above

local rarestFirst = {}
for i = 1, N do rarestFirst[i] = i end
table.sort(rarestFirst, function(a, b) return SLOTS[a].Weight < SLOTS[b].Weight end)

for order, slotIdx in ipairs(rarestFirst) do
	local slot = SLOTS[slotIdx]
	-- INSET BY THE STROKE WIDTH. DetailsPanel has ClipsDescendants = true and a
	-- candyPanel UIStroke is ApplyStrokeMode.Border -- it draws OUTSIDE the frame.
	-- At the panel's full width the left and right of every row's outline fell
	-- outside the clip and was cut off, which is what made the corners read as
	-- chopped and squared rather than rounded. CANDY.stroke is 3, so -8 clears it
	-- on both sides with a pixel to spare.
	local row = new("Frame", {
		Name = "Row" .. slotIdx, LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, ROW_H), ZIndex = 14,
	}, detailsPanel)
	UITheme.candyPanel(row, 14)

	-- ONE tinted tile, not a swatch stripe plus a white chip. candyPanel'd, the chip
	-- was a white panel with its own 3px ink border sitting on a white panel with a
	-- 3px ink border -- two competing outlines, and a 12px radius on a 44px box is a
	-- tight enough curve that Roblox's stroke renderer visibly steps around it. The
	-- tile now carries the wedge's colour itself, which is what the separate stripe
	-- was for, so the row loses a shape and both rough outlines at once.
	local chip = new("Frame", {
		Name = "Chip", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(44, 44), BorderSizePixel = 0,
		BackgroundColor3 = slot.Colour:Lerp(Color3.new(1, 1, 1), 0.58), ZIndex = 15,
	}, row)
	new("UICorner", { CornerRadius = UDim.new(0, 9) }, chip)
	-- NoPolish: UIPolish recolours and outlines text, and exempts emoji by testing
	-- for a 4-byte UTF-8 lead byte. The bolt is U+26A1 -- THREE bytes -- so it slips
	-- through that test and comes back white with a stroke smeared over it while the
	-- other five render normally. Tagging the tile opts the whole subtree out and
	-- does not depend on which glyph a slot happens to use.
	chip:SetAttribute("NoPolish", true)
	-- the same ICON RULE the wedge uses -- glyph or drawn art, decided once in
	-- paintIcon -- so the list and the wheel are visibly the same six prizes rather
	-- than two unrelated sets of pictures
	-- Its own inset holder, matching the wedge chip's: paintIcon fills whatever it
	-- is given, so the 0.8 inset the glyph has always had lives here rather than in
	-- the shared helper, and a drawn icon lands with the same margin.
	local listIcon = new("Frame", {
		Name = "IconInner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8), BackgroundTransparency = 1, ZIndex = 16,
	}, chip)
	paintIcon(listIcon, slot, 34, 16)

	-- Label, not Value. Value is written for the WEDGE, where it can run to three
	-- lines (the loot crate does) -- poured into a 22px row it scaled down to
	-- nothing. Label is the one-line name of the same prize.
	local rowPayout = new("TextLabel", {
		Name = "Payout", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 71, 0.31, 0),
		Size = UDim2.new(1, -79, 0, 24), BackgroundTransparency = 1, Text = slot.Label,
		Font = UITheme.Candy.font, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UITheme.Candy.ink, ZIndex = 15,
	}, row)
	-- the list carries the same tiering as the wheel. It needs its OWN outline
	-- first: unlike the wedge labels this one is plain ink text on a white card, so
	-- a bright gradient would have nothing to sit against.
	if slot.OddsStyle then
		new("UIStroke", {
			Color = UITheme.Candy.ink, Thickness = 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, LineJoinMode = Enum.LineJoinMode.Round,
		}, rowPayout)
		tintPrize(rowPayout, slot)
	end
	local rowOdds = new("TextLabel", {
		Name = "Odds", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 71, 0.76, 0),
		Size = UDim2.new(1, -79, 0, 19), BackgroundTransparency = 1,
		-- the long form here: this panel is the one place with room for "(1 in 100)",
		-- and on a 1% prize that phrasing lands far harder than "1%"
		Text = WheelConfig.OddsText(slot),
		Font = UITheme.Candy.font, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 15,
	}, row)
	-- same tiering as the wheel's rim chips, so the two readouts of the same number
	-- do not disagree about how rare it is
	if slot.OddsStyle then
		styleOdds(rowOdds, slot, 2)
	else
		rowOdds.TextColor3 = Color3.fromRGB(96, 102, 116)
	end
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
		-- ROW_PITCH, not a literal: rows grew 56 -> 60 with the 2026-08-18 cleanup and
		-- this panel ClipsDescendants, so a stale pitch silently guillotines the last
		-- row instead of erroring.
		detailsPanel.Size = UDim2.fromOffset(DETAILS_W, math.min(N * ROW_PITCH, vh - BOTTOM_HUD_RESERVE - 20))
	else
		detailsPanel.AnchorPoint = Vector2.new(0.5, 0)
		detailsPanel.Position = UDim2.new(0, centerX, 0, clusterBottom + 16)
		-- floor of 50 (not just clamped to >=0): DETAILS_BELOW_RESERVE above keeps
		-- this comfortably positive in practice, but never let a tight/unusual
		-- viewport hand this a negative Size.Y -- see the reserve's own comment.
		-- Bottom bound is (vh - DETAILS_BOTTOM_RESERVE), NOT vh, so this clears
		-- the native hotbar / Bag / Sprint row AND LuckHUDClient's luck chip.
		local h = math.max(50, math.min(N * ROW_PITCH, (vh - DETAILS_BOTTOM_RESERVE) - clusterBottom - 16))
		-- Snap to whole rows (ROW_H row + 8px list padding = ROW_PITCH per extra row)
		-- so ClipsDescendants never leaves the last visible row half-cut.
		if h >= ROW_H then h = ROW_H + math.floor((h - ROW_H) / ROW_PITCH) * ROW_PITCH end
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
--
-- UIKIT (Task 10): the Settings panel now ALSO offers this same preference
-- (GameHUDPanels.SettingsPanel, GAMEPLAY section) and persists it into
-- data.Settings.fastSpin server-side. Since this script is a LocalScript
-- (returns nothing -- nothing can require() it to reach `fastSpin`
-- directly), the bridge is a client-local Instance Attribute on the
-- player: `FastSpinPref`. This toggle button and the Settings row both
-- read/write the SAME attribute now, so whichever one the player uses stays
-- in sync with the other -- `fastSpin` is just a cached mirror of the
-- attribute, updated exclusively through the listener below (single write
-- path, no drift between the two controls).
local fastSpin = player:GetAttribute("FastSpinPref") == true
local FAST_OFF_1, FAST_OFF_2 = Color3.fromRGB(150, 154, 164), Color3.fromRGB(110, 114, 124)
-- act/active = green family; gold is reserved for real-money (Robux) surfaces.
-- Same pair the ready-state SPIN button uses, so ON reads as "active", not "paid".
local FAST_ON_1,  FAST_ON_2  = UITheme.Candy.green1, UITheme.Candy.green2

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

-- UIKIT (Task 10): single render function, shared by the click handler AND
-- the attribute listener below, so a change from EITHER source (this
-- button, or the Settings panel) repaints the same way.
local function applyFastSpinVisual(on)
	if on then
		fastToggle.Text = "FAST SPIN: ON"
		UITheme.setColors(fastToggle, FAST_ON_1, FAST_ON_2)
	else
		fastToggle.Text = "FAST SPIN: OFF"
		UITheme.setColors(fastToggle, FAST_OFF_1, FAST_OFF_2)
	end
end
applyFastSpinVisual(fastSpin)

fastToggle.Activated:Connect(function()
	player:SetAttribute("FastSpinPref", not fastSpin)
end)

-- Single write path for `fastSpin`: BOTH this button and SettingsPanel only
-- ever set the attribute, never this local directly -- this listener is the
-- one place `fastSpin` itself changes.
player:GetAttributeChangedSignal("FastSpinPref"):Connect(function()
	fastSpin = player:GetAttribute("FastSpinPref") == true
	applyFastSpinVisual(fastSpin)
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
-- The loot crate's contents, parked here between the two remotes that deliver a
-- win: WheelState carries the manifest (per-player -- see WheelHandler), and it
-- lands while the wheel is still turning, seconds before WheelSpun's landing
-- callback is ready to use it.
local pendingReveal = nil
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
	-- The paid spin stays available ON cooldown -- skipping the wait is the entire
	-- thing being sold -- and is only suppressed mid-spin so two cannot overlap.
	-- hidden only mid-spin; the placeholder stays on screen the rest of the time
	buyBtn.Visible = not spinning
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
-- Blur-never-dim: instant world blur while the wheel is up. The old 0.45 black
-- wash was cut on request; this restores the SEPARATION the shipped grammar
-- uses everywhere (backdrop blur, never a dark dim). Driven off root.Visible
-- rather than setOpen because SideRail's single-open force-closes this surface
-- by writing root.Visible directly -- a setOpen-only toggle would strand the
-- blur on. NEVER tween a BlurEffect (TweenService silently no-ops on
-- non-GuiObjects in this place): create at full Size, destroy on close.
local function setWheelBlur(on)
	local Lighting = game:GetService("Lighting")
	local existing = Lighting:FindFirstChild("WheelBlur")
	if on and not existing then
		local blur = Instance.new("BlurEffect")
		blur.Name = "WheelBlur"
		blur.Size = 10
		blur.Parent = Lighting
	elseif not on and existing then
		existing:Destroy()
	end
end
local isOpen = false
-- One watcher, two jobs, and it MUST sit BELOW the isOpen declaration (this
-- file's own note: a local declared later in the scope is not captured and
-- silently resolves as a nil global):
--   1. blur follows the surface's true visibility;
--   2. LATENT DESYNC FIX (round-8 audit): SideRail's single-open force-closes
--      this surface by writing root.Visible directly, so setOpen never ran and
--      isOpen stayed true -- the next SpinPrompt press early-returned and the
--      wheel was dead until the player walked out past FAR. Keeping the latch
--      synced here makes every out-of-band hide recoverable.
root:GetPropertyChangedSignal("Visible"):Connect(function()
	setWheelBlur(root.Visible)
	isOpen = root.Visible
end)
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

-- Deliberately NOT gated on `cooldown`: skipping the wait is the thing being sold.
buyBtn.Activated:Connect(function()
	if spinning then return end
	if not WheelConfig.IsPaidSpinLive() then
		-- The placeholder is deliberately clickable so this message is reachable --
		-- silently swallowing the click is how a half-configured product survives to
		-- release.
		showResult("Robux spin is not set up yet", Color3.fromRGB(255, 214, 120))
		warn("[WheelClient] paid spin has no Product ID. Create a DEVELOPER PRODUCT "
			.. ("priced R$%d on the Creator Dashboard, then paste its id over the 0 in ")
				:format(PAID.RobuxPrice)
			.. "ReplicatedStorage.Modules.WheelConfig -> PAID_SPIN.ProductId. "
			.. "It must be a developer product, not a game pass -- a pass fires no "
			.. "ProcessReceipt and would take the Robux without granting the spin.")
		return
	end
	-- Nothing is granted here. The purchase goes to Roblox and the spin happens only
	-- server-side, in ProductRegistry's receipt handler -- so a client that fakes this
	-- click, or a player who cancels the prompt, is paid nothing. There is also no
	-- `spinning = true` here: the wheel starts turning when the SERVER answers with a
	-- result, which for a purchase is after Roblox confirms the receipt.
	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, PAID.ProductId)
	end)
	if not ok then warn("[WheelClient] PromptProductPurchase failed: " .. tostring(err)) end
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
			-- walk-over auto-open removed (user request 2026-08-03): the wheel now
			-- opens ONLY via its SpinPrompt (E / click). Walking away still closes it.
			if d > FAR then
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
	local slot = SLOTS[index]
	local mine = (whoName == player.Name)
	spin(index, function()
		-- THE CRATE OPENS INSTEAD OF TOASTING, and only for whoever won it. A one
		-- line banner cannot carry $2.5M, 200 emeralds and five hatched pets, which
		-- is the whole reason the wedge stopped printing its own contents.
		--
		-- Bystanders keep the banner: the manifest is on the per-player state remote
		-- and they never receive one. The `pendingReveal` guard is belt and braces --
		-- the payload arrives seconds before this callback, while the wheel is still
		-- turning -- so a crate that somehow has no manifest falls through to the
		-- banner rather than opening an empty chest.
		if mine and slot.Crate and pendingReveal then
			local rows = pendingReveal
			pendingReveal = nil
			-- The wheel goes first: the ceremony is a full-screen takeover, and the
			-- wheel left up behind its own backdrop blur reads as two panels stacked.
			setOpen(false)
			if CrateCeremony.play({
				Rows = rows, Title = slot.Label or slot.Name,
				-- Tells the server the chest is done with, which is what releases the
				-- crate's eggs to the egg shop's hatch ceremony. Resolved HERE rather
				-- than at load: the remote is created by WheelHandler.Init, and a
				-- WaitForChild at the top of this file would be one more thing that can
				-- stall the whole wheel on a slow boot for a signal used once a spin.
				OnFinished = function()
					local done = remotes:FindFirstChild("WheelCrateDone")
					if done then done:FireServer() end
				end,
			}) then
				return
			end
			-- refused to start (one already playing, or no PlayerGui yet): fall through
			-- and say it the old way rather than paying out nothing visible at all
		end
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
	-- Held, not used: the wheel has seven and a half seconds of spinning to do
	-- before the landing callback wants this.
	if type(s.Reveal) == "table" and #s.Reveal > 0 then pendingReveal = s.Reveal end
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

--============================= free-spin marker ============================--
--[[ A red "!" floating over the wheel while YOUR daily spin is ready.

PER-PLAYER, which is why it is built here and not in WheelBoard alongside the
rest of the wheel. Everything on that model is server-built and therefore the
same for everyone -- the headboard countdown included, and that one shows the
SHORTEST cooldown of anyone online (WheelHandler.refreshSign), so "FREE SPIN
READY" on the sign can perfectly well mean somebody else's spin. This marker
reads this player's own WheelState, so it is never wrong about whose.

Parented to PlayerGui with an Adornee rather than into the model: a
LAYOUT_VERSION bump DESTROYS and rebuilds the wheel (WheelBoard.buildSite), and
a badge living inside it would go with it -- the watcher below re-attaches to
whatever model turns up instead. ResetOnSpawn = false is the same hazard on the
other axis: PlayerGui clears resetting LayerCollectors on every respawn, and
`claimed` would then never let this one be rebuilt.

NoPolish is load-bearing, not decoration. UIPolish force-whitens every
unexempted label under PlayerGui, so without it the red "!" is a white "!" --
and it fails SILENTLY, because the marker still appears, just in the wrong
colour. Exempt gets it the whole way through: the fill is saturated, which is
the branch UIPolish's readability floor leaves alone as a deliberate colour.

BOTH wheels get one -- valley and tundra. The cooldown is per player, not per
wheel, so the marker has to be waiting at whichever one you walk up to. ]]
do
	local READY_RED = Color3.fromRGB(255, 58, 58)
	local FLOAT_Y   = 3.4        -- studs above CallAnchor, clearing the SPIN call-out
	-- Studs, so this shrinks with distance -- which means it has to be sized for the
	-- FAR end of MaxDistance, not for how it looks standing at the wheel. 4.2 studs
	-- is ~16px tall at 150 studs (a red tick you notice across the plaza) and ~95px
	-- walking up, against the fixed-pixel SPIN call-out it sits above.
	local W, H      = 3.0, 4.2

	-- `cooldown` is 0 until the first WheelState lands, and 0 reads as READY -- so
	-- without this the marker is up for the first few seconds of every session
	-- whether the spin is banked or not (the server's own first send is on a 3s
	-- delay). Connected here rather than folded into the handler above so the whole
	-- marker stays inside this block, and last, so it always runs after `cooldown`
	-- has been written.
	local synced = false
	stateRemote.OnClientEvent:Connect(function(s)
		if type(s) == "table" then synced = true end
	end)

	local badges  = {}   -- [model] = { bb, mark, st, model }
	local claimed = {}   -- [model] = true, taken BEFORE the first yield in attach()

	-- CallAnchor is WheelBoard's own float point above the wheel; the fallbacks
	-- cover a model built before it existed. Returns nil while the wheel's parts
	-- are streamed out, which is a normal state, not a failure -- see the update
	-- loop, which is what calls this.
	local function anchorFor(model)
		return model:FindFirstChild("CallAnchor")
			or model:FindFirstChild("Sign") or model.PrimaryPart
	end

	local function attach(model)
		-- Claimed up front: the initial sweep and ChildAdded can both land on the
		-- same model, and every guard after this point is on the far side of a yield.
		if claimed[model] then return end
		claimed[model] = true
		model.Destroying:Connect(function()
			local b = badges[model]
			if b then b.bb:Destroy() end
			badges[model], claimed[model] = nil, nil
		end)
		local pg = player:WaitForChild("PlayerGui", 20)
		if not (pg and model.Parent) then claimed[model] = nil; return end
		-- Adornee is left nil here and resolved by the update loop instead. Under
		-- StreamingEnabled a wheel's PARTS are absent until you are near it -- the
		-- model replicates, its contents do not -- so waiting on CallAnchor at attach
		-- time times out on every wheel except the one you spawned beside, and the
		-- tundra wheel then never gets a marker no matter how close you walk. Measured
		-- exactly that: 1 badge built, 2 wheels in the client's Workspace.
		local bb = new("BillboardGui", {
			Name = "SpinReadyBadge", Enabled = false,
			-- Scale, not Offset: a studs-sized billboard shrinks with distance like
			-- everything else in the world, instead of pinning itself over it at a
			-- fixed pixel size -- which is the exact complaint the CallOut sitting
			-- just below it was retuned for.
			Size = UDim2.fromScale(W, H),
			StudsOffsetWorldSpace = Vector3.new(0, FLOAT_Y, 0),
			AlwaysOnTop = false, MaxDistance = 150, ResetOnSpawn = false,
		}, pg)
		bb:SetAttribute("NoPolish", true)
		local mark = new("TextLabel", {
			Name = "Mark", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
			Text = "!", TextColor3 = READY_RED, Font = Enum.Font.FredokaOne,
			TextScaled = true, TextStrokeTransparency = 1,
		}, bb)
		stroke(mark, 4)
		badges[model] = { bb = bb, mark = mark, model = model,
			st = mark:FindFirstChildOfClass("UIStroke") }
	end

	task.spawn(function()
		local gw = Workspace:WaitForChild("GameWorld", 30)
		if not gw then return end
		-- Prefix, not equality: DailyWheel and DailyWheelTundra (WheelBoard.SITES).
		-- resolveWorld above deliberately tracks only the valley wheel -- it drives
		-- the prop's spin animation -- but a marker that only ever appeared in world
		-- 1 would be worse than none in world 2.
		local function consider(c)
			if c:IsA("Model") and c.Name:sub(1, 10) == "DailyWheel" then
				task.spawn(attach, c)
			end
		end
		gw.ChildAdded:Connect(consider)
		for _, c in ipairs(gw:GetChildren()) do consider(c) end
	end)

	-- Down while the panel is open or a spin is running: you are already looking at
	-- the answer, and a marker still shouting READY over a wheel mid-spin is the
	-- badge lying about a state it has not caught up with.
	local t0, nextResolve = os.clock(), 0
	RunService.Heartbeat:Connect(function()
		local ready = synced and cooldown <= 0 and not spinning and not isOpen
		local el = os.clock() - t0
		-- RE-RESOLVED, not resolved once: streaming removes the wheel's parts when
		-- you walk away and streams back NEW instances when you return, so an Adornee
		-- captured at attach time is a dead reference on the second visit -- and a
		-- dead Adornee renders nothing at all, silently. Throttled because the answer
		-- only changes on a stream event.
		local resolve = el >= nextResolve
		if resolve then nextResolve = el + 0.5 end
		for _, b in pairs(badges) do
			local a = b.bb.Adornee
			if resolve and (not a or not a.Parent) then
				a = anchorFor(b.model)
				b.bb.Adornee = a
			end
			local show = ready and a ~= nil
			if b.bb.Enabled ~= show then b.bb.Enabled = show end
			if show then
				-- slow bob + a small breath, so it reads as "come here" rather than as
				-- one more static prop bolted to the wheel
				local k = 1 + math.sin(el * 3.2) * 0.06
				b.bb.Size = UDim2.fromScale(W * k, H * k)
				b.bb.StudsOffsetWorldSpace =
					Vector3.new(0, FLOAT_Y + math.sin(el * 2.0) * 0.26, 0)
				-- UIStroke.Thickness is in PIXELS while the billboard is in STUDS, so a
				-- fixed keyline is a hairline up close and a red blob at 150 studs.
				-- Tracked off the glyph's own on-screen size instead.
				if b.st then
					b.st.Thickness = math.clamp(b.mark.AbsoluteSize.Y * 0.05, 1.2, 6)
				end
			end
		end
	end)
end
