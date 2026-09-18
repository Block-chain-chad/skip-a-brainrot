--!strict
-- CatchCinematic.BrainrotRig -- the creature. THE MONEY SHOT.
--
-- Clone from ReplicatedStorage.BrainrotModels, neuter (PullCeremony's loop,
-- verbatim, plus Massless -- this rig's clone sits live in world space rather
-- than riding the camera like PullCeremony's does, so it must never contribute
-- mass or collide with anything), scale via MassiveEmergence's exact fit math
-- (reused verbatim, per the brief):
--   hs = clamp(template:GetAttribute("HeightScale") or 1, 0.7, 1.5)
--   fit = min((6.0*hs)/extents.Y, 9.5/max(width,0.01)) * Sizes.Scale(size)
--   model:ScaleTo(model:GetScale() * fit)      -- ScaleTo is ABSOLUTE, always factor-of-original
-- Silhouette colour is MassiveEmergence's, verbatim: Color3.fromRGB(6, 8, 12).
--
-- POSE MATH -- adapted, not copy-pasted, from MassiveEmergence's inline placeAt:
-- MassiveEmergence's placeAt(pos, yaw) is a per-frame RenderStepped closure that
-- rotates the model's CURRENT pivot by `yaw` every call, so the total rotation
-- compounds across frames (fine for a fire-and-forget cutscene, but the OPPOSITE
-- of "setRise(alpha) is a pure function of alpha" -- calling it twice with the
-- same alpha must yield the same pose). So here the pivot/bounding-box-centre
-- offset is captured ONCE at build time (_pivot0/_localOffset, at yaw=0) and
-- every pose call recomputes the model's CFrame from scratch via poseCFrame():
-- pos and yaw both go in, the exact same pivot CFrame comes out, every time.
-- The below/above targets and the quint-ease-out rise curve are MassiveEmergence's
-- own numbers, unchanged.
--
-- Model handling per the brief: all BaseParts Anchored + CanCollide/CanQuery/
-- CanTouch false + Massless; PivotTo for all movement (never welds); ScaleTo is
-- ABSOLUTE (model:GetScale() * factor, never a bare factor).
--
-- .new() calls stageBelow() once at the end of construction, so a rig is ALWAYS
-- fully staged (silhouette-black, sunk below the surface) the instant it exists
-- -- there is no frame where a freshly-cloned model could flash its real colours
-- at some arbitrary ReplicatedStorage-inherited CFrame before the Sequencer gets
-- a chance to pose it. stageBelow() itself stays idempotent/re-callable (the
-- Sequencer's documented staging beat).
--
-- COLOR/SIZE ANIMATION -- HAND-LERPED, NOT TWEENSERVICE, DESPITE THE BRIEF'S
-- "Color is sanctioned" note: TweenService progress read back as stalled during
-- this module's verification session (Studio was backgrounded behind another
-- window and render-throttled at the time -- not a place bug). revealColors()
-- and eyeTwitch() hand-lerp instead (task.spawn stepping loop + task.wait(),
-- the same render-throttle-safe pattern PostFX/AudioBus already use for their
-- own hand-lerped properties) so a reveal never silently depends on the editor
-- window being foregrounded.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Sizes = require(ReplicatedStorage.Modules.SizeConfig)
-- THE MUTATION LOOK (spec S9): the same MutationFX.apply the spawner paints a placed
-- brainrot with, on this display clone. Fail-soft: without it a mutated catch simply
-- shows the plain model, exactly as before 2026-09-17.
local okFX, MutationFX = pcall(function()
	return require(ReplicatedStorage.Modules.MutationFX)
end)
if not okFX or type(MutationFX) ~= "table" or type(MutationFX.apply) ~= "function" then
	warn("[BrainrotRig] MutationFX unavailable (" .. tostring(MutationFX) .. "); cuts show plain models")
	MutationFX = nil
end

local SILHOUETTE_COLOR = Color3.fromRGB(6, 8, 12)
local EYE_TWITCH_SCALE = 1.15
local EYE_TWITCH_SECONDS = 0.18
local BREACH_ABOVE_FRAC = 1 / 3 -- fraction of model height poking above the surface at breachPose()
local STREAK_MIN_SCALE = 0.03 -- never literally zero -- ScaleTo(0) is undefined behaviour

