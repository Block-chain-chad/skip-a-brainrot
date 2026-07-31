local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("MainUI")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local RockConfig = require(ReplicatedStorage.Modules.RockConfig)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local MerchantDialog = require(ReplicatedStorage.Modules.MerchantDialog)
local UIStyle = require(ReplicatedStorage.Modules.UIStyle) -- Round 2: shared bubbly theme for the top bar
local SideRail = require(ReplicatedStorage.Modules.SideRail) -- single-open panel registry
local BrainrotThumb = require(ReplicatedStorage.Modules.BrainrotThumb) -- shared 3D thumbnail helper (sell list icons)
local SoundKit = require(ReplicatedStorage.Modules.SoundKit) -- SFX2
-- Kit-style icon artwork for the teleport tabs (see UIKit.IconArt). pcall'd:
-- ClientMain drives the whole throw minigame, so a missing icon module must
-- degrade to the old emoji rather than take the client down.
local okIconArt, IconArt = pcall(function()
	return require(ReplicatedStorage.Modules.UIKit.IconArt)
end)
if not okIconArt then IconArt = nil end

local SELL_MULTIPLIER = 40

local brainrotInfoByName = {}
for _, entry in ipairs(BrainrotConfig) do
	brainrotInfoByName[entry.Name] = entry
end
local tierByName = {}
for _, tier in ipairs(RarityConfig) do
	tierByName[tier.Name] = tier
end

local cashFrame = gui.CashFrame
local cashLabel = cashFrame.CashLabel
local shopFrame = gui.ShopFrame
local shopList = shopFrame.ShopList
local shopCloseButton = shopFrame.CloseButton
local sellFrame = gui.SellFrame
local sellList = sellFrame.SellList
local sellCloseButton = sellFrame.CloseButton
local sellEmptyLabel = sellFrame.EmptyLabel
local throwFrame = gui.ThrowFrame
local throwButton = throwFrame.ThrowButton
local barFill = throwFrame.BarBackground.BarFill
local resultFrame = gui.ResultFrame
local rarityLabel = resultFrame.RarityLabel
local nameLabel = resultFrame.NameLabel
local infoLabel = resultFrame.InfoLabel

-- === Campfire menu chrome (shop / sell) ===
local P = UITheme.Palette
local CF = UITheme.Camp
local FONT = UITheme.Font

-- One accent per card, cycled down the list. It is carried through three places
-- at once -- card border, title text, sunburst tint -- exactly as MerchantClient.
local ACCENTS = {
	{ CF.amber1, CF.amber2 },
	{ CF.pine1,  CF.pine2  },
	{ CF.lake1,  CF.lake2  },
	{ CF.ember1, CF.ember2 },
	{ CF.berry1, CF.berry2 },
}

-- Repaint the Border strokes an authored instance already carries; adding a new
-- one would double the outline.
local function blackRim(o, thick)
	for _, s in ipairs(o:GetChildren()) do
		if s:IsA("UIStroke") and s.ApplyStrokeMode ~= Enum.ApplyStrokeMode.Contextual then
			s.Color = CF.ink; s.Thickness = thick or 3; s.Transparency = 0
		end
	end
end

-- Black glyph outline, reusing an existing Contextual stroke when there is one.
local function inkTextOnce(o, thick)
	for _, s in ipairs(o:GetChildren()) do
		if s:IsA("UIStroke") and s.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then
			s.Color = CF.ink; s.Thickness = thick or 2.4; s.Transparency = 0
			return s
		end
	end
	return UITheme.inkText(o, thick)
end

local function styleMenus()
	for _, spec in ipairs({
		{ frame = shopFrame, list = shopList, close = shopCloseButton, ribbonScale = 0.58 },
		{ frame = sellFrame, list = sellList, close = sellCloseButton, ribbonScale = 0.74 },
	}) do
		spec.frame.Size = UDim2.fromOffset(440, 400)
		-- MainUI is Global ZIndexBehavior: lift the panel, then every child with it.
		spec.frame.ZIndex = 10
		UITheme.campPanel(spec.frame)

		-- carved-wood banner overhanging the top, reusing the authored header text
		UITheme.ribbon(spec.frame, spec.frame.TextLabel.Text, spec.ribbonScale)
		spec.frame.TextLabel.Visible = false   -- kept, not destroyed

		UITheme.styleClose(spec.close)
		spec.close.ZIndex = 18
		spec.close.TextSize = 18
		blackRim(spec.close, 3)

		spec.list.Position = UDim2.new(0, 14, 0, 64)
		spec.list.Size = UDim2.new(1, -28, 1, -80)
		spec.list.BackgroundTransparency = 1
		spec.list.BorderSizePixel = 0
		spec.list.ScrollBarThickness = 6
		spec.list.ZIndex = 11
		spec.list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		spec.list.CanvasSize = UDim2.new(0, 0, 0, 0)
		local ll = spec.list:FindFirstChildOfClass("UIListLayout")
		if ll then ll.Padding = UDim.new(0, 10); ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.HorizontalAlignment = Enum.HorizontalAlignment.Center end
	end
	sellEmptyLabel.Position = UDim2.new(0, 16, 0, 74)
	sellEmptyLabel.Font = FONT
	sellEmptyLabel.TextSize = 15
	sellEmptyLabel.TextColor3 = CF.muted
	sellEmptyLabel.ZIndex = 12
	inkTextOnce(sellEmptyLabel, 2)
	-- shop + sell join the single-open registry: opening either closes any rail
	-- panel and folds the rail away, and vice versa
	SideRail.registerPanel(shopFrame)
	SideRail.registerPanel(sellFrame)
end
styleMenus()

local DEFAULT_THROW_TEXT = "HOLD TO SKIP"

local state = {
	Cash = 0,
	OwnedRocks = { Pebble = true },
	EquippedRock = "Pebble",
	Brainrots = {},
}

-- canonical abbreviator, K through Qi -- see Modules.NumberFormat
local formatNumber = require(ReplicatedStorage.Modules.NumberFormat).Short

local displayCash = 0
local function refreshCashLabel()
	cashLabel.Text = "Cash: " .. formatNumber(displayCash)
end
local function snapCashLabel()          -- for non-animated updates (purchases, snapshots)
	displayCash = state.Cash
	refreshCashLabel()
end
RunService.Heartbeat:Connect(function(dt)
	if math.abs(displayCash - state.Cash) < 1 then
		if displayCash ~= state.Cash then displayCash = state.Cash; refreshCashLabel() end
		return
	end
	displayCash += (state.Cash - displayCash) * math.min(dt * 9, 1)
	refreshCashLabel()
end)

-- === Shop ===
local rockRows = {}

