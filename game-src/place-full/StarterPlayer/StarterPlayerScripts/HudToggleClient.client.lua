-- HudToggleClient: two independent HUD collapses.
--
--   UI TOGGLE     folds the nav rail out to the left and the SKIP/SHOPS/PLOT tabs up
--                 off the top. Sits directly above the luck chip, bottom-right -- except
--                 on TOUCH devices, where it is lifted clear of the corner square
--                 Roblox draws its jump button in (see uiTarget's clamp).
--   QUEST TOGGLE  folds the quest bar and the quest tracker out to the right. Its own
--                 smaller button, riding the tracker's edge and travelling out with
--                 it, so the two are separate choices rather than one switch.
--
-- WHAT IS NEVER HIDDEN, by explicit decision: the cash and emerald pills, the luck
-- chip, Sprint and the hotbar. Those are either live numbers you play against or
-- controls you play with -- a "clean screen" that takes them away is not clean, it is
-- broken. It also matters mechanically: the UI button anchors ITSELF to the luck
-- chip, so the chip has to be something that is always on screen.
--
-- Neither button can hide itself: with the rail folded there is no other route to
-- Settings, so a toggle that could vanish would be a one-way trip out of the UI.
--
-- ONE EXCEPTION, PHONE ONLY (2026-08-18): the whole HudToggleUI ScreenGui stands
-- down while a GameHUD panel is open, because phone panels are now near-fullscreen
-- modals and this pill drew on top of one. That does not break the rule above --
-- while a panel is up the panel's own close button is the route out, and the pill
-- returns the instant the panel does. See "panel yield" below. Desktop is unchanged.
--
-- ONE CLOCK MOVES EVERYTHING. Each collapse is a 0 (shown) to 1 (folded) timeline,
-- advanced at a fixed rate and shaped by a single easing curve in the driver at the
-- bottom; every surface, the quest button's position, the turn of its arrow and its
-- fade all read that one number. Nothing else animates, tweens or snaps.
--
-- That is not decoration, it is the fix. The first version had a tween, a 0.5s
-- polling loop, a 0.22s "settle" and geometry signals all writing the same Position,
-- cancelling each other mid-slide; and the panels themselves popped out instantly
-- while the button glided, which reads as broken even once the glide is smooth.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local modules = ReplicatedStorage:WaitForChild("Modules")

local UI = require(modules:WaitForChild("UIKit"):WaitForChild("Builders"))
local Platform = require(modules:WaitForChild("Platform"))
local okSound, SoundKit = pcall(function() return require(modules.SoundKit) end)
if not okSound then SoundKit = nil end

local saveRemote = remotes:WaitForChild("SettingsSave")
local dataRemote = remotes:WaitForChild("DataUpdated")

local navHidden, questsHidden = false, false
local userTouched = false  -- set by either button; see applySnapshot

---------------------------------------------------------------- the surfaces
-- `owner` picks which collapse drives it. `axis`/`sign` is the direction it leaves
-- in -- each surface exits the way it already faces, so nothing crosses the screen.
--
-- LEVELS ARE CHOSEN PER SURFACE and are not interchangeable:
--   NavRail    the rail FRAME only. Its parent Chrome also holds the currency pills,
--              which stay, so this cannot hide Chrome.
--   TabBar     the tabs only; the rest of MainUI is the hotbar and Sprint.
--   Quest*UI   the whole ScreenGui, because the scripts inside own their children's
--              .Visible -- QuestTrackerClient sizes its holder by row count -- and
--              writing those would fight them.
-- QuestTrackerUI IS NOT IN THIS LIST ANY MORE (2026-08-12). The quest tracker was
-- rebuilt to the "Quest Log HUD" design, whose collapse is a 52px RAIL that stays on
-- screen rather than a slide off the right edge -- and QuestTrackerClient now reads the
-- same `questsHidden` setting itself to choose between its panel and that rail. Sliding
-- the whole ScreenGui away from here as well would have taken the rail with it, so the
-- surface was removed and the state is now the only thing shared.
--
-- The button below still writes questsHidden, so it still collapses and expands the
-- quest log -- it just does it by flipping the setting the tracker is watching, instead
-- of by moving it. QuestBarUI (the Goals bar) still folds the old way; it has no rail.
local SURFACES = {
	{ owner = "quest", gui = "QuestBarUI", axis = "x", sign = 1 },
	{ owner = "nav", gui = "GameHUD", path = { "Chrome", "NavRail" }, axis = "x", sign = -1 },
	{ owner = "nav", gui = "MainUI", path = { "TabBar" }, axis = "y", sign = -1 },
}

-- MEASURE WHILE IT IS STILL SHOWN. A disabled ScreenGui stops being laid out and
-- reports stale nonsense -- this tracker reads AbsolutePosition (490, 74) while
-- folded against the (1610, 301) it renders at -- so travel distances can only be
-- taken from a live surface. Everything starts shown, and a saved fold needs a
-- server round trip to arrive, so the first frames are the window for this. If a
-- capture never lands, `fold` below falls back to showing and hiding outright:
-- correct, just not animated.
local function find(s)
	local g = playerGui:FindFirstChild(s.gui)
	if not g then return nil end
	if s.path then
		local node = g
		for _, name in ipairs(s.path) do
			node = node:FindFirstChild(name)
			if not node then return nil end
		end
		return node
	end
	local node = g:FindFirstChildWhichIsA("GuiObject")
	if not node then return nil end
	s.screen = g  -- a ScreenGui-backed surface: Enabled is the switch
	return node
end

-- Returns base position and travel distance, or nil if the surface cannot be trusted
-- yet. Re-run every frame the surface is at rest, not just once: the first frame a
-- surface reports a size is often before its layout has settled, and the nav rail was
-- captured three times wider than it ends up -- so it whipped off screen at triple the
-- speed of everything else, arriving early and reading as a jolt rather than a glide.
local function measure(s, node)
	-- Width only. A zero HEIGHT is legitimate here: QuestTrackerClient leaves its
	-- holder at 0 and lets the entries inside define the height, so demanding a real
	-- AbsoluteSize.Y blocked the tracker from ever being captured -- it fell back to
	-- popping while everything around it slid. Where a slide genuinely needs the size
	-- (anything exiting left or up), the `travel <= 0` test below catches it.
	if node.AbsoluteSize.X <= 0 then return end

	-- Platform.Viewport, not the raw camera (2026-08-26): identical live, and the
	-- difference under a device preview is the whole point -- see PlatformClient's
	-- fitPanels note. Platform.Viewport also never reads (1,1) during boot.
	local vp = Platform.Viewport

	-- AbsolutePosition IS NOT SAFE HERE, AbsoluteSize IS. Roblox stops laying out a
	-- hidden surface, and what is left behind is stale: this tracker reads
	-- AbsolutePosition (490, 74) while folded against the (1610, 301) it renders at.
	-- Measuring that gave a NEGATIVE travel and slid everything off the LEFT edge.
	-- AbsoluteSize survives, though -- both these surfaces are fixed-offset sized.
	--
	-- So position is DERIVED from the parent's rect when the surface is off screen,
	-- and only read directly when it is up and definitely laid out. Requiring it to be
	-- visible instead was the obvious fix and the wrong one: whichever surface had not
	-- finished appearing when a saved fold arrived got switched off, and could then
	-- never be measured at all -- so one of the two always fell back to popping while
	-- the other slid, and which one it was changed run to run.
	local shown = if s.screen then s.screen.Enabled else node.Visible
	local size = node.AbsoluteSize
	local pos
	if shown then
		pos = node.AbsolutePosition
	else
		local parent = node.Parent
		local pp, ps
		if parent and parent:IsA("GuiObject") then
			pp, ps = parent.AbsolutePosition, parent.AbsoluteSize
		else
			pp, ps = Vector2.zero, vp  -- a ScreenGui spans the viewport
		end
		local p = node.Position
		pos = Vector2.new(
			pp.X + p.X.Scale * ps.X + p.X.Offset - node.AnchorPoint.X * size.X,
			pp.Y + p.Y.Scale * ps.Y + p.Y.Offset - node.AnchorPoint.Y * size.Y)
	end
	-- WHERE THE SCREEN EDGE ACTUALLY IS. Not 0. AbsolutePosition is reported in a space
	-- whose origin sits below the topbar, so a ScreenGui with IgnoreGuiInset starts at
	-- -inset instead: the tab bar sits at AbsolutePosition.Y = -48 while rendering 10px
	-- down the screen. Treating the top as 0 made its travel come out 58px short, so it
	-- slid up, stopped with a third of itself still showing, and blinked out from there
	-- -- which is exactly what "glitching into place" looks like.
	local inset = GuiService:GetGuiInset()
	local ignore = false
	local sg = node:FindFirstAncestorWhichIsA("ScreenGui")
	if sg then ignore = sg.IgnoreGuiInset end
	local left = ignore and -inset.X or 0
	local top = ignore and -inset.Y or 0
	-- The far edges land in the same place either way: an inset-ignoring gui starts
	-- higher but is correspondingly taller.
	local right, bottom = vp.X - inset.X, vp.Y - inset.Y

	local travel
	if s.axis == "x" then
		travel = (s.sign > 0) and (right - pos.X) or ((pos.X + size.X) - left)
	else
		travel = (s.sign > 0) and (bottom - pos.Y) or ((pos.Y + size.Y) - top)
	end
	if travel <= 0 then return end  -- a reading that cannot be right; try again next frame
	return node.Position, travel + 8
end

local function capture(s)
	if s.node then return end
	local node = find(s)
	if not node then return end
	local base, travel = measure(s, node)
	if not base then return end
	s.node, s.base, s.travel = node, base, travel
end

local function setShown(s, on)
	if s.screen then
		if s.screen.Enabled ~= on then s.screen.Enabled = on end
	elseif s.node.Visible ~= on then
		s.node.Visible = on
	end
end

-- Applies one surface at progress `p`. The visibility rules here are what let this
-- coexist with SideRail, which folds QuestTrackerUI away on its own while a panel is
-- open (updateRailVisibility) and switches it back on when the last one closes:
--
--   fully folded  ours -- assert it stays hidden, so closing a panel cannot
--                 resurrect a tracker the player deliberately put away
--   mid-slide     ours -- it has to be on screen to be seen leaving
--   fully shown   NOT ours -- we write nothing, so SideRail stays free to hide it
--                 for its own good reason (its cards cover a panel's left column)
--
-- The same rule covers Position: while shown, `base` is re-read rather than written,
-- so if anything ever re-lays out the HUD we follow it instead of pinning it to a
-- stale spot.
local function fold(s, p)
	if not s.node then
		-- NEVER MEASURED, SO IT CANNOT SLIDE -- show and hide it outright instead.
		-- A surface can legitimately be off screen for the whole window we look in:
		-- QuestBarClient owns its own bar and a dismissed one stays disabled, so
		-- there is nothing to measure and nothing we should force back on.
		--
		-- Note this follows the SAME ownership rule as the animated path below: while
		-- fully shown we write nothing at all, which leaves the surface's real owner
		-- in charge and lets capture() succeed later, the next time it appears. The
		-- fold then upgrades itself from a pop to a slide with no further help.
		local g = playerGui:FindFirstChild(s.gui)
		if g and g:IsA("ScreenGui") and not s.path then
			if p > 0.995 then g.Enabled = false
			elseif p > 0.001 then g.Enabled = true end
		end
		return
	end
	if p <= 0.001 then
		-- At rest the surface belongs to whoever built it, so re-measure rather than
		-- write: base and travel both stay current, which is what lets a first reading
		-- taken before the layout settled correct itself instead of being lived with.
		local base, travel = measure(s, s.node)
		if base then s.base, s.travel = base, travel end
		return
	end
	setShown(s, p < 0.995)
	local d = s.travel * p * s.sign
	s.node.Position = s.base + UDim2.fromOffset(
		s.axis == "x" and d or 0,
		s.axis == "y" and d or 0)
end

---------------------------------------------------------------- shell
local gui = Instance.new("ScreenGui")
gui.Name = "HudToggleUI"
gui.ResetOnSpawn = false
-- 11 clears the passive HUD (7) and the panel ScreenGuis that sit enabled-but-empty
-- at 8-9 (Trade, Booth, Fusion, Rebirth) whose full-screen canvases would otherwise
-- layer over these buttons -- while staying under the wheel (12), the egg shop (25)
-- and toasts (60), which SHOULD cover them.
gui.DisplayOrder = 11
gui.IgnoreGuiInset = true
-- Hidden until the driver has a real measurement to place the buttons with: showing
-- them first means showing them in the wrong place.
gui.Enabled = false
gui.Parent = playerGui

---------------------------------------------------------------- panel yield (PHONE)
-- WHO OWNS gui.Enabled. Two owners, and they are not symmetric, so neither writes
-- the property directly -- both set their own flag and call applyShell():
--
--   primed      the driver's. False until it has a real measurement and has placed
--               the buttons; the reveal must never beat the placement.
--   panelYield  the phone panel watch's, below.
--
-- THE FOLD IS DELIBERATELY NOT AN OWNER, and that is what keeps folding intact. By
-- this file's founding rule neither button may ever hide itself, so no fold state
-- ever wants this ScreenGui switched off -- which makes "restore what the fold
-- wants" and "recompute from the flags" the same answer, and lets a panel close
-- just call applyShell() instead of asserting true.
--
-- What the fold DOES say about the pill -- its position, and the 0.35 -> 0 fade that
-- reads folded vs unfolded -- is written every frame by the driver off cur.nt, and
-- the yield never touches cur. So the pill comes back wearing exactly the fold state
-- it left with, a fold caught mid-slide included. If the fold ever does gain an
-- opinion about Enabled, it belongs in the one expression below and nowhere else.
local primed = false
local panelYield = false

local function applyShell()
	local want = primed and not panelYield
	if gui.Enabled ~= want then gui.Enabled = want end
end

-- STAND DOWN WHILE A GameHUD PANEL IS OPEN -- PHONE ONLY (2026-08-18). Phone HUD
-- panels were just enlarged ~61% (the counter-band reserve that crushed them to
-- 0.299 scale is gone; they run at Platform.FitPanel ~0.483) and now read as
-- near-fullscreen MODALS. This ScreenGui sits at DisplayOrder 11, above GameHUD's 7,
-- so the pill drew straight over one. GameHUDClient's openPanel already stands the
-- nav rail and the currency cluster down on phone; this was the surface left over.
--
-- Same tell every other yielding surface watches: GameHUD.Canvas.PanelHost.Visible,
-- which openPanel sets true and closePanel drops false after its close tween.
-- QuestBarClient and ClientMain's teleport bar keep the identical contract.
--
-- DESKTOP IS UNTOUCHED, on purpose. There the panels float inside the canvas fit
-- with this corner well clear, so there is nothing to yield to -- and taking the
-- pill away while the rail is folded would remove the only route back to the UI.
--
-- Platform.IsPhone is read INSIDE sync rather than captured once, and Platform.Watch
-- re-runs sync on every device change, so a PlatformOverride flip or a real change of
-- device class is honoured live instead of frozen at require time. Watch also calls
-- sync immediately, which is the initial read.
task.spawn(function()
	local hud = playerGui:WaitForChild("GameHUD", 30)
	local canvas = hud and hud:WaitForChild("Canvas", 10)
	local panelHost = canvas and canvas:WaitForChild("PanelHost", 10)
	if not panelHost then return end
	local function sync()
		panelYield = Platform.IsPhone and panelHost.Visible
		applyShell()
	end
	panelHost:GetPropertyChangedSignal("Visible"):Connect(sync)
	Platform.Watch(sync)
end)

---------------------------------------------------------------- buttons
-- TOUCH FLOOR (2026-08-25, measured 151x34 on a phone-classed client): 10px
-- under Roblox's 44px minimum, on the control that gets you back OUT of a
-- hidden HUD -- miss it and there is nothing else to press. UI_H feeds the
-- corner stack's collision maths below (the zone tests and the chip stacking)
-- as well as the button's own size, so the floor belongs on the constant --
-- writing it onto the instance would leave the layout believing 34.
local UI_W, UI_H = 138, (Platform.IsTouch and 44 or 34)
local uiBtn = UI.button(gui, "HIDE UI", "tab", UDim2.fromOffset(UI_W, UI_H), "buttonM")
uiBtn.Name = "UiToggle"
uiBtn.AnchorPoint = Vector2.new(0, 0)
uiBtn.ZIndex = 50

-- HUDLAYOUT OWNS THIS PILL'S POSITION (2026-08-26).
--
-- It used to chase uiTarget(), which read LuckHUD's chip rect every frame and
-- fell back to a hardcoded (1766, 863) when that read looked implausible -- a
-- desktop coordinate, i.e. off the side of a phone. That anchor is the reason
-- this file carries a jump-corner clamp, a plausibility test, and the warning in
-- LuckHUDClient that its chip must never be hidden with gui.Enabled. All of it
-- was scaffolding around one peer dependency.
--
-- Now it declares a slot: top of the bottom-right stack, above RIDE and the luck
-- chip. The stack measures its own members, so nothing here reads anything.
local HudLayout = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("HudLayout"))
HudLayout.PrepareGui(gui, "Toggle")
local uiSlot = HudLayout.Attach(uiBtn, {
	stack = "BottomRight",
	order = HudLayout.Order.HideUI,
})

-- Cluster width without measuring a neighbour: the luck chip wears the same
-- scale from the same shared source, so the two land at matching widths.
if uiSlot then
	local uiScale = Instance.new("UIScale")
	uiScale.Name = "DeviceScale"
	uiScale.Parent = uiBtn
	Platform.Watch(function()
		uiScale.Scale = HudLayout.ChipScale()
		-- SIZED LIVE, not from the UI_H captured at require time. UI_H reads
		-- Platform.IsTouch once, at load, and a device class settled after that --
		-- or changed mid-session -- left this pill at the desktop 34px, rendering
		-- 37 on a phone. This is the control that gets you back out of a hidden
		-- HUD: miss it and there is nothing else to press.
		uiBtn.Size = UDim2.fromOffset(HudLayout.ChipWidth(), HudLayout.ChipHeight())

		-- THIS PILL KEEPS THE CORNER. See ScooterButtonClient: on a short phone the
		-- bottom-right column can hold two of the three controls, and RIDE is the one
		-- that leaves. HIDE UI and Sprint are the two a player reaches for, so they
		-- stay under the thumb that is already on the jump button.

		-- UI.hardShadow COPIES the frame's size once, at construction, and thereafter
		-- only tracks Position -- so a pill that narrows for a phone left a shadow at
		-- the old 138px width sticking out from under it (measured 21% of a 667px
		-- screen, wider than the button casting it). Resize it alongside.
		local shadow = uiBtn.Parent and uiBtn.Parent:FindFirstChild("HardShadow")
		if shadow and shadow:IsA("GuiObject") then
			shadow.Size = uiBtn.Size
		end
	end)
end
local uiCap = uiBtn:FindFirstChildWhichIsA("TextLabel")
if uiCap then uiCap.TextSize = 14; uiCap.ZIndex = uiBtn.ZIndex + 1 end
-- 2026-08-17 corner-cluster unification: the bottom-right controls share the
-- sticker language from ClientMain's sticker pass (vivid fill + WHITE
-- keyline). This one takes Sprint's sky pair so the two system buttons in the
-- stack read as one family; the "tab" variant's navy plate + dark rim retire.
do
	for _, s in ipairs(uiBtn:GetChildren()) do
		if s:IsA("UIStroke") then s.Transparency = 1 end
	end
	local key = Instance.new("UIStroke")
	key.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	key.LineJoinMode = Enum.LineJoinMode.Round
	key.Color = Color3.new(1, 1, 1)
	key.Thickness = 2.5
	key.Parent = uiBtn
	local skyTop, skyBot = Color3.fromRGB(116, 196, 255), Color3.fromRGB(26, 116, 228)
	uiBtn.BackgroundColor3 = skyTop -- multiply trap: base moves WITH the gradient
	local grad = uiBtn:FindFirstChildOfClass("UIGradient")
	if grad then
		grad.Color = ColorSequence.new(skyTop, skyBot)
	else
		grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Color = ColorSequence.new(skyTop, skyBot)
		grad.Parent = uiBtn
	end
	if uiCap then
		uiCap.TextColor3 = Color3.new(1, 1, 1)
		local gs = uiCap:FindFirstChildOfClass("UIStroke")
		if not gs then
			gs = Instance.new("UIStroke")
			gs.Parent = uiCap
		end
		gs.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		gs.Color = Color3.fromRGB(14, 52, 110)
		gs.Thickness = 2
		gs.Transparency = 0
	end
