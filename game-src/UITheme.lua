-- UITheme: shared premium "candy" styling helpers so menus match the side-rail.
local M = {}

local P = {
	panelTop = Color3.fromRGB(40, 46, 62),
	panelBot = Color3.fromRGB(23, 27, 39),
	outline = Color3.fromRGB(14, 19, 29),
	cardTop = Color3.fromRGB(48, 54, 72),
	cardBot = Color3.fromRGB(33, 38, 53),
	cardOutline = Color3.fromRGB(17, 22, 33),
	text = Color3.fromRGB(255, 255, 255),
	subtext = Color3.fromRGB(168, 176, 196),
	white = Color3.fromRGB(255, 255, 255),
	gold1 = Color3.fromRGB(255, 216, 107), gold2 = Color3.fromRGB(240, 150, 30),
	green1 = Color3.fromRGB(96, 222, 128), green2 = Color3.fromRGB(46, 176, 88),
	blue1 = Color3.fromRGB(96, 182, 255), blue2 = Color3.fromRGB(30, 127, 219),
	red1 = Color3.fromRGB(255, 112, 98), red2 = Color3.fromRGB(220, 60, 54),
	-- vibrant HUD
	hudThrow1 = Color3.fromRGB(255, 138, 88), hudThrow2 = Color3.fromRGB(228, 62, 40),
	hudShop1 = Color3.fromRGB(116, 196, 255), hudShop2 = Color3.fromRGB(26, 116, 228),
	hudPlot1 = Color3.fromRGB(126, 238, 156), hudPlot2 = Color3.fromRGB(36, 172, 86),
	hudGold1 = Color3.fromRGB(255, 216, 96), hudGold2 = Color3.fromRGB(238, 148, 24),
	hudMuted1 = Color3.fromRGB(152, 158, 172), hudMuted2 = Color3.fromRGB(94, 100, 114),
	hudDark1 = Color3.fromRGB(46, 52, 68), hudDark2 = Color3.fromRGB(22, 26, 38),
	cashText = Color3.fromRGB(126, 255, 148),
}
M.Palette = P

function M.corner(o, r)
	local c = o:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 12); c.Parent = o; return c
end

function M.stroke(o, color, thick, transp)
	local s = Instance.new("UIStroke")
	s.Color = color or P.outline; s.Thickness = thick or 2; s.Transparency = transp or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.LineJoinMode = Enum.LineJoinMode.Round; s.Parent = o; return s
end

function M.gradient(o, cTop, cBot, rot)
	local g = o:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
	g.Rotation = rot or 90; g.Color = ColorSequence.new(cTop, cBot); g.Parent = o; return g
end

-- soft white gloss strip over the top of an element (no text underneath)
function M.gloss(o, radius, topTransparency)
	local gl = Instance.new("Frame")
	gl.Name = "Gloss"; gl.AnchorPoint = Vector2.new(0.5, 0); gl.Position = UDim2.new(0.5, 0, 0, 2)
	gl.Size = UDim2.new(1, -6, 0.44, 0); gl.BackgroundColor3 = P.white; gl.BorderSizePixel = 0
	gl.ZIndex = (o.ZIndex or 1) + 1; gl.Parent = o
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, radius or 8); c.Parent = gl
	local g = Instance.new("UIGradient"); g.Rotation = 90
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, topTransparency or 0.5), NumberSequenceKeypoint.new(1, 1) }); g.Parent = gl
	return gl
end

-- glossy rounded medallion chip (used for shop rock / sell rarity swatch)
function M.medallion(parent, size, pos, color)
	local m = Instance.new("Frame")
	m.Size = size; m.Position = pos; m.AnchorPoint = Vector2.new(0, 0.5)
	m.BackgroundColor3 = color; m.BorderSizePixel = 0; m.Parent = parent
	M.corner(m, 10)
	M.stroke(m, P.white, 1.5, 0.5)
	M.gloss(m, 8)
	return m
