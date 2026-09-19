--!strict
-- PanelChrome -- factory for every drawn part of the HUD-upgrade panel system
-- (design_handoff_hud_upgrade). One shell, six colourways; rows, pills, bars,
-- toggles, sliders, segments, rarity chips, section heads, corner ribbons.
--
-- Re-expressed from the handoff's reference module against THIS place's
-- constraints:
--   * UIScale/BackgroundTransparency/NumberValue tweens DO NOT RUN here
--     (probed live, see roblox-tweenservice-guiobject-only) -- press/hover
--     feedback tweens Size instead, the same trick the nav rail uses.
--   * StarterPlayerScripts.UIPolish force-restyles every text object without
--     a NoPolish attribute, so shout()/read() opt their labels out and carry
--     the spec's own two-typeface system (LuckiestGuy / FredokaOne).
--   * Panels mount into GameHUDClient's host at its zindex band, so nothing
--     here hardcodes the sheet's 100-band; zIndex threads through props.
--
-- Nothing here knows about gameplay. Compose a panel from these parts, then
-- wire the returned instances to your own controllers.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local S = require(script.Parent.SpecTheme)

local PanelChrome = {}

local Z = 30 -- default base; sits above host (26) under Sibling behaviour

------------------------------------------------------------------ primitives
local function corner(parent: GuiObject, radius: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function stroke(parent: GuiObject, thickness: number, color: Color3?): UIStroke
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or S.Outline
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
	return s
end

local function gradient(parent: GuiObject, top: Color3, bottom: Color3): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = 90
	g.Parent = parent
	return g
end

-- Depth from one light source: hard inner highlight on top, inner shade at
-- the bottom. No blur, no ambient glow (README rule 4).
local function gloss(frame: GuiObject, radius: number, shadeAlpha: number?)
	local hi = Instance.new("Frame")
	hi.Name = "Highlight"
	hi.BackgroundColor3 = Color3.new(1, 1, 1)
	hi.BackgroundTransparency = 0.58
	hi.BorderSizePixel = 0
	hi.Size = UDim2.new(1, 0, 0, math.max(4, math.floor(radius * 0.22)))
	hi.ZIndex = frame.ZIndex + 1
	corner(hi, radius)
	hi.Parent = frame

	local sh = Instance.new("Frame")
	sh.Name = "Shade"
	sh.BackgroundColor3 = Color3.new(0, 0, 0)
	sh.BackgroundTransparency = 1 - (shadeAlpha or 0.18)
	sh.BorderSizePixel = 0
	sh.AnchorPoint = Vector2.new(0, 1)
	sh.Position = UDim2.fromScale(0, 1)
	sh.Size = UDim2.new(1, 0, 0, math.max(5, math.floor(radius * 0.3)))
	sh.ZIndex = frame.ZIndex + 1
	corner(sh, radius)
	sh.Parent = frame
end

PanelChrome.zBase = Z

--- A filled, outlined, glossy plate. The base object of the whole system.
function PanelChrome.plate(props: {
	name: string?, size: UDim2, position: UDim2?, anchor: Vector2?,
	colors: { Color3 }, radius: number, outline: number,
	zIndex: number?, parent: Instance?, gloss: boolean?, layoutOrder: number?,
}): Frame
	local f = Instance.new("Frame")
	f.Name = props.name or "Plate"
	f.Size = props.size
	f.Position = props.position or UDim2.fromOffset(0, 0)
	f.AnchorPoint = props.anchor or Vector2.new(0, 0)
	f.BackgroundColor3 = props.colors[1]
	f.BorderSizePixel = 0
	f.ZIndex = props.zIndex or Z
	if props.layoutOrder then f.LayoutOrder = props.layoutOrder end
	corner(f, props.radius)
	stroke(f, props.outline)
	gradient(f, props.colors[1], props.colors[2])
	if props.gloss ~= false then
		gloss(f, props.radius, 0.2)
	end
	f.Parent = props.parent
	return f
end

--- Cartoon text: white fill, hard dark outline. LuckiestGuy.
function PanelChrome.shout(props: {
	text: string, size: number, parent: Instance?, color: Color3?,
	frameSize: UDim2?, position: UDim2?, anchor: Vector2?,
	align: Enum.TextXAlignment?, zIndex: number?, name: string?, scaled: boolean?,
}): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = props.name or "Shout"
	l.BackgroundTransparency = 1
	l.Text = props.text
	l.Font = S.Font.Shout
	l.TextSize = props.size
	if props.scaled then
		l.TextScaled = true
		local fit = Instance.new("UITextSizeConstraint")
		fit.MaxTextSize = props.size
		fit.MinTextSize = 9
		fit.Parent = l
	end
	l.TextColor3 = props.color or Color3.new(1, 1, 1)
	l.TextXAlignment = props.align or Enum.TextXAlignment.Center
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Size = props.frameSize or UDim2.fromScale(1, 1)
	l.Position = props.position or UDim2.fromOffset(0, 0)
	l.AnchorPoint = props.anchor or Vector2.new(0, 0)
	l.ZIndex = props.zIndex or (Z + 3)
	l:SetAttribute("NoPolish", true)
	local s = stroke(l, S.strokeFor(props.size))
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	l.Parent = props.parent
	return l
end

--- Body text: dark fill, no outline. FredokaOne.
function PanelChrome.read(props: {
	text: string, size: number, parent: Instance?, color: Color3?,
	frameSize: UDim2?, position: UDim2?, anchor: Vector2?,
	align: Enum.TextXAlignment?, zIndex: number?, name: string?, wrap: boolean?,
}): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = props.name or "Read"
	l.BackgroundTransparency = 1
	l.Text = props.text
	l.Font = S.Font.Read
	l.TextSize = props.size
	l.TextColor3 = props.color or S.Surface.ReadInk
	l.TextXAlignment = props.align or Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.TextWrapped = props.wrap == true
	l.Size = props.frameSize or UDim2.fromScale(1, 1)
	l.Position = props.position or UDim2.fromOffset(0, 0)
	l.AnchorPoint = props.anchor or Vector2.new(0, 0)
	l.ZIndex = props.zIndex or (Z + 3)
	l:SetAttribute("NoPolish", true)
	l.Parent = props.parent
	return l
end

------------------------------------------------------------------- behaviour
--- Hover 1.05 / press 0.95 on any GuiButton -- tweened on SIZE about the
--- button's own footprint (UIScale tweens are silent no-ops in this place).
--- Live AbsoluteSize drives the delta, so scale-sized buttons work too.
function PanelChrome.bindPressFeedback(button: GuiButton)
	local rest = button.Size
	local hovering = false
	local function to(mult: number, info: TweenInfo)
		local abs = button.AbsoluteSize
		local scaleNow = math.max(button.Parent and 1 or 1, 1)
		local dx = math.round(abs.X * (mult - 1))
		local dy = math.round(abs.Y * (mult - 1))
		-- AbsoluteSize is post-UIScale; the offset delta lands pre-UIScale. The
		-- error is the host scale factor, which only softens the effect a touch
		-- -- acceptable for a 5% feedback cue.
		local target = if mult == 1 then rest else UDim2.new(
			rest.X.Scale, rest.X.Offset + dx, rest.Y.Scale, rest.Y.Offset + dy)
		TweenService:Create(button, info, { Size = target }):Play()
	end
	button.MouseEnter:Connect(function()
		hovering = true
		to(S.Scale.Hover, S.Tween.HoverIn)
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		to(1, S.Tween.HoverOut)
	end)
	button.MouseButton1Down:Connect(function() to(S.Scale.Press, S.Tween.Press) end)
	button.MouseButton1Up:Connect(function()
		if hovering then to(S.Scale.Hover, S.Tween.HoverIn) else to(1, S.Tween.HoverOut) end
	end)
end

------------------------------------------------------------------- the shell
--- Panel shell: outlined frame, coloured header, close button, body.
--- One shell, six colourways: pass the openPanel id as `key` and the header
--- takes that button's plate colour (README rule 2).
--- Returns { root, header, body, close, list, titleLabel, addHeaderTabs }.
function PanelChrome.shell(props: {
	name: string, title: string, key: string,
	size: Vector2?, parent: Instance?, scroll: boolean?, zIndex: number?,
	icon: string?, listLayout: boolean?,
})
	local C = S.Chrome
	local size = props.size or S.ShellFor[props.key] or C.ShellSize
	local plateColors = S.Plate[props.key] or S.Plate.settings
	local z = props.zIndex or Z

	local root = Instance.new("Frame")
	root.Name = props.name
	root.Size = UDim2.fromOffset(size.X, size.Y)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.BackgroundColor3 = S.Surface.Shell
	root.BorderSizePixel = 0
	root.ZIndex = z
	root:SetAttribute("NoPolish", true)
	corner(root, C.ShellRadius)
	stroke(root, C.ShellOutline)

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, C.ShellPadding)
	pad.PaddingBottom = UDim.new(0, C.ShellPadding)
	pad.PaddingLeft = UDim.new(0, C.ShellPadding)
	pad.PaddingRight = UDim.new(0, C.ShellPadding)
	pad.Parent = root

	local header = PanelChrome.plate({
		name = "Header",
		size = UDim2.new(1, 0, 0, C.HeaderHeight),
		colors = plateColors,
		radius = C.HeaderRadius,
		outline = C.HeaderOutline,
		zIndex = z + 1,
		parent = root,
	})

	local hx = C.HeaderPadding
	if props.icon and props.icon ~= "" then
		-- illustrated icon overhangs the header by 6px, like the reference art
		local ic = Instance.new("ImageLabel")
		ic.Name = "Icon"
		ic.Image = props.icon
		ic.BackgroundTransparency = 1
		ic.ScaleType = Enum.ScaleType.Fit
		ic.Size = UDim2.fromOffset(126, 126)
		ic.Position = UDim2.new(0, hx, 0.5, -6)
		ic.AnchorPoint = Vector2.new(0, 0.5)
		ic.ZIndex = z + 4
		ic.Parent = header
		hx = hx + 126 + 18
	end

	local titleLabel = PanelChrome.shout({
		name = "Title",
		text = props.title,
		size = S.TextSize.PanelTitle,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, -(hx + C.CloseSize + 40), 1, 0),
		position = UDim2.fromOffset(hx, 0),
		zIndex = z + 3,
		parent = header,
	})

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Text = ""
	close.BackgroundColor3 = S.Action.Danger[1]
	close.AutoButtonColor = false
	close.BorderSizePixel = 0
	close.Size = UDim2.fromOffset(C.CloseSize, C.CloseSize)
	close.Position = UDim2.new(1, -C.HeaderPadding, 0.5, 0)
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.ZIndex = z + 3
	corner(close, C.CloseSize / 2)
	stroke(close, C.CloseOutline)
	gradient(close, S.Action.Danger[1], S.Action.Danger[2])
	close.Parent = header
	PanelChrome.shout({ text = "X", size = 40, zIndex = z + 4, parent = close })
	PanelChrome.bindPressFeedback(close)

	local body: GuiObject
	if props.scroll == false then
		local f = Instance.new("Frame")
		body = f
	else
		local sc = Instance.new("ScrollingFrame")
		sc.ScrollBarThickness = 10
		sc.ScrollBarImageColor3 = S.Outline
		sc.CanvasSize = UDim2.fromOffset(0, 0)
		sc.AutomaticCanvasSize = Enum.AutomaticSize.Y
		sc.ScrollingDirection = Enum.ScrollingDirection.Y
		body = sc
	end
	body.Name = "Body"
	body.BackgroundColor3 = S.Surface.Body
	body.BorderSizePixel = 0
	body.Size = UDim2.new(1, 0, 1, -(C.HeaderHeight + C.RowGap))
	body.Position = UDim2.fromOffset(0, C.HeaderHeight + C.RowGap)
	body.ZIndex = z + 1
	corner(body, C.BodyRadius)
	stroke(body, C.BodyOutline)
	body.Parent = root

	local bpad = Instance.new("UIPadding")
	bpad.PaddingTop = UDim.new(0, C.BodyPadding)
	bpad.PaddingBottom = UDim.new(0, C.BodyPadding)
	bpad.PaddingLeft = UDim.new(0, C.BodyPadding)
	bpad.PaddingRight = UDim.new(0, C.BodyPadding)
	bpad.Parent = body

	local list = nil
	if props.listLayout ~= false then
		list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, C.RowGap)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = body
	end

	local shellApi = {
		root = root, header = header, body = body, close = close,
		list = list, titleLabel = titleLabel, z = z,
	}

	--- Header-level tabs (Progress: GOALS / SEASON PASS; Bag: ROCKS / BRAINROTS).
	--- Visibly senior to any sub-tabs in the body: 72 tall, gold when selected.
	function shellApi.addHeaderTabs(tabs: { { text: string, width: number } }, selected: number, onChanged: (number) -> ())
		local holder = Instance.new("Frame")
		holder.Name = "HeaderTabs"
		holder.BackgroundTransparency = 1
		holder.AnchorPoint = Vector2.new(1, 0.5)
		holder.Position = UDim2.new(1, -(C.HeaderPadding + C.CloseSize + 22), 0.5, 0)
		holder.Size = UDim2.new(0, 0, 0, 72)
		holder.AutomaticSize = Enum.AutomaticSize.X
		holder.ZIndex = z + 3
		holder.Parent = header
		local hl = Instance.new("UIListLayout")
		hl.FillDirection = Enum.FillDirection.Horizontal
		hl.Padding = UDim.new(0, 12)
		hl.SortOrder = Enum.SortOrder.LayoutOrder
		hl.VerticalAlignment = Enum.VerticalAlignment.Center
		hl.Parent = holder

		local btns = {}
		local current = selected
		local function paint()
			for i, b in ipairs(btns) do
				local g = b:FindFirstChildOfClass("UIGradient")
				local c = if i == current then S.Action.Gold else S.Action.Neutral
				-- BackgroundColor3 must move WITH the gradient: UIGradient
				-- MULTIPLIES the background colour, so gold-over-the-neutral
				-- base the pill was built with rendered olive (2026-08-11).
				b.BackgroundColor3 = c[1]
				if g then g.Color = ColorSequence.new(c[1], c[2]) end
			end
		end
		for i, tab in ipairs(tabs) do
			local b = PanelChrome.pill({
				text = tab.text,
				colors = S.Action.Neutral,
				size = UDim2.fromOffset(tab.width, 72),
				textSize = 26,
				zIndex = z + 3,
				parent = holder,
			})
			b.LayoutOrder = i
			b.Activated:Connect(function()
				if current == i then return end
				current = i
				paint()
				onChanged(i)
			end)
			btns[i] = b
		end
		paint()
		return {
			set = function(i: number) current = i; paint() end,
			get = function() return current end,
		}
	end

	root.Parent = props.parent
	return shellApi
