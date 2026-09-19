-- IceFishingEvent -- the World-2 blizzard ice-fishing event, end to end.
--
-- Every real-clock hour the Frozen Tundra lake freezes for 20 minutes: the invisible
-- LakeBarrier drops, a walkable ice sheet covers the terrain water, holes are augered
-- through it, and every tundra player's ROCK SATCHEL is swapped for a fishing rod.
-- Fishing at a hole runs a cast whose speed comes from the equipped rock's REACH and
-- whose luck feeds catch rarity (IceFishingConfig.RollBite) and, through it, which of the
-- 23 exclusive tundra fish comes up (RollCatch). When it thaws, anyone still out on the
-- ice is teleported home to their tundra camp, the satchel comes back and the lake is
-- restored.
--
-- WORLD 2 ONLY. Nothing here touches the valley. All numbers live in IceFishingConfig.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Cfg = require(ReplicatedStorage.Modules.IceFishingConfig)
local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local WorldProgression = require(ReplicatedStorage.Modules.WorldProgression)
local RodService = require(ServerScriptService.Modules.RodService)
local RockSlingService = require(ServerScriptService.Modules.RockSlingService)
-- The catch grant mirrors ThrowHandler.revealCatch: same mutation/size axes, same
-- inventory hand-off. "Mutations reuse your existing pool -- nothing here adds a new
-- mutation axis" (owner's call, 2026-08-21).
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)
local Sizes = require(ReplicatedStorage.Modules.SizeConfig)
local RebirthConfig = require(ReplicatedStorage.Modules.RebirthConfig)
local RarityConfigTundra = require(ReplicatedStorage.Modules.RarityConfigTundra)
local InventoryHandler = require(ServerScriptService.Modules.InventoryHandler)
local PetHandler = require(ServerScriptService.Modules.PetHandler)
-- Same paid cap a throw is held to (Deep Pockets raises BagConfig.BrainrotCap); a fish
-- must respect it too or the upgrade means nothing on this faucet.
local BagConfig = require(ReplicatedStorage.Modules.BagConfig)
-- REVEAL CUTS (2026-09-17): a landed fish routes through the same Config.CUT_FOR and the
-- same CatchCinematic broadcast a throw does (spec S5.5). Soft dependency, exactly as in
-- ThrowHandler: a broken cinematic module must never eat a fish.
local okCin, CinematicConfig = pcall(function()
	return require(ReplicatedStorage.Modules.CatchCinematic.Config)
end)
if not okCin or type(CinematicConfig) ~= "table" or type(CinematicConfig.CUT_FOR) ~= "function" then
	warn("[IceFishingEvent] CatchCinematic.Config unavailable (" .. tostring(CinematicConfig) .. "); fishing cuts are disabled for this server")
	CinematicConfig = { CUT_FOR = function() return nil end }
end

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local TUNDRA_ARRIVAL = Vector3.new(-8243, 2034, -8283)   -- TeleportService.TUNDRA_POS, the fallback drop

-- rarity name -> its ladder color, for the RareCatch banner (mirrors tier.Color in
-- ThrowHandler.revealCatch). Built once from World 2's own ladder, not World 1's.
local COLOR_BY_RARITY = {}
for _, t in ipairs(RarityConfigTundra) do COLOR_BY_RARITY[t.Name] = t.Color end

local IceFishingEvent = {}

local active = false
local activeEndsAt = 0
local rigFolder      -- the spawned IceFishing folder (sheet + holes), destroyed on thaw
local holes = {}     -- the FishingHole parts built this freeze
local savedWall = {} -- [wall] = original CanCollide, so thaw restores exactly
local fishing = {}   -- [player] = cast token (truthy while a cast is in flight)
local pendingBand = {} -- [player] = { min, max, issuedAt } -- the one PERFECT-cast band they may cash in next

