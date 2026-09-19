-- FireflyClient: warm fireflies that emerge at night and drift over the dirt trails
-- and the plots. Purely cosmetic and CLIENT-ONLY (nothing replicates; other players
-- are unaffected). Gated on Lighting's "Daylight" attribute -- the same signal
-- DayNightCycle publishes and NightLights reads -- so they fade in at dusk and out
-- at dawn. There is no bloom in the scene, so each firefly is a Neon core (its own
-- glow) plus a small warm PointLight that is culled to near the camera for perf.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

-- ---- tunables ----
local COUNT        = 100
local HOVER        = 2.6      -- studs above the anchor surface a firefly's home sits
local WANDER       = 6.0      -- horizontal drift radius around that home
local SPEED        = 3.0      -- drift speed (studs/sec)
local BOB_AMP      = 0.6      -- vertical bob height
-- Two-layer orb: a small, more-visible orange core inside a larger, softer yellow
-- halo -- reads as a warm glowing circle instead of a hard sparkle.
local CORE_SIZE    = 0.30
local HALO_SIZE    = 0.58
local CORE_ALPHA   = 0.05     -- inner orange: lower = more visible
local HALO_ALPHA   = 0.72     -- outer yellow: softer / fainter than the core
local NIGHT_START  = 0.18     -- Daylight below this begins the fade-in (0 = deep night)
local LIGHT_RANGE  = 5.0
local LIGHT_BRIGHT = 0.75
local LIGHT_CULL   = 32       -- only fireflies within this many studs of the camera cast light
local CORE_COLOR   = Color3.fromRGB(255, 108, 20)    -- orangish middle
local HALO_COLOR   = Color3.fromRGB(255, 218, 104)   -- yellow outer glow
local WARM_LIGHT   = Color3.fromRGB(255, 236, 170)

-- ---- anchors: trail parts + plot camp dirt (hub only, Y < 100) ----
local gw = Workspace:WaitForChild("GameWorld")
local trails = gw:WaitForChild("DirtTrails")
local bases = Workspace:WaitForChild("PlayerBases")

-- StreamingEnabled is ON, so the trail/plot parts may not have replicated to the
-- client yet at spawn. Poll until a healthy set has streamed in (or we time out),
-- then snapshot -- homeOver below captures fixed Vector3 homes, so a firefly keeps
-- working even if its source part later streams back out.
local function collectAnchors()
	local a = {}
	for _, p in ipairs(trails:GetDescendants()) do
		if p:IsA("BasePart") and p.Position.Y < 100 then a[#a + 1] = p end
	end
	for _, plot in ipairs(bases:GetChildren()) do
		local cd = plot:FindFirstChild("CampDirt")
		if cd and cd:IsA("BasePart") and cd.Position.Y < 100 then a[#a + 1] = cd end
	end
	return a
end

local anchors = collectAnchors()
for _ = 1, 40 do
	if #anchors >= 400 then break end   -- most of the ~605 trail parts have streamed in
	task.wait(0.5)
	anchors = collectAnchors()
end
if #anchors == 0 then return end

local function homeOver(part)
	local hx = (math.random() - 0.5) * part.Size.X
	local hz = (math.random() - 0.5) * part.Size.Z
	local top = part.CFrame * CFrame.new(hx, part.Size.Y * 0.5, hz)
	return top.Position + Vector3.new(0, HOVER, 0)
end

-- ---- build the pool ----
local folder = Instance.new("Folder")
folder.Name = "FirefliesLocal"
folder.Parent = Workspace

local flies = {}
for i = 1, COUNT do
	local home = homeOver(anchors[math.random(#anchors)])

	local function orb(size, color, name)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(size, size, size)
		p.Material = Enum.Material.Neon
		p.Color = color
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Massless = true
		p.Transparency = 1
		p.Position = home
		p.Parent = folder
		return p
	end
	local halo = orb(HALO_SIZE, HALO_COLOR, "Halo")
	local core = orb(CORE_SIZE, CORE_COLOR, "Core")

	local light = Instance.new("PointLight")
	light.Range = LIGHT_RANGE
	light.Brightness = 0
	light.Color = WARM_LIGHT
	light.Shadows = false
	light.Enabled = false
	light.Parent = core

	flies[i] = {
		core = core, halo = halo, light = light, home = home, pos = home, target = home,
		bobPhase = math.random() * 6.28, bobSpeed = 1.0 + math.random() * 1.2,
		blinkPhase = math.random() * 6.28, blinkSpeed = 1.3 + math.random() * 2.2,
	}
end

local function nightFactor()
	local d = Lighting:GetAttribute("Daylight")
	if d == nil then
		local h = Lighting.ClockTime
		d = (h < 5 or h >= 20) and 0 or 1
	end
	return math.clamp((NIGHT_START - d) / NIGHT_START, 0, 1)
end

local t = 0
local hidden = false
RunService.Heartbeat:Connect(function(dt)
	t += dt
	local nf = nightFactor()

	if nf <= 0 then
		if not hidden then
			for _, f in ipairs(flies) do
				f.core.Transparency = 1
				f.halo.Transparency = 1
				f.light.Enabled = false
			end
			hidden = true
		end
		return
	end
	hidden = false

	local cam = Workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero

	for _, f in ipairs(flies) do
		-- wander toward the current target; pick a fresh one once reached
		local dir = f.target - f.pos
		local dist = dir.Magnitude
		if dist < 0.5 then
			local a = math.random() * 6.28
			local r = math.random() * WANDER
			f.target = f.home + Vector3.new(math.cos(a) * r, (math.random() - 0.5) * 2, math.sin(a) * r)
		else
			f.pos = f.pos + dir.Unit * math.min(SPEED * dt, dist)
		end

		-- vertical bob
		local vy = math.sin(t * f.bobSpeed + f.bobPhase) * BOB_AMP
		local p = f.pos + Vector3.new(0, vy, 0)
		f.core.Position = p
		f.halo.Position = p

		-- blink on/off; scaled by how deep into night we are
		local b = 0.5 + 0.5 * math.sin(t * f.blinkSpeed + f.blinkPhase)
		f.core.Transparency = 1 - (1 - CORE_ALPHA) * b * nf
		f.halo.Transparency = 1 - (1 - HALO_ALPHA) * b * nf

		-- light only near the camera to cap active-light cost
		if (p - camPos).Magnitude < LIGHT_CULL then
			f.light.Enabled = true
			f.light.Brightness = LIGHT_BRIGHT * b * nf
		else
			f.light.Enabled = false
		end
	end
end)