local BrainrotRig = {}
BrainrotRig.__index = BrainrotRig

export type Rig = typeof(setmetatable(
	{} :: {
		_stage: Folder,
		_name: string,
		_size: string,
		_splashPos: Vector3,
		_model: Model,
		_pivot0: CFrame,
		_localOffset: Vector3,
		_finalExtents: Vector3,
		_belowPos: Vector3,
		_risePos: Vector3,
		_originalColor: { [BasePart]: Color3 },
		_originalTint: { [Instance]: Color3 },
		_mutation: string?,
		_mutationHeld: { { inst: Instance, prop: string, value: any } },
		_mutationShown: boolean,
		_colorsStored: boolean,
		_riseAlpha: number,
		_baseYaw: number,
		_angryEyes: { [BasePart]: { color: Color3, material: Enum.Material } }?,
		_colorGen: number,
		_eyeGen: number,
		_breached: boolean,
		_destroyed: boolean,
	},
	BrainrotRig
))

-- MutationFX on the display clone (spec S9), applied AFTER the rig geometry is read so
-- a halo or ground ring never changes the extents the framing and rise maths use.
-- Its colour/material shifts land on the parts themselves -- stageBelow() then stores
-- THOSE as the originals, so the silhouette lerps up to the mutated colours. Everything
-- it ADDS (emitters, lights, highlight, beams, halo/ring/shell parts, textures) is held
-- back -- disabled or fully transparent -- and the MutationBody tag withheld, so nothing
-- glows through the water before the creature shows; revealColors() releases it all.
-- Returns the held (instance, property, value) triples to restore.
local function applyMutation(model: Model, mutation: string?): { { inst: Instance, prop: string, value: any } }
	local held: { { inst: Instance, prop: string, value: any } } = {}
	if not mutation or not MutationFX then
		return held
	end
	local before: { [Instance]: boolean } = {}
	for _, d in ipairs(model:GetDescendants()) do
		before[d] = true
	end
	local ok, err = pcall(MutationFX.apply, model, mutation)
	if not ok then
		warn("[BrainrotRig] MutationFX.apply failed for '" .. tostring(mutation) .. "': " .. tostring(err))
		return held
	end
	for _, d in ipairs(model:GetDescendants()) do
		if before[d] then
			continue
		end
		local a: any = d
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			table.insert(held, { inst = d, prop = "Transparency", value = d.Transparency })
			d.Transparency = 1
		elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Highlight") or d:IsA("Light") or d:IsA("Trail") then
			table.insert(held, { inst = d, prop = "Enabled", value = a.Enabled })
			a.Enabled = false
		elseif d:IsA("Decal") or d:IsA("Texture") then
			table.insert(held, { inst = d, prop = "Transparency", value = a.Transparency })
			a.Transparency = 1
		end
	end
	-- MutationMotionClient's handshake waits for the reveal too (it would otherwise
	-- animate -- and for some mutations recolour -- the silhouette)
	CollectionService:RemoveTag(model, "MutationBody")
	return held
end

-- Clone + neuter + fit-scale + parent into stage. Returns nil (all four values)
-- if the model name doesn't exist in BrainrotModels -- the ONE failure path both
-- .new() and swapModel() share, so "no model" fails soft identically either way.
local function buildModel(stage: Folder, name: string, size: string): (Model?, CFrame?, Vector3?, Vector3?)
	local modelFolder = ReplicatedStorage:FindFirstChild("BrainrotModels")
	local template = modelFolder and modelFolder:FindFirstChild(name)
	if not template or not template:IsA("Model") then
		return nil, nil, nil, nil
	end

	local model = template:Clone()
	local _, extents = model:GetBoundingBox()
	local hsRaw = template:GetAttribute("HeightScale")
	local hs = math.clamp((typeof(hsRaw) == "number" and hsRaw or 1) :: number, 0.7, 1.5)
	-- WidthScale mirrors BrainrotSpawner (see MIN_WIDTH_SHARE there). A long low
	-- creature otherwise always fills the whole 9.5 width budget, which made a tadpole
	-- rise out of the lake at the same size as a hammerhead. Default 1 = unchanged.
	local wsRaw = template:GetAttribute("WidthScale")
	local ws = math.clamp((typeof(wsRaw) == "number" and wsRaw or 1) :: number, 0.35, 1)
	local width = math.max(extents.X, extents.Z)
	local fit = math.min((6.0 * hs) / extents.Y, (9.5 * ws) / math.max(width, 0.01)) * Sizes.Scale(size)
	model:ScaleTo(model:GetScale() * fit)

	-- PullCeremony's neuter loop (ReplicatedStorage.Modules.PullCeremony), verbatim,
	-- plus Massless -- see module header.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		elseif d:IsA("Sound") then
			d.Looped = false
			d.Playing = false
		elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ProximityPrompt") or d:IsA("BillboardGui") then
			d:Destroy()
		end
	end

	model.Parent = stage
	local pivot0 = model:GetPivot()
	local cf, finalExtents = model:GetBoundingBox()
	local localOffset = pivot0:PointToObjectSpace(cf.Position)
	return model, pivot0, localOffset, finalExtents
