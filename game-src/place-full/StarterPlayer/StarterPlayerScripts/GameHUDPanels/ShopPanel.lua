-- ShopPanel: the Robux shop -- a GameHUDPanels consumer module.
--
-- Two sections, both read from the SHARED catalogs so a price shown here is the
-- same row the server registers: GamepassConfig (7 passes) and EmeraldPackConfig
-- (4 emerald packs).
--
-- AN ITEM WHOSE ID IS STILL 0 IS NOT FOR SALE. Both catalogs ship with every id at
-- 0 -- the "not created yet" sentinel -- and such a row renders as COMING SOON with
-- no button rather than a BUY that takes a click and does nothing. Filling a real
-- id into the config is the single act that puts an item on sale; nothing here
-- needs editing for that.
--
-- >>> BEFORE FILLING IN ANY PASS ID <<<
-- The pass EFFECTS are not wired into gameplay yet: GamepassService exposes
-- CashMult / LuckMult / PowerMult / ChargeMult / HasFlag and, as of writing,
-- nothing calls them. Six of the seven passes would therefore take Robux and do
-- nothing. Wire the effects first, then create the passes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Mods = ReplicatedStorage:WaitForChild("Modules")
local GamepassConfig = require(Mods:WaitForChild("GamepassConfig"))
local EmeraldPackConfig = require(Mods:WaitForChild("EmeraldPackConfig"))
-- Emerald's drawn face, for the pack cards. He is not part of the UI kit, so there is no
-- Tokens.icons entry and an artSlot would render an empty box -- same reason GoalsPanel
-- reaches for this module. pcall'd so a missing module costs an icon, not the panel.
local okIconArt, IconArt = pcall(function() return require(Mods.UIKit.IconArt) end)
if not okIconArt then IconArt = nil end

local ShopPanel = { Id = "shop" }

-- module-top-level capture, same race every other panel has: Build is lazy, the
-- server's ownership push is not
local remotesTop = ReplicatedStorage:WaitForChild("Remotes")
local capturedState = nil
local liveCallbacks: { (any) -> () } = {}
do
	local r = remotesTop:WaitForChild("ShopState", 30)
	if r then
		r.OnClientEvent:Connect(function(s)
			if typeof(s) ~= "table" then return end
			capturedState = s
			for _, cb in ipairs(liveCallbacks) do cb(s) end
		end)
	end
end

local ROBUX = "\u{E002}"   -- Roblox's own R$ glyph; renders in the default font

