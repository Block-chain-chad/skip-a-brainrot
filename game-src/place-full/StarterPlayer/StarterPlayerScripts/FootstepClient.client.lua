-- FootstepClient: discrete, material-aware footsteps.
--
-- WHY REPLACE THE DEFAULT: Roblox's RbxCharacterSounds plays ONE looped 2.48s sample
-- (action_footsteps_plastic) at a fixed pitch for every surface, which is why the
-- default walk sounds like scuffing a plastic tray no matter where you are. This fires
-- ONE short hit per stride and shapes it by the surface underfoot, so the dock, the
-- camp grass and the plaza floor all sound like different places.
--
-- SOURCE AUDIO: Pro Sound Effects "Rocks Dirt Impacts in Ground" -- first-party, short
-- (0.42s / 0.58s), and verified loadable in this place. Deliberately NOT the community
-- "grass_walk"/"Wood Footsteps" uploads: the former are Minecraft extractions (the
-- seller says so) and the latter are 3-second multi-step SEQUENCES, useless per-stride.
-- Two variants alternate and every hit gets pitch/volume jitter, so no two steps are
-- identical -- that repetition is what makes most footstep systems grating.
--
-- RUNS FOR EVERY CHARACTER, not just the local one, so you hear other players walking
-- past. That is why this is client-side and costs zero replication: each client sounds
-- out every character it can see, exactly like RbxCharacterSounds does.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local STEP_A = "rbxassetid://9118686853"   -- 0.42s, tighter
local STEP_B = "rbxassetid://9118685591"   -- 0.58s, a touch heavier
local WATER  = "rbxasset://sounds/impact_water.mp3"

local BASE_VOLUME = 0.30    -- under the SFX and well under the register/collect cues
local STRIDE       = 6.2    -- studs per step; interval = STRIDE / speed
local MIN_SPEED    = 3.0    -- below this we treat the character as standing still
local HEAR_RADIUS  = 90     -- do not bother sounding characters further out than this

-- pitch/volume per surface. Higher speed = brighter and louder, applied on top.
-- One table covers terrain AND parts because Raycast reports both as Enum.Material.
local PROFILE = {
	[Enum.Material.Grass]       = { p = 0.82, v = 0.80 },
	[Enum.Material.LeafyGrass]  = { p = 0.78, v = 0.86 },
	[Enum.Material.Ground]      = { p = 0.86, v = 0.90 },
	[Enum.Material.Mud]         = { p = 0.70, v = 0.80 },
	[Enum.Material.Sand]        = { p = 0.74, v = 0.72 },
	[Enum.Material.Snow]        = { p = 0.66, v = 0.60 },
	[Enum.Material.Wood]        = { p = 1.24, v = 1.00 },
	[Enum.Material.WoodPlanks]  = { p = 1.30, v = 1.05 },
	[Enum.Material.Rock]        = { p = 1.12, v = 1.00 },
	[Enum.Material.Slate]       = { p = 1.18, v = 1.00 },
	[Enum.Material.Basalt]      = { p = 1.10, v = 1.00 },
	[Enum.Material.Concrete]    = { p = 1.16, v = 0.95 },
	[Enum.Material.Cobblestone] = { p = 1.20, v = 1.00 },
	[Enum.Material.Metal]       = { p = 1.36, v = 0.90 },
	[Enum.Material.DiamondPlate]= { p = 1.40, v = 0.95 },
	[Enum.Material.Pebble]      = { p = 1.26, v = 0.92 },
	[Enum.Material.Fabric]      = { p = 0.72, v = 0.55 },
	[Enum.Material.SmoothPlastic]= { p = 1.22, v = 0.85 },
	[Enum.Material.Plastic]     = { p = 1.18, v = 0.85 },
}
local DEFAULT_PROFILE = { p = 1.0, v = 0.9 }

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = false

local function surfaceUnder(char, hrp)
	rayParams.FilterDescendantsInstances = { char }
	local hit = Workspace:Raycast(hrp.Position, Vector3.new(0, -6, 0), rayParams)
	if not hit then return nil end
	return hit.Material
end

local flip = false
local function playStep(hrp, material, speed)
	local prof = PROFILE[material] or DEFAULT_PROFILE
	local isWater = (material == Enum.Material.Water)
	local s = Instance.new("Sound")
	if isWater then
		s.SoundId = WATER
		s.PlaybackSpeed = 1.7 + (math.random() - 0.5) * 0.12
		s.Volume = BASE_VOLUME * 0.55
	else
		flip = not flip
		s.SoundId = flip and STEP_A or STEP_B
		-- faster movement reads brighter; jitter keeps consecutive steps from matching
		local fast = math.clamp((speed - 8) / 18, 0, 1)
		s.PlaybackSpeed = prof.p * (1 + fast * 0.14) + (math.random() - 0.5) * 0.10
		s.Volume = BASE_VOLUME * prof.v * (0.85 + fast * 0.3)
	end
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 6
	s.RollOffMaxDistance = 65
	s.Parent = hrp
	s:Play()
	Debris:AddItem(s, 1.2)
end

-- per-character state: when the next step is due
local state = setmetatable({}, { __mode = "k" })

local function silenceDefault(char)
	-- RbxCharacterSounds parents its looped "Running" sound to the HRP. Muting it rather
	-- than destroying it means the CoreScript can keep managing its own lifecycle without
	-- erroring, and a future Roblox update that renames things degrades to "both play"
	-- rather than "script breaks".
	task.delay(0.6, function()
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local run = hrp and hrp:FindFirstChild("Running")
		if run and run:IsA("Sound") then run.Volume = 0 end
	end)
end

local function hook(char)
	silenceDefault(char)
end
local function watch(plr)
	if plr.Character then hook(plr.Character) end
	plr.CharacterAdded:Connect(hook)
end
for _, plr in ipairs(Players:GetPlayers()) do watch(plr) end
Players.PlayerAdded:Connect(watch)

local camera = Workspace.CurrentCamera
local accum = 0
RunService.Heartbeat:Connect(function(dt)
	-- 20 Hz is plenty to place a step within a few milliseconds of correct, and keeps
	-- this off the render path entirely
	accum += dt
	if accum < 0.05 then return end
	local step = accum
	accum = 0
	local camPos = camera and camera.CFrame.Position
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 then
			if not camPos or (hrp.Position - camPos).Magnitude <= HEAR_RADIUS then
				local grounded = hum.FloorMaterial ~= Enum.Material.Air
				local speed = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z).Magnitude
				local st = state[char]
				if not st then st = { next = 0 }; state[char] = st end
				if grounded and speed >= MIN_SPEED then
					st.next -= step
					if st.next <= 0 then
						-- FloorMaterial is already the surface the Humanoid is standing on, so
						-- prefer it and only raycast when it comes back empty
						local mat = hum.FloorMaterial
						if mat == Enum.Material.Air then mat = surfaceUnder(char, hrp) end
						playStep(hrp, mat, speed)
						st.next = math.clamp(STRIDE / math.max(speed, 1), 0.20, 0.62)
					end
				else
					st.next = 0   -- land the first step immediately on moving off again
				end
			end
		end
	end
end)
