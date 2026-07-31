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
-- Darrel's face, drawn from primitives (UIKit.IconArt). pcall'd so a missing
-- module leaves the shop working with the old emoji rather than failing to open.
local okIconArt, IconArt = pcall(function()
	return require(ReplicatedStorage.Modules.UIKit.IconArt)
end)
if not okIconArt then IconArt = nil end

local CF = UITheme.Camp
local FONT = UITheme.Font
local WORLD_ID = "Forest"
local world = EggConfig.GetWorld(WORLD_ID)

-- creature name -> tier colour, same lookup pattern BackpackClient/EggHandler use
local PetConfig = require(ReplicatedStorage.Modules.PetConfig)

local tierByName, rarityByName = {}, {}
for _, t in ipairs(RarityConfig) do tierByName[t.Name] = t end
for _, e in ipairs(BrainrotConfig.List or BrainrotConfig) do rarityByName[e.Name] = e.Rarity end

-- Egg tables name PETS as of 2026-08-01, so rarity resolves through PetConfig
-- first. The BrainrotConfig fallback is still live for the ten retired stand-in
-- pets, which are brainrots and have no PetConfig-only rarity of their own.
-- Pet tiers (Rare..Secret) all exist in RarityConfig, so the colour lookup is
-- unchanged either way.
local function rarityOf(creatureName)
	local id = PetConfig.IdFor(creatureName)
	local def = id and PetConfig.Pets[id]
	if def then return def.Rarity end
	return rarityByName[creatureName]
end

local function tierColor(creatureName)
	local tier = tierByName[rarityOf(creatureName)]
	return tier and tier.Color or CF.ink
end

-- The hatch reveal spins the PET that was just hatched. BrainrotThumb.master is
-- hardwired to ReplicatedStorage.BrainrotModels, so pets need their own lookup
-- against PetModels (child named after the imported .glb, per PetConfig.Model),
-- falling through to BrainrotThumb for the retired stand-ins. Masters are cached
-- per key exactly like BrainrotThumb does, so a reveal clones rather than
-- rebuilds.
local petMasters = {}
local function petMaster(creatureName, petId)
	local key = petId or creatureName
	if key and petMasters[key] then return petMasters[key] end
	local folder = ReplicatedStorage:FindFirstChild("PetModels")
	local def = petId and PetConfig.Pets[petId]
	local src = folder and ((def and def.Model and folder:FindFirstChild(def.Model))
		or (creatureName and folder:FindFirstChild(creatureName)))
	if src then
		local m = src:Clone()
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false end
		end
		if key then petMasters[key] = m end
		return m
	end
	return BrainrotThumb.master(creatureName)
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
local FRAME_W = 640
-- The fit was hard-capped at 1x, so on any normal monitor the panel stopped dead at
-- its design 640x520 and read small -- there was headroom it simply refused to use.
-- Allow a modest upscale instead; still capped, because the UIScale magnifies the ink
-- strokes and text along with everything else.
local MAX_SCALE = 1.35
local BOTTOM_MARGIN = 16          -- was 40; the extra 24px is real height on a short window
local hudScale = new("UIScale", { Name = "HudFixScale" }, frame)
local function relayout()
	local vh, vw = gui.AbsoluteSize.Y, gui.AbsoluteSize.X
	if vh <= 0 then return end
	-- Width is now part of the fit. It never was before, which was a latent bug rather
	-- than a style choice: at 1x a 640-wide panel already overflowed anything narrower
	-- than 640, and raising the cap would have made that worse on a phone.
	local s = math.min(MAX_SCALE,
		(vh - 146 - BOTTOM_MARGIN) / FRAME_H,
		(vw - 32) / FRAME_W)
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
-- The balance used to read "\u{1F48E} 0" -- a generic diamond emoji for a
-- currency that is named after, and has, an actual mascot. Darrel's face goes
-- in a slot on the left and the label keeps just the number.
local DARREL_ICON = 30
local darrelIcon = new("Frame", {
	Name = "DarrelIcon",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 10, 0.5, 0),
	Size = UDim2.fromOffset(DARREL_ICON, DARREL_ICON),
	BackgroundTransparency = 1,
	ZIndex = 13,
}, darrelChip)
if IconArt and IconArt.has("darrel") then
	IconArt.draw(darrelIcon, "darrel", DARREL_ICON, 13)
