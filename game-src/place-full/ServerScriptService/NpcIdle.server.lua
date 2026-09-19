--[[
	NpcIdle.lua
	Idle motion for every NPC in the place that is NOT a shopkeeper.

	WHY PROCEDURAL, NOT AN ANIMATION. Every character here -- the R15 ones included --
	is a bag of fully ANCHORED parts with ZERO Motor6D joints. A Humanoid animation
	drives Motor6D transforms, so loading one onto these would play silently and move
	nothing at all. The only thing that can move them is writing CFrames, which is
	exactly what ServerScriptService.EggStallIdle already does for the egg displays;
	this follows that script's shape deliberately.

	SERVER-SIDE, like EggStallIdle and NightLights, so every player sees the same pose.
	That costs replication, so every NPC is PROXIMITY GATED independently -- an NPC with
	nobody near it writes nothing. The two worlds are 8,000 studs apart, so in practice
	only a couple are ever live at once.

	SHOPKEEPERS ARE EXCLUDED ON PURPOSE. Rocco, Marco, Enzo, Gino and Lil Miss (and
	their five tundra copies) stand behind counters with their stock; bobbing them
	desyncs them from the geometry they are posed against.

	BASE POSES ARE CAPTURED ONCE. Never re-read a part's CFrame while animating and
	feed it back in -- that integrates the offset every frame and the NPC walks away.
	If a model streams out the entry is dropped and re-resolved from scratch, which is
	safe because streamed-in parts arrive at their saved pose.

	ELDER TUNG ROCKS INSTEAD OF BOBBING. He is sitting in GameWorld.RockingChair, which
	is a SEPARATE model from him, so his profile pulls the chair in with `rides` and moves
	the two as one rigid group -- bobbing or swaying him alone lifts him out of the seat.
	The rock is a roll, not a spin: see rockGeometry() and the note above rockAngle().
]]

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local TAU = math.pi * 2
local PROXIMITY_RANGE = 90
local PROXIMITY_CHECK_EVERY = 10
local RESOLVE_EVERY = 120
local rad = math.rad

-- Elder Tung's beard is the one piece of him that does NOT ride the chair rigidly: it
-- hangs off his jaw, so it trails the rock by a fraction of a second. His mustache is
-- deliberately excluded -- it is short and stiff and would only detach from his lip.
local TUNG_BEARD = { beard_jaw = true, beard_mid = true, beard_fall = true, beard_tip = true }

-- Michel's groups, matched by the part names his builder gave them.
local MICHEL_HEAD = { Head = true, Crown = true, Nape = true, Neck = true, Cere = true,
                      BeakUpper = true, BeakHook = true, BeakLower = true,
                      Brow = true, Eye = true, Pupil = true, Nostril = true }
local MICHEL_WINGS = { WingUpper = true, Covert = true, Secondary = true,
                       WingMid = true, WingTip = true, ShoulderHump = true }
local MICHEL_TAIL = { TailFeather = true, TailTip = true }

-- Gianluca, Maxwell and the TUNDRA Elder Tung are deliberately absent. Their idles were
-- one sine on a rigid model, which read as mechanical, and they were cut rather than
-- retuned. Leaving a profile out is the whole removal -- nothing else here refers to them,
-- and an NPC with no profile is simply never written to.
local PROFILES = {
	{
		name = "Elder Tung (valley)",
		path = { "GameWorld", "ElderTung" },
		-- SEATED: no bob, no sway, no head turns. The chair does all of it.
		rides = { "GameWorld", "RockingChair" },
		rock = { amp = rad(4.5), period = 3.8, dwell = 0.8 },
		beard = { names = TUNG_BEARD, trail = 0.6, lag = 0.18 },
	},
	{
		name = "Michel",
		path = { "GameWorld", "FrozenTundra", "Michel" },
		-- birds do not sway their heads, they SNAP and hold. See snapYaw() below.
		bob = { amp = 0.045, period = 2.8 },
		yaw = { amp = rad(1.2), period = 8.0 },
		roll = { amp = rad(0.6), period = 9.5 },
		head = { names = MICHEL_HEAD, snapAmp = rad(38), snapPeriod = 3.2, snapEase = 0.18,
		         pitchAmp = rad(5), pitchPeriod = 4.3 },
		wings = { names = MICHEL_WINGS, period = 15.0, liftAmp = 0.16 },
		tail = { names = MICHEL_TAIL, yawAmp = rad(5), yawPeriod = 5.5 },
	},
	{
		name = "SecretChim",
		path = { "GameWorld", "SecretChim" },
		bob = { amp = 0.06, period = 3.0 },
		yaw = { amp = rad(3.5), period = 6.5 },
		roll = { amp = rad(1.4), period = 8.0 },
	},
}

