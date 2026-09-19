-- BuildTown -- Aelunmyr, the elven town on the skirt of the hill.
--
-- Deliberately SPARSE. The brief is architecture set into nature, not a dense city:
-- buildings sit apart from each other along one climbing street, with trees, roots,
-- streams and open ground between them. Roughly a third of the town's footprint is
-- built on; the rest is left as garden and rock.
--
-- Ground here climbs from about y=0 at the south edge to y=110 at the north, so every
-- building gets a levelled podium cut down to its lowest corner -- otherwise half of
-- them would float and the other half would be buried to the windows.

local L = require(script.Parent.Lib)
local F = require(script.Parent.Field)
local A = require(script.Parent.Arch)
local P = require(script.Parent.Props)
local H = require(script.Parent.House)
local Fl = require(script.Parent.Flora)

local M = {}
local T = workspace.Terrain

local function g(x, z) return F.ground(x, z, F.ceiling(x, z)) end

-- The street: a spline climbing from the river causeway up to the foot of the hill path.
local STREET = {
	Vector2.new(0, 40), Vector2.new(-18, -40), Vector2.new(-52, -118),
	Vector2.new(-40, -196), Vector2.new(6, -262), Vector2.new(48, -330),
	Vector2.new(26, -398), Vector2.new(-16, -452),
}

local function streetPoint(u)
	local n = #STREET
	local seg = math.clamp(math.floor(u * (n - 1)) + 1, 1, n - 1)
	local t = u * (n - 1) - (seg - 1)
	local p0 = STREET[math.max(seg - 1, 1)]
	local p1 = STREET[seg]
	local p2 = STREET[math.min(seg + 1, n)]
	local p3 = STREET[math.min(seg + 2, n)]
	local t2, t3 = t * t, t * t * t
	local x = 0.5 * ((2 * p1.X) + (-p0.X + p2.X) * t + (2 * p0.X - 5 * p1.X + 4 * p2.X - p3.X) * t2 + (-p0.X + 3 * p1.X - 3 * p2.X + p3.X) * t3)
	local z = 0.5 * ((2 * p1.Y) + (-p0.Y + p2.Y) * t + (2 * p0.Y - 5 * p1.Y + 4 * p2.Y - p3.Y) * t2 + (-p0.Y + 3 * p1.Y - 3 * p2.Y + p3.Y) * t3)
	return x, z
end

-- Levels a building pad: a stone podium reaching from the floor level down past the
-- lowest ground corner, so nothing ever floats on the slope.
local function podium(parent, cx, cz, w, d, rng)
	local hi, lo = -1e9, 1e9
	for _, c in ipairs({{-1, -1}, {1, -1}, {-1, 1}, {1, 1}, {0, 0}}) do
		local gy = g(cx + c[1] * w * 0.5, cz + c[2] * d * 0.5)
		hi = math.max(hi, gy); lo = math.min(lo, gy)
	end
	local floorY = hi + 0.5
	local depth = math.max(floorY - lo, 0) + 8
	L.box(parent, "Podium", L.wcf(cx, floorY - depth / 2, cz), Vector3.new(w + 7, depth, d + 7),
		P.jitterCol(L.C.GreyStone, rng, 12), L.M.Stone, {solid = true})
	L.box(parent, "PodiumCap", L.wcf(cx, floorY - 0.4, cz), Vector3.new(w + 8.4, 1.4, d + 8.4),
		L.C.WeatheredStone, L.M.Stone, {shadow = false})
	return floorY
end

