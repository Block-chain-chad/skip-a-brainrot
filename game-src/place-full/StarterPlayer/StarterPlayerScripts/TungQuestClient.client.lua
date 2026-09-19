-- TungQuestClient: Elder Tung's NPC front end -- dialogue AND the hand-over picker.
--
-- Tung wants twelve brainrots (5 Epic, 5 Legendary, 2 Mythic) and the PLAYER CHOOSES
-- WHICH ONES, A FEW AT A TIME. Both halves of that matter:
--   * choosing, because the hand-over destroys the items -- picking blind would mean
--     losing a Rainbow Mythic to a quest that would have taken the plain one beside it;
--   * a few at a time, because "come back when you have all twelve" makes the panel
--     useless until the very end. Give him one now and four later; each tier ticks off
--     permanently as it fills.
--
-- Every decision still stays on the server. The picker sends a list of Uids; TungQuest
-- re-resolves each one, re-checks placement and re-checks what is still owed before it
-- removes anything, so this panel can only ever ask.
--
-- Payload from TungState, mirrored here:
--   State  0 not accepted  1 collecting  2 the rest is in hand  3 delivered
--   Tiers  [tierName] = { Have = DELIVERED, Need, Left, Held, Placed }
-- Have is the delivered count, capped at Need -- it is what the quest tracker renders,
-- and it is deliberately NOT a count of what is in the bag.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local modules = ReplicatedStorage:WaitForChild("Modules")

local MerchantDialog = require(modules:WaitForChild("MerchantDialog"))
local TungQuestConfig = require(modules:WaitForChild("TungQuestConfig"))
local BrainrotConfig = require(modules:WaitForChild("BrainrotConfig"))
local RarityConfig = require(modules:WaitForChild("RarityConfig"))
local Mutations = require(modules:WaitForChild("MutationConfig"))
local BrainrotThumb = require(modules:WaitForChild("BrainrotThumb"))
local SideRail = require(modules:WaitForChild("SideRail")) -- single-open coordination
local HudLayout = require(modules:WaitForChild("HudLayout")) -- safe-area panel fitting
local T = require(modules:WaitForChild("UIKit"):WaitForChild("Tokens"))
local UI = require(modules.UIKit:WaitForChild("Builders"))

local okSound, SoundKit = pcall(function() return require(modules.SoundKit) end)
if not okSound then SoundKit = nil end

local talkRemote = remotes:WaitForChild("TungTalk")
local stateRemote = remotes:WaitForChild("TungState")
local dataRemote = remotes:WaitForChild("DataUpdated")

-- his own colours: the wood-brown skin, so his dialogue card is recognisably his
local TUNG = { Color3.fromRGB(198, 150, 96), Color3.fromRGB(146, 98, 54) }
local NAME = "Elder Tung"

local REQS = TungQuestConfig.Requirements
local TOTAL = TungQuestConfig.Total

local infoByName, tierColor = {}, {}
for _, e in ipairs(BrainrotConfig.List or BrainrotConfig) do infoByName[e.Name] = e end
for _, t in ipairs(RarityConfig) do tierColor[t.Name] = t.Color end

local function tierOf(name)
	local info = infoByName[name]
	return info and info.Rarity or nil
end

---------------------------------------------------------------- state
local questState = 0
local tiers = {}          -- [tierName] = { Have, Need, Left, Held, Placed }
local lastNote = nil      -- so the "you can finish this" popup fires on the transition only
local brainrots = {}      -- the live inventory snapshot the picker renders from
local selected = {}       -- [uid] = true
local anchorPart = nil    -- Tung's prompt host, for the walk-away close

local function tierInfo(tier)
	local t = tiers[tier]
	local need = TungQuestConfig.ByTier[tier] or 0
	if not t then return { Have = 0, Need = need, Left = need, Held = 0, Placed = 0 } end
	return t
end

