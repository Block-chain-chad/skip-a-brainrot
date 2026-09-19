--[[ PippoSkin -- paints Claude Design's Pippo mutation pack onto OUR brainrots.

THE PACK IS THE AUTHORITY AND IS NOT COPIED HERE. ReplicatedStorage.Modules.
PippoMutations is the pack's own Luau port, installed byte-exact and verified
against its generated parity.json (all 13 mutations match on voxel count, class
histogram and colour probes). This module does not re-implement a single one of
its transforms -- it CALLS them.

THE ONE TRICK THAT MAKES IT 1:1. The pack resolves a voxel with
`style(mat, x, y, z)`, and internally that reads its own BASE_PALETTE to find the
voxel's base colour. `B(m)` does that lookup at CALL time, on the live table -- so
writing our part's colour into a palette slot and then calling style() runs the
pack's exact arithmetic over OUR colour instead of Pippo's olive. Same for
glowFn(). Nothing is approximated or re-derived.

WHAT THIS FIXES vs the earlier attempt. The first pass applied one flat colour
transform per mutation and no emissive at all, which is why it read as a plain
recolour: glowFn was simply never called. It is the entire visual identity of half
the pack -- demon's lava seams, aurora's rising curtains, celestial's starfield,
electric's arcs, glitched's corruption bands, gold's sparkle flecks. It is also
POSITION-DRIVEN, so different parts of one creature get different treatment, which
a single transform can never produce.

The second pass fixed that by rebuilding the body out of voxel cubes, and that
threw away the creature's silhouette. This keeps the creature and paints it.

MAPPING. Each part's centre is expressed in the model's own bounding box, then
scaled into the pack's frame (x -10..9, y 0..39, z -8..7) so a part low on the
body samples the pack low on the body. Every position-driven feature -- crack
seams, aurora bands, glitch scanlines, the rainbow hue ramp -- therefore lands in
the right place on any creature, whatever its proportions.

COMPOSITE. IMPLEMENTATION.md: the reference renderer draws `surface + glow * 0.75`,
and `glow`-class voxels go Neon and use the glow colour directly. Both are done
exactly that way below.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Pippo = require(ReplicatedStorage.Modules.PippoMutations)

local M = {}

-- The palette slot we borrow. Deliberately NOT an eye slot: isEye() drives a
-- separate branch in several mutations, and a whole creature is a body.
local SLOT = "olive"

--[[ How much of a SPARSE glow feature survives averaging.

A flat gain on the average was wrong and Angel proved it: its glow is a uniform
ambient wash (0.1 + 0.07*wave over the whole body), so multiplying the average
blew an already near-white body to pure #FFFFFF and erased every fold in it.

So the lift is applied to the SPREAD, not the level: glow = avg + (max - avg) *
FEATURE_LIFT. Where the glow is uniform -- Angel, Diamond's shimmer -- max equals
avg, the second term is zero, and the ambient passes through untouched.

AND IT IS KEPT SMALL, which measurement settled rather than taste. Sampled on a
real Tung at lift 0 / 0.2 / 0.35 / 0.6, the pack's own descriptions pick out the
low end every time:
     electric  "near-black chrome body"   #384c59 -> #94abb6   washed out by 0.6
     gold      "saturated gold ramp"      #ffca52 -> #ffff9f   goes pale yellow
     aurora    "very dark body"           #2e4641 -> #44a295   stops being dark
     celestial "night-sky body"           #403889 -> #a99edd   stops being night
Only Demon genuinely wants lifting, because its lava seams ARE its identity and
at lift 0 they average away to nothing (#3d150d).

The reason a small number is right is structural, and IMPLEMENTATION.md says so
for exactly this case: a one-voxel seam on a 4,280-voxel body is simply below the
resolution of a six-part model, and the fix is not to fake it in the body colour.
Its Path-A guidance is to "drive a Highlight/PointLight/texture tint rather than
per-voxel colour" -- which is what MutationVisuals' effect stack already does:
embers for Demon, arc beams for Electric, ribbons for Aurora, a starfield for
Celestial. Body faithful here; features carried there. ]]
local FEATURE_LIFT = 0.12

--[[ MINIMUM SAMPLING NEIGHBOURHOOD, in pack voxels.

Without it the sample window is the PART's own extent, and on a model built from
many small parts that is about one voxel -- so each part takes a single noisy draw
from a sparse random feature (Celestial's starfield, Gold's sparkle flecks), and
neighbouring parts draw independently of each other.

Measured on Secret Pete, 195 parts and 20 distinct colours unmutated: Celestial
gave him 172 DISTINCT COLOURS -- very nearly one per part. That is not a mutation,
it is confetti, and it is what "the design and the mutation didn't blend" looks
like. Tung has six parts and never showed it.

A fixed minimum neighbourhood makes adjacent parts overlap the same sampled
region, so they resolve to similar values and the feature reads as one coherent
pattern across the body instead of per-part static. Parts larger than the minimum
still use their own extent, so nothing is lost on a chunky model. ]]
local MIN_SAMPLE_VOX = 3

local function hexOf(c: Color3): number
	return bit32.bor(
		bit32.lshift(math.floor(c.R * 255 + 0.5), 16),
		bit32.lshift(math.floor(c.G * 255 + 0.5), 8),
		math.floor(c.B * 255 + 0.5))
end

local function clamp01(v) return v < 0 and 0 or (v > 1 and 1 or v) end

-- The pack's hsl(), needed because rainbow's motion does NOT go through glowFn --
-- it recomputes the body colour from a scrolling hue, so style() alone can never
-- animate it (which is exactly why rainbow came out frozen on the first pass).
-- Deterministic maths, not the hash: safe to port, unlike rand().
local function hsl(h: number, s: number, l: number)
	h = (h % 1 + 1) % 1
	local function f(n)
		local k = (n + h * 12) % 12
		local a = s * math.min(l, 1 - l)
		return l - a * math.max(-1, math.min(k - 3, math.min(9 - k, 1)))
	end
	return f(0), f(8), f(4)
end

--- Parts worth painting. Invisible scaffolding (RootPart, FakeRootPart,
--- VfxInstance) exists on 148 of the 192 models and must keep its transparency --
--- a glass class would otherwise turn it into visible boxes round the creature.
local function paintable(model: Instance): { BasePart }
	local out = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.9
			and not d:FindFirstAncestor("MutationSkin") then
			out[#out + 1] = d
		end
	end
	if #out == 0 and model:IsA("BasePart") then out[1] = model end
	return out
end
M.paintable = paintable

--[[ Paint one model with one mutation at time `t`.

`t` only matters for the animated mutations -- it is the pack's own animation
clock, in seconds, and every glowFn takes it. Re-calling with a rising t is what
scrolls rainbow's hue, pulses demon's lava and drifts aurora's curtains.

Stores each part's ORIGINAL colour in an attribute the first time it runs, so
repeated calls (the animation driver does ~20/second) keep transforming the
creature's own colour rather than compounding on the previous result.
]]
function M.Paint(model: Instance, id: string, t: number?, quality: number?)
	local samples = math.clamp(quality or 2, 1, 4)   -- (2*n+1)^3 points per part
	local spec = Pippo.specOf(id)
	if not spec then return 0 end
	local parts = paintable(model)
	if #parts == 0 then return 0 end

	local F = Pippo.FRAME
	-- NOT a parenthesised ternary: wrapping GetBoundingBox() in brackets truncates
	-- it to its first return and `size` comes back nil.
	local cf, size
	if model:IsA("BasePart") then
		cf, size = model.CFrame, model.Size
	else
		cf, size = model:GetBoundingBox()
	end
	local sx = math.max(size.X, 0.001)
	local sy = math.max(size.Y, 0.001)
	local sz = math.max(size.Z, 0.001)
	local time = t or 0.6

	-- borrowed for the duration of the pass, restored before returning: the pack
	-- module is shared, and leaving our colour in its palette would corrupt any
	-- later VoxelsFor() call
	local saved = Pippo.BASE_PALETTE[SLOT]

	for _, p in ipairs(parts) do
		-- the creature's OWN colour is the input, every time
		local base = p:GetAttribute("PippoBaseColor")
		if typeof(base) ~= "Color3" then
			base = p.Color
			p:SetAttribute("PippoBaseColor", base)
		end

		local rel = cf:PointToObjectSpace(p.Position)
		local fx = math.floor(F.minX + (rel.X / sx + 0.5) * (F.maxX - F.minX) + 0.5)
		local fy = math.floor(F.minY + (rel.Y / sy + 0.5) * (F.maxY - F.minY) + 0.5)
		local fz = math.floor(F.minZ + (rel.Z / sz + 0.5) * (F.maxZ - F.minZ) + 0.5)

		Pippo.BASE_PALETTE[SLOT] = hexOf(base)
		local st = spec.style(SLOT, fx, fy, fz)

		--[[ GLOW IS SUPERSAMPLED ACROSS THE PART, not read at its centre.

		The pack's emissive features are FINE: demon's lava runs in seams about one
		voxel wide (~5% of positions), gold sparkles on 2.2% of voxels, glitched
		corrupts scattered bands. Pippo has 4,280 voxels so plenty land on one; a
		brainrot has about six parts, so point-sampling their centres misses almost
		everything and the mutation reads as a flat recolour -- demon in particular
		came out as plain charred brown with no heat in it at all.

		Sampling the part's whole EXTENT and averaging is what a body made of
		thousands of voxels would actually show: a part a seam crosses picks up a
		share of that seam proportional to how much of it is lit. ]]
		local glow = { 0, 0, 0 }
		if spec.glowFn then
			local ext = p.Size
			-- the part's half-extent in pack-frame voxels, at least one either way
			local hx = math.max(MIN_SAMPLE_VOX, math.floor(ext.X / sx * (F.maxX - F.minX) * 0.5))
			local hy = math.max(MIN_SAMPLE_VOX, math.floor(ext.Y / sy * (F.maxY - F.minY) * 0.5))
			local hz = math.max(MIN_SAMPLE_VOX, math.floor(ext.Z / sz * (F.maxZ - F.minZ) * 0.5))
			local n = 0
			local mx = { 0, 0, 0 }
			for i = -samples, samples do
				for j = -samples, samples do
					for k = -samples, samples do
						local g = spec.glowFn(SLOT,
							fx + math.floor(hx * i / samples),
							fy + math.floor(hy * j / samples),
							fz + math.floor(hz * k / samples), time)
						glow[1] += g[1]; glow[2] += g[2]; glow[3] += g[3]
						if g[1] > mx[1] then mx[1] = g[1] end
						if g[2] > mx[2] then mx[2] = g[2] end
						if g[3] > mx[3] then mx[3] = g[3] end
						n += 1
					end
				end
			end
			-- avg + (max - avg) * lift: ambient passes through, sparse features survive
			for ci = 1, 3 do
				local avg = glow[ci] / n
				glow[ci] = math.min(avg + (mx[ci] - avg) * FEATURE_LIFT, 1)
			end
		end

		local cls = Pippo.CLASSES[st.cls] or Pippo.CLASSES.solid
		if st.cls == "glow" then
			-- a glow voxel IS the light: Neon, glow colour straight on
			p.Color = Color3.new(
				clamp01(math.max(st.c[1], glow[1])),
				clamp01(math.max(st.c[2], glow[2])),
				clamp01(math.max(st.c[3], glow[3])))
		else
			-- surface + glow * 0.75, the reference renderer's own composite
			p.Color = Color3.new(
				clamp01(st.c[1] + glow[1] * 0.75),
				clamp01(st.c[2] + glow[2] * 0.75),
				clamp01(st.c[3] + glow[3] * 0.75))
		end
		-- HUE SCROLL overrides the style colour outright, the same way the pack's own
		-- Animate does: `hsl(y*0.055 + x*0.014 - t*0.28, 0.78, 0.55)`. Eyes are left
		-- alone there and we have none, so every part scrolls.
		if spec.animate and spec.animate.kind == "hueScroll" then
			local r, g, b = hsl(fy * 0.055 + fx * 0.014 - time * 0.28, 0.78, 0.55)
			p.Color = Color3.new(r, g, b)
		end

		p.Material = cls.Material
		p.Reflectance = cls.Reflectance
		-- guarded: see paintable() -- and never push an already-solid part see-through
		if cls.Transparency > 0 then p.Transparency = cls.Transparency end

		-- authored surface art rides along, or a decal-faced model keeps a pristine
		-- face over a fully mutated body
		for _, k in ipairs(p:GetChildren()) do
			if k.Name:sub(1, 10) ~= "MutationFX" then
				if k:IsA("Decal") or k:IsA("Texture") then
					k.Color3 = Color3.new(1, 1, 1):Lerp(p.Color, 0.55)
				elseif k:IsA("SurfaceAppearance") then
					k.Color = Color3.new(1, 1, 1):Lerp(p.Color, 0.55)
				end
			end
		end
	end

	Pippo.BASE_PALETTE[SLOT] = saved
	return #parts
end

--[[ GLITCHED'S SLICE TEAR. The one mutation whose motion is geometry rather than
colour: horizontal bands jump along X, 9 steps a second, 28% of bands per step.
The pack's numbers exactly -- band = floor(y/3), and the 0.3/0.28 converts its
metres to studs.

Only ever applied to ANCHORED parts. On a live pad model the parts are welded to
a moving root, and writing Position under that fights the physics solver rather
than tearing the creature. ]]
function M.SliceShift(model: Instance, t: number)
	local parts = paintable(model)
	if #parts == 0 then return end
	local F = Pippo.FRAME
	local cf, size
	if model:IsA("BasePart") then
		cf, size = model.CFrame, model.Size
	else
		cf, size = model:GetBoundingBox()
	end
	local sy = math.max(size.Y, 0.001)
	local step = math.floor(t * 9)
	for _, p in ipairs(parts) do
		if p.Anchored then
			local home = p:GetAttribute("PippoHomePos")
			if typeof(home) ~= "Vector3" then
				home = p.Position
				p:SetAttribute("PippoHomePos", home)
			end
			local rel = cf:PointToObjectSpace(home)
			local fy = math.floor(F.minY + (rel.Y / sy + 0.5) * (F.maxY - F.minY) + 0.5)
			local band = math.floor(fy / 3)
			local off = 0
			if Pippo.rand(step, band, 0, 83) > 0.72 then
				off = (Pippo.rand(step, band, 1, 89) - 0.5) * 0.3 / 0.28
			end
			p.Position = Vector3.new(home.X + off, home.Y, home.Z)
		end
	end
end

--- Which mutations actually move, and how fast the pack says they should be
--- resampled. Static ones must never be handed to the driver -- repainting a
--- still image 20 times a second is pure cost.
function M.AnimateKind(id: string): string?
	local spec = Pippo.specOf(id)
	local a = spec and spec.animate
	return a and a.kind or nil
end

return M
