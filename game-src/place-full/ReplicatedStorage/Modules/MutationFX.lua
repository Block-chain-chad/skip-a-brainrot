-- MutationFX: the 3D presentation of a mutated brainrot.
--
-- 2026-08-13 BESPOKE REWRITE (from the "Roblox brainrot mutations" design
-- handoff; owner-approved, replacing the generic 4-band ladder that shipped
-- 2026-07-27). Every mutation now has its own identity -- see MutationVisuals
-- for the data and the deltas from the handoff (Fog dropped, real economy
-- kept, ring parity with the tiles).
--
-- DIVISION OF LABOUR:
--   * This module (required by the SERVER at spawn, and by CatchReveal /
--     PullCeremony client-side for display clones) builds ONLY STATIC
--     instances: materials, colour shifts, highlights, emitters, lights,
--     beams, shells, halos. Nothing here ticks.
--   * Anything that MOVES (hue cycles, flickers, sheens, halo bobs, ring
--     spins, glitch strobes) is driven by StarterPlayerScripts.
--     MutationMotionClient -- ONE Heartbeat for every mutated model in view,
--     with distance LOD. The handshake is the "MutationBody" CollectionService
--     tag plus the model's existing "Mutation" attribute.
--
-- COLOUR SHIFTS, NOT FLATTENS: every shift transforms each part's OWN colour
-- (hue/sat/value maths), so a 47-part Pete keeps his internal read. Rainbow used
-- to be the one exception -- it flattened the whole body to a single hex and let
-- the client cycle it -- and that is exactly why it read as a flat glowing blob
-- that was only ever ONE colour at a time (and plain red in any still). It now
-- gets a real spectrum across the body instead; see applyRainbowBody.
-- Recolours and material swaps are PERMANENT for the model instance: placed
-- models are fresh clones on every spawn and display clones are throwaway, so
-- nothing ever needs the original back (clear() removes added INSTANCES only).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Visuals = require(ReplicatedStorage.Modules.MutationVisuals)

local M = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local A = Visuals.Assets -- phase-2 bespoke sprites (see MutationVisuals)

local FXTAG = "MutationBody"

