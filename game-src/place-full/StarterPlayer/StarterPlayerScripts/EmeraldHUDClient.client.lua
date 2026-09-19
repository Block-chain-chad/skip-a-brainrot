-- EmeraldHUDClient -- always-visible emerald-balance chip, pinned directly under
-- the cash pill (StarterGui.MainUI.CashFrame). Self-owned ScreenGui, same
-- pattern as LuckHUDClient: MainUI and ClientMain are never touched.
--
-- POSITION MATH: MainUI ignores the gui inset (IgnoreGuiInset = true), so its
-- cash pill sits at RAW SCREEN y 12..58 (Position y=12, Height=46, confirmed
-- live off StarterGui.MainUI.CashFrame). This gui instead uses ScreenInsets =
-- CoreUISafeInsets with IgnoreGuiInset left FALSE -- Roblox offsets THIS gui's
-- y=0 to the safe-area inset, which on a normal (non-notched) screen lands at
-- screen y=58, exactly where the cash pill ends. So gui-local y=6 here renders
-- at screen y=64: 6px clear of the pill, no manual inset arithmetic needed.
--
-- Chip screen-extent: x = viewport-170..viewport-12, y = 64..102.
-- HUD overlap check: TabBar (ClientMain's teleport rail) sits centered at the
-- TOP of the screen -- normal desktop/tablet widths keep its whole bar (up to
-- 318px wide at the WIDE metrics) within roughly viewport/2 +/- 160px, nowhere
-- near this chip's right-edge band. See the build report for the one
-- narrow-viewport (<~580px) caveat where TabBar's own "stack under the pill"
-- fallback (UNDER_PILL_Y = 66) could theoretically graze this same y-band --
-- a pre-existing ClientMain responsive edge case, not something this script
-- can or should fix.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local modules = ReplicatedStorage:WaitForChild("Modules")

local UIStyle = require(modules:WaitForChild("UIStyle")) -- same pill/gradient/stroke language as ClientMain's cash pill
local UITheme = require(modules:WaitForChild("UITheme")) -- UITheme.Font (Cartoon) for the label
local NumberFormat = require(modules:WaitForChild("NumberFormat")) -- canonical abbreviator; 1500 must read like cash does
local BrainrotThumb = require(modules:WaitForChild("BrainrotThumb")) -- reuse its bounding-box camera framing math

-- ===== ScreenGui: self-owned, DisplayOrder 5, under CoreUISafeInsets =====
local gui = Instance.new("ScreenGui")
gui.Name = "EmeraldHUD"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.IgnoreGuiInset = false
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets end)
gui.Parent = playerGui

-- Gains ("+N") get their OWN ScreenGui at a high DisplayOrder so nothing -- the
-- cash pill, the buy button, the teleport rail -- can ever render over them. The
-- balance chip stays at DisplayOrder 5; this floats above the lot.
local popGui = Instance.new("ScreenGui")
popGui.Name = "EmeraldGainPop"
popGui.ResetOnSpawn = false
popGui.DisplayOrder = 60
popGui.IgnoreGuiInset = false
pcall(function() popGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets end)
popGui.Parent = playerGui

-- ===== Chip: 158x38, top-right, directly under the cash pill =====
local chip = Instance.new("Frame")
chip.Name = "EmeraldChip"
chip.AnchorPoint = Vector2.new(1, 0)
chip.Position = UDim2.new(1, -12, 0, 6)
chip.Size = UDim2.fromOffset(158, 38)
chip.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
chip.BorderSizePixel = 0
chip.Parent = gui

-- Same construction ClientMain uses for the cash pill (UIStyle.pill for the
-- fully-rounded corner family, UIStyle.gradient for the vertical tint, a white
-- UIStyle.stroke keyline) -- just Booth's teal accent instead of Gold, since
-- emeralds are a different currency and teal reads correctly under the diamond
-- glyph + teal-cream label below.
UIStyle.pill(chip)
UIStyle.gradient(chip, UIStyle.Palette.Booth)
UIStyle.stroke(chip, Color3.fromRGB(255, 255, 255), 3.5)

