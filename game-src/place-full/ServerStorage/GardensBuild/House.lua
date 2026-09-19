-- GardensHouse -- gothic-elven buildings for the town of Aelunmyr.
--
-- THE ENCLOSURE CONTRACT. Every building this module produces is closed: four full
-- walls, a floor, and a roof whose gable triangles are filled by A.gableFill so the
-- roof always has wall under every edge. Openings are cut by A.wall, which builds
-- masonry around them in slices rather than assembling loose panels and hoping the
-- joins meet.
--
-- Walls deliberately OVERLAP at the corners (the +/-Z walls span the full width and
-- the +/-X walls span the full depth) -- a shared corner is worth a few duplicated
-- studs of stone to make a gap impossible.

local L = require(script.Parent.Lib)
local A = require(script.Parent.Arch)
local P = require(script.Parent.Props)

local H = {}

local function litWindow(parent, cf, w, h, rise, opts)
	A.traceryWindow(parent, cf, w, h, rise, opts)
end

-- cf: centre of the building footprint, at ground level. +X = width, +Z = depth.
-- The roof ridge runs along X, so the gable ends are the +/-X walls.
function H.elvenHouse(parent, cf, opts)
	opts = opts or {}
	local rng = Random.new(opts.seed or 3)
	local m = Instance.new("Model")
	m.Name = opts.name or "ElvenHouse"
	m.Parent = parent

	local w = opts.width or rng:NextNumber(24, 34)
	local d = opts.depth or rng:NextNumber(20, 28)
	local wallH = opts.wallH or rng:NextNumber(22, 34)
	local t = opts.thick or 2.0
	local stone = opts.stone or L.C.ElvenStone
	local dark = opts.dark or L.C.GreyStone
	local mat = opts.mat or L.M.Stone
	local glass = opts.glass or {L.C.GlowGold, L.C.GlowCyan, L.C.GlowGreen}

	-- plinth and floor
	L.box(m, "Plinth", cf * CFrame.new(0, 1.2, 0), Vector3.new(w + 3.2, 2.4, d + 3.2), dark, mat, {solid = true})
	L.box(m, "PlinthMould", cf * CFrame.new(0, 2.6, 0), Vector3.new(w + 2.2, 0.8, d + 2.2), opts.trim or L.C.PaleStone, mat, {shadow = false})
	-- The floor OVERLAPS the plinth. At 2.6..3.8 over a plinth ending at 2.4 it left a
	-- 0.2-stud slot right round the building, screened only by the moulding -- and the
	-- moulding is decorative trim with CanQuery off, so it stopped nothing.
	L.box(m, "Floor", cf * CFrame.new(0, 3.0, 0), Vector3.new(w + 0.6, 2.2, d + 0.6), dark, L.M.Cobble, {solid = true})
	local base = cf * CFrame.new(0, 3.0, 0)

	-- ===== windows =====
	local winH = wallH * 0.34
	local winRise = winH * 0.75
	local sill = wallH * 0.32
	local nSide = math.max(1, math.floor(w / 13))
	local sideOpenings, gableOpenings = {}, {}
	for i = 1, nSide do
		local x = -w / 2 + w * i / (nSide + 1)
		sideOpenings[#sideOpenings + 1] = {x = x, w = 5.2, sill = sill, h = winH, rise = winRise}
	end
	local nEnd = math.max(1, math.floor(d / 15))
	for i = 1, nEnd do
		local x = -d / 2 + d * i / (nEnd + 1)
		gableOpenings[#gableOpenings + 1] = {x = x, w = 5.0, sill = sill, h = winH, rise = winRise}
	end

	-- ===== the four walls =====
	-- front (-Z), with the door
	local doorW, doorH, doorRise = 7.0, wallH * 0.42, 5.5
	local frontOpenings = {{x = 0, w = doorW, sill = 0, h = doorH, rise = doorRise}}
	for i = 1, nSide do
		local x = -w / 2 + w * i / (nSide + 1)
		if math.abs(x) > doorW * 0.9 then
			frontOpenings[#frontOpenings + 1] = {x = x, w = 5.2, sill = sill, h = winH, rise = winRise}
		end
	end
	local frontCF = base * CFrame.new(0, 0, -d / 2) * CFrame.Angles(0, math.pi, 0)
	A.wall(m, frontCF, w, wallH, t, {openings = frontOpenings, color = stone, mat = mat,
		trimColor = opts.trim or L.C.PaleStone, name = "FrontWall"})
	local backCF = base * CFrame.new(0, 0, d / 2)
	A.wall(m, backCF, w, wallH, t, {openings = sideOpenings, color = stone, mat = mat,
		trimColor = opts.trim or L.C.PaleStone, name = "BackWall"})
	local rightCF = base * CFrame.new(w / 2, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
	A.wall(m, rightCF, d, wallH, t, {openings = gableOpenings, color = stone, mat = mat,
		trimColor = opts.trim or L.C.PaleStone, name = "EndWall"})
	local leftCF = base * CFrame.new(-w / 2, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0)
	A.wall(m, leftCF, d, wallH, t, {openings = gableOpenings, color = stone, mat = mat,
		trimColor = opts.trim or L.C.PaleStone, name = "EndWall"})

	-- glazing in every opening
	for i, o in ipairs(sideOpenings) do
		litWindow(m, backCF * CFrame.new(o.x, o.sill, 0), o.w, o.h, o.rise,
			{colors = glass, seed = i, lightColor = glass[1], lightBrightness = 2.0, lightRange = 26, stoneColor = opts.trim})
	end
	for i, o in ipairs(gableOpenings) do
		litWindow(m, rightCF * CFrame.new(o.x, o.sill, 0), o.w, o.h, o.rise, {colors = glass, seed = i + 3, stoneColor = opts.trim})
		litWindow(m, leftCF * CFrame.new(o.x, o.sill, 0), o.w, o.h, o.rise, {colors = glass, seed = i + 6, stoneColor = opts.trim})
	end
	for i = 2, #frontOpenings do
		local o = frontOpenings[i]
		litWindow(m, frontCF * CFrame.new(o.x, o.sill, 0), o.w, o.h, o.rise, {colors = glass, seed = i + 9, stoneColor = opts.trim})
	end
	-- THE TYMPANUM. The doorway's arched head was left open above the door leaf, so
	-- the front wall had a crescent of daylight through it. Filled with the same
	-- vertical-slice trick the walls use, then carved.
	do
		local prof = A.archProfile(doorW, doorRise)
		local n = 10
		for i = 0, n - 1 do
			local x = -doorW / 2 + (i + 0.5) * (doorW / n)
			local hgt = prof(x)
			if hgt > 0.05 then
				L.box(m, "Tympanum", frontCF * CFrame.new(x, doorH + hgt / 2, 0),
					Vector3.new(doorW / n + 0.06, hgt, t), stone, mat, {solid = true})
			end
		end
		L.glow(m, "Fanlight", frontCF * CFrame.new(0, doorH + doorRise * 0.42, 0.5),
			Vector3.new(doorW * 0.5, doorRise * 0.42, 0.3), L.C.GlowGold, 1.2, 18)
	end
	-- the door leaf itself, sized to actually FILL its opening (it used to be 0.8
	-- studs narrower, leaving a slot down each side)
	L.box(m, "Door", frontCF * CFrame.new(0, doorH / 2, 0.4), Vector3.new(doorW + 0.4, doorH + 0.2, 0.6),
		opts.wood or L.C.Wood, Enum.Material.WoodPlanks, {solid = true})
	for i = 1, 3 do
		L.box(m, "DoorBand", frontCF * CFrame.new(0, doorH * i / 4, 0.75), Vector3.new(doorW - 0.6, 0.5, 0.3),
			L.C.Iron, Enum.Material.Metal, {shadow = false})
	end
	L.ball(m, "DoorKnob", frontCF * CFrame.new(doorW * 0.28, doorH * 0.45, 0.9), 0.7, L.C.Gold, Enum.Material.Foil, {shadow = false})
	-- doorstep
	L.box(m, "Step", frontCF * CFrame.new(0, -0.6, -2.2), Vector3.new(doorW + 4, 1.4, 4.4), opts.trim or L.C.PaleStone, mat, {solid = true})

	-- ===== corner buttresses (they also hide the corner joints) =====
	for _, sx in ipairs({-1, 1}) do
		for _, sz in ipairs({-1, 1}) do
			L.box(m, "Buttress", base * CFrame.new(sx * (w / 2 + 0.2), wallH * 0.44, sz * (d / 2 + 0.2)),
				Vector3.new(3.6, wallH * 0.88, 3.6), stone, mat, {solid = true})
			L.box(m, "ButtressCap", base * CFrame.new(sx * (w / 2 + 0.2), wallH * 0.88 + 0.6, sz * (d / 2 + 0.2)),
				Vector3.new(4.4, 1.2, 4.4), opts.trim or L.C.PaleStone, mat, {shadow = false})
			-- a small pinnacle
			A.spire(m, base * CFrame.new(sx * (w / 2 + 0.2), wallH * 0.88 + 1.2, sz * (d / 2 + 0.2)),
				1.7, 6.5, {segs = 7, color = dark, mat = mat, finial = false})
		end
	end
	-- string course under the eaves
	L.box(m, "StringCourse", base * CFrame.new(0, wallH - 1.2, 0), Vector3.new(w + 2.6, 1.0, d + 2.6), opts.trim or L.C.PaleStone, mat, {shadow = false})

	-- ===== roof =====
	local rise = opts.roofRise or wallH * 0.62
	local roofCF = base * CFrame.new(0, wallH, 0)
	if opts.curvedRoof ~= false then
		A.roofCurved(m, roofCF, w, d, rise, {
			color = opts.roof or L.C.DarkStone, mat = mat, thick = 1.2, overhang = 2.6, bands = 5,
			gableColor = stone, gableThick = t + 0.4, ridgeColor = opts.trim or L.C.PaleStone,
		})
	else
		A.roofPitched(m, roofCF, w, d, rise, {
			color = opts.roof or L.C.DarkStone, mat = mat, thick = 1.2, overhang = 2.6,
			gableColor = stone, gableThick = t + 0.4, ridgeColor = opts.trim or L.C.PaleStone,
		})
	end
	-- ridge cresting
	for i = 0, math.floor(w / 4) do
		L.box(m, "Cresting", roofCF * CFrame.new(-w / 2 + i * 4, rise + 2.2, 0), Vector3.new(0.5, 2.0, 0.4),
			opts.trim or L.C.PaleStone, mat, {shadow = false})
	end
	-- chimney (a closed stack, capped)
	if opts.chimney ~= false then
		local cx = w * 0.3 * (rng:NextNumber() < 0.5 and 1 or -1)
		local ch = rise + rng:NextNumber(8, 14)
		L.box(m, "Chimney", roofCF * CFrame.new(cx, ch / 2, d * 0.18), Vector3.new(4.4, ch, 4.4), dark, L.M.Brick, {solid = true})
		L.box(m, "ChimneyCap", roofCF * CFrame.new(cx, ch + 0.6, d * 0.18), Vector3.new(5.6, 1.2, 5.6), opts.trim or L.C.PaleStone, mat, {shadow = false})
		L.glow(m, "ChimneyGlow", roofCF * CFrame.new(cx, ch + 1.6, d * 0.18), Vector3.new(2.2, 0.6, 2.2), L.C.GlowGold, 0.8, 14)
	end

	-- ===== balcony on some houses =====
	if opts.balcony then
		local by = wallH * 0.58
		L.box(m, "BalconyFloor", frontCF * CFrame.new(0, by, -3.0), Vector3.new(w * 0.5, 0.9, 6.0), opts.trim or L.C.PaleStone, mat, {solid = true})
		for _, s in ipairs({-1, 1}) do
			L.box(m, "BalconyCorbel", frontCF * CFrame.new(s * w * 0.2, by - 1.8, -1.6) * CFrame.Angles(math.rad(28), 0, 0),
				Vector3.new(1.6, 4.0, 1.6), stone, mat, {shadow = false})
		end
		local bp = {}
		for i = 0, 6 do
			bp[#bp + 1] = (frontCF * CFrame.new(-w * 0.25 + w * 0.5 * i / 6, by + 0.5, -5.8)).Position
		end
		A.railing(m, bp, {height = 3.0, spacing = 2.2, color = opts.trim or L.C.PaleStone, postDia = 0.6, railW = 1.0})
		P.hangingLantern(m, (frontCF * CFrame.new(w * 0.24, by + 4.0, -5.6)).Position, 1.6,
			{scale = 0.6, color = L.C.GlowGold, brightness = 1.6, range = 20})
	end

	-- ===== nature reclaiming it =====
	local vineN = opts.vines or rng:NextInteger(2, 5)
	for i = 1, vineN do
		local sx = rng:NextNumber(-w / 2, w / 2)
		local sz = (rng:NextNumber() < 0.5 and -1 or 1) * (d / 2 + 0.6)
		P.vine(m, (base * CFrame.new(sx, wallH - rng:NextNumber(1, 8), sz)).Position,
			rng:NextNumber(8, wallH * 0.7), {seed = rng:NextInteger(1, 9999), leafColor = L.C.LeafDark,
			glow = rng:NextNumber() < 0.3 and L.C.GlowGreen or nil})
	end
	for i = 1, rng:NextInteger(3, 7) do
		local sx = rng:NextNumber(-w / 2, w / 2)
		local sz = (rng:NextNumber() < 0.5 and -1 or 1) * (d / 2 + 0.3)
		L.blob(m, "WallMoss", base * CFrame.new(sx, rng:NextNumber(1, wallH * 0.7), sz),
			Vector3.new(rng:NextNumber(3, 8), rng:NextNumber(2, 6), 0.8),
			rng:NextNumber() < 0.3 and L.C.Lichen or L.C.Moss, Enum.Material.Grass, {collide = false, shadow = false})
	end
	return m, wallH
end

-- A polygonal tower: closed shaft, floors, windows, and a spire on top.
function H.tower(parent, cf, opts)
	opts = opts or {}
	local rng = Random.new(opts.seed or 5)
	local m = Instance.new("Model")
	m.Name = opts.name or "Tower"
	m.Parent = parent
	local r = opts.radius or rng:NextNumber(9, 13)
	local h = opts.height or rng:NextNumber(46, 78)
	local sides = opts.sides or 8
	local stone = opts.stone or L.C.ElvenStone
	local mat = opts.mat or L.M.Stone
	local t = 2.4

	L.box(m, "TowerPlinth", cf * CFrame.new(0, 1.4, 0), Vector3.new(r * 2.6, 2.8, r * 2.6), opts.dark or L.C.GreyStone, mat, {solid = true})
	-- shaft: each side is a full-height slab, so the ring is closed all the way up
	local segArc = 2 * math.pi * r / sides * 1.22
	for i = 0, sides - 1 do
		local a = math.rad(i * 360 / sides)
		local wcf = cf * CFrame.new(math.cos(a) * r, 0, math.sin(a) * r) * CFrame.Angles(0, -a + math.pi / 2, 0)
		local openings = {}
		-- two tiers of lancet windows, on alternating faces
		if i % 2 == 0 then
			for tier = 1, math.max(1, math.floor(h / 26)) do
				openings[#openings + 1] = {x = 0, w = 3.6, sill = 10 + (tier - 1) * 22, h = 7.5, rise = 4.2}
			end
		end
		A.wall(m, wcf, segArc, h, t, {openings = openings, color = stone, mat = mat,
			trimColor = opts.trim or L.C.PaleStone, name = "TowerWall", slices = 8})
		for _, o in ipairs(openings) do
			A.traceryWindow(m, wcf * CFrame.new(o.x, o.sill, 0), o.w, o.h, o.rise,
				{colors = {L.C.GlowGold, L.C.GlowCyan}, mullions = 1, seed = i, stoneColor = opts.trim})
		end
	end
	-- string courses
	for tier = 1, math.floor(h / 22) do
		local y = tier * 22
		if y < h - 4 then
			for i = 0, sides - 1 do
				local a = math.rad(i * 360 / sides)
				L.box(m, "TowerBand", cf * CFrame.new(math.cos(a) * (r + 0.6), y, math.sin(a) * (r + 0.6)) * CFrame.Angles(0, -a + math.pi / 2, 0),
					Vector3.new(segArc, 1.2, 1.6), opts.trim or L.C.PaleStone, mat, {shadow = false})
			end
		end
	end
	-- capped top: a solid floor so the tower is not an open tube, then battlement + spire
	L.cyl(m, "TowerCap", cf * CFrame.new(0, h + 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)), 1.6, r * 2.3, stone, mat, {solid = true})
	for i = 0, sides * 2 - 1 do
		local a = math.rad(i * 360 / (sides * 2))
		L.box(m, "Merlon", cf * CFrame.new(math.cos(a) * (r + 0.5), h + 3.0, math.sin(a) * (r + 0.5)) * CFrame.Angles(0, -a, 0),
			Vector3.new(1.6, 4.0, 3.0), opts.trim or L.C.PaleStone, mat, {shadow = false})
	end
	A.spire(m, cf * CFrame.new(0, h + 1.4, 0), r * 0.95, opts.spireH or h * 0.55,
		{segs = 18, color = opts.roof or L.C.DarkStone, mat = mat, curve = 1.25, finialColor = L.C.Gold})
	-- a lantern at the top, so towers read as landmarks in the dark
	L.glow(m, "TowerBeacon", cf * CFrame.new(0, h + 4, 0), Vector3.new(3, 3, 3), opts.beacon or L.C.GlowCyan, 3.0, 90, "blob")
	return m, h
end

-- An arched bridge between two points, with piers reaching the ground.
function H.archBridge(parent, a, b, width, opts)
	opts = opts or {}
	local m = Instance.new("Model")
	m.Name = opts.name or "Bridge"
	m.Parent = parent
	local stone = opts.stone or L.C.WeatheredStone
	local mat = opts.mat or L.M.Stone
	local span = (b - a).Magnitude
	local dir = (b - a).Unit
	local rise = opts.rise or span * 0.12
	local segs = math.max(6, math.floor(span / 8))
	local prev
	for i = 0, segs do
		local u = i / segs
		local p = a:Lerp(b, u) + Vector3.new(0, math.sin(u * math.pi) * rise, 0)
		if prev then
			local mid = (prev + p) / 2
			local len = (p - prev).Magnitude
			local cf = CFrame.lookAt(mid, p)
			L.box(m, "BridgeDeck", cf, Vector3.new(width, 1.8, len + 0.3), stone, mat, {solid = true})
			-- the arch ring below the deck
			local drop = 3.5 + math.sin(u * math.pi) * rise * 0.5
			L.box(m, "ArchRing", cf * CFrame.new(0, -drop * 0.5 - 0.9, 0), Vector3.new(width * 0.82, drop, len + 0.3), stone, mat, {shadow = false})
			-- parapets
			for _, s in ipairs({1, -1}) do
				L.box(m, "Parapet", cf * CFrame.new(s * (width / 2 - 0.6), 2.2, 0), Vector3.new(1.2, 2.6, len + 0.3), opts.trim or L.C.PaleStone, mat, {solid = true})
			end
		end
		prev = p
	end
	-- piers at the ends, dropped to the given foot heights
	if opts.footA then
		L.box(m, "Pier", CFrame.new((a + Vector3.new(0, opts.footA, 0)) * 0.5 + a * 0.5 - Vector3.new(0, 0, 0)), Vector3.new(1, 1, 1), stone, mat, {shadow = false})
	end
	for _, e in ipairs({{a, opts.groundA}, {b, opts.groundB}}) do
		if e[2] then
			local top = e[1].Y
			local hgt = math.max(top - e[2], 1)
			L.box(m, "Abutment", CFrame.new(e[1] - Vector3.new(0, hgt / 2, 0)), Vector3.new(width + 3, hgt, width * 0.7), stone, mat, {solid = true})
		end
	end
	return m
end

return H
