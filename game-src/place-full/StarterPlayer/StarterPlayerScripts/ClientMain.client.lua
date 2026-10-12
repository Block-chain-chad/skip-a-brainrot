local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("MainUI")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local MerchantDialog = require(ReplicatedStorage.Modules.MerchantDialog)
local UIStyle = require(ReplicatedStorage.Modules.UIStyle) -- Round 2: shared bubbly theme for the top bar
local SideRail = require(ReplicatedStorage.Modules.SideRail) -- single-open panel registry
local SoundKit = require(ReplicatedStorage.Modules.SoundKit) -- SFX2
local Platform = require(ReplicatedStorage.Modules.Platform) -- device class + TV-safe insets
local HudLayout = require(ReplicatedStorage.Modules.HudLayout) -- screen anchor slots; owns Position for registered HUD frames
local GamepadHint = require(ReplicatedStorage.Modules.GamepadHint) -- controller glyphs on the two always-on controls
-- Kit-style icon artwork for the teleport tabs (see UIKit.IconArt). pcall'd:
-- ClientMain drives the whole throw minigame, so a missing icon module must
-- degrade to the old emoji rather than take the client down.
local okIconArt, IconArt = pcall(function()
	return require(ReplicatedStorage.Modules.UIKit.IconArt)
end)
if not okIconArt then IconArt = nil end
-- Throw pacing (2026-09-21): the shared arc clock (server + ghost + skip counter + camera
-- all read one module) and the stone-tracking camera, which moved out of this file onto
-- CatchCinematic.CameraRig. Both fail-soft: a missing module costs the chase camera /
-- the accelerated cadence, never the throw itself. One local each, on purpose.
local SkipArc = (function() local ok, m = pcall(require, ReplicatedStorage.Modules:WaitForChild("SkipArc", 5)) return ok and m or nil end)()
local ThrowCam = (function() local ok, m = pcall(require, ReplicatedStorage.Modules:WaitForChild("ThrowCam", 5)) return ok and m or nil end)()


local tierByName = {}
for _, tier in ipairs(RarityConfig) do
	tierByName[tier.Name] = tier
end

local cashFrame = gui.CashFrame
local cashLabel = cashFrame.CashLabel
local throwFrame = gui.ThrowFrame
local throwButton = throwFrame.ThrowButton
local barFill = throwFrame.BarBackground.BarFill
local resultFrame = gui.ResultFrame
local rarityLabel = resultFrame.RarityLabel
local nameLabel = resultFrame.NameLabel
local infoLabel = resultFrame.InfoLabel

-- === Bazaar menu chrome (shop / sell) ===
local P = UITheme.Palette
local CF = UITheme.Camp
local FONT = UITheme.Font
local BZ = UITheme.Bazaar

-- Repaint the Border strokes an authored instance already carries; adding a new
-- one would double the outline.
local function blackRim(o, thick)
	for _, s in ipairs(o:GetChildren()) do
		if s:IsA("UIStroke") and s.ApplyStrokeMode ~= Enum.ApplyStrokeMode.Contextual then
			s.Color = CF.ink; s.Thickness = thick or 3; s.Transparency = 0
		end
	end
end

-- Black glyph outline, reusing an existing Contextual stroke when there is one.
local function inkTextOnce(o, thick)
	for _, s in ipairs(o:GetChildren()) do
		if s:IsA("UIStroke") and s.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then
			s.Color = CF.ink; s.Thickness = thick or 2.4; s.Transparency = 0
			return s
		end
	end
	return UITheme.inkText(o, thick)
end

local function styleMenus()
	for _, spec in ipairs({
	}) do
		spec.frame.Size = UDim2.fromOffset(440, 400)
		-- MainUI is Global ZIndexBehavior: lift the panel, then every child with it.
		spec.frame.ZIndex = 10
		UITheme.bazaarPanel(spec.frame)

		UITheme.bazaarHeader(spec.frame, spec.title, spec.icon, spec.accent1, spec.accent2)
		spec.frame.TextLabel.Visible = false   -- kept, not destroyed

		UITheme.bazaarClose(spec.close)
		spec.close.ZIndex = 20

		spec.list.Position = UDim2.new(0, 14, 0, 64)
		spec.list.Size = UDim2.new(1, -28, 1, -80)
		spec.list.BackgroundTransparency = 1
		spec.list.BorderSizePixel = 0
		spec.list.ScrollBarThickness = 6
		spec.list.ZIndex = 11
		spec.list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		spec.list.CanvasSize = UDim2.new(0, 0, 0, 0)
		local ll = spec.list:FindFirstChildOfClass("UIListLayout")
		if ll then ll.Padding = UDim.new(0, 10); ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.HorizontalAlignment = Enum.HorizontalAlignment.Center end
	end
	-- shop joins the single-open registry: opening it closes any rail panel and
	-- folds the rail away, and vice versa. Sell is now GameHUDPanels.SellPanel,
	-- opened via the HudPanelRequest attribute (see openSell below).
end
styleMenus()

local DEFAULT_THROW_TEXT = "HOLD TO SKIP"

local state = {
	Cash = 0,
	OwnedRocks = { Pebble = true },
	EquippedRock = "Pebble",
	Brainrots = {},
}

-- canonical abbreviator, K through Qi -- see Modules.NumberFormat
local formatNumber = require(ReplicatedStorage.Modules.NumberFormat).Short

-- REMOVED (U2): a per-frame Heartbeat that lerped displayCash toward state.Cash
-- and wrote it into cashLabel -- a label inside gui.CashFrame, which
-- GameHUDClient retires on startup (retireAsync(mainUI, "CashFrame")). So it
-- animated a number nobody could see, every frame, for the whole session, and
-- it broke CLAUDE.md's "never lerp in a RunService loop for something a tween
-- can do" while doing it.
--
-- The visible coin pill is driven by GameHUDClient's makeTicker (a TweenService
-- tween on a NumberValue), which now also subscribes to CashTick -- the income
-- channel this loop was the only consumer of.
--
-- cashFrame/cashLabel locals stay: the legacy styling pass further down still
-- references them, and the frame is retired rather than destroyed.
local function refreshCashLabel() end   -- no-op: retained for the call sites below
local function snapCashLabel() end

-- === Walk-up shop + sell stalls (ProximityPrompt) ===
local StallPrompt = require(game:GetService("ReplicatedStorage").Modules.StallPrompt)
local gameWorld = Workspace:WaitForChild("GameWorld")
local sellStall = gameWorld:WaitForChild("SellStall")
local sellPromptPart = sellStall:WaitForChild("PromptPart")
local sellPrompt = sellPromptPart:WaitForChild("SellPrompt")

-- Rock shop is served by the unified MerchantClient panel (see MerchantClient LocalScript).

-- Marco keeps a stall in each world (SellStall in the valley, TundraSellStall in
-- the Frozen Tundra hub). Both bind this one handler, and the dialogue anchors to
-- whichever stall was actually used.
-- Filled by StallPrompt below, for BOTH worlds. Not seeded with sellPromptPart:
-- the binder adds the valley part itself, and would otherwise double-count it.
local sellParts = {}
local function openSell(part)
	-- Coin jingle on the way in. Marco is deliberately NOT a MerchantConfig
	-- merchant (he keeps his own sell menu, so MerchantClient's shared panel and
	-- its EnterSound field don't apply to him), which is why this is wired here
	-- rather than off a config field -- but the id still lives in SoundKit like
	-- every other sound in the game.
	SoundKit.play("shopCoins", nil, { volume = 0.4 })
	-- E starts a short dialogue; the new SellPanel opens when the player continues
	MerchantDialog.Show("Marco the Buyer", {
		"Brainrots to sell? I pay top dollar!",
	}, { CF.amber1, CF.amber2 }, function()
		player:SetAttribute("HudPanelRequest", "sell")
	end, part)
end

-- BOTH of Marco's stalls bind through StallPrompt. The tundra one used to be a
-- one-shot WaitForChild(..., 30) which, with streaming on, timed out for anyone who
-- joined in the valley -- world 2's sell prompt was then connected to nothing and
-- pressing E did nothing at all. The valley one goes through the same path because
-- streaming REPLACES parts: after a trip to the tundra and back, the original
-- sellPrompt instance is gone and its connection with it.
for _, stallName in ipairs({ "SellStall", "TundraSellStall", "GardensSellStall" }) do
	StallPrompt.Bind(stallName, "SellPrompt", function(part, prompt)
		table.insert(sellParts, part)
		prompt.Triggered:Connect(function(triggeringPlayer)
			if triggeringPlayer ~= player then return end
			openSell(part)
		end)
	end)
end

-- auto-close if the player wanders away from a stall
RunService.Heartbeat:Connect(function()
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- RESTORED (2026-08-21, owner call): SellPanel moved into GameHUDClient
	-- and took its Visible flag with it, so this can no longer just flip a
	-- local frame -- it asks GameHUDClient to close via the same attribute
	-- idiom HudPanelRequest uses to open (a late listener still sees an
	-- already-set value; a BindableEvent would not). GameHUDClient gates the
	-- request on currentPanelId, so this can only ever close the sell panel,
	-- never the Bag, Goals, or anything else the player opened on purpose.
	--
	-- GATE FIX (2026-08-21): this whole block used to run unconditionally,
	-- every frame, including the ~100% of frames where no sell panel is even
	-- open -- and it WROTE HudPanelCloseRequest every one of those frames
	-- (SetAttribute fires GetAttributeChangedSignal even when rewriting the
	-- same value; GameHUDClient's watcher then clears the attribute, which
	-- fires the signal again -- ~120 writes/fires per second, forever, for
	-- every player). GameHUDClient now mirrors currentPanelId onto the
	-- HudOpenPanel attribute, so gate on that FIRST -- one cheap attribute
	-- read -- before doing any distance work, restoring the ported
	-- `if sellFrame.Visible then` cost profile.
	if player:GetAttribute("HudOpenPanel") == "sell" then
		-- nearest stall, not the valley one: the tundra copy is 11k studs away
		-- and would otherwise close the menu the moment it opened. A parentless
		-- part has STREAMED OUT; its last position is stale.
		local nearest = math.huge
		for _, part in ipairs(sellParts) do
			if part.Parent then
				nearest = math.min(nearest, (hrp.Position - part.Position).Magnitude)
			end
		end
		if nearest > 20 then
			player:SetAttribute("HudPanelCloseRequest", "sell")
		end
	end
end)

-- === Data sync ===
local function applySnapshot(snapshot)
	if not snapshot then return end
	state.Cash = snapshot.Cash or state.Cash
	state.OwnedRocks = snapshot.OwnedRocks or state.OwnedRocks
	state.EquippedRock = snapshot.EquippedRock or state.EquippedRock
	state.Brainrots = snapshot.Brainrots or state.Brainrots
	snapCashLabel()
end

task.spawn(function()
	local snapshot = remotes.GetInitialData:InvokeServer()
	applySnapshot(snapshot)
end)

remotes.DataUpdated.OnClientEvent:Connect(applySnapshot)

remotes.CashTick.OnClientEvent:Connect(function(newCash)
	state.Cash = newCash      -- the Heartbeat lerp animates toward it
end)

remotes.PurchaseResult.OnClientEvent:Connect(function(result)
	-- lightweight feedback handled by DataUpdated refresh; nothing else needed for MVP
end)

remotes.SellResult.OnClientEvent:Connect(function(result)
	-- lightweight feedback handled by DataUpdated refresh; nothing else needed for MVP
	if result and result.Success and result.Amount then SoundKit.play("cash", nil, { volume = 0.25 }) end -- SFX2
end)

-- === Catch celebration VFX (scales with rarity; big mutations promote the tier) ===
local rarityIndexByName = {}
for i, tier in ipairs(RarityConfig) do rarityIndexByName[tier.Name] = i end

local camera = Workspace.CurrentCamera
local BASE_FOV = camera.FieldOfView

local function shakeCamera(intensity, duration)
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local el = os.clock() - t0
		if el >= duration then
			conn:Disconnect()
			return
		end
		local mag = intensity * (1 - el / duration)
		camera.CFrame = camera.CFrame * CFrame.Angles((math.random() - 0.5) * mag, (math.random() - 0.5) * mag, 0)
	end)
end

local function fovPunch(amount, backTime)
	camera.FieldOfView = BASE_FOV - amount
	TweenService:Create(camera, TweenInfo.new(backTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = BASE_FOV }):Play()
end

local function spawnRevealPillar(color, scale)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local pillar = Instance.new("Part")
	pillar.Name = "CatchPillar"
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Size = Vector3.new(34 * scale, 5 * scale, 5 * scale)
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.Material = Enum.Material.Neon
	pillar.Color = color
	pillar.Transparency = 0.25
	pillar.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 14 * scale, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pillar.Parent = Workspace

	local sparkAttach = Instance.new("Attachment")
	sparkAttach.Position = Vector3.new(0, 0, 0)
	sparkAttach.Parent = pillar
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(color)
	sparks.LightEmission = 1
	sparks.Lifetime = NumberRange.new(0.5, 1.1)
	sparks.Speed = NumberRange.new(8, 16)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new(0.1)
	sparks.Rate = 0
	sparks.Parent = sparkAttach
	sparks:Emit(math.floor(25 * scale))

	TweenService:Create(pillar, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Transparency = 1,
		Size = Vector3.new(34 * scale, 1.2, 1.2),
	}):Play()
	game:GetService("Debris"):AddItem(pillar, 1.4)
end

local celebrateSound = Instance.new("Sound")
celebrateSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
celebrateSound.Parent = gui

local function celebrateCatch(rarityName, mutation)
	-- RETIRED (2026-09-21 reward-pacing pass). This predates the reveal system and was
	-- still firing on top of it: a 34-stud Neon pillar around the character, a camera
	-- shake and a FOV punch on the frame ThrowResult lands -- i.e. while the stone
	-- camera is still out over the water (the pillar off-screen, the FOV write fighting
	-- the camera rig) and, on a Mythic, during the cut's own FOV tighten. The reward's
	-- own accents live in CatchPop (screen-space) and CatchFX (the burst around you,
	-- particles only) now. Kept one-block-revertible, like the result card below.
	if true then return end
	local idx = rarityIndexByName[rarityName] or 1
	-- Band 4 locks the camera onto a world model, so the pillar spawned around
	-- the character would be off-screen and a shake would fight the lock.
	if rarityName == "Secret" or rarityName == "God" then return end
	-- Rainbow/Glitched mutations always celebrate at least Legendary-sized
	if mutation == "Rainbow" or mutation == "Glitched" then
		idx = math.max(idx, 5)
	end
	if idx < 3 then return end

	local tier = tierByName[rarityName]
	local color = (tier and tier.Color) or Color3.fromRGB(255, 255, 255)
	local scale = 0.7 + (idx - 3) * 0.28

	celebrateSound.PlaybackSpeed = math.clamp(1.5 - (idx - 3) * 0.14, 0.8, 1.5)
	celebrateSound.Volume = math.clamp(0.3 + idx * 0.08, 0, 1)
	celebrateSound:Play()

	if idx >= 3 then fovPunch(3 + idx, 0.55) end
	if idx >= 4 then
		spawnRevealPillar(color, scale)
		shakeCamera(0.012 * idx, 0.3 + idx * 0.06)
	end
end

-- === Throw result popup ===
-- Campfire card: warm two-tone body, heavy black rim, outlined glyphs. UIStroke
-- carries its own Transparency (it does NOT follow BackgroundTransparency or
-- TextTransparency), so the outlines are collected here and faded with the popup.
local resultInk = {}
do
	resultFrame.ZIndex = 20
	resultFrame.BackgroundColor3 = P.white
	resultFrame.BorderSizePixel = 0
	UITheme.corner(resultFrame, 16)
	UITheme.gradient(resultFrame, CF.panelTop, CF.panelBot, 90)
	table.insert(resultInk, UITheme.ink(resultFrame, 4))

	rarityLabel.Font = FONT          -- colour stays driven by result.RarityColor
	rarityLabel.TextSize = 20
	rarityLabel.ZIndex = 21
	table.insert(resultInk, UITheme.inkText(rarityLabel, 3))

	nameLabel.Font = FONT
	nameLabel.TextColor3 = CF.cream
	nameLabel.ZIndex = 21
	table.insert(resultInk, UITheme.inkText(nameLabel, 2.6))

	infoLabel.Font = Enum.Font.GothamMedium
	infoLabel.TextColor3 = CF.muted
	infoLabel.ZIndex = 21
	table.insert(resultInk, UITheme.inkText(infoLabel, 1.8))
end

