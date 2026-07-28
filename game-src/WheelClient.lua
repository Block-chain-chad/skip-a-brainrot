-- WheelClient: the daily spin wheel.
--
-- Walk into the ring by the wheel and the full-screen wheel comes up on its own; walk
-- away and it goes. The physical wheel in the world spins in step with it, so bystanders
-- see it turn too.
--
-- This script decides NOTHING. The server rolls, pays out, and broadcasts which slot won;
-- every client animates to that slot locally. A laggy client cannot stall anyone else.
--
-- The wedges are drawn, not an image asset: a fan of thin bars inside a circular mask (a
-- square Frame with a 0.5 UICorner and ClipsDescendants), which clips their square ends
-- to a clean circle. Note GuiObject.Rotation pivots about an object's CENTRE, not its
-- AnchorPoint -- so every radial piece is centred at half its length along its own ray.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local WheelConfig = require(ReplicatedStorage.Modules.WheelConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)

local spunRemote  = remotes:WaitForChild("WheelSpun")
local stateRemote = remotes:WaitForChild("WheelState")
local spinRemote  = remotes:WaitForChild("WheelSpin")

local SLOTS = WheelConfig.SLOTS
local N = #SLOTS
local SEG = 360 / N

local WHEEL_PX   = 560
local R          = WHEEL_PX / 2
local WINDUP_T   = 0.55
local WINDUP_DEG = 22
local SPIN_T     = 6.2
local TURNS      = 9
local TICK_GAP   = 0.055
local TOAST_HOLD = 5.0

local NEAR, FAR  = 15, 21     -- hysteresis: open inside NEAR, close outside FAR

local INK = Color3.fromRGB(16, 14, 20)

local function new(cls, props, parent)
	local o = Instance.new(cls)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

-- heavy black outline on everything, which is what makes the reference readable
local function stroke(o, thickness)
	new("UIStroke", {
		Color = INK, Thickness = thickness or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, o)
	return o
end

--=================================== shell =================================--
local gui = new("ScreenGui", {
	Name = "WheelUI", ResetOnSpawn = false, DisplayOrder = 12,
	IgnoreGuiInset = true, Enabled = true,
}, player:WaitForChild("PlayerGui"))

local root = new("Frame", {
	Name = "Root", BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1), Visible = false,
}, gui)

-- Dim the world behind the wheel. Without it the saturated wedges compete with grass,
-- trees and the rest of the HUD and the whole thing reads as noise.
new("Frame", {
	Name = "Scrim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 0,
}, root)

local holder = new("Frame", {
	Name = "Holder", BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.50, 0),
	Size = UDim2.fromOffset(WHEEL_PX, WHEEL_PX),
}, root)
local holderScale = new("UIScale", { Scale = 1 }, holder)
-- keeps the whole wheel on screen on short or mobile viewports
new("UISizeConstraint", { MaxSize = Vector2.new(WHEEL_PX, WHEEL_PX) }, holder)

-- thick outer rim, like the reference's grey bezel
local bezel = new("Frame", {
	Name = "Bezel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(WHEEL_PX + 54, WHEEL_PX + 54),
	BackgroundColor3 = Color3.fromRGB(150, 155, 165), BorderSizePixel = 0,
}, holder)
new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, bezel)
stroke(bezel, 5)
new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(196, 201, 210), Color3.fromRGB(112, 117, 128)),
	Rotation = 90,
}, bezel)

local mask = new("Frame", {
	Name = "Mask", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(30, 32, 38),
	BorderSizePixel = 0, ClipsDescendants = true,
}, holder)
new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, mask)

local spinner = new("Frame", {
	Name = "Spinner", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
}, mask)

--================================== wedges =================================--
local function radial(frame, angleDeg, len)
	local a = math.rad(angleDeg)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, math.sin(a) * len / 2, 0.5, -math.cos(a) * len / 2)
	frame.Rotation = angleDeg
end

local barsBySlot = {}
local BAR_STEP = 1.5
local barW = math.ceil(2 * R * math.sin(math.rad(BAR_STEP) / 2)) + 3

for i, slot in ipairs(SLOTS) do
	barsBySlot[i] = {}
	for b = 0, math.floor(SEG / BAR_STEP) - 1 do
		local bar = new("Frame", {
			Name = ("S%dB%d"):format(i, b), Size = UDim2.fromOffset(barW, R),
			BackgroundColor3 = slot.Colour, BorderSizePixel = 0,
		}, spinner)
		radial(bar, (i - 1) * SEG + b * BAR_STEP + BAR_STEP / 2, R)
		table.insert(barsBySlot[i], bar)
	end
