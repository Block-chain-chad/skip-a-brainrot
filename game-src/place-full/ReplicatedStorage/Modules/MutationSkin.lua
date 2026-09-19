--[[ =====================================================================
MutationSkin -- the Pippo Olivardino pack as an actual VOXEL SKIN.

WHY THIS EXISTS. MutationFX ports the pack's colour maths onto a brainrot's own
parts, and that alone was never going to look like the reference: in the pack a
mutation is mostly GEOMETRY. Wet grows brine beads off every downward face and
pools at the feet; Sandy erodes 7% of the body away and drifts a pile round the
base; Frozen crusts ice on every upward face; Demon grows horns; Glitched drops
whole scanline bands. Recolouring 34 authored parts reproduces none of that.

So this builds what the pack actually describes: the model is voxelised, the
pack's own extras() run on that grid, and every surviving voxel is painted by
the pack's own style() and glowFn(). The original parts are hidden and the voxel
shell becomes the creature -- a new layer of skin.

FIDELITY, AND WHERE IT HAS TO BEND.
  * rand(), hsl(), mix/mul/lum and all twelve style() bodies are ported from
    pippo_mutations.js verbatim -- same hash constants, same ramps -- so the
    noise patterns are the pack's own rather than a lookalike.
  * The pack's grid IS Pippo: 40 voxels tall, and extras() hardcodes that (drips
    scan y 8..14, the puddle has radius 8.5, horns start at y 38). Those are
    re-expressed here as FRACTIONS of whatever model is being skinned, which is
    the only way they carry to a body of another shape.
  * B(m) -- the pack's base-palette lookup -- becomes the colour of the PART a
    voxel was sampled from, so a mutation transforms the creature's own colours
    exactly as it transforms Pippo's.
  * Eyes are not special-cased. The pack gives them their own glow on six
    mutations via isEye(m), and there is no reliable way to pick an eye voxel
    out of 192 differently-authored models, so they take the body treatment.

COST. A skinned model is a few hundred parts rather than ~34, so this is for
DISPLAY -- a lineup, a reveal stage, a shop pedestal. MutationFX stays the cheap
path for every brainrot standing on a plot, which is why Build() is deliberately
NOT wired into MutationFX.apply.
========================================================================= ]]

local MutationSkin = {}

---------------------------------------------------------------- pack helpers
-- Math.imul: a 32-bit multiply keeping only the low word. Lua numbers are
-- doubles, so a plain a*b loses the wrap the pack's hash depends on.
local function imul(a, b)
	a, b = bit32.band(a, 0xFFFFFFFF), bit32.band(b, 0xFFFFFFFF)
	local ah, al = bit32.rshift(a, 16), bit32.band(a, 0xFFFF)
	local bh, bl = bit32.rshift(b, 16), bit32.band(b, 0xFFFF)
	return bit32.band(al * bl + bit32.lshift(ah * bl + al * bh, 16), 0xFFFFFFFF)
end

-- pippo_mutations.js rand(), constant for constant
local function rand(x, y, z, s)
	local n = bit32.bxor(imul(x, 0x27d4eb2d), imul(y, 0x165667b1),
		imul(z, 0x9e3779b1), imul(s or 0, 0x85ebca6b))
	n = imul(bit32.bxor(n, bit32.rshift(n, 15)), 0x2c1b3c6d)
	n = imul(bit32.bxor(n, bit32.rshift(n, 12)), 0x297a2d39)
	n = bit32.bxor(n, bit32.rshift(n, 15))
	return n / 4294967295
end

local function hexC(h)
	return Color3.fromRGB(bit32.band(bit32.rshift(h, 16), 255),
		bit32.band(bit32.rshift(h, 8), 255), bit32.band(h, 255))
end
local function lum(c) return c.R * 0.299 + c.G * 0.587 + c.B * 0.114 end
local function mul(c, k) return Color3.new(c.R * k, c.G * k, c.B * k) end
local function mix(a, b, t) return a:Lerp(b, math.clamp(t, 0, 1)) end
-- the pack's hsl(): LIGHTNESS, not value
local function hsl(h, s, l)
	h = (h % 1 + 1) % 1
	local function f(n)
		local k = (n + h * 12) % 12
		local a = s * math.min(l, 1 - l)
		return l - a * math.max(-1, math.min(k - 3, math.min(9 - k, 1)))
	end
	return Color3.new(f(0), f(8), f(4))
end
local function wave(v) return math.sin(v) * 0.5 + 0.5 end

MutationSkin.rand = rand