local resultScale = Instance.new("UIScale")
resultScale.Parent = resultFrame
local resultToken = 0
remotes.ThrowResult.OnClientEvent:Connect(function(result)
	resultToken += 1
	local myToken = resultToken

	-- The card is SEMI-retired: CatchRevealClient normally shows the caught
	-- brainrot itself, spinning, instead of describing it in text -- but for
	-- rarities picked under Settings > Skip Catch Animation, the ceremony is
	-- skipped over there (shouldReveal) and this card is the fast
	-- announcement: rarity/name/distance/income in ~3s of corner text. The
	-- quick celebrateCatch juice above runs in both modes.
	celebrateCatch(result.Rarity, result.Mutation)
	-- AUTO quick-tier catches skip their ceremony too (CatchRevealClient.shouldReveal,
	-- same 2026-08-17 change), so this card is their announcement as well.
	local autoQuickSkip = player:GetAttribute("AutoActive") == true
		and (result.Rarity == "Common" or result.Rarity == "Uncommon" or result.Rarity == "Rare")
	if player:GetAttribute("SkipReveal" .. tostring(result.Rarity)) ~= true and not autoQuickSkip then return end

	rarityLabel.Text = string.upper(result.Rarity)
	rarityLabel.TextColor3 = result.RarityColor
	nameLabel.Text = result.BrainrotName
	infoLabel.Text = ("Distance: %dm  |  +%s/s"):format(result.Distance, formatNumber(result.CashPerSecond))

	resultFrame.Visible = true
	resultScale.Scale = 0.6
	TweenService:Create(resultScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	resultFrame.BackgroundTransparency = 1
	local labels = { rarityLabel, nameLabel, infoLabel }
	for _, l in ipairs(labels) do l.TextTransparency = 1 end
	for _, s in ipairs(resultInk) do s.Transparency = 1 end

	TweenService:Create(resultFrame, TweenInfo.new(0.25), { BackgroundTransparency = 0.15 }):Play()
	for _, l in ipairs(labels) do
		TweenService:Create(l, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
	end
	for _, s in ipairs(resultInk) do
		TweenService:Create(s, TweenInfo.new(0.25), { Transparency = 0 }):Play()
	end

	task.delay(2.5, function()
		if myToken ~= resultToken then return end
		TweenService:Create(resultFrame, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		for _, l in ipairs(labels) do
			TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		end
		for _, s in ipairs(resultInk) do
			TweenService:Create(s, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		end
		task.delay(0.4, function()
			if myToken == resultToken then
				resultFrame.Visible = false
			end
		end)
	end)
end)

-- === Charge + throw ===
-- FIXED "sweet spot": a slim green strip pinned to the END of the charge bar. It
-- used to jump to a new spot every time the minigame loaded; it no longer moves,
-- so the perfect release is always the full-power release.
-- The band is still SERVER-ISSUED (GetSweetSpot) and judged server-side against
-- the released power; this side only draws where it is told. Until the server
-- answers there is no band: the sentinels below can never match a real power value.
local BAND_WIDTH = 0.07
local perfectMin, perfectMax = -1, -1

local perfectBand = Instance.new("Frame")
perfectBand.Name = "PerfectBand"
perfectBand.Size = UDim2.new(BAND_WIDTH, 0, 1, 0)
perfectBand.Position = UDim2.new(perfectMin, 0, 0, 0)
perfectBand.BackgroundColor3 = P.white
perfectBand.BackgroundTransparency = 0
perfectBand.BorderSizePixel = 0
perfectBand.ZIndex = barFill.ZIndex + 2
perfectBand.Parent = throwFrame.BarBackground
do
	-- sweet-spot strip: pine two-tone + black outline (size/position stay driven
	-- by refreshSweetSpot and BAND_WIDTH)
	UITheme.corner(perfectBand, 6)
	UITheme.gradient(perfectBand, CF.pine1, CF.pine2, 90)
	UITheme.ink(perfectBand, 2)
end

-- Ask the server for a fresh band and draw whatever it says. A failed or slow
-- fetch just means no band this throw (no perfect chance), never an error --
-- and the token guard stops a stale answer from overdrawing a newer one.
local bandToken = 0
local function refreshSweetSpot()
	bandToken += 1
	local myToken = bandToken
	perfectMin, perfectMax = -1, -1
	perfectBand.Visible = false
	task.spawn(function()
		local ok, band = pcall(function()
			local rf = remotes:WaitForChild("GetSweetSpot", 10)
			return rf and rf:InvokeServer() or nil
		end)
		if not ok or type(band) ~= "table" or myToken ~= bandToken then return end
		perfectMin, perfectMax = band.min, band.max
		perfectBand.Position = UDim2.new(perfectMin, 0, 0, 0)
		perfectBand.Size = UDim2.new(perfectMax - perfectMin, 0, 1, 0)
		perfectBand.Visible = true
	end)
end
refreshSweetSpot()

-- === Campfire theme for the skip minigame panel (carved sign + charge groove) ===
-- ZIndex is deliberately left alone in here: MainUI is Global ZIndexBehavior and
-- every child of this panel sits at 1-3, so lifting the frame would bury them.
do
	local GROOVE_TOP = Color3.fromRGB(58, 39, 26)
	local GROOVE_BOT = Color3.fromRGB(30, 20, 13)

	-- panel -> carved wooden sign
	throwFrame.BackgroundColor3 = P.white
	throwFrame.BackgroundTransparency = 0
	throwFrame.BorderSizePixel = 0
	UITheme.corner(throwFrame, 16)
	UITheme.gradient(throwFrame, CF.wood1, CF.wood2, 90)
	blackRim(throwFrame, 4)
	local fgloss = throwFrame:FindFirstChild("Gloss")
	if fgloss then
		local gg = fgloss:FindFirstChildOfClass("UIGradient")
		-- keep the sheen weak or the wood washes out to beige
		if gg then gg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.86), NumberSequenceKeypoint.new(1, 1) }) end
	end

	-- charge groove -> recessed earth
	local barBg = throwFrame.BarBackground
	barBg.BackgroundColor3 = P.white
	barBg.BorderSizePixel = 0
	UITheme.gradient(barBg, GROOVE_TOP, GROOVE_BOT, 90)
	blackRim(barBg, 2.5)
	local bc = barBg:FindFirstChildOfClass("UICorner"); if bc then bc.CornerRadius = UDim.new(1, 0) end

	-- fill -> rounded + soft sheen (keeps the red->green power ramp). The fill is
	-- resized every frame from 0 width, so it gets no outline of its own -- the
	-- groove's black rim reads as the outline instead.
	local fillC = barFill:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	fillC.CornerRadius = UDim.new(1, 0); fillC.Parent = barFill
	if not barFill:FindFirstChild("Sheen") then
		local sheen = Instance.new("Frame")
		sheen.Name = "Sheen"; sheen.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		sheen.BackgroundTransparency = 0.72; sheen.BorderSizePixel = 0
		sheen.Size = UDim2.new(1, 0, 0.42, 0); sheen.ZIndex = barFill.ZIndex + 1
		local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(1, 0); sc.Parent = sheen
		sheen.Parent = barFill
	end

	-- chunky pill button. UITheme.setColors keeps driving the state colours from
	-- releaseThrow / the throw-zone gate, so only the chrome changes here.
	throwButton.TextSize = 18
	UITheme.campButton(throwButton, UITheme.Palette.hudThrow1, UITheme.Palette.hudThrow2)
	blackRim(throwButton, 3)
	inkTextOnce(throwButton, 2.6)
	local bgloss = throwButton:FindFirstChild("Gloss")
	if bgloss then
		local gg = bgloss:FindFirstChildOfClass("UIGradient")
		if gg then gg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.72), NumberSequenceKeypoint.new(1, 1) }) end
	end
end

-- === Touch lift for the throw cluster ===
-- The authored ThrowFrame anchor ({0.5,0},{1,-110}, AnchorPoint 0.5,1) parks the
-- whole cluster -- charge groove, HOLD TO SKIP pill, and the AUTO chip hanging
-- above it -- in the bottom-centre thumb corridor, between Roblox's touch
-- joystick (bottom-left) and jump button (bottom-right). On touch devices the
-- cluster rides 110px higher so thumbs and the jump/joystick band clear it;
-- desktop keeps the authored spot to the pixel. Position only: everything in
-- the frame (breath tweens, AUTO chip, bar fill, perfect band) is authored
-- relative to it and moves along for free -- the breath tweens ride
-- throwButton, a child, so they never fight this.
--
-- Platform.Watch fires immediately AND on every later device change (including
-- a PlatformOverride flip from the command bar), so this re-resolves live
-- rather than latching whatever the first frame reported.
do
	-- 2026-08-18 REWRITE, measured on a landscape phone (666x374) the first time
	-- the phone class actually engaged. The previous version SUBTRACTED a flat
	-- 110px on touch, on top of the authored -110 -- which put the cluster at
	-- y 24..96 (the top third of the screen, over the currency counters) and
	-- pushed AUTO SKIP off-screen at y -18. It was never verified on a real
	-- phone viewport; this is.
	--
	-- The bottom-centre lane is FREE on touch: Roblox puts the thumbstick left
	-- of x~140 and the jump button right of x~526, while this cluster spans
	-- x 163..503. It does not need lifting out of the way -- a HOLD control
	-- WANTS to be in the thumb zone. What it must clear is the nav rail, which
	-- on a phone is a left-edge block anchored on the vertical midline.
	--
	-- So: on touch the cluster sits at the FOOT of the safe area (offset 0),
	-- which measured AUTO at y 202..236 and the bar at y 244..316 -- directly
	-- under the rail block, nothing overlapping. Desktop keeps its authored
	-- -110 exactly. Platform.Watch re-resolves on every device change.
	local restPos = throwFrame.Position   -- authored bottom-centre anchor
	Platform.Watch(function()
		local offset = Platform.IsTouch and 0 or restPos.Y.Offset
		throwFrame.Position = UDim2.new(
			restPos.X.Scale, restPos.X.Offset,
			restPos.Y.Scale, offset)
	end)
end

-- ============================= PERFECT SKIP POPUP =============================
-- Its OWN ScreenGui rather than a label inside ThrowFrame, which is where this used to
-- live. Parented to the throw HUD it was a 21px line of green text pinned above the power
-- bar -- easy to miss entirely, and it inherited the HUD's scale and clipping. A perfect
-- is now a rare thing you had to aim for (the band moved off the top of the bar), so it
-- gets the middle of the screen and its own DisplayOrder.
local PERFECT_GOLD = Color3.fromRGB(255, 214, 56)
local PERFECT_AMBER = Color3.fromRGB(255, 150, 24)

local perfectGui = Instance.new("ScreenGui")
perfectGui.Name = "PerfectPopUI"
perfectGui.ResetOnSpawn = false
perfectGui.IgnoreGuiInset = true
perfectGui.DisplayOrder = 30
perfectGui.Parent = player:WaitForChild("PlayerGui")

local perfectRoot = Instance.new("Frame")
perfectRoot.Name = "Root"
perfectRoot.Size = UDim2.fromOffset(620, 200)
perfectRoot.AnchorPoint = Vector2.new(0.5, 0.5)
perfectRoot.Position = UDim2.new(0.5, 0, 0.34, 0)   -- above centre, clear of the crosshair
perfectRoot.BackgroundTransparency = 1
perfectRoot.Visible = false
perfectRoot.Parent = perfectGui
local perfectScale = Instance.new("UIScale")
perfectScale.Parent = perfectRoot

-- Sunburst. 12 bars at 15 degrees covers a full starburst, not a half one: a rectangle
-- rotated 180 degrees is the same rectangle, so 12 x 15 = 180 is the whole fan.
local burst = Instance.new("Frame")
burst.Name = "Burst"
burst.Size = UDim2.fromOffset(230, 230)
burst.AnchorPoint = Vector2.new(0.5, 0.5)
burst.Position = UDim2.fromScale(0.5, 0.5)
burst.BackgroundTransparency = 1
burst.Parent = perfectRoot
local burstScale = Instance.new("UIScale")
burstScale.Parent = burst
local rays = {}
for i = 1, 12 do
	local ray = Instance.new("Frame")
	ray.AnchorPoint = Vector2.new(0.5, 0.5)
	ray.Position = UDim2.fromScale(0.5, 0.5)
	ray.Size = UDim2.fromOffset(i % 2 == 0 and 5 or 9, i % 2 == 0 and 150 or 210)
	ray.Rotation = (i - 1) * 15
	ray.BackgroundColor3 = PERFECT_GOLD
	ray.BorderSizePixel = 0
	ray.ZIndex = 1
	ray.Parent = burst
	rays[#rays + 1] = ray
end

local perfectText = Instance.new("TextLabel")
perfectText.Name = "Big"
perfectText.Size = UDim2.new(1, 0, 0, 92)
perfectText.Position = UDim2.new(0, 0, 0, 34)
perfectText.BackgroundTransparency = 1
perfectText.Font = Enum.Font.FredokaOne
perfectText.TextSize = 80
perfectText.Text = "PERFECT!"
perfectText.TextColor3 = PERFECT_GOLD
perfectText.ZIndex = 3
perfectText.Parent = perfectRoot
-- UIGradient tints TEXT on a TextLabel, so this is the gold-to-amber fall without
-- needing two stacked labels.
local textGrad = Instance.new("UIGradient")
textGrad.Color = ColorSequence.new(PERFECT_GOLD, PERFECT_AMBER)
textGrad.Rotation = 90
textGrad.Parent = perfectText
UITheme.inkText(perfectText, 6)

local perfectSub = Instance.new("TextLabel")
perfectSub.Name = "Sub"
perfectSub.Size = UDim2.new(1, 0, 0, 26)
perfectSub.Position = UDim2.new(0, 0, 0, 124)
perfectSub.BackgroundTransparency = 1
perfectSub.Font = FONT
perfectSub.TextSize = 22
-- the real multipliers, from ThrowHandler's PERFECT_DISTANCE_MULT / PERFECT_LUCK_MULT
perfectSub.Text = "+10% DISTANCE   \u{2022}   +7.5% LUCK"
perfectSub.TextColor3 = Color3.fromRGB(255, 240, 200)
perfectSub.ZIndex = 3
perfectSub.Parent = perfectRoot
UITheme.inkText(perfectSub, 3)

-- Sparks, reused rather than rebuilt: this fires on a throw cooldown, so churning
-- instances every time would be pointless garbage.
local sparks = {}
for i = 1, 10 do
	local s = Instance.new("Frame")
	s.AnchorPoint = Vector2.new(0.5, 0.5)
	s.Position = UDim2.fromScale(0.5, 0.5)
	s.Size = UDim2.fromOffset(10, 10)
	s.Rotation = 45
	s.BackgroundColor3 = i % 3 == 0 and Color3.fromRGB(255, 255, 255) or PERFECT_GOLD
	s.BorderSizePixel = 0
	s.ZIndex = 2
	s.Visible = false
	s.Parent = perfectRoot
	sparks[#sparks + 1] = s
end

local perfectPopToken = 0
local function showPerfectPop()
	perfectPopToken += 1
	local myToken = perfectPopToken
	-- 78 lines of sunburst, sparks, FOV punch and camera shake had no audio at all.
	--
	-- STACKED, AND IT WINS THE FRAME (2026-08-21, owner: "a cool sound affect").
	-- One 0.63s twinkle could never land this: it fires on the SAME FRAME as the
	-- release whoosh (RELEASE_VOL 0.38) and the old note above had it deliberately
	-- sitting UNDER that -- so the game's only skill moment was the quietest cue in
	-- the throw. Perfect now gets the density treatment the catch ladder uses for
	-- its top rungs (see SoundKit.Ids.catchBigHit): an IMPACT to land the moment,
	-- then the SPARKLE over the top, offset so the two read as one gesture rather
	-- than doubling on the attack. Both ids are load-verified (2.01s / 0.63s).
	--
	-- VOLUMES ARE INLINE ON PURPOSE. `PERFECT_VOL` is declared ~110 lines BELOW
	-- this function, so the name here resolved to a nil GLOBAL and SoundKit fell
	-- back to its 0.25 "quiet incidental" default -- the cue was never even playing
	-- at the 0.32 that constant advertised. Do not swap these back to a constant
	-- unless you move its declaration above showPerfectPop; ClientMain is at Luau's
	-- 200-local ceiling, so ADD nothing at the top level here.
	SoundKit.play("catchBigHit", nil, { volume = 0.5 })
	task.delay(0.07, function()
		SoundKit.play("catchSparkle", nil, { volume = 0.42, speed = 1.12 })
	end)

	-- reset every animated property, or a second perfect mid-fade inherits the tail of
	-- the first and reads as a flicker
	perfectRoot.Visible = true
	perfectRoot.Position = UDim2.new(0.5, 0, 0.34, 0)
	perfectScale.Scale = 0.45
	perfectText.Rotation = -9
	perfectText.TextTransparency = 0
	perfectSub.TextTransparency = 0
	for _, st in ipairs(perfectText:GetChildren()) do
		if st:IsA("UIStroke") then st.Transparency = 0 end
	end
	for _, st in ipairs(perfectSub:GetChildren()) do
		if st:IsA("UIStroke") then st.Transparency = 0 end
	end
	burstScale.Scale = 0.35
	for _, r in ipairs(rays) do r.BackgroundTransparency = 0.15 end

	-- punch in past 1 and settle back: the overshoot is what gives it weight
	TweenService:Create(perfectScale, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1.12 }):Play()
	TweenService:Create(perfectText, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Rotation = 0 }):Play()
	task.delay(0.26, function()
		if myToken ~= perfectPopToken then return end
		TweenService:Create(perfectScale, TweenInfo.new(0.14, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
	end)

	-- burst blooms outward and fades, so it reads as a flash rather than furniture
	TweenService:Create(burstScale, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Scale = 1.75 }):Play()
	for _, r in ipairs(rays) do
		TweenService:Create(r, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }):Play()
	end

	-- sparks fly out on their own headings
	for i, s in ipairs(sparks) do
		local ang = (i / #sparks) * math.pi * 2 + math.random() * 0.4
		local dist = 120 + math.random() * 90
		s.Visible = true
		s.Position = UDim2.fromScale(0.5, 0.5)
		s.Size = UDim2.fromOffset(11, 11)
		s.BackgroundTransparency = 0
		TweenService:Create(s, TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, math.cos(ang) * dist, 0.5, math.sin(ang) * dist),
			Size = UDim2.fromOffset(0, 0),
			BackgroundTransparency = 1,
			Rotation = 225,
		}):Play()
	end

	-- a little physical feedback; both helpers already exist above for the catch reveal
	fovPunch(2.5, 0.4)
	shakeCamera(0.006, 0.18)

	-- hold, then drift up and out
	task.delay(0.62, function()
		if myToken ~= perfectPopToken then return end
		local ti = TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(perfectRoot, ti, { Position = UDim2.new(0.5, 0, 0.27, 0) }):Play()
		TweenService:Create(perfectText, ti, { TextTransparency = 1 }):Play()
		TweenService:Create(perfectSub, ti, { TextTransparency = 1 }):Play()
		for _, lbl in ipairs({ perfectText, perfectSub }) do
			for _, st in ipairs(lbl:GetChildren()) do
				if st:IsA("UIStroke") then TweenService:Create(st, ti, { Transparency = 1 }):Play() end
			end
		end
		task.delay(0.45, function()
			if myToken == perfectPopToken then
				perfectRoot.Visible = false
				for _, s in ipairs(sparks) do s.Visible = false end
			end
		end)
	end)
end