end

-- Deliberately small and glyph-only: a secondary control in the busiest corner of
-- the screen, and a second word-pill up there would be the clutter this removes.
local Q = 36
-- RETIRED 2026-08-12 (owner: "remove this from the game, we dont need this anymore").
-- This little round arrow was the ONLY way to fold the quest tracker away. The tracker
-- was rebuilt to the Quest Log design, which carries its own controls -- the header's
-- collapse chevron, the whole collapsed rail as a click target, and the J key -- so this
-- became a second, worse door to the same setting sitting on top of the panel.
--
-- It is built and then hidden rather than deleted: the fold driver at the bottom writes
-- its Position, Rotation and transparencies every frame, and half of those writes are
-- interleaved with the nav rail's. Keeping the instance costs one invisible 36px button
-- and keeps that driver in one piece; deleting it means unpicking the driver, which is
-- the part of this file with the long comment about why it must stay a single clock.
-- Snapshot first: UI.button parents its drop shadow as a SIBLING of the button, not as
-- a child, so hiding the button alone left a 36px dark disc floating beside the quest
-- log with nothing on top of it. There are two HardShadow frames in this ScreenGui (the
-- UI toggle owns the other one), so the new one is found by diffing rather than by name.
local beforeBtn = {}
for _, c in ipairs(gui:GetChildren()) do beforeBtn[c] = true end