end

-- Pure: same (pivot0, localOffset, pos, yaw) always yields the same CFrame. `pos`
-- is where the model's BOUNDING-BOX CENTRE should land (matches MassiveEmergence's
-- placeAt convention); `yaw` is an ABSOLUTE turn from the model's build-time
-- orientation (pivot0), not an increment on whatever the pivot currently holds.
local function poseCFrame(pivot0: CFrame, localOffset: Vector3, pos: Vector3, yaw: number): CFrame
	local rot = pivot0.Rotation * CFrame.Angles(0, yaw, 0)
	local worldOffset = rot:VectorToWorldSpace(localOffset)
	return CFrame.new(pos - worldOffset) * rot
end

function BrainrotRig.new(stage: Folder, name: string, size: string, splashPos: Vector3, mutation: string?): Rig?
	local model, pivot0, localOffset, finalExtents = buildModel(stage, name, size)
	if not model or not pivot0 or not localOffset or not finalExtents then
		return nil
	end
	local held = applyMutation(model, mutation)

	local self = setmetatable({
		_stage = stage,
		_name = name,
		_size = size,
		_splashPos = splashPos,
		_model = model,
		_pivot0 = pivot0,
		_localOffset = localOffset,
		_finalExtents = finalExtents,
		_belowPos = splashPos - Vector3.new(0, finalExtents.Y * 1.05, 0),
		_risePos = splashPos + Vector3.new(0, finalExtents.Y * 0.5 - finalExtents.Y * 0.08, 0),
		_originalColor = {} :: { [BasePart]: Color3 },
		_originalTint = {} :: { [Instance]: Color3 },
		_mutation = mutation,
		_mutationHeld = held,
		_mutationShown = false,
		_colorsStored = false,
		_riseAlpha = 0,
		_baseYaw = 0,
		_angryEyes = nil :: { [BasePart]: { color: Color3, material: Enum.Material } }?,
		_colorGen = 0,
		_eyeGen = 0,
		_breached = false,
		_descentStarted = false,
		_destroyed = false,
	}, BrainrotRig)
	local rig = (self :: any) :: Rig
	rig:stageBelow()
	return rig
end

function BrainrotRig:_placeAt(pos: Vector3, yaw: number)
	if self._destroyed then
		return
	end
	self._model:PivotTo(poseCFrame(self._pivot0, self._localOffset, pos, self._baseYaw + yaw))
end

-- Silhouette (store colours -- once, idempotently -- then paint rgb(6,8,12)) and
-- pivot fully below splashPos. Safe to call more than once: subsequent calls
-- repaint from the STORED originals (never re-capture already-black colour).
function BrainrotRig:stageBelow()
	if self._destroyed then
		return
	end
	if not self._colorsStored then
		for _, d in ipairs(self._model:GetDescendants()) do
			if d:IsA("BasePart") then
				self._originalColor[d] = d.Color
			-- DECALS TOO (2026-08-14): a Decal/Texture draws at full strength
			-- regardless of the part colour under it, so a model whose face is
			-- painted rather than modelled (Secret Pete since the v2 redesign)
			-- staged as a black body wearing a fully lit face -- the one thing
			-- the silhouette exists to hide. Color3 is a tint multiplier, so it
			-- blacks out and reveals on exactly the same curve.
			elseif d:IsA("Decal") or d:IsA("Texture") then
				self._originalTint[d] = (d :: any).Color3
			end
		end
		self._colorsStored = true
	end
	for part in pairs(self._originalColor) do
		if part.Parent then
			part.Color = SILHOUETTE_COLOR
		end
	end
	for decal in pairs(self._originalTint) do
		if decal.Parent then
			local art: any = decal
			art.Color3 = SILHOUETTE_COLOR
		end
	end
	self._riseAlpha = 0
	self._breached = false -- back to the initial silhouette state -- not breached (yet)
	self:_placeAt(self._belowPos, 0)
