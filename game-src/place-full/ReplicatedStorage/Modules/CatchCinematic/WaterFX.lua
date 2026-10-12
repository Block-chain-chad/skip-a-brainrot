--!strict
-- CatchCinematic.WaterFX -- water-surface effects for the Massive catch cinematic:
-- bonk ripple, glassy-still water, an accelerating dread ripple train, a suction
-- shadow + dip, a taut water dome, the eruption (column + splash + foam), a
-- waterfall cascade off the revealed model, and a fanned godray backdrop.
--
-- Style: reuses ThrowHandler's house ripple recipe verbatim (thin Neon cylinder,
-- rotated flat via CFrame.Angles(0,0,90), TweenService Quad-EaseOut on Size +
-- Transparency -- see ServerScriptService.Modules.ThrowHandler's ripple()/
-- spawnSplash()). Every ring in this module starts at LEAST half-faded
-- (Transparency >= 0.4), never opaque -- a Neon cylinder is a FILLED disc, so an
-- opaque one reads as a solid coin, not a ring.
--
-- TweenService is the one sanctioned animation domain here (BasePart Color/Size/
-- Transparency/CFrame) -- no RenderStepped/Heartbeat loops in this module, even
-- for the "slow rotation" on godrays (see _orbitForever: chained small-arc
-- CFrame tweens, not a per-frame writer). rippleTrain()/suctionAndShadow() are
-- instead driven EXTERNALLY: the caller (Sequencer, or this task's harness)
-- calls them every frame with an advancing `progress`, and this module sets
-- properties directly as a pure function of that progress -- replaying the same
-- progress sequence always reproduces the same state.
--
-- Every part follows ThrowHandler's decorPart pattern: Anchored, CanCollide/
-- CanQuery/CanTouch off, CastShadow off, Locked.
--
-- Randomness: ONLY through the `rng: Random` passed into WaterFX.new (godrays'
-- per-wedge angle/length jitter is the one scatter this module draws). A
-- ParticleEmitter's own per-particle scatter (SpreadAngle, Speed range, etc.) is
-- the ENGINE's internal RNG, not ours, has no override hook, and is left alone --
-- it is not what "all randomness through rng" governs.
--
-- Particle budget: Fx:particleEstimate() is a non-contractual helper (not in the
-- Task 4 interface list, additive only) returning this instance's running total,
-- so the harness/Sequencer can assert
--   sum(Rate * averageLifetime) + one-shot burst counts <= particlesCfg[quality].budget
-- without reverse-engineering live ParticleEmitter state after a fire-and-forget
-- :Emit() burst. It only ever increases (conservative for a budget check).

local TweenService = game:GetService("TweenService")

export type WaterFXCfg = {
	stillWater: boolean?,
	rippleTrainCount: number?,
	rippleMaxRadiusMult: number?,
	rippleAccel: number?,
	suctionDipStuds: number?,
	shadowMaxMult: number?,
	domeHeightFrac: number?,
	domeRiseSeconds: number?,
	columnHeightMult: number?,
	columnSeconds: number?,
	cascadeSeconds: number?,
	debrisBurst: number?,
}

export type ParticlesTierCfg = { mult: number, budget: number }
export type ParticlesCfg = { [string]: ParticlesTierCfg }

local WaterFX = {}
WaterFX.__index = WaterFX

export type Fx = typeof(setmetatable(
	{} :: {
		_cfg: WaterFXCfg,
		_particlesCfg: ParticlesCfg,
		_stage: Folder,
		_surfacePos: Vector3,
		_quality: string,
		_mult: number,
		_budget: number,
		_rng: Random,
		_parts: { Instance },
		_tweens: { Tween },
		_waveSaved: { Size: number, Speed: number }?,
		_particleEstimate: number,
		_rippleTrainSpawned: number,
		_debrisFired: boolean,
		_shadowDisc: BasePart?,
		_dipDisc: BasePart?,
		_dome: BasePart?,
		_destroyed: boolean,
	},
	WaterFX
))

-- Visual constants not owned by Config.WATER (per-effect geometry that isn't a
-- tunable the brief asked for) -- mirrors ThrowHandler's own local constants
-- (SPLASH_TEX etc.), which likewise aren't pulled from a Config table.
local RING_THICKNESS = 0.12
local RING_COLOR = Color3.fromRGB(226, 244, 255)
local BONK_RING_START_D, BONK_RING_END_D, BONK_RING_LIFE = 2.0, 15, 0.55
local DREAD_RING_START_D, DREAD_RING_LIFE = 1.2, 0.9
local BASE_RIPPLE_D = 6
local SHADOW_BASE_D = 6
local SHADOW_TRANSPARENCY_START, SHADOW_TRANSPARENCY_END = 0.5, 0.15
local SURFACE_HUG = 0.03 -- matches ThrowHandler ripple()'s +0.04 "just above water" convention
local SHADOW_COLOR = Color3.fromRGB(8, 10, 14)
local DIP_COLOR = Color3.fromRGB(140, 200, 230)
-- RETUNED 2026-08-09 (owner: "big blue bubble like gum") -- the dome is now a DARK
-- swell, the surface bulging over something enormous, not a bright glass bubble.
local DOME_COLOR = Color3.fromRGB(26, 44, 52)
local DOME_TRANSPARENCY = 0.3
local COLUMN_COLOR = Color3.fromRGB(140, 210, 235)
local COLUMN_CROSS_D_MULT = 0.55 -- cross-section diameter, relative to modelExtents width
local FOAM_TEX = "rbxasset://textures/particles/smoke_main.dds"
local FOAM_BURST_BASE = 70
local MIST_RATE_BASE = 14
local MIST_LIFETIME = 0.55
local CASCADE_TEX = "rbxasset://textures/particles/smoke_main.dds"
local CASCADE_RATE_BASE = 9
local CASCADE_LIFETIME = 0.55
local CASCADE_MAX_PARTS = 3
local GODRAY_COUNT = 5
local GODRAY_COLOR = Color3.fromRGB(255, 250, 220)
local GODRAY_TRANSPARENCY = 0.78
local GODRAY_WIDTH, GODRAY_THICK = 3.2, 0.15
local GODRAY_RADIUS = 6 -- how far each wedge's base sits from the fan's centre pivot
local GODRAY_JITTER_DEG = 8
local GODRAY_LEN_JITTER = 0.3
local GODRAY_TILT_DEG = 12
local GODRAY_SPIN_DEG_PER_SEC = 2.5
local GODRAY_LEG_DEG = 30

local function decorPart(p: BasePart): BasePart
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Locked = true
	return p
end

function WaterFX.new(
	cfg: WaterFXCfg,
	particlesCfg: ParticlesCfg,
	stage: Folder,
	surfacePos: Vector3,
	quality: string,
	rng: Random
): Fx
	local tier = particlesCfg[quality] or particlesCfg.high or { mult = 1, budget = math.huge }
	local self = setmetatable({
		_cfg = cfg,
		_particlesCfg = particlesCfg,
		_stage = stage,
		_surfacePos = surfacePos,
		_quality = quality,
		_mult = tier.mult or 1,
		_budget = tier.budget or math.huge,
		_rng = rng,
		_parts = {},
		_tweens = {},
		_waveSaved = nil,
		_particleEstimate = 0,
		_rippleTrainSpawned = 0,
		_debrisFired = false,
		_shadowDisc = nil,
		_dipDisc = nil,
		_dome = nil,
		_destroyed = false,
	}, WaterFX)
	return (self :: any) :: Fx
end

-- Non-contractual: see the module header note on particle-budget verification.
function WaterFX:particleEstimate(): number
	return self._particleEstimate
end

function WaterFX:_ring(pos: Vector3, startD: number, endD: number, life: number, startAlpha: number): BasePart
	local ring = Instance.new("Part")
	ring.Name = "CinematicRipple"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(RING_THICKNESS, startD, startD)
	ring.Material = Enum.Material.Neon
	ring.Color = RING_COLOR
	ring.Transparency = math.max(startAlpha, 0.4)
	ring.CFrame = CFrame.new(pos.X, pos.Y + 0.04, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	decorPart(ring)
	ring.Parent = self._stage
	table.insert(self._parts, ring)

	local tw = TweenService:Create(
		ring,
		TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(RING_THICKNESS, endD, endD), Transparency = 1 }
	)
	table.insert(self._tweens, tw)
	tw:Play()
	return ring
end

-- One tiny impact ring -- reuses ThrowHandler's ripple recipe.
function WaterFX:bonkRing()
	self:_ring(self._surfacePos, BONK_RING_START_D, BONK_RING_END_D, BONK_RING_LIFE, 0.5)
end

-- THE THING THE ROCK HITS (owner 2026-08-09: "I don't see the rock visibly hitting
-- something"). A dark back barely breaking the waterline at the strike point: it
-- A RING OF PARTICLES bursting outward from a circle on the water: one :Emit from the
-- rim of a disc-shaped emitter, drifting out and fading. This is what shockRing() and
-- erupt()'s splash rings draw with now (2026-09-21): a Neon cylinder is a FILLED disc,
-- and at 6x the creature's width the "ring" was a glowing coin covering the water
-- under the reward -- the flat-disc look the reveal pass bans. No geometry at all here;
-- the particles ARE the ring. Counts scale by the quality mult.
function WaterFX:particleRing(pos: Vector3, startRadius: number, travel: number, life: number, color: Color3, count: number, size: number?)
	if self._destroyed then
		return
	end
	local r = math.max(startRadius, 0.5)
	local host = Instance.new("Part")
	host.Name = "ParticleRing"
	host.Size = Vector3.new(r * 2, 0.2, r * 2)
	host.Transparency = 1
	host.CFrame = CFrame.new(pos.X, pos.Y + 0.25, pos.Z)
	decorPart(host)
	host.Parent = self._stage
	table.insert(self._parts, host)

	local e = Instance.new("ParticleEmitter")
	e.Name = "RingBurst"
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Shape = Enum.ParticleEmitterShape.Disc
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	e.EmissionDirection = Enum.NormalId.Top
	e.Rate = 0
	e.Lifetime = NumberRange.new(life * 0.75, life)
	-- speed so the ring travels `travel` studs over its life
	local v = math.max(travel, 1) / math.max(life, 0.05)
	e.Speed = NumberRange.new(v * 0.8, v * 1.1)
	e.SpreadAngle = Vector2.new(5, 5)
	e.Acceleration = Vector3.new(0, 1.5, 0)
	e.Drag = 1.5
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-60, 60)
	e.LightEmission = 0.85
	e.Color = ColorSequence.new(color)
	local sz = size or 1.0
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, sz),
		NumberSequenceKeypoint.new(0.6, sz * 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.7, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Parent = host
	local n = math.max(math.floor(count * self._mult), 6)
	e:Emit(n)
	self._particleEstimate += n
end

-- The tier-coloured energy ring of the Mythic burst, the gold shockwave of God's
-- arrival: a particle ring now (see particleRing). Signature unchanged for callers.
function WaterFX:shockRing(color: Color3, maxRadius: number, life: number)
	if self._destroyed then
		return
	end
	local start = math.max(maxRadius * 0.12, 1)
	self:particleRing(self._surfacePos, start, maxRadius - start, life, color, 48 + math.floor(maxRadius * 1.2), 1.1)
	-- a brief light where the ring left, so the water under the creature answers it
	local host = Instance.new("Part")
	host.Name = "ShockLight"
	host.Size = Vector3.new(0.2, 0.2, 0.2)
	host.Transparency = 1
	host.CFrame = CFrame.new(self._surfacePos + Vector3.new(0, 1, 0))
	decorPart(host)
	host.Parent = self._stage
	table.insert(self._parts, host)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 3
	light.Range = math.clamp(maxRadius * 1.5, 12, 60)
	light.Shadows = false
	light.Parent = host
	task.spawn(function()
		local t0 = os.clock()
		while not self._destroyed and light.Parent do
			local a = math.clamp((os.clock() - t0) / math.max(life, 0.05), 0, 1)
			light.Brightness = 3 * (1 - a)
			if a >= 1 then
				break
			end
			task.wait()
		end
	end)
end

-- A CONCENTRATED POINT OF ENERGY forming at the surface (Mythic's gather beat):
-- sparkles converging on the point from a sphere around it, a light that brightens
-- with them, and a faint glow under the water. `seconds` is how long the gather runs
-- before the pulse; the emitter stops itself.
function WaterFX:energyPoint(color: Color3, radius: number, seconds: number)
	if self._destroyed then
		return
	end
	local host = Instance.new("Part")
	host.Name = "EnergyPoint"
	host.Shape = Enum.PartType.Ball
	host.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	host.Transparency = 1
	host.CFrame = CFrame.new(self._surfacePos + Vector3.new(0, 0.8, 0))
	decorPart(host)
	host.Parent = self._stage
	table.insert(self._parts, host)

	local e = Instance.new("ParticleEmitter")
	e.Name = "Gather"
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Shape = Enum.ParticleEmitterShape.Sphere
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	e.Rate = 90 * self._mult
	e.Lifetime = NumberRange.new(0.28, 0.42)
	e.Speed = NumberRange.new(radius / 0.4, radius / 0.3)
	e.SpreadAngle = Vector2.new(3, 3)
	e.LightEmission = 1
	e.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color),
		ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1):Lerp(color, 0.4)),
	})
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0.9),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	e.Parent = host
	self._particleEstimate += e.Rate * 0.35

	local core = Instance.new("Part")
	core.Name = "EnergyCore"
	core.Shape = Enum.PartType.Ball
	core.Material = Enum.Material.Neon
	core.Color = Color3.new(1, 1, 1):Lerp(color, 0.3)
	core.Transparency = 1
	core.Size = Vector3.new(0.6, 0.6, 0.6)
	core.CFrame = host.CFrame
	decorPart(core)
	core.Parent = self._stage
	table.insert(self._parts, core)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 0
	light.Range = 24
	light.Shadows = false
	light.Parent = core

	task.spawn(function()
		local t0 = os.clock()
		while not self._destroyed and core.Parent do
			local a = math.clamp((os.clock() - t0) / math.max(seconds, 0.05), 0, 1)
			local e2 = a * a
			core.Transparency = 1 - 0.9 * e2
			local d = 0.6 + 1.6 * e2
			core.Size = Vector3.new(d, d, d)
			light.Brightness = 5 * e2
			if a >= 1 then
				break
			end
			task.wait()
		end
		if e.Parent then
			e.Enabled = false
		end
	end)
	self:glowBelow(color, seconds)
