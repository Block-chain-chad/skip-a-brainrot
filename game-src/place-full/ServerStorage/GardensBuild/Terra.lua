-- GardensTerra -- voxel writer for World 3.
--
-- WHY TILES AND NOT FillBlock PER COLUMN. FillBlock sets full occupancy, so a
-- heightfield built out of it is terraced -- you get staircase hills. WriteVoxels
-- takes FRACTIONAL occupancy, which is what makes a smooth surface, so the whole
-- floor and ceiling go in through WriteVoxels on 64-stud tiles.
--
-- WHY THE SHELL BOTTOM LOOKS AT NEIGHBOURS. Terrain here is a SHELL, not solid rock
-- to bedrock -- filling 2960x2960x900 studs solid is hundreds of millions of voxels.
-- A fixed-depth shell is fine on gentle ground but tears open on steep ground: if one
-- column's surface is 200 and the next is 300, two 30-deep shells (170..200, 270..300)
-- leave a 70-stud hole in the cliff. Taking the MINIMUM of the column and its
-- neighbours guarantees consecutive shells overlap, so a cliff face is always closed.

local L = require(script.Parent.Lib)
local F = require(script.Parent.Field)

local T = workspace.Terrain
local Terra = {}

local RES = 4
local CEIL_THICK = 34

-- Roblox reconstructs its terrain isosurface about 2 studs ABOVE the height implied
-- by a straight "fill each voxel from its bottom" occupancy. Measured over 521
-- samples: mean +2.11, median +1.99, p10 +1.72, p90 +2.49, and independent of where
-- the height falls between voxel boundaries -- a constant bias, not noise.
--
-- Correcting it HERE rather than in the placement code keeps Field.ground(x,z) the
-- height that things actually stand on. Left uncorrected it silently buried every
-- paving slab, footing and doorstep in the world by two studs.
local SURFACE_BIAS = 2.1

local ORIGIN = L.ORIGIN

-- world-space Region3 for a local-space box (origin is 4-aligned, so this stays on grid)
local function regionOf(x0, y0, z0, x1, y1, z1)
	return Region3.new(
		Vector3.new(ORIGIN.X + x0, ORIGIN.Y + y0, ORIGIN.Z + z0),
		Vector3.new(ORIGIN.X + x1, ORIGIN.Y + y1, ORIGIN.Z + z1))
end

local AIR = Enum.Material.Air

----------------------------------------------------------------------------------
-- FLOOR
----------------------------------------------------------------------------------
-- Writes one 64-stud tile of ground. Returns voxels written.
local function floorTile(tx, tz, size)
	local n = size / RES                       -- voxels across
	-- sample heights with a one-voxel margin so the shell bottom can see neighbours
	local g, sd = {}, {}
	local gmin, gmax = math.huge, -math.huge
	for i = -1, n do
		g[i], sd[i] = {}, {}
		local x = tx + (i + 0.5) * RES
		for j = -1, n do
			local z = tz + (j + 0.5) * RES
			local ch = F.ceiling(x, z)
			local h = F.ground(x, z, ch)
			g[i][j] = h
			sd[i][j] = F.shellDepth(x, z)
			if i >= 0 and i < n and j >= 0 and j < n then
				if h < gmin then gmin = h end
				if h > gmax then gmax = h end
			end
		end
	end

	-- shell bottom: min of self and 4-neighbours, minus this column's shell depth
	local bot = {}
	local bmin = math.huge
	for i = 0, n - 1 do
		bot[i] = {}
		for j = 0, n - 1 do
			local m = math.min(g[i][j], g[i - 1][j], g[i + 1][j], g[i][j - 1], g[i][j + 1])
			local b = m - sd[i][j]
			bot[i][j] = b
			if b < bmin then bmin = b end
		end
	end

	local y0 = math.floor(bmin / RES) * RES
	local y1 = math.ceil((gmax + RES) / RES) * RES
	if y1 <= y0 then return 0 end
	local ny = (y1 - y0) / RES
	if ny < 1 then return 0 end

	local mats, occs = {}, {}
	for i = 1, n do
		local mx, ox = {}, {}
		local ii = i - 1
		local x = tx + (ii + 0.5) * RES
		for k = 1, ny do
			local my, oy = {}, {}
			local yc = y0 + (k - 0.5) * RES
			for j = 1, n do
				local jj = j - 1
				local h = g[ii][jj]
				local b = bot[ii][jj]
				local occ = 0
				local mat = AIR
				local hs = h - SURFACE_BIAS
				if yc + RES * 0.5 > b and yc - RES * 0.5 < hs then
					-- fractional fill at the surface gives a smooth top
					occ = math.clamp((hs - (yc - RES * 0.5)) / RES, 0, 1)
					-- and at the shell bottom, so the underside is not a hard plane
					local below = math.clamp(((yc + RES * 0.5) - b) / RES, 0, 1)
					occ = math.min(occ, below)
					if occ > 0.02 then
						if hs - yc < 7 then
							local z = tz + (jj + 0.5) * RES
							local slope = math.max(
								math.abs(g[ii + 1][jj] - g[ii - 1][jj]),
								math.abs(g[ii][jj + 1] - g[ii][jj - 1])) / (2 * RES)
							mat = F.material(x, z, h, slope)
						elseif h - yc < 40 then
							mat = Enum.Material.Rock
						else
							mat = Enum.Material.Basalt
						end
					else
						occ = 0
					end
				end
				my[j] = mat
				oy[j] = occ
			end
			mx[k] = my
			ox[k] = oy
		end
		mats[i] = mx
		occs[i] = ox
	end
	T:WriteVoxels(regionOf(tx, y0, tz, tx + size, y1, tz + size), RES, mats, occs)
	return n * ny * n