end

-- idempotent premium action button (safe to re-call to change color per state)
function M.styleButton(btn, cTop, cBot)
	btn.AutoButtonColor = true
	btn.BackgroundColor3 = P.white
	btn.TextColor3 = P.white
	btn.Font = Enum.Font.GothamBold
	btn.BorderSizePixel = 0
	M.corner(btn, 9)
	M.gradient(btn, cTop, cBot, 90)
	local hasBorder, hasText = false, false
	for _, s in ipairs(btn:GetChildren()) do
		if s:IsA("UIStroke") then
			if s.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then hasText = true else hasBorder = true end
		end
	end
	if not hasBorder then M.stroke(btn, P.outline, 2) end
	if not hasText then
		local ts = Instance.new("UIStroke")
		ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		ts.Color = Color3.fromRGB(28, 32, 42); ts.Thickness = 2; ts.Transparency = 0.1; ts.Parent = btn
	end
end

function M.stylePanel(frame)
	frame.BackgroundColor3 = P.white
	frame.BackgroundTransparency = 0.03
	M.corner(frame, 16)
	if not frame:FindFirstChildOfClass("UIGradient") then M.gradient(frame, P.panelTop, P.panelBot, 90) end
	if not frame:FindFirstChildOfClass("UIStroke") then M.stroke(frame, P.outline, 2.5) end
end

function M.styleHeader(titleLabel, accentTop, accentBot)
	titleLabel.AnchorPoint = Vector2.new(0.5, 0)
	titleLabel.Position = UDim2.new(0.5, 0, 0, 9)
	titleLabel.Size = UDim2.new(1, -18, 0, 40)
	titleLabel.BackgroundColor3 = P.white
	titleLabel.BackgroundTransparency = 0
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextColor3 = P.white
	titleLabel.TextSize = 19
	titleLabel.BorderSizePixel = 0
	M.corner(titleLabel, 12)
	M.gradient(titleLabel, accentTop, accentBot, 90)
	if not titleLabel:FindFirstChildOfClass("UIStroke") then M.stroke(titleLabel, P.outline, 2) end
	local ts = Instance.new("UIStroke")
	ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual; ts.Color = Color3.fromRGB(20, 22, 28); ts.Thickness = 1.6; ts.Transparency = 0.3; ts.Parent = titleLabel
end

function M.styleClose(btn)
	btn.AnchorPoint = Vector2.new(1, 0)
	btn.Position = UDim2.new(1, -13, 0, 13)
	btn.Size = UDim2.fromOffset(30, 30)
	btn.BackgroundColor3 = P.white
	btn.Text = "\u{2715}"
	btn.TextColor3 = P.white
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 16
	btn.AutoButtonColor = true
	btn.BorderSizePixel = 0
	btn.ZIndex = 6
	M.corner(btn, 15)
	M.gradient(btn, P.red1, P.red2, 90)
	if not btn:FindFirstChildOfClass("UIStroke") then M.stroke(btn, P.outline, 2) end
end

