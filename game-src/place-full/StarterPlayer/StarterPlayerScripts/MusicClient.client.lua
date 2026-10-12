-- MusicClient: a shuffled chill soundtrack for the camp.
--
-- LICENSING: every track is from Roblox's OWN first-party libraries -- APMOfficial
-- (courtesy of APM Music) and DistrokidOfficial. Same reasoning as WeatherClient's
-- ambience: first-party audio keeps playback rights valid in the live game, where a
-- random community upload can be pulled or fail to authorise. All 14 candidates were
-- verified with ContentProvider:PreloadAsync in this place before being shortlisted.
--
-- CLIENT-SIDE on purpose. Music is a per-player experience: each player gets their own
-- shuffle and their own position in the track, and nothing about it needs replicating.
-- Sounds parent to SoundService so they are 2D and global -- music must not fall off
-- as you walk, which is exactly what would happen if it lived on a part in Workspace.
--
-- VOLUME sits deliberately low. WeatherClient runs its ambience beds at 0.08-0.34 and
-- the campfire register is 0.40; music has to sit UNDER both or it competes with the
-- feedback the player actually needs to hear.
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

-- Lowered 0.22 -> 0.15. Even at 0.22 the music was sitting level with the skip
-- splashes (0.22 each) and masking them, which is backwards: the splash is the
-- feedback for the thing the player just did, the music is furniture.
local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local SoundKit = require(Modules:WaitForChild("SoundKit"))
-- The reveal ducking registry (2026-09-21). Pops and cuts ask it to pull the music
-- down; this script is the ONLY thing that writes the track's Volume, and it
-- multiplies MusicDuck.level() into every write, so nothing else ever has to touch
-- the Sound and two writers can never fight over it again.
local MusicDuck = require(Modules:WaitForChild("MusicDuck"))

local VOLUME    = 0.15   -- under the weather beds and well under the SFX
-- The Settings music slider is a MULTIPLIER over VOLUME, never an absolute level.
-- SetCategoryVolume cannot simply write s.Volume here: this script owns Volume
-- for its own fades, so a direct write would be overwritten by the next step and
-- lost entirely on the next track. Instead we hold the live scale and fold it into
-- every write below.
local musicScale = SoundKit.MusicScale and SoundKit.MusicScale() or 1

-- ONE WRITER. Volume = VOLUME * slider * fade envelope * duck, recomputed and written
-- directly every 50ms while a track plays. Direct writes rather than a tween: measured
-- in this place, a TweenService tween on Sound.Volume does not move the property, so
-- every tween-based fade silently left the track at 0. The fade in/out is an ENVELOPE
-- (0..1) this loop ramps, not a target volume, which is what lets the slider and a
-- reveal duck land mid-fade without either being overwritten.
local env = 0                 -- the fade envelope, 0..1
local envFrom, envTo, envT0, envSecs = 0, 0, 0, 0
local function fadeEnv(to, seconds)
	envFrom = env
	envTo = to
	envT0 = os.clock()
	envSecs = math.max(seconds or 0, 0)
end
local function stepEnv()
	if envSecs <= 0 then
		env = envTo
		return
	end
	local a = math.clamp((os.clock() - envT0) / envSecs, 0, 1)
	env = envFrom + (envTo - envFrom) * a
end
local currentTrack = nil
local function levelNow()
	stepEnv()
	return VOLUME * musicScale * env * MusicDuck.level()
end
SoundKit.OnMusicVolume(function(v)
	musicScale = v   -- the driver loop picks it up on its next step (<= 50ms)
end)
local FADE      = 3.0    -- seconds of fade in / fade out
local GAP_MIN   = 5      -- silence between tracks, so it breathes instead of
local GAP_MAX   = 11     -- running wall-to-wall like a menu screen

-- Durations are measured, not guessed (PreloadAsync + TimeLength in this place).
local PLAYLIST = {
	{ id = "105008212701444", name = "Mountain Air",          len = 144.1 },
	{ id = "107987350831589", name = "Silent Stream Path",    len = 79.0 },
	{ id = "117716119176266", name = "Ethereal Forest Murmur", len = 80.0 },
	{ id = "99678007903413",  name = "Somewhere Beyond",      len = 81.0 },
	{ id = "120950485414901", name = "Velvet Night Tides",    len = 77.4 },
	{ id = "9039590627",      name = "Heartstrings",          len = 60.1 },
	{ id = "92591332804828",  name = "Open Arms",             len = 60.8 },
}

local folder = SoundService:FindFirstChild("Music")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Music"
	folder.Parent = SoundService
end

-- Shuffle the whole list, then walk it, then reshuffle. A plain random pick repeats
-- tracks back-to-back often enough to be noticeable on a 7-track list; a bag shuffle
-- guarantees you hear all 7 before any repeats.
local bag = {}
local function refill()
	bag = table.clone(PLAYLIST)
	for i = #bag, 2, -1 do
		local j = math.random(1, i)
		bag[i], bag[j] = bag[j], bag[i]
	end
end
local lastPlayed
local function nextTrack()
	if #bag == 0 then
		refill()
		-- avoid the seam case: last of the old bag being first of the new one
		if #bag > 1 and bag[1].id == lastPlayed then bag[1], bag[#bag] = bag[#bag], bag[1] end
	end
	local t = table.remove(bag, 1)
	lastPlayed = t.id
	return t
end

local stopped = false
Players.LocalPlayer.AncestryChanged:Connect(function()
	if not Players.LocalPlayer:IsDescendantOf(game) then stopped = true end
end)

task.spawn(function()
	task.wait(4)   -- let the join sequence (offline popup, tutorial) land first
	while not stopped do
		local t = nextTrack()
		local s = Instance.new("Sound")
		s.Name = t.name
		s.SoundId = "rbxassetid://" .. t.id
		s.Looped = false
		s.Volume = 0            -- always fade in; a track snapping on at full volume is jarring
		-- Deliberately NO BaseVolume attribute any more: SoundKit.SetCategoryVolume used it
		-- to write s.Volume from outside, which is exactly the second writer this loop
		-- exists to retire. The slider reaches us through OnMusicVolume instead.
		s.Parent = folder
		s:Play()
		currentTrack = s
		env = 0
		fadeEnv(1, FADE)
		-- the one writer, for the life of this track
		task.spawn(function()
			while s.Parent and currentTrack == s do
				s.Volume = levelNow()
				task.wait(0.05)
			end
		end)

		-- Wait on the measured length rather than s.Ended: Ended does not fire if the asset
		-- fails to stream, which would stall the playlist forever on a bad connection.
		-- The +1 covers small decode differences between the measured and actual length.
		local hold = math.max((t.len or 60) - FADE, 5)
		local t0 = os.clock()
		while not stopped and os.clock() - t0 < hold do task.wait(0.5) end

		fadeEnv(0, FADE)
		task.wait(FADE + 0.2)
		if currentTrack == s then currentTrack = nil end
		if s.Parent then s:Stop(); s:Destroy() end
		if stopped then break end
		task.wait(math.random(GAP_MIN, GAP_MAX))
	end
end)