-- 2026-08-09 HUD upgrade (design_handoff_hud_upgrade): the shop wears the
-- sheet's PanelChrome shell -- 1180x830, yellow header, TWO columns (gap 14),
-- 128-tall product rows, 84 icon tiles. The price plate stacks the number
-- over the state INSIDE one plate ("SOON must not float loose beside the
-- number as it does now"), and BEST VALUE is a rotated corner ribbon.
-- Two families, two fills: gamepasses on white, emerald packs on violet tint
-- -- sorted by eye, not by reading. Catalogs, live/owned rules and the
-- ShopPrompt wiring are untouched.
local UIKit = Mods:WaitForChild("UIKit")
local PC = require(UIKit:WaitForChild("PanelChrome"))
local S = require(UIKit:WaitForChild("SpecTheme"))

function ShopPanel.Build(ctx)
	local ROW_H, ROW_RADIUS, GAP = 128, 24, 14
	local ICON = 84
	local PRICE_W, PRICE_H = 150, 78
	local STATE_INK = Color3.new(1, 1, 1) -- SOON reads white on the grey-blue Inert plate, same as OWNED

	local state = { Owned = {} }

	local shell = PC.shell({
		name = "ShopPanel",
		title = "SHOP",
		key = "shop",
		icon = S.Art.shop, -- PS99 restyle: rail sticker in the header
		size = S.ShellFor.shop,
		scroll = true,
	})
	shell.list.Padding = UDim.new(0, GAP)
	shell.close.Activated:Connect(function()
		if ctx.closePanel then ctx.closePanel() end
	end)

	local order = 0
	local function nextOrder() order += 1 return order end

	-- two per row: eleven items must not become an eleven-screen scroll
	local function pairRow()
		local r = Instance.new("Frame")
		r.Name = "PairRow" .. nextOrder()
		r.LayoutOrder = order
		r.Size = UDim2.new(1, 0, 0, ROW_H)
		r.BackgroundTransparency = 1
		r.ZIndex = shell.z + 2
		r.Parent = shell.body
		local l = Instance.new("UIListLayout")
		l.FillDirection = Enum.FillDirection.Horizontal
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Padding = UDim.new(0, GAP)
		l.Parent = r
		return r
	end

	local cards = {}   -- ("pass"|"pack") .. Key -> paint handles

	-- `live` is the ONLY thing that decides whether an item is buyable, and it
	-- is the id being real -- never the price, the name, or anything a client
	-- sends. The plate carries number over state in ONE plate; only the plate
	-- colour and the word change between live / SOON / OWNED.
	local function buildCard(parent, slotOrder, kind, key, glyph, name, desc, price, live, best, violet)
		local z = shell.z + 3
		-- PS99 sticker treatment: interior icons run big and tilted like the rail's.
		-- Alternating per slot so a row of cards doesn't lean in formation.
		local tilt = (slotOrder % 2 == 0) and -6 or 5
		local card = PC.plate({
			name = kind .. key,
			size = UDim2.new(0.5, -math.ceil(GAP / 2), 1, 0),
			colors = violet and S.Action.VioletRow or { S.Surface.RowTop, S.Surface.RowBottom },
			radius = ROW_RADIUS,
			outline = 6,
			strokeColor = S.OutlineSoft, -- PS99: interior cards wear the soft edge
			zIndex = z,
			parent = parent,
			gloss = false,
		})
		card.LayoutOrder = slotOrder
		card.ClipsDescendants = false

		local tile = PC.plate({
			name = "IconTile",
			size = UDim2.fromOffset(ICON, ICON),
			position = UDim2.new(0, 16, 0.5, 0),
			anchor = Vector2.new(0, 0.5),
			colors = violet and { Color3.fromHex("E9D5FF"), Color3.fromHex("C9A6EE") }
				or { Color3.fromHex("BFD6EC"), Color3.fromHex("8FB2D4") },
			radius = 22,
			outline = 5,
			strokeColor = S.OutlineSoft, -- PS99: soft edge on the icon tile too
			zIndex = z + 1,
			parent = card,
		})
		tile.ClipsDescendants = false -- the sticker overhang must show past the tile edge
		-- SCROLL-MASK FIX (2026-08-18): the engine NEVER clips a rotated
		-- GuiObject, so the tilted glyphs sailed over the white title band when
		-- the list scrolled, while their unrotated cards clipped fine. The tilt
		-- now lives inside this NON-rotated CanvasGroup: the rotation is
		-- rasterized into the group's own rect, which the body ScrollingFrame
		-- clips like any plain frame. Sized past the tile (an 88px square at
		-- ~6 degrees needs ~97px) so the sticker overhang still shows -- but
		-- only INSIDE the scroll area.
		local sticker = Instance.new("CanvasGroup")
		sticker.Name = "Sticker"
		sticker.BackgroundTransparency = 1
		sticker.BorderSizePixel = 0
		sticker.Size = UDim2.fromOffset(ICON + 16, ICON + 16)
		sticker.Position = UDim2.fromScale(0.5, 0.5)
		sticker.AnchorPoint = Vector2.new(0.5, 0.5)
		sticker.ZIndex = z + 2
		sticker.Parent = tile
		-- THE CURRENCY WEARS ITS OWN FACE. Emerald packs draw Emerald himself
		-- (UIKit.IconArt), the same face the HUD counter keeps; passes keep
		-- their config emoji.
		if glyph == nil and IconArt and IconArt.has("emerald") then
			local slot = Instance.new("Frame")
			slot.Name = "Face"
			slot.BackgroundTransparency = 1
			slot.Size = UDim2.fromOffset(ICON + 4, ICON + 4) -- sticker: face runs a touch past the tile
			slot.Rotation = tilt -- drawn primitives rotate with their slot, inside the sticker canvas
			slot.Position = UDim2.fromScale(0.5, 0.5)
			slot.AnchorPoint = Vector2.new(0.5, 0.5)
			slot.ZIndex = z + 2
			slot.Parent = sticker
			IconArt.draw(slot, "emerald", ICON + 4, z + 2)
		else
			local g = PC.shout({
				name = "Glyph", text = glyph or "\u{1F48E}", size = 48,
				zIndex = z + 2, parent = sticker,
			})
			g.TextScaled = true
			-- offset, not scale: the sticker canvas is wider than the tile, so
			-- 1.05x of IT would balloon; 88px keeps the old 84*1.05 footprint
			g.Size = UDim2.fromOffset(ICON + 4, ICON + 4) -- sticker: run just past the tile edge
			g.Position = UDim2.fromScale(0.5, 0.5)
			g.AnchorPoint = Vector2.new(0.5, 0.5)
			g.Rotation = tilt
		end

		local textX = 16 + ICON + 14
		local textW = -(textX + PRICE_W + 34)
		PC.read({
			name = "Name",
			text = name,
			size = 26,
			frameSize = UDim2.new(1, textW, 0, 30),
			position = UDim2.new(0, textX, 0.5, -22),
			anchor = Vector2.new(0, 0.5),
			zIndex = z + 1,
			parent = card,
		})
		PC.read({
			name = "Desc",
			text = desc,
			size = 18,
			color = violet and Color3.fromHex("6B4E8C") or S.Surface.ReadSub,
			frameSize = UDim2.new(1, textW, 0, 44),
			position = UDim2.new(0, textX, 0.5, 14),
			anchor = Vector2.new(0, 0.5),
			zIndex = z + 1,
			parent = card,
			wrap = true,
		})

		-- price plate: number stacked over state, one plate
		local function platePaint(plate, numberLabel, stateLabel, mode)
			local grad = plate:FindFirstChildOfClass("UIGradient")
			-- PS99 gold inversion fix (2026-08-17): Robux prices are GOLD -- gold
			-- means real money and nothing else. Green was backwards (green = free
			-- in-game act) and inverted the whole game's money grammar.
			local c = mode == "live" and S.Action.Robux or S.Action.Inert
			-- BackgroundColor3 must move WITH the gradient: UIGradient MULTIPLIES the
			-- background colour (mirrors PanelChrome.addHeaderTabs' repaint), so an
			-- Inert gradient over the Go-green base rendered OWNED plates green-grey
			plate.BackgroundColor3 = c[1]
			if grad then grad.Color = ColorSequence.new(c[1], c[2]) end
			if mode == "live" then
				numberLabel.Position = UDim2.fromOffset(0, 0)
				numberLabel.Size = UDim2.fromScale(1, 1)
				stateLabel.Visible = false
			else
				numberLabel.Position = UDim2.fromOffset(0, -12)
				numberLabel.Size = UDim2.new(1, 0, 1, 0)
				stateLabel.Visible = true
				stateLabel.Text = mode == "owned" and "OWNED" or "SOON"
				stateLabel.TextColor3 = mode == "owned" and Color3.new(1, 1, 1) or STATE_INK
			end
		end

		local plate
		if live then
			plate = PC.pill({
				name = "PricePlate",
				text = "",
				colors = S.Action.Robux, -- gold = real money (see platePaint)
				size = UDim2.fromOffset(PRICE_W, PRICE_H),
				position = UDim2.new(1, -16, 0.5, 0),
				anchor = Vector2.new(1, 0.5),
				zIndex = z + 1,
				parent = card,
			})
			plate.Activated:Connect(function()
				local r = ctx.remotes:FindFirstChild("ShopPrompt")
				if r then r:FireServer(kind, key) end
			end)
			plate:FindFirstChild("Label"):Destroy() -- number/state pair below instead
		else
			plate = PC.plate({
				name = "PricePlate",
				size = UDim2.fromOffset(PRICE_W, PRICE_H),
				position = UDim2.new(1, -16, 0.5, 0),
				anchor = Vector2.new(1, 0.5),
				colors = S.Action.Inert,
				radius = 22,
				outline = 6,
				zIndex = z + 1,
				parent = card,
			})
		end
		local number = PC.shout({
			name = "PriceNumber",
			text = ROBUX .. tostring(price),
			size = 30,
			zIndex = z + 3,
			parent = plate,
			scaled = true,
		})
		number.Size = UDim2.new(0.9, 0, 0, 34)
		number.Position = UDim2.new(0.05, 0, 0, 6)
		local stateWord = PC.shout({
			name = "PriceState",
			text = "SOON",
			size = 17,
			color = STATE_INK,
			zIndex = z + 3,
			parent = plate,
		})
		stateWord.Size = UDim2.new(1, 0, 0, 20)
		stateWord.Position = UDim2.new(0, 0, 1, -26)
		platePaint(plate, number, stateWord, live and "live" or "soon")

		-- BEST VALUE: a rotated corner ribbon, not a caption above the row.
		-- Same rotation-escapes-clipping leak as the glyphs (PC.ribbon rotates
		-- its whole frame 12 degrees), so it too rides inside a non-rotated
		-- CanvasGroup the scroll mask can clip. The holder covers the ribbon's
		-- rotated bounds (190x40 at 12 degrees ~ 195x79) and its centre sits
		-- where the ribbon's used to: straddling the card's top-right corner.
		if best then
			local rHold = Instance.new("CanvasGroup")
			rHold.Name = "RibbonHold"
			rHold.BackgroundTransparency = 1
			rHold.BorderSizePixel = 0
			rHold.Size = UDim2.fromOffset(200, 84)
			rHold.Position = UDim2.new(1, 8, 0, 12) -- the ribbon's old centre
			rHold.AnchorPoint = Vector2.new(0.5, 0.5)
			rHold.ZIndex = z + 5
			rHold.Parent = card
			local rb = PC.ribbon({ text = "BEST VALUE", parent = rHold, zIndex = z + 5 })
			rb.Position = UDim2.fromScale(0.5, 0.5) -- centred; the holder carries the old offset
		end

		cards[kind .. key] = {
			plate = plate, number = number, stateWord = stateWord,
			platePaint = platePaint, live = live,
		}
	end

	----------------------------------------------------------- passes
	PC.sectionHead({ text = "PASSES", parent = shell.body, layoutOrder = nextOrder(), zIndex = shell.z + 2 })
	do
		local row
		for i, g in ipairs(GamepassConfig.List) do
			if (i - 1) % 2 == 0 then row = pairRow() end
			buildCard(row, i, "pass", g.Key, g.Icon, g.Name, g.Desc, g.RobuxPrice,
				(g.GamepassId or 0) > 0, false, false)
		end
	end

	----------------------------------------------------------- emeralds
	-- the currency is GEMS to the player (2026-09-18); EmeraldPackConfig keeps its
	-- internal name -- Emerald is the NPC who sells them
	PC.sectionHead({ text = "GEMS", parent = shell.body, layoutOrder = nextOrder(), zIndex = shell.z + 2 })
	do
		local row
		for i, p in ipairs(EmeraldPackConfig.List) do
			if (i - 1) % 2 == 0 then row = pairRow() end
			-- nil glyph = Emerald's own face; see buildCard
			buildCard(row, i, "pack", p.Key, nil, p.Name,
				("%d Gems"):format(p.Amount), p.RobuxPrice,
				EmeraldPackConfig.IsLive(p), p.Best == true, true)
		end
	end

	----------------------------------------------------------- paint
	local function render()
		for _, g in ipairs(GamepassConfig.List) do
			local c = cards["pass" .. g.Key]
			if c then
				if state.Owned[g.Key] then
					c.platePaint(c.plate, c.number, c.stateWord, "owned")
				elseif c.live then
					c.platePaint(c.plate, c.number, c.stateWord, "live")
				end
				-- a not-live card is left exactly as built: price over SOON
			end
		end
	end

	local function applyServerState(s2)
		if typeof(s2) ~= "table" then return end
		if typeof(s2.Owned) == "table" then state.Owned = s2.Owned end
		render()
	end

	if capturedState then applyServerState(capturedState) end
	table.insert(liveCallbacks, applyServerState)

	render()
	return shell.root
end

return ShopPanel