-- Rate-limits the "your bag is full" toast on a landed fish that has nowhere to go --
-- same shape as ThrowHandler's lastFullWarn/FULL_WARN_COOLDOWN, but IceFishingEvent's OWN
-- local table (not reaching into ThrowHandler's), so the two faucets' cooldowns can never
-- starve each other.
local lastFishFullWarn = {}   -- [userId] = os.clock() of the last "bag is full" toast
local FISH_FULL_WARN_COOLDOWN = 8

local function remote(name)
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = remotes
	end
	return r
end
local function remoteFn(name)
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteFunction")
		r.Name = name
		r.Parent = remotes
	end
	return r
end
local stateRemote  = remote("IceFishingState")
local castRemote   = remote("IceFishingCast")
local cancelRemote = remote("IceFishingCancel")
local reelRemote  = remote("IceFishingReel")
local sweetRemote  = remoteFn("IceFishingSweetSpot")   -- issues the PERFECT-cast band

-- ===== world lookups =========================================================
local function skipArea()
	local node = workspace
	for _, name in ipairs(Cfg.SKIP_AREA_PATH) do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function inTundra(player)
	return PlayerDataManager.PlayerWorld(player) == "Tundra"
end

local function onLake(hrp)
	local p = hrp.Position
	local c = Cfg.LAKE_CENTER
	return p.Y > Cfg.ICE_MIN_Y
		and math.abs(p.X - c.X) <= Cfg.LAKE_HALF_X
		and math.abs(p.Z - c.Z) <= Cfg.LAKE_HALF_Z
end

-- Range to a hole is measured FLAT. The pool part's origin is the middle of a column
-- that runs well under the waterline, so a 3D distance would read several studs long
-- for someone standing right on the rim.
local function flatDistance(pos, hole)
	local d = hole.Position - pos
	return math.sqrt(d.X * d.X + d.Z * d.Z)
end

local function nearestHole(pos)
	local best, bestD = nil, math.huge
	for _, h in ipairs(holes) do
		if h.Parent then
			local d = flatDistance(pos, h)
			if d < bestD then best, bestD = h, d end
		end
	end
	return best, bestD
end

local function teleportHome(player)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local target
	local plot = PlayerDataManager.GetPlot(player, "Tundra")
	if plot then
		local ok, pivot = pcall(function() return plot:GetPivot() end)
		if ok then target = pivot.Position + Vector3.new(0, 6, 0) end
	end
	char:PivotTo(CFrame.new(target or TUNDRA_ARRIVAL))
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
end

-- ===== barrier ===============================================================
local function barrierWalls()
	local sa = skipArea()
	local folder = sa and sa:FindFirstChild(Cfg.BARRIER_FOLDER)
	return folder and folder:GetChildren() or {}
end

local function setBarrier(open)
	if open then
		savedWall = {}
		for _, w in ipairs(barrierWalls()) do
			if w:IsA("BasePart") then
				savedWall[w] = w.CanCollide
				w.CanCollide = false        -- drop the wall so players can step onto the ice
			end
		end
	else
		for w, was in pairs(savedWall) do
			if w and w.Parent then w.CanCollide = was end
		end
		savedWall = {}
	end
end

-- ===== the rig ===============================================================
-- Everything below is anchored scenery: CanCollide is off except for the sheet itself
-- and the low ridges/floes you step over, and CanQuery is off on all of it except the
-- pools, which are what the walk-up prompt measures range to.
local function block(folder, name, size, cf, colour, material, transparency, collide)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = collide or false
	p.CanQuery = false
	p.CanTouch = false
	p.Color = colour
	p.Material = material
	p.Transparency = transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = folder
	return p
end

-- An ELLIPTICAL disc: a block wearing a CylinderMesh, so X and Z stay independent
-- diameters. Plain rectangles read as rectangles on open ice; these read as weather.
local function disc(folder, name, sx, sy, sz, cf, colour, material, transparency)
	local p = block(folder, name, Vector3.new(sx, sy, sz), cf, colour, material, transparency)
	Instance.new("CylinderMesh").Parent = p
	return p
end

local function holePositions()
	local out = {}
	local c = Cfg.LAKE_CENTER
	for _, h in ipairs(Cfg.HOLES) do
		table.insert(out, Vector2.new(c.X + h.dx, c.Z + h.dz))
	end
	return out
end

local function clearOfHoles(x, z, pad)
	local c = Cfg.LAKE_CENTER
	for _, h in ipairs(Cfg.HOLES) do
		local dx, dz = x - (c.X + h.dx), z - (c.Z + h.dz)
		if dx * dx + dz * dz < (Cfg.HOLE_RADIUS + pad) ^ 2 then return false end
	end
	-- and out of the lane you walk in on, or the first thing off the dock is a snowdrift
	if z < -7745 and math.abs(x - c.X) < 46 then return false end
	return true
end

local function bandAt(z)
	for _, b in ipairs(Cfg.LAKE_PROFILE) do
		if z >= b.z0 and z <= b.z1 then return b end
	end
	return nil
end

-- Bands are wildly uneven -- one covers 312 studs of open middle, several cover 8 at the
-- pinched ends -- so a uniform pick would pile the whole dressing into the slivers.
-- Weight by area and the drifts land where there is actually ice.
local bandWeights, bandTotal
local function buildBandWeights()
	bandWeights, bandTotal = {}, 0
	for i, b in ipairs(Cfg.LAKE_PROFILE) do
		bandTotal += (b.z1 - b.z0) * (b.x1 - b.x0)
		bandWeights[i] = bandTotal
	end
end

-- FOOTPRINT-AWARE PLACEMENT. Checking only an object's CENTRE against the holes is not
-- enough and it bit hard: a 92-stud drift centred 20 studs from a hole still covers it,
-- and the first tonal fields (up to 200 studs wide and near-opaque) blanked several holes
-- outright -- you walked up to a pale disc with no water in it at all, from every angle.
-- Anything wide enough to span a hole goes through here instead.
local function randomOnIce(rng, margin)
	if not bandWeights then buildBandWeights() end
	local roll = rng:NextNumber(0, bandTotal)
	local band = Cfg.LAKE_PROFILE[#Cfg.LAKE_PROFILE]
	for i, upto in ipairs(bandWeights) do
		if roll <= upto then band = Cfg.LAKE_PROFILE[i]; break end
	end
	local x0, x1 = band.x0 + margin, band.x1 - margin
	if x1 <= x0 then return nil, nil end
	return rng:NextNumber(x0, x1), rng:NextNumber(band.z0, band.z1)
end

-- A spot where something `halfSpan` studs across will not lie over a hole. Retries rather
-- than giving up on the first clash, so raising a piece's size costs a few attempts
-- instead of quietly thinning the whole layer out.
local function spotFor(rng, halfSpan, margin)
	for _ = 1, 12 do
		local x, z = randomOnIce(rng, margin or 16)
		if x and clearOfHoles(x, z, halfSpan + 3) then return x, z end
	end
	return nil, nil
end

-- One fishing hole. The sheet is genuinely SUBTRACTED here (see buildSheet), so this
-- only dresses the opening -- the hole itself is a real gap you look down through.
--
-- The pool is a COLUMN, not a thin disc lying in the bore. Terrain water renders over
-- any part whose top sits near its own plane, so a disc floating in the bore gets eaten
-- at grazing angles and the hole half-fills with bright lake blue. A column topped at
-- POOL_Y (1.7 above the water plane) renders clean from standing height. Three nested
-- columns give the bottom a fall-off instead of one flat colour.
local function buildHole(folder, cx, cz, rng)
	local R = Cfg.HOLE_RADIUS
	local TOP = Cfg.ICE_TOP
	local POOL = Cfg.POOL_Y
	local H = POOL - Cfg.ICE_BOTTOM + 0.4        -- reaches well under the waterline

	-- ===== THE WATER ============================================================
	-- INNER DISCS SIT HIGHEST -- each one 0.02 proud of the ring outside it, so all five
	-- read. Get that order backwards and the widest disc caps every darker one beneath it,
	-- and the whole pool renders as that single ring: in a mottled material it comes out
	-- indistinguishable from the terrain water this is supposed to be a hole IN.
	--
	-- FIVE DARK STEPS, NOT THREE NEARLY-IDENTICAL ONES. The old ramp ran 12,30,44 ->
	-- 6,17,27 -> 2,8,14 -- all within 20 of each other, and the world's haze (see the
	-- POOL_* note in the config) closed what little gap was left, so the hole read as one
	-- flat black sticker. The fix is contrast INSIDE the darks, not brightness: lifting the
	-- shelf to a wet teal with real Reflectance was tried and read as a glowing blue
	-- portal, which is the sci-fi failure this world's art direction rules out. Reflectance
	-- stays near zero so the sky never gets into the water.
	--
	-- NO BORE LINING. Twenty tangential tabs at R-0.2 used to line the cut, and straight
	-- chords on a circle alternate in and out of the CSG edge -- every one of them showed
	-- as a tooth and the rim read as a cog. The subtracted face is real ice, lit correctly
	-- by the sheet's own material, and needs no help at all.
	local function pdisc(name, dia, topY, colour, refl)
		local p = disc(folder, name, dia, H, dia, CFrame.new(cx, topY - H / 2, cz),
			colour, Enum.Material.SmoothPlastic, 0)
		p.Reflectance = refl
		return p
	end
	pdisc("BoreWet", R * 2.02, POOL + 0.00, Cfg.WET_COLOR, 0.04)
	local pool = pdisc("FishingHole", R * 1.80, POOL + 0.02, Cfg.POOL_COLOR, 0.03)
	pdisc("PoolMid",  R * 1.46, POOL + 0.04, Cfg.POOL_MID,  0.03)
	pdisc("PoolDeep", R * 1.02, POOL + 0.06, Cfg.POOL_DEEP, 0.02)
	pdisc("PoolCore", R * 0.52, POOL + 0.08, Cfg.POOL_CORE, 0.02)
	pool.CanQuery = true

	-- Open water steaming in a blizzard. It is also what makes a hole findable from
	-- across the ice, which matters now the prompt only offers when you are close.
	local em = Instance.new("ParticleEmitter")
	em.Name = "HoleVapour"
	em.Texture = "rbxasset://textures/particles/smoke_main.dds"
	em.Color = ColorSequence.new(Color3.fromRGB(232, 244, 253))
	em.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.28, 0.78),
		NumberSequenceKeypoint.new(1, 1),
	})
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 14) })
	-- Thin. A denser plume sat as a white column straight over the water and greyed out the
	-- one thing on the whole lake that is meant to be dark.
	em.Rate = 4
	em.Lifetime = NumberRange.new(3.4, 5.6)
	em.Speed = NumberRange.new(1.4, 3.0)
	em.SpreadAngle = Vector2.new(16, 16)
	em.Rotation = NumberRange.new(0, 360)
	em.RotSpeed = NumberRange.new(-9, 9)
	em.LightEmission = 0
	em.LightInfluence = 1
	em.Parent = pool

	-- SLUSH AT THE RIM, not floating out in the middle. Six discs at 0.55-0.80R sat in open
	-- water and read as a ring of polka dots laid on the one dark shape on the whole lake.
	-- These hug the edge, which is where broken ice actually collects.
	for k = 1, 5 do
		local a = rng:NextNumber(0, math.pi * 2)
		local rr = R * rng:NextNumber(0.86, 0.98)
		disc(folder, "Slush", rng:NextNumber(1.1, 2.2), 0.20, rng:NextNumber(0.9, 1.7),
			CFrame.new(cx + math.cos(a) * rr, POOL + 0.14, cz + math.sin(a) * rr)
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Color3.fromRGB(222, 238, 249), Enum.Material.Snow, 0)
	end

	-- ===== THE RIM ==============================================================
	-- SHAVINGS, NOT BOULDERS. The first version scattered 22 randomly-yawed cubes 0.7-1.9
	-- studs tall at R+1..R+3 and called it a berm. From a standing eye height that ring was
	-- a WALL: it hid the water completely, so what you walked up to was a crown of white
	-- blocks with no hole visible in it at all. That is the "choppy" -- big cubes, random
	-- angles, too tall, too close.
	--
	-- These lie FLAT, run TANGENTIALLY round the circle, and sit further out. The height
	-- rides a slow wave around the ring with a little jitter on top, so the pile is uneven
	-- in a way that reads as one heap of chippings rather than as noise. Nothing in the
	-- main ring is over ~0.7 studs, which is well under eye line from any standing spot.
	-- The yaw jitter is wide (+/- 32 degrees) and the radius spread is loose ON PURPOSE.
	-- At +/- 12 degrees and an even radius the plates lined up into a starburst and the
	-- rim read as a cog rather than as spoil thrown out of a hole.
	local RIM = 24
	for k = 1, RIM do
		local a = (k / RIM) * math.pi * 2 + rng:NextNumber(-0.10, 0.10)
		local rr = R + 1.5 + rng:NextNumber(0, 3.4)
		local hgt = 0.18 + 0.16 * (math.sin(a * 2.3) * 0.5 + 0.5) + rng:NextNumber(0, 0.14)
		block(folder, "IceChunk",
			Vector3.new(rng:NextNumber(2.2, 5.0), hgt, rng:NextNumber(1.3, 3.0)),
			CFrame.new(cx + math.cos(a) * rr, TOP + hgt * 0.42, cz + math.sin(a) * rr)
				* CFrame.Angles(math.rad(rng:NextNumber(-8, 8)),
					-a + math.pi / 2 + rng:NextNumber(-0.55, 0.55),
					math.rad(rng:NextNumber(-11, 11))),
			Cfg.CHUNK_COLOR, Enum.Material.Glacier)
	end
	-- four bigger slabs tipped up against the pile, purely for silhouette. Four, not
	-- twenty-four: one or two catching the light is interesting, a whole ring of them is
	-- the wall again.
	for k = 1, 4 do
		local a = rng:NextNumber(0, math.pi * 2)
		local rr = R + rng:NextNumber(2.4, 3.8)
		local hgt = rng:NextNumber(0.6, 0.95)
		block(folder, "IceSlab",
			Vector3.new(rng:NextNumber(3.0, 4.6), hgt, rng:NextNumber(1.6, 2.6)),
			CFrame.new(cx + math.cos(a) * rr, TOP + hgt * 0.45, cz + math.sin(a) * rr)
				* CFrame.Angles(math.rad(rng:NextNumber(16, 30)), -a + math.pi / 2, 0),
			Cfg.CHUNK_COLOR, Enum.Material.Glacier)
	end
	-- ===== THE COLLAR ============================================================
	-- ELLIPSES STILL, BUT MANY AND SMALL. This was nine discs of 9-16 x 6-11 studs at
	-- R+4.5..R+8.5, and nine saucers that size all sitting at one height overlap into a
	-- white flower -- from above that flower WAS the hole's silhouette, and from eye level
	-- the outer ones read as flat white ovals lying on the ice. Swapping them for
	-- rectangles only trades the flower for a ring of tiles; what actually works is pieces
	-- too small to be read as individual shapes, laid tangentially and overlapped into one
	-- continuous bank.
	--
	-- The bank FEATHERS ITSELF instead of getting a second scattered pass outside it --
	-- that outer pass is exactly how the saucers come back. Radius, width and height all
	-- ride `amt`, so the downwind side is deep and wide and the upwind side thins to almost
	-- nothing: one drift shaped by the lake's shared WIND_ANGLE, not a ring of props.
	local COLLAR = 44
	for k = 1, COLLAR do
		local a = (k / COLLAR) * math.pi * 2 + rng:NextNumber(-0.05, 0.05)
		local lee = math.cos(a - Cfg.WIND_ANGLE) * 0.5 + 0.5        -- 1 downwind, 0 upwind
		local amt = 0.22 + 0.78 * lee
		local rr  = R + 2.9 + amt * 3.4 + rng:NextNumber(0, 1.2)
		local hgt = (0.08 + 0.22 * amt) * rng:NextNumber(0.85, 1.15)
		local tone = (k % 3 == 0) and Cfg.SNOW_COOL
			or ((k % 7 == 0) and Cfg.SNOW_SHADE or Cfg.SNOW_COLOR)
		disc(folder, "HoleSnow", rng:NextNumber(5.0, 8.0), hgt,
			(3.0 + 4.8 * amt) * rng:NextNumber(0.9, 1.1),
			CFrame.new(cx + math.cos(a) * rr, TOP + hgt * 0.30, cz + math.sin(a) * rr)
				* CFrame.Angles(0, -a + math.pi / 2 + rng:NextNumber(-0.16, 0.16), 0),
			tone, Enum.Material.Snow, 0)
	end
	for k = 1, 5 do
		local a = rng:NextNumber(0, math.pi * 2)
		local len = rng:NextNumber(14, 34)
		local mid = R + 3 + len / 2
		block(folder, "Crack", Vector3.new(rng:NextNumber(0.5, 1.1), 0.10, len),
			CFrame.new(cx + math.cos(a) * mid, TOP + 0.04, cz + math.sin(a) * mid)
				* CFrame.Angles(0, -a + math.pi / 2, 0),
			Cfg.CRACK_COLOR, Enum.Material.Ice, 0.35)
	end

	-- ===== THE CAMP =============================================================
	-- A hole with gear beside it reads as somebody's fishing spot; a bare cut in the ice
	-- reads as damage. It is also what makes a hole findable from a distance -- the lantern
	-- is the only warm colour anywhere on the lake. All of it sits UPWIND on one side, so
	-- the approach from the dock stays clear and you never walk into a crate.
	local camp = Cfg.WIND_ANGLE + math.pi
	local function at(bearing, dist)
		return cx + math.cos(bearing) * dist, cz + math.sin(bearing) * dist
	end

	local px, pz = at(camp, R + 4.5)
	block(folder, "LanternPost", Vector3.new(0.34, 7.0, 0.34), CFrame.new(px, TOP + 3.5, pz),
		Cfg.WOOD_DARK, Enum.Material.Wood)
	block(folder, "LanternArm", Vector3.new(1.5, 0.24, 0.24),
		CFrame.new(px + 0.6, TOP + 6.7, pz), Cfg.WOOD_DARK, Enum.Material.Wood)
	local lamp = block(folder, "Lantern", Vector3.new(0.7, 0.95, 0.7),
		CFrame.new(px + 1.25, TOP + 6.2, pz), Cfg.LANTERN_COLOR, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = Cfg.LANTERN_COLOR
	light.Brightness = 1.1        -- a lamp, not a floodlight: the ice is already bright
	light.Range = 15
	light.Shadows = false
	light.Parent = lamp

	px, pz = at(camp + 0.55, R + 5.5)
	block(folder, "Crate", Vector3.new(2.6, 1.9, 2.2),
		CFrame.new(px, TOP + 0.95, pz) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
		Cfg.WOOD_COLOR, Enum.Material.WoodPlanks, 0, true)
	px, pz = at(camp - 0.5, R + 4.8)
	-- galvanised, not the reel's near-black: at 70,74,82 this read as a hole in the ice
	local bucket = block(folder, "Bucket", Vector3.new(1.5, 1.3, 1.5),
		CFrame.new(px, TOP + 0.65, pz), Cfg.ROD_METAL_COLOR, Enum.Material.Metal)
	Instance.new("CylinderMesh").Parent = bucket

	-- BUBBLES frozen INTO THE SURFACE near the rim: the detail that says this is a sheet
	-- with a lake under it rather than a white floor with a hole cut in it.
	--
	-- On the surface, not down the ice. The obvious version of this is a column of bubbles
	-- rising through the ice -- but the sheet is opaque (Transparency 0, and it has to be:
	-- a see-through sheet over bright terrain water washes the whole lake out), so anything
	-- placed inside it is simply invisible. These sit a few millimetres proud instead and
	-- read as bubbles caught at the surface, which is a real thing lake ice does.
	-- Four clusters of three, not six of four: at 24 a hole this was 240 parts across the
	-- lake, a fifth of the whole rig, for a detail you only ever read from about ten studs.
	for _ = 1, 4 do
		local a = rng:NextNumber(0, math.pi * 2)
		local rr = R + rng:NextNumber(2.5, 9.0)
		local bx, bz = cx + math.cos(a) * rr, cz + math.sin(a) * rr
		for k = 1, 3 do
			local s = rng:NextNumber(0.45, 0.95) * (1 - k * 0.14)
			local b = block(folder, "Bubble", Vector3.new(s, s * 0.55, s),
				CFrame.new(bx + rng:NextNumber(-1.4, 1.4), TOP + 0.04, bz + rng:NextNumber(-1.4, 1.4)),
				Color3.fromRGB(236, 248, 255), Enum.Material.Glass, 0.45)
			b.Reflectance = 0.12
			-- SpecialMesh, not Shape = Ball: a Ball part renders at its SMALLEST dimension,
			-- so the squash that makes these read as domes in the surface would be thrown away
			local bm = Instance.new("SpecialMesh")
			bm.MeshType = Enum.MeshType.Sphere
			bm.Parent = b
		end
	end

	-- ===== THE INVISIBLE RING ===================================================
	-- YOU WALK AROUND A HOLE, NOT OVER IT (owner's call, 2026-08-23). The obvious way to do
	-- that is to cut the sheet's collision as well as its render, and that does not work --
	-- PreciseConvexDecomposition makes SubtractAsync fail on every strip that contains a
	-- hole, so the holes stop existing altogether (see the note in buildSheet). The sheet
	-- therefore stays solid underneath, and this ring is what actually stops you.
	--
	-- TANGENTIAL SEGMENTS, NOT A CYLINDER. One invisible cylinder over the hole would give
	-- you a lid to stand on at its top face, which is the same bug wearing a hat. These are
	-- thin walls standing on the rim, so there is nothing above the opening at all.
	--
	-- 4 studs tall: enough to stop you walking in, low enough that a deliberate jump still
	-- clears it -- and the sheet under the hole is solid, so a player who insists on jumping
	-- in just stands there rather than falling into the lake.
	local WALLS = 22
	local wallChord = (R * 2 * math.pi / WALLS) * 1.35
	for k = 1, WALLS do
		local a = (k / WALLS) * math.pi * 2
		local w = block(folder, "HoleBarrier", Vector3.new(0.6, 4, wallChord),
			CFrame.new(cx + math.cos(a) * (R + 0.3), TOP + 2, cz + math.sin(a) * (R + 0.3))
				* CFrame.Angles(0, -a + math.pi / 2, 0),
			Cfg.ICE_COLOR, Enum.Material.SmoothPlastic, 1, true)
		w.CastShadow = false
	end

	return pool
end

-- The sheet: one strip per LAKE_PROFILE band, cut to that band's water width, and the
-- holes genuinely subtracted out of the strips they fall in. CSG per strip rather than
-- one 388 x 948 union keeps every operation small, and the stepped edge that results is
-- the lake's own outline -- the shore rubble is laid along it to hide the steps.
local function buildSheet(folder, rng)
	local TOP, BOT = Cfg.ICE_TOP, Cfg.ICE_BOTTOM
	local THICK = TOP - BOT
	local OVER = Cfg.SHORE_OVERRUN
	local R = Cfg.HOLE_RADIUS
	local centres = holePositions()
	local last = #Cfg.LAKE_PROFILE

	for i, band in ipairs(Cfg.LAKE_PROFILE) do
		local x0, x1 = band.x0 - OVER, band.x1 + OVER
		-- Grow SIDEWAYS only. Bands abut exactly in z; overlapping them would put two
		-- coplanar top faces in the same place and they would z-fight the whole lake.
		local z0 = band.z0 - (i == 1 and OVER or 0)
		local z1 = band.z1 + (i == last and OVER or 0)

		local slab = Instance.new("Part")
		slab.Name = "IceSheet"
		slab.Anchored = true
		slab.Size = Vector3.new(x1 - x0, THICK, z1 - z0)
		slab.CFrame = CFrame.new((x0 + x1) / 2, TOP - THICK / 2, (z0 + z1) / 2)
		slab.Parent = folder

		local negs = {}
		for _, c in ipairs(centres) do
			if c.Y + R > z0 and c.Y - R < z1 then      -- Vector2: .Y carries the world z
				local n = Instance.new("Part")
				n.Shape = Enum.PartType.Cylinder
				n.Size = Vector3.new(THICK * 3, R * 2, R * 2)
				n.CFrame = CFrame.new(c.X, TOP - THICK / 2, c.Y) * CFrame.Angles(0, 0, math.rad(90))
				n.Anchored = true
				n.Parent = folder
				table.insert(negs, n)
			end
		end

		local piece = slab
		if #negs > 0 then
			-- BOX FIDELITY, and it has to be. The obvious way to stop players walking over an
			-- opening is to cut the collision too -- but PreciseConvexDecomposition makes
			-- SubtractAsync FAIL outright on exactly the strips that contain holes (measured
			-- 2026-08-23: strips 4, 5, 8, 9, 12, 13 and 18 all came back nil and stayed solid,
			-- so the holes disappeared entirely). Box keeps the cut RENDERING while the
			-- collision volume stays the whole strip, which also means nobody can drop through
			-- into the water under an opaque sheet. Walking onto the opening is prevented by
			-- the invisible ring buildHole puts around each hole instead.
			local ok, cut = pcall(function()
				return slab:SubtractAsync(negs, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Precise)
			end)
			if ok and cut then
				piece = cut
				piece.Name = "IceSheet"
				piece.Anchored = true
				piece.UsePartColor = true
				slab:Destroy()
			else
				warn("[IceFishing] SubtractAsync failed on strip " .. i .. "; that strip stays solid")
			end
			for _, n in ipairs(negs) do n:Destroy() end
		end

		piece.CanCollide = true
		piece.CanQuery = true
		piece.CanTouch = false
		-- A HAIR OF TONE PER STRIP. Twenty-two identical slabs laid edge to edge is what
		-- makes the lake read as one flat plane before a single drift lands on it, and no
		-- amount of scattered detail fixes a uniform base. Tiny -- +/- 4 of 255 -- and
		-- weighted toward blue, so it reads as the ice varying rather than as banding.
		local j = rng:NextNumber(-0.016, 0.016)
		piece.Color = Color3.new(
			math.clamp(Cfg.ICE_COLOR.R + j, 0, 1),
			math.clamp(Cfg.ICE_COLOR.G + j * 0.75, 0, 1),
			math.clamp(Cfg.ICE_COLOR.B + j * 0.45, 0, 1))
		piece.Material = Enum.Material.Glacier
		piece.Transparency = 0
		piece.Reflectance = 0.05
		piece.TopSurface = Enum.SurfaceType.Smooth
		piece.BottomSurface = Enum.SurfaceType.Smooth
		piece.Parent = folder
	end
end

-- Drifts, wind-scoured panels, cracks, pressure ridges, frozen-in floes and the rubble
-- along the bank. Without this the lake is one flat white plane out to the horizon.
local function dressSheet(folder, rng)
	local TOP = Cfg.ICE_TOP
	local windX, windZ = math.sin(Cfg.WIND_ANGLE), math.cos(Cfg.WIND_ANGLE)

	-- ===== 1. THE VALUE STRUCTURE, FIRST =======================================
	-- Everything else lands on top of this. Broad, almost flat fields of slightly
	-- different snow tone, 70-200 studs across, so the lake has large-scale light and dark
	-- before any object is placed. This is the single biggest thing separating "a white
	-- plane with props on it" from a snowfield -- detail scattered on a uniform base just
	-- reads as noise on a uniform base.
	local TONES = { Cfg.SNOW_COOL, Cfg.SNOW_SHADE, Cfg.SNOW_COLOR, Cfg.SNOW_DEEP }
	for i = 1, Cfg.FIELDS do
		-- MANY MEDIUM FIELDS, NOT A FEW ENORMOUS ONES. These were 70-200 studs wide, which
		-- both blanked holes and left nowhere clear to put them once that was enforced.
		-- Overlapping medium patches read as the same broad structure and place easily.
		local w, d = rng:NextNumber(40, 95), rng:NextNumber(34, 78)
		local x, z = spotFor(rng, math.max(w, d) * 0.5, 24)
		if x then
			-- near-opaque on purpose: at 0.15-0.45 these washed out to nothing against the
			-- sheet and the lake stayed flat. A value structure you cannot see is not one.
			disc(folder, "Field", w, 0.10, d,
				CFrame.new(x, TOP + 0.02, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				TONES[(i % #TONES) + 1], Enum.Material.Snow, rng:NextNumber(0.05, 0.25))
		end
	end

	-- ===== 2. TOPOGRAPHY =======================================================
	-- HUMMOCKS: broad snow-covered swells. Built as three stacked contour discs rather
	-- than one dome, because a SpecialMesh sphere keeps its part's BOX collision -- a dome
	-- would be an invisible wall at its bounding box. Left non-colliding anyway at this
	-- height: walking over a 1.5-stud swell you cannot feel is better than clipping the
	-- corners of three stacked boxes.
	for _ = 1, Cfg.HUMMOCKS do
		local x, z = randomOnIce(rng, 36)
		if x and clearOfHoles(x, z, 26) then
			local w0, d0 = rng:NextNumber(26, 52), rng:NextNumber(20, 40)
			local yaw = rng:NextNumber(0, math.pi * 2)
			local step = rng:NextNumber(0.40, 0.62)
			for k = 0, 2 do
				local f = 1 - k * 0.27
				disc(folder, "Hummock", w0 * f, step * 1.35, d0 * f,
					CFrame.new(x, TOP + step * k + step * 0.18, z) * CFrame.Angles(0, yaw, 0),
					(k == 2) and Cfg.SNOW_COLOR or Cfg.SNOW_COOL, Enum.Material.Snow, 0)
			end
		end
	end

	-- ===== 3. SURFACE ==========================================================
	-- wind-scoured bare ice. Kept PALE and well short of saturated: at full Ice-material
	-- blue these panels read as open water and the lake looks half-thawed.
	for _ = 1, Cfg.PANELS do
		local w, d = rng:NextNumber(46, 120), rng:NextNumber(34, 90)
		local x, z = spotFor(rng, math.max(w, d) * 0.5, 30)
		if x then
			local p = disc(folder, "BareIce", w, 0.14, d,
				CFrame.new(x, TOP + 0.05, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				Cfg.BARE_COLOR, Enum.Material.Ice, 0.22)
			p.Reflectance = 0.06
		end
	end
	-- DRIFTS, each with the shadow it casts downwind. Under Roblox's flat outdoor light a
	-- white drift on white snow has almost no edge -- the painted shade is what gives it a
	-- form to read, and it costs one flat disc.
	for _ = 1, Cfg.DRIFTS do
		local hgt = rng:NextNumber(0.35, 1.2)
		local w, d = rng:NextNumber(28, 92), rng:NextNumber(22, 66)
		local x, z = spotFor(rng, math.max(w, d) * 0.5, 16)
		if x then
			local yaw = Cfg.WIND_ANGLE + rng:NextNumber(-0.5, 0.5)
			disc(folder, "DriftShade", w * 1.06, 0.08, d * 1.06,
				CFrame.new(x + windX * d * 0.22, TOP + 0.035, z + windZ * d * 0.22)
					* CFrame.Angles(0, yaw, 0),
				Cfg.SNOW_DEEP, Enum.Material.Snow, 0.28)
			disc(folder, "Drift", w, hgt, d,
				CFrame.new(x, TOP + hgt / 2 - 0.16, z) * CFrame.Angles(0, yaw, 0),
				Cfg.SNOW_COLOR, Enum.Material.Snow, 0)
		end
	end
	for _ = 1, Cfg.CRACKS do
		local len = rng:NextNumber(60, 190)
		local x, z = spotFor(rng, len * 0.5, 20)
		if x then
			block(folder, "Crack", Vector3.new(rng:NextNumber(0.6, 1.5), 0.10, len),
				CFrame.new(x, TOP + 0.04, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				Cfg.CRACK_COLOR, Enum.Material.Ice, 0.35)
		end
	end
	-- pressure ridges: plates shoved up where two floes met. Capped at 1.6 and tilted, so
	-- they break the horizon and still walk like a ramp rather than a wall.
	local c = Cfg.LAKE_CENTER
	for _, ridge in ipairs({
		{ z = c.Z - 250, yaw = 0.12 },
		{ z = c.Z + 90,  yaw = -0.20, hero = true },
		{ z = c.Z + 300, yaw = 0.06 },
	}) do
		local n = ridge.hero and 22 or 15
		for k = 1, n do
			local t = (k - 0.5) / n
			-- THE HERO RIDGE gets a gap in the middle. It is the one thing on the lake with
			-- real height, which is exactly why it must not be a fence across it: the point
			-- is a silhouette to walk toward, not an obstacle to walk around.
			if not (ridge.hero and t > 0.44 and t < 0.58) then
				local x = c.X - 170 + t * 340
				local z = ridge.z + math.sin(t * 6.2) * 26 + (x - c.X) * ridge.yaw
				-- the ridge line is drawn straight, so clamp it back inside the band it
				-- actually lands in or its ends hang off the ice where the lake narrows
				local b = bandAt(z)
				if b then x = math.clamp(x, b.x0 + 14, b.x1 - 14) end
				if b and clearOfHoles(x, z, 18) then
					local hgt = ridge.hero and rng:NextNumber(2.1, 3.4) or rng:NextNumber(0.9, 1.6)
					block(folder, "Ridge",
						Vector3.new(rng:NextNumber(14, ridge.hero and 30 or 26), hgt, rng:NextNumber(4, ridge.hero and 12 or 9)),
						CFrame.new(x, TOP + hgt * 0.34, z)
							* CFrame.Angles(math.rad(rng:NextNumber(-30, 30)), rng:NextNumber(-0.5, 0.5),
								math.rad(rng:NextNumber(-20, 20))),
						Cfg.CHUNK_COLOR, Enum.Material.Glacier, 0, true)
					-- snow packed into the lee of the pile, so it sits IN the surface rather
					-- than on top of it like dropped luggage
					disc(folder, "RidgeSnow", rng:NextNumber(16, 30), 0.34, rng:NextNumber(10, 18),
						CFrame.new(x + windX * 6, TOP + 0.08, z + windZ * 6)
							* CFrame.Angles(0, Cfg.WIND_ANGLE, 0),
						Cfg.SNOW_COLOR, Enum.Material.Snow, 0)
				end
			end
		end
	end
	for _ = 1, Cfg.FLOES do
		local x, z = randomOnIce(rng, 26)
		if x and clearOfHoles(x, z, 22) then
			local hgt = rng:NextNumber(1.0, 1.5)
			block(folder, "Floe", Vector3.new(rng:NextNumber(9, 20), hgt, rng:NextNumber(8, 17)),
				CFrame.new(x, TOP + hgt * 0.36, z)
					* CFrame.Angles(math.rad(rng:NextNumber(-9, 9)), rng:NextNumber(0, math.pi * 2),
						math.rad(rng:NextNumber(-9, 9))),
				Cfg.CHUNK_COLOR, Enum.Material.Glacier, 0, true)
		end
	end
	-- SASTRUGI: the wind-carved ripples that give open snow its grain. All aligned to the
	-- one WIND_ANGLE, in short broken runs rather than scattered, because what reads as
	-- wind is the PARALLELISM -- random yaw on the same parts just looks like litter.
	for _ = 1, math.floor(Cfg.SASTRUGI / 6) do
		local x, z = randomOnIce(rng, 22)
		if x then
			local yaw = Cfg.WIND_ANGLE + rng:NextNumber(-0.10, 0.10)
			local dx, dz = math.sin(yaw), math.cos(yaw)
			for k = 0, 5 do
				-- step ALONG the ridge line, and offset each rib a little across it
				local px = x + dx * k * rng:NextNumber(7, 12) - dz * rng:NextNumber(-3, 3)
				local pz = z + dz * k * rng:NextNumber(7, 12) + dx * rng:NextNumber(-3, 3)
				if clearOfHoles(px, pz, 12) then
					local hgt = rng:NextNumber(0.18, 0.42)
					disc(folder, "Sastruga", rng:NextNumber(9, 19), hgt, rng:NextNumber(2.0, 3.6),
						CFrame.new(px, TOP + hgt * 0.34, pz) * CFrame.Angles(0, yaw + math.pi / 2, 0),
						Cfg.SNOW_COLOR, Enum.Material.Snow, 0)
				end
			end
		end
	end

	-- THE TRAIL. People come off the dock and walk to the two near holes, so the snow
	-- between is packed flat and grey-blue rather than fresh. It is also the cheapest
	-- possible signpost: a player stepping onto the ice can see where to go.
	local c2 = Cfg.LAKE_CENTER
	for i = 1, Cfg.TRAIL do
		local t = (i - 0.5) / Cfg.TRAIL
		-- one stem north off the dock, forking to the -70/+70 pair at dz -420
		local x, z
		if t < 0.45 then
			x, z = c2.X + rng:NextNumber(-3, 3), -7787 + (t / 0.45) * 22
		else
			-- the fork STOPS SHORT of the two near holes rather than running onto them: it
			-- is a path leading you there, and a packed-snow disc laid over the water is
			-- exactly the thing that was hiding the pool
			local side = (i % 2 == 0) and -56 or 56
			local u = (t - 0.45) / 0.55
			x = c2.X + side * u + rng:NextNumber(-3, 3)
			z = -7765 - u * 3 + rng:NextNumber(-3, 3)
		end
		-- NOT clearOfHoles: that ALSO refuses the dock walk-on lane, which is the one place
		-- the trail is supposed to be -- it rejected 22 of 24 discs and left two stray
		-- patches on the ice. Only the holes themselves need avoiding here.
		local clear = true
		for _, h in ipairs(Cfg.HOLES) do
			local dx, dz = x - (c2.X + h.dx), z - (c2.Z + h.dz)
			if dx * dx + dz * dz < (Cfg.HOLE_RADIUS + 9) ^ 2 then clear = false; break end
		end
		if clear then
			disc(folder, "Trail", rng:NextNumber(9, 15), 0.10, rng:NextNumber(7, 12),
				CFrame.new(x, TOP + 0.03, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				Color3.fromRGB(222, 234, 244), Enum.Material.Snow, 0.15)
		end
	end

	-- SPINDRIFT: loose snow streaming across the ice on the same bearing. Anchored to a
	-- handful of invisible posts rather than one emitter, so it blows past you wherever
	-- you are on the lake instead of only near the middle.
	for _ = 1, Cfg.SPINDRIFT do
		local x, z = randomOnIce(rng, 40)
		if x then
			local post = block(folder, "SpindriftPost", Vector3.new(1, 1, 1),
				CFrame.new(x, TOP + 1.2, z), Cfg.SNOW_COLOR, Enum.Material.Snow, 1)
			local em = Instance.new("ParticleEmitter")
			em.Name = "Spindrift"
			em.Texture = "rbxasset://textures/particles/smoke_main.dds"
			em.Color = ColorSequence.new(Color3.fromRGB(240, 249, 255))
			em.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0.72),
				NumberSequenceKeypoint.new(1, 1),
			})
			em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 26) })
			em.Rate = 4
			em.Lifetime = NumberRange.new(2.6, 4.2)
			em.Speed = NumberRange.new(26, 40)
			em.SpreadAngle = Vector2.new(7, 3)
			em.Rotation = NumberRange.new(0, 360)
			em.LightEmission = 0
			em.LightInfluence = 1
			-- EmissionDirection is a face of the part, so the POST is turned to face downwind
			-- rather than the emitter being given a direction it does not have.
			post.CFrame = CFrame.new(post.Position) * CFrame.Angles(0, Cfg.WIND_ANGLE, 0)
			em.EmissionDirection = Enum.NormalId.Front
			em.Parent = post
		end
	end

	-- THE BERM: snow banked against the bank the whole way round. It does two jobs -- it
	-- frames the lake so the eye reads an edge rather than the sheet simply stopping, and
	-- it buries the stepped outline the per-band strips leave behind, which the scattered
	-- rubble below only ever half-hid.
	for i = 1, Cfg.BERM do
		local band = Cfg.LAKE_PROFILE[((i - 1) % #Cfg.LAKE_PROFILE) + 1]
		local onLeft = (i % 2 == 0)
		local inward = onLeft and 1 or -1
		local x = (onLeft and band.x0 or band.x1) + inward * rng:NextNumber(1, 9)
		local z = rng:NextNumber(band.z0, band.z1)
		if clearOfHoles(x, z, 12) then
			local hgt = rng:NextNumber(1.1, 2.5)
			disc(folder, "Berm", rng:NextNumber(18, 36), hgt, rng:NextNumber(10, 22),
				CFrame.new(x, TOP + hgt * 0.30, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				Cfg.SNOW_COLOR, Enum.Material.Snow, 0)
		end
	end

	-- LOW MIST. The far end is 900 studs off and every part out there is the same value as
	-- every part at your feet, so without this the distance simply flattens into white. Big,
	-- slow and very transparent -- it is atmosphere, not weather; the spindrift above is
	-- what does weather.
	for _ = 1, Cfg.MIST do
		local x, z = randomOnIce(rng, 50)
		if x then
			local post = block(folder, "MistPost", Vector3.new(1, 1, 1),
				CFrame.new(x, TOP + 1.0, z) * CFrame.Angles(0, Cfg.WIND_ANGLE, 0),
				Cfg.SNOW_COLOR, Enum.Material.Snow, 1)
			local em = Instance.new("ParticleEmitter")
			em.Name = "GroundMist"
			em.Texture = "rbxasset://textures/particles/smoke_main.dds"
			em.Color = ColorSequence.new(Color3.fromRGB(228, 241, 251))
			em.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, 0.84),
				NumberSequenceKeypoint.new(1, 1),
			})
			em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 44), NumberSequenceKeypoint.new(1, 96) })
			em.Rate = 1.3
			em.Lifetime = NumberRange.new(9, 15)
			em.Speed = NumberRange.new(2, 5)
			em.SpreadAngle = Vector2.new(4, 4)
			em.Rotation = NumberRange.new(0, 360)
			em.RotSpeed = NumberRange.new(-3, 3)
			em.LightEmission = 0
			em.LightInfluence = 1
			em.EmissionDirection = Enum.NormalId.Front
			em.Parent = post
		end
	end

	-- rubble along the bank, walked off the profile so it follows the stepped edge
	local bands = Cfg.LAKE_PROFILE
	for i = 1, Cfg.RUBBLE do
		local band = bands[((i - 1) % #bands) + 1]
		local onLeft = (i % 2 == 0)
		local x = (onLeft and band.x0 or band.x1) + rng:NextNumber(-3, 3)
		local z = rng:NextNumber(band.z0, band.z1)
		if clearOfHoles(x, z, 10) then
			local hgt = rng:NextNumber(0.8, 2.0)
			block(folder, "ShoreRubble", Vector3.new(rng:NextNumber(4, 11), hgt, rng:NextNumber(4, 11)),
				CFrame.new(x, TOP + hgt * 0.30, z)
					* CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), rng:NextNumber(0, math.pi * 2),
						math.rad(rng:NextNumber(-25, 25))),
				Cfg.CHUNK_COLOR, Enum.Material.Glacier)
		end
	end