---------------------------------------------------------------- CLASSES
-- pippo_mutations.js CLASSES, its `roblox` column verbatim
local CLASSES = {
	solid = { Material = Enum.Material.Plastic, Transparency = 0,    Reflectance = 0 },
	metal = { Material = Enum.Material.Metal,   Transparency = 0,    Reflectance = 0.25 },
	wet   = { Material = Enum.Material.Glass,   Transparency = 0,    Reflectance = 0.3 },
	rough = { Material = Enum.Material.Sand,    Transparency = 0,    Reflectance = 0 },
	glass = { Material = Enum.Material.Glass,   Transparency = 0.32, Reflectance = 0.2 },
	glow  = { Material = Enum.Material.Neon,    Transparency = 0,    Reflectance = 0 },
}
MutationSkin.CLASSES = CLASSES

---------------------------------------------------------------- style()
-- One entry per mutation, each the pack's own style() body. `b` stands in for
-- B(m): the colour of the part this voxel was sampled from.
local DIA_A, DIA_B = hexC(0x8ecfec), hexC(0xeafcff)
local WHITE = Color3.new(1, 1, 1)
local STYLE = {
	Golden = function(b) return "metal", hsl(0.115, 0.95, 0.22 + math.min(0.62, lum(b) * 0.72)) end,
	Diamond = function(b, x, y, z)
		return "glass", mix(DIA_A, DIA_B, math.min(1, lum(b) * 1.2 + rand(x, y, z, 3) * 0.2))
	end,
	Wet = function(b, x, y, z, mat)
		if mat == "drip" then return "glass", hexC(0xd8f7ee) end
		local c = mix(mul(b, 0.78), hexC(0x24484a), 0.16)
		return "wet", mix(c, hexC(0xd6f0f2), rand(x, y, z, 5) > 0.78 and 0.5 or 0)
	end,
	Sandy = function(b, x, y, z, mat)
		if mat == "sand" then return "rough", mix(hexC(0xc9a961), hexC(0xe8d5a0), rand(x, y, z, 2)) end
		local grain = (rand(x, y, z, 9) - 0.5) * 0.16
		return "rough", mix(hexC(0x7a5c2c), hexC(0xf0e2b8), math.clamp(lum(b) * 1.15 + grain, 0, 1))
	end,
	Rainbow = function(_, x, y, z) return "solid", hsl(y * 0.055 + x * 0.014, 0.78, 0.55) end,
	Electric = function(b) return "metal", mix(mul(b, 0.3), hexC(0x14304a), 0.62) end,
	Frozen = function(b, x, y, z, mat)
		if mat == "ice" then return "glass", mix(hexC(0x9dc9de), hexC(0xf0fbff), rand(x, y, z, 4)) end
		local frost = rand(x, y, z, 13) > 0.8 and 0.35 or 0
		return "glass", mix(mix(b, hexC(0xa9cddd), 0.55), WHITE, frost)
	end,
	Aurora = function(b) return "metal", mix(mul(b, 0.3), hexC(0x0e2233), 0.55) end,
	Celestial = function(b) return "metal", mix(hexC(0x151a4c), hexC(0x453690), lum(b)) end,
	Glitched = function(b, x, y, z)
		local r, patch = rand(0, math.floor(y / 2), 0, 61), rand(x, y, z, 63)
		if r > 0.93 and patch > 0.45 then return "glow", hexC(0xff2ee0) end
		if r > 0.87 and patch > 0.6 then return "glow", hexC(0x2efff2) end
		return "solid", mix(b, hexC(0x291d33), 0.35)
	end,
	Demon = function(b, x, y, z, mat)
		if mat == "horn" then return "metal", mix(hexC(0x1a0d0a), hexC(0x54211a), rand(x, y, z, 6)) end
		local crack = rand(x, y, z, 43)
		if math.abs(wave(x * 0.5 + y * 0.31 + z * 0.2) - 0.5) < 0.05 and crack > 0.35 then
			return "glow", mix(hexC(0xff4a12), hexC(0xffc148), crack * 0.6)
		end
		return "metal", mix(hexC(0x140806), hexC(0x4a1a12), lum(b) * 0.9)
	end,
	Angel = function(b)
		return "metal", mix(mix(hexC(0xdcd3b4), hexC(0xfffefa), math.min(1, lum(b) * 1.5)), hexC(0xf6e8bc), 0.22)
	end,
}
MutationSkin.STYLE = STYLE

