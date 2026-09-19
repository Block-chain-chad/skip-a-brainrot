-- BuildTundraUpgrade -- World 2 work: replot, dock, ice spikes.
--
-- THE DESIGN LANGUAGE IS TAKEN FROM THE MAIN IGLOO (FrozenTundra.Hub), sampled part
-- by part rather than invented:
--   RoofPlate    Snow,    ~(195-206, 201-217, 222-230)  jittered snow plates
--   ReliefField  Slate,   (58, 72, 89)                  dark inlay ground
--   ReliefPaw/Band/Chevron Snow, (206,226,244)/(219,233,248)  carved motifs
--   CausewayRune Ice,     (150, 196, 228)
--   GatePillar   Glacier, (100, 138, 184)   GateGlow Neon (150, 220, 255)
--   Brazier*     Slate,   (98, 101, 105)    BrazierFire Neon (255, 158, 70)
--   Lantern      Neon,    (255, 232, 176)   IceWindow Neon (150, 214, 255) t0.2
--
-- WHAT MUST NOT BE TOUCHED. These plot children are looked up by name from 20+
-- scripts, so the remodel keeps every one of them exactly where it is and only
-- replaces the purely decorative dressing around them:
--   Platform, Pads, PlotBoard, Campfire, CampDressing, CampDirt, CampStand,
--   EquipBestPad, PlatformRim's role (rebuilt in place, same footprint)

local L = require(script.Parent.Lib)
local M = {}

local SNOW   = Enum.Material.Snow
local GLACIER= Enum.Material.Glacier
local SLATE  = Enum.Material.Slate
local ICEM   = Enum.Material.Ice
local NEON   = Enum.Material.Neon

local C = {
	plate   = Color3.fromRGB(201, 209, 226),
	field   = Color3.fromRGB(58, 72, 89),
	motif   = Color3.fromRGB(206, 226, 244),
	motif2  = Color3.fromRGB(219, 233, 248),
	rune    = Color3.fromRGB(150, 196, 228),
	pillar  = Color3.fromRGB(100, 138, 184),
	glow    = Color3.fromRGB(150, 220, 255),
	brazier = Color3.fromRGB(98, 101, 105),
	fire    = Color3.fromRGB(255, 158, 70),
	lantern = Color3.fromRGB(255, 232, 176),
	window  = Color3.fromRGB(150, 214, 255),
	ice     = Color3.fromRGB(118, 152, 192),
	stone   = Color3.fromRGB(126, 130, 136),
	stoneD  = Color3.fromRGB(92, 96, 102),
}

local function jit(c, rng, a)
	a = a or 10
	return Color3.fromRGB(
		math.clamp(c.R * 255 + rng:NextNumber(-a, a), 0, 255),
		math.clamp(c.G * 255 + rng:NextNumber(-a, a), 0, 255),
		math.clamp(c.B * 255 + rng:NextNumber(-a, a), 0, 255))
end

-- PROTECTED: never removed, never moved.
local KEEP = {
	Platform = true, Pads = true, PlotBoard = true, Campfire = true,
	CampDressing = true, CampDirt = true, CampStand = true, EquipBestPad = true,
}

