--!strict
-- HudLayout: the one place that answers "WHERE does this go".
--
-- Platform (its sibling) answers "what device is this and how big should the UI
-- be". It does that job well. What the place never had is an owner of POSITION,
-- and that -- not scale -- is what made the phone build unplayable.
--
-- ============================ THE BUG THIS FIXES ============================
-- Five scripts stack down the right edge of the screen: EmeraldHUD (gem chip),
-- QuestBar, QuestTracker, HudToggle (HIDE UI), Scooter (RIDE) and LuckHUD.
-- None of them owned that edge. Each picked a corner and hardcoded a pixel
-- offset, and where two would have collided the fix was to teach one about the
-- other's private geometry:
--
--   ScooterButtonClient:82   local LUCK_BOTTOM, LUCK_H, PILL_H = 78, 34, 34
--                            -- "LUCK_BOTTOM is LuckHUDClient's own (1, -78)"
--   LuckHUDClient:197        measures ClientMain's sprint button AbsolutePosition
--   HudToggleClient:141      re-derives the luck chip's rect EVERY FRAME
--   LuckHUDClient:285        Position = UDim2.new(1, -260, 1, -118)
--                            -- "shifted left, clear of the quest tracker band"
--
-- So the right edge was laid out by four scripts reading each other's live
-- AbsolutePosition and rewriting Position on different cadences -- Platform
-- passes, Heartbeat, and tweens -- with no defined evaluation order. Whoever
-- wrote last won that frame. ScooterButtonClient's own comment traces the
-- symptom exactly:
--
--   "this script rewrites Position on every Platform pass and HudToggleClient
--    rewrites the pill's every frame, so the nudge is overwritten the moment it
--    lands (traced: 1766 -> 1715 by the nudge, then tweened back to 1725)"
--
-- That is a cyclic dependency resolved by frame-order luck. It is why the HUD
-- looks different between sessions, why a fix to one widget moves three others,
-- and why patching individual scripts has never held: there is no position that
-- is stable, only a position that happened to be written last.
--
-- ================================ THE RULE =================================
-- ONE WRITER. A script that registers a frame here stops setting its Position,
-- forever. It declares intent -- "I am a chip on the right edge, above the luck
-- chip" -- and HudLayout computes the rect. Nothing reads anyone else's
-- geometry, because nothing needs to: the stack measures its own members.
--
-- Add a widget, remove one, hide one, change one's size, rotate the device --
-- the stack reflows and every neighbour stays correct without knowing that the
-- others exist.
--
-- Usage:
--   local HudLayout = require(ReplicatedStorage.Modules.HudLayout)
--   HudLayout.PrepareGui(gui, "HUD")            -- insets + DisplayOrder
--   local slot = HudLayout.Attach(chip, {        -- and never set Position again
--       stack = "BottomRight", order = HudLayout.Order.Luck,
--   })
--   slot:SetVisible(false)                       -- neighbours close the gap
--
-- Gated on the HUD_LAYOUT_V2 attribute (default on). Set it false to fall
-- straight back to every script's legacy positioning:
--   game.ReplicatedStorage:SetAttribute("HUD_LAYOUT_V2", false)

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")

local Platform = require(ReplicatedStorage.Modules.Platform)

local HudLayout = {}

export type StackName =
	"TopLeft" | "TopRight" | "BottomLeft" | "BottomRight"
	| "TopCentre" | "BottomCentre" | "LeftCentre" | "RightCentre"

export type Spec = {
	stack: StackName,
	order: number?,        -- lower = nearer the anchored edge. Order table below.
	gap: number?,          -- extra px after this item, on top of the stack gap
	pad: number?,          -- extra px between this item and the screen edge
	visible: boolean?,
	-- Push this item further along its stack until it clears widgets in OTHER
	-- stacks. For the few elements whose own stack does not by itself keep them
	-- apart from a neighbouring corner -- a top-centre bar beside a top-left
	-- cluster, which is what ClientMain's tab bar spends 60 lines solving by hand.
	avoid: boolean?,
}

----------------------------------------------------------------- flag
local FLAG = "HUD_LAYOUT_V2"

function HudLayout.Enabled(): boolean
	local v = ReplicatedStorage:GetAttribute(FLAG)
	if v == nil then return true end   -- default ON; absence is not opt-out
	return v == true
end

----------------------------------------------------------------- dirty flag
-- Declared FIRST, above every function that touches it.
--
-- Luau locals are visible only BELOW their declaration, and a function that
-- closes over a name declared later captures nil silently -- it compiles, then
-- throws the first time it runs. This module has now been bitten by that twice:
-- once when Obstacle() called a markDirty() defined further down (which threw
-- inside GameHUDClient's fit() and took the whole nav rail's layout with it),
-- and once when a second copy of these three declarations further down SHADOWED
-- this one, so Reserve and Obstacle set a flag that runPass never read.
--
-- One declaration, at the top, above every use.
local dirty = false
local laying = false

local function markDirty()
	dirty = true
end

----------------------------------------------------------------- layers
-- DISPLAYORDER REGISTRY. The place had seven scripts on DisplayOrder 9, three
-- each on 4, 7 and 8, and pairs on 13, 40 and 60. Ties are resolved by
-- PlayerGui child order, which is script execution order, which is not stable --
-- so "the panel opened behind the HUD" was a coin flip. Named, spaced, unique.
local LAYER: { [string]: number } = {
	World    = 1,    -- world-anchored overlays, below everything
	Tracker  = 10,   -- quest tracker / quest bar
	HUD      = 20,   -- persistent chrome: rail, currency, luck, ride, sprint
	Toggle   = 30,   -- HIDE UI and its companions -- always above the HUD it hides
	Panel    = 40,   -- modal panels: shop, backpack, index, settings
	Dialog   = 50,   -- confirmations and prompts opened FROM a panel
	Reward   = 60,   -- reward reveals, wheel, catch cinematic
	Toast    = 70,   -- transient notifications
	Tutorial = 80,   -- coach marks, which must sit over whatever they point at
	Fade     = 100,  -- teleport fades and cinematic bars, over everything
}
HudLayout.Layer = LAYER

