-- BuildHub -- the Verdant Court, World 3's central hub.
--
-- Layout, from the middle outward:
--   r 0..110   the market -- stalls, tents, a fountain. NO buildings: the brief is a
--              gathering space, not a town square with shops around it.
--   r 118..134 a ring canal carved into the terrain, crossed by four bridges
--   r 150..215 the garden ring -- creature statues, planters, benches, trees
--   r ~232     an arcade of giant roots arching over the plaza edge
-- Four approaches at 0/90/180/270 degrees stay clear all the way through: east,
-- south to the arrival gorge, west, and north to the causeway and the town.
--
-- Re-runnable. It re-carves its own terrain, so running it again after a terrain
-- rebuild restores the canal and pools.

local L = require(script.Parent.Lib)
local F = require(script.Parent.Field)
local A = require(script.Parent.Arch)
local P = require(script.Parent.Props)
local C = require(script.Parent.Creature)
local Fl = require(script.Parent.Flora)

local M = {}
local T = workspace.Terrain

local CX, CZ = F.HUB.X, F.HUB.Y
local FLOOR = 9.4                    -- top of the paving
local CANAL_IN, CANAL_OUT = 118, 134
local APPROACH = {0, 90, 180, 270}   -- degrees kept clear

local function inApproach(deg, halfWidth)
	for _, a in ipairs(APPROACH) do
		local d = math.abs((deg - a + 180) % 360 - 180)
		if d < (halfWidth or 13) then return true end
	end
	return false
end

local function hp(r, deg, y)   -- hub polar -> world
	local a = math.rad(deg)
	return L.wv(CX + math.cos(a) * r, y or FLOOR, CZ + math.sin(a) * r)
end

