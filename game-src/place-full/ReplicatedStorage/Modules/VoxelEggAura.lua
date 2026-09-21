-- Per-egg aura. Two builders, because the two surfaces have opposite capabilities:
--   buildWorld    -- stall / open world. ParticleEmitter + PointLight are fine here.
--   buildViewport -- the hatch ViewportFrame, which draws BaseParts ONLY. No
--                    ParticleEmitter, no Trail, no Beam, no Light -- a PointLight
--                    parented into that viewport "drew nothing, ever". So the
--                    viewport aura is moving PARTS or it does not exist.
-- Shapes ported from the Blender previz (egg_set.py). Everything is CUBES so the
-- aura stays in the game's voxel language.
local M = {}

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

-- proportions are fractions of the egg's HEIGHT, so one table serves every scale
-- kind         width           height          taper
M.GROWTH = {
	spike   = { {0.025, 0.049}, {0.057, 0.292}, 0.62 },
	tuft    = { {0.032, 0.062}, {0.057, 0.166}, 0.42 },
	reed    = { {0.012, 0.022}, {0.160, 0.406}, 0.15 },
	thorn   = { {0.017, 0.036}, {0.079, 0.292}, 0.86 },
	root    = { {0.049, 0.094}, {0.023, 0.068}, 0.10 },
	plate   = { {0.064, 0.128}, {0.015, 0.045}, 0.05 },
	curtain = { {0.017, 0.032}, {0.283, 0.623}, 0.12 },
}

local function part(parent, name, size, cf, colour, neon)
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color = name, size, cf, colour
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.CastShadow = false
	p.Material = neon and Enum.Material.Neon or Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Stepped, tapered columns erupting from the ground. This is the effect that
-- actually reads as elemental: floating specks say "dust", geometry coming out of
-- the floor says the egg is DOING something.
function M.growth(parent, spec, H, seed, count)
	local g = M.GROWTH[spec.aura.growth] or M.GROWTH.spike
	local rng = Random.new(seed or 1)
	local n = count or 34
	local made = 0
	for i = 1, n do
		-- STRATIFIED angle: uniform random clumps them into a wall on one side
		local ang = (i + rng:NextNumber(0.15, 0.85)) / n * math.pi * 2
		local rad = H * (0.41 + (rng:NextNumber() ^ 0.7) * 0.55)
		local near = math.max(0, 1 - (rad / H - 0.41) / 0.55)
		local w = H * rng:NextNumber(g[1][1], g[1][2])
		local tall = H * (g[2][1] + near * (g[2][2] - g[2][1])) * rng:NextNumber(0.55, 1.25)
		-- CAPPED. Uncapped this is tall/width, which is fine for a fat spike but
		-- explodes on thin tall kinds: reeds hit 451 parts and curtains 525 --
		-- more aura than egg. Past ~5 steps the taper reads the same anyway.
		local steps = math.clamp(math.floor(tall / math.max(w, 0.02)), 1, 5)
		for k = 0, steps - 1 do
			local f = k / math.max(1, steps)
			local sw = w * (1 - g[3] * f)
			local sh = tall / steps
			-- NOT Neon. In Blender's dark studio the growth was emissive and read as
			-- ice; under this game's daylight Neon turns every column into a glowing
			-- light-stick, and the world already carries ~9,200 Neon parts. The
			-- PointLight carries the glow instead. Only the top step of a tier 4-5
			-- egg gets a lit tip, so rarity still reads without a forest of lamps.
			local lit = (spec.tier or 1) >= 4 and k == steps - 1
			part(parent, "aura_" .. spec.aura.growth .. "_" .. i .. "_" .. k,
				Vector3.new(sw, sh * 1.02, sw),
				CFrame.new(math.cos(ang) * rad, (k + 0.5) * sh, math.sin(ang) * rad),
				spec.aura.gcol, lit)
			made += 1
		end
	end
	return made
end

-- Full aura for the open world. Returns a Model to be positioned at the egg's BASE.
function M.buildWorld(spec, H, seed)
	local model = Instance.new("Model")
	model.Name = (spec.name or "Egg") .. "_Aura"
	M.growth(model, spec, H, seed, 34)

	local hub = part(model, "AuraHub", Vector3.new(0.2, 0.2, 0.2),
		CFrame.new(0, H * 0.45, 0), spec.aura.mote, false)
	hub.Transparency = 1
	local att = Instance.new("Attachment"); att.Parent = hub

	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARK          -- only sparkles_main and smoke_main resolve in this place
	e.Color = ColorSequence.new(spec.aura.mote)
	e.Size = NumberSequence.new(H * 0.055)
	e.Lifetime = NumberRange.new(1.6, 2.8)
	e.Rate = 6 + (spec.tier or 1) * 4
	e.Speed = NumberRange.new(0.4, 1.1)
	e.SpreadAngle = Vector2.new(35, 35)
	e.Acceleration = Vector3.new(0, 1.1, 0)
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.25),
		NumberSequenceKeypoint.new(0.8, 0.35), NumberSequenceKeypoint.new(1, 1),
	})
	e.LightEmission = 0.6
	e.Parent = att

	local l = Instance.new("PointLight")
	l.Color = spec.aura.glow
	l.Brightness = 1.1 + (spec.tier or 1) * 0.35
	l.Range = H * 2.2
	l.Shadows = false
	l.Parent = hub

	model.PrimaryPart = hub
	return model
end

-- Viewport aura: motes as PARTS, since nothing else renders there. Returns the
-- parts plus their orbit parameters; the caller drives them per frame.
function M.buildViewport(spec, H, seed, count)
	local rng = Random.new(seed or 2)
	local folder = Instance.new("Model")
	folder.Name = (spec.name or "Egg") .. "_AuraVP"
	local motes = {}
	for i = 1, (count or 18) do
		local s = H * rng:NextNumber(0.012, 0.026)
		local p = part(folder, "mote_" .. i, Vector3.new(s, s, s), CFrame.new(), spec.aura.mote, true)
		-- born invisible AT THE ORIGIN. stepViewport is what places and fades them
		-- in, and it only runs once the egg is ready -- until then an opaque mote
		-- would sit in a clump at the centre of the stage.
		p.Transparency = 1
		motes[#motes + 1] = {
			part = p,
			rad = H * rng:NextNumber(0.42, 0.72),
			y0 = H * rng:NextNumber(-0.35, 0.45),
			spd = rng:NextNumber(0.25, 0.75) * (rng:NextNumber() < 0.5 and -1 or 1),
			ph = rng:NextNumber(0, math.pi * 2),
			rise = rng:NextNumber(0.10, 0.28),
		}
	end
	return folder, motes
end

-- one frame of viewport-mote motion; `lit` 0..1 fades them in with the ceremony
function M.stepViewport(motes, t, H, lit)
	for _, mo in ipairs(motes) do
		local a = mo.ph + t * mo.spd
		local y = mo.y0 + ((t * mo.rise + mo.ph) % (H * 0.9)) - H * 0.35
		mo.part.CFrame = CFrame.new(math.cos(a) * mo.rad, y, math.sin(a) * mo.rad)
		mo.part.Transparency = 1 - math.clamp(lit, 0, 1) * 0.85
	end
end

return M
