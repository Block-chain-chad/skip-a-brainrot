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
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("MainUI")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local RockConfig = require(ReplicatedStorage.Modules.RockConfig)
local RockDesign = require(ReplicatedStorage.Modules.RockDesign)
local SideRail = require(ReplicatedStorage.Modules.SideRail)
local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
local MerchantConfig = require(ReplicatedStorage.Modules.MerchantConfig)
local MerchantDialog = require(ReplicatedStorage.Modules.MerchantDialog)
local SoundKit = require(ReplicatedStorage.Modules.SoundKit)
local UITheme = require(ReplicatedStorage.Modules.UITheme)

local BLACK = Color3.fromRGB(0, 0, 0)
local FONT = UITheme.Font
local state = { Cash = 0, OwnedRocks = {}, EquippedRock = "", Upgrades = {} }
local current = nil
local page = 1
local PER_PAGE = 6   -- mock 1d: 3x2 grid per page (was 2x4 of 8)

---------------------------------------------------------------- palette (style replacement 2026-08-04, Pet-Sim guide)
-- These mirror T.gradient.window / T.gradient.header / T.gradient.slot and
-- T.color.outline / innerKeyline / textOnWindow, but stay literals: this
-- client has never required the Tokens module at load (only a pcall for the
-- coin art), and it is not worth a new hard dependency for a colour table.
local WINDOW_TOP = Color3.fromHex("#d6d6d6")   -- guide window body, top
local WINDOW_BOT = Color3.fromHex("#a9a9a9")   -- guide window body, bottom
local HEADER_TOP = Color3.fromHex("#f96b57")   -- guide header bar -- ONE red, every merchant
local HEADER_BOT = Color3.fromHex("#c84535")
local SLOT_TOP = Color3.fromHex("#4a4a4a")     -- guide card/slot/row, top
local SLOT_BOT = Color3.fromHex("#363636")     -- guide card/slot/row, bottom
local OUTLINE = Color3.fromHex("#202020")      -- guide outer border (was BLACK-on-tan)
local KEYLINE = Color3.fromHex("#ffffff")      -- guide inner keyline
-- card type used to be dark ink so it could sit on cream; the cards are DARK
-- now, so it goes back to white. Only the blurb still sits straight on the
-- light window, and it alone keeps the dark ink (= T.color.textOnWindow).
local SLOT_TEXT = Color3.fromRGB(255, 255, 255)
local SLOT_MUTED = Color3.fromHex("#c9c9c9")
local TEXT_ON_WINDOW = Color3.fromHex("#202020")
-- currency identity kept, brightened off the old cream-friendly #b47607: an
-- amber that dark reads as mud on a #363636 slot.
local PRICE_AMBER = Color3.fromHex("#ffc531")
-- state identities, retuned to the guide's own accent pairs (green/blue/red)
-- -- same three states, same reading, guide-exact hexes.
local BUY_TOP = Color3.fromHex("#83e34a")
local BUY_BOT = Color3.fromHex("#4fb42e")
local EQUIP_TOP = Color3.fromHex("#56b7ff")
local EQUIP_BOT = Color3.fromHex("#2e81d8")
local DONE_TOP = Color3.fromHex("#8fa378")     -- EQUIPPED olive: no guide counterpart, left alone
local DONE_BOT = Color3.fromHex("#54643c")
local LOCK_TOP = Color3.fromRGB(150, 156, 170) -- LOCKED/MAXED gray, left alone
local LOCK_BOT = Color3.fromRGB(94, 100, 114)
local TAB_GOLD_TOP = Color3.fromHex("#ffdf5e") -- active pager chip: gold is the selected-tab identity
local TAB_GOLD_BOT = Color3.fromHex("#f7a721")
local CLOSE_TOP = Color3.fromHex("#ff6b6b")    -- guide red accent
local CLOSE_BOT = Color3.fromHex("#d83e3e")

local function short(n)
	n = math.floor(n)
	if n >= 1e9 then return string.format("%.1fB", n/1e9)
	elseif n >= 1e6 then return string.format("%.1fM", n/1e6)
	elseif n >= 1e3 then return string.format("%.1fK", n/1e3) end
	return tostring(n)
end
local function inkText(o, thick)
	local st = Instance.new("UIStroke")
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	st.Color = BLACK; st.Thickness = thick or 2; st.Transparency = 0.05
	st.Parent = o
	return st
