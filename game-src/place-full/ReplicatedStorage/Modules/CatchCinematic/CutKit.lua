--!strict
-- CatchCinematic.CutKit -- helpers shared by Takeover (the framework) and every
-- Cuts/<Name> module. Pure functions over the run bag; no instances of its own.
local Players = game:GetService("Players")

local folder = script.Parent
local Config = require(folder:WaitForChild("Config"))
local Types = require(folder:WaitForChild("Types"))
type Run = Types.Run

local CutKit = {}

CutKit.VIEW_DIST_PAD = 10        -- MassiveEmergence's viewDist pad: max(X,Z)*mult + 10
CutKit.TRAVEL_BACK_STUDS = 24    -- how far short of the splash the low fly-out parks

-- ============================== trove ==============================
function CutKit.track(run: Run, fn: () -> ())
	table.insert(run.trove, fn)
end

-- LIFO drain. Construction order is stage -> cut rigs -> audio -> camera -> post ->
-- ui -> skip conns -> kill-switch conns -> render bind -> [overlay], so draining
-- backwards restores the camera before the world is torn out from under it and
-- destroys the stage folder last, as the catch-all for anything a rig leaked.
function CutKit.drain(run: Run, tag: string)
	if run.cleaned then
		return
	end
	run.cleaned = true
	for i = #run.trove, 1, -1 do
		local ok, err = pcall(run.trove[i])
		if not ok then
			warn("[" .. tag .. "] cleanup step failed: " .. tostring(err))
		end
	end
	run.trove = {}
end

-- ============================== beats ==============================
function CutKit.beatIndexOf(run: Run, name: string): number?
	for i, b in ipairs(run.beats) do
		if b.name == name then
			return i
		end
	end
	return nil
end

function CutKit.beatT0(run: Run, name: string, fallback: number): number
	local i = CutKit.beatIndexOf(run, name)
	if i then
		return run.beats[i].t0
	end
	return fallback
end

-- Wall-clock seconds the CURRENT beat lasts (cinematic length x stretch).
function CutKit.beatSeconds(run: Run): number
	local beat = run.beats[run.beatIdx]
	if not beat then
		return 0
	end
	return (beat.t1 - beat.t0) * run.stretch
end

function CutKit.mergeHandlers(base: { [string]: any }, extra: { [string]: any }): { [string]: any }
	local out: { [string]: any } = {}
	for k, v in pairs(base) do
		out[k] = v
	end
	for k, v in pairs(extra) do
		out[k] = v
	end
	return out
end

-- ============================== tables ==============================
function CutKit.shallowMerge(base: { [string]: any }, extra: { [string]: any }): { [string]: any }
	return CutKit.mergeHandlers(base, extra)
end

-- Shallow copy with ONLY the named duration fields multiplied by `stretch` -- how the
-- debug timescale reaches durations that live inside a module's cfg.
function CutKit.scaleDurations(base: { [string]: any }, fields: { string }, stretch: number): { [string]: any }
	local out: { [string]: any } = {}
	for k, v in pairs(base) do
		out[k] = v
	end
	if stretch == 1 then
		return out
	end
	for _, k in ipairs(fields) do
		local v = out[k]
		if type(v) == "number" then
			out[k] = v * stretch
		end
	end
	return out
end

-- ============================== geometry ==============================
function CutKit.localHRP(): BasePart?
	local player = Players.LocalPlayer
	local char = player and player.Character
	return (char and char:FindFirstChild("HumanoidRootPart")) :: BasePart?
end

-- Unit horizontal direction from the player toward the surface point; +Z fallback.
function CutKit.horizToward(surface: Vector3): Vector3
	local hrp = CutKit.localHRP()
	if hrp then
		local flat = Vector3.new(surface.X - hrp.Position.X, 0, surface.Z - hrp.Position.Z)
		if flat.Magnitude > 1e-3 then
			return flat.Unit
		end
	end
	return Vector3.new(0, 0, 1)
end

-- Refreshed after a swapModel, which replaces both.
function CutKit.refreshGeometry(run: Run)
	local brain = run.brain
	if not brain then
		return
	end
	run.model = brain:model()
	run.extents = brain:extents() or Vector3.new(4, 6, 4)
end

-- Eye/focus for the close "hero" framing at the surface, from Config.CAMERA.
function CutKit.heroFraming(run: Run): (Vector3, Vector3)
	local cam = Config.CAMERA
	local ext = run.extents :: Vector3
	local width = math.max(ext.X, ext.Z)
	local dist = width * (cam.hoverDistMult or 1.15) + CutKit.VIEW_DIST_PAD
	local focus = run.surface + Vector3.new(0, ext.Y * (cam.hoverHeightFrac or 0.42), 0)
	local eye = focus - run.horiz * dist + Vector3.new(0, ext.Y * (cam.heroHeightFrac or 0.18), 0)
	return eye, focus
end

-- Eye/focus for the pulled-back framing that sells SCALE: far enough that the whole
-- creature fits (distance from its height x farHeightMult, floored by its width x
-- farDistMult), with the eye LOW -- farHeightFrac of its height above the water --
-- so the body towers over the camera. A 36-stud Kraken fills ~40% of the frame
-- height from ~75 studs; the low angle does the rest. (First pass used 2.4x the
-- largest extent from a high eye: the creature read as distant, not enormous.)
function CutKit.farFraming(run: Run): (Vector3, Vector3)
	local cam = Config.CAMERA
	local ext = run.extents :: Vector3
	local width = math.max(ext.X, ext.Z)
	local dist = math.max(ext.Y * (cam.farHeightMult or 1.8), width * (cam.farDistMult or 1.3)) + CutKit.VIEW_DIST_PAD
	local focus = run.surface + Vector3.new(0, ext.Y * 0.5, 0)
	local eye = run.surface - run.horiz * dist + Vector3.new(0, math.max(ext.Y * (cam.farHeightFrac or 0.12), 3), 0)
	return eye, focus
end

return CutKit
