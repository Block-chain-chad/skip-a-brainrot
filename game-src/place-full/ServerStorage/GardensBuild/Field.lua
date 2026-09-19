-- GardensField -- THE COMPOSITION OF WORLD 3, as one shared definition.
--
-- Terrain, water, roads, building footprints and prop scattering ALL read their
-- heights from F.ground(). That is the whole point: a world assembled from separate
-- guesses about "roughly where the ground is" ends up with floating rocks and
-- half-buried walls. There is one surface here and everything sits on it.
--
-- Local coordinates throughout: X east, Z south-ish, Y up, origin at Lib.ORIGIN.
-- The main progression runs along -Z:
--     arrival gorge (z 1240) -> HUB (z 700) -> river (z 360) -> TOWN (z -260)
--     -> hill face -> CATHEDRAL on the plateau (z -880)

local L = require(script.Parent.Lib)
local F = {}

F.HALF        = 1480          -- terrain extends to +/- this
F.PLAY        = 1230          -- perimeter wall starts here

F.HUB         = Vector2.new(0, 700)
F.HUB_R       = 235
F.HUB_Y       = 8

F.HILL        = Vector2.new(30, -880)
F.HILL_TOP    = 340
F.PLATEAU_R   = 230
F.HILL_FOOT   = 820

F.TOWN        = Vector2.new(-40, -250)
F.CASCADE     = Vector2.new(-1120, 380)
F.SUNKEN      = Vector2.new(-930, 930)
F.FUNGAL      = Vector2.new(1060, 650)
F.ROOTWAY_A   = Vector2.new(700, -300)
F.ROOTWAY_B   = Vector2.new(1060, -770)
F.WEEPING     = Vector2.new(-1010, -620)
F.WHISPER     = Vector2.new(1150, -1050)
F.ARRIVAL     = Vector2.new(0, 1280)

F.WATER       = 2             -- the connected water table (river, pools, sunken ruins)
F.RIVER_BED   = -18
F.RIVER_W     = 62            -- half-width of the channel floor

-- The Silverwend, west to east across the map. The hub sits south of it, the town north.
F.RIVER = {
	Vector2.new(-1120, 380), Vector2.new(-880, 300), Vector2.new(-600, 372),
	Vector2.new(-330, 424), Vector2.new(-60, 366), Vector2.new(220, 300),
	Vector2.new(520, 356), Vector2.new(800, 322), Vector2.new(1080, 250),
	Vector2.new(1330, 176),
}
-- The arrival gorge: a narrow winding slot that opens into the hub.
F.GORGE = {
	Vector2.new(0, 1330), Vector2.new(-70, 1258), Vector2.new(45, 1186),
	Vector2.new(-40, 1104), Vector2.new(30, 1022), Vector2.new(0, 946),
}
F.ARRIVAL_CHAMBER = Vector2.new(0, 1318)   -- where the return portal stands

local smooth, fbm, segDist = L.smooth, L.fbm, L.segDist

local function gauss(d, r)
	local t = math.clamp(d / r, 0, 1)
	return (1 - t * t) ^ 2
end

-- Squircle distance -- a rounded square, so the cavern is not a plain circle.
-- Exponent 6 rather than 4: at 4 the corners read as further out and got walled off
-- first, which quietly shrank the playable area to a disc.
local function squircle(x, z)
	local ax, az = math.abs(x), math.abs(z)
	return (ax ^ 6 + az ^ 6) ^ (1 / 6)
end
F.squircle = squircle

-- distance to a polyline, plus how far along it (0..1)
local function polyDist(x, z, pts)
	local best, bestU = 1e9, 0
	local total = 0
	local lens = {}
	for i = 1, #pts - 1 do
		local l = (pts[i + 1] - pts[i]).Magnitude
		lens[i] = l
		total = total + l
	end
	local acc = 0
	for i = 1, #pts - 1 do
		local d, t = segDist(x, z, pts[i].X, pts[i].Y, pts[i + 1].X, pts[i + 1].Y)
		if d < best then
			best = d
			bestU = (acc + lens[i] * t) / total
		end
		acc = acc + lens[i]
	end
	return best, bestU
