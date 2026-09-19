-- GardensWater -- waterfalls, cascades, spray and mist.
--
-- Roblox terrain water cannot fall, so every vertical water feature here is built
-- from parts. The look is taken from the reference image: not a flat blue slab but
-- a bundle of bright VERTICAL STREAKS at slightly different depths and speeds,
-- brightest at the edges, dissolving into mist at the bottom.
--
-- Particle textures are all rbxasset:// paths that ship with the client -- no
-- marketplace ids, so nothing here can break from an asset going private.

local L = require(script.Parent.Lib)
local W = {}

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

W.WATER_COL   = Color3.fromRGB(198, 236, 240)
W.WATER_DEEP  = Color3.fromRGB(126, 190, 208)
W.FOAM        = Color3.fromRGB(236, 250, 250)

-- A soft mist emitter. `size` is the emitter's part size (the volume it fills).
function W.mist(parent, cf, size, opts)
	opts = opts or {}
	local p = L.box(parent, opts.name or "Mist", cf, size, W.FOAM, Enum.Material.Neon,
		{collide = false, shadow = false, transparency = 1})
	local e = Instance.new("ParticleEmitter")
	e.Texture = SMOKE
	e.Color = ColorSequence.new(opts.color or Color3.fromRGB(216, 240, 236))
	e.LightEmission = opts.lightEmission or 0.35
	e.LightInfluence = 0.4
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, (opts.sizeMin or 14)),
		NumberSequenceKeypoint.new(1, (opts.sizeMax or 42)),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, opts.alpha or 0.72),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Rate = opts.rate or 6
	e.Lifetime = NumberRange.new(opts.life or 5, (opts.life or 5) * 1.8)
	e.Speed = NumberRange.new(opts.speed or 1, (opts.speed or 1) * 3)
	e.SpreadAngle = Vector2.new(40, 40)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-8, 8)
	e.VelocityInheritance = 0
	e.EmissionDirection = opts.dir or Enum.NormalId.Top
	e.Acceleration = opts.accel or Vector3.new(0, 1.5, 0)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.Parent = p
	return p
end

-- Spray thrown off where falling water lands.
function W.spray(parent, cf, opts)
	opts = opts or {}
	local p = L.box(parent, "Spray", cf, opts.size or Vector3.new(10, 4, 10), W.FOAM, Enum.Material.Neon,
		{collide = false, shadow = false, transparency = 1})
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARK
	e.Color = ColorSequence.new(W.FOAM)
	e.LightEmission = 0.7
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, opts.sizeMin or 2.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Rate = opts.rate or 26
	e.Lifetime = NumberRange.new(0.7, 1.6)
	e.Speed = NumberRange.new(opts.speed or 12, (opts.speed or 12) * 2)
	e.SpreadAngle = Vector2.new(55, 55)
	e.Acceleration = Vector3.new(0, -42, 0)
	e.EmissionDirection = Enum.NormalId.Top
	e.Shape = Enum.ParticleEmitterShape.Box
	e.Parent = p
	return p
end

