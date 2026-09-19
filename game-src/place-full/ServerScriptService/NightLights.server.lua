-- Ties the world's 200-odd lights to the day/night cycle.
--
-- Before this, every torch, lantern, brazier and camp glow burned at full brightness at
-- noon as well as midnight. That is what makes a world look like a set rather than a
-- place -- nothing responds to the sky.
--
-- SERVER-SIDE so every player sees the same lit torches, and because Light.Brightness
-- replicates cheaply (it is set at 2Hz, not per frame).
--
-- TWO BANDS, because "turn the lights off in the day" would break interiors:
--   * OUTDOOR (torches, braziers, lanterns, camp glows) swing hard -- nearly out at
--     noon, full at night. These are the ones that should read as being LIT at dusk.
--   * everything else, which includes the ice hall's window panels, pillar lamps and
--     the sculpture uplights, keeps a high floor. An interior has to stay usable at
--     midday, and guessing indoor-vs-outdoor from geometry is not worth the fragility.
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local OUTDOOR = {
	Flame = true, Torch = true, TorchFire = true, BrazierFire = true, Campfire = true,
	Bonfire = true, Lantern = true, LanternGlass = true, HangLantern = true,
	LanternGlow = true, SignLamp = true, TentGlow = true, IglooGlow = true,
	MarkerGlow = true, GateGlow = true, FloorLight = true, PoolLight = true,
}

local OUTDOOR_FLOOR = 0.45      -- how much an outdoor light keeps at noon. 0.15 made the valley DIMMER by day than
-- before the cycle existed, because these lamps were previously part of the fill light.
local INDOOR_FLOOR  = 0.55      -- interiors must stay readable in daylight

local tracked = {}              -- [light] = { base = number, outdoor = bool }

local function register(light)
	if not (light:IsA("PointLight") or light:IsA("SpotLight") or light:IsA("SurfaceLight")) then
		return
	end
	if tracked[light] then return end
	local host = light.Parent
	local name = host and host.Name or ""
	tracked[light] = { base = light.Brightness, outdoor = OUTDOOR[name] == true }
end

for _, d in ipairs(workspace:GetDescendants()) do register(d) end
workspace.DescendantAdded:Connect(function(d)
	-- brand-new lights (a placed brainrot, a fresh camp) join the cycle automatically
	task.defer(register, d)
end)
workspace.DescendantRemoving:Connect(function(d) tracked[d] = nil end)

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.5 then return end       -- 2Hz: a sunset takes ~40s of real time, this is plenty
	acc = 0

	local daylight = Lighting:GetAttribute("Daylight")
	if type(daylight) ~= "number" then daylight = 1 end
	local night = 1 - math.clamp(daylight, 0, 1)

	for light, info in pairs(tracked) do
		if light.Parent then
			local floor = info.outdoor and OUTDOOR_FLOOR or INDOOR_FLOOR
			light.Brightness = info.base * (floor + (1 - floor) * night)
		else
			tracked[light] = nil
		end
	end
end)

local outdoor, indoor = 0, 0
for _, info in pairs(tracked) do
	if info.outdoor then outdoor += 1 else indoor += 1 end
end
print(("NightLights online (%d outdoor lights swing to %.0f%% at noon, %d others hold %.0f%%)")
	:format(outdoor, OUTDOOR_FLOOR * 100, indoor, INDOOR_FLOOR * 100))
