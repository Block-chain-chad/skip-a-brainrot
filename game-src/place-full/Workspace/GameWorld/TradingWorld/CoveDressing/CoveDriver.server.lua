-- CoveDriver: THE single Heartbeat driver for every piece of Cove dressing animation.
-- One connection, a tag registry, and a sleep gate: with no player within WAKE_RADIUS
-- of the island centre it does zero per-frame work (geometry stays; only motion stops).
-- Convention follows UIKit.Builders.ensureRingDriver: nothing else in CoveDressing may
-- create a loop. Tags (all on parts/models under CoveDressing):
--   CoveOrbit   (Model)  attrs OrbitRadius, OrbitAngle0, OrbitHeight, OrbitRate, SelfSpin
--   CoveSpin    (BasePart) attr SpinRate (deg/s, about own Y at its own position)
--   CoveBreatheT(BasePart) attrs Period, TMin, TMax  (Transparency sine)
--   CoveBreatheH(Highlight) attrs Period, HMin, HMax (FillTransparency sine)
--   CoveBob     (BasePart) attrs Period, Amp, Phase  (vertical bob about captured CFrame)
--   CoveFallScroll(BasePart) attrs FallTop, FallBottom, FallSpeed (studs/s, wraps)
--   CoveAmbience(Sound)  attr TargetVolume (stepped lerp toward target; 0 when asleep)
-- The Eternal Skip's wake trail is driver-owned: pooled rings under CoveDressing.WakePool.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local cd = script.Parent
local C = Vector3.new(8000, 2002, 8000)
local WAKE_RADIUS = 400

local t = 0                -- animation clock, advances only while awake
local awake = false
local lastGate = 0
script:SetAttribute("WorkCount", 0)
script:SetAttribute("Awake", false)

local orbits = {}      -- {model, r, a0, h, rate, selfSpin, baseRot}
local spins = {}       -- {part, rate, pos, baseCF}
local breatheT = {}    -- {part, period, mn, mx}
local breatheH = {}    -- {hl, period, mn, mx}
local bobs = {}        -- {part, period, amp, phase, baseCF}
local falls = {}       -- {part, top, bottom, speed, baseCF, span}
local sounds = {}      -- {sound, target}

local function collect()
	orbits, spins, breatheT, breatheH, bobs, falls, sounds = {}, {}, {}, {}, {}, {}, {}
	for _, m in ipairs(CollectionService:GetTagged("CoveOrbit")) do
		if m:IsDescendantOf(cd) then
			table.insert(orbits, { m = m,
				r = m:GetAttribute("OrbitRadius") or 60,
				a0 = math.rad(m:GetAttribute("OrbitAngle0") or 0),
				h = m:GetAttribute("OrbitHeight") or 2060,
				rate = math.rad(m:GetAttribute("OrbitRate") or 0.9),
				selfSpin = math.rad(m:GetAttribute("SelfSpin") or 0) })
		end
	end
	for _, p in ipairs(CollectionService:GetTagged("CoveSpin")) do
		if p:IsDescendantOf(cd) then
			table.insert(spins, { p = p, rate = math.rad(p:GetAttribute("SpinRate") or 4), base = p.CFrame })
		end
	end
	for _, p in ipairs(CollectionService:GetTagged("CoveBreatheT")) do
		if p:IsDescendantOf(cd) then
			table.insert(breatheT, { p = p, period = p:GetAttribute("Period") or 3.2,
				mn = p:GetAttribute("TMin") or 0.4, mx = p:GetAttribute("TMax") or 0.8 })
		end
	end
	for _, h in ipairs(CollectionService:GetTagged("CoveBreatheH")) do
		if h:IsDescendantOf(cd) then
			table.insert(breatheH, { h = h, period = h:GetAttribute("Period") or 2.4,
				mn = h:GetAttribute("HMin") or 0.6, mx = h:GetAttribute("HMax") or 0.95 })
		end
	end
	for _, p in ipairs(CollectionService:GetTagged("CoveBob")) do
		if p:IsDescendantOf(cd) then
			table.insert(bobs, { p = p, period = p:GetAttribute("Period") or 3,
				amp = p:GetAttribute("Amp") or 0.25, phase = p:GetAttribute("Phase") or 0, base = p.CFrame })
		end
	end
	for _, p in ipairs(CollectionService:GetTagged("CoveFallScroll")) do
		if p:IsDescendantOf(cd) then
			local top = p:GetAttribute("FallTop") or 2002
			local bottom = p:GetAttribute("FallBottom") or 1972
			table.insert(falls, { p = p, top = top, bottom = bottom,
				speed = p:GetAttribute("FallSpeed") or 9, base = p.CFrame, span = top - bottom })
		end
	end
	for _, s in ipairs(CollectionService:GetTagged("CoveAmbience")) do
		if s:IsDescendantOf(workspace) then
			table.insert(sounds, { s = s, target = s:GetAttribute("TargetVolume") or 0.4 })
			s.Volume = 0
		end
	end