end
-- display-only: MerchantConfig titles carry a leading emoji ("\u{1F48E} ROCK
-- SHOP"); the style guide bans emoji icons, so strip anything before the
-- first A-Z for the header wordmark. Config itself is untouched.
local function titleWord(s)
	return (tostring(s or ""):gsub("^[^%a]+", ""))
end

---------------------------------------------------------------- rock previews (3D)
local spinParts = {}
-- Rock previews come from ReplicatedStorage.Modules.RockDesign, the same builder
-- the thrown rock and Rocco's shelf use -- one source of truth for rock looks.
local function makeRockViewport(med, rock)
	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.new(1, 0, 1, 0)
	vp.BackgroundColor3 = Color3.fromRGB(26, 30, 40)
	vp.Ambient = Color3.fromRGB(160, 160, 170)
	vp.LightColor = Color3.fromRGB(255, 244, 224)
	vp.LightDirection = Vector3.new(-0.6, -1, -0.4)
	vp.ZIndex = med.ZIndex + 1
	vp.Parent = med
	UITheme.corner(vp, 8)   -- guide: art 8, matched to the display case it fills

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
RunService.RenderStepped:Connect(function()
	local a = os.clock() * 0.8
	-- backwards + prune: every rebuild destroys the page's viewports, and a
	-- table that only ever grows would pin every dead Model for the session
	-- and walk them all each frame (review catch; same convention as
	-- UIKit.Builders' ringActive driver)
	for i = #spinParts, 1, -1 do
		local mdl = spinParts[i]
		if mdl.Parent then
			mdl:PivotTo(CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(-8), 0, 0))
		else
			table.remove(spinParts, i)
		end
	end
end)

---------------------------------------------------------------- panel (guide window)
local FRAME_W, FRAME_H = 680, 620
local HEADER_H = 58
local BLURB_H = 20
local CHIPS_H = 38
local GRID_TOP = HEADER_H + 8 + BLURB_H + 6 + CHIPS_H + 6

local frame = Instance.new("Frame")
frame.Name = "MerchantFrame"
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.new(0.5, 0, 0.5, 0)
frame.Size = UDim2.fromOffset(FRAME_W, FRAME_H)
frame.BackgroundColor3 = WINDOW_TOP
frame.BorderSizePixel = 0
frame.Visible = false
frame.ZIndex = 10
frame.Parent = gui
-- The rail sits at DisplayOrder 6 and this panel at 0; registering it means
-- the legacy rail folds away while the shop is open (single-open registry).
SideRail.registerPanel(frame)
UITheme.corner(frame, 8)   -- guide: panels 8 (was the 1d mock's 24)
do
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(WINDOW_TOP, WINDOW_BOT)
	grad.Parent = frame
	local ink = Instance.new("UIStroke")
	ink.Thickness = 4
	ink.Color = OUTLINE
	ink.Transparency = 0.05
	ink.Parent = frame
	-- guide inner keyline: a UIStroke is one-per-instance, so the 2px white
	-- line is its own inset ring. Active = false + no fill, so it neither eats
	-- clicks nor covers content (it sits at the panel's own ZIndex, under the
	-- 11+ chrome), and it is deliberately NOT a second stroke on `frame`.
	local keyline = Instance.new("Frame")
	keyline.Name = "InnerKeyline"
	keyline.AnchorPoint = Vector2.new(0.5, 0.5)
	keyline.Position = UDim2.fromScale(0.5, 0.5)
	keyline.Size = UDim2.new(1, -8, 1, -8)
	keyline.BackgroundTransparency = 1
	keyline.BorderSizePixel = 0
	keyline.Active = false
	keyline.ZIndex = frame.ZIndex
	keyline.Parent = frame
	UITheme.corner(keyline, 6)
	local line = Instance.new("UIStroke")
	line.Thickness = 2
	line.Color = KEYLINE
	line.Transparency = 0.55
	line.Parent = keyline
end

-- Short-viewport guard: shrink and push the panel down so it never covers the
-- top TabBar band (146px) and keeps a 40px bottom margin. Anchor stays (0.5, 0.5).
local hudScale = Instance.new("UIScale")
hudScale.Name = "HudFixScale"
hudScale.Parent = frame
local function relayout()
	local vh = gui.AbsoluteSize.Y
	if vh <= 0 then return end
	local s = math.min(1, (vh - 146 - 40) / FRAME_H)
	hudScale.Scale = s
	-- clamp so the panel's top edge sits at or below the 146px band
	frame.Position = UDim2.new(0.5, 0, 0.5, math.max(0, 146 + FRAME_H * s / 2 - vh / 2))
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
relayout()

-- header bar: the guide's ONE red, every merchant (the per-merchant Accent
-- gradient is gone -- see rebuild()), title wordmark centred, clipped to the
-- panel's rounded top by its own corner
local headerBar = Instance.new("Frame")
headerBar.Name = "HeaderBar"
headerBar.Size = UDim2.new(1, 0, 0, HEADER_H)
headerBar.Position = UDim2.fromOffset(0, 0)
headerBar.BackgroundColor3 = HEADER_TOP
headerBar.BorderSizePixel = 0
headerBar.ZIndex = 12
headerBar.Parent = frame
UITheme.corner(headerBar, 8)   -- guide: matches the panel's own 8 (was 22)
local headerGrad = Instance.new("UIGradient")
headerGrad.Rotation = 90
headerGrad.Color = ColorSequence.new(HEADER_TOP, HEADER_BOT)
headerGrad.Parent = headerBar
do
	-- square off the header's bottom corners: a plain strip overlapping its
	-- lower half, carrying the gradient's bottom colour band. Height follows
	-- the corner down (16 -> 10) now that the corner is the guide's 8.
	local squareOff = Instance.new("Frame")
	squareOff.Name = "SquareOff"
	squareOff.AnchorPoint = Vector2.new(0, 1)
	squareOff.Position = UDim2.new(0, 0, 1, 0)
	squareOff.Size = UDim2.new(1, 0, 0, 10)
	squareOff.BackgroundColor3 = HEADER_TOP:Lerp(HEADER_BOT, 0.7)
	squareOff.BorderSizePixel = 0
	squareOff.ZIndex = 12
	squareOff.Parent = headerBar
end
local headerInk = Instance.new("UIStroke")
headerInk.Thickness = 3
headerInk.Color = OUTLINE
headerInk.Transparency = 0.05
headerInk.Parent = headerBar

local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.new(0.5, 0, 0.5, 0)
title.Size = UDim2.new(1, -140, 1, 0)
title.BackgroundTransparency = 1
title.Font = FONT
title.TextSize = 30
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Text = "SHOPS"
title.ZIndex = 14
title.Parent = headerBar
inkText(title, 3)

-- mock close: 48px red circle overlapping the top-right corner, white ring
local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseButton"
closeBtn.AnchorPoint = Vector2.new(0.5, 0.5)
closeBtn.Position = UDim2.new(1, -8, 0, 8)
closeBtn.Size = UDim2.fromOffset(48, 48)
closeBtn.Text = "\u{2715}"
closeBtn.TextSize = 20
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.AutoButtonColor = false
closeBtn.BackgroundColor3 = CLOSE_TOP
closeBtn.BorderSizePixel = 0
closeBtn.Font = FONT
closeBtn.ZIndex = 18
closeBtn.Parent = frame
UITheme.corner(closeBtn, 24)
do
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(CLOSE_TOP, CLOSE_BOT)
	grad.Parent = closeBtn
	-- the white ring was already the guide's keyline; named as such now
	local ring = Instance.new("UIStroke")
	ring.Thickness = 3.5
	ring.Color = KEYLINE
	ring.Parent = closeBtn
end
inkText(closeBtn, 2.5)
-- mock hover: scale 1.12 + rotate 90deg. Size+Rotation only (UIScale tweens
-- are dead in this place; Rotation is verified live).
local TweenService = game:GetService("TweenService")
closeBtn.MouseEnter:Connect(function()
	TweenService:Create(closeBtn, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(54, 54), Rotation = 90 }):Play()
end)
closeBtn.MouseLeave:Connect(function()
	TweenService:Create(closeBtn, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(48, 48), Rotation = 0 }):Play()
