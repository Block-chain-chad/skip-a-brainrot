--!strict
-- EggHatch.Stage: the room a hatch plays in, and the ONLY thing in the hatch that
-- touches state it has to give back. It owns:
--   * the hatch gui (edge vignette + input catcher + fx/plate layers). The WORLD is dimmed
--     with a ColorCorrectionEffect, never with a full-screen frame: the eggs are world
--     objects, so a frame over the screen would darken the very thing the hatch is
--     about. Post-processing dims the blurred world and the lit stage stays the
--     brightest thing in the frame,
--   * a Workspace folder that FOLLOWS THE CAMERA every frame (the eggs are staged in
--     front of whatever the player is looking at -- the camera is never taken over, so
--     there is no camera to restore and nothing can strand it),
--   * DepthOfField (world blurs, the stage stays sharp), a fill light, the local
--     character's fade, ProximityPrompts, the HUD switch-off under the veil, the
--     RevealActive input lock and the FOV punch.
-- Every one of those is tracked in a LIFO trove that finish() drains on every exit path.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)

local player = Players.LocalPlayer
local REVEAL_ATTR = "RevealActive"
local GUI_NAME = "EggHatchUI"
local FOLDER_NAME = "EggHatchStage"

local Stage = {}
Stage.__index = Stage

export type Stage = typeof(setmetatable({} :: {
	trove: { () -> () }, done: boolean, finishing: boolean, t: number,
	veilTarget: number, gui: ScreenGui, cc: ColorCorrectionEffect, fxLayer: Frame, plateLayer: Frame,
	catcher: TextButton, folder: Folder, camera: Camera, frame: CFrame, base: CFrame,
	D: number, tanV: number, tanH: number, vp: Vector2,
	kickT: number, kickAmp: number, fovBase: number, fovPunch: number, fovT: number,
	hidden: { ScreenGui }, onTap: ((() -> ())?), light: PointLight?, lightPart: Part?,
	dof: DepthOfFieldEffect?, charParts: { Instance },
}, Stage))

local function track(self, fn: () -> ())
	table.insert(self.trove, fn)
end

local function drain(self)
	for i = #self.trove, 1, -1 do
		local ok, err = pcall(self.trove[i])
		if not ok then warn("[EggHatch.Stage] restore step failed: " .. tostring(err)) end
	end
	table.clear(self.trove)
end

-- roll-free camera frame at the camera's position: the stage sits in front of the
-- player's view and stays upright even while they look up or down
local function cameraFrame(cam: Camera): CFrame
	local cf = cam.CFrame
	local look = cf.LookVector
	local up = Vector3.yAxis
	if math.abs(look.Y) > 0.97 then up = cf.UpVector end
	return CFrame.lookAt(cf.Position, cf.Position + look, up)
end

function Stage.new(opts: { veil: number?, light: number? }): Stage
	local self = setmetatable({}, Stage) :: any
	self.trove = {}
	self.done = false
	self.finishing = false
	self.t = 0
	self.veilTarget = opts.veil or 0.55
	self.lightMult = opts.light or 1
	self.kickT = 10
	self.kickAmp = 0
	self.fovPunch = 0
	self.fovT = 10
	self.hidden = {}
	self.charParts = {}
	return self
end

