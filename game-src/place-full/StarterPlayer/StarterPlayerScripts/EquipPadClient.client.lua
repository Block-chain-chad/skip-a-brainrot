-- EquipPadClient: the confirm that appears when you walk onto your base's
-- AUTO-PLACE pad.
--
-- It asks, and nothing more. Saying yes fires the EXISTING EquipBest remote --
-- the same one the Backpack panel's EQUIP BEST button has always fired -- so all
-- the decisions (what counts as best, how many pads are unlocked, what comes down)
-- stay in InventoryHandler.EquipBest on the server. Nothing here can place
-- anything, which is why it is safe for the pad to be a plain Touched.
--
-- WHY A CONFIRM AT ALL: auto-place is DESTRUCTIVE to an arrangement. It pulls down
-- anything that no longer makes the cut, so a player who has deliberately laid
-- their base out would lose that by walking over a pad. Walking somewhere is not
-- an intention, which is exactly why the pad asks instead of acting.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local modules = ReplicatedStorage:WaitForChild("Modules")

local T = require(modules:WaitForChild("UIKit"):WaitForChild("Tokens"))
local UI = require(modules.UIKit:WaitForChild("Builders"))
local SideRail = require(modules:WaitForChild("SideRail"))   -- single-open coordination
local HudLayout = require(modules:WaitForChild("HudLayout")) -- safe-area panel fitting
local okSound, SoundKit = pcall(function() return require(modules.SoundKit) end)
if not okSound then SoundKit = nil end

local promptRemote = remotes:WaitForChild("EquipPadPrompt")

---------------------------------------------------------------- shell
local PANEL_W, PANEL_H = 560, 300

local gui = Instance.new("ScreenGui")
gui.Name = "EquipPadUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 14
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

local panel = UI.surface(gui, UDim2.fromOffset(PANEL_W, PANEL_H), "panel", T.radius.panel, T.stroke.panel)
panel.Name = "ConfirmPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.ZIndex = 2
UI.gloss(panel, T.radius.panel)

-- One UIScale doing the open-pop AND the fit-to-screen factor, the same way the
-- hand-over pickers do it: only one UIScale applies per object, so they cannot be
-- separate instances and every tween has to target fitScale() rather than 1.
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

-- The third verbatim copy of this formula in the place, with the same two faults:
-- it divides by the RAW viewport (which counts the topbar and the touch-control
-- band as usable) and then floors at 0.45, overruling the correct answer on the
-- short screens that needed it. Measured at 146% of usable height on a phone.
-- Three copies is why fixing one never fixed the symptom.
local function fitScale()
	return HudLayout.FitPanelScale(PANEL_W, PANEL_H, 12, 0.3)
end

local title = UI.label(panel, "PLACE YOUR BEST?", "panelTitle", T.color.white)
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.new(0.5, 0, 0, 26)
title.Size = UDim2.new(1, -40, 0, 40)
title.AutomaticSize = Enum.AutomaticSize.None
title.TextXAlignment = Enum.TextXAlignment.Center
title.ZIndex = 4

local body = UI.label(panel,
	"Your highest-earning brainrots go out onto your base.\n\n"
	.. "Anything already down that no longer makes the cut goes back to your bag.",
	"cardLabel", T.color.textMuted)
body.AnchorPoint = Vector2.new(0.5, 0)
body.Position = UDim2.new(0.5, 0, 0, 84)
body.Size = UDim2.new(1, -64, 0, 110)
body.AutomaticSize = Enum.AutomaticSize.None
body.TextWrapped = true
body.TextXAlignment = Enum.TextXAlignment.Center
body.TextYAlignment = Enum.TextYAlignment.Top
body.ZIndex = 4

local BTN_W, BTN_H = 226, 56
local function slot(name, anchorX, x)
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(anchorX, 1)
	f.Position = UDim2.new(anchorX, x, 1, -22)
	f.Size = UDim2.fromOffset(BTN_W, BTN_H)
	f.BackgroundTransparency = 1
	f.ZIndex = 6
	f.Parent = panel
	return f
