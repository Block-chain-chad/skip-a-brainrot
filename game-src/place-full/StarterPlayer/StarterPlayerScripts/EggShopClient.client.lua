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

-- 1240 -> "1,240" (the egg-shop handoff shows every count, price and shortfall
-- thousands-separated)
local function comma(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local k
	repeat
		s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return s
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
-- Row eggs turn slowly in their slots (user, 2026-07-31 -- the static "no spin"
-- brief is superseded). One shared RenderStepped drives every registered
-- viewport by orbiting its CAMERA, the same trick the hatch reveal uses so an
-- off-centre pivot can't make the model swing; phase-offset per slot so five
-- eggs don't rotate in lockstep. The loop is gated on the panel being visible,
-- so a closed shop costs nothing per frame.
local SLOT_SPIN_TIME = 6   -- seconds per revolution
local SLOT_BOB = 0.04      -- camera-height sine, as a fraction of framing dist
local eggSpinners = {}
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
	if opts.spin then
		eggSpinners[#eggSpinners + 1] = {
			cam = cam, centre = centre, dist = dist,
			phase = #eggSpinners * 0.9,
		}
	end
	return vp
end

-- Pet render for the odds tiles and the multi-open result cards. petMaster
-- (defined above; the hatch reveal shares it) resolves PetModels first, then
-- the brainrot stand-ins; returns nil when neither folder has the model --
-- which is most pets today, since the .glb imports are still a pending user
-- step -- and callers fall back to text.
local function addPetViewport(parent, creatureName, petId, zIndex)
	local master = petMaster(creatureName, petId)
	if not master then return nil end
	local vp = new("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = zIndex or 1,
	}, parent)
	local m = master:Clone()
	m.Parent = vp
	local fov = 30
	local centre, dist = BrainrotThumb.framing(m, fov)
	local cam = new("Camera", { FieldOfView = fov })
	cam.CFrame = CFrame.lookAt(centre + BrainrotThumb.DEFAULT_DIR * dist, centre)
	cam.Parent = vp
	vp.CurrentCamera = cam
	return vp
end

-- UI.button hardcodes its caption label to ZIndex 3 (Builders ~line 174). Every
-- kit panel lives in a ScreenGui set to ZIndexBehavior.Sibling, where a child
-- always draws above its parent and that 3 never matters. THIS ScreenGui is
-- Global (it predates the kit), so a caption at 3 renders UNDERNEATH its own
-- button and the button comes out blank -- which is exactly what happened.
-- Lifting the caption is the surgical fix; flipping the whole ScreenGui to
-- Sibling would also re-layer the hatch reveal, which is not ours to disturb.
--
-- The z argument is not optional sugar: the caption's ZIndex has to be derived
-- from the button's FINAL one, and callers set that after UI.button returns. A
-- first cut read b.ZIndex inside here and got the default 1, so captions ended
-- up at 2 and stayed buried. Same eager-capture trap Builders documents for the
-- hover rest-position, one field over.
--
-- Declared HERE, above the panel, because the header's close button is its
-- first caller -- it used to live down in the egg-row section and was nil by
-- the time the header ran, which killed the script mid-build.
local function kitButton(parent, text, variant, size, z)
	local b = UI.button(parent, text, variant, size)
	b.ZIndex = z
	local cap = b:FindFirstChildWhichIsA("TextLabel")
	if cap then cap.ZIndex = z + 1 end
	return b, cap
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
-- STRUCTURE, read off the rendered reference: the panel is TWO stacked slabs,
-- not one. A header bar (92 tall, its own 5px outline, radius 22), then
-- margin-top:12, then a separate body slab. Building it as a single panel with
-- a gold strip inside is what kept it looking wrong regardless of colour --
-- the silhouette was one box where the design is two.
local FRAME_W  = T.size.panelWidth.eggs   -- 940, per the egg-shop handoff
local HEADER_H = 92
local GAP      = 12
local BODY_H   = 606
local FRAME_H  = HEADER_H + GAP + BODY_H

-- The registered frame is a transparent COLUMN holding both slabs, so toggling
-- its Visible still means "the shop is open" for setOpen and for the reveal.
local frame = new("Frame", {
	Name = "EggShopFrame",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.fromOffset(FRAME_W, FRAME_H),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 10,
}, gui)
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
-- The sibling-shadow trap is gone with UI.panel: both slabs are UI.surface, and
-- any shadow we add lands as a child, so it inherits Visible.
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

-- Handoff layout tree: a full-screen dim sits behind the column while the shop
-- is open. Kit panels get theirs from GameHUDClient's shared scrim; this stall
-- panel owns its own. A plain Frame: it dims the world without eating input.
local scrim = new("Frame", {
	Name = "Scrim",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(10, 14, 6),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 5,
}, gui)
local SCRIM_ALPHA = 0.5

-- Open/close motion (handoff: open scale .92 -> 1 Back/Out 180ms, close -> .95
-- fade 120ms). A SECOND UIScale, multiplicative with hudScale's fit factor, so
-- the pop never fights the responsive fit.
local openPop = new("UIScale", { Name = "OpenPop" }, frame)

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
-- GOLD header bar. Read off the kit's rendered reference
-- (design_handoff_game_ui/game-ui-reference.html), not the README prose: the
-- header is a full-width gold slab, the same gradient family as the balance
-- pill, with the title sitting on it. Building from the written spec alone is
-- how the first two passes ended up with a dark header that looked nothing
-- like the picture.
local headerBar = UI.surface(frame, UDim2.new(1, 0, 0, HEADER_H), "gold", T.radius.panel, T.stroke.panel)
headerBar.Name = "HeaderBar"
headerBar.Position = UDim2.fromOffset(0, 0)
headerBar.ZIndex = frame.ZIndex + 2
UI.gloss(headerBar, T.radius.panel)

local body = UI.surface(frame, UDim2.new(1, 0, 0, BODY_H), "panel", T.radius.panel, T.stroke.panel)
body.Name = "Body"
body.Position = UDim2.fromOffset(0, HEADER_H + GAP)
body.ZIndex = frame.ZIndex + 2
local bodyPad = Instance.new("UIPadding")
bodyPad.PaddingTop = UDim.new(0, 16)
bodyPad.PaddingBottom = UDim.new(0, 16)
bodyPad.PaddingLeft = UDim.new(0, 16)
bodyPad.PaddingRight = UDim.new(0, 16)
bodyPad.Parent = body

-- 62px egg mark leading the title (handoff header row: icon, title, spacer,
-- coin pill, close). Drawn by IconArt like every other header glyph -- the
-- transcription of the handoff's eggs.svg lives in IconArt.SHAPES.egg.
local eggIcon = new("Frame", {
	Name = "EggIcon",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 14, 0.5, 0),
	Size = UDim2.fromOffset(62, 62),
	BackgroundTransparency = 1,
	ZIndex = frame.ZIndex + 4,
}, headerBar)
if IconArt and IconArt.has("egg") then
	IconArt.draw(eggIcon, "egg", 62, eggIcon.ZIndex)
end

local headerTitle = UI.label(headerBar, "Forest Eggs", "panelTitle", T.color.white)
headerTitle.Name = "Title"
headerTitle.AnchorPoint = Vector2.new(0, 0.5)
headerTitle.Position = UDim2.new(0, 90, 0.5, 0)
headerTitle.Size = UDim2.fromOffset(420, 40)
headerTitle.TextXAlignment = Enum.TextXAlignment.Left
headerTitle.ZIndex = frame.ZIndex + 4

-- BALANCE PILL -- DARK, not gold. The reference puts it on the gold header as
-- `linear-gradient(180deg,#3B4731,#26301F)` with a 4px outline: height 62,
-- radius 15, icon 42, value 26, then a 36px green + button. I had it goldSmall,
-- which vanished into the header it sits on.
local BAL_W, BAL_H, BAL_ICON = 196, 62, 42
local balPill = UI.surface(headerBar, UDim2.fromOffset(BAL_W, BAL_H), "slot", 15, T.stroke.control)
balPill.Name = "BalancePill"
balPill.AnchorPoint = Vector2.new(1, 0.5)
balPill.Position = UDim2.new(1, -(T.size.closeButton.X + 22), 0.5, 0)
balPill.ZIndex = headerBar.ZIndex + 3
balPill.BackgroundColor3 = Color3.fromRGB(59, 71, 49)
local balGrad = balPill:FindFirstChildOfClass("UIGradient")
if balGrad then
	balGrad.Color = ColorSequence.new(Color3.fromRGB(59, 71, 49), Color3.fromRGB(38, 48, 31))
end

local darrelIcon = new("Frame", {
	Name = "DarrelIcon",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 6, 0.5, 0),
	Size = UDim2.fromOffset(BAL_ICON, BAL_ICON),
	BackgroundTransparency = 1,
	ZIndex = balPill.ZIndex + 2,
}, balPill)
if IconArt and IconArt.has("darrel") then
	IconArt.draw(darrelIcon, "darrel", BAL_ICON, balPill.ZIndex + 2)
end

local darrelLabel = UI.label(balPill, "0", "value", T.color.white)
darrelLabel.Name = "Value"
darrelLabel.AnchorPoint = Vector2.new(0, 0.5)
darrelLabel.Position = UDim2.new(0, 6 + BAL_ICON + 9, 0.5, 0)
darrelLabel.Size = UDim2.fromOffset(BAL_W - (6 + BAL_ICON + 9 + 36 + 20), 30)
darrelLabel.TextXAlignment = Enum.TextXAlignment.Left
darrelLabel.ZIndex = balPill.ZIndex + 2

-- the reference's green "+" that routes to the currency shop; no darrel pack
-- products exist yet, so it says so instead of opening nothing
local plusBtn = kitButton(balPill, "+", "green", UDim2.fromOffset(36, 36), balPill.ZIndex + 2)
plusBtn.Name = "Plus"
plusBtn.AnchorPoint = Vector2.new(1, 0.5)
plusBtn.Position = UDim2.new(1, -8, 0.5, 0)

-- UI.button(parent, text, variant, size) -- text and size are NOT interchangeable
-- with each other's positions; passing them the other way round assigns a string
-- to Size and the panel dies half-built.
-- "X" the letter, NOT \u{2715}: Fredoka One has no glyph for the multiply-cross,
-- so the caption rendered as nothing and the close button sat blank (same
-- unrenderable-glyph trap the HUD icon work documented).
local closeBtn = kitButton(headerBar, "X", "red",
	UDim2.fromOffset(T.size.closeButton.X, T.size.closeButton.Y), headerBar.ZIndex + 3)
closeBtn.Name = "Close"
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, -10, 0.5, 0)

