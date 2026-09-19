--[[
UIStyle — bubbly "cartoony simulator" theme for the Trading Center surfaces
============================================================================
Used by: TradeClient (green), BoothClient (teal), SeasonClient (purple).
NOT used by ClientMain / shop / sell menus — those keep UITheme, untouched.

STYLE GUIDE (read me before styling anything new!)
--------------------------------------------------
* Shapes: everything rounded. Panels corner 18, cards/buttons corner 12,
  pills for money amounts. -> UIStyle.corner / UIStyle.pill
* Outlines: thick dark Border-mode UIStroke on everything. Panels 6px,
  buttons/cards 3px. -> UIStyle.stroke
* Color: saturated vertical gradients, light on top -> dark on bottom.
  One accent per surface:
      Trade  = green,   Booth = teal,   Season = purple,
      Gold   = ONLY for cash / price / reward amounts (any surface),
      Red    = destructive (cancel / decline / remove / close),
      Grey   = neutral or disabled, Locked = dark desaturated locked state.
  Cream is the card body color; Ink is the dark text color used on cream.
* Text: chunky white FredokaOne (Fonts.Title) for titles + button labels,
  GothamBold (Fonts.Body) for small body text and dense numbers. EVERY
  white text that sits on a gradient MUST get a Contextual UIStroke via
  UIStyle.bubbleText — white-on-light with no outline is invisible (this
  bit us before; do not skip it).
* Motion: panels pop in/out (popIn/popOut), buttons scale on hover AND
  press (attachHoverPress). Never rely on hover alone — mobile has none.

All helpers are idempotent: re-calling one on the same instance updates
the existing named child instead of duplicating it. Canonical child names:
  "UIStyleCorner", "UIStyleStrokeBorder" (Border mode),
  "UIStyleStrokeText" (Contextual mode), "UIStyleGradient",
  "UIStyleScale" (panel root scale), "PressScale" (button hover/press).
Border vs text strokes are distinguished by ApplyStrokeMode AND by name.
]]

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
-- SoundKit is a LEAF (it requires no module of its own), and UIStyle is never
-- required server-side, so this top-level require cannot cycle. UITheme requires
-- it lazily instead only because UITheme loads on the server too.
local SoundKit = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("SoundKit"))

local UIStyle = {}

-- CLICK AUDIO. Deliberately the SAME "SfxWired" attribute key UITheme.wireClick
-- uses: a button that passes through constructors in BOTH modules (or is styled
-- and then wired directly) can only ever get ONE connection, so it can never
-- double-click. Volume matches UITheme's existing 0.12 so every button in the
-- game sits at one level.
local CLICK_VOLUME = 0.12
local function wireClick(btn, soundName)
	if not RunService:IsClient() then return end
	if typeof(btn) ~= "Instance" or not btn:IsA("GuiButton") then return end
	if btn:GetAttribute("SfxWired") then return end
	btn:SetAttribute("SfxWired", true)
	btn.MouseButton1Click:Connect(function()
		pcall(SoundKit.play, soundName or "uiClick", nil, { volume = CLICK_VOLUME })
	end)
end
UIStyle._wireClick = wireClick

local function C(r, g, b) return Color3.fromRGB(r, g, b) end

UIStyle.Palette = {
	Gold   = { light = C(255, 200, 60),  dark = C(240, 150, 25),  outline = C(140, 80, 10) },
	Trade  = { light = C(120, 225, 120), dark = C(40, 170, 70),   outline = C(20, 95, 45) },
	Booth  = { light = C(95, 220, 220),  dark = C(30, 160, 175),  outline = C(15, 90, 105) },
	Season = { light = C(190, 140, 255), dark = C(125, 70, 220),  outline = C(70, 35, 130) },
	-- support accents (additions beyond the core four):
	Red    = { light = C(255, 120, 105), dark = C(220, 60, 55),   outline = C(130, 25, 20) },
	Grey   = { light = C(205, 210, 220), dark = C(145, 152, 166), outline = C(70, 76, 88) },
	Locked = { light = C(120, 126, 140), dark = C(78, 84, 98),    outline = C(42, 46, 56) },
	Cream  = C(255, 248, 235),
	Ink    = C(45, 35, 25),
	White  = C(255, 255, 255),
}
UIStyle.Fonts = { Title = Enum.Font.FredokaOne, Body = Enum.Font.GothamBold }

