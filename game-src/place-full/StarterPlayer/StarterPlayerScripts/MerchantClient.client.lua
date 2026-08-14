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
	return WorldProgression.RocksFor(currentWorld)
end
local page = 1
local PER_PAGE = 6   -- mock 1d: 3x2 grid per page (was 2x4 of 8)

---------------------------------------------------------------- palette (2026-08-06 Bazaar restyle)
-- Panel/header/close/card chrome now comes straight from UITheme.Bazaar
-- (BZ, above). Only the state-identity colours Bazaar's palette has no slot
-- for -- LOCKED/MAXED gray, the gold active page chip -- stay as literals.
-- LemonPop 2026-08-13: cool grays land as dead spots on the lemon panel --
-- locked state takes the theme's warm-taupe disabled family instead
local LOCK_TOP = Color3.fromHex("#8A7C5E") -- LOCKED/MAXED (was cool gray 150,156,170)
local LOCK_BOT = Color3.fromHex("#5C5138") -- (was 94,100,114)
local TAB_GOLD_TOP = Color3.fromHex("#ffdf5e") -- active pager chip: gold is the selected-tab identity
local TAB_GOLD_BOT = Color3.fromHex("#f7a721")

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
	vp.BackgroundColor3 = Color3.fromHex("#FFF4D9") -- LemonPop light art well (was dark 26,30,40)
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

---------------------------------------------------------------- panel (mock 1d)
local FRAME_W, FRAME_H = 680, 620
local HEADER_H = 54   -- bazaarHeader's own footprint: 10px inset + 44px bar
local BLURB_H = 20
local CHIPS_H = 38
local GRID_TOP = HEADER_H + 8 + BLURB_H + 6 + CHIPS_H + 6

local frame = Instance.new("Frame")
frame.Name = "MerchantFrame"
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.new(0.5, 0, 0.5, 0)
frame.Size = UDim2.fromOffset(FRAME_W, FRAME_H)
frame.Visible = false
frame.ZIndex = 10
frame.Parent = gui
-- The rail sits at DisplayOrder 6 and this panel at 0; registering it means
-- the legacy rail folds away while the shop is open (single-open registry).
SideRail.registerPanel(frame)
UITheme.bazaarPanel(frame)   -- dark gradient stall-shop panel body

-- Viewport fit, CENTRED.
--
-- This used to reserve a 146px band at the top so the panel never covered the
-- TabBar, and pushed itself down below it. That cost a quarter of the height on a
-- short window: measured at 940x568 the panel was forced to 0.616 scale and sat
-- 53px below centre, which is what "the shop is low on the screen and the text is
-- tiny" was -- 16px body text rendering at ~10px.
--
-- A shop is a MODAL. Covering the nav band while it is open is fine and is what
-- every other panel in the game does; what is not fine is shrinking the whole
-- panel to dodge it. Fit the full viewport with an even margin and sit dead centre.
-- THE SIZE KNOB. Fraction of the viewport the panel is allowed to occupy.
-- 1.0 fits it to the screen edge-to-edge (too big -- it read as full-screen);
-- the old behaviour was effectively ~0.6 with a 146px band reserved on top
-- (too small -- 16px body text rendered at ~10px). Turn this one number.
local FILL = 0.76
local hudScale = Instance.new("UIScale")
hudScale.Name = "HudFixScale"
hudScale.Parent = frame

-- Centre on the MEASURED rect, not a predicted one. Two things make the position
-- hard to predict here: layout positions the frame from its UNSCALED size while
-- UIScale draws it scaled, and this ScreenGui carries ScreenInsets, so the canvas
-- is not always the screen. Reading back what actually rendered sidesteps both.
local function recentre()
	-- Retries across frames and ignores a zero-size read: at script load the frame
	-- has not been laid out yet, and an early pass saw a delta of ~0, returned, and
	-- left the panel 58px high for the whole session.
	for _ = 1, 8 do
		local h = frame.AbsoluteSize.Y
		if h > 0 then
			local vpY = workspace.CurrentCamera.ViewportSize.Y
			local delta = vpY / 2 - (frame.AbsolutePosition.Y + h / 2)
			if math.abs(delta) < 1 then return end
			frame.Position = frame.Position + UDim2.fromOffset(0, delta)
		end
		task.wait()
	end
end

local function relayout()
	local vh, vw = gui.AbsoluteSize.Y, gui.AbsoluteSize.X
	if vh <= 0 or vw <= 0 then return end
	-- capped at 1: the panel is authored at its true pixel size, and upscaling
	-- magnifies the ink strokes along with the text
	local s = math.min(1, (vh * FILL) / FRAME_H, (vw * FILL) / FRAME_W)
	hudScale.Scale = s
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	task.defer(recentre)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
relayout()
-- Re-centre whenever the panel is actually shown. Startup layout is the unreliable
-- moment; the instant it becomes visible, the rect is real.
frame:GetPropertyChangedSignal("Visible"):Connect(function()
	if frame.Visible then task.defer(recentre) end
end)

-- inset bronze-gradient header bar (Bazaar chrome): small coin glyph + white
-- title. Per-merchant Accent recolour stays dropped, but the whole panel now
-- gets its OWN identity colour (bronze/gold, fitting a rock+upgrade market
-- stall) instead of sharing the plain cyan every other Bazaar panel used to.
local headerBar, title = UITheme.bazaarHeader(frame, "SHOPS", "\u{1F4B0}", BZ.rockHeader1, BZ.rockHeader2)

