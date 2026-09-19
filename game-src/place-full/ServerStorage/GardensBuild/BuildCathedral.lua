-- BuildCathedral -- the Verdant Sanctum, on the plateau at the top of the hill.
--
-- The primary landmark of World 3: it has to read from the hub 1600 studs away, so
-- it is built at cathedral scale rather than house scale -- a 200x300 stud footprint,
-- a 104-stud nave, twin west towers, and a crossing spire whose tip stands ~270
-- studs above the plateau (about 610 above the cavern floor).
--
-- Plan runs along Z: the west front and its stair face SOUTH (+Z) toward the town and
-- the path up, the apse closes the NORTH (-Z) end.
--   x +/-32  nave arcade walls, 104 tall
--   x +/-56  aisle outer walls, 58 tall, lean-to roofs up to the nave
--   z +100   west front, twin towers
--   z -100   crossing into the apse
--   transept arms are closed gabled boxes crossing at z = -30

local L = require(script.Parent.Lib)
local F = require(script.Parent.Field)
local A = require(script.Parent.Arch)
local P = require(script.Parent.Props)
local Fl = require(script.Parent.Flora)

local M = {}
local T = workspace.Terrain

local CX, CZ = F.HILL.X, F.HILL.Y

local STONE   = L.C.PaleStone
local STONE2  = L.C.ElvenStone
local TRIM    = Color3.fromRGB(232, 230, 214)
local DARK    = L.C.DeepStone
local ROOF    = Color3.fromRGB(62, 74, 78)
local MAT     = L.M.Stone

local GLASS = {L.C.GlowCyan, L.C.GlowGold, L.C.GlowPink, L.C.GlowGreen, L.C.GlowBlue, L.C.GlowMagenta}

local function g(x, z) return F.ground(x, z, F.ceiling(x, z)) end

