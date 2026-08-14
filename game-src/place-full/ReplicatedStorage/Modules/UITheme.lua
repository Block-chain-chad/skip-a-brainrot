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

-- Central click SFX wiring. Idempotent via the SfxWired attribute: -- SFX2
-- campButton/styleButton are deliberately RE-CALLED on the same button for -- SFX2
-- state swaps, so without the guard every restyle would stack another connect. -- SFX2
-- SoundKit is required lazily inside pcall (UITheme loads very early on both -- SFX2
-- client AND server, so an eager top-level require risks load-order cycles). -- SFX2
local function wireClick(btn, soundName) -- SFX2
	if not game:GetService("RunService"):IsClient() then return end -- SFX2
	if not btn:IsA("GuiButton") then return end -- SFX2
	if btn:GetAttribute("SfxWired") then return end -- SFX2
	btn:SetAttribute("SfxWired", true) -- SFX2
	btn.MouseButton1Click:Connect(function() -- SFX2
		local ok, kit = pcall(function() -- SFX2
			return require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("SoundKit")) -- SFX2
		end) -- SFX2
		if ok and kit then pcall(kit.play, soundName, nil, { volume = 0.12 }) end -- SFX2
	end) -- SFX2
end -- SFX2

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
	wireClick(btn, "uiClick") -- SFX2
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

