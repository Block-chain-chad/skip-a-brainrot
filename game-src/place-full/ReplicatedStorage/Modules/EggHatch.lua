--!strict
-- EggHatch (controller): turns one EggResult payload into one hatch presentation.
--
--   EggHatch.play(result, opts?) -> boolean    queue a run (one at a time, FIFO)
--   EggHatch.isActive() -> boolean
--   EggHatch.skip()                            end the current run now (restores everything)
--   EggHatch.setSpeed(mult)                    global pace; opts.speed multiplies per run
--
-- opts: { speed: number?, onStart: (() -> ())?, onDone: ((ok: boolean) -> ())? }
--
-- The run is a master clock in AUTHORED seconds (t += dt * speed) driving a sorted event
-- list plus per-frame updates for the stage (camera follow), every EggRig and every
-- RewardRig. Rigs are pure functions of that clock, which is what makes speed, batches
-- and a future skip/auto-hatch one number rather than a second animation.
--
-- ORDER OF TRUTH: the reward model is parented at the pop beat; its Plate (name,
-- rarity) is constructed only after every egg in the batch has popped. Nothing about
-- the result reaches the screen before the creature does.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(script:WaitForChild("Config"))
local Stage = require(script:WaitForChild("Stage"))
local EggRig = require(script:WaitForChild("EggRig"))
local RewardRig = require(script:WaitForChild("RewardRig"))
local Fx = require(script:WaitForChild("Fx"))
local Plate = require(script:WaitForChild("Plate"))
local EggConfig = require(Modules:WaitForChild("EggConfig"))
local PetConfig = require(Modules:WaitForChild("PetConfig"))
local Platform = require(Modules:WaitForChild("Platform"))
local SoundKit = require(Modules:WaitForChild("SoundKit"))
local okMut, MutationConfig = pcall(function() return require(Modules:WaitForChild("MutationConfig")) end)
if not okMut then MutationConfig = nil end
local okSize, SizeConfig = pcall(function() return require(Modules:WaitForChild("SizeConfig")) end)
if not okSize then SizeConfig = nil end

local player = Players.LocalPlayer
local BIND = "EggHatchStep"
local TAG = "[EggHatch]"

local M = {}

type Entry = {
	name: string, rarity: string, petId: string?, petUid: any, eggId: string?, eggKey: string,
	mutation: string?, size: string?, colour: Color3, rank: number,
}

type Job = { entries: { Entry }, opts: { [string]: any }, result: { [string]: any } }

local queue: { Job } = {}
local active: { [string]: any }? = nil

-- ------------------------------------------------------------------ helpers
local function rarityOf(name: string): string?
	local id = PetConfig.IdFor(name)
	local def = id and PetConfig.Pets[id]
	return def and def.Rarity
end

local function eggKeyFor(eggId: string?): string
	if type(eggId) == "string" then
		local worldId = EggConfig.WorldIdOfEgg(eggId)
		local egg = worldId and EggConfig.GetEgg(worldId, eggId)
		if egg and egg.Model then return egg.Model end
	end
	return "ForestEgg1"
end

local function sound(spec: { any }?, pitchMult: number?, volMult: number?)
	if not spec then return end
	local ok, err = pcall(SoundKit.play, spec[1], nil, { volume = spec[2] * (volMult or 1), speed = (spec[3] or 1) * (pitchMult or 1) })
	if not ok then warn(TAG .. " sound " .. tostring(spec[1]) .. " failed: " .. tostring(err)) end
end

local function normalise(result: { [string]: any }): { Entry }
	local rows = result.Results
	if type(rows) ~= "table" or #rows == 0 then
		rows = { { Name = result.Name, Rarity = result.Rarity, PetUid = result.PetUid, PetId = result.PetId, Mutation = result.Mutation, Size = result.Size } }
	end
	local out: { Entry } = {}
	for _, r in ipairs(rows) do
		if type(r) == "table" and type(r.Name) == "string" then
			local rarity = r.Rarity or rarityOf(r.Name) or "Rare"
			local eggId = r.EggId or result.EggId
			out[#out + 1] = {
				name = r.Name, rarity = rarity, petId = r.PetId, petUid = r.PetUid, eggId = eggId,
				eggKey = eggKeyFor(eggId), mutation = r.Mutation, size = r.Size,
				colour = Config.colourFor(rarity), rank = Config.RARITY_RANK[rarity] or 3,
			}
		end
	end
	return out
