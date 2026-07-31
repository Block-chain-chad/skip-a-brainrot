-- Unified merchant shop: press E at a merchant to see what they sell.
-- Driven by MerchantConfig, so adding a merchant = adding a config entry.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("MainUI")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local RockConfig = require(ReplicatedStorage.Modules.RockConfig)
local RockDesign = require(ReplicatedStorage.Modules.RockDesign)
local SideRail = require(ReplicatedStorage.Modules.SideRail)
local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
local MerchantConfig = require(ReplicatedStorage.Modules.MerchantConfig)
local MerchantDialog = require(ReplicatedStorage.Modules.MerchantDialog)
local SoundKit = require(ReplicatedStorage.Modules.SoundKit)
local UITheme = require(ReplicatedStorage.Modules.UITheme)

local P = UITheme.Palette
local BLACK = Color3.fromRGB(0, 0, 0)
local FONT = UITheme.Font
local state = { Cash = 0, OwnedRocks = {}, EquippedRock = "", Upgrades = {} }
local current = nil
local page = 1
local PER_PAGE = 8   -- cards per shop page (2x4 grid); the panel + list are sized to fit exactly this

local function short(n)
	n = math.floor(n)
	if n >= 1e9 then return string.format("%.1fB", n/1e9)
	elseif n >= 1e6 then return string.format("%.1fM", n/1e6)
	elseif n >= 1e3 then return string.format("%.1fK", n/1e3) end
	return tostring(n)
end
local function blackRim(o, thick)
	for _, s in ipairs(o:GetChildren()) do
		if s:IsA("UIStroke") and s.ApplyStrokeMode ~= Enum.ApplyStrokeMode.Contextual then
			s.Color = BLACK; s.Thickness = thick or 3; s.Transparency = 0
		end
	end
end
local function inkText(o, thick)
	local st = Instance.new("UIStroke")
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	st.Color = BLACK; st.Thickness = thick or 2; st.Transparency = 0.05
	st.Parent = o
	return st
end

---------------------------------------------------------------- rock previews (3D)
local spinParts = {}
-- Rock previews come from ReplicatedStorage.Modules.RockDesign, the same builder
-- the thrown rock and Rocco's shelf use. This replaces a local ROCK_PREVIEW table
-- that specified DIFFERENT shapes and materials from the thrown rock, so a rock
-- could look like one object in the shop and another in your hand.
local function makeRockViewport(med, rock)
	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.new(1, 0, 1, 0)
	vp.BackgroundColor3 = Color3.fromRGB(26, 30, 40)
	vp.Ambient = Color3.fromRGB(160, 160, 170)
	vp.LightColor = Color3.fromRGB(255, 244, 224)
	vp.LightDirection = Vector3.new(-0.6, -1, -0.4)
	vp.ZIndex = med.ZIndex + 1
	vp.Parent = med
	UITheme.corner(vp, 12)

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
	for _, mdl in ipairs(spinParts) do
		if mdl.Parent then
			mdl:PivotTo(CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(-8), 0, 0))
		end
	end
end)

---------------------------------------------------------------- panel (campfire style)
local CF = UITheme.Camp

local frame = Instance.new("Frame")
frame.Name = "MerchantFrame"
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.new(0.5, 0, 0.5, 0)
frame.Size = UDim2.fromOffset(664, 720)   -- room for one 2x4 page (compact cards) plus the page bar
frame.Visible = false
frame.ZIndex = 10
frame.Parent = gui
-- The rail sits at DisplayOrder 6 and this panel at 0, so the six rail cards were
-- drawing straight over the shop's left-hand column. Registering it means the rail
-- folds away while the shop is open, exactly as it does for the Index and Backpack.
SideRail.registerPanel(frame)
UITheme.campPanel(frame)

-- Short-viewport guard: shrink and push the panel down so it never covers the
-- top TabBar band (146px) and keeps a 40px bottom margin. Anchor stays (0.5, 0.5).
local FRAME_H = 720
local hudScale = Instance.new("UIScale")
hudScale.Name = "HudFixScale"
hudScale.Parent = frame
local function relayout()
	local vh = gui.AbsoluteSize.Y
	if vh <= 0 then return end
	local s = math.min(1, (vh - 146 - 40) / FRAME_H)
	hudScale.Scale = s
	-- clamp so the panel's top edge sits at or below the 146px band
	frame.Position = UDim2.new(0.5, 0, 0.5, math.max(0, 146 + FRAME_H * s / 2 - vh / 2))
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
relayout()

