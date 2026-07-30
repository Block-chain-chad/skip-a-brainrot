-- EggShopClient -- Forest Egg Shop panel: 5-egg buy list with data-driven odds,
-- a darrel chip, and the daily-quest mini list. Opens via the EggStall's
-- ProximityPrompt on the client (server never gates the OPEN, only the BUY).
--
-- ODDS ARE ALWAYS VISIBLE AND NEVER HARD-CODED: every percentage rendered here
-- comes from iterating EggConfig's own egg.Table at runtime -- the server rolls
-- from those exact same rows (EggHandler.RollFor), so shown odds can never
-- drift from real odds (Roblox requires published odds for paid random items).
--
-- playReveal(result), further down, plays the hatch animation (Task 8):
-- shake -> crack -> tier-lit creature spin -> skip/fade. Everything around it
-- (buy -> disable -> result -> reopen) is unrelated and untouched by that task.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local EggConfig = require(ReplicatedStorage.Modules.EggConfig)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local SideRail = require(ReplicatedStorage.Modules.SideRail)
local BrainrotThumb = require(ReplicatedStorage.Modules.BrainrotThumb)
local RarityFX = require(ReplicatedStorage.Modules.RarityFX)
local SoundKit = require(ReplicatedStorage.Modules.SoundKit)

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

---------------------------------------------------------------- hatch reveal
-- Full-screen dim + a single ViewportFrame carried through three phases:
-- SHAKE (egg jitters in place), CRACK (every non-shell part bursts outward
-- while the shell fades), CREATURE (viewport swaps to the hatched brainrot,
-- tier-lit tile, slow spin). "Non-shell part" rather than a fixed name-prefix
-- whitelist: the five egg models carry a `ring_*`/`tape_*` family alongside
-- the documented shard/drip/spike/horn/stripe/stud/rune/crown/link/cap/halo
-- ones, so matching everything except shell_body_* is what actually covers
-- every decoration on every egg instead of silently stranding a family that
-- was never on the list.
--
-- ONE RenderStepped connection drives every per-frame animation in this
-- reveal -- the egg shake AND the later creature spin both read the same
-- `elapsed` accumulator -- stored in `conn` and disconnected in `skip()`, so
-- a reveal can never leak a per-frame cost after it ends.
--
-- Every phase transition is a task.delay chained off the one before. Each
-- callback checks its captured `myGen` against the shared `revealGen`
-- counter before doing anything: skip() and a fresh playReveal() both bump
-- `revealGen`, so a stale callback from an already-skipped reveal is a no-op
-- instead of reaching into whatever reveal (or nothing) is live by then.
local revealGui
local function ensureRevealGui()
	if revealGui and revealGui.Parent then return revealGui end
	revealGui = new("ScreenGui", {
		Name = "EggRevealUI", DisplayOrder = 10, IgnoreGuiInset = true, ResetOnSpawn = false,
	}, playerGui)
	return revealGui
end

local VP_SIZE = 320
local SHAKE_TIME, SHAKE_HZ, SHAKE_DEG = 1.2, 20, 4
local CRACK_TIME, CRACK_DIST_MULT, MAX_EXPLODE = 0.4, 2.5, 60
local SPIN_TIME = 2.0     -- seconds per creature revolution
local CREATURE_HOLD = 3.5 -- seconds the creature sits before auto-skip
local FADE_TIME = 0.3
local DIM_TARGET = 0.35

local revealGen = 0    -- bumped by skip() and by every new playReveal()
local revealSkip = nil -- the live reveal's skip(), or nil

local function volumeOf(part)
	local s = part.Size
	return s.X * s.Y * s.Z
end

