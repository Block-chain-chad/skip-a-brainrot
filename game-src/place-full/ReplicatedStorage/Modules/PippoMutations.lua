--!strict
--[[
	PippoMutations.luau — Pippo Olivardino: voxel character + 12 visual mutations.
	ModuleScript (put in ReplicatedStorage). No dependencies.

	This is a 1:1 port of export/pippo_mutations.js — same hash, same colour math,
	same iteration order — so what Studio builds matches the HTML viewer voxel for
	voxel. Do not "clean up" the integer math: the noise function is bit-exact on
	purpose. Parity numbers to check against are in parity.json.

	API
	  Pippo.MUTATIONS                      -- ordered array of specs (id/label/rarity/desc/bg)
	  Pippo.VoxelsFor(id, t)               -- { {x,y,z,mat,cls,color,glow}, ... } sorted x,y,z
	  Pippo.PartsFor(id)                   -- detached props: halo, ring, stars, wings
	  Pippo.Build(id, opts)                -- Model of merged Parts, feet at the pivot's Y=0
	  Pippo.Animate(model, id, opts)       -- drives that mutation's motion; returns a stop()
	  Pippo.VOXEL_STUDS                    -- 0.178571 studs (0.05 m at 1 stud = 0.28 m)

	Build options: { Scale = 1, Parent = workspace, Anchored = true, CanCollide = false, Time = 0.6 }
	Animate options: { UpdateHz = 20 }
]]

local RunService = game:GetService("RunService")

local Pippo = {}

Pippo.VOXEL_METERS = 0.05
Pippo.VOXEL_STUDS = 0.05 / 0.28 -- 0.178571…; character stands ~7.14 studs tall

--=========================================================
-- 32-bit integer helpers (must stay bit-exact with JS)
--=========================================================
local B32 = 4294967296

local function u32(v: number): number
	v = math.floor(v) % B32
	if v < 0 then v += B32 end
	return v
end

-- equivalent of JS Math.imul, returned unsigned
local function imul(a: number, b: number): number
	a, b = u32(a), u32(b)
	local ah, al = math.floor(a / 65536), a % 65536
	local bh, bl = math.floor(b / 65536), b % 65536
	local hi = (ah * bl + al * bh) % 65536
	return (hi * 65536 + al * bl) % B32
end

local bxor, rshift = bit32.bxor, bit32.rshift

--- deterministic noise in [0,1) — identical to rand() in the JS module
local function rand(x: number, y: number, z: number, s: number?): number
	local n = bxor(
		bxor(imul(x, 0x27d4eb2d), imul(y, 0x165667b1)),
		bxor(imul(z, 0x9e3779b1), imul(s or 0, 0x85ebca6b))
	)
	n = imul(bxor(n, rshift(n, 15)), 0x2c1b3c6d)
	n = imul(bxor(n, rshift(n, 12)), 0x297a2d39)
	n = bxor(n, rshift(n, 15))
	return n / 4294967295
end
Pippo.rand = rand

--=========================================================
-- colour helpers (values are 0..1 sRGB triples)
--=========================================================
type RGB = { number }

local function rgb(hex: number): RGB
	return { math.floor(hex / 65536) % 256 / 255, math.floor(hex / 256) % 256 / 255, hex % 256 / 255 }
end
local function toHex(c: RGB): number
	local function q(v: number)
		return math.floor(math.clamp(v, 0, 1) * 255 + 0.5)
	end
	return q(c[1]) * 65536 + q(c[2]) * 256 + q(c[3])
end
local function mixc(a: RGB, b: RGB, t: number): RGB
	return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end
local function mulc(a: RGB, k: number): RGB
	return { a[1] * k, a[2] * k, a[3] * k }
end
local function lum(c: RGB): number
	return c[1] * 0.299 + c[2] * 0.587 + c[3] * 0.114
end
local function hsl(h: number, s: number, l: number): RGB
	h = ((h % 1) + 1) % 1
	local function f(n: number): number
		local k = (n + h * 12) % 12
		local a = s * math.min(l, 1 - l)
		return l - a * math.max(-1, math.min(k - 3, math.min(9 - k, 1)))
	end
	return { f(0), f(8), f(4) }
end
local function wave(v: number): number
	return math.sin(v) * 0.5 + 0.5
end
local function toColor3(hex: number): Color3
	return Color3.fromRGB(math.floor(hex / 65536) % 256, math.floor(hex / 256) % 256, hex % 256)
end
Pippo.toColor3 = toColor3