---------------------------------------------------------------- egg list
-- Full width now. The old layout split 640 into a 392 list and a 176 side
-- column; with quests gone there is no second column, so the list gets all of
-- it and an egg row can carry its art, name, price and action on one line.
-- Sized in SCALE against the padded content box rather than in absolute pixels:
-- UI.panel's own padding already supplies the margin, so subtracting it again
-- here would inset the list twice.
-- Bottom band reserved for the hatch-odds strip, which the kit says REPLACES
-- the cramped per-row list: "same information, but each entry gets a rarity
-- frame, a real drop rate, and enough room to read".
local ODDS_H = 160
local list = new("ScrollingFrame", {
	Name = "EggList",
	Position = UDim2.fromOffset(0, 0),
	Size = UDim2.new(1, 0, 1, -(ODDS_H + 12)),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = T.color.scrollThumb,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = body.ZIndex + 1,
}, body)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, list)

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

-- Rarity colours are the reference's own, not RarityConfig's: the kit ships a
-- four-stop ladder for frames and the game's tier palette does not line up with
-- it. common #C9CCC2 / rare #3FA9F5 / epic #A855F7 / legend #FFB200.
local KIT_RARITY = {
	Rare      = Color3.fromRGB(63, 169, 245),
	Epic      = Color3.fromRGB(168, 85, 247),
	Legendary = Color3.fromRGB(255, 178, 0),
	Mythic    = Color3.fromRGB(168, 85, 247),
	Secret    = Color3.fromRGB(255, 178, 0),
}
local function kitTint(creatureName)
	return KIT_RARITY[rarityOf(creatureName)] or Color3.fromRGB(201, 204, 194)
end

local openButtons = {}
local buyLocked = false
local qtyByEgg = {}  -- [eggId] = 1|3|10; per-egg, remembered (handoff quantity picker)
local selectRow      -- assigned once the odds strip exists
local refreshAffordability -- assigned after the rows exist; qty clicks re-run it
local rowCards = {}  -- { card, egg } for the selection ring
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
	local qty = qtyByEgg[egg.Id] or 1
	-- the recessed "Need N" chassis is not a button; presses on it are ignored
	-- (the server re-checks regardless)
	if darrelsKnown and currentDarrels < egg.Price * qty then return end
	buyLocked = true
	for _, b in ipairs(openButtons) do
		b.Active = false
		b.AutoButtonColor = false
	end
	remotes.EggBuy:FireServer(WORLD_ID, egg.Id, qty)
	task.delay(0.6, function()
		buyLocked = false
		for _, b in ipairs(openButtons) do
			b.Active = true
			b.AutoButtonColor = true
		end
	end)
end

for i, egg in ipairs(world.Eggs) do
	local tint = kitTint(eggTier(egg))
	qtyByEgg[egg.Id] = 1

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

	-- Fixed holder between the layout and the card: the row wrapper's
	-- UIListLayout owns its children's Position, so the handoff's 3px hover
	-- slide has to happen one level down, on a child the layout can't see.
	local cardHolder = new("Frame", {
		Name = "CardHolder",
		Size = UDim2.new(1, 0, 0, ROW_H),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		ZIndex = 13,
	}, row)
	local card = UI.surface(cardHolder, UDim2.new(1, 0, 0, ROW_H), "row", T.radius.control, T.stroke.control)
	card.Name = "Card"
	card.ZIndex = 13
	UI.gloss(card, T.radius.control)
	card.MouseEnter:Connect(function()
		TweenService:Create(card, T.tween.hover, { Position = UDim2.fromOffset(3, 0) }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(card, T.tween.hover, { Position = UDim2.fromOffset(0, 0) }):Play()
	end)

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
		spin = true,
	})
	if not vp then
		local sw = new("Frame", {
			Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4),
			BackgroundColor3 = tint, ZIndex = card.ZIndex + 2,
		}, iconHolder)
		UI.corner(sw, T.radius.art)
	end

	-- NAME COLUMN -- fixed 196 wide (reference: width:196px;flex:0 0 196px),
	-- name stacked over the price chip.
	local NAME_X = 12 + ART + 12
	local nameLabel = UI.label(card, egg.Name, "cardLabel", T.color.white)
	nameLabel.Name = "EggName"
	nameLabel.Position = UDim2.new(0, NAME_X, 0, 12)
	nameLabel.Size = UDim2.fromOffset(196, 26)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.ZIndex = card.ZIndex + 1

	-- price chip (kit: height 30, radius 9, icon + value). Darrel's face leads
	-- the number, the same order the balance pill uses, so a player comparing
	-- price against balance sees the same mark in both places.
	local PRICE_ICON = 24
	local priceChip = new("Frame", {
		Name = "PriceChip",
		Position = UDim2.new(0, NAME_X, 0, 44),
		Size = UDim2.fromOffset(PRICE_ICON + 15 + 52, 30),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.68,
		ZIndex = card.ZIndex + 1,
	}, card)
	UI.corner(priceChip, 9)
	local priceEdge = Instance.new("UIStroke")
	priceEdge.Thickness = 3
	priceEdge.Color = Color3.fromRGB(0, 0, 0)
	priceEdge.Transparency = 0.55
	priceEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	priceEdge.Parent = priceChip

	local priceIcon = new("Frame", {
		Name = "PriceIcon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 5, 0.5, 0),
		Size = UDim2.fromOffset(PRICE_ICON, PRICE_ICON),
		BackgroundTransparency = 1, ZIndex = priceChip.ZIndex + 1,
	}, priceChip)
	if IconArt and IconArt.has("darrel") then
		IconArt.draw(priceIcon, "darrel", PRICE_ICON, priceChip.ZIndex + 1)
	end

	local priceValue = UI.label(priceChip, comma(egg.Price), "chip", T.color.white)
	priceValue.Name = "Value"
	priceValue.AnchorPoint = Vector2.new(0, 0.5)
	priceValue.Position = UDim2.new(0, 5 + PRICE_ICON + 6, 0.5, 0)
	priceValue.Size = UDim2.fromOffset(52, 22)
	priceValue.TextXAlignment = Enum.TextXAlignment.Left
	priceValue.ZIndex = priceChip.ZIndex + 1

	-- ACTION -- 132x56, radius 14, stroke 4. The reference's grey state names
	-- the SHORTFALL ("Need 1,160") rather than just refusing.
	local ACT_W, ACT_H = 132, 56
	local QTY_W, QTY_H, QTY_GAP = 46, 38, 6
	local openBtn = kitButton(card, "Open", "green", UDim2.fromOffset(ACT_W, ACT_H), card.ZIndex + 2)
	openBtn.Name = "Open"
	openBtn.AnchorPoint = Vector2.new(1, 0.5)
	openBtn.Position = UDim2.new(1, -12, 0.5, 0)
	openBtn.Activated:Connect(function() fireBuy(egg) end)
	openButtons[#openButtons + 1] = openBtn
	local openCap = openBtn:FindFirstChildWhichIsA("TextLabel")

	-- The pieces the too-poor state strips (handoff: recessed chassis, "inner
	-- shadow, no drop"): the green lift kit (hard shadow + gloss) hides and a
	-- flat top shade shows instead. The shadow lookup is safe HERE because
	-- openBtn is the only shadow-carrying child of the card so far -- the qty
	-- segments below keep theirs inside their own slot wrappers.
	local openShadow = card:FindFirstChild("HardShadow")
	local openGloss = openBtn:FindFirstChild("Gloss")
	local openShade = openBtn:FindFirstChild("Shade")
	local recessShade = new("Frame", {
		Name = "RecessShade",
		Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.65,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = openBtn.ZIndex,
	}, openBtn)
	UI.corner(recessShade, T.radius.inner)

	-- QUANTITY SEGMENTS -- 46x38, gap 6, active wears the same #FFD84D ring the
	-- selected row does. LIVE as of the egg-shop handoff: the pick is per-egg
	-- state (qtyByEgg), Open sends it, and EggHandler debits price x qty in one
	-- atomic spend.
	local qtyRow = new("Frame", {
		Name = "Qty",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(12 + ACT_W + 12), 0.5, 0),
		Size = UDim2.fromOffset(QTY_W * 3 + QTY_GAP * 2, QTY_H),
		BackgroundTransparency = 1,
		ZIndex = card.ZIndex + 1,
	}, card)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, QTY_GAP),
	}, qtyRow)
	local qtyRings = {}
	for qi, qty in ipairs({ 1, 3, 10 }) do
		-- SLOT WRAPPER, and it is not optional: UI.button parents its hard shadow
		-- as a SIBLING, so dropping three buttons straight into a UIListLayout
		-- gives the layout SIX children -- the three shadows become phantom list
		-- items and shove the real buttons clean past the end of the row, on top
		-- of the Open button. Wrapping each button in its own frame keeps the
		-- shadow inside the slot and out of the layout. This is the codebase-wide
		-- pattern for exactly this reason.
		local slot = new("Frame", {
			Name = "QtySlot" .. qty,
			Size = UDim2.fromOffset(QTY_W, QTY_H),
			BackgroundTransparency = 1,
			LayoutOrder = qi,
			ZIndex = qtyRow.ZIndex,
		}, qtyRow)
		local seg = kitButton(slot, "x" .. qty, "tab", UDim2.fromOffset(QTY_W, QTY_H), qtyRow.ZIndex + 1)
		seg.Name = "Qty" .. qty
		local ring = Instance.new("UIStroke")
		ring.Color = T.color.activeRing
		ring.Thickness = 4
		ring.Transparency = (qty == 1) and 0 or 1
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ring.Parent = seg
		qtyRings[qty] = ring
		seg.Activated:Connect(function()
			qtyByEgg[egg.Id] = qty
			for q, r in pairs(qtyRings) do r.Transparency = (q == qty) and 0 or 1 end
			-- affordability is priced against price x qty, so the pick re-runs it
			if refreshAffordability then refreshAffordability() end
		end)
	end

	-- Selecting a row drives the odds strip below, which is the kit's model:
	-- "Selected row wears a 4px #FFD84D ring and drives the odds strip below."
	local selRing = Instance.new("UIStroke")
	selRing.Color = T.color.activeRing
	selRing.Thickness = 4
	selRing.Transparency = 1
	selRing.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	selRing.Parent = card

	-- stops short of the qty segments and the action so it cannot eat their input
	local hit = new("TextButton", {
		Name = "SelectHit", Text = "", BackgroundTransparency = 1,
		Size = UDim2.new(1, -(12 + ACT_W + 12 + QTY_W * 3 + QTY_GAP * 2 + 12), 1, 0),
		ZIndex = card.ZIndex, AutoButtonColor = false,
	}, card)
	hit.Activated:Connect(function() if selectRow then selectRow(egg) end end)

	rowCards[#rowCards + 1] = { egg = egg, ring = selRing }
	priceRows[#priceRows + 1] = {
		chip = priceChip, edge = priceEdge, value = priceValue,
		button = openBtn, cap = openCap, price = egg.Price, eggId = egg.Id,
		shadow = openShadow, gloss = openGloss, shade = openShade, recess = recessShade,
	}

	-- ODDS ARE DATA-DRIVEN: every line below reads straight from egg.Table
	-- (EggConfig), the exact table EggHandler.RollFor rolls against server-side.
	-- No percentage is ever authored a second time in this file.
end

---------------------------------------------------------------- hatch-odds strip
-- Kit README 3.1: one shared strip under the list, not a per-row dropdown --
-- "This replaces the cramped numbered pet row at the bottom of the old screen
-- -- same information, but each entry gets a rarity frame, a real drop rate,
-- and enough room to read." Values still come straight from egg.Table, so the
-- published odds cannot drift from what EggHandler.RollFor actually uses.
local oddsStrip = UI.surface(body, UDim2.new(1, 0, 0, ODDS_H), "subPanel", T.radius.control, T.stroke.control)
oddsStrip.Name = "OddsStrip"
oddsStrip.AnchorPoint = Vector2.new(0, 1)
oddsStrip.Position = UDim2.new(0, 0, 1, 0)
oddsStrip.ZIndex = body.ZIndex + 1

local oddsTitle = UI.label(oddsStrip, "", "cardLabel", T.color.white)
oddsTitle.Name = "OddsTitle"
oddsTitle.Position = UDim2.fromOffset(12, 10)
oddsTitle.Size = UDim2.fromOffset(420, 26)
oddsTitle.TextXAlignment = Enum.TextXAlignment.Left
oddsTitle.ZIndex = oddsStrip.ZIndex + 1

local oddsNote = UI.label(oddsStrip, "Odds are the live drop rates for this egg", "meta", T.color.textMuted)
oddsNote.AnchorPoint = Vector2.new(1, 0)
oddsNote.Position = UDim2.new(1, -12, 0, 14)
oddsNote.Size = UDim2.fromOffset(340, 20)
oddsNote.TextXAlignment = Enum.TextXAlignment.Right
oddsNote.ZIndex = oddsStrip.ZIndex + 1

local tileRow = new("Frame", {
	Name = "Tiles",
	Position = UDim2.fromOffset(12, 48),
	Size = UDim2.new(1, -24, 0, 94),  -- handoff pool cards are 94 tall
	BackgroundTransparency = 1,
	ZIndex = oddsStrip.ZIndex + 1,
}, oddsStrip)
local tileLayout = new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 10),
}, tileRow)

