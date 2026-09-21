-- Riverside Market grade (Trading World).
--
-- The trading town is timber, plaster and stone under the same midday sky as the valley, and the
-- shared Lighting (blue-grey OutdoorAmbient, cool sky) reads it as blue-white. Lighting is global,
-- so this is the TundraAtmosphere pattern: a PRIVATE ColorCorrectionEffect (Lighting.TradingGrade),
-- disabled at rest and faded in only while the player is inside the world.
--
-- What it touches: ONLY Lighting.TradingGrade (Enabled, TintColor, Brightness, Contrast, Saturation).
-- Never Brightness (WeatherClient), never ExposureCompensation (TundraAtmosphere writes the base every
-- frame outside its region, so a second writer would fight it), never the Atmosphere object.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- Matches BoundsGuard's Trading region and MUST keep matching it.
local MIN = Vector3.new(7300, 1930, 7375)
local MAX = Vector3.new(8790, 2110, 8725)

local FADE = 1.6                         -- seconds to ease across the portal
local TINT = Color3.fromRGB(255, 238, 214) -- warm old-world cast; the lanterns do the rest
local WHITE = Color3.new(1, 1, 1)

local grade = Lighting:WaitForChild("TradingGrade", 20)
if not grade then return end

local target, current = 0, 0

local function inside(pos)
	return pos.X >= MIN.X and pos.X <= MAX.X
		and pos.Y >= MIN.Y and pos.Y <= MAX.Y
		and pos.Z >= MIN.Z and pos.Z <= MAX.Z
end

RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	target = (hrp and inside(hrp.Position)) and 1 or 0

	if current ~= target then
		local step = dt / FADE
		current = (current < target) and math.min(current + step, target)
			or math.max(current - step, target)
	end

	if current <= 0.001 then
		if grade.Enabled then grade.Enabled = false end
		return
	end

	grade.Enabled = true
	grade.TintColor = WHITE:Lerp(TINT, current)
	grade.Brightness = 0.015 * current
	grade.Contrast   = 0.06 * current
	grade.Saturation = 0.05 * current
end)