local questBtn = UI.button(gui, "\u{25B6}", "tab", UDim2.fromOffset(Q, Q), "buttonM")
questBtn.Name = "QuestToggle"
questBtn.Visible = false
questBtn.Active = false

-- everything UI.button added alongside the button itself goes with it
for _, c in ipairs(gui:GetChildren()) do
	if not beforeBtn[c] and c ~= questBtn and c:IsA("GuiObject") then
		c.Visible = false
	end
end
questBtn.AnchorPoint = Vector2.new(1, 0)
questBtn.ZIndex = 50
local questCap = questBtn:FindFirstChildWhichIsA("TextLabel")
if questCap then
	questCap.TextSize = 18
	questCap.ZIndex = questBtn.ZIndex + 1
	-- CENTRED ON ITS OWN CENTRE, because Rotation pivots about the AnchorPoint and
	-- UI.button leaves that at the top-left corner. The arrow turns through 180 as
	-- the quests fold (see the driver), and half a turn about a corner swings it
	-- clean off the plate instead of flipping it where it stands. Same rect as
	-- before: a (0.5, 0.5) anchor at scale-centre with a full-size label.
	questCap.AnchorPoint = Vector2.new(0.5, 0.5)
	questCap.Position = UDim2.fromScale(0.5, 0.5)