local function buildShop()
	for _, child in ipairs(shopList:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	rockRows = {}

	local order = 0
	for _, rock in ipairs(RockConfig) do
		order += 1
		local acc = ACCENTS[((order - 1) % #ACCENTS) + 1]
		local card, row = UITheme.accentCard(shopList, acc[1], 14)
		row.Size = UDim2.new(1, -12, 0, 84)
		row.LayoutOrder = order
		row.ZIndex = 11
		card.ZIndex = 12

		-- icon tile: sunburst backdrop with the rock colour as the medallion dot
		local icon = Instance.new("Frame")
		icon.Size = UDim2.fromOffset(56, 56)
		icon.Position = UDim2.new(0, 12, 0.5, -28)
		icon.BackgroundColor3 = P.white
		icon.BorderSizePixel = 0
		icon.ClipsDescendants = true
		icon.ZIndex = card.ZIndex + 1
		icon.Parent = card
		UITheme.corner(icon, 10)
		UITheme.sunburst(icon, acc[1], 12)
		UITheme.ink(icon, 3)

		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.5, 0.5)
		dot.Size = UDim2.fromOffset(34, 34)
		dot.BackgroundColor3 = rock.Color
		dot.BorderSizePixel = 0
		dot.ZIndex = icon.ZIndex + 3
		dot.Parent = icon
		UITheme.corner(dot, 17)
		UITheme.ink(dot, 2.5)
		UITheme.gloss(dot, 16, 0.55)

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, -204, 0, 24)
		title.Position = UDim2.new(0, 80, 0, 12)
		title.BackgroundTransparency = 1
		title.Text = rock.Id
		title.TextColor3 = acc[1]
		title.Font = FONT
		title.TextSize = 18
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextTruncate = Enum.TextTruncate.AtEnd
		title.ZIndex = card.ZIndex + 2
		title.Parent = card
		UITheme.inkText(title, 2.8)

		local subtitle = Instance.new("TextLabel")
		subtitle.Size = UDim2.new(1, -204, 0, 18)
		subtitle.Position = UDim2.new(0, 80, 0, 40)
		subtitle.BackgroundTransparency = 1
		subtitle.Text = "Up to " .. rock.MaxDistance .. "m   \u{2022}   " .. string.format("%.2fx", rock.Luck) .. " luck"
		subtitle.TextColor3 = CF.muted
		subtitle.Font = Enum.Font.GothamMedium
		subtitle.TextSize = 13
		subtitle.TextXAlignment = Enum.TextXAlignment.Left
		subtitle.TextTruncate = Enum.TextTruncate.AtEnd
		subtitle.ZIndex = card.ZIndex + 2
		subtitle.Parent = card
		UITheme.inkText(subtitle, 1.6)

		local actionButton = Instance.new("TextButton")
		actionButton.AnchorPoint = Vector2.new(1, 0.5)
		actionButton.Size = UDim2.new(0, 104, 0, 42)
		actionButton.Position = UDim2.new(1, -12, 0.5, 0)
		actionButton.TextSize = 17
		actionButton.ZIndex = card.ZIndex + 2
		actionButton.Parent = card

		actionButton.MouseButton1Click:Connect(function()
			if state.OwnedRocks[rock.Id] then
				if state.EquippedRock ~= rock.Id then
					remotes.EquipRock:FireServer(rock.Id)
				end
			else
				remotes.BuyRock:FireServer(rock.Id)
			end
		end)

		rockRows[rock.Id] = { row = row, button = actionButton, price = rock.Price }
	end

	refreshShopButtons()
end

function refreshShopButtons()
	for id, entry in pairs(rockRows) do
		local owned = state.OwnedRocks[id]
		local equipped = state.EquippedRock == id
		if equipped then
			UITheme.campButton(entry.button, CF.pine1, CF.pine2)
			entry.button.Text = "EQUIPPED"
			entry.button.TextSize = 15
		elseif owned then
			UITheme.campButton(entry.button, CF.lake1, CF.lake2)
			entry.button.Text = "EQUIP"
			entry.button.TextSize = 17
		else
			UITheme.campButton(entry.button, CF.amber1, CF.amber2)
			entry.button.Text = "$" .. formatNumber(entry.price)
			entry.button.TextSize = 17
		end
	end
end

buildShop()

shopCloseButton.MouseButton1Click:Connect(function()
	shopFrame.Visible = false
end)

-- === Sell ===
local function buildSellList()
	for _, child in ipairs(sellList:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	local counts = {}
	local order = {}
	-- Inventory only. A brainrot placed on the base (PadIndex set) is earning
	-- and is not for sale until it is picked up, so it must not be counted here
	-- either -- otherwise the list offers more than the server will sell.
	for _, entry in ipairs(state.Brainrots) do
		if entry.PadIndex == nil then
			if not counts[entry.Name] then
				counts[entry.Name] = 0
				table.insert(order, entry.Name)
			end
			counts[entry.Name] += 1
		end
	end

	sellEmptyLabel.Visible = #order == 0

	for i, name in ipairs(order) do
		local count = counts[name]
		local info = brainrotInfoByName[name]
		if info then
			local tier = tierByName[info.Rarity]
			local sellValueEach = info.CashPerSecond * SELL_MULTIPLIER
			local acc = ACCENTS[((i - 1) % #ACCENTS) + 1]

			local card, row = UITheme.accentCard(sellList, acc[1], 14)
			row.Size = UDim2.new(1, -12, 0, 84)
			row.LayoutOrder = i
			row.ZIndex = 11
			card.ZIndex = 12

			-- icon tile: sunburst backdrop, tier colour now on the tile's border
			-- (matches the backpack grid), with the real 3D brainrot inside
			local icon = Instance.new("Frame")
			icon.Size = UDim2.fromOffset(56, 56)
			icon.Position = UDim2.new(0, 12, 0.5, -28)
			icon.BackgroundColor3 = P.white
			icon.BorderSizePixel = 0
			icon.ClipsDescendants = true
			icon.ZIndex = card.ZIndex + 1
			icon.Parent = card
			UITheme.corner(icon, 10)
			UITheme.sunburst(icon, acc[1], 12)
			UITheme.stroke(icon, tier and tier.Color or CF.ink, 3)

			-- the actual 3D brainrot, matching the backpack grid and catch reveal
			local vp = BrainrotThumb.add(icon, name, {
				size = UDim2.new(1, -8, 1, -8),
				position = UDim2.new(0, 4, 0, 4),
				zIndex = icon.ZIndex + 3,
			})
			if not vp then
				-- no model for this name (Maxwell, at time of writing): keep the old
				-- flat rarity swatch so the tile is never blank and selling still works
				local dot = Instance.new("Frame")
				dot.AnchorPoint = Vector2.new(0.5, 0.5)
				dot.Position = UDim2.fromScale(0.5, 0.5)
				dot.Size = UDim2.fromOffset(34, 34)
				dot.BackgroundColor3 = tier and tier.Color or Color3.fromRGB(255, 255, 255)
				dot.BorderSizePixel = 0
				dot.ZIndex = icon.ZIndex + 3
				dot.Parent = icon
				UITheme.corner(dot, 17)
				UITheme.ink(dot, 2.5)
				UITheme.gloss(dot, 16, 0.55)
			end

			local title = Instance.new("TextLabel")
			title.Size = UDim2.new(1, -204, 0, 24)
			title.Position = UDim2.new(0, 80, 0, 12)
			title.BackgroundTransparency = 1
			title.Text = name
			title.TextColor3 = acc[1]
			title.Font = FONT
			title.TextSize = 17
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextTruncate = Enum.TextTruncate.AtEnd
			title.ZIndex = card.ZIndex + 2
			title.Parent = card
			UITheme.inkText(title, 2.8)

			local subtitle = Instance.new("TextLabel")
			subtitle.Size = UDim2.new(1, -204, 0, 18)
			subtitle.Position = UDim2.new(0, 80, 0, 40)
			subtitle.BackgroundTransparency = 1
			subtitle.Text = "\u{00D7}" .. count .. "   \u{2022}   $" .. formatNumber(sellValueEach) .. " each"
			subtitle.TextColor3 = CF.muted
			subtitle.Font = Enum.Font.GothamMedium
			subtitle.TextSize = 13
			subtitle.TextXAlignment = Enum.TextXAlignment.Left
			subtitle.TextTruncate = Enum.TextTruncate.AtEnd
			subtitle.ZIndex = card.ZIndex + 2
			subtitle.Parent = card
			UITheme.inkText(subtitle, 1.6)

			local sellOneButton = Instance.new("TextButton")
			sellOneButton.AnchorPoint = Vector2.new(1, 0)
			sellOneButton.Size = UDim2.new(0, 104, 0, 32)
			sellOneButton.Position = UDim2.new(1, -12, 0, 6)
			sellOneButton.Text = "SELL 1"
			sellOneButton.TextSize = 15
			sellOneButton.ZIndex = card.ZIndex + 2
			sellOneButton.Parent = card
			UITheme.campButton(sellOneButton, CF.pine1, CF.pine2)

			local sellAllButton = Instance.new("TextButton")
			sellAllButton.AnchorPoint = Vector2.new(1, 0)
			sellAllButton.Size = UDim2.new(0, 104, 0, 32)
			sellAllButton.Position = UDim2.new(1, -12, 0, 42)
			sellAllButton.Text = "SELL ALL"
			sellAllButton.TextSize = 15
			sellAllButton.ZIndex = card.ZIndex + 2
			sellAllButton.Parent = card
			UITheme.campButton(sellAllButton, CF.amber1, CF.amber2)

			sellOneButton.MouseButton1Click:Connect(function()
				remotes.SellBrainrot:FireServer({ Name = name, Mode = "One" })
			end)
			sellAllButton.MouseButton1Click:Connect(function()
				remotes.SellBrainrot:FireServer({ Name = name, Mode = "All" })
			end)
		end
	end
end

sellCloseButton.MouseButton1Click:Connect(function()
	sellFrame.Visible = false
end)

-- === Walk-up shop + sell stalls (ProximityPrompt) ===
local gameWorld = Workspace:WaitForChild("GameWorld")
local shopStall = gameWorld:WaitForChild("ShopStall")
local shopPromptPart = shopStall:WaitForChild("PromptPart")
local shopPrompt = shopPromptPart:WaitForChild("ShopPrompt")
local sellStall = gameWorld:WaitForChild("SellStall")
local sellPromptPart = sellStall:WaitForChild("PromptPart")
local sellPrompt = sellPromptPart:WaitForChild("SellPrompt")

-- Rock shop is served by the unified MerchantClient panel (see MerchantClient LocalScript).

sellPrompt.Triggered:Connect(function(triggeringPlayer)
	if triggeringPlayer ~= player then return end
	if sellFrame.Visible then
		sellFrame.Visible = false
		return
	end
	-- Coin jingle on the way in. Marco is deliberately NOT a MerchantConfig
	-- merchant (he keeps his own sell menu, so MerchantClient's shared panel and
	-- its EnterSound field don't apply to him), which is why this is wired here
	-- rather than off a config field -- but the id still lives in SoundKit like
	-- every other sound in the game. Sits BELOW the close-toggle return above so
	-- the coins never jingle on the way out.
	SoundKit.play("shopCoins", nil, { volume = 0.4 })
	-- E starts a short dialogue; the sell menu opens when the player continues
	MerchantDialog.Show("Marco the Buyer", {
		"Brainrots to sell? I pay top dollar!",
	}, { CF.amber1, CF.amber2 }, function()
		buildSellList()
		sellFrame.Visible = true
		shopFrame.Visible = false
	end, sellPromptPart)
end)

-- auto-close if the player wanders away from a stall
RunService.Heartbeat:Connect(function()
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	if shopFrame.Visible then
		local distance = (hrp.Position - shopPromptPart.Position).Magnitude
		if distance > 20 then
			shopFrame.Visible = false
		end
	end

	if sellFrame.Visible then
		local distance = (hrp.Position - sellPromptPart.Position).Magnitude
		if distance > 20 then
			sellFrame.Visible = false
		end
	end
end)

-- === Data sync ===
local function applySnapshot(snapshot)
	if not snapshot then return end
	state.Cash = snapshot.Cash or state.Cash
	state.OwnedRocks = snapshot.OwnedRocks or state.OwnedRocks
	state.EquippedRock = snapshot.EquippedRock or state.EquippedRock
	state.Brainrots = snapshot.Brainrots or state.Brainrots
	snapCashLabel()
	refreshShopButtons()
	if sellFrame.Visible then
		buildSellList()
	end
end

task.spawn(function()
	local snapshot = remotes.GetInitialData:InvokeServer()
	applySnapshot(snapshot)
end)

remotes.DataUpdated.OnClientEvent:Connect(applySnapshot)

remotes.CashTick.OnClientEvent:Connect(function(newCash)
	state.Cash = newCash      -- the Heartbeat lerp animates toward it
end)

remotes.PurchaseResult.OnClientEvent:Connect(function(result)
	-- lightweight feedback handled by DataUpdated refresh; nothing else needed for MVP
end)

remotes.SellResult.OnClientEvent:Connect(function(result)
	-- lightweight feedback handled by DataUpdated refresh; nothing else needed for MVP
	if result and result.Success and result.Amount then SoundKit.play("cash", nil, { volume = 0.25 }) end -- SFX2
end)

-- === Catch celebration VFX (scales with rarity; big mutations promote the tier) ===
local rarityIndexByName = {}
for i, tier in ipairs(RarityConfig) do rarityIndexByName[tier.Name] = i end

local camera = Workspace.CurrentCamera
local BASE_FOV = camera.FieldOfView

local function shakeCamera(intensity, duration)
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local el = os.clock() - t0
		if el >= duration then
			conn:Disconnect()
			return
		end
		local mag = intensity * (1 - el / duration)
		camera.CFrame = camera.CFrame * CFrame.Angles((math.random() - 0.5) * mag, (math.random() - 0.5) * mag, 0)
	end)
end

local function fovPunch(amount, backTime)
	camera.FieldOfView = BASE_FOV - amount
	TweenService:Create(camera, TweenInfo.new(backTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = BASE_FOV }):Play()
end

local function spawnRevealPillar(color, scale)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local pillar = Instance.new("Part")
	pillar.Name = "CatchPillar"
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Size = Vector3.new(34 * scale, 5 * scale, 5 * scale)
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.Material = Enum.Material.Neon
	pillar.Color = color
	pillar.Transparency = 0.25
	pillar.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 14 * scale, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pillar.Parent = Workspace

	local sparkAttach = Instance.new("Attachment")
	sparkAttach.Position = Vector3.new(0, 0, 0)
	sparkAttach.Parent = pillar
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(color)
	sparks.LightEmission = 1
	sparks.Lifetime = NumberRange.new(0.5, 1.1)
	sparks.Speed = NumberRange.new(8, 16)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new(0.1)
	sparks.Rate = 0
	sparks.Parent = sparkAttach
	sparks:Emit(math.floor(25 * scale))

	TweenService:Create(pillar, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Transparency = 1,
		Size = Vector3.new(34 * scale, 1.2, 1.2),
	}):Play()
	game:GetService("Debris"):AddItem(pillar, 1.4)
end

local celebrateSound = Instance.new("Sound")
celebrateSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
celebrateSound.Parent = gui

local function celebrateCatch(rarityName, mutation)
	local idx = rarityIndexByName[rarityName] or 1
	-- Band 4 locks the camera onto a world model, so the pillar spawned around
	-- the character would be off-screen and a shake would fight the lock.
	if rarityName == "Secret" or rarityName == "God" then return end
	-- Rainbow/Glitched mutations always celebrate at least Legendary-sized
	if mutation == "Rainbow" or mutation == "Glitched" then
		idx = math.max(idx, 5)
	end
	if idx < 3 then return end

	local tier = tierByName[rarityName]
	local color = (tier and tier.Color) or Color3.fromRGB(255, 255, 255)
	local scale = 0.7 + (idx - 3) * 0.28

	celebrateSound.PlaybackSpeed = math.clamp(1.5 - (idx - 3) * 0.14, 0.8, 1.5)
	celebrateSound.Volume = math.clamp(0.3 + idx * 0.08, 0, 1)
	celebrateSound:Play()

	if idx >= 3 then fovPunch(3 + idx, 0.55) end
	if idx >= 4 then
		spawnRevealPillar(color, scale)
		shakeCamera(0.012 * idx, 0.3 + idx * 0.06)
	end
end

-- === Throw result popup ===
-- Campfire card: warm two-tone body, heavy black rim, outlined glyphs. UIStroke
-- carries its own Transparency (it does NOT follow BackgroundTransparency or
-- TextTransparency), so the outlines are collected here and faded with the popup.
local resultInk = {}
do
	resultFrame.ZIndex = 20
	resultFrame.BackgroundColor3 = P.white
	resultFrame.BorderSizePixel = 0
	UITheme.corner(resultFrame, 16)
	UITheme.gradient(resultFrame, CF.panelTop, CF.panelBot, 90)
	table.insert(resultInk, UITheme.ink(resultFrame, 4))

	rarityLabel.Font = FONT          -- colour stays driven by result.RarityColor
	rarityLabel.TextSize = 20
	rarityLabel.ZIndex = 21
	table.insert(resultInk, UITheme.inkText(rarityLabel, 3))

	nameLabel.Font = FONT
	nameLabel.TextColor3 = CF.cream
	nameLabel.ZIndex = 21
	table.insert(resultInk, UITheme.inkText(nameLabel, 2.6))

	infoLabel.Font = Enum.Font.GothamMedium
	infoLabel.TextColor3 = CF.muted
	infoLabel.ZIndex = 21
	table.insert(resultInk, UITheme.inkText(infoLabel, 1.8))
end

local resultScale = Instance.new("UIScale")
resultScale.Parent = resultFrame
local resultToken = 0
remotes.ThrowResult.OnClientEvent:Connect(function(result)
	resultToken += 1
	local myToken = resultToken

	-- The card is retired: CatchRevealClient now shows the caught brainrot
	-- itself, spinning, instead of describing it in text. The frame and its
	-- styling are left in place so this is a one-block revert.
	celebrateCatch(result.Rarity, result.Mutation)
	if true then return end

	rarityLabel.Text = string.upper(result.Rarity)
	rarityLabel.TextColor3 = result.RarityColor
	nameLabel.Text = result.BrainrotName
	infoLabel.Text = ("Distance: %dm  |  +%s/s"):format(result.Distance, formatNumber(result.CashPerSecond))

	resultFrame.Visible = true
	resultScale.Scale = 0.6
	TweenService:Create(resultScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	resultFrame.BackgroundTransparency = 1
	local labels = { rarityLabel, nameLabel, infoLabel }
	for _, l in ipairs(labels) do l.TextTransparency = 1 end
	for _, s in ipairs(resultInk) do s.Transparency = 1 end

	TweenService:Create(resultFrame, TweenInfo.new(0.25), { BackgroundTransparency = 0.15 }):Play()
	for _, l in ipairs(labels) do
		TweenService:Create(l, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
	end
	for _, s in ipairs(resultInk) do
		TweenService:Create(s, TweenInfo.new(0.25), { Transparency = 0 }):Play()
	end

	task.delay(2.5, function()
		if myToken ~= resultToken then return end
		TweenService:Create(resultFrame, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		for _, l in ipairs(labels) do
			TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		end
		for _, s in ipairs(resultInk) do
			TweenService:Create(s, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		end
		task.delay(0.4, function()
			if myToken == resultToken then
				resultFrame.Visible = false
			end
		end)
	end)
end)

-- === Charge + throw ===
-- FIXED "sweet spot": a slim green strip pinned to the END of the charge bar. It
-- used to jump to a new spot every time the minigame loaded; it no longer moves,
-- so the perfect release is always the full-power release.
-- The band is still SERVER-ISSUED (GetSweetSpot) and judged server-side against
-- the released power; this side only draws where it is told. Until the server
-- answers there is no band: the sentinels below can never match a real power value.
local BAND_WIDTH = 0.07
local perfectMin, perfectMax = -1, -1

local perfectBand = Instance.new("Frame")
perfectBand.Name = "PerfectBand"
perfectBand.Size = UDim2.new(BAND_WIDTH, 0, 1, 0)
perfectBand.Position = UDim2.new(perfectMin, 0, 0, 0)
perfectBand.BackgroundColor3 = P.white
perfectBand.BackgroundTransparency = 0
perfectBand.BorderSizePixel = 0
perfectBand.ZIndex = barFill.ZIndex + 2
perfectBand.Parent = throwFrame.BarBackground
do
	-- sweet-spot strip: pine two-tone + black outline (size/position stay driven
	-- by refreshSweetSpot and BAND_WIDTH)
	UITheme.corner(perfectBand, 6)
	UITheme.gradient(perfectBand, CF.pine1, CF.pine2, 90)
	UITheme.ink(perfectBand, 2)
end

-- Ask the server for a fresh band and draw whatever it says. A failed or slow
-- fetch just means no band this throw (no perfect chance), never an error --
-- and the token guard stops a stale answer from overdrawing a newer one.
local bandToken = 0
local function refreshSweetSpot()
	bandToken += 1
	local myToken = bandToken
	perfectMin, perfectMax = -1, -1
	perfectBand.Visible = false
	task.spawn(function()
		local ok, band = pcall(function()
			local rf = remotes:WaitForChild("GetSweetSpot", 10)
			return rf and rf:InvokeServer() or nil
		end)
		if not ok or type(band) ~= "table" or myToken ~= bandToken then return end
		perfectMin, perfectMax = band.min, band.max
		perfectBand.Position = UDim2.new(perfectMin, 0, 0, 0)
		perfectBand.Size = UDim2.new(perfectMax - perfectMin, 0, 1, 0)
		perfectBand.Visible = true
	end)
end
refreshSweetSpot()

-- === Campfire theme for the skip minigame panel (carved sign + charge groove) ===
-- ZIndex is deliberately left alone in here: MainUI is Global ZIndexBehavior and
-- every child of this panel sits at 1-3, so lifting the frame would bury them.
do
	local GROOVE_TOP = Color3.fromRGB(58, 39, 26)
	local GROOVE_BOT = Color3.fromRGB(30, 20, 13)

	-- panel -> carved wooden sign
	throwFrame.BackgroundColor3 = P.white
	throwFrame.BackgroundTransparency = 0
	throwFrame.BorderSizePixel = 0
	UITheme.corner(throwFrame, 16)
	UITheme.gradient(throwFrame, CF.wood1, CF.wood2, 90)
	blackRim(throwFrame, 4)
	local fgloss = throwFrame:FindFirstChild("Gloss")
	if fgloss then
		local gg = fgloss:FindFirstChildOfClass("UIGradient")
		-- keep the sheen weak or the wood washes out to beige
		if gg then gg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.86), NumberSequenceKeypoint.new(1, 1) }) end
	end

	-- charge groove -> recessed earth
	local barBg = throwFrame.BarBackground
	barBg.BackgroundColor3 = P.white
	barBg.BorderSizePixel = 0
	UITheme.gradient(barBg, GROOVE_TOP, GROOVE_BOT, 90)
	blackRim(barBg, 2.5)
	local bc = barBg:FindFirstChildOfClass("UICorner"); if bc then bc.CornerRadius = UDim.new(1, 0) end

	-- fill -> rounded + soft sheen (keeps the red->green power ramp). The fill is
	-- resized every frame from 0 width, so it gets no outline of its own -- the
	-- groove's black rim reads as the outline instead.
	local fillC = barFill:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	fillC.CornerRadius = UDim.new(1, 0); fillC.Parent = barFill
	if not barFill:FindFirstChild("Sheen") then
		local sheen = Instance.new("Frame")
		sheen.Name = "Sheen"; sheen.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		sheen.BackgroundTransparency = 0.72; sheen.BorderSizePixel = 0
		sheen.Size = UDim2.new(1, 0, 0.42, 0); sheen.ZIndex = barFill.ZIndex + 1
		local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(1, 0); sc.Parent = sheen
		sheen.Parent = barFill
	end

	-- chunky pill button. UITheme.setColors keeps driving the state colours from
	-- releaseThrow / the throw-zone gate, so only the chrome changes here.
	throwButton.TextSize = 18
	UITheme.campButton(throwButton, UITheme.Palette.hudThrow1, UITheme.Palette.hudThrow2)
	blackRim(throwButton, 3)
	inkTextOnce(throwButton, 2.6)
	local bgloss = throwButton:FindFirstChild("Gloss")
	if bgloss then
		local gg = bgloss:FindFirstChildOfClass("UIGradient")
		if gg then gg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.72), NumberSequenceKeypoint.new(1, 1) }) end
	end
end

-- ============================= PERFECT SKIP POPUP =============================
-- Its OWN ScreenGui rather than a label inside ThrowFrame, which is where this used to
-- live. Parented to the throw HUD it was a 21px line of green text pinned above the power
-- bar -- easy to miss entirely, and it inherited the HUD's scale and clipping. A perfect
-- is now a rare thing you had to aim for (the band moved off the top of the bar), so it
-- gets the middle of the screen and its own DisplayOrder.
local PERFECT_GOLD = Color3.fromRGB(255, 214, 56)
local PERFECT_AMBER = Color3.fromRGB(255, 150, 24)

local perfectGui = Instance.new("ScreenGui")
perfectGui.Name = "PerfectPopUI"
perfectGui.ResetOnSpawn = false
perfectGui.IgnoreGuiInset = true
perfectGui.DisplayOrder = 30
perfectGui.Parent = player:WaitForChild("PlayerGui")

local perfectRoot = Instance.new("Frame")
perfectRoot.Name = "Root"
perfectRoot.Size = UDim2.fromOffset(620, 200)
perfectRoot.AnchorPoint = Vector2.new(0.5, 0.5)
perfectRoot.Position = UDim2.new(0.5, 0, 0.34, 0)   -- above centre, clear of the crosshair
perfectRoot.BackgroundTransparency = 1
perfectRoot.Visible = false
perfectRoot.Parent = perfectGui
local perfectScale = Instance.new("UIScale")
perfectScale.Parent = perfectRoot

-- Sunburst. 12 bars at 15 degrees covers a full starburst, not a half one: a rectangle
-- rotated 180 degrees is the same rectangle, so 12 x 15 = 180 is the whole fan.
local burst = Instance.new("Frame")
burst.Name = "Burst"
burst.Size = UDim2.fromOffset(230, 230)
burst.AnchorPoint = Vector2.new(0.5, 0.5)
burst.Position = UDim2.fromScale(0.5, 0.5)
burst.BackgroundTransparency = 1
burst.Parent = perfectRoot
local burstScale = Instance.new("UIScale")
burstScale.Parent = burst
local rays = {}
for i = 1, 12 do
	local ray = Instance.new("Frame")
	ray.AnchorPoint = Vector2.new(0.5, 0.5)
	ray.Position = UDim2.fromScale(0.5, 0.5)
	ray.Size = UDim2.fromOffset(i % 2 == 0 and 5 or 9, i % 2 == 0 and 150 or 210)
	ray.Rotation = (i - 1) * 15
	ray.BackgroundColor3 = PERFECT_GOLD
	ray.BorderSizePixel = 0
	ray.ZIndex = 1
	ray.Parent = burst
	rays[#rays + 1] = ray
end

local perfectText = Instance.new("TextLabel")
perfectText.Name = "Big"
perfectText.Size = UDim2.new(1, 0, 0, 92)
perfectText.Position = UDim2.new(0, 0, 0, 34)
perfectText.BackgroundTransparency = 1
perfectText.Font = Enum.Font.FredokaOne
perfectText.TextSize = 80
perfectText.Text = "PERFECT!"
perfectText.TextColor3 = PERFECT_GOLD
perfectText.ZIndex = 3
perfectText.Parent = perfectRoot
-- UIGradient tints TEXT on a TextLabel, so this is the gold-to-amber fall without
-- needing two stacked labels.
local textGrad = Instance.new("UIGradient")
textGrad.Color = ColorSequence.new(PERFECT_GOLD, PERFECT_AMBER)
textGrad.Rotation = 90
textGrad.Parent = perfectText
UITheme.inkText(perfectText, 6)

local perfectSub = Instance.new("TextLabel")
perfectSub.Name = "Sub"
perfectSub.Size = UDim2.new(1, 0, 0, 26)
perfectSub.Position = UDim2.new(0, 0, 0, 124)
perfectSub.BackgroundTransparency = 1
perfectSub.Font = FONT
perfectSub.TextSize = 22
-- the real multipliers, from ThrowHandler's PERFECT_DISTANCE_MULT / PERFECT_LUCK_MULT
perfectSub.Text = "+10% DISTANCE   \u{2022}   +7.5% LUCK"
perfectSub.TextColor3 = Color3.fromRGB(255, 240, 200)
perfectSub.ZIndex = 3
perfectSub.Parent = perfectRoot
UITheme.inkText(perfectSub, 3)

-- Sparks, reused rather than rebuilt: this fires on a throw cooldown, so churning
-- instances every time would be pointless garbage.
local sparks = {}
for i = 1, 10 do
	local s = Instance.new("Frame")
	s.AnchorPoint = Vector2.new(0.5, 0.5)
	s.Position = UDim2.fromScale(0.5, 0.5)
	s.Size = UDim2.fromOffset(10, 10)
	s.Rotation = 45
	s.BackgroundColor3 = i % 3 == 0 and Color3.fromRGB(255, 255, 255) or PERFECT_GOLD
	s.BorderSizePixel = 0
	s.ZIndex = 2
	s.Visible = false
	s.Parent = perfectRoot
	sparks[#sparks + 1] = s
end

local perfectPopToken = 0
local function showPerfectPop()
	perfectPopToken += 1
	local myToken = perfectPopToken

	-- reset every animated property, or a second perfect mid-fade inherits the tail of
	-- the first and reads as a flicker
	perfectRoot.Visible = true
	perfectRoot.Position = UDim2.new(0.5, 0, 0.34, 0)
	perfectScale.Scale = 0.45
	perfectText.Rotation = -9
	perfectText.TextTransparency = 0
	perfectSub.TextTransparency = 0
	for _, st in ipairs(perfectText:GetChildren()) do
		if st:IsA("UIStroke") then st.Transparency = 0 end
	end
	for _, st in ipairs(perfectSub:GetChildren()) do
		if st:IsA("UIStroke") then st.Transparency = 0 end
	end
	burstScale.Scale = 0.35
	for _, r in ipairs(rays) do r.BackgroundTransparency = 0.15 end

	-- punch in past 1 and settle back: the overshoot is what gives it weight
	TweenService:Create(perfectScale, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1.12 }):Play()
	TweenService:Create(perfectText, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Rotation = 0 }):Play()
	task.delay(0.26, function()
		if myToken ~= perfectPopToken then return end
		TweenService:Create(perfectScale, TweenInfo.new(0.14, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
	end)

	-- burst blooms outward and fades, so it reads as a flash rather than furniture
	TweenService:Create(burstScale, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Scale = 1.75 }):Play()
	for _, r in ipairs(rays) do
		TweenService:Create(r, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }):Play()
	end

	-- sparks fly out on their own headings
	for i, s in ipairs(sparks) do
		local ang = (i / #sparks) * math.pi * 2 + math.random() * 0.4
		local dist = 120 + math.random() * 90
		s.Visible = true
		s.Position = UDim2.fromScale(0.5, 0.5)
		s.Size = UDim2.fromOffset(11, 11)
		s.BackgroundTransparency = 0
		TweenService:Create(s, TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, math.cos(ang) * dist, 0.5, math.sin(ang) * dist),
			Size = UDim2.fromOffset(0, 0),
			BackgroundTransparency = 1,
			Rotation = 225,
		}):Play()
	end

	-- a little physical feedback; both helpers already exist above for the catch reveal
	fovPunch(2.5, 0.4)
	shakeCamera(0.006, 0.18)

	-- hold, then drift up and out
	task.delay(0.62, function()
		if myToken ~= perfectPopToken then return end
		local ti = TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(perfectRoot, ti, { Position = UDim2.new(0.5, 0, 0.27, 0) }):Play()
		TweenService:Create(perfectText, ti, { TextTransparency = 1 }):Play()
		TweenService:Create(perfectSub, ti, { TextTransparency = 1 }):Play()
		for _, lbl in ipairs({ perfectText, perfectSub }) do
			for _, st in ipairs(lbl:GetChildren()) do
				if st:IsA("UIStroke") then TweenService:Create(st, ti, { Transparency = 1 }):Play() end
			end
		end
		task.delay(0.45, function()
			if myToken == perfectPopToken then
				perfectRoot.Visible = false
				for _, s in ipairs(sparks) do s.Visible = false end
			end
		end)
	end)
