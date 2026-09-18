--!strict
-- GalleryPanel -- STUDIO-ONLY living style guide (spec 2026-09-18 UI foundation
-- §10). Every kit component in every state, the BrainrotCard ladder, the framing
-- extremes with their measured fill, and a stress grid on the culler that SETS
-- S.Card.MaxLive per platform. Everything here is built from S + the components --
-- no bespoke styling -- so what the Gallery shows IS the design system.
-- Registration: outside Studio this module returns {} and GameHUDClient skips it
-- (documented "not registered here" answer). No rail button; trigger from the
-- client command bar:  game.Players.LocalPlayer:SetAttribute("HudGallery", true)
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return {}
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local modules = ReplicatedStorage:WaitForChild("Modules")
local UIKit = modules:WaitForChild("UIKit")
local S = require(UIKit:WaitForChild("SpecTheme"))
local PC = require(UIKit:WaitForChild("PanelChrome"))
local TabBar = require(UIKit:WaitForChild("TabBar"))
local SearchBar = require(UIKit:WaitForChild("SearchBar"))
local SortButton = require(UIKit:WaitForChild("SortButton"))
local Modal = require(UIKit:WaitForChild("Modal"))
local Toast = require(UIKit:WaitForChild("Toast"))
local BrainrotCard = require(UIKit:WaitForChild("BrainrotCard"))
local ViewportCuller = require(UIKit:WaitForChild("ViewportCuller"))
local FxDriver = require(UIKit:WaitForChild("FxDriver"))
local BrainrotThumb = require(modules:WaitForChild("BrainrotThumb"))
local Platform = require(modules:WaitForChild("Platform"))

local GalleryPanel = { Id = "gallery" }

local SECTIONS = {
	{ id = "tokens", text = "TOKENS" }, { id = "buttons", text = "BUTTONS" }, { id = "shell", text = "SHELL" },
	{ id = "tabs", text = "TABS" }, { id = "inputs", text = "INPUTS" }, { id = "modal", text = "MODAL+TOAST" },
	{ id = "cards", text = "CARDS" }, { id = "stress", text = "STRESS" }, { id = "legacy", text = "LEGACY" },
}
local TIERS = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret", "God" }
local CARD_W, CARD_H = 140, 176

-- roster helpers -------------------------------------------------------------
local function rosterNames(n: number): { string }
	local names = {}
	for _, m in ipairs(ReplicatedStorage:WaitForChild("BrainrotModels"):GetChildren()) do
		if m:IsA("Model") then table.insert(names, m.Name) end
	end
	table.sort(names)
	local out = {}
	for i = 1, math.min(n, #names) do out[i] = names[i] end
	return out
end

-- the framing set: extremes picked by MEASUREMENT so the section never depends on
-- a hand-typed name (tallest, widest, biggest, smallest, palest, darkest)
local function framingSet(): { { label: string, name: string } }
	local best = { tall = -1, wide = -1, big = -1, small = math.huge, pale = -1, dark = math.huge }
	local pick: { [string]: string } = {}
	for _, m in ipairs(ReplicatedStorage.BrainrotModels:GetChildren()) do
		if m:IsA("Model") then
			local ok, errOrCf, ext = pcall(function() return m:GetBoundingBox() end)
			if not ok then
				warn(("[UIKit] Gallery framingSet: GetBoundingBox failed for %s: %s"):format(m.Name, tostring(errOrCf)))
			end
			if ok and ext and ext.Magnitude > 0 then
				local tall, wide, vol = ext.Y / math.max(ext.X, ext.Z), math.max(ext.X, ext.Z) / ext.Y, ext.X * ext.Y * ext.Z
				if tall > best.tall then best.tall = tall; pick.tall = m.Name end
				if wide > best.wide then best.wide = wide; pick.wide = m.Name end
				if vol > best.big then best.big = vol; pick.big = m.Name end
				if vol < best.small then best.small = vol; pick.small = m.Name end
				local master = BrainrotThumb.master(m.Name)
				if master then
					local lum = BrainrotThumb.meanLuminance(master)
					if lum > best.pale then best.pale = lum; pick.pale = m.Name end
					if lum < best.dark then best.dark = lum; pick.dark = m.Name end
				end
			end
		end
	end
	local out = {}
	for _, key in ipairs({ "tall", "wide", "big", "small", "pale", "dark" }) do
		if pick[key] then table.insert(out, { label = key:upper(), name = pick[key] }) end
	end
	return out
end

-- measured fill + off-centre residual for a model at the card's aspect (Task 8 maths)
local function measureFill(name: string, aspect: number): (number, number, number)
	local master = BrainrotThumb.master(name)
	if not master then return 0, 0, 0 end
	local m = master
	local dir = m:GetPivot():VectorToWorldSpace(BrainrotThumb.DEFAULT_DIR)
	local yaw = BrainrotThumb.FACING[name]
	if yaw and yaw ~= 0 then dir = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(yaw)) * dir end
	local fov = 30
	local centre, dist = BrainrotThumb.framingBox(m, fov, { dir = dir, aspect = aspect, fill = S.Card.Fill })
	local look = -dir
	local right = look:Cross(Vector3.yAxis).Unit
	local up = right:Cross(look).Unit
	local tanV = math.tan(math.rad(fov * 0.5)); local tanH = tanV * aspect
	local cf, ext = m:GetBoundingBox()
	local maxAbs, minX, maxX, minY, maxY = 0, math.huge, -math.huge, math.huge, -math.huge
	for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
		local q = cf:PointToWorldSpace(Vector3.new(sx * ext.X / 2, sy * ext.Y / 2, sz * ext.Z / 2))
		local w = q - centre
		local depth = dist - w:Dot(dir)
		local px, py = w:Dot(right) / depth / tanH, w:Dot(up) / depth / tanV
		maxAbs = math.max(maxAbs, math.abs(px), math.abs(py))
		minX, maxX, minY, maxY = math.min(minX, px), math.max(maxX, px), math.min(minY, py), math.max(maxY, py)
	end end end
	return maxAbs, (minX + maxX) / 2, (minY + maxY) / 2
