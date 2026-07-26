-- SideRail: Pet-Sim-style left button rail of FREE-FLOATING bubbly glyph icons.
-- 2026-07-25 (user call: "just the icon itself"): the plate/box era is over --
-- no tile face, no sunburst, no rims, no square shadow. MakeTile builds a big
-- outlined glyph with its own soft drop shadow and returns the same handle
-- contract as before (button / setReady / setBadge), so no caller changes.
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

-- ===== tile factory =====
function SideRail.MakeTile(cfg)
	local rail = getRail()
	local TILE = 64

	local slot = Instance.new("Frame")
	slot.Name = (cfg.name or "Rail") .. "Slot"
	slot.BackgroundTransparency = 1
	slot.Size = UDim2.fromOffset(TILE, TILE)
	slot.LayoutOrder = cfg.layoutOrder or 1
	slot.ClipsDescendants = false
	slot.Parent = rail

	-- The input surface is an invisible square (comfortable hit target); the
	-- ICON is the whole visual. ClipsDescendants stays off so the oversized
	-- glyph and its shadow can breathe past the slot.
	local tile = Instance.new("ImageButton")
	tile.Name = "Tile"
	tile.AnchorPoint = Vector2.new(0.5, 0.5)
	tile.Position = UDim2.fromScale(0.5, 0.5)
	tile.Size = UDim2.fromOffset(TILE, TILE)
	tile.BackgroundTransparency = 1
	tile.AutoButtonColor = false
	tile.ClipsDescendants = false
	tile.ZIndex = 2
	tile.Parent = slot
	local uiscale = Instance.new("UIScale"); uiscale.Parent = tile

	local GLYPH = { gift = "\u{1F381}", target = "\u{1F3AF}", star = "\u{2B50}", book = "\u{1F4D6}", trophy = "\u{1F3C6}", pack = "\u{1F392}", wheel = "\u{1F3A1}" }
	local glyphChar = GLYPH[cfg.iconKind] or "\u{2B50}"

	-- setReady's claim cue, built first so it sits UNDER everything: a soft gold
	-- halo behind the glyph. A glow is a cue, not a box -- the box era is over.
	local readyGlow = Instance.new("Frame")
	readyGlow.Name = "ReadyGlow"
	readyGlow.AnchorPoint = Vector2.new(0.5, 0.5)
	readyGlow.Position = UDim2.fromScale(0.5, 0.5)
	readyGlow.Size = UDim2.fromScale(1.25, 1.25)
	readyGlow.BackgroundColor3 = UIStyle.Palette.Gold.light
	readyGlow.BackgroundTransparency = 0.35
	readyGlow.Visible = false
	readyGlow.ZIndex = 2
	readyGlow.Parent = tile
	Instance.new("UICorner", readyGlow).CornerRadius = UDim.new(1, 0)

	-- Soft drop shadow: the SAME glyph, ink-dark and translucent, offset down.
	-- This is what keeps a free-floating icon from looking pasted on the world.
	local iconShadow = Instance.new("TextLabel")
	iconShadow.Name = "IconShadow"
	iconShadow.BackgroundTransparency = 1
	iconShadow.AnchorPoint = Vector2.new(0.5, 0.5)
	iconShadow.Position = UDim2.new(0.5, 0, 0.5, 5)
	iconShadow.Size = UDim2.fromScale(1.16, 1.16)
	iconShadow.TextScaled = true
	iconShadow.Text = glyphChar
	iconShadow.TextColor3 = CF.ink
	iconShadow.TextTransparency = 0.55
	iconShadow.ZIndex = 3
	iconShadow.Parent = tile

	-- The bubbly icon itself: an oversized emoji glyph with the heavy black
	-- contextual outline the rest of the campfire UI wears. Emoji stay the
	-- sanctioned icon source (catalog decals resolved blank/moderated).
	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(1.16, 1.16)
	icon.TextScaled = true
	icon.Text = glyphChar
	icon.ZIndex = 4
	icon.Parent = tile
	UIStyle.bubbleText(icon, OUTLINE).Thickness = 4

	-- badge (top-right)
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, 5, 0, -5)
	badge.Size = UDim2.fromOffset(22, 22)
	badge.BackgroundColor3 = BADGE_RED
	badge.Visible = false
	badge.ZIndex = 7
	badge.Parent = tile
	Instance.new("UICorner", badge).CornerRadius = UDim.new(1, 0)
	-- campfire badges get the same black rim as every other shape (was white)
	local bstroke = Instance.new("UIStroke"); bstroke.Thickness = 2.5; bstroke.Color = CF.ink; bstroke.Parent = badge
	local blabel = Instance.new("TextLabel")
	blabel.BackgroundTransparency = 1; blabel.Size = UDim2.fromScale(1, 1)
	blabel.Font = Enum.Font.GothamBlack; blabel.TextColor3 = WHITE; blabel.TextScaled = true
	blabel.Text = "!"; blabel.ZIndex = 8; blabel.Parent = badge
	-- Round 2: white badge text gets the mandatory contextual outline (bubbleText)
	UIStyle.bubbleText(blabel, OUTLINE, true)
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
	-- Static, idempotent claim cue for the plateless icon: the gold halo behind
	-- the glyph switches on. No animation -- an untouched rail stays pixel-still.
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
function SideRail.registerPanel(frame)
	if not frame or railPanels[frame] then return frame end
	railPanels[frame] = true
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not frame.Visible then return end
		for other in pairs(railPanels) do
			if other ~= frame and other.Parent and other.Visible then
				other.Visible = false
			end
		end
	end)
	return frame
end

return SideRail
