-- SoundKit: every sound effect in the game, in one place.
--
-- Before this there was no audio layer at all -- three stock rbxasset sounds
-- scattered across three scripts, no Sound instances saved, nothing in
-- SoundService. Sounds are declared here BY NAME so a call site never carries
-- an asset id, and changing a sound is a one-line edit instead of a hunt.
--
-- Every id below was verified to actually LOAD in this experience before being
-- added. Roblox gates third-party audio and an unusable id fails SILENTLY --
-- no error, just no sound -- so "it looked right in the code" proves nothing.

local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local M = {}

M.Ids = {
	-- Catch ladder. Deliberately ALL ONE FAMILY ("bling diamond pickup"), picked
	-- by ear off the audition board -- "easy on the ears". The first attempt mixed
	-- a harsh electronic ping with two different bell samples and read as noise.
	catchCommon = "rbxassetid://4612374209",        -- bling pickup 1, softest
	catchRare   = "rbxassetid://4612374495",        -- bling pickup 3, the approved one
	catchEpic   = "rbxassetid://4612374393",        -- bling pickup 2
	catchLegend = "rbxassetid://4612374036",        -- bling BIG pickup, top of the ladder
	-- generic sting for a rare mutation; REPLACES the catch sound, never layers
	mutation    = "rbxassetid://4612374036",
	-- The top mutations get their OWN voice rather than a pitched-up version of
	-- everything else. See MUTATION_SOUND in RareCatchClient for the mapping.
	angel       = "rbxassetid://102859001475552",   -- choir, 2.6s        (Angel, r12)
	demon       = "rbxassetid://9114628818",        -- deep growl, 2.1s   (Demon, r11)
	glitched    = "rbxassetid://137930743906958",   -- glitch sfx, 1.8s   (Glitched, r10)
	cash        = "rbxassetid://6786936397",        -- coin_effect
	place       = "rbxassetid://9113805426",        -- ProSoundEffects, dirt impact
	uiClick     = "rbxasset://sounds/switch.wav",
	splash      = "rbxasset://sounds/impact_water.mp3",
}

-- One template per sound, parented to SoundService so the asset resolves once
-- for the session instead of on every play.
local templates = {}
local function template(name)
	local id = M.Ids[name]
	if not id then
		warn("[SoundKit] unknown sound: " .. tostring(name))
		return nil
	end
	local t = templates[name]
	if not t or not t.Parent then
		t = Instance.new("Sound")
		t.Name = "tpl_" .. name
		t.SoundId = id
		t.Volume = 0
		t.Parent = SoundService
		templates[name] = t
	end
	return t
end

-- Warm every template up front so the first catch of a session is not silent
-- while the asset streams in.
function M.preload()
	for name in pairs(M.Ids) do template(name) end
end

-- where: nil for a flat 2D sound (UI, or something that happened to YOU),
--        a BasePart or Vector3 to place it in the world so distance applies.
-- opts:  volume, speed, range
function M.play(name, where, opts)
	local t = template(name)
	if not t then return nil end
	opts = opts or {}

	local s = t:Clone()
	s.Name = name
	-- 0.5 was too hot across the board -- feedback was "loud rings". Call sites
	-- should still pass an explicit volume; this default is for quiet incidentals.
	s.Volume = opts.volume or 0.25
	s.PlaybackSpeed = opts.speed or 1

	-- TimeLength is 0 until the asset loads, so the cleanup delay needs a floor
	-- or a clone can be destroyed before it has made a sound.
	local life = math.max(t.TimeLength, 3) + 0.5

	if typeof(where) == "Instance" and where:IsA("BasePart") then
		s.RollOffMaxDistance = opts.range or 90
		s.Parent = where
	elseif typeof(where) == "Vector3" then
		local anchor = Instance.new("Part")
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one
		anchor.CFrame = CFrame.new(where)
		anchor.Parent = workspace
		s.RollOffMaxDistance = opts.range or 90
		s.Parent = anchor
		Debris:AddItem(anchor, life)
	else
		s.Parent = SoundService
	end

	s:Play()
	Debris:AddItem(s, life)
	return s
end

return M
