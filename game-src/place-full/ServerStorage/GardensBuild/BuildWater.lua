-- BuildWater -- every vertical water feature in World 3.
--
-- THE SOURCE RULE. Water does not appear out of a hillside. Every fall in this world
-- now starts in a real body of terrain water, carved and filled at its head, and you
-- can walk to the pool it spills out of. The first version hung 22 waterfalls off bare
-- rock with nothing feeding any of them.
--
-- THE CLEARANCE RULE. A fall must not pass through built geometry. The three cascades
-- that used to run down the hill face were laid at fixed X positions while the Pilgrim
-- Way spirals 302 degrees around the same hill, so they cut straight through the road
-- -- one of them intersected 37 steps and 22 paving slabs. The hill now carries ONE
-- cascade, in the 34-80 degree sector the path does not occupy, fed by the overflow of
-- the cathedral's own foundation moat.

local L = require(script.Parent.Lib)
local F = require(script.Parent.Field)
local W = require(script.Parent.Water)

local M = {}
local T = workspace.Terrain

local function g(x, z) return F.ground(x, z, F.ceiling(x, z)) end

-- Carves a basin and fills it so its surface sits at waterY. Kept shallow relative to
-- the local shell depth so it cannot punch through into the hollow under the terrain.
-- Returns the water surface height it actually used.
--
-- THE RIM RULE. The surface must sit BELOW the lowest point of the basin's rim. A
-- horizontal slab of water dropped on a 40-degree hillside spills out of the downhill
-- side and hangs in mid-air as a floating blue block -- which is exactly how the first
-- version of the Sanctum Overflow's plunge pools looked. Sampling the rim and taking
-- its minimum keeps every pool inside the ground that holds it.
local function sourcePool(x, z, waterY, radius, depth)
	depth = depth or 11
	local minRim = math.huge
	for a = 0, 330, 30 do
		local px = x + math.cos(math.rad(a)) * (radius + 3)
		local pz = z + math.sin(math.rad(a)) * (radius + 3)
		minRim = math.min(minRim, g(px, pz))
	end
	waterY = math.min(waterY, minRim - 2.5)
	-- The carve must bottom out at EXACTLY the water's floor. Carving 10 studs deeper
	-- than the fill (as this did at first) leaves a void directly under every pool, so
	-- the water hangs over its own excavation -- the floating blue slabs on the hill.
	local floorY = waterY - depth
	local topY = waterY + 6
	T:FillCylinder(CFrame.new(L.wv(x, (floorY + topY) * 0.5, z)), topY - floorY, radius + 4, Enum.Material.Air)
	T:FillCylinder(CFrame.new(L.wv(x, waterY - depth * 0.5, z)), depth, radius, Enum.Material.Water)
	return waterY
end

-- A short channel from a pool to the lip, so the water reads as flowing to the edge.
-- A RETAINING RIM around a pool.
--
-- Cutting a basin into a slope leaves the downhill face of the water exposed -- you
-- see the side of the water block standing out of the hill. Rock backfill fixes what
-- is UNDER the water but not what is in FRONT of it. This walls the basin, which also
-- makes the cascade read as a chain of carved elven basins rather than raw puddles.
local function basinRim(parent, x, z, waterY, radius)
	local n = 18
	for i = 0, n - 1 do
		local a = math.rad(i * 360 / n)
		local px, pz = x + math.cos(a) * (radius + 2), z + math.sin(a) * (radius + 2)
		local gy = g(px, pz)
		-- tall enough to reach from the ground outside up past the water surface
		local top = waterY + 2.5
		local bot = math.min(gy, waterY) - 10
		L.box(parent, "BasinRim", L.wcf(px, (top + bot) * 0.5, pz) * CFrame.Angles(0, -a, 0),
			Vector3.new(5.5, top - bot, 2 * math.pi * (radius + 2) / n * 1.3),
			L.C.WeatheredStone, L.M.Stone, {solid = true})
		L.box(parent, "BasinCap", L.wcf(px, top + 0.6, pz) * CFrame.Angles(0, -a, 0),
			Vector3.new(7.0, 1.2, 2 * math.pi * (radius + 2) / n * 1.3),
			L.C.PaleStone, L.M.Stone, {shadow = false})
	end