---------------------------------------------------------------- glowFn()
-- The pack's emissive term at t = 0. A voxel with a glow is promoted to Neon and
-- tinted with base+glow; animating it is MutationMotionClient's job, not this
-- module's, so the shape reads correctly in a still.
local GLOW = {
	Golden = function(x, y, z)
		if rand(x, y, z, 7) < 0.978 then return nil end
		return mul(hexC(0xfff6d0), 0.85)
	end,
	Diamond = function(x, y, z)
		if rand(x, y, z, 11) > 0.984 then return mul(hexC(0xe6faff), 0.8) end
		return nil
	end,
	Electric = function(x, y, z)
		if math.abs(wave(y * 0.8 + math.sin(x * 0.5) * 1.4) - 0.5) < 0.09 then
			return mul(hexC(0x5fdcff), 0.7)
		end
		return nil
	end,
	Frozen = function() return nil end,
	Aurora = function(x, y, z)
		local band = wave(y * 0.34 + math.sin(x * 0.22) * 0.9)
		local v = math.pow(band, 6) * 1.05
		if v < 0.25 then return nil end
		return mul(hsl(0.34 + 0.28 * wave(y * 0.12), 0.85, 0.58), math.min(v, 1))
	end,
	Celestial = function(x, y, z)
		local s = rand(x, y, z, 53)
		if s > 0.93 then return mul(hexC(0xfff6d8), 0.75) end
		if s > 0.84 then return mul(hexC(0x9d8bff), 0.3) end
		return nil
	end,
	Demon = function(x, y, z)
		if math.abs(wave(x * 0.5 + y * 0.31 + z * 0.2) - 0.5) >= 0.075 then return nil end
		return mul(hexC(0xff5a18), 0.8)
	end,
	Angel = function(x, y, z) return nil end,
}
MutationSkin.GLOW = GLOW


---------------------------------------------------------------- voxelise
-- True WORLD axis-aligned box. Model:GetBoundingBox returns extents in the
-- PrimaryPart's frame, so a model whose primary part is rotated reports nonsense
-- for world height -- build it from the parts' own corners instead.
local function worldBox(model)
	local lo, hi
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 0.95 then
			local cf, s = p.CFrame, p.Size * 0.5
			for i = 0, 7 do
				local c = cf * Vector3.new(
					(i % 2 == 0) and -s.X or s.X,
					(math.floor(i / 2) % 2 == 0) and -s.Y or s.Y,
					(math.floor(i / 4) % 2 == 0) and -s.Z or s.Z)
				lo = lo and Vector3.new(math.min(lo.X, c.X), math.min(lo.Y, c.Y), math.min(lo.Z, c.Z)) or c
				hi = hi and Vector3.new(math.max(hi.X, c.X), math.max(hi.Y, c.Y), math.max(hi.Z, c.Z)) or c
			end
		end
	end
	return lo, hi
end

-- PACK RESOLUTION. Pippo is 40 voxels tall and every constant in extras(),
-- style() and glowFn() is written against that scale -- band frequencies, the
-- drip window, the horn height. Sampling coarser (for part count) and then
-- feeding RAW indices to those functions would halve every spatial frequency,
-- so the grid is sampled at VOX_H while the coordinates handed to the pack's own
-- functions are scaled back into its 40-tall space.
local PACK_H = 40

--[[ SAMPLING HEIGHT -- the whole reason a voxel cast reads as "blocks" or as the
pack's own art. It is a dial, and it was set too low.

What matters is VOXEL SIZE IN STUDS, not the count. Pippo is 40 voxels over 7.14
studs, so his voxel is 0.179 studs. A brainrot is taller -- Tung is 10.23 -- so
sampling it at the same COUNT gives a voxel of 10.23/40 = 0.26 studs, already
coarser than the design; at the 24 this used to be fixed at, it is 0.43 studs,
**2.4x the size of Pippo's**, which is precisely why the first cast looked chunky
and wrong next to the real thing.

DEFAULT_VOX_STUDS matches the pack instead of matching its count, so a creature of
any height gets voxels the same physical size as Pippo's and therefore the same
visual grain. Cost scales with surface area, so roughly the square of the height:
Tung goes from ~930 parts at 24 to ~5,000 at pack density.

That cost is fine for ONE creature on screen -- a catch reveal, an index viewport,
a display stand -- and not fine for the 16 sitting on a plot. Pass
opts.voxelHeight (or opts.voxelStuds) to choose per call site. ]]
local DEFAULT_VOX_STUDS = 7.14 / 40   -- 0.1785: the pack's own voxel, in studs
local MIN_VOX_H, MAX_VOX_H = 12, 96   -- sanity rails on the part count

-- Ground-effect radii, in STUDS. Both were fractions of the voxel grid, which
-- meant they scaled with resolution -- doubling the detail quadrupled the disc.
-- Real distances instead, so the drift and the puddle stay the size the pack
-- draws them however finely the body is sampled.
local PILE_STUDS = 3.0
local PUDDLE_STUDS = 2.6