end

-- Pure function of alpha: pivot lerp below->full-rise-height + slow yaw. RETUNED
-- 2026-08-09: MassiveEmergence's quint-ease-out curve and its pi*1.25 total turn
-- are BOTH gone -- the curve is now a sine ease-in-out (the beast crawl) and the
-- turn a 0.6*pi part-turn (the aurafarm turn). See the inline notes below for the
-- owner direction behind each. Still a from-scratch recompute rather than a
-- literal copy of MassiveEmergence's accumulating RenderStepped closure -- see the
-- module header for why.
function BrainrotRig:setRise(alpha: number)
	if self._destroyed then
		return
	end
	alpha = math.clamp(alpha, 0, 1)
	self._riseAlpha = alpha
	-- RETUNED 2026-08-09 (owner feedback: "doesn't emerge slowly like a beast"):
	-- the original quint-ease-OUT burst up fast and settled, which read as a pop.
	-- Sine ease-in-out is the beast crawl -- slow shoulder out of the water, steady
	-- climb, gentle settle. Still pure in alpha.
	local e = 0.5 - 0.5 * math.cos(math.pi * alpha)
	local pos = self._belowPos:Lerp(self._risePos, e)
	-- 0.6*pi (was 1.25*pi): the aurafarm turn -- a slow, unbothered part-turn,
	-- not a runway spin (owner direction 2026-08-09).
	local yaw = alpha * math.pi * 0.6
	self:_placeAt(pos, yaw)
end

-- Pure function of alpha, the sky path: 0 = `fromHeight` studs ABOVE the rise pose,
-- 1 = the rise pose itself, with a 0.75-turn yaw and a sine ease-in-out. Used
-- forward for God's descent and backward (1 - alpha) for Massive God's ascension.
-- Reveals the colours on first use: a creature in a beam of light is never a
-- silhouette.
function BrainrotRig:setDescent(alpha: number, fromHeight: number)
	if self._destroyed then
		return
	end
	alpha = math.clamp(alpha, 0, 1)
	if not self._descentStarted then
		self._descentStarted = true
		self:revealColors(0.05)
	end
	self._riseAlpha = 1
	self._breached = true
	local e = 0.5 - 0.5 * math.cos(math.pi * alpha)
	local top = self._risePos + Vector3.new(0, fromHeight, 0)
	local pos = top:Lerp(self._risePos, e)
	self:_placeAt(pos, math.pi * 0.6 + alpha * math.pi * 1.5)
end