end

-- divider spokes
for i = 1, N do
	local sp = new("Frame", {
		Name = "Spoke" .. i, Size = UDim2.fromOffset(5, R),
		BackgroundColor3 = Color3.fromRGB(240, 242, 246), BorderSizePixel = 0, ZIndex = 4,
	}, spinner)
	radial(sp, (i - 1) * SEG, R)
end

-- Per-wedge text stack, laid out at three radii like the reference: big name on the
-- outer arc, icon and value in the belly, percentage near the hub.
-- A wedge is only 2*r*tan(SEG/2) wide at radius r, so a label sized for the rim will
-- spill into its neighbours near the hub -- which is exactly what happened first pass:
-- the values and percentages piled up into an unreadable knot around the centre. Every
-- label is now capped to the width actually available where it sits.
local TAN_HALF = math.tan(math.rad(SEG / 2))
local function wedgeWidth(rr) return 2 * rr * TAN_HALF * 0.86 end

for i, slot in ipairs(SLOTS) do
	local mid = (i - 1) * SEG + SEG / 2
	local a = math.rad(mid)
	local function at(rr, w, h)
		return UDim2.new(0.5, math.sin(a) * rr, 0.5, -math.cos(a) * rr),
			UDim2.fromOffset(math.min(w, wedgeWidth(rr)), h)
	end

	local p, s = at(R * 0.76, 215, 44)
	local name = new("TextLabel", {
		Name = "Name" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = p, Size = s,
		BackgroundTransparency = 1, Rotation = mid, Text = slot.Name,
		Font = Enum.Font.FredokaOne, TextScaled = true,
		TextColor3 = slot.Text or Color3.fromRGB(255, 255, 255), ZIndex = 6,
	}, spinner)
	new("UITextSizeConstraint", { MaxTextSize = 30 }, name)
	stroke(name, 3)

	p, s = at(R * 0.40, 86, 86)
	new("TextLabel", {
		Name = "Icon" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = p, Size = s,
		BackgroundTransparency = 1, Rotation = mid, Text = slot.Icon,
		Font = Enum.Font.FredokaOne, TextScaled = true, ZIndex = 6,
	}, spinner)

	p, s = at(R * 0.60, 170, 30)
	local val = new("TextLabel", {
		Name = "Val" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = p, Size = s,
		BackgroundTransparency = 1, Rotation = mid, Text = slot.Value,
		Font = Enum.Font.FredokaOne, TextScaled = true,
		TextColor3 = slot.Text or Color3.fromRGB(255, 255, 255), ZIndex = 6,
	}, spinner)
	new("UITextSizeConstraint", { MaxTextSize = 21 }, val)
	stroke(val, 2.5)

	p, s = at(R * 0.205, 70, 26)
	local pct = new("TextLabel", {
		Name = "Pct" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = p, Size = s,
		BackgroundTransparency = 1, Rotation = mid, Text = slot.Weight .. "%",
		Font = Enum.Font.FredokaOne, TextScaled = true,
		TextColor3 = slot.Text or Color3.fromRGB(255, 255, 255), ZIndex = 6,
	}, spinner)
	new("UITextSizeConstraint", { MaxTextSize = 19 }, pct)
	stroke(pct, 2.5)
end

-- hub and pointer live OUTSIDE the spinner so they hold still while it turns
local hub = new("Frame", {
	Name = "Hub", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(76, 76), BackgroundColor3 = Color3.fromRGB(206, 196, 176),
	BorderSizePixel = 0, ZIndex = 10,
}, holder)
new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, hub)
stroke(hub, 5)

-- white triangle, built from a rotated square so no image asset is needed
local ptrHolder = new("Frame", {
	Name = "Pointer", AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(60, 60),
	BackgroundTransparency = 1, ZIndex = 12, ClipsDescendants = true,
}, holder)
local ptrTri = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.fromOffset(42, 42), Rotation = 45,
	BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0, ZIndex = 12,
}, ptrHolder)
stroke(ptrTri, 4)

--================================== chrome =================================--
local title = new("TextLabel", {
	Name = "Title", AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.105, 0), Size = UDim2.fromOffset(520, 68),
	BackgroundTransparency = 1, Text = "DAILY SPIN", Font = Enum.Font.FredokaOne,
	TextScaled = true, TextColor3 = Color3.fromRGB(255, 176, 46), ZIndex = 14,
}, root)
new("UITextSizeConstraint", { MaxTextSize = 64 }, title)
stroke(title, 5)