end
F.polyDist = polyDist

-- The hill's radial profile. The exponent flattens the skirt so the town has gentle
-- ground to stand on, and steepens the middle so the hill face is dramatic.
function F.hillHeight(r)
	if r <= F.PLATEAU_R then return F.HILL_TOP end
	local t = (r - F.PLATEAU_R) / (F.HILL_FOOT - F.PLATEAU_R)
	if t >= 1 then return 0 end
	return F.HILL_TOP * (1 - smooth(t)) ^ 2.6
end

----------------------------------------------------------------------------------
-- GROUND
----------------------------------------------------------------------------------
-- `ch` is the ceiling at this column. The writer already has it, and recomputing it
-- here doubled the noise cost of the single hottest function in the build.
function F.ground(x, z, ch)
	-- 1. rolling base
	local h = 16
		+ fbm(x / 620, z / 620, 11, 4, 1, 0.5) * 30
		+ fbm(x / 190, z / 190, 23, 3, 1, 0.5) * 9

	-- 2. THE HILL
	local hr = math.sqrt((x - F.HILL.X) ^ 2 + (z - F.HILL.Y) ^ 2)
	local hh = F.hillHeight(hr)
	if hh > 0 then
		-- ridges and gullies so it is not a smooth cone
		local ridge = fbm(x / 150, z / 150, 71, 3, 1, 0.55) * 26 * math.min(hh / 120, 1)
		h = math.max(h, hh + ridge)
	end

	-- 3. HUB PLATEAU -- flat, then blended out to the surrounding ground
	local dHub = math.sqrt((x - F.HUB.X) ^ 2 + (z - F.HUB.Y) ^ 2)
	if dHub < F.HUB_R + 150 then
		local w = 1 - smooth((dHub - F.HUB_R) / 150)
		h = h + (F.HUB_Y - h) * math.clamp(w, 0, 1)
	end

	-- 4. THE FUNGAL HOLLOW -- a sunken bowl inside a raised rim, east
	local dF = math.sqrt((x - F.FUNGAL.X) ^ 2 + (z - F.FUNGAL.Y) ^ 2)
	if dF < 430 then
		local rim = gauss(math.abs(dF - 330), 120) * 120
		h = h + rim
		if dF < 250 then
			local w = 1 - smooth((dF - 130) / 120)
			h = h + (22 - h) * math.clamp(w, 0, 1)
		end
	end

	-- 5. THE WEEPING CLIFFS -- a high shelf ending in a GENUINE cliff, northwest.
	--    The first version dropped 150 studs over a 250-stud run, which is a 31-degree
	--    hillside. You cannot hang a waterfall on a hillside, and the whole point of
	--    this landmark is the row of falls down its face, so the face is now short and
	--    steep (~67 degrees) with a broad flat top for the hidden grove to sit on.
	local dW = math.sqrt((x - F.WEEPING.X) ^ 2 + (z - F.WEEPING.Y) ^ 2)
	if dW < 460 then
		-- notches in the lip, so the falls have somewhere to pour from
		local notch = fbm(x / 55, z / 55, 91, 2, 1, 0.5) * 26
		local face = 1 - smooth(math.clamp((dW - 158) / 74, 0, 1))
		local shelf = (172 + notch) * face
		h = math.max(h, shelf + fbm(x / 90, z / 90, 97, 2, 1, 0.5) * 10 * face)
	end

	-- 6. THE ROOTWAY RAVINE -- a deep slot between two shoulders, northeast
	local dR = polyDist(x, z, {F.ROOTWAY_A, F.ROOTWAY_B})
	if dR < 300 then
		local shoulder = gauss(math.max(dR - 90, 0), 210) * 130
		h = h + shoulder
		if dR < 88 then
			local w = 1 - smooth(dR / 88)
			h = h + (-46 - h) * math.clamp(w, 0, 1)
		end
	end

	-- 7. THE ARRIVAL GORGE MASS -- everything south of the hub is a high rock mass.
	--    The slot through it is cut in step 12, AFTER the perimeter wall, because the
	--    wall would otherwise fill the tunnel back in and seal the entrance.
	if z > 900 then
		h = math.max(h, 300 * smooth((z - 900) / 190))
	end

	-- 8. THE GREAT CASCADE BASIN -- a deep plunge pool under the west chimney
	local dC = math.sqrt((x - F.CASCADE.X) ^ 2 + (z - F.CASCADE.Y) ^ 2)
	if dC < 400 then
		local w = 1 - smooth(math.clamp((dC - 150) / 250, 0, 1))
		h = h + (-36 - h) * math.clamp(w, 0, 1) * 0.92
	end

	-- 9. THE SUNKEN RUINS -- a flooded plaza, southwest.
	--    The bed used to be -3 with +/-6 of noise on it, which straddles the water
	--    table: half the basin came out as dry sandbars and the waterline broke into
	--    contour stripes. It is now decisively UNDER water with gentle relief, and the
	--    dry parts are deliberate islands rather than an accident of the noise.
	local dS = math.sqrt((x - F.SUNKEN.X) ^ 2 + (z - F.SUNKEN.Y) ^ 2)
	if dS < 380 then
		local w = 1 - smooth(math.clamp((dS - 120) / 260, 0, 1))
		local bed = -8 + fbm(x / 150, z / 150, 55, 2, 1, 0.5) * 3.5
		h = h + (bed - h) * math.clamp(w, 0, 1)
		-- deliberate islands for the colonnade to stand on
		-- tall enough to clear the damp-margin band and carry real grass
		for _, isl in ipairs({
			{-1010, 860, 74, 26}, {-846, 986, 64, 23}, {-960, 1046, 52, 19}, {-1060, 950, 44, 17},
		}) do
			h = h + gauss(math.sqrt((x - isl[1]) ^ 2 + (z - isl[2]) ^ 2), isl[3]) * isl[4]
		end
		-- one deep pocket you have to swim
		h = h - gauss(math.sqrt((x + 1000) ^ 2 + (z - 1010) ^ 2), 90) * 14
	end

	-- 9b. THE TOWN SHELF. Between roughly z +60 and z -200 the natural ground sits at
	--     0..5, which is UNDER the water table -- the southern half of Aelunmyr came
	--     out as a lake with houses standing in it. This lifts that trough into a dry
	--     shelf for the town, blending out to nothing at its edges so the hill behind
	--     and the river valley in front are untouched.
	do
		local tx = (x + 20) / 420
		local tz = (z + 160) / 320
		local td = math.sqrt(tx * tx + tz * tz)
		if td < 1 then
			h = math.max(h, 22 * (1 - smooth(td)))
		end
	end

	-- 10. THE RIVER -- carved last among the landforms so it wins over them
	local dRiv, uRiv = polyDist(x, z, F.RIVER)
	if dRiv < 190 then
		local bed = F.RIVER_BED + math.sin(uRiv * 22) * 3
		local w = 1 - smooth(math.clamp((dRiv - F.RIVER_W) / 128, 0, 1))
		h = h + (bed - h) * math.clamp(w, 0, 1)
	end

	-- 11. PERIMETER WALL -- the cavern closes in. Steep, so it reads as rock wall.
	--     The wall line is pushed in and out by noise: a clean squircle produced a
	--     smooth ring whose voxel stair-stepping lined up into perfectly parallel
	--     horizontal terraces all the way round. Breaking the line up turns those
	--     bands into buttresses, spurs and alcoves instead.
	local d = squircle(x, z) + fbm(x / 210, z / 210, 313, 3, 1, 0.55) * 105
		+ fbm(x / 74, z / 74, 317, 2, 1, 0.5) * 26
	if d > F.PLAY then
		local up = 940 * smooth((d - F.PLAY) / 250) ^ 1.1
		h = math.max(h, 10 + up)
	end

	-- 12. THE GORGE SLOT -- cut last so it punches THROUGH the perimeter wall and the
	--     gorge mass alike. This is the only way into the world on foot.
	if z > 900 then
		local dG = polyDist(x, z, F.GORGE)
		-- the arrival chamber at the far end is wider, so the portal has a room
		local dCham = math.sqrt((x - F.ARRIVAL_CHAMBER.X) ^ 2 + (z - F.ARRIVAL_CHAMBER.Y) ^ 2)
		local inner = 46 + 46 * (1 - smooth(math.clamp(dCham / 110, 0, 1)))
		if dG < inner + 90 then
			local floor = 26 + fbm(x / 70, z / 70, 33, 2, 1, 0.5) * 5
			local w = 1 - smooth(math.clamp((dG - inner) / 90, 0, 1))
			h = h + (floor - h) * math.clamp(w, 0, 1)
		end
	end

	-- 13. SHORELINE SHARPENING. Ground that sits within a couple of studs of the water
	--     table over broad flat land does not read as a beach -- at 4-stud voxels it
	--     combs into alternating wet/dry contour stripes. Pushing heights away from the
	--     waterline turns that mush into a definite edge.
	local dw = h - F.WATER
	if dw > -5 and dw < 5 and dw ~= 0 then
		local s = math.abs(dw) / 5
		h = F.WATER + (dw < 0 and -1 or 1) * 5 * s ^ 0.45
	end

	-- keep the wall from being taller than it needs to be (pure voxel savings --
	-- nothing above the ceiling is ever visible from inside the cavern)
	ch = ch or F.ceiling(x, z)
	if h > ch + 45 then h = ch + 45 end
	return h