-- Canonical stack order for the persistent HUD. Named so a reader can see the
-- intended stacking at a glance instead of decoding pixel offsets, and so
-- inserting a widget is a one-line change here rather than a re-tune of every
-- neighbour's constants.
HudLayout.Order = {
	-- BottomRight, growing UP from the bottom edge
	Sprint   = 10,
	Luck     = 20,
	Ride     = 30,
	HideUI   = 40,
	-- TopRight, growing DOWN from the top edge
	Currency = 10,
	QuestBar = 20,
	Quest    = 30,
	-- TopLeft
	Rail     = 10,
}

----------------------------------------------------------------- geometry
-- Default gap between stacked items, in SCREEN px. Scaled per device so a phone
-- gets breathing room proportional to its chunkier furniture rather than the
-- 8px that was authored against a 1350px canvas.
local function stackGap(): number
	-- 10 -> 8 on phone (2026-08-27). Generous gaps are a luxury of a screen with
	-- room; on a handset the bottom-right column has ~167-191px for three controls
	-- that are each at the 44px touch floor, and two 10px gaps is 12% of that band
	-- spent on air.
	-- Tighter still on a SHORT screen. A 360px-tall handset has ~165px of usable
	-- band for three touch-floor controls; 8px gaps are 10% of that spent on air.
	if Platform.IsPhone then
		return (Platform.Viewport.Y < 380) and 6 or 8
	end
	if Platform.IsTablet then return 9 end
	if Platform.IsConsole then return 12 end
	return 8
end

-- Padding from the screen edge, inside the safe insets.
local function edgePad(): number
	-- 10 -> 8 on a SHORT phone (2026-08-26). The pad is charged once per stack, and
	-- on a 310px-tall screen every stack is within a few px of its band -- the
	-- bottom-centre column came out at 141 of 140 with 10. Two px per stack is the
	-- cheapest px on the screen to reclaim.
	if Platform.IsShortPhone() then return 8 end
	if Platform.IsPhone then return 10 end
	if Platform.IsConsole then return 20 end
	return 16
end

-- THE INSETS THE SCREENGUI HAS NOT ALREADY APPLIED.
--
-- Measured 2026-08-26 rather than reasoned about, because the comments in this
-- place disagree with each other on it. Four probe ScreenGuis, one per inset
-- mode, a child at offset (0,0) in each, on a 1920x1077 viewport with a 58px
-- topbar:
--
--   IgnoreGuiInset = false / CoreUISafeInsets   AbsoluteSize 1920x1019, child at y=0
--   IgnoreGuiInset = true  / DeviceSafeInsets   AbsoluteSize 1920x1077, child at y=-58
--
-- So AbsolutePosition's origin is BELOW the topbar in every mode -- a full-bleed
-- gui simply starts at negative y -- and a gui that respects the inset has ALREADY
-- removed the topbar from its own coordinate space.
--
-- Platform.Insets() reports the total safe area including that topbar, so adding
-- it to a position inside an inset-respecting gui double-counts it: every top-
-- anchored widget would sit 58px lower than asked. PrepareGui puts every stacked
-- surface on CoreUISafeInsets, so what this layer owes is only the part Roblox
-- has NOT already handled -- console overscan, and the touch-control band along
-- the bottom, which is not a GuiInset at all.
local function extraInsets()
	local si = Platform.Insets()
	local topLeft, bottomRight = GuiService:GetGuiInset()
	return {
		Top = math.max(si.Top - topLeft.Y, 0),
		Left = math.max(si.Left - topLeft.X, 0),
		Bottom = math.max(si.Bottom - bottomRight.Y, 0),
		Right = math.max(si.Right - bottomRight.X, 0),
	}
end

-- FULL-BLEED GUIS NEED THE TOPBAR ADDED BACK.
--
-- Probed 2026-08-26: with a 58px topbar, a child at offset (0,0) reports
-- AbsolutePosition.Y = 0 inside an inset-respecting ScreenGui and -58 inside an
-- IgnoreGuiInset one -- the full-bleed gui starts above the origin. Both guis'
-- BOTTOM edges land at the same absolute y, so only top- and centre-anchored
-- positions differ, by the inset scaled by how far the anchor sits from the
-- bottom.
--
-- This is the trap HudToggleClient documented the hard way ("a bare Position of
-- (x, 28) rendered at y -30 against a 58px inset -- off the top of the screen,
-- with every click sailing past into the world") and the one that still has
-- MainUI's SKIP / SHOPS / PLOT tabs sitting at y = -48 on every device.
--
-- Compensating HERE lets a widget join a stack without its ScreenGui changing
-- inset mode -- which matters for a shared authored gui like MainUI, where
-- flipping the mode would move all six of its children at once.
local function insetComp(frame: GuiObject, ys: number): number
	local node: Instance? = frame.Parent
	while node and not node:IsA("ScreenGui") do node = node.Parent end
	if not (node and (node :: ScreenGui).IgnoreGuiInset) then return 0 end
	local topLeft = GuiService:GetGuiInset()
	return topLeft.Y * (1 - ys)
end

-- The usable screen box in AbsolutePosition space: origin just below the topbar,
-- extending to the bottom of the window. Both inset modes resolve their bottom
-- edge here, and insetComp lifts full-bleed tops into the same box.
--
-- UNDER A VIEWPORT OVERRIDE, LAY OUT AGAINST THE PRETEND SCREEN (2026-08-27).
--
-- This used the real camera viewport unconditionally, and that quietly made the
-- device preview useless for the thing it was built to catch. Overriding to a
-- 867x399 handset changed every Platform SCALE, so widgets shrank correctly --
-- but the stacks were still laid out against the real 1920x1019 Studio window,
-- so they had 1019px of vertical room instead of 341. A bottom-right column that
-- needs 260px in a 229px band fitted comfortably in the preview and overflowed
-- off the top of the real phone. The audit reported zero problems against a HUD
-- that was visibly broken on the device.
--
-- With the override active the whole model is "pretend the screen is this size",
-- and layout has to pretend too, or the preview is only simulating half the
-- system. Positions land wrong on the real Studio window while an override is
-- set -- that is expected, and is what makes the overflow visible.
local function screenBox(): (number, number)
	local forced = Platform.GetViewportOverride()
	if forced then
		return forced.X, forced.Y - GuiService:GetGuiInset().Y
	end
	local cam = Workspace.CurrentCamera
	local vp = (cam and cam.ViewportSize.X > 1) and cam.ViewportSize or Platform.Viewport
	local topLeft = GuiService:GetGuiInset()
	return vp.X, vp.Y - topLeft.Y
end

-- A frame's offsets are interpreted in its PARENT's coordinate space, which an
-- enclosing UIScale multiplies. AbsoluteSize is already in screen px. Mixing the
-- two silently misplaces anything nested under a scaled host -- so convert.
local function parentScaleChain(frame: GuiObject): number
	local mult = 1
	local node: Instance? = frame.Parent
	while node and not node:IsA("ScreenGui") do
		if node:IsA("GuiObject") then
			for _, c in ipairs(node:GetChildren()) do
				if c:IsA("UIScale") then mult *= c.Scale end
			end
		end
		node = node.Parent
	end
	return (mult > 0.001) and mult or 1
end

-- The device scale shared by the bottom-right corner chips.
--
-- LuckHUD's chip and HudToggle's HIDE UI pill are meant to read as one cluster,
-- which means matching widths. They achieved that by having the pill re-read the
-- chip's AbsoluteSize EVERY FRAME (HudToggleClient's uiTarget) -- a peer
-- dependency that then had to be defended with plausibility tests, fallback
-- coordinates and a note explaining why the chip may never be hidden via
-- gui.Enabled, because a disabled ScreenGui stops laying out and fed the pill
-- stale geometry.
--
-- Both now ask HERE. Deriving the same number from a shared authority is not the
-- same thing as reading it off a neighbour: there is no ordering, nothing to go
-- stale, and hiding either one cannot affect the other.
function HudLayout.ChipScale(): number
	-- 1.1 -> 1.0 ON PHONE (2026-08-27). The 1.1 was chosen to make a 138px chip
	-- readable, back when readability and block size were the same lever. They are
	-- not any more -- Platform.Block and CompensateType split them -- and measured
	-- on a real 867-wide handset the boosted chip rendered 151px, i.e. 18% of the
	-- screen's width for a passive readout. Type keeps its size through the
	-- compensation path; the box does not need it.
	if Platform.IsConsole then return 1.3 end
	return 1