end

-- section helpers ------------------------------------------------------------
local function row(host: Instance, name: string, height: number?, order: number): Frame
	local r = Instance.new("Frame")
	r.Name = name
	r.BackgroundTransparency = 1
	r.Size = UDim2.new(1, 0, 0, height or 0)
	if not height then r.AutomaticSize = Enum.AutomaticSize.Y end
	r.LayoutOrder = order
	r.ZIndex = PC.zBase + 3
	r.Parent = host
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, S.Space.std)
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Wraps = true
	l.Parent = r
	return r
end

local function heading(host: Instance, text: string, order: number)
	PC.sectionHead({ text = text, parent = host, zIndex = PC.zBase + 3, layoutOrder = order })
end

local function caption(parent: Instance, text: string, order: number?): TextLabel
	local l = PC.read({ text = text, size = S.TextSize.Meta, color = S.Surface.ReadSub, parent = parent, frameSize = UDim2.new(0, 0, 0, 28), zIndex = PC.zBase + 3 })
	l.AutomaticSize = Enum.AutomaticSize.X
	if order then l.LayoutOrder = order end
	return l
end

local function cardSlot(parent: Instance, order: number, label: string?): Frame
	-- a fixed cell so cards render at the Bag's proportions
	local holder = Instance.new("Frame")
	holder.Name = "Slot" .. order
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(CARD_W, CARD_H + (label and 26 or 0))
	holder.LayoutOrder = order
	holder.ZIndex = PC.zBase + 3
	holder.Parent = parent
	local cell = Instance.new("Frame")
	cell.Name = "Cell"
	cell.BackgroundTransparency = 1
	cell.Size = UDim2.fromOffset(CARD_W, CARD_H)
	cell.ZIndex = PC.zBase + 3
	cell.Parent = holder
	if label then
		local l = PC.read({ text = label, size = S.TextSize.Chip, color = S.Surface.ReadSub, parent = holder, frameSize = UDim2.new(1, 0, 0, 24), position = UDim2.fromOffset(0, CARD_H + 2), zIndex = PC.zBase + 3 })
		l.TextTruncate = Enum.TextTruncate.AtEnd
	end
	return cell
end