end

--------------------------------------------------------------------- content
--- Pressable pill button (CTA plate).
function PanelChrome.pill(props: {
	text: string, colors: { Color3 }, size: UDim2, position: UDim2?,
	anchor: Vector2?, textSize: number?, parent: Instance?, enabled: boolean?,
	zIndex: number?, radius: number?, name: string?, layoutOrder: number?,
}): TextButton
	local C = S.Chrome
	local z = props.zIndex or (Z + 3)
	local b = Instance.new("TextButton")
	b.Name = props.name or "Pill"
	b.Text = ""
	b.AutoButtonColor = false
	b.BackgroundColor3 = props.colors[1]
	b.BorderSizePixel = 0
	b.Size = props.size
	b.Position = props.position or UDim2.fromOffset(0, 0)
	b.AnchorPoint = props.anchor or Vector2.new(0, 0)
	b.ZIndex = z
	if props.layoutOrder then b.LayoutOrder = props.layoutOrder end
	corner(b, props.radius or C.CtaRadius)
	stroke(b, C.CtaOutline)
	gradient(b, props.colors[1], props.colors[2])
	gloss(b, props.radius or C.CtaRadius, 0.22)
	PanelChrome.shout({
		name = "Label",
		text = props.text,
		size = props.textSize or S.TextSize.Cta,
		zIndex = z + 2,
		parent = b,
		scaled = true,
	})
	if props.enabled == false then
		b.Active = false
		b.BackgroundTransparency = 0.45
		for _, d in ipairs(b:GetDescendants()) do
			if d:IsA("TextLabel") then d.TextTransparency = 0.45 end
		end
	else
		PanelChrome.bindPressFeedback(b)
	end
	b.Parent = props.parent
	return b