end

local charging = false
local power = 0
local cooldown = false
local CYCLE_SECONDS = 1.1
-- The bar's period is RE-ROLLED on every charge rather than being the flat 1.1s it used
-- to be. A fixed period made the bar a metronome: hold for a known number of
-- milliseconds and you land on the same point every single time, which is the whole of
-- what a macro needs. Re-rolling per charge means a fixed-cadence macro cannot know
-- where the bar is at the moment it releases, so it cannot be set up overnight.
local CYCLE_MIN_MULT, CYCLE_MAX_MULT = 0.62, 1.55
local chargeStart = 0
local chargePeriod = CYCLE_SECONDS
local MAX_FLIGHT_SECONDS = 4.2   -- mirrors the upper clamp in ThrowHandler

-- The bar stays locked from release until the stone has actually SETTLED, not for a
-- fixed 1.1s. Flight is up to 4.2s, so the old timer freed the bar mid-skip and a held
-- button could queue throw after throw. The server enforces one-stone-at-a-time too;
-- this half just keeps the UI honest about it.
local throwToken = 0

-- Set by the stone-tracking camera further down. The bar must not reopen while the
-- camera is still out over the water: handing control back mid-flyback reads as a
-- glitch, and the player cannot aim at something they are not looking at.
local cameraTracking = false

