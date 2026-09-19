-- The Lush Gardens grade (World 3).
--
-- World 3 is a sealed cavern. The only daylight is what falls through the fissures in
-- its roof, so under the valley's midday Lighting it reads as a flat dark box: the
-- greens go grey and every lantern, glowing plant and waterfall in the place stops
-- registering. This lifts it back and pushes it toward the reference image's palette
-- -- soft green and gold, saturated, with heavy verdant haze in the distance.
--
-- WHAT IS SAFE TO TOUCH (same rules TundraAtmosphere established):
--   * Lighting.Brightness           -- NO. WeatherClient owns it.
--   * Lighting.Ambient              -- NO. DayNightCycle owns it.
--   * a PRIVATE ColorCorrectionEffect -- yes, effects stack.
--   * Lighting.Atmosphere           -- shared with TundraAtmosphere, see AtmoClaim below.
--
-- ExposureCompensation is deliberately NOT used here even though it is free in World
-- 2: TundraAtmosphere writes it back to its base value every frame while the player
-- is outside the tundra, which is always true when they are in the Gardens. The two
-- would fight and the world would flicker. All the lift is done in the private grade.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- Matches BoundsGuard's "Gardens" region and MUST keep matching it.
local MIN = Vector3.new(6440, 900, -9560)
local MAX = Vector3.new(9560, 1900, -6440)

local FADE = 2.0        -- seconds to ease in/out, so the gorge is a fade not a snap

local grade = Lighting:WaitForChild("GardensGrade", 20)
if not grade then return end

local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
local ATMO_BASE = atmo and {
	Density = atmo.Density, Haze = atmo.Haze, Glare = atmo.Glare,
	Offset = atmo.Offset, Color = atmo.Color, Decay = atmo.Decay,
} or nil

-- Cavern haze: enough to give the far side of the space depth, not enough to erase
-- it. Density 0.42 / Haze 2.7 was a WHITEOUT -- past about 200 studs everything
-- washed to flat sky-tinted haze and the underground world rendered as open sea and
-- blue sky. Roblox's atmosphere takes its illumination from the sky, so in a sealed
-- cavern heavy haze does not read as fog, it reads as daylight.
local ATMO_GARDENS = {
	Density = 0.13, Haze = 0.85, Glare = 0, Offset = 0.25,
	Color = Color3.fromRGB(198, 216, 186),
	Decay = Color3.fromRGB(58, 84, 66),
}

-- TundraAtmosphere restores the Atmosphere to its valley baseline every frame while
-- the player is outside the tundra -- which includes every moment they are in here.
-- This attribute is the handshake: while it is set, that script leaves the atmosphere
-- alone and we own it. We clear it the moment we have faded fully out and put the
-- baseline back ourselves.
local CLAIM = "AtmoClaim"

local target, current = 0, 0
local claimed = false

local function inside(p)
	return p.X >= MIN.X and p.X <= MAX.X
		and p.Y >= MIN.Y and p.Y <= MAX.Y
		and p.Z >= MIN.Z and p.Z <= MAX.Z
end

local function weatherIsClear()
	local w = ReplicatedStorage:GetAttribute("WeatherName")
	return w == nil or w == "Clear"
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
		if claimed then
			-- hand the atmosphere back exactly as we found it, then release the claim
			if atmo and ATMO_BASE and weatherIsClear() then
				atmo.Density, atmo.Haze = ATMO_BASE.Density, ATMO_BASE.Haze
				atmo.Glare, atmo.Offset = ATMO_BASE.Glare, ATMO_BASE.Offset
				atmo.Color, atmo.Decay = ATMO_BASE.Color, ATMO_BASE.Decay
			end
			Lighting:SetAttribute(CLAIM, nil)
			claimed = false
		end
		return
	end

	if not claimed then
		Lighting:SetAttribute(CLAIM, "Gardens")
		claimed = true
	end

	grade.Enabled = true
	-- Lift, saturate, and tint toward green-gold. Scaled by `current` so the whole
	-- grade fades together as the player walks in through the gorge.
	grade.Brightness = 0.075 * current
	grade.Contrast   = 0.10 * current
	grade.Saturation = 0.26 * current
	grade.TintColor  = Color3.new(
		1 - 0.05 * current,
		1,
		1 - 0.035 * current)

	if atmo and ATMO_BASE and weatherIsClear() then
		-- Underground, so the haze does NOT fade out with the sun the way the tundra's
		-- does -- there is no sky in here for it to belong to. It is cave air, and it
		-- should look the same at midnight as at noon.
		local t = current
		atmo.Density = ATMO_BASE.Density + (ATMO_GARDENS.Density - ATMO_BASE.Density) * t
		atmo.Haze    = ATMO_BASE.Haze    + (ATMO_GARDENS.Haze    - ATMO_BASE.Haze)    * t
		atmo.Glare   = ATMO_BASE.Glare   + (ATMO_GARDENS.Glare   - ATMO_BASE.Glare)   * t
		atmo.Offset  = ATMO_BASE.Offset  + (ATMO_GARDENS.Offset  - ATMO_BASE.Offset)  * t
		atmo.Color   = ATMO_BASE.Color:Lerp(ATMO_GARDENS.Color, t)
		atmo.Decay   = ATMO_BASE.Decay:Lerp(ATMO_GARDENS.Decay, t)
	end
end)