end

----------------------------------------------------------------------------------
-- CEILING
----------------------------------------------------------------------------------
-- The ceiling is ADDITIVE: it reads the tile back and only ever RAISES occupancy.
--
-- Two bugs came from the old write-everything version. It set AIR below the ceiling
-- line, which erased the top of the perimeter wall wherever wall and roof met in the
-- same tile; and it skipped any column whose ground came within 6 studs of the
-- ceiling, which left a ring of roofless "chimney" columns open to the void around
-- every place the floor rose to meet the roof. Reading first fixes both: solid stays
-- solid, and every non-fissure column gets a roof regardless of what is under it.
local function ceilTile(tx, tz, size)
	local n = size / RES
	local c, open = {}, {}
	local cmin, cmax = math.huge, -math.huge
	local any = false
	for i = 0, n - 1 do
		c[i], open[i] = {}, {}
		local x = tx + (i + 0.5) * RES
		for j = 0, n - 1 do
			local z = tz + (j + 0.5) * RES
			local ch = F.ceiling(x, z)
			c[i][j] = ch
			local o = not F.fissure(x, z)   -- ONLY a fissure may leave a column open
			open[i][j] = o
			if o then
				any = true
				if ch < cmin then cmin = ch end
				if ch > cmax then cmax = ch end
			end
		end
	end
	if not any then return 0 end

	local y0 = math.floor(cmin / RES) * RES
	local y1 = math.ceil((cmax + CEIL_THICK) / RES) * RES
	local ny = (y1 - y0) / RES
	if ny < 1 then return 0 end

	local region = regionOf(tx, y0, tz, tx + size, y1, tz + size)
	local mats, occs = T:ReadVoxels(region, RES)
	local written = 0
	for i = 1, n do
		local ii = i - 1
		local x = tx + (ii + 0.5) * RES
		for k = 1, ny do
			local yc = y0 + (k - 0.5) * RES
			for j = 1, n do
				local jj = j - 1
				if open[ii][jj] then
					local ch = c[ii][jj]
					local chs = ch + SURFACE_BIAS   -- same bias, so the roof hangs where Field says
					if yc + RES * 0.5 > chs and yc - RES * 0.5 < chs + CEIL_THICK then
						local occ = math.clamp(((yc + RES * 0.5) - chs) / RES, 0, 1)
						if occ > occs[i][k][j] + 0.02 then
							local z = tz + (jj + 0.5) * RES
							occs[i][k][j] = occ
							mats[i][k][j] = (yc - ch < 8) and F.ceilingMaterial(x, z) or Enum.Material.Basalt
							written = written + 1
						end
					end
				end
			end
		end
	end
	if written > 0 then T:WriteVoxels(region, RES, mats, occs) end
	return written
end

