-- QuestBarClient: ONE always-visible progress bar for the Goals board.
--
-- CLAUDE.md asks for something visibly close to completing at all times; there
-- were zero progress indicators anywhere. This is the first of the three bars --
-- deliberately only the quest one this round.
--
-- Built from the UIKit primitives that already shipped and had ZERO call sites:
-- UI.track / UI.setFill / UI.claimRing. setFill tweens with T.tween.bar
-- (0.40s Quad/Out), so the fill is never snapped.
--
-- NOT a panel and not the retired QuestUI: its own small ScreenGui pinned under
-- the currency cluster (top-left 18,18 + pill height 54). That band is free --
-- the rail is vertically centred, the tabs are top-centre, and panels are
-- canvas-centred so they never reach x < 400 on a real viewport.
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
local formatNumber = require(modules:WaitForChild("NumberFormat")).Short

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local W, H = 300, 62

local gui = Instance.new("ScreenGui")
gui.Name = "QuestBarUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = T.zindex.currency
gui.Parent = player:WaitForChild("PlayerGui")

local root = Instance.new("Frame")
root.Name = "Root"
root.Position = UDim2.fromOffset(18, 18 + T.size.currencyPill + 12)
root.Size = UDim2.fromOffset(W, H)
root.BackgroundTransparency = 1
root.Visible = false          -- until the first payload names a quest
root.Parent = gui

-- match the HUD's uniform fit so this scales with everything else
local scale = Instance.new("UIScale")
scale.Parent = root
local function fit()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize
	scale.Scale = math.min(vp.X / T.size.canvas.X, vp.Y / T.size.canvas.Y)
end
fit()
do
	local cam = workspace.CurrentCamera
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(fit) end
end

local plate = UI.surface(root, UDim2.fromOffset(W, H), "row", T.radius.control, T.stroke.control)

local title = UI.label(plate, "", "chip")
title.Position = UDim2.fromOffset(12, 6)
title.AutomaticSize = Enum.AutomaticSize.None
title.Size = UDim2.fromOffset(W - 100, 18)
title.TextTruncate = Enum.TextTruncate.AtEnd
title.ZIndex = plate.ZIndex + 1

local count = UI.label(plate, "", "chip", T.color.textAccent)
count.AnchorPoint = Vector2.new(1, 0)
count.Position = UDim2.new(1, -12, 0, 6)
count.ZIndex = plate.ZIndex + 1

-- the primitives that shipped unused
local track, fill = UI.track(plate, UDim2.fromOffset(W - 24, 20), "green", T.radius.small)
track.Position = UDim2.fromOffset(12, 30)
track.ZIndex = plate.ZIndex + 1
fill.ZIndex = track.ZIndex + 1

local claimRing = nil
local shownId, shownPct = nil, -1

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
	root.Visible = true

	local target = tonumber(q.Target) or 1
	local cur = tonumber(q.Cur) or 0
	title.Text = tostring(q.Desc or "")
	count.Text = q.Met and "READY!" or (formatNumber(cur) .. " / " .. formatNumber(target))

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

	-- pulsing ring only while it is actually claimable
	if q.Met and not claimRing then
		claimRing = UI.claimRing(plate)
	elseif not q.Met and claimRing then
		claimRing:Destroy()
		claimRing = nil
	end
end)