-- force: last-resort release that ignores the camera, so a camera that never restores
-- cannot strand the player unable to throw.
local function unlockThrow(token, force)
	if token and token ~= throwToken then return end   -- a newer throw owns the bar now
	if not cooldown then return end
	if cameraTracking and not force then return end    -- wait for the camera to come home
	cooldown = false
	power = 0
	barFill.Size = UDim2.new(0, 0, 1, 0)
	throwButton.Text = DEFAULT_THROW_TEXT
	UITheme.setColors(throwButton, UITheme.Palette.hudThrow1, UITheme.Palette.hudThrow2)
	refreshSweetSpot() -- re-arm the (single-use) band for the next attempt
end

local inThrowZone = false

-- A player must own a base before they can skip. Ownership is read live from the
-- plot's replicated OwnerUserId attribute (set server-side on claim).
local function playerHasPlot()
	local bases = Workspace:FindFirstChild("PlayerBases")
	if not bases then return false end
	for _, plot in ipairs(bases:GetChildren()) do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			return true
		end
	end
	return false
end

-- forward declarations: the wind-up system is defined just below, but startCharge and
-- the RenderStepped driver both sit above it in this file
local beginWindup, driveWindup, endWindup

local function startCharge()
	if cooldown or charging then return end
	if not inThrowZone then return end
	if not playerHasPlot() then return end -- no base yet; button acts as "get a plot" instead
	charging = true
	-- roll this charge's own bar speed (see CYCLE_MIN_MULT above)
	chargeStart = os.clock()
	chargePeriod = CYCLE_SECONDS * (CYCLE_MIN_MULT + math.random() * (CYCLE_MAX_MULT - CYCLE_MIN_MULT))
	beginWindup()
