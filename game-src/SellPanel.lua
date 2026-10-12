--!strict
-- SellPanel: Marco's counter. A GameHUDPanels consumer module.
-- Contract: { Id = "sell", Build = function(ctx) -> Frame }. Build runs ONCE on
-- first open; GameHUDClient parents the frame and owns Visible. Never set
-- Parent here and never animate open/close here.
--
-- ============================================================================
-- REBUILT 2026-08-26 TO THE "Sell Shop" DESIGN HANDOFF
-- (design_handoff_sell_shop/README.md + Sell Shop.dc.html, Claude Design).
--
-- The handoff replaces the 2026-08-20 shape (quick-sell bar -> species grid ->
-- per-species drill-down tab) with ONE flat screen:
--
--   row 1  header tabs (BRAINROTS / PETS) + the live cash balance
--   row 2  RARITY filter chips
--   row 3  MUTATION filter chips (brainrots only) + search
--   row 4  meta line ("N stacks - M items shown" / the stepper hint)
--   row 5  the STACK GRID (left) + the ACTION RAIL (right)
--
-- A STACK is one tile per name + mutation + size, so a Golden Massive Antonio
-- is its own tile with its own price -- the drill-down existed only because the
-- old grid was one tile per SPECIES and could not price a mutated copy. Tapping
-- a tile selects 1; the tile's own [-] n/total [+] [MAX] stepper sets the
-- amount. That is the whole drill-down, on the tile, with no view swap.
--
-- WHAT CAME FROM THE HANDOFF AND WHAT CAME FROM THIS GAME
--   layout, tile anatomy, stepper, selection card, quick-sell rail, confirm
--   dialog -- from the handoff.
--   rarities (Common..God, not the handoff's four), prices, mutations, sizes,
--   art, chrome and colour -- from this game. The handoff's kit is the OLD grey
--   /red web mirror; the live game is the PS99 white restyle (SpecTheme), and
--   gold is reserved for real-money surfaces game-wide, so the handoff's gold
--   accents are the house green (SpecTheme.Action.Go) here.
--
-- DELIBERATELY NOT BUILT (both already exist elsewhere -- a second one would be
-- a duplicate, not a feature):
--   * the sale TOAST. StarterPlayerScripts.ToastClient is "the ONLY renderer for
--     {Success, Message} server replies" and is already wired to SellResult, so
--     every sale fired from here already prints the SERVER's own total.
--   * the gem balance pill. Selling pays cash only, and PlayerDataManager
--     .Snapshot carries no gem field (gems live behind remotes.EmeraldState);
--     the HUD's own emerald counter is on screen the whole time. One pill, for
--     the one currency this screen can move.
--   * the EGGS and POTIONS tabs. There are no potions in this game, and eggs are
--     bought and hatched, never sold. Two tabs, both real.
--
-- Every price shown here comes from SellValue (BaseRate / OfBrainrot / OfPet)
-- plus PetConfig.StackedMult's "Sell Value" pet ability -- never recomputed
-- locally. A sell row advertising one price while the server pays another is
-- the exact bug this panel's whole history exists to remove, so the two
-- multiplier SHAPES are mirrored exactly:
--   brainrots  floor(sum(each) * sellMult)      -- SellHandler applies it ONCE
--   pets       sum(floor(each * sellMult))      -- PetHandler applies it PER PET
-- ============================================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local PanelChrome = require(ReplicatedStorage.Modules.UIKit.PanelChrome)
local SpecTheme = require(ReplicatedStorage.Modules.UIKit.SpecTheme)
local SellValue = require(ReplicatedStorage.Modules.SellValue)
local PetConfig = require(ReplicatedStorage.Modules.PetConfig)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local BrainrotThumb = require(ReplicatedStorage.Modules.BrainrotThumb)
local Sizes = require(ReplicatedStorage.Modules.SizeConfig)
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local WorldProgression = require(ReplicatedStorage.Modules.WorldProgression)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local SellPanel = { Id = "sell" }

------------------------------------------------------------------ config knobs
-- The handoff exposes three; these are their Luau equivalents.
--
-- CONFIRM_FROM_RARITY: any sale whose scope includes a brainrot/pet at or above
-- this tier opens the "HOLD ON!" dialog first. The handoff's default is epic+,
-- but its ladder has four tiers and ours has EIGHT -- epic+ here would mean five
-- of the eight and a confirm on almost every sale. Legendary+ is the same
-- *position* on our ladder. Set to nil to switch confirmations off entirely.
local CONFIRM_FROM_RARITY: string? = "Legendary"
-- ...and so does any mutated or oversized copy, whatever its tier: those are the
-- ones worth 2x-760x a plain copy (MutationConfig / SizeConfig), which is what
-- the confirmation is actually protecting.
local CONFIRM_ON_SPECIAL = true
-- The handoff's "quick-sell rail can be hidden" knob.
local SHOW_QUICK_SELL = true

-- Server payload ceilings, mirrored so a client list can never be silently
-- rejected whole: SellHandler.MAX_SELL_UIDS is 1000, PetHandler
-- .MAX_SELL_MANY_UIDS is 200, and BOTH reject the entire payload -- with no
-- reply at all in the pet case -- the moment it is one element too long.
local MAX_BRAINROT_UIDS = 1000
local MAX_PET_UIDS = 200

------------------------------------------------------------------ rarity ladder
-- This game's ladder, not the handoff's. Order is weakest -> strongest; the
-- grid sorts by it (rarest first, matching PetConfig.RARITY_ORDER and the Bag).
local RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret", "God" }
local RARITY_KEY: { [string]: string } = {
	Common = "COM", Uncommon = "UNC", Rare = "RARE", Epic = "EPIC",
	Legendary = "LEG", Mythic = "MYTH", Secret = "SEC", God = "GOD",
}
local RARITY_RANK: { [string]: number } = {}
for i, r in ipairs(RARITY_ORDER) do
	RARITY_RANK[r] = i
end
local CONFIRM_RANK = (CONFIRM_FROM_RARITY and RARITY_RANK[CONFIRM_FROM_RARITY]) or math.huge

-- EVERY WORLD, built exactly the way SellValue builds its rate table and
-- SellHandler builds its own rarity table -- BrainrotConfig alone is World 1
-- only, which is how the tundra/gardens exclusives went missing from the sell
-- list in the first place (2026-08-20 bug 2). Valley first so a shared name
-- keeps its World 1 rarity.
local rarityByName: { [string]: string } = {}
for _, entry in ipairs(BrainrotConfig) do
	rarityByName[entry.Name] = entry.Rarity
end
for _, worldName in ipairs(WorldProgression.List()) do
	local world = WorldProgression.Resolve(worldName)
	for _, e in ipairs((world and world.Pool) or {}) do
		if rarityByName[e.Name] == nil then
			rarityByName[e.Name] = e.Rarity
		end
	end
end

local function rarityRamp(word: string?): { Color3 }
	local key = word and RARITY_KEY[word]
	return (key and SpecTheme.Rarity[key]) or SpecTheme.Rarity.COM
end

-- The 12 colour/finish mutations, weakest -> strongest (MutationConfig.Order).
local function mutationColour(name: string?): Color3
	return (name and Mutations.Color(name)) or SpecTheme.Action.Premium[1]
end

------------------------------------------------------------- server-confirmed data
-- Same "module-top-level capture, not inside Build" wiring every other
-- GameHUDPanels module carries: this module is require()d once, early, at
-- GameHUDClient's own script top level, while Build(ctx) only runs lazily on
-- first open -- so the server's join-time DataUpdated push (or the one-shot
-- GetInitialData pull below) can land well before Build ever runs.
local state = { Brainrots = {}, Pets = {}, PetSlots = {}, Cash = 0 }
local refresh: (() -> ())? = nil -- forward declaration; assigned in Build
local paintCash: (() -> ())? = nil
-- The debounced + visibility-gated wrapper around refresh() (Finding 1,
-- 2026-08-20), same shape as BackpackPanel's scheduleRender. applySnapshot
-- calls THIS, never refresh() directly.
local scheduleRender: (() -> ())? = nil

local function applySnapshot(snap)
	if typeof(snap) ~= "table" then
		return
	end
	if typeof(snap.Brainrots) == "table" then
		state.Brainrots = snap.Brainrots
	end
	if typeof(snap.Pets) == "table" then
		state.Pets = snap.Pets
	end
	-- PlayerDataManager.Snapshot DOES ship data.PetSlots (equipped Uids);
	-- BackpackPanel and LuckHUDClient already read this exact field off this
	-- exact snapshot shape. Without it an equipped pet is indistinguishable
	-- from a sellable one.
	if typeof(snap.PetSlots) == "table" then
		state.PetSlots = snap.PetSlots
	end
	if typeof(snap.Cash) == "number" then
		state.Cash = snap.Cash
		if paintCash then
			paintCash()
		end
	end
	if scheduleRender then
		scheduleRender()
	end
