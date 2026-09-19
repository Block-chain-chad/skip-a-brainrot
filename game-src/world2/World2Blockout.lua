--!nocheck
--[[
World2Blockout -- BUILD-TIME ONLY greybox generator for the World 2 (Frozen Tundra) rebuild.

Installed at ServerStorage.World2Blockout.Generator. Nothing in the game requires it. Run it from the
command bar or the Studio MCP, in Edit mode:

    local G = loadstring(game:GetService("ServerStorage").World2Blockout.Generator.Source)()
    G.Floor(); G.Massifs(); G.Features(); G.Carves(); G.HollowAndFalls(); G.Ramps(); G.Outside()
    G.BuildParts()                -- Workspace.GameWorld.FrozenTundra.Greybox
    G.Relocate()                  -- one-time moves of the kept objects (idempotent via BlockoutMoved)

To rebuild after editing numbers: G.ClearAll(), then the terrain steps and BuildParts again.

Spec: docs/WORLD2-MASTERPLAN.md, approved by Balkan 2026-09-19. GREYBOX ONLY -- simple forms, no art.
Compass used everywhere here: N = +Z (up-lake, the skip direction), E = -X, W = +X. Every height below is
a WALKABLE SURFACE; the datum is y 2002 (lake banks, dock deck, town floor).

TERRAIN HEIGHT CALIBRATION (measured in this place 2026-09-19): a FillBlock whose top is at y T walks at
T + 2 -- the existing banks are voxels up to 2000 with their surface at 2002. So every solid here is
written to (surface - 2). Wedges come out about a stud above their box, so a ramp is written from
(low - 2) to (high - 1.5).

NEVER TOUCHED: the lake water and the ground under it, the LakeBarrier walls, the dock and the ThrowZone.
Every write stays outside LAKE_BANDS + LAKE_MARGIN, a copy of IceFishingConfig.LAKE_PROFILE: the
ice-fishing sheet, its holes and the dock lane are all measured against that water outline.

KNOWN BLOCKER (Balkan, 2026-09-19): there is no World 2 respawn/checkpoint -- dying, resetting or leaving
the BoundsGuard box sends a player to the valley spawn. That is being fixed separately; the cliffs and
drops here are NOT final until it is.
]]

local Workspace = game:GetService("Workspace")
local T = Workspace.Terrain
local MAT = Enum.Material

local M = {}
M.VERSION = 1

local D = 2002            -- datum surface
local BOTTOM = 1966       -- bottom of every terrain fill
local CHUNK = 512
M.DATUM = D

local XE, XW = -8600, -7400   -- east / west edges of the BoundsGuard Tundra box
local ZS, ZN = -8600, -6700   -- south / north edges

-- 16, not 8: the real water overshoots the stepped profile by up to 7 studs at the band corners
-- (measured 2026-09-19, z -7798), so 8 left less than one voxel of clearance and a rebuild nibbled
-- two water cells. 16 keeps at least two voxels between every write and the water.
M.LAKE_MARGIN = 16
M.LAKE_SOUTH_Z = -7808        -- the water's southernmost voxel row starts here
-- IceFishingConfig.LAKE_PROFILE, live 2026-09-19. The two dock-flank strips are merged into one band
-- here because the water under the dock between them has to be protected as well.
M.LAKE_BANDS = {
	{ z0 = -7806,   z1 = -7789.5, x0 = -8057, x1 = -7935 },
	{ z0 = -7789.5, z1 = -7773.5, x0 = -8084, x1 = -7916 },
	{ z0 = -7773.5, z1 = -7757.5, x0 = -8098, x1 = -7904 },
	{ z0 = -7757.5, z1 = -7733.5, x0 = -8114, x1 = -7886 },
	{ z0 = -7733.5, z1 = -7709.5, x0 = -8128, x1 = -7872 },
	{ z0 = -7709.5, z1 = -7677.5, x0 = -8142, x1 = -7858 },
	{ z0 = -7677.5, z1 = -7637.5, x0 = -8154, x1 = -7846 },
	{ z0 = -7637.5, z1 = -7589.5, x0 = -8164, x1 = -7836 },
	{ z0 = -7589.5, z1 = -7525.5, x0 = -8176, x1 = -7824 },
	{ z0 = -7525.5, z1 = -7469.5, x0 = -8188, x1 = -7812 },
	{ z0 = -7469.5, z1 = -7157.5, x0 = -8190, x1 = -7810 },
	{ z0 = -7157.5, z1 = -7117.5, x0 = -8178, x1 = -7822 },
	{ z0 = -7117.5, z1 = -7077.5, x0 = -8170, x1 = -7830 },
	{ z0 = -7077.5, z1 = -7037.5, x0 = -8162, x1 = -7838 },
	{ z0 = -7037.5, z1 = -7013.5, x0 = -8150, x1 = -7850 },
	{ z0 = -7013.5, z1 = -6989.5, x0 = -8134, x1 = -7860 },
	{ z0 = -6989.5, z1 = -6957.5, x0 = -8130, x1 = -7872 },
	{ z0 = -6957.5, z1 = -6933.5, x0 = -8116, x1 = -7884 },
	{ z0 = -6933.5, z1 = -6909.5, x0 = -8102, x1 = -7898 },
	{ z0 = -6909.5, z1 = -6901.5, x0 = -8082, x1 = -7918 },
	{ z0 = -6901.5, z1 = -6885.5, x0 = -8069, x1 = -7923 },
	{ z0 = -6885.5, z1 = -6877.5, x0 = -8038, x1 = -7956 },
	{ z0 = -6877.5, z1 = -6869.5, x0 = -8028, x1 = -7972 },
}

-- ============================================================== LAYOUT (masterplan §2)
-- Six camps, 3 + 3 along the Avenue (x -8000). face = +1 when the Avenue is at +X of the camp.
M.CAMPS = {
	{ plot = "Plot7",  x = -8125, z = -8065, face = 1 },
	{ plot = "Plot8",  x = -8125, z = -7975, face = 1 },
	{ plot = "Plot9",  x = -8125, z = -7885, face = 1 },
	{ plot = "Plot10", x = -7875, z = -7885, face = -1 },
	{ plot = "Plot11", x = -7875, z = -7975, face = -1 },
	{ plot = "Plot12", x = -7875, z = -8065, face = -1 },
}
M.TERRACE = 5   -- camp terraces stand this far above the datum

-- The Cellar Pass runs DIAGONALLY from the portal chamber to a mouth on the Frostgate's +X end, so the
-- first thing a player walks out to is the view over the town and up the lake. (A straight tunnel
-- opened onto the High Ledge instead -- a flat plateau and a glacier wall, no reveal. Measured on the
-- first blockout pass.) The arrival point is a few steps inside the mouth, facing it. It is NOT at the
-- chamber end: the return portal is right behind that, and the travel curtain does not re-aim the
-- camera, so a player who arrived with the camera facing back walked straight into the portal and
-- home again (33 studs, measured in Play 2026-09-19). From here the portal is ~87 studs back.
M.TUNNEL = { { -8272, -8352, 2030 }, { -8236, -8266, 2030 } }
M.ARRIVAL = Vector3.new(-8243, 2034, -8283)
M.ARRIVAL_LOOK = Vector3.new(0.386, 0, 0.922).Unit

