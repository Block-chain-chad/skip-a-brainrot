-- MichelQuestClient: Michael's NPC front end -- the dialogue AND the hand-over picker.
--
-- (He is "Michael" to the player and Michel* in code -- see the naming note at the top of
-- MichelQuestConfig. Every player-facing string here comes from that config.)
--
-- He wants five MUTATED Tung Tung Tung Sahurs and pays 1000 emeralds. Deliberately built
-- to the same shape as TungQuestClient, because it is the same interaction: the player
-- picks EXACT copies out of a grid, a few at a time, and each one is destroyed.
--
-- THE ONE REAL DIFFERENCE is what the tiles are coloured by. Elder Tung's picker tints
-- by RARITY, which is the thing that varies across his twelve. Every tile here is the
-- same Mythic, so rarity would paint the whole grid one colour and say nothing -- the
-- MUTATION is the only thing that differs between two of these, and it is exactly what
-- the player is choosing between. So the ring is the mutation's own colour.
--
-- Every decision still stays on the server. The picker sends a list of Uids; MichelQuest
-- re-resolves each one and re-checks name, mutation, placement and what is still owed
-- before it removes anything, so this panel can only ever ask.
--
-- Payload from MichelState, mirrored here:
--   State  0 not accepted  1 collecting  2 the rest is in hand  3 delivered
--   Have (DELIVERED, capped at Need) / Need / Left / Held / Placed
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local modules = ReplicatedStorage:WaitForChild("Modules")

local MerchantDialog = require(modules:WaitForChild("MerchantDialog"))
local CFG = require(modules:WaitForChild("MichelQuestConfig"))
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

local talkRemote = remotes:WaitForChild("MichelTalk")
local stateRemote = remotes:WaitForChild("MichelState")
local dataRemote = remotes:WaitForChild("DataUpdated")

local NAME = CFG.NpcName
local ACCENT = CFG.Accent
local NEED = CFG.Count

local infoByName, tierColor = {}, {}
for _, e in ipairs(BrainrotConfig.List or BrainrotConfig) do infoByName[e.Name] = e end
for _, t in ipairs(RarityConfig) do tierColor[t.Name] = t.Color end
local WANTED_TIER = (infoByName[CFG.Brainrot] and infoByName[CFG.Brainrot].Rarity) or nil
local WANTED_COLOR = (WANTED_TIER and tierColor[WANTED_TIER]) or T.color.outline

---------------------------------------------------------------- state
local questState = 0
local have, left, placedWanted = 0, NEED, 0
local lastNote = nil      -- so the "you can finish this" popup fires on the transition only
local brainrots = {}      -- the live inventory snapshot the picker renders from
local selected = {}       -- [uid] = true
local promptHost = nil    -- Michel's prompt host, for the portrait and the walk-away close

local function totalSelected()
	local n = 0
	for _ in pairs(selected) do n += 1 end
	return n
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

---------------------------------------------------------------- panel shell
local gui = Instance.new("ScreenGui")
gui.Name = "MichelOfferUI"
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
-- one UIScale applies per object). Every tween below therefore targets fitScale(), never
-- a bare 1 -- a 760px panel does not fit a portrait playtest window, let alone a phone.
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

-- Was: the RAW camera viewport, minus a flat 24px, floored at 0.45. Two faults,
-- both only visible on a handset. The raw viewport counts the topbar and the
-- touch-control band as usable space -- 390px against a real 220px on a phone --
-- and the 0.45 floor then overruled the correct answer on exactly the screens
-- that needed it. Measured: this 760x560 panel rendered at 255% of usable height.
-- Reading the camera directly also meant it never responded to Platform at all,
-- so the device preview could not reproduce it.
local function fitScale()
	return HudLayout.FitPanelScale(PANEL_W, PANEL_H, 12, 0.3)
end

local title = UI.label(panel, CFG.PickTitle, "buttonL")
title.Position = UDim2.fromOffset(22, 14)
title.ZIndex = 4

local hint = UI.label(panel, CFG.PickHint, "meta", T.color.textMuted)
hint.Position = UDim2.fromOffset(24, 54)
hint.ZIndex = 4

local closeX = UI.button(panel, "\u{2715}", "red", UDim2.fromOffset(52, 46))
closeX.Name = "Close"
closeX.AnchorPoint = Vector2.new(1, 0)
closeX.Position = UDim2.new(1, -18, 0, 14)
closeX.ZIndex = 6

---------------------------------------------------------------- quota chip
-- One chip, not three: his ask is a single line. It reads DELIVERED + TICKED, so
-- ticking a tile visibly advances the same number the quest tracker shows.
local chip = UI.surface(panel, UDim2.fromOffset(360, 44), "slot", T.radius.chip, T.stroke.chip)
chip.Position = UDim2.fromOffset(22, 80)
chip.ZIndex = 4
local chipStroke = chip:FindFirstChildOfClass("UIStroke")
if chipStroke then chipStroke.Color = WANTED_COLOR end