-- Builds everything and starts the ramps. Never yields.
function Stage:begin()
	local playerGui = player:WaitForChild("PlayerGui")
	local cam = workspace.CurrentCamera
	self.camera = cam
	local S = Config.STAGE

	-- ---------------------------------------------------------------- gui
	local gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local okLayout = pcall(function()
		require(ReplicatedStorage.Modules.HudLayout).PrepareGui(gui, "Reward", true)
	end)
	if not okLayout then gui.DisplayOrder = 60 end
	gui.Parent = playerGui
	self.gui = gui
	track(self, function() gui:Destroy() end)

	-- the "veil": a colour correction that darkens and desaturates the (blurred) world.
	-- It is a Lighting effect, so the plates and the vignette above are untouched.
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "EggHatchGrade"
	cc.Brightness = 0
	cc.Saturation = 0
	cc.Contrast = 0
	cc.Parent = Lighting
	self.cc = cc
	track(self, function() cc:Destroy() end)

	-- vignette: two edge gradients (top/bottom) so the middle stays the brightest
	-- band of the screen and the eggs sit in it
	self.vignette = {}
	for i, rot in ipairs({ 90, 270 }) do
		local bar = Instance.new("Frame")
		bar.Name = "Vignette" .. i
		bar.Size = UDim2.fromScale(1, 0.34)
		bar.Position = (i == 1) and UDim2.fromScale(0, 0) or UDim2.fromScale(0, 0.66)
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BackgroundTransparency = 1
		bar.BorderSizePixel = 0
		bar.ZIndex = 2
		local g = Instance.new("UIGradient")
		g.Rotation = rot
		-- keypoint 0 is the SCREEN EDGE for both bars (rotation 90 runs top->bottom on the
		-- top bar, 270 runs bottom->top on the bottom one): dark at the edge, clear inward
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = bar
		bar.Parent = gui
		self.vignette[i] = bar
	end

	local catcher = Instance.new("TextButton")
	catcher.Name = "Catcher"
	catcher.Size = UDim2.fromScale(1, 1)
	catcher.BackgroundTransparency = 1
	catcher.Text = ""
	catcher.AutoButtonColor = false
	catcher.ZIndex = 3
	catcher.Parent = gui
	self.catcher = catcher
	catcher.Activated:Connect(function()
		if self.onTap and not self.done then self.onTap() end
	end)
	local inputConn = UserInputService.InputBegan:Connect(function(input, processed)
		if self.done or not self.onTap then return end
		local k = input.KeyCode
		if k == Enum.KeyCode.ButtonA or k == Enum.KeyCode.ButtonB or k == Enum.KeyCode.Space or k == Enum.KeyCode.Return then
			self.onTap()
		end
	end)
	track(self, function() inputConn:Disconnect() end)

	local fx = Instance.new("Frame")
	fx.Name = "Fx"
	fx.Size = UDim2.fromScale(1, 1)
	fx.BackgroundTransparency = 1
	fx.ZIndex = 5
	fx.Parent = gui
	self.fxLayer = fx

	local plates = Instance.new("Frame")
	plates.Name = "Plates"
	plates.Size = UDim2.fromScale(1, 1)
	plates.BackgroundTransparency = 1
	plates.ZIndex = 10
	plates.Parent = gui
	self.plateLayer = plates

	-- ---------------------------------------------------------------- stage folder
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = workspace
	self.folder = folder
	track(self, function() folder:Destroy() end)

	-- ---------------------------------------------------------------- geometry
	self.base = cameraFrame(cam)
	self.frame = self.base
	self.vp = cam.ViewportSize
	self.tanV = math.tan(math.rad(cam.FieldOfView / 2))
	self.tanH = self.tanV * (self.vp.X / math.max(1, self.vp.Y))
	local D = S.distance
	do
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local filter = { folder }
		if player.Character then table.insert(filter, player.Character) end
		params.FilterDescendantsInstances = filter
		params.IgnoreWater = true
		local hit = workspace:Raycast(self.base.Position, self.base.LookVector * (D + S.clearance), params)
		if hit then
			D = math.max(S.minDistance, hit.Distance - S.clearance)
		end
	end
	self.D = D

	-- ---------------------------------------------------------------- fill light
	local lp = Instance.new("Part")
	lp.Name = "StageLight"
	lp.Anchored = true
	lp.CanCollide = false
	lp.CanQuery = false
	lp.CanTouch = false
	lp.Transparency = 1
	lp.Size = Vector3.one
	lp.CFrame = self.frame * CFrame.new(0, 1.5, -D * 0.45)
	lp.Parent = folder
	local light = Instance.new("PointLight")
	light.Brightness = 0
	light.Range = S.lightRange
	light.Color = Color3.fromRGB(255, 250, 240)
	light.Shadows = false
	light.Parent = lp
	self.lightPart, self.light = lp, light
	TweenService:Create(light, TweenInfo.new(S.veilIn), { Brightness = S.lightBrightness * self.lightMult }):Play()

	-- ---------------------------------------------------------------- depth of field
	local dof = Instance.new("DepthOfFieldEffect")
	dof.Name = "EggHatchDoF"
	dof.FocusDistance = D
	dof.InFocusRadius = D * S.dofRadiusMult
	dof.NearIntensity = 0
	dof.FarIntensity = 0
	dof.Parent = Lighting
	self.dof = dof
	track(self, function() dof:Destroy() end)
	TweenService:Create(dof, TweenInfo.new(S.veilIn), { FarIntensity = S.dofFar }):Play()

	-- ---------------------------------------------------------------- veil ramp
	self:setVeil(self.veilTarget, S.veilIn)

	-- ---------------------------------------------------------------- locks
	player:SetAttribute(REVEAL_ATTR, true)
	track(self, function() player:SetAttribute(REVEAL_ATTR, nil) end)

	local promptsWere = ProximityPromptService.Enabled
	ProximityPromptService.Enabled = false
	track(self, function() ProximityPromptService.Enabled = promptsWere end)

	-- Highlights (walk-up NPC outlines, favourite glows) draw over the grade and would
	-- sit beside the eggs at full brightness; the ones near the player stand down
	do
		local dimmed = {}
		local here = self.base.Position
		for _, h in ipairs(workspace:GetDescendants()) do
			if h:IsA("Highlight") and h.Enabled then
				local ad = h.Adornee or h.Parent
				local pos = ad and ((ad:IsA("BasePart") and ad.Position) or (ad:IsA("Model") and ad:GetPivot().Position)) or nil
				if pos and (pos - here).Magnitude < 60 then
					h.Enabled = false
					table.insert(dimmed, h)
				end
			end
		end
		track(self, function()
			for _, h in ipairs(dimmed) do
				if h.Parent then h.Enabled = true end
			end
		end)
	end

	self.fovBase = cam.FieldOfView
	track(self, function()
		if cam.Parent then cam.FieldOfView = self.fovBase end
	end)

	-- ---------------------------------------------------------------- character fade
	if S.characterFade and player.Character then
		for _, d in ipairs(player.Character:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Decal") then
				table.insert(self.charParts, d)
				TweenService:Create(d, TweenInfo.new(S.veilIn), { LocalTransparencyModifier = 1 }):Play()
			end
		end
		track(self, function()
			for _, d in ipairs(self.charParts) do
				if d.Parent then d.LocalTransparencyModifier = 0 end
			end
		end)
	end

	-- ---------------------------------------------------------------- HUD, under the veil
	task.delay(S.hudHideAt, function()
		if self.done or self.finishing then return end
		self:hideHud()
	end)
	track(self, function() self:restoreHud() end)
end

function Stage:hideHud()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end
	for _, g in ipairs(playerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled and not Config.HUD_KEEP[g.Name] then
			g.Enabled = false
			table.insert(self.hidden, g)
		end
	end
end

function Stage:restoreHud()
	for _, g in ipairs(self.hidden) do
		pcall(function()
			if g.Parent then g.Enabled = true end
		end)
	end
	table.clear(self.hidden)
end

-- alpha is the preset's veil depth (0.5 common .. 0.86 god). It maps onto how far the
-- world is pulled down: brightness, saturation and a touch of contrast, plus the edge
-- vignette. 0 restores the world exactly.
function Stage:setVeil(alpha: number, seconds: number)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local k = math.clamp(alpha, 0, 1)
	TweenService:Create(self.cc, info, {
		Brightness = -0.30 * k,
		Saturation = -0.24 * k,
		Contrast = 0.12 * k,
	}):Play()
	for _, bar in ipairs(self.vignette) do
		TweenService:Create(bar, info, { BackgroundTransparency = 1 - k * 0.95 }):Play()
	end
end

-- a camera-space impulse: the whole stage jolts toward the camera and settles, and the
-- FOV punches by `degrees` (capped). Tiny by design -- the world behind is blurred, so
-- even a small jolt reads as a hit without moving the player's view.
function Stage:kick(strength: number, degrees: number?)
	self.kickT = 0
	self.kickAmp = math.max(self.kickAmp * 0.5, strength)
	if degrees and degrees > 0 then
		self.fovT = 0
		self.fovPunch = math.min(Config.STAGE.fovPunchMax, degrees)
	end
end

-- Called once per frame by the controller, AFTER the camera has updated (the
-- controller binds after RenderPriority.Camera).
function Stage:update(dt: number)
	if self.done then return end
	self.t += dt
	local cam = workspace.CurrentCamera
	if cam ~= self.camera then
		self.camera = cam
	end
	self.base = cameraFrame(cam)
	self.kickT += dt
	self.fovT += dt
	local off = Vector3.zero
	local rot = 0
	if self.kickT < 0.6 then
		local k = self.kickAmp * math.exp(-9 * self.kickT)
		off = Vector3.new(0, -0.05 * k * math.sin(self.kickT * 42), -0.10 * k * math.sin(self.kickT * 30))
		rot = math.rad(0.7) * k * math.sin(self.kickT * 38)
	end
	self.frame = self.base * CFrame.new(off) * CFrame.Angles(rot, 0, 0)
	if self.fovT < 0.7 then
		local p = self.fovPunch * math.exp(-6.5 * self.fovT)
		cam.FieldOfView = self.fovBase + p
	elseif self.fovT < 0.8 then
		cam.FieldOfView = self.fovBase
	end
	if self.lightPart then
		self.lightPart.CFrame = self.frame * CFrame.new(0, 1.5, -self.D * 0.45)
	end
end

-- screen fractions (x, y in [-0.5, 0.5], +y up) at depth D + dz -> stage-local point
function Stage:localPoint(sx: number, sy: number, dz: number?): Vector3
	local d = self.D + (dz or 0)
	return Vector3.new(sx * 2 * d * self.tanH, sy * 2 * d * self.tanV, -d)
end

-- world height (studs) that fills `frac` of the viewport height at depth D + dz
function Stage:heightFor(frac: number, dz: number?): number
	return frac * 2 * (self.D + (dz or 0)) * self.tanV
end

function Stage:toWorld(localPos: Vector3): CFrame
	return self.frame * CFrame.new(localPos)
end

-- stage-local point -> gui pixel position (for plates under a reward)
function Stage:toScreen(localPos: Vector3): Vector2
	local d = -localPos.Z
	if d < 0.01 then d = 0.01 end
	local sx = localPos.X / (2 * d * self.tanH)
	local sy = localPos.Y / (2 * d * self.tanV)
	local size = self.gui.AbsoluteSize
	return Vector2.new((0.5 + sx) * size.X, (0.5 - sy) * size.Y)
end

-- Ends the run: HUD back under the veil, then the veil, DoF and light ramp out, then
-- everything tracked is destroyed. `after` runs once the ramp has landed. Idempotent.
function Stage:finish(after: (() -> ())?)
	if self.done or self.finishing then return end
	self.finishing = true
	local S = Config.STAGE
	self:restoreHud()
	self:setVeil(0, S.veilOut)
	if self.dof then
		TweenService:Create(self.dof, TweenInfo.new(S.veilOut), { FarIntensity = 0 }):Play()
	end
	if self.light then
		TweenService:Create(self.light, TweenInfo.new(S.veilOut), { Brightness = 0 }):Play()
	end
	for _, d in ipairs(self.charParts) do
		if d.Parent then
			TweenService:Create(d, TweenInfo.new(S.veilOut), { LocalTransparencyModifier = 0 }):Play()
		end
	end
	task.delay(S.veilOut + 0.03, function()
		self.done = true
		drain(self)
		if after then
			local ok, err = pcall(after)
			if not ok then warn("[EggHatch.Stage] after-finish callback failed: " .. tostring(err)) end
		end
	end)
end

-- Hard stop for kill switches: no ramp, everything restored this frame.
function Stage:abort()
	if self.done then return end
	self.done = true
	self.finishing = true
	drain(self)
end

return Stage