--=========================================================
-- base palette + shading classes
--=========================================================
Pippo.BASE_PALETTE = {
	olive = 0x7d9c2f, oliveLt = 0x91b03c, oliveDk = 0x51681c, pimento = 0xc93a26, pimentoD = 0x9c2a1a,
	skin = 0xefc0a2, skinShade = 0xd9a184, stubble = 0xd2ab80, hair = 0x6b4a2c, hairDk = 0x503821,
	eyeWhite = 0xf6f1e6, iris = 0x4c5b38, mouth = 0xbe6f68, chain = 0xd6d9de, shoe = 0x2f3a17,
}

--- how each shading class should look in Studio
Pippo.CLASSES = {
	solid = { Material = Enum.Material.Plastic, Transparency = 0,    Reflectance = 0 },
	metal = { Material = Enum.Material.Metal,   Transparency = 0,    Reflectance = 0.25 },
	wet   = { Material = Enum.Material.Glass,   Transparency = 0,    Reflectance = 0.3 },
	rough = { Material = Enum.Material.Sand,    Transparency = 0,    Reflectance = 0 },
	glass = { Material = Enum.Material.Glass,   Transparency = 0.32, Reflectance = 0.2 },
	glow  = { Material = Enum.Material.Neon,    Transparency = 0,    Reflectance = 0 },
}

local function B(m: string): RGB
	return rgb(Pippo.BASE_PALETTE[m] or 0x888888)
end
local function isEye(m: string): boolean
	return m == "eyeWhite" or m == "iris"
end

--=========================================================
-- base character
--=========================================================
type Grid = { [string]: string }

local function key(x: number, y: number, z: number): string
	return x .. "," .. y .. "," .. z
end

local function buildBase(): Grid
	local g: Grid = {}
	local function set(x, y, z, m) g[key(x, y, z)] = m end
	local function del(x, y, z) g[key(x, y, z)] = nil end
	local function get(x, y, z) return g[key(x, y, z)] end

	local function box(x0, x1, y0, y1, z0, z1, m)
		for x = x0, x1 do for y = y0, y1 do for z = z0, z1 do set(x, y, z, m) end end end
	end
	local function ell(cx, cy, cz, rx, ry, rz, m)
		for x = math.floor(cx - rx), math.ceil(cx + rx) do
			for y = math.floor(cy - ry), math.ceil(cy + ry) do
				for z = math.floor(cz - rz), math.ceil(cz + rz) do
					local dx, dy, dz = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry, (z + 0.5 - cz) / rz
					if dx * dx + dy * dy + dz * dz <= 1 then set(x, y, z, m) end
				end
			end
		end
	end
	-- snapshot keys, then recolour: matches the JS paint() (order-independent)
	local function paint(test: (number, number, number, string) -> boolean, m: string)
		local keys = {}
		for k in pairs(g) do table.insert(keys, k) end
		for _, k in ipairs(keys) do
			local x, y, z = string.match(k, "(-?%d+),(-?%d+),(-?%d+)")
			local xi, yi, zi = tonumber(x) :: number, tonumber(y) :: number, tonumber(z) :: number
			if g[k] and test(xi, yi, zi, g[k] :: string) then g[k] = m end
		end
	end

	box(-4, -2, 0, 1, -1, 3, "shoe"); box(1, 3, 0, 1, -1, 3, "shoe")          -- feet
	box(-4, -2, 2, 9, -1, 1, "skin"); box(1, 3, 2, 9, -1, 1, "skin")          -- legs
	ell(0, 17.5, 0, 8.3, 9.0, 7.7, "olive")                                   -- olive torso
	paint(function(_, y, _, m) return m == "olive" and (y == 11 or y == 22) end, "oliveLt")
	paint(function(_, y, _, m) return m == "olive" and y >= 24 end, "oliveDk")
	paint(function(_, y, _, m) return m == "oliveLt" and y >= 24 end, "oliveDk")
	for x = -3, 2 do for z = -3, 2 do for y = 24, 26 do del(x, y, z) end end end  -- hollow top
	do -- pimento in the chest
		local snapshot = {}
		for k, m in pairs(g) do snapshot[k] = m end
		for k, m in pairs(snapshot) do
			if m == "olive" or m == "oliveLt" then
				local xs, ys, zs = string.match(k, "(-?%d+),(-?%d+),(-?%d+)")
				local x, y, z = tonumber(xs) :: number, tonumber(ys) :: number, tonumber(zs) :: number
				local d = math.sqrt((x + 0.5) ^ 2 + (y + 0.5 - 17.5) ^ 2)
				if z >= 5 and d <= 2.6 then g[k] = "pimento"
				elseif z >= 6 and d <= 3.8 then g[k] = "pimentoD" end
			end
		end
	end
	box(-2, 1, 24, 27, -2, 1, "skin")                                          -- neck
	for x = -3, 2 do for z = -3, 2 do
		if x == -3 or x == 2 or z == -3 or z == 2 then set(x, if z == 2 then 26 else 27, z, "chain") end
	end end
	box(-5, 4, 28, 37, -5, 4, "skin")                                          -- head
	box(-5, 4, 28, 29, 4, 4, "stubble"); box(-5, -5, 28, 30, 1, 4, "stubble")
	box(4, 4, 28, 30, 1, 4, "stubble"); box(-4, 3, 27, 27, -4, 3, "stubble")
	box(-5, 4, 32, 32, 4, 4, "skinShade")
	box(-5, 4, 36, 37, -5, 4, "hair"); box(-6, 5, 38, 39, -6, 5, "hair")       -- bowl cut
	box(-6, -6, 31, 39, -5, 4, "hair"); box(5, 5, 31, 39, -5, 4, "hair"); box(-5, 4, 31, 39, -6, -6, "hair")
	box(-5, 4, 35, 35, 4, 4, "hair"); box(-5, 1, 34, 34, 4, 5, "hair")
	box(-6, -2, 35, 37, 5, 5, "hairDk"); box(2, 5, 36, 37, 5, 5, "hair")
	box(-4, -2, 33, 33, 4, 4, "hairDk"); box(1, 3, 33, 33, 4, 4, "hairDk")
	box(-2, -2, 34, 34, 4, 4, "hairDk"); box(1, 1, 34, 34, 4, 4, "hairDk")
	box(-4, -2, 31, 31, 4, 4, "eyeWhite"); box(1, 3, 31, 31, 4, 4, "eyeWhite") -- half-lidded eyes
	box(-3, -3, 31, 31, 4, 4, "iris"); box(2, 2, 31, 31, 4, 4, "iris")
	box(-4, -2, 32, 32, 4, 4, "skinShade"); box(1, 3, 32, 32, 4, 4, "skinShade")
	box(-1, 0, 29, 31, 4, 5, "skin"); box(-1, 0, 29, 29, 5, 5, "skinShade")    -- nose
	box(-2, 1, 28, 28, 4, 4, "mouth"); box(-1, 0, 27, 27, 4, 4, "mouth")       -- mouth
	box(-6, -6, 30, 32, -1, 1, "skin"); box(5, 5, 30, 32, -1, 1, "skin")       -- ears
	for _, a in ipairs({ { -10, -9 }, { 8, 9 } }) do                            -- arms + hands
		box(a[1], a[2], 12, 22, -1, 0, "skin"); box(a[1], a[2], 10, 11, -1, 1, "skin")
	end
	return g
