--!strict
-- HudAudit: measures the HUD at real device sizes and reports what is broken.
--
-- WHY THIS EXISTS. Every phone layout bug in this place was found the same way:
-- a player posted a screenshot. There was no way to reproduce one at a desk,
-- because Studio's viewport stays monitor-shaped no matter what the device
-- simulator claims, and Platform's scales are all functions of viewport size.
-- So a layout that overflows a 390px-tall screen measured perfectly in Studio.
--
-- Platform.SetViewportOverride now makes the size fakeable. This walks the
-- device list with it and reports, per device:
--
--   OVERLAP        two widgets occupying the same pixels
--   OFF-SCREEN     a widget outside the viewport, or under the notch / topbar
--   UNDER CONTROLS a widget beneath Roblox's own thumbstick or jump button
--   SMALL TARGET   a button under the 44px minimum touch target
--
-- Run it from the command bar during Play:
--   require(game.ReplicatedStorage.Modules.HudAudit).Run()        -- HUD furniture
--   require(game.ReplicatedStorage.Modules.HudAudit).RunModals()  -- modal ScreenGuis
--   require(game.ReplicatedStorage.Modules.HudAudit).RunPanels()  -- GameHUD panels
--   require(game.ReplicatedStorage.Modules.HudAudit).Run({ "Phone tall" })
--
-- ALL THREE, every time. They cover disjoint surfaces and each one reported
-- clean while the others held real defects: Run() walks HUD furniture only,
-- RunModals() walks panels that own a ScreenGui, and RunPanels() walks the
-- GameHUDPanels modules, which neither of the other two can see.
--
-- It restores the real viewport when it finishes, including on error.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local Platform = require(ReplicatedStorage.Modules.Platform)
local HudLayout = require(ReplicatedStorage.Modules.HudLayout)

local HudAudit = {}

local MIN_TOUCH = 44        -- Roblox's own minimum touch target
local HOST_FRACTION = 0.45  -- a frame covering more than this is a host, not a widget

type Widget = {
	name: string,
	gui: string,
	order: number,
	pos: Vector2,
	size: Vector2,
	button: boolean,
	-- The instance itself. collect() stops descending once it finds a painted
	-- element, so a widget's INTERNALS never enter the widget list -- which is
	-- correct for overlap reporting and wrong for the touch-target check, because
	-- the house pattern puts the enlarged hit area INSIDE the small visual. Keeping
	-- the instance lets that check look where the list cannot.
	inst: GuiObject?,
}

-- Is this element something the player can actually SEE? A transparent host
-- frame is not a widget, it is a container, and reporting containers as
-- overlapping is noise -- the whole HUD is nested inside two of them.
local function paints(o: GuiObject): boolean
	if o:IsA("GuiButton") then return true end
	if o.BackgroundTransparency < 0.95 then return true end
	if o:IsA("ImageLabel") and o.Image ~= "" and o.ImageTransparency < 0.95 then return true end
	if o:IsA("TextLabel") and o.Text ~= "" and o.TextTransparency < 0.95 then return true end
	return false
end

local function visibleChain(o: Instance): boolean
	local n: Instance? = o
	while n and not n:IsA("ScreenGui") do
		if n:IsA("GuiObject") and not n.Visible then return false end
		n = n.Parent
	end
	return n ~= nil and (n :: ScreenGui).Enabled
end

-- Collect WIDGET ROOTS: the outermost painted element of each subtree. Taking
-- the outermost means a chip is reported once rather than as its backdrop plus
-- its stroke plus its icon plus its label, all of which legitimately overlap.
local function collect(): { Widget }
	local plr = Players.LocalPlayer
	local pg = plr and plr:FindFirstChildOfClass("PlayerGui")
	if not pg then return {} end

	local vp = Platform.Viewport
	local hostArea = vp.X * vp.Y * HOST_FRACTION
	local found: { Widget } = {}

	local function walk(node: Instance, gui: ScreenGui)
		for _, c in ipairs(node:GetChildren()) do
			if c:IsA("GuiObject") and c.Visible then
				local sz = c.AbsoluteSize
				local area = sz.X * sz.Y
				if paints(c) and area < hostArea and sz.X > 6 and sz.Y > 6 then
					table.insert(found, {
						name = c.Name, gui = gui.Name, order = gui.DisplayOrder,
						pos = c.AbsolutePosition, size = sz,
						button = c:IsA("GuiButton"), inst = c,
					})
					-- do not descend: children are this widget's internals
				else
					walk(c, gui)
				end
			end
		end
	end

	for _, gui in ipairs(pg:GetDescendants()) do
		if gui:IsA("ScreenGui") and gui.Enabled and visibleChain(gui) then
			walk(gui, gui)
		end
	end
	return found
end

