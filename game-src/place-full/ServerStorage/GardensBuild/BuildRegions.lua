-- BuildRegions -- the outlying places, and the things worth walking out to find.
--
-- Everything here is DISCOVERY content: it is off the hub-town-cathedral spine, and
-- most of it is only visible once you have gone looking. Four set pieces:
--   * the Drowned Colonnade, standing in the flooded basin in the south-west
--   * the Rootway, giant roots bridging the flooded ravine in the north-east
--   * the Whisperdeep, a tunnel cut back into the cavern wall
--   * a chamber hidden BEHIND one of the Weeping Cliff falls
--
-- Anything that carves terrain is followed by Terra.reseal in the caller.

local L = require(script.Parent.Lib)
local F = require(script.Parent.Field)
local A = require(script.Parent.Arch)
local P = require(script.Parent.Props)
local C = require(script.Parent.Creature)
local Fl = require(script.Parent.Flora)

local M = {}
local T = workspace.Terrain

local function g(x, z) return F.ground(x, z, F.ceiling(x, z)) end

function M.run()
	local root = workspace.GameWorld.LushGardens
	local reg = L.folder(root, "Regions")
	reg:ClearAllChildren()
	local caves = L.folder(root, "Caves")
	caves:ClearAllChildren()
	local rng = Random.new(80808)
	local log = {}

	----------------------------------------------------------------------------
	-- 1. THE DROWNED COLONNADE
	----------------------------------------------------------------------------
	do
		local f = L.folder(reg, "DrownedColonnade")
		local cx, cz = F.SUNKEN.X, F.SUNKEN.Y
		-- two ranks of columns marching across the flooded plaza, most of them broken
		local ang = math.rad(28)
		local dx, dz = math.cos(ang), math.sin(ang)
		local px, pz = -dz, dx
		local n = 11
		for i = 0, n - 1 do
			local t = (i - (n - 1) / 2) * 46
			for _, s in ipairs({-1, 1}) do
				local x = cx + dx * t + px * s * 40
				local z = cz + dz * t + pz * s * 40
				local gy = g(x, z)
				-- height falls off toward the middle of the basin: the deeper it stood,
				-- the more of it has come down
				local broken = rng:NextNumber()
				local h = broken < 0.28 and rng:NextNumber(8, 16)
					or broken < 0.62 and rng:NextNumber(22, 34) or rng:NextNumber(40, 54)
				A.column(f, L.wcf(x, gy - 1, z), h, rng:NextNumber(5, 7),
					{color = L.C.WeatheredStone, mat = L.M.Stone, trimColor = L.C.MossStone, fluted = true})
				-- a surviving stretch of architrave between tall neighbours
				if h > 38 and i < n - 1 and rng:NextNumber() < 0.5 then
					local x2 = cx + dx * (t + 46) + px * s * 40
					local z2 = cz + dz * (t + 46) + pz * s * 40
					L.beam(f, "Architrave", L.wv(x, gy - 1 + h + 2, z), L.wv(x2, gy - 1 + h + 2, z2),
						7, 5, L.C.WeatheredStone, L.M.Stone, {solid = true})
				end
				-- fallen drums in the water
				if broken < 0.5 then
					for k = 1, rng:NextInteger(1, 3) do
						local fx = x + rng:NextNumber(-16, 16)
						local fz = z + rng:NextNumber(-16, 16)
						L.post(f, "FallenDrum", L.wcf(fx, g(fx, fz) + 2, fz)
							* CFrame.Angles(math.rad(90), rng:NextNumber(0, 6), 0),
							rng:NextNumber(6, 12), rng:NextNumber(5, 7), L.C.MossStone, L.M.Stone, {solid = true})
					end
				end
			end
		end
		-- a statue on each island, facing the middle
		for i, isl in ipairs({{-1010, 860}, {-846, 986}, {-960, 1046}, {-1060, 950}}) do
			local gy = g(isl[1], isl[2])
			local topY = C.pedestal(f, L.wv(isl[1], gy, isl[2]), 16, 16, 10, {seed = i, glow = L.C.GlowCyan})
			local face = math.atan2(cz - isl[2], cx - isl[1])
			local mo
			if i % 2 == 0 then
				mo = C.owl(f, CFrame.new(L.wv(isl[1], 0, isl[2]).X, L.ORIGIN.Y + topY, L.wv(isl[1], 0, isl[2]).Z)
					* CFrame.Angles(0, -face, 0), 1.2, {seed = i, eyeGlow = L.C.GlowGold})
			else
				mo = C.quadruped(f, CFrame.new(L.wv(isl[1], 0, isl[2]).X, L.ORIGIN.Y + topY, L.wv(isl[1], 0, isl[2]).Z)
					* CFrame.Angles(0, -face, 0), 1.1, {style = "doe", seed = i})
			end
			C.weather(mo, {seed = i * 3, amount = 0.4, vines = 3})
		end
		log[#log + 1] = "Drowned Colonnade: 22 columns standing in the flood, 4 island statues"
	end

	----------------------------------------------------------------------------
	-- 2. THE ROOTWAY -- giant roots bridging the flooded ravine
	----------------------------------------------------------------------------
	do
		local f = L.folder(reg, "Rootway")
		local A2, B2 = F.ROOTWAY_A, F.ROOTWAY_B
		local ang = math.atan2(B2.Y - A2.Y, B2.X - A2.X) + math.pi / 2
		local ox, oz = math.cos(ang), math.sin(ang)
		local crossings = 0
		for i = 1, 4 do
			local t = i / 5
			local mx = A2.X + (B2.X - A2.X) * t
			local mz = A2.Y + (B2.Y - A2.Y) * t
			-- the two shoulders either side of the slot
			local ax, az = mx + ox * 105, mz + oz * 105
			local bx, bz = mx - ox * 105, mz - oz * 105
			local ay, by = g(ax, az), g(bx, bz)
			local deckY = math.max(ay, by) + 4
			-- the root itself: a single great arc from shoulder to shoulder
			local pts = {
				L.wv(ax, ay - 6, az),
				L.wv(mx + ox * 46, deckY + 10, mz + oz * 46),
				L.wv(mx, deckY + 16, mz),
				L.wv(mx - ox * 46, deckY + 10, mz - oz * 46),
				L.wv(bx, by - 6, bz),
			}
			P.root(f, pts, 9, 6, {color = L.C.Root, mat = Enum.Material.Wood, steps = 18,
				name = "GreatRoot", rootlets = 8, seed = i * 7, joints = true})
			-- a plank walkway laid along the top of it, so it is actually crossable
			local prev
			for k = 0, 22 do
				local p = L.spline(pts, k / 22) + Vector3.new(0, 8, 0)
				if prev then
					local d = p - prev
					if d.Magnitude > 0.3 then
						local cf = CFrame.lookAt((p + prev) / 2, p)
						L.box(f, "RootPlank", cf, Vector3.new(13, 1.2, d.Magnitude + 0.8),
							P.jitterCol(L.C.WoodPale, rng, 16), Enum.Material.WoodPlanks, {solid = true})
						for _, s in ipairs({1, -1}) do
							L.post(f, "RopePost", cf * CFrame.new(s * 6, 2.4, 0), 4.4, 0.7, L.C.Wood, Enum.Material.Wood, {shadow = false})
							L.tube(f, "Rope", prev + Vector3.new(0, 12.4, 0), p + Vector3.new(0, 12.4, 0), 0.3,
								L.C.BarkPale, Enum.Material.Fabric, {collide = false, shadow = false})
						end
					end
				end
				prev = p
			end
			-- lanterns hung from the root, and a landing at each end
			for _, e in ipairs({{ax, az, ay}, {bx, bz, by}}) do
				L.box(f, "RootLanding", L.wcf(e[1], e[3] + 1, e[2]), Vector3.new(22, 3, 22),
					L.C.WeatheredStone, L.M.Stone, {solid = true})
				P.lampPost(f, L.wv(e[1], e[3] + 2.5, e[2]), 11, {color = L.C.GlowCyan, brightness = 2.0, range = 28})
			end
			P.hangingLantern(f, L.spline(pts, 0.5) + Vector3.new(0, 4, 0), 4,
				{scale = 0.9, color = L.C.GlowGold, brightness = 2.2, range = 34})
			crossings = crossings + 1
		end
		log[#log + 1] = string.format("Rootway: %d giant-root bridges with plank decks over the flooded ravine", crossings)
	end

	----------------------------------------------------------------------------
	-- 3. THE WHISPERDEEP -- a tunnel cut back into the cavern wall
	----------------------------------------------------------------------------
	do
		local f = L.folder(caves, "Whisperdeep")
		local sx, sz = F.WHISPER.X, F.WHISPER.Y
		-- drive the tunnel inward from the wall face toward the middle of the map
		local d = Vector2.new(-sx, -sz).Unit
		local mouthX, mouthZ = sx + d.X * 150, sz + d.Y * 150
		local mouthY = g(mouthX, mouthZ)
		local pts = {}
		for i = 0, 7 do
			local t = i / 7
			pts[#pts + 1] = Vector3.new(
				mouthX - d.X * 210 * t + math.sin(t * 5) * 46,
				mouthY + 2 + math.sin(t * 3) * 8,
				mouthZ - d.Y * 210 * t + math.cos(t * 4) * 40)
		end
		for i = 0, 46 do
			local p = L.spline(pts, i / 46)
			T:FillBlock(CFrame.new(L.wv(p.X, p.Y + 8, p.Z)), Vector3.new(34, 30, 34), Enum.Material.Air)
			if i % 6 == 0 then
				Fl.crystals(f, L.wv(p.X + rng:NextNumber(-11, 11), p.Y - 2, p.Z + rng:NextNumber(-11, 11)),
					{seed = i, count = 5, spread = 6, minH = 5, maxH = 18,
					color = (i % 12 == 0) and L.C.GlowGreen or L.C.GlowCyan, brightness = 2.0, range = 40})
			end
		end
		-- a shrine at the far end
		local e = pts[#pts]
		L.box(f, "ShrineFloor", L.wcf(e.X, e.Y - 1, e.Z), Vector3.new(26, 3, 26), L.C.WeatheredStone, L.M.Stone, {solid = true})
		P.carving(f, L.wcf(e.X, e.Y + 9, e.Z), 12, 16, {glow = L.C.GlowGreen, seed = 3})
		L.glow(f, "DeepLight", L.wcf(e.X, e.Y + 8, e.Z), Vector3.new(4, 5, 4), L.C.GlowGreen, 3.0, 60, "blob")
		P.brazier(f, L.wv(e.X + 9, e.Y, e.Z), {fire = L.C.GlowGreen})
		P.brazier(f, L.wv(e.X - 9, e.Y, e.Z), {fire = L.C.GlowGreen})
		log[#log + 1] = "Whisperdeep: a 210-stud tunnel into the wall, crystal-lit, with a shrine at the end"
	end

	----------------------------------------------------------------------------
	-- 4. THE CHAMBER BEHIND THE FALLS
	----------------------------------------------------------------------------
	do
		local f = L.folder(caves, "BehindTheFalls")
		local cx, cz = F.WEEPING.X, F.WEEPING.Y
		local facing = math.atan2(0 - cz, 0 - cx)
		local a = facing - 0.10                    -- behind WeepingFall4
		local dx, dz = math.cos(a), math.sin(a)
		-- the chamber sits INSIDE the cliff, entered from the ledge beside the plunge
		local ledgeX, ledgeZ = cx + dx * 236, cz + dz * 236
		local ledgeY = g(ledgeX, ledgeZ)
		for i = 0, 12 do
			local t = i / 12
			local px = cx + dx * (232 - t * 78)
			local pz = cz + dz * (232 - t * 78)
			T:FillBlock(CFrame.new(L.wv(px, ledgeY + 12 + t * 6, pz)), Vector3.new(30, 26, 30), Enum.Material.Air)
		end
		local ex, ez = cx + dx * 154, cz + dz * 154
		L.box(f, "ChamberFloor", L.wcf(ex, ledgeY + 4, ez), Vector3.new(34, 3, 34), L.C.WeatheredStone, L.M.Stone, {solid = true})
		Fl.crystals(f, L.wv(ex, ledgeY + 5, ez), {seed = 5, count = 7, spread = 11, minH = 6, maxH = 22,
			color = L.C.GlowPink, brightness = 2.4, range = 48})
		local topY = C.pedestal(f, L.wv(ex, ledgeY + 5, ez), 12, 12, 8, {seed = 9, glow = L.C.GlowPink})
		local mo = C.quadruped(f, CFrame.new(L.wv(ex, 0, ez).X, L.ORIGIN.Y + topY, L.wv(ex, 0, ez).Z)
			* CFrame.Angles(0, -a + math.pi, 0), 1.0, {style = "cat", seed = 4, eyeGlow = L.C.GlowPink})
		C.weather(mo, {seed = 2, amount = 0.35, vines = 2})
		-- a ledge to walk in on
		L.box(f, "ApproachLedge", L.wcf(ledgeX, ledgeY + 1, ledgeZ), Vector3.new(20, 3, 20), L.C.GreyStone, L.M.Stone, {solid = true})
		log[#log + 1] = "A hidden chamber behind the Weeping Cliffs falls, reached by a ledge beside the plunge"
	end

	----------------------------------------------------------------------------
	-- 5. THE FUNGAL HOLLOW SHRINE
	----------------------------------------------------------------------------
	do
		local f = L.folder(reg, "FungalHollow")
		local cx, cz = F.FUNGAL.X, F.FUNGAL.Y
		local gy = g(cx, cz)
		L.box(f, "ShrineDais", L.wcf(cx, gy + 1.5, cz), Vector3.new(40, 4, 40), L.C.WeatheredStone, L.M.Stone, {solid = true})
		for i = 0, 5 do
			local a = math.rad(i * 60)
			A.column(f, L.wcf(cx + math.cos(a) * 15, gy + 3, cz + math.sin(a) * 15), 22, 3.5,
				{color = L.C.PaleStone, mat = L.M.Stone, fluted = true})
		end
		L.cyl(f, "ShrineRing", L.wcf(cx, gy + 27, cz) * CFrame.Angles(0, 0, math.rad(90)), 3, 40,
			L.C.PaleStone, L.M.Stone, {solid = true})
		L.glow(f, "HollowLight", L.wcf(cx, gy + 16, cz), Vector3.new(6, 8, 6), L.C.GlowCyan, 3.4, 80, "blob")
		for i = 1, 10 do
			local a = rng:NextNumber(0, 6.283)
			local r = rng:NextNumber(46, 120)
			Fl.giantMushroom(f, L.wv(cx + math.cos(a) * r, g(cx + math.cos(a) * r, cz + math.sin(a) * r), cz + math.sin(a) * r),
				{seed = i * 5, height = rng:NextNumber(34, 58), capR = rng:NextNumber(16, 28),
				cap = rng:NextNumber() < 0.5 and L.C.GlowPink or L.C.PetalPale, gill = L.C.GlowCyan})
		end
		log[#log + 1] = "Fungal Hollow: a ringed shrine among 10 great mushrooms"
	end

	local parts = 0
	for _, fol in ipairs({reg, caves}) do
		for _, d in ipairs(fol:GetDescendants()) do if d:IsA("BasePart") then parts = parts + 1 end end
	end
	return table.concat(log, "\n") .. string.format("\n%d parts", parts)
end

return M
