--!strict
-- EggArt: the ONE recipe per egg, and the builders that turn it into
--   * a display model (shop card viewport, stall shelf, season/daily reward tiles), and
--   * a hatch rig (the same egg, plus crack anchors, burst fragments and a light core)
-- so the egg a player buys, the egg on the shelf and the egg that cracks open are the
-- same object. Replaces the 350-450 part voxel lattices (VoxelEgg) that gave every
-- egg the same silhouette and left colour as the only identity.
--
-- DESIGN RULES (egg-hatch overhaul, 2026-09-21):
--   * silhouette first -- each recipe changes the PROFILE (squat / tall / tapered) and
--     adds one or two shape features (cap, band, straps, spikes, crown, antlers, window)
--     that read from several studs away with no text and with bloom off;
--   * materials do the texture work (Grass, Wood, Slate, Ice, Snow, Metal, Glass);
--   * at most TWO neon parts per egg, both small -- glow is an accent, never the identity;
--   * 14-34 parts per egg, collisions/queries off on everything, shared per-egg cache.
--
-- Egg space: origin at the shell centre, +Y up, +Z is the FRONT (the side that faces
-- the camera in the hatch and the shelf edge on the stall). Recipes are authored at a
-- canonical height (`CANON_H` studs); build() scales the finished model to any height.

local M = {}

local CANON_H = 2.0
M.CANON_H = CANON_H

export type Ellipsoid = { cy: number, rx: number, ry: number, colour: Color3, material: Enum.Material }
export type Recipe = {
	key: string, name: string, world: string, tier: number,
	base: Color3, accent: Color3, dark: Color3, glow: Color3,
	material: Enum.Material,
	shells: { Ellipsoid },          -- 1-2 overlapping ellipsoids = the silhouette
	deco: { { any } },              -- decoration ops, see OPS below
	seed: number,
}

local function C(r: number, g: number, b: number): Color3 return Color3.fromRGB(r, g, b) end
local function mul(c: Color3, f: number): Color3
	return Color3.new(math.clamp(c.R * f, 0, 1), math.clamp(c.G * f, 0, 1), math.clamp(c.B * f, 0, 1))
end
M.mul = mul

-- ====================================================================== recipes
-- Ten eggs, two worlds. `shells` are (centre y, x radius, y radius) in canonical units
-- where the whole egg is ~2 tall; the max over the shells is the silhouette.
local R: { [string]: Recipe } = {}

R.ForestEgg1 = {
	key = "ForestEgg1", name = "Mossy Egg", world = "Forest", tier = 1, seed = 101,
	base = C(176, 198, 138), accent = C(96, 150, 72), dark = C(70, 104, 54), glow = C(150, 235, 110),
	material = Enum.Material.SmoothPlastic,
	-- squat, wide-based egg: the classic "sat in the grass" shape
	shells = { { cy = -0.05, rx = 0.80, ry = 0.92, colour = C(176, 198, 138), material = Enum.Material.SmoothPlastic } },
	deco = {
		{ "cap", C(96, 150, 72), Enum.Material.Grass, 0.40, 0.16 },          -- moss hood draping over the top third
		{ "sprouts", C(120, 190, 84), 3, 0.78 },                             -- little leaf stalks out of the moss
		{ "dots", C(150, 172, 112), 7, 0.14, -0.55, 0.30 },                  -- dark speckles low on the shell
		{ "pebbles", C(196, 180, 132), 3, 0.16, -0.72 },                     -- pebbles it sits among
	},
}

R.ForestEgg2 = {
	key = "ForestEgg2", name = "Reedwater Egg", world = "Forest", tier = 2, seed = 102,
	base = C(146, 200, 196), accent = C(72, 150, 140), dark = C(50, 104, 100), glow = C(120, 240, 236),
	material = Enum.Material.SmoothPlastic,
	-- tall and slim, sitting low in water
	shells = { { cy = 0.02, rx = 0.66, ry = 1.00, colour = C(146, 200, 196), material = Enum.Material.SmoothPlastic } },
	deco = {
		{ "band", C(72, 150, 140), Enum.Material.SmoothPlastic, -0.30, 0.10, 0.07 },   -- the waterline
		{ "ripple", C(190, 232, 236), -0.36, 0.05 },                               -- pale ring just under it
		{ "reeds", C(96, 158, 96), C(120, 92, 56), 3 },                            -- reed stalks with cattails
		{ "droplets", C(210, 240, 244), 5, 0.10, 0.10, 0.75 },                     -- droplet bumps high up
	},
}