----------------------------------------------------------------------------------
-- WATER
----------------------------------------------------------------------------------
-- Terrain cannot hold water and solid in the SAME voxel, so this cannot be a simple
-- FillBlock: that would replace the riverbed with water and drain the river through
-- the floor. Instead each tile is read back, and only the voxels that came out EMPTY
-- below the water table are turned to water. The shoreline then lands wherever the
-- ground voxels stop, which is exactly where it should be.
local function waterTile(tx, tz, size)
	local n = size / RES
	-- cheap reject: does any part of this tile sit below the water table?
	local lowest = math.huge
	for i = 0, n, 2 do
		local x = tx + i * RES
		for j = 0, n, 2 do
			local z = tz + j * RES
			local g = F.ground(x, z, F.ceiling(x, z))
			if g < lowest then lowest = g end
		end
	end
	if lowest >= F.WATER - 0.5 then return 0 end

	local y0 = math.floor((lowest - 12) / RES) * RES
	local y1 = math.ceil((F.WATER + RES * 2) / RES) * RES
	if y1 <= y0 then return 0 end
	local region = regionOf(tx, y0, tz, tx + size, y1, tz + size)
	local mats, occs = T:ReadVoxels(region, RES)
	local ny = (y1 - y0) / RES
	local filled = 0
	-- Water may ONLY sit on top of the ground surface.
	--
	-- The first version filled every empty voxel under the water table, which included
	-- the hollow UNDER the terrain shell. That water then plugged real gaps in the
	-- shell from above, so the world looked closed while you could see straight down
	-- through the waterline into the void -- and it hid the gaps from a raycast test.
	local gcol = {}
	for i = 0, n - 1 do
		gcol[i] = {}
		local x = tx + (i + 0.5) * RES
		for j = 0, n - 1 do
			local z = tz + (j + 0.5) * RES
			gcol[i][j] = F.ground(x, z, F.ceiling(x, z))
		end
	end
	for i = 1, n do
		for k = 1, ny do
			local yc = y0 + (k - 0.5) * RES
			if yc - RES * 0.5 < F.WATER then
				for j = 1, n do
					if occs[i][k][j] < 0.02 and yc > gcol[i - 1][j - 1] then
						-- fractional at the surface so the waterline is flat, not stepped
						local o = math.clamp((F.WATER - (yc - RES * 0.5)) / RES, 0, 1)
						if o > 0.02 then
							mats[i][k][j] = Enum.Material.Water
							occs[i][k][j] = o
							filled = filled + 1
						end
					end
				end
			end
		end
	end
	if filled > 0 then T:WriteVoxels(region, RES, mats, occs) end
	return filled
end

function Terra.water(x0, x1, size)
	size = size or 64
	local half = F.HALF
	local z0 = -math.ceil(half / size) * size
	local z1 = math.ceil(half / size) * size
	local total, wet = 0, 0
	local t0 = os.clock()
	for tx = x0, x1 - size, size do
		for tz = z0, z1 - size, size do
			local f = waterTile(tx, tz, size)
			if f > 0 then wet = wet + 1 end
			total = total + f
		end
	end
	return string.format("water x=%d..%d : %d wet tiles, %.2fM voxels, %.1fs", x0, x1, wet, total / 1e6, os.clock() - t0)
end

-- Build a band of tiles. x0/x1 are LOCAL x bounds; the band covers the full z extent.
function Terra.band(x0, x1, which, size)
	size = size or 64
	local half = F.HALF
	local z0 = -math.ceil(half / size) * size
	local z1 = math.ceil(half / size) * size
	local total, tiles = 0, 0
	local t0 = os.clock()
	for tx = x0, x1 - size, size do
		for tz = z0, z1 - size, size do
			if which == "floor" then
				total = total + floorTile(tx, tz, size)
			else
				total = total + ceilTile(tx, tz, size)
			end
			tiles = tiles + 1
		end
	end
	return string.format("%s band x=%d..%d : %d tiles, %.2fM voxels, %.1fs",
		which, x0, x1, tiles, total / 1e6, os.clock() - t0)
end