end

-- ============================ THROW WIND-UP + RELEASE ============================
-- Procedural full-body posing, written straight to the rig's joints every frame.
--
-- WHY NOT KeyframeSequence: this character is a CONSTRAINT rig -- 15 AnimationConstraints,
-- 14 BallSocketConstraints, and ZERO Motor6D. Runtime-registered KeyframeSequences resolve
-- their Poses through Motor6D, so on this rig they apply to NOTHING. Measured in this
-- place: posing by part name (RightUpperArm) and by joint name (RightShoulder) each moved
-- the arm 0.0 degrees, while the track itself reported weight 1.00 and scrubbed its
-- TimePosition perfectly. The original throw animation used exactly that approach wrapped
-- in a pcall -- which is why it silently did nothing at all.
--
-- WHAT DOES WORK: AnimationConstraint.Transform is writable. Driving RightShoulder moved
-- the arm 2.7 -> 120.0 degrees (measured), and it snapped back the moment we stopped. The
-- Animator rewrites Transform every frame, so a pose must be REWRITTEN every frame.
--
-- THE PHASE MATTERS, AND ONLY ONE WORKS. Measured all five on this rig, writing the same
-- CFrame to RightShoulder and reading the resulting arm angle:
--     RenderStepped    2.3 deg   overwritten
--     Stepped        147.2 deg   <-- WINS
--     Heartbeat        3.8 deg   overwritten
--     PreAnimation     3.0 deg   overwritten
--     PostSimulation   3.6 deg   overwritten
-- The Animator evaluates after every phase except Stepped, so anywhere else the write is
-- discarded within the same frame. `power` is still computed in the existing RenderStepped
-- loop; that loop only RECORDS the wanted pose, and the Stepped driver below applies it.
--
-- This also suits the mechanic better than any clip. The charge bar is a 1.1s SINE, so
-- mapping `power` straight onto joint angles makes the body literally be the bar, with no
-- clip length or playback speed to keep in sync.
local throwAnimActive = false

local function A(x, y, z)
	return CFrame.Angles(math.rad(x or 0), math.rad(y or 0), math.rad(z or 0))
end

