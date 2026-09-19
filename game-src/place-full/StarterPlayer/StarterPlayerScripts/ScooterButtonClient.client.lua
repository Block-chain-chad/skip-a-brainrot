--[[ ============================================================================
ScooterButtonClient -- the VIP scooter tab: ALWAYS on screen, and the only way on
or off the scooter.

THREE STATES, one tab (owner, 2026-08-22):
  don't own VIP   gold "VIP" pill, the scooter greyed out. Clicking opens the
                  Roblox purchase prompt for the VIP pass.
  own it, parked  green "RIDE" pill, scooter in its real colours.
  own it, riding  blue "PARK" pill, plus the nav rail's glow rings.

IT IS NO LONGER HIDDEN FOR NON-OWNERS. It used to vanish entirely without VIP;
now it is a permanent tab that advertises the scooter and sells it, which is why
the not-owned state gets the house's PURCHASABLE GOLD (the same gold the bag's
locked pet slots and the SHOP tab wear) rather than a dead grey.

THE STYLE IS THE NAV RAIL'S, deliberately. Those tiles are a FLOATING 3D icon
with a coloured caption pill under it and NO background plate -- the plate and
caption in GameHUDClient's rail code are both left undrawn (RAIL_PLATE_DRAWN =
false) because each tile's whole look, icon and caption ribbon together, is baked
into one image asset. Those assets cannot be matched without commissioning a
scooter to go with them, so this builds the same GRAMMAR from primitives: no
plate, a real 3D scooter floating where their render sits, and a rounded caption
pill beneath in the same white-on-colour with a heavy ink outline.
(An earlier pass used a solid rounded plate; side by side at 3.4x against BAG,
SHOP and REBIRTH it read as a boxy odd-one-out, which is what this replaces.)

THIS IS THE ONLY WAY TO EQUIP, because this script also switches the Roblox
CoreGui BACKPACK off -- so the scooter cannot be equipped from the inventory or
by pressing 1.

  THAT IS SAFE HERE, AND ONLY HERE, because the scooter is the ONLY Tool in the
  game -- Instance.new("Tool") appears exactly once, in ScooterService. The
  fishing rod (RodService) and rock sling (RockSlingService) are WELDED PROPS,
  not Tools, so nothing else ever needed the backpack. IF A SECOND REAL TOOL IS
  EVER ADDED, this has to be revisited or that tool becomes unequippable.

  IT IS RE-ASSERTED, not set once. EggShopClient runs
  SetCoreGuiEnabled(CoreGuiType.All, true) when its shop closes, which switches
  the backpack back ON -- so a one-shot disable silently comes undone the first
  time a player cracks an egg. The poll owns this and puts it back, writing only
  when it reads wrong. (MerchantDialog also toggles it, but restores the PREVIOUS
  value, so it agrees with whatever this last set.)

OWNERSHIP IS ASKED TWO WAYS, and either one saying yes is enough:
  1. the Tool exists   -- ScooterService only grants it to a pass holder, so its
     presence is the server's own word and needs no round trip;
  2. UserOwnsGamePassAsync -- because (1) lands a few seconds AFTER join (the
     pass cache refreshes async), and for those seconds a real VIP would other-
     wise be shown the gold BUY state and could be prompted to buy what they
     already own.
Re-asked when a purchase completes, so buying it flips the tab without a rejoin.

EQUIPPING FROM THE CLIENT IS CORRECT, not a shortcut: a player has network
ownership of their own character, and Humanoid:EquipTool / :UnequipTools is what
Roblox's own backpack does. ScooterService's Tool.Equipped/Unequipped handlers
still do the real work server-side (weld the prop, set ScooterOn).

WHY A SEPARATE SCRIPT rather than lines in ClientMain: ClientMain sits a handful
of locals under Luau's 200-register ceiling, and "Out of local registers" is a
COMPILE error that takes the whole client HUD down with it.
============================================================================ ]]
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- MUST MATCH ScooterService.TOOL_NAME, and GamepassConfig's VIP entry. Both are
-- stated once, here, so a rename fails visibly in one place.
local TOOL_NAME = "Electric Scooter"
local RIDING_ATTR = "ScooterOn"
local VIP_GAMEPASS_ID = 1940899409