-- The setRise alpha whose EASED height equals breachPose's fixed pose, computed
-- from this instance's own numbers so the two can never drift apart. The rise
-- beat starts from here instead of 0 -- without this the creature visibly dunks
-- back underwater after the eruption and re-emerges (the discontinuity behind
-- the owner's "doesn't emerge" note).
function BrainrotRig:breachAlpha(): number
	if self._destroyed then
		return 0
	end
	local breachY = self._splashPos.Y + self._finalExtents.Y * (BREACH_ABOVE_FRAC - 0.5)
	local span = self._risePos.Y - self._belowPos.Y
	if span <= 0 then
		return 0
	end
	local e = math.clamp((breachY - self._belowPos.Y) / span, 0, 1)
	-- invert the sine ease: e = 0.5 - 0.5*cos(pi*a)  ->  a = acos(1 - 2e)/pi
	return math.acos(math.clamp(1 - 2 * e, -1, 1)) / math.pi
end

-- The swapModel guard's WRITER since the v2 retune. The eruption beat now drives
-- the emergence through setRise (0 -> breachAlpha) and never calls breachPose, so
-- _breached had no writer left on the main path and a post-eruption swapModel
-- could have silently rebuilt the creature mid-emergence. The Sequencer marks the
-- breach explicitly here instead, at the instant the dome bursts. Idempotent.
function BrainrotRig:markBreached()
	if self._destroyed then
		return
	end
	self._breached = true
end

-- The eruption instant: head/upper-third above the surface. A fixed pose, not
-- part of the setRise(alpha) timeline (the "rise" beat that follows re-poses via
-- setRise from 0 again -- breachPose is deliberately a separate, discrete beat).
-- OFF THE MAIN PATH since the 2026-08-09 retune: nothing calls it any more (the
-- eruption drives setRise); kept because breachAlpha() is defined against its pose.
function BrainrotRig:breachPose()
	if self._destroyed then
		return
	end
	self._breached = true -- past this point, swapModel is a no-op -- see swapModel's guard
	local centerY = self._splashPos.Y + self._finalExtents.Y * (BREACH_ABOVE_FRAC - 0.5)
	local pos = Vector3.new(self._splashPos.X, centerY, self._splashPos.Z)
	self:_placeAt(pos, 0)
end

-- Hand-lerp stored colours back (see module header: render-throttle-safe,
-- doesn't depend on TweenService progressing). Generation counter so a second
-- revealColors() call cleanly supersedes an in-flight one instead of two loops
-- fighting over the same parts.
-- Release the held MutationFX additions and hand the model to MutationMotionClient.
-- Idempotent; part of every colour reveal, so every cut gets it on its reveal beat.
function BrainrotRig:_showMutation()
	if self._destroyed or self._mutationShown then
		return
	end
	self._mutationShown = true
	for _, h in ipairs(self._mutationHeld) do
		if h.inst.Parent then
			local a: any = h.inst
			a[h.prop] = h.value
		end
	end
	if self._mutation and MutationFX then
		CollectionService:AddTag(self._model, "MutationBody")
	end
end

-- The confirmed grant can carry a different mutation from the flight-time roll (a
-- reveal-time fallback swap). Rebuilds the staged model with the confirmed look --
-- MutationFX recolours are permanent on an instance, so a fresh clone is the only
-- honest way -- and is a no-op once the creature has breached, like swapModel.
function BrainrotRig:setMutation(mutation: string?): boolean
	if self._destroyed or mutation == self._mutation then
		return false
	end
	self._mutation = mutation
	return self:swapModel(self._name)
end

function BrainrotRig:revealColors(seconds: number)
	if self._destroyed then
		return
	end
	self:_showMutation()
	seconds = math.max(seconds, 0.05)
	self._colorGen += 1
	local myGen = self._colorGen
	local targets = self._originalColor
	local starts: { [BasePart]: Color3 } = {}
	for part in pairs(targets) do
		starts[part] = part.Color
	end
	local tintTargets = self._originalTint
	local tintStarts: { [Instance]: Color3 } = {}
	for decal in pairs(tintTargets) do
		local art: any = decal
		tintStarts[decal] = art.Color3
	end

	task.spawn(function()
		local t0 = os.clock()
		while self._colorGen == myGen and not self._destroyed do
			local a = math.clamp((os.clock() - t0) / seconds, 0, 1)
			local e = 1 - (1 - a) ^ 3
			for part, target in pairs(targets) do
				-- angry eyes hold their red through the reveal; calmEyes restores them
				if part.Parent and not (self._angryEyes and self._angryEyes[part]) then
					local s = starts[part] or target
					part.Color = s:Lerp(target, e)
				end
			end
			for decal, target in pairs(tintTargets) do
				if decal.Parent then
					-- bound to a local first: a statement STARTING with "(" is parsed as a
					-- call on the previous line's expression, which is a load-time syntax error
					local art: any = decal
					art.Color3 = (tintStarts[decal] or target):Lerp(target, e)
				end
			end
			if a >= 1 then
				break
			end
			task.wait()
		end
	end)
end

function BrainrotRig:_findEyePart(): BasePart?
	if self._destroyed then
		return nil
	end
	for _, d in ipairs(self._model:GetDescendants()) do
		if d:IsA("BasePart") and string.find(string.lower(d.Name), "eye") then
			return d
		end
	end
	return nil
end

-- FACING (owner 2026-08-09: "rise slowly facing the player"): a constant yaw offset
-- applied under every pose, so the rise's slow turn LANDS square on whatever the
-- Sequencer aimed at. Pure state -- the next _placeAt picks it up.
function BrainrotRig:setFacing(baseYaw: number)
	if self._destroyed then
		return
	end
	self._baseYaw = baseYaw
end

-- ANGRY EYES (same owner note): every part whose name contains "eye" goes hot
-- glowing red for the emergence; calmEyes restores the stored originals exactly.
-- Fail-soft: a model with no eye parts is a clean no-op both ways -- and RETURNS
-- FALSE, which is the whole point of the return value: 170 of the 191 models in
-- BrainrotModels have no part named "eye", so on most catches the red never showed
-- at all. The caller needs to know the angry read did not land so it can paint one
-- somewhere the model definitely has (the Sequencer reddens the aura rim instead).
-- Idempotent: a second call re-reports the first call's answer, never re-captures.
function BrainrotRig:angryEyes(): boolean
	if self._destroyed then
		return false
	end
	if self._angryEyes then
		return next(self._angryEyes) ~= nil
	end
	local store: { [BasePart]: { color: Color3, material: Enum.Material } } = {}
	for _, d in ipairs(self._model:GetDescendants()) do
		if d:IsA("BasePart") and string.find(string.lower(d.Name), "eye") then
			store[d] = { color = d.Color, material = d.Material }
			d.Color = Color3.fromRGB(255, 45, 25)
			d.Material = Enum.Material.Neon
		end
	end
	self._angryEyes = store
	return next(store) ~= nil
end

function BrainrotRig:calmEyes()
	local store = self._angryEyes
	if not store then
		return
	end
	self._angryEyes = nil
	for part, orig in pairs(store) do
		if part.Parent then
			part.Color = self._originalColor[part] or orig.color
			part.Material = orig.material
		end
	end
end

-- Briefly hand-lerp an eye part's Size 1.15x and back (see module header: no
-- TweenService in this module). No-op if the model has no part named "eye"
-- (case-insensitive substring match).
function BrainrotRig:eyeTwitch()
	if self._destroyed then
		return
	end
	local eyePart = self:_findEyePart()
	if not eyePart then
		return
	end
	self._eyeGen += 1
	local myGen = self._eyeGen
	local baseSize = eyePart.Size
	local upSize = baseSize * EYE_TWITCH_SCALE
	local half = EYE_TWITCH_SECONDS * 0.5

	task.spawn(function()
		local t0 = os.clock()
		while self._eyeGen == myGen and not self._destroyed and eyePart.Parent do
			local a = math.clamp((os.clock() - t0) / half, 0, 1)
			eyePart.Size = baseSize:Lerp(upSize, a)
			if a >= 1 then
				break
			end
			task.wait()
		end
		if self._eyeGen ~= myGen or self._destroyed or not eyePart.Parent then
			return
		end
		local t1 = os.clock()
		while self._eyeGen == myGen and not self._destroyed and eyePart.Parent do
			local a = math.clamp((os.clock() - t1) / half, 0, 1)
			eyePart.Size = upSize:Lerp(baseSize, a)
			if a >= 1 then
				break
			end
			task.wait()
		end
	end)
end

-- The fitted model's world-space extents, captured once at build time (and refreshed
-- by swapModel). Published because the Sequencer needs them for the hero framing
-- distance, the dread dome radius and WaterFX:erupt's column size -- reaching into
-- _finalExtents from outside was legal (it is in the exported Rig type) but left the
-- geometry contract undocumented.
function BrainrotRig:extents(): Vector3
	return self._finalExtents