end

-- Authored width for a corner chip. 138 was picked against a desktop canvas and
-- is 16% of an 867px handset before any scale -- wide enough that two of them
-- stacked read as a wall. Narrower on a phone, unchanged everywhere else.
function HudLayout.ChipWidth(): number
	-- 112 -> 96 on a SHORT phone (2026-08-26, from an owner capture). 112 is 16% of
	-- a 700px-wide handset, and the owner marked this cluster as needing to be
	-- smaller -- two of these plus the RIDE card read as a wall down the right-hand
	-- third of the screen. The label inside is compensated type (see
	-- CompensateType), so the text does not shrink with the box.
	if Platform.IsShortPhone() then return 96 end
	if Platform.IsPhone then return 112 end
	return 138
end

-- Roblox's minimum touch target.
HudLayout.MIN_TOUCH = 44

-- The AUTHORED height a corner chip needs so that, once ChipScale has been
-- applied, it renders at or above the touch floor.
--
-- Both chips got this wrong in the same way, and for the same reason: each
-- computed a height once, at require time, from Platform.IsTouch. The luck chip
-- asked for 40 and rendered 40 on a tablet (ChipScale 1.0) -- four px short --
-- and the HIDE UI pill captured IsTouch before the device was known and rendered
-- 37. LuckHUDClient's own comment records the earlier round of this as a
-- trade-off it accepted: "chip height drops 44 -> 37px, under the 44px touch
-- floor, accepted for a low-frequency control". It never needed to be a
-- trade-off; it needed the floor and the scale in the same expression.
function HudLayout.ChipHeight(): number
	if not Platform.IsTouch then return 34 end
	return math.ceil(HudLayout.MIN_TOUCH / HudLayout.ChipScale())
end

----------------------------------------------------------------- reserved zones
-- Rects that game UI must never occupy, in screen px, keyed by name so a caller
-- can update one without knowing about the others.
--
-- Roblox draws its own touch controls into the bottom corners: the thumbstick
-- bottom-left, jump bottom-right. Platform.Insets() already reserves a full-width
-- band for them, which is correct but expensive -- it costs the bottom 140px of
-- screen across the WHOLE width, on the device with the least screen to spend.
-- Naming the two corners instead lets a bottom-centre stack use the middle of
-- that band, which is where the throw button wants to live.
local reserved: { [string]: Rect } = {}

-- OBSTACLES: space that is occupied but not placed by this module.
--
-- Not every HUD surface should join a stack. GameHUDClient owns a `chrome` host
-- with its own scale and its own internal grid, and it is ALREADY a single
-- writer for everything inside it -- it was never part of the write-ordering
-- race, so pulling its internals out here would be risk without benefit. But
-- other stacks still need to know where its currency cluster sits, or they will
-- lay a nav bar straight over it (measured: bar left edge 745 against a cluster
-- right edge of 865 on the phone layout).
--
-- An obstacle is declared by its owner -- "I occupy this rect" -- and read only
-- by the layout pass. That is not the peer-reading pattern this module exists to
-- remove: the danger there was TWO WRITERS taking turns, each overwriting the
-- other's correction. One writer observing a rect it does not touch is just how
-- a layout engine works.
--
-- Declared HERE, above its first use. It was originally added down in the state
-- section and read from Obstacle() above it, so the upvalue was nil at call time
-- and every fit() pass in GameHUDClient threw -- which aborted that function
-- before its layoutRail() call and silently stopped laying out the nav rail.
local obstacles: { [string]: GuiObject } = {}

function HudLayout.Reserve(name: string, rect: Rect?)
	if rect then reserved[name] = rect else reserved[name] = nil end
	HudLayout.Refresh()
end

-- Declare that `frame` occupies its own rect, so `avoid` items route around it.
-- Pass nil to clear. Returns a function that clears it.
function HudLayout.Obstacle(name: string, frame: GuiObject?)
	obstacles[name] = frame
	markDirty()
	return function()
		obstacles[name] = nil
		markDirty()
	end
