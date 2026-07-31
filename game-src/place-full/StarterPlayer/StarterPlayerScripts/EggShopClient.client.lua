-- EggShopClient -- Forest Egg Shop panel: 5-egg buy list with data-driven odds,
-- a darrel chip, and the daily-quest mini list. Opens via the EggStall's
-- ProximityPrompt on the client (server never gates the OPEN, only the BUY).
--
-- ODDS ARE ALWAYS VISIBLE AND NEVER HARD-CODED: every percentage rendered here
-- comes from iterating EggConfig's own egg.Table at runtime -- the server rolls
-- from those exact same rows (EggHandler.RollFor), so shown odds can never
-- drift from real odds (Roblox requires published odds for paid random items).
--
-- playReveal(result), further down, plays the hatch animation (Task 8):
-- shake -> crack -> tier-lit creature spin -> skip/fade. Everything around it
-- (buy -> disable -> result -> reopen) is unrelated and untouched by that task.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local EggConfig = require(ReplicatedStorage.Modules.EggConfig)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local SideRail = require(ReplicatedStorage.Modules.SideRail)
local BrainrotThumb = require(ReplicatedStorage.Modules.BrainrotThumb)
local RarityFX = require(ReplicatedStorage.Modules.RarityFX)
local SoundKit = require(ReplicatedStorage.Modules.SoundKit)
-- Darrel's face, drawn from primitives (UIKit.IconArt). pcall'd so a missing
-- module leaves the shop working with the old emoji rather than failing to open.
local okIconArt, IconArt = pcall(function()
	return require(ReplicatedStorage.Modules.UIKit.IconArt)
end)
if not okIconArt then IconArt = nil end

-- The kit itself. NOT pcall'd, unlike IconArt: the panel's shell, header and
-- rows are built out of these, so a failure here is not a degraded icon, it is
-- no shop at all -- better to throw at require time than to nil-index halfway
-- through building the panel.
local T = require(ReplicatedStorage.Modules.UIKit.Tokens)
local UI = require(ReplicatedStorage.Modules.UIKit.Builders)

local CF = UITheme.Camp
local FONT = UITheme.Font
local WORLD_ID = "Forest"
local world = EggConfig.GetWorld(WORLD_ID)

-- creature name -> tier colour, same lookup pattern BackpackClient/EggHandler use
local PetConfig = require(ReplicatedStorage.Modules.PetConfig)

local tierByName, rarityByName = {}, {}
for _, t in ipairs(RarityConfig) do tierByName[t.Name] = t end
for _, e in ipairs(BrainrotConfig.List or BrainrotConfig) do rarityByName[e.Name] = e.Rarity end

-- Egg tables name PETS as of 2026-08-01, so rarity resolves through PetConfig
-- first. The BrainrotConfig fallback is still live for the ten retired stand-in
-- pets, which are brainrots and have no PetConfig-only rarity of their own.
-- Pet tiers (Rare..Secret) all exist in RarityConfig, so the colour lookup is
-- unchanged either way.
local function rarityOf(creatureName)
	local id = PetConfig.IdFor(creatureName)
	local def = id and PetConfig.Pets[id]
	if def then return def.Rarity end
	return rarityByName[creatureName]
end

local function tierColor(creatureName)
	local tier = tierByName[rarityOf(creatureName)]
	return tier and tier.Color or CF.ink
end

-- The hatch reveal spins the PET that was just hatched. BrainrotThumb.master is
-- hardwired to ReplicatedStorage.BrainrotModels, so pets need their own lookup
-- against PetModels (child named after the imported .glb, per PetConfig.Model),
-- falling through to BrainrotThumb for the retired stand-ins. Masters are cached
-- per key exactly like BrainrotThumb does, so a reveal clones rather than
-- rebuilds.
local petMasters = {}
local function petMaster(creatureName, petId)
	local key = petId or creatureName
	if key and petMasters[key] then return petMasters[key] end
	local folder = ReplicatedStorage:FindFirstChild("PetModels")
	local def = petId and PetConfig.Pets[petId]
	local src = folder and ((def and def.Model and folder:FindFirstChild(def.Model))
		or (creatureName and folder:FindFirstChild(creatureName)))
	if src then
		local m = src:Clone()
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false end
		end
		if key then petMasters[key] = m end
		return m
	end
	return BrainrotThumb.master(creatureName)
end