-- ===================================================================
-- CAMPFIRE style pack (v2 look): chunky black outlines, sunburst icon
-- backdrops, carved-wood ribbon headers, per-card accent colours.
-- Warm lake-and-campfire palette instead of the old cool navy.
-- ===================================================================
local CF = {
	-- CAFE palette. Panels are cream and the ink is dark BROWN, never black.
	ink      = Color3.fromRGB(62, 34, 19),     -- outline on every shape AND glyph
	panelTop = Color3.fromRGB(250, 240, 224),  -- cream panel body
	panelBot = Color3.fromRGB(238, 224, 200),
	cardTop  = Color3.fromRGB(245, 220, 192),  -- card cream
	cardBot  = Color3.fromRGB(231, 203, 170),
	-- `cream` and `muted` are TEXT colours, and the panel under them just went
	-- from dark green to cream -- so they invert to dark brown. Roughly 58 call
	-- sites across 12 client scripts read these two, which is exactly why the
	-- swap happens here instead of in every script.
	cream    = Color3.fromRGB(62, 34, 19),
	muted    = Color3.fromRGB(138, 108, 82),
	-- for glyphs/fills that sit on a DARK or saturated surface (header bar,
	-- accent buttons) where dark-on-dark would disappear
	onDark   = Color3.fromRGB(255, 246, 228),
	wood1    = Color3.fromRGB(205, 132, 58),   -- warm-brown header bar
	wood2    = Color3.fromRGB(178, 104, 40),
	locked1  = Color3.fromRGB(214, 198, 176),  -- disabled / locked button fill
	locked2  = Color3.fromRGB(186, 168, 146),
	-- per-card accents
	amber1 = Color3.fromRGB(255, 200, 96),  amber2 = Color3.fromRGB(232, 138, 34),
	ember1 = Color3.fromRGB(255, 152, 82),  ember2 = Color3.fromRGB(214, 80, 40),
	pine1  = Color3.fromRGB(146, 214, 122), pine2  = Color3.fromRGB(54, 140, 76),
	lake1  = Color3.fromRGB(126, 216, 224), lake2  = Color3.fromRGB(36, 138, 166),
	berry1 = Color3.fromRGB(226, 150, 226), berry2 = Color3.fromRGB(146, 68, 168),
}
M.Camp = CF

-- the bubbly cafe face, picked off the Stage 5 proof board
M.Font = Enum.Font.Cartoon

-- decorative dingbats (✦, arrows) -- the theme face above may not carry these
-- glyphs, so anything ornamental rather than body text draws from here instead
M.GlyphFont = Enum.Font.GothamBold

local function lum(c) return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B end

-- heavy black outline (the single biggest reason this style pops)
function M.ink(o, thick)
	local s = Instance.new("UIStroke")
	s.Color = CF.ink; s.Thickness = thick or 3; s.Transparency = 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = o
	return s
end

-- black outline around TEXT glyphs
function M.inkText(o, thick)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Color = CF.ink; s.Thickness = thick or 2.4; s.Transparency = 0
	s.Parent = o
	return s
end

-- radial sunburst rays behind an icon; rays pivot on their AnchorPoint at the centre
function M.sunburst(parent, color, rays, baseTop, baseBot)
	rays = rays or 12
	local holder = Instance.new("Frame")
	holder.Name = "Sunburst"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundColor3 = P.white
	holder.BorderSizePixel = 0
	holder.ClipsDescendants = true
	holder.ZIndex = (parent.ZIndex or 1)
	holder.Parent = parent
	M.corner(holder, 10)
	-- Cafe look: the radial rays are RETIRED. The base is always the light card
	-- cream now -- callers pass their old dark base colours (e.g. cardBot/ink),
	-- which on the cafe palette would render a dark tile, so they're ignored.
	M.gradient(holder, CF.cardTop, CF.cardBot, 90)
	-- One flat accent wash replaces the rays, keeping each caller's "one accent
	-- per card" read. It is still NAMED "Ray" on purpose: RareCatchClient walks
	-- the burst's children and retints anything called "Ray" to show the tier
	-- colour, so that per-tier read keeps working with no change at the call site.
	local wash = holder:FindFirstChild("Ray") or Instance.new("Frame")
	wash.Name = "Ray"
	wash.Size = UDim2.fromScale(1, 1)
	wash.BackgroundColor3 = color
	wash.BackgroundTransparency = 0.58
	wash.BorderSizePixel = 0
	wash.ZIndex = holder.ZIndex
	wash.Parent = holder
	M.corner(wash, 10)
	return holder
end

-- derive a card interior from an accent hue so each card reads in its OWN
-- colour instead of a uniform cream -- this is what makes the cards pop.
-- Cafe version: PALE tinted cream. The body text on these cards is now dark
-- brown, so the old deep jewel-tone interior would swallow it whole.
function M.accentFill(accent)
	local h, s = accent:ToHSV()
	local top = Color3.fromHSV(h, math.min(s * 0.30, 1), 0.98)
	local bot = Color3.fromHSV(h, math.min(s * 0.46, 1), 0.90)
	return top, bot
