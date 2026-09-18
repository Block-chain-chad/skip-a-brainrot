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
-- CHAT RESERVE (feedback item 5, 2026-08-19). Roblox's chat window is CoreGui, and
-- CoreGui ALWAYS renders above PlayerGui -- no DisplayOrder beats it -- so the
-- top-left rect the chat owns is not ours to draw in. Measured at the 1891x772 dev
-- window, CurrencyCluster sat at x 18..462 / y 76..146: entirely inside it, on
-- every viewport, unconditionally. The counters lost, every time.
local TextChatService = game:GetService("TextChatService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local modules = ReplicatedStorage:WaitForChild("Modules")

local UIKit = modules:WaitForChild("UIKit")
local T = require(UIKit:WaitForChild("Tokens"))
local UI = require(UIKit:WaitForChild("Builders"))
-- 2026-08-09 HUD upgrade (design_handoff_hud_upgrade): illustrated button /
-- counter art ids and the sheet's HUD numbers live in UIKit.SpecTheme.
local SPEC = require(UIKit:WaitForChild("SpecTheme"))
-- One source of truth for device class, UI scale and safe insets. Everything
-- that used to be `math.min(vp.X / 1350, vp.Y / 775)` inline goes through it.
local Platform = require(modules:WaitForChild("Platform"))
local HudLayout = require(modules:WaitForChild("HudLayout"))
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
-- Notch / rounded-corner handling. IgnoreGuiInset stays true (this HUD does its
-- own topbar maths in fit()), but DeviceSafeInsets still keeps the layer clear
-- of a phone's camera cutout, which nothing in this place was doing before.
Platform.PrepareGui(gui, true)
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
--
-- 2026-08-05 cross-platform: the three scales below are now DIFFERENT numbers
-- on a phone or a console, where they used to be one. See Modules.Platform.
--   canvasScale  fits the 1350x775 canvas. Unboosted -- a fit is already the
--                largest scale that fits, so boosting it overflows the screen.
--   chromeScale  edge-anchored furniture (pills, rail). Boosted, because this
--                layer is resized to the viewport every pass and has no canvas
--                to overflow -- a phone needs thumb-sized controls.
--   hostScale    modals. Fits the OPEN PANEL's box rather than the whole
--                canvas, so a 960-wide panel fills a handset instead of
--                floating in the middle of it at 30% size. Re-solved by
--                openPanel whenever the open panel's fit width changes.
-- All three collapse to the old single value on desktop (boost 1.0), so the
-- desktop HUD is pixel-identical to what it was.
local canvasScale = Instance.new("UIScale")
canvasScale.Parent = root

local chromeScale = Instance.new("UIScale")
chromeScale.Parent = chrome

-- Assigned once the rail exists, further down: the rail centres itself
-- within the chrome layer's height, and that height is viewport-dependent,
-- so it has to be recomputed on every fit().
local layoutRail = nil
-- Same deal for the panel host's own scale, created with the host below --
-- and (2026-08-16) for the host frame itself: fit() now writes its Position
-- too, to keep a tall panel's top edge below the currency counter band.
local host = nil
local hostScale = nil

-- Design-box the panel host is currently fitted against. Panels are NOT all one
-- width (T.size.panelWidth: settings 700, daily 800, goals 860, index/eggs 940,
-- pass/backpack 960, charms 1120), so one global constant either clips the
-- widest panel or shrinks every other one. openPanel writes the open panel's
-- own width here and re-fits; fit() reads it.
--
-- FLOORED AT 960 -- the box every panel was fitted against before the Charm
-- Codex arrived -- and that floor is load-bearing, not defensive. Fitting each
-- panel to its own width UNfloored flips the four panels narrower than 960 from
-- width-bound to height-bound on a 4:3 tablet and grows them: measured at
-- 1024x768, settings/daily/goals +2.86% and index +2.13%. Nobody asked the six
-- shipped panels to move, so the floor pins them to exactly today's scale and
-- only a panel WIDER than 960 changes anything at all.
local PANEL_FIT_FLOOR_W = 960
local PANEL_FIT_H = 700
local panelFitW = PANEL_FIT_FLOOR_W
-- 2026-08-09 HUD upgrade: spec panels are authored in the build sheet's own
-- px and are TALLER than 700 (settings 1090, shop 830) -- the fit box gets a
-- per-panel HEIGHT to match, same floored mechanism as the width. Legacy
-- panels have no panelHeight entry and stay pinned at exactly 700.
local panelFitH = PANEL_FIT_H

-- Forward-declared like layoutRail: the UIScale is built WITH the currency
-- cluster further down; fit() caps its phone footprint (2026-08-17 audit --
-- the cluster is ~466 fixed design px on the chrome layer, and the 1.70
-- phone chrome boost rendered it ~57% of an iPhone 7's width, over the
-- player's own nametag).
local clusterCapScale
-- Forward-declared with clusterCapScale for the same reason: fit() writes the
-- cluster's Position now (chat reserve, below) and the cluster is built further down.
local currencyCluster

-- The chat publishes its own rect in screen px. Returns 0,0 whenever the chat is
-- off or has been moved off the top-left, so a future ChatWindowConfiguration
-- change silently retires all of this rather than leaving a stale reserve behind.
local CHAT_GAP = 12

--[[ THE COUNTERS STAY ON THE LEFT EDGE (2026-08-19, owner: "the cash and emerald
counter is messed up, move it back to where it has been").

The reserve below sizes itself off ChatWindowConfiguration, which reports the
chat's rect whenever the chat is ENABLED -- not whenever it is actually on screen.
The chat is enabled permanently and shows only when a message arrives, so the
cluster was pushed ~272px right of HUD_EDGE_PAD one hundred percent of the time to
dodge something that is usually not there. It also broke the deliberate "cluster
and nav rail share one left edge" alignment, which the note below already admits
is the cost.

The trade it was buying is real but rare: while a message IS up, the pills sit
under a 70%-opaque panel. Rare and temporary beats permanent and misaligned, so
the slide is off. Set RESERVE_FOR_CHAT = true to restore it -- and if the overlap
ever needs solving properly, drive it off the chat's actual VISIBILITY rather than
its Enabled flag. ]]
local RESERVE_FOR_CHAT = false

local function chatReserve(): (number, number)   -- right edge, bottom edge, screen px
	if not RESERVE_FOR_CHAT then return 0, 0 end
	local cfg = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
	if not cfg or not cfg.Enabled then return 0, 0 end
	if cfg.HorizontalAlignment ~= Enum.HorizontalAlignment.Left then return 0, 0 end
	if cfg.VerticalAlignment ~= Enum.VerticalAlignment.Top then return 0, 0 end
	local pos, size = cfg.AbsolutePosition, cfg.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then return 0, 0 end
	return pos.X + size.X + CHAT_GAP, pos.Y + size.Y + CHAT_GAP
end

local function fit()
	local camera = workspace.CurrentCamera
	if not camera then return end
	-- Platform.Viewport, NOT camera.ViewportSize (2026-08-27). Same value in play;
	-- different under a device preview, and that difference is the point. Reading
	-- the camera meant this whole layer sized itself against the real Studio window
	-- no matter what device was being previewed, so every footprint budget below
	-- was evaluated against 1920x1077 and never bound. The rail's 40%-of-height cap
	-- was silently a no-op in every test that was supposed to exercise it.
	local vp = Platform.Viewport
	local scale = Platform.Fit(T.size.canvas.X, T.size.canvas.Y)
	-- BLOCKS get the unboosted scale; TYPE is re-authored to compensate. Before the
	-- split this was Platform.Chrome, which on a phone is 0.875 against a 0.515 fit
	-- -- i.e. the boxes were drawn at 1.7x the share of the screen they take on a
	-- monitor. See Platform.Block.
	local chromeS = Platform.Block(T.size.canvas.X, T.size.canvas.Y)
	canvasScale.Scale = scale
	chromeScale.Scale = chromeS
	HudLayout.CompensateType(chrome, Platform.TypeCompensation(T.size.canvas.X, T.size.canvas.Y))

	-- TOUCH FLOOR FOR THE CURRENCY COUNTERS (2026-08-27).
	--
	-- These are ImageButtons, not just readouts -- the gem counter opens the shop.
	-- Their height comes from SPEC.Hud.CounterH scaled by chromeScale, and the
	-- unboosted block scale that fixed the HUD's footprint also took them under
	-- Roblox's 44px minimum: measured 41px on a 867x399 handset, 38px on a 667x375
	-- one. Shrinking the blocks was right; letting a control fall under the touch
	-- floor was not, so the floor is enforced here rather than by giving the boost
	-- back to everything.
	--
	-- The authored height is stashed per instance so this is idempotent -- it runs
	-- on every device change, and computing from the live value would ratchet the
	-- counters taller on every rotation.
	if currencyCluster then
		local cs = math.max(chromeS, 0.01)
		-- +1 design px of margin: ceil(44 / cs) * cs can still round DOWN to 43 on
		-- the way to the screen, and 43 is a failing touch target for the sake of a
		-- rounding step. Measured exactly that at 667x375 before the margin.
		local floorH = math.ceil(HudLayout.MIN_TOUCH / cs) + 1
		for _, c in ipairs(currencyCluster:GetChildren()) do
			if c:IsA("GuiButton") then
				local authored = c:GetAttribute("AuthoredCounterH")
				if authored == nil then
					authored = c.Size.Y.Offset
					c:SetAttribute("AuthoredCounterH", authored)
				end
				local want = Platform.IsTouch and math.max(authored :: number, floorH) or authored
				if c.Size.Y.Offset ~= want then
					c.Size = UDim2.new(c.Size.X.Scale, c.Size.X.Offset, c.Size.Y.Scale, want)
				end
			end
		end
	end

	-- Safe area, not just the topbar. Console TVs clip the outer ~3.5% of the
	-- picture, and on touch the bottom band belongs to Roblox's own thumbstick
	-- and jump button -- the nav rail used to sit right on top of them. Read
	-- up here (its chrome consumers sit further down) because the panel block
	-- below needs si.Top for its top-clearance maths.
	local si = Platform.Insets()

	-- Panels get their own multiplier ON TOP of the canvas scale, so the net
	-- scale on a modal is exactly Platform.FitPanel. Divided out rather than
	-- set directly because hostScale is nested inside canvasScale and the two
	-- multiply.
	--
	-- Fitted against the OPEN panel's box (panelFitW, written by openPanel), not
	-- a constant. This line used to read FitPanel(960, 700) with a comment
	-- claiming 960 was the widest registered panel; CharmsPanel is 1120 and hung
	-- 43px off the side of a 4:3 tablet (measured, 1024x768). Simply raising the
	-- constant to 1120 fixes that but costs every OTHER panel 14.29% of its scale
	-- on the same device, which is a worse trade than the bug.
	if hostScale then
		local fitScale = Platform.FitPanel(panelFitW, panelFitH)
		-- 2026-08-10 (user capture): panels bigger than the old 960x700 family
		-- are authored on the SHEET's 1920x1080 canvas, and fitting them with
		-- the game-canvas rules ballooned them on large windows -- a 1.39x bag
		-- rendered under the currency counters and the shop crossed the nav
		-- rail. On desktop they scale by the sheet's own rule instead --
		-- min(vpX/1920, vpY/1080), clamped 0.62-1.35 per the sheet -- so they
		-- occupy exactly the screen fraction they were designed to.
		if Platform.IsDesktop and (panelFitW > PANEL_FIT_FLOOR_W or panelFitH > PANEL_FIT_H) then
			fitScale = math.min(fitScale, math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.62, 1.35))
		end
		-- and whatever path produced the scale, a modal must never overflow
		-- the viewport (Platform.FitPanel pins desktop to the canvas fit, and
		-- settings' 1090 shell is taller than the 775 canvas).
		-- 2026-08-11 polish: tall shells used to KISS the currency counters at
		-- small windows -- the height clamp now reserves the HUD's top counter
		-- band (EdgePad + CounterH, chrome-scaled) on both edges, because the
		-- host centres its panel, so half the reserve lands above it.
		-- PHONE (2026-08-19, measured): reserving this band on BOTH edges costs
		-- 154px of a 374px landscape phone -- 41% of the height -- and that clamp
		-- then BEAT Platform.FitPanel, crushing panels to 0.299 when they could
		-- run at 0.483 (the Bag rendered 323x215 on a 666x374 screen: every label
		-- in it sat around 7px). There is nothing to reserve on a phone anyway --
		-- panels are modal there, so openPanel hides the rail AND the currency
		-- cluster while one is open. Desktop keeps the reserve exactly as it was.
		local counterBand = Platform.IsPhone and 0
			or (SPEC.Hud.EdgePad + SPEC.Hud.CounterH + 6) * chromeS
		local hard = math.min(vp.X / panelFitW, math.max(vp.Y - counterBand * 2, 200) / panelFitH) * 0.98

		-- ...AND IT MUST FIT UNDER THE TOPBAR (2026-08-28).
		--
		-- Every height budget above measures against the RAW viewport, so the only
		-- thing keeping a panel clear of the Roblox topbar was having enough spare
		-- height that its centred top margin happened to exceed it. On a monitor
		-- that is free: the topbar is 5% of 1080 and the counter reserve alone
		-- leaves a 131px margin. On a handset it is 16% of 360 and there is no
		-- spare, because counterBand is deliberately 0 on a phone (panels are modal
		-- there, so there are no counters to clear).
		--
		-- Canvas is a FULL-BLEED layer -- GameHUD is DeviceSafeInsets, so Canvas's
		-- y=0 is the physical top of the screen, above the topbar (probed:
		-- AbsolutePosition.Y = -58). Centring in it centres in the whole display,
		-- topbar included. Measured at 800x360 before this clamp, with the panel
		-- heights each panel actually asks for:
		--
		--   goals/settings/shop  352px tall, top edge 3px  -> 54px under the topbar
		--   charms               360px tall               -> 45px under, 12px past the bottom
		--   bag                  334px tall               -> 33px under
		--   worlds               306px tall               -> 31px under
		--
		-- That band is where a panel's title and its CLOSE BUTTON live. Same defect
		-- class as MainUI's SKIP/SHOPS/PLOT tabs at y = -48 (see the fixed-defects
		-- table in the handoff): a full-bleed layer that never added the inset back.
		--
		-- Applied as a MINIMUM against the existing budget, never a replacement, so
		-- it can only ever shrink a panel. Verified that it does not bind off-phone:
		-- on desktop and tablet counterBand * 2 is already the stricter of the two
		-- (262px vs 58px at 1080p), and on console TV_SAFE makes it stricter still --
		-- so desktop, tablet and console keep exactly today's scale.
		--
		-- BOTTOM EDGE: deliberately NOT reserved. Insets().Bottom is the full-width
		-- touch strip (112px on a phone); taking it here would leave a 360px screen
		-- 190px of band and crush settings' 1090px shell to 0.17, i.e. body text
		-- under 3px. That is Platform.Height's own note about floors, from the other
		-- direction: below a certain size the panel needs to scroll or reflow, and
		-- shrinking it further is not an answer. A centred modal is horizontally
		-- clear of the two bottom CORNERS the controls actually occupy at most of
		-- these sizes anyway (at 800x360 the widest panel spans x 142..657 against
		-- corners of 0..137 and 663..800), and the topbar is the band that always
		-- obscures, full width, on every device. Fix that one; do not trade it for
		-- an unreadable panel.
		--
		-- CLAMPED ON THE PAINTED LAYER, WHICH IS NOT panelFitW x panelFitH.
		--
		-- The panels come in two shapes and the fit box describes only one of them:
		--
		--   offset-authored  bag is {0,1080},{0,720}; also goals, settings, shop,
		--                    daily, worlds. These really are panelFit* tall and wide.
		--   host-filling     CharmsPanel is {1,0},{1,0}, so it renders host's box --
		--                    1350x775, the whole canvas -- while T.size.panelWidth
		--                    declares it 1120 and gives it no panelHeight entry at
		--                    all, leaving panelFitH on the 700 floor.
		--
		-- ...and the two overlap in both directions, which is why neither box alone
		-- works as the bound. Charms is TALLER than its declared box (775 vs 700), so
		-- clamping on panelFitH exempts it -- measured 327px tall in a 302px band,
		-- 20px off the bottom of an 800x360 screen. But settings (1090), shop and
		-- sell (830) and goals (800) are all taller than the CANVAS, so they hang out
		-- of host and clamping on host's box exempts them instead -- measured
		-- settings still 51px under the topbar with host itself sitting correctly
		-- inside the band. Both of those were live failures of earlier cuts of this
		-- fix, in opposite directions.
		--
		-- The painted layer is the LARGER of the two on each axis. That is one
		-- expression that is true for both shapes, and it is what the band has to
		-- hold. Do not "simplify" it back to either box on its own -- each one looks
		-- right and each one silently exempts half the panels.
		--
		-- The width term is conservative for a narrow offset panel (its host is wider
		-- than it paints), but it is never the binding constraint for one: phones are
		-- wide and short so height always binds first, and on desktop and tablet it
		-- computes above the height term for every registered panel. Verified across
		-- all seven profiles -- the only thing it moves is Charms on a 4:3 tablet,
		-- where it really was 1223px wide on a 1180px screen.
		local layerW = math.max(T.size.canvas.X, panelFitW)
		local layerH = math.max(T.size.canvas.Y, panelFitH)
		local bandFit = math.min(vp.X / layerW, math.max(vp.Y - si.Top, 120) / layerH)
		hard = math.min(hard, bandFit)

		hostScale.Scale = (scale > 0) and (math.min(fitScale, hard) / scale) or 1

		-- 2026-08-16 top clearance: the counterBand reserve above measures from
		-- y=0, but the REAL band hangs from the chrome layer, which is inset
		-- si.Top below the top of the window -- so a height-bound tall panel
		-- (settings' 1090 shell) still rose ~si.Top px into the currency
		-- cluster at narrow windows, and the counters drew over the panel
		-- title ("TTINGS"). Widening the reserve instead would shrink panels at
		-- viewports that are fine today; so the HOST slides down just far enough
		-- that the fitted box's top edge clears the band, and stays dead centre
		-- (offset 0) whenever the panel already clears the counters.
		--
		-- GATED ON REAL OVERLAP: the cluster hugs the top-LEFT, so at wide
		-- windows a box whose top rows sit level with the band never touches it
		-- (measured at the 1891x772 dev window: bag left edge 553 vs cluster
		-- right 462) and moving it would change sanctioned layouts for nothing.
		-- The slide only engages when the box's left edge actually reaches the
		-- cluster's column -- which is exactly the narrow-viewport regime the
		-- bug lives in -- so fit() is behaviour-identical to before at every
		-- viewport where the panel clears the band on its own.
		local netScale = math.min(fitScale, hard)
		local boxTop = (vp.Y - panelFitH * netScale) / 2 -- host centres in the full window
		local boxLeft = (vp.X - panelFitW * netScale) / 2
		local bandBottom = si.Top + counterBand -- chrome (and the cluster) starts at si.Top
		-- Cluster's right edge: EdgePad + coin pill (190) + gap + gem counter
		-- (GEM.W, 246), chrome-scaled. Fixed widths by design (see buildCounter:
		-- "no AutomaticSize ... the counter never breathes"), so this stays a
		-- constant -- update it if the cluster gains or resizes a counter.
		local clusterRight = si.Left + (SPEC.Hud.EdgePad + 190 + SPEC.Hud.CounterGap + 246) * chromeS
		-- HOW FAR DOWN THE BOX HAS TO START.
		--
		-- Two different things can push it down, and they are not the same shape:
		--
		--   the TOPBAR      full width, on every device, always drawn over game UI.
		--                   Counts whenever the box's top edge reaches into it.
		--   the COUNTER BAND hangs BELOW the topbar and only occupies the top-LEFT,
		--                   so it only counts when the box actually reaches the
		--                   cluster's column -- and not at all on a phone, where
		--                   openPanel hides the counters while a panel is open.
		--
		-- The phone used to be excluded from the slide entirely, and the reason
		-- given was sound at the time: "a near full-height modal has nowhere to
		-- slide TO (it would push itself off the bottom of the screen)". That was
		-- true while a panel could be as tall as the whole viewport. It cannot any
		-- more -- bandFit above caps host at vp.Y - si.Top -- so sliding it clear of
		-- the topbar now lands its bottom edge at vp.Y exactly, never past it. The
		-- two changes are a pair: re-introducing the exclusion without also dropping
		-- bandFit puts the panel straight back under the topbar.
		--
		-- Desktop, tablet and console keep the old expression exactly: they take the
		-- elseif, and there counterBand * 2 already holds boxTop at or below 131px --
		-- well clear of a 58px topbar -- so bandFit never binds on them either.
		--
		-- The phone branch measures the PAINTED LAYER (layerH), for the same reason
		-- the clamp above does: boxTop is derived from panelFitH, which describes
		-- neither a host-filling panel nor one taller than the canvas. layerH is the
		-- one extent that is true for every panel, and everything is centred on the
		-- same point, so sliding that clear of the topbar slides all of them clear.
		local pushDown = 0
		if Platform.IsPhone then
			local layerTop = (vp.Y - layerH * netScale) / 2
			pushDown = math.max(si.Top - layerTop, 0)
		elseif boxLeft < clusterRight then
			pushDown = math.max(bandBottom - boxTop, 0)
		end
		-- The offset is in canvas design px: host sits under canvasScale, and a
		-- frame's own UIScale never moves its Position.
		host.Position = UDim2.new(0.5, 0, 0.5, (scale > 0) and (pushDown / scale) or 0)
	end

	chrome.Position = UDim2.fromOffset(si.Left, si.Top)
	chrome.Size = UDim2.fromOffset(
		math.max(vp.X - si.Left - si.Right, 1) / chromeS,
		math.max(vp.Y - si.Top - si.Bottom, 1) / chromeS)

	-- PHONE footprint cap for the currency cluster -- the same treatment
	-- layoutRail applies to the rail below: never wider than ~45% of the
	-- screen. The cluster is top-left anchored, so the UIScale shrinks it
	-- into its own corner. Desktop/tablet/console: cap computes >= 1, held
	-- at exactly 1 so nothing changes off-phone.
	if clusterCapScale then
		local CLUSTER_W = SPEC.Hud.EdgePad + 190 + SPEC.Hud.CounterGap + 246
		-- 0.45 -> 0.38 (2026-08-24). Nearly half the width for two read-only
		-- counters was too much to spend on a screen this short, and it is the
		-- other half of the collision in the owner's capture: the cluster hangs
		-- top-left and the nav rail is centred on the same edge, so the counters
		-- ended up behind the Shop tile. 0.38 keeps the counter text at ~19px --
		-- still well clear of the 13.6px that made it unreadable before the phone
		-- boost went in -- while giving the rail its corner back.
		local cap = math.min(1, (vp.X * 0.38 / chromeS) / CLUSTER_W)
		clusterCapScale.Scale = Platform.IsPhone and cap or 1
	end

	-- SLIDE THE COUNTERS OUT OF THE CHAT'S RECT (feedback item 5). The chat hangs
	-- from the safe-area top-left and so does this cluster, so they were fighting
	-- over one corner and CoreGui always won -- the coin and gem pills sat UNDER a
	-- 70%-opaque dark panel whenever a message was up. Prefer sliding RIGHT (keeps
	-- the counters on the top edge where the PS99 grammar wants them); if the
	-- viewport is too narrow for that, drop BELOW the chat instead; if neither
	-- fits, stay put rather than run off-screen. Written here rather than once at
	-- build time because the chat rect tracks the viewport and Width/HeightScale.
	-- COST: this breaks the deliberate "cluster and nav rail share one left edge"
	-- alignment. That is the price of the fix -- the alternative is counters you
	-- cannot read.
	if currencyCluster then
		local chatRight, chatBottom = chatReserve()
		local left, top = SPEC.Hud.EdgePad, SPEC.Hud.EdgePad
		if chatRight > 0 then
			local capS = clusterCapScale and clusterCapScale.Scale or 1
			local clusterW = (190 + SPEC.Hud.CounterGap + 246) * capS
			local wanted = (chatRight - si.Left) / chromeS
			local room = chrome.Size.X.Offset - SPEC.Hud.EdgePad - clusterW
			if wanted <= room then
				left = math.max(SPEC.Hud.EdgePad, wanted)
			else
				top = math.max(SPEC.Hud.EdgePad, (chatBottom - si.Top) / chromeS)
			end
		end
		currencyCluster.Position = UDim2.fromOffset(left, top)
	end

	if layoutRail then layoutRail() end
end
-- Platform.Watch fires now and on every viewport / device / input change, so
-- this replaces the old ViewportSize connection and both delayed re-reads.
Platform.Watch(fit)

-- ...and on every change to the CHAT's rect, which Platform knows nothing about
-- (the player collapsing it, a Width/HeightScale edit, device rotation).
task.spawn(function()
	local cfg = TextChatService:WaitForChild("ChatWindowConfiguration", 10)
	if not cfg then return end
	for _, prop in ipairs({ "AbsoluteSize", "AbsolutePosition", "Enabled",
		"HorizontalAlignment", "VerticalAlignment" }) do
		cfg:GetPropertyChangedSignal(prop):Connect(fit)
	end
	fit()
end)

---------------------------------------------------------------- scrim
-- HUD RESCUE (2026-07-31): a sibling of the canvas, not a child of it. As a
-- child it only ever darkened the canvas, leaving the letterbox bars (273px
-- down each side at the measured 1891x772) bright behind an open modal.
local scrim = Instance.new("Frame")
scrim.Name = "Scrim"
scrim.Size = UDim2.fromScale(1, 1)
scrim.BackgroundColor3 = T.scrim
-- hardened 2026-08-17 (round-8 hunt): built fully transparent so a future
-- "Visible = true" regression cannot repaint the retired dark dim
scrim.BackgroundTransparency = 1
scrim.BorderSizePixel = 0
scrim.Visible = false
scrim.ZIndex = T.zindex.panel -- 25: below Canvas (26), so panels sit above it
scrim.Parent = gui

-- PS99 blur-never-dim (2026-08-17 field-study rule): panels separate from the
-- world with ONE shared backdrop blur; the scrim above stays parented for
-- layering but never paints again. Instant on/off, no tween -- BlurEffect
-- property tweens sit in the same TweenService non-GuiObject no-op family the
-- UIScale entrance died of, and the per-panel recipe this centralises
-- (SettingsPanel/BackpackPanel et al) was always instant anyway.
local HUD_BLUR_NAME = "HUDPanelBlur"
local function setPanelBlur(on)
	local Lighting = game:GetService("Lighting")
	local existing = Lighting:FindFirstChild(HUD_BLUR_NAME)
	if on and not existing then
		local blur = Instance.new("BlurEffect")
		blur.Name = HUD_BLUR_NAME
		blur.Size = 10
		blur.Parent = Lighting
	elseif not on and existing then
		existing:Destroy()
	end
end

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
-- Assigned into the forward-declared local (next to hostScale's, above fit)
-- so fit() can nudge its Position for the counter-band top clearance.
host = Instance.new("Frame")
host.Name = "PanelHost"
host.Size = UDim2.fromScale(1, 1)
-- CENTRE-ANCHORED (2026-08-10): hostScale scales this frame about its
-- ANCHOR point, and with the default (0,0) any scale other than exactly 1
-- shrank the whole modal layer toward the canvas's top-left corner -- the
-- shop measured at x62/y-78 instead of dead centre. Desktop never saw it
-- before because FitPanel pinned desktop hostScale to exactly 1; the
-- sheet-fit for spec panels (and phones all along) runs it off 1.
host.AnchorPoint = Vector2.new(0.5, 0.5)
-- fit() re-asserts this every pass: dead centre, plus a y offset only when
-- its top-clearance maths needs to keep the box below the counter band.
host.Position = UDim2.fromScale(0.5, 0.5)
host.BackgroundTransparency = 1
host.Visible = false
host.ZIndex = T.zindex.panel + 1 -- 26: directly above the scrim, per brief Step 2
host.Parent = root

-- Assigned into the forward-declared local so fit() can drive it (fit runs
-- before this line on the first pass, hence the nil guard up there).
hostScale = Instance.new("UIScale")
hostScale.Name = "PanelScale"
hostScale.Parent = host
fit()

-- SELF-HEALING BLUR (2026-08-17 round-8 regression catch): the blur used to
-- follow only openPanel/closePanel, but the panel layer can be hidden by
-- DIRECT Visible writes that bypass both -- caught live: host hidden, zero
-- panels visible, HUDPanelBlur still on, world blurred over nothing. The
-- blur now also follows the host's own Visible -- the one observable that
-- is true exactly while the panel layer is up -- so any out-of-band hide
-- clears it. The explicit calls in openPanel/closePanel stay as the primary
-- path (idempotent; this watcher only fires on actual flips).
host:GetPropertyChangedSignal("Visible"):Connect(function()
	setPanelBlur(host.Visible)
end)

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
-- Same abbreviation family EmeraldHUDClient uses (NumberFormat.Short),
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
	-- emerald has no kit PNG and never will (he is ours, not the kit's), so this
	-- is only reached if IconArt itself fails to load; the diamond is the same
	-- stand-in the currency used before he had a face.
	emerald = "\u{1F48E}",
	-- rebirth is also ours (7th button, no kit PNG): only reached if IconArt
	-- fails to load. U+2B50 is the same star the legacy SideRail tile used,
	-- proven rendering there since 07-26.
	rebirth = "\u{2B50}",
	-- worlds (2026-08-07) has neither a kit PNG nor an IconArt drawing, so unlike
	-- the two above this glyph is the REAL icon, not a fallback for one. Proven the
	-- way this block asks: U+1F30D rendered live in the WorldsPanel header on this
	-- build before it was added here. Give it a drawing in IconArt and it retires
	-- itself -- the chain prefers art over glyphs.
	worlds = "\u{1F30D}",
	-- shop, same situation and the same rule. U+1F6D2 TROLLEY is proven by the
	-- ShopPanel header rendering it on this build; if it ever shows as a box here,
	-- that is this glyph failing and not the rail.
	shop = "\u{1F6D2}",
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
-- Top 18 / left 18, gap 12 (kit README 3.7).
--
-- 2026-08-05: the cluster STAYS VISIBLE while a panel is open. It used to be
-- hidden on every openPanel, so opening Goals (or any other panel) blanked
-- your coin/gem counts -- which reads as the menu having eaten your currency,
-- and is the exact opposite of what you want on a screen whose whole job is
-- showing you what a reward costs or pays. It lives on the `chrome` layer
-- (ZIndex 30), a SIBLING of the canvas (26) and scrim (25), so it already
-- renders above an open panel with no z-fighting -- the same treatment the
-- nav rail on that layer has always had. No panel reaches it either: the
-- widest one is 960 design px on the 1350 canvas, leaving 195px gutters, and
-- the cluster ends ~150px in.
-- The left margin every chrome-layer element hugging the screen edge shares.
-- The nav rail reads it too (see layoutRail) so the coin pill and the icon
-- column below it line up on one edge instead of stepping in and out.
local HUD_EDGE_PAD = 18

currencyCluster = Instance.new("Frame") -- assigns the forward-declared upvalue; fit() writes its Position
currencyCluster.Name = "CurrencyCluster"
currencyCluster.Position = UDim2.fromOffset(HUD_EDGE_PAD, HUD_EDGE_PAD)
-- DECLARE THE SPACE, don't make others measure it. ClientMain's tab bar used to
-- read this frame's AbsolutePosition out of another ScreenGui and convert between
-- two inset spaces by hand to decide whether it fitted beside the cluster; it now
-- asks HudLayout, which routes it below when there is no room.
--
-- Registered ONCE, here, rather than from fit(): HudLayout re-reads the frame's
-- rect every pass, so it tracks chatReserve moving the cluster anyway, and a call
-- inside fit() sits upstream of layoutRail() -- when the first version of this
-- threw, it took the whole nav rail's layout down with it.
HudLayout.Obstacle("CurrencyCluster", currencyCluster)
currencyCluster.Size = UDim2.new(0, 0, 0, SPEC.Hud.CounterH)
currencyCluster.AutomaticSize = Enum.AutomaticSize.X
currencyCluster.BackgroundTransparency = 1
currencyCluster.ZIndex = T.zindex.currency
currencyCluster.Parent = chrome -- screen edge, not canvas edge (see the chrome layer)

local clusterList = Instance.new("UIListLayout")
clusterList.FillDirection = Enum.FillDirection.Horizontal
clusterList.VerticalAlignment = Enum.VerticalAlignment.Center
clusterList.SortOrder = Enum.SortOrder.LayoutOrder
clusterList.Padding = UDim.new(0, SPEC.Hud.CounterGap)
clusterList.Parent = currencyCluster

-- phone footprint cap target (see the forward declaration above fit()); the
-- cluster is built AFTER Platform.Watch(fit) first fired, so run fit() once
-- now that the scale exists or the cap would wait for the next viewport event
clusterCapScale = Instance.new("UIScale")
clusterCapScale.Name = "PhoneFootprintCap"
clusterCapScale.Parent = currencyCluster
fit()

-- 2026-08-09 HUD upgrade (design_handoff_hud_upgrade): both counters are the
-- handoff's painted pill PNGs now (SPEC.Art), with a live TextScaled overlay
-- sitting where the sheet's baked number was (README "asset pipeline": the
-- digits were cropped out of the art before upload). Fixed widths from
-- SPEC.Hud, so the old text-measuring path (Bug A's sizePillToValue) retired
-- with the drawn pills.
--
-- OWNER DECISION (2026-08-09): the handoff's new emerald face is REJECTED.
-- The premium pill was uploaded with that face and its gems erased, and the
-- game's own drawn emerald (UIKit.IconArt, unchanged) sits over the pill's
-- left end instead -- same face the egg shop and goals rows wear.
-- Field study delta 3 (user-approved 2026-08-16): currencies are BARE -- a
-- tilted sticker icon + outlined numeral floating on the world, zero pill
-- chrome (PS99 grammar: passive info gets no plate). `artId` is now the
-- ICON art, not pill art. Retires the painted counter PNGs; the user
-- explicitly approved reversing the 2026-08-09 premiumCounter owner call.
local function buildCounter(order, name, artId, width, isButton, valuePos)
	local c = Instance.new(isButton and "ImageButton" or "ImageLabel")
	c.Name = name
	c.LayoutOrder = order
	c.Image = ""
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.ScaleType = Enum.ScaleType.Fit
	c.Size = UDim2.fromOffset(width, SPEC.Hud.CounterH)
	c.ZIndex = T.zindex.currency
	if isButton then
		c.AutoButtonColor = false
	end
	c.Parent = currencyCluster

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Image = artId
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Size = UDim2.fromOffset(56, 56)
	icon.Position = UDim2.new(0, 0, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Rotation = -6 -- sticker lean, same as the rail
	icon.ZIndex = T.zindex.currency + 1
	icon.Parent = c

	-- overlay label: geometry from the sheet (Position 0.66,0.5 / Size
	-- 0.52,0.42 in scale units of the pill image). NoPolish: this is spec
	-- type (LuckiestGuy + dark stroke), not UIPolish's GothamBold.
	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.BackgroundTransparency = 1
	value.Font = SPEC.Font.Shout
	value.TextColor3 = Color3.new(1, 1, 1)
	value.TextScaled = true
	value.Text = "0"
	-- measured against the actual pill pixels inside each PNG (the pill is
	-- NOT vertically centred in the art -- its middle sits at ~0.61 of the
	-- image height, which is why a 0.5-centred overlay rode high in the
	-- 2026-08-10 user capture)
	-- fixed box, left-anchored beside the icon (Bug A: no AutomaticSize --
	-- TextScaled in a fixed silhouette so the counter never breathes)
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.TextColor3 = Color3.new(1, 1, 1) -- polish pass: cash counts WHITE like PS99's paw/silver counts -- gold stays reserved for real money
	value.Size = UDim2.fromOffset(width - 66, 36)
	value.Position = UDim2.new(0, 62, 0.5, 0)
	value.AnchorPoint = Vector2.new(0, 0.5)
	value.ZIndex = T.zindex.currency + 2
	value:SetAttribute("NoPolish", true)
	local vs = Instance.new("UIStroke")
	vs.Thickness = 3
	vs.Color = SPEC.Outline
	vs.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	vs.LineJoinMode = Enum.LineJoinMode.Round
	vs.Parent = value
	value.Parent = c

	local popScale = Instance.new("UIScale")
	popScale.Parent = c

	return c, value, popScale
end

local coinPill, coinValueLabel, coinPop = buildCounter(1, "CoinPill", T.icons.coin, 190, false, SPEC.Hud.ValuePosCash)
--[[ ------------------------------------------------------- EMERALD COUNTER
2026-08-14, owner reference art. The gem counter is no longer
SPEC.Art.premiumCounter (the painted pill PNG) with a face laid over its left
end -- it is DRAWN from primitives, for two reasons the PNG could not give us:
the number now sits in a real inset panel instead of floating on the pill, and
the buy "+" is its OWN button with its own hover instead of the whole pill
being one click target.

The coin pill still uses buildCounter and the sheet's painted art, so the two
counters are now drawn by different means. That is deliberate for this round
and flagged to the owner, not an oversight.

Geometry is canvas px on the 70-tall counter, taken from the reference's own
ratios. The one that matters: the cluster ends exactly where the inner panel
begins, so the art overhangs the BAR but never the digits -- at the first
geometry the emerald sat on top of the leading "1" of 12,456.

Widths are fixed and there is no AutomaticSize: the value is TextScaled inside
a fixed panel, which is what keeps "7" and "1,204,880" the same silhouette
instead of the counter breathing on every tick (the Bug A lesson above). ]]
local GEM = {
	W = 246,
	BarX = 50,  BarY = 7,  BarW = 196, BarH = 56, BarR = 28,
	PanelX = 78, PanelY = 15, PanelW = 110, PanelH = 40, PanelR = 20,
	BtnX = 194, BtnY = 13, BtnS = 44, BtnR = 14,
	ClusterS = 76, ClusterX = 0, ClusterY = -3,
	Stroke = 3.5,
}
-- The inner panel's mint is the one surface the build sheet never specified
-- (it had no inset panel). A cool mint tuned for the PS99 palette that keeps
-- the counter's emerald-green identity.
local GEM_PANEL_TINT = { Color3.fromHex("DFF5E6"), Color3.fromHex("B8E6C6") }

local function gemSkin(f: GuiObject, radius: number, top: Color3, bottom: Color3, strokeW: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = f
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = 90
	g.Parent = f
	if strokeW and strokeW > 0 then
		local s = Instance.new("UIStroke")
		s.Color = SPEC.Outline -- every interactive surface wears this edge
		s.Thickness = strokeW
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.LineJoinMode = Enum.LineJoinMode.Round
		s.Parent = f
	end
end

-- The light band across the top of a glossy surface. Inset from the edges so
-- it never touches the keyline, which would read as a lighting seam.
local function gemGloss(parent: GuiObject, inset: number, heightFrac: number, radius: number, z: number)
	local g = Instance.new("Frame")
	g.Name = "Gloss"
	g.BackgroundColor3 = Color3.new(1, 1, 1)
	g.BackgroundTransparency = 0.62
	g.BorderSizePixel = 0
	g.Position = UDim2.fromOffset(inset, math.floor(inset * 0.7))
	g.Size = UDim2.new(1, -inset * 2, heightFrac, 0)
	g.ZIndex = z
	g.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = g
end

local function buildGemCounter(order: number)
	local zc = T.zindex.currency

	-- The whole counter stays a button (the sheet's premium counter was one):
	-- clicking anywhere but the "+" still goes to the shop.
	local root = Instance.new("ImageButton")
	root.Name = "GemPill"
	root.LayoutOrder = order
	root.Image = ""
	root.BackgroundTransparency = 1
	root.AutoButtonColor = false
	root.BorderSizePixel = 0
	root.Size = UDim2.fromOffset(GEM.W, SPEC.Hud.CounterH)
	root.ZIndex = zc
	root.Parent = currencyCluster

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BorderSizePixel = 0
	bar.Position = UDim2.fromOffset(GEM.BarX, GEM.BarY)
	bar.Size = UDim2.fromOffset(GEM.BarW, GEM.BarH)
	bar.ZIndex = zc + 1
	bar.BackgroundTransparency = 1 -- delta 3: the bar is a layout skeleton now, not chrome
	bar.Parent = root

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BorderSizePixel = 0
	panel.Position = UDim2.fromOffset(GEM.PanelX - GEM.BarX, GEM.PanelY - GEM.BarY)
	panel.Size = UDim2.fromOffset(GEM.PanelW, GEM.PanelH)
	panel.ZIndex = zc + 3
	panel.BackgroundTransparency = 1 -- delta 3: numeral floats bare
	panel.Parent = bar

	-- NoPolish: spec type (Shout + dark stroke), not UIPolish's GothamBold.
	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.BackgroundTransparency = 1
	value.Font = SPEC.Font.Shout
	value.TextColor3 = Color3.fromHex("7CE04A") -- PS99: emeralds count in green
	value.TextScaled = true
	value.Text = "0"
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.AnchorPoint = Vector2.new(0.5, 0.5)
	value.Position = UDim2.fromScale(0.5, 0.5)
	value.Size = UDim2.new(1, -16, 1, -8)
	value.ZIndex = zc + 4
	value:SetAttribute("NoPolish", true)
	value.Parent = panel
	local vs = Instance.new("UIStroke")
	vs.Thickness = 3
	vs.Color = SPEC.Outline
	vs.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	vs.LineJoinMode = Enum.LineJoinMode.Round
	vs.Parent = value

	local buy = Instance.new("ImageButton")
	buy.Name = "Buy"
	buy.Image = ""
	buy.AutoButtonColor = false
	buy.BorderSizePixel = 0
	buy.Position = UDim2.fromOffset(GEM.BtnX - GEM.BarX, GEM.BtnY - GEM.BarY)
	buy.Size = UDim2.fromOffset(GEM.BtnS, GEM.BtnS)
	buy.ZIndex = zc + 3
	buy.Parent = bar
	gemSkin(buy, GEM.BtnR, SPEC.Action.Go[1], SPEC.Action.Go[2], GEM.Stroke)
	gemGloss(buy, 6, 0.36, math.floor(GEM.BtnR * 0.6), zc + 4)
	do
		local slot = Instance.new("Frame")
		slot.Name = "PlusGlyph"
		slot.BackgroundTransparency = 1
		slot.AnchorPoint = Vector2.new(0.5, 0.5)
		slot.Position = UDim2.fromScale(0.5, 0.5)
		slot.Size = UDim2.fromOffset(30, 30)
		slot.ZIndex = zc + 5
		slot.Parent = buy
		if IconArt and IconArt.has("plus") then
			IconArt.draw(slot, "plus", 30, slot.ZIndex)
		else
			-- ASCII plus, not U+FF0B: the display face carries the ASCII one.
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Size = UDim2.fromScale(1, 1)
			t.Text = "+"
			t.Font = SPEC.Font.Shout
			t.TextScaled = true
			t.TextColor3 = Color3.new(1, 1, 1)
			t.ZIndex = slot.ZIndex + 1
			t:SetAttribute("NoPolish", true)
			t.Parent = slot
		end
	end

	-- Cluster LAST and above the bar, so it overhangs the pill's left end the
	-- way the reference art does. It is 76 on a 70-tall counter, so it bleeds
	-- 3px past the top and bottom -- nothing clips it, and the cluster row has
	-- the tallest element in the HUD's top-left corner anyway.
	local cluster = Instance.new("Frame")
	cluster.Name = "Cluster"
	cluster.BackgroundTransparency = 1
	cluster.Position = UDim2.fromOffset(GEM.ClusterX, GEM.ClusterY)
	cluster.Size = UDim2.fromOffset(GEM.ClusterS, GEM.ClusterS)
	cluster.ZIndex = zc + 6
	cluster.Parent = root
	if IconArt and IconArt.has("gemCluster") then
		IconArt.draw(cluster, "gemCluster", GEM.ClusterS, cluster.ZIndex)
	else
		-- falls back to the single stone, which every other gem surface uses
		glyphFallback(cluster, "emerald", 44, false)
	end

	local popScale = Instance.new("UIScale")
	popScale.Parent = root

	return root, value, popScale, buy
end

local gemPill, gemValueLabel, gemPop, gemBuy = buildGemCounter(2)

-- The counter goes where gems are bought. openPanel is a forward-declared
-- local assigned further down; by the time a click can land it exists. Both
-- the pill and the nested "+" are wired: the inner button eats clicks in its
-- own 44px box, so without this the most obvious target would do nothing.
wireClick(gemPill, "uiClick")
gemPill.MouseButton1Click:Connect(function()
	openPanel("shop")
end)
wireClick(gemBuy, "uiClick")
gemBuy.MouseButton1Click:Connect(function()
	openPanel("shop")
end)

-- Same destination, asked for from the egg shop's own BUY EMERALDS button. That
-- button lives in EggShopClient, a different LocalScript, so it hands off with a
-- PLAYER ATTRIBUTE -- the idiom the join sequence's IntroDailyDone handoff uses
-- further down this file, and for the same reason: a listener that connects late
-- still sees an attribute that was already set, so no startup race can eat it.
-- EggShopClient writes a timestamp rather than `true` so repeat presses keep
-- firing this. Guarded on a truthy read so clearing the attribute cannot open it.
player:GetAttributeChangedSignal("OpenShopRequest"):Connect(function()
	if player:GetAttribute("OpenShopRequest") then
		openPanel("shop")
	end
end)

local cash, emeralds = 0, 0
local hasCashLoaded, hasEmeraldsLoaded = false, false

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
	-- CHURN GUARD (2026-08-19). paint() runs EVERY FRAME of a count-up, but
	-- shortNumber only produces a new string a handful of times across one -- while
	-- counting through 1.20K -> 1.21K the visible text changes maybe twice. Writing
	-- .Text regardless costs a TextScaled font re-solve plus a Contextual UIStroke
	-- outline rebuild on every one of those frames, and it never stops: IncomeLoop
	-- fires CashTick every 0.35s, which is FASTER than the 0.45s count-up, so the
	-- loop is superseded and restarted forever and this label was being rewritten
	-- ~60x/sec for the entire session of any player standing on an earning plot.
	-- Compare the rendered string and write only on a real change -- the same guard
	-- ClientMain already uses on the throw button. Zero visible difference.
	local lastStr = nil
	local function paint(v)
		local s = shortNumber(math.floor(v))
		if s ~= lastStr then
			lastStr = s
			valueLabel.Text = s
		end
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
	local l = UI.label(coinPill, "", "chip", T.color.textAccentOnDark) -- gold: floats over the 3D world, not a light panel
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
local tickEmeralds = makeTicker(gemPill, gemValueLabel)         -- gem pill untouched this round

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

local function applyEmeralds(n)
	if typeof(n) ~= "number" then return end
	local prev = emeralds
	emeralds = n
	tickEmeralds(n, hasEmeraldsLoaded and n > prev)
	if hasEmeraldsLoaded and n > prev then playPop(gemPop) end
	hasEmeraldsLoaded = true
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
remotes.EmeraldUpdate.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end
	if typeof(payload.Darrels) == "number" then
		applyEmeralds(payload.Darrels)
	end
end)

-- Startup pulls, mirroring EmeraldHUDClient/EggShopClient's own join-time
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
-- EmeraldService.M.Get is `local data = PDM.Get(player); return data and
-- data.Darrels or 0`, and PlayerDataManager.Get is a plain
-- `cache[player.UserId]` lookup that stays nil until the async DataStore
-- load lands. So any pull that beats the profile load returns a PLACEHOLDER
-- {Darrels = 0}, and `typeof(res.Darrels) == "number"` is perfectly true of
-- 0 -- a "valid" result indistinguishable from this pill's own seed text,
-- which is exactly why it always looked like the pull never landed. Nothing
-- corrected it afterwards either: EmeraldService.Init's join-time push is
-- itself guarded by `if data then`, so it no-ops on the same unloaded
-- profile and EmeraldUpdate never fires at join at all.
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
		local ok, res = pcall(function() return remotes.EmeraldState:InvokeServer() end)
		if ok and typeof(res) == "table" and typeof(res.Darrels) == "number" then
			applyEmeralds(res.Darrels)
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

-- 2026-08-04 icon redesign (user handoff "Roblox game UI redesign", option
-- 3a): the rail wears the mock's frameless sticker treatment -- the EMOJI
-- GLYPH IS THE ICON, at the mock's per-icon size ladder (scaled 653->775 to
-- our canvas) and tilt, idle-bobbing with a 0.25s stagger; the Daily gift
-- wobbles instead (rotate about its base tilt -- Rotation tweens verified
-- running in this place, unlike the transparency/UIScale family). The kit
-- PNGs in T.icons and IconArt stay untouched underneath: delete a STICKER
-- entry and that slot falls straight back to the old art chain. Rebirth
-- deliberately has NO entry (user call: keep our drawn arc-over-star).
-- Every glyph below was render-proven live on a probe board this session.
-- NOTE: the mock's dark keyline is NOT achievable on colour emoji --
-- UIStroke (3px and 6px), legacy TextStroke and UIPolish are all no-ops on
-- them (probed live) -- so the glyphs ride bare with the shadow the emoji
-- art itself carries.
local STICKER = {
	bag      = { glyph = "\u{1F392}", size = 64, tilt = -5 },
	goals    = { glyph = "\u{2705}", size = 59, tilt = 4 },
	pass     = { glyph = "\u{2B50}", size = 64, tilt = 5 },
	index    = { glyph = "\u{1F4D8}", size = 62, tilt = -4 },
	daily    = { glyph = "\u{1F381}", size = 68, tilt = -6, wobble = true },
	worlds   = { glyph = "\u{1F30D}", size = 62, tilt = -4 },
	shop     = { glyph = "\u{1F6D2}", size = 60, tilt = 5 },
	settings = { glyph = "\u{2699}\u{FE0F}", size = 52, tilt = 4 },
}
local BOB_RISE = 7        -- px of idle lift (mock: 6 at reference scale)
local BOB_TIME = 1.6      -- half-cycle; full bob = 3.2s like the mock
local BOB_STAGGER = 0.25
local WOB_SWING = 3       -- degrees either side of the base tilt
local WOB_TIME = 1.3      -- half-cycle; full wobble = 2.6s

-- PLATE COLOUR PER BUTTON (2026-08-06, user reference: a saturated tile with a
-- heavy dark rim and a high-chroma icon on it). Seven identical cream plates
-- meant the rail read as one undifferentiated stack and you navigated it by
-- counting positions; a hue each makes it findable at a glance without adding
-- labels the blueprint does not want.
--
-- Each plate is picked AGAINST its icon, not for its own sake -- the icon has
-- to stay the loudest thing on the button:
--   bag is coral      -> teal      pass is purple+gold -> indigo
--   daily is off-white-> sky       goals is white+green-> orange
--   index is cyan     -> violet    settings is white   -> slate
--   rebirth is magenta+ice -> green (straight off the reference image)
-- NO DAILY TILE (2026-08-07 user decision). The calendar is not something you
-- go and find any more -- it opens BY ITSELF at join, before anything else, and
-- hands off to the offline-earnings card. See the join sequence at the foot of
-- this file. The panel itself is untouched and still registered under "daily":
-- panelModules is populated from the GameHUDPanels folder, NOT from this list,
-- so openPanel("daily") still works with no tile pointing at it.
--
-- Everything here is derived from #RAIL_ORDER (RAIL_H, layoutRail's column
-- reflow), so dropping an entry re-flows the grid on its own.
local RAIL_ORDER = {
	{ id = "bag", label = "Bag", plate = { "#34C6B0", "#12897A" } },
	-- NO SEPARATE PASS TILE (2026-08-07). The season pass is a tab inside the Goals
	-- destination now -- see GameHUDPanels.ProgressPanel, which answers to "goals"
	-- and mounts GoalsPanel and PassPanel as its two tabs.
	{ id = "goals", label = "Goals", plate = { "#FFA83D", "#E06A0C" } },
	-- NO INDEX TILE (2026-08-07). The Index is a tab inside the Bag now -- see
	-- BackpackPanel's renderIndex, which builds GameHUDPanels.IndexPanel embedded
	-- across its grid and detail columns.
	-- Worlds (2026-08-07): fast travel to anywhere you have already been on foot.
	-- Deep teal against the globe glyph, and away from Bag's lighter teal in the
	-- grid so the two do not read as a pair.
	{ id = "worlds", label = "Worlds", plate = { "#3FA9C9", "#12627E" } },
	-- Shop (2026-08-07): Robux passes and emerald packs. Roblox green, the colour
	-- players already read as "this costs Robux".
	{ id = "shop", label = "Shop", plate = { "#5BD46B", "#1F8B34" } },
	{ id = "settings", label = "Settings", plate = { "#7C8AA0", "#3E4A5E" } },
	-- 7th button (2026-08-04): Rebirth's claim cue finally has a visible
	-- home; its click path is special -- see rebirthPanel() just below.
	-- Review catch: a THIRD column would overlap open panels' left edge at
	-- true 16:9 sizes (rail is true-screen chrome, panels are scaled canvas;
	-- at 1080p the panel edge sits ~screen-x 291 while a third column spans
	-- ~234..340) -- and its invisible hit button would steal panel clicks and
	-- force-close the panel via single-open. So the grid grows DOWN instead:
	-- two columns of four, RAIL_W stays 218, zero new overlap.
	{ id = "rebirth", label = "Rebirth", plate = { "#6ED44F", "#2E8B2A" } },
}

-- Rebirth's surface is still RebirthClient's own legacy panel
-- (PlayerGui.RebirthUI.RebirthPanel, built eagerly at join) -- there is no
-- GameHUDPanels module for it. Toggling that frame's Visible is the
-- sanctioned lever: the panel sits in SideRail.registerPanel's single-open
-- registry, so opening it force-closes `host` (and vice versa), and the
-- host watcher near the bottom of this file already resyncs our bookkeeping
-- when that happens.
local function rebirthPanel()
	local ui = playerGui:FindFirstChild("RebirthUI")
	return ui and ui:FindFirstChild("RebirthPanel") or nil
end

-- USER LAYOUT (2026-07-30): two columns of three instead of one column of six,
-- filled COLUMN-FIRST -- Bag/Pass/Daily down the left, Goals/Index/Settings
-- beside them. Anchored to the TOP of the band rather than centred in it, so
-- the left column keeps the on-screen position it already had. Three rows of
-- full-size items is 306px against a ~532px band, so railScale sits back at
-- 1.0 and the icons render at the kit's intended 66px again.
-- ============================================================================
-- 2026-08-04 SIDEBAR BLUEPRINT (user's "Roblox Simulator UI Blueprint (1:1)"
-- .docx). Replaces the 2x4 grid of frameless labelled icons with the
-- blueprint's sidebar: ONE column, vertically centred on the left edge,
-- 72px plated buttons 8px apart, NO permanent labels.
--   "Sidebar Position (0.02,0.5), AnchorPoint (0,0.5), width ~80px"
--   "Button 64x64 or 72x72 ImageButton, UICorner, UIStroke 3px, UIGradient,
--    Shadow"
--   "Hover scale 1.00->1.08 (0.08s). Click 1.08->0.92->1.00"
--   "Spacing 8px between icons, all same size"
--   "Style ... no permanent labels"
-- The labels are GONE per that last line -- the icon art plus the active
-- glow, badges and claim halos carry the meaning now.
-- ============================================================================
-- USER REFERENCE (2026-08-04): the sidebar art they want is a chunky icon on
-- a CREAM plate inside a heavy near-black outline. In that reference the
-- plate is part of the PNG (which is why the blueprint says "replace only
-- the icon image") -- but the icons currently in T.icons are an older, plain,
-- plate-less set, so until the real 512px art is uploaded the plate is drawn
-- here instead, in the reference's own colours. When the new art lands:
-- swap the T.icons ids and set RAIL_PLATE_DRAWN = false, and the artwork's
-- baked plate takes over with nothing behind it.
-- 2026-08-09 HUD upgrade: the illustrated buttons carry their own plate,
-- outline and label, so the drawn plate stands down (the handoff art landed;
-- this is the exact one-flag retirement the comment above promised).
local RAIL_PLATE_DRAWN = false
local RAIL_PLATE_TOP = Color3.fromHex("#F7E7C2")   -- cream, reference plate top
local RAIL_PLATE_BOT = Color3.fromHex("#DFC28C")   -- warmer tan at the foot
local RAIL_PLATE_INK = Color3.fromHex("#171310")   -- the reference's heavy outline
local RAIL_PLATE_STROKE = 4                        -- thicker than the blueprint's 3: the reference outline is heavy
-- 2026-08-09 HUD upgrade: the six buttons are the handoff's illustrated
-- 128x146 slots (pre-scaled x0.703 onto this canvas -> 90x103), labels baked
-- into the art. Uniform slot + Fit letterboxes <=4px on the widest asset;
-- do NOT size buttons to their own aspect (README, asset pipeline).
local RAIL_BTN_W = SPEC.Hud.Slot.X
local RAIL_BTN_H = SPEC.Hud.Slot.Y
local RAIL_BTN = RAIL_BTN_W  -- narrow dimension; keeps the touch-target maths honest
local RAIL_BTN_GAP = SPEC.Hud.SlotGap
-- CAPTION ROW (2026-08-06, user reference image). The blueprint said "no
-- permanent labels" and this rail shipped without them -- but the reference the
-- user wants matched puts a chunky outlined word under every tile, and that is
-- the single biggest thing separating ours from it. A word is also what makes an
-- unfamiliar icon readable on a first visit, so it outranks the blueprint here.
--
-- It needs vertical room, so the grid now steps by a DIFFERENT amount on each
-- axis: a plate is still RAIL_BTN square and columns pack at RAIL_BTN width, but
-- a row advances by the plate plus the caption. Before this the single `step`
-- did both, and adding the caption to it would have spread the columns apart by
-- the height of the text.
-- 21 against a 70 plate is ~30%, which is the proportion the reference uses. At
-- 18 the word read as a timid footnote rather than part of the tile.
local RAIL_LABEL_H = 21
local RAIL_LABEL_LIFT = 8    -- the caption overlaps the plate's bottom edge, as in the reference
local RAIL_STEP_X = RAIL_BTN_W + RAIL_BTN_GAP
-- no caption row in the step any more: the art carries its own label plate
local RAIL_STEP_Y = RAIL_BTN_H + RAIL_BTN_GAP
-- How much of the button the artwork covers; the rest is the plate's stroke
-- and gloss showing as a border. Both icon paths below size off THIS, so the
-- drawn icons and the imported PNGs come out the same size.
local RAIL_ICON_FILL = 0.74
local RAIL_HOVER = 1.08      -- blueprint hover scale
local RAIL_PRESS = 0.92      -- blueprint click squash
local RAIL_HOVER_TIME = 0.08 -- blueprint "(0.08s)"
local RAIL_W = RAIL_BTN_W
local RAIL_H = #RAIL_ORDER * RAIL_STEP_Y - RAIL_BTN_GAP

local rail = Instance.new("Frame")
rail.Name = "NavRail"
-- blueprint: AnchorPoint (0,0.5) -- the column is centred on the screen's
-- vertical midline instead of hanging from a top clearance
rail.AnchorPoint = if RAIL_ON_LEFT then Vector2.new(0, 0.5) else Vector2.new(1, 0.5)
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
-- 2026-08-05 cross-platform: this used to be shrink-to-fit only, and on a
-- phone that degenerated completely. A single column of 7 buttons is 552
-- design px; a handset in landscape leaves a band of ~122, so the scale came
-- out at 0.22 and the rail's Hit buttons measured 10x10 SCREEN px on a
-- simulated iPhone 17 Pro -- i.e. the whole nav rail was untappable, well
-- under Roblox's 44px minimum touch target.
--
-- So it reflows into COLUMNS before it shrinks: add a column, halve the
-- height, and only scale down once the grid genuinely cannot fit. Desktop is
-- unaffected -- a tall window still resolves to one column at scale 1.
local RAIL_MIN_SCALE = 0.66

layoutRail = function()
	-- RESERVES ARE DESKTOP-SIZED AND MUST NOT APPLY ON A PHONE (2026-08-21).
	-- `chrome` ALREADY excludes the safe-area insets -- the topbar and Roblox's own
	-- touch-control band -- so subtracting another 96 + 88 design px double-counts.
	-- On a landscape handset chrome is only ~120 design px tall ((374 - 58 - 112) /
	-- 1.70), so 184 of reserve exceeded the ENTIRE available height, band clamped to
	-- 1, and the column-fitting loop below could never satisfy its fit test -- so it
	-- ran cols all the way up to #RAIL_ORDER and produced a 6-wide horizontal ROW.
	-- That is the "mobile UI is a row" report. 8px keeps the grid off the edges.
	-- Hoisted: the grid SHAPE now depends on the orientation too, not just the
	-- footprint cap further down that used to be the only reader.
	-- Platform.Viewport, not the camera: this function's whole job below is to spend
	-- a budget measured as a share of the screen, and reading the real window made
	-- those shares meaningless under a device preview. See fit().
	local vpx = Platform.Viewport
	local topClear = Platform.IsPhone and 8 or RAIL_TOP_CLEARANCE
	local botReserve = Platform.IsPhone and 8 or RAIL_BOTTOM_RESERVE
	local band = math.max(chrome.Size.Y.Offset - topClear - botReserve, 1)
	local n = #RAIL_ORDER
	local stepX, stepY = RAIL_STEP_X, RAIL_STEP_Y

	-- On touch the floor is not a taste call, it is the 44px minimum touch
	-- target expressed back in rail-scale units. Reflowing to two rows still
	-- only reached 36px on a simulated iPhone 17 Pro; solving for 44 makes the
	-- grid go as wide as it needs to (7x1 on a handset) instead of guessing at
	-- a column count.
	local minScale = RAIL_MIN_SCALE
	if Platform.IsTouch then
		-- 44 -> 45 (2026-08-27). The floor is applied as a SCALE and then multiplied
		-- back out through two more roundings before it reaches the screen, and it
		-- landed on 43px tiles at 667x375 -- one pixel under, purely from rounding.
		-- Asking for one extra pixel here is cheaper than chasing the rounding.
		local touchFloor = (HudLayout.MIN_TOUCH + 1) / (RAIL_BTN * math.max(chromeScale.Scale, 0.01))
		if Platform.IsPhone then
			-- PHONE: floor at the TRUE 44px touch minimum and nothing higher.
			-- Clamping this UP to RAIL_MIN_SCALE (0.66) was self-defeating: against the
			-- 1.70 phone chrome boost, 0.66 means 101px buttons -- more than DOUBLE the
			-- 44px requirement -- and that surplus is exactly what made the grid too big
			-- to stack, forcing it wide. The real floor here is 0.29; letting the scale
			-- reach it is what lets two columns fit at a still-comfortable ~49-54px.
			--
			-- CEILING 1 -> 1.15 (2026-09-11). The `1` here was silently defeating the
			-- line above it. Measured at 700x310: Chrome wears Block() = 0.46 (NOT
			-- Chrome() = 0.68 -- the 2026-08-27 block/type split moved it), so the 45px
			-- floor needs a rail scale of 45 / (90 * 0.46) = 1.087. Clamping to 1 gave
			-- 90 * 1.0 * 0.46 = 41px tiles -- three under Roblox's minimum -- and
			-- `math.max(s, minScale)` below then faithfully enforced a floor that had
			-- already been rounded down below the thing it exists to guarantee.
			--
			-- Scaling the 90x103 slot art above 1 is mild upscaling and is the cheaper
			-- side of the trade: the rail goes 98 -> 107px tall on that screen, i.e.
			-- 32% -> 34% of the height, against the 30% it already takes at 800x360.
			-- 1.15 bounds it so a pathological viewport cannot run the art away.
			minScale = math.min(touchFloor, 1.15)
		else
			minScale = math.clamp(touchFloor, RAIL_MIN_SCALE, 1)
		end
	end

	-- Cap the ROW count before solving for columns. The fewest-columns-that-fit
	-- rule is right on a monitor and wrong on a handset: it settled on 2x4,
	-- which measured 92x188 px = 12% of the width but 52% of the HEIGHT, i.e.
	-- the rail ate half the phone screen down the left edge.
	--
	-- 2026-08-18, MEASURED ON A LANDSCAPE PHONE (666x374, first session where the
	-- phone class actually engaged): the 1-row cure was worse than the disease.
	-- Six buttons in a row measured 312px WIDE -- reaching x=326, half the
	-- screen -- and the rail anchors on the vertical midline, so the strip ran
	-- straight through the throw bar (the game's core control) at y 147..203.
	-- 3 rows x 2 cols is the shape that fits the free left-edge column: ~96x168
	-- on that screen, clear of the centre lane AND of the bottom-left joystick.
	-- PHONE: TWO COLUMNS, FIXED (2026-08-21, owner direction -- supersedes the
	-- 2026-08-18 note above). The reflow-until-it-fits rule is right on a monitor and
	-- wrong on a handset: with the band bug above it always bottomed out at 1 row x 6
	-- and ran the icons across the screen as a strip. A fixed 2 x 3 keeps the rail a
	-- COLUMN ON THE SIDE, which is what the shape is for, and is narrow enough to stay
	-- clear of the centre lane where the throw bar lives.
	--
	-- MEASURED with the two fixes above, at the 44px touch floor:
	--   landscape 666x374 -> 102 x 177 px, 49px buttons, 15% of the width
	--   portrait  375x812 -> 112 x 194 px, 54px buttons, 30% of the width
	-- Both clear the topbar and the touch band, and both stay above 44px.
	local cols
	if Platform.IsPhone then
		-- THE GRID FOLLOWS THE ORIENTATION (2026-08-24, owner: "unplayable" +
		-- capture). Fixed at 2 since 2026-08-21, which is right in portrait and
		-- wrong in landscape: six buttons in two columns is THREE ROWS, and three
		-- rows of a 103px slot cannot be made short on a screen that is ~430px tall
		-- in total. The 44px touch floor then blocks the only remedy the old code
		-- had -- shrinking -- so the rail was pinned at half the screen height no
		-- matter what the footprint cap below asked for, and its top edge ran up
		-- into the currency counters it is supposed to sit beneath. Both of those
		-- are visible in the owner's capture.
		--
		-- Turning the grid on its side spends the axis landscape actually has: 3x2
		-- is 213 design px tall where 2x3 was 323, at the SAME button size.
		--
		-- The 2026-08-04 note above warns that a third column overlaps an open
		-- panel's left edge and its hit button steals panel clicks. That is a
		-- DESKTOP finding at 1080p, and it does not reach here: openPanel hides the
		-- rail outright on a phone (see its Platform.IsPhone branch), so on this
		-- path there is no open panel for a third column to collide with.
		cols = (vpx.X >= vpx.Y) and 3 or 2
	else
		cols = 1
		while cols < n do
			local r = math.ceil(n / cols)
			if (r * stepY - RAIL_BTN_GAP) * minScale <= band then break end
			cols += 1
		end
	end
	local rows = math.ceil(n / cols)
	local colH = rows * stepY - RAIL_BTN_GAP
	local colW = cols * stepX - RAIL_BTN_GAP

	-- THE CEILING HAS TO TRACK THE FLOOR (2026-09-11). `math.clamp(x, minScale, 1)`
	-- does not quietly prefer one bound when they cross -- it ERRORS: "max must be
	-- greater than or equal to min". The phone touch floor above can now ask for
	-- 1.087 on a 700x310 handset, so this threw, layoutRail died half-way through,
	-- and the rail was left as an un-reflowed 1x6 column of 35px tiles -- SMALLER
	-- than the 41px this set out to fix, plus a console error on every layout pass.
	-- A raised floor has to raise the ceiling with it or it cannot be honoured.
	-- Desktop and tablet are untouched: minScale is <= 1 on both, so maxScale is
	-- exactly 1 there and this line reads as it always did.
	local maxScale = math.max(1, minScale)
	local s = math.clamp(band / colH, minScale, maxScale)
	-- and cap the footprint as a share of the screen, or the raised phone chrome
	-- boost (1.70) just makes the block enormous instead of tall.
	--
	-- SHARES ARE SHAPE-AWARE (2026-08-18). One fixed pair cannot serve both
	-- shapes this rail takes: a LANDSCAPE phone has ~204px of usable height
	-- (topbar 58 + touch band 112 eat the rest), so the grid is forced into one
	-- 6-wide row and legitimately needs ~45% of the width; a PORTRAIT phone has
	-- the height for a 2x3 block, which must stay narrow so it never crosses
	-- into the centre lane where the throw bar lives. Measured the wrong way
	-- round it crushes: a 0.30 width share on the 6-wide row produced 31px
	-- buttons on a 666x374 handset.
	if Platform.IsPhone then
		local cs = math.max(chromeScale.Scale, 0.01)
		-- BUDGET THE SCARCE AXIS (2026-08-24). The old pair spent 62% of the HEIGHT
		-- on a landscape handset. It was honoured exactly -- which is the problem:
		-- 0.62 was never a budget anyone chose, it was the shape the 2x3 grid
		-- happened to want, written back as a cap. Measured on the owner's iPhone
		-- capture the rail ran from 19% to 81% of the screen down the left edge.
		--
		-- Landscape is height-poor and width-rich and portrait is the reverse, so
		-- each orientation now gets the ceiling that binds on ITS scarce axis and
		-- slack on the other. With the orientation-aware column count above, the
		-- rail lands at roughly 24% x 39% in landscape and 24% x 19% in portrait --
		-- a corner block in both, rather than a wall down one side.
		-- 0.40 -> 0.26 IN LANDSCAPE (2026-08-27). The 40% cap was written while this
		-- function was reading the real Studio window rather than the device, so it
		-- never actually bound and was never tested at the size it describes. Measured
		-- once the viewport was honest, on a real handset's 867x399: the six tiles
		-- wanted 202% of the 229px usable height, and 40% of the FULL height is still
		-- 160px of a 229px band -- 70% of everything the player has, for the nav rail
		-- alone, before the corner controls get any.
		--
		-- 26% lands the 3x2 grid at ~104px with ~54px tiles, clear of the 44px touch
		-- floor, leaving room for the corner stack and the throw lane. Portrait keeps
		-- 0.34: it has the height to spend and the width it must not.
		local landscape = vpx.X >= vpx.Y
		local wShare = landscape and 0.26 or 0.34
		local hShare = landscape and 0.26 or 0.34
		s = math.min(s, (vpx.X * wShare / cs) / colW, (vpx.Y * hShare / cs) / colH)
		-- The footprint cap must never win against the TOUCH TARGET FLOOR: it is
		-- applied with math.min, so before this line it could (and did) drive the
		-- buttons under Roblox's 44px minimum. minScale already encodes that
		-- floor in rail-scale units, and 6 buttons at 44px is ~300px on a 666px
		-- screen, so honouring it cannot overflow.
		s = math.max(s, minScale)
	end
	-- CLOSED 2026-09-11. This carried a KNOWN OPEN note saying 700x310 tiles
	-- render 41x47 and guessing that "the shortfall is in how the floor is
	-- derived ... one of those is not the number the tile ends up wearing". The
	-- derivation was right and both numbers were the live ones; the shortfall was
	-- the `math.min(touchFloor, 1)` CEILING on the phone branch above, which
	-- rounded a floor of 1.087 down to 1. See the note there. Tiles now measure
	-- 45x52 on that profile.
	railScale.Scale = s
	rail.Size = UDim2.fromOffset(colW, colH)

	-- Items are hand-placed (see the build loop's note on UIListLayout eating
	-- Position writes), so the grid is re-addressed here rather than by a
	-- layout object. Column-first, matching the original single column.
	for order, cfg in ipairs(RAIL_ORDER) do
		local entry = railItems[cfg.id]
		if entry and entry.frame then
			local c = math.floor((order - 1) / rows)
			local r = (order - 1) % rows
			entry.frame.Position = UDim2.fromOffset(c * stepX + RAIL_BTN_W / 2, r * stepY + RAIL_BTN_H / 2)
		end
	end

	-- A wide, short grid centred on the left edge reads as a floating blob, so
	-- once it has reflowed that far it goes along the BOTTOM of the safe area
	-- instead. Chrome already excludes the touch-control band, so "bottom of
	-- chrome" is above Roblox's own thumbstick and jump button.
	-- The blueprint asks for a 0.02 scale inset here, and that is what this was.
	-- But the currency cluster directly above the rail sits at a flat 18, and on
	-- a 1920 viewport 0.02 comes out at 38 -- so the coin pill started 13px to
	-- the LEFT of the icon column it visually belongs to. Two things on the same
	-- edge with two different margins is the kind of half-pixel-off that makes a
	-- HUD look unfinished, so they share HUD_EDGE_PAD now. This is not a
	-- regression on small screens: both live in `chrome`, which carries the
	-- device UIScale, so the offset tracks the viewport exactly as a scale would.
	local edgeScale = RAIL_ON_LEFT and 0 or 1
	local edgeOffset = RAIL_ON_LEFT and HUD_EDGE_PAD or -HUD_EDGE_PAD

	-- KEEP THE COLUMN OUT OF THE THUMBSTICK CORNER (2026-08-26).
	--
	-- The comment above says "Chrome already excludes the touch-control band, so
	-- 'bottom of chrome' is above Roblox's own thumbstick and jump button". That
	-- is true of the BAND and false of the CONTROL: Platform's bottom inset is a
	-- full-width strip of 112px on a phone, deliberately shorter than the ~150px
	-- square the thumbstick actually occupies in the corner, because reserving the
	-- taller figure across the whole width would cost 38% of a handset's height.
	-- This rail hugs the left edge, which is precisely where that extra 38px sits.
	-- Measured before this: the bottom two tiles of a centred column sat 28-44%
	-- under the thumbstick -- and they are BAG and SHOP, the two most-used buttons
	-- in the game.
	--
	-- Chrome-local units: chrome carries its own UIScale, and rail.Position is
	-- read in chrome's unscaled space, so the screen-space overhang is divided by
	-- that scale before it is used here.
	local si = Platform.Insets()
	local cs = (chromeScale and chromeScale.Scale > 0) and chromeScale.Scale or 1
	local overhang = math.max(Platform.TouchCorner() - si.Bottom, 0) / cs
	local chromeH = chrome.Size.Y.Offset
	local railH = colH * ((railScale and railScale.Scale > 0) and railScale.Scale or 1)

	if rows <= 2 and cols >= 3 then
		-- Bottom-anchored: lift it by the overhang directly.
		rail.AnchorPoint = Vector2.new(RAIL_ON_LEFT and 0 or 1, 1)
		rail.Position = UDim2.new(edgeScale, edgeOffset, 1, -math.round(overhang))
	else
		-- Centred, unless centring would push the bottom into the corner square, in
		-- which case sit as low as it is allowed to. Never rises above true centre.
		rail.AnchorPoint = Vector2.new(RAIL_ON_LEFT and 0 or 1, 0.5)
		local centreY = chromeH * 0.5
		local maxCentreY = chromeH - overhang - railH * 0.5
		if maxCentreY < centreY then
			rail.Position = UDim2.new(edgeScale, edgeOffset, 0,
				math.round(math.max(maxCentreY, railH * 0.5)))
		else
			rail.Position = UDim2.new(edgeScale, edgeOffset, 0.5, 0)
		end
	end
end
layoutRail()

-- Placed by hand rather than by a UIListLayout: the grid is column-first,
-- which no single FillDirection expresses, and a layout-managed child ignores
-- writes to its Position -- which had quietly been making the hover/press
-- translate below a no-op (only the scale half of it was landing).
for order, cfg in ipairs(RAIL_ORDER) do
	-- `item` is a transparent WRAPPER, centred in its slot, and every child
	-- below sizes in SCALE units -- so the blueprint's hover/press scaling can
	-- be driven by tweening this one frame's Size and the plate, shadow, icon
	-- and glow all follow it. (It cannot ride a UIScale: UIScale tweens do not
	-- run in this place -- which is why the old rail's "scale 1.03" hover was
	-- a silent no-op the whole time it shipped.)
	local item = Instance.new("Frame")
	item.Name = cfg.id .. "Item"
	item.LayoutOrder = order
	item.AnchorPoint = Vector2.new(0.5, 0.5)
	item.Position = UDim2.new(0.5, 0, 0, (order - 1) * RAIL_STEP_Y + RAIL_BTN_H / 2)
	item.Size = UDim2.fromOffset(RAIL_BTN_W, RAIL_BTN_H)
	item.BackgroundTransparency = 1
	item.ZIndex = T.zindex.rail
	item.Parent = rail

	-- blueprint "Shadow": the guide's hard offset shadow, as a scale-sized
	-- sibling INSIDE the wrapper so it scales with the hover instead of
	-- detaching from the plate (UI.hardShadow parents as an outside sibling
	-- and copies a fixed Size -- wrong for a frame whose Size is tweened)
	local plateShadow = Instance.new("Frame")
	plateShadow.Name = "PlateShadow"
	plateShadow.Size = UDim2.fromScale(1, 1)
	plateShadow.Position = UDim2.fromOffset(0, 4)
	plateShadow.BackgroundColor3 = RAIL_PLATE_INK
	plateShadow.BackgroundTransparency = 0.3
	plateShadow.BorderSizePixel = 0
	plateShadow.Visible = RAIL_PLATE_DRAWN
	plateShadow.ZIndex = item.ZIndex
	plateShadow.Parent = item
	UI.corner(plateShadow, T.radius.control)

	-- blueprint "UICorner, UIStroke 3px, UIGradient" -- the plate the icon
	-- sits on. This is the piece the 3a direction removed ("the icon IS the
	-- button") and the blueprint brings back.
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.Size = UDim2.fromScale(1, 1)
	-- cfg.plate is this button's hue (see RAIL_ORDER); cream is the fallback for
	-- any entry added without one, so a new button is never invisible.
	local plateTop = cfg.plate and Color3.fromHex(cfg.plate[1]) or RAIL_PLATE_TOP
	local plateBot = cfg.plate and Color3.fromHex(cfg.plate[2]) or RAIL_PLATE_BOT
	plate.BackgroundColor3 = plateTop
	plate.BorderSizePixel = 0
	plate.Visible = RAIL_PLATE_DRAWN
	plate.ZIndex = item.ZIndex + 1
	plate.Parent = item
	UI.corner(plate, T.radius.control)
	-- light on top -> darker at the foot, the same direction every gradient in
	-- this game runs, so the rail sits in the same light as everything else.
	UI.gradient(plate, ColorSequence.new(plateTop, plateBot))
	local plateInk = UI.stroke(plate, RAIL_PLATE_STROKE)
	plateInk.Color = RAIL_PLATE_INK
	UI.gloss(plate, T.radius.control)

	-- v2: no button plate -- the icon floats directly on the item column,
	-- top-aligned, with the label directly under it. USER (2026-07-30): and no
	-- gold tile behind the art either. The slot is now a bare transparent host;
	-- what goes in it is the kit's own icon artwork, matching captures/hud.png.
	-- The art sits INSIDE the plate now, sized in scale so it rides the hover
	-- with everything else. 0.74 leaves the plate's stroke and gloss visible
	-- as a border around the icon rather than the art running to the edge.
	local icon = Instance.new("Frame")
	icon.Name = "IconSlot"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(RAIL_ICON_FILL, RAIL_ICON_FILL)
	icon.BackgroundTransparency = 1
	icon.ZIndex = item.ZIndex + 3
	icon.Parent = item

	-- STYLE REPLACEMENT (2026-08-04, Pet-Sim guide): the emoji stickers are
	-- RETIRED. The guide's rule is a thick ink outline on every icon, and a
	-- colour emoji cannot carry one -- UIStroke (probed at 3px and 6px), the
	-- legacy TextStroke and the UIPolish sweep are all no-ops on them, so an
	-- emoji rail can never be in this style, only near it.
	-- Setting STICKER_ENABLED = false hands every slot back to the art chain
	-- below, which was never deleted: imported PNG art (T.icons, 8 ids live)
	-- wins, then UIKit.IconArt's primitive drawings (16 icons, real ink
	-- outlines -- exactly the "chunky vector icons" the guide asks for), then
	-- the emoji glyphFallback as a last resort. Flip this back to true to
	-- restore the 3a sticker look in one edit.
	local STICKER_ENABLED = false
	local sticker = STICKER_ENABLED and STICKER[cfg.id] or nil
	if sticker then
		-- redesign glyph wins over the old art chain (see STICKER above)
		local glyph = Instance.new("TextLabel")
		glyph.Name = "StickerGlyph"
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.BackgroundTransparency = 1
		glyph.Font = Enum.Font.FredokaOne
		glyph.TextSize = sticker.size
		glyph.Text = sticker.glyph
		glyph.TextColor3 = T.color.white -- colour emoji ignore this; fallback only
		glyph.Rotation = sticker.tilt
		glyph.ZIndex = icon.ZIndex + 1
		-- emoji must not be re-coloured or outlined by the game-wide UIPolish
		-- sweep (SideRail convention; strokes are no-ops on emoji anyway)
		glyph:SetAttribute("NoPolish", true)
		glyph.Parent = icon
		if sticker.wobble then
			-- rock about the base tilt, engine-driven, no per-frame Lua
			glyph.Rotation = sticker.tilt - WOB_SWING
			TweenService:Create(glyph,
				TweenInfo.new(WOB_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Rotation = sticker.tilt + WOB_SWING }):Play()
		else
			-- idle bob on the icon SLOT (never `item`: hover/press tween item
			-- Position and capture a lazy rest pose -- bobbing there would
			-- corrupt basePos). Staggered like the mock so the rail ripples.
			local slotRest = icon.Position
			task.delay(order * BOB_STAGGER, function()
				if not icon.Parent then return end
				TweenService:Create(icon,
					TweenInfo.new(BOB_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Position = slotRest - UDim2.fromOffset(0, BOB_RISE) }):Play()
			end)
		end
	else
		-- 2026-08-09 HUD upgrade: the handoff art wins over the kit PNGs, and
		-- fills the whole slot -- its plate, outline and label plate are baked
		-- into the illustration. Delete a SPEC.Art entry to fall back.
		local iconId = SPEC.Art[cfg.id] or T.icons[cfg.id]
		if iconId and iconId ~= "" then
			if SPEC.Art[cfg.id] then
				icon.Size = UDim2.fromScale(1, 1)
			end
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
			-- Draw at the SLOT's size, not T.size.railIcon. The imported-art branch
			-- above fills the slot with fromScale(1, 1) and so is always exactly
			-- right; this branch takes a pixel size, and the 66px token predates
			-- the plate -- the slot is 0.74 of a 72px button, i.e. 53. Rebirth is
			-- the one rail entry still on this path, and 66 drew it 24% bigger than
			-- its six neighbours and hanging off the bottom of its own plate.
			IconArt.draw(icon, cfg.id, RAIL_BTN * RAIL_ICON_FILL, icon.ZIndex + 1)
		else
			glyphFallback(icon, cfg.id, 40, false) -- last resort, unplated
		end
		-- rebirth keeps its drawn icon (user call) but joins the mock's motion
		-- language with the staggered bob, so one dead-still icon doesn't read
		-- as broken in a rail of live ones. NO TILT, deliberately: rotating any
		-- ancestor of IconArt's clip frames disables ClipsDescendants (probed
		-- live at 4x -- the arch's keyline+purple rings render as FULL ovals
		-- looping through the star). Review catch.
		-- The idle bob is RETIRED with the sticker era: the blueprint's motion
		-- list is hover and click only, and one lone bobbing icon in a rail of
		-- still ones reads as a glitch rather than life.
	end

	-- CAPTION, per the user's reference: chunky white word, heavy ink keyline,
	-- sitting under the plate and overlapping its bottom edge.
	--
	-- Allowed to overhang the plate's WIDTH (+26) so "Settings" is not crushed,
	-- and TextScaled with a max size so a long word shrinks to fit instead of
	-- truncating. The item frame does not clip, so the overhang renders.
	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.AnchorPoint = Vector2.new(0.5, 0)
	caption.Position = UDim2.new(0.5, 0, 1, -RAIL_LABEL_LIFT)
	caption.Size = UDim2.new(1, 26, 0, RAIL_LABEL_H)
	caption.BackgroundTransparency = 1
	caption.Font = Enum.Font.FredokaOne
	caption.TextScaled = true
	caption.TextColor3 = T.color.white
	caption.Text = cfg.label or cfg.id
	caption.ZIndex = item.ZIndex + 8
	-- our own font and our own keyline: without this the game-wide UIPolish sweep
	-- forces GothamBold and a thinner outline, which is exactly what the top tabs
	-- opt out of for the same reason
	caption:SetAttribute("NoPolish", true)
	-- 2026-08-09 HUD upgrade: the illustrated buttons carry a baked label
	-- plate, so the drawn caption stands down whenever art is present
	-- (delete the SPEC.Art entry and the caption comes straight back).
	caption.Visible = not (SPEC.Art[cfg.id] and SPEC.Art[cfg.id] ~= "")
	caption.Parent = item
	local capInk = Instance.new("UIStroke")
	capInk.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	capInk.LineJoinMode = Enum.LineJoinMode.Round
	capInk.Thickness = 3.2
	capInk.Color = RAIL_PLATE_INK
	capInk.Parent = caption
	local capFit = Instance.new("UITextSizeConstraint")
	capFit.MaxTextSize = RAIL_LABEL_H
	capFit.MinTextSize = 9
	capFit.Parent = caption

	-- Active state (kit README 3.7): "88px radial gold glow behind the
	-- icon, rgba(255,232,122,.75) centre -> transparent at 72%". Roblox's
	-- UIGradient has no radial mode, so this approximates the falloff with
	-- concentric circles (opaque centre, fading outward, capped ~72% of
	-- the radius) instead of a texture asset -- same non-native-primitive
	-- workaround convention as UI.rainbowRing above.
	local glow = Instance.new("Frame")
	glow.Name = "ActiveGlow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	-- centred on the PLATE now (scale units), not hung off the old icon-slot
	-- top edge, and sized in scale so it rides the hover with everything else.
	-- 1.5x, up from 1.2x (2026-08-17): the sticker art fills the whole button
	-- now, so a halo barely larger than the plate hid entirely behind it --
	-- "no persistent rail active state" in the field-study grade was THIS.
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromScale(1.5, 1.5)
	glow.BackgroundTransparency = 1
	glow.Visible = false
	glow.ZIndex = item.ZIndex -- behind the plate
	glow.Parent = item

	-- Rings sized against the 1.5x halo so they clear the sticker's silhouette,
	-- and GREEN (delta 7: active = green game-wide; the old gold halo also
	-- collided with gold = real money).
	local GLOW_GREEN = Color3.fromRGB(99, 222, 67)
	local GLOW_RINGS = { -- {diameter fraction of railGlow, transparency} outer -> inner
		{ 0.96, 0.84 },
		{ 0.80, 0.62 },
		{ 0.60, 0.40 },
		{ 0.38, 0.18 }, -- innermost/most opaque
	}
	for i, ringSpec in ipairs(GLOW_RINGS) do
		local d = ringSpec[1]
		local glowRing = Instance.new("Frame")
		glowRing.Name = "Ring" .. i
		glowRing.AnchorPoint = Vector2.new(0.5, 0.5)
		glowRing.Position = UDim2.fromScale(0.5, 0.5)
		glowRing.Size = UDim2.fromScale(d, d)
		glowRing.BackgroundColor3 = GLOW_GREEN
		glowRing.BackgroundTransparency = ringSpec[2]
		glowRing.BorderSizePixel = 0
		glowRing.ZIndex = glow.ZIndex
		glowRing.Parent = glow
		UI.corner(glowRing, 999) -- scale-sized now, so a pill radius keeps it round at any size
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
	-- scale units, centred on the plate, same reason as ActiveGlow above
	claimHalo.Position = UDim2.fromScale(0.5, 0.5)
	claimHalo.Size = UDim2.fromScale(1.14, 1.14)
	claimHalo.BackgroundColor3 = GLOW_GREEN -- claim = act: green (gold = real money only; matches the ActiveGlow rings above)
	claimHalo.BackgroundTransparency = 0.35
	claimHalo.BorderSizePixel = 0
	claimHalo.Visible = false
	claimHalo.ZIndex = item.ZIndex -- behind the plate, beside ActiveGlow
	claimHalo.Parent = item
	UI.corner(claimHalo, 999)

	-- Hit target: invisible button over the whole plate. 72px is well clear of
	-- the 44px minimum touch target on its own now that the label is gone.
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.ZIndex = item.ZIndex + 10
	hit.Parent = item
	wireClick(hit, "uiClick")

	-- blueprint motion: "Hover scale 1.00->1.08 (0.08s). Click 1.08->0.92->
	-- 1.00". Driven on the wrapper's SIZE, never a UIScale -- UIScale tweens
	-- do not run in this place, which is exactly why the rail's previous
	-- "scale 1.03" hover never actually scaled anything. AnchorPoint is
	-- (0.5,0.5), so Size alone grows the button about its own centre with no
	-- position compensation.
	local REST_SIZE = UDim2.fromOffset(RAIL_BTN_W, RAIL_BTN_H)
	local function sizeAt(mult)
		return UDim2.fromOffset(math.round(RAIL_BTN_W * mult), math.round(RAIL_BTN_H * mult))
	end
	local HOVER_INFO = TweenInfo.new(RAIL_HOVER_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local hovering = false

	hit.MouseEnter:Connect(function()
		hovering = true
		TweenService:Create(item, HOVER_INFO, { Size = sizeAt(RAIL_HOVER) }):Play()
	end)
	hit.MouseLeave:Connect(function()
		hovering = false
		TweenService:Create(item, HOVER_INFO, { Size = REST_SIZE }):Play()
	end)
	hit.MouseButton1Down:Connect(function()
		TweenService:Create(item, HOVER_INFO, { Size = sizeAt(RAIL_PRESS) }):Play()
	end)
	hit.MouseButton1Up:Connect(function()
		-- release settles to whichever state the cursor is actually in, so a
		-- click that drags off the button does not leave it stuck enlarged
		TweenService:Create(item, HOVER_INFO,
			{ Size = hovering and sizeAt(RAIL_HOVER) or REST_SIZE }):Play()
	end)
	hit.MouseButton1Click:Connect(function()
		if cfg.id == "rebirth" then
			-- legacy panel, not an openPanel id -- see rebirthPanel() above
			local panel = rebirthPanel()
			if panel then panel.Visible = not panel.Visible end
			return
		end
		if currentPanelId == cfg.id then
			closePanel()
		else
			openPanel(cfg.id)
		end
	end)

	railItems[cfg.id] = { frame = item, glow = glow, claim = claimHalo }
	-- re-address the grid now this item exists: the first layoutRail() ran
	-- before any of them were built
	layoutRail()
end

-- U3 port: these rail buttons are the claim surface now -- the legacy
-- LeftRail this used to happen on is hidden permanently further down this
-- file. SideRail's central arbitration (priority table + PULSE_MAX cap)
-- still decides WHO pulses; it just paints onto these halos. Rebirth joined
-- the map when it got its own rail button (2026-08-04). Type-guarded so an
-- older SideRail (two sessions edit this place) can never hard-error the
-- HUD build.
-- "Daily" is deliberately absent: there is no daily tile to paint a claim halo
-- or a badge onto any more (see RAIL_ORDER). Both loops below already skip an id
-- with no railItems entry, so leaving it in would have been harmless -- but it
-- would have read as a bug rather than a decision.
local CLAIM_SOURCE = { goals = "Goals", pass = "Season", rebirth = "Rebirth" }
if type(SideRail.attachClaimSurface) == "function" then
	for id, tileName in pairs(CLAIM_SOURCE) do
		local entry = railItems[id]
		if entry and entry.claim then
			SideRail.attachClaimSurface(tileName, entry.claim)
		end
	end
end

-- One renderer for every badge kind on the rail. "count" is the v2 kit badge
-- (red, numeric); "dot" is the smaller red one that says only "there is
-- something here"; "alert" is the gold one the legacy tiles used for Rebirth. ctx.setBadge keeps its
-- numeric contract through the setBadge wrapper further down; SideRail's
-- reporters arrive here with their kind intact via attachBadgeSurface --
-- which also closes a real gap: the pass badge used to be absent until the
-- pass panel's FIRST open (PassPanel.Build is lazy), while SeasonClient
-- pushes the same claimable count from join+1s.
local BADGE_GOLD = ColorSequence.new(Color3.fromHex("#FFE87A"), Color3.fromHex("#E8930F"))
local function paintBadge(id, kind, n)
	local item = railItems[id]
	if not item then return end
	if kind == "none" or (kind == "count" and (not n or n <= 0)) then
		if railBadges[id] then
			railBadges[id]:Destroy()
			railBadges[id] = nil
		end
		return
	end
	-- EVERY NON-NUMERIC BADGE IS A "!" (2026-08-09, owner's call). "dot" used to be
	-- a bare disc with no glyph in it, which on a rail this busy was easy to read as
	-- part of the button art rather than as something waiting to be claimed. Size and
	-- colour still separate the two kinds -- dot is small and red, alert is large and
	-- gold -- so nothing is lost by giving them the same mark.
	local text = (kind == "count") and ((n > 99) and "99+" or tostring(n)) or "!"
	local b = railBadges[id]
	-- a kind flip rebuilds; only same-kind updates retarget the label
	if b and b:GetAttribute("BadgeKind") ~= kind then
		b:Destroy()
		b = nil
		railBadges[id] = nil
	end
	if b then
		local label = b:FindFirstChild("Value")
		if label then label.Text = text end
		return
	end
	-- v2 (kit README 3.7): min-width 34, height 34, stroke 4, hard
	-- shadow 0 3, value 19, at top -6 / right 12 relative to the item
	-- column -- UI.badge ships the v1 defaults (30/30, stroke 3.5, no
	-- shadow, text 16), overridden here rather than in the shared builder.
	-- 24, up from the 18 it was as an empty disc: a "!" inside 18px with the kit's
	-- 3px rim on it is a smudge. Still clearly the junior badge next to the 34s.
	local d = (kind == "dot") and 24 or 34
	b = UI.badge(item.frame, text)
	b:SetAttribute("BadgeKind", kind)
	b.Size = UDim2.fromOffset(0, d)
	local sizeConstraint = b:FindFirstChildOfClass("UISizeConstraint")
	if sizeConstraint then sizeConstraint.MinSize = Vector2.new(d, d) end
	local badgeStroke = b:FindFirstChildOfClass("UIStroke")
	if badgeStroke then badgeStroke.Thickness = (kind == "dot") and 3 or 4 end
	local valueLabel = b:FindFirstChild("Value")
	if valueLabel then valueLabel.TextSize = (kind == "dot") and 17 or 19 end
	if kind == "alert" then
		-- gold, matching the legacy tile's alert and the kit's coin golds
		local grad = b:FindFirstChildOfClass("UIGradient")
		if grad then grad.Color = BADGE_GOLD
		else b.BackgroundColor3 = Color3.fromHex("#F5B62E") end
	end
	b.AnchorPoint = Vector2.new(1, 0)
	b.Position = UDim2.new(1, -12, 0, -6)
	b.ZIndex = T.zindex.rail + 15
	-- (no UI.hardShadow: the badge is AutomaticSize.X with an offset-0 Size,
	-- and hardShadow copies that Size literally -- the shadow rendered 0px
	-- wide, i.e. never. Pre-existing; the kit's "hard shadow 0 3" spec needs
	-- a sizing fix in Builders first. Dropping the dead call stops orphaning
	-- one invisible frame per badge. Review catch.)
	railBadges[id] = b
end

if type(SideRail.attachBadgeSurface) == "function" then
	for id, tileName in pairs(CLAIM_SOURCE) do
		if railItems[id] then
			SideRail.attachBadgeSurface(tileName, function(kind, n)
				paintBadge(id, kind, n)
			end)
		end
	end
end

---------------------------------------------------------------- panel control
local function updateActiveGlow()
	local rb = rebirthPanel()
	for id, item in pairs(railItems) do
		if id == "rebirth" then
			-- rebirth's open state lives on the legacy panel, not currentPanelId
			item.glow.Visible = (rb ~= nil and rb.Visible)
		else
			item.glow.Visible = (id == currentPanelId)
		end
	end
end

-- The legacy panel opens/closes outside openPanel/closePanel, so the rebirth
-- glow rides the panel's own Visible signal instead.
task.spawn(function()
	local ui = playerGui:WaitForChild("RebirthUI", 10)
	local panel = ui and ui:WaitForChild("RebirthPanel", 5)
	if not panel then return end
	panel:GetPropertyChangedSignal("Visible"):Connect(updateActiveGlow)
	updateActiveGlow()
end)

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

-- PS99 restyle (2026-08-16): hand-lerped panel glide on RenderStepped, the
-- same render-throttle-safe pattern CatchCinematic.PostFX uses. TweenService
-- entrances on the panel wrapper proved unreliable here (probed live: the
-- glide completed instantly on real opens while the identical tween glided
-- from a probe), so the entrance owns the property frame-by-frame instead --
-- pure math via TweenService:GetValue, gen-guarded, first-paint aware.
local function glidePanel(fr, from, to, info, gen, waitFirstPaint)
	fr.Position = from
	task.spawn(function()
		local RS = game:GetService("RunService")
		if waitFirstPaint then
			-- let the (possibly heavy) first paint land before the clock starts,
			-- or a 200ms build/paint frame eats the whole glide
			RS.RenderStepped:Wait()
			if closeGen ~= gen or not fr.Visible then return end
		end
		local t0 = os.clock()
		while true do
			RS.RenderStepped:Wait()
			if closeGen ~= gen then return end
			local a = math.clamp((os.clock() - t0) / info.Time, 0, 1)
			fr.Position = from:Lerp(to, TweenService:GetValue(a, info.EasingStyle, info.EasingDirection))
			if a >= 1 then return end
		end
	end)
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
	--
	-- Review catch (2026-08-04, panel-restyle round): hide EVERY other panel
	-- unconditionally, not just panelInstances[currentPanelId]. closePanel
	-- nils currentPanelId synchronously and DEFERS its wrapper hide behind
	-- closeGen; an openPanel within that 0.12s window bumps closeGen (killing
	-- the deferred hide) while this branch used to skip (currentPanelId
	-- already nil) -- stranding the previous wrapper Visible=true forever:
	-- panels stacked, and DailyPanel's backdrop blur + countdown never tore
	-- down (their teardown rides wrapper.Visible). Iterating everything is
	-- idempotent and closes the race whatever the bookkeeping says.
	for otherId, inst in pairs(panelInstances) do
		if otherId ~= id and inst.Visible then
			inst.Visible = false
		end
	end
	if placeholderForId and placeholderForId ~= id then
		destroyPlaceholder()
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

	-- Refit the host to THIS panel's design box, before it is shown and only when
	-- the box actually changes -- so opening any of the six 960-floor panels back
	-- to back costs nothing and cannot perturb a scale that is already correct.
	--
	-- No visible jump: the outgoing panel was hidden a few lines up, in this same
	-- resumption, so the scale moves while nothing is on screen wearing the old
	-- one. Deliberately NOT reset by closePanel -- that tweens the outgoing panel
	-- out over T.tween.panelClose.Time, and refitting underneath it mid-tween is
	-- exactly the jump this avoids on open.
	local screenName = ID_TO_SCREEN[id] or id
	local fitW = math.max(PANEL_FIT_FLOOR_W, T.size.panelWidth[screenName] or 0)
	local fitH = math.max(PANEL_FIT_H, (T.size.panelHeight or {})[screenName] or 0)
	if fitW ~= panelFitW or fitH ~= panelFitH then
		panelFitW = fitW
		panelFitH = fitH
		fit()
	end

	currentPanelId = id
	-- FIX (2026-08-21): mirrored onto an attribute so LocalScripts outside
	-- this closure (ClientMain's sell-stall Heartbeat) can cheaply read
	-- "is a panel open, and which" without a BindableEvent round trip. Set
	-- here and cleared everywhere currentPanelId is cleared below, so it can
	-- never disagree with the variable it mirrors.
	player:SetAttribute("HudOpenPanel", id)
	state.screen = ID_TO_SCREEN[id] or id
	host.Visible = true

	-- PHONE (2026-08-17 device-sim finding): at handheld sizes the rail row
	-- physically overlaps the panel AND draws over it -- it buried Settings'
	-- whole GRAPHICS row on an iPhone 7 viewport. Panels are modal at that
	-- size, so the rail stands down while one is open. Desktop keeps the
	-- rail's click-to-switch behaviour: no overlap there, nothing changes.
	-- (HudToggleClient's fold driver only asserts Visible while folded or
	-- mid-slide, so this coexists with it -- same contract SideRail uses.)
	if Platform.IsPhone then
		rail.Visible = false
		-- and the counters too (2026-08-19): a phone panel is a near-fullscreen
		-- modal, so the top-left cluster would sit ON it. Hiding it is what lets
		-- fit() drop the counter-band reserve and run panels 61% larger. The
		-- 2026-08-05 "cluster stays visible" rule was a DESKTOP call (there it
		-- sits in a gutter beside the panel, which is genuinely useful when you
		-- are reading a price) -- it still holds off-phone. closePanel restores
		-- the cluster unconditionally, so nothing can strand it hidden.
		currencyCluster.Visible = false
	end

	frame.Visible = true
	-- PS99 restyle (2026-08-16): the old pop tweened a UIScale, and UIScale
	-- tweens are a PROVEN silent no-op in this place (see the TweenService
	-- gotcha) -- panels have been snapping open with zero drawn frames. Animate
	-- Position instead: a 26px rise on the proven GuiObject tween path. The
	-- frame's rest position is captured once into an attribute so close/reopen
	-- always returns to the authored spot.
	local scale = frame:FindFirstChildOfClass("UIScale")
	if scale then scale.Scale = 1 end -- retire the old mechanism; never strand 0.92
	local rest = frame:GetAttribute("RestPosition")
	if rest == nil then
		rest = frame.Position
		frame:SetAttribute("RestPosition", rest)
	end
	glidePanel(frame, rest + UDim2.fromOffset(0, 26), rest, T.tween.panelOpen, closeGen, true)

	-- blur-never-dim: the world softens, it does not go dark
	setPanelBlur(true)

	updateActiveGlow()
end

-- EXTERNAL OPEN HOOK. Panels are normally opened by their rail tile, but the
-- sell counter is opened by a ProximityPrompt in ClientMain, which cannot see
-- this local. An attribute rather than a BindableEvent for the reason recorded
-- at the join sequence below: a late listener still sees a value already set.
-- Cleared immediately so the same id can be requested twice in a row.
player:GetAttributeChangedSignal("HudPanelRequest"):Connect(function()
	local id = player:GetAttribute("HudPanelRequest")
	if type(id) ~= "string" or id == "" then return end
	player:SetAttribute("HudPanelRequest", "")
	openPanel(id)
end)

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
	player:SetAttribute("HudOpenPanel", nil)
	state.screen = "none"
	currencyCluster.Visible = true
	if Platform.IsPhone then
		rail.Visible = true -- the fold driver re-asserts hidden if the HUD is folded
	end
	updateActiveGlow()

	if frame then
		-- PS99 restyle: Position drop-away instead of the inert UIScale shrink
		local rest = frame:GetAttribute("RestPosition")
		if rest then
			glidePanel(frame, rest, rest + UDim2.fromOffset(0, 18), T.tween.panelClose, closeGen, false)
		end
	end

	-- FIX F3 (2026-07-30 fix wave): this callback used to run unconditionally,
	-- so a close->reopen within panelClose.Time (e.g. a rail double-click) hid
	-- the freshly reopened panel out from under the player -- openPanel bumps
	-- closeGen too, so myCloseGen goes stale the instant any open/close call
	-- happens after this one, and the callback no-ops instead of touching
	-- state that no longer belongs to it.
	task.delay(T.tween.panelClose.Time, function()
		if myCloseGen ~= closeGen then return end
		if frame then
			frame.Visible = false
			-- reset so the next open's rise starts from the authored spot
			local rest = frame:GetAttribute("RestPosition")
			if rest then frame.Position = rest end
		end
		if placeholderForId == id then
			destroyPlaceholder()
		end
		if not currentPanelId then
			setPanelBlur(false)
			host.Visible = false
		end
	end)
end

-- EXTERNAL CLOSE HOOK. ClientMain's stall-distance Heartbeat (SellStall /
-- TundraSellStall / GardensSellStall) can't see this local either, so it
-- asks via the same attribute idiom HudPanelRequest uses above. Gated on
-- currentPanelId: ClientMain can only ever close the sell panel it opened,
-- never the Bag, Goals, or anything else the player opened deliberately.
-- Goes through closePanel() itself (not a raw Visible flip) so the scrim,
-- blur, and currentPanelId teardown all still run -- a hidden-but-not-closed
-- panel would strand the HUD blur.
player:GetAttributeChangedSignal("HudPanelCloseRequest"):Connect(function()
	local id = player:GetAttribute("HudPanelCloseRequest")
	if type(id) ~= "string" or id == "" then return end
	player:SetAttribute("HudPanelCloseRequest", "")
	if currentPanelId == id then
		closePanel()
	end
end)

function setBadge(id, n)
	-- ctx contract unchanged (numeric): panels keep calling this. Kind-aware
	-- paints from SideRail's reporters reach paintBadge directly via
	-- attachBadgeSurface; both paths share the one renderer above the
	-- panel-control section.
	paintBadge(id, (n and n > 0) and "count" or "none", n)
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

---------------------------------------------------------------- ESC / B
-- B is the console equivalent of ESC, and without it a controller player could
-- open a panel and have no way out of it except finding the X button with the
-- selection highlight -- which is a dead end the moment a panel opens with
-- nothing selected. Same handler, so the two can never drift apart.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
		-- the rebirth surface is a legacy panel outside closePanel's world;
		-- without this, ESC would ignore it (RebirthClient never wired ESC)
		local rb = rebirthPanel()
		if rb and rb.Visible then
			rb.Visible = false
			return
		end
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
	player:SetAttribute("HudOpenPanel", nil)
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
retireAsync(playerGui, "EmeraldHUD")

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

---------------------------------------------------------------- join sequence
-- THE DAILY CALENDAR IS THE FIRST THING A PLAYER SEES (2026-08-07 user
-- decision). Its rail tile is gone; the panel opens by itself at join and then
-- hands off to the "while you were away" card. The ORDER is the whole point:
-- reward first, payout second.
--
-- The two halves live in different LocalScripts, so the handoff is a PLAYER
-- ATTRIBUTE rather than a BindableEvent -- a listener that connects late still
-- sees an attribute that was already set, so the two scripts cannot lose the
-- handoff to a startup race.
--
-- NOTHING IS AT RISK IN THE DELAY. OfflineEarningsHandler.OnJoin has ALREADY
-- credited the offline cash (PlayerDataManager.AddEarnings) and parked only the
-- popup PAYLOAD; the remote OfflineEarningsClient fires merely asks for that
-- receipt. A player who never sees the card still has the money.
local INTRO_ATTR = "IntroDailyDone"

-- How long the claim's own motion needs before the panel is taken away:
-- DailyPanel's scrim -> check -> flying coin chain runs ~720ms, plus a beat to
-- actually read the card flipping to CLAIMED.
local CLAIM_HOLD = 1.6

local introOpened = false
local sequenceOver = false   -- we are finished with the calendar
local handoffDone = false    -- the payout card has been let through
local dailyClaimable = false

-- Lets OfflineEarningsClient go. DELIBERATELY SEPARATE from sequenceOver: the
-- timeout below has to release the payout card without also standing the
-- calendar down, or a player who sits reading the week for half a minute would
-- lose the claim's auto-advance and be left closing the panel by hand.
local function releaseHandoff()
	if handoffDone then return end
	handoffDone = true
	player:SetAttribute(INTRO_ATTR, true)
end

local function endSequence()
	sequenceOver = true
	releaseHandoff()
end

-- Safety net: if the profile never loads, DailyState never arrives and this
-- block would hold the handoff forever, so the payout card would never show.
-- OfflineEarningsClient carries its own timeout as well -- belt and braces,
-- because silently swallowing a player's payout receipt is not acceptable.
task.delay(30, releaseHandoff)

remotes.DailyState.OnClientEvent:Connect(function(s)
	if typeof(s) ~= "table" then return end
	dailyClaimable = (s.Claimable == true)
	if sequenceOver then return end

	if not introOpened then
		-- The join-time push. Nothing to claim today (a same-day rejoin) means no
		-- panel at all: a popup you cannot act on, on every single rejoin, is
		-- friction rather than a reward.
		if not dailyClaimable then
			endSequence()
			return
		end
		introOpened = true
		openPanel("daily")

		task.spawn(function()
			-- Give openPanel a moment to commit currentPanelId before watching for
			-- it to clear, or the first read would look like "already closed".
			-- Bounded, so a panel that never opens still falls through to the
			-- claim below rather than hanging the sequence.
			for _ = 1, 20 do
				if currentPanelId == "daily" then break end
				task.wait(0.05)
			end
			-- ANY route out counts: claimed, closed by hand, or SideRail's
			-- single-open taking the surface for something else.
			while currentPanelId == "daily" do
				task.wait(0.1)
			end

			-- AUTO-CLAIM ON DISMISS (user decision). With the rail tile gone the
			-- calendar has no second entrance, so closing it unclaimed would
			-- forfeit the day -- and the streak -- until the next rejoin. Claim it
			-- for them instead. dailyClaimable is still true only if no claim
			-- landed, so the claim path below cannot double-fire through here.
			if dailyClaimable then
				local claimRemote = remotes:FindFirstChild("DailyClaim")
				if claimRemote then claimRemote:FireServer() end
			end
			endSequence()
		end)
		return
	end

	-- A later push while the calendar is still up is the claim landing. Let the
	-- coin finish flying, then move the player on to the payout card. The watcher
	-- above sees the close and does the handoff.
	if s.JustClaimed then
		task.delay(CLAIM_HOLD, function()
			if currentPanelId == "daily" then closePanel() end
		end)
	end
end)