end

-- screen-fraction slots for n eggs: one shallow arc up to five, two arcs above
local function slotsFor(n: number): ({ { x: number, y: number, z: number } }, { [string]: any })
	if n <= 1 then return Config.LAYOUT[1].slots, Config.LAYOUT[1] end
	if n <= 3 then
		local L = Config.LAYOUT[3]
		if n == 3 then return L.slots, L end
		return { { x = -0.16, y = 0.08, z = 0.2 }, { x = 0.16, y = 0.08, z = 0.2 } }, L
	end
	if n <= 5 then
		local L = { frac = 0.23, phoneFrac = 0.26, shortFrac = 0.24, plateScale = 0.72 }
		local slots = {}
		for i = 1, n do
			local x = (i - (n + 1) / 2) * (0.62 / (n - 1))
			slots[i] = { x = x, y = 0.09 + 0.05 * math.abs(x) / 0.31, z = 0.5 * math.abs(x) / 0.31 }
		end
		return slots, L
	end
	local L = Config.LAYOUT[10]
	local top = math.ceil(n / 2)
	local bottom = n - top
	local slots = {}
	local function row(count: number, y: number, into: { any })
		for i = 1, count do
			local x = (count == 1) and 0 or (i - (count + 1) / 2) * (0.72 / (count - 1))
			into[#into + 1] = { x = x, y = y + 0.03 * math.abs(x) / 0.36, z = 0.6 * math.abs(x) / 0.36 }
		end
	end
	row(top, 0.25, slots)
	row(bottom, -0.13, slots)
	return slots, L
end

local function takeoverActive(): boolean
	local ok, res = pcall(function()
		local folder = Modules:FindFirstChild("CatchCinematic")
		local tk = folder and folder:FindFirstChild("Takeover")
		return tk and require(tk).isActive() or false
	end)
	return ok and res == true
end

-- ------------------------------------------------------------------ the run
local runNext

local function teardown(run, ok: boolean)
	pcall(RunService.UnbindFromRenderStep, RunService, BIND)
	for _, r in ipairs(run.rigs) do pcall(r.destroy, r) end
	for _, r in ipairs(run.rewards) do pcall(r.destroy, r) end
	for _, p in ipairs(run.plates) do pcall(p.destroy, p) end
	if active == run then active = nil end
	if run.opts.onDone then
		local okD, err = pcall(run.opts.onDone, ok)
		if not okD then warn(TAG .. " onDone failed: " .. tostring(err)) end
	end
	runNext()
end

-- ok = true: the clean exit (rewards and plates scale away, then the stage ramps out);
-- ok = false: a kill switch, everything restored this frame.
local function finishRun(run, ok: boolean)
	if run.ended then return end
	run.ended = true
	for _, c in ipairs(run.conns) do pcall(function() c:Disconnect() end) end
	if not ok then
		run.stage:abort()
		teardown(run, false)
		return
	end
	run.exiting = true
	for _, r in ipairs(run.rewards) do pcall(r.exit, r, run.t, Config.EXIT) end
	for _, p in ipairs(run.plates) do pcall(p.exit, p, Config.EXIT / run.speed) end
	sound(Config.SOUND.dismiss)
	task.delay(Config.EXIT / run.speed, function()
		run.stage:finish(function() teardown(run, true) end)
	end)
end

local function startRun(job: Job)
	local entries = job.entries
	local n = #entries
	local speed = math.max(0.05, Config.SPEED * (tonumber(job.opts.speed) or 1))
	local ts = 1 / speed   -- real seconds per authored second, for the screen tweens

	-- the batch's preset is its BEST tier; each egg keeps its own colour
	local best = entries[1]
	for _, e in ipairs(entries) do
		if e.rank > best.rank then best = e end
	end
	local preset = Config.presetFor(best.rarity)

	local stage = Stage.new({ veil = preset.veil, light = preset.light })
	local run = {
		job = job, opts = job.opts, stage = stage, preset = preset, speed = speed,
		t = 0, events = {}, rigs = {}, rewards = {}, plates = {}, conns = {}, ended = false, exiting = false,
		tapArmedAt = math.huge, autoEndAt = math.huge,
	}
	active = run

	local okBegin, errBegin = pcall(stage.begin, stage)
	if not okBegin then
		warn(TAG .. " stage failed to begin: " .. tostring(errBegin))
		finishRun(run, false)
		return
	end

	-- ---------------------------------------------------------------- layout
	local slots, layout = slotsFor(n)
	local frac = layout.frac
	if Platform.IsPhone then frac = layout.phoneFrac end
	if Platform.IsShortPhone and Platform.IsShortPhone() then frac = layout.shortFrac end
	local eggH = stage:heightFor(frac, 0)

	-- tiny per-egg offsets so a batch never moves in lockstep; the rarest egg of a
	-- Legendary-or-better batch pops last (its OFFSET moves, its slot does not)
	local offsets = {}
	for i = 1, n do offsets[i] = (i - 1) * Config.BATCH_OFFSET end
	if n > 1 and preset.rank >= Config.PRESETS.Legendary.rank then
		local bestIdx = 1
		for i, e in ipairs(entries) do
			if e.rank > entries[bestIdx].rank then bestIdx = i end
		end
		offsets[bestIdx] = (n - 1) * Config.BATCH_OFFSET + Config.BATCH_RAREST_EXTRA
	end

	local B = Config.BEATS
	local lastPop = 0
	local function at(time: number, fn: () -> ())
		run.events[#run.events + 1] = { time = time, fn = fn }
	end
	for i, e in ipairs(entries) do
		local s = slots[i] or slots[#slots]
		local base = stage:localPoint(s.x, s.y - frac * 0.5, s.z)
		local sizeMult = (e.size and Config.SIZE_SCALE[e.size]) or 1
		local okR, rig = pcall(EggRig.new, stage, {
			key = e.eggKey, height = eggH, slot = base, accent = e.colour, seed = 11 * i + 3, light = preset.light,
		})
		if not okR then
			warn(TAG .. " egg rig failed: " .. tostring(rig))
			finishRun(run, false)
			return
		end
		local okW, reward = pcall(RewardRig.new, stage, {
			name = e.name, petId = e.petId, mutation = e.mutation, height = eggH * 1.0, slot = base,
			sizeMult = sizeMult, pop = preset.pop, bounce = preset.bounce,
		})
		if not okW then
			warn(TAG .. " reward rig failed: " .. tostring(reward))
			finishRun(run, false)
			return
		end
		local okL, leak = pcall(Fx.leak, rig.core, e.colour, eggH)
		rig.leak = okL and leak or nil

		local off = offsets[i]
		local lean = {}
		for _, k in ipairs(B.lean) do lean[#lean + 1] = { off + k[1], k[2] } end
		local plan: EggRig.Plan = {
			enter = off, enterLen = B.enterLen, settle = off + B.settle, settleLen = B.settleLen,
			lean = lean, squash = off + B.squash, squashLen = B.squashLen,
			shake = off + B.shake, shakeLen = B.shakeLen, pop = off + B.pop,
		}
		rig.plan = plan
		run.rigs[i] = rig
		run.rewards[i] = reward
		lastPop = math.max(lastPop, plan.pop)

		local first = (i == 1)
		local isBest = (e == best)
		at(plan.enter, function()
			if first then sound(Config.SOUND.enter) end
		end)
		at(plan.settle, function()
			if first then sound(Config.SOUND.land) end
		end)
		-- knocks on the leans (the first egg only: a batch would stack nine ticks)
		if first then
			for ki = 2, #lean - 1, 2 do
				at(lean[ki][1], function() sound(Config.SOUND.knock, 1 + 0.06 * ki, 0.8 + 0.05 * ki) end)
			end
		end
		at(plan.squash, function()
			rig:setCracks(1)
			if rig.leak then rig.leak.Rate = 8 end
			if first then sound(Config.SOUND.squash) end
		end)
		at(plan.shake, function()
			rig:setCracks(2)
			if rig.leak then rig.leak.Rate = 22 end
			if first then sound(Config.SOUND.shake); stage:kick(0.3, 0) end
		end)
		at(plan.pop, function()
			if rig.leak then rig.leak.Rate = 0 end
			local centre = rig:centreWorld()
			pcall(Fx.burst, stage.folder, centre, e.colour, 0.6 + 0.2 * (preset.rank / 8), eggH)
			sound(Config.SOUND.pop, 1, first and 1 or 0.7)
			sound(Config.SOUND.popLayer, 1 + 0.04 * i, first and 1 or 0.7)
			stage:kick(preset.kick * (isBest and 1 or 0.5), isBest and preset.punch or 0)
			if isBest and preset.flash > 0 then
				pcall(Fx.flash, stage.fxLayer, Color3.new(1, 1, 1):Lerp(e.colour, 0.25), preset.flash, 0.22, ts)
			end
		end)
		at(plan.pop + B.reward, function()
			reward:reveal(run.t)
			if isBest then
				sound({ preset.sting, preset.stingVol, 1 })
				for _, layer in ipairs(preset.layers) do
					local l = layer
					task.delay(l[3] * ts, function()
						if not run.ended then sound({ l[1], l[2], 1 }) end
					end)
				end
				if preset.ring then
					pcall(Fx.ring, stage.fxLayer, stage:toScreen(base + Vector3.new(0, eggH * 0.5, 0)), e.colour, (eggH * 34 + 90) * preset.ringSize, 0.45, ts)
				end
				if preset.orbit then
					local host = reward.model.PrimaryPart or reward.model:FindFirstChildWhichIsA("BasePart")
					if host then pcall(Fx.orbit, host, e.colour, eggH, 10) end
				end
			end
		end)
	end

	-- plates only once the last egg has popped; celebration a beat after
	local plateStart = lastPop + B.plate
	local lastPlate = plateStart
	for i, e in ipairs(entries) do
		local when = plateStart + (i - 1) * Config.PLATE_STAGGER
		lastPlate = math.max(lastPlate, when)
		at(when, function()
			local rig = run.rigs[i]
			local pos = stage:toScreen(rig.slot + Vector3.new(0, -eggH * 0.05, 0))
			local tags = {}
			if e.mutation then
				local col = (MutationConfig and MutationConfig.Color and MutationConfig.Color(e.mutation)) or Color3.fromRGB(255, 215, 90)
				tags[#tags + 1] = { e.mutation, col }
			end
			if e.size then
				local col = (SizeConfig and SizeConfig.Color and SizeConfig.Color(e.size)) or Color3.fromRGB(120, 220, 255)
				tags[#tags + 1] = { e.size, col }
			end
			local okP, plate = pcall(Plate.new, stage.plateLayer, pos, stage.vp.Y, {
				name = e.name, rarity = e.rarity, colour = e.colour, tags = tags,
				scale = layout.plateScale, slam = preset.plateSlam,
			})
			if okP then
				run.plates[#run.plates + 1] = plate
				plate:show(preset.plateSlam and e == best, ts)
				if i == 1 then sound(Config.SOUND.plate) end
			else
				warn(TAG .. " plate failed: " .. tostring(plate))
			end
		end)
	end
	at(lastPop + B.celebrate, function()
		if preset.confetti > 0 then
			local bestIdx = 1
			for i, e in ipairs(entries) do
				if e == best then bestIdx = i end
			end
			local rig = run.rigs[bestIdx]
			local pos = stage:toScreen(rig.slot + Vector3.new(0, eggH * 0.7, 0))
			pcall(Fx.confetti, stage.fxLayer, pos, preset.confetti, { best.colour, Color3.new(1, 1, 1), best.colour:Lerp(Color3.new(1, 1, 1), 0.5) }, math.max(120, eggH * 46), ts)
		end
	end)
	run.tapArmedAt = lastPlate + Config.TAP_GRACE
	run.autoEndAt = lastPlate + preset.hold + ((n >= 6) and 1.0 or (n >= 3) and 0.35 or 0)

	table.sort(run.events, function(a, b) return a.time < b.time end)
	run.nextEvent = 1
	-- QA seam: the run's shape as one attribute (inert unless something reads it)
	pcall(function()
		player:SetAttribute("EggHatchRun", string.format("n=%d preset=%s speed=%.2f lastPop=%.2f plates=%.2f end=%.2f D=%.2f eggH=%.2f",
			n, best.rarity, speed, lastPop, lastPlate, run.autoEndAt, stage.D, eggH))
	end)

	stage.onTap = function()
		if run.ended then return end
		if run.t >= run.tapArmedAt then finishRun(run, true) end
	end

	-- kill switches: a death or respawn mid-hatch restores everything this frame
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		run.conns[#run.conns + 1] = hum.Died:Connect(function() finishRun(run, false) end)
	end
	run.conns[#run.conns + 1] = player.CharacterAdded:Connect(function() finishRun(run, false) end)
	-- watchdog: whatever happens, the HUD comes back
	task.delay(run.autoEndAt * ts + 6, function()
		if not run.ended then
			warn(TAG .. " watchdog fired -- forcing the hatch to end")
			finishRun(run, true)
		elseif active == run and run.exiting then
			-- an exit that never landed (stage finish callback lost): hard stop
			warn(TAG .. " exit watchdog -- hard stop")
			run.stage:abort()
			teardown(run, true)
		end
	end)

	if run.opts.onStart then pcall(run.opts.onStart) end

	-- ---------------------------------------------------------------- the driver
	local function step(dt: number)
		if run.stage.done then return end
		local okS, err = pcall(function()
			dt = math.min(dt, 0.1)
			local dtA = dt * speed
			-- QA seam: EggHatchHold = an authored time the clock parks at (captures land on
			-- an exact beat); inert unless the attribute is set
			local hold = player:GetAttribute("EggHatchHold")
			if type(hold) == "number" and run.t + dtA >= hold and not run.exiting then
				dtA = math.max(0, hold - run.t)
			end
			run.t += dtA
			stage:update(dt)
			if not run.ended then
				while run.nextEvent <= #run.events and run.events[run.nextEvent].time <= run.t do
					local ev = run.events[run.nextEvent]
					run.nextEvent += 1
					local okE, errE = pcall(ev.fn)
					if not okE then warn(TAG .. " event failed: " .. tostring(errE)) end
				end
			end
			for _, rig in ipairs(run.rigs) do
				rig:update(dtA, run.t - rig.plan.enter, rig.plan)
			end
			for _, reward in ipairs(run.rewards) do
				reward:update(dtA, run.t)
			end
			if not run.ended and run.t >= run.autoEndAt then finishRun(run, true) end
		end)
		if not okS then
			warn(TAG .. " step failed, ending the hatch: " .. tostring(err))
			finishRun(run, false)
		end
	end
	RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 1, step)
end

runNext = function()
	if active then return end
	local job = table.remove(queue, 1)
	if not job then return end
	if takeoverActive() then
		table.insert(queue, 1, job)
		task.delay(0.25, runNext)
		return
	end
	local ok, err = pcall(startRun, job)
	if not ok then
		warn(TAG .. " run failed to start: " .. tostring(err))
		if active then finishRun(active, false) else runNext() end
	end
end

-- ------------------------------------------------------------------ public
function M.play(result: { [string]: any }, opts: { [string]: any }?): boolean
	if type(result) ~= "table" or result.Ok == false then return false end
	local entries = normalise(result)
	if #entries == 0 then return false end
	-- a batch bigger than the layout supports splits into runs of ten
	while #entries > 10 do
		local chunk = {}
		for i = 1, 10 do chunk[i] = table.remove(entries, 1) end
		table.insert(queue, { entries = chunk, opts = opts or {}, result = result })
	end
	table.insert(queue, { entries = entries, opts = opts or {}, result = result })
	runNext()
	return true
end

function M.isActive(): boolean
	return active ~= nil
end

function M.skip()
	if active then finishRun(active, true) end
end

function M.setSpeed(mult: number)
	if type(mult) == "number" and mult > 0 then Config.SPEED = mult end
end

function M.queued(): number
	return #queue
end

return M
