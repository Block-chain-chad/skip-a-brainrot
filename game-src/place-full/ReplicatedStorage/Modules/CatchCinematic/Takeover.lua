--!strict
-- CatchCinematic.Takeover -- THE FRAMEWORK. Everything a camera-takeover cut needs
-- that is not the cut itself: one run per client, the master clock and timescale,
-- the result hold before the cut's reveal beat, the cancel path, hold-to-skip,
-- watchdogs, kill switches, camera + HUD takeover AND restore, the stage folder,
-- audio/post/shake/ui construction, Bridge plumbing and beat dispatch.
--
-- The CUT (Cuts/<Name>) supplies: beats, handlers keyed by beat name, revealBeat,
-- skippable/skipTo/onSkip, onCancel, everyFrame, build(run), bannerText.
-- A cut NEVER writes Camera.CameraType, ScreenGui.Enabled or Lighting: this module
-- (via CameraRig / PostFX) is the only takeover path and the only restore path.
--
-- ================================ RUN FIELDS ================================
-- Set by play() before build:  payload, cut, trove, stage(after build), spectator,
--   beats, beatIdx, t, realElapsed, speed, stretch, budget, surface, horiz, name,
--   size, mutation, rarity, rarityColor, rng, quality, reducedMotion, waterCfg,
--   postCfg, bridgeGen, usesBridge, resultSeen, result, breached, displayName,
--   revealT0, skipping, cancelling, finished.
-- Set by buildRun:  audio, cam?, shake?, post?, hype?  (thrower only for the last 4)
-- Set by the cut's build:  brain, water, rock?, and anything cut-specific.
--
-- ================================ TIMESCALE ================================
-- run.speed = Config.timescale() (cinematic seconds per real second); run.stretch =
-- 1/speed. The conductor advances run.t by dt*speed. Every wall-clock duration a
-- handler passes to a module is cinematicSeconds * run.stretch. Durations inside a
-- module's cfg (Config.WATER / Config.POSTFX) reach the constructors as scaled
-- shallow copies (run.waterCfg / run.postCfg). Skip hold, the luminance dips and
-- ScreenShake decay are deliberately NOT scaled (input/UX, not choreography).
--
-- ================================ LIFECYCLE ================================
-- ONE run table per play, ONE trove drained LIFO by finish(), ONE render binding.
-- finish() is wired to every exit: normal end, skip-into-skipTo (still ends normally),
-- cancel timeout, Humanoid.Died, CharacterAdded, the conductor's pcall handler, and
-- two watchdogs. play() BLOCKS; false means DECLINED (nothing parented) and the
-- caller stages its stock landing; opts.onCommit fires synchronously on commit.
--
-- SKIP SAFETY: a skip jumps to cut.skipTo, which (for every shipped cut) reveals and
-- awards the creature -- so it is gated on the grant having landed. Held early, the
-- dip goes full dark and WAITS; if the grant never comes, cancel takes over from
-- that same dark frame. A skip can never show a catch the cancel path exists to hide.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local folder = script.Parent
local Config = require(folder:WaitForChild("Config"))
local CutKit = require(folder:WaitForChild("CutKit"))
local Types = require(folder:WaitForChild("Types"))
local CameraRig = require(folder:WaitForChild("CameraRig"))
local ScreenShake = require(folder:WaitForChild("ScreenShake"))
local PostFX = require(folder:WaitForChild("PostFX"))
local AudioBus = require(folder:WaitForChild("AudioBus"))
local HypeUI = require(folder:WaitForChild("HypeUI"))
local Bridge = require(folder:WaitForChild("Bridge"))
local Sizes = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SizeConfig"))

type Run = Types.Run
type Cut = Types.Cut