function M.run()
	local root = workspace.GameWorld.LushGardens
	local hub = root.Hub
	hub:ClearAllChildren()
	local rng = Random.new(20260808)

	----------------------------------------------------------------- terrain work
	-- The ring canal, carved then filled. Terrain water is static per voxel, so a
	-- trench above the world water table holds its own water perfectly well.
	local segs = 110
	for i = 0, segs - 1 do
		local deg = i * 360 / segs
		local a = math.rad(deg)
		local mid = (CANAL_IN + CANAL_OUT) / 2
		local arc = 2 * math.pi * mid / segs * 1.35
		local cf = CFrame.new(L.wv(CX + math.cos(a) * mid, 2, CZ + math.sin(a) * mid)) * CFrame.Angles(0, -a, 0)
		T:FillBlock(cf, Vector3.new(CANAL_OUT - CANAL_IN, 16, arc), Enum.Material.Air)
		T:FillBlock(cf * CFrame.new(0, 2.6, 0), Vector3.new(CANAL_OUT - CANAL_IN - 1.5, 5, arc), Enum.Material.Water)
	end
	-- four garden pools
	local pools = {}
	for i, deg in ipairs({45, 135, 225, 315}) do
		local a = math.rad(deg)
		local px, pz = CX + math.cos(a) * 186, CZ + math.sin(a) * 186
		pools[i] = {px, pz}
		T:FillCylinder(CFrame.new(L.wv(px, 2, pz)), 18, 21, Enum.Material.Air)
		T:FillCylinder(CFrame.new(L.wv(px, 4.4, pz)), 5.4, 20, Enum.Material.Water)
	end

	----------------------------------------------------------------- paving
	local pave = L.folder(hub, "Paving")
	local ringW = 26
	for ri = 0, 7 do
		local r0 = ri * ringW
		local r1 = r0 + ringW
		if r1 <= 186 then
			local rmid = (r0 + r1) / 2
			local n = math.max(8, math.floor(2 * math.pi * rmid / ringW))
			for i = 0, n - 1 do
				local deg = i * 360 / n + (ri % 2) * (180 / n)
				-- leave the canal band unpaved
				if not (rmid > CANAL_IN - 6 and rmid < CANAL_OUT + 6) then
					local a = math.rad(deg)
					local col = P.jitterCol(rng:NextNumber() < 0.12 and L.C.MossStone or L.C.ElvenStone, rng, 16)
					L.box(pave, "Slab", CFrame.new(L.wv(CX + math.cos(a) * rmid, FLOOR - 1.2, CZ + math.sin(a) * rmid))
						* CFrame.Angles(0, -a, 0),
						Vector3.new(ringW - 0.5, 2.4, 2 * math.pi * rmid / n * 0.94),
						col, ri % 2 == 0 and L.M.Stone or L.M.Cobble, {solid = true})
				end
			end
			-- an inlaid band between rings
			if ri > 0 and r0 < 186 and not (r0 > CANAL_IN - 8 and r0 < CANAL_OUT + 8) then
				local bn = math.max(12, math.floor(2 * math.pi * r0 / 9))
				for i = 0, bn - 1 do
					local a = math.rad(i * 360 / bn)
					L.box(pave, "Inlay", CFrame.new(L.wv(CX + math.cos(a) * r0, FLOOR - 0.1, CZ + math.sin(a) * r0))
						* CFrame.Angles(0, -a, 0), Vector3.new(2.2, 0.4, 2 * math.pi * r0 / bn * 0.98),
						L.C.PaleStone, Enum.Material.Marble, {shadow = false})
				end
			end
		end
	end
	-- radial star inlay under the fountain
	for i = 0, 15 do
		local a = math.rad(i * 22.5)
		L.box(pave, "StarRay", CFrame.new(L.wv(CX + math.cos(a) * 44, FLOOR - 0.1, CZ + math.sin(a) * 44))
			* CFrame.Angles(0, -a, 0), Vector3.new(64, 0.4, 2.6), L.C.PaleStone, Enum.Material.Marble, {shadow = false})
	end
	-- approach roads reaching out past the arcade
	for _, deg in ipairs(APPROACH) do
		local a = math.rad(deg)
		for r = 190, 320, 13 do
			local gy = F.ground(CX + math.cos(a) * r, CZ + math.sin(a) * r, F.ceiling(CX + math.cos(a) * r, CZ + math.sin(a) * r))
			local y = math.max(gy + 1.0, 3)
			L.box(pave, "RoadSlab", CFrame.new(L.wv(CX + math.cos(a) * r, y, CZ + math.sin(a) * r)) * CFrame.Angles(0, -a, 0),
				Vector3.new(13.5, 2.2, 28), P.jitterCol(L.C.WeatheredStone, rng, 14), L.M.Cobble, {solid = true})
		end
	end

	----------------------------------------------------------------- canal edging + bridges
	local canal = L.folder(hub, "Canal")
	local en = 96
	for i = 0, en - 1 do
		local deg = i * 360 / en
		local a = math.rad(deg)
		local arc = 2 * math.pi * CANAL_IN / en * 1.1
		for _, side in ipairs({{CANAL_IN - 1.2, 1}, {CANAL_OUT + 1.2, -1}}) do
			L.box(canal, "CanalKerb", CFrame.new(L.wv(CX + math.cos(a) * side[1], FLOOR - 0.6, CZ + math.sin(a) * side[1]))
				* CFrame.Angles(0, -a, 0), Vector3.new(3.4, 3.6, arc * (side[1] / CANAL_IN)),
				L.C.PaleStone, L.M.Stone, {solid = true})
		end
		if i % 8 == 0 and not inApproach(deg, 16) then
			P.lantern(canal, CFrame.new(hp(CANAL_OUT + 4.5, deg, FLOOR + 4.5)), {scale = 0.75, color = L.C.GlowCyan, brightness = 1.6, range = 22})
			L.post(canal, "CanalPost", CFrame.new(hp(CANAL_OUT + 4.5, deg, FLOOR + 2)), 5, 1.1, L.C.WeatheredStone, L.M.Stone, {solid = true})
		end
	end
	for _, deg in ipairs(APPROACH) do
		local a = math.rad(deg)
		local mid = (CANAL_IN + CANAL_OUT) / 2
		local bcf = CFrame.new(L.wv(CX + math.cos(a) * mid, FLOOR - 0.4, CZ + math.sin(a) * mid)) * CFrame.Angles(0, -a, 0)
		L.box(canal, "BridgeDeck", bcf, Vector3.new(CANAL_OUT - CANAL_IN + 10, 2.0, 26), L.C.PaleStone, L.M.Stone, {solid = true})
		for _, s in ipairs({1, -1}) do
			L.box(canal, "BridgeParapet", bcf * CFrame.new(0, 2.2, s * 12.4),
				Vector3.new(CANAL_OUT - CANAL_IN + 10, 2.6, 1.4), L.C.PaleStone, L.M.Stone, {solid = true})
			for k = -1, 1, 2 do
				L.box(canal, "BridgePier", bcf * CFrame.new(k * (CANAL_OUT - CANAL_IN) / 2, -3.4, s * 12.4),
					Vector3.new(3.0, 8.0, 3.0), L.C.GreyStone, L.M.Stone, {solid = true})
				P.lantern(canal, bcf * CFrame.new(k * (CANAL_OUT - CANAL_IN + 8) / 2, 6.4, s * 12.4),
					{scale = 0.7, color = L.C.GlowGold, brightness = 1.8, range = 24})
				L.post(canal, "BridgeLampPost", bcf * CFrame.new(k * (CANAL_OUT - CANAL_IN + 8) / 2, 4.0, s * 12.4),
					4.4, 0.9, L.C.PaleStone, L.M.Stone, {shadow = false})
			end
		end
	end

	----------------------------------------------------------------- fountain
	P.fountain(hub, L.wv(CX, FLOOR, CZ), 22, {tiers = 3, stone = L.C.ElvenStone,
		trim = L.C.PaleStone, glow = L.C.GlowCyan, crown = L.C.GlowCyan, name = "CourtFountain"})
	for i = 0, 7 do
		local deg = i * 45 + 22.5
		P.lampPost(hub, hp(36, deg), 12, {color = L.C.GlowGold, brightness = 2.0, range = 30, scale = 0.9})
	end

	----------------------------------------------------------------- market
	local market = L.folder(hub, "Market")
	local stallCloths = {L.C.ClothTeal, L.C.ClothPink, L.C.ClothGold, L.C.Cloth}
	local placed = 0
	for i = 0, 17 do
		local deg = i * 20 + 10
		if not inApproach(deg, 15) then
			local r = (i % 2 == 0) and 70 or 96
			local cf = CFrame.new(hp(r, deg)) * CFrame.Angles(0, math.rad(-deg + 180), 0)
			P.stall(market, cf, {
				seed = 100 + i, width = rng:NextNumber(13, 17), depth = rng:NextNumber(9, 12),
				height = rng:NextNumber(9, 11), cloth = stallCloths[(i % #stallCloths) + 1],
				goods = rng:NextInteger(4, 6), name = "Stall" .. i,
			})
			placed = placed + 1
		end
	end
	for i, deg in ipairs({34, 76, 124, 166, 214, 256, 304, 346}) do
		if not inApproach(deg, 15) then
			P.tent(market, CFrame.new(hp(112, deg)), {radius = rng:NextNumber(8, 11), height = rng:NextNumber(12, 16),
				cloth = stallCloths[(i % #stallCloths) + 1], seed = 200 + i, name = "Tent" .. i})
		end
	end
	-- clutter: crates, barrels, sacks, rugs, hanging banners between poles
	for i = 1, 46 do
		local deg = rng:NextNumber(0, 360)
		if not inApproach(deg, 16) then
			local r = rng:NextNumber(48, 108)
			local cf = CFrame.new(hp(r, deg)) * L.yaw(rng:NextNumber(0, 360))
			local k = rng:NextInteger(1, 4)
			if k == 1 then
				P.crate(market, cf * CFrame.new(0, 1.7, 0), Vector3.new(rng:NextNumber(3, 4.6), 3.2, rng:NextNumber(3, 4.6)))
			elseif k == 2 then
				P.barrel(market, cf, {height = rng:NextNumber(3.6, 5)})
			elseif k == 3 then
				L.box(market, "Sack", cf * CFrame.new(0, 1.3, 0), Vector3.new(2.6, 2.6, 2.2),
					P.jitterCol(L.C.ClothGold, rng, 20), Enum.Material.Fabric, {solid = true})
			else
				L.box(market, "Rug", cf * CFrame.new(0, 0.2, 0), Vector3.new(rng:NextNumber(7, 11), 0.25, rng:NextNumber(5, 8)),
					P.jitterCol(L.C.ClothPink, rng, 30), Enum.Material.Fabric, {shadow = false})
			end
		end
	end
	-- banner poles ringing the market
	for i = 0, 11 do
		local deg = i * 30 + 15
		if not inApproach(deg, 15) then
			local base = hp(108, deg)
			L.post(market, "BannerPole", CFrame.new(base + Vector3.new(0, 9, 0)), 18, 1.0, L.C.Wood, Enum.Material.Wood, {solid = true})
			L.box(market, "PoleFoot", CFrame.new(base + Vector3.new(0, 0.8, 0)), Vector3.new(3, 1.6, 3), L.C.WeatheredStone, L.M.Stone, {shadow = false})
			P.banner(market, CFrame.new(base + Vector3.new(0, 17, 0)) * CFrame.Angles(0, math.rad(-deg), 0), 6, 9,
				{color = stallCloths[(i % #stallCloths) + 1], trim = L.C.Gold})
			P.hangingLantern(market, base + Vector3.new(0, 15, 0), 2, {scale = 0.6, color = L.C.GlowGold, brightness = 1.4, range = 18})
		end
	end

	----------------------------------------------------------------- statues
	local statues = L.folder(hub, "Statues")
	local spec = {
		{deg = 30,  kind = "quad", style = "stag", scale = 1.7, eye = L.C.GlowGold},
		{deg = 60,  kind = "owl",  scale = 1.9, eye = L.C.GlowGold},
		{deg = 120, kind = "quad", style = "wolf", scale = 1.7},
		{deg = 150, kind = "bird", scale = 1.5},
		{deg = 210, kind = "quad", style = "elk", scale = 1.8},
		{deg = 240, kind = "quad", style = "cat", scale = 1.7, eye = L.C.GlowGreen},
		{deg = 300, kind = "drag", scale = 1.5, eye = L.C.GlowCyan},
		{deg = 330, kind = "quad", style = "doe", scale = 1.6},
	}
	for i, s in ipairs(spec) do
		local base = hp(172, s.deg)
		local topY = C.pedestal(statues, base, 24, 24, 13, {seed = i * 5, glow = L.C.GlowCyan})
		-- every figure faces the middle of the plaza
		local cf = CFrame.new(Vector3.new(base.X, topY, base.Z)) * CFrame.Angles(0, math.rad(-s.deg + 180), 0)
		local mo
		if s.kind == "quad" then
			mo = C.quadruped(statues, cf, s.scale, {style = s.style, seed = i * 13, eyeGlow = s.eye})
		elseif s.kind == "owl" then
			mo = C.owl(statues, cf, s.scale, {seed = i * 13, eyeGlow = s.eye})
		elseif s.kind == "bird" then
			mo = C.greatBird(statues, cf, s.scale, {seed = i * 13})
		else
			mo = C.dragon(statues, cf, s.scale, {seed = i * 13, eyeGlow = s.eye})
		end
		C.weather(mo, {seed = i * 9, amount = 0.26, vines = 4})
		-- a brazier either side
		for _, off in ipairs({-17, 17}) do
			P.brazier(statues, hp(172, s.deg + off), {fire = L.C.GlowCyan})
		end
	end

	----------------------------------------------------------------- garden ring
	local garden = L.folder(hub, "Garden")
	for i, p in ipairs(pools) do
		-- pool kerbing
		for k = 0, 27 do
			local a = math.rad(k * 360 / 28)
			L.box(garden, "PoolKerb", CFrame.new(L.wv(p[1] + math.cos(a) * 21, FLOOR - 1.0, p[2] + math.sin(a) * 21))
				* CFrame.Angles(0, -a, 0), Vector3.new(3.2, 3.2, 2 * math.pi * 21 / 28 * 1.12),
				L.C.PaleStone, L.M.Stone, {solid = true})
		end
		for k = 1, 7 do
			local a = rng:NextNumber(0, 6.283)
			local rr = rng:NextNumber(2, 15)
			Fl.lilyPad(garden, L.wv(p[1] + math.cos(a) * rr, 7.4, p[2] + math.sin(a) * rr),
				{seed = i * 40 + k, radius = rng:NextNumber(3, 6), flowerChance = 0.5, flower = L.C.PetalPale})
		end
		Fl.flowerPatch(garden, L.wv(p[1] + 26, FLOOR, p[2]), {seed = i * 7, radius = 9, count = 12,
			colors = {L.C.GlowPink, L.C.GlowCyan, L.C.GlowGold}})
	end
	for i = 0, 23 do
		local deg = i * 15 + 7
		if not inApproach(deg, 14) then
			local r = 150 + (i % 3) * 22
			local base = hp(r, deg)
			local k = i % 4
			if k == 0 then
				P.planter(garden, base, 7, {seed = i, plants = 8, bloom = L.C.GlowPink})
			elseif k == 1 then
				P.bench(garden, CFrame.new(base) * CFrame.Angles(0, math.rad(-deg + 180), 0), {width = 9})
			elseif k == 2 then
				P.lampPost(garden, base, 14, {color = L.C.GlowGold, brightness = 1.8, range = 28})
			else
				Fl.flowerPatch(garden, base, {seed = i * 3, radius = 8, count = 10,
					colors = {L.C.GlowPink, L.C.GlowGreen, L.C.GlowCyan}})
			end
		end
	end
	-- trees around the garden ring
	for i = 0, 15 do
		local deg = i * 22.5 + 11
		if not inApproach(deg, 18) then
			local r = 198 + rng:NextNumber(-10, 16)
			Fl.tree(garden, hp(r, deg, FLOOR - 1), {
				seed = 500 + i, height = rng:NextNumber(52, 82), branches = rng:NextInteger(5, 8),
				bloom = (i % 3 == 0) and L.C.GlowPink or nil, blooms = 7,
				leaf = L.C.Leaf, leafPale = L.C.LeafPale, vines = 4, name = "CourtTree" .. i,
			})
		end
	end

	----------------------------------------------------------------- root arcade
	local arcade = L.folder(hub, "RootArcade")
	for i = 0, 19 do
		local deg = i * 18 + 9
		if not inApproach(deg, 22) then
			local a = math.rad(deg)
			local cf = CFrame.new(hp(232, deg, FLOOR - 2)) * CFrame.Angles(0, math.rad(-deg), 0)
			P.rootArch(arcade, cf, rng:NextNumber(34, 46), rng:NextNumber(34, 52), rng:NextNumber(3.0, 4.6),
				{seed = 700 + i, rootlets = 5, color = P.jitterCol(L.C.Root, rng, 14)})
			if i % 2 == 0 then
				P.vine(arcade, hp(232, deg, FLOOR + 34), rng:NextNumber(14, 26),
					{seed = 800 + i, glow = L.C.GlowGreen, leafColor = L.C.LeafDark})
			end
		end
	end
	-- standing carved stones at the four approaches
	for _, deg in ipairs(APPROACH) do
		for _, s in ipairs({-1, 1}) do
			local base = hp(228, deg + s * 15)
			L.box(arcade, "MenhirBase", CFrame.new(base + Vector3.new(0, 1.2, 0)), Vector3.new(11, 2.4, 11), L.C.GreyStone, L.M.Stone, {solid = true})
			L.box(arcade, "Menhir", CFrame.new(base + Vector3.new(0, 15, 0)) * CFrame.Angles(0, math.rad(-deg), 0),
				Vector3.new(7.5, 26, 4.4), L.C.WeatheredStone, L.M.Stone, {solid = true})
			P.carving(arcade, CFrame.new(base + Vector3.new(0, 16, 0)) * CFrame.Angles(0, math.rad(-deg + 180), 0) * CFrame.new(0, 0, 2.4),
				5.5, 18, {glow = L.C.GlowCyan, seed = deg + s})
			L.glow(arcade, "MenhirCap", CFrame.new(base + Vector3.new(0, 28.6, 0)), Vector3.new(4, 1.6, 3),
				L.C.GlowCyan, 1.4, 22, "blob")
		end
	end

	local parts = 0
	for _, d in ipairs(hub:GetDescendants()) do if d:IsA("BasePart") then parts = parts + 1 end end
	return string.format("Verdant Court built: %d stalls, 8 creature statues, 4 bridges, %d parts", placed, parts)
end

return M
