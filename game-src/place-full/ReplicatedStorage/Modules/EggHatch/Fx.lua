--!strict
-- EggHatch.Fx: the effects vocabulary of a hatch, world and screen. Everything is
-- built into the stage (its folder / its fx layer), so the stage's teardown is the
-- cleanup; nothing here outlives a run. Deliberately small (owner, 2026-09-21: effects
-- support the reward, they never overwhelm it): one burst part per egg with two
-- emitters, one leak emitter on the egg core, one orbit emitter on a Legendary+ reward,
-- a thin ring and a little confetti on screen. No beams, no discs, no bloom fields.

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Fx = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function invisiblePart(parent: Instance, cf: CFrame, size: number?): Part
	local p = Instance.new("Part")
	p.Name = "fx"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.one * (size or 0.5)
	p.CFrame = cf
	p.Parent = parent
	return p
end

local function seq(c: Color3, c2: Color3?): ColorSequence
	return ColorSequence.new(c, c2 or c)
end

-- ---------------------------------------------------------------- world
-- light leaking through the cracks: a slow sparkle emitter on the egg core part.
-- Returns the emitter so the rig can raise its Rate as the cracks open.
function Fx.leak(host: BasePart, colour: Color3, scale: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "leak"
	e.Texture = SPARKLE
	e.Color = seq(colour, Color3.new(1, 1, 1))
	e.LightEmission = 0.9
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05 * scale), NumberSequenceKeypoint.new(0.4, 0.16 * scale), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(1.2 * scale, 2.6 * scale)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, 1.5 * scale, 0)
	e.Rate = 0
	e.Drag = 2
	e.Parent = host
	return e
end

-- the hatch burst at a world CFrame: sparks outward + a soft glow puff, one-shot
function Fx.burst(folder: Instance, cf: CFrame, colour: Color3, strength: number, scale: number)
	local p = invisiblePart(folder, cf, 0.4)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARKLE
	sparks.Color = seq(colour, Color3.new(1, 1, 1))
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.14 * scale), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1) })
	sparks.Lifetime = NumberRange.new(0.45, 0.85)
	sparks.Speed = NumberRange.new(5 * scale * strength, 11 * scale * strength)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Acceleration = Vector3.new(0, -9 * scale, 0)
	sparks.Drag = 2.5
	sparks.Rate = 0
	sparks.Parent = p
	local puff = Instance.new("ParticleEmitter")
	puff.Texture = SMOKE
	puff.Color = seq(colour:Lerp(Color3.new(1, 1, 1), 0.5))
	puff.LightEmission = 0.8
	puff.LightInfluence = 0
	puff.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4 * scale), NumberSequenceKeypoint.new(1, 1.3 * scale) })
	puff.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	puff.Lifetime = NumberRange.new(0.35, 0.5)
	puff.Speed = NumberRange.new(0.5 * scale, 1.5 * scale)
	puff.SpreadAngle = Vector2.new(180, 180)
	puff.Rate = 0
	puff.Parent = p
	sparks:Emit(math.floor(10 + 10 * strength))
	puff:Emit(math.floor(2 + 2 * strength))
	local light = Instance.new("PointLight")
	light.Color = colour
	light.Brightness = 1.2 * strength
	light.Range = 8 * scale
	light.Shadows = false
	light.Parent = p
	TweenService:Create(light, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	Debris:AddItem(p, 1.6)
end

-- gold/tier sparkles orbiting the reward (Legendary and up), lives with the reward part
function Fx.orbit(host: BasePart, colour: Color3, scale: number, rate: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "orbit"
	e.Texture = SPARKLE
	e.Color = seq(colour, Color3.new(1, 1, 1))
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.18 * scale), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.9, 1.4)
	e.Speed = NumberRange.new(0.6 * scale, 1.4 * scale)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, 1.2 * scale, 0)
	e.Rate = rate
	e.Parent = host
	return e
end

-- ---------------------------------------------------------------- screen
-- a full-screen flash on the fx layer
function Fx.flash(layer: Frame, colour: Color3, alpha: number, seconds: number, timeScale: number?)
	seconds = seconds * (timeScale or 1)
	local f = Instance.new("Frame")
	f.Name = "Flash"
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = colour
	f.BackgroundTransparency = 1 - alpha
	f.BorderSizePixel = 0
	f.ZIndex = 6
	f.Parent = layer
	TweenService:Create(f, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(f, seconds + 0.1)
end

-- an expanding hollow ring at a gui pixel position (Rare+ hatches)
function Fx.ring(layer: Frame, at: Vector2, colour: Color3, size: number, seconds: number, timeScale: number?)
	seconds = seconds * (timeScale or 1)
	local r = Instance.new("Frame")
	r.Name = "Ring"
	r.AnchorPoint = Vector2.new(0.5, 0.5)
	r.Position = UDim2.fromOffset(at.X, at.Y)
	r.Size = UDim2.fromOffset(size, size)
	r.BackgroundTransparency = 1
	r.ZIndex = 6
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = r
	local s = Instance.new("UIStroke"); s.Color = colour; s.Thickness = math.max(2, size * 0.012); s.Transparency = 0.2; s.Parent = r
	local sc = Instance.new("UIScale"); sc.Scale = 0.35; sc.Parent = r
	r.Parent = layer
	TweenService:Create(sc, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.9 }):Play()
	TweenService:Create(s, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
	Debris:AddItem(r, seconds + 0.1)
end

-- confetti: small tinted squares falling from above the reward, UI only, self-cleaning
function Fx.confetti(layer: Frame, at: Vector2, n: number, colours: { Color3 }, spread: number, timeScale: number?)
	local ts = timeScale or 1
	local rng = Random.new()
	for i = 1, n do
		local piece = Instance.new("Frame")
		piece.Name = "Confetti"
		local w = rng:NextInteger(6, 11)
		piece.Size = UDim2.fromOffset(w, math.floor(w * 0.6))
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		local x0 = at.X + rng:NextNumber(-spread * 0.3, spread * 0.3)
		local y0 = at.Y - rng:NextNumber(0, spread * 0.25)
		piece.Position = UDim2.fromOffset(x0, y0)
		piece.BackgroundColor3 = colours[rng:NextInteger(1, #colours)]
		piece.BorderSizePixel = 0
		piece.Rotation = rng:NextNumber(0, 360)
		piece.ZIndex = 7
		piece.Parent = layer
		local life = rng:NextNumber(0.9, 1.5) * ts
		local dx = rng:NextNumber(-spread, spread)
		local dy = rng:NextNumber(spread * 0.5, spread * 1.1)
		local info = TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, rng:NextNumber(0, 0.15) * ts)
		TweenService:Create(piece, info, { Position = UDim2.fromOffset(x0 + dx, y0 + dy), Rotation = piece.Rotation + rng:NextNumber(-260, 260), BackgroundTransparency = 1 }):Play()
		Debris:AddItem(piece, life + 0.3)
	end
end

return Fx