local P = UIStyle.Palette

-- soft cream gradient used for card bodies
local CARD = { light = P.Cream, dark = C(240, 226, 202) }

-- one active tween per animated instance; a new tween cancels the old one
-- (kv-weak so destroyed rows don't pile up dead entries)
local activeTweens = setmetatable({}, { __mode = "kv" })
local function playTween(target, info, goal)
	local old = activeTweens[target]
	if old then old:Cancel() end
	local tween = TweenService:Create(target, info, goal)
	activeTweens[target] = tween
	tween:Play()
	return tween
end

local function findChild(parent, name, className)
	local child = parent:FindFirstChild(name)
	if child and child:IsA(className) then return child end
	return nil
end

-- accepts an accent table ({light, dark, outline}) or a raw Color3
local function outlineColorOf(accent)
	if typeof(accent) == "Color3" then return accent end
	if type(accent) == "table" and accent.outline then return accent.outline end
	return P.Ink
end

function UIStyle.corner(gui, px)
	local c = findChild(gui, "UIStyleCorner", "UICorner")
	if not c then
		c = Instance.new("UICorner")
		c.Name = "UIStyleCorner"
		c.Parent = gui
	end
	c.CornerRadius = UDim.new(0, px or 12)
	return c
end

function UIStyle.pill(gui)
	local c = UIStyle.corner(gui)
	c.CornerRadius = UDim.new(0.5, 0)
	return c
end

function UIStyle.stroke(gui, accent, thickness)
	local s = findChild(gui, "UIStyleStrokeBorder", "UIStroke")
	if not s then
		s = Instance.new("UIStroke")
		s.Name = "UIStyleStrokeBorder"
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.LineJoinMode = Enum.LineJoinMode.Round
		s.Parent = gui
	end
	s.Color = outlineColorOf(accent)
	s.Thickness = thickness or 3
	s.Transparency = 0
	return s
end

function UIStyle.gradient(gui, accent)
	local g = findChild(gui, "UIStyleGradient", "UIGradient")
	if not g then
		g = Instance.new("UIGradient")
		g.Name = "UIStyleGradient"
		g.Parent = gui
	end
	g.Rotation = 90
	g.Color = ColorSequence.new(accent.light, accent.dark)
	return g
end

-- chunky cartoon text: white + dark Contextual outline. bodyFont = true
-- keeps GothamBold for dense/small text; default is FredokaOne.
function UIStyle.bubbleText(label, accent, bodyFont)
	label.Font = bodyFont and UIStyle.Fonts.Body or UIStyle.Fonts.Title
	label.TextColor3 = P.White
	-- One text outline per label. Contextual mode on a text object strokes the
	-- GLYPHS, so a label that was authored in StarterGui with its own Contextual
	-- stroke -- the cash counter is the one that mattered -- ends up wearing two
	-- once we add ours, at two thicknesses and two colours. That renders as a
	-- single fat lumpy edge rather than as two outlines, so it looks like sloppy
	-- art rather than a bug. Ours is the one that matches the surface, so the
	-- older one is retired (hidden, not destroyed: it may be authored content a
	-- collaborator still looks up by name).
	for _, k in ipairs(label:GetChildren()) do
		if k:IsA("UIStroke")
			and k.Name ~= "UIStyleStrokeText"
			and k.ApplyStrokeMode ~= Enum.ApplyStrokeMode.Border
		then
			k.Transparency = 1
		end
	end
	local s = findChild(label, "UIStyleStrokeText", "UIStroke")
	if not s then
		s = Instance.new("UIStroke")
		s.Name = "UIStyleStrokeText"
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		s.LineJoinMode = Enum.LineJoinMode.Round
		s.Parent = label
	end
	s.Color = outlineColorOf(accent)
	s.Thickness = bodyFont and 2 or 2.5
	s.Transparency = 0
	return s
end

-- 2026-08-05 cross-platform: was `math.clamp(vp.Y / 900, 0.8, 1.25)` inline.
-- Same formula and the same numbers on desktop, but Platform raises the FLOOR
-- on phones and consoles. That floor is the part that mattered: a 414-tall
-- handset landed on 0.8 -- identical furniture size to a 720p monitor -- which
-- put HUD buttons at ~38px, under Roblox's 44px minimum touch target.
local Platform = require(script.Parent:WaitForChild("Platform"))

local function clampedScale()
	return Platform.Height(900, 0.8, 1.25)
end

local function rootScale(panel)
	local sc = findChild(panel, "UIStyleScale", "UIScale")
	if not sc then
		sc = Instance.new("UIScale")
		sc.Name = "UIStyleScale"
		sc.Parent = panel
	end
	return sc
end

function UIStyle.stylePanel(frame, accent)
	frame.BackgroundColor3 = P.White
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	UIStyle.corner(frame, 18)
	UIStyle.gradient(frame, accent)
	UIStyle.stroke(frame, accent, 6)
	local base = clampedScale()
	frame:SetAttribute("UIStyleBaseScale", base)
	rootScale(frame).Scale = base
	return frame
end

function UIStyle.styleHeader(frame, accent, text)
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 8)
	frame.Size = UDim2.new(1, -18, 0, 40)
	frame.BackgroundColor3 = P.White
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	UIStyle.corner(frame, 12)
	-- darker banner (dark -> outline shade) so the white title pops
	local g = findChild(frame, "UIStyleGradient", "UIGradient")
	if not g then
		g = Instance.new("UIGradient")
		g.Name = "UIStyleGradient"
		g.Parent = frame
	end
	g.Rotation = 90
	g.Color = ColorSequence.new(accent.dark, accent.outline)
	UIStyle.stroke(frame, accent, 3)
	if frame:IsA("TextLabel") or frame:IsA("TextButton") then
		if text then frame.Text = text end
		frame.TextSize = 20
		UIStyle.bubbleText(frame, accent)
	end
	return frame