-- Discovery, for the handoff's "?" covers: the same name-keyed map the Index
-- renders from (GetInitialData / DataUpdated snapshots). EggHandler now writes
-- it on every hatch, so a cover clears the moment the first copy leaves its
-- shell.
local discovered = {}
local selectedEgg

-- Tiles are rebuilt per selection: egg tables differ in length (3 to 5), so a
-- fixed pool would either strand entries or leave holes.
local function buildOddsFor(egg)
	oddsTitle.Text = "Inside the " .. egg.Name
	for _, c in ipairs(tileRow:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	local n = #egg.Table
	for j, tableRow in ipairs(egg.Table) do
		local creature, weight = tableRow[1], tableRow[2]
		local known = discovered[creature] == true
		local tile = UI.surface(tileRow, UDim2.new(1 / n, -10 + 10 / n, 1, 0), "slot", T.radius.inner, T.stroke.control)
		tile.LayoutOrder = j
		tile.ZIndex = tileRow.ZIndex + 1
		local frameRing = Instance.new("UIStroke")
		frameRing.Color = kitTint(creature)
		frameRing.Thickness = 4
		frameRing.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		frameRing.Parent = tile

		-- ART AREA -- a real pet render when the model exists, the name in text
		-- otherwise (the .glb imports are a pending user step, so text is what
		-- most tiles show today).
		local art = new("Frame", {
			Name = "ArtSlot",
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.new(1, -12, 1, -36),
			BackgroundTransparency = 1,
			ZIndex = tile.ZIndex + 1,
		}, tile)
		local vp = addPetViewport(art, creature, PetConfig.IdFor(creature), tile.ZIndex + 1)
		if not vp then
			local nameL = UI.label(art, creature, "meta", T.color.white)
			nameL.Position = UDim2.fromOffset(0, 4)
			nameL.Size = UDim2.new(1, 0, 1, -4)
			nameL.AutomaticSize = Enum.AutomaticSize.None
			nameL.TextWrapped = true
			nameL.TextXAlignment = Enum.TextXAlignment.Center
			nameL.ZIndex = tile.ZIndex + 2
		end

		-- Undiscovered = the handoff's "?" cover -- over the ART ONLY, on
		-- purpose: these are paid random items, so the published chance below
		-- may never be hidden, secret pet or not.
		if not known then
			local cover = new("Frame", {
				Name = "UndiscoveredCover",
				Position = UDim2.fromOffset(4, 4),
				Size = UDim2.new(1, -8, 1, -32),
				BackgroundColor3 = Color3.fromRGB(8, 12, 5),
				BackgroundTransparency = 0.28,
				BorderSizePixel = 0,
				ZIndex = tile.ZIndex + 3,
			}, tile)
			UI.corner(cover, T.radius.slot)
			local q = UI.label(cover, "?", "cardLabel", Color3.fromRGB(122, 138, 102))
			q.TextSize = 34
			q.Size = UDim2.fromScale(1, 1)
			q.AutomaticSize = Enum.AutomaticSize.None
			q.TextXAlignment = Enum.TextXAlignment.Center
			q.ZIndex = cover.ZIndex + 1
		end

		local pct = UI.label(tile, tostring(weight) .. "%", "chip", T.color.textAccent)
		pct.AnchorPoint = Vector2.new(0.5, 1)
		pct.Position = UDim2.new(0.5, 0, 1, -6)
		pct.Size = UDim2.new(1, -12, 0, 18)
		pct.AutomaticSize = Enum.AutomaticSize.None
		pct.TextXAlignment = Enum.TextXAlignment.Center
		pct.ZIndex = tile.ZIndex + 4
	end
end

selectRow = function(egg)
	selectedEgg = egg
	for _, r in ipairs(rowCards) do
		r.ring.Transparency = (r.egg == egg) and 0 or 1
	end
	buildOddsFor(egg)
end
if world.Eggs[1] then selectRow(world.Eggs[1]) end

-- Same subscription shape IndexPanel uses: wholesale replace from the snapshot,
-- then repaint whatever the covers were drawn from.
local function applyDiscovered(snap)
	if typeof(snap) ~= "table" or typeof(snap.Discovered) ~= "table" then return end
	discovered = snap.Discovered
	if selectedEgg then buildOddsFor(selectedEgg) end
end
remotes.DataUpdated.OnClientEvent:Connect(applyDiscovered)
task.spawn(function()
	local ok, snap = pcall(function()
		return remotes:WaitForChild("GetInitialData"):InvokeServer()
	end)
	if ok then applyDiscovered(snap) end
end)

-- Kit README 5, egg-shop state machine: too_poor -> buyable. The price chip goes
-- red and OPEN dims when the balance will not cover the egg. The server still
-- re-checks and refunds -- this only stops the player finding out the hard way.
-- alive pass #4: a buy button that JUST became affordable pops once.
-- Keyed by row; nil = first paint (silent). Only false->true pops.
local wasAffordable = {}
local function popAffordable(btn)
	local ps = btn:FindFirstChild("AffordPop")
	if not ps then
		ps = Instance.new("UIScale")
		ps.Name = "AffordPop"
		ps.Parent = btn
	end
	ps.Scale = 0.9
	TweenService:Create(ps, T.tween.pop, { Scale = 1 }):Play()
end
refreshAffordability = function()
	for _, r in ipairs(priceRows) do
		-- Priced against price x the row's picked quantity: with x10 selected the
		-- action really does cost 10 eggs, so that is the number the state and
		-- the shortfall speak to.
		local need = r.price * (qtyByEgg[r.eggId] or 1)
		local ok = (not darrelsKnown) or currentDarrels >= need
		-- affordable: rgba(0,0,0,.32) on a rgba(0,0,0,.45) edge, white value
		-- too poor:   #C8231C -> #8E120D on #7A1710, #FFD2CC value
		r.chip.BackgroundColor3 = ok and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(200, 35, 28)
		r.chip.BackgroundTransparency = ok and 0.68 or 0
		r.edge.Color = ok and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(122, 23, 16)
		r.edge.Transparency = ok and 0.55 or 0
		r.value.TextColor3 = ok and T.color.white or Color3.fromRGB(255, 210, 204)
		local grad = r.button:FindFirstChildOfClass("UIGradient")
		if grad then grad.Color = ok and T.gradient.green or T.gradient.disabled end
		if ok and wasAffordable[r] == false then popAffordable(r.button) end
		wasAffordable[r] = ok
		-- third chassis (handoff): too-poor is RECESSED -- lift kit hidden, flat
		-- top shade shown, two-line label naming the exact shortfall
		if r.shadow then r.shadow.Visible = ok end
		if r.gloss then r.gloss.Visible = ok end
		if r.shade then r.shade.Visible = ok end
		if r.recess then r.recess.Visible = not ok end
		if r.cap then
			if ok then
				r.cap.Text = "Open"
				r.cap.TextSize = 24
				r.cap.TextColor3 = T.color.white
			else
				r.cap.Text = "Need\n" .. comma(need - currentDarrels)
				r.cap.TextSize = 15
				r.cap.TextColor3 = Color3.fromRGB(184, 196, 164)
			end
			local st = r.cap:FindFirstChildOfClass("UIStroke")
			if st then st.Thickness = ok and 3.5 or 2.5 end
		end
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
-- Full-screen dim + a single ViewportFrame carried through the TEN BEATS of
-- Animation Spec v1 (see the beat constants below for the per-beat numbers):
--
--   B1  egg drops in and settles          B6  squash hold -- "the beat"
--   B2  wobble, ramping 2->7 Hz           B7  shell splits, ballistic halves
--   B3  fracture opens  [TAP]             B8  confetti + shockwave ring
--   B4  fracture crosses [TAP]            B9  pet reveal / settle
--   B5  fracture closes the ring [TAP]    B10 rarity banner, then dismiss
--
-- B2 runs UNDERNEATH B3-B5: unlike the previous build, the egg does NOT go
-- still between hits. The spec is explicit that the egg is shaking the whole
-- time it is cracking and that amplitude and frequency both keep ramping --
-- the escalation is what sells the three hits, not stillness between them.
--
-- Every non-shell part bursts outward at B7. "Non-shell part" rather than a
-- fixed name-prefix whitelist: the five egg models carry a `ring_*`/`tape_*`
-- family alongside the documented shard/drip/spike/horn/stripe/stud/rune/
-- crown/link/cap/halo ones, so matching everything except shell_body_* is what
-- actually covers every decoration on every egg instead of silently stranding
-- a family that was never on the list.
--
-- B3-B5 wait on player input rather than a timer, so they need a way out that a
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

-- ANIMATION SPEC v1 (user, 2026-08-01 -- "Skip Rocks for Brainrots, Animation
-- Spec v1: Egg Hatch Sequence"). Ten beats, one shared skeleton, five tiers.
--
-- ONE DELIBERATE DEVIATION, agreed with the user before this was built: the spec
-- locks out all input from B1 to B10 and fires the three fracture beats off a
-- timer. We keep the TAP -- B3/B4/B5 fire when the player taps the egg. Every
-- other thing here (staging, easing, transforms, escalation, audio order) is the
-- spec's. Because taps are untimed, B6 onward are scheduled RELATIVE to the last
-- tap instead of from an absolute t0, so the back half of the sequence keeps the
-- specified gaps no matter how long the player takes.
local CRACKS_TO_OPEN = 3

-- B1 egg spawn / settle -- 0.00-0.35, Back Out overshoot 1.07
local B1_TIME, B1_DROP, B1_SCALE0, B1_OVER = 0.35, 0.9, 0.82, 1.07
-- B2 wobble build-up -- runs UNDERNEATH B3-B5. The egg shakes the whole time it
-- is cracking and both amplitude and frequency keep ramping. Z axis only, pivot
-- at the shell base: the base never leaves the ground, there is no vertical hop.
local B2_RAMP = 1.70
local B2_AMP0, B2_AMP1 = 5, 14   -- degrees
local B2_HZ0, B2_HZ1 = 2, 7      -- Hz
-- B4 punches scale for one frame as the crack jumps a vertex; B5 bleeds light
local B4_PUNCH, B5_LIGHT = 1.03, 6
-- B6 squash hold -- "the beat". Motion and sound both stop cold.
local B6_TIME, B6_SX, B6_SY = 0.15, 1.14, 0.86
-- B7 shell splits -- ballistic, gravity 0.5x, halves fade at 70% of flight
local B7_TIME, B7_RISE, B7_TILT, B7_BASE_TIP = 0.14, 5, 42, -6
local B7_GRAVITY, B7_FADE_AT = 0.5, 0.70
-- B8 confetti + shockwave -- ring Quint Out
local B8_DELAY, B8_TIME = 0.04, 0.36
local B8_RING0, B8_RING1, B8_RING_A = 0.15, 2.8, 0.85
-- B9 pet reveal -- overlaps the burst by 2 frames so the pet reads as ejected
local B9_DELAY, B9_TIME, B9_S0, B9_OVER, B9_RISE = 0.12, 0.58, 0.25, 1.16, 1.2
-- B10 rarity banner -- slam, settle at -2 degrees, then auto-dismiss
local B10_DELAY, B10_TIME = 0.23, 0.45
local B10_S0, B10_UNDER, B10_REST_TILT, B10_DISMISS = 2.4, 0.93, -2, 0.8

-- The spec's ladder runs common..legendary. This game's pet tiers are
-- Rare..Secret, so the five rungs map by RANK -- the rarest thing in the game
-- gets the loudest treatment. shake is {pixels, seconds}.
local REVEAL_TIER = {
	-- aura is the BackgroundTransparency the pet's tier bloom settles at: lower is
	-- stronger. The escalation table's "none / soft rim / pulse rim / rim+sparks /
	-- rim+beam+sparks" ladder, expressed as one number.
	Rare      = { shards = 6,  parts = 18,  shake = { 0, 0 },     hold = 0,    fov = 0,  aura = 0.92, loud = false, sting = "catchRare" },
	Epic      = { shards = 8,  parts = 34,  shake = { 4, 0.15 },  hold = 0,    fov = -1, aura = 0.86, loud = false, sting = "catchEpic" },
	Legendary = { shards = 10, parts = 56,  shake = { 9, 0.25 },  hold = 0,    fov = -3, aura = 0.78, loud = true,  sting = "catchLegend" },
	Mythic    = { shards = 12, parts = 84,  shake = { 14, 0.30 }, hold = 0.25, fov = -5, aura = 0.70, loud = true,  sting = "catchMythic" },
	Secret    = { shards = 14, parts = 120, shake = { 18, 0.35 }, hold = 0.50, fov = -8, aura = 0.62, loud = true,  sting = "catchSecret" },
}

-- Spec cue sheet -> SoundKit. Every cue already exists in the kit. The one with
-- no equivalent is B6's -12 dB bus duck: SoundKit has no bus API, so the beat
-- gets its silence by simply having nothing scheduled into it.
local SFX_CRACK = { "eggCrack1", "eggCrack2", "eggCrack3" }
local SFX_CRACK_SPEED = { 1.0, 1.122, 0.95 } -- B4 is "+2 semitones"; B5 is the long tear
local SFX_CRACK_VOL = { 0.34, 0.40, 0.48 }

local TAP_DEBOUNCE = 0.15   -- so mashing cannot land all three hits inside one frame
local TAP_TIMEOUT = 3.5     -- the reveal must never wait forever
local TAP_TIMEOUT_FAST = 0.9
local MAX_EXPLODE = 24
local CRACK_DIST_MULT = 2.4
local FADE_TIME = 0.3
local DIM_TARGET = 0.72   -- the world has to RECEDE; 0.35 left it fully legible
local REVEAL_BLUR = 24    -- spec build note: 0.4s blur so nothing else competes
local SKIP_GRACE = 0.35
local CRACK_DARK = Color3.fromRGB(14, 10, 9)

-- Spec fracture: ONE jagged loop near the equator, as percentages of the egg's
-- box. The same vertex list drives the crack line AND the cut the two shell
-- halves separate along, so B7 reads as the same crack finishing its job.
local FRACTURE = {
	{ 0, 49 }, { 9, 44 }, { 17, 51 }, { 26, 45 }, { 34, 52 }, { 43, 46 }, { 51, 53 },
	{ 59, 45 }, { 68, 51 }, { 76, 44 }, { 85, 51 }, { 93, 45 }, { 100, 50 },
}
local SEG_PER_HIT = math.ceil((#FRACTURE - 1) / CRACKS_TO_OPEN) -- 4

local function volumeOf(part)
	local s = part.Size
	return s.X * s.Y * s.Z
end

local function tierOf(rarity)
	return REVEAL_TIER[rarity] or REVEAL_TIER.Rare
end

-- Two-stage overshoot. Roblox's Back easing has a fixed overshoot, but the spec
-- names exact peaks (1.07, 1.16, 0.93), so the curve is driven explicitly: rise
-- to the peak over most of the beat, then settle to 1.
local function overshoot(p, from, peak)
	if p < 0.7 then
		local q = p / 0.7
		return from + (peak - from) * (1 - (1 - q) ^ 2)
	end
	local q = (p - 0.7) / 0.3
	return peak + (1 - peak) * (1 - (1 - q) ^ 2)
end

-- The seam is REAL GEOMETRY ON THE SHELL, not a line drawn over the viewport.
--
-- It used to be flat UI bars in a CanvasGroup layered on top of the egg, and it
-- read as a sticker rather than as damage: square ends poked past the egg's
-- curved silhouette, nothing was ever occluded as the seam wrapped around the
-- back, it took no light, and it sat perfectly still while the egg wobbled
-- underneath it. These are small parts sitting just proud of the shell's
-- ellipsoid instead, so the seam curves with the surface, hides itself round
-- the back, shades with the viewport light, and rides the wobble, the B4 punch
-- and the B6 squash for free because it is parented into the egg model.
local RING_N = #FRACTURE - 1 -- 12 segments around the loop

-- Surface point of the shell ellipsoid at a given angle round Y and a signed
-- height fraction (yfrac = 0 is the equator, +1 the top).
local function seamPoint(a, b, c, theta, yfrac)
	local k = math.sqrt(math.max(0, 1 - yfrac * yfrac))
	return Vector3.new(a * k * math.sin(theta), b * yfrac, c * k * math.cos(theta))
end

-- Ellipsoid normal: the gradient of x^2/a^2 + y^2/b^2 + z^2/c^2, which is what
-- makes the segment lie FLAT on a curved surface instead of tangent to a sphere
-- it is not actually on (the shells are 1.88 x 2.40, nowhere near round).
local function seamNormal(a, b, c, p)
	return Vector3.new(p.X / (a * a), p.Y / (b * b), p.Z / (c * c)).Unit
end

-- k is 1..RING_N. Returns the dark part and its tier-coloured glow, both
-- parented into the egg model so every later transform carries them.
local function seamSegment(shell, parent, k, accent)
	local a, b, c = shell.Size.X / 2, shell.Size.Y / 2, shell.Size.Z / 2
	-- fractional index -> a point on the seam, so the segment's MIDPOINT can be
	-- put back on the surface; a chord midpoint sags inside the shell and the
	-- segment would sink into it
	local function at(t)
		local i0 = math.floor(t)
		local f = t - i0
		local v0 = FRACTURE[((i0 - 1) % RING_N) + 1]
		local v1 = FRACTURE[(i0 % RING_N) + 1]
		-- spec y% is measured DOWN the screen with 50% at the equator
		local y0 = (0.5 - v0[2] / 100) * 2
		local y1 = (0.5 - v1[2] / 100) * 2
		return seamPoint(a, b, c, ((t - 1) / RING_N) * math.pi * 2, y0 + (y1 - y0) * f)
	end

	local p1, p2, pm = at(k), at(k + 1), at(k + 0.5)
	local tangent = (p2 - p1)
	if tangent.Magnitude < 1e-4 then return nil, nil end
	local n = seamNormal(a, b, c, pm)
	local width = shell.Size.X * 0.030
	local depth = width * 0.7
	-- 1.10 so consecutive segments overlap at the joints and the seam stays
	-- unbroken through every kink
	local len = tangent.Magnitude * 1.10

	local function mk(name, w, d, l, out, colour, material, transparency)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = Vector3.new(w, d, l)
		-- lookAt puts -Z along the tangent and Y along the surface normal, so the
		-- part's length runs round the egg and its thickness stands off the surface
		p.CFrame = shell.CFrame * CFrame.lookAt(pm + n * out, pm + n * out + tangent, n)
		p.Color = colour
		p.Material = material
		p.Transparency = transparency
		p.Anchored, p.CanCollide, p.CanQuery, p.CastShadow = true, false, false, false
		p.Parent = parent
		return p
	end

	-- glow sits slightly INSIDE the dark bar and is wider, so at B5 it reads as
	-- light escaping from behind the crack rather than as a painted outline
	local glow = mk("seamGlow", width * 2.4, depth * 0.9, len * 1.02, depth * 0.05,
		accent, Enum.Material.Neon, 1)
	local bar = mk("crackSeg", width, depth, len, depth * 0.45,
		CRACK_DARK, Enum.Material.SmoothPlastic, 0)
	return bar, glow
end

-- Shared by BOTH reveals (single and multi): the generation counter is what
-- makes a second EggResult arriving mid-reveal safe, and revealSkip is the
-- handle whichever reveal is live registers so the next one can end it.
local revealGen, revealSkip = 0, nil

-- Mean height of the fracture loop, as a signed fraction of ry. The two halves
-- part on this line, and the seam geometry drawn during B3-B5 straddles it.
local function fractureMeanFrac()
	local sum = 0
	for _, v in ipairs(FRACTURE) do sum += (v[2] / 100 - 0.5) * 2 end
	return sum / #FRACTURE
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
	local T = tierOf(result.Rarity)

	-- Tone B from the spec's three banner options -- the one it recommends
	-- itself: "lets the FX carry the excitement, scales best across all five
	-- tiers and reads well on small mobile screens".
	local chanceText
	if eggDef and eggDef.Table then
		local total, mine = 0, nil
		for _, row in ipairs(eggDef.Table) do
			total += (row[2] or 0)
			if row[1] == result.Name then mine = row[2] end
		end
		if mine and total > 0 then
			local pct = mine / total * 100
			chanceText = (pct < 0.1 and string.format("%.3f%% chance", pct))
				or (pct < 1 and string.format("%.2f%% chance", pct))
				or string.format("%.1f%% chance", pct)
		end
	end

	local root = new("Frame", {
		Name = "Reveal", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1,
	}, ensureRevealGui())

	-- Spec backdrop: radial #26301c centre -> #141a10 edge. UIGradient is linear
	-- only, so the radial is built as a soft olive pool over the edge colour --
	-- much closer to the spec than the flat black that was here.
	local dim = new("Frame", {
		Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(20, 26, 16),
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1,
	}, root)
	local pool = new("Frame", {
		Name = "BackdropPool", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.35, 1.35), BackgroundColor3 = Color3.fromRGB(38, 48, 28),
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1,
	}, root)
	UITheme.corner(pool, 9999)
	TweenService:Create(dim, TweenInfo.new(FADE_TIME), { BackgroundTransparency = 1 - DIM_TARGET }):Play()
	TweenService:Create(pool, TweenInfo.new(FADE_TIME), { BackgroundTransparency = 0.55 }):Play()

	local holder = new("Frame", {
		Name = "Holder", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(VP_SIZE, VP_SIZE + 96), BackgroundTransparency = 1, ZIndex = 2,
	}, root)

	-- Spec: "the egg is centred on both axes and sized as a fraction of the
	-- shorter viewport edge". The stage is authored against a fixed 320 design
	-- size, so rather than thread a live size through every measurement, one
	-- UIScale maps that design size onto the actual screen. B9's pop drives this
	-- same UIScale -- a second one on the same object would not stack.
	local vpSize = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local stageScale = math.clamp(math.min(vpSize.X, vpSize.Y) * 0.62 / VP_SIZE, 0.65, 1.8)
	local stageUI = new("UIScale", { Scale = stageScale }, holder)

	local clickCatcher = new("TextButton", {
		Name = "ClickCatcher", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 20,
	}, root)

	frame.Visible = false -- hide the shop panel behind the reveal overlay

	local fades = { { dim, "BackgroundTransparency" }, { pool, "BackgroundTransparency" } }

	local conn
	local dead = false
	local elapsed = 0
	local spinFn, splitFn, shakeFn
	local shellPart, decorations, crackParts, glowParts = nil, {}, {}, {}
	local eggRx, eggRy -- shell half-extents in stage pixels; the B8 ring is sized off these
	local splitting = false
	local canSkip = false

	-- Spec build note: "Show the sequence in a full-screen ScreenGui with a 0.4 s
	-- blur on the world behind it so nothing else competes." Without this the
	-- shop shelf, the egg-keeper NPC and the player's own character stay fully
	-- legible behind the reveal and fight it the entire time.
	local blur = Instance.new("BlurEffect")
	blur.Name = "EggRevealBlur"
	blur.Size = 0
	blur.Parent = game:GetService("Lighting")
	TweenService:Create(blur, TweenInfo.new(0.4), { Size = REVEAL_BLUR }):Play()

	-- The "E / Open" ProximityPrompt renders in 3D space and drew straight over
	-- the egg for the whole sequence. It is world input during a cutscene, so it
	-- goes off with everything else.
	local prompts = game:GetService("ProximityPromptService")
	prompts.Enabled = false

	-- Spec: "Nothing else in the frame -- no chrome, no buttons, no odds display
	-- -- is part of this sequence." The HUD, currency pills, quest tracker,
	-- hotbar and the Roblox topbar were all still on screen competing with it.
	local StarterGui = game:GetService("StarterGui")
	local myGui = root.Parent
	local hiddenGuis = {}
	for _, g in ipairs(myGui.Parent:GetChildren()) do
		if g:IsA("ScreenGui") and g ~= myGui and g.Enabled then
			g.Enabled = false
			hiddenGuis[#hiddenGuis + 1] = g
		end
	end
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
	-- SetCoreGuiEnabled does NOT cover the topbar; it needs its own SetCore call
	pcall(function() StarterGui:SetCore("TopbarEnabled", false) end)

	local function skip()
		if dead then return end
		dead = true
		revealGen += 1
		if revealSkip == skip then revealSkip = nil end
		if conn then conn:Disconnect(); conn = nil end
		clickCatcher.Active = false
		prompts.Enabled = true
		for _, g in ipairs(hiddenGuis) do
			if g.Parent then g.Enabled = true end
		end
		pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true) end)
		pcall(function() StarterGui:SetCore("TopbarEnabled", true) end)
		if blur then
			local dyingBlur = blur
			blur = nil
			TweenService:Create(dyingBlur, TweenInfo.new(FADE_TIME), { Size = 0 }):Play()
			task.delay(FADE_TIME + 0.05, function() dyingBlur:Destroy() end)
		end
		for _, f in ipairs(fades) do
			TweenService:Create(f[1], TweenInfo.new(FADE_TIME), { [f[2]] = 1 }):Play()
		end
		frame.Visible = true
		task.delay(FADE_TIME, function()
			if root then root:Destroy(); root = nil end
		end)
	end
	revealSkip = skip
	-- Spec: input is sunk for the whole sequence. The catcher stays Active so
	-- stray clicks are SWALLOWED rather than passed through to the world; it does
	-- nothing until B10 unlocks input on its last frame.
	clickCatcher.Activated:Connect(function()
		if canSkip then skip() end
	end)

	---------------------------------------------------- B1  spawn / settle
	local eggClone, basePivot, eggVp, eggCam, eggCentre, eggDist
	local eggStage, innerLight
	-- The egg models are NOT authored at scale 1 -- ForestEgg1/2 sit at 2.00,
	-- Egg3 at 1.83, Egg4 at 1.94. Model:ScaleTo takes an ABSOLUTE factor, so
	-- ScaleTo(0.82) does not mean "82% of this egg", it means "82% of the raw
	-- asset" -- which shrank every egg to roughly half size and left it there,
	-- while eggRx and the camera framing had already been measured at full size.
	-- Every B1 scale below is therefore expressed RELATIVE to this.
	local eggBaseScale = 1
	local eggMasterModel = eggModelName and eggMaster(eggModelName)
	if eggMasterModel then
		-- eggVp and crackLayer share a centred stage so B6 can squash both at once
		eggStage = new("Frame", {
			Name = "EggStage", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(VP_SIZE / 2, VP_SIZE / 2),
			Size = UDim2.fromOffset(VP_SIZE, VP_SIZE), BackgroundTransparency = 1, ZIndex = 3,
		}, holder)

		eggVp = new("ViewportFrame", {
			Name = "EggViewport", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(VP_SIZE, VP_SIZE), BackgroundTransparency = 1, ZIndex = 3,
		}, eggStage)
		eggCam = new("Camera", { FieldOfView = EGG_FOV }, eggVp)
		eggVp.CurrentCamera = eggCam
		eggClone = eggMasterModel:Clone()
		eggClone.Parent = eggVp
		basePivot = eggClone:GetPivot()
		eggCentre, eggDist = BrainrotThumb.framing(eggClone, EGG_FOV)
		eggCam.CFrame = CFrame.lookAt(eggCentre + BrainrotThumb.DEFAULT_DIR * eggDist, eggCentre)

		shellPart = eggClone:FindFirstChild("shell_body_1")
		for _, d in ipairs(eggClone:GetDescendants()) do
			if d:IsA("BasePart") and d ~= shellPart then
				decorations[#decorations + 1] = d
			end
		end
		table.sort(decorations, function(a, b) return volumeOf(a) > volumeOf(b) end)

		if shellPart then
			local perStud = (VP_SIZE / 2) / (math.tan(math.rad(EGG_FOV / 2)) * eggDist)
			eggRx = shellPart.Size.X / 2 * perStud
			eggRy = shellPart.Size.Y / 2 * perStud

			-- B5's inner light, tinted to the tier: it bleeds through the gap as
			-- the seam closes the ring, so the player learns the rarity HERE,
			-- a beat before the reveal.
			innerLight = Instance.new("PointLight")
			innerLight.Color = accent
			innerLight.Brightness = 0
			innerLight.Range = shellPart.Size.X * 3
			innerLight.Parent = shellPart
		end

		-- the drop itself, relative to whatever scale this egg was authored at
		eggBaseScale = eggClone:GetScale()
		eggClone:ScaleTo(eggBaseScale * B1_SCALE0)
		SoundKit.play("place", nil, { volume = 0.35, speed = 0.9 })
	end

	local beginCracking, armTap, crackBeat, squashHold, splitPhase, burstPhase, creaturePhase, bannerPhase

	---------------------------------------------------- per-frame driver
	-- ONE RenderStepped connection drives every per-frame animation in this
	-- reveal: the B1 settle, the B2 wobble, the B7 ballistic halves, the tier
	-- camera shake and the pet idle. Phases hand it functions; it never branches
	-- on phase state itself.
	local wobbleStart, wobbleFrozen = nil, false
	local punchUntil = 0

	conn = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt

		if eggClone and basePivot and not splitting then
			local scale, lift = 1, 0
			if elapsed < B1_TIME then
				local p = elapsed / B1_TIME
				scale = overshoot(p, B1_SCALE0, B1_OVER)
				lift = (1 - (1 - p) ^ 2) * B1_DROP - B1_DROP
			end
			if punchUntil > elapsed then scale = scale * B4_PUNCH end

			local ang = 0
			if wobbleStart and not wobbleFrozen then
				local w = math.clamp((elapsed - wobbleStart) / B2_RAMP, 0, 1)
				local amp = B2_AMP0 + (B2_AMP1 - B2_AMP0) * w
				local hz = B2_HZ0 + (B2_HZ1 - B2_HZ0) * w
				ang = math.rad(amp) * math.sin((elapsed - wobbleStart) * hz * (2 * math.pi))
			end

			-- pivot at the SHELL BASE, Z only: the egg rocks on its heel, it does
			-- not swing about its middle and it never leaves the ground
			local baseY = shellPart and (shellPart.Size.Y / 2) or 0
			local toBase = CFrame.new(0, -baseY, 0)
			eggClone:PivotTo(basePivot
				* CFrame.new(0, lift, 0)
				* toBase * CFrame.Angles(0, 0, ang) * toBase:Inverse())
			local want = eggBaseScale * scale
			if math.abs(eggClone:GetScale() - want) > 0.001 then
				eggClone:ScaleTo(want)
			end
		end

		if splitFn then splitFn(elapsed) end
		if shakeFn then shakeFn(elapsed) end
		if spinFn then spinFn(elapsed) end
	end)

	-- B2 starts as soon as the egg has settled and runs until the squash
	task.delay(B1_TIME, function()
		if myGen ~= revealGen then return end
		wobbleStart = elapsed
		SoundKit.play("eggStrain", nil, { volume = 0.18, speed = 0.9 })
		beginCracking()
	end)

	---------------------------------------------------- B3-B5  fracture (tap-driven)
	local rng = Random.new()
	local hits = 0
	local tapToken = 0
	local lastTap = -1
	local timedOut = false
	local crackBtn, hintLabel

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
			crackBeat()
		end)
	end

	beginCracking = function()
		if not (eggClone and shellPart and eggVp and eggRx) then
			squashHold()
			return
		end

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

		crackBtn.Activated:Connect(function()
			if myGen ~= revealGen or hits >= CRACKS_TO_OPEN then return end
			if elapsed - lastTap < TAP_DEBOUNCE then return end
			lastTap = elapsed
			crackBeat()
		end)

		armTap()
	end

	-- Reveals the next third of the ONE equatorial seam. The tap no longer places
	-- the fracture -- the spec's whole read is "this egg is about to come apart in
	-- two", which a crack starting wherever the finger landed cannot deliver.
	crackBeat = function()
		hits += 1
		local n = math.min(hits, CRACKS_TO_OPEN)
		SoundKit.play(SFX_CRACK[n], nil, { volume = SFX_CRACK_VOL[n], speed = SFX_CRACK_SPEED[n] })

		local first = (n - 1) * SEG_PER_HIT + 1
		local last = math.min(n * SEG_PER_HIT, RING_N)
		for i = first, last do
			local bar, glow = seamSegment(shellPart, eggClone, i, accent)
			if bar then
				crackParts[#crackParts + 1] = bar
				glowParts[#glowParts + 1] = glow
			end
		end

		-- B4: a one-frame scale punch as the crack jumps a vertex
		punchUntil = elapsed + 0.035

		-- B5: seam and wobble peak together, then tier-coloured light bleeds
		-- along the whole crack line and out through the gap
		if n >= CRACKS_TO_OPEN then
			for _, g in ipairs(glowParts) do
				TweenService:Create(g, TweenInfo.new(0.22), { Transparency = 0.25 }):Play()
			end
			if innerLight then
				TweenService:Create(innerLight, TweenInfo.new(0.22), { Brightness = B5_LIGHT }):Play()
			end
			hidePrompt()
			task.delay(0.22, function()
				if myGen ~= revealGen then return end
				squashHold()
			end)
		else
			armTap()
		end
	end

	---------------------------------------------------- B6  squash hold
	-- The beat. Motion and sound both stop cold on a compressed shell, and the
	-- rarest tiers extend the pause -- the spec is explicit that the pause is the
	-- hype, not the effect.
	squashHold = function()
		wobbleFrozen = true
		if eggClone and basePivot then eggClone:PivotTo(basePivot) end
		-- Squash is applied to the VIEWPORT rather than the model: Model:ScaleTo is
		-- uniform and cannot do 1.14x / 0.86y. Re-rendering the same scene into a
		-- wider, shorter rect gives exactly the compressed silhouette the spec asks
		-- for. The crack layer is left alone for these 0.15s -- it is about to be
		-- replaced by the split, and chasing 12 segment transforms for one beat
		-- would buy nothing visible.
		if eggVp then
			TweenService:Create(eggVp, TweenInfo.new(B6_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.fromOffset(VP_SIZE * B6_SX, VP_SIZE * B6_SY),
			}):Play()
		end
		task.delay(B6_TIME + T.hold, function()
			if myGen ~= revealGen then return end
			splitPhase()
		end)
	end

	---------------------------------------------------- B7  shell splits in half
	splitPhase = function()
		splitting = true
		SoundKit.play("eggSplit", nil, { volume = 0.5 })

		-- One white flash frame at burst, across the WHOLE frame -- in the reference
		-- the entire backdrop goes white for a frame, not just the egg's stage.
		local flashFrame = new("Frame", {
			Name = "SplitFlash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.12, BorderSizePixel = 0, ZIndex = 30,
		}, root)
		task.delay(0.05, function() if flashFrame then flashFrame:Destroy() end end)

		if eggClone and shellPart and eggRx and eggStage and eggCam then
			-- THE HALVES ARE THE REAL EGG, CLIPPED -- not a drawing of it.
			--
			-- An earlier pass rebuilt the shell out of 40 flat rectangles. That put the
			-- egg's SILHOUETTE on a 40-step staircase (the "pixelated egg") and threw
			-- away the model itself: studs, stripes, shading, all of it replaced by a
			-- plain coloured blob. Wrong trade. Here each half is a ClipsDescendants
			-- CanvasGroup holding a ViewportFrame that renders the ACTUAL egg model, so
			-- the outline stays a clean 3D render and every decoration survives the
			-- split. The clip window is the only thing that differs between them.
			--
			-- The parting line itself is straight; what reads as jagged is the seam
			-- geometry already sitting on the shell, which is cloned into both halves
			-- and tears apart with them.
			local cutY = VP_SIZE / 2 + fractureMeanFrac() * eggRy

			local function makeHalf(isTop)
				local clip = new("CanvasGroup", {
					Name = isTop and "ShellTop" or "ShellBase",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(VP_SIZE / 2, isTop and cutY / 2 or (cutY + VP_SIZE) / 2),
					Size = UDim2.fromOffset(VP_SIZE, isTop and cutY or (VP_SIZE - cutY)),
					BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 6,
				}, eggStage)
				local v = new("ViewportFrame", {
					-- offset back up so the egg lands in exactly the place it was already
					-- rendered; the clip window is what selects this half
					Position = UDim2.fromOffset(0, isTop and 0 or -cutY),
					Size = UDim2.fromOffset(VP_SIZE, VP_SIZE),
					BackgroundTransparency = 1, ZIndex = 6,
				}, clip)
				local cam = new("Camera", { FieldOfView = eggCam.FieldOfView, CFrame = eggCam.CFrame }, v)
				v.CurrentCamera = cam
				local c = eggClone:Clone()
				c.Parent = v
				return clip
			end

			local topHalf, botHalf = makeHalf(true), makeHalf(false)
			if eggVp then eggVp.Visible = false end

			-- studs-to-pixels, so the spec's "+5 studs" lands as the right distance on
			-- screen rather than an arbitrary pixel count
			local perStud = eggRx / (shellPart.Size.X / 2)
			local riseV = (B7_RISE * perStud) / (B7_TIME * 2)
			local topHome, botHome = topHalf.Position, botHalf.Position
			local t0 = elapsed
			-- BALLISTIC, gravity 0.5x -- the top cap launches up and back and tumbles
			-- as it goes; the base just rocks back on its heel and stays.
			splitFn = function(t)
				local age = t - t0
				local p = math.min(age / (B7_TIME * 4), 1)
				local y = riseV * age - 0.5 * (perStud * 60 * B7_GRAVITY) * age * age
				topHalf.Position = topHome - UDim2.fromOffset(0, y)
				topHalf.Rotation = B7_TILT * 0.45 * p
				botHalf.Position = botHome
				botHalf.Rotation = B7_BASE_TIP * p
				if p > B7_FADE_AT then
					local f = (p - B7_FADE_AT) / (1 - B7_FADE_AT)
					topHalf.GroupTransparency = f
					botHalf.GroupTransparency = f
				end
				if p >= 1 then splitFn = nil end
			end
			task.delay(B7_TIME * 4 + 0.1, function()
				if topHalf then topHalf:Destroy() end
				if botHalf then botHalf:Destroy() end
			end)
		end

		-- The seam now RIDES the halves (see above) instead of being faded on the
		-- spot, so it only needs clearing once the flight is over. Destroyed rather
		-- than left at transparency 1: leaving it parented is what used to keep the
		-- cracks hanging over the opened pet.
		local seam = {}
		for _, p in ipairs(crackParts) do seam[#seam + 1] = p end
		for _, p in ipairs(glowParts) do seam[#seam + 1] = p end
		crackParts, glowParts = {}, {}
		task.delay(B7_TIME * 4 + 0.1, function()
			for _, p in ipairs(seam) do if p.Parent then p:Destroy() end end
		end)

		-- chips spray off the seam; the halves are the story, chips are seasoning
		if eggClone then
			local centre = (shellPart and shellPart.Position) or basePivot.Position
			for i, part in ipairs(decorations) do
				if i <= MAX_EXPLODE then
					local target = centre + (part.Position - centre) * CRACK_DIST_MULT
					TweenService:Create(part, TweenInfo.new(B7_TIME * 3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						CFrame = CFrame.new(target) * (part.CFrame - part.CFrame.Position),
						Transparency = 1,
					}):Play()
				else
					part.Transparency = 1
				end
			end
		end

		-- tier camera shake. The spec shakes the world camera; this reveal is a UI
		-- overlay, and its own build note warns against touching CameraOffset while
		-- the player is moving -- so the STAGE is shaken instead. Same read, and it
		-- cannot interfere with whatever the character is doing behind the dim.
		if T.shake[1] > 0 then
			local amp, dur = T.shake[1], T.shake[2]
			local s0 = elapsed
			local homeX, homeY = VP_SIZE / 2, VP_SIZE / 2
			shakeFn = function(t)
				local age = t - s0
				if age > dur or not eggStage then
					if eggStage then eggStage.Position = UDim2.fromOffset(homeX, homeY) end
					shakeFn = nil
					return
				end
				local decay = 1 - age / dur
				eggStage.Position = UDim2.fromOffset(
					homeX + rng:NextNumber(-amp, amp) * decay,
					homeY + rng:NextNumber(-amp, amp) * decay)
			end
		end
		-- FOV punch on the egg camera, which IS ours to move. Spec: fires on the
		-- same frame as the shake and EASES BACK over 0.4s -- it was being left
		-- punched before, which only went unnoticed because the egg viewport is torn
		-- down a fraction of a second later.
		if eggCam and T.fov ~= 0 then
			eggCam.FieldOfView = EGG_FOV + T.fov
			TweenService:Create(eggCam, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				FieldOfView = EGG_FOV,
			}):Play()
		end

		task.delay(B8_DELAY, function()
			if myGen ~= revealGen then return end
			burstPhase()
		end)
		task.delay(B8_DELAY + B9_DELAY, function()
			if myGen ~= revealGen then return end
			creaturePhase()
		end)
	end

	---------------------------------------------------- B8  confetti + shockwave
	burstPhase = function()
		SoundKit.play("eggCrumbleBig", nil, { volume = 0.30 + 0.002 * T.parts, speed = 1.05 })

		local burst = new("Frame", {
			Name = "Burst", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(VP_SIZE / 2, VP_SIZE / 2),
			Size = UDim2.fromOffset(VP_SIZE, VP_SIZE), BackgroundTransparency = 1, ZIndex = 10,
		}, holder)

		-- Tier-coloured ring, Quint Out. Sized against the EGG, not the stage: the
		-- spec's 0.15 -> 2.8 is relative to its own egg, and taking it against
		-- VP_SIZE instead blew the ring out to 896px -- wider than the whole screen.
		local ringBase = (eggRx and eggRx * 2) or (VP_SIZE * 0.55)
		local ring = new("Frame", {
			Name = "Shockwave", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(ringBase * B8_RING0, ringBase * B8_RING0),
			BackgroundTransparency = 1, ZIndex = 10,
		}, burst)
		UITheme.corner(ring, 999)
		local ringStroke = Instance.new("UIStroke")
		ringStroke.Color = accent
		ringStroke.Thickness = 6
		ringStroke.Transparency = 1 - B8_RING_A
		ringStroke.Parent = ring
		local quint = TweenInfo.new(B8_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		TweenService:Create(ring, quint, {
			Size = UDim2.fromOffset(ringBase * B8_RING1, ringBase * B8_RING1),
		}):Play()
		TweenService:Create(ringStroke, quint, { Transparency = 1, Thickness = 1 }):Play()

		-- particle count scales by tier; capped for mobile the same way the spec's
		-- own reference caps its preview
		local count = math.min(T.parts, 60)
		for i = 1, count do
			local ang = (i / count) * math.pi * 2 + 1.1
			local dist = 90 + ((i * 53) % 160)
			local isDot = (i % 4 == 0)
			local p = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(isDot and 5 or 8, isDot and 5 or 3),
				BackgroundColor3 = (i % 5 == 0) and Color3.new(1, 1, 1) or accent,
				BorderSizePixel = 0, Rotation = (i * 131) % 360, ZIndex = 10,
			}, burst)
			if isDot then UITheme.corner(p, 999) end
			local ease = TweenInfo.new(B8_TIME * 3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(p, ease, {
				Position = UDim2.fromOffset(VP_SIZE / 2 + math.cos(ang) * dist,
					VP_SIZE / 2 + math.sin(ang) * dist * 0.8 + 60),
				Rotation = ((i * 131) % 720),
				BackgroundTransparency = 1,
			}):Play()
		end

		-- chip shards off the seam, in the colour of the shell they came off
		local shellColour = (shellPart and shellPart.Color) or accent
		for i = 1, T.shards do
			local ang = (i % 2 == 1 and 1 or -1) * (0.15 + ((i * 29) % 60) / 100) + (i % 2 == 1 and math.pi or 0)
			local dist = 90 + ((i * 37) % 80)
			local s = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48),
				Size = UDim2.fromOffset(11, 13), BackgroundColor3 = shellColour,
				BorderSizePixel = 0, Rotation = 0, ZIndex = 10,
			}, burst)
			TweenService:Create(s, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(VP_SIZE / 2 + math.cos(ang) * dist,
					VP_SIZE * 0.48 + math.sin(ang) * dist - 40),
				Rotation = ((i * 97) % 540) - 180,
				BackgroundTransparency = 1,
			}):Play()
		end

		task.delay(B8_TIME * 3, function() if burst then burst:Destroy() end end)
	end

	---------------------------------------------------- B9  pet reveal / settle
	creaturePhase = function()
		if eggVp then eggVp:Destroy(); eggVp = nil end
		eggClone, splitFn = nil, nil
		SoundKit.play(T.sting, nil, { volume = 0.45 })

		-- TIER AURA. In the reference the pet sits in a big tier-coloured bloom, and
		-- it is most of why the reveal reads as a payoff rather than a card appearing.
		-- The escalation table carried an `aura` field from the start; nothing had
		-- ever drawn it until now.
		local aura = new("Frame", {
			Name = "PetAura", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(VP_SIZE / 2, VP_SIZE / 2),
			Size = UDim2.fromOffset(VP_SIZE * 0.6, VP_SIZE * 0.6),
			BackgroundColor3 = accent, BackgroundTransparency = 1,
			BorderSizePixel = 0, ZIndex = 11,
		}, holder)
		UITheme.corner(aura, 9999)
		table.insert(fades, { aura, "BackgroundTransparency" })
		TweenService:Create(aura, TweenInfo.new(B9_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(VP_SIZE * 1.55, VP_SIZE * 1.55),
			BackgroundTransparency = T.aura,
		}):Play()

		local card, outer = UITheme.accentCard(holder, accent, 20)
		outer.Name = "RevealTile"
		outer.Size = UDim2.fromOffset(VP_SIZE + 20, VP_SIZE + 20)
		outer.Position = UDim2.fromOffset(-10, -10)
		outer.ZIndex = 12
		card.ZIndex = 13
		RarityFX.attach(outer, card, result.Rarity, accent, 0)
		table.insert(fades, { outer, "BackgroundTransparency" })
		table.insert(fades, { card, "BackgroundTransparency" })

		local creatureVp = new("ViewportFrame", {
			Name = "CreatureViewport", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 14,
		}, card)
		local ccam = new("Camera", { FieldOfView = 30 }, creatureVp)
		creatureVp.CurrentCamera = ccam
		table.insert(fades, { creatureVp, "ImageTransparency" })

		-- Scale 0.25 -> 1.16 -> 1.00 with a matching rise, driven explicitly
		-- because the spec names the peak. On holder rather than the tile: holder
		-- is the only node here anchored at its own centre, so the tile would
		-- otherwise grow out of its top-left corner.
		-- Drives the stage's EXISTING UIScale rather than adding a second one: two
		-- UIScales on the same object do not compose, so a fresh one would throw
		-- away the responsive stage scale computed at setup.
		stageUI.Scale = stageScale * B9_S0
		local homePos = holder.Position
		local petStart = elapsed
		local settled = false
		local petFn = function(t)
			local p = math.min((t - petStart) / B9_TIME, 1)
			stageUI.Scale = stageScale * overshoot(p, B9_S0, B9_OVER)
			holder.Position = homePos + UDim2.fromOffset(0, (1 - p) * B9_RISE * 24)
			if p >= 1 and not settled then settled = true end
		end

		local master = petMaster(result.Name, result.PetId)
		if master then
			local m = master:Clone()
			m.Parent = creatureVp
			local centre, dist = BrainrotThumb.framing(m, 30)
			local rest = m:GetPivot()
			local hopScale = dist * 0.05
			spinFn = function(t)
				petFn(t)
				local age = t - petStart
				-- idle animation takes over on landing
				local bob = settled and math.sin(age * 2.4) * 0.12 or 0
				m:PivotTo(rest + Vector3.new(0, bob * hopScale, 0))
				local ang = (age / 2.0) * (2 * math.pi)
				local dir = CFrame.Angles(0, ang, 0) * BrainrotThumb.DEFAULT_DIR
				ccam.CFrame = CFrame.lookAt(centre + dir * dist, centre)
			end
		else
			local sw = new("Frame", {
				Size = UDim2.fromScale(1, 1), BackgroundColor3 = accent, BackgroundTransparency = 0.5, ZIndex = 14,
			}, card)
			UITheme.corner(sw, 12)
			spinFn = petFn
		end

		task.delay(B10_DELAY, function()
			if myGen ~= revealGen then return end
			bannerPhase()
		end)
	end

	---------------------------------------------------- B10  rarity banner
	bannerPhase = function()
		-- spec cue sheet: pet vocal, THEN the banner, 4 frames apart
		SoundKit.play("catchCommon", nil, { volume = 0.30, speed = 1.25 })
		task.delay(4 / 60, function()
			if myGen == revealGen then SoundKit.play("catchBigHit", nil, { volume = 0.42 }) end
		end)

		-- ABOVE the pet, at 13% from the top, parented to root rather than to the
		-- stage. B10 says the banner "slams in over the pet", but Responsive
		-- Behavior settles what that means: "the banner sits at 13% from the top"
		-- and "keep the pet fully inside the middle 60% of the screen height so the
		-- banner never overlaps it". Over = above, not on top of. Parenting it to
		-- root also keeps it clear of the stage's pop scale.
		-- Tokens: rgba(16,20,12,.82), 2px tier border, 12px radius.
		local banner = new("Frame", {
			Name = "RarityBanner", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.13),
			Size = UDim2.fromOffset(VP_SIZE + 36, 96),
			BackgroundColor3 = Color3.fromRGB(16, 20, 12), BackgroundTransparency = 0.18,
			BorderSizePixel = 0, ZIndex = 16,
		}, root)
		UITheme.corner(banner, 12)
		local bStroke = Instance.new("UIStroke")
		bStroke.Color = accent
		bStroke.Thickness = 2
		bStroke.Parent = banner
		table.insert(fades, { banner, "BackgroundTransparency" })
		table.insert(fades, { bStroke, "Transparency" })

		local headline = new("TextLabel", {
			Name = "Headline", Position = UDim2.fromOffset(0, 4),
			Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1,
			Font = FONT, TextSize = 30, TextColor3 = accent,
			-- Spec's banner-copy recommendation: "Tone B as the default with Tone A
			-- unlocked for Epic and Legendary" -- i.e. the top tiers shout. Mapped onto
			-- this game's ladder that is Legendary and up.
			Text = string.upper(tostring(result.Rarity or "?")) .. (T.loud and "!" or ""),
			ZIndex = 17,
		}, banner)
		local hInk = UITheme.inkText(headline, 3.0)

		local petLine = new("TextLabel", {
			Name = "PetLine", Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 32),
			BackgroundTransparency = 1, Font = FONT, TextSize = 24, TextColor3 = CF.onDark,
			TextTruncate = Enum.TextTruncate.AtEnd, Text = result.Name, ZIndex = 17,
		}, banner)
		local pInk = UITheme.inkText(petLine, 2.8)

		local subLine = new("TextLabel", {
			Name = "SubLine", Position = UDim2.fromOffset(0, 68), Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1, Font = FONT, TextSize = 17,
			TextColor3 = Color3.fromRGB(182, 194, 166), -- spec sub-line token #b6c2a6
			Text = chanceText or "added to your brainrots", ZIndex = 17,
		}, banner)
		local sInk = UITheme.inkText(subLine, 2.0)

		for _, pair in ipairs({ { headline, hInk }, { petLine, pInk }, { subLine, sInk } }) do
			table.insert(fades, { pair[1], "TextTransparency" })
			table.insert(fades, { pair[2], "Transparency" })
		end

		-- slam: 2.4 -> 0.93 -> 1.00, settling at a -2 degree tilt
		local bScale = new("UIScale", { Scale = B10_S0 }, banner)
		local bStart = elapsed
		local prevSpin = spinFn
		spinFn = function(t)
			if prevSpin then prevSpin(t) end
			local p = math.min((t - bStart) / B10_TIME, 1)
			bScale.Scale = overshoot(p, B10_S0, B10_UNDER)
			banner.Rotation = B10_REST_TILT * p
		end

		-- input unlocks on the last frame of B10, then the sequence auto-dismisses
		task.delay(B10_TIME, function()
			if myGen ~= revealGen then return end
			canSkip = true
			task.delay(B10_DISMISS, function()
				if myGen ~= revealGen then return end
				skip()
			end)
		end)
	end
