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
--   * Lighting.ExposureCompensation  -- yes, but SHARED: the weather kits write it too, so this
--     script only writes it inside the tundra blend (see ITEM 10b below).
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
-- EXPOSURE IS SHARED WITH THE WEATHER (ITEM 10b). Every WeatherClient kit tweens
-- ExposureCompensation too (Golden Hour 0.30, Blizzard 0.24, Thunderstorm -0.10 ...). This
-- script used to pin it to baseExposure every frame OUTSIDE the tundra as well, so no kit's
-- exposure ever showed anywhere, the valley included. Now it only writes while the tundra
-- blend is above 0. Whatever someone else writes in between (a kit's tween, its restore) is
-- the weather's own value; the fade out ends on that value, and at blend 0 it is handed back
-- once and the script stops writing, so the kits own exposure outside the tundra.
local weatherExposure = baseExposure   -- the last value the weather set (the base in Clear)
local wroteExposure = nil              -- what this script wrote last frame; nil = hands off
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
--   night -- a deeper moonlight tint and an exposure cut, so it reads as night while the
--            dock, the door and the ice stay findable (their own lights carry them).
-- Same rule as the rest of the file: the private TundraGrade and ExposureCompensation only,
-- faded by `current`, so World 1, the Gardens and the HUD blur never see any of it.
-- ITEM 9b: night pushed. At 198,214,255 / -0.22 the snow and the ice sheet stayed near daytime
-- white and 21:30 read as dusk under a dark sky. 156,180,248 / -0.50 (tuned by shot) puts the
-- snow into moonlight blue; the night saturation dip went with it, it greyed the warm windows.
local DUSK_TINT  = Color3.fromRGB(208, 222, 255)
local NIGHT_TINT = Color3.fromRGB(156, 180, 248)
local NIGHT_EXPOSURE = -0.50
local WHITE = Color3.new(1, 1, 1)
local DAWN, DUSK = 5, 20   -- DayNightCycle's daylight window; keep the two in step
local evMix = 0            -- 0 = the tundra's own look, 1 = a weather event owns the colour
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

-- WEATHER EVENTS IN THE TUNDRA (ITEM 11b). On top of the handover and the cap, a few events get
-- a Tundra row: how they should read on snow. All of it is inside the tundra blend, so World 1
-- never sees it, and anything global a row borrows is handed back on the way out.
--   look   -- the grade while the event runs (the handover's neutral grade otherwise);
--             look.soften answers the kit's own screen wash (WeatherCC) instead of a fixed tint,
--             look.exposure (stops) is added to the tundra's exposure while the row is in
--   cap    -- the event's own EVENT_CAP
--   atmo   -- Atmosphere Color / Decay (the kit's own are remembered and handed back)
--   clouds -- Terrain.Clouds (nothing else writes them; the sky's own are put back)
local EVENT_ROWS = {
	-- the kit walks WeatherCC through mint, blue, violet and green at +0.5 saturation. On white
	-- snow the blue step read royal blue, and the fixed teal pull first tried here (214,255,236)
	-- turned the timber lime on the green step. soften takes about half of whichever step is
	-- showing back out, so the cycle keeps its hues at half strength.
	Aurora = { look = { soften = 0.45, saturation = -0.35 } },
	-- the kit is a desert: tan light, tan haze, tan grit, and on snow it read green-tan. Stripped
	-- to grey-white under a snow-white haze it reads as wind-driven spindrift. Desaturating alone
	-- did not do it: measured, the kit's tan WeatherCC tint (236,176,104) lands on top of the -0.85
	-- and the frame stayed tan. soften 0.9 takes the tan out; a tint can only darken, so the row
	-- lifts exposure 1 stop (inside the tundra only, like the rest of the grade).
	Sandstorm = {
		look = { tint = Color3.fromRGB(232, 240, 255), soften = 0.9, saturation = -0.85, brightness = 0.02,
			exposure = 1.0 },
		atmo = { Color = Color3.fromRGB(226, 232, 240), Decay = Color3.fromRGB(196, 206, 220) },
	},
	-- under the common cap it was a sunny day with big flakes. Its own cap, set by MASTER's floor:
	-- the dock, the Warmhouse door and a hole at 55 studs stay findable. Measured by shot: at 2.4 /
	-- 0.45 the peak still stood clear from the dock; the kit's own full whiteout (4.8 / 0.58) keeps
	-- all three readable at 55, so the cap is the kit's own and holds it there if the kit grows.
	Blizzard = {
		cap = { Haze = 4.8, Density = 0.58 },
		clouds = { Cover = 0.95, Density = 0.9, Color = Color3.fromRGB(205, 210, 220) },
	},
}
local lastEvent = nil      -- the event whose row is easing in or out
local weatherCC = nil      -- WeatherClient's screen wash, found once it exists (read, never written)
local ATMO_KEYS = { "Haze", "Density", "Color", "Decay" }
local function same(a, b)
	if typeof(a) == "Color3" then
		return math.abs(a.R - b.R) < 0.002 and math.abs(a.G - b.G) < 0.002 and math.abs(a.B - b.B) < 0.002
	end
	return math.abs(a - b) < 1e-3
end
local evKit, evWrote = nil, nil
local function trackEventAtmo()
	-- per property: anything that is not what we wrote last frame is the kit's own value
	evKit = evKit or {}
	for _, k in ipairs(ATMO_KEYS) do
		if evKit[k] == nil or not (evWrote and evWrote[k] ~= nil and same(atmo[k], evWrote[k])) then
			evKit[k] = atmo[k]
		end
	end
end
local clouds = workspace:WaitForChild("Terrain"):FindFirstChildOfClass("Clouds")
local cloudsBase, cloudMix, cloudRow = nil, 0, nil
local function applyClouds(w)
	if not clouds then return end
	if w > 0.001 and cloudRow then
		cloudsBase = cloudsBase or { Cover = clouds.Cover, Density = clouds.Density, Color = clouds.Color }
		clouds.Cover = cloudsBase.Cover + (cloudRow.Cover - cloudsBase.Cover) * w
		clouds.Density = cloudsBase.Density + (cloudRow.Density - cloudsBase.Density) * w
		clouds.Color = cloudsBase.Color:Lerp(cloudRow.Color, w)
	elseif cloudsBase then
		clouds.Cover, clouds.Density, clouds.Color = cloudsBase.Cover, cloudsBase.Density, cloudsBase.Color
		cloudsBase = nil
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
			atmo.Color, atmo.Decay = evKit.Color, evKit.Decay
		end
		evWrote, evKit = nil, nil
		applyClouds(0)
		if grade.Enabled then grade.Enabled = false end
		-- hand exposure back ONCE, then leave it alone (the fade already ended on this value)
		if wroteExposure ~= nil then
			Lighting.ExposureCompensation = weatherExposure
			wroteExposure = nil
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
	-- Scale the cut by time of day. At -1.95 on top of a night sky the tundra would be
	-- black, so the grade relaxes after dark instead of compounding with it.
	-- ITEM 10: the phase is read from THIS client's clock, on DayNightCycle's own curve, not
	-- from its Daylight attribute. Daylight follows the SERVER clock, which is frozen while a
	-- weather event runs -- but every event kit sets its own ClockTime on the client. A night
	-- kit (Aurora, Shooting Star, Blood Moon) that began at noon was graded as noon, the -0.40
	-- white-out cut on a moonlit sky; a storm that began at night got the night tint and cut on
	-- top of its daytime look. In Clear weather the clock replicates, so nothing changes.
	local x = (Lighting.ClockTime - DAWN) / (DUSK - DAWN)
	local daylight = math.clamp(math.sin(math.clamp(x, 0, 1) * math.pi), 0, 1)
	local blue  = ease(0.62, 0.30, daylight)   -- 0 in daylight, 1 from the blue hour on
	local night = ease(0.30, 0.00, daylight)   -- 1 at full dark
	-- ITEM 10: while an event runs, WeatherClient's WeatherCC owns the colour. The tundra's cold
	-- tint, contrast and saturation stacked on the blue kits (Thunderstorm, Blizzard, Shooting
	-- Star) read as double blue, so the look eases out over FADE and only the daylight snow cut
	-- (below) stays in. Clear weather: evMix is 0 and every line is what it was.
	local weather = ReplicatedStorage:GetAttribute("WeatherName")
	local eventOn = not (weather == nil or weather == "Clear")
	evMix = eventOn and math.min(evMix + dt / FADE, 1) or math.max(evMix - dt / FADE, 0)
	local look = 1 - evMix
	-- ITEM 11b: an event with a Tundra row eases to that row's grade instead of to neutral. With
	-- no row the result is the ITEM 10 handover exactly; in Clear weather, the tundra's own look.
	if eventOn then lastEvent = weather end
	local row = lastEvent and EVENT_ROWS[lastEvent]
	local rowLook = row and row.look or {}
	local ownTint = DAY_TINT:Lerp(DUSK_TINT, blue * current):Lerp(NIGHT_TINT, night * current)
	local rowTint = rowLook.tint or WHITE
	weatherCC = weatherCC or Lighting:FindFirstChild("WeatherCC")
	if rowLook.soften and weatherCC and weatherCC.Enabled then
		-- a tint can only take light away, so the channels the wash cut are lifted by dimming the
		-- one it kept: the wash's inverse to the power `soften`, scaled to a peak of 1
		local c, k = weatherCC.TintColor, -rowLook.soften
		local r, g, b = math.max(c.R, 0.05) ^ k, math.max(c.G, 0.05) ^ k, math.max(c.B, 0.05) ^ k
		local peak = math.max(r, g, b)
		rowTint = Color3.new(rowTint.R * r / peak, rowTint.G * g / peak, rowTint.B * b / peak)
	end
	grade.TintColor  = ownTint:Lerp(WHITE:Lerp(rowTint, current), evMix)
	grade.Contrast   = (0.12 + 0.05 * blue) * current * look + (rowLook.contrast or 0) * current * evMix
	grade.Saturation = (-0.05 + 0.09 * blue) * current * look + (rowLook.saturation or 0) * current * evMix
	grade.Brightness = (rowLook.brightness or 0) * current * evMix
	-- The exposure cut exists to tame a BLOWN-OUT white noon. After dark there is no
	-- white-out left to tame, so it goes fully to zero rather than keeping a floor:
	-- the old 0.25 floor was still pulling a quarter-stop out of an already night sky.
	-- (NIGHT_EXPOSURE is a separate, smaller cut for the night LOOK, not for white-out, so it
	-- is part of the look and eases out during an event with the tint.)
	-- ITEM 10b: anything that changed exposure since our last write is the weather's own value
	-- (on the first frame back in, whatever is there is). The blend runs from that value to the
	-- tundra's, so at full blend nothing changes, and the fade out lands on the weather's value
	-- with no pop. In Clear weather the weather's value is baseExposure: identical to before.
	if wroteExposure == nil or math.abs(Lighting.ExposureCompensation - wroteExposure) > 1e-4 then
		weatherExposure = Lighting.ExposureCompensation
	end
	local tundraExposure = baseExposure + EXPOSURE_IN * daylight + NIGHT_EXPOSURE * night * look
		+ (rowLook.exposure or 0) * evMix
	wroteExposure = weatherExposure + (tundraExposure - weatherExposure) * current
	Lighting.ExposureCompensation = wroteExposure
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
			local evRow = EVENT_ROWS[weather]
			local cap = (evRow and evRow.cap) or EVENT_CAP
			atmo.Haze    = evKit.Haze    + (math.min(evKit.Haze,    cap.Haze)    - evKit.Haze)    * current
			atmo.Density = evKit.Density + (math.min(evKit.Density, cap.Density) - evKit.Density) * current
			if evRow and evRow.atmo then
				atmo.Color = evKit.Color:Lerp(evRow.atmo.Color, current)
				atmo.Decay = evKit.Decay:Lerp(evRow.atmo.Decay, current)
			end
			evWrote = evWrote or {}
			for _, k in ipairs(ATMO_KEYS) do evWrote[k] = atmo[k] end
		else
			evWrote, evKit = nil, nil
		end
	end
	-- ITEM 11b: a row's clouds ease in and out with the event, and with the region blend
	local rowClouds = eventOn and EVENT_ROWS[weather] and EVENT_ROWS[weather].clouds
	if rowClouds then cloudRow = rowClouds end
	cloudMix = rowClouds and math.min(cloudMix + dt / FADE, 1) or math.max(cloudMix - dt / FADE, 0)
	applyClouds(cloudMix * current)
end)