end

local function buildIce()
	local sa = skipArea()
	if not sa then warn("[IceFishing] SkipArea not found; cannot freeze"); return end

	local folder = Instance.new("Folder")
	folder.Name = Cfg.RIG_FOLDER
	folder.Parent = sa            -- CSG refuses to run on operands outside the DataModel

	local rng = Random.new(os.time())
	buildSheet(folder, rng)

	holes = {}
	local c = Cfg.LAKE_CENTER
	for _, h in ipairs(Cfg.HOLES) do
		table.insert(holes, buildHole(folder, c.X + h.dx, c.Z + h.dz, rng))
	end

	dressSheet(folder, rng)
	rigFolder = folder
end

local function removeIce()
	if rigFolder then rigFolder:Destroy(); rigFolder = nil end
	holes = {}
end

-- ===== rod <-> rock satchel =================================================
-- A tundra player carries a rod OR a satchel, never both: the sling is what the rod is
-- replacing. SetHidden also blocks RockSlingService's own 1s refresh poll, which would
-- otherwise rebuild the sling within a second of it being taken off.
local function giveRod(player)
	if not RodService.IsEquipped(player) then RodService.Equip(player) end
	RockSlingService.SetHidden(player, true)
end

local function takeRod(player)
	if RodService.IsEquipped(player) then RodService.Unequip(player) end
	RockSlingService.SetHidden(player, false)
	player:SetAttribute("Fishing", nil)   -- never leave anyone frozen when the lake thaws