function M.run()
	local root = workspace.GameWorld.LushGardens
	local town = root.Town
	town:ClearAllChildren()
	local rng = Random.new(31415)
	local built = {houses = 0, towers = 0, bridges = 0}

	----------------------------------------------------------------- the street
	local street = L.folder(town, "Street")
	local prevX, prevZ
	for i = 0, 150 do
		local u = i / 150
		local x, z = streetPoint(u)
		local y = g(x, z)
		if prevX then
			local a = L.wv(prevX, g(prevX, prevZ) + 1.1, prevZ)
			local b = L.wv(x, y + 1.1, z)
			local d = (b - a)
			if d.Magnitude > 0.4 then
				local cf = CFrame.lookAt((a + b) / 2, b)
				L.box(street, "StreetSlab", cf, Vector3.new(23, 2.6, d.Magnitude + 1.2),
					P.jitterCol(L.C.WeatheredStone, rng, 16), L.M.Cobble, {solid = true})
				-- kerbs
				for _, s in ipairs({1, -1}) do
					L.box(street, "Kerb", cf * CFrame.new(s * 12.0, 0.7, 0), Vector3.new(2.0, 2.6, d.Magnitude + 1.2),
						L.C.PaleStone, L.M.Stone, {solid = true})
				end
			end
		end
		prevX, prevZ = x, z
		-- lamps and greenery along the way
		if i % 12 == 0 and i > 0 then
			local nx, nz = streetPoint(math.min(u + 0.01, 1))
			local dx, dz = nx - x, nz - z
			local len = math.sqrt(dx * dx + dz * dz)
			if len > 0.01 then
				local px, pz = -dz / len, dx / len
				local side = (i % 24 == 0) and 1 or -1
				P.lampPost(street, L.wv(x + px * 15 * side, y + 1, z + pz * 15 * side), 13,
					{color = L.C.GlowGold, brightness = 2.0, range = 30})
				if i % 24 == 12 then
					Fl.flowerPatch(street, L.wv(x - px * 15 * side, y + 1, z - pz * 15 * side),
						{seed = i, radius = 6, count = 8, colors = {L.C.GlowPink, L.C.GlowCyan}})
				end
			end
		end
	end

	----------------------------------------------------------------- buildings
	local blocks = L.folder(town, "Buildings")
	-- Each entry: distance along the street (u), side (+1 right / -1 left), how far
	-- back from the kerb, and the building's character.
	local plots = {
		{u = 0.06, side = -1, back = 46, w = 30, d = 24, h = 26, curved = true,  balcony = true},
		{u = 0.13, side =  1, back = 52, w = 26, d = 28, h = 30, curved = false},
		{u = 0.22, side = -1, back = 62, w = 34, d = 26, h = 24, curved = true},
		{u = 0.29, side =  1, back = 44, w = 24, d = 22, h = 34, curved = true,  balcony = true},
		{u = 0.38, side = -1, back = 58, w = 28, d = 30, h = 28, curved = false},
		{u = 0.46, side =  1, back = 66, w = 32, d = 24, h = 26, curved = true},
		{u = 0.54, side = -1, back = 48, w = 22, d = 22, h = 36, curved = true,  balcony = true},
		{u = 0.62, side =  1, back = 56, w = 30, d = 28, h = 30, curved = false},
		{u = 0.71, side = -1, back = 70, w = 26, d = 24, h = 28, curved = true},
		{u = 0.79, side =  1, back = 46, w = 34, d = 30, h = 32, curved = true,  balcony = true},
		{u = 0.88, side = -1, back = 60, w = 24, d = 26, h = 26, curved = false},
		{u = 0.95, side =  1, back = 52, w = 28, d = 24, h = 30, curved = true},
	}
	local palettes = {
		{stone = L.C.ElvenStone, trim = L.C.PaleStone, roof = L.C.DarkStone},
		{stone = L.C.WarmStone,  trim = L.C.PaleStone, roof = L.C.DeepStone},
		{stone = L.C.WeatheredStone, trim = L.C.ElvenStone, roof = L.C.GreyStone},
		{stone = L.C.PaleStone,  trim = L.C.WarmStone, roof = L.C.DarkStone},
	}
	for i, pl in ipairs(plots) do
		local x, z = streetPoint(pl.u)
		local nx, nz = streetPoint(math.min(pl.u + 0.01, 1))
		local dx, dz = nx - x, nz - z
		local len = math.max(math.sqrt(dx * dx + dz * dz), 0.001)
		local px, pz = -dz / len, dx / len
		local bx = x + px * pl.back * pl.side
		local bz = z + pz * pl.back * pl.side
		local floorY = podium(blocks, bx, bz, pl.w, pl.d, rng)
		-- face the street
		local face = math.atan2(-px * pl.side, -pz * pl.side)
		local pal = palettes[(i % #palettes) + 1]
		H.elvenHouse(blocks, L.wcf(bx, floorY, bz) * CFrame.Angles(0, face, 0), {
			seed = 900 + i, width = pl.w, depth = pl.d, wallH = pl.h,
			curvedRoof = pl.curved, balcony = pl.balcony, chimney = (i % 3 ~= 0),
			stone = pal.stone, trim = pal.trim, roof = pal.roof,
			glass = {L.C.GlowGold, L.C.GlowCyan, L.C.GlowGreen, L.C.GlowPink},
			name = "House" .. i,
		})
		built.houses = built.houses + 1
		-- a garden wall and greenery on the plot, so buildings sit IN planting
		for k = 1, rng:NextInteger(2, 4) do
			local a = rng:NextNumber(0, 6.283)
			local rr = rng:NextNumber(pl.w * 0.7, pl.w * 1.2)
			local gx, gz = bx + math.cos(a) * rr, bz + math.sin(a) * rr
			if rng:NextNumber() < 0.55 then
				Fl.tree(blocks, L.wv(gx, g(gx, gz) - 1, gz), {seed = 1000 + i * 7 + k,
					height = rng:NextNumber(40, 66), bloom = rng:NextNumber() < 0.35 and L.C.GlowPink or nil,
					vines = 3, name = "TownTree"})
			else
				Fl.bush(blocks, L.wv(gx, g(gx, gz), gz), {seed = 1100 + i * 7 + k, radius = rng:NextNumber(4, 8),
					berries = rng:NextNumber() < 0.3 and L.C.GlowCyan or nil})
			end
		end
	end

	----------------------------------------------------------------- towers
	local towers = L.folder(town, "Towers")
	for i, t in ipairs({
		{x = -190, z = -150, r = 11, h = 62},
		{x = 150,  z = -232, r = 10, h = 54},
		{x = -150, z = -352, r = 12, h = 70},
		{x = 190,  z = -420, r = 10, h = 58},
	}) do
		local floorY = podium(towers, t.x, t.z, t.r * 2.4, t.r * 2.4, rng)
		H.tower(towers, L.wcf(t.x, floorY, t.z), {seed = 200 + i, radius = t.r, height = t.h,
			sides = 8, stone = L.C.ElvenStone, trim = L.C.PaleStone, roof = L.C.DeepStone,
			beacon = (i % 2 == 0) and L.C.GlowCyan or L.C.GlowGold, name = "Tower" .. i})
		built.towers = built.towers + 1
	end

	----------------------------------------------------------------- town square
	local square = L.folder(town, "Square")
	do
		local sx, sz = -70, -232
		local sy = g(sx, sz)
		for ri = 0, 3 do
			local rmid = 10 + ri * 16
			local n = math.max(8, math.floor(2 * math.pi * rmid / 15))
			for k = 0, n - 1 do
				local a = math.rad(k * 360 / n)
				local px, pz = sx + math.cos(a) * rmid, sz + math.sin(a) * rmid
				L.box(square, "SquareSlab", L.wcf(px, g(px, pz) + 1.0, pz) * CFrame.Angles(0, -a, 0),
					Vector3.new(16, 2.6, 2 * math.pi * rmid / n * 1.05),
					P.jitterCol(L.C.ElvenStone, rng, 14), L.M.Stone, {solid = true})
			end
		end
		-- a well at the centre
		for k = 0, 11 do
			local a = math.rad(k * 30)
			L.box(square, "WellRing", L.wcf(sx + math.cos(a) * 6, sy + 3.6, sz + math.sin(a) * 6) * CFrame.Angles(0, -a, 0),
				Vector3.new(1.6, 5.2, 3.4), L.C.WeatheredStone, L.M.Stone, {solid = true})
		end
		local ww = L.cyl(square, "WellWater", L.wcf(sx, sy + 2.6, sz) * CFrame.Angles(0, 0, math.rad(90)),
			0.5, 10, L.C.Water, Enum.Material.Glass, {collide = false, shadow = false})
		ww.Transparency = 0.34
		L.light(ww, L.C.GlowCyan, 1.4, 26)
		for _, s in ipairs({1, -1}) do
			L.post(square, "WellPost", L.wcf(sx + s * 7, sy + 12, sz), 16, 1.4, L.C.Wood, Enum.Material.Wood, {solid = true})
		end
		L.box(square, "WellBeam", L.wcf(sx, sy + 20, sz), Vector3.new(18, 1.6, 1.6), L.C.Wood, Enum.Material.Wood, {solid = true})
		A.roofPitched(square, L.wcf(sx, sy + 20.8, sz), 18, 12, 6,
			{color = L.C.DeepStone, mat = L.M.Stone, thick = 0.9, overhang = 2.0, openGable = true})
		P.hangingLantern(square, L.wv(sx, sy + 19, sz), 3, {scale = 0.9, color = L.C.GlowGold, brightness = 2.4, range = 34})
		for k = 0, 5 do
			local a = math.rad(k * 60 + 20)
			P.bench(square, L.wcf(sx + math.cos(a) * 44, g(sx + math.cos(a) * 44, sz + math.sin(a) * 44), sz + math.sin(a) * 44)
				* CFrame.Angles(0, -a + math.pi, 0), {width = 9})
			P.planter(square, L.wv(sx + math.cos(a + 0.5) * 52, g(sx + math.cos(a + 0.5) * 52, sz + math.sin(a + 0.5) * 52), sz + math.sin(a + 0.5) * 52),
				7, {seed = k, plants = 8, bloom = L.C.GlowPink})
		end
	end

	----------------------------------------------------------------- streams + bridges
	local streams = L.folder(town, "Streams")
	local runs = {
		{Vector2.new(-236, -320), Vector2.new(-210, -250), Vector2.new(-186, -170), Vector2.new(-150, -80), Vector2.new(-120, 10)},
		{Vector2.new(232, -344), Vector2.new(206, -262), Vector2.new(178, -180), Vector2.new(150, -90), Vector2.new(128, 6)},
	}
	for si, run in ipairs(runs) do
		local prev
		for i = 0, 90 do
			local u = i / 90
			local p = L.spline({Vector3.new(run[1].X, 0, run[1].Y), Vector3.new(run[2].X, 0, run[2].Y),
				Vector3.new(run[3].X, 0, run[3].Y), Vector3.new(run[4].X, 0, run[4].Y), Vector3.new(run[5].X, 0, run[5].Y)}, u)
			local gy = g(p.X, p.Z)
			-- carve a shallow bed and fill it
			T:FillBlock(CFrame.new(L.wv(p.X, gy - 3.0, p.Z)), Vector3.new(17, 9, 17), Enum.Material.Air)
			T:FillBlock(CFrame.new(L.wv(p.X, gy - 4.4, p.Z)), Vector3.new(15, 5.2, 15), Enum.Material.Water)
			if prev and i % 6 == 0 then
				for _, s in ipairs({1, -1}) do
					local d = (p - prev)
					if d.Magnitude > 0.1 then
						local side = Vector3.new(-d.Z, 0, d.X).Unit * 9.5 * s
						L.box(streams, "StreamStone", L.wcf(p.X + side.X, gy - 0.8, p.Z + side.Z) * L.yaw(rng:NextNumber(0, 360)),
							Vector3.new(rng:NextNumber(4, 8), 3.4, rng:NextNumber(4, 8)),
							P.jitterCol(L.C.GreyStone, rng, 18), L.M.Rough, {solid = true})
					end
				end
			end
			prev = p
		end
		-- footbridges where the street crosses
		for _, u in ipairs({0.3, 0.66}) do
			local p = L.spline({Vector3.new(run[1].X, 0, run[1].Y), Vector3.new(run[2].X, 0, run[2].Y),
				Vector3.new(run[3].X, 0, run[3].Y), Vector3.new(run[4].X, 0, run[4].Y), Vector3.new(run[5].X, 0, run[5].Y)}, u)
			local gy = g(p.X, p.Z)
			H.archBridge(streams, L.wv(p.X - 16, gy + 2, p.Z), L.wv(p.X + 16, gy + 2, p.Z), 11,
				{rise = 3.5, stone = L.C.WeatheredStone, trim = L.C.PaleStone, name = "Footbridge"})
			built.bridges = built.bridges + 1
		end
	end

	----------------------------------------------------------------- roots + scatter
	local nature = L.folder(town, "Nature")
	for i = 1, 26 do
		local u = rng:NextNumber(0.02, 0.98)
		local x, z = streetPoint(u)
		local a = rng:NextNumber(0, 6.283)
		local rr = rng:NextNumber(80, 190)
		local px, pz = x + math.cos(a) * rr, z + math.sin(a) * rr
		local gy = g(px, pz)
		if gy > F.WATER + 3 and gy < 200 then
			local k = i % 5
			if k == 0 then
				P.rootArch(nature, L.wcf(px, gy - 2, pz) * L.yaw(rng:NextNumber(0, 360)),
					rng:NextNumber(30, 50), rng:NextNumber(28, 46), rng:NextNumber(2.6, 4.2), {seed = i, rootlets = 5})
			elseif k == 1 then
				Fl.giantMushroom(nature, L.wv(px, gy, pz), {seed = i * 3, height = rng:NextNumber(16, 34),
					cap = rng:NextNumber() < 0.5 and L.C.GlowPink or L.C.PetalPale, gill = L.C.GlowCyan})
			elseif k == 2 then
				Fl.fern(nature, L.wv(px, gy, pz), {seed = i * 5, fronds = 8, height = rng:NextNumber(5, 10)})
			elseif k == 3 then
				Fl.tree(nature, L.wv(px, gy - 1, pz), {seed = i * 11, height = rng:NextNumber(46, 74),
					bloom = rng:NextNumber() < 0.3 and L.C.GlowPink or nil, vines = 4})
			else
				Fl.crystals(nature, L.wv(px, gy, pz), {seed = i * 13, count = 5, spread = 6,
					color = rng:NextNumber() < 0.5 and L.C.GlowCyan or L.C.GlowGreen})
			end
		end
	end

	local parts = 0
	for _, d in ipairs(town:GetDescendants()) do if d:IsA("BasePart") then parts = parts + 1 end end
	return string.format("Aelunmyr: %d houses, %d towers, %d footbridges, 2 streams, %d parts",
		built.houses, built.towers, built.bridges, parts)
end

return M