-- Keys are AnimationConstraint names on the rig: Root Waist Neck, Left/RightShoulder,
-- Left/RightElbow, Left/RightWrist, Left/RightHip, Left/RightKnee, Left/RightAnkle.
-- A throw is a kinetic chain -- legs brace, hips and ribs coil, the arm arrives last --
-- so the whole body is keyed rather than just the throwing arm.
--
-- SIGN CONVENTION, measured on this rig rather than assumed (+40 deg on each joint's X
-- and reading the limb's world direction against the torso's LookVector):
--     +X on ANY shoulder / hip / knee  ->  that limb swings FORWARD
--     +Y on Waist                      ->  the RIGHT shoulder swings FORWARD
-- Two consequences that were wrong in the first pass and made the whole throw read
-- backwards:
--   * The off arm must OPPOSE the throwing arm, so LeftShoulder takes the OPPOSITE sign
--     to RightShoulder at every key. Matching signs made both arms reach back together
--     and then both swing forward, which is not a throw.
--   * A knee bends with the shin travelling BACKWARD, so every knee value is NEGATIVE.
--     Positive knee values bent the legs the wrong way entirely.
local WOUND = {
	Waist         = A(14, -30, 0),   -- -Y: right shoulder rotates AWAY from the target
	Neck          = A(-4, 26, 0),    -- counter-twist so the eyes stay on the lake
	RightShoulder = A(-150, 0, 14),  -- -X: throwing arm cocked BACK and out
	RightElbow    = A(-70, 0, 0),    -- elbow folded
	LeftShoulder  = A(44, 0, -24),   -- +X: off arm comes FORWARD across the chest
	LeftElbow     = A(-28, 0, 0),
	RightHip      = A(-14, 0, 0),    -- weight settles onto the back leg
	RightKnee     = A(-24, 0, 0),    -- back knee BENDS to take it
	LeftHip       = A(10, 0, 0),     -- front leg straightens and braces
	LeftKnee      = A(-6, 0, 0),
}
local WHIP = {
	Waist         = A(-22, 26, 0),   -- +Y: shoulders fire through toward the target
	Neck          = A(-8, -10, 0),   -- head snaps out after the stone
	RightShoulder = A(95, 0, -10),   -- +X: throwing arm drives FORWARD
	RightElbow    = A(-8, 0, 0),     -- elbow straightens as it releases
	LeftShoulder  = A(-26, 0, 16),   -- -X: off arm drives BACK, opposing the throw
	LeftElbow     = A(-8, 0, 0),
	RightHip      = A(14, 0, 0),     -- back leg comes through onto the front foot
	RightKnee     = A(-4, 0, 0),
	LeftHip       = A(-12, 0, 0),
	LeftKnee      = A(-10, 0, 0),    -- front knee absorbs the transfer
}
local FOLLOW = {
	Waist         = A(-14, 17, 0),
	Neck          = A(-5, -6, 0),
	RightShoulder = A(55, 0, -26),   -- arm carries across the body
	RightElbow    = A(-30, 0, 0),
	LeftShoulder  = A(-10, 0, 10),   -- off arm still trailing behind
	RightHip      = A(8, 0, 0),
	LeftHip       = A(-6, 0, 0),
	LeftKnee      = A(-5, 0, 0),
}
local RELEASE_KEYS = {
	{ 0.00, WOUND },
	{ 0.10, WHIP },
	{ 0.22, FOLLOW },
	{ 0.42, nil },     -- nil = back to neutral
}

-- Union of every joint any pose touches. ONLY these are ever written, so the walk and
-- idle animations keep full control of the wrists, ankles and everything else.
local CONTROLLED = {}
for _, pose in ipairs({ WOUND, WHIP, FOLLOW }) do
	for name in pairs(pose) do CONTROLLED[name] = true end
end

local joints = {}
local function cacheJoints(char)
	joints = {}
	if not char then return end
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("AnimationConstraint") and CONTROLLED[d.Name] then
			joints[d.Name] = d
		end
	end
end
cacheJoints(player.Character)
player.CharacterAdded:Connect(function(c)
	throwAnimActive = false
	task.wait(0.3)          -- let the rig finish assembling before caching
	cacheJoints(c)
end)

local IDENTITY = CFrame.identity
local function applyPose(pose, alpha)
	for name, joint in pairs(joints) do
		if joint.Parent then
			local target = (pose and pose[name]) or IDENTITY
			if alpha and alpha < 1 then target = IDENTITY:Lerp(target, alpha) end
			joint.Transform = target
		end
	end
end
local function blend(p1, p2, t)
	local out = {}
	for name in pairs(CONTROLLED) do
		out[name] = ((p1 and p1[name]) or IDENTITY):Lerp((p2 and p2[name]) or IDENTITY, t)
	end
	return out
end

-- What the Stepped driver should be writing right now. nil = hands the rig back to the
-- walk/idle animation.
local activePose, activeAlpha = nil, 1
local windupActive = false

RunService.Stepped:Connect(function()
	if windupActive or throwAnimActive then
		if activePose then applyPose(activePose, activeAlpha) end
	elseif activePose then
		-- charge cancelled or throw finished: one neutral frame, then stop writing so the
		-- Animator resumes. Self-healing, so no exit path can leave the body stuck posed.
		applyPose(nil, 1)
		activePose = nil
	end
end)

function beginWindup()
	if not next(joints) then cacheJoints(player.Character) end
	windupActive = true
end

function driveWindup(p)
	if not windupActive then return end
	-- record only. power 0..1 lerps neutral -> fully wound, so the coil tracks the bar.
	activePose, activeAlpha = WOUND, math.clamp(p, 0, 1)
end

function endWindup()
	windupActive = false
end