-- wall + its glazing in one call, so an opening can never be left unglazed
local function glazedWall(m, cf, len, h, t, openings, opts)
	opts = opts or {}
	A.wall(m, cf, len, h, t, {openings = openings, color = opts.color or STONE, mat = MAT,
		trimColor = opts.trim or TRIM, name = opts.name or "Wall", slices = opts.slices or 14})
	for i, o in ipairs(openings) do
		if o.glaze ~= false then
			A.traceryWindow(m, cf * CFrame.new(o.x, o.sill, 0), o.w, o.h, o.rise or 0, {
				colors = GLASS, mullions = o.mullions or 2, seed = i * 3 + (opts.seed or 0),
				stoneColor = opts.trim or TRIM, transparency = 0.18,
				lightColor = GLASS[(i % #GLASS) + 1], lightBrightness = 2.6, lightRange = 46,
			})
		end
	end
end

function M.run()
	local root = workspace.GameWorld.LushGardens
	local cath = root.Cathedral
	cath:ClearAllChildren()
	local rng = Random.new(77777)

	-- plateau height under the cathedral
	local baseY = 0
	do
		local s, n = 0, 0
		for dx = -90, 90, 30 do for dz = -140, 140, 30 do
			s = s + g(CX + dx, CZ + dz); n = n + 1
		end end
		baseY = s / n
	end
	local O = CFrame.new(L.wv(CX, baseY, CZ))    -- cathedral origin, on the plateau

	----------------------------------------------------------------- platform + moat
	local plat = L.folder(cath, "Platform")
	-- a broad stepped terrace, so the building stands on something
	for i, s in ipairs({{116, 186, 0}, {108, 176, 4.5}, {100, 168, 9}}) do
		L.box(plat, "Terrace", O * CFrame.new(0, s[3] - 2, -10), Vector3.new(s[1] * 2, 5.5, s[2] * 2),
			i == 3 and STONE2 or L.C.WeatheredStone, MAT, {solid = true})
	end
	local PY = 9 + 0.75      -- finished floor level above baseY
	-- water channel around the foundation, carved into the plateau
	for i = 0, 71 do
		local a = math.rad(i * 5)
		local rx, rz = 132 + math.cos(a * 3) * 6, 202 + math.sin(a * 2) * 8
		local px, pz = CX + math.cos(a) * rx, CZ - 10 + math.sin(a) * rz
		T:FillBlock(CFrame.new(L.wv(px, baseY - 2, pz)), Vector3.new(22, 12, 22), Enum.Material.Air)
		T:FillBlock(CFrame.new(L.wv(px, baseY - 3.4, pz)), Vector3.new(19, 6, 19), Enum.Material.Water)
	end

	----------------------------------------------------------------- the great stair
	local stair = L.folder(cath, "GreatStair")
	do
		local top = (O * CFrame.new(0, PY, 196)).Position
		local footZ = 300
		local footY = g(CX, CZ + footZ) + 1
		local topY = top.Y - L.ORIGIN.Y

		-- CUT THE STAIR INTO THE HILL.
		-- The stair climbs in a straight line from the foot (y~304) to the terrace
		-- (y~344), but the hill between them bulges ABOVE that line -- it reaches 337 by
		-- z=-660. Laid straight onto the ground the middle of the flight ended up as
		-- much as 11 studs INSIDE the hillside, so the stair vanished into the slope and
		-- the Pilgrim Way appeared to run straight over the top of it.
		-- Carve the trench, then backfill beneath it so the shell stays closed.
		for i = 0, 30 do
			local t = i / 30
			local z = (CZ + footZ) + ((CZ + 196) - (CZ + footZ)) * t
			local y = footY + (topY - footY) * t
			-- the trench floor sits 4 studs BELOW the tread line; cutting from above it
			-- left a couple of studs of hillside still standing over the treads
			T:FillBlock(CFrame.new(L.wv(CX, y + 30, z)), Vector3.new(96, 68, 14), Enum.Material.Air)
			T:FillBlock(CFrame.new(L.wv(CX, y - 27, z)), Vector3.new(96, 46, 14), Enum.Material.Rock)
		end

		A.stairs(stair, L.wv(CX, footY, CZ + footZ), top, 70,
			{stepH = 2.0, color = STONE2, mat = MAT, drop = 10, cheeks = true, cheekColor = L.C.WeatheredStone})
		-- flanking balustrades and lamps
		for _, s in ipairs({-1, 1}) do
			local pts = {}
			for k = 0, 8 do
				local t = k / 8
				local z = CZ + footZ + (196 - footZ) * t
				local y = L.lerp(g(CX, CZ + footZ) + 1, baseY + PY, t)
				pts[#pts + 1] = L.wv(CX + s * 38, y, z)
			end
			A.railing(stair, pts, {height = 4.0, spacing = 6, color = STONE2, postDia = 1.2, railW = 2.2})
			for k = 0, 4 do
				local t = k / 4
				local z = CZ + footZ + (196 - footZ) * t
				local y = L.lerp(g(CX, CZ + footZ) + 1, baseY + PY, t)
				P.lampPost(stair, L.wv(CX + s * 46, y, z), 16, {color = L.C.GlowCyan, brightness = 2.4, range = 40})
			end
		end
	end

	----------------------------------------------------------------- floor
	local shell = L.folder(cath, "Shell")
	L.box(shell, "Floor", O * CFrame.new(0, PY - 1.5, 0), Vector3.new(120, 3, 210), L.C.WeatheredStone, L.M.Marble, {solid = true})
	L.box(shell, "ApseFloor", O * CFrame.new(0, PY - 1.5, -128), Vector3.new(70, 3, 60), L.C.WeatheredStone, L.M.Marble, {solid = true})

	local FY = PY          -- interior floor level
	local NAVE_H = 104
	local AISLE_H = 58
	local NAVE_HALF, AISLE_HALF = 32, 56

	----------------------------------------------------------------- aisle outer walls
	for _, sx in ipairs({-1, 1}) do
		local openings = {}
		for i = 1, 7 do
			local z = -84 + i * 21
			openings[#openings + 1] = {x = z, w = 13, sill = 14, h = 22, rise = 15, mullions = 2}
		end
		local cf = O * CFrame.new(sx * AISLE_HALF, FY, 0) * CFrame.Angles(0, sx * math.pi / 2, 0)
		glazedWall(shell, cf, 200, AISLE_H, 4.5, openings, {seed = sx > 0 and 1 or 9, name = "AisleWall"})
		-- buttresses between the windows
		for i = 0, 7 do
			local z = -95 + i * 27
			L.box(shell, "Buttress", O * CFrame.new(sx * (AISLE_HALF + 4), FY + AISLE_H * 0.45, z),
				Vector3.new(9, AISLE_H * 0.9, 8), STONE, MAT, {solid = true})
			L.box(shell, "ButtressCap", O * CFrame.new(sx * (AISLE_HALF + 4), FY + AISLE_H * 0.9 + 1, z),
				Vector3.new(11, 2, 10), TRIM, MAT, {shadow = false})
			A.spire(shell, O * CFrame.new(sx * (AISLE_HALF + 4), FY + AISLE_H * 0.9 + 2, z), 3.4, 16,
				{segs = 9, color = ROOF, mat = MAT, finial = false})
			-- gargoyle-ish creature corbels
			if i % 2 == 0 then
				local gc = O * CFrame.new(sx * (AISLE_HALF + 9), FY + AISLE_H * 0.86, z)
				L.blob(shell, "Gargoyle", gc, Vector3.new(4.5, 3.4, 7), L.C.GreyStone, MAT, {collide = false, shadow = false})
				L.blob(shell, "GargoyleHead", gc * CFrame.new(sx * 2.6, 0.6, 0), Vector3.new(3.4, 3.0, 3.6), L.C.GreyStone, MAT, {collide = false, shadow = false})
				for _, w in ipairs({1, -1}) do
					L.blob(shell, "GargoyleWing", gc * CFrame.new(0, 2.4, w * 2.6) * CFrame.Angles(w * 0.5, 0, 0),
						Vector3.new(3, 5, 1.2), L.C.GreyStone, MAT, {collide = false, shadow = false})
				end
			end
		end
	end

	----------------------------------------------------------------- nave arcade walls (clerestory above)
	for _, sx in ipairs({-1, 1}) do
		local openings = {}
		-- arcade arches at ground level, opening into the aisles
		for i = 1, 7 do
			local z = -84 + i * 21
			openings[#openings + 1] = {x = z, w = 15, sill = 0, h = 26, rise = 14, glaze = false}
		end
		-- clerestory windows high up
		for i = 1, 7 do
			local z = -84 + i * 21
			openings[#openings + 1] = {x = z, w = 11, sill = 66, h = 18, rise = 12, mullions = 1}
		end
		local cf = O * CFrame.new(sx * NAVE_HALF, FY, 0) * CFrame.Angles(0, sx * math.pi / 2, 0)
		glazedWall(shell, cf, 200, NAVE_H, 5.0, openings, {seed = sx > 0 and 3 or 7, name = "NaveWall", slices = 16})
	end

	----------------------------------------------------------------- aisle lean-to roofs
	for _, sx in ipairs({-1, 1}) do
		local run = AISLE_HALF - NAVE_HALF + 4
		local rise = 74 - AISLE_H
		local ang = math.atan2(rise, run)
		local len = math.sqrt(run * run + rise * rise)
		L.box(shell, "AisleRoof",
			O * CFrame.new(sx * (NAVE_HALF + run / 2 - 2), FY + AISLE_H + rise / 2, 0) * CFrame.Angles(0, 0, -sx * ang),
			Vector3.new(len + 3, 2.0, 206), ROOF, MAT, {solid = true})
		-- close the two ends of the lean-to so it is not an open lean-to tunnel
		for _, sz in ipairs({-1, 1}) do
			A.gableFill(shell, O * CFrame.new(sx * (NAVE_HALF + run / 2 - 2), FY + AISLE_H, sz * 100),
				len, 3.0, function(xx) return rise * (0.5 + xx / len * sx * sz * 0) + rise * 0.5 end, STONE, MAT, 6)
		end
	end

	----------------------------------------------------------------- nave roof
	A.roofPitched(shell, O * CFrame.new(0, FY + NAVE_H, 0), 200, NAVE_HALF * 2 + 4, 46, {
		color = ROOF, mat = MAT, thick = 2.2, overhang = 3.5,
		gableColor = STONE, gableThick = 5.0, ridgeColor = TRIM, trimColor = TRIM,
	})
	for i = 0, 24 do
		L.box(shell, "Cresting", O * CFrame.new(0, FY + NAVE_H + 49, -100 + i * 8.4), Vector3.new(1.2, 4.5, 1.0), TRIM, MAT, {shadow = false})
	end

	----------------------------------------------------------------- apse (polygonal north end)
	do
		local n = 5
		local r = 46
		local apseZ = -100
		for i = 0, n - 1 do
			local a = math.rad(180 + (i + 0.5) * (180 / n))
			local px, pz = math.cos(a) * r, apseZ + math.sin(a) * r * 0.9
			local arc = 2 * math.pi * r / (n * 2) * 1.35
			local cf = O * CFrame.new(px, FY, pz) * CFrame.Angles(0, -a + math.pi / 2, 0)
			glazedWall(shell, cf, arc, 92, 4.5,
				{{x = 0, w = arc * 0.42, sill = 20, h = 34, rise = 22, mullions = 3}},
				{seed = i * 5, name = "ApseWall"})
			L.box(shell, "ApseButtress", O * CFrame.new(px * 1.12, FY + 44, pz + (pz - apseZ) * 0.12),
				Vector3.new(8, 88, 8), STONE, MAT, {solid = true})
		end
		-- half-cone roof over the apse
		for i = 0, 9 do
			local t = i / 9
			L.post(shell, "ApseRoof", O * CFrame.new(0, FY + 92 + t * 34, apseZ), 4.0, (r * 2.1) * (1 - t * 0.92), ROOF, MAT, {solid = true})
		end
		A.spire(shell, O * CFrame.new(0, FY + 126, apseZ), 6, 40, {segs = 12, color = ROOF, mat = MAT, curve = 1.2, finialColor = L.C.Gold})
	end

	----------------------------------------------------------------- transept arms
	for _, sx in ipairs({-1, 1}) do
		local armLen = 56
		local armW = 54
		local cxm = sx * (AISLE_HALF + armLen / 2)
		local h = 88
		-- closed box: outer end wall, two side walls, and a gabled roof
		local endCF = O * CFrame.new(sx * (AISLE_HALF + armLen), FY, -30) * CFrame.Angles(0, sx * math.pi / 2, 0)
		glazedWall(shell, endCF, armW, h, 5.0,
			{{x = 0, w = 30, sill = 24, h = 34, rise = 26, mullions = 3}},
			{seed = sx > 0 and 11 or 13, name = "TranseptEnd"})
		for _, sz in ipairs({-1, 1}) do
			local sideCF = O * CFrame.new(cxm, FY, -30 + sz * armW / 2) * CFrame.Angles(0, sz > 0 and 0 or math.pi, 0)
			glazedWall(shell, sideCF, armLen + 2, h, 4.5,
				{{x = -armLen * 0.22, w = 12, sill = 20, h = 24, rise = 16, mullions = 1},
				 {x = armLen * 0.22, w = 12, sill = 20, h = 24, rise = 16, mullions = 1}},
				{seed = sx * 2 + sz, name = "TranseptSide"})
		end
		A.roofPitched(shell, O * CFrame.new(cxm, FY + h, -30) * CFrame.Angles(0, math.pi / 2, 0), armW, armLen + 4, 30, {
			color = ROOF, mat = MAT, thick = 2.0, overhang = 3.0,
			gableColor = STONE, gableThick = 5.0, ridgeColor = TRIM,
		})
		-- rose window in the transept gable
		local rc = endCF * CFrame.new(0, h + 12, 0)
		L.cyl(shell, "RoseFrame", rc * CFrame.Angles(0, math.rad(90), 0), 5.0, 30, TRIM, MAT, {solid = true})
		for k = 0, 11 do
			local a = math.rad(k * 30)
			L.box(shell, "RoseSpoke", rc * CFrame.new(math.cos(a) * 7.5, math.sin(a) * 7.5, 0) * CFrame.Angles(0, 0, a),
				Vector3.new(15, 1.6, 5.4), TRIM, MAT, {shadow = false})
			L.glow(shell, "RosePane", rc * CFrame.new(math.cos(a) * 10.5, math.sin(a) * 10.5, 0.6),
				Vector3.new(5.5, 5.5, 1.2), GLASS[(k % #GLASS) + 1], 1.4, 26, "blob")
		end
		L.glow(shell, "RoseHeart", rc * CFrame.new(0, 0, 0.6), Vector3.new(7, 7, 1.4), L.C.GlowGold, 2.6, 44, "blob")
	end

	----------------------------------------------------------------- crossing spire
	do
		local cy = FY + NAVE_H + 46
		local r = 26
		for i = 0, 7 do
			local a = math.rad(i * 45)
			L.box(shell, "LanternPier", O * CFrame.new(math.cos(a) * r, cy + 26, -30 + math.sin(a) * r) * CFrame.Angles(0, -a, 0),
				Vector3.new(6, 52, 8), STONE, MAT, {solid = true})
			L.glow(shell, "LanternLight", O * CFrame.new(math.cos(a) * (r - 3), cy + 30, -30 + math.sin(a) * (r - 3)),
				Vector3.new(3, 30, 3), GLASS[(i % #GLASS) + 1], 1.6, 40)
		end
		L.post(shell, "CrossingBase", O * CFrame.new(0, cy + 12, -30), 26, r * 2.3, STONE, MAT, {solid = true})
		L.post(shell, "CrossingCap", O * CFrame.new(0, cy + 54, -30), 5, r * 2.5, TRIM, MAT, {solid = true})
		A.spire(shell, O * CFrame.new(0, cy + 56, -30), r * 1.15, 118,
			{segs = 26, color = ROOF, mat = MAT, curve = 1.35, finialColor = L.C.Gold})
		L.glow(shell, "SpireBeacon", O * CFrame.new(0, cy + 178, -30), Vector3.new(7, 7, 7), L.C.GlowCyan, 6, 220, "blob")
	end

	----------------------------------------------------------------- west front + twin towers
	do
		local wz = 100
		local doorW, doorH, doorRise = 30, 44, 26
		local frontCF = O * CFrame.new(0, FY, wz)
		local openings = {
			{x = 0, w = doorW, sill = 0, h = doorH, rise = doorRise, glaze = false},
			{x = -40, w = 12, sill = 18, h = 22, rise = 15, mullions = 1},
			{x = 40, w = 12, sill = 18, h = 22, rise = 15, mullions = 1},
		}
		glazedWall(shell, frontCF, 118, 126, 6.0, openings, {seed = 21, name = "WestFront", slices = 18})
		-- the great doors
		L.box(shell, "GreatDoor", frontCF * CFrame.new(0, doorH / 2, 1.2), Vector3.new(doorW + 0.6, doorH + 0.4, 1.6),
			L.C.Wood, Enum.Material.WoodPlanks, {solid = true})
		for i = 1, 5 do
			L.box(shell, "DoorBand", frontCF * CFrame.new(0, doorH * i / 6, 2.1), Vector3.new(doorW, 1.4, 0.6), L.C.Iron, Enum.Material.Metal, {shadow = false})
		end
		L.box(shell, "DoorMullion", frontCF * CFrame.new(0, doorH / 2, 2.1), Vector3.new(1.6, doorH, 0.7), L.C.Iron, Enum.Material.Metal, {shadow = false})
		-- tympanum over the doors
		do
			local prof = A.archProfile(doorW, doorRise)
			for i = 0, 13 do
				local x = -doorW / 2 + (i + 0.5) * (doorW / 14)
				local hgt = prof(x)
				if hgt > 0.05 then
					L.box(shell, "Tympanum", frontCF * CFrame.new(x, doorH + hgt / 2, 0), Vector3.new(doorW / 14 + 0.08, hgt, 6.0), STONE, MAT, {solid = true})
				end
			end
			L.glow(shell, "DoorSigil", frontCF * CFrame.new(0, doorH + doorRise * 0.42, 3.2), Vector3.new(14, 9, 0.8), L.C.GlowGold, 2.6, 46, "blob")
		end
		-- the great rose window
		local rc = frontCF * CFrame.new(0, 88, 0)
		L.cyl(shell, "RoseFrame", rc * CFrame.Angles(0, math.rad(90), 0), 6.5, 52, TRIM, MAT, {solid = true})
		for ring = 1, 2 do
			local n = ring == 1 and 8 or 16
			local rr = ring == 1 and 9 or 18
			for k = 0, n - 1 do
				local a = math.rad(k * 360 / n)
				L.box(shell, "RoseSpoke", rc * CFrame.new(math.cos(a) * rr, math.sin(a) * rr, 0) * CFrame.Angles(0, 0, a),
					Vector3.new(rr * 1.1, 1.8, 7.0), TRIM, MAT, {shadow = false})
				L.glow(shell, "RosePane", rc * CFrame.new(math.cos(a) * (rr + 4), math.sin(a) * (rr + 4), 0.8),
					Vector3.new(6.5, 6.5, 1.4), GLASS[(k % #GLASS) + 1], 1.5, 30, "blob")
			end
		end
		L.glow(shell, "RoseHeart", rc * CFrame.new(0, 0, 0.8), Vector3.new(11, 11, 1.6), L.C.GlowGold, 3.2, 60, "blob")
		-- gable above the front
		A.gableFill(shell, frontCF * CFrame.new(0, 126, 0), 118, 6.0,
			function(x) return math.max(0, 40 * (1 - math.abs(x) / 59)) end, STONE, MAT, 22)

		-- twin towers
		for _, sx in ipairs({-1, 1}) do
			local tx = sx * 74
			local tH = 196
			local tR = 22
			for i = 0, 7 do
				local a = math.rad(i * 45)
				local wcf = O * CFrame.new(tx + math.cos(a) * tR, FY, wz + 6 + math.sin(a) * tR) * CFrame.Angles(0, -a + math.pi / 2, 0)
				local ops = {}
				if i % 2 == 0 then
					for tier = 1, 4 do
						ops[#ops + 1] = {x = 0, w = 8, sill = 40 + (tier - 1) * 38, h = 20, rise = 13, mullions = 1}
					end
				end
				glazedWall(shell, wcf, 2 * math.pi * tR / 8 * 1.28, tH, 5.0, ops, {seed = i + (sx > 0 and 30 or 40), name = "TowerWall", slices = 8})
			end
			-- string courses and a solid cap
			for tier = 1, 4 do
				local y = tier * 42
				if y < tH - 8 then
					L.post(shell, "TowerBand", O * CFrame.new(tx, FY + y, wz + 6), 3.0, tR * 2.32, TRIM, MAT, {solid = true})
				end
			end
			L.post(shell, "TowerCap", O * CFrame.new(tx, FY + tH + 1.5, wz + 6), 4.0, tR * 2.4, STONE, MAT, {solid = true})
			for i = 0, 15 do
				local a = math.rad(i * 22.5)
				L.box(shell, "Merlon", O * CFrame.new(tx + math.cos(a) * (tR + 1), FY + tH + 6, wz + 6 + math.sin(a) * (tR + 1)) * CFrame.Angles(0, -a, 0),
					Vector3.new(2.6, 8, 5), TRIM, MAT, {shadow = false})
				if i % 4 == 0 then
					A.spire(shell, O * CFrame.new(tx + math.cos(a) * (tR + 1), FY + tH + 10, wz + 6 + math.sin(a) * (tR + 1)), 3.0, 22,
						{segs = 9, color = ROOF, mat = MAT, finial = false})
				end
			end
			A.spire(shell, O * CFrame.new(tx, FY + tH + 3, wz + 6), tR * 1.05, 92,
				{segs = 22, color = ROOF, mat = MAT, curve = 1.3, finialColor = L.C.Gold})
			L.glow(shell, "TowerBeacon", O * CFrame.new(tx, FY + tH + 60, wz + 6), Vector3.new(5, 5, 5),
				sx > 0 and L.C.GlowCyan or L.C.GlowGold, 4.5, 170, "blob")
		end
	end

	----------------------------------------------------------------- flying buttresses
	for _, sx in ipairs({-1, 1}) do
		for i = 0, 6 do
			local z = -84 + i * 28
			local a = O * CFrame.new(sx * (AISLE_HALF + 4), FY + AISLE_H + 4, z)
			local b = O * CFrame.new(sx * (NAVE_HALF + 3), FY + NAVE_H - 16, z)
			local mid = (a.Position + b.Position) / 2 + Vector3.new(0, 16, 0)
			-- the arc of the flyer
			local prev
			for k = 0, 8 do
				local t = k / 8
				local p = L.spline({a.Position, mid, b.Position}, t)
				if prev then
					L.beam(shell, "Flyer", prev, p, 4.0, 5.0, STONE, MAT, {solid = true})
				end
				prev = p
			end
			L.box(shell, "FlyerCap", CFrame.new(mid + Vector3.new(0, 2, 0)), Vector3.new(5, 3, 5), TRIM, MAT, {shadow = false})
		end
	end

	----------------------------------------------------------------- interior
	local inside = L.folder(cath, "Interior")
	for _, sx in ipairs({-1, 1}) do
		for i = 1, 7 do
			local z = -84 + i * 21
			A.column(inside, O * CFrame.new(sx * (NAVE_HALF - 3), FY, z), 40, 7,
				{color = STONE2, mat = MAT, trimColor = TRIM, fluted = true})
		end
	end
	-- altar and sanctuary light
	L.box(inside, "AltarStep", O * CFrame.new(0, FY + 1.5, -104), Vector3.new(52, 3, 34), STONE2, L.M.Marble, {solid = true})
	L.box(inside, "Altar", O * CFrame.new(0, FY + 7, -112), Vector3.new(24, 8, 12), TRIM, L.M.Marble, {solid = true})
	L.glow(inside, "AltarLight", O * CFrame.new(0, FY + 16, -112), Vector3.new(6, 9, 6), L.C.GlowGold, 4.0, 90, "blob")
	for _, sx in ipairs({-1, 1}) do
		P.brazier(inside, (O * CFrame.new(sx * 20, FY, -96)).Position, {fire = L.C.GlowCyan})
	end
	-- hanging banners down the nave
	for i = 1, 7 do
		local z = -84 + i * 21
		for _, sx in ipairs({-1, 1}) do
			P.banner(inside, O * CFrame.new(sx * (NAVE_HALF - 6), FY + 58, z) * CFrame.Angles(0, sx > 0 and 0 or math.pi, 0),
				9, 22, {color = GLASS[(i % 3) + 1] == L.C.GlowPink and L.C.ClothPink or L.C.ClothTeal, trim = L.C.Gold})
		end
	end
	-- glowing floor sigil at the crossing
	for k = 0, 23 do
		local a = math.rad(k * 15)
		L.glow(inside, "FloorRune", O * CFrame.new(math.cos(a) * 22, FY + 0.4, -30 + math.sin(a) * 22) * CFrame.Angles(0, -a, 0),
			Vector3.new(7, 0.3, 1.4), L.C.GlowCyan, 0.5, 12)
	end

	----------------------------------------------------------------- weathering
	local nature = L.folder(cath, "Nature")
	for i = 1, 46 do
		local a = rng:NextNumber(0, 6.283)
		local rr = rng:NextNumber(70, 150)
		local px, pz = CX + math.cos(a) * rr, CZ - 10 + math.sin(a) * rr * 1.3
		local gy = g(px, pz)
		if gy > baseY - 30 then
			if i % 3 == 0 then
				Fl.tree(nature, L.wv(px, gy - 1, pz), {seed = i * 9, height = rng:NextNumber(40, 62),
					bloom = rng:NextNumber() < 0.4 and L.C.GlowPink or nil, vines = 3})
			elseif i % 3 == 1 then
				Fl.bush(nature, L.wv(px, gy, pz), {seed = i * 5, radius = rng:NextNumber(4, 9)})
			else
				Fl.flowerPatch(nature, L.wv(px, gy, pz), {seed = i * 7, radius = 7, count = 8,
					colors = {L.C.GlowPink, L.C.GlowCyan, L.C.GlowGold}})
			end
		end
	end
	-- vines down the towers and buttresses
	for i = 1, 26 do
		local sx = rng:NextNumber() < 0.5 and -1 or 1
		local px = sx * rng:NextNumber(AISLE_HALF, AISLE_HALF + 14)
		local pz = rng:NextNumber(-100, 100)
		P.vine(nature, (O * CFrame.new(px, FY + rng:NextNumber(20, AISLE_H), pz)).Position,
			rng:NextNumber(12, 40), {seed = i * 3, leafColor = L.C.LeafDark,
			glow = rng:NextNumber() < 0.3 and L.C.GlowGreen or nil})
	end

	-- Folder has no GetBoundingBox, so measure the extents from the parts themselves
	local parts = 0
	local mn = Vector3.new(math.huge, math.huge, math.huge)
	local mx = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, d in ipairs(cath:GetDescendants()) do
		if d:IsA("BasePart") then
			parts = parts + 1
			local p, s = d.Position, d.Size
			mn = Vector3.new(math.min(mn.X, p.X - s.X / 2), math.min(mn.Y, p.Y - s.Y / 2), math.min(mn.Z, p.Z - s.Z / 2))
			mx = Vector3.new(math.max(mx.X, p.X + s.X / 2), math.max(mx.Y, p.Y + s.Y / 2), math.max(mx.Z, p.Z + s.Z / 2))
		end
	end
	return string.format("Verdant Sanctum: %.0f wide x %.0f long, spire tip %.0f above the cavern floor (plateau %.0f), %d parts",
		mx.X - mn.X, mx.Z - mn.Z, mx.Y - L.ORIGIN.Y, baseY, parts)
end

return M