end

local noBtn = UI.button(slot("NoSlot", 0, 26), "NO", "tab", UDim2.fromOffset(BTN_W, BTN_H))
noBtn.ZIndex = 7
local noCap = noBtn:FindFirstChildWhichIsA("TextLabel")
if noCap then noCap.TextSize = 20; noCap.ZIndex = 8 end

local yesBtn = UI.button(slot("YesSlot", 1, -26), "PLACE THEM", "green", UDim2.fromOffset(BTN_W, BTN_H))
yesBtn.ZIndex = 7
local yesCap = yesBtn:FindFirstChildWhichIsA("TextLabel")
if yesCap then yesCap.TextSize = 20; yesCap.ZIndex = 8 end

---------------------------------------------------------------- open / close
SideRail.registerScreenGui(gui)

local function close()
	if not gui.Enabled then return end
	gui.Enabled = false
	if SoundKit then pcall(function() SoundKit.play("panelClose", nil, { volume = 0.14 }) end) end
end

local function open()
	-- Already asking? Do nothing. The pad is debounced server-side too, but a
	-- second prompt landing mid-decision would re-pop the panel under the player's
	-- cursor and could turn a NO into a YES.
	if gui.Enabled then return end
	gui.Enabled = true
	local fit = fitScale()
	panelScale.Scale = fit * 0.88
	TweenService:Create(panelScale, T.tween.panelOpen, { Scale = fit }):Play()
	if SoundKit then pcall(function() SoundKit.play("panelOpen", nil, { volume = 0.14 }) end) end
end

if Workspace.CurrentCamera then
	HudLayout.WatchDevice(function()
		-- Was Camera.ViewportSize alone: misses a device-class change and cannot be
		-- driven by the device preview, so this panel's 146%-of-screen overflow was
		-- not reproducible outside a real handset.
		if gui.Enabled then panelScale.Scale = fitScale() end
	end)
end

noBtn.Activated:Connect(close)
scrim.Activated:Connect(close)

yesBtn.Activated:Connect(function()
	close()
	local r = remotes:FindFirstChild("EquipBest")
	if r then r:FireServer() end
	-- no local feedback on purpose: InventoryHandler.EquipBest sends its own toast,
	-- and it is the only thing that knows what actually moved
end)

promptRemote.OnClientEvent:Connect(open)

---------------------------------------------------------------- own-plot only
-- The AUTO-PLACE billboard is built on EVERY plot's pad, but the pad only does
-- anything on YOUR OWN base (PlotEquipPad.onTouched is owner-only), so on every
-- other plot the title is just clutter floating over a button you cannot use.
-- Show it only on the plot(s) this player owns. Ownership is per-player, so this
-- can only be decided on the client; the pad part itself is left alone.
local basesFolder = Workspace:WaitForChild("PlayerBases")

local function ownsPlot(plot)
	return plot:GetAttribute("Claimed") == true
		and plot:GetAttribute("OwnerUserId") == player.UserId
end

local function refreshPadLabels()
	for _, plot in ipairs(basesFolder:GetChildren()) do
		local pad = plot:FindFirstChild("EquipBestPad")
		local label = pad and pad:FindFirstChild("Label")
		if label then label.Enabled = ownsPlot(plot) end
	end
end

-- a claim or unclaim flips ownership; watch both attributes on every plot
local function watchPlot(plot)
	plot:GetAttributeChangedSignal("OwnerUserId"):Connect(refreshPadLabels)
	plot:GetAttributeChangedSignal("Claimed"):Connect(refreshPadLabels)
end
for _, plot in ipairs(basesFolder:GetChildren()) do watchPlot(plot) end
basesFolder.ChildAdded:Connect(function(plot)
	watchPlot(plot)
	task.defer(refreshPadLabels)
end)
-- pads/labels can stream in after this runs; re-apply when one appears
basesFolder.DescendantAdded:Connect(function(d)
	if d.Name == "Label" or d.Name == "EquipBestPad" then task.defer(refreshPadLabels) end
end)

refreshPadLabels()