----------------------------------------------------------------------------------
-- THE WATERFALL
----------------------------------------------------------------------------------
-- top / bot : world Vector3 at the centre of the lip and of the landing
-- width     : stud width at the lip (it flares toward the bottom)
-- opts.flare, opts.streaks, opts.seed, opts.glow, opts.lit
function W.waterfall(parent, top, bot, width, opts)
	opts = opts or {}
	local model = Instance.new("Model")
	model.Name = opts.name or "Waterfall"
	model.Parent = parent

	local rng = Random.new(opts.seed or 1)
	local drop = top - bot                 -- points from the landing UP to the lip
	local height = drop.Magnitude
	local flatDir = Vector3.new(drop.X, 0, drop.Z)
	-- the horizontal direction the water travels as it falls
	local face = flatDir.Magnitude > 0.5 and flatDir.Unit or (opts.face or Vector3.new(0, 0, 1))
	local mid = (top + bot) * 0.5

	-- THE SHEET LEANS WITH THE DROP. Built as a plain vertical box, a fall down a
	-- sloped cliff face hung in mid-air next to the rock instead of running down it,
	-- and its height came out as the 3D distance rather than the vertical drop. This
	-- frame puts local +Y along the fall itself and local X across it, so the body,
	-- streaks and mist all follow the rock no matter how angled the descent is.
	local dirUp = drop.Magnitude > 0.01 and drop.Unit or Vector3.new(0, 1, 0)
	local right = face:Cross(Vector3.new(0, 1, 0))
	right = right.Magnitude > 0.01 and right.Unit or Vector3.new(1, 0, 0)
	local baseCF = CFrame.fromMatrix(mid, right, dirUp)
	local flare = opts.flare or 1.35
	local botW = width * flare

	-- 1. THE CURTAIN.
	--    Three big overlapping panes read as sheets of glass, not water -- hard
	--    rectangular edges, a dead straight top, and nothing suggesting movement.
	--    Instead the body is a bundle of narrow ribbons, each split into vertical
	--    segments that step OUTWARD as they descend, so the curtain flares, its side
	--    edges break up, and its top edge is ragged.
	local ribbons = opts.ribbons or math.clamp(math.floor(width / 3.2), 8, 44)
	local segs = math.clamp(math.floor(height / 130) + 1, 2, 5)
	for i = 1, ribbons do
		local u = (i - 0.5) / ribbons
		local x0 = (u - 0.5) * width
		-- overlap generously: at low density the flare pulled the ribbons apart and
		-- left daylight gaps down the middle of the curtain
		local rw = rng:NextNumber(3.0, math.max(4.4, width / ribbons * 2.4))
		local startT = rng:NextNumber(0, 0.07)
		local endT = rng:NextNumber(0.96, 1.0)
		local bright = rng:NextNumber() < 0.32
		for s = 0, segs - 1 do
			local t0 = startT + (endT - startT) * (s / segs)
			local t1 = startT + (endT - startT) * ((s + 1) / segs)
			local tm = (t0 + t1) * 0.5
			local spread = 1 + (flare - 1) * tm
			local p = L.box(model, "FallRibbon",
				baseCF * CFrame.new(x0 * spread + rng:NextNumber(-1.6, 1.6),
					(0.5 - tm) * height, rng:NextNumber(-3.0, 3.0)),
				Vector3.new(rw, (t1 - t0) * height + 1.6, rng:NextNumber(1.4, 3.4)),
				bright and W.FOAM or W.WATER_COL,
				bright and Enum.Material.Neon or Enum.Material.Glass,
				{collide = false, shadow = false})
			p.Transparency = bright and rng:NextNumber(0.46, 0.72) or rng:NextNumber(0.3, 0.58)
			if not bright then p.Reflectance = 0.2 end
		end
	end
	-- two near-invisible backing panes so the curtain has volume behind the ribbons
	for i = 1, 2 do
		local p = L.box(model, "FallBody",
			baseCF * CFrame.new(0, 0, (i - 1.5) * 4.4),
			Vector3.new(L.lerp(width, botW, 0.55) * 0.94, height * 0.99, 2.2),
			W.WATER_DEEP, Enum.Material.Glass, {collide = false, shadow = false})
		p.Transparency = 0.68
	end

	-- 3. the lip: water bulging over the edge, plus the rock lip itself if asked
	local lipCF = CFrame.fromMatrix(top, right, Vector3.new(0, 1, 0))
	L.box(model, "Lip", lipCF * CFrame.new(0, -1.2, 0), Vector3.new(width * 1.04, 3.4, 7),
		W.WATER_COL, Enum.Material.Glass, {collide = false, shadow = false, transparency = 0.34})
	L.cyl(model, "LipRoll", lipCF * CFrame.new(0, 0.2, -2.2) * CFrame.Angles(0, math.rad(90), 0),
		width * 1.02, 3.6, W.FOAM, Enum.Material.Neon, {collide = false, shadow = false, transparency = 0.55})
	-- mist at the lip, so the top of the curtain dissolves into spray instead of
	-- ending on a hard horizontal line
	W.mist(model, lipCF * CFrame.new(0, -height * 0.04 - 4, 0),
		Vector3.new(width * 1.25, math.min(height * 0.1, 26), 16),
		{rate = math.clamp(width * 0.35, 3, 22), sizeMin = 10, sizeMax = 30, alpha = 0.7, speed = 2})

	-- 4. the landing: foam, spray, and a lot of mist
	local footCF = CFrame.fromMatrix(bot, right, Vector3.new(0, 1, 0))
	L.cyl(model, "Foam", footCF * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.rad(90)),
		1.2, botW * 1.5, W.FOAM, Enum.Material.Neon, {collide = false, shadow = false, transparency = 0.45})
	L.cyl(model, "FoamOuter", footCF * CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, math.rad(90)),
		0.8, botW * 2.4, W.FOAM, Enum.Material.Glass, {collide = false, shadow = false, transparency = 0.72})
	W.spray(model, footCF * CFrame.new(0, 2, 0), {
		size = Vector3.new(botW, 4, 10), rate = math.floor(width * 1.6), speed = math.min(10 + height * 0.05, 34)})
	W.mist(model, footCF * CFrame.new(0, height * 0.06 + 8, 0),
		Vector3.new(botW * 1.8, math.min(height * 0.3, 70), 30),
		{rate = math.clamp(width * 0.5, 4, 34), sizeMin = 16, sizeMax = 54, alpha = 0.6, speed = 3})

	-- mist ladders up tall falls so the whole drop is atmospheric, not just its foot
	local rungs = math.clamp(math.floor(height / 90), 0, 6)
	for i = 1, rungs do
		local t = i / (rungs + 1)
		W.mist(model, baseCF * CFrame.new(0, (0.5 - t) * height, 0),
			Vector3.new(botW * 1.2, height * 0.16, 22),
			{rate = 4, sizeMin = 14, sizeMax = 40, alpha = 0.78, speed = 2})
	end

	-- 5. light. Falling water in a dark cavern is a light source in its own right.
	if opts.lit ~= false then
		local lp = L.box(model, "FallLight", footCF * CFrame.new(0, 10, 0), Vector3.new(1, 1, 1),
			W.FOAM, Enum.Material.Neon, {collide = false, shadow = false, transparency = 1})
		L.light(lp, opts.lightColor or Color3.fromRGB(178, 226, 236), opts.lightBrightness or 2.2,
			math.clamp(botW * 2.2, 30, 60))
		local steps = math.clamp(math.floor(height / 130), 0, 5)
		for i = 1, steps do
			local t = i / (steps + 1)
			local q = L.box(model, "FallLight", baseCF * CFrame.new(0, (0.5 - t) * height, 0), Vector3.new(1, 1, 1),
				W.FOAM, Enum.Material.Neon, {collide = false, shadow = false, transparency = 1})
			L.light(q, opts.lightColor or Color3.fromRGB(178, 226, 236), 1.1, 40)
		end
	end
	return model