end

-- Was a private copy of 150/190. Now asks Platform, so the layout and the audit
-- cannot drift apart about where Roblox's own controls are.
local function touchCornerWidth(): number
	return Platform.TouchCorner()
end

----------------------------------------------------------------- state
type Entry = {
	frame: GuiObject,
	spec: Spec,
	visible: boolean,
	conns: { RBXScriptConnection },
}

local stacks: { [string]: { Entry } } = {}
-- dirty / laying / markDirty are declared at the top of the file. They were
-- briefly re-declared here as well, which is worse than either place alone: the
-- second pair SHADOWED the first, so Reserve and Obstacle set one flag while
-- runPass read the other and no layout pass ever ran from them.

----------------------------------------------------------------- the layout pass
-- Anchor and growth direction per stack. AnchorPoint is set by HudLayout, not by
-- the caller, so an item cannot half-opt-in and land somewhere unexpected.
local ANCHOR: { [string]: { anchor: Vector2, xs: number, ys: number, dir: number, axis: string } } = {
	TopLeft      = { anchor = Vector2.new(0, 0),   xs = 0, ys = 0, dir =  1, axis = "Y" },
	TopRight     = { anchor = Vector2.new(1, 0),   xs = 1, ys = 0, dir =  1, axis = "Y" },
	BottomLeft   = { anchor = Vector2.new(0, 1),   xs = 0, ys = 1, dir = -1, axis = "Y" },
	BottomRight  = { anchor = Vector2.new(1, 1),   xs = 1, ys = 1, dir = -1, axis = "Y" },
	TopCentre    = { anchor = Vector2.new(0.5, 0), xs = 0.5, ys = 0, dir =  1, axis = "Y" },
	BottomCentre = { anchor = Vector2.new(0.5, 1), xs = 0.5, ys = 1, dir = -1, axis = "Y" },
	LeftCentre   = { anchor = Vector2.new(0, 0.5), xs = 0, ys = 0.5, dir =  1, axis = "Y" },
	RightCentre  = { anchor = Vector2.new(1, 0.5), xs = 1, ys = 0.5, dir =  1, axis = "Y" },
}

-- STACK ORDER MATTERS. Corners are laid first and the centre bars last, so an
-- `avoid` item in a centre stack has real rects to test against: a top-centre
-- nav bar can only step around a top-left currency cluster if the cluster has
-- already been placed this pass.
local STACK_ORDER = {
	"TopLeft", "TopRight", "BottomLeft", "BottomRight",
	"LeftCentre", "RightCentre", "TopCentre", "BottomCentre",
}

-- Where a frame's rect lands in screen space, from its anchor and offsets.
local function rectFor(a, xOff: number, yOff: number, w: number, h: number, W: number, H: number)
	return (a.xs * W + xOff - a.xs * w), (a.ys * H + yOff - a.ys * h)
end

local function boxesOverlap(l1, t1, w1, h1, l2, t2, w2, h2, m: number): boolean
	return (l1 < l2 + w2 + m) and (l2 < l1 + w1 + m)
		and (t1 < t2 + h2 + m) and (t2 < t1 + h1 + m)
end

local function layoutStack(name: string, entries: { Entry }, placed: { any })
	local a = ANCHOR[name]
	if not a then return end

	local si = extraInsets()
	local gap = stackGap()
	local pad = edgePad()
	local W, H = screenBox()

	-- Distance already consumed along the growth axis, measured from the anchored
	-- edge INSIDE the safe inset.
	local used: number
	if a.dir > 0 then
		used = (name:find("Top") and si.Top or 0) + pad
	else
		used = si.Bottom + pad
	end

	-- A BOTTOM CORNER STACK MUST CLEAR THE CONTROL SQUARE, NOT JUST THE BAND.
	-- Platform's bottom inset is a full-width strip and is deliberately shorter
	-- than the controls are tall (112px against a 150px jump button on a phone),
	-- because reserving the taller figure across the whole width would cost 38% of
	-- a handset's height. The corners are where the controls actually are, so the
	-- two stacks that grow out of them start above the square instead. Measured
	-- before this: the sprint button sat 59% under the jump control.
	if (name == "BottomLeft" or name == "BottomRight") and Platform.IsTouch then
		used = math.max(used, Platform.TouchCorner() + pad)
	end

	-- Centre-anchored vertical stacks start from the middle, not an edge.
	if name == "LeftCentre" or name == "RightCentre" then used = 0 end

	-- The bottom corners must clear Roblox's own touch controls. Platform.Insets()
	-- reserves the band across the full width; a corner stack needs no more than
	-- that, but a BottomCentre stack may reclaim the middle of it.
	if name == "BottomCentre" and Platform.IsTouch then
		used = math.max(pad, si.Bottom - 60)
	end

	local sorted = table.clone(entries)
	table.sort(sorted, function(x, y)
		return (x.spec.order or 100) < (y.spec.order or 100)
	end)

	for _, e in ipairs(sorted) do
		local f = e.frame
		if f.Parent and e.visible and f.Visible then
			local chain = parentScaleChain(f)
			local h = f.AbsoluteSize.Y
			local w = f.AbsoluteSize.X
			local itemPad = e.spec.pad or 0

			-- Horizontal placement: hug the anchored edge inside its inset.
			local xOff: number
			if a.xs == 0 then
				xOff = si.Left + pad + itemPad
			elseif a.xs == 1 then
				xOff = -(si.Right + pad + itemPad)
			else
				xOff = 0
			end

			-- A bottom corner item wider than the corner it sits in would run under
			-- the thumbstick or jump button. Nudge it inboard rather than letting it
			-- overlap a control the player cannot move.
			if Platform.IsTouch and (name == "BottomLeft" or name == "BottomRight") then
				local corner = touchCornerWidth()
				if w < corner and used < si.Bottom then
					local shove = corner - w
					xOff += (a.xs == 1) and -shove or shove
				end
			end

			-- CROSS-STACK AVOIDANCE. A stack keeps its own members apart by
			-- construction, but says nothing about the stack in the next corner. The
			-- one case in this HUD that needs it is ClientMain's tab bar, which spends
			-- ~60 lines and three fallback metric sets solving "is there room beside
			-- the currency cluster, and if not, how far under it do I go" -- by reading
			-- the cluster's AbsolutePosition off another ScreenGui every pass. Asking
			-- the layout that owns both is the same answer without the peer read.
			-- ON A CENTRE STACK, spec.pad HAS TO MOVE THE GROWTH AXIS (2026-08-26).
			--
			-- The xOff block above is the only consumer of itemPad, and for TopCentre /
			-- BottomCentre it takes the `else xOff = 0` branch -- so a pad on a centred
			-- item was read, discarded, and reported no error. ClientMain's tab bar asked
			-- for -40 and did not move a pixel, which looked like the caller was wrong.
			--
			-- For a centred item the only edge it HAS is the one it grows from, so that is
			-- where "extra px from the screen edge" has to apply. Strictly additive: on
			-- every edge-anchored stack itemPad keeps going to xOff exactly as before, so
			-- nothing that works today moves.
			local axisPad = (a.xs ~= 0 and a.xs ~= 1) and itemPad or 0
			local comp = insetComp(f, a.ys)
			local l, t, hit
			local guard = 0
			repeat
				hit = nil
				local probeY = ((a.dir > 0) and (used + axisPad) or -(used + axisPad)) + comp
				l, t = rectFor(a, xOff, probeY, w, h, W, H)
				if e.spec.avoid then
					for _, p in ipairs(placed) do
						if p.stack ~= name and boxesOverlap(l, t, w, h, p.l, p.t, p.w, p.h, gap) then
							hit = p
							break
						end
					end
				end
				if hit then
					-- Step just past the obstruction, along this stack's growth axis.
					local push = (a.dir > 0)
						and ((hit.t + hit.h + gap) - t)
						or ((t + h + gap) - hit.t)
					used += math.max(push, 1)
				end
				guard += 1
			until (not hit) or guard >= 8

			-- axisPad HERE TOO, not only in the probe above. This line is the one that
			-- actually writes the frame; the probe inside the loop only feeds `avoid`.
			-- Adding the pad to the probe alone moved the collision test and left the
			-- final position untouched, so the item did not budge and the trace showed a
			-- correct axisPad = -40 being computed and then thrown away.
			local yOff = ((a.dir > 0) and (used + axisPad) or -(used + axisPad)) + comp

			f.AnchorPoint = a.anchor
			f.Position = UDim2.new(
				a.xs, math.round(xOff / chain),
				a.ys, math.round(yOff / chain)
			)

			table.insert(placed, { stack = name, l = l, t = t, w = w, h = h })
			used += h + gap + (e.spec.gap or 0)
		end
	end