R.ForestEgg3 = {
	key = "ForestEgg3", name = "Bramble Egg", world = "Forest", tier = 3, seed = 103,
	base = C(168, 128, 92), accent = C(104, 74, 48), dark = C(70, 48, 30), glow = C(255, 160, 70),
	material = Enum.Material.Wood,
	shells = { { cy = 0.00, rx = 0.74, ry = 0.98, colour = C(168, 128, 92), material = Enum.Material.Wood } },
	deco = {
		{ "strap", C(96, 70, 44), 0.55, 0.11, 12, 0.00 },     -- two crossing bramble straps
		{ "strap", C(96, 70, 44), -0.55, 0.11, 12, 1.05 },
		{ "thorns", C(232, 208, 160), 6, 0.30, 0.16 },        -- pale thorns on the straps
		{ "dots", C(120, 86, 56), 6, 0.10, -0.6, 0.6 },       -- bark knots
	},
}

R.ForestEgg4 = {
	key = "ForestEgg4", name = "Hollow Egg", world = "Forest", tier = 4, seed = 104,
	base = C(172, 168, 184), accent = C(118, 96, 160), dark = C(58, 50, 78), glow = C(190, 130, 255),
	material = Enum.Material.Slate,
	-- tapered top: a second, narrower ellipsoid pushed up gives the pointed egg
	shells = {
		{ cy = -0.18, rx = 0.78, ry = 0.82, colour = C(172, 168, 184), material = Enum.Material.Slate },
		{ cy = 0.18, rx = 0.60, ry = 0.82, colour = C(172, 168, 184), material = Enum.Material.Slate },
	},
	deco = {
		{ "window", C(40, 32, 58), C(190, 130, 255), 0.05, 0.42, 0.30 },  -- dark hollow with a violet core
		{ "crown", C(140, 126, 168), 5, -0.62, 0.36, 0.15 },               -- stone shards rising round the base
		{ "wisps", C(210, 190, 250), 2 },                                  -- two pale wisps drifting off the top
		{ "dots", C(118, 96, 160), 5, 0.09, -0.2, 0.7 },                   -- violet flecks
	},
}

R.ForestEgg5 = {
	key = "ForestEgg5", name = "Heartwood Egg", world = "Forest", tier = 5, seed = 105,
	base = C(160, 96, 72), accent = C(96, 52, 36), dark = C(60, 30, 20), glow = C(255, 150, 60),
	material = Enum.Material.WoodPlanks,
	shells = { { cy = 0.00, rx = 0.82, ry = 1.00, colour = C(160, 96, 72), material = Enum.Material.WoodPlanks } },
	deco = {
		{ "plates", C(112, 64, 44), Enum.Material.Wood, 6, 0.42, 0.34, 0.06 },  -- bark plates around the middle
		{ "antlers", C(226, 196, 142), 2 },                                     -- blocky antlers off the top
		{ "veins", C(255, 150, 60), 3, 0.30 },                                  -- amber grain (neon, thin)
		{ "band", C(96, 52, 36), Enum.Material.Wood, -0.62, 0.09, 0.05 },       -- root collar at the base
	},
}

R.TundraEgg1 = {
	key = "TundraEgg1", name = "Frostcap Egg", world = "Tundra", tier = 1, seed = 201,
	base = C(122, 160, 198), accent = C(236, 244, 252), dark = C(70, 100, 140), glow = C(150, 210, 255),
	material = Enum.Material.SmoothPlastic,
	shells = { { cy = -0.04, rx = 0.78, ry = 0.94, colour = C(122, 160, 198), material = Enum.Material.SmoothPlastic } },
	deco = {
		{ "cap", C(236, 244, 252), Enum.Material.Snow, 0.34, 0.10 },   -- snow cap
		{ "icicles", C(214, 236, 252), 4, 0.36 },                       -- icicles hanging off the cap rim
		{ "dots", C(96, 134, 176), 6, 0.11, -0.6, 0.2 },                -- frost speckle
	},
}

R.TundraEgg2 = {
	key = "TundraEgg2", name = "Rimeplate Egg", world = "Tundra", tier = 2, seed = 202,
	base = C(150, 160, 170), accent = C(96, 104, 116), dark = C(56, 62, 72), glow = C(200, 220, 240),
	material = Enum.Material.Metal,
	-- barrel-ish: wide, slightly flattened top
	shells = { { cy = 0.00, rx = 0.76, ry = 0.94, colour = C(150, 160, 170), material = Enum.Material.Metal } },
	deco = {
		{ "band", C(96, 104, 116), Enum.Material.Metal, 0.42, 0.11, 0.07 },   -- three riveted bands
		{ "band", C(96, 104, 116), Enum.Material.Metal, 0.00, 0.13, 0.08 },
		{ "band", C(96, 104, 116), Enum.Material.Metal, -0.42, 0.11, 0.07 },
		{ "rivets", C(210, 216, 224), 8, 0.00, 0.08 },                        -- rivets on the middle band
		{ "rivets", C(210, 216, 224), 6, 0.42, 0.07 },
	},
}

