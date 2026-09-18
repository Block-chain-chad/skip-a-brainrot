--!strict
-- CatchCinematic.Bridge -- the handshake between the SERVER's ThrowResult (which
-- carries the authoritative grant) and the client-side cinematic that is already
-- playing by the time it lands. Three parties, one small state machine:
--
--   CinematicClient   arm(payload, secs) -> gen   at flight start, thrower only.
--                                                 nil = refused, run no cinematic.
--                     markFailedFor(gen)          play declined/errored
--   Takeover         markRunning(gen)            when its conductor binds
--                     result(gen)                 polled per frame for the
--                                                 authoritative name (reveal-time
--                                                 fallbacks can swap the creature)
--                     finish(gen, ok)             exactly once, at teardown
--   CatchRevealClient tryAdopt(result)            "is this catch cinematic-owned?"
--                     onDone(cb)                  "then tell me how it went"
--
-- STATE:  idle --arm--> armed --markRunning--> running --finish--> idle
--         armed/running --markFailedFor / expiry / reset / superseding arm--> idle,
--         and EVERY one of those transitions fires the pending onDone callbacks.
--
-- ============================ THE INVARIANT ============================
-- NO ThrowResult IS EVER SUPPRESSED UNLESS ITS OWN CINEMATIC RAN TO SUCCESS.
-- tryAdopt() returning true is a PROMISE that some onDone will fire; the ordinary
-- reveal is deferred on the strength of it. Three rules keep that promise, and every
-- state transition below is written to preserve them:
--
--   R1  ONE ARM, ONE ADOPTION. An arm that has already taken a result refuses every
--       later one. ThrowResult carries no throw token (it is FireClient'd to the
--       owner and nothing in it identifies the flight), so "this arm is already
--       spoken for" is the ONLY thing separating throw A's result from throw B's
--       when B lands while A's cinematic is still on screen. Without R1, B's result
--       adopts into A's arm, A's cinematic reports success, and B's catch is
--       revealed by nobody. Ordering makes R1 sufficient rather than merely helpful:
--       ThrowHandler clears its one-stone `inFlight` lock only AFTER revealCatch has
--       fired ThrowResult (ThrowHandler ~line 1116), so throw A's ThrowResult always
--       precedes throw B's MassiveCinematic broadcast.
--   R2  A LIVE RUN IS NEVER CLOBBERED. arm() REFUSES while an arm is "running":
--       the caller runs no cinematic for that throw and stages the stock landing
--       instead. Overwriting would strand the running catch's onDone; stealing the
--       slot would break R1.
--   R3  NOTHING VANISHES SILENTLY. Every exit from armed/running goes through
--       settle(), which answers every pending callback exactly once -- including the
--       arm-expiry sweep and reset(), which used to just drop them.
--
-- Generation counter: every arm has an id, and markRunning/result/finish/
-- markFailedFor all no-op unless the id matches the CURRENT arm. That is what stops
-- a stale, debounced or superseded play from tearing down a live arm belonging to a
-- different throw -- the single worst bug this module can have.
--
-- WHY A SEPARATE MODULE: CatchRevealClient must not require the Takeover, which
-- pulls in CameraRig/WaterFX/HypeUI/... -- every ordinary catch in the game would
-- then depend on the cinematic loading cleanly. This module requires NOTHING, so
-- CatchRevealClient's fail-soft require of it is genuinely cheap. The dependency
-- arrow is one-way: Takeover -> Bridge, never back.
--
-- ARM EXPIRY: arm() happens at flight start; play() happens TotalTime later. If the
-- scheduler between them dies, a permanently-armed Bridge would swallow the reveal of
-- every future Massive catch, so an arm carries a deadline and fails itself (R3).
-- markRunning() EXTENDS that deadline with the run's own budget, because the arm has
-- to outlive the cinematic: a 4.2s flight armed for flight+cancel+slack would
-- otherwise time out around the eruption beat of a 10.7s cutscene and hand the reveal
-- back to the ordinary path ON TOP of the cinematic still playing it.
--
-- CALLBACKS ARE task.spawn'd, ALWAYS. onDone's callback runs PullCeremony, which
-- BLOCKS for seconds; finish() is called from the Takeover's render step, and a
-- render step that blocks for seconds freezes the game.

local Config = require(script.Parent:WaitForChild("Config"))

local Bridge = {}

type Result = { [string]: any }

local DEFAULT_ARM_SECONDS = 12

local gen: number = 0
local state: string = "idle" -- "idle" | "armed" | "running"
-- The CUT the arm was made for (payload.Cut). Since the 2026-09-17 reveal build the
-- arm is keyed on the cut name rather than the size: rarity cuts (Mythic/Secret/God)
-- have no size at all, and a result is adopted iff it ROUTES to the armed cut.
local armedCut: string? = nil
local armExpiresAt: number = 0
local result: Result? = nil
local doneCbs: { (boolean) -> () } = {}
local lastOk: boolean = false -- outcome of the most recently settled arm