end

-- THE UPWARD PULSE (Mythic's burst): a fast column of sparks and foam going straight
-- up through the creature's rise, a ring on the water, and the energy core let go.
-- Frames the creature -- it is a fountain of particles, not a tube around it.
function WaterFX:pulseUp(color: Color3, modelExtents: Vector3)
	if self._destroyed then
		return
	end
	local surf = self._surfacePos
	local width = math.max(math.max(modelExtents.X, modelExtents.Z), 2)
	local height = math.max(modelExtents.Y, 4)
	local host = Instance.new("Part")
	host.Name = "PulseHost"
	host.Size = Vector3.new(width * 0.5, 0.2, width * 0.5)
	host.Transparency = 1
	host.CFrame = CFrame.new(surf + Vector3.new(0, 0.3, 0))
	decorPart(host)
	host.Parent = self._stage
	table.insert(self._parts, host)

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "PulseSparks"
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Shape = Enum.ParticleEmitterShape.Disc
	sparks.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Rate = 0
	sparks.Lifetime = NumberRange.new(0.45, 0.8)
	sparks.Speed = NumberRange.new(height * 1.6, height * 2.4)
	sparks.SpreadAngle = Vector2.new(9, 9)
	sparks.Acceleration = Vector3.new(0, -height * 1.2, 0)
	sparks.Drag = 0.8
	sparks.LightEmission = 1
	sparks.Color = ColorSequence.new(color)
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Parent = host

	local foam = Instance.new("ParticleEmitter")
	foam.Name = "PulseFoam"
	foam.Texture = FOAM_TEX
	foam.Shape = Enum.ParticleEmitterShape.Disc
	foam.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	foam.EmissionDirection = Enum.NormalId.Top
	foam.Rate = 0
	foam.Lifetime = NumberRange.new(0.5, 0.9)
	foam.Speed = NumberRange.new(height * 1.0, height * 1.8)
	foam.SpreadAngle = Vector2.new(30, 30)
	foam.Acceleration = Vector3.new(0, -70, 0)
	foam.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.0),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	foam.Color = ColorSequence.new(Color3.fromRGB(236, 250, 255))
	foam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	foam.Parent = host

	local n1 = math.max(math.floor(70 * self._mult), 10)
	local n2 = math.max(math.floor(50 * self._mult), 8)
	sparks:Emit(n1)
	foam:Emit(n2)
	self._particleEstimate += n1 + n2

	self:particleRing(surf, width * 0.5, width * 1.6, 0.55, color, 40, 0.9)
