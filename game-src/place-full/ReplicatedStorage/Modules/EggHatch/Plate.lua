--!strict
-- EggHatch.Plate: the name + rarity plate under a revealed creature. It is only ever
-- built AFTER the reward is on screen (the controller orders it that way), so nothing
-- textual can spoil the reveal. Name pops first, the rarity chip lands a beat later,
-- then any tags (a mutation, a size class). NoPolish: the chip's colour IS the tier.

local TweenService = game:GetService("TweenService")

local Config = require(script.Parent.Config)

local FONT = Enum.Font.FredokaOne
local INK = Color3.fromRGB(7, 19, 35)

local Plate = {}
Plate.__index = Plate

export type Info = {
	name: string, rarity: string?, colour: Color3, tags: { { any } }?,
	scale: number, slam: boolean?,
}

local function backOut(u: number): number
	u = math.clamp(u, 0, 1)
	local s = 1.70158
	local x = u - 1
	return x * x * ((s + 1) * x + s) + 1
end

local function label(parent: Instance, text: string, size: number, colour: Color3, strokeColour: Color3, strokeT: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.Text = text
	l.TextSize = size
	l.TextColor3 = colour
	l.Size = UDim2.fromOffset(10, size + 6)
	l.AutomaticSize = Enum.AutomaticSize.X
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.ZIndex = 12
	local s = Instance.new("UIStroke")
	s.Thickness = strokeT
	s.Color = strokeColour
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = l
	l.Parent = parent
	return l
end

-- at: gui pixel position of the plate's TOP-CENTRE. vpH: viewport height in px.
function Plate.new(layer: Frame, at: Vector2, vpH: number, info: Info)
	local self = setmetatable({}, Plate) :: any
	local base = math.clamp(vpH * 0.056, 18, 46) * info.scale
	local nameSize = math.floor(base)
	local chipSize = math.floor(base * 0.52)
	self.dead = false

	local root = Instance.new("Frame")
	root.Name = "Plate"
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.fromOffset(at.X, at.Y)
	root.Size = UDim2.fromOffset(10, 10)
	root.AutomaticSize = Enum.AutomaticSize.XY
	root.BackgroundTransparency = 1
	root.ZIndex = 11
	root:SetAttribute("NoPolish", true)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, math.floor(base * 0.12))
	list.Parent = root
	root.Parent = layer
	self.root = root

	-- the name: white, inked, pops in from small
	local nameHolder = Instance.new("Frame")
	nameHolder.BackgroundTransparency = 1
	nameHolder.AutomaticSize = Enum.AutomaticSize.XY
	nameHolder.Size = UDim2.fromOffset(10, 10)
	nameHolder.LayoutOrder = 1
	nameHolder.ZIndex = 11
	nameHolder.Parent = root
	local nameL = label(nameHolder, info.name, nameSize, Color3.new(1, 1, 1), INK, math.max(2, nameSize * 0.11))
	local nameScale = Instance.new("UIScale")
	nameScale.Scale = 0
	nameScale.Parent = nameHolder
	self.nameScale = nameScale
	self.nameL = nameL

	-- the chip row: rarity pill + tags
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.AutomaticSize = Enum.AutomaticSize.XY
	row.Size = UDim2.fromOffset(10, 10)
	row.LayoutOrder = 2
	row.ZIndex = 11
	local rl = Instance.new("UIListLayout")
	rl.FillDirection = Enum.FillDirection.Horizontal
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rl.VerticalAlignment = Enum.VerticalAlignment.Center
	rl.SortOrder = Enum.SortOrder.LayoutOrder
	rl.Padding = UDim.new(0, math.floor(base * 0.18))
	rl.Parent = row
	row.Parent = root
	local rowScale = Instance.new("UIScale")
	rowScale.Scale = 0
	rowScale.Parent = row
	self.rowScale = rowScale

	local function chip(text: string, fill: Color3, order: number)
		local c = Instance.new("Frame")
		c.BackgroundColor3 = fill
		c.AutomaticSize = Enum.AutomaticSize.XY
		c.Size = UDim2.fromOffset(10, chipSize + math.floor(base * 0.22))
		c.LayoutOrder = order
		c.ZIndex = 12
		local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(1, 0); corner.Parent = c
		local stroke = Instance.new("UIStroke"); stroke.Color = INK; stroke.Thickness = math.max(1.5, base * 0.06); stroke.Parent = c
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, math.floor(base * 0.34))
		pad.PaddingRight = UDim.new(0, math.floor(base * 0.34))
		pad.Parent = c
		-- dark text on a bright tier colour, white on a dark one
		local _, _, v = fill:ToHSV()
		local textCol = (v > 0.72) and INK or Color3.new(1, 1, 1)
		local l = label(c, string.upper(text), chipSize, textCol, INK, (v > 0.72) and 0 or math.max(1.5, chipSize * 0.1))
		l.Size = UDim2.new(0, 10, 1, 0)
		l.TextYAlignment = Enum.TextYAlignment.Center
		c.Parent = row
		return c
	end
	if info.rarity then chip(info.rarity, info.colour, 1) end
	for i, tag in ipairs(info.tags or {}) do chip(tag[1], tag[2], 1 + i) end

	return self
end

-- Animates in: the name now, the chip row a beat later. Returns when the row lands.
-- timeScale stretches the tweens (1 / run speed) so a slowed run stays coherent.
function Plate:show(slam: boolean?, timeScale: number?): number
	if self.dead then return 0 end
	local ts = timeScale or 1
	local nameInfo = TweenInfo.new(0.20 * ts, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(self.nameScale, nameInfo, { Scale = 1 }):Play()
	local delay = 0.08 * ts
	task.delay(delay, function()
		if self.dead then return end
		if slam then
			self.rowScale.Scale = 1.5
			TweenService:Create(self.rowScale, TweenInfo.new(0.14 * ts, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		else
			TweenService:Create(self.rowScale, TweenInfo.new(0.18 * ts, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end)
	return delay + 0.2 * ts
end

-- clean exit: scales away with the reward
function Plate:exit(seconds: number)
	if self.dead then return end
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(self.nameScale, info, { Scale = 0 }):Play()
	TweenService:Create(self.rowScale, info, { Scale = 0 }):Play()
end

function Plate:fade(seconds: number)
	if self.dead then return end
	for _, d in ipairs(self.root:GetDescendants()) do
		if d:IsA("TextLabel") then
			TweenService:Create(d, TweenInfo.new(seconds), { TextTransparency = 1 }):Play()
		elseif d:IsA("UIStroke") then
			TweenService:Create(d, TweenInfo.new(seconds), { Transparency = 1 }):Play()
		elseif d:IsA("Frame") and d.BackgroundTransparency < 1 then
			TweenService:Create(d, TweenInfo.new(seconds), { BackgroundTransparency = 1 }):Play()
		end
	end
end

function Plate:destroy()
	if self.dead then return end
	self.dead = true
	self.root:Destroy()
end

return Plate