end

-- HOVER AND PRESS HAVE TO BE DRIVEN, NOT TWEENED. UI.button ships its own 2px lift
-- on MouseEnter, and on this button it has never once reached the screen: the driver
-- below writes Position every frame, so the tween is overwritten before it renders.
-- The state is tracked here and the response applied where position and scale are
-- actually decided. Until now this was the only control in the corner that did not
-- answer the mouse at all.
--
-- A UIScale is safe to WRITE per frame even though TweenService cannot animate one
-- in this place (the rail hit the same wall -- see GameHUDClient's note on the
-- "scale 1.03" hover that never scaled anything). 1.08 / 0.92 are the rail's own
-- hover and press multipliers, so the two controls answer alike.
local Q_HOVER, Q_PRESS = 1.08, 0.92
local questScale = Instance.new("UIScale")
questScale.Parent = questBtn
local questHovered, questPressed = false, false
questBtn.MouseEnter:Connect(function() questHovered = true end)
questBtn.MouseLeave:Connect(function()
	-- pressed clears too: a press dragged off the button never sends MouseButton1Up,
	-- and it would stay squashed for good.
	questHovered, questPressed = false, false
end)
questBtn.MouseButton1Down:Connect(function() questPressed = true end)
questBtn.MouseButton1Up:Connect(function() questPressed = false end)