----------------------------------------------------------------------------------
-- shared pieces
----------------------------------------------------------------------------------
-- a faceted snow dome, the way the hub's roof is built: rings of jittered plates
local function snowDome(parent, cf, R, H, rng, opts)
	opts = opts or {}
	local rings = opts.rings or 4
	-- A dark glacier base course, and every third block laid in glacier rather than
	-- snow. Built purely in Snow the dome was white-on-white against the snowfield and
	-- simply vanished -- the hub only reads because of its dark slate inlay contrast.
	local bn = math.max(8, math.floor(2 * math.pi * R / (R * 0.38)))
	for i = 0, bn - 1 do
		local a = math.rad(i * 360 / bn)
		L.box(parent, "DomeCourse", cf * CFrame.new(math.cos(a) * R, 1.1, math.sin(a) * R) * CFrame.Angles(0, -a, 0),
			Vector3.new(2 * math.pi * R / bn * 1.2, 2.6, 3.2), jit(C.pillar, rng, 10), GLACIER, {solid = true})
	end
	for ring = 0, rings - 1 do
		local t0 = ring / rings
		local t1 = (ring + 1) / rings
		local r = R * math.cos(t0 * math.pi / 2)
		local y = H * math.sin(t0 * math.pi / 2)
		local yNext = H * math.sin(t1 * math.pi / 2)
		local n = math.max(6, math.floor(2 * math.pi * r / (R * 0.42)))
		for i = 0, n - 1 do
			local a = math.rad(i * 360 / n + ring * 11)
			local tilt = math.rad(18 + ring * 16)
			local blue = ((i + ring) % 3 == 0)
			L.box(parent, "RoofPlate",
				cf * CFrame.new(math.cos(a) * r, 2.4 + y + (yNext - y) * 0.4, math.sin(a) * r)
					* CFrame.Angles(0, -a, 0) * CFrame.Angles(-tilt, 0, 0),
				Vector3.new(2 * math.pi * r / n * 1.22, math.max((yNext - y) * 1.5, 2.4), 2.4),
				blue and jit(C.pillar, rng, 14) or jit(C.plate, rng, 9),
				blue and GLACIER or SNOW, {solid = true})
		end
	end
	L.ball(parent, "RoofCap", cf * CFrame.new(0, 2.4 + H * 0.94, 0), R * 0.5, jit(C.plate, rng, 6), SNOW, {solid = true})
	L.post(parent, "DomeFinial", cf * CFrame.new(0, 2.4 + H * 0.94 + R * 0.4, 0), R * 0.35, 0.8, C.pillar, GLACIER, {shadow = false})
	local fg = L.box(parent, "DomeGlow", cf * CFrame.new(0, 2.4 + H * 0.94 + R * 0.6, 0), Vector3.new(1.8, 1.8, 1.8), C.glow, NEON, {collide = false, shadow = false})
	L.light(fg, C.glow, 2.0, 30)
	-- ice windows set into the shell
	for i = 0, 2 do
		local a = math.rad(i * 120 + 40)
		local w = L.box(parent, "IceWindow",
			cf * CFrame.new(math.cos(a) * R * 0.86, 2.4 + H * 0.40, math.sin(a) * R * 0.86) * CFrame.Angles(0, -a, 0),
			Vector3.new(4.5, 5.5, 1.8), C.window, NEON, {collide = false, shadow = false})
		w.Transparency = 0.2
		L.light(w, C.window, 1.4, 20)
	end
end

-- the hub's entrance idiom: a stubby tunnel with jambs and a corbelled cap
local function snowMouth(parent, cf, w, h, d, rng)
	for _, s in ipairs({-1, 1}) do
		L.box(parent, "MouthJamb", cf * CFrame.new(s * (w / 2 + 0.8), h / 2, 0),
			Vector3.new(1.8, h, d), jit(C.plate, rng, 8), SNOW, {solid = true})
	end
	for i = 0, 4 do
		local t = i / 4
		local a = math.rad(t * 180)
		L.box(parent, "TunnelCap", cf * CFrame.new(math.cos(a) * (w / 2 + 0.4), h + math.sin(a) * 2.4, 0)
			* CFrame.Angles(0, 0, -a), Vector3.new(2.2, 1.8, d), jit(C.plate, rng, 8), SNOW, {solid = true})
	end
	L.box(parent, "Corbel", cf * CFrame.new(0, h + 3.4, 0), Vector3.new(w + 4, 1.6, d + 1.4), jit(C.plate, rng, 6), SNOW, {solid = true})
	L.box(parent, "MouthDrift", cf * CFrame.new(0, 0.5, -d / 2 - 1.4), Vector3.new(w + 6, 1.4, 3.5), jit(C.plate, rng, 8), SNOW, {shadow = false})
end