-- FillBlock caps at ~4.2M studs^3 per call ("Extents are too large"), so the clear
-- runs as a grid of 160-stud cubes rather than one world-sized box.
----------------------------------------------------------------------------------
-- VERIFICATION
----------------------------------------------------------------------------------
-- Raycasts are the WRONG tool for auditing this world and produced two rounds of
-- false results: a ray that starts inside terrain returns nil (reads as a hole that
-- is not there), and a ray stops on water (reads as solid ground that is not there).
-- This reads the voxels instead, which cannot be fooled.
--
-- For every column it walks DOWN from the surface and UP from the ceiling looking for
-- a continuous run of solid, non-water material. A column that has no such run is a
-- genuine hole from the cavern into the void.
-- `stride` is in VOXELS (1 = audit every column). It used to be in studs and was
-- tested with `x % step == 0`, but column centres are always 2 mod 4, so that
-- condition was never true and the audit silently checked nothing.
function Terra.verify(x0, x1, stride, minRun)
	stride = stride or 2
	minRun = minRun or 10
	local half = F.HALF
	local floorHoles, roofHoles, checked = {}, {}, 0
	local SIZE = 64
	local n = SIZE / RES
	for tx = x0, x1 - SIZE, SIZE do
		for tz = -math.ceil(half / SIZE) * SIZE, math.ceil(half / SIZE) * SIZE - SIZE, SIZE do
			-- floor band for this tile
			local gmin, gmax, cmin, cmax = math.huge, -math.huge, math.huge, -math.huge
			local g, c = {}, {}
			for i = 0, n - 1 do
				g[i], c[i] = {}, {}
				for j = 0, n - 1 do
					local x, z = tx + (i + 0.5) * RES, tz + (j + 0.5) * RES
					local ch = F.ceiling(x, z)
					local h = F.ground(x, z, ch)
					g[i][j], c[i][j] = h, ch
					if h < gmin then gmin = h end
					if h > gmax then gmax = h end
					if ch < cmin then cmin = ch end
					if ch > cmax then cmax = ch end
				end
			end
			-- Deep enough to see BELOW a carve. At gmin-18 the window stopped above the
			-- rock under a plunge pool or a road cutting, so every carved column read as
			-- a hole that was not there.
			local fy0 = math.floor((gmin - minRun - 150) / RES) * RES
			local fy1 = math.ceil((gmax + 8) / RES) * RES
			local fm, fo = T:ReadVoxels(regionOf(tx, fy0, tz, tx + SIZE, fy1, tz + SIZE), RES)
			local cy0 = math.floor((cmin - 8) / RES) * RES
			local cy1 = math.ceil((cmax + CEIL_THICK + 8) / RES) * RES
			local cm, co = T:ReadVoxels(regionOf(tx, cy0, tz, tx + SIZE, cy1, tz + SIZE), RES)
			local fny, cny = (fy1 - fy0) / RES, (cy1 - cy0) / RES

			for i = 0, n - 1 do
				for j = 0, n - 1 do
					local x, z = tx + (i + 0.5) * RES, tz + (j + 0.5) * RES
					if i % stride == 0 and j % stride == 0 and g[i][j] < c[i][j] - 4 then
						checked = checked + 1
						-- FLOOR: find the topmost solid voxel actually present in this column
						-- (which may be a carved road bed or pool floor well below
						-- Field.ground), then require solid rock continuously beneath it.
						local run, best = 0, 0
						local started = false
						for k = fny, 1, -1 do
							local mm = fm[i + 1][k][j + 1]
							local solid = fo[i + 1][k][j + 1] > 0.35 and mm ~= Enum.Material.Water and mm ~= AIR
							if solid then
								started = true
								run = run + RES
								if run > best then best = run end
							elseif started then
								run = 0
							end
						end
						if best < minRun then floorHoles[#floorHoles + 1] = {x, z, g[i][j], best} end
						-- ROOF: continuous solid run upward from the ceiling line
						if not F.fissure(x, z) then
							local run2, best2 = 0, 0
							for k = 1, cny do
								local yc = cy0 + (k - 0.5) * RES
								if yc >= c[i][j] - RES then
									local mm = cm[i + 1][k][j + 1]
									if co[i + 1][k][j + 1] > 0.35 and mm ~= Enum.Material.Water and mm ~= AIR then
										run2 = run2 + RES
										if run2 > best2 then best2 = run2 end
									else
										run2 = 0
									end
								end
							end
							if best2 < minRun then roofHoles[#roofHoles + 1] = {x, z, c[i][j], best2} end
						end
					end
				end
			end
		end
	end
	return checked, floorHoles, roofHoles
end

----------------------------------------------------------------------------------
-- RESEAL
----------------------------------------------------------------------------------
-- Anything that CARVES the world after the terrain is written -- road cuts, plunge
-- pools, spillways, canal trenches -- can cut deeper than the shell is thick and
-- open a hole into the hollow underneath. Re-running the floor pass would repair it
-- but would also undo the carve (it regenerates from Field.ground, so it fills the
-- road cutting back in).
--
-- This instead works from the terrain AS IT NOW STANDS: for each column it finds the
-- topmost solid voxel and guarantees a run of solid rock beneath it, filling only
-- voxels that are currently Air. Carved shapes are preserved; holes are closed.
function Terra.reseal(x0, x1, thickness)
	thickness = thickness or 44
	local SIZE = 64
	local n = SIZE / RES
	local half = F.HALF
	local filled, cols = 0, 0
	for tx = x0, x1 - SIZE, SIZE do
		for tz = -math.ceil(half / SIZE) * SIZE, math.ceil(half / SIZE) * SIZE - SIZE, SIZE do
			local gmin, gmax = math.huge, -math.huge
			for i = 0, n - 1 do
				for j = 0, n - 1 do
					local x, z = tx + (i + 0.5) * RES, tz + (j + 0.5) * RES
					local h = F.ground(x, z, F.ceiling(x, z))
					if h < gmin then gmin = h end
					if h > gmax then gmax = h end
				end
			end
			-- deep enough to see the floor of a carved plunge pool
			local y0 = math.floor((gmin - thickness - 110) / RES) * RES
			local y1 = math.ceil((gmax + 8) / RES) * RES
			local ny = (y1 - y0) / RES
			if ny > 0 then
				local region = regionOf(tx, y0, tz, tx + SIZE, y1, tz + SIZE)
				local mats, occs = T:ReadVoxels(region, RES)
				local dirty = false
				for i = 1, n do
					for j = 1, n do
						-- A POOL FLOOR NEEDS ROCK UNDER IT TOO. Pools carved into a hillside
						-- can cut deeper than the ~42-stud shell and bottom out in the hollow
						-- beneath it, leaving the water hanging over its own excavation. So
						-- the lowest water voxel counts as a surface to be underpinned.
						local lowWater
						for k = 1, ny do
							if mats[i][k][j] == Enum.Material.Water and occs[i][k][j] > 0.2 then lowWater = k break end
						end
						if lowWater then
							local need = math.ceil(thickness / RES)
							for k = lowWater - 1, math.max(lowWater - need, 1), -1 do
								local mm = mats[i][k][j]
								if (mm == AIR or occs[i][k][j] < 0.35) and mm ~= Enum.Material.Water then
									mats[i][k][j] = Enum.Material.Rock
									occs[i][k][j] = 1
									filled = filled + 1
									dirty = true
								end
							end
						end
						-- topmost solid, non-water voxel in this column
						local topK
						for k = ny, 1, -1 do
							local mm = mats[i][k][j]
							if occs[i][k][j] > 0.35 and mm ~= AIR and mm ~= Enum.Material.Water then
								topK = k break
							end
						end
						if topK then
							cols = cols + 1
							local need = math.ceil(thickness / RES)
							for k = topK - 1, math.max(topK - need, 1), -1 do
								local mm = mats[i][k][j]
								if mm == AIR or occs[i][k][j] < 0.35 then
									if mm ~= Enum.Material.Water then
										mats[i][k][j] = Enum.Material.Rock
										occs[i][k][j] = 1
										filled = filled + 1
										dirty = true
									end
								end
							end
						end
					end
				end
				if dirty then T:WriteVoxels(region, RES, mats, occs) end
			end
		end
	end
	return string.format("reseal x=%d..%d : %d columns, %d voxels filled", x0, x1, cols, filled)
end

function Terra.clearAll()
	local half = F.HALF + 40
	local S = 160
	local n = 0
	for x = -half, half - 1, S do
		for z = -half, half - 1, S do
			for y = -160, 900, S do
				T:FillBlock(CFrame.new(ORIGIN + Vector3.new(x + S / 2, y + S / 2, z + S / 2)),
					Vector3.new(S, S, S), AIR)
				n = n + 1
			end
		end
	end
	return "cleared " .. n .. " blocks"
end

return Terra