local TAG = "Takeover"
local STAGE_NAME = "CatchCinematicStage"
local FADE_GUI_NAME = "CatchCinematicFade"
local REVEAL_ATTR = "RevealActive"
local BIND_NAME = "CatchCinematicTakeover"
local BIND_PRIORITY = Enum.RenderPriority.Camera.Value - 1
local runCounter = 0
local VM_SALT: string
do
	local ok, guid = pcall(function()
		return game:GetService("HttpService"):GenerateGUID(false)
	end)
	if ok and type(guid) == "string" then
		VM_SALT = string.sub((string.gsub(guid, "%-", "")), 1, 8)
	else
		VM_SALT = string.format("%08x", math.floor(os.clock() * 1e6) % 0xFFFFFFFF)
	end
end

local DIP_MAX = 0.82
local WATCHDOG_PAD = 8
local CANCEL_DIP_IN, CANCEL_DIP_OUT = 0.15, 0.6
local WATER_DURATION_FIELDS = { "domeRiseSeconds", "columnSeconds", "cascadeSeconds" }
local POSTFX_DURATION_FIELDS = { "flashSeconds", "easeBackSeconds" }

local SPECTATOR_SKIP_IGNORED: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.W] = true, [Enum.KeyCode.A] = true, [Enum.KeyCode.S] = true,
	[Enum.KeyCode.D] = true, [Enum.KeyCode.Space] = true,
	[Enum.KeyCode.LeftShift] = true, [Enum.KeyCode.RightShift] = true,
}

export type PlayOpts = {
	spectator: boolean?,
	bridgeGen: number?,
	onCommit: (() -> ())?,
}

local Takeover = {}
local active: Run? = nil

local track = CutKit.track
local function drain(run: Run)
	CutKit.drain(run, TAG)
end

-- ============================== overlay ==============================
local function ensureOverlay(run: Run): Frame?
	if run.overlay then
		return run.overlay
	end
	local player = Players.LocalPlayer
	local pg = player and player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = FADE_GUI_NAME
	gui.DisplayOrder = 60
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Parent = pg
	local dip = Instance.new("Frame")
	dip.Name = "Dip"
	dip.Size = UDim2.fromScale(1, 1)
	dip.BackgroundColor3 = Color3.new(0, 0, 0)
	dip.BackgroundTransparency = 1
	dip.BorderSizePixel = 0
	dip.Parent = gui
	run.overlay = dip
	track(run, function()
		gui:Destroy()
	end)
	return dip
end

-- ============================== finish ==============================
local function finish(run: Run, ok: boolean)
	if run.finished then
		return
	end
	run.finished = true
	run.ok = ok
	drain(run)
	if active == run then
		active = nil
	end
	if run.usesBridge then
		pcall(Bridge.finish, run.bridgeGen, ok)
	end
end

-- ============================== skip ==============================
local function runExit(run: Run)
	local current = run.beats[run.beatIdx]
	if current then
		local h = run.cut.handlers[current.name]
		if h and h.exit then
			h.exit(run)
		end
	end
end

local function jumpTo(run: Run, beatName: string)
	if run.usesBridge and not run.resultSeen then
		warn("[" .. TAG .. "] jump refused: no result yet")
		return
	end
	local idx = CutKit.beatIndexOf(run, beatName)
	if not idx then
		finish(run, true)
		return
	end
	runExit(run)
	if run.cut.onSkip then
		local okS, err = pcall(run.cut.onSkip, run)
		if not okS then
			warn("[" .. TAG .. "] onSkip errored: " .. tostring(err))
		end
	end
	run.beatIdx = idx - 1
	run.t = run.beats[idx].t0
end

local function beginSkip(run: Run)
	if run.skipping or run.cancelling or run.finished then
		return
	end
	if run.spectator then
		run.skipping = true
		finish(run, true)
		return
	end
	run.skipping = true
	run.skipPhase = "out"
	run.skipClock = 0
	if run.hype then
		run.hype:interrupt()
		run.hype:hideSkipPrompt()
	end
	ensureOverlay(run)
end

local function inputQualifies(input: InputObject, spectator: boolean): boolean
	local t = input.UserInputType
	if t == Enum.UserInputType.Keyboard then
		if spectator and SPECTATOR_SKIP_IGNORED[input.KeyCode] then
			return false
		end
		return true
	end
	if t == Enum.UserInputType.Touch then
		return not spectator
	end
	if t == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.ButtonB then
		return true
	end
	return false
