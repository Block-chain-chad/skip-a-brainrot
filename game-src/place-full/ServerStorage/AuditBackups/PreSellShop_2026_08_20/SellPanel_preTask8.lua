--!strict
-- SellPanel: Marco's counter. A GameHUDPanels consumer module.
-- Contract: { Id = "sell", Build = function(ctx) -> Frame }. Build runs ONCE on
-- first open; GameHUDClient parents the frame and owns Visible. Never set
-- Parent here and never animate open/close here.
--
-- TASK 5 SCOPE: shell, header tabs (BRAINROTS / PETS) and the quick-sell
-- bar with its irreversible-action confirm dialog.
-- TASK 6 SCOPE (2026-08-20 sell-shop-revamp): the species grid and search
-- box, filling the well Task 5 left under the quick-sell bar. Grid tiles
-- show only UNPLACED copies (PadIndex == nil); a species with no
-- SellValue.BaseRate renders GREYED and UNCLICKABLE, never hidden -- the two
-- priceless ghost species in real saves must be visible.
-- TASK 7 SCOPE (this pass, 2026-08-20 sell-shop-revamp): openSpecies(name)
-- -- Task 6 left it a forward-declared no-op -- now opens a THIRD full-bleed
-- tab body (DrilldownTab, same "sibling toggled by Visible" idiom as
-- petsTab) listing EVERY copy of that species, placed and favourited
-- included, each labelled with the reason it cannot be sold. A copy only
-- gets a checkbox when it passes the SAME three gates SellHandler's Uids
-- branch checks (unplaced, unfavourited, priceable) -- selection is
-- structurally incapable of including a uid the server would refuse, so the
-- footer's "Sell N -- total" can never advertise more than it pays. Firing
-- the sale reuses Step 5's confirm-dialog idiom (openConfirm is now
-- title/body/onConfirm-parameterised so both the quick-sell bar and this
-- drill-down share one modal instead of two).
-- The Pets tab's real content (Task 8) is still not built here; petsTab
-- stays an empty placeholder frame per the Task 5 brief.
--
-- DEVIATION FROM THE BRIEF'S STEP 1 SKELETON (judgment call, see
-- task-5-report.md): the brief's example names PanelChrome.shell's return
-- value "root" and `return`s it directly, but PanelChrome.shell actually
-- returns the shellApi TABLE ({ root, header, body, close, list, titleLabel,
-- z, addHeaderTabs }), not a Frame -- returning it as-is would violate the
-- documented "Build -> Frame" contract. Every real panel (ShopPanel,
-- ProgressPanel, BackpackPanel) names it `shell` and returns `shell.root`;
-- this module does the same.
--
-- Every price shown here comes from SellValue (BaseRate / OfBrainrot /
-- SelectBulk) -- never recomputed locally. That duplication (a sell row
-- advertising one price while the server paid another) is the exact bug
-- this whole project exists to remove.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PanelChrome = require(ReplicatedStorage.Modules.UIKit.PanelChrome)
local SpecTheme = require(ReplicatedStorage.Modules.UIKit.SpecTheme)
local SellValue = require(ReplicatedStorage.Modules.SellValue)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local BrainrotThumb = require(ReplicatedStorage.Modules.BrainrotThumb)
local Sizes = require(ReplicatedStorage.Modules.SizeConfig) -- Sizes.Label is the one combined mutation+size label builder (BackpackPanel/IncomeLoop/CatchCinematic all share it); Task 7's drill-down rows reuse it rather than re-concatenating.
local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local SellPanel = { Id = "sell" }