end
Pippo.buildBase = buildBase

-- shared frame: the base silhouette spans x -10..9, y 0..39, z -8..7
Pippo.FRAME = { minX = -10, maxX = 9, minY = 0, maxY = 39, minZ = -8, maxZ = 7 }

--=========================================================
-- mutations
--=========================================================
local function ringCells(r: number, n: number)
	local out = {}
	for a = 0, n - 1 do
		local th = a / n * math.pi * 2
		table.insert(out, { x = math.floor(math.cos(th) * r + 0.5), y = 0, z = math.floor(math.sin(th) * r + 0.5) })
	end
	return out
end

type Style = { cls: string, c: RGB }

Pippo.MUTATIONS = {
	{
		id = "normale", label = "Normale", rarity = "1 / 1", bg = "#d9d3ba", chip = "#7d9c2f",
		desc = "Il ragazzo del barattolo. Standard salamoia issue.",
		style = function(m: string): Style return { cls = "solid", c = B(m) } end,
	},
	{
		id = "gold", label = "Gold", rarity = "1 / 50", bg = "#efe0b6", chip = "#e8b422",
		desc = "Dipped in the good oil money. Everything but the eyes is bullion.",
		style = function(m): Style
			if isEye(m) then
				return { cls = "glow", c = if m == "iris" then rgb(0x8a5a12) else rgb(0xfff4c6) }
			end
			return { cls = "metal", c = hsl(0.115, 0.95, 0.22 + math.min(0.62, lum(B(m)) * 0.72)) }
		end,
		glowFn = function(_, x, y, z, t): RGB
			local s = rand(x, y, z, 7)
			if s < 0.978 then return { 0, 0, 0 } end
			return if wave(t * 2.2 + s * 140) > 0.72 then mulc(rgb(0xfff6d0), 0.85) else { 0, 0, 0 }
		end,
		animate = { kind = "sparkle" },
	},
	{
		id = "diamond", label = "Diamond", rarity = "1 / 200", bg = "#e4f2fb", chip = "#a8e4ff",
		desc = "Crystallised in brine. Facets refract the olive underneath.",
		style = function(m, x, y, z): Style
			if isEye(m) then return { cls = "glow", c = rgb(0xdff6ff) } end
			local facet = rand(x, y, z, 3) * 0.2
			return { cls = "glass", c = mixc(rgb(0x8ecfec), rgb(0xeafcff), math.min(1, lum(B(m)) * 1.2 + facet)) }
		end,
		glowFn = function(_, x, y, z, t): RGB
			local s = rand(x, y, z, 11)
			if s > 0.984 and wave(t * 3.1 + s * 160) > 0.7 then return mulc(rgb(0xe6faff), 0.8) end
			return mulc(rgb(0x7cc4e8), 0.08)
		end,
		animate = { kind = "sparkle" },
	},
	{
		id = "wet", label = "Wet", rarity = "1 / 25", bg = "#c6d9de", chip = "#3f7f8c",
		desc = "Fresh out of the jar and still dripping the juice.",
		style = function(m, x, y, z): Style
			if m == "drip" then return { cls = "glass", c = rgb(0xd8f7ee) } end
			if isEye(m) then return { cls = "wet", c = B(m) } end
			local c = mixc(mulc(B(m), 0.78), rgb(0x24484a), 0.16)
			local sheen = if rand(x, y, z, 5) > 0.78 then 0.5 else 0
			return { cls = "wet", c = mixc(c, rgb(0xd6f0f2), sheen) }
		end,
		extras = function(a)
			for x = -8, 7 do for z = -7, 6 do for y = 14, 8, -1 do
				if a.get(x, y, z) and not a.get(x, y - 1, z) and rand(x, y, z, 17) > 0.62 then
					a.set(x, y - 1, z, "drip")
					if rand(x, y, z, 19) > 0.45 then a.set(x, y - 2, z, "drip") end
					if rand(x, y, z, 21) > 0.8 then a.set(x, y - 3, z, "drip") end
				end
			end end end
			for x = -9, 8 do for z = -8, 7 do
				if math.sqrt((x + 0.5) ^ 2 + (z + 0.5) ^ 2) < 8.5 and rand(x, 0, z, 23) > 0.35 and not a.get(x, 0, z) then
					a.set(x, 0, z, "drip")
				end
			end end
		end,
	},
	{
		id = "sandy", label = "Sandy", rarity = "1 / 20", bg = "#e6d7ae", chip = "#c9a961",
		desc = "Left on the beach in Rimini. Crumbling at the edges.",
		style = function(m, x, y, z): Style
			if m == "sand" then
				return { cls = "rough", c = mixc(rgb(0xc9a961), rgb(0xe8d5a0), rand(x, y, z, 2)) }
			end
			local grain = (rand(x, y, z, 9) - 0.5) * 0.16
			return { cls = "rough", c = mixc(rgb(0x7a5c2c), rgb(0xf0e2b8), math.clamp(lum(B(m)) * 1.15 + grain, 0, 1)) }
		end,
		extras = function(a)
			for _, c in ipairs(a.cells()) do
				if c.y > 2 and rand(c.x, c.y, c.z, 31) > 0.93 then a.del(c.x, c.y, c.z) end
			end
			for x = -11, 10 do for z = -9, 8 do
				local h = math.floor(math.max(0, 3 - math.sqrt((x * 0.5 + 0.5) ^ 2 + (z * 0.6 + 0.5) ^ 2) * 0.7 + rand(x, 0, z, 41) * 1.4))
				for y = 0, h - 1 do if not a.get(x, y, z) then a.set(x, y, z, "sand") end end
			end end
		end,
	},
	{
		id = "rainbow", label = "Rainbow", rarity = "1 / 500", bg = "#f2ecf6", chip = "#ff5ea8",
		desc = "Refuses one colour. The hue crawls up the body forever.",
		style = function(m, x, y, _): Style
			if isEye(m) then return { cls = "wet", c = B(m) } end
			return { cls = "solid", c = hsl(y * 0.055 + x * 0.014, 0.78, 0.55) }
		end,
		-- animated: hue scrolls; see Animate()
		animate = { kind = "hueScroll", speed = 0.28, sat = 0.78, light = 0.55 },
	},
	{
		id = "electric", label = "Electric", rarity = "1 / 150", bg = "#101a26", chip = "#5ee7ff",
		desc = "Plugged into the fridge socket. Arcs jump across the brine.",
		style = function(m): Style
			if isEye(m) then return { cls = "glow", c = rgb(0xc9f7ff) } end
			return { cls = "metal", c = mixc(mulc(B(m), 0.3), rgb(0x14304a), 0.62) }
		end,
		glowFn = function(_, x, y, z, t): RGB
			if rand(x, y, z, math.floor(t * 7)) > 0.94 then return rgb(0xe4fdff) end
			if math.abs(wave(y * 0.8 + math.sin(x * 0.5 + t * 3) * 1.4 + t * 5) - 0.5) < 0.09 then
				return mulc(rgb(0x5fdcff), 0.7)
			end
			return mulc(rgb(0x123a52), 0.18)
		end,
		animate = { kind = "arcs" },
	},
	{
		id = "frozen", label = "Frozen", rarity = "1 / 100", bg = "#dceaf2", chip = "#bcdcea",
		desc = "Back of the freezer, forgotten since 2011. Still asleep.",
		style = function(m, x, y, z): Style
			if m == "ice" then
				return { cls = "glass", c = mixc(rgb(0x9dc9de), rgb(0xf0fbff), rand(x, y, z, 4)) }
			end
			if isEye(m) then return { cls = "glass", c = rgb(0xdcf2fb) } end
			local frost = if rand(x, y, z, 13) > 0.8 then 0.35 else 0
			return { cls = "glass", c = mixc(mixc(B(m), rgb(0xa9cddd), 0.55), rgb(0xffffff), frost) }
		end,
		glowFn = function(_, x, y, z, t): RGB
			return mulc(rgb(0x8fd3f4), 0.06 + 0.05 * wave(t * 0.9 + rand(x, y, z, 29) * 20))
		end,
		-- NOTE: order-dependent — cells() is sorted x,y,z in both languages
		extras = function(a)
			for _, c in ipairs(a.cells()) do
				if not a.get(c.x, c.y + 1, c.z) and rand(c.x, c.y, c.z, 37) > 0.5 then
					a.set(c.x, c.y + 1, c.z, "ice")
				end
			end
		end,
		animate = { kind = "shimmer" },
	},
	{
		id = "aurora", label = "Aurora", rarity = "1 / 750", bg = "#071019", chip = "#57ffb0",
		desc = "Curtains of green and violet light drift up through him.",
		style = function(m): Style
			if isEye(m) then return { cls = "glow", c = rgb(0xbfffe4) } end
			return { cls = "metal", c = mixc(mulc(B(m), 0.3), rgb(0x0e2233), 0.55) }
		end,
		glowFn = function(_, x, y, _, t): RGB
			local band = wave(y * 0.34 - t * 1.5 + math.sin(x * 0.22 + t * 0.7) * 0.9)
			return mulc(hsl(0.34 + 0.28 * wave(y * 0.12 + t * 0.4), 0.85, 0.58), band ^ 6 * 1.05)
		end,
		animate = { kind = "bands" },
	},
	{
		id = "celestial", label = "Celestial", rarity = "1 / 1500", bg = "#06071a", chip = "#8f7bff",
		desc = "A pocket of night sky wearing his face. Stars orbit the head.",
		style = function(m): Style
			if isEye(m) then return { cls = "metal", c = rgb(0xfff4cf) } end
			return { cls = "metal", c = mixc(rgb(0x151a4c), rgb(0x453690), lum(B(m))) }
		end,
		glowFn = function(_, x, y, z, t): RGB
			local s = rand(x, y, z, 53)
			if s > 0.93 then return mulc(rgb(0xfff6d8), 0.5 + 0.5 * wave(t * 2 + s * 70)) end
			if s > 0.84 then return mulc(rgb(0x9d8bff), 0.22 + 0.16 * wave(t * 1.3 + s * 40)) end
			return mulc(rgb(0x2b2a72), 0.14)
		end,
		parts = function()
			local stars = {}
			for i = 0, 29 do
				local th = i / 30 * math.pi * 2 * 3.7
				local r = 15 + (i % 4) * 2
				table.insert(stars, {
					x = math.floor(math.cos(th) * r + 0.5),
					y = -3 + ((i * 7) % 13),
					z = math.floor(math.sin(th) * r + 0.5),
				})
			end
			return {
				{ name = "celestial_ring", cells = ringCells(9, 44), color = 0xcfc4ff, cls = "glow",
					offset = Vector3.new(0, 2.02, 0), tiltX = 0.35, spin = 0.32 },
				{ name = "celestial_stars", cells = stars, color = 0xfff3c8, cls = "glow",
					offset = Vector3.new(0, 1.15, 0), spin = -0.5, bob = 0.05 },
			}
		end,
		animate = { kind = "starfield" },
	},
	{
		id = "glitched", label = "Glitched", rarity = "1 / 2500", bg = "#140f1c", chip = "#ff3df0",
		desc = "Model failed to load correctly. Nobody is fixing it.",
		style = function(m, x, y, z): Style
			if isEye(m) then return { cls = "glow", c = rgb(0xff5cf2) } end
			local r, patch = rand(0, math.floor(y / 2), 0, 61), rand(x, y, z, 63)
			if r > 0.93 and patch > 0.45 then return { cls = "glow", c = rgb(0xff2ee0) } end
			if r > 0.87 and patch > 0.6 then return { cls = "glow", c = rgb(0x2efff2) } end
			return { cls = "solid", c = mixc(B(m), rgb(0x291d33), 0.35) }
		end,
		glowFn = function(_, x, y, z, t): RGB
			if rand(math.floor(t * 8), math.floor(y / 2), 0, 71) > 0.93 and rand(x, y, z, 73) > 0.55 then
				return mulc(rgb(0xff43e6), 0.35)
			end
			return { 0, 0, 0 }
		end,
		extras = function(a)
			for _, c in ipairs(a.cells()) do
				if rand(0, math.floor(c.y / 2), 0, 67) > 0.93 then a.del(c.x, c.y, c.z) end
			end
		end,
		-- horizontal slices jitter along X: 9 steps/sec, bands of 3 voxels, ±0.075 m
		animate = { kind = "sliceShift", stepsPerSecond = 9, bandVoxels = 3, maxOffsetMeters = 0.15, chance = 0.28 },
	},
	{
		id = "demon", label = "Demon", rarity = "1 / 5000", bg = "#170805", chip = "#e0341c",
		desc = "Cursed by the vinegar. Cracks in the rind leak heat.",
		style = function(m, x, y, z): Style
			if m == "horn" then
				return { cls = "metal", c = mixc(rgb(0x1a0d0a), rgb(0x54211a), rand(x, y, z, 6)) }
			end
			if isEye(m) then
				return { cls = "glow", c = if m == "iris" then rgb(0xffd08a) else rgb(0xff3a12) }
			end
			local crack = rand(x, y, z, 43)
			if math.abs(wave(x * 0.5 + y * 0.31 + z * 0.2) - 0.5) < 0.05 and crack > 0.35 then
				return { cls = "glow", c = mixc(rgb(0xff4a12), rgb(0xffc148), crack * 0.6) }
			end
			return { cls = "metal", c = mixc(rgb(0x140806), rgb(0x4a1a12), lum(B(m)) * 0.9) }
		end,
		glowFn = function(_, x, y, z, t): RGB
			if math.abs(wave(x * 0.5 + y * 0.31 + z * 0.2) - 0.5) >= 0.075 then
				return mulc(rgb(0x2b0704), 0.05)
			end
			return mulc(rgb(0xff5a18), (0.35 + 0.65 * wave(t * 1.8 + y * 0.4 + x * 0.2)) * 0.8)
		end,
		extras = function(a)
			for _, hb in ipairs({ { -5, -1 }, { 4, 1 } }) do
				local bx, dir = hb[1], hb[2]
				for i = 0, 6 do
					local x, y, w = bx + dir * math.floor(i / 3), 38 + i, if i < 4 then 1 else 0
					for dx = 0, w do for z = -1, 1 do a.set(x + dir * dx, y, z, "horn") end end
				end
			end
		end,
		animate = { kind = "lavaPulse" },
	},
	{
		id = "angel", label = "Angel", rarity = "1 / 10000", bg = "#f3efe4", chip = "#ffe9a8",
		desc = "Ascended above the jar. Nobody knows who let him in.",
		style = function(m): Style
			if m == "iris" then return { cls = "glow", c = rgb(0xf0cf82) } end
			if isEye(m) then return { cls = "glow", c = rgb(0xfffdf2) } end
			local c = mixc(rgb(0xdcd3b4), rgb(0xfffefa), math.min(1, lum(B(m)) * 1.5))
			return { cls = "metal", c = mixc(c, rgb(0xf6e8bc), 0.22) }
		end,
		glowFn = function(_, _, y, _, t): RGB
			return mulc(rgb(0xfff3c8), 0.1 + 0.07 * wave(t * 1.1 + y * 0.2))
		end,
		parts = function()
			local function wing(dir: number)
				local out = {}
				for j = 0, 15 do
					local span = math.floor(13 - math.abs(j - 9) * 0.85 + 0.5)
					for i = 0, span - 1 do
						if not (i > span - 2 and j % 3 == 0) then
							table.insert(out, { x = dir * (2 + i), y = 4 + j, z = -math.floor(i * 0.35 + 0.5) })
						end
					end
				end
				return out
			end
			return {
				{ name = "angel_halo", cells = ringCells(6, 40), color = 0xffeaa8, cls = "glow",
					offset = Vector3.new(0, 2.06, 0), tiltX = 0.2, spin = 0.4, bob = 0.03 },
				{ name = "angel_wing_l", cells = wing(-1), color = 0xfffdf6, cls = "solid",
					offset = Vector3.new(-0.06, 0.52, -0.5), flap = -1 },
				{ name = "angel_wing_r", cells = wing(1), color = 0xfffdf6, cls = "solid",
					offset = Vector3.new(0.06, 0.52, -0.5), flap = 1 },
			}
		end,
		animate = { kind = "halo", haloSpin = 0.4, wingFlapRate = 1.6, wingFlapRadians = 0.22 },
	},
}

