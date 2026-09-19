-- GardensFlora -- the living layer: trees, mushrooms, ferns, blooms, crystals.
--
-- These are PROTOTYPE builders. A big tree is ~80 parts, so the scatter pass builds
-- a handful of variants once and clones them, rather than generating thousands of
-- unique trees and drowning the place in instances.
--
-- Palette follows the reference image: deep green foliage, pale yellow-green
-- highlights, and hot pink blooms as the accent -- never neon across the board.

local L = require(script.Parent.Lib)
local P = require(script.Parent.Props)
local Fl = {}

local function jc(c, rng, a) return P.jitterCol(c, rng, a or 16) end

----------------------------------------------------------------------------------
-- TREES
----------------------------------------------------------------------------------
-- A canopy cluster: overlapping ellipsoids, darker underneath, paler on top.
local function canopy(m, centre, r, rng, opts)
	-- fewer, bigger blobs: at 7 per branch tip a single tree carried 60 canopy parts
	local n = opts.blobs or 4
	for i = 1, n do
		local a = rng:NextNumber(0, 6.283)
		local rr = rng:NextNumber(0, r * 0.62)
		local p = centre + Vector3.new(math.cos(a) * rr, rng:NextNumber(-r * 0.25, r * 0.35), math.sin(a) * rr)
		local sz = rng:NextNumber(r * 0.66, r * 1.15)
		local up = (p.Y - centre.Y) / math.max(r, 1)
		local col = up > 0.15 and (opts.leafPale or L.C.LeafPale) or (opts.leaf or L.C.Leaf)
		L.blob(m, "Leaves", CFrame.new(p) * CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 6), 0),
			Vector3.new(sz, sz * rng:NextNumber(0.55, 0.8), sz * rng:NextNumber(0.85, 1.1)),
			jc(col, rng, 18), Enum.Material.Grass, {collide = false, shadow = true})
	end
	-- blossoms
	if opts.bloom then
		for i = 1, (opts.blooms or 3) do
			local a = rng:NextNumber(0, 6.283)
			local rr = rng:NextNumber(r * 0.3, r * 0.95)
			local p = centre + Vector3.new(math.cos(a) * rr, rng:NextNumber(-r * 0.3, r * 0.4), math.sin(a) * rr)
			L.glow(m, "Blossom", CFrame.new(p), Vector3.new(2.0, 1.4, 2.0), opts.bloom, 0.8, 14, "blob")
		end
	end
end

