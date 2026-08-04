-- BrainrotIdleClient: idle motion for every body Model tagged "BrainrotBody".
-- Bodies are server-anchored primitives, so every CFrame write below is
-- client-local and never replicates back -- the server pays nothing for any
-- of this. Everything runs off ONE Heartbeat: per-model connections at
-- full-plot scale would be hundreds of callbacks a frame doing identical work.
-- The look must be identical for every player on every server, so nothing in
-- here calls math.random -- phases come from a hash (see phaseFor).
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TAG = "BrainrotBody"

local RANGE = 120          -- studs; a body further than this from the camera sits still that frame
local BUDGET = 80          -- most bodies moved per frame; past this only the nearest move
local AMPLITUDE = 0.15     -- studs of vertical travel for bob/hover
local SWAY_ANGLE = math.rad(3.5)
local HOVER_YAW = 0.6      -- rad/s
local SPIN_YAW = 1.1       -- rad/s; about one lazy turn every six seconds
local SHIVER_AMP = 0.05    -- studs; shiver should read as tension, not travel
-- Tolerance for deciding the SERVER re-seated a body. The drift check
-- compares against the exact pivot WE last wrote (lastPos), so the presets'
-- own offsets can never trip it, whatever their amplitude -- this is purely
-- replication-jitter headroom.
local RESEAT = 0.5

-- Phase must be stable across sessions and identical on every client, so it
-- is hashed, never rolled. The name alone is not enough: plots can hold
-- duplicates of the SAME brainrot, and same-name bodies would move in
-- lockstep -- so the spawn position salts the hash. The spawn pivot is fixed
-- per pad, which makes the salt exactly as stable as the name.
local function phaseFor(model, base)
	local name = model.Name
	local h = 0
	for i = 1, #name do
		-- keep h small: Luau numbers are doubles, and unbounded growth would
		-- discard the low bits that carry all of the stagger
		h = (h * 33 + string.byte(name, i)) % 8192
	end
	local p = base.Position
	h = h + math.floor(p.X + 0.5) * 5 + math.floor(p.Z + 0.5) * 13
	return (h % 628) * 0.01   -- 0 .. ~2*pi
end

-- Each preset maps (t, phase) to an offset CFrame layered onto the spawn
-- pivot. Offsets compose in PIVOT space, so yaw always turns a body around
-- its own up axis no matter how the pad oriented it.
local MOTIONS = {}

function MOTIONS.bob(t, phase)
	-- remapped to 0..AMPLITUDE rather than a centered sine: a body that dips
	-- BELOW its spawn pivot sinks its feet into the pad it is seated on
	return CFrame.new(0, (math.sin(t * 2.1 + phase) * 0.5 + 0.5) * AMPLITUDE, 0)
end

function MOTIONS.sway(t, phase)
	-- rotation, not translation: sliding a seated body sideways would shear
	-- its feet across the pad, while a small roll reads as rocking in place
	return CFrame.Angles(0, 0, math.sin(t * 1.7 + phase) * SWAY_ANGLE)
end

function MOTIONS.hover(t, phase)
	return CFrame.new(0, (math.sin(t * 2.1 + phase) * 0.5 + 0.5) * AMPLITUDE, 0)
		* CFrame.Angles(0, t * HOVER_YAW + phase, 0)
end

function MOTIONS.spin(t, phase)
	return CFrame.Angles(0, t * SPIN_YAW + phase, 0)
end

function MOTIONS.shiver(t, phase)
	-- two prime frequencies so the jitter never settles into a visible cycle;
	-- the phase multiplier keeps the axes from tracing a diagonal line
	return CFrame.new(
		math.sin(t * 41 + phase) * SHIVER_AMP,
		0,
		math.sin(t * 53 + phase * 1.7) * SHIVER_AMP)
end

-- bodies[model] = { model, animBase, rel, lastPos, phase, offset, dist, conn }
local bodies = {}

local function drop(model)
	local entry = bodies[model]
	if not entry then return end
	bodies[model] = nil
	entry.conn:Disconnect()
	-- a body that survives untagged parks exactly where the server thinks it
	-- is, so nothing is left frozen mid-bob above its pad
	if model.Parent and entry.animBase then
		model:PivotTo(entry.animBase * entry.rel)
	end
end

local function adopt(model)
	if bodies[model] ~= nil or not model:IsA("Model") then return end
	local offset = MOTIONS[model:GetAttribute("Motion")]
	-- "none" and anything unrecognized cost zero from here on: never tracked,
	-- never iterated, never pivoted
	if not offset then return end
	-- Capture NOTHING here. The tag signal fires mid-replication-burst, and a
	-- capture taken then can see a half-arrived model: PrimaryPart may not
	-- have replicated yet, so GetPivot falls back near the box centre and
	-- `rel` bakes in as identity -- then the real (limb) pivot arrives a
	-- frame later and the body yaws about the limb again, which is exactly
	-- the orbit the animBase rework removes. Observed live: pivot pinned dead
	-- still, body orbiting it. The Heartbeat captures on the body's first
	-- animated frame instead, after replication has settled.
	bodies[model] = {
		model = model,
		offset = offset,
		dist = 0,
		conn = model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(Workspace) then
				drop(model)
			end
		end),
	}
end

-- a player can join with plots already full, so sweep what exists first
for _, model in ipairs(CollectionService:GetTagged(TAG)) do
	adopt(model)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(adopt)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(drop)

-- scratch list reused every frame so the loop allocates nothing at steady state
local candidates = {}

