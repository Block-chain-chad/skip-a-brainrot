-- BuildLife -- fireflies, drifting spores, and the wildlife.
--
-- The brief asks for the world to feel ALIVE, not merely pretty. Two layers:
--   * PARTICLES: fireflies over the vegetated ground, pollen drifting through the lit
--     spaces, leaves falling near the tree cover, spores in the Fungal Hollow.
--   * ANIMALS: the Creature module's figures, recoloured out of stone into fur and
--     feather and scaled down to real animal size, placed sparsely -- deer in the
--     open ground, rabbits near the town, owls up on ruins and branches.
--
-- Deliberately sparse: the brief says spread through the world rather than placed
-- everywhere, and every emitter costs GPU whether anyone is looking at it or not.

local L = require(script.Parent.Lib)
local F = require(script.Parent.Field)
local C = require(script.Parent.Creature)

local M = {}

local function g(x, z) return F.ground(x, z, F.ceiling(x, z)) end

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function emitter(parent, name, cf, size, cfg)
	local p = L.box(parent, name, cf, size, cfg.color or L.C.GlowGold, Enum.Material.Neon,
		{collide = false, shadow = false, transparency = 1})
	local e = Instance.new("ParticleEmitter")
	e.Texture = cfg.texture or SPARK
	e.Color = ColorSequence.new(cfg.color or L.C.GlowGold)
	e.LightEmission = cfg.lightEmission or 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.25, cfg.size or 1.2),
		NumberSequenceKeypoint.new(0.75, cfg.size or 1.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, cfg.alpha or 0.1),
		NumberSequenceKeypoint.new(0.8, cfg.alpha or 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Rate = cfg.rate or 4
	e.Lifetime = NumberRange.new(cfg.life or 6, (cfg.life or 6) * 1.7)
	e.Speed = NumberRange.new(cfg.speed or 1, (cfg.speed or 1) * 2.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = cfg.accel or Vector3.new(0, 0.4, 0)
	e.Drag = cfg.drag or 1.2
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-30, 30)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = p
	return p
end

-- Turn one of the stone figures into a living animal: fur colours, soft material,
-- no collision (so it never blocks a doorway or a bridge).
local function liven(model, body, accent)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Material ~= Enum.Material.Neon then
				d.Material = Enum.Material.SmoothPlastic
				local n = d.Name
				if n == "Eye" or n == "Nose" or n == "OwlEye" then
					d.Color = Color3.fromRGB(24, 20, 18)
				elseif n == "Muzzle" or n == "OwlFace" or n == "Tail" or n == "Mane" or n == "OwlTuft" then
					d.Color = accent
				elseif n == "Hoof" or n == "Paw" or n == "Talon" or n == "TalonTip" or n == "BirdBeak" or n == "OwlBeak" then
					d.Color = Color3.fromRGB(52, 44, 40)
				elseif n ~= "Moss" and n ~= "Vine" and n ~= "VineLeaf" then
					d.Color = body
				end
			end
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
end

function M.run()
	local root = workspace.GameWorld.LushGardens
	local life = L.folder(root, "Wildlife")
	life:ClearAllChildren()
	local fx = L.folder(root, "Effects")
	fx:ClearAllChildren()
	local rng = Random.new(31337)
	local counts = {fireflies = 0, pollen = 0, leaves = 0, spores = 0, animals = 0}

	----------------------------------------------------------------- fireflies
	-- Scattered over vegetated ground, avoiding water and the bare wall band.
	for i = 1, 700 do
		if counts.fireflies >= 34 then break end
		local x = rng:NextNumber(-1150, 1150)
		local z = rng:NextNumber(-1150, 1150)
		local ch = F.ceiling(x, z)
		local y = F.ground(x, z, ch)
		if y > F.WATER + 3 and y < 300 and ch > y + 60 and F.squircle(x, z) < F.PLAY - 90 then
			emitter(fx, "Fireflies", L.wcf(x, y + 16, z), Vector3.new(150, 34, 150), {
				color = rng:NextNumber() < 0.75 and L.C.GlowGold or L.C.GlowGreen,
				rate = 7, size = 0.9, life = 8, speed = 1.4, alpha = 0.05,
				accel = Vector3.new(0, 0.2, 0),
			})
			counts.fireflies = counts.fireflies + 1
		end
	end

	----------------------------------------------------------------- pollen and mist motes
	for _, spot in ipairs({
		{F.HUB.X, F.HUB.Y, 300}, {-40, -250, 280}, {F.HILL.X, F.HILL.Y, 260},
		{F.CASCADE.X, F.CASCADE.Y, 240}, {F.SUNKEN.X, F.SUNKEN.Y, 240},
		{F.FUNGAL.X, F.FUNGAL.Y, 220}, {0, 1180, 180},
	}) do
		local x, z, r = spot[1], spot[2], spot[3]
		local y = g(x, z)
		emitter(fx, "Pollen", L.wcf(x, y + 40, z), Vector3.new(r * 1.6, 90, r * 1.6), {
			color = Color3.fromRGB(240, 240, 205), texture = SPARK,
			rate = 9, size = 1.5, life = 14, speed = 0.7, alpha = 0.4,
			accel = Vector3.new(0.4, 0.1, 0.2), lightEmission = 0.55,
		})
		counts.pollen = counts.pollen + 1
	end

	----------------------------------------------------------------- falling leaves
	for i = 1, 14 do
		local a = rng:NextNumber(0, 6.283)
		local r = rng:NextNumber(200, 950)
		local x, z = math.cos(a) * r, math.sin(a) * r
		local ch = F.ceiling(x, z)
		local y = F.ground(x, z, ch)
		if y > F.WATER + 3 and ch > y + 60 then
			emitter(fx, "FallingLeaves", L.wcf(x, y + 55, z), Vector3.new(180, 30, 180), {
				color = rng:NextNumber() < 0.5 and L.C.LeafPale or L.C.Leaf, texture = SPARK,
				rate = 3, size = 2.2, life = 12, speed = 0.5, alpha = 0.25,
				accel = Vector3.new(0.6, -1.4, 0.3), lightEmission = 0.1, drag = 2.2,
			})
			counts.leaves = counts.leaves + 1
		end
	end

	----------------------------------------------------------------- fungal spores
	for i = 1, 5 do
		local a = rng:NextNumber(0, 6.283)
		local r = rng:NextNumber(0, 220)
		local x, z = F.FUNGAL.X + math.cos(a) * r, F.FUNGAL.Y + math.sin(a) * r
		emitter(fx, "Spores", L.wcf(x, g(x, z) + 24, z), Vector3.new(150, 60, 150), {
			color = L.C.GlowCyan, rate = 6, size = 1.8, life = 16, speed = 0.5, alpha = 0.3,
			accel = Vector3.new(0, 0.6, 0), lightEmission = 0.8,
		})
		counts.spores = counts.spores + 1
	end

	----------------------------------------------------------------- wildlife
	local FUR = {
		deer   = {Color3.fromRGB(150, 106, 68),  Color3.fromRGB(224, 214, 196)},
		stag   = {Color3.fromRGB(126, 88, 56),   Color3.fromRGB(210, 198, 178)},
		rabbit = {Color3.fromRGB(186, 176, 162), Color3.fromRGB(238, 234, 228)},
		wolf   = {Color3.fromRGB(112, 114, 118), Color3.fromRGB(196, 198, 200)},
		cat    = {Color3.fromRGB(96, 88, 84),    Color3.fromRGB(196, 172, 120)},
		owl    = {Color3.fromRGB(138, 112, 82),  Color3.fromRGB(226, 214, 190)},
	}
	local spots = {
		{-560, 520, "deer", 0.42}, {-520, 470, "deer", 0.36}, {-600, 560, "deer", 0.30},
		{620, 180, "stag", 0.50}, {430, -120, "deer", 0.40},
		{-260, 120, "rabbit", 0.16}, {-230, 90, "rabbit", 0.14}, {180, -60, "rabbit", 0.15},
		{-820, -220, "wolf", 0.44}, {-780, -170, "wolf", 0.40},
		{980, 300, "cat", 0.34}, {-1000, 760, "cat", 0.30},
		{760, 720, "deer", 0.38}, {-380, 900, "stag", 0.46},
		{240, 640, "owl", 0.5}, {-660, -640, "owl", 0.5}, {900, -180, "owl", 0.5},
	}
	for i, s in ipairs(spots) do
		local x, z, kind, scale = s[1], s[2], s[3], s[4]
		local ch = F.ceiling(x, z)
		local y = F.ground(x, z, ch)
		if y > F.WATER + 2 and ch > y + 30 then
			local cf = L.wcf(x, y, z) * CFrame.Angles(0, rng:NextNumber(0, 6.283), 0)
			local mo
			if kind == "owl" then
				-- owls perch: give them a stump to sit on
				L.post(life, "Perch", L.wcf(x, y + 5, z), 10, 3.2, L.C.Bark, Enum.Material.Wood, {solid = true})
				mo = C.owl(life, L.wcf(x, y + 10, z) * CFrame.Angles(0, rng:NextNumber(0, 6.283), 0), scale,
					{seed = i, eyeGlow = L.C.GlowGold})
			elseif kind == "rabbit" then
				mo = C.quadruped(life, cf, scale, {style = "cat", seed = i, antlers = false})
			else
				mo = C.quadruped(life, cf, scale, {style = kind == "stag" and "stag" or (kind == "wolf" and "wolf" or (kind == "cat" and "cat" or "doe")), seed = i})
			end
			mo.Name = kind:sub(1, 1):upper() .. kind:sub(2)
			local fur = FUR[kind]
			liven(mo, fur[1], fur[2])
			counts.animals = counts.animals + 1
		end
	end

	----------------------------------------------------------------- butterflies
	for i = 1, 8 do
		local a = rng:NextNumber(0, 6.283)
		local r = rng:NextNumber(150, 900)
		local x, z = math.cos(a) * r, math.sin(a) * r
		local y = F.ground(x, z, F.ceiling(x, z))
		if y > F.WATER + 3 then
			emitter(fx, "Butterflies", L.wcf(x, y + 10, z), Vector3.new(90, 20, 90), {
				color = ({L.C.GlowPink, L.C.GlowGold, L.C.GlowCyan})[rng:NextInteger(1, 3)],
				rate = 3, size = 1.7, life = 9, speed = 2.2, alpha = 0.15,
				accel = Vector3.new(0, 0.5, 0), drag = 1.8,
			})
		end
	end

	local parts = 0
	for _, f in ipairs({life, fx}) do
		for _, d in ipairs(f:GetDescendants()) do if d:IsA("BasePart") then parts = parts + 1 end end
	end
	return string.format("Life: %d firefly swarms, %d pollen fields, %d leaf-fall zones, %d spore clouds, %d animals -- %d parts",
		counts.fireflies, counts.pollen, counts.leaves, counts.spores, counts.animals, parts)
end

return M
