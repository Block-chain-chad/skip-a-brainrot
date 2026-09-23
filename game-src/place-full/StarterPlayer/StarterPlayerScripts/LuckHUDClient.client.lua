-- Transparent Luck HUD: shows your total luck; tap to expand the source breakdown
-- + which rarities your current setup can reach at full power.
--
-- No longer literally always-on: on PHONE the chip stands down while a GameHUD
-- panel is open, because those panels are now near-fullscreen modals. See the
-- PanelHost watch below. Desktop and console are unchanged.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local modules = ReplicatedStorage:WaitForChild("Modules")
local WorldProgression = require(modules:WaitForChild("WorldProgression"))
local RarityConfig = require(modules:WaitForChild("RarityConfig"))
local UpgradeConfig = require(modules:WaitForChild("UpgradeConfig"))
local RebirthConfig = require(modules:WaitForChild("RebirthConfig"))
local OfferingConfig = require(modules:WaitForChild("OfferingConfig"))
local BrainrotConfig = require(modules:WaitForChild("BrainrotConfig"))
local PetConfig = require(modules:WaitForChild("PetConfig"))
local RarityCurve = require(modules:WaitForChild("RarityCurve"))
local WheelConfig = require(modules:WaitForChild("WheelConfig"))
local UITheme = require(modules:WaitForChild("UITheme"))
local P = UITheme.Palette
local CF = UITheme.Camp

-- every world's rocks: an equipped tundra rock has to show its real luck here, not
-- fall through to Pebble because this only indexed the valley ladder
local rockById = {}
for _, rock in ipairs(WorldProgression.AllRocks()) do rockById[rock.Id] = rock end

-- TWO DIFFERENT THINGS ARE CALLED "PETS" IN THIS GAME, and conflating them is how
-- this panel starts lying:
--   * BELOW: BRAINROTS PLACED ON YOUR BASE that carry BrainrotConfig.LuckMult. These
--     feed RARITY luck. Rendered as the "Brainrots on base" row.
--   * SEPARATELY: EQUIPPED EGG PETS (PetConfig / data.PetSlots), hatched at the egg
--     stall. These feed MUTATION luck, via PetHandler.LuckMult on the server. They
--     were missing from this panel entirely, so once pets went live the MUTATION LUCK
--     figure under-reported reality by the whole pet multiplier. Now read through the
--     shared PetConfig.StackedMult, which is the same function the server calls.
local petLuckByName = {}
for _, e in ipairs(BrainrotConfig) do
	if e.LuckMult then petLuckByName[e.Name] = e.LuckMult end
end

local state = { EquippedRock = "Pebble", Upgrades = {}, Rebirths = 0, Offerings = 0, Brainrots = {}, Pets = {}, PetSlots = {}, Boosts = {} }

-- =====================================================================
-- LUCK IS ADDITIVE, and it is TWO SEPARATE SYSTEMS (ServerScriptService.Modules.ThrowHandler).
-- Every source contributes a BONUS (its multiplier minus 1); the bonuses SUM onto a base of
-- 1 instead of multiplying against each other. This panel mirrors that sum exactly -- each
-- row is the amount a source ADDS, and the headline is 1 + all of them.
--
--   RARITY luck  -- shifts WHICH BRAINROT you catch.
--     accessLuck = 1 + (rock-1) + (charm-1) + (offerings-1) + (wheel-1) + Sum(placed pets-1)
--     then + a flat weather event bonus that is the SAME for every player, and perfect
--     x1.075 as a per-throw multiplier on the total. Distance UNLOCKS higher tiers;
--     accessLuck shifts the RarityCurve toward the top. Nothing is guaranteed.
--     REBIRTH LUCK IS NOT IN THIS.
--
--   MUTATION luck -- decides whether it comes out Golden / Diamond.
--     boost = 1 + (rebirth-1) + (equipped pets-1) + weather-event mutation bonus,
--     passed straight into Mutations.Roll(boost, weatherName). No x6 clamp any more --
--     additive stacking is self-limiting, so the old ceiling is gone.
--
-- Rebirth luck lives in the SECOND system, not the first: showing it next to the rock
-- would tell a player their rebirths buy tier access; they do not.
-- =====================================================================

-- Mirrors of ThrowHandler's constants. Duplicated rather than shared because a
-- LocalScript cannot require ServerScriptService -- if ThrowHandler retunes these,
-- this panel starts lying, so they are listed together and named identically.
local PERFECT_DISTANCE_MULT = 1.1
local PERFECT_LUCK_MULT = 1.075
local MAX_TOTAL_DISTANCE = 900
local PROMO_DIVISOR = 4.0     -- promoChance = clamp((accessLuck - 1) / this, 0, cap)
local PROMO_MAX = 0.90
local PROMO_DECAY = 0.45      -- each further promotion is this much likelier to fail
local MAX_PROMOTIONS = 3

-- same descending scan as RarityRoll.TierIndexForDistance: the HIGHEST tier whose
-- MinDistance your raw throw clears. (Kept as a scan, not a table, so a retuned
-- RarityConfig needs no change here.)
local function tierIndexForDistance(distance)
	for i = #RarityConfig, 1, -1 do
		if distance >= RarityConfig[i].MinDistance then return i end
	end
	return 1
end

local gui = Instance.new("ScreenGui")
gui.Name = "LuckHUD"
gui.ResetOnSpawn = false
gui.DisplayOrder = 7
gui.Parent = player:WaitForChild("PlayerGui")

