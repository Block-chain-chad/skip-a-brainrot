-- MutationMotionClient: the ONE animation driver for every mutated brainrot in
-- view, plus distance LOD. Counterpart of MutationFX (which builds only static
-- instances) -- see its header for the division of labour.
--
-- Same discipline as BrainrotIdleClient and UIKit.Builders' ring driver: a
-- single Heartbeat, a registry pruned when instances die, and everything this
-- script does is LOCAL-ONLY COSMETICS on replicated instances (colour, light
-- brightness, the CFrame of anchored decor parts) -- the server never hears
-- about any of it.
--
-- LOD (the 60-stud test from the design handoff, plus engine budgets):
--   < 60 studs   full stack animates
--   > 75 studs   animation stops (hysteresis so the boundary never flickers)
--   > 95 studs   emitters + highlights disabled entirely
--   Highlights   hard-capped to the nearest 20 (engine draws ~31 max, and the
--                catch reveal / ceremony need headroom)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Visuals = require(ReplicatedStorage.Modules.MutationVisuals)

local ANIMATE_IN = 60
local ANIMATE_OUT = 75
local EFFECTS_OUT = 95
local HIGHLIGHT_BUDGET = 20
local SCAN_EVERY = 0.4

local player = Players.LocalPlayer

local tracked = {} -- [model] = state
local clock = 0

local function hueShift(c, delta)
	local h, s, v = c:ToHSV()
	return Color3.fromHSV((h + delta) % 1, s, v)
end

local function enter(model)
	if tracked[model] then return end
	local name = model:GetAttribute("Mutation")
	local v = name and Visuals.For(name)
	if not v then return end
	local state = {
		v = v,
		phase = math.random() * 10, -- desync neighbours so a row never pulses in lockstep
		near = false,
		effectsOn = true,
		highlight = model:FindFirstChild("MutationFXHighlight"),
		light = model:FindFirstChild("MutationFXLight", true),
		halo = model:FindFirstChild("MutationFXHalo"),
		ring = model:FindFirstChild("MutationFXRing"),
		groundRing = model:FindFirstChild("MutationFXGroundRing"),
		groundDecal = model:FindFirstChild("MutationFXGroundDecal"),
		ringBase = nil,
		haloBase = nil,
		beams = nil, -- Electric limb beams, created lazily in range
		lastBeamStep = 0,
		lastStrobe = 0,
	}
	if state.halo then state.haloBase = state.halo.CFrame end
	if state.ring then state.ringBase = state.ring.CFrame end
	if state.groundRing then state.groundRingBase = state.groundRing.CFrame end
	if state.groundDecal then
		state.groundDecalBase = state.groundDecal.Size
		state.groundDecalFace = state.groundDecal:FindFirstChild("MutationFXGroundDecalFace")
	end
	tracked[model] = state
end

local function leave(model)
	local st = tracked[model]
	if not st then return end
	-- st.beams holds {beam, a0, a1} TABLES, not instances -- calling Destroy on
	-- the table was a crash-per-scan storm the first time an Electric body
	-- despawned (found in the phase-2 verify round; the error also aborted the
	-- scan before untracking, so it repeated forever). Destroy the members.
	-- (Inline rather than dropElectricBeams: that local is declared below this
	-- function, so it is not in scope here.)
	if st.beams then
		for _, e in ipairs(st.beams) do
			if e.beam then e.beam:Destroy() end
			if e.a0 then e.a0:Destroy() end
			if e.a1 then e.a1:Destroy() end
		end
		st.beams = nil
	end
	tracked[model] = nil
end