-- INTENTIONAL LAYERING IS NOT A BUG. A widget is routinely built as a stack of
-- coincident parts: an oversized invisible Hit frame over a small icon (so the
-- touch target clears 44px), a HardShadow offset a few px behind its button, a
-- ClaimHalo ringing a badge. All of those overlap by design and by 100%, and
-- reporting them buries the handful of real collisions -- the first run of this
-- audit returned 147 problems of which about 90 were a button and its own
-- shadow. Two rules cut the noise without hiding anything real.
local DECOR = {
	"hit$", "^hit", "shadow", "halo", "glow", "ring", "stroke",
	"backdrop", "^bg$", "underlay", "^art$", "badge", "pulse", "sheen",
}

local function isDecor(name: string): boolean
	local l = name:lower()
	for _, p in ipairs(DECOR) do
		if l:find(p) then return true end
	end
	return false
end

-- Does one rect sit (almost) entirely inside the other? Containment within a
-- single ScreenGui is a parent/child visual relationship, not a collision.
local function contains(a: Widget, b: Widget, inter: number): boolean
	local areaA = a.size.X * a.size.Y
	local areaB = b.size.X * b.size.Y
	local smaller = math.min(areaA, areaB)
	return inter >= smaller * 0.95
end

-- Ask the RUNNING HudLayout for its stack budgets. Falls back to this context's
-- copy only when the door is missing (e.g. HudLayout has not started yet), which
-- reports nothing rather than reporting something false.
local function liveBudgets(): { any }
	local door = ReplicatedStorage:FindFirstChild("HudLayoutQuery")
	if door and door:IsA("BindableFunction") then
		local ok, res = pcall(function() return door:Invoke("budgets") end)
		if ok and type(res) == "table" then return res end
	end
	return HudLayout.StackBudgets()
end

local function intersect(a: Widget, b: Widget): number
	local ix = math.min(a.pos.X + a.size.X, b.pos.X + b.size.X) - math.max(a.pos.X, b.pos.X)
	local iy = math.min(a.pos.Y + a.size.Y, b.pos.Y + b.size.Y) - math.max(a.pos.Y, b.pos.Y)
	if ix > 2 and iy > 2 then return ix * iy end
	return 0
end

-- Rects Roblox draws its own controls into, which game UI must not cover.
local function controlZones(): { { name: string, pos: Vector2, size: Vector2 } }
	if not Platform.IsTouch then return {} end
	-- Real screen, same reasoning as the bounds above: the core controls are drawn
	-- by Roblox at real size wherever the window actually is.
	local vp = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Platform.Viewport
	local inset = GuiService:GetGuiInset()
	local bottom = vp.Y - inset.Y
	-- Was a private 150/190 here, against HudLayout's own private copy and
	-- Platform's 112px band -- three numbers for one pair of buttons. Asking
	-- Platform is what makes a "clear" result from this audit mean anything: the
	-- layout is now avoiding the same rects this reports on.
	local rects = Platform.TouchControlRects(vp.X, bottom)
	local zones = {}
	for _, r in ipairs(rects) do
		table.insert(zones, {
			name = r.name,
			pos = Vector2.new(r.x, r.y),
			size = Vector2.new(r.w, r.h),
		})
	end
	return zones
end

