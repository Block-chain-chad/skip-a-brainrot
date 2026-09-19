-- GardensArch -- gothic-elven structural builders for World 3.
--
-- THE ANTI-GAP RULE. Past builds left holes in walls and roofs floating over nothing.
-- Everything here is watertight BY CONSTRUCTION rather than by careful placement:
--
--  * A.wall() takes a list of openings and fills the wall with VERTICAL SLICES that
--    run from the opening profile up to the wall head. A slice cannot miss its
--    neighbour, so a wall cannot have a hole in it that was not asked for.
--  * A.gableFill() closes the triangle/curve between a wall head and a roof with the
--    same slicing. A roof therefore always has a wall under every edge of it.
--  * A.roofPitched()/A.roofCurved() always emit their own gable fills unless the
--    caller says the gable is somebody else's job (openGable), which is only correct
--    when another wing's roof continues through.

local L = require(script.Parent.Lib)
local A = {}

----------------------------------------------------------------------------------
-- POINTED ARCH GEOMETRY
----------------------------------------------------------------------------------
-- Two-centred arch of span s and rise r. Returns a function giving arch height above
-- the springing line at local offset x in [-s/2, s/2].
function A.archProfile(span, rise)
	local half = span * 0.5
	if rise <= half + 0.01 then
		-- semicircle (or flatter): treat as a segmental arc through the apex
		local r = rise
		return function(x)
			local t = math.clamp(math.abs(x) / half, 0, 1)
			return r * math.sqrt(math.max(0, 1 - t * t))
		end
	end
	local d = (rise * rise - half * half) / span
	local R = half + d
	return function(x)
		local ax = math.abs(x) + d
		return math.sqrt(math.max(0, R * R - ax * ax))
	end
end

----------------------------------------------------------------------------------
-- WALLS
----------------------------------------------------------------------------------
-- cf     : centre of the wall's BASE, +X along the wall, +Z is the wall's outward normal
-- length : along local X
-- height : wall head height above the base
-- thick  : along local Z
-- opts.openings : { {x=, w=, sill=, h=, rise=} , ... }   rise>0 makes it a pointed arch
-- opts.color / opts.mat / opts.slices (slices per opening head, default 14)
function A.wall(parent, cf, length, height, thick, opts)
	opts = opts or {}
	local color = opts.color or L.C.ElvenStone
	local mat = opts.mat or L.M.Stone
	local o = {solid = true}
	local openings = opts.openings or {}
	local name = opts.name or "Wall"

	-- sort openings left to right and validate they sit inside the wall
	local ops = {}
	for _, op in ipairs(openings) do
		local x, w = op.x or 0, op.w or 6
		if x - w / 2 > -length / 2 + 0.05 and x + w / 2 < length / 2 - 0.05 then
			table.insert(ops, op)
		end
	end
	table.sort(ops, function(a, b) return a.x < b.x end)

	-- 1. solid piers between/around the openings -- full height, no exceptions
	local cursor = -length / 2
	local function pier(x0, x1)
		local w = x1 - x0
		if w <= 0.02 then return end
		L.box(parent, name, cf * CFrame.new((x0 + x1) / 2, height / 2, 0), Vector3.new(w, height, thick), color, mat, o)
	end
	for _, op in ipairs(ops) do
		pier(cursor, op.x - (op.w or 6) / 2)
		cursor = op.x + (op.w or 6) / 2
	end
	pier(cursor, length / 2)

	-- 2. for each opening: the sill block below it and sliced masonry above its head
	for _, op in ipairs(ops) do
		local w = op.w or 6
		local sill = op.sill or 0
		local h = op.h or 8
		local rise = op.rise or 0
		if sill > 0.02 then
			L.box(parent, name .. "Sill", cf * CFrame.new(op.x, sill / 2, 0), Vector3.new(w, sill, thick), color, mat, o)
		end
		local headBase = sill + h
		local prof = rise > 0 and A.archProfile(w, rise) or nil
		local n = opts.slices or 14
		local sw = w / n
		for i = 0, n - 1 do
			local xs = -w / 2 + (i + 0.5) * sw
			local top = headBase + (prof and prof(xs) or 0)
			-- overlap each slice by a hair so adjacent slices cannot leave a seam
			local yTop = math.max(top, headBase)
			if height - yTop > 0.02 then
				L.box(parent, name .. "Head", cf * CFrame.new(op.x + xs, (yTop + height) / 2, 0),
					Vector3.new(sw + 0.06, height - yTop, thick), color, mat, o)
			end
		end
		-- a moulded arch ring on the outer face, purely decorative
		if rise > 0 and opts.voussoirs ~= false then
			-- 6 rather than 13: the moulded ring still reads at 6 segments and this runs
			-- on every arched opening in the world
			local ringN = 6
			local t = thick * 0.34
			for i = 0, ringN do
				local u = i / ringN
				local xs = -w / 2 + u * w
				local y = headBase + prof(xs)
				local xs2 = -w / 2 + math.min(u + 1 / ringN, 1) * w
				local y2 = headBase + prof(xs2)
				local a = Vector3.new(xs, y, 0)
				local b = Vector3.new(xs2, y2, 0)
				local mid = (a + b) / 2
				local ang = math.atan2(b.Y - a.Y, b.X - a.X)
				local len = (b - a).Magnitude
				if len > 0.05 then
					L.box(parent, name .. "Voussoir",
						cf * CFrame.new(op.x + mid.X, mid.Y, thick / 2 + t / 2 - 0.02) * CFrame.Angles(0, 0, ang),
						Vector3.new(len + 0.4, 1.1, t), opts.trimColor or color, mat, {shadow = false})
				end
			end
		end
	end
	return parent
