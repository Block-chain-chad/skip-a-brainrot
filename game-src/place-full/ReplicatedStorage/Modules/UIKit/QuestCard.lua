--[[ ==========================================================================
QuestCard -- one tracked NPC quest, on the kit (UI round 3, 2026-09-19).
---------------------------------------------------------------------------
The presentation half of the quest tracker. QuestTrackerClient owns the data
(which questlines exist, what their remotes say, which stage means what); this
module only knows how to DRAW one quest from a plain table, so a new NPC is one
table entry there and nothing here.

  local card = QuestCard.new({
      parent = frame, layoutOrder = 1, zIndex = 5, typeScale = 1,
      npc = { name = "Gianluca", initial = "G", accent = {c1, c2}, icon = "keyGianluca" },
      title = "The Secret Chim",
      objective = "Find the Secret Chim", current = 0, required = 1, hasProgress = false,
      state = "active",          -- "active" | "return" | "claim" | "complete"
      returnTo = "GIANLUCA",     -- the chip text after RETURN TO / CLAIM FROM
  })
  card.set(props, animate)       -- repaint; animate = tween the fill + pop the count
  card.setCompact(bool)          -- objective + bar (or chip) only (the collapsed tracker)
  card.playComplete(onDone)      -- fill settles, "COMPLETE" chip, then onDone()
  card.root / card.Activated     -- the card is a button (tap = expand/collapse)
  QuestCard.measure(props)       -- the height new() will lay those props out at
  props.minHeight                -- a floor on that height (touch targets), authored px

READS IN UNDER A SECOND, by hierarchy: the NPC badge (accent plate + initial +
motif), the quest name, ONE objective line, a chunky bar with the numbers on it.
State chips (RETURN TO X / CLAIM FROM X / COMPLETE) replace nothing -- they sit
under the bar, in the kit's colour grammar: blue = go somewhere, green = claim /
done. Nothing here runs per frame: the fill and the pop are TweenService tweens
on Size/Position (the two properties tweens are known to drive in this place),
the complete beat is task.delay, and there are no viewports.

TYPE ON GLASS. The tracker scales this card with Platform.Widget() (0.6 on a
phone), which would take 15px copy down to 9px. `typeScale` re-authors every
TextSize on the way in -- the same compensation idea HudLayout.CompensateType
uses -- so the phone card keeps ~12px type inside a smaller box.
========================================================================== ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local UIKitFolder = script.Parent
local PC = require(UIKitFolder:WaitForChild("PanelChrome"))
local S = require(UIKitFolder:WaitForChild("SpecTheme"))
local okIcon, IconArt = pcall(function() return require(UIKitFolder:WaitForChild("IconArt")) end)
if not okIcon then IconArt = nil end

local QuestCard = {}

QuestCard.WIDTH = 300
local W = QuestCard.WIDTH
local PAD = 12
local BADGE = 44
local BAR_H = 22
local CHIP_H = 26
local GAP = 6

-- The head row: the badge beside two text lines (NPC name over quest name).
-- On the phone the type is re-authored 1.35x, so the lines outgrow the badge
-- and the row grows with them (a 24px title in a 22px slot clipped its glyphs
-- -- phone-override finding, 2026-09-19). measure() and new() share this.
local function headHeight(sz): number
	return math.max(BADGE, sz(16) + sz(22))
end

local FILL_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_UP = TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_DOWN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- chip ramps: blue = navigation ("go back to him"), green = claim / done
local CHIP = {
	["return"]   = { colors = S.Role.Neutral,  prefix = "RETURN TO " },
	["claim"]    = { colors = S.Role.Positive, prefix = "CLAIM FROM " },
	["complete"] = { colors = { Color3.fromHex("C9EFC2"), Color3.fromHex("B2E4A8") }, prefix = "\u{2713} COMPLETE" },
}

local function frame(name: string, parent: Instance, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Parent = parent
	return f
end

--- The height new()/set() will lay a card out at, in authored px, from the
--- same props -- so the tracker can fit WHOLE cards to the room it has before
--- it builds anything. Mirrors the row rules in new() exactly: the head only
--- when not compact, the objective always (wrapped at the card's inner width),
--- the chip for a chip state, the bar with progress -- except compact, where a
--- chip state keeps the chip and drops the bar.
--- TextService measures with the same engine the AutomaticSize label uses, so
--- this agrees with the live card to the pixel (checked 2026-09-19).
function QuestCard.measure(p): number
	local ts = p.typeScale or 1
	local function sz(n) return math.floor(n * ts + 0.5) end
	local compact = p.compact == true
	local rows = {}
	if not compact then table.insert(rows, headHeight(sz)) end
	local bounds = TextService:GetTextSize(p.objective or "", sz(15), S.Font.Read, Vector2.new(W - 2 * PAD, 4096))
	table.insert(rows, math.max(bounds.Y, sz(15)))
	local chipKind = CHIP[p.kind or p.state or "active"] ~= nil
	if p.hasProgress ~= false and not (compact and chipKind) then table.insert(rows, BAR_H) end
	if chipKind then table.insert(rows, CHIP_H) end
	local h = PAD * 2
	for i, r in ipairs(rows) do
		h += r + ((i > 1) and GAP or 0)
	end
	return math.max(h, p.minHeight or 0)
end

function QuestCard.new(props)
	local z = props.zIndex or 5
	local ts = props.typeScale or 1
	local function sz(n) return math.floor(n * ts + 0.5) end

	-- the card is a BUTTON: tap = expand / collapse (the tracker wires Activated)
	local root = Instance.new("TextButton")
	root.Name = props.name or "QuestCard"
	root.Text = ""
	root.AutoButtonColor = false
	root.BackgroundColor3 = S.Surface.RowTop
	root.BorderSizePixel = 0
	-- AutomaticSize only ever GROWS past Size, so the Y offset here is a floor:
	-- the tracker passes the 44px touch minimum (in authored px) on a phone so a
	-- compact card is still a tappable target
	root.Size = UDim2.new(0, W, 0, props.minHeight or 0)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.LayoutOrder = props.layoutOrder or 1
	root.ZIndex = z
	root:SetAttribute("NoPolish", true)
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 20); c.Parent = root
		local s = Instance.new("UIStroke"); s.Thickness = 4; s.Color = S.Outline; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.LineJoinMode = Enum.LineJoinMode.Round; s.Parent = root
		local g = Instance.new("UIGradient"); g.Rotation = 90; g.Color = ColorSequence.new(S.Surface.RowTop, S.Surface.RowBottom); g.Parent = root
		local p = Instance.new("UIPadding")
		p.PaddingTop = UDim.new(0, PAD); p.PaddingBottom = UDim.new(0, PAD)
		p.PaddingLeft = UDim.new(0, PAD); p.PaddingRight = UDim.new(0, PAD)
		p.Parent = root
	end
	-- depth comes from the chunky navy outline + the top-to-bottom shell gradient;
	-- no shadow frame under an AutomaticSize card (a scale-sized child inside a
	-- self-sizing parent is the kind of loop this kit avoids)

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, GAP)
	list.Parent = root

	------------------------------------------------------------ head: badge + name + title
	local HEAD_H = headHeight(sz)
	local badgeY = math.floor((HEAD_H - BADGE) / 2)
	local head = frame("Head", root, z + 1)
	head.LayoutOrder = 1
	head.Size = UDim2.new(1, 0, 0, HEAD_H)

	local badge = PC.plate({
		name = "Badge",
		size = UDim2.fromOffset(BADGE, BADGE),
		position = UDim2.fromOffset(0, badgeY),
		colors = (props.npc and props.npc.accent) or S.Role.Neutral,
		radius = 14, outline = 3, strokeColor = Color3.new(1, 1, 1),
		zIndex = z + 2, parent = head, gloss = false,
	})
	local initial = PC.shout({
		name = "Initial", text = (props.npc and props.npc.initial) or "?", size = sz(26),
		zIndex = z + 3, parent = badge, scaled = true,
		frameSize = UDim2.new(1, -6, 1, -6), position = UDim2.fromOffset(3, 3),
	})
	local motif: Frame? = nil
	if IconArt and props.npc and props.npc.icon and IconArt.has(props.npc.icon) then
		-- a small authored motif on the badge's corner: the key he pays, the crown...
		local host = frame("Motif", head, z + 4)
		host.AnchorPoint = Vector2.new(1, 1)
		host.Position = UDim2.new(0, BADGE + 5, 0, badgeY + BADGE + 4)
		host.Size = UDim2.fromOffset(20, 20)
		IconArt.draw(host, props.npc.icon, 20, z + 5)
		motif = host
	end

	local textX = BADGE + 10
	local npcName = PC.shout({
		name = "Npc", text = string.upper((props.npc and props.npc.name) or ""), size = sz(13),
		color = (props.npc and props.npc.accent and props.npc.accent[2]) or S.Role.Neutral[2],
		strokeColor = Color3.new(1, 1, 1), align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, -textX, 0, sz(16)), position = UDim2.fromOffset(textX, 0),
		zIndex = z + 2, parent = head,
	})
	npcName.TextTruncate = Enum.TextTruncate.AtEnd
	local title = PC.read({
		name = "Title", text = props.title or "", size = sz(18), color = S.Surface.ReadInk,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, -textX, 0, HEAD_H - sz(16)), position = UDim2.fromOffset(textX, sz(16)),
		zIndex = z + 2, parent = head,
	})
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.TextYAlignment = Enum.TextYAlignment.Top

	------------------------------------------------------------ objective
	local objective = PC.read({
		name = "Objective", text = props.objective or "", size = sz(15), color = S.Surface.ReadInk,
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, 0, 0, 0), zIndex = z + 1, parent = root,
	})
	objective.LayoutOrder = 3
	objective.AutomaticSize = Enum.AutomaticSize.Y
	objective.TextWrapped = true
	objective.TextYAlignment = Enum.TextYAlignment.Top

	------------------------------------------------------------ bar
	local barRow = frame("BarRow", root, z + 1)
	barRow.LayoutOrder = 4
	barRow.Size = UDim2.new(1, 0, 0, BAR_H)

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BackgroundColor3 = S.Surface.Track
	track.BorderSizePixel = 0
	track.Size = UDim2.new(1, 0, 1, 0)
	track.ZIndex = z + 2
	track.ClipsDescendants = true
	track.Parent = barRow
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 999); c.Parent = track
		local s = Instance.new("UIStroke"); s.Thickness = 3; s.Color = S.Outline; s.Parent = track
	end
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = S.Action.GreenFill[1]
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = z + 3
	fill.Parent = track
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 999); c.Parent = fill
		local g = Instance.new("UIGradient"); g.Rotation = 90; g.Color = ColorSequence.new(S.Action.GreenFill[1], S.Action.GreenFill[2]); g.Parent = fill
	end
	-- the numbers ride ON the bar, right-aligned, white shout with the navy stroke
	local count = PC.shout({
		name = "Count", text = "", size = sz(14), align = Enum.TextXAlignment.Right,
		frameSize = UDim2.new(1, -10, 1, 0), position = UDim2.fromOffset(0, 0),
		zIndex = z + 4, parent = track,
	})

	------------------------------------------------------------ state chip
	local chipRow = frame("ChipRow", root, z + 1)
	chipRow.LayoutOrder = 5
	chipRow.Size = UDim2.new(1, 0, 0, CHIP_H)
	chipRow.Visible = false
	local chip = PC.statePlate({
		name = "State", text = "", colors = S.Role.Neutral,
		size = UDim2.new(1, 0, 1, 0), textSize = sz(15), zIndex = z + 2, parent = chipRow,
	})
	local chipLabel = chip:FindFirstChild("Label")
	local chipGrad = chip:FindFirstChildOfClass("UIGradient")

	------------------------------------------------------------ state
	local card = { root = root, Activated = root.Activated }
	local state = {
		current = 0, required = 1, hasProgress = true, compact = props.compact == true,
		kind = "active", returnTo = "", shownPct = -1, completing = false,
	}

	local function applyChip()
		local spec = CHIP[state.kind]
		if not spec then
			chipRow.Visible = false
			return
		end
		chipRow.Visible = true
		local text = spec.prefix
		if state.kind ~= "complete" then text = spec.prefix .. string.upper(state.returnTo or "") end
		if chipLabel then chipLabel.Text = text end
		local resolved = spec.colors
		chip.BackgroundColor3 = resolved[1]
		if chipGrad then chipGrad.Color = ColorSequence.new(resolved[1], resolved[2]) end
		if chipLabel then
			local lum = resolved[1].R * 0.299 + resolved[1].G * 0.587 + resolved[1].B * 0.114
			local dark = lum > 0.82
			chipLabel.TextColor3 = dark and Color3.fromHex("1F6E2A") or Color3.new(1, 1, 1)
			local st = chipLabel:FindFirstChildOfClass("UIStroke")
			if st then st.Color = dark and Color3.new(1, 1, 1) or S.Outline end
		end
	end

	-- compact keeps ONE line under the objective: the chip when the stage has
	-- one (RETURN TO X says more than a full bar would), otherwise the bar
	local function applyCompact()
		head.Visible = not state.compact
		local chipKind = CHIP[state.kind] ~= nil
		barRow.Visible = state.hasProgress and not (state.compact and chipKind)
		applyChip()
	end

	-- the count pops once: a 3px lift on POP_UP, back with a Back ease
	local function popCount()
		count.Position = UDim2.fromOffset(0, 0)
		local up = TweenService:Create(count, POP_UP, { Position = UDim2.fromOffset(0, -3) })
		up.Completed:Connect(function()
			TweenService:Create(count, POP_DOWN, { Position = UDim2.fromOffset(0, 0) }):Play()
		end)
		up:Play()
	end

	local function setFill(pct: number, animate: boolean)
		pct = math.clamp(pct, 0, 1)
		if animate then
			TweenService:Create(fill, FILL_TWEEN, { Size = UDim2.fromScale(pct, 1) }):Play()
		else
			fill.Size = UDim2.fromScale(pct, 1)
		end
	end

	function card.set(p, animate: boolean?)
		if p.npc then
			if p.npc.initial then initial.Text = p.npc.initial end
			if p.npc.name then npcName.Text = string.upper(p.npc.name) end
			if p.npc.accent then
				badge.BackgroundColor3 = p.npc.accent[1]
				local bg = badge:FindFirstChildOfClass("UIGradient")
				if bg then bg.Color = ColorSequence.new(p.npc.accent[1], p.npc.accent[2]) end
				npcName.TextColor3 = p.npc.accent[2]
			end
		end
		if p.title ~= nil then title.Text = p.title end
		if p.objective ~= nil then objective.Text = p.objective end
		if p.kind ~= nil or p.state ~= nil then state.kind = p.kind or p.state end
		if p.returnTo ~= nil then state.returnTo = p.returnTo end
		if p.hasProgress ~= nil then state.hasProgress = p.hasProgress end

		local cur = tonumber(p.current) or state.current
		local req = tonumber(p.required) or state.required
		local grew = animate and (cur > state.current) and (req == state.required)
		state.current, state.required = cur, req
		local pct = (req > 0) and (cur / req) or 0
		if state.kind == "complete" then pct = 1 end
		count.Text = state.hasProgress and string.format("%d / %d", cur, req) or ""
		setFill(pct, animate == true and state.shownPct >= 0)
		state.shownPct = pct
		if grew then popCount() end
		applyCompact()
	end

	function card.setCompact(v: boolean)
		state.compact = v and true or false
		applyCompact()
	end

	-- THE COMPLETION BEAT (brief §8): the bar settles full, the chip flips to
	-- COMPLETE, a short pause, then onDone() -- the tracker drops the card. Only
	-- ever called once the server's state says the questline is finished.
	function card.playComplete(onDone: (() -> ())?, holdSeconds: number?)
		if state.completing then return end
		state.completing = true
		state.kind = "complete"
		barRow.Visible = state.hasProgress
		count.Text = state.hasProgress and string.format("%d / %d", state.required, state.required) or ""
		setFill(1, true)
		state.shownPct = 1
		-- the chip lands as the fill settles, not on top of it
		task.delay(0.30, function()
			if not root.Parent then return end
			state.compact = false
			applyCompact()
		end)
		task.delay(holdSeconds or 1.2, function()
			if onDone then onDone() end
		end)
	end

	function card.isCompleting() return state.completing end

	function card.destroy()
		root:Destroy()
	end

	card.set(props, false)
	root.Parent = props.parent
	return card
end

return QuestCard