-- collapsed chip (bottom-right, above the sprint button)
-- 2026-08-18 DE-PLATE (house grammar): the luck readout is PASSIVE INFO, and
-- passive info is naked bubble text -- no plate, no gradient, no keyline. The
-- green sticker skin from the 2026-08-17 corner-cluster pass made this read
-- as a button promising an action, when all a tap does is expand a breakdown.
-- The TextButton itself stays -- same name, size and click wiring -- as an
-- invisible hit target behind the text (HudToggle's HIDE UI also reads this
-- chip's AbsolutePosition/AbsoluteSize, so the frame keeps its footprint).
local chip = Instance.new("TextButton")
chip.Name = "LuckChip"
chip.AnchorPoint = Vector2.new(1, 1)
-- Margin and width still MATCH THE SPRINT BUTTON below (ClientMain: 16 from
-- the right, 138 wide), so the naked text right-aligns with the corner
-- cluster and the HIDE UI width-copy stays cluster-wide.
chip.Position = UDim2.new(1, -16, 1, -78)
chip.Size = UDim2.new(0, 138, 0, 34)
chip.BackgroundTransparency = 1     -- naked text: the child label is the whole visual
chip.BorderSizePixel = 0
chip.Text = ""                      -- the text lives in a CHILD label; see below
chip.AutoButtonColor = false        -- nothing left to tint on a transparent body
chip.Parent = gui
-- UIPolish force-whitens/restyles unexempted labels; this text is already at
-- the naked-bubble spec, so opt out here (the attribute covers the child label).
chip:SetAttribute("NoPolish", true)

-- The text stays in a CHILD label rather than chip.Text: the button is the
-- transparent hit target, the label is the visual. (The split originally
-- dodged the UIGradient-tints-glyphs trap; the gradient is gone, but the
-- split still keeps hit box and paint surface independent.)
local chipLabel = Instance.new("TextLabel")
chipLabel.Name = "Label"
chipLabel.Size = UDim2.fromScale(1, 1)
chipLabel.BackgroundTransparency = 1
chipLabel.Font = Enum.Font.FredokaOne   -- the house bubble face for naked HUD text
chipLabel.TextSize = 15
chipLabel.TextColor3 = P.text
chipLabel.Text = "\u{1F340} Luck \u{00D7}1.00"
chipLabel.ZIndex = (chip.ZIndex or 1) + 1
chipLabel.Parent = chip
do -- naked text floats over the world, so it carries the house navy glyph stroke
	local gs = Instance.new("UIStroke")
	gs.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	gs.Color = Color3.fromRGB(49, 61, 79)   -- dark navy #313D4F, the passive-info stroke
	gs.Thickness = 2
	gs.Parent = chipLabel
end

-- 2026-08-05 cross-platform: this chip was authored at a fixed 128x34 with 15px
-- text and no viewport handling, so it rendered at 15px on a 361-tall phone --
-- one of the elements called out as unreadable. Scaled up on the two devices
-- that need it (phone held at arm's length, console read from a sofa) and left
-- exactly as-is on desktop and tablet. Anchored bottom-right, so it grows into
-- the corner rather than across the screen.
local Platform = require(modules:WaitForChild("Platform"))
local HudLayout = require(modules:WaitForChild("HudLayout"))

-- HUDLAYOUT OWNS THIS CHIP'S POSITION (2026-08-26). Everything the code below
-- used to do to place it -- measure ClientMain's sprint button, dodge the jump
-- corner, re-seat on every Platform pass -- is a stack's job, and doing it here
-- is what made the bottom-right corner unfixable: ScooterButtonClient carried a
-- hardcoded copy of this chip's margin (LUCK_BOTTOM = 78) and HudToggleClient
-- re-derived its rect every frame, so moving it moved two other widgets by
-- side effect and any correction to those was overwritten on the next pass.
-- They now all declare a slot in the same BottomRight stack and none of them
-- reads the others.
HudLayout.PrepareGui(gui, "HUD")
local luckSlot = HudLayout.Attach(chip, {
	stack = "BottomRight",
	order = HudLayout.Order.Luck,
})

local chipScale = Instance.new("UIScale")
chipScale.Name = "DeviceScale"
chipScale.Parent = chip

-- === touch repositioning =============================================
-- On touch devices Roblox draws the core JUMP button in the bottom-right
-- corner (roughly the bottom-right 130x130px on phones) -- right under this
-- chip's authored desktop spot. On touch the chip re-anchors so its bottom
-- edge sits above the TOP of the sprint button (ClientMain's, lives in
-- MainUI -- read-only from here) or above the jump zone, whichever is
-- higher: it stacks clear of both wherever the corner cluster ends up.
-- HudToggle's HIDE UI positions itself off this chip's AbsolutePosition, so
-- it rides up with the chip for free. Desktop and console keep the authored
-- position exactly.
local DESKTOP_POS = chip.Position
local JUMP_ZONE = 130    -- px the core jump control claims from the bottom edge
local CLUSTER_GAP = 8    -- breathing room between the chip and what is below it
local sprintButton = nil -- resolved async below; nil until MainUI exists

local function repositionChip()
	-- LEGACY PATH. With HUD_LAYOUT_V2 on, the stack has already placed this chip
	-- and writing here would reintroduce exactly the race this migration removed.
	if luckSlot then return end
	if not Platform.IsTouch then
		-- CONSOLE TITLE-SAFE (2026-08-21). The note above used to end "Desktop and
		-- console keep the authored position exactly" -- and that is the bug: the
		-- authored spot is 16px from the right edge, while a TV does not draw the
		-- outer ~3.5%. Measured on the Console layout, this chip ran to x=1904 on a
		-- 1920 screen, 51px outside the title-safe box, and it took TWO more widgets
		-- with it -- HudToggleClient anchors the HIDE UI pill to this chip's live
		-- AbsolutePosition (its uiTarget), and the pill carries its own shadow.
		--
		-- IT HAS TO BE FIXED HERE. PlatformClient's TV-safe nudge cannot rescue any
		-- of the three: this script rewrites Position on every Platform pass and
		-- HudToggleClient rewrites the pill's every frame, so the nudge is overwritten
		-- the moment it lands (traced: 1766 -> 1715 by the nudge, then tweened back to
		-- 1725). Insetting at the source is the only place it sticks -- and the pill
		-- follows for free, exactly as it already does on touch.
		if Platform.IsConsole then
			local si = Platform.Insets()
			chip.Position = DESKTOP_POS - UDim2.fromOffset(si.Right, si.Bottom)
		else
			chip.Position = DESKTOP_POS
		end
		return
	end
	-- This gui uses the default screen insets, so a child's Y offset IS its
	-- AbsolutePosition.Y -- the cross-gui maths below stay in that one frame.
	local guiBottom = gui.AbsoluteSize.Y
	local clearY = guiBottom - JUMP_ZONE   -- top of the jump zone
	local sb = sprintButton
	if sb then
		-- MEASURE ONLY WHILE PLAUSIBLE (HudToggle's lesson: hidden or folding
		-- layouts report stale geometry). A real sprint button sits in the lower
		-- half of the screen; anything else is mid-fold or stale, so skip the
		-- write entirely and keep the last good position instead of chasing it.
		if not (sb.Visible and sb.AbsoluteSize.X > 0) then return end
		local top = sb.AbsolutePosition.Y
		if top <= guiBottom * 0.5 or top > guiBottom then return end
		clearY = math.min(clearY, top)
	end
	chip.Position = UDim2.new(1, -16, 0, math.round(clearY - CLUSTER_GAP))
end

task.spawn(function()
	local mainUI = player:WaitForChild("PlayerGui"):WaitForChild("MainUI", 10)
	sprintButton = mainUI and mainUI:WaitForChild("SprintButton", 10) or nil
	if sprintButton then
		-- rotation, a device-sim flip, or another script re-seating the corner
		-- cluster all move the sprint button; the chip re-stacks above it
		sprintButton:GetPropertyChangedSignal("AbsolutePosition"):Connect(repositionChip)
		sprintButton:GetPropertyChangedSignal("AbsoluteSize"):Connect(repositionChip)
	end
	repositionChip()
end)

-- === PHONE: yield to an open GameHUD panel (2026-08-19) ==============
-- The phone HUD panels were just enlarged ~61%: the counter-band reserve that
-- was crushing them to 0.299 scale is gone, so they now run at Platform.FitPanel
-- (~0.483) and read as near-fullscreen MODALS. This chip is anchored bottom-
-- right on a ScreenGui at DisplayOrder 7 -- the same order GameHUD uses -- so it
-- drew straight across an open panel. GameHUDClient's openPanel already clears
-- the nav rail and the currency cluster on phone; this was the last corner
-- surface still on top.
--
-- The tell is the one QuestBarClient watches: GameHUD.Canvas.PanelHost.Visible,
-- which openPanel sets true and closePanel drops false after its close tween.
--
-- THE SWITCH IS chip.Visible, DELIBERATELY NOT gui.Enabled (QuestBarClient uses
-- Enabled; this file must not). HudToggleClient anchors its HIDE UI pill to THIS
-- chip's live AbsolutePosition/AbsoluteSize every frame (its uiTarget), and a
-- DISABLED ScreenGui stops being laid out -- HudToggleClient's own measure()
-- records reading a folded surface at (490, 74) against the (1610, 301) it
-- renders at. Disabling this gui would hand that anchor stale geometry, and a
-- zero AbsoluteSize would drop it to its 1766x863 DESKTOP fallback, i.e. off a
-- phone screen entirely -- so the pill would lurch away and glide back on every
-- panel open. Visible = false still lays out, so the anchor stays exact while
-- the chip stops both drawing and taking taps.
--
-- NOT SUBORDINATE TO ANYTHING, checked: HudToggleClient's fold does not own this
-- chip (LuckHUD is not in its SURFACES list -- "WHAT IS NEVER HIDDEN ... the luck
-- chip"), it only MEASURES it, and nothing else in the game writes LuckChip's
-- visibility. So true is a safe restore value here.
--
-- The breakdown panel needs nothing: LuckPanel is SideRail-registered and so is
-- PanelHost (GameHUDClient), so SideRail's single-open already force-closes the
-- breakdown the moment a HUD panel opens.
local panelHostOpen = false   -- last read of GameHUD.Canvas.PanelHost.Visible

local function syncPanelYield()
	-- Phone only. On desktop and console a panel is a window over a HUD that
	-- stays put, and this chip has always been part of that HUD.
	-- A reward pop is the second thing it yields to (2026-09-21): on the iPhone 16 sim
	-- the chip's top-centre slot (true y 130-174) sits exactly under CatchPop's
	-- creature, so the chip steps aside for the ~1-2s a pop is on screen
	-- (RevealPopActive, published by CatchPop) and comes straight back.
	local popActive = player:GetAttribute("RevealPopActive") == true
	chip.Visible = not (Platform.IsPhone and (panelHostOpen or popActive))
end
player:GetAttributeChangedSignal("RevealPopActive"):Connect(syncPanelYield)

task.spawn(function()
	local hud = player:WaitForChild("PlayerGui"):WaitForChild("GameHUD", 30)
	local canvas = hud and hud:WaitForChild("Canvas", 10)
	local panelHost = canvas and canvas:WaitForChild("PanelHost", 10)
	if not panelHost then return end
	local function onHostChanged()
		-- RailPanelOpen is SideRail's "any registered panel is open" (round 2.5): the
		-- legacy shops never touch PanelHost but are just as fullscreen on a phone.
		panelHostOpen = panelHost.Visible or player:GetAttribute("RailPanelOpen") == true
		syncPanelYield()
	end
	panelHost:GetPropertyChangedSignal("Visible"):Connect(onHostChanged)
	player:GetAttributeChangedSignal("RailPanelOpen"):Connect(onHostChanged)
	onHostChanged()
end)

Platform.Watch(function()
	-- phone 1.3 -> 1.1 (2026-08-17 device-sim audit): the 1.3 chip inflated the
	-- whole corner cluster -- HudToggle's HIDE UI copies this chip's width every
	-- frame, so both ran 179px wide (27% of an iPhone 7 screen). At 1.1 the
	-- pair is ~151px. Trade-off on record: chip height drops 44 -> 37px, under
	-- the 44px touch floor, accepted for a low-frequency control; console keeps
	-- 1.3 (sofa distance, no space pressure).
	-- Was an inline copy of this expression; HudToggle's pill needs the identical
	-- number to stay cluster-width, and it used to get it by measuring this chip.
	chipScale.Scale = HudLayout.ChipScale()
	-- THE TRADE-OFF ABOVE IS NO LONGER NECESSARY (2026-08-25, re-measured 152x37).
	-- It reads as a choice between a 44px-tall chip and a chip narrow enough for a
	-- handset, because the only lever considered was the SCALE -- which moves both
	-- axes. Only the height was ever the problem. Raising the authored height
	-- instead buys the floor on the axis that was short and leaves the width
	-- exactly where 1.1 put it: 40 x 1.1 = 44, still ~151px wide, so HudToggle's
	-- HIDE UI (which copies this chip's width every frame) does not move either.
	-- Set inside the Watch, not at construction, so it tracks a device change.
	-- Was `Platform.IsTouch and 40 or 34`, which rendered 40px on a tablet because
	-- ChipScale is 1.0 there -- four px under the touch floor. The floor and the
	-- scale now live in one expression, so it clears on every device.
	chip.Size = UDim2.new(0, HudLayout.ChipWidth(), 0, HudLayout.ChipHeight())
	-- THE CORNER IS FOR CONTROLS; THIS IS A READOUT (2026-08-27). A phone has about
	-- 229px of usable height and the bottom-right column wanted ~200px of it for
	-- four items. Sprint, RIDE and HIDE UI are things you press; the luck multiplier
	-- is something you glance at, so on a handset it moves to the top edge and the
	-- corner keeps the controls. Desktop and tablet are unchanged.
	if luckSlot then
		-- TopRight -> TopCentre on a phone (2026-08-26).
		--
		-- Moving the chip out of BottomRight was right; moving it to TopRight was not
		-- far enough, because TopRight and BottomRight are THE SAME PHYSICAL COLUMN.
		-- BottomRight holds Sprint(44) + RIDE(50) + HIDE UI(44) and needs 160px of its
		-- 165px band, so it starts at the very top of the column -- exactly where
		-- TopRight starts. Measured at 800x360: the chip landed at y 68..112 and the
		-- HIDE UI pill at y 63..107, an 89% overlap.
		--
		-- Neither audit could report it. StackBudgets() checks each stack against its
		-- own band and both pass (54 of 190, 160 of 165); nothing asks whether two
		-- stacks occupy the same pixels. HudAudit's overlap check would have caught
		-- it, but it is disabled under a device preview and so had only ever run at
		-- 1920x1077, where the column has room for both.
		--
		-- TopCentre is the free band on that screen: it holds only TabBar(56) of 190,
		-- and the chip is a readout, so it does not need thumb reach. Desktop is
		-- untouched -- it keeps BottomRight, where the column is nowhere near full.
		-- ...and TopCentre was not right either (2026-08-26, owner capture). It put a
		-- passive readout directly under the SKIP/SHOPS/PLOT tabs, floating over the
		-- middle of the play area with the character behind it -- the owner marked it
		-- as needing a new home. BottomCentre groups it with the other non-gameplay
		-- furniture (HIDE UI, the quest bar) in the strip between the two thumb
		-- corners, and leaves the centre of the screen to the game.
		--
		-- Taller phones keep TopCentre: their bottom-centre band is doing less work
		-- and the top band there has the room, so nothing moves that does not have to.
		if Platform.IsShortPhone() then
			luckSlot:SetStack("BottomCentre")
		else
			luckSlot:SetStack(Platform.IsPhone and "TopCentre" or "BottomRight")
		end
	end
	-- device class changes move the jump zone in and out of existence; re-seat
	repositionChip()
	-- Platform.IsPhone is a live field (device changes AND the PlatformOverride
	-- attribute both refresh it), so a mid-session flip has to re-decide the
	-- yield too -- otherwise a chip hidden as a phone stays hidden as a desktop.
	syncPanelYield()
end)

-- ======================= THE BREAKDOWN, ON THE KIT (2026-09-18 UI round 2) =======================
-- The flyout used to be UITheme's cream "carved wood" Camp panel with 14px Gotham
-- rows -- the last legacy-styled surface a player reaches from the HUD. It is now
-- a white kit card in the same language as every panel: bubble title, the
-- headline multiplier on a green plate, three tinted section bands (RARITY LUCK
-- gold, MUTATION LUCK purple, BEST THROW blue), and inside RARITY LUCK the
-- sources are split into PERMANENT (rock, charm, offerings, pets) and TEMPORARY
-- (wheel boost, weather event) so a player can see at a glance what is theirs
-- for keeps and what is ticking away. Row maths and every number are unchanged.
local UIKit = modules:WaitForChild("UIKit")
local PC = require(UIKit:WaitForChild("PanelChrome"))
local S = require(UIKit:WaitForChild("SpecTheme"))

local PANEL_W, PANEL_H = 360, 560 -- tall enough for all three sections at 1080p; clamped to the viewport below
local panel = PC.plate({
	name = "LuckPanel",
	size = UDim2.fromOffset(PANEL_W, PANEL_H),
	-- bottom-right, above the chip and LEFT of the quest tracker's column (the old
	-- -260 overlapped the tracker by ~44px at 1891x793)
	position = UDim2.new(1, -310, 1, -118),
	anchor = Vector2.new(1, 1),
	colors = { S.Surface.Shell, S.Surface.Shell },
	radius = 24,
	outline = 5,
	zIndex = 5,
	parent = gui,
	gloss = false,
})
panel.Visible = false
-- UI-02 (2026-09-19): THIS CARD SIZES ITSELF, so it carries its own UIScale.
-- PlatformClient.fitPanels has two branches: a panel with no scale of its own is
-- fitted AND, on a touch screen, GROWN into the space (measured here: x1.16 to x1.35
-- across the phone and tablet profiles), while a panel that already carries one is
-- only ever rescued from an actual overflow, never grown. The grow branch is what
-- put this flyout's title row back off the top of a phone screen after its height
-- budget was fixed below -- the budget is in real pixels and the growth silently
-- multiplied them. Declaring our own scale (first UIScale child: the engine applies
-- only the first, and fitPanels writes its correction through it) hands the sizing
-- back to the Watch below, which measures the screen honestly.
local ownScale = Instance.new("UIScale")
ownScale.Name = "LuckScale"
ownScale.Scale = 1
ownScale.Parent = panel

-- single-open: the luck breakdown is a panel like any other, so opening the
-- backpack (or anything else) puts it away, and vice versa
require(modules:WaitForChild("SideRail")).registerPanel(panel)

-- a phone has ~370px of height: the card never exceeds the screen, and the
-- scrolling list inside it does the rest
--
-- UI-02 (2026-09-19): the flyout is anchored BOTTOM-right and lifted LIFT px clear
-- of the chip, so its height budget has to leave room for that lift AND for the
-- topbar -- `vp.Y - 60` left neither. Measured before this fix on the 1530x576
-- Studio window: panel top -76, i.e. the whole title row -- the "YOUR LUCK" title,
-- the xN headline and the close button with them -- rendered off the top of the
-- screen, so the flyout could not be dismissed by its own X. By the same arithmetic
-- (top = vp.Y - ins.Top - LIFT - h) it also loses that row on a 1280x720 laptop and
-- on every phone profile in Platform.TEST_SIZES, where the 118px lift eats a third
-- of the screen. Height and lift now both come out of what the screen actually has,
-- and the X offset is clamped the same way so a narrow (portrait) screen cannot
-- push the card off the left edge instead. The list inside scrolls, so a shorter
-- card shows fewer rows rather than losing any.
local LIFT, EDGE = 118, 12
local function fitFlyout()
	local vp = Platform.Viewport
	local ins = Platform.Insets()
	-- the band fitPanels measures against too: everything below the topbar
	local usable = math.max(160, vp.Y - ins.Top)
	local w = if Platform.IsPhone then math.min(PANEL_W, vp.X - 40) else PANEL_W
	-- the lift gives way first: on a short screen the card is worth more than the gap
	local lift = math.min(LIFT, math.max(EDGE, usable - 240 - EDGE))
	local minH = math.min(240, math.max(120, usable - 2 * EDGE))
	local h = math.clamp(usable - lift - EDGE, minH, PANEL_H)
	panel.Size = UDim2.fromOffset(w, h)
	panel.Position = UDim2.new(1, -math.clamp(310, EDGE, math.max(EDGE, vp.X - w - EDGE)), 1, -lift)
end
Platform.Watch(fitFlyout)
-- ...AND when the topbar inset arrives. GuiService:GetGuiInset() answers 0 until the
-- topbar has initialised, and Platform.Watch fires on device-class / viewport changes
-- only -- so the first fit of a session was computed against a 58px-taller screen than
-- the real one and the card came out 446 tall instead of 388, which put the title row
-- back off the top until something else moved. Re-fit when the inset lands (and it is
-- idempotent, so a repeat costs nothing).
game:GetService("GuiService"):GetPropertyChangedSignal("TopbarInset"):Connect(fitFlyout)

----------------------------------------------------------------- title row
local TITLE_H = 56
-- round 2.5: the title row is title | headline plate | close. The close is the
-- kit's -- pink-red rounded square, white edge, shout X, the control every HUD
-- panel's header carries -- at flyout size. It used to be an INVISIBLE hit area
-- laid over the headline plate, so nothing told the player how to dismiss this.
local CLOSE_S = 40
PC.shout({
	name = "Title", text = "\u{1F340} YOUR LUCK", size = 26,
	color = S.Role.Positive[2], strokeColor = Color3.new(1, 1, 1),
	align = Enum.TextXAlignment.Left,
	frameSize = UDim2.new(1, -(150 + CLOSE_S + 8), 0, TITLE_H), position = UDim2.fromOffset(16, 0),
	zIndex = 7, parent = panel,
})
-- the headline: RARITY luck, the number that decides what you catch
local headPlate = PC.plate({
	name = "Headline",
	size = UDim2.fromOffset(112, 38),
	position = UDim2.new(1, -(12 + CLOSE_S + 8), 0, 9), anchor = Vector2.new(1, 0),
	colors = S.Role.Positive, radius = 14, outline = 3,
	zIndex = 7, parent = panel, gloss = false,
})
local headline = PC.shout({ name = "Label", text = "\u{00D7}1.00", size = 22, zIndex = 9, parent = headPlate, scaled = true })

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.Text = ""
closeBtn.AutoButtonColor = false
closeBtn.BackgroundColor3 = S.Role.Destructive[1]
closeBtn.BorderSizePixel = 0
closeBtn.Size = UDim2.fromOffset(CLOSE_S, CLOSE_S)
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -12, 0, 8)
closeBtn.ZIndex = 8
closeBtn.Parent = panel
closeBtn:SetAttribute("NoPolish", true)
do
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 12)
	cc.Parent = closeBtn
	local cs = Instance.new("UIStroke")
	cs.Thickness = 3
	cs.Color = Color3.new(1, 1, 1)
	cs.Parent = closeBtn
	local cg = Instance.new("UIGradient")
	cg.Rotation = 90
	cg.Color = ColorSequence.new(S.Role.Destructive[1], S.Role.Destructive[2])
	cg.Parent = closeBtn
end
PC.shout({ text = "X", size = 22, zIndex = 9, parent = closeBtn })
closeBtn:SetAttribute("SfxMuted", true)
PC.bindPressFeedback(closeBtn)

----------------------------------------------------------------- the list
local listFrame = Instance.new("ScrollingFrame")
listFrame.Name = "List"
listFrame.BackgroundTransparency = 1
listFrame.BorderSizePixel = 0
listFrame.Position = UDim2.fromOffset(12, TITLE_H)
listFrame.Size = UDim2.new(1, -24, 1, -TITLE_H - 12)
listFrame.CanvasSize = UDim2.new()
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
listFrame.ScrollBarThickness = 4
listFrame.ScrollBarImageColor3 = S.OutlineSoft
listFrame.ElasticBehavior = Enum.ElasticBehavior.Never
listFrame.ZIndex = 7
listFrame.Parent = panel
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 3)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = listFrame