---------------------------------------------------------------- tiny UI helper
local function new(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do inst[k] = v end
	inst.Parent = parent
	return inst
end

---------------------------------------------------------------- egg viewport
-- Eggs live in ReplicatedStorage.EggModels.Forest, a DIFFERENT folder from the
-- BrainrotModels folder BrainrotThumb.add() is hardwired to -- so eggs can't
-- go through .add() directly by name. Instead this reuses BrainrotThumb's own
-- public camera-framing maths (M.framing / M.DEFAULT_DIR) against a hand-cloned
-- egg model, so every 3D viewport in the game still shares one framing formula.
-- Eggs are static props (no spin), matching the brief's "no spin needed" note.
local eggFolder = ReplicatedStorage:WaitForChild("EggModels"):WaitForChild(WORLD_ID)
local eggMasterCache = {}
local function eggMaster(modelName)
	if eggMasterCache[modelName] == nil then
		local real = eggFolder:FindFirstChild(modelName)
		eggMasterCache[modelName] = real and real:Clone() or false
	end
	return eggMasterCache[modelName] or nil
end
local function addEggViewport(parent, modelName, opts)
	local master = eggMaster(modelName)
	if not master then return nil end
	opts = opts or {}
	local vp = new("ViewportFrame", {
		Size = opts.size or UDim2.fromScale(1, 1),
		Position = opts.position or UDim2.fromScale(0, 0),
		BackgroundTransparency = 1,
		ZIndex = opts.zIndex or 1,
	}, parent)
	local m = master:Clone()
	m.Parent = vp
	local fov = opts.fov or 32
	local centre, dist = BrainrotThumb.framing(m, fov)
	local cam = new("Camera", { FieldOfView = fov })
	cam.CFrame = CFrame.lookAt(centre + BrainrotThumb.DEFAULT_DIR * dist, centre)
	cam.Parent = vp
	vp.CurrentCamera = cam
	return vp
end

---------------------------------------------------------------- ScreenGui + panel
local gui = new("ScreenGui", {
	Name = "EggShopUI", DisplayOrder = 9, IgnoreGuiInset = false, ResetOnSpawn = false,
}, playerGui)

-- KIT RESTYLE (2026-08-01): the panel is now built from UIKit (README 3.1,
-- "Eggs Shop -- panel width 1080") so it matches the six HUD panels instead of
-- wearing the older campfire theme. Deliberately NOT in the kit's design:
--   * no biome chips -- EggConfig has one world, and a one-tab strip is worse
--     than no strip. The header renders chips only when a second world exists.
--   * no egg icon in the header, and none in the nav rail: eggs are reached
--     from the stall prompt and live in the inventory.
--   * no quests card -- the three darrel dailies are already the Goals panel's
--     Daily tab, so the copy here was a duplicate. Its column is gone and the
--     egg list takes the width back.
-- Everything below the reveal banner is untouched by this restyle.
local FRAME_W = T.size.panelWidth.eggs   -- 1080
local FRAME_H = 620

local frame = UI.panel(gui, UDim2.fromOffset(FRAME_W, FRAME_H))
frame.Name = "EggShopFrame"
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.new(0.5, 0, 0.5, 0)
frame.Visible = false
frame.ZIndex = 10
SideRail.registerPanel(frame)

-- UI.panel drops a hard shadow as a SIBLING of the panel, not a child (see
-- UIKit.Builders' UI.hardShadow: `sh.Parent = frame.Parent`), so it does NOT
-- inherit frame.Visible. Left alone that is an opaque 860x620 slab parked in
-- this ScreenGui at DisplayOrder 9 for the whole session, covering the game
-- while the shop is CLOSED -- which is exactly what it did.
--
-- Mirrored rather than re-parented on purpose: `frame` is what setOpen toggles
-- AND what the hatch reveal restores when it finishes, so it has to stay the
-- thing whose Visible means "the shop is open"; and moving the shadow inside
-- the frame would put it under UI.panel's own UIPadding and inset it.
local panelShadow = frame.Parent:FindFirstChild("HardShadow")
if panelShadow then
	panelShadow.Visible = frame.Visible
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		panelShadow.Visible = frame.Visible
	end)
end
-- The fit was hard-capped at 1x, so on any normal monitor the panel stopped dead at
-- its design 640x520 and read small -- there was headroom it simply refused to use.
-- Allow a modest upscale instead; still capped, because the UIScale magnifies the ink
-- strokes and text along with everything else.
-- The panel is now 1080 wide against a 640 design before, so the fit matters
-- more, not less: MAX_SCALE stays at 1 because a kit panel is authored at its
-- true pixel size and upscaling it magnifies the 4-5px strokes into slabs.
local MAX_SCALE = 1.0
local BOTTOM_MARGIN = 16
local hudScale = new("UIScale", { Name = "HudFixScale" }, frame)
local function relayout()
	local vh, vw = gui.AbsoluteSize.Y, gui.AbsoluteSize.X
	if vh <= 0 then return end
	local s = math.min(MAX_SCALE,
		(vh - 146 - BOTTOM_MARGIN) / FRAME_H,
		(vw - 32) / FRAME_W)
	hudScale.Scale = s
	frame.Position = UDim2.new(0.5, 0, 0.5, math.max(0, 146 + FRAME_H * s / 2 - vh / 2))
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
relayout()

---------------------------------------------------------------- header
-- Title left, balance right, close on the far right. The balance moved up here
-- from the old side column: with the quests card gone it was the only thing
-- left in a 176px gutter, and the kit puts currency in the panel chrome anyway
-- (README 1: the HUD currency cluster hides while a panel is open, so a panel
-- has to state the price currency itself).
local HEADER_H = T.size.headerHeight   -- 92
local BODY_PAD = 16

-- NOTE ON POSITIONING: UI.panel puts a UIPadding on the frame, so every child
-- below is laid out inside that inset box. Offsets here are therefore relative
-- to the padded content area, not to the panel's outer 1080x620 -- which is why
-- the header sits at x=0 rather than at a hand-written margin.
local headerTitle = UI.label(frame, "FOREST EGGS", "panelTitle", T.color.white)
headerTitle.Name = "Title"
headerTitle.AnchorPoint = Vector2.new(0, 0.5)
headerTitle.Position = UDim2.new(0, 0, 0, HEADER_H / 2)
headerTitle.Size = UDim2.fromOffset(420, 40)
headerTitle.TextXAlignment = Enum.TextXAlignment.Left
headerTitle.ZIndex = frame.ZIndex + 4

-- balance pill (README 3.1 side column: height 66, radius 16, goldSmall)
local BAL_W, BAL_H, BAL_ICON = 208, 66, 46
local balPill = UI.surface(frame, UDim2.fromOffset(BAL_W, BAL_H), "goldSmall", T.radius.control, T.stroke.control)
balPill.Name = "BalancePill"
balPill.AnchorPoint = Vector2.new(1, 0.5)
balPill.Position = UDim2.new(1, -(T.size.closeButton.X + 18), 0, HEADER_H / 2)
balPill.ZIndex = frame.ZIndex + 4
UI.gloss(balPill, T.radius.control)

local darrelIcon = new("Frame", {
	Name = "DarrelIcon",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 10, 0.5, 0),
	Size = UDim2.fromOffset(BAL_ICON, BAL_ICON),
	BackgroundTransparency = 1,
	ZIndex = balPill.ZIndex + 2,
}, balPill)
if IconArt and IconArt.has("darrel") then
	IconArt.draw(darrelIcon, "darrel", BAL_ICON, balPill.ZIndex + 2)
end

local darrelLabel = UI.label(balPill, "0", "value", T.color.textOnGoldChrome)
darrelLabel.Name = "Value"
darrelLabel.AnchorPoint = Vector2.new(0, 0.5)
darrelLabel.Position = UDim2.new(0, 10 + BAL_ICON + 10, 0.5, 0)
darrelLabel.Size = UDim2.fromOffset(BAL_W - (10 + BAL_ICON + 20), 30)
darrelLabel.TextXAlignment = Enum.TextXAlignment.Left
darrelLabel.ZIndex = balPill.ZIndex + 2

-- UI.button(parent, text, variant, size) -- text and size are NOT interchangeable
-- with each other's positions; passing them the other way round assigns a string
-- to Size and the panel dies half-built.
local closeBtn = UI.button(frame, "\u{2715}", "red",
	UDim2.fromOffset(T.size.closeButton.X, T.size.closeButton.Y))
closeBtn.Name = "Close"
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, 0, 0, HEADER_H / 2)
closeBtn.ZIndex = frame.ZIndex + 5

---------------------------------------------------------------- egg list
-- Full width now. The old layout split 640 into a 392 list and a 176 side
-- column; with quests gone there is no second column, so the list gets all of
-- it and an egg row can carry its art, name, price and action on one line.
-- Sized in SCALE against the padded content box rather than in absolute pixels:
-- UI.panel's own padding already supplies the margin, so subtracting it again
-- here would inset the list twice.
local list = new("ScrollingFrame", {
	Name = "EggList",
	Position = UDim2.fromOffset(0, HEADER_H),
	Size = UDim2.new(1, 0, 1, -HEADER_H),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = T.color.scrollThumb,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = frame.ZIndex + 3,
}, frame)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 12) }, list)

-- The three rotating darrel dailies used to live here in a 176px side column.
-- They are GONE from this panel (user, 2026-08-01): the Goals panel's Daily tab
-- already renders the same three quests from the same DarrelState payload, so
-- this was a second place to keep in sync for no gain. DarrelState still
-- carries .Daily; applyDarrel below simply ignores it now.

---------------------------------------------------------------- egg rows
-- Kit README 3.1: "Egg row -- height 80, radius 16, stroke 4, rowTop/rowBottom".
-- The pastel per-egg ACCENTS this replaces tinted the whole card, which made
-- five rows read as five unrelated screens and left the art slot fighting its
-- own background. In the kit the card is neutral and the COLOUR comes from the
-- rarity frame on the art -- "rarity is the egg's tier, so value reads before
-- the price does".
local ROW_H, ART = 80, 64

-- An egg's tier is the rarest pet it can produce. Derived from egg.Table rather
-- than authored, so it can never disagree with what the egg actually rolls.
local RARITY_RANK = { Rare = 1, Epic = 2, Legendary = 3, Mythic = 4, Secret = 5 }
local function eggTier(egg)
	local best, bestRank = nil, -1
	for _, tableRow in ipairs(egg.Table) do
		local r = rarityOf(tableRow[1])
		local rank = r and RARITY_RANK[r] or 0
		if rank > bestRank then best, bestRank = tableRow[1], rank end
	end
	return best