------------------------------------------------------------------------ Build
function GalleryPanel.Build(ctx)
	local shell = PC.shell({
		name = "GalleryPanel", title = "UI GALLERY", key = "settings", size = Vector2.new(1600, 920),
		scroll = false, listLayout = false, icon = S.Art.settings,
		stat = { text = "Studio-only living style guide -- spec 2026-09-18-ui-foundation-design" },
	})
	shell.close.MouseButton1Click:Connect(function()
		if ctx.closePanel then ctx.closePanel() end
	end)
	local z = shell.z

	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Position = UDim2.fromOffset(200, 0)
	content.Size = UDim2.new(1, -200, 1, 0)
	content.CanvasSize = UDim2.new()
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollBarThickness = 5
	content.ScrollBarImageColor3 = S.OutlineSoft
	content.ZIndex = z + 2
	content.Parent = shell.body

	-- per-section teardown: cards, cullers, driver entries, connections
	local live: { cards: { any }, cullers: { any }, conns: { RBXScriptConnection }, fx: { number }, threads: { thread } } = { cards = {}, cullers = {}, conns = {}, fx = {}, threads = {} }
	local function teardown()
		for _, c in ipairs(live.cullers) do c.detach() end
		for _, c in ipairs(live.cards) do c.destroy() end
		for _, c in ipairs(live.conns) do c:Disconnect() end
		for _, id in ipairs(live.fx) do FxDriver.unregister(id) end
		for _, th in ipairs(live.threads) do task.cancel(th) end
		live = { cards = {}, cullers = {}, conns = {}, fx = {}, threads = {} }
		Modal.closeCurrent()
		for _, ch in ipairs(content:GetChildren()) do
			if ch:IsA("GuiObject") then ch:Destroy() end
		end
	end
	local function track(card) table.insert(live.cards, card) return card end

	local sections: { [string]: (host: Frame) -> () } = {}

	---------------------------------------------------------------- TOKENS
	sections.tokens = function(host)
		heading(host, "COLOUR ROLES (handoff §4)", 1)
		local r = row(host, "Roles", nil, 2)
		local roles = {
			{ "Positive", "equip / claim / confirm / teleport / buy with coins" }, { "Destructive", "delete / remove / close" },
			{ "Neutral", "utility, filters, sort, ACTIVE tab" }, { "Gold", "coins, rewards, value, prices" },
			{ "Purple", "gems, premium" }, { "Disabled", "inactive tabs, secondary chips" }, { "DisabledButton", "a disabled button" },
		}
		for i, spec in ipairs(roles) do
			local ramp = S.Role[spec[1]]
			local sw = PC.plate({ name = spec[1], size = UDim2.fromOffset(200, 110), colors = ramp, radius = 18, outline = 4, zIndex = z + 3, parent = r, layoutOrder = i })
			PC.shout({ text = spec[1]:upper(), size = 22, parent = sw, frameSize = UDim2.new(1, 0, 0, 40), zIndex = z + 5, scaled = true })
			local c = PC.read({ text = spec[2], size = 16, color = S.Surface.ReadInk, parent = sw, frameSize = UDim2.new(1, -12, 0, 56), position = UDim2.fromOffset(6, 44), zIndex = z + 5 })
			c.TextWrapped = true
			c.TextColor3 = Color3.new(1, 1, 1)
		end
		local selRow = row(host, "Selection", 40, 3)
		local sel = PC.plate({ name = "Selection", size = UDim2.fromOffset(200, 36), colors = { S.Role.Selection, S.Role.Selection }, radius = 12, outline = 3, zIndex = z + 3, parent = selRow, gloss = false })
		PC.shout({ text = "SELECTION RING", size = 18, parent = sel, zIndex = z + 5 })
		heading(host, "SPACING (handoff §16)", 4)
		local sp = row(host, "Spacing", 60, 5)
		for i, key in ipairs({ "micro", "small", "std", "section", "large" }) do
			local v = S.Space[key]
			local bar = PC.plate({ name = key, size = UDim2.fromOffset(v * 4, 40), colors = S.Role.Neutral, radius = 8, outline = 2, zIndex = z + 3, parent = sp, layoutOrder = i, gloss = false })
			PC.shout({ text = ("%s %d"):format(key, v), size = 16, parent = bar, zIndex = z + 5, scaled = true })
		end
		heading(host, "TYPE", 6)
		local ty = row(host, "Type", nil, 7)
		for i, key in ipairs({ "PanelTitle", "HeroAction", "SectionHead", "RowTitle", "Cta", "RowSub", "Meta", "Chip" }) do
			local sz = S.TextSize[key]
			local l = PC.shout({ text = ("%s %d"):format(key, sz), size = sz, color = S.Role.Neutral[2], strokeColor = Color3.new(1, 1, 1), parent = ty, frameSize = UDim2.fromOffset(0, sz + 12), zIndex = z + 3 })
			l.AutomaticSize = Enum.AutomaticSize.X
			l.LayoutOrder = i
		end
	end

	---------------------------------------------------------------- BUTTONS
	sections.buttons = function(host)
		local kinds = { "positive", "neutral", "destructive", "gold", "purple", "secondary" }
		heading(host, "KINDS -- normal / disabled / busy", 1)
		for i, kind in ipairs(kinds) do
			local r = row(host, kind, 90, 1 + i)
			PC.button({ kind = kind, text = kind:upper(), parent = r, zIndex = z + 3, layoutOrder = 1 })
			local d = PC.button({ kind = kind, text = "DISABLED", parent = r, zIndex = z + 3, layoutOrder = 2 })
			PC.setEnabled(d, false)
			local b = PC.button({ kind = kind, text = "BUSY", parent = r, zIndex = z + 3, layoutOrder = 3 })
			PC.setBusy(b, true, { timeout = 3600 })
			PC.button({ kind = kind, text = "SMALL", size = "small", parent = r, zIndex = z + 3, layoutOrder = 4 })
			PC.button({ kind = kind, text = "ICON", icon = S.Art.bag, parent = r, zIndex = z + 3, layoutOrder = 5 })
		end
		heading(host, "BUSY ROUND TRIP -- click to go busy for 2s (timeout 3s warns if a reply never came)", 10)
		local r = row(host, "BusyTrip", 90, 11)
		local trip: TextButton
		trip = PC.button({ kind = "positive", text = "EQUIP BEST", parent = r, zIndex = z + 3, onActivated = function()
			PC.setBusy(trip, true, { timeout = 3 })
			task.delay(2, function() PC.setBusy(trip, false) end)
		end })
		local lost: TextButton
		lost = PC.button({ kind = "gold", text = "LOST REPLY", parent = r, zIndex = z + 3, onActivated = function()
			PC.setBusy(lost, true, { timeout = 3 })
		end })
	end

	---------------------------------------------------------------- SHELL
	sections.shell = function(host)
		heading(host, "SHELL SLOTS -- stat, primary action, footer (destructive on the right)", 1)
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.new(1, 0, 0, 640)
		holder.LayoutOrder = 2
		holder.ZIndex = z + 3
		holder.Parent = host
		local mini = PC.shell({
			name = "MiniShell", title = "BAG", key = "bag", size = Vector2.new(1100, 600), parent = holder, zIndex = z + 4,
			icon = S.Art.bag, stat = { text = "16/16 equipped  ·  $1.2M/s", icon = S.Art.shop },
			primaryAction = { kind = "positive", text = "EQUIP BEST", onActivated = function() Toast.show({ text = "EQUIP BEST pressed", tone = "success" }) end },
		})
		mini.root.Position = UDim2.fromScale(0.5, 0.5)
		mini.close:SetAttribute("SfxMuted", true)
		mini.addFooter({
			left = { { text = "HIDE PLOT", kind = "secondary" }, { text = "LOCK ALL", kind = "neutral" }, { text = "MULTI-SELECT", kind = "neutral" } },
			right = { { text = "DELETE", kind = "destructive", onActivated = function()
				Modal.confirm({ title = "DELETE 3 BRAINROTS?", body = "They go back into the wild. This cannot be undone.", loss = "You will lose $12.4K/s of income.", confirmText = "DELETE",
					onConfirm = function() Toast.show({ text = "Deleted (demo)", tone = "error" }) end })
			end } },
		})
		for i = 1, 3 do
			PC.row({ title = "Row " .. i, subtitle = "a PanelChrome.row inside the body", parent = mini.body, zIndex = z + 5, layoutOrder = i })
		end
	end

	---------------------------------------------------------------- TABS
	sections.tabs = function(host)
		heading(host, "HORIZONTAL TABBAR (quests) -- with a badge", 1)
		local r1 = row(host, "Horizontal", 90, 2)
		local hz = TabBar.new({ tabs = { { id = "main", text = "MAIN" }, { id = "daily", text = "DAILY" }, { id = "event", text = "EVENT", icon = S.Art.goals }, { id = "done", text = "COMPLETED" } }, selected = "main", parent = r1, zIndex = z + 3, onChanged = function(id) Toast.show({ text = "tab: " .. id }) end })
		hz.setBadge("daily", 2)
		heading(host, "VERTICAL TABBAR (bag categories)", 3)
		local r2 = row(host, "Vertical", 480, 4)
		TabBar.new({ orientation = "vertical", width = 140, tabs = { { id = "brainrots", text = "BRAINROTS", icon = S.Art.bag }, { id = "pets", text = "PETS", icon = S.Art.rebirth }, { id = "charms", text = "CHARMS", icon = S.Art.goals }, { id = "keys", text = "KEYS", icon = S.Art.worlds }, { id = "tags", text = "TAGS", icon = S.Art.shop }, { id = "index", text = "INDEX", icon = S.Art.settings } }, selected = "brainrots", parent = r2, zIndex = z + 3, onChanged = function() end })
		heading(host, "HEADER TABS (senior level, PanelChrome.addHeaderTabs)", 5)
		local r3 = row(host, "Header", 100, 6)
		local mini = PC.shell({ name = "TabShell", title = "PROGRESS", key = "goals", size = Vector2.new(900, 90), parent = r3, zIndex = z + 4, scroll = false })
		mini.root.Position = UDim2.fromScale(0, 0)
		mini.root.AnchorPoint = Vector2.new(0, 0)
		mini.root.Size = UDim2.fromOffset(900, 90)
		mini.body.Visible = false
		mini.close:SetAttribute("SfxMuted", true)
		mini.addHeaderTabs({ { text = "GOALS", width = 180 }, { text = "SEASON PASS", width = 240 } }, 1, function() end)
	end

	---------------------------------------------------------------- INPUTS
	sections.inputs = function(host)
		heading(host, "SEARCH + SORT (bag sizes: 36px) and kit sizes (64px)", 1)
		local r1 = row(host, "Small", 60, 2)
		local echo = caption(r1, "query: (none)  sort: rarity", 3)
		local q, srt = "", "rarity"
		local function paintEcho() echo.Text = ("query: %s  sort: %s"):format(q == "" and "(none)" or q, srt) end
		SearchBar.new({ placeholder = "SEARCH...", width = 240, height = 36, parent = r1, zIndex = z + 3, layoutOrder = 1, onChanged = function(v) q = v; paintEcho() end })
		SortButton.new({ modes = { { id = "rarity", label = "RARITY" }, { id = "newest", label = "NEWEST" }, { id = "az", label = "A-Z" } }, selected = "rarity", height = 36, width = 3 * 96 + 24, parent = r1, zIndex = z + 3, layoutOrder = 2, onChanged = function(id) srt = id; paintEcho() end })
		local r2 = row(host, "Large", 90, 3)
		SearchBar.new({ placeholder = "SEARCH BRAINROTS...", width = 420, parent = r2, zIndex = z + 3, layoutOrder = 1, onChanged = function() end })
		SortButton.new({ modes = { { id = "rarity", label = "RARITY" }, { id = "newest", label = "NEWEST" }, { id = "az", label = "A-Z" } }, selected = "newest", parent = r2, zIndex = z + 3, layoutOrder = 2, onChanged = function() end })
		heading(host, "SEGMENTED / TOGGLE / SLIDER / BAR (existing PanelChrome parts)", 4)
		local r3 = row(host, "Parts", 100, 5)
		PC.segmented({ options = { "LOW", "MED", "HIGH" }, selected = 2, size = UDim2.fromOffset(420, 64), parent = r3, zIndex = z + 3 })
		PC.toggle({ parent = r3, zIndex = z + 3, on = true, onChanged = function() end })
		local r4 = row(host, "Slider", 100, 6)
		PC.slider({ size = UDim2.fromOffset(420, 60), parent = r4, zIndex = z + 3, value = 0.6, onChanged = function() end })
		local r5 = row(host, "Bar", 80, 7)
		local bar = PC.bar({ size = UDim2.fromOffset(420, S.Chrome.TrackHeight), parent = r5, zIndex = z + 3, label = "10 / 16" })
		bar.set(0.62)
	end

	---------------------------------------------------------------- MODAL + TOAST
	sections.modal = function(host)
		heading(host, "CONFIRMATION MODAL (dangerous actions only)", 1)
		local r = row(host, "Modals", 90, 2)
		PC.button({ kind = "destructive", text = "DELETE (cancelable)", parent = r, zIndex = z + 3, onActivated = function()
			Modal.confirm({ title = "DELETE 3 BRAINROTS?", body = "They go back into the wild. This cannot be undone.", loss = "You will lose $12.4K/s of income.", confirmText = "DELETE",
				onConfirm = function() Toast.show({ text = "Confirmed", tone = "error" }) end, onCancel = function() Toast.show({ text = "Cancelled" }) end })
		end })
		PC.button({ kind = "positive", text = "REBIRTH (not cancelable)", parent = r, zIndex = z + 3, onActivated = function()
			Modal.confirm({ title = "REBIRTH NOW?", body = "Cash resets. Brainrots stay. Multiplier +15%.", confirmText = "REBIRTH", confirmKind = "positive", cancelable = false,
				onConfirm = function() Toast.show({ text = "Reborn (demo)", tone = "reward" }) end })
		end })
		heading(host, "TOAST TONES", 3)
		local r2 = row(host, "Toasts", 90, 4)
		for i, tone in ipairs({ "info", "success", "error", "reward" }) do
			PC.button({ kind = if tone == "error" then "destructive" elseif tone == "reward" then "gold" elseif tone == "success" then "positive" else "neutral", text = tone:upper(), parent = r2, zIndex = z + 3, layoutOrder = i, onActivated = function()
				Toast.show({ text = ("A %s toast that is long enough to wrap on a phone, so the whole sentence still shows."):format(tone), tone = tone })
			end })
		end
	end

	---------------------------------------------------------------- CARDS
	sections.cards = function(host)
		local names = rosterNames(8)
		heading(host, "RARITY LADDER (grid variant)", 1)
		local r1 = row(host, "Ladder", nil, 2)
		for i, tier in ipairs(TIERS) do
			local cell = cardSlot(r1, i, tier)
			track(BrainrotCard.new({ kind = "brainrot", name = names[i] or names[1], rarity = tier, income = 10 ^ i, variant = "grid", parent = cell, zIndex = z + 3 })).mount()
		end
		heading(host, "STATES -- badges never overpower the rarity", 3)
		local r2 = row(host, "States", nil, 4)
		local n = names[3] or names[1]
		local states = {
			{ "locked", { locked = true } }, { "equipped #7", { equipped = 7 } }, { "new", { new = true } }, { "selected", { selected = true } },
			{ "all three (cap 2)", { locked = true, equipped = 3, new = true } },
		}
		for i, st in ipairs(states) do
			local cell = cardSlot(r2, i, st[1])
			track(BrainrotCard.new({ kind = "brainrot", name = n, rarity = "Legendary", income = 9500, state = st[2], lock = { onToggle = function(v) Toast.show({ text = "lock -> " .. tostring(v) }) end }, variant = "grid", parent = cell, zIndex = z + 3 })).mount()
		end
		local cellM = cardSlot(r2, 6, "Golden Huge x3")
		track(BrainrotCard.new({ kind = "brainrot", name = n, rarity = "Epic", income = 1800, mutation = "Golden", mutationColor = Color3.fromRGB(255, 215, 60), sizeTag = "Huge", count = 3, variant = "grid", parent = cellM, zIndex = z + 3 })).mount()
		local cellG = cardSlot(r2, 7, "missing art")
		track(BrainrotCard.new({ kind = "brainrot", name = "NoSuchBrainrot_Gallery", rarity = "Rare", income = 0, variant = "grid", parent = cellG, zIndex = z + 3 })).mount()
		heading(host, "VARIANTS -- compact / grid / hero", 5)
		local r3 = row(host, "Variants", nil, 6)
		local cc = Instance.new("Frame"); cc.BackgroundTransparency = 1; cc.Size = UDim2.fromOffset(100, 110); cc.LayoutOrder = 1; cc.Parent = r3
		track(BrainrotCard.new({ kind = "brainrot", name = n, rarity = "Mythic", income = 62000, mutation = "Diamond", mutationColor = Color3.fromRGB(120, 230, 255), state = { equipped = true }, variant = "compact", parent = cc, zIndex = z + 3 })).mount()
		local cg = Instance.new("Frame"); cg.BackgroundTransparency = 1; cg.Size = UDim2.fromOffset(CARD_W, CARD_H); cg.LayoutOrder = 2; cg.Parent = r3
		track(BrainrotCard.new({ kind = "brainrot", name = n, rarity = "Mythic", income = 62000, mutation = "Diamond", mutationColor = Color3.fromRGB(120, 230, 255), state = { equipped = true }, variant = "grid", parent = cg, zIndex = z + 3 })).mount()
		local ch = Instance.new("Frame"); ch.BackgroundTransparency = 1; ch.Size = UDim2.fromOffset(300, 380); ch.LayoutOrder = 3; ch.Parent = r3
		track(BrainrotCard.new({ kind = "brainrot", name = n, rarity = "Secret", income = 410000, title = "Diamond " .. n, mutation = "Diamond", mutationColor = Color3.fromRGB(120, 230, 255), state = { equipped = true, new = true }, variant = "hero", parent = ch, zIndex = z + 3 })).mount()
		heading(host, ("FRAMING SET -- projected fill target %.2f (spec §8.1); label = measured fill / off-centre"):format(S.Card.Fill), 7)
		local r4 = row(host, "Framing", nil, 8)
		local aspect = (CARD_W - 2 * S.Card.ArtInset) / (CARD_H * (1 - S.Card.BandFrac) - S.Card.ArtInset - 8)
		for i, pick in ipairs(framingSet()) do
			local fill, mx, my = measureFill(pick.name, aspect)
			local cell = cardSlot(r4, i, ("%s %s  fill %.2f  off (%.2f,%.2f)"):format(pick.label, pick.name, fill, mx, my))
			track(BrainrotCard.new({ kind = "brainrot", name = pick.name, rarity = "Rare", income = 100, variant = "grid", parent = cell, zIndex = z + 3 })).mount()
		end
	end

	---------------------------------------------------------------- STRESS
	sections.stress = function(host)
		heading(host, "STRESS -- N cards on ViewportCuller; readout sets S.Card.MaxLive per platform", 1)
		local controls = row(host, "Controls", 90, 2)
		local readout = caption(host, "not running", 3)
		readout.Size = UDim2.new(1, 0, 0, 28)
		local grid = Instance.new("ScrollingFrame")
		grid.Name = "StressGrid"
		grid.BackgroundColor3 = S.Surface.Body
		grid.BorderSizePixel = 0
		grid.Size = UDim2.new(1, 0, 0, 520)
		grid.LayoutOrder = 4
		grid.CanvasSize = UDim2.new()
		grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
		grid.ScrollBarThickness = 5
		grid.ZIndex = z + 3
		grid.Parent = host
		local gl = Instance.new("UIGridLayout")
		gl.CellSize = UDim2.fromOffset(100, 132)
		gl.CellPadding = UDim2.fromOffset(8, 8)
		gl.SortOrder = Enum.SortOrder.LayoutOrder
		gl.Parent = grid
		local names = rosterNames(24)
		local count, cap = 100, ViewportCuller.defaultCap()
		local culler = nil
		local samples, sIdx = {}, 0
		local function rebuild()
			if culler then culler.detach() culler = nil end
			for _, c in ipairs(live.cards) do c.destroy() end
			live.cards = {}
			for i = 1, count do
				local card = BrainrotCard.new({ kind = "brainrot", name = names[(i - 1) % #names + 1], rarity = TIERS[(i - 1) % 8 + 1], income = i * 10, variant = "grid", parent = grid, zIndex = z + 3, layoutOrder = i })
				table.insert(live.cards, card)
			end
			culler = ViewportCuller.attach(grid, live.cards, { maxLive = cap })
			live.cullers = { culler }
		end
		for _, nOpt in ipairs({ 100, 250, 500 }) do
			PC.button({ kind = "neutral", text = "N=" .. nOpt, size = "small", parent = controls, zIndex = z + 3, onActivated = function() count = nOpt; rebuild() end })
		end
		for _, cOpt in ipairs({ 24, 48, 72, 96 }) do
			PC.button({ kind = "gold", text = "CAP " .. cOpt, size = "small", parent = controls, zIndex = z + 3, onActivated = function() cap = cOpt; rebuild() end })
		end
		PC.button({ kind = "secondary", text = "AUTO-SCROLL", size = "small", parent = controls, zIndex = z + 3, onActivated = function()
			table.insert(live.threads, task.spawn(function()
				local maxY = math.max(0, grid.AbsoluteCanvasSize.Y - grid.AbsoluteSize.Y)
				for step = 0, 40 do
					grid.CanvasPosition = Vector2.new(0, maxY * (step / 40))
					task.wait(0.05)
				end
				grid.CanvasPosition = Vector2.new(0, maxY * 0.5)
			end))
		end })
		table.insert(live.fx, FxDriver.register(readout, function(_, dt)
			sIdx = sIdx % 30 + 1
			samples[sIdx] = dt
			local sum, n = 0, 0
			for _, v in ipairs(samples) do sum += v; n += 1 end
			local avg = n > 0 and (sum / n) * 1000 or 0
			readout.Text = ("%s  N=%d  cap=%d  live=%d  avg dt=%.1fms  fx=%d  platform=%s"):format(culler and "running" or "idle", count, culler and culler.cap() or cap, culler and culler.live() or 0, avg, FxDriver.count(), Platform.Class)
		end))
		rebuild()
	end

	---------------------------------------------------------------- LEGACY
	sections.legacy = function(host)
		heading(host, "OLD vs NEW -- migration audit", 1)
		local r = row(host, "Buttons", 90, 2)
		PC.pill({ text = "OLD PILL (Go)", colors = S.Action.Go, size = UDim2.fromOffset(230, 76), parent = r, zIndex = z + 3 })
		PC.button({ kind = "positive", text = "NEW BUTTON", parent = r, zIndex = z + 3 })
		PC.pill({ text = "OLD NEUTRAL", colors = S.Action.Neutral, size = UDim2.fromOffset(230, 76), parent = r, zIndex = z + 3 })
		PC.button({ kind = "neutral", text = "NEW NEUTRAL", parent = r, zIndex = z + 3 })
		caption(host, "Old pills keep their values as aliases; kit consumers read S.Role.", 3)
	end

	---------------------------------------------------------------- navigation
	local currentSection = "tokens"
	local function showSection(id: string)
		teardown()
		currentSection = id
		local host = Instance.new("Frame")
		host.Name = "Section_" .. id
		host.BackgroundTransparency = 1
		host.Size = UDim2.new(1, -S.Space.std, 0, 0)
		host.AutomaticSize = Enum.AutomaticSize.Y
		host.ZIndex = z + 3
		host.Parent = content
		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, S.Space.section)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = host
		content.CanvasPosition = Vector2.new(0, 0)
		local fn = sections[id]
		local ok, err = pcall(fn, host)
		if not ok then
			warn(("[UIKit] Gallery section %q failed: %s\n%s"):format(id, tostring(err), debug.traceback()))
			local tile = PC.plate({ name = "SectionError", size = UDim2.new(1, 0, 0, 160), colors = S.Role.Destructive, radius = 18, outline = 4, zIndex = z + 4, parent = host, gloss = false })
			local l = PC.read({ text = ("SECTION %s FAILED:\n%s"):format(id:upper(), tostring(err)), size = 18, color = Color3.new(1, 1, 1), parent = tile, frameSize = UDim2.new(1, -24, 1, -24), position = UDim2.fromOffset(12, 12), zIndex = z + 5 })
			l.TextWrapped = true
		end
	end

	local tabs = TabBar.new({ orientation = "vertical", width = 180, tabs = SECTIONS, selected = "tokens", parent = shell.body, zIndex = z + 3, onChanged = showSection })
	tabs.root.Position = UDim2.fromOffset(0, 0)

	-- panel hidden -> release everything (viewports, cullers, driver entries)
	shell.root:GetPropertyChangedSignal("Visible"):Connect(function()
		if shell.root.Visible then
			showSection(currentSection)
		else
			teardown()
		end
	end)
	showSection("tokens")
	return shell.root
end

return GalleryPanel
