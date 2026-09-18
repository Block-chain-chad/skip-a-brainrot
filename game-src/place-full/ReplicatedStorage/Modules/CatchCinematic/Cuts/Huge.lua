--!strict
-- CatchCinematic.Cuts.Huge -- SCALE. The shortened giant water emergence (spec S6.4):
-- Massive's handlers on Huge's own bounds, plus the splash beat and the HUGE banner.
local folder = script.Parent.Parent
local CutKit = require(folder:WaitForChild("CutKit"))
local Types = require(folder:WaitForChild("Types"))
local Massive = require(script.Parent:WaitForChild("Massive"))
type Run = Types.Run

local Huge = {}

-- ===== TUNABLES (spec S6.4) =====
Huge.BEATS = {
	{ name = "bonk",       t0 = 0.00, t1 = 0.30 },
	{ name = "ripple",     t0 = 0.30, t1 = 0.80 },  -- water moves strangely (0.30), large ripple (0.70)
	{ name = "splash",     t0 = 0.80, t1 = 1.20 },  -- water starts splashing
	{ name = "silhouette", t0 = 1.20, t1 = 1.50 },
	{ name = "emergence",  t0 = 1.50, t1 = 2.00 },
	{ name = "scale",      t0 = 2.00, t1 = 3.40 },
	{ name = "banner",     t0 = 3.40, t1 = 4.00 },  -- HUGE; remains in the water; settles
	{ name = "handoff",    t0 = 4.00, t1 = 4.80 },
}

local function updateSplash(run: Run, p: number)
	if run.water then
		run.water:rippleTrain(0.35 + p * 0.65)
		run.water:suctionAndShadow(p * 0.5)
	end
	if run.shake then
		run.shake:setSustain(0.25 * p)
	end
end

Huge.handlers = CutKit.mergeHandlers(Massive.handlers, {
	splash = { update = updateSplash },
})
Huge.everyFrame = Massive.everyFrame
Huge.onSkip = Massive.onSkip
Huge.build = function(run: Run): boolean
	run.size = run.size or "Huge"
	return Massive.build(run)
end
Huge.name = "Huge"
Huge.beats = Huge.BEATS
Huge.revealBeat = "emergence"
Huge.skippable = true
Huge.skipTo = "banner"
Huge.bannerText = "HUGE"

return Huge
