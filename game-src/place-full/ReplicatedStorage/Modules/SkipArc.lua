--!strict
-- SkipArc: the ONE description of how a thrown stone travels -- contact count, flight
-- time, per-hop timing and hop heights -- shared by ThrowHandler (the authoritative
-- server flight), ClientMain (the thrower's render-rate ghost + skip counter) and
-- ThrowCam (the tracking camera). Change a number here and every side moves together;
-- before this module the arc formula was copied by hand into ThrowHandler and
-- ClientMain with a "change one side and the ghost parts company with the splashes"
-- warning.
--
-- PACING (2026-09-21 throw-pacing pass). Distance is progression, not a waiting
-- punishment: a 900-stud throw used to fly for 3.4s at a constant cadence, and the
-- thrower's camera followed all of it plus a 1.4s dwell. The flight is now shorter
-- overall (TIME_MAX 4.2 -> 2.7; the same 900 studs take 2.7s) AND non-linear: each hop
-- is HOP_RATIO the duration of the one before it, so the opening skips play at a
-- readable pace and the distant ones accelerate away. The RESULT is untouched --
-- distance, rarity, the grant at landing and the splash positions are exactly what
-- they were; only the clock the stone follows between them changed.
local SkipArc = {}

SkipArc.CONTACT_SPACING = 18   -- ~one water contact per 18 studs
SkipArc.MIN_CONTACTS = 2
SkipArc.MAX_CONTACTS = 8

SkipArc.TIME_BASE = 0.9        -- seconds a zero-length throw would take
SkipArc.TIME_PER_STUD = 1 / 500
SkipArc.TIME_MIN = 1.15
SkipArc.TIME_MAX = 2.7

-- Each hop lasts this fraction of the previous one. 1.0 = the old constant cadence.
-- 0.86 over 8 hops: first hop ~20% of the flight, last ~7% -- the stone visibly
-- speeds off into the distance while the first two or three skips stay readable.
-- The acceleration is DISTANCE-GATED (HopRatio): a throw up to ACCEL_FROM studs keeps
-- the uniform cadence (its hops are already short, and an accelerated 150-stud throw
-- ended in 80ms taps that smeared the splashes and the skip counter together); it
-- ramps to the full ratio at ACCEL_FULL.
SkipArc.HOP_RATIO = 0.86
SkipArc.ACCEL_FROM = 200
SkipArc.ACCEL_FULL = 900

function SkipArc.HopRatio(distance: number?): number
	if type(distance) ~= "number" then
		return SkipArc.HOP_RATIO
	end
	local a = math.clamp((distance - SkipArc.ACCEL_FROM) / math.max(SkipArc.ACCEL_FULL - SkipArc.ACCEL_FROM, 1), 0, 1)
	return 1 - (1 - SkipArc.HOP_RATIO) * a
end

function SkipArc.Contacts(distance: number): number
	return math.clamp(math.floor(distance / SkipArc.CONTACT_SPACING) + 1, SkipArc.MIN_CONTACTS, SkipArc.MAX_CONTACTS)
end

function SkipArc.TotalTime(distance: number): number
	return math.clamp(SkipArc.TIME_BASE + distance * SkipArc.TIME_PER_STUD, SkipArc.TIME_MIN, SkipArc.TIME_MAX)
end

-- Hop k (1-based) runs from starts[k] to starts[k + 1]; starts[1] = 0 and
-- starts[n + 1] = totalTime exactly, so the landing never drifts off the server's
-- own clock however the hops are weighted.
function SkipArc.HopStarts(nContacts: number, totalTime: number, distance: number?): { number }
	local n = math.max(math.floor(nContacts), 1)
	local r = SkipArc.HopRatio(distance)
	local weights = table.create(n)
	local sum = 0
	local w = 1
	for k = 1, n do
		weights[k] = w
		sum += w
		w *= r
	end
	local starts = table.create(n + 1)
	local t = 0
	starts[1] = 0
	for k = 1, n do
		t += totalTime * (weights[k] / sum)
		starts[k + 1] = t
	end
	starts[n + 1] = totalTime
	return starts
end

-- Clear, bouncy hop heights (flat-ish so it reads as skipping, not lobbing). The
-- numbers are ThrowHandler's originals, unchanged.
function SkipArc.Apex(k: number, hopLen: number): number
	if k == 1 then
		return math.clamp(hopLen * 0.4, 3, 11)
	end
	return math.max(2.5, math.clamp(hopLen * 0.42, 3, 8) * (0.82 ^ (k - 2)))
end

-- Which hop is live at time t, and how far through it (0..1). Clamps at both ends.
function SkipArc.HopAt(starts: { number }, t: number): (number, number)
	local n = #starts - 1
	if n < 1 then
		return 1, 1
	end
	if t <= 0 then
		return 1, 0
	end
	for k = 1, n do
		local a, b = starts[k], starts[k + 1]
		if t < b then
			return k, math.clamp((t - a) / math.max(b - a, 1e-4), 0, 1)
		end
	end
	return n, 1
end

-- World position of the stone at time t along `points` (origin + one point per
-- contact, as both ThrowHandler and ClientMain build them). Pure: the same inputs
-- always give the same position, so the server stone and the client ghost agree.
function SkipArc.Sample(points: { Vector3 }, starts: { number }, hopLen: number, t: number): (Vector3, number, number)
	local k, alpha = SkipArc.HopAt(starts, t)
	local a, b = points[k], points[k + 1]
	if not a or not b then
		local last = points[#points]
		return last, k, alpha
	end
	local flat = a:Lerp(b, alpha)
	local h = math.sin(alpha * math.pi) * SkipArc.Apex(k, hopLen)
	return Vector3.new(flat.X, flat.Y + h, flat.Z), k, alpha
end

return SkipArc