local INK, SUB = S.Surface.ReadInk, S.Surface.ReadSub
local DIM = Color3.fromHex("A3AFBD")
-- section tints (handoff grammar): gold = value/what you catch, purple = special
-- (mutations), blue = neutral info (odds), orange = time (temporary boosts)
local TINT_RARITY = S.Role.Gold
local TINT_MUT = S.Role.Purple
local TINT_ODDS = S.Role.Neutral
local TINT_TEMP = { Color3.fromHex("FFB454"), Color3.fromHex("FF8A1F") }

--[[ THE ROW. Label left (read face), value right (shout face), and behind them a
faint bar as wide as that source's SHARE of its section total -- the panel reads
as a chart you can scan instead of twenty numbers. One Frame per row. ]]
local rowCount = 0
local function addRow(leftText, rightText, leftColor, rightColor, bold, barFrac, barColour)
	rowCount += 1
	local row = Instance.new("Frame")
	row.Name = "Row" .. rowCount
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -8, 0, 24)   -- 8px gutter so the scrollbar never sits on the numbers
	row.LayoutOrder = rowCount
	row.ZIndex = 7
	row.Parent = listFrame

	if barFrac and barFrac > 0.005 then
		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = barColour or TINT_RARITY[2]
		bar.BackgroundTransparency = 0.84
		bar.Size = UDim2.new(math.min(barFrac, 1), 0, 1, -4)
		bar.Position = UDim2.new(0, 0, 0, 2)
		bar.ZIndex = 7
		bar.Parent = row
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 6)
		bc.Parent = bar
	end

	local l = PC.read({
		name = "L", text = leftText, size = 16, color = leftColor or INK,
		frameSize = UDim2.new(0.62, -6, 1, 0), position = UDim2.fromOffset(8, 0),
		zIndex = 8, parent = row,
	})
	l.TextTruncate = Enum.TextTruncate.AtEnd
	if bold then l.Font = S.Font.Shout end

	local r = PC.shout({
		name = "R", text = rightText, size = 16, color = rightColor or INK, strokeColor = Color3.new(1, 1, 1),
		align = Enum.TextXAlignment.Right,
		frameSize = UDim2.new(0.38, -6, 1, 0), position = UDim2.new(1, -8, 0, 0), anchor = Vector2.new(1, 0),
		zIndex = 8, parent = row,
	})
	if not bold then r.Font = S.Font.Read end
	return row