end

-- safe to re-call on the same button for per-state recolor
function UIStyle.styleButton(btn, accent)
	btn.BackgroundColor3 = P.White
	btn.BackgroundTransparency = 0
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	UIStyle.corner(btn, 12)
	UIStyle.gradient(btn, accent)
	UIStyle.stroke(btn, accent, 3)
	if btn:IsA("TextButton") then
		UIStyle.bubbleText(btn, accent)
	end
	wireClick(btn, "uiClick")
	return btn
end

-- row/card: soft cream body + accent outline
function UIStyle.styleCard(frame, accent)
	frame.BackgroundColor3 = P.White
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	UIStyle.corner(frame, 12)
	UIStyle.stroke(frame, accent, 3)
	UIStyle.gradient(frame, CARD)
	return frame
end

-- gold pill treatment for any cash / price / reward amount text
function UIStyle.goldAmount(label)
	label.BackgroundColor3 = P.White
	label.BackgroundTransparency = 0
	label.BorderSizePixel = 0
	UIStyle.pill(label)
	UIStyle.gradient(label, P.Gold)
	UIStyle.stroke(label, P.Gold, 2)
	UIStyle.bubbleText(label, P.Gold, true)
	return label
end

-- Bars are children of btn, so Position/Size stay relative to it for free.
-- ZIndex needs live tracking: this codebase's ScreenGuis often use Global
-- ZIndexBehavior, which compares ZIndex across the WHOLE tree instead of
-- cascading a parent's Z to its children, so a caller that raises btn.ZIndex
-- after styling would otherwise strand the bars at their old Z and let the
-- button's own opaque fill repaint over them. This is its own copy of
-- UITheme's identical helper -- kept local rather than a cross-module
-- require, since making this module depend on UITheme is a bigger call than
-- a bug fix.
local closeXSignals = setmetatable({}, { __mode = "k" })
local function drawCloseX(btn)
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
		bar.BackgroundColor3 = P.White
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