end

-- The live clone. WaterFX:cascade needs the Model itself to hang emitters off, and
-- swapModel replaces it, so callers must re-read rather than cache across a swap.
function BrainrotRig:model(): Model
	return self._model
end

-- Current bounding-box top centre -- RockRig's second-bonk target.
function BrainrotRig:headTop(): Vector3
	if self._destroyed then
		return self._splashPos
	end
	local cf, ext = self._model:GetBoundingBox()
	return cf.Position + Vector3.new(0, ext.Y / 2, 0)
end

-- Scale the model down while lerping toward the camera-ray of target2D (a
-- viewport-fraction Vector2, 0..1 on each axis), then hide it. Self-driving
-- (task.spawn stepping loop, per the hard rule -- Model:ScaleTo/PivotTo are not
-- TweenService-able properties regardless). Ends with the model destroyed --
-- "hidden" and "stage empty of it" in one step -- and `done` fired after.
function BrainrotRig:compressAndStreak(target2D: Vector2, seconds: number, done: (() -> ())?)
	if self._destroyed then
		if done then
			task.spawn(done)
		end
		return
	end
	seconds = math.max(seconds, 0.05)
	local model = self._model
	local startPos = model:GetPivot().Position
	local startScale = model:GetScale()
	-- The model's ACTUAL current rotation, not a reconstruction from _riseAlpha:
	-- breachPose() poses at yaw=0 without touching _riseAlpha, so a stale
	-- pivot0/riseAlpha recompute would snap rotation on breach -> compress. Reading
	-- the live pivot is correct regardless of which pose call happened last.
	local lockedRotation = model:GetPivot().Rotation

	local targetPos = startPos
	local cam = Workspace.CurrentCamera
	if cam then
		local vs = cam.ViewportSize
		local sx = math.clamp(target2D.X, 0, 1) * vs.X
		local sy = math.clamp(target2D.Y, 0, 1) * vs.Y
		local ok, ray = pcall(function()
			return cam:ViewportPointToRay(sx, sy)
		end)
		if ok and ray then
			local dist = (startPos - cam.CFrame.Position).Magnitude
			targetPos = ray.Origin + ray.Direction.Unit * dist
		end
	end

	task.spawn(function()
		local t0 = os.clock()
		while not self._destroyed do
			local a = math.clamp((os.clock() - t0) / seconds, 0, 1)
			local e = a * a * a -- cubic ease-in: accelerating streak toward the camera
			local pos = startPos:Lerp(targetPos, e)
			local scaleFactor = math.max(1 - (1 - STREAK_MIN_SCALE) * e, STREAK_MIN_SCALE)
			if model.Parent then
				model:PivotTo(CFrame.new(pos) * lockedRotation)
				pcall(function()
					model:ScaleTo(startScale * scaleFactor)
				end)
			end
			if a >= 1 then
				break
			end
			task.wait()
		end
		if not self._destroyed then
			self._destroyed = true
			self._colorGen += 1
			self._eyeGen += 1
			if model.Parent then
				model:Destroy()
			end
		end
		if done then
			pcall(done)
		end
	end)
