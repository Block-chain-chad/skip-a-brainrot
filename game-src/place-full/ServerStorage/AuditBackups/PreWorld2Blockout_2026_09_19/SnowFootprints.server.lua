-- Footprints in snow.
--
-- SERVER-SIDE so every player sees the same tracks -- footprints you leave that nobody
-- else can see are barely worth having. That choice costs replication, so the whole
-- design is about bounding that cost:
--
--   * STRIDE-GATED, not time-gated. A print is spawned per distance travelled, so
--     sprinting does not spawn more than walking and standing still spawns none.
--   * REGION-GATED. Nothing runs unless a player is inside the Tundra bounds, so World 1
--     costs literally nothing.
--   * MATERIAL-GATED. RaycastResult.Material returns the TERRAIN material for terrain
--     hits and the part material for parts, so one check covers sculpted snow and snow
--     parts alike -- and prints never appear on ice, rock, timber decks or indoors.
--   * HARD CAPPED with oldest-first eviction, so a full server cannot grow the count
--     without limit no matter how many people run in circles.
--   * one part per print, non-colliding, non-querying, no shadow.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local TMIN = Vector3.new(-8600, 1850, -8600)
local TMAX = Vector3.new(-7400, 2250, -7400)

local STRIDE = 3.2          -- studs between prints
local LIFETIME = 11         -- seconds before a print has fully faded
local FADE = 4              -- of which the last N are the fade itself
local GLOBAL_CAP = 200      -- across all players
local PROBE = 6             -- how far below the feet to look for ground

local folder = Instance.new("Folder")
folder.Name = "Footprints"
folder.Parent = workspace

local prints = {}           -- FIFO queue of live prints
local lastAt = {}           -- [player] = last print position
local footSide = {}         -- [player] = alternating -1 / 1

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { folder }
rayParams.IgnoreWater = true

local function inTundra(p)
	return p.X >= TMIN.X and p.X <= TMAX.X and p.Y >= TMIN.Y and p.Y <= TMAX.Y
		and p.Z >= TMIN.Z and p.Z <= TMAX.Z
end

local function evict()
	while #prints > GLOBAL_CAP do
		local oldest = table.remove(prints, 1)
		if oldest and oldest.Parent then oldest:Destroy() end
	end
end

local function stamp(pos, normal, look, side)
	local p = Instance.new("Part")
	p.Name = "Footprint"
	p.Size = Vector3.new(0.85, 0.06, 1.5)
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.CastShadow = false
	p.Material = Enum.Material.Snow
	-- a shade under the snow it sits on: a compressed dent, not a decal
	p.Color = Color3.fromRGB(150, 168, 196)
	p.Transparency = 0.25

	-- lie the print flat on whatever it landed on, facing the way the player is going
	local right = look:Cross(normal)
	if right.Magnitude < 0.01 then right = Vector3.new(1, 0, 0) end
	right = right.Unit
	local fwd = normal:Cross(right).Unit
	p.CFrame = CFrame.fromMatrix(pos + normal * 0.03 + right * (side * 0.45), right, normal, -fwd)
	p.Parent = folder

	table.insert(prints, p)
	evict()

	TweenService:Create(p, TweenInfo.new(FADE, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
	task.delay(LIFETIME, function()
		if p.Parent then
			for i, q in ipairs(prints) do
				if q == p then table.remove(prints, i); break end
			end
			p:Destroy()
		end
	end)
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.12 then return end       -- ~8Hz is finer than any stride at running speed
	acc = 0

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 and inTundra(root.Position) then
			-- airborne players leave nothing
			local grounded = hum.FloorMaterial ~= Enum.Material.Air
			local last = lastAt[player]
			local moved = (not last) or (root.Position - last).Magnitude >= STRIDE
			if grounded and moved then
				-- The character MUST be excluded or the probe hits the player's own torso and
				-- never reaches the ground -- which is exactly how this failed first time.
				rayParams.FilterDescendantsInstances = { folder, char }
				local origin = root.Position + Vector3.new(0, 1, 0)
				local hit = workspace:Raycast(origin, Vector3.new(0, -PROBE, 0), rayParams)
				-- only snow. Terrain hits report the terrain material here, so this one
				-- test covers sculpted snow and snow-material parts together.
				if hit and hit.Material == Enum.Material.Snow then
					local side = (footSide[player] or 1) * -1
					footSide[player] = side
					local look = root.CFrame.LookVector
					look = Vector3.new(look.X, 0, look.Z)
					if look.Magnitude < 0.01 then look = Vector3.new(0, 0, 1) end
					stamp(hit.Position, hit.Normal, look.Unit, side)
					lastAt[player] = root.Position
				else
					-- not snow: remember where we were so the next snow step is a fresh stride
					lastAt[player] = root.Position
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastAt[player] = nil
	footSide[player] = nil
end)

print(("SnowFootprints online (snow only, %.1f-stud stride, %ds life, cap %d)")
	:format(STRIDE, LIFETIME, GLOBAL_CAP))
