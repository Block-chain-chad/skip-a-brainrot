--!strict
-- PlatformClient: the device-specific behaviour that would otherwise mean
-- hand-editing all 27 client UI scripts. Two jobs.
--
-- 1. SAFE AREA on every ScreenGui.
--    Not one gui in this place set ScreenInsets, so on a notched handset the
--    HUD ran underneath the camera cutout, and on a TV the outer few percent
--    sat in the overscan where it is simply not drawn. Applied per-gui and
--    preserving each one's intent, because ScreenInsets supersedes
--    IgnoreGuiInset and the two must not disagree:
--      IgnoreGuiInset = true  -> DeviceSafeInsets   (full screen, minus cutouts)
--      IgnoreGuiInset = false -> CoreUISafeInsets   (also clears the topbar)
--    Both are no-ops on a desktop monitor, which is why this is safe to apply
--    blanket rather than gui by gui.
--
-- 2. GAMEPAD NAVIGATION.
--    `Selectable` and `SelectionGroup` returned ZERO hits across every script
--    in the place, which means that on a console a player could see the UI and
--    had no way to move through it -- the game was unplayable on a controller
--    even though it rendered fine. Every GuiButton becomes selectable while a
--    gamepad is the active input, and pressing a direction with nothing
--    selected parks the highlight on the topmost visible button so navigation
--    can start. Selection is dropped again the moment the player goes back to
--    mouse or touch, so the highlight box never appears on other devices.

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Platform = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Platform"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------- 1. safe area
local function applyInsets(gui: Instance)
	if not gui:IsA("ScreenGui") then return end
	-- pcall: ScreenInsets is a newer property and a stray older client should
	-- lose the notch handling, not the whole HUD.
	pcall(function()
		(gui :: any).ScreenInsets = gui.IgnoreGuiInset
			and Enum.ScreenInsets.DeviceSafeInsets
			or Enum.ScreenInsets.CoreUISafeInsets
	end)
end

for _, gui in ipairs(playerGui:GetChildren()) do
	applyInsets(gui)
end
playerGui.ChildAdded:Connect(applyInsets)

----------------------------------------------------------------- 2. gamepad
local selectableTagged: { [Instance]: boolean } = {}

local function wantsGamepad(): boolean
	return Platform.IsConsole or Platform.IsGamepad
end

local function tag(inst: Instance)
	if inst:IsA("GuiButton") and not selectableTagged[inst] then
		selectableTagged[inst] = true
		inst.Selectable = true
	end
end

local function tagAll()
	for _, d in ipairs(playerGui:GetDescendants()) do
		tag(d)
	end
end

-- Walks up to the ScreenGui: a button inside a hidden panel is still
-- Visible=true itself, so selecting it would move the highlight to something
-- the player cannot see.
local function shownOnScreen(btn: GuiButton, gui: ScreenGui): boolean
	if not btn.Visible or not btn.Active then return false end
	if btn.AbsoluteSize.X < 8 or btn.AbsoluteSize.Y < 8 then return false end
	local p: Instance? = btn.Parent
	while p and p ~= gui do
		if p:IsA("GuiObject") and not p.Visible then return false end
		p = p.Parent
	end
	return true
end

local function firstSelectable(): GuiButton?
	local best: GuiButton?, bestOrder = nil, -math.huge
	for _, gui in ipairs(playerGui:GetChildren()) do
		if gui:IsA("ScreenGui") and gui.Enabled then
			for _, d in ipairs(gui:GetDescendants()) do
				if d:IsA("GuiButton") and shownOnScreen(d, gui) and gui.DisplayOrder >= bestOrder then
					best, bestOrder = d, gui.DisplayOrder
				end
			end
		end
	end
	return best
end

