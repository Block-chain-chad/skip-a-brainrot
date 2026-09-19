-- GardensCreature -- the ancient animal sculptures of the Verdant Court.
--
-- Built from ellipsoid blobs and tapered tubes rather than boxes: a stag made of
-- bricks reads as a pile of bricks, and these are meant to be the most impressive
-- objects in the hub. Every figure is posed on a plinth that carries its weight,
-- and C.weather() then breaks it up with moss and vines so it looks like it has
-- stood there for a thousand years.
--
-- All figures are built facing +X, standing on y = 0 of the given CFrame.

local L = require(script.Parent.Lib)
local P = require(script.Parent.Props)
local C = {}

local STONE = L.C.WeatheredStone
local MAT = Enum.Material.Slate

local function blob(m, name, cf, size, col, mat)
	return L.blob(m, name, cf, size, col or STONE, mat or MAT, {collide = false, shadow = true})
end
local function tube(m, name, a, b, d, col, mat)
	return L.tube(m, name, a, b, d, col or STONE, mat or MAT, {collide = false, shadow = true})
end

----------------------------------------------------------------------------------
-- PLINTH
----------------------------------------------------------------------------------
function C.pedestal(parent, base, w, d, h, opts)
	opts = opts or {}
	local col = opts.stone or L.C.GreyStone
	local m = parent
	-- stepped base
	L.box(m, "PlinthStep", CFrame.new(base + Vector3.new(0, 0.6, 0)), Vector3.new(w + 4, 1.2, d + 4), col, MAT, {solid = true})
	L.box(m, "PlinthStep", CFrame.new(base + Vector3.new(0, 1.8, 0)), Vector3.new(w + 2.4, 1.2, d + 2.4), col, MAT, {solid = true})
	-- die
	L.box(m, "PlinthDie", CFrame.new(base + Vector3.new(0, 2.4 + h / 2, 0)), Vector3.new(w, h, d), col, MAT, {solid = true})
	-- cornice and cap
	L.box(m, "PlinthCornice", CFrame.new(base + Vector3.new(0, 2.4 + h + 0.5, 0)), Vector3.new(w + 2.0, 1.0, d + 2.0), opts.trim or L.C.PaleStone, MAT, {solid = true})
	L.box(m, "PlinthCap", CFrame.new(base + Vector3.new(0, 2.4 + h + 1.3, 0)), Vector3.new(w + 1.2, 0.7, d + 1.2), opts.trim or L.C.PaleStone, MAT, {shadow = false})
	-- carved panels on all four faces
	for i = 0, 3 do
		local a = math.rad(i * 90)
		local off = (i % 2 == 0) and d or w
		P.carving(m, CFrame.new(base + Vector3.new(math.sin(a) * (off / 2 + 0.3), 2.4 + h / 2, math.cos(a) * (off / 2 + 0.3)))
			* CFrame.Angles(0, a, 0), (i % 2 == 0) and w * 0.6 or d * 0.6, h * 0.62,
			{stone = col, glow = opts.glow or L.C.GlowCyan, seed = (opts.seed or 1) + i})
	end
	return base.Y + 2.4 + h + 1.65   -- top surface Y
end