end)

local blurb = Instance.new("TextLabel")
blurb.Name = "Blurb"
blurb.Size = UDim2.new(1, -44, 0, BLURB_H)
blurb.Position = UDim2.new(0, 22, 0, HEADER_H + 8)
blurb.BackgroundTransparency = 1
blurb.Font = Enum.Font.GothamMedium
blurb.TextSize = 13
-- the one label that sits straight on the light window, so it keeps dark ink
blurb.TextColor3 = TEXT_ON_WINDOW
blurb.ZIndex = 12
blurb.Parent = frame

---------------------------------------------------------------- page chips (mock tab row, driving the pager)
local chipRow = Instance.new("Frame")
chipRow.Name = "PageChips"
chipRow.AnchorPoint = Vector2.new(0.5, 0)
chipRow.Position = UDim2.new(0.5, 0, 0, HEADER_H + 8 + BLURB_H + 6)
chipRow.Size = UDim2.new(1, -44, 0, CHIPS_H)
chipRow.BackgroundTransparency = 1
chipRow.ZIndex = 14
chipRow.Parent = frame
local chipList = Instance.new("UIListLayout")
chipList.FillDirection = Enum.FillDirection.Horizontal
chipList.HorizontalAlignment = Enum.HorizontalAlignment.Center
chipList.VerticalAlignment = Enum.VerticalAlignment.Center
chipList.SortOrder = Enum.SortOrder.LayoutOrder
chipList.Padding = UDim.new(0, 10)
chipList.Parent = chipRow