---------------------------------------------------------------- where they belong
-- These describe DESTINATIONS only. Nothing here writes a position; the driver owns
-- that. Keeping "where" apart from "how it gets there" is what stops writers fighting.

-- The UI button anchors to the luck chip rather than a fixed corner: the chip is
-- always on screen, and measuring it means the button stays put whatever the viewport
-- or the chip's own width does. (An earlier version hardcoded an x beside the cash
-- pill and ended up underneath it, because sizePillToValue grows that pill with the
-- number -- 270px wide at one balance, 392 at another.)
local UI_GAP = 8
local UI_FALLBACK_X, UI_FALLBACK_Y = 1766, 863

-- TOUCH ONLY. Roblox draws its jump button in the bottom-right corner of every
-- touch screen, and the chip anchor can put this pill straight under the player's
-- jump thumb. The anchor is kept -- it is still what survives resizes and the
-- cash pill growing -- and a final clamp is added on top: if the rect it produces
-- overlaps the corner square the jump button owns, the pill is LIFTED above the
-- square. Up rather than left, because up keeps the chip's x-alignment and
-- stacking above the Sprint cluster is fine, while left walks it into the
-- bottom-centre thumb corridor. Desktop never enters the branch, so its position
-- is unchanged. Platform.IsTouch is a live field (refreshed on device changes and
-- the PlatformOverride attribute), so reading it per frame tracks all of that.
local JUMP_CORNER = 140  -- px on a side, matching Platform's TOUCH_CONTROL_BAND