end

-- Fills the space between a wall head (y=0 of this cf) and a roof profile.
-- cf: centre of the gable BASE, +X along the width, +Z the wall normal.
-- profile(x) -> height above the base at offset x.
function A.gableFill(parent, cf, width, thick, profile, color, mat, slices)
	slices = slices or 18
	local sw = width / slices
	for i = 0, slices - 1 do
		local x = -width / 2 + (i + 0.5) * sw
		local h = math.max(profile(x), 0)
		if h > 0.05 then
			L.box(parent, "Gable", cf * CFrame.new(x, h / 2, 0), Vector3.new(sw + 0.06, h, thick),
				color or L.C.ElvenStone, mat or L.M.Stone, {solid = true})
		end
	end
end

----------------------------------------------------------------------------------
-- ROOFS
----------------------------------------------------------------------------------
-- Straight pitched roof. cf = centre of the roof's BEARING plane (wall head level),
-- +X along the ridge, +Z across the span.
-- Emits: two slopes, a ridge beam, eaves fascia, and (unless openGable) both gables.
function A.roofPitched(parent, cf, ridgeLen, span, rise, opts)
	opts = opts or {}
	local color = opts.color or L.C.DarkStone
	local mat = opts.mat or L.M.Stone
	local th = opts.thick or 1.2
	local over = opts.overhang or 2.5

	-- THE EAVES MUST MEET THE WALL HEAD.
	-- The slope used to run from the ridge down to zero at (span/2 + overhang), which
	-- put it OVERHANG-worth of height above the bearing plane at the wall line -- a
	-- continuous ~5-stud slot around the whole building between wall top and roof
	-- underside. Rays fired from inside escaped through it. The slope now passes
	-- through zero exactly at span/2 and keeps descending through the overhang, so
	-- the roof underside is BELOW the wall head where they meet.
	local halfSpan = span / 2
	local ang = math.atan2(rise, halfSpan)
	local runTotal = halfSpan + over
	local slopeLen = runTotal / math.cos(ang)
	local endY = rise - math.tan(ang) * runTotal
	local L2 = ridgeLen + over * 2

	for _, s in ipairs({1, -1}) do
		L.box(parent, "RoofSlope",
			cf * CFrame.new(0, (rise + endY) / 2, s * runTotal / 2) * CFrame.Angles(s * ang, 0, 0),
			Vector3.new(L2, th, slopeLen + th), color, mat, {shadow = true, solid = true})
	end
	-- PLUG UNDER THE APEX. Two slope slabs meeting at a steep pitch leave a wedge of
	-- daylight directly under the ridge -- invisible on a shallow roof, a real hole at
	-- 67 degrees. The notch widens with the pitch, so the plug is sized from tan(ang).
	L.box(parent, "RidgePlug", cf * CFrame.new(0, rise - th * 0.85, 0),
		Vector3.new(L2, th * 2.4, th * 2 * math.tan(ang) + th * 2.2), color, mat, {solid = true})
	-- ridge
	L.box(parent, "Ridge", cf * CFrame.new(0, rise + th * 0.35, 0), Vector3.new(L2, th * 1.1, th * 2.4),
		opts.ridgeColor or L.C.GreyStone, mat, {shadow = false})
	-- eaves fascia on both long sides, so the roof edge reads as a built thing
	for _, s in ipairs({1, -1}) do
		L.box(parent, "Fascia", cf * CFrame.new(0, endY - th * 0.4, s * runTotal), Vector3.new(L2, th * 1.8, th * 0.7),
			opts.trimColor or L.C.BarkPale, mat, {shadow = false})
	end
	-- GABLES: the triangle under each end of the roof must be walled, or the roof
	-- is floating over an open hole. This is the bug this function exists to prevent.
	if not opts.openGable then
		-- matches the slope exactly: zero at the wall line, so gable and roof agree
		local prof = function(x)
			return math.max(0, rise * (1 - math.abs(x) / halfSpan))
		end
		for _, s in ipairs({1, -1}) do
			local gcf = cf * CFrame.new(s * ridgeLen / 2, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
			A.gableFill(parent, gcf, span, opts.gableThick or 1.6, prof,
				opts.gableColor or opts.wallColor or L.C.ElvenStone, opts.gableMat or mat)
		end
	end
end

-- Bell/ogee elven roof: stacked slope bands whose pitch steepens toward the ridge.
function A.roofCurved(parent, cf, ridgeLen, span, rise, opts)
	opts = opts or {}
	local color = opts.color or L.C.DarkStone
	local mat = opts.mat or L.M.Stone
	local th = opts.thick or 1.1
	local over = opts.overhang or 3
	local bands = opts.bands or 5
	local half = span / 2
	-- u is measured against the WALL LINE, so hAt(1) = 0 lands the roof exactly on the
	-- bearing plane and the overhang (u > 1) keeps dropping below it. Parameterising
	-- against half+over instead left a gap under the eaves the whole way round.
	local function hAt(u)
		-- ogee: steep at the top, flaring out at the eave
		return rise * (1 - u * u * (1.35 - 0.35 * u))
	end
	local uMax = (half + over) / half
	local L2 = ridgeLen + over * 2
	for b = 0, bands - 1 do
		local u0 = uMax * b / bands
		local u1 = uMax * (b + 1) / bands
		local z0 = u0 * half
		local z1 = u1 * half
		local y0, y1 = hAt(u0), hAt(u1)
		local seg = math.sqrt((z1 - z0) ^ 2 + (y0 - y1) ^ 2)
		local ang = math.atan2(y0 - y1, z1 - z0)
		for _, s in ipairs({1, -1}) do
			L.box(parent, "RoofBand",
				cf * CFrame.new(0, (y0 + y1) / 2, s * (z0 + z1) / 2) * CFrame.Angles(-s * ang, 0, 0),
				Vector3.new(L2, th, seg + th * 1.6), color, mat, {shadow = true, solid = true})
		end
	end
	-- same apex plug as the pitched roof; the topmost band is the steepest part of
	-- the ogee, so this is where a curved roof opens up if anywhere does
	local topAng = math.atan2(hAt(0) - hAt(uMax / bands), uMax / bands * half)
	L.box(parent, "RidgePlug", cf * CFrame.new(0, rise - th * 0.85, 0),
		Vector3.new(L2, th * 2.4, th * 2 * math.tan(topAng) + th * 2.4), color, mat, {solid = true})
	L.box(parent, "Ridge", cf * CFrame.new(0, rise + th * 0.4, 0), Vector3.new(L2, th * 1.2, th * 2.2),
		opts.ridgeColor or L.C.GreyStone, mat, {shadow = false})
	if not opts.openGable then
		local prof = function(x)
			return math.max(0, hAt(math.clamp(math.abs(x) / half, 0, 1)))
		end
		for _, s in ipairs({1, -1}) do
			local gcf = cf * CFrame.new(s * ridgeLen / 2, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
			A.gableFill(parent, gcf, span, opts.gableThick or 1.6, prof,
				opts.gableColor or opts.wallColor or L.C.ElvenStone, opts.gableMat or mat)
		end
	end
end

-- Conical / spire roof built from stacked frusta -- watertight by construction.
function A.spire(parent, baseCF, baseR, height, opts)
	opts = opts or {}
	local segs = opts.segs or 16
	local color = opts.color or L.C.DarkStone
	local mat = opts.mat or L.M.Stone
	local curve = opts.curve or 1.0   -- 1 = straight cone, >1 = concave (needle)
	for i = 0, segs - 1 do
		local u0 = i / segs
		local u1 = (i + 1) / segs
		local r0 = baseR * (1 - u0) ^ curve
		local r1 = baseR * (1 - u1) ^ curve
		local r = math.max((r0 + r1) / 2, 0.12)
		local h = height / segs
		L.post(parent, "SpireSeg", baseCF * CFrame.new(0, height * u0 + h / 2, 0), h + 0.05, r * 2, color, mat, {shadow = true})
	end
	if opts.finial ~= false then
		local fy = height
		L.ball(parent, "Finial", baseCF * CFrame.new(0, fy + 1.2, 0), 2.4, opts.finialColor or L.C.Gold, L.M.Foil, {shadow = false})
		L.post(parent, "FinialSpike", baseCF * CFrame.new(0, fy + 3.6, 0), 4.4, 0.5, opts.finialColor or L.C.Gold, L.M.Foil, {shadow = false})
	end
end

----------------------------------------------------------------------------------
-- COLUMNS, STAIRS, RAILS
----------------------------------------------------------------------------------
function A.column(parent, baseCF, height, dia, opts)
	opts = opts or {}
	local color = opts.color or L.C.ElvenStone
	local mat = opts.mat or L.M.Stone
	local baseH = opts.baseH or math.max(1.4, dia * 0.5)
	local capH = opts.capH or math.max(1.6, dia * 0.55)
	local shaft = height - baseH - capH
	L.box(parent, "ColBase", baseCF * CFrame.new(0, baseH / 2, 0), Vector3.new(dia * 1.5, baseH, dia * 1.5), color, mat, {solid = true})
	L.post(parent, "ColShaft", baseCF * CFrame.new(0, baseH + shaft / 2, 0), shaft, dia, color, mat, {solid = true})
	if opts.fluted then
		for i = 1, 8 do
			local a = math.rad(i * 45)
			L.post(parent, "Flute", baseCF * CFrame.new(math.cos(a) * dia * 0.5, baseH + shaft / 2, math.sin(a) * dia * 0.5),
				shaft, dia * 0.16, opts.trimColor or color, mat, {shadow = false})
		end
	end
	L.box(parent, "ColCap", baseCF * CFrame.new(0, baseH + shaft + capH / 2, 0), Vector3.new(dia * 1.7, capH, dia * 1.7), color, mat, {solid = true})
	L.box(parent, "ColAbacus", baseCF * CFrame.new(0, height + 0.35, 0), Vector3.new(dia * 2.0, 0.7, dia * 2.0), opts.trimColor or color, mat, {shadow = false})
	return height
end

-- Straight run of steps from a to b. Each step is a solid box that reaches DOWN to
-- `groundY` so no step ever floats.
function A.stairs(parent, a, b, width, opts)
	opts = opts or {}
	local color = opts.color or L.C.WeatheredStone
	local mat = opts.mat or L.M.Stone
	local riseTotal = b.Y - a.Y
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local run = flat.Magnitude
	local stepH = opts.stepH or 1.1
	local n = math.max(1, math.floor(math.abs(riseTotal) / stepH + 0.5))
	local dir = run > 0.01 and flat.Unit or Vector3.new(0, 0, 1)
	local yawCF = CFrame.lookAt(Vector3.new(0, 0, 0), dir)
	local stepRun = run / n
	local groundDrop = opts.drop or 6
	for i = 1, n do
		local t = (i - 0.5) / n
		local pos = a + flat * t
		local topY = a.Y + riseTotal * (i / n)
		local h = (topY - (a.Y - groundDrop))
		local cf = CFrame.new(Vector3.new(pos.X, topY - h / 2, pos.Z)) * (yawCF - yawCF.Position)
		L.box(parent, "Step", cf, Vector3.new(width, h, stepRun + 0.1), color, mat, {solid = true})
	end
	if opts.cheeks then
		for _, s in ipairs({1, -1}) do
			local off = (yawCF.RightVector) * (s * (width / 2 + 0.9))
			local mid = a + flat * 0.5 + off + Vector3.new(0, riseTotal / 2 - groundDrop / 2, 0)
			local h = math.abs(riseTotal) + groundDrop + 2
			local cf = CFrame.new(mid) * (yawCF - yawCF.Position)
			L.box(parent, "StairCheek", cf, Vector3.new(1.8, h, run), opts.cheekColor or color, mat, {solid = true})
		end
	end
	return n
end

-- Balustrade along a list of world points.
function A.railing(parent, pts, opts)
	opts = opts or {}
	local color = opts.color or L.C.WeatheredStone
	local mat = opts.mat or L.M.Stone
	local h = opts.height or 3.2
	local spacing = opts.spacing or 4.5
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local seg = (b - a)
		local len = seg.Magnitude
		local n = math.max(1, math.floor(len / spacing))
		for j = 0, n do
			local p = a + seg * (j / n)
			L.post(parent, "Baluster", CFrame.new(p + Vector3.new(0, h * 0.5, 0)), h * 0.86, opts.postDia or 0.85, color, mat, {shadow = false})
			L.box(parent, "BalusterFoot", CFrame.new(p + Vector3.new(0, 0.3, 0)), Vector3.new(1.5, 0.6, 1.5), color, mat, {shadow = false})
		end
		L.beam(parent, "Handrail", a + Vector3.new(0, h, 0), b + Vector3.new(0, h, 0), opts.railW or 1.5, 0.7, color, mat, {solid = true})
		L.beam(parent, "RailFoot", a + Vector3.new(0, 0.5, 0), b + Vector3.new(0, 0.5, 0), opts.railW or 1.6, 1.0, color, mat, {solid = true})
	end
end

----------------------------------------------------------------------------------
-- WINDOWS
----------------------------------------------------------------------------------
-- Fills a pointed opening with glowing glass + tracery. cf = centre of the opening's
-- springing line, matching the wall's opening (x, sill).
function A.traceryWindow(parent, cf, w, h, rise, opts)
	opts = opts or {}
	local glassColors = opts.colors or {L.C.GlowCyan, L.C.GlowGold, L.C.GlowPink, L.C.GlowGreen}
	local mullions = opts.mullions or 1
	local prof = A.archProfile(w, rise)
	local th = opts.thick or 0.5
	-- glass: sliced so it follows the arch exactly and never pokes through the stone
	local n = opts.slices or 6      -- glazing slices; 12 doubled the cost for no visible gain
	local sw = w / n
	for i = 0, n - 1 do
		local x = -w / 2 + (i + 0.5) * sw
		local top = prof(x)
		local gh = h + top
		local c = glassColors[((i + (opts.seed or 0)) % #glassColors) + 1]
		local pane = L.box(parent, "Glass", cf * CFrame.new(x, gh / 2, 0),
			Vector3.new(sw + 0.05, gh, th), c, L.M.Neon, {collide = false, shadow = false})
		pane.Transparency = opts.transparency or 0.25
	end
	local lightP = L.box(parent, "WindowGlow", cf * CFrame.new(0, h * 0.55, 0), Vector3.new(0.4, 0.4, 0.4), L.C.GlowGold, L.M.Neon, {collide = false, shadow = false})
	lightP.Transparency = 1
	L.light(lightP, opts.lightColor or L.C.GlowGold, opts.lightBrightness or 1.6, opts.lightRange or 24)
	-- mullions
	for i = 1, mullions do
		local x = -w / 2 + (w * i / (mullions + 1))
		local top = prof(x)
		L.box(parent, "Mullion", cf * CFrame.new(x, (h + top) / 2, 0), Vector3.new(0.55, h + top, th * 2.2),
			opts.stoneColor or L.C.WeatheredStone, L.M.Stone, {shadow = false})
	end
	L.box(parent, "Transom", cf * CFrame.new(0, h * 0.62, 0), Vector3.new(w, 0.5, th * 2.2), opts.stoneColor or L.C.WeatheredStone, L.M.Stone, {shadow = false})
end

return A
