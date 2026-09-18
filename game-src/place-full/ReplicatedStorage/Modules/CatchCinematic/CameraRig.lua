--!strict
-- CatchCinematic.CameraRig — hand-lerped camera takeover for the Massive catch cinematic.
-- Single per-frame camera writer: the RenderStepped-bound callback below. No TweenService
-- is used on Camera.CFrame or Camera.FieldOfView anywhere in this module — every motion
-- (flyTo/lookHover/orbit/punchFOV/shake) is sampled and applied by hand each frame.
-- ScreenShake (sibling module) owns NO camera writes; it only returns (offset, rollDeg)
-- via the fn installed through setShakeSource, applied here AFTER the base CFrame.
--
-- Wind-down contract: once returnToPlayer() begins a real blend (self._motion.kind ==
-- "returning"), this rig instance is winding down. From that point on: flyTo/lookHover/
-- orbit/punchFOV are no-ops (the wind-down is not interruptible by more motion calls);
-- a second returnToPlayer() call is itself a no-op — the FIRST call's `done` still
-- fires, exactly once, the second call's `done` is never invoked; and takeover() on
-- this same rig instance returns false for as long as it is already active (winding
-- down or not — this also closes the double-save hazard where a second takeover()
-- would overwrite the saved pre-cinematic state with mid-cinematic Scriptable values).
-- restore() is the one abort path out of a wind-down (or out of any active state): it
-- always fires a still-pending returnToPlayer `done` exactly once before returning.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- A FIXED string, unlike the Sequencer's per-run salted bind name, and deliberately so.
-- A shared BindToRenderStep name is only dangerous when two bindings can be live at
-- once, and two live rigs are impossible here: Sequencer.play refuses to start while a
-- run is active (the `active` debounce), each run builds exactly one CameraRig, and
-- takeover() returns false on an already-active rig instance. One rig, one binding.
local RENDER_BIND_NAME = "CatchCinematicCamera"

export type CameraRigCfg = {
	fovBase: number?,
	fovPunchHi: number?,
	fovPunchSettle: number?,
	fovPunchDur: number?,
	outboundHeight: number?,
	hoverDistMult: number?,
	hoverHeightFrac: number?,
	heroDistMult: number?,
	heroHeightFrac: number?,
	orbitDegrees: number?,
	returnBlendSeconds: number?,
	zoomPunchScale: number?,
}

type SavedCameraState = {
	CameraType: Enum.CameraType,
	CameraSubject: Instance?,
	FieldOfView: number,
	CFrame: CFrame,
}

-- Flat "variant record": one field set covers every motion kind; unused fields stay nil.
-- Each branch in _computeBaseCFrame casts the fields it needs (::) — safe because the
-- fields are always populated together by the constructor for that kind.
type Motion = {
	kind: string, -- "none" | "hold" | "flyTo" | "hover" | "orbit" | "returning"
	cf: CFrame?,
	startCF: CFrame?,
	targetCF: CFrame?,
	duration: number?,
	elapsed: number?,
	easeOutHard: boolean?,
	eye: Vector3?,
	focus: Vector3?,
	startTime: number?,
	seedX: number?,
	seedY: number?,
	seedZ: number?,
	degrees: number?,
	dist: number?,
	height: number?,
	startAngle: number?,
}

type FovPunch = {
	startFOV: number,
	hi: number,
	settle: number,
	duration: number,
	elapsed: number,
}

local CameraRig = {}
CameraRig.__index = CameraRig

export type Rig = typeof(setmetatable(
	{} :: {
		-- Retained only as the documented home of this rig's tunables (Config.CAMERA)
		-- for the Sequencer's own reference — never read internally. Every motion
		-- method below takes explicit per-call numbers instead of silently falling
		-- back to fields in here, so nothing in this module can drift out of sync
		-- with what the Sequencer actually passed for a given beat.
		_cfg: CameraRigCfg,
		_camera: Camera?,
		_active: boolean,
		_bound: boolean,
		_saved: SavedCameraState?,
		_savedOffset: CFrame?,
		_motion: Motion,
		_fovPunch: FovPunch?,
		_shakeSource: (() -> (Vector3, number))?,
		_lastBaseCF: CFrame?,
		_elapsedTime: number,
		_pendingDone: (() -> ())?,
		_pendingFinishSoft: boolean,
	},
	CameraRig
))

local function easeFlyTo(t: number, hard: boolean): number
	t = math.clamp(t, 0, 1)
	if hard then
		-- harder deceleration, no slow start: snap into motion, brake hard at the end.
		return 1 - (1 - t) ^ 7
	end
	-- cubic ease-in first half, quintic ease-out second half.
	if t < 0.5 then
		local u = t * 2
		return 0.5 * (u * u * u)
	else
		local u = (t - 0.5) * 2
		return 0.5 + 0.5 * (1 - (1 - u) ^ 5)
	end
