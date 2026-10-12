--!strict
-- MusicDuck: the one place that decides how far the soundtrack is pulled down under
-- a reveal. Client-side, instance-free, requires nothing.
--
-- WHY. Before this, two writers fought over the music track's Volume: MusicClient's
-- own fade loop and AudioBus's ambient duck (it hand-lerped every playing Sound under
-- SoundService, the track included). Whichever wrote last won, a cut that started
-- during a track's 3s fade-in could leave the music parked at the wrong level, and
-- the pops (Common..Legendary) had no way to duck at all -- they just played louder
-- sounds over the bed. Now MusicClient is the ONLY writer of the track's Volume and
-- multiplies in MusicDuck.level() every step; everything that wants the music out of
-- the way asks here.
--
-- MODEL. Named requests, each a ramp from its current level to a target over `seconds`
-- (0 = instant, the intentional hard cut). The effective level is the MINIMUM over
-- every live request, so a stronger duck always wins and a weaker one never lifts it.
-- clear(id) ramps a request back to 1 and forgets it once it gets there, so a caller
-- that dies mid-ramp cannot leave the music stuck low -- and a caller that is torn
-- down (a cinematic's cleanup) can still hand the music a SMOOTH return, because the
-- ramp lives here, not in the caller.
--
-- The rarity ladder itself (how far each tier ducks) lives with the presentation that
-- plays it: CatchPop's presets for the pops, CatchCinematic.Config.MUSIC_DUCK for the
-- cuts. This module only knows levels and ramps.
local MusicDuck = {}

type Request = {
	from: number,
	to: number,
	t0: number,
	secs: number,
	release: boolean, -- forget once it reaches 1
}

local requests: { [string]: Request } = {}
local changed: BindableEvent? = nil

local function levelOf(req: Request, now: number): number
	if req.secs <= 0 then
		return req.to
	end
	local a = math.clamp((now - req.t0) / req.secs, 0, 1)
	-- smoothstep: a duck that starts and stops abruptly reads as a fault, not a mix
	local e = a * a * (3 - 2 * a)
	return req.from + (req.to - req.from) * e
end

-- Ramp the request `id` to `level` (0..1, a multiplier on the track's own volume)
-- over `seconds`. Re-issuing an id restarts the ramp from wherever it currently is.
function MusicDuck.set(id: string, level: number, seconds: number?)
	if type(id) ~= "string" or id == "" then
		return
	end
	local now = os.clock()
	local cur = requests[id]
	local from = cur and levelOf(cur, now) or 1
	requests[id] = {
		from = from,
		to = math.clamp(tonumber(level) or 1, 0, 1),
		t0 = now,
		secs = math.max(tonumber(seconds) or 0, 0),
		release = false,
	}
	if changed then
		changed:Fire()
	end
end

-- Ramp the request back to full over `seconds` and forget it on arrival. Safe to
-- call for an id that was never set.
function MusicDuck.clear(id: string, seconds: number?)
	if type(id) ~= "string" or id == "" then
		return
	end
	local cur = requests[id]
	if not cur then
		return
	end
	local now = os.clock()
	requests[id] = {
		from = levelOf(cur, now),
		to = 1,
		t0 = now,
		secs = math.max(tonumber(seconds) or 0, 0),
		release = true,
	}
	if changed then
		changed:Fire()
	end
end

-- Effective multiplier right now: the minimum over every live request. Prunes
-- released requests that have arrived at 1.
function MusicDuck.level(): number
	local now = os.clock()
	local out = 1
	for id, req in pairs(requests) do
		local v = levelOf(req, now)
		if req.release and v >= 0.999 then
			requests[id] = nil
		else
			if v < out then
				out = v
			end
		end
	end
	return out
end

-- True while any request is live (including one still releasing): the music driver
-- can idle at its own pace otherwise.
function MusicDuck.active(): boolean
	return next(requests) ~= nil
end

-- Fires whenever a request is set or cleared -- lets a driver wake from idle rather
-- than poll. Optional; level() is always the source of truth.
function MusicDuck.Changed(): RBXScriptSignal
	if not changed then
		changed = Instance.new("BindableEvent")
	end
	return (changed :: BindableEvent).Event
end

-- Studio/debug view.
function MusicDuck.debugState(): { [string]: number }
	local now = os.clock()
	local out = {}
	for id, req in pairs(requests) do
		out[id] = levelOf(req, now)
	end
	return out
end

return MusicDuck