local function specOf(id: string)
	for _, m in ipairs(Pippo.MUTATIONS) do
		if m.id == id then return m end
	end
	return Pippo.MUTATIONS[1]
end
Pippo.specOf = specOf

--=========================================================
-- resolve a mutation to voxels
--=========================================================
export type Voxel = { x: number, y: number, z: number, mat: string, cls: string, color: number, glow: number }

local function sortedCells(grid: Grid)
	local out = {}
	for k, m in pairs(grid) do
		local xs, ys, zs = string.match(k, "(-?%d+),(-?%d+),(-?%d+)")
		table.insert(out, { x = tonumber(xs) :: number, y = tonumber(ys) :: number, z = tonumber(zs) :: number, m = m })
	end
	table.sort(out, function(a, b)
		if a.x ~= b.x then return a.x < b.x end
		if a.y ~= b.y then return a.y < b.y end
		return a.z < b.z
	end)
	return out
end

function Pippo.VoxelsFor(id: string, t: number?): { Voxel }
	local mut = specOf(id)
	local grid = buildBase()
	local api = {
		set = function(x, y, z, m) grid[key(x, y, z)] = m end,
		del = function(x, y, z) grid[key(x, y, z)] = nil end,
		get = function(x, y, z) return grid[key(x, y, z)] end,
		cells = function() return sortedCells(grid) end,
	}
	if mut.extras then mut.extras(api) end

	local time = t or 0.6
	local out: { Voxel } = {}
	for _, c in ipairs(sortedCells(grid)) do
		local st = mut.style(c.m, c.x, c.y, c.z)
		local glow = if mut.glowFn then mut.glowFn(c.m, c.x, c.y, c.z, time) else { 0, 0, 0 }
		table.insert(out, {
			x = c.x, y = c.y, z = c.z, mat = c.m,
			cls = st.cls, color = toHex(st.c), glow = toHex(glow),
		})
	end
	return out