end

--- Inert state plate (YOU ARE HERE, locked, in-progress): same geometry as a
--- pill but a Frame, never a button, so it cannot read as pressable.
function PanelChrome.statePlate(props: {
	text: string, colors: { Color3 }?, size: UDim2, position: UDim2?,
	anchor: Vector2?, textSize: number?, parent: Instance?, zIndex: number?, name: string?,
}): Frame
	local C = S.Chrome
	local z = props.zIndex or (Z + 3)
	local f = PanelChrome.plate({
		name = props.name or "StatePlate",
		size = props.size,
		position = props.position,
		anchor = props.anchor,
		colors = props.colors or S.Action.Inert,
		radius = C.CtaRadius,
		outline = C.CtaOutline,
		zIndex = z,
		parent = props.parent,
	})
	PanelChrome.shout({
		name = "Label",
		text = props.text,
		size = props.textSize or S.TextSize.ChipState,
		zIndex = z + 2,
		parent = f,
		scaled = true,
	})
	return f
end

--- Standard list row: icon tile, title, subtitle, action plate on the right.
function PanelChrome.row(props: {
	title: string, subtitle: string?, cta: string?, ctaColors: { Color3 }?,
	ctaSize: Vector2?, rowColors: { Color3 }?, iconColors: { Color3 }?,
	iconImage: string?, iconSize: number?, height: number?, radius: number?,
	layoutOrder: number?, parent: Instance?, zIndex: number?, inert: boolean?,
})
	local C = S.Chrome
	local h = props.height or C.RowHeight
	local z = props.zIndex or (Z + 2)
	local iconSize = props.iconSize or C.IconTile
	local ctaSize = props.ctaSize or C.CtaSize

	local row = PanelChrome.plate({
		name = "Row",
		size = UDim2.new(1, 0, 0, h),
		colors = props.rowColors or { S.Surface.RowTop, S.Surface.RowBottom },
		radius = props.radius or C.RowRadius,
		outline = C.RowOutline,
		zIndex = z,
		parent = props.parent,
		gloss = false,
	})
	row.LayoutOrder = props.layoutOrder or 1

	local x = 22
	local tile = PanelChrome.plate({
		name = "IconTile",
		size = UDim2.fromOffset(iconSize, iconSize),
		position = UDim2.new(0, x, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		colors = props.iconColors or { Color3.fromHex("BFD6EC"), Color3.fromHex("8FB2D4") },
		radius = C.IconRadius,
		outline = C.IconOutline,
		zIndex = z + 1,
		parent = row,
	})
	if props.iconImage and props.iconImage ~= "" then
		local img = Instance.new("ImageLabel")
		img.Name = "Art"
		img.Image = props.iconImage
		img.BackgroundTransparency = 1
		img.ScaleType = Enum.ScaleType.Fit
		img.Size = UDim2.fromScale(0.86, 0.86)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.ZIndex = z + 2
		img.Parent = tile
	end
	x = x + iconSize + 20

	local ctaW = if props.cta then ctaSize.X else 0
	local textW = -(x + ctaW + 40)

	local titleLabel = PanelChrome.read({
		name = "RowTitle",
		text = props.title,
		size = S.TextSize.RowTitle,
		frameSize = UDim2.new(1, textW, 0, 40),
		position = UDim2.new(0, x, 0.5, if props.subtitle then -18 else 0),
		anchor = if props.subtitle then Vector2.new(0, 0.5) else Vector2.new(0, 0.5),
		zIndex = z + 1,
		parent = row,
	})
	local subLabel = nil
	if props.subtitle then
		subLabel = PanelChrome.read({
			name = "RowSub",
			text = props.subtitle,
			size = S.TextSize.RowSub,
			color = S.Surface.ReadSub,
			frameSize = UDim2.new(1, textW, 0, 30),
			position = UDim2.new(0, x, 0.5, 18),
			anchor = Vector2.new(0, 0.5),
			zIndex = z + 1,
			parent = row,
		})
	end

	local button = nil
	if props.cta then
		if props.inert then
			button = PanelChrome.statePlate({
				text = props.cta,
				colors = props.ctaColors or S.Action.Inert,
				size = UDim2.fromOffset(ctaSize.X, ctaSize.Y),
				position = UDim2.new(1, -22, 0.5, 0),
				anchor = Vector2.new(1, 0.5),
				zIndex = z + 1,
				parent = row,
			})
		else
			button = PanelChrome.pill({
				text = props.cta,
				colors = props.ctaColors or S.Action.Go,
				size = UDim2.fromOffset(ctaSize.X, ctaSize.Y),
				position = UDim2.new(1, -22, 0.5, 0),
				anchor = Vector2.new(1, 0.5),
				zIndex = z + 1,
				parent = row,
			})
		end
	end

	return { root = row, button = button, icon = tile, title = titleLabel, sub = subLabel }
end

--- Progress / XP bar with the count ON the track. Returns { root, set }.
function PanelChrome.bar(props: {
	size: UDim2, position: UDim2?, anchor: Vector2?, parent: Instance?,
	fill: { Color3 }?, label: string?, zIndex: number?,
})
	local C = S.Chrome
	local z = props.zIndex or (Z + 3)
	local fillColors = props.fill or S.Action.GreenFill

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BackgroundColor3 = S.Surface.Track
	track.BorderSizePixel = 0
	track.Size = props.size
	track.Position = props.position or UDim2.fromOffset(0, 0)
	track.AnchorPoint = props.anchor or Vector2.new(0, 0)
	track.ZIndex = z
	track.ClipsDescendants = true
	corner(track, C.TrackRadius)
	stroke(track, 5)
	track.Parent = props.parent

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = fillColors[1]
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = z + 1
	corner(fill, C.TrackRadius)
	gradient(fill, fillColors[1], fillColors[2])
	fill.Parent = track

	local label = PanelChrome.shout({
		name = "Count",
		text = props.label or "",
		size = S.TextSize.BarLabel,
		zIndex = z + 2,
		parent = track,
	})

	return {
		root = track,
		set = function(alpha: number, text: string?)
			fill.Size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
			if text then label.Text = text end
		end,
	}
end

--- On/off toggle, 150x62. The word sits INSIDE the track, opposite the knob
--- (an OFF label beside a green fill reads as ON -- README, Settings).
function PanelChrome.toggle(props: {
	position: UDim2?, anchor: Vector2?, parent: Instance?, on: boolean?,
	zIndex: number?, onChanged: ((boolean) -> ())?,
})
	local C = S.Chrome
	local z = props.zIndex or (Z + 3)
	local on = props.on == true

	local b = Instance.new("TextButton")
	b.Name = "Toggle"
	b.Text = ""
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundColor3 = S.Action.Neutral[1]
	b.Size = UDim2.fromOffset(C.ToggleSize.X, C.ToggleSize.Y)
	b.Position = props.position or UDim2.fromOffset(0, 0)
	b.AnchorPoint = props.anchor or Vector2.new(0, 0)
	b.ZIndex = z
	corner(b, C.ToggleSize.Y / 2)
	stroke(b, 5)
	local grad = gradient(b, S.Action.Neutral[1], S.Action.Neutral[2])
	b.Parent = props.parent

	local word = PanelChrome.shout({
		name = "Word", text = "OFF", size = 24, zIndex = z + 1, parent = b,
		frameSize = UDim2.new(0, 90, 1, 0),
	})

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BorderSizePixel = 0
	knob.Size = UDim2.fromOffset(54, 54)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.ZIndex = z + 2
	corner(knob, 27)
	stroke(knob, 4)
	knob.Parent = b

	local function paint(instant: boolean?)
		local x = if on then C.ToggleSize.X - 31 else 31
		local target = UDim2.new(0, x, 0.5, 0)
		if instant then
			knob.Position = target
		else
			TweenService:Create(knob, S.Tween.HoverIn, { Position = target }):Play()
		end
		grad.Color = if on
			then ColorSequence.new(S.Action.GreenFill[1], S.Action.GreenFill[2])
			else ColorSequence.new(S.Action.Neutral[1], S.Action.Neutral[2])
		word.Text = if on then "ON" else "OFF"
		word.Position = if on then UDim2.fromOffset(14, 0) else UDim2.fromOffset(46, 0)
	end
	paint(true)

	b.Activated:Connect(function()
		on = not on
		paint()
		if props.onChanged then props.onChanged(on) end
	end)

	return {
		root = b,
		get = function() return on end,
		set = function(v: boolean, instant: boolean?) on = v; paint(instant) end,
	}
end

--- Slider: 38 track, green fill, 52 gold knob that OVERHANGS the track --
--- that is what makes it read as grabbable (README, Settings).
function PanelChrome.slider(props: {
	size: UDim2, position: UDim2?, anchor: Vector2?, parent: Instance?,
	value: number?, zIndex: number?, onChanged: ((number) -> ())?,
})
	local C = S.Chrome
	local z = props.zIndex or (Z + 3)
	local value = math.clamp(props.value or 1, 0, 1)

	local holder = Instance.new("Frame")
	holder.Name = "Slider"
	holder.BackgroundTransparency = 1
	holder.Size = props.size
	holder.Position = props.position or UDim2.fromOffset(0, 0)
	holder.AnchorPoint = props.anchor or Vector2.new(0, 0)
	holder.ZIndex = z
	holder.Parent = props.parent

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BackgroundColor3 = S.Surface.Track
	track.BorderSizePixel = 0
	track.Size = UDim2.new(1, 0, 0, C.TrackHeight)
	track.Position = UDim2.fromScale(0, 0.5)
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.ZIndex = z
	corner(track, C.TrackRadius)
	stroke(track, 5)
	track.Parent = holder

	local fillClip = Instance.new("Frame")
	fillClip.Name = "FillClip"
	fillClip.BackgroundTransparency = 1
	fillClip.BorderSizePixel = 0
	fillClip.Size = UDim2.fromScale(value, 1)
	fillClip.ZIndex = z + 1
	fillClip.ClipsDescendants = true
	fillClip.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = S.Action.GreenFill[1]
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(0, 0, 1, 0) -- resized against the TRACK below
	fill.ZIndex = z + 1
	corner(fill, C.TrackRadius)
	gradient(fill, S.Action.GreenFill[1], S.Action.GreenFill[2])
	fill.Parent = fillClip

	local knob = Instance.new("TextButton")
	knob.Name = "Knob"
	knob.Text = ""
	knob.AutoButtonColor = false
	knob.BackgroundColor3 = S.Action.Knob[1]
	knob.BorderSizePixel = 0
	knob.Size = UDim2.fromOffset(C.KnobSize, C.KnobSize)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.new(value, 0, 0.5, 0)
	knob.ZIndex = z + 2
	corner(knob, C.KnobSize / 2)
	stroke(knob, 5)
	gradient(knob, S.Action.Knob[1], S.Action.Knob[2])
	knob.Parent = track

	-- the fill stays track-sized (stable rounded caps); the clip frame does
	-- the revealing, so fill is the inverse scale of its clip parent
	local function paint()
		fillClip.Size = UDim2.fromScale(value, 1)
		fill.Size = UDim2.fromScale(1 / math.max(value, 0.001), 1)
		knob.Position = UDim2.new(value, 0, 0.5, 0)
	end
	paint()

	local dragging = false
	local function applyFromX(screenX: number)
		local absPos = track.AbsolutePosition.X
		local absW = math.max(track.AbsoluteSize.X, 1)
		value = math.clamp((screenX - absPos) / absW, 0, 1)
		paint()
		if props.onChanged then props.onChanged(value) end
	end

	local function beginDrag(input: InputObject)
		dragging = true
		applyFromX(input.Position.X)
	end
	knob.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			beginDrag(input)
		end
	end)
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			beginDrag(input)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			applyFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	return {
		root = holder,
		track = track,
		get = function() return value end,
		set = function(v: number) value = math.clamp(v, 0, 1); paint() end,
		isDragging = function() return dragging end,
	}