end

----------------------------------------------------------------------------------
-- CEILING
----------------------------------------------------------------------------------
function F.ceiling(x, z)
	local c = 440 + fbm(x / 420, z / 420, 131, 3, 1, 0.5) * 55

	-- vaults over the two great spaces
	local dHub = math.sqrt((x - F.HUB.X) ^ 2 + (z - F.HUB.Y) ^ 2)
	c = c + gauss(dHub, 470) * 180

	local dHill = math.sqrt((x - F.HILL.X) ^ 2 + (z - F.HILL.Y) ^ 2)
	c = c + gauss(dHill, 620) * 360      -- must clear the cathedral spires

	-- the chimney the Great Cascade falls out of
	local dC = math.sqrt((x - F.CASCADE.X) ^ 2 + (z - F.CASCADE.Y) ^ 2)
	c = c + gauss(dC, 300) * 210

	-- the gorge is a tight slot, not a hall (but still tall enough to feel like a
	-- canyon rather than a crawlspace once the perimeter cove is added on top)
	if z > 900 then
		c = c - 145 * smooth((z - 900) / 200)
	end

	-- cove down to meet the perimeter wall, so wall and ceiling curve into each
	-- other instead of meeting at a hard corner
	local d = squircle(x, z)
	if d > 1030 then
		c = c - 170 * smooth((d - 1030) / 300)
	end
	return math.max(c, 96)   -- never let the cove pinch the roof below head height
