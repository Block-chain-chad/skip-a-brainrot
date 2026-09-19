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
	chip.Visible = not (Platform.IsPhone and panelHostOpen)
end

task.spawn(function()
	local hud = player:WaitForChild("PlayerGui"):WaitForChild("GameHUD", 30)
	local canvas = hud and hud:WaitForChild("Canvas", 10)
	local panelHost = canvas and canvas:WaitForChild("PanelHost", 10)
	if not panelHost then return end
	local function onHostChanged()
		panelHostOpen = panelHost.Visible
		syncPanelYield()
	end
	panelHost:GetPropertyChangedSignal("Visible"):Connect(onHostChanged)
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

-- expanded breakdown panel
local panel = Instance.new("Frame")
panel.Name = "LuckPanel"
panel.AnchorPoint = Vector2.new(1, 1)
panel.Position = UDim2.new(1, -260, 1, -118)   -- shifted left, clear of the quest tracker band
-- WIDER AND TALLER (2026-08-19). At 278 the label column was 0.62 of 254 usable
-- px = 157px, and "Lucky Charm upgrade" at 13px does not fit -- so the longest,
-- most informative labels were exactly the ones being truncated.
panel.Size = UDim2.new(0, 342, 0, 440)
panel.BackgroundColor3 = P.white
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
-- single-open: the luck breakdown is a panel like any other, so opening the
-- backpack (or anything else) puts it away, and vice versa
require(modules:WaitForChild("SideRail")).registerPanel(panel)
UITheme.campPanel(panel)
UITheme.corner(panel, 16)

-- small carved-wood ribbon overhanging the panel top
local ribbon, title = UITheme.ribbon(panel, "\u{1F340} YOUR LUCK", 0.84)
title.TextSize = 17

-- A ScrollingFrame rather than a plain Frame: the breakdown is now two sections
-- plus the rarity table, and the old fixed Frame silently CLIPPED anything past
-- its height. Scrolling means a future extra source, or a short phone screen,
-- hides nothing.
local listFrame = Instance.new("ScrollingFrame")
listFrame.BackgroundTransparency = 1
listFrame.BorderSizePixel = 0
listFrame.Position = UDim2.new(0, 12, 0, 44)
listFrame.Size = UDim2.new(1, -24, 1, -56)
listFrame.CanvasSize = UDim2.new()
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
listFrame.ScrollBarThickness = 4
listFrame.ScrollBarImageColor3 = CF.wood1
listFrame.ZIndex = 2
listFrame.Parent = panel
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 3)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = listFrame

--[[ ================= THE ROW, REBUILT (2026-08-19) =================
Owner: "so choppy and has weird overlapping lines, it just doesn't look good --
make it cooler and more unique."

THE CHOPPINESS WAS A STROKE, and it measures: every label carried a 1.8px ink
UIStroke at TextSize 13. That is 13.8% of the glyph height, which fattens each
letter until the counters in e/a/o close up -- and on a cream panel it is a DARK
outline around DARK text, so it adds no contrast, only weight. Two neighbouring
rows at an 18px pitch then had their strokes almost touching, which is the
"overlapping lines". The stroke is gone from body rows; it survives only on the
coloured section headings, where light-on-tint genuinely needs it.

THE BAR IS THE NEW PART. Every contribution row now draws a faint bar behind its
label, as wide as that source's SHARE of its section total. The panel stops being
twenty numbers to read in sequence and becomes a chart you can scan: you can see
at a glance that equipped pets are almost all of your mutation luck. It costs one
Frame per row and no extra data -- refresh already knows every number.
]]
local rowCount = 0
local function addRow(leftText, rightText, leftColor, rightColor, bold, barFrac, barColour)
	rowCount += 1
	local row = Instance.new("Frame")
	row.Name = "Row" .. rowCount
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -8, 0, 22)   -- 8px gutter so the scrollbar never sits on the numbers
	row.LayoutOrder = rowCount
	row.ZIndex = 2
	row.Parent = listFrame

	-- share-of-section bar, behind everything
	if barFrac and barFrac > 0.005 then
		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = barColour or CF.amber1
		bar.BackgroundTransparency = 0.82
		bar.Size = UDim2.new(math.min(barFrac, 1), 0, 1, -4)
		bar.Position = UDim2.new(0, 0, 0, 2)
		bar.ZIndex = 2
		bar.Parent = row
		UITheme.corner(bar, 5)
	end

	local l = Instance.new("TextLabel")
	l.Name = "L"
	l.BackgroundTransparency = 1
	l.Position = UDim2.new(0, 6, 0, 0)
	l.Size = UDim2.new(0.60, -6, 1, 0)
	l.Font = bold and Enum.Font.FredokaOne or Enum.Font.GothamMedium
	l.TextSize = 14
	l.TextColor3 = leftColor or CF.ink
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = leftText
	l.ZIndex = 3
	l.Parent = row

	local r = Instance.new("TextLabel")
	r.Name = "R"
	r.BackgroundTransparency = 1
	r.AnchorPoint = Vector2.new(1, 0)
	r.Position = UDim2.new(1, -6, 0, 0)
	r.Size = UDim2.new(0.40, -6, 1, 0)
	r.Font = bold and Enum.Font.FredokaOne or Enum.Font.GothamMedium
	r.TextSize = 14
	r.TextColor3 = rightColor or CF.ink
	r.TextXAlignment = Enum.TextXAlignment.Right
	r.Text = rightText
	r.ZIndex = 3
	r.Parent = row

	-- Stroke ONLY where it earns its place: a bold heading sitting on a coloured
	-- band. Body rows are dark ink on a cream panel and already have all the
	-- contrast they need -- see the note above.
	if bold then
		for _, lbl in ipairs({ l, r }) do
			local st = Instance.new("UIStroke")
			st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			st.Color = CF.ink
			st.Thickness = 1.4
			st.Transparency = 0.15
			st.Parent = lbl
		end
	end
	return row