-- === THROW AUDIO =========================================================
-- All four cues reuse ids already declared and load-verified in SoundKit.Ids;
-- nothing new is invented here, and the two orphaned ids (panelOpen, fusion)
-- are deliberately left for the features they belong to.
--   charge   throwCharge flyloop 5.12s -- sustained air, pitched up as you wind
--   release  wheelWind  UI whoosh 0.85s   -- the commit, its own voice not a UI click
--   perfect  catchSparkle Twinkling 0.63s -- bright, short, fires seconds before any
--                                            catch audio so the two never collide
--   pity     wheelWin   bling             -- handled in PityThrowClient
--
-- THE CHARGE BED WAS eggStrain UNTIL 2026-08-18 -- bonecrackle, the egg hatch's
-- waiting bed. A bone sample, looped, under the game's most-pressed button (owner:
-- "the hold to skip button makes a weird sound"). Two things were wrong with it and
-- the swap fixes both: it is a horror texture, and at 2.63s it WRAPPED inside a long
-- hold, retriggering its own attack. See SoundKit.Ids.throwCharge for the sizing rule
-- and the vetted alternates.
--
-- SUBTLETY PASS (owner 2026-08-18: flyloop is the right sound, "lets make it more
-- subtle"). Two knobs do that and both moved, because level alone is not what makes
-- a bed obtrusive -- a wide pitch sweep pulls the ear whatever its volume:
--   VOLUME  0.20 -> 0.12. Under the 0.16 the old crackle sat at, and under a third
--           of the release. THIS is the lever if it wants another nudge either way.
--   RAMP    0.80-1.70 -> 0.90-1.42. Still tracks the bar -- riding `power` is what
--           lets you hear where you are in the fill, and that is worth keeping --
--           but it now climbs rather than swoops.
-- flyloop is a sustained bed with no arc of its own, so the ramp is doing all of the
-- building; that is why narrowing it reads as calmer instead of broken. The sample
-- itself was picked by ear from a six-class audition -- see SoundKit.Ids.throwCharge
-- before swapping it, because reasoning alone got it wrong twice.
local CHARGE_PITCH_LO = 0.90    -- power 0
local CHARGE_PITCH_HI = 1.42    -- power 1
local CHARGE_VOL      = 0.12    -- a bed: must lose to the release (RELEASE_VOL 0.38)
local RELEASE_VOL     = 0.38    -- loudest of the four -- this is the commitment
-- PERFECT_VOL is GONE, not moved: it sat here, 110 lines below the only place that
-- read it, so it was a nil global at the call site and never applied. The perfect
-- stack's levels are inline in showPerfectPop above (0.5 impact / 0.42 sparkle) --
-- deliberately ABOVE this release whoosh now, because perfect should beat the throw.
local CHARGE_FADE     = 0.12    -- stop fade on release OR cancel
local chargeLoop = nil

-- ONE teardown, called from every path that can end a charge. Idempotent.
local function stopChargeLoop()
	if chargeLoop then
		chargeLoop:stop(CHARGE_FADE)
		chargeLoop = nil
	end
end

-- ===================== CTA BREATH =====================
-- The one element in the game that breathes. It is the primary call to action,
-- and only while the player has gone quiet: 6s after the last throw, stopping
-- the instant they charge again.
--
-- REAL TWEENS with Reverses + RepeatCount = -1, so the engine drives them and
-- no per-frame Lua is involved. It breathes via Size + Position rather than a
-- UIScale because a TweenService tween on UIScale.Scale does not run in this
-- place (probed live) -- Size and Position are GuiObject properties and do.
-- AnchorPoint is (0,0), so Position is shifted by half the growth to keep the
-- button breathing about its own centre. Both always return to exact rest.
local BREATH_SCALE = 0.025      -- 1.000 <-> 1.025
local BREATH_TIME  = 2.4        -- seconds per half-cycle
local BREATH_IDLE  = 6          -- seconds of no throw before it starts
local breathTweens = {}
local breathOn = false
local lastThrowAt = os.clock()

local BREATH_REST_SIZE = throwButton.Size
local BREATH_REST_POS  = throwButton.Position

local function stopBreath()
	if not breathOn then return end
	breathOn = false
	for _, t in ipairs(breathTweens) do t:Cancel() end
	table.clear(breathTweens)
	-- exact rest, never "wherever the tween happened to stop"
	throwButton.Size = BREATH_REST_SIZE
	throwButton.Position = BREATH_REST_POS
end

local function startBreath()
	if breathOn then return end
	breathOn = true
	local growX = math.round(340 * BREATH_SCALE)   -- ThrowFrame is 340 wide
	local growY = math.round(34 * BREATH_SCALE)
	local info = TweenInfo.new(BREATH_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local sz = TweenService:Create(throwButton, info, {
		Size = UDim2.new(BREATH_REST_SIZE.X.Scale, BREATH_REST_SIZE.X.Offset + growX,
		                 BREATH_REST_SIZE.Y.Scale, BREATH_REST_SIZE.Y.Offset + growY),
	})
	local ps = TweenService:Create(throwButton, info, {
		Position = UDim2.new(BREATH_REST_POS.X.Scale, BREATH_REST_POS.X.Offset - growX / 2,
		                     BREATH_REST_POS.Y.Scale, BREATH_REST_POS.Y.Offset - growY / 2),
	})
	breathTweens = { sz, ps }
	sz:Play(); ps:Play()
end

local charging = false
local power = 0
local cooldown = false
local CYCLE_SECONDS = 1.1
-- REFERENCE VIDEO (2026-08-04, user recording): chargePeriod is now the FILL
-- DURATION of a single left-to-right sweep, not an oscillation period -- see
-- the RenderStepped charge block. It is still RE-ROLLED on every charge for
-- the same anti-macro reason as always: a fixed duration makes the bar a
-- metronome (hold N ms, land on the same power every time). Re-rolling per
-- charge means a fixed-hold-time macro cannot know what power it releases
-- at. (A macro CAN now camp the clamp at full power -- the sine bar punished
-- that, the reference mechanic does not -- but full power never earns the
-- server-judged perfect, and the auto/AFK taxes in ThrowHandler still apply.)
local CYCLE_MIN_MULT, CYCLE_MAX_MULT = 0.62, 1.55
local chargeStart = 0
local chargePeriod = CYCLE_SECONDS
local MAX_FLIGHT_SECONDS = 4.2   -- mirrors the upper clamp in ThrowHandler

-- The bar stays locked from release until the stone has actually SETTLED, not for a
-- fixed 1.1s. Flight is up to 4.2s, so the old timer freed the bar mid-skip and a held
-- button could queue throw after throw. The server enforces one-stone-at-a-time too;
-- this half just keeps the UI honest about it.
local throwToken = 0

-- Set by the stone-tracking camera further down. The bar must not reopen while the
-- camera is still out over the water: handing control back mid-flyback reads as a
-- glitch, and the player cannot aim at something they are not looking at.
local cameraTracking = false

-- force: last-resort release that ignores the camera, so a camera that never restores
-- cannot strand the player unable to throw.
local function unlockThrow(token, force)
	if token and token ~= throwToken then return end   -- a newer throw owns the bar now
	if not cooldown then return end
	if cameraTracking and not force then return end    -- wait for the camera to come home
	cooldown = false
	power = 0
	barFill.Size = UDim2.new(0, 0, 1, 0)
	throwButton.Text = DEFAULT_THROW_TEXT
	UITheme.setColors(throwButton, UITheme.Palette.hudThrow1, UITheme.Palette.hudThrow2)
	refreshSweetSpot() -- re-arm the (single-use) band for the next attempt
end

local inThrowZone = false

-- A player must own a base before they can skip. Ownership is read live from the
-- plot's replicated OwnerUserId attribute (set server-side on claim).
local function playerHasPlot()
	local bases = Workspace:FindFirstChild("PlayerBases")
	if not bases then return false end
	for _, plot in ipairs(bases:GetChildren()) do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			return true
		end
	end
	return false
end

-- forward declarations: the wind-up system is defined just below, but startCharge and
-- the RenderStepped driver both sit above it in this file
local beginWindup, driveWindup, endWindup
-- assigned by the skip-counter block further down; startCharge clears the counter
-- so the last throw's number never bleeds into the next wind-up
local clearSkipCounter

-- THE DOCK THE PLAYER IS STANDING ON, and whether that world can be fished at all.
-- Declared up here rather than beside computeInZone (far below) because startCharge and
-- the button-text pass both need it and both run earlier in the file. computeInZone
-- assigns it; nothing else writes it.
--
-- Only an EXPLICIT false blocks. ThrowHandler writes CatchesEnabled on each dock, but a
-- dock whose attribute has not replicated yet reads nil and behaves exactly as before --
-- a race can never lock the player out of the valley.
local currentZone = nil
local function zoneCatchesDisabled(): boolean
	return currentZone ~= nil and currentZone:GetAttribute("CatchesEnabled") == false
end

-- BRAINROT BAG FULL. Published by PlayerDataManager.PushUpdate on every data
-- change, read here as an attribute rather than counted locally: this script
-- holds no copy of the player's inventory, and a second count would drift from
-- the one the server actually refuses on.
--
-- Missing (nil) reads as ROOM, exactly like CatchesEnabled above -- an attribute
-- that has not replicated yet must never lock the player out of the valley. The
-- server refuses independently in ThrowHandler, so a permissive race costs one
-- refused throw, while a strict one would brick the core loop on a slow join.
local function bagFull(): boolean
	return (player:GetAttribute("BrainrotSpace") or 1) <= 0
end

local function startCharge()
	if cooldown or charging then return end
	-- A takeover cut is playing (Takeover sets RevealActive for the catcher; spec S11):
	-- no throws until the camera is back. Client-side on purpose -- it only guards
	-- the local camera round-trip.
	if player:GetAttribute("RevealActive") == true then return end
	if not inThrowZone then return end
	-- Nothing to catch in this world yet (World 2 pending its roster). Refusing HERE
	-- rather than letting the server abandon the throw is the whole point: the old
	-- path charged, showed PERFECT, then sat dead on "SKIPPING..." for ~6.7s.
	if zoneCatchesDisabled() then return end
	-- FULL BAG CANNOT SKIP (2026-08-24, owner direction). Refused before the charge
	-- rather than at the catch: the old path let the player spend a charge, watch
	-- the skip land, and only then be told the catch was dropped on the floor. The
	-- button already reads BAG FULL by the time anyone gets here.
	if bagFull() then return end
	if not playerHasPlot() then return end -- no base yet; button acts as "get a plot" instead
	charging = true
	stopBreath()          -- they are engaged; the invitation is over
	lastThrowAt = os.clock()
	if clearSkipCounter then clearSkipCounter() end   -- last throw's count goes away NOW
	stopChargeLoop()   -- never stack two beds if a charge somehow re-enters
	chargeLoop = SoundKit.loop("throwCharge", { volume = CHARGE_VOL, speed = CHARGE_PITCH_LO })
	-- roll this charge's own bar speed (see CYCLE_MIN_MULT above)
	chargeStart = os.clock()
	chargePeriod = CYCLE_SECONDS * (CYCLE_MIN_MULT + math.random() * (CYCLE_MAX_MULT - CYCLE_MIN_MULT))
	-- FAST CHARGE (Robux pass), wired 2026-08-09 -- nothing read ChargeMult before, so
	-- that pass would have taken Robux and done nothing. The bar is drawn and timed on
	-- this client, so the multiplier can only be applied here; ownership arrives on the
	-- shop's state push and is parked on the throw button (see the register note by the
	-- AUTO button). Trust model is unchanged -- the client already reports its own power.
	--
	-- WHAT IT ACTUALLY BUYS is throughput, not a better throw: the green band keeps the
	-- same WIDTH in power but goes past faster in time, so a perfect gets harder to hit
	-- while throws come round quicker. Clamped so a bad value can never divide by ~0.
	chargePeriod = chargePeriod / math.clamp(throwButton:GetAttribute("ChargeMult") or 1, 0.25, 4)
	beginWindup()
end

-- ============================ THROW WIND-UP + RELEASE ============================
-- Procedural full-body posing, written straight to the rig's joints every frame.
--
-- WHY NOT KeyframeSequence: this character is a CONSTRAINT rig -- 15 AnimationConstraints,
-- 14 BallSocketConstraints, and ZERO Motor6D. Runtime-registered KeyframeSequences resolve
-- their Poses through Motor6D, so on this rig they apply to NOTHING. Measured in this
-- place: posing by part name (RightUpperArm) and by joint name (RightShoulder) each moved
-- the arm 0.0 degrees, while the track itself reported weight 1.00 and scrubbed its
-- TimePosition perfectly. The original throw animation used exactly that approach wrapped
-- in a pcall -- which is why it silently did nothing at all.
--
-- WHAT DOES WORK: AnimationConstraint.Transform is writable. Driving RightShoulder moved
-- the arm 2.7 -> 120.0 degrees (measured), and it snapped back the moment we stopped. The
-- Animator rewrites Transform every frame, so a pose must be REWRITTEN every frame.
--
-- THE PHASE MATTERS, AND ONLY ONE WORKS. Measured all five on this rig, writing the same
-- CFrame to RightShoulder and reading the resulting arm angle:
--     RenderStepped    2.3 deg   overwritten
--     Stepped        147.2 deg   <-- WINS
--     Heartbeat        3.8 deg   overwritten
--     PreAnimation     3.0 deg   overwritten
--     PostSimulation   3.6 deg   overwritten
-- The Animator evaluates after every phase except Stepped, so anywhere else the write is
-- discarded within the same frame. `power` is still computed in the existing RenderStepped
-- loop; that loop only RECORDS the wanted pose, and the Stepped driver below applies it.
--
-- This also suits the mechanic better than any clip. The charge bar is a 1.1s SINE, so
-- mapping `power` straight onto joint angles makes the body literally be the bar, with no
-- clip length or playback speed to keep in sync.
-- Also means "a cast sequence owns the rig": the ice-fishing cast reuses this flag rather
-- than adding one of its own. See the do-block below playThrowAnimation for why every
-- single local there had to stay out of this chunk.
local throwAnimActive = false

local function A(x, y, z)
	return CFrame.Angles(math.rad(x or 0), math.rad(y or 0), math.rad(z or 0))
end

-- Keys are AnimationConstraint names on the rig: Root Waist Neck, Left/RightShoulder,
-- Left/RightElbow, Left/RightWrist, Left/RightHip, Left/RightKnee, Left/RightAnkle.
-- A throw is a kinetic chain -- legs brace, hips and ribs coil, the arm arrives last --
-- so the whole body is keyed rather than just the throwing arm.
--
-- SIGN CONVENTION, measured on this rig rather than assumed (+40 deg on each joint's X
-- and reading the limb's world direction against the torso's LookVector):
--     +X on ANY shoulder / hip / knee  ->  that limb swings FORWARD
--     +Y on Waist                      ->  the RIGHT shoulder swings FORWARD
-- Two consequences that were wrong in the first pass and made the whole throw read
-- backwards:
--   * The off arm must OPPOSE the throwing arm, so LeftShoulder takes the OPPOSITE sign
--     to RightShoulder at every key. Matching signs made both arms reach back together
--     and then both swing forward, which is not a throw.
--   * A knee bends with the shin travelling BACKWARD, so every knee value is NEGATIVE.
--     Positive knee values bent the legs the wrong way entirely.
--
-- KEEP EVERY SWING UNDER 180 DEGREES. blend() interpolates with CFrame:Lerp, which
-- takes the SHORTEST arc between two rotations. The wind-up used to cock the shoulder
-- to -150 and whip to +95: a raw difference of 245 degrees, so the short arc was the
-- other 115 -- and the arm swung BACKWARD over the top instead of forward through the
-- throw. Measured on the rig: axis-angle distance between those two keys came out at
-- 116.6 degrees, i.e. 360 - 245, which is the proof it was travelling the wrong way.
-- The signs above were never the problem; the arc length was.
--
-- So: no joint may differ by more than 180 degrees between consecutive keys, and the
-- shoulder now cocks to -72 (a natural coil) rather than -150 (past vertical).
local WOUND = {
	Waist         = A(14, -30, 0),   -- -Y: right shoulder rotates AWAY from the target
	Neck          = A(-4, 26, 0),    -- counter-twist so the eyes stay on the lake
	RightShoulder = A(-72, 0, 18),   -- -X: cocked BACK, and only 72 deg from neutral so
	                                 -- the swing to WHIP (+92) is 164 deg -- under 180,
	                                 -- so Lerp's short arc runs FORWARD through the throw
	RightElbow    = A(-78, 0, 0),    -- elbow folded tighter to keep the hand back by the ear
	LeftShoulder  = A(44, 0, -24),   -- +X: off arm comes FORWARD across the chest
	LeftElbow     = A(-28, 0, 0),
	RightHip      = A(-14, 0, 0),    -- weight settles onto the back leg
	RightKnee     = A(-24, 0, 0),    -- back knee BENDS to take it
	LeftHip       = A(10, 0, 0),     -- front leg straightens and braces
	LeftKnee      = A(-6, 0, 0),
}
local WHIP = {
	Waist         = A(-22, 26, 0),   -- +Y: shoulders fire through toward the target
	Neck          = A(-8, -10, 0),   -- head snaps out after the stone
	RightShoulder = A(92, 0, -14),   -- +X: throwing arm drives FORWARD (164 deg from WOUND)
	RightElbow    = A(-12, 0, 0),    -- elbow straightens as it releases
	LeftShoulder  = A(-26, 0, 16),   -- -X: off arm drives BACK, opposing the throw
	LeftElbow     = A(-8, 0, 0),
	RightHip      = A(14, 0, 0),     -- back leg comes through onto the front foot
	RightKnee     = A(-4, 0, 0),
	LeftHip       = A(-12, 0, 0),
	LeftKnee      = A(-10, 0, 0),    -- front knee absorbs the transfer
}
local FOLLOW = {
	Waist         = A(-14, 17, 0),
	Neck          = A(-5, -6, 0),
	RightShoulder = A(55, 0, -26),   -- arm carries across the body
	RightElbow    = A(-30, 0, 0),
	LeftShoulder  = A(-10, 0, 10),   -- off arm still trailing behind
	RightHip      = A(8, 0, 0),
	LeftHip       = A(-6, 0, 0),
	LeftKnee      = A(-5, 0, 0),
}
local RELEASE_KEYS = {
	{ 0.00, WOUND },
	{ 0.10, WHIP },
	{ 0.22, FOLLOW },
	{ 0.42, nil },     -- nil = back to neutral
}


-- Union of every joint any pose touches. ONLY these are ever written, so the walk and
-- idle animations keep full control of the wrists, ankles and everything else.
local CONTROLLED = {}
for _, pose in ipairs({ WOUND, WHIP, FOLLOW }) do
	for name in pairs(pose) do CONTROLLED[name] = true end
end
-- The ankles are claimed for the SCOOTER, which parks the default animations while you
-- ride: without them under control the feet keep whatever half-stride angle the walk
-- clip happened to freeze on. No pose here names them, so applyPose neutralises them --
-- which is also what a throw wants, and is what the animator was giving them anyway.
CONTROLLED.LeftAnkle = true
CONTROLLED.RightAnkle = true

local joints = {}
local function cacheJoints(char)
	joints = {}
	if not char then return end
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("AnimationConstraint") and CONTROLLED[d.Name] then
			joints[d.Name] = d
		end
	end
end
cacheJoints(player.Character)
player.CharacterAdded:Connect(function(c)
	throwAnimActive = false
	task.wait(0.3)          -- let the rig finish assembling before caching
	cacheJoints(c)
end)

local IDENTITY = CFrame.identity
local function applyPose(pose, alpha)
	for name, joint in pairs(joints) do
		if joint.Parent then
			local target = (pose and pose[name]) or IDENTITY
			if alpha and alpha < 1 then target = IDENTITY:Lerp(target, alpha) end
			joint.Transform = target
		end
	end
end
local function blend(p1, p2, t)
	local out = {}
	for name in pairs(CONTROLLED) do
		out[name] = ((p1 and p1[name]) or IDENTITY):Lerp((p2 and p2[name]) or IDENTITY, t)
	end
	return out
end

-- What the Stepped driver should be writing right now. nil = hands the rig back to the
-- walk/idle animation.
local activePose, activeAlpha = nil, 1
local windupActive = false
-- Set by the scooter driver much further down: a COMPLETE pose table, rebuilt every
-- frame with the lean and the float already baked into its angles, or nil whenever the
-- player is not riding. It reuses this machinery rather than starting a second one --
-- the ten joints a ride wants are the ten the throw already controls, and two writers
-- on one rig is how a pose ends up flickering between them.
local ridePose = nil

RunService.Stepped:Connect(function()
	if windupActive or throwAnimActive then
		if activePose then applyPose(activePose, activeAlpha) end
		return
	end
	if activePose then
		-- charge cancelled or throw finished: one neutral frame, then stop writing so the
		-- Animator resumes. Self-healing, so no exit path can leave the body stuck posed.
		applyPose(nil, 1)
		activePose = nil
	end
	-- THE THROW OUTRANKS THE RIDE, and has to: both write the same ten joints, and a
	-- throw taken while riding must still look like a throw. The ride only gets the rig
	-- on the frames no throw wants it. Dropping ridePose needs no neutral frame of its
	-- own -- the Animator reclaims a joint the moment we stop writing it.
	if ridePose then applyPose(ridePose, 1) end
end)

function beginWindup()
	if not next(joints) then cacheJoints(player.Character) end
	windupActive = true
end

function driveWindup(p)
	if not windupActive then return end
	-- record only. power 0..1 lerps neutral -> fully wound, so the coil tracks the bar.
	activePose, activeAlpha = WOUND, math.clamp(p, 0, 1)
end

function endWindup()
	windupActive = false
end

local function playThrowAnimation()
	endWindup()                       -- hand off from the held coil, no snap to neutral
	if throwAnimActive then return end
	if not next(joints) then cacheJoints(player.Character) end
	throwAnimActive = true
	task.spawn(function()
		local t0 = os.clock()
		local total = RELEASE_KEYS[#RELEASE_KEYS][1]
		while true do
			local t = os.clock() - t0
			if t >= total then break end
			local k1, k2 = RELEASE_KEYS[1], RELEASE_KEYS[#RELEASE_KEYS]
			for i = 1, #RELEASE_KEYS - 1 do
				if t >= RELEASE_KEYS[i][1] and t <= RELEASE_KEYS[i + 1][1] then
					k1, k2 = RELEASE_KEYS[i], RELEASE_KEYS[i + 1]
					break
				end
			end
			local span = math.max(k2[1] - k1[1], 1e-4)
			local f = math.clamp((t - k1[1]) / span, 0, 1)
			f = f * f * (3 - 2 * f)   -- smoothstep; a linear ramp between keys looks robotic
			-- record; the Stepped driver above is what actually writes it
			activePose, activeAlpha = blend(k1[2], k2[2], f), 1
			RunService.Stepped:Wait()
		end
		throwAnimActive = false       -- the Stepped driver now returns the rig to neutral
	end)
end

-- ===================== ICE-FISHING CAST (World 2 blizzard) =====================
-- Same rig, same sign conventions, same 180-degree rule as the throw above -- read that
-- block first, all of it applies here.
--
-- WHY THIS IS ALL INSIDE ONE do-BLOCK, AND WHY IT HOLDS ITS POSES IN ONE TABLE:
-- this chunk sits on Luau's 200-local ceiling. A first version of this section declared
-- its tables and functions at top level and the whole script died on the spot --
-- "Out of local registers when trying to allocate applyLayout: exceeded limit 200" at
-- the HUD layout code far below -- which took sprint, the scooter and everything else
-- past that line with it. A do-block releases its locals again, and folding fifteen pose
-- tables into one `P` keeps the peak inside the block low as well. If you add to this
-- section, add FIELDS to P, never new top-level locals.
--
-- It also reuses throwAnimActive rather than adding a cast flag, for the same reason.
-- The flag really means "a pose sequence owns the rig", which is exactly true during a
-- cast, and the two can never overlap: World-2 throwing is off for the whole blizzard.
--
-- DELIBERATELY USES ONLY THE TEN JOINTS THE THROW ALREADY NAMES, so CONTROLLED is
-- unchanged. Claiming the wrists would give the rod tip a nicer flick, but applyPose
-- forces every CONTROLLED joint a pose does not name to identity -- so taking the wrists
-- here would quietly change how every THROW in the game looks.
--
-- The rod itself is server-side (RodService): it re-welds from the back into the right
-- hand when the cast starts, so this pose swings a hand that is really holding it. Line,
-- float, splash and bite tug are server-side too and so are visible to everyone; the
-- pose, like the throw's, is local view only.
do
	local P = {
		-- pulling it off your back
		reach = { Waist = A(8, -16, 0), Neck = A(-6, 14, 0),
			RightShoulder = A(-96, 0, 36), RightElbow = A(-104, 0, 0),
			LeftShoulder = A(14, 0, -8), LeftElbow = A(-18, 0, 0),
			RightHip = A(-6, 0, 0), RightKnee = A(-10, 0, 0),
			LeftHip = A(4, 0, 0), LeftKnee = A(-6, 0, 0) },
		grab = { Waist = A(10, -22, 0), Neck = A(-4, 18, 0),
			RightShoulder = A(-84, 0, 30), RightElbow = A(-118, 0, 0),
			LeftShoulder = A(18, 0, -10), LeftElbow = A(-24, 0, 0),
			RightHip = A(-8, 0, 0), RightKnee = A(-12, 0, 0),
			LeftHip = A(5, 0, 0), LeftKnee = A(-6, 0, 0) },
		-- it comes clear of the shoulder and the off hand meets it
		pull = { Waist = A(4, -12, 0), Neck = A(-8, 8, 0),
			RightShoulder = A(-34, 0, 16), RightElbow = A(-86, 0, 0),
			LeftShoulder = A(26, 0, -14), LeftElbow = A(-70, 0, 0),
			RightHip = A(-6, 0, 0), RightKnee = A(-12, 0, 0),
			LeftHip = A(4, 0, 0), LeftKnee = A(-8, 0, 0) },
		-- deep coil behind the shoulder, weight on the back foot
		load = { Waist = A(12, -28, 0), Neck = A(-2, 22, 0),
			RightShoulder = A(-70, 0, 26), RightElbow = A(-74, 0, 0),
			LeftShoulder = A(34, 0, -20), LeftElbow = A(-62, 0, 0),
			RightHip = A(-14, 0, 0), RightKnee = A(-22, 0, 0),
			LeftHip = A(9, 0, 0), LeftKnee = A(-6, 0, 0) },
		-- the whip. -70 -> +60 is 130 deg, so Lerp's short arc runs FORWARD
		flick = { Waist = A(-18, 22, 0), Neck = A(-12, -8, 0),
			RightShoulder = A(60, 0, -10), RightElbow = A(-14, 0, 0),
			LeftShoulder = A(-16, 0, 12), LeftElbow = A(-28, 0, 0),
			RightHip = A(11, 0, 0), RightKnee = A(-6, 0, 0),
			LeftHip = A(-9, 0, 0), LeftKnee = A(-13, 0, 0) },
		follow = { Waist = A(-10, 14, 0), Neck = A(-16, -4, 0),
			RightShoulder = A(44, 0, -8), RightElbow = A(-30, 0, 0),
			LeftShoulder = A(4, 0, 10), LeftElbow = A(-44, 0, 0),
			RightHip = A(6, 0, 0), RightKnee = A(-6, 0, 0),
			LeftHip = A(-5, 0, 0), LeftKnee = A(-9, 0, 0) },
		-- waiting on the float, two hands on the rod
		hold = { Waist = A(-6, 8, 0), Neck = A(-15, -2, 0),
			RightShoulder = A(30, 0, -6), RightElbow = A(-44, 0, 0),
			LeftShoulder = A(24, 0, 8), LeftElbow = A(-58, 0, 0),
			RightHip = A(2, 0, 0), RightKnee = A(-6, 0, 0),
			LeftHip = A(-2, 0, 0), LeftKnee = A(-6, 0, 0) },
		holdB = { Waist = A(-4, 9, 0), Neck = A(-12, -2, 0),
			RightShoulder = A(34, 0, -6), RightElbow = A(-38, 0, 0),
			LeftShoulder = A(26, 0, 8), LeftElbow = A(-52, 0, 0),
			RightHip = A(2, 0, 0), RightKnee = A(-6, 0, 0),
			LeftHip = A(-2, 0, 0), LeftKnee = A(-6, 0, 0) },
		-- the jig: you work a hole, you do not stand over it like a lamppost
		jig = { Waist = A(-8, 8, 0), Neck = A(-17, -2, 0),
			RightShoulder = A(16, 0, -8), RightElbow = A(-62, 0, 0),
			LeftShoulder = A(16, 0, 8), LeftElbow = A(-74, 0, 0),
			RightHip = A(2, 0, 0), RightKnee = A(-8, 0, 0),
			LeftHip = A(-2, 0, 0), LeftKnee = A(-8, 0, 0) },
		-- the hookset, after the float has already ducked under
		set = { Waist = A(-2, 4, 0), Neck = A(-18, 0, 0),
			RightShoulder = A(-34, 0, -16), RightElbow = A(-66, 0, 0),
			LeftShoulder = A(-10, 0, 12), LeftElbow = A(-66, 0, 0),
			RightHip = A(-8, 0, 0), RightKnee = A(-16, 0, 0),
			LeftHip = A(5, 0, 0), LeftKnee = A(-11, 0, 0) },
		strain = { Waist = A(-14, 2, 0), Neck = A(-10, 0, 0),
			RightShoulder = A(-14, 0, -14), RightElbow = A(-78, 0, 0),
			LeftShoulder = A(-2, 0, 12), LeftElbow = A(-84, 0, 0),
			RightHip = A(-12, 0, 0), RightKnee = A(-18, 0, 0),
			LeftHip = A(8, 0, 0), LeftKnee = A(-8, 0, 0) },
		-- two winding keys, alternated, so the off hand cranks the reel
		windA = { Waist = A(-10, -4, 0), Neck = A(-12, 0, 0),
			RightShoulder = A(4, 0, -10), RightElbow = A(-88, 0, 0),
			LeftShoulder = A(16, 0, 14), LeftElbow = A(-98, 0, 0),
			RightHip = A(-4, 0, 0), RightKnee = A(-12, 0, 0),
			LeftHip = A(2, 0, 0), LeftKnee = A(-10, 0, 0) },
		windB = { Waist = A(-8, 4, 0), Neck = A(-13, 0, 0),
			RightShoulder = A(10, 0, -8), RightElbow = A(-74, 0, 0),
			LeftShoulder = A(2, 0, 10), LeftElbow = A(-62, 0, 0),
			RightHip = A(-4, 0, 0), RightKnee = A(-12, 0, 0),
			LeftHip = A(2, 0, 0), LeftKnee = A(-10, 0, 0) },
		-- lifting it clear of the hole to look at it
		lift = { Waist = A(-6, -6, 0), Neck = A(-22, 0, 0),
			RightShoulder = A(-40, 0, -20), RightElbow = A(-52, 0, 0),
			LeftShoulder = A(-30, 0, 16), LeftElbow = A(-58, 0, 0),
			RightHip = A(-2, 0, 0), RightKnee = A(-8, 0, 0),
			LeftHip = A(2, 0, 0), LeftKnee = A(-8, 0, 0) },
		slump = { Waist = A(8, 0, 0), Neck = A(12, 0, 0),
			RightShoulder = A(14, 0, -4), RightElbow = A(-22, 0, 0),
			LeftShoulder = A(10, 0, 6), LeftElbow = A(-18, 0, 0),
			RightHip = A(-2, 0, 0), RightKnee = A(-8, 0, 0),
			LeftHip = A(2, 0, 0), LeftKnee = A(-8, 0, 0) },
	}

	-- The flick lands at 0.52 and the arm is settled by 0.56, which is why
	-- IceFishingConfig.CAST_LEAD is 0.56: that is when the server drops the float in and
	-- lets the hook minigame start. Change one, change the other. STOW_DELAY likewise has
	-- to outlast the catch sequence or the rod vanishes mid-reel.
	local SEQ = {
		cast = { { 0.00, P.reach }, { 0.14, P.grab }, { 0.28, P.pull },
			{ 0.42, P.load }, { 0.52, P.flick }, { 0.64, P.follow }, { 0.82, P.hold } },
		catch = { { 0.00, P.set }, { 0.14, P.set }, { 0.32, P.strain },
			{ 0.54, P.windA }, { 0.72, P.windB }, { 0.90, P.windA }, { 1.08, P.windB },
			{ 1.32, P.lift }, { 1.60, P.lift }, { 1.92, nil } },
		miss = { { 0.00, P.set }, { 0.12, P.set }, { 0.36, P.slump },
			{ 0.84, P.slump }, { 1.20, nil } },
	}

	local seq = 0

	-- Runs a key list. Unlike the throw, a cast has a phase of UNKNOWN LENGTH in the
	-- middle -- the hook minigame runs until you click or time out -- so when `hold` is
	-- set the sequence parks there and keeps writing: breathing on a slow sine, with a
	-- jig twitch every couple of seconds. Without it the body would snap back to the walk
	-- cycle the instant the flick finished and stand there with a rod in its fist.
	local function play(keys, hold)
		seq += 1
		local mine = seq
		if not next(joints) then cacheJoints(player.Character) end
		throwAnimActive = true
		task.spawn(function()
			local t0 = os.clock()
			local total = keys[#keys][1]
			while seq == mine do
				local t = os.clock() - t0
				if t >= total then break end
				local k1, k2 = keys[1], keys[#keys]
				for i = 1, #keys - 1 do
					if t >= keys[i][1] and t <= keys[i + 1][1] then
						k1, k2 = keys[i], keys[i + 1]
						break
					end
				end
				local span = math.max(k2[1] - k1[1], 1e-4)
				local f = math.clamp((t - k1[1]) / span, 0, 1)
				f = f * f * (3 - 2 * f)   -- smoothstep; a linear ramp between keys looks robotic
				activePose, activeAlpha = blend(k1[2], k2[2], f), 1
				RunService.Stepped:Wait()
			end
			if seq ~= mine then return end
			if not hold then
				throwAnimActive = false   -- the Stepped driver returns the rig to neutral
				return
			end
			local h0 = os.clock()
			while seq == mine do
				local t = os.clock() - h0
				local base = blend(P.hold, P.holdB, (math.sin(t * 1.7) + 1) * 0.5)
				local cyc = t % 2.4
				if cyc < 0.34 then
					base = blend(base, P.jig, math.sin((cyc / 0.34) * math.pi) * 0.85)
				end
				activePose, activeAlpha = base, 1
				RunService.Stepped:Wait()
			end
		end)
	end

	local function stop()
		seq += 1
		throwAnimActive = false
	end

	-- a cast cannot survive the character that was holding the rod; RodService drops the
	-- stance back to Slung on respawn for the same reason
	player.CharacterAdded:Connect(stop)

	-- Driven straight off the event's own remote rather than through IceFishingClient,
	-- because the rig has exactly one pose writer and it lives in this file.
	task.spawn(function()
		local iceState = remotes:WaitForChild("IceFishingState", 30)
		if not iceState then return end
		iceState.OnClientEvent:Connect(function(p)
			if type(p) ~= "table" then return end
			if p.Casting then
				play(SEQ.cast, true)
				-- square up to the hole on the first frame, the way releaseThrow squares you
				-- up to the lake. AutoRotate is off for the whole cast (see applySprint), so
				-- this facing is what you keep until the rod is stowed.
				local ch = player.Character
				local root = ch and ch:FindFirstChild("HumanoidRootPart")
				if root and typeof(p.HolePos) == "Vector3" then
					local flat = Vector3.new(p.HolePos.X, root.Position.Y, p.HolePos.Z)
					if (flat - root.Position).Magnitude > 0.5 then
						root.CFrame = CFrame.lookAt(root.Position, flat)
					end
				end
			elseif p.Catch then
				play(SEQ.catch)
			elseif p.GotAway then
				play(SEQ.miss)
			elseif p.Cancelled or p.Active == false then
				stop()
			end
		end)
	end)
end


local function releaseThrow(isAuto)
	if not charging then return end
	charging = false
	stopChargeLoop()
	-- release is a COMMITMENT with no cancel, so it gets its own voice rather than
	-- the incidental uiClick that was leaking from the button style. Pitched by the
	-- power behind it (a full-bar release whooshes higher and harder than a tap) with
	-- a hair of random variation, so ten throws in a row are not ten identical samples.
	SoundKit.play("wheelWind", nil, {
		volume = RELEASE_VOL * (0.85 + 0.15 * power),
		speed = 0.92 + 0.16 * power + (math.random() - 0.5) * 0.06,
	})
	local finalPower = power
	local _char = player.Character
	local _hrp = _char and _char:FindFirstChild("HumanoidRootPart")
	if _hrp then
		local _p = _hrp.Position
		_hrp.CFrame = CFrame.new(_p, _p + Vector3.new(0, 0, 1))
	end

	-- Auto is ALWAYS perfect server-side now (2026-08-15, owner direction), so it claims
	-- one here too and the HUD celebration matches what the throw actually gets. The
	-- server grants it unconditionally for pass owners, so this does not depend on the
	-- release having landed inside the band -- see ThrowHandler's autoPerfect.
	local landedPerfect = isAuto
		or (finalPower >= perfectMin and finalPower <= perfectMax)
	if landedPerfect then
		showPerfectPop()
	end

	cooldown = true
	throwToken += 1
	local myToken = throwToken
	throwButton.Text = "SKIPPING..."
	UITheme.setColors(throwButton, UITheme.Palette.hudMuted1, UITheme.Palette.hudMuted2)

	-- The third argument is what the server prices the AFK penalty off (AUTO_LUCK_MULT /
	-- AUTO_DISTANCE_MULT in ThrowHandler). landedPerfect stays display-only; the server
	-- judges perfect itself against the band it issued.
	remotes.ThrowRequest:FireServer(finalPower, landedPerfect, isAuto and true or false)
	playThrowAnimation()

	-- Last-resort release. Normally the bar is freed by the camera restoring, or by
	-- ThrowResult / StoneThrown on throws too short to trigger the tracking camera.
	-- This only matters when the server declined the throw outright, so none of those
	-- ever arrive. Deliberately later than the camera's own flightTime + 1.4 restore,
	-- so it never preempts it.
	task.delay(MAX_FLIGHT_SECONDS + 2.5, function()
		unlockThrow(myToken, true)
	end)
end

-- WHICH FINGER OWNS THE CHARGE (2026-08-19). The release below is a GLOBAL
-- InputEnded -- it has to be, because a finger that slides off the button still
-- has to be able to let the rock go. But it used to fire releaseThrow() for ANY
-- ending Touch, without ever recording which input started the charge. A phone
-- has several fingers down at once: the walk thumbstick, the jump button, the
-- end of a camera-pan drag. Every one of those releases fired the rock at
-- whatever power the bar happened to be at, so on mobile the perfect band was
-- unhittable unless you stood perfectly still and used exactly one finger --
-- i.e. the game's core mechanic was broken on its main platform.
-- Desktop never saw it: one mouse, one button, one InputObject.
local chargeInput: InputObject? = nil

throwButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		if inThrowZone and not playerHasPlot() then
			remotes.TeleportTo:FireServer("OpenPlot") -- send them to an open plot to claim a base
			return
		end
		chargeInput = input
		startCharge()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		-- only the input that STARTED this charge may end it. When nothing is
		-- charging chargeInput is nil and this behaves exactly as it always did,
		-- so the gamepad path and every non-charge release are untouched.
		if chargeInput ~= nil and input ~= chargeInput then return end
		chargeInput = nil
		releaseThrow()
	end
end)

-- === The throw, on a controller ===
-- Everything above listens for MouseButton1 and Touch ONLY, which meant that on
-- a gamepad the game's single core action was unreachable: you could walk to the
-- dock, see the power bar, and never throw a rock. That is the whole game, so
-- "runs on console" was never true no matter how well the UI scaled.
--
-- R2 is the trigger a player reaches for on a charge-and-release, with X as the
-- alternate. Deliberately NOT ButtonA: the default control module binds A (and
-- R2) to activate whatever GUI element is selected, and A is the one that has to
-- keep doing that so the nav rail and every panel stay operable.
--
-- Bound only while the player is actually at a skip dock, so R2 goes back to
-- activating the selected button everywhere else in the game. The Heartbeat that
-- already tracks inThrowZone drives it.
local THROW_ACTION = "SkipThrowGamepad"
local throwBound = false

local function gamepadThrow(_, state)
	if state == Enum.UserInputState.Begin then
		-- same two-step the tap path takes: no plot yet means send them to claim
		-- one rather than starting a charge they cannot bank
		if inThrowZone and not playerHasPlot() then
			remotes.TeleportTo:FireServer("OpenPlot")
			return Enum.ContextActionResult.Sink
		end
		startCharge()
	elseif state == Enum.UserInputState.End then
		releaseThrow()
	end
	return Enum.ContextActionResult.Sink
end

local function setThrowBinding(on: boolean)
	if on == throwBound then return end
	throwBound = on
	if on then
		ContextActionService:BindAction(THROW_ACTION, gamepadThrow, false,
			Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonX)
	else
		ContextActionService:UnbindAction(THROW_ACTION)
		-- Walking out of the zone mid-charge must not strand the charge: without
		-- this the End half of the action never arrives and the bar holds forever.
		if charging then releaseThrow() end
	end
end

-- === Auto skip ===
-- Parented INSIDE ThrowFrame at a negative Y, so it draws above the panel while
-- inheriting the panel's Visible -- it appears and disappears with the minigame
-- instead of floating over the world. ThrowFrame has ClipsDescendants off, which
-- is what makes hanging a child outside its bounds work.
--
-- It drives the SAME startCharge/releaseThrow path a tap does. No parallel throw
-- route to keep in sync, and the server just sees an ordinary ThrowRequest, so
-- every existing check (cooldown, one-stone-at-a-time, throw zone, plot) applies
-- unchanged.
local autoOn = false

-- IT IS A GAMEPASS NOW (2026-08-09, owner's call). The button stays where it was
-- for everyone; unowned, it opens the Robux prompt instead of toggling.
--
-- FREE UNTIL THE PASS IS REAL. GamepassId sits at 0 until someone creates the pass
-- on the Creator Dashboard, and `Prompt` no-ops on a 0 -- so gating unconditionally
-- would leave a dead button and a feature nobody in the game could use, which is a
-- removal rather than a sale. While the id is 0 this reads exactly as it did
-- before; filling the id in is the single act that switches it to paid, matching
-- the convention the shop already runs on.
--
-- A STOREFRONT GATE, NOT A SECURITY BOUNDARY, and it cannot be otherwise: the
-- server has no way to tell an auto throw from a manual one except the flag this
-- client sets, and that flag only ever PENALISES the throw (AUTO_LUCK_MULT). A
-- modified client could fire throws on a timer before this change and still can.
-- ITS STATE LIVES ON THE BUTTON, as attributes, not as upvalues. This chunk sits a
-- handful of locals under Luau's 200-register ceiling: four plain locals here took
-- the file over it, and "Out of local registers" is a COMPILE error -- the entire
-- client HUD failed to load, throw bar and all, for a monetization gate. Attributes
-- cost no registers and are readable from every closure below.
local autoBtn = Instance.new("TextButton")
autoBtn.Name = "AutoButton"
autoBtn.AnchorPoint = Vector2.new(0.5, 1)
autoBtn.Position = UDim2.new(0.5, 0, 0, -8)
autoBtn.Size = UDim2.fromOffset(150, 34)
autoBtn.Font = Enum.Font.FredokaOne
autoBtn.TextSize = 18
autoBtn.Text = "AUTO: OFF"
autoBtn.AutoButtonColor = false
autoBtn.ZIndex = throwFrame.ZIndex + 1
autoBtn.Parent = throwFrame
UITheme.campButton(autoBtn, UITheme.Palette.hudMuted1, UITheme.Palette.hudMuted2)
blackRim(autoBtn, 3)
inkTextOnce(autoBtn, 2.6)

-- do-block so its working locals are freed again; see the register note above
do
	local pass = require(ReplicatedStorage.Modules.GamepassConfig).ByKey["AutoSkip"]
	local live = (pass ~= nil and (pass.GamepassId or 0) > 0)
	autoBtn:SetAttribute("PassLive", live)
	-- free for everyone until the pass is real -- see the note above the button
	autoBtn:SetAttribute("PassOwned", not live)
end

local function refreshAutoButton()
	if not autoBtn:GetAttribute("PassOwned") then
		-- gold rather than muted: it is not disabled, it is for sale
		autoBtn.Text = "\u{1F512} AUTO SKIP"
		UITheme.setColors(autoBtn, UITheme.Palette.hudGold1, UITheme.Palette.hudGold2)
		return
	end
	autoBtn.Text = autoOn and "AUTO: ON" or "AUTO: OFF"
	if autoOn then
		UITheme.setColors(autoBtn, UITheme.Palette.green1, UITheme.Palette.green2)
	else
		UITheme.setColors(autoBtn, UITheme.Palette.hudMuted1, UITheme.Palette.hudMuted2)
	end
end
refreshAutoButton()

autoBtn.MouseButton1Click:Connect(function()
	if not autoBtn:GetAttribute("PassOwned") then
		-- ShopService owns every prompt; it re-checks the key and the id itself, so
		-- this cannot open a prompt for something that is not on sale
		local prompt = remotes:FindFirstChild("ShopPrompt")
		if prompt then prompt:FireServer("pass", "AutoSkip") end
		return
	end
	autoOn = not autoOn
	-- Mirrored as an attribute so CatchRevealClient can pace the reveals off it
	-- (2026-08-17 auto quick-tier skip) without a cross-script global.
	player:SetAttribute("AutoActive", autoOn)
	refreshAutoButton()
end)

-- Ownership arrives on the shop's own state push -- on join, and again the instant a
-- pass is bought, so buying it flips this button to a working toggle with no rejoin.
-- Bounded wait: ShopService self-heals the remote at Init, and a client that somehow
-- never sees it simply keeps whatever autoOwned started as.
task.spawn(function()
	local shopState = remotes:WaitForChild("ShopState", 30)
	if not shopState then return end
	shopState.OnClientEvent:Connect(function(s)
		if typeof(s) ~= "table" or typeof(s.Owned) ~= "table" then return end
		local ownsIt = (not autoBtn:GetAttribute("PassLive")) or (s.Owned["AutoSkip"] == true)
		autoBtn:SetAttribute("PassOwned", ownsIt)
		-- Same push carries every other pass, so the charge multiplier is resolved off it
		-- here rather than inventing a second remote. Product across owned passes, matching
		-- GamepassService.multOf on the server.
		local charge = 1
		for _, g in ipairs(require(ReplicatedStorage.Modules.GamepassConfig).List) do
			if s.Owned[g.Key] and g.Effects and type(g.Effects.ChargeMult) == "number" then
				charge = charge * g.Effects.ChargeMult
			end
		end
		throwButton:SetAttribute("ChargeMult", charge)
		-- losing the gate must also stop a loop already running
		if not ownsIt then autoOn = false end
		player:SetAttribute("AutoActive", autoOn)
		refreshAutoButton()
	end)
	-- SELF-HEAL for the join race (2026-08-17 field-study catch): ShopService's
	-- join push can fire before this listener connects (RemoteEvents do not
	-- queue for a late listener), and the next push only comes when a pass is
	-- BOUGHT -- so an OWNER who missed the push stared at the locked gold BUY
	-- state all session (observed live: ~10 minutes of captures showing the
	-- lock on an owned pass, until a prompt poke re-pushed). One client-side
	-- ownership check patches exactly that case; purchases and revocations
	-- still flow through ShopState above.
	if autoBtn:GetAttribute("PassLive") and not autoBtn:GetAttribute("PassOwned") then
		local mkOk, owns = pcall(function()
			local gp = require(ReplicatedStorage.Modules.GamepassConfig).ByKey["AutoSkip"]
			return game:GetService("MarketplaceService"):UserOwnsGamePassAsync(player.UserId, gp.GamepassId)
		end)
		if mkOk and owns then
			autoBtn:SetAttribute("PassOwned", true)
			refreshAutoButton()
		end
	end
end)

-- ONE loop rather than a chain of task.delay callbacks: every gate is re-checked
-- each pass, so switching auto off, walking away from the dock, or losing the plot
-- stops it at the next tick instead of after one more throw has already gone out.
task.spawn(function()
	while true do
		task.wait(0.1)
		if autoOn and autoBtn:GetAttribute("PassOwned") and inThrowZone and not charging and not cooldown and not bagFull() and playerHasPlot() then
			startCharge()
			-- AIM AT THE BAND (2026-08-15, owner direction: auto should score a perfect
			-- every time). This deliberately reverses the previous behaviour, which released
			-- at a random 0.30..0.88 unrelated to the band so that idling produced a spread
			-- of mediocre throws. The middle of the band, not its lower edge, so ordinary
			-- frame jitter cannot fall out of a strip only BAND_WIDTH (0.07) across.
			--
			-- The perfect itself does NOT depend on this landing cleanly -- ThrowHandler
			-- grants auto a perfect outright for pass owners. This is what makes the bar
			-- LOOK right while it happens; without it the strip would flash PERFECT with the
			-- marker sitting somewhere else entirely.
			--
			-- Falls back to the old random spread only when no band was issued this charge
			-- (a failed GetSweetSpot fetch), where there is nothing to aim at.
			--
			-- The 3s ceiling still means a stuck charge releases rather than holding the
			-- bar forever.
			local target = (perfectMin >= 0 and perfectMax > perfectMin)
				and (perfectMin + (perfectMax - perfectMin) * 0.5)
				or (0.30 + math.random() * 0.58)
			local t0 = os.clock()
			while autoOn and charging and os.clock() - t0 < 3 do
				if power >= target then
					-- a beat of jitter so releases are not even frame-consistent
					task.wait(math.random() * 0.10)
					break
				end
				task.wait()
			end
			if charging then releaseThrow(true) end
		end
	end
end)

RunService.RenderStepped:Connect(function(dt)
	-- STRUCTURAL SAFETY NET: the bed's lifetime is owned by the same frame loop that
	-- owns `power`, so it cannot outlive a charge by ANY path -- release, a cancel
	-- that only flips `charging`, leaving the zone, death, or a character reset that
	-- takes the whole rig with it. Nothing has to remember to call the teardown.
	if not charging and chargeLoop then
		stopChargeLoop()
	end
	if charging then
		-- REFERENCE VIDEO (2026-08-04): the bar FILLS ONCE, left to right, and
		-- holds at full -- no more bouncing sine. Missing the green band is a
		-- real miss now: past it there is no second pass, exactly like the
		-- reference. Speed still varies per charge (chargePeriod re-roll), so
		-- the release point cannot be macro'd off a stopwatch.
		local t = os.clock() - chargeStart
		power = math.clamp(t / chargePeriod, 0, 1)
		barFill.Size = UDim2.new(power, 0, 1, 0)
		-- user brief: the fill fades GREEN into RED the longer you hold (the
		-- old ramp ran the other way); the pinned green band keeps its spot
		barFill.BackgroundColor3 = Color3.fromHSV(0.33 * (1 - power), 0.8, 1)
		-- Pitch rides the SAME power the bar and the arm ride, so what you hear is
		-- exactly what you see. Geometric, not linear: pitch perception is
		-- logarithmic, and a linear sweep audibly stalls near the top.
		if chargeLoop then
			chargeLoop:setSpeed(CHARGE_PITCH_LO * (CHARGE_PITCH_HI / CHARGE_PITCH_LO) ^ power)
		end
		-- the arm IS the bar: same value drives both, so what you see on the HUD and what
		-- the character is doing can never disagree
		driveWindup(power)
	end
end)

refreshCashLabel()

-- === Teleport tabs ===
local tabBar = gui:WaitForChild("TabBar")
-- Declared before applyLayout so its first pass already knows who owns Position.
local tabSlot = HudLayout.Attach(tabBar, {
	stack = "TopCentre",
	order = 10,
	avoid = true,   -- step below the top-left currency cluster rather than over it
})

-- THE TAB BAR USES THE TOPBAR BAND ON A PHONE (2026-08-26, owner capture).
--
-- The safe-area top inset is reserved across the full width for Roblox's topbar,
-- but on a phone that chrome -- logo, menu, chat, voice -- is LEFT-ALIGNED and the
-- middle of the band is empty. Measured on the capture: the pill ends around
-- x 570 of 1999 while these tabs sit at x 763..1237, so the two never meet.
-- Paying the full 58px anyway spent 19% of a 310px screen's height on nothing and
-- pushed the tabs down into the play area, which is what the owner marked as
-- needing to be higher.
--
-- Safe ONLY because this bar is centred and narrow. Do not copy the negative pad
-- onto anything that reaches the left edge -- Roblox's chrome always draws on top,
-- so a widget under it is invisible and untappable.
-- ...and it has to stop AVOIDING to do it. The two settings pull against each
-- other: `avoid` exists to push this bar clear of the currency cluster, and the
-- cluster occupies the very band the pad is trying to move into -- so the raise
-- was applied and then immediately undone, landing the bar back at 66px and
-- looking as though SetPad did nothing (it fires correctly; traced).
--
-- Safe to drop on a phone specifically, because there the two are clear on the
-- axis avoidance cannot see past: the cluster is left-anchored and ends around
-- x 216 of 700, while this bar is centred at x 267..433. On desktop the bar is
-- wider relative to the screen and the cluster is a real obstacle, so avoidance
-- stays on there exactly as before.
if tabSlot then
	HudLayout.WatchDevice(function()
		local phone = Platform.IsPhone
		tabSlot:SetAvoid(not phone)
		tabSlot:SetPad(phone and -40 or 0)
	end)
end
local throwTab = tabBar:WaitForChild("ThrowTab")
local shopsTab = tabBar:WaitForChild("ShopsTab")
local plotTab = tabBar:WaitForChild("PlotTab")

throwTab.MouseButton1Click:Connect(function()
	remotes.TeleportTo:FireServer("Throw")
end)
shopsTab.MouseButton1Click:Connect(function()
	remotes.TeleportTo:FireServer("Shops")
end)
plotTab.MouseButton1Click:Connect(function()
	remotes.TeleportTo:FireServer("Plot")
end)

-- 2026-08-17 polish (field-study nit "orphaned SKIP/SHOPS/PLOT icons behind
-- panels"): the teleport bar kept drawing -- and taking clicks -- behind any
-- open panel. It stands down while the panel host is up, the same contract
-- the quest tracker keeps via SideRail, and returns the moment the last
-- panel closes (PanelHost.Visible is owned by openPanel/closePanel).
--
-- EXTENDED 2026-08-19 -- PHONE ONLY -- to the other two MainUI surfaces that
-- now draw ON an open panel rather than beside one: the SPRINT pill and the
-- whole THROW cluster (ThrowFrame, which the AUTO button hangs inside and so
-- inherits). HUD panels were just enlarged ~61% on handsets -- the counter-band
-- reserve that crushed them to 0.299 is gone and they run near-fullscreen at
-- Platform.FitPanel -- so they are modals now, and GameHUDClient's openPanel
-- already stands the nav rail and the currency cluster down for exactly that
-- reason. This is the rest of that sweep, kept in the ONE watcher this file
-- already runs rather than a second one racing it. Desktop is untouched:
-- the phone test only gates the two NEW surfaces, and tabBar keeps the
-- unconditional behaviour it has had since 08-17.
task.spawn(function()
	local hudGui = player:WaitForChild("PlayerGui"):WaitForChild("GameHUD", 30)
	local canvas = hudGui and hudGui:WaitForChild("Canvas", 10)
	local host = canvas and canvas:WaitForChild("PanelHost", 10)
	if not host then return end
	-- Resolved HERE rather than reusing the file-level `sprintButton`: that local
	-- is declared hundreds of lines BELOW this closure, so it is not an upvalue
	-- yet, and hoisting it would add a main-chunk local to a file that sits a
	-- handful under Luau's 200-register ceiling (see the register note by the
	-- AUTO button -- "Out of local registers" is a COMPILE error that takes the
	-- whole client HUD down). Locals inside this closure cost the chunk nothing.
	local sprintBtn = gui:WaitForChild("SprintButton", 10)
	local hidden = false   -- edge trigger; see the write rule below
	local function sync()
		-- RailPanelOpen is SideRail's "any registered panel is open" (round 2.5): the
		-- legacy shops (egg, merchant) never touch PanelHost but sit near-fullscreen
		-- on a phone too, and Sprint was drawing across the egg shop's right edge;
		-- the tab bar's three icons poked out above its header. Phone only, like
		-- the rest of this sweep -- the desktop tab bar keeps its 08-17 behaviour.
		local shopOnPhone = Platform.IsPhone and player:GetAttribute("RailPanelOpen") == true
		tabBar.Visible = not (host.Visible or shopOnPhone)
		local hide = (host.Visible or shopOnPhone) and Platform.IsPhone
		-- WRITE ONLY ON THE EDGE, never every sync. On desktop `hide` is false from
		-- the first call and never moves, so this branch is never entered and these
		-- two surfaces are not written to AT ALL there -- no chance of this quietly
		-- becoming a second visibility owner of Sprint or the throw cluster and
		-- re-asserting true over some other system that wanted them away. It also
		-- means a phone->desktop device flip while a panel is open still restores,
		-- because that flip is itself an edge.
		if hide ~= hidden then
			hidden = hide
			if sprintBtn then sprintBtn.Visible = not hide end
			-- THE THROW CLUSTER IS NOT OURS TO SET. The throw-zone Heartbeat further
			-- down owns ThrowFrame.Visible outright and rewrites it EVERY FRAME from
			-- inThrowZone/charging/cooldown, so a false written here would survive one
			-- frame. Park the intent as an attribute -- the same "state lives on the
			-- instance" idiom this file uses for the AUTO button -- and let that owner
			-- AND it in; it stays the only writer, so the frame comes back exactly as
			-- the dock/charge state says it should, not blindly shown. The direct write
			-- is purely so the hide lands on this frame instead of the next one.
			throwFrame:SetAttribute("PanelHidden", hide)
			if hide then throwFrame.Visible = false end
		end
	end
	host:GetPropertyChangedSignal("Visible"):Connect(sync)
	player:GetAttributeChangedSignal("RailPanelOpen"):Connect(sync)
	-- Device class can change under us (Studio's device emulator, and a desktop
	-- window resized narrow). Platform.Watch calls fn immediately and on every
	-- change; the trailing sync() is kept anyway so the first paint never depends
	-- on that contract.
	Platform.Watch(sync)
	sync()
end)

-- === Teleport tabs: top bar (Skip / Shops / Plot) + cash pill ===
-- Runtime-only: the StarterGui source is untouched and the TeleportTo wiring
-- above is left alone -- only appearance and placement change here.
--
-- Each tab is a sticker card (white plate, saturated ribbon banner, white
-- keyline) from UIStyle.sticker; this block picks colours and lays them out.
-- All lettering is white FredokaOne (see UIPolish for the game-wide sweep).
--
-- PLACEMENT: centred along the top. The cash pill owns the top-right corner
-- (190 wide + 12 margin), so the bar has to be narrow enough to clear it --
-- pickMetrics() below solves for that rather than assuming a screen size, and
-- drops the bar UNDER the pill on screens too narrow for any size to fit.
do
	local function C(r, g, b) return Color3.fromRGB(r, g, b) end

	-- One saturated accent per destination. Deliberately high-chroma and far
	-- apart in hue so a glance at the rail is enough to tell them apart.
	local RAIL = {
		{ btn = throwTab, order = 1, word = "Skip",  glyph = "\u{1F3AF}", icon = "skip", tilt = -4,
		  accent = { light = C(255, 182, 64),  dark = C(244, 122, 18), outline = C(148, 64, 8)  } },
		{ btn = shopsTab, order = 2, word = "Shops", glyph = "\u{1F6D2}", icon = "shops", tilt = 3,
		  accent = { light = C(255, 116, 176), dark = C(226, 42, 122), outline = C(134, 14, 70) } },
		{ btn = plotTab,  order = 3, word = "Plot",  glyph = "\u{1F3E0}", icon = "plot", tilt = -3,
		  accent = { light = C(112, 192, 255), dark = C(38, 118, 236), outline = C(18, 58, 138) } },
	}

	--[[ 2026-08-04 icon redesign (user handoff, option 3a), round 2: the full
	mock treatment for the top actions -- bare tilted emoji with a plain white
	OUTLINED word below it, NO ribbon banner, no plate. Placement stays
	top-middle (user instruction; the mock parks these top-right). The ribbon
	UIStyle.sticker builds every applyLayout pass is hidden rather than the
	builder edited -- sticker() is shared with other surfaces. UIStroke works
	fine on ordinary TEXT (it is only colour emoji it cannot outline), so the
	word gets the mock's #1c1333 keyline for real, matching the rail labels.

	applyLayout re-runs on every viewport change, so this stays idempotent:
	previous glyph/word are destroyed, the ribbon re-hidden, every pass. ]]
	local function applyStickerGlyph(btn, spec, MET)
		local card = btn:FindFirstChild("StickerCard")
		if not card then return end

		local emoji = card:FindFirstChild("StickerIcon")
		for _, host in ipairs({ card, btn }) do
			for _, n in ipairs({ "KitIcon", "StickerGlyph", "StickerWord" }) do
				local stale = host:FindFirstChild(n)
				if stale then stale:Destroy() end
			end
		end

		-- un-plate: card goes invisible but stays as the layout box
		card.BackgroundTransparency = 1
		for _, child in ipairs(card:GetChildren()) do
			if child:IsA("UIStroke") then child.Transparency = 1 end
		end
		if emoji then emoji.Visible = false end
		local ribbon = btn:FindFirstChild("StickerRibbon")
		if ribbon then ribbon.Visible = false end

		-- Sized off the metrics rather than AbsoluteSize: this runs in the same
		-- tick the card is built, before any layout pass has resolved it. The
		-- glyph is capped below the free space so it stays in family with the
		-- nav rail's icons instead of ballooning into the ribbon's old room.
		local labelSize = MET.LABEL or ((MET.W >= 80) and 18 or 14)
		local labelH = labelSize + 4
		local room = MET.H - labelH - 2
		local box = math.min(MET.W, room, math.floor(MET.H * 0.65))
		-- STYLE REPLACEMENT (2026-08-04, Pet-Sim guide): the emoji glyph is
		-- retired for the same reason as the nav rail's -- a colour emoji cannot
		-- carry the guide's mandatory ink outline (UIStroke/TextStroke/UIPolish
		-- are all no-ops on them, probed live). UIKit.IconArt draws skip / shops
		-- / plot from GUI primitives WITH outlines, so the tabs go back to that
		-- artwork; the emoji stays only as the fallback when IconArt has no
		-- entry for this tab (or fails to load), which is also what keeps this
		-- safe if a future tab has no drawing yet.
		local drew = nil
		if IconArt and spec.icon and IconArt.has(spec.icon) then
			local holder = Instance.new("Frame")
			holder.Name = "StickerGlyph" -- name kept: applyStickerGlyph's own idempotency sweep looks for it
			holder.AnchorPoint = Vector2.new(0.5, 0.5)
			holder.Position = UDim2.new(0.5, 0, 0, math.floor(room * 0.5) + 2)
			holder.Size = UDim2.fromOffset(box, box)
			holder.BackgroundTransparency = 1
			holder.Rotation = spec.tilt or 0
			holder.ZIndex = btn.ZIndex + 3
			holder.Parent = btn
			IconArt.draw(holder, spec.icon, box, holder.ZIndex)
			drew = holder
		end
		if not drew then
			local glyph = Instance.new("TextLabel")
			glyph.Name = "StickerGlyph"
			glyph.AnchorPoint = Vector2.new(0.5, 0.5)
			glyph.Position = UDim2.new(0.5, 0, 0, math.floor(room * 0.5) + 2)
			glyph.Size = UDim2.fromOffset(box, box)
			glyph.BackgroundTransparency = 1
			glyph.Font = Enum.Font.FredokaOne
			glyph.TextSize = box
			glyph.Text = spec.glyph
			glyph.Rotation = spec.tilt or 0
			glyph.ZIndex = btn.ZIndex + 3
			-- emoji must not be re-coloured or outlined by the UIPolish sweep
			glyph:SetAttribute("NoPolish", true)
			glyph.Parent = btn
		end

		local word = Instance.new("TextLabel")
		word.Name = "StickerWord"
		word.AnchorPoint = Vector2.new(0.5, 1)
		word.Position = UDim2.new(0.5, 0, 1, 0)
		word.Size = UDim2.new(0, MET.W + 14, 0, labelH)
		word.BackgroundTransparency = 1
		word.Font = Enum.Font.FredokaOne
		word.TextSize = labelSize
		word.TextColor3 = Color3.fromRGB(255, 255, 255)
		word.Text = string.upper(spec.word)
		word.ZIndex = btn.ZIndex + 3
		-- our own keyline; keep the game-wide sweep's hands off it
		word:SetAttribute("NoPolish", true)
		local ink = Instance.new("UIStroke")
		ink.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		ink.Thickness = 3
		ink.Color = Color3.fromHex("#1c1333")
		ink.Parent = word
		word.Parent = btn
	end

	-- LABEL is carried per-metric rather than derived from W. Deriving it meant
	-- shrinking the card shrank the word with it, so the phone step below took
	-- SKIP/SHOPS/PLOT down to 14px -- smaller than they were on a 1080p monitor,
	-- on the device held closest to your face. The card shrinks; the word does
	-- not. At 17px on a 361-tall screen the label is ~4.7% of the height, vs
	-- 1.7% for 18px on desktop, so it reads bigger where it needs to.
	local WIDE    = { W = 86, H = 104, GAP = 30, LABEL = 18 }
	local COMPACT = { W = 64, H = 80,  GAP = 24, LABEL = 16 }
	-- 2026-08-05: a third, phone-sized step. pickMetrics only ever solved for
	-- horizontal room, and a 750x361 handset has plenty of WIDTH -- so it chose
	-- WIDE and the SKIP/SHOPS/PLOT bar rendered 318x104, which is 42% of the
	-- width and 29% of the HEIGHT of the screen. Height was never in the sum.
	local TINY    = { W = 46, H = 56,  GAP = 14, LABEL = 17 }
	local TOP_Y, UNDER_PILL_Y = 10, 66

	-- the cash pill: 190 wide, 12 from the right edge, occupying y 12..58
	local CASH_W, CASH_MARGIN, CLEARANCE = 190, 12, 10

	local cam = Workspace.CurrentCamera
	local function barWidth(MET) return #RAIL * MET.W + (#RAIL - 1) * MET.GAP end

	-- A centred bar of width B clears the pill when B < vx - 2*(CASH_W + margin
	-- + clearance). Solved rather than guessed at a breakpoint, so it stays
	-- correct if the pill is ever resized.
	--
	-- MEASURED, NOT ASSUMED (2026-08-21, beta pass). The claim above stopped being
	-- true: CASH_W describes a 190-wide pill in the top-RIGHT corner, and the
	-- currency cluster has since moved top-LEFT and grown with the layout --
	-- measured 620px on Desktop, 694 on Tablet, 830 on Phone, up to 4x what the
	-- constant reserves. The sum still "solved", still answered WIDE at TOP_Y, and
	-- on the phone layout laid the centred bar straight over the cluster: bar left
	-- edge 745 against a cluster right edge of 865, a 119x58px overlap with the
	-- SKIP tab sitting under the emerald pill. Desktop cleared by 156px and Tablet
	-- by 23px, which is the only reason this never showed up on a monitor.
	--
	-- Two terms were missing and both belong in the sum:
	--   * the cluster's REAL right edge, read off the instance every pass
	--   * PlatformFitScale, the UIScale on tabBar -- 1.35 on Tablet and Phone. The
	--     metrics below are authored UNSCALED, so barWidth() is not the width that
	--     actually lands on the screen.
	-- Both are read fresh here rather than cached: applyLayout re-runs on every
	-- viewport and platform change, which is exactly when they move.
	local function pickMetrics()
		-- Platform.Viewport, not the camera (2026-08-27). This function's entire job
		-- is to pick a tab size that fits the screen, and reading the real Studio
		-- window meant it always measured 1920x1077 -- so `roomH = vp.Y * 0.17` came
		-- out at 183px, WIDE's 104px tabs "fitted", and a handset got 104px tabs that
		-- are 30% of its total height. With the real device size it falls through to
		-- TINY (46x56) as it was always designed to.
		local vp = Platform.Viewport

		-- CASH_W + CASH_MARGIN stays as the floor, so a missing or not-yet-laid-out
		-- cluster degrades to the old behaviour instead of to zero clearance.
		local cluster = gui.Parent:FindFirstChild("GameHUD")
		cluster = cluster and cluster:FindFirstChild("Chrome")
		cluster = cluster and cluster:FindFirstChild("CurrencyCluster")
		local blockRight = CASH_W + CASH_MARGIN
		if cluster and cluster.Visible and cluster.AbsoluteSize.X > 1 then
			blockRight = math.max(blockRight, cluster.AbsolutePosition.X + cluster.AbsoluteSize.X)
		end

		local fit = tabBar:FindFirstChild("PlatformFitScale")
		fit = (fit and fit:IsA("UIScale") and fit.Scale > 0) and fit.Scale or 1

		local room = vp.X - 2 * (blockRight + CLEARANCE)
		-- A nav bar has no business taking more than ~17% of the screen height.
		-- Expressed against the live viewport rather than a device check, so it
		-- also fixes short desktop windows and needs no platform lookup here.
		local roomH = vp.Y * 0.17
		if barWidth(WIDE) * fit <= room and WIDE.H * fit <= roomH then return WIDE, TOP_Y end
		if barWidth(COMPACT) * fit <= room and COMPACT.H * fit <= roomH then return COMPACT, TOP_Y end
		if barWidth(TINY) * fit <= room then return TINY, TOP_Y end

		-- Nothing fits beside the cluster: stack the bar UNDER it. UNDER_PILL_Y (66)
		-- was measured against that same old 190x46 pill and is NOT below the cluster
		-- any more -- it is 131px tall on the phone layout -- so dropping to the
		-- constant just traded a sideways overlap for a vertical one. Measure it too.
		--
		-- Frame conversion matters here: topY is applied as tabBar.Position, which is
		-- relative to MainUI, while the cluster is measured in absolute screen space.
		-- BOTH ScreenGuis set IgnoreGuiInset, so MainUI's own AbsolutePosition.Y is
		-- -58 (the topbar inset), not 0 -- subtracting it is what keeps the two
		-- agreeing. Do not simplify this to a bare AbsolutePosition.Y.
		local underY = UNDER_PILL_Y
		if cluster and cluster.Visible and cluster.AbsoluteSize.Y > 1 then
			underY = math.max(underY,
				(cluster.AbsolutePosition.Y + cluster.AbsoluteSize.Y) - gui.AbsolutePosition.Y + CLEARANCE)
		end
		-- TINY ON TOUCH, not COMPACT (2026-08-27).
		--
		-- Reaching here means the bar could not fit BESIDE the cluster, and the width
		-- test that decides that is `vp.X - 2 * blockRight` -- doubled, because a
		-- CENTRED bar has to clear the cluster on the left and its mirror image on the
		-- right. Sound for centring, brutal on a phone: measured at 667x375 the
		-- cluster is 253px wide, so a centred bar gets 139px and even TINY (166px)
		-- "does not fit" -- and the fallback then handed back COMPACT, the SECOND
		-- largest set, at 80px tall on a 375px screen. The narrowest option was
		-- rejected for being too wide and replaced with a wider one.
		--
		-- Below the cluster there is no such constraint: the bar has the whole width.
		-- HudLayout's `avoid` already does the moving, so all this has to do is pick a
		-- set that suits a small screen.
		if Platform.IsTouch then return TINY, underY end
		return COMPACT, underY
	end

	-- The authored wooden decorations stay hidden rather than destroyed: a
	-- collaborator's script may still look them up by name.
	local function stripLegacy(btn)
		for _, n in ipairs({ "Accent", "Gloss", "Nail1", "Nail2" }) do
			local d = btn:FindFirstChild(n)
			if d then d.Visible = false end
		end
		for _, n in ipairs({ "TabBase", "TabFace" }) do   -- from the campfire pass
			local d = btn:FindFirstChild(n)
			if d then d:Destroy() end
		end
		for _, s in ipairs(btn:GetChildren()) do
			if s:IsA("UIStroke") and s.Name ~= "UIStyleStrokeBorder" then s.Transparency = 1 end
		end
	end

	-- TV OVERSCAN. A television does not draw the outer few percent of the
	-- signal. This bar hangs off the TOP edge, and measured on a console it sat
	-- at y=-11 -- above the title-safe line, partly not drawn at all.
	--
	-- It has to be solved here rather than by PlatformClient's blanket edge
	-- nudge, because applyLayout rewrites tabBar.Position on every viewport
	-- change and would overwrite that nudge -- after which the nudge's own
	-- bookkeeping would subtract a shift that was no longer applied, walking the
	-- bar further off on each pass. Whoever writes Position last has to own the
	-- inset, so the bar opts out of the blanket pass and applies its own.
	tabBar:SetAttribute("TVSafeSelfManaged", true)

	-- The OVERSCAN part of the top inset only -- deliberately not the Roblox
	-- topbar, which MainUI ignores by design and which would move the bar on
	-- desktop. Derived by subtracting the topbar back out rather than repeating
	-- Platform's 3.5% constant, so the two cannot drift. Returns exactly 0 on
	-- every non-console device, which is what keeps desktop pixel-identical.
	local function overscanTop(): number
		return math.max(Platform.Insets().Top - GuiService:GetGuiInset().Y, 0)
	end

	local function applyLayout(MET, topY)
		tabBar.BackgroundTransparency = 1
		tabBar.BorderSizePixel = 0
		tabBar.Size = UDim2.fromOffset(barWidth(MET), MET.H)
		tabBar.ZIndex = 2
		-- HUDLAYOUT OWNS THE BAR'S POSITION (2026-08-26). Two separate bugs lived in
		-- the single line this replaces:
		--
		--   1. MainUI sets IgnoreGuiInset, so an offset of topY renders topY - 58.
		--      Measured across every device: the SKIP / SHOPS / PLOT tabs sat at
		--      y = -48, i.e. half of each tab was behind the Roblox topbar and taps
		--      in that band went past the UI into the world. HudLayout adds the inset
		--      back for full-bleed guis, so the bar lands where the number says.
		--   2. pickMetrics decides whether the bar fits beside the currency cluster by
		--      reading that cluster's AbsolutePosition out of GameHUD's ScreenGui and
		--      converting between two inset spaces by hand. The `avoid` flag asks the
		--      layout that placed both instead -- the top-left stack is laid first, so
		--      the bar simply steps below the cluster when there is no room beside it.
		if not tabSlot then
			tabBar.AnchorPoint = Vector2.new(0.5, 0)
			tabBar.Position = UDim2.new(0.5, 0, 0, topY + overscanTop())
		end

		local layout = tabBar:FindFirstChildOfClass("UIListLayout")
		if not layout then layout = Instance.new("UIListLayout", tabBar) end
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Top
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, MET.GAP)

		for _, spec in ipairs(RAIL) do
			local btn = spec.btn
			if btn then
				stripLegacy(btn)
				btn.LayoutOrder = spec.order
				btn.ZIndex = 2
				btn.Size = UDim2.fromOffset(MET.W, MET.H)
				UIStyle.sticker(btn, {
					accent = spec.accent,
					label  = spec.word,
					glyph  = spec.glyph,
					badge  = false,     -- flip on via UIStyle.stickerBadge(btn, true)
				})
				applyStickerGlyph(btn, spec, MET)
			end
		end
	end

	-- Fires immediately AND on every later device change. The viewport listener
	-- below is not enough on its own: picking up a controller or landing on a
	-- console changes the overscan inset without the window size moving at all.
	--
	-- THREE PASSES, and the later two are load-bearing (2026-08-21). pickMetrics
	-- now MEASURES the currency cluster rather than assuming CASH_W, and that
	-- cluster is resized by its OWN Platform.Watch -- registration order decides
	-- which of the two runs first, and ours runs while the cluster is still at its
	-- previous size. So the first pass solves against a stale, too-small right edge
	-- and picks a bar that does not actually fit: on the phone layout that is
	-- precisely the 119px SKIP-tab overlap the measurement was added to remove, and
	-- it looks like the fix simply did not work.
	--
	-- task.defer re-runs after every watcher in this cycle has had its turn; the
	-- 0.12 beat then catches anything that resizes across a yield or a tween. Same
	-- defer-plus-a-beat idiom the bag uses to restore its scroll position.
	-- applyLayout is idempotent by contract (see its header), so the repeats are free.
	Platform.Watch(function()
		applyLayout(pickMetrics())
		task.defer(function() applyLayout(pickMetrics()) end)
		task.delay(0.12, function() applyLayout(pickMetrics()) end)
	end)

	-- Re-layout on viewport changes, debounced so a drag-resize does not
	-- rebuild every frame. Token pattern: only the newest wait wins.
	local resizeToken = 0
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			resizeToken += 1
			local myToken = resizeToken
			task.delay(0.12, function()
				if myToken ~= resizeToken then return end
				applyLayout(pickMetrics())
			end)
		end)
	end

	-- === Cash pill ===
	-- Same sticker language: gold gradient, white keyline, white FredokaOne.
	if cashFrame then
		cashFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		cashFrame.BorderSizePixel = 0
		UIStyle.pill(cashFrame)
		UIStyle.gradient(cashFrame, UIStyle.Palette.Gold)
		UIStyle.stroke(cashFrame, Color3.fromRGB(255, 255, 255), 3.5)

		local gloss = cashFrame:FindFirstChild("Gloss")
		if gloss then
			gloss.Visible = true
			local gg = gloss:FindFirstChildOfClass("UIGradient")
			if gg then
				gg.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.68), NumberSequenceKeypoint.new(1, 1) })
			end
		end

		local badge = cashFrame:FindFirstChild("CoinBadge")
		if badge then
			UIStyle.pill(badge)
			UIStyle.gradient(badge, { light = Color3.fromRGB(255, 236, 150),
			                          dark  = Color3.fromRGB(250, 190, 40) })
			UIStyle.stroke(badge, Color3.fromRGB(255, 255, 255), 2.5)
		end

		if cashLabel then
			UIStyle.bubbleText(cashLabel, UIStyle.Palette.Gold)
		end
	end