end

-- JOLTS down on impact, holds a beat, then slides back under during the travel.
-- Same lifecycle as every other part here -- stage-parented, tracked, tween-tracked.
function WaterFX:bonkHump(radius: number)
	if self._destroyed then
		return
	end
	radius = math.max(radius or 6, 3)
	local hump = Instance.new("Part")
	hump.Name = "BonkHump"
	hump.Shape = Enum.PartType.Ball
	hump.Material = Enum.Material.SmoothPlastic
	hump.Color = Color3.fromRGB(18, 30, 36)
	-- FULLY OPAQUE, deliberately. This module's own hard-tested finding (see the
	-- suction shadow/dip discs below): a semi-transparent BasePart sitting below this
	-- place's TRUE water top renders completely invisible -- only 0.00 ever draws. The
	-- hump is mostly submerged by design, so 0.05 was the whole back not rendering.
	hump.Transparency = 0
	-- a low back, mostly submerged: wide, flat, only ~15% proud of the surface
	hump.Size = Vector3.new(radius * 2, radius * 0.9, radius * 1.4)
	hump.CFrame = CFrame.new(self._surfacePos - Vector3.new(0, radius * 0.28, 0))
	decorPart(hump)
	hump.Parent = self._stage
	table.insert(self._parts, hump)
	-- Impact jolt, in three tracked tweens: a sharp 0.12s dip, the recovery the
	-- comment always promised (0.3s ease back up by a tenth of the radius -- without
	-- it the back only ever went down, which read as dead weight rather than a living
	-- thing taking a hit), then the sink-away on the existing 0.9s delay, which lands
	-- after the recovery has finished (0.12 + 0.3 < 0.9).
	local dip = TweenService:Create(hump, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = hump.CFrame - Vector3.new(0, radius * 0.14, 0) })
	table.insert(self._tweens, dip)
	dip:Play()
	task.delay(0.12, function()
		if self._destroyed or not hump.Parent then
			return
		end
		local back = TweenService:Create(hump, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = hump.CFrame + Vector3.new(0, radius * 0.10, 0) })
		table.insert(self._tweens, back)
		back:Play()
	end)
	task.delay(0.9, function()
		if self._destroyed or not hump.Parent then
			return
		end
		-- No Transparency in this tween: fading it out would make it vanish outright on
		-- the first frame off 0 (see the note above the Transparency assignment). It
		-- leaves by sinking, so it sinks far enough (2.2r) to be genuinely gone.
		local sink = TweenService:Create(hump, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ CFrame = hump.CFrame - Vector3.new(0, radius * 2.2, 0) })
		table.insert(self._tweens, sink)
		sink:Play()
	end)