end

local function wireSkipInput(run: Run)
	local holds: { [InputObject]: boolean } = {}
	local function recompute()
		run.holdDown = next(holds) ~= nil
	end
	local c1 = UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe or not inputQualifies(input, run.spectator) then
			return
		end
		holds[input] = true
		recompute()
	end)
	local c2 = UserInputService.InputEnded:Connect(function(input)
		if holds[input] then
			holds[input] = nil
			recompute()
		end
	end)
	local c3 = UserInputService.WindowFocusReleased:Connect(function()
		table.clear(holds)
		run.holdDown = false
		run.holdTime = 0
	end)
	track(run, function()
		c1:Disconnect()
		c2:Disconnect()
		c3:Disconnect()
	end)
end

-- ============================== cancel ==============================
local function defaultCancelTeardown(run: Run)
	if run.water then
		run.water:cleanup()
	end
	if run.brain then
		run.brain:cleanup()
		run.brain = nil
	end
	if run.rock then
		run.rock:cleanup()
		run.rock = nil
	end
end

local function beginCancel(run: Run)
	if run.cancelling or run.finished then
		return
	end
	run.cancelling = true
	run.skipping = false
	warn("[" .. TAG .. "] no result within " .. tostring(Config.CANCEL_TIMEOUT) .. "s -- cancelling " .. run.cut.name)
	if run.hype then
		run.hype:interrupt()
		run.hype:hideSkipPrompt()
	end
	if run.cut.onCancel then
		local okC, err = pcall(run.cut.onCancel, run)
		if not okC then
			warn("[" .. TAG .. "] onCancel errored: " .. tostring(err))
		end
	end
	defaultCancelTeardown(run)
	if run.shake then
		run.shake:setSustain(0)
	end
	if run.post then
		run.post:easeBack(0.25)
	end
	if run.audio then
		run.audio:unsilence()
		run.audio:play("waterExplosion", { where = run.surface })
		run.audio:restoreAmbient(0.35)
	end
	local dip0 = ensureOverlay(run)
	local alpha0 = dip0 and math.clamp((1 - dip0.BackgroundTransparency) / DIP_MAX, 0, 1) or 0
	run.cancelClock = alpha0 * CANCEL_DIP_IN
	run.cancelDeadline = CANCEL_DIP_IN + CANCEL_DIP_OUT + 0.5
	if run.cam then
		run.cam:returnToPlayer((Config.CAMERA.returnBlendSeconds or 0.8) * 0.7, function()
			finish(run, false)
		end)
	end
end