-- red round close button, top-right of its panel
function UIStyle.styleClose(btn)
	btn.AnchorPoint = Vector2.new(1, 0)
	btn.Position = UDim2.new(1, -12, 0, 12)
	btn.Size = UDim2.fromOffset(34, 34)
	btn.Text = ""
	btn.ZIndex = 6
	-- wire the CLOSE voice first: styleButton below would otherwise claim this
	-- button for the generic uiClick via the shared SfxWired guard
	wireClick(btn, "panelClose")
	UIStyle.styleButton(btn, P.Red)
	UIStyle.pill(btn)
	drawCloseX(btn)
	return btn
end

-- hover 1.06 / press 0.92 scale feedback. Wires BOTH hover and press paths
-- (touch fires the mouse-button events; hover alone would strand mobile).
-- Pass enabled = false to only ensure the inert PressScale child exists
-- (disabled/locked buttons: present for consistency, no feedback).
-- Never double-connects: wiring is guarded by an attribute.
function UIStyle.attachHoverPress(btn, enabled)
	local ps = findChild(btn, "PressScale", "UIScale")
	if not ps then
		ps = Instance.new("UIScale")
		ps.Name = "PressScale"
		ps.Parent = btn
	end
	if enabled == false then return ps end
	if btn:GetAttribute("UIStyleHoverWired") then return ps end
	btn:SetAttribute("UIStyleHoverWired", true)
	local hovering = false
	local function to(target, dur)
		playTween(ps, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = target })
	end
	btn.MouseEnter:Connect(function()
		hovering = true
		to(1.06, 0.12)
	end)
	btn.MouseLeave:Connect(function()
		hovering = false
		to(1, 0.12)
	end)
	btn.MouseButton1Down:Connect(function()
		to(0.92, 0.08)
	end)
	btn.MouseButton1Up:Connect(function()
		to(hovering and 1.06 or 1, 0.08)
	end)
	return ps
end

-- pop-open: 0.65 -> full scale, 0.25s Back/Out. Sets Visible = true itself.
function UIStyle.popIn(panelRoot)
	local base = panelRoot:GetAttribute("UIStyleBaseScale") or 1
	local sc = rootScale(panelRoot)
	panelRoot.Visible = true
	pcall(SoundKit.play, "panelOpen", nil, { volume = CLICK_VOLUME })
	sc.Scale = base * 0.65
	playTween(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = base })
end

-- pop-closed: 0.15s Quad/In shrink, THEN hides the panel and calls cb.
-- If a popIn interrupts, the tween is cancelled and Visible stays true.
function UIStyle.popOut(panelRoot, cb)
	pcall(SoundKit.play, "panelClose", nil, { volume = CLICK_VOLUME })
	local base = panelRoot:GetAttribute("UIStyleBaseScale") or 1
	local sc = rootScale(panelRoot)
	local tween = playTween(sc, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = base * 0.65 })
	tween.Completed:Connect(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed then
			panelRoot.Visible = false
			sc.Scale = base
			if cb then cb() end
		end
	end)
end