end


-- === Sprint (Left Shift hold, or button toggle) ===
local WALK_SPEED = 20.8
local SPRINT_SPEED = 33.8
local shiftHeld = false
local sprintToggled = false

local sprintButton = gui:WaitForChild("SprintButton")
-- PHONE (2026-08-17 device-sim audit): the button is authored 138x50 desktop
-- px and nothing scaled it on handsets, where it anchors the oversized corner
-- stack. Its authored AnchorPoint is (1,1) at (1,-16),(1,-16) -- verified on
-- the StarterGui instance -- so a UIScale shrinks it INTO the corner, no
-- drift.
--
-- 0.85 -> 0.88 (2026-08-25). 0.85 was called "still a legitimate touch target"
-- on the strength of 117x43; measured on a phone-classed client it renders
-- 117x42, i.e. it was ALWAYS a rounding error under Roblox's 44px minimum, and
-- this is a core control -- the only way to sprint without a keyboard. 138x50 at
-- 0.88 is 121x44, which clears it. Anchored (1,1) into the corner, so the extra
-- 4px grows away from the screen edge and nothing else moves.
-- HUDLAYOUT OWNS THIS BUTTON'S POSITION (2026-08-26).
--
-- The -96 below is the clearest example in the place of why this HUD could not
-- be fixed a widget at a time. It is not a design value; it is the residue of
-- probing THREE other things live on one specific handset -- HudToggle's pill
-- ("ends 168"), Roblox's jump band ("starts 262"), and the 20px disagreement
-- between MainUI's and HudToggleUI's inset modes -- and picking a number that
-- happened to fit between them on that device. Any of the three moving, or a
-- different screen, invalidates it, and two of the three are themselves
-- positioned by the same kind of constant.
--
-- The stack replaces all of it: Sprint is simply the bottom item of the
-- bottom-right column, above the luck chip, and the column starts above the
-- touch-control band because Platform.Insets() says where that band is.
local sprintSlot = HudLayout.Attach(sprintButton, {
	stack = "BottomRight",
	order = HudLayout.Order.Sprint,
})

