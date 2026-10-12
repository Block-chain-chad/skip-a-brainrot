--!strict
-- ThrowCam: the thrower's stone-tracking camera. Moved out of ClientMain (2026-09-21
-- throw-pacing pass) and rebuilt on CatchCinematic.CameraRig so every camera the game
-- takes -- the stone chase and the reward cuts -- shares one takeover/restore path.
--
-- WHAT IT FIXES. The old block held Scriptable for the WHOLE flight plus a hard 1.4s
-- dwell out at the landing point and then snapped CameraType back -- so a long throw
-- was up to ~4.8s of forced spectating, the reward pop started while the camera was
-- still parked over the water, and the return was a cut, not a move.
--
-- THE NEW SHAPE, in wall-clock seconds from StoneThrown receipt:
--   CHASE   0 .. chaseEnd      camera rides behind the stone through the opening skips
--                              (chaseEnd = min(CHASE_MAX, CHASE_FRAC * flight); shorter
--                              on touch -- the exciting part IS the first few skips)
--   GLIDE   chaseEnd .. land   the camera's forward speed dies away and it keeps its eye
--                              on the stone as it accelerates off into the distance:
--                              the player SEES how far it goes without being dragged
--                              900 studs out to watch it
--   DWELL   land .. +DWELL     the landing splash, briefly
--   RETURN  +RETURN            an eased blend back to the player's own camera pose
--                              (CameraRig:returnToPlayer -- HRP-relative, so it lands
--                              on the camera the player actually had)
-- The pop layer waits for the camera to be home (player attribute ThrowCamBusy), so
-- "camera settles -> short anticipation -> Brainrot appears" happens in that order.
--
-- QUICK THROW (player attribute QuickThrow, from Settings > Gameplay): no takeover at
-- all. The player keeps their own camera, watches the stone leave from the dock, and
-- the reward arrives the moment the server confirms it. Built for grinding; also the
-- right default for anyone who finds the chase tiring.
--
-- CUT HANDOFF. A Mythic+ throw's cut takes the camera AT the final contact. The old
-- code restored Custom a beat early (the CinematicCameraInbound handshake), which
-- snapped the player home for a frame before the cut flew back out. Now the rig is
-- OFFERED to the next CameraRig takeover (CameraRig.offerHandoff): the cut adopts our
-- saved home pose as its restore target, starts its own motion from the camera's
-- current pose, and we stand down without writing anything. If no cut claims the
-- offer within HANDOFF_GRACE (declined, no model, errored), we withdraw it and go home
-- ourselves -- the camera is never left in nobody's hands.
--
-- FAILURE SAFETY. Every exit path goes through release(): kill switches on
-- CharacterAdded and Humanoid.Died, a wall-clock backstop past the longest possible
-- flight, pcall'd per-frame work inside CameraRig, and CameraWatchdog behind all of
-- it. ThrowCamBusy is cleared on every path.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local SkipArc = require(Modules:WaitForChild("SkipArc"))
local Platform = require(Modules:WaitForChild("Platform"))
local CameraRig = require(Modules:WaitForChild("CatchCinematic"):WaitForChild("CameraRig"))

local player = Players.LocalPlayer

local ThrowCam = {}

-- ===== TUNABLES =====
ThrowCam.CFG = {
	minDistance = 60,         -- throws shorter than this never leave the player's camera
	chaseMax = 1.6,           -- seconds of chase, desktop
	chaseMaxTouch = 1.15,     -- seconds of chase, touch (phones especially)
	chaseFrac = 0.62,         -- ...or this fraction of the flight, whichever is shorter
	glideDecay = 0.55,        -- seconds for the forward speed to die after the chase
	glideRise = 5,            -- studs the camera lifts during the glide (a better vantage)
	dwell = 0.30,             -- seconds on the landing splash
	returnSeconds = 0.55,     -- blend back to the player (the base; see returnFor)
	returnMax = 0.80,         -- ...stretched by how far out the camera parked, up to this
	cinematicLead = 0.10,     -- seconds before the final contact the handoff is offered
	handoffGrace = 0.45,      -- seconds a cut has to claim the offer before we go home
	backstopPad = 3.0,        -- wall-clock seconds past the flight before a forced release
	-- chase framing, relative to the lane: behind, above, a little to the side
	back = 24, up = 14, side = 6,
	lookAhead = 6, lookUp = 1,
}

local BUSY_ATTR = "ThrowCamBusy"
local QUICK_ATTR = "QuickThrow"
local INBOUND_ATTR = "CinematicCameraInbound"