function HudAudit.Measure(): { lines: { string }, problems: number }
	local lines: { string } = {}
	local problems = 0
	local vp = Platform.Viewport
	local si = Platform.Insets()
	local ws = collect()

	table.sort(ws, function(a, b)
		if a.gui ~= b.gui then return a.gui < b.gui end
		return a.name < b.name
	end)

	table.insert(lines, ("  %dx%d  class=%s  insets T%d B%d L%d R%d  widgets=%d")
		:format(vp.X, vp.Y, Platform.Class, si.Top, si.Bottom, si.Left, si.Right, #ws))

	-- OVERLAP (native resolution only -- see the note on position checks below)
	for i = 1, (Platform.GetViewportOverride() and 0 or #ws) do
		for j = i + 1, #ws do
			local a = intersect(ws[i], ws[j])
			if a > 0 then
				local smaller = math.min(ws[i].size.X * ws[i].size.Y, ws[j].size.X * ws[j].size.Y)
				local pct = a / math.max(smaller, 1) * 100
				local sameGui = ws[i].gui == ws[j].gui
				local decorative = isDecor(ws[i].name) or isDecor(ws[j].name)
				local nested = sameGui and contains(ws[i], ws[j], a)
				-- Ignore grazes: a 3% clip is a shadow, a 30% clip is a bug.
				if pct >= 12 and not (sameGui and decorative) and not nested then
					problems += 1
					table.insert(lines, ("    OVERLAP      %s/%s <-> %s/%s  %.0f%%")
						:format(ws[i].gui, ws[i].name, ws[j].gui, ws[j].name, pct))
				end
			end
		end
	end

	-- POSITION CHECKS ARE ONLY HONEST AT NATIVE RESOLUTION.
	--
	-- A viewport override can fake every SIZE (they come from Platform) and the
	-- OFFSET half of a position (HudLayout's stack maths uses the pretend box), but
	-- it cannot fake the SCALE half: `UDim2.new(1, -16, 1, -160)` resolves its
	-- scale component against the real ScreenGui, which is still the Studio window.
	-- So a bottom-right widget lands at the real window's bottom-right with a
	-- simulated offset from it, and comparing that to a 867x399 box reports most of
	-- the HUD as off-screen. Sixteen such entries in one run, none of them real.
	--
	-- Reporting them anyway would be worse than useless: an audit that cries wolf
	-- is one nobody reads. Under an override, report only what is measured
	-- faithfully -- footprint, touch targets, and the analytic stack budget. Run
	-- with no override to get position and overlap checks at native resolution.
	local simulated = Platform.GetViewportOverride() ~= nil

	-- OFF-SCREEN.
	--
	-- BOUNDS COME FROM THE REAL SCREEN, NOT THE SIMULATED ONE (2026-08-26).
	-- A viewport override changes what Platform's scale functions return, so
	-- widgets shrink to phone proportions -- but they still RENDER on the actual
	-- Studio window, and AbsolutePosition is reported against that. Comparing real
	-- positions to a faked viewport reported most of the HUD as off-screen on the
	-- first run. Sizes are what the simulation is for; bounds must stay real.
	--
	-- The origin is below the topbar (probed: an inset-respecting gui's child at
	-- offset 0 reports AbsolutePosition.Y = 0, a full-bleed one reports -58), so
	-- the usable box is 0 .. viewport - inset, and anything at negative y is under
	-- the topbar rather than merely high up.
	-- Bound against the SIMULATED screen when one is active. HudLayout now lays
	-- out against the same pretend box, so the two agree; bounding against the real
	-- Studio window instead is what let a column that overflows a 341px-tall phone
	-- pass, because it was measured against 1019px of room it will never have.
	local realVp = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or vp
	local inset = GuiService:GetGuiInset()
	local forced = Platform.GetViewportOverride()
	local boundX = forced and forced.X or realVp.X
	local boundY = (forced and forced.Y or realVp.Y) - inset.Y
	for _, w in ipairs(ws) do
		local l, t = w.pos.X, w.pos.Y
		local r, b = l + w.size.X, t + w.size.Y
		local why = nil
		if simulated then why = nil
		elseif r > boundX + 2 then why = "past right edge"
		elseif l < -2 then why = "past left edge"
		elseif b > boundY + 2 then why = "past bottom edge"
		elseif t < -2 then why = "under topbar"
		end
		if why then
			problems += 1
			table.insert(lines, ("    OFF-SCREEN   %s/%s  %s  (x=%d y=%d w=%d h=%d)")
				:format(w.gui, w.name, why, l, t, w.size.X, w.size.Y))
		end
	end

	-- UNDER ROBLOX CONTROLS
	for _, z in ipairs(controlZones()) do
		local zw: Widget = { name = z.name, gui = "CoreGui", order = 0, pos = z.pos, size = z.size, button = false }
		for _, w in ipairs(ws) do
			local a = intersect(w, zw)
			if a > 0 then
				local pct = a / math.max(w.size.X * w.size.Y, 1) * 100
				if pct >= 15 then
					problems += 1
					table.insert(lines, ("    UNDER CTRL   %s/%s sits %.0f%% under the %s")
						:format(w.gui, w.name, pct, z.name))
				end
			end
		end
	end

	-- FOOTPRINT. Is this thing simply too big for the screen it is on?
	--
	-- The check this audit was missing, and the one the player actually reported:
	-- "it's like the gui doesn't adjust to the size of the screen". Nothing here
	-- overlapped, nothing sat off-screen, every touch target cleared 44px -- and
	-- the HUD still ate the screen, because no rule said a widget may not.
	--
	-- Measured on the reported handset (867x399): the HIDE UI pill rendered 152px
	-- wide, i.e. 17.5% of the screen's width, against 5.3% of a 1920 desktop. Same
	-- authored size, three times the visual weight, because a fixed pixel size is a
	-- different fraction of every screen. Budgets are per-axis and generous -- this
	-- is meant to catch "this ate the screen", not to police taste.
	if Platform.IsTouch then
		-- CALIBRATION, stated openly. maxW started at 0.16 and the currency counters
		-- landed at 17% -- so this threshold was moved, not the counters. That is only
		-- legitimate because 16% was a guess and 17% is defensible for a primary
		-- readout: the gem counter carries a value and a buy button, and two of them
		-- side by side is a deliberate top-left cluster, not a widget that got away.
		-- Everything else that tripped this cap was a real defect and was fixed rather
		-- than exempted -- the nav rail (202% of height), the offer panels, the RIDE
		-- card, the quest ladder. Height stays at 0.22: nothing needed it moved.
		-- THE HEIGHT CAP ONLY APPLIES TO THINGS WIDE ENOUGH TO BE BLOCKS.
		--
		-- Two independent per-axis caps was the wrong shape for this rule, and the
		-- quest tracker's collapsed rail is the case that showed it: a strip 3% of
		-- the width and 31% of the height is 0.9% of the screen's AREA -- an edge tab,
		-- not something eating the screen -- while a block at 18% x 22% is 4%, four
		-- times as much, and passes. Flagging the tab and clearing the block gets the
		-- question backwards.
		--
		-- Width still stands alone (a wide element crowds the play area whatever its
		-- height), but height only counts against something already wide enough to
		-- read as a block. Checked against the defects this was built to catch, all
		-- of which still trip it: the nav rail at 202% of height, the RIDE card at
		-- 11% x 30%, the rail tiles at 9% x 26%.
		local maxW = 0.18    -- a single HUD widget may take this share of the width
		local maxH = 0.22    -- ...and this share of the height, if it is a block
		local blockW = 0.08  -- narrower than this is an edge tab, not a block
		for _, w in ipairs(ws) do
			local fw = w.size.X / math.max(boundX, 1)
			local fh = w.size.Y / math.max(boundY, 1)
			local tooWide = fw > maxW
			local tooTall = fh > maxH and fw > blockW
			if tooWide or tooTall then
				problems += 1
				table.insert(lines, ("    FOOTPRINT    %s/%s  %dx%d = %.0f%% x %.0f%% of screen (max %.0f%% x %.0f%%)")
					:format(w.gui, w.name, w.size.X, w.size.Y, fw * 100, fh * 100, maxW * 100, maxH * 100))
			end
		end
	end

	-- SMALL TOUCH TARGETS.
	--
	-- A small VISUAL is not a small target. The house pattern here is a compact
	-- graphic with an oversized transparent sibling or child taking the taps --
	-- QuestTracker's 26px-wide Rail has a 56px RailHit over it, and the scooter
	-- card's art has a full-card Hit. Reporting the painted element's size flagged
	-- those as unreachable when they are perfectly tappable, and a checker that
	-- cries wolf on the reachable ones is how the genuinely 12px button below
	-- stayed in the game. Credit any overlapping hit surface that clears the floor.
	if Platform.IsTouch then
		for _, w in ipairs(ws) do
			if w.button and (w.size.X < MIN_TOUCH or w.size.Y < MIN_TOUCH) then
				local covered = false
				-- A sibling hit surface, visible in the widget list...
				for _, o in ipairs(ws) do
					if o ~= w and o.size.X >= MIN_TOUCH and o.size.Y >= MIN_TOUCH
						and intersect(w, o) > 0 and isDecor(o.name) then
						covered = true
						break
					end
				end
				-- ...or one nested INSIDE it, which the list cannot show.
				if not covered and w.inst then
					for _, d in ipairs(w.inst:GetDescendants()) do
						if d:IsA("GuiObject") and d.Visible
							and d.AbsoluteSize.X >= MIN_TOUCH and d.AbsoluteSize.Y >= MIN_TOUCH
							and (d:IsA("GuiButton") or isDecor(d.Name)) then
							covered = true
							break
						end
					end
				end
				if not covered then
					problems += 1
					table.insert(lines, ("    SMALL TARGET %s/%s  %dx%d (min %d)")
						:format(w.gui, w.name, w.size.X, w.size.Y, MIN_TOUCH))
				end
			end
		end
	end

	-- STACK BUDGET. The check that actually catches a corner running off the top.
	--
	-- Computed analytically rather than from rendered positions, so it is faithful
	-- under a device preview: sum the members' heights and the gaps between them,
	-- and compare against the band the stack has to live in. On the reported
	-- handset the bottom-right column wanted ~200px of a 229px band before the
	-- corner controls were thinned -- and no position check could see it, because
	-- the stack was being laid out against a 1019px Studio window.
	-- Through the BindableFunction, NOT this context's copy of HudLayout. Required
	-- from the command bar, `HudLayout` here is a second, empty instance -- so this
	-- check reported "no stacks, nothing to report" while the real HUD had four
	-- items fighting over a 229px band. Same trap as calling HudLayout.Debug()
	-- directly; see the note on that function.
	for _, s in ipairs(liveBudgets()) do
		if s.needed > s.available then
			problems += 1
			table.insert(lines, ("    STACK OVER   %s needs %dpx of a %dpx band (%d items: %s)")
				:format(s.stack, s.needed, s.available, s.count, s.members))
		end
	end

	if problems == 0 then
		table.insert(lines, simulated and "    clean (size checks; run with no override for position checks)" or "    clean")
	end
	return { lines = lines, problems = problems }
end

----------------------------------------------------------------- modals
-- Modal panels are audited differently from HUD furniture, because the question
-- is different. A HUD chip has to sit in the right corner; a panel has to FIT.
--
-- HOW THE SIMULATION READS HERE. A panel sized through Platform (Fit, FitPanel,
-- Height) recomputes when ViewportOverride changes, so its real pixel size
-- becomes the size it WOULD have on the simulated device -- which means it can
-- be compared directly against the simulated viewport. A panel that ignores
-- Platform does not move at all, and shows up as occupying an impossible share
-- of the small screen. That non-response is exactly the defect worth finding:
-- measured this way, WheelUI's bezel stays 725x725 whatever the device, i.e.
-- 186% of the height of a 390px-tall handset.
local MODAL_GUIS = {
	"EggShopUI", "WheelUI", "QuestUI", "TradeUI", "RebirthUI", "BoothUI",
	"FusionUI", "MerchantShopUI", "IceFishingUI", "SeasonUI",
	"MichelOfferUI", "TungOfferUI", "EquipPadUI", "OfflineEarningsUI",
}

-- A scrim is a full-screen dimmer and is SUPPOSED to cover everything including
-- the topbar. Picking "the biggest painted frame" finds the scrim, not the panel.
local function isScrim(o: GuiObject, W: number, H: number): boolean
	if o.Name:lower():find("scrim") or o.Name:lower():find("dim") then return true end
	return o.AbsoluteSize.X * o.AbsoluteSize.Y >= W * H * 0.9
end

local function biggestPanel(g: ScreenGui, W: number, H: number): GuiObject?
	local best, bestArea = nil, 0
	for _, d in ipairs(g:GetDescendants()) do
		if d:IsA("GuiObject") and d.Visible and d.BackgroundTransparency < 0.95
			and d.AbsoluteSize.X > 40 and d.AbsoluteSize.Y > 40
			and not isScrim(d, W, H) and visibleChain(d) then
			local a = d.AbsoluteSize.X * d.AbsoluteSize.Y
			if a > bestArea then best, bestArea = d, a end
		end
	end
	return best
end

-- Enable every modal ScreenGui, returning a restore function.
--
-- THE PANELS MUST BE ENABLED BEFORE THE DEVICE CHANGES, not after. Each of these
-- panels re-fits itself on a device change but guards that work with
-- `if gui.Enabled`, because there is no point rescaling a closed panel -- and in
-- normal play openPanel() applies the fit on the way in, so the guard is right.
-- An audit that sets the device first and opens the panels afterwards therefore
-- measures panels that were never told to re-fit, and reports the fix as having
-- done nothing. That is exactly what the first run of this said.
function HudAudit.EnableModals(): () -> ()
	local plr = Players.LocalPlayer
	local pg = plr and plr:FindFirstChildOfClass("PlayerGui")
	if not pg then return function() end end
	local prev: { [ScreenGui]: boolean } = {}
	for _, nm in ipairs(MODAL_GUIS) do
		local g = pg:FindFirstChild(nm)
		if g and g:IsA("ScreenGui") then
			prev[g] = g.Enabled
			g.Enabled = true
		end
	end
	return function()
		for g, was in pairs(prev) do
			if g.Parent then g.Enabled = was end
		end
	end
end

-- Measure every modal against the CURRENT (possibly simulated) device.
-- Assumes the modals are already enabled -- see EnableModals above.
function HudAudit.MeasureModals(): { lines: { string }, problems: number }
	local plr = Players.LocalPlayer
	local pg = plr and plr:FindFirstChildOfClass("PlayerGui")
	if not pg then return { lines = {}, problems = 0 } end

	local vp = Platform.Viewport
	local si = Platform.Insets()
	local availW = vp.X - si.Left - si.Right
	local availH = vp.Y - si.Top - si.Bottom
	local realVp = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or vp
	local realH = realVp.Y - GuiService:GetGuiInset().Y

	local lines = { ("  device %dx%d  usable %dx%d"):format(vp.X, vp.Y, availW, availH) }
	local problems = 0

	for _, nm in ipairs(MODAL_GUIS) do
		local g = pg:FindFirstChild(nm)
		if g and g:IsA("ScreenGui") and g.Enabled then
			local p = biggestPanel(g, realVp.X, realH)
			if p then
				local w, h = p.AbsoluteSize.X, p.AbsoluteSize.Y
				local fw, fh = w / availW, h / availH
				if fw > 1.02 or fh > 1.02 then
					problems += 1
					table.insert(lines, ("    TOO BIG      %-16s %s is %dx%d = %.0f%% x %.0f%% of usable")
						:format(nm, p.Name, w, h, fw * 100, fh * 100))
				end
			end
		end
	end
	if problems == 0 then table.insert(lines, "    clean") end
	return { lines = lines, problems = problems }
end

function HudAudit.RunModals(only: { string }?)
	local report, total = { "===== MODAL AUDIT =====" }, 0
	local realVp = Platform.GetViewportOverride()
	local realCls = Platform.GetOverride()
	local ok, err = pcall(function()
		for _, dev in ipairs(Platform.TEST_SIZES) do
			local skip = false
			if only then
				skip = true
				for _, n in ipairs(only) do if n == dev.name then skip = false break end end
			end
			if not skip then
				-- open first, THEN change device, so each panel's re-fit watch fires
				-- while it is enabled. See EnableModals.
				local restore = HudAudit.EnableModals()
				task.wait(0.3)
				-- An entry may pin its own class (the laptop profiles do -- their short
				-- edge is tablet-sized, so the implied rule would audit them as tablets).
				-- nil clears the override and lets the size imply the class, as before.
				Platform.SetOverride((dev :: any).class)
				Platform.SetViewportOverride(dev.size)
				task.wait(0.8)
				local r = HudAudit.MeasureModals()
				restore()
				total += r.problems
				table.insert(report, ("\n[%s]  %d problem(s)"):format(dev.name, r.problems))
				for _, l in ipairs(r.lines) do table.insert(report, l) end
			end
		end
	end)
	Platform.SetViewportOverride(realVp)
	Platform.SetOverride(realCls)
	if not ok then table.insert(report, "MODAL AUDIT ERROR: " .. tostring(err)) end
	table.insert(report, ("\n===== MODAL PROBLEMS: %d ====="):format(total))
	local text = table.concat(report, "\n")
	print(text)
	return text, total
end

----------------------------------------------------------------- HUD panels
-- The GameHUDPanels modules do not get their own ScreenGuis -- they mount into
-- GameHUD.Canvas.PanelHost -- so MeasureModals above cannot see them, and
-- Measure()'s widget walk skips them too (a panel is bigger than HOST_FRACTION,
-- so collect() classifies it as a container and descends past it). They are also
-- the surface a player spends most of their time in.
--
-- That gap is how six of the seven panels shipped running 29-58px UNDER the
-- Roblox topbar on every phone profile -- the band their title and close button
-- live in -- while both audits reported clean. Measured at 800x360 before the
-- fix: goals/settings/shop 54px under, charms 45px under and 12px past the
-- bottom of the screen, bag 33px, worlds 31px.
--
-- WHY THIS ONE IS FAITHFUL UNDER A DEVICE PREVIEW, when the position checks in
-- Measure() are not. Canvas is OFFSET-sized from Platform.Viewport, so it really
-- does become an 800x360 box when the override says so, and PanelHost is centred
-- inside it. Measuring the panel's top edge RELATIVE TO CANVAS therefore asks a
-- question the simulation can answer honestly -- unlike raw AbsolutePosition,
-- which is reported against the real Studio window. Canvas is full-bleed (GameHUD
-- is DeviceSafeInsets, probed AbsolutePosition.Y = -58), so relative y = 0 is the
-- physical top of the screen and the topbar occupies 0 .. Insets().Top.

-- The ids these panels register under, i.e. GameHUDPanels.*.Id.
--
-- MAINTAINED BY HAND, deliberately. Requiring the modules to read .Id is not
-- safe from here: four of them (BackpackPanel, IndexPanel, SettingsPanel,
-- SellPanel) run a top-level task.spawn, and a require from this context is a
-- SECOND module instance -- see the command-bar cache trap on HudLayout.Debug --
-- so it would start a second copy of that work against the live HUD. Scraping
-- the source for `Id = "..."` is no better: GoalsPanel's first match is its inner
-- id, not the one it registers under.
--
-- A stale entry here is loud rather than silent: an id that does not open is
-- reported as DID NOT OPEN, so a rename shows up as a failing audit line.
--
-- "sell" IS DELIBERATELY ABSENT. It opens fine, and then ClientMain's stall
-- Heartbeat closes it again on the next frame -- it force-closes any open sell
-- panel once the player is more than 20 studs from a sell stall, which is where
-- an audit's character is standing. Listing it here would mean a permanent
-- DID NOT OPEN on every run, and an audit that always reports one failure is an
-- audit nobody reads. It is covered by proxy: SellPanel's fit box is 1180x830,
-- the same one ShopPanel uses, and shop IS walked. Drive it by hand from beside
-- Marco if you need it measured directly.
local PANEL_IDS = { "bag", "goals", "daily", "settings", "charms", "shop", "worlds" }

-- Measure every HUD panel against the CURRENT (possibly simulated) device.
function HudAudit.MeasurePanels(ids: { string }?): { lines: { string }, problems: number }
	local plr = Players.LocalPlayer
	local pg = plr and plr:FindFirstChildOfClass("PlayerGui")
	local gh = pg and pg:FindFirstChild("GameHUD")
	local canvas = gh and gh:FindFirstChild("Canvas")
	local host = canvas and canvas:FindFirstChild("PanelHost")
	if not host then
		return { lines = { "    (GameHUD.Canvas.PanelHost not found -- HUD not built yet)" }, problems = 0 }
	end

	local vp = Platform.Viewport
	local si = Platform.Insets()
	local lines = { ("  device %dx%d  topbar %d  canvas %dx%d")
		:format(vp.X, vp.Y, si.Top, canvas.AbsoluteSize.X, canvas.AbsoluteSize.Y) }
	local problems = 0
	local wasOpen = plr:GetAttribute("HudOpenPanel")

	-- WHERE CANVAS'S TOP EDGE IS, IN SCREEN SPACE.
	--
	-- Canvas is AnchorPoint (0.5,0.5) at Position (0.5,0),(0.5,0) of a full-bleed
	-- ScreenGui, and fit() never writes its Position -- so its centre is always the
	-- centre of the screen. Its HEIGHT, though, is the design canvas fitted, which
	-- equals the viewport only while the fit is height-bound. On a 4:3 tablet
	-- (1180x820) the fit is WIDTH-bound and Canvas is 677 tall, sitting 71px below
	-- the top of the screen -- so a panel 39px below Canvas's top is 110px below
	-- the screen's top, comfortably clear of the topbar, and measuring it against
	-- Canvas alone reports it as 20px underneath. That false positive is the whole
	-- reason this offset is computed rather than assumed to be zero.
	local canvasTop = (vp.Y - canvas.AbsoluteSize.Y) / 2

	for _, id in ipairs(ids or PANEL_IDS) do
		plr:SetAttribute("HudPanelRequest", id)
		task.wait(0.55)
		-- Prefer a visible DIRECT child -- that is where openPanel mounts a panel,
		-- and taking the outermost frame is what makes the topbar maths meaningful.
		-- Fall back to the largest painted descendant for a panel that wraps itself
		-- one level deeper, and require a fully visible chain either way: closed
		-- panels are hidden, not destroyed, so a plain GetDescendants scan happily
		-- measures the LAST panel you opened and reports it as this one.
		local panel: GuiObject? = nil
		for _, c in ipairs(host:GetChildren()) do
			if c:IsA("GuiObject") and c.Visible then panel = c break end
		end
		if not panel then
			local bestArea = 0
			for _, d in ipairs(host:GetDescendants()) do
				if d:IsA("GuiObject") and d.Visible and d.BackgroundTransparency < 0.95
					and d.AbsoluteSize.X > 40 and d.AbsoluteSize.Y > 40 and visibleChain(d) then
					local a = d.AbsoluteSize.X * d.AbsoluteSize.Y
					if a > bestArea then panel, bestArea = d, a end
				end
			end
		end
		if not panel then
			problems += 1
			table.insert(lines, ("    DID NOT OPEN %s -- no visible frame in PanelHost"):format(id))
		else
			local p = panel :: GuiObject
			-- LET THE OPEN GLIDE FINISH FIRST. openPanel hands the panel to
			-- glidePanel, which owns its Position frame-by-frame on RenderStepped
			-- for the length of T.tween.panelOpen -- so a fixed wait measures
			-- wherever the panel had got to, and the answer moves between runs.
			-- Traced exactly that: goals read 9px off the bottom of a 667x375 screen
			-- on one pass and 0.5px inside it on the next, from the same layout; and
			-- bag measured 27px lower than its settled position on the FIRST open of
			-- a session, which is the cold build of a 5264-line panel finishing after
			-- the sample was taken. Wait for the position to stop moving rather than
			-- guessing a duration that covers a cold build.
			--
			-- THREE consecutive stable samples, not one. glidePanel parks the frame at
			-- `from` and then waits a RenderStepped (waitFirstPaint) before it starts
			-- lerping -- so the position is genuinely motionless for a moment BEFORE
			-- the glide, and a single-sample test breaks there and measures the
			-- panel at its entrance offset.
			local last, stable = p.AbsolutePosition.Y, 0
			for _ = 1, 60 do
				task.wait(0.05)
				local now = p.AbsolutePosition.Y
				stable = (math.abs(now - last) < 0.5) and (stable + 1) or 0
				last = now
				if stable >= 3 then break end
			end
			local relTop = canvasTop + (p.AbsolutePosition.Y - canvas.AbsolutePosition.Y)
			local relBot = relTop + p.AbsoluteSize.Y
			local under = math.max(0, si.Top - relTop)
			local past = math.max(0, relBot - vp.Y)
			local wide = math.max(0, p.AbsoluteSize.X - vp.X)
			-- 2px of tolerance on each: these are the product of a float scale and a
			-- centring divide, and a 1px rounding step is not a defect.
			if under > 2 then
				problems += 1
				table.insert(lines, ("    UNDER TOPBAR %-9s %s  %dpx of its top edge is behind the topbar (h=%d, top=%d)")
					:format(id, p.Name, under, p.AbsoluteSize.Y, relTop))
			end
			if past > 2 then
				problems += 1
				table.insert(lines, ("    PAST BOTTOM  %-9s %s  runs %dpx off the bottom of the screen (bottom=%d of %d)")
					:format(id, p.Name, past, relBot, vp.Y))
			end
			if wide > 2 then
				problems += 1
				table.insert(lines, ("    TOO WIDE     %-9s %s  %dpx wide on a %dpx screen")
					:format(id, p.Name, p.AbsoluteSize.X, vp.X))
			end
		end
	end

	-- Leave the HUD as we found it. closePanel() is a local in GameHUDClient and
	-- is reachable only through HudPanelCloseRequest, which that script gates on
	-- the id actually being the open one -- so close by name rather than flipping
	-- host.Visible, which would strand the scrim and the HUD blur.
	plr:SetAttribute("HudPanelRequest", "")
	local nowOpen = plr:GetAttribute("HudOpenPanel")
	if type(nowOpen) == "string" and nowOpen ~= "" then
		plr:SetAttribute("HudPanelCloseRequest", nowOpen)
		task.wait(0.2)
	end
	if type(wasOpen) == "string" and wasOpen ~= "" then
		plr:SetAttribute("HudPanelRequest", wasOpen)
	end

	if problems == 0 then table.insert(lines, "    clean") end
	return { lines = lines, problems = problems }
end

function HudAudit.RunPanels(only: { string }?)
	local report, total = { "===== PANEL AUDIT =====" }, 0
	local realVp = Platform.GetViewportOverride()
	local realCls = Platform.GetOverride()
	local ok, err = pcall(function()
		for _, dev in ipairs(Platform.TEST_SIZES) do
			local skip = false
			if only then
				skip = true
				for _, n in ipairs(only) do if n == dev.name then skip = false break end end
			end
			if not skip then
				-- device FIRST here, unlike RunModals: these panels are re-fitted by
				-- GameHUDClient.openPanel on the way in, so opening after the device
				-- change is both realistic and correctly fitted. (The modal panels
				-- audited above re-fit on a device change instead, guarded by
				-- gui.Enabled, which is why that one has to open first.)
				Platform.SetOverride((dev :: any).class)
				Platform.SetViewportOverride(dev.size)
				task.wait(0.6)
				local r = HudAudit.MeasurePanels()
				total += r.problems
				table.insert(report, ("\n[%s]  %d problem(s)"):format(dev.name, r.problems))
				for _, l in ipairs(r.lines) do table.insert(report, l) end
			end
		end
	end)
	Platform.SetViewportOverride(realVp)
	Platform.SetOverride(realCls)
	if not ok then table.insert(report, "PANEL AUDIT ERROR: " .. tostring(err)) end
	table.insert(report, ("\n===== PANEL PROBLEMS: %d ====="):format(total))
	local text = table.concat(report, "\n")
	print(text)
	return text, total
end

-- Walk the device list. `only` optionally filters to named sizes.
function HudAudit.Run(only: { string }?, settle: number?)
	local wait_ = settle or 0.6
	local report: { string } = { "===== HUD AUDIT =====" }
	local total = 0

	local realClass = Platform.GetOverride()
	local realVp = Platform.GetViewportOverride()

	local ok, err = pcall(function()
		for _, dev in ipairs(Platform.TEST_SIZES) do
			local skip = false
			if only then
				skip = true
				for _, n in ipairs(only) do
					if n == dev.name then skip = false break end
				end
			end
			if not skip then
				Platform.SetOverride((dev :: any).class)
				Platform.SetViewportOverride(dev.size)
				task.wait(wait_)
				local r = HudAudit.Measure()
				total += r.problems
				table.insert(report, ("\n[%s]  %d problem%s")
					:format(dev.name, r.problems, r.problems == 1 and "" or "s"))
				for _, l in ipairs(r.lines) do table.insert(report, l) end
			end
		end
	end)

	Platform.SetViewportOverride(realVp)
	Platform.SetOverride(realClass)

	if not ok then
		table.insert(report, "AUDIT ERROR: " .. tostring(err))
	end
	table.insert(report, ("\n===== TOTAL PROBLEMS: %d ====="):format(total))
	local text = table.concat(report, "\n")
	print(text)
	return text, total
end

return HudAudit