-- Electric only: client-local beams arcing limb to limb, re-targeted every
-- beamRestep seconds. Created in range, destroyed out of range.
--
-- REWORKED 2026-08-15 (owner: "make the electric and aurora mutation look way
-- better"). Three separate reasons nobody could see these:
--   * the count was hardcoded `for i = 1, 2`, so motion.limbBeams was read by
--     the caller as a boolean and its VALUE never did anything;
--   * Width0 was a flat 0.12 studs -- a hairline against a 9-stud body -- and
--     did not scale with the model, so bigger creatures showed less;
--   * both attachments sat at their part's ORIGIN, i.e. its centre, so an arc
--     between two limbs ran THROUGH the body and was occluded for most of its
--     length. perchOutside now pushes each end onto the outside of its part,
--     facing away from the model centre, so the arc travels in open air.
local function perchOutside(att, part, centre)
	att.Parent = part
	local away = part.Position - centre
	if away.Magnitude < 0.05 then away = Vector3.new(0, 1, 0) end
	local reach = math.max(part.Size.X, part.Size.Y, part.Size.Z) * 0.5 + 0.35
	att.WorldPosition = part.Position + away.Unit * reach
end

local function ensureElectricBeams(model, st)
	if st.beams then return end
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:sub(1, 10) ~= "MutationFX" then parts[#parts + 1] = d end
	end
	if #parts < 2 then return end
	st.beamParts = parts

	local cf, size
	if model:IsA("BasePart") then cf, size = model.CFrame, model.Size else cf, size = model:GetBoundingBox() end
	st.beamCentre = cf.Position
	st.beamWidth = math.max(math.max(size.X, size.Y) * 0.055, 0.22)
	st.beamCurve = math.max(size.X, size.Y) * 0.28

	local count = math.clamp(tonumber(st.v.motion and st.v.motion.limbBeams) or 2, 1, 12)
	st.beams = {}
	for i = 1, count do
		local a0 = Instance.new("Attachment")
		a0.Name = "MutationFXArcA"
		perchOutside(a0, parts[math.random(#parts)], st.beamCentre)
		local a1 = Instance.new("Attachment")
		a1.Name = "MutationFXArcB"
		perchOutside(a1, parts[math.random(#parts)], st.beamCentre)
		local b = Instance.new("Beam")
		b.Name = "MutationFXArc"
		b.Attachment0 = a0
		b.Attachment1 = a1
		-- hot core to cool tip, so it reads as current rather than a cyan ribbon
		b.Color = ColorSequence.new(st.v.palette.primary, st.v.palette.secondary)
		b.Width0 = st.beamWidth
		b.Width1 = st.beamWidth * 0.35
		b.FaceCamera = true
		b.LightEmission = 1
		b.Transparency = NumberSequence.new(0.08)
		b.CurveSize0 = (math.random() * 2 - 1) * st.beamCurve
		b.CurveSize1 = (math.random() * 2 - 1) * st.beamCurve
		b.Parent = a0
		st.beams[i] = { beam = b, a0 = a0, a1 = a1 }
	end
end

local function restepElectric(st)
	if not (st.beams and st.beamParts) then return end
	for _, e in ipairs(st.beams) do
		local p0 = st.beamParts[math.random(#st.beamParts)]
		local p1 = st.beamParts[math.random(#st.beamParts)]
		if p0.Parent and p1.Parent then
			perchOutside(e.a0, p0, st.beamCentre or p0.Position)
			perchOutside(e.a1, p1, st.beamCentre or p1.Position)
			e.beam.CurveSize0 = (math.random() * 2 - 1) * (st.beamCurve or 2)
			e.beam.CurveSize1 = (math.random() * 2 - 1) * (st.beamCurve or 2)
			e.beam.Enabled = math.random() > 0.15
		end
	end
end

local function dropElectricBeams(st)
	if st.beams then
		for _, e in ipairs(st.beams) do
			e.beam:Destroy()
			e.a0:Destroy()
			e.a1:Destroy()
		end
		st.beams = nil
		st.beamParts = nil
	end
end

-- Plate hooks (nameplates carry a "MutationPill" frame; absent = nothing to do)
local function plateOf(model)
	local bg = model:FindFirstChildOfClass("BillboardGui")
	return bg and bg:FindFirstChild("MutationPill", true)
end

----------------------------------------------------------------- LOD scan
local lastScan = 0
local function scan()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local eye = cam.CFrame.Position

	local byDist = {}
	for model, st in pairs(tracked) do
		if not model.Parent then
			leave(model)
		else
			local host = model:IsA("BasePart") and model or model.PrimaryPart
			local d = host and (host.Position - eye).Magnitude or math.huge
			st.dist = d
			-- animation band with hysteresis
			if st.near and d > ANIMATE_OUT then
				st.near = false
				if st.v.motion and st.v.motion.limbBeams then dropElectricBeams(st) end
			elseif not st.near and d < ANIMATE_IN then
				st.near = true
			end
			-- effects band
			local wantEffects = d < EFFECTS_OUT
			if wantEffects ~= st.effectsOn then
				st.effectsOn = wantEffects
				for _, desc in ipairs(model:GetDescendants()) do
					if desc:IsA("ParticleEmitter") and desc.Name == "MutationFXEmitter" then
						desc.Enabled = wantEffects
					end
				end
			end
			byDist[#byDist + 1] = { model = model, st = st, d = d }
		end
	end

	-- highlight budget: nearest N only
	table.sort(byDist, function(x, y) return x.d < y.d end)
	for i, e in ipairs(byDist) do
		local h = e.st.highlight
		if h and h.Parent then
			h.Enabled = (i <= HIGHLIGHT_BUDGET) and e.d < EFFECTS_OUT
		end
	end
end

----------------------------------------------------------------- the driver
RunService.Heartbeat:Connect(function(dt)
	clock += dt
	if clock - lastScan >= SCAN_EVERY then
		lastScan = clock
		scan()
	end

	for model, st in pairs(tracked) do
		if st.near then
			local v = st.v
			local motion = v.motion
			local t = clock + st.phase
			if motion then
				-- flickering point lights (Electric 0.1 amp, Demon 0.3)
				if motion.lightFlicker and st.light and st.light.Parent then
					local base = v.light.brightness
					st.light.Brightness = base * (1 - motion.lightFlicker * (0.5 + 0.5 * math.sin(t * 23) * math.sin(t * 7.3)))
				end
				-- Electric limb arcs
				if motion.limbBeams then
					ensureElectricBeams(model, st)
					if clock - st.lastBeamStep >= (motion.beamRestep or 0.1) then
						st.lastBeamStep = clock
						restepElectric(st)
					end
				end
				-- Rainbow: the SPECTRUM SCROLLS UP THE BODY (reworked 2026-08-15).
				-- This used to drive ONE hue into a highlight fill it forced to 65%
				-- opacity, over a body MutationFX had flattened to flat red -- so the
				-- creature showed a single colour at any instant and its shape was
				-- buried under the fill. applyRainbowBody now stamps a base hue on each
				-- part from its height; all this does is add a moving offset, so the
				-- whole spectrum is on screen at once and it travels upward.
				-- The fill is deliberately left alone: the BODY is the rainbow now, and
				-- re-flooding it would hide the thing we just built.
				if motion.hueCycle then
					local off = (t / motion.hueCycle) % 1
					if st.hueParts == nil then
						st.hueParts = {}
						for _, d in ipairs(model:GetDescendants()) do
							if d:IsA("BasePart") and d:GetAttribute("MutationHue") ~= nil then
								st.hueParts[#st.hueParts + 1] = d
							end
						end
					end
					for _, p in ipairs(st.hueParts) do
						if p.Parent then
							p.Color = Color3.fromHSV(((p:GetAttribute("MutationHue") or 0) + off) % 1, 0.85, 1)
						end
					end
					local lead = Color3.fromHSV(off, 0.85, 1)
					if st.groundRing and st.groundRing.Parent then
						st.groundRing.Color = lead
					end
					if st.highlight and st.highlight.Parent then
						st.highlight.OutlineColor = hueShift(lead, 0.12)
					end
				end
				-- ring spins (Celestial 9s, Rainbow ground ring 4s)
				if motion.ringSpin then
					local spin = (t / motion.ringSpin) * math.pi * 2
					if st.ring and st.ring.Parent and st.ringBase then
						st.ring.CFrame = st.ringBase * CFrame.Angles(0, spin, 0)
					end
					if st.groundRing and st.groundRing.Parent and st.groundRingBase then
						st.groundRing.CFrame = st.groundRingBase * CFrame.Angles(spin, 0, 0)
					end
				end
				-- Golden sheen: outline shimmer every sheenSweep seconds
				if motion.sheenSweep and st.highlight and st.highlight.Parent then
					local k = (t % motion.sheenSweep) / motion.sheenSweep
					local pulse = math.clamp(1 - math.abs(k - 0.12) / 0.12, 0, 1)
					st.highlight.OutlineTransparency = 0.65 - 0.55 * pulse
				end
				-- Angel halo bob
				if motion.haloBob and st.halo and st.halo.Parent and st.haloBase then
					st.halo.CFrame = st.haloBase + Vector3.new(0, 0.16 * math.sin(t * (math.pi * 2) / motion.haloBob), 0)
				end
				-- Aurora ribbon drift: widths breathe slowly
				if motion.ribbonDrift then
					for _, d in ipairs(model:GetDescendants()) do
						if d:IsA("Beam") and d.Name == "MutationFXRibbon" then
							local w = 1 + 0.15 * math.sin(t * motion.ribbonDrift * math.pi * 2 + d.Width0)
							d.Width1 = d.Width0 * 1.35 * w
						end
					end
				end
				-- Wet ripple: the base decal swells and fades on a ripplePulse loop
				if motion.ripplePulse and st.groundDecal and st.groundDecal.Parent and st.groundDecalBase then
					local k = (t % motion.ripplePulse) / motion.ripplePulse
					local s = 0.55 + 0.75 * k
					st.groundDecal.Size = Vector3.new(st.groundDecalBase.X * s, st.groundDecalBase.Y, st.groundDecalBase.Z * s)
					if st.groundDecalFace then
						st.groundDecalFace.Transparency = 0.2 + 0.8 * k
					end
				end

				-- Glitched scanlines: the body-face bars slide down the model
				if motion.scanSlide then
					if st.scanTex == nil then
						st.scanTex = {}
						for _, d in ipairs(model:GetDescendants()) do
							if d:IsA("Texture") and d.Name == "MutationFXScanTex" then
								st.scanTex[#st.scanTex + 1] = d
							end
						end
					end
					for _, tex in ipairs(st.scanTex) do
						if tex.Parent then
							tex.OffsetStudsV = -(t * motion.scanSlide) % tex.StudsPerTileV
						end
					end
				end

				-- Celestial galaxy: slow texture scroll (the spec's 0.05)
				if motion.galaxyScroll then
					if st.galaxyTex == nil then
						st.galaxyTex = {}
						for _, d in ipairs(model:GetDescendants()) do
							if d:IsA("Texture") and d.Name == "MutationFXGalaxyTex" then
								st.galaxyTex[#st.galaxyTex + 1] = d
							end
						end
					end
					local off = (t * motion.galaxyScroll * 4) % 4
					for _, tex in ipairs(st.galaxyTex) do
						if tex.Parent then
							tex.OffsetStudsU = off
							tex.OffsetStudsV = off * 0.6
						end
					end
				end

				-- Glitched strobe: RGB split holds ~45% of the 2.2s cycle
				if motion.glitchStrobe and st.highlight and st.highlight.Parent then
					local cycle = (t % motion.glitchStrobe) / motion.glitchStrobe
					if cycle < 0.45 then
						local flip = math.floor(t * 12) % 2 == 0
						st.highlight.FillColor = flip and v.palette.primary or v.palette.secondary
						st.highlight.OutlineColor = flip and v.palette.secondary or v.palette.primary
						st.highlight.FillTransparency = 0.25 + 0.15 * (flip and 1 or 0)
					else
						st.highlight.FillColor = v.palette.primary
						st.highlight.OutlineColor = v.palette.secondary
						st.highlight.FillTransparency = 0.3
					end
				end
				-- plate loops
				local plateKind = motion.plate
				if plateKind then
					local pill = st.pill
					if pill == nil then
						pill = plateOf(model) or false
						st.pill = pill
					end
					if pill and pill.Parent then
						if plateKind == "flicker" then
							pill.BackgroundTransparency = (math.floor(t / 1.1 * 6) % 5 == 0) and 0.45 or 0
						elseif plateKind == "hue" then
							local g = pill:FindFirstChildOfClass("UIGradient")
							if g then
								local hue = (t / 4) % 1
								g.Color = ColorSequence.new(Color3.fromHSV(hue, 0.85, 1), Color3.fromHSV((hue + 0.25) % 1, 0.85, 1))
							end
						elseif plateKind == "jitter" then
							local stepT = math.floor(t / 2.2 * 10)
							if stepT % 7 == 0 then
								pill.Position = UDim2.new(0.5, math.random(-2, 2), 0, math.random(-1, 1))
							else
								pill.Position = UDim2.new(0.5, 0, 0, 0)
							end
						end
					end
				end
			end
		end
	end
end)

----------------------------------------------------------------- registry
for _, model in ipairs(CollectionService:GetTagged("MutationBody")) do
	enter(model)
end
CollectionService:GetInstanceAddedSignal("MutationBody"):Connect(enter)
CollectionService:GetInstanceRemovedSignal("MutationBody"):Connect(leave)