local CARD_W, CARD_H = 92, 104
local PILL_W, PILL_H_ = 84, 27
local EDGE_PAD = 16               -- matches Sprint and the luck chip exactly
local GAP = 8
-- LEGACY FALLBACK ONLY (2026-08-26). These three numbers were a hand-copy of
-- LuckHUDClient's private geometry -- "LUCK_BOTTOM is LuckHUDClient's own
-- (1, -78)" -- kept in sync by hand so this card would land above that chip.
-- That is the coupling that made the bottom-right corner unfixable: retuning the
-- luck chip silently moved this card, and correcting this card was overwritten
-- the next time LuckHUD re-seated itself. With HUD_LAYOUT_V2 on, both declare a
-- slot in one stack and neither knows the other exists. Retained only so the
-- flag-off path still renders where it always did.
local LUCK_BOTTOM, LUCK_H, PILL_H = 78, 34, 34
local PILL_BAND = PILL_H + GAP

local INK = Color3.fromRGB(23, 19, 16)
local GLOW = Color3.fromRGB(99, 222, 67)
-- caption pill per state, taken from UITheme.Camp so they match the rest of the HUD
local GOLD = { Color3.fromRGB(255, 216, 107), Color3.fromRGB(240, 150, 30) }
local GREEN = { Color3.fromRGB(96, 222, 128), Color3.fromRGB(46, 176, 88) }
local BLUE = { Color3.fromRGB(96, 182, 255), Color3.fromRGB(30, 127, 219) }
-- The BACKDROP behind the icon (owner, 2026-08-22: "give it some more
-- character"). The rail's own REBIRTH tile is exactly this shape -- a coloured
-- medallion with the icon on it and a caption pill underneath -- so a backdrop
-- is on-grammar rather than a departure from it. It also fixes a real contrast
-- problem: the scooter is navy and cyan, which is drab next to BAG's red or
-- SHOP's stripes, and it had nothing behind it to sit against.
local DECK_TOP, DECK_BOT = Color3.fromRGB(196, 150, 255), Color3.fromRGB(116, 62, 214)
-- a violet-tinted grey, so locked reads as the SAME medallion drained rather than
-- as a different component
local DECK_TOP_OFF, DECK_BOT_OFF = Color3.fromRGB(166, 160, 182), Color3.fromRGB(106, 100, 124)
-- the scooter's own paint, from ScooterService, and its locked greyscale
-- Lighter than ScooterService's real 34,38,48 on purpose -- see the note by the rig.
local BODY, TRIM, RUBBER = Color3.fromRGB(64, 72, 92), Color3.fromRGB(90, 225, 255), Color3.fromRGB(20, 20, 22)
local BODY_OFF, TRIM_OFF, RUBBER_OFF = Color3.fromRGB(112, 118, 130), Color3.fromRGB(150, 156, 166), Color3.fromRGB(70, 72, 78)

---------------------------------------------------------------- shell
-- Default screen insets, exactly like LuckHUD: a child's Y OFFSET is then its
-- AbsolutePosition.Y, which is what lets the cross-gui stacking maths below stay
-- in one coordinate frame. Do not set IgnoreGuiInset here.
local HudLayout = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("HudLayout"))
local Platform = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Platform"))

-- DEVICE SIZE FOR THIS CARD (2026-08-27).
--
-- The card is authored 92x104, which is 30% of the usable HEIGHT of a handset --
-- for one optional control, in a corner that also has to hold Sprint and HIDE UI.
-- Measured on a real 867x399 device before this: the bottom-right column wanted
-- roughly 200px of a 229px band.
--
-- ONE UIScale does double duty here, deliberately: only one applies per object,
-- and `scale` is already the hover/press tween's target. So the device factor
-- lives in the same scale and every tween multiplies by it rather than tweening
-- to a bare 1 -- the same pattern the offer panels use for their fitScale, and
-- for the same reason: a tween to 1 would silently undo the device sizing on the
-- first hover.
local function deviceK(): number
	if not Platform.IsPhone then
		return Platform.IsTablet and 0.85 or 1
	end
	-- SIZED AGAINST THE BAND IT HAS TO SHARE, not a flat constant.
	--
	-- A fixed 0.62 fitted the handset this was measured on and overflowed the one
	-- below it: the bottom-right column needed 184px of a 167px band at 667x375,
	-- while the same column had 191px to play with at 867x399. The card is the only
	-- member with any give -- Sprint and HIDE UI are both already at the 44px touch
	-- floor -- so it is the one that has to yield, and by however much THIS screen
	-- requires rather than by a number that happened to work once.
	--
	-- Never below the touch floor: if 30% of the band cannot hold a tappable card,
	-- the answer is to move the card out of the corner, not to ship one too small
	-- to press. HudAudit's STACK OVER check is what catches that if it ever happens.
	local si = Platform.Insets()
	local band = Platform.Viewport.Y - si.Top - math.max(si.Bottom, Platform.TouchCorner())
	local want = (band * 0.30) / CARD_H
	-- The floor is set by the card's NARROW axis. Guarding only the height let the
	-- 92x104 card shrink to 40x45 at 800x360 -- tall enough to pass, four px too
	-- narrow to press.
	local floor = HudLayout.MIN_TOUCH / math.min(CARD_W, CARD_H)
	return math.clamp(want, floor, 0.62)