local closeBtn = new("TextButton", {
	Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -22, 0, 22),
	Size = UDim2.fromOffset(56, 56), Text = "", Font = Enum.Font.FredokaOne,
	TextScaled = true, TextColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundColor3 = Color3.fromRGB(224, 58, 58), AutoButtonColor = true, ZIndex = 14,
}, root)
new("UICorner", { CornerRadius = UDim.new(0, 12) }, closeBtn)
stroke(closeBtn, 4)
-- Draws the X as two rotated Frames (UITheme.closeGlyph), not text -- the
-- glyph U+2715 does not render in this Roblox build. Deliberately NOT
-- UITheme.styleClose: this button's 56px size, position and red are custom
-- to the wheel and styleClose would reset them to the 30px standard.
UITheme.closeGlyph(closeBtn)

local spinBtn = new("TextButton", {
	Name = "SpinBtn", AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -104), Size = UDim2.fromOffset(320, 74),
	Text = "SPIN", Font = Enum.Font.FredokaOne, TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 255, 255), AutoButtonColor = false,
	BackgroundColor3 = Color3.fromRGB(88, 200, 62), ZIndex = 14,
}, root)
new("UICorner", { CornerRadius = UDim.new(0, 16) }, spinBtn)
new("UITextSizeConstraint", { MaxTextSize = 42 }, spinBtn)
stroke(spinBtn, 4)

local subLabel = new("TextLabel", {
	Name = "Sub", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -186),
	Size = UDim2.fromOffset(520, 34), BackgroundTransparency = 1, Text = "",
	Font = Enum.Font.FredokaOne, TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 255, 255), ZIndex = 14,
}, root)
new("UITextSizeConstraint", { MaxTextSize = 26 }, subLabel)
stroke(subLabel, 3)

local banner = new("Frame", {
	Name = "Banner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.16, 0),
	Size = UDim2.fromOffset(560, 84), BackgroundColor3 = Color3.fromRGB(20, 24, 30),
	BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, ZIndex = 16,
}, root)
new("UICorner", { CornerRadius = UDim.new(0, 16) }, banner)
local bannerStroke = new("UIStroke", { Color = INK, Thickness = 4, Transparency = 1 }, banner)
local bannerScale = new("UIScale", { Scale = 1 }, banner)
local bannerText = new("TextLabel", {
	Name = "Text", Size = UDim2.new(1, -24, 1, -18), Position = UDim2.new(0, 12, 0, 9),
	BackgroundTransparency = 1, Text = "", Font = Enum.Font.FredokaOne, TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 208, 70), ZIndex = 17,
}, banner)
new("UITextSizeConstraint", { MaxTextSize = 40 }, bannerText)
stroke(bannerText, 3.5)

