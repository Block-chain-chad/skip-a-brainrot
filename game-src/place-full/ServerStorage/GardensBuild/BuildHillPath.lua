-- BuildHillPath -- the Pilgrim Way, from Aelunmyr up to the Verdant Sanctum.
--
-- Not a staircase. It spirals most of the way round the hill (about 300 degrees,
-- roughly 1900 studs of walking to gain 230 studs of height, so ~7 degrees average)
-- which turns the climb into a journey with a different view off every stretch --
-- the town, the river, the cascade, the far wall -- before it arrives at the foot of
-- the cathedral's great stair.
--
-- The hillside is ~40 degrees across the path's width, so every segment gets a
-- retaining wall on the downhill side that reaches the real ground. Without it the
-- outer half of the road hangs in the air the whole way up.

local T = workspace.Terrain
local L = require(script.Parent.Lib)
local F = require(script.Parent.Field)
local A = require(script.Parent.Arch)
local P = require(script.Parent.Props)
local C = require(script.Parent.Creature)
local Fl = require(script.Parent.Flora)

local M = {}
local HX, HZ = F.HILL.X, F.HILL.Y

local function g(x, z) return F.ground(x, z, F.ceiling(x, z)) end

-- A FULL CIRCUIT. At a 302-degree sweep ending at radius 252 the path finished on the
-- far side of the plateau, 263 studs from the cathedral's great stair with nothing
-- joining them -- the two paths simply did not meet. Sweeping the whole 360 and
-- ending at radius 300 brings the walker back round to the stair's foot at (30,-580),
-- so the spiral delivers you to the bottom step of the cathedral stair.
local START_DEG, SWEEP = 92, 360
local R0, R1 = 470, 300
local WIDTH = 24
-- Where the Sanctum Overflow comes down the hill (55 degrees). A full circuit must
-- cross it, so the road bridges the cascade instead of damming it.
local CROSS_DEG, CROSS_HALF = 55, 9
-- How high the deck humps over the cascade. Combined with the plunge pool the water
-- pass is cut into (17 studs down), this gives ~30 studs of clearance, so the stream
-- runs UNDER the bridge instead of through the deck.
local CROSS_RISE = 13

local function pathAt(u)
	local deg = START_DEG + SWEEP * u
	local r = L.lerp(R0, R1, u)
	local a = math.rad(deg)
	return HX + math.cos(a) * r, HZ + math.sin(a) * r, a, r
end