-- Bars are children of btn, so Position/Size stay relative to it for free.
-- ZIndex needs live tracking: MainUI's Global ZIndexBehavior compares ZIndex
-- across the WHOLE tree instead of cascading a parent's Z to its children, so
-- a caller raising btn.ZIndex after styling (IndexClient does, deliberately)
-- would otherwise strand the bars at their old Z and let the button's own
-- opaque fill repaint over them.
--
-- Public: styleClose calls this, but so does anything that builds its own
-- close button by hand and can't go through styleClose (e.g. WheelClient's
-- oversized 56px Daily Spin close button, whose size/position/color are
-- deliberate and must not be reset to the 30px standard).
local closeXSignals = setmetatable({}, { __mode = "k" })
function M.closeGlyph(btn)
	local oldConn = closeXSignals[btn]
	if oldConn then oldConn:Disconnect() end
	for _, c in ipairs(btn:GetChildren()) do
		if c.Name == "CloseXBar" then c:Destroy() end
	end

	local bars = {}
	for _, rot in ipairs({ 45, -45 }) do
		local bar = Instance.new("Frame")
		bar.Name = "CloseXBar"
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.new(0.64, 0, 0.16, 0)
		bar.Rotation = rot
		bar.BackgroundColor3 = P.white
		bar.BorderSizePixel = 0
		bar.Parent = btn
		bars[#bars + 1] = bar
	end

	local function sync()
		for _, bar in ipairs(bars) do bar.ZIndex = btn.ZIndex + 1 end
	end
	sync()
	closeXSignals[btn] = btn:GetPropertyChangedSignal("ZIndex"):Connect(sync)
end

function M.styleClose(btn)
	btn.AnchorPoint = Vector2.new(1, 0)
	btn.Position = UDim2.new(1, -13, 0, 13)
	btn.Size = UDim2.fromOffset(30, 30)
	btn.BackgroundColor3 = P.white
	btn.Text = ""
	btn.AutoButtonColor = true
	btn.BorderSizePixel = 0
	btn.ZIndex = 6
	M.corner(btn, 15)
	M.gradient(btn, P.red1, P.red2, 90)
	if not btn:FindFirstChildOfClass("UIStroke") then M.stroke(btn, P.outline, 2) end
	M.closeGlyph(btn)
	wireClick(btn, "panelClose") -- SFX2
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
	wireClick(btn, "uiClick") -- SFX2
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
	wireClick(btn, "uiClick") -- SFX2
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

-- ===================================================================
-- CANDY style pack (2026-07-27). A SECOND palette living beside Camp,
-- from the user's design handoff (docs/design-handoff, build from v3):
-- bright Pet-Sim treatment -- white panels, comic-thick ink outlines,
-- and hard unblurred offset shadows.
--
-- Deliberately ADDITIVE. Camp and all 12 of its callers are untouched,
-- so nothing on screen changes until something opts in. That is what
-- makes reverting this a one-file revert rather than unpicking the
-- five-stage cafe restyle.
-- ===================================================================
local CANDY = {
	ink       = Color3.fromRGB(16, 19, 31),      -- #10131f, on everything
	panelTop  = Color3.fromRGB(255, 255, 255),
	panelBot  = Color3.fromRGB(207, 224, 245),   -- #cfe0f5
	shadow    = Color3.fromRGB(10, 13, 22),      -- #0a0d16, SOLID, never blurred
	green1    = Color3.fromRGB(163, 255, 79),
	green2    = Color3.fromRGB(61, 158, 24),
	red1      = Color3.fromRGB(255, 92, 122),
	red2      = Color3.fromRGB(163, 18, 58),
	gold1     = Color3.fromRGB(255, 230, 128),
	gold2     = Color3.fromRGB(224, 140, 0),
	onDark    = Color3.fromRGB(255, 255, 255),
	-- The handoff specifies Luckiest Guy, which Roblox does not have.
	-- FredokaOne is the nearest chunky rounded face. Kept HERE rather than
	-- on M.Font so the cafe face (Cartoon) is unaffected.
	font      = Enum.Font.FredokaOne,
	radius    = 26,    -- panels; chips use ~16
	-- Task 4 tune-by-eye: 4 (itself already reduced from the handoff's 6) still
	-- read heavy at Roblox scale once the whole wheel was on screen together --
	-- particularly stacked up on the small chips/rows, where a 4px border on a
	-- ~44px chip is proportionally thick. 3 keeps the "comic outline" read
	-- (relationship that must hold, per the spec) without looking like a slab.
	stroke    = 3,
}
M.Candy = CANDY

-- The detail that makes the reference read as a toy: a HARD offset shadow,
-- no blur. Drawn as a plain Frame behind the object, matching its corner
-- radius. Parented to the object's PARENT (not the object) so it cannot be
-- clipped by ClipsDescendants and cannot inherit a gradient.
function M.candyShadow(o, offsetY, radius)
	offsetY = offsetY or 8
	local sh = Instance.new("Frame")
	sh.Name = "CandyShadow"
	sh.BackgroundColor3 = CANDY.shadow
	sh.BorderSizePixel = 0
	sh.Size = o.Size
	sh.Position = o.Position + UDim2.fromOffset(0, offsetY)
	sh.AnchorPoint = o.AnchorPoint
	sh.ZIndex = math.max(1, o.ZIndex - 1)
	sh.Parent = o.Parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or CANDY.radius)
	c.Parent = sh
	return sh
end

function M.candyPanel(f, radius)
	f.BackgroundColor3 = CANDY.panelTop
	f.BorderSizePixel = 0
	M.corner(f, radius or CANDY.radius)
	M.gradient(f, CANDY.panelTop, CANDY.panelBot, 90)
	local s = Instance.new("UIStroke")
	s.Color = CANDY.ink
	s.Thickness = CANDY.stroke
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = f
	return f
end

function M.candyButton(b, c1, c2, radius)
	b.BackgroundColor3 = c1
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.TextColor3 = CANDY.onDark
	b.Font = CANDY.font
	M.corner(b, radius or 18)
	M.gradient(b, c1, c2, 90)
	local s = Instance.new("UIStroke")
	s.Color = CANDY.ink
	s.Thickness = CANDY.stroke
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = b
	-- a gradient multiplies TEXT as well as background and multiply can only
	-- darken, so a light label needs its own ink outline to survive. NOT
	-- M.inkText -- that shared helper hardcodes Camp's warm-brown ink (CF.ink),
	-- so a candy button's text outline would pick up the cafe's colour instead
	-- of candy's own near-black. Built by hand here so it stays on CANDY.ink.
	local ts = Instance.new("UIStroke")
	ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	ts.Color = CANDY.ink
	ts.Thickness = 2.5
	ts.Parent = b
	wireClick(b, "uiClick") -- SFX2
	return b
end

-- ===================================================================
-- BAZAAR style pack: dark stall-shop look (totem/gem shop reference).
-- Deliberately ADDITIVE, same as Candy above -- nothing else on screen
-- changes until a shop script opts in by calling these instead of
-- accentCard/campPanel/campButton.
-- ===================================================================
-- 2026-08-13 LEMONPOP RETINT (spec §3b "every shop"): the dark stall goes
-- lemon-cream -- light window, warm outline, ONE red header per shop window
-- (the per-shop bronze/green/pink header identities collapse into the red,
-- deliberate). Old values inline. Text colours below assume the pack's
-- builders now set NoPolish and follow the light/dark rule themselves.
local BZ = {
	ink        = Color3.fromRGB(36, 31, 20),    -- #241F14 (was 10,13,19)
	panelTop   = Color3.fromRGB(255, 251, 226), -- #FFFBE2 (was dark 38,46,60)
	panelBot   = Color3.fromRGB(255, 217, 119), -- #FFD977 (was 19,23,32)
	panelEdge  = Color3.fromRGB(36, 31, 20),    -- #241F14 (was 7,9,13)
	header1    = Color3.fromRGB(255, 107, 92),  -- #FF6B5C the ONE red (was cyan 126,219,255)
	header2    = Color3.fromRGB(216, 52, 44),   -- #D8342C (was 26,138,214)
	close1     = Color3.fromRGB(255, 107, 107), -- #FF6B6B (was 255,100,100)
	close2     = Color3.fromRGB(216, 62, 62),   -- #D83E3E (was 204,32,32)
	notice     = Color3.fromRGB(194, 65, 12),   -- #C2410C accent ink on light (was salmon 255,122,96)
	cardTop    = Color3.fromRGB(255, 246, 207), -- #FFF6CF subPanel (was 35,43,56)
	cardBot    = Color3.fromRGB(247, 201, 92),  -- #F7C95C (was 23,28,38)
	cardEdge   = Color3.fromRGB(36, 31, 20),    -- #241F14 (was 12,16,22)
	iconTop    = Color3.fromRGB(255, 255, 255), -- #FFFFFF light art well (was 48,57,74)
	iconBot    = Color3.fromRGB(255, 244, 217), -- #FFF4D9 (was 27,32,43)
	title      = Color3.fromRGB(194, 65, 12),   -- #C2410C item names = accent on light (was green 104,232,118)
	desc       = Color3.fromRGB(51, 38, 26),    -- #33261A ink on light (was 224,230,240)
	muted      = Color3.fromRGB(122, 106, 82),  -- #7A6A52 (was 150,158,174)
	stock      = Color3.fromRGB(216, 52, 44),   -- #D8342C warning red that reads on cream (was 255,92,92)
	cash1      = Color3.fromRGB(131, 227, 74),  -- #83E34A LemonPop green (was 200,246,96)
	cash2      = Color3.fromRGB(79, 180, 46),   -- #4FB42E (was 92,194,40)
	cashText   = Color3.fromRGB(24, 44, 10),
	gem1       = Color3.fromRGB(255, 197, 49),  -- #FFC531 LemonPop gold (was 255,194,92)
	gem2       = Color3.fromRGB(224, 138, 12),  -- #E08A0C (was 222,120,18)
	white      = Color3.fromRGB(255, 255, 255),
	rivetTop   = Color3.fromRGB(194, 168, 120), -- #C2A878 brass on cream (was 90,100,118)
	rivetBot   = Color3.fromRGB(138, 115, 80),  -- #8A7350 (was 30,35,46)
	rowAltTop  = Color3.fromRGB(255, 242, 192), -- #FFF2C0 alt stripe (was 31,38,50)
	rowAltBot  = Color3.fromRGB(242, 193, 84),  -- #F2C154 (was 19,23,32)
	shadow     = Color3.fromRGB(36, 31, 20),    -- #241F14 warm hard shadow (was 6,7,10)
	-- per-shop header identity RETIRED under LemonPop's one-red-header rule --
	-- keys kept so call sites don't change, all resolve to the red
	-- (was rock 255,199,120/197,122,32; sell 168,236,130/58,168,76; egg 255,156,214/188,72,172)
	rockHeader1 = Color3.fromRGB(255, 107, 92), rockHeader2 = Color3.fromRGB(216, 52, 44),
	sellHeader1 = Color3.fromRGB(255, 107, 92), sellHeader2 = Color3.fromRGB(216, 52, 44),
	eggHeader1  = Color3.fromRGB(255, 107, 92), eggHeader2  = Color3.fromRGB(216, 52, 44),
}
M.Bazaar = BZ
M.BazaarFont = Enum.Font.FredokaOne

local function bzStroke(o, color, thick)
	local s = Instance.new("UIStroke")
	s.Color = color; s.Thickness = thick or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = o
	return s
end

local function bzTextStroke(o, thick)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Color = BZ.ink; s.Thickness = thick or 2; s.Transparency = 0.1
	s.Parent = o
	return s
end

-- hard, unblurred offset shadow -- same technique as candyShadow, but on BZ.shadow.
-- Idempotent per SOURCE OBJECT via a weak map (same pattern as closeXSignals
-- above): re-calling this for the same `o` updates its existing shadow instead
-- of stacking a new one, which matters because bazaarPanel/Header/Close/Pill
-- can legitimately be re-called on the same instance (state restyles).
local bzShadowMap = setmetatable({}, { __mode = "k" })
local function bzShadow(o, offsetY, radius)
	local sh = bzShadowMap[o]
	if not sh or not sh.Parent then
		sh = Instance.new("Frame")
		sh.Name = "BazaarShadow"
		sh.BackgroundColor3 = BZ.shadow
		sh.BorderSizePixel = 0
		sh.Parent = o.Parent
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, radius or 12)
		c.Parent = sh
		bzShadowMap[o] = sh
		-- The shadow is a SIBLING of `o` -- it has to sit BEHIND the panel, so it
		-- cannot be a child of it -- which means hiding `o` does NOT hide this.
		-- Everything else below is copied from `o` (Size/Position/AnchorPoint/
		-- ZIndex); Visible was the one property never linked, so a closed panel
		-- left its shadow on screen as an opaque near-black rounded rectangle at
		-- the panel's exact size and position. Found live: MerchantFrame hidden
		-- but its 680x620 shadow still drawn, reading as a big black square
		-- mid-screen, with the Rock and Sell shops' 440x400 shadows orphaned
		-- underneath it. Same failure UI.hardShadow has -- see the Bug D2 note in
		-- GameHUDClient, which solved it with a wrapper Frame; this builder is
		-- called on frames it does not own, so it links the property instead.
		o:GetPropertyChangedSignal("Visible"):Connect(function()
			sh.Visible = o.Visible
		end)
	end
	-- Mirrored on every call, not only from the signal above: bazaarPanel and
	-- friends are re-called on state restyles, which can land while the panel is
	-- already hidden, and a fresh shadow must not flash back on.
	sh.Visible = o.Visible
	sh.Size = o.Size
	sh.Position = o.Position + UDim2.fromOffset(0, offsetY or 5)
	sh.AnchorPoint = o.AnchorPoint
	sh.ZIndex = math.max(1, o.ZIndex - 1)
	return sh