-- ===================== GAMEPAD UI: A VIRTUAL CURSOR =====================
--
-- THE BUG THIS REPLACES. The old set below started menu navigation on ANY of the
-- D-pad, ButtonA, or Thumbstick1:
--
--     [Enum.KeyCode.ButtonA] = true, [Enum.KeyCode.Thumbstick1] = true,
--
-- ButtonA is JUMP. Pressing it parked GuiService.SelectedObject on the topmost
-- visible HUD button, and from that moment every A press activated that button
-- instead of jumping -- the player could no longer jump at all. Thumbstick1 is the
-- MOVEMENT stick, so simply walking armed the same trap. Neither may ever begin
-- selection.
--
-- WHY A CURSOR RATHER THAN SELECTION LINKS. Nearly all UI in this place is built at
-- runtime and driven by MOUSE events: 18 client scripts fire only MouseButton1Click
-- with no .Activated anywhere, PanelChrome drags its slider on MouseMovement, and 11
-- scripts change state on MouseEnter hover. A selection highlight cannot drag a
-- slider or hover, and rewriting 18 files is the fragile fix. The virtual cursor
-- generates REAL pointer events, so every one of those handlers works untouched.
--
-- WHEN IT IS ON. The cursor takes the right stick away from the camera, so it is only
-- active while a full-screen panel is actually open, plus a manual toggle on
-- ButtonSelect (the View button -- the only conventional face/menu button not already
-- bound: A/B/X, L3 and R2 are all taken).
local GamepadService = game:GetService("GamepadService")
local RunService = game:GetService("RunService")
-- (no `camera` upvalue: every viewport read in this file now goes through
-- Platform.Viewport, which is the same number live and is the only one a device
-- preview can drive. A cached CurrentCamera would also go stale on respawn.)

-- A panel counts as OPEN only if it is big, actually drawn, and every ancestor up to
-- the ScreenGui is visible. That last part is the trap: closed panels in this game
-- routinely leave their own frame Visible = true and switch off only the PARENT, so a
-- test that checks the object alone reports "open" during ordinary play.
local function ancestorsVisible(obj: Instance, gui: Instance): boolean
	local p: Instance? = obj.Parent
	while p and p ~= gui do
		if p:IsA("GuiObject") and not p.Visible then return false end
		p = p.Parent
	end
	return true
end

local function isPanelOpen(): boolean
	-- Platform.Viewport, NOT camera.ViewportSize (2026-08-26). Identical on a real
	-- device, so live behaviour does not move; under a device preview the camera is
	-- still the Studio window, so this ratio was comparing PREVIEW-SIZED
	-- AbsoluteSize against a DESKTOP viewport and came out about a third of what it
	-- should be -- no frame ever reached 28% and no panel was ever seen as open.
	local vp = Platform.Viewport
	for _, gui in ipairs(playerGui:GetChildren()) do
		if gui:IsA("ScreenGui") and gui.Enabled then
			for _, d in ipairs(gui:GetDescendants()) do
				if d:IsA("GuiObject") and d.Visible then
					local sz = d.AbsoluteSize
					if sz.X >= vp.X * 0.28 and sz.Y >= vp.Y * 0.28 then
						-- a fully transparent container is a layout box, not a panel
						local drawn = false
						if d:IsA("ImageLabel") or d:IsA("ImageButton") then
							drawn = d.ImageTransparency < 0.95 or d.BackgroundTransparency < 0.95
						elseif d:IsA("GuiObject") then
							drawn = d.BackgroundTransparency < 0.95
						end
						if drawn and ancestorsVisible(d, gui) then return true end
					end
				end
			end
		end
	end
	return false
end

local cursorOn = false
local manualCursor = false

local function setCursor(on: boolean)
	if on == cursorOn then return end
	cursorOn = on
	local ok = pcall(function()
		if on then
			GamepadService:EnableGamepadCursor(nil)
		else
			GamepadService:DisableGamepadCursor()
		end
	end)
	if not ok then
		-- Very old clients have no GamepadService. Fall back to the selection
		-- highlight so a controller is not left with no way through the UI at all.
		cursorOn = false
		if on then
			local target = firstSelectable()
			if target then GuiService.SelectedObject = target end
		elseif GuiService.SelectedObject then
			GuiService.SelectedObject = nil
		end
	end
end

-- ButtonSelect toggles the cursor by hand, for anything the panel test misses.
UserInputService.InputBegan:Connect(function(input, processed)
	if not wantsGamepad() then return end
	if input.KeyCode ~= Enum.KeyCode.ButtonSelect then return end
	manualCursor = not manualCursor
end)

