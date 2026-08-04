-- CatchFX: a world-space burst on the catcher, escalating with rarity.
--
-- Separate from CatchReveal on purpose. CatchReveal owns the screen-space reveal card;
-- this is the thing that happens AROUND YOU, so the two can be tuned (or skipped by the
-- phase-2 upgrade) independently.
--
-- Intensity is one number per tier and every element derives from it, so the ladder
-- cannot end up non-monotonic the way separate hand-tuned entries do. Elements switch on
-- at thresholds rather than scaling from zero -- a Common should be a puff, not a faint
-- version of a God.
--
-- Only sparkles_main and smoke_main resolve as particle textures in this place; anything
-- else renders as nothing, which is why those two do all the work here.
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local M = {}

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

-- tier -> intensity. Gaps are deliberate: Legendary is a real step up, Secret another.
local TIER = {
	Common = 1, Uncommon = 2, Rare = 3, Epic = 4,
	Legendary = 5, Mythic = 6, Secret = 7, God = 8,
}

local function attach(part, life)
	Debris:AddItem(part, life)
	return part
end

-- a flat expanding ring on the ground
local function ring(root, colour, size, life, thickness)
	local p = Instance.new("Part")
	p.Name = "CatchFXRing"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(thickness or 0.4, 2, 2)
	p.CFrame = CFrame.new(root.Position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Material, p.Color = Enum.Material.Neon, colour
	p.Transparency = 0.15
	p.Parent = workspace
	attach(p, life + 0.1)
	TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = Vector3.new(thickness or 0.4, size, size),
		Transparency = 1,
	}):Play()
	return p
end

-- a column of light climbing out of the ground
local function beam(root, colour, height, life)
	local p = Instance.new("Part")
	p.Name = "CatchFXBeam"
	p.Size = Vector3.new(2.2, 1, 2.2)
	p.CFrame = CFrame.new(root.Position - Vector3.new(0, 2.4, 0))
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Material, p.Color = Enum.Material.Neon, colour
	p.Transparency = 0.25
	p.Parent = workspace
	attach(p, life + 0.1)
	TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.6, height, 0.6),
		CFrame = CFrame.new(root.Position + Vector3.new(0, height / 2 - 2.4, 0)),
		Transparency = 1,
	}):Play()
end

local function sparks(root, colour, count, speed, life, texture, sizeMul)
	local a = Instance.new("Attachment")
	a.Parent = root
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture or SPARK
	e.Color = ColorSequence.new(colour)
	e.LightEmission = 0.8
	e.Lifetime = NumberRange.new(life * 0.5, life)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -18, 0)
	e.Drag = 2
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-180, 180)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.1 * (sizeMul or 1)),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Rate = 0
	e.Parent = a
	e:Emit(count)
	Debris:AddItem(a, life + 0.6)
end

local function flash(root, colour, brightness, range, life)
	local p = Instance.new("Part")
	p.Name = "CatchFXFlash"
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = CFrame.new(root.Position)
	p.Transparency = 1
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Parent = workspace
	local l = Instance.new("PointLight")
	l.Color, l.Brightness, l.Range = colour, brightness, range
	l.Parent = p
	attach(p, life + 0.1)
	TweenService:Create(l, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Brightness = 0 }):Play()
end

-- screen-edge bloom for the top of the ladder only
local function vignette(colour, strength, life)
	local player = Players.LocalPlayer
	local pg = player and player:FindFirstChildOfClass("PlayerGui")
	if not pg then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "CatchFXVignette"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 25
	gui.Parent = pg
	local img = Instance.new("Frame")
	img.Size = UDim2.fromScale(1, 1)
	img.BackgroundColor3 = colour
	img.BackgroundTransparency = 1 - strength
	img.BorderSizePixel = 0
	img.Parent = gui
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(1, 0.25),
	})
	grad.Parent = img
	TweenService:Create(img, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }):Play()
	Debris:AddItem(gui, life + 0.2)
end

local function kick(strength)
	local cam = workspace.CurrentCamera
	if not cam then return end
	local t0 = os.clock()
	task.spawn(function()
		while os.clock() - t0 < 0.28 do
			local k = (1 - (os.clock() - t0) / 0.28) * strength
			cam.CFrame = cam.CFrame * CFrame.Angles(
				math.rad((math.random() - 0.5) * k),
				math.rad((math.random() - 0.5) * k), 0)
			task.wait()
		end
	end)
end

-- info = { Rarity = string, Color = Color3?, Mutation = string? }
function M.play(info)
	local player = Players.LocalPlayer
	local char = player and player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local tier = TIER[info and info.Rarity] or 1
	local colour = (info and info.Color) or Color3.fromRGB(255, 236, 170)

	-- every tier gets SOMETHING, but a Common is a puff and nothing more
	sparks(root, colour, 6 + tier * 7, 6 + tier * 3.5, 0.5 + tier * 0.12, nil, 0.6 + tier * 0.09)

	if tier >= 2 then ring(root, colour, 6 + tier * 2.2, 0.45 + tier * 0.05, 0.35) end
	if tier >= 3 then flash(root, colour, 1 + tier * 0.7, 16 + tier * 4, 0.35 + tier * 0.06) end
	if tier >= 4 then
		task.delay(0.09, function()
			if root.Parent then ring(root, colour, 10 + tier * 2.6, 0.5 + tier * 0.05, 0.25) end
		end)
	end
	if tier >= 5 then
		beam(root, colour, 22 + tier * 5, 0.5 + tier * 0.07)
		kick(0.5 + (tier - 5) * 0.45)
	end
	if tier >= 6 then
		-- slow smoke bloom under the sparks: gives the top tiers physical weight
		sparks(root, colour, 10 + tier * 3, 4, 1.1, SMOKE, 3 + tier * 0.5)
	end
	if tier >= 7 then
		vignette(colour, 0.16 + (tier - 7) * 0.1, 0.55)
		-- a second, larger ring a beat later reads as a shockwave rather than a repeat
		task.delay(0.2, function()
			if root.Parent then ring(root, colour, 26 + tier * 4, 0.75, 0.5) end
		end)
	end
	if tier >= 8 then
		task.delay(0.34, function()
			if root.Parent then
				sparks(root, colour, 90, 34, 1.5, nil, 1.5)
				flash(root, colour, 7, 60, 0.7)
			end
		end)
	end
end

M.Tiers = TIER
return M
