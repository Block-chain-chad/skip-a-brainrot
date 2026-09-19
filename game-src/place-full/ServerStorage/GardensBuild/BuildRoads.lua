-- BuildRoads -- the connections between the world's set pieces.
--
-- The world had three built areas that did not actually join up:
--   * the hub's north approach road ran INTO the Silverwend and stopped -- there was
--     no crossing of the river at all, a 340-stud gap between hub and town
--   * the town street ended 51 studs short of the Pilgrim Way
--   * the Pilgrim Way ended 263 studs from the cathedral's great stair
-- The third is fixed by the path now sweeping a full circuit. This module builds the
-- first two: a causeway with an arched span over the river, and the short joint at
-- the top of the town.

local L = require(script.Parent.Lib)
local F = require(script.Parent.Field)
local A = require(script.Parent.Arch)
local P = require(script.Parent.Props)
local H = require(script.Parent.House)

local M = {}

local function g(x, z) return F.ground(x, z, F.ceiling(x, z)) end

-- paved ribbon following the ground between two points
local function road(parent, x0, z0, x1, z1, width, rng)
	local steps = math.max(2, math.ceil(math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2) / 12))
	local prev
	for i = 0, steps do
		local t = i / steps
		local x, z = x0 + (x1 - x0) * t, z0 + (z1 - z0) * t
		local y = math.max(g(x, z), F.WATER + 1) + 1.2
		local p = L.wv(x, y, z)
		if prev and (p - prev).Magnitude > 0.4 then
			local cf = CFrame.lookAt((p + prev) / 2, p)
			L.box(parent, "RoadSlab", cf, Vector3.new(width, 2.8, (p - prev).Magnitude + 1.5),
				P.jitterCol(L.C.WeatheredStone, rng, 14), L.M.Cobble, {solid = true})
			for _, s in ipairs({1, -1}) do
				L.box(parent, "Kerb", cf * CFrame.new(s * (width / 2 - 0.9), 1.1, 0),
					Vector3.new(2.0, 2.8, (p - prev).Magnitude + 1.5), L.C.PaleStone, L.M.Stone, {solid = true})
			end
		end
		prev = p
	end
end

function M.run()
	local roads = L.folder(workspace.GameWorld.LushGardens, "Roads")
	roads:ClearAllChildren()
	local rng = Random.new(5150)
	local log = {}

	-- ===== THE SILVERWEND CAUSEWAY =============================================
	-- Find the real banks by walking north from the hub until the ground climbs back
	-- out of the water, rather than assuming where the river is.
	local X = F.HUB.X
	local southBank, northBank
	for z = 520, 120, -4 do
		local h = g(X, z)
		if not southBank and h < F.WATER then southBank = z + 4 end
		if southBank and not northBank and h > F.WATER + 1.5 then northBank = z - 4 break end
	end
	southBank = southBank or 430
	northBank = northBank or 250
	local span = southBank - northBank
	local deckY = math.max(g(X, southBank), g(X, northBank)) + 7

	-- approach roads on dry land at each end
	road(roads, X, 520, X, southBank + 2, 22, rng)
	road(roads, X, northBank - 2, X, 40, 22, rng)

	-- the bridge itself
	local a = L.wv(X, deckY, southBank + 2)
	local b = L.wv(X, deckY, northBank - 2)
	H.archBridge(roads, a, b, 26, {rise = span * 0.16, stone = L.C.WeatheredStone,
		trim = L.C.PaleStone, name = "SilverwendCauseway",
		groundA = L.ORIGIN.Y + g(X, southBank + 2), groundB = L.ORIGIN.Y + g(X, northBank - 2)})
	-- piers standing in the river, and lamps along the parapet
	for i = 1, 3 do
		local t = i / 4
		local pz = southBank + (northBank - southBank) * t
		local bedY = g(X, pz)
		for _, s in ipairs({1, -1}) do
			local px = X + s * 11
			local hgt = deckY + math.sin(t * math.pi) * span * 0.16 - bedY
			L.box(roads, "Pier", L.wcf(px, bedY + hgt / 2, pz), Vector3.new(6, hgt, 9),
				L.C.GreyStone, L.M.Stone, {solid = true})
			P.lampPost(roads, L.wv(px, deckY + math.sin(t * math.pi) * span * 0.16 + 1, pz), 13,
				{color = L.C.GlowGold, brightness = 2.0, range = 30})
		end
	end
	-- gate arches at each end of the crossing
	for _, e in ipairs({{southBank + 6, 1}, {northBank - 6, -1}}) do
		local z, s = e[1], e[2]
		local gy = math.max(g(X, z), F.WATER) + 1
		for _, sx in ipairs({-1, 1}) do
			L.box(roads, "GatePier", L.wcf(X + sx * 17, gy + 13, z), Vector3.new(6, 26, 6), L.C.PaleStone, L.M.Stone, {solid = true})
			A.spire(roads, L.wcf(X + sx * 17, gy + 26, z), 3.2, 12, {segs = 8, color = L.C.DeepStone, mat = L.M.Stone, finialColor = L.C.Gold})
			P.lantern(roads, L.wcf(X + sx * 17, gy + 29, z), {scale = 0.8, color = L.C.GlowCyan, brightness = 2.0, range = 28})
		end
	end
	log[#log + 1] = string.format("Silverwend Causeway: %.0f-stud arched span over the river (banks z=%.0f to %.0f), plus %.0f studs of approach road",
		span, southBank, northBank, (520 - southBank) + (northBank - 40))

	-- ===== TOWN STREET -> PILGRIM WAY ==========================================
	local sx, sz = -16, -452                     -- town street north end
	local px, pz = F.HILL.X + math.cos(math.rad(92)) * 470, F.HILL.Y + math.sin(math.rad(92)) * 470
	road(roads, sx, sz, px, pz, 23, rng)
	-- a marker arch where the town ends and the climb begins
	local gy = g((sx + px) / 2, (sz + pz) / 2)
	P.rootArch(roads, L.wcf((sx + px) / 2, gy - 2, (sz + pz) / 2), 42, 40, 4.0, {seed = 9, rootlets = 6})
	log[#log + 1] = string.format("town street joined to the Pilgrim Way (%.0f studs)", math.sqrt((px - sx) ^ 2 + (pz - sz) ^ 2))

	local parts = 0
	for _, d in ipairs(roads:GetDescendants()) do if d:IsA("BasePart") then parts = parts + 1 end end
	return table.concat(log, "\n") .. string.format("\n%d parts", parts)
end

return M