----------------------------------------------------------------- small helpers
local function partsOf(model)
	local out = {}
	if model:IsA("BasePart") then
		out[1] = model
	else
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then out[#out + 1] = d end
		end
	end
	return out
end

-- PARTS THAT ACTUALLY SHOW (2026-08-18). 148 of the 192 brainrot models carry fully
-- invisible scaffolding -- RootPart, FakeRootPart, VfxInstance and friends -- and any
-- effect that BUILDS geometry from a part, or paints a surface onto one, turns that
-- scaffolding into something you can see:
--   * addIceShell cloned them into 0.62-transparency glass, so Frozen grew a crate of
--     phantom boxes around the body. Tung Tung Tung Sahur is 3 invisible parts out of
--     6, so its "ice" was mostly boxes hanging in open air. (owner: "fix diamond and
--     frozen, they look really bad")
--   * addScanTex / addGalaxyTex tile Textures, and Roblox draws a Texture on a part
--     even at Transparency 1 -- so Glitched hung scanline bars, and Celestial hung
--     starfields, in mid-air around the model.
--   * applyTrimNeon spent its capped Neon budget on parts nobody can see.
-- Recolouring an invisible part is harmless, so partsOf above is deliberately left
-- alone; this is for the effects where being visible is the entire point.
local function renderedParts(model)
	local out = {}
	for _, p in ipairs(partsOf(model)) do
		if p.Transparency < 0.9 then out[#out + 1] = p end
	end
	-- never hand back an empty list: a model that somehow renders nothing should still
	-- get whatever the effect intended rather than silently losing it
	if #out == 0 then return partsOf(model) end
	return out
end

local function hostOf(model)
	return model:IsA("BasePart") and model or (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true))
end

local function boxOf(model)
	if model:IsA("BasePart") then
		return model.CFrame, model.Size
	end
	return model:GetBoundingBox()
end

-- attachment at a world position, expressed in the host's local space
local function attachAt(host, worldPos, name)
	local a = Instance.new("Attachment")
	a.Name = name
	-- parent FIRST: WorldPosition on an unparented attachment writes the raw
	-- world coords into local Position, which then gets re-interpreted in host
	-- space on parenting -- flinging the attachment |worldPos| studs away in a
	-- direction set by the host's yaw (the wandering-ribbons bug).
	a.Parent = host
	a.WorldPosition = worldPos
	return a
end

----------------------------------------------------------------- colour shifts
local CHAR_TARGET = Color3.fromHex("1A0505")
-- Diamond and Frozen pull toward these AFTER their HSV maths. An RGB lerp, not a
-- hue rotation: rotating an orange body's hue toward cyan travels through YELLOW
-- and GREEN, so a "slightly icy" creature comes out swamp-coloured on the way.
local DIAMOND_ICE = Color3.fromHex("CFEFFF")
local FROST_BLUE = Color3.fromHex("BBE4F5")

--[[ ================= THE PIPPO OLIVARDINO MUTATION PACK ==================
Claude Design's 12-mutation pack (`pippo_mutations.js`, 2026-08-19), ported 1:1.

The pack defines each mutation as `style(mat, x, y, z) -> { cls, c }`: a TRANSFORM
of the voxel's own base colour plus a shading class. That is precisely the shape
this table already had, which is why the port is a straight translation rather
than a rewrite -- each function below is the pack's own arithmetic, and the
constants are its own hexes.

TWO THINGS THE PORT HAS TO BRIDGE:

 1. HSL, NOT HSV. The pack's `hsl()` takes lightness; Color3.fromHSV takes value,
    and they are NOT the same axis -- feeding an L into fromHSV washes every
    ramp out at the top end. hslC below is the pack's own function, ported.

 2. PER-VOXEL NOISE HAS NO VOXELS HERE. Diamond's facets, Sandy's grain and
    Frozen's frost are `rand(x,y,z,seed)` over a voxel grid. A brainrot is an
    authored model of a few dozen parts, so the noise is hashed off each PART's
    position instead -- same role (breaks up a flat ramp), same determinism (a
    given part always lands on the same value, so nothing shimmers between
    applications), different granularity.

The pack's rarity column is deliberately ignored: its own README calls those
placeholders and says to keep the game's drop table, which lives in
MutationConfig and is untouched. ]]
local function hexC(h)
	return Color3.fromRGB(bit32.band(bit32.rshift(h, 16), 255),
		bit32.band(bit32.rshift(h, 8), 255), bit32.band(h, 255))
end
local function lumC(c) return c.R * 0.299 + c.G * 0.587 + c.B * 0.114 end
local function mulC(c, k) return Color3.new(c.R * k, c.G * k, c.B * k) end
-- the pack's hsl(), ported verbatim (lightness, not value)
local function hslC(h, s, l)
	h = (h % 1 + 1) % 1
	local function f(n)
		local k = (n + h * 12) % 12
		local a = s * math.min(l, 1 - l)
		return l - a * math.max(-1, math.min(k - 3, math.min(9 - k, 1)))
	end
	return Color3.new(f(0), f(8), f(4))
end
-- Stable 0..1 per part, standing in for the pack's rand(x,y,z,seed). Quantised so
-- two parts at nearly the same spot get the same value rather than a seam.
local function pnoise(p, seed)
	if not p then return 0.5 end
	local v = p.Position
	local n = math.floor(v.X * 7.13) * 374761393
		+ math.floor(v.Y * 7.13) * 668265263
		+ math.floor(v.Z * 7.13) * 1274126177
		+ (seed or 0) * 362437
	n = (n % 2147483647 + 2147483647) % 2147483647
	n = (n * 1103515245 + 12345) % 2147483647
	return n / 2147483647
end

-- pack constants, by mutation
local DIA_A, DIA_B = hexC(0x8ecfec), hexC(0xeafcff)
local WET_DEEP = hexC(0x24484a)
local SAND_DK, SAND_LT = hexC(0x7a5c2c), hexC(0xf0e2b8)
local ELEC_DEEP = hexC(0x14304a)
local ICE_MIX = hexC(0xa9cddd)
local AUR_DEEP = hexC(0x0e2233)
local CEL_A, CEL_B = hexC(0x151a4c), hexC(0x453690)
local GLITCH_DEEP = hexC(0x291d33)
local DEM_A, DEM_B = hexC(0x140806), hexC(0x4a1a12)
local ANG_A, ANG_B, ANG_WARM = hexC(0xdcd3b4), hexC(0xfffefa), hexC(0xf6e8bc)
local WHITE = Color3.new(1, 1, 1)

local SHIFTS = {
	none = nil,

	--== the pack's twelve, each one its own style() ==--
	-- gold: hsl(.115, .95, .22 + min(.62, lum*.72)) -- a saturated gold RAMP driven
	-- by the part's own brightness, so a two-tone creature stays two-tone in gold.
	pGold = function(c)
		return hslC(0.115, 0.95, 0.22 + math.min(0.62, lumC(c) * 0.72))
	end,
	-- diamond: mix(8ecfec, eafcff, min(1, lum*1.2 + facet)), facet = rand*.2
	pDiamond = function(c, p)
		return DIA_A:Lerp(DIA_B, math.min(1, lumC(c) * 1.2 + pnoise(p, 3) * 0.2))
	end,
	-- wet: mix(mul(c,.78), 24484a, .16) -- darkened and pulled toward brine
	pWet = function(c)
		return mulC(c, 0.78):Lerp(WET_DEEP, 0.16)
	end,
	-- sandy: mix(7a5c2c, f0e2b8, clamp(lum*1.15 + grain)), grain = (rand-.5)*.16
	pSandy = function(c, p)
		return SAND_DK:Lerp(SAND_LT,
			math.clamp(lumC(c) * 1.15 + (pnoise(p, 9) - 0.5) * 0.16, 0, 1))
	end,
	-- electric: mix(mul(c,.3), 14304a, .62) -- near-black chrome under the arcs
	pElectric = function(c)
		return mulC(c, 0.3):Lerp(ELEC_DEEP, 0.62)
	end,
	-- frozen: mix(mix(c, a9cddd, .55), white, frost), frost = rand>.8 ? .35 : 0
	pFrozen = function(c, p)
		local frost = (pnoise(p, 13) > 0.8) and 0.35 or 0
		return c:Lerp(ICE_MIX, 0.55):Lerp(WHITE, frost)
	end,
	-- aurora: mix(mul(c,.3), 0e2233, .55) -- very dark, so the curtains carry it
	pAurora = function(c)
		return mulC(c, 0.3):Lerp(AUR_DEEP, 0.55)
	end,
	-- celestial: mix(151a4c, 453690, lum) -- night sky, brightness picks the depth
	pCelestial = function(c)
		return CEL_A:Lerp(CEL_B, lumC(c))
	end,
	-- glitched: mix(c, 291d33, .35) -- corrupted, keeps some of the creature
	pGlitched = function(c)
		return c:Lerp(GLITCH_DEEP, 0.35)
	end,
	-- demon: mix(140806, 4a1a12, lum*.9) -- charred, seams glow on top
	pDemon = function(c)
		return DEM_A:Lerp(DEM_B, lumC(c) * 0.9)
	end,
	-- angel: mix(mix(dcd3b4, fffefa, min(1, lum*1.5)), f6e8bc, .22)
	pAngel = function(c)
		return ANG_A:Lerp(ANG_B, math.min(1, lumC(c) * 1.5)):Lerp(ANG_WARM, 0.22)
	end,

	--== superseded by the pack, kept so an older look can be restored by name ==--
	warm = function(c)
		local h, s, v = c:ToHSV()
		return Color3.fromHSV(0.11, math.min(s * 0.8 + 0.25, 1), math.min(v * 1.02, 1))
	end,
	-- Frozen's shift, and Frozen's only. Loosened 2026-08-18 alongside Diamond: half
	-- the saturation plus a 12% value lift pushed most bodies to a pale wash, and with
	-- the ice shell over the top the creature underneath stopped reading at all.
	-- The frost lerp is what actually makes it read COLD. Desaturating alone just made
	-- bodies pale -- pale is not frozen, and on a warm-coloured creature it read as
	-- washed out. Keeping saturation and pulling toward blue is the difference.
	desat = function(c)
		local h, s, v = c:ToHSV()
		return Color3.fromHSV(h, s * 0.62, math.min(v * 1.05, 1)):Lerp(FROST_BLUE, 0.38)
	end,
	brighten = function(c)
		local h, s, v = c:ToHSV()
		return Color3.fromHSV(h, s, math.min(v * 1.15, 1))
	end,
	darken55 = function(c)
		local h, s, v = c:ToHSV()
		return Color3.fromHSV(h, s, v * 0.55)
	end,
	darken18 = function(c)
		local h, s, v = c:ToHSV()
		return Color3.fromHSV(h, s, v * 0.82)
	end,
	char = function(c)
		return c:Lerp(CHAR_TARGET, 0.82)
	end,
	gold = function(c)
		local _, _, v = c:ToHSV()
		return Color3.fromHSV(0.125, 0.75, math.min(v * 1.05 + 0.08, 1))
	end,
	-- Diamond's shift, and Diamond's only. s * 0.12 was an 88% desaturation: every
	-- brainrot arrived as the SAME near-white blob with none of its own colour left,
	-- which is the literal opposite of blending with the creature (owner 2026-08-18).
	-- Keeping roughly half the saturation reads as "iced over" rather than "replaced",
	-- and the value lift is gentler now that the colour underneath survives to carry it.
	-- The value lift matters as much as the saturation here: v * 1.16 + 0.06 CLAMPED to
	-- 1.0 for any body brighter than ~0.81, which is most of them, so every model came
	-- out at maximum brightness and read as pastel however much saturation survived.
	-- A lift that does not clamp keeps the creature's own shading.
	--
	-- Saturation landed at 0.68 by comparison with Golden, which is the rung below and
	-- the one that visibly works: `gold` holds saturation at 0.75 and preserves value
	-- PER PART, so you read the creature's form through it. Diamond was doing the
	-- opposite on both counts. It gets its tier from the reflectance, the icy outline
	-- and the glint particles -- not from bleaching the creature.
	--
	-- FINAL VALUE 0.85, and it is high on purpose. Diamond and Frozen kept collapsing
	-- into the same pale neutral, because "crystalline" and "blend with the creature"
	-- pull in opposite directions and Frozen already owns pale-and-icy. Diamond is
	-- therefore resolved the other way: it stays almost fully the creature's own
	-- colour, just brighter, and the tier is carried entirely by the gloss, the icy
	-- outline and the glint particles. If it ever needs to read more crystalline than
	-- creature, this multiplier and the DIAMOND_ICE lerp below are the two dials --
	-- but moving them back toward Frozen's territory is what made them twins before.
	white = function(c)
		local h, s, v = c:ToHSV()
		-- Only a light pull toward ice, and that is deliberate: at 0.28 Diamond and
		-- Frozen both landed on the same pale neutral and you could not tell the two
		-- rungs apart at a glance. Frozen owns COLD (frost lerp plus the shell); Diamond
		-- keeps the creature's own warmth and takes its identity from SHINE -- the
		-- reflectance, the icy outline and the glint particles. Two different ideas
		-- rather than two strengths of the same one.
		return Color3.fromHSV(h, s * 0.85, math.min(v * 1.05, 1)):Lerp(DIAMOND_ICE, 0.10)
	end,
}

-- AUTHORED SURFACE ART: Decal, Texture, and -- the one that was missing --
-- SurfaceAppearance. A SurfaceAppearance's ColorMap OVERRIDES BasePart.Color
-- outright, so a colour shift never reaches that surface at all: 147 of the 192
-- models carry one, usually on the face mesh, which is precisely the "parts of their
-- face stay normal colour" the owner reported 2026-08-18. Its own Color is a tint
-- multiplier and starts white.
--
-- The tint TRACKS THE BODY rather than being derived from the art's own white
-- multiplier. Running the shift over white was the obvious move and it is subtly
-- wrong: a shift's effect on white is not its effect on the creature. Diamond keeps
-- a warm body because the creature's own hue survives the desaturation -- but white
-- has no hue to keep, so the same shift sent the face icy blue against a peach body,
-- swapping one mismatch for another. Blending white toward the part's ALREADY-SHIFTED
-- colour keeps face and body in step on every rung, and stopping partway leaves the
-- artwork's own detail readable instead of flooding it flat.
local ART_TINT_STRENGTH = 0.55
local function artTint(shiftedPartColour)
	return Color3.new(1, 1, 1):Lerp(shiftedPartColour, ART_TINT_STRENGTH)
end

-- Rainbow: a REAL spectrum down the body, not one flat colour.
--
-- 2026-08-15 (owner: "fix up rainbow too its kinda bad"). The old treatment set
-- every part to #FF5252 and went full Neon, so the entire creature collapsed into
-- a single glowing red silhouette -- all internal detail gone -- and the only
-- actual rainbow was the client hue-cycling a highlight it forced to 65% opacity
-- on top. That meant one colour visible at any instant, and a plain RED body in
-- every context where the motion driver does not run (viewport thumbnails, the
-- catch reveal's staged clone, edit-time stills).
--
-- Each part now takes its hue from its own HEIGHT in the model, so the whole
-- spectrum is on screen at once and the body keeps its shape. The base hue is
-- stamped on the part as an attribute; MutationMotionClient adds a scrolling
-- offset to it so the spectrum FLOWS up the body instead of the whole creature
-- strobing through one colour together.
local function applyRainbowBody(model, v)
	local cf, size = boxOf(model)
	local baseY = cf.Position.Y - size.Y * 0.5
	local span = math.max(size.Y, 0.01)
	for _, p in ipairs(partsOf(model)) do
		-- 2.2 TURNS, from the pack: its rainbow is hsl(y*.055 + x*.014, .78, .55) over
		-- a 40-voxel body, i.e. 40 * .055 = 2.2 full hue cycles from sole to scalp --
		-- tight bands rather than one slow sweep. (This used to run 0.85 of a turn, to
		-- avoid ending on the same red it began with; banding makes that moot.)
		local hue = math.clamp((p.Position.Y - baseY) / span, 0, 1) * 2.2
		p:SetAttribute("MutationHue", hue)
		-- the pack's saturation and LIGHTNESS, through its own hsl()
		p.Color = hslC(hue, 0.78, 0.55)
		-- painted faces ride the spectrum too, at lower saturation so a decal-faced
		-- model (Secret Pete) stays readable instead of vanishing into the colour
		for _, k in ipairs(p:GetChildren()) do
			if k.Name:sub(1, 10) ~= "MutationFX" then
				if k:IsA("Decal") or k:IsA("Texture") then
					k.Color3 = hslC(hue, 0.55, 0.6)
				elseif k:IsA("SurfaceAppearance") then
					k.Color = hslC(hue, 0.55, 0.6)   -- else the face sits out the spectrum
				end
			end
		end
	end
end

----------------------------------------------------------------- builders
--[[ The pack's own resolver, when the row names one. PippoSkin calls
PippoMutations' style() and glowFn() directly with the creature's colour in the
palette, so a brainrot gets the pack's exact arithmetic -- including the emissive,
which no `shift` function can express.

pcall'd and cached false on failure: this module is on the boot path for every
catch reveal and every pad spawn, and a missing art module must degrade to the
old shift rather than take a catch down with it. ]]
local pippoSkin = nil
local function skin()
	if pippoSkin == nil then
		local ok, mod = pcall(require, ReplicatedStorage.Modules:FindFirstChild("PippoSkin"))
		pippoSkin = (ok and type(mod) == "table") and mod or false
		if not pippoSkin then
			warn("[MutationFX] PippoSkin unavailable -- falling back to the shift table")
		end
	end
	return pippoSkin or nil
end
M.Skin = skin

local function applyShiftAndMaterial(model, v)
	-- PACK PATH. Returns early: it has already written colour, material,
	-- reflectance, transparency and the surface-art tint for every visible part.
	if v.pippo then
		local s = skin()
		if s then
			local ok = pcall(s.Paint, model, v.pippo, 0.6)
			if ok then
				--[[ MATERIAL OVERRIDE, APPLIED ON TOP OF THE PACK.

				Paint sets Material/Transparency/Reflectance from the pack's own CLASSES
				table, which is right for eleven of the twelve and wrong for the ones
				this game has already ruled on. Its `glass` class carries Transparency
				0.32, and on this map's bright skybox that leaves the creature half
				see-through -- a pale ghost inside its own outline.

				This block is why editing `material` in MutationVisuals looked like it
				did nothing: the pack path RETURNS EARLY below, so v.material was never
				read at all. It is read here instead, after the paint, so a row can
				override the pack's class without touching PippoSkin.

				Transparency is reset EXPLICITLY rather than left alone -- the pack may
				have just written 0.32, and an override that only sets Material would
				leave the creature transparent in a new material. Only parts Paint
				actually touched are eligible (it stamps PippoBaseColor on them), so the
				invisible scaffolding stays invisible. ]]
				if v.material then
					for _, p in ipairs(partsOf(model)) do
						if p:GetAttribute("PippoBaseColor") ~= nil then
							if v.material.material then p.Material = v.material.material end
							p.Reflectance = v.material.reflectance or 0
							p.Transparency = v.material.transparency or 0
						end
					end
				end
				-- stamped so the client motion driver knows which pack id to animate
				-- without having to look the mutation up again
				if model:IsA("Model") or model:IsA("BasePart") then
					model:SetAttribute("PippoId", v.pippo)
				end
				return
			end
		end
	end
	local shift = SHIFTS[v.shift or "none"]
	local mat = v.material
	for _, p in ipairs(partsOf(model)) do
		-- the part is passed as well as its colour: the pack's noise-driven shifts
		-- (Diamond facets, Sandy grain, Frozen frost) hash it for a stable per-part
		-- value. Every older shift ignores the second argument, so this is additive.
		if shift then p.Color = shift(p.Color, p) end
		if mat then
			if mat.material then p.Material = mat.material end
			if mat.reflectance then p.Reflectance = mat.reflectance end
			-- TRANSPARENCY ONLY ON PARTS THAT ALREADY RENDER. The pack's `glass` class
			-- carries Transparency .32, and writing that blindly would turn the
			-- invisible scaffolding 148 of the 192 models carry -- RootPart,
			-- FakeRootPart, VfxInstance -- into visible boxes hanging around the
			-- creature. That is the exact failure addIceShell shipped once (see
			-- renderedParts above); the 0.9 test is the same guard.
			if mat.transparency and p.Transparency < 0.9 then
				p.Transparency = mat.transparency
			end
		end
		-- AUTHORED SURFACE ART SHIFTS WITH THE BODY (2026-08-14). A Decal/Texture
		-- draws its image at full strength no matter what colour the part under it
		-- is, so a model whose face is a decal -- Secret Pete since the v2 redesign,
		-- where the glasses, eyes and smirk are all painted rather than modelled --
		-- kept a pristine, untouched face while the rest of him went gold, charred
		-- or frozen. Decal.Color3 is a tint multiplier, so pushing it through the
		-- SAME shift moves the artwork with everything else.
		-- Our own FX art is skipped: it is added after this pass with deliberate
		-- palette colours, and clear() + re-apply must not compound a tint onto it.
		if shift then
			local tint = artTint(p.Color)   -- p.Color was shifted just above
			for _, k in ipairs(p:GetChildren()) do
				if k.Name:sub(1, 10) ~= "MutationFX" then
					if k:IsA("Decal") or k:IsA("Texture") then
						k.Color3 = tint
					elseif k:IsA("SurfaceAppearance") then
						k.Color = tint
					end
				end
			end
		end
	end
end

-- Electric: only the SMALLEST visible parts go Neon, so the body keeps its
-- colours and the trim reads as live wiring.
local function applyTrimNeon(model, v)
	local parts = renderedParts(model)
	table.sort(parts, function(a, b)
		local sa, sb = a.Size, b.Size
		return (sa.X * sa.Y * sa.Z) < (sb.X * sb.Y * sb.Z)
	end)
	-- SKIP THE CONFETTI (2026-08-15). "Smallest" taken literally finds decorative
	-- crumbs, not trim: on Secret Pete the bottom of this list is four soap suds
	-- and a glasses temple hook, so the live-wiring read was a lit bar of soap.
	-- Anything far below the median part is detail nobody can see at body scale;
	-- filter it out first, then take the smallest of what genuinely remains.
	local med = parts[math.max(1, math.floor(#parts / 2))]
	local medVol = med and (med.Size.X * med.Size.Y * med.Size.Z) or 0
	local eligible = {}
	for _, p in ipairs(parts) do
		if (p.Size.X * p.Size.Y * p.Size.Z) >= medVol * 0.08 then
			eligible[#eligible + 1] = p
		end
	end
	if #eligible < 2 then eligible = parts end
	local n = math.clamp(math.floor(#eligible * 0.2), 3, 24)
	for i = 1, math.min(n, #eligible) do
		eligible[i].Material = Enum.Material.Neon
		eligible[i].Color = v.palette.primary
	end
end

-- Electric's STATIC bolt cage: current arcing up and around the body. The
-- client's limb arcs (MutationMotionClient) crackle and re-target, but they only
-- exist inside the 60-stud animation band and never run at all in a
-- ViewportFrame thumbnail or an edit-time still, so Electric needs a permanent
-- read too. CurveSize bows each bolt OUTSIDE the silhouette -- the old arcs'
-- whole problem was running through the model's interior.
local function addArcBolts(model, v)
	local host = hostOf(model)
	if not host then return end
	local cf, size = boxOf(model)
	local spec = v.arcBolts
	local n = spec.count or 5
	local r = math.max(size.X, size.Z) * 0.62
	for i = 1, n do
		local ang = (i - 0.5) * (math.pi * 2 / n)
		local base = cf.Position + Vector3.new(math.cos(ang) * r, -size.Y * 0.46, math.sin(ang) * r)
		-- the top end is rotated round the body, so the bolt spirals rather than
		-- standing as a straight fence post
		local top = cf.Position + Vector3.new(math.cos(ang + 0.9) * r, size.Y * 0.5, math.sin(ang + 0.9) * r)
		local a0 = attachAt(host, base, "MutationFXBoltA" .. i)
		local a1 = attachAt(host, top, "MutationFXBoltB" .. i)
		local b = Instance.new("Beam")
		b.Name = "MutationFXBolt"
		b.Attachment0 = a0
		b.Attachment1 = a1
		b.Color = ColorSequence.new(spec.core or v.palette.primary, spec.color or v.palette.secondary)
		-- NO TEXTURE. The first cut used the aurora curtain strip, which is a soft,
		-- mostly-transparent gradient -- as a lightning bolt it rendered as a faint
		-- smudge you had to hunt for. An untextured Beam is a clean tapered quad,
		-- which is exactly the hard bright arc this wants.
		b.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(1, 0.05),
		})
		b.Width0 = math.max(size.X * 0.085, 0.34)
		b.Width1 = math.max(size.X * 0.04, 0.18)
		-- a single gentle bow OUT from the body; the old +/-1.1r pair was an S-bend
		-- that flung the middle of the bolt well clear of the silhouette
		b.CurveSize0 = r * 0.65
		b.CurveSize1 = -r * 0.45
		b.FaceCamera = true
		-- same daylight lesson as the aurora curtains: full additive blending looks
		-- right in a dark scene and vanishes against this map's lit sky, so blend
		-- these mostly normally and let the colour itself carry the bolt
		b.LightEmission = 0.55
		b.Parent = host
	end
end

-- Demon: best-effort eyes -- small near-black or near-white parts in the top
-- half go Neon red. The pack is inconsistent (voxel ink everywhere), so this
-- caps at 6 parts and quietly does nothing when it finds no candidates.
local function applyNeonEyes(model, v)
	local cf, size = boxOf(model)
	local inv = cf:Inverse()
	local vol = size.X * size.Y * size.Z
	local found = 0
	for _, p in ipairs(renderedParts(model)) do
		if found >= 6 then break end
		local rel = inv * p.CFrame
		local pv = p.Size.X * p.Size.Y * p.Size.Z
		local _, _, val = p.Color:ToHSV()
		if rel.Position.Y > size.Y * 0.15 and pv < vol * 0.0015 and (val < 0.16 or val > 0.92) then
			p.Material = Enum.Material.Neon
			p.Color = v.palette.primary
			found += 1
		end
	end
end

local function addHighlight(model, v)
	local h = Instance.new("Highlight")
	h.Name = "MutationFXHighlight"
	h.Adornee = model
	h.FillColor = v.highlight.fill or Color3.new(1, 1, 1)
	h.FillTransparency = v.highlight.fillTransparency or 1
	h.OutlineColor = v.highlight.outline or Color3.new(1, 1, 1)
	h.OutlineTransparency = v.highlight.outlineTransparency or 0
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = model
end

-- Phase 2: bespoke sprites where they matter, engine textures where they were
-- already right (electric sparks, sandy smoke). All sprites are white and
-- tinted by the emitter's ColorSequence.
-- Sizes stepped up 2026-08-13: the phase-2 values were tuned against the
-- design board's 520px cards and read as dust at world scale -- the owner's
-- own flight past the row registered none of them.
local EMITTER_PRESETS = {
	drip = { texture = A.droplet, size = 0.28, spread = 15, accel = Vector3.new(0, -26, 0), transparency = 0.1 },
	dust = { texture = SMOKE, size = 1.45, spread = 40, accel = Vector3.new(0, 1.5, 0), transparency = 0.55 },
	spark = { texture = SPARKLE, size = 0.3, spread = 180, accel = Vector3.new(0, 0, 0), transparency = 0 },
	snow = { texture = A.snowflake, size = 0.3, spread = 25, accel = Vector3.new(0, -4, 0), transparency = 0.05 },
	star = { texture = A.star, size = 0.45, spread = 180, accel = Vector3.new(0, 0.5, 0), transparency = 0 },
	ember = { texture = A.ember, size = 0.5, spread = 20, accel = Vector3.new(0, 6, 0), transparency = 0 },
	feather = { texture = A.feather, size = 0.55, spread = 35, accel = Vector3.new(0, -1.6, 0), transparency = 0 },
	sparkle = { texture = A.star, size = 0.5, spread = 60, accel = Vector3.new(0, 1, 0), transparency = 0 },
	glint = { texture = A.star, size = 0.6, spread = 10, accel = Vector3.new(0, 0, 0), transparency = 0 },
	confetti = { texture = A.square, size = 0.3, spread = 70, accel = Vector3.new(0, -6, 0), transparency = 0 },
	static = { texture = A.square, size = 0.2, spread = 180, accel = Vector3.new(0, 0, 0), transparency = 0 },
}

local function addEmitters(model, v)
	local host = hostOf(model)
	if not host then return end
	local cf, size = boxOf(model)
	for _, spec in ipairs(v.particles or {}) do
		local preset = EMITTER_PRESETS[spec.kind]
		if preset then
			local origin = cf.Position
			if spec.kind == "ember" or spec.kind == "dust" then
				origin = origin - Vector3.new(0, size.Y * 0.48, 0)
			elseif spec.kind == "drip" then
				origin = origin + Vector3.new(0, size.Y * 0.3, 0)
			elseif spec.kind == "snow" or spec.kind == "feather" then
				origin = origin + Vector3.new(0, size.Y * 0.55, 0)
			end
			local a = attachAt(host, origin, "MutationFXEmit_" .. spec.kind)
			local e = Instance.new("ParticleEmitter")
			e.Name = "MutationFXEmitter"
			e.Texture = preset.texture
			e.Rate = spec.rate or 8
			e.Speed = NumberRange.new((spec.speed or 4) * 0.7, spec.speed or 4)
			e.Lifetime = NumberRange.new((spec.lifetime or 1) * 0.75, spec.lifetime or 1)
			e.Size = NumberSequence.new(spec.size or preset.size)
			e.Transparency = NumberSequence.new(preset.transparency)
			e.SpreadAngle = Vector2.new(preset.spread, preset.spread)
			e.Acceleration = preset.accel
			e.Rotation = NumberRange.new(0, spec.rotation or 0)
			e.RotSpeed = NumberRange.new(-40, 40)
			e.Drag = spec.drag or 0
			e.Color = ColorSequence.new(v.palette.primary, v.palette.secondary)
			e.LightEmission = 0.6 -- 3D-handoff baseline. The old "owner saw nothing" note
			-- blamed glow, but the real cause was attachAt flinging emitters ~220 studs
			-- off-body (fixed above); the +45% size/rate boost is reverted with it.
			e.Parent = a
		end
	end
end

-- ABOVE the body, not inside it (2026-08-18). Parented straight to the host, the
-- lamp sits INSIDE the creature -- often under a stud from its own surfaces -- and at
-- that range the falloff blows them out to white. That, not the material and not the
-- body colour, is what made Diamond and Frozen read as featureless pale blobs through
-- several rounds of recolouring: measured by disabling this single light on a built
-- Diamond, which restored its #e89f6a instantly with nothing else changed.
--
-- Lifted clear of the head it still glows, still tints the ground and still flickers
-- (MutationMotionClient finds it with a RECURSIVE FindFirstChild, so the extra
-- Attachment in the path costs nothing), but the creature keeps its own shading.
local function addLight(model, v)
	local host = hostOf(model)
	if not host then return end
	local cf, size = boxOf(model)
	local a = attachAt(host, cf.Position + Vector3.new(0, size.Y * 0.62, 0), "MutationFXLightPoint")
	local l = Instance.new("PointLight")
	l.Name = "MutationFXLight"
	l.Color = v.light.color
	l.Brightness = v.light.brightness
	l.Range = v.light.range
	l.Shadows = false
	l.Parent = a
end

-- Body-hugging ice (2026-08-13 owner feedback: "it should be outlines their
-- body", replacing the bounding cube). The shell is glass CLONES of the
-- body's largest parts, grown ~12% about their own centres, so the ice reads
-- as a coat the creature is frozen INSIDE rather than a box it stands in.
-- Capped at the biggest 60 parts: those carry the silhouette; cloning all
-- 1400 of a Valanga would double its part count for detail nobody sees
-- through the frost anyway.
local ICE_SHELL_CAP = 60
local function addIceShell(model, v)
	if model:IsA("BasePart") then
		-- placeholder cube: one grown glass copy is exactly right
		local shell = model:Clone()
		shell:ClearAllChildren()
		shell.Name = "MutationFXShellPart"
		shell.Size = model.Size * 1.12
		shell.Material = Enum.Material.Glass
		shell.Color = v.palette.primary
		shell.Transparency = 0.6
		shell.Reflectance = 0.12
		shell.CanCollide = false
		shell.CanQuery = false
		shell.CanTouch = false
		shell.CastShadow = false
		shell.Anchored = true
		shell.Parent = model.Parent
		return
	end
	-- rendered only: cloning an invisible part into glass is how this grew a crate
	local parts = renderedParts(model)
	table.sort(parts, function(a, b)
		local sa, sb = a.Size, b.Size
		return (sa.X * sa.Y * sa.Z) > (sb.X * sb.Y * sb.Z)
	end)
	local holder = Instance.new("Model")
	holder.Name = "MutationFXShell"
	for i = 1, math.min(ICE_SHELL_CAP, #parts) do
		local src = parts[i]
		-- CLONE the source, never Instance.new("Part") (2026-08-18). 149 of the 192
		-- brainrot models are built from MeshParts, and a fresh Part given a MeshPart's
		-- Size is that mesh's BOUNDING BOX -- so the "body-hugging ice" this function
		-- exists to make came out as a glass CRATE around the creature on three quarters
		-- of the roster. It only ever looked right on the plain-Part models (Secret Pete
		-- is one), which is how it survived review. Cloning keeps the silhouette.
		local shell = src:Clone()
		shell:ClearAllChildren()            -- drop attachments, decals, SurfaceAppearance
		if shell:IsA("MeshPart") then
			shell.TextureID = ""            -- a property, not a child: the creature's own
		end                                 -- skin showing through the ice reads as grime
		shell.Name = "MutationFXShellPart"
		-- Tightened 1.12 -> 1.07 and thinned 0.62 -> 0.68 (2026-08-18). Now the shell
		-- follows the real mesh instead of a bounding box, 12% growth read as a bloated
		-- second body floating off the creature rather than a coat frozen onto it.
		shell.Size = src.Size * 1.07 + Vector3.new(0.03, 0.03, 0.03)
		shell.CFrame = src.CFrame
		shell.Material = Enum.Material.Glass
		shell.Color = v.palette.primary
		shell.Transparency = 0.68
		shell.Reflectance = 0.12
		shell.Anchored = true
		shell.CanCollide = false
		shell.CanQuery = false
		shell.CanTouch = false
		shell.CastShadow = false
		shell.Parent = holder
	end
	holder.Parent = model
	-- frozen solid: the idle system reads Motion at adopt (tag + attributes
	-- replicate in one batch, so the client sees this final value) -- a body
	-- bobbing inside its static ice coat would clip through it, and stillness
	-- IS the read the spec wanted anyway ("idle speed x0.85", taken further)
	model:SetAttribute("Motion", "none")
end

local function addHalo(model, v)
	local cf, size = boxOf(model)
	local halo = Instance.new("Part")
	halo.Name = "MutationFXHalo"
	halo.Shape = Enum.PartType.Cylinder
	local d = math.clamp(size.X * 0.55, 1.2, 6)
	halo.Size = Vector3.new(0.18, d, d)
	halo.CFrame = CFrame.new(cf.Position + Vector3.new(0, size.Y * 0.5 + (v.halo.lift or 1.2), 0))
		* CFrame.Angles(0, 0, math.rad(90))
	halo.Material = Enum.Material.Neon
	halo.Color = v.palette.secondary
	halo.Transparency = 0.25
	halo.Anchored = true
	halo.CanCollide = false
	halo.CanQuery = false
	halo.CanTouch = false
	halo.CastShadow = false
	halo.Parent = model:IsA("BasePart") and model.Parent or model
end

-- Angel's god rays: thin vertical gold beams rising around the body, the
-- terminal-rung read the base spec was missing (owner-approved boost)
local function addGodRays(model, v)
	local host = hostOf(model)
	if not host then return end
	local cf, size = boxOf(model)
	local r = math.max(size.X, size.Z) * 0.62
	for i = 1, v.godRays.count do
		local ang = (i - 0.5) * (math.pi * 2 / v.godRays.count)
		local base = cf.Position + Vector3.new(math.cos(ang) * r, -size.Y * 0.4, math.sin(ang) * r)
		local a0 = attachAt(host, base, "MutationFXRayA" .. i)
		local a1 = attachAt(host, base + Vector3.new(0, size.Y * 1.15, 0), "MutationFXRayB" .. i)
		local b = Instance.new("Beam")
		b.Name = "MutationFXRay"
		b.Attachment0 = a0
		b.Attachment1 = a1
		b.Color = ColorSequence.new(v.godRays.color)
		b.Texture = A.auroraStrip
		b.TextureMode = Enum.TextureMode.Stretch
		b.TextureSpeed = 0.35
		b.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(0.75, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		b.Width0 = 1.1
		b.Width1 = 0.4
		b.FaceCamera = true
		b.LightEmission = 0.9
		b.Parent = host
	end
end

-- A CURTAIN THAT WRAPS (2026-08-15, owner: "make the electric and aurora
-- mutation look way better"). This used to build three ribbons on ONE flat
-- plane at +Z -- and since every model fronts -Z, that put the entire light
-- show directly behind the body, invisible from the one angle a player ever
-- approaches from. Aurora consequently rendered as a plain darkened block.
-- The ribbons now sweep an arc around the back and out past both shoulders and
-- rise clear of the head, so the curtain reads from everywhere but dead astern.
-- Names are unchanged: MutationMotionClient's ribbonDrift finds them by name.
local function addAuroraRibbons(model, v)
	local host = hostOf(model)
	if not host then return end
	local cf, size = boxOf(model)
	local colours = v.auroraRibbons.colors
	local n = math.max(v.auroraRibbons.count or #colours, 1)
	local arc = math.rad(v.auroraRibbons.arc or 210)
	-- pushed out past the shoulders so the curtains FRAME the body instead of
	-- hanging on it -- overlapping wide ribbons at close radius just stack into
	-- one green fog and you lose the bands entirely
	local r = math.max(size.X, size.Z) * 0.88
	local w = math.max(size.X, 3)
	for i = 1, n do
		-- SYMMETRIC, COOLEST ON THE OUTSIDE. Cycling the palette put green (the
		-- first colour) on the outermost curtains, and this map is a green forest --
		-- those bands disappeared straight into the treeline. Ordering by distance
		-- from the centre puts the last palette entry (violet) on the edges, where
		-- it has something to contrast against, and keeps green in the middle where
		-- the body backs it.
		local mid = (n + 1) / 2
		local dist = (mid > 1) and (math.abs(i - mid) / (mid - 1)) or 0
		local colour = colours[math.clamp(1 + math.floor(dist * (#colours - 1) + 0.5), 1, #colours)]
		-- theta measured from the model's BACK (+Z), fanning both ways
		local frac = (n == 1) and 0.5 or ((i - 1) / (n - 1))
		local theta = -arc / 2 + arc * frac
		local base = cf.Position + Vector3.new(math.sin(theta) * r, 0, math.cos(theta) * r)
		local a0 = attachAt(host, base - Vector3.new(0, size.Y * 0.45, 0), "MutationFXRibbonA" .. i)
		-- well clear of the head: the top half of each curtain then reads against
		-- SKY rather than against this map's treeline, which is the same green the
		-- curtains are and swallowed them whole
		local a1 = attachAt(host, base + Vector3.new(0, size.Y * 1.85, 0), "MutationFXRibbonB" .. i)
		local b = Instance.new("Beam")
		b.Name = "MutationFXRibbon"
		b.Attachment0 = a0
		b.Attachment1 = a1
		b.Color = ColorSequence.new(colour)
		-- phase 2: the curtain sprite + a slow TextureSpeed is the spec's own
		-- "textureSpeed 0.2" drift -- real movement, not just width breathing
		b.Texture = A.auroraStrip
		b.TextureMode = Enum.TextureMode.Stretch
		b.TextureLength = 1
		b.TextureSpeed = 0.2
		-- fades at BOTH ends: a band hanging in the air, not a solid slab planted
		-- in the ground (the old ramp was opaque at the base and faded out at the
		-- top, which is upside down for a curtain and killed the towering read)
		b.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.08),
			NumberSequenceKeypoint.new(0.75, 0.14),
			NumberSequenceKeypoint.new(1, 1),
		})
		b.Width0 = w * (0.55 / math.sqrt(n))
		b.Width1 = w * (0.85 / math.sqrt(n))
		b.FaceCamera = true
		-- LOW LightEmission ON PURPOSE. Additive blending (1.0) is what an aurora
		-- "should" be, but this game is a bright daytime map: additive bands simply
		-- washed out against a lit sky and read as green fog. Blending them mostly
		-- normally keeps them as distinct COLOURED CURTAINS in daylight, which is
		-- the read that was missing.
		b.LightEmission = 0.35
		b.Parent = host
	end
end

-- Celestial: a tilted ring drawn as two half-circle beams between opposed
-- attachments on a spinnable holder; the client rotates the holder.
local function addOrbitRing(model, v)
	local cf, size = boxOf(model)
	local holder = Instance.new("Part")
	holder.Name = "MutationFXRing"
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.Transparency = 1
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CFrame = CFrame.new(cf.Position) * CFrame.Angles(math.rad(v.orbitRing.tilt or 20), 0, 0)
	holder.Parent = model:IsA("BasePart") and model.Parent or model
	local r = math.max(size.X, size.Z) * 0.72
	local a = Instance.new("Attachment")
	a.Position = Vector3.new(-r, 0, 0)
	a.Parent = holder
	local b = Instance.new("Attachment")
	b.Position = Vector3.new(r, 0, 0)
	b.Parent = holder
	for k = 1, 2 do
		local beam = Instance.new("Beam")
		beam.Name = "MutationFXRingBeam"
		beam.Attachment0 = k == 1 and a or b
		beam.Attachment1 = k == 1 and b or a
		beam.CurveSize0 = r * 1.35
		beam.CurveSize1 = r * 1.35
		beam.Color = ColorSequence.new(v.orbitRing.color)
		beam.Transparency = NumberSequence.new(0.12)
		beam.Width0 = 0.42
		beam.Width1 = 0.42
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.Parent = holder
	end
end

-- Rainbow: flat neon ring at the feet, spun by the client
local function addGroundRing(model, v)
	local cf, size = boxOf(model)
	local ring = Instance.new("Part")
	ring.Name = "MutationFXGroundRing"
	ring.Shape = Enum.PartType.Cylinder
	local d = math.max(size.X, size.Z) * 1.25
	ring.Size = Vector3.new(0.12, d, d)
	ring.CFrame = CFrame.new(cf.Position - Vector3.new(0, size.Y * 0.5 - 0.1, 0))
		* CFrame.Angles(0, 0, math.rad(90))
	ring.Material = Enum.Material.Neon
	ring.Color = v.palette.primary
	ring.Transparency = 0.3
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = model:IsA("BasePart") and model.Parent or model
end

-- Wet ripple / Sandy dust pool: a thin invisible plate at the feet carrying a
-- tinted top-face Decal. Wet's is pulsed (scale + fade) by the motion driver;
-- Sandy's just sits there.
local function addGroundDecal(model, v)
	local cf, size = boxOf(model)
	local d = math.max(size.X, size.Z) * 1.6
	local plate = Instance.new("Part")
	plate.Name = "MutationFXGroundDecal"
	plate.Size = Vector3.new(d, 0.05, d)
	plate.CFrame = CFrame.new(cf.Position - Vector3.new(0, size.Y * 0.5 - 0.06, 0))
	plate.Transparency = 1
	plate.Anchored = true
	plate.CanCollide = false
	plate.CanQuery = false
	plate.CanTouch = false
	plate.CastShadow = false
	local decal = Instance.new("Decal")
	decal.Name = "MutationFXGroundDecalFace"
	decal.Face = Enum.NormalId.Top
	decal.Texture = v.groundDecal.kind == "ripple" and A.ripple or A.dustpool
	decal.Color3 = v.palette.primary
	decal.Transparency = v.groundDecal.kind == "ripple" and 0.35 or 0.25
	decal.Parent = plate
	plate.Parent = model:IsA("BasePart") and model.Parent or model
end

-- Glitched: scanline bars tiled straight onto the body's side faces (a shell
-- box was tried first and read as a floating hologram crate -- it wraps the
-- T-pose arms, so most of it is scanlines hanging in open air). The client
-- slides OffsetStudsV so the bars run down the model.
local function addScanTex(model, v)
	local parts = {}
	if model:IsA("BasePart") then
		parts[1] = model
	else
		-- Transparency guard: a Texture renders on a part even at Transparency 1, so
		-- without this the bars tile onto invisible roots and hang in open air.
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name:sub(1, 10) ~= "MutationFX" and d.Transparency < 0.9 then
				parts[#parts + 1] = d
			end
		end
		table.sort(parts, function(a, b)
			return a.Size.X * a.Size.Y * a.Size.Z > b.Size.X * b.Size.Y * b.Size.Z
		end)
	end
	local faces = { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }
	for i = 1, math.min(#parts, 10) do
		local p = parts[i]
		for _, face in ipairs(faces) do
			local tex = Instance.new("Texture")
			tex.Name = "MutationFXScanTex"
			tex.Face = face
			tex.Texture = A.scanline
			tex.Color3 = v.palette.primary
			tex.Transparency = 0.5
			tex.StudsPerTileU = math.max(p.Size.X, p.Size.Z, 0.8) * 1.2
			tex.StudsPerTileV = 2.4
			tex.Parent = p
		end
	end
end

-- Celestial: the spec's galaxy skin. SurfaceAppearance needs MeshParts, which
-- these voxel bodies aren't, so the starfield tiles onto the largest parts as
-- Texture instances instead; the client scrolls the offsets (spec's 0.05).
local function addGalaxyTex(model, v)
	local parts = {}
	if model:IsA("BasePart") then
		parts[1] = model
	else
		-- same Transparency guard as addScanTex: an invisible root would otherwise wear
		-- a starfield and read as a galaxy-textured box floating beside the creature
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name:sub(1, 10) ~= "MutationFX" and d.Transparency < 0.9 then
				parts[#parts + 1] = d
			end
		end
		table.sort(parts, function(a, b)
			return a.Size.X * a.Size.Y * a.Size.Z > b.Size.X * b.Size.Y * b.Size.Z
		end)
	end
	local spec = v.galaxyTex
	local faces = { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left,
		Enum.NormalId.Right, Enum.NormalId.Top }
	for i = 1, math.min(#parts, spec.maxParts or 8) do
		for f = 1, math.min(#faces, spec.faces or 5) do
			local tex = Instance.new("Texture")
			tex.Name = "MutationFXGalaxyTex"
			tex.Face = faces[f]
			tex.Texture = A.galaxy
			tex.Transparency = spec.transparency or 0.35
			tex.StudsPerTileU = 4
			tex.StudsPerTileV = 4
			tex.Parent = parts[i]
		end
	end
end

----------------------------------------------------------------- public api
-- Strip anything a previous call left behind so this is safe to re-apply.
-- Also clears the legacy band-system names, for models mid-migration.
function M.clear(host)
	local root = host
	if host:IsA("BasePart") and host.Parent then root = host end
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name:sub(1, 10) == "MutationFX"
		or d.Name == "MutationLight" or d.Name == "MutationAura"
		or d.Name == "MutationMotes" or d.Name == "MutationGlow" then
			d:Destroy()
		end
	end
end

-- model may be a Model or a single BasePart (the placeholder cube).
-- Returns true if anything was applied.
function M.apply(model, mutationName)
	if not mutationName then return false end
	local v = Visuals.For(mutationName)
	if not v then return false end

	M.clear(model)

	applyShiftAndMaterial(model, v)
	if v.rainbowBody then applyRainbowBody(model, v) end
	if v.trimNeon then applyTrimNeon(model, v) end
	if v.arcBolts then addArcBolts(model, v) end
	if v.neonEyes then applyNeonEyes(model, v) end
	if v.highlight then addHighlight(model, v) end
	addEmitters(model, v)
	if v.light then addLight(model, v) end
	if v.iceShell then addIceShell(model, v) end
	if v.halo then addHalo(model, v) end
	if v.godRays then addGodRays(model, v) end
	if v.auroraRibbons then addAuroraRibbons(model, v) end
	if v.orbitRing then addOrbitRing(model, v) end
	if v.groundRing then addGroundRing(model, v) end
	if v.groundDecal then addGroundDecal(model, v) end
	if v.scanShell then addScanTex(model, v) end
	if v.galaxyTex then addGalaxyTex(model, v) end

	-- handshake for MutationMotionClient (hue cycles, flickers, bobs, spins,
	-- strobes, LOD). The "Mutation" attribute is set by the spawner for placed
	-- models; display clones get it here so the reveal animates identically.
	if model:GetAttribute("Mutation") == nil then
		model:SetAttribute("Mutation", mutationName)
	end
	CollectionService:AddTag(model, "MutationBody")

	return true
end

return M