local function voxelise(model, opts)
	opts = opts or {}
	local lo, hi = worldBox(model)
	if not lo then return nil end
	local size = hi - lo
	-- height in voxels: explicit, or derived so each voxel is pack-sized
	local voxH = opts.voxelHeight
		or math.floor(size.Y / (opts.voxelStuds or DEFAULT_VOX_STUDS) + 0.5)
	local VOX_H = math.clamp(voxH, MIN_VOX_H, MAX_VOX_H)
	local vs = size.Y / VOX_H
	if vs <= 0 then return nil end
	local nx = math.max(1, math.ceil(size.X / vs))
	local nz = math.max(1, math.ceil(size.Z / vs))
	local parts = {}
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 0.95 then parts[#parts + 1] = p end
	end
	local cells = {}
	local function key(x, y, z) return x .. "," .. y .. "," .. z end
	for _, p in ipairs(parts) do
		local half = p.Size * 0.5
		local cf = p.CFrame
		local plo, phi
		for i = 0, 7 do
			local c = cf * Vector3.new(
				(i % 2 == 0) and -half.X or half.X,
				(math.floor(i / 2) % 2 == 0) and -half.Y or half.Y,
				(math.floor(i / 4) % 2 == 0) and -half.Z or half.Z)
			plo = plo and Vector3.new(math.min(plo.X, c.X), math.min(plo.Y, c.Y), math.min(plo.Z, c.Z)) or c
			phi = phi and Vector3.new(math.max(phi.X, c.X), math.max(phi.Y, c.Y), math.max(phi.Z, c.Z)) or c
		end
		local x0 = math.max(0, math.floor((plo.X - lo.X) / vs))
		local x1 = math.min(nx - 1, math.ceil((phi.X - lo.X) / vs))
		local y0 = math.max(0, math.floor((plo.Y - lo.Y) / vs))
		local y1 = math.min(VOX_H - 1, math.ceil((phi.Y - lo.Y) / vs))
		local z0 = math.max(0, math.floor((plo.Z - lo.Z) / vs))
		local z1 = math.min(nz - 1, math.ceil((phi.Z - lo.Z) / vs))
		for x = x0, x1 do
			for y = y0, y1 do
				for z = z0, z1 do
					local world = lo + Vector3.new((x + 0.5) * vs, (y + 0.5) * vs, (z + 0.5) * vs)
					local l = cf:PointToObjectSpace(world)
					if math.abs(l.X) <= half.X and math.abs(l.Y) <= half.Y and math.abs(l.Z) <= half.Z then
						cells[key(x, y, z)] = { colour = p.Color, mat = "body" }
					end
				end
			end
		end
	end
	return { cells = cells, lo = lo, vs = vs, nx = nx, ny = VOX_H, nz = nz, key = key, packScale = PACK_H / VOX_H }
end
MutationSkin.voxelise = voxelise

local function ikey(k)
	local x, y, z = string.match(k, "(-?%d+),(-?%d+),(-?%d+)")
	return tonumber(x), tonumber(y), tonumber(z)
end

---------------------------------------------------------------- extras()
-- The pack's own extras(), with its Pippo-specific constants re-expressed as
-- fractions of whatever body is being skinned. The pack's numbers are quoted on
-- each so the translation stays auditable.
local EXTRAS = {
	-- brine beads off every downward face over the torso, then a puddle at y0.
	-- pack: scans y 14..8 of 40 (35%..20%); puddle radius 8.5 against ~10 half-width
	Wet = function(g)
		local yTop, yBot = math.floor(g.ny * 0.35), math.floor(g.ny * 0.20)
		local add = {}
		for x = 0, g.nx - 1 do
			for z = 0, g.nz - 1 do
				for y = yTop, yBot, -1 do
					if g.cells[g.key(x, y, z)] and not g.cells[g.key(x, y - 1, z)]
						and rand(x, y, z, 17) > 0.62 then
						add[g.key(x, y - 1, z)] = true
						if rand(x, y, z, 19) > 0.45 then add[g.key(x, y - 2, z)] = true end
						if rand(x, y, z, 21) > 0.8 then add[g.key(x, y - 3, z)] = true end
					end
				end
			end
		end
		-- THE PUDDLE HAS TO REACH PAST THE FEET. Sweeping only 0..nx-1 confined it to
		-- the body's own footprint, where every cell is already solid, so it placed
		-- almost nothing. The pack's radius (8.5 against a ~10 half-width) spills
		-- clear of Pippo's legs; this sweeps the same way, outside the grid included.
		local cx, cz = (g.nx - 1) / 2, (g.nz - 1) / 2
		-- BOUNDED IN STUDS, not in grid cells. As a fraction of the grid it grows with
		-- the RESOLUTION as well as the creature, so at pack density the disc explodes:
		-- cost goes as the square of the radius. The pack's puddle reaches a little
		-- past Pippo's feet, so cap it at the same real distance.
		local r = math.min(math.max(g.nx, g.nz) * 0.62, PUDDLE_STUDS / g.vs)
		for x = math.floor(cx - r), math.ceil(cx + r) do
			for z = math.floor(cz - r), math.ceil(cz + r) do
				local d = math.sqrt((x - cx) ^ 2 + (z - cz) ^ 2)
				if d < r and rand(x, 0, z, 23) > 0.35 and not g.cells[g.key(x, 0, z)] then
					add[g.key(x, 0, z)] = true
				end
			end
		end
		for k in pairs(add) do
			if not g.cells[k] then g.cells[k] = { colour = Color3.new(1, 1, 1), mat = "drip" } end
		end
	end,
	-- erode ~7% above the ankles, then drift a pile round the base.
	-- pack: rand(...,31) > .93 for y > 2 of 40; pile height 3 falling off with radius
	Sandy = function(g)
		--[[ ERODE THE SURFACE ONLY, never the interior.

		The pack deletes 7% of voxels anywhere in the body, which is fine for Pippo:
		his character is a thin voxel shell, so a deleted cell was almost certainly on
		the surface already. Voxelising a brainrot fills its parts SOLID, so the same
		rule punches 7% of holes through the inside of a solid block -- and every
		interior hole exposes six new faces that all become parts.

		Measured on Tung: Golden 2,161 parts, Sandy 17,022. Fourteen thousand of those
		were internal surface around holes NOBODY CAN SEE, because they are buried
		inside the creature. It was also immune to the part budget, since erosion runs
		after the grid is sized.

		Restricting it to already-exposed cells gives the identical silhouette -- the
		crumbling edge the pack is after is a surface effect -- at a fraction of the
		cost. ]]
		local floorY = math.max(1, math.floor(g.ny * 0.05))
		local dead = {}
		for k in pairs(g.cells) do
			local x, y, z = ikey(k)
			if y > floorY and rand(x, y, z, 31) > 0.93 then
				local buried = g.cells[g.key(x + 1, y, z)] and g.cells[g.key(x - 1, y, z)]
					and g.cells[g.key(x, y + 1, z)] and g.cells[g.key(x, y - 1, z)]
					and g.cells[g.key(x, y, z + 1)] and g.cells[g.key(x, y, z - 1)]
				if not buried then dead[#dead + 1] = k end
			end
		end
		for _, k in ipairs(dead) do g.cells[k] = nil end
		-- SAME REACH PROBLEM AS THE PUDDLE, worse: the pack's falloff (h = 3 - d*0.7)
		-- dies at about 4 voxels, which on Pippo clears his narrow legs but on a wider
		-- creature lands entirely inside the body -- every cell already solid, so the
		-- pile placed nothing at all. Falloff is expressed against the body's own
		-- half-width instead, so the drift always rings the feet whatever it is
		-- drifting around.
		local cx, cz = (g.nx - 1) / 2, (g.nz - 1) / 2
		-- SAME CAP, and this is the one that mattered: uncapped, Sandy at pack density
		-- built a 40-voxel-radius drift and came to 19,031 parts on its own -- six
		-- times the whole rest of the creature, and enough to hitch a catch reveal.
		-- The pack's pile dies about 8.6 voxels out on a body 10 voxels half-wide, so
		-- it is a drift AROUND THE FEET, never a beach.
		local pileMax = math.max(2, math.floor(g.ny * 0.10))
		local R = math.min(math.max(g.nx, g.nz) * 0.78, PILE_STUDS / g.vs)
		for x = math.floor(cx - R), math.ceil(cx + R) do
			for z = math.floor(cz - R), math.ceil(cz + R) do
				local d = math.sqrt(((x - cx) * 1.0) ^ 2 + ((z - cz) * 1.2) ^ 2)
				local h = math.floor(math.max(0,
					pileMax * (1 - d / R) + rand(x, 0, z, 41) * 1.4))
				for y = 0, h - 1 do
					if not g.cells[g.key(x, y, z)] then
						g.cells[g.key(x, y, z)] = { colour = Color3.new(1, 1, 1), mat = "sand" }
					end
				end
			end
		end
	end,
	-- ice crust on every upward-exposed voxel. pack: rand(...,37) > .5, already
	-- general -- no Pippo constants to translate.
	Frozen = function(g)
		local add = {}
		for k in pairs(g.cells) do
			local x, y, z = ikey(k)
			if not g.cells[g.key(x, y + 1, z)] and rand(x, y, z, 37) > 0.5 then
				add[g.key(x, y + 1, z)] = true
			end
		end
		for k in pairs(add) do
			if not g.cells[k] then g.cells[k] = { colour = Color3.new(1, 1, 1), mat = "ice" } end
		end
	end,
	-- drop whole 2-voxel horizontal bands. pack: rand(0, floor(y/2), 0, 67) > .93
	Glitched = function(g)
		local dead = {}
		for k in pairs(g.cells) do
			local _, y = ikey(k)
			if rand(0, math.floor(y / 2), 0, 67) > 0.93 then dead[#dead + 1] = k end
		end
		for _, k in ipairs(dead) do g.cells[k] = nil end
	end,
	-- two horns off the top of the head. pack: bases at x -5 / +4, rising 7 voxels
	-- from y38 of 40, tapering from width 2 to 1.
	Demon = function(g)
		local top = g.ny - 1
		local minX, maxX = g.nx, -1
		for k in pairs(g.cells) do
			local x, y = ikey(k)
			if y >= top - 2 then
				minX = math.min(minX, x); maxX = math.max(maxX, x)
			end
		end
		if maxX < 0 then minX, maxX = 0, g.nx - 1 end
		local cz = math.floor((g.nz - 1) / 2)
		local len = math.max(3, math.floor(g.ny * 0.18))
		for _, spec in ipairs({ { minX + 1, -1 }, { maxX - 1, 1 } }) do
			local bx, dir = spec[1], spec[2]
			for i = 0, len - 1 do
				local x = bx + dir * math.floor(i / 3)
				local y = top + i
				local w = (i < math.floor(len * 0.6)) and 1 or 0
				for dx = 0, w do
					for dz = -1, 1 do
						g.cells[g.key(x + dir * dx, y, cz + dz)] =
							{ colour = Color3.new(1, 1, 1), mat = "horn" }
					end
				end
			end
		end
	end,
}
MutationSkin.EXTRAS = EXTRAS


---------------------------------------------------------------- parts()
-- The pack's detached props. Its `cells` are in VOXELS (0.05 m each) and its
-- `offset` is in METRES against a 2.00 m Pippo, so both are converted through
-- the skinned model's own height: one pack voxel = H/40, one metre = H/2.
local function ringCells(r, n)
	local out = {}
	for a = 0, n - 1 do
		local th = a / n * math.pi * 2
		out[#out + 1] = { math.floor(math.cos(th) * r + 0.5), 0, math.floor(math.sin(th) * r + 0.5) }
	end
	return out
end

local PROPS = {
	Celestial = function()
		local stars = {}
		for i = 0, 29 do
			local th = i / 30 * math.pi * 2 * 3.7
			local r = 15 + (i % 4) * 2
			stars[#stars + 1] = { math.floor(math.cos(th) * r + 0.5), -3 + ((i * 7) % 13), math.floor(math.sin(th) * r + 0.5) }
		end
		return {
			{ name = "celestial_ring",  cells = ringCells(9, 44), colour = 0xcfc4ff, cls = "glow", offset = { 0, 2.02, 0 }, tiltX = 0.35, spin = 0.32 },
			{ name = "celestial_stars", cells = stars,            colour = 0xfff3c8, cls = "glow", offset = { 0, 1.15, 0 }, spin = -0.5, bob = 0.05 },
		}
	end,
	Angel = function()
		local function wing(dir)
			local out = {}
			for j = 0, 15 do
				local span = math.floor(13 - math.abs(j - 9) * 0.85 + 0.5)
				for i = 0, span - 1 do
					if not (i > span - 2 and (j % 3) == 0) then
						out[#out + 1] = { dir * (2 + i), 4 + j, -math.floor(i * 0.35 + 0.5) }
					end
				end
			end
			return out
		end
		return {
			{ name = "angel_halo",   cells = ringCells(6, 40), colour = 0xffeaa8, cls = "glow",  offset = { 0, 2.06, 0 }, tiltX = 0.2, spin = 0.4, bob = 0.03 },
			{ name = "angel_wing_l", cells = wing(-1),         colour = 0xfffdf6, cls = "solid", offset = { -0.06, 0.52, -0.5 }, flap = -1 },
			{ name = "angel_wing_r", cells = wing(1),          colour = 0xfffdf6, cls = "solid", offset = { 0.06, 0.52, -0.5 },  flap = 1 },
		}
	end,
}
MutationSkin.PROPS = PROPS

---------------------------------------------------------------- build
local function applyClass(part, cls)
	local c = CLASSES[cls] or CLASSES.solid
	part.Material = c.Material
	part.Transparency = c.Transparency
	part.Reflectance = c.Reflectance
end

local function newCube(parent, size, cf, colour, cls, name)
	local p = Instance.new("Part")
	p.Name = name or "Vox"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	applyClass(p, cls)
	p.Parent = parent
	return p
end

--[[ Build the skin. Returns the Folder it created, or nil if this mutation has
no skin treatment. `model` keeps its own parts -- they are hidden, not destroyed,
so Clear() puts the creature back exactly as it was. ]]
function MutationSkin.Build(model, mutationName, opts)
	opts = opts or {}
	local style = STYLE[mutationName]
	if not style then return nil end
	local g = voxelise(model, opts)

	--[[ PART BUDGET. Pack density is a per-STUD resolution, so the cost depends
	entirely on how big the creature is -- measured across the roster it ranges from
	~2,200 parts (Golden) to ~16,000 (Sandy, whose drift adds most of it), and the
	build time with it: 122 ms against 444 ms.

	Half a second of hitch is fine for a display stand you build once and walk away
	from, and NOT fine on a catch reveal, which fires the instant a throw lands.
	So a caller that cares passes maxParts and gets the finest grid that fits.

	BUDGET AGAINST THE EXPOSED SHELL, NOT THE CELL COUNT. Only surface cells become
	parts, and the ratio between the two is not a constant -- measured on Tung it is
	about 23 cells per part for Golden, whose body is a solid volume that is nearly
	all interior, and about 6 for Sandy, whose drift is a flat slab that is nearly
	all surface. Budgeting on raw cells therefore over-corrects wildly on the solid
	ones: Golden came back at 173 parts against a 4,000 budget, a twelfth of what it
	was allowed, and looked worse than the coarse version it replaced.

	MERGE_YIELD converts exposed cells to parts. The builder merges runs of
	same-colour, same-class voxels along X, which costs roughly half of them.

	One retry, not a loop: the shell goes as the square of the height, so scaling by
	sqrt(budget/projected) lands close enough, and a second pass would cost more
	than the remaining error is worth. ]]
	if g and opts.maxParts then
		local exposed = 0
		for k in pairs(g.cells) do
			local x, y, z = ikey(k)
			if not (g.cells[g.key(x + 1, y, z)] and g.cells[g.key(x - 1, y, z)]
				and g.cells[g.key(x, y + 1, z)] and g.cells[g.key(x, y - 1, z)]
				and g.cells[g.key(x, y, z + 1)] and g.cells[g.key(x, y, z - 1)]) then
				exposed += 1
			end
		end
		-- CONSERVATIVE ON PURPOSE. The builder merges runs of same-colour, same-class
		-- voxels along X, and how much that saves depends entirely on the mutation:
		-- Golden's flat ramp merges well (~0.5), Diamond's per-voxel facets much less
		-- (~0.66), and RAINBOW NOT AT ALL -- its hue varies with both x and y, so no
		-- two neighbours ever share a colour and the yield is 1.0. Assuming the
		-- optimistic 0.5 let Diamond, Sandy and Rainbow all sail past the budget.
		-- Assuming no merging under-shoots slightly on the mergeable ones, which costs
		-- a little detail; over-shooting costs a frame hitch on a catch. Take the hit.
		local MERGE_YIELD = 0.95
		local projected = exposed * MERGE_YIELD
		if projected > opts.maxParts then
			local o2 = table.clone(opts)
			o2.voxelHeight = math.max(MIN_VOX_H,
				math.floor(g.ny * math.sqrt(opts.maxParts / projected)))
			g = voxelise(model, o2) or g
		end
	end
	if not g then return nil end

	local ex = EXTRAS[mutationName]
	if ex then ex(g) end

	--[[ SKIN ONLY BY DEFAULT (owner: "now they look like blocks and look weird --
	make it just the skin of the models when mutated").

	Rebuilding the whole body out of cubes turned every brainrot into a blocky
	approximation of itself: the creature's authored silhouette -- which is the
	thing a player recognises -- was thrown away and replaced with a voxel cast of
	it. The pack can do that because ITS creature is a voxel model to begin with;
	ours are not, and the cast is strictly worse than the original.

	So the body is left alone. The mutation reaches it as a SKIN -- the pack's
	colour transform and shading class on the model's own surfaces, which is
	MutationFX's job -- and this module now only builds the parts of the pack that
	are genuinely ADDITIONAL geometry and have nowhere else to live: Wet's drips
	and puddle, Sandy's drift pile, Frozen's ice crust, Demon's horns, Celestial's
	ring and stars, Angel's halo and wings.

	Two of the pack's extras are dropped entirely rather than faked, because they
	only mean anything on a voxel body: Sandy's 7% erosion and Glitched's dropped
	scanline bands both DELETE body voxels, and there is no equivalent operation on
	an authored mesh. Glitched therefore adds no geometry at all -- its whole read
	is the colour bands MutationFX already paints on.

	Pass opts.bodyShell = true to get the full voxel cast back. ]]
	local shell = {}
	for k, v in pairs(g.cells) do
		-- a cell the extras added (drip / sand / ice / horn) is never "body"
		local isAdded = v.mat ~= "body"
		if opts.bodyShell or isAdded then
			local x, y, z = ikey(k)
			if not (g.cells[g.key(x + 1, y, z)] and g.cells[g.key(x - 1, y, z)]
				and g.cells[g.key(x, y + 1, z)] and g.cells[g.key(x, y - 1, z)]
				and g.cells[g.key(x, y, z + 1)] and g.cells[g.key(x, y, z - 1)]) then
				shell[k] = v
			end
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = "MutationSkin"

	local glowFn = GLOW[mutationName]
	local ps = g.packScale
	-- resolve every shell voxel through the pack's style() and glowFn(), at
	-- coordinates scaled back into its own 40-tall space
	local resolved = {}
	for k, v in pairs(shell) do
		local x, y, z = ikey(k)
		local px = math.floor(x * ps + 0.5)
		local py = math.floor(y * ps + 0.5)
		local pz = math.floor(z * ps + 0.5)
		local cls, colour = style(v.colour, px, py, pz, v.mat)
		if glowFn then
			local gl = glowFn(px, py, pz)
			if gl then
				-- the pack's reference renderer adds glow * 0.75 on top of the surface
				colour = Color3.new(
					math.min(1, colour.R + gl.R * 0.75),
					math.min(1, colour.G + gl.G * 0.75),
					math.min(1, colour.B + gl.B * 0.75))
				cls = "glow"
			end
		end
		-- QUANTISE BEFORE MERGING. The pack's per-voxel noise (Diamond's facets,
		-- Sandy's grain, Frozen's frost) gives almost every voxel a colour that
		-- differs from its neighbour in the last bit, so the run merge below found
		-- nothing to join and those two came out at 1,562 and 2,349 parts. Rounding
		-- to 32 levels per channel is invisible at voxel size -- one step is under
		-- 1/255 of a channel away from where the noise already put it -- and lets
		-- runs collapse again.
		local function q(v) return math.floor(v * 31 + 0.5) / 31 end
		colour = Color3.new(q(colour.R), q(colour.G), q(colour.B))
		resolved[k] = { x = x, y = y, z = z, cls = cls, colour = colour }
	end

	-- GREEDY MERGE ALONG X, which the pack's own README suggests: runs of equal
	-- colour and class become one part. On a blocky body this is most of them,
	-- and it is the difference between ~900 parts and ~300.
	local rows = {}
	for k, v in pairs(resolved) do
		local rk = v.y .. "," .. v.z
		rows[rk] = rows[rk] or {}
		table.insert(rows[rk], v)
	end
	local vs = g.vs
	local built = 0
	for _, row in pairs(rows) do
		table.sort(row, function(a, b) return a.x < b.x end)
		local i = 1
		while i <= #row do
			local a = row[i]
			local j = i
			while j < #row do
				local nxt = row[j + 1]
				if nxt.x == row[j].x + 1 and nxt.cls == a.cls
					and nxt.colour == a.colour then j += 1 else break end
			end
			local run = j - i + 1
			local cx = (a.x + run / 2)
			local pos = g.lo + Vector3.new(cx * vs, (a.y + 0.5) * vs, (a.z + 0.5) * vs)
			newCube(folder, Vector3.new(vs * run, vs, vs), CFrame.new(pos), a.colour, a.cls)
			built += 1
			i = j + 1
		end
	end

	-- props, in pack units
	local H = g.ny * vs
	local mk = PROPS[mutationName]
	if mk then
		local centre = g.lo + Vector3.new(g.nx * vs * 0.5, 0, g.nz * vs * 0.5)
		for _, prop in ipairs(mk()) do
			local holder = Instance.new("Folder")
			holder.Name = prop.name
			holder.Parent = folder
			local off = Vector3.new(prop.offset[1], prop.offset[2], prop.offset[3]) * (H / 2)
			local cubeSize = Vector3.new(vs, vs, vs)
			for _, c in ipairs(prop.cells) do
				local local3 = Vector3.new(c[1], c[2], c[3]) * (H / 40)
				local cf = CFrame.new(centre + off) * CFrame.Angles(prop.tiltX or 0, 0, 0) * CFrame.new(local3)
				newCube(holder, cubeSize, cf, hexC(prop.colour), prop.cls, "PropVox")
				built += 1
			end
			-- the pack's own animation numbers, left on the instance for a motion
			-- driver to read rather than baked into a pose here
			if prop.spin then holder:SetAttribute("Spin", prop.spin) end
			if prop.bob then holder:SetAttribute("Bob", prop.bob) end
			if prop.flap then holder:SetAttribute("Flap", prop.flap) end
		end
	end

	-- ONLY a full voxel cast hides the creature underneath it. In skin mode the
	-- body is the creature's own geometry and must stay visible -- hiding it is
	-- exactly what made them read as blocks.
	if opts.bodyShell then
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") and p.Transparency < 0.95 then
				p:SetAttribute("SkinHidTransparency", p.Transparency)
				p.Transparency = 1
			end
		end
	end

	-- nothing to add (Glitched, and anything with no extras or props): do not leave
	-- an empty folder on the model for Clear() to have to reason about
	if built == 0 then
		folder:Destroy()
		return nil, 0
	end

	folder:SetAttribute("VoxelCount", built)
	folder:SetAttribute("Mutation", mutationName)
	folder.Parent = model
	return folder, built
end

function MutationSkin.Clear(model)
	local f = model:FindFirstChild("MutationSkin")
	if f then f:Destroy() end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local was = p:GetAttribute("SkinHidTransparency")
			if was then
				p.Transparency = was
				p:SetAttribute("SkinHidTransparency", nil)
			end
		end
	end
end

return MutationSkin
