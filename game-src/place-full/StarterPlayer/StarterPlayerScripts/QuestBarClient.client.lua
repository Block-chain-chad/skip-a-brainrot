-- QuestBarClient: ONE standing progress bar for the Goals board. (No longer
-- literally always-visible: it yields while a GameHUD panel is open -- see the
-- PanelHost watch below -- and the player can dismiss it.)
--
-- CLAUDE.md asks for something visibly close to completing at all times; there
-- were zero progress indicators anywhere. This is the first of the three bars --
-- deliberately only the quest one this round.
--
-- Progress still moves through UI.setFill, which tweens with T.tween.bar
-- (0.40s Quad/Out), so the fill is never snapped. (UI.track / UI.claimRing
-- fell away with the restyles; setFill is the one UIKit primitive left here.)
--
-- NOT a panel and not the retired QuestUI: its own small ScreenGui, pinned to the
-- RIGHT edge (owner's call, 2026-08-06 -- it used to sit top-left under the
-- currency cluster).
--
-- The right edge is a column, not free space, so the vertical offset matters:
--   cash pill      y  12..58
--   weather pill   y  72..110   (only during an event)
--   THIS BAR       below both
--   quest tracker  ~y 207       (QuestTrackerClient, already right-aligned)
-- Anything moved here has to clear that stack or it lands on top of the cash pill.
--
-- NPC quests have their own tracker (QuestTrackerClient, middle-right, log rows).
-- This is the Goals board, a different system with a different shape -- the two
-- do not overlap on screen or in data.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local modules = ReplicatedStorage:WaitForChild("Modules")
local UIKit = modules:WaitForChild("UIKit")
local T = require(UIKit:WaitForChild("Tokens"))
local UI = require(UIKit:WaitForChild("Builders"))
local Platform = require(modules:WaitForChild("Platform"))
local formatNumber = require(modules:WaitForChild("NumberFormat")).Short

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local W, H = 300, 62
-- Clears the cash pill and the weather pill above it. Tuned against the measured
-- rect rather than assumed: this ScreenGui's canvas is shifted by the platform's
-- safe-area inset, so the rendered Y is not the same as this offset.
-- 2026-08-14: raised from 190 to open a clear GAP to the QUEST LOG below it
-- (QuestTrackerClient, TOP_Y = 264); ~37px of air reads them as two separate
-- widgets. Still ~55px below the weather pill (72..110), so it does not ride up
-- into it during an event. Kept through the 2026-08-16 naked restyle: the text
-- occupies the same rect the old plate did, so the column maths still hold.
local TOP_OFFSET = 165

local gui = Instance.new("ScreenGui")
gui.Name = "QuestBarUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
-- 2026-08-16 Z FIX: was T.zindex.currency (20), which sits ABOVE the GameHUD
-- ScreenGui (DisplayOrder 7) -- so this bar rendered over every open panel and
-- buried their close buttons at narrow viewports. 4 matches the quest log
-- (QuestTrackerUI): under the side rail (6) and GameHUD (7), over MainUI (0).
gui.DisplayOrder = 4
-- TYPOGRAPHY / COLOUR OPT-OUT. This bar owns its own colours -- cyan progress
-- numbers, green READY!, pink-red dismiss glyph -- so it must stay exempt from
-- UIPolish, which otherwise repaints every label white FredokaOne.
gui:SetAttribute("NoPolish", true)
local playerGui = player:WaitForChild("PlayerGui")
gui.Parent = playerGui

