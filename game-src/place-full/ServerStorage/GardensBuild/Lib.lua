-- GardensLib -- primitive builders for World 3, The Lush Gardens.
--
-- Everything in World 3 is placed in LOCAL coordinates around L.ORIGIN so the whole
-- world can be moved later by changing one number. Use L.wv/L.wcf to convert.
--
-- House rules for this world (they exist because of specific past mistakes):
--  * every part is Anchored, and decorative parts get CanQuery/CanTouch = false so a
--    world of 30k props does not cost 30k touch checks.
--  * nothing that a player can stand under is ever built without something holding it up.
--  * walls are built as SOLID slabs with openings COMPOSED from sill/jamb/lintel pieces,
--    never as four loose panels with a hoped-for join. That is what leaves gaps.

local L = {}

L.ORIGIN = Vector3.new(8000, 1000, -8000)

function L.wv(x, y, z)
	return Vector3.new(L.ORIGIN.X + x, L.ORIGIN.Y + y, L.ORIGIN.Z + z)
end
function L.wcf(x, y, z)
	return CFrame.new(L.ORIGIN.X + x, L.ORIGIN.Y + y, L.ORIGIN.Z + z)
end
-- world vector -> local
function L.lv(v)
	return v - L.ORIGIN
end

----------------------------------------------------------------------------------
-- PALETTE
----------------------------------------------------------------------------------
L.C = {
	PaleStone      = Color3.fromRGB(216, 216, 200),
	ElvenStone     = Color3.fromRGB(198, 202, 186),
	WarmStone      = Color3.fromRGB(206, 196, 162),
	WeatheredStone = Color3.fromRGB(154, 160, 146),
	GreyStone      = Color3.fromRGB(126, 132, 128),
	DarkStone      = Color3.fromRGB(78, 84, 82),
	DeepStone      = Color3.fromRGB(52, 58, 56),
	MossStone      = Color3.fromRGB(124, 142, 106),
	Moss           = Color3.fromRGB(94, 130, 72),
	DeepMoss       = Color3.fromRGB(62, 96, 56),
	Lichen         = Color3.fromRGB(158, 178, 118),
	Leaf           = Color3.fromRGB(102, 156, 86),
	LeafDark       = Color3.fromRGB(60, 104, 64),
	LeafPale       = Color3.fromRGB(154, 190, 112),
	LeafBlue       = Color3.fromRGB(96, 152, 138),
	Bark           = Color3.fromRGB(88, 74, 60),
	BarkPale       = Color3.fromRGB(134, 124, 102),
	Root           = Color3.fromRGB(102, 86, 66),
	RootPale       = Color3.fromRGB(140, 126, 100),
	GlowGreen      = Color3.fromRGB(180, 248, 178),
	GlowCyan       = Color3.fromRGB(158, 234, 238),
	GlowGold       = Color3.fromRGB(248, 234, 160),
	GlowPink       = Color3.fromRGB(250, 138, 180),
	GlowMagenta    = Color3.fromRGB(232, 112, 198),
	GlowBlue       = Color3.fromRGB(140, 186, 246),
	Water          = Color3.fromRGB(124, 190, 194),
	Gold           = Color3.fromRGB(204, 176, 112),
	Verdigris      = Color3.fromRGB(122, 164, 146),
	Iron           = Color3.fromRGB(72, 76, 78),
	Wood           = Color3.fromRGB(108, 86, 62),
	WoodPale       = Color3.fromRGB(156, 130, 94),
	WoodRed        = Color3.fromRGB(122, 76, 58),
	Cloth          = Color3.fromRGB(92, 118, 110),
	ClothPink      = Color3.fromRGB(196, 104, 138),
	ClothGold      = Color3.fromRGB(198, 168, 104),
	ClothTeal      = Color3.fromRGB(74, 128, 130),
	Glass          = Color3.fromRGB(150, 212, 202),
	Petal          = Color3.fromRGB(238, 106, 152),
	PetalPale      = Color3.fromRGB(246, 176, 202),
}