do
	local s = Instance.new("UIScale")
	s.Name = "DeviceScale"
	s.Parent = sprintButton
	Platform.Watch(function()
		s.Scale = Platform.IsPhone and 0.88 or 1
		if sprintSlot then return end   -- stack owns Position; legacy path below
		-- and LIFT it clear of Roblox's jump button on touch (the bottom-right
		-- ~112px phone band) -- the pill sat directly ON the jump circle in the
		-- 2026-08-18 mobile video. -120 slots it into the free lane BETWEEN the
		-- jump band (bottom ~112px) and HudToggleClient's relocated HIDE UI
		-- (probed live at abs y134-168 on a 374-tall phone viewport; -152 landed
		-- exactly on it and the toggle drew over the pill). Desktop unchanged.
		sprintButton.Position = Platform.IsTouch
			and UDim2.new(1, -16, 1, -96) -- probed live: MainUI ignores the topbar inset, HudToggleUI does not, so their y-spaces differ ~20px; -96 lands Sprint at abs y177-220 (HIDE UI ends 168, jump starts 262)
			or UDim2.new(1, -16, 1, -16)
	end)
end
-- Authored in StarterGui and only ever handed to UITheme.setColors, which is a
-- COLOUR swap and wires nothing -- so it passed through no constructor and was
-- silent. Wired directly, with the same SfxWired guard the constructors use so
-- it can never end up double-connected.
if not sprintButton:GetAttribute("SfxWired") then
	sprintButton:SetAttribute("SfxWired", true)
	sprintButton.MouseButton1Click:Connect(function()
		pcall(SoundKit.play, "uiClick", nil, { volume = 0.12 })
	end)