-- "Epic 3/5   *   Legendary 0/5   *   Mythic 0/2" -- DELIVERED over required, in the
-- config's own order, so the line can never disagree with the quota the server checks.
local function progressLine()
	local bits = {}
	for _, r in ipairs(REQS) do
		local t = tierInfo(r.Tier)
		bits[#bits + 1] = ("%s %d/%d"):format(r.Tier, math.min(t.Have, r.Count), r.Count)
	end
	return table.concat(bits, "   \u{2022}   ")
end

local function valueOf(entry)
	local info = infoByName[entry.Name]
	return (info and info.CashPerSecond or 0) * Mutations.Mult(entry.Mutation)
end

local function shortNum(n)
	if n >= 1e9 then return ("%.1fB"):format(n / 1e9) end
	if n >= 1e6 then return ("%.1fM"):format(n / 1e6) end
	if n >= 1e3 then return ("%.1fK"):format(n / 1e3) end
	return ("%d"):format(n)
end

-- how many of a tier are currently ticked
local function selectedCount(tier)
	local n = 0
	for _, e in ipairs(brainrots) do
		if selected[e.Uid] and tierOf(e.Name) == tier then n += 1 end
	end
	return n
end

local function totalSelected()
	local n = 0
	for _ in pairs(selected) do n += 1 end
	return n
end

---------------------------------------------------------------- panel shell
local gui = Instance.new("ScreenGui")
gui.Name = "TungOfferUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 13          -- above MerchantDialog (12): the dialogue opens this
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local scrim = Instance.new("TextButton")
scrim.Name = "Scrim"
scrim.Size = UDim2.fromScale(1, 1)
scrim.BackgroundColor3 = T.scrim
scrim.BackgroundTransparency = T.scrimAlpha
scrim.BorderSizePixel = 0
scrim.Text = ""
scrim.AutoButtonColor = false
scrim.ZIndex = 1
scrim.Parent = gui

local PANEL_W, PANEL_H = 760, 560
local panel = UI.surface(gui, UDim2.fromOffset(PANEL_W, PANEL_H), "panel", T.radius.panel, T.stroke.panel)
panel.Name = "OfferPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.ZIndex = 2
UI.gloss(panel, T.radius.panel)

-- ONE UIScale does double duty: the open-pop tween AND the fit-to-screen factor (only
-- one UIScale applies per object, so they cannot be separate instances). Every tween
-- below therefore targets fitScale(), never a bare 1 -- a 760px panel does not fit the
-- portrait Studio playtest window, let alone a phone.
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

-- Was: the RAW camera viewport, minus a flat 24px, floored at 0.45 -- an exact
-- copy of MichelQuestClient's, with the same two faults. The raw viewport counts
-- the topbar and the touch-control band as usable space (390px against a real
-- 220px on a phone), and the 0.45 floor then overruled the correct answer on
-- precisely the screens that needed it. Measured at 255% of usable height.
local function fitScale()
	return HudLayout.FitPanelScale(PANEL_W, PANEL_H, 12, 0.3)
end

HudLayout.WatchDevice(function()
	if gui.Enabled then panelScale.Scale = fitScale() end
end)

local title = UI.label(panel, TungQuestConfig.PickTitle, "buttonL")
title.Position = UDim2.fromOffset(22, 14)
title.ZIndex = 4

local hint = UI.label(panel, TungQuestConfig.PickHint, "meta", T.color.textMuted)
hint.Position = UDim2.fromOffset(24, 54)
hint.ZIndex = 4

local closeX = UI.button(panel, "\u{2715}", "red", UDim2.fromOffset(52, 46))
closeX.Name = "Close"
closeX.AnchorPoint = Vector2.new(1, 0)
closeX.Position = UDim2.new(1, -18, 0, 14)
closeX.ZIndex = 6

---------------------------------------------------------------- tier chips
local chipRow = Instance.new("Frame")
chipRow.Name = "Quota"
chipRow.Position = UDim2.fromOffset(22, 80)
chipRow.Size = UDim2.new(1, -44, 0, 44)
chipRow.BackgroundTransparency = 1
chipRow.ZIndex = 4
chipRow.Parent = panel

local chipLayout = Instance.new("UIListLayout")
chipLayout.FillDirection = Enum.FillDirection.Horizontal
chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
chipLayout.Padding = UDim.new(0, 10)
chipLayout.Parent = chipRow

local chips = {}
for i, r in ipairs(REQS) do
	local chip = UI.surface(chipRow, UDim2.fromOffset(184, 44), "slot", T.radius.chip, T.stroke.chip)
	chip.LayoutOrder = i
	chip.ZIndex = 4
	local st = chip:FindFirstChildOfClass("UIStroke")
	if st then st.Color = tierColor[r.Tier] or T.color.outline end

	local lbl = UI.label(chip, ("%s 0/%d"):format(r.Tier, r.Count), "cardLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.AutomaticSize = Enum.AutomaticSize.None
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.ZIndex = 5
	chips[r.Tier] = { frame = chip, label = lbl, stroke = st }
end

---------------------------------------------------------------- grid
local TILE_W, TILE_H, GAP = 108, 136, 10

local grid = Instance.new("ScrollingFrame")
grid.Name = "Grid"
grid.Position = UDim2.fromOffset(22, 134)
grid.Size = UDim2.new(1, -44, 1, -134 - 86)
grid.BackgroundTransparency = 1
grid.BorderSizePixel = 0
grid.ScrollBarThickness = 6
grid.ScrollBarImageColor3 = T.color.scrollThumb
grid.CanvasSize = UDim2.new()
grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
grid.ScrollingDirection = Enum.ScrollingDirection.Y
grid.ZIndex = 4
grid.Parent = panel

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(TILE_W, TILE_H)
gridLayout.CellPadding = UDim2.fromOffset(GAP, GAP)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = grid

-- Parented to the PANEL, not the grid: a TextLabel under a UIGridLayout is laid out as
-- a cell, so an empty-state line inside the grid would sit in the first tile slot.
local empty = UI.label(panel, "", "cardLabel", T.color.textMuted)
empty.Position = UDim2.fromOffset(26, 150)
empty.Size = UDim2.new(1, -52, 0, 80)
empty.AutomaticSize = Enum.AutomaticSize.None
empty.TextWrapped = true
empty.Visible = false
empty.ZIndex = 5

---------------------------------------------------------------- footer
local function slot(name, x, w)
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0, 1)
	f.Position = UDim2.new(0, x, 1, -18)
	f.Size = UDim2.fromOffset(w, 56)
	f.BackgroundTransparency = 1
	f.ZIndex = 6
	f.Parent = panel
	return f
end

local autoBtn = UI.button(slot("AutoSlot", 22, 236), "AUTO-PICK CHEAPEST", "blue", UDim2.fromOffset(236, 56))
autoBtn.ZIndex = 7
local autoLabel = autoBtn:FindFirstChildWhichIsA("TextLabel")
if autoLabel then autoLabel.TextSize = 18; autoLabel.ZIndex = 8 end

local clearBtn = UI.button(slot("ClearSlot", 268, 150), "CLEAR", "tab", UDim2.fromOffset(150, 56))
clearBtn.ZIndex = 7
local clearLabel = clearBtn:FindFirstChildWhichIsA("TextLabel")
if clearLabel then clearLabel.TextSize = 18; clearLabel.ZIndex = 8 end

local giveSlot = Instance.new("Frame")
giveSlot.Name = "GiveSlot"
giveSlot.AnchorPoint = Vector2.new(1, 1)
giveSlot.Position = UDim2.new(1, -22, 1, -18)
giveSlot.Size = UDim2.fromOffset(272, 56)
giveSlot.BackgroundTransparency = 1
giveSlot.ZIndex = 6
giveSlot.Parent = panel

local giveBtn = UI.button(giveSlot, "HAND OVER", "green", UDim2.fromOffset(272, 56))
giveBtn.ZIndex = 7
local giveLabel = giveBtn:FindFirstChildWhichIsA("TextLabel")
if giveLabel then giveLabel.TextSize = 20; giveLabel.ZIndex = 8 end
local giveGrad = giveBtn:FindFirstChildOfClass("UIGradient")

-- UI.button bakes its variant in at creation, so enable/disable is a re-tint rather
-- than a rebuild -- rebuilding would drop the Activated connection below.
local giveArmed = false
local function armGive(on)
	giveArmed = on
	if giveGrad then giveGrad.Color = on and T.gradient.green or T.gradient.disabled end
	if giveLabel then giveLabel.TextColor3 = on and T.color.white or T.color.textDisabled end
end

---------------------------------------------------------------- tiles
local tiles = {}          -- [uid] = { root, ring, tick, tint }

-- Chip reads DELIVERED + TICKED over the quota, so ticking a tile visibly advances the
-- same number the quest tracker shows. It can never exceed Need: toggle() below caps
-- the selection at what is still owed.
local function refreshChips()
	for _, r in ipairs(REQS) do
		local t = tierInfo(r.Tier)
		local n = math.min(t.Have, r.Count) + selectedCount(r.Tier)
		local c = chips[r.Tier]
		c.label.Text = ("%s %d/%d"):format(r.Tier, n, r.Count)
		local met = (n >= r.Count)
		c.label.TextColor3 = met and T.color.claimRing or T.color.white
		if c.stroke then c.stroke.Color = met and T.color.claimRing or (tierColor[r.Tier] or T.color.outline) end
	end
	local n = totalSelected()
	if giveLabel then
		giveLabel.Text = (n > 0) and ("HAND OVER %d"):format(n) or "HAND OVER"
	end
	-- ANY non-empty selection is a legal delivery -- that is the whole point of letting
	-- him take them a few at a time.
	armGive(n > 0)
end

local function paintTile(uid)
	local t = tiles[uid]
	if not t then return end
	local on = selected[uid] == true
	t.ring.Color = on and T.color.claimRing or (t.tint or T.color.outline)
	t.ring.Thickness = on and 5 or T.stroke.chip
	t.tick.Visible = on
end

local function nudgeChip(tier)
	local c = chips[tier]
	if not c then return end
	c.frame.Rotation = 2
	TweenService:Create(c.frame, T.tween.pop, { Rotation = 0 }):Play()
end

local function toggle(entry)
	local uid = entry.Uid
	if selected[uid] then
		selected[uid] = nil
	else
		local tier = tierOf(entry.Name)
		local t = tier and tiers[tier]
		if not t then return end
		-- cap at what is STILL OWED, not at the full quota: handing over a sixth Epic
		-- after five are already delivered destroys an item for nothing
		if selectedCount(tier) >= t.Left then
			if SoundKit then pcall(function() SoundKit.play("panelClose", nil, { volume = 0.18 }) end) end
			nudgeChip(tier)
			return
		end
		selected[uid] = true
	end
	if SoundKit then pcall(function() SoundKit.play("uiClick", nil, { volume = 0.16 }) end) end
	paintTile(uid)
	refreshChips()
end

local function buildTile(entry, order)
	local tint = tierColor[tierOf(entry.Name)] or T.color.outline

	local btn = Instance.new("TextButton")
	btn.Name = "Tile" .. tostring(entry.Uid)
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.BackgroundColor3 = T.color.white
	btn.BorderSizePixel = 0
	btn.LayoutOrder = order
	btn.ZIndex = 5
	btn.Parent = grid
	UI.corner(btn, T.radius.slot)
	UI.gradient(btn, T.gradient.slot)
	local ring = UI.stroke(btn, T.stroke.chip)
	ring.Color = tint

	-- the real creature, same viewport helper the Index and Backpack grids use
	local art = Instance.new("Frame")
	art.Size = UDim2.new(1, -10, 0, 78)
	art.Position = UDim2.fromOffset(5, 6)
	art.BackgroundTransparency = 1
	art.ZIndex = 6
	art.Parent = btn
	if not BrainrotThumb.add(art, entry.Name, { zIndex = 6 }) then
		-- no model for that name: a flat rarity swatch rather than an empty hole
		local sw = Instance.new("Frame")
		sw.Size = UDim2.fromScale(1, 1)
		sw.BackgroundColor3 = tint
		sw.BorderSizePixel = 0
		sw.ZIndex = 6
		sw.Parent = art
		UI.corner(sw, T.radius.art)
	end

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(1, -8, 0, 16)
	nameLbl.Position = UDim2.fromOffset(4, 86)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = Enum.Font.GothamBold
	nameLbl.TextSize = 11
	nameLbl.TextColor3 = T.color.white
	nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
	nameLbl.Text = entry.Name
	nameLbl.ZIndex = 7
	nameLbl.Parent = btn

	local metaLbl = Instance.new("TextLabel")
	metaLbl.Size = UDim2.new(1, -8, 0, 14)
	metaLbl.Position = UDim2.fromOffset(4, 102)
	metaLbl.BackgroundTransparency = 1
	metaLbl.Font = Enum.Font.GothamMedium
	metaLbl.TextSize = 11
	metaLbl.TextColor3 = Mutations.Color(entry.Mutation) or T.color.textMuted
	metaLbl.TextTruncate = Enum.TextTruncate.AtEnd
	metaLbl.Text = entry.Mutation and (entry.Mutation .. " \u{2022} $" .. shortNum(valueOf(entry)) .. "/s")
		or ("$" .. shortNum(valueOf(entry)) .. "/s")
	metaLbl.ZIndex = 7
	metaLbl.Parent = btn

	local tierLbl = Instance.new("TextLabel")
	tierLbl.Size = UDim2.new(1, -8, 0, 14)
	tierLbl.Position = UDim2.fromOffset(4, 118)
	tierLbl.BackgroundTransparency = 1
	tierLbl.Font = Enum.Font.GothamBold
	tierLbl.TextSize = 10
	tierLbl.TextColor3 = tint
	tierLbl.Text = tierOf(entry.Name) or ""
	tierLbl.ZIndex = 7
	tierLbl.Parent = btn

	local tick = Instance.new("TextLabel")
	tick.Name = "Tick"
	tick.AnchorPoint = Vector2.new(1, 0)
	tick.Position = UDim2.new(1, -4, 0, 4)
	tick.Size = UDim2.fromOffset(24, 24)
	tick.BackgroundColor3 = T.color.claimRing
	tick.BorderSizePixel = 0
	tick.Font = Enum.Font.GothamBlack
	tick.TextSize = 15
	tick.TextColor3 = T.color.textOnLight
	tick.Text = "\u{2713}"
	tick.Visible = false
	tick.ZIndex = 9
	tick.Parent = btn
	UI.corner(tick, T.radius.pill)

	tiles[entry.Uid] = { root = btn, ring = ring, tick = tick, tint = tint }
	btn.Activated:Connect(function() toggle(entry) end)
end

-- Only tiers Tung STILL WANTS get tiles, in the config's own order, cheapest first
-- inside each group -- the copies a player is most likely to part with come first, and
-- a finished tier simply stops offering its brainrots up for destruction.
local function rebuild()
	for _, child in ipairs(grid:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end
	tiles = {}

	local byTier = {}
	local wanted = 0
	for _, r in ipairs(REQS) do
		if tierInfo(r.Tier).Left > 0 then byTier[r.Tier] = {}; wanted += 1 end
	end

	local placedWanted = 0
	for _, e in ipairs(brainrots) do
		local bucket = byTier[tierOf(e.Name)]
		if bucket and e.Uid then
			if e.PadIndex == nil then bucket[#bucket + 1] = e else placedWanted += 1 end
		end
	end

	-- drop ticks for anything sold, placed, traded away or no longer wanted
	local live = {}
	for _, bucket in pairs(byTier) do
		for _, e in ipairs(bucket) do live[e.Uid] = true end
	end
	for uid in pairs(selected) do
		if not live[uid] then selected[uid] = nil end
	end

	local order = 0
	for _, r in ipairs(REQS) do
		local bucket = byTier[r.Tier]
		if bucket then
			table.sort(bucket, function(a, b)
				local va, vb = valueOf(a), valueOf(b)
				if va == vb then return (a.Uid or 0) < (b.Uid or 0) end
				return va < vb
			end)
			for _, e in ipairs(bucket) do
				order += 1
				buildTile(e, order)
			end
		end
	end

	empty.Visible = (order == 0)
	if order == 0 then
		if wanted == 0 then
			empty.Text = "Tung has everything he asked for."
		else
			local missing = {}
			for _, r in ipairs(REQS) do
				local t = tierInfo(r.Tier)
				if t.Left > 0 then missing[#missing + 1] = ("%d %s"):format(t.Left, r.Tier) end
			end
			empty.Text = ("Nothing in hand that Tung still wants. He is waiting on %s.")
				:format(table.concat(missing, ", "))
		end
	end
	hint.Text = (placedWanted > 0)
		and ("%s  (%d on your base -- store them to offer those)"):format(TungQuestConfig.PickHint, placedWanted)
		or TungQuestConfig.PickHint

	for uid in pairs(selected) do paintTile(uid) end
	refreshChips()
end

---------------------------------------------------------------- open / close
local walkAwayConn = nil

-- SINGLE-OPEN. Registered as a SCREENGUI, not a panel: this surface shows and
-- hides by toggling gui.Enabled and leaves OfferPanel.Visible true the whole
-- time, so registering the frame would read as permanently open and jam every
-- other panel shut. Closing it externally is identical to closePanel below,
-- which is also what clicking the scrim does -- no offer is lost.
SideRail.registerScreenGui(gui)

local function closePanel()
	gui.Enabled = false
	if walkAwayConn then walkAwayConn:Disconnect(); walkAwayConn = nil end
end

local function openPanel()
	selected = {}
	rebuild()
	gui.Enabled = true
	local fit = fitScale()
	panelScale.Scale = fit * 0.88
	TweenService:Create(panelScale, T.tween.panelOpen, { Scale = fit }):Play()
	if SoundKit then pcall(function() SoundKit.play("panelOpen", nil, { volume = 0.14 }) end) end

	if walkAwayConn then walkAwayConn:Disconnect() end
	walkAwayConn = RunService.Heartbeat:Connect(function()
		if not gui.Enabled or not anchorPart then return end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - anchorPart.Position).Magnitude > 32 then closePanel() end
	end)
end

-- The Camera.ViewportSize listener that used to sit here is replaced by the
-- HudLayout.WatchDevice call beside fitScale(): Watch fires on viewport changes
-- too, and additionally on a device-class change and on the device preview, so
-- one subscription covers strictly more than the old one did.

closeX.Activated:Connect(closePanel)
scrim.Activated:Connect(closePanel)
clearBtn.Activated:Connect(function()
	selected = {}
	for uid in pairs(tiles) do paintTile(uid) end
	refreshChips()
end)

autoBtn.Activated:Connect(function()
	-- mirrors the server's own auto-pick (cheapest first, up to what is still owed) so
	-- the tiles the player sees ticked are exactly the ones that would be taken
	selected = {}
	local byTier = {}
	for _, r in ipairs(REQS) do byTier[r.Tier] = {} end
	for _, e in ipairs(brainrots) do
		local bucket = byTier[tierOf(e.Name)]
		if bucket and e.Uid and e.PadIndex == nil then bucket[#bucket + 1] = e end
	end
	for _, r in ipairs(REQS) do
		local bucket = byTier[r.Tier]
		table.sort(bucket, function(a, b)
			local va, vb = valueOf(a), valueOf(b)
			if va == vb then return (a.Uid or 0) < (b.Uid or 0) end
			return va < vb
		end)
		for i = 1, math.min(tierInfo(r.Tier).Left, #bucket) do selected[bucket[i].Uid] = true end
	end
	for uid in pairs(tiles) do paintTile(uid) end
	refreshChips()
end)

giveBtn.Activated:Connect(function()
	if not giveArmed then return end
	local uids = {}
	for uid in pairs(selected) do uids[#uids + 1] = uid end
	if #uids == 0 then return end
	talkRemote:FireServer("offer", uids)
	-- deliberately STAYS OPEN: a partial hand-over is meant to be followed by another.
	-- The server's DataUpdated/TungState pushes rebuild the grid with what is left, and
	-- the "key" note closes the panel when the last one lands.
	selected = {}
	refreshChips()
end)

-- the panel renders from the same snapshot every other inventory UI reads
local function applySnapshot(snap)
	if typeof(snap) ~= "table" then return end
	if snap.Brainrots then
		brainrots = snap.Brainrots
		if gui.Enabled then rebuild() end
	end
end
dataRemote.OnClientEvent:Connect(applySnapshot)
task.spawn(function()
	local ok, snap = pcall(function() return remotes.GetInitialData:InvokeServer() end)
	if ok then applySnapshot(snap) end
end)

---------------------------------------------------------------- NPC prompt
-- Find the prompt by NAME anywhere in Workspace rather than by a fixed path: the model
-- has already moved once (AuxScene -> GameWorld) and a hardcoded path would silently
-- stop finding him the next time.
local function findPrompt()
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == "TungTalkPrompt" then return d end
	end
	return nil
end

task.spawn(function()
	local prompt
	for _ = 1, 60 do
		prompt = findPrompt()
		if prompt then break end
		task.wait(0.5)
	end
	if not prompt then
		warn("[TungQuestClient] no TungTalkPrompt found in Workspace -- is Elder Tung in the place?")
		return
	end
	local host = prompt.Parent
	anchorPart = host:IsA("BasePart") and host or host:FindFirstChildWhichIsA("BasePart")

	prompt.Triggered:Connect(function(who)
		if who ~= player then return end

		if questState >= 3 then
			MerchantDialog.Show(NAME, { TungQuestConfig.Done }, TUNG, nil, host, "OK \u{25B6}")

		elseif questState == 2 then
			MerchantDialog.Show(NAME, {
				TungQuestConfig.Ready,
				progressLine(),
			}, TUNG, openPanel, host, "CHOOSE WHAT TO GIVE \u{25B6}")

		elseif questState == 1 then
			-- The picker is reachable while still short, deliberately: he takes them a
			-- few at a time, so there is always something worth handing over.
			MerchantDialog.Show(NAME, {
				TungQuestConfig.Nag,
				progressLine(),
			}, TUNG, openPanel, host, "HAND SOME OVER \u{25B6}")

		else
			MerchantDialog.Show(NAME, {
				TungQuestConfig.Intro,
				("Catch and bring me: %s"):format(progressLine()),
			}, TUNG, function()
				talkRemote:FireServer()          -- anything but offer/claim = accept
			end, host, "TAKE THE JOB \u{25B6}")
		end
	end)
end)

---------------------------------------------------------------- state in
-- Treated as the only source of truth: this script never advances questState on its
-- own, so the dialogue can never offer a step the server has not actually reached.
stateRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end
	questState = payload.State or questState
	tiers = payload.Tiers or tiers

	if payload.Note == "quota" and lastNote ~= "quota" then
		-- Only on the transition INTO "you hold the rest": the server's watcher re-sends
		-- state whenever the inventory moves, and this would otherwise pop a dialogue
		-- every couple of seconds while the player stood there holding them.
		MerchantDialog.Show(NAME, {
			"You have the rest of my list on you. Come and finish it.",
			progressLine(),
		}, TUNG, nil, nil, "ON MY WAY \u{25B6}")
	elseif payload.Note == "key" then
		closePanel()
		MerchantDialog.Show(NAME, {
			TungQuestConfig.Key,
			("Cellar keys: %d"):format(tonumber(payload.Keys) or 0),
		}, TUNG, nil, nil, "TAKE THE KEY \u{25B6}")
	end
	lastNote = payload.Note

	if gui.Enabled then rebuild() end
	-- "capture" fires on every counted catch and "gave" on a partial hand-over; both are
	-- deliberately silent here -- the toast already reports the hand-over, and a long
	-- grind would otherwise pop a dialogue box twelve times.
end)