end

local gui = Instance.new("ScreenGui")
gui.Name = "ScooterUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 7
gui.Parent = playerGui
HudLayout.PrepareGui(gui, "HUD")

local slot = Instance.new("Frame")
slot.Name = "ScooterTab"
slot.AnchorPoint = Vector2.new(1, 1)
-- AnchorPoint is (1, 1), so this Y is the card's BOTTOM edge measured up from the
-- gui's bottom: clear the luck chip, then the HIDE UI pill, then one gap.
-- Legacy value; HudLayout overwrites it on the first pass when V2 is on.
slot.Position = UDim2.new(1, -EDGE_PAD, 1, -(LUCK_BOTTOM + LUCK_H + GAP + PILL_H + GAP))
slot.Size = UDim2.fromOffset(CARD_W, CARD_H)
slot.BackgroundTransparency = 1
slot.ZIndex = 30
slot.Parent = gui

-- Declares WHERE, not a pixel offset: third up the bottom-right stack, above the
-- HIDE UI pill and the luck chip. Hiding it (VIP gate) closes the gap for free.
local rideSlot = HudLayout.Attach(slot, {
	stack = "BottomRight",
	order = HudLayout.Order.Ride,
})

local scale = Instance.new("UIScale")
scale.Parent = slot
Platform.Watch(function()
	scale.Scale = deviceK()

	-- RIDE LEAVES THE CORNER ON A SHORT PHONE (2026-08-26, owner capture).
	--
	-- BottomRight is the strip between the topbar and the jump button. On the
	-- owner's 700x310 handset that is 134px, and the three controls in it need 160:
	-- this card is 50 tall (it is the only non-pill of the three, so the 44px touch
	-- floor lands on its narrow axis and forces 50 on the other), plus Sprint 44,
	-- plus HIDE UI 44, plus gaps and pad. It overflowed by 26px, which is what the
	-- owner saw as the right-hand cluster being too big.
	--
	-- Nothing shrinks out of this: three controls at Roblox's 44px minimum simply
	-- do not fit in 134px, so one has to move. RIDE is the one -- it is an
	-- occasional mount toggle, where HIDE UI and Sprint are both reached for mid-
	-- play and want to stay under the thumb that is already on the jump button.
	-- BottomCentre sits between the two thumb corners and is otherwise near empty.
	--
	-- The audits could not see any of this: the shortest device they walked was 360
	-- tall, where the same column has 165px and all three fit with 5 to spare.
	if rideSlot then
		rideSlot:SetStack(Platform.IsShortPhone() and "BottomCentre" or "BottomRight")
	end
end)

-- STAND DOWN WHILE A PANEL IS OPEN -- PHONE ONLY (round 2.5, 2026-09-19). The
-- same contract HIDE UI, the luck chip and Sprint keep: on a phone every panel
-- (GameHUD's and the legacy shops') runs near-fullscreen, and this tab was drawn
-- across the egg shop's right edge. SideRail publishes RailPanelOpen on the
-- player for every registered panel. Desktop is untouched -- the tab is the
-- permanent VIP advertisement there and nothing runs into it.
local function syncPanelYield()
	slot.Visible = not (Platform.IsPhone and player:GetAttribute("RailPanelOpen") == true)
end
player:GetAttributeChangedSignal("RailPanelOpen"):Connect(syncPanelYield)
Platform.Watch(syncPanelYield)