L.M = {
	Stone   = Enum.Material.Slate,
	Rough   = Enum.Material.Rock,
	Cobble  = Enum.Material.Cobblestone,
	Marble  = Enum.Material.Marble,
	Granite = Enum.Material.Granite,
	Sand    = Enum.Material.Sandstone,
	Brick   = Enum.Material.Brick,
	Wood    = Enum.Material.Wood,
	Plank   = Enum.Material.WoodPlanks,
	Grass   = Enum.Material.Grass,
	Leafy   = Enum.Material.LeafyGrass,
	Moss    = Enum.Material.Grass,
	Neon    = Enum.Material.Neon,
	Glass   = Enum.Material.Glass,
	Metal   = Enum.Material.Metal,
	Foil    = Enum.Material.Foil,
	Fabric  = Enum.Material.Fabric,
	Ice     = Enum.Material.Ice,
	Slime   = Enum.Material.Glacier,
	Mud     = Enum.Material.Mud,
	Ground  = Enum.Material.Ground,
	Basalt  = Enum.Material.Basalt,
	Lime    = Enum.Material.Limestone,
	Pebble  = Enum.Material.Pebble,
	Concrete= Enum.Material.Concrete,
}

----------------------------------------------------------------------------------
-- CORE PART FACTORY
----------------------------------------------------------------------------------
-- opts:  collide=false, shadow=false, solid=true (keeps CanQuery/CanTouch on),
--        transparency, reflect, name suffix handled by caller.
local function finish(p, o)
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if o.collide == false then p.CanCollide = false end
	if o.shadow == false then p.CastShadow = false end
	-- decorative by default: props do not need to answer raycasts or touch events
	if o.solid ~= true then
		p.CanQuery = false
		p.CanTouch = false
	end
	if o.transparency then p.Transparency = o.transparency end
	if o.reflect then p.Reflectance = o.reflect end
	if o.doubleSided ~= nil then end
	return p
end

local EMPTY = {}

function L.box(parent, name, cf, size, color, material, o)
	o = o or EMPTY
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color or L.C.ElvenStone
	p.Material = material or L.M.Stone
	finish(p, o)
	p.Parent = parent
	return p
end

-- Cylinder: Roblox's Cylinder shape runs its LENGTH along the part's local X axis.
function L.cyl(parent, name, cf, len, dia, color, material, o)
	o = o or EMPTY
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Name = name
	p.Size = Vector3.new(len, dia, dia)
	p.CFrame = cf
	p.Color = color or L.C.ElvenStone
	p.Material = material or L.M.Stone
	finish(p, o)
	p.Parent = parent
	return p
end

-- An upright cylinder (a column/trunk) centred at cf, running along cf's Y axis.
function L.post(parent, name, cf, height, dia, color, material, o)
	return L.cyl(parent, name, cf * CFrame.Angles(0, 0, math.rad(90)), height, dia, color, material, o)
end

function L.ball(parent, name, cf, dia, color, material, o)
	o = o or EMPTY
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Name = name
	p.Size = Vector3.new(dia, dia, dia)
	p.CFrame = cf
	p.Color = color or L.C.Leaf
	p.Material = material or L.M.Grass
	finish(p, o)
	p.Parent = parent
	return p
end

-- A squashable sphere (uses a Block with heavy rounding is not possible, so this is a
-- Ball scaled by CFrame is not possible either -- so foliage blobs use SpecialMesh).
function L.blob(parent, name, cf, size, color, material, o)
	o = o or EMPTY
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color or L.C.Leaf
	p.Material = material or L.M.Grass
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	finish(p, o)
	p.Parent = parent
	return p
end

function L.wedge(parent, name, cf, size, color, material, o)
	o = o or EMPTY
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color or L.C.ElvenStone
	p.Material = material or L.M.Stone
	finish(p, o)
	p.Parent = parent
	return p
end

function L.corner(parent, name, cf, size, color, material, o)
	o = o or EMPTY
	local p = Instance.new("CornerWedgePart")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color or L.C.ElvenStone
	p.Material = material or L.M.Stone
	finish(p, o)
	p.Parent = parent
	return p
end

-- A cylinder spanning two points -- the workhorse for roots, vines, branches, cables.
function L.tube(parent, name, a, b, dia, color, material, o)
	local d = b - a
	local len = d.Magnitude
	if len < 0.05 then return nil end
	local cf = CFrame.lookAt(a + d * 0.5, b) * CFrame.Angles(0, math.pi / 2, 0)
	return L.cyl(parent, name, cf, len, dia, color, material, o)
end

-- A box spanning two points (beams, rails, planks).
function L.beam(parent, name, a, b, w, h, color, material, o)
	local d = b - a
	local len = d.Magnitude
	if len < 0.05 then return nil end
	local cf = CFrame.lookAt(a + d * 0.5, b)
	return L.box(parent, name, cf, Vector3.new(w, h, len), color, material, o)
