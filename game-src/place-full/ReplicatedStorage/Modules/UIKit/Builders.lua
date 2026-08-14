--!strict
-- ui_builders.lua — the five primitives this style needs, so panels stay short.
-- Reproduces: thick outline, hard offset shadow, vertical gradient, top gloss,
-- bottom shade, stroked display text, inset track.
--
-- local UI = require(script.Parent.ui_builders)
-- local panel = UI.panel(parent, UDim2.fromOffset(960, 566))
-- local btn   = UI.button(panel, "Claim", "green", UDim2.fromOffset(136, 60))

local T = require(script.Parent.Tokens)
-- SoundKit is a LEAF (requires no module) and UIKit is never required server-side,
-- so this cannot cycle. Same SfxWired attribute key UITheme/UIStyle use, so a button
-- built here and restyled elsewhere still gets exactly ONE click connection.
local RunService = game:GetService("RunService")
local SoundKit = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("SoundKit"))
local CLICK_VOLUME = 0.12
local function wireClick(btn: GuiButton, soundName: string?)
	if not RunService:IsClient() then return end
	if btn:GetAttribute("SfxWired") then return end
	btn:SetAttribute("SfxWired", true)
	btn.MouseButton1Click:Connect(function()
		pcall(SoundKit.play, soundName or "uiClick", nil, { volume = CLICK_VOLUME })
	end)
end

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

--[[ GLOSS AND SHADE ARE RETIRED (2026-08-06, user call).

This used to draw a white strip along the top edge of a surface and a dark strip
along the bottom, on all 68 elements that pass through here. Because both were
full-width and pinned flush to the edge, on a rounded host they overhung the
curve and rendered as pale bars sitting proud of the shape -- worst on the
currency pills, which are stadiums ~37px round while the gloss was a 6px strip
whose own corner clamped to 3px.

I first fixed that by clipping both strips to the host's silhouette, which did
work. The user's call on seeing it was that the banding itself is the problem,
not where its edges land -- so the strips are gone rather than contained. The
surfaces keep their UIGradient, which is what actually gives them their form.

Every caller that looks the strips up by name guards with `if gloss then` -- the
cash pill, the egg shop's open button, toasts, the throw frame and button, the
rail's legacy sweep. Checked all six; they simply skip now.
]]
function UI.gloss(frame: GuiObject, _radius: number?, _lightAlpha: number?)
	-- Nothing is drawn. See the note above.
	--
	-- Still a FUNCTION, not deleted: 20 scripts call it, and it now does the
	-- useful job of TAKING DOWN strips on any instance that already has them --
	-- a reused element, or one built before this change.
	for _, n in ipairs({ "GlossClip", "Gloss", "Shade" }) do
		local old = frame:FindFirstChild(n)
		if old then old:Destroy() end
	end
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

	-- FIX F2 (2026-07-30 fix wave): shadow FOLLOWS its frame. UI.button (and
	-- every panel) calls UI.hardShadow at creation time, before the caller
	-- repositions the frame (the mandatory two-step pattern: `local f = ...;
	-- f.Position = ...` set AFTER construction) -- so the shadow captured
	-- above at the frame's creation-time Position/AnchorPoint would otherwise
	-- be stranded wherever `frame` originally sat, visible as a dark offset
	-- block under every panel's close button, the Pass quests button, and the
	-- Goals/Settings segment buttons. Three connections per shadow is fine --
	-- shadows are few. No double-offset risk: sh.Position is already set to
	-- frame.Position + offset above, so if Position never changes these
	-- handlers simply never fire and the initial value stands untouched.
	frame:GetPropertyChangedSignal("Position"):Connect(function()
		sh.Position = frame.Position + UDim2.fromOffset(0, offsetY)
	end)
	frame:GetPropertyChangedSignal("AnchorPoint"):Connect(function()
		sh.AnchorPoint = frame.AnchorPoint
	end)
	frame.Destroying:Connect(function()
		sh:Destroy()
	end)

	return sh
end

-- Display text. `styleKey` indexes T.text.
-- LemonPop 2026-08-13: the stroke follows the FILL, not the style spec alone
-- -- light type (white/gold, i.e. sitting on a dark or saturated ground)
-- keeps the heavy outline; dark ink (the light-surface default) carries
-- itself unstroked. Luminance decides, same trick as UITheme.campButton.
local function lum(c: Color3): number
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end
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
	if spec[2] > 0 and lum(l.TextColor3) > 0.5 then
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
-- LemonPop: the kit's light grounds; every other kind is treated as dark/saturated
local LIGHT_KINDS = {
	panel = true, subPanel = true, slot = true, window = true, cream = true,
	freeCard = true, lockBadge = true, knob = true, passCard = true,
}
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
	-- LemonPop 2026-08-13: any surface that is not one of the kit's LIGHT
	-- grounds is dark or saturated (rows, tracks, tabs, the red header, and
	-- the action-gradient kinds panels use for header bars) -- tag it once and
	-- UIPolish gives every label inside the white stroked on-dark treatment;
	-- light surfaces default to dark unstroked ink.
	if not LIGHT_KINDS[kind] then
		f:SetAttribute("PolishOnDark", true)
	end
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
	-- LemonPop 2026-08-13: action gradients are saturated grounds -- their
	-- labels keep the white stroked treatment (see UIPolish PolishOnDark)
	b:SetAttribute("PolishOnDark", true)
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
	-- disabled variants stay silent: a dead control that clicks reads as a bug
	if variant ~= "disabled" then wireClick(b, "uiClick") end
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
	b:SetAttribute("PolishOnDark", true) -- LemonPop: red pill = saturated ground, white stroked label
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
	r:SetAttribute("PolishOnDark", true) -- LemonPop: ribbon gradients = saturated grounds, white stroked label
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
