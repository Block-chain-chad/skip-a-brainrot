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
local SoundKit = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("SoundKit"))

local VOLUME    = 0.15   -- under the weather beds and well under the SFX
-- The Settings music slider is a MULTIPLIER over VOLUME, never an absolute level.
-- SetCategoryVolume cannot simply write s.Volume here: this script tweens Volume
-- for its own fades, so a direct write would be overwritten by the next fade and
-- lost entirely on the next track. Instead we hold the live scale and re-apply
-- base * scale ourselves, both on slider moves and whenever a track starts.
local musicScale = SoundKit.MusicScale and SoundKit.MusicScale() or 1

-- Volume is written DIRECTLY in steps rather than tweened. Measured in this place:
-- a TweenService tween on Sound.Volume does not move the property, so every fade
-- here silently left the track at 0 and the music was only ever audible after a
-- slider move (SetCategoryVolume writes Volume directly). Direct writes always
-- work, so the fade is a loop. Token-guarded: a new fade supersedes an old one
-- instead of the two fighting over the same property.
local fadeToken = 0
local function fadeSound(snd, to, seconds)
	if not snd or not snd.Parent then return end
	fadeToken += 1
	local myToken = fadeToken
	if not seconds or seconds <= 0 then
		snd.Volume = to
		return
	end
	local from = snd.Volume
	local steps = math.max(1, math.floor(seconds / 0.05))
	for i = 1, steps do
		if myToken ~= fadeToken or not snd.Parent then return end
		snd.Volume = from + (to - from) * (i / steps)
		task.wait(seconds / steps)
	end
	if myToken == fadeToken and snd.Parent then snd.Volume = to end
end
local currentTrack = nil
SoundKit.OnMusicVolume(function(v)
	musicScale = v
	-- Re-level the playing track immediately: a slider is a live control, not a
	-- setting that waits for the next song.
	if currentTrack and currentTrack.Parent then
		task.spawn(fadeSound, currentTrack, VOLUME * v, 0.15)
	end
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
		s:SetAttribute("BaseVolume", VOLUME)   -- lets SoundKit scale it without knowing our base
		s.Parent = folder
		s:Play()
		currentTrack = s
		task.spawn(fadeSound, s, VOLUME * musicScale, FADE)

		-- Wait on the measured length rather than s.Ended: Ended does not fire if the asset
		-- fails to stream, which would stall the playlist forever on a bad connection.
		-- The +1 covers small decode differences between the measured and actual length.
		local hold = math.max((t.len or 60) - FADE, 5)
		local t0 = os.clock()
		while not stopped and os.clock() - t0 < hold do task.wait(0.5) end

		fadeSound(s, 0, FADE)
		task.wait(0.2)
		if currentTrack == s then currentTrack = nil end
		if s.Parent then s:Stop(); s:Destroy() end
		if stopped then break end
		task.wait(math.random(GAP_MIN, GAP_MAX))
	end
end)