-- the rail's four concentric ActiveGlow rings, shown only while riding
local glowHost = Instance.new("Frame")
glowHost.Name = "ActiveGlow"
glowHost.AnchorPoint = Vector2.new(0.5, 0.5)
glowHost.Position = UDim2.new(0.5, 0, 0.5, -10)
glowHost.Size = UDim2.fromScale(1.35, 1.05)
glowHost.BackgroundTransparency = 1
glowHost.Visible = false
glowHost.ZIndex = 30
glowHost.Parent = slot
for i, spec in ipairs({ { 0.98, 0.74 }, { 0.84, 0.58 }, { 0.68, 0.42 }, { 0.52, 0.26 } }) do
	local ring = Instance.new("Frame")
	ring.Name = "Ring" .. i
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(spec[1], spec[1])
	ring.BackgroundColor3 = GLOW
	ring.BackgroundTransparency = spec[2]
	ring.BorderSizePixel = 0
	ring.ZIndex = 30
	ring.Parent = glowHost
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(0, 999)
	rc.Parent = ring
end

---------------------------------------------------------------- the backdrop
-- Sits BEHIND the ViewportFrame (ZIndex 31/32 against the icon's 33) and inside
-- the icon band only -- the caption pill keeps its own ground below. Rounded
-- hard, not a square plate: an earlier build used a full-tile rectangular plate
-- and read as a boxy odd-one-out next to the rail's tiles.
local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.AnchorPoint = Vector2.new(0.5, 0.5)
backdrop.Position = UDim2.new(0.5, 0, 0, math.floor((CARD_H - PILL_H_ - 4) / 2))
backdrop.Size = UDim2.fromOffset(CARD_W - 6, CARD_H - PILL_H_ - 10)
backdrop.BackgroundColor3 = DECK_TOP
backdrop.BorderSizePixel = 0
backdrop.ZIndex = 31
backdrop.Parent = slot
local bdCorner = Instance.new("UICorner")
bdCorner.CornerRadius = UDim.new(0, 20)
bdCorner.Parent = backdrop
local bdGrad = Instance.new("UIGradient")
bdGrad.Rotation = 90
bdGrad.Color = ColorSequence.new(DECK_TOP, DECK_BOT)
bdGrad.Parent = backdrop
local bdInk = Instance.new("UIStroke")
bdInk.Color = INK
bdInk.Thickness = 3
bdInk.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
bdInk.Parent = backdrop

-- a soft lighter pool in the middle, so the medallion has depth instead of
-- reading as one flat swatch, and the dark scooter has something to sit against
local pool = Instance.new("Frame")
pool.Name = "Pool"
pool.AnchorPoint = Vector2.new(0.5, 0.5)
pool.Position = UDim2.fromScale(0.5, 0.56)
pool.Size = UDim2.fromScale(0.82, 0.72)
pool.BackgroundColor3 = Color3.new(1, 1, 1)
pool.BackgroundTransparency = 0.55
pool.BorderSizePixel = 0
pool.ZIndex = 32
pool.Parent = backdrop
local poolCorner = Instance.new("UICorner")
poolCorner.CornerRadius = UDim.new(0, 999)
poolCorner.Parent = pool

-- gloss cap across the top, the same highlight the sprint button carries
local bdGloss = Instance.new("Frame")
bdGloss.Name = "Gloss"
bdGloss.AnchorPoint = Vector2.new(0.5, 0)
bdGloss.Position = UDim2.new(0.5, 0, 0, 4)
bdGloss.Size = UDim2.new(1, -12, 0.42, 0)
bdGloss.BackgroundColor3 = Color3.new(1, 1, 1)
bdGloss.BorderSizePixel = 0
bdGloss.ZIndex = 32
bdGloss.Parent = backdrop
local bdGlossCorner = Instance.new("UICorner")
bdGlossCorner.CornerRadius = UDim.new(0, 14)
bdGlossCorner.Parent = bdGloss
local bdGlossGrad = Instance.new("UIGradient")
bdGlossGrad.Rotation = 90
bdGlossGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.55),
	NumberSequenceKeypoint.new(1, 1),
})
bdGlossGrad.Parent = bdGloss