end

local function easeReturnBlend(t: number): number
	t = math.clamp(t, 0, 1)
	return 1 - (1 - t) ^ 5
end

function CameraRig.new(cfg: CameraRigCfg): Rig
	local self = setmetatable({
		_cfg = cfg,
		_camera = nil,
		_active = false,
		_bound = false,
		_saved = nil,
		_savedOffset = nil,
		_motion = { kind = "none" } :: Motion,
		_fovPunch = nil,
		_shakeSource = nil,
		_lastBaseCF = nil,
		_elapsedTime = 0,
		_pendingDone = nil,
		_pendingFinishSoft = false,
	}, CameraRig)
	return self
end

-- True once returnToPlayer() has started a real blend. See the wind-down contract
-- in the module header — this is the single source of truth every guard below reads.
function CameraRig:_isWindingDown(): boolean
	return self._motion.kind == "returning"
end

function CameraRig:_applyRestore(includeCFrame: boolean)
	local cam = self._camera
	local saved = self._saved
	if not cam or not saved then
		return
	end
	cam.CameraType = saved.CameraType
	cam.CameraSubject = saved.CameraSubject
	cam.FieldOfView = saved.FieldOfView
	if includeCFrame then
		-- One-time bookend write (restore/hard-restore only) — not a per-frame writer.
		cam.CFrame = saved.CFrame
	end
end

function CameraRig:takeover(): boolean
	-- Always false while already active — winding down or not. A second takeover()
	-- must never re-save: overwriting self._saved with the current (mid-cinematic,
	-- Scriptable) camera state would permanently lose the real pre-cinematic values
	-- restore() is supposed to hand back.
	if self._active then
		return false
	end

	local cam = workspace.CurrentCamera
	if not cam then
		return false
	end

	self._camera = cam
	-- NEVER save Scriptable as the thing to hand back. Scriptable means some OTHER
	-- script had the camera when we took over (ClientMain's stone-tracking camera is
	-- the one that really does this -- see the CinematicCameraInbound handshake in
	-- CinematicClient, which stops it happening on the real throw path). Whoever it
	-- was, they are not getting it back after a 10.7s cutscene: their render loop is
	-- long gone and their own restore already fired mid-cut. Restoring Scriptable
	-- would leave the player with a frozen camera and no way to recover it short of
	-- rejoining. Custom is the correct terminal state for a cinematic that always
	-- ends by giving the player their camera back, so coerce it here as a last-resort
	-- backstop that no future camera-owning feature can defeat.
	local savedType = cam.CameraType
	local savedSubject: Instance? = cam.CameraSubject
	if savedType == Enum.CameraType.Scriptable then
		warn("[CameraRig] camera was already Scriptable at takeover -- restoring to Custom instead")
		savedType = Enum.CameraType.Custom
		-- A Scriptable owner may also have left CameraSubject nil, and Custom with no
		-- subject is still a dead camera. Only ever done alongside the type coercion --
		-- on the normal path the player's real subject is whatever we found.
		if not savedSubject then
			local plr = Players.LocalPlayer
			local char = plr and plr.Character
			local hum = char and char:FindFirstChildWhichIsA("Humanoid")
			if hum then savedSubject = hum end
		end
	end
	self._saved = {
		CameraType = savedType,
		CameraSubject = savedSubject,
		FieldOfView = cam.FieldOfView,
		CFrame = cam.CFrame,
	}

	local player = Players.LocalPlayer
	local character = player and player.Character
	local hrp = (character and character:FindFirstChild("HumanoidRootPart")) :: BasePart?
	if hrp then
		self._savedOffset = hrp.CFrame:ToObjectSpace(cam.CFrame)
	else
		self._savedOffset = nil
	end

	self._lastBaseCF = cam.CFrame
	self._motion = { kind = "hold", cf = cam.CFrame } :: Motion
	self._fovPunch = nil
	self._shakeSource = nil
	self._elapsedTime = 0
	self._pendingDone = nil
	self._pendingFinishSoft = false

	local typeOk = pcall(function()
		cam.CameraType = Enum.CameraType.Scriptable
	end)
	if not typeOk then
		self._camera = nil
		self._saved = nil
		return false
	end

	local bindOk = pcall(function()
		RunService:BindToRenderStep(RENDER_BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
			local stepOk, stepErr = pcall(function()
				self:_onRenderStep(dt)
			end)
			if not stepOk then
				warn("[CameraRig] render step error: " .. tostring(stepErr))
			end
		end)
	end)
	if not bindOk then
		pcall(function()
			cam.CameraType = (self._saved :: SavedCameraState).CameraType
		end)
		self._camera = nil
		self._saved = nil
		return false
	end

	self._bound = true
	self._active = true
	return true
end

