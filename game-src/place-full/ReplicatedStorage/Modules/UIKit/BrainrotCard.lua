--!strict
-- BrainrotCard -- the ONE collectible card (spec 2026-09-18 UI foundation §7).
-- Style C "dark well tile": RARITY is the card's identity (edge, band, pips, foil,
-- aura, holo ring and sparkles escalate by tier, from S.Card.Ladder); equipped /
-- locked / new / mutation / size are small corner badges that never recolour the
-- plate, edge, band or aura (decision 5).
--
-- Data in, instances out. This module never reads BrainrotConfig, RarityConfig,
-- remotes or save fields: the panel maps its entries -- and normalises its legacy
-- "Fav" flag to `locked` -- before calling new(). The lock control is a padlock
-- toggle; a favourite system, if ever added, is a separate state.
--
-- Structure (§7.2):
--   CellRoot   (transparent; owned by the consumer's UIGridLayout; never animated)
--   └─ VisualRoot (hover/press tween its Position; everything visible hangs off it)
--      ├─ Shadow, SelectionRing            (OUTSIDE the clipped plate)
--      └─ Plate (ClipsDescendants)         → Aura, Foil, ArtWell, ContactShadow,
--                                             ArtHolder (viewport mounts here), HoloRing,
--                                             Pips, Band, Rate, Sparkles,
--                                             BadgesRight, BadgesLeft, Hit
-- Animation only through FxDriver: registered on mount(), released on unmount(),
-- at most S.Card.MaxAnimatedLayers layers per card (the ladder names them).
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local S = require(script.Parent.SpecTheme)
local PC = require(script.Parent.PanelChrome)
local FxDriver = require(script.Parent.FxDriver)
local modules = ReplicatedStorage:WaitForChild("Modules")
local BrainrotThumb = require(modules:WaitForChild("BrainrotThumb"))
local NumberFormat = require(modules:WaitForChild("NumberFormat"))
local Platform = require(modules:WaitForChild("Platform"))

export type State = { equipped: (boolean | number)?, locked: boolean?, selected: boolean?, new: boolean? }
export type Props = {
	kind: string?, name: string, model: string?, rarity: string, income: number?,
	mutation: string?, mutationColor: Color3?, sizeTag: string?, count: number?,
	state: State?, lock: { onToggle: (nextLocked: boolean) -> () }?,
	title: string?, variant: string?,
	parent: Instance?, zIndex: number?, layoutOrder: number?, instanceName: string?,
}
export type Card = {
	root: Frame, visual: Frame, plate: Frame, art: Frame, data: Props,
	set: (patch: { [string]: any }) -> (), setState: (patch: State) -> (),
	mount: () -> (), unmount: () -> (), isMounted: () -> boolean, destroy: () -> (),
	Activated: RBXScriptSignal, HoverStart: RBXScriptSignal, HoverEnd: RBXScriptSignal,
}

local BrainrotCard = {}

local UNLIT_PIP = Color3.fromHex("39414F")
local RAINBOW_INK = Color3.fromHex("12060C")
local NEW_RED = Color3.fromHex("FF3D6E")
local INK_DARK = Color3.fromHex("10141C")
-- touch has no hover: a press held this long is an INSPECT (HoverStart), never a
-- tap -- the same 0.35 s the Bag's old wireCardHit used (2026-08-19 touch fix)
local LONG_PRESS = 0.35

local warned: { [string]: boolean } = {}
local function warnOnce(key: string, msg: string)
	if warned[key] then return end
	warned[key] = true
	warn("[UIKit] BrainrotCard: " .. msg)
end

local function corner(o: GuiObject, r: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = o
	return c
end

local function stroke(o: GuiObject, thickness: number, color: Color3): UIStroke
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = o
	return s
end

local function frame(name: string, parent: Instance, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Parent = parent
	return f
end

-- two spectra end to end so a half-width scroll always shows one full rainbow
local function doubledSequence(seq: ColorSequence): ColorSequence
	local kps = {}
	for _, kp in ipairs(seq.Keypoints) do
		table.insert(kps, ColorSequenceKeypoint.new(kp.Time * 0.5, kp.Value))
	end
	for i, kp in ipairs(seq.Keypoints) do
		if i > 1 then table.insert(kps, ColorSequenceKeypoint.new(0.5 + kp.Time * 0.5, kp.Value)) end
	end
	return ColorSequence.new(kps)
end

-- padlock from two frames (shackle + body), like the Bag's buildPadlock
local function drawPadlock(parent: GuiObject, px: number, tint: Color3, z: number)
	local shackle = Instance.new("Frame")
	shackle.Name = "Shackle"
	shackle.BackgroundTransparency = 1
	shackle.AnchorPoint = Vector2.new(0.5, 0)
	shackle.Position = UDim2.new(0.5, 0, 0, math.floor(px * 0.12))
	shackle.Size = UDim2.fromOffset(math.floor(px * 0.44), math.floor(px * 0.42))
	shackle.ZIndex = z
	corner(shackle, 999)
	stroke(shackle, math.max(2, math.floor(px * 0.11)), tint)
	shackle.Parent = parent
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundColor3 = tint
	body.BorderSizePixel = 0
	body.AnchorPoint = Vector2.new(0.5, 1)
	body.Position = UDim2.new(0.5, 0, 1, -math.floor(px * 0.12))
	body.Size = UDim2.fromOffset(math.floor(px * 0.62), math.floor(px * 0.46))
	body.ZIndex = z + 1
	corner(body, math.max(2, math.floor(px * 0.14)))
	body.Parent = parent
end

-- ONE release-anywhere guard for every card (§7.6): a finger that slides off a card
-- before lifting -- the ordinary scroll gesture -- must still release that card.
local pressedRelease: (() -> ())? = nil
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	local r = pressedRelease
	pressedRelease = nil
	if r then r() end
end)

function BrainrotCard.new(props: Props): Card
	local C = S.Card
	local tierKey = C.TIER_KEY[props.rarity or ""]
	if not tierKey then
		warnOnce("rarity:" .. tostring(props.rarity), ("unknown rarity %q for %q -- using Common"):format(tostring(props.rarity), tostring(props.name)))
		tierKey = "COM"
	end
	local ladder = C.Ladder[tierKey]
	local ramp = S.Rarity[tierKey]
	local variantName = props.variant or "grid"
	local variant = C.Variants[variantName]
	if not variant then
		warnOnce("variant:" .. tostring(variantName), ("unknown variant %q -- using grid"):format(tostring(variantName)))
		variantName = "grid"
		variant = C.Variants.grid
	end
	local isHero, isCompact = variantName == "hero", variantName == "compact"
	local z = props.zIndex or 15
	local state: State = { equipped = false, locked = false, selected = false, new = false }
	if props.state then
		for k, v in pairs(props.state) do (state :: any)[k] = v end
	end
	local data: Props = props
	local touchOnly = Platform.IsTouch == true or (UserInputService.TouchEnabled and not UserInputService.MouseEnabled)
	local radius = C.Radius
	local bandFrac = C.BandFrac
	local bandMin = variant.bandMin or C.BandMin

	---------------------------------------------------------------- roots
	local cell = Instance.new("Frame")
	cell.Name = props.instanceName or ("Card_" .. tostring(props.name))
	cell.BackgroundTransparency = 1
	cell.BorderSizePixel = 0
	cell.Size = UDim2.fromScale(1, 1)
	cell.ZIndex = z
	if props.layoutOrder then cell.LayoutOrder = props.layoutOrder end
	cell:SetAttribute("BrainrotName", props.name)
	cell:SetAttribute("Rarity", props.rarity)

	local visual = frame("VisualRoot", cell, z)
	visual.AnchorPoint = Vector2.new(0.5, 0.5)
	visual.Position = UDim2.fromScale(0.5, 0.5)
	visual.Size = UDim2.fromScale(1, 1)

	local shadow = frame("Shadow", visual, z)
	shadow.BackgroundTransparency = 0.72
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.Position = UDim2.fromOffset(0, 4)
	shadow.Size = UDim2.fromScale(1, 1)
	corner(shadow, radius)

	local ring = frame("SelectionRing", visual, z + 1)
	ring.Position = UDim2.fromOffset(-4, -4)
	ring.Size = UDim2.new(1, 8, 1, 8)
	ring.Visible = state.selected == true
	corner(ring, radius + 4)
	stroke(ring, 3, S.Role.Selection)

	local plate = frame("Plate", visual, z + 1)
	plate.BackgroundTransparency = 0
	plate.BackgroundColor3 = C.Plate[1]
	plate.Size = UDim2.fromScale(1, 1)
	plate.ClipsDescendants = true
	corner(plate, radius)
	local plateGrad = Instance.new("UIGradient")
	plateGrad.Rotation = 90
	plateGrad.Color = ColorSequence.new(C.Plate[1], C.Plate[2])
	plateGrad.Parent = plate
	local edge = stroke(plate, C.Edge, ramp[2])
	edge.Name = "Edge"

	---------------------------------------------------------------- rarity layers
	local aura: Frame? = nil
	if ladder.aura then
		local a = frame("Aura", plate, z + 2)
		a.BackgroundTransparency = if ladder.aura == "strong" then 0.35 else 0.45
		a.BackgroundColor3 = ramp[2]
		a.AnchorPoint = Vector2.new(0, 1)
		a.Position = UDim2.new(0, 0, 1 - bandFrac, 0)
		a.Size = UDim2.new(1, 0, 0.45, 0)
		local ag = Instance.new("UIGradient")
		ag.Rotation = -90
		ag.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		ag.Parent = a
		aura = a
	end
	if ladder.foil then
		local foil = frame("Foil", plate, z + 2)
		foil.BackgroundTransparency = ladder.foil
		foil.BackgroundColor3 = Color3.new(1, 1, 1)
		foil.Size = UDim2.new(1, 0, 1 - bandFrac, 0)
		local fg = Instance.new("UIGradient")
		fg.Rotation = 25
		fg.Color = C.Rainbow -- static sheet: foil never drifts (decision 16)
		fg.Parent = foil
	end
	local well = frame("ArtWell", plate, z + 2)
	well.BackgroundTransparency = C.ArtWellAlpha
	well.BackgroundColor3 = Color3.new(1, 1, 1)
	well.AnchorPoint = Vector2.new(0.5, 0.5)
	well.Position = UDim2.new(0.5, 0, (1 - bandFrac) * 0.5, 0)
	well.Size = UDim2.new(0.8, 0, (1 - bandFrac) * 0.72, 0)
	corner(well, 999)
	local contact = frame("ContactShadow", plate, z + 3)
	contact.BackgroundTransparency = 0.55
	contact.BackgroundColor3 = Color3.new(0, 0, 0)
	contact.AnchorPoint = Vector2.new(0.5, 1)
	contact.Position = UDim2.new(0.5, 0, 1 - bandFrac, -4)
	contact.Size = UDim2.new(0.5, 0, 0, 8)
	corner(contact, 999)

	local art = frame("ArtHolder", plate, z + 3)
	art.Position = UDim2.fromOffset(C.ArtInset, C.ArtInset)
	art.Size = UDim2.new(1, -2 * C.ArtInset, 1 - bandFrac, -(C.ArtInset + 8))

	if ladder.holo then
		-- static rainbow ring around the art (a UIGradient on a UIStroke); the
		-- animated rainbow lives on the band only, so the cap holds
		local holo = frame("HoloRing", plate, z + 4)
		holo.AnchorPoint = Vector2.new(0.5, 0.5)
		holo.Position = UDim2.new(0.5, 0, (1 - bandFrac) * 0.5, 0)
		holo.Size = UDim2.new(1, -2, 1 - bandFrac, -2)
		corner(holo, radius - 2)
		local hs = stroke(holo, 3, Color3.new(1, 1, 1))
		local hg = Instance.new("UIGradient")
		hg.Color = C.Rainbow
		hg.Parent = hs
	end

	-- pips (top-left): lit count by tier
	local pips = frame("Pips", plate, z + 5)
	pips.Position = UDim2.fromOffset(8, 8)
	pips.Size = UDim2.fromOffset(5 * (C.Pip + 5), C.Pip + 2)
	for i = 1, 5 do
		local pip = Instance.new("Frame")
		pip.Name = "Pip" .. i
		pip.Size = UDim2.fromOffset(C.Pip, C.Pip)
		pip.Position = UDim2.fromOffset((i - 1) * (C.Pip + 5), 1)
		pip.Rotation = 45
		pip.BorderSizePixel = 0
		pip.ZIndex = z + 5
		pip.BackgroundColor3 = if i <= ladder.pips then ramp[1] else UNLIT_PIP
		pip.Parent = pips
	end

	-- band (bottom): tier name + count
	local band = frame("Band", plate, z + 4)
	band.BackgroundTransparency = 0
	band.AnchorPoint = Vector2.new(0, 1)
	band.Position = UDim2.fromScale(0, 1)
	band.Size = UDim2.new(1, 0, bandFrac, 0)
	local bandFloor = Instance.new("UISizeConstraint")
	bandFloor.MinSize = Vector2.new(0, bandMin)
	bandFloor.Parent = band
	local bandGrad: UIGradient? = nil
	local bandInk, bandStroke = Color3.new(1, 1, 1), S.Outline
	if ladder.band == "rainbow" then
		band.BackgroundColor3 = Color3.new(1, 1, 1)
		local bg = Instance.new("UIGradient")
		bg.Color = doubledSequence(C.Rainbow)
		bg.Parent = band
		bandGrad = bg
		bandInk, bandStroke = RAINBOW_INK, Color3.new(1, 1, 1)
	else
		band.BackgroundColor3 = ramp[2]
		band.BackgroundTransparency = if ladder.band == "muted" then 0.75 else 0.35
	end
	local tierName = PC.shout({
		name = "TierName", text = string.upper(props.rarity or "?"), size = if isHero then 22 else 13,
		color = bandInk, strokeColor = bandStroke, align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, -56, 1, 0), position = UDim2.fromOffset(8, 0), zIndex = z + 5, parent = band, scaled = true,
	})
	local countLabel = PC.shout({
		name = "Count", text = "", size = if isHero then 22 else 14, color = bandInk, strokeColor = bandStroke,
		align = Enum.TextXAlignment.Right, frameSize = UDim2.fromOffset(48, 0), position = UDim2.new(1, -8, 0, 0),
		anchor = Vector2.new(1, 0), zIndex = z + 5, parent = band, scaled = true,
	})
	countLabel.Size = UDim2.new(0, 48, 1, 0)
	local function paintCount()
		local showing = data.count and data.count > 1
		countLabel.Text = if showing then "x" .. tostring(data.count) else ""
		tierName.Size = UDim2.new(1, if showing then -56 else -16, 1, 0)
	end

	-- rate pill above the band
	local rateH = if isHero then 30 elseif isCompact then 15 else 18
	local ratePill = frame("Rate", plate, z + 5)
	ratePill.BackgroundTransparency = 0.15
	ratePill.BackgroundColor3 = INK_DARK
	ratePill.AnchorPoint = Vector2.new(0.5, 1)
	ratePill.Position = UDim2.new(0.5, 0, 1 - bandFrac, -4)
	ratePill.Size = UDim2.fromOffset(0, rateH)
	ratePill.AutomaticSize = Enum.AutomaticSize.X
	corner(ratePill, 999)
	local ratePad = Instance.new("UIPadding")
	ratePad.PaddingLeft = UDim.new(0, 7)
	ratePad.PaddingRight = UDim.new(0, 7)
	ratePad.Parent = ratePill
	local rateLabel = PC.shout({
		name = "Label", text = "", size = math.floor(rateH * 0.8), zIndex = z + 6, parent = ratePill,
		frameSize = UDim2.new(0, 0, 1, 0),
	})
	rateLabel.AutomaticSize = Enum.AutomaticSize.X
	local function paintRate()
		local v = tonumber(data.income) or 0
		rateLabel.Text = NumberFormat.Cash(v) .. "/s"
		ratePill.Visible = data.income ~= nil
	end
	paintRate()

	-- sparkles (Secret, God)
	local sparkles: { TextLabel } = {}
	if ladder.sparkles then
		for i, pos in ipairs({ UDim2.new(0.5, 0, 0.08, 0), UDim2.new(0.12, 0, 0.42, 0), UDim2.new(0.88, 0, 0.42, 0) }) do
			local sp = PC.shout({ name = "Sparkle" .. i, text = "\u{2726}", size = if isHero then 22 else 13, color = ramp[1], strokeColor = S.Outline, zIndex = z + 5, parent = plate, frameSize = UDim2.fromOffset(18, 18), position = pos, anchor = Vector2.new(0.5, 0.5) })
			table.insert(sparkles, sp)
		end
	end

	-- hero title
	if variant.title and props.title then
		PC.shout({ name = "Title", text = props.title, size = 26, zIndex = z + 5, parent = plate, scaled = true,
			frameSize = UDim2.new(1, -16, 0, 34), position = UDim2.new(0, 8, 1 - bandFrac, -(rateH + 42)) })
	end

	---------------------------------------------------------------- badges
	local badgePx = C.Badge
	-- badges sit ABOVE the Hit button (z+6) so the lock toggle receives its click
	local rightStack = frame("BadgesRight", plate, z + 7)
	rightStack.AnchorPoint = Vector2.new(1, 0)
	rightStack.Position = UDim2.new(1, -4, 0, 4)
	rightStack.Size = UDim2.fromOffset(badgePx + 14, 0)
	rightStack.AutomaticSize = Enum.AutomaticSize.Y
	local rl = Instance.new("UIListLayout")
	rl.FillDirection = Enum.FillDirection.Vertical
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	rl.Padding = UDim.new(0, 4)
	rl.SortOrder = Enum.SortOrder.LayoutOrder
	rl.Parent = rightStack

	local leftRow: Frame? = nil
	if variant.leftBadges then
		local lr = frame("BadgesLeft", plate, z + 7)
		lr.Position = UDim2.fromOffset(8, 8 + C.Pip + 8)
		lr.Size = UDim2.fromOffset(0, C.MutationStar)
		lr.AutomaticSize = Enum.AutomaticSize.X
		local ll = Instance.new("UIListLayout")
		ll.FillDirection = Enum.FillDirection.Horizontal
		ll.VerticalAlignment = Enum.VerticalAlignment.Center
		ll.Padding = UDim.new(0, 4)
		ll.SortOrder = Enum.SortOrder.LayoutOrder
		ll.Parent = lr
		leftRow = lr
	end

	local lockBtn: TextButton? = nil
	local hovering = false

	local function paintLeft()
		if not leftRow then return end
		for _, c in ipairs(leftRow:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		if data.mutation and data.mutation ~= "" then
			-- mutation gem: the mutation's OWN colour (decision 17), a rotated square
			-- with a dark edge so it never reads as a rarity pip
			local gemHolder = frame("MutationGem", leftRow, z + 6)
			gemHolder.LayoutOrder = 1
			gemHolder.Size = UDim2.fromOffset(C.MutationStar, C.MutationStar)
			local gem = Instance.new("Frame")
			gem.Name = "Gem"
			gem.AnchorPoint = Vector2.new(0.5, 0.5)
			gem.Position = UDim2.fromScale(0.5, 0.5)
			gem.Size = UDim2.fromOffset(math.floor(C.MutationStar * 0.68), math.floor(C.MutationStar * 0.68))
			gem.Rotation = 45
			gem.BorderSizePixel = 0
			gem.BackgroundColor3 = data.mutationColor or S.Role.Purple[1]
			gem.ZIndex = z + 7
			corner(gem, 2)
			stroke(gem, 2, INK_DARK)
			gem.Parent = gemHolder
		end
		if data.sizeTag and data.sizeTag ~= "" then
			-- size chip: ONE neutral secondary treatment, never red (decision 17)
			local chip = frame("SizeChip", leftRow, z + 6)
			chip.LayoutOrder = 2
			chip.BackgroundTransparency = 0
			chip.BackgroundColor3 = S.Surface.Track
			chip.Size = UDim2.fromOffset(0, C.BadgeSmall)
			chip.AutomaticSize = Enum.AutomaticSize.X
			corner(chip, 4)
			local cp = Instance.new("UIPadding")
			cp.PaddingLeft = UDim.new(0, 4)
			cp.PaddingRight = UDim.new(0, 4)
			cp.Parent = chip
			local l = PC.shout({ name = "Label", text = string.upper(data.sizeTag), size = C.BadgeSmall - 4, zIndex = z + 7, parent = chip, frameSize = UDim2.new(0, 0, 1, 0) })
			l.AutomaticSize = Enum.AutomaticSize.X
		end
	end

	local function paintRight()
		for _, c in ipairs(rightStack:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		lockBtn = nil
		local cap = variant.rightCap or 2
		local used = 0
		-- priority: Locked / lock toggle > Equipped > NEW (§7.5)
		if (state.locked == true or props.lock) and used < cap then
			used += 1
			local slot = frame("LockSlot", rightStack, z + 7)
			slot.LayoutOrder = 1
			slot.Size = UDim2.fromOffset(badgePx, badgePx)
			local b = Instance.new("TextButton")
			b.Name = "Lock"
			b.Text = ""
			b.AutoButtonColor = false
			b.BorderSizePixel = 0
			b.Size = UDim2.fromScale(1, 1)
			b.BackgroundColor3 = S.Role.Disabled[1]
			b.ZIndex = z + 7
			b.Active = props.lock ~= nil
			b:SetAttribute("NoPolish", true)
			corner(b, 6)
			stroke(b, 2, Color3.new(1, 1, 1))
			drawPadlock(b, badgePx, S.Surface.ReadInk, z + 8)
			if state.locked == true then
				b.Visible = true
				b.BackgroundTransparency = 0
			elseif touchOnly then
				b.Visible = true -- always reachable on touch, drawn subdued
				b.BackgroundTransparency = 0.5
				for _, d in ipairs(b:GetChildren()) do
					if d:IsA("Frame") then
						d.BackgroundTransparency = 0.5
						local s = d:FindFirstChildOfClass("UIStroke")
						if s then s.Transparency = 0.5 end
					end
				end
			else
				b.Visible = hovering -- desktop: revealed on hover
				b.BackgroundTransparency = 0.25
			end
			if props.lock then
				b.Activated:Connect(function()
					local fn = props.lock and props.lock.onToggle
					if fn then
						local ok, err = pcall(fn, not (state.locked == true))
						if not ok then warn(("[UIKit] BrainrotCard lock toggle failed: %s\n%s"):format(tostring(err), debug.traceback())) end
					end
				end)
			end
			b.Parent = slot
			lockBtn = b
		end
		if state.equipped and state.equipped ~= false and used < cap then
			used += 1
			local padText = if typeof(state.equipped) == "number" then ("\u{2713}%d"):format(state.equipped :: number) else "\u{2713}"
			local e = frame("Equipped", rightStack, z + 7)
			e.LayoutOrder = 2
			e.BackgroundTransparency = 0
			e.BackgroundColor3 = S.Role.Positive[1]
			e.Size = UDim2.fromOffset(if typeof(state.equipped) == "number" then badgePx + 12 else badgePx, badgePx)
			corner(e, 6)
			stroke(e, 2, Color3.new(1, 1, 1))
			PC.shout({ name = "Label", text = padText, size = badgePx - 8, color = Color3.fromHex("06301B"), strokeColor = Color3.new(1, 1, 1), zIndex = z + 8, parent = e })
		end
		if state.new == true and used < cap then
			used += 1
			local n = frame("New", rightStack, z + 7)
			n.LayoutOrder = 3
			n.BackgroundTransparency = 0
			n.BackgroundColor3 = NEW_RED
			n.Size = UDim2.fromOffset(30, C.BadgeSmall)
			corner(n, 4)
			PC.shout({ name = "Label", text = "NEW", size = C.BadgeSmall - 5, zIndex = z + 8, parent = n })
		end
	end

	paintLeft()
	paintRight()

	---------------------------------------------------------------- signals + feel
	local activatedEv = Instance.new("BindableEvent")
	activatedEv.Name = "ActivatedEvent"
	activatedEv.Parent = cell
	local hoverStartEv = Instance.new("BindableEvent")
	hoverStartEv.Name = "HoverStartEvent"
	hoverStartEv.Parent = cell
	local hoverEndEv = Instance.new("BindableEvent")
	hoverEndEv.Name = "HoverEndEvent"
	hoverEndEv.Parent = cell

	local REST = UDim2.fromScale(0.5, 0.5)
	local LIFT = UDim2.new(0.5, 0, 0.5, -3)
	local SINK = UDim2.new(0.5, 0, 0.5, 1)
	local function moveTo(pos: UDim2, info: TweenInfo)
		TweenService:Create(visual, info, { Position = pos }):Play()
	end

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = z + 6 -- under the badges (z+7), over every layer
	hit:SetAttribute("NoPolish", true)
	hit.Parent = plate

	local isDown = false
	local pressToken = 0 -- touch long-press: bumps per press so a stale delay never fires
	local longPressed = false -- touch: the current press became an inspect
	local function release()
		isDown = false
		if hovering then moveTo(LIFT, S.Tween.HoverIn) else moveTo(REST, S.Tween.HoverOut) end
	end
	hit.MouseEnter:Connect(function()
		if touchOnly then return end
		hovering = true
		if lockBtn and state.locked ~= true then lockBtn.Visible = true end
		moveTo(LIFT, S.Tween.HoverIn)
		hoverStartEv:Fire()
	end)
	hit.MouseLeave:Connect(function()
		-- touch: the inspect state is owned by the press logic below; a touch-end
		-- MouseLeave must not cancel it the instant the finger lifts
		if touchOnly then return end
		local wasHovering = hovering
		hovering = false
		if lockBtn and state.locked ~= true and not touchOnly then lockBtn.Visible = false end
		if wasHovering then
			if not isDown then moveTo(REST, S.Tween.HoverOut) end
			hoverEndEv:Fire()
		end
	end)
	hit.MouseButton1Down:Connect(function()
		isDown = true
		pressedRelease = release
		moveTo(SINK, S.Tween.Press)
		if touchOnly then
			if longPressed then
				-- a new press ends the previous inspect
				longPressed = false
				hovering = false
				if lockBtn and state.locked ~= true then lockBtn.Visible = true end -- touch keeps it visible (subdued)
				hoverEndEv:Fire()
			end
			pressToken += 1
			local my = pressToken
			task.delay(LONG_PRESS, function()
				if isDown and my == pressToken and cell.Parent then
					longPressed = true
					hovering = true
					hoverStartEv:Fire()
				end
			end)
		end
	end)
	hit.MouseButton1Up:Connect(function()
		if pressedRelease == release then pressedRelease = nil end
		release()
	end)
	hit.Activated:Connect(function()
		if touchOnly and longPressed then return end -- a long press is an inspect, never an equip
		activatedEv:Fire()
	end)

	---------------------------------------------------------------- mount / unmount
	local mounted = false
	local vp: ViewportFrame? = nil
	local placeholder: TextLabel? = nil
	local fxIds: { number } = {}

	local function clearFx()
		for _, id in ipairs(fxIds) do FxDriver.unregister(id) end
		table.clear(fxIds)
	end
	local function registerFx()
		clearFx()
		local n = 0
		for _, layer in ipairs(ladder.animated) do
			if n >= C.MaxAnimatedLayers then break end
			if layer == "aura" and aura then
				local a = aura :: Frame
				table.insert(fxIds, FxDriver.register(plate, function(t)
					a.BackgroundTransparency = 0.25 + 0.40 * (0.5 + 0.5 * math.sin(t * 1.9))
				end))
				n += 1
			elseif layer == "band" and bandGrad then
				local g = bandGrad :: UIGradient
				table.insert(fxIds, FxDriver.register(plate, function(t)
					g.Offset = Vector2.new(-((t * 0.15) % 0.5), 0)
				end))
				n += 1
			elseif layer == "sparkles" and #sparkles > 0 then
				table.insert(fxIds, FxDriver.register(plate, function(t)
					for i, sp in ipairs(sparkles) do
						local v = 0.3 + 0.6 * (0.5 + 0.5 * math.sin(t * 3.1 + i * 2.1))
						sp.TextTransparency = v
						local st = sp:FindFirstChildOfClass("UIStroke")
						if st then st.Transparency = v end
					end
				end))
				n += 1
			end
		end
	end

	local function showPlaceholder()
		if placeholder then return end
		local q = PC.shout({ name = "MissingArt", text = "?", size = 40, color = S.Surface.ReadSub, strokeColor = INK_DARK, zIndex = z + 4, parent = art })
		placeholder = q
	end

	local function mount()
		if mounted then return end
		mounted = true
		local ok, res = pcall(function()
			local master = if data.kind == "pet"
				then BrainrotThumb.petMaster(data.model, data.name)
				else BrainrotThumb.master(data.name)
			if not master then return nil end
			return BrainrotThumb.addMaster(art, master, {
				size = UDim2.fromScale(1, 1), zIndex = z + 4,
				dir = C.Light.Dir, ambient = C.Light.Ambient, lightColor = C.Light.LightColor, lightDirection = C.Light.LightDirection,
				fill = C.Fill,
				faceYaw = if data.kind == "pet" then nil else BrainrotThumb.FACING[data.name],
			})
		end)
		if ok and res then
			vp = res
			vp.Name = "Preview"
		else
			if not ok then
				warnOnce("clone:" .. tostring(data.name), ("viewport for %q failed: %s\n%s"):format(tostring(data.name), tostring(res), debug.traceback()))
			end
			showPlaceholder()
		end
		registerFx()
	end

	local function unmount()
		if not mounted then return end
		mounted = false
		clearFx()
		if vp then vp:Destroy() vp = nil end
		if placeholder then placeholder:Destroy() placeholder = nil end
	end

	---------------------------------------------------------------- api
	local card: Card
	card = {
		root = cell, visual = visual, plate = plate, art = art, data = data,
		setState = function(patch: State)
			for k, v in pairs(patch) do (state :: any)[k] = v end
			ring.Visible = state.selected == true
			paintRight()
		end,
		set = function(patch: { [string]: any })
			if patch.rarity ~= nil and patch.rarity ~= data.rarity then
				warnOnce("set-rarity", "set({ rarity }) is not supported -- destroy and rebuild the card")
			end
			if patch.name ~= nil or patch.kind ~= nil or patch.model ~= nil then
				warnOnce("set-identity", "set({ name/kind/model }) is not supported -- destroy and rebuild the card")
			end
			for k, v in pairs(patch) do
				if k == "state" then
					card.setState(v)
				elseif k ~= "rarity" and k ~= "name" and k ~= "kind" and k ~= "model" then
					(data :: any)[k] = v
				end
			end
			paintRate()
			paintCount()
			paintLeft()
		end,
		mount = mount,
		unmount = unmount,
		isMounted = function() return mounted end,
		destroy = function()
			unmount()
			if pressedRelease == release then pressedRelease = nil end
			cell:Destroy()
		end,
		Activated = activatedEv.Event,
		HoverStart = hoverStartEv.Event,
		HoverEnd = hoverEndEv.Event,
	}
	paintCount()
	cell.Parent = props.parent
	return card
end

return BrainrotCard
