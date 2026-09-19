--!strict
-- SellPanel: Marco's counter. A GameHUDPanels consumer module.
-- Contract: { Id = "sell", Build = function(ctx) -> Frame }. Build runs ONCE on
-- first open; GameHUDClient parents the frame and owns Visible. Never set
-- Parent here and never animate open/close here.
--
-- TASK 5 SCOPE: shell, header tabs (BRAINROTS / PETS) and the quick-sell
-- bar with its irreversible-action confirm dialog.
-- TASK 6 SCOPE (this pass, 2026-08-20 sell-shop-revamp): the species grid
-- and search box, filling the well Task 5 left under the quick-sell bar.
-- Grid tiles show only UNPLACED copies (PadIndex == nil); a species with no
-- SellValue.BaseRate renders GREYED and UNCLICKABLE, never hidden -- the two
-- priceless ghost species in real saves must be visible. Each tile's click
-- handler is a forward-declared openSpecies(name) stub; the real per-species
-- drill-down (multi-select, per-copy sell) is Task 7's job, not this one.
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

	----------------------------------------------------------- header tabs (Step 3)
	local activeTabIndex = 1
	shell.addHeaderTabs({
		{ text = "BRAINROTS", width = 140 },
		{ text = "PETS", width = 110 },
	}, 1, function(idx)
		activeTabIndex = idx
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
	-- Tile click target. Left as a documented no-op: Task 7 replaces this with
	-- the real per-species drill-down (multi-select, per-copy sell). Every
	-- tile's hit button already calls this by name, so Task 7 only has to fill
	-- the body in -- no SellPanel structure changes.
	local function openSpecies(name: string)
		-- TODO(Task 7): open the per-species drill-down for `name`.
	end

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
			openSpecies(name)
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

	local function openConfirm(count: number, total: number)
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
			text = "SELL DUPLICATES?",
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
			text = ("This sells %d duplicates for %s. This cannot be undone."):format(count, NumberFormat.Cash(total)),
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
			remotes.SellBrainrot:FireServer({ Mode = "Duplicates" })
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
		openConfirm(#chosen, total)
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
		local counts, copies, order = {}, {}, {}
		for _, e in ipairs(state.Brainrots) do
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
	end
	refresh()

	return shell.root
end

return SellPanel