local function clearJumpCorner(x, y, w)
	if not Platform.IsTouch then return x, y end
	-- Platform.Viewport, not the raw camera (2026-08-26) -- see the note above.
	local vp = Platform.Viewport
	-- Same screen-edge arithmetic as measure(): AbsolutePosition space ends at
	-- vp - inset, not at vp.
	local inset = GuiService:GetGuiInset()
	local zoneX = (vp.X - inset.X) - JUMP_CORNER
	local zoneY = (vp.Y - inset.Y) - JUMP_CORNER
	if x + w > zoneX and y + UI_H > zoneY then
		y = zoneY - UI_H - UI_GAP
	end
	return x, y
end

local function uiTarget()
	local g = playerGui:FindFirstChild("LuckHUD")
	local chip = g and g:FindFirstChildWhichIsA("GuiObject")
	if chip and chip.AbsoluteSize.X > 0 then
		local w = math.max(UI_W, chip.AbsoluteSize.X)
		local x, y = clearJumpCorner(chip.AbsolutePosition.X,
			chip.AbsolutePosition.Y - UI_GAP - UI_H, w)
		return x, y, w
	end
	local x, y = clearJumpCorner(UI_FALLBACK_X, UI_FALLBACK_Y, UI_W)
	return x, y, UI_W
end

-- The quest button rides the fold: on the tracker's left edge while the quests are
-- up, out at the screen edge once they have gone, and interpolated between the two by
-- the same progress that moves the panels -- so it travels with them rather than
-- chasing them.
--
-- The plausibility test is doing real work. The tracker is pinned to the right edge
-- (QuestTrackerClient:259, holder.Position = UDim2.new(1, -14, 0.40, 0)), so any real
-- layout puts its right edge within a few pixels of the viewport's. A disabled or
-- mid-relayout tracker fails that by over a thousand pixels; without the test the
-- button lurched across the screen and back every time the quests came back.
local Q_GAP = 8
local Q_SCREEN_INSET = 14  -- matches the tracker's own margin, so it lands where the panel was
local Q_EDGE_TOLERANCE = 60
local Q_FALLBACK_Y = 390
local lastQuestX, lastQuestY = nil, nil

-- `atRest` is not an optimisation, it is correctness. The anchor wanted here is where
-- the tracker SITS, and mid-fold the tracker is somewhere between its two homes --
-- because we are the ones moving it. Reading it then makes the button interpolate
-- toward a target that is itself sliding, and the two curves compound into a
-- backwards kick: on an unfold the button ran 1713 -> 1636 -> 1665 -> 1615, visibly
-- stuttering against panels that were gliding cleanly. So the anchor is only re-read
-- while the fold is fully at rest, and held frozen for the length of any transition.
local function questAnchor(atRest)
	-- Platform.Viewport, not the raw camera (2026-08-26) -- see the note above.
	local vw = Platform.Viewport.X
	if atRest then
		local g = playerGui:FindFirstChild("QuestTrackerUI")
		local tr = g and (g:FindFirstChild("Tracker") or g:FindFirstChildWhichIsA("GuiObject"))
		if tr and tr.AbsoluteSize.X > 0
			and math.abs(vw - (tr.AbsolutePosition.X + tr.AbsoluteSize.X)) < Q_EDGE_TOLERANCE then
			lastQuestX = tr.AbsolutePosition.X - Q_GAP
			lastQuestY = tr.AbsolutePosition.Y + (tr.AbsoluteSize.Y - Q) * 0.5
		end
	end
	return lastQuestX or (vw - Q_SCREEN_INSET), lastQuestY or Q_FALLBACK_Y, vw - Q_SCREEN_INSET
