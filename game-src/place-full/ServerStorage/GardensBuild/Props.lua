-- GardensProps -- the small built things: stalls, tents, lanterns, roots, fountains.
--
-- Every prop that has a roof or a top surface also has the thing holding it up.
-- Canopies sit ON posts that reach the ground, counters have solid front and side
-- panels rather than a floating slab, and tent cloth is pinned to poles and pegs.

local L = require(script.Parent.Lib)
local P = {}

local function jitterCol(c, rng, amt)
	amt = amt or 12
	return Color3.fromRGB(
		math.clamp(c.R * 255 + rng:NextNumber(-amt, amt), 0, 255),
		math.clamp(c.G * 255 + rng:NextNumber(-amt, amt), 0, 255),
		math.clamp(c.B * 255 + rng:NextNumber(-amt, amt), 0, 255))
end
P.jitterCol = jitterCol

----------------------------------------------------------------------------------
-- ROOTS AND VINES
----------------------------------------------------------------------------------
-- A gnarled root/branch following control points, tapering along its length.
-- Joint spheres hide the seams between segments so it reads as one organic form.
-- COST NOTE: this used to emit a tube AND a joint sphere for every step, so a tree
-- built from it came out at ~320 parts and 800 trees put 350k parts in the world.
-- The joints only matter where the curve is tight; `joints = false` (the default for
-- vegetation) drops them and the overlapping tube ends hide the seam by themselves.
function P.root(parent, pts, r0, r1, opts)
	opts = opts or {}
	local color = opts.color or L.C.Root
	local mat = opts.mat or Enum.Material.Wood
	local steps = opts.steps or math.max(6, #pts * 3)
	local wantJoints = opts.joints == true
	local prev, prevR
	for i = 0, steps do
		local u = i / steps
		local p = L.spline(pts, u)
		local r = L.lerp(r0, r1, u ^ (opts.taperPow or 1))
		if prev then
			-- 1.06 overlap so consecutive segments meet without a joint sphere
			L.tube(parent, opts.name or "Root", prev, p, (r + prevR) * 1.06, color, mat,
				{collide = opts.collide ~= false, shadow = opts.shadow ~= false})
			if wantJoints then
				L.ball(parent, "RootJoint", CFrame.new(p), r * 2.05, color, mat,
					{collide = false, shadow = false})
			end
		end
		prev, prevR = p, r
	end
	-- side rootlets
	if opts.rootlets then
		local rng = Random.new(opts.seed or 3)
		for i = 1, opts.rootlets do
			local u = rng:NextNumber(0.15, 0.9)
			local base = L.spline(pts, u)
			local dir = (L.spline(pts, math.min(u + 0.05, 1)) - base)
			dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(0, 1, 0)
			local side = dir:Cross(Vector3.new(0, 1, 0))
			side = side.Magnitude > 0.1 and side.Unit or Vector3.new(1, 0, 0)
			local len = rng:NextNumber(6, 20)
			local tip = base + side * len * rng:NextNumber(-1, 1) + dir * len * 0.4
				- Vector3.new(0, rng:NextNumber(2, 10), 0)
			local rr = L.lerp(r0, r1, u) * 0.42
			L.tube(parent, "Rootlet", base, tip, rr, color, mat, {collide = false, shadow = false})
			L.ball(parent, "RootletTip", CFrame.new(tip), rr * 1.4, color, mat, {collide = false, shadow = false})
		end
	end
end

-- Two roots arching over a path and meeting overhead.
function P.rootArch(parent, cf, span, height, thick, opts)
	opts = opts or {}
	for _, s in ipairs({1, -1}) do
		local pts = {
			(cf * CFrame.new(s * span * 0.62, -4, 0)).Position,
			(cf * CFrame.new(s * span * 0.55, height * 0.42, s * 5)).Position,
			(cf * CFrame.new(s * span * 0.30, height * 0.86, -s * 4)).Position,
			(cf * CFrame.new(s * span * 0.03, height, 0)).Position,
			(cf * CFrame.new(-s * span * 0.16, height * 0.94, s * 3)).Position,
		}
		P.root(parent, pts, thick, thick * 0.42, {
			color = opts.color or L.C.Root, rootlets = opts.rootlets or 4,
			seed = (opts.seed or 5) + (s > 0 and 0 or 41), name = "ArchRoot",
		})
	end
end

-- A hanging vine, optionally with leaves and glowing buds.
function P.vine(parent, from, len, opts)
	opts = opts or {}
	local rng = Random.new(opts.seed or 9)
	local segs = math.max(2, math.floor(len / 12))
	local pts = {from}
	local drift = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
	for i = 1, segs do
		pts[#pts + 1] = from + Vector3.new(0, -len * i / segs, 0) + drift * (i * rng:NextNumber(0.4, 1.6))
	end
	local prev
	for i = 0, segs do
		local p = L.spline(pts, i / segs)
		if prev then
			L.tube(parent, "Vine", prev, p, opts.thick or 0.5, opts.color or L.C.DeepMoss,
				Enum.Material.Grass, {collide = false, shadow = false})
		end
		prev = p
		if opts.leaves ~= false and i > 0 then
			L.blob(parent, "VineLeaf", CFrame.new(p + Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2)))
				* CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 6), 0),
				Vector3.new(rng:NextNumber(2, 4.5), 0.4, rng:NextNumber(2, 4.5)),
				opts.leafColor or L.C.Leaf, Enum.Material.Grass, {collide = false, shadow = false})
		end
	end
	if opts.glow then
		local tip = pts[#pts]
		L.glow(parent, "VineBud", CFrame.new(tip), Vector3.new(1.6, 1.6, 1.6), opts.glow, 1.2, 12, "ball")
	end
end

----------------------------------------------------------------------------------
-- LIGHT
----------------------------------------------------------------------------------
-- An elven lantern: a glowing core inside an open metal cage.
function P.lantern(parent, cf, opts)
	opts = opts or {}
	local col = opts.color or L.C.GlowGold
	local s = opts.scale or 1
	local m = opts.model or parent
	L.glow(m, "LanternCore", cf, Vector3.new(1.5 * s, 1.9 * s, 1.5 * s), col, opts.brightness or 2.2,
		opts.range or 26, "blob")
	-- cage: 4 uprights + top and bottom rings, so it is a lantern, not a floating orb
	for i = 0, 3 do
		local a = math.rad(i * 90 + 45)
		L.box(m, "LanternRib", cf * CFrame.new(math.cos(a) * 1.15 * s, 0, math.sin(a) * 1.15 * s)
			* CFrame.Angles(0, -a, 0), Vector3.new(0.18 * s, 2.5 * s, 0.18 * s),
			opts.metal or L.C.Iron, Enum.Material.Metal, {collide = false, shadow = false})
	end
	L.cyl(m, "LanternRingTop", cf * CFrame.new(0, 1.35 * s, 0) * CFrame.Angles(0, 0, math.rad(90)),
		0.22 * s, 2.7 * s, opts.metal or L.C.Iron, Enum.Material.Metal, {collide = false, shadow = false})
	L.cyl(m, "LanternRingBot", cf * CFrame.new(0, -1.35 * s, 0) * CFrame.Angles(0, 0, math.rad(90)),
		0.22 * s, 2.7 * s, opts.metal or L.C.Iron, Enum.Material.Metal, {collide = false, shadow = false})
	L.box(m, "LanternCap", cf * CFrame.new(0, 1.7 * s, 0), Vector3.new(2.4 * s, 0.5 * s, 2.4 * s),
		opts.metal or L.C.Iron, Enum.Material.Metal, {collide = false, shadow = false})
	L.post(m, "LanternFinial", cf * CFrame.new(0, 2.1 * s, 0), 0.9 * s, 0.3 * s,
		opts.metal or L.C.Iron, Enum.Material.Metal, {collide = false, shadow = false})
	return m
end

-- Lantern hanging from a point above (rope + lantern).
function P.hangingLantern(parent, anchor, drop, opts)
	opts = opts or {}
	local s = opts.scale or 0.8
	L.tube(parent, "LanternRope", anchor, anchor - Vector3.new(0, drop, 0), 0.16,
		opts.rope or L.C.Bark, Enum.Material.Fabric, {collide = false, shadow = false})
	P.lantern(parent, CFrame.new(anchor - Vector3.new(0, drop + 2 * s, 0)), opts)
end

-- An ornate lamp post.
function P.lampPost(parent, base, height, opts)
	opts = opts or {}
	local col = opts.stone or L.C.WeatheredStone
	L.box(parent, "PostBase", CFrame.new(base + Vector3.new(0, 0.8, 0)), Vector3.new(3.4, 1.6, 3.4), col, L.M.Stone, {solid = true})
	L.box(parent, "PostPlinth", CFrame.new(base + Vector3.new(0, 2.1, 0)), Vector3.new(2.4, 1.2, 2.4), col, L.M.Stone, {shadow = false})
	L.post(parent, "PostShaft", CFrame.new(base + Vector3.new(0, height * 0.5 + 2, 0)), height - 2, 1.0, col, L.M.Stone, {solid = true})
	-- scrolled bracket arms
	for i = 0, 3 do
		local a = math.rad(i * 90)
		L.box(parent, "PostScroll", CFrame.new(base + Vector3.new(math.cos(a) * 1.1, height - 0.6, math.sin(a) * 1.1))
			* CFrame.Angles(0, -a, math.rad(28)), Vector3.new(0.4, 2.2, 0.4), col, L.M.Stone, {shadow = false})
	end
	L.box(parent, "PostCap", CFrame.new(base + Vector3.new(0, height + 0.4, 0)), Vector3.new(2.8, 0.8, 2.8), col, L.M.Stone, {shadow = false})
	P.lantern(parent, CFrame.new(base + Vector3.new(0, height + 2.4, 0)), opts)
	return height
end

-- A stone brazier with a glowing bowl.
function P.brazier(parent, base, opts)
	opts = opts or {}
	local col = opts.stone or L.C.WeatheredStone
	L.box(parent, "BrazierBase", CFrame.new(base + Vector3.new(0, 0.7, 0)), Vector3.new(4.2, 1.4, 4.2), col, L.M.Stone, {solid = true})
	for i = 0, 2 do
		local a = math.rad(i * 120)
		L.post(parent, "BrazierLeg", CFrame.new(base + Vector3.new(math.cos(a) * 1.2, 2.6, math.sin(a) * 1.2))
			* CFrame.Angles(math.rad(6) * math.sin(a), 0, -math.rad(6) * math.cos(a)), 3.4, 0.8, col, L.M.Stone, {shadow = false})
	end
	L.cyl(parent, "BrazierBowl", CFrame.new(base + Vector3.new(0, 4.6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		1.5, 5.6, col, L.M.Stone, {solid = true})
	L.glow(parent, "BrazierFire", CFrame.new(base + Vector3.new(0, 5.4, 0)), Vector3.new(4.4, 1.8, 4.4),
		opts.fire or L.C.GlowCyan, 3.0, 34, "blob")
	return parent
end

----------------------------------------------------------------------------------
-- MARKET
----------------------------------------------------------------------------------
-- A market stall. Posts run from the ground to the canopy, the counter has solid
-- front and end panels, and the canopy is a real pitched cloth roof with a ridge.
function P.stall(parent, cf, opts)
	opts = opts or {}
	local rng = Random.new(opts.seed or 11)
	local m = Instance.new("Model")
	m.Name = opts.name or "MarketStall"
	m.Parent = parent
	local w = opts.width or 14
	local d = opts.depth or 10
	local postH = opts.height or 10
	local wood = opts.wood or L.C.Wood
	local cloth = opts.cloth or L.C.ClothTeal
	local stone = opts.stone or L.C.WeatheredStone

	-- 4 posts, ground to canopy
	for _, sx in ipairs({-1, 1}) do
		for _, sz in ipairs({-1, 1}) do
			L.box(m, "StallPost", cf * CFrame.new(sx * (w / 2 - 0.5), postH / 2, sz * (d / 2 - 0.5)),
				Vector3.new(0.9, postH, 0.9), wood, Enum.Material.Wood, {solid = true})
			L.box(m, "PostFoot", cf * CFrame.new(sx * (w / 2 - 0.5), 0.4, sz * (d / 2 - 0.5)),
				Vector3.new(1.6, 0.8, 1.6), stone, L.M.Stone, {shadow = false})
		end
	end
	-- head rails tying the posts together
	for _, sz in ipairs({-1, 1}) do
		L.box(m, "StallRail", cf * CFrame.new(0, postH - 0.5, sz * (d / 2 - 0.5)), Vector3.new(w, 0.7, 0.7), wood, Enum.Material.Wood, {shadow = false})
	end
	for _, sx in ipairs({-1, 1}) do
		L.box(m, "StallRail", cf * CFrame.new(sx * (w / 2 - 0.5), postH - 0.5, 0), Vector3.new(0.7, 0.7, d), wood, Enum.Material.Wood, {shadow = false})
	end

	-- counter: top slab plus front and end panels so it is not a floating shelf
	local ch = opts.counterH or 4
	L.box(m, "CounterTop", cf * CFrame.new(0, ch, -d / 2 + 1.6), Vector3.new(w - 1.4, 0.6, 3.2),
		opts.counterStone ~= false and stone or wood, opts.counterStone ~= false and L.M.Stone or Enum.Material.Wood, {solid = true})
	L.box(m, "CounterFront", cf * CFrame.new(0, ch / 2, -d / 2 + 0.3), Vector3.new(w - 1.4, ch, 0.5), wood, Enum.Material.WoodPlanks, {solid = true})
	for _, sx in ipairs({-1, 1}) do
		L.box(m, "CounterEnd", cf * CFrame.new(sx * (w / 2 - 1.0), ch / 2, -d / 2 + 1.6), Vector3.new(0.5, ch, 3.2), wood, Enum.Material.WoodPlanks, {shadow = false})
	end
	-- back shelf
	L.box(m, "BackShelf", cf * CFrame.new(0, ch + 1.8, d / 2 - 1.2), Vector3.new(w - 2.4, 0.4, 2.0), wood, Enum.Material.WoodPlanks, {shadow = false})
	for _, sx in ipairs({-1, 1}) do
		L.box(m, "ShelfBracket", cf * CFrame.new(sx * (w / 2 - 1.6), ch * 0.5 + 0.9, d / 2 - 1.2), Vector3.new(0.4, ch + 1.8, 0.4), wood, Enum.Material.Wood, {shadow = false})
	end

	-- canopy: pitched cloth on a ridge beam carried by the posts
	local ridge = postH + 3.2
	L.box(m, "Ridge", cf * CFrame.new(0, ridge, 0), Vector3.new(w + 2.2, 0.5, 0.5), wood, Enum.Material.Wood, {shadow = false})
	local slopeLen = math.sqrt((d / 2 + 1.4) ^ 2 + (ridge - postH + 0.5) ^ 2)
	local ang = math.atan2(ridge - postH + 0.5, d / 2 + 1.4)
	for _, sz in ipairs({-1, 1}) do
		L.box(m, "Canopy", cf * CFrame.new(0, (ridge + postH - 0.5) / 2, sz * (d / 2 + 1.4) / 2)
			* CFrame.Angles(sz * ang, 0, 0), Vector3.new(w + 2.4, 0.28, slopeLen),
			cloth, Enum.Material.Fabric, {collide = false, shadow = true})
		-- scalloped valance along the eave
		for i = 0, 6 do
			L.box(m, "Valance", cf * CFrame.new(-(w + 2) / 2 + (w + 2) * i / 6, postH - 1.3, sz * (d / 2 + 1.5)),
				Vector3.new((w + 2) / 7, 1.4, 0.2), i % 2 == 0 and cloth or L.C.ClothGold, Enum.Material.Fabric,
				{collide = false, shadow = false})
		end
	end
	-- gable cloth so you cannot see straight through under the ridge
	for _, sx in ipairs({-1, 1}) do
		for i = 0, 5 do
			local t = i / 5
			local hgt = (ridge - postH + 0.5) * (1 - math.abs(t * 2 - 1))
			if hgt > 0.1 then
				L.box(m, "CanopyGable", cf * CFrame.new(sx * (w + 2.2) / 2, postH - 0.5 + hgt / 2, (t - 0.5) * (d + 2.8)),
					Vector3.new(0.22, hgt, (d + 2.8) / 6), cloth, Enum.Material.Fabric, {collide = false, shadow = false})
			end
		end
	end

	-- hanging lanterns at the front corners
	for _, sx in ipairs({-1, 1}) do
		P.hangingLantern(m, (cf * CFrame.new(sx * (w / 2 - 0.6), postH - 1.0, -d / 2 - 1.0)).Position, 2.0,
			{scale = 0.6, color = opts.lantern or L.C.GlowGold, brightness = 1.6, range = 18})
	end

	-- goods on the counter
	local goods = opts.goods or 5
	for i = 1, goods do
		local gx = -w / 2 + 1.6 + (w - 3.2) * (i - 0.5) / goods
		local kind = rng:NextInteger(1, 4)
		local gcf = cf * CFrame.new(gx, ch + 0.5, -d / 2 + 1.6)
		if kind == 1 then
			L.blob(m, "Fruit", gcf * CFrame.new(0, 0.5, 0), Vector3.new(1.6, 1.3, 1.6),
				jitterCol(L.C.Petal, rng, 40), Enum.Material.Grass, {collide = false, shadow = false})
		elseif kind == 2 then
			L.cyl(m, "Pot", gcf * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0, math.rad(90)), 1.7, 1.7,
				jitterCol(L.C.WoodRed, rng), Enum.Material.Slate, {collide = false, shadow = false})
		elseif kind == 3 then
			L.box(m, "Bundle", gcf * CFrame.new(0, 0.6, 0) * L.yaw(rng:NextNumber(0, 90)),
				Vector3.new(1.8, 1.0, 1.4), jitterCol(L.C.ClothGold, rng), Enum.Material.Fabric, {collide = false, shadow = false})
		else
			L.glow(m, "GlowJar", gcf * CFrame.new(0, 0.9, 0), Vector3.new(1.3, 1.7, 1.3),
				({L.C.GlowGreen, L.C.GlowCyan, L.C.GlowPink})[rng:NextInteger(1, 3)], 1.4, 12, "blob")
		end
	end
	return m
end

-- A conical decorative tent, pinned to pegs.
function P.tent(parent, cf, opts)
	opts = opts or {}
	local r = opts.radius or 9
	local h = opts.height or 13
	local cloth = opts.cloth or L.C.ClothPink
	local m = Instance.new("Model")
	m.Name = opts.name or "Tent"
	m.Parent = parent
	local n = opts.panels or 10
	L.post(m, "TentPole", cf * CFrame.new(0, h * 0.5, 0), h, 0.6, L.C.Wood, Enum.Material.Wood, {solid = true})
	for i = 0, n - 1 do
		local a0 = math.rad(i * 360 / n)
		local mid = math.rad((i + 0.5) * 360 / n)
		-- each panel is a leaning slab from the peg ring up to the pole top
		local footR = r
		local px, pz = math.cos(mid) * footR, math.sin(mid) * footR
		local slope = math.sqrt(footR * footR + h * h)
		local tilt = math.atan2(footR, h)
		L.box(m, "TentPanel",
			cf * CFrame.new(px * 0.5, h * 0.5, pz * 0.5) * CFrame.Angles(0, -mid, 0) * CFrame.Angles(0, 0, -tilt),
			Vector3.new(0.3, slope + 0.6, 2 * math.pi * r / n * 1.25),
			jitterCol(cloth, Random.new((opts.seed or 1) + i), 10), Enum.Material.Fabric,
			{collide = false, shadow = true})
		-- peg and guy rope
		local ex, ez = math.cos(a0) * (r + 2.6), math.sin(a0) * (r + 2.6)
		L.post(m, "TentPeg", cf * CFrame.new(ex, 0.5, ez), 1.6, 0.35, L.C.Bark, Enum.Material.Wood, {shadow = false})
		L.tube(m, "GuyRope", (cf * CFrame.new(math.cos(a0) * r * 0.9, h * 0.86, math.sin(a0) * r * 0.9)).Position,
			(cf * CFrame.new(ex, 0.9, ez)).Position, 0.14, L.C.BarkPale, Enum.Material.Fabric, {collide = false, shadow = false})
	end
	L.ball(m, "TentFinial", cf * CFrame.new(0, h + 0.8, 0), 1.6, L.C.Gold, Enum.Material.Foil, {shadow = false})
	return m
end

function P.crate(parent, cf, size, opts)
	opts = opts or {}
	size = size or Vector3.new(3.4, 3.0, 3.4)
	local col = opts.color or L.C.WoodPale
	L.box(parent, "Crate", cf, size, col, Enum.Material.WoodPlanks, {solid = true})
	for _, s in ipairs({1, -1}) do
		L.box(parent, "CrateBand", cf * CFrame.new(0, s * size.Y * 0.3, 0),
			Vector3.new(size.X + 0.1, 0.3, size.Z + 0.1), L.C.Bark, Enum.Material.Wood, {shadow = false})
	end
end

function P.barrel(parent, cf, opts)
	opts = opts or {}
	local h = opts.height or 4
	L.post(parent, "Barrel", cf * CFrame.new(0, h / 2, 0), h, 3.0, opts.color or L.C.Wood, Enum.Material.Wood, {solid = true})
	for _, t in ipairs({0.25, 0.75}) do
		L.post(parent, "BarrelHoop", cf * CFrame.new(0, h * t, 0), 0.35, 3.2, L.C.Iron, Enum.Material.Metal, {shadow = false})
	end
end

function P.banner(parent, cf, w, h, opts)
	opts = opts or {}
	local col = opts.color or L.C.ClothTeal
	L.box(parent, "BannerCloth", cf * CFrame.new(0, -h / 2, 0), Vector3.new(w, h, 0.2), col, Enum.Material.Fabric, {collide = false, shadow = false})
	L.box(parent, "BannerTrim", cf * CFrame.new(0, -h - 0.3, 0), Vector3.new(w, 0.6, 0.26), opts.trim or L.C.Gold, Enum.Material.Foil, {collide = false, shadow = false})
	-- pointed tail so it is not a plain rectangle
	for i = 0, 3 do
		local t = (i + 0.5) / 4
		local tail = (1 - math.abs(t * 2 - 1)) * 2.2
		L.box(parent, "BannerTail", cf * CFrame.new((t - 0.5) * w, -h - 0.6 - tail / 2, 0),
			Vector3.new(w / 4, tail, 0.2), col, Enum.Material.Fabric, {collide = false, shadow = false})
	end
	L.cyl(parent, "BannerRod", cf * CFrame.Angles(0, math.rad(90), 0), w * 1.15, 0.3, opts.rod or L.C.Iron, Enum.Material.Metal, {collide = false, shadow = false})
end

-- A stone planter full of plants.
function P.planter(parent, base, r, opts)
	opts = opts or {}
	local rng = Random.new(opts.seed or 21)
	local col = opts.stone or L.C.WeatheredStone
	local n = opts.sides or 8
	for i = 0, n - 1 do
		local a = math.rad(i * 360 / n)
		L.box(parent, "PlanterWall", CFrame.new(base + Vector3.new(math.cos(a) * r, 1.4, math.sin(a) * r)) * CFrame.Angles(0, -a, 0),
			Vector3.new(0.7, 2.8, 2 * math.pi * r / n * 1.16), col, L.M.Stone, {solid = true})
	end
	L.cyl(parent, "PlanterSoil", CFrame.new(base + Vector3.new(0, 2.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		1.6, r * 2 - 0.6, L.C.Bark, Enum.Material.Ground, {shadow = false})
	for i = 1, (opts.plants or 7) do
		local a = rng:NextNumber(0, 6.28)
		local rr = rng:NextNumber(0, r - 1.4)
		local p = base + Vector3.new(math.cos(a) * rr, 2.9, math.sin(a) * rr)
		L.blob(parent, "PlanterBush", CFrame.new(p + Vector3.new(0, rng:NextNumber(0.6, 2), 0)),
			Vector3.new(rng:NextNumber(2, 4), rng:NextNumber(2, 3.6), rng:NextNumber(2, 4)),
			jitterCol(opts.leaf or L.C.Leaf, rng, 22), Enum.Material.Grass, {collide = false, shadow = false})
		if rng:NextNumber() < 0.4 then
			L.glow(parent, "PlanterBloom", CFrame.new(p + Vector3.new(0, rng:NextNumber(2.4, 4), 0)),
				Vector3.new(1.1, 1.1, 1.1), opts.bloom or L.C.GlowPink, 0.9, 10, "ball")
		end
	end
end

-- A tiered fountain with falling water and a lit basin.
function P.fountain(parent, base, r, opts)
	opts = opts or {}
	local m = Instance.new("Model")
	m.Name = opts.name or "Fountain"
	m.Parent = parent
	local col = opts.stone or L.C.ElvenStone
	local n = 16
	-- basin wall (a closed ring of segments) and floor
	for i = 0, n - 1 do
		local a = math.rad(i * 360 / n)
		L.box(m, "BasinWall", CFrame.new(base + Vector3.new(math.cos(a) * r, 1.6, math.sin(a) * r)) * CFrame.Angles(0, -a, 0),
			Vector3.new(1.2, 3.2, 2 * math.pi * r / n * 1.16), col, L.M.Stone, {solid = true})
		L.box(m, "BasinCap", CFrame.new(base + Vector3.new(math.cos(a) * r, 3.4, math.sin(a) * r)) * CFrame.Angles(0, -a, 0),
			Vector3.new(1.8, 0.4, 2 * math.pi * r / n * 1.16), opts.trim or L.C.PaleStone, L.M.Stone, {shadow = false})
	end
	L.cyl(m, "BasinFloor", CFrame.new(base + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		0.8, r * 2, col, L.M.Stone, {solid = true})
	local water = L.cyl(m, "BasinWater", CFrame.new(base + Vector3.new(0, 2.4, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		0.5, r * 2 - 1.4, L.C.Water, Enum.Material.Glass, {collide = false, shadow = false})
	water.Transparency = 0.35
	water.Reflectance = 0.3
	L.light(water, opts.glow or L.C.GlowCyan, 1.6, r * 3)

	-- central column and upper bowls
	local tiers = opts.tiers or 2
	L.post(m, "FountainStem", CFrame.new(base + Vector3.new(0, 4.5, 0)), 5.0, r * 0.3, col, L.M.Stone, {solid = true})
	for t = 1, tiers do
		local ty = 4 + t * 5.5
		local tr = r * (0.62 - 0.18 * (t - 1))
		L.cyl(m, "TierBowl", CFrame.new(base + Vector3.new(0, ty, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			1.0, tr * 2, col, L.M.Stone, {solid = true})
		L.cyl(m, "TierRim", CFrame.new(base + Vector3.new(0, ty + 0.7, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			0.5, tr * 2 + 0.6, opts.trim or L.C.PaleStone, L.M.Stone, {shadow = false})
		local tw = L.cyl(m, "TierWater", CFrame.new(base + Vector3.new(0, ty + 0.9, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			0.4, tr * 2 - 0.4, L.C.Water, Enum.Material.Glass, {collide = false, shadow = false})
		tw.Transparency = 0.3
		if t < tiers then
			L.post(m, "TierStem", CFrame.new(base + Vector3.new(0, ty + 3, 0)), 5.0, tr * 0.42, col, L.M.Stone, {solid = true})
		end
		-- falling sheets from this bowl to the one below
		for i = 0, 5 do
			local a = math.rad(i * 60 + t * 18)
			local fall = L.box(m, "FountainFall",
				CFrame.new(base + Vector3.new(math.cos(a) * tr, ty - 2.6, math.sin(a) * tr)) * CFrame.Angles(0, -a, 0),
				Vector3.new(0.5, 5.2, 1.6), L.C.Water, Enum.Material.Glass, {collide = false, shadow = false})
			fall.Transparency = 0.45
		end
	end
	L.glow(m, "FountainCrown", CFrame.new(base + Vector3.new(0, 4 + tiers * 5.5 + 2.4, 0)),
		Vector3.new(2.2, 2.6, 2.2), opts.crown or L.C.GlowCyan, 2.4, 34, "blob")
	return m
end

-- An engraved stone slab: elven motif as inlaid glowing lines.
function P.carving(parent, cf, w, h, opts)
	opts = opts or {}
	local rng = Random.new(opts.seed or 31)
	local col = opts.stone or L.C.WeatheredStone
	L.box(parent, "CarvingSlab", cf, Vector3.new(w, h, 0.8), col, L.M.Stone, {solid = true})
	L.box(parent, "CarvingFrame", cf * CFrame.new(0, 0, 0.1), Vector3.new(w + 0.6, h + 0.6, 0.6), opts.trim or L.C.GreyStone, L.M.Stone, {shadow = false})
	local glow = opts.glow or L.C.GlowCyan
	local rows = math.max(2, math.floor(h / 3))
	for i = 1, rows do
		local y = -h / 2 + h * i / (rows + 1)
		local segw = w * rng:NextNumber(0.35, 0.78)
		L.glow(parent, "Rune", cf * CFrame.new(rng:NextNumber(-w * 0.18, w * 0.18), y, 0.5),
			Vector3.new(segw, 0.28, 0.14), glow, 0.6, 10)
		if rng:NextNumber() < 0.6 then
			L.glow(parent, "RuneTick", cf * CFrame.new(rng:NextNumber(-w * 0.3, w * 0.3), y - 0.9, 0.5),
				Vector3.new(0.26, 1.4, 0.14), glow, 0.4, 8)
		end
	end
	return parent
end

function P.bench(parent, cf, opts)
	opts = opts or {}
	local col = opts.stone or L.C.WeatheredStone
	local w = opts.width or 8
	L.box(parent, "BenchSeat", cf * CFrame.new(0, 2.4, 0), Vector3.new(w, 0.7, 3.0), col, L.M.Stone, {solid = true})
	for _, s in ipairs({-1, 1}) do
		L.box(parent, "BenchLeg", cf * CFrame.new(s * (w / 2 - 1.0), 1.2, 0), Vector3.new(1.0, 2.4, 2.8), col, L.M.Stone, {solid = true})
	end
	L.box(parent, "BenchBack", cf * CFrame.new(0, 4.0, 1.2), Vector3.new(w, 2.6, 0.5), col, L.M.Stone, {shadow = false})
end

return P