end

-- A channel from a pool to the lip. Same rim rule: the channel bed is cut BELOW the
-- surrounding ground along its whole length so the water runs in a groove.
local function spillway(x0, z0, x1, z1, waterY, halfW)
	local steps = math.max(2, math.ceil(math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2) / 6))
	for i = 0, steps do
		local t = i / steps
		local px, pz = x0 + (x1 - x0) * t, z0 + (z1 - z0) * t
		local side = math.min(g(px + halfW + 3, pz), g(px - halfW - 3, pz), g(px, pz + halfW + 3), g(px, pz - halfW - 3))
		local wy = math.min(waterY, side - 2)
		T:FillBlock(CFrame.new(L.wv(px, wy + 5, pz)), Vector3.new(halfW * 2 + 6, 18, halfW * 2 + 6), Enum.Material.Air)
		T:FillBlock(CFrame.new(L.wv(px, wy - 3, pz)), Vector3.new(halfW * 2, 8, halfW * 2), Enum.Material.Water)
	end
end

function M.run()
	local root = workspace.GameWorld.LushGardens
	local waterF = root.Water
	waterF:ClearAllChildren()
	local log, made, sources = {}, 0, 0

	-- ===== 1. THE GREAT CASCADE =================================================
	-- Falls through the roof fissure in the west. Its source is a sheet of water lying
	-- ON TOP of the cavern roof, draining through the crack -- visible from below as
	-- water brimming at the rim of the opening.
	do
		local cx, cz = F.CASCADE.X, F.CASCADE.Y
		local lipX = cx - 46
		local ceil = F.ceiling(lipX, cz)
		-- The reservoir must clear the roof shell across its WHOLE footprint. The roof
		-- domes by 200+ studs near the cascade, so offsetting from a single sample point
		-- still cut into the shell wherever the ceiling rose higher than that sample.
		-- Take the maximum ceiling over the footprint and sit above that.
		local maxCh = -math.huge
		for sx = -150, 150, 25 do
			for sz = -200, 200, 25 do
				local c = F.ceiling(cx - 10 + sx, cz - 30 + sz)
				if c > maxCh then maxCh = c end
			end
		end
		local resY = maxCh + 46          -- clear of the 34-stud shell everywhere
		T:FillBlock(CFrame.new(L.wv(cx - 10, resY + 14, cz - 30)), Vector3.new(300, 30, 400), Enum.Material.Air)
		T:FillBlock(CFrame.new(L.wv(cx - 10, resY, cz - 30)), Vector3.new(288, 16, 388), Enum.Material.Water)
		sources = sources + 1
		local top = L.wv(lipX, ceil + 10, cz)
		local bot = L.wv(cx + 24, F.WATER, cz + 8)
		W.waterfall(waterF, top, bot, 108, {
			name = "GreatCascade", seed = 101, flare = 1.5, streaks = 48,
			lightBrightness = 3.2, lightColor = Color3.fromRGB(186, 232, 240),
		})
		made = made + 1
		log[#log + 1] = string.format("GreatCascade %.0f studs -- fed by a reservoir on top of the roof, draining through the fissure", (top - bot).Magnitude)
		-- The ribbon drains the SAME reservoir through the same fissure, so it starts at
		-- the reservoir surface. Started at the local ceiling instead it hung 40 studs
		-- below the water it was supposed to be coming out of.
		W.waterfall(waterF, L.wv(cx - 20, resY, cz + 128),
			L.wv(cx + 40, F.WATER, cz + 118), 32,
			{name = "CascadeRibbon", seed = 117, flare = 1.7, lightBrightness = 1.8})
		made = made + 1
	end

	-- ===== 2. THE WEEPING CLIFFS ================================================
	-- One tarn on the shelf top feeds the whole row; each fall spills off its rim.
	do
		local cx, cz = F.WEEPING.X, F.WEEPING.Y
		local shelfY = g(cx, cz)
		local tarnY = shelfY - 3
		-- the lake on top of the shelf
		for ring = 0, 2 do
			local rr = 52 + ring * 40
			T:FillCylinder(CFrame.new(L.wv(cx, tarnY + 3, cz)), 26, rr, Enum.Material.Air)
			T:FillCylinder(CFrame.new(L.wv(cx, tarnY - 5, cz)), 11, rr - 6, Enum.Material.Water)
		end
		sources = sources + 1
		log[#log + 1] = string.format("Weeping Cliffs: a tarn of radius ~126 on the shelf at y=%.0f feeds all 7 falls", tarnY)
		local facing = math.atan2(0 - cz, 0 - cx)
		for i, o in ipairs({-1.05, -0.72, -0.40, -0.10, 0.20, 0.52, 0.86}) do
			local a = facing + o
			local dx, dz = math.cos(a), math.sin(a)
			local lx, lz = cx + dx * 158, cz + dz * 158
			-- cut the notch the water leaves through, and connect it to the tarn
			spillway(cx + dx * 96, cz + dz * 96, lx, lz, tarnY, 9)
			local top = L.wv(lx, tarnY, lz)
			local bx, bz = cx + dx * 254, cz + dz * 254
			local bot = L.wv(bx, math.max(g(bx, bz), F.WATER), bz)
			if (top.Y - bot.Y) > 40 then
				W.waterfall(waterF, top, bot, 12 + (i % 3) * 7,
					{name = "WeepingFall" .. i, seed = 200 + i * 7, flare = 1.4, lightBrightness = 1.5})
				made = made + 1
			end
		end
	end

	-- ===== 3. INTO THE ROOTWAY RAVINE ===========================================
	-- Springs on the ravine shoulders, falling into the flooded chasm below.
	do
		local ang = math.atan2(F.ROOTWAY_B.Y - F.ROOTWAY_A.Y, F.ROOTWAY_B.X - F.ROOTWAY_A.X) + math.pi / 2
		for i, p in ipairs({{760, -370, 1}, {880, -520, -1}, {990, -680, 1}}) do
			local px, pz, side = p[1], p[2], p[3]
			local ox, oz = math.cos(ang) * 96 * side, math.sin(ang) * 96 * side
			local lx, lz = px + ox, pz + oz
			local lipY = g(lx, lz) - 2
			-- spring pool set back from the edge, spilling toward it
			local sx, sz = px + ox * 1.5, pz + oz * 1.5
			lipY = sourcePool(sx, sz, lipY, 26, 12)
			basinRim(waterF, sx, sz, lipY, 26)
			spillway(sx, sz, lx, lz, lipY, 8)
			sources = sources + 1
			local top = L.wv(lx, lipY, lz)
			local bot = L.wv(px + ox * 0.16, F.WATER, pz + oz * 0.16)
			if (top.Y - bot.Y) > 40 then
				W.waterfall(waterF, top, bot, 16,
					{name = "RavineFall" .. i, seed = 300 + i * 11, flare = 1.5, lightBrightness = 1.6})
				made = made + 1
			end
		end
	end

	-- ===== 4. THE SANCTUM OVERFLOW ==============================================
	-- The cathedral's foundation moat brims over on its east side and falls down the
	-- hill to the valley floor. Placed at 55 degrees round the hill, inside the only
	-- sector the Pilgrim Way (92 -> 34 degrees) and the great stair do not occupy.
	do
		local HX, HZ = F.HILL.X, F.HILL.Y
		local a = math.rad(55)
		local dx, dz = math.cos(a), math.sin(a)
		-- The Pilgrim Way now sweeps a full circuit, so it MUST cross this cascade. It
		-- crosses at radius ~317 (angle 55 falls at u=0.897 along the path, r = 470-170u).
		-- A pool is placed exactly there and cut deep, so the road bridges it with real
		-- clearance instead of the water running through the deck.
		local CROSS_R = 317
		local pts = {}
		local radii = {214, 300, CROSS_R, 392, 486, 582, 690}
		for _, r in ipairs(radii) do
			local px, pz = HX + dx * r, HZ + dz * r
			local deep = (r == CROSS_R) and 17 or 2      -- sink the pool under the bridge
			pts[#pts + 1] = {px, pz, g(px, pz) - deep, deep}
		end
		-- basin at the head, level with the moat
		pts[1][3] = sourcePool(pts[1][1], pts[1][2], pts[1][3], 30, 12)
		basinRim(waterF, pts[1][1], pts[1][2], pts[1][3], 30)
		sources = sources + 1
		for i = 1, #pts - 1 do
			local A, B = pts[i], pts[i + 1]
			local rad = B[4] > 8 and 30 or 22
			B[3] = sourcePool(B[1], B[2], B[3], rad, B[4] > 8 and 20 or 10)
			basinRim(waterF, B[1], B[2], B[3], rad)
			W.waterfall(waterF, L.wv(A[1], A[3], A[2]), L.wv(B[1], B[3], B[2]), 15,
				{name = "SanctumOverflow" .. i, seed = 700 + i * 13, flare = 1.3, lightBrightness = 1.6})
			made = made + 1
		end
		log[#log + 1] = string.format("Sanctum Overflow: %d steps from the cathedral moat down the hill's east flank (55 deg -- clear of the Pilgrim Way)", #pts - 1)
	end

	-- ===== 5. OFF THE FUNGAL HOLLOW RIM =========================================
	do
		local cx, cz = F.FUNGAL.X, F.FUNGAL.Y
		for i, a in ipairs({2.5, 4.1, 5.6}) do
			local lx, lz = cx + math.cos(a) * 296, cz + math.sin(a) * 296
			local lipY = g(lx, lz) - 2
			local sx, sz = cx + math.cos(a) * 330, cz + math.sin(a) * 330
			lipY = sourcePool(sx, sz, lipY, 24, 11)
			basinRim(waterF, sx, sz, lipY, 24)
			spillway(sx, sz, lx, lz, lipY, 8)
			sources = sources + 1
			local bx, bz = cx + math.cos(a) * 198, cz + math.sin(a) * 198
			local top = L.wv(lx, lipY, lz)
			local bot = L.wv(bx, math.max(g(bx, bz), F.WATER), bz)
			if (top.Y - bot.Y) > 30 then
				W.waterfall(waterF, top, bot, 11, {name = "HollowFall" .. i, seed = 500 + i * 13, lightBrightness = 1.4})
				made = made + 1
			end
		end
	end

	-- ===== 6. OUT OF THE PERIMETER WALL =========================================
	-- Groundwater emerging from the rock: each one gets an alcove cut into the wall
	-- with a pool in it, so you can see where it comes from.
	do
		for i, s in ipairs({
			{-620, -1180, 150}, {430, -1210, 170}, {1180, 620, 150},
			{-1200, -180, 190}, {760, 1130, 130}, {-980, 1180, 120},
		}) do
			local x, z, up = s[1], s[2], s[3]
			local d = Vector2.new(-x, -z)
			d = d.Magnitude > 1 and d.Unit or Vector2.new(0, 1)
			local lipY = g(x, z) + up
			-- the alcove is cut BACK into the wall, away from the cavern
			local ax, az = x - d.X * 26, z - d.Y * 26
			lipY = sourcePool(ax, az, lipY, 22, 12)
			basinRim(waterF, ax, az, lipY, 22)
			spillway(ax, az, x, z, lipY, 8)
			sources = sources + 1
			local bx, bz = x + d.X * 130, z + d.Y * 130
			local top = L.wv(x, lipY, z)
			local bot = L.wv(bx, math.max(g(bx, bz), F.WATER), bz)
			if (top.Y - bot.Y) > 60 then
				W.waterfall(waterF, top, bot, 18 + (i % 3) * 9,
					{name = "WallFall" .. i, seed = 600 + i * 19, flare = 1.6, lightBrightness = 1.8})
				made = made + 1
			end
		end
	end

	local parts = 0
	for _, d in ipairs(waterF:GetDescendants()) do if d:IsA("BasePart") then parts = parts + 1 end end
	return table.concat(log, "\n") .. string.format("\n%d falls, %d carved water sources, %d parts", made, sources, parts)
end

return M