-- HIDE WHILE ANY GameHUD PANEL IS OPEN (2026-08-16). The quest log yields the
-- same way: SideRail flips QuestTrackerUI.Enabled from its panel registry
-- (updateRailVisibility). This bar is not rail-registered, so it watches the
-- tell the panels themselves toggle: GameHUD.Canvas.PanelHost.Visible, which
-- GameHUDClient's openPanel sets true and closePanel drops false after its
-- close tween. The switch is gui.Enabled, NOT root.Visible -- Visible carries
-- the "is there a goal to show / was it dismissed" state and must come through
-- an open/close cycle untouched. Coexists with HudToggleClient's fold by that
-- script's own ownership rule: while fully folded it re-asserts Enabled=false
-- every pass, so this watcher cannot resurrect a bar the player put away.
task.spawn(function()
	local hud = playerGui:WaitForChild("GameHUD", 30)
	local canvas = hud and hud:WaitForChild("Canvas", 10)
	local panelHost = canvas and canvas:WaitForChild("PanelHost", 10)
	if not panelHost then return end
	local function sync()
		-- RailPanelOpen is SideRail's "any registered panel is open" (round 2.5): the
		-- legacy shops (egg, merchant) never touch PanelHost, and this bar was left
		-- poking out from under the egg shop's header on a phone. Phone only, like
		-- every other chrome yield -- on desktop the shops simply draw over it.
		gui.Enabled = not (panelHost.Visible or (Platform.IsPhone and player:GetAttribute("RailPanelOpen") == true))
	end
	panelHost:GetPropertyChangedSignal("Visible"):Connect(sync)
	player:GetAttributeChangedSignal("RailPanelOpen"):Connect(sync)
	sync()
end)

local root = Instance.new("Frame")
root.Name = "Root"
-- right-aligned: anchor on the right edge so the plate grows leftwards and the
-- gap to the screen edge stays 18px whatever the bar is sized to
-- Named because the phone layout hands this frame to HudLayout, which overwrites
-- AnchorPoint with its stack's own, and detaching has to put this one back.
local HOME_ANCHOR = Vector2.new(1, 0)
root.AnchorPoint = HOME_ANCHOR
root.Position = UDim2.new(1, -18, 0, TOP_OFFSET)
root.Size = UDim2.fromOffset(W, H)
root.BackgroundTransparency = 1
root.Visible = false          -- until the first payload names a quest
root.Parent = gui

-- Declared HERE, above dismissBar, and NOT again lower down. Luau captures a
-- later-declared local as nil silently -- it compiles and then throws the first
-- time it runs -- and this was 165 lines below its first use, so the dismiss tween
-- completed, tried to restore a nil Position, and left the bar parked at its
-- off-screen `away` spot (observed live at Position {1, 308}).
local HOME_POS = UDim2.new(1, -18, 0, TOP_OFFSET)

-- One dismiss path rather than two copies of the same tween (the X button and the
-- oversized touch target behind it both land here).
local function dismissBar()
	local away = UDim2.new(1, 18 + W + 60, 0, TOP_OFFSET)
	local tw = TweenService:Create(root,
		TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = away })
	tw.Completed:Connect(function()
		root.Visible = false
		root.Position = HOME_POS
	end)
	tw:Play()
end

-- 2026-08-10 (user capture): this bar visibly JUMPED between two sizes
-- mid-session. Two defects in the old fit: (1) it listened on the camera
-- INSTANCE, and both respawns and the catch cinematic replace the camera,
-- killing the connection -- so the bar kept a stale scale until something
-- unrelated poked it; (2) it used the canvas fit, which at 1080p renders
-- this 300px widget at 1.39x -- 40% bigger than the quest tracker sitting
-- directly beneath it. Platform.Watch survives camera swaps, and Widget()
-- is the same scale the tracker uses, so the column reads as one family.
local scale = Instance.new("UIScale")
scale.Parent = root
Platform.Watch(function()
	scale.Scale = Platform.Widget()
end)