end

function HudLayout.Refresh()
	markDirty()
end

local function runPass()
	if laying then return end
	laying = true
	-- Rects placed so far this pass, for `avoid` items to test against. Rebuilt
	-- every pass rather than cached: sizes change as counters grow and panels open.
	local placed = {}
	-- Seed with declared obstacles, measured live: their sizes change as counters
	-- grow and their owners rescale them per device.
	for name, f in pairs(obstacles) do
		if f.Parent and f.Visible and f.AbsoluteSize.X > 1 then
			table.insert(placed, {
				stack = "@" .. name,
				l = f.AbsolutePosition.X, t = f.AbsolutePosition.Y,
				w = f.AbsoluteSize.X, h = f.AbsoluteSize.Y,
			})
		end
	end
	for _, name in ipairs(STACK_ORDER) do
		local entries = stacks[name]
		if entries then
			-- Drop entries whose frame has been destroyed, so a stack cannot be held
			-- open by a gap belonging to something that no longer exists.
			for i = #entries, 1, -1 do
				if not entries[i].frame.Parent then
					table.remove(entries, i)
				end
			end
			layoutStack(name, entries, placed)
		end
	end
	laying = false
end

----------------------------------------------------------------- attach
local Slot = {}
Slot.__index = Slot

function Slot:SetVisible(v: boolean)
	self._entry.visible = v
	self._entry.frame.Visible = v
	markDirty()
end

function Slot:SetOrder(n: number)
	self._entry.spec.order = n
	markDirty()
end

-- Move this item to a different stack, live.
--
-- A phone has ~229px of usable height and four bottom-right controls wanting
-- ~200px of it. The answer is not to shrink all four into illegibility but to
-- move the passive ones somewhere with room -- so the luck readout rides the top
-- edge on a handset and the corner keeps the controls you actually press. That
-- decision has to be live rather than made at require time: device class settles
-- a beat after join, and can change mid-session (rotation, a preview override).
function Slot:SetStack(name: StackName)
	if name == self._stack then return end
	if not ANCHOR[name] then
		warn(string.format("[HudLayout] unknown stack %q", tostring(name)))
		return
	end
	local from = stacks[self._stack]
	if from then
		local i = table.find(from, self._entry)
		if i then table.remove(from, i) end
	end
	self._stack = name
	self._entry.spec.stack = name
	stacks[name] = stacks[name] or {}
	table.insert(stacks[name], self._entry)
	markDirty()
end

function Slot:SetGap(n: number)
	self._entry.spec.gap = n
	markDirty()
end

-- Change the item's distance from its anchored edge after the fact.
--
-- NEGATIVE IS LEGAL AND IS THE POINT. A full-bleed surface can deliberately sit
-- inside the topbar band: on a phone Roblox's own chrome (logo, menu, chat,
-- voice) is left-aligned and the middle of that band is empty, so a centred strip
-- can use it. That is 46px of a 310px screen -- 15% of the height -- reclaimed
-- from a margin that is only reserved because of chrome that is not there.
-- Only do this for something horizontally clear of that chrome.
function Slot:SetPad(n: number)
	self._entry.spec.pad = n
	markDirty()
end

-- Turn cross-stack avoidance on or off after the fact.
--
-- Needed because avoidance and a negative pad pull against each other: raising an
-- item INTO a band an obstacle also occupies is exactly what `avoid` exists to
-- undo, so the item is pushed straight back to where it started and the pad looks
-- like it did nothing. Where the two are known not to conflict on an axis avoid
-- does not test -- a centred bar against a left-anchored cluster -- the caller can
-- say so.
function Slot:SetAvoid(v: boolean)
	self._entry.spec.avoid = v
	markDirty()