-- carved-wood banner that overhangs the panel top
local ribbon, title = UITheme.ribbon(frame, "SHOP", 0.62)

local blurb = Instance.new("TextLabel")
blurb.Size = UDim2.new(1, -44, 0, 20)
blurb.Position = UDim2.new(0, 22, 0, 46)
blurb.BackgroundTransparency = 1
blurb.Font = FONT
blurb.TextSize = 14
blurb.TextColor3 = CF.muted
blurb.ZIndex = 12
blurb.Parent = frame
inkText(blurb, 1.8)

local closeBtn = Instance.new("TextButton")
closeBtn.Parent = frame
UITheme.styleClose(closeBtn)
closeBtn.ZIndex = 18
closeBtn.TextSize = 18
blackRim(closeBtn, 3)

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -36, 0, 590)   -- fixed to one 2x4 page (590 = 4 rows of 140 + 10 gap); no in-page scroll
list.Position = UDim2.new(0, 18, 0, 74)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ZIndex = 11
list.Parent = frame
local layout = Instance.new("UIGridLayout")
layout.CellSize = UDim2.fromOffset(300, 140)
layout.CellPadding = UDim2.fromOffset(14, 10)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = list

---------------------------------------------------------------- pagination bar
-- The rock ladder is long now, so the shop is paged (PER_PAGE cards each). This bar
-- sits under the grid; rebuild() shows it only when there is more than one page.
local pageBar = Instance.new("Frame")
pageBar.Name = "PageBar"
pageBar.AnchorPoint = Vector2.new(0.5, 1)
pageBar.Position = UDim2.new(0.5, 0, 1, -14)
pageBar.Size = UDim2.fromOffset(320, 34)
pageBar.BackgroundTransparency = 1
pageBar.ZIndex = 14
pageBar.Visible = false
pageBar.Parent = frame

local function pageArrow(glyph, anchorX, posX)
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(anchorX, 0.5)
	b.Position = UDim2.new(posX, 0, 0.5, 0)
	b.Size = UDim2.fromOffset(52, 30)
	b.Text = glyph
	b.TextSize = 18
	b.ZIndex = 15
	b.Parent = pageBar
	UITheme.campButton(b, CF.amber1, CF.amber2)
	return b
end
local prevBtn = pageArrow("\u{25C0}", 0, 0)
local nextBtn = pageArrow("\u{25B6}", 1, 1)

local pageLabel = Instance.new("TextLabel")
pageLabel.AnchorPoint = Vector2.new(0.5, 0.5)
pageLabel.Position = UDim2.fromScale(0.5, 0.5)
pageLabel.Size = UDim2.fromOffset(170, 30)
pageLabel.BackgroundTransparency = 1
pageLabel.Font = FONT
pageLabel.TextSize = 16
pageLabel.TextColor3 = CF.cream
pageLabel.Text = "Page 1 / 1"
pageLabel.ZIndex = 15
pageLabel.Parent = pageBar
inkText(pageLabel, 2)

---------------------------------------------------------------- card builder
-- each card gets its own accent, carried through the border, the title colour
-- and the sunburst behind the icon -- that trio is what sells the style.
local ACCENTS = {
	{ CF.amber1, CF.amber2 },
	{ CF.pine1,  CF.pine2  },
	{ CF.lake1,  CF.lake2  },
	{ CF.ember1, CF.ember2 },
	{ CF.berry1, CF.berry2 },
}