-- ============================================================================
-- NAKED RESTYLE (2026-08-16, PS99 white-chrome pass). Passive info carries no
-- plate: the charcoal card, its border stroke and the amber accent bar are
-- gone. What remains floats straight on the world as white bubble text with
-- the house dark-navy #313D4F Contextual stroke, plus one THIN minimal track
-- (dark navy #2E3A4C) with a CYAN #39D7F5 fill -- cyan is the progress colour;
-- gold is reserved for real money, so the amber left with the old card.
-- READY! keeps green (act/ready); the dismiss x is a small pink-red glyph.
-- ============================================================================
local C = {
	ink      = Color3.fromRGB(49, 61, 79),    -- #313D4F bubble-text stroke
	trackBg  = Color3.fromRGB(46, 58, 76),    -- #2E3A4C thin track
	progress = Color3.fromRGB(57, 215, 245),  -- #39D7F5 progress numbers + fill
	ready    = Color3.fromRGB(99, 222, 67),   -- #63DE43 house act/ready green
	dismiss  = Color3.fromRGB(255, 93, 128),  -- #FF5D80 dismiss glyph
	dismissH = Color3.fromRGB(255, 141, 166), -- its hover lift
	white    = Color3.fromRGB(255, 255, 255),
}
local FONT = Enum.Font.FredokaOne

-- the bubble-text outline every naked label wears: Contextual (glyph-hugging),
-- not Border -- there are no boxes left to border
local function inkStroke(obj, thickness)
	local s = Instance.new("UIStroke")
	s.Color = C.ink
	s.Thickness = thickness or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = obj
	return s
end

local function label(parent, size, colour, xAlign)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Text = ""
	l.Font = FONT
	l.TextSize = size
	l.TextColor3 = colour
	l.TextXAlignment = xAlign or Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Parent = parent
	return l
end

-- NO PLATE (naked restyle): the old ClaimRing helper, charcoal plate and amber
-- accent bar are gone. Children hang straight off `root`, which is already
-- transparent, and the READY! pulse now lives on the text itself (see the
-- QuestState handler at the bottom).

-- goal text: naked white bubble text floating on the world
local title = label(root, 14, C.white)
title.Position = UDim2.fromOffset(14, 11)
title.Size = UDim2.fromOffset(W - 14 - 88, 20)
title.TextTruncate = Enum.TextTruncate.AtEnd
title.ZIndex = root.ZIndex + 1
inkStroke(title, 2)

-- "GOAL" kind tag: small white outlined caps -- the boxed amber chip lost its
-- hairline border and its gold along with the plate (gold = real money only)
local chip = label(root, 9, C.white, Enum.TextXAlignment.Center)
chip.Name = "Kind"
chip.AnchorPoint = Vector2.new(1, 0)
chip.Position = UDim2.new(1, -32, 0, 12)
chip.AutomaticSize = Enum.AutomaticSize.X
chip.Size = UDim2.fromOffset(0, 17)
chip.Text = "G O A L"
chip.ZIndex = root.ZIndex + 1
inkStroke(chip, 1)

-- THIN minimal progress row: dark navy track, CYAN fill (cyan = progress; the
-- old amber fill went with the card), right-aligned n/m beside it
local track = Instance.new("Frame")
track.Name = "Track"
track.AnchorPoint = Vector2.new(0, 0.5)
track.Position = UDim2.new(0, 14, 0, 44)
track.Size = UDim2.new(1, -74, 0, 3)
track.BackgroundColor3 = C.trackBg
track.BorderSizePixel = 0
track.ZIndex = root.ZIndex + 1
track.Parent = root

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.new(0, 0, 1, 0)
fill.BackgroundColor3 = C.progress
fill.BorderSizePixel = 0
fill.ZIndex = track.ZIndex + 1
fill.Parent = track

local count = label(root, 10, C.progress, Enum.TextXAlignment.Right)
count.Name = "Count"
count.AnchorPoint = Vector2.new(1, 0.5)
count.Position = UDim2.new(1, -14, 0, 44)
count.Size = UDim2.fromOffset(44, 13)
count.ZIndex = root.ZIndex + 1
inkStroke(count, 2)

local readyPulse = nil   -- looping TextTransparency pulse on READY! while claimable
local shownId, shownPct = nil, -1

-- DISMISSIBLE (2026-08-06). This was built as a standing "you are one step from a
-- reward" nudge and had no way off the screen at all -- reported as "it pops up
-- and won't go away". A nudge you cannot close is just clutter, especially on a
-- goal like 0/2 that will sit there for a long time.
--
-- Closing hides the CURRENT goal only. It comes back by itself when there is
-- something new to say -- a different goal takes the lead, or this one turns
-- claimable -- so the bar still does its job and the player still gets to shut
-- it up. Deliberately not persisted: a fresh session starts with it shown again.
local dismissedId = nil

local close = Instance.new("TextButton")
close.Name = "Dismiss"
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -8, 0, 9)
-- 20x20 AUTHORED, 12x12 RENDERED on a phone once Platform.Widget() has scaled
-- this bar down -- under a third of Roblox's 44px minimum, on the only control
-- that makes this nudge go away. The bar exists because "it pops up and won't go
-- away" was a player report; a dismiss button too small to hit reintroduces
-- exactly that complaint.
--
-- The GLYPH stays small -- a big X would shout louder than the nudge it closes.
-- What grows is the hit area, via a transparent oversized child, which is the
-- pattern already used by the scooter card and the quest rail. Sized against the
-- scale this bar wears so the RENDERED target clears the floor.
close.Size = UDim2.fromOffset(20, 20)
close.BackgroundTransparency = 1
close.BorderSizePixel = 0
close.Text = "\u{00D7}"
close.Font = FONT
close.TextSize = 14
close.TextColor3 = C.dismiss
close.AutoButtonColor = false
close.ZIndex = root.ZIndex + 2
close.Parent = root
-- naked pink-red glyph -- the bordered box went with the plate. The 20x20 hit
-- target stays; hover lifts the glyph colour now there is no stroke to tint.
inkStroke(close, 1)
close.MouseEnter:Connect(function() close.TextColor3 = C.dismissH end)
close.MouseLeave:Connect(function() close.TextColor3 = C.dismiss end)