-- the hub's carved inlay: a dark slate field with paw / chevron / band motifs
local function reliefStrip(parent, cf, len, rng, seedOff)
	L.box(parent, "ReliefField", cf, Vector3.new(len, 0.35, 4.6), C.field, SLATE, {shadow = false})
	local n = math.max(2, math.floor(len / 7))
	for i = 0, n - 1 do
		local x = -len / 2 + (i + 0.5) * (len / n)
		local kind = (i + seedOff) % 3
		if kind == 0 then
			-- paw: a pad and four toes
			L.box(parent, "ReliefPaw", cf * CFrame.new(x, 0.28, 0), Vector3.new(1.7, 0.3, 1.5), C.motif, SNOW, {shadow = false})
			for k = -1, 2 do
				L.box(parent, "ReliefPaw", cf * CFrame.new(x + k * 0.62 - 0.3, 0.28, 1.35),
					Vector3.new(0.55, 0.3, 0.65), C.motif, SNOW, {shadow = false})
			end
		elseif kind == 1 then
			for k = -1, 1 do
				L.box(parent, "ReliefChevron", cf * CFrame.new(x + k * 0.9, 0.28, 0) * CFrame.Angles(0, 0, 0),
					Vector3.new(0.5, 0.3, 3.0), C.motif, SNOW, {shadow = false})
			end
		else
			L.box(parent, "ReliefBand", cf * CFrame.new(x, 0.28, 0), Vector3.new(4.2, 0.3, 0.8), C.motif2, SNOW, {shadow = false})
			L.box(parent, "CausewayRune", cf * CFrame.new(x, 0.32, 1.5), Vector3.new(1.4, 0.3, 1.4), C.rune, ICEM, {shadow = false})
		end
	end
end

local function brazier(parent, base, rng)
	L.box(parent, "BrazierBase", CFrame.new(base + Vector3.new(0, 0.9, 0)), Vector3.new(4.0, 1.8, 4.0), C.brazier, SLATE, {solid = true})
	L.post(parent, "BrazierPost", CFrame.new(base + Vector3.new(0, 3.4, 0)), 3.6, 1.5, C.brazier, SLATE, {solid = true})
	L.cyl(parent, "BrazierBowl", CFrame.new(base + Vector3.new(0, 5.4, 0)) * CFrame.Angles(0, 0, math.rad(90)), 1.4, 5.0, C.brazier, SLATE, {solid = true})
	local f = L.box(parent, "BrazierFire", CFrame.new(base + Vector3.new(0, 6.4, 0)), Vector3.new(3.6, 2.0, 3.6), C.fire, NEON, {collide = false, shadow = false})
	f.Transparency = 0.3
	L.light(f, C.fire, 2.4, 30)
end

local function gatePillar(parent, base, h, rng)
	L.box(parent, "GateBase", CFrame.new(base + Vector3.new(0, 1.0, 0)), Vector3.new(5.4, 2.0, 5.4), C.pillar, GLACIER, {solid = true})
	L.box(parent, "GatePillar", CFrame.new(base + Vector3.new(0, h / 2 + 2, 0)), Vector3.new(3.6, h, 3.6), C.pillar, GLACIER, {solid = true})
	L.box(parent, "GateCap", CFrame.new(base + Vector3.new(0, h + 2.6, 0)), Vector3.new(5.0, 1.4, 5.0), C.pillar, GLACIER, {solid = true})
	local g = L.box(parent, "GateGlow", CFrame.new(base + Vector3.new(0, h + 4.2, 0)), Vector3.new(2.4, 2.4, 2.4), C.glow, NEON, {collide = false, shadow = false})
	L.light(g, C.glow, 2.6, 34)
	-- ice grown up the pillar
	for i = 1, 3 do
		L.box(parent, "PillarIce", CFrame.new(base + Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(3, h), rng:NextNumber(-2, 2)))
			* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6), rng:NextNumber(-0.3, 0.3)),
			Vector3.new(rng:NextNumber(1, 2.2), rng:NextNumber(2, 5), rng:NextNumber(1, 2.2)), C.ice, GLACIER,
			{collide = false, shadow = false})
	end
end

local function iceSpike(parent, base, scale, rng)
	local h = rng:NextNumber(6, 20) * scale
	local w = h * rng:NextNumber(0.22, 0.4)
	local segs = 3
	for i = 0, segs - 1 do
		local t = i / segs
		local rr = w * (1 - t) + 0.4
		L.box(parent, "Spike",
			CFrame.new(base + Vector3.new(0, h * (t + 0.5 / segs), 0))
				* CFrame.Angles(rng:NextNumber(-0.06, 0.06), rng:NextNumber(0, 6), rng:NextNumber(-0.06, 0.06)),
			Vector3.new(rr, h / segs * 1.15, rr), jit(C.ice, rng, 12), GLACIER, {solid = true})
	end
	if rng:NextNumber() < 0.5 then
		L.box(parent, "IceShard", CFrame.new(base + Vector3.new(rng:NextNumber(-w, w), h * 0.2, rng:NextNumber(-w, w)))
			* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6), rng:NextNumber(-0.4, 0.4)),
			Vector3.new(w * 0.5, h * 0.45, w * 0.5), jit(C.ice, rng, 14), GLACIER, {shadow = false})
	end
