-- RebirthClient: the Rebirth prestige panel (with a wipe confirmation).
--
-- 2026-08-09 HUD upgrade (design_handoff_hud_upgrade): the campfire panel is
-- replaced by the sheet's PanelChrome shell -- 900x740, green header, violet
-- summary strip, three stat cards (COST gold / INCOME green / LUCK sky, the
-- numbers ARE the panel), a 46-tall amber warning strip, and a 110 action
-- plate. The in-button two-step confirm becomes a REAL modal dialog at
-- ZIndex 150 (sheet: "the action is destructive and currently one tap away").
--
-- Unchanged: the legacy SideRail tile (invisible rail, but its setReady /
-- setBadge feed GameHUDClient's claim-halo + badge arbitration), the
-- RebirthState/RebirthRequest wiring, single-open registration, and the
-- disarm-on-close rule (any Visible=false must tear the confirm down).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService") -- for the topbar inset; see drawableY below

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local function fmt(n)
	n = math.floor(n)
	if n >= 1e9 then return string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then return string.format("%.0fK", n / 1e3) end
	return tostring(n)
end
local function pct(mult) return ("+%d%%"):format(math.floor((mult - 1) * 100 + 0.5)) end

local gui = Instance.new("ScreenGui")
gui.Name = "RebirthUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 9
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local SideRail = require(ReplicatedStorage.Modules.SideRail)
local tile = SideRail.MakeTile({
	name = "Rebirth", iconKind = "star", layoutOrder = 4,
	hueTop = Color3.fromRGB(199, 123, 240), hueBottom = Color3.fromRGB(154, 46, 214),
	accent = Color3.fromRGB(178, 75, 232),
})
local btn = tile.button

local Platform = require(ReplicatedStorage.Modules.Platform)
local UIKit = ReplicatedStorage.Modules.UIKit
local PC = require(UIKit.PanelChrome)
local S = require(UIKit.SpecTheme)

---------------------------------------------------------------- panel shell
local shell = PC.shell({
	name = "RebirthPanel",
	title = "REBIRTH",
	key = "rebirth",
	icon = S.Art.rebirth, -- PS99 restyle: rail sticker in the header
	size = S.ShellFor.rebirth,
	scroll = false,
	listLayout = false,
	parent = gui,
})
local panel = shell.root
local z = shell.z
-- PC.shell leaves the root Frame at its default Visible=true; every other
-- shell user lives under GameHUD's hidden host, but this legacy surface sits
-- in its own always-enabled ScreenGui -- unhidden, it IS the first thing a
-- joining player sees, and (registered below while visible) it also stomps
-- the daily calendar's join auto-open through SideRail's single-open registry.
panel.Visible = false
SideRail.registerPanel(panel)   -- only one rail panel open at a time

-- THE TOPBAR IS NOT DRAWABLE, AND THIS ScreenGui DOES NOT IGNORE IT
-- (2026-08-25, measured). `gui` above is created with the default
-- IgnoreGuiInset = false, so the box it can actually paint into is vp.Y MINUS
-- GuiService's inset -- 518 on a 576-tall viewport, not 576. Every fit below
-- divided by vp.Y, overstating the available height by exactly the inset, and
-- the 740-tall rebirth shell rendered 550 into that 518 box: clipped 16px off
-- the TOP and 16px off the BOTTOM at once, with the top 10px of the CLOSE
-- button off screen entirely (captured -- the header sticker and the X are
-- visibly cut, and the REBIRTH button is cut at the foot). Projected forward it
-- is worse where it matters: ~50px of overflow on a landscape handset.
--
-- Read from the ScreenGui's own flag rather than hardcoding the subtraction, so
-- flipping IgnoreGuiInset later cannot silently reintroduce this.
local function drawableY(vp: Vector2): number
	return math.max(vp.Y - (gui.IgnoreGuiInset and 0 or GuiService:GetGuiInset().Y), 1)
end

-- RE-FIT ON THE TOPBAR, NOT JUST ON THE DEVICE (2026-08-25). Correcting the
-- arithmetic above changed nothing on its own, which is the interesting part:
-- `GuiService:GetGuiInset()` returns ZERO until the topbar has initialised, and
-- Platform.Watch fires on device-class changes only. So the fit ran once, early,
-- with an inset of 0, computed the full-height scale, and never ran again when
-- the real 58px inset arrived. The maths was right and the ANSWER WAS STALE.
-- Anything reading the inset has to re-read it -- bind the topbar and the
-- viewport too (rotation on a handset moves both).
local function watchFit(fn: () -> ())
	Platform.Watch(fn)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(fn)
	local function bindCamera()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(fn)
		end
	end
	bindCamera()
	-- the camera instance itself is replaced on some respawn/teleport paths, and
	-- a signal bound to the old one is dead
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindCamera()
		fn()
	end)