end

-- A stepped cascade running down a list of world points (each a pool lip).
function W.cascade(parent, pts, width, opts)
	opts = opts or {}
	local model = Instance.new("Model")
	model.Name = opts.name or "Cascade"
	model.Parent = parent
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local w = width * (opts.taper and (1 - 0.06 * i) or 1)
		W.waterfall(model, a, b, w, {
			seed = (opts.seed or 7) + i * 13, flare = 1.15,
			lightBrightness = 1.2, name = "Step" .. i,
		})
		-- the pool each step lands in
		L.cyl(model, "Pool", CFrame.new(b + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			1.6, w * 2.2, W.WATER_DEEP, Enum.Material.Glass,
			{collide = false, shadow = false, transparency = 0.42})
	end
	return model
end

-- A still pool surface (for pools that sit above the terrain water table).
function W.pool(parent, centre, radius, opts)
	opts = opts or {}
	local m = Instance.new("Model")
	m.Name = opts.name or "Pool"
	m.Parent = parent
	local p = L.cyl(m, "Surface", CFrame.new(centre) * CFrame.Angles(0, 0, math.rad(90)),
		0.8, radius * 2, opts.color or W.WATER_DEEP, Enum.Material.Glass,
		{collide = false, shadow = false})
	p.Transparency = opts.transparency or 0.38
	p.Reflectance = 0.3
	if opts.glow then
		local g = L.cyl(m, "Glow", CFrame.new(centre - Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			0.4, radius * 1.8, opts.glow, Enum.Material.Neon, {collide = false, shadow = false, transparency = 0.62})
		L.light(g, opts.glow, 1.4, radius * 3)
	end
	return m
end

return W