local chipLabel = UI.label(chip, CFG.ProgressLine(0), "cardLabel")
chipLabel.Size = UDim2.fromScale(1, 1)
chipLabel.AutomaticSize = Enum.AutomaticSize.None
chipLabel.TextXAlignment = Enum.TextXAlignment.Center
chipLabel.ZIndex = 5

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

-- Parented to the PANEL, not the grid: a TextLabel under a UIGridLayout is laid out as a
-- cell, so an empty-state line inside the grid would sit in the first tile slot.
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

-- UI.button bakes its variant in at creation, so enable/disable is a re-tint rather than
-- a rebuild -- rebuilding would drop the Activated connection below.
local giveArmed = false
local function armGive(on)
	giveArmed = on
	if giveGrad then giveGrad.Color = on and T.gradient.green or T.gradient.disabled end
	if giveLabel then giveLabel.TextColor3 = on and T.color.white or T.color.textDisabled end
end

---------------------------------------------------------------- tiles
local tiles = {}          -- [uid] = { root, ring, tick, tint }

local function refreshChip()
	local n = math.min(have, NEED) + totalSelected()
	chipLabel.Text = CFG.ProgressLine(n)
	local met = (n >= NEED)
	chipLabel.TextColor3 = met and T.color.claimRing or T.color.white
	if chipStroke then chipStroke.Color = met and T.color.claimRing or WANTED_COLOR end

	local sel = totalSelected()
	if giveLabel then
		giveLabel.Text = (sel > 0) and ("HAND OVER %d"):format(sel) or "HAND OVER"
	end
	-- ANY non-empty selection is a legal delivery -- that is the whole point of letting
	-- him take them a few at a time.
	armGive(sel > 0)
end

local function paintTile(uid)
	local t = tiles[uid]
	if not t then return end
	local on = selected[uid] == true
	t.ring.Color = on and T.color.claimRing or (t.tint or T.color.outline)
	t.ring.Thickness = on and 5 or T.stroke.chip
	t.tick.Visible = on
end

local function nudgeChip()
	chip.Rotation = 2
	TweenService:Create(chip, T.tween.pop, { Rotation = 0 }):Play()
end

local function toggle(entry)
	local uid = entry.Uid
	if selected[uid] then
		selected[uid] = nil
	else
		-- cap at what is STILL OWED, not at the full quota: handing over a sixth after
		-- five are already delivered destroys an item for nothing
		if totalSelected() >= left then
			if SoundKit then pcall(function() SoundKit.play("panelClose", nil, { volume = 0.18 }) end) end
			nudgeChip()
			return
		end
		selected[uid] = true
	end
	if SoundKit then pcall(function() SoundKit.play("uiClick", nil, { volume = 0.16 }) end) end
	paintTile(uid)
	refreshChip()
end

local function buildTile(entry, order)
	-- see the header: the ring is the MUTATION's colour, because that is the only thing
	-- that differs between two of these and the only thing worth choosing between
	local tint = Mutations.Color(entry.Mutation) or WANTED_COLOR

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
		local sw = Instance.new("Frame")
		sw.Size = UDim2.fromScale(1, 1)
		sw.BackgroundColor3 = tint
		sw.BorderSizePixel = 0
		sw.ZIndex = 6
		sw.Parent = art
		UI.corner(sw, T.radius.art)
	end

	-- MUTATION first and biggest. Every tile is the same creature, so the name is the
	-- least useful line on it and the mutation is the whole decision.
	local mutLbl = Instance.new("TextLabel")
	mutLbl.Size = UDim2.new(1, -8, 0, 16)
	mutLbl.Position = UDim2.fromOffset(4, 86)
	mutLbl.BackgroundTransparency = 1
	mutLbl.Font = Enum.Font.GothamBold
	mutLbl.TextSize = 12
	mutLbl.TextColor3 = tint
	mutLbl.TextTruncate = Enum.TextTruncate.AtEnd
	mutLbl.Text = entry.Mutation or ""
	mutLbl.ZIndex = 7
	mutLbl.Parent = btn

	local metaLbl = Instance.new("TextLabel")
	metaLbl.Size = UDim2.new(1, -8, 0, 14)
	metaLbl.Position = UDim2.fromOffset(4, 103)
	metaLbl.BackgroundTransparency = 1
	metaLbl.Font = Enum.Font.GothamMedium
	metaLbl.TextSize = 11
	metaLbl.TextColor3 = T.color.textMuted
	metaLbl.TextTruncate = Enum.TextTruncate.AtEnd
	metaLbl.Text = "$" .. shortNum(valueOf(entry)) .. "/s"
	metaLbl.ZIndex = 7
	metaLbl.Parent = btn

	local tierLbl = Instance.new("TextLabel")
	tierLbl.Size = UDim2.new(1, -8, 0, 14)
	tierLbl.Position = UDim2.fromOffset(4, 118)
	tierLbl.BackgroundTransparency = 1
	tierLbl.Font = Enum.Font.GothamBold
	tierLbl.TextSize = 10
	tierLbl.TextColor3 = WANTED_COLOR
	tierLbl.Text = WANTED_TIER or ""
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

