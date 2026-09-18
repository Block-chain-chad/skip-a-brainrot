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
-- Builders requires Tokens/SoundKit/Platform and never requires this module,
-- so this cannot cycle. Used for UI.touchMin on the tap-only controls below.
local UI = require(script.Parent.Builders)
local Platform = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Platform"))
-- 2026-09-18 UI foundation: click sound on every kit button (handoff §11) and the
-- shared Heartbeat driver for the busy indicator. SoundKit never requires UIKit.
local SoundKit = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("SoundKit"))
local FxDriver = require(script.Parent:WaitForChild("FxDriver"))
local CLICK_VOLUME = 0.12 -- same level GameHUDClient.wireClick uses on the rail

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
	strokeColor: Color3?, -- PS99 restyle: soft interior edges pass S.OutlineSoft
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
	stroke(f, props.outline, props.strokeColor)
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
	strokeColor: Color3?, -- PS99 restyle: coloured titles wear a WHITE stroke
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
	local s = stroke(l, S.strokeFor(props.size), props.strokeColor)
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
	-- setEnabled/setBusy read this back to snap a hovered button to rest
	button:SetAttribute("UIRestSize", rest)
	local hovering = false
	-- disabled (UIEnabled == false) and busy (UIBusy == true) buttons give no feedback
	local function blocked(): boolean
		return button:GetAttribute("UIEnabled") == false or button:GetAttribute("UIBusy") == true
	end
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
	-- PHANTOM HOVER (2026-08-19): a touch tap fires MouseEnter too, just AFTER
	-- Down -- so `hovering` latched true, MouseButton1Up settled the control at
	-- Scale.Hover (1.06), and MouseLeave never came to undo it. Every close
	-- button, pill, header tab, segmented option and row CTA a phone player
	-- tapped stayed 6% enlarged; in the two horizontal UIListLayout holders
	-- (addHeaderTabs, segmented) that stuck Size also re-flowed the strip, so
	-- the tabs crept sideways with each tap. Touch has no hover to preserve.
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	button.MouseEnter:Connect(function()
		if touchOnly or blocked() then return end
		hovering = true
		to(S.Scale.Hover, S.Tween.HoverIn)
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		if blocked() then return end
		to(1, S.Tween.HoverOut)
	end)
	button.MouseButton1Down:Connect(function()
		if blocked() then return end
		to(S.Scale.Press, S.Tween.Press)
	end)
	button.MouseButton1Up:Connect(function()
		if blocked() then return end
		if hovering then to(S.Scale.Hover, S.Tween.HoverIn) else to(1, S.Tween.HoverOut) end
	end)
	-- Click sound (handoff §11 "sound behavior" shared by all buttons). Same SfxWired
	-- attribute convention as GameHUDClient.wireClick, so a button wired there too
	-- can only ever carry one connection. SfxMuted opts a button out (the shell's
	-- close button: closePanel already plays panelClose).
	if not button:GetAttribute("SfxWired") then
		button:SetAttribute("SfxWired", true)
		button.MouseButton1Click:Connect(function()
			if blocked() or button:GetAttribute("SfxMuted") == true then return end
			pcall(SoundKit.play, S.Sound.Click, nil, { volume = CLICK_VOLUME })
		end)
	end
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

	-- PS99 restyle: the header is a LAYOUT BAND, not a coloured slab -- same
	-- white as the shell, no outline, no gloss. Title + close float on it.
	local header = PanelChrome.plate({
		name = "Header",
		size = UDim2.new(1, 0, 0, C.HeaderHeight),
		colors = plateColors,
		radius = C.HeaderRadius,
		outline = C.HeaderOutline,
		zIndex = z + 1,
		parent = root,
		gloss = false,
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
		-- field study delta 1: the sticker CROSSES the shell's top-left corner
		-- (half in, half out) instead of sitting inside a band -- root never clips
		ic.Position = UDim2.new(0, hx - 10, 0, -6)
		ic.AnchorPoint = Vector2.new(0, 0.5)
		ic.Rotation = -8 -- PS99 restyle: sticker tilt, same language as the nav rail
		ic.ZIndex = z + 4
		ic.Parent = header
		hx = hx + 126 + 18
	end

	-- Field study delta 1 (120-frame live PS99 study): large-panel titles are
	-- WHITE bubble text with the dark outline, sitting ON the shell's top
	-- border -- no band, no coloured ink. Identity lives in the corner sticker.
	-- (S.TitleInk survives for small-modal use.)
	local titleLabel = PanelChrome.shout({
		name = "Title",
		text = props.title,
		size = S.TextSize.PanelTitle,
		color = Color3.new(1, 1, 1),
		strokeColor = S.Outline,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, -(hx + C.CloseSize + 40), 0, C.HeaderHeight),
		position = UDim2.new(0, hx, 0, -34), -- baseline straddles the shell edge
		zIndex = z + 4,
		parent = header,
	})

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Text = ""
	close.BackgroundColor3 = S.Action.Danger[1]
	close.AutoButtonColor = false
	close.BorderSizePixel = 0
	close.Size = UDim2.fromOffset(C.CloseSize, C.CloseSize)
	-- PS99: rounded SQUARE, white-stroked, overlapping up-and-out of the corner
	close.Position = UDim2.new(1, 14, 0, -10)
	close.AnchorPoint = Vector2.new(1, 0)
	close.ZIndex = z + 3
	corner(close, math.floor(C.CloseSize * 0.3))
	stroke(close, C.CloseOutline, Color3.new(1, 1, 1))
	gradient(close, S.Action.Danger[1], S.Action.Danger[2])
	close.Parent = header
	PanelChrome.shout({ text = "X", size = 40, zIndex = z + 4, parent = close })
	close:SetAttribute("SfxMuted", true) -- closePanel plays panelClose
	PanelChrome.bindPressFeedback(close)
	-- TOUCH FLOOR (2026-08-25). This one is only a HAIR under -- it measured
	-- 43.50 on a phone-classed client -- but it is the close button on every
	-- panel in the game, and a modal you cannot reliably dismiss is the worst
	-- failure on the list. Corner radius follows so it stays the rounded square.
	UI.touchMin(close, 44, function(btn)
		local c = btn:FindFirstChildOfClass("UICorner")
		if c then c.CornerRadius = UDim.new(0, math.floor(btn.Size.X.Offset * 0.3)) end
	end)

	local body: GuiObject
	if props.scroll == false then
		local f = Instance.new("Frame")
		body = f
	else
		local sc = Instance.new("ScrollingFrame")
		-- 2026-08-17 polish: 5px soft thumb, not a 10px ink bar riding over the
		-- cards (PS99 keeps scroll chrome nearly invisible)
		sc.ScrollBarThickness = 5
		sc.ScrollBarImageColor3 = S.OutlineSoft
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
	stroke(body, C.BodyOutline, S.OutlineSoft)
	body.Parent = root

	-- Field study delta 5: the faint doodle watermark every PS99 panel wears.
	-- Our own motif tile (skip rocks, ripples, brainrot faces) at ~5% strength.
	-- BLOCKER FIX (2026-08-16 grade): parented to ROOT over the body's rect,
	-- NOT into body -- inside a listLayout body the UIListLayout treated the
	-- full-height watermark as the FIRST LIST ITEM and pushed every row below
	-- the fold (Worlds/Shop/Settings looked empty until scrolled). As a later
	-- sibling at body's ZIndex it draws above body's fill and below its z+2
	-- children; it deliberately does not scroll (a ground texture, per PS99).
	do
		local wm = Instance.new("ImageLabel")
		wm.Name = "Watermark"
		wm.Image = "rbxassetid://106223454313706"
		wm.BackgroundTransparency = 1
		wm.ImageTransparency = 0.94
		wm.ScaleType = Enum.ScaleType.Tile
		wm.TileSize = UDim2.fromOffset(200, 200)
		wm.Size = UDim2.new(1, -8, 1, -(C.HeaderHeight + C.RowGap + 8))
		wm.Position = UDim2.fromOffset(4, C.HeaderHeight + C.RowGap + 4)
		wm.ZIndex = z + 1
		local wmCorner = Instance.new("UICorner")
		wmCorner.CornerRadius = UDim.new(0, C.BodyRadius)
		wmCorner.Parent = wm
		wm.Parent = root
	end

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
				-- 2026-09-18 UI foundation (handoff §4): blue = navigation, so the ACTIVE
				-- tab is S.Role.Neutral and the inactive one the grey S.Role.Disabled
				-- (was field-study delta 7: active = green)
				local c = if i == current then S.Role.Neutral else S.Role.Disabled
				-- BackgroundColor3 must move WITH the gradient: UIGradient
				-- MULTIPLIES the background colour, so gold-over-the-neutral
				-- base the pill was built with rendered olive (2026-08-11).
				b.BackgroundColor3 = c[1]
				if g then g.Color = ColorSequence.new(c[1], c[2]) end
				-- light Neutral fill takes dark ink + white stroke; the active
				-- green takes the white shout + dark stroke (pill's build gate)
				local label = b:FindFirstChild("Label")
				if label and label:IsA("TextLabel") then
					local ls = label:FindFirstChildOfClass("UIStroke")
					if i == current then
						label.TextColor3 = Color3.new(1, 1, 1)
						if ls then ls.Color = S.Outline end
					else
						label.TextColor3 = S.Surface.ReadInk
						if ls then ls.Color = Color3.new(1, 1, 1) end
					end
				end
			end
		end
		for i, tab in ipairs(tabs) do
			local b = PanelChrome.pill({
				text = tab.text,
				colors = S.Role.Disabled,
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
	outline: number?, -- 2026-09-18: small controls (36px sort chips) need a thinner edge than CtaOutline
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
	stroke(b, props.outline or C.CtaOutline)
	gradient(b, props.colors[1], props.colors[2])
	gloss(b, props.radius or C.CtaRadius, 0.22)
	-- PS99 restyle: very light plates (gold chips, white tabs) take dark ink
	-- with a white stroke instead of vanishing white-on-light.
	local lum = props.colors[1].R * 0.299 + props.colors[1].G * 0.587 + props.colors[1].B * 0.114
	PanelChrome.shout({
		name = "Label",
		text = props.text,
		size = props.textSize or S.TextSize.Cta,
		color = if lum > 0.82 then S.Surface.ReadInk else Color3.new(1, 1, 1),
		strokeColor = if lum > 0.82 then Color3.new(1, 1, 1) else nil,
		zIndex = z + 2,
		parent = b,
		scaled = true,
	})
	-- ramp remembered for setEnabled/setBusy repaints (legacy pills included)
	b:SetAttribute("UIRampTop", props.colors[1])
	b:SetAttribute("UIRampBottom", props.colors[2])
	PanelChrome.bindPressFeedback(b)
	if props.enabled == false then
		-- 2026-09-18: the runtime disabled state (spec §6.2) replaces the old
		-- build-time-only transparency fade; callers can re-enable later
		PanelChrome.setEnabled(b, false)
	end
	b.Parent = props.parent
	return b
end

------------------------------------------------------------- semantic buttons
-- 2026-09-18 UI foundation (spec §6.2, handoff §11). kind -> S.Role ramp. Built ON
-- pill so geometry, gloss and the >0.82-luminance ink gate are shared. The ramp is
-- remembered on the button as attributes so the runtime states repaint without
-- guessing, and a disabled/busy button is Interactable = false so consumer-wired
-- Activated handlers cannot fire either.
-- "secondary" = the quiet grey option (Cancel, Hide Plot): handoff §4 "Gray = secondary"
local KIND_ROLE = { positive = "Positive", neutral = "Neutral", destructive = "Destructive", gold = "Gold", purple = "Purple", secondary = "Disabled" }
local BUSY_DOTS = "\u{00B7} \u{00B7} \u{00B7}"

local function inkFor(top: Color3): (Color3, Color3)
	local lum = top.R * 0.299 + top.G * 0.587 + top.B * 0.114
	if lum > 0.82 then return S.Surface.ReadInk, Color3.new(1, 1, 1) end
	return Color3.new(1, 1, 1), S.Outline
end

local function repaintLabel(btn: GuiButton, top: Color3)
	local label = btn:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		local ink, strokeC = inkFor(top)
		label.TextColor3 = ink
		local ls = label:FindFirstChildOfClass("UIStroke")
		if ls then ls.Color = strokeC end
	end
end

local function snapToRest(btn: GuiButton)
	local rest = btn:GetAttribute("UIRestSize")
	if typeof(rest) == "UDim2" then btn.Size = rest end
end

function PanelChrome.button(props: {
	kind: string?, text: string, size: (UDim2 | string)?, icon: string?, enabled: boolean?,
	sound: boolean?, onActivated: (() -> ())?, parent: Instance?, zIndex: number?,
	layoutOrder: number?, name: string?, position: UDim2?, anchor: Vector2?,
	textSize: number?, radius: number?, outline: number?,
}): TextButton
	local kindKey = props.kind or "positive"
	local roleName = KIND_ROLE[kindKey]
	if not roleName then
		warn(("[UIKit] button: unknown kind %q, using positive"):format(tostring(props.kind)))
		roleName = "Positive"
		kindKey = "positive"
	end
	local ramp = S.Role[roleName]
	local size: UDim2
	if typeof(props.size) == "UDim2" then
		size = props.size :: UDim2
	elseif props.size == "small" then
		size = UDim2.fromOffset(160, 64)
	else
		size = UDim2.fromOffset(S.Chrome.CtaSize.X, S.Chrome.CtaSize.Y)
	end
	local b = PanelChrome.pill({
		text = props.text, colors = ramp, size = size, position = props.position, anchor = props.anchor,
		textSize = props.textSize, zIndex = props.zIndex, radius = props.radius, outline = props.outline,
		name = props.name or ("Button_" .. kindKey), layoutOrder = props.layoutOrder,
	})
	b:SetAttribute("UIKind", kindKey)
	if props.sound == false then b:SetAttribute("SfxMuted", true) end
	if props.icon and props.icon ~= "" then
		local ic = Instance.new("ImageLabel")
		ic.Name = "Icon"
		ic.Image = props.icon
		ic.BackgroundTransparency = 1
		ic.ScaleType = Enum.ScaleType.Fit
		ic.AnchorPoint = Vector2.new(0, 0.5)
		ic.Position = UDim2.new(0, 14, 0.5, 0)
		ic.Size = UDim2.fromOffset(40, 40)
		ic.ZIndex = b.ZIndex + 2
		ic.Parent = b
		local label = b:FindFirstChild("Label")
		if label then
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 44)
			pad.Parent = label
		end
	end
	if props.onActivated then
		b.Activated:Connect(function()
			if b:GetAttribute("UIEnabled") == false or b:GetAttribute("UIBusy") == true then return end
			props.onActivated()
		end)
	end
	if props.enabled == false then PanelChrome.setEnabled(b, false) end
	b.Parent = props.parent
	return b
end

--- Runtime enable/disable. Disabled = grey ramp, dimmed label, no input, no feedback.
function PanelChrome.setEnabled(btn: GuiButton, on: boolean)
	local g = btn:FindFirstChildOfClass("UIGradient")
	local label = btn:FindFirstChild("Label")
	if on then
		btn:SetAttribute("UIEnabled", nil)
		if btn:GetAttribute("UIBusy") ~= true then
			btn.Interactable = true
			btn.Active = true
		end
		local top, bottom = btn:GetAttribute("UIRampTop"), btn:GetAttribute("UIRampBottom")
		if typeof(top) == "Color3" and typeof(bottom) == "Color3" then
			btn.BackgroundColor3 = top
			if g then g.Color = ColorSequence.new(top, bottom) end
			repaintLabel(btn, top)
		end
		btn.BackgroundTransparency = 0
		if label and label:IsA("TextLabel") then
			label.TextTransparency = if btn:GetAttribute("UIBusy") == true then 0.35 else 0
		end
	else
		if btn:GetAttribute("UIRampTop") == nil then
			-- a hand-built button: remember what it wore so re-enabling restores it
			btn:SetAttribute("UIRampTop", btn.BackgroundColor3)
			local bottom = btn.BackgroundColor3
			if g then
				local kps = g.Color.Keypoints
				bottom = kps[#kps].Value
			end
			btn:SetAttribute("UIRampBottom", bottom)
		end
		btn:SetAttribute("UIEnabled", false)
		btn.Interactable = false
		btn.Active = false
		snapToRest(btn)
		local d = S.Role.DisabledButton
		btn.BackgroundColor3 = d[1]
		if g then g.Color = ColorSequence.new(d[1], d[2]) end
		repaintLabel(btn, d[1])
		if label and label:IsA("TextLabel") then label.TextTransparency = 0.45 end
	end
end

--- Busy = "waiting on the server": keeps size and ramp, blocks input/feedback/sound,
--- dims the label and pulses three dots. Auto-clears after `timeout` (default 10s)
--- with a warning so a lost reply can never brick a button. Distinct from disabled.
function PanelChrome.setBusy(btn: GuiButton, on: boolean, opts: { timeout: number? }?)
	local label = btn:FindFirstChild("Label")
	if on then
		if btn:GetAttribute("UIBusy") == true then return end
		btn:SetAttribute("UIBusy", true)
		btn.Interactable = false
		btn.Active = false
		snapToRest(btn)
		if label and label:IsA("TextLabel") then label.TextTransparency = 0.35 end
		local dots = Instance.new("TextLabel")
		dots.Name = "BusyDots"
		dots.BackgroundTransparency = 1
		dots.Size = UDim2.fromScale(1, 1)
		dots.Font = S.Font.Shout
		dots.TextSize = 30
		dots.Text = BUSY_DOTS
		dots.TextColor3 = Color3.new(1, 1, 1)
		dots.TextXAlignment = Enum.TextXAlignment.Center
		dots.ZIndex = btn.ZIndex + 3
		dots:SetAttribute("NoPolish", true)
		local ds = Instance.new("UIStroke")
		ds.Thickness = 2
		ds.Color = S.Outline
		ds.Parent = dots
		dots.Parent = btn
		local fxId = FxDriver.register(btn, function(t)
			dots.TextTransparency = 0.15 + 0.55 * (0.5 + 0.5 * math.sin(t * 5))
		end)
		btn:SetAttribute("UIBusyFx", fxId)
		local gen = (tonumber(btn:GetAttribute("UIBusyGen")) or 0) + 1
		btn:SetAttribute("UIBusyGen", gen)
		local timeout = (opts and opts.timeout) or 10
		task.delay(timeout, function()
			if btn.Parent and btn:GetAttribute("UIBusy") == true and btn:GetAttribute("UIBusyGen") == gen then
				warn(("[UIKit] setBusy: %s still busy after %.1fs -- clearing (lost reply?)"):format(btn:GetFullName(), timeout))
				PanelChrome.setBusy(btn, false)
			end
		end)
	else
		if btn:GetAttribute("UIBusy") ~= true then return end
		btn:SetAttribute("UIBusy", nil)
		FxDriver.unregister(tonumber(btn:GetAttribute("UIBusyFx")))
		btn:SetAttribute("UIBusyFx", nil)
		local dots = btn:FindFirstChild("BusyDots")
		if dots then dots:Destroy() end
		local disabled = btn:GetAttribute("UIEnabled") == false
		if not disabled then
			btn.Interactable = true
			btn.Active = true
		end
		if label and label:IsA("TextLabel") then label.TextTransparency = if disabled then 0.45 else 0 end
	end
end

--- Inert state plate (YOU ARE HERE, locked, in-progress): same geometry as a
--- pill but a Frame, never a button, so it cannot read as pressable.
function PanelChrome.statePlate(props: {
	text: string, colors: { Color3 }?, size: UDim2, position: UDim2?,
	anchor: Vector2?, textSize: number?, parent: Instance?, zIndex: number?, name: string?,
}): Frame
	local C = S.Chrome
	local z = props.zIndex or (Z + 3)
	-- PS99 grammar fix (2026-08-17): chrome means CLICKABLE. The old default
	-- (saturated Inert ramp + dark border + gloss + white shout) was pill
	-- chrome on a non-button, so YOU ARE HERE read pressable. Inert now means
	-- pale fill barely off the ground, soft edge, no gloss, grey ink. Callers
	-- that pass their own dark ramp keep the white shout via the same
	-- luminance gate pill() uses.
	local resolved = props.colors or S.Action.Pale
	local f = PanelChrome.plate({
		name = props.name or "StatePlate",
		size = props.size,
		position = props.position,
		anchor = props.anchor,
		colors = resolved,
		radius = C.CtaRadius,
		outline = C.CtaOutline,
		strokeColor = S.OutlineSoft,
		gloss = false,
		zIndex = z,
		parent = props.parent,
	})
	local lum = resolved[1].R * 0.299 + resolved[1].G * 0.587 + resolved[1].B * 0.114
	PanelChrome.shout({
		name = "Label",
		text = props.text,
		size = props.textSize or S.TextSize.ChipState,
		color = if lum > 0.82 then Color3.fromHex("6E7E94") else Color3.new(1, 1, 1),
		strokeColor = if lum > 0.82 then Color3.new(1, 1, 1) else nil,
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
		strokeColor = S.OutlineSoft, -- PS99: interior cards wear the soft edge
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
		colors = props.iconColors or { Color3.fromHex("E4EDF7"), Color3.fromHex("C3D4E6") },
		radius = C.IconRadius,
		outline = C.IconOutline,
		strokeColor = S.OutlineSoft,
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
				-- nil = statePlate's pale-inert default (PS99 grammar: a
				-- non-button never wears the saturated slate ramp)
				colors = props.ctaColors,
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
		-- base must move WITH the gradient (same multiply trap as the tab
		-- painters), and the light OFF fill takes dark ink + white stroke
		b.BackgroundColor3 = if on then S.Action.GreenFill[1] else S.Action.Neutral[1]
		word.Text = if on then "ON" else "OFF"
		word.TextColor3 = if on then Color3.new(1, 1, 1) else S.Surface.ReadInk
		local ws = word:FindFirstChildOfClass("UIStroke")
		if ws then
			ws.Color = if on then S.Outline else Color3.new(1, 1, 1)
		end
		word.Position = if on then UDim2.fromOffset(14, 0) else UDim2.fromOffset(46, 0)
	end
	paint(true)

	-- TOUCH FLOOR (2026-08-25, measured). The toggle is authored 78x32 DESIGN px
	-- and a panel renders under a UIScale, so it came out 78x32 ON a phone-classed
	-- client -- 12px under the 44px minimum on the short axis, on a control that
	-- is nothing but a tap target. The radius has to follow the new height or the
	-- capsule grows into a rounded rectangle.
	UI.touchMin(b, 44, function(btn)
		local c = btn:FindFirstChildOfClass("UICorner")
		if c then c.CornerRadius = UDim.new(0, btn.Size.Y.Offset / 2) end
	end)

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

	-- TOUCH GRAB STRIP (2026-08-25, measured). On a phone-classed client the knob
	-- rendered 27x27 and the track 38 design px is thinner still -- both well under
	-- the 44px minimum, so the slider was a hairline to aim at with a thumb.
	--
	-- The knob is NOT grown to 44: at the panel scale in force that means ~85
	-- design px, more than twice the track's height and most of the 104-tall row,
	-- which wrecks the control to fix its hitbox. An invisible strip over the whole
	-- track carries the hit area instead -- the slider looks identical and the
	-- reachable band goes from ~20px to 44. It runs the SAME beginDrag as the track
	-- (which reads track.AbsolutePosition, so the maths is untouched), and it sits
	-- under the knob's ZIndex so grabbing the knob still goes to the knob.
	if Platform.IsTouch then
		local grab = Instance.new("Frame")
		grab.Name = "GrabStrip"
		grab.BackgroundTransparency = 1
		grab.Active = true -- required, or a transparent Frame receives no input
		grab.AnchorPoint = Vector2.new(0.5, 0.5)
		grab.Position = UDim2.fromScale(0.5, 0.5)
		grab.Size = UDim2.fromScale(1, 1)
		grab.ZIndex = z + 1
		grab.Parent = track
		grab.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				beginDrag(input)
			end
		end)
		UI.touchMin(grab, 44)
	end
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
	radius: number?, outline: number?, textSize: number?, -- 2026-09-18: SortButton passes small-control geometry
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
			-- 2026-09-18 UI foundation: active = blue (navigation), inactive = grey
			local c = if i == selected then S.Role.Neutral else S.Role.Disabled
			-- same multiply trap as addHeaderTabs: repaint the base too
			b.BackgroundColor3 = c[1]
			if g then g.Color = ColorSequence.new(c[1], c[2]) end
			-- same ink rule as addHeaderTabs: dark ink on the light Neutral,
			-- white shout + dark stroke on the active green
			local label = b:FindFirstChild("Label")
			if label and label:IsA("TextLabel") then
				local ls = label:FindFirstChildOfClass("UIStroke")
				if i == selected then
					label.TextColor3 = Color3.new(1, 1, 1)
					if ls then ls.Color = S.Outline end
				else
					label.TextColor3 = S.Surface.ReadInk
					if ls then ls.Color = Color3.new(1, 1, 1) end
				end
			end
		end
	end

	for i, opt in ipairs(props.options) do
		local b = PanelChrome.pill({
			text = opt,
			colors = S.Role.Disabled,
			size = UDim2.new(1 / #props.options, -math.ceil(12 * (#props.options - 1) / #props.options), 1, 0),
			zIndex = z + 1,
			parent = holder,
			radius = props.radius or 24,
			outline = props.outline,
			textSize = props.textSize,
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

--- Section heading on the panel ground (AUDIO, EMERALDS...): 34px shout with
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

	-- Field study delta 6: PS99 section heads are CENTERED ink flanked by a
	-- thin hairline on EACH side (was: left-aligned + one right-side rule).
	local label = PanelChrome.shout({
		text = props.text,
		size = props.size or S.TextSize.SectionHead,
		color = S.Surface.ReadInk,
		strokeColor = Color3.new(1, 1, 1),
		align = Enum.TextXAlignment.Center,
		frameSize = UDim2.new(1, 0, 1, 0),
		zIndex = z + 1,
		parent = holder,
	})
	label.AutomaticSize = Enum.AutomaticSize.None

	local function hairline(name: string, anchorX: number)
		local rule = Instance.new("Frame")
		rule.Name = name
		rule.BackgroundColor3 = Color3.fromHex("E2E6EC")
		rule.BorderSizePixel = 0
		rule.AnchorPoint = Vector2.new(anchorX, 0.5)
		rule.Position = UDim2.new(anchorX, 0, 0.5, 2)
		rule.Size = UDim2.new(0, 0, 0, 2)
		rule.ZIndex = z + 1
		corner(rule, 1)
		rule.Parent = holder
		return rule
	end
	local left = hairline("RuleL", 0)
	local right = hairline("RuleR", 1)
	local function sizeRules()
		local w = holder.AbsoluteSize.X
		local side = math.max((w - label.TextBounds.X - 48) / 2, 0)
		left.Size = UDim2.new(0, side, 0, 2)
		right.Size = UDim2.new(0, side, 0, 2)
	end
	label:GetPropertyChangedSignal("TextBounds"):Connect(sizeRules)
	holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(sizeRules)
	task.defer(sizeRules)
	return holder
end

--- Field study delta 10: THE hover tooltip -- the ONLY shadowed element in
--- the whole language (that is what makes it read as floating). White card,
--- thin soft border; top rarities retint the WHOLE card (border + ground).
--- Fixed content stack: name / rarity word / divider / description / meta /
--- price row / verdict. Positioning uses SCALE-RELATIVE coordinates derived
--- from AbsolutePosition ratios, which sidesteps the ~0.72 cumulative
--- UIScale trap by construction (no offset math to mis-scale).
function PanelChrome.tooltip(props: { parent: GuiObject, zIndex: number? })
	local z = props.zIndex or (Z + 20)
	local host = props.parent

	local shadow = Instance.new("Frame")
	shadow.Name = "TooltipShadow"
	shadow.BackgroundColor3 = Color3.fromHex("1A2430")
	shadow.BackgroundTransparency = 0.82
	shadow.BorderSizePixel = 0
	shadow.Visible = false
	shadow.ZIndex = z - 1
	corner(shadow, 18)
	shadow.Parent = host

	local card = Instance.new("Frame")
	card.Name = "Tooltip"
	card.BackgroundColor3 = Color3.new(1, 1, 1)
	card.BorderSizePixel = 0
	card.Size = UDim2.fromOffset(250, 100)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Visible = false
	card.ZIndex = z
	corner(card, 16)
	local cardStroke = stroke(card, 2.5, S.OutlineSoft)
	card.Parent = host

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = card
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = card

	local function line(name: string, order: number, size: number, color: Color3, wrap: boolean?): TextLabel
		local l = PanelChrome.read({
			name = name, text = "", size = size, color = color,
			frameSize = UDim2.new(1, 0, 0, 0), zIndex = z + 1, wrap = wrap,
		})
		l.AutomaticSize = Enum.AutomaticSize.Y
		l.LayoutOrder = order
		l.Parent = card
		return l
	end
	local nameL = line("NameLine", 1, 24, S.Surface.ReadInk, true)
	local rarityL = line("RarityLine", 2, 18, S.Surface.ReadSub)
	rarityL.TextWrapped = false -- polish: "Mythic" was wrapping to "My thic" at narrow card widths
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.BackgroundColor3 = Color3.fromHex("E2E6EC")
	divider.BorderSizePixel = 0
	divider.Size = UDim2.new(1, 0, 0, 2)
	divider.LayoutOrder = 3
	divider.ZIndex = z + 1
	divider.Parent = card
	local descL = line("DescLine", 4, 16, S.Surface.ReadSub, true)
	local metaL = line("MetaLine", 5, 15, S.Surface.ReadSub)
	local priceL = line("PriceLine", 6, 20, Color3.fromHex("2589D6"))
	local verdictL = line("VerdictLine", 7, 17, Color3.fromHex("2E8A1C"))

	local api = {}
	function api.show(anchor: GuiObject, data: {
		name: string, rarity: string?, rarityColor: Color3?, tintCard: boolean?,
		desc: string?, meta: string?, price: string?, verdict: string?, verdictColor: Color3?,
	})
		nameL.Text = data.name or ""
		rarityL.Text = data.rarity or ""
		rarityL.TextColor3 = data.rarityColor or S.Surface.ReadSub
		rarityL.Visible = data.rarity ~= nil
		descL.Text = data.desc or ""
		descL.Visible = data.desc ~= nil
		metaL.Text = data.meta or ""
		metaL.Visible = data.meta ~= nil
		priceL.Text = data.price or ""
		priceL.Visible = data.price ~= nil
		verdictL.Text = data.verdict or ""
		verdictL.TextColor3 = data.verdictColor or Color3.fromHex("2E8A1C")
		verdictL.Visible = data.verdict ~= nil
		if data.tintCard and data.rarityColor then
			card.BackgroundColor3 = Color3.new(1, 1, 1):Lerp(data.rarityColor, 0.10)
			cardStroke.Color = Color3.new(1, 1, 1):Lerp(data.rarityColor, 0.55)
		else
			card.BackgroundColor3 = Color3.new(1, 1, 1)
			cardStroke.Color = S.OutlineSoft
		end
		-- scale-relative placement beside the anchor (right side, flips left
		-- when it would leave the host) -- ratios of ABSOLUTE rects, immune to
		-- the cumulative-UIScale offset trap
		local hAbs, hSize = host.AbsolutePosition, host.AbsoluteSize
		local aAbs, aSize = anchor.AbsolutePosition, anchor.AbsoluteSize
		local rightX = (aAbs.X + aSize.X - hAbs.X + 10) / math.max(hSize.X, 1)
		local y = (aAbs.Y - hAbs.Y) / math.max(hSize.Y, 1)
		local cardW = card.AbsoluteSize.X / math.max(hSize.X, 1)
		if rightX + cardW > 0.98 then
			rightX = (aAbs.X - hAbs.X - card.AbsoluteSize.X - 10) / math.max(hSize.X, 1)
		end
		card.Position = UDim2.fromScale(rightX, math.clamp(y, 0.02, 0.72))
		shadow.Position = card.Position + UDim2.fromOffset(0, 6)
		-- card.AbsoluteSize has not recomputed for the new text yet (AutomaticSize
		-- lands next layout pass); size the shadow after it so a wrapped two-line
		-- name does not keep the previous tip's shadow height
		task.defer(function()
			shadow.Size = UDim2.fromOffset(card.AbsoluteSize.X, card.AbsoluteSize.Y)
		end)
		card.Visible = true
		shadow.Visible = true
	end
	function api.hide()
		card.Visible = false
		shadow.Visible = false
	end
	api.card = card
	return api
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