-- round red X, top-right corner of the panel (Bazaar chrome)
local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseButton"
closeBtn.Parent = frame
UITheme.bazaarClose(closeBtn)

local blurb = Instance.new("TextLabel")
blurb.Name = "Blurb"
blurb.Size = UDim2.new(1, -44, 0, BLURB_H)
blurb.Position = UDim2.new(0, 22, 0, HEADER_H + 8)
blurb.BackgroundTransparency = 1
blurb.Font = Enum.Font.GothamMedium
blurb.TextSize = 13
blurb.TextColor3 = BZ.desc   -- panel body is dark now, so the blurb reads light gray
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
		UITheme.corner(chip, 10)
		if active then
			-- gold selected tab: identity, kept through the Bazaar restyle
			chip.BackgroundColor3 = TAB_GOLD_TOP
			UITheme.gradient(chip, TAB_GOLD_TOP, TAB_GOLD_BOT, 90)
			chip.TextColor3 = BZ.white
			local ink = Instance.new("UIStroke")
			ink.Color = BZ.ink; ink.Thickness = 2
			ink.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			ink.Parent = chip
		else
			-- unselected tab: Bazaar's dark card gradient, so the gold active
			-- chip still pops off the row
			chip.BackgroundColor3 = BZ.cardTop
			UITheme.gradient(chip, BZ.cardTop, BZ.cardBot, 90)
			chip.TextColor3 = BZ.muted
			local border = Instance.new("UIStroke")
			border.Color = BZ.cardEdge; border.Thickness = 2
			border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
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

---------------------------------------------------------------- card builder (Bazaar dark bordered card)
-- Signature kept close to the old makeRow so rebuild()'s item closures stay
-- recognisable: order, name, infoLine, button spec (+ its text colour),
-- click, preview builder, optional statLine (upgrades), optional stockText
-- (a red bazaarStock warning line, e.g. sequential-unlock "buy the previous
-- rock first"). Price is no longer a separate row -- it is embedded in
-- btnText as a cash pill, matching ClientMain's rockRows/sellList pattern.
local function makeCard(order, name, infoLine, btnText, btnTop, btnBot, textColor, onClick, previewBuilder, statLine, stockText)
	local card = UITheme.bazaarRow(list, 192)
	card.Name = "Card" .. order
	card.LayoutOrder = order
	card.ZIndex = 12

	-- icon tile: dark display case holding the 3D preview (or a glyph),
	-- top-centred instead of bazaarIconSlot's default left-middle so it
	-- still reads as a card inside the 3x2 grid
	local icon = UITheme.bazaarIconSlot(card, 72)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 10)
	if previewBuilder then
		previewBuilder(icon)
	end

	local n = UITheme.bazaarTitle(card, name)
	n.Size = UDim2.new(1, -16, 0, 20)
	n.Position = UDim2.new(0, 8, 0, 86)
	n.TextSize = 16
	n.TextXAlignment = Enum.TextXAlignment.Center

	-- two wrapped lines, not one truncated one: an upgrade's desc + level
	-- stat ("Better rarity rolls  Lv. 3/12 +15%") never fits 184px at 11px
	-- (review catch); rocks use a single line and are unaffected
	local info = UITheme.bazaarDesc(card, statLine and (infoLine .. "  \u{2022}  " .. statLine) or infoLine)
	info.Size = UDim2.new(1, -16, 0, 28)
	info.Position = UDim2.new(0, 8, 0, 104)
	info.TextSize = 11
	info.TextXAlignment = Enum.TextXAlignment.Center

	-- optional red warning line (sequential-unlock "buy the previous rock first")
	if stockText then
		local stock = UITheme.bazaarStock(card, stockText)
		stock.Size = UDim2.new(1, -16, 0, 14)
		stock.Position = UDim2.new(0, 8, 0, 132)
		stock.TextSize = 10
		stock.TextXAlignment = Enum.TextXAlignment.Center
	end

	-- chunky action / price pill (mock BUY): Bazaar cash/state gradient
	local b = Instance.new("TextButton")
	b.Name = "ActionButton"
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = UDim2.new(0.5, 0, 1, -12)
	b.Size = UDim2.new(1, -24, 0, 34)
	b.Text = btnText
	b.TextSize = 16
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
				local stockText = (not owned and not unlocked and prevRock) and ("Buy the %s first"):format(prevRock.Id) or nil
				makeCard(order, rock.Id, desc, txt, top, bot, textColor, cb,
					function(med) makeRockViewport(med, rock) end, nil, stockText)
			end
		end
	elseif current.Kind == "Upgrade" then
		for i, up in ipairs(UpgradeConfig.List) do
			items[i] = function(order)
				local lvl = UpgradeConfig.Level(state.Upgrades, up.Id)
				local price = UpgradeConfig.Price(up.Id, lvl)
				local pct = math.floor(lvl * up.PerLevel * 100 + 0.5)
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
					("Lv. %d/%d  +%d%%"):format(lvl, up.MaxLevel, pct))
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
		for i, rock in ipairs(shelf()) do
			if not state.OwnedRocks[rock.Id] then return math.ceil(i / PER_PAGE) end
		end
	end
	return 1
end

local function openMerchant(m, world)
	current = m
	currentWorld = world or WorldProgression.Default
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