-- Slide out right, the direction the quest fold already leaves in, instead
-- of vanishing in one frame (2026-08-10 user capture: every state change on
-- this bar was a pop). Position tweens are on the proven-working list;
-- restore the home Position after hiding so re-shows land where they belong.
-- (HOME_POS itself is declared above dismissBar -- see the note there.)
close.MouseButton1Click:Connect(function()
	dismissedId = shownId
	dismissBar()
end)

-- THE HIT AREA, not the glyph.
--
-- close is authored 20x20 and RENDERS 12x12 on a phone once Platform.Widget()
-- has scaled this bar down -- under a third of Roblox's 44px minimum, on the one
-- control that makes this nudge go away. This bar exists because "it pops up and
-- won't go away" was a player report; a dismiss button too small to hit hands
-- that complaint straight back.
--
-- The X stays small, because a 44px glyph would shout louder than the nudge it
-- closes. What grows is a transparent oversized child -- the same pattern the
-- scooter card and the quest rail already use. Sized against the scale this bar
-- wears, so the target clears the floor ON THE GLASS rather than in design units.
do
	local HudLayout = require(modules:WaitForChild("HudLayout"))
	local hit = Instance.new("TextButton")
	hit.Name = "DismissHit"
	hit.AnchorPoint = Vector2.new(0.5, 0.5)
	hit.Position = UDim2.fromScale(0.5, 0.5)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.ZIndex = close.ZIndex + 1
	hit.Parent = close
	Platform.Watch(function()
		if not Platform.IsTouch then
			hit.Size = UDim2.fromScale(1, 1)
			return
		end
		local s = math.max(Platform.Widget(), 0.01)
		local need = math.ceil(HudLayout.MIN_TOUCH / s)
		hit.Size = UDim2.fromOffset(math.max(need, 20), math.max(need, 20))
	end)
	-- Same effect as pressing the X, routed through the same signal so there is
	-- one dismiss path rather than two copies of the tween.
	hit.MouseButton1Click:Connect(function()
		dismissedId = shownId
		dismissBar()
	end)
end