function CameraRig:flyTo(targetCF: CFrame, seconds: number, easeOutHard: boolean)
	if not self._active or not self._camera or self:_isWindingDown() then
		return
	end
	local startCF = self._lastBaseCF or self._camera.CFrame
	self._motion = {
		kind = "flyTo",
		startCF = startCF,
		targetCF = targetCF,
		duration = math.max(seconds, 1e-3),
		elapsed = 0,
		easeOutHard = easeOutHard,
	} :: Motion
end

function CameraRig:lookHover(eye: Vector3, focus: Vector3)
	if not self._active or not self._camera or self:_isWindingDown() then
		return
	end
	self._motion = {
		kind = "hover",
		eye = eye,
		focus = focus,
		startTime = self._elapsedTime,
		seedX = math.random() * 1000,
		seedY = math.random() * 1000,
		seedZ = math.random() * 1000,
	} :: Motion
end

function CameraRig:orbit(focus: Vector3, degrees: number, seconds: number, dist: number, height: number)
	if not self._active or not self._camera or self:_isWindingDown() then
		return
	end
	local currentCF = self._lastBaseCF or self._camera.CFrame
	local rel = currentCF.Position - focus
	local startAngle = 0
	if rel.Magnitude > 1e-3 then
		startAngle = math.atan2(rel.Z, rel.X)
	end
	self._motion = {
		kind = "orbit",
		focus = focus,
		degrees = degrees,
		duration = math.max(seconds, 1e-3),
		dist = dist,
		height = height,
		elapsed = 0,
		startAngle = startAngle,
	} :: Motion
end

function CameraRig:punchFOV(hi: number, settle: number, seconds: number)
	if not self._active or not self._camera or self:_isWindingDown() then
		return
	end
	self._fovPunch = {
		startFOV = self._camera.FieldOfView,
		hi = hi,
		settle = settle,
		duration = math.max(seconds, 1e-3),
		elapsed = 0,
	}
end

function CameraRig:setShakeSource(fn: (() -> (Vector3, number))?)
	self._shakeSource = fn
end

function CameraRig:returnToPlayer(seconds: number, done: (() -> ())?)
	-- Already winding down: a second returnToPlayer() is a pure no-op. The first
	-- call's motion/done own the wind-down; this call's `done` is deliberately never
	-- invoked (there is nothing for it to observe completing) and nothing here is
	-- touched, so the in-flight blend can't be re-targeted or have its done orphaned.
	if self:_isWindingDown() then
		return
	end

	if not self._active or not self._camera then
		if done then
			pcall(done)
		end
		return
	end

	local player = Players.LocalPlayer
	local character = player and player.Character
	local hrp = (character and character:FindFirstChild("HumanoidRootPart")) :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local isDead = humanoid ~= nil and humanoid.Health <= 0

	if not hrp or not self._savedOffset or isDead then
		self._pendingDone = done
		self:_finishReturn(true)
		return
	end

	local targetCF = hrp.CFrame * (self._savedOffset :: CFrame)
	self._motion = {
		kind = "returning",
		startCF = self._lastBaseCF or self._camera.CFrame,
		targetCF = targetCF,
		duration = math.max(seconds, 1e-3),
		elapsed = 0,
	} :: Motion
	self._pendingDone = done
end

-- hard=true: full restore incl. CFrame (kill-path / no valid HRP to blend toward).
-- hard=false: CameraType/Subject/FOV only — CFrame was already landed by the render
-- loop's own write this frame (see _onRenderStep), at the blended HRP-relative pose.
function CameraRig:_finishReturn(hard: boolean)
	local done = self._pendingDone
	self._pendingDone = nil

	if hard then
		self:restore()
	else
		pcall(function()
			if self._bound then
				RunService:UnbindFromRenderStep(RENDER_BIND_NAME)
				self._bound = false
			end
			self:_applyRestore(false)
		end)
		self._active = false
		self._shakeSource = nil
		self._motion = { kind = "none" } :: Motion
		self._fovPunch = nil
	end

	if done then
		pcall(done)
	end
end

function CameraRig:restore()
	-- restore() doubles as the abort path (kill-path, or aborting mid-returnToPlayer):
	-- if a returnToPlayer is still in flight, its done must still fire — exactly once,
	-- never silently dropped. Pop it into a local up front (so nothing can read/fire it
	-- twice — in particular the render loop's own _finishReturn can't double-fire it,
	-- since unbinding below guarantees _onRenderStep never runs again), do the actual
	-- restore work, then invoke it last so callers see a fully-restored camera.
	local done = self._pendingDone
	self._pendingDone = nil
	self._pendingFinishSoft = false

	pcall(function()
		if self._bound then
			RunService:UnbindFromRenderStep(RENDER_BIND_NAME)
			self._bound = false
		end
		if self._active then
			self:_applyRestore(true)
		end
	end)
	self._active = false
	self._shakeSource = nil
	self._motion = { kind = "none" } :: Motion
	self._fovPunch = nil

	if done then
		pcall(done)
	end