end

-- Put the rod back on the back and take the line in. Safe on every exit path -- landed,
-- missed, timed out, walked away, event over -- and a no-op if it is already stowed.
-- PLANTED AT THE HOLE. ClientMain's applySprint reads this attribute inline and zeroes
-- WalkSpeed and AutoRotate while it is set -- it has to happen there rather than here,
-- because that function is the one writer of WalkSpeed and runs on every input, so a
-- speed set from the server would be overwritten within a frame.
--
-- Held until the rod is STOWED rather than cleared the moment the fish resolves, so you
-- stay planted through the reel-in instead of being free to stroll off mid-animation.
local function setFishing(player, on)
	player:SetAttribute("Fishing", on and true or nil)
end

local function stowRod(player)
	if player.Character then RodService.ClearLine(player.Character) end
	RodService.SetStance(player, "Slung")
	setFishing(player, false)
end

-- ===== fishing ===============================================================
-- No hold, no ProximityPrompt: the client shows a FISH HERE button whenever you are
-- standing within HOLE_REACH of a hole (the same walk-up-and-it-appears deal as the
-- dock's throw button) and one press sends this. The server still owns the range check.

-- pick a green BITE window of `width` at a random spot on the bar (kept off the very ends)
local function pickGreen(width)
	local gmin = 0.05 + math.random() * math.max(0, 0.90 - width)
	return gmin, gmin + width
end

-- Open the next reel step: advance the counter, roll a fresh green at the run's CURRENT
-- (shrunk) width, send it, and arm THIS step's timeout. Called once per click -- the first
-- from the cast-lead beat once the float lands, the rest from the reel handler on a good
-- pull. `stepToken` voids the previous step's timer so an advanced run can't time out.
local function sendReelStep(player)
	local st = fishing[player]
	if not st then return end
	st.step += 1
	st.greenMin, st.greenMax = pickGreen(st.width)
	local stepToken = {}
	st.stepToken = stepToken
	stateRemote:FireClient(player, {
		Minigame = true, GreenMin = st.greenMin, GreenMax = st.greenMax,
		MarkerPeriod = Cfg.MARKER_PERIOD, Step = st.step, Steps = st.steps,
		Rarity = st.rarity, RockId = st.rockId,
	})
	task.delay(Cfg.HOOK_TIMEOUT, function()
		local s2 = fishing[player]
		if not s2 or s2.stepToken ~= stepToken then return end
		fishing[player] = nil
		stateRemote:FireClient(player, { GotAway = true })
		stowRod(player)
	end)
end

local function startFishing(player, power)
	if not active then return end
	if not inTundra(player) then return end
	if fishing[player] then return end          -- one cast at a time
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local hole, dist = nearestHole(hrp.Position)
	if not hole or dist > Cfg.HOLE_REACH + 3 then
		stateRemote:FireClient(player, { Cancelled = true })
		return
	end

	-- PERFECT-CAST timing. Consume the single-use band this server issued for this charge and
	-- judge the released `power` against it -- server-owned exactly like the skip-rock band, so
	-- the client can only DRAW the band, never declare its own casts perfect. A perfect fishes
	-- the whole cast at PERFECT_LUCK_MULT luck, lifting bite rarity and the catch together.
	local band = pendingBand[player]
	pendingBand[player] = nil
	local perfect = band ~= nil
		and typeof(power) == "number" and power == power
		and (os.clock() - band.issuedAt) <= Cfg.PERFECT_BAND_MAX_AGE
		and power >= band.min and power <= band.max

	-- the equipped rock's stats drive the rod
	local data = PlayerDataManager.Get(player)
	local rockId = (data and data.EquippedRock) or "Pebble"
	local rock = WorldProgression.RockById(rockId) or WorldProgression.RockById("Pebble")
	-- The "Fishing Luck" PET ABILITY (2026-08-22): Riverborn, Marshlight, Frostcaller.
	-- It goes on the BITE roll, not on RollCatch, because RollBite is where the
	-- rarity is decided -- RollCatch only picks a name inside a rarity already
	-- rolled, and its own comment says re-reading luck there would double-dip the
	-- same roll. Multiplicative, matching the perfect-cast multiplier beside it.
	local luck = ((rock and rock.Luck) or 1) * (perfect and Cfg.PERFECT_LUCK_MULT or 1)
		* PetHandler.StatMult(player, "FishLuck")
	local reach = (rock and rock.MaxDistance) or Cfg.REACH_MIN

	giveRod(player)
	RodService.SetStance(player, "Ready")     -- the rod comes off the back and into the hand
	setFishing(player, true)                  -- and you are planted until it is stowed

	-- Roll WHAT'S ON THE LINE (stub): a rarity -> a number of reel clicks. Higher rarity
	-- takes more clicks, and the green shrinks each click (see sendReelStep). Store the run;
	-- the reel handler (Init) judges each click and either tightens it or ends it.
	local bite = Cfg.RollBite(luck, reach)
	local token = {}
	fishing[player] = {
		token = token, hole = hole, rockId = rockId, luck = luck, reach = reach,
		rarity = bite.Rarity, steps = bite.Steps, step = 0,
		width = Cfg.GreenWidth(reach), armed = false,
	}

	-- THE CAST IS A BEAT OF ITS OWN. ClientMain drives the wind-back and flick off this,
	-- and everything that follows waits CAST_LEAD for it: the line only appears when the
	-- flick lands, and the first reel step only opens once there is a float in the water.
	-- HolePos rides along so ClientMain can square the character up to the hole on the
	-- first frame of the cast, the way releaseThrow squares you up to the lake.
	stateRemote:FireClient(player, {
		Casting = true, Lead = Cfg.CAST_LEAD, RockId = rockId, HolePos = hole.Position,
		Perfect = perfect,
	})

	task.delay(Cfg.CAST_LEAD, function()
		local st = fishing[player]
		if not st or st.token ~= token then return end
		local ch = player.Character
		if not ch or not hole.Parent then return end
		RodService.CastLine(ch, Vector3.new(hole.Position.X, Cfg.POOL_Y + 0.35, hole.Position.Z))
		st.armed = true                        -- a reel before this point cannot count
		sendReelStep(player)                   -- opens step 1; further steps re-arm from the reel handler
	end)
end

-- BACKING OUT. Being planted at the hole is the point, but a cast with no exit meant
-- waiting out the full HOOK_TIMEOUT before you could move again -- and then the walk-up
-- loop simply re-cast at you. This is the release valve: it abandons the cast, takes the
-- line in and hands movement back immediately.
--
-- Deliberately forgiving about state. If the cast already resolved a moment ago and the
-- client is only now telling us it wants out, there is nothing to cancel -- but the rod
-- may still be in hand on its stow delay, so stow it anyway rather than returning early.
-- Nobody should ever be left standing frozen because two messages crossed.
local function cancelFishing(player)
	local st = fishing[player]
	if st then
		fishing[player] = nil
		stateRemote:FireClient(player, { Cancelled = true })
	end
	stowRod(player)
end

-- ===== who is shown the event ==============================================
-- The banner used to go out with FireAllClients, so VALLEY players saw a blizzard banner
-- for an event happening 8,000 studs away that they cannot take part in. Every "the lake
-- is freezing / is frozen" message is now addressed only to players whose BoundsGuard
-- region is Tundra -- the same inTundra() test that already decides who gets a rod.
local bannerOn = {}   -- [player] = true while that player is currently being shown the event
local function pushEvent(p, on)
	if on and not bannerOn[p] then
		bannerOn[p] = true
		stateRemote:FireClient(p, { Active = true, EndsAt = activeEndsAt })
	elseif not on and bannerOn[p] then
		bannerOn[p] = nil
		stateRemote:FireClient(p, { Active = false })
	end
end
local function tellTundra(payload)
	for _, p in ipairs(Players:GetPlayers()) do
		if inTundra(p) then stateRemote:FireClient(p, payload) end
	end
end

-- ===== rod upkeep while frozen ==============================================
-- Hands a rod to anyone in the tundra and takes it back off anyone who is not (a player
-- can portal in or out mid-event). Runs only while active.
local function rodMaintainer()
	task.spawn(function()
		while active do
			for _, p in ipairs(Players:GetPlayers()) do
				local want = inTundra(p)
				-- portal in mid-event and the banner appears; portal out and it clears
				pushEvent(p, want)
				if want and not RodService.IsEquipped(p) then
					giveRod(p)
				elseif not want and RodService.IsEquipped(p) then
					takeRod(p)
				end
				-- A rod left in the hand with no cast behind it: the player walked off
				-- mid-minigame, or a resolve raced the stow. Without this the rod stays out
				-- until the next cast, which looks like it is stuck.
				if fishing[p] == nil and RodService.IsEquipped(p)
					and p.Character and p.Character:FindFirstChild("CastLine") then
					stowRod(p)
				end
			end
			task.wait(3)
		end
	end)
end

-- ===== freeze / thaw =========================================================
function IceFishingEvent.Freeze(duration)
	if active then return false end
	active = true
	activeEndsAt = os.time() + duration
	-- Shared gate: ThrowHandler (server) and ClientMain (throw UI) both read this attribute
	-- to switch World-2 throwing OFF while the lake is frozen -- you fish instead. It
	-- replicates to every client for free.
	ReplicatedStorage:SetAttribute("IceFishingActive", true)
	setBarrier(true)
	buildIce()
	for _, p in ipairs(Players:GetPlayers()) do
		if inTundra(p) then giveRod(p) end
	end
	rodMaintainer()
	for _, p in ipairs(Players:GetPlayers()) do
		if inTundra(p) then pushEvent(p, true) end
	end
	print(string.format("[IceFishing] lake FROZEN for %ds", duration))
	return true
end

function IceFishingEvent.Thaw()
	if not active then return false end
	active = false
	ReplicatedStorage:SetAttribute("IceFishingActive", false)   -- World-2 throwing back on
	-- deliberately EVERYONE, not just tundra players: someone who portalled out while the
	-- banner was up must still get the clear, and a stray clear is harmless.
	stateRemote:FireAllClients({ Active = false })
	bannerOn = {}

	-- send home anyone who is out on the ice or mid-cast, THEN restore the barrier so
	-- nobody is left standing on water when the sheet vanishes.
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and (fishing[p] or onLake(hrp)) then
			teleportHome(p)
		end
	end
	fishing = {}
	setBarrier(false)
	removeIce()
	-- everyone, not just tundra players: someone who portalled out mid-event still has
	-- a hidden satchel waiting to come back
	for _, p in ipairs(Players:GetPlayers()) do takeRod(p) end
	print("[IceFishing] lake THAWED, world restored")
	return true
end

-- Manual trigger for testing: a short freeze that auto-thaws. No-op if one is running.
function IceFishingEvent.ForceStart(duration)
	duration = duration or 90
	if not IceFishingEvent.Freeze(duration) then return false end
	task.delay(duration, function() IceFishingEvent.Thaw() end)
	return true
end

function IceFishingEvent.IsActive() return active end

-- ===== scheduler (real-clock hourly) ========================================
function IceFishingEvent.Init()
	ReplicatedStorage:SetAttribute("IceFishingActive", false)   -- explicit default before any freeze

	-- DEV TRIGGER. execute_luau (and the command bar) each get their OWN require cache, so
	-- a probe that requires this module gets a different table from the one the live server
	-- holds -- calling ForceStart on that copy builds a second rig and never touches the
	-- running event. An attribute is an Instance, and Instances cross that boundary: set
	-- ReplicatedStorage.IceFishingForce to a number of seconds and the LIVE module starts a
	-- freeze of that length. Cleared as it fires, so it is single-use and cannot re-trigger.
	-- Nothing in normal play ever writes it; the hourly scheduler below is unaffected.
	ReplicatedStorage:GetAttributeChangedSignal("IceFishingForce"):Connect(function()
		local secs = ReplicatedStorage:GetAttribute("IceFishingForce")
		if type(secs) == "number" and secs > 0 then
			ReplicatedStorage:SetAttribute("IceFishingForce", nil)
			IceFishingEvent.ForceStart(math.clamp(secs, 10, Cfg.FREEZE_SECONDS))
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		fishing[p] = nil
		pendingBand[p] = nil
		lastFishFullWarn[p.UserId] = nil
	end)

	-- The sweet-spot handshake (mirrors ThrowHandler.GetSweetSpot): the client asks for a band
	-- when it arms at a hole and draws whatever this returns. Rolled per charge in the mid-high
	-- region of the meter, single-use (consumed by the next cast) and aged, so there is exactly
	-- one live band per player and it can never be replayed across casts.
	sweetRemote.OnServerInvoke = function(player)
		local lo = Cfg.PERFECT_BAND_LO + math.random() * (Cfg.PERFECT_BAND_HI - Cfg.PERFECT_BAND_LO)
		local band = { min = lo, max = math.min(1, lo + Cfg.PERFECT_BAND_WIDTH), issuedAt = os.clock() }
		pendingBand[player] = band
		return { min = band.min, max = band.max }
	end

	castRemote.OnServerEvent:Connect(function(player, power) startFishing(player, power) end)
	cancelRemote.OnServerEvent:Connect(function(player) cancelFishing(player) end)

	-- The player clicked the line to hook the fish. `frac` is where the marker was (0..1);
	-- a hit is inside the green the cast picked. Server-owned so the result can't be faked
	-- past what the green allows (and, for now, it grants nothing anyway).
	reelRemote.OnServerEvent:Connect(function(player, frac)
		local st = fishing[player]
		if not st then return end                       -- nothing in flight / already resolved
		if not st.armed then return end                 -- clicked before the float even landed
		local ch = player.Character
		local h = ch and ch:FindFirstChild("HumanoidRootPart")
		if not active or not h or not st.hole.Parent
			or flatDistance(h.Position, st.hole) > Cfg.HOLE_REACH + 6 then
			fishing[player] = nil
			stateRemote:FireClient(player, { Cancelled = true })
			task.delay(Cfg.STOW_DELAY, function() if fishing[player] == nil then stowRod(player) end end)
			return
		end
		local hit = type(frac) == "number" and frac == frac
			and frac >= st.greenMin and frac <= st.greenMax
		if not hit then
			fishing[player] = nil
			stateRemote:FireClient(player, { GotAway = true })
			task.delay(Cfg.STOW_DELAY, function() if fishing[player] == nil then stowRod(player) end end)
		elseif st.step >= st.steps then
			-- LANDED IT (final pull). the float ducks under first, so the fish takes it a
			-- beat BEFORE the banner says so rather than after
			fishing[player] = nil
			RodService.Tug(ch)
			task.wait(Cfg.SET_TIME)
			if not active then stowRod(player); return end

			-- THE GRANT. RollCatch picks a real fish of st.rarity (RollBite already rolled
			-- the rarity, luck and all); everything from here mirrors ThrowHandler's own
			-- revealCatch grant -- same Mutation/Size axes, same Brainrots insert, same
			-- BrainrotsCaught counter, same RareCatch banner terms -- so a caught fish is a
			-- brainrot exactly like a thrown one, not a second, divergent grant path.
			local caughtFish = Cfg.RollCatch(st.rarity, st.luck, st.reach)
			local catchPayload = nil
			local isNew, anchor = nil, nil   -- reveal copy + where the cut stages (spec S5.5)
			local gotAway = false   -- true only for the "won it, but nowhere to put it" case below
			if caughtFish then
				local liveData = PlayerDataManager.Get(player)
				-- READ-ONLY SESSION GUARD, same rule PetHandler.Sell/SellHandler use: a failed
				-- DataStore load serves a DEFAULT profile and every write is discarded at
				-- logout, so granting into one would hand the player a fish that evaporates on
				-- rejoin. Checked BEFORE any mutation of liveData.Brainrots below -- and before
				-- liveData is missing entirely (player left mid-reel).
				if liveData and not liveData.__noSave then
					-- BAG CAPACITY (fix round 1, 2026-08-21). ThrowHandler.revealCatch checks
					-- BagConfig.HasBrainrotSpace before ITS grant too -- Deep Pockets is a paid
					-- upgrade to BagConfig.BrainrotCap, and a fishing grant that skipped this
					-- would let a caught fish exceed a cap the player paid to raise. Checked
					-- BEFORE TakeUid and the Brainrots insert below, same as the noSave guard.
					if BagConfig.HasBrainrotSpace(liveData, 1) then
						-- mutation + size, the SAME modules and the SAME formula ThrowHandler's
						-- revealCatch uses (see its `mutBoost` / sizeVariant roll) -- no fishing-
						-- specific mutation table.
						local rebirthLuck = RebirthConfig.LuckMult(liveData.Rebirths)
						local weatherMut = ReplicatedStorage:GetAttribute("WeatherMut") or 1
						local mutBoost = 1
							+ (rebirthLuck - 1)
							+ (PetHandler.LuckMult(player) - 1)
							-- the Mutation Luck ability, same term ThrowHandler adds: a fish
							-- is a brainrot, so an equipped Glow Moth has to work here too
							+ (PetHandler.StatMult(player, "MutationLuck") - 1)
							+ math.max(weatherMut - 1, 0)
						local mutation = Mutations.Roll(mutBoost, ReplicatedStorage:GetAttribute("WeatherName"))
						-- Size Luck ability, same product ThrowHandler feeds Sizes.Roll
						local sizeVariant = Sizes.Roll(weatherMut * PetHandler.StatMult(player, "SizeLuck"))

						-- REVEAL BROADCAST (spec S5.5): the same CatchCinematic payload a throw sends
						-- at flight start, fired at hook-set so nearby players see the world FX and
						-- the catcher's client can stage the cut at the hole. No rock, no flight:
						-- TotalTime 0 means the client plays it on receipt. The grant below is
						-- unaffected, and the result remote fires right after it, in order.
						anchor = Vector3.new(st.hole.Position.X, Cfg.POOL_Y, st.hole.Position.Z)
						do
							local cutName = CinematicConfig.CUT_FOR(caughtFish.Rarity, sizeVariant)
							local cinRemote = remotes:FindFirstChild("CatchCinematic")
							if cutName and cinRemote then
								cinRemote:FireAllClients({
									UserId = player.UserId,
									BrainrotName = caughtFish.Name,
									Rarity = caughtFish.Rarity,
									RarityColor = COLOR_BY_RARITY[caughtFish.Rarity],
									Mutation = mutation,
									Size = sizeVariant,
									Cut = cutName,
									Seed = math.random(1, 2 ^ 30),
									EndPos = anchor, SurfaceY = anchor.Y,
									TotalTime = 0, NContacts = 0, SegTime = 0,
								})
							end
						end
						-- "NEW BRAINROT!" is server-authoritative (spec S10): read before the grant
						-- lands and before PushUpdate re-marks discovery from the bag.
						isNew = not (liveData.Discovered ~= nil and liveData.Discovered[caughtFish.Name] == true)

						local caught = {
							Name = caughtFish.Name, PadIndex = nil, Pending = 0,
							Mutation = mutation, Size = sizeVariant,
							Uid = PlayerDataManager.TakeUid(liveData),
						}
						table.insert(liveData.Brainrots, caught)
						-- Leaderboard stat -- same rule as ThrowHandler: a fish is a genuine catch,
						-- so it counts here exactly like a thrown catch does.
						liveData.BrainrotsCaught = (liveData.BrainrotsCaught or 0) + 1
						InventoryHandler.SyncBackpack(player)

						-- server-wide hype banner, same terms as ThrowHandler's
						if caughtFish.Rarity == "Secret" or caughtFish.Rarity == "God"
							or mutation == "Rainbow" or mutation == "Glitched" then
							local rare = remotes:FindFirstChild("RareCatch")
							if rare then
								rare:FireAllClients(player.Name, caughtFish.Rarity, caughtFish.Name,
									COLOR_BY_RARITY[caughtFish.Rarity], mutation)
							end
						end

						-- enough for the client to show a real reveal, ADDED onto the existing
						-- Rarity/RockId fields below rather than replacing them
						catchPayload = {
							Name = caughtFish.Name, Rarity = caughtFish.Rarity,
							CashPerSecond = caughtFish.CashPerSecond,
							Mutation = mutation, Size = sizeVariant,
						}
						PlayerDataManager.PushUpdate(player)
					else
						-- BAG FULL. The minigame is already won -- a silent no-op here would read
						-- as a bug, so the client gets the same GotAway shape the missed-click
						-- branch above uses (functionally true: the fish has nowhere to go, so it
						-- goes back). Rate-limited exactly like ThrowHandler's own full-bag
						-- warning, but through THIS module's own lastFishFullWarn table.
						gotAway = true
						local now = os.clock()
						local seen = lastFishFullWarn[player.UserId]
						if not seen or now - seen >= FISH_FULL_WARN_COOLDOWN then
							lastFishFullWarn[player.UserId] = now
							local r = remotes:FindFirstChild("PurchaseResult")
							if r then
								r:FireClient(player, { Success = false, Message = BagConfig.BrainrotFullMessage(liveData) })
							end
						end
					end
				end
			end
			-- GotAway omitted (nil) rather than sent false, matching how the miss branch above
			-- only ever sends it true.
			stateRemote:FireClient(player, { Catch = catchPayload, GotAway = (gotAway or nil), Rarity = st.rarity, RockId = st.rockId, IsNew = isNew, Anchor = anchor })
			task.delay(Cfg.STOW_DELAY, function() if fishing[player] == nil then stowRod(player) end end)
		else
			-- a good pull, but the fish is not up yet: a quick tug, tighten the green, reel again
			RodService.Tug(ch)
			st.width = math.max(Cfg.GREEN_MIN_FLOOR, st.width * Cfg.GREEN_SHRINK)
			sendReelStep(player)
		end
	end)

	task.spawn(function()
		while true do
			local now = os.time()
			local nextTop = now - (now % Cfg.PERIOD_SECONDS) + Cfg.PERIOD_SECONDS   -- next :00
			local toWarn = (nextTop - Cfg.WARN_SECONDS) - os.time()
			if toWarn > 0 then task.wait(toWarn) end
			tellTundra({ Warning = true, StartsAt = nextTop, Seconds = Cfg.WARN_SECONDS })
			local toFreeze = nextTop - os.time()
			if toFreeze > 0 then task.wait(toFreeze) end
			if IceFishingEvent.Freeze(Cfg.FREEZE_SECONDS) then
				task.wait(Cfg.FREEZE_SECONDS)
				IceFishingEvent.Thaw()
			end
		end
	end)

	print("IceFishingEvent online (World 2 blizzard, hourly on the :00, 20-min freeze)")
end

return IceFishingEvent