----------------------------------------------------------------------------------
-- QUADRUPEDS
----------------------------------------------------------------------------------
-- opts.style: "stag" | "wolf" | "cat" | "doe" | "elk"
function C.quadruped(parent, cf, scale, opts)
	opts = opts or {}
	local s = scale or 1
	local style = opts.style or "stag"
	local rng = Random.new(opts.seed or 7)
	local m = Instance.new("Model")
	m.Name = opts.name or (style:sub(1, 1):upper() .. style:sub(2) .. "Statue")
	m.Parent = parent
	local col = opts.stone or STONE

	-- proportions per style
	local prof = ({
		stag = {bl = 15, sh = 15, bw = 6.0, leg = 1.35, neck = 9.0, neckAng = 62, headL = 4.6, tail = 3.0, ears = true, antlers = true},
		elk  = {bl = 17, sh = 16, bw = 7.2, leg = 1.6,  neck = 9.5, neckAng = 55, headL = 5.4, tail = 2.6, ears = true, antlers = true, mane = true},
		doe  = {bl = 13, sh = 13, bw = 5.4, leg = 1.2,  neck = 8.0, neckAng = 66, headL = 4.0, tail = 2.6, ears = true},
		wolf = {bl = 15, sh = 11, bw = 5.6, leg = 1.5,  neck = 5.4, neckAng = 34, headL = 5.2, tail = 8.0, ears = true, mane = true, muzzle = true},
		cat  = {bl = 14, sh = 10, bw = 5.0, leg = 1.4,  neck = 4.6, neckAng = 30, headL = 4.0, tail = 11.0, ears = true, round = true},
	})[style] or {bl = 15, sh = 14, bw = 6, leg = 1.4, neck = 8, neckAng = 60, headL = 4.6, tail = 3, ears = true}

	local BL, SH, BW = prof.bl * s, prof.sh * s, prof.bw * s
	local bodyY = SH

	-- ===== body: a tapered barrel of overlapping ellipsoids along the spine =====
	local segs = 7
	for i = 0, segs do
		local t = i / segs
		local x = L.lerp(BL * 0.42, -BL * 0.46, t)
		-- chest deep at the front, narrower at the waist, swelling again at the haunch
		local girth = (1 - 0.34 * math.abs(t - 0.42) * 2) * (t > 0.72 and 1.08 or 1)
		local sag = math.sin(t * math.pi) * 0.5 * s
		blob(m, "Body", cf * CFrame.new(x, bodyY - sag, 0),
			Vector3.new(BL / segs * 2.1, BW * girth * 0.95, BW * girth), col)
	end
	-- shoulder and haunch masses
	blob(m, "Shoulder", cf * CFrame.new(BL * 0.30, bodyY + 0.5 * s, 0), Vector3.new(BW * 1.15, BW * 1.05, BW * 1.02), col)
	blob(m, "Haunch", cf * CFrame.new(-BL * 0.34, bodyY + 0.3 * s, 0), Vector3.new(BW * 1.25, BW * 1.15, BW * 1.06), col)

	-- ===== legs: thigh, shank, and a hoof/paw that reaches the ground =====
	local legR = prof.leg * s
	local function leg(fx, fz, front)
		local hipY = bodyY - BW * 0.25
		local hip = (cf * CFrame.new(fx, hipY, fz)).Position
		-- knee kicks forward on the front legs and back on the rear, as in a real animal
		local kneeX = fx + (front and 0.7 or -1.1) * s
		local knee = (cf * CFrame.new(kneeX, hipY * 0.52, fz * 1.02)).Position
		local footX = fx + (front and 0.2 or 0.5) * s
		local foot = (cf * CFrame.new(footX, legR * 0.9, fz * 1.04)).Position
		-- slimmer than the first pass: at 2.3x the thigh was half the body's width and
		-- the animals read as standing on tree trunks
		tube(m, "Thigh", hip, knee, legR * 1.85, col)
		tube(m, "Shank", knee, foot, legR * 1.20, col)
		blob(m, "Knee", CFrame.new(knee), Vector3.new(legR * 1.9, legR * 1.9, legR * 1.9), col)
		if style == "wolf" or style == "cat" then
			blob(m, "Paw", CFrame.new(foot - Vector3.new(0, legR * 0.5, 0)),
				Vector3.new(legR * 3.0, legR * 1.5, legR * 2.4), col)
		else
			L.post(m, "Hoof", CFrame.new(foot - Vector3.new(0, legR * 0.45, 0)), legR * 1.5, legR * 2.1, col, MAT, {shadow = false})
		end
	end
	leg(BL * 0.30, BW * 0.40, true)
	leg(BL * 0.30, -BW * 0.40, true)
	leg(-BL * 0.34, BW * 0.42, false)
	leg(-BL * 0.34, -BW * 0.42, false)

	-- ===== neck and head =====
	local neckLen = prof.neck * s
	local na = math.rad(prof.neckAng)
	local neckBase = cf * CFrame.new(BL * 0.40, bodyY + BW * 0.30, 0)
	local nsegs = 5
	local prev = neckBase.Position
	for i = 1, nsegs do
		local t = i / nsegs
		local p = (neckBase * CFrame.new(math.cos(na) * neckLen * t, math.sin(na) * neckLen * t, 0)).Position
		local r = L.lerp(BW * 0.52, BW * 0.30, t)
		tube(m, "Neck", prev, p, r, col)
		blob(m, "NeckSeg", CFrame.new(p), Vector3.new(r * 1.05, r * 1.05, r * 1.05), col)
		prev = p
	end
	local headBase = prev
	local headL = prof.headL * s
	local headDir = Vector3.new(math.cos(na - math.rad(prof.headTilt or 42)), math.sin(na - math.rad(prof.headTilt or 42)), 0)
	headDir = (cf:VectorToWorldSpace(headDir)).Unit
	local headMid = headBase + headDir * headL * 0.44
	blob(m, "Skull", CFrame.new(headMid), Vector3.new(headL * 1.05, headL * 0.68, headL * 0.62), col)
	local muzzleEnd = headBase + headDir * headL * 1.02
	blob(m, "Muzzle", CFrame.new(headBase + headDir * headL * 0.82),
		Vector3.new(headL * 0.72, headL * 0.42, headL * 0.40), col)
	L.ball(m, "Nose", CFrame.new(muzzleEnd), headL * 0.24, opts.dark or L.C.DarkStone, MAT, {collide = false, shadow = false})

	-- eyes
	local side = cf:VectorToWorldSpace(Vector3.new(0, 0, 1))
	for _, sg in ipairs({1, -1}) do
		local ep = headMid + side * (headL * 0.26 * sg) + headDir * headL * 0.16 + Vector3.new(0, headL * 0.10, 0)
		if opts.eyeGlow then
			L.glow(m, "Eye", CFrame.new(ep), Vector3.new(headL * 0.16, headL * 0.16, headL * 0.16), opts.eyeGlow, 1.1, 12, "ball")
		else
			L.ball(m, "Eye", CFrame.new(ep), headL * 0.17, opts.dark or L.C.DarkStone, MAT, {collide = false, shadow = false})
		end
	end
	-- ears
	if prof.ears then
		for _, sg in ipairs({1, -1}) do
			local ep = headMid + side * (headL * 0.30 * sg) - headDir * headL * 0.22 + Vector3.new(0, headL * 0.42, 0)
			blob(m, "Ear", CFrame.new(ep) * CFrame.Angles(0, 0, sg * 0.3),
				Vector3.new(headL * 0.22, headL * 0.62, headL * 0.36), col)
		end
	end
	-- mane
	if prof.mane then
		for i = 1, 7 do
			local t = i / 8
			local p = neckBase.Position + (headBase - neckBase.Position) * t + Vector3.new(0, BW * 0.30, 0)
			blob(m, "Mane", CFrame.new(p) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.3, 0.3), 0),
				Vector3.new(BW * 0.5, BW * 0.62, BW * 0.72), col)
		end
	end

	-- ===== antlers =====
	if prof.antlers and opts.antlers ~= false then
		for _, sg in ipairs({1, -1}) do
			local root = headMid + side * (headL * 0.24 * sg) - headDir * headL * 0.3 + Vector3.new(0, headL * 0.48, 0)
			local up = Vector3.new(0, 1, 0)
			local outw = side * sg
			-- SHORTER, THICKER, MORE BRANCHED. The first version swept 11 studs straight
			-- up on a 0.6-stud beam, which read as two bare twigs rather than antlers.
			-- Real antlers are broad and forward-sweeping, not tall and thin.
			local beam = {root}
			local n = 5
			for i = 1, n do
				local t = i / n
				beam[#beam + 1] = root + up * (5.2 * s * t) + outw * (4.4 * s * t * t)
					+ headDir * (2.6 * s * math.sin(t * 2.0))
			end
			P.root(m, beam, 0.95 * s, 0.34 * s, {color = col, mat = MAT, name = "AntlerBeam", steps = 14, collide = false})
			-- tines: six per side, sweeping up and forward off the main beam
			for k = 1, 6 do
				local t = 0.16 + k * 0.135
				local at = L.spline(beam, math.min(t, 0.98))
				local tip = at + up * (2.9 * s * (1 - k * 0.07)) + outw * (1.2 * s)
					+ headDir * (2.9 * s - k * 0.55 * s)
				tube(m, "Tine", at, tip, 0.58 * s, col)
				L.ball(m, "TineTip", CFrame.new(tip), 0.55 * s, col, MAT, {collide = false, shadow = false})
			end
		end
	end

	-- ===== tail =====
	local tailLen = prof.tail * s
	local tbase = cf * CFrame.new(-BL * 0.48, bodyY + BW * 0.28, 0)
	if style == "cat" or style == "wolf" then
		local pts = {tbase.Position}
		for i = 1, 4 do
			local t = i / 4
			pts[#pts + 1] = (tbase * CFrame.new(-tailLen * t * 0.8, tailLen * (style == "cat" and 0.55 or 0.12) * math.sin(t * 2.2), 0)).Position
		end
		P.root(m, pts, BW * 0.20, BW * 0.10, {color = col, mat = MAT, name = "Tail", steps = 12, collide = false})
	else
		blob(m, "Tail", tbase * CFrame.new(-tailLen * 0.4, -tailLen * 0.2, 0),
			Vector3.new(tailLen, tailLen * 0.7, tailLen * 0.5), col)
	end
	return m
end

----------------------------------------------------------------------------------
-- OWL
----------------------------------------------------------------------------------
function C.owl(parent, cf, scale, opts)
	opts = opts or {}
	local s = scale or 1
	local col = opts.stone or STONE
	local m = Instance.new("Model")
	m.Name = opts.name or "OwlStatue"
	m.Parent = parent
	local bodyH = 13 * s
	-- body: a rounded upright cone of stacked ellipsoids
	for i = 0, 6 do
		local t = i / 6
		local w = L.lerp(7.4, 5.2, t) * s * (1 - 0.18 * t * t)
		blob(m, "OwlBody", cf * CFrame.new(0, bodyH * 0.30 + bodyH * 0.62 * t, 0),
			Vector3.new(w, bodyH * 0.26, w * 0.92), col)
	end
	-- head, set low into the shoulders as an owl's is
	local headY = bodyH * 1.02
	blob(m, "OwlHead", cf * CFrame.new(0, headY, 0), Vector3.new(7.6 * s, 6.6 * s, 7.0 * s), col)
	-- facial disc
	blob(m, "OwlFace", cf * CFrame.new(1.9 * s, headY - 0.2 * s, 0), Vector3.new(3.2 * s, 5.6 * s, 6.2 * s), opts.trim or L.C.PaleStone)
	for _, sg in ipairs({1, -1}) do
		local eye = cf * CFrame.new(3.0 * s, headY + 0.6 * s, sg * 1.7 * s)
		L.ball(m, "OwlEyeRing", eye, 2.5 * s, col, MAT, {collide = false, shadow = false})
		if opts.eyeGlow then
			L.glow(m, "OwlEye", eye * CFrame.new(0.5 * s, 0, 0), Vector3.new(1.7 * s, 1.7 * s, 1.7 * s), opts.eyeGlow, 1.6, 18, "ball")
		else
			L.ball(m, "OwlEye", eye * CFrame.new(0.5 * s, 0, 0), 1.7 * s, opts.dark or L.C.DarkStone, MAT, {collide = false, shadow = false})
		end
		-- ear tufts
		blob(m, "OwlTuft", cf * CFrame.new(-0.4 * s, headY + 3.6 * s, sg * 2.4 * s) * CFrame.Angles(sg * 0.35, 0, 0),
			Vector3.new(2.0 * s, 4.2 * s, 1.6 * s), col)
	end
	L.post(m, "OwlBeak", cf * CFrame.new(4.2 * s, headY - 0.6 * s, 0) * CFrame.Angles(0, 0, math.rad(-90)), 2.2 * s, 1.5 * s, opts.trim or L.C.PaleStone, MAT, {shadow = false})
	-- folded wings
	for _, sg in ipairs({1, -1}) do
		for k = 0, 3 do
			blob(m, "OwlWing", cf * CFrame.new(-0.6 * s + k * 0.3 * s, bodyH * (0.78 - k * 0.14), sg * (3.4 - k * 0.15) * s)
				* CFrame.Angles(sg * 0.12, 0, 0),
				Vector3.new(6.0 * s, bodyH * 0.30, 1.5 * s), col)
		end
	end
	-- talons gripping the plinth
	for _, sg in ipairs({1, -1}) do
		for k = -1, 1 do
			local toe = cf * CFrame.new(1.6 * s + k * 0.9 * s, 0.7 * s, sg * 2.2 * s + k * 0.5 * s)
			tube(m, "Talon", (cf * CFrame.new(0.4 * s, 2.2 * s, sg * 2.0 * s)).Position, toe.Position, 1.0 * s, col)
			L.ball(m, "TalonTip", toe, 1.0 * s, col, MAT, {collide = false, shadow = false})
		end
	end
	return m
end

----------------------------------------------------------------------------------
-- GREAT BIRD (wings spread)
----------------------------------------------------------------------------------
function C.greatBird(parent, cf, scale, opts)
	opts = opts or {}
	local s = scale or 1
	local col = opts.stone or STONE
	local m = Instance.new("Model")
	m.Name = opts.name or "GreatBirdStatue"
	m.Parent = parent
	local bodyY = 9 * s
	for i = 0, 5 do
		local t = i / 5
		blob(m, "BirdBody", cf * CFrame.new(L.lerp(4, -6, t) * s, bodyY + math.sin(t * 3.14) * 0.6 * s, 0),
			Vector3.new(4.2 * s, L.lerp(5.4, 3.0, t) * s, L.lerp(5.0, 3.0, t) * s), col)
	end
	-- neck + head
	local hp = cf * CFrame.new(7.4 * s, bodyY + 5.2 * s, 0)
	tube(m, "BirdNeck", (cf * CFrame.new(4.2 * s, bodyY + 1.4 * s, 0)).Position, hp.Position, 2.6 * s, col)
	blob(m, "BirdHead", hp, Vector3.new(4.4 * s, 3.4 * s, 3.2 * s), col)
	L.post(m, "BirdBeak", hp * CFrame.new(2.8 * s, -0.3 * s, 0) * CFrame.Angles(0, 0, math.rad(-90)), 3.4 * s, 1.5 * s, opts.trim or L.C.PaleStone, MAT, {shadow = false})
	-- spread wings, feathered in overlapping vanes
	for _, sg in ipairs({1, -1}) do
		local shoulder = (cf * CFrame.new(2.0 * s, bodyY + 3.0 * s, sg * 2.0 * s)).Position
		local elbow = (cf * CFrame.new(-1.0 * s, bodyY + 9.5 * s, sg * 9.0 * s)).Position
		local tip = (cf * CFrame.new(-4.5 * s, bodyY + 12.0 * s, sg * 20.0 * s)).Position
		tube(m, "WingBone", shoulder, elbow, 2.4 * s, col)
		tube(m, "WingBone", elbow, tip, 1.6 * s, col)
		for k = 0, 8 do
			local t = k / 8
			local along = shoulder:Lerp(elbow, t)
			local along2 = elbow:Lerp(tip, t)
			local a = (t < 1) and along or along
			local featherLen = (7.0 - 3.0 * t) * s
			local back = cf:VectorToWorldSpace(Vector3.new(-1, -0.25, 0)).Unit
			tube(m, "Feather", a, a + back * featherLen, 1.5 * s, col)
			tube(m, "Feather", along2, along2 + back * (featherLen * 1.25), 1.3 * s, col)
		end
	end
	-- tail fan
	for k = -3, 3 do
		local base = (cf * CFrame.new(-6.0 * s, bodyY - 0.5 * s, 0)).Position
		local dir = cf:VectorToWorldSpace(Vector3.new(-1, -0.12, k * 0.16)).Unit
		tube(m, "TailFeather", base, base + dir * 10 * s, 1.5 * s, col)
	end
	-- legs
	for _, sg in ipairs({1, -1}) do
		local hip = (cf * CFrame.new(-0.5 * s, bodyY - 2.6 * s, sg * 1.8 * s)).Position
		local foot = (cf * CFrame.new(0.6 * s, 0.8 * s, sg * 2.2 * s)).Position
		tube(m, "BirdLeg", hip, foot, 2.0 * s, col)
		for k = -1, 1 do
			local toe = (cf * CFrame.new(2.4 * s + k * 0.4 * s, 0.5 * s, sg * 2.2 * s + k * 1.0 * s)).Position
			tube(m, "BirdToe", foot, toe, 0.9 * s, col)
		end
	end
	return m
end

----------------------------------------------------------------------------------
-- DRAGON (coiled, wings raised)
----------------------------------------------------------------------------------
function C.dragon(parent, cf, scale, opts)
	opts = opts or {}
	local s = scale or 1
	local col = opts.stone or STONE
	local m = Instance.new("Model")
	m.Name = opts.name or "DragonStatue"
	m.Parent = parent
	-- serpentine body coiling up and around
	local pts = {}
	local turns = 1.55
	local n = 9
	for i = 0, n do
		local t = i / n
		local a = t * turns * math.pi * 2
		local r = (13 - 7 * t) * s
		pts[#pts + 1] = (cf * CFrame.new(math.cos(a) * r, 2.2 * s + 13 * s * t, math.sin(a) * r)).Position
	end
	local prev, prevR
	for i = 0, 44 do
		local u = i / 44
		local p = L.spline(pts, u)
		local r = L.lerp(3.4, 1.5, u) * s
		if prev then
			tube(m, "DragonBody", prev, p, r * 2, col)
			blob(m, "DragonSeg", CFrame.new(p), Vector3.new(r * 2.1, r * 2.1, r * 2.1), col)
			-- dorsal spines
			if i % 3 == 0 then
				local up = Vector3.new(0, 1, 0)
				local dir = (p - prev).Unit
				local sideV = dir:Cross(up)
				sideV = sideV.Magnitude > 0.05 and sideV.Unit or Vector3.new(1, 0, 0)
				local spineUp = sideV:Cross(dir).Unit
				tube(m, "Spine", p, p + spineUp * r * 2.4, r * 0.6, opts.trim or L.C.PaleStone)
			end
		end
		prev, prevR = p, r
	end
	-- head at the top of the coil
	local hp = L.spline(pts, 1) + Vector3.new(0, 2.5 * s, 0)
	blob(m, "DragonSkull", CFrame.new(hp), Vector3.new(6.4 * s, 3.6 * s, 3.6 * s), col)
	blob(m, "DragonJaw", CFrame.new(hp + Vector3.new(2.4 * s, -1.2 * s, 0)), Vector3.new(4.6 * s, 1.8 * s, 2.6 * s), col)
	for _, sg in ipairs({1, -1}) do
		-- horns sweeping back
		local hb = hp + Vector3.new(-1.4 * s, 1.4 * s, sg * 1.3 * s)
		tube(m, "Horn", hb, hb + Vector3.new(-4.6 * s, 3.2 * s, sg * 1.8 * s), 1.1 * s, opts.trim or L.C.PaleStone)
		if opts.eyeGlow then
			L.glow(m, "DragonEye", CFrame.new(hp + Vector3.new(1.7 * s, 0.7 * s, sg * 1.5 * s)),
				Vector3.new(1.0 * s, 1.0 * s, 1.0 * s), opts.eyeGlow, 1.8, 16, "ball")
		else
			L.ball(m, "DragonEye", CFrame.new(hp + Vector3.new(1.7 * s, 0.7 * s, sg * 1.5 * s)), 1.0 * s, L.C.DarkStone, MAT, {collide = false, shadow = false})
		end
		-- wings, membrane spanned between ribs
		local sh = L.spline(pts, 0.74)
		local elbow = sh + Vector3.new(-3 * s, 11 * s, sg * 7 * s)
		local tip = sh + Vector3.new(-7 * s, 17 * s, sg * 17 * s)
		tube(m, "WingArm", sh, elbow, 2.0 * s, col)
		tube(m, "WingArm", elbow, tip, 1.4 * s, col)
		for k = 1, 4 do
			local t = k / 4
			local rib = elbow:Lerp(tip, t * 0.9)
			local down = sh:Lerp(rib, 0.15) + Vector3.new(0, -4 * s * t, 0)
			tube(m, "WingRib", rib, down, 0.9 * s, col)
			-- membrane panel
			local mid = (rib + down) / 2
			local len = (rib - down).Magnitude
			local mcf = CFrame.lookAt(mid, rib)
			L.box(m, "Membrane", mcf, Vector3.new(6.5 * s * (1 - t * 0.3), 0.35 * s, len), col, MAT, {collide = false, shadow = false})
		end
	end
	return m
end

----------------------------------------------------------------------------------
-- WEATHERING
----------------------------------------------------------------------------------
-- Moss patches, chipped stone and hanging vines. Applied AFTER the figure is built
-- so it can react to the actual geometry rather than being designed in.
function C.weather(model, opts)
	opts = opts or {}
	local rng = Random.new(opts.seed or 13)
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Moss" and d.Name ~= "Vine" then parts[#parts + 1] = d end
	end
	if #parts == 0 then return end
	local amount = opts.amount or 0.30
	local cf, size = model:GetBoundingBox()
	local topY = cf.Position.Y + size.Y / 2
	for _, p in ipairs(parts) do
		if rng:NextNumber() < amount then
			-- moss sits on upward faces, which is where it would actually grow
			local m = L.blob(model, "Moss",
				p.CFrame * CFrame.new(rng:NextNumber(-0.2, 0.2) * p.Size.X, p.Size.Y * 0.34, rng:NextNumber(-0.2, 0.2) * p.Size.Z),
				Vector3.new(p.Size.X * rng:NextNumber(0.5, 0.95), p.Size.Y * 0.30, p.Size.Z * rng:NextNumber(0.5, 0.95)),
				rng:NextNumber() < 0.3 and L.C.Lichen or L.C.Moss, Enum.Material.Grass,
				{collide = false, shadow = false})
			m.Transparency = rng:NextNumber(0, 0.15)
		end
	end
	-- vines trailing off the highest parts
	local high = {}
	for _, p in ipairs(parts) do
		if p.Position.Y > topY - size.Y * 0.45 then high[#high + 1] = p end
	end
	for i = 1, (opts.vines or 4) do
		if #high > 0 then
			local p = high[rng:NextInteger(1, #high)]
			P.vine(model, p.Position + Vector3.new(rng:NextNumber(-2, 2), -1, rng:NextNumber(-2, 2)),
				rng:NextNumber(8, 22), {seed = rng:NextInteger(1, 9999), thick = 0.4,
				glow = rng:NextNumber() < 0.35 and L.C.GlowGreen or nil})
		end
	end
end

return C
