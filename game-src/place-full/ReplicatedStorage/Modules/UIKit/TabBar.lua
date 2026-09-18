--!strict
-- TabBar -- body-level tabs (spec 2026-09-18 UI foundation §6.3). One component, two
-- layouts: horizontal chips (Quests: MAIN / DAILY / EVENT) or a vertical rail of
-- icon-over-label tiles (the Bag's categories). Paint follows the handoff's grammar:
-- active = S.Role.Neutral (blue = navigation, white shout) + selection ring, inactive
-- = S.Role.Disabled (grey, dark ink). Hover pops the GLYPH only: the tiles are layout
-- children, and a Size tween on one re-flows the whole strip (2026-08-16 lesson).
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local S = require(script.Parent.SpecTheme)
local PC = require(script.Parent.PanelChrome)
local UI = require(script.Parent.Builders)
local SoundKit = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("SoundKit"))

export type Tab = { id: string, text: string, icon: string? }
export type Props = {
	tabs: { Tab }, selected: string?, onChanged: (id: string) -> (), orientation: string?,
	parent: Instance?, zIndex: number?, height: number?, width: number?, name: string?, textSize: number?,
}
export type Api = {
	root: Frame, set: (id: string) -> (), get: () -> string,
	setBadge: (id: string, n: number) -> (), destroy: () -> (),
}

local TabBar = {}

type Entry = { id: string, btn: TextButton, grad: UIGradient, label: TextLabel, labelStroke: UIStroke, ring: Frame, glyph: GuiObject, glyphRest: UDim2 }

local function corner(o: GuiObject, r: number)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o
end

local function paint(e: Entry, active: boolean)
	local ramp = if active then S.Role.Neutral else S.Role.Disabled
	e.btn.BackgroundColor3 = ramp[1]
	e.grad.Color = ColorSequence.new(ramp[1], ramp[2])
	e.label.TextColor3 = if active then Color3.new(1, 1, 1) else S.Surface.ReadInk
	e.labelStroke.Color = if active then S.Outline else Color3.new(1, 1, 1)
	e.ring.Visible = active
end

