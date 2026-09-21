-- VoxelEgg: single source of truth for the voxel egg shell.
-- Ported from scratchpad/voxel_egg.py (the recipe that matched the reference clip)
-- and the Blender previz egg_set.py. The shop models AND the hatch ceremony must
-- both build from this, or they drift (the ceremony was 14 rows, the models 16).
local M = {}

M.HEIGHT, M.WIDTH = 5.30, 4.10
M.CELLS_Y = 16
M.CELL = M.HEIGHT / M.CELLS_Y
M.CELLS_XZ = math.floor(M.WIDTH / M.CELL + 0.5)
M.HALF = M.CELLS_XZ / 2
M.SEAM = math.floor(M.CELLS_Y * 0.44)

local PATCH_CHANCE = 0.62
local PEBBLES = 24
local PEB_MIN, PEB_MAX = 0.30, 0.44
local PEB_PROTRUDE = 0.35
local PEB_BAND0, PEB_BAND1 = 0.10, 0.85
local COLUMN_JITTER = 0.085

-- ViewportFrames clip albedo over ~205 to flat white, losing all face shading.
-- Anything built for the hatch/shop viewport must be authored darker.
M.VIEWPORT_SCALE = 0.724

function M.radiusAt(j)
	local t = ((j + 0.5) / M.CELLS_Y) * 1.94 - 0.97
	local s = math.max(0, 1 - t * t) ^ (t > 0 and 0.5 or 0.36)
	return M.HALF * s * (1 - 0.14 * t)
end

local function jitter(ix, iz)
	local h = bit32.bxor(ix * 73856093 % 2147483647, iz * 19349663 % 2147483647)
	return (bit32.band(bit32.rshift(h, 8), 1023) / 1023 - 0.5) * 0.8
end

local function mul(c, f)
	return Color3.new(math.clamp(c.R * f, 0, 1), math.clamp(c.G * f, 0, 1), math.clamp(c.B * f, 0, 1))
end

-- spec = { base, greys = {..}, peb, pebdk, cap = {colour, frac} or nil, seed }
-- returns array of { cf = CFrame, size = Vector3, colour = Color3, half = "top"/"bot" }
function M.cells(spec, tint)
	tint = tint or 1
	local rng = Random.new(spec.seed or 20260814)
	local BASE, GREYS = spec.base, spec.greys
	local segs, out = {}, {}
	for ix = 0, M.CELLS_XZ - 1 do
		for iz = 0, M.CELLS_XZ - 1 do
			local cx, cz = ix - (M.CELLS_XZ - 1) / 2, iz - (M.CELLS_XZ - 1) / 2
			local lo, hi
			for j = 0, M.CELLS_Y - 1 do
				local r = M.radiusAt(j) + jitter(ix, iz)
				if cx * cx + cz * cz <= r * r then
					lo = lo or j
					hi = j
				end
			end
			if lo then
				local cut = M.SEAM + (((math.floor(ix / 2) + iz) % 2 == 0) and 1 or 0)
				local raw = {}
				if rng:NextNumber() < PATCH_CHANCE and (hi - lo) >= 2 then
					local plen = rng:NextInteger(1, math.min(2, hi - lo))
					local ps = rng:NextInteger(lo, hi - plen + 1)
					local grey = GREYS[rng:NextInteger(1, #GREYS)]
					if ps > lo then table.insert(raw, {lo, ps - 1, BASE}) end
					table.insert(raw, {ps, ps + plen - 1, grey})
					if ps + plen <= hi then table.insert(raw, {ps + plen, hi, BASE}) end
				else
					table.insert(raw, {lo, hi, BASE})
				end
				if spec.cap then
					local capcol, capfrac = spec.cap[1], spec.cap[2]
					local crow = math.floor(M.CELLS_Y * capfrac)
					local split = {}
					for _, s in ipairs(raw) do
						local a, b, c = s[1], s[2], s[3]
						if a < crow and crow <= b then
							table.insert(split, {a, crow - 1, c})
							table.insert(split, {crow, b, c == BASE and capcol or c})
						else
							table.insert(split, {a, b, (a >= crow and c == BASE) and capcol or c})
						end
					end
					raw = split
				end
				local vj = 1 + (rng:NextNumber() * 2 - 1) * COLUMN_JITTER
				local list = {}
				for _, s in ipairs(raw) do
					local a, b, c = s[1], s[2], mul(s[3], vj)
					if a < cut and cut <= b then
						table.insert(list, {a, cut - 1, c, "bot"})
						table.insert(list, {cut, b, c, "top"})
					else
						table.insert(list, {a, b, c, a >= cut and "top" or "bot"})
					end
				end
				segs[ix .. "," .. iz] = list
			end
		end
	end

	for k, list in pairs(segs) do
		local ix, iz = k:match("(-?%d+),(-?%d+)")
		ix, iz = tonumber(ix), tonumber(iz)
		for _, s in ipairs(list) do
			local a, b, c, half = s[1], s[2], s[3], s[4]
			local cx = (ix - (M.CELLS_XZ - 1) / 2) * M.CELL
			local cz = (iz - (M.CELLS_XZ - 1) / 2) * M.CELL
			local cy = (((a + b) / 2 + 0.5) - M.CELLS_Y / 2) * M.CELL
			table.insert(out, {
				cf = CFrame.new(cx, cy, cz),
				size = Vector3.new(M.CELL, (b - a + 1) * M.CELL, M.CELL),
				colour = mul(c, tint), half = half,
			})
		end
	end

	-- pebbles: AXIS-ALIGNED. Free-rotated cubes inside a grid-aligned voxel body
	-- poke a corner out and read as flat debris stuck on the shell.
	for _ = 1, PEBBLES do
		local j = math.floor(M.CELLS_Y * (PEB_BAND0 + (rng:NextNumber() ^ 1.35) * (PEB_BAND1 - PEB_BAND0)))
		local r = M.radiusAt(j)
		if r > 1.2 then
			local ang = rng:NextNumber() * math.pi * 2
			local sz = PEB_MIN + rng:NextNumber() * (PEB_MAX - PEB_MIN)
			local d = (r + PEB_PROTRUDE - 0.5 * sz / M.CELL) * M.CELL
			local col = rng:NextNumber() < 0.3 and spec.pebdk or spec.peb
			table.insert(out, {
				cf = CFrame.new(math.cos(ang) * d, ((j + 0.5) - M.CELLS_Y / 2) * M.CELL, math.sin(ang) * d),
				size = Vector3.new(sz, sz * (0.88 + rng:NextNumber() * 0.12), sz),
				colour = mul(col, tint),
				half = j >= M.SEAM and "top" or "bot",
			})
		end
	end
	return out
end

function M.build(spec, tint, name)
	local model = Instance.new("Model")
	model.Name = name or "VoxelEgg"
	local n = 0
	for _, c in ipairs(M.cells(spec, tint)) do
		n += 1
		local p = Instance.new("Part")
		p.Name = (c.half == "top" and "cap_" or "cradle_") .. n
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
		p.Material = Enum.Material.SmoothPlastic
		p.Size, p.CFrame, p.Color = c.size, c.cf, c.colour
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Parent = model
	end
	model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart")
	return model
end

return M
