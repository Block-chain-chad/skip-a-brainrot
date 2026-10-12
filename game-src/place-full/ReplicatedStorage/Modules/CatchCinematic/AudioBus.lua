--!strict
-- CatchCinematic.AudioBus -- slot-based playback for the cinematic's OWN sounds,
-- plus duck/silence/restore of every OTHER playing Sound in the game (the
-- "ambient" set) so the 0.45s dead-air beat actually reads as dead air.
--
-- Slot resolution: cfg (Config.ASSETS) maps a slot name to either "kit:<name>"
-- (routes through SoundKit.play) or a raw "rbxassetid://..." id (routes through
-- SoundKit.playId). Volume is cfg.VOLUMES[slot] unless opts.volume overrides it.
--
-- Ambient set: every Sound instance found under SoundService or Workspace.SFX
-- (GetDescendants -- both are shallow-and-deep folders of other people's sounds)
-- that IS Playing and is NOT one of ours (identity-checked against _oursSet).
-- Snapshotted ONCE per sound (first time it's seen), original Volume remembered
-- forever until cleanup()/restoreAmbient() lets it go.
--
-- Sound.Volume is NEVER tweened -- every ramp here is a hand-lerp task.spawn
-- loop, matching PostFX's pattern: render-throttle-safe and proven correct,
-- rather than depending on TweenService progress, which read back as stalled
-- during a backgrounded/render-throttled verification session (not a
-- place-wide TweenService defect). duckAmbient/restoreAmbient share a
-- generation counter so the latest call always wins over an in-flight one.
-- silence()/unsilence() are hard,
-- instantaneous cuts (the "dead air" beat must not fade) and operate
-- independently of whatever hand-lerp is mid-flight -- silence() bumps the
-- generation counter to cancel any in-progress duck/restore first, so a lerp
-- from a moment ago can't stomp the hard-cut a frame later.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local SoundKit = require(ReplicatedStorage.Modules.SoundKit)
-- THE MUSIC IS NOT IN THE AMBIENT SET any more (2026-09-21). MusicClient is the single
-- writer of the soundtrack's Volume and multiplies MusicDuck.level() into every write,
-- so this bus ducks/silences/restores the music THROUGH MusicDuck (one request id per
-- bus) and hand-lerps only the true ambience -- weather beds, lake, other people's
-- sounds. Two writers on one Sound was how a cut that started mid-fade left the music
-- parked at the wrong level.
local MusicDuck = require(ReplicatedStorage.Modules.MusicDuck)
local MUSIC_ID = "cinematic"
local MUSIC_RELEASE_SECONDS = 0.8   -- how the music comes back on cleanup: a ramp, never a snap

export type AudioBusCfg = { [string]: any }

export type PlayOpts = {
	volume: number?,
	speed: number?,
	range: number?,
	where: (Instance | Vector3)?,
}

type OursEntry = {
	sound: Sound,
	volume: number,
	preSilence: number?,
}

type SnapshotEntry = {
	original: number,
	preSilence: number?,
}

local AudioBus = {}
AudioBus.__index = AudioBus

export type Bus = typeof(setmetatable(
	{} :: {
		_cfg: AudioBusCfg,
		_ours: { OursEntry },
		_oursSet: { [Sound]: boolean },
		_snapshots: { [Sound]: SnapshotEntry },
		_silenced: boolean,
		_gen: number,
		_destroyed: boolean,
		_musicLevel: number,      -- the last duck level asked of the music (1 = none)
		_musicPreSilence: number?, -- what to put back on unsilence()
	},
	AudioBus
))

function AudioBus.new(cfg: AudioBusCfg): Bus
	local self = setmetatable({
		_cfg = cfg,
		_ours = {} :: { OursEntry },
		_oursSet = {} :: { [Sound]: boolean },
		_snapshots = {} :: { [Sound]: SnapshotEntry },
		_silenced = false,
		_gen = 0,
		_destroyed = false,
		_musicLevel = 1,
		_musicPreSilence = nil,
	}, AudioBus)
	return (self :: any) :: Bus
end

-- Is this Sound part of the soundtrack (MusicClient's SoundService.Music folder)?
local function isMusic(s: Instance): boolean
	local folder = SoundService:FindFirstChild("Music")
	return folder ~= nil and s:IsDescendantOf(folder)
end

-- Resolves "kit:<name>" -> SoundKit.play(name, ...) or "rbxassetid://..." ->
-- SoundKit.playId(id, ...). Volume: opts.volume, else cfg.VOLUMES[slot], else
-- 0.5. Returns the Sound (nil if the slot is unknown or SoundKit declined).
function AudioBus:play(slot: string, opts: PlayOpts?): Sound?
	if self._destroyed then
		return nil
	end
	local assetRef = self._cfg[slot]
	if type(assetRef) ~= "string" then
		warn("[AudioBus] unknown slot: " .. tostring(slot))
		return nil
	end
	-- An EMPTY ref is a slot that is deliberately silent until the owner supplies an
	-- asset (Config.ASSETS comments say which): the beat plays as a rest, no warning.
	if assetRef == "" then
		return nil
	end

	local volumes = self._cfg.VOLUMES
	local fallbackVol = (type(volumes) == "table" and type(volumes[slot]) == "number") and volumes[slot] or 0.5
	local o = opts or {}
	local volume = (type(o.volume) == "number") and o.volume or fallbackVol
	local playOpts = { volume = volume, speed = o.speed, range = o.range }

	local sound: Sound? = nil
	if assetRef:sub(1, 4) == "kit:" then
		local kitName = assetRef:sub(5)
		local ok, result = pcall(SoundKit.play, kitName, o.where, playOpts)
		if ok then
			sound = result
		else
			warn("[AudioBus] slot '" .. slot .. "' (kit:" .. kitName .. ") errored: " .. tostring(result))
		end
	elseif assetRef:sub(1, 13) == "rbxassetid://" then
		local ok, result = pcall(SoundKit.playId, assetRef, o.where, playOpts)
		if ok then
			sound = result
		else
			warn("[AudioBus] slot '" .. slot .. "' (" .. assetRef .. ") errored: " .. tostring(result))
		end
	else
		warn("[AudioBus] slot '" .. slot .. "' has an unrecognised asset ref: " .. assetRef)
	end

	if sound then
		local entry: OursEntry = { sound = sound, volume = volume, preSilence = nil }
		table.insert(self._ours, entry)
		self._oursSet[sound] = true
		-- A sound played AFTER silence() is the sound OF the silent beat (God's rumble at
		-- 0.3s, under the world's dead air) and is heard. This used to mute it until
		-- unsilence(), which left God's first 1.3s completely silent and dumped rumble,
		-- beam and choir on the player at once. silence() still hard-cuts everything
		-- that was already playing, ours included.
	end
	return sound
end

-- Adds every currently-playing, not-ours Sound under SoundService/Workspace.SFX
-- to the snapshot set (idempotent -- a Sound already snapshotted keeps its
-- original ORIGINAL volume, never overwritten by a later call).
function AudioBus:_snapshotAmbient()
	local roots: { Instance } = { SoundService }
	local sfx = Workspace:FindFirstChild("SFX")
	if sfx then
		table.insert(roots, sfx)
	end
	for _, root in ipairs(roots) do
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("Sound") and d.Playing and not self._oursSet[d] and not self._snapshots[d] and not isMusic(d) then
				self._snapshots[d] = { original = d.Volume, preSilence = nil }
			end
		end
	end
end

-- Hand-lerp every ambient sound toward `toLevel` (a FRACTION 0..1 of that
-- sound's own original volume -- ambient sounds have wildly different authored
-- levels, so a single absolute target would blow some out and mute others) over
-- `seconds`. Supersedes any in-flight duck/restore.
-- musicLevel (optional): a separate target for the soundtrack -- God's choir wants the
-- ambience back to a whisper and the music to NOTHING. Defaults to toLevel.
function AudioBus:duckAmbient(toLevel: number, seconds: number, musicLevel: number?)
	if self._destroyed then
		return
	end
	toLevel = math.clamp(toLevel, 0, 1)
	seconds = math.max(seconds, 0.02)
	self:_snapshotAmbient()
	local m = math.clamp(tonumber(musicLevel) or toLevel, 0, 1)
	self._musicLevel = m
	self._musicPreSilence = nil
	self._silenced = false
	MusicDuck.set(MUSIC_ID, m, seconds)

	self._gen += 1
	local myGen = self._gen
	local snapshots = self._snapshots

	task.spawn(function()
		local starts: { [Sound]: number } = {}
		for sound in pairs(snapshots) do
			starts[sound] = sound.Volume
		end
		local t0 = os.clock()
		while self._gen == myGen and not self._destroyed do
			local a = math.clamp((os.clock() - t0) / seconds, 0, 1)
			for sound, snap in pairs(snapshots) do
				if sound.Parent then
					local s = starts[sound] or snap.original
					local target = snap.original * toLevel
					sound.Volume = s + (target - s) * a
				end
			end
			if a >= 1 then
				break
			end
			task.wait()
		end
	end)
end

-- Hard-cut OURS to 0 AND the ducked ambient set to 0 -- the 0.45s dead-air beat.
-- Instantaneous, not a lerp. Cancels any in-flight duck/restore first so it
-- can't get overwritten a frame later.
function AudioBus:silence()
	if self._destroyed then
		return
	end
	-- Snapshot FIRST. This used to iterate whatever duckAmbient had already collected,
	-- so a cut that opened with silence() (God's bonk) silenced nothing but its own
	-- sounds -- the "world goes quiet" beat never happened.
	self:_snapshotAmbient()
	self._gen += 1
	self._silenced = true
	self._musicPreSilence = self._musicLevel
	MusicDuck.set(MUSIC_ID, 0, 0)   -- the hard cut is the beat
	for sound, snap in pairs(self._snapshots) do
		if sound.Parent then
			snap.preSilence = sound.Volume
			sound.Volume = 0
		end
	end
	for _, entry in ipairs(self._ours) do
		if entry.sound.Parent then
			entry.preSilence = entry.sound.Volume
			entry.sound.Volume = 0
		end
	end
end

-- Hard-cut back to whatever level everything was at the instant BEFORE
-- silence() -- undoes JUST the silence() cut, not a full restore to original
-- (that is restoreAmbient's job).
function AudioBus:unsilence()
	if self._destroyed or not self._silenced then
		return
	end
	self._silenced = false
	-- the music comes back to whatever duck it had before the cut -- over a short ramp
	-- rather than the hard step the ambience takes, since a step UP in music reads as a
	-- glitch where a step down reads as a beat
	MusicDuck.set(MUSIC_ID, self._musicPreSilence or self._musicLevel, 0.15)
	self._musicPreSilence = nil
	for sound, snap in pairs(self._snapshots) do
		if sound.Parent and snap.preSilence then
			sound.Volume = snap.preSilence
		end
		snap.preSilence = nil
	end
	for _, entry in ipairs(self._ours) do
		if entry.sound.Parent and entry.preSilence then
			entry.sound.Volume = entry.preSilence
		end
		entry.preSilence = nil
	end
end

-- Hand-lerp every ambient sound back to its ORIGINAL volume over `seconds`.
-- Supersedes any in-flight duck/restore.
function AudioBus:restoreAmbient(seconds: number)
	if self._destroyed then
		return
	end
	seconds = math.max(seconds, 0.02)
	self._musicLevel = 1
	self._musicPreSilence = nil
	self._silenced = false
	MusicDuck.clear(MUSIC_ID, seconds)
	self._gen += 1
	local myGen = self._gen
	local snapshots = self._snapshots

	task.spawn(function()
		local starts: { [Sound]: number } = {}
		for sound in pairs(snapshots) do
			starts[sound] = sound.Volume
		end
		local t0 = os.clock()
		while self._gen == myGen and not self._destroyed do
			local a = math.clamp((os.clock() - t0) / seconds, 0, 1)
			for sound, snap in pairs(snapshots) do
				if sound.Parent then
					local s = starts[sound] or snap.original
					sound.Volume = s + (snap.original - s) * a
				end
			end
			if a >= 1 then
				break
			end
			task.wait()
		end
	end)
end

-- Stops ours, restores every snapshotted volume -- exactly. Final, idempotent
-- safety net regardless of what duck/silence/restore sequence ran before it.
function AudioBus:cleanup()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._gen += 1
	-- The music's return is a RAMP even on the safety net: MusicDuck owns the ramp, so
	-- it finishes after this bus is gone. (restoreAmbient in the handoff beat normally
	-- got there first; this catches the cancel/kill paths.)
	MusicDuck.clear(MUSIC_ID, MUSIC_RELEASE_SECONDS)
	for _, entry in ipairs(self._ours) do
		if entry.sound.Parent then
			pcall(function()
				entry.sound:Stop()
			end)
		end
	end
	self._ours = {}
	self._oursSet = {}
	for sound, snap in pairs(self._snapshots) do
		if sound.Parent then
			sound.Volume = snap.original
		end
	end
	self._snapshots = {}
end

return AudioBus