end

function WaterFX:stillWater()
	if self._cfg.stillWater == false then
		return
	end
	if self._waveSaved then
		return -- already saved -- idempotent, never overwrites the real originals
	end
	local terrain = workspace.Terrain
	self._waveSaved = { Size = terrain.WaterWaveSize, Speed = terrain.WaterWaveSpeed }
	terrain.WaterWaveSize = 0
	terrain.WaterWaveSpeed = 0
end

function WaterFX:_restoreWater()
	if self._waveSaved then
		local terrain = workspace.Terrain
		terrain.WaterWaveSize = self._waveSaved.Size
		terrain.WaterWaveSpeed = self._waveSaved.Speed
		self._waveSaved = nil
	end
end

-- Accelerating concentric ring train: spawn thresholds use exponent 1/rippleAccel
-- so gaps between successive rings SHRINK as progress climbs (dread ramping up).
-- Called every frame with an advancing 0..1 progress; catches up on any threshold
-- crossed between calls (robust to uneven frame timing).
function WaterFX:rippleTrain(progress: number)
	local p = math.clamp(progress, 0, 1)
	local cfg = self._cfg
	local count = math.max(math.floor(cfg.rippleTrainCount or 5), 0)
	local accel = math.max(cfg.rippleAccel or 1.6, 0.1)
	local maxD = BASE_RIPPLE_D * (cfg.rippleMaxRadiusMult or 3.2)

	while self._rippleTrainSpawned < count do
		local i = self._rippleTrainSpawned + 1
		local spawnAt = (i / count) ^ (1 / accel)
		if p < spawnAt then
			break
		end
		self:_ring(self._surfacePos, DREAD_RING_START_D, maxD, DREAD_RING_LIFE, 0.45)
		self._rippleTrainSpawned = i
	end