end

local darrelLabel = new("TextLabel", {
	Position = UDim2.fromOffset(DARREL_ICON + 16, 0),
	Size = UDim2.new(1, -(DARREL_ICON + 26), 1, 0),
	BackgroundTransparency = 1, Font = FONT, TextSize = 20,
	TextColor3 = CF.onDark, Text = IconArt and "0" or "\u{1F48E} 0", ZIndex = 13,
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
	-- reward is right-aligned, so Darrel sits to the RIGHT of the number here
	-- (trailing the value, where the emoji used to be) rather than leading it
	local REWARD_ICON = 15
	local rewardIcon = new("Frame", {
		Name = "RewardIcon",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 1, -14),
		Size = UDim2.fromOffset(REWARD_ICON, REWARD_ICON),
		BackgroundTransparency = 1, Visible = false, ZIndex = 14,
	}, row)
	if IconArt and IconArt.has("darrel") then
		IconArt.draw(rewardIcon, "darrel", REWARD_ICON, 14)
	end

	local reward = new("TextLabel", {
		Position = UDim2.new(0.5, 4, 1, -22),
		Size = UDim2.new(0.5, -12 - (IconArt and (REWARD_ICON + 5) or 0), 0, 16),
		BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = CF.amber2,
		TextXAlignment = Enum.TextXAlignment.Right, Text = "", ZIndex = 13,
	}, row)
	local check = new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(20, 20),
		BackgroundTransparency = 1, Font = FONT, TextSize = 16, TextColor3 = CF.pine1,
		Text = "\u{2713}", Visible = false, ZIndex = 14,
	}, row)
	UITheme.inkText(check, 2)
	questRows[i] = { row = row, text = text, progress = progress, reward = reward, rewardIcon = rewardIcon, check = check }
end

