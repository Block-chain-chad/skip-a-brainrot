-- WeatherHandler: timed lake events that spike luck + mutation odds for LIVE throws.
-- Publishes WeatherLuck / WeatherMut / WeatherName attributes on ReplicatedStorage
-- (ThrowHandler reads them) and fires WeatherState to clients for the banner + sky.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remotes = ReplicatedStorage.Remotes
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)

local CLEAR = { Name = "Clear", Luck = 1, Mut = 1, Duration = 180, IsEvent = false }

-- Weight = how often this event is picked, relative to the others. The design
-- figures sum to 112.4 rather than 100, so they are normalised by the running
-- total below and act as relative weights -- the ratios are what was specified.
-- Each event's paired mutation and its odds live in MutationConfig.Events.
-- Luck AND Mut are both 1 on every event. An event grants exactly one thing:
-- a chance at its own mutation (see MutationConfig.Events). It does not make
-- you catch rarer brainrots and does not nudge the base variant odds -- the
-- mutation's own cash multiplier is the entire reward.
--
-- NOTE: luck is ADDITIVE game-wide now (ThrowHandler adds WeatherLuck-1 to every
-- player's personal luck), so this is the one seam to raise a Luck above 1 if a
-- shared, everyone-gets-it luck spike is ever wanted during an event. Left at 1 for now.
-- Duration is not fixed per event any more; each occurrence rolls 4-7 minutes.
local EVENTS = {
	{ Name = "Fog",          Luck = 1, Mut = 1, Weight = 30,  Tint = { 200, 210, 220 }, Emoji = "\u{1F32B}\u{FE0F}" },
	{ Name = "Sandstorm",    Luck = 1, Mut = 1, Weight = 25,  Tint = { 232, 178, 108 }, Emoji = "\u{1F3DC}\u{FE0F}" },
	{ Name = "Thunderstorm", Luck = 1, Mut = 1, Weight = 21,  Tint = { 120, 140, 180 }, Emoji = "\u{26C8}\u{FE0F}" },
	{ Name = "Blizzard",     Luck = 1, Mut = 1, Weight = 15,  Tint = { 226, 240, 255 }, Emoji = "\u{2744}\u{FE0F}" },
	{ Name = "Aurora",       Luck = 1, Mut = 1, Weight = 11,  Tint = { 120, 255, 190 }, Emoji = "\u{1F30C}" },
	{ Name = "Shooting Star", Luck = 1, Mut = 1, Weight = 6.9, Tint = { 170, 200, 255 }, Emoji = "\u{1F320}" },
	{ Name = "Blood Moon",   Luck = 1, Mut = 1, Weight = 2.5, Tint = { 255, 120, 120 }, Emoji = "\u{1F314}" },
	{ Name = "Golden Hour",  Luck = 1, Mut = 1, Weight = 1,   Tint = { 255, 215, 140 }, Emoji = "\u{2600}\u{FE0F}" },
}

local WARN_SECONDS = 20          -- heads-up before an event starts
local EVENT_MIN, EVENT_MAX = 240, 420   -- 4 to 7 minutes

-- Pacing: after an event ends, wait at least this long before rolling again, so
-- events come no more often than once every ~20 minutes. Each roll only has a
-- CHANCE to spawn one, so some windows stay clear.
local EVENT_COOLDOWN = 20 * 60   -- 20-minute minimum gap after an event
local ROLL_INTERVAL  = 5 * 60    -- how often we roll for the next event
local ROLL_CHANCE    = 0.5       -- chance a given roll actually spawns an event

local TOTAL_WEIGHT = 0
for _, e in ipairs(EVENTS) do TOTAL_WEIGHT += e.Weight end

local function pickEvent()
	local r = math.random() * TOTAL_WEIGHT
	local cum = 0
	for _, e in ipairs(EVENTS) do
		cum += e.Weight
		if r < cum then return e end
	end
	return EVENTS[#EVENTS]
end

local WeatherHandler = {}
local current = CLEAR
local currentEndsAt = 0

local function payload(w, endsAt)
	-- carry the event's mutation so the banner can advertise the real reward
	local ev = Mutations.Events[w.Name]
	return {
		Name = w.Name, Luck = w.Luck, Mut = w.Mut,
		IsEvent = w.IsEvent ~= false and w.Name ~= "Clear",
		EndsAt = endsAt, Tint = w.Tint, Emoji = w.Emoji,
		MutName = ev and ev.Name or nil,
		MutChance = ev and ev.Chance or nil,
		MutMult = ev and ev.Mult or nil,
	}
end

function WeatherHandler.Apply(w, durationOverride)
	current = w
	currentEndsAt = os.time() + (durationOverride or w.Duration or 180)
	ReplicatedStorage:SetAttribute("WeatherName", w.Name)
	ReplicatedStorage:SetAttribute("WeatherLuck", w.Luck)
	ReplicatedStorage:SetAttribute("WeatherMut", w.Mut)
	ReplicatedStorage:SetAttribute("WeatherEndsAt", currentEndsAt)
	remotes.WeatherState:FireAllClients(payload(w, currentEndsAt))
end

-- Apply an event BY NAME, looking up its real Tint/Emoji from the EVENTS table above.
-- Exists so callers outside this module (the dev weather command) cannot drift from the
-- authored definitions by hand-rolling a payload -- a wrong Tint or a missing Emoji would
-- silently give the banner the wrong colour and no icon.
-- Returns false plus the valid names when the name does not match.
function WeatherHandler.ApplyByName(name, duration)
	if typeof(name) ~= "string" then return false, nil end
	local want = name:lower()
	if want == "clear" or want == "none" or want == "off" then
		WeatherHandler.Apply(CLEAR)
		return true, "Clear"
	end
	-- exact match first, then unique prefix, so "/wx thun" works but an ambiguous stub does not
	local exact, prefix, prefixCount
	for _, e in ipairs(EVENTS) do
		local lower = e.Name:lower()
		if lower == want then exact = e end
		if lower:sub(1, #want) == want then
			prefix = e
			prefixCount = (prefixCount or 0) + 1
		end
	end
	local pick = exact or (prefixCount == 1 and prefix or nil)
	if not pick then return false, nil end
	WeatherHandler.Apply(pick, duration or math.random(EVENT_MIN, EVENT_MAX))
	return true, pick.Name
end

-- every event name, for the dev command's help text
function WeatherHandler.EventNames()
	local t = {}
	for _, e in ipairs(EVENTS) do t[#t + 1] = e.Name end
	return t
end

-- Broadcast an incoming event. Rides the existing WeatherState remote with a
-- Warning flag, so clients that only care about the live event ignore it.
function WeatherHandler.Warn(w, seconds)
	local ev = Mutations.Events[w.Name]
	remotes.WeatherState:FireAllClients({
		Warning = true,
		Name = w.Name,
		Emoji = w.Emoji,
		Tint = w.Tint,
		StartsAt = os.time() + seconds,
		Seconds = seconds,
		MutName = ev and ev.Name or nil,
		MutChance = ev and ev.Chance or nil,
		MutMult = ev and ev.Mult or nil,
	})
end

function WeatherHandler.Init()
	WeatherHandler.Apply(CLEAR)

	Players.PlayerAdded:Connect(function(player)
		task.wait(1.5)
		if player.Parent then
			remotes.WeatherState:FireClient(player, payload(current, currentEndsAt))
		end
	end)

	task.spawn(function()
		-- first event can arrive after a short roll period; every event afterwards
		-- is gated behind the 20-minute cooldown set at the end of the loop.
		local waitBeforeRolling = ROLL_INTERVAL
		while true do
			task.wait(waitBeforeRolling)

			-- roll for an event; keep rolling on the interval until one spawns, so
			-- events still have their chance without being guaranteed on every try.
			while math.random() >= ROLL_CHANCE do
				task.wait(ROLL_INTERVAL)
			end

			local ev = pickEvent()
			-- tell everyone what's coming, then hold for the countdown
			WeatherHandler.Warn(ev, WARN_SECONDS)
			task.wait(WARN_SECONDS)

			local dur = math.random(EVENT_MIN, EVENT_MAX)
			WeatherHandler.Apply(ev, dur)
			task.wait(dur)
			WeatherHandler.Apply(CLEAR)

			-- one just spawned -> wait at least 20 minutes before rolling again
			waitBeforeRolling = EVENT_COOLDOWN
		end
	end)

	print("WeatherHandler online")
end

return WeatherHandler