local toastToken = 0
local function showResult(text, colour)
	toastToken += 1
	local mine = toastToken
	bannerText.Text = text
	bannerText.TextColor3 = colour or Color3.fromRGB(255, 208, 70)
	banner.Visible = true
	banner.BackgroundTransparency = 0.1
	bannerStroke.Transparency = 0
	bannerText.TextTransparency = 0
	bannerScale.Scale = 0.6
	TweenService:Create(bannerScale, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }):Play()
	task.delay(TOAST_HOLD, function()
		if mine ~= toastToken then return end
		local ti = TweenInfo.new(0.5)
		TweenService:Create(bannerText, ti, { TextTransparency = 1 }):Play()
		TweenService:Create(banner, ti, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(bannerStroke, ti, { Transparency = 1 }):Play()
		task.delay(0.55, function() if mine == toastToken then banner.Visible = false end end)
	end)
end

--================================== sounds =================================--
local sg = game:GetService("SoundService")
local tickSound = new("Sound", { SoundId = "rbxasset://sounds/switch.wav", Volume = 0.4 }, sg)
local winSound = new("Sound", { SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6 }, sg)

--=============================== world wheel ===============================--
-- Kept in sync so bystanders see the prop turn too. Bound with WaitForChild because the
-- model's parts and its SurfaceGui children stream in separately.
local worldWheel, worldSpinner, worldPointer, worldPtrBase
local function resolveWorld(model)
	if not model or not model.Parent then return end
	local face = model:WaitForChild("Face", 20)
	local wsg = face and face:WaitForChild("WheelFace", 20)
	local wmask = wsg and wsg:WaitForChild("Mask", 20)
	local sp = wmask and wmask:WaitForChild("Spinner", 20)
	if not sp then return end
	worldWheel, worldSpinner = model, sp
	worldPointer = model:FindFirstChild("Pointer")
	worldPtrBase = worldPointer and worldPointer.CFrame or nil
end

task.spawn(function()
	local gw = Workspace:WaitForChild("GameWorld", 30)
	if not gw then return end
	gw.ChildAdded:Connect(function(c)
		if c.Name == "DailyWheel" then task.spawn(resolveWorld, c) end
	end)
	local existing = gw:FindFirstChild("DailyWheel")
	if existing then task.spawn(resolveWorld, existing) end
end)

--================================= the spin ================================--
local spinToken = 0
local spinning = false
local cooldown, luckLeft, powerLeft = 0, 0, 0
local lastSync = os.clock()

local function ease(t)
	local KICK = 0.12
	if t < KICK then
		local u = t / KICK
		return (u * u) * KICK * 0.55
	end
	local u = (t - KICK) / (1 - KICK)
	return KICK * 0.55 + (1 - KICK * 0.55) * (1 - (1 - u) ^ 5)
end

local function hms(sec)
	sec = math.max(0, math.floor(sec))
	local h = math.floor(sec / 3600)
	local m = math.floor((sec % 3600) / 60)
	local s = sec % 60
	if h > 0 then return ("%dh %02dm"):format(h, m) end
	if m > 0 then return ("%dm %02ds"):format(m, s) end
	return ("%ds"):format(s)
end

local function refreshButton()
	if spinning then
		spinBtn.Text = "SPINNING..."
		spinBtn.BackgroundColor3 = Color3.fromRGB(150, 150, 156)
	elseif cooldown > 0 then
		spinBtn.Text = "NEXT SPIN " .. hms(cooldown)
		spinBtn.BackgroundColor3 = Color3.fromRGB(128, 132, 142)
	else
		spinBtn.Text = "SPIN"
		spinBtn.BackgroundColor3 = Color3.fromRGB(88, 200, 62)
	end
	local bits = {}
	if luckLeft > 0 then table.insert(bits, ("\u{1F340} LUCK %s"):format(hms(luckLeft))) end
	if powerLeft > 0 then table.insert(bits, ("\u{1F4AA} POWER %s"):format(hms(powerLeft))) end
	subLabel.Text = (#bits > 0) and table.concat(bits, "    ") or "one free spin every 24 hours"
end

local function flashWinner(index, myToken)
	local bars = barsBySlot[index]
	if not bars then return end
	local base = SLOTS[index].Colour
	local hot = Color3.new(math.min(base.R + 0.45, 1), math.min(base.G + 0.45, 1), math.min(base.B + 0.45, 1))
	for _ = 1, 3 do
		if myToken ~= spinToken then break end
		for _, b in ipairs(bars) do
			if b.Parent then TweenService:Create(b, TweenInfo.new(0.16), { BackgroundColor3 = hot }):Play() end
		end
		task.wait(0.17)
		if myToken ~= spinToken then break end
		for _, b in ipairs(bars) do
			if b.Parent then TweenService:Create(b, TweenInfo.new(0.16), { BackgroundColor3 = base }):Play() end
		end
		task.wait(0.17)
	end
	task.wait(0.18)
	for _, b in ipairs(bars) do if b.Parent then b.BackgroundColor3 = base end end
end

local function spin(index, onDone)
	spinToken += 1
	local myToken = spinToken
	spinning = true
	refreshButton()

	local startRot = spinner.Rotation
	local target = -((index - 1) * SEG + SEG / 2)
	while target > startRot - 360 * TURNS do target -= 360 end

	local windTo = startRot + WINDUP_DEG
	local wind = TweenService:Create(spinner,
		TweenInfo.new(WINDUP_T, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = windTo })
	if worldSpinner and worldSpinner.Parent then
		TweenService:Create(worldSpinner,
			TweenInfo.new(WINDUP_T, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = windTo }):Play()
	end
	wind:Play()
	wind.Completed:Wait()
	if myToken ~= spinToken then return end

	local from, span = windTo, target - windTo
	local t0, lastTick = os.clock(), 0
	local lastBoundary = math.floor((-from) / SEG)
	local kick, lastFrame = 0, os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if myToken ~= spinToken then conn:Disconnect() return end
		local nowT = os.clock()
		local dt = math.min(nowT - lastFrame, 0.1)
		lastFrame = nowT
		local t = math.clamp((nowT - t0) / SPIN_T, 0, 1)
		local rot = from + span * ease(t)
		spinner.Rotation = rot
		if worldSpinner and worldSpinner.Parent then worldSpinner.Rotation = rot end

		local boundary = math.floor((-rot) / SEG)
		if boundary ~= lastBoundary then
			lastBoundary = boundary
			if nowT - lastTick >= TICK_GAP then
				lastTick = nowT
				tickSound.PlaybackSpeed = 1.45 - 0.45 * t + (math.random() - 0.5) * 0.06
				tickSound:Play()
			end
			kick = 15 * (1 - t) + 4
		end
		-- spring back over time; snapping back next frame made it invisible
		kick = kick * math.exp(-dt * 11)
		ptrTri.Rotation = 45 - kick
		if worldPointer and worldPointer.Parent and worldPtrBase then
			worldPointer.CFrame = worldPtrBase * CFrame.Angles(0, 0, math.rad(-kick))
		end

		if t >= 1 then
			conn:Disconnect()
			spinner.Rotation = target % 360
			if worldSpinner and worldSpinner.Parent then worldSpinner.Rotation = target % 360 end
			ptrTri.Rotation = 45
			if worldPointer and worldPointer.Parent and worldPtrBase then worldPointer.CFrame = worldPtrBase end
			winSound:Play()
			spinning = false
			refreshButton()
			task.spawn(flashWinner, index, myToken)
			if onDone then onDone() end
		end
	end)
end

--============================== open and close =============================--
local isOpen = false
local function setOpen(on)
	if isOpen == on then return end
	isOpen = on
	if on then
		root.Visible = true
		holderScale.Scale = 0.82
		TweenService:Create(holderScale, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }):Play()
		stateRemote:FireServer()
	else
		root.Visible = false
	end
