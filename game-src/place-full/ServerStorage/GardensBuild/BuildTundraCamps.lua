-- BuildTundraCamps -- the six World 2 player plots.
--
-- Mirrors WORLD 1's camp LAYOUT (pine ring, bedroll, lantern post, fire) built from
-- WORLD 2's own assets. No World 1 props are cloned, and there is no igloo.
--
-- PROTECTED, never touched: Platform, PlatformRim, Pads, PlotBoard, Campfire,
-- CampDressing, PitStone -- all looked up by name from 20+ scripts.

local M = {}

local PINES = {
	Vector3.new(-22.9, 0, -24.3), Vector3.new(34.4, 0, 15.9), Vector3.new(4.1, 0, 31.9),
	Vector3.new(-27.9, 0, 13.2), Vector3.new(14.4, 0, -33.4),
}
local BED  = Vector3.new(-24.4, 0, -1.2)
local LAMP = Vector3.new(18.0, 0, -12.9)
local PINE_H = 22.3

-- A proper campfire, built AROUND the protected Campfire part (which stays exactly
-- where it is -- FusionHandler, OfferingHandler, IncomeLoop, PlotEquipPad and the
-- banking client all find it by name).
--
-- The old one was a bare glowing box with two logs lying flat beside it, which is why
-- it did not read as a fire. A campfire reads from three things: a charred bed, logs
-- LEANING INTO a teepee, and embers.
local function buildFire(parent, fire, rng)
	-- TWO SEPARATE SCALES, deliberately. The wood and the flame want to go in opposite
	-- directions: chunky logs read as a bonfire/woodpile, whereas a camp fire is a small
	-- stack of sticks with a big flame off it. So the timber is sized DOWN and the fire
	-- effect is sized UP, rather than one factor dragging both together.
	local WOOD = 1.0     -- logs: thin and short
	local RING = 1.8     -- ash bed + hearth stones, kept wide enough to frame the flame

	-- The Campfire part is PROTECTED by name (FusionHandler, OfferingHandler, IncomeLoop,
	-- PlotEquipPad, CampfireBankClient all find it) but nothing reads its size, so the
	-- flame itself can be grown freely.
	-- THE FLAME IS THE `Fire` OBJECT, NOT THE PART.
	-- Scaling the Campfire part up just makes a bigger glowing CUBE sitting over the
	-- logs -- which is exactly how it looked at 6.6 studs. The part's only job is to be
	-- a small round glow core and carry the light; all the actual fire comes from the
	-- Fire effect and the embers, which is what gets scaled up instead.
	fire.Shape = Enum.PartType.Ball
	fire.Size = Vector3.new(2.6, 2.6, 2.6)
	fire.Transparency = 0.55
	local pl = fire:FindFirstChildOfClass("PointLight")
	if pl then
		pl.Range = 48
		pl.Brightness = 5.0
	end
	local ff = fire:FindFirstChildOfClass("Fire")
	if ff then
		ff.Size = 28          -- the visible flame
		ff.Heat = 24
		ff.Color = Color3.fromRGB(255, 172, 62)
		ff.SecondaryColor = Color3.fromRGB(226, 78, 24)
	end

	local base = fire.Position
	local ground = base - Vector3.new(0, fire.Size.Y * 0.5 + 0.4, 0)

	local bed = Instance.new("Part")
	bed.Name = "FireBedAsh"
	bed.Shape = Enum.PartType.Cylinder
	bed.Size = Vector3.new(0.6, 6.2 * RING, 6.2 * RING)
	bed.CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90))
	bed.Anchored = true; bed.CanCollide = false; bed.CanQuery = false; bed.CastShadow = false
	bed.Material = Enum.Material.Slate
	bed.Color = Color3.fromRGB(44, 38, 36)
	bed.Parent = parent

	-- hearth stones holding the fire in
	for i = 0, 9 do
		local a = math.rad(i * 36 + rng:NextNumber(-6, 6))
		local r = 3.4 * RING
		local st = Instance.new("Part")
		st.Name = "HearthStone"
		st.Size = Vector3.new(rng:NextNumber(1.5, 2.3), rng:NextNumber(1.0, 1.6), rng:NextNumber(1.5, 2.3))
		st.CFrame = CFrame.new(ground + Vector3.new(math.cos(a) * r, 0.4, math.sin(a) * r))
			* CFrame.Angles(0, rng:NextNumber(0, 6.283), 0)
		st.Anchored = true; st.CanCollide = false; st.CanQuery = false
		st.Material = Enum.Material.Slate
		st.Color = Color3.fromRGB(96, 99, 103)
		st.Parent = parent
	end

	-- glowing coals across the bed
	for i = 1, 11 do
		local a = rng:NextNumber(0, 6.283)
		local r = rng:NextNumber(0, 2.4 * RING)
		local c = Instance.new("Part")
		c.Name = "Ember"
		c.Size = Vector3.new(rng:NextNumber(0.7, 1.5), 0.45, rng:NextNumber(0.7, 1.5))
		c.CFrame = CFrame.new(ground + Vector3.new(math.cos(a) * r, 0.35, math.sin(a) * r))
			* CFrame.Angles(0, rng:NextNumber(0, 6.283), 0)
		c.Anchored = true; c.CanCollide = false; c.CanQuery = false; c.CastShadow = false
		c.Material = Enum.Material.Neon
		c.Color = Color3.fromRGB(226, 106, 40)
		c.Transparency = 0.12
		c.Parent = parent
	end

	-- SMALLER TIMBER: thin sticks leaning in, sitting low so the flame rises past them
	for i = 0, 6 do
		local a = math.rad(i * (360 / 7) + rng:NextNumber(-8, 8))
		local out = 2.6 * WOOD
		local log = Instance.new("Part")
		log.Name = "FireLog"
		log.Size = Vector3.new(0.75 * WOOD, 5.2 * WOOD, 0.75 * WOOD)
		log.CFrame = CFrame.new(ground + Vector3.new(math.cos(a) * out, 1.9 * WOOD, math.sin(a) * out))
			* CFrame.Angles(0, -a, 0)
			* CFrame.Angles(0, 0, math.rad(40))
		log.Anchored = true; log.CanCollide = false; log.CanQuery = false
		log.Material = Enum.Material.Wood
		log.Color = Color3.fromRGB(74, 54, 40)
		log.Parent = parent
		local char = log:Clone()
		char.Name = "FireLogCharred"
		char.Size = Vector3.new(0.82 * WOOD, 1.9 * WOOD, 0.82 * WOOD)
		char.CFrame = log.CFrame * CFrame.new(0, -1.7 * WOOD, 0)
		char.Color = Color3.fromRGB(38, 32, 30)
		char.Material = Enum.Material.Slate
		char.Parent = parent
	end

	-- embers, thicker and faster to match the bigger flame
	local e = fire:FindFirstChild("Embers")
	if not e then
		e = Instance.new("ParticleEmitter")
		e.Name = "Embers"
		e.Parent = fire
	end
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(255, 168, 74))
	e.LightEmission = 1
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Rate = 38
	e.Lifetime = NumberRange.new(1.5, 3.0)
	e.Speed = NumberRange.new(7, 14)
	e.SpreadAngle = Vector2.new(26, 26)
	e.Acceleration = Vector3.new(0, 9, 0)
	e.Drag = 1.3