end

---------------------------------------------------------------- state
local function paint()
	if uiCap then uiCap.Text = navHidden and "SHOW UI" or "HIDE UI" end
	-- THE QUEST ARROW IS NOT SWAPPED HERE. It is one glyph that turns: pointing right
	-- while the quests are up, left once they have gone, and every angle between the
	-- two on the way out. Arrows point along the fold either way -- the quests slide
	-- out to the right edge and come back in from it -- but swapping the character was
	-- the last thing on this button that still happened in one frame while everything
	-- around it glided. The driver owns the angle; see questCap.Rotation.
end

local function setNav(v, save)
	navHidden = v and true or false
	paint()
	if save then saveRemote:FireServer({ navHidden = navHidden }) end
end

local function setQuests(v, save)
	questsHidden = v and true or false
	paint()
	if save then saveRemote:FireServer({ questsHidden = questsHidden }) end
end

uiBtn.Activated:Connect(function()
	userTouched = true
	setNav(not navHidden, true)
	if SoundKit then pcall(function() SoundKit.play("uiClick", nil, { volume = 0.16 }) end) end
end)
questBtn.Activated:Connect(function()
	userTouched = true
	setQuests(not questsHidden, true)
	if SoundKit then pcall(function() SoundKit.play("uiClick", nil, { volume = 0.16 }) end) end
end)

---------------------------------------------------------------- saved preference
-- FOLLOW THE SERVER UNTIL THE PLAYER TAKES OVER.
--
-- This used to latch onto the first snapshot carrying a Settings table, on the
-- reasoning that DataUpdated fires for every cash tick and re-applying each time
-- would fight someone who had just pressed a button. That was the wrong latch: the
-- first DataUpdated of a session can arrive before the profile has finished loading,
-- carrying a default Settings table, and locking onto that made a saved fold come up
-- unfolded -- with the save still holding the value it failed to honour.
--
-- Tracking until the first press is right in every ordering: before a press the
-- server is the only opinion worth having, and after one the local value is, so a
-- late echo cannot flip the HUD out from under someone.
local function applySnapshot(snap)
	if typeof(snap) ~= "table" then return end
	local st = snap.Settings
	if typeof(st) ~= "table" then return end
	if userTouched then return end
	local wantNav = (st.navHidden == true)
	local wantQuests = (st.questsHidden == true)
	if wantNav ~= navHidden then setNav(wantNav, false) end
	if wantQuests ~= questsHidden then setQuests(wantQuests, false) end
end

dataRemote.OnClientEvent:Connect(applySnapshot)
task.spawn(function()
	local ok, snap = pcall(function() return remotes.GetInitialData:InvokeServer() end)
	if ok then applySnapshot(snap) end
end)

---------------------------------------------------------------- the driver
-- TWO KINDS OF MOTION, and they are not interchangeable.
--
-- THE FOLD IS A TIMELINE. `nt`/`qt` run 0 -> 1 at a fixed dt/FOLD_TIME, and are
-- shaped by smootherstep before anything reads them. The fold used to be an
-- exponential ease -- `v += (target - v) * (1 - exp(-k*dt))` -- which is smooth but
-- has no ease-IN: it left at full speed on the frame you pressed and then crawled
-- the last handful of pixels, arriving only because an epsilon rounded it off.
-- Shaped, it accelerates away, decelerates in, and lands exactly, at a time you can
-- name. Reversing mid-fold still just works: the timeline turns round from wherever
-- it is, so the panels change direction from where they ARE rather than restarting.
--
-- THE ANCHORS ARE A CHASE, so they stay exponential. There is no start and no end to
-- shape -- the luck chip and the tracker move for their own reasons, and beside the
-- tracker the target genuinely does change every frame as entries scale in -- so the
-- buttons simply have to keep up. `1 - exp(-k*dt)` keeps that frame-rate independent:
-- the same glide at 30fps and at 240fps, where a plain per-frame lerp would run four
-- times faster on the better machine.
local FOLD_TIME = 0.34   -- seconds edge to edge, the same both directions
local FOLLOW_RATE = 14   -- buttons tracking their anchors
local FX_RATE = 16       -- the quest button's own hover / press

local cur = nil
local primeBy = os.clock() + 1

local function ease(v, target, a, eps)
	v += (target - v) * a
	return (math.abs(target - v) < (eps or 0.35)) and target or v
end

-- Linear, clamped, symmetric. All the shaping happens after.
local function approach(v, target, step)
	if v < target then return math.min(v + step, target) end
	return math.max(v - step, target)
end

-- smootherstep, 6t^5 - 15t^4 + 10t^3: zero velocity AND zero acceleration at both
-- ends, so neither the start nor the stop has an edge on it. Plain smoothstep leaves
-- acceleration discontinuous at the ends, which over this much travel shows as a
-- small kick as the panels let go.
local function shape(t)
	return t * t * t * (t * (t * 6 - 15) + 10)
end