end
collect()
task.delay(3, collect) -- late-built dressing chunks

-- Eternal Skip wake trail: pooled flat rings that trail the stone
local skipStone = tw and nil
do
	local es = cd.Parent:FindFirstChild("EternalSkip")
	skipStone = es and es:FindFirstChild("Stone")
end
local pool = Instance.new("Folder"); pool.Name = "WakePool"; pool.Parent = cd
local wakeParts = {}
for i = 1, 8 do
	local w = Instance.new("Part")
	w.Name = "WakeRing"; w.Anchored = true
	w.Shape = Enum.PartType.Cylinder
	w.Size = Vector3.new(0.1, 1.5, 1.5)
	w.Material = Enum.Material.Neon
	w.Color = Color3.fromRGB(180, 240, 245)
	w.Transparency = 1
	w.CanCollide = false; w.CanQuery = false; w.CanTouch = false
	w.CFrame = CFrame.new(8000, 1990, 8000) * CFrame.Angles(0, 0, math.rad(90))
	w.Parent = pool
	wakeParts[i] = { p = w, born = -10 }
end
local wakeIdx, lastWake = 0, 0
local WAKE_LIFE = 1.4

local function anyPlayerNear()
	for _, plr in ipairs(Players:GetPlayers()) do
		local ch = plr.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - C).Magnitude <= WAKE_RADIUS then return true end
	end
	return false
end

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	if now - lastGate > 0.5 then
		lastGate = now
		local a = anyPlayerNear()
		if a ~= awake then
			awake = a
			script:SetAttribute("Awake", a)
		end
	end
	if not awake then
		-- settle, then truly idle: ambience fades out and any in-flight wake rings
		-- finish their fade instead of freezing mid-life
		for _, e in ipairs(sounds) do
			if e.s.Volume > 0 then e.s.Volume = math.max(0, e.s.Volume - dt * 0.5) end
		end
		for _, w in ipairs(wakeParts) do
			if w.p.Transparency < 1 then w.p.Transparency = math.min(1, w.p.Transparency + dt * 1.5) end
		end
		return
	end
	t += dt
	script:SetAttribute("WorkCount", (script:GetAttribute("WorkCount") or 0) + 1)

	for _, o in ipairs(orbits) do
		local a = o.a0 + o.rate * t
		local pos = Vector3.new(8000 + o.r * math.cos(a), o.h, 8000 + o.r * math.sin(a))
		o.m:PivotTo(CFrame.new(pos) * CFrame.Angles(0, o.selfSpin ~= 0 and (o.selfSpin * t) or -a, 0))
	end
	for _, s in ipairs(spins) do
		-- world-Y spin about the part's own position (parts may be axis-rotated cylinders)
		local rot = s.base - s.base.Position
		s.p.CFrame = CFrame.new(s.base.Position) * CFrame.Angles(0, s.rate * t, 0) * rot
	end
	for _, b in ipairs(breatheT) do
		local k = 0.5 + 0.5 * math.sin(t * 2 * math.pi / b.period)
		b.p.Transparency = b.mn + (b.mx - b.mn) * k
	end
	for _, b in ipairs(breatheH) do
		local k = 0.5 + 0.5 * math.sin(t * 2 * math.pi / b.period)
		b.h.FillTransparency = b.mn + (b.mx - b.mn) * k
	end
	for _, b in ipairs(bobs) do
		local y = b.amp * math.sin((t + b.phase) * 2 * math.pi / b.period)
		b.p.CFrame = b.base + Vector3.new(0, y, 0)
	end
	for _, f in ipairs(falls) do
		local off = (f.speed * t) % f.span
		f.p.CFrame = f.base - Vector3.new(0, off, 0)
		f.p.Transparency = 0.25 + 0.55 * (off / f.span)
	end
	for _, e in ipairs(sounds) do
		local v = e.s.Volume
		if math.abs(v - e.target) > 0.01 then
			e.s.Volume = v + math.clamp(e.target - v, -dt * 0.4, dt * 0.4)
		end
	end
	-- wake trail
	if skipStone and t - lastWake > 0.3 then
		lastWake = t
		wakeIdx = wakeIdx % 8 + 1
		local w = wakeParts[wakeIdx]
		w.born = t
		w.p.CFrame = CFrame.new(skipStone.Position.X, 2002.05, skipStone.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
	end
	for _, w in ipairs(wakeParts) do
		local age = t - w.born
		if age < WAKE_LIFE then
			local k = age / WAKE_LIFE
			w.p.Size = Vector3.new(0.1, 1.5 + 6 * k, 1.5 + 6 * k)
			w.p.Transparency = 0.35 + 0.65 * k
		elseif w.p.Transparency < 1 then
			w.p.Transparency = 1
		end
	end
end)