local function makeRow(order, swatch, name, desc, btnText, btnTop, btnBot, onClick, dim, previewBuilder, pillA, pillB)
	local acc = ACCENTS[((order - 1) % #ACCENTS) + 1]
	local card, outer = UITheme.accentCard(list, acc[1], 14)
	outer.LayoutOrder = order
	outer.ZIndex = 11
	card.ZIndex = 12
	if dim then card.BackgroundTransparency = 0.2 end

	-- icon tile: sunburst backdrop + medallion (or the 3D rock preview)
	local icon = Instance.new("Frame")
	icon.Size = UDim2.fromOffset(58, 58)
	icon.Position = UDim2.new(0, 12, 0, 12)
	icon.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	icon.BorderSizePixel = 0
	icon.ClipsDescendants = true
	icon.ZIndex = card.ZIndex + 1
	icon.Parent = card
	UITheme.corner(icon, 10)
	UITheme.sunburst(icon, acc[1], 12)
	UITheme.ink(icon, 3)

	if previewBuilder then
		local holder = Instance.new("Frame")
		holder.Size = UDim2.fromScale(1, 1)
		holder.BackgroundTransparency = 1
		holder.ClipsDescendants = true
		holder.ZIndex = icon.ZIndex + 3
		holder.Parent = icon
		previewBuilder(holder)
	else
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.5, 0.5)
		dot.Size = UDim2.fromOffset(46, 46)
		dot.BackgroundColor3 = swatch
		dot.BorderSizePixel = 0
		dot.ZIndex = icon.ZIndex + 3
		dot.Parent = icon
		UITheme.corner(dot, 23)
		UITheme.ink(dot, 2.5)
		UITheme.gloss(dot, 20, 0.55)
	end

	local n = Instance.new("TextLabel")
	n.Size = UDim2.new(1, -88, 0, 22)
	n.Position = UDim2.new(0, 80, 0, 10)
	n.BackgroundTransparency = 1
	n.Font = FONT
	n.TextSize = 17
	n.TextXAlignment = Enum.TextXAlignment.Left
	n.TextTruncate = Enum.TextTruncate.AtEnd
	n.TextColor3 = acc[1]
	n.Text = name
	n.ZIndex = card.ZIndex + 2
	n.Parent = card
	UITheme.inkText(n, 2.8)

	local d = Instance.new("TextLabel")
	d.Size = UDim2.new(1, -90, 0, 32)
	d.Position = UDim2.new(0, 80, 0, 32)
	d.BackgroundTransparency = 1
	d.Font = Enum.Font.GothamMedium
	d.TextSize = 12
	d.TextXAlignment = Enum.TextXAlignment.Left
	d.TextYAlignment = Enum.TextYAlignment.Top
	d.TextWrapped = true
	d.TextColor3 = CF.muted
	d.Text = desc
	d.ZIndex = card.ZIndex + 2
	d.Parent = card
	UITheme.inkText(d, 1.6)

	-- "Lv. 3" / "x1.4" stat pills, like the reference
	local function pill(txt, xOff)
		local f = Instance.new("Frame")
		f.Size = UDim2.fromOffset(74, 22)
		f.Position = UDim2.new(0, xOff, 0, 66)
		f.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		f.BorderSizePixel = 0
		f.ZIndex = card.ZIndex + 2
		f.Parent = card
		UITheme.corner(f, 7)
		UITheme.gradient(f, CF.panelTop, CF.panelBot, 90)
		UITheme.ink(f, 2.5)
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = FONT
		t.TextSize = 13
		t.TextColor3 = CF.cream
		t.Text = txt
		t.ZIndex = f.ZIndex + 1
		t.Parent = f
		UITheme.inkText(t, 2)
	end
	if pillA then pill(pillA, 80) end
	if pillB then pill(pillB, 160) end

	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = UDim2.new(0.5, 0, 1, -8)
	b.Size = UDim2.new(1, -22, 0, 32)
	b.Text = btnText
	b.TextSize = 15
	b.ZIndex = card.ZIndex + 2
	b.Parent = card
	UITheme.campButton(b, btnTop, btnBot)
	if onClick then
		b.Activated:Connect(onClick)
	else
		b.AutoButtonColor = false
	end
	return card
end

---------------------------------------------------------------- rebuild
local function rebuild()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	if not current then pageBar.Visible = false; return end
	title.Text = current.Title
	blurb.Text = current.Npc .. "  \u{2022}  " .. current.Blurb
	UITheme.setColors(title, current.Accent[1], current.Accent[2])

	-- Build a flat list of render closures so pagination is Kind-agnostic: each entry
	-- draws exactly one card when called with its on-page order (1..PER_PAGE).
	local items = {}
	if current.Kind == "Rock" then
		for i, rock in ipairs(RockConfig) do
			local owned = state.OwnedRocks[rock.Id]
			local equipped = state.EquippedRock == rock.Id
			-- SEQUENTIAL UNLOCK: buyable only once the previous rock is owned
			local prevRock = RockConfig[i - 1]
			local unlocked = (i == 1) or (prevRock ~= nil and state.OwnedRocks[prevRock.Id] == true)
			items[i] = function(order)
				local txt, top, bot, cb
				if equipped then
					txt, top, bot = "EQUIPPED", P.green1, P.green2
				elseif owned then
					txt, top, bot = "EQUIP", P.blue1, P.blue2
					cb = function() remotes.EquipRock:FireServer(rock.Id) end
				elseif not unlocked then
					txt, top, bot = "\u{1F512} LOCKED", Color3.fromRGB(150,156,170), Color3.fromRGB(94,100,114)
					-- no cb -> disabled button
				else
					txt, top, bot = "$" .. short(rock.Price), Color3.fromRGB(255,216,96), Color3.fromRGB(238,148,24)
					cb = function() remotes.BuyRock:FireServer(rock.Id) end
				end
				local desc = ("Up to %dm  \u{2022}  %.2fx luck"):format(rock.MaxDistance, rock.Luck)
				if not owned and not unlocked and prevRock then
					desc = ("\u{1F512} Buy the %s first"):format(prevRock.Id)
				end
				makeRow(order, rock.Color, rock.Id, desc, txt, top, bot, cb, not owned,
					function(med) makeRockViewport(med, rock) end)
			end
		end
	elseif current.Kind == "Upgrade" then
		for i, up in ipairs(UpgradeConfig.List) do
			items[i] = function(order)
				local lvl = UpgradeConfig.Level(state.Upgrades, up.Id)
				local price = UpgradeConfig.Price(up.Id, lvl)
				local pct = math.floor(lvl * up.PerLevel * 100 + 0.5)
				local txt, top, bot, cb
				if not price then
					txt, top, bot = "MAXED", Color3.fromRGB(150,156,170), Color3.fromRGB(94,100,114)
				else
					txt, top, bot = "$" .. short(price), CF.amber1, CF.amber2
					cb = function() remotes.BuyUpgrade:FireServer(up.Id) end
				end
				makeRow(order, current.Accent[1], up.Name, up.Desc, txt, top, bot, cb, price ~= nil and lvl == 0,
					function(holder)
						local e = Instance.new("TextLabel")
						e.Size = UDim2.fromScale(1, 1)
						e.BackgroundTransparency = 1
						e.Font = FONT
						e.TextSize = 40
						e.Text = up.Icon
						e.ZIndex = holder.ZIndex + 1
						e.Parent = holder
					end,
					("Lv. %d/%d"):format(lvl, up.MaxLevel), ("+%d%%"):format(pct))
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

	pageBar.Visible = totalPages > 1
	pageLabel.Text = ("Page %d / %d"):format(page, totalPages)
end

---------------------------------------------------------------- open / close
-- open to the page holding your next rock to buy, not always page 1
local function firstRelevantPage(m)
	if m.Kind == "Rock" then
		for i, rock in ipairs(RockConfig) do
			if not state.OwnedRocks[rock.Id] then return math.ceil(i / PER_PAGE) end
		end
	end
	return 1
end
local function changePage(delta)
	page += delta
	rebuild()   -- rebuild re-clamps page and re-renders
end
prevBtn.Activated:Connect(function() changePage(-1) end)
nextBtn.Activated:Connect(function() changePage(1) end)

local function openMerchant(m)
	current = m
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
local promptParts = {}
for _, m in ipairs(MerchantConfig) do
	task.spawn(function()
		local stall = gameWorld:WaitForChild(m.Stall, 30)
		if not stall then return end
		local part = stall:WaitForChild("PromptPart", 30)
		if not part then return end
		local prompt = part:WaitForChild(m.Prompt, 30)
		if not prompt then return end
		promptParts[m.Id] = part
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
				MerchantDialog.Show(m.Npc, m.Dialogue, m.Accent, function() openMerchant(m) end, part)
			end
		end)
	end)
end

-- walk away -> close
RunService.Heartbeat:Connect(function()
	if not frame.Visible or not current then return end
	local part = promptParts[current.Id]
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if part and hrp and (hrp.Position - part.Position).Magnitude > 24 then
		closeMerchant()
	end
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