local function clearArm()
	state = "idle"
	armedCut = nil
	armExpiresAt = 0
	result = nil
	doneCbs = {}
end

-- R3's single implementation. Every path out of armed/running calls this.
local function settle(ok: boolean)
	local cbs = doneCbs
	clearArm()
	lastOk = ok == true
	for _, cb in ipairs(cbs) do
		task.spawn(cb, lastOk)
	end
end

-- True while an arm is still live. A timed-out arm is FAILED here (not dropped),
-- so an adopted result is handed back to the ordinary reveal instead of vanishing.
local function armLive(): boolean
	if state == "idle" then
		return false
	end
	if os.clock() > armExpiresAt then
		settle(false)
		return false
	end
	return true
end

-- CinematicClient, thrower only, at flight start. Returns the arm's generation, or
-- NIL when refused (R2) -- a nil return means "run no cinematic for this throw".
function Bridge.arm(payload: { [string]: any }, seconds: number?): number?
	if armLive() then
		if state == "running" then
			return nil -- R2
		end
		settle(false) -- an armed-but-never-played arm being superseded (R3)
	end
	gen += 1
	state = "armed"
	armedCut = (type(payload) == "table" and type(payload.Cut) == "string") and payload.Cut or nil
	armExpiresAt = os.clock() + math.max(tonumber(seconds) or DEFAULT_ARM_SECONDS, 1)
	result = nil
	doneCbs = {}
	return gen
end

function Bridge.isCurrent(g: number?): boolean
	return type(g) == "number" and g == gen and armLive()
end

-- Takeover, once its conductor is bound. Promotes armed -> running (so a LATER
-- throw's arm() is refused rather than clobbering it, R2) and pushes the expiry out
-- to cover the run itself -- the caller passes its own wall-clock budget, because the
-- Bridge has no business knowing how long a cut is.
function Bridge.markRunning(g: number?, seconds: number?)
	if type(g) ~= "number" or g ~= gen or state ~= "armed" then
		return
	end
	state = "running"
	local extend = tonumber(seconds)
	if extend then
		armExpiresAt = math.max(armExpiresAt, os.clock() + math.max(extend, 1))
	end
end

-- CatchRevealClient. TRUE means: this catch belongs to a cinematic, do not run the
-- ordinary chain now -- register onDone and let the cinematic decide.
function Bridge.tryAdopt(res: { [string]: any }): boolean
	if not armLive() then
		return false
	end
	if type(res) ~= "table" then
		return false
	end
	-- The cut the RESULT routes to must be the cut that was armed. A pop-tier result
	-- (CUT_FOR == nil) is by definition an ordinary catch and is never adopted.
	-- (Pre-2026-09-17 this keyed on Size; rarity cuts have none, hence the cut name.)
	local routed = Config.CUT_FOR(res.Rarity, res.Size)
	if routed == nil or routed ~= armedCut then
		return false
	end
	if result ~= nil then
		return false -- R1: this arm is already spoken for
	end
	result = res
	return true
end

-- Takeover, polled per frame, generation-checked so a stale run can never read a
-- newer throw's grant.
function Bridge.result(g: number?): Result?
	if type(g) == "number" and g == gen then
		return result
	end
	return nil
end

function Bridge.onDone(cb: (boolean) -> ())
	if type(cb) ~= "function" then
		return
	end
	-- Already over (a cinematic that died between tryAdopt and this call): answer
	-- immediately rather than registering a callback nothing will ever fire.
	if state == "idle" then
		task.spawn(cb, lastOk)
		return
	end
	table.insert(doneCbs, cb)
end

-- Takeover, exactly once per run, with the generation it was handed at play time.
-- ok=false means the cinematic never delivered the reveal (error / death / cancel),
-- which is CatchRevealClient's cue to run the ordinary chain after all.
function Bridge.finish(g: number?, ok: boolean)
	if type(g) ~= "number" or g ~= gen or state == "idle" then
		return
	end
	settle(ok)
end

-- CinematicClient, when ITS OWN play declined or errored before running. Generation-
-- scoped on purpose: a debounced play must never tear down the live arm of the
-- earlier throw whose cinematic is the very thing debouncing it.
function Bridge.markFailedFor(g: number?)
	Bridge.finish(g, false)
end

-- Hard escape hatch (harness teardown, and any future place-level reset). Goes
-- through settle(), so it FAILS a live arm rather than dropping it -- R3 again.
function Bridge.reset()
	if state ~= "idle" then
		settle(false)
	end
	lastOk = false
end

-- Diagnostics only.
function Bridge.debugState(): { [string]: any }
	return {
		gen = gen,
		state = state,
		armedCut = armedCut,
		-- Recomputed WITHOUT armLive(), which settles a stale arm as a side effect --
		-- reading a diagnostic must never change the thing it reports on.
		armLive = state ~= "idle" and os.clock() <= armExpiresAt,
		hasResult = result ~= nil,
		pendingCallbacks = #doneCbs,
		lastOk = lastOk,
	}
end

return Bridge