end

-- UI.button hardcodes its caption label to ZIndex 3 (Builders ~line 174). Every
-- kit panel lives in a ScreenGui set to ZIndexBehavior.Sibling, where a child
-- always draws above its parent and that 3 never matters. THIS ScreenGui is
-- Global (it predates the kit), so a caption at 3 renders UNDERNEATH its own
-- button at 15 and the button comes out blank -- which is exactly what happened.
-- Lifting the caption is the surgical fix; flipping the whole ScreenGui to
-- Sibling would also re-layer the hatch reveal, which is not ours to disturb.
--
-- The z argument is not optional sugar: the caption's ZIndex has to be derived
-- from the button's FINAL one, and callers set that after UI.button returns. A
-- first cut read b.ZIndex inside here and got the default 1, so captions ended
-- up at 2 and stayed buried under a button later moved to 15. Same eager-capture
-- trap Builders documents for the hover rest-position, one field over.
local function kitButton(parent, text, variant, size, z)
	local b = UI.button(parent, text, variant, size)
	b.ZIndex = z
	local cap = b:FindFirstChildWhichIsA("TextLabel")
	if cap then cap.ZIndex = z + 1 end
	return b, cap
end

local openButtons = {}
local buyLocked = false
-- Live balance, so a row can show whether it is affordable. applyDarrel feeds
-- this; refreshAffordability re-runs on every balance change.
--
-- darrelsKnown matters: DarrelState answers a pull that beats the DataStore load
-- with a PLACEHOLDER {Darrels = 0} (the same lying-zero GameHUDClient documents
-- at length), and a 0 we have not confirmed would paint every egg "too poor" on
-- open. Until a payload proves the profile is loaded, rows stay in the neutral
-- affordable look rather than asserting something we cannot back up.
local currentDarrels = 0
local darrelsKnown = false
local priceRows = {}   -- { chip, value, button, price }

local function fireBuy(egg)
	if buyLocked then return end
	buyLocked = true
	for _, b in ipairs(openButtons) do
		b.Active = false
		b.AutoButtonColor = false
	end
	remotes.EggBuy:FireServer(WORLD_ID, egg.Id)
	task.delay(0.6, function()
		buyLocked = false
		for _, b in ipairs(openButtons) do
			b.Active = true
			b.AutoButtonColor = true
		end
	end)
end

for i, egg in ipairs(world.Eggs) do
	local tint = tierColor(eggTier(egg))

	-- Wrapper carries the expansion; the CARD stays a fixed 80 so the collapsed
	-- list keeps the kit's even rhythm rather than five different heights.
	local row = new("Frame", {
		Name = "EggRow_" .. egg.Id,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = i,
		ZIndex = 12,
	}, list)
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, row)

	local card = UI.surface(row, UDim2.new(1, 0, 0, ROW_H), "row", T.radius.control, T.stroke.control)
	card.Name = "Card"
	card.LayoutOrder = 1
	card.ZIndex = 13
	UI.gloss(card, T.radius.control)

	-- art slot 64x64; the rarity frame is what carries the egg's colour
	local iconHolder = UI.surface(card, UDim2.fromOffset(ART, ART), "slot", T.radius.small, T.stroke.chip)
	iconHolder.Name = "Art"
	iconHolder.AnchorPoint = Vector2.new(0, 0.5)
	iconHolder.Position = UDim2.new(0, 12, 0.5, 0)
	iconHolder.ZIndex = card.ZIndex + 1
	local tierRing = Instance.new("UIStroke")
	tierRing.Color = tint
	tierRing.Thickness = 4
	tierRing.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	tierRing.Parent = iconHolder

	local vp = addEggViewport(iconHolder, egg.Model, {
		size = UDim2.new(1, -8, 1, -8), position = UDim2.fromOffset(4, 4), zIndex = card.ZIndex + 2,
	})
	if not vp then
		local sw = new("Frame", {
			Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4),
			BackgroundColor3 = tint, ZIndex = card.ZIndex + 2,
		}, iconHolder)
		UI.corner(sw, T.radius.art)
	end

	local nameLabel = UI.label(card, egg.Name, "cardLabel", T.color.white)
	nameLabel.Name = "EggName"
	nameLabel.Position = UDim2.new(0, 12 + ART + 12, 0, 14)
	nameLabel.Size = UDim2.fromOffset(240, 26)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.ZIndex = card.ZIndex + 1

	-- price chip (kit: height 30, radius 9, icon + value). Darrel's face leads
	-- the number, the same order the balance pill uses, so a player comparing
	-- price against balance sees the same mark in both places.
	local PRICE_ICON = 24
	local priceChip = new("Frame", {
		Name = "PriceChip",
		Position = UDim2.new(0, 12 + ART + 12, 0, 44),
		Size = UDim2.fromOffset(PRICE_ICON + 16 + 46, 30),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.68,
		ZIndex = card.ZIndex + 1,
	}, card)
	UI.corner(priceChip, T.radius.art)
	UI.stroke(priceChip, T.stroke.hairline)

	local priceIcon = new("Frame", {
		Name = "PriceIcon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.fromOffset(PRICE_ICON, PRICE_ICON),
		BackgroundTransparency = 1, ZIndex = priceChip.ZIndex + 1,
	}, priceChip)
	if IconArt and IconArt.has("darrel") then
		IconArt.draw(priceIcon, "darrel", PRICE_ICON, priceChip.ZIndex + 1)
	end

	local priceValue = UI.label(priceChip, tostring(egg.Price), "chip", T.color.white)
	priceValue.Name = "Value"
	priceValue.AnchorPoint = Vector2.new(0, 0.5)
	priceValue.Position = UDim2.new(0, 4 + PRICE_ICON + 6, 0.5, 0)
	priceValue.Size = UDim2.fromOffset(44, 20)
	priceValue.TextXAlignment = Enum.TextXAlignment.Left
	priceValue.ZIndex = priceChip.ZIndex + 1

	local openBtn = kitButton(card, "OPEN", "green", UDim2.fromOffset(112, 44), card.ZIndex + 2)
	openBtn.Name = "Open"
	openBtn.AnchorPoint = Vector2.new(1, 0.5)
	openBtn.Position = UDim2.new(1, -12, 0.5, 0)
	openBtn.Activated:Connect(function() fireBuy(egg) end)
	openButtons[#openButtons + 1] = openBtn

	local chevron, chevronCap = kitButton(card, "\u{25BC}", "tab", UDim2.fromOffset(44, 44), card.ZIndex + 2)
	chevron.Name = "OddsToggle"
	chevron.AnchorPoint = Vector2.new(1, 0.5)
	chevron.Position = UDim2.new(1, -132, 0.5, 0)

	priceRows[#priceRows + 1] = { chip = priceChip, value = priceValue, button = openBtn, price = egg.Price }

	-- ODDS ARE DATA-DRIVEN: every line below reads straight from egg.Table
	-- (EggConfig), the exact table EggHandler.RollFor rolls against server-side.
	-- No percentage is ever authored a second time in this file.
	local oddsHolder = UI.surface(row, UDim2.new(1, 0, 0, 0), "subPanel", T.radius.control, T.stroke.chip)
	oddsHolder.Name = "OddsPanel"
	oddsHolder.AutomaticSize = Enum.AutomaticSize.Y
	oddsHolder.Visible = false
	oddsHolder.LayoutOrder = 2
	oddsHolder.ZIndex = 13
	local oddsPad = Instance.new("UIPadding")
	oddsPad.PaddingTop = UDim.new(0, 10)
	oddsPad.PaddingBottom = UDim.new(0, 10)
	oddsPad.PaddingLeft = UDim.new(0, 12)
	oddsPad.PaddingRight = UDim.new(0, 12)
	oddsPad.Parent = oddsHolder
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, oddsHolder)

	local oddsHead = UI.label(oddsHolder, "INSIDE THE " .. egg.Name:upper(), "chip", T.color.textAccent)
	oddsHead.LayoutOrder = 0
	oddsHead.Size = UDim2.new(1, 0, 0, 20)
	oddsHead.TextXAlignment = Enum.TextXAlignment.Left
	oddsHead.ZIndex = oddsHolder.ZIndex + 1

	for j, tableRow in ipairs(egg.Table) do
		local creature, weight = tableRow[1], tableRow[2]
		local line = new("Frame", {
			Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1,
			LayoutOrder = j, ZIndex = oddsHolder.ZIndex + 1,
		}, oddsHolder)
		-- rarity pip, so the tier reads without parsing the name
		local pip = new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(10, 10), BackgroundColor3 = tierColor(creature),
			ZIndex = line.ZIndex + 1,
		}, line)
		UI.corner(pip, 5)
		local nameL = UI.label(line, creature, "meta", T.color.white)
		nameL.AnchorPoint = Vector2.new(0, 0.5)
		nameL.Position = UDim2.new(0, 20, 0.5, 0)
		nameL.Size = UDim2.new(1, -100, 0, 20)
		nameL.TextXAlignment = Enum.TextXAlignment.Left
		nameL.ZIndex = line.ZIndex + 1
		-- ODDS ARE DATA-DRIVEN: straight from egg.Table, the exact table
		-- EggHandler.RollFor rolls against. Never authored twice.
		local pct = UI.label(line, tostring(weight) .. "%", "meta", T.color.textAccent)
		pct.AnchorPoint = Vector2.new(1, 0.5)
		pct.Position = UDim2.new(1, 0, 0.5, 0)
		pct.Size = UDim2.fromOffset(70, 20)
		pct.TextXAlignment = Enum.TextXAlignment.Right
		pct.ZIndex = line.ZIndex + 1
	end

	chevron.Activated:Connect(function()
		oddsHolder.Visible = not oddsHolder.Visible
		-- UI.button puts the caption in a child Label, so setting .Text on the
		-- button itself would write to an empty string nobody renders.
		if chevronCap then chevronCap.Text = oddsHolder.Visible and "\u{25B2}" or "\u{25BC}" end
	end)
