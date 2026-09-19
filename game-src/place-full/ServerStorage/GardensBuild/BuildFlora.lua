-- BuildFlora -- the living layer across the whole cavern.
--
-- PROTOTYPE AND CLONE. A detailed tree is ~50 parts; generating a unique one for
-- every position would put 20k+ unique instances in the world for the trees alone.
-- Instead a small set of variants is built once and cloned with random yaw and
-- scale, which is far cheaper to build and lets the engine reuse the geometry.
--
-- Placement is rejection-sampled against the height field: nothing is planted in
-- water, on ground too steep to stand on, or inside the areas that are already
-- built (the plaza, the street, the cathedral terrace, the pilgrim way).

local L = require(script.Parent.Lib)
local F = require(script.Parent.Field)
local P = require(script.Parent.Props)
local Fl = require(script.Parent.Flora)

local M = {}

local function g(x, z) return F.ground(x, z, F.ceiling(x, z)) end

local function slopeAt(x, z)
	local ch = F.ceiling(x, z)
	return math.max(
		math.abs(F.ground(x + 6, z, ch) - F.ground(x - 6, z, ch)),
		math.abs(F.ground(x, z + 6, ch) - F.ground(x, z - 6, ch))) / 12
end

-- keep-out zones: already-built ground
local function blocked(x, z)
	-- hub plaza and its approaches
	local dh = math.sqrt((x - F.HUB.X) ^ 2 + (z - F.HUB.Y) ^ 2)
	if dh < 250 then return true end
	-- cathedral terrace
	local dc = math.sqrt((x - F.HILL.X) ^ 2 + (z - (F.HILL.Y - 10)) ^ 2)
	if dc < 190 then return true end
	-- the pilgrim way spiral
	local hr = math.sqrt((x - F.HILL.X) ^ 2 + (z - F.HILL.Y) ^ 2)
	if hr > 240 and hr < 490 then
		local ang = math.deg(math.atan2(z - F.HILL.Y, x - F.HILL.X)) % 360
		local u = (L.lerp(0, 1, (470 - hr) / (470 - 252)))
		local wantDeg = (92 + 302 * u) % 360
		local d = math.abs((ang - wantDeg + 180) % 360 - 180)
		if d < 6 then return true end
	end
	-- town street corridor
	if x > -420 and x < 340 and z > -470 and z < 60 then
		local dt = math.sqrt((x + 40) ^ 2 + (z + 250) ^ 2)
		if dt < 60 then return true end
	end
	return false
end

-- EVERY prototype is built standing on the world origin, so its pivot is pinned there
-- with NO rotation.
--
-- Without this, a Model that has no PrimaryPart takes its pivot from the BOUNDING-BOX
-- CENTRE -- for a tree that is ~32 studs up, and it carries an arbitrary rotation
-- (measured: -0.72, 0.77, -3.14 radians). PivotTo then planted every tree by its
-- middle, burying it 19-44 studs, and applied the leftover rotation as a tumble that
-- laid a chunk of them on their sides.
--
-- Pinning the pivot to the base makes PivotTo mean "stand here", and makes ScaleTo
-- grow the plant upward from its roots rather than about its waist.
local function pinPivot(m)
	m.WorldPivot = CFrame.new(0, 0, 0)
	return m
end