local rebuild -- forward-declared; chips call it on page change

local function renderPageChips(totalPages)
	for _, c in ipairs(chipRow:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	chipRow.Visible = totalPages > 1
	if totalPages <= 1 then return end
	for n = 1, totalPages do
		local active = n == page
		local chip = Instance.new("TextButton")
		chip.Name = "PageChip" .. n
		chip.LayoutOrder = n
		chip.Size = UDim2.fromOffset(64, 34)
		chip.AutoButtonColor = false
		chip.Text = "PAGE " .. n
		chip.TextSize = 14
		chip.Font = FONT
		chip.BorderSizePixel = 0
		chip.ZIndex = 15
		chip.Parent = chipRow
		UITheme.corner(chip, 10)   -- guide: chip 10 (was 12)
		if active then
			-- gold selected tab: identity, untouched by the style replacement
			chip.BackgroundColor3 = TAB_GOLD_TOP
			local grad = Instance.new("UIGradient")
			grad.Rotation = 90
			grad.Color = ColorSequence.new(TAB_GOLD_TOP, TAB_GOLD_BOT)
			grad.Parent = chip
			chip.TextColor3 = Color3.fromRGB(255, 255, 255)
			local ink = Instance.new("UIStroke")
			ink.Thickness = 3
			ink.Color = OUTLINE
			ink.Transparency = 0.05
			ink.Parent = chip
			inkText(chip, 2)
		else
			-- unselected tab was white + tan; it is the guide's dark slot now,
			-- which is also what makes the gold active chip pop off the row
			chip.BackgroundColor3 = SLOT_TOP
			local grad = Instance.new("UIGradient")
			grad.Rotation = 90
			grad.Color = ColorSequence.new(SLOT_TOP, SLOT_BOT)
			grad.Parent = chip
			chip.TextColor3 = SLOT_MUTED
			local border = Instance.new("UIStroke")
			border.Thickness = 3
			border.Color = OUTLINE
			border.Parent = chip
			chip.Activated:Connect(function()
				page = n
				rebuild()
			end)
		end
	end
end

---------------------------------------------------------------- card grid
local list = Instance.new("ScrollingFrame")
list.Name = "CardGrid"
list.Size = UDim2.new(1, -44, 0, 398)   -- one 3x2 page (2 rows of 192 + 14 gap); no in-page scroll
list.Position = UDim2.new(0, 22, 0, GRID_TOP)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ZIndex = 11
list.Parent = frame
local layout = Instance.new("UIGridLayout")
layout.CellSize = UDim2.fromOffset(200, 192)
layout.CellPadding = UDim2.fromOffset(14, 14)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = list

---------------------------------------------------------------- card builder (guide dark slot)
-- Signature kept close to the old makeRow so rebuild()'s item closures stay
-- recognisable: order, name, infoLine, button spec, click, preview builder,
-- optional price (nil hides the price row), optional statLine (upgrades).
local function makeCard(order, name, infoLine, btnText, btnTop, btnBot, onClick, previewBuilder, price, statLine)
	local card = Instance.new("Frame")
	card.Name = "Card" .. order
	card.LayoutOrder = order
	-- style replacement: flat white + tan border -> the guide's dark slot
	-- gradient + #202020 outline. Still ONE stroke on the card.
	card.BackgroundColor3 = SLOT_TOP
	card.BorderSizePixel = 0
	card.ZIndex = 12
	card.Parent = list
	UITheme.corner(card, 8)   -- guide: slots 8 (was 18)
	do
		local grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Color = ColorSequence.new(SLOT_TOP, SLOT_BOT)
		grad.Parent = card
	end
	local border = Instance.new("UIStroke")
	border.Thickness = 3
	border.Color = OUTLINE
	border.Parent = card

	-- icon tile: dark display case holding the 3D preview (or a glyph)
	local icon = Instance.new("Frame")
	icon.Name = "IconTile"
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 10)
	icon.Size = UDim2.fromOffset(72, 72)
	icon.BackgroundColor3 = Color3.fromRGB(26, 30, 40)
	icon.BorderSizePixel = 0
	icon.ClipsDescendants = true
	icon.ZIndex = card.ZIndex + 1
	icon.Parent = card
	UITheme.corner(icon, 8)   -- guide: art 8 (was 12)
	do
		-- the display case is darker than the slot it now sits in, so the tan
		-- rim becomes the guide's white keyline -- a #202020 rim would vanish
		local rim = Instance.new("UIStroke")
		rim.Thickness = 2
		rim.Color = KEYLINE
		rim.Transparency = 0.4
		rim.Parent = icon
	end
	if previewBuilder then
		previewBuilder(icon)
	end

	local n = Instance.new("TextLabel")
	n.Name = "Name"
	n.Size = UDim2.new(1, -16, 0, 20)
	n.Position = UDim2.new(0, 8, 0, 86)
	n.BackgroundTransparency = 1
	n.Font = FONT
	n.TextSize = 16
	n.TextXAlignment = Enum.TextXAlignment.Center
	n.TextTruncate = Enum.TextTruncate.AtEnd
	n.TextColor3 = SLOT_TEXT
	n.Text = name
	n.ZIndex = card.ZIndex + 2
	n.Parent = card

	-- two wrapped lines, not one truncated one: an upgrade's desc + level
	-- stat ("Better rarity rolls  Lv. 3/12 +15%") never fits 184px at 11px
	-- (review catch); rocks use a single line and are unaffected
	local info = Instance.new("TextLabel")
	info.Name = "Info"
	info.Size = UDim2.new(1, -16, 0, 28)
	info.Position = UDim2.new(0, 8, 0, 104)
	info.BackgroundTransparency = 1
	info.Font = Enum.Font.GothamMedium
	info.TextSize = 11
	info.TextXAlignment = Enum.TextXAlignment.Center
	info.TextYAlignment = Enum.TextYAlignment.Top
	info.TextWrapped = true
	info.TextTruncate = Enum.TextTruncate.AtEnd
	info.TextColor3 = SLOT_MUTED
	info.Text = statLine and (infoLine .. "  \u{2022}  " .. statLine) or infoLine
	info.ZIndex = card.ZIndex + 2
	info.Parent = card

	-- price row (mock: coin + amber amount), hidden when price is nil
	if price then
		local priceRow = Instance.new("Frame")
		priceRow.Name = "PriceRow"
		priceRow.AnchorPoint = Vector2.new(0.5, 0)
		priceRow.Position = UDim2.new(0.5, 0, 0, 122)
		priceRow.Size = UDim2.fromOffset(120, 18)
		priceRow.BackgroundTransparency = 1
		priceRow.ZIndex = card.ZIndex + 2
		priceRow.Parent = card
		local coin = Instance.new("ImageLabel")
		coin.Name = "Coin"
		coin.AnchorPoint = Vector2.new(1, 0.5)
		coin.Position = UDim2.new(0.5, -34, 0.5, 0)
		coin.Size = UDim2.fromOffset(18, 18)
		coin.BackgroundTransparency = 1
		coin.ScaleType = Enum.ScaleType.Fit
		coin.ZIndex = priceRow.ZIndex + 1
		coin.Parent = priceRow
		-- the kit's imported coin art; falls back to a plain gold dot if the
		-- Tokens module or its icon id is ever unavailable
		local okCoin = pcall(function()
			local T = require(ReplicatedStorage.Modules.UIKit.Tokens)
			coin.Image = T.icons.coin
		end)
		if not okCoin or coin.Image == "" then
			coin.BackgroundTransparency = 0
			coin.BackgroundColor3 = Color3.fromHex("#ffc531")
			UITheme.corner(coin, 9)
		end
		local amount = Instance.new("TextLabel")
		amount.Name = "Amount"
		amount.AnchorPoint = Vector2.new(0, 0.5)
		amount.Position = UDim2.new(0.5, -28, 0.5, 0)
		amount.Size = UDim2.fromOffset(90, 18)
		amount.BackgroundTransparency = 1
		amount.Font = FONT
		amount.TextSize = 15
		amount.TextXAlignment = Enum.TextXAlignment.Left
		amount.TextColor3 = PRICE_AMBER
		amount.Text = "$" .. short(price)
		amount.ZIndex = priceRow.ZIndex + 1
		amount.Parent = priceRow
	end

	-- chunky action button (mock BUY): gradient fill, ink border, hard shadow
	local shadow = Instance.new("Frame")
	shadow.Name = "BtnShadow"
	shadow.AnchorPoint = Vector2.new(0.5, 1)
	shadow.Position = UDim2.new(0.5, 0, 1, -8)
	shadow.Size = UDim2.new(1, -24, 0, 34)
	shadow.BackgroundColor3 = Color3.fromHex("#1c7a2e")
	shadow.BackgroundTransparency = 0.1
	shadow.BorderSizePixel = 0
	shadow.ZIndex = card.ZIndex + 1
	shadow.Parent = card
	UITheme.corner(shadow, 12)

	local b = Instance.new("TextButton")
	b.Name = "ActionButton"
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = UDim2.new(0.5, 0, 1, -12)
	b.Size = UDim2.new(1, -24, 0, 34)
	b.Text = btnText
	b.TextSize = 16
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.AutoButtonColor = false
	b.BackgroundColor3 = btnTop
	b.BorderSizePixel = 0
	b.Font = FONT
	b.ZIndex = card.ZIndex + 2
	b.Parent = card
	UITheme.corner(b, 12)   -- guide: buttons 10-14, already in band
	do
		local grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Color = ColorSequence.new(btnTop, btnBot)
		grad.Parent = b
		local ink = Instance.new("UIStroke")
		ink.Thickness = 3
		ink.Color = OUTLINE
		ink.Transparency = 0.05
		ink.Parent = b
	end
	inkText(b, 2.2)
	-- shadow tint follows the button's own dark shade
	shadow.BackgroundColor3 = btnBot:Lerp(BLACK, 0.35)
	if onClick then
		b.Activated:Connect(onClick)
		-- mock hover lift: -2px, Position-driven
		b.MouseEnter:Connect(function()
			TweenService:Create(b, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = UDim2.new(0.5, 0, 1, -14) }):Play()
		end)
		b.MouseLeave:Connect(function()
			TweenService:Create(b, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = UDim2.new(0.5, 0, 1, -12) }):Play()
		end)
	end
	return card