end

-- Kit README 5, egg-shop state machine: too_poor -> buyable. The price chip goes
-- red and OPEN dims when the balance will not cover the egg. The server still
-- re-checks and refunds -- this only stops the player finding out the hard way.
local function refreshAffordability()
	for _, r in ipairs(priceRows) do
		local ok = (not darrelsKnown) or currentDarrels >= r.price
		r.chip.BackgroundColor3 = ok and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(200, 35, 28)
		r.chip.BackgroundTransparency = ok and 0.68 or 0.05
		r.value.TextColor3 = ok and T.color.white or Color3.fromRGB(255, 210, 204)
		local grad = r.button:FindFirstChildOfClass("UIGradient")
		if grad then grad.Color = ok and T.gradient.green or T.gradient.disabled end
	end
end

---------------------------------------------------------------- local toast
-- Follows ToastClient's visual language (campPanel card, ink border, outlined
-- cream text, slide/fade-ish hold-then-hide) but is built fresh here --
-- ToastClient itself is never touched, per the brief.
local toastCard = new("Frame", {
	Name = "EggToast",
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 132), Size = UDim2.new(0, 380, 0, 46),
	Visible = false, ZIndex = 50,
}, gui)
UITheme.campPanel(toastCard)
UITheme.corner(toastCard, 12)
local toastLabel = new("TextLabel", {
	Size = UDim2.new(1, -20, 1, 0), Position = UDim2.new(0, 10, 0, 0), BackgroundTransparency = 1,
	Font = FONT, TextSize = 15, TextColor3 = CF.cream, TextWrapped = true, Text = "", ZIndex = 51,
}, toastCard)
UITheme.inkText(toastLabel, 2.2)

local toastToken = 0
local function showToast(message)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = message or "Something went wrong."
	toastCard.Visible = true
	task.delay(2.6, function()
		if token == toastToken then toastCard.Visible = false end
	end)
end

---------------------------------------------------------------- hatch reveal
-- Full-screen dim + a single ViewportFrame carried through four phases:
-- SHAKE (egg jitters in place), CRACK x3 (the PLAYER taps the egg three times;
-- each tap fractures the shell at the point that was hit and punches the egg so
-- it rings down), SPLIT (the shell opens while every non-shell
-- part bursts outward), CREATURE (viewport swaps to the hatched brainrot,
-- tier-lit tile, slow spin). "Non-shell part" rather than a fixed name-prefix
-- whitelist: the five egg models carry a `ring_*`/`tape_*` family alongside
-- the documented shard/drip/spike/horn/stripe/stud/rune/crown/link/cap/halo
-- ones, so matching everything except shell_body_* is what actually covers
-- every decoration on every egg instead of silently stranding a family that
-- was never on the list.
--
-- The three hits are what sell it, and they only read as three if the egg is
-- STILL between them -- so the idle shake stops at SHAKE_TIME and each hit
-- fires its own decaying jolt instead.
--
-- CRACK waits on player input rather than a timer, so it needs a way out that a
-- timer-driven phase did not: TAP_TIMEOUT cracks the egg on its own if nobody
-- taps. Without it a hatch could sit forever with the shop panel hidden behind
-- this overlay and the player's darrels already spent.
--
-- ONE RenderStepped connection drives every per-frame animation in this
-- reveal -- the egg shake AND the later creature spin both read the same
-- `elapsed` accumulator -- stored in `conn` and disconnected in `skip()`, so
-- a reveal can never leak a per-frame cost after it ends.
--
-- Every phase transition is a task.delay chained off the one before. Each
-- callback checks its captured `myGen` against the shared `revealGen`
-- counter before doing anything: skip() and a fresh playReveal() both bump
-- `revealGen`, so a stale callback from an already-skipped reveal is a no-op
-- instead of reaching into whatever reveal (or nothing) is live by then.
local revealGui
local function ensureRevealGui()
	if revealGui and revealGui.Parent then return revealGui end
	revealGui = new("ScreenGui", {
		Name = "EggRevealUI", DisplayOrder = 10, IgnoreGuiInset = true, ResetOnSpawn = false,
	}, playerGui)
	return revealGui
end