-- The Squeeze: Nico's canyon to the Blue Hollow. { x, z, floor surface }; the last leg is the ice arch.
M.SQUEEZE = {
	{ -7692, -7470, 2002 },
	{ -7650, -7452, 1999 },
	{ -7620, -7420, 1996 },
	{ -7596, -7380, 1993 },
	{ -7572, -7330, 1990 },
	{ -7560, -7292, 1987 },
	{ -7550, -7262, 1984 },
}

-- Where the kept objects go (used by Relocate).
M.STALL_SHIFT = Vector3.new(0, 0, -215)                    -- the five stalls, into the Warmhouse
-- The drill faces north, out of the Dig's nook. Its "seaward" side (site-local +Z) is where
-- CaveDrillClient opens the shaft (12 studs out, = DepthsPortal's PortalTouch) and stands every
-- cutscene camera, so that side points INTO the nook, off every walking line. Facing the other way,
-- the invisible shaft trigger sat on the path to Elder Tung and bounced players who walked past it.
M.DRILL_SITE = CFrame.lookAt(Vector3.new(-8345, 2022, -7722), Vector3.new(-8345, 2022, -7721))
M.DEPTHS_REFUSE = Vector3.new(-8325, 2025, -7710)          -- where a refused player is put back
M.TOWER_BASE = Vector3.new(-7700, 2048, -8005)             -- the Broken Watchtower, on Eagle's Crag
M.PORTAL_TOUCH = Vector3.new(-8272, 2043.4, -8375)         -- TundraReturnPortal, in the portal chamber
M.WHEEL_PIVOT = Vector3.new(-7955, 2001.8, -8128)          -- DailyWheelTundra (old -7970, -7840)
M.BOARDS_AT = Vector3.new(-8045, 2001.8, -8128)            -- LeaderboardsTundra (old -8040, -7840)

-- ============================================================== TERRAIN HELPERS
local function cuts(a, b)
	local out = { a }
	local c = a + CHUNK
	while c < b - 8 do
		table.insert(out, math.floor(c / 4) * 4)
		c += CHUNK
	end
	table.insert(out, b)
	return out
end

-- One box, split into chunks so no single write is enormous. Internal cuts sit on the voxel grid and
-- overlap by one voxel, so no seam cell is ever left half-filled between two chunks.
local function fill(x0, x1, y0, y1, z0, z1, mat)
	if x1 - x0 < 1 or y1 - y0 < 0.5 or z1 - z0 < 1 then return end
	local xs, zs = cuts(x0, x1), cuts(z0, z1)
	for i = 1, #xs - 1 do
		for k = 1, #zs - 1 do
			local a0, a1 = xs[i], xs[i + 1]
			local b0, b1 = zs[k], zs[k + 1]
			if i > 1 then a0 -= 4 end
			if k > 1 then b0 -= 4 end
			T:FillBlock(CFrame.new((a0 + a1) / 2, (y0 + y1) / 2, (b0 + b1) / 2), Vector3.new(a1 - a0, y1 - y0, b1 - b0), mat)
		end
	end
end
M.Fill = fill

local function air(x0, x1, y0, y1, z0, z1) fill(x0, x1, y0, y1, z0, z1, MAT.Air) end

-- a flat solid whose walkable surface is `surf`
local function solid(x0, x1, z0, z1, surf, mat)
	fill(x0, x1, BOTTOM, surf - 2, z0, z1, mat or MAT.Snow)
end

-- a cliff mass: basalt foot, glacier body, snow cap. The basalt shows as a dark band at the foot of
-- every face that rises from the datum, which is most of the value structure a greybox needs.
local function massif(x0, x1, z0, z1, surf)
	local top = surf - 2
	local basaltTop = math.min(top, D + 14)
	fill(x0, x1, BOTTOM, basaltTop, z0, z1, MAT.Basalt)
	if top - 6 > basaltTop then fill(x0, x1, basaltTop, top - 6, z0, z1, MAT.Glacier) end
	fill(x0, x1, math.max(top - 6, BOTTOM), top, z0, z1, MAT.Snow)
end

-- a ramp from A (low end, walkable at lowSurf) to B (high end, walkable at highSurf)
local function wedge(ax, az, lowSurf, bx, bz, highSurf, width, mat)
	local A, B = Vector3.new(ax, 0, az), Vector3.new(bx, 0, bz)
	local dir, len = (B - A).Unit, (B - A).Magnitude
	local y0, y1 = lowSurf - 2, highSurf - 1.5
	local c = Vector3.new((ax + bx) / 2, (y0 + y1) / 2, (az + bz) / 2)
	-- a terrain wedge rises toward its local +Z, i.e. against its LookVector
	T:FillWedge(CFrame.lookAt(c, c - dir), Vector3.new(width, y1 - y0, len), mat or MAT.Snow)
end
M.Wedge = wedge

-- carve a walkable corridor along points { x, z, floorSurf }; legs from `archFrom` on keep a roof
local function corridor(points, width, ceiling, archFrom)
	for i = 1, #points - 1 do
		local p, q = points[i], points[i + 1]
		local A, B = Vector3.new(p[1], 0, p[2]), Vector3.new(q[1], 0, q[2])
		local dir, len = (B - A).Unit, (B - A).Magnitude
		local lo, hi = math.min(p[3], q[3]), math.max(p[3], q[3])
		local top = (archFrom and i >= archFrom) and (lo + 16) or ceiling
		local y0 = lo - 2
		local c = Vector3.new((p[1] + q[1]) / 2, (y0 + top) / 2, (p[2] + q[2]) / 2)
		-- lengthened a little so the joints between legs stay open
		T:FillBlock(CFrame.lookAt(c, c + dir), Vector3.new(width, top - y0, len + width * 0.6), MAT.Air)
		if hi > lo + 0.5 then
			local low, high = (p[3] < q[3]) and p or q, (p[3] < q[3]) and q or p
			wedge(low[1], low[2], lo, high[1], high[2], hi, width, MAT.Snow)
		end
	end
end

-- ============================================================== TERRAIN STEPS
-- 1. The town floor and the banks, everywhere except the lake zone (same surface as the old banks).
function M.Floor()
	local m, bands = M.LAKE_MARGIN, M.LAKE_BANDS
	solid(XE, XW, ZS, M.LAKE_SOUTH_Z, D)
	for i, b in ipairs(bands) do
		local z0 = (i == 1) and M.LAKE_SOUTH_Z or b.z0
		local z1 = (i == #bands) and (b.z1 + m) or b.z1
		solid(XE, b.x0 - m, z0, z1, D)
		solid(b.x1 + m, XW, z0, z1, D)
	end
	solid(XE, XW, bands[#bands].z1 + m, ZN, D)
end

-- 2. The walls of the caldera, inside the bounds.
function M.Massifs()
	-- south: the town's back wall (the Warmhouse is built into it), higher further back
	massif(XE, XW, ZS, -8345, 2090)
	massif(XE, XW, ZS, -8460, 2140)
	-- south-east corner: hosts the Cellar Pass tunnel and the portal chamber
	massif(XE, -8212, -8349, -8262, 2090)
	-- EAST (right, facing up-lake): the High Ledge along the town, Elder's Dig shelf, tall glacier behind
	massif(-8334, -8245, -8216, -7696, 2022)
	massif(-8424, -8200, -7704, -7556, 2022)
	-- the Dig's nook under the glacier: the station, the Crack and the horn stand in it. (Without it the
	-- glacier behind the High Ledge ran on to z -7700 and swallowed all three, and Elder Tung with them.)
	massif(-8420, -8330, -7764, -7700, 2022)
	massif(XE, -8330, -8266, -7764, 2110)
	massif(XE, -8420, -7764, -7556, 2110)
	for _, b in ipairs(M.LAKE_BANDS) do          -- north of the Dig the cliff comes down to the bank
		local z0, z1 = math.max(b.z0, -7560), b.z1
		if z1 > z0 then massif(XE, b.x0 - M.LAKE_MARGIN, z0, z1, 2110) end
	end
	-- WEST (left, facing up-lake): the west ledge along the town and Nico's shore, tall glacier behind
	massif(-7755, -7666, -8349, -7416, 2022)
	massif(-7670, XW, -8349, -7416, 2110)
	for _, b in ipairs(M.LAKE_BANDS) do          -- north of Nico the cliff comes down to the bank
		local z0, z1 = math.max(b.z0, -7420), b.z1
		if z1 > z0 then massif(b.x1 + M.LAKE_MARGIN, XW, z0, z1, 2110) end
	end
	-- north: the lake head (notched for the Frozen Falls in Carves)
	massif(XE, -8044, -6872, ZN, 2150)
	massif(-7956, XW, -6872, ZN, 2150)
	massif(-8044, -7956, -6853, ZN, 2150)
end

-- 3. Raised features and landings.
function M.Features()
	massif(-8334, -8190, -8266, -8212, 2030)            -- the Frostgate (arrival overlook, +28)
	massif(-7759, -7636, -8050, -7960, 2048)            -- Eagle's Crag (+46)
	for _, c in ipairs(M.CAMPS) do                      -- camp terraces (+5)
		solid(c.x - 42, c.x + 42, c.z - 40, c.z + 40, D + M.TERRACE)
	end
	solid(-8194, -8136, -8230, -8214, 2016)             -- under the first descent leg
	solid(-8140, -8112, -8236, -8208, 2016)             -- descent landing
	solid(-7778, -7751, -8132, -8106, 2022)             -- crag ramp A top
	solid(-7702, -7668, -8086, -8060, 2046)             -- crag ramp B top (rope bridge, south end)
	solid(-8212, -8184, -7632, -7602, 2022)             -- Dig ramp top
end

-- 4. Everything cut out of the massifs.
function M.Carves()
	corridor(M.TUNNEL, 18, 2046, 1)                     -- Cellar Pass tunnel (floor 2030), roofed
	air(-8320, -8224, 2028, 2068, -8395, -8345)         -- portal chamber at the tunnel's back (the gate is 87 wide)
	air(-8114, -7886, 2000, 2042, -8389, -8340)         -- the Warmhouse, into the south cliff
	air(-7670, -7636, 2046, 2200, -8050, -7960)         -- crag ledge, cut back into the west wall
	air(-7763, -7650, 2010, 2200, -8060, -8050)         -- crevasse under the rope bridge (open east: no trap)
	air(-7762, -7690, 2000, 2200, -7502, -7438)         -- Nico's Point clearing
	fill(-7762, -7690, 1996, 2000, -7502, -7438, MAT.Snow) -- ...with a snow floor, not the ledge's basalt
	corridor(M.SQUEEZE, 12, 2200, #M.SQUEEZE - 1)       -- the Squeeze, ending under the ice arch
	air(-7615, -7445, 1980, 2200, -7265, -7095)         -- the Blue Hollow (floor 1982)
	air(-8032, -7968, 2000, 2200, -6853, ZN)            -- the Frozen Falls notch in the north wall
end

-- 5. The Hollow's contents and the Frozen Falls.
function M.HollowAndFalls()
	-- a snow floor, and glacier (not basalt) walls and arch: the massif's basalt band runs 34 studs up
	-- the Hollow's sides because the floor is sunk 20 below the datum, and read as a dark pit
	fill(-7615, -7445, 1976, 1980, -7265, -7095, MAT.Snow)
	T:ReplaceMaterial(Region3.new(Vector3.new(-7632, 1964, -7300), Vector3.new(-7428, 2024, -7080)):ExpandToGrid(4), 4, MAT.Basalt, MAT.Glacier)
	fill(-7487, -7441, 2058, 2108, -7265, -7095, MAT.Glacier)         -- the overhanging glacier face
	fill(-7546, -7514, 1980, 2108, -7112, -7093, MAT.Glacier)         -- frozen waterfall, north wall
	T:FillCylinder(CFrame.new(-7525, 1980.5, -7165), 1, 26, MAT.Ice)  -- the frozen pond (Warm Eye is a part)
	wedge(-8000, -6850, D, -8000, -6764, 2030, 60, MAT.Glacier)       -- Frozen Falls apron from the lake tip
	fill(-8014, -7986, 2000, 2148, -6764, ZN, MAT.Glacier)            -- the ice curtain, vertical
end

-- 6. Ramps (terrain wedges).
function M.Ramps()
	wedge(-8285, -8182, 2022, -8285, -8214, 2030, 22)                 -- Frostgate -> High Ledge
	wedge(-8138, -8222, 2016, -8194, -8222, 2030, 16)                 -- Frostgate descent, leg 1
	wedge(-8050, -8200, D, -8114, -8222, 2016, 16)                    -- descent leg 2, to the Circle
	for _, c in ipairs(M.CAMPS) do                                     -- camp terraces, Avenue side
		local edge = c.x + 42 * c.face
		wedge(edge + 18 * c.face, c.z, D, edge, c.z, D + M.TERRACE, 30)
	end
	wedge(-7768, -8192, D, -7768, -8124, 2022, 16)                    -- crag ramp A: West Road -> west ledge
	wedge(-7745, -8073, 2022, -7690, -8073, 2046, 14)                 -- crag ramp B: west ledge -> bridge
	wedge(-8192, -7706, D, -8192, -7626, 2022, 14)                    -- Elder's Dig: bank -> shelf
end

-- 7. Outside the bounds: the Sundered Peak and the caldera rim (scenery, never walkable).
function M.Outside()
	local function half(sign)   -- sign -1: the east half (x < -8000); +1: the west half
		local function X(a, b)
			local p, q = -8000 + sign * a, -8000 + sign * b
			return math.min(p, q), math.max(p, q)
		end
		local x0, x1 = X(14, 360); fill(x0, x1, BOTTOM, 2258, ZN, ZN + 400, MAT.Basalt)
		x0, x1 = X(16, 300); fill(x0, x1, 2258, 2438, ZN + 40, ZN + 370, MAT.Glacier)
		x0, x1 = X(18, 210); fill(x0, x1, 2438, 2578, ZN + 80, ZN + 330, MAT.Glacier)
		x0, x1 = X(20, 120); fill(x0, x1, 2578, 2688, ZN + 120, ZN + 280, MAT.Snow)
	end
	half(-1); half(1)
	fill(-8014, -7986, 2000, 2430, ZN, ZN + 100, MAT.Glacier)         -- the Frozen Falls, up the split
	massif(-8900, XE, -8900, -6300, 2230)                              -- rim: east
	massif(XW, -7100, -8900, -6300, 2230)                              -- rim: west
	massif(XE, XW, -8900, ZS, 2250)                                    -- rim: south
	massif(XE, -8360, ZN, -6300, 2240)                                 -- rim: north-east shoulder
	massif(-7640, XW, ZN, -6300, 2240)                                 -- rim: north-west shoulder
	for i = 0, 8 do                                                    -- lumps, so the skyline is not a ruler
		local z = -8840 + i * 300
		T:FillBall(Vector3.new(-8760, 2200, z), 110 + (i % 3) * 25, MAT.Snow)
		T:FillBall(Vector3.new(-7240, 2200, z + 150), 110 + ((i + 1) % 3) * 25, MAT.Snow)
	end
	for i = 0, 5 do
		T:FillBall(Vector3.new(-8550 + i * 230, 2220, -8760), 120 + (i % 2) * 30, MAT.Snow)
	end
end

-- Clears everything the steps above can write (inside the bounds except the lake zone, and the
-- outside scenery), so the terrain can be rebuilt from scratch or rolled back.
function M.ClearAll()
	local m, bands = M.LAKE_MARGIN, M.LAKE_BANDS
	local y0, y1 = 1950, 2262
	air(XE, XW, y0, y1, ZS, M.LAKE_SOUTH_Z)
	for i, b in ipairs(bands) do
		local z0 = (i == 1) and M.LAKE_SOUTH_Z or b.z0
		local z1 = (i == #bands) and (b.z1 + m) or b.z1
		air(XE, b.x0 - m, y0, y1, z0, z1)
		air(b.x1 + m, XW, y0, y1, z0, z1)
	end
	air(XE, XW, y0, y1, bands[#bands].z1 + m, ZN)
	air(XE, XW, 2001, y1, M.LAKE_SOUTH_Z, ZN)                          -- above the lake zone (water tops out at 2000)
	air(-8960, XE, y0, 2400, -8960, -6240)
	air(XW, -7040, y0, 2400, -8960, -6240)
	air(XE, XW, y0, 2400, -8960, ZS)
	air(XE, XW, y0, 2760, ZN, -6240)
end

-- ============================================================== GREYBOX PARTS
local C = {
	stone = Color3.fromRGB(196, 202, 208),
	timber = Color3.fromRGB(176, 136, 96),
	timberDark = Color3.fromRGB(110, 78, 50),
	roof = Color3.fromRGB(232, 238, 244),
	path = Color3.fromRGB(214, 196, 160),
	road = Color3.fromRGB(200, 182, 146),
	warm = Color3.fromRGB(255, 206, 128),
	hearth = Color3.fromRGB(232, 137, 58),
	ice = Color3.fromRGB(168, 206, 232),
	crack = Color3.fromRGB(70, 128, 190),
	ancient = Color3.fromRGB(74, 79, 87),
	brass = Color3.fromRGB(198, 148, 62),
	dark = Color3.fromRGB(24, 38, 52),
}

local function part(parent, name, size, cf, color, material, opts)
	opts = opts or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or MAT.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = opts.collide ~= false
	p.CanTouch = false
	if opts.query == false then p.CanQuery = false end
	p.CastShadow = (opts.shadow == true) or (opts.shadow == nil and math.max(size.X, size.Y, size.Z) >= 12)
	if opts.transparency then p.Transparency = opts.transparency end
	if opts.shape then p.Shape = opts.shape end
	p:SetAttribute("Greybox", true)
	p.Parent = parent
	return p
end

local function boxPart(parent, name, x0, x1, y0, y1, z0, z1, color, material, opts)
	return part(parent, name, Vector3.new(x1 - x0, y1 - y0, z1 - z0),
		CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, opts)
end

-- a flat, non-colliding path strip laid on the surface along points { x, z }
local function strip(parent, name, pts, width, color, surf)
	local y = (surf or D) + 0.12
	for i = 1, #pts - 1 do
		local a = Vector3.new(pts[i][1], y, pts[i][2])
		local b = Vector3.new(pts[i + 1][1], y, pts[i + 1][2])
		part(parent, name, Vector3.new(width, 0.2, (b - a).Magnitude + width * 0.5), CFrame.lookAt((a + b) / 2, b),
			color, MAT.SmoothPlastic, { collide = false, shadow = false, query = false })
	end
end

-- a greybox label for the walkthrough (removed at the art pass)
local function label(parent, text, pos, width, color)
	local a = part(parent, "Label", Vector3.new(1, 1, 1), CFrame.new(pos), Color3.new(1, 1, 1), MAT.SmoothPlastic,
		{ collide = false, shadow = false, transparency = 1, query = false })
	a.Name = "Label_" .. (text:gsub("[^%w]", ""))
	a:SetAttribute("GreyboxLabel", true)
	local bb = Instance.new("BillboardGui")
	bb.Name = "GreyboxLabel"
	bb.Size = UDim2.fromOffset(width or 360, 54)
	bb.MaxDistance = 450   -- only nearby labels; from far away they pile on top of each other
	bb.LightInfluence = 0
	bb.Parent = a
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = color or Color3.new(1, 1, 1)
	t.Text = text
	t.Parent = bb
	local s = Instance.new("UIStroke")
	s.Thickness = 2
	s.Color = Color3.fromRGB(20, 28, 36)
	s.Parent = t
	return a
end

local function light(p, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = p
	return l
end

local function lantern(parent, x, z, surf)
	boxPart(parent, "LanternPost", x - 0.4, x + 0.4, surf, surf + 9, z - 0.4, z + 0.4, C.timberDark, MAT.Wood, { shadow = false })
	boxPart(parent, "Lantern", x - 0.8, x + 0.8, surf + 9, surf + 10.6, z - 0.8, z + 0.8, C.warm, MAT.SmoothPlastic, { shadow = false, collide = false })
end

-- a greybox building: floor, four walls with a door gap on `doorSide` ("x0" east, "x1" west,
-- "z0" south, "z1" north), a flat roof with a snow cap
local function building(parent, name, x0, x1, z0, z1, surf, h, doorSide, doorW, doorH, color)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	local t = 2
	boxPart(f, "Floor", x0, x1, surf - 1, surf + 0.05, z0, z1, C.timberDark, MAT.WoodPlanks)
	local function wall(nm, a0, a1, b0, b1, side)
		if side ~= doorSide then
			boxPart(f, nm, a0, a1, surf, surf + h, b0, b1, color, MAT.WoodPlanks)
		elseif side == "z0" or side == "z1" then
			local mid = (a0 + a1) / 2
			boxPart(f, nm .. "A", a0, mid - doorW / 2, surf, surf + h, b0, b1, color, MAT.WoodPlanks)
			boxPart(f, nm .. "B", mid + doorW / 2, a1, surf, surf + h, b0, b1, color, MAT.WoodPlanks)
			boxPart(f, nm .. "Lintel", mid - doorW / 2, mid + doorW / 2, surf + doorH, surf + h, b0, b1, color, MAT.WoodPlanks)
		else
			local mid = (b0 + b1) / 2
			boxPart(f, nm .. "A", a0, a1, surf, surf + h, b0, mid - doorW / 2, color, MAT.WoodPlanks)
			boxPart(f, nm .. "B", a0, a1, surf, surf + h, mid + doorW / 2, b1, color, MAT.WoodPlanks)
			boxPart(f, nm .. "Lintel", a0, a1, surf + doorH, surf + h, mid - doorW / 2, mid + doorW / 2, color, MAT.WoodPlanks)
		end
	end
	wall("WallS", x0, x1, z0, z0 + t, "z0")
	wall("WallN", x0, x1, z1 - t, z1, "z1")
	wall("WallE", x0, x0 + t, z0 + t, z1 - t, "x0")
	wall("WallW", x1 - t, x1, z0 + t, z1 - t, "x1")
	boxPart(f, "Roof", x0 - 1, x1 + 1, surf + h, surf + h + 1.5, z0 - 1, z1 + 1, C.timberDark, MAT.WoodPlanks)
	boxPart(f, "RoofSnow", x0 - 1, x1 + 1, surf + h + 1.5, surf + h + 2.5, z0 - 1, z1 + 1, C.roof, MAT.Snow)
	return f
end

function M.BuildParts()
	local ft = Workspace.GameWorld.FrozenTundra
	local old = ft:FindFirstChild("Greybox")
	if old then old:Destroy() end
	local root = Instance.new("Folder")
	root.Name = "Greybox"
	root:SetAttribute("GreyboxVersion", M.VERSION)
	local function sub(n)
		local f = Instance.new("Folder")
		f.Name = n
		f.Parent = root
		return f
	end

	-- ① Cellar Pass + Frostgate
	local g = sub("CellarPass")
	do
		local a, b = M.TUNNEL[1], M.TUNNEL[2]
		local A, B = Vector3.new(a[1], 2030, a[2]), Vector3.new(b[1], 2030, b[2])
		local dir = (B - A).Unit
		-- timber ribs down the diagonal tunnel, square to it; the last one is the Frostgate frame. The
		-- carved tunnel measures about +-7 wide and 14 high inside, so the ribs stand within that
		-- (at +-8 / +17 they were buried in the rock). A dim lantern hangs from each rib; its light is
		-- near-white because warm light on the cyan glacier reads as green moss.
		for _, t in ipairs({ 0.2, 0.45, 0.7, 0.97 }) do
			local frame = CFrame.lookAt(A:Lerp(B, t), A:Lerp(B, t) + dir)
			local heavy = t > 0.9
			local w = heavy and 2 or 1
			local col = heavy and C.timber or C.timberDark
			part(g, heavy and "GatePostL" or "RibPostL", Vector3.new(w, 12.5, w), frame * CFrame.new(-6, 6.25, 0), col, MAT.Wood)
			part(g, heavy and "GatePostR" or "RibPostR", Vector3.new(w, 12.5, w), frame * CFrame.new(6, 6.25, 0), col, MAT.Wood)
			part(g, heavy and "GateLintel" or "RibBeam", Vector3.new(heavy and 14 or 13, w, w), frame * CFrame.new(0, 12.5 - w / 2, 0), col, MAT.Wood)
			if not heavy then
				light(part(g, "RibLantern", Vector3.new(1.2, 1.4, 1.2), frame * CFrame.new(0, 11.3, 0), C.warm, MAT.SmoothPlastic,
					{ collide = false, shadow = false }), Color3.fromRGB(255, 242, 226), 14, 0.6)
			end
		end
	end
	boxPart(g, "RailN", -8245, -8190, 2030, 2031.6, -8213, -8212, C.timber, MAT.Wood, { shadow = false })
	boxPart(g, "RailW", -8191, -8190, 2030, 2031.6, -8262, -8232, C.timber, MAT.Wood, { shadow = false })
	label(g, "① CELLAR PASS · FROSTGATE (+28)", Vector3.new(-8222, 2052, -8240))

	-- ② Warming Circle, ③ the Avenue, roads and shore paths
	local town = sub("Frostwatch")
	part(town, "WarmingCircle", Vector3.new(0.3, 90, 90), CFrame.new(-8000, D + 0.12, -8195) * CFrame.Angles(0, 0, math.rad(90)),
		C.path, MAT.SmoothPlastic, { collide = false, shadow = false, shape = Enum.PartType.Cylinder, query = false })
	boxPart(town, "Bonfire", -8004, -7996, D, D + 3, -8199, -8191, C.hearth, MAT.SmoothPlastic)
	boxPart(town, "Signpost", -8031, -8029, D, D + 10, -8167, -8165, C.timberDark, MAT.Wood)
	label(town, "② WARMING CIRCLE", Vector3.new(-8000, D + 14, -8195))
	strip(town, "Avenue", { { -8000, -8150 }, { -8000, -7818 } }, 24, C.path)
	for _, z in ipairs({ -8120, -8040, -7960, -7880 }) do
		lantern(town, -8016, z, D)
		lantern(town, -7984, z, D)
	end
	label(town, "③ THE SIX CAMPS", Vector3.new(-8000, D + 22, -7975))
	strip(town, "EastRoad", { { -8045, -8195 }, { -8215, -8180 }, { -8215, -7832 } }, 14, C.road)
	strip(town, "WestRoad", { { -7955, -8195 }, { -7785, -8180 }, { -7785, -7832 } }, 14, C.road)
	strip(town, "ShorePromenade", { { -8215, -7832 }, { -7785, -7832 } }, 14, C.road)
	strip(town, "EastShorePath", { { -8215, -7832 }, { -8195, -7760 }, { -8192, -7712 } }, 12, C.road)
	strip(town, "WestShorePath", { { -7785, -7832 }, { -7800, -7760 }, { -7805, -7680 }, { -7790, -7600 }, { -7770, -7530 }, { -7757, -7490 } }, 12, C.road)
	strip(town, "HighLedgePath", { { -8290, -8180 }, { -8290, -7712 } }, 10, C.road, 2022)
	label(town, "HIGH LEDGE (+20)", Vector3.new(-8290, 2034, -8000), 260)

	-- ④ the Warmhouse (the five stall models are moved in by Relocate)
	local wh = building(root, "Warmhouse", -8112, -7888, -8385, -8250, D, 36, "z1", 28, 20, C.timber)
	light(boxPart(wh, "Hearth", -8006, -7994, D, D + 2, -8321, -8309, C.hearth, MAT.SmoothPlastic), C.hearth, 30, 2)
	-- the hall is cut into the cliff and lit only through its door: without lamps the stalls are black
	for _, x in ipairs({ -8070, -8025, -7975, -7930 }) do
		for _, z in ipairs({ -8290, -8345 }) do
			light(boxPart(wh, "Lamp", x - 1, x + 1, D + 27, D + 29, z - 1, z + 1, C.warm, MAT.SmoothPlastic,
				{ shadow = false, collide = false }), C.warm, 42, 1.3)
		end
	end
	boxPart(wh, "ChimneyE", -8076, -8064, D + 36, D + 50, -8330, -8318, C.stone, MAT.Slate)
	boxPart(wh, "ChimneyW", -7936, -7924, D + 36, D + 50, -8330, -8318, C.stone, MAT.Slate)
	for _, x in ipairs({ -8080, -8045, -7955, -7920 }) do
		boxPart(wh, "WarmWindow", x - 7, x + 7, D + 10, D + 16, -8250.2, -8249.6, C.warm, MAT.SmoothPlastic, { shadow = false })
	end
	label(wh, "④ THE WARMHOUSE", Vector3.new(-8000, D + 46, -8248))

	-- ⑧ Elder's Dig (Elder Tung, the drill site and the Depths shaft are moved in by Relocate)
	local dig = sub("EldersDig")
	building(dig, "EldersStation", -8404, -8364, -7716, -7684, 2022, 16, "x1", 8, 10, C.timber)
	boxPart(dig, "Porch", -8364, -8350, 2021, 2022.4, -7716, -7684, C.timberDark, MAT.WoodPlanks, { shadow = false })
	boxPart(dig, "Chimney", -8398, -8390, 2038, 2050, -7712, -7704, C.stone, MAT.Slate)
	part(dig, "ListeningHorn", Vector3.new(12, 5, 5), CFrame.new(-8372, 2028, -7738) * CFrame.Angles(0, 0, math.rad(-30)),
		C.brass, MAT.Metal, { shape = Enum.PartType.Cylinder })
	boxPart(dig, "TheCrack", -8363, -8359, 2022.02, 2022.22, -7760, -7732, C.crack, MAT.SmoothPlastic, { collide = false, shadow = false })
	boxPart(dig, "AncientStone", -8424, -8416, 2024, 2052, -7716, -7684, C.ancient, MAT.Slate)
	label(dig, "⑧ ELDER'S DIG (+20)", Vector3.new(-8362, 2054, -7700))
	label(dig, "DRILL · DEPTHS SHAFT → WORLD 3", Vector3.new(-8345, 2038, -7734), 300, Color3.fromRGB(150, 245, 160))

	-- ⑥ Nico's Point
	local nico = sub("NicosPoint")
	building(nico, "NicosLodge", -7746, -7716, -7482, -7458, D, 14, "x0", 8, 10, C.timber)
	boxPart(nico, "StoveChimney", -7730, -7724, D + 14, D + 24, -7466, -7460, C.stone, MAT.Slate)
	boxPart(nico, "StoveGlow", -7730, -7724, D + 24, D + 25, -7466, -7460, C.warm, MAT.SmoothPlastic, { shadow = false })
	boxPart(nico, "Jetty", -7812, -7746, D - 0.5, D + 0.4, -7474, -7466, C.timberDark, MAT.WoodPlanks, { shadow = false })
	boxPart(nico, "TrophyBoard", -7747, -7746.4, D + 6, D + 11, -7482, -7474, C.timberDark, MAT.Wood, { shadow = false })
	boxPart(nico, "RodRack", -7750, -7748, D, D + 7, -7462, -7458, C.timberDark, MAT.Wood, { shadow = false })
	label(nico, "⑥ NICO'S POINT", Vector3.new(-7731, D + 30, -7470))

	-- the Squeeze: Nico's three old lanterns (his Quest 3 relights them)
	local sq = sub("TheSqueeze")
	for _, i in ipairs({ 2, 4, 6 }) do
		local p = M.SQUEEZE[i]
		lantern(sq, p[1] + 4, p[2], p[3])
	end
	label(sq, "THE SQUEEZE", Vector3.new(-7650, 2020, -7452), 240)

	-- ⑦ the Blue Hollow
	local ho = sub("BlueHollow")
	building(ho, "NicosShanty", -7596, -7582, -7232, -7220, 1982, 9, "x0", 5, 7, C.timberDark)
	part(ho, "WarmEye", Vector3.new(0.4, 10, 10), CFrame.new(-7525, 1983.3, -7165) * CFrame.Angles(0, 0, math.rad(90)),
		C.dark, MAT.SmoothPlastic, { collide = false, shadow = false, shape = Enum.PartType.Cylinder })
	for i, c in ipairs({ { -7600, -7120 }, { -7470, -7130 }, { -7460, -7240 }, { -7605, -7250 }, { -7490, -7108 } }) do
		part(ho, "Crystal", Vector3.new(4, 14 + i * 2, 4),
			CFrame.new(c[1], 1982 + 7 + i, c[2]) * CFrame.Angles(math.rad(12 * (i % 3 - 1)), math.rad(i * 37), math.rad(10)),
			C.ice, MAT.Glacier)
	end
	label(ho, "⑦ THE BLUE HOLLOW (−20)", Vector3.new(-7530, 2006, -7180))
	label(ho, "THE WARM EYE · permanent hole (after Nico Q3)", Vector3.new(-7525, 1993, -7165), 380, Color3.fromRGB(255, 214, 150))

	-- ⑨ Eagle's Crag (the Broken Watchtower and Michael are moved up by Relocate)
	local crag = sub("EaglesCrag")
	for i = 0, 6 do
		local z = -8061 + i * 2
		local y = 2046 + i * (2 / 6)
		boxPart(crag, "BridgePlank", -7690, -7680, y - 0.6, y, z - 0.9, z + 0.9, C.timberDark, MAT.WoodPlanks, { shadow = false })
	end
	boxPart(crag, "RopeE", -7690.3, -7689.7, 2049, 2049.3, -8062, -8048, C.timber, MAT.Fabric, { collide = false, shadow = false })
	boxPart(crag, "RopeW", -7680.3, -7679.7, 2049, 2049.3, -8062, -8048, C.timber, MAT.Fabric, { collide = false, shadow = false })
	-- the trail on the two flat stretches (the ramps read by themselves): along the west ledge from
	-- ramp A to ramp B -- the ledge edge is right beside it, and stepping off drops you to the road --
	-- and from the bridge to the foot of the lookout ramp
	strip(crag, "CragTrail", { { -7768, -8126 }, { -7745, -8118 }, { -7745, -8080 } }, 8, C.road, 2022)
	strip(crag, "CragTrail", { { -7685, -8049 }, { -7662, -8042 } }, 8, C.road, 2048)
	-- Michael's lookout. He perches on the tower's broken top (y 2082), 34 above the summit and far
	-- outside his prompt's 18-stud reach from the ground, so a timber ramp climbs the tower's east
	-- side, starting where the rope bridge lands, to a gallery along its north face just below him
	-- (prompt ~12 studs from the gallery's west end). "Michael = a climb to a secret trade."
	-- (First pass ran the ramp west-to-east with its foot against the glacier wall: walking in from
	-- the bridge you met its underside, so nobody could get on it. Walked in Play 2026-09-19.)
	local LOOK_Y = 2074
	local G0, G1 = -7993.5, -7983.5   -- the gallery's south and north edges; the tower's north face is at ~-7994.5
	boxPart(crag, "LookoutGallery", -7702, -7659, LOOK_Y - 1, LOOK_Y, G0, G1, C.timberDark, MAT.WoodPlanks)
	local ra, rb = Vector3.new(-7662, LOOK_Y, G0), Vector3.new(-7662, 2048, G0 - 44)
	local len, rampCF = (rb - ra).Magnitude, CFrame.lookAt((ra + rb) / 2, rb)
	part(crag, "LookoutRamp", Vector3.new(6, 1, len), rampCF * CFrame.new(0, -0.5, 0), C.timberDark, MAT.WoodPlanks)
	for _, s in ipairs({ -1, 1 }) do
		part(crag, "LookoutRampRail", Vector3.new(0.5, 3, len), rampCF * CFrame.new(s * 3.25, 1.5, 0), C.timber, MAT.Wood, { shadow = false })
		boxPart(crag, "LookoutRampPost", -7662 + s * 2.5 - 0.5, -7662 + s * 2.5 + 0.5, 2048, (ra.Y + rb.Y) / 2 - 1, G0 - 22.5, G0 - 21.5, C.timberDark, MAT.Wood)
	end
	boxPart(crag, "LookoutRailN", -7702, -7659, LOOK_Y, LOOK_Y + 3, G1 - 0.5, G1, C.timber, MAT.Wood, { shadow = false })
	boxPart(crag, "LookoutRailW", -7702.5, -7702, LOOK_Y, LOOK_Y + 3, G0, G1, C.timber, MAT.Wood, { shadow = false })
	boxPart(crag, "LookoutRailE", -7659.5, -7659, LOOK_Y, LOOK_Y + 3, G0, G1, C.timber, MAT.Wood, { shadow = false })
	-- the south edge is railed except where the tower's face is right behind it and at the ramp's top
	boxPart(crag, "LookoutRailS", -7702, -7695, LOOK_Y, LOOK_Y + 3, G0 - 0.5, G0, C.timber, MAT.Wood, { shadow = false })
	boxPart(crag, "LookoutRailS", -7682, -7665, LOOK_Y, LOOK_Y + 3, G0 - 0.5, G0, C.timber, MAT.Wood, { shadow = false })
	for _, x in ipairs({ -7701, -7687, -7673, -7660 }) do
		for _, z in ipairs({ G1 - 1, G0 + 1 }) do
			boxPart(crag, "LookoutPost", x - 0.6, x + 0.6, 2048, LOOK_Y - 1, z - 0.6, z + 0.6, C.timberDark, MAT.Wood)
		end
	end
	label(crag, "⑨ EAGLE'S CRAG (+46)", Vector3.new(-7700, 2090, -8005))

	-- ⑤ the lake, ⑩ the peak
	label(root, "⑤ THE FROZEN LAKE", Vector3.new(-8000, 2030, -7500))
	local peak = label(root, "⑩ THE SUNDERED PEAK", Vector3.new(-8000, 2520, -6690), 440)
	peak.GreyboxLabel.MaxDistance = 6000

	root.Parent = ft
	return root
end

-- ============================================================== RELOCATION (one time)
-- Moves the KEPT objects into the new layout. Each object is stamped BlockoutMoved so a second run
-- is a no-op. Names and parents are never changed -- scripts find these by name and path.
function M.Relocate()
	local log = {}
	local gw = Workspace.GameWorld
	local ft = gw.FrozenTundra

	-- camps: move, raise onto the terrace, and turn so each PlotBoard faces the Avenue
	for _, c in ipairs(M.CAMPS) do
		local plot = Workspace.PlayerBases:FindFirstChild(c.plot)
		if plot and not plot:GetAttribute("BlockoutMoved") then
			local piv = plot:GetPivot()
			local board = plot:FindFirstChild("PlotBoard")
			local dir = Vector3.new(c.face, 0, 0)
			if board then
				local d = board:GetPivot().Position - piv.Position
				if Vector3.new(d.X, 0, d.Z).Magnitude > 1 then dir = Vector3.new(d.X, 0, d.Z).Unit end
			end
			local theta = math.atan2(c.face, 0) - math.atan2(dir.X, dir.Z)
			local pos = Vector3.new(c.x, piv.Position.Y + M.TERRACE, c.z)
			plot:PivotTo(CFrame.new(pos) * CFrame.Angles(0, theta, 0) * (piv - piv.Position))
			plot:SetAttribute("BlockoutMoved", true)
			table.insert(log, ("%s -> (%d, %d) turned %.0f deg"):format(c.plot, c.x, c.z, math.deg(theta)))
		end
	end

	-- the five stalls and their prompt models, into the Warmhouse (one rigid shift)
	local stalls = ft:FindFirstChild("Hub") and ft.Hub:FindFirstChild("Stalls")
	if stalls and not stalls:GetAttribute("BlockoutMoved") then
		for _, m in ipairs(stalls:GetChildren()) do m:PivotTo(m:GetPivot() + M.STALL_SHIFT) end
		for _, n in ipairs({ "TundraShopStall", "TundraSellStall", "TundraEggStall", "TundraUpgradeStall", "TundraCharmStall" }) do
			local m = gw:FindFirstChild(n)
			if m then m:PivotTo(m:GetPivot() + M.STALL_SHIFT) end
		end
		stalls:SetAttribute("BlockoutMoved", true)
		table.insert(log, "stalls + prompt models shifted " .. tostring(M.STALL_SHIFT))
	end

	-- Elder Tung, the drill site and the Depths shaft move as ONE rigid unit (the cutscenes need it)
	local site = ft:FindFirstChild("DrillSite")
	if site and not site:GetAttribute("BlockoutMoved") then
		local xf = M.DRILL_SITE * site.CFrame:Inverse()
		local npc = ft:FindFirstChild("ElderTungTundra")
		if npc then
			npc:PivotTo(xf * npc:GetPivot())
			-- he stood on his old hut's floor, 1.9 above the site; there is no floor here, so ground him
			local cf, s = npc:GetBoundingBox()
			npc:PivotTo(npc:GetPivot() - Vector3.new(0, cf.Position.Y - s.Y / 2 - M.DRILL_SITE.Position.Y, 0))
		end
		local dp = gw.Portals:FindFirstChild("DepthsPortal")
		if dp then
			dp:PivotTo(xf * dp:GetPivot())
			local touch = dp:FindFirstChild("PortalTouch", true)
			if touch then
				touch:SetAttribute("RefuseX", M.DEPTHS_REFUSE.X)
				touch:SetAttribute("RefuseY", M.DEPTHS_REFUSE.Y)
				touch:SetAttribute("RefuseZ", M.DEPTHS_REFUSE.Z)
			end
		end
		site.CFrame = M.DRILL_SITE
		site:SetAttribute("BlockoutMoved", true)
		table.insert(log, "Elder Tung + DrillSite + DepthsPortal -> Elder's Dig")
	end

	-- the Broken Watchtower up to Eagle's Crag, and Michael onto its top (his path stays FrozenTundra.Michel)
	local tower = ft:FindFirstChild("Ruins") and ft.Ruins:FindFirstChild("BrokenWatchtower")
	if tower and not tower:GetAttribute("BlockoutMoved") then
		local cf, size = tower:GetBoundingBox()
		local base = Vector3.new(cf.Position.X, cf.Position.Y - size.Y / 2, cf.Position.Z)
		tower:PivotTo(tower:GetPivot() + (M.TOWER_BASE - base))
		tower:SetAttribute("BlockoutMoved", true)
		table.insert(log, "Broken Watchtower -> Eagle's Crag")
	end
	local michel = ft:FindFirstChild("Michel")
	if michel and tower and not michel:GetAttribute("BlockoutMoved") then
		local tcf, tsize = tower:GetBoundingBox()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { tower }
		local topY = tcf.Position.Y + tsize.Y / 2
		local best
		for dx = -6, 6, 3 do
			for dz = -6, 6, 3 do
				local hit = Workspace:Raycast(Vector3.new(tcf.Position.X + dx, topY + 5, tcf.Position.Z + dz), Vector3.new(0, -tsize.Y - 10, 0), params)
				if hit and (not best or hit.Position.Y > best.Position.Y) then best = hit end
			end
		end
		local mcf, msize = michel:GetBoundingBox()
		local target = best and best.Position or Vector3.new(tcf.Position.X, topY, tcf.Position.Z)
		local from = Vector3.new(mcf.Position.X, mcf.Position.Y - msize.Y / 2, mcf.Position.Z)
		michel:PivotTo(michel:GetPivot() + (target - from))
		michel:SetAttribute("BlockoutMoved", true)
		table.insert(log, ("Michael -> tower top at y %.1f"):format(target.Y))
	end

	-- the way home: the TundraReturnPortal gate, turned to face north against the chamber's south wall
	local rp = gw.Portals:FindFirstChild("TundraReturnPortal")
	if rp and not rp:GetAttribute("BlockoutMoved") then
		local piv = rp:GetPivot()
		rp:PivotTo(CFrame.new(M.PORTAL_TOUCH) * CFrame.Angles(0, math.rad(90), 0) * (piv - piv.Position))
		rp:SetAttribute("BlockoutMoved", true)
		table.insert(log, "TundraReturnPortal -> portal chamber")
	end

	-- the daily wheel and the leaderboards, to the Avenue's mouth (WheelBoard / LeaderboardBoards
	-- constants are updated to match, so a layout-version rebuild lands in the same place)
	local wheel = gw:FindFirstChild("DailyWheelTundra")
	if wheel and not wheel:GetAttribute("BlockoutMoved") then
		local p = wheel:GetPivot().Position
		wheel:PivotTo(wheel:GetPivot() + Vector3.new(M.WHEEL_PIVOT.X - p.X, 0, M.WHEEL_PIVOT.Z - p.Z))
		wheel:SetAttribute("BlockoutMoved", true)
		table.insert(log, "DailyWheelTundra -> Avenue mouth")
	end
	local lb = gw:FindFirstChild("LeaderboardsTundra")
	if lb and not lb:GetAttribute("BlockoutMoved") then
		local d = Vector3.new(M.BOARDS_AT.X - -8040, 0, M.BOARDS_AT.Z - -7840)
		for _, m in ipairs(lb:GetChildren()) do
			if m:IsA("Model") then m:PivotTo(m:GetPivot() + d) end
		end
		lb:SetAttribute("BlockoutMoved", true)
		table.insert(log, "LeaderboardsTundra -> Avenue mouth")
	end
	return log
end

-- The old geometry the blockout replaces, reparented (not destroyed) into the backup folder.
function M.StashOld(backup)
	local ft = Workspace.GameWorld.FrozenTundra
	local dest = backup:FindFirstChild("RemovedFromWorkspace")
	if not dest then
		dest = Instance.new("Folder")
		dest.Name = "RemovedFromWorkspace"
		dest.Parent = backup
	end
	local moved = {}
	for _, n in ipairs({ "Ground", "Decor", "Icebergs", "Village", "Relief", "Floes", "ShelfEdge", "IceSpikes", "ElderHut" }) do
		local c = ft:FindFirstChild(n)
		if c then c.Parent = dest; table.insert(moved, n) end
	end
	local hub = ft:FindFirstChild("Hub")
	if hub then
		local hd = dest:FindFirstChild("Hub") or Instance.new("Folder")
		hd.Name = "Hub"
		hd.Parent = dest
		for _, c in ipairs(hub:GetChildren()) do
			if c.Name ~= "Stalls" then c.Parent = hd; table.insert(moved, "Hub." .. c.Name) end
		end
	end
	local ruins = ft:FindFirstChild("Ruins")
	if ruins then
		local rd = dest:FindFirstChild("Ruins") or Instance.new("Folder")
		rd.Name = "Ruins"
		rd.Parent = dest
		for _, n in ipairs({ "RuinedHamlet", "AbandonedOutpost" }) do
			local c = ruins:FindFirstChild(n)
			if c then c.Parent = rd; table.insert(moved, "Ruins." .. n) end
		end
	end
	return moved
end

return M