function TabBar.new(props: Props): Api
	local vertical = props.orientation == "vertical"
	local z = props.zIndex or (PC.zBase + 3)
	local h = props.height or (if vertical then 74 else 64)
	local textSize = props.textSize or math.clamp(math.floor(h * 0.36), 12, 26)
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

	local root = Instance.new("Frame")
	root.Name = props.name or "TabBar"
	root.BackgroundTransparency = 1
	root.ZIndex = z
	if vertical then
		root.Size = UDim2.new(0, props.width or 120, 0, 0)
		root.AutomaticSize = Enum.AutomaticSize.Y
	else
		root.Size = UDim2.new(0, 0, 0, h)
		root.AutomaticSize = Enum.AutomaticSize.X
	end
	local list = Instance.new("UIListLayout")
	list.FillDirection = if vertical then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, S.Space.small)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = root

	local entries: { [string]: Entry } = {}
	local current = props.selected or (props.tabs[1] and props.tabs[1].id) or ""

	local function select(id: string, fire: boolean)
		if not entries[id] then return end
		local changed = id ~= current
		current = id
		for eid, e in pairs(entries) do paint(e, eid == id) end
		if changed and fire then props.onChanged(id) end
	end

	for i, tab in ipairs(props.tabs) do
		local btn = Instance.new("TextButton")
		btn.Name = "Tab" .. tab.id
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.BorderSizePixel = 0
		btn.LayoutOrder = i
		btn.ZIndex = z + 1
		btn.BackgroundColor3 = S.Role.Disabled[1]
		if vertical then
			btn.Size = UDim2.new(1, 0, 0, h)
		else
			local bounds = TextService:GetTextSize(tab.text, textSize, S.Font.Shout, Vector2.new(4096, h))
			local w = math.max(props.width or 120, math.ceil(bounds.X) + (if tab.icon then 32 + 12 else 0) + 40)
			btn.Size = UDim2.fromOffset(w, h)
		end
		local radius = math.floor(h * 0.3)
		corner(btn, radius)
		local edge = Instance.new("UIStroke")
		edge.Thickness = if h < 48 then 3 else 4
		edge.Color = S.Outline
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.LineJoinMode = Enum.LineJoinMode.Round
		edge.Parent = btn
		local grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Color = ColorSequence.new(S.Role.Disabled[1], S.Role.Disabled[2])
		grad.Parent = btn
		btn:SetAttribute("NoPolish", true)

		-- selection ring OUTSIDE the tile (never clipped: neither btn nor root clips)
		local ring = Instance.new("Frame")
		ring.Name = "Ring"
		ring.BackgroundTransparency = 1
		ring.Position = UDim2.fromOffset(-4, -4)
		ring.Size = UDim2.new(1, 8, 1, 8)
		ring.ZIndex = z
		ring.Visible = false
		corner(ring, radius + 4)
		local rs = Instance.new("UIStroke")
		rs.Thickness = 3
		rs.Color = S.Role.Selection
		rs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rs.Parent = ring
		ring.Parent = btn

		local glyph: GuiObject
		local label: TextLabel
		if vertical then
			local iconH = if tab.icon then math.floor(h * 0.5) else 0
			if tab.icon then
				local ic = Instance.new("ImageLabel")
				ic.Name = "Icon"
				ic.Image = tab.icon
				ic.BackgroundTransparency = 1
				ic.ScaleType = Enum.ScaleType.Fit
				ic.AnchorPoint = Vector2.new(0.5, 0)
				ic.Position = UDim2.new(0.5, 0, 0, 4)
				ic.Size = UDim2.fromOffset(iconH, iconH)
				ic.ZIndex = z + 2
				ic.Parent = btn
				glyph = ic
			end
			label = PC.shout({
				name = "Label", text = tab.text, size = textSize, zIndex = z + 2, parent = btn, scaled = true,
				frameSize = UDim2.new(1, -8, 0, h - iconH - 8), position = UDim2.new(0, 4, 0, iconH + 4),
			})
			if not tab.icon then glyph = label end
		else
			local lx = 0
			if tab.icon then
				local ic = Instance.new("ImageLabel")
				ic.Name = "Icon"
				ic.Image = tab.icon
				ic.BackgroundTransparency = 1
				ic.ScaleType = Enum.ScaleType.Fit
				ic.AnchorPoint = Vector2.new(0, 0.5)
				ic.Position = UDim2.new(0, 12, 0.5, 0)
				ic.Size = UDim2.fromOffset(32, 32)
				ic.ZIndex = z + 2
				ic.Parent = btn
				glyph = ic
				lx = 32 + 12
			end
			label = PC.shout({
				name = "Label", text = tab.text, size = textSize, zIndex = z + 2, parent = btn, scaled = true,
				frameSize = UDim2.new(1, -(lx + 16), 1, 0), position = UDim2.new(0, lx + 8, 0, 0),
			})
			if not tab.icon then glyph = label end
		end
		local labelStroke = label:FindFirstChildOfClass("UIStroke") :: UIStroke

		local entry: Entry = { id = tab.id, btn = btn, grad = grad, label = label, labelStroke = labelStroke, ring = ring, glyph = glyph, glyphRest = glyph.Size }
		entries[tab.id] = entry

		-- glyph-only hover pop (+12%), never the tile
		local function pop(mult: number)
			local rest = entry.glyphRest
			local target = if mult == 1 then rest else UDim2.new(rest.X.Scale * mult, math.round(rest.X.Offset * mult), rest.Y.Scale * mult, math.round(rest.Y.Offset * mult))
			TweenService:Create(glyph, S.Tween.HoverIn, { Size = target }):Play()
		end
		btn.MouseEnter:Connect(function() if not touchOnly then pop(1.12) end end)
		btn.MouseLeave:Connect(function() pop(1) end)
		btn.Activated:Connect(function()
			pcall(SoundKit.play, S.Sound.Click, nil, { volume = 0.12 })
			select(tab.id, true)
		end)
		btn:SetAttribute("SfxWired", true)
		UI.touchMin(btn, 44)
		btn.Parent = root
	end

	select(current, false)

	local api: Api = {
		root = root,
		set = function(id: string) select(id, false) end,
		get = function() return current end,
		setBadge = function(id: string, n: number)
			local e = entries[id]
			if not e then return end
			local old = e.btn:FindFirstChild("Badge")
			if old then old:Destroy() end
			if n and n > 0 then
				local b = UI.badge(e.btn, n)
				b.Name = "Badge"
				b.AnchorPoint = Vector2.new(0.5, 0.5)
				b.Position = UDim2.new(1, -2, 0, 2)
				b.ZIndex = z + 4
			end
		end,
		destroy = function() root:Destroy() end,
	}
	root.Parent = props.parent
	return api
end

return TabBar