end

local function clearRows()
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	rowCount = 0
end

local DIM = Color3.fromRGB(128, 110, 94)

local function spacerRow()
	local sp = addRow("", "")
	sp.Size = UDim2.new(1, -8, 0, 6)
	return sp
end

-- A short muted caption under a section heading. INDENTED and smaller, so it
-- reads as belonging to the heading above rather than as another data row -- it
-- carries no number and used to line up with the rows that do.
local function noteRow(text)
	local r = addRow(text, "", DIM, DIM)
	r.Size = UDim2.new(1, -8, 0, 16)
	local l = r:FindFirstChild("L")
	if l then
		l.Position = UDim2.new(0, 14, 0, 0)
		l.Size = UDim2.new(1, -14, 1, 0)
		l.TextSize = 12
		l.Font = Enum.Font.Gotham
	end
	return r
end

--[[ A section heading, on its own tinted band.

The three sections used to be plain bold rows in the same list as their contents,
so the panel read as one undifferentiated column of twenty-odd lines and you had
to read the words to find where a section began. A band makes that structural
rather than typographic -- the three blocks are visible before you read anything.
Tinted from the section's OWN accent so it groups without competing with the
coloured numbers inside it. ]]
local function sectionRow(leftText, rightText, colour)
	local row = addRow(leftText, rightText, colour, colour, true)
	row.Size = UDim2.new(1, -8, 0, 28)
	row.BackgroundColor3 = colour
	row.BackgroundTransparency = 0.86
	row.BorderSizePixel = 0
	UITheme.corner(row, 8)
	local l, r = row:FindFirstChild("L"), row:FindFirstChild("R")
	if l then l.Position = UDim2.new(0, 10, 0, 0); l.TextSize = 15 end
	if r then r.Position = UDim2.new(1, -10, 0, 0); r.TextSize = 15 end
	return row
end