end

function Slot:Detach()
	for _, c in ipairs(self._entry.conns) do c:Disconnect() end
	table.clear(self._entry.conns)
	if self._entry.frame.Parent then
		self._entry.frame:SetAttribute("HudLayoutManaged", nil)
	end
	local list = stacks[self._stack]
	if list then
		local i = table.find(list, self._entry)
		if i then table.remove(list, i) end
	end
	markDirty()
end

-- Register a frame into a stack. Returns a slot handle, or nil when the flag is
-- off -- callers keep their legacy path behind `if not slot then ... end`.
--
-- THE FRAME MUST BE A DIRECT CHILD OF ITS SCREENGUI (or of a host that fills the
-- screen). Stack placement resolves scale anchors against the screen box, so a
-- frame nested inside a smaller, offset host -- GameHUDClient's `chrome`, say --
-- would be positioned against the wrong rectangle. Those surfaces stay with
-- their own owner and declare an Obstacle instead.
function HudLayout.Attach(frame: GuiObject, spec: Spec)
	if not HudLayout.Enabled() then return nil end
	if not ANCHOR[spec.stack] then
		warn(("[HudLayout] unknown stack %q for %s"):format(tostring(spec.stack), frame:GetFullName()))
		return nil
	end

	local entry: Entry = {
		frame = frame,
		spec = spec,
		visible = (spec.visible ~= false) and frame.Visible,
		conns = {},
	}

	stacks[spec.stack] = stacks[spec.stack] or {}
	table.insert(stacks[spec.stack], entry)

	-- CLAIM THE FRAME PUBLICLY. PlatformClient runs a blanket auto-fitter that
	-- hunts for offset-sized frames over 80x100 and retro-fits a UIScale onto them
	-- -- and its own comment records the gate being widened from 150 to 80
	-- specifically to catch ScooterUI's ride tile, which is now a member of this
	-- stack. Two systems sizing one frame is the same failure mode as two systems
	-- positioning it. The attribute is how that fitter knows to leave it alone.
	frame:SetAttribute("HudLayoutManaged", true)

	-- A widget that changes size (a counter going from 3 to 4 digits, a label
	-- resizing on a longer quest name) must push its neighbours, not overlap them.
	table.insert(entry.conns, frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(markDirty))
	table.insert(entry.conns, frame:GetPropertyChangedSignal("Visible"):Connect(function()
		entry.visible = frame.Visible
		markDirty()
	end))

	local slot = setmetatable({ _entry = entry, _stack = spec.stack }, Slot)
	markDirty()
	return slot
end

----------------------------------------------------------------- guis
-- Which DisplayOrder each gui was actually given, and how many guis have claimed
-- each layer so far.
local assignedOrder: { [Instance]: number } = {}
local layerClaims: { [number]: number } = {}

-- One inset model for every HUD surface. This is what makes cross-gui stacking
-- meaningful at all: the place currently mixes IgnoreGuiInset true (GameHUD,
-- QuestBar, HudToggle), false (EmeraldHUD, Booth, Rebirth, Toast) and unset
-- (LuckHUD, Scooter, QuestClient), so "16px from the top" means two different
-- screen rows depending on which script drew it -- and on a notched phone one
-- set of widgets runs under the cutout while the other clears it.
--
-- CoreUISafeInsets: the gui's (0,0) is below the Roblox topbar and inside the
-- notch, so an offset IS a screen position, for everyone, always.
function HudLayout.PrepareGui(gui: ScreenGui, layerName: string, fullBleed: boolean?)
	local order = LAYER[layerName]
	if not order then
		warn(("[HudLayout] unknown layer %q for %s -- defaulting to HUD"):format(layerName, gui.Name))
		order = LAYER.HUD
	end

	if not HudLayout.Enabled() then return order end

	-- SEVERAL GUIS PER LAYER IS NORMAL, AND MUST STILL BE DETERMINISTIC.
	-- The persistent HUD is legitimately three or four ScreenGuis that share the
	-- "HUD" layer and never overlap -- LuckHUD, ScooterUI, MainUI. Giving them one
	-- identical DisplayOrder would leave their z-order decided by PlayerGui child
	-- order, i.e. by script execution order, which is not stable between sessions;
	-- that undefined tie is what this registry exists to remove, so warning about
	-- it and then doing it anyway (the first version of this) fixed nothing.
	--
	-- Instead each claimant after the first takes the next order up. Layers are
	-- spaced 10 apart, so a layer has room for ten surfaces before it could reach
	-- the next one. Re-preparing the same gui returns its existing order rather
	-- than walking it upward on every call.
	local already = assignedOrder[gui]
	if already then
		gui.DisplayOrder = already
		return already
	end
	local claimed = layerClaims[order] or 0
	layerClaims[order] = claimed + 1
	if claimed >= 9 then
		warn(("[HudLayout] layer %q is full (10 surfaces); %q may z-fight the next layer")
			:format(layerName, gui.Name))
	end
	order += math.min(claimed, 9)
	assignedOrder[gui] = order

	gui.DisplayOrder = order
	gui.ResetOnSpawn = false
	-- Full-bleed surfaces (fades, cinematic bars, backdrops) genuinely want the
	-- whole screen including the topbar. Everything else shares one frame.
	gui.IgnoreGuiInset = fullBleed == true
	Platform.PrepareGui(gui, fullBleed == true)
	return order
end