end

function L.folder(parent, name)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

function L.model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

----------------------------------------------------------------------------------
-- LIGHT / EFFECT HELPERS
----------------------------------------------------------------------------------
function L.light(parent, color, brightness, range, shadows)
	local pl = Instance.new("PointLight")
	pl.Color = color
	pl.Brightness = brightness
	pl.Range = range
	pl.Shadows = shadows or false
	pl.Parent = parent
	return pl
end

function L.spot(parent, color, brightness, range, angle, face)
	local s = Instance.new("SpotLight")
	s.Color = color
	s.Brightness = brightness
	s.Range = range
	s.Angle = angle
	s.Face = face or Enum.NormalId.Bottom
	s.Shadows = false
	s.Parent = parent
	return s
end

-- A glowing element: neon part + matching light, the standard "glowing plant" unit.
function L.glow(parent, name, cf, size, color, brightness, range, shape)
	local p
	if shape == "ball" then
		p = L.ball(parent, name, cf, size.X, color, L.M.Neon, {collide = false, shadow = false})
	elseif shape == "blob" then
		p = L.blob(parent, name, cf, size, color, L.M.Neon, {collide = false, shadow = false})
	else
		p = L.box(parent, name, cf, size, color, L.M.Neon, {collide = false, shadow = false})
	end
	if brightness and brightness > 0 then
		L.light(p, color, brightness, range or 14)
	end
	return p
end

----------------------------------------------------------------------------------
-- MATH / RANDOM
----------------------------------------------------------------------------------
function L.rng(seed) return Random.new(seed) end

function L.lerp(a, b, t) return a + (b - a) * t end

function L.yaw(deg) return CFrame.Angles(0, math.rad(deg), 0) end

-- Deterministic smooth value noise in 2D, range roughly -1..1.
-- Luau has no bitwise OPERATORS (that is Lua 5.3), so this is the float hash rather
-- than the usual xor-shift -- it is deterministic, which is all the terrain needs.
local function hash2(x, y, seed)
	local n = math.sin(x * 127.1 + y * 311.7 + seed * 74.7) * 43758.5453
	return (n - math.floor(n)) * 2 - 1
end
function L.noise2(x, y, seed)
	local xi, yi = math.floor(x), math.floor(y)
	local xf, yf = x - xi, y - yi
	local u = xf * xf * (3 - 2 * xf)
	local v = yf * yf * (3 - 2 * yf)
	local a = hash2(xi, yi, seed)
	local b = hash2(xi + 1, yi, seed)
	local c = hash2(xi, yi + 1, seed)
	local d = hash2(xi + 1, yi + 1, seed)
	return L.lerp(L.lerp(a, b, u), L.lerp(c, d, u), v)
end

-- fractal noise, `oct` octaves
function L.fbm(x, y, seed, oct, freq, gain)
	oct = oct or 4; freq = freq or 1; gain = gain or 0.5
	local sum, amp, norm = 0, 1, 0
	for i = 1, oct do
		sum = sum + L.noise2(x * freq, y * freq, seed + i * 101) * amp
		norm = norm + amp
		amp = amp * gain
		freq = freq * 2
	end
	return sum / norm
end

-- Smooth 0..1 ramp
function L.smooth(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- distance from point to a 2D segment, for river/path shaping
function L.segDist(px, pz, ax, az, bx, bz)
	local vx, vz = bx - ax, bz - az
	local wx, wz = px - ax, pz - az
	local len2 = vx * vx + vz * vz
	local t = len2 > 0 and math.clamp((wx * vx + wz * vz) / len2, 0, 1) or 0
	local cx, cz = ax + vx * t, az + vz * t
	local dx, dz = px - cx, pz - cz
	return math.sqrt(dx * dx + dz * dz), t
end

-- Catmull-Rom through a list of Vector3, returns point at u in 0..1
function L.spline(points, u)
	local n = #points
	if n < 2 then return points[1] end
	local seg = math.clamp(math.floor(u * (n - 1)) + 1, 1, n - 1)
	local t = u * (n - 1) - (seg - 1)
	local p0 = points[math.max(seg - 1, 1)]
	local p1 = points[seg]
	local p2 = points[math.min(seg + 1, n)]
	local p3 = points[math.min(seg + 2, n)]
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

return L