-- Scale pop lives on the chip root so the medallion and label bump together.
local popScale = Instance.new("UIScale")
popScale.Parent = chip

-- ===== Medallion: 30x30 ViewportFrame, EmeraldBust's head only =====
local MEDALLION_SIZE, MEDALLION_MARGIN = 30, 4

local function buildMedallion()
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Medallion"
	vp.Position = UDim2.fromOffset(MEDALLION_MARGIN, MEDALLION_MARGIN)
	vp.Size = UDim2.fromOffset(MEDALLION_SIZE, MEDALLION_SIZE)
	vp.BackgroundTransparency = 1
	vp.Parent = chip

	local source = ReplicatedStorage:FindFirstChild("EmeraldBust")
	if not source then return end -- degrade to chip+label only if the mascot ever goes missing

	local head = source:Clone()
	-- Strip the shoulder/crewneck parts so the medallion reads as head + cap +
	-- locs + glasses only (ShoulderBase, Neck) -- matched BY NAME rather than a
	-- hand-picked keep-list, so a future EmeraldBust rename/addition degrades
	-- gracefully instead of silently leaking a shoulder into a 30px head icon.
	for _, d in ipairs(head:GetDescendants()) do
		if d:IsA("BasePart") then
			local n = d.Name:lower()
			if n:find("shoulder", 1, true) or n:find("crew", 1, true) or n:find("neck", 1, true) then
				d:Destroy()
			end
		end
	end
	head.Parent = vp

	-- Same bounding-box camera framing SideRail/BrainrotThumb/EggShopClient's
	-- reveal already use (BrainrotThumb.framing): centre + direction * distance,
	-- looked at. EmeraldBust's face parts (mustache/grin/chin beard) all sit on
	-- the +Z side of HeadCore, opposite the -Z "faces away" convention the body
	-- models use, so the camera direction here is +Z, not BrainrotThumb.DEFAULT_DIR's
	-- -Z. A static 10-degree yaw off dead-on gives the medallion some character
	-- without any per-frame driver -- computed ONCE, since this is a permanent
	-- HUD element with no per-frame polling loop anywhere in this script.
	local FOV = 30
	local centre, dist = BrainrotThumb.framing(head, FOV)
	local YAW = math.rad(10)
	local dir = CFrame.Angles(0, YAW, 0) * Vector3.new(0, 0.15, 1).Unit

	local cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	cam.CFrame = CFrame.lookAt(centre + dir * dist, centre)
	cam.Parent = vp
	vp.CurrentCamera = cam
end

buildMedallion()

-- ===== Label: "\u{1F48E} N", right-padded 10 from the chip's edge =====
local LABEL_LEFT = MEDALLION_MARGIN + MEDALLION_SIZE + 6 -- clears the medallion + a small gap
local LABEL_RIGHT_PAD = 10

local label = Instance.new("TextLabel")
label.Name = "EmeraldLabel"
label.BackgroundTransparency = 1
label.AnchorPoint = Vector2.new(0, 0.5)
label.Position = UDim2.new(0, LABEL_LEFT, 0.5, 0)
label.Size = UDim2.new(1, -(LABEL_LEFT + LABEL_RIGHT_PAD), 1, -8)
label.Font = UITheme.Font
label.TextScaled = true
label.TextColor3 = Color3.fromRGB(180, 240, 225) -- teal-tinted cream
label.Text = "\u{1F48E} 0"
label.Parent = chip

local labelStroke = Instance.new("UIStroke")
labelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
labelStroke.LineJoinMode = Enum.LineJoinMode.Round
labelStroke.Color = Color3.fromRGB(62, 34, 19) -- ink outline
labelStroke.Thickness = 2
labelStroke.Parent = label

-- ===== Balance state + increase-only pop feedback =====
local emeralds = 0
local hasLoaded = false -- true once ANY source (push or pull) has set a real value

local function setLabelText(n)
	label.Text = "\u{1F48E} " .. NumberFormat.Short(n)
end