end

local function clearRows()
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	rowCount = 0
end

local function spacerRow()
	local sp = addRow("", "")
	sp.Size = UDim2.new(1, -8, 0, 8)
	return sp
end

-- a short muted caption under a section heading, indented so it reads as
-- belonging to the heading rather than as another data row
local function noteRow(text)
	local r = addRow(text, "", SUB, SUB)
	r.Size = UDim2.new(1, -8, 0, 18)
	local l = r:FindFirstChild("L")
	if l then
		l.Position = UDim2.fromOffset(14, 0)
		l.Size = UDim2.new(1, -14, 1, 0)
		l.TextSize = 14
	end
	return r
end

-- a section heading on its own coloured band: white shout on the ramp, the
-- section total at the right
local function sectionRow(leftText, rightText, ramp)
	local row = addRow(leftText, rightText, Color3.new(1, 1, 1), Color3.new(1, 1, 1), true)
	row.Size = UDim2.new(1, -8, 0, 32)
	row.BackgroundTransparency = 0
	row.BackgroundColor3 = ramp[1]
	row.BorderSizePixel = 0
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(ramp[1], ramp[2])
	g.Parent = row
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(0, 10)
	rc.Parent = row
	local st = Instance.new("UIStroke")
	st.Thickness = 2
	st.Color = S.Outline
	st.Parent = row
	local lum = ramp[1].R * 0.299 + ramp[1].G * 0.587 + ramp[1].B * 0.114
	for _, n in ipairs({ "L", "R" }) do
		local lbl = row:FindFirstChild(n)
		if lbl then
			lbl.TextColor3 = if lum > 0.82 then INK else Color3.new(1, 1, 1)
			lbl.TextSize = 17
			local ls = lbl:FindFirstChildOfClass("UIStroke")
			if not ls then
				ls = Instance.new("UIStroke")
				ls.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
				ls.Parent = lbl
			end
			ls.Color = if lum > 0.82 then Color3.new(1, 1, 1) else S.Outline
			ls.Thickness = 2
		end
	end
	local l = row:FindFirstChild("L")
	if l then l.Position = UDim2.fromOffset(12, 0) end
	local r = row:FindFirstChild("R")
	if r then r.Position = UDim2.new(1, -12, 0, 0) end
	return row