end

---------------------------------------------------------------- rebuild
rebuild = function()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	if not current then chipRow.Visible = false; return end
	title.Text = titleWord(current.Title)
	blurb.Text = current.Npc .. "  \u{2022}  " .. current.Blurb
	-- style replacement (2026-08-04, Pet-Sim guide): the header no longer
	-- repaints itself from current.Accent -- the guide gives shop chrome ONE
	-- red, so headerGrad/SquareOff keep the colours they were built with and
	-- every merchant shares the bar. current.Accent is still live data and is
	-- still read where it means something (MerchantDialog.Show, below).

	-- Build a flat list of render closures so pagination is Kind-agnostic: each entry
	-- draws exactly one card when called with its on-page order (1..PER_PAGE).
	local items = {}
	if current.Kind == "Rock" then
		for i, rock in ipairs(RockConfig) do
			local owned = state.OwnedRocks[rock.Id]
			local equipped = state.EquippedRock == rock.Id
			-- SEQUENTIAL UNLOCK: buyable only once the previous rock is owned
			local prevRock = RockConfig[i - 1]
			local unlocked = (i == 1) or (prevRock ~= nil and state.OwnedRocks[prevRock.Id] == true)
			items[i] = function(order)
				local txt, top, bot, cb, price
				if equipped then
					txt, top, bot = "EQUIPPED", DONE_TOP, DONE_BOT
				elseif owned then
					txt, top, bot = "EQUIP", EQUIP_TOP, EQUIP_BOT
					cb = function() remotes.EquipRock:FireServer(rock.Id) end
				elseif not unlocked then
					txt, top, bot = "LOCKED", LOCK_TOP, LOCK_BOT
					-- no cb -> disabled button
				else
					txt, top, bot = "BUY", BUY_TOP, BUY_BOT
					price = rock.Price
					cb = function() remotes.BuyRock:FireServer(rock.Id) end
				end
				local desc = ("Up to %dm  \u{2022}  %.2fx luck"):format(rock.MaxDistance, rock.Luck)
				if not owned and not unlocked and prevRock then
					desc = ("Buy the %s first"):format(prevRock.Id)
				end
				makeCard(order, rock.Id, desc, txt, top, bot, cb,
					function(med) makeRockViewport(med, rock) end, price)
			end
		end
	elseif current.Kind == "Upgrade" then
		for i, up in ipairs(UpgradeConfig.List) do
			items[i] = function(order)
				local lvl = UpgradeConfig.Level(state.Upgrades, up.Id)
				local price = UpgradeConfig.Price(up.Id, lvl)
				local pct = math.floor(lvl * up.PerLevel * 100 + 0.5)
				local txt, top, bot, cb
				if not price then
					txt, top, bot = "MAXED", LOCK_TOP, LOCK_BOT
				else
					txt, top, bot = "BUY", BUY_TOP, BUY_BOT
					cb = function() remotes.BuyUpgrade:FireServer(up.Id) end
				end
				makeCard(order, up.Name, up.Desc, txt, top, bot, cb,
					function(holder)
						local e = Instance.new("TextLabel")
						e.Size = UDim2.fromScale(1, 1)
						e.BackgroundTransparency = 1
						e.Font = FONT
						e.TextSize = 40
						e.Text = up.Icon
						e.ZIndex = holder.ZIndex + 1
						e.Parent = holder
					end,
					price, ("Lv. %d/%d  +%d%%"):format(lvl, up.MaxLevel, pct))
			end
		end
	end

	-- render only the current page
	local total = #items
	local totalPages = math.max(1, math.ceil(total / PER_PAGE))
	page = math.clamp(page, 1, totalPages)
	local startI = (page - 1) * PER_PAGE + 1
	local order = 0
	for i = startI, math.min(startI + PER_PAGE - 1, total) do
		order += 1
		items[i](order)
	end

	renderPageChips(totalPages)