end

function CameraRig:_updateFOV(dt: number)
	local punch = self._fovPunch
	if not punch then
		return
	end
	local cam = self._camera
	if not cam then
		return
	end
	punch.elapsed += dt
	local t = math.clamp(punch.elapsed / punch.duration, 0, 1)
	local riseFrac = 0.35
	local fov: number
	if t < riseFrac then
		local u = t / riseFrac
		fov = punch.startFOV + (punch.hi - punch.startFOV) * (1 - (1 - u) ^ 3)
	else
		local u = (t - riseFrac) / (1 - riseFrac)
		fov = punch.hi + (punch.settle - punch.hi) * (u * u * (3 - 2 * u))
	end
	cam.FieldOfView = fov
	if t >= 1 then
		self._fovPunch = nil
	end
end

function CameraRig:_computeBaseCFrame(dt: number): CFrame
	local motion = self._motion
	local baseCF: CFrame

	if motion.kind == "hold" then
		baseCF = motion.cf :: CFrame

	elseif motion.kind == "flyTo" then
		local elapsed = (motion.elapsed :: number) + dt
		motion.elapsed = elapsed
		local duration = motion.duration :: number
		local t = math.clamp(elapsed / duration, 0, 1)
		local startCF = motion.startCF :: CFrame
		local targetCF = motion.targetCF :: CFrame
		local alpha = easeFlyTo(t, motion.easeOutHard :: boolean)
		baseCF = startCF:Lerp(targetCF, alpha)
		if t >= 1 then
			self._motion = { kind = "hold", cf = targetCF } :: Motion
		end

	elseif motion.kind == "hover" then
		local eye = motion.eye :: Vector3
		local focus = motion.focus :: Vector3
		local t = self._elapsedTime - (motion.startTime :: number)
		local amp = 0.15
		local dx = math.noise(t * 0.5, motion.seedX :: number) * amp
		local dy = math.noise(t * 0.5, motion.seedY :: number) * amp
		local dz = math.noise(t * 0.5, motion.seedZ :: number) * amp
		baseCF = CFrame.lookAt(eye + Vector3.new(dx, dy, dz), focus)

	elseif motion.kind == "orbit" then
		local elapsed = (motion.elapsed :: number) + dt
		motion.elapsed = elapsed
		local duration = motion.duration :: number
		local t = math.clamp(elapsed / duration, 0, 1)
		local focus = motion.focus :: Vector3
		local degrees = motion.degrees :: number
		local dist = motion.dist :: number
		local height = motion.height :: number
		local startAngle = motion.startAngle :: number
		local angle = startAngle + math.rad(degrees) * t
		local pos = focus + Vector3.new(math.cos(angle) * dist, height, math.sin(angle) * dist)
		baseCF = CFrame.lookAt(pos, focus)

	elseif motion.kind == "returning" then
		local elapsed = (motion.elapsed :: number) + dt
		motion.elapsed = elapsed
		local duration = motion.duration :: number
		local t = math.clamp(elapsed / duration, 0, 1)
		local startCF = motion.startCF :: CFrame
		local targetCF = motion.targetCF :: CFrame
		if t >= 1 then
			baseCF = targetCF
			self._pendingFinishSoft = true
		else
			local alpha = easeReturnBlend(t)
			baseCF = startCF:Lerp(targetCF, alpha)
		end

	else
		baseCF = self._lastBaseCF or (self._camera :: Camera).CFrame
	end

	self._lastBaseCF = baseCF
	return baseCF
end

function CameraRig:_onRenderStep(dt: number)
	if not self._active or not self._camera then
		return
	end

	self._elapsedTime += dt
	local cam = self._camera :: Camera
	self:_updateFOV(dt)

	-- The one and only per-frame Camera.CFrame writer. baseCF comes from whichever
	-- motion state is active (flyTo/hover/orbit/returning/hold); shakeOffset/rollDeg
	-- come from the fn installed via setShakeSource (ScreenShake:sample), applied
	-- strictly AFTER the base CFrame — ScreenShake itself never touches the camera.
	local baseCF = self:_computeBaseCFrame(dt)

	local shakeOffset = Vector3.new()
	local rollDeg = 0
	local source = self._shakeSource
	if source then
		local ok, o, r = pcall(source)
		if ok and typeof(o) == "Vector3" and typeof(r) == "number" then
			shakeOffset = o
			rollDeg = r
		end
	end

	cam.CFrame = baseCF * CFrame.new(shakeOffset) * CFrame.Angles(0, 0, math.rad(rollDeg))

	if self._pendingFinishSoft then
		self._pendingFinishSoft = false
		self:_finishReturn(false)
	end
end

return CameraRig
