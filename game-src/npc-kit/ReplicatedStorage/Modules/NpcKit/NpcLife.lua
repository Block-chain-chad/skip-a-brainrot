-- NpcLife -- the client-side NPC driver, as a module with injected services.
--
-- NpcLifeClient (the LocalScript) builds one of these with the real services
-- and feeds it Heartbeat + prompt/dialogue events; tools/npc_kit builds one
-- with stubs and feeds it fake frames. Same code either way.
--
-- INERT BY CONSTRUCTION (decision D-7): the registry fills only from the
-- `NpcBody` tag. With no tagged bodies, step() is a single comparison per
-- frame -- no scans, no writes, no interference with the legacy rigs (which
-- carry a Humanoid and never the tag). A body is adopted with ONE descendant
-- scan at adopt time and never scanned again.
--
-- What it writes, and only on the client: Motor6D.C0 (procedural pose from a
-- captured rest), face part C0/Size (expression, blink, gaze, talk),
-- PointLight.Enabled (by band), and Model:PivotTo for creature breathing.
-- Never Transform (the Animator's), never anything on the server, never a
-- prompt, never a quest.

local NpcLife = {}
NpcLife.__index = NpcLife

local TAG = "NpcBody"
local GESTURE_IN, GESTURE_OUT = 0.25, 0.35
local TRACK_RAMP = 0.3
local TALK_TIMEOUT = 180
local GREET_COOLDOWN = 8

-- ===== construction ==========================================================
-- deps = {
--   CollectionService, Workspace, Players,             -- Roblox services (or stubs)
--   camera = function() -> Camera,                     -- current camera
--   playerHead = function() -> Vector3 | nil,          -- local player's head position
--   now = function() -> seconds,                       -- synchronised clock (GetServerTimeNow) or os.clock
--   modules = { RigSpec, FaceConfig, MotionConfig, LodProfiles, Motion },
--   log = function(msg) (optional),
-- }
function NpcLife.new(deps)
	assert(deps and deps.modules, "NpcLife.new needs deps.modules")
	local self = setmetatable({}, NpcLife)
	self.deps = deps
	self.M = deps.modules
	self.entries = {}
	self.count = 0
	self.frame = 0
	self.animated = {}
	self.lastTrigger = { entry = nil, at = -1e9 }
	self.dialogVisible = false
	self.talkingEntry = nil
	self.conns = {}
	self.tracked = {}
	self.stats = { adopts = 0, drops = 0, writes = 0, ranks = 0 }
	return self
end

local function log(self, msg)
	if self.deps.log then self.deps.log(msg) end
end

-- ===== helpers ===============================================================
local function parseOverrides(s)
	-- "idle.breathe.period=2.9;greet=ringBell;gestures.ringBell.weight=3"
	if type(s) ~= "string" or s == "" then return nil end
	local out = {}
	for pair in string.gmatch(s, "[^;]+") do
		local k, v = pair:match("^%s*([^=]+)%s*=%s*(.-)%s*$")
		if k and v then
			if v == "true" then out[k] = true
			elseif v == "false" then out[k] = false
			elseif tonumber(v) then out[k] = tonumber(v)
			else out[k] = v end
		end
	end
	return out
end

local function pivotOf(model)
	local ok, cf = pcall(function() return model:GetPivot() end)
	if ok then return cf end
	return CFrame.new()
end

-- ===== adopt / drop ==========================================================
function NpcLife:adopt(model)
	if self.entries[model] then return self.entries[model] end
	if not (model and model:IsA("Model")) then return nil end
	local M = self.M
	local rig = model:GetAttribute("NpcRig") or "SR1"
	local tier = tonumber(model:GetAttribute("NpcTier")) or 2
	local packId = model:GetAttribute("NpcPack") or "Background"
	local profile = model:GetAttribute("NpcProfile")
	local overrides = parseOverrides(model:GetAttribute("NpcPackOverrides"))
	local okPack, pack = pcall(M.MotionConfig.Resolve, packId, overrides, profile)
	if not okPack then log(self, "[NpcLife] " .. model.Name .. ": bad pack " .. tostring(packId) .. " -- skipped"); return nil end

	local entry = {
		model = model, rig = rig, tier = tier, pack = pack,
		lod = M.LodProfiles.Get(tier),
		joints = {}, jointList = {}, face = nil, lights = {}, planted = {},
		band = nil, animatedFlag = false, dist = math.huge, offscreenSince = nil,
		gesture = nil, cooldowns = {}, drawIndex = 0,
		trackWeight = 0, aimTurn = 0, aimBend = 0,
		promptShown = false, talking = false, talkingSince = 0, greetPending = false, lastGreet = -1e9,
		nextTalkGesture = 0, nextBlink = 0, blinkUntil = 0, mouthOpen = false, mouthBurstUntil = 0, mouthRestUntil = 0, nextGaze = 0,
		lastWritten = {}, frameCounter = 0, dirtyModel = false,
	}
	local pivot = pivotOf(model)
	entry.basePivot = pivot
	entry.phase = M.Motion.phaseFor(model.Name, pivot.Position)
	entry.seed = M.Motion.seedFor(model.Name, pivot.Position)

	-- root
	if rig == "Creature" then
		entry.root = model.PrimaryPart or model:FindFirstChild("RootPart")
	else
		entry.root = model:FindFirstChild("HumanoidRootPart")
	end
	if not entry.root then log(self, "[NpcLife] " .. model.Name .. ": no root part -- skipped"); return nil end

	-- ONE scan. Joints, face, lights, planted props all come out of it.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and d.Name ~= "FaceJoint" then
			local class, side
			if rig == "Creature" then
				class, side = M.RigSpec.ClassifyCreatureJoint(d.Name)
			else
				class = M.RigSpec.JointClass[d.Name]
				side = M.RigSpec.Side[d.Name]
			end
			if class then
				local j = { joint = d, rest = d.C0, class = class, side = side or 1, name = d.Name }
				entry.joints[d.Name] = j
				entry.jointList[#entry.jointList + 1] = j
			end
		elseif d:IsA("PointLight") or d:IsA("SpotLight") then
			entry.lights[#entry.lights + 1] = d
		elseif d:IsA("BasePart") and d:GetAttribute("Planted") == true then
			local grip = d:GetAttribute("Grip") or "RightHand"
			entry.planted[grip] = true
		end
	end
	-- creature joints are addressed by the pack under generic names (Head, WingL);
	-- map those onto whatever the template calls them, by loose match
	if rig == "Creature" then
		local function alias(generic, patterns)
			if entry.joints[generic] then return end
			for name, j in pairs(entry.joints) do
				local n = name:lower()
				for _, p in ipairs(patterns) do
					if n:find(p) then entry.joints[generic] = j; return end
				end
			end
		end
		alias("Head", { "head", "neck" })
		alias("WingL", { "wing_l", "wingl", "leftwing", "wing1" })
	end

	-- face
	local faceFolder = model:FindFirstChild("Face")
	if faceFolder then
		local f = { parts = {}, joints = {}, rest = {}, expr = model:GetAttribute("NpcFace") or M.FaceConfig.Default }
		for _, p in ipairs(faceFolder:GetChildren()) do
			local j = p:FindFirstChild("FaceJoint")
			if p:IsA("BasePart") and j then
				f.parts[p.Name] = p
				f.joints[p.Name] = j
			end
		end
		if next(f.parts) then
			entry.face = f
			self:_applyFace(entry, f.expr)
		end
	end

	-- gesture cooldown seeds
	for name, g in pairs(pack.gestures) do
		if (g.weight or 0) > 0 then
			entry.drawIndex = entry.drawIndex + 1
			entry.cooldowns[name] = self.deps.now() + M.Motion.draw(entry.seed, entry.drawIndex, g.cooldown[1], g.cooldown[2]) * 0.5
		end
	end

	self.entries[model] = entry
	self.count = self.count + 1
	self.stats.adopts = self.stats.adopts + 1

	local faceConn = model:GetAttributeChangedSignal("NpcFace"):Connect(function()
		local e = self.entries[model]
		if e and e.face then
			e.face.expr = model:GetAttribute("NpcFace") or M.FaceConfig.Default
			self:_applyFace(e, e.face.expr)
		end
	end)
	self.conns[model] = { faceConn }
	return entry
end

function NpcLife:drop(model)
	local entry = self.entries[model]
	if not entry then return end
	local conns = self.conns[model]
	if conns then for _, c in ipairs(conns) do c:Disconnect() end end
	self.conns[model] = nil
	self.entries[model] = nil
	self.count = self.count - 1
	self.stats.drops = self.stats.drops + 1
	if self.talkingEntry == entry then self.talkingEntry = nil end
	if self.lastTrigger.entry == entry then self.lastTrigger.entry = nil end
end

-- A tagged model is TRACKED for as long as it carries the tag, wherever it is:
-- adopted whenever it is inside Workspace, dropped whenever it leaves (streaming
-- out, being parked back in storage). NpcForge tags a body while it sits in
-- ServerStorage.NpcStaging, so "tag added" and "entered Workspace" are two
-- different moments -- the first version of this driver missed the second.
function NpcLife:_track(model)
	if self.tracked[model] then return end
	local function sync()
		if model:IsDescendantOf(self.deps.Workspace) then
			if not self.entries[model] then self:adopt(model) end
		else
			if self.entries[model] then self:drop(model) end
		end
	end
	self.tracked[model] = model.AncestryChanged:Connect(sync)
	sync()
end

function NpcLife:_untrack(model)
	local c = self.tracked[model]
	if c then c:Disconnect() end
	self.tracked[model] = nil
	self:drop(model)
end

-- start(): one GetTagged (not a workspace walk) + the two tag signals.
function NpcLife:start()
	local CS = self.deps.CollectionService
	self.tracked = self.tracked or {}
	for _, m in ipairs(CS:GetTagged(TAG)) do self:_track(m) end
	self.tagAdded = CS:GetInstanceAddedSignal(TAG):Connect(function(m) self:_track(m) end)
	self.tagRemoved = CS:GetInstanceRemovedSignal(TAG):Connect(function(m) self:_untrack(m) end)
	log(self, ("[NpcLife] online (%d NPC-01 bodies)"):format(self.count))
end

function NpcLife:stop()
	if self.tagAdded then self.tagAdded:Disconnect() end
	if self.tagRemoved then self.tagRemoved:Disconnect() end
	for model in pairs(self.tracked or {}) do self:_untrack(model) end
end

-- ===== face ==================================================================
function NpcLife:_applyFace(entry, exprId)
	local f = entry.face
	if not f then return end
	local resolved = self.M.FaceConfig.Resolve(exprId)
	f.rest = resolved
	for name, r in pairs(resolved) do
		local j, p = f.joints[name], f.parts[name]
		if j and p then
			j.C0 = r.c0
			p.Size = r.size
		end
	end
	f.expr = exprId
end

-- ===== ranking ===============================================================
local function entryForPrompt(self, prompt)
	local node = prompt and prompt.Parent
	local guard = 0
	while node and guard < 12 do
		local e = self.entries[node]
		if e then return e end
		node = node.Parent
		guard = guard + 1
	end
	return nil
end

function NpcLife:_rank(now)
	local G = self.M.LodProfiles.Global
	local cam = self.deps.camera()
	if not cam then return end
	local camPos, camLook = cam.CFrame.Position, cam.CFrame.LookVector
	local candidates = {}
	for _, e in pairs(self.entries) do
		local pivot = pivotOf(e.model)
		local diff = pivot.Position - camPos
		local d = diff.Magnitude
		e.dist = d
		local band = nil
		if d <= G.worldRadius then
			band = self.M.LodProfiles.BandFor(e.lod, d)
			if e.talking or e.promptShown then band = e.lod.bands[1] end
		end
		-- off-screen with hysteresis (behind the camera, or outside the viewport)
		local behind = d > 1 and (diff / d):Dot(camLook) < G.offscreenDot
		local onScreen = true
		if not behind then
			local ok, _, vis = pcall(function() return cam:WorldToViewportPoint(pivot.Position) end)
			if ok and vis == false then onScreen = false end
		end
		if (behind or not onScreen) and not e.talking then
			if not e.offscreenSince then e.offscreenSince = now end
			if now - e.offscreenSince >= G.offscreenHold then band = nil end
		else
			e.offscreenSince = nil
		end
		e.band = band
		if band then candidates[#candidates + 1] = e end
	end
	table.sort(candidates, function(a, b)
		if a.talking ~= b.talking then return a.talking end
		return a.dist < b.dist
	end)
	local animated = {}
	for i, e in ipairs(candidates) do
		if i <= G.maxAnimated then animated[#animated + 1] = e end
	end
	-- flags + lights (only written on change)
	local set = {}
	for _, e in ipairs(animated) do set[e] = true end
	for _, e in pairs(self.entries) do
		local isAnim = set[e] == true
		e.animatedFlag = isAnim
		local lightsOn = isAnim and e.band and e.band.lights or false
		if e.lightsOn ~= lightsOn then
			e.lightsOn = lightsOn
			for _, l in ipairs(e.lights) do l.Enabled = lightsOn end
		end
	end
	self.animated = animated
	self.stats.ranks = self.stats.ranks + 1
end

-- ===== per-frame ===========================================================
function NpcLife:step(dt, now)
	if self.count == 0 then return end          -- INERT: nothing tagged, nothing done
	self.frame = self.frame + 1
	if self.frame % self.M.LodProfiles.Global.rankEvery == 1 or not self.rankedOnce then
		self.rankedOnce = true
		self:_rank(now)
	end
	-- talking safety: walk-away / timeout
	local te = self.talkingEntry
	if te then
		local head = self.deps.playerHead()
		local far = head and (head - te.root.Position).Magnitude > (te.lod.talkRange > 0 and te.lod.talkRange or 24)
		if far or (now - te.talkingSince) > TALK_TIMEOUT then self:_setTalking(te, false, now) end
	end
	for _, e in ipairs(self.animated) do
		self:_update(e, dt, now)
	end
end

local function gestureWeight(elapsed, duration)
	local win = elapsed / GESTURE_IN
	local wout = (duration - elapsed) / GESTURE_OUT
	local w = win < wout and win or wout
	if w > 1 then w = 1 end
	if w < 0 then w = 0 end
	return w
end

function NpcLife:_pickGesture(entry, now, talkOnly)
	local pack = entry.pack
	local names = {}
	if talkOnly then
		for _, n in ipairs(pack.talk and pack.talk.gestures or {}) do names[#names + 1] = n end
	else
		for n, g in pairs(pack.gestures) do
			if (g.weight or 0) > 0 and not g.talk and not g.signatureOnlyOnGreet and (entry.cooldowns[n] or 0) <= now then names[#names + 1] = n end
		end
		table.sort(names)
	end
	if #names == 0 then return nil end
	local total = 0
	for _, n in ipairs(names) do total = total + (pack.gestures[n] and pack.gestures[n].weight or 1) end
	entry.drawIndex = entry.drawIndex + 1
	local r = self.M.Motion.draw(entry.seed, entry.drawIndex, 0, total)
	local acc = 0
	for _, n in ipairs(names) do
		acc = acc + (pack.gestures[n] and pack.gestures[n].weight or 1)
		if r <= acc then return n end
	end
	return names[#names]
end

function NpcLife:_startGesture(entry, name, now)
	local g = entry.pack.gestures[name]
	if not g then return false end
	entry.gesture = { def = g, name = name, started = now }
	entry.drawIndex = entry.drawIndex + 1
	local cd = g.cooldown or { 10, 20 }
	entry.cooldowns[name] = now + (g.duration or 1) + self.M.Motion.draw(entry.seed, entry.drawIndex, cd[1], cd[2])
	return true
end

function NpcLife:_update(entry, dt, now)
	local M = self.M
	local Motion = M.Motion
	local band = entry.band
	if not band then return end
	entry.frameCounter = entry.frameCounter + 1
	local pack = entry.pack

	-- tracking weight (talking = 1, prompt shown = promptWeight, else 0)
	local wantTrack = 0
	local head = self.deps.playerHead()
	if head and entry.lod.trackRange > 0 then
		local d = (head - entry.root.Position).Magnitude
		if d <= entry.lod.trackRange then
			if entry.talking then wantTrack = 1 elseif entry.promptShown then wantTrack = pack.track and pack.track.promptWeight or 0 end
		end
	end
	entry.trackWeight = Motion.smooth(entry.trackWeight, wantTrack, dt, TRACK_RAMP / 3)
	if entry.trackWeight > 0.001 and head and pack.track then
		local turn, bend = Motion.aimAngles(entry.root.CFrame, entry.root.Position + Vector3.new(0, M.RigSpec.Root.HeadOffset, 0), head)
		turn = Motion.clamp(turn, -pack.track.maxTurn, pack.track.maxTurn)
		bend = Motion.clamp(bend, -pack.track.maxBend, pack.track.maxBend)
		entry.aimTurn = Motion.smooth(entry.aimTurn, turn, dt, pack.track.smooth or 0.25)
		entry.aimBend = Motion.smooth(entry.aimBend, bend, dt, pack.track.smooth or 0.25)
	end

	-- greet / gestures (scheduling runs every frame; pose evaluation is rate-limited below)
	if entry.gesture then
		local elapsed = now - entry.gesture.started
		if elapsed >= (entry.gesture.def.duration or 0) and not entry.gesture.def.hold then entry.gesture = nil end
	end
	if not entry.gesture then
		if entry.greetPending then
			entry.greetPending = false
			if pack.greet and (now - entry.lastGreet) >= GREET_COOLDOWN and self:_startGesture(entry, pack.greet, now) then
				entry.lastGreet = now
			end
		elseif entry.talking and pack.talk then
			if now >= entry.nextTalkGesture then
				local name = self:_pickGesture(entry, now, true)
				if name then self:_startGesture(entry, name, now) end
				entry.drawIndex = entry.drawIndex + 1
				entry.nextTalkGesture = now + Motion.draw(entry.seed, entry.drawIndex, pack.talk.every[1], pack.talk.every[2])
			end
		elseif band.gestures and entry.dist <= (entry.lod.gestureRange or 0) then
			local name = self:_pickGesture(entry, now, false)
			if name then self:_startGesture(entry, name, now) end
		end
	end

	-- pose (rate-limited by the band)
	if entry.frameCounter % (band.procEvery or 1) == 0 then
		local acc = {}
		local t = now
		-- idle layers
		for _, layer in pairs(pack.idle) do
			local usable = true
			if layer.optional then
				usable = false
				for _, ef in ipairs(layer.effects) do if entry.joints[ef.joint] then usable = true end end
			end
			if usable then
				local v = Motion.evalLayer(layer, t, entry.phase)
				local w = 1
				if (layer.priority or 0) >= 1 then w = 1 - entry.trackWeight end   -- look layers yield to tracking
				if w > 0.001 and v ~= 0 then
					for _, ef in ipairs(layer.effects) do
						local skip = ef.unlessPlanted and entry.planted[ef.unlessPlanted]
						if not skip then Motion.accumulate(acc, ef.joint, ef.axis, v * (ef.scale or 1) * w) end
					end
					if layer.plantedCounter then
						if entry.planted.RightHand then Motion.accumulate(acc, "RightShoulder", "spread", -v * w) end
						if entry.planted.LeftHand then Motion.accumulate(acc, "LeftShoulder", "spread", -v * w) end
					end
				end
			end
		end
		-- gesture
		if entry.gesture then
			local g = entry.gesture
			local elapsed = now - g.started
			local vals = Motion.evalGesture(g.def, elapsed)
			local w = gestureWeight(elapsed, g.def.duration or 1)
			for joint, axes in pairs(vals) do
				for axis, v in pairs(axes) do Motion.accumulate(acc, joint, axis, v * w) end
			end
		end
		-- tracking
		if entry.trackWeight > 0.001 then
			local target = (pack.track and pack.track.target) or "Neck"
			Motion.accumulate(acc, target, "turn", entry.aimTurn * entry.trackWeight)
			Motion.accumulate(acc, target, "bend", entry.aimBend * entry.trackWeight)
			if entry.joints.Waist then Motion.accumulate(acc, "Waist", "turn", entry.aimTurn * 0.3 * entry.trackWeight) end
		end
		self:_write(entry, acc)
	end

	-- face (blink / gaze / talk) -- timers, cheap
	if entry.face and band.face then self:_face(entry, now, head) end
end

function NpcLife:_write(entry, acc)
	local Motion = self.M.Motion
	local written = {}
	for jointName, axes in pairs(acc) do
		if jointName == "__model" then
			local up = axes.up or 0
			entry.model:PivotTo(entry.basePivot * CFrame.new(0, up, 0))
			entry.dirtyModel = true
			self.stats.writes = self.stats.writes + 1
		else
			local j = entry.joints[jointName]
			if j then
				local off = Motion.offsetFor(j.class, j.side, axes)
				j.joint.C0 = off and (j.rest * off) or j.rest
				written[jointName] = true
				self.stats.writes = self.stats.writes + 1
			end
		end
	end
	-- joints that moved last frame but not this one go back to rest (never accumulate)
	for jointName in pairs(entry.lastWritten) do
		if not written[jointName] then
			local j = entry.joints[jointName]
			if j then j.joint.C0 = j.rest end
		end
	end
	if entry.dirtyModel and not acc.__model then
		entry.model:PivotTo(entry.basePivot)
		entry.dirtyModel = false
	end
	entry.lastWritten = written
end

function NpcLife:_face(entry, now, head)
	local M = self.M
	local f = entry.face
	local FC = M.FaceConfig
	-- blink
	if now >= entry.nextBlink then
		entry.drawIndex = entry.drawIndex + 1
		entry.nextBlink = now + M.Motion.draw(entry.seed, entry.drawIndex, FC.Blink.every[1], FC.Blink.every[2])
		entry.blinkUntil = now + FC.Blink.duration
		for _, n in ipairs({ "EyeL", "EyeR" }) do
			local p = f.parts[n]; if p then local s = p.Size; p.Size = Vector3.new(s.X, FC.Closed.eyeSizeY, s.Z) end
		end
		for _, n in ipairs({ "PupilL", "PupilR" }) do
			local p = f.parts[n]; if p then p.Size = Vector3.new(FC.Closed.pupilSize, FC.Closed.pupilSize, p.Size.Z) end
		end
	elseif entry.blinkUntil > 0 and now >= entry.blinkUntil then
		entry.blinkUntil = 0
		for _, n in ipairs({ "EyeL", "EyeR", "PupilL", "PupilR" }) do
			local p, r = f.parts[n], f.rest[n]; if p and r then p.Size = r.size end
		end
	end
	-- gaze (10 Hz)
	if now >= entry.nextGaze then
		entry.nextGaze = now + 1 / FC.Gaze.hz
		local dx, dy = 0, 0
		if head and entry.dist <= FC.Gaze.range then
			local root = entry.root.CFrame
			local d = root:VectorToObjectSpace(head - entry.root.Position)
			local mag = d.Magnitude
			if mag > 0 and (-d.Z / mag) > FC.Gaze.dot then
				dx = M.Motion.clamp(d.X / mag, -1, 1) * FC.Gaze.x
				dy = M.Motion.clamp(d.Y / mag, -1, 1) * FC.Gaze.y
			end
		end
		for _, n in ipairs({ "PupilL", "PupilR" }) do
			local j, r = f.joints[n], f.rest[n]
			if j and r then j.C0 = r.c0 * CFrame.new(dx, dy, 0) end
		end
	end
	-- talk: mouth height oscillates in bursts
	local mouth = f.parts.Mouth
	if mouth and f.rest.Mouth then
		if entry.talking then
			-- bursts of movement (1.5-2.5 s) with short rests between, like a typewriter line
			if now >= entry.mouthRestUntil then
				entry.drawIndex = entry.drawIndex + 1
				entry.mouthBurstUntil = now + M.Motion.draw(entry.seed, entry.drawIndex, FC.Talking.burst[1], FC.Talking.burst[2])
				entry.mouthRestUntil = entry.mouthBurstUntil + FC.Talking.rest
			end
			if now < entry.mouthBurstUntil then
				local hz = FC.Talking.hz[1] + (FC.Talking.hz[2] - FC.Talking.hz[1]) * M.Motion.hash01(math.floor(now * 2))
				local a = 0.5 + 0.5 * math.sin(now * hz * math.pi * 2)
				local lo, hi = FC.Talking.mouthSizeYRange[1], FC.Talking.mouthSizeYRange[2]
				local rs = f.rest.Mouth.size
				mouth.Size = Vector3.new(rs.X * FC.Talking.mouthSizeXScale, lo + (hi - lo) * a, rs.Z)
				entry.mouthOpen = true
			elseif entry.mouthOpen then
				mouth.Size = f.rest.Mouth.size
				entry.mouthOpen = false
			end
		elseif entry.mouthOpen then
			mouth.Size = f.rest.Mouth.size
			entry.mouthOpen = false
		end
	end
end

-- ===== hooks (zero edits to locked files: driven by prompt + dialogue signals) =====
function NpcLife:onPromptShown(prompt)
	local e = entryForPrompt(self, prompt)
	if not e then return end
	e.promptShown = true
	e.greetPending = true
end

function NpcLife:onPromptHidden(prompt)
	local e = entryForPrompt(self, prompt)
	if e then e.promptShown = false end
end

function NpcLife:onPromptTriggered(prompt, now)
	local e = entryForPrompt(self, prompt)
	if not e then return end
	self.lastTrigger.entry = e
	self.lastTrigger.at = now
	if self.dialogVisible then self:_setTalking(e, true, now) end
end

function NpcLife:onDialogVisible(visible, now)
	self.dialogVisible = visible
	if visible then
		local e = self.lastTrigger.entry
		if e and (now - self.lastTrigger.at) <= 1.5 then self:_setTalking(e, true, now) end
	elseif self.talkingEntry then
		self:_setTalking(self.talkingEntry, false, now)
	end
end

function NpcLife:_setTalking(entry, on, now)
	if on then
		if self.talkingEntry and self.talkingEntry ~= entry then self:_setTalking(self.talkingEntry, false, now) end
		entry.talking = true
		entry.talkingSince = now
		entry.nextTalkGesture = now + 1.0
		self.talkingEntry = entry
	else
		entry.talking = false
		if self.talkingEntry == entry then self.talkingEntry = nil end
		if entry.face and entry.face.parts.Mouth and entry.face.rest.Mouth then
			entry.face.parts.Mouth.Size = entry.face.rest.Mouth.size
			entry.mouthOpen = false
		end
	end
end

-- external face interface (D-3): quest/world lanes set the attribute; this is
-- the same path the attribute signal takes, exposed for tests and tools.
function NpcLife:setFace(model, exprId)
	local e = self.entries[model]
	if not e or not e.face then return false end
	self:_applyFace(e, exprId)
	return true
end

return NpcLife
