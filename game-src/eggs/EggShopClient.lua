-- EggShopClient -- Forest Egg Shop panel: 5-egg buy list with data-driven odds,
-- a darrel chip, and the daily-quest mini list. Opens via the EggStall's
-- ProximityPrompt on the client (server never gates the OPEN, only the BUY).
--
-- ODDS ARE ALWAYS VISIBLE AND NEVER HARD-CODED: every percentage rendered here
-- comes from iterating EggConfig's own egg.Table at runtime -- the server rolls
-- from those exact same rows (EggHandler.RollFor), so shown odds can never
-- drift from real odds (Roblox requires published odds for paid random items).
--
-- playReveal(result) is a STUB in this task -- Task 8 replaces its body with
-- the real hatch animation. Everything around it (buy -> disable -> result ->
-- reopen) is final.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local EggConfig = require(ReplicatedStorage.Modules.EggConfig)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local SideRail = require(ReplicatedStorage.Modules.SideRail)
local BrainrotThumb = require(ReplicatedStorage.Modules.BrainrotThumb)

local CF = UITheme.Camp
local FONT = UITheme.Font
local WORLD_ID = "Forest"
local world = EggConfig.GetWorld(WORLD_ID)

-- creature name -> tier colour, same lookup pattern BackpackClient/EggHandler use
local tierByName, rarityByName = {}, {}
for _, t in ipairs(RarityConfig) do tierByName[t.Name] = t end
for _, e in ipairs(BrainrotConfig.List or BrainrotConfig) do rarityByName[e.Name] = e.Rarity end

local function tierColor(creatureName)
	local rarity = rarityByName[creatureName]
	local tier = rarity and tierByName[rarity]
	return tier and tier.Color or CF.ink
end

---------------------------------------------------------------- tiny UI helper
local function new(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do inst[k] = v end
	inst.Parent = parent
	return inst
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
	return vp
end

---------------------------------------------------------------- ScreenGui + panel
local gui = new("ScreenGui", {
	Name = "EggShopUI", DisplayOrder = 9, IgnoreGuiInset = false, ResetOnSpawn = false,
}, playerGui)

local frame = new("Frame", {
	Name = "EggShopFrame",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.fromOffset(640, 520),
	Visible = false,
	ZIndex = 10,
}, gui)
UITheme.campPanel(frame)
SideRail.registerPanel(frame)

-- short-viewport guard, same pattern as every other campfire panel: shrink and
-- push down so the panel never covers the top TabBar band (146px)
local FRAME_H = 520
local hudScale = new("UIScale", { Name = "HudFixScale" }, frame)
local function relayout()
	local vh = gui.AbsoluteSize.Y
	if vh <= 0 then return end
	local s = math.min(1, (vh - 146 - 40) / FRAME_H)
	hudScale.Scale = s
	frame.Position = UDim2.new(0.5, 0, 0.5, math.max(0, 146 + FRAME_H * s / 2 - vh / 2))
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
relayout()

local ribbon, ribbonTitle = UITheme.ribbon(frame, "FOREST EGGS", 0.62)

local closeBtn = new("TextButton", {}, frame)
UITheme.styleClose(closeBtn)
closeBtn.ZIndex = 18
for _, s in ipairs(closeBtn:GetChildren()) do
	if s:IsA("UIStroke") and s.ApplyStrokeMode ~= Enum.ApplyStrokeMode.Contextual then
		s.Color = CF.ink
		s.Thickness = 3
	end
end

---------------------------------------------------------------- layout columns
local LEFT_W, RIGHT_W, PAD = 392, 176, 16
local list = new("ScrollingFrame", {
	Name = "EggList",
	Position = UDim2.fromOffset(PAD, 78),
	Size = UDim2.fromOffset(LEFT_W, FRAME_H - 78 - PAD),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = CF.cream,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 12,
}, frame)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10) }, list)

local right = new("Frame", {
	Name = "SidePanel",
	Position = UDim2.fromOffset(PAD * 2 + LEFT_W, 78),
	Size = UDim2.fromOffset(RIGHT_W, FRAME_H - 78 - PAD),
	BackgroundTransparency = 1,
	ZIndex = 12,
}, frame)

---------------------------------------------------------------- darrel chip
local darrelChip = new("Frame", { Size = UDim2.new(1, 0, 0, 44), ZIndex = 12 }, right)
UITheme.corner(darrelChip, 12)
UITheme.gradient(darrelChip, CF.wood1, CF.wood2, 90)
UITheme.ink(darrelChip, 3)
local darrelLabel = new("TextLabel", {
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = FONT, TextSize = 20,
	TextColor3 = CF.onDark, Text = "\u{1F48E} 0", ZIndex = 13,
}, darrelChip)
UITheme.inkText(darrelLabel, 2.4)