end

function Pippo.PartsFor(id: string)
	local mut = specOf(id)
	return if mut.parts then mut.parts() else {}
end

--=========================================================
-- build in Studio
--=========================================================
local function applyClass(part: BasePart, cls: string)
	local k = Pippo.CLASSES[cls] or Pippo.CLASSES.solid
	part.Material = k.Material
	part.Transparency = k.Transparency
	part.Reflectance = k.Reflectance
end

--- One Part per run of same-colour, same-class voxels along X. Feet sit at the
--- model's local Y = 0, x/z centred. Returns the Model plus a voxel map for Animate().
function Pippo.Build(id: string, opts: { Scale: number?, Parent: Instance?, Anchored: boolean?, CanCollide: boolean?, Time: number? }?)
	local o = opts or {}
	local scale = (o.Scale or 1) * Pippo.VOXEL_STUDS
	local voxels = Pippo.VoxelsFor(id, o.Time or 0.6)
	local mut = specOf(id)

	local model = Instance.new("Model")
	model.Name = "Pippo_" .. id

	-- centre on the base silhouette so every mutation lines up identically
	local F = Pippo.FRAME
	local ox = -((F.minX + F.maxX + 1) / 2)
	local oz = -((F.minZ + F.maxZ + 1) / 2)

	local tracked: { { part: BasePart, x: number, y: number, z: number, mat: string, cls: string, baseColor: number } } = {}

	local function makePart(x0: number, x1: number, y: number, z: number, cls: string, color: number, mat: string, name: string)
		local run = x1 - x0 + 1
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = if o.Anchored == nil then true else o.Anchored
		p.CanCollide = if o.CanCollide == nil then false else o.CanCollide
		p.CastShadow = cls ~= "glow"
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Size = Vector3.new(run * scale, scale, scale)
		p.Position = Vector3.new(
			(x0 + ox + run / 2) * scale,
			(y + 0.5) * scale,
			(z + oz + 0.5) * scale
		)
		p.Color = toColor3(color)
		applyClass(p, cls)
		p.Parent = model
		table.insert(tracked, { part = p, x = x0, y = y, z = z, mat = mat, cls = cls, baseColor = color })
		return p
	end

	-- voxels are already sorted x,y,z; group by (y,z) rows then merge runs
	local rows: { [string]: { Voxel } } = {}
	local rowOrder: { string } = {}
	for _, v in ipairs(voxels) do
		local rk = v.y .. "," .. v.z
		if not rows[rk] then rows[rk] = {}; table.insert(rowOrder, rk) end
		table.insert(rows[rk], v)
	end
	for _, rk in ipairs(rowOrder) do
		local list = rows[rk]
		table.sort(list, function(a, b) return a.x < b.x end)
		local i = 1
		while i <= #list do
			local v = list[i]
			local j = i
			while j + 1 <= #list
				and list[j + 1].x == list[j].x + 1
				and list[j + 1].color == v.color
				and list[j + 1].cls == v.cls do
				j += 1
			end
			makePart(v.x, list[j].x, v.y, v.z, v.cls, v.color, v.mat, "vox_" .. v.cls)
			i = j + 1
		end
	end

	-- detached props (halo, ring, orbiting stars, wings) as their own Models
	local props = {}
	for _, p in ipairs(Pippo.PartsFor(id)) do
		local pm = Instance.new("Model")
		pm.Name = p.name
		for _, c in ipairs(p.cells) do
			local part = Instance.new("Part")
			part.Name = p.name .. "_vox"
			part.Anchored = true
			part.CanCollide = false
			part.CastShadow = p.cls ~= "glow"
			part.Size = Vector3.new(scale, scale, scale)
			part.Position = Vector3.new(c.x * scale, c.y * scale, c.z * scale)
				+ Vector3.new(p.offset.X, p.offset.Y, p.offset.Z) / 0.28 * (o.Scale or 1)
			part.Color = toColor3(p.color)
			applyClass(part, p.cls)
			part.Parent = pm
		end
		local primary = pm:GetChildren()[1]
		if primary and primary:IsA("BasePart") then pm.PrimaryPart = primary end
		pm.Parent = model
		table.insert(props, { model = pm, spec = p, y0 = if primary and primary:IsA("BasePart") then primary.Position.Y else 0 })
	end

	local first = model:FindFirstChildWhichIsA("BasePart")
	if first then model.PrimaryPart = first end
	model:SetAttribute("Mutation", id)
	model:SetAttribute("Rarity", mut.rarity)
	model.Parent = o.Parent or workspace

	Pippo._tracked = Pippo._tracked or {}
	Pippo._tracked[model] = { voxels = tracked, props = props, scale = scale }
	return model, tracked, props
