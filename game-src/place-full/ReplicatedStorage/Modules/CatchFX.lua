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
--
-- NO PRIMITIVE GEOMETRY (2026-09-21 reward-pacing pass). The rings used to be filled
-- Neon cylinders (a Neon cylinder is a DISC -- a glowing coin at the player's feet, up
-- to 24 studs across on the top tiers) and the "column of light" a Neon block. Both are
-- exactly the flat-disc / tube look the reveal pass bans: the reward is the brainrot,
-- the effects only frame it. Rings are now particle bursts emitted from the rim of a
-- disc-shaped emitter (a true ring, no fill) and the column is an upward sparkle
-- stream. The light flash and the sparks were always particles/lights and stay.
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

local function host(root, offsetY, size)
	local p = Instance.new("Part")
	p.Name = "CatchFXHost"
	p.Size = size or Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = CFrame.new(root.Position + Vector3.new(0, offsetY or 0, 0))
	p.Transparency = 1
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.CastShadow = false
	p.Parent = workspace
	return p
end

-- A RING on the ground: one burst from the rim of a disc emitter, drifting outward and
-- fading. Reads as an expanding ring with no geometry at all.
local function ring(root, colour, size, life, count)
	local radius = math.max(size * 0.5, 1)
	local p = host(root, -2.6, Vector3.new(radius * 2, 0.2, radius * 2))
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARK
	e.Shape = Enum.ParticleEmitterShape.Disc
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	e.EmissionDirection = Enum.NormalId.Top
	e.Color = ColorSequence.new(colour)
	e.LightEmission = 0.9
	e.Lifetime = NumberRange.new(life * 0.7, life)
	e.Speed = NumberRange.new(radius * 0.8, radius * 1.4)
	e.SpreadAngle = Vector2.new(6, 6)
	e.Acceleration = Vector3.new(0, 2, 0)
	e.Drag = 3
	e.Rotation = NumberRange.new(0, 360)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(0.6, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Rate = 0
	e.Parent = p
	e:Emit(count or 36)
	attach(p, life + 0.4)
	return p
end

-- A column of light climbing from the ground: an upward sparkle stream, no block.
local function column(root, colour, height, life)
	local p = host(root, -2.4, Vector3.new(1.6, 0.2, 1.6))
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARK
	e.Shape = Enum.ParticleEmitterShape.Disc
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.EmissionDirection = Enum.NormalId.Top
	e.Color = ColorSequence.new(colour)
	e.LightEmission = 1
	e.Lifetime = NumberRange.new(life * 0.6, life)
	e.Speed = NumberRange.new(height / life * 0.7, height / life)
	e.SpreadAngle = Vector2.new(4, 4)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Rate = 0
	e.Parent = p
	e:Emit(40)
	attach(p, life + 0.4)
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
	local p = host(root, 0)
	p.Name = "CatchFXFlash"
	local l = Instance.new("PointLight")
	l.Color, l.Brightness, l.Range = colour, brightness, range
	l.Shadows = false
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
	-- never fight a camera somebody else is driving (a cut, the stone chase)
	if cam.CameraType == Enum.CameraType.Scriptable then return end
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
	sparks(root, colour, 4 + tier * 6, 6 + tier * 3.2, 0.45 + tier * 0.1, nil, 0.5 + tier * 0.08)

	if tier >= 2 then ring(root, colour, 5 + tier * 1.8, 0.45 + tier * 0.05, 18 + tier * 5) end
	if tier >= 3 then flash(root, colour, 1 + tier * 0.6, 14 + tier * 4, 0.35 + tier * 0.06) end
	if tier >= 4 then
		task.delay(0.09, function()
			if root.Parent then ring(root, colour, 8 + tier * 2.2, 0.5 + tier * 0.05, 26 + tier * 5) end
		end)
	end
	if tier >= 5 then
		column(root, colour, 14 + tier * 3, 0.55 + tier * 0.05)
		kick(0.35 + (tier - 5) * 0.3)
	end
	if tier >= 6 then
		-- slow smoke bloom under the sparks: gives the top tiers physical weight
		sparks(root, colour, 8 + tier * 3, 4, 1.0, SMOKE, 2.5 + tier * 0.4)
	end
	if tier >= 7 then
		vignette(colour, 0.16 + (tier - 7) * 0.1, 0.55)
		-- a second, larger ring a beat later reads as a shockwave rather than a repeat
		task.delay(0.2, function()
			if root.Parent then ring(root, colour, 20 + tier * 3, 0.75, 48) end
		end)
	end
	if tier >= 8 then
		task.delay(0.34, function()
			if root.Parent then
				sparks(root, colour, 80, 30, 1.4, nil, 1.4)
				flash(root, colour, 6, 56, 0.7)
			end
		end)
	end
end

M.Tiers = TIER
return M