local function resolvePath(path)
	local node = Workspace
	for _, seg in ipairs(path) do
		node = node:FindFirstChild(seg)
		if not node then return nil end
	end
	return node
end

-- pivot at the horizontal centre of the pose, down at its lowest part: yaw and roll then
-- read as the figure shifting its weight rather than orbiting some point in the floor
local function pivotOf(entries)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, e in ipairs(entries) do
		lo = lo:Min(e.cf0.Position)
		hi = hi:Max(e.cf0.Position)
	end
	if lo.X > hi.X then return CFrame.new() end
	return CFrame.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
end

-- ...but a beard swings from where it is ATTACHED, which is the TOP of the group. Same
-- pivot, hung from hi.Y instead of lo.Y.
local function hangPivotOf(entries)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, e in ipairs(entries) do
		lo = lo:Min(e.cf0.Position)
		hi = hi:Max(e.cf0.Position)
	end
	if lo.X > hi.X then return CFrame.new() end
	return CFrame.new((lo.X + hi.X) / 2, hi.Y, (lo.Z + hi.Z) / 2)
end

-- MEASURED off the chair's own rockers rather than hardcoded, so the rock survives the
-- chair being nudged, turned or rebuilt. Each runner is a faceted arc -- five 0.9-stud
-- blocks tilted 0, +/-9 and +/-18 degrees -- and four things come out of it:
--   axis     the chair's left-right axis, which the rock turns about
--   forward  the way the runners point, which is where a forward tip travels
--   radius   the radius of curvature of the arc (about 5 studs on this chair)
--   pivot    the CENTRE of that arc, which sits `radius` studs ABOVE the floor contact,
--            up around his chest -- not at the seat, and not down in the deck
-- Turning about that centre slides the arc along itself, so the runners stay kissing the
-- deck at every angle instead of digging in at one end and lifting off at the other.
local function rockGeometry(model)
	local rockers = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "Rocker" then table.insert(rockers, d) end
	end
	if #rockers < 2 then return nil end

	-- the flattest segments are the ones actually on the floor, and being untilted their
	-- CFrame is the chair's own frame
	local flat = rockers[1]
	for _, p in ipairs(rockers) do
		if p.CFrame.UpVector.Y > flat.CFrame.UpVector.Y then flat = p end
	end
	local axis = flat.CFrame.RightVector
	local fwd = Vector3.new(flat.CFrame.LookVector.X, 0, flat.CFrame.LookVector.Z)
	if fwd.Magnitude < 1e-4 then return nil end

	-- chord = 2*R*sin(dtheta/2) between two segments whose up-vectors differ by dtheta.
	-- Dropping the chord's component along `axis` removes the sideways gap between the two
	-- runners, so ANY pair of segments works, not only two on the same runner.
	local radius, widest = nil, 0
	for _, p in ipairs(rockers) do
		local dtheta = math.acos(math.clamp(p.CFrame.UpVector:Dot(flat.CFrame.UpVector), -1, 1))
		if dtheta > widest then
			local d = p.Position - flat.Position
			d -= axis * d:Dot(axis)
			radius, widest = d.Magnitude / (2 * math.sin(dtheta / 2)), dtheta
		end
	end
	if not radius or radius <= 0 then return nil end

	local contactY, sum, n = math.huge, Vector3.zero, 0
	for _, p in ipairs(rockers) do
		contactY = math.min(contactY, p.Position.Y - p.Size.Y / 2)
		if p.CFrame.UpVector.Y >= flat.CFrame.UpVector.Y - 1e-3 then
			sum, n = sum + p.Position, n + 1
		end
	end
	local mid = sum / n

	return {
		axis = axis,
		forward = fwd.Unit,
		radius = radius,
		pivot = CFrame.new(mid.X, contactY + radius, mid.Z),
	}