end

function WaterFX:_emitDebrisBurst()
	local cfg = self._cfg
	local count = math.max(math.floor((cfg.debrisBurst or 24) * self._mult), 0)
	if count <= 0 then
		return
	end
	local host = Instance.new("Part")
	host.Name = "SuctionDebrisHost"
	host.Size = Vector3.new(0.2, 0.2, 0.2)
	host.Transparency = 1
	host.CFrame = CFrame.new(self._surfacePos)
	decorPart(host)
	host.Parent = self._stage
	table.insert(self._parts, host)

	local e = Instance.new("ParticleEmitter")
	e.Name = "SuctionDebris"
	e.Texture = FOAM_TEX
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.3, 0.7)
	e.Speed = NumberRange.new(4, 10)
	e.EmissionDirection = Enum.NormalId.Top
	e.SpreadAngle = Vector2.new(70, 70)
	e.Acceleration = Vector3.new(0, -60, 0)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	e.Color = ColorSequence.new(SHADOW_COLOR:Lerp(Color3.new(1, 1, 1), 0.15))
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Parent = host
	e:Emit(count)
	self._particleEstimate += count
end

-- Dark disc growing under the surface + a slight visible dip. Both discs are
-- lazily created once and then updated in place every call -- a pure function of
-- progress, EXCEPT the one-shot debris burst at progress>=0.3 (guarded so it
-- fires exactly once regardless of how many frames straddle that threshold).
function WaterFX:suctionAndShadow(progress: number)
	local p = math.clamp(progress, 0, 1)
	local cfg = self._cfg
	local surf = self._surfacePos

	if not self._shadowDisc then
		local disc = Instance.new("Part")
		disc.Name = "SuctionShadow"
		disc.Shape = Enum.PartType.Cylinder
		disc.Material = Enum.Material.SmoothPlastic
		decorPart(disc)
		disc.Parent = self._stage
		table.insert(self._parts, disc)
		self._shadowDisc = disc
	end
	if not self._dipDisc then
		local dip = Instance.new("Part")
		dip.Name = "SuctionDip"
		dip.Shape = Enum.PartType.Cylinder
		dip.Material = Enum.Material.Neon
		decorPart(dip)
		dip.Parent = self._stage
		table.insert(self._parts, dip)
		self._dipDisc = dip
	end

	local shadowMaxMult = cfg.shadowMaxMult or 1.4
	local d = SHADOW_BASE_D + (SHADOW_BASE_D * shadowMaxMult - SHADOW_BASE_D) * p
	local disc = self._shadowDisc :: BasePart
	disc.Size = Vector3.new(0.3, d, d)
	disc.Color = SHADOW_COLOR
	disc.Transparency = SHADOW_TRANSPARENCY_START - (SHADOW_TRANSPARENCY_START - SHADOW_TRANSPARENCY_END) * p
	-- Sits AT the surface (SURFACE_HUG, same convention as ThrowHandler's ripple()
	-- +0.04) rather than literally below it. Hard-tested finding: a semi-transparent
	-- BasePart positioned below this place's TRUE water top renders completely
	-- invisible, on both SmoothPlastic and Neon -- swept Transparency 0.00 to 0.20
	-- at a fixed underwater depth and only 0.00 (fully opaque) ever rendered.
	-- Ripples read as "on the water" for the same reason: they sit a hair ABOVE the
	-- true surface, never below it. So "growing under the surface" is depicted here
	-- as a dark stain spreading ACROSS the surface, not a literal submerged disc.
	disc.CFrame = CFrame.new(surf.X, surf.Y + SURFACE_HUG, surf.Z) * CFrame.Angles(0, 0, math.rad(90))

	local dipStuds = cfg.suctionDipStuds or 1.1
	local dip = self._dipDisc :: BasePart
	local dipD = BASE_RIPPLE_D * 0.9
	dip.Size = Vector3.new(0.15, dipD, dipD)
	dip.Color = DIP_COLOR
	-- Fully opaque -- see the shadow disc's comment above. This one DOES go
	-- genuinely underwater as it lowers, so it needs Transparency 0 to render at
	-- all; reads as a bright sinking whirlpool core rather than a tint, which
	-- still sells "the surface is being pulled down" fine.
	dip.Transparency = 0
	dip.CFrame = CFrame.new(surf.X, surf.Y - dipStuds * p, surf.Z) * CFrame.Angles(0, 0, math.rad(90))

	if not self._debrisFired and p >= 0.3 then
		self._debrisFired = true
		self:_emitDebrisBurst()
	end
end