R.TundraEgg3 = {
	key = "TundraEgg3", name = "Whiteout Egg", world = "Tundra", tier = 3, seed = 203,
	base = C(240, 244, 248), accent = C(190, 206, 224), dark = C(150, 168, 190), glow = C(220, 240, 255),
	material = Enum.Material.Snow,
	shells = { { cy = -0.02, rx = 0.80, ry = 0.90, colour = C(240, 244, 248), material = Enum.Material.Snow } },
	deco = {
		{ "ring", C(214, 226, 240), Enum.Material.Ice, 10, 1.22, 0.18, 24 },  -- a tilted storm ring of ice cubes
		{ "dots", C(200, 214, 230), 8, 0.12, -0.6, 0.6 },                    -- drift flecks
	},
}

R.TundraEgg4 = {
	key = "TundraEgg4", name = "Aurora Egg", world = "Tundra", tier = 4, seed = 204,
	base = C(150, 132, 210), accent = C(120, 240, 190), dark = C(70, 56, 120), glow = C(120, 250, 200),
	material = Enum.Material.Glass,
	shells = {
		{ cy = -0.16, rx = 0.74, ry = 0.84, colour = C(150, 132, 210), material = Enum.Material.Glass },
		{ cy = 0.22, rx = 0.56, ry = 0.80, colour = C(150, 132, 210), material = Enum.Material.Glass },
	},
	deco = {
		{ "ribbons", C(120, 240, 190), C(230, 120, 220), 4, 0.05 },   -- vertical aurora ribbons (2 neon, 2 plastic)
		{ "crystals", C(196, 230, 250), 3, 0.92, 0.38 },              -- crystal crown on the point
	},
}

R.TundraEgg5 = {
	key = "TundraEgg5", name = "Frostheart Egg", world = "Tundra", tier = 5, seed = 205,
	base = C(70, 110, 180), accent = C(40, 70, 130), dark = C(26, 44, 88), glow = C(80, 170, 255),
	material = Enum.Material.Ice,
	shells = { { cy = 0.02, rx = 0.82, ry = 1.00, colour = C(70, 110, 180), material = Enum.Material.Ice } },
	deco = {
		{ "window", C(24, 40, 80), C(80, 170, 255), 0.00, 0.36, 0.34 },  -- the frozen heart, lit from within
		{ "crown", C(160, 200, 240), 6, -0.66, 0.44, 0.18 },              -- ice spikes rising from the base
		{ "band", C(40, 70, 130), Enum.Material.Ice, -0.70, 0.09, 0.06 },
		{ "dots", C(120, 170, 230), 5, 0.10, 0.1, 0.7 },
	},
}

M.Recipes = R

function M.recipe(key: string): Recipe?
	return R[key]
end

-- ====================================================================== geometry
-- radius of the silhouette at height y, and which shell owns it
local function radiusAt(recipe: Recipe, y: number): (number, Ellipsoid?)
	local best, owner = 0, nil
	for _, e in ipairs(recipe.shells) do
		local ny = (y - e.cy) / e.ry
		if math.abs(ny) < 1 then
			local r = e.rx * math.sqrt(1 - ny * ny)
			if r > best then best, owner = r, e end
		end
	end
	return best, owner
end
M.radiusAt = radiusAt

local function topOf(recipe: Recipe): number
	local t = -math.huge
	for _, e in ipairs(recipe.shells) do t = math.max(t, e.cy + e.ry) end
	return t
end
local function bottomOf(recipe: Recipe): number
	local b = math.huge
	for _, e in ipairs(recipe.shells) do b = math.min(b, e.cy - e.ry) end
	return b
end
M.topOf, M.bottomOf = topOf, bottomOf

-- outward normal at a surface point (theta around Y from +Z, height y)
local function normalAt(recipe: Recipe, theta: number, y: number): Vector3
	local r, e = radiusAt(recipe, y)
	if not e or r <= 1e-4 then return Vector3.yAxis end
	local x, z = r * math.sin(theta), r * math.cos(theta)
	local n = Vector3.new(x / (e.rx * e.rx), (y - e.cy) / (e.ry * e.ry), z / (e.rx * e.rx))
	if n.Magnitude < 1e-5 then return Vector3.yAxis end
	return n.Unit
end