local activePop
local function playPop()
	if activePop then activePop:Cancel() end
	popScale.Scale = 1
	local up = TweenService:Create(popScale, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.08 })
	up.Completed:Connect(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed then
			activePop = TweenService:Create(popScale, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
			activePop:Play()
		end
	end)
	activePop = up
	up:Play()
end

-- ===== Floating "+N" gain ticker =====
-- A small teal "+N" that appears at the chip's right edge and drifts DOWNWARD a
-- little while fading, each time the balance goes up. Down, not up, on purpose:
-- the chip is pinned to the very top of the screen (cash pill above it, teleport
-- rail beside it), so a rising number would collide with all of that -- drifting
-- down keeps it clear of everything and out of the play area. Parented to the gui
-- rather than the chip so the chip's pop-scale can't stretch it, and right-aligned
-- so it never reaches left into the scene. Each call makes its own label that
-- cleans itself up, so overlapping gains just stack briefly and never leak.
local GAIN_TEXT_SIZE = 16
local function playGain(amount)
	if typeof(amount) ~= "number" or amount <= 0 then return end
	local g = Instance.new("TextLabel")
	g.Name = "EmeraldGain"
	g.BackgroundTransparency = 1
	g.AnchorPoint = Vector2.new(0.5, 1)
	-- Sits in the gap just right of the balance number, up near the chip's top edge
	-- (where the player circled it), and pops UPWARD from there. x/y here are the two
	-- knobs: -48 from the right edge is the number->buy-button gap; y is the baseline.
	g.Position = UDim2.new(1, -48, 0, 16)
	g.Size = UDim2.fromOffset(90, 22)
	g.Font = UITheme.Font
	g.TextXAlignment = Enum.TextXAlignment.Center
	g.TextSize = GAIN_TEXT_SIZE
	g.TextColor3 = Color3.fromRGB(140, 240, 180)  -- gain green-teal, distinct from the balance's cream
	g.Text = "+" .. NumberFormat.Short(amount)
	g.ZIndex = 6
	g.Parent = popGui

	local gs = Instance.new("UIStroke")
	gs.Color = Color3.fromRGB(62, 34, 19)
	gs.Thickness = 1.5
	gs.Parent = g

	-- Quick upward pop-in (Back easing overshoots a touch), a plain hold, then a
	-- fade+drift out. The hold is an explicit task.delay rather than a delayed tween
	-- so it can't fight the entrance tween over the shared Position property (that
	-- interaction was leaving the label invisible).
	local HOLD, FADE = 3.4, 0.6
	TweenService:Create(g, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(1, -48, 0, 4) }):Play()
	task.delay(0.2 + HOLD, function()
		if not g.Parent then return end
		local info = TweenInfo.new(FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local fade = TweenService:Create(g, info, { Position = UDim2.new(1, -48, 0, -8), TextTransparency = 1 })
		TweenService:Create(gs, info, { Transparency = 1 }):Play()
		fade.Completed:Connect(function() g:Destroy() end)
		fade:Play()
	end)
end

-- Shared by both the push and the pull paths below so the pop-on-increase
-- rule can't drift between them. The FIRST call (whichever source wins the
-- join-time race) only hydrates the label -- popping on initial load would
-- read as a fake "you just earned this" cue for a balance that was already
-- there.
local function applyEmeralds(n)
	if typeof(n) ~= "number" then return end
	local prev = emeralds
	emeralds = n
	setLabelText(n)
	if hasLoaded and n > prev then playPop(); playGain(n - prev) end -- Emil-style: earning pops, spending stays silent
	hasLoaded = true
end

remotes.EmeraldUpdate.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end
	applyEmeralds(payload.Darrels)
end)

-- Startup pull, mirroring EggShopClient/LuckHUDClient's own join-time invoke:
-- EmeraldUpdate's server push can race this script's listener connecting, and
-- EmeraldState self-heals server-side (EmeraldService.Init) if the RemoteFunction
-- was ever missing, so this is safe to invoke unconditionally.
task.spawn(function()
	local ok, res = pcall(function()
		return remotes.EmeraldState:InvokeServer()
	end)
	if ok and typeof(res) == "table" then
		applyEmeralds(res.Darrels)
	end
end)