local function playReveal(result)
	-- Back-to-back safety: a second EggResult while a reveal is live skips
	-- the current one, then plays the new one straight after (simplest
	-- correct behaviour -- no queue to get stuck).
	if revealSkip then revealSkip() end

	revealGen += 1
	local myGen = revealGen

	local eggDef = EggConfig.GetEgg(WORLD_ID, result.EggId)
	local eggModelName = eggDef and eggDef.Model
	local tier = tierByName[result.Rarity]
	local accent = (tier and tier.Color) or CF.ink

	local root = new("Frame", {
		Name = "Reveal", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1,
	}, ensureRevealGui())

	local dim = new("Frame", {
		Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1,
	}, root)
	TweenService:Create(dim, TweenInfo.new(FADE_TIME), { BackgroundTransparency = 1 - DIM_TARGET }):Play()

	local holder = new("Frame", {
		Name = "Holder", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromOffset(VP_SIZE, VP_SIZE + 96), BackgroundTransparency = 1, ZIndex = 2,
	}, root)

	local clickCatcher = new("TextButton", {
		Name = "ClickCatcher", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 20,
	}, root)

	frame.Visible = false -- hide the shop panel behind the reveal overlay

	-- {inst, prop} pairs to hide (tween to transparency 1) on skip; every
	-- element that should visibly fade rather than snap registers itself here.
	local fades = { { dim, "BackgroundTransparency" } }

	local conn -- the ONE RenderStepped connection for this reveal
	local dead = false
	local elapsed = 0
	local spinFn -- set once the creature phase starts

	local function skip()
		if dead then return end
		dead = true
		revealGen += 1 -- invalidate any pending task.delay for THIS reveal too
		if revealSkip == skip then revealSkip = nil end
		if conn then conn:Disconnect(); conn = nil end
		clickCatcher.Active = false
		for _, f in ipairs(fades) do
			TweenService:Create(f[1], TweenInfo.new(FADE_TIME), { [f[2]] = 1 }):Play()
		end
		frame.Visible = true -- restore the shop panel
		task.delay(FADE_TIME, function()
			if root then root:Destroy(); root = nil end
		end)
	end
	revealSkip = skip
	clickCatcher.Activated:Connect(skip)

	---------------------------------------------------- SHAKE
	local eggClone, basePivot, eggVp
	local eggMasterModel = eggModelName and eggMaster(eggModelName)
	if eggMasterModel then
		eggVp = new("ViewportFrame", {
			Name = "EggViewport", Size = UDim2.fromOffset(VP_SIZE, VP_SIZE), BackgroundTransparency = 1, ZIndex = 3,
		}, holder)
		local eggCam = new("Camera", { FieldOfView = 32 }, eggVp)
		eggVp.CurrentCamera = eggCam
		eggClone = eggMasterModel:Clone()
		eggClone.Parent = eggVp
		basePivot = eggClone:GetPivot()
		local centre, dist = BrainrotThumb.framing(eggClone, 32)
		eggCam.CFrame = CFrame.lookAt(centre + BrainrotThumb.DEFAULT_DIR * dist, centre)
	end

	local crackPhase, creaturePhase

	conn = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		if eggClone and elapsed <= SHAKE_TIME then
			local w = elapsed * SHAKE_HZ * (2 * math.pi)
			local rx = math.rad(SHAKE_DEG) * math.sin(w)
			local ry = math.rad(SHAKE_DEG) * math.sin(w * 1.31 + 1.7)
			local rz = math.rad(SHAKE_DEG) * math.sin(w * 0.77 + 0.4)
			eggClone:PivotTo(basePivot * CFrame.Angles(rx, ry, rz))
		end
		if spinFn then spinFn(elapsed) end
	end)

	task.delay(SHAKE_TIME, function()
		if myGen ~= revealGen then return end
		crackPhase()
	end)

	---------------------------------------------------- CRACK
	crackPhase = function()
		SoundKit.play("panelOpen", nil, { volume = 0.2 })

		if eggClone then
			local shellPart = eggClone:FindFirstChild("shell_body_1")
			local centre = (shellPart and shellPart.Position) or basePivot.Position

			-- everything except the shell is a decoration to burst outward --
			-- see the header note on why this beats a fixed prefix whitelist.
			local decorations = {}
			for _, d in ipairs(eggClone:GetDescendants()) do
				if d:IsA("BasePart") and d ~= shellPart then
					decorations[#decorations + 1] = d
				end
			end
			-- cap the tween count: the biggest MAX_EXPLODE pieces fly outward,
			-- the rest (barely visible slivers on a 97-part Crown egg) just
			-- vanish instantly instead of paying for a tween nobody would see
			table.sort(decorations, function(a, b) return volumeOf(a) > volumeOf(b) end)
			for i, part in ipairs(decorations) do
				if i <= MAX_EXPLODE then
					local targetPos = centre + (part.Position - centre) * CRACK_DIST_MULT
					local targetCFrame = CFrame.new(targetPos) * (part.CFrame - part.CFrame.Position)
					TweenService:Create(part, TweenInfo.new(CRACK_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						CFrame = targetCFrame, Transparency = 1,
					}):Play()
				else
					part.Transparency = 1
				end
			end

			if shellPart then
				TweenService:Create(shellPart, TweenInfo.new(CRACK_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Transparency = 1,
				}):Play()
			end
		end

		task.delay(CRACK_TIME, function()
			if myGen ~= revealGen then return end
			creaturePhase()
		end)
	end

	---------------------------------------------------- CREATURE
	creaturePhase = function()
		if eggVp then eggVp:Destroy(); eggVp = nil end
		eggClone = nil

		local card, outer = UITheme.accentCard(holder, accent, 20)
		outer.Name = "RevealTile"
		outer.Size = UDim2.fromOffset(VP_SIZE + 20, VP_SIZE + 20)
		outer.Position = UDim2.fromOffset(-10, -10)
		outer.ZIndex = 12
		card.ZIndex = 13
		-- Rare and up get glow / shimmer / sparkles / a cycling border, same
		-- ladder as every other tile in the game (RarityFX itself decides
		-- Common/Uncommon get nothing).
		RarityFX.attach(outer, card, result.Rarity, accent, 0)
		table.insert(fades, { outer, "BackgroundTransparency" })
		table.insert(fades, { card, "BackgroundTransparency" })

		local creatureVp = new("ViewportFrame", {
			Name = "CreatureViewport", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 14,
		}, card)
		local ccam = new("Camera", { FieldOfView = 30 }, creatureVp)
		creatureVp.CurrentCamera = ccam
		table.insert(fades, { creatureVp, "ImageTransparency" })

		local master = BrainrotThumb.master(result.Name)
		if master then
			local m = master:Clone()
			m.Parent = creatureVp
			local centre, dist = BrainrotThumb.framing(m, 30)
			local creatureStart = elapsed
			spinFn = function(t)
				local ang = ((t - creatureStart) / SPIN_TIME) * (2 * math.pi)
				local dir = CFrame.Angles(0, ang, 0) * BrainrotThumb.DEFAULT_DIR
				ccam.CFrame = CFrame.lookAt(centre + dir * dist, centre)
			end
		else
			-- no model for this name: a flat rarity swatch keeps the tile
			-- readable instead of leaving a hole (same fallback BackpackClient uses)
			local sw = new("Frame", {
				Size = UDim2.fromScale(1, 1), BackgroundColor3 = accent, BackgroundTransparency = 0.5, ZIndex = 14,
			}, card)
			UITheme.corner(sw, 12)
		end

		local nameLabel = new("TextLabel", {
			Name = "CreatureName", Position = UDim2.fromOffset(-90, VP_SIZE + 14),
			Size = UDim2.fromOffset(VP_SIZE + 180, 34), BackgroundTransparency = 1, Font = FONT, TextSize = 24,
			TextColor3 = CF.onDark, TextTruncate = Enum.TextTruncate.AtEnd, Text = result.Name, ZIndex = 16,
		}, holder)
		local nameInk = UITheme.inkText(nameLabel, 2.8)
		table.insert(fades, { nameLabel, "TextTransparency" })
		table.insert(fades, { nameInk, "Transparency" })

		local tierLabel = new("TextLabel", {
			Name = "CreatureTier", Position = UDim2.fromOffset(-90, VP_SIZE + 50),
			Size = UDim2.fromOffset(VP_SIZE + 180, 26), BackgroundTransparency = 1, Font = FONT, TextSize = 18,
			TextColor3 = accent, Text = string.upper(tostring(result.Rarity or "?")), ZIndex = 16,
		}, holder)
		local tierInk = UITheme.inkText(tierLabel, 2.2)
		table.insert(fades, { tierLabel, "TextTransparency" })
		table.insert(fades, { tierInk, "Transparency" })

		task.delay(CREATURE_HOLD, function()
			if myGen ~= revealGen then return end
			skip()
		end)
	end
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
	-- setOpen first so darrel/quest state refreshes and the panel is the one
	-- playReveal hides behind its own overlay; playReveal restores
	-- frame.Visible itself when the reveal ends or is skipped.
	setOpen(true)
	playReveal(result)
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