end

closeBtn.Activated:Connect(function() setOpen(false) end)

spinBtn.Activated:Connect(function()
	if spinning or cooldown > 0 then return end
	spinning = true
	refreshButton()
	spinRemote:FireServer()
	task.delay(8, function() if spinning then spinning = false; refreshButton() end end)
end)

-- Auto-open on approach, with hysteresis so standing on the boundary does not strobe the
-- UI. Closing is suppressed mid-spin so the wheel cannot vanish while it is still turning.
local manualClose = false
task.spawn(function()
	while true do
		task.wait(0.25)
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local anchor = worldWheel and (worldWheel.PrimaryPart or worldWheel:FindFirstChild("Base"))
		if hrp and anchor then
			local d = (hrp.Position - anchor.Position).Magnitude
			if d <= NEAR and not isOpen and not manualClose then
				setOpen(true)
			elseif d > FAR then
				manualClose = false
				if isOpen and not spinning then setOpen(false) end
			end
		end
	end
end)
-- pressing X should not immediately reopen while still standing in the ring
closeBtn.Activated:Connect(function() manualClose = true end)

--================================== remotes ================================--
spunRemote.OnClientEvent:Connect(function(index, whoName, text)
	if type(index) ~= "number" or not SLOTS[index] then return end
	local mine = (whoName == player.Name)
	spin(index, function()
		if mine then
			showResult("YOU WON  " .. tostring(text or ""), SLOTS[index].Colour)
		elseif whoName then
			showResult(tostring(whoName) .. " won " .. tostring(text or ""), SLOTS[index].Colour)
		end
	end)
end)

stateRemote.OnClientEvent:Connect(function(s)
	if type(s) ~= "table" then return end
	cooldown = tonumber(s.Cooldown) or 0
	luckLeft = tonumber(s.LuckLeft) or 0
	powerLeft = tonumber(s.PowerLeft) or 0
	lastSync = os.clock()
	if s.Error then showResult(tostring(s.Error), Color3.fromRGB(255, 120, 110)); spinning = false end
	if not s.Result then refreshButton() end
end)

task.spawn(function()
	while true do
		task.wait(1)
		local dt = os.clock() - lastSync
		lastSync = os.clock()
		if cooldown > 0 then cooldown = math.max(0, cooldown - dt) end
		if luckLeft > 0 then luckLeft = math.max(0, luckLeft - dt) end
		if powerLeft > 0 then powerLeft = math.max(0, powerLeft - dt) end
		if not spinning then refreshButton() end
	end
end)

refreshButton()
task.delay(2, function() stateRemote:FireServer() end)