-- A fantasy tree: flared roots, a curving tapered trunk, forked branches, and
-- canopy clusters that actually sit on the branch tips.
function Fl.tree(parent, base, opts)
	opts = opts or {}
	local rng = Random.new(opts.seed or 5)
	local m = Instance.new("Model")
	m.Name = opts.name or "Tree"
	m.Parent = parent
	local h = opts.height or rng:NextNumber(46, 74)
	local r0 = opts.trunkR or h * 0.045
	local bark = opts.bark or L.C.Bark
	local mat = Enum.Material.Wood

	-- root flare
	for i = 1, (opts.roots or 3) do
		local a = rng:NextNumber(0, 6.283)
		local len = r0 * rng:NextNumber(3.2, 6.0)
		local tip = base + Vector3.new(math.cos(a) * len, -1.5, math.sin(a) * len)
		P.root(m, {base + Vector3.new(0, r0 * 2.2, 0), base + Vector3.new(math.cos(a) * len * 0.45, r0 * 0.7, math.sin(a) * len * 0.45), tip},
			r0 * 0.62, r0 * 0.18, {color = jc(bark, rng, 10), mat = mat, steps = 2, name = "TreeRoot", collide = false})
	end

	-- trunk: a spline that leans and curves rather than a straight pole
	local lean = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * h * 0.10
	local pts = {base}
	local segs = 4
	for i = 1, segs do
		local t = i / segs
		pts[#pts + 1] = base + Vector3.new(0, h * 0.72 * t, 0) + lean * (t * t)
			+ Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * h * 0.03
	end
	P.root(m, pts, r0, r0 * 0.42, {color = bark, mat = mat, steps = 5, name = "Trunk", taperPow = 0.85})

	-- branches off the upper trunk
	local nb = opts.branches or rng:NextInteger(4, 6)
	local tips = {}
	for i = 1, nb do
		local t = rng:NextNumber(0.45, 0.98)
		local from = L.spline(pts, t)
		local a = (i / nb) * 6.283 + rng:NextNumber(-0.4, 0.4)
		local blen = h * rng:NextNumber(0.20, 0.40) * (1.15 - t * 0.4)
		local rise = blen * rng:NextNumber(0.45, 0.95)
		local mid = from + Vector3.new(math.cos(a) * blen * 0.5, rise * 0.55, math.sin(a) * blen * 0.5)
		local tip = from + Vector3.new(math.cos(a) * blen, rise, math.sin(a) * blen)
		P.root(m, {from, mid, tip}, r0 * 0.40, r0 * 0.13,
			{color = jc(bark, rng, 8), mat = mat, steps = 3, name = "Branch", collide = false})
		tips[#tips + 1] = tip
		-- a fork on some branches
		if rng:NextNumber() < 0.3 then
			local a2 = a + rng:NextNumber(-1.1, 1.1)
			local t2 = mid + Vector3.new(math.cos(a2) * blen * 0.55, rise * 0.5, math.sin(a2) * blen * 0.55)
			P.root(m, {mid, (mid + t2) / 2 + Vector3.new(0, 2, 0), t2}, r0 * 0.24, r0 * 0.09,
				{color = jc(bark, rng, 8), mat = mat, steps = 2, name = "Branch", collide = false})
			tips[#tips + 1] = t2
		end
	end

	-- canopy on the tips, plus a crown over the trunk top
	local cr = opts.canopyR or h * 0.20
	for _, tp in ipairs(tips) do
		canopy(m, tp, cr * rng:NextNumber(0.75, 1.15), rng, opts)
	end
	canopy(m, L.spline(pts, 1) + Vector3.new(0, cr * 0.5, 0), cr * 1.25, rng, opts)

	-- hanging vines from the canopy, as in the reference image
	for i = 1, (opts.vines or 2) do
		if #tips > 0 then
			local tp = tips[rng:NextInteger(1, #tips)]
			P.vine(m, tp + Vector3.new(rng:NextNumber(-3, 3), -cr * 0.4, rng:NextNumber(-3, 3)),
				rng:NextNumber(10, 30), {seed = rng:NextInteger(1, 9999),
				leafColor = opts.leaf or L.C.Leaf,
				glow = (opts.bloom and rng:NextNumber() < 0.4) and opts.bloom or nil})
		end
	end
	return m
end

----------------------------------------------------------------------------------
-- THE HANGING BLOOM -- the reference image's big pink lotus, opened downward
----------------------------------------------------------------------------------
function Fl.hangingBloom(parent, anchor, opts)
	opts = opts or {}
	local rng = Random.new(opts.seed or 3)
	local m = Instance.new("Model")
	m.Name = opts.name or "HangingBloom"
	m.Parent = parent
	local s = opts.scale or 1
	local stemLen = opts.stem or rng:NextNumber(10, 26)
	local head = anchor - Vector3.new(0, stemLen, 0)
	-- stem
	P.root(m, {anchor, anchor - Vector3.new(0, stemLen * 0.55, 0) + Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2)), head},
		0.9 * s, 0.6 * s, {color = opts.stemColor or L.C.DeepMoss, mat = Enum.Material.Grass, steps = 7, name = "BloomStem", collide = false})
	-- calyx
	L.blob(m, "Calyx", CFrame.new(head + Vector3.new(0, 1.2 * s, 0)), Vector3.new(5 * s, 3.4 * s, 5 * s),
		opts.stemColor or L.C.DeepMoss, Enum.Material.Grass, {collide = false, shadow = false})
	-- petals: two rings, opening downward and outward
	local petal = opts.petal or L.C.Petal
	for ring = 1, 2 do
		local n = ring == 1 and 6 or 7
		local rr = ring == 1 and 4.6 or 7.0
		local drop = ring == 1 and 2.2 or 4.2
		for i = 0, n - 1 do
			local a = math.rad(i * 360 / n + ring * 26)
			local p = head + Vector3.new(math.cos(a) * rr * s, -drop * s, math.sin(a) * rr * s)
			L.blob(m, "Petal", CFrame.new(p) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, math.rad(38 + ring * 16)),
				Vector3.new(3.2 * s, 1.0 * s, 8.0 * s),
				ring == 1 and petal or (opts.petalPale or L.C.PetalPale),
				Enum.Material.Grass, {collide = false, shadow = false})
		end
	end
	-- glowing heart
	L.glow(m, "BloomHeart", CFrame.new(head - Vector3.new(0, 2.6 * s, 0)), Vector3.new(3.4 * s, 2.6 * s, 3.4 * s),
		opts.glow or L.C.GlowPink, opts.brightness or 1.8, 26 * s, "blob")
	return m
end

----------------------------------------------------------------------------------
-- MUSHROOMS
----------------------------------------------------------------------------------
function Fl.giantMushroom(parent, base, opts)
	opts = opts or {}
	local rng = Random.new(opts.seed or 17)
	local m = Instance.new("Model")
	m.Name = opts.name or "GiantMushroom"
	m.Parent = parent
	local h = opts.height or rng:NextNumber(18, 52)
	local capR = opts.capR or h * rng:NextNumber(0.34, 0.52)
	local stalkR = h * 0.075
	-- stalk, bulging at the base and leaning slightly
	local lean = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * h * 0.07
	local pts = {base, base + Vector3.new(0, h * 0.35, 0) + lean * 0.4, base + Vector3.new(0, h * 0.75, 0) + lean * 0.85, base + Vector3.new(0, h, 0) + lean}
	P.root(m, pts, stalkR * 1.5, stalkR, {color = opts.stalk or L.C.PaleStone, mat = Enum.Material.Sand, steps = 4, name = "Stalk"})
	local top = base + Vector3.new(0, h, 0) + lean
	-- cap: a dome of stacked discs so the underside reads as a real cap edge
	local capCol = opts.cap or L.C.GlowPink
	for i = 0, 2 do
		local t = i / 2
		local rr = capR * math.sqrt(1 - t * t * 0.86)
		L.cyl(m, "Cap", CFrame.new(top + Vector3.new(0, capR * 0.30 * t, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			capR * 0.20, rr * 2, jc(capCol, rng, 14), Enum.Material.Grass, {collide = false, shadow = true})
	end
	L.blob(m, "CapDome", CFrame.new(top + Vector3.new(0, capR * 0.34, 0)), Vector3.new(capR * 1.7, capR * 0.9, capR * 1.7),
		jc(capCol, rng, 14), Enum.Material.Grass, {collide = false, shadow = true})
	-- gills underneath, glowing
	for i = 0, 7 do
		local a = math.rad(i * 45)
		L.box(m, "Gill", CFrame.new(top + Vector3.new(math.cos(a) * capR * 0.55, -0.4, math.sin(a) * capR * 0.55))
			* CFrame.Angles(0, -a, 0), Vector3.new(capR * 1.0, 0.35, 0.5),
			opts.gill or L.C.GlowCyan, Enum.Material.Neon, {collide = false, shadow = false})
	end
	local gl = L.box(m, "CapGlow", CFrame.new(top - Vector3.new(0, 1.2, 0)), Vector3.new(1, 1, 1), opts.gill or L.C.GlowCyan, Enum.Material.Neon, {collide = false, shadow = false, transparency = 1})
	L.light(gl, opts.gill or L.C.GlowCyan, 1.6, capR * 4)
	-- spots on the cap
	for i = 1, (opts.spots or 3) do
		local a = rng:NextNumber(0, 6.283)
		local rr = rng:NextNumber(0, capR * 0.75)
		L.blob(m, "CapSpot", CFrame.new(top + Vector3.new(math.cos(a) * rr, capR * 0.42, math.sin(a) * rr)),
			Vector3.new(rng:NextNumber(1.5, 4), 0.6, rng:NextNumber(1.5, 4)), opts.spot or L.C.PetalPale,
			Enum.Material.Grass, {collide = false, shadow = false})
	end
	return m
end

----------------------------------------------------------------------------------
-- UNDERGROWTH
----------------------------------------------------------------------------------
function Fl.fern(parent, base, opts)
	opts = opts or {}
	local rng = Random.new(opts.seed or 23)
	local n = opts.fronds or rng:NextInteger(4, 6)
	local h = opts.height or rng:NextNumber(4, 11)
	for i = 1, n do
		local a = rng:NextNumber(0, 6.283)
		local arch = rng:NextNumber(0.5, 1.0)
		local tip = base + Vector3.new(math.cos(a) * h * arch * 0.8, h * rng:NextNumber(0.6, 1.0), math.sin(a) * h * arch * 0.8)
		local mid = base + Vector3.new(math.cos(a) * h * 0.2, h * 0.8, math.sin(a) * h * 0.2)
		local steps = 3
		local prev
		for k = 0, steps do
			local p = L.spline({base, mid, tip}, k / steps)
			if prev then
				L.box(parent, "Frond", CFrame.lookAt(prev, p) * CFrame.new(0, 0, -(p - prev).Magnitude / 2),
					Vector3.new(rng:NextNumber(1.4, 2.6) * (1 - k / steps * 0.5), 0.22, (p - prev).Magnitude * 1.2),
					jc(opts.leaf or L.C.Leaf, rng, 20), Enum.Material.Grass, {collide = false, shadow = false})
			end
			prev = p
		end
	end
end

function Fl.bush(parent, base, opts)
	opts = opts or {}
	local rng = Random.new(opts.seed or 29)
	local r = opts.radius or rng:NextNumber(3, 8)
	for i = 1, (opts.blobs or 3) do
		local a = rng:NextNumber(0, 6.283)
		local rr = rng:NextNumber(0, r * 0.5)
		L.blob(parent, "Bush", CFrame.new(base + Vector3.new(math.cos(a) * rr, r * rng:NextNumber(0.4, 0.8), math.sin(a) * rr))
			* CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 6), 0),
			Vector3.new(r * rng:NextNumber(0.8, 1.4), r * rng:NextNumber(0.6, 1.0), r * rng:NextNumber(0.8, 1.4)),
			jc(opts.leaf or L.C.LeafDark, rng, 20), Enum.Material.Grass, {collide = false, shadow = false})
	end
	if opts.berries then
		for i = 1, 4 do
			local a = rng:NextNumber(0, 6.283)
			L.glow(parent, "Berry", CFrame.new(base + Vector3.new(math.cos(a) * r * 0.7, r * rng:NextNumber(0.5, 1.0), math.sin(a) * r * 0.7)),
				Vector3.new(0.9, 0.9, 0.9), opts.berries, 0.5, 8, "ball")
		end
	end
end

-- A patch of glowing flowers.
function Fl.flowerPatch(parent, base, opts)
	opts = opts or {}
	local rng = Random.new(opts.seed or 31)
	local r = opts.radius or 6
	for i = 1, (opts.count or 6) do
		local a = rng:NextNumber(0, 6.283)
		local rr = rng:NextNumber(0, r)
		local p = base + Vector3.new(math.cos(a) * rr, 0, math.sin(a) * rr)
		local hh = rng:NextNumber(1.6, 4.2)
		L.box(parent, "Stem", CFrame.new(p + Vector3.new(0, hh / 2, 0)) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), 0, rng:NextNumber(-0.2, 0.2)),
			Vector3.new(0.22, hh, 0.22), L.C.DeepMoss, Enum.Material.Grass, {collide = false, shadow = false})
		local col = opts.colors and opts.colors[rng:NextInteger(1, #opts.colors)] or L.C.GlowPink
		L.glow(parent, "Flower", CFrame.new(p + Vector3.new(0, hh, 0)), Vector3.new(1.5, 0.9, 1.5), col,
			opts.brightness or 0.55, 9, "blob")
		-- petals around the glow
		for k = 0, 2 do
			local pa = math.rad(k * 90 + rng:NextNumber(0, 40))
			L.blob(parent, "Petal", CFrame.new(p + Vector3.new(math.cos(pa) * 0.9, hh, math.sin(pa) * 0.9))
				* CFrame.Angles(0, -pa, math.rad(24)), Vector3.new(1.0, 0.22, 1.7),
				col, Enum.Material.Grass, {collide = false, shadow = false})
		end
	end
end

function Fl.grassTuft(parent, base, opts)
	opts = opts or {}
	local rng = Random.new(opts.seed or 37)
	for i = 1, (opts.blades or 6) do
		local a = rng:NextNumber(0, 6.283)
		local hh = rng:NextNumber(2, 6)
		L.box(parent, "Blade", CFrame.new(base + Vector3.new(math.cos(a) * 0.7, hh / 2, math.sin(a) * 0.7))
			* CFrame.Angles(math.cos(a) * 0.28, rng:NextNumber(0, 6), math.sin(a) * 0.28),
			Vector3.new(0.5, hh, 0.16), jc(opts.leaf or L.C.Moss, rng, 22), Enum.Material.Grass,
			{collide = false, shadow = false})
	end
end

function Fl.lilyPad(parent, pos, opts)
	opts = opts or {}
	local rng = Random.new(opts.seed or 41)
	local r = opts.radius or rng:NextNumber(3, 7)
	L.cyl(parent, "LilyPad", CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), 0.35, r * 2,
		jc(opts.leaf or L.C.LeafDark, rng, 18), Enum.Material.Grass, {collide = false, shadow = false})
	-- notch, so it is a lily pad and not a coin
	L.box(parent, "PadNotch", CFrame.new(pos + Vector3.new(r * 0.7, 0.05, 0)) * L.yaw(rng:NextNumber(0, 360)),
		Vector3.new(r * 0.7, 0.4, r * 0.5), jc(opts.leaf or L.C.LeafDark, rng, 18), Enum.Material.Grass, {collide = false, shadow = false})
	if rng:NextNumber() < (opts.flowerChance or 0.3) then
		L.glow(parent, "LilyFlower", CFrame.new(pos + Vector3.new(0, 1.1, 0)), Vector3.new(2.0, 1.6, 2.0),
			opts.flower or L.C.PetalPale, 0.7, 12, "blob")
	end
end

-- A cluster of glowing crystals.
function Fl.crystals(parent, base, opts)
	opts = opts or {}
	local rng = Random.new(opts.seed or 43)
	local col = opts.color or L.C.GlowCyan
	for i = 1, (opts.count or 5) do
		local a = rng:NextNumber(0, 6.283)
		local rr = rng:NextNumber(0, opts.spread or 5)
		local hh = rng:NextNumber(opts.minH or 4, opts.maxH or 14)
		local p = base + Vector3.new(math.cos(a) * rr, 0, math.sin(a) * rr)
		local shard = L.box(parent, "Crystal",
			CFrame.new(p + Vector3.new(0, hh * 0.45, 0)) * CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, 6), rng:NextNumber(-0.25, 0.25)),
			Vector3.new(hh * 0.20, hh, hh * 0.20), col, Enum.Material.Glass, {collide = false, shadow = false})
		shard.Transparency = 0.32
		shard.Reflectance = 0.35
		local core = L.box(parent, "CrystalCore",
			shard.CFrame, Vector3.new(hh * 0.09, hh * 0.86, hh * 0.09), col, Enum.Material.Neon, {collide = false, shadow = false})
		if i == 1 then L.light(core, col, opts.brightness or 1.6, opts.range or 30) end
	end
end

return Fl