function M.run()
	local root = workspace.GameWorld.LushGardens
	local flora = root.Flora
	flora:ClearAllChildren()
	local proto = Instance.new("Folder")
	proto.Name = "_proto"
	proto.Parent = workspace          -- built here, cloned out, then destroyed
	local rng = Random.new(987654)

	----------------------------------------------------------------- prototypes
	local trees, mushrooms, clumps, crystals = {}, {}, {}, {}
	local leafSets = {
		{leaf = L.C.Leaf,     pale = L.C.LeafPale,  bloom = nil},
		{leaf = L.C.LeafDark, pale = L.C.Leaf,      bloom = L.C.GlowPink},
		{leaf = L.C.LeafBlue, pale = L.C.LeafPale,  bloom = L.C.GlowCyan},
		{leaf = L.C.Leaf,     pale = L.C.Lichen,    bloom = nil},
		{leaf = L.C.LeafDark, pale = L.C.LeafPale,  bloom = L.C.GlowGold},
	}
	for i = 1, 8 do
		local ls = leafSets[((i - 1) % #leafSets) + 1]
		-- These options used to OVERRIDE the module's (already lowered) defaults and put
		-- each tree back up to 122 parts. Kept deliberately lean: the scatter scales them
		-- up to 2.1x, so a big canopy costs the same as a small one.
		local m = Fl.tree(proto, Vector3.new(0, 0, 0), {
			seed = i * 77, height = 44 + (i % 4) * 12, branches = 4,
			blobs = 3, leaf = ls.leaf, leafPale = ls.pale, bloom = ls.bloom, blooms = 2,
			vines = 1, roots = 2, name = "TreeProto" .. i,
		})
		trees[#trees + 1] = pinPivot(m)
	end
	for i = 1, 5 do
		mushrooms[#mushrooms + 1] = pinPivot(Fl.giantMushroom(proto, Vector3.new(0, 0, 0), {
			seed = i * 31, height = 14 + i * 7,
			cap = (i % 2 == 0) and L.C.GlowPink or L.C.PetalPale,
			gill = (i % 3 == 0) and L.C.GlowGreen or L.C.GlowCyan, spots = 5,
			name = "ShroomProto" .. i,
		}))
	end
	for i = 1, 6 do
		local m = Instance.new("Model"); m.Name = "ClumpProto" .. i; m.Parent = proto
		Fl.bush(m, Vector3.new(0, 0, 0), {seed = i * 13, radius = 4 + (i % 3) * 2,
			berries = (i % 3 == 0) and L.C.GlowCyan or nil})
		Fl.fern(m, Vector3.new(rng:NextNumber(-6, 6), 0, rng:NextNumber(-6, 6)), {seed = i * 17, fronds = 4, height = 6})
		if i % 3 == 0 then
			Fl.flowerPatch(m, Vector3.new(rng:NextNumber(-7, 7), 0, rng:NextNumber(-7, 7)),
				{seed = i * 19, radius = 5, count = 4, colors = {L.C.GlowPink, L.C.GlowCyan, L.C.GlowGold}})
		end
		clumps[#clumps + 1] = pinPivot(m)
	end
	for i = 1, 4 do
		local m = Instance.new("Model"); m.Name = "CrystalProto" .. i; m.Parent = proto
		Fl.crystals(m, Vector3.new(0, 0, 0), {seed = i * 23, count = 4 + i, spread = 5,
			minH = 5, maxH = 8 + i * 4, color = (i % 2 == 0) and L.C.GlowCyan or L.C.GlowGreen,
			brightness = 1.4, range = 30})
		crystals[#crystals + 1] = pinPivot(m)
	end

	----------------------------------------------------------------- scatter
	local placed = {tree = 0, shroom = 0, clump = 0, crystal = 0}
	local folders = {
		tree = L.folder(flora, "Trees"), shroom = L.folder(flora, "Mushrooms"),
		clump = L.folder(flora, "Undergrowth"), crystal = L.folder(flora, "Crystals"),
	}
	local function place(kind, list, x, z, scaleLo, scaleHi)
		local m = list[rng:NextInteger(1, #list)]:Clone()
		m.Parent = folders[kind]
		local y = g(x, z)
		m:PivotTo(CFrame.new(L.wv(x, y, z)) * CFrame.Angles(0, rng:NextNumber(0, 6.283), 0))
		if scaleHi and scaleHi > scaleLo then
			local s = rng:NextNumber(scaleLo, scaleHi)
			if math.abs(s - 1) > 0.04 then m:ScaleTo(s) end
		end
		placed[kind] = placed[kind] + 1
		return m
	end

	-- HARD CAPS. The first version ran 5200 attempts with no ceiling and planted 3031
	-- pieces of vegetation -- 351,000 parts, eight times the rest of the world, and it
	-- made the whole game unplayable. Vegetation now has a budget and stops when it is
	-- spent. Roughly: 90*70 + 60*35 + 140*15 + 40*8 parts, about 12k in total.
	local CAP = {tree = 90, shroom = 60, clump = 140, crystal = 40}
	local function room(kind) return placed[kind] < CAP[kind] end

	local ATTEMPTS = 2600
	for i = 1, ATTEMPTS do
		local x = rng:NextNumber(-1190, 1190)
		local z = rng:NextNumber(-1190, 1190)
		local ch = F.ceiling(x, z)
		local y = F.ground(x, z, ch)
		if y > F.WATER + 2.5 and ch > y + 40 and not blocked(x, z) then
			local sl = slopeAt(x, z)
			if sl < 1.1 then
				-- what grows here depends on where here is
				local dFung = math.sqrt((x - F.FUNGAL.X) ^ 2 + (z - F.FUNGAL.Y) ^ 2)
				local dCasc = math.sqrt((x - F.CASCADE.X) ^ 2 + (z - F.CASCADE.Y) ^ 2)
				local dWeep = math.sqrt((x - F.WEEPING.X) ^ 2 + (z - F.WEEPING.Y) ^ 2)
				local r = rng:NextNumber()
				if dFung < 330 then
					-- the Fungal Hollow: mushrooms and crystals, almost no trees
					if r < 0.62 and room("shroom") then place("shroom", mushrooms, x, z, 0.9, 2.8)
					elseif r < 0.82 and room("crystal") then place("crystal", crystals, x, z, 0.8, 1.9)
					elseif room("clump") then place("clump", clumps, x, z, 0.7, 1.5) end
				elseif dCasc < 340 or dWeep < 330 then
					-- wet ground: dense undergrowth and ferns
					if r < 0.30 and room("tree") then place("tree", trees, x, z, 0.85, 1.5)
					elseif r < 0.80 and room("clump") then place("clump", clumps, x, z, 0.8, 1.8)
					elseif room("shroom") then place("shroom", mushrooms, x, z, 0.8, 1.8) end
				elseif y > 230 then
					-- the upper hill: sparser, wind-bent, more crystal
					if r < 0.28 and room("tree") then place("tree", trees, x, z, 0.7, 1.2)
					elseif r < 0.72 and room("clump") then place("clump", clumps, x, z, 0.6, 1.2)
					elseif room("crystal") then place("crystal", crystals, x, z, 0.7, 1.4) end
				else
					-- fewer, LARGER trees: the world reads better with 90 big canopies than
					-- with 800 small ones, and costs a fraction as much
					if r < 0.30 and room("tree") then place("tree", trees, x, z, 1.0, 2.1)
					elseif r < 0.74 and room("clump") then place("clump", clumps, x, z, 0.8, 1.9)
					elseif r < 0.90 and room("shroom") then place("shroom", mushrooms, x, z, 0.8, 2.0)
					elseif room("crystal") then place("crystal", crystals, x, z, 0.7, 1.4) end
				end
			end
		end
	end

	----------------------------------------------------------------- lily pads
	local pads = L.folder(flora, "WaterPlants")
	local padN = 0
	for i = 1, 700 do
		if padN >= 110 then break end
		local x = rng:NextNumber(-1150, 1150)
		local z = rng:NextNumber(-1150, 1150)
		local ch = F.ceiling(x, z)
		local y = F.ground(x, z, ch)
		if y < F.WATER - 2 and y > F.WATER - 26 and ch > F.WATER + 30 then
			Fl.lilyPad(pads, L.wv(x, F.WATER + 0.5, z), {seed = i, radius = rng:NextNumber(3, 8),
				flowerChance = 0.34, flower = rng:NextNumber() < 0.5 and L.C.PetalPale or L.C.GlowPink})
			padN = padN + 1
			if rng:NextNumber() < 0.25 then
				-- reeds at the margin
				for k = 1, 4 do
					local rx, rz = x + rng:NextNumber(-6, 6), z + rng:NextNumber(-6, 6)
					local hh = rng:NextNumber(5, 12)
					L.box(pads, "Reed", L.wcf(rx, F.WATER + hh / 2, rz) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15)),
						Vector3.new(0.4, hh, 0.4), L.C.DeepMoss, Enum.Material.Grass, {collide = false, shadow = false})
				end
			end
		end
	end

	----------------------------------------------------------------- hanging blooms
	-- the reference image's big pink lotus flowers, hung from the cavern roof and
	-- from the undersides of overhangs above the main spaces
	-- THE HANGING BLOOMS are the reference image's signature, so they get their own
	-- placement rather than being left to chance. The first pass demanded a roof within
	-- 230 studs, which almost nothing in a cavern this tall satisfies -- it placed 4.
	-- They now hang from overhangs, from the roof wherever it is reachable, and are
	-- concentrated over the hub, the town and the cascade where players actually are.
	local hang = L.folder(flora, "HangingBlooms")
	local hangN = 0
	local hotspots = {F.HUB, Vector2.new(-40, -250), F.CASCADE, F.FUNGAL, F.SUNKEN, F.ARRIVAL_CHAMBER}
	for i = 1, 900 do
		if hangN >= 70 then break end
		local x, z
		if i % 2 == 0 then
			local hs = hotspots[rng:NextInteger(1, #hotspots)]
			local a, rr = rng:NextNumber(0, 6.283), rng:NextNumber(60, 330)
			x, z = hs.X + math.cos(a) * rr, hs.Y + math.sin(a) * rr
		else
			x, z = rng:NextNumber(-1150, 1150), rng:NextNumber(-1150, 1150)
		end
		local ch = F.ceiling(x, z)
		local y = F.ground(x, z, ch)
		if ch - y > 30 and ch - y < 520 and not F.fissure(x, z) then
			Fl.hangingBloom(hang, L.wv(x, ch - 2, z), {seed = i, scale = rng:NextNumber(0.8, 2.0),
				stem = rng:NextNumber(12, 40), petal = rng:NextNumber() < 0.7 and L.C.Petal or L.C.PetalPale,
				glow = L.C.GlowPink, brightness = 1.4})
			hangN = hangN + 1
		end
	end

	proto:Destroy()
	local parts = 0
	for _, d in ipairs(flora:GetDescendants()) do if d:IsA("BasePart") then parts = parts + 1 end end
	return string.format("Flora: %d trees, %d mushrooms, %d undergrowth, %d crystal clusters, %d lily pads, %d hanging blooms -- %d parts",
		placed.tree, placed.shroom, placed.clump, placed.crystal, padN, hangN, parts)
end

return M