-- Cheapest first, so the copies a player is most likely to part with come first. Only
-- brainrots that pass the SHARED CFG.Accepts test are offered -- the same function the
-- server validates with, so the panel can never show a tile that would be refused.
local function rebuild()
	for _, child in ipairs(grid:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end
	tiles = {}

	local pool = {}
	local onBase = 0
	for _, e in ipairs(brainrots) do
		if CFG.Accepts(e) and e.Uid then
			if e.PadIndex == nil then pool[#pool + 1] = e else onBase += 1 end
		end
	end

	-- drop ticks for anything sold, placed, traded away or already delivered
	local live = {}
	for _, e in ipairs(pool) do live[e.Uid] = true end
	for uid in pairs(selected) do
		if not live[uid] then selected[uid] = nil end
	end

	table.sort(pool, function(a, b)
		local va, vb = valueOf(a), valueOf(b)
		if va == vb then return (a.Uid or 0) < (b.Uid or 0) end
		return va < vb
	end)

	if left > 0 then
		for i, e in ipairs(pool) do buildTile(e, i) end
	end

	local shown = (left > 0) and #pool or 0
	empty.Visible = (shown == 0)
	if shown == 0 then
		empty.Text = (left <= 0) and CFG.AllDone or CFG.Empty
	end
	hint.Text = (onBase > 0)
		and ("%s  (%d on your base -- store them to offer those)"):format(CFG.PickHint, onBase)
		or CFG.PickHint
	placedWanted = onBase

	for uid in pairs(selected) do paintTile(uid) end
	refreshChip()
end

---------------------------------------------------------------- open / close
local walkAwayConn = nil

-- SINGLE-OPEN. Registered as a SCREENGUI, not a panel: this surface shows and hides by
-- toggling gui.Enabled and leaves OfferPanel.Visible true the whole time, so registering
-- the frame would read as permanently open and jam every other panel shut.
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
		if not gui.Enabled or not promptHost then return end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - promptHost.Position).Magnitude > 32 then closePanel() end
	end)
end

-- Was Camera.ViewportSize alone, which misses a device-class change (a phone
-- reporting late, a controller picked up mid-session) and cannot be driven by the
-- device preview at all -- so this panel's overflow was unreproducible at a desk.
HudLayout.WatchDevice(function()
	if gui.Enabled then panelScale.Scale = fitScale() end
end)

closeX.Activated:Connect(closePanel)
scrim.Activated:Connect(closePanel)
clearBtn.Activated:Connect(function()
	selected = {}
	for uid in pairs(tiles) do paintTile(uid) end
	refreshChip()
end)

