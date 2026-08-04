-- LakeAmbience: one always-on water bed at the valley lake.
--
-- POSITIONAL, not global (2D), and that is a deliberate split from WeatherClient,
-- whose beds ARE global. Weather is global -- rain falls on the whole map -- but
-- water is a PLACE. Two reasons this has to fall off with distance:
--   1. The playable world is three islands ~8000 studs apart (valley lake, the
--      trading island, the frozen tundra). A 2D bed would follow the player to
--      the tundra and play lake water over a snowfield.
--   2. Inside the valley, the camps sit at z ~ -113 and the dock at z ~ 22. Your
--      campfire should not sound like you are standing on the shoreline.
--
-- Client-side: it is per-player furniture, nothing replicates, and it costs the
-- server nothing. SoundKit owns the id; the SFX slider drives the level through
-- OnSfxVolume, because a long-lived loop is not an M.play clone and would
-- otherwise ignore the slider completely.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundKit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundKit"))

local VOLUME = 0.10   -- under the 0.15 music bed: furniture beneath furniture
local FADE   = 2.0    -- slightly faster than music's 3.0 so arrival is not silent
local RANGE  = 150    -- dock (z~22) to camp (z~-113) is ~135 studs: present on the
                      -- shore, gone at the campfire

local gameWorld = workspace:WaitForChild("GameWorld")

-- Anchor on the dock if it is there, else the throw zone, else the lake centre.
-- Never errors out of existence: a missing dock costs the bed its position, not
-- its life.
local function anchorPosition()
	local dock = gameWorld:FindFirstChild("SkipDock")
	if dock then
		local ok, cf = pcall(function() return dock:GetPivot() end)
		if ok and cf then return cf.Position + Vector3.new(0, 0, 40) end
	end
	local zone = gameWorld:FindFirstChild("ThrowZone")
	if zone then return zone.Position + Vector3.new(0, 0, 40) end
	return Vector3.new(0, 2, 120)   -- open water up the lake
end

local host = Instance.new("Part")
host.Name = "LakeAmbienceHost"
host.Anchored = true
host.CanCollide = false
host.CanQuery = false
host.CanTouch = false
host.Transparency = 1
host.Size = Vector3.one
host.CFrame = CFrame.new(anchorPosition())
host.Parent = workspace

local bed = Instance.new("Sound")
bed.Name = "LakeBed"
bed.SoundId = SoundKit.Ids.ambienceShore1   -- water on a beach, 8.53s loop
bed.Looped = true
bed.Volume = 0
bed.RollOffMaxDistance = RANGE
bed.RollOffMode = Enum.RollOffMode.InverseTapered
bed:SetAttribute("BaseVolume", VOLUME)
bed.Parent = host
bed:Play()

-- Level is written DIRECTLY, never tweened. The fade is a short stepped loop
-- instead: one authority over this Sound's Volume means a slider moving mid-fade
-- simply retargets the loop rather than racing a tween that would finish later
-- and overwrite it.
local scale = SoundKit.SfxScale and SoundKit.SfxScale() or 1
local target = VOLUME * scale
local fadeToken = 0

local function setLevel(v, fadeSeconds)
	target = v
	fadeToken += 1
	local myToken = fadeToken
	if not fadeSeconds or fadeSeconds <= 0 then
		bed.Volume = target
		return
	end
	task.spawn(function()
		local from = bed.Volume
		local steps = math.max(1, math.floor(fadeSeconds / 0.05))
		for i = 1, steps do
			if myToken ~= fadeToken or not bed.Parent then return end
			bed.Volume = from + (target - from) * (i / steps)
			task.wait(fadeSeconds / steps)
		end
		if myToken == fadeToken and bed.Parent then bed.Volume = target end
	end)
end

setLevel(VOLUME * scale, FADE)

-- Live slider control. Fires once on registration too, so a level restored from a
-- saved profile lands even if it arrives after this script has already faded in.
SoundKit.OnSfxVolume(function(v)
	scale = v
	setLevel(VOLUME * v, 0.15)
end)