RunService.RenderStepped:Connect(function(dt)
	local captured = true
	for _, s in ipairs(SURFACES) do
		capture(s)
		if not s.node then captured = false end
	end

	local ux, uy, uw = uiTarget()
	local shownX, anchorY, edgeX = questAnchor(cur == nil or cur.qt <= 0)
	local navGoal = navHidden and 1 or 0
	local questGoal = questsHidden and 1 or 0

	if not cur then
		-- PRIME ONCE, ON A REAL MEASUREMENT. The buttons must appear already in place;
		-- easing them in from a guess is the join-time version of the glitchiness this
		-- exists to remove. The tracker is not measurable for the first frames, so
		-- priming immediately would put the quest button at the screen edge and then
		-- visibly slide it 300px inward. Folded needs no measurement, so it is ready
		-- at once; the timeout is the backstop for a tracker that never turns up.
		-- Capture must finish FIRST: folding a surface before it has been measured
		-- switches it off, and then it can never be measured. See capture().
		local timedOut = os.clock() > primeBy
		-- Only wait on capture if something is actually going to fold; with nothing
		-- folded there is no measurement to get wrong, so do not stall the reveal.
		if (navHidden or questsHidden) and not (captured or timedOut) then return end
		if not (questsHidden or lastQuestX or timedOut) then return end
		cur = {
			ux = ux, uy = uy, qy = anchorY,
			nt = navGoal, qt = questGoal,
			fx = 1,
		}
		-- Through applyShell rather than straight to Enabled: a phone panel already
		-- open at prime time must win, or the reveal would drop the pill on top of it.
		primed = true
		applyShell()
	else
		local follow = 1 - math.exp(-FOLLOW_RATE * dt)
		cur.ux = ease(cur.ux, ux, follow)
		cur.uy = ease(cur.uy, uy, follow)
		cur.qy = ease(cur.qy, anchorY, follow)

		-- CAPPED so one monstrous dt cannot cross the whole fold in a single frame.
		-- A surface that was never measured is shown and hidden outright by fold(),
		-- and it re-enables one only while 0.001 < p < 0.995 -- mid-slide. Stepping
		-- 1 -> 0 in one go steps straight over that window and the surface stays
		-- switched off. Not hypothetical: Studio in the background renders at ~4fps,
		-- which is one frame either side of it. At 0.5 a fold is always at least two
		-- steps, so there is always a frame in the middle to catch.
		local step = math.min(dt / FOLD_TIME, 0.5)
		cur.nt = approach(cur.nt, navGoal, step)
		cur.qt = approach(cur.qt, questGoal, step)

		-- eps well under a pixel of a 36px button, or the scale visibly stair-steps
		cur.fx = ease(cur.fx, questPressed and Q_PRESS or (questHovered and Q_HOVER or 1),
			1 - math.exp(-FX_RATE * dt), 0.002)
	end

	-- Shaped ONCE, here, and read by everything downstream: the panels, the button's
	-- x, its arrow and both fades. Nothing past this line eases anything of its own.
	local np, qp = shape(cur.nt), shape(cur.qt)

	for _, s in ipairs(SURFACES) do
		fold(s, s.owner == "nav" and np or qp)
	end

	-- IgnoreGuiInset SUBTRACTS the topbar inset from where a child lands, so a bare
	-- Position of (x, 28) rendered at y -30 against a 58px inset -- off the top of the
	-- screen, with every click sailing past into the world. Adding it back puts a
	-- button where the number says. Read per frame: it varies by device and topbar,
	-- and can change mid-session.
	local inset = GuiService:GetGuiInset().Y
	-- LEGACY PATH ONLY. With V2 on, HudLayout has already placed this pill and
	-- sized it from the shared chip scale; writing either here every frame is
	-- precisely the overwrite that made the corner uncorrectable before.
	if not uiSlot then
		uiBtn.Position = UDim2.fromOffset(math.round(cur.ux), math.round(cur.uy) + inset)
		if uiBtn.Size.X.Offset ~= uw then uiBtn.Size = UDim2.fromOffset(uw, UI_H) end
	end

	-- x comes straight from the fold progress rather than easing separately: the
	-- button and the panels then move as one thing, which is the whole illusion.
	local qx = shownX + (edgeX - shownX) * qp
	questBtn.Position = UDim2.fromOffset(math.round(qx), math.round(cur.qy) + inset)
	questScale.Scale = cur.fx
	-- Half a turn spread across the whole fold: right at rest, left once folded, and
	-- the same progress everywhere in between. See paint().
	if questCap then questCap.Rotation = 180 * qp end

	-- Quiet while its surface is up (the button is furniture too, and less furniture
	-- is the point); solid once folded, when it is the only way back. Read off the
	-- shaped fold rather than a second, slower clock of its own -- two rates meant the
	-- button was still fading a beat after it had stopped moving.
	uiBtn.BackgroundTransparency = 0.35 - np * 0.35
	if uiCap then uiCap.TextTransparency = 0.25 - np * 0.25 end
	questBtn.BackgroundTransparency = 0.35 - qp * 0.35
	if questCap then questCap.TextTransparency = 0.25 - qp * 0.25 end
end)

paint()