end

-- a small sub-heading inside a section (PERMANENT / TEMPORARY)
local function groupRow(text, colour)
	local r = addRow(string.upper(text), "", colour, colour, true)
	r.Size = UDim2.new(1, -8, 0, 20)
	local l = r:FindFirstChild("L")
	if l then
		l.TextSize = 13
		l.Position = UDim2.fromOffset(10, 0)
	end
	return r
end

local function refresh()
	local rock = rockById[state.EquippedRock] or rockById["Pebble"]
	local upgradeLuck = UpgradeConfig.Mult(state.Upgrades, "Luck")
	local offeringLuck = OfferingConfig.LuckMult(state.Offerings or 0)
	-- Wheel Luck boost: a timed +30% from the daily wheel. state.Boosts.Luck is the os.time()
	-- it expires (server clock), compared against os.time() the same way the server does.
	local wheelExpires = state.Boosts and tonumber(state.Boosts.Luck) or nil
	local wheelActive = wheelExpires ~= nil and os.time() < wheelExpires
	local wheelLuck = wheelActive and WheelConfig.BOOST_MULT or 1
	-- Placed brainrots: summed as bonuses (mult-1), matching the server's additive accessLuck.
	local petBonus = 0
	for _, e in ipairs(state.Brainrots or {}) do
		if e.PadIndex and petLuckByName[e.Name] then petBonus += (petLuckByName[e.Name] - 1) end
	end
	local rebirthLuck = RebirthConfig.LuckMult(state.Rebirths or 0)
	local weatherLuck = ReplicatedStorage:GetAttribute("WeatherLuck") or 1
	local weatherMut = ReplicatedStorage:GetAttribute("WeatherMut") or 1
	-- Equipped EGG pets (not the placed brainrots above) -- the exact function the
	-- server's PetHandler.LuckMult delegates to, fed from the same snapshot fields.
	local eggPetLuck = PetConfig.StackedMult(state.Pets, state.PetSlots, "Luck")
	-- THE TWO SIGNATURE ABILITIES THAT MOVE LUCK (2026-08-22). Separate from the Luck
	-- column above: a pet's Luck has always fed the MUTATION roll only, while these are
	-- the abilities carried by specific pets. Same StackedMult the server calls, so the
	-- two cannot drift -- see PetConfig.ABILITY_KINDS for where each one lands.
	local petRarityAbility = PetConfig.StackedMult(state.Pets, state.PetSlots, "RarityLuck")
	local petMutAbility = PetConfig.StackedMult(state.Pets, state.PetSlots, "MutationLuck")

	-- RARITY luck == ThrowHandler's accessLuck (ADDITIVE): 1 + every source's bonus, plus the
	-- flat weather event bonus (same for everyone). Perfect x1.075 is per-throw, shown as its
	-- own row rather than folded into this headline.
	local weatherAccessBonus = math.max(weatherLuck - 1, 0)
	local personalRarity = 1
		+ (rock.Luck - 1)
		+ (upgradeLuck - 1)
		+ (offeringLuck - 1)
		+ (wheelLuck - 1)
		+ petBonus
		-- ThrowHandler.personalAccess gained this exact term on 2026-08-22
		+ (petRarityAbility - 1)
	local rarityLuck = personalRarity + weatherAccessBonus
	-- MUTATION luck == the boost ThrowHandler hands Mutations.Roll (ADDITIVE, no clamp).
	local weatherMutBonus = math.max(weatherMut - 1, 0)
	local mutBoost = 1
		+ (rebirthLuck - 1)
		+ (eggPetLuck - 1)
		+ (petMutAbility - 1)
		+ weatherMutBonus

	-- The chip shows RARITY luck: it is the number that decides what you catch, and
	-- multiplying it by the mutation boost would produce a figure the server never
	-- computes. De-plated naked text: white at rest, the luck-green once anything
	-- is boosting the number (green = active here; cashText would read as money).
	chipLabel.Text = ("\u{1F340} Luck \u{00D7}%.2f"):format(rarityLuck)
	local boosted = rarityLuck > 1.0001 or mutBoost > 1.0001
	chipLabel.TextColor3 = boosted and P.green1 or P.text

	if not panel.Visible then return end
	clearRows()
	headline.Text = ("\u{00D7}%.2f"):format(rarityLuck)

	--=================== 1. what you catch ==============================--
	-- ADDITIVE: the header is the total (1 + every bonus below + weather). Each row is the
	-- amount that source ADDS, not a multiplier. Share-of-section denominator: every row
	-- adds into rarityLuck, so a source's bar is its own contribution over that total.
	local rTot = math.max(rarityLuck, 0.0001)
	sectionRow("RARITY LUCK", ("\u{00D7}%.2f"):format(rarityLuck), TINT_RARITY)
	noteRow("which brainrot you catch")
	groupRow("Permanent", SUB)
	addRow("Base", "\u{00D7}1.00", DIM, DIM, false, 1 / rTot, TINT_RARITY[2])
	-- display name, not the save-key Id (see WorldProgression.RockName)
	addRow("Rock (" .. WorldProgression.RockName(rock) .. ")", ("+%.2f"):format(rock.Luck - 1),
		nil, nil, false, (rock.Luck - 1) / rTot, TINT_RARITY[2])
	addRow("Lucky Charm upgrade", ("+%.2f"):format(upgradeLuck - 1),
		nil, nil, false, (upgradeLuck - 1) / rTot, TINT_RARITY[2])
	-- a source contributing nothing is dimmed rather than shown at full weight
	local offLive = offeringLuck > 1.0001
	addRow("Offerings (" .. tostring(math.floor(state.Offerings or 0)) .. ")",
		("+%.2f"):format(offeringLuck - 1),
		(if offLive then INK else DIM), (if offLive then INK else DIM),
		false, (offeringLuck - 1) / rTot, TINT_RARITY[2])
	if petBonus > 0.0001 then
		-- "Brainrots on base", not "Pets": with equipped egg pets shown in the mutation
		-- section below, an unqualified "Pets" row here reads as those.
		addRow("Brainrots on base", ("+%.2f"):format(petBonus), nil, nil, false, petBonus / rTot, TINT_RARITY[2])
	end
	if petRarityAbility > 1.0001 then
		addRow("Pet abilities", ("+%.2f"):format(petRarityAbility - 1), nil, nil, false, (petRarityAbility - 1) / rTot, TINT_RARITY[2])
	end

	-- TEMPORARY: what is ticking away. Always listed, so a player who has no boost
	-- running can see there is one to go and get.
	groupRow("Temporary", TINT_TEMP[2])
	local anyTemp = false
	if wheelLuck > 1.0001 then
		anyTemp = true
		local left = wheelExpires and math.max(0, wheelExpires - os.time()) or 0
		local mins = math.floor(left / 60 + 0.5)
		addRow(("Wheel boost \u{00B7} %dm left"):format(mins), ("+%.2f"):format(wheelLuck - 1),
			TINT_TEMP[2], TINT_TEMP[2], false, (wheelLuck - 1) / rTot, TINT_TEMP[2])
	end
	if weatherAccessBonus > 0.0001 then
		anyTemp = true
		local wName = ReplicatedStorage:GetAttribute("WeatherName")
		local wl = (wName and wName ~= "" and wName ~= "Clear") and ("Event \u{00B7} " .. wName) or "Event luck"
		addRow(wl, ("+%.2f"):format(weatherAccessBonus), TINT_TEMP[2], TINT_TEMP[2],
			false, weatherAccessBonus / rTot, TINT_TEMP[2])
	end
	if not anyTemp then
		noteRow("none active \u{2014} spin the daily wheel for +30%")
	end
	-- multiplies the total rather than adding to it, so it gets no share bar
	addRow("Perfect throw", ("\u{00D7}%.3f"):format(PERFECT_LUCK_MULT), DIM, DIM)

	spacerRow()

	--=================== 2. what it comes out as ========================--
	local mTot = math.max(mutBoost, 0.0001)
	sectionRow("MUTATION LUCK", ("\u{00D7}%.2f"):format(mutBoost), TINT_MUT)
	noteRow("golden / diamond odds")
	addRow("Base", "\u{00D7}1.00", DIM, DIM, false, 1 / mTot, TINT_MUT[2])
	local rbLive = rebirthLuck > 1.0001
	addRow("Rebirths (" .. tostring(math.floor(state.Rebirths or 0)) .. ")",
		("+%.2f"):format(rebirthLuck - 1),
		(if rbLive then INK else DIM), (if rbLive then INK else DIM),
		false, (rebirthLuck - 1) / mTot, TINT_MUT[2])
	if eggPetLuck > 1.0001 then
		addRow("Equipped pets", ("+%.2f"):format(eggPetLuck - 1), nil, nil, false, (eggPetLuck - 1) / mTot, TINT_MUT[2])
	end
	if petMutAbility > 1.0001 then
		addRow("Pet abilities", ("+%.2f"):format(petMutAbility - 1), nil, nil, false, (petMutAbility - 1) / mTot, TINT_MUT[2])
	end
	if weatherMutBonus > 0.0001 then
		local wName = ReplicatedStorage:GetAttribute("WeatherName")
		local wl = (wName and wName ~= "" and wName ~= "Clear") and ("Event \u{00B7} " .. wName) or "Event mutation"
		addRow(wl, ("+%.2f"):format(weatherMutBonus), TINT_TEMP[2], TINT_TEMP[2], false, weatherMutBonus / mTot, TINT_TEMP[2])
	end

	spacerRow()

	--=================== 3. your best throw's odds =====================--
	-- Distance = power x rock.MaxDistance x Power upgrade x rebirth power x (perfect 1.1),
	-- clamped to MAX_TOTAL_DISTANCE. At that best throw, RarityCurve turns distance + luck
	-- into a probability per tier -- the SAME curve the server rolls (RarityCurve).
	local bestDist = math.min(
		rock.MaxDistance
			* UpgradeConfig.Mult(state.Upgrades, "Power")
			* RebirthConfig.PowerMult(state.Rebirths or 0)
			* PERFECT_DISTANCE_MULT,
		MAX_TOTAL_DISTANCE)
	local bestLuck = rarityLuck * PERFECT_LUCK_MULT
	local probs = RarityCurve.Probabilities(bestDist, bestLuck)

	sectionRow("BEST THROW", ("%dm odds"):format(math.floor(bestDist)), TINT_ODDS)
	noteRow("chance per catch at full power")
	for i, tier in ipairs(RarityConfig) do
		local pct = (probs[i] or 0) * 100
		local rightTxt, rightCol
		if tier.MaxDistance == math.huge then
			-- God is off the curve: Pete is an independent 1-in-a-million on top throws
			rightTxt, rightCol = "1 in a million", DIM
		elseif pct <= 0 then
			-- not unlocked yet -- you must throw at least this far for any chance
			rightTxt, rightCol = ("%dm \u{1F512}"):format(math.ceil(tier.MinDistance)), DIM
		elseif pct >= 1 then
			rightTxt, rightCol = ("%.1f%%"):format(pct), INK
		elseif pct >= 0.01 then
			rightTxt, rightCol = ("%.2f%%"):format(pct), INK
		else
			rightTxt, rightCol = "<0.01%", DIM
		end
		-- the bar is the CHANCE itself here, not a share of a total -- square-rooted
		-- so a 0.05% tier still shows a sliver instead of nothing at all
		local frac = (pct > 0 and pct <= 100) and math.sqrt(pct / 100) or 0
		addRow(tier.Name, rightTxt, tier.Color, rightCol, false, frac, tier.Color)
	end
