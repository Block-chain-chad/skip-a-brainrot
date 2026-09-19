--!strict
-- SellPanel: Marco's counter. A GameHUDPanels consumer module.
-- Contract: { Id = "sell", Build = function(ctx) -> Frame }. Build runs ONCE on
-- first open; GameHUDClient parents the frame and owns Visible. Never set
-- Parent here and never animate open/close here.
--
-- TASK 5 SCOPE ONLY (2026-08-20 sell-shop-revamp): shell, header tabs
-- (BRAINROTS / PETS) and the quick-sell bar with its irreversible-action
-- confirm dialog. The species grid (Task 6), the drill-down multi-select
-- (Task 7) and the Pets tab's real content (Task 8) are NOT built here --
-- brainrotsTab is an empty content well below the quick-sell bar, ready for
-- Task 6 to fill; petsTab is an empty placeholder frame per the Task 5 brief.
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
	end
	refresh()

	return shell.root
end

return SellPanel