----------------------------------------------------------------- type scale
-- Re-author TextSize under `root` by `factor`, idempotently.
--
-- The other half of the block/type split. A UIScale scales geometry AND glyphs
-- together, which is exactly the coupling that made the phone HUD enormous: the
-- only lever was one number, so making text readable made every box around it
-- readable-sized too. Roblox has no "scale text only" property, so the type half
-- is applied by rewriting TextSize on the way in, and the geometry half stays on
-- the UIScale.
--
-- IDEMPOTENT, which matters more than it looks: this runs on every device change,
-- and multiplying the CURRENT TextSize each pass would compound (three device
-- changes at 1.48 would give 3.2x and the HUD would grow every time the player
-- rotated the phone). The authored value is stashed in an attribute on first
-- contact and every later pass is computed from that, never from the live value.
--
-- TextScaled labels are skipped -- they ignore TextSize by definition, and their
-- size is already driven by their box.
function HudLayout.CompensateType(root: Instance, factor: number)
	if not HudLayout.Enabled() then return end
	factor = math.clamp(factor or 1, 0.25, 4)
	local function apply(d: Instance)
		if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
			if not d.TextScaled then
				local authored = d:GetAttribute("AuthoredTextSize")
				if authored == nil then
					authored = d.TextSize
					d:SetAttribute("AuthoredTextSize", authored)
				end
				d.TextSize = math.max(1, math.round((authored :: number) * factor))
			end
		end
	end
	apply(root)
	for _, d in ipairs(root:GetDescendants()) do apply(d) end
end

----------------------------------------------------------------- panel fitting
-- The scale at which a fixed-size panel fits INSIDE THE SAFE AREA.
--
-- Deliberately not Platform.FitPanel, which divides by the RAW viewport. On a
-- 390px-tall handset the raw height is 390 and the usable height is 220 -- the
-- topbar takes 58 and the touch-control band takes 112 -- so a panel fitted to
-- the raw figure overflows the part of the screen the player can actually see by
-- nearly 80%. Measured on the two offer panels: 760x560 authored, rendering at
-- 255% of usable height.
--
-- The floor matters as much as the formula. Both offer panels clamped at 0.45,
-- which on a short screen is not a safety net but the actual cause: the honest
-- answer was ~0.35 and the clamp overruled it. Platform.Height's own comments
-- record the same discovery about its floor -- "that is the 'pop ups cover the
-- whole screen' report, and the floor was causing it". A floor should stop a
-- panel becoming unreadable, not force it off the screen; below it, the panel
-- needs to scroll or reflow, which is a design change rather than a scale.
-- Re-run `fn` now and on every device change (viewport, rotation, device class,
-- and the Platform/Viewport preview overrides). A thin pass-through to
-- Platform.Watch, so a panel that only needs re-fitting does not have to require
-- Platform as well as this module -- and, more to the point, so it stops
-- listening to Camera.ViewportSize alone, which misses a device-class change and
-- cannot be driven by the preview at all.
function HudLayout.WatchDevice(fn: () -> ()): () -> ()
	return Platform.Watch(function() fn() end)
end

function HudLayout.FitPanelScale(designW: number, designH: number, margin: number?, minScale: number?): number
	local vp = Platform.Viewport
	local si = Platform.Insets()
	local m = margin or 12
	local availW = math.max(vp.X - si.Left - si.Right - m * 2, 80)
	local availH = math.max(vp.Y - si.Top - si.Bottom - m * 2, 80)
	if designW <= 0 or designH <= 0 then return 1 end
	return math.clamp(math.min(availW / designW, availH / designH), minScale or 0.28, 1)
end

----------------------------------------------------------------- modals
-- Centre a fixed-size panel and size it for the device.
--
-- Panels here are authored 800-960px wide inside a 1350px canvas. Fitting the
-- CANVAS spends ~30% of the width on gutters, which is affordable on a monitor
-- and ruinous on a handset -- Platform.FitPanel already solves that arithmetic;
-- what was missing is that nothing applied it consistently, so some panels fit
-- the canvas, some fit the panel, and some were authored at raw px with no fit
-- at all and simply overflowed the screen.
function HudLayout.Modal(frame: GuiObject, designW: number, designH: number, opts: { margin: number?, scaleName: string? }?)
	if not HudLayout.Enabled() then return nil end
	local o = opts or {}

	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)

	local scale = frame:FindFirstChild(o.scaleName or "HudLayoutScale")
	if not (scale and scale:IsA("UIScale")) then
		scale = Instance.new("UIScale")
		scale.Name = o.scaleName or "HudLayoutScale"
		scale.Parent = frame
	end

	return Platform.Watch(function()
		if not scale.Parent then return end
		local s = Platform.FitPanel(designW, designH, o.margin)
		-- A modal must also clear the safe insets, not just fit the raw viewport:
		-- a notched phone in landscape loses real width to the cutout, and a TV
		-- loses 3.5% on every edge.
		local si = Platform.Insets()
		local vp = Platform.Viewport
		local availW = math.max(vp.X - si.Left - si.Right, 120)
		local availH = math.max(vp.Y - si.Top - si.Bottom, 120)
		local capped = math.min(s, availW / designW, availH / designH)
		;(scale :: UIScale).Scale = math.clamp(capped, 0.2, 1.7)
	end)
end

----------------------------------------------------------------- budgets
-- What each stack NEEDS versus what it HAS, in screen px.
--
-- Analytic on purpose. A stack that overflows its band does not report itself
-- through rendered positions -- it just keeps stacking past the edge -- and under
-- a device preview it cannot even do that, because the scale half of each
-- position still resolves against the real window. Summing the members is the
-- only way to see it, and it stays faithful at any simulated size.
function HudLayout.StackBudgets(): { any }
	local si = extraInsets()
	local gap = stackGap()
	local pad = edgePad()
	local _, H = screenBox()
	local report = {}

	for _, name in ipairs(STACK_ORDER) do
		local entries = stacks[name]
		if entries and #entries > 0 then
			local needed, count, names = 0, 0, {}
			for _, e in ipairs(entries) do
				local f = e.frame
				if f.Parent and e.visible and f.Visible then
					count += 1
					needed += f.AbsoluteSize.Y + (e.spec.gap or 0)
					table.insert(names, string.format("%s(%d)", f.Name, math.round(f.AbsoluteSize.Y)))
				end
			end
			if count > 0 then
				needed += gap * math.max(count - 1, 0) + pad
				-- The band this stack may occupy: usable height, less the insets at its
				-- own end, less the control square for a bottom corner.
				local available = H - si.Top - si.Bottom
				if (name == "BottomLeft" or name == "BottomRight") and Platform.IsTouch then
					available = H - si.Top - math.max(si.Bottom, Platform.TouchCorner())
				end
				table.insert(report, {
					stack = name,
					needed = math.round(needed),
					available = math.round(available),
					count = count,
					members = table.concat(names, " "),
				})
			end
		end
	end
	return report