local VP_SIZE = 320
local EGG_FOV = 32
local SHAKE_TIME, SHAKE_HZ, SHAKE_DEG = 0.9, 20, 4
local CRACKS_TO_OPEN = 3
-- See the header note: the reveal must never wait forever. Once the FIRST
-- timeout fires the player is plainly not tapping, so the rest run themselves
-- off quickly -- three full-length waits back to back would strand an AFK
-- player behind the overlay for thirteen seconds.
local TAP_TIMEOUT, TAP_TIMEOUT_FAST = 3.5, 0.9
local TAP_DEBOUNCE = 0.15 -- so mashing cannot land all three hits inside one frame
local SPLIT_DELAY = 0.34  -- a beat of stillness after the last hit before the shell goes
local JOLT_TIME, JOLT_HZ, JOLT_DEG = 0.22, 16, 2.2
local HIT_SOUND  = { "eggCrack1", "eggCrack2", "eggCrack3" }
local HIT_TAIL   = { "eggCrumble", "eggCrumble", "eggCrumbleBig" }
local HIT_VOLUME = { 0.34, 0.40, 0.46 }
local HIT_SPEED  = { 1.10, 1.00, 0.94 }
local SPLIT_TIME, CRACK_DIST_MULT, MAX_EXPLODE = 0.5, 2.5, 60
local SPIN_TIME = 2.0     -- seconds per creature revolution
local ENTER_TIME = 0.5    -- the hatched pet's hop-in before it settles to an idle bob
-- Clicking anywhere used to skip the reveal instantly, so a stray click right
-- after pressing OPEN threw the hatch away. Nothing is skippable until the pet
-- is actually on screen, and then only after this grace -- otherwise the click
-- that landed the final crack carries straight through and dismisses it.
local SKIP_GRACE = 0.35
local CREATURE_HOLD = 3.5 -- seconds the creature sits before auto-skip
local FADE_TIME = 0.3
local DIM_TARGET = 0.35

local revealGen = 0    -- bumped by skip() and by every new playReveal()
local revealSkip = nil -- the live reveal's skip(), or nil

local function volumeOf(part)
	local s = part.Size
	return s.X * s.Y * s.Z
end

-- Cracks are drawn FLAT, as UI over the egg viewport, rather than as parts stuck
-- on the shell. The 3D version this replaces could not be made to look right:
-- slivers pasted onto an ellipsoid are lit by the viewport's own ambient, stand
-- a couple of pixels proud at best, and read as dark specks rather than as a
-- fracture. Screen-space lines stay crisp at any egg size -- and the tap
-- position is ALREADY in screen space, so the crack starts exactly under the
-- finger with no projection maths in between.
--
-- What makes it read as a fracture rather than a drawn line: the walk turns by a
-- random amount at every step, it propagates BOTH WAYS from the point struck,
-- each segment tapers as it travels out, hairline branches fork off partway
-- along, and every segment carries a 1px light edge so it looks chipped rather
-- than painted on.
local CRACK_DARK = Color3.fromRGB(14, 10, 9)


-- ONE seam down the middle, extended in three stages -- stage 1 marks the top
-- third, stage 2 the middle, stage 3 the bottom -- so three taps draw a single
-- continuous line that the split then opens along. This is what an egg cracking
-- looks like and what the three taps promise.
--
-- The tap ADVANCES the seam, it does not place it. A fracture starting wherever
-- you happened to click read as random damage scattered over the shell rather
-- than as an egg opening; tap position now only leans the seam slightly, so
-- tapping still feels connected to what appears without scattering it.
local SEAM_BANDS = { { -0.70, -0.18 }, { -0.18, 0.26 }, { 0.26, 0.72 } } -- fractions of ry
local SEAM_STEPS = 4
local SEAM_WANDER = 0.18 -- how far off centre each kink swings, as a fraction of rx

-- seamX is where the previous stage left off, so the stages join up instead of
-- each starting from a fresh guess. Returns the new end point for the next one.
local function drawCrack(layer, seamX, px, rx, ry, hit, rng)
	local made = {}
	local cx, cy = VP_SIZE / 2, VP_SIZE / 2
	local band = SEAM_BANDS[math.min(hit, #SEAM_BANDS)]
	local y0, y1 = cy + band[1] * ry, cy + band[2] * ry
	local step = (y1 - y0) / SEAM_STEPS
	local lean = math.clamp((px - cx) / rx, -1, 1) * rx * 0.12
	local thick = 6 + hit

	local x, y = seamX or (cx + lean), y0
	for i = 1, SEAM_STEPS do
		-- alternate the swing so the seam zigs and zags instead of drifting one way
		local swing = (i % 2 == 0) and 1 or -1
		local nx = cx + lean + swing * rng:NextNumber(SEAM_WANDER * 0.45, SEAM_WANDER) * rx
		local ny = y + step
		local dx, dy = nx - x, ny - y
		local len = math.sqrt(dx * dx + dy * dy)
		-- GuiObject.Rotation is degrees CLOCKWISE and screen +Y is down, so a
		-- frame's long axis at rotation r runs along (-sin r, cos r) -- meaning the
		-- angle pointing along (dx, dy) is atan2(-dx, dy). Getting this backwards is
		-- exactly what makes a jagged polyline come apart into loose sticks.
		local a = math.atan2(-dx, dy)
		made[#made + 1] = new("Frame", {
			Name = "crackSeg", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset((x + nx) / 2, (y + ny) / 2),
			-- +3 so consecutive segments overlap at the joint and the seam stays
			-- unbroken through every kink
			Size = UDim2.fromOffset(thick, len + 3),
			Rotation = math.deg(a), BackgroundColor3 = CRACK_DARK, BorderSizePixel = 0, ZIndex = 5,
		}, layer)
		x, y = nx, ny
	end
	return made, x
end


-- Shell flakes knocked loose by a hit, in the colour of the shell they came off
-- so they read as debris rather than as more decoration.
local function drawChips(layer, px, py, count, colour, rng)
	for _ = 1, count do
		local s = rng:NextNumber(4, 9)
		local chip = new("Frame", {
			Name = "chip", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(px, py), Size = UDim2.fromOffset(s, s),
			Rotation = rng:NextNumber(0, 180), BackgroundColor3 = colour,
			BorderSizePixel = 0, ZIndex = 21,
		}, layer)
		TweenService:Create(chip, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromOffset(px + rng:NextNumber(-46, 46), py + rng:NextNumber(26, 74)),
			Rotation = rng:NextNumber(-220, 220),
			Size = UDim2.fromOffset(s * 0.4, s * 0.4),
			BackgroundTransparency = 1,
		}):Play()
	end
end