end

--- Segmented control (Low / Medium / High; Daily / Weekly / Goals).
function PanelChrome.segmented(props: {
	options: { string }, selected: number?, size: UDim2, position: UDim2?,
	parent: Instance?, zIndex: number?, onChanged: ((number, string) -> ())?,
})
	local z = props.zIndex or (Z + 2)
	local selected = props.selected or 1

	local holder = Instance.new("Frame")
	holder.Name = "Segmented"
	holder.BackgroundTransparency = 1
	holder.Size = props.size
	holder.Position = props.position or UDim2.fromOffset(0, 0)
	holder.ZIndex = z
	holder.Parent = props.parent

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, 12)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = holder

	local buttons = {}
	local function paint()
		for i, b in ipairs(buttons) do
			local g = b:FindFirstChildOfClass("UIGradient")
			local c = if i == selected then S.Action.Gold else S.Action.Neutral
			-- same multiply trap as addHeaderTabs: repaint the base too
			b.BackgroundColor3 = c[1]
			if g then g.Color = ColorSequence.new(c[1], c[2]) end
		end
	end

	for i, opt in ipairs(props.options) do
		local b = PanelChrome.pill({
			text = opt,
			colors = S.Action.Neutral,
			size = UDim2.new(1 / #props.options, -math.ceil(12 * (#props.options - 1) / #props.options), 1, 0),
			zIndex = z + 1,
			parent = holder,
			radius = 24,
		})
		b.LayoutOrder = i
		b.Activated:Connect(function()
			if selected == i then return end
			selected = i
			paint()
			if props.onChanged then props.onChanged(i, opt) end
		end)
		buttons[i] = b
	end
	paint()

	return {
		root = holder,
		get = function() return selected end,
		set = function(i: number) selected = i; paint() end,
	}
end

--- Rarity chip (COM / UNC / RARE / EPIC / LEG / MYTH / SEC / GOD).
function PanelChrome.chip(props: {
	rarity: string, size: UDim2, parent: Instance?, zIndex: number?, layoutOrder: number?,
}): Frame
	local C = S.Chrome
	local z = props.zIndex or (Z + 3)
	local colors = S.Rarity[props.rarity] or S.Rarity.COM
	local f = PanelChrome.plate({
		name = props.rarity,
		size = props.size,
		colors = colors,
		radius = C.ChipRadius,
		outline = 4,
		zIndex = z,
		parent = props.parent,
		layoutOrder = props.layoutOrder,
	})
	PanelChrome.shout({
		text = props.rarity, size = S.TextSize.Chip,
		zIndex = z + 2, parent = f, scaled = true,
	})
	return f
end

--- Section heading on the panel ground (AUDIO, DARRELS...): 34px shout with
--- a 6px rule filling the remaining width. Never grey-on-grey inside a row.
function PanelChrome.sectionHead(props: {
	text: string, parent: Instance?, layoutOrder: number?, zIndex: number?, size: number?,
}): Frame
	local z = props.zIndex or (Z + 2)
	local holder = Instance.new("Frame")
	holder.Name = "SectionHead"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 48)
	holder.LayoutOrder = props.layoutOrder or 1
	holder.ZIndex = z
	holder.Parent = props.parent

	local label = PanelChrome.shout({
		text = props.text,
		size = props.size or S.TextSize.SectionHead,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, 0, 1, 0),
		zIndex = z + 1,
		parent = holder,
	})
	label.AutomaticSize = Enum.AutomaticSize.None

	-- the rule: measure the text via TextBounds once it exists
	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.BackgroundColor3 = Color3.fromHex("B7C6D8")
	rule.BorderSizePixel = 0
	rule.AnchorPoint = Vector2.new(1, 0.5)
	rule.Position = UDim2.new(1, 0, 0.5, 2)
	rule.Size = UDim2.new(0, 0, 0, 6)
	rule.ZIndex = z + 1
	corner(rule, 3)
	rule.Parent = holder
	local function sizeRule()
		local w = holder.AbsoluteSize.X
		local used = label.TextBounds.X + 24
		rule.Size = UDim2.new(0, math.max(w - used, 0), 0, 6)
	end
	label:GetPropertyChangedSignal("TextBounds"):Connect(sizeRule)
	holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(sizeRule)
	task.defer(sizeRule)
	return holder
end

--- Rotated corner ribbon (BEST VALUE) pinned to a row's top-right corner.
function PanelChrome.ribbon(props: { text: string, parent: GuiObject, zIndex: number? }): Frame
	local z = props.zIndex or (Z + 5)
	local f = Instance.new("Frame")
	f.Name = "Ribbon"
	f.BackgroundColor3 = S.Action.Gold[2]
	f.BorderSizePixel = 0
	f.Size = UDim2.fromOffset(190, 40)
	f.Position = UDim2.new(1, 8, 0, 12)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Rotation = 12
	f.ZIndex = z
	corner(f, 10)
	stroke(f, 4)
	gradient(f, S.Action.Gold[1], S.Action.Gold[2])
	PanelChrome.shout({ text = props.text, size = 20, zIndex = z + 1, parent = f, scaled = true })
	f.Parent = props.parent
	return f
end

return PanelChrome