local function refreshQuests(daily)
	local quests = (daily and daily.Quests) or {}
	for i, ui in ipairs(questRows) do
		local q = quests[i]
		ui.row.Visible = q ~= nil
		if q then
			ui.text.Text = q.Text or ""
			ui.progress.Text = ("%d/%d"):format(q.Progress or 0, q.Target or 0)
			ui.reward.Text = "+" .. tostring(q.Reward or 0) .. (IconArt and "" or "\u{1F48E}")
			-- the icon only appears alongside a populated row, so it hides and shows
			-- with the row's own text rather than floating on an empty card
			if ui.rewardIcon then ui.rewardIcon.Visible = (IconArt ~= nil) end
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

	-- Price reads "<face> 25" rather than "25<diamond emoji>": Darrel's face
	-- leads, the same order the balance chip and the HUD pill use, so a player
	-- scanning prices against their balance sees the same mark in both places.
	local PRICE_ICON = 18
	local priceIcon = new("Frame", {
		Name = "PriceIcon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 90, 0, 48),
		Size = UDim2.fromOffset(PRICE_ICON, PRICE_ICON),
		BackgroundTransparency = 1, ZIndex = 14,
	}, header)
	if IconArt and IconArt.has("darrel") then
		IconArt.draw(priceIcon, "darrel", PRICE_ICON, 14)
	end

	local priceLabel = new("TextLabel", {
		Position = UDim2.fromOffset(90 + PRICE_ICON + 6, 38), Size = UDim2.new(1, -(220 + PRICE_ICON + 6), 0, 20),
		BackgroundTransparency = 1, Font = FONT, TextSize = 15, TextColor3 = CF.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = (IconArt and "" or "") .. tostring(egg.Price) .. (IconArt and "" or "\u{1F48E}"), ZIndex = 14,
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
-- Full-screen dim + a single ViewportFrame carried through four phases:
-- SHAKE (egg jitters in place), CRACK x3 (the PLAYER taps the egg three times;
-- each tap fractures the shell at the point that was hit and punches the egg so
-- it rings down), SPLIT (the shell opens while every non-shell
-- part bursts outward), CREATURE (viewport swaps to the hatched brainrot,
-- tier-lit tile, slow spin). "Non-shell part" rather than a fixed name-prefix
-- whitelist: the five egg models carry a `ring_*`/`tape_*` family alongside
-- the documented shard/drip/spike/horn/stripe/stud/rune/crown/link/cap/halo
-- ones, so matching everything except shell_body_* is what actually covers
-- every decoration on every egg instead of silently stranding a family that
-- was never on the list.
--
-- The three hits are what sell it, and they only read as three if the egg is
-- STILL between them -- so the idle shake stops at SHAKE_TIME and each hit
-- fires its own decaying jolt instead.
--
-- CRACK waits on player input rather than a timer, so it needs a way out that a
-- timer-driven phase did not: TAP_TIMEOUT cracks the egg on its own if nobody
-- taps. Without it a hatch could sit forever with the shop panel hidden behind
-- this overlay and the player's darrels already spent.
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
local EGG_FOV = 32
local SHAKE_TIME, SHAKE_HZ, SHAKE_DEG = 0.9, 20, 4
local CRACKS_TO_OPEN = 3
-- See the header note: the reveal must never wait forever. Once the FIRST
-- timeout fires the player is plainly not tapping, so the rest run themselves
-- off quickly -- three full-length waits back to back would strand an AFK
-- player behind the overlay for thirteen seconds.
local TAP_TIMEOUT, TAP_TIMEOUT_FAST = 3.5, 0.9
local TAP_DEBOUNCE = 0.15 -- so mashing cannot land all three hits inside one frame
local SPLIT_DELAY = 0.34  -- a beat of stillness after the last hit before the shell goes
local JOLT_TIME, JOLT_HZ, JOLT_DEG = 0.22, 16, 2.2
local HIT_SOUND  = { "eggCrack1", "eggCrack2", "eggCrack3" }
local HIT_TAIL   = { "eggCrumble", "eggCrumble", "eggCrumbleBig" }
local HIT_VOLUME = { 0.34, 0.40, 0.46 }
local HIT_SPEED  = { 1.10, 1.00, 0.94 }
local SPLIT_TIME, CRACK_DIST_MULT, MAX_EXPLODE = 0.5, 2.5, 60
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

-- The shell's tangent frame at rest. Flattened camera direction, not an
-- arbitrary model axis: a fracture has to land on the face the viewport camera
-- actually looks at, and every egg here is built unrotated at the origin so
-- world axes are the shell's axes.
local function shellFrame(shellPart)
	local out = Vector3.new(BrainrotThumb.DEFAULT_DIR.X, 0, BrainrotThumb.DEFAULT_DIR.Z).Unit
	return out, Vector3.yAxis:Cross(out).Unit,
		shellPart.Size.X / 2, shellPart.Size.Y / 2, shellPart.Position
end

-- A crack is grown as a 2D random walk in the shell's (side, up) tangent plane,
-- then pushed back onto the ellipsoid so it follows the curve of the shell
-- instead of lying flat across it.
--
-- Four things the previous fixed zigzag had none of are what make this read as a
-- real fracture rather than a drawn line: the walk TURNS by a random amount at
-- every step, each sliver TAPERS as it travels away from the impact, hairline
-- BRANCHES fork off partway along, and the whole thing propagates BOTH WAYS from
-- the point that was struck -- which is what a hit shell actually does.
local CRACK_COLOR = Color3.fromRGB(16, 12, 10)

local function growCrack(eggClone, shellPart, s0, y0, hit, rng)
	local made = {}
	if not shellPart then return made end
	local out, side, hx, hy, centre = shellFrame(shellPart)

	-- One sliver at tangent coordinate (s, y), angled along its direction of
	-- travel. Returns false once the walk has wandered past the silhouette,
	-- where there is no front face left to scar.
	local function place(s, y, len, thick, ang)
		local k = 1 - (y / hy) ^ 2 - (s / hx) ^ 2
		if k <= 0.03 then return false end
		local pos = centre + side * s + Vector3.yAxis * y + out * (hx * math.sqrt(k) * 0.98)
		local dir = (Vector3.yAxis * math.cos(ang) + side * math.sin(ang)).Unit
		local seg = Instance.new("Part")
		seg.Name = "crack"
		seg.Anchored, seg.CanCollide, seg.CanQuery, seg.CastShadow = true, false, false, false
		seg.Material = Enum.Material.SmoothPlastic
		seg.Color = CRACK_COLOR
		seg.Size = Vector3.new(thick, len, thick)
		-- built from the basis directly rather than lookAt+roll: the sliver's long
		-- axis IS its direction of travel, so the two can never disagree
		seg.CFrame = CFrame.fromMatrix(pos, dir:Cross(-out), dir)
		seg.Parent = eggClone
		made[#made + 1] = seg
		return true
	end

	local function walk(s, y, ang, steps, len, thick)
		for i = 1, steps do
			local f = 1 - 0.55 * ((i - 1) / steps) -- taper away from the impact
			if not place(s, y, len * f, thick * f, ang) then break end
			s += math.sin(ang) * len * f * 0.85
			y += math.cos(ang) * len * f * 0.85
			ang += math.rad(rng:NextNumber(-26, 26))
		end
	end

	local steps = 3 + hit                    -- 4, 5, 6 -- later hits travel further
	local len = hy * 0.17
	local thick = hx * (0.075 + 0.018 * hit)
	local ang = rng:NextNumber(-0.55, 0.55)  -- broadly vertical, never twice the same

	walk(s0, y0, ang, steps, len, thick)
	walk(s0, y0, ang + math.pi, steps, len, thick)

	for _ = 1, hit - 1 do                    -- 0, then 1, then 2 hairline branches
		local away = (rng:NextInteger(0, 1) == 0 and 1 or -1) * rng:NextNumber(0.6, 1.1)
		local d = len * rng:NextNumber(0.8, 1.8)
		walk(s0 + math.sin(ang) * d, y0 + math.cos(ang) * d, ang + away,
			math.max(2, steps - 2), len * 0.8, thick * 0.55)
	end
	return made
end

-- Shell flakes knocked loose by a hit. Same colour and material as the shell
-- they came off, so they read as debris rather than as more decoration.
local function spawnChips(eggClone, shellPart, s0, y0, count, rng)
	if not shellPart then return end
	local out, side, hx, hy, centre = shellFrame(shellPart)
	for _ = 1, count do
		local s = s0 + rng:NextNumber(-0.12, 0.12) * hx
		local y = y0 + rng:NextNumber(-0.12, 0.12) * hy
		local k = math.max(0.05, 1 - (y / hy) ^ 2 - (s / hx) ^ 2)
		local pos = centre + side * s + Vector3.yAxis * y + out * (hx * math.sqrt(k))
		local chip = Instance.new("Part")
		chip.Name = "chip"
		chip.Anchored, chip.CanCollide, chip.CanQuery, chip.CastShadow = true, false, false, false
		chip.Material = shellPart.Material
		chip.Color = shellPart.Color
		chip.Size = Vector3.one * (hx * rng:NextNumber(0.05, 0.10))
		chip.CFrame = CFrame.new(pos)
		chip.Parent = eggClone
		local fly = pos + out * rng:NextNumber(0.15, 0.40)
			+ side * rng:NextNumber(-0.30, 0.30)
			- Vector3.yAxis * rng:NextNumber(0.30, 0.70)
		TweenService:Create(chip, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = CFrame.new(fly) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)),
			Transparency = 1,
		}):Play()
	end
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
	local shellPart, decorations, crackParts = nil, {}, {}
	local joltStart, joltMag, splitting = nil, 1, false

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
	local eggClone, basePivot, eggVp, eggCam, eggCentre, eggDist
	local eggMasterModel = eggModelName and eggMaster(eggModelName)
	if eggMasterModel then
		eggVp = new("ViewportFrame", {
			Name = "EggViewport", Size = UDim2.fromOffset(VP_SIZE, VP_SIZE), BackgroundTransparency = 1, ZIndex = 3,
		}, holder)
		-- camera and framing are kept: mapping a tap back onto the shell needs both
		eggCam = new("Camera", { FieldOfView = EGG_FOV }, eggVp)
		eggVp.CurrentCamera = eggCam
		eggClone = eggMasterModel:Clone()
		eggClone.Parent = eggVp
		basePivot = eggClone:GetPivot()
		eggCentre, eggDist = BrainrotThumb.framing(eggClone, EGG_FOV)
		eggCam.CFrame = CFrame.lookAt(eggCentre + BrainrotThumb.DEFAULT_DIR * eggDist, eggCentre)

		-- Captured HERE, before any crack geometry exists. "Everything that is not
		-- the shell is a decoration" still holds, but the crack slivers and the two
		-- shell halves added later are also non-shell parts, so scanning at SPLIT
		-- time would sweep the fissure itself into the burst list.
		shellPart = eggClone:FindFirstChild("shell_body_1")
		for _, d in ipairs(eggClone:GetDescendants()) do
			if d:IsA("BasePart") and d ~= shellPart then
				decorations[#decorations + 1] = d
			end
		end
		-- cap the tween count: the biggest MAX_EXPLODE pieces fly outward, the rest
		-- (barely visible slivers on a 200-part Crown egg) just vanish instantly
		-- instead of paying for a tween nobody would see
		table.sort(decorations, function(a, b) return volumeOf(a) > volumeOf(b) end)
	end

	local beginCracking, armTap, crackBeat, splitPhase, creaturePhase

	conn = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		-- `splitting` gates this off entirely: once SPLIT starts, the halves are
		-- driven by tweens and a PivotTo here would fight them every frame.
		if eggClone and basePivot and not splitting then
			if elapsed <= SHAKE_TIME then
				local w = elapsed * SHAKE_HZ * (2 * math.pi)
				local rx = math.rad(SHAKE_DEG) * math.sin(w)
				local ry = math.rad(SHAKE_DEG) * math.sin(w * 1.31 + 1.7)
				local rz = math.rad(SHAKE_DEG) * math.sin(w * 0.77 + 0.4)
				eggClone:PivotTo(basePivot * CFrame.Angles(rx, ry, rz))
			elseif joltStart then
				-- Each beat punches the egg and lets it ring down to rest. The
				-- stillness in between is the whole point -- continuing the idle
				-- jitter here would blur three hits back into one long wobble.
				local t = elapsed - joltStart
				if t < JOLT_TIME then
					local decay = (1 - t / JOLT_TIME) ^ 2
					local a = math.rad(JOLT_DEG) * joltMag * decay * math.sin(t * JOLT_HZ * (2 * math.pi))
					eggClone:PivotTo(basePivot * CFrame.Angles(a * 0.5, a, a * 0.8))
				else
					eggClone:PivotTo(basePivot)
					joltStart = nil
				end
			end
		end
		if spinFn then spinFn(elapsed) end
	end)

	task.delay(SHAKE_TIME, function()
		if myGen ~= revealGen then return end
		beginCracking()
	end)

	---------------------------------------------------- CRACK (player-driven)
	-- The egg no longer cracks itself: each hit is a tap ON the egg, and the
	-- fracture starts AT the point that was tapped. crackBtn sits at ZIndex 21,
	-- one rung above the full-screen clickCatcher, so a tap on the egg cracks it
	-- while a tap anywhere else still skips the reveal.
	local rng = Random.new()
	local hits = 0
	local tapToken = 0  -- bumped by every hit; a stale timeout sees the change and no-ops
	local lastTap = -1
	local timedOut = false -- latched once the player has shown they are not tapping
	local crackBtn, hintLabel

	-- Screen point -> a coordinate in the shell's (side, up) tangent plane. The
	-- viewport is square and FieldOfView is vertical, so one half-extent covers
	-- both axes.
	local function tangentFromScreen(px, py)
		local _, side, hx, hy, shellPos = shellFrame(shellPart)
		local abs, sz = eggVp.AbsolutePosition, eggVp.AbsoluteSize
		local u = (px - abs.X) / math.max(1, sz.X)
		local v = (py - abs.Y) / math.max(1, sz.Y)
		local halfExtent = math.tan(math.rad(EGG_FOV / 2)) * eggDist
		local camCF = eggCam.CFrame
		local world = eggCentre
			+ camCF.RightVector * ((u - 0.5) * 2 * halfExtent)
			+ camCF.UpVector * ((0.5 - v) * 2 * halfExtent)
		local rel = world - shellPos
		local s, y = rel:Dot(side), rel:Dot(Vector3.yAxis)
		-- A tap out near the silhouette would start a crack on the rim, where the
		-- surface curves away and there is no front face to draw on. Pull it back
		-- onto the cap that faces the camera.
		local e = (s / hx) ^ 2 + (y / hy) ^ 2
		if e > 0.6 then
			local k = math.sqrt(0.6 / e)
			s, y = s * k, y * k
		end
		return s, y
	end

	-- Hidden rather than destroyed: both are registered in `fades`, and skip()
	-- tweens everything in there -- tweening a Destroy()'d instance throws.
	local function hidePrompt()
		tapToken += 1
		if crackBtn then crackBtn.Active, crackBtn.Visible = false, false end
		if hintLabel then hintLabel.Visible = false end
	end

	armTap = function()
		tapToken += 1
		local myToken = tapToken
		if hintLabel then
			local left = CRACKS_TO_OPEN - hits
			hintLabel.Text = (hits == 0) and "TAP THE EGG TO CRACK IT"
				or ((left == 1) and "ONE MORE!" or (left .. " MORE!"))
		end
		task.delay(timedOut and TAP_TIMEOUT_FAST or TAP_TIMEOUT, function()
			if myGen ~= revealGen or myToken ~= tapToken then return end
			timedOut = true
			local _, _, hx, hy = shellFrame(shellPart)
			crackBeat(rng:NextNumber(-0.3, 0.3) * hx, rng:NextNumber(-0.35, 0.35) * hy)
		end)
	end

	beginCracking = function()
		if not (eggClone and shellPart and eggVp) then
			splitPhase() -- no egg model resolved: nothing to tap, so go straight through
			return
		end
		SoundKit.play("eggStrain", nil, { volume = 0.16, speed = 0.9 })

		crackBtn = new("TextButton", {
			Name = "CrackButton", Size = UDim2.fromOffset(VP_SIZE, VP_SIZE),
			BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 21,
		}, holder)
		hintLabel = new("TextLabel", {
			Name = "CrackHint", Position = UDim2.fromOffset(-90, VP_SIZE + 14),
			Size = UDim2.fromOffset(VP_SIZE + 180, 30), BackgroundTransparency = 1,
			Font = FONT, TextSize = 20, TextColor3 = CF.onDark, Text = "", ZIndex = 22,
		}, holder)
		local hintInk = UITheme.inkText(hintLabel, 2.4)
		table.insert(fades, { hintLabel, "TextTransparency" })
		table.insert(fades, { hintInk, "Transparency" })

		-- InputBegan, not Activated: Activated does not carry a position, and the
		-- position is the whole point of tapping the egg rather than a button.
		crackBtn.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch then return end
			if myGen ~= revealGen or hits >= CRACKS_TO_OPEN then return end
			if elapsed - lastTap < TAP_DEBOUNCE then return end
			lastTap = elapsed
			crackBeat(tangentFromScreen(input.Position.X, input.Position.Y))
		end)

		armTap()
	end

	crackBeat = function(s0, y0)
		hits += 1
		local n = math.min(hits, CRACKS_TO_OPEN)
		SoundKit.play(HIT_SOUND[n], nil, { volume = HIT_VOLUME[n], speed = HIT_SPEED[n] })
		SoundKit.play(HIT_TAIL[n], nil, { volume = 0.20 + 0.04 * n, speed = 0.95 })

		-- Everything already drawn widens a little. A shell does not keep its first
		-- crack hairline once you have hit it twice more.
		for _, seg in ipairs(crackParts) do
			seg.Size = Vector3.new(seg.Size.X * 1.13, seg.Size.Y, seg.Size.Z * 1.13)
		end
		for _, seg in ipairs(growCrack(eggClone, shellPart, s0, y0, n, rng)) do
			crackParts[#crackParts + 1] = seg
		end
		spawnChips(eggClone, shellPart, s0, y0, 2 + n, rng)

		joltStart, joltMag = elapsed, n -- later hits hit harder

		if hits >= CRACKS_TO_OPEN then
			hidePrompt()
			task.delay(SPLIT_DELAY, function()
				if myGen ~= revealGen then return end
				splitPhase()
			end)
		else
			armTap()
		end
	end

	---------------------------------------------------- SPLIT
	splitPhase = function()
		joltStart, splitting = nil, true
		SoundKit.play("eggSplit", nil, { volume = 0.5 })
		SoundKit.play("catchSparkle", nil, { volume = 0.3, speed = 1.1 })

		if eggClone then
			local centre = (shellPart and shellPart.Position) or basePivot.Position
			local ease = TweenInfo.new(SPLIT_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

			-- The shell is ONE Part carrying a Sphere SpecialMesh, so there is no
			-- half to peel off -- it gets swapped for two clones at half height,
			-- which the mesh refits to on its own. Two domes parting with a
			-- tier-coloured flash between them reads as a shell opening; the
			-- rounded cut faces are never still long enough to give it away.
			if shellPart then
				local sz = shellPart.Size
				local function half(sign, name)
					local h = shellPart:Clone()
					h.Name = "shell_half_" .. name
					h.Size = Vector3.new(sz.X, sz.Y / 2, sz.Z)
					h.CFrame = shellPart.CFrame * CFrame.new(0, sign * sz.Y / 4, 0)
					h.Parent = eggClone
					return h
				end
				local top, bottom = half(1, "top"), half(-1, "bottom")
				shellPart.Transparency = 1

				TweenService:Create(top, ease, {
					CFrame = top.CFrame * CFrame.new(0, sz.Y * 0.85, 0) * CFrame.Angles(math.rad(38), 0, math.rad(22)),
					Transparency = 1,
				}):Play()
				TweenService:Create(bottom, ease, {
					CFrame = bottom.CFrame * CFrame.new(0, -sz.Y * 0.30, 0) * CFrame.Angles(math.rad(-16), 0, math.rad(-12)),
					Transparency = 1,
				}):Play()
			end

			-- Flash in the widening gap, tier-coloured so the reveal's accent lands
			-- a beat before the creature tile carrying that same accent does.
			local flash = Instance.new("Part")
			flash.Name = "split_flash"
			flash.Anchored, flash.CanCollide, flash.CanQuery, flash.CastShadow = true, false, false, false
			flash.Material = Enum.Material.Neon
			flash.Color = accent
			flash.Size = Vector3.one * 0.2
			flash.CFrame = CFrame.new(centre)
			local fmesh = Instance.new("SpecialMesh")
			fmesh.MeshType = Enum.MeshType.Sphere
			fmesh.Parent = flash
			flash.Parent = eggClone
			TweenService:Create(flash, TweenInfo.new(SPLIT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.one * ((shellPart and shellPart.Size.X * 1.6) or 3),
				Transparency = 1,
			}):Play()

			-- the fissure goes with the shell it was drawn on
			for _, seg in ipairs(crackParts) do
				TweenService:Create(seg, TweenInfo.new(SPLIT_TIME * 0.5), { Transparency = 1 }):Play()
			end

			for i, part in ipairs(decorations) do
				if i <= MAX_EXPLODE then
					local targetPos = centre + (part.Position - centre) * CRACK_DIST_MULT
					local targetCFrame = CFrame.new(targetPos) * (part.CFrame - part.CFrame.Position)
					TweenService:Create(part, TweenInfo.new(SPLIT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						CFrame = targetCFrame, Transparency = 1,
					}):Play()
				else
					part.Transparency = 1
				end
			end
		end

		task.delay(SPLIT_TIME, function()
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

		local master = petMaster(result.Name, result.PetId)
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
		darrelLabel.Text = (IconArt and "" or "\u{1F48E} ") .. tostring(math.floor(payload.Darrels))
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