end

-- small stud/rivet, the "bolted-together market stall" detail on panel corners
local function bzRivet(parent, x, y, z)
	local r = Instance.new("Frame")
	r.Name = "Rivet"
	r.AnchorPoint = Vector2.new(0.5, 0.5)
	r.Position = UDim2.new(0, x, 0, y)
	r.Size = UDim2.fromOffset(9, 9)
	r.BackgroundColor3 = BZ.rivetTop
	r.BorderSizePixel = 0
	r.ZIndex = z
	r.Parent = parent
	M.corner(r, 5)
	M.gradient(r, BZ.rivetTop, BZ.rivetBot, 90)
	bzStroke(r, BZ.panelEdge, 1.5)
	return r
end

-- dark gradient panel body, used for the whole shop window. Chunkier than the
-- first pass: thicker outline, a hard offset shadow behind the whole panel,
-- and four corner rivets so it reads as a bolted-together market stall rather
-- than a flat generic dark rectangle.
function M.bazaarPanel(frame, radius)
	radius = radius or 18
	frame.BackgroundColor3 = BZ.panelTop
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	M.corner(frame, radius)
	M.gradient(frame, BZ.panelTop, BZ.panelBot, 90)
	if not frame:FindFirstChildOfClass("UIStroke") then bzStroke(frame, BZ.panelEdge, 4) end
	bzShadow(frame, 7, radius)
	if not frame:FindFirstChild("Rivet") then
		local w, h = frame.AbsoluteSize.X, frame.AbsoluteSize.Y
		-- fallback offsets for the very first frame (AbsoluteSize not resolved yet)
		if w == 0 then w, h = 440, 400 end
		bzRivet(frame, 16, 16, frame.ZIndex + 3)
		bzRivet(frame, w - 16, 16, frame.ZIndex + 3)
		bzRivet(frame, 16, h - 16, frame.ZIndex + 3)
		bzRivet(frame, w - 16, h - 16, frame.ZIndex + 3)
	end
	return frame
