-- ToastClient -- the ONLY renderer for {Success, Message} server replies.
-- (BUILD SPEC v2 §7.4, USER DECISION U3)
--
-- Before this script, ClientMain's PurchaseResult/SellResult handlers were empty comment
-- bodies, so every server message in the game was silently discarded. Without a renderer
-- every TryLike rejection string goes nowhere and the like feature cannot be QA'd.
--
-- RemoteEvents support multiple connections, so ClientMain's existing (empty) handlers are
-- harmless and are deliberately left untouched -- zero edits to ClientMain from this file.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local P = UITheme.Palette
local CF = UITheme.Camp

local MAX_TOASTS = 3
local HOLD = 2.6
local SLIDE = 0.18
local FADE = 0.35
local WIDTH, HEIGHT = 420, 50

local screen = Instance.new("ScreenGui")
screen.Name = "ToastGui"
screen.DisplayOrder = 60
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local stack = Instance.new("Frame")
stack.Name = "Stack"
stack.AnchorPoint = Vector2.new(0.5, 0)
stack.Position = UDim2.new(0.5, 0, 0, 88)
stack.Size = UDim2.new(0, WIDTH, 0, 0)
stack.BackgroundTransparency = 1
stack.AutomaticSize = Enum.AutomaticSize.Y
stack.Parent = screen

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.VerticalAlignment = Enum.VerticalAlignment.Top
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = stack

local live = {}     -- array of active toast wrappers, oldest first
local seq = 0

local function dismiss(entry)
	if entry.dismissed then return end
	entry.dismissed = true
	for i, e in ipairs(live) do
		if e == entry then table.remove(live, i) break end
	end
	local info = TweenInfo.new(FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(entry.card, info, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(entry.label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	if entry.stroke then TweenService:Create(entry.stroke, info, { Transparency = 1 }):Play() end
	if entry.gloss then TweenService:Create(entry.gloss, info, { BackgroundTransparency = 1 }):Play() end
	if entry.accent then TweenService:Create(entry.accent, info, { BackgroundTransparency = 1 }):Play() end
	if entry.accentInk then TweenService:Create(entry.accentInk, info, { Transparency = 1 }):Play() end
	if entry.textStroke then TweenService:Create(entry.textStroke, info, { Transparency = 1 }):Play() end
	Debris:AddItem(entry.wrapper, FADE + 0.05)
end

local function push(success, message)
	-- cap the stack: dismiss the oldest early rather than letting toasts pile up
	while #live >= MAX_TOASTS do
		dismiss(live[1])
	end

	seq += 1
	local wrapper = Instance.new("Frame")
	wrapper.Name = "Toast" .. seq
	wrapper.Size = UDim2.new(0, WIDTH, 0, HEIGHT)
	wrapper.BackgroundTransparency = 1
	wrapper.BorderSizePixel = 0
	wrapper.ClipsDescendants = true      -- lets the card slide in from the right edge
	wrapper.LayoutOrder = seq
	wrapper.Parent = stack

	-- inset from the clipping wrapper: a stroke drawn on the wrapper's own edge is clipped away
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.new(1, -10, 1, -8)
	card.Position = UDim2.new(0, WIDTH, 0, 4)   -- off to the right, slides to x = 5
	card.BorderSizePixel = 0
	card.Parent = wrapper
	UITheme.campPanel(card)
	UITheme.corner(card, 12)

	-- campPanel adds the heavy border UIStroke; it stays BLACK and the success/fail
	-- colour rides the accent bar instead (campfire style)
	local stroke
	for _, s in ipairs(card:GetChildren()) do
		if s:IsA("UIStroke") and s.ApplyStrokeMode ~= Enum.ApplyStrokeMode.Contextual then stroke = s end
	end
	if stroke then
		stroke.Color = CF.ink
		stroke.Thickness = 3
	end

	local accTop = success and CF.pine1 or CF.ember1
	local accBot = success and CF.pine2 or CF.ember2

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Size = UDim2.new(0, 7, 1, -14)
	accent.Position = UDim2.new(0, 9, 0, 7)
	accent.BackgroundColor3 = accTop
	accent.BorderSizePixel = 0
	accent.ZIndex = 2
	accent.Parent = card
	UITheme.corner(accent, 4)
	UITheme.gradient(accent, accTop, accBot, 90)
	local accentInk = UITheme.ink(accent, 2)

	local label = Instance.new("TextLabel")
	label.Name = "Msg"
	label.Size = UDim2.new(1, -40, 1, 0)
	label.Position = UDim2.new(0, 26, 0, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 18
	label.TextColor3 = CF.cream
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = message
	label.ZIndex = 2
	label.Parent = card

	-- heavy black glyph outline: campfire text is never left un-inked
	local ts = UITheme.inkText(label, 2.6)

	local entry = {
		wrapper = wrapper, card = card, label = label, stroke = stroke,
		gloss = card:FindFirstChild("Gloss"), dismissed = false,
		accent = accent, accentInk = accentInk, textStroke = ts,
	}
	table.insert(live, entry)

	TweenService:Create(card, TweenInfo.new(SLIDE, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 5, 0, 4),
	}):Play()

	task.delay(SLIDE + HOLD, function() dismiss(entry) end)
end

-- Payload guard: every producer in this game uses { Success = bool, Message = string },
-- but a malformed/absent field must never throw inside a remote handler.
local function show(res)
	if type(res) ~= "table" or type(res.Message) ~= "string" then return end
	push(res.Success == true, res.Message)
end

for _, name in ipairs({ "PurchaseResult", "SellResult", "LikeResult" }) do
	local r = remotes:WaitForChild(name, 10)
	if r then
		r.OnClientEvent:Connect(show)
	else
		warn("[ToastClient] remote missing: " .. name)
	end
end