-- NOT HANDED TO HudLayout, and that is deliberate (2026-08-26).
--
-- Attaching it looked obviously right -- `HudLayout.Order.QuestBar` has existed
-- since the stacks were written -- and it was wrong for two reasons that only
-- showed up once it was live:
--
--   TWO WRITERS. This bar rides HudToggleClient's fold: the fold owns its
--   Position while quests are hidden, which on a phone is the DEFAULT state, and
--   parks it off to the right. A stack that also writes Position is exactly the
--   race HudLayout exists to remove, reintroduced by the module meant to fix it.
--
--   IT SPENDS A BAND IT DOES NOT USE. StackBudgets counts a member whether or not
--   the fold has it parked off-screen, so an invisible bar took 31px of
--   BottomCentre's 140 and pushed that stack to 145/140 -- an overflow reported
--   against furniture the player cannot see.
--
-- The collision this was meant to fix (the bar over SprintButton) is handled at
-- the other end instead: RIDE leaves the corner on a short phone, so the column
-- is no longer full, and the bar only appears at all when quests are unfolded.
-- If it is ever attached, the fold has to stop writing Position first.
--
-- PrepareGui still runs: it costs nothing, puts this gui on the one inset model
-- the stacks use, and settles the DisplayOrder tie the handoff flagged (QuestBarUI
-- and QuestTrackerUI both sat on 4, so which drew on top was decided by script
-- execution order).
do
	local HudLayout = require(modules:WaitForChild("HudLayout"))
	HudLayout.PrepareGui(gui, "Tracker")
end

-- NEAREST TO COMPLETE, in priority order:
--   1. unclaimed AND met  -> ready to claim, the strongest possible "you are one
--      click from a reward" signal, so it outranks any fraction
--   2. otherwise the highest Cur/Target fraction
--   3. ties broken by list order, which is authored easiest-first
local function pick(list)
	local best, bestPct, bestIdx
	for i, q in ipairs(list) do
		if not q.Claimed then
			local target = tonumber(q.Target) or 1
			local cur = tonumber(q.Cur) or 0
			local pct = target > 0 and math.clamp(cur / target, 0, 1) or 0
			if q.Met then pct = 1 end
			if not best or pct > bestPct + 1e-6 or (math.abs(pct - bestPct) <= 1e-6 and i < bestIdx) then
				best, bestPct, bestIdx = q, pct, i
			end
		end
	end
	return best, bestPct or 0
end

remotes.QuestState.OnClientEvent:Connect(function(list)
	if typeof(list) ~= "table" then return end
	local q, pct = pick(list)
	if not q then
		-- every goal claimed: nothing to show rather than a full empty bar
		root.Visible = false
		shownId, shownPct = nil, -1
		return
	end

	-- Closed by the player and still the same un-claimable goal: stay shut. Kept
	-- BEFORE the fill/label work so a dismissed bar does no tweening off-screen.
	if dismissedId == q.Id and not q.Met then
		root.Visible = false
		shownId, shownPct = q.Id, pct
		return
	end
	dismissedId = nil
	root.Visible = true

	local target = tonumber(q.Target) or 1
	local cur = tonumber(q.Cur) or 0
	title.Text = tostring(q.Desc or "")
	if q.Met then
		count.Text = "READY!"
		count.TextColor3 = C.ready   -- act/ready green, naked outlined text
	else
		count.Text = formatNumber(cur) .. "/" .. formatNumber(target)
		count.TextColor3 = C.progress   -- cyan = progress numbers
		count.TextTransparency = 0
	end

	-- Re-targeting to a DIFFERENT quest snaps (the bar now means something else,
	-- so animating between two unrelated values would read as progress that did
	-- not happen). Progress WITHIN the same quest animates.
	local sameQuest = (shownId == q.Id)
	if not sameQuest or shownPct < 0 then
		UI.setFill(fill, pct, false)
	elseif math.abs(pct - shownPct) > 1e-4 then
		UI.setFill(fill, pct, true)   -- T.tween.bar: 0.40s Quad/Out
	end
	shownId, shownPct = q.Id, pct

	-- READY! pulse only while it is actually claimable. Retargeted from the old
	-- plate ClaimRing to the text itself -- there is no plate left to ring. The
	-- tween drives TextLabel.TextTransparency, a GuiObject property on the
	-- proven-working tween path (a UIStroke pulse would be a silent no-op here).
	if q.Met and not readyPulse then
		readyPulse = TweenService:Create(count,
			TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ TextTransparency = 0.5 })
		readyPulse:Play()
	elseif not q.Met and readyPulse then
		readyPulse:Cancel()
		readyPulse = nil
		count.TextTransparency = 0
	end
end)