-- ============================== conductor ==============================
local function stepInner(run: Run, dt: number)
	run.realElapsed += dt
	if run.realElapsed > run.budget then
		warn("[" .. TAG .. "] watchdog fired at " .. string.format("%.2f", run.realElapsed) .. "s")
		finish(run, false)
		return
	end

	-- (1) master clock, with the pre-reveal result hold
	local newT = run.t + dt * run.speed
	if not run.spectator and not run.resultSeen and not run.cancelling then
		if newT >= run.revealT0 and run.realElapsed < run.cancelTimeout then
			newT = math.min(newT, run.revealT0 - 1e-3)
		end
	end
	run.t = newT

	-- (2) cancel deadline
	if not run.spectator and not run.resultSeen and not run.cancelling then
		if run.realElapsed >= run.cancelTimeout then
			beginCancel(run)
		end
	end
	if run.cancelling then
		run.cancelClock += dt
		local dip = run.overlay
		if dip then
			local a: number
			if run.cancelClock <= CANCEL_DIP_IN then
				a = run.cancelClock / CANCEL_DIP_IN
			else
				a = math.clamp(1 - (run.cancelClock - CANCEL_DIP_IN) / CANCEL_DIP_OUT, 0, 1)
			end
			dip.BackgroundTransparency = 1 - a * DIP_MAX
		end
		if run.cancelClock >= run.cancelDeadline then
			finish(run, false)
		end
		return
	end

	-- (3) result reconciliation: the server's roll can be superseded at reveal time
	if run.usesBridge and not run.resultSeen then
		local res = Bridge.result(run.bridgeGen)
		if res ~= nil then
			run.resultSeen = true
			run.result = res
			local name = res.BrainrotName
			if type(name) == "string" and name ~= "" and name ~= run.name and not run.breached and run.brain then
				if run.brain:swapModel(name) then
					run.name = name
					CutKit.refreshGeometry(run)
					run.displayName = Sizes.Label(res.Mutation or run.mutation, run.size, name)
				end
			end
		end
	end

	-- (4) skip
	if run.skipEnabled and not run.skipArmed and run.t >= run.skipDelay then
		run.skipArmed = true
		if run.hype then
			run.hype:showSkipPrompt()
		end
	end
	if run.skipArmed and not run.skipping then
		if run.holdDown then
			run.holdTime += dt
		else
			run.holdTime = 0
		end
		local a = math.clamp(run.holdTime / run.skipHold, 0, 1)
		if run.hype then
			run.hype:setSkipProgress(a)
		end
		if a >= 1 then
			beginSkip(run)
		end
	end
	if run.skipping and run.skipPhase ~= "done" then
		run.skipClock += dt
		local half = math.max(run.skipFade * 0.5, 0.02)
		local dip = run.overlay
		local a = math.clamp(run.skipClock / half, 0, 1)
		if run.skipPhase == "out" then
			if dip then
				dip.BackgroundTransparency = 1 - a * DIP_MAX
			end
			if a >= 1 then
				if run.usesBridge and not run.resultSeen then
					run.skipHolding = true
				else
					run.skipHolding = false
					jumpTo(run, run.cut.skipTo or run.beats[#run.beats].name)
					run.skipPhase = "in"
					run.skipClock = 0
				end
			end
		else
			if dip then
				dip.BackgroundTransparency = 1 - (1 - a) * DIP_MAX
			end
			if a >= 1 then
				run.skipPhase = "done"
				if dip then
					dip.BackgroundTransparency = 1
				end
			end
		end
	end
	if run.finished then
		return
	end

	-- (5) the cut's per-frame work (rock, one-shots), pure in run.t
	if run.cut.everyFrame then
		run.cut.everyFrame(run)
	end

	-- (6) beat dispatch
	while run.beatIdx < #run.beats do
		local nextBeat = run.beats[run.beatIdx + 1]
		if run.t < nextBeat.t0 then
			break
		end
		runExit(run)
		run.beatIdx += 1
		local h = run.cut.handlers[nextBeat.name]
		if h and h.enter then
			h.enter(run)
		end
	end
	local beat = run.beats[run.beatIdx]
	if beat then
		local span = math.max(beat.t1 - beat.t0, 1e-3)
		local p = math.clamp((run.t - beat.t0) / span, 0, 1)
		local h = run.cut.handlers[beat.name]
		if h and h.update then
			h.update(run, p)
		end
	end

	-- (7) end of timeline
	if run.t >= run.beats[#run.beats].t1 then
		finish(run, true)
	end
end

local function step(run: Run, dt: number)
	if run.finished then
		return
	end
	local ok, err = pcall(stepInner, run, dt)
	if not ok then
		warn("[" .. TAG .. "] beat error, tearing down: " .. tostring(err))
		finish(run, false)
	end
end

-- ============================== build ==============================
-- Stage folder stays parented to NIL until every constructor has succeeded, so a
-- decline can happen with literally nothing in the world yet.
local function buildRun(run: Run): boolean
	local stage = Instance.new("Folder")
	stage.Name = STAGE_NAME
	run.stage = stage
	track(run, function()
		stage:Destroy()
	end)

	local okB, built = pcall(run.cut.build, run)
	if not okB then
		warn("[" .. TAG .. "] " .. run.cut.name .. " build errored: " .. tostring(built))
		return false
	end
	if built ~= true then
		return false
	end

	local audio = AudioBus.new(Config.ASSETS)
	run.audio = audio
	track(run, function()
		audio:cleanup()
	end)

	if not run.spectator then
		local player = Players.LocalPlayer
		-- The input lock (spec S11): throw/cast input refuses while this is set.
		-- Tracked so every exit path clears it.
		if player then
			player:SetAttribute(REVEAL_ATTR, true)
			track(run, function()
				player:SetAttribute(REVEAL_ATTR, nil)
			end)
		end

		local cam = CameraRig.new(Config.CAMERA)
		if cam:takeover() then
			run.cam = cam
			track(run, function()
				cam:restore()
			end)
			-- HIDE THE GAME HUD. Re-enabled by the trove on EVERY exit path; our own
			-- guis are never touched; a gui that vanishes mid-cut is skipped by the pcall.
			local pg = player and player:FindFirstChildOfClass("PlayerGui")
			if pg then
				local hidden = {}
				for _, g in ipairs(pg:GetChildren()) do
					if g:IsA("ScreenGui") and g.Enabled and g.Name ~= "CatchCinematicUI" and g.Name ~= FADE_GUI_NAME then
						g.Enabled = false
						table.insert(hidden, g)
					end
				end
				track(run, function()
					for _, g in ipairs(hidden) do
						pcall(function()
							g.Enabled = true
						end)
					end
				end)
			end
			local shake = ScreenShake.new(CutKit.shallowMerge(Config.SHAKE, {
				shakeMult = run.reducedMotion and (Config.REDUCED_MOTION.shakeMult or 0.25) or 1,
			}))
			run.shake = shake
			local lastSample = os.clock()
			cam:setShakeSource(function()
				local now = os.clock()
				local d = math.clamp(now - lastSample, 0, 0.1)
				lastSample = now
				return shake:sample(d)
			end)
		else
			warn("[" .. TAG .. "] camera takeover refused -- running without the camera")
		end

		local post = PostFX.new(run.postCfg, run.quality, run.reducedMotion)
		run.post = post
		track(run, function()
			post:cleanup()
		end)

		local hype = HypeUI.new(
			{ HYPE = Config.HYPE, SKIP = Config.SKIP, PARTICLES = Config.PARTICLES },
			run.quality, run.reducedMotion, run.rng, run.stretch
		)
		run.hype = hype
		track(run, function()
			hype:cleanup()
		end)
	end

	wireSkipInput(run)
	stage.Parent = Workspace
	return true
end

local function wireKillSwitches(run: Run)
	local player = Players.LocalPlayer
	if not player then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		local c = hum.Died:Connect(function()
			finish(run, false)
		end)
		track(run, function()
			c:Disconnect()
		end)
	end
	local ca = player.CharacterAdded:Connect(function()
		finish(run, false)
	end)
	track(run, function()
		ca:Disconnect()
	end)
end

-- ============================== public ==============================
function Takeover.isActive(): boolean
	return active ~= nil
end

function Takeover.debugState(): { [string]: any }?
	local run = active
	if not run then
		return nil
	end
	return {
		cut = run.cut.name, t = run.t, beat = run.beats[run.beatIdx] and run.beats[run.beatIdx].name,
		resultSeen = run.resultSeen, skipping = run.skipping, cancelling = run.cancelling,
		spectator = run.spectator, realElapsed = run.realElapsed,
	}
end

-- Studio harness seam: simulate the skip hold without real input.
function Takeover.debugHold(down: boolean)
	local run = active
	if run and RunService:IsStudio() then
		run.holdDown = down == true
		if not down then
			run.holdTime = 0
		end
	end
end

function Takeover.play(cut: Cut, payload: { [string]: any }, opts: PlayOpts?): boolean
	if active ~= nil then
		return false
	end
	if type(cut) ~= "table" or type(cut.beats) ~= "table" or #cut.beats == 0 then
		return false
	end
	if type(payload) ~= "table" or typeof(payload.EndPos) ~= "Vector3" then
		return false
	end
	if type(payload.BrainrotName) ~= "string" or payload.BrainrotName == "" then
		return false
	end
	local o = opts or {}
	local spectator = o.spectator == true
	local bridgeGen = o.bridgeGen
	local usesBridge = (not spectator) and Bridge.isCurrent(bridgeGen)
	local player = Players.LocalPlayer
	if not player then
		return false
	end

	local speed = Config.timescale()
	if type(speed) ~= "number" or speed <= 0 then
		speed = 1
	end
	local stretch = 1 / speed
	local endPos = payload.EndPos :: Vector3
	local surfaceY = tonumber(payload.SurfaceY) or endPos.Y
	local surface = Vector3.new(endPos.X, surfaceY, endPos.Z)
	local beats = cut.beats
	local mutation = (type(payload.Mutation) == "string" and payload.Mutation ~= "" and payload.Mutation ~= "None") and payload.Mutation or nil

	local run: Run = {
		payload = payload, cut = cut, trove = {}, cleaned = false, finished = false, ok = false,
		spectator = spectator, beats = beats, beatIdx = 0, t = 0, realElapsed = 0,
		speed = speed, stretch = stretch,
		budget = beats[#beats].t1 * stretch + WATCHDOG_PAD,
		surface = surface, horiz = CutKit.horizToward(surface),
		name = payload.BrainrotName, size = payload.Size, mutation = mutation,
		rarity = payload.Rarity,
		rarityColor = (typeof(payload.RarityColor) == "Color3") and payload.RarityColor or Color3.fromRGB(255, 220, 120),
		rng = Random.new(tonumber(payload.Seed) or 1),
		quality = Config.qualityFor(player),
		reducedMotion = player:GetAttribute("CinematicReducedMotion") == true,
		waterCfg = CutKit.scaleDurations(Config.WATER, WATER_DURATION_FIELDS, stretch),
		postCfg = CutKit.scaleDurations(Config.POSTFX, POSTFX_DURATION_FIELDS, stretch),
		bridgeGen = bridgeGen, usesBridge = usesBridge, committed = false,
		resultSeen = not usesBridge, breached = false,
		skipEnabled = spectator or cut.skippable == true,
		skipArmed = false, skipping = false, skipPhase = "none", skipClock = 0,
		holdDown = false, holdTime = 0, skipHolding = false,
		skipDelay = Config.SKIP.delay or 1.0,
		skipHold = math.max(Config.SKIP.holdSeconds or 0.45, 0.05),
		skipFade = math.max(Config.SKIP.exitFadeSeconds or 0.18, 0.04),
		cancelling = false, cancelClock = 0,
		cancelDeadline = CANCEL_DIP_IN + CANCEL_DIP_OUT + 0.5,
		cancelTimeout = math.max(tonumber(Config.CANCEL_TIMEOUT) or 3.0, 0.25) * stretch,
	}
	run.displayName = Sizes.Label(mutation, run.size, run.name)
	run.revealT0 = CutKit.beatT0(run, cut.revealBeat, beats[#beats].t1)

	active = run
	local okBuild, buildResult = pcall(buildRun, run)
	if not okBuild then
		warn("[" .. TAG .. "] build errored: " .. tostring(buildResult))
		drain(run)
		active = nil
		return false
	end
	if buildResult ~= true then
		drain(run)
		active = nil
		return false
	end

	if run.usesBridge then
		pcall(Bridge.markRunning, run.bridgeGen, run.budget + 4)
	end
	wireKillSwitches(run)

	runCounter += 1
	run.bindName = BIND_NAME .. VM_SALT .. "_" .. tostring(runCounter)
	local bindOk = pcall(function()
		RunService:BindToRenderStep(run.bindName, BIND_PRIORITY, function(dt: number)
			step(run, dt)
		end)
	end)
	if not bindOk then
		warn("[" .. TAG .. "] could not bind the conductor")
		drain(run)
		active = nil
		return false
	end
	track(run, function()
		pcall(function()
			RunService:UnbindFromRenderStep(run.bindName)
		end)
	end)
	task.delay(run.budget + 2, function()
		if active == run and not run.finished then
			warn("[" .. TAG .. "] backstop watchdog fired")
			finish(run, false)
		end
	end)

	run.committed = true
	if o.onCommit then
		pcall(o.onCommit)
	end
	while not run.finished do
		task.wait()
	end
	return true
end

return Takeover