-- three sparkles, deterministic positions -- pure character, and the one thing
-- here that is not load-bearing
for i, s in ipairs({ { 0.14, 0.20, 7 }, { 0.86, 0.30, 5 }, { 0.78, 0.80, 4 } }) do
	local star = Instance.new("Frame")
	star.Name = "Sparkle" .. i
	star.AnchorPoint = Vector2.new(0.5, 0.5)
	star.Position = UDim2.fromScale(s[1], s[2])
	star.Size = UDim2.fromOffset(s[3], s[3])
	star.Rotation = 45
	star.BackgroundColor3 = Color3.new(1, 1, 1)
	star.BackgroundTransparency = 0.25
	star.BorderSizePixel = 0
	star.ZIndex = 32
	star.Parent = backdrop
end

---------------------------------------------------------------- the 3D scooter
-- Floating, with NO plate behind it, exactly like the rail's icons. Built from
-- primitives rather than cloned from ScooterService's real prop: that prop only
-- exists while the scooter is EQUIPPED and welded to a character, so there is
-- nothing to clone in the state this tab spends most of its life in.
local view = Instance.new("ViewportFrame")
view.Name = "Icon"
view.AnchorPoint = Vector2.new(0.5, 0.5)
view.Position = backdrop.Position
view.Size = UDim2.fromOffset(CARD_W - 6 - 8, CARD_H - PILL_H_ - 10 - 8)
view.BackgroundTransparency = 1
view.Ambient = Color3.fromRGB(196, 210, 226)
view.LightColor = Color3.fromRGB(255, 255, 255)
view.LightDirection = Vector3.new(-0.4, -1, -0.55)
view.ZIndex = 33
view.Parent = slot

local rig = Instance.new("Model")
rig.Name = "ScooterIcon"
rig.Parent = view

local painted = {}   -- part -> { on = Color3, off = Color3 }, for the locked look
local function piece(name, size, cf, colour, offColour, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.Parent = rig
	painted[p] = { on = colour, off = offColour }
	return p
end

-- A Cylinder's axis runs along its own X. A wheel needs that axis pointing ACROSS
-- the scooter (world Z), so the rotation is about Y -- rotating about Z instead
-- stands the wheel up like a rolling pin. WHEEL_Y clears the deck's underside.
local WHEEL_Y = -0.40
local function wheel(name, x)
	local spin = CFrame.Angles(0, math.rad(90), 0)
	local w = piece(name, Vector3.new(0.16, 0.62, 0.62), CFrame.new(x, WHEEL_Y, 0) * spin,
		RUBBER, RUBBER_OFF, Enum.Material.Slate)
	w.Shape = Enum.PartType.Cylinder
	local hub = piece(name .. "Hub", Vector3.new(0.18, 0.26, 0.26), CFrame.new(x, WHEEL_Y, 0) * spin,
		TRIM, TRIM_OFF, Enum.Material.Neon)
	hub.Shape = Enum.PartType.Cylinder
end

-- a kick scooter seen from its left front: long deck, stem rising at the front,
-- bar across the top
-- Frame thickened ~1.6x over the real vehicle's proportions. At 92px a scale
-- model of the actual scooter is a few hairlines; the rail's own icons are
-- deliberately chunky for the same reason.
piece("Deck", Vector3.new(2.10, 0.224, 0.832), CFrame.new(0, 0, 0), BODY, BODY_OFF)
piece("Grip", Vector3.new(1.30, 0.05, 0.64), CFrame.new(0.15, 0.14, 0), TRIM, TRIM_OFF, Enum.Material.Neon)
piece("Stem", Vector3.new(0.224, 1.55, 0.224), CFrame.new(-0.92, 0.80, 0) * CFrame.Angles(0, 0, math.rad(-8)), BODY, BODY_OFF)
piece("Bar", Vector3.new(0.208, 0.208, 1.10), CFrame.new(-1.03, 1.55, 0), BODY, BODY_OFF)
piece("GripL", Vector3.new(0.15, 0.15, 0.24), CFrame.new(-1.03, 1.55, 0.46), TRIM, TRIM_OFF, Enum.Material.Neon)
piece("GripR", Vector3.new(0.15, 0.15, 0.24), CFrame.new(-1.03, 1.55, -0.46), TRIM, TRIM_OFF, Enum.Material.Neon)
wheel("WheelFront", -1.00)
wheel("WheelRear", 0.98)

-- Framing picked by rendering candidates at 4x and looking: further back left the
-- scooter small in the tile, tighter cropped the bar and the rear wheel.
local cam = Instance.new("Camera")
cam.CFrame = CFrame.lookAt(Vector3.new(1.453, 1.007, 1.788), Vector3.new(-0.05, 0.40, 0))
cam.Parent = view
view.CurrentCamera = cam

---------------------------------------------------------------- caption pill
local pill = Instance.new("Frame")
pill.Name = "Caption"
pill.AnchorPoint = Vector2.new(0.5, 1)
pill.Position = UDim2.new(0.5, 0, 1, 0)
pill.Size = UDim2.fromOffset(PILL_W, PILL_H_)
pill.BackgroundColor3 = GREEN[1]
pill.BorderSizePixel = 0
pill.ZIndex = 35
pill.Parent = slot
local pillCorner = Instance.new("UICorner")
pillCorner.CornerRadius = UDim.new(0.5, 0)
pillCorner.Parent = pill
local pillGrad = Instance.new("UIGradient")
pillGrad.Rotation = 90
pillGrad.Color = ColorSequence.new(GREEN[1], GREEN[2])
pillGrad.Parent = pill
local pillInk = Instance.new("UIStroke")
pillInk.Color = INK
pillInk.Thickness = 3
pillInk.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
pillInk.Parent = pill

local label = Instance.new("TextLabel")
label.Name = "Label"
label.BackgroundTransparency = 1
label.Size = UDim2.fromScale(1, 1)
label.Font = Enum.Font.FredokaOne
label.TextSize = 17
label.TextColor3 = Color3.new(1, 1, 1)
label.Text = "RIDE"
label.ZIndex = 36
label:SetAttribute("NoPolish", true)
label.Parent = pill
local labelInk = Instance.new("UIStroke")
labelInk.Color = INK
labelInk.Thickness = 2.6
labelInk.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
labelInk.Parent = label

local hit = Instance.new("TextButton")
hit.Name = "Hit"
hit.Text = ""
hit.Size = UDim2.fromScale(1, 1)
hit.BackgroundTransparency = 1
hit.ZIndex = 40
hit.Parent = slot

---------------------------------------------------------------- state
local function findTool()
	local char = player.Character
	local held = char and char:FindFirstChild(TOOL_NAME)
	if held and held:IsA("Tool") then return held, true end
	local backpack = player:FindFirstChildOfClass("Backpack")
	local stowed = backpack and backpack:FindFirstChild(TOOL_NAME)
	if stowed and stowed:IsA("Tool") then return stowed, false end
	return nil, false
end

local owns = false
local function refreshOwnership()
	-- the server's own grant is proof and costs nothing
	if findTool() then owns = true return end
	local ok, res = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, VIP_GAMEPASS_ID)
	end)
	if ok then owns = res and true or false end