end

-- Pre-eruption only: rebuild at the SAME rise alpha (covers the reveal-time
-- fallback swap). ENFORCED, not just documented: a no-op (warn + return false)
-- once breachPose() has run (_breached), so a post-eruption swap can never
-- silently rebuild the creature mid-emergence. Builds the replacement FIRST --
-- if the new name doesn't resolve, the old model is left completely untouched
-- and this returns false. Exactly one model lives in the stage at any time
-- either way.
function BrainrotRig:swapModel(newName: string): boolean
	if self._destroyed then
		return false
	end
	if self._breached then
		warn("[BrainrotRig] swapModel('" .. newName .. "') ignored: already past breachPose()")
		return false
	end
	local newModel, pivot0, localOffset, finalExtents = buildModel(self._stage, newName, self._size)
	if not newModel or not pivot0 or not localOffset or not finalExtents then
		return false
	end

	local oldModel = self._model
	local preservedAlpha = self._riseAlpha

	self._mutationHeld = applyMutation(newModel, self._mutation)
	self._mutationShown = false
	self._model = newModel
	self._pivot0 = pivot0
	self._localOffset = localOffset
	self._finalExtents = finalExtents
	self._belowPos = self._splashPos - Vector3.new(0, finalExtents.Y * 1.05, 0)
	self._risePos = self._splashPos + Vector3.new(0, finalExtents.Y * 0.5 - finalExtents.Y * 0.08, 0)
	self._name = newName
	self._originalColor = {}
	self._originalTint = {}
	self._colorsStored = false
	-- The OLD model's eye parts are about to be destroyed: keeping their keys would
	-- leave revealColors skipping dead parts and calmEyes writing to them.
	self._angryEyes = nil

	if oldModel.Parent then
		oldModel:Destroy()
	end

	self:stageBelow() -- paints black + captures colours for the NEW model
	self:setRise(preservedAlpha) -- restore rise progress on the new model
	return true
end

function BrainrotRig:cleanup()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._colorGen += 1
	self._eyeGen += 1
	if self._model and self._model.Parent then
		self._model:Destroy()
	end
end

return BrainrotRig