-- a CFrame sitting ON the surface with its +Y along the outward normal
local function frameOn(recipe: Recipe, theta: number, y: number, protrude: number): CFrame
	local r = radiusAt(recipe, y)
	local n = normalAt(recipe, theta, y)
	local pos = Vector3.new(r * math.sin(theta), y, r * math.cos(theta)) + n * protrude
	local ref = (math.abs(n.Y) > 0.9) and Vector3.zAxis or Vector3.yAxis
	local right = n:Cross(ref).Unit
	local back = right:Cross(n).Unit
	return CFrame.fromMatrix(pos, right, n, back)
end
M.frameOn = frameOn

-- ====================================================================== part factory
type Ctx = {
	recipe: Recipe, model: Model, rng: Random, parts: { BasePart },
	families: { [BasePart]: string }, neon: number,
}

-- shape: nil/Block, Enum.PartType.Cylinder, or the string "ellipsoid". A Ball part is
-- always a true sphere (its diameter is the smallest axis), so a stretched egg body is a
-- Block carrying a SpecialMesh Sphere, which does scale with the part's Size.
local function mk(ctx: Ctx, family: string, size: Vector3, cf: CFrame, colour: Color3, material: Enum.Material?, shape: any): Part
	local p = Instance.new("Part")
	p.Name = family .. "_" .. (#ctx.parts + 1)
	if shape == "ellipsoid" then
		p.Shape = Enum.PartType.Block
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	else
		p.Shape = shape or Enum.PartType.Block
	end
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = material or Enum.Material.SmoothPlastic
	if p.Material == Enum.Material.Neon then ctx.neon += 1 end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = ctx.model
	ctx.parts[#ctx.parts + 1] = p
	ctx.families[p] = family
	return p
end

local function wedge(ctx: Ctx, family: string, size: Vector3, cf: CFrame, colour: Color3, material: Enum.Material?): WedgePart
	local p = Instance.new("WedgePart")
	p.Name = family .. "_" .. (#ctx.parts + 1)
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = ctx.model
	ctx.parts[#ctx.parts + 1] = p
	ctx.families[p] = family
	return p
end

-- ====================================================================== decoration ops
local OPS: { [string]: (ctx: Ctx, args: { any }) -> () } = {}

-- a flattened ball sitting on top of the egg, draping `drape` below the crown
OPS.cap = function(ctx, a)
	local colour, material, frac, drape = a[2], a[3], a[4], a[5]
	local rec = ctx.recipe
	local top = topOf(rec)
	local yCut = top - (top - bottomOf(rec)) * frac
	-- a flattened ball whose equator sits on the cut line: it hugs the shell there, rises
	-- `drape` above the crown and hangs `drape` below the cut -- a hood, not a snowman head
	local r = radiusAt(rec, yCut) + 0.05
	local h = (top - yCut) + drape * 2
	mk(ctx, "cap", Vector3.new(r * 2 + 0.06, h, r * 2 + 0.06), CFrame.new(0, (top + yCut) * 0.5, 0), colour, material, "ellipsoid")
end

-- a horizontal disc ring at height y (fraction of the half height), poking out `out`
OPS.band = function(ctx, a)
	local colour, material, yf, thick, out = a[2], a[3], a[4], a[5], a[6]
	local rec = ctx.recipe
	local y = yf * (topOf(rec) - bottomOf(rec)) * 0.5 + (topOf(rec) + bottomOf(rec)) * 0.5
	local r = radiusAt(rec, y) + out
	-- a Cylinder part's axis is X; stand it up so the disc lies flat
	mk(ctx, "band", Vector3.new(thick, r * 2, r * 2), CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2), colour, material, Enum.PartType.Cylinder)
end

OPS.ripple = function(ctx, a)
	local colour, yf, thick = a[2], a[3], a[4]
	local rec = ctx.recipe
	local y = yf * (topOf(rec) - bottomOf(rec)) * 0.5 + (topOf(rec) + bottomOf(rec)) * 0.5
	local r = radiusAt(rec, y) + 0.16
	mk(ctx, "ripple", Vector3.new(thick, r * 2, r * 2), CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2), colour, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
end

-- small half-buried cubes scattered on the surface between two heights
OPS.dots = function(ctx, a)
	local colour, n, size, y0, y1 = a[2], a[3], a[4], a[5], a[6]
	local rec = ctx.recipe
	for i = 1, n do
		local th = ctx.rng:NextNumber(0, math.pi * 2)
		local y = ctx.rng:NextNumber(y0, y1)
		local s = size * ctx.rng:NextNumber(0.8, 1.2)
		mk(ctx, "dot", Vector3.new(s, s, s), frameOn(rec, th, y, -s * 0.35), colour)
	end
end

OPS.pebbles = function(ctx, a)
	local colour, n, size, y = a[2], a[3], a[4], a[5]
	local rec = ctx.recipe
	for i = 1, n do
		local th = (i - 0.5) / n * math.pi * 2 + ctx.rng:NextNumber(-0.4, 0.4)
		local r = radiusAt(rec, y) + 0.10 + ctx.rng:NextNumber(0, 0.14)
		local s = size * ctx.rng:NextNumber(0.8, 1.25)
		mk(ctx, "pebble", Vector3.new(s * 1.2, s * 0.8, s), CFrame.new(r * math.sin(th), bottomOf(rec) + s * 0.35, r * math.cos(th)) * CFrame.Angles(0, th, 0), colour)
	end
end

-- leaf stalks sprouting from the cap
OPS.sprouts = function(ctx, a)
	local colour, n, y = a[2], a[3], a[4]
	local rec = ctx.recipe
	for i = 1, n do
		local th = (i - 0.5) / n * math.pi * 2 + ctx.rng:NextNumber(-0.5, 0.5)
		local base = frameOn(rec, th, y, 0.04)
		local lean = CFrame.Angles(ctx.rng:NextNumber(-0.3, 0.3), 0, ctx.rng:NextNumber(-0.3, 0.3))
		local stalk = base * lean * CFrame.new(0, 0.16, 0)
		mk(ctx, "sprout", Vector3.new(0.06, 0.32, 0.06), stalk, mul(colour, 0.8))
		mk(ctx, "sprout", Vector3.new(0.20, 0.08, 0.12), stalk * CFrame.new(0.08, 0.16, 0) * CFrame.Angles(0, 0, -0.5), colour)
		mk(ctx, "sprout", Vector3.new(0.20, 0.08, 0.12), stalk * CFrame.new(-0.08, 0.20, 0) * CFrame.Angles(0, 0, 0.5), colour)
	end
end

-- reed stalks standing beside the egg, leaning off the back-left
OPS.reeds = function(ctx, a)
	local stalk, head, n = a[2], a[3], a[4]
	local rec = ctx.recipe
	local b = bottomOf(rec)
	for i = 1, n do
		local th = math.rad(125) + (i - 1) * math.rad(34)
		local r = radiusAt(rec, b + 0.35) + 0.16
		local h = 2.0 + i * 0.26
		local x, z = r * math.sin(th), r * math.cos(th)
		local cf = CFrame.new(x, b + h / 2 + 0.05, z) * CFrame.Angles(0, 0, math.rad(-8 + i * 5))
		mk(ctx, "reed", Vector3.new(0.07, h, 0.07), cf, stalk)
		mk(ctx, "reed", Vector3.new(0.16, 0.34, 0.16), cf * CFrame.new(0, h / 2 - 0.12, 0), head)
	end
end

OPS.droplets = function(ctx, a)
	local colour, n, size, y0, y1 = a[2], a[3], a[4], a[5], a[6]
	local rec = ctx.recipe
	for i = 1, n do
		local th = ctx.rng:NextNumber(-1.4, 1.4)   -- front half only
		local y = ctx.rng:NextNumber(y0, y1)
		local s = size * ctx.rng:NextNumber(0.8, 1.3)
		mk(ctx, "droplet", Vector3.new(s, s * 1.3, s), frameOn(rec, th, y, s * 0.1), colour, Enum.Material.SmoothPlastic, "ellipsoid")
	end
end

-- a tilted ring of box segments hugging the shell: the bramble straps
OPS.strap = function(ctx, a)
	local colour, tilt, thick, segs, phase = a[2], a[3], a[4], a[5], a[6]
	local rec = ctx.recipe
	local ry = (topOf(rec) - bottomOf(rec)) * 0.5
	local cy = (topOf(rec) + bottomOf(rec)) * 0.5
	for i = 1, segs do
		local t = (i - 0.5) / segs * math.pi * 2 + phase
		local y = cy + math.sin(t) * ry * 0.72 * tilt
		local th = t
		local cf = frameOn(rec, th, y, thick * 0.3)
		-- run the box along the ring direction: rotate about the normal so its X axis follows the path
		local nextY = cy + math.sin(t + 0.05) * ry * 0.72 * tilt
		local p1, p2 = frameOn(rec, th, y, 0).Position, frameOn(rec, th + 0.05, nextY, 0).Position
		local dir = (p2 - p1)
		local len = radiusAt(rec, y) * math.pi * 2 / segs * 1.12
		if dir.Magnitude > 1e-4 then
			local up = cf.UpVector
			local tangent = dir - up * dir:Dot(up)
			if tangent.Magnitude > 1e-4 then
				local right = tangent.Unit
				local back = right:Cross(up).Unit
				cf = CFrame.fromMatrix(cf.Position, right, up, back)
			end
		end
		mk(ctx, "strap", Vector3.new(len, thick, thick * 1.4), cf, colour)
	end
end

-- pale thorns sticking out of the straps
OPS.thorns = function(ctx, a)
	local colour, n, len, base = a[2], a[3], a[4], a[5]
	local rec = ctx.recipe
	for i = 1, n do
		local th = (i - 0.5) / n * math.pi * 2 + 0.3
		local y = math.sin(th * 1.0) * 0.5
		local cf = frameOn(rec, th, y, 0.02)
		mk(ctx, "thorn", Vector3.new(base, len, base), cf * CFrame.new(0, len / 2, 0), colour)
		mk(ctx, "thorn", Vector3.new(base * 0.5, len * 0.5, base * 0.5), cf * CFrame.new(0, len + len * 0.22, 0), colour)
	end
end

-- a dark inset disc on the front with a glowing neon core behind it
OPS.window = function(ctx, a)
	local dark, glow, y, size, depth = a[2], a[3], a[4], a[5], a[6]
	local rec = ctx.recipe
	local cf = frameOn(rec, 0, y, -depth * 0.35)
	-- the hole: a dark ellipsoid sunk into the shell
	mk(ctx, "window", Vector3.new(size * 1.15, size * 1.3, depth * 1.6), cf, dark, Enum.Material.SmoothPlastic, "ellipsoid")
	-- the core: a small neon ball sitting in the mouth of the hole (one of the two neon parts allowed)
	mk(ctx, "glowcore", Vector3.new(size * 0.46, size * 0.52, size * 0.30), cf * CFrame.new(0, depth * 0.30, 0), glow, Enum.Material.Neon, "ellipsoid")
end

-- blocky shards/spikes rising from a ring around the base
OPS.crown = function(ctx, a)
	local colour, n, y, len, base = a[2], a[3], a[4], a[5], a[6]
	local rec = ctx.recipe
	local yy = y * (topOf(rec) - bottomOf(rec)) * 0.5 + (topOf(rec) + bottomOf(rec)) * 0.5
	for i = 1, n do
		local th = (i - 0.5) / n * math.pi * 2 + 0.2
		local r = radiusAt(rec, yy) + 0.05
		-- leaning OUT from the shell, roots buried in it: a rim of shards, not a set of legs
		local lean = CFrame.Angles(0, th, 0) * CFrame.Angles(math.rad(-34), 0, 0)
		local cf = CFrame.new(r * math.sin(th), yy + len * 0.30, r * math.cos(th)) * lean
		mk(ctx, "crown", Vector3.new(base, len, base), cf, colour)
		mk(ctx, "crown", Vector3.new(base * 0.55, len * 0.55, base * 0.55), cf * CFrame.new(0, len * 0.72, 0), colour)
	end
end

-- small pale ellipsoids hovering off the crown (the Hollow egg's ghost wisps)
OPS.wisps = function(ctx, a)
	local colour, n = a[2], a[3]
	local rec = ctx.recipe
	local top = topOf(rec)
	for i = 1, n do
		local side = (i % 2 == 0) and 1 or -1
		local cf = CFrame.new(side * 0.30, top + 0.12 + i * 0.10, 0.12 - i * 0.10)
		mk(ctx, "wisp", Vector3.new(0.26, 0.16, 0.22), cf, colour, Enum.Material.SmoothPlastic, "ellipsoid")
	end
end

-- flat plates lying on the shell around a band of heights
OPS.plates = function(ctx, a)
	local colour, material, n, size, y, protrude = a[2], a[3], a[4], a[5], a[6], a[7]
	local rec = ctx.recipe
	for i = 1, n do
		local th = (i - 0.5) / n * math.pi * 2
		local yy = (i % 2 == 0) and y or -y * 0.4
		local cf = frameOn(rec, th, yy, protrude)
		mk(ctx, "plate", Vector3.new(size, protrude * 2, size * 0.8), cf, colour, material)
	end
end

-- two blocky antlers off the top, leaning outward
OPS.antlers = function(ctx, a)
	local colour, n = a[2], a[3]
	local rec = ctx.recipe
	local top = topOf(rec)
	for i = 1, n do
		local side = (i == 1) and -1 or 1
		local root = CFrame.new(side * 0.22, top - 0.10, 0.05) * CFrame.Angles(0, 0, side * math.rad(-28))
		mk(ctx, "antler", Vector3.new(0.13, 0.62, 0.13), root * CFrame.new(0, 0.31, 0), colour)
		local fork = root * CFrame.new(0, 0.58, 0)
		mk(ctx, "antler", Vector3.new(0.11, 0.40, 0.11), fork * CFrame.Angles(0, 0, side * math.rad(-40)) * CFrame.new(0, 0.18, 0), colour)
		mk(ctx, "antler", Vector3.new(0.10, 0.34, 0.10), fork * CFrame.Angles(0, 0, side * math.rad(35)) * CFrame.new(0, 0.16, 0), colour)
	end
end

-- thin neon grain lines running up the front (max 2 neon; the third is plastic)
OPS.veins = function(ctx, a)
	local colour, n, len = a[2], a[3], a[4]
	local rec = ctx.recipe
	for i = 1, n do
		local th = (i - (n + 1) / 2) * 0.55
		local y = -0.15 + (i % 2) * 0.25
		local cf = frameOn(rec, th, y, 0.005)
		local neon = ctx.neon < 2
		mk(ctx, "vein", Vector3.new(0.05, 0.012, len), cf * CFrame.Angles(0, math.rad(20 * (i - 2)), 0), colour, neon and Enum.Material.Neon or Enum.Material.SmoothPlastic)
	end
end

-- icicles hanging off the cap rim
OPS.icicles = function(ctx, a)
	local colour, n, yf = a[2], a[3], a[4]
	local rec = ctx.recipe
	local top = topOf(rec)
	local yCut = top - (top - bottomOf(rec)) * yf
	for i = 1, n do
		local th = (i - 0.5) / n * math.pi * 2 + 0.4
		local r = radiusAt(rec, yCut) + 0.05
		local len = 0.22 + ctx.rng:NextNumber(0, 0.2)
		local cf = CFrame.new(r * math.sin(th), yCut - len / 2, r * math.cos(th))
		mk(ctx, "icicle", Vector3.new(0.09, len, 0.09), cf, colour, Enum.Material.Ice)
		mk(ctx, "icicle", Vector3.new(0.05, len * 0.45, 0.05), cf * CFrame.new(0, -len * 0.6, 0), colour, Enum.Material.Ice)
	end
end

OPS.rivets = function(ctx, a)
	local colour, n, yf, size = a[2], a[3], a[4], a[5]
	local rec = ctx.recipe
	local y = yf * (topOf(rec) - bottomOf(rec)) * 0.5 + (topOf(rec) + bottomOf(rec)) * 0.5
	for i = 1, n do
		local th = (i - 0.5) / n * math.pi * 2
		local r = radiusAt(rec, y) + 0.09
		mk(ctx, "rivet", Vector3.new(size, size, size), CFrame.new(r * math.sin(th), y, r * math.cos(th)) * CFrame.Angles(0, th, 0), colour, Enum.Material.Metal)
	end
end

-- a tilted orbit ring of cubes around the egg (Whiteout's storm)
OPS.ring = function(ctx, a)
	local colour, material, n, radius, size, tiltDeg = a[2], a[3], a[4], a[5], a[6], a[7]
	local tilt = CFrame.Angles(math.rad(tiltDeg), 0, math.rad(8))
	for i = 1, n do
		local th = (i - 0.5) / n * math.pi * 2
		local s = size * (0.75 + 0.5 * ((i * 7) % 3) / 2)
		local cf = tilt * CFrame.new(radius * math.sin(th), 0, radius * math.cos(th)) * CFrame.Angles(0, th, 0)
		mk(ctx, "ring", Vector3.new(s, s, s), cf, colour, material)
	end
end

-- vertical ribbons on the shell (aurora): alternate neon / plastic, max two neon
OPS.ribbons = function(ctx, a)
	local c1, c2, n, thick = a[2], a[3], a[4], a[5]
	local rec = ctx.recipe
	for i = 1, n do
		local th = (i - (n + 1) / 2) * 0.62 + 0.1
		local segs = 4
		for s = 1, segs do
			local y0 = -0.55 + (s - 1) * 0.30
			local y1 = y0 + 0.30
			local cfA, cfB = frameOn(rec, th, y0, thick * 0.4), frameOn(rec, th, y1, thick * 0.4)
			local mid = cfA.Position:Lerp(cfB.Position, 0.5)
			local dir = cfB.Position - cfA.Position
			local up = (cfA.UpVector + cfB.UpVector).Unit
			local right = (dir - up * dir:Dot(up)).Unit
			local back = right:Cross(up).Unit
			local colour = (i % 2 == 1) and c1 or c2
			local neon = (i % 2 == 1) and ctx.neon < 2
			mk(ctx, "ribbon", Vector3.new(dir.Magnitude * 1.05, thick, thick * 2.2), CFrame.fromMatrix(mid, right, up, back), colour, neon and Enum.Material.Neon or Enum.Material.SmoothPlastic)
		end
	end
end

-- crystal shards on the point of the egg
OPS.crystals = function(ctx, a)
	local colour, n, y, len = a[2], a[3], a[4], a[5]
	local rec = ctx.recipe
	local top = topOf(rec)
	for i = 1, n do
		local th = (i - 0.5) / n * math.pi * 2
		local lean = CFrame.Angles(0, th, 0) * CFrame.Angles(math.rad(-22), 0, 0)
		local cf = CFrame.new(0.12 * math.sin(th), top - 0.12 + len * 0.4, 0.12 * math.cos(th)) * lean
		mk(ctx, "crystal", Vector3.new(0.16, len, 0.16), cf, colour, Enum.Material.Glass)
		mk(ctx, "crystal", Vector3.new(0.09, len * 0.5, 0.09), cf * CFrame.new(0, len * 0.7, 0), colour, Enum.Material.Glass)
	end
end

-- ====================================================================== build
export type Build = {
	model: Model, shells: { Part }, decorations: { BasePart }, recipe: Recipe,
	families: { [BasePart]: string }, height: number, canonH: number,
}

-- Builds the display egg. opts.height (studs, default CANON_H). opts.viewport dims the
-- palette slightly so the flat viewport light does not blow pale shells out.
-- opts.noScale leaves the egg in canonical units (the hatch rig adds cracks and shards
-- in that space first, then scales the whole model once); `canonH` in the result is
-- the egg's own canonical height so the caller can do that.
function M.build(key: string, opts: { height: number?, viewport: boolean?, name: string?, noScale: boolean? }?): Build?
	local recipe = R[key]
	if not recipe then return nil end
	opts = opts or {}
	local model = Instance.new("Model")
	model.Name = opts.name or key
	local ctx: Ctx = { recipe = recipe, model = model, rng = Random.new(recipe.seed), parts = {}, families = {}, neon = 0 }
	local tint = opts.viewport and 0.86 or 1
	local shells = {}
	for i, e in ipairs(recipe.shells) do
		local p = mk(ctx, "shell_body", Vector3.new(e.rx * 2, e.ry * 2, e.rx * 2), CFrame.new(0, e.cy, 0), mul(e.colour, tint), e.material, "ellipsoid")
		p.Name = "shell_body_" .. i
		shells[#shells + 1] = p
	end
	for _, op in ipairs(recipe.deco) do
		local fn = OPS[op[1]]
		if fn then
			fn(ctx, op)
		else
			warn("[EggArt] unknown op " .. tostring(op[1]) .. " in " .. key)
		end
	end
	if tint ~= 1 then
		for _, p in ipairs(ctx.parts) do
			if p.Material ~= Enum.Material.Neon and ctx.families[p] ~= "shell_body" then p.Color = mul(p.Color, tint) end
		end
	end
	model.PrimaryPart = shells[1]
	local decorations = {}
	for _, p in ipairs(ctx.parts) do
		if ctx.families[p] ~= "shell_body" then decorations[#decorations + 1] = p end
	end
	local canonH = topOf(recipe) - bottomOf(recipe)
	local height = opts.height or CANON_H
	-- The model's pivot is the egg's BASE (a model with a PrimaryPart pivots on that
	-- part, so the offset lives on the shell), so callers stand an egg on a surface with
	-- one PivotTo and the hatch rig rocks it about the point it touches the ground.
	shells[1].PivotOffset = CFrame.new(0, bottomOf(recipe) - recipe.shells[1].cy, 0)
	if not opts.noScale and math.abs(height - canonH) > 1e-3 then
		model:ScaleTo(height / canonH)
	end
	return { model = model, shells = shells, decorations = decorations, recipe = recipe, families = ctx.families, height = opts.noScale and canonH or height, canonH = canonH }
end

-- Part count report, for the budget check in the QA doc.
function M.census(key: string): (number, number)
	local b = M.build(key)
	if not b then return 0, 0 end
	local n, neon = 0, 0
	for _, d in ipairs(b.model:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
			if d.Material == Enum.Material.Neon then neon += 1 end
		end
	end
	b.model:Destroy()
	return n, neon
end

-- Keys in shop order per world, so callers can regenerate a whole folder.
function M.keysFor(world: string): { string }
	local out = {}
	for k, r in pairs(R) do
		if r.world == world then out[#out + 1] = k end
	end
	table.sort(out)
	return out
end

return M