end

local function build(profile)
	local root = resolvePath(profile.path)
	if not root then return nil end

	local rides = profile.rides and resolvePath(profile.rides) or nil
	if profile.rides and not rides then
		warn(("[NpcIdle] %s rides %s, which is missing -- leaving him still")
			:format(profile.name, table.concat(profile.rides, ".")))
		return nil
	end

	local all, head, wings, tail, beard = {}, {}, {}, {}, {}
	local function consider(part)
		-- The name tag and the prompt anchor are UI hung off the model, not anatomy. A
		-- 0.05-stud bob never showed on them; a rock swings them visibly, so a rocking
		-- profile drops them from `all` and they are simply never written.
		local isUi = part.Name == "PromptPart" or part.Name == "NameAnchor"
		if isUi and profile.rock then return end

		local entry = { part = part, cf0 = part.CFrame }
		table.insert(all, entry)
		if isUi then return end

		if profile.head and profile.head.names[part.Name] then
			table.insert(head, entry)
		elseif profile.wings and profile.wings.names[part.Name] then
			table.insert(wings, entry)
		elseif profile.tail and profile.tail.names[part.Name] then
			table.insert(tail, entry)
		elseif profile.beard and profile.beard.names[part.Name] then
			table.insert(beard, entry)
		end
	end

	local function gather(node)
		if node:IsA("BasePart") then consider(node) end
		for _, d in ipairs(node:GetDescendants()) do
			if d:IsA("BasePart") then consider(d) end
		end
	end
	gather(root)
	if rides then gather(rides) end
	if #all == 0 then return nil end

	local rock
	if profile.rock then
		rock = rockGeometry(rides or root)
		if not rock then
			warn(("[NpcIdle] %s: found no rocker arc to rock about -- leaving him still")
				:format(profile.name))
			return nil
		end
	end

	return {
		profile = profile,
		root = root,
		rides = rides,
		all = all,
		head = head,
		wings = wings,
		tail = tail,
		beard = beard,
		rock = rock,
		pivot = pivotOf(all),
		headPivot = #head > 0 and pivotOf(head) or nil,
		beardPivot = #beard > 0 and hangPivotOf(beard) or nil,
		phase = (#profile.name % 7) * 0.9,
		active = false,
	}
end

local states = {}
local function resolveAll()
	for _, profile in ipairs(PROFILES) do
		local s = states[profile]
		if not s or not s.root or not s.root.Parent or (s.rides and not s.rides.Parent) then
			states[profile] = build(profile)
		end
	end
end
resolveAll()

do
	local live = {}
	for p, s in pairs(states) do if s then table.insert(live, p.name) end end
	table.sort(live)
	print(("[NpcIdle] animating %d NPCs: %s"):format(#live, table.concat(live, ", ")))
end

-- deterministic hash so every server picks the same look-around sequence
local function hash01(n)
	local x = math.sin(n * 12.9898) * 43758.5453
	return x - math.floor(x)
end

-- snap-and-hold: ease quickly to a new angle, then sit on it. A sine here would read as a
-- fish, not a bird.
local function snapYaw(t, period, ease, amp)
	local pos = t / period
	local step = math.floor(pos)
	local frac = pos - step
	local a = (hash01(step) * 2 - 1) * amp
	local b = (hash01(step + 1) * 2 - 1) * amp
	local e = math.clamp(frac / ease, 0, 1)
	e = e * e * (3 - 2 * e)
	return a + (b - a) * e
end

-- A rocking chair is a pendulum: it HANGS at each extreme and hurries through the middle.
-- A bare sine spends equal time everywhere and reads as a metronome, so the sine is bent
-- by an exponent below 1, which pushes the curve out towards its own peaks.
local function rockAngle(t, r)
	local s = math.sin(TAU * t / r.period)
	return r.amp * math.sign(s) * math.abs(s) ^ r.dwell
end

local frame = 0
RunService.Heartbeat:Connect(function()
	frame += 1

	if frame % RESOLVE_EVERY == 0 then
		resolveAll()
	end

	if frame % PROXIMITY_CHECK_EVERY == 0 then
		local chars = {}
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then table.insert(chars, hrp.Position) end
		end
		for _, s in pairs(states) do
			if s then
				s.active = false
				local origin = s.pivot.Position
				for _, p in ipairs(chars) do
					if (p - origin).Magnitude <= PROXIMITY_RANGE then
						s.active = true
						break
					end
				end
			end
		end
	end

	local t = os.clock()

	for _, s in pairs(states) do
		if s and s.active and s.root and s.root.Parent then
			local pf = s.profile
			local ph = s.phase

			local bodyM, rockA
			if s.rock then
				-- Rolling, not spinning. Turning by `a` about the arc's centre keeps the
				-- runners on the deck, but the chair ALSO has to travel radius*a along
				-- them -- that shuffle across the porch is most of what says "rocking".
				rockA = rockAngle(t + ph, pf.rock)
				bodyM = CFrame.new(s.rock.forward * (s.rock.radius * rockA))
					* s.rock.pivot
					* CFrame.fromAxisAngle(s.rock.axis, rockA)
					* s.rock.pivot:Inverse()
			else
				local bobY = pf.bob.amp * math.sin(TAU * t / pf.bob.period + ph)
				local yaw = pf.yaw.amp * math.sin(TAU * t / pf.yaw.period + ph)
				local roll = pf.roll.amp * math.sin(TAU * t / pf.roll.period + ph * 1.7)
				bodyM = s.pivot
					* CFrame.new(0, bobY, 0)
					* CFrame.Angles(0, yaw, 0)
					* CFrame.Angles(0, 0, roll)
					* s.pivot:Inverse()
			end

			-- The beard is always a moment behind the chair. Driving it off the DIFFERENCE
			-- between the rock now and the rock `lag` ago means it goes to zero by itself
			-- wherever the chair is momentarily still -- no separate damping to tune.
			local beardM
			if rockA and s.beardPivot and pf.beard then
				local trail = (rockAngle(t + ph - pf.beard.lag, pf.rock) - rockA) * pf.beard.trail
				beardM = s.beardPivot
					* CFrame.fromAxisAngle(s.rock.axis, trail)
					* s.beardPivot:Inverse()
			end

			local headM
			if s.headPivot and pf.head then
				local h = pf.head
				local hy = h.snapAmp
					and snapYaw(t + ph, h.snapPeriod, h.snapEase, h.snapAmp)
					or h.yawAmp * math.sin(TAU * t / h.yawPeriod + ph)
				local hp = h.pitchAmp * math.sin(TAU * t / h.pitchPeriod + ph * 2.3)
				headM = s.headPivot * CFrame.Angles(0, hy, 0) * CFrame.Angles(hp, 0, 0) * s.headPivot:Inverse()
			end

			local wingM
			if pf.wings and #s.wings > 0 then
				-- a settle every wings.period seconds, not a constant flap
				local u = (t + ph) % pf.wings.period
				local window = pf.wings.period * 0.13
				if u < window then
					local k = math.sin((u / window) * math.pi)
					wingM = CFrame.new(0, pf.wings.liftAmp * k, 0)
				end
			end

			local tailM
			if pf.tail and #s.tail > 0 then
				local ty = pf.tail.yawAmp * math.sin(TAU * t / pf.tail.yawPeriod + ph)
				tailM = s.pivot * CFrame.Angles(0, ty, 0) * s.pivot:Inverse()
			end

			for _, e in ipairs(s.all) do
				if e.part.Parent then
					e.part.CFrame = bodyM * e.cf0
				end
			end
			if headM then
				for _, e in ipairs(s.head) do
					if e.part.Parent then e.part.CFrame = bodyM * headM * e.cf0 end
				end
			end
			if wingM then
				for _, e in ipairs(s.wings) do
					if e.part.Parent then e.part.CFrame = bodyM * wingM * e.cf0 end
				end
			end
			if tailM then
				for _, e in ipairs(s.tail) do
					if e.part.Parent then e.part.CFrame = bodyM * tailM * e.cf0 end
				end
			end
			if beardM then
				for _, e in ipairs(s.beard) do
					if e.part.Parent then e.part.CFrame = bodyM * beardM * e.cf0 end
				end
			end
		end
	end
end)
