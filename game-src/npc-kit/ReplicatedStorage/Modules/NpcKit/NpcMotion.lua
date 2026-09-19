-- NpcMotion -- pure functions behind the procedural driver. No instances, no
-- services, no state: everything takes numbers and tables and returns numbers
-- and CFrames, which is what lets tools/npc_kit test it under plain Lua.
--
-- Semantic axes -> CFrame (Phase 2.5 doc C1). Character space is the HRP's:
-- front -Z, right +X, up +Y. `CFrame.Angles(rx, ry, rz)` is Roblox's XYZ
-- Euler constructor; for a hanging limb +rx swings it forward, for a head +rx
-- tips the nose up, hence the sign flips below.

local NpcMotion = {}
NpcMotion.Version = 1

local rad = math.rad
local sin, floor, abs = math.sin, math.floor, math.abs
local TAU = math.pi * 2

-- ===== hashing (deterministic across clients; never math.random) ============
function NpcMotion.hash01(n)
	local x = sin(n * 12.9898) * 43758.5453
	return x - floor(x)
end

-- phase in 0..~2pi from the model name salted by its spawn position
-- (BrainrotIdleClient.phaseFor, verbatim in spirit)
function NpcMotion.phaseFor(name, pos)
	local h = 0
	for i = 1, #name do h = (h * 33 + string.byte(name, i)) % 8192 end
	h = h + floor(pos.X + 0.5) * 5 + floor(pos.Z + 0.5) * 13
	return (h % 628) * 0.01
end

function NpcMotion.seedFor(name, pos)
	local h = 7
	for i = 1, #name do h = (h * 31 + string.byte(name, i)) % 100003 end
	return h + floor(abs(pos.X) + 0.5) * 3 + floor(abs(pos.Z) + 0.5) * 7
end

-- draw the k-th deterministic number in [lo, hi] for a seed
function NpcMotion.draw(seed, k, lo, hi)
	local u = NpcMotion.hash01(seed + k * 0.618)
	return lo + (hi - lo) * u
end

-- ===== curves ================================================================
function NpcMotion.smoothstep(a)
	if a <= 0 then return 0 end
	if a >= 1 then return 1 end
	return a * a * (3 - 2 * a)
end

function NpcMotion.clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

-- exponential smoothing toward target with time constant tau (seconds)
function NpcMotion.smooth(current, target, dt, tau)
	if tau <= 0 then return target end
	local a = 1 - math.exp(-dt / tau)
	return current + (target - current) * a
end

-- snap-and-hold: ease quickly to a hashed target in [-amp, amp], then sit on
-- it until the next period (NpcIdle.snapYaw's shape)
function NpcMotion.snapValue(t, period, ease, amp, phase)
	local pos = (t + phase) / period
	local step = floor(pos)
	local frac = pos - step
	local a = (NpcMotion.hash01(step) * 2 - 1) * amp
	local b = (NpcMotion.hash01(step + 1) * 2 - 1) * amp
	local e = NpcMotion.smoothstep(frac / (ease > 0 and ease or 0.001))
	return a + (b - a) * e
end

-- one layer's scalar at time t. `phase` is the body's hashed phase (radians)
function NpcMotion.evalLayer(layer, t, phase)
	local kind = layer.kind
	local period = layer.period or 1
	local amp = layer.amp or 0
	local ph = phase + (layer.phase or 0) * TAU
	if kind == "sine" then
		return amp * sin(TAU * t / period + ph)
	elseif kind == "sineAbs" then
		return amp * abs(sin(TAU * t / period + ph))
	elseif kind == "snap" then
		return NpcMotion.snapValue(t, period, layer.ease or 0.2, amp, phase * period / TAU)
	elseif kind == "const" then
		return amp
	end
	return 0
end

-- ===== gestures ==============================================================
local function buildTracks(gesture)
	local keys = gesture.keys or {}
	local names = {}
	for _, key in ipairs(keys) do
		for joint, axes in pairs(key) do
			if joint ~= "t" and type(axes) == "table" then
				for axis in pairs(axes) do
					local id = joint .. "." .. axis
					if not names[id] then names[id] = { joint = joint, axis = axis } end
				end
			end
		end
	end
	local tracks = {}
	for id, ja in pairs(names) do
		local pts = {}
		local prev = 0
		for i, key in ipairs(keys) do
			local v
			local axes = key[ja.joint]
			if type(axes) == "table" and axes[ja.axis] ~= nil then
				v = axes[ja.axis]
			elseif i == 1 then
				v = 0
			elseif i == #keys and not gesture.hold then
				v = 0
			else
				v = prev
			end
			pts[#pts + 1] = { t = key.t or 0, v = v }
			prev = v
		end
		tracks[id] = { joint = ja.joint, axis = ja.axis, pts = pts }
	end
	gesture.__tracks = tracks
	return tracks
end

-- evalGesture(gesture, elapsed) -> { [joint] = { [axis] = value } }, done(bool)
function NpcMotion.evalGesture(gesture, elapsed)
	local tracks = gesture.__tracks or buildTracks(gesture)
	local out = {}
	local duration = gesture.duration or 0
	local done = elapsed >= duration and not gesture.hold
	for _, tr in pairs(tracks) do
		local pts = tr.pts
		local v = pts[#pts].v
		if elapsed <= pts[1].t then
			v = pts[1].v
		else
			for i = 1, #pts - 1 do
				local a, b = pts[i], pts[i + 1]
				if elapsed >= a.t and elapsed < b.t then
					local span = b.t - a.t
					local f = span > 0 and (elapsed - a.t) / span or 1
					v = a.v + (b.v - a.v) * NpcMotion.smoothstep(f)
					break
				end
			end
		end
		if v ~= 0 then
			out[tr.joint] = out[tr.joint] or {}
			out[tr.joint][tr.axis] = (out[tr.joint][tr.axis] or 0) + v
		end
	end
	return out, done
end

-- ===== accumulation & mapping ===============================================
function NpcMotion.accumulate(acc, joint, axis, value)
	if value == 0 then return end
	local j = acc[joint]
	if not j then j = {}; acc[joint] = j end
	j[axis] = (j[axis] or 0) + value
end

-- semantic degrees/studs -> CFrame offset for a joint of `class` on `side`
function NpcMotion.offsetFor(class, side, ax)
	local rx, ry, rz = 0, 0, 0
	if class == "spine" then
		rx = -(ax.bend or 0)
		ry = -(ax.turn or 0)
		rz = -(ax.tilt or 0)
	elseif class == "face" then
		rz = side * (ax.browOuterUp or 0) + (ax.rotZ or 0)
	else -- limb
		rx = (ax.swing or 0)
		ry = side * (ax.twist or 0)
		rz = side * (ax.spread or 0)
	end
	local x, y, z = ax.x or 0, ax.y or 0, ax.z or 0
	if rx == 0 and ry == 0 and rz == 0 then
		if x == 0 and y == 0 and z == 0 then return nil end
		return CFrame.new(x, y, z)
	end
	return CFrame.new(x, y, z) * CFrame.Angles(rad(rx), rad(ry), rad(rz))
end

-- aim angles (turn right+, bend down+) from a root-space direction to the target
function NpcMotion.aimAngles(rootCFrame, fromPos, targetPos)
	local d = rootCFrame:VectorToObjectSpace(targetPos - fromPos)
	local horiz = math.sqrt(d.X * d.X + d.Z * d.Z)
	local turn = math.deg(math.atan2(d.X, -d.Z))
	local bend = math.deg(math.atan2(-d.Y, horiz))
	return turn, bend
end

return NpcMotion