local function playThrowAnimation()
	endWindup()                       -- hand off from the held coil, no snap to neutral
	if throwAnimActive then return end
	if not next(joints) then cacheJoints(player.Character) end
	throwAnimActive = true
	task.spawn(function()
		local t0 = os.clock()
		local total = RELEASE_KEYS[#RELEASE_KEYS][1]
		while true do
			local t = os.clock() - t0
			if t >= total then break end
			local k1, k2 = RELEASE_KEYS[1], RELEASE_KEYS[#RELEASE_KEYS]
			for i = 1, #RELEASE_KEYS - 1 do
				if t >= RELEASE_KEYS[i][1] and t <= RELEASE_KEYS[i + 1][1] then
					k1, k2 = RELEASE_KEYS[i], RELEASE_KEYS[i + 1]
					break
				end
			end
			local span = math.max(k2[1] - k1[1], 1e-4)
			local f = math.clamp((t - k1[1]) / span, 0, 1)
			f = f * f * (3 - 2 * f)   -- smoothstep; a linear ramp between keys looks robotic
			-- record; the Stepped driver above is what actually writes it
			activePose, activeAlpha = blend(k1[2], k2[2], f), 1
			RunService.Stepped:Wait()
		end
		throwAnimActive = false       -- the Stepped driver now returns the rig to neutral
	end)
end


local function releaseThrow(isAuto)
	if not charging then return end
	charging = false
	local finalPower = power
	local _char = player.Character
	local _hrp = _char and _char:FindFirstChild("HumanoidRootPart")
	if _hrp then
		local _p = _hrp.Position
		_hrp.CFrame = CFrame.new(_p, _p + Vector3.new(0, 0, 1))
	end

	-- Auto can never be perfect server-side, so it must not claim one here either --
	-- otherwise the HUD celebrates a bonus the throw did not actually get.
	local landedPerfect = (not isAuto)
		and finalPower >= perfectMin and finalPower <= perfectMax
	if landedPerfect then
		showPerfectPop()
	end

	cooldown = true
	throwToken += 1
	local myToken = throwToken
	throwButton.Text = "SKIPPING..."
	UITheme.setColors(throwButton, UITheme.Palette.hudMuted1, UITheme.Palette.hudMuted2)

	-- The third argument is what the server prices the AFK penalty off (AUTO_LUCK_MULT /
	-- AUTO_DISTANCE_MULT in ThrowHandler). landedPerfect stays display-only; the server
	-- judges perfect itself against the band it issued.
	remotes.ThrowRequest:FireServer(finalPower, landedPerfect, isAuto and true or false)
	playThrowAnimation()

	-- Last-resort release. Normally the bar is freed by the camera restoring, or by
	-- ThrowResult / StoneThrown on throws too short to trigger the tracking camera.
	-- This only matters when the server declined the throw outright, so none of those
	-- ever arrive. Deliberately later than the camera's own flightTime + 1.4 restore,
	-- so it never preempts it.
	task.delay(MAX_FLIGHT_SECONDS + 2.5, function()
		unlockThrow(myToken, true)
	end)
end

throwButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		if inThrowZone and not playerHasPlot() then
			remotes.TeleportTo:FireServer("OpenPlot") -- send them to an open plot to claim a base
			return
		end
		startCharge()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		releaseThrow()
	end
end)

-- === Auto skip ===
-- Parented INSIDE ThrowFrame at a negative Y, so it draws above the panel while
-- inheriting the panel's Visible -- it appears and disappears with the minigame
-- instead of floating over the world. ThrowFrame has ClipsDescendants off, which
-- is what makes hanging a child outside its bounds work.
--
-- It drives the SAME startCharge/releaseThrow path a tap does. No parallel throw
-- route to keep in sync, and the server just sees an ordinary ThrowRequest, so
-- every existing check (cooldown, one-stone-at-a-time, throw zone, plot) applies
-- unchanged.
local autoOn = false

local autoBtn = Instance.new("TextButton")
autoBtn.Name = "AutoButton"
autoBtn.AnchorPoint = Vector2.new(0.5, 1)
autoBtn.Position = UDim2.new(0.5, 0, 0, -8)
autoBtn.Size = UDim2.fromOffset(150, 34)
autoBtn.Font = Enum.Font.FredokaOne
autoBtn.TextSize = 18
autoBtn.Text = "AUTO: OFF"
autoBtn.AutoButtonColor = false
autoBtn.ZIndex = throwFrame.ZIndex + 1
autoBtn.Parent = throwFrame
UITheme.campButton(autoBtn, UITheme.Palette.hudMuted1, UITheme.Palette.hudMuted2)
blackRim(autoBtn, 3)
inkTextOnce(autoBtn, 2.6)

local function refreshAutoButton()
	autoBtn.Text = autoOn and "AUTO: ON" or "AUTO: OFF"
	if autoOn then
		UITheme.setColors(autoBtn, UITheme.Palette.green1, UITheme.Palette.green2)
	else
		UITheme.setColors(autoBtn, UITheme.Palette.hudMuted1, UITheme.Palette.hudMuted2)
	end
end
refreshAutoButton()

autoBtn.MouseButton1Click:Connect(function()
	autoOn = not autoOn
	refreshAutoButton()
end)

-- ONE loop rather than a chain of task.delay callbacks: every gate is re-checked
-- each pass, so switching auto off, walking away from the dock, or losing the plot
-- stops it at the next tick instead of after one more throw has already gone out.
task.spawn(function()
	while true do
		task.wait(0.1)
		if autoOn and inThrowZone and not charging and not cooldown and playerHasPlot() then
			startCharge()
			-- Release at a RANDOM point on the bar, deliberately unrelated to the band.
			--
			-- This used to wait for power to reach perfectMin and fire the instant it got
			-- there, which scored a perfect on literally every throw -- the exact opposite
			-- of what an idle mode should do, and the reason an overnight session came back
			-- loaded with rares. Auto is now a spread of mediocre throws, and the server
			-- refuses it a perfect outright on top of taxing its distance and luck.
			--
			-- The 3s ceiling still means a stuck charge releases rather than holding the
			-- bar forever.
			local target = 0.30 + math.random() * 0.58     -- 0.30 .. 0.88
			local t0 = os.clock()
			while autoOn and charging and os.clock() - t0 < 3 do
				if power >= target then
					-- a beat of jitter so releases are not even frame-consistent
					task.wait(math.random() * 0.10)
					break
				end
				task.wait()
			end
			if charging then releaseThrow(true) end
		end
	end
end)

RunService.RenderStepped:Connect(function(dt)
	if charging then
		-- time since THIS charge began, on THIS charge's period: the bar always starts at 0
		-- and sweeps up, but at a speed the player cannot read off the previous throw
		local t = os.clock() - chargeStart
		power = (math.sin((t * (2 * math.pi / chargePeriod)) - math.pi / 2) + 1) / 2
		barFill.Size = UDim2.new(power, 0, 1, 0)
		barFill.BackgroundColor3 = Color3.fromHSV(0.33 * power, 0.8, 1)
		-- the arm IS the bar: same value drives both, so what you see on the HUD and what
		-- the character is doing can never disagree
		driveWindup(power)
	end
end)

refreshCashLabel()

-- === Teleport tabs ===
local tabBar = gui:WaitForChild("TabBar")
local throwTab = tabBar:WaitForChild("ThrowTab")
local shopsTab = tabBar:WaitForChild("ShopsTab")
local plotTab = tabBar:WaitForChild("PlotTab")

throwTab.MouseButton1Click:Connect(function()
	remotes.TeleportTo:FireServer("Throw")
end)
shopsTab.MouseButton1Click:Connect(function()
	remotes.TeleportTo:FireServer("Shops")
end)
plotTab.MouseButton1Click:Connect(function()
	remotes.TeleportTo:FireServer("Plot")
end)

-- === Teleport tabs: top bar (Skip / Shops / Plot) + cash pill ===
-- Runtime-only: the StarterGui source is untouched and the TeleportTo wiring
-- above is left alone -- only appearance and placement change here.
--
-- Each tab is a sticker card (white plate, saturated ribbon banner, white
-- keyline) from UIStyle.sticker; this block picks colours and lays them out.
-- All lettering is white FredokaOne (see UIPolish for the game-wide sweep).
--
-- PLACEMENT: centred along the top. The cash pill owns the top-right corner
-- (190 wide + 12 margin), so the bar has to be narrow enough to clear it --
-- pickMetrics() below solves for that rather than assuming a screen size, and
-- drops the bar UNDER the pill on screens too narrow for any size to fit.
do
	local function C(r, g, b) return Color3.fromRGB(r, g, b) end

	-- One saturated accent per destination. Deliberately high-chroma and far
	-- apart in hue so a glance at the rail is enough to tell them apart.
	local RAIL = {
		{ btn = throwTab, order = 1, word = "Skip",  glyph = "\u{1F3AF}", icon = "skip",
		  accent = { light = C(255, 182, 64),  dark = C(244, 122, 18), outline = C(148, 64, 8)  } },
		{ btn = shopsTab, order = 2, word = "Shops", glyph = "\u{1F6D2}", icon = "shops",
		  accent = { light = C(255, 116, 176), dark = C(226, 42, 122), outline = C(134, 14, 70) } },
		{ btn = plotTab,  order = 3, word = "Plot",  glyph = "\u{1F3E0}", icon = "plot",
		  accent = { light = C(112, 192, 255), dark = C(38, 118, 236), outline = C(18, 58, 138) } },
	}

	--[[ USER (2026-07-31): the tabs take the same treatment the nav rail got --
	the kit-style drawing from UIKit.IconArt, sitting bare with no white plate
	behind it, matching the reference image. UIStyle.sticker is left alone (it is
	shared with other surfaces and is idempotent); this runs straight after it
	and un-plates the card it just built, keeping the card only as the icon's
	positioning box. The ribbon underneath is untouched -- it IS the label.

	applyLayout re-runs on every viewport change, so this has to be idempotent
	too: the previous drawing is destroyed before a new one goes in. ]]
	local function applyKitIcon(btn, iconName, MET)
		local card = btn:FindFirstChild("StickerCard")
		if not card then return end

		local emoji = card:FindFirstChild("StickerIcon")
		local stale = card:FindFirstChild("KitIcon")
		if stale then stale:Destroy() end

		if not (IconArt and iconName and IconArt.has(iconName)) then
			if emoji then emoji.Visible = true end -- no artwork for this tab: keep the emoji
			return
		end

		-- un-plate: card goes invisible but stays as the layout box
		card.BackgroundTransparency = 1
		for _, child in ipairs(card:GetChildren()) do
			if child:IsA("UIStroke") then child.Transparency = 1 end
		end
		if emoji then emoji.Visible = false end

		-- Sized off the metrics rather than card.AbsoluteSize: this runs in the
		-- same tick the card is built, before any layout pass has resolved it.
		local box = math.min(MET.W, MET.H - 22)
		local size = math.max(math.floor(box * 0.92), 8)

		local holder = Instance.new("Frame")
		holder.Name = "KitIcon"
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.46)
		holder.Size = UDim2.fromOffset(size, size)
		holder.BackgroundTransparency = 1
		holder.ZIndex = card.ZIndex + 2
		holder.Parent = card
		IconArt.draw(holder, iconName, size, holder.ZIndex)
	end

	local WIDE    = { W = 86, H = 104, GAP = 30 }
	local COMPACT = { W = 64, H = 80,  GAP = 24 }
	local TOP_Y, UNDER_PILL_Y = 10, 66

	-- the cash pill: 190 wide, 12 from the right edge, occupying y 12..58
	local CASH_W, CASH_MARGIN, CLEARANCE = 190, 12, 10

	local cam = Workspace.CurrentCamera
	local function barWidth(MET) return #RAIL * MET.W + (#RAIL - 1) * MET.GAP end

	-- A centred bar of width B clears the pill when B < vx - 2*(CASH_W + margin
	-- + clearance). Solved rather than guessed at a breakpoint, so it stays
	-- correct if the pill is ever resized.
	local function pickMetrics()
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local room = vp.X - 2 * (CASH_W + CASH_MARGIN + CLEARANCE)
		if barWidth(WIDE) <= room then return WIDE, TOP_Y end
		if barWidth(COMPACT) <= room then return COMPACT, TOP_Y end
		-- too narrow for either: stack the bar beneath the pill instead of
		-- letting them overlap
		return COMPACT, UNDER_PILL_Y
	end

	-- The authored wooden decorations stay hidden rather than destroyed: a
	-- collaborator's script may still look them up by name.
	local function stripLegacy(btn)
		for _, n in ipairs({ "Accent", "Gloss", "Nail1", "Nail2" }) do
			local d = btn:FindFirstChild(n)
			if d then d.Visible = false end
		end
		for _, n in ipairs({ "TabBase", "TabFace" }) do   -- from the campfire pass
			local d = btn:FindFirstChild(n)
			if d then d:Destroy() end
		end
		for _, s in ipairs(btn:GetChildren()) do
			if s:IsA("UIStroke") and s.Name ~= "UIStyleStrokeBorder" then s.Transparency = 1 end
		end
	end

	local function applyLayout(MET, topY)
		tabBar.BackgroundTransparency = 1
		tabBar.BorderSizePixel = 0
		tabBar.AnchorPoint = Vector2.new(0.5, 0)
		tabBar.Position = UDim2.new(0.5, 0, 0, topY)
		tabBar.Size = UDim2.fromOffset(barWidth(MET), MET.H)
		tabBar.ZIndex = 2

		local layout = tabBar:FindFirstChildOfClass("UIListLayout")
		if not layout then layout = Instance.new("UIListLayout", tabBar) end
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Top
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, MET.GAP)

		for _, spec in ipairs(RAIL) do
			local btn = spec.btn
			if btn then
				stripLegacy(btn)
				btn.LayoutOrder = spec.order
				btn.ZIndex = 2
				btn.Size = UDim2.fromOffset(MET.W, MET.H)
				UIStyle.sticker(btn, {
					accent = spec.accent,
					label  = spec.word,
					glyph  = spec.glyph,
					badge  = false,     -- flip on via UIStyle.stickerBadge(btn, true)
				})
				applyKitIcon(btn, spec.icon, MET)
			end
		end
	end

	applyLayout(pickMetrics())

	-- Re-layout on viewport changes, debounced so a drag-resize does not
	-- rebuild every frame. Token pattern: only the newest wait wins.
	local resizeToken = 0
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			resizeToken += 1
			local myToken = resizeToken
			task.delay(0.12, function()
				if myToken ~= resizeToken then return end
				applyLayout(pickMetrics())
			end)
		end)
	end

	-- === Cash pill ===
	-- Same sticker language: gold gradient, white keyline, white FredokaOne.
	if cashFrame then
		cashFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		cashFrame.BorderSizePixel = 0
		UIStyle.pill(cashFrame)
		UIStyle.gradient(cashFrame, UIStyle.Palette.Gold)
		UIStyle.stroke(cashFrame, Color3.fromRGB(255, 255, 255), 3.5)

		local gloss = cashFrame:FindFirstChild("Gloss")
		if gloss then
			gloss.Visible = true
			local gg = gloss:FindFirstChildOfClass("UIGradient")
			if gg then
				gg.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.68), NumberSequenceKeypoint.new(1, 1) })
			end
		end

		local badge = cashFrame:FindFirstChild("CoinBadge")
		if badge then
			UIStyle.pill(badge)
			UIStyle.gradient(badge, { light = Color3.fromRGB(255, 236, 150),
			                          dark  = Color3.fromRGB(250, 190, 40) })
			UIStyle.stroke(badge, Color3.fromRGB(255, 255, 255), 2.5)
		end

		if cashLabel then
			UIStyle.bubbleText(cashLabel, UIStyle.Palette.Gold)
		end
	end
