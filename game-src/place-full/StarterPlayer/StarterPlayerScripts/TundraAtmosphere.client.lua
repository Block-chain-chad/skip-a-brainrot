-- Frozen Tundra grade.
--
-- World 2 is a white-on-white snowfield under the same midday Lighting as World 1
-- (ClockTime 12.1, Brightness 1.9), which blows it out to a flat sheet with no
-- readable form. Lighting is global, so this cannot be a place-wide change without
-- wrecking the valley.
--
-- RE-TUNED once the skip area became open water. -1.05 was set against a view that was
-- snow to the horizon and nothing else; with a lake in the middle of it the same figure
-- crushed the water to near-black while the snow around it still read fine. The dark
-- lake now supplies the contrast the exposure cut used to have to fake.
--
-- What it is safe to touch:
--   * Lighting.Brightness            -- NO. WeatherClient owns it; we would fight.
--   * Lighting.ExposureCompensation  -- yes. Nothing else in the game writes it.
--   * a PRIVATE ColorCorrectionEffect -- yes. Effects stack, so ours does not
--     clobber the existing Lighting.ColorCorrection.
--
-- Both are eased in and out so crossing the portal is a fade, not a snap.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- Matches BoundsGuard's Tundra region, and MUST keep matching it: the lake now runs out
-- to z -6870, so the old -7400 edge put the far half of the water outside the grade --
-- swim past the middle of the lake and the whole world would snap brightness.
local MIN = Vector3.new(-8600, 1850, -8600)
local MAX = Vector3.new(-7400, 2250, -6700)

-- THE DIAL. 0 = untouched (blown-out white), -1.2 = heavy overcast.
-- RE-TUNED with the World 2 art pass (2026-09-21): -0.70 was set when the tundra was a white
-- plain and the cut had to manufacture all its relief. The rebuilt world carries its own range
-- -- slate cliffs, timber buildings, painted paths, the dark lake -- and at -0.70 the new town
-- read as dusk at noon. -0.40 keeps the snow from blowing out and lets the colour through.
local EXPOSURE_IN = -0.40
local FADE = 1.6                   -- seconds to ease across

local grade = Lighting:WaitForChild("TundraGrade", 20)
if not grade then return end
local DAY_TINT = grade.TintColor   -- the daytime tint set on the effect itself