---------------------------------------------------------------- daily quests
local questHeader = new("TextLabel", {
	Position = UDim2.new(0, 0, 0, 54), Size = UDim2.new(1, 0, 0, 20),
	BackgroundTransparency = 1, Font = FONT, TextSize = 15, TextColor3 = CF.cream,
	Text = "DAILY QUESTS", ZIndex = 12,
}, right)
UITheme.inkText(questHeader, 2)

local questList = new("Frame", {
	Position = UDim2.new(0, 0, 0, 78), Size = UDim2.new(1, 0, 1, -78),
	BackgroundTransparency = 1, ZIndex = 12,
}, right)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, questList)

local questRows = {}
for i = 1, 3 do
	local row = new("Frame", { Size = UDim2.new(1, 0, 0, 64), Visible = false, LayoutOrder = i, ZIndex = 12 }, questList)
	UITheme.corner(row, 10)
	UITheme.gradient(row, CF.cardTop, CF.cardBot, 90)
	UITheme.ink(row, 2.5)
	local text = new("TextLabel", {
		Position = UDim2.new(0, 8, 0, 6), Size = UDim2.new(1, -16, 0, 30),
		BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 12,
		TextColor3 = CF.ink, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
		Text = "", ZIndex = 13,
	}, row)
	local progress = new("TextLabel", {
		Position = UDim2.new(0, 8, 1, -22), Size = UDim2.new(0.5, -12, 0, 16),
		BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = CF.muted,
		TextXAlignment = Enum.TextXAlignment.Left, Text = "", ZIndex = 13,
	}, row)
	local reward = new("TextLabel", {
		Position = UDim2.new(0.5, 4, 1, -22), Size = UDim2.new(0.5, -12, 0, 16),
		BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = CF.amber2,
		TextXAlignment = Enum.TextXAlignment.Right, Text = "", ZIndex = 13,
	}, row)
	local check = new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(20, 20),
		BackgroundTransparency = 1, Font = FONT, TextSize = 16, TextColor3 = CF.pine1,
		Text = "\u{2713}", Visible = false, ZIndex = 14,
	}, row)
	UITheme.inkText(check, 2)
	questRows[i] = { row = row, text = text, progress = progress, reward = reward, check = check }
end

local function refreshQuests(daily)
	local quests = (daily and daily.Quests) or {}
	for i, ui in ipairs(questRows) do
		local q = quests[i]
		ui.row.Visible = q ~= nil
		if q then
			ui.text.Text = q.Text or ""
			ui.progress.Text = ("%d/%d"):format(q.Progress or 0, q.Target or 0)
			ui.reward.Text = "+" .. tostring(q.Reward or 0) .. "\u{1F48E}"
			ui.check.Visible = q.Claimed == true
		end
	end
end

---------------------------------------------------------------- egg rows
local ACCENTS = {
	{ CF.amber1, CF.amber2 }, { CF.pine1, CF.pine2 }, { CF.lake1, CF.lake2 },
	{ CF.ember1, CF.ember2 }, { CF.berry1, CF.berry2 },
}

local openButtons = {}
local buyLocked = false

local function fireBuy(egg)
	if buyLocked then return end
	buyLocked = true
	for _, b in ipairs(openButtons) do
		b.Active = false
		b.AutoButtonColor = false
	end
	remotes.EggBuy:FireServer(WORLD_ID, egg.Id)
	task.delay(0.6, function()
		buyLocked = false
		for _, b in ipairs(openButtons) do
			b.Active = true
			b.AutoButtonColor = true
		end
	end)
end