end

local shown = nil   -- "buy" | "ride" | "park", so the paint runs only on a change
local function paint(state: string)
	if shown == state then return end
	shown = state
	local ramp = if state == "buy" then GOLD elseif state == "park" then BLUE else GREEN
	pillGrad.Color = ColorSequence.new(ramp[1], ramp[2])
	pill.BackgroundColor3 = ramp[1]
	label.Text = if state == "buy" then "VIP" elseif state == "park" then "PARK" else "RIDE"
	glowHost.Visible = (state == "park")
	-- locked reads as a greyed-out scooter, so the tab still shows WHAT is on offer
	local locked = (state == "buy")
	for part, cols in pairs(painted) do
		part.Color = if locked then cols.off else cols.on
	end
	-- the medallion greys out too: a vivid backdrop behind a grey scooter reads as
	-- a rendering fault rather than as "locked"
	bdGrad.Color = if locked then ColorSequence.new(DECK_TOP_OFF, DECK_BOT_OFF)
		else ColorSequence.new(DECK_TOP, DECK_BOT)
	backdrop.BackgroundColor3 = if locked then DECK_TOP_OFF else DECK_TOP
end
paint("buy")

---------------------------------------------------------------- placement
-- Sits above the HIDE UI pill, which sits above the luck chip, which on touch
-- rides above the sprint button. Anchoring off LIVE geometry rather than a
-- hard-coded Y keeps the column intact on phone and console, where all of those
-- move (see LuckHUDClient.repositionChip).
--
-- MEASURE ONLY WHILE PLAUSIBLE, the rule LuckHUDClient and HudToggleClient both
-- learned the hard way: a disabled or mid-fold ScreenGui reports stale geometry,
-- so anything outside the lower half of the screen is ignored and the last good
-- position is kept.
local function anchorTop(): number?
	local vpY = gui.AbsoluteSize.Y
	if vpY <= 0 then return nil end
	local ht = playerGui:FindFirstChild("HudToggleUI")
	local p = ht and ht.Enabled and ht:FindFirstChild("UiToggle")
	if p and p:IsA("GuiObject") and p.Visible and p.AbsoluteSize.Y > 0 then
		local top = p.AbsolutePosition.Y
		if top > vpY * 0.5 and top < vpY then return top end
	end
	local lh = playerGui:FindFirstChild("LuckHUD")
	local chip = lh and lh:FindFirstChild("LuckChip")
	if chip and chip:IsA("GuiObject") and chip.AbsoluteSize.Y > 0 then
		local top = chip.AbsolutePosition.Y
		if top > vpY * 0.5 and top < vpY then return top - PILL_BAND end
	end
	return nil