end

---------------------------------------------------------------- open / close
-- open to the page holding your next rock to buy, not always page 1
local function firstRelevantPage(m)
	if m.Kind == "Rock" then
		for i, rock in ipairs(RockConfig) do
			if not state.OwnedRocks[rock.Id] then return math.ceil(i / PER_PAGE) end
		end
	end
	return 1
end

local function openMerchant(m)
	current = m
	page = firstRelevantPage(m)
	local shop = gui:FindFirstChild("ShopFrame"); if shop then shop.Visible = false end
	local sell = gui:FindFirstChild("SellFrame"); if sell then sell.Visible = false end
	local idx = gui:FindFirstChild("IndexFrame"); if idx then idx.Visible = false end
	rebuild()
	frame.Visible = true
end
local function closeMerchant()
	frame.Visible = false
	current = nil
	-- clicking the X means the cursor was ON it -- MouseLeave never fires for
	-- a hidden button, so the hover pose (54px, 90deg) would stick for the
	-- next open (review catch). Snap the rest pose back explicitly.
	closeBtn.Size = UDim2.fromOffset(48, 48)
	closeBtn.Rotation = 0
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
local promptParts = {}          -- [Id] = { part, part, ... }
local function bindStall(m, stallName)
	task.spawn(function()
		local stall = gameWorld:WaitForChild(stallName, 30)
		if not stall then return end
		local part = stall:WaitForChild("PromptPart", 30)
		if not part then return end
		local prompt = part:WaitForChild(m.Prompt, 30)
		if not prompt then return end
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
				MerchantDialog.Show(m.Npc, m.Dialogue, m.Accent, function() openMerchant(m) end, part)
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
	-- nearest, not first: the same merchant now exists in two worlds 11k studs apart
	local nearest = math.huge
	for _, part in ipairs(list) do
		nearest = math.min(nearest, (hrp.Position - part.Position).Magnitude)
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
