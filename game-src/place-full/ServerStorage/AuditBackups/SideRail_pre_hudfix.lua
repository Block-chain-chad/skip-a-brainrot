-- SideRail: the left button rail -- sticker cards, matching the reference art.
--
-- HISTORY, because this has flipped once already:
--   2026-07-25  "just the icon itself" -- plates removed, icons left free-floating
--               as 3D IconForge renders behind a heavy ink outline.
--   2026-07-26  reference image reverses it. Each slot is a sticker again: white
--               card + coloured ribbon banner + corner badge, no drop shadow, and
--               a flat emoji glyph instead of the 3D render. Built to match
--               UIStyle.sticker exactly so this rail and the nav rail on the
--               right read as ONE art style.
--
-- The handle contract has never changed across any of it:
--   { button, setReady(on), setBadge(kind, n) }   -- so no caller edits, ever.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer

-- Round 2: reuse the SAME shared theme module the Trade/Booth/Season surfaces use.
local UIStyle = require(script.Parent.UIStyle)
local PAL = UIStyle.Palette

-- Campfire palette (UITheme.Camp) supplies the ink for glyph outlines, shadows
-- and badge rims -- the only framing a free-floating icon still has.
local UITheme = require(script.Parent.UITheme)
local CF = UITheme.Camp

local OUTLINE = CF.ink   -- warm campfire black (was a cool navy) behind every glyph
local WHITE = Color3.fromRGB(255, 255, 255)
local BADGE_RED = Color3.fromRGB(235, 64, 52)
local BADGE_GOLD = Color3.fromRGB(255, 194, 26)

-- (per-tile accent plumbing removed with the plates: callers still pass
-- hueTop/hueBottom harmlessly, but a free-floating glyph has no face to tint --
-- the emoji brings its own colour)

local SideRail = {}

-- ===== idle motion: REMOVED =====
-- The old sway rocked each 3D icon +/-14 degrees every Heartbeat via math.sin
-- -- that was the "shaky" tell the user called out. Icons are flat 2D now and
-- sit perfectly still; ALL motion is hover/press only. No idle driver remains.
-- (idle-sway Heartbeat driver + `spinning` registry deleted -- icons are static)

-- ===== floating rail singleton =====
local railFrame
local function getRail()
	if railFrame and railFrame.Parent then return railFrame end
	local pg = player:WaitForChild("PlayerGui")
	local sg = pg:FindFirstChild("SideRailUI")
	if not sg then
		sg = Instance.new("ScreenGui")
		sg.Name = "SideRailUI"
		sg.ResetOnSpawn = false
		sg.DisplayOrder = 6
		pcall(function() sg.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets end)
		sg.Parent = pg
	end
	railFrame = sg:FindFirstChild("LeftRail")
	if not railFrame then
		railFrame = Instance.new("Frame")
		railFrame.Name = "LeftRail"
		railFrame.BackgroundTransparency = 1
		railFrame.AnchorPoint = Vector2.new(0, 0.5)
		railFrame.Position = UDim2.new(0, 18, 0.42, 0)
		railFrame.Size = UDim2.fromOffset(76, 10)
		railFrame.AutomaticSize = Enum.AutomaticSize.Y
		railFrame.Parent = sg
		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Vertical
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Padding = UDim.new(0, 12)
		list.Parent = railFrame
		local scale = Instance.new("UIScale")
		scale.Parent = railFrame
		local cam = workspace.CurrentCamera
		local function upd() if cam then scale.Scale = math.clamp(cam.ViewportSize.Y / 900, 0.8, 1.25) end end
		upd()
		if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(upd) end
	end
	return railFrame
end

-- (3D icon builders removed -- rail icons are flat 2D glyphs now)

-- ===== vector icons =====
-- Escape hatch for slots the emoji set serves badly. The system emoji font
-- draws U+1F381 as an orange lump that does not read as a present at rail size,
-- and no other codepoint is a gift, so Daily is drawn from flat shapes instead.
-- Same visual language as the emoji (flat, saturated, no outline) -- just built
-- rather than typed. A slot with a builder here uses it; everything else falls
-- through to glyphFor().
local VECTOR_ICONS = {}