end

-- inset title bar with an optional leading glyph, e.g. "\u{1F4E6}". Pass
-- accentTop/accentBot to give a shop its OWN identity colour (rock shop
-- bronze, sell green, egg pink) instead of every panel sharing one cyan --
-- omit them and it falls back to the original cyan.
function M.bazaarHeader(parent, text, iconGlyph, accentTop, accentBot)
	local bar = Instance.new("Frame")
	bar.Name = "BazaarHeader"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 10)
	bar.Size = UDim2.new(1, -58, 0, 44)
	bar.BackgroundColor3 = BZ.white
	bar.BorderSizePixel = 0
	bar.ZIndex = (parent.ZIndex or 1) + 2
	bar.Parent = parent
	M.corner(bar, 12)
	M.gradient(bar, accentTop or BZ.header1, accentBot or BZ.header2, 90)
	bzStroke(bar, BZ.panelEdge, 3)
	bzShadow(bar, 4, 12)

	if iconGlyph then
		local icon = Instance.new("TextLabel")
		icon.Name = "Icon"
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 8, 0.5, 0)
		icon.Size = UDim2.fromOffset(30, 30)
		icon.BackgroundTransparency = 1
		icon.Font = Enum.Font.GothamBold
		icon.Text = iconGlyph
		icon.TextSize = 24
		icon.ZIndex = bar.ZIndex + 1
		icon.Parent = bar
	end

	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(0, iconGlyph and 42 or 14, 0.5, 0)
	label.Size = UDim2.new(1, (iconGlyph and -52 or -24), 1, 0)
	label.BackgroundTransparency = 1
	label.Font = M.BazaarFont
	label.Text = text or ""
	label.TextColor3 = BZ.white -- red header = dark ground: white + stroke stays
	label.TextSize = 21
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.ZIndex = bar.ZIndex + 1
	label:SetAttribute("NoPolish", true) -- LemonPop: the pack governs its own text
	label.Parent = bar
	bzTextStroke(label, 2)
	return bar, label