local baseExposure = Lighting.ExposureCompensation
-- FOG IS WORLD 2 ONLY. The Atmosphere object is global, and at Density 0.28 its haze was
-- showing up in the valley too. The base is now the valley's (near-clear); the tundra
-- raises it, scaled by the same region fade as the grade, and puts it back on the way out.
--
-- WHY IT ONLY WRITES WHILE THE WEATHER IS CLEAR: WeatherClient owns Atmosphere during an
-- event -- eight kits tween it, and restoreVisuals tweens it back to the join-time
-- snapshot. Writing over that every frame is the same mistake that made the sky flicker
-- when the day/night cycle fought it over Ambient. So an active event wins outright.
local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
local ATMO_BASE = atmo and {
	Density = atmo.Density, Haze = atmo.Haze, Glare = atmo.Glare, Offset = atmo.Offset,
} or nil
-- the tundra target: thick, cold distance haze
-- (lighter with the art pass: 1.9 of haze greyed out the peak and the far cliffs, the
-- landmarks the new layout is built to show)
local ATMO_TUNDRA = { Density = 0.20, Haze = 1.1, Glare = 0.10, Offset = 0.20 }
-- How much of that haze survives at midnight. Atmosphere takes its colour from the
-- SKY, so after dark a Haze of 1.9 is a black veil laid over an already dark world --
-- world 2 read as pitch black while the valley at the same clock stayed navigable.
-- The haze is a DAYLIGHT effect (it is what gives the white snowfield its distance),
-- so it now fades out with the sun instead of riding on top of the night.
-- ITEM 9: all the way out. At full dark the tundra's Haze is the valley's own 0.30 and no more
-- (MASTER's night cap); 0.25 of the mix had left it at ~0.50 after dark.
local NIGHT_HAZE = 0

-- DUSK AND NIGHT (ITEM 9). Before this the grade had one look, scaled by daylight, so the
-- tundra at 21:30 was the tundra at 17:45 under a darker sky: OutdoorAmbient is held constant
-- after dark on purpose (DayNightCycle), the snow stays near white, and the warm windows had
-- nothing to glow against. Two curves on Lighting.Daylight fix that, inside the tundra only:
--   blue  -- the blue hour: a cold tint, a touch more contrast and saturation, so the warm
--            lights (Warmhouse, huts, camps, hole lanterns) separate from the snow by hue;
--   night -- a slightly deeper tint and a small exposure cut, so it reads as night while the
--            dock, the door and the ice stay findable (their own lights carry them).
-- Same rule as the rest of the file: the private TundraGrade and ExposureCompensation only,
-- faded by `current`, so World 1, the Gardens and the HUD blur never see any of it.
local DUSK_TINT  = Color3.fromRGB(208, 222, 255)
local NIGHT_TINT = Color3.fromRGB(198, 214, 255)
local NIGHT_EXPOSURE = -0.22
local function ease(from, to, x)   -- 0 at `from`, 1 at `to`, smoothstepped (works either way round)
	local t = math.clamp((x - from) / (to - from), 0, 1)
	return t * t * (3 - 2 * t)
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local target, current = 0, 0

-- WEATHER-EVENT HAZE CAP (MASTER, 2026-09-23). During an event WeatherClient tweens the
-- global Atmosphere to its kit (Thunderstorm is Density 0.42 / Haze 2.7), which greys out
-- everything past ~150 studs and hides the peak and the glacier walls. Inside the tundra
-- only, and faded by the same region blend, the event look is capped at these values.
-- WeatherClient is not touched: we remember the last value IT set (anything that is not
-- what we wrote last frame) and put exactly that back when the player leaves mid-event.
-- Fog is exempt, because fog is the whole point of that event.
local EVENT_CAP = { Density = 0.32, Haze = 1.2 }
local CAP_EXEMPT = { Fog = true }
local evKit, evWrote = nil, nil
local function trackEventAtmo()
	if not evWrote or math.abs(atmo.Haze - evWrote.Haze) > 1e-3
		or math.abs(atmo.Density - evWrote.Density) > 1e-3 then
		evKit = { Haze = atmo.Haze, Density = atmo.Density }
	end
end

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
		-- left the tundra mid-event: hand WeatherClient's own values back, once
		if atmo and evWrote and evKit then
			atmo.Haze, atmo.Density = evKit.Haze, evKit.Density
		end
		evWrote, evKit = nil, nil
		if grade.Enabled then grade.Enabled = false end
		if Lighting.ExposureCompensation ~= baseExposure then
			Lighting.ExposureCompensation = baseExposure
		end
		-- Fully outside the tundra: hand the atmosphere back to the valley baseline --
		-- UNLESS another world has claimed it. World 3 (the Lush Gardens) runs its own
		-- atmosphere, and "outside the tundra" is true the entire time a player is in
		-- there, so without this check the two scripts overwrite each other every frame
		-- and the Gardens' haze strobes.
		if atmo and ATMO_BASE and Lighting:GetAttribute("AtmoClaim") == nil then
			local weather = ReplicatedStorage:GetAttribute("WeatherName")
			if weather == nil or weather == "Clear" then
				atmo.Density, atmo.Haze = ATMO_BASE.Density, ATMO_BASE.Haze
				atmo.Glare, atmo.Offset = ATMO_BASE.Glare, ATMO_BASE.Offset
			end
		end
		return
	end

	grade.Enabled = true
	-- scale the whole grade by `current` so the fade covers tint and exposure together
	-- CONTRAST CAME DOWN with the lake. 0.30 was set against a view that was snow to the
	-- horizon, where it was the only thing giving the picture any tonal range. Stacked on
	-- Lighting.ColorCorrection's own +0.10 it now lands on open water, and high contrast on
	-- a specular surface exaggerates every fleck -- the lake read as restless even after
	-- the terracing in its surface was fixed. The water and the bergs supply the range now.
	-- and down again with the art pass: timber, painted paths and warm windows now sit in
	-- the frame, and at 0.26 contrast / +0.10 saturation they went hard and orange. The
	-- grade's tint (TundraGrade.TintColor) was eased from 214,230,255 to 238,244,255 with it.
	grade.Brightness =  0
	-- Scale the cut by time of day. At -1.95 on top of a night sky the tundra would be
	-- black; DayNightCycle publishes Lighting.Daylight (0 at night, 1 at noon) so the
	-- grade relaxes after dark instead of compounding with it. Defaults to 1 when no
	-- cycle is running, which is exactly the old behaviour.
	local daylight = Lighting:GetAttribute("Daylight")
	if type(daylight) ~= "number" then daylight = 1 end
	daylight = math.clamp(daylight, 0, 1)
	local blue  = ease(0.62, 0.30, daylight)   -- 0 in daylight, 1 from the blue hour on
	local night = ease(0.30, 0.00, daylight)   -- 1 at full dark
	grade.TintColor  = DAY_TINT:Lerp(DUSK_TINT, blue * current):Lerp(NIGHT_TINT, night * current)
	grade.Contrast   = (0.12 + 0.05 * blue) * current
	grade.Saturation = (-0.05 + 0.09 * blue - 0.03 * night) * current
	-- The exposure cut exists to tame a BLOWN-OUT white noon. After dark there is no
	-- white-out left to tame, so it goes fully to zero rather than keeping a floor:
	-- the old 0.25 floor was still pulling a quarter-stop out of an already night sky.
	-- (NIGHT_EXPOSURE is a separate, smaller cut for the night LOOK, not for white-out.)
	Lighting.ExposureCompensation = baseExposure + (EXPOSURE_IN * daylight + NIGHT_EXPOSURE * night) * current
	if atmo and ATMO_BASE then
		local weather = ReplicatedStorage:GetAttribute("WeatherName")
		if weather == nil or weather == "Clear" then
			evWrote, evKit = nil, nil
			-- same region fade, then scaled again by time of day so the cold haze is a
			-- daytime look and never a blackout at night
			local mix = current * (NIGHT_HAZE + (1 - NIGHT_HAZE) * daylight)
			atmo.Density = ATMO_BASE.Density + (ATMO_TUNDRA.Density - ATMO_BASE.Density) * mix
			atmo.Haze    = ATMO_BASE.Haze    + (ATMO_TUNDRA.Haze    - ATMO_BASE.Haze)    * mix
			atmo.Glare   = ATMO_BASE.Glare   + (ATMO_TUNDRA.Glare   - ATMO_BASE.Glare)   * mix
			atmo.Offset  = ATMO_BASE.Offset  + (ATMO_TUNDRA.Offset  - ATMO_BASE.Offset)  * mix
		elseif not CAP_EXEMPT[weather] then
			trackEventAtmo()
			local h = evKit.Haze    + (math.min(evKit.Haze,    EVENT_CAP.Haze)    - evKit.Haze)    * current
			local d = evKit.Density + (math.min(evKit.Density, EVENT_CAP.Density) - evKit.Density) * current
			atmo.Haze, atmo.Density = h, d
			evWrote = { Haze = atmo.Haze, Density = atmo.Density }
		else
			evWrote, evKit = nil, nil
		end
	end
end)
