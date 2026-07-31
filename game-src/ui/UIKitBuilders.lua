--!strict
-- ui_builders.lua — the five primitives this style needs, so panels stay short.
-- Reproduces: thick outline, hard offset shadow, vertical gradient, top gloss,
-- bottom shade, stroked display text, inset track.
--
-- local UI = require(script.Parent.ui_builders)
-- local panel = UI.panel(parent, UDim2.fromOffset(960, 566))
-- local btn   = UI.button(panel, "Claim", "green", UDim2.fromOffset(136, 60))

local T = require(script.Parent.Tokens)

local UI = {}

function UI.corner(parent: Instance, radius: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

function UI.stroke(parent: Instance, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or T.stroke.control
	s.Color = T.color.outline
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
	return s
end

function UI.gradient(parent: Instance, colorSequence: ColorSequence): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = colorSequence
	g.Rotation = 90 -- top -> bottom
	g.Parent = parent
	return g
end

-- Top white gloss strip + bottom dark shade. Call after corner/gradient.
function UI.gloss(frame: GuiObject, radius: number, lightAlpha: number?)
	local top = Instance.new("Frame")
	top.Name = "Gloss"
	top.Size = UDim2.new(1, 0, 0, T.gloss.height)
	top.BackgroundColor3 = T.color.white
	top.BackgroundTransparency = 1 - (lightAlpha or T.gloss.alpha)
	top.BorderSizePixel = 0
	top.ZIndex = (frame.ZIndex or 1) + 1
	top.Parent = frame
	UI.corner(top, radius)

	local bottom = Instance.new("Frame")
	bottom.Name = "Shade"
	bottom.AnchorPoint = Vector2.new(0, 1)
	bottom.Position = UDim2.fromScale(0, 1)
	bottom.Size = UDim2.new(1, 0, 0, T.gloss.shadeHeight)
	bottom.BackgroundColor3 = Color3.new(0, 0, 0)
	bottom.BackgroundTransparency = T.gloss.shadeAlpha
	bottom.BorderSizePixel = 0
	bottom.ZIndex = (frame.ZIndex or 1) + 1
	bottom.Parent = frame
	UI.corner(bottom, radius)
end

-- The hard cartoon shadow: a copy of the shape, outline-coloured, pushed down Y.
-- Returns the wrapper you should parent siblings to; `frame` stays the visual surface.
function UI.hardShadow(frame: GuiObject, offsetY: number, radius: number): Frame
	local sh = Instance.new("Frame")
	sh.Name = "HardShadow"
	sh.Size = frame.Size
	sh.Position = frame.Position + UDim2.fromOffset(0, offsetY)
	sh.AnchorPoint = frame.AnchorPoint
	sh.BackgroundColor3 = T.color.outline
	sh.BorderSizePixel = 0
	sh.ZIndex = frame.ZIndex - 1
	sh.Parent = frame.Parent
	UI.corner(sh, radius)
	return sh
end

-- Display text with the heavy outline. `styleKey` indexes T.text.
function UI.label(parent: Instance, text: string, styleKey: string, color: Color3?): TextLabel
	local spec = T.text[styleKey]
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color or T.color.white
	l.TextSize = spec[1]
	l.FontFace = if styleKey == "meta" then T.font.ui else T.font.display
	l.RichText = false
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.AutomaticSize = Enum.AutomaticSize.XY
	l.Parent = parent
	if spec[2] > 0 then
		local s = Instance.new("UIStroke")
		s.Thickness = spec[2]
		s.Color = T.color.outline
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		s.LineJoinMode = Enum.LineJoinMode.Round
		s.Parent = l
	end
	return l
end

-- Panel / card surface. kind: "panel" | "subPanel" | "row" | "slot" | "tab" | "track"
function UI.surface(parent: Instance, size: UDim2, kind: string, radius: number?, strokeW: number?): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.BackgroundColor3 = T.color.white
	f.BorderSizePixel = 0
	f.Parent = parent
	local r = radius or T.radius.panel
	UI.corner(f, r)
	UI.gradient(f, T.gradient[kind])
	UI.stroke(f, strokeW or T.stroke.panel)
	return f
end

function UI.panel(parent: Instance, size: UDim2): Frame
	local f = UI.surface(parent, size, "panel", T.radius.panel, T.stroke.panel)
	UI.hardShadow(f, T.shadowOffset.panel, T.radius.panel)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, T.pad.panel)
	p.PaddingBottom = UDim.new(0, T.pad.panel)
	p.PaddingLeft = UDim.new(0, T.pad.panel)
	p.PaddingRight = UDim.new(0, T.pad.panel)
	p.Parent = f
	return f
end

-- variant: "gold" | "goldSmall" | "green" | "purple" | "red" | "blue" | "disabled" | "tab"
function UI.button(parent: Instance, text: string, variant: string, size: UDim2, styleKey: string?): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.Text = ""
	b.AutoButtonColor = false
	b.BackgroundColor3 = T.color.white
	b.BorderSizePixel = 0
	b.Active = variant ~= "disabled"
	b.Parent = parent
	UI.corner(b, T.radius.control)
	UI.gradient(b, T.gradient[variant])
	UI.stroke(b, T.stroke.control)
	if variant ~= "disabled" then
		UI.gloss(b, T.radius.control)
		UI.hardShadow(b, T.shadowOffset.control, T.radius.control)
	end
	local l = UI.label(b, text, styleKey or "buttonM",
		if variant == "disabled" then T.color.textDisabled else T.color.white)
	l.Size = UDim2.fromScale(1, 1)
	l.AutomaticSize = Enum.AutomaticSize.None
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.ZIndex = 3

	-- hover / press
	-- Rest position captured LAZILY (state machine below), not at creation:
	-- UI.button doesn't take a position parameter, so every caller's mandatory
	-- pattern is `local btn = UI.button(...); btn.Position = ...` -- set AFTER
	-- this function returns. Capturing `b.Position` here (as this used to do)
	-- froze `base` at the TextButton default (0,0) before the caller ever
	-- repositioned it, so the first hover/press tween dragged the button back
	-- toward (0,0)-ish. Instead: capture `rest` on first MouseEnter, by which
	-- point the caller has always already set the real Position. Same fix as
	-- GameHUDClient's nav-rail basePos() (~line 528).
	-- Known limitation: if a caller repositions the button again WHILE it is
	-- already hovered/pressed, `rest` is not invalidated (no cheap way to
	-- detect external repositioning) -- that one tween will animate off the
	-- stale `rest` instead of the new position. Considered acceptable: no
	-- caller in this codebase repositions buttons post-hover today.
	local TweenService = game:GetService("TweenService")
	local rest = nil
	local hovered, pressed = false, false
	if variant ~= "disabled" then
		b.MouseEnter:Connect(function()
			if not hovered and not pressed then
				rest = b.Position
			end
			hovered = true
			TweenService:Create(b, T.tween.hover, { Position = rest - UDim2.fromOffset(0, 2) }):Play()
		end)
		b.MouseLeave:Connect(function()
			hovered = false
			TweenService:Create(b, T.tween.hover, { Position = rest }):Play()
		end)
		b.MouseButton1Down:Connect(function()
			pressed = true
			TweenService:Create(b, T.tween.press, { Position = rest + UDim2.fromOffset(0, 2) }):Play()
		end)
		b.MouseButton1Up:Connect(function()
			pressed = false
			TweenService:Create(b, T.tween.press, {
				Position = if hovered then rest - UDim2.fromOffset(0, 2) else rest,
			}):Play()
		end)
	end
	return b
end

-- Inset progress track + fill. Returns (track, fill). Drive with UI.setFill.
function UI.track(parent: Instance, size: UDim2, fillVariant: string, radius: number?): (Frame, Frame)
	local r = radius or T.radius.inner
	local t = UI.surface(parent, size, "track", r, T.stroke.control)
	t.ClipsDescendants = true

	local inset = Instance.new("Frame") -- inner top shadow
	inset.Size = UDim2.new(1, 0, 0, 4)
	inset.BackgroundColor3 = Color3.new(0, 0, 0)
	inset.BackgroundTransparency = 0.45
	inset.BorderSizePixel = 0
	inset.ZIndex = 2
	inset.Parent = t

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = T.color.white
	fill.BorderSizePixel = 0
	fill.ZIndex = 1
	fill.Parent = t
	UI.corner(fill, r)
	UI.gradient(fill, T.gradient[fillVariant])
	return t, fill
end

function UI.setFill(fill: Frame, pct: number, animate: boolean?)
	local goal = UDim2.new(math.clamp(pct, 0, 1), 0, 1, 0)
	if animate then
		game:GetService("TweenService"):Create(fill, T.tween.bar, { Size = goal }):Play()
	else
		fill.Size = goal
	end
end

-- Labelled art slot — replace the placeholder with an ImageLabel in production.
function UI.artSlot(parent: Instance, size: UDim2, image: string?): ImageLabel
	local i = Instance.new("ImageLabel")
	i.Size = size
	i.BackgroundColor3 = T.color.slotTop
	-- kit deviation: "" (unuploaded icon) must render the placeholder, not an invisible slot
	local has = image ~= nil and image ~= ""
	i.BackgroundTransparency = if has then 1 else 0.15
	i.Image = if has then image else ""
	i.ScaleType = Enum.ScaleType.Fit
	i.BorderSizePixel = 0
	i.Parent = parent
	UI.corner(i, T.radius.art)
	return i
end

-- 4px inner rarity frame + inner glow. rarity: "common" | "rare" | "epic" | "legend"
function UI.rarityFrame(slot: GuiObject, rarity: string): Frame
	local map = {
		common = T.color.rarityCommon, rare = T.color.rarityRare,
		epic = T.color.rarityEpic, legend = T.color.rarityLegend,
	}
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundTransparency = 1
	-- relative like UI.rainbowRing (was hardcoded 5, which buried this stroke under any sibling art rendered above z=5, e.g. BackpackPanel's tile renders sitting at parent+1)
	f.ZIndex = (slot.ZIndex or 1) + 2
	f.Parent = slot
	UI.corner(f, T.radius.slot)
	local s = Instance.new("UIStroke")
	s.Thickness = 4
	s.Color = map[rarity]
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = f
	return f
end

-- Pulsing claimable ring (inset -4, radius 19 in the design).
function UI.claimRing(card: GuiObject): Frame
	local r = Instance.new("Frame")
	r.Size = UDim2.new(1, 8, 1, 8)
	r.Position = UDim2.fromOffset(-4, -4)
	r.BackgroundTransparency = 1
	r.ZIndex = 6
	r.Parent = card
	UI.corner(r, T.radius.control + 3)
	local s = Instance.new("UIStroke")
	s.Thickness = 5
	s.Color = T.color.claimRing
	s.Parent = r
	task.spawn(function()
		local TweenService = game:GetService("TweenService")
		local info = TweenInfo.new(T.tween.pulsePeriod / 2, Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut, -1, true)
		TweenService:Create(s, info, { Transparency = 0.45 }):Play()
	end)
	return r
end

------------------------------------------------------------------- additions
-- README-specified builders, missing from the vendored kit file. Same shared-
-- driver convention as ReplicatedStorage.Modules.RarityFX: ONE Heartbeat total,
-- a registry pruned when the instance is gone, instead of a connection per ring.

local RunService = game:GetService("RunService")

local ringActive, ringConn, ringClock = {}, nil, 0

local function ensureRingDriver()
	if ringConn then return end
	ringConn = RunService.Heartbeat:Connect(function(dt)
		ringClock += dt
		for i = #ringActive, 1, -1 do
			local e = ringActive[i]
			if not e.ring.Parent then
				table.remove(ringActive, i) -- ring destroyed by a rebuild/close
			else
				e.gradient.Rotation = (ringClock / 6 * 360 + e.phase) % 360
			end
		end
		if #ringActive == 0 then ringConn:Disconnect(); ringConn = nil end
	end)
end

-- Rainbow cycling ring around `card`. No texture asset exists yet, so this is a
-- Frame + UIStroke + UIGradient fallback (an ImageLabel ring texture can replace
-- it later without changing the call site). Rotation sweeps 0->360 over 6s.
function UI.rainbowRing(card: GuiObject, radius: number?): Frame
	local ring = Instance.new("Frame")
	ring.Name = "RainbowRing"
	ring.Size = UDim2.new(1, 10, 1, 10)
	ring.Position = UDim2.fromOffset(-5, -5)
	ring.BackgroundTransparency = 1
	ring.ZIndex = (card.ZIndex or 1) + 1
	ring.Parent = card
	UI.corner(ring, radius or T.radius.control)

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = ring

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    T.hex("#FF5252")),
		ColorSequenceKeypoint.new(0.25, T.hex("#FFB200")),
		ColorSequenceKeypoint.new(0.5,  T.hex("#7CE04A")),
		ColorSequenceKeypoint.new(0.75, T.hex("#3FA9F5")),
		ColorSequenceKeypoint.new(1,    T.hex("#A855F7")),
	})
	gradient.Parent = stroke

	ringActive[#ringActive + 1] = { ring = ring, gradient = gradient, phase = 0 }
	ensureRingDriver()
	return ring
end

-- Red notification pill. `value` is coerced to a string (e.g. "3", "9+").
function UI.badge(parent: Instance, value: string | number): Frame
	local b = Instance.new("Frame")
	b.Name = "Badge"
	b.AutomaticSize = Enum.AutomaticSize.X
	b.Size = UDim2.fromOffset(0, 30)
	b.BackgroundColor3 = T.color.white
	b.BorderSizePixel = 0
	b.ZIndex = 10
	b.Parent = parent
	UI.corner(b, T.radius.pill)
	UI.gradient(b, T.gradient.red)
	UI.stroke(b, 3.5)

	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(30, 30)
	constraint.Parent = b

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = b

	local l = Instance.new("TextLabel")
	l.Name = "Value"
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Text = tostring(value)
	l.TextColor3 = T.color.white
	l.TextSize = 16
	l.FontFace = T.font.ui
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.ZIndex = 11
	l.Parent = b

	return b
end

-- Small pill tag on a card corner. variant: "EQUIPPED" | "GRAND" | "NEW".
local RIBBON_VARIANT = {
	EQUIPPED = "green",
	GRAND = "purple",
	NEW = "red",
}

function UI.ribbon(parent: Instance, text: string, variant: string): Frame
	local grad = RIBBON_VARIANT[variant] or "green"
	local r = Instance.new("Frame")
	r.Name = "Ribbon"
	r.AutomaticSize = Enum.AutomaticSize.X
	r.Size = UDim2.fromOffset(0, 24)
	r.BackgroundColor3 = T.color.white
	r.BorderSizePixel = 0
	r.ZIndex = 10
	r.Parent = parent
	UI.corner(r, T.radius.chip)
	UI.gradient(r, T.gradient[grad])
	UI.stroke(r, T.stroke.chip)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = r

	local l = Instance.new("TextLabel")
	l.Name = "Text"
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Text = text
	l.TextColor3 = T.color.white
	l.TextSize = T.text.chip[1]
	l.FontFace = T.font.ui
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.ZIndex = 11
	l.Parent = r
	if T.text.chip[2] > 0 then
		local s = Instance.new("UIStroke")
		s.Thickness = T.text.chip[2]
		s.Color = T.color.outline
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		s.Parent = l
	end

	return r
end

return UI