end

local function reposition()
	-- LEGACY PATH. This is the third writer of this card's Position and the last
	-- peer-reader in the bottom-right corner: anchorTop() above reads HudToggle's
	-- pill, falling back to LuckHUD's chip, and places this card relative to
	-- whichever it finds. Measured with the stack already correct, it moved the
	-- card from 799 to 645 -- so the stack was right and this put it back.
	if rideSlot then return end
	local top = anchorTop()
	if not top then return end
	-- `top` is the anchor surface's TOP edge; this tab's AnchorPoint is (1, 1), so
	-- its Y offset IS its own bottom edge -- one gap above that top, and it must
	-- NOT also subtract CARD_H (that double-counts the height).
	slot.Position = UDim2.new(1, -EDGE_PAD, 0, math.round(top - GAP))
end

---------------------------------------------------------------- interaction
local HOVER = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Multiplied by deviceK(), never a bare value -- see the note by deviceK.
local function to(v) TweenService:Create(scale, HOVER, { Scale = v * deviceK() }):Play() end
hit.MouseEnter:Connect(function() to(1.08) end)   -- the rail's own hover scale
hit.MouseLeave:Connect(function() to(1) end)
hit.MouseButton1Down:Connect(function() to(0.92) end)
hit.MouseButton1Up:Connect(function() to(1.08) end)

hit.Activated:Connect(function()
	if not owns then
		-- Prompting is safe even if `owns` is somehow stale: Roblox answers an
		-- already-owned pass with its own "you already own this" dialog rather
		-- than charging again.
		pcall(function()
			MarketplaceService:PromptGamePassPurchase(player, VIP_GAMEPASS_ID)
		end)
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local tool, riding = findTool()
	if not tool then return end
	if riding then hum:UnequipTools() else hum:EquipTool(tool) end
	paint(if riding then "ride" else "park")   -- answer the press; the poll corrects
end)

-- Buying it mid-session flips the tab without a rejoin. ScooterService is watching
-- the same signal server-side and hands the Tool over, which the poll then sees.
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, id, purchased)
	if plr == player and id == VIP_GAMEPASS_ID and purchased then
		owns = true
	end
end)

task.spawn(refreshOwnership)

---------------------------------------------------------------- the driver
-- ONE 5Hz poll: do we own it, is it equipped, where does the corner cluster want
-- the tab, and is the backpack still off. A poll rather than a web of
-- ChildAdded/Removed/CharacterAdded/CoreGui signals because the answer depends on
-- four containers across three ScreenGuis owned by three other scripts, plus a
-- CoreGui flag with no change event at all. Nothing here yields, so it cannot
-- pile up, and the async ownership call is NOT in here -- it runs once at start
-- and again on a purchase.
task.spawn(function()
	while gui.Parent do
		local tool, riding = findTool()
		if tool then owns = true end
		if not owns then
			paint("buy")
		else
			local attr = player:GetAttribute(RIDING_ATTR)
			local on = if typeof(attr) == "boolean" then attr else riding
			paint(if on then "park" else "ride")
		end
		reposition()
		-- THE BACKPACK STAYS OFF. Written only when it actually reads wrong, so
		-- this is a comparison rather than a CoreGui write five times a second.
		local okRead, enabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack)
		if okRead and enabled then
			pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false)
		end
		task.wait(0.2)
	end
end)