-- Water-coloured hemisphere (flattened ellipsoid Ball, half-sunk) taut over the
-- silhouette. Only the height grows during the rise -- the footprint (radius) is
-- set once, matching "taut over the silhouette" rather than "swelling outward".
function WaterFX:dome(radius: number)
	if self._dome then
		return
	end
	local cfg = self._cfg
	local heightFrac = cfg.domeHeightFrac or 0.35
	local riseSeconds = cfg.domeRiseSeconds or 0.42

	local ball = Instance.new("Part")
	ball.Name = "SuctionDome"
	ball.Shape = Enum.PartType.Ball
	ball.Material = Enum.Material.Glass
	ball.Color = DOME_COLOR
	ball.Transparency = DOME_TRANSPARENCY
	ball.Size = Vector3.new(radius * 2, 0.2, radius * 2)
	ball.CFrame = CFrame.new(self._surfacePos)
	decorPart(ball)
	ball.Parent = self._stage
	table.insert(self._parts, ball)
	self._dome = ball

	local tw = TweenService:Create(
		ball,
		TweenInfo.new(riseSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(radius * 2, radius * 2 * heightFrac, radius * 2) }
	)
	table.insert(self._tweens, tw)
	tw:Play()
end

-- A glowing disc just UNDER the surface, fading in over `seconds`: Secret's
-- "something is down there" fake-out and God's gold water. Its PointLight is
-- hand-lerped (Brightness is not on the Tween allow-list).
function WaterFX:glowBelow(color: Color3, seconds: number)
	if self._destroyed then
		return
	end
	local disc = Instance.new("Part")
	disc.Name = "GlowBelow"
	disc.Shape = Enum.PartType.Cylinder
	disc.Material = Enum.Material.Neon
	disc.Color = color
	disc.Transparency = 1
	disc.Size = Vector3.new(0.3, 6, 6)
	disc.CFrame = CFrame.new(self._surfacePos - Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	decorPart(disc)
	disc.Parent = self._stage
	table.insert(self._parts, disc)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 0
	light.Range = 30
	light.Parent = disc
	local tw = TweenService:Create(disc, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Transparency = 0.35, Size = Vector3.new(0.3, 18, 18),
	})
	table.insert(self._tweens, tw)
	tw:Play()
	task.spawn(function()
		local t0 = os.clock()
		while not self._destroyed and light.Parent do
			local a = math.clamp((os.clock() - t0) / math.max(seconds, 0.05), 0, 1)
			light.Brightness = 3 * a
			if a >= 1 then
				break
			end
			task.wait()
		end
	end)
end

-- Destroys the dome WITH the eruption: a fast outward pop-and-fade, then gone.
function WaterFX:burstDome()
	local ball = self._dome
	if not ball then
		return
	end
	self._dome = nil
	local tw = TweenService:Create(
		ball,
		TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = ball.Size * Vector3.new(1.5, 0.2, 1.5), Transparency = 1 }
	)
	table.insert(self._tweens, tw)
	tw.Completed:Once(function()
		ball:Destroy()
	end)
	tw:Play()
end