end

closeBtn.MouseButton1Click:Connect(function()
	panel.Visible = false
end)

chip.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
	refresh()
end)

remotes.DataUpdated.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	if data.EquippedRock then state.EquippedRock = data.EquippedRock end
	if data.Upgrades then state.Upgrades = data.Upgrades end
	if data.Rebirths ~= nil then state.Rebirths = data.Rebirths end
	if data.Offerings ~= nil then state.Offerings = data.Offerings end
	if data.Brainrots then state.Brainrots = data.Brainrots end
	if data.Pets then state.Pets = data.Pets end
	if data.PetSlots then state.PetSlots = data.PetSlots end
	if data.Boosts then state.Boosts = data.Boosts end
	refresh()
end)

ReplicatedStorage:GetAttributeChangedSignal("WeatherLuck"):Connect(refresh)
ReplicatedStorage:GetAttributeChangedSignal("WeatherName"):Connect(refresh)
-- WeatherMut is the event's own mutation boost and moves independently of
-- WeatherLuck, so it needs its own listener or the MUTATION LUCK total goes stale.
ReplicatedStorage:GetAttributeChangedSignal("WeatherMut"):Connect(refresh)

task.spawn(function()
	local ok, snapshot = pcall(function()
		return remotes.GetInitialData:InvokeServer()
	end)
	if ok and typeof(snapshot) == "table" then
		state.EquippedRock = snapshot.EquippedRock or state.EquippedRock
		state.Upgrades = snapshot.Upgrades or state.Upgrades
		state.Rebirths = snapshot.Rebirths or state.Rebirths
		state.Offerings = snapshot.Offerings or state.Offerings
		state.Brainrots = snapshot.Brainrots or state.Brainrots
		state.Pets = snapshot.Pets or state.Pets
		state.PetSlots = snapshot.PetSlots or state.PetSlots
		state.Boosts = snapshot.Boosts or state.Boosts
	end
	refresh()
end)