end

-- round red X, top-right corner of the panel
function M.bazaarClose(btn)
	btn.AnchorPoint = Vector2.new(1, 0)
	btn.Position = UDim2.new(1, -10, 0, 10)
	btn.Size = UDim2.fromOffset(38, 38)
	btn.BackgroundColor3 = BZ.white
	btn.Text = ""
	btn.AutoButtonColor = true
	btn.BorderSizePixel = 0
	btn.ZIndex = 20
	M.corner(btn, 12)
	M.gradient(btn, BZ.close1, BZ.close2, 90)
	if not btn:FindFirstChildOfClass("UIStroke") then bzStroke(btn, BZ.panelEdge, 3) end
	bzShadow(btn, 4, 12)
	M.closeGlyph(btn)
	wireClick(btn, "panelClose") -- SFX2
	return btn
end

-- small italic warning/notice line under the header (e.g. stock limit text)
function M.bazaarNotice(parent, text, yOffset)
	local lbl = Instance.new("TextLabel")
	lbl.Name = "Notice"
	lbl.AnchorPoint = Vector2.new(0.5, 0)
	lbl.Position = UDim2.new(0.5, 0, 0, yOffset or 58)
	lbl.Size = UDim2.new(1, -24, 0, 20)
	lbl.BackgroundTransparency = 1
	-- Enum.Font has no italic Gotham; GothamBoldItalic threw for every caller
	lbl.Font = Enum.Font.GothamBold
	lbl.Text = text or ""
	lbl:SetAttribute("NoPolish", true) -- LemonPop: accent ink on the light window
	lbl.TextColor3 = BZ.notice
	lbl.TextSize = 13
	lbl.TextWrapped = true
	lbl.ZIndex = (parent.ZIndex or 1) + 1
	lbl.Parent = parent
	return lbl
end

-- one dark bordered item row; caller fills in icon/title/desc/pills. Rows
-- alternate between two close shades (odd/even, counted off existing
-- siblings) so a long list reads as a striped stall shelf instead of one
-- undifferentiated dark slab -- purely cosmetic, no call site needs to change.
function M.bazaarRow(parent, height)
	local existing = 0
	for _, c in ipairs(parent:GetChildren()) do
		if c:IsA("Frame") and c.Name == "Row" then existing += 1 end
	end
	local top, bot = BZ.cardTop, BZ.cardBot
	if existing % 2 == 1 then top, bot = BZ.rowAltTop, BZ.rowAltBot end

	local row = Instance.new("Frame")
	row.Name = "Row"
	row.Size = UDim2.new(1, 0, 0, height or 96)
	row.BackgroundColor3 = top
	row.BorderSizePixel = 0
	row.Parent = parent
	M.corner(row, 12)
	M.gradient(row, top, bot, 90)
	bzStroke(row, BZ.cardEdge, 3)
	return row
end