end

-- this legacy surface lives in its own ScreenGui, outside GameHUD's fitted
-- host, so it carries its own viewport fit
local pScale = Instance.new("UIScale")
pScale.Parent = panel
watchFit(function()
	-- FitPanel pins desktop to the canvas fit, which can overflow a short
	-- window with a 740-tall shell -- clamp to the real viewport too
	-- Platform.Viewport, not the raw camera (2026-08-26): the same number live, but
	-- the camera cannot be driven by a device preview, so this clamp was always
	-- evaluated against the Studio window and never bound in testing.
	local vp = Platform.Viewport
	local hard = math.min(vp.X / S.ShellFor.rebirth.X, drawableY(vp) / S.ShellFor.rebirth.Y) * 0.98
	pScale.Scale = math.min(Platform.FitPanel(S.ShellFor.rebirth.X, S.ShellFor.rebirth.Y), hard)
end)

local body = shell.body
local GAP = 14

---------------------------------------------------------------- summary strip
-- violet tint, gold icon tile: REBIRTHS over "N . now +x% income / +y% luck"
local strip = PC.plate({
	name = "SummaryStrip",
	size = UDim2.new(1, 0, 0, 104),
	colors = { Color3.fromHex("F3E2FF"), Color3.fromHex("D9B6F7") },
	radius = 24,
	outline = 6,
	zIndex = z + 2,
	parent = body,
	gloss = false,
})
local stripIcon = PC.plate({
	name = "IconTile",
	size = UDim2.fromOffset(72, 72),
	position = UDim2.new(0, 16, 0.5, 0),
	anchor = Vector2.new(0, 0.5),
	colors = S.Action.Violet, -- gold = real money ONLY; rebirth identity is violet
	radius = 20,
	outline = 5,
	zIndex = z + 3,
	parent = strip,
})
-- PS99 sticker treatment: the star outgrows its tile (plates don't clip)
-- and wears the rail's tilt; lone icon takes the rail's -6.
local stripGlyph = PC.shout({
	text = "\u{2B50}", size = 56, zIndex = z + 4, parent = stripIcon, scaled = true,
	frameSize = UDim2.fromScale(1.35, 1.35),
	position = UDim2.fromScale(0.5, 0.5),
	anchor = Vector2.new(0.5, 0.5),
})
stripGlyph.Rotation = -6
PC.shout({
	name = "StripTitle", text = "REBIRTHS", size = 24,
	align = Enum.TextXAlignment.Left,
	frameSize = UDim2.new(1, -220, 0, 28),
	position = UDim2.new(0, 106, 0, 16),
	zIndex = z + 3, parent = strip,
})
local curLabel = PC.read({
	name = "Current", text = "", size = 22,
	color = Color3.fromHex("4A2E63"),
	frameSize = UDim2.new(1, -220, 0, 26),
	position = UDim2.new(0, 106, 0, 56),
	zIndex = z + 3, parent = strip,
})

---------------------------------------------------------------- stat cards
-- one ramp per card, 78 icon tile, 24 key over the 40 value over the 20 sub
local CARD_Y = 104 + GAP
local CARD_H = 230
local CARD_RAMPS = {
	cost   = { Color3.fromHex("FFF0C2"), Color3.fromHex("FFD866") },
	income = { Color3.fromHex("D9F7CC"), Color3.fromHex("8FE86A") },
	luck   = { Color3.fromHex("CFEFFF"), Color3.fromHex("8FD8F5") },
}
local COST_RED = { Color3.fromHex("FFDCD4"), Color3.fromHex("F5A79A") }

local function statCard(idx, ramp, glyph, keyText, subText)
	local card = PC.plate({
		name = keyText .. "Card",
		size = UDim2.new(1 / 3, -math.ceil(GAP * 2 / 3), 0, CARD_H),
		position = UDim2.new((idx - 1) / 3, (idx - 1) * math.ceil(GAP / 3), 0, CARD_Y),
		colors = ramp,
		radius = 26,
		outline = 6,
		zIndex = z + 2,
		parent = body,
		gloss = false,
	})
	local tileF = PC.plate({
		name = "IconTile",
		size = UDim2.fromOffset(78, 78),
		position = UDim2.new(0.5, 0, 0, 16),
		anchor = Vector2.new(0.5, 0),
		colors = { Color3.new(1, 1, 1), Color3.fromHex("FFF4D9") }, -- LemonPop light card (was #E4EDF7)
		radius = 20,
		outline = 5,
		zIndex = z + 3,
		parent = card,
	})
	-- PS99 sticker treatment: glyph bigger than its tile, alternating tilt
	-- per card (even idx -6, odd +5), same language as the nav rail.
	local glyphLabel = PC.shout({
		text = glyph, size = 60, zIndex = z + 4, parent = tileF, scaled = true,
		frameSize = UDim2.fromScale(1.35, 1.35),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
	})
	glyphLabel.Rotation = if idx % 2 == 0 then -6 else 5
	PC.shout({
		name = "Key", text = keyText, size = 24,
		frameSize = UDim2.new(1, 0, 0, 26),
		position = UDim2.new(0, 0, 0, 106),
		zIndex = z + 3, parent = card,
	})
	local value = PC.shout({
		name = "Value", text = "", size = 40,
		frameSize = UDim2.new(1, -8, 0, 44),
		position = UDim2.new(0, 4, 0, 136),
		zIndex = z + 3, parent = card, scaled = true,
	})
	local sub = PC.read({
		name = "Sub", text = subText or "", size = 20,
		align = Enum.TextXAlignment.Center,
		color = Color3.fromHex("4A2E00"),
		frameSize = UDim2.new(1, -8, 0, 24),
		position = UDim2.new(0, 4, 0, 186),
		zIndex = z + 3, parent = card,
	})
	return card, value, sub
end

local costCard, costLabel = statCard(1, CARD_RAMPS.cost, "\u{1F4B0}", "COST", "cash needed")
local _, incLabel, incSub = statCard(2, CARD_RAMPS.income, "\u{1F4C8}", "INCOME", "")
local _, luckLabel, luckSub = statCard(3, CARD_RAMPS.luck, "\u{1F340}", "LUCK", "")
local costGrad = costCard:FindFirstChildOfClass("UIGradient")

---------------------------------------------------------------- warning strip
local WARN_Y = CARD_Y + CARD_H + GAP
local warn = PC.plate({
	name = "WarningStrip",
	size = UDim2.new(1, 0, 0, 46),
	position = UDim2.new(0, 0, 0, WARN_Y),
	colors = S.Action.Warn,
	radius = 24,
	outline = 6,
	zIndex = z + 2,
	parent = body,
	gloss = false,
})
local bang = PC.plate({
	name = "BangTile",
	size = UDim2.fromOffset(48, 48),
	position = UDim2.new(0, 10, 0.5, 0),
	anchor = Vector2.new(0, 0.5),
	colors = { Color3.fromHex("FF9F1C"), Color3.fromHex("E2620A") },
	radius = 14,
	outline = 5,
	zIndex = z + 3,
	parent = warn,
})
PC.shout({ text = "!", size = 30, zIndex = z + 4, parent = bang })
local warnLabel = PC.read({
	name = "Copy",
	text = "Resets your cash \u{2014} rocks and brainrots stay",
	size = 26,
	color = Color3.fromHex("4A2E00"),
	frameSize = UDim2.new(1, -84, 1, 0),
	position = UDim2.new(0, 72, 0, 0),
	zIndex = z + 3, parent = warn,
})
warnLabel.TextScaled = true
local warnFit = Instance.new("UITextSizeConstraint")
warnFit.MaxTextSize = 26
warnFit.Parent = warnLabel

---------------------------------------------------------------- action plate
local rebirthBtn = PC.pill({
	name = "RebirthButton",
	text = "REBIRTH",
	colors = S.Action.Go,
	size = UDim2.new(1, 0, 0, 110),
	position = UDim2.new(0, 0, 1, 0),
	anchor = Vector2.new(0, 1),
	textSize = 46,
	radius = 28,
	zIndex = z + 2,
	parent = body,
})
local rebirthLabel = rebirthBtn:FindFirstChild("Label")
local rebirthGrad = rebirthBtn:FindFirstChildOfClass("UIGradient")

---------------------------------------------------------------- confirm dialog (ZIndex 150)
local dialogScrim = Instance.new("TextButton") -- button: clicking the scrim cancels
dialogScrim.Name = "RebirthConfirmScrim"
dialogScrim.Text = ""
dialogScrim.AutoButtonColor = false
dialogScrim.BackgroundColor3 = Color3.new(0, 0, 0)
-- blur-never-dim (PS99 grammar): the scrim keeps its click-to-cancel job but
-- never paints -- the dark backdrop is RebirthConfirmBlur, driven from
-- setConfirmOpen below.
dialogScrim.BackgroundTransparency = 1
dialogScrim.BorderSizePixel = 0
dialogScrim.Size = UDim2.fromScale(1, 1)
dialogScrim.Visible = false
dialogScrim.ZIndex = 150
dialogScrim.Parent = gui

local dialog = PC.plate({
	name = "RebirthConfirm",
	size = UDim2.fromOffset(640, 320),
	position = UDim2.fromScale(0.5, 0.5),
	anchor = Vector2.new(0.5, 0.5),
	colors = { S.Surface.Shell, S.Surface.Shell },
	radius = 44,
	outline = 12,
	zIndex = 151,
	parent = dialogScrim,
	gloss = false,
})
dialog:SetAttribute("NoPolish", true)
dialog.Active = true -- sink clicks: only the scrim OUTSIDE the dialog cancels
local dScale = Instance.new("UIScale")
dScale.Parent = dialog
watchFit(function()
	-- same inset blindness as the shell fit above: this dialog paints into the
	-- same inset-respecting ScreenGui, so it gets the same drawable height
	-- Platform.Viewport, not the raw camera (2026-08-26) -- see the shell fit above.
	local vp = Platform.Viewport
	dScale.Scale = math.min(Platform.FitPanel(640, 320), (vp.X / 640) * 0.9, (drawableY(vp) / 320) * 0.9)
end)

PC.shout({
	name = "DialogTitle", text = "REALLY REBIRTH?", size = 40,
	frameSize = UDim2.new(1, -40, 0, 60),
	position = UDim2.new(0, 20, 0, 26),
	zIndex = 152, parent = dialog,
})
PC.shout({
	name = "DialogCopy",
	text = "\u{1F525} WIPES YOUR CASH \u{2014} ROCKS & BRAINROTS STAY \u{1F525}",
	size = 24,
	color = S.Action.Warn[2],
	frameSize = UDim2.new(1, -60, 0, 40),
	position = UDim2.new(0, 30, 0, 104),
	zIndex = 152, parent = dialog,
})

local cancelBtn = PC.pill({
	name = "Cancel", text = "CANCEL",
	colors = S.Action.Neutral,
	size = UDim2.fromOffset(250, 84),
	position = UDim2.new(0.5, -14, 1, -30),
	anchor = Vector2.new(1, 1),
	textSize = 30,
	zIndex = 152,
	parent = dialog,
})
local confirmBtn = PC.pill({
	name = "Confirm", text = "REBIRTH",
	colors = S.Action.Danger,
	size = UDim2.fromOffset(250, 84),
	position = UDim2.new(0.5, 14, 1, -30),
	anchor = Vector2.new(0, 1),
	textSize = 30,
	zIndex = 152,
	parent = dialog,
})

-- Instant per-surface backdrop blur, cloned from GameHUDClient's HUDPanelBlur
-- recipe (GameHUDClient ~327-339): create at Size 10 on open, :Destroy() on
-- close. NEVER tween a BlurEffect property -- TweenService silently no-ops on
-- non-GuiObjects in this place. Two UNIQUE names so this legacy surface can
-- never fight the shared HUDPanelBlur or its own second layer.
local function setRebirthBlur(name, on)
	local Lighting = game:GetService("Lighting")
	local existing = Lighting:FindFirstChild(name)
	if on and not existing then
		local blur = Instance.new("BlurEffect")
		blur.Name = name
		blur.Size = 10
		blur.Parent = Lighting
	elseif not on and existing then
		existing:Destroy()
	end
end

local function setConfirmOpen(open)
	dialogScrim.Visible = open
	setRebirthBlur("RebirthConfirmBlur", open)
end

---------------------------------------------------------------- state + paint
local state = {}
local function render()
	curLabel.Text = ("%d   \u{2022}   now %s income / %s luck"):format(
		state.Rebirths or 0, pct(state.IncomeMult or 1), pct(state.LuckMult or 1))
	costLabel.Text = "$" .. fmt(state.Cost or 0)
	incLabel.Text = pct(state.NextIncomeMult or 1)
	incSub.Text = "now " .. pct(state.IncomeMult or 1)
	luckLabel.Text = pct(state.NextLuckMult or 1)
	luckSub.Text = "now " .. pct(state.LuckMult or 1)
	tile.setReady(state.CanAfford == true)
	tile.setBadge(state.CanAfford and "alert" or "none")

	local can = state.CanAfford == true
	-- cannot afford: the COST card reads red and the action plate drops out
	if costGrad then
		local ramp = can and CARD_RAMPS.cost or COST_RED
		costGrad.Color = ColorSequence.new(ramp[1], ramp[2])
	end
	costLabel.TextColor3 = can and Color3.new(1, 1, 1) or Color3.fromHex("FFB3A6")
	if rebirthLabel then
		rebirthLabel.Text = can and "REBIRTH" or ("NEED $" .. fmt(state.Cost or 0))
	end
	if rebirthGrad then
		local ramp = can and S.Action.Go or S.Action.Inert
		rebirthGrad.Color = ColorSequence.new(ramp[1], ramp[2])
	end
	rebirthBtn.Active = can
	rebirthBtn.BackgroundTransparency = can and 0 or 0.45
end

remotes.RebirthState.OnClientEvent:Connect(function(s)
	if typeof(s) ~= "table" then return end
	state = s
	setConfirmOpen(false)
	render()
end)

btn.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
	setConfirmOpen(false)
	render()
end)
shell.close.Activated:Connect(function()
	panel.Visible = false
	setConfirmOpen(false)
end)
-- Every close path must tear the confirm down, not just the two above: ESC
-- and the rebirth rail button (GameHUDClient) toggle raw Visible, and
-- SideRail's single-open registry force-hides this panel when any other
-- registered panel opens. Watching our own Visible catches every path.
panel:GetPropertyChangedSignal("Visible"):Connect(function()
	if not panel.Visible then
		setConfirmOpen(false)
	end
	-- blur-never-dim: the legacy shell opens OUTSIDE GameHUDClient's
	-- openPanel/setPanelBlur path (its rail click toggles raw Visible and
	-- returns), so it never had a backdrop. Every open/close path -- rail
	-- click, legacy tile, close X, ESC, SideRail single-open force-hide --
	-- lands on this signal, exactly like the confirm teardown above.
	setRebirthBlur("RebirthPanelBlur", panel.Visible)
end)

rebirthBtn.Activated:Connect(function()
	if not state.CanAfford then return end
	setConfirmOpen(true)
end)
cancelBtn.Activated:Connect(function() setConfirmOpen(false) end)
dialogScrim.Activated:Connect(function() setConfirmOpen(false) end)
confirmBtn.Activated:Connect(function()
	if not state.CanAfford then setConfirmOpen(false) return end
	setConfirmOpen(false)
	remotes.RebirthRequest:FireServer()
end)