function VECTOR_ICONS.Daily(parent, z)
	local BOX_LIGHT = Color3.fromRGB(255, 86, 96)
	local BOX_DARK  = Color3.fromRGB(214, 38, 62)
	local GOLD      = Color3.fromRGB(255, 202, 64)

	local function piece(name, colour, anchor, pos, size, zi, radiusScale)
		local f = Instance.new("Frame")
		f.Name = name
		f.AnchorPoint = anchor
		f.Position = pos
		f.Size = size
		f.BackgroundColor3 = colour
		f.BorderSizePixel = 0
		f.ZIndex = zi
		f.Parent = parent
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(radiusScale or 0.12, 0)
		c.Parent = f
		return f
	end

	-- bows first so the lid overlaps their base
	piece("BowL", GOLD, Vector2.new(1, 1), UDim2.fromScale(0.54, 0.28), UDim2.fromScale(0.34, 0.26), z, 1)
	piece("BowR", GOLD, Vector2.new(0, 1), UDim2.fromScale(0.46, 0.28), UDim2.fromScale(0.34, 0.26), z, 1)
	-- body, then the lid sitting proud of it
	piece("Box", BOX_DARK,  Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.46), UDim2.fromScale(0.84, 0.48), z + 1, 0.10)
	piece("Lid", BOX_LIGHT, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.26), UDim2.fromScale(1.00, 0.22), z + 2, 0.20)
	-- ribbon runs over lid and body, knot covers where the bows meet
	piece("RibbonV", GOLD, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.26), UDim2.fromScale(0.17, 0.68), z + 3, 0.30)
	piece("Knot",    GOLD, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.28), UDim2.fromScale(0.22, 0.22), z + 4, 1)
end

-- ===== icon glyphs =====
-- Keyed by slot NAME rather than iconKind: the kinds were named after the old
-- 3D primitives ("bag", "star") and several described the feature poorly.
-- Backpack in particular rendered as a lidded bin and read as a bin, which is
-- what prompted this pass.
--
-- Deliberately no duplicates: Skip on the right rail already owns the dartboard,
-- so Goals takes a clipboard rather than a second target.
local NAME_GLYPHS = {
	Daily    = "\u{1F381}",   -- wrapped gift
	Goals    = "\u{1F4CB}",   -- clipboard
	Backpack = "\u{1F392}",   -- school satchel: the clearest backpack in the set
	Rebirth  = "\u{2B50}",    -- star
	Index    = "\u{1F4D6}",   -- open book
	Season   = "\u{1F3C6}",   -- trophy
}
-- fallback for any future slot that has no name mapping
local KIND_GLYPHS = {
	gift = "\u{1F381}", target = "\u{1F3AF}", star = "\u{2B50}",
	book = "\u{1F4D6}", trophy = "\u{1F3C6}", bag = "\u{1F392}",
}
local function glyphFor(cfg)
	return cfg.glyph
		or NAME_GLYPHS[cfg.name or ""]
		or KIND_GLYPHS[cfg.iconKind or ""]
		or "\u{2B50}"
end