-- ============================================================================
-- Pet-Sim "clean plate" -- turns `root` into a single raised, SOLID plated
-- clickable: a dark saturated accent RIM (root itself), a fully-opaque
-- low-contrast FACE inset + nudged up, exactly ONE soft top GLOSS, and a
-- centered iconHolder to drop a flat 2D icon into. No 3D, no stacked
-- medallions, no idle motion -- the plate is perfectly still; hover/press
-- juice is the caller's job.
--
-- Idempotent: reuses children by canonical Name, so re-calling it (e.g. to
-- recolor for a ready/locked state) never duplicates layers or strokes.
--   root  = the GuiObject you pass in (ImageButton/Frame) -> rim + input surface
--   Face  = "PlateFace"       solid, clips its own children to the rounded rect
--   Gloss = "PlateGloss"      one white sheen, transparency gradient 0.55 -> 1
--   Icon  = "PlateIconHolder" transparent holder, centered, ~64% of the face
--   Shadow= "PlateShadow"     behind root (skipped when opts.shadow == false)
-- Returns { root, face, gloss, iconHolder, shadow }.
local PLATE_BLACK = C(15, 18, 24)
local function plateEnsure(parent, name, className)
	local c = parent:FindFirstChild(name)
	if not (c and c:IsA(className)) then
		if c then c:Destroy() end
		c = Instance.new(className)
		c.Name = name
		c.Parent = parent
	end
	return c
end
local function plateCorner(gui, scale)
	local c = plateEnsure(gui, "PlateCorner", "UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	return c
end
local function normalizeAccent(accent)
	if type(accent) == "table" and accent.light and accent.dark then
		return { light = accent.light, dark = accent.dark, outline = accent.outline or accent.dark }
	end
	if typeof(accent) == "Color3" then
		return { light = accent, dark = accent:Lerp(PLATE_BLACK, 0.35), outline = accent:Lerp(PLATE_BLACK, 0.6) }
	end
	return P.Grey
end

function UIStyle.plate(root, accent, opts)
	opts = opts or {}
	accent = normalizeAccent(accent)
	local cScale    = opts.corner    or 0.20  -- corner radius as a fraction of the short side
	local glossFrac = opts.gloss     or 0.44  -- gloss covers the top 44% of the face
	local faceIn    = opts.faceInset or 0.86  -- face size as a fraction of the rim
	local faceLift  = opts.faceLift  or 0.03  -- nudge the face up so the bottom rim reads thicker

	-- RIM (the root itself): dark saturated accent + thick round outline stroke.
	root.BackgroundColor3 = accent.dark
	root.BackgroundTransparency = 0
	root.BorderSizePixel = 0
	if root:IsA("GuiButton") then root.AutoButtonColor = false end
	plateCorner(root, cScale)
	UIStyle.stroke(root, accent, opts.strokeThickness or 3)

	-- FACE: solid, low-contrast vertical gradient; clips gloss/icon to its round.
	local face = plateEnsure(root, "PlateFace", "Frame")
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.new(0.5, 0, 0.5 - faceLift, 0)
	face.Size = UDim2.fromScale(faceIn, faceIn)
	face.BackgroundColor3 = accent.light
	face.BackgroundTransparency = 0
	face.BorderSizePixel = 0
	face.ClipsDescendants = true
	face.ZIndex = (root.ZIndex or 1) + 1
	plateCorner(face, cScale)
	local fg = plateEnsure(face, "PlateFaceGradient", "UIGradient")
	fg.Rotation = 90
	fg.Color = ColorSequence.new(accent.light:Lerp(P.White, 0.15), accent.light:Lerp(PLATE_BLACK, 0.12))

	-- GLOSS: one white top sheen fading out downward (never a hard bar).
	local gloss = plateEnsure(face, "PlateGloss", "Frame")
	gloss.AnchorPoint = Vector2.new(0.5, 0)
	gloss.Position = UDim2.fromScale(0.5, 0)
	gloss.Size = UDim2.fromScale(0.92, glossFrac)
	gloss.BackgroundColor3 = P.White
	gloss.BorderSizePixel = 0
	gloss.ZIndex = face.ZIndex + 1
	plateCorner(gloss, cScale)
	local gg = plateEnsure(gloss, "PlateGlossGradient", "UIGradient")
	gg.Rotation = 90
	gg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })

	-- ICON HOLDER: centered transparent slot for a flat 2D icon.
	local iconHolder = plateEnsure(face, "PlateIconHolder", "Frame")
	iconHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	iconHolder.Position = UDim2.fromScale(0.5, 0.5)
	iconHolder.Size = UDim2.fromScale(0.64, 0.64)
	iconHolder.BackgroundTransparency = 1
	iconHolder.ZIndex = gloss.ZIndex + 1

	-- SHADOW behind the rim (one only; skip when the caller supplies its own).
	local shadow
	if opts.shadow ~= false and root.Parent then
		shadow = plateEnsure(root.Parent, "PlateShadow", "Frame")
		shadow.AnchorPoint = root.AnchorPoint
		shadow.Position = root.Position + UDim2.fromOffset(0, opts.shadowDrop or 5)
		shadow.Size = root.Size
		shadow.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
		shadow.BackgroundTransparency = 0.6
		shadow.BorderSizePixel = 0
		shadow.ZIndex = (root.ZIndex or 1) - 1
		plateCorner(shadow, cScale)
	end

	wireClick(root, "uiClick")   -- no-ops when the plate root is a Frame, not a button
	return { root = root, face = face, gloss = gloss, iconHolder = iconHolder, shadow = shadow }