end

----------------------------------------------------------------- debug
-- What each stack currently holds, in the order it is laid. Answers "why is this
-- widget there" without re-deriving the arithmetic by hand -- which is how the
-- old HUD's magic offsets got written in the first place.
--   print(require(game.ReplicatedStorage.Modules.HudLayout).Debug())
-- HOW TO READ THIS FROM THE COMMAND BAR.
--
-- Not by requiring this module and calling Debug() -- that returns an EMPTY
-- report. Studio's command bar keeps its own module cache, so requiring
-- HudLayout there builds a second, fresh instance with no stacks in it, exactly
-- as Platform's note about PlatformOverride describes for its own fields. The
-- first attempt to debug this layout produced a confident "no stacks registered"
-- against a HUD that was visibly laid out.
--
-- Set the attribute instead: the RUNNING copy is listening, and prints.
--   game.ReplicatedStorage:SetAttribute("HudLayoutDump", true)
function HudLayout.Debug(): string
	local si = extraInsets()
	local W, H = screenBox()
	local lines = {
		("HudLayout enabled=%s class=%s vp=%dx%d screenBox=%dx%d")
			:format(tostring(HudLayout.Enabled()), Platform.Class,
				Platform.Viewport.X, Platform.Viewport.Y, W, H),
		("extraInsets T%d B%d L%d R%d  gap=%d pad=%d")
			:format(si.Top, si.Bottom, si.Left, si.Right, stackGap(), edgePad()),
	}
	for name, f in pairs(obstacles) do
		table.insert(lines, ("  obstacle %-18s %s size %s")
			:format(name, tostring(f.AbsolutePosition), tostring(f.AbsoluteSize)))
	end
	for _, sname in ipairs(STACK_ORDER) do
		local entries = stacks[sname]
		if entries and #entries > 0 then
			table.insert(lines, ("[%s] %d item(s)"):format(sname, #entries))
			local sorted = table.clone(entries)
			table.sort(sorted, function(x, y)
				return (x.spec.order or 100) < (y.spec.order or 100)
			end)
			for _, e in ipairs(sorted) do
				local f = e.frame
				local gui: Instance? = f.Parent
				while gui and not gui:IsA("ScreenGui") do gui = gui.Parent end
				table.insert(lines, ("   order=%-4s %-28s vis=%-5s abs=%s size=%s gui=%s ignoreInset=%s chain=%.2f")
					:format(tostring(e.spec.order), f:GetFullName():sub(-40),
						tostring(e.visible and f.Visible),
						tostring(f.AbsolutePosition), tostring(f.AbsoluteSize),
						gui and gui.Name or "?",
						tostring(gui and (gui :: ScreenGui).IgnoreGuiInset),
						parentScaleChain(f)))
			end
		end
	end
	return table.concat(lines, "\n")
end

----------------------------------------------------------------- wiring
if RunService:IsClient() then
	-- Coalesce every dirty mark into ONE pass per frame. The old code wrote
	-- Position from Heartbeat handlers, Platform passes and tweens at once; a
	-- single ordered pass is what removes the write-ordering race entirely.
	RunService.Heartbeat:Connect(function()
		if dirty then
			dirty = false
			runPass()
		end
	end)

	Platform.Watch(function() markDirty() end)

	local function hookCamera()
		local cam = Workspace.CurrentCamera
		if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(markDirty) end
	end
	hookCamera()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		hookCamera()
		markDirty()
	end)

	ReplicatedStorage:GetAttributeChangedSignal(FLAG):Connect(markDirty)

	-- A DOOR INTO THE RUNNING INSTANCE.
	--
	-- Every other context -- the command bar, and HudAudit when it is required from
	-- there -- gets its OWN copy of this module with an empty stack table. That is
	-- not a nuisance, it is a correctness hole: HudAudit's stack-overflow check
	-- called StackBudgets() on its own empty copy and cheerfully reported no
	-- problems, so the one check that can catch a corner running off the top was
	-- dead from the day it was written and looked like it was passing.
	--
	-- A BindableFunction is shared state in the DataModel rather than in a module
	-- table, so an Invoke from anywhere reaches the instance that actually owns the
	-- layout. Same reasoning as Platform keeping its override in an attribute.
	-- FIRST INSTANCE WINS. Do NOT replace an existing door.
	--
	-- The first version destroyed and recreated it, which inverted the whole point:
	-- requiring HudAudit from the command bar pulls in a second copy of THIS module,
	-- whose wiring then tore down the real HUD's door and hung its own -- bound to a
	-- stack table that is permanently empty. The budgets query started answering
	-- "nothing registered" the moment anything inspected it, which is precisely when
	-- it matters. The real owner is whichever copy a LocalScript required at join,
	-- and it gets there first.
	if not ReplicatedStorage:FindFirstChild("HudLayoutQuery") then
		local query = Instance.new("BindableFunction")
		query.Name = "HudLayoutQuery"
		query.OnInvoke = function(what: string?)
			if what == "budgets" then return HudLayout.StackBudgets() end
			if what == "debug" then return HudLayout.Debug() end
			return nil
		end
		query.Parent = ReplicatedStorage
	end

	-- Dump-on-attribute, so the running instance is the one that reports. See the
	-- note on Debug() above for why requiring this module from the command bar and
	-- calling Debug() there cannot work.
	local DUMP = "HudLayoutDump"
	ReplicatedStorage:GetAttributeChangedSignal(DUMP):Connect(function()
		if ReplicatedStorage:GetAttribute(DUMP) then
			print("\n" .. HudLayout.Debug())
			ReplicatedStorage:SetAttribute(DUMP, false)
		end
	end)

	-- ViewportSize reads (1,1) for a frame or two during boot, exactly as Platform
	-- documents. Take late readings so a HUD laid out against the bogus value is
	-- corrected rather than stranded.
	task.delay(1, markDirty)
	task.delay(3, markDirty)
end

return HudLayout