end

-- Openings in the ceiling. These are why the cavern is lit at all: shafts of daylight
-- fall through them onto the hub, the cathedral and the cascade.
F.FISSURES = {
	{c = Vector2.new(0, 690),     rx = 165, rz = 110},  -- over the hub market
	{c = Vector2.new(30, -880),   rx = 205, rz = 165},  -- over the cathedral
	{c = Vector2.new(-1120, 330), rx = 95,  rz = 210},  -- the cascade pours from here
	{c = Vector2.new(1060, 650),  rx = 80,  rz = 62},   -- over the fungal hollow
	{c = Vector2.new(-330, 424),  rx = 55,  rz = 130},  -- a slot over the river bend
	{c = Vector2.new(880, -560),  rx = 70,  rz = 95},   -- over the rootway ravine
}

function F.fissure(x, z)
	for _, f in ipairs(F.FISSURES) do
		local dx = (x - f.c.X) / f.rx
		local dz = (z - f.c.Y) / f.rz
		local d2 = dx * dx + dz * dz
		if d2 < 1 then
			-- ragged edge rather than a clean ellipse
			local edge = fbm(x / 45, z / 45, 177, 2, 1, 0.5) * 0.26
			if d2 < (0.88 + edge) then return true end
		end
	end
	return false
end