end

-- card with an accent border + black outline. returns the INNER content frame.
-- the interior is tinted toward `accent` so each card reads as its own colour.
function M.accentCard(parent, accent, radius)
	local outer = Instance.new("Frame")
	outer.BackgroundColor3 = accent
	outer.BorderSizePixel = 0
	outer.Parent = parent
	M.corner(outer, radius or 14)
	M.ink(outer, 3)
	local inner = Instance.new("Frame")
	inner.Name = "Content"
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.new(1, -7, 1, -7)
	inner.BackgroundColor3 = P.white
	inner.BorderSizePixel = 0
	inner.ZIndex = (outer.ZIndex or 1) + 1
	inner.Parent = outer
	M.corner(inner, (radius or 14) - 3)
	local fillTop, fillBot = M.accentFill(accent)
	M.gradient(inner, fillTop, fillBot, 90)
	return inner, outer
end

-- carved-wood banner that overhangs the top of a panel
function M.ribbon(parent, text, widthScale)
	local holder = Instance.new("Frame")
	holder.Name = "Ribbon"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, -22)
	holder.Size = UDim2.new(widthScale or 0.74, 0, 0, 58)
	holder.BackgroundTransparency = 1
	holder.ZIndex = (parent.ZIndex or 1) + 4
	holder.Parent = parent
	for _, side in ipairs({ -1, 1 }) do
		local tab = Instance.new("Frame")
		tab.Name = "Tab"
		tab.AnchorPoint = Vector2.new(0.5, 0.5)
		tab.Position = UDim2.new(side < 0 and 0 or 1, side * 16, 0.5, 7)
		tab.Size = UDim2.fromOffset(58, 42)
		tab.Rotation = side * 8
		tab.BackgroundColor3 = P.white
		tab.BorderSizePixel = 0
		tab.ZIndex = holder.ZIndex
		tab.Parent = holder
		M.corner(tab, 8)
		M.gradient(tab, CF.wood2, CF.ink, 90)
		M.ink(tab, 3)
	end
	local plank = Instance.new("Frame")
	plank.Name = "Plank"
	plank.Size = UDim2.fromScale(1, 1)
	plank.BackgroundColor3 = P.white
	plank.BorderSizePixel = 0
	plank.ZIndex = holder.ZIndex + 1
	plank.Parent = holder
	M.corner(plank, 12)
	M.gradient(plank, CF.wood1, CF.wood2, 90)
	M.ink(plank, 3.5)
	M.gloss(plank, 10, 0.86)   -- keep the sheen subtle or the wood washes out to beige
	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = M.Font
	label.TextScaled = false
	label.TextSize = 30
	label.TextColor3 = CF.onDark
	label.Text = text or ""
	label.ZIndex = holder.ZIndex + 3
	label.Parent = holder
	M.inkText(label, 3.2)
	return holder, label
end

-- Solid warm-brown header bar: the cafe alternative to M.ribbon's carved plank.
-- Sits flush across the top of a panel instead of overhanging it.
function M.headerBar(parent, text, height)
	local bar = Instance.new("Frame")
	bar.Name = "HeaderBar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 0)
	bar.Size = UDim2.new(1, 0, 0, height or 52)
	bar.BackgroundColor3 = P.white
	bar.BorderSizePixel = 0
	bar.ZIndex = (parent.ZIndex or 1) + 2
	bar.Parent = parent
	M.corner(bar, 16)
	M.gradient(bar, CF.wood1, CF.wood2, 90)
	M.ink(bar, 3)
	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = M.Font
	label.TextSize = 26
	label.TextColor3 = CF.onDark
	label.Text = text or ""
	label.ZIndex = bar.ZIndex + 1
	label.Parent = bar
	M.inkText(label, 2.6)
	return bar, label