end

remotes.DataUpdated.OnClientEvent:Connect(applySnapshot)
-- CashTick is the fast path the HUD counter rides; a sale's cash lands here
-- well before the next full DataUpdated, which is what makes the balance pill
-- move the instant the sale clears.
local cashTick = remotes:FindFirstChild("CashTick")
if cashTick and cashTick:IsA("RemoteEvent") then
	cashTick.OnClientEvent:Connect(function(newCash)
		if typeof(newCash) == "number" then
			state.Cash = newCash
			if paintCash then
				paintCash()
			end
		end
	end)
end
task.spawn(function()
	local ok, snap = pcall(function()
		return remotes.GetInitialData:InvokeServer()
	end)
	if ok then
		applySnapshot(snap)
	end
end)

function SellPanel.Build(ctx)
	local shell = PanelChrome.shell({
		name = "SellPanel",
		title = "SELL SHOP",
		key = "shop", -- no dedicated SpecTheme.Plate/ShellFor "sell" entry; "shop" is the closest existing colourway (1180x830)
		scroll = false,
		listLayout = false, -- two full-bleed tab bodies share the well, same idiom ProgressPanel uses
	})
	shell.close.Activated:Connect(function()
		if ctx.closePanel then
			ctx.closePanel()
		end
	end)
	local z = shell.z

	----------------------------------------------------------------- geometry
	-- Spec px on the 1920x1080 sheet, the way every panel in this kit is
	-- authored (SpecTheme's header). The shell is 1180x830, so after the 18px
	-- shell padding, the 112+16 header band and the 22px body padding, the body
	-- gives 1100 x 622 of usable ground. The handoff's own 884 x ~590 content
	-- block scales onto that by ~1.24, which is where these numbers come from.
	local FILTER_H = 52
	local ROW_GAP = 10
	local META_H = 24
	local ROW_A_Y = 0
	local ROW_B_Y = ROW_A_Y + FILTER_H + ROW_GAP        -- 62
	local META_Y = ROW_B_Y + FILTER_H + ROW_GAP         -- 124
	local CONTENT_Y = META_Y + META_H + 6               -- 154
	local RAIL_W = 320
	local COL_GAP = 16
	local TILE_W, TILE_H = 140, 176
	local TILE_GAP = 12
	local ART_H = 96
	local LABEL_W = 104 -- the "RARITY" / "MUTATION" gutter

	----------------------------------------------------------------- art mat
	-- THE ART MAT (2026-08-25). Owner, looking at the pets grid: "there is just
	-- so much white it looks badly made." SpecTheme puts the card at #FFFFFF->
	-- #F4F7FB (lum 1.000->0.967) on a well of #F5F8FC (0.971) -- the card and
	-- the ground it sits on are THE SAME VALUE -- and the pet key light travels
	-- within ~10 degrees of the camera axis, so 14 of 30 pets clip to white.
	-- One neutral slate behind every tile, brainrot and pet alike.
	--
	-- NEVER key this to rarity. A rarity-coloured plate behind the art is
	-- exactly the placeholder the owner rejected; the RARITY FRAME (the tile's
	-- own coloured edge, below) is where rarity belongs.
	local ART_MAT = Color3.fromRGB(150, 166, 192)
	local function addArtMat(artHolder: Frame)
		local mat = Instance.new("Frame")
		mat.Name = "ArtMat"
		mat.Size = UDim2.fromScale(1, 1)
		mat.BackgroundColor3 = ART_MAT
		mat.BorderSizePixel = 0
		mat.ZIndex = artHolder.ZIndex -- the viewport goes in at +1, so this sits behind it
		mat.Parent = artHolder
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = mat
		return mat
	end

	-- The house missing-art mark, drawn ON the mat: light '?' with a dark halo,
	-- the same idiom BackpackPanel.buildSwatch uses. A blank tinted rectangle is
	-- indistinguishable from "the art failed to load".
	local function addMissingArtMark(artHolder: Frame)
		PanelChrome.shout({
			name = "MissingArt",
			text = "?",
			size = 46,
			color = Color3.fromRGB(238, 243, 250),
			strokeColor = Color3.fromRGB(74, 88, 110),
			zIndex = artHolder.ZIndex + 2,
			parent = artHolder,
		})
	end

	-- Pet relighting. The pet models were authored for a key light aimed away
	-- from the camera, so an un-relit pet renders as a dark brown blob. These
	-- are the Bag's exact numbers.
	local PET_ART_AMBIENT = Color3.fromRGB(205, 210, 220)
	local PET_ART_LIGHT = Color3.fromRGB(255, 248, 232)
	local PET_ART_DIR = Vector3.new(-0.8, -0.65, 1)

	----------------------------------------------------------------- tab bodies
	-- Full-bleed siblings inside shell.body, toggled by Visible -- the exact
	-- pattern ProgressPanel uses for its embedded frames. Both tabs share ONE
	-- set of controls (filters, grid, rail); `tab` below is the only state that
	-- separates them, so there is no second grid to keep in step.
	local content = Instance.new("Frame")
	content.Name = "SellContent"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = z + 2
	content.Parent = shell.body

	----------------------------------------------------------------- view state
	local tab: string = "brainrots"          -- "brainrots" | "pets"
	local rarityFilter: string = "all"       -- "all" | a RARITY_ORDER word
	local mutFilter: string = "all"          -- "all" | "none" | a mutation name
	local search: string = ""
	local sel: { [string]: number } = {}     -- stack key -> units selected (1..count)

	-- Rebuilt every refresh(); read by the rail, the quick rows and the confirm
	-- dialog, so they can never disagree with what the grid is showing.
	local stacks: { any } = {}               -- the FILTERED, on-screen stacks
	local allStacks: { any } = {}            -- every sellable stack, filters ignored
	local heldBack = 0                       -- placed / locked / equipped / unpriceable
	local tileApi: { [string]: any } = {}    -- stack key -> { update = fn }

	------------------------------------------------------------- the sell multiplier
	-- The "Sell Value" pet ability (Acornel, Mossback, Cheek Hoard...). Both
	-- server paths apply it and neither tells the client, so without this the
	-- panel would quietly advertise LESS than it pays. Read from the same
	-- ReplicatedStorage function the server calls, off the same snapshot fields.
	local function sellMult(): number
		local ok, mult = pcall(PetConfig.StackedMult, state.Pets, state.PetSlots, "SellBonus")
		if not ok or type(mult) ~= "number" or mult ~= mult or mult < 1 then
			return 1
		end
		return mult
	end

	-- SellHandler applies the multiplier ONCE to the summed total; PetHandler's
	-- sellOne applies it PER PET and floors each. Mirrored exactly.
	local function payoutOfEntries(entries: { any }): number
		-- entries: { { kind, unit, units } }
		local mult = sellMult()
		local coins, brainrotRaw = 0, 0
		for _, e in ipairs(entries) do
			if e.kind == "pet" then
				coins += math.floor(e.unit * mult) * e.units
			else
				brainrotRaw += e.unit * e.units
			end
		end
		if brainrotRaw > 0 then
			coins += math.floor(brainrotRaw * mult)
		end
		return coins
	end

	------------------------------------------------------------------ balance pill
	-- 142/240 are the widths that make the WORST REAL CASE fit without scrolling:
	-- the owner's save carries 7 of the 8 rarities and 6 mutations, which measure
	-- 592px and 515px of chips -- against strips of 597 and 525 at these reserves.
	-- (150 left rarity 3px short, which cut the edge off the SECRET chip.)
	local balancePill = PanelChrome.plate({
		name = "CashPill",
		size = UDim2.fromOffset(142, FILTER_H),
		position = UDim2.new(1, 0, 0, ROW_A_Y),
		anchor = Vector2.new(1, 0),
		colors = { Color3.new(1, 1, 1), SpecTheme.Surface.RowBottom },
		radius = 26,
		outline = 3,
		strokeColor = SpecTheme.OutlineSoft,
		zIndex = z + 3,
		parent = content,
		gloss = false,
	})
	local cashLabel = PanelChrome.read({
		name = "CashValue",
		text = "$0",
		size = 24,
		color = SpecTheme.Surface.ReadInk,
		align = Enum.TextXAlignment.Center,
		frameSize = UDim2.new(1, -24, 1, 0),
		position = UDim2.fromOffset(12, 0),
		zIndex = z + 4,
		parent = balancePill,
	})
	paintCash = function()
		cashLabel.Text = NumberFormat.Cash(state.Cash or 0)
	end
	paintCash()

	------------------------------------------------------------------- filter rows
	local function gutterLabel(text: string, y: number): TextLabel
		return PanelChrome.read({
			name = text .. "Gutter",
			text = text,
			size = 17,
			color = SpecTheme.Surface.ReadSub,
			align = Enum.TextXAlignment.Left,
			frameSize = UDim2.fromOffset(LABEL_W, FILTER_H),
			position = UDim2.fromOffset(0, y),
			zIndex = z + 3,
			parent = content,
		})
	end
	gutterLabel("RARITY", ROW_A_Y)
	local mutGutter = gutterLabel("MUTATION", ROW_B_Y)

	-- MEASURED, NOT GUESSED (2026-08-26 playtest): on a real 404-brainrot save the
	-- rarity row wanted 680px of chips in a 546px strip and the mutation row 591 in
	-- 482, so a plain clipping Frame ate MYTHIC and ELECTRIC outright -- the two
	-- filters a stocked player most wants. Eight rarities and twelve mutations can
	-- never be made to fit one fixed row, so the strip SCROLLS sideways; the chips
	-- below were trimmed as well so an ordinary inventory needs no scrolling at all.
	local function chipStrip(name: string, y: number, rightReserve: number): ScrollingFrame
		local strip = Instance.new("ScrollingFrame")
		strip.Name = name
		strip.BackgroundTransparency = 1
		strip.BorderSizePixel = 0
		strip.Position = UDim2.fromOffset(LABEL_W, y)
		strip.Size = UDim2.new(1, -(LABEL_W + rightReserve), 0, FILTER_H)
		strip.ClipsDescendants = true
		strip.ScrollingDirection = Enum.ScrollingDirection.X
		strip.CanvasSize = UDim2.new()
		strip.AutomaticCanvasSize = Enum.AutomaticSize.X
		strip.ElasticBehavior = Enum.ElasticBehavior.Never
		strip.ScrollBarThickness = 4
		strip.ScrollBarImageColor3 = SpecTheme.OutlineSoft
		strip.ZIndex = z + 3
		strip.Parent = content
		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Horizontal
		list.Padding = UDim.new(0, 8)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		list.Parent = strip
		return strip
	end
	-- Row A gives the balance pill its width back; row B gives it to the search box.
	local SEARCH_W = 240
	local rarityStrip = chipStrip("RarityChips", ROW_A_Y, 142 + 16)
	local mutStrip = chipStrip("MutationChips", ROW_B_Y, SEARCH_W + 16)

	-- A filter chip: pill + optional colour dot. Width is MEASURED rather than
	-- guessed, because the labels run from "All" to "Legendary" and a fixed
	-- width would either clip the long ones or leave the short ones swimming.
	local CHIP_H = 38
	local CHIP_TEXT = 16
	local function chipWidth(text: string, hasDot: boolean): number
		local bounds = TextService:GetTextSize(text, CHIP_TEXT, SpecTheme.Font.Shout, Vector2.new(1000, CHIP_H))
		return math.ceil(bounds.X) + 22 + (hasDot and 19 or 0)
	end

	local function buildChip(parent: GuiObject, order: number, text: string, dot: Color3?, active: boolean, onPick: () -> ())
		local hasDot = dot ~= nil
		local b = PanelChrome.pill({
			name = "Chip_" .. text,
			text = "",
			colors = if active then SpecTheme.Action.Go else SpecTheme.Action.Neutral,
			size = UDim2.fromOffset(chipWidth(text, hasDot), CHIP_H),
			radius = 20,
			zIndex = z + 4,
			parent = parent,
			layoutOrder = order,
		})
		-- pill's own Label is empty and full-bleed; the real label is placed
		-- beside the dot instead, so the two never overlap.
		local existing = b:FindFirstChild("Label")
		if existing then
			existing:Destroy()
		end
		local textX = 11
		if dot then
			local swatch = Instance.new("Frame")
			swatch.Name = "Dot"
			swatch.Size = UDim2.fromOffset(13, 13)
			swatch.Position = UDim2.new(0, 10, 0.5, 0)
			swatch.AnchorPoint = Vector2.new(0, 0.5)
			swatch.BackgroundColor3 = dot
			swatch.BorderSizePixel = 0
			swatch.ZIndex = b.ZIndex + 2
			swatch.Parent = b
			local sc = Instance.new("UICorner")
			sc.CornerRadius = UDim.new(1, 0)
			sc.Parent = swatch
			local ss = Instance.new("UIStroke")
			ss.Thickness = 2
			ss.Color = SpecTheme.Outline
			ss.Parent = swatch
			textX = 28
		end
		PanelChrome.shout({
			name = "ChipLabel",
			text = text,
			size = CHIP_TEXT,
			color = if active then Color3.new(1, 1, 1) else SpecTheme.Surface.ReadInk,
			strokeColor = if active then SpecTheme.Outline else Color3.new(1, 1, 1),
			align = Enum.TextXAlignment.Left,
			frameSize = UDim2.new(1, -(textX + 8), 1, 0),
			position = UDim2.fromOffset(textX, 0),
			zIndex = b.ZIndex + 2,
			parent = b,
		})
		b.Activated:Connect(onPick)
		return b
	end

	------------------------------------------------------------------- search box
	local searchHost = PanelChrome.plate({
		name = "SearchBox",
		size = UDim2.fromOffset(SEARCH_W, FILTER_H),
		position = UDim2.new(1, 0, 0, ROW_B_Y),
		anchor = Vector2.new(1, 0),
		colors = { Color3.new(1, 1, 1), SpecTheme.Surface.RowBottom },
		radius = 26,
		outline = 2,
		strokeColor = SpecTheme.OutlineSoft,
		zIndex = z + 3,
		parent = content,
		gloss = false,
	})
	local searchBox = Instance.new("TextBox")
	searchBox.Name = "SearchInput"
	searchBox.BackgroundTransparency = 1
	searchBox.Position = UDim2.fromOffset(20, 0)
	searchBox.Size = UDim2.new(1, -40, 1, 0)
	searchBox.Text = ""
	searchBox.PlaceholderText = "SEARCH..."
	searchBox.PlaceholderColor3 = SpecTheme.Surface.ReadSub
	searchBox.TextColor3 = SpecTheme.Surface.ReadInk
	searchBox.Font = SpecTheme.Font.Read
	searchBox.TextSize = 18
	searchBox.ClearTextOnFocus = false
	searchBox.TextXAlignment = Enum.TextXAlignment.Left
	searchBox.TextTruncate = Enum.TextTruncate.AtEnd
	searchBox.ZIndex = z + 4
	searchBox:SetAttribute("NoPolish", true) -- UIPolish would otherwise force this white-on-white
	searchBox.Parent = searchHost

	------------------------------------------------------------------- meta line
	-- Both halves live inside the GRID's own width, so the right-hand hint sits
	-- over the grid rather than over the rail.
	local metaRow = Instance.new("Frame")
	metaRow.Name = "MetaRow"
	metaRow.BackgroundTransparency = 1
	metaRow.Position = UDim2.fromOffset(4, META_Y)
	metaRow.Size = UDim2.new(1, -(RAIL_W + COL_GAP + 8), 0, META_H)
	metaRow.ZIndex = z + 3
	metaRow.Parent = content
	local metaLeft = PanelChrome.read({
		name = "MetaCount",
		text = "",
		size = 17,
		color = SpecTheme.Surface.ReadSub,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(0.62, 0, 1, 0),
		zIndex = z + 4,
		parent = metaRow,
	})
	PanelChrome.read({
		name = "MetaHint",
		text = "Tap to select \u{2022} \u{2212} + MAX to adjust",
		size = 17,
		color = SpecTheme.Surface.ReadSub,
		align = Enum.TextXAlignment.Right,
		frameSize = UDim2.new(0.38, 0, 1, 0),
		position = UDim2.fromScale(0.62, 0),
		zIndex = z + 4,
		parent = metaRow,
	})

	--------------------------------------------------------------------- the grid
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "StackGrid"
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Position = UDim2.fromOffset(0, CONTENT_Y)
	grid.Size = UDim2.new(1, -(RAIL_W + COL_GAP), 1, -CONTENT_Y)
	grid.ZIndex = z + 2
	grid.ScrollBarThickness = 5
	grid.ScrollBarImageColor3 = SpecTheme.OutlineSoft
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.ElasticBehavior = Enum.ElasticBehavior.Never
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.Parent = content

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(TILE_W, TILE_H)
	gridLayout.CellPadding = UDim2.fromOffset(TILE_GAP, TILE_GAP)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	local emptyState = Instance.new("Frame")
	emptyState.Name = "EmptyState"
	emptyState.BackgroundTransparency = 1
	emptyState.Position = UDim2.fromOffset(0, CONTENT_Y)
	emptyState.Size = UDim2.new(1, -(RAIL_W + COL_GAP), 1, -CONTENT_Y)
	emptyState.Visible = false
	emptyState.ZIndex = z + 3
	emptyState.Parent = content
	PanelChrome.shout({
		name = "EmptyTitle",
		text = "ALL SOLD OUT HERE!",
		size = 30,
		color = SpecTheme.Surface.ReadInk,
		strokeColor = Color3.new(1, 1, 1),
		align = Enum.TextXAlignment.Center,
		frameSize = UDim2.new(1, 0, 0, 40),
		position = UDim2.new(0, 0, 0.42, 0),
		zIndex = z + 4,
		parent = emptyState,
	})
	local emptySub = PanelChrome.read({
		name = "EmptySub",
		text = "Catch more to fill your bag back up.",
		size = 19,
		color = SpecTheme.Surface.ReadSub,
		align = Enum.TextXAlignment.Center,
		frameSize = UDim2.new(1, 0, 0, 30),
		position = UDim2.new(0, 0, 0.42, 44),
		zIndex = z + 4,
		parent = emptyState,
	})

	--------------------------------------------------------------------- the rail
	local rail = Instance.new("ScrollingFrame")
	rail.Name = "ActionRail"
	rail.BackgroundTransparency = 1
	rail.BorderSizePixel = 0
	rail.Position = UDim2.new(1, -RAIL_W, 0, CONTENT_Y)
	rail.Size = UDim2.new(0, RAIL_W, 1, -CONTENT_Y)
	rail.ZIndex = z + 2
	rail.ScrollBarThickness = 4
	rail.ScrollBarImageColor3 = SpecTheme.OutlineSoft
	rail.CanvasSize = UDim2.new()
	rail.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rail.ElasticBehavior = Enum.ElasticBehavior.Never
	rail.ScrollingDirection = Enum.ScrollingDirection.Y
	rail.Parent = content
	local railList = Instance.new("UIListLayout")
	railList.Padding = UDim.new(0, 10)
	railList.SortOrder = Enum.SortOrder.LayoutOrder
	railList.Parent = rail

	local RAIL_INNER = RAIL_W - 8 -- leave the scrollbar its lane

	----- selection card
	local SEL_CARD_H = 236
	local selCard = PanelChrome.plate({
		name = "SelectionCard",
		size = UDim2.fromOffset(RAIL_INNER, SEL_CARD_H),
		colors = { Color3.new(1, 1, 1), SpecTheme.Surface.RowBottom },
		radius = 20,
		outline = 3,
		strokeColor = SpecTheme.OutlineSoft,
		zIndex = z + 3,
		parent = rail,
		gloss = false,
		layoutOrder = 1,
	})
	PanelChrome.read({
		name = "SelectionHead",
		text = "YOUR SELECTION",
		size = 16,
		color = SpecTheme.Surface.ReadSub,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, -28, 0, 20),
		position = UDim2.fromOffset(14, 12),
		zIndex = z + 4,
		parent = selCard,
	})
	local selLine = PanelChrome.read({
		name = "SelectionLine",
		text = "",
		size = 18,
		color = SpecTheme.Surface.ReadSub,
		wrap = true,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, -28, 0, 46),
		position = UDim2.fromOffset(14, 36),
		zIndex = z + 4,
		parent = selCard,
	})
	local selPayout = PanelChrome.shout({
		name = "SelectionPayout",
		text = "",
		size = 32,
		color = SpecTheme.Surface.ReadInk,
		strokeColor = Color3.new(1, 1, 1),
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, -28, 0, 38),
		position = UDim2.fromOffset(14, 86),
		zIndex = z + 4,
		parent = selCard,
	})
	local sellSelectedBtn = PanelChrome.pill({
		name = "SellSelected",
		text = "SELL SELECTED",
		colors = SpecTheme.Action.Danger, -- handoff: every sell action is red, KEEP THEM is green
		size = UDim2.new(1, -28, 0, 62),
		position = UDim2.fromOffset(14, 132),
		textSize = 24,
		zIndex = z + 4,
		parent = selCard,
	})
	local function linkButton(name: string, text: string, colour: Color3, alignRight: boolean): TextButton
		local b = Instance.new("TextButton")
		b.Name = name
		b.Text = ""
		b.AutoButtonColor = false
		b.BackgroundTransparency = 1
		b.Size = UDim2.new(0.5, -14, 0, 26)
		b.Position = if alignRight then UDim2.new(1, -14, 0, 202) else UDim2.fromOffset(14, 202)
		b.AnchorPoint = if alignRight then Vector2.new(1, 0) else Vector2.new(0, 0)
		b.ZIndex = z + 4
		b.Parent = selCard
		PanelChrome.read({
			name = "Label",
			text = text,
			size = 16,
			color = colour,
			align = if alignRight then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
			frameSize = UDim2.fromScale(1, 1),
			zIndex = b.ZIndex + 1,
			parent = b,
		})
		return b
	end
	local selectAllBtn = linkButton("SelectAllShown", "SELECT ALL SHOWN", SpecTheme.Action.Go[2], false)
	local clearBtn = linkButton("ClearSelection", "CLEAR", SpecTheme.Surface.ReadSub, true)

	----- quick sell
	local quickHead = PanelChrome.read({
		name = "QuickSellHead",
		text = "QUICK SELL",
		size = 16,
		color = SpecTheme.Surface.ReadSub,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, -8, 0, 22),
		zIndex = z + 3,
		parent = rail,
	})
	quickHead.LayoutOrder = 2
	quickHead.Visible = SHOW_QUICK_SELL

	local QUICK_ROW_H = 104
	local function buildQuickRow(order: number)
		local row = PanelChrome.plate({
			name = "QuickRow" .. order,
			size = UDim2.fromOffset(RAIL_INNER, QUICK_ROW_H),
			colors = { Color3.new(1, 1, 1), SpecTheme.Surface.RowBottom },
			radius = 18,
			outline = 3,
			strokeColor = SpecTheme.OutlineSoft,
			zIndex = z + 3,
			parent = rail,
			gloss = false,
			layoutOrder = 2 + order,
		})
		local title = PanelChrome.read({
			name = "Title",
			text = "",
			size = 19,
			color = SpecTheme.Surface.ReadInk,
			align = Enum.TextXAlignment.Left,
			frameSize = UDim2.new(1, -24, 0, 24),
			position = UDim2.fromOffset(12, 10),
			zIndex = z + 4,
			parent = row,
		})
		local sub = PanelChrome.read({
			name = "Sub",
			text = "",
			size = 15,
			color = SpecTheme.Surface.ReadSub,
			wrap = true,
			align = Enum.TextXAlignment.Left,
			frameSize = UDim2.new(1, -116, 0, 34),
			position = UDim2.fromOffset(12, 34),
			zIndex = z + 4,
			parent = row,
		})
		local payout = PanelChrome.shout({
			name = "Payout",
			text = "",
			size = 22,
			color = SpecTheme.Surface.ReadInk,
			strokeColor = Color3.new(1, 1, 1),
			align = Enum.TextXAlignment.Left,
			frameSize = UDim2.new(1, -116, 0, 26),
			position = UDim2.fromOffset(12, 70),
			zIndex = z + 4,
			parent = row,
		})
		local btn = PanelChrome.pill({
			name = "Sell",
			text = "SELL",
			colors = SpecTheme.Action.Danger,
			size = UDim2.fromOffset(92, 52),
			position = UDim2.new(1, -12, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			textSize = 20,
			zIndex = z + 4,
			parent = row,
		})
		return { root = row, title = title, sub = sub, payout = payout, btn = btn, run = nil :: (() -> ())? }
	end

	local quickRows = { buildQuickRow(1), buildQuickRow(2), buildQuickRow(3) }
	for _, q in ipairs(quickRows) do
		q.root.Visible = SHOW_QUICK_SELL
		q.btn.Activated:Connect(function()
			if q.run then
				q.run()
			end
		end)
	end

	local trustNote = PanelChrome.read({
		name = "TrustNote",
		text = "",
		size = 15,
		color = SpecTheme.Surface.ReadSub,
		wrap = true,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, -8, 0, 46),
		zIndex = z + 3,
		parent = rail,
	})
	trustNote.LayoutOrder = 9

	-- pill's disabled state is decided at BUILD time, so this is the runtime
	-- equivalent: Active false is what stops Activated firing (the same trick
	-- the old species grid used for unpriceable tiles), and the fade matches
	-- PanelChrome.pill's own `enabled = false` look.
	local function setPillEnabled(b: TextButton, on: boolean)
		b.Active = on
		b.BackgroundTransparency = if on then 0 else 0.45
		for _, d in ipairs(b:GetDescendants()) do
			if d:IsA("TextLabel") then
				d.TextTransparency = if on then 0 else 0.45
			end
		end
	end

	----------------------------------------------------------- confirm dialog
	-- Every sell action routes through startSell() below, which opens this
	-- first whenever the scope contains something worth protecting. One modal
	-- at a time, parented into the panel's own root -- the same idiom
	-- BackpackPanel's openModalScrim/closeModal use.
	local activeModal: Instance? = nil
	local function closeModal()
		if activeModal then
			activeModal:Destroy()
			activeModal = nil
		end
	end

	-- rare: the stacks that tripped the threshold, in the order they were picked.
	local function openConfirm(units: number, coins: number, rare: { any }, onConfirm: () -> ())
		closeModal()
		local scrim = Instance.new("TextButton")
		scrim.Name = "SellConfirmScrim"
		scrim.Text = ""
		scrim.AutoButtonColor = false
		scrim.BackgroundColor3 = Color3.fromRGB(10, 14, 6)
		scrim.BackgroundTransparency = 0.5
		scrim.BorderSizePixel = 0
		scrim.Size = UDim2.fromScale(1, 1)
		scrim.ZIndex = z + 30
		scrim.Parent = shell.root
		scrim.MouseButton1Click:Connect(closeModal)
		activeModal = scrim

		local dlg = PanelChrome.plate({
			name = "SellConfirmDialog",
			size = UDim2.fromOffset(700, 440),
			position = UDim2.fromScale(0.5, 0.5),
			anchor = Vector2.new(0.5, 0.5),
			colors = { Color3.new(1, 1, 1), SpecTheme.Surface.RowBottom },
			radius = 28,
			outline = 6,
			strokeColor = SpecTheme.OutlineSoft,
			zIndex = z + 31,
			parent = scrim,
		})
		dlg.Active = true -- eat clicks so the scrim's click-to-cancel underneath does not also fire

		PanelChrome.shout({
			name = "Title",
			text = "HOLD ON!",
			size = 38,
			color = SpecTheme.Surface.ReadInk,
			strokeColor = Color3.new(1, 1, 1),
			align = Enum.TextXAlignment.Center,
			frameSize = UDim2.new(1, -40, 0, 46),
			position = UDim2.new(0, 20, 0, 20),
			zIndex = z + 32,
			parent = dlg,
		})
		PanelChrome.read({
			name = "Body",
			text = ("You're about to sell %d %s, including these rare finds:")
				:format(units, units == 1 and "item" or "items"),
			size = 20,
			color = SpecTheme.Surface.ReadSub,
			wrap = true,
			align = Enum.TextXAlignment.Center,
			frameSize = UDim2.new(1, -60, 0, 50),
			position = UDim2.new(0, 30, 0, 74),
			zIndex = z + 32,
			parent = dlg,
		})

		-- up to six 84px rarity frames, then "+N more"
		local strip = Instance.new("Frame")
		strip.Name = "RareStrip"
		strip.BackgroundTransparency = 1
		strip.Position = UDim2.new(0, 30, 0, 132)
		strip.Size = UDim2.new(1, -60, 0, 122)
		strip.ZIndex = z + 32
		strip.Parent = dlg
		local stripList = Instance.new("UIListLayout")
		stripList.FillDirection = Enum.FillDirection.Horizontal
		stripList.HorizontalAlignment = Enum.HorizontalAlignment.Center
		stripList.VerticalAlignment = Enum.VerticalAlignment.Top
		stripList.Padding = UDim.new(0, 12)
		stripList.SortOrder = Enum.SortOrder.LayoutOrder
		stripList.Parent = strip

		local SHOWN = math.min(#rare, 6)
		for i = 1, SHOWN do
			local item = rare[i]
			local cell = Instance.new("Frame")
			cell.Name = "Rare" .. i
			cell.BackgroundTransparency = 1
			cell.Size = UDim2.fromOffset(84, 118)
			cell.LayoutOrder = i
			cell.ZIndex = z + 32
			cell.Parent = strip

			local frame = PanelChrome.plate({
				name = "Art",
				size = UDim2.fromOffset(84, 84),
				colors = { Color3.new(1, 1, 1), SpecTheme.Surface.RowBottom },
				radius = 16,
				outline = 4,
				strokeColor = rarityRamp(item.rarity)[1],
				zIndex = z + 33,
				parent = cell,
				gloss = false,
			})
			local holder = Instance.new("Frame")
			holder.Name = "Holder"
			holder.BackgroundTransparency = 1
			holder.Position = UDim2.fromOffset(6, 6)
			holder.Size = UDim2.new(1, -12, 1, -12)
			holder.ZIndex = frame.ZIndex + 1
			holder.Parent = frame
			addArtMat(holder)
			local vp
			if item.kind == "pet" then
				vp = BrainrotThumb.addPet(holder, item.model, item.name, {
					size = UDim2.fromScale(1, 1),
					zIndex = holder.ZIndex + 1,
					ambient = PET_ART_AMBIENT,
					lightColor = PET_ART_LIGHT,
					lightDirection = PET_ART_DIR,
				})
			else
				vp = BrainrotThumb.add(holder, item.name, {
					size = UDim2.fromScale(1, 1),
					zIndex = holder.ZIndex + 1,
				})
			end
			if not vp then
				addMissingArtMark(holder)
			end
			PanelChrome.read({
				name = "Name",
				text = item.name,
				size = 15,
				color = SpecTheme.Surface.ReadInk,
				align = Enum.TextXAlignment.Center,
				frameSize = UDim2.new(1, 0, 0, 30),
				position = UDim2.fromOffset(0, 88),
				zIndex = z + 33,
				parent = cell,
			})
		end
		if #rare > SHOWN then
			local more = Instance.new("Frame")
			more.Name = "More"
			more.BackgroundTransparency = 1
			more.Size = UDim2.fromOffset(90, 84)
			more.LayoutOrder = 99
			more.ZIndex = z + 32
			more.Parent = strip
			PanelChrome.read({
				name = "Label",
				text = ("+%d more"):format(#rare - SHOWN),
				size = 18,
				color = SpecTheme.Surface.ReadSub,
				align = Enum.TextXAlignment.Center,
				frameSize = UDim2.fromScale(1, 1),
				zIndex = z + 33,
				parent = more,
			})
		end

		PanelChrome.read({
			name = "Payout",
			text = ("You'll get %s"):format(NumberFormat.Cash(coins)),
			size = 24,
			color = SpecTheme.Surface.ReadInk,
			align = Enum.TextXAlignment.Center,
			frameSize = UDim2.new(1, -60, 0, 32),
			position = UDim2.new(0, 30, 0, 262),
			zIndex = z + 32,
			parent = dlg,
		})

		local keep = PanelChrome.pill({
			name = "KeepThem",
			text = "KEEP THEM",
			colors = SpecTheme.Action.Go,
			size = UDim2.fromOffset(230, 68),
			position = UDim2.new(0.5, -12, 1, -26),
			anchor = Vector2.new(1, 1),
			textSize = 24,
			zIndex = z + 32,
			parent = dlg,
		})
		keep.Activated:Connect(closeModal)

		local sellAnyway = PanelChrome.pill({
			name = "SellAnyway",
			text = "SELL ANYWAY",
			colors = SpecTheme.Action.Danger,
			size = UDim2.fromOffset(230, 68),
			position = UDim2.new(0.5, 12, 1, -26),
			anchor = Vector2.new(0, 1),
			textSize = 24,
			zIndex = z + 32,
			parent = dlg,
		})
		sellAnyway.Activated:Connect(function()
			onConfirm()
			closeModal()
		end)
	end

	----------------------------------------------------------------- the sell pipe
	-- ONE door for every sale on this screen (the handoff's startSell): decide
	-- whether the scope needs a confirmation, then fire. Nothing else in this
	-- module touches remotes.SellBrainrot / remotes.SellPet.
	--
	-- `picks` is { { stack, units } }. The uids handed to the server are taken
	-- off the stack's own entry list, which is built from the SAME three gates
	-- SellHandler re-checks (unplaced, unlocked, priceable) -- so a selection is
	-- structurally incapable of containing a uid the server would refuse, and
	-- the advertised total can never be more than the paid one.
	local function startSell(picks: { any })
		local units, coinsParts, rare, brainrotUids, petUids = 0, {}, {}, {}, {}
		-- BOTH server handlers reject an over-long payload WHOLE -- PetHandler
		-- returns without so much as a refusal toast -- so the cap is applied
		-- HERE, before anything is totalled, and the confirm dialog then quotes
		-- exactly the sale that is about to be fired rather than a larger one.
		for _, p in ipairs(picks) do
			local st = p.stack
			local room = if st.kind == "pet"
				then MAX_PET_UIDS - #petUids
				else MAX_BRAINROT_UIDS - #brainrotUids
			local n = math.min(p.units, st.count, math.max(room, 0))
			if n > 0 then
				units += n
				table.insert(coinsParts, { kind = st.kind, unit = st.unit, units = n })
				local special = (st.mutation ~= nil) or (st.size ~= nil)
				local rank = RARITY_RANK[st.rarity or ""] or 0
				if rank >= CONFIRM_RANK or (CONFIRM_ON_SPECIAL and special) then
					table.insert(rare, st)
				end
				for i = 1, n do
					local uid = st.entries[i]
					if uid then
						if st.kind == "pet" then
							table.insert(petUids, uid)
						else
							table.insert(brainrotUids, uid)
						end
					end
				end
			end
		end
		if units == 0 then
			return
		end

		local coins = payoutOfEntries(coinsParts)

		local function fire()
			if #brainrotUids > 0 then
				remotes.SellBrainrot:FireServer({ Uids = brainrotUids })
			end
			if #petUids > 0 then
				remotes.SellPet:FireServer(petUids)
			end
			sel = {}
			if refresh then
				refresh()
			end
		end

		if #rare > 0 then
			openConfirm(units, coins, rare, fire)
		else
			fire()
		end
	end

	--------------------------------------------------------------------- stacking
	-- One entry per name + mutation + size (brainrots) or per pet Id (pets).
	-- Only SELLABLE copies go in -- the same gates the server applies -- and
	-- everything held back is COUNTED rather than silently dropped, so the meta
	-- line can say why the numbers do not match the bag.
	local function buildStacks()
		local byKey: { [string]: any } = {}
		local order: { any } = {}
		heldBack = 0

		if tab == "brainrots" then
			for _, e in ipairs(state.Brainrots) do
				local priceable = SellValue.BaseRate(e.Name) ~= nil
				if e.PadIndex ~= nil or e.PlotFav or not priceable then
					heldBack += 1
				else
					local key = ("%s|%s|%s"):format(e.Name, tostring(e.Mutation), tostring(e.Size))
					local st = byKey[key]
					if not st then
						st = {
							key = key,
							kind = "brainrot",
							name = e.Name,
							rarity = rarityByName[e.Name],
							mutation = e.Mutation,
							size = e.Size,
							unit = SellValue.OfBrainrot(e) or 0,
							entries = {},
						}
						byKey[key] = st
						table.insert(order, st)
					end
					table.insert(st.entries, e.Uid)
				end
			end
		else
			local equipped: { [string]: boolean } = {}
			for _, uid in ipairs(state.PetSlots) do
				equipped[uid] = true
			end
			for _, pet in ipairs(state.Pets) do
				if equipped[pet.Uid] then
					heldBack += 1
				else
					local def = PetConfig.Pets[pet.Id]
					local key = "pet|" .. tostring(pet.Id)
					local st = byKey[key]
					if not st then
						st = {
							key = key,
							kind = "pet",
							name = (def and def.Name) or pet.Id,
							rarity = def and def.Rarity,
							model = def and def.Model,
							petId = pet.Id,
							mutation = nil,
							size = nil,
							unit = SellValue.OfPet(pet.Id),
							entries = {},
						}
						byKey[key] = st
						table.insert(order, st)
					end
					table.insert(st.entries, pet.Uid)
				end
			end
		end

		for _, st in ipairs(order) do
			st.count = #st.entries
		end
		-- Rarest first, then dearest, then A-Z: the same reading order the Bag
		-- and the Index use (PetConfig.RARITY_ORDER is rarest-first).
		table.sort(order, function(a, b)
			local ra = RARITY_RANK[a.rarity or ""] or 0
			local rb = RARITY_RANK[b.rarity or ""] or 0
			if ra ~= rb then
				return ra > rb
			end
			if a.unit ~= b.unit then
				return a.unit > b.unit
			end
			return a.name < b.name
		end)
		return order
	end

	local function passesFilters(st: any): boolean
		if rarityFilter ~= "all" and st.rarity ~= rarityFilter then
			return false
		end
		if tab == "brainrots" then
			if mutFilter == "none" then
				if st.mutation ~= nil then
					return false
				end
			elseif mutFilter ~= "all" then
				if st.mutation ~= mutFilter then
					return false
				end
			end
		end
		if search ~= "" and st.name:lower():find(search, 1, true) == nil then
			return false
		end
		return true
	end

	----------------------------------------------------------------------- a tile
	local rebuildGrid: (() -> ())? = nil
	local paintRail: (() -> ())? = nil

	local function selectedOf(st: any): number
		return sel[st.key] or 0
	end

	local function setSelected(st: any, units: number)
		units = math.clamp(units, 0, st.count)
		if units <= 0 then
			sel[st.key] = nil
		else
			sel[st.key] = units
		end
		local api = tileApi[st.key]
		if api then
			api.update()
		end
		if paintRail then
			paintRail()
		end
	end

	local function buildTile(order: number, st: any)
		local isMutated = st.mutation ~= nil or st.size ~= nil

		local tile = PanelChrome.plate({
			name = "StackTile",
			size = UDim2.fromOffset(TILE_W, TILE_H),
			colors = { Color3.new(1, 1, 1), SpecTheme.Surface.RowBottom },
			radius = 18,
			-- THE RARITY FRAME (handoff): the tile's own edge carries the tier.
			-- Never the art mat, never the fill.
			outline = 4,
			strokeColor = rarityRamp(st.rarity)[1],
			zIndex = z + 3,
			parent = grid,
			gloss = false,
			layoutOrder = order,
		})

		local artHolder = Instance.new("Frame")
		artHolder.Name = "Art"
		artHolder.BackgroundTransparency = 1
		artHolder.Position = UDim2.fromOffset(8, 8)
		artHolder.Size = UDim2.new(1, -16, 0, ART_H)
		artHolder.ZIndex = tile.ZIndex + 1
		artHolder.Parent = tile
		addArtMat(artHolder)

		local vp
		if st.kind == "pet" then
			vp = BrainrotThumb.addPet(artHolder, st.model, st.name, {
				size = UDim2.fromScale(1, 1),
				zIndex = artHolder.ZIndex + 1,
				ambient = PET_ART_AMBIENT,
				lightColor = PET_ART_LIGHT,
				lightDirection = PET_ART_DIR,
			})
		else
			vp = BrainrotThumb.add(artHolder, st.name, {
				size = UDim2.fromScale(1, 1),
				zIndex = artHolder.ZIndex + 1,
			})
		end
		if not vp then
			-- No model for this name (the ghost species some real saves carry).
			addMissingArtMark(artHolder)
		end

		-- count chip, top-left, only when the stack is more than one
		if st.count > 1 then
			local chip = Instance.new("Frame")
			chip.Name = "CountChip"
			chip.Position = UDim2.fromOffset(6, 6)
			chip.Size = UDim2.fromOffset(38, 22)
			chip.BackgroundColor3 = SpecTheme.Outline
			chip.BorderSizePixel = 0
			chip.ZIndex = tile.ZIndex + 4
			chip.Parent = tile
			local cc = Instance.new("UICorner")
			cc.CornerRadius = UDim.new(0, 8)
			cc.Parent = chip
			PanelChrome.read({
				name = "Count",
				text = "x" .. tostring(st.count),
				size = 15,
				color = Color3.new(1, 1, 1),
				align = Enum.TextXAlignment.Center,
				frameSize = UDim2.fromScale(1, 1),
				zIndex = chip.ZIndex + 1,
				parent = chip,
			})
		end

		-- mutation / size pill, bottom-centre of the art, coloured by the
		-- mutation itself (MutationConfig owns those colours). Sizes.Label is
		-- the one combined "Golden Massive" builder the Bag/IncomeLoop share.
		if isMutated then
			local label = Sizes.Label(st.mutation, st.size, nil)
			local pill = Instance.new("Frame")
			pill.Name = "MutationPill"
			pill.AnchorPoint = Vector2.new(0.5, 1)
			pill.Position = UDim2.new(0.5, 0, 0, ART_H + 4)
			pill.Size = UDim2.fromOffset(TILE_W - 28, 22)
			pill.BackgroundColor3 = mutationColour(st.mutation)
			pill.BorderSizePixel = 0
			pill.ZIndex = tile.ZIndex + 4
			pill.Parent = tile
			local pc = Instance.new("UICorner")
			pc.CornerRadius = UDim.new(0, 10)
			pc.Parent = pill
			local ps = Instance.new("UIStroke")
			ps.Thickness = 2
			ps.Color = SpecTheme.Outline
			ps.Parent = pill
			PanelChrome.shout({
				name = "Label",
				text = label:upper(),
				size = 14,
				color = Color3.new(1, 1, 1),
				align = Enum.TextXAlignment.Center,
				frameSize = UDim2.new(1, -8, 1, 0),
				position = UDim2.fromOffset(4, 0),
				zIndex = pill.ZIndex + 1,
				parent = pill,
				scaled = true,
			})

			-- ...and the mutated tile also wears a rainbow ring OUTSIDE its
			-- rarity frame, so the tier colour is never overwritten (handoff:
			-- "rainbow ring = mutated, never recolor the rarity frame").
			local ring = Instance.new("Frame")
			ring.Name = "MutationRing"
			ring.BackgroundTransparency = 1
			ring.Position = UDim2.fromOffset(-3, -3)
			ring.Size = UDim2.new(1, 6, 1, 6)
			ring.ZIndex = tile.ZIndex + 5
			ring.Parent = tile
			local rc = Instance.new("UICorner")
			rc.CornerRadius = UDim.new(0, 21)
			rc.Parent = ring
			local rs = Instance.new("UIStroke")
			rs.Thickness = 3
			rs.Color = Color3.new(1, 1, 1)
			rs.Parent = ring
			local rg = Instance.new("UIGradient")
			rg.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 92, 92)),
				ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 214, 74)),
				ColorSequenceKeypoint.new(0.50, Color3.fromRGB(96, 226, 118)),
				ColorSequenceKeypoint.new(0.75, Color3.fromRGB(92, 178, 255)),
				ColorSequenceKeypoint.new(1.00, Color3.fromRGB(199, 110, 255)),
			})
			rg.Rotation = 35
			rg.Parent = rs
		end

		local nameLabel = PanelChrome.read({
			name = "StackName",
			text = st.name,
			size = 15,
			color = SpecTheme.Surface.ReadInk,
			align = Enum.TextXAlignment.Center,
			frameSize = UDim2.new(1, -10, 0, 24),
			position = UDim2.fromOffset(5, ART_H + 12),
			zIndex = tile.ZIndex + 2,
			parent = tile,
		})
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

		-- LINE 2, two states in the same 32px band (handoff): the unit price
		-- when the tile is unselected, the quantity stepper when it is.
		local LINE2_Y = ART_H + 40
		local priceLabel = PanelChrome.read({
			name = "UnitPrice",
			text = NumberFormat.Cash(st.unit),
			size = 17,
			color = SpecTheme.Surface.ReadSub,
			align = Enum.TextXAlignment.Center,
			frameSize = UDim2.new(1, -10, 0, 28),
			position = UDim2.fromOffset(5, LINE2_Y),
			zIndex = tile.ZIndex + 2,
			parent = tile,
		})

		local stepper = Instance.new("Frame")
		stepper.Name = "Stepper"
		stepper.BackgroundTransparency = 1
		stepper.Position = UDim2.fromOffset(8, LINE2_Y)
		stepper.Size = UDim2.new(1, -16, 0, 28)
		stepper.Visible = false
		stepper.ZIndex = tile.ZIndex + 6
		stepper.Parent = tile

		local function stepButton(name: string, glyph: string, x: number, onPress: () -> ())
			local b = PanelChrome.pill({
				name = name,
				text = glyph,
				colors = SpecTheme.Action.Neutral,
				size = UDim2.fromOffset(26, 26),
				position = UDim2.fromOffset(x, 1),
				radius = 13,
				textSize = 18,
				zIndex = stepper.ZIndex + 1,
				parent = stepper,
			})
			b.Activated:Connect(onPress)
			return b
		end
		-- 124px of inner tile: 26 + 34 + 26 + 34, so MAX keeps a readable plate
		-- instead of shrinking to the shout builder's 9px floor.
		stepButton("Dec", "\u{2212}", 0, function()
			setSelected(st, selectedOf(st) - 1)
		end)
		local countLabel = PanelChrome.read({
			name = "StepCount",
			text = "",
			size = 16,
			color = SpecTheme.Surface.ReadInk,
			align = Enum.TextXAlignment.Center,
			frameSize = UDim2.fromOffset(34, 28),
			position = UDim2.fromOffset(27, 0),
			zIndex = stepper.ZIndex + 1,
			parent = stepper,
		})
		stepButton("Inc", "+", 62, function()
			setSelected(st, selectedOf(st) + 1)
		end)
		local maxBtn = PanelChrome.pill({
			name = "Max",
			text = "MAX",
			colors = SpecTheme.Action.Go,
			size = UDim2.fromOffset(34, 26),
			position = UDim2.new(1, 0, 0, 1),
			anchor = Vector2.new(1, 0),
			radius = 9,
			textSize = 14,
			zIndex = stepper.ZIndex + 1,
			parent = stepper,
		})
		maxBtn.Activated:Connect(function()
			setSelected(st, st.count)
		end)

		-- selection chrome: green ring + check medallion
		local selRing = Instance.new("Frame")
		selRing.Name = "SelectedRing"
		selRing.BackgroundTransparency = 1
		selRing.Position = UDim2.fromOffset(-5, -5)
		selRing.Size = UDim2.new(1, 10, 1, 10)
		selRing.Visible = false
		selRing.ZIndex = tile.ZIndex + 7
		selRing.Parent = tile
		local src = Instance.new("UICorner")
		src.CornerRadius = UDim.new(0, 23)
		src.Parent = selRing
		local srs = Instance.new("UIStroke")
		srs.Thickness = 4
		srs.Color = SpecTheme.Action.Go[1]
		srs.Parent = selRing

		local check = PanelChrome.plate({
			name = "Check",
			size = UDim2.fromOffset(30, 30),
			position = UDim2.new(1, 6, 0, -6),
			anchor = Vector2.new(1, 0),
			colors = SpecTheme.Action.Go,
			radius = 15,
			outline = 3,
			zIndex = tile.ZIndex + 8,
			parent = tile,
			gloss = false,
		})
		check.Visible = false
		PanelChrome.shout({
			name = "Tick",
			text = "\u{2713}",
			size = 18,
			zIndex = check.ZIndex + 1,
			parent = check,
		})

		-- The whole-tile hit target sits BELOW the stepper (which is at +6/+7),
		-- so a tap on a stepper button never also toggles the tile. That is this
		-- kit's equivalent of the handoff's stopPropagation.
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.AutoButtonColor = false
		hit.BackgroundTransparency = 1
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = tile.ZIndex + 5
		hit.Parent = tile
		hit.Activated:Connect(function()
			if selectedOf(st) > 0 then
				setSelected(st, 0)
			else
				setSelected(st, 1)
			end
		end)

		local function update()
			local n = selectedOf(st)
			local on = n > 0
			stepper.Visible = on
			priceLabel.Visible = not on
			selRing.Visible = on
			check.Visible = on
			countLabel.Text = ("%d/%d"):format(n, st.count)
		end
		update()

		tileApi[st.key] = { update = update }
	end

	----------------------------------------------------------------- quick sells
	-- Every row is a Uids payload built from the SAME stacks the grid is
	-- showing, so its advertised total is the total the server pays. Mode =
	-- "Duplicates" is deliberately NOT used: that server mode sells EVERY
	-- bulk-eligible copy, which is not what "keep 1 of each" means.
	local function quickPicks(kind: string): { any }
		local picks = {}
		if kind == "spares" then
			for _, st in ipairs(stacks) do
				if st.count > 1 then
					table.insert(picks, { stack = st, units = st.count - 1 })
				end
			end
		elseif kind == "shown" then
			for _, st in ipairs(stacks) do
				table.insert(picks, { stack = st, units = st.count })
			end
		else -- "all"
			for _, st in ipairs(allStacks) do
				table.insert(picks, { stack = st, units = st.count })
			end
		end
		return picks
	end

	local function picksTotals(picks: { any }): (number, number, number)
		local units, parts, stackCount = 0, {}, 0
		for _, p in ipairs(picks) do
			if p.units > 0 then
				units += p.units
				stackCount += 1
				table.insert(parts, { kind = p.stack.kind, unit = p.stack.unit, units = p.units })
			end
		end
		return units, payoutOfEntries(parts), stackCount
	end

	----------------------------------------------------------------- the rail paint
	paintRail = function()
		local picks = {}
		for _, st in ipairs(allStacks) do
			local n = sel[st.key]
			if n and n > 0 then
				table.insert(picks, { stack = st, units = n })
			end
		end
		local units, coins, stackCount = picksTotals(picks)

		if units == 0 then
			selLine.Text = "Tap a tile to sell 1 \u{2014} use \u{2212} + MAX on the tile to set the amount."
			selLine.TextColor3 = SpecTheme.Surface.ReadSub
			selPayout.Text = ""
			setPillEnabled(sellSelectedBtn, false)
		else
			selLine.Text = ("%d %s \u{2022} %d %s"):format(
				stackCount, stackCount == 1 and "stack" or "stacks",
				units, units == 1 and "item" or "items")
			selLine.TextColor3 = SpecTheme.Surface.ReadInk
			selPayout.Text = "+" .. NumberFormat.Cash(coins)
			setPillEnabled(sellSelectedBtn, true)
		end

		local noun = if tab == "pets" then "PETS" else "BRAINROTS"
		local specs = {
			{ kind = "spares", title = "Duplicates \u{2022} Keep 1" },
			{ kind = "shown", title = "Everything Shown" },
			{ kind = "all", title = "All " .. noun },
		}
		for i, q in ipairs(quickRows) do
			local spec = specs[i]
			local picksFor = quickPicks(spec.kind)
			local qUnits, qCoins, qStacks = picksTotals(picksFor)
			q.title.Text = spec.title
			if spec.kind == "spares" then
				q.sub.Text = ("Sells %d %s, keeps 1 of each"):format(qUnits, qUnits == 1 and "spare" or "spares")
			elseif spec.kind == "shown" then
				q.sub.Text = ("%d %s \u{2022} follows your filters"):format(qStacks, qStacks == 1 and "stack" or "stacks")
			else
				q.sub.Text = "The whole category, filters ignored"
			end
			q.payout.Text = if qUnits > 0 then "+" .. NumberFormat.Cash(qCoins) else "Nothing to sell"
			setPillEnabled(q.btn, qUnits > 0)
			q.run = function()
				startSell(quickPicks(spec.kind))
			end
		end

		if CONFIRM_FROM_RARITY then
			trustNote.Text = ("%s and above \u{2014} and anything mutated or oversized \u{2014} always ask before they sell.")
				:format(CONFIRM_FROM_RARITY)
		else
			trustNote.Text = ""
		end
	end

	sellSelectedBtn.Activated:Connect(function()
		local picks = {}
		for _, st in ipairs(allStacks) do
			local n = sel[st.key]
			if n and n > 0 then
				table.insert(picks, { stack = st, units = n })
			end
		end
		startSell(picks)
	end)
	selectAllBtn.Activated:Connect(function()
		-- "SELECT ALL SHOWN selects FULL stacks" (handoff).
		for _, st in ipairs(stacks) do
			sel[st.key] = st.count
		end
		if rebuildGrid then
			rebuildGrid()
		end
	end)
	clearBtn.Activated:Connect(function()
		sel = {}
		if rebuildGrid then
			rebuildGrid()
		end
	end)

	------------------------------------------------------------------ chip rows
	local function paintChips()
		for _, c in ipairs(rarityStrip:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		for _, c in ipairs(mutStrip:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end

		-- Chips are built from what the player ACTUALLY HOLDS, not from the
		-- full config: eight rarity chips and twelve mutation chips would
		-- overflow the strip, and a chip that can only ever filter to zero is
		-- noise. "All" is always first.
		local haveRarity: { [string]: boolean } = {}
		local haveMut: { [string]: boolean } = {}
		local anyPlain = false
		for _, st in ipairs(allStacks) do
			if st.rarity then
				haveRarity[st.rarity] = true
			end
			if st.mutation then
				haveMut[st.mutation] = true
			elseif st.size == nil then
				anyPlain = true
			end
		end

		local order = 1
		buildChip(rarityStrip, order, "All", nil, rarityFilter == "all", function()
			rarityFilter = "all"
			if rebuildGrid then
				rebuildGrid()
			end
		end)
		for _, word in ipairs(RARITY_ORDER) do
			if haveRarity[word] then
				order += 1
				local w = word
				buildChip(rarityStrip, order, w, rarityRamp(w)[1], rarityFilter == w, function()
					rarityFilter = w
					if rebuildGrid then
						rebuildGrid()
					end
				end)
			end
		end

		mutStrip.Visible = (tab == "brainrots")
		mutGutter.Visible = (tab == "brainrots")
		if tab == "brainrots" then
			order = 1
			buildChip(mutStrip, order, "All", nil, mutFilter == "all", function()
				mutFilter = "all"
				if rebuildGrid then
					rebuildGrid()
				end
			end)
			if anyPlain then
				order += 1
				buildChip(mutStrip, order, "Normal", nil, mutFilter == "none", function()
					mutFilter = "none"
					if rebuildGrid then
						rebuildGrid()
					end
				end)
			end
			for _, m in ipairs(Mutations.Order) do
				if haveMut[m.Name] then
					order += 1
					local name = m.Name
					buildChip(mutStrip, order, name, m.Color, mutFilter == name, function()
						mutFilter = name
						if rebuildGrid then
							rebuildGrid()
						end
					end)
				end
			end
		end
	end

	------------------------------------------------------------------- grid paint
	rebuildGrid = function()
		for _, c in ipairs(grid:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		tileApi = {}

		stacks = {}
		for _, st in ipairs(allStacks) do
			if passesFilters(st) then
				table.insert(stacks, st)
			end
		end

		local shownItems = 0
		for i, st in ipairs(stacks) do
			shownItems += st.count
			buildTile(i, st)
		end

		local hasAny = #stacks > 0
		grid.Visible = hasAny
		emptyState.Visible = not hasAny
		if not hasAny then
			emptySub.Text = if #allStacks > 0
				then "Nothing matches those filters."
				else "Catch more to fill your bag back up."
		end

		local meta = ("%d %s \u{2022} %d %s shown"):format(
			#stacks, #stacks == 1 and "stack" or "stacks",
			shownItems, shownItems == 1 and "item" or "items")
		if heldBack > 0 then
			meta ..= (" \u{2022} %d held back"):format(heldBack)
		end
		metaLeft.Text = meta

		paintChips()
		if paintRail then
			paintRail()
		end
	end

	------------------------------------------------------------------ header tabs
	shell.addHeaderTabs({
		{ text = "BRAINROTS", width = 200 },
		{ text = "PETS", width = 130 },
	}, 1, function(idx)
		local next_ = if idx == 1 then "brainrots" else "pets"
		if next_ == tab then
			return
		end
		tab = next_
		-- The handoff: "Tab select -> resets filters and selection."
		rarityFilter = "all"
		mutFilter = "all"
		search = ""
		searchBox.Text = ""
		sel = {}
		if refresh then
			refresh()
		end
	end)

	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		search = searchBox.Text:lower()
		if rebuildGrid then
			rebuildGrid()
		end
	end)

	--------------------------------------------------------------------- refresh
	refresh = function()
		allStacks = buildStacks()

		-- A snapshot can shrink a stack (or delete it) under a live selection --
		-- a sale elsewhere, a plot placement, a trade. Clamp before anything
		-- reads `sel`, so the rail can never total units that no longer exist.
		local live: { [string]: number } = {}
		local byKey: { [string]: any } = {}
		for _, st in ipairs(allStacks) do
			byKey[st.key] = st
		end
		for key, n in pairs(sel) do
			local st = byKey[key]
			if st then
				local clamped = math.clamp(n, 0, st.count)
				if clamped > 0 then
					live[key] = clamped
				end
			end
		end
		sel = live

		if rebuildGrid then
			rebuildGrid()
		end
	end
	refresh()

	----------------------------------------------------------- debounced rebuild
	-- Coalesces DataUpdated bursts into one rebuild every 0.25s -- matches
	-- BackpackPanel's own scheduleRender delay -- and skips the rebuild entirely
	-- while the panel is closed, so a catch/sale/purchase/plot-collect/trade/
	-- hatch/pet-equip anywhere else in the game no longer tears down and
	-- rebuilds the whole grid (every tile carries a BrainrotThumb ViewportFrame
	-- and a cloned model) on every one of DataUpdated's client fires.
	local pendingRender = false
	scheduleRender = function()
		if pendingRender then
			return
		end
		pendingRender = true
		task.delay(0.25, function()
			pendingRender = false
			if shell.root.Visible then
				refresh()
			end
		end)
	end

	-- REOPEN FRESHNESS GUARANTEE: shell.root's own Visible flip (GameHUDClient
	-- owns it, per this module's header contract) forces an IMMEDIATE,
	-- undebounced refresh, so any DataUpdated pushes skipped while the panel was
	-- closed are always caught the instant it opens again.
	shell.root:GetPropertyChangedSignal("Visible"):Connect(function()
		if shell.root.Visible then
			closeModal()
			refresh()
		end
	end)

	return shell.root
end

return SellPanel