end

--=========================================================
-- animation
--=========================================================
--- Drives the mutation's motion on a model returned by Build(). Returns stop().
--- Animated mutations only need colour updates (except `glitched`, which nudges
--- slices along X, and props, which rotate/bob).
function Pippo.Animate(model: Model, id: string, opts: { UpdateHz: number? }?)
	local o = opts or {}
	local hz = o.UpdateHz or 20
	local mut = specOf(id)
	local data = (Pippo._tracked or {})[model]
	if not data then return function() end end

	local tracked, props, scale = data.voxels, data.props, data.scale
	local basePos: { [BasePart]: Vector3 } = {}
	for _, tv in ipairs(tracked) do basePos[tv.part] = tv.part.Position end

	local acc, clock = 0, 0
	local kind = if mut.animate then mut.animate.kind else nil

	local conn = RunService.Heartbeat:Connect(function(dt)
		clock += dt
		acc += dt

		for _, pr in ipairs(props) do
			local pm, spec = pr.model, pr.spec
			if pm.PrimaryPart then
				local rot = 0
				if spec.spin then rot = clock * spec.spin end
				if spec.flap then rot = spec.flap * (-0.55 - math.sin(clock * 1.6) * 0.22) end
				local bob = if spec.bob then math.sin(clock * 1.4) * spec.bob / 0.28 else 0
				local pivot = pm:GetPivot()
				pm:PivotTo(CFrame.new(pivot.Position.X, pr.y0 + bob, pivot.Position.Z)
					* CFrame.Angles(spec.tiltX or 0, rot, 0))
			end
		end

		if not kind or acc < 1 / hz then return end
		acc = 0

		if kind == "hueScroll" then
			for _, tv in ipairs(tracked) do
				if tv.mat ~= "eyeWhite" and tv.mat ~= "iris" then
					local c = hsl(tv.y * 0.055 + tv.x * 0.014 - clock * 0.28, 0.78, 0.55)
					tv.part.Color = Color3.new(c[1], c[2], c[3])
				end
			end
		elseif kind == "sliceShift" then
			local step = math.floor(clock * 9)
			for _, tv in ipairs(tracked) do
				local band = math.floor(tv.y / 3)
				local off = if rand(step, band, 0, 83) > 0.72 then (rand(step, band, 1, 89) - 0.5) * 0.3 / 0.28 else 0
				local b = basePos[tv.part]
				tv.part.Position = Vector3.new(b.X + off, b.Y, b.Z)
			end
		elseif mut.glowFn then
			-- sparkle / arcs / bands / shimmer / starfield / lavaPulse:
			-- surface colour + additive glow, exactly like the reference renderer
			for _, tv in ipairs(tracked) do
				local g = mut.glowFn(tv.mat, tv.x, tv.y, tv.z, clock)
				local base = rgb(tv.baseColor)
				tv.part.Color = Color3.new(
					math.min(1, base[1] + g[1] * 0.75),
					math.min(1, base[2] + g[2] * 0.75),
					math.min(1, base[3] + g[3] * 0.75)
				)
			end
		end
	end)

	return function() conn:Disconnect() end
end

return Pippo