end

-- cream panel body for the cafe look
function M.campPanel(frame)
	frame.BackgroundColor3 = P.white
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	M.corner(frame, 18)
	M.gradient(frame, CF.panelTop, CF.panelBot, 90)
	M.ink(frame, 4)
end

-- big chunky price/action pill
function M.campButton(btn, cTop, cBot)
	btn.BackgroundColor3 = P.white
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.Font = M.Font
	-- campButton gradient/locked-state audit (the spec asked for this sweep).
	-- A UIGradient on a TextButton multiplies its TEXT as well as its background,
	-- so NEITHER a light nor a dark label survives on fill colour alone. What
	-- actually carries legibility is the thick dark-brown glyph outline applied
	-- below -- light glyphs + heavy ink outline is the reference look on the
	-- saturated buttons. Dark ink is only correct on a genuinely PALE fill
	-- (locked/disabled, or the cream panel colours), where a light label would
	-- vanish and the outline would be all that's left.
	btn.TextColor3 = ((lum(cTop) + lum(cBot)) * 0.5 > 0.70) and CF.ink or CF.onDark
	M.corner(btn, 10)
	M.setColors(btn, cTop, cBot)
	if not btn:FindFirstChildOfClass("UIStroke") then M.ink(btn, 3) end
	local hasText = false
	for _, s in ipairs(btn:GetChildren()) do
		if s:IsA("UIStroke") and s.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then hasText = true end
	end
	if not hasText then M.inkText(btn, 2.6) end
end

-- swap an already-styled element's gradient colors (state changes)
function M.setColors(o, cTop, cBot)
	local g = o:FindFirstChildOfClass("UIGradient")
	if g then g.Color = ColorSequence.new(cTop, cBot) else M.gradient(o, cTop, cBot, 90) end
end

-- vibrant HUD button: bright gradient + gloss shine + chunky dark outline + outlined bold text
function M.styleHudButton(btn, cTop, cBot, radius)
	radius = radius or 12
	btn.BackgroundColor3 = P.white
	btn.BackgroundTransparency = 0
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.Font = Enum.Font.GothamBlack
	btn.TextColor3 = P.white
	M.corner(btn, radius)
	M.setColors(btn, cTop, cBot)
	local border, textStroke
	for _, s in ipairs(btn:GetChildren()) do
		if s:IsA("UIStroke") then
			if s.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then textStroke = s else border = s end
		end
	end
	border = border or M.stroke(btn, P.outline, 3)
	border.Color = P.outline; border.Thickness = 3; border.Transparency = 0
	if not textStroke then
		textStroke = Instance.new("UIStroke")
		textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		textStroke.Parent = btn
	end
	textStroke.Color = Color3.fromRGB(20, 24, 32); textStroke.Thickness = 2; textStroke.Transparency = 0.1
	if not btn:FindFirstChild("Gloss") then M.gloss(btn, math.max(radius - 3, 4), 0.72) end
	return btn
end

-- dark glossy chip (cash counter, throw panel) with an accent rim
function M.styleHudChip(frame, radius, accent, accentTransparency)
	radius = radius or 12
	frame.BackgroundColor3 = P.white
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	M.corner(frame, radius)
	M.setColors(frame, P.hudDark1, P.hudDark2)
	local border
	for _, s in ipairs(frame:GetChildren()) do
		if s:IsA("UIStroke") and s.ApplyStrokeMode ~= Enum.ApplyStrokeMode.Contextual then border = s end
	end
	border = border or M.stroke(frame, accent or P.hudGold1, 2.5)
	border.Color = accent or P.hudGold1
	border.Thickness = 2.5
	border.Transparency = accentTransparency or 0.15
	if not frame:FindFirstChild("Gloss") then M.gloss(frame, math.max(radius - 3, 4), 0.82) end
	return frame
end

return M