function M.run()
	local root = workspace.GameWorld.LushGardens
	local hp = root.HillPath
	hp:ClearAllChildren()
	local rng = Random.new(4242)
	local road = L.folder(hp, "Road")
	local decor = L.folder(hp, "Decor")

	local N = 210
	local prev, prevY
	local climbed, length = 0, 0
	for i = 0, N do
		local u = i / N
		local x, z, a, r = pathAt(u)
		local gy = g(x, z)
		-- tangent, for orienting the slabs
		local x2, z2 = pathAt(math.min(u + 1 / N, 1))
		local dx, dz = x2 - x, z2 - z
		-- At u = 1 the look-ahead clamps to the same point, so the tangent is zero and
		-- CFrame.lookAt returns a NaN frame -- which Terrain:FillBlock rejects outright
		-- ("Extents cannot be empty"). Fall back to the direction we arrived from.
		if math.abs(dx) < 1e-6 and math.abs(dz) < 1e-6 and prev then
			dx, dz = x - prev.x, z - prev.z
		end
		if math.abs(dx) < 1e-6 and math.abs(dz) < 1e-6 then dx, dz = 1, 0 end
		local tl = math.max(math.sqrt(dx * dx + dz * dz), 0.001)
		local tx, tz = dx / tl, dz / tl
		-- outward normal (downhill, away from the hill centre)
		local ox, oz = math.cos(a), math.sin(a)

		-- angular distance to the cascade crossing
		local degNow = (START_DEG + SWEEP * u) % 360
		local dCross = math.abs((degNow - CROSS_DEG + 180) % 360 - 180)
		local bridging = dCross < CROSS_HALF

		if prev then
			local segLen = math.sqrt((x - prev.x) ^ 2 + (z - prev.z) ^ 2)
			length = length + segLen
			climbed = climbed + math.max(gy - prevY, 0)
			-- smooth hump across the crossing window so the road ramps up and over
			local hump = bridging and (CROSS_RISE * (1 - (dCross / CROSS_HALF) ^ 2)) or 0
			local cf = CFrame.lookAt(L.wv(x, gy + 1.4 + hump, z), L.wv(x + tx, gy + 1.4 + hump, z + tz))
			if bridging then
				-- span the cascade rather than cutting through it: deck, parapets, and
				-- an arch ring underneath so it reads as a real bridge from below
				L.box(road, "BridgeDeck", cf, Vector3.new(WIDTH, 2.4, segLen + 1.5), L.C.PaleStone, L.M.Stone, {solid = true})
				L.box(road, "BridgeArch", cf * CFrame.new(0, -3.2, 0), Vector3.new(WIDTH * 0.8, 4.5, segLen + 1.5), L.C.WeatheredStone, L.M.Stone, {shadow = false})
				-- abutments down to the ground at the ends of the span
				if dCross > CROSS_HALF * 0.72 then
					L.box(road, "BridgeAbutment", cf * CFrame.new(0, -(hump + 8) / 2 - 1, 0),
						Vector3.new(WIDTH + 4, hump + 10, segLen + 1.5), L.C.GreyStone, L.M.Stone, {solid = true})
				end
				for _, s in ipairs({1, -1}) do
					L.box(road, "BridgeParapet", cf * CFrame.new(s * (WIDTH / 2 - 0.8), 2.6, 0),
						Vector3.new(1.6, 3.2, segLen + 1.5), L.C.PaleStone, L.M.Stone, {solid = true})
				end
			else

			-- CUT THE SHELF FIRST. The hillside runs at about 40 degrees, so a 24-stud
			-- road laid flat on it has its uphill half inside the hill -- the mountain
			-- clipped straight through the walkway. Carving the notch before laying the
			-- slab is what makes this a road cut into the hill rather than a plank
			-- resting against it.
			if segLen > 0.5 and not bridging then
				T:FillBlock(cf * CFrame.new(0, 27, 0), Vector3.new(WIDTH + 15, 54, segLen + 9), Enum.Material.Air)
				-- THEN PUT ROCK BACK UNDER IT. The hill's terrain is a ~42-stud shell, so
				-- cutting a 54-stud notch into it goes clean through into the hollow
				-- underneath -- the first carve opened 292 holes in the hillside.
				-- Backfilling below the deck reseals the shell and gives the road
				-- something solid to stand on.
				T:FillBlock(cf * CFrame.new(0, -23, 0), Vector3.new(WIDTH + 15, 46, segLen + 9), Enum.Material.Rock)
			end
			L.box(road, "PathSlab", cf, Vector3.new(WIDTH, 3.0, segLen + 1.5),
				P.jitterCol(L.C.WeatheredStone, rng, 16), L.M.Cobble, {solid = true})
			-- RETAINING WALL on the downhill side, down to the ground it stands over
			local ex, ez = x + ox * (WIDTH / 2), z + oz * (WIDTH / 2)
			local eg = g(ex, ez)
			local wallH = math.max(gy + 1.4 - eg, 0) + 6
			L.box(road, "Retaining", CFrame.lookAt(L.wv(ex, gy + 1.4 - wallH / 2 + 1, ez), L.wv(ex + tx, gy + 1.4 - wallH / 2 + 1, ez + tz)),
				Vector3.new(4.5, wallH, segLen + 1.5), L.C.GreyStone, L.M.Stone, {solid = true})
			-- kerb on top of it
			L.box(road, "Kerb", CFrame.lookAt(L.wv(ex, gy + 3.4, ez), L.wv(ex + tx, gy + 3.4, ez + tz)),
				Vector3.new(3.0, 2.0, segLen + 1.5), L.C.PaleStone, L.M.Stone, {solid = true})
			-- cut face on the uphill side, so the road reads as carved into the hill
			local ix, iz = x - ox * (WIDTH / 2 + 2), z - oz * (WIDTH / 2 + 2)
			local ig = g(ix, iz)
			if ig > gy + 2 then
				L.box(road, "CutFace", CFrame.lookAt(L.wv(ix, gy + (ig - gy) / 2, iz), L.wv(ix + tx, gy + (ig - gy) / 2, iz + tz)),
					Vector3.new(3.0, ig - gy + 4, segLen + 1.5), L.C.GreyStone, L.M.Rough, {solid = true})
			end
			-- steps where the grade steepens
			if gy - prevY > 3.2 then
				A.stairs(road, L.wv(prev.x, prevY + 1.4, prev.z), L.wv(x, gy + 1.4, z), WIDTH - 3,
					{stepH = 1.6, color = L.C.PaleStone, mat = L.M.Stone, drop = 5})
			end
			end   -- close the `if bridging ... else` branch
		end
		prev, prevY = {x = x, z = z}, gy

		-- ===== furnishing the way =====
		if i % 7 == 0 and i > 0 then
			local ex, ez = x + ox * (WIDTH / 2 + 3), z + oz * (WIDTH / 2 + 3)
			P.lampPost(decor, L.wv(ex, gy + 2, ez), 13, {color = L.C.GlowCyan, brightness = 2.2, range = 34})
		end
		if i % 11 == 5 then
			local ix, iz = x - ox * (WIDTH / 2 + 8), z - oz * (WIDTH / 2 + 8)
			local k = (i // 11) % 4
			if k == 0 then
				Fl.tree(decor, L.wv(ix, g(ix, iz) - 1, iz), {seed = i, height = rng:NextNumber(38, 58),
					bloom = rng:NextNumber() < 0.4 and L.C.GlowPink or nil, vines = 3})
			elseif k == 1 then
				Fl.flowerPatch(decor, L.wv(ix, g(ix, iz), iz), {seed = i, radius = 7, count = 9,
					colors = {L.C.GlowPink, L.C.GlowCyan, L.C.GlowGold}})
			elseif k == 2 then
				Fl.fern(decor, L.wv(ix, g(ix, iz), iz), {seed = i, fronds = 8, height = rng:NextNumber(5, 10)})
			else
				Fl.crystals(decor, L.wv(ix, g(ix, iz), iz), {seed = i, count = 4, spread = 5, color = L.C.GlowCyan})
			end
		end
	end

	----------------------------------------------------------------- landings
	-- Overlooks, shrines and statues at intervals: places to stop and look out.
	local stations = {
		{u = 0.10, kind = "overlook"},
		{u = 0.22, kind = "shrine"},
		{u = 0.34, kind = "statue", style = "stag"},
		{u = 0.46, kind = "overlook"},
		{u = 0.58, kind = "ruin"},
		{u = 0.70, kind = "statue", style = "wolf"},
		{u = 0.82, kind = "shrine"},
		{u = 0.92, kind = "overlook"},
	}
	for si, st in ipairs(stations) do
		local x, z, a, r = pathAt(st.u)
		local gy = g(x, z)
		local ox, oz = math.cos(a), math.sin(a)
		if st.kind == "overlook" then
			-- a balcony pushed out over the drop, carried on corbels
			local px, pz = x + ox * (WIDTH / 2 + 16), z + oz * (WIDTH / 2 + 16)
			local pg = g(px, pz)
			L.box(decor, "OverlookDeck", L.wcf(px, gy + 1.4, pz) * CFrame.Angles(0, -a, 0),
				Vector3.new(34, 3.0, 26), L.C.PaleStone, L.M.Stone, {solid = true})
			L.box(decor, "OverlookPier", L.wcf(px, gy - (gy - pg) / 2 - 1, pz) * CFrame.Angles(0, -a, 0),
				Vector3.new(22, math.max(gy - pg, 4) + 6, 16), L.C.GreyStone, L.M.Stone, {solid = true})
			local pts = {}
			for k = -3, 3 do
				local ang = -a + k * 0.22
				pts[#pts + 1] = L.wv(px + math.cos(ang + a) * 0, gy + 2.9, pz) + Vector3.new(math.cos(-a) * k * 5, 0, math.sin(-a) * k * 5)
			end
			A.railing(decor, {L.wv(px - math.sin(a) * 15, gy + 2.9, pz + math.cos(a) * 15),
				L.wv(px + ox * 10, gy + 2.9, pz + oz * 10),
				L.wv(px + math.sin(a) * 15, gy + 2.9, pz - math.cos(a) * 15)},
				{height = 3.6, spacing = 4, color = L.C.PaleStone, postDia = 0.9})
			P.lampPost(decor, L.wv(px, gy + 2.9, pz), 14, {color = L.C.GlowGold, brightness = 2.4, range = 36})
			P.bench(decor, L.wcf(px - ox * 8, gy + 2.9, pz - oz * 8) * CFrame.Angles(0, -a + math.pi, 0), {width = 10})
		elseif st.kind == "shrine" then
			local px, pz = x - ox * (WIDTH / 2 + 14), z - oz * (WIDTH / 2 + 14)
			local sg = g(px, pz)
			L.box(decor, "ShrineBase", L.wcf(px, sg + 1.5, pz) * CFrame.Angles(0, -a, 0), Vector3.new(20, 3, 20), L.C.WeatheredStone, L.M.Stone, {solid = true})
			for _, sx in ipairs({-1, 1}) do
				for _, sz in ipairs({-1, 1}) do
					A.column(decor, L.wcf(px + sx * 7, sg + 3, pz + sz * 7), 18, 3, {color = L.C.PaleStone, mat = L.M.Stone, fluted = true})
				end
			end
			L.box(decor, "ShrineRoof", L.wcf(px, sg + 22.5, pz) * CFrame.Angles(0, -a, 0), Vector3.new(22, 2, 22), L.C.PaleStone, L.M.Stone, {solid = true})
			A.spire(decor, L.wcf(px, sg + 23.5, pz), 8, 20, {segs = 10, color = L.C.DeepStone, mat = L.M.Stone, finialColor = L.C.Gold})
			P.carving(decor, L.wcf(px, sg + 11, pz) * CFrame.Angles(0, -a + math.pi, 0), 9, 13, {glow = L.C.GlowCyan, seed = si})
			L.glow(decor, "ShrineLight", L.wcf(px, sg + 12, pz), Vector3.new(3, 4, 3), L.C.GlowCyan, 3.0, 44, "blob")
			for _, sx in ipairs({-1, 1}) do
				P.brazier(decor, L.wv(px + math.sin(a) * 13 * sx, sg + 3, pz - math.cos(a) * 13 * sx), {fire = L.C.GlowCyan})
			end
		elseif st.kind == "statue" then
			local px, pz = x - ox * (WIDTH / 2 + 13), z - oz * (WIDTH / 2 + 13)
			local sg = g(px, pz)
			local topY = C.pedestal(decor, L.wv(px, sg, pz), 18, 18, 11, {seed = si * 3, glow = L.C.GlowCyan})
			local mo = C.quadruped(decor, CFrame.new(L.wv(px, 0, pz).X, L.ORIGIN.Y + topY, L.wv(px, 0, pz).Z) * CFrame.Angles(0, -a + math.pi, 0),
				1.4, {style = st.style, seed = si * 7, eyeGlow = L.C.GlowGold})
			C.weather(mo, {seed = si * 5, amount = 0.3, vines = 3})
		else -- ruin
			local px, pz = x - ox * (WIDTH / 2 + 18), z - oz * (WIDTH / 2 + 18)
			local sg = g(px, pz)
			for k = 1, 6 do
				local ra = rng:NextNumber(0, 6.283)
				local rr = rng:NextNumber(4, 18)
				local bx, bz = px + math.cos(ra) * rr, pz + math.sin(ra) * rr
				local bg = g(bx, bz)
				local hgt = rng:NextNumber(6, 26)
				A.column(decor, L.wcf(bx, bg, bz), hgt, rng:NextNumber(2.5, 4.5),
					{color = L.C.WeatheredStone, mat = L.M.Stone, trimColor = L.C.MossStone})
				if rng:NextNumber() < 0.5 then
					L.box(decor, "FallenBlock", L.wcf(bx + rng:NextNumber(-8, 8), bg + 1.5, bz + rng:NextNumber(-8, 8))
						* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6), rng:NextNumber(-0.3, 0.3)),
						Vector3.new(rng:NextNumber(4, 9), 3, rng:NextNumber(4, 9)), L.C.MossStone, L.M.Stone, {solid = true})
				end
			end
			Fl.bush(decor, L.wv(px, sg, pz), {seed = si, radius = 8})
		end
	end

	local parts = 0
	for _, d in ipairs(hp:GetDescendants()) do if d:IsA("BasePart") then parts = parts + 1 end end
	return string.format("Pilgrim Way: %.0f studs long, climbs %.0f studs (avg %.1f deg), %d stations, %d parts",
		length, climbed, math.deg(math.atan(climbed / math.max(length, 1))), #stations, parts)
end

return M