-- Poll rather than hook every panel: the panels are built by 20-odd separate scripts
-- with no shared open/close event to listen to.
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.2 then return end
	acc = 0
	if not wantsGamepad() then
		if cursorOn then setCursor(false) end
		if GuiService.SelectedObject then GuiService.SelectedObject = nil end
		return
	end
	setCursor(manualCursor or isPanelOpen())
	-- With the cursor doing the work, a selection highlight parked on the HUD would
	-- still steal ButtonA. Keep it clear unless the fallback path put it there.
	if not cursorOn and GuiService.SelectedObject and not manualCursor and not isPanelOpen() then
		GuiService.SelectedObject = nil
	end
end)

-- Going back to mouse or touch must clear both, or a console-shaped selection box or
-- pointer is left stranded on a PC player's screen.
UserInputService.LastInputTypeChanged:Connect(function(last)
	local isPad = last == Enum.UserInputType.Gamepad1
		or last == Enum.UserInputType.Gamepad2
		or last == Enum.UserInputType.Gamepad3
		or last == Enum.UserInputType.Gamepad4
	if isPad then
		tagAll()
	else
		manualCursor = false
		setCursor(false)
		if GuiService.SelectedObject then GuiService.SelectedObject = nil end
	end
end)

playerGui.DescendantAdded:Connect(function(d)
	if wantsGamepad() then tag(d) end
end)

----------------------------------------------------------------- 3. panels must fit
-- Every modal in this game is authored at a fixed pixel size against a desktop
-- window, and most of them never had any viewport scaling at all. Surveyed on
-- a 750x361 phone, drawn at their authored size:
--
--   QuestUI.GoalsPanel      560x468   75%W x 130%H   no UIScale anywhere
--   DailyUI.DailyPanel      600x420   80%W x 116%H   no UIScale anywhere
--   FusionUI.FusionFrame    520x466   69%W x 129%H   no UIScale anywhere
--   RebirthUI.RebirthPanel  440x368   59%W x 102%H   no UIScale anywhere
--   MainUI.IndexFrame       788x660  105%W x 183%H
--   TungOfferUI.OfferPanel  760x560  101%W x 155%H
--
-- i.e. taller than the screen. That is the "every pop up covers the whole
-- screen" report, and UIStyle's phone floor of 1.0 (which I raised for HUD
-- furniture) made the ones it touches render at FULL authored size instead of
-- the 0.8 they used to get -- so this got worse before it got better. Floors
-- are right for small furniture and wrong for big panels; panels have to FIT.
--
-- Fixed centrally rather than in ~12 scripts. The scale is capped at 1, so it
-- can only ever shrink a panel that does not fit -- on a 1080p monitor every
-- one of these already fits and the factor is exactly 1, leaving desktop
-- untouched. It composes correctly with a panel's existing UIScale because
-- nested UIScales multiply.
local FIT_TAG = "PlatformFitScale"

-- There WAS an existingChain() here that multiplied every UIScale from a frame
-- up to its ScreenGui. It was removed on 2026-09-17 because it encoded the
-- wrong model twice over:
--
--   * siblings do not multiply -- a frame applies only its FIRST UIScale, so
--     multiplying two of them over-counted (see the note in fitPanels), and
--   * this pass only ever visits DIRECT children of a ScreenGui, so the
--     ancestor walk had nothing to walk: the loop always terminated on the
--     first step.
--
-- The correction is now applied through the panel's own scale, which cannot
-- double-shrink by construction -- the point the old comment was making when
-- it recorded EggShopFrame coming out at 6% x 10% of a phone screen.

