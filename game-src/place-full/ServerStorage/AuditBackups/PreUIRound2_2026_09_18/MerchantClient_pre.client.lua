-- Unified merchant shop: press E at a merchant to see what they sell.
-- Driven by MerchantConfig, so adding a merchant = adding a config entry.
--
-- 2026-08-04 RESTYLE (user handoff "Roblox game theme UI redesign", option
-- 1d): the panel wears the mock's look -- cream body, per-merchant gradient
-- header bar, overlapping red close circle, page chips styled as the mock's
-- tabs, and a 3x2 grid of white cards with price rows + chunky green BUY.
-- ONLY the visual tree changed. The prompt binding (bindStall + AltStalls,
-- the concurrent session's multi-world work), walk-away close, open/close
-- flow, SideRail registration, data wiring and the BuyRock/EquipRock/
-- BuyUpgrade remotes are untouched.
-- Deliberate deviations from the mock, called out in the round report:
--   - the mock's ROCKS/BOOSTS/PASSES tabs have no real counterpart (Rocco
--     sells only rocks; Enzo only upgrades) -- the tab chips ARE the pager;
--   - no NEW! tag (the game has no restock/new-item concept yet);
--   - card icons are the live spinning 3D rock viewports, not emoji
--     (STYLE_GUIDE: no emoji as icons; the kit's own art rule);
--   - locked/equip states keep their distinct button colours -- the mock
--     only drew the buyable state.
--
-- 2026-08-04 STYLE REPLACEMENT (Pet-Sim guide): the cream/1d skin above is
-- GONE. Window body is the guide's light gray, the header bar is ONE red for
-- every merchant (the per-merchant Accent recolour is dropped -- Accent still
-- feeds MerchantDialog), the white+tan cards are the guide's DARK slots with
-- white type, corners tighten to panel 8 / slot 8 / control 12, and every
-- surface stroke is the guide's #202020 with a white inner keyline on the
-- window. Colour IDENTITIES survive untouched: BUY green, EQUIP blue, EQUIPPED
-- olive, LOCKED gray, gold active tab, gold coin, the dark 3D display case.
-- Still visual-only -- prompts, walk-away close, SideRail, the pager and the
-- BuyRock/EquipRock/BuyUpgrade remotes are byte-for-byte the same.
--
-- 2026-08-06 BAZAAR RESTYLE: the Pet-Sim guide's gray/red chrome above is
-- replaced with UITheme's Bazaar dark stall-shop pack (bazaarPanel/
-- bazaarHeader/bazaarClose/bazaarIconSlot/bazaarTitle/bazaarDesc/
-- bazaarStock), matching the Rock Shop/Sell panels in ClientMain and the
-- Totems Shop reference. Colour IDENTITIES survive: the buyable price now
-- reads as a cash pill (BZ.cash1/cash2), EQUIP uses the header cyan,
-- EQUIPPED uses the Palette green (matching ClientMain's rockRows),
-- LOCKED/MAXED and the gold active page chip stay their own literals --
-- Bazaar's palette has no slot for them, and there is no gem/premium
-- currency path here. The 3x2 paginated grid, page chips, prompts,
-- walk-away close, SideRail registration and the BuyRock/EquipRock/
-- BuyUpgrade remotes are untouched; only chrome- and card-construction
-- calls changed. The close button's hover scale/rotate tween is dropped --
-- UITheme.bazaarClose is a static 38px button with no hover state, matching
-- every other Bazaar-styled panel in the game.
--
-- 2026-08-21 SCROLL RESTYLE (owner: "make all the shops scroll wheels and give
-- them the same design as the egg shop but you can scroll through"). The Bazaar
-- chrome described above is REPLACED, and the pager with it. This window is now
-- built from UIKit.Builders + Tokens at the egg shop's own 940x700 footprint,
-- and the 3x2-per-page grid is one ScrollingFrame holding every item -- Rocco's
-- valley shelf is fourteen rocks, which the old PER_PAGE = 6 split across three
-- pages. All three merchants (ROCK SHOP / UPGRADES / CHARMS) share this file, so
-- all three are restyled by it. Prompts, walk-away close, SideRail registration,
-- the dialogue hand-off and the BuyRock / EquipRock / BuyUpgrade remotes are
-- untouched; makeCard even keeps its old signature so rebuild() never changed.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("MainUI")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local WorldProgression = require(ReplicatedStorage.Modules.WorldProgression)
local RockDesign = require(ReplicatedStorage.Modules.RockDesign)
local SideRail = require(ReplicatedStorage.Modules.SideRail)
local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
local MerchantConfig = require(ReplicatedStorage.Modules.MerchantConfig)
local MerchantDialog = require(ReplicatedStorage.Modules.MerchantDialog)
local SoundKit = require(ReplicatedStorage.Modules.SoundKit)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
-- THE EGG SHOP'S KIT (2026-08-21). EggShopClient builds its window out of these
-- two modules and nothing else, so pulling the same pair is what makes the two
-- shops the same furniture rather than two things that merely resemble each
-- other. Platform sizes the modal -- see the viewport-fit block below.
local T = require(ReplicatedStorage.Modules.UIKit.Tokens)
local UI = require(ReplicatedStorage.Modules.UIKit.Builders)
local Platform = require(ReplicatedStorage.Modules:WaitForChild("Platform"))

local BZ = UITheme.Bazaar
local P = UITheme.Palette
local FONT = UITheme.BazaarFont
local state = { Cash = 0, OwnedRocks = {}, EquippedRock = "", Upgrades = {} }
local current = nil
-- WHICH SHELF IS ON SCREEN. Rocco's two stalls stock different rocks, so the panel
-- draws the shelf belonging to the stall you actually walked up to (see
-- MerchantConfig.StallWorld). Defaults to the valley for any stall not listed.
local currentWorld = WorldProgression.Default
local function shelf()
	return WorldProgression.ShelfFor(currentWorld)
end
-- `page` and PER_PAGE are gone with the pager: the card grid is one scroller now
-- and every item is always in it. See the panel block below.

---------------------------------------------------------------- palette (2026-08-06 Bazaar restyle)
-- Panel/header/close/card chrome now comes straight from UITheme.Bazaar
-- (BZ, above). Only the state-identity colours Bazaar's palette has no slot
-- for -- LOCKED/MAXED gray, the gold active page chip -- stay as literals.
-- PS99 cool 2026-08-16: locked state uses the cool grey-blue Inert family
-- (SpecTheme Action.Inert) on the new cool light panel
local LOCK_TOP = Color3.fromHex("#93A1B4") -- LOCKED/MAXED (was warm taupe #8A7C5E)
local LOCK_BOT = Color3.fromHex("#6E7E94") -- (was #5C5138)
-- The gold/green PAGER CHIP colours that stood here are gone with the pager
-- itself (2026-08-21 scroll restyle) -- there are no page tabs left to paint.

local function short(n)
	n = math.floor(n)
	if n >= 1e9 then return string.format("%.1fB", n/1e9)
	elseif n >= 1e6 then return string.format("%.1fM", n/1e6)
	elseif n >= 1e3 then return string.format("%.1fK", n/1e3) end
	return tostring(n)
end
-- display-only: MerchantConfig titles carry a leading emoji ("\u{1F48E} ROCK
-- SHOP"); the style guide bans emoji icons, so strip anything before the
-- first A-Z for the header wordmark. Config itself is untouched.
local function titleWord(s)
	return (tostring(s or ""):gsub("^[^%a]+", ""))
end

-- Mutates an EXISTING button into a Bazaar price/action pill -- same pattern
-- as ClientMain's styleActionPill (green->yellow "cash" look, or any other
-- gradient pair the caller passes), since these buttons are authored once
-- per card and just get restyled in place as state changes across rebuild()s.
local function stylePill(btn, c1, c2, textColor)
	UITheme.bazaarRestylePill(btn, c1, c2, textColor)
end

---------------------------------------------------------------- rock previews (3D)
local spinParts = {}
-- Rock previews come from ReplicatedStorage.Modules.RockDesign, the same builder
-- the thrown rock and Rocco's shelf use -- one source of truth for rock looks.
local function makeRockViewport(med, rock)
	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.new(1, 0, 1, 0)
	vp.BackgroundColor3 = Color3.fromHex("#EFF3F9") -- PS99 cool light art well (was warm #FFF4D9)
	vp.Ambient = Color3.fromRGB(160, 160, 170)
	vp.LightColor = Color3.fromRGB(255, 255, 255) -- neutral light, no warm cast (was 255,244,224)
	vp.LightDirection = Vector3.new(-0.6, -1, -0.4)
	vp.ZIndex = med.ZIndex + 1
	vp.Parent = med
	UITheme.corner(vp, 16)  -- was 8; tracks the r20 icon slot so the 3D preview stops showing square corners inside a rounded tile

	local model = RockDesign.Build(rock.Id, rock.Color)
	model:PivotTo(CFrame.Angles(math.rad(-8), 0, 0))
	model.Parent = vp

	-- frame the camera off the rock's TRUE size so every rock fills the tile
	-- equally, whatever its proportions
	local size = RockDesign.Extents(model)
	local reach = math.max(size.X, size.Y, size.Z)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 38
	cam.CFrame = CFrame.lookAt(Vector3.new(0.42, 0.30, 1) * reach * 2.55, Vector3.new(0, 0, 0))
	cam.Parent = vp
	vp.CurrentCamera = cam

	table.insert(spinParts, model)
end
-- Forward-declared so the spinner driver below can ask whether the panel is even
-- on screen. The frame itself is built further down.
local frame
RunService.RenderStepped:Connect(function()
	if #spinParts == 0 then return end
	-- VISIBILITY GUARD (2026-08-19). Without it, once the merchant panel had been
	-- opened a SINGLE time this kept pivoting a whole page of rock models (up to 7
	-- BaseParts each) and re-rendering their ViewportFrames every frame for the rest
	-- of the session, with the panel closed. The identical driver in EggShopClient
	-- already carries this guard. Pruning still runs while hidden so a closed panel
	-- can never pin destroyed models for the session.
	local spin = frame ~= nil and frame.Visible
	local a = os.clock() * 0.8
	-- backwards + prune: every rebuild destroys the page's viewports, and a
	-- table that only ever grows would pin every dead Model for the session
	-- and walk them all each frame (review catch; same convention as
	-- UIKit.Builders' ringActive driver)
	for i = #spinParts, 1, -1 do
		local mdl = spinParts[i]
		if mdl.Parent then
			if spin then
				mdl:PivotTo(CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(-8), 0, 0))
			end
		else
			table.remove(spinParts, i)
		end
	end
end)

---------------------------------------------------------------- panel (2026-08-21: the egg shop's window)
-- WHY THIS IS THE EGG SHOP'S FURNITURE NOW (owner: "make all the shops scroll
-- wheels and give them the same design as the egg shop but you can scroll
-- through"). What stood here was a 680x552 Bazaar window with a 3x2 grid and a
-- PAGE 1 / PAGE 2 / PAGE 3 chip row. Rocco's valley shelf is FOURTEEN rocks, so
-- the pager was hiding two thirds of the shop behind chips nobody clicks.
--
-- So this window is now built from the same two modules EggShopClient builds its
-- panel from -- UIKit.Builders and UIKit.Tokens -- at the same 940x700 footprint,
-- with the same 92px header band and the same 295-wide cards. The pager is gone,
-- replaced by ONE scroller holding every item at once.
--
-- All three merchants share this window (MerchantConfig: ROCK SHOP, UPGRADES,
-- CHARMS), so all three get the restyle from this one file.
local PANEL_W, PANEL_H = 940, 700       -- the egg shop's own footprint
local HEADER_H = T.size.headerHeight    -- 92
local STRIP_H  = 26                     -- blurb strip under the header
local BLOCK_GAP = T.pad.gap             -- 12
local CARD_W, CARD_H = 295, 250
local GRID_GAP, GRID_COLS = 9, 3
-- 3 x 295 + 2 x 9 = 903 inside the panel's 908 padded content box: three columns
-- exactly, the same count the egg shop's top row runs.
local GRID_TOP = HEADER_H + BLOCK_GAP + STRIP_H + BLOCK_GAP

-- ITS OWN ScreenGui, and BOTH reasons are load-bearing (2026-08-21):
--
-- ZIndexBehavior.Sibling. MainUI runs GLOBAL, where a child draws BELOW a parent
-- that has a higher ZIndex -- and UI.button hardcodes its caption to ZIndex 3, so
-- the close button's glyph rendered underneath its own ZIndex-14 button and came
-- out as a blank red circle. EggShopClient's own header carries a note about
-- exactly this trap; every kit panel runs Sibling, and so must this one.
--
-- DisplayOrder 24. MainUI sits at 5 and GameHUD at 7, so at the egg shop's full
-- 940x700 footprint the HUD's currency cluster drew straight across this window's
-- title bar. 24 clears the HUD and sits just under the egg shop's own 25.
local host = Instance.new("ScreenGui")
host.Name = "MerchantShopUI"
host.ResetOnSpawn = false
host.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
host.DisplayOrder = 24
host.Enabled = true
host.Parent = player:WaitForChild("PlayerGui")
Platform.PrepareGui(host)

frame = Instance.new("Frame") -- assigns the forward-declared upvalue (see the spinner guard above)
frame.Name = "MerchantFrame"
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.new(0.5, 0, 0.5, 0)
frame.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
frame.BackgroundTransparency = 1   -- the UI.panel inside draws the window
frame.Visible = false
frame.ZIndex = 10
frame.Parent = host
-- The rail sits at DisplayOrder 6 and this panel at 0; registering it means
-- the legacy rail folds away while the shop is open (single-open registry).
SideRail.registerPanel(frame)

-- Assigned further down; openMerchant and apply() both call it. Kept as a real
-- local -- without the declaration the `rebuild = function()` below would quietly
-- create a GLOBAL instead.
local rebuild

-- The window itself. UI.panel carries its own 16px padding, which is why every
-- child below sits at x = 0 rather than at a hand-written margin.
local panel = UI.panel(frame, UDim2.fromScale(1, 1))
panel.Name = "Panel"
panel.ZIndex = 11

---------------------------------------------------------------- header band
local header = UI.surface(panel, UDim2.new(1, 0, 0, HEADER_H), "panel", T.radius.panel, T.stroke.panel)
header.Name = "Header"
header:SetAttribute("PolishOnDark", true)
header.ZIndex = panel.ZIndex + 1
-- RETINT the gradient UI.surface already parented; do not add a second. Two
-- UIGradients on one GuiObject do not blend -- one simply wins, and which one is
-- not something to rely on. BZ.rockHeader1/2 is the pair the Bazaar palette
-- already defines for this shop, sibling to the eggHeader pink next door: same
-- furniture, different colour, which is exactly the family resemblance wanted.
do
	local hg = header:FindFirstChildOfClass("UIGradient")
	if hg then
		hg.Color = ColorSequence.new(BZ.rockHeader1, BZ.rockHeader2)
	else
		UI.gradient(header, ColorSequence.new(BZ.rockHeader1, BZ.rockHeader2))
	end
end

local title = UI.label(header, "SHOPS", "panelTitle", T.color.white)
title.Name = "Title"
title.AnchorPoint = Vector2.new(0, 0.5)
title.Position = UDim2.new(0, 18, 0.5, 0)
title.Size = UDim2.new(1, -96, 0, 44)
title.AutomaticSize = Enum.AutomaticSize.None
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = header.ZIndex + 1

-- "X" THE LETTER, never U+2715 -- and "buttonL", not "buttonM". EggShopClient
-- carries the same line with the same warning ("this file already lost a close
-- button"): UIPolish force-sets Font = FredokaOne on every label in the game, and
-- FredokaOne has no U+2715, so the multiplication-X renders as nothing and the
-- button ships as a blank red circle. Verified here the same way -- the glyph
-- measured 12x27 of bounds and drew nothing.
local closeBtn = UI.button(header, "X", "red", UDim2.fromOffset(44, 44), "buttonL")
closeBtn.Name = "CloseButton"
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, -16, 0.5, 0)
closeBtn.ZIndex = header.ZIndex + 2

---------------------------------------------------------------- blurb strip
local blurb = UI.label(panel, "", "meta", T.color.textOnWindow)
blurb.Name = "Blurb"
blurb.Position = UDim2.fromOffset(0, HEADER_H + BLOCK_GAP)
blurb.Size = UDim2.new(1, 0, 0, STRIP_H)
blurb.AutomaticSize = Enum.AutomaticSize.None
blurb.TextXAlignment = Enum.TextXAlignment.Center
blurb.ZIndex = panel.ZIndex + 1

---------------------------------------------------------------- the scroller
-- THE PAGER'S REPLACEMENT. AutomaticCanvasSize grows the canvas to whatever the
-- grid lays out, so a 14-rock shelf and a 7-upgrade list both work with no page
-- count computed anywhere and no chips to keep in sync with the data.
local list = Instance.new("ScrollingFrame")
list.Name = "CardGrid"
list.Size = UDim2.new(1, 0, 1, -GRID_TOP)
list.Position = UDim2.fromOffset(0, GRID_TOP)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 8
list.ScrollBarImageColor3 = T.color.scrollThumb
list.ScrollBarImageTransparency = 0.15
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ScrollingDirection = Enum.ScrollingDirection.Y
list.ZIndex = panel.ZIndex + 1
list.Parent = panel
local layout = Instance.new("UIGridLayout")
layout.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
layout.CellPadding = UDim2.fromOffset(GRID_GAP, GRID_GAP)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = list
-- bottom gutter, so the last row does not sit flush against the panel edge
local listPad = Instance.new("UIPadding")
listPad.PaddingBottom = UDim.new(0, GRID_GAP)
listPad.Parent = list

---------------------------------------------------------------- viewport fit
-- Platform.FitPanel is the project's single answer to "how big is a modal on this
-- device", and it is the call EggShopClient makes for the very same window size.
-- It replaces this file's old bespoke `FILL = 0.76` constant, which knew nothing
-- about phones or console title-safe. The measure-and-recentre loop below is kept
-- verbatim: layout still positions the frame from its UNSCALED size while UIScale
-- draws it scaled, so the centre still has to be read back rather than predicted.
local hudScale = Instance.new("UIScale")
hudScale.Name = "HudFixScale"
hudScale.Parent = frame

local function recentre()
	-- Retries across frames and ignores a zero-size read: at script load the frame
	-- has not been laid out yet, and an early pass saw a delta of ~0, returned, and
	-- left the panel 58px high for the whole session.
	for _ = 1, 8 do
		local h = frame.AbsoluteSize.Y
		if h > 0 then
			-- CENTRE IN THE PARENT GUI'S BOX, not the camera's (2026-08-21). MainUI
			-- carries ScreenInsets, so its space runs -58 .. vpY-58 rather than
			-- 0 .. vpY. Solving against the raw viewport therefore parked the window
			-- 58px low, which the old 552-tall panel had the slack to absorb and the
			-- egg shop's 973 does not: measured, it hung 6px off the bottom edge.
			local mid = host.AbsolutePosition.Y + host.AbsoluteSize.Y / 2
			local delta = mid - (frame.AbsolutePosition.Y + h / 2)
			if math.abs(delta) < 1 then return end
			frame.Position = frame.Position + UDim2.fromOffset(0, delta)
		end
		task.wait()
	end
end

local function relayout()
	local vh, vw = host.AbsoluteSize.Y, host.AbsoluteSize.X
	if vh <= 0 or vw <= 0 then return end
	hudScale.Scale = Platform.FitPanel(PANEL_W, PANEL_H)
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	task.defer(recentre)
end
host:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
Platform.Watch(relayout)
relayout()
-- Re-centre whenever the panel is actually shown. Startup layout is the unreliable
-- moment; the instant it becomes visible, the rect is real.
frame:GetPropertyChangedSignal("Visible"):Connect(function()
	if frame.Visible then task.defer(recentre) end
end)

---------------------------------------------------------------- coming soon plate
-- For a merchant whose shelf is not built yet (MerchantConfig.ComingSoon). Built
-- ONCE and toggled, like the blurb above -- rebuild() only clears the card grid,
-- so anything parented to the panel itself must not be rebuilt per open or it
-- would stack a copy every time you walked up.
local comingSoon = UI.label(panel, "COMING SOON!", "panelTitle", T.color.textOnWindow)
comingSoon.Name = "ComingSoon"
comingSoon.AnchorPoint = Vector2.new(0.5, 0)
comingSoon.Position = UDim2.new(0.5, 0, 0, GRID_TOP + 110)
comingSoon.Size = UDim2.new(1, -60, 0, 90)
comingSoon.AutomaticSize = Enum.AutomaticSize.None
comingSoon.TextXAlignment = Enum.TextXAlignment.Center
comingSoon.Visible = false
comingSoon.ZIndex = panel.ZIndex + 3

---------------------------------------------------------------- card builder (egg-shop card)
-- SIGNATURE DELIBERATELY UNCHANGED from the Bazaar card this replaces, so
-- rebuild()'s item closures below -- and with them the whole rock/upgrade data
-- path, the remotes and the state rules -- are untouched by the restyle.
--
-- The bands mirror EggShopClient's card so the two grids read as one design:
-- art / name / info / action, four bands and three gaps inside a 13px pad.
-- 13 + 101 + 9 + 24 + 9 + 32 + 9 + 40 + 13 = 250 = CARD_H, which is why none of
-- these numbers is free to drift on its own.
local CARD_PAD, BAND_GAP = 13, 9
local ART_H, NAME_H, INFO_H, BTN_H = 101, 24, 32, 40

local function makeCard(order, name, infoLine, btnText, btnTop, btnBot, textColor, onClick, previewBuilder, statLine, stockText)
	-- UI.surface, NOT UI.panel: UI.panel hangs a hard shadow as a SIBLING, and a
	-- sibling dropped into this UIGridLayout becomes a phantom cell that shoves
	-- every later card one slot along. Cards are surfaces everywhere in this kit.
	local card = UI.surface(list, UDim2.fromOffset(CARD_W, CARD_H), "subPanel", T.radius.panel, T.stroke.control)
	card.Name = "Card" .. order
	card.LayoutOrder = order
	card.ZIndex = list.ZIndex + 1
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, CARD_PAD)
	pad.PaddingBottom = UDim.new(0, CARD_PAD)
	pad.PaddingLeft = UDim.new(0, CARD_PAD)
	pad.PaddingRight = UDim.new(0, CARD_PAD)
	pad.Parent = card

	-- ART WELL: the kit's "slot" ground, so a spinning 3D rock and an upgrade
	-- glyph sit in the same frame instead of each inventing their own tile.
	local well = UI.surface(card, UDim2.new(1, 0, 0, ART_H), "slot", T.radius.art, T.stroke.control)
	well.Name = "ArtWell"
	well.ZIndex = card.ZIndex + 1
	well.ClipsDescendants = true
	if previewBuilder then
		previewBuilder(well)
	end

	-- Sequential-unlock warning, laid OVER the foot of the art well rather than
	-- given a band of its own: every cell in a UIGridLayout is the same height, so
	-- a card that grew when it had a warning would misalign its whole row.
	if stockText then
		local warn = UI.label(well, stockText, "meta", T.color.white)
		warn.Name = "StockWarn"
		warn.AnchorPoint = Vector2.new(0.5, 1)
		warn.Position = UDim2.new(0.5, 0, 1, -4)
		warn.Size = UDim2.new(1, -12, 0, 16)
		warn.AutomaticSize = Enum.AutomaticSize.None
		warn.TextXAlignment = Enum.TextXAlignment.Center
		warn.ZIndex = well.ZIndex + 4
	end

	local n = UI.label(card, name, "cardLabel", T.color.textOnWindow)
	n.Name = "Name"
	n.Position = UDim2.fromOffset(0, ART_H + BAND_GAP)
	n.Size = UDim2.new(1, 0, 0, NAME_H)
	n.AutomaticSize = Enum.AutomaticSize.None
	n.TextXAlignment = Enum.TextXAlignment.Center
	n.TextTruncate = Enum.TextTruncate.AtEnd
	n.ZIndex = card.ZIndex + 1

	local info = UI.label(card, statLine and (infoLine .. "  \u{2022}  " .. statLine) or infoLine,
		"meta", T.color.textOnWindow)
	info.Name = "Info"
	info.Position = UDim2.fromOffset(0, ART_H + BAND_GAP + NAME_H + BAND_GAP)
	info.Size = UDim2.new(1, 0, 0, INFO_H)
	info.AutomaticSize = Enum.AutomaticSize.None
	info.TextWrapped = true
	info.TextXAlignment = Enum.TextXAlignment.Center
	info.ZIndex = card.ZIndex + 1

	-- ACTION PILL. Still a bare TextButton restyled by stylePill rather than a
	-- UI.button: the caller passes an explicit gradient PAIR per state (cash
	-- green, header cyan, Palette green, locked grey) and the kit's named variants
	-- have no slot for that vocabulary. Absolutely positioned, so UI.hardShadow's
	-- sibling problem cannot bite -- the card itself carries no layout.
	local b = Instance.new("TextButton")
	b.Name = "ActionButton"
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = UDim2.new(0.5, 0, 1, 0)
	b.Size = UDim2.new(1, 0, 0, BTN_H)
	b.Text = btnText
	b.TextSize = 18
	b.ZIndex = card.ZIndex + 2
	b.Parent = card
	stylePill(b, btnTop, btnBot, textColor)
	if onClick then
		b.Activated:Connect(onClick)
	end
	return card
end

---------------------------------------------------------------- rebuild
rebuild = function()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	if not current then return end
	title.Text = titleWord(current.Title)
	blurb.Text = current.Npc .. "  \u{2022}  " .. current.Blurb

	-- SHELF NOT BUILT YET. The walk-up, the dialogue and the panel all behave
	-- exactly as they do for any other merchant -- you just get told, instead of
	-- being shown an empty grid. The blurb above still runs, so the merchant keeps
	-- their own pitch over the notice.
	comingSoon.Visible = current.ComingSoon == true
	list.Visible = not current.ComingSoon
	if current.ComingSoon then
		return
	end
	-- style replacement (2026-08-04, Pet-Sim guide): the header no longer
	-- repaints itself from current.Accent -- the guide gives shop chrome ONE
	-- red, so headerGrad/SquareOff keep the colours they were built with and
	-- every merchant shares the bar. current.Accent is still live data and is
	-- still read where it means something (MerchantDialog.Show, below).

	-- Build a flat list of render closures so pagination is Kind-agnostic: each entry
	-- draws exactly one card when called with its position in the scroller.
	local items = {}
	if current.Kind == "Rock" then
		local rocks = shelf()
		for i, rock in ipairs(rocks) do
			local owned = state.OwnedRocks[rock.Id]
			local equipped = state.EquippedRock == rock.Id
			-- SEQUENTIAL UNLOCK, within THIS world's ladder: the tundra shelf is
			-- self-contained, so its first rock is buyable without any valley rock
			local prevRock = rocks[i - 1]
			local unlocked = (i == 1) or (prevRock ~= nil and state.OwnedRocks[prevRock.Id] == true)
			items[i] = function(order)
				local txt, top, bot, textColor, cb
				if equipped then
					txt, top, bot, textColor = "EQUIPPED", P.green1, P.green2, BZ.white
				elseif owned then
					txt, top, bot, textColor = "EQUIP", BZ.header1, BZ.header2, BZ.white
					cb = function() remotes.EquipRock:FireServer(rock.Id) end
				elseif not unlocked then
					txt, top, bot, textColor = "LOCKED", LOCK_TOP, LOCK_BOT, BZ.white
					-- no cb -> disabled button
				else
					txt, top, bot, textColor = "$" .. short(rock.Price), BZ.cash1, BZ.cash2, BZ.cashText
					cb = function() remotes.BuyRock:FireServer(rock.Id) end
				end
				local desc = ("Up to %dm  \u{2022}  %.2fx luck"):format(rock.MaxDistance, rock.Luck)
				-- DISPLAY NAME, not the Id (2026-08-22). Ids are save keys in CamelCase,
				-- so the shelf used to read "MeteoriteFragment" / "PermafrostHeart".
				-- WorldProgression.RockName is the single resolver -- see its note there.
				local stockText = (not owned and not unlocked and prevRock)
					and ("Buy the %s first"):format(WorldProgression.RockName(prevRock)) or nil
				makeCard(order, WorldProgression.RockName(rock), desc, txt, top, bot, textColor, cb,
					function(med) makeRockViewport(med, rock) end, nil, stockText)
			end
		end
	elseif current.Kind == "Upgrade" then
		for i, up in ipairs(UpgradeConfig.List) do
			items[i] = function(order)
				local lvl = UpgradeConfig.Level(state.Upgrades, up.Id)
				local price = UpgradeConfig.Price(up.Id, lvl)
				-- NOT `+%d%%` off PerLevel any more (2026-08-20). The two bag upgrades
				-- store a COUNT of slots per level rather than a fraction of a
				-- multiplier, so the old inline format printed "+2500%" for one level
				-- of Deep Pockets. UpgradeConfig.EffectText owns the per-unit wording.
				local effect = UpgradeConfig.EffectText(up, lvl)
				local txt, top, bot, textColor, cb
				if not price then
					txt, top, bot, textColor = "MAXED", LOCK_TOP, LOCK_BOT, BZ.white
				else
					txt, top, bot, textColor = "$" .. short(price), BZ.cash1, BZ.cash2, BZ.cashText
					cb = function() remotes.BuyUpgrade:FireServer(up.Id) end
				end
				makeCard(order, up.Name, up.Desc, txt, top, bot, textColor, cb,
					function(holder)
						local e = Instance.new("TextLabel")
						e.Size = UDim2.fromScale(1, 1)
						e.BackgroundTransparency = 1
						e.Font = UITheme.GlyphFont
						e.TextSize = 40
						e.Text = up.Icon
						e.ZIndex = holder.ZIndex + 1
						e.Parent = holder
					end,
					("Lv. %d/%d  %s"):format(lvl, up.MaxLevel, effect))
			end
		end
	end

	-- EVERY ITEM, IN ONE SCROLL. What this replaces rendered PER_PAGE = 6 of
	-- Rocco's FOURTEEN valley rocks, so two thirds of the shop lived behind PAGE 2
	-- and PAGE 3 chips. The grid's AutomaticCanvasSize means nothing here needs to
	-- know how many rows that comes to.
	for i = 1, #items do
		items[i](i)
	end
end

---------------------------------------------------------------- open / close
---------------------------------------------------------------- open / close
-- Open SCROLLED TO your next rock rather than pinned at the top. This is the
-- same intent firstRelevantPage had when it picked an opening PAGE, expressed
-- against a scroller instead of a pager: you still walk up to Rocco and see the
-- rock you are actually saving for, without the shop having to be split up.
local function firstRelevantOffset(m)
	if m.Kind ~= "Rock" then return 0 end
	for i, rock in ipairs(shelf()) do
		if not state.OwnedRocks[rock.Id] then
			return math.max(0, math.floor((i - 1) / GRID_COLS) * (CARD_H + GRID_GAP))
		end
	end
	return 0
end

local function openMerchant(m, world)
	current = m
	currentWorld = world or WorldProgression.Default
	local shop = gui:FindFirstChild("ShopFrame"); if shop then shop.Visible = false end
	local sell = gui:FindFirstChild("SellFrame"); if sell then sell.Visible = false end
	local idx = gui:FindFirstChild("IndexFrame"); if idx then idx.Visible = false end
	rebuild()
	frame.Visible = true
	-- DEFERRED, and it has to be: AutomaticCanvasSize has not measured the grid
	-- yet on the frame rebuild() ran in, so the canvas is still zero-height and
	-- any CanvasPosition written now would be clamped straight back to 0.
	local want = firstRelevantOffset(m)
	task.defer(function()
		if frame.Visible then list.CanvasPosition = Vector2.new(0, want) end
	end)
end
local function closeMerchant()
	frame.Visible = false
	current = nil
end
closeBtn.MouseButton1Click:Connect(closeMerchant)

---------------------------------------------------------------- entry cue
-- A merchant's walk-in sound is a SoundKit NAME on its MerchantConfig entry, not
-- an asset id -- SoundKit owns every id in the game. Passing nil for `where`
-- makes it 2D, which is right: this is a cue for the player who pressed E, so
-- there is no rolloff to tune. SoundKit.play clones a preloaded template and
-- Debris-cleans the clone, so repeat entries never stack voices. Templates are
-- already warmed by RareCatchClient's SoundKit.preload(), which walks all Ids.
local function playEnterCue(m)
	if not m.EnterSound then return end
	SoundKit.play(m.EnterSound, nil, { volume = m.EnterVolume or 0.35 })
end

---------------------------------------------------------------- prompts
local gameWorld = Workspace:WaitForChild("GameWorld")
-- A merchant can stand in more than one world. `Stall` is the primary and
-- `AltStalls` lists the copies (the Frozen Tundra hub). Each one binds the SAME
-- handler, so the shop behaves identically wherever it is opened from.
local StallPrompt = require(game:GetService("ReplicatedStorage").Modules.StallPrompt)
local promptParts = {}          -- [Id] = { part, part, ... }
-- Bound through StallPrompt rather than a one-shot WaitForChild: with streaming on,
-- the tundra copy's parts are not replicated to a player standing in the valley, so
-- the old 30s wait timed out and world 2's prompts were never connected at all.
local function bindStall(m, stallName)
	-- the shelf this particular stall stocks; declared in MerchantConfig, not guessed
	local stallWorld = MerchantConfig.StallWorld and MerchantConfig.StallWorld[stallName]
	StallPrompt.Bind(stallName, m.Prompt, function(part, prompt)
		local list = promptParts[m.Id]
		if not list then list = {}; promptParts[m.Id] = list end
		table.insert(list, part)
		prompt.Triggered:Connect(function(who)
			if who ~= player then return end
			if frame.Visible and current and current.Id == m.Id then
				closeMerchant()
			else
				-- Cue fires here, in the OPENING branch only -- the same Triggered
				-- event doubles as the close-toggle above, and a shop bell going off
				-- as you walk out would be wrong.
				playEnterCue(m)
				-- E starts a short dialogue; the shop opens when the player continues
				MerchantDialog.Show(m.Npc, m.Dialogue, m.Accent, function() openMerchant(m, stallWorld) end, part)
			end
		end)
	end)
end
for _, m in ipairs(MerchantConfig) do
	bindStall(m, m.Stall)
	for _, alt in ipairs(m.AltStalls or {}) do bindStall(m, alt) end
end

-- walk away -> close
RunService.Heartbeat:Connect(function()
	if not frame.Visible or not current then return end
	local list = promptParts[current.Id]
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not list or not hrp then return end
	-- nearest, not first: the same merchant now exists in two worlds 11k studs apart.
	-- Parentless parts are ones that have STREAMED OUT -- their last known position is
	-- stale, and counting it would close the panel you just opened in the other world.
	local nearest = math.huge
	for _, part in ipairs(list) do
		if part.Parent then
			nearest = math.min(nearest, (hrp.Position - part.Position).Magnitude)
		end
	end
	if nearest > 24 then closeMerchant() end
end)

---------------------------------------------------------------- data
local function apply(snap)
	if not snap then return end
	state.Cash = snap.Cash or state.Cash
	state.OwnedRocks = snap.OwnedRocks or state.OwnedRocks
	state.EquippedRock = snap.EquippedRock or state.EquippedRock
	state.Upgrades = snap.Upgrades or state.Upgrades
	if frame.Visible then rebuild() end
end
task.spawn(function()
	local ok, snap = pcall(function() return remotes.GetInitialData:InvokeServer() end)
	if ok then apply(snap) end
end)
remotes.DataUpdated.OnClientEvent:Connect(apply)
remotes.CashTick.OnClientEvent:Connect(function(cash)
	state.Cash = cash
end)