end

function M.run()
	local ft = workspace.GameWorld.FrozenTundra
	local sa = ft:FindFirstChild("SkipArea")

	local srcSpire, srcTent, srcPole, srcLantern
	for _, d in ipairs(ft:GetDescendants()) do
		if not srcSpire and d.Name == "IceSpire" and d:IsA("BasePart") then srcSpire = d end
		if not srcTent and d.Name == "Tent" and d:IsA("Model") then srcTent = d end
	end
	if sa then
		for _, d in ipairs(sa:GetDescendants()) do
			if not srcPole and d.Name == "LanternPole" then srcPole = d end
			if not srcLantern and d.Name == "Lantern" then srcLantern = d end
		end
	end
	if not (srcSpire and srcTent) then return "missing a World 2 source asset" end

	local built, parts, nudged = 0, 0, 0
	for _, plot in ipairs(workspace.PlayerBases:GetChildren()) do
		local plat = plot:FindFirstChild("Platform")
		if plat and plat.Position.X < -7000 then
			local rng = Random.new(plat.Position.X * 7 + plat.Position.Z)
			local topY = plat.Position.Y + plat.Size.Y / 2

			for _, n in ipairs({"TundraCamp", "IglooDressing", "Igloo", "Tent"}) do
				local o = plot:FindFirstChild(n)
				if o then o:Destroy() end
			end
			local camp = Instance.new("Model"); camp.Name = "TundraCamp"; camp.Parent = plot

			-- Where the sign is, so nothing gets planted through it. The board sits at
			-- radius ~31, which is exactly the band the spires were landing in.
			local board = plot:FindFirstChild("PlotBoard")
			local boardAng, boardR
			if board then
				local bcf = board:GetBoundingBox()
				local d = bcf.Position - plat.Position
				boardAng = math.atan2(d.Z, d.X)
				boardR = math.sqrt(d.X * d.X + d.Z * d.Z)
			end

			-- 1. ice spires at World 1's pine positions.
			--    NO rubble ring: the old SpireBase blocks scattered at radius 29-41
			--    formed a ring of stone-like chunks right round every plot.
			for _, off in ipairs(PINES) do
				local ox, oz = off.X, off.Z
				if boardAng then
					local a = math.atan2(oz, ox)
					local diff = math.abs((a - boardAng + math.pi) % (2 * math.pi) - math.pi)
					-- inside the sign's arc: swing this spire clear of it
					if diff < math.rad(38) then
						local r = math.sqrt(ox * ox + oz * oz)
						local sign = ((a - boardAng + math.pi) % (2 * math.pi) - math.pi) >= 0 and 1 or -1
						local a2 = boardAng + sign * math.rad(46)
						ox, oz = math.cos(a2) * r, math.sin(a2) * r
						nudged = nudged + 1
					end
				end
				local h = PINE_H * rng:NextNumber(0.85, 1.25)
				local c = srcSpire:Clone()
				c.Name = "CampSpire"; c.Parent = camp; c.Anchored = true
				c.Size = srcSpire.Size * (h / srcSpire.Size.Y)
				c.CFrame = CFrame.new(plat.Position.X + ox, topY + c.Size.Y / 2 - 0.8, plat.Position.Z + oz)
					* CFrame.Angles(rng:NextNumber(-0.05, 0.05), rng:NextNumber(0, 6.283), rng:NextNumber(-0.05, 0.05))
			end

			-- Swings a placement out of the sign's arc. The PlotBoard's bearing is PER
			-- PLOT (PlotBoardHandler sites it on each plot's nearest-trail heading), so a
			-- position lifted from World 1 lands on top of the sign on whichever plots
			-- happen to face that way -- which is what put the tent through it.
			local function clearOfSign(ox, oz, halfArcDeg)
				if not boardAng then return ox, oz end
				local a = math.atan2(oz, ox)
				local twoPi = math.pi * 2
				local delta = (a - boardAng + math.pi) - math.floor((a - boardAng + math.pi) / twoPi) * twoPi - math.pi
				if math.abs(delta) < math.rad(halfArcDeg) then
					local r = math.sqrt(ox * ox + oz * oz)
					local a2 = boardAng + (delta >= 0 and 1 or -1) * math.rad(halfArcDeg)
					nudged = nudged + 1
					return math.cos(a2) * r, math.sin(a2) * r
				end
				return ox, oz
			end

			-- 2. tent where World 1 puts its bedroll
			local bx, bz = clearOfSign(BED.X, BED.Z, 46)
			local t = srcTent:Clone(); t.Name = "Tent"; t.Parent = camp
			local _, sz = t:GetBoundingBox()
			t:PivotTo(CFrame.new(plat.Position.X + bx, topY + sz.Y / 2 - 0.5, plat.Position.Z + bz)
				* CFrame.Angles(0, rng:NextNumber(0, 6.283), 0))

			-- 3. lantern post
			if srcPole then
				local p = srcPole:Clone(); p.Name = "LanternPost"; p.Parent = camp; p.Anchored = true
				local lx, lz = clearOfSign(LAMP.X, LAMP.Z, 34)
				p.CFrame = CFrame.new(plat.Position.X + lx, topY + p.Size.Y / 2, plat.Position.Z + lz)
				if srcLantern then
					local l = srcLantern:Clone(); l.Name = "Lantern"; l.Parent = camp; l.Anchored = true
					l.CFrame = CFrame.new(p.Position.X, topY + p.Size.Y + 1.0, p.Position.Z)
				end
			end

			-- 4. a fire that reads as a fire
			local fire = plot:FindFirstChild("Campfire")
			if fire then buildFire(camp, fire, rng) end

			for _, d in ipairs(camp:GetDescendants()) do if d:IsA("BasePart") then parts = parts + 1 end end
			built = built + 1
		end
	end
	return string.format("%d camps rebuilt | no rubble ring | %d spires swung clear of the sign | %d parts (%.0f each)",
		built, nudged, parts, parts / math.max(built, 1))
end

return M