RunService.Heartbeat:Connect(function()
	local camera = Workspace.CurrentCamera
	if not camera then return end
	local camPos = camera.CFrame.Position
	local t = os.clock()

	table.clear(candidates)
	for _, entry in pairs(bodies) do
		-- Deferred capture (see adopt): animate about an UPRIGHT frame at the
		-- bounding-box centre, NOT the raw pivot -- on the pack models the
		-- pivot is an arbitrary limb (CatchReveal measured 3.75 studs off),
		-- and yawing about a limb makes the body ORBIT across neighbouring
		-- pads. `rel` carries the offset pivot along, so PivotTo lands the
		-- body exactly where it stood; on a centred pivot (BrainrotSpawner
		-- now centres them at spawn) rel is identity. One-time cost per body.
		if not entry.animBase then
			local pivot = entry.model:GetPivot()
			local boxCF = entry.model:GetBoundingBox()
			entry.animBase = CFrame.new(boxCF.Position)
			entry.rel = entry.animBase:ToObjectSpace(pivot)
			entry.lastPos = pivot.Position
			entry.phase = phaseFor(entry.model, entry.animBase)
		end
		-- gate on the cached box centre: one Vector3 subtraction per body,
		-- where GetPivot here would touch every part of every body every frame
		entry.dist = (entry.animBase.Position - camPos).Magnitude
		if entry.dist <= RANGE then
			candidates[#candidates + 1] = entry
		end
	end

	local count = #candidates
	if count > BUDGET then
		-- sort only once over budget, so the common case never pays for it
		table.sort(candidates, function(a, b)
			return a.dist < b.dist
		end)
		count = BUDGET
	end

	for i = 1, count do
		local entry = candidates[i]
		local model = entry.model
		-- the server can re-seat a body (mover, pad shuffle) and its writes
		-- land on the anchored parts over ours. We know exactly where WE left
		-- the pivot (lastPos), so any real difference is a server move --
		-- recapture both frames from the new pose, or the body would snap
		-- back to wherever it spawned
		local current = model:GetPivot()
		if (current.Position - entry.lastPos).Magnitude > RESEAT then
			local boxCF = model:GetBoundingBox()
			entry.animBase = CFrame.new(boxCF.Position)
			entry.rel = entry.animBase:ToObjectSpace(current)
		end
		local target = entry.animBase * entry.offset(t, entry.phase) * entry.rel
		model:PivotTo(target)
		entry.lastPos = target.Position
	end
end)
-- ============================ IDLE VOICE LINES ============================
-- The creature occasionally says its own line while sitting on a pad. This is
-- the most annoying thing in the game if it is wrong, so every number here is
-- deliberately conservative and every one is a named constant.
--
-- Runs on its OWN slow timer, never the Heartbeat above: this fires about once
-- a minute, and putting it on a per-frame loop to do nothing 3599 times out of
-- 3600 would be waste. Client-side and positional -- your camp should sound
-- alive when you are standing in it, and silent from across the valley.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundKit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundKit"))
local BrainrotConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BrainrotConfig"))

local VOICE_INTERVAL   = 45     -- seconds between attempts (base)
local VOICE_JITTER     = 15     -- +/- seconds, so a plot never speaks in chorus
local VOICE_RANGE      = 60     -- studs; HALF the 120 visual range -- audio intrudes more
local VOICE_COOLDOWN   = 90     -- seconds before the SAME body may speak again
local VOICE_MIN_GAP    = 8      -- seconds between ANY two voices, anywhere
local VOICE_VOLUME     = 0.18   -- under the splash register

-- name -> VoiceId, built once. Empty today: no entry in BrainrotConfig has a
-- VoiceId yet, so this whole system is inert until one is authored.
local voiceByName = {}
for _, e in ipairs(BrainrotConfig) do
	if type(e.VoiceId) == "string" and e.VoiceId ~= "" then
		voiceByName[e.Name] = e.VoiceId
	end
end

local player = Players.LocalPlayer
local lastSpoke = {}          -- [model] = os.clock() of its last line
local lastAnyVoice = 0        -- global gap, the real anti-noise guard

task.spawn(function()
	while true do
		task.wait(VOICE_INTERVAL + (math.random() * 2 - 1) * VOICE_JITTER)

		-- Nothing authored -> nothing to do. Costs one table lookup a minute.
		if next(voiceByName) ~= nil then
			local now = os.clock()
			if now - lastAnyVoice >= VOICE_MIN_GAP then
				local cam = Workspace.CurrentCamera
				local origin = cam and cam.CFrame.Position
				if origin then
					-- Collect every eligible body, then pick ONE. Picking one and
					-- playing it is the concurrency cap: there is no path here
					-- that starts a second voice in the same pass.
					local eligible = {}
					for _, model in ipairs(CollectionService:GetTagged(TAG)) do
						local id = voiceByName[model.Name]
						if id and model.Parent then
							local ok, pivot = pcall(function() return model:GetPivot().Position end)
							if ok and (pivot - origin).Magnitude <= VOICE_RANGE then
								local last = lastSpoke[model]
								if not last or now - last >= VOICE_COOLDOWN then
									eligible[#eligible + 1] = { model = model, id = id, part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart") }
								end
							end
						end
					end
					if #eligible > 0 then
						local pick = eligible[math.random(1, #eligible)]
						if pick.part then
							SoundKit.playId(pick.id, pick.part, { volume = VOICE_VOLUME, range = VOICE_RANGE })
							lastSpoke[pick.model] = now
							lastAnyVoice = now
						end
					end
				end
			end
		end

		-- prune bodies that have been despawned, so lastSpoke cannot grow forever
		for model in pairs(lastSpoke) do
			if not model.Parent then lastSpoke[model] = nil end
		end
	end
end)
