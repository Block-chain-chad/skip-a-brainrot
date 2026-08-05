--!strict
-- ShopPanel: Robux purchase panel -- a GameHUDPanels consumer module
-- (StarterPlayer.StarterPlayerScripts.GameHUDPanels.ShopPanel).
--
-- Contract (identical to PassPanel/DailyPanel/GoalsPanel -- the family
-- template, read those headers first):
--   return { Id = "shop", Build = function(ctx) -> Frame }
-- Build is called ONCE lazily on first open; the shell (GameHUDClient) parents
-- the returned Frame into ctx.host and owns Visible toggling on every
-- open/close after that -- this module never sets its own Parent or drives
-- its own open/close animation. GameHUDClient's startup loop auto-registers
-- any ModuleScript in this folder (GameHUDClient.client.lua ~:1415), so this
-- file needs NO registration edit -- only a rail button to be reachable (see
-- docs/monetization/shop-panel-remotes.md for that proposed one-liner).
--
-- ============================================================================
-- DATA CONTRACT (read ReplicatedStorage.Modules.GamepassConfig,
-- ServerScriptService.Modules.GamepassService and
-- ServerScriptService.Modules.ProductRegistry FULLY before touching this):
--
--   Pass catalog -- GamepassConfig.List (SHARED on purpose: its own header
--     says "SHARED so a future shop UI can read names / icons / prices
--     straight from here"). Key/GamepassId/Name/Icon/Desc/RobuxPrice consumed
--     verbatim. GamepassId == 0 means "not created yet" (GamepassService
--     convention) -> the card renders COMING SOON and NEVER carries a click
--     connection. Double-guarded: the disabled-variant button is Active=false
--     AND no handler is ever connected to it; live buy handlers ALSO re-check
--     id > 0 and not-owned at click time.
--
--   Darrel packs -- ProductRegistry.Init's PACK_AMOUNTS { 80, 180, 400, 1000 }
--     with PACK_IDS all 0. Those tables are LOCALS inside a server module the
--     client cannot require, so this panel carries a mirror (PACK_FALLBACK
--     below) that MUST be kept in sync by hand until the optional ShopState
--     remote exists. ProductId == 0 -> COMING SOON, same no-connection rule.
--
--   remotes.ShopState -- OPTIONAL RemoteFunction, does not exist in this
--     build (documented + proposed server patch in
--     docs/monetization/shop-panel-remotes.md):
--       client -> server: ShopState:InvokeServer()   (no args)
--       returns: { Owned = { [PassKey: string]: true },
--                  Packs = { { Amount: number, ProductId: number }, ... } }
--     Resolved with a BOUNDED WaitForChild (5s, ToastClient/SettingsPanel
--     convention) inside a spawned thread so the lazy Build never stalls
--     openPanel. Absent (today) -> permanent client-only fallback:
--       - ownership: MarketplaceService:UserOwnsGamePassAsync per pass with a
--         REAL id (zero calls while everything is 0), pcall'd like
--         GamepassService.refresh does server-side;
--       - packs: the PACK_FALLBACK mirror.
--
--   Purchases -- client-side MarketplaceService prompts, per task spec:
--     PromptGamePassPurchase(player, GamepassId) for passes,
--     PromptProductPurchase(player, ProductId) for Darrel packs. No new
--     purchase remotes: grants already land server-side via GamepassService's
--     PromptGamePassPurchaseFinished cache listener (passes) and
--     ProductRegistry.ProcessReceipt (products -- the game's single
--     ProcessReceipt assignment; see that file's header).
--
--   Ownership state -- server-confirmed only, with ONE deliberate exception
--     mirroring the server's own convention: the client's
--     PromptGamePassPurchaseFinished(wasPurchased=true) flips owned[Key]
--     locally, exactly like GamepassService.Init's listener flips its cache.
--     No other click handler ever writes into `owned`.
--
-- Pack prices are NOT in ProductRegistry (dev-product prices live on the
-- dashboard), so live packs fetch theirs via GetProductInfo(id, Product) --
-- pcall'd, cached, async; the button says "BUY" until the price lands. Pass
-- prices come straight from GamepassConfig.RobuxPrice (display only; Roblox
-- charges the dashboard price at prompt time regardless).
--
-- Emoji note: pass Icon glyphs render on the default face (FredokaOne has no
-- emoji -- GameHUDClient's glyphFallback comment), with NoPolish set so the
-- UIPolish sweep leaves them alone. GamepassConfig's 1F9F2 (magnet) is not
-- yet render-proven in this build's emoji font -- flagged in the companion
-- doc, swap the Icon string in GamepassConfig if it shows tofu.
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local modules = ReplicatedStorage:WaitForChild("Modules")
local GamepassConfig = require(modules:WaitForChild("GamepassConfig"))

local ShopPanel = { Id = "shop" }

function ShopPanel.Build(ctx)
	local T = ctx.Tokens
	local UI = ctx.Builders

	-- Darrel's drawn face + the kit's shop art, pcall'd (GoalsPanel
	-- convention): a missing or broken IconArt must not take the panel down.
	local okIconArt, IconArt = pcall(function()
		return require(game:GetService("ReplicatedStorage").Modules.UIKit.IconArt)
	end)
	if not okIconArt then IconArt = nil end

	----------------------------------------------------------- geometry
	-- No `shop` key exists in T.size.panelWidth yet (Tokens is not edited by
	-- this task); 900 matches Daily's slot in the width family and clears the
	-- 2-column left rail with room to spare. Forward-compatible read: paste a
	-- shop key into Tokens later and this line starts honouring it.
	local PANEL_W = T.size.panelWidth.shop or 900
	local HEADER_H = T.size.headerHeight -- 92
	local BODY_TOP = HEADER_H + 12
	local TAB_H = 56 -- GoalsPanel's tab bar height, verbatim
	local TAB_GAP = T.pad.gap -- 12 (same token GoalsPanel's tabs reuse)
	local CONTENT_GAP = 12
	local CONTENT_H = 480 -- GoalsPanel's rows viewport, verbatim (5x88 + 4x10)
	local BODY_CONTENT_H = TAB_H + CONTENT_GAP + CONTENT_H -- 548
	local BODY_H = T.pad.panel * 2 + BODY_CONTENT_H -- 580
	local GROUP_H = BODY_TOP + BODY_H -- 684, fits the 775 canvas
	local BODY_INNER_W = PANEL_W - T.pad.panel * 2 -- 868
	local TAB_W = (BODY_INNER_W - TAB_GAP) / 2 -- two tabs, not Goals' three

	-- pass rows (GoalsPanel quest-row family)
	local ROW_H = T.size.questRow -- 88
	local ROW_GAP = T.pad.rowGap -- 10
	local ROW_PAD_X = 12
	local ICON_W = 60
	local TEXT_X = ROW_PAD_X + ICON_W + 10
	local ACTION_W, ACTION_H = 190, 60 -- 190: "COMING SOON" at buttonM needs it

	-- darrel pack cards (PassPanel reward-card family, taller for a buy button)
	local CARD_W, CARD_H = 196, 300
	local CARD_GAP = T.pad.gridGap -- 11
	local CARDS_Y = 66

	----------------------------------------------------------- module-local state
	-- `owned` is server-confirmed only (plus the PromptGamePassPurchaseFinished
	-- exception documented in the header). `packs` starts as the hand-kept
	-- mirror of ProductRegistry.Init's locals and is REPLACED wholesale by a
	-- ShopState payload if that remote ever appears.
	local owned: { [string]: boolean } = {}
	local PACK_FALLBACK = {
		{ Amount = 80, ProductId = 0 },
		{ Amount = 180, ProductId = 0 },
		{ Amount = 400, ProductId = 0 },
		{ Amount = 1000, ProductId = 0 },
	}
	local packs: { { Amount: number, ProductId: number } } = PACK_FALLBACK
	local productPrice: { [number]: number } = {} -- GetProductInfo cache
	local shopStateRemote: RemoteFunction? = nil

	-- remember the open tab across close/reopen, mirroring goals.tab; the key
	-- is created here because the shell's state table predates this panel.
	ctx.state.shop = ctx.state.shop or { tab = "Passes" }
	local activeTab: string = (ctx.state.shop.tab == "Darrels") and "Darrels" or "Passes"

	----------------------------------------------------------- root
	local wrapper = Instance.new("Frame")
	wrapper.Name = "ShopPanel"
	wrapper.Size = UDim2.fromScale(1, 1)
	wrapper.BackgroundTransparency = 1
	wrapper.ZIndex = 10

	local panelCol = Instance.new("Frame")
	panelCol.Name = "PanelColumn"
	panelCol.AnchorPoint = Vector2.new(0.5, 0.5)
	panelCol.Position = UDim2.fromScale(0.5, 0.5)
	panelCol.Size = UDim2.fromOffset(PANEL_W, GROUP_H)
	panelCol.BackgroundTransparency = 1
	panelCol.ZIndex = 10
	panelCol.Parent = wrapper

	----------------------------------------------------------- header (common shell, README §3) -- gold, money surface
	local header = UI.surface(panelCol, UDim2.fromOffset(PANEL_W, HEADER_H), "gold", T.radius.panel, T.stroke.panel)
	header.Name = "Header"
	header.Position = UDim2.fromOffset(0, 0)
	header.ZIndex = 12
	UI.gloss(header, T.radius.panel)
	UI.hardShadow(header, T.shadowOffset.panel, T.radius.panel)

	local iconPlate = UI.surface(header, UDim2.fromOffset(62, 62), "goldSmall", T.radius.small, T.stroke.control)
	iconPlate.Name = "SectionIconPlate"
	iconPlate.AnchorPoint = Vector2.new(0, 0.5)
	iconPlate.Position = UDim2.new(0, 12, 0.5, 0)
	iconPlate.ZIndex = header.ZIndex + 1
	UI.gloss(iconPlate, T.radius.small)

	-- the kit's own "shops" vector art; money-bag glyph (render-proven, see
	-- GameHUDClient's GLYPH table) only if IconArt is missing entirely
	local headerArt = IconArt and IconArt.has("shops")
		and IconArt.draw(iconPlate, "shops", 48, iconPlate.ZIndex + 2)
		or nil
	if headerArt then
		headerArt.AnchorPoint = Vector2.new(0.5, 0.5)
		headerArt.Position = UDim2.fromScale(0.5, 0.5)
	else
		local glyph = Instance.new("TextLabel")
		glyph.Name = "SectionGlyph"
		glyph.BackgroundTransparency = 1
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.Text = "\u{1F4B0}"
		glyph.TextSize = 34
		glyph.TextXAlignment = Enum.TextXAlignment.Center
		glyph.TextYAlignment = Enum.TextYAlignment.Center
		-- default face on purpose: FredokaOne has no emoji glyphs
		glyph.ZIndex = iconPlate.ZIndex + 2
		glyph:SetAttribute("NoPolish", true)
		glyph.Parent = iconPlate
	end

	local headerTitle = UI.label(header, "Shop", "panelTitle", T.color.white)
	headerTitle.Name = "Title"
	headerTitle.AnchorPoint = Vector2.new(0, 0.5)
	headerTitle.Position = UDim2.new(0, 12 + 62 + 14, 0.5, 0)
	headerTitle.ZIndex = header.ZIndex + 2

	local closeBtn = UI.button(header, "X", "red", UDim2.fromOffset(T.size.closeButton.X, T.size.closeButton.Y), "buttonL")
	closeBtn.Name = "CloseButton"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -12, 0.5, 0)
	closeBtn.ZIndex = header.ZIndex + 2

	----------------------------------------------------------- body (common shell, README §3)
	local body = UI.panel(panelCol, UDim2.fromOffset(PANEL_W, BODY_H)) -- UI.panel adds the 16px UIPadding all layout below is measured against
	body.Name = "Body"
	body.Position = UDim2.fromOffset(0, BODY_TOP)
	body.ZIndex = 12

	----------------------------------------------------------- tabs (GoalsPanel pattern, two-wide)
	local TAB_DEFS = { "Passes", "Darrels" }
	local tabsRow = Instance.new("Frame")
	tabsRow.Name = "Tabs"
	tabsRow.Position = UDim2.fromOffset(0, 0)
	tabsRow.Size = UDim2.new(1, 0, 0, TAB_H)
	tabsRow.BackgroundTransparency = 1
	tabsRow.ZIndex = 14
	tabsRow.Parent = body

	local tabButtons: { [string]: TextButton } = {}
	local tabRings: { [string]: Frame } = {}

	for i, id in ipairs(TAB_DEFS) do
		local btn = UI.button(tabsRow, id, "tab", UDim2.fromOffset(TAB_W, TAB_H), "buttonM")
		btn.Name = "Tab" .. id
		btn.Position = UDim2.fromOffset((i - 1) * (TAB_W + TAB_GAP), 0)
		btn.ZIndex = 14
		tabButtons[id] = btn

		-- static active-state gold ring (GoalsPanel convention: claimRing's
		-- inset/radius, NO pulse -- selection indicator, not an affordance)
		local ring = Instance.new("Frame")
		ring.Name = "ActiveRing"
		ring.Size = UDim2.new(1, 8, 1, 8)
		ring.Position = UDim2.fromOffset(-4, -4)
		ring.BackgroundTransparency = 1
		ring.Visible = false
		ring.ZIndex = btn.ZIndex + 3
		ring.Parent = btn
		UI.corner(ring, T.radius.control + 3)
		local ringStroke = Instance.new("UIStroke")
		ringStroke.Thickness = 4
		ringStroke.Color = T.color.activeRing
		ringStroke.Parent = ring
		tabRings[id] = ring
	end

	----------------------------------------------------------- tab content hosts
	-- Two persistent frames toggled by tab, rebuilt in place on data refresh.
	local passScroll = Instance.new("ScrollingFrame")
	passScroll.Name = "PassRows"
	passScroll.Position = UDim2.fromOffset(0, TAB_H + CONTENT_GAP)
	passScroll.Size = UDim2.new(1, 0, 0, CONTENT_H)
	passScroll.BackgroundTransparency = 1
	passScroll.BorderSizePixel = 0
	passScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	passScroll.ScrollBarThickness = 10
	passScroll.ScrollBarImageColor3 = T.color.scrollThumb
	passScroll.CanvasSize = UDim2.new()
	passScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	passScroll.ElasticBehavior = Enum.ElasticBehavior.Never
	passScroll.ZIndex = 14
	passScroll.Parent = body

	local passList = Instance.new("UIListLayout")
	passList.FillDirection = Enum.FillDirection.Vertical
	passList.SortOrder = Enum.SortOrder.LayoutOrder
	passList.Padding = UDim.new(0, ROW_GAP)
	passList.Parent = passScroll

	local darrelContent = Instance.new("Frame")
	darrelContent.Name = "DarrelCards"
	darrelContent.Position = UDim2.fromOffset(0, TAB_H + CONTENT_GAP)
	darrelContent.Size = UDim2.new(1, 0, 0, CONTENT_H)
	darrelContent.BackgroundTransparency = 1
	darrelContent.ZIndex = 14
	darrelContent.Parent = body

	----------------------------------------------------------- shared bits
	local function clearGui(container: Instance)
		-- rows/cards (and their hardShadow siblings) are all GuiObjects; the
		-- UIListLayout survives, PassPanel's clearRow convention
		for _, c in ipairs(container:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
	end

	local function centreLabel(l: TextLabel, parentZ: number)
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = UDim2.fromScale(0.5, 0.5)
		l.Size = UDim2.fromScale(1, 1)
		l.AutomaticSize = Enum.AutomaticSize.None
		l.TextXAlignment = Enum.TextXAlignment.Center
		l.ZIndex = parentZ + 2
	end

	----------------------------------------------------------- Passes tab
	local function renderPasses()
		clearGui(passScroll)
		for i, g in ipairs(GamepassConfig.List) do
			local row = UI.surface(passScroll, UDim2.new(1, -12, 0, ROW_H), "row", T.radius.control, T.stroke.control)
			row.Name = "PassRow" .. g.Key
			row.LayoutOrder = i
			row.ZIndex = 15

			local plate = UI.surface(row, UDim2.fromOffset(ICON_W, ICON_W), "slot", T.radius.small, T.stroke.control)
			plate.Name = "IconPlate"
			plate.AnchorPoint = Vector2.new(0, 0.5)
			plate.Position = UDim2.new(0, ROW_PAD_X, 0.5, 0)
			plate.ZIndex = row.ZIndex + 1

			local glyph = Instance.new("TextLabel")
			glyph.Name = "IconGlyph"
			glyph.BackgroundTransparency = 1
			glyph.Size = UDim2.fromScale(1, 1)
			glyph.Text = g.Icon or "?"
			glyph.TextSize = 32
			glyph.TextXAlignment = Enum.TextXAlignment.Center
			glyph.TextYAlignment = Enum.TextYAlignment.Center
			-- default face on purpose (emoji); NoPolish per rail convention
			glyph.ZIndex = plate.ZIndex + 2
			glyph:SetAttribute("NoPolish", true)
			glyph.Parent = plate

			local name = UI.label(row, g.Name, "value", T.color.white)
			name.Name = "NameLabel"
			name.Position = UDim2.fromOffset(TEXT_X, 12)
			name.ZIndex = row.ZIndex + 2

			local desc = UI.label(row, g.Desc, "meta", T.color.textMuted)
			desc.Name = "DescLabel"
			desc.Position = UDim2.fromOffset(TEXT_X, 52)
			desc.Size = UDim2.new(1, -(TEXT_X + ACTION_W + ROW_PAD_X + 12), 0, 18)
			desc.AutomaticSize = Enum.AutomaticSize.None
			desc.TextTruncate = Enum.TextTruncate.AtEnd
			desc.ZIndex = row.ZIndex + 2

			if owned[g.Key] then
				-- OWNED: a dead surface, not a button -- inherently unclickable
				-- (T.gradient.ownedCta is the kit's own owned-CTA treatment)
				local chip = UI.surface(row, UDim2.fromOffset(ACTION_W, ACTION_H), "ownedCta", T.radius.control, T.stroke.control)
				chip.Name = "OwnedChip"
				chip.AnchorPoint = Vector2.new(1, 0.5)
				chip.Position = UDim2.new(1, -ROW_PAD_X, 0.5, 0)
				chip.ZIndex = row.ZIndex + 1
				UI.gloss(chip, T.radius.control)
				local lbl = UI.label(chip, "\u{2713} OWNED", "buttonM", T.color.white)
				lbl.Name = "OwnedLabel"
				centreLabel(lbl, chip.ZIndex)
			elseif g.GamepassId > 0 then
				local btn = UI.button(row, "R$ " .. tostring(g.RobuxPrice), "green", UDim2.fromOffset(ACTION_W, ACTION_H), "buttonM")
				btn.Name = "BuyButton"
				btn.AnchorPoint = Vector2.new(1, 0.5)
				btn.Position = UDim2.new(1, -ROW_PAD_X, 0.5, 0)
				btn.ZIndex = row.ZIndex + 1
				-- The ONE PromptGamePassPurchase call site in this module.
				-- Click-time re-check: the row may be stale (bought in another
				-- window, id zeroed by a hot-edit) -- never trust the render.
				btn.MouseButton1Click:Connect(function()
					if g.GamepassId > 0 and not owned[g.Key] then
						MarketplaceService:PromptGamePassPurchase(player, g.GamepassId)
					end
				end)
			else
				-- GamepassId == 0: COMING SOON, and NEVER a purchase prompt.
				-- "disabled" variant is Active=false with no click sfx, and no
				-- handler is connected here -- there is nothing to fire.
				local btn = UI.button(row, "COMING SOON", "disabled", UDim2.fromOffset(ACTION_W, ACTION_H), "buttonM")
				btn.Name = "ComingSoonButton"
				btn.AnchorPoint = Vector2.new(1, 0.5)
				btn.Position = UDim2.new(1, -ROW_PAD_X, 0.5, 0)
				btn.ZIndex = row.ZIndex + 1
			end
		end
	end

	----------------------------------------------------------- Darrels tab
	local function renderPacks()
		clearGui(darrelContent)
		local totalW = #packs * CARD_W + math.max(#packs - 1, 0) * CARD_GAP
		local x0 = math.max(math.floor((BODY_INNER_W - totalW) / 2), 0)
		for i, pack in ipairs(packs) do
			-- hand-positioned (no UIListLayout) so UI.hardShadow's sibling
			-- shadow can't corrupt a layout -- see PassPanel's slot-wrapper
			-- comment for the failure mode this sidesteps
			local card = UI.surface(darrelContent, UDim2.fromOffset(CARD_W, CARD_H), "freeCard", T.radius.control, T.stroke.control)
			card.Name = "PackCard" .. tostring(pack.Amount)
			card.Position = UDim2.fromOffset(x0 + (i - 1) * (CARD_W + CARD_GAP), CARDS_Y)
			card.ZIndex = 15
			UI.hardShadow(card, T.shadowOffset.control, T.radius.control)

			local amount = UI.label(card, tostring(pack.Amount), "buttonL", T.color.textOnLight)
			amount.Name = "AmountLabel"
			amount.AnchorPoint = Vector2.new(0.5, 0)
			amount.Position = UDim2.new(0.5, 0, 0, 12)
			amount.Size = UDim2.new(1, -16, 0, 34)
			amount.AutomaticSize = Enum.AutomaticSize.None
			amount.TextXAlignment = Enum.TextXAlignment.Center
			amount.ZIndex = card.ZIndex + 2

			local unit = UI.label(card, "DARRELS", "cardLabel", T.color.textOnLight)
			unit.Name = "UnitLabel"
			unit.AnchorPoint = Vector2.new(0.5, 0)
			unit.Position = UDim2.new(0.5, 0, 0, 48)
			unit.Size = UDim2.new(1, -16, 0, 22)
			unit.AutomaticSize = Enum.AutomaticSize.None
			unit.TextXAlignment = Enum.TextXAlignment.Center
			unit.ZIndex = card.ZIndex + 2

			local artHost = Instance.new("Frame")
			artHost.Name = "ArtHost"
			artHost.AnchorPoint = Vector2.new(0.5, 0)
			artHost.Position = UDim2.new(0.5, 0, 0, 82)
			artHost.Size = UDim2.fromOffset(116, 116)
			artHost.BackgroundTransparency = 1
			artHost.ZIndex = card.ZIndex + 1
			artHost.Parent = card
			local face = IconArt and IconArt.has("darrel")
				and IconArt.draw(artHost, "darrel", 116, artHost.ZIndex)
				or nil
			if not face then
				local glyph = Instance.new("TextLabel")
				glyph.Name = "Glyph"
				glyph.BackgroundTransparency = 1
				glyph.Size = UDim2.fromScale(1, 1)
				glyph.Text = "\u{1F48E}" -- Darrel's pre-face diamond stand-in
				glyph.TextSize = 64
				glyph.TextXAlignment = Enum.TextXAlignment.Center
				glyph.TextYAlignment = Enum.TextYAlignment.Center
				glyph.ZIndex = artHost.ZIndex + 1
				glyph:SetAttribute("NoPolish", true)
				glyph.Parent = artHost
			end

			if pack.ProductId > 0 then
				local cached = productPrice[pack.ProductId]
				local btn = UI.button(card, cached and ("R$ " .. tostring(cached)) or "BUY", "green",
					UDim2.fromOffset(CARD_W - 26, 54), "buttonM")
				btn.Name = "BuyButton"
				btn.AnchorPoint = Vector2.new(0.5, 1)
				btn.Position = UDim2.new(0.5, 0, 1, -12)
				btn.ZIndex = card.ZIndex + 1
				-- The ONE PromptProductPurchase call site in this module.
				btn.MouseButton1Click:Connect(function()
					if pack.ProductId > 0 then
						MarketplaceService:PromptProductPurchase(player, pack.ProductId)
					end
				end)
				if not cached then
					-- dev-product price lives on the dashboard, not in any
					-- config -- fetch once, cache, retarget the live label
					task.spawn(function()
						local ok, info = pcall(function()
							return MarketplaceService:GetProductInfo(pack.ProductId, Enum.InfoType.Product)
						end)
						if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
							productPrice[pack.ProductId] = info.PriceInRobux
							if btn.Parent then
								local lbl = btn:FindFirstChildOfClass("TextLabel")
								if lbl then
									lbl.Text = "R$ " .. tostring(info.PriceInRobux)
								end
							end
						end
					end)
				end
			else
				-- ProductId == 0: COMING SOON, no connection, no prompt -- ever
				local btn = UI.button(card, "COMING SOON", "disabled", UDim2.fromOffset(CARD_W - 26, 54), "buttonM")
				btn.Name = "ComingSoonButton"
				btn.AnchorPoint = Vector2.new(0.5, 1)
				btn.Position = UDim2.new(0.5, 0, 1, -12)
				btn.ZIndex = card.ZIndex + 1
			end

			if i == #packs and #packs > 1 then
				local ribbon = UI.ribbon(card, "BEST VALUE", "GRAND")
				ribbon.AnchorPoint = Vector2.new(0.5, 0.5)
				ribbon.Position = UDim2.new(0.5, 0, 0, 0)
				ribbon.ZIndex = card.ZIndex + 6
			end
		end

		local caption = UI.label(darrelContent, "Darrels are spent on eggs at the Forest Egg Shop", "meta", T.color.textMuted)
		caption.Name = "Caption"
		caption.AnchorPoint = Vector2.new(0.5, 0)
		caption.Position = UDim2.new(0.5, 0, 0, CARDS_Y + CARD_H + 24)
		caption.Size = UDim2.new(1, 0, 0, 18)
		caption.AutomaticSize = Enum.AutomaticSize.None
		caption.TextXAlignment = Enum.TextXAlignment.Center
		caption.ZIndex = 14
	end

	----------------------------------------------------------- tab switching
	local function applyTab()
		passScroll.Visible = (activeTab == "Passes")
		darrelContent.Visible = (activeTab == "Darrels")
		for id, ring in pairs(tabRings) do
			ring.Visible = (id == activeTab)
		end
	end

	local function setTab(id: string)
		if activeTab == id then
			return
		end
		activeTab = id
		ctx.state.shop.tab = id
		applyTab()
	end

	----------------------------------------------------------- data refresh
	-- ShopState if it exists (server truth for ownership + real pack ids);
	-- otherwise the documented client-only fallback. Yields -- always called
	-- from a spawned thread, single-flighted so an open-spam can't stack
	-- invokes.
	local refreshing = false
	local function refresh()
		if refreshing then
			return
		end
		refreshing = true
		local remote = shopStateRemote
		if remote then
			local ok, res = pcall(function()
				return remote:InvokeServer()
			end)
			if ok and typeof(res) == "table" then
				if typeof(res.Owned) == "table" then
					local set: { [string]: boolean } = {}
					for k, v in pairs(res.Owned) do
						if typeof(k) == "string" and v == true then
							set[k] = true
						end
					end
					owned = set
				end
				if typeof(res.Packs) == "table" then
					local list = {}
					for _, p in ipairs(res.Packs) do
						if typeof(p) == "table" and typeof(p.Amount) == "number" and typeof(p.ProductId) == "number" then
							table.insert(list, { Amount = p.Amount, ProductId = p.ProductId })
						end
					end
					if #list > 0 then
						packs = list
					end
				end
			end
		else
			-- fallback: ask Roblox directly, but only about passes that exist
			-- (GamepassId > 0 -- zero calls in today's all-zero build), pcall'd
			-- exactly like GamepassService.refresh server-side
			for _, g in ipairs(GamepassConfig.List) do
				if g.GamepassId > 0 and not owned[g.Key] then
					local ok, has = pcall(function()
						return MarketplaceService:UserOwnsGamePassAsync(player.UserId, g.GamepassId)
					end)
					if ok and has == true then
						owned[g.Key] = true
					end
				end
			end
		end
		refreshing = false
		renderPasses()
		renderPacks()
	end

	----------------------------------------------------------- wiring
	closeBtn.MouseButton1Click:Connect(function()
		ctx.closePanel()
	end)
	for id, btn in pairs(tabButtons) do
		btn.MouseButton1Click:Connect(function()
			setTab(id)
		end)
	end

	-- Mid-session purchase: flip owned locally on the client's own
	-- wasPurchased signal -- the one sanctioned non-server write, mirroring
	-- GamepassService.Init's identical cache update. (ByGamepassId can only
	-- match a REAL id here: the event never fires with 0, and 0-id configs
	-- are additionally excluded by the > 0 guard.)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, gamepassId, wasPurchased)
		if plr ~= player or not wasPurchased then
			return
		end
		local g = GamepassConfig.ByGamepassId(gamepassId)
		if g and g.GamepassId > 0 then
			owned[g.Key] = true
			renderPasses()
		end
	end)

	-- Bounded remote resolution (SettingsPanel/ToastClient convention), in its
	-- own thread so the lazy Build -- which runs inside openPanel -- never
	-- stalls the first open. ShopState does not exist in this build; when the
	-- proposed server patch lands, this picks it up with no client edit.
	task.spawn(function()
		local inst = ctx.remotes:WaitForChild("ShopState", 5)
		if inst and inst:IsA("RemoteFunction") then
			shopStateRemote = inst
			refresh()
		end
	end)

	-- Re-check ownership/packs every time the panel becomes visible (mirrors
	-- PassPanel's open-time SeasonState refresh) -- covers the very first open
	-- and every reopen after a purchase elsewhere.
	wrapper:GetPropertyChangedSignal("Visible"):Connect(function()
		if wrapper.Visible then
			task.spawn(refresh)
		end
	end)

	applyTab()
	renderPasses() -- initial paint from GamepassConfig + the pack mirror:
	renderPacks() -- correct TODAY (everything id-0 -> COMING SOON) with no server round trip

	return wrapper
end

return ShopPanel