local function playReveal(result)
	-- Back-to-back safety: a second EggResult while a reveal is live skips
	-- the current one, then plays the new one straight after (simplest
	-- correct behaviour -- no queue to get stuck).
	if revealSkip then revealSkip() end

	revealGen += 1
	local myGen = revealGen

	local eggDef = EggConfig.GetEgg(WORLD_ID, result.EggId)
	local eggModelName = eggDef and eggDef.Model
	local tier = tierByName[result.Rarity]
	local accent = (tier and tier.Color) or CF.ink

	local root = new("Frame", {
		Name = "Reveal", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1,
	}, ensureRevealGui())

	local dim = new("Frame", {
		Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1,
	}, root)
	TweenService:Create(dim, TweenInfo.new(FADE_TIME), { BackgroundTransparency = 1 - DIM_TARGET }):Play()

	local holder = new("Frame", {
		Name = "Holder", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromOffset(VP_SIZE, VP_SIZE + 96), BackgroundTransparency = 1, ZIndex = 2,
	}, root)

	local clickCatcher = new("TextButton", {
		Name = "ClickCatcher", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 20,
	}, root)

	frame.Visible = false -- hide the shop panel behind the reveal overlay

	-- {inst, prop} pairs to hide (tween to transparency 1) on skip; every
	-- element that should visibly fade rather than snap registers itself here.
	local fades = { { dim, "BackgroundTransparency" } }

	local conn -- the ONE RenderStepped connection for this reveal
	local dead = false
	local elapsed = 0
	local spinFn -- set once the creature phase starts
	local shellPart, decorations, crackParts = nil, {}, {}
	local crackLayer, eggRx, eggRy
	local joltStart, joltMag, splitting = nil, 1, false
	local canSkip = false -- see SKIP_GRACE

	local function skip()
		if dead then return end
		dead = true
		revealGen += 1 -- invalidate any pending task.delay for THIS reveal too
		if revealSkip == skip then revealSkip = nil end
		if conn then conn:Disconnect(); conn = nil end
		clickCatcher.Active = false
		for _, f in ipairs(fades) do
			TweenService:Create(f[1], TweenInfo.new(FADE_TIME), { [f[2]] = 1 }):Play()
		end
		frame.Visible = true -- restore the shop panel
		task.delay(FADE_TIME, function()
			if root then root:Destroy(); root = nil end
		end)
	end
	revealSkip = skip
	-- Stays Active the whole time so stray clicks are SWALLOWED rather than
	-- passed through to whatever is underneath; it just does nothing until the
	-- reveal is at a point where skipping is what the player meant.
	clickCatcher.Activated:Connect(function()
		if canSkip then skip() end
	end)

	---------------------------------------------------- SHAKE
	local eggClone, basePivot, eggVp, eggCam, eggCentre, eggDist
	local eggMasterModel = eggModelName and eggMaster(eggModelName)
	if eggMasterModel then
		eggVp = new("ViewportFrame", {
			Name = "EggViewport", Size = UDim2.fromOffset(VP_SIZE, VP_SIZE), BackgroundTransparency = 1, ZIndex = 3,
		}, holder)
		-- camera and framing are kept: mapping a tap back onto the shell needs both
		eggCam = new("Camera", { FieldOfView = EGG_FOV }, eggVp)
		eggVp.CurrentCamera = eggCam
		eggClone = eggMasterModel:Clone()
		eggClone.Parent = eggVp
		basePivot = eggClone:GetPivot()
		eggCentre, eggDist = BrainrotThumb.framing(eggClone, EGG_FOV)
		eggCam.CFrame = CFrame.lookAt(eggCentre + BrainrotThumb.DEFAULT_DIR * eggDist, eggCentre)

		-- Captured HERE, before any crack geometry exists. "Everything that is not
		-- the shell is a decoration" still holds, but the crack slivers and the two
		-- shell halves added later are also non-shell parts, so scanning at SPLIT
		-- time would sweep the fissure itself into the burst list.
		shellPart = eggClone:FindFirstChild("shell_body_1")
		for _, d in ipairs(eggClone:GetDescendants()) do
			if d:IsA("BasePart") and d ~= shellPart then
				decorations[#decorations + 1] = d
			end
		end
		-- cap the tween count: the biggest MAX_EXPLODE pieces fly outward, the rest
		-- (barely visible slivers on a 200-part Crown egg) just vanish instantly
		-- instead of paying for a tween nobody would see
		table.sort(decorations, function(a, b) return volumeOf(a) > volumeOf(b) end)

		-- A CanvasGroup so the whole fissure can be faded with ONE property at
		-- split time, instead of chasing every segment and its edge highlight.
		-- Clipped to the viewport rect so a stray branch cannot draw outside it.
		-- ZIndex 4: directly above the egg viewport (3) and BELOW the reveal tile
		-- (12-14). It used to sit at 18, on top of everything, so any hiccup in the
		-- split-time fade left the seam drawn over the hatched pet.
		crackLayer = new("CanvasGroup", {
			Name = "CrackLayer", Size = UDim2.fromOffset(VP_SIZE, VP_SIZE),
			BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 4,
		}, holder)
		table.insert(fades, { crackLayer, "GroupTransparency" })

		-- Pixels per stud: the camera's half-extent at the egg's distance maps to
		-- half the viewport, so the shell's radii convert straight into screen radii.
		if shellPart then
			local perStud = (VP_SIZE / 2) / (math.tan(math.rad(EGG_FOV / 2)) * eggDist)
			eggRx = shellPart.Size.X / 2 * perStud
			eggRy = shellPart.Size.Y / 2 * perStud
		end
	end

	local beginCracking, armTap, crackBeat, splitPhase, creaturePhase

	conn = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		-- `splitting` gates this off entirely: once SPLIT starts, the halves are
		-- driven by tweens and a PivotTo here would fight them every frame.
		if eggClone and basePivot and not splitting then
			if elapsed <= SHAKE_TIME then
				local w = elapsed * SHAKE_HZ * (2 * math.pi)
				local rx = math.rad(SHAKE_DEG) * math.sin(w)
				local ry = math.rad(SHAKE_DEG) * math.sin(w * 1.31 + 1.7)
				local rz = math.rad(SHAKE_DEG) * math.sin(w * 0.77 + 0.4)
				eggClone:PivotTo(basePivot * CFrame.Angles(rx, ry, rz))
			elseif joltStart then
				-- Each beat punches the egg and lets it ring down to rest. The
				-- stillness in between is the whole point -- continuing the idle
				-- jitter here would blur three hits back into one long wobble.
				local t = elapsed - joltStart
				if t < JOLT_TIME then
					local decay = (1 - t / JOLT_TIME) ^ 2
					local a = math.rad(JOLT_DEG) * joltMag * decay * math.sin(t * JOLT_HZ * (2 * math.pi))
					eggClone:PivotTo(basePivot * CFrame.Angles(a * 0.5, a, a * 0.8))
				else
					eggClone:PivotTo(basePivot)
					joltStart = nil
				end
			end
		end
		if spinFn then spinFn(elapsed) end
	end)

	task.delay(SHAKE_TIME, function()
		if myGen ~= revealGen then return end
		beginCracking()
	end)

	---------------------------------------------------- CRACK (player-driven)
	-- The egg no longer cracks itself: each hit is a tap ON the egg, and the
	-- fracture starts AT the point that was tapped. crackBtn sits at ZIndex 21,
	-- one rung above the full-screen clickCatcher, so a tap on the egg cracks it
	-- while a tap anywhere else still skips the reveal.
	local rng = Random.new()
	local hits = 0
	local tapToken = 0  -- bumped by every hit; a stale timeout sees the change and no-ops
	local lastTap = -1
	local timedOut = false -- latched once the player has shown they are not tapping
	local crackBtn, hintLabel
	local seamX -- where the seam's last stage ended, so the next one joins onto it

	-- Screen point -> layer-local pixels, pulled inside the egg's silhouette. A
	-- tap out on the rim would start a fissure half off the shell.
	local function layerPoint(sx, sy)
		local abs = crackLayer.AbsolutePosition
		local px, py = sx - abs.X, sy - abs.Y
		local cx, cy = VP_SIZE / 2, VP_SIZE / 2
		local e = ((px - cx) / eggRx) ^ 2 + ((py - cy) / eggRy) ^ 2
		if e > 0.55 then
			local k = math.sqrt(0.55 / e)
			px, py = cx + (px - cx) * k, cy + (py - cy) * k
		end
		return px, py
	end

	-- Hidden rather than destroyed: both are registered in `fades`, and skip()
	-- tweens everything in there -- tweening a Destroy()'d instance throws.
	local function hidePrompt()
		tapToken += 1
		if crackBtn then crackBtn.Active, crackBtn.Visible = false, false end
		if hintLabel then hintLabel.Visible = false end
	end

	armTap = function()
		tapToken += 1
		local myToken = tapToken
		if hintLabel then
			local left = CRACKS_TO_OPEN - hits
			hintLabel.Text = (hits == 0) and "TAP THE EGG TO CRACK IT"
				or ((left == 1) and "ONE MORE!" or (left .. " MORE!"))
		end
		task.delay(timedOut and TAP_TIMEOUT_FAST or TAP_TIMEOUT, function()
			if myGen ~= revealGen or myToken ~= tapToken then return end
			timedOut = true
			crackBeat(VP_SIZE / 2 + rng:NextNumber(-0.4, 0.4) * eggRx,
				VP_SIZE / 2 + rng:NextNumber(-0.45, 0.45) * eggRy)
		end)
	end

	beginCracking = function()
		if not (eggClone and shellPart and eggVp and crackLayer and eggRx) then
			splitPhase() -- no egg model resolved: nothing to tap, so go straight through
			return
		end
		SoundKit.play("eggStrain", nil, { volume = 0.16, speed = 0.9 })

		crackBtn = new("TextButton", {
			Name = "CrackButton", Size = UDim2.fromOffset(VP_SIZE, VP_SIZE),
			BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 21,
		}, holder)
		hintLabel = new("TextLabel", {
			Name = "CrackHint", Position = UDim2.fromOffset(-90, VP_SIZE + 14),
			Size = UDim2.fromOffset(VP_SIZE + 180, 30), BackgroundTransparency = 1,
			Font = FONT, TextSize = 20, TextColor3 = CF.onDark, Text = "", ZIndex = 22,
		}, holder)
		local hintInk = UITheme.inkText(hintLabel, 2.4)
		table.insert(fades, { hintLabel, "TextTransparency" })
		table.insert(fades, { hintInk, "Transparency" })

		-- InputBegan, not Activated: Activated does not carry a position, and the
		-- position is the whole point of tapping the egg rather than a button.
		crackBtn.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch then return end
			if myGen ~= revealGen or hits >= CRACKS_TO_OPEN then return end
			if elapsed - lastTap < TAP_DEBOUNCE then return end
			lastTap = elapsed
			crackBeat(layerPoint(input.Position.X, input.Position.Y))
		end)

		armTap()
	end

	crackBeat = function(px, py)
		hits += 1
		local n = math.min(hits, CRACKS_TO_OPEN)
		SoundKit.play(HIT_SOUND[n], nil, { volume = HIT_VOLUME[n], speed = HIT_SPEED[n] })
		SoundKit.play(HIT_TAIL[n], nil, { volume = 0.20 + 0.04 * n, speed = 0.95 })

		-- Everything already drawn widens a little. A shell does not keep its first
		-- crack hairline once you have hit it twice more.
		for _, seg in ipairs(crackParts) do
			seg.Size = UDim2.fromOffset(seg.Size.X.Offset + 1, seg.Size.Y.Offset)
		end
		local segs, endX = drawCrack(crackLayer, seamX, px, eggRx, eggRy, n, rng)
		seamX = endX
		for _, seg in ipairs(segs) do
			crackParts[#crackParts + 1] = seg
		end
		-- chips come off the seam's leading edge, not off wherever the finger was
		drawChips(crackLayer, endX, VP_SIZE / 2 + SEAM_BANDS[n][2] * eggRy, 1 + n, shellPart.Color, rng)

		joltStart, joltMag = elapsed, n -- later hits hit harder

		if hits >= CRACKS_TO_OPEN then
			hidePrompt()
			task.delay(SPLIT_DELAY, function()
				if myGen ~= revealGen then return end
				splitPhase()
			end)
		else
			armTap()
		end
	end

	---------------------------------------------------- SPLIT
	splitPhase = function()
		joltStart, splitting = nil, true
		SoundKit.play("eggSplit", nil, { volume = 0.5 })
		SoundKit.play("catchSparkle", nil, { volume = 0.3, speed = 1.1 })

		if eggClone then
			local centre = (shellPart and shellPart.Position) or basePivot.Position
			local ease = TweenInfo.new(SPLIT_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

			-- The shell is ONE Part carrying a Sphere SpecialMesh, so there is no
			-- half to peel off -- it gets swapped for two clones at half height,
			-- which the mesh refits to on its own. Two domes parting with a
			-- tier-coloured flash between them reads as a shell opening; the
			-- rounded cut faces are never still long enough to give it away.
			if shellPart then
				local sz = shellPart.Size
				local function half(sign, name)
					local h = shellPart:Clone()
					h.Name = "shell_half_" .. name
					h.Size = Vector3.new(sz.X, sz.Y / 2, sz.Z)
					h.CFrame = shellPart.CFrame * CFrame.new(0, sign * sz.Y / 4, 0)
					h.Parent = eggClone
					return h
				end
				local top, bottom = half(1, "top"), half(-1, "bottom")
				shellPart.Transparency = 1

				TweenService:Create(top, ease, {
					CFrame = top.CFrame * CFrame.new(0, sz.Y * 0.85, 0) * CFrame.Angles(math.rad(38), 0, math.rad(22)),
					Transparency = 1,
				}):Play()
				TweenService:Create(bottom, ease, {
					CFrame = bottom.CFrame * CFrame.new(0, -sz.Y * 0.30, 0) * CFrame.Angles(math.rad(-16), 0, math.rad(-12)),
					Transparency = 1,
				}):Play()
			end

			-- Flash in the widening gap, tier-coloured so the reveal's accent lands
			-- a beat before the creature tile carrying that same accent does.
			local flash = Instance.new("Part")
			flash.Name = "split_flash"
			flash.Anchored, flash.CanCollide, flash.CanQuery, flash.CastShadow = true, false, false, false
			flash.Material = Enum.Material.Neon
			flash.Color = accent
			flash.Size = Vector3.one * 0.2
			flash.CFrame = CFrame.new(centre)
			local fmesh = Instance.new("SpecialMesh")
			fmesh.MeshType = Enum.MeshType.Sphere
			fmesh.Parent = flash
			flash.Parent = eggClone
			TweenService:Create(flash, TweenInfo.new(SPLIT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.one * ((shellPart and shellPart.Size.X * 1.6) or 3),
				Transparency = 1,
			}):Play()

			-- The seam goes with the shell it was drawn on -- one property, because the
			-- layer is a CanvasGroup. DESTROYED after the fade rather than left at
			-- transparency 1: an invisible layer is still a layer, and leaving it
			-- parented is what kept the cracks on screen over the opened pet.
			if crackLayer then
				local dying = crackLayer
				crackLayer = nil
				TweenService:Create(dying, TweenInfo.new(SPLIT_TIME * 0.5), { GroupTransparency = 1 }):Play()
				task.delay(SPLIT_TIME * 0.5 + 0.05, function()
					if dying then dying:Destroy() end
				end)
			end

			for i, part in ipairs(decorations) do
				if i <= MAX_EXPLODE then
					local targetPos = centre + (part.Position - centre) * CRACK_DIST_MULT
					local targetCFrame = CFrame.new(targetPos) * (part.CFrame - part.CFrame.Position)
					TweenService:Create(part, TweenInfo.new(SPLIT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						CFrame = targetCFrame, Transparency = 1,
					}):Play()
				else
					part.Transparency = 1
				end
			end
		end

		task.delay(SPLIT_TIME, function()
			if myGen ~= revealGen then return end
			creaturePhase()
		end)
	end

	---------------------------------------------------- CREATURE
	creaturePhase = function()
		if eggVp then eggVp:Destroy(); eggVp = nil end
		eggClone = nil

		local card, outer = UITheme.accentCard(holder, accent, 20)
		outer.Name = "RevealTile"
		outer.Size = UDim2.fromOffset(VP_SIZE + 20, VP_SIZE + 20)
		outer.Position = UDim2.fromOffset(-10, -10)
		outer.ZIndex = 12
		card.ZIndex = 13
		-- Rare and up get glow / shimmer / sparkles / a cycling border, same
		-- ladder as every other tile in the game (RarityFX itself decides
		-- Common/Uncommon get nothing).
		RarityFX.attach(outer, card, result.Rarity, accent, 0)
		table.insert(fades, { outer, "BackgroundTransparency" })
		table.insert(fades, { card, "BackgroundTransparency" })

		local creatureVp = new("ViewportFrame", {
			Name = "CreatureViewport", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 14,
		}, card)
		local ccam = new("Camera", { FieldOfView = 30 }, creatureVp)
		creatureVp.CurrentCamera = ccam
		table.insert(fades, { creatureVp, "ImageTransparency" })

		-- The tile POPS in rather than cutting in, so the moment the shell opens
		-- lands. On holder (not the tile) because holder is the only node here
		-- anchored at its own centre -- scaling the tile would grow it out of its
		-- top-left corner -- and this way the name and tier labels pop with it.
		local pop = new("UIScale", { Scale = 0.55 }, holder)
		TweenService:Create(pop, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()

		local master = petMaster(result.Name, result.PetId)
		if master then
			local m = master:Clone()
			m.Parent = creatureVp
			local centre, dist = BrainrotThumb.framing(m, 30)
			local rest = m:GetPivot()
			local hopScale = dist * 0.05 -- size-relative, so a big pet hops as far as a small one
			local creatureStart = elapsed
			spinFn = function(t)
				local age = t - creatureStart
				-- ENTRANCE then IDLE: the pet hops up into frame, settles, and keeps a
				-- gentle bob going. A pet that only turns on the spot reads as a
				-- turntable render; the hop is what makes it read as alive.
				local hop = (age < ENTER_TIME)
					and math.sin(age / ENTER_TIME * math.pi) * 0.6
					or 0
				local bob = math.sin(age * 2.4) * 0.12
				-- world-space offset (CFrame + Vector3), NOT rest * CFrame.new: a pet
				-- whose pivot is tilted would otherwise hop off at an angle
				m:PivotTo(rest + Vector3.new(0, (hop + bob) * hopScale, 0))
				-- the camera keeps the spin, so an off-centre pivot cannot make the
				-- model swing around instead of turning on the spot
				local ang = (age / SPIN_TIME) * (2 * math.pi)
				local dir = CFrame.Angles(0, ang, 0) * BrainrotThumb.DEFAULT_DIR
				ccam.CFrame = CFrame.lookAt(centre + dir * dist, centre)
			end
		else
			-- no model for this name: a flat rarity swatch keeps the tile
			-- readable instead of leaving a hole (same fallback BackpackClient uses)
			local sw = new("Frame", {
				Size = UDim2.fromScale(1, 1), BackgroundColor3 = accent, BackgroundTransparency = 0.5, ZIndex = 14,
			}, card)
			UITheme.corner(sw, 12)
		end

		local nameLabel = new("TextLabel", {
			Name = "CreatureName", Position = UDim2.fromOffset(-90, VP_SIZE + 14),
			Size = UDim2.fromOffset(VP_SIZE + 180, 34), BackgroundTransparency = 1, Font = FONT, TextSize = 24,
			TextColor3 = CF.onDark, TextTruncate = Enum.TextTruncate.AtEnd, Text = result.Name, ZIndex = 16,
		}, holder)
		local nameInk = UITheme.inkText(nameLabel, 2.8)
		table.insert(fades, { nameLabel, "TextTransparency" })
		table.insert(fades, { nameInk, "Transparency" })

		local tierLabel = new("TextLabel", {
			Name = "CreatureTier", Position = UDim2.fromOffset(-90, VP_SIZE + 50),
			Size = UDim2.fromOffset(VP_SIZE + 180, 26), BackgroundTransparency = 1, Font = FONT, TextSize = 18,
			TextColor3 = accent, Text = string.upper(tostring(result.Rarity or "?")), ZIndex = 16,
		}, holder)
		local tierInk = UITheme.inkText(tierLabel, 2.2)
		table.insert(fades, { tierLabel, "TextTransparency" })
		table.insert(fades, { tierInk, "Transparency" })

		-- only now is a click a deliberate "I have seen it, move on"
		task.delay(SKIP_GRACE, function()
			if myGen ~= revealGen then return end
			canSkip = true
		end)

		task.delay(CREATURE_HOLD, function()
			if myGen ~= revealGen then return end
			skip()
		end)
	end
end

---------------------------------------------------------------- darrel state pull
-- DarrelUpdate's join-time push can race this script's own listener connecting
-- (Task 3's note), so this ALSO pulls current state via a RemoteFunction --
-- once at startup, and again every time the panel opens.
local darrelStateRF = remotes:WaitForChild("DarrelState")
local function applyDarrel(payload)
	if type(payload) ~= "table" then return end
	if payload.Darrels then
		currentDarrels = math.floor(payload.Darrels)
		darrelLabel.Text = tostring(currentDarrels)
		-- .Daily is only a table once the profile has actually loaded, so it is the
		-- discriminator that tells a real 0 from a placeholder 0.
		if typeof(payload.Daily) == "table" then darrelsKnown = true end
		refreshAffordability()
	end
	-- payload.Daily is deliberately unused: quests render in the Goals panel now.
end
local function pullDarrelState()
	task.spawn(function()
		local ok, res = pcall(function() return darrelStateRF:InvokeServer() end)
		if ok then applyDarrel(res) end
	end)
end
pullDarrelState()
remotes.DarrelUpdate.OnClientEvent:Connect(applyDarrel)

---------------------------------------------------------------- open / close
local function setOpen(open)
	frame.Visible = open
	if open then
		pullDarrelState()
		list.CanvasPosition = Vector2.new(0, 0)
	end
end
closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)

remotes.EggResult.OnClientEvent:Connect(function(result)
	if type(result) ~= "table" then return end
	if not result.Ok then
		showToast(result.Message)
		return
	end
	-- setOpen first so darrel/quest state refreshes and the panel is the one
	-- playReveal hides behind its own overlay; playReveal restores
	-- frame.Visible itself when the reveal ends or is skipped.
	setOpen(true)
	playReveal(result)
end)

---------------------------------------------------------------- stall prompt
local prompt = Workspace:WaitForChild("GameWorld"):WaitForChild("EggStall"):WaitForChild("PromptPart"):WaitForChild("EggPrompt")
ProximityPromptService.PromptTriggered:Connect(function(triggeredPrompt, who)
	if who ~= player or triggeredPrompt ~= prompt then return end
	setOpen(not frame.Visible)
end)

-- walk away -> close, same convention as the other stall panels (MerchantClient)
RunService.Heartbeat:Connect(function()
	if not frame.Visible then return end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and (hrp.Position - prompt.Parent.Position).Magnitude > 24 then
		setOpen(false)
	end
end)