local function refresh()
	local rock = rockById[state.EquippedRock] or rockById["Pebble"]
	local upgradeLuck = UpgradeConfig.Mult(state.Upgrades, "Luck")
	local offeringLuck = OfferingConfig.LuckMult(state.Offerings or 0)
	-- Wheel Luck boost: a timed +30% from the daily wheel. state.Boosts.Luck is the os.time()
	-- it expires (server clock), compared against os.time() the same way the server does.
	local wheelActive = state.Boosts and tonumber(state.Boosts.Luck) ~= nil
		and os.time() < tonumber(state.Boosts.Luck)
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

	--=================== 1. what you catch ==============================--
	-- ADDITIVE: the header is the total (1 + every bonus below + weather). Each row is the
	-- amount that source ADDS, not a multiplier.
	-- Share-of-section denominator: every row below adds into rarityLuck, so a
	-- source's bar is its own contribution over that total. Guarded against a zero
	-- denominator so a broken stat can never divide by nothing.
	local rTot = math.max(rarityLuck, 0.0001)
	sectionRow("RARITY LUCK", ("\u{00D7}%.2f"):format(rarityLuck), CF.amber1)
	noteRow("which brainrot you catch")
	addRow("Base", "\u{00D7}1.00", DIM, DIM, false, 1 / rTot, CF.amber1)
	-- display name, not the save-key Id (see WorldProgression.RockName)
	addRow("Rock (" .. WorldProgression.RockName(rock) .. ")", ("+%.2f"):format(rock.Luck - 1),
		nil, nil, false, (rock.Luck - 1) / rTot, CF.amber1)
	addRow("Lucky Charm upgrade", ("+%.2f"):format(upgradeLuck - 1),
		nil, nil, false, (upgradeLuck - 1) / rTot, CF.amber1)
	-- a source contributing nothing is dimmed rather than shown at full weight:
	-- "Offerings (0)  +0.00" competing with a live bonus is half of why the list
	-- was hard to scan
	local offLive = offeringLuck > 1.0001
	addRow("Offerings (" .. tostring(math.floor(state.Offerings or 0)) .. ")",
		("+%.2f"):format(offeringLuck - 1),
		offLive and CF.ember1 or DIM,
		offLive and CF.ember1 or DIM,
		false, (offeringLuck - 1) / rTot, CF.ember1)
	if wheelLuck > 1.0001 then
		addRow("Wheel boost", ("+%.2f"):format(wheelLuck - 1), CF.ember1, CF.ember1,
			false, (wheelLuck - 1) / rTot, CF.ember1)
	end
	if petBonus > 0.0001 then
		-- "Brainrots on base", not "Pets": with equipped egg pets shown in the mutation
		-- section below, an unqualified "Pets" row here reads as those.
		addRow("Brainrots on base", ("+%.2f"):format(petBonus), CF.pine1, CF.pine1,
			false, petBonus / rTot, CF.pine1)
	end
	if petRarityAbility > 1.0001 then
		-- "Pet abilities", distinct from the "Brainrots on base" row above and from the
		-- "Equipped pets" row in the mutation section: three different pet-ish sources
		-- feed these two totals, and an unqualified label would collapse them.
		addRow("Pet abilities", ("+%.2f"):format(petRarityAbility - 1), CF.pine1, CF.pine1,
			false, (petRarityAbility - 1) / rTot, CF.pine1)
	end
	if weatherAccessBonus > 0.0001 then
		local wName = ReplicatedStorage:GetAttribute("WeatherName")
		local wl = (wName and wName ~= "" and wName ~= "Clear") and ("Event (" .. wName .. ")") or "Event luck"
		addRow(wl, ("+%.2f"):format(weatherAccessBonus), CF.lake1, CF.lake1,
			false, weatherAccessBonus / rTot, CF.lake1)
	end
	-- multiplies the total rather than adding to it, so it gets no share bar
	addRow("Perfect throw", ("\u{00D7}%.3f"):format(PERFECT_LUCK_MULT), DIM, DIM)

	spacerRow()

	--=================== 2. what it comes out as ========================--
	local mTot = math.max(mutBoost, 0.0001)
	sectionRow("MUTATION LUCK", ("\u{00D7}%.2f"):format(mutBoost), CF.berry1)
	noteRow("golden / diamond odds")
	addRow("Base", "\u{00D7}1.00", DIM, DIM, false, 1 / mTot, CF.berry1)
	local rbLive = rebirthLuck > 1.0001
	addRow("Rebirths (" .. tostring(math.floor(state.Rebirths or 0)) .. ")",
		("+%.2f"):format(rebirthLuck - 1),
		rbLive and CF.berry1 or DIM,
		rbLive and CF.berry1 or DIM,
		false, (rebirthLuck - 1) / mTot, CF.berry1)
	if eggPetLuck > 1.0001 then
		addRow("Equipped pets", ("+%.2f"):format(eggPetLuck - 1), CF.berry1, CF.berry1,
			false, (eggPetLuck - 1) / mTot, CF.berry1)
	end
	if petMutAbility > 1.0001 then
		addRow("Pet abilities", ("+%.2f"):format(petMutAbility - 1), CF.berry1, CF.berry1,
			false, (petMutAbility - 1) / mTot, CF.berry1)
	end
	if weatherMutBonus > 0.0001 then
		local wName = ReplicatedStorage:GetAttribute("WeatherName")
		local wl = (wName and wName ~= "" and wName ~= "Clear") and ("Event (" .. wName .. ")") or "Event mutation"
		addRow(wl, ("+%.2f"):format(weatherMutBonus), CF.lake1, CF.lake1,
			false, weatherMutBonus / mTot, CF.lake1)
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

	sectionRow("BEST THROW", ("%dm odds"):format(math.floor(bestDist)), CF.lake1)
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
			rightTxt, rightCol = ("%.1f%%"):format(pct), CF.pine1
		elseif pct >= 0.01 then
			rightTxt, rightCol = ("%.2f%%"):format(pct), CF.pine1
		else
			rightTxt, rightCol = "<0.01%", DIM
		end
		-- the bar is the CHANCE itself here, not a share of a total -- square-rooted
		-- so a 0.05% tier still shows a sliver instead of nothing at all
		local frac = (pct > 0 and pct <= 100) and math.sqrt(pct / 100) or 0
		addRow(tier.Name, rightTxt, tier.Color, rightCol, false, frac, tier.Color)
	end
end

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
