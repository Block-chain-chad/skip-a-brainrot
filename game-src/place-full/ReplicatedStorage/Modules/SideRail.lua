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
	-- OFF-SCREEN MUST NOT ANIMATE, whoever hid it. GameHUDClient hides this
	-- frame directly rather than going through updateRailVisibility, so hooking
	-- only our own path missed that case entirely (verified: the suspend never
	-- fired while the rail was folded). Watching the frame's own Visible, plus
	-- the ScreenGui's Enabled, catches every hider including future ones.
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
-- ===================== CLAIM PULSE ARBITRATION =====================
-- Every rail client calls setReady on its own tile with no knowledge of the
-- others, so four could breathe at once. Six pulsing buttons reads as noise
-- rather than as a reward, so the decision is made HERE, centrally, where the
-- full set is visible -- no call site changes.
--
-- <= PULSE_MAX claimable: they all pulse.
-- >  PULSE_MAX: only the highest-priority one pulses. The rest keep a STATIC
--    glow, so nothing stops advertising that it is claimable -- it just stops
--    competing for attention.
-- ONE shared driver for every claim pulse, matching the convention
-- UIKit.Builders already uses for its rainbow ring ("ONE Heartbeat total, a
-- registry pruned when the instance is gone") rather than a loop per element.
--
-- Why not a tween, given the round asked for tweens: measured in this place, a
-- TweenService tween on BackgroundTransparency does not run -- the property sits
-- at whatever it was last set to. Frame.Size tweens fine (it drives the quest
-- bar), so this is property-specific, not a broken TweenService. UIScale.Scale,
-- NumberValue.Value and Sound.Volume behave the same way. One registry-driven
-- Heartbeat for the whole rail keeps the cost bounded and, critically, still
-- lets every pulse be stopped dead when the rail folds away.
local RunService = game:GetService("RunService")
local pulseSet, pulseConn = {}, nil

-- Effective visibility: every GuiObject ancestor Visible, and the ScreenGui
-- Enabled. A hidden ANCESTOR is what folding the rail actually does.
local function isShown(inst)
	local node = inst
	while node and node ~= game do
		if node:IsA("GuiObject") and not node.Visible then return false end
		if node:IsA("ScreenGui") then return node.Enabled end
		node = node.Parent
	end
	return true
end

local function ensurePulseDriver()
	if pulseConn then return end
	pulseConn = RunService.Heartbeat:Connect(function()
		local t = os.clock()
		local live = false
		for glow, spec in pairs(pulseSet) do
			if not glow.Parent then
				pulseSet[glow] = nil                 -- gone for good
			else
				live = true
				-- OFF-SCREEN DOES NO WORK. Visibility is decided HERE, per frame,
				-- rather than by hooking whoever hides the rail: GameHUDClient
				-- hides LeftRail directly while SideRail hides it too, and
				-- hooking both made them fight and flip-flop (observed live --
				-- the pulse was cleared several times a second and never showed).
				-- Asking the instance is self-correcting and cannot disagree.
				if glow.Visible and glow:IsDescendantOf(game) and isShown(glow) then
					local a = (math.sin(t * (2 * math.pi / spec.period)) + 1) * 0.5
					glow.BackgroundTransparency = spec.rest + (spec.peak - spec.rest) * a
				elseif glow.BackgroundTransparency ~= spec.rest then
					glow.BackgroundTransparency = spec.rest   -- park it, once
				end
			end
		end
		if not live then
			pulseConn:Disconnect()
			pulseConn = nil
		end
	end)
end

local PULSE_MAX = 3
local CLAIM_PRIORITY = { Daily = 1, Season = 2, Goals = 3, Rebirth = 4 }
local readyTiles = {}   -- [tileName] = { setPulse = fn, ready = bool, legacyGlow = Frame }

-- U3 port: GameHUDClient hides LeftRail permanently, so a claim cue painted on
-- these tiles animates something the player never sees. The visible nav rail
-- attaches a per-button halo here; from then on every claim paint for that
-- tile name lands on the halo instead. Reporters are untouched -- the handle
-- contract does not change.
local REST_ALPHA, PULSE_ALPHA, PULSE_PERIOD = 0.35, 0.62, 1.1
local claimSurfaces = {}   -- [tileName] = GuiObject on the visible rail
local badgeSurfaces = {}   -- [tileName] = fn(kind, n) painting the visible badge

local function arbitrateClaims()
	local ready = {}
	for name, entry in pairs(readyTiles) do
		if entry.ready then ready[#ready + 1] = name end
	end
	table.sort(ready, function(a, b)
		return (CLAIM_PRIORITY[a] or 99) < (CLAIM_PRIORITY[b] or 99)
	end)
	local onlyTop = #ready > PULSE_MAX
	for i, name in ipairs(ready) do
		readyTiles[name].setPulse(not onlyTop or i == 1)
	end
end

-- The visible rail calls this once per button it wants claim cues on. Safe in
-- any order relative to MakeTile: attaching re-applies the tile's current
-- ready state to the new surface, and a tile made later routes to the surface
-- through claimTarget() on its next paint.
function SideRail.attachClaimSurface(name, glow)
	claimSurfaces[name] = glow
	local entry = readyTiles[name]
	if entry then
		-- the legacy glow may still be registered with the pulse driver; retire it
		if entry.legacyGlow then
			pulseSet[entry.legacyGlow] = nil
		end
		glow.Visible = entry.ready == true
		glow.BackgroundTransparency = REST_ALPHA
		arbitrateClaims()
	else
		glow.Visible = false
	end
end

-- Badge twin of attachClaimSurface: the visible rail hands us a paint
-- function (kind, n), and every handle.setBadge for that tile name routes
-- there instead of the hidden tile's own bubble. The last badge is replayed
-- on attach, so a reporter that painted before the HUD rail finished
-- building loses nothing.
function SideRail.attachBadgeSurface(name, paint)
	badgeSurfaces[name] = paint
	local entry = readyTiles[name]
	if entry and entry.lastBadgeKind then
		paint(entry.lastBadgeKind, entry.lastBadgeN)
	end
end

-- Called when the rail folds away behind an open panel. Off-screen elements
-- must not keep animating, and the loops are CANCELLED rather than hidden --
-- a paused-but-live tween is exactly the orphan this is meant to avoid.



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
	-- alive pass #1: the claim halo pops in once, then BREATHES until cleared.
	-- 1.6 is UIKit.Tokens' T.tween.pulsePeriod (SideRail deliberately imports no
	-- Tokens); the loop mirrors UIKit.Builders.claimRing exactly.
	-- APPEARS BY FADE, not by pop. The old pop tweened a UIScale, and a
	-- TweenService tween on UIScale.Scale does not run in this place (probed
	-- live: the scale sits at whatever it was set to). A transparency fade is
	-- both what the spec asks for and a GuiObject property, which does tween.
	local key = cfg.name or tostring(slot)
	-- claim paints land on the visible rail's halo once one is attached for
	-- this name (see attachClaimSurface); until then, the legacy readyGlow.
	local function claimTarget()
		return claimSurfaces[key] or readyGlow
	end
	local function setPulse(on)
		local glow = claimTarget()
		if on then
			pulseSet[glow] = { rest = REST_ALPHA, peak = PULSE_ALPHA, period = PULSE_PERIOD }
			ensurePulseDriver()
		else
			pulseSet[glow] = nil                       -- deregistered, not merely paused
			if glow.Visible then
				glow.BackgroundTransparency = REST_ALPHA  -- static, still claimable
			end
		end
	end
	readyTiles[key] = { setPulse = setPulse, ready = false, legacyGlow = readyGlow }

	function handle.setReady(on)
		local entry = readyTiles[key]
		local glow = claimTarget()
		if on == true then
			if not glow.Visible then
				glow.Visible = true
				glow.BackgroundTransparency = REST_ALPHA   -- appears at rest, no pop
			end
			if entry then entry.ready = true end
		else
			setPulse(false)
			glow.BackgroundTransparency = REST_ALPHA
			glow.Visible = false
			if entry then entry.ready = false end
		end
		arbitrateClaims()
	end
	-- alive pass #5: a visible badge whose text CHANGES re-pops (1.25 -> 1);
	-- rapid updates retarget by cancelling the previous tween, never stacking.
	local badgeTween = nil
	function handle.setBadge(kind, n)
		kind = kind or "none"
		-- memo + route: once the visible rail attaches a badge surface it owns
		-- this tile's badge paint; the memo makes a late attach lossless
		local entry = readyTiles[key]
		if entry then entry.lastBadgeKind, entry.lastBadgeN = kind, n end
		local paint = badgeSurfaces[key]
		if paint then paint(kind, n); return end
		if kind == "none" then badge.Visible = false; return end
		local wasVisible = badge.Visible
		local oldText = blabel.Text
		badge.Visible = true
		if kind == "dot" then
			blabel.Text = ""; badge.Size = UDim2.fromOffset(15, 15); badge.BackgroundColor3 = BADGE_RED
		elseif kind == "count" then
			blabel.Text = (n and n > 99) and "99+" or tostring(n or 0); badge.Size = UDim2.fromOffset(22, 22); badge.BackgroundColor3 = BADGE_RED
		elseif kind == "alert" then
			blabel.Text = "!"; badge.Size = UDim2.fromOffset(22, 22); badge.BackgroundColor3 = BADGE_GOLD
		end
		if not wasVisible then
			if badgeTween then badgeTween:Cancel() end
			bscale.Scale = 0
			badgeTween = TweenService:Create(bscale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			badgeTween:Play()
		elseif blabel.Text ~= oldText then
			if badgeTween then badgeTween:Cancel() end
			bscale.Scale = 1.25
			badgeTween = TweenService:Create(bscale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			badgeTween:Play()
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
	-- the quest tracker hugs the right edge and overlaps open panels the same
	-- way the rail does, so it folds away with the rail and returns with it
	local pg = player:FindFirstChild("PlayerGui")
	local qt = pg and pg:FindFirstChild("QuestTrackerUI")
	if qt then qt.Enabled = not anyOpen end
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