for i, egg in ipairs(world.Eggs) do
	local acc = ACCENTS[((i - 1) % #ACCENTS) + 1]
	local fillTop, fillBot = UITheme.accentFill(acc[1])

	local row = new("Frame", {
		Name = "EggRow_" .. egg.Id,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		LayoutOrder = i,
		ZIndex = 12,
	}, list)
	UITheme.corner(row, 14)
	UITheme.ink(row, 3)
	UITheme.gradient(row, fillTop, fillBot, 90)
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, row)

	local header = new("Frame", {
		Size = UDim2.new(1, 0, 0, 92), BackgroundTransparency = 1, LayoutOrder = 1, ZIndex = 13,
	}, row)

	local iconHolder = new("Frame", {
		Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(72, 72),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255), ZIndex = 14,
	}, header)
	UITheme.corner(iconHolder, 10)
	UITheme.ink(iconHolder, 2.5)
	local vp = addEggViewport(iconHolder, egg.Model, {
		size = UDim2.new(1, -6, 1, -6), position = UDim2.fromOffset(3, 3), zIndex = 15,
	})
	if not vp then
		local sw = new("Frame", {
			Size = UDim2.new(1, -6, 1, -6), Position = UDim2.fromOffset(3, 3),
			BackgroundColor3 = acc[1], ZIndex = 15,
		}, iconHolder)
		UITheme.corner(sw, 8)
	end

	local nameLabel = new("TextLabel", {
		Position = UDim2.fromOffset(90, 12), Size = UDim2.new(1, -220, 0, 24),
		BackgroundTransparency = 1, Font = FONT, TextSize = 18, TextColor3 = acc[1],
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		Text = egg.Name, ZIndex = 14,
	}, header)
	UITheme.inkText(nameLabel, 2.6)

	local priceLabel = new("TextLabel", {
		Position = UDim2.fromOffset(90, 38), Size = UDim2.new(1, -220, 0, 20),
		BackgroundTransparency = 1, Font = FONT, TextSize = 15, TextColor3 = CF.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = tostring(egg.Price) .. "\u{1F48E}", ZIndex = 14,
	}, header)
	UITheme.inkText(priceLabel, 1.6)

	local chevron = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -100, 0.5, 0), Size = UDim2.fromOffset(30, 30),
		Text = "\u{25BC}", Font = FONT, TextSize = 16, ZIndex = 14,
	}, header)
	UITheme.campButton(chevron, CF.locked1, CF.locked2)

	local openBtn = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(78, 36),
		Text = "OPEN", Font = FONT, TextSize = 15, ZIndex = 14,
	}, header)
	UITheme.campButton(openBtn, CF.pine1, CF.pine2)
	openBtn.Activated:Connect(function() fireBuy(egg) end)
	openButtons[#openButtons + 1] = openBtn

	-- ODDS ARE DATA-DRIVEN: every line below reads straight from egg.Table
	-- (EggConfig), the exact table EggHandler.RollFor rolls against server-side.
	-- No percentage is ever authored a second time in this file.
	local oddsHolder = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, Visible = false, LayoutOrder = 2, ZIndex = 13,
	}, row)
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }, oddsHolder)
	for j, tableRow in ipairs(egg.Table) do
		local creature, weight = tableRow[1], tableRow[2]
		local oddsLine = new("TextLabel", {
			Position = UDim2.new(0, 14, 0, 0), Size = UDim2.new(1, -28, 0, 18),
			BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 13,
			TextColor3 = tierColor(creature), TextXAlignment = Enum.TextXAlignment.Left,
			Text = creature .. " \u{2014} " .. tostring(weight) .. "%",
			LayoutOrder = j, ZIndex = 14,
		}, oddsHolder)
		if j == #egg.Table then
			-- bottom breathing room before the row's rounded corner
			oddsLine.Size = UDim2.new(1, -28, 0, 24)
		end
	end

	chevron.Activated:Connect(function()
		oddsHolder.Visible = not oddsHolder.Visible
		chevron.Text = oddsHolder.Visible and "\u{25B2}" or "\u{25BC}"
	end)
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

---------------------------------------------------------------- hatch reveal (Task 8 stub)
local function playReveal(result)
	print("[EggShop] hatched:", result.Name)
end

---------------------------------------------------------------- darrel state pull
-- DarrelUpdate's join-time push can race this script's own listener connecting
-- (Task 3's note), so this ALSO pulls current state via a RemoteFunction --
-- once at startup, and again every time the panel opens.
local darrelStateRF = remotes:WaitForChild("DarrelState")
local function applyDarrel(payload)
	if type(payload) ~= "table" then return end
	if payload.Darrels then
		darrelLabel.Text = "\u{1F48E} " .. tostring(math.floor(payload.Darrels))
	end
	if payload.Daily then
		refreshQuests(payload.Daily)
	end
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
local function setOpen(open)
	frame.Visible = open
	if open then
		pullDarrelState()
		list.CanvasPosition = Vector2.new(0, 0)
	end
end
closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)

remotes.EggResult.OnClientEvent:Connect(function(result)
	if type(result) ~= "table" then return end
	if not result.Ok then
		showToast(result.Message)
		return
	end
	playReveal(result)
	-- Task 8's real hatch overlay may hide this panel while it plays; this stub
	-- doesn't, but reopening here keeps the contract stable either way.
	setOpen(true)
end)

---------------------------------------------------------------- stall prompt
local prompt = Workspace:WaitForChild("GameWorld"):WaitForChild("EggStall"):WaitForChild("PromptPart"):WaitForChild("EggPrompt")
ProximityPromptService.PromptTriggered:Connect(function(triggeredPrompt, who)
	if who ~= player or triggeredPrompt ~= prompt then return end
	setOpen(not frame.Visible)
end)

-- walk away -> close, same convention as the other stall panels (MerchantClient)
RunService.Heartbeat:Connect(function()
	if not frame.Visible then return end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and (hrp.Position - prompt.Parent.Position).Magnitude > 24 then
		setOpen(false)
	end
end)