------------------------------------------------------------- server-confirmed data
-- Same "module-top-level capture, not inside Build" fix every other
-- GameHUDPanels module carries (see BackpackPanel's header note): this
-- module is require()d once, early, at GameHUDClient's own script top level;
-- Build(ctx) only runs lazily on first open. The server's join-time
-- DataUpdated push (or the one-shot GetInitialData pull below) can land well
-- before Build ever runs, so the snapshot is captured here, at true
-- require-time -- not inside Build -- exactly mirroring BackpackPanel/
-- ShopPanel's own top-level wiring.
local state = { Brainrots = {}, Pets = {} }
local refresh: (() -> ())? = nil -- forward declaration; assigned in Build

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
	if refresh then
		refresh()
	end
end

remotes.DataUpdated.OnClientEvent:Connect(applySnapshot)
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
		title = "MARCO THE BUYER",
		key = "shop", -- no dedicated SpecTheme.Plate/ShellFor "sell" entry yet; "shop" is the closest existing colourway (see task-5-report.md)
		scroll = false,
		listLayout = false, -- two full-bleed tab bodies share the well, same idiom ProgressPanel uses for its two embedded tabs
	})
	shell.close.Activated:Connect(function()
		if ctx.closePanel then
			ctx.closePanel()
		end
	end)
	local z = shell.z

	----------------------------------------------------------- tab bodies
	-- Full-bleed siblings inside shell.body, toggled by Visible -- the exact
	-- pattern ProgressPanel uses for its embedded GoalsPanel/PassPanel frames.
	local brainrotsTab = Instance.new("Frame")
	brainrotsTab.Name = "BrainrotsTab"
	brainrotsTab.BackgroundTransparency = 1
	brainrotsTab.Size = UDim2.fromScale(1, 1)
	brainrotsTab.ZIndex = z + 2
	brainrotsTab.Parent = shell.body
	local brainrotsList = Instance.new("UIListLayout")
	brainrotsList.Padding = UDim.new(0, 14)
	brainrotsList.SortOrder = Enum.SortOrder.LayoutOrder
	brainrotsList.Parent = brainrotsTab

	-- Task 8 fills this with the real Pets tab (grid + multi-select); an
	-- empty placeholder frame is the whole Task 5 scope for it per the brief.
	local petsTab = Instance.new("Frame")
	petsTab.Name = "PetsTab"
	petsTab.BackgroundTransparency = 1
	petsTab.Size = UDim2.fromScale(1, 1)
	petsTab.Visible = false
	petsTab.ZIndex = z + 2
	petsTab.Parent = shell.body
	PanelChrome.read({
		name = "ComingSoon",
		text = "Coming soon",
		size = 24,
		color = SpecTheme.Surface.ReadSub,
		align = Enum.TextXAlignment.Center,
		frameSize = UDim2.new(1, 0, 0, 40),
		position = UDim2.new(0, 0, 0.5, -20),
		zIndex = z + 3,
		parent = petsTab,
	})

	----------------------------------------------------------- per-species drill-down (Task 7)
	-- A THIRD full-bleed sibling of brainrotsTab/petsTab, toggled by Visible --
	-- the exact idiom the Task 5 comment above documents for petsTab (itself
	-- borrowed from ProgressPanel's embedded GoalsPanel/PassPanel frames).
	-- openSpecies (forward-declared where Task 6 left its stub, real body
	-- assigned further down after the confirm-dialog idiom it reuses) shows
	-- this and hides brainrotsTab; BACK (or a tab switch) reverses it. Kept
	-- OUT of brainrotsList's layout on purpose, same reason petsTab is: a
	-- full-bleed view swap, not a list row.
	--
	-- `copies[name]` (Task 6's grouping) is UNPLACED-ONLY by construction --
	-- exactly the set the server will actually sell -- so it stays the source
	-- for selection and totals (hoisted here, unchanged shape, so this
	-- section and refresh() below see the same table; see refresh() for the
	-- one-line change that stopped it being function-local). It cannot show a
	-- PLACED copy's row though, and the brief + global constraints require
	-- placed (and favourited) copies to be listed with their reason, never
	-- silently dropped. `speciesAll[name]` is the one addition: the SAME
	-- grouping loop, unfiltered, kept ONLY for the drill-down's display list
	-- -- selection and pricing never read from it.
	local currentName: string? = nil
	local selected: { [string]: boolean } = {}
	local copies: { [string]: { any } } = {}
	local speciesAll: { [string]: { any } } = {}
	local rebuildDrilldownList: (() -> ())? = nil

	local DD_HEADER_H, DD_FOOTER_H, DD_GAP = 64, 84, 14

	local drilldownTab = Instance.new("Frame")
	drilldownTab.Name = "DrilldownTab"
	drilldownTab.BackgroundTransparency = 1
	drilldownTab.Size = UDim2.fromScale(1, 1)
	drilldownTab.Visible = false
	drilldownTab.ZIndex = z + 2
	drilldownTab.Parent = shell.body

	local ddHeader = Instance.new("Frame")
	ddHeader.Name = "DrilldownHeader"
	ddHeader.BackgroundTransparency = 1
	ddHeader.Size = UDim2.new(1, 0, 0, DD_HEADER_H)
	ddHeader.ZIndex = z + 2
	ddHeader.Parent = drilldownTab

	local ddBack = PanelChrome.pill({
		name = "Back",
		text = "\u{2190} BACK",
		colors = SpecTheme.Action.Neutral,
		size = UDim2.fromOffset(150, DD_HEADER_H),
		textSize = 22,
		zIndex = z + 3,
		parent = ddHeader,
	})

	local ddTitle = PanelChrome.read({
		name = "DrilldownTitle",
		text = "",
		size = 26,
		color = SpecTheme.Surface.ReadInk,
		frameSize = UDim2.new(1, -170, 1, 0),
		position = UDim2.fromOffset(166, 0),
		zIndex = z + 3,
		parent = ddHeader,
	})

	local ddList = Instance.new("ScrollingFrame")
	ddList.Name = "DrilldownList"
	ddList.BackgroundTransparency = 1
	ddList.BorderSizePixel = 0
	ddList.Position = UDim2.fromOffset(0, DD_HEADER_H + DD_GAP)
	ddList.Size = UDim2.new(1, 0, 1, -(DD_HEADER_H + DD_GAP + DD_FOOTER_H + DD_GAP))
	ddList.ZIndex = z + 2
	ddList.ScrollBarThickness = 5
	ddList.ScrollBarImageColor3 = SpecTheme.OutlineSoft
	ddList.CanvasSize = UDim2.new()
	ddList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	ddList.ElasticBehavior = Enum.ElasticBehavior.Never
	ddList.ScrollingDirection = Enum.ScrollingDirection.Y
	ddList.Parent = drilldownTab

	local ddListLayout = Instance.new("UIListLayout")
	ddListLayout.Padding = UDim.new(0, 10)
	ddListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	ddListLayout.Parent = ddList

	-- The footer IS the "Sell N -- total" control (brief Step 2); its own
	-- Label text is rewritten on every rebuild rather than paired with a
	-- separate caption -- the same "one pill, dynamic text" shape quickPill
	-- and quickLabel/quickNote already use next door.
	local ddFooterPill = PanelChrome.pill({
		name = "DrilldownSellPill",
		text = "",
		colors = SpecTheme.Action.Go,
		size = UDim2.fromOffset(340, DD_FOOTER_H),
		position = UDim2.new(0.5, 0, 1, -8),
		anchor = Vector2.new(0.5, 1),
		textSize = 24,
		zIndex = z + 3,
		parent = drilldownTab,
	})

	local function closeDrilldown()
		drilldownTab.Visible = false
		brainrotsTab.Visible = true
		currentName = nil
		selected = {}
	end
	ddBack.Activated:Connect(closeDrilldown)

	----------------------------------------------------------- header tabs (Step 3)
	local activeTabIndex = 1
	shell.addHeaderTabs({
		{ text = "BRAINROTS", width = 140 },
		{ text = "PETS", width = 110 },
	}, 1, function(idx)
		activeTabIndex = idx
		if drilldownTab.Visible then
			closeDrilldown() -- a tab switch always returns to the grid, never leaves the drill-down open behind PETS
		end
		brainrotsTab.Visible = (idx == 1)
		petsTab.Visible = (idx == 2)
		if refresh then
			refresh()
		end
	end)

	----------------------------------------------------------- quick-sell bar (Step 4)
	PanelChrome.sectionHead({
		text = "QUICK SELL",
		parent = brainrotsTab,
		layoutOrder = 1,
		zIndex = z + 2,
	})

	local QUICK_H = 100
	local quickBar = PanelChrome.plate({
		name = "QuickSellBar",
		size = UDim2.new(1, 0, 0, QUICK_H),
		colors = { SpecTheme.Surface.RowTop, SpecTheme.Surface.RowBottom },
		radius = 22,
		outline = 3,
		strokeColor = SpecTheme.OutlineSoft,
		zIndex = z + 3,
		parent = brainrotsTab,
		gloss = false,
		layoutOrder = 2,
	})

	local quickLabel = PanelChrome.read({
		name = "QuickLabel",
		text = "",
		size = 26,
		color = SpecTheme.Surface.ReadInk,
		frameSize = UDim2.new(1, -264, 0, 32),
		position = UDim2.new(0, 24, 0, 18),
		zIndex = z + 4,
		parent = quickBar,
	})
	local quickNote = PanelChrome.read({
		name = "QuickNote",
		text = "",
		size = 18,
		color = SpecTheme.Surface.ReadSub,
		wrap = true,
		frameSize = UDim2.new(1, -264, 0, 44),
		position = UDim2.new(0, 24, 0, 52),
		zIndex = z + 4,
		parent = quickBar,
	})

	local quickPill = PanelChrome.pill({
		name = "QuickSellPill",
		text = "SELL DUPLICATES",
		colors = SpecTheme.Action.Go,
		size = UDim2.fromOffset(224, 68),
		position = UDim2.new(1, -20, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		textSize = 22,
		zIndex = z + 4,
		parent = quickBar,
	})

	----------------------------------------------------------- species grid (Task 6)
	-- Tile click target. Forward-declared exactly like `refresh` above (see
	-- module-top note): the real body is assigned further down, after the
	-- confirm-dialog idiom (Step 5) it reuses to fire the sale, so this
	-- section and buildSpeciesTile below stay untouched from Task 6.
	local openSpecies: ((name: string) -> ())? = nil

	PanelChrome.sectionHead({
		text = "SELL BY SPECIES",
		parent = brainrotsTab,
		layoutOrder = 3,
		zIndex = z + 2,
	})

	local SEARCH_H = 56
	local searchHost = PanelChrome.plate({
		name = "SearchBox",
		size = UDim2.new(1, 0, 0, SEARCH_H),
		colors = { SpecTheme.Surface.RowTop, SpecTheme.Surface.RowBottom },
		radius = 18,
		outline = 2,
		strokeColor = SpecTheme.OutlineSoft,
		zIndex = z + 3,
		parent = brainrotsTab,
		gloss = false,
		layoutOrder = 4,
	})

	local searchBox = Instance.new("TextBox")
	searchBox.Name = "SearchInput"
	searchBox.BackgroundTransparency = 1
	searchBox.Position = UDim2.fromOffset(20, 0)
	searchBox.Size = UDim2.new(1, -40, 1, 0)
	searchBox.Text = ""
	searchBox.PlaceholderText = "SEARCH SPECIES..."
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

	-- Grid rebuild is driven entirely from refresh() (Step 4 of the brief):
	-- typing sets `filter` and calls refresh(), same as a DataUpdated push.
	local filter = ""
	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		filter = searchBox.Text:lower()
		if refresh then
			refresh()
		end
	end)

	-- Fixed pixel reserve for everything ABOVE the grid (both section heads,
	-- the quick-sell bar and the search box, plus the 4 gaps brainrotsList's
	-- own 14px Padding puts between them) so the grid can claim "the rest" of
	-- brainrotsTab's height with 1-scale, negative-offset math.
	local SECTION_H, GAP = 48, 14
	local GRID_TOP_RESERVED = SECTION_H + GAP + QUICK_H + GAP + SECTION_H + GAP + SEARCH_H + GAP

	local speciesGrid = Instance.new("ScrollingFrame")
	speciesGrid.Name = "SpeciesGrid"
	speciesGrid.BackgroundTransparency = 1
	speciesGrid.BorderSizePixel = 0
	speciesGrid.Size = UDim2.new(1, 0, 1, -GRID_TOP_RESERVED)
	speciesGrid.ZIndex = z + 2
	speciesGrid.ScrollBarThickness = 5
	speciesGrid.ScrollBarImageColor3 = SpecTheme.OutlineSoft
	speciesGrid.CanvasSize = UDim2.new()
	speciesGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	speciesGrid.ElasticBehavior = Enum.ElasticBehavior.Never
	speciesGrid.ScrollingDirection = Enum.ScrollingDirection.Y
	speciesGrid.LayoutOrder = 5
	speciesGrid.Parent = brainrotsTab

	local speciesGridLayout = Instance.new("UIGridLayout")
	local TILE_W, TILE_H = 140, 168
	speciesGridLayout.CellSize = UDim2.fromOffset(TILE_W, TILE_H)
	speciesGridLayout.CellPadding = UDim2.fromOffset(12, 12)
	speciesGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	speciesGridLayout.Parent = speciesGrid

	-- One tile per species. `list` is copies[name] from the grouping in
	-- refresh() -- every UNPLACED copy of this species, used only to detect a
	-- mutation (never to price anything; SellValue owns every price shown).
	local function buildSpeciesTile(layoutOrder: number, name: string, count: number, list)
		local hasMutation = false
		for _, e in ipairs(list) do
			if e.Mutation ~= nil then
				hasMutation = true
				break
			end
		end

		local tile = PanelChrome.plate({
			name = "SpeciesTile",
			size = UDim2.fromOffset(TILE_W, TILE_H),
			colors = { SpecTheme.Surface.RowTop, SpecTheme.Surface.RowBottom },
			radius = 18,
			outline = 3,
			strokeColor = SpecTheme.OutlineSoft,
			zIndex = z + 3,
			parent = speciesGrid,
			gloss = false,
			layoutOrder = layoutOrder,
		})

		local artHolder = Instance.new("Frame")
		artHolder.Name = "Art"
		artHolder.BackgroundTransparency = 1
		artHolder.Position = UDim2.fromOffset(8, 8)
		artHolder.Size = UDim2.new(1, -16, 0, 88)
		artHolder.ZIndex = tile.ZIndex + 1
		artHolder.Parent = tile

		local vp = BrainrotThumb.add(artHolder, name, {
			size = UDim2.fromScale(1, 1),
			zIndex = artHolder.ZIndex + 1,
		})
		if not vp then
			-- No model for this name (matches the two priceless ghost species
			-- some real saves carry) -- a flat swatch keeps the tile's geometry
			-- instead of leaving a hole.
			local swatch = Instance.new("Frame")
			swatch.Name = "ArtFallback"
			swatch.BackgroundColor3 = SpecTheme.Surface.RowBottom
			swatch.BorderSizePixel = 0
			swatch.Size = UDim2.fromScale(1, 1)
			swatch.ZIndex = artHolder.ZIndex + 1
			swatch.Parent = artHolder
			local swatchCorner = Instance.new("UICorner")
			swatchCorner.CornerRadius = UDim.new(0, 12)
			swatchCorner.Parent = swatch
		end

		PanelChrome.read({
			name = "SpeciesName",
			text = name,
			size = 14,
			color = SpecTheme.Surface.ReadInk,
			align = Enum.TextXAlignment.Center,
			wrap = true,
			frameSize = UDim2.new(1, -12, 0, 30),
			position = UDim2.fromOffset(6, 98),
			zIndex = tile.ZIndex + 2,
			parent = tile,
		})

		-- The tile's ONE price line. BaseRate(name) == nil means this species
		-- is in NO config and cannot be priced -- Step 3 below overwrites this
		-- same label with "can't be sold" rather than ever computing a number
		-- for it. When priceable, the sample copy prefers a plain (unmutated,
		-- unsized) entry so the tile advertises the base per-copy price, not
		-- whatever the first copy in the array happens to be.
		local rate = SellValue.BaseRate(name)
		local priceText = ""
		if rate ~= nil then
			local sample = list[1]
			for _, e in ipairs(list) do
				if e.Mutation == nil and e.Size == nil then
					sample = e
					break
				end
			end
			local v = SellValue.OfBrainrot(sample)
			if v then
				priceText = NumberFormat.Cash(v) .. " each"
			end
		end
		local label = PanelChrome.read({
			name = "PriceLabel",
			text = priceText,
			size = 15,
			color = SpecTheme.Surface.ReadSub,
			align = Enum.TextXAlignment.Center,
			frameSize = UDim2.new(1, -12, 0, 20),
			position = UDim2.fromOffset(6, 130),
			zIndex = tile.ZIndex + 2,
			parent = tile,
		})

		do
			local badge = Instance.new("Frame")
			badge.Name = "CountBadge"
			badge.AnchorPoint = Vector2.new(1, 0)
			badge.Position = UDim2.new(1, -6, 0, 6)
			badge.Size = UDim2.fromOffset(36, 22)
			badge.BackgroundColor3 = SpecTheme.Outline
			badge.BackgroundTransparency = 0.1
			badge.BorderSizePixel = 0
			badge.ZIndex = tile.ZIndex + 3
			badge.Parent = tile
			local badgeCorner = Instance.new("UICorner")
			badgeCorner.CornerRadius = UDim.new(0, 11)
			badgeCorner.Parent = badge
			PanelChrome.read({
				name = "Count",
				text = "\u{00D7}" .. tostring(count),
				size = 14,
				color = Color3.new(1, 1, 1),
				align = Enum.TextXAlignment.Center,
				frameSize = UDim2.fromScale(1, 1),
				zIndex = badge.ZIndex + 1,
				parent = badge,
			})
		end

		-- Violet mutation star -- same colour as the Bag's mutation badge, per
		-- the brief. Shown when ANY unplaced copy of this species is mutated.
		local star = PanelChrome.shout({
			name = "MutationStar",
			text = "\u{2605}",
			size = 20,
			color = Color3.fromRGB(193, 76, 255),
			strokeColor = Color3.new(1, 1, 1),
			frameSize = UDim2.fromOffset(24, 24),
			position = UDim2.fromOffset(4, 4),
			zIndex = tile.ZIndex + 3,
			parent = tile,
		})
		star.Visible = hasMutation

		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.AutoButtonColor = false
		hit.BackgroundTransparency = 1
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = tile.ZIndex + 5
		hit.Parent = tile
		hit.Activated:Connect(function()
			if openSpecies then
				openSpecies(name)
			end
		end)

		-- Step 3: unpriceable species render GREYED and UNCLICKABLE, never
		-- hidden -- this is what makes the ghost entries visible instead of
		-- silently absent.
		if rate == nil then
			tile.BackgroundTransparency = 0.5
			label.Text = "can't be sold"
			hit.Active = false
		end
	end

	----------------------------------------------------------- confirm dialog (Step 5)
	-- The bulk action is irreversible (the server sells and cannot undo it),
	-- so quickPill NEVER fires the remote directly -- it opens this scrim +
	-- dialog first. Same "scrim parented into the panel's own root, one modal
	-- at a time" idiom BackpackPanel's openModalScrim/closeModal use, redrawn
	-- with PanelChrome primitives (this module's chrome family) rather than
	-- the older UI.surface/UI.button builders BackpackPanel also carries.
	local activeModal: Frame? = nil
	local function closeModal()
		if activeModal then
			activeModal:Destroy()
			activeModal = nil
		end
	end

	local function openConfirm(title: string, body: string, onConfirm: () -> ())
		closeModal()
		local scrim = Instance.new("TextButton")
		scrim.Name = "SellConfirmScrim"
		scrim.Text = ""
		scrim.AutoButtonColor = false
		scrim.BackgroundColor3 = Color3.new(1, 1, 1)
		scrim.BackgroundTransparency = 0.3
		scrim.BorderSizePixel = 0
		scrim.Size = UDim2.fromScale(1, 1)
		scrim.ZIndex = z + 30
		scrim.Parent = shell.root
		scrim.MouseButton1Click:Connect(closeModal)
		activeModal = scrim

		local dlg = PanelChrome.plate({
			name = "SellConfirmDialog",
			size = UDim2.fromOffset(480, 268),
			position = UDim2.fromScale(0.5, 0.5),
			anchor = Vector2.new(0.5, 0.5),
			colors = { Color3.new(1, 1, 1), SpecTheme.Surface.RowBottom },
			radius = 28,
			outline = 6,
			zIndex = z + 31,
			parent = scrim,
		})
		dlg.Active = true -- eat clicks so the scrim's click-to-cancel underneath does not also fire

		PanelChrome.shout({
			name = "Title",
			text = title,
			size = 32,
			color = SpecTheme.Surface.ReadInk,
			strokeColor = Color3.new(1, 1, 1),
			align = Enum.TextXAlignment.Center,
			frameSize = UDim2.new(1, -40, 0, 40),
			position = UDim2.new(0, 20, 0, 22),
			zIndex = z + 32,
			parent = dlg,
		})
		PanelChrome.read({
			name = "Body",
			text = body,
			size = 19,
			color = SpecTheme.Surface.ReadSub,
			wrap = true,
			align = Enum.TextXAlignment.Center,
			frameSize = UDim2.new(1, -48, 0, 74),
			position = UDim2.new(0, 24, 0, 76),
			zIndex = z + 32,
			parent = dlg,
		})

		local cancelBtn = PanelChrome.pill({
			name = "Cancel",
			text = "CANCEL",
			colors = SpecTheme.Action.Neutral,
			size = UDim2.fromOffset(196, 68),
			position = UDim2.new(0, 24, 1, -24),
			anchor = Vector2.new(0, 1),
			textSize = 24,
			zIndex = z + 32,
			parent = dlg,
		})
		cancelBtn.Activated:Connect(closeModal)

		local confirmBtn = PanelChrome.pill({
			name = "Confirm",
			text = "CONFIRM",
			colors = SpecTheme.Action.Go,
			size = UDim2.fromOffset(196, 68),
			position = UDim2.new(1, -24, 1, -24),
			anchor = Vector2.new(1, 1),
			textSize = 24,
			zIndex = z + 32,
			parent = dlg,
		})
		confirmBtn.Activated:Connect(function()
			onConfirm()
			closeModal()
		end)
	end

	quickPill.Activated:Connect(function()
		local chosen = SellValue.SelectBulk(state.Brainrots, nil)
		if #chosen == 0 then
			return
		end
		local total = 0
		for _, e in ipairs(chosen) do
			total += (SellValue.OfBrainrot(e) or 0)
		end
		openConfirm("SELL DUPLICATES?",
			("This sells %d duplicates for %s. This cannot be undone."):format(#chosen, NumberFormat.Cash(total)),
			function()
				remotes.SellBrainrot:FireServer({ Mode = "Duplicates" })
			end)
	end)

	----------------------------------------------------------- per-species drill-down logic (Task 7)
	-- Brief Step 2's exact shape: n and sum walk copies[currentName] (the
	-- unplaced-only table), summing only what is actually in `selected`.
	local function totalSelected(): (number, number)
		local n, sum = 0, 0
		local list = currentName and copies[currentName]
		if list then
			for _, e in ipairs(list) do
				if selected[e.Uid] then
					n += 1
					sum += (SellValue.OfBrainrot(e) or 0)
				end
			end
		end
		return n, sum
	end

	local function setFooterText(text: string)
		local label = ddFooterPill:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then
			label.Text = text
		end
	end

	-- One row per copy in speciesAll[currentName] -- EVERY copy of the
	-- species, placed or not, favourited or not (global constraint: the
	-- server's refusal must never be a surprise). A row only becomes
	-- SELECTABLE -- gets a Hit button and can enter `selected` -- when all
	-- three of SellHandler's own Uids gates already pass: unplaced,
	-- unfavourited, priceable. That is what makes an over-the-wire refusal
	-- structurally impossible: nothing this code lets the player pick can
	-- fail that check.
	local function buildDrilldownRow(layoutOrder: number, entry)
		local price = SellValue.OfBrainrot(entry)
		local placed = entry.PadIndex ~= nil
		local fav = entry.Fav == true
		local sellable = (not placed) and (not fav) and price ~= nil
		local ROW_H = 60

		local row = PanelChrome.plate({
			name = "CopyRow",
			size = UDim2.new(1, 0, 0, ROW_H),
			colors = if sellable then { SpecTheme.Surface.RowTop, SpecTheme.Surface.RowBottom } else SpecTheme.Action.Pale,
			radius = 16,
			outline = 2,
			strokeColor = SpecTheme.OutlineSoft,
			zIndex = z + 3,
			parent = ddList,
			gloss = false,
			layoutOrder = layoutOrder,
		})

		if sellable then
			local isSelected = selected[entry.Uid] == true
			local box = PanelChrome.plate({
				name = "CheckBox",
				size = UDim2.fromOffset(28, 28),
				position = UDim2.new(0, 16, 0.5, 0),
				anchor = Vector2.new(0, 0.5),
				colors = if isSelected then SpecTheme.Action.Go else { Color3.new(1, 1, 1), SpecTheme.Surface.RowBottom },
				radius = 8,
				outline = 3,
				strokeColor = SpecTheme.OutlineSoft,
				zIndex = z + 4,
				parent = row,
				gloss = false,
			})
			if isSelected then
				PanelChrome.shout({
					text = "\u{2713}",
					size = 20,
					zIndex = z + 5,
					parent = box,
				})
			end
		end

		local labelText = Sizes.Label(entry.Mutation, entry.Size, nil)
		if labelText == "" then
			labelText = "Plain"
		end
		PanelChrome.read({
			name = "CopyLabel",
			text = labelText,
			size = 20,
			color = if sellable then SpecTheme.Surface.ReadInk else SpecTheme.Surface.ReadSub,
			frameSize = UDim2.new(1, -220, 1, 0),
			position = UDim2.fromOffset(56, 0),
			zIndex = z + 4,
			parent = row,
		})

		if sellable then
			PanelChrome.read({
				name = "CopyPrice",
				text = NumberFormat.Cash(price or 0),
				size = 20,
				color = SpecTheme.Surface.ReadInk,
				align = Enum.TextXAlignment.Right,
				frameSize = UDim2.new(0, 180, 1, 0),
				position = UDim2.new(1, -196, 0, 0),
				zIndex = z + 4,
				parent = row,
			})

			local hit = Instance.new("TextButton")
			hit.Name = "Hit"
			hit.Text = ""
			hit.AutoButtonColor = false
			hit.BackgroundTransparency = 1
			hit.Size = UDim2.fromScale(1, 1)
			hit.ZIndex = z + 6
			hit.Parent = row
			hit.Activated:Connect(function()
				selected[entry.Uid] = not selected[entry.Uid] or nil
				if rebuildDrilldownList then
					rebuildDrilldownList()
				end
			end)
		else
			local reason = if placed then "PLACED" elseif fav then "FAVOURITED" else "CAN'T BE SOLD"
			PanelChrome.read({
				name = "Reason",
				text = reason,
				size = 16,
				color = SpecTheme.Surface.ReadSub,
				align = Enum.TextXAlignment.Right,
				frameSize = UDim2.new(0, 180, 1, 0),
				position = UDim2.new(1, -196, 0, 0),
				zIndex = z + 4,
				parent = row,
			})
		end
	end

	rebuildDrilldownList = function()
		if not currentName then
			return
		end
		local list = speciesAll[currentName]
		if not list or #list == 0 then
			-- every copy of this species is gone (sold elsewhere while this view
			-- was open) -- nothing left to show; fall back to the grid rather
			-- than render an empty shell. The grid underneath is already current
			-- for this snapshot (this only ever runs after the grid rebuild in
			-- refresh(), or from openSpecies on a name a freshly-clicked tile
			-- guarantees is non-empty).
			closeDrilldown()
			return
		end

		-- A selection can go stale from an external change (a DataUpdated push
		-- landing while this view is open) -- prune anything selected that is
		-- no longer eligible so the footer total can never drift from what is
		-- actually still choosable. `copies[currentName]` membership alone only
		-- re-checks "still unplaced" -- Fav can flip true on an unplaced copy
		-- (e.g. the player locks it elsewhere) without ever removing it from
		-- that table, so the other two Uids gates are re-checked here too.
		local stillEligible = {}
		for _, e in ipairs(copies[currentName] or {}) do
			if not e.Fav and SellValue.OfBrainrot(e) ~= nil then
				stillEligible[e.Uid] = true
			end
		end
		for uid in pairs(selected) do
			if not stillEligible[uid] then
				selected[uid] = nil
			end
		end

		ddTitle.Text = ("%s \u{00D7} %d"):format(currentName, #list)

		for _, c in ipairs(ddList:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		for i, entry in ipairs(list) do
			buildDrilldownRow(i, entry)
		end

		local n, sum = totalSelected()
		setFooterText(("Sell %d \u{2014} %s"):format(n, NumberFormat.Cash(sum)))
		ddFooterPill.Visible = n > 0
	end

	openSpecies = function(name: string)
		currentName = name
		selected = {}
		drilldownTab.Visible = true
		brainrotsTab.Visible = false
		if rebuildDrilldownList then
			rebuildDrilldownList()
		end
	end

	ddFooterPill.Activated:Connect(function()
		if not currentName then
			return
		end
		local name = currentName
		local n, sum = totalSelected()
		if n == 0 then
			return
		end
		openConfirm(("SELL %d COPIES?"):format(n),
			("This sells %d %s for %s. This cannot be undone."):format(n, name, NumberFormat.Cash(sum)),
			function()
				local uids = {}
				for _, e in ipairs(copies[name] or {}) do
					if selected[e.Uid] then
						uids[#uids + 1] = e.Uid
					end
				end
				remotes.SellBrainrot:FireServer({ Uids = uids })
				selected = {}
				if rebuildDrilldownList then
					rebuildDrilldownList()
				end
			end)
	end)

	----------------------------------------------------------- refresh (Step 4)
	refresh = function()
		local chosen, held = SellValue.SelectBulk(state.Brainrots, nil)
		local total = 0
		for _, e in ipairs(chosen) do
			total += (SellValue.OfBrainrot(e) or 0)
		end
		quickLabel.Text = ("Sell %d duplicates \u{2014} %s"):format(#chosen, NumberFormat.Cash(total))
		quickNote.Text = ("%d held back \u{2014} favourited, placed, mutated or oversized, or unsellable"):format(held)
		quickPill.Visible = #chosen > 0

		-- Step 1: group the unplaced snapshot into species (brief's exact shape).
		for _, c in ipairs(speciesGrid:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local counts, order = {}, {}
		copies, speciesAll = {}, {} -- hoisted (Task 7): both this grid rebuild and the drill-down read the same tables afterward
		for _, e in ipairs(state.Brainrots) do
			if speciesAll[e.Name] == nil then
				speciesAll[e.Name] = {}
			end
			table.insert(speciesAll[e.Name], e)
			if e.PadIndex == nil then
				if counts[e.Name] == nil then
					counts[e.Name] = 0
					copies[e.Name] = {}
					order[#order + 1] = e.Name
				end
				counts[e.Name] += 1
				table.insert(copies[e.Name], e)
			end
		end
		table.sort(order) -- A-Z scans easier than snapshot-append order; not spec'd either way

		local shown = 0
		for _, name in ipairs(order) do
			if filter == "" or name:lower():find(filter, 1, true) ~= nil then
				shown += 1
				buildSpeciesTile(shown, name, counts[name], copies[name])
			end
		end
		if shown == 0 then
			PanelChrome.read({
				name = "EmptyMsg",
				text = if filter ~= "" then "No species match your search." else "Nothing here yet \u{2014} go skip some rocks!",
				size = 18,
				color = SpecTheme.Surface.ReadSub,
				align = Enum.TextXAlignment.Center,
				frameSize = UDim2.new(1, 0, 0, 40),
				zIndex = z + 3,
				parent = speciesGrid,
			})
		end

		-- Keep the drill-down in sync with a live snapshot too (a DataUpdated
		-- push, or the search box's own refresh() call, can land while it is
		-- open) rather than only ever rebuilding it from openSpecies.
		if drilldownTab.Visible and rebuildDrilldownList then
			rebuildDrilldownList()
		end
	end
	refresh()

	return shell.root
end

return SellPanel