end

local function getHumanoid()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function applySprint()
	local sprinting = shiftHeld or sprintToggled
	local hum = getHumanoid()
	if hum then
		local speed = sprinting and SPRINT_SPEED or WALK_SPEED
		-- VIP ELECTRIC SCOOTER, the speed half. 1.75x (up from 1.55 on 2026-08-09) on top
		-- of walk OR sprint rather than a fixed replacement, so riding beats running
		-- instead of making sprint pointless while you are on it. ScooterService (server) welds the prop and
		-- flips the attribute; the speed has to be applied HERE because this function
		-- is the one writer of WalkSpeed -- it runs on every input and every respawn,
		-- so anything the server set would be overwritten within a frame. Read inline,
		-- with no local to hold it: see the register note on the AUTO button above.
		if player:GetAttribute("ScooterOn") == true then speed = speed * 1.75 end
		-- ICE FISHING plants you at the hole for the length of a cast, the same way a skip
		-- has you planted on the dock. IceFishingEvent sets the attribute; it is read inline
		-- here for the same register reason as ScooterOn, and it MUST be applied in this
		-- function -- applySprint is the one writer of WalkSpeed and runs on every input, so
		-- a speed set anywhere else would be overwritten within a frame.
		if player:GetAttribute("Fishing") == true then speed = 0 end
		hum.WalkSpeed = speed
		hum.AutoRotate = player:GetAttribute("Fishing") ~= true
	end
	-- PS99 colour grammar (2026-08-17): ACTIVE = GREEN (same as the Auto
	-- button's engaged state); gold is reserved for real money and "sprinting"
	-- wearing it read as a purchase surface
	if sprinting then UITheme.setColors(sprintButton, UITheme.Palette.green1, UITheme.Palette.green2)
	else UITheme.setColors(sprintButton, UITheme.Palette.hudShop1, UITheme.Palette.hudShop2) end
	sprintButton.Text = sprinting and "🏃 Sprinting" or "🏃 Sprint"
end
-- the lock goes on and comes off with the attribute, not on the next input
player:GetAttributeChangedSignal("Fishing"):Connect(applySprint)

player.CharacterAdded:Connect(function(char)
	local hum = char:WaitForChild("Humanoid")
	hum.WalkSpeed = (shiftHeld or sprintToggled) and SPRINT_SPEED or WALK_SPEED
end)

-- === VIP electric scooter: the jump half ===
-- Wrapped in a do-block so its three locals are released again rather than held for
-- the rest of the chunk -- the register ceiling this file is up against is about how
-- many locals are live AT ONCE. The connections keep what they capture alive.
do
	local baseJump = nil
	-- PARK THE DEFAULT ANIMATIONS WHILE RIDING. The walk and idle clips keep running
	-- otherwise, and the legs pedal away underneath a rider who is supposed to be
	-- standing on a board -- the pose below already owns the hips and knees, so what
	-- shows through is a half-driven stride fighting a static stance.
	--
	-- Disabling the Animate LocalScript is reversible and rig-agnostic: re-enabling it
	-- restarts the script, which re-binds and resumes as if nothing happened. Order
	-- matters on dismount -- Animate comes back BEFORE the ride pose stops being
	-- written, or the body holds the last posed frame until something else moves it.
	local function setDefaultAnimations(on)
		local char = player.Character
		local animate = char and char:FindFirstChild("Animate")
		if animate then animate.Disabled = not on end
	end

	local function applyScooter()
		local hum = getHumanoid()
		if not hum then return end
		setDefaultAnimations(player:GetAttribute("ScooterOn") ~= true)
		-- Captured before anything of ours writes it, and restored EXACTLY as found --
		-- every field. A place can be on JumpHeight rather than JumpPower, and leaving
		-- UseJumpPower flipped would quietly change how everyone jumps for the rest of
		-- the session, long after the scooter was put away.
		if not baseJump then
			baseJump = { use = hum.UseJumpPower, power = hum.JumpPower,
				height = hum.JumpHeight, hip = hum.HipHeight }
		end
		if player:GetAttribute("ScooterOn") == true then
			hum.UseJumpPower = true
			hum.JumpPower = 105        -- stock is 50; the hop is the point of the thing
			-- STAND ON IT, don't stand IN it. A Humanoid pins its feet to the floor, so
			-- the deck welded under them is really welded into the floor unless the rider
			-- comes up to meet it. 0.7 MUST MATCH ScooterService.LIFT, which is what the
			-- server measures the deck and wheels against -- it cannot be required from
			-- here (ServerScriptService), so the two are kept in step by hand.
			hum.HipHeight = baseJump.hip + 0.7
		else
			hum.UseJumpPower = baseJump.use
			hum.JumpPower = baseJump.power
			hum.JumpHeight = baseJump.height
			hum.HipHeight = baseJump.hip
		end
		applySprint()
	end

	player.CharacterAdded:Connect(function(char)
		char:WaitForChild("Humanoid")
		baseJump = nil   -- a new rig has stock numbers again; the old capture must go
		applyScooter()
	end)
	-- The server flips this on equip and unequip, and clears it on every respawn.
	player:GetAttributeChangedSignal("ScooterOn"):Connect(applyScooter)
	if player.Character then applyScooter() end

	--[[ ===== THE RIDE ITSELF =====

	Everything here is per-frame, and that is the whole point: a board that only moved
	when you pressed something reads as a prop you are standing on, not a thing you are
	riding. Four channels, all driven off what the character is ACTUALLY doing rather
	than off the input -- so it reads the same on keyboard, thumbstick or click-to-move,
	and stays honest when something else moves you:

	  BANK   from the yaw rate. Lean into the turn, board and body together.
	  PITCH  from forward acceleration. Nose up under power, down off it.
	  FLOAT  a slow sine on the weld, with the knees soaking it up in counter-phase so
	         the rider rides the float instead of levitating rigidly with it.
	  SPEED  eased toward the target rather than snapped, so pulling away feels like
	         acceleration and not like a switch.

	LOCAL VIEW ONLY, unavoidably. Both halves -- AnimationConstraint.Transform and the
	weld's C0 -- are client property writes, and Roblox does not replicate those. Other
	players see a rider standing on a level board. The existing throw animation has the
	same limitation for the same reason; making either visible to everyone needs the
	pose baked into an uploaded animation asset, which only the owner can publish.
	]]
	local BOB_RATE, BOB_DEPTH = 3.1, 0.055
	local LEAN_MAX, PITCH_MAX = 0.5, 0.4     -- radians of board roll / pitch at full tilt
	local lean, pitch, speedNow, clock = 0, 0, 0, 0
	local lastYaw, lastSpeed = nil, 0
	-- MOUNT AND DISMOUNT ARE A BLEND, NOT A CUT (2026-08-09). The pose used to arrive
	-- and leave on one frame, which is the one moment a procedural stance reads as
	-- wrong -- the body snapped into a crouch and snapped back out mid-stride. `blend`
	-- eases 0..1 and every joint is lerped from neutral by it, so stepping on and off
	-- takes about a fifth of a second. `fullPose` is the stance at blend 1, kept so the
	-- fade-OUT still has something to fade from after the ride has already ended.
	local blend, fullPose = 0, nil

	local function toward(v, target, dt, rate)
		return v + (target - v) * (1 - math.exp(-rate * dt))
	end

	local function faded(pose, alpha)
		if not pose then return nil end
		if alpha >= 0.999 then return pose end
		local out = {}
		for name, cf in pairs(pose) do out[name] = CFrame.identity:Lerp(cf, alpha) end
		return out
	end

	RunService.RenderStepped:Connect(function(dt)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local riding = (player:GetAttribute("ScooterOn") == true) and hum ~= nil and hrp ~= nil
		blend = toward(blend, riding and 1 or 0, dt, 9)

		if not riding then
			-- Forget the ride's state, so the next mount starts from a standstill rather
			-- than resuming mid-lean -- but keep FADING the stance out for a few frames.
			lastYaw, lean, pitch, speedNow = nil, 0, 0, 0
			if blend < 0.02 then
				blend, fullPose, ridePose = 0, nil, nil
			else
				ridePose = faded(fullPose, blend)
			end
			return
		end
		clock += dt

		local look = hrp.CFrame.LookVector
		local yaw = math.atan2(look.X, look.Z)
		local dYaw = 0
		if lastYaw then
			-- shortest way round, or every pass through +/-pi reads as a violent turn
			dYaw = (yaw - lastYaw + math.pi) % (2 * math.pi) - math.pi
		end
		lastYaw = yaw
		-- 0.34 rather than 0.42: at the higher gain an ordinary mouse turn pegged the
		-- bank at full tilt and held it there, so every corner looked identical. This
		-- saturates around 3 rad/s, which leaves normal steering somewhere in between.
		lean = toward(lean, math.clamp((dt > 0 and dYaw / dt or 0) * 0.34, -1, 1), dt, 7)

		-- Flat speed, so riding down a hill does not read as accelerating. Tuned up from
		-- /45 at rate 5, which was too slow to catch a launch: pulling away is one hard
		-- spike of acceleration over two or three frames, and at that response the nose
		-- had barely lifted before the spike was gone.
		local vel = hrp.AssemblyLinearVelocity
		local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		pitch = toward(pitch, math.clamp((dt > 0 and (speed - lastSpeed) / dt or 0) / 30, -1, 1), dt, 8)
		lastSpeed = speed

		local bob = math.sin(clock * BOB_RATE) * BOB_DEPTH

		-- SPEED RAMP. Seeded from the walking speed rather than from hum.WalkSpeed --
		-- applySprint has already put the scooter multiplier on that by now, and seeding
		-- from it would start the ramp at its destination and there would be no ramp.
		local base = (shiftHeld or sprintToggled) and SPRINT_SPEED or WALK_SPEED
		if speedNow <= 0 then speedNow = base end
		speedNow = toward(speedNow, base * 1.75, dt, 5.5)
		hum.WalkSpeed = speedNow

		local scooter = char:FindFirstChild("ElectricScooter")
		local deck = scooter and scooter:FindFirstChild("Deck")
		local weld = deck and deck:FindFirstChild("RideWeld")
		if weld then
			-- Base from the attribute, never from the live C0 -- that is already a frame
			-- of this animation, and compounding it would walk the board away.
			local baseC0 = weld:GetAttribute("BaseC0") or weld.C0
			-- BANK INTO THE TURN. The sign is measured, not reasoned: with the roll
			-- negated the board leaned OUT of every corner -- 116 samples of a steady
			-- right-hand turn, and the deck's up-vector pointed left in every one of them.
			weld.C0 = baseC0
				* CFrame.new(0, bob, 0)
				* CFrame.Angles(pitch * PITCH_MAX, 0, lean * LEAN_MAX)
		end

		-- Knees take the float in counter-phase to the deck, which is what stops the
		-- rider looking bolted to a bobbing plank.
		local flex = bob * 90
		fullPose = {
			Waist         = A(12 + pitch * 7, 0, lean * 9),
			Neck          = A(-9, 0, lean * -4),
			-- hands out to the bars: elbows straighter than the first pass, which left
			-- them folded short of the grips
			LeftShoulder  = A(52 + pitch * 5, 0, -11),
			RightShoulder = A(52 + pitch * 5, 0, 11),
			LeftElbow     = A(-17, 0, 0),
			RightElbow    = A(-17, 0, 0),
			LeftHip       = A(15, 0, 0),                 -- front foot leads down the deck
			LeftKnee      = A(-30 - flex, 0, 0),         -- knees NEGATIVE to bend, per the
			RightHip      = A(-5, 0, 0),                 -- sign convention on the throw poses
			RightKnee     = A(-21 - flex, 0, 0),
		}
		ridePose = faded(fullPose, blend)
	end)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.LeftShift then
		shiftHeld = true
		applySprint()
	end
	-- Controllers: L3 (click the left stick) is the platform convention for
	-- sprint. It TOGGLES rather than holds, because holding a thumbstick clicked
	-- in while also steering with it is not something you can ask of a player --
	-- which is exactly why the keyboard's hold-to-sprint does not port directly.
	-- Shares sprintToggled with the on-screen button, so the two agree.
	if input.KeyCode == Enum.KeyCode.ButtonL3 then
		sprintToggled = not sprintToggled
		applySprint()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		shiftHeld = false
		applySprint()
	end
end)