-- Vertical column + radial splash ring cascade + one-shot foam sheet. Rates and
-- burst counts scale by this instance's quality mult, same as debrisBurst.
function WaterFX:erupt(modelExtents: Vector3)
	local cfg = self._cfg
	local columnHeight = math.max((cfg.columnHeightMult or 2.6) * modelExtents.Y, 1)
	local columnSeconds = math.max(cfg.columnSeconds or 0.7, 0.05)
	local crossD = math.max(math.max(modelExtents.X, modelExtents.Z) * COLUMN_CROSS_D_MULT, 1)
	local surf = self._surfacePos

	-- A SPOUT, NOT A TUBE (2026-09-21). The column used to be 2.6x the creature's
	-- height and over half its width at 0.25 transparency -- a glass cylinder the
	-- reward rose up inside, and on a Massive a 120-stud tube. Now: a slim, short,
	-- mostly-transparent core (the wet "spine" of the splash) plus a spray of foam
	-- particles that does the visual work. The creature is never inside it.
	columnHeight = columnHeight * 0.55
	crossD = crossD * 0.5
	columnSeconds = columnSeconds * 0.7
	do
		local spout = Instance.new("ParticleEmitter")
		spout.Name = "EruptionSpout"
		spout.Texture = FOAM_TEX
		spout.Shape = Enum.ParticleEmitterShape.Disc
		spout.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		spout.EmissionDirection = Enum.NormalId.Top
		spout.Rate = 0
		spout.Lifetime = NumberRange.new(0.5, 0.95)
		spout.Speed = NumberRange.new(columnHeight * 1.4, columnHeight * 2.2)
		spout.SpreadAngle = Vector2.new(14, 14)
		spout.Acceleration = Vector3.new(0, -columnHeight * 2.0, 0)
		spout.Drag = 0.6
		spout.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, math.clamp(crossD * 0.35, 0.8, 4)),
			NumberSequenceKeypoint.new(1, 0.2),
		})
		spout.Color = ColorSequence.new(Color3.fromRGB(230, 246, 255))
		spout.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		local spoutHost = Instance.new("Part")
		spoutHost.Name = "EruptionSpoutHost"
		spoutHost.Size = Vector3.new(crossD, 0.2, crossD)
		spoutHost.Transparency = 1
		spoutHost.CFrame = CFrame.new(surf.X, surf.Y + 0.2, surf.Z)
		decorPart(spoutHost)
		spoutHost.Parent = self._stage
		table.insert(self._parts, spoutHost)
		spout.Parent = spoutHost
		local n = math.max(math.floor(90 * self._mult), 12)
		spout:Emit(n)
		self._particleEstimate += n
	end

	-- Vertical column: same flat-cylinder rotation ThrowHandler's ripple() uses,
	-- just applied to a TALL cylinder (Size.X is the length axis pre-rotation;
	-- CFrame.Angles(0,0,90) always maps it to world Y, regardless of magnitude).
	local column = Instance.new("Part")
	column.Name = "EruptionColumn"
	column.Shape = Enum.PartType.Cylinder
	column.Material = Enum.Material.Glass
	column.Color = COLUMN_COLOR
	column.Transparency = 0.55
	column.Size = Vector3.new(0.4, crossD, crossD)
	column.CFrame = CFrame.new(surf.X, surf.Y + 0.2, surf.Z) * CFrame.Angles(0, 0, math.rad(90))
	decorPart(column)
	column.Parent = self._stage
	table.insert(self._parts, column)

	local growTw = TweenService:Create(
		column,
		TweenInfo.new(columnSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = Vector3.new(columnHeight, crossD, crossD),
			CFrame = CFrame.new(surf.X, surf.Y + columnHeight / 2, surf.Z) * CFrame.Angles(0, 0, math.rad(90)),
		}
	)
	table.insert(self._tweens, growTw)
	growTw:Play()
	growTw.Completed:Once(function()
		if not column.Parent then
			return
		end
		local fadeTw = TweenService:Create(
			column,
			TweenInfo.new(columnSeconds * 0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
			{ Transparency = 1, Size = Vector3.new(columnHeight * 0.6, crossD * 0.5, crossD * 0.5) }
		)
		table.insert(self._tweens, fadeTw)
		fadeTw:Play()
	end)

	-- Mist riding the column, auto-disabled after columnSeconds.
	local mistHost = Instance.new("Attachment")
	mistHost.Name = "MistAttach"
	mistHost.Parent = column
	local mist = Instance.new("ParticleEmitter")
	mist.Name = "EruptionMist"
	mist.Texture = FOAM_TEX
	mist.Rate = MIST_RATE_BASE * self._mult
	mist.Lifetime = NumberRange.new(MIST_LIFETIME * 0.7, MIST_LIFETIME)
	mist.Speed = NumberRange.new(2, 6)
	mist.SpreadAngle = Vector2.new(35, 35)
	mist.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 1.6),
	})
	mist.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	mist.Color = ColorSequence.new(COLUMN_COLOR)
	mist.Parent = mistHost
	self._particleEstimate += mist.Rate * ((MIST_LIFETIME * 0.7 + MIST_LIFETIME) / 2)
	task.delay(columnSeconds, function()
		if mist.Parent then
			mist.Enabled = false
		end
	end)

	-- Radial splash: three cascading PARTICLE rings (2026-09-21 -- these were three
	-- filled Neon discs up to 3.2x the creature's footprint), ThrowHandler's "big"
	-- splash cadence scaled to the model's own footprint.
	local ringBase = math.max(modelExtents.X, modelExtents.Z) * 1.4
	local ringColor = Color3.fromRGB(226, 244, 255)
	self:particleRing(surf, ringBase * 0.5, ringBase * 1.1, 0.85, ringColor, 40, 1.0)
	task.delay(0.10, function()
		if not self._destroyed then
			self:particleRing(surf, ringBase * 0.4, ringBase * 2.0, 1.1, ringColor, 48, 0.9)
		end
	end)
	task.delay(0.22, function()
		if not self._destroyed then
			self:particleRing(surf, ringBase * 0.3, ringBase * 2.9, 1.45, ringColor, 56, 0.8)
		end
	end)

	-- Foam sheet: one-shot burst.
	local foamHost = Instance.new("Part")
	foamHost.Name = "EruptionFoamHost"
	foamHost.Size = Vector3.new(0.2, 0.2, 0.2)
	foamHost.Transparency = 1
	foamHost.CFrame = CFrame.new(surf.X, surf.Y + 0.15, surf.Z)
	decorPart(foamHost)
	foamHost.Parent = self._stage
	table.insert(self._parts, foamHost)

	local foam = Instance.new("ParticleEmitter")
	foam.Name = "EruptionFoam"
	foam.Texture = FOAM_TEX
	foam.Rate = 0
	foam.Lifetime = NumberRange.new(0.5, 1.1)
	foam.Speed = NumberRange.new(14, 30)
	foam.EmissionDirection = Enum.NormalId.Top
	foam.SpreadAngle = Vector2.new(60, 60)
	foam.Acceleration = Vector3.new(0, -80, 0)
	foam.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	foam.Color = ColorSequence.new(Color3.fromRGB(236, 250, 255))
	foam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	foam.Parent = foamHost
	local foamCount = math.max(math.floor(FOAM_BURST_BASE * self._mult), 1)
	foam:Emit(foamCount)
	self._particleEstimate += foamCount
end

-- Waterfall ParticleEmitters attached to the model's UPPER parts (top 3 by world
-- Y, deterministic by position -- no rng needed for a purely positional choice).
-- Auto-fades: each emitter runs for `seconds` then Enabled=false; already-alive
-- particles finish out their own Transparency ramp naturally.
function WaterFX:cascade(model: Model, seconds: number)
	local parts: { BasePart } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	if #parts == 0 then
		return
	end
	table.sort(parts, function(a, b)
		return a.Position.Y > b.Position.Y
	end)

	local n = math.min(CASCADE_MAX_PARTS, #parts)
	for i = 1, n do
		local part = parts[i]
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "CinematicCascade"
		emitter.Texture = CASCADE_TEX
		emitter.Rate = CASCADE_RATE_BASE * self._mult
		emitter.Lifetime = NumberRange.new(CASCADE_LIFETIME * 0.7, CASCADE_LIFETIME)
		emitter.Speed = NumberRange.new(2, 5)
		emitter.EmissionDirection = Enum.NormalId.Bottom
		emitter.SpreadAngle = Vector2.new(12, 12)
		emitter.Acceleration = Vector3.new(0, -50, 0)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 0.15),
		})
		emitter.Color = ColorSequence.new(Color3.fromRGB(210, 235, 250))
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Parent = part
		table.insert(self._parts, emitter)
		self._particleEstimate += emitter.Rate * ((CASCADE_LIFETIME * 0.7 + CASCADE_LIFETIME) / 2)

		task.delay(seconds, function()
			if emitter.Parent then
				emitter.Enabled = false
			end
		end)
	end