end


-- === Sprint (Left Shift hold, or button toggle) ===
local WALK_SPEED = 20.8
local SPRINT_SPEED = 33.8
local shiftHeld = false
local sprintToggled = false

local sprintButton = gui:WaitForChild("SprintButton")

local function getHumanoid()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function applySprint()
	local sprinting = shiftHeld or sprintToggled
	local hum = getHumanoid()
	if hum then
		hum.WalkSpeed = sprinting and SPRINT_SPEED or WALK_SPEED
	end
	if sprinting then UITheme.setColors(sprintButton, UITheme.Palette.hudGold1, UITheme.Palette.hudGold2)
	else UITheme.setColors(sprintButton, UITheme.Palette.hudShop1, UITheme.Palette.hudShop2) end
	sprintButton.Text = sprinting and "🏃 Sprinting" or "🏃 Sprint"
end

player.CharacterAdded:Connect(function(char)
	local hum = char:WaitForChild("Humanoid")
	hum.WalkSpeed = (shiftHeld or sprintToggled) and SPRINT_SPEED or WALK_SPEED
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.LeftShift then
		shiftHeld = true
		applySprint()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		shiftHeld = false
		applySprint()
	end
end)

sprintButton.Activated:Connect(function()
	sprintToggled = not sprintToggled
	applySprint()
end)

applySprint()

-- === Throw-zone gating ===
local throwZone = gameWorld:WaitForChild("ThrowZone")

local function computeInZone()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	local rel = throwZone.CFrame:PointToObjectSpace(hrp.Position)
	local s = throwZone.Size / 2
	return math.abs(rel.X) <= s.X and math.abs(rel.Z) <= s.Z and math.abs(rel.Y) <= s.Y + 6
end

local prevInZone = false
RunService.Heartbeat:Connect(function()
	inThrowZone = computeInZone()
	if inThrowZone and not prevInZone then refreshSweetSpot() end -- fresh spot on walk-up
	prevInZone = inThrowZone
	-- only show the throw UI at the dock (stay visible mid-throw so it doesn't vanish)
	throwFrame.Visible = inThrowZone or charging or cooldown
	if charging or cooldown then return end
	local wantText, cTop, cBot
	if not inThrowZone then
		wantText, cTop, cBot = "GO TO SKIP AREA", UITheme.Palette.hudMuted1, UITheme.Palette.hudMuted2
	elseif not playerHasPlot() then
		wantText, cTop, cBot = "GET A PLOT FIRST", UITheme.Palette.hudGold1, UITheme.Palette.hudGold2
	else
		wantText, cTop, cBot = DEFAULT_THROW_TEXT, UITheme.Palette.hudThrow1, UITheme.Palette.hudThrow2
	end
	if throwButton.Text ~= wantText then
		throwButton.Text = wantText
		UITheme.setColors(throwButton, cTop, cBot)
	end
end)

-- === Stone tracking camera (far throws) ===
local camera = Workspace.CurrentCamera
local TRACK_MIN_DISTANCE = 60
local tracking = false
local stoneThrownRemote = remotes:WaitForChild("StoneThrown")

stoneThrownRemote.OnClientEvent:Connect(function(startPos, landingPos, flightTime, distance)
	if tracking then return end
	if (distance or 0) < TRACK_MIN_DISTANCE then return end
	if not startPos or not landingPos then return end
	tracking = true
	cameraTracking = true    -- holds the throw bar at "SKIPPING..." until the flyback ends
	flightTime = flightTime or 1.5
	local prevType = camera.CameraType
	camera.CameraType = Enum.CameraType.Scriptable
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local alpha = math.clamp((os.clock() - t0) / flightTime, 0, 1)
		local target = startPos:Lerp(landingPos, alpha)
		camera.CFrame = CFrame.new(target + Vector3.new(6, 14, -24), target + Vector3.new(0, 1, 6))
	end)
	task.delay(flightTime + 1.4, function()
		if conn then conn:Disconnect() end
		camera.CameraType = prevType
		tracking = false
		-- camera is back on the player: this is the real end of the throw
		cameraTracking = false
		unlockThrow()
	end)
end)

-- === Releasing the throw lock ===
-- Connected down here, after unlockThrow and the remotes both exist. Separate
-- listeners rather than edits to the handlers above, so the catch popup and the
-- tracking camera keep their own concerns.

-- Normal case: the stone has settled and the catch is being revealed.
remotes.ThrowResult.OnClientEvent:Connect(function()
	unlockThrow()
end)

-- Thrown, but no catch is coming (the server bailed out of the reveal). StoneThrown
-- carries the real flight time, so the bar opens exactly when the stone lands rather
-- than waiting for the pessimistic MAX_FLIGHT_SECONDS fallback.
stoneThrownRemote.OnClientEvent:Connect(function(_, _, flightTime)
	local myToken = throwToken
	task.delay((flightTime or 1.5) + 0.3, function()
		unlockThrow(myToken)
	end)
end)

-- === Sticker pass: throw panel + sprint button ===
-- Brings the two remaining always-on-screen controls into the same language as
-- the rail: rounder shapes and a WHITE keyline instead of the old near-black
-- one. Only the outline and corner radius change -- the gradients here were
-- already vivid, and the state code drives them through UITheme.setColors,
-- which touches the UIGradient only. That is why this pass survives a state
-- change and does not need re-running on every throw.
do
	local WHITE = Color3.fromRGB(255, 255, 255)

	-- Retire the authored dark rims, then add one white keyline we own by name.
	local function keyline(o, thickness, radius)
		if not o then return end
		for _, s in ipairs(o:GetChildren()) do
			if s:IsA("UIStroke") and s.ApplyStrokeMode == Enum.ApplyStrokeMode.Border
			   and s.Name ~= "UIStyleStrokeBorder" then
				s.Transparency = 1
			end
		end
		if radius then UIStyle.corner(o, radius) end
		UIStyle.stroke(o, WHITE, thickness)
	end

	keyline(throwFrame, 3.5, 20)

	local barBg = throwFrame and throwFrame:FindFirstChild("BarBackground")
	if barBg then
		UIStyle.pill(barBg)
		keyline(barBg, 2.5)
		local fill = barBg:FindFirstChild("BarFill")
		if fill then UIStyle.pill(fill) end
	end

	keyline(throwButton, 3, 14)
	keyline(sprintButton, 3, 16)
	if sprintButton then UIStyle.pill(sprintButton) end
end