end

---------------------------------------------------------------- multi-open reveal
-- x3/x10 batches skip the tap-to-crack theatre: the handoff shows the results
-- as a grid of rarity-framed cards popping in on a 90ms stagger, with Skip.
-- Shares revealGen/revealSkip with playReveal so the two can never stack, and
-- restores frame.Visible through the same skip() contract.
local MULTI_CARD_W, MULTI_CARD_H = 150, 196
local MULTI_GAP = 10
local MULTI_STAGGER = 0.09
local MULTI_HOLD = 5.0

local function playMultiReveal(result)
	if revealSkip then revealSkip() end
	revealGen += 1
	local myGen = revealGen
	local results = result.Results

	local root = new("Frame", {
		Name = "MultiReveal", Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, ZIndex = 1,
	}, ensureRevealGui())

	local dim = new("Frame", {
		Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1,
	}, root)
	TweenService:Create(dim, TweenInfo.new(FADE_TIME), { BackgroundTransparency = 1 - DIM_TARGET }):Play()

	local clickCatcher = new("TextButton", {
		Name = "ClickCatcher", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 2,
	}, root)

	frame.Visible = false

	-- every popped element carries its own UIScale; skip() shrinks them all so
	-- the dismissal reads as one motion instead of a hard cut
	local pops = {}
	local dead = false
	local canSkip = false
	local function skip()
		if dead then return end
		dead = true
		revealGen += 1
		if revealSkip == skip then revealSkip = nil end
		frame.Visible = true
		TweenService:Create(dim, TweenInfo.new(FADE_TIME), { BackgroundTransparency = 1 }):Play()
		for _, p in ipairs(pops) do
			TweenService:Create(p, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 }):Play()
		end
		task.delay(FADE_TIME, function()
			if root then root:Destroy(); root = nil end
		end)
	end
	revealSkip = skip
	clickCatcher.Activated:Connect(function()
		if canSkip then skip() end
	end)

	SoundKit.play("eggSplit", nil, { volume = 0.5 })

	local n = #results
	local cols = math.min(n, 5)
	local rowsN = math.ceil(n / 5)
	local gridW = cols * MULTI_CARD_W + (cols - 1) * MULTI_GAP
	local gridH = rowsN * MULTI_CARD_H + (rowsN - 1) * MULTI_GAP

	local titleL = new("TextLabel", {
		Name = "Title", AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.5, -gridH / 2 - 16),
		Size = UDim2.fromOffset(520, 40), BackgroundTransparency = 1,
		Font = FONT, TextSize = 28, TextColor3 = CF.onDark,
		Text = n .. " EGGS OPENED!", ZIndex = 3,
	}, root)
	UITheme.inkText(titleL, 2.8)
	local titleScale = new("UIScale", { Scale = 0 }, titleL)
	pops[#pops + 1] = titleScale
	TweenService:Create(titleScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local grid = new("Frame", {
		Name = "Cards", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(gridW, gridH),
		BackgroundTransparency = 1, ZIndex = 3,
	}, root)

	for i, res in ipairs(results) do
		local col = (i - 1) % 5
		local rowI = math.floor((i - 1) / 5)
		local tier = tierByName[res.Rarity]
		local accent = (tier and tier.Color) or CF.ink

		local slot = new("Frame", {
			Name = "Result" .. i,
			Position = UDim2.fromOffset(col * (MULTI_CARD_W + MULTI_GAP), rowI * (MULTI_CARD_H + MULTI_GAP)),
			Size = UDim2.fromOffset(MULTI_CARD_W, MULTI_CARD_H),
			BackgroundTransparency = 1, ZIndex = 4,
		}, grid)
		local pop = new("UIScale", { Scale = 0 }, slot)

		local card, outer = UITheme.accentCard(slot, accent, 12)
		outer.Name = "ResultCard"
		outer.Size = UDim2.new(1, 0, 1, -40)
		outer.Position = UDim2.fromOffset(0, 0)
		outer.ZIndex = 4
		card.ZIndex = 5
		RarityFX.attach(outer, card, res.Rarity, accent, 0)

		local vp = addPetViewport(card, res.Name, res.PetId, 6)
		if not vp then
			local sw = new("Frame", {
				Size = UDim2.new(1, -12, 1, -12), Position = UDim2.fromOffset(6, 6),
				BackgroundColor3 = accent, BackgroundTransparency = 0.5, ZIndex = 6,
			}, card)
			UITheme.corner(sw, 10)
		end

		local nameL = new("TextLabel", {
			Name = "Name", Position = UDim2.new(0, -10, 1, -38), Size = UDim2.new(1, 20, 0, 20),
			BackgroundTransparency = 1, Font = FONT, TextSize = 16, TextColor3 = CF.onDark,
			TextTruncate = Enum.TextTruncate.AtEnd, Text = res.Name, ZIndex = 6,
		}, slot)
		UITheme.inkText(nameL, 2.2)
		local tierL = new("TextLabel", {
			Name = "Tier", Position = UDim2.new(0, -10, 1, -18), Size = UDim2.new(1, 20, 0, 16),
			BackgroundTransparency = 1, Font = FONT, TextSize = 13, TextColor3 = accent,
			Text = string.upper(tostring(res.Rarity or "?")), ZIndex = 6,
		}, slot)
		UITheme.inkText(tierL, 2)

		pops[#pops + 1] = pop
		task.delay(MULTI_STAGGER * (i - 1), function()
			if myGen ~= revealGen then return end
			SoundKit.play("catchSparkle", nil, { volume = 0.18, speed = 1 + 0.03 * i })
			TweenService:Create(pop, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)
	end

	-- Skip: kitButton's hard shadow lands in this holder rather than in root
	-- (the codebase-wide slot-wrapper pattern), and the holder carries the pop.
	local skipHolder = new("Frame", {
		Name = "SkipHolder", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, gridH / 2 + 22),
		Size = UDim2.fromOffset(132, 52), BackgroundTransparency = 1, ZIndex = 7,
	}, root)
	pops[#pops + 1] = new("UIScale", { Scale = 0 }, skipHolder)
	local skipBtn = kitButton(skipHolder, "Skip", "red", UDim2.fromOffset(132, 52), 8)
	skipBtn.Name = "SkipButton"
	skipBtn.Activated:Connect(skip)
	task.delay(MULTI_STAGGER * n + 0.1, function()
		if myGen ~= revealGen then return end
		TweenService:Create(pops[#pops], TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)

	task.delay(SKIP_GRACE + MULTI_STAGGER * n, function()
		if myGen ~= revealGen then return end
		canSkip = true
	end)
	task.delay(MULTI_HOLD + MULTI_STAGGER * n, function()
		if myGen ~= revealGen then return end
		skip()
	end)
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
		darrelLabel.Text = comma(currentDarrels)
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
local openToken = 0
local function setOpen(open)
	openToken += 1
	local token = openToken
	if open then
		frame.Visible = true
		scrim.Visible = true
		openPop.Scale = 0.92
		TweenService:Create(openPop, T.tween.panelOpen, { Scale = 1 }):Play()
		TweenService:Create(scrim, T.tween.scrim, { BackgroundTransparency = SCRIM_ALPHA }):Play()
		SoundKit.play("panelOpen", nil, { volume = 0.15 })
		pullDarrelState()
		list.CanvasPosition = Vector2.new(0, 0)
	else
		TweenService:Create(openPop, T.tween.panelClose, { Scale = 0.95 }):Play()
		TweenService:Create(scrim, T.tween.scrim, { BackgroundTransparency = 1 }):Play()
		-- hide after the close tween lands; the token guards a reopen racing it
		task.delay(0.12, function()
			if token ~= openToken then return end
			frame.Visible = false
			scrim.Visible = false
			openPop.Scale = 1
		end)
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
	-- the reveal hides behind its own overlay; both reveals restore
	-- frame.Visible themselves when they end or are skipped.
	setOpen(true)
	if typeof(result.Results) == "table" and #result.Results > 1 then
		playMultiReveal(result)
	else
		playReveal(result)
	end
end)

---------------------------------------------------------------- stall prompt
-- Gino has a stall in each world; accept the prompt from any of them.
local eggPrompts, eggParts = {}, {}
local function bindEggStall(stallName)
	task.spawn(function()
		local stall = Workspace:WaitForChild("GameWorld"):WaitForChild(stallName, 30)
		if not stall then return end
		local part = stall:WaitForChild("PromptPart", 30)
		if not part then return end
		local p = part:WaitForChild("EggPrompt", 30)
		if not p then return end
		eggPrompts[p] = true
		table.insert(eggParts, part)
	end)
end
bindEggStall("EggStall")
bindEggStall("TundraEggStall")
ProximityPromptService.PromptTriggered:Connect(function(triggeredPrompt, who)
	if who ~= player or not eggPrompts[triggeredPrompt] then return end
	setOpen(not frame.Visible)
end)

-- the shared slot-spin driver (see addEggViewport); connected once, for life
RunService.RenderStepped:Connect(function()
	if not frame.Visible or #eggSpinners == 0 then return end
	local t = os.clock()
	local ang = (t / SLOT_SPIN_TIME) * (2 * math.pi)
	for _, s in ipairs(eggSpinners) do
		local a = ang + s.phase
		local dir = CFrame.Angles(0, a, 0) * BrainrotThumb.DEFAULT_DIR
		local bob = math.sin(t * 1.7 + s.phase) * SLOT_BOB * s.dist
		s.cam.CFrame = CFrame.lookAt(s.centre + dir * s.dist + Vector3.new(0, bob, 0), s.centre)
	end
end)

-- walk away -> close, same convention as the other stall panels (MerchantClient)
RunService.Heartbeat:Connect(function()
	if not frame.Visible then return end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local nearestEgg = math.huge
	for _, part in ipairs(eggParts) do
		nearestEgg = math.min(nearestEgg, (hrp and (hrp.Position - part.Position).Magnitude) or math.huge)
	end
	if hrp and #eggParts > 0 and nearestEgg > 24 then
		setOpen(false)
	end
end)