end
M.iceSpike = iceSpike

----------------------------------------------------------------------------------
-- 1. THE PLOTS -- World 1's camp, rebuilt in tundra dress
----------------------------------------------------------------------------------
-- The first attempt invented a new igloo-village layout and the plots came out
-- unrecognisable as camps. They are supposed to read as the SAME camp the valley
-- has -- fenced rim, pines, bed roll, lantern post, stone fire ring -- only frozen.
--
-- So the geometry is CLONED from a valley plot (identical shapes, identical relative
-- positions) and then re-skinned: evergreens go dark and get snow loads, timber goes
-- frost-bleached, and ice grows on the stonework.
local THEME = {
	-- leaf greens -> darker, bluer evergreen
	[Color3.fromRGB(58,151,77)]  = Color3.fromRGB(38,96,72),
	[Color3.fromRGB(76,169,95)]  = Color3.fromRGB(48,112,86),
	[Color3.fromRGB(40,131,58)]  = Color3.fromRGB(30,82,62),
	[Color3.fromRGB(86,200,84)]  = Color3.fromRGB(56,124,92),
	-- timber -> frost-bleached
	[Color3.fromRGB(97,59,32)]   = Color3.fromRGB(96,86,84),
	[Color3.fromRGB(116,71,36)]  = Color3.fromRGB(112,102,100),
	[Color3.fromRGB(146,100,62)] = Color3.fromRGB(132,124,122),
	[Color3.fromRGB(124,82,50)]  = Color3.fromRGB(118,110,110),
	[Color3.fromRGB(82,50,27)]   = Color3.fromRGB(84,76,76),
	[Color3.fromRGB(205,132,58)] = Color3.fromRGB(178,186,196),
	[Color3.fromRGB(135,93,50)]  = Color3.fromRGB(140,150,164),
}

local function nearest(c)
	local best, bd = nil, 0.06
	for k, v in pairs(THEME) do
		local d = math.abs(k.R - c.R) + math.abs(k.G - c.G) + math.abs(k.B - c.B)
		if d < bd then best, bd = v, d end
	end
	return best
end