function M.bazaarIconSlot(parent, size)
	size = size or 64
	local icon = Instance.new("Frame")
	icon.Name = "IconSlot"
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 10, 0.5, 0)
	icon.Size = UDim2.fromOffset(size, size)
	icon.BackgroundColor3 = BZ.iconTop
	icon.BorderSizePixel = 0
	icon.ClipsDescendants = true
	icon.ZIndex = (parent.ZIndex or 1) + 1
	icon.Parent = parent
	M.corner(icon, 10)
	M.gradient(icon, BZ.iconTop, BZ.iconBot, 90)
	bzStroke(icon, BZ.cardEdge, 2.5)
	return icon
end

function M.bazaarTitle(parent, text)
	local lbl = Instance.new("TextLabel")
	lbl.Name = "Title"
	lbl.BackgroundTransparency = 1
	lbl.Font = M.BazaarFont
	lbl.Text = text or ""
	lbl.TextColor3 = BZ.title
	lbl.TextSize = 18
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextTruncate = Enum.TextTruncate.AtEnd
	lbl.ZIndex = (parent.ZIndex or 1) + 1
	lbl:SetAttribute("NoPolish", true) -- LemonPop: accent ink on a light card, UNSTROKED
	lbl.Parent = parent
	return lbl
end

function M.bazaarDesc(parent, text)
	local lbl = Instance.new("TextLabel")
	lbl.Name = "Desc"
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamMedium
	lbl.Text = text or ""
	lbl:SetAttribute("NoPolish", true) -- LemonPop: dark ink on light card
	lbl.TextColor3 = BZ.desc
	lbl.TextSize = 13
	lbl.TextWrapped = true
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Top
	lbl.ZIndex = (parent.ZIndex or 1) + 1
	lbl.Parent = parent
	return lbl
end

function M.bazaarStock(parent, text)
	local lbl = Instance.new("TextLabel")
	lbl.Name = "Stock"
	lbl.BackgroundTransparency = 1
	-- see bazaarNotice: no italic Gotham exists
	lbl.Font = Enum.Font.GothamBold
	lbl.Text = text or ""
	lbl:SetAttribute("NoPolish", true) -- LemonPop: warning red on light card
	lbl.TextColor3 = BZ.stock
	lbl.TextSize = 13
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.ZIndex = (parent.ZIndex or 1) + 1
	lbl.Parent = parent
	return lbl
end

-- price/cost pill. kind: "cash" (green->yellow, dark text) or "gem" (orange, white text)
function M.bazaarPill(parent, text, kind)
	local btn = Instance.new("TextButton")
	btn.Name = (kind == "gem") and "GemPill" or "CashPill"
	btn.BackgroundColor3 = BZ.white
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.Font = Enum.Font.GothamBlack
	btn.Text = text or ""
	btn.TextSize = 16
	btn.ZIndex = (parent.ZIndex or 1) + 1
	btn:SetAttribute("NoPolish", true) -- LemonPop: pill governs its own label
	btn.Parent = parent
	M.corner(btn, 10)
	if kind == "gem" then
		M.gradient(btn, BZ.gem1, BZ.gem2, 90)
		btn.TextColor3 = BZ.white
		bzTextStroke(btn, 1.6)
	else
		M.gradient(btn, BZ.cash1, BZ.cash2, 90)
		btn.TextColor3 = BZ.cashText
	end
	bzStroke(btn, BZ.ink, 2.5)
	-- pills live inside a Row, so a shadow parented to the SAME row (not the
	-- row's parent) tracks the row's list-managed position automatically --
	-- no PropertyChangedSignal needed, unlike panel/header/close above.
	bzShadow(btn, 3, 10)
	wireClick(btn, "uiClick") -- SFX2
	return btn
end

-- Mutates an EXISTING button in place (the pattern every live call site
-- actually uses instead of bazaarPill, since their buttons are authored once
-- and just get recoloured on state changes -- often every data refresh, which
-- is exactly why bzShadow's idempotency above matters here). kind is unused
-- but kept for call-site symmetry with bazaarPill.
function M.bazaarRestylePill(btn, c1, c2, textColor)
	btn.BackgroundColor3 = BZ.white
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.Font = Enum.Font.GothamBlack
	btn:SetAttribute("NoPolish", true) -- LemonPop: caller-chosen pill colours survive the polish pass
	btn.TextColor3 = textColor
	M.corner(btn, 10)
	M.gradient(btn, c1, c2, 90)
	for _, s in ipairs(btn:GetChildren()) do
		if s:IsA("UIStroke") then s:Destroy() end
	end
	bzStroke(btn, BZ.ink, 2.5)
	bzShadow(btn, 3, 10)
	wireClick(btn, "uiClick") -- SFX2
end

return M
