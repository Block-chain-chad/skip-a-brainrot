--!strict
-- CatchCinematic.ScreenShake — trauma-based shake sampler. Owns NO camera writes;
-- CameraRig calls Shake:sample(dt) each frame (via the fn installed through
-- Rig:setShakeSource) and applies the returned (offset, rollDeg) itself, AFTER the
-- base CFrame, inside its single RenderStepped-bound writer.
--
-- cfg is Config.SHAKE, optionally with one extra field merged in by the caller:
--   shakeMult — reduced-motion multiplier (Config.REDUCED_MOTION.shakeMult when the
--   player has reduced motion on, else 1/omitted). Applied to trauma inside sample().

export type ScreenShakeCfg = {
	dreadRampTo: number?,
	eruption: number?,
	riseSustain: number?,
	traumaDecayPerSec: number?,
	maxOffset: number?,
	maxRollDeg: number?,
	shakeMult: number?,
}

local ScreenShake = {}
ScreenShake.__index = ScreenShake

export type Shake = typeof(setmetatable(
	{} :: {
		_cfg: ScreenShakeCfg,
		_trauma: number,
		_sustain: number,
		_t: number,
		_seedX: number,
		_seedY: number,
		_seedZ: number,
		_seedRoll: number,
	},
	ScreenShake
))

function ScreenShake.new(cfg: ScreenShakeCfg): Shake
	local self = setmetatable({
		_cfg = cfg,
		_trauma = 0,
		_sustain = 0,
		_t = 0,
		_seedX = math.random() * 1000,
		_seedY = math.random() * 1000,
		_seedZ = math.random() * 1000,
		_seedRoll = math.random() * 1000,
	}, ScreenShake)
	return self
end

function ScreenShake:add(trauma: number)
	local n = tonumber(trauma) or 0
	self._trauma = math.clamp(self._trauma + n, 0, 1)
end

-- Floor beneath which trauma will not decay — the "rise" beat's ambient sustain.
function ScreenShake:setSustain(level: number)
	self._sustain = math.clamp(tonumber(level) or 0, 0, 1)
end

function ScreenShake:sample(dt: number): (Vector3, number)
	local d = tonumber(dt) or 0
	local cfg = self._cfg
	local decayPerSec = cfg.traumaDecayPerSec or 1.4

	self._trauma = math.clamp(math.max(self._sustain, self._trauma - decayPerSec * d), 0, 1)
	self._t += d

	local mult = cfg.shakeMult or 1
	local effectiveTrauma = math.clamp(self._trauma * mult, 0, 1)
	local mag = effectiveTrauma * effectiveTrauma -- applied magnitude = trauma^2

	local maxOffset = cfg.maxOffset or 0.9
	local maxRollDeg = cfg.maxRollDeg or 1.2

	-- Smooth per-axis noise, distinct seeds so axes don't move in lockstep.
	local nx = math.noise(self._t * 13, self._seedX)
	local ny = math.noise(self._t * 13, self._seedY)
	local nz = math.noise(self._t * 13, self._seedZ)
	local nr = math.noise(self._t * 13, self._seedRoll)

	local offset = Vector3.new(nx, ny, nz) * (mag * maxOffset)
	local rollDeg = nr * mag * maxRollDeg

	return offset, rollDeg
end

return ScreenShake