export type Spec = {
	origin: Vector3,
	landing: Vector3,
	totalTime: number,
	distance: number,
	nContacts: number,
	cinematic: boolean?,
	startFlat: Vector3?,   -- the server's lane start (StoneThrown arg 8); derived when absent
	onHome: (() -> ())?,   -- fired exactly once when the camera is the player's again
}

export type Handle = {
	release: (force: boolean?) -> (),
	active: () -> boolean,
}

local current: { [string]: any }? = nil

function ThrowCam.isQuick(): boolean
	return player ~= nil and player:GetAttribute(QUICK_ATTR) == true
end

function ThrowCam.isActive(): boolean
	return current ~= nil
end

local function setBusy(on: boolean)
	if not player then
		return
	end
	if on then
		player:SetAttribute(BUSY_ATTR, true)
	else
		player:SetAttribute(BUSY_ATTR, nil)
	end
end

-- Returns nil when the throw does not take the camera (short throw, quick throw, or a
-- takeover already in flight). The caller treats nil as "the camera is already home".
function ThrowCam.start(spec: Spec): Handle?
	if typeof(spec.origin) ~= "Vector3" or typeof(spec.landing) ~= "Vector3" then
		return nil
	end
	if type(spec.totalTime) ~= "number" or spec.totalTime ~= spec.totalTime or spec.totalTime <= 0 then
		return nil
	end
	if (spec.distance or 0) < ThrowCam.CFG.minDistance then
		return nil
	end
	if ThrowCam.isQuick() then
		return nil
	end
	if current then
		return nil
	end
	local cfg = ThrowCam.CFG
	local rig = CameraRig.new({ returnBlendSeconds = cfg.returnSeconds })
	if not rig:takeover() then
		return nil
	end

	local state: { [string]: any } = { rig = rig, released = false, homed = false, offered = false }
	current = state
	setBusy(true)

	local T = spec.totalTime
	local n = math.max(math.floor(spec.nContacts or SkipArc.Contacts(spec.distance)), 1)
	local starts = SkipArc.HopStarts(n, T, spec.distance)
	-- the same lane geometry the ghost/server use: origin, then one point per contact.
	-- Both docks run +Z today (ThrowHandler.skipDirOf), and for a +Z lane the flat run
	-- starts directly under the hand, so origin->landing IS the lane direction; a future
	-- directional zone gets the same treatment to within the hand offset.
	local lane: Vector3
	local startFlat: Vector3
	if typeof(spec.startFlat) == "Vector3" then
		startFlat = spec.startFlat :: Vector3
		local flat = Vector3.new(spec.landing.X - startFlat.X, 0, spec.landing.Z - startFlat.Z)
		lane = flat.Magnitude > 1e-3 and flat.Unit or Vector3.new(0, 0, 1)
	else
		local dirFlat = Vector3.new(spec.landing.X - spec.origin.X, 0, spec.landing.Z - spec.origin.Z)
		lane = dirFlat.Magnitude > 1e-3 and dirFlat.Unit or Vector3.new(0, 0, 1)
		startFlat = spec.landing - lane * spec.distance
	end
	local points = { spec.origin }
	for i = 1, n do
		points[i + 1] = startFlat + lane * (spec.distance * (i / n))
	end
	local hopLen = spec.distance / n
	local side = Vector3.new(0, 1, 0):Cross(lane)
	local offset = side * cfg.side + Vector3.new(0, cfg.up, 0) - lane * cfg.back
	local lookOff = Vector3.new(0, cfg.lookUp, 0) + lane * cfg.lookAhead

	local chaseEnd = math.min(Platform.IsTouch and cfg.chaseMaxTouch or cfg.chaseMax, T * cfg.chaseFrac)
	chaseEnd = math.max(chaseEnd, 0.35)

	local t0 = os.clock()
	local camPos: Vector3? = nil
	local camVel = Vector3.zero
	local glideT0: number? = nil
	local glideStart: Vector3? = nil

	local function finishHome()
		if state.homed then
			return
		end
		state.homed = true
		if current == state then
			current = nil
		end
		setBusy(false)
		if spec.onHome then
			task.spawn(spec.onHome)
		end
	end

	-- A blend home that scales with the distance it has to cover: a 70-stud throw's
	-- camera is back in the base time, a 900-stud throw's parked ~550 studs out and
	-- takes up to returnMax -- still quick, but a move rather than a cut.
	local function returnFor(): number
		local here = rig:currentCFrame()
		local char2 = player.Character
		local hrp2 = char2 and char2:FindFirstChild("HumanoidRootPart")
		if not here or not hrp2 then
			return cfg.returnSeconds
		end
		local d = (here.Position - (hrp2 :: BasePart).Position).Magnitude
		return math.clamp(cfg.returnSeconds + (d - 60) / 2000, cfg.returnSeconds, cfg.returnMax)
	end

	local function release(force: boolean?)
		if state.released then
			return
		end
		state.released = true
		if state.charConn then
			state.charConn:Disconnect()
			state.charConn = nil
		end
		if state.diedConn then
			state.diedConn:Disconnect()
			state.diedConn = nil
		end
		CameraRig.withdrawHandoff(rig)
		if force then
			-- kill path: hard restore, no blend (a dead/new character has nothing to
			-- blend toward), and never yield inside a signal handler
			pcall(function()
				rig:restore()
			end)
			finishHome()
			return
		end
		rig:returnToPlayer(returnFor(), finishHome)
		-- returnToPlayer resolves synchronously when there is nothing to blend toward
		-- (no HRP / dead / abandoned); otherwise `done` lands from the render step.
	end

	-- kill switches
	state.charConn = player.CharacterAdded:Connect(function()
		release(true)
	end)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		state.diedConn = hum.Died:Connect(function()
			release(true)
		end)
	end

	local function offerToCut()
		if state.offered or state.released then
			return
		end
		state.offered = true
		CameraRig.offerHandoff(rig)
		-- hold still: the cut's rig starts from this exact pose
		local hold = rig:currentCFrame()
		if hold then
			rig:follow(function()
				return hold
			end)
		end
		task.delay(cfg.handoffGrace, function()
			if state.released then
				return
			end
			if rig:isActive() then
				-- nobody claimed it (cut declined / no model / errored): go home ourselves
				CameraRig.withdrawHandoff(rig)
				release(false)
			else
				-- claimed: the cut owns the camera and its restore now
				state.released = true
				if state.charConn then state.charConn:Disconnect() state.charConn = nil end
				if state.diedConn then state.diedConn:Disconnect() state.diedConn = nil end
				finishHome()
			end
		end)
	end

	rig:follow(function(dt: number, _elapsed: number): CFrame
		local t = os.clock() - t0
		-- a cut is inbound: offer the camera a beat before the final contact
		if spec.cinematic and not state.offered and t >= T - cfg.cinematicLead
			and player:GetAttribute(INBOUND_ATTR) then
			offerToCut()
			return rig:currentCFrame() or Workspace.CurrentCamera.CFrame
		end
		local rockPos = SkipArc.Sample(points, starts, hopLen, math.min(t, T))
		local rockFlat = Vector3.new(rockPos.X, spec.landing.Y, rockPos.Z)
		local pos: Vector3
		if t < chaseEnd then
			pos = rockFlat + offset
			camPos = pos
			-- remember the chase velocity for the glide (finite difference on the lane)
			local ahead = SkipArc.Sample(points, starts, hopLen, math.min(t + 0.05, T))
			camVel = Vector3.new(ahead.X - rockPos.X, 0, ahead.Z - rockPos.Z) / 0.05
		else
			if not glideT0 then
				glideT0 = t
				glideStart = camPos or (rockFlat + offset)
			end
			local g = t - (glideT0 :: number)
			-- exponential decay of the forward speed, plus a gentle rise
			local k = math.max(cfg.glideDecay, 0.05)
			local travelled = camVel * k * (1 - math.exp(-g / k))
			local rise = Vector3.new(0, cfg.glideRise * (1 - math.exp(-g / 0.6)), 0)
			pos = (glideStart :: Vector3) + travelled + rise
			camPos = pos
		end
		local focus = (t >= T) and (spec.landing + Vector3.new(0, cfg.lookUp, 0)) or (rockFlat + lookOff)
		-- keep the eye from ever looking straight down at a stone passing underneath
		local flatDist = Vector3.new(focus.X - pos.X, 0, focus.Z - pos.Z).Magnitude
		if flatDist < 4 then
			focus = pos + lane * 8 - Vector3.new(0, cfg.up * 0.6, 0)
		end
		return CFrame.lookAt(pos, focus)
	end)

	-- landing + dwell -> home (non-cinematic throws)
	task.delay(T + cfg.dwell, function()
		if state.released or state.offered then
			return
		end
		release(false)
	end)
	-- backstop: whatever happens, the camera is handed back
	task.delay(T + cfg.dwell + cfg.returnMax + cfg.backstopPad, function()
		if not state.homed then
			warn("[ThrowCam] backstop fired -- forcing the camera home")
			release(true)
			finishHome()
		end
	end)

	return {
		release = function(force: boolean?)
			release(force)
		end,
		active = function()
			return current == state and not state.homed
		end,
	}
end

return ThrowCam