-- Re-skin a cloned valley object for the tundra, and load it with snow.
-- `obj` may be a Model or a single BasePart. It must NEVER be handed the whole
-- dressing model: doing that re-frosted everything already placed on each call and
-- compounded to 11,762 parts per plot.
local function frost(obj, rng)
	local tops = {}
	local list = obj:IsA("BasePart") and {obj} or obj:GetDescendants()
	for _, d in ipairs(list) do
		if d:IsA("BasePart") and d.Name ~= "SnowLoad" then
			local repl = nearest(d.Color)
			if repl then d.Color = jit(repl, rng, 7) end
			if d.Material == Enum.Material.Grass or d.Material == Enum.Material.LeafyGrass then
				d.Material = Enum.Material.SmoothPlastic
			end
			tops[#tops + 1] = d
		end
	end
	-- snow settled on every upward face, which is what actually sells "frozen"
	local host = obj:IsA("BasePart") and obj.Parent or obj
	for _, d in ipairs(tops) do
		if d.Size.X > 1.2 and d.Size.Z > 1.2 and rng:NextNumber() < 0.6 then
			local cap = L.box(host, "SnowLoad",
				d.CFrame * CFrame.new(0, d.Size.Y * 0.5 + 0.16, 0),
				Vector3.new(d.Size.X * rng:NextNumber(0.75, 1.02), 0.42, d.Size.Z * rng:NextNumber(0.75, 1.02)),
				jit(Color3.fromRGB(226, 234, 245), rng, 6), SNOW, {collide = false, shadow = false})
			cap.CanQuery = false
		end
	end
end

function M.plots()
	local pb = workspace.PlayerBases
	local rng = Random.new(20260809)

	-- the valley plot we copy from
	local tmpl
	for _, p in ipairs(pb:GetChildren()) do
		local plat = p:FindFirstChild("Platform")
		if plat and plat.Position.X > -7000 and p:FindFirstChild("CampBed") then tmpl = p break end
	end
	if not tmpl then return "no valley template plot found" end
	local tPlat = tmpl.Platform

	-- decorative children to copy, with their WORLD offset from the template platform
	local COPY = {CampPine = true, CampBed = true, LanternPost = true, Lantern = true,
		PitStone = true, FireLog = true, WoodPile = true, CampChest = true}
	local blueprint = {}
	for _, c in ipairs(tmpl:GetChildren()) do
		if COPY[c.Name] then
			local pos
			if c:IsA("Model") then pos = c:GetBoundingBox().Position elseif c:IsA("BasePart") then pos = c.Position end
			if pos then blueprint[#blueprint + 1] = {obj = c, off = pos - tPlat.Position} end
		end
	end

	local done, copied = 0, 0
	for _, plot in ipairs(pb:GetChildren()) do
		if plot:IsA("Model") then
			local plat = plot:FindFirstChild("Platform")
			if plat and plat.Position.X < -7000 then
				local old = plot:FindFirstChild("IglooDressing")
				if old then old:Destroy() end
				local dress = Instance.new("Model")
				dress.Name = "IglooDressing"
				dress.Parent = plot

				for _, b in ipairs(blueprint) do
					local c = b.obj:Clone()
					c.Parent = dress
					local target = plat.Position + b.off
					if c:IsA("Model") then
						c:PivotTo(CFrame.new(target) * CFrame.Angles(0, rng:NextNumber(-0.25, 0.25), 0))
					else
						c.Position = target
					end
					frost(c:IsA("Model") and c or dress, rng)
					copied = copied + 1
				end

				-- tundra accents on top of the valley layout
				local hx, hz = plat.Size.X / 2, plat.Size.Z / 2
				local cf = plat.CFrame
				for i = 1, 8 do
					local a = rng:NextNumber(0, 6.283)
					iceSpike(dress, (cf * CFrame.new(math.cos(a) * (hx + rng:NextNumber(6, 16)), -1,
						math.sin(a) * (hz + rng:NextNumber(6, 16)))).Position, rng:NextNumber(0.5, 1.1), rng)
				end
				for _, sx in ipairs({-1, 1}) do
					gatePillar(dress, (cf * CFrame.new(sx * (hx - 4), 0.5, hz - 5)).Position, 8, rng)
				end
				done = done + 1
			end
		end
	end
	return string.format("plots: %d tundra camps rebuilt from the valley layout (%d objects copied per plot), frost-themed",
		done, #blueprint)
end

-- 2. THE SKIP DOCK -- stone, pillared, frozen over.
-- It was brown timber, which reads as a warm-water jetty on an ice shelf. Existing
-- parts are re-skinned to stone IN PLACE (names kept, so name lookups still work),
-- then a colonnade is added down both sides and ice grown over deck and pillars.
function M.dock()
	local sa = workspace.GameWorld.FrozenTundra:FindFirstChild("SkipArea")
	local dock = sa and sa:FindFirstChild("Dock")
	if not dock then return "no Dock found" end
	local rng = Random.new(4242)
	local old = sa:FindFirstChild("DockStonework"); if old then old:Destroy() end
	local work = Instance.new("Model"); work.Name = "DockStonework"; work.Parent = sa
	local mn = Vector3.new(1e9,1e9,1e9); local mx = Vector3.new(-1e9,-1e9,-1e9)
	local reskinned = 0
	for _, d in ipairs(dock:GetDescendants()) do
		if d:IsA("BasePart") then
			mn = Vector3.new(math.min(mn.X,d.Position.X-d.Size.X/2), math.min(mn.Y,d.Position.Y-d.Size.Y/2), math.min(mn.Z,d.Position.Z-d.Size.Z/2))
			mx = Vector3.new(math.max(mx.X,d.Position.X+d.Size.X/2), math.max(mx.Y,d.Position.Y+d.Size.Y/2), math.max(mx.Z,d.Position.Z+d.Size.Z/2))
			if d.Material == Enum.Material.SmoothPlastic or d.Material == Enum.Material.Wood or d.Material == Enum.Material.WoodPlanks then
				d.Material = SLATE
				d.Color = jit((d.Name == "Seam" or d.Name == "SeamCross") and C.stoneD or C.stone, rng, 9)
				reskinned = reskinned + 1
			end
		end
	end
	local cx, cz = (mn.X+mx.X)/2, (mn.Z+mx.Z)/2
	local topY = mx.Y
	local halfX, halfZ = (mx.X-mn.X)/2, (mx.Z-mn.Z)/2
	local alongZ = halfZ >= halfX
	local hL = alongZ and halfZ or halfX
	local hW = alongZ and halfX or halfZ
	local steps = math.max(6, math.floor(hL*2/8))
	for i = 0, steps do
		local t = -1 + 2*(i/steps)
		for _, s in ipairs({-1,1}) do
			local px = alongZ and (cx + s*hW) or (cx + t*hL)
			local pz = alongZ and (cz + t*hL) or (cz + s*hW)
			L.box(work, "DockKerb", CFrame.new(px, topY-0.4, pz),
				alongZ and Vector3.new(2.4,1.6,hL*2/steps*1.1) or Vector3.new(hL*2/steps*1.1,1.6,2.4),
				jit(C.stone,rng,10), SLATE, {solid=true})
		end
	end
	-- ONE pillar per side, not a colonnade. Five a side turned the dock into a
	-- temple; the brief is a stone dock with a pillar either side of it.
	local pillars = 0
	for _, t in ipairs({0}) do
		for _, s in ipairs({-1,1}) do
			-- The pillars flank the dock across its OTHER axis: offset along the long
			-- axis, centred on the short one. The first version offset them the other
			-- way and put them on the wrong pair of sides.
			local px = alongZ and (cx + t*hW) or (cx + s*(hL+4.5))
			local pz = alongZ and (cz + s*(hL+4.5)) or (cz + t*hW)
			-- taller and heavier now that there are only two of them
			local h = 22
			L.box(work,"PillarBase",CFrame.new(px,topY-1.4,pz),Vector3.new(9,3.6,9),jit(C.stoneD,rng,8),SLATE,{solid=true})
			L.box(work,"PillarPlinth",CFrame.new(px,topY+1.2,pz),Vector3.new(7.6,2.0,7.6),jit(C.stone,rng,8),SLATE,{solid=true})
			L.post(work,"DockPillar",CFrame.new(px,topY+h/2+2,pz),h,6.0,jit(C.stone,rng,8),SLATE,{solid=true})
			for b = 1, 3 do
				L.post(work,"PillarBand",CFrame.new(px,topY+2+h*b/4,pz),1.2,6.8,jit(C.stoneD,rng,8),SLATE,{shadow=false})
			end
			L.box(work,"PillarCap",CFrame.new(px,topY+h+3.4,pz),Vector3.new(8.6,2.6,8.6),jit(C.stone,rng,8),SLATE,{solid=true})
			local g = L.box(work,"PillarLamp",CFrame.new(px,topY+h+6.0,pz),Vector3.new(3.0,3.4,3.0),C.lantern,NEON,{collide=false,shadow=false})
			L.light(g, C.lantern, 2.6, 36)
			for k = 1, 7 do
				local a = rng:NextNumber(0,6.283)
				L.box(work,"PillarIce",CFrame.new(px+math.cos(a)*3.1, topY+rng:NextNumber(2,h*0.9), pz+math.sin(a)*3.1)
					* CFrame.Angles(rng:NextNumber(-0.25,0.25), -a, rng:NextNumber(-0.25,0.25)),
					Vector3.new(rng:NextNumber(1.4,2.6), rng:NextNumber(3,7), rng:NextNumber(1.2,2.2)),
					jit(C.ice,rng,12), GLACIER, {collide=false,shadow=false})
			end
			for k = 1, 6 do
				local a = rng:NextNumber(0,6.283)
				L.box(work,"Icicle",CFrame.new(px+math.cos(a)*3.8, topY+h+2.0, pz+math.sin(a)*3.8),
					Vector3.new(0.8, rng:NextNumber(2,4.5), 0.8), jit(C.ice,rng,10), GLACIER, {collide=false,shadow=false})
			end
			pillars = pillars + 1
		end
	end
	for i = 1, 30 do
		local t, u = rng:NextNumber(-1,1), rng:NextNumber(-0.85,0.85)
		local px = alongZ and (cx+u*hW) or (cx+t*hL)
		local pz = alongZ and (cz+t*hL) or (cz+u*hW)
		L.box(work,"DeckIce",CFrame.new(px,topY+0.2,pz)*CFrame.Angles(0,rng:NextNumber(0,6),0),
			Vector3.new(rng:NextNumber(3,8), rng:NextNumber(0.5,1.4), rng:NextNumber(3,8)),
			jit(C.ice,rng,14), GLACIER, {collide=false,shadow=false})
	end
	for i = 1, 16 do
		local t = rng:NextNumber(-1,1)
		local s = rng:NextNumber() < 0.5 and -1 or 1
		local px = alongZ and (cx+s*hW) or (cx+t*hL)
		local pz = alongZ and (cz+t*hL) or (cz+s*hW)
		L.box(work,"EdgeIce",CFrame.new(px, topY-rng:NextNumber(2,5), pz)
			*CFrame.Angles(rng:NextNumber(-0.3,0.3), rng:NextNumber(0,6), rng:NextNumber(-0.3,0.3)),
			Vector3.new(rng:NextNumber(2,5), rng:NextNumber(3,8), rng:NextNumber(2,5)),
			jit(C.ice,rng,12), GLACIER, {collide=false,shadow=false})
	end
	local n = 0
	for _, d in ipairs(work:GetDescendants()) do if d:IsA("BasePart") then n = n + 1 end end
	return "dock: " .. reskinned .. " timber parts re-skinned to stone, " .. pillars .. " pillars, " .. n .. " new stone/ice parts"
end

-- 3. MORE ICE SPIKES ACROSS THE SNOWFIELD
function M.spikes(target)
	local ft = workspace.GameWorld.FrozenTundra
	local folder = ft:FindFirstChild("IceSpikes"); if folder then folder:Destroy() end
	folder = Instance.new("Folder"); folder.Name = "IceSpikes"; folder.Parent = ft
	local rng = Random.new(90210)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = {workspace.Terrain}
	rp.IgnoreWater = true
	local avoid = {{-8000,-8100,200},{-8000,-7804,165}}
	for _, p in ipairs(workspace.PlayerBases:GetChildren()) do
		local plat = p:FindFirstChild("Platform")
		if plat and plat.Position.X < -7000 then avoid[#avoid+1] = {plat.Position.X, plat.Position.Z, 68} end
	end
	target = target or 170
	local placed, clusters = 0, 0
	for attempt = 1, 5000 do
		if placed >= target then break end
		local x = rng:NextNumber(-8400,-7620)
		local z = rng:NextNumber(-8380,-6900)
		local blocked = false
		for _, a in ipairs(avoid) do
			if (x-a[1])^2 + (z-a[2])^2 < a[3]^2 then blocked = true break end
		end
		if not blocked then
			local hit = workspace:Raycast(Vector3.new(x,2200,z), Vector3.new(0,-400,0), rp)
			if hit and hit.Material == Enum.Material.Snow and hit.Position.Y > 2000 then
				for k = 1, rng:NextInteger(2,5) do
					local ox, oz = rng:NextNumber(-15,15), rng:NextNumber(-15,15)
					local h2 = workspace:Raycast(Vector3.new(x+ox,2200,z+oz), Vector3.new(0,-400,0), rp)
					if h2 and h2.Material == Enum.Material.Snow then
						iceSpike(folder, h2.Position - Vector3.new(0,1.5,0), rng:NextNumber(0.5,1.5), rng)
						placed = placed + 1
					end
				end
				clusters = clusters + 1
			end
		end
	end
	local n = 0
	for _, d in ipairs(folder:GetDescendants()) do if d:IsA("BasePart") then n = n + 1 end end
	return "ice spikes: " .. placed .. " spikes in " .. clusters .. " clusters (" .. n .. " parts)"
end

return M