local function fitPanels()
	-- Platform.Viewport, NOT camera.ViewportSize (2026-08-26). THE BIG ONE.
	--
	-- This function retro-fits a UIScale onto essentially every offset-sized
	-- top-level frame in the game (every ScreenGui except GameHUD), so it governs
	-- the size of most of the UI -- and it was reading the raw camera. Under a
	-- device preview that is the real Studio window, so availW/availH were
	-- 1805x937 no matter which handset was being simulated, and every panel this
	-- owns kept its DESKTOP scale through every audit ever run. The audits were
	-- measuring desktop-sized furniture and reporting it clean.
	--
	-- Same rule the rail budgets and the tab metrics were moved to for exactly
	-- this reason: if you size or budget anything, read Platform.Viewport.
	-- Identical on a real device, where the two are the same number.
	local vp = Platform.Viewport
	if vp.X <= 1 or vp.Y <= 1 then return end
	local insets = Platform.Insets()
	-- Only the TOP inset is subtracted. The bottom one is the touch-control
	-- reserve, and taking that off too left modals capped at 50% of the height
	-- on a phone -- needlessly cramped, since a modal is dismissible and may
	-- sit over the thumbstick while it is open.
	local availW = math.max(vp.X - insets.Left - insets.Right, 1) * 0.94
	local availH = math.max(vp.Y - insets.Top, 1) * 0.92

	for _, gui in ipairs(playerGui:GetChildren()) do
		-- GameHUD sizes its own panel host through Platform.FitPanel
		if gui:IsA("ScreenGui") and gui.Name ~= "GameHUD" then
			for _, f in ipairs(gui:GetChildren()) do
				if f:IsA("GuiObject") then
					local w, h = f.Size.X, f.Size.Y
					-- offset-sized only: a scale-sized frame already adapts, and a
					-- full-bleed scrim or canvas must stay full-bleed
					-- WIDTH GATE 150 -> 80 (2026-08-24). The pair was picked to catch
					-- panels, and it let the narrow-but-tall furniture through
					-- ungoverned: ScooterUI's ride tile is 96x108, so 96 < 150 meant
					-- nothing here ever looked at it, and at fixed px it took 25% of
					-- the HEIGHT of a 932x430 handset. h.Offset > 100 still does the
					-- real filtering, so this only admits frames of that shape.
					-- HUDLAYOUT-MANAGED FRAMES ARE OFF LIMITS (2026-08-26).
					--
					-- This is a blanket fitter: it finds offset-sized frames by shape and
					-- retro-fits a UIScale onto them, without knowing what they are. The
					-- 150 -> 80 widening noted above was made precisely to catch ScooterUI's
					-- ride tile -- which is now a member of HudLayout's bottom-right stack,
					-- sized and placed by it. Two systems sizing one frame reproduces, in
					-- scale, exactly the write-ordering race HudLayout was built to remove
					-- from position; this file already documents losing that race once, when
					-- its TV-safe nudge was traced being overwritten 1766 -> 1715 -> 1725.
					--
					-- A managed frame declares itself with this attribute. Everything else
					-- is unchanged, so the genuinely ungoverned panels still get fitted.
					local managed = f:GetAttribute("HudLayoutManaged") == true
					-- WIDE-AND-SHORT STRIPS WERE NEVER ADMITTED (2026-09-11).
					--
					-- `h.Offset > 100` was doing the real filtering, and it silently
					-- excluded every banner, toast and ticker in the game -- the frames
					-- that are wide by design and only 40-80px tall. Nothing in this
					-- function had ever looked at one of them.
					--
					-- Measured on the 700x310 reference handset: Messages.Container is
					-- 825x55 FIXED px, i.e. 118% of the screen's width -- it hangs 62px
					-- off EACH side and lands 76% on top of HudToggleUI's HIDE UI pill.
					-- That single frame is the owner's "it's too big and it overlaps"
					-- report in one object: too big and overlapping are the same defect
					-- here, because a frame wider than the screen has nowhere to go.
					--
					-- The note further down says a width cap would crush strips that are
					-- wide BY DESIGN, and that is still true -- so this does NOT add one.
					-- It only lets the existing `fit` term (already capped at availW, i.e.
					-- 94% of the usable width) see these frames at all. A strip that
					-- already fits solves to scale 1 and does not move; only one that
					-- overflows is brought back onto the screen. Verified across the
					-- device list: DESKTOP CHANGES NOTHING, tablet admits two frames and
					-- shrinks neither.
					--
					-- The 16px floor keeps hairlines and 1px rules out; the <= 100 upper
					-- bound means this branch can only ever ADD frames the old gate
					-- rejected, never reinterpret one it already accepted.
					local panelish = w.Offset > 80 and h.Offset > 100
					local wideStrip = w.Offset > availW * 0.5 and h.Offset > 16 and h.Offset <= 100
					if not managed and w.Scale == 0 and h.Scale == 0 and (panelish or wideStrip) then
						-- A FRAME APPLIES ONLY ITS *FIRST* UIScale (2026-09-17). THE BIG ONE.
						--
						-- The note below says this "composes correctly with a panel's existing
						-- UIScale because nested UIScales multiply". Nested ones do -- a UIScale
						-- on a PARENT multiplies with one on its CHILD. SIBLINGS DO NOT. Probed
						-- live: a 100px frame carrying UIScale(2) and UIScale(3) renders at 200,
						-- and editing the second one changes nothing -- the engine applies the
						-- first child and silently ignores the rest.
						--
						-- This function parents its correction NEXT TO the panel's own scale, so
						-- on every panel that already had one the correction was inert. It was
						-- computed correctly, stored correctly, and drawn by nothing. Measured on
						-- a 390x844 handset before this fix:
						--
						--   EggShopUI.EggShopFrame  1900x887 =  487% of the width  (fit 0.193 dead)
						--   TungOfferUI.OfferPanel   760x560 =  194%              (fit 0.48 dead)
						--   EquipPadUI.ConfirmPanel  560x300 =  143%              (fit 0.65 dead)
						--   SeasonUI.SeasonPanel     512x382 =  131%              (fit 0.72 dead)
						--
						-- That is the whole of "pop ups cover the screen / run off the edge" on
						-- mobile, and it audits CLEAN in any check that reads the UIScale's value
						-- rather than the frame's rendered size.
						--
						-- So: find the panel's own scale first. If it has one, that is the only
						-- scale the engine will honour, and the correction has to go THROUGH it
						-- (below) instead of beside it.
						local own = nil
						for _, u in ipairs(f:GetChildren()) do
							if u:IsA("UIScale") and u.Name ~= FIT_TAG then own = u break end
						end
						-- Two behaviours, split on whether the panel already carries a
						-- UIScale of its own.
						--
						-- NO scale of its own -- nothing was managing it, so this owns
						-- the sizing outright: fit it, and on a touch/console screen
						-- let it grow into the space (capped, so a big screen does not
						-- get a bloated modal). These are the genuinely broken ones.
						--
						-- HAS its own scale -- only rescue an actual overflow, never
						-- grow. Compensating for their chain looked right until
						-- MerchantDialog (Gianluca's dialogue) turned up: it animates
						-- its pop-in ON a UIScale, so the chain read mid-tween and the
						-- correction solved against a number that was about to change,
						-- landing on 1.296 -- which would have overflowed the width
						-- once the tween finished. Not fighting a script that is
						-- already sizing itself is both safer and more honest.
						if own then
							-- APPLIED THROUGH THE PANEL'S OWN SCALE, not beside it (see above).
							--
							-- Still "only rescue an actual overflow, never grow": k is capped at 1,
							-- so a panel that already fits is written back at exactly the value it
							-- asked for and desktop does not move.
							--
							-- The panel's script keeps ownership of its own sizing: whenever IT moves
							-- the value (a device change, MerchantDialog's pop-in tween), that value
							-- is adopted as the new base, so the size is given back as soon as there
							-- is room for it. Comparing against what we last wrote is what keeps the
							-- two writers from ratcheting each other down -- the failure this file
							-- already documents for applyTvSafe's shift bookkeeping.
							local wrote = f:GetAttribute("PlatformScaleWrote")
							local base = f:GetAttribute("PlatformScaleBase")
							if typeof(base) ~= "number" or typeof(wrote) ~= "number"
								or math.abs(own.Scale - wrote) > 1e-3 then
								base = own.Scale
								f:SetAttribute("PlatformScaleBase", base)
							end
							base = math.max(base, 0.01)
							-- DESKTOP MUST NOT MOVE, so the bound is not the same on both.
							--
							-- availW/availH carry a 6%/8% breathing margin. That is right for a
							-- modal this pass sizes from scratch, and wrong for one whose own
							-- script already chose a size: measured on a 1920x1080 window, holding
							-- these panels to the margin shrank five SHIPPED desktop layouts by
							-- 7-13% the moment the correction started working (RebirthPanel 97% ->
							-- 91% of usable height, TradeUI's canvas 1876 -> 1781 wide, EggShop and
							-- MerchantShop 1309 -> 1262). None of those is broken on a monitor --
							-- they fit the screen -- and shrinking them is a regression, not a fix.
							--
							-- So on a pointer device correct only what genuinely LEAVES the screen,
							-- and keep the margin for touch, which is where the overflow lives.
							local boundW = Platform.IsTouch and availW or math.max(vp.X, 1)
							local boundH = Platform.IsTouch and availH or math.max(vp.Y, 1)
							local k = math.min(1, boundW / (w.Offset * base), boundH / (h.Offset * base))
							local want = base * k
							if math.abs(own.Scale - want) > 1e-4 then own.Scale = want end
							f:SetAttribute("PlatformScaleWrote", want)
							-- Leave no inert tag behind to mislead the next reader.
							local dead = f:FindFirstChild(FIT_TAG)
							if dead then dead:Destroy() end
						else
							local s = f:FindFirstChild(FIT_TAG)
							if not s then
								s = Instance.new("UIScale")
								s.Name = FIT_TAG
								s.Parent = f
							end
							local fit = math.min(availW / w.Offset, availH / h.Offset)
							-- GROW ONLY WHAT IS ACTUALLY A MODAL (2026-08-24).
							-- The 1.35 allowance was written for the panels listed at
							-- the top of this section -- things that fill the screen
							-- and are then dismissed -- but the only test that reaches
							-- it is a size gate, which plenty of HUD FURNITURE passes
							-- too. Measured under a forced Phone class: MainUI.TabBar,
							-- MainUI.ResultFrame, MainUI.TutorialCard, IceFishingUI.Cast,
							-- EquipPadUI.ConfirmPanel and PerfectPopUI.Root were all
							-- being handed the full 1.35 -- a third larger than their own
							-- script asked for -- purely for being over the gate. None of
							-- them is a modal and nothing should be growing them.
							--
							-- A modal is recognised by FOOTPRINT: at its authored size
							-- it already wants a serious share of the available box.
							-- A STRIP IS FURNITURE, NEVER A MODAL (2026-09-11). This test is
							-- an `or`, so a frame that is merely WIDE ENOUGH trips it -- and a
							-- 600x66 banner is wide. Left alone it would hand every strip the
							-- 1.35 modal grow ceiling AND exempt it from the height share cap
							-- below, so PityThrowUI.Banner would have come out BIGGER on a
							-- phone than on a monitor -- the exact failure the grow ceiling was
							-- narrowed to stop in 2026-08-24.
							--
							-- Frames that passed the OLD gate are unaffected by construction:
							-- wideStrip is false for every one of them, so this expression
							-- reads exactly as it did before.
							local modalish = not wideStrip
								and ((w.Offset >= availW * 0.45)
									or (h.Offset >= availH * 0.45))
							local ceiling = (Platform.IsDesktop or not modalish) and 1 or 1.35

							-- ...AND FURNITURE ANSWERS TO A SHARE OF THE SCREEN, not
							-- only to "does it overflow" (2026-08-24). Overflow is the
							-- right question for a modal and the wrong one for chrome:
							-- the tab bar is 318x104 FIXED px carrying no UIScale of any
							-- kind, so it holds its desktop size all the way down and
							-- simply claims more of the screen as the screen shrinks --
							-- 17% x 10% of a 1920 window, 34% x 24% of a 932x430 phone.
							-- It never overflows, so nothing here ever touched it. That
							-- is the owner's "UI doesn't adjust to the screen" report in
							-- its purest form: these frames do not adjust, at all.
							--
							-- HEIGHT ONLY. Height is the scarce axis on a landscape
							-- handset, and a width cap would crush the wide-and-short
							-- strips that are wide BY DESIGN (Messages.Container is
							-- 826x54 -- 89% of a phone's width, and correct at that).
							-- Desktop and console are untouched: no touch, no cap.
							if Platform.IsTouch and not modalish then
								local share = Platform.IsPhone and 0.16 or 0.20
								ceiling = math.min(ceiling, vp.Y * share / h.Offset)
							end
							s.Scale = math.min(fit, ceiling)
						end
					end
				end
			end
		end
	end
end

----------------------------------------------------------------- 4. TV overscan
-- GameHUDClient insets its own chrome layer, but the legacy HUDs (LuckHUD,
-- WheelUI, SideRailUI, the MainUI tab bar...) anchor straight to the screen
-- edge, and on a console a TV simply does not draw the outer few percent.
-- Measured on a simulated Xbox One: 8 visible buttons sat inside the 3.5%
-- title-safe margin.
--
-- Rather than edit every legacy script, edge-anchored TOP-LEVEL frames get
-- nudged inward. The shift is recorded per-frame and undone before each
-- re-apply, so this is idempotent and reverses cleanly when the device stops
-- being a console.
local SAFE_TAG = "TVSafeShift"
-- Where we LEFT the frame after shifting it. The shift alone is not enough to
-- undo safely -- see the staleness check in applyTvSafe.
local SAFE_AT = "TVSafeShiftAt"
local TV_SAFE = 0.035

local function applyTvSafe()
	-- THE RAW CAMERA, DELIBERATELY -- and this is the one place in this file that
	-- must not read Platform.Viewport (2026-08-26).
	--
	-- fitPanels above computes a SIZE, and sizes come from Platform, so a preview
	-- fakes them honestly. This function compares a frame's RENDERED
	-- AbsolutePosition against the screen edges and pushes whatever hangs over. A
	-- preview cannot fake where a frame actually renders -- it is still in the real
	-- Studio window -- so pointing this at a simulated 700px viewport made every
	-- right-hand widget look like it hung 300px off the edge, and this obligingly
	-- shoved them all inboard. Traced: it moved QuestBarUI.Root from {1, -18} to
	-- {1, 308}, i.e. off the screen it was trying to rescue it from.
	--
	-- Same rule as HudAudit's position checks: sizes are fakeable under a preview,
	-- positions are not.
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize
	local mx = Platform.IsConsole and vp.X * TV_SAFE or 0
	local my = Platform.IsConsole and vp.Y * TV_SAFE or 0
	for _, gui in ipairs(playerGui:GetChildren()) do
		-- GameHUD already lays itself out inside Platform.Insets()
		if gui:IsA("ScreenGui") and gui.Name ~= "GameHUD" then
			for _, f in ipairs(gui:GetChildren()) do
				-- Opt-out for a frame whose own script rewrites Position on every
				-- layout pass. Nudging one of those is worse than leaving it alone:
				-- the script overwrites the shift, then the next pass here subtracts
				-- a shift that is no longer applied, and the frame walks a little
				-- further off screen each time. ClientMain's tab bar is the one that
				-- does this; it applies the same inset itself instead.
				if f:IsA("GuiObject") and not f:GetAttribute("TVSafeSelfManaged") then
					-- ONLY UNDO A SHIFT THE FRAME IS STILL WEARING (2026-08-21).
					-- Three legacy HUDs -- HudToggleUI's HIDE UI button, LuckHUD's chip
					-- and the quest tracker -- TWEEN their own Position after this pass
					-- has run. Traced live: this pass moved UiToggle 1766 -> 1715, then
					-- four tween frames walked it to 1725 while the -51.2 shift stayed
					-- recorded against it. Subtracting that stale shift from the tween's
					-- landing spot is exactly the "walks a little further off screen each
					-- time" drift the note above warns about, and the old bookkeeping had
					-- no way to notice. If the frame is not where we left it, the shift is
					-- not there to undo -- drop it and re-solve from where the frame is.
					local prev = f:GetAttribute(SAFE_TAG)
					local prevAt = f:GetAttribute(SAFE_AT)
					if typeof(prev) == "Vector2" and typeof(prevAt) == "Vector2"
						and math.abs(f.Position.X.Offset - prevAt.X) < 0.5
						and math.abs(f.Position.Y.Offset - prevAt.Y) < 0.5
					then
						f.Position -= UDim2.fromOffset(prev.X, prev.Y)
					end
					-- EDGE IS MEASURED, NOT INFERRED FROM Position.Scale (2026-08-21).
					-- The old test read the SCALE term to decide which edge a frame
					-- belonged to, which is only true of scale-anchored frames. A frame
					-- parked at the right edge by pure OFFSET -- HudToggleUI's HIDE UI
					-- button is Position (0.00, 1725) on a 1920 screen -- reads as
					-- Scale 0 and was therefore classed as a LEFT-edge frame and shoved
					-- +67px FURTHER INTO the overscan: the pass meant to rescue it was
					-- the thing pushing it off the TV. Measured on the Console layout,
					-- UiToggle ended 51px outside the title-safe box, its shadow 10px.
					--
					-- So resolve the frame's OWN box in this ScreenGui's pixel space and
					-- push whichever edge actually sits outside, by exactly the overhang.
					-- AbsoluteSize is safe to read here even though we just rewrote
					-- Position: the undo above moves the frame, it does not resize it.
					local dx, dy = 0, 0
					if mx > 0 or my > 0 then
						local host = gui.AbsoluteSize
						local sz = f.AbsoluteSize
						local left = f.Position.X.Scale * host.X + f.Position.X.Offset - f.AnchorPoint.X * sz.X
						local top = f.Position.Y.Scale * host.Y + f.Position.Y.Offset - f.AnchorPoint.Y * sz.Y
						-- A frame parked ENTIRELY off screen is a folded surface, not a
						-- clipped one (HudToggleClient slides things away by design), and
						-- dragging it back would un-hide it. A frame as big as the screen
						-- is a full-bleed canvas with nothing to rescue.
						local parked = (left + sz.X <= 0) or (left >= host.X)
							or (top + sz.Y <= 0) or (top >= host.Y)
						if not parked then
							if sz.X > 0 and sz.X < host.X then
								if left < mx then dx = mx - left
								elseif left + sz.X > host.X - mx then dx = (host.X - mx) - (left + sz.X) end
							end
							if sz.Y > 0 and sz.Y < host.Y then
								if top < my then dy = my - top
								elseif top + sz.Y > host.Y - my then dy = (host.Y - my) - (top + sz.Y) end
							end
						end
					end
					if dx ~= 0 or dy ~= 0 then
						f.Position += UDim2.fromOffset(dx, dy)
						f:SetAttribute(SAFE_TAG, Vector2.new(dx, dy))
						f:SetAttribute(SAFE_AT, Vector2.new(f.Position.X.Offset, f.Position.Y.Offset))
					else
						f:SetAttribute(SAFE_TAG, nil)
						f:SetAttribute(SAFE_AT, nil)
					end
				end
			end
		end
	end
end

-- Panels are created lazily the first time a player opens them, so a one-shot
-- pass at join would miss most of them.
playerGui.DescendantAdded:Connect(function(d)
	if d:IsA("GuiObject") then
		task.defer(fitPanels)
	end
end)

Platform.Watch(function(class)
	if wantsGamepad() then tagAll() end
	fitPanels()
	applyTvSafe()
	-- AND AGAIN once the legacy HUDs' own Position tweens have landed. Several of
	-- them animate into place AFTER this fires and settle back outside the
	-- title-safe box, so a single pass can only ever be right for the frames that
	-- do not move themselves. applyTvSafe re-solves from the live rect and the
	-- staleness check above makes it safe to repeat, so this costs nothing.
	-- ...and fitPanels for the same reason, now that it corrects THROUGH a panel's
	-- own UIScale. Every panel re-computes that scale on its own Platform.Watch,
	-- and watcher order is registration order -- so a panel that registered after
	-- this file writes its desktop scale back AFTER the correction was applied,
	-- and keeps it until something else pokes the layout. Re-running once the
	-- other watchers have landed is the same defer-and-settle idiom the HUD uses
	-- when one surface measures another.
	task.delay(0.4, fitPanels)
	task.delay(0.4, applyTvSafe)
	-- Published for anything that wants to branch on device without requiring
	-- the module (server-side analytics, other collaborators' scripts).
	player:SetAttribute("PlatformClass", class)
	player:SetAttribute("PlatformTouch", Platform.IsTouch)
	player:SetAttribute("PlatformGamepad", Platform.IsGamepad)
end)

print(("PlatformClient online (%s, touch=%s, gamepad=%s, scale fit=%.2f chrome=%.2f)")
	:format(Platform.Class, tostring(Platform.IsTouch), tostring(Platform.IsGamepad),
		Platform.Fit(), Platform.Chrome()))