-- ===== tile factory =====
-- 2026-07-26: the plate is BACK, by user reference image. The previous pass
-- stripped tiles down to a free-floating glyph ("just the icon itself"); the
-- new reference is explicitly the opposite -- a white illustration card with a
-- bold coloured ribbon banner under it, red alert bubble on the corner. That
-- sticker shape is now the whole UI's language (see UIStyle.sticker).
--
-- Callers are UNCHANGED: every one of them already passed name / hueTop /
-- hueBottom, which previously went nowhere ("a free-floating glyph has no face
-- to tint"). Those now drive the ribbon label and its gradient, so the six
-- existing rail buttons pick up the new look without a single call-site edit.
--
-- Handle contract is also unchanged: { button, setReady, setBadge }.
function SideRail.MakeTile(cfg)
	local rail = getRail()
	local W, CARD_H, RIBBON_H, OVERLAP = 72, 64, 26, 9

	local accentDark = cfg.hueBottom or PAL.Gold.dark
	local accent = {
		light   = cfg.hueTop or PAL.Gold.light,
		dark    = accentDark,
		outline = accentDark:Lerp(Color3.fromRGB(0, 0, 0), 0.55),
	}

	local slot = Instance.new("Frame")
	slot.Name = (cfg.name or "Rail") .. "Slot"
	slot.BackgroundTransparency = 1
	slot.Size = UDim2.fromOffset(W, CARD_H + RIBBON_H - OVERLAP)
	slot.LayoutOrder = cfg.layoutOrder or 1
	slot.ClipsDescendants = false
	slot.Parent = rail

	-- invisible hit surface covering card + ribbon
	local tile = Instance.new("ImageButton")
	tile.Name = "Tile"
	tile.AnchorPoint = Vector2.new(0.5, 0.5)
	tile.Position = UDim2.fromScale(0.5, 0.5)
	tile.Size = UDim2.fromScale(1, 1)
	tile.BackgroundTransparency = 1
	tile.AutoButtonColor = false
	tile.ClipsDescendants = false
	tile.ZIndex = 2
	tile.Parent = slot
	local uiscale = Instance.new("UIScale"); uiscale.Parent = tile

	-- 1. (no drop shadow -- cards sit flat; the white keyline does the work)

	-- 2. white illustration card
	local card = Instance.new("Frame")
	card.Name = "StickerCard"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 0)
	card.Size = UDim2.fromOffset(W - 6, CARD_H)
	card.BackgroundColor3 = WHITE
	card.BorderSizePixel = 0
	card.ClipsDescendants = false
	card.ZIndex = 3
	card.Parent = tile
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 16)
	UIStyle.gradient(card, { light = WHITE, dark = Color3.fromRGB(238, 240, 248) })
	UIStyle.stroke(card, WHITE, 3.5)

	-- 3. claim cue: soft gold halo, behind the icon, inside the card
	local readyGlow = Instance.new("Frame")
	readyGlow.Name = "ReadyGlow"
	readyGlow.AnchorPoint = Vector2.new(0.5, 0.5)
	readyGlow.Position = UDim2.fromScale(0.5, 0.5)
	readyGlow.Size = UDim2.fromScale(0.92, 0.92)
	readyGlow.BackgroundColor3 = PAL.Gold.light
	readyGlow.BackgroundTransparency = 0.35
	readyGlow.BorderSizePixel = 0
	readyGlow.Visible = false
	readyGlow.ZIndex = 4
	readyGlow.Parent = card
	Instance.new("UICorner", readyGlow).CornerRadius = UDim.new(1, 0)

	-- 4. the glyph -- a flat emoji, built EXACTLY like UIStyle.sticker builds
	-- the nav cards on the right, so the two rails read as one art style.
	--
	-- This replaces IconForge, which rendered 3D primitives into stacked
	-- ViewportFrames behind a heavy ink silhouette. That technique was built for
	-- free-floating icons against the world; sitting on a white card it made the
	-- left rail look darker and blockier than the right one.
	local icon = Instance.new("Frame")
	icon.Name = "StickerIcon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.44)
	icon.Size = UDim2.fromScale(0.68, 0.68)
	icon.BackgroundTransparency = 1
	icon.ZIndex = 5
	icon.Parent = card
	-- keep it square whatever the card does, so a drawn icon never skews
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.Parent = icon

	local drawn = VECTOR_ICONS[cfg.name or ""]
	if drawn then
		drawn(icon, 5)
	else
		local glyph = Instance.new("TextLabel")
		glyph.Name = "Glyph"
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.BackgroundTransparency = 1
		glyph.ZIndex = 5
		glyph.Font = UIStyle.Fonts.Title
		glyph.TextScaled = true
		glyph.TextColor3 = WHITE      -- emoji carry their own colour; this is only a fallback
		glyph.Text = glyphFor(cfg)
		glyph.Parent = icon
		-- emoji must not be re-coloured or outlined by the game-wide UIPolish sweep
		glyph:SetAttribute("NoPolish", true)
	end

	-- 5. ribbon banner -- wider than the card, overlapping its foot
	local ribbon = Instance.new("Frame")
	ribbon.Name = "StickerRibbon"
	ribbon.AnchorPoint = Vector2.new(0.5, 1)
	ribbon.Position = UDim2.fromScale(0.5, 1)
	ribbon.Size = UDim2.fromOffset(W, RIBBON_H)
	ribbon.BackgroundColor3 = accent.light
	ribbon.BorderSizePixel = 0
	ribbon.ZIndex = 9
	ribbon.Parent = tile
	Instance.new("UICorner", ribbon).CornerRadius = UDim.new(0, 9)
	UIStyle.gradient(ribbon, accent)
	UIStyle.stroke(ribbon, WHITE, 3)

	local word = Instance.new("TextLabel")
	word.Name = "StickerLabel"
	word.AnchorPoint = Vector2.new(0.5, 0.5)
	word.Position = UDim2.fromScale(0.5, 0.5)
	word.Size = UDim2.new(1, -8, 1, -6)
	word.BackgroundTransparency = 1
	word.Text = string.upper(cfg.label or cfg.name or "")
	word.TextScaled = true
	word.ZIndex = 10
	word.Parent = ribbon
	UIStyle.bubbleText(word, accent)
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 17
	cap.Parent = word

	-- 6. badge (top-right of the card)
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, 4, 0, -4)
	badge.Size = UDim2.fromOffset(22, 22)
	badge.BackgroundColor3 = BADGE_RED
	badge.BorderSizePixel = 0
	badge.Visible = false
	badge.ZIndex = 11
	badge.Parent = card
	Instance.new("UICorner", badge).CornerRadius = UDim.new(1, 0)
	-- white rim, matching the sticker keyline (was campfire ink)
	local bstroke = Instance.new("UIStroke")
	bstroke.Thickness = 2.5; bstroke.Color = WHITE; bstroke.Parent = badge
	local blabel = Instance.new("TextLabel")
	blabel.BackgroundTransparency = 1; blabel.Size = UDim2.fromScale(1, 1)
	blabel.Font = UIStyle.Fonts.Title; blabel.TextColor3 = WHITE; blabel.TextScaled = true
	blabel.Text = "!"; blabel.ZIndex = 12; blabel.Parent = badge
	UIStyle.bubbleText(blabel, OUTLINE)
	local bpad = Instance.new("UIPadding")
	bpad.PaddingTop = UDim.new(0, 3); bpad.PaddingBottom = UDim.new(0, 3)
	bpad.PaddingLeft = UDim.new(0, 3); bpad.PaddingRight = UDim.new(0, 3); bpad.Parent = blabel
	local bscale = Instance.new("UIScale"); bscale.Parent = badge

	-- ===== interaction juice =====
	local cur
	local function to(s, t, style, dir)
		if cur then cur:Cancel() end
		cur = TweenService:Create(uiscale, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), { Scale = s })
		cur:Play()
	end
	tile.MouseEnter:Connect(function() to(1.08, 0.12) end)
	tile.MouseLeave:Connect(function() to(1.0, 0.22, Enum.EasingStyle.Back) end)
	tile.MouseButton1Down:Connect(function() to(0.9, 0.08) end)
	tile.MouseButton1Up:Connect(function() to(1.08, 0.22, Enum.EasingStyle.Back) end)

	-- ===== handle =====
	local handle = { button = tile }
	function handle.setReady(on)
		readyGlow.Visible = on == true
	end
	function handle.setBadge(kind, n)
		if not kind or kind == "none" then badge.Visible = false; return end
		local wasVisible = badge.Visible
		badge.Visible = true
		if kind == "dot" then
			blabel.Text = ""; badge.Size = UDim2.fromOffset(15, 15); badge.BackgroundColor3 = BADGE_RED
		elseif kind == "count" then
			blabel.Text = (n and n > 99) and "99+" or tostring(n or 0); badge.Size = UDim2.fromOffset(22, 22); badge.BackgroundColor3 = BADGE_RED
		elseif kind == "alert" then
			blabel.Text = "!"; badge.Size = UDim2.fromOffset(22, 22); badge.BackgroundColor3 = BADGE_GOLD
		end
		if not wasVisible then
			bscale.Scale = 0
			TweenService:Create(bscale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end
	return handle
end

-- ===== single-open coordination =====
-- Rail panels registered here close one another, so only ONE is open at a time.
-- We watch each panel's Visible; when one turns on, the rest turn off. Works no
-- matter how a client toggles it (a raw Visible flag, or UIStyle.popIn which also
-- sets Visible). Hiding the others via Visible=false is enough for every panel.
local railPanels = {}

-- The rail sits at DisplayOrder 6, above every panel, and its cards are wide
-- enough to cover a panel's left-hand column (the Index grid lost a whole
-- column of tiles behind it). Rather than pad every panel, the rail simply
-- gets out of the way: it hides while any registered panel is open and comes
-- back when the last one closes.
local function updateRailVisibility()
	if not (railFrame and railFrame.Parent) then return end
	local anyOpen = false
	for panel in pairs(railPanels) do
		if panel.Parent and panel.Visible then anyOpen = true break end
	end
	railFrame.Visible = not anyOpen
end

function SideRail.registerPanel(frame)
	if not frame or railPanels[frame] then return frame end
	railPanels[frame] = true
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible then
			for other in pairs(railPanels) do
				if other ~= frame and other.Parent and other.Visible then
					other.Visible = false
				end
			end
		end
		updateRailVisibility()
	end)
	updateRailVisibility()
	return frame
end

return SideRail
