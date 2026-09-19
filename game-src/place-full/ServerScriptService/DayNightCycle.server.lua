-- Day/night cycle.
--
-- SCOPE, LEARNED THE HARD WAY. WeatherClient is already a full lighting director: every
-- weather kit sets ClockTime, Brightness, ExposureCompensation, Ambient, OutdoorAmbient
-- and Fog together, and restoreVisuals tweens the whole set back when an event ends. Its
-- own comment notes that night events "tween ClockTime up through 24 rather than down
-- through 0 so the transition reads as a sunset instead of a rewind" -- it owns the sky
-- during an event, deliberately.
--
-- So this cycle does exactly two things:
--   * writes ClockTime, and ONLY while the weather is Clear
--   * publishes a Daylight value for other systems to read
--
-- It does NOT write Ambient or OutdoorAmbient. Animating those was a mistake: weather
-- owns them, so the two fought (a 2.4s restore tween against 4Hz writes, which is what
-- the flicker was), and pulling them down at night is what made the valley too dark.
-- Roblox already darkens the world from sun angle alone; constant OutdoorAmbient is what
-- keeps night navigable rather than black.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DAY_LENGTH = 900        -- real seconds for a full 24h
local START_HOUR = 8
local DAWN, DUSK = 5, 20      -- daylight window for the Daylight curve

Lighting.ClockTime = START_HOUR

-- sun altitude rather than a linear ramp, so dawn and dusk stay short
local function daylightAt(hour)
	local x = (hour - DAWN) / (DUSK - DAWN)
	return math.clamp(math.sin(math.clamp(x, 0, 1) * math.pi), 0, 1)
end

Lighting:SetAttribute("Daylight", daylightAt(START_HOUR))
Lighting:SetAttribute("DayLengthSeconds", DAY_LENGTH)

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.25 then return end
	local step = acc
	acc = 0

	-- WeatherHandler publishes this; "Clear" (or nil) means nothing is running.
	-- While an event owns the sky, hold the clock still so the kit's ClockTime sticks.
	local weather = ReplicatedStorage:GetAttribute("WeatherName")
	local clear = (weather == nil or weather == "Clear")

	if clear then
		Lighting.ClockTime = (Lighting.ClockTime + (step / DAY_LENGTH) * 24) % 24
	end

	-- Daylight is derived from whatever the clock actually says, so it stays correct
	-- during a weather event too -- NightLights and TundraAtmosphere both read it.
	Lighting:SetAttribute("Daylight", daylightAt(Lighting.ClockTime))
end)

print(("DayNightCycle online (%.0fs/day from %02d:00; writes ClockTime only, and pauses while weather is active)")
	:format(DAY_LENGTH, START_HOUR))