sprintButton.Activated:Connect(function()
	sprintToggled = not sprintToggled
	applySprint()
end)

applySprint()

-- === Throw-zone gating ===
-- ONE ZONE PER SKIP AREA, and there are two: the hub dock and the Frozen Tundra's
-- ice deck 8000 studs out. This used to be a single WaitForChild on GameWorld.ThrowZone,
-- so at the tundra deck the HUD sat on "GO TO SKIP AREA" forever while the server --
-- which does its own check -- would happily have taken the throw.
--
-- Matched to ThrowHandler's throwZoneOf: any BasePart named ThrowZone under GameWorld,
-- same box test, same generous Y. Rebuilt on add/remove rather than walked per frame;
-- GameWorld is far too big to search inside a Heartbeat.
local throwZones = {}
local function rebuildThrowZones()
	table.clear(throwZones)
	for _, d in ipairs(gameWorld:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "ThrowZone" then
			table.insert(throwZones, d)
		end
	end
end
rebuildThrowZones()
gameWorld.DescendantAdded:Connect(function(d)
	if d.Name == "ThrowZone" and d:IsA("BasePart") then rebuildThrowZones() end
end)
gameWorld.DescendantRemoving:Connect(function(d)
	if d.Name == "ThrowZone" and d:IsA("BasePart") then task.defer(rebuildThrowZones) end
end)

local function computeInZone()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	currentZone = nil
	if not hrp then return false end
	-- ICE FISHING: the Frozen Tundra dock's throw zone is switched off while the lake is
	-- frozen -- you fish at the holes instead. Reading it here means the whole throw
	-- pipeline (minigame UI, auto-skip, gamepad bind) treats that dock as "not a zone".
	local iceOn = ReplicatedStorage:GetAttribute("IceFishingActive") == true
	for _, zone in ipairs(throwZones) do
		local rel = zone.CFrame:PointToObjectSpace(hrp.Position)
		local s = zone.Size / 2
		if math.abs(rel.X) <= s.X and math.abs(rel.Z) <= s.Z and math.abs(rel.Y) <= s.Y + 6 then
			if iceOn and zone:FindFirstAncestor("FrozenTundra") then return false end
			currentZone = zone   -- carries this world's CatchesEnabled flag
			return true
		end
	end
	return false
end

local prevInZone = false
-- The breath gate rides the throw-zone Heartbeat that already exists rather than
-- adding a loop of its own. It only ever starts/stops tweens -- the animation
-- itself is engine-driven.
local function updateBreathGate()
	local offer = inThrowZone and not charging and not cooldown
		and throwFrame.Visible and throwButton.Visible
	if not offer then
		stopBreath()
		return
	end
	if os.clock() - lastThrowAt >= BREATH_IDLE then
		startBreath()
	end
end
RunService.Heartbeat:Connect(function()
	inThrowZone = computeInZone()
	-- ...and only where there is something to catch, so a controller cannot take the
	-- route the touch/mouse path now refuses.
	setThrowBinding(inThrowZone and not zoneCatchesDisabled() and not bagFull())
	updateBreathGate()
	if inThrowZone and not prevInZone then refreshSweetSpot() end -- fresh spot on walk-up
	prevInZone = inThrowZone
	-- only show the throw UI at the dock (stay visible mid-throw so it doesn't vanish)
	-- ...and never ON TOP OF AN OPEN PANEL on phone. This line is the sole owner of
	-- ThrowFrame.Visible and reasserts it every frame, so the PanelHost watcher up by
	-- the teleport tabs cannot just write false -- it parks its intent in PanelHidden
	-- and this AND reads it. Nothing sets that attribute on desktop, GetAttribute
	-- returns nil there, and the expression stays exactly the one it has always been.
	throwFrame.Visible = (inThrowZone or charging or cooldown)
		and not throwFrame:GetAttribute("PanelHidden")
	if charging or cooldown then return end
	local wantText, cTop, cBot
	if not inThrowZone then
		wantText, cTop, cBot = "GO TO SKIP AREA", UITheme.Palette.hudMuted1, UITheme.Palette.hudMuted2
	elseif zoneCatchesDisabled() then
		-- Checked BEFORE the plot rule: in a world with no roster, "get a plot" would be
		-- advice that leads nowhere. Say the true thing instead.
		wantText, cTop, cBot = "COMING SOON", UITheme.Palette.hudMuted1, UITheme.Palette.hudMuted2
	elseif not playerHasPlot() then
		wantText, cTop, cBot = "GET A PLOT FIRST", UITheme.Palette.hudGold1, UITheme.Palette.hudGold2
	elseif bagFull() then
		-- Last of the blocking branches, so the new-player funnel above still wins:
		-- someone with no plot gets pointed at a plot (and tapping the button takes
		-- them to one), which is the more useful thing to say. By the time a bag is
		-- full the player has certainly claimed a base.
		wantText, cTop, cBot = "BAG FULL", UITheme.Palette.hudMuted1, UITheme.Palette.hudMuted2
	else
		wantText, cTop, cBot = DEFAULT_THROW_TEXT, UITheme.Palette.hudThrow1, UITheme.Palette.hudThrow2
	end
	if throwButton.Text ~= wantText then
		throwButton.Text = wantText
		UITheme.setColors(throwButton, cTop, cBot)
	end
end)

-- === Stone tracking camera (far throws) ===
-- Lives in ReplicatedStorage.Modules.ThrowCam since 2026-09-21 (chase -> glide ->
-- dwell -> eased return, quick-throw setting, cut handoff); the block at the bottom of
-- this file is the wiring. TRACK_MIN_DISTANCE is ThrowCam.CFG.minDistance now.
local stoneThrownRemote = remotes:WaitForChild("StoneThrown")

-- === Skip counter =========================================================
-- ThrowHandler computes nContacts (2..8) to lay out the arc and now ships it,
-- with segTime, on the StoneThrown payload. Splash k fires server-side at
-- k*segTime after that payload is sent; the payload and each splash sound both
-- reach us one-way-late, so the latency cancels and ticking at k*segTime after
-- RECEIVING lands on the splash. TICK_LEAD is perceptual only -- a visual a hair
-- ahead of its audio reads as simultaneous, behind reads as lag.
--
-- AUTHORED IN STUDIO, NOT HERE: this code only drives an element that a human
-- placed. Expected at PlayerGui.MainUI.SkipCounter (TextLabel) with a UIScale
-- child for the pop. Missing element = silent no-op (warned once), never a
-- runtime error and never an Instance.new UI.
local SKIP_TICK_LEAD  = 0.03   -- seconds BEFORE the splash the number flips
local SKIP_POP_SCALE  = 1.45   -- pop peak, settles to 1
local SKIP_POP_TIME   = 0.18   -- seconds, Back/Out
local SKIP_CLEAR_SAFE = 1.5    -- seconds after the last skip (~ when the rock lands) before the counter auto-hides, so it does not linger through the catch reveal

local skipCounterWarned = false
local skipToken = 0

local function skipCounterLabel()
	local gui = player:FindFirstChild("PlayerGui")
	local mainUi = gui and gui:FindFirstChild("MainUI")
	local label = mainUi and mainUi:FindFirstChild("SkipCounter", true)
	if not label and not skipCounterWarned then
		skipCounterWarned = true
		warn("[ClientMain] SkipCounter not authored yet -- expected PlayerGui.MainUI.SkipCounter (TextLabel + UIScale child). Skip count will not display.")
	end
	return label
end

local function hideSkipCounter()
	skipToken += 1
	local label = skipCounterLabel()
	if label then label.Visible = false end
end
clearSkipCounter = hideSkipCounter   -- startCharge calls this (forward-declared above)

local function runSkipCounter(nContacts, segTime, totalTime, distance)
	local label = skipCounterLabel()
	if not label then return end
	if type(nContacts) ~= "number" or type(segTime) ~= "number" then return end
	if nContacts ~= nContacts or segTime ~= segTime then return end   -- NaN
	if nContacts < 1 or segTime <= 0 then return end

	skipToken += 1
	local token = skipToken
	local scale = label:FindFirstChildOfClass("UIScale")

	label.Text = "0"
	label.Visible = true

	-- Hop k ends at starts[k + 1] (SkipArc, 2026-09-21: the hops accelerate, so the
	-- ticks are no longer k * segTime). Falls back to the uniform cadence without it.
	local starts = (SkipArc and type(totalTime) == "number" and totalTime > 0)
		and SkipArc.HopStarts(nContacts, totalTime, distance) or nil

	task.spawn(function()
		local t0 = os.clock()
		for k = 1, nContacts do
			local due = (starts and starts[k + 1] or (k * segTime)) - SKIP_TICK_LEAD
			local waitFor = due - (os.clock() - t0)
			if waitFor > 0 then task.wait(waitFor) end
			if token ~= skipToken then return end     -- superseded by a new throw / charge
			label.Text = tostring(k)
			if scale then
				-- retarget rather than queue: at 8 contacts on a short flight the
				-- pops overlap, and a queued tween would drift behind the splashes
				scale.Scale = SKIP_POP_SCALE
				TweenService:Create(scale,
					TweenInfo.new(SKIP_POP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Scale = 1 }):Play()
			end
		end
		task.delay(SKIP_CLEAR_SAFE, function()
			if token == skipToken and label then label.Visible = false end
		end)
	end)
end

stoneThrownRemote.OnClientEvent:Connect(function(_, _, totalTime, distance, nContacts, segTime)
	runSkipCounter(nContacts, segTime, totalTime, distance)
end)

-- === Client-smoothed stone =================================================
-- The server flies ThrownRock with anchored PivotTo steps, which reach this
-- client at replication rate (~20Hz) with NO interpolation -- so the rock
-- visibly stuttered against the RenderStepped tracking camera (user capture
-- 2026-08-10, "when i go to throw a rock its very chopped"). The arc is
-- fully deterministic and the payload already carries everything needed to
-- rebuild it (the same latency-cancels argument the skip counter documents),
-- so the thrower hides the server stone LOCALLY and flies a clone of it at
-- render rate instead. Other clients keep the server stone; every gameplay
-- event -- splashes, catch roll, the settle, onLand -- stays server-side.
--
-- Arc reconstruction mirrors ThrowHandler.spawnSkippingStone exactly:
--   startFlat = landing - (0,0,distance); points[i] = startFlat + (0,0,d*i/n)
--   apex k=1: clamp(hopLen*0.4, 3, 11); k>1: max(2.5, clamp(hopLen*0.42, 3, 8)*0.82^(k-2))
-- Change one side and the ghost parts company with the splashes.
stoneThrownRemote.OnClientEvent:Connect(function(origin, landing, totalTime, distance, nContacts, segTime, isCinematic, startFlatFromServer)
	if typeof(origin) ~= "Vector3" or typeof(landing) ~= "Vector3" then return end
	if type(totalTime) ~= "number" or type(distance) ~= "number"
		or type(nContacts) ~= "number" or type(segTime) ~= "number" then return end
	if nContacts < 1 or segTime <= 0 or totalTime <= 0 then return end

	task.spawn(function()
		-- find MY server stone (ThrowHandler tags it); it is parented right
		-- before the payload fires, so it is normally already here
		local stone
		local deadline = os.clock() + 1
		repeat
			for _, c in ipairs(Workspace:GetChildren()) do
				if c.Name == "ThrownRock" and c:GetAttribute("ThrowerUserId") == player.UserId
					and not c:GetAttribute("ClientSmoothed") then
					stone = c
					break
				end
			end
			if not stone then task.wait(0.05) end
		until stone or os.clock() > deadline
		if not stone then return end -- old behaviour: the server stone stays visible
		stone:SetAttribute("ClientSmoothed", true) -- client-local; never replicates

		-- hide the stepping original for me only. Its Trail / motes / glow keep
		-- drawing through a LocalTransparencyModifier (they are not BaseParts), and the
		-- server-stepped Trail at replication rate was a second, jagged wake laid over
		-- the ghost's own -- half of the "laser beam" read. Disabled locally; the
		-- properties never replicate back.
		local function hidePart(d)
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 1
			elseif d:IsA("Trail") or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Light") then
				d.Enabled = false
			end
		end
		for _, d in ipairs(stone:GetDescendants()) do hidePart(d) end
		local hideConn = stone.DescendantAdded:Connect(hidePart)

		local ghost = stone:Clone()
		ghost.Name = "ThrownRockGhost"
		for _, d in ipairs(ghost:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 0
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			elseif d:IsA("Trail") or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Light") then
				-- the clone was taken AFTER hidePart switched these off on the original,
				-- and Enabled does clone: the ghost is the one that gets to glow
				d.Enabled = true
			end
		end
		ghost.Parent = Workspace

		-- The lane: the server's own startFlat when it ships one (2026-09-21 -- the Lush
		-- Gardens bridge skips along +/-X, and the old +Z-only reconstruction flew the
		-- ghost down a diagonal there), else the +Z reconstruction both hub docks use.
		local startFlat, lane
		if typeof(startFlatFromServer) == "Vector3" then
			startFlat = startFlatFromServer
			local flat = Vector3.new(landing.X - startFlat.X, 0, landing.Z - startFlat.Z)
			lane = flat.Magnitude > 1e-3 and flat.Unit or Vector3.new(0, 0, 1)
		else
			startFlat = landing - Vector3.new(0, 0, distance)
			lane = Vector3.new(0, 0, 1)
		end
		local points = { origin }
		for i = 1, nContacts do
			points[i + 1] = startFlat + lane * (distance * (i / nContacts))
		end
		local hopLen = distance / nContacts
		-- the accelerating hop schedule (SkipArc, 2026-09-21); uniform without it
		local starts = SkipArc and SkipArc.HopStarts(nContacts, totalTime, distance) or nil

		local spin = 0
		local flightT0 = os.clock()
		local conn
		local done = false
		local function cleanup()
			if done then return end
			done = true
			if conn then conn:Disconnect() conn = nil end
			if hideConn then hideConn:Disconnect() hideConn = nil end
			if not ghost.Parent then return end
			if isCinematic then
				-- the server destroys its stone at the bonk; a settling ghost
				-- would float through the Massive emergence
				ghost:Destroy()
			else
				-- settle exactly where the server settles, and leave the ghost
				-- for the same beat Debris gives the original
				ghost:PivotTo(CFrame.new(landing.X, landing.Y, landing.Z) * CFrame.Angles(math.rad(6), 0, 0))
				task.delay(1.25, function()
					if ghost.Parent then ghost:Destroy() end
				end)
			end
		end

		conn = RunService.RenderStepped:Connect(function(dt)
			local t = os.clock() - flightT0
			if t >= totalTime then
				cleanup()
				return
			end
			local pos
			if starts then
				pos = SkipArc.Sample(points, starts, hopLen, t)
			else
				local k = math.clamp(math.floor(t / segTime) + 1, 1, nContacts)
				local alpha = math.clamp(t / segTime - (k - 1), 0, 1)
				local a, b = points[k], points[k + 1]
				local apex
				if k == 1 then
					apex = math.clamp(hopLen * 0.4, 3, 11)
				else
					apex = math.max(2.5, math.clamp(hopLen * 0.42, 3, 8) * (0.82 ^ (k - 2)))
				end
				local flat = a:Lerp(b, alpha)
				pos = Vector3.new(flat.X, flat.Y + math.sin(alpha * math.pi) * apex, flat.Z)
			end
			-- the server steps 1 rad per ~60Hz heartbeat; 60 rad/s matches it
			spin += 60 * dt
			ghost:PivotTo(CFrame.new(pos)
				* CFrame.Angles(0, spin, 0)
				* CFrame.Angles(math.rad(12), 0, 0))
		end)
		-- backstop: never outlive the flight, whatever else happens
		task.delay(totalTime + 2, cleanup)
	end)
end)

-- The thrower's camera for a far throw. ThrowCam owns the whole round trip (takeover,
-- chase, glide, dwell, eased return, cut handoff, kill switches); this side only
-- holds the throw bar at "SKIPPING..." until the camera is genuinely home, and never
-- for longer than the module's own backstop. A nil handle means the camera never left
-- (short throw, Quick Throw setting, module unavailable) and the bar follows
-- ThrowResult / StoneThrown as it always did.
stoneThrownRemote.OnClientEvent:Connect(function(startPos, landingPos, flightTime, distance, nContacts, _segTime, isCinematic, startFlat)
	if not ThrowCam then return end
	if typeof(startPos) ~= "Vector3" or typeof(landingPos) ~= "Vector3" then return end
	if type(flightTime) ~= "number" or flightTime ~= flightTime or flightTime <= 0 then return end
	local myToken = throwToken
	-- set BEFORE start(): onHome may run on the very frame the rig resolves, and a flag
	-- raised after it fired would hold the bar until the last-resort timer
	cameraTracking = true    -- holds the throw bar until the flyback ends
	local handle = ThrowCam.start({
		origin = startPos,
		landing = landingPos,
		totalTime = flightTime,
		distance = distance or 0,
		nContacts = nContacts or 2,
		cinematic = isCinematic == true,
		startFlat = (typeof(startFlat) == "Vector3") and startFlat or nil,
		onHome = function()
			-- camera is back on the player: this is the real end of the throw
			cameraTracking = false
			unlockThrow(myToken)
		end,
	})
	if not handle then
		cameraTracking = false   -- the camera never left
	end
end)

-- === Releasing the throw lock ===
-- Connected down here, after unlockThrow and the remotes both exist. Separate
-- listeners rather than edits to the handlers above, so the catch popup and the
-- tracking camera keep their own concerns.

-- Normal case: the stone has settled and the catch is being revealed.
remotes.ThrowResult.OnClientEvent:Connect(function()
	unlockThrow()
end)

-- Thrown, but no catch is coming (the server bailed out of the reveal). StoneThrown
-- carries the real flight time, so the bar opens exactly when the stone lands rather
-- than waiting for the pessimistic MAX_FLIGHT_SECONDS fallback.
stoneThrownRemote.OnClientEvent:Connect(function(_, _, flightTime)
	local myToken = throwToken
	task.delay((flightTime or 1.5) + 0.3, function()
		unlockThrow(myToken)
	end)
end)

-- === Sticker pass: throw panel + sprint button ===
-- Brings the two remaining always-on-screen controls into the same language as
-- the rail: rounder shapes and a WHITE keyline instead of the old near-black
-- one. Only the outline and corner radius change -- the gradients here were
-- already vivid, and the state code drives them through UITheme.setColors,
-- which touches the UIGradient only. That is why this pass survives a state
-- change and does not need re-running on every throw.
do
	local WHITE = Color3.fromRGB(255, 255, 255)

	-- Retire the authored dark rims, then add one white keyline we own by name.
	--
	-- The UICorner sweep matters as much as the stroke one. UIStyle.corner works
	-- on a child it names "UIStyleCorner", but these controls were authored in
	-- StarterGui with a UICorner of their own already sitting there. Roblox
	-- honours ONE UICorner per object and does not say which -- so the sprint
	-- button kept rendering at the authored 18 while this code believed it had
	-- made a pill, and the radius was really down to child order. One corner per
	-- object, ours, decided here.
	local function keyline(o, thickness, radius)
		if not o then return end
		for _, s in ipairs(o:GetChildren()) do   -- snapshot: safe to Destroy inside
			if s:IsA("UIStroke") and s.ApplyStrokeMode == Enum.ApplyStrokeMode.Border
			   and s.Name ~= "UIStyleStrokeBorder" then
				s.Transparency = 1
			elseif s:IsA("UICorner") and s.Name ~= "UIStyleCorner" then
				s:Destroy()
			end
		end
		if radius then UIStyle.corner(o, radius) end
		UIStyle.stroke(o, WHITE, thickness)
	end

	keyline(throwFrame, 3.5, 20)

	local barBg = throwFrame and throwFrame:FindFirstChild("BarBackground")
	if barBg then
		UIStyle.pill(barBg)
		keyline(barBg, 2.5)
		local fill = barBg:FindFirstChild("BarFill")
		if fill then UIStyle.pill(fill) end
	end

	keyline(throwButton, 3, 14)
	-- No radius passed: UIStyle.pill writes the same UIStyleCorner keyline would,
	-- so a 16 here was only ever overwritten a line later. The pill is the
	-- intended shape -- it matches the currency pills and the luck chip it
	-- stacks with.
	keyline(sprintButton, 3)
	if sprintButton then UIStyle.pill(sprintButton) end
end

-- === Controller glyphs ===
-- The two controls that are on screen at all times, labelled with the button
-- that works them. Bindings live where the behaviour does -- R2/X on the throw
-- (see setThrowBinding) and L3 on sprint (see the InputBegan handler) -- so the
-- KeyCodes are repeated here only as the thing to DRAW, and the pair must be
-- kept in step by hand. Both hide themselves on mouse and touch.
GamepadHint.attach(throwButton, Enum.KeyCode.ButtonR2)
GamepadHint.attach(sprintButton, Enum.KeyCode.ButtonL3)