autoBtn.Activated:Connect(function()
	-- mirrors the server's own auto-pick (cheapest first, up to what is still owed) so the
	-- tiles the player sees ticked are exactly the ones that would be taken
	selected = {}
	local pool = {}
	for _, e in ipairs(brainrots) do
		if CFG.Accepts(e) and e.Uid and e.PadIndex == nil then pool[#pool + 1] = e end
	end
	table.sort(pool, function(a, b)
		local va, vb = valueOf(a), valueOf(b)
		if va == vb then return (a.Uid or 0) < (b.Uid or 0) end
		return va < vb
	end)
	for i = 1, math.min(left, #pool) do selected[pool[i].Uid] = true end
	for uid in pairs(tiles) do paintTile(uid) end
	refreshChip()
end)

giveBtn.Activated:Connect(function()
	if not giveArmed then return end
	local uids = {}
	for uid in pairs(selected) do uids[#uids + 1] = uid end
	if #uids == 0 then return end
	talkRemote:FireServer("offer", uids)
	-- deliberately STAYS OPEN: a partial hand-over is meant to be followed by another.
	-- The server's DataUpdated/MichelState pushes rebuild the grid with what is left, and
	-- the "reward" note closes the panel when the last one lands.
	selected = {}
	refreshChip()
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

---------------------------------------------------------------- dialogue
-- The refusal, reached from EITHER "no" -- the offer and the confirmation. He says the
-- same thing both times because it is the same answer.
local function showRefusal()
	MerchantDialog.Show(NAME, { CFG.Refuse }, ACCENT, nil, promptHost, "OK \u{25B6}")
end

-- Second gate. RichText is on for this one line so "eagles quest" carries his own gold;
-- MerchantDialog types markup out tag-aware, so the tags never appear on screen.
local function askConfirm()
	MerchantDialog.Show(NAME, { CFG.ConfirmLine() }, ACCENT, function()
		talkRemote:FireServer("accept")
	end, promptHost, "YES", {
		DeclineLabel = "NO",
		OnDecline = showRefusal,
		RichText = true,
	})
end

---------------------------------------------------------------- the prompt
local PROMPT_NAME = "MichelPrompt"

local function speak(host)
	if questState >= 3 then
		MerchantDialog.Show(NAME, { CFG.Done }, ACCENT, nil, host, "OK \u{25B6}")

	elseif questState == 2 then
		MerchantDialog.Show(NAME, {
			CFG.Ready,
			CFG.ProgressLine(have),
		}, ACCENT, openPanel, host, "CHOOSE WHAT TO GIVE \u{25B6}")

	elseif questState == 1 then
		-- The picker is reachable while still short, deliberately: he takes them a few at
		-- a time, so there is always something worth handing over.
		MerchantDialog.Show(NAME, {
			CFG.Nag,
			CFG.ProgressLine(have),
		}, ACCENT, openPanel, host, "HAND SOME OVER \u{25B6}")

	else
		-- THE ASK, in two gates. He states the job, then asks you to confirm it by name --
		-- and "no" at either one gets the same squawk. The grey button only turns into NO
		-- on the last line of each box (see MerchantDialog.opts), so the player is never
		-- shown a choice before they have been asked.
		MerchantDialog.Show(NAME, {
			CFG.Intro1,
			CFG.Intro2,
		}, ACCENT, askConfirm, host, "YES", {
			DeclineLabel = "NO",
			OnDecline = showRefusal,
		})
	end
end

-- STREAMING, and this part has to be right or he cannot be talked to at all.
-- workspace.StreamingEnabled is on and Michael stands 8,000 studs from spawn, so a player
-- in the valley has the Michel MODEL (containers replicate) and NONE of its parts -- his
-- prompt does not exist yet. A one-shot scan at join therefore finds nothing, gives up,
-- and leaves him permanently silent for that whole session. That is not hypothetical: it
-- is what the first version of this file did, and TundraQuestClient's header records the
-- identical bug being fixed there. This is the same fix.
--
-- Scan once for the case where we are already in the tundra, then WATCH. Streaming
-- DESTROYS and recreates the instance rather than reparenting it, so every arrival is a
-- fresh prompt that has to be bound again.
--
-- Scoped to the tundra folder, not Workspace: a DescendantAdded on Workspace fires for
-- every part that streams in anywhere in the game.
local function bindPrompt(prompt)
	local host = prompt.Parent
	if not host then return end
	promptHost = host:IsA("BasePart") and host or host:FindFirstChildWhichIsA("BasePart")
	prompt.Triggered:Connect(function(who)
		if who == player then speak(host) end
	end)
end

task.spawn(function()
	local gw = Workspace:WaitForChild("GameWorld", 60)
	local ft = gw and gw:WaitForChild("FrozenTundra", 60)
	if not ft then
		warn("[MichelQuestClient] no GameWorld.FrozenTundra -- is World 2 in the place?")
		return
	end
	for _, d in ipairs(ft:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == PROMPT_NAME then bindPrompt(d) end
	end
	ft.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") and d.Name == PROMPT_NAME then bindPrompt(d) end
	end)
end)

---------------------------------------------------------------- state in
-- Treated as the only source of truth: this script never advances questState on its own,
-- so the dialogue can never offer a step the server has not actually reached.
stateRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end
	questState = payload.State or questState
	have = tonumber(payload.Have) or have
	left = tonumber(payload.Left) or math.max(0, NEED - have)

	if payload.Note == "quota" and lastNote ~= "quota" then
		-- Only on the transition INTO "you hold the rest": the server's watcher re-sends
		-- state whenever the inventory moves, and this would otherwise pop a dialogue
		-- every couple of seconds while the player stood there holding them.
		MerchantDialog.Show(NAME, {
			CFG.Carrying,
			CFG.ProgressLine(have),
		}, ACCENT, nil, nil, "ON MY WAY \u{25B6}")
	elseif payload.Note == "reward" then
		closePanel()
		MerchantDialog.Show(NAME, {
			CFG.Reward,
			("Gems: %d"):format(tonumber(payload.Darrels) or 0), -- player-facing: Gems (2026-09-18); payload.Darrels is the internal field
		}, ACCENT, nil, nil, "TAKE THE GEMS \u{25B6}")
	end
	lastNote = payload.Note

	if gui.Enabled then rebuild() end
	-- "gave" (a partial hand-over) is deliberately silent here -- the toast already
	-- reports it, and the panel stays open showing what is left.
end)