end

-- Chains small-arc (GODRAY_LEG_DEG) CFrame tweens around `pivot` forever -- the
-- "slow rotation", built entirely from TweenService (no RenderStepped). Each leg
-- is small enough that the straight-line position Lerp between its two endpoints
-- is visually indistinguishable from the true arc. Stops the instant
-- self._destroyed flips (checked before every new leg is queued).
function WaterFX:_orbitForever(part: BasePart, pivot: Vector3, localOffsetCF: CFrame, startAngleDeg: number, degPerSec: number)
	local function step(angleDeg: number)
		if self._destroyed or not part.Parent then
			return
		end
		local nextAngle = angleDeg + GODRAY_LEG_DEG
		local legSeconds = GODRAY_LEG_DEG / math.max(degPerSec, 0.01)
		local targetCF = CFrame.new(pivot) * CFrame.Angles(0, math.rad(nextAngle), 0) * localOffsetCF
		local tw = TweenService:Create(part, TweenInfo.new(legSeconds, Enum.EasingStyle.Linear), { CFrame = targetCF })
		table.insert(self._tweens, tw)
		tw.Completed:Once(function()
			step(nextAngle)
		end)
		tw:Play()
	end
	step(startAngleDeg)
end

-- 5 long translucent Neon wedges (plain Blocks -- WedgePart's taper axis isn't
-- worth the guesswork for a light-shaft silhouette) fanned behind `pos`, slow
-- rotation. Per-wedge angle/length jitter is the ONE rng draw in this module.
function WaterFX:godrays(pos: Vector3, height: number, color: Color3?)
	local baseAngle = 360 / GODRAY_COUNT
	for i = 1, GODRAY_COUNT do
		local jitterDeg = (self._rng:NextNumber() - 0.5) * 2 * GODRAY_JITTER_DEG
		local lenMult = 1 + (self._rng:NextNumber() - 0.5) * 2 * GODRAY_LEN_JITTER
		local startAngle = (i - 1) * baseAngle + jitterDeg
		local rayHeight = height * lenMult

		local w = Instance.new("Part")
		w.Name = "Godray"
		w.Shape = Enum.PartType.Block
		w.Material = Enum.Material.Neon
		w.Color = color or GODRAY_COLOR
		w.Transparency = GODRAY_TRANSPARENCY
		w.Size = Vector3.new(GODRAY_WIDTH, rayHeight, GODRAY_THICK)
		decorPart(w)

		-- Local offset: stood up behind pos at GODRAY_RADIUS studs out, leaning back
		-- slightly. Must clear whatever's at the centre (e.g. erupt()'s column) or
		-- the fan hides behind it -- GODRAY_WIDTH*0.3 (under 1 stud) was PROVEN too
		-- tight in-place: all 5 wedges rendered clustered inside the column's own
		-- ~2.75-stud radius, fully occluded.
		local localOffsetCF = CFrame.new(0, rayHeight / 2, -GODRAY_RADIUS) * CFrame.Angles(math.rad(GODRAY_TILT_DEG), 0, 0)
		w.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.rad(startAngle), 0) * localOffsetCF
		w.Parent = self._stage
		table.insert(self._parts, w)

		self:_orbitForever(w, pos, localOffsetCF, startAngle, GODRAY_SPIN_DEG_PER_SEC)
	end
end

-- Destroys everything this instance made, restores Terrain wave props. Sets
-- _destroyed FIRST so any in-flight task.delay/chained-tween callbacks no-op
-- instead of racing new parts into existence after teardown.
function WaterFX:cleanup()
	self._destroyed = true
	for _, tw in ipairs(self._tweens) do
		pcall(function()
			tw:Cancel()
		end)
	end
	self._tweens = {}
	for _, inst in ipairs(self._parts) do
		pcall(function()
			inst:Destroy()
		end)
	end
	self._parts = {}
	self._shadowDisc = nil
	self._dipDisc = nil
	self._dome = nil
	self:_restoreWater()
end

return WaterFX