end

--[[ ==========================================================================
STICKER RAIL  (the colourful side-menu look)
---------------------------------------------------------------------------
UIStyle.sticker(btn, opts) turns a TextButton into a "sticker" menu entry:
a white illustration card, a saturated ribbon banner across its foot, and
an optional red "!" alert bubble clipped to the top-right corner.

	opts = {
		accent = UIStyle.Palette.Trade,   -- ribbon colour (table or Color3)
		label  = "shop",                  -- ribbon word; upper-cased for you
		glyph  = "\u{1F6D2}",             -- emoji drawn on the card
		image  = "rbxassetid://123",      -- optional; wins over glyph
		badge  = true,                    -- show the red "!" bubble
	}

Every piece is white-outlined rather than dark-outlined -- that white keyline
against the world is what makes these read as stickers instead of as panels.
The ribbon word keeps a dark Contextual stroke so white-on-yellow still reads.

Idempotent like the rest of this module: re-calling updates the existing
children instead of stacking new ones. Canonical child names:
	StickerCard / StickerIcon / StickerRibbon / StickerBadge
========================================================================== ]]
function UIStyle.sticker(btn, opts)
	opts = opts or {}
	local accent = normalizeAccent(opts.accent or P.Gold)
	local z = btn.ZIndex or 1

	btn.AutoButtonColor = false
	btn.BackgroundTransparency = 1     -- still fully hit-testable
	btn.BorderSizePixel = 0
	btn.ClipsDescendants = false       -- ribbon + badge overhang the button
	btn.Text = ""

	local function ensure(parent, name, class)
		local c = parent:FindFirstChild(name)
		if c and not c:IsA(class) then c:Destroy(); c = nil end
		if not c then
			c = Instance.new(class)
			c.Name = name
			c.Parent = parent
		end
		return c
	end

	-- 1. NO SHADOW. The cards read cleaner sitting flat against the world --
	-- the white keyline alone is enough separation. Cleared here too so a
	-- hot-reload over an older build does not leave an orphan slab behind.
	local staleShadow = btn:FindFirstChild("StickerShadow")
	if staleShadow then staleShadow:Destroy() end

	-- 2. CARD - the white illustration plate
	local card = ensure(btn, "StickerCard", "Frame")
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.fromScale(0.5, 0)
	card.Size = UDim2.new(1, 0, 1, -22)
	card.BackgroundColor3 = P.White
	card.BorderSizePixel = 0
	card.ZIndex = z + 1
	UIStyle.corner(card, 18)
	UIStyle.gradient(card, { light = P.White, dark = C(238, 240, 248) })
	UIStyle.stroke(card, P.White, 3.5)

	-- 3. ICON - emoji by default, ImageLabel when opts.image is given
	local wantImage = opts.image ~= nil
	local old = card:FindFirstChild("StickerIcon")
	if old and ((wantImage and not old:IsA("ImageLabel")) or (not wantImage and not old:IsA("TextLabel"))) then
		old:Destroy()
	end
	local icon = ensure(card, "StickerIcon", wantImage and "ImageLabel" or "TextLabel")
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.44)
	icon.Size = UDim2.fromScale(0.68, 0.68)
	icon.BackgroundTransparency = 1
	icon.ZIndex = z + 2
	if wantImage then
		icon.Image = opts.image
		icon.ScaleType = Enum.ScaleType.Fit
	else
		icon.Text = opts.glyph or "\u{2B50}"
		icon.Font = UIStyle.Fonts.Title
		icon.TextScaled = true
		icon.TextColor3 = P.White
	end

	-- 4. RIBBON - the banner; wider than the card so it reads as a wrap
	local ribbon = ensure(btn, "StickerRibbon", "Frame")
	ribbon.AnchorPoint = Vector2.new(0.5, 1)
	ribbon.Position = UDim2.fromScale(0.5, 1)
	ribbon.Size = UDim2.new(1, 12, 0, 36)
	ribbon.BackgroundColor3 = accent.light
	ribbon.BorderSizePixel = 0
	ribbon.ZIndex = z + 3
	UIStyle.corner(ribbon, 11)
	UIStyle.gradient(ribbon, accent)
	UIStyle.stroke(ribbon, P.White, 3.5)

	local word = ensure(ribbon, "StickerLabel", "TextLabel")
	word.AnchorPoint = Vector2.new(0.5, 0.5)
	word.Position = UDim2.fromScale(0.5, 0.5)
	word.Size = UDim2.new(1, -12, 1, -8)
	word.BackgroundTransparency = 1
	word.ZIndex = z + 4
	word.Text = string.upper(opts.label or btn.Name)
	word.TextScaled = true
	UIStyle.bubbleText(word, accent)
	local wc = word:FindFirstChild("UIStyleTextSize")
	if not wc then
		wc = Instance.new("UITextSizeConstraint")
		wc.Name = "UIStyleTextSize"
		wc.Parent = word
	end
	wc.MaxTextSize = 26

	-- 5. BADGE - red "!" bubble, hangs off the card's top-right corner
	local badge = ensure(btn, "StickerBadge", "Frame")
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.new(1, -4, 0, 4)
	badge.Size = UDim2.fromOffset(30, 30)
	badge.BackgroundColor3 = P.Red.light
	badge.BorderSizePixel = 0
	badge.ZIndex = z + 5
	badge.Visible = opts.badge == true
	UIStyle.pill(badge)
	UIStyle.gradient(badge, P.Red)
	UIStyle.stroke(badge, P.White, 3)

	local bang = ensure(badge, "StickerBang", "TextLabel")
	bang.AnchorPoint = Vector2.new(0.5, 0.5)
	bang.Position = UDim2.fromScale(0.5, 0.46)
	bang.Size = UDim2.fromScale(0.9, 0.8)
	bang.BackgroundTransparency = 1
	bang.ZIndex = z + 6
	bang.Text = "!"
	bang.TextScaled = true
	UIStyle.bubbleText(bang, P.Red)

	UIStyle.attachHoverPress(btn)
	wireClick(btn, "uiClick")
	return { card = card, icon = icon, ribbon = ribbon, label = word, badge = badge }
end

-- Show/hide the red "!" on a button already passed through UIStyle.sticker.
function UIStyle.stickerBadge(btn, on)
	local badge = btn:FindFirstChild("StickerBadge")
	if badge then badge.Visible = on and true or false end
end

return UIStyle
