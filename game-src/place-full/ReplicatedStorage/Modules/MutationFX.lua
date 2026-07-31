-- MutationFX: the 3D presentation of a mutated brainrot.
--
-- Before this, all twelve mutations rendered IDENTICALLY -- one PointLight plus
-- one sparkle emitter, tinted. A Glitched (x50) looked exactly like a Golden
-- (x2). The economy already has a careful 12-rung rarity ladder in
-- MutationConfig; this makes that ladder visible.
--
-- Everything here is a STATIC instance -- lights, emitters, a Highlight. No
-- per-frame work and no tweens, because these sit on every placed brainrot on
-- every plot in the server and anything per-frame would multiply badly.
--
-- NOTE: it never recolours the model's own parts. Flattening an authored model
-- to one colour erases the thing that makes it recognisable (Pete has 47 parts).
-- The tint is carried by light, particles and a Highlight OUTLINE instead.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)

local M = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

-- Rarity runs 1 (Golden) .. 12 (Angel). Bands, each adding a NEW kind of effect
-- rather than just more of the last one, so you can read the tier at a glance:
--   1-2   light + sparkles
--   3-6   + a coloured outline around the whole creature
--   7-9   + a faint inner fill and denser, faster sparkles
--   10-12 + rising motes and the brightest light in the game
local function band(r)
	if r >= 10 then return 4
	elseif r >= 7 then return 3
	elseif r >= 3 then return 2
	else return 1 end
end

-- Strip anything a previous call left behind so this is safe to re-apply.
function M.clear(host)
	for _, d in ipairs(host:GetDescendants()) do
		if d.Name == "MutationLight" or d.Name == "MutationAura"
		or d.Name == "MutationMotes" or d.Name == "MutationGlow" then
			d:Destroy()
		end
	end
end

-- model may be a Model or a single BasePart (the placeholder cube).
-- Returns true if anything was applied.
function M.apply(model, mutationName)
	if not mutationName then return false end
	local colour = Mutations.Color(mutationName)
	if not colour then return false end
	local rarity = Mutations.Rarity(mutationName)
	local b = band(rarity)

	local host = model:IsA("BasePart") and model or model.PrimaryPart
	if not host then
		host = model:FindFirstChildWhichIsA("BasePart", true)
	end
	if not host then return false end

	M.clear(model)

	-- how far up the ladder we are, 0..1 -- drives every magnitude below
	local t = math.clamp((rarity - 1) / 11, 0, 1)

	-- Kept deliberately modest. A plot has 16 pads and a server has six plots, so
	-- these can stack to ~96 lights; the old single-value 13/3 washed the whole
	-- base out once more than a couple were mutated. The Highlight below is what
	-- actually carries the colour -- the light is only there to sell it.
	local light = Instance.new("PointLight")
	light.Name = "MutationLight"
	light.Color = colour
	light.Range = 7 + 6 * t
	light.Brightness = 1.0 + 2.6 * t
	light.Parent = host

	local aura = Instance.new("ParticleEmitter")
	aura.Name = "MutationAura"
	aura.Texture = SPARKLE
	aura.Color = ColorSequence.new(colour)
	aura.Rate = 16 + 44 * t
	aura.Lifetime = NumberRange.new(0.6, 1.2 + 0.6 * t)
	aura.Speed = NumberRange.new(0.4, 1.4 + 1.6 * t)
	aura.SpreadAngle = Vector2.new(180, 180)
	aura.Size = NumberSequence.new(0.45 + 0.35 * t)
	aura.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	aura.Parent = host

	-- band 2+: outline the whole creature in its mutation colour. A Highlight is
	-- the one way to tint a model without touching its parts' own colours.
	if b >= 2 and not model:IsA("BasePart") then
		local hl = Instance.new("Highlight")
		hl.Name = "MutationGlow"
		hl.FillColor = colour
		hl.OutlineColor = colour
		-- band 2 is outline-only; the fill creeps in higher up the ladder so the
		-- top tiers read as genuinely glowing rather than merely outlined
		hl.FillTransparency = (b >= 3) and (0.86 - 0.22 * t) or 1
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = model
	end

	-- band 4: rising motes, reserved for Glitched / Demon / Angel
	if b >= 4 then
		local motes = Instance.new("ParticleEmitter")
		motes.Name = "MutationMotes"
		motes.Texture = SPARKLE
		motes.Color = ColorSequence.new(colour)
		motes.Rate = 14
		motes.Lifetime = NumberRange.new(1.4, 2.2)
		motes.Speed = NumberRange.new(2.4, 4.0)
		motes.SpreadAngle = Vector2.new(14, 14)
		motes.Acceleration = Vector3.new(0, 3.5, 0)   -- drift upward
		motes.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.7),
			NumberSequenceKeypoint.new(1, 0),
		})
		motes.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		motes.Parent = host
	end

	return true
end

return M