----------------------------------------------------------------------------------
-- MATERIALS
----------------------------------------------------------------------------------
-- slope is |gradient| of the ground, computed by the writer and passed in
function F.material(x, z, h, slope)
	local d = squircle(x, z)
	-- perimeter wall and the gorge walls are bare rock
	if d > F.PLAY + 40 or (z > 960 and h > 150) then
		return (h > 300) and Enum.Material.Basalt or Enum.Material.Rock
	end
	if h < F.WATER - 1 then
		return Enum.Material.Sand           -- riverbeds and pool floors
	end
	if slope > 1.55 then
		return (h > 240) and Enum.Material.Rock or Enum.Material.Slate
	end
	if slope > 1.15 then
		-- bare rock only on genuinely steep ground; at 0.85 the small-scale noise was
		-- enough to turn a third of the lush world grey
		return Enum.Material.Rock
	end
	if h > 250 then
		return Enum.Material.Grass          -- the hilltop is lighter moss
	end
	if h < F.WATER + 2.5 then
		-- A NARROW damp margin only. At 5 studs this band swallowed whole islands and
		-- turned them into dark brown blobs that read as holes in the world.
		return Enum.Material.Ground
	end
	local n = fbm(x / 110, z / 110, 211, 2, 1, 0.5)
	if n > 0.28 then return Enum.Material.Grass end
	return Enum.Material.LeafyGrass
end

function F.ceilingMaterial(x, z)
	local dHub = math.sqrt((x - F.HUB.X) ^ 2 + (z - F.HUB.Y) ^ 2)
	local dHill = math.sqrt((x - F.HILL.X) ^ 2 + (z - F.HILL.Y) ^ 2)
	if dHub < 420 or dHill < 520 then
		-- the lit vaults read warm, like the reference image's glowing stone
		return (L.fbm(x / 130, z / 130, 251, 2, 1, 0.5) > 0.1) and Enum.Material.Sandstone or Enum.Material.Rock
	end
	return Enum.Material.Basalt
end

-- How deep below the surface to fill. Cave country needs real rock to tunnel through.
F.CAVE_ZONES = {
	{c = Vector2.new(1150, -1050), r = 420, depth = 190},  -- Whisperdeep
	{c = Vector2.new(-1120, 380),  r = 340, depth = 170},  -- behind the Great Cascade
	{c = Vector2.new(-1010, -620), r = 380, depth = 170},  -- Weeping Cliffs
	{c = Vector2.new(880, -560),   r = 300, depth = 160},  -- Rootway walls
	{c = Vector2.new(30, -880),    r = 500, depth = 150},  -- the hill (grottoes)
	{c = Vector2.new(0, 1180),     r = 400, depth = 170},  -- gorge walls
}

function F.shellDepth(x, z)
	local d = 30
	for _, cz in ipairs(F.CAVE_ZONES) do
		local dd = math.sqrt((x - cz.c.X) ^ 2 + (z - cz.c.Y) ^ 2)
		if dd < cz.r then
			d = math.max(d, 30 + (cz.depth - 30) * (1 - smooth(dd / cz.r)))
		end
	end
	if F.squircle(x, z) > F.PLAY - 60 then d = math.max(d, 120) end
	return d
end

-- Is this column open water at the shared table height?
function F.isWater(x, z)
	return F.ground(x, z) < F.WATER - 0.5
end

return F
