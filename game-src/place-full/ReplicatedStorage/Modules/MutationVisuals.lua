-- MutationVisuals: the per-mutation LOOK table, from the "Roblox brainrot 3d
-- mutations" handoff (2026-08-12 -- the 3D revision, values judged on a live
-- three.js stage instead of 520px cards; built in Claude Design with the
-- game's own synced HUD kit, so plate chrome matches UIKit tokens by birth).
-- Particle rates/sizes are that spec's 3D baselines: the earlier +40-50%
-- "loudness pass" is reverted -- it compensated for the attachAt displacement
-- bug in MutationFX (emitters spawning ~220 studs off-body), not real dust.
--
-- DATA ONLY. Economy (Mult/Chance/Rarity/rolls) stays in MutationConfig; this
-- file is what a mutation LOOKS like: body treatment, effect stack, nameplate
-- pill. MutationFX (server, static instances) and MutationMotionClient (the
-- one shared animation driver + LOD) both read it.
--
-- Deltas from the handoff, all owner-decided 2026-08-13:
--   * FOG DROPPED -- the game has 12 mutations; "Fog" is a weather EVENT that
--     grants Wet. Its look (transparency + smoke, no outline) is shelved.
--   * The spec's tier column and multipliers are IGNORED -- the real ladder
--     lives in MutationConfig (Golden is rung 1, Angel is rung 12 terminal).
--     Looks are per-mutation IDENTITIES, not a tier costume.
--   * Rainbow's hue ramp uses the game's own tile-ring ramp (the spec demands
--     ring parity, and its listed hexes drifted from the shipped ring).
--   * Sounds ship in phase 2 with the uploaded-asset round.
--
-- Field notes:
--   shift    "none" | "warm" | "desat" | "brighten" | "darken55" | "darken18"
--            | "char" | "gold" | "white"   -- per-part colour TRANSFORMS, never
--            a flatten (Pete keeps his 47-part readability). There is no longer
--            any exception: Rainbow used to flatten the body to one cycling
--            colour and that is exactly why it read as a red blob -- it now uses
--            rainbowBody, a per-part spectrum, and its shift is "none".
--   motion   what MutationMotionClient must drive; absent = fully static.
--   plate    nameplate pill fill (ordered stops, top->bottom unless angle set).

local Visuals = {}

-- Phase 2 (2026-08-13): bespoke particle/beam sprites, generated white-on-
-- transparent (emitters tint them) and uploaded from the prohacks_sorry
-- account over the local-HTTP route -- the same pipeline as the HUD icons in
-- UIKit.Tokens. Re-upload recipe lives there too.
Visuals.Assets = {
	star = "rbxassetid://84048598683079",
	feather = "rbxassetid://121330432671704",
	ember = "rbxassetid://115980710506942",
	square = "rbxassetid://72223365334126",
	snowflake = "rbxassetid://93283645765914",
	droplet = "rbxassetid://136286381988530",
	auroraStrip = "rbxassetid://81147858925742",
	-- 3D-handoff polish round (2026-08-12, same PIL + local-HTTP pipeline):
	ripple = "rbxassetid://93801015805275", -- white rings, tinted by Decal.Color3
	dustpool = "rbxassetid://130749951060233", -- soft white blob, tinted tan
	scanline = "rbxassetid://120140182446165", -- ragged white bars, tiles vertically
	galaxy = "rbxassetid://110754188366473", -- seamless starfield, NOT tintable
}

local function c3(hex)
	return Color3.fromHex(hex)
end

--[[ ============ THE PIPPO OLIVARDINO PACK (2026-08-19) ============
Claude Design shipped a 12-mutation pack (`pippo_mutations.js`) whose names,
ORDER and rarity ladder line up one-for-one with the twelve already in
MutationConfig -- Gold through Angel, weakest to strongest. So this is a
retune of the twelve looks, not a new roster.

What came across from the pack, per mutation:
  * the BODY TRANSFORM, as its own `shift` (see the SHIFTS block in MutationFX,
    where each one is the pack's own style() arithmetic);
  * the SHADING CLASS, via the pack's own CLASSES -> Roblox table:
        solid -> Plastic, T 0,   R 0        rough -> Sand,   T 0,   R 0
        metal -> Metal,   T 0,   R .25      glass -> Glass,  T .32, R .2
        wet   -> Glass,   T 0,   R .3       glow  -> Neon,   T 0,   R 0
  * the glow / prop colours quoted on each row below.

>>> `pippo` IS NOW THE AUTHORITY, NOT `shift`. <<<
Each row carries the pack's own mutation id. MutationFX hands that to PippoSkin,
which calls the PACK MODULE'S OWN style() and glowFn() with the brainrot's colour
written into its palette -- so the arithmetic is the pack's, not a transcription
of it. `shift` is kept as the fallback for when PippoMutations is unavailable,
and as the still-image approximation; it cannot express glowFn at all, which is
why the first port read as a flat recolour.

>>> THE PACK'S MATERIALS WERE TRIED, AND FIVE ARE REVERTED. <<<
The pack is authored against a dark three.js stage. This map is a bright daytime
skybox, and the pack's `glass` class -- Transparency 0.32 -- leaves a creature
half see-through, so what remains on screen is a pale ghost inside its own
outline. That is the failure this file had ALREADY RECORDED TWICE before the pack
arrived, and the owner named it again on sight: "these are not the models".
Shipped values restored:
     Diamond   SmoothPlastic R.12   (pack wanted Glass T.32 R.2)
     Frozen    Ice R.18             (pack wanted Glass T.32 R.2)
     Wet       SmoothPlastic R.15   (pack wanted Glass R.3)
     Glitched  ForceField           (pack wanted Plastic -- but the ghost IS that one)
     Rainbow   Neon                 (pack wanted Plastic)

EVERYTHING ELSE FROM THE PACK STANDS: all twelve colour transforms, the glow
composite, the animation descriptors, the add-on geometry. Only these five
material lines are ours, and each is one line to change back. ]]

Visuals.ByName = {
	Wet = {
		palette = { primary = c3("5BC8F5"), secondary = c3("0E7FC6"), accent = c3("BFEBFF") },
		medallion = c3("3FA9F5"),
		-- Reflectance cut from 0.35 (2026-08-18, with the Diamond pass). Wet has no
		-- colour shift at all -- the body is supposed to be the creature, just sodden --
		-- but 0.35 mirrors this map's bright daytime skybox over a third of every
		-- surface, so the creature bleached to pale grey anyway. Wet reads through the
		-- drips and the ripple at its feet; the sheen only has to suggest, not dominate.
		-- PACK SAYS Glass R.3; SHIPPED VALUE RESTORED (2026-08-19). Glass frosts over
		-- whatever colour sits under it, and against this map's bright skybox the
		-- creature stops reading as itself.
		material = { material = Enum.Material.SmoothPlastic, reflectance = 0.15 },
		shift = "pWet", pippo = "wet",
		highlight = nil,
		particles = { { kind = "drip", rate = 6, speed = 12, lifetime = 0.8 } },
		light = nil,
		groundDecal = { kind = "ripple" }, -- spec: ripple at the base, 2.4s loop
		motion = { ripplePulse = 2.4 },
		plate = { stops = { "7FD8F8", "0E7FC6" } },
	},
	Sandy = {
		palette = { primary = c3("EFC978"), secondary = c3("B98338"), accent = c3("6E4B1C") },
		medallion = c3("C9A05A"),
		-- PACK: cls `rough` -> Sand. Already matched; only the shift changes.
		material = { material = Enum.Material.Sand, reflectance = 0 },
		shift = "pSandy", pippo = "sandy",
		highlight = nil,
		particles = { { kind = "dust", rate = 10, speed = 3, lifetime = 1.6, drag = 4, rotation = 90 } },
		light = nil,
		groundDecal = { kind = "dustpool" }, -- spec: static tan dust pool at the feet
		plate = { stops = { "EFC978", "A87B3C" } },
	},
	Electric = {
		palette = { primary = c3("FFE94A"), secondary = c3("35D6FF"), accent = c3("1B2BFF") },
		medallion = c3("FFE94A"),
		-- PACK: cls `metal` -> Metal, Reflectance .25, over a near-black chrome body.
		-- trimNeon stays: the pack lights its arcs per-voxel, which has no equivalent
		-- on an authored model, so the neon trim keeps carrying that read.
		material = { material = Enum.Material.Metal, reflectance = 0.25 },
		shift = "pElectric", pippo = "electric",
		-- TRIM NEON IS OFF under the pack (2026-08-19). It runs after the body pass
		-- and forces the smallest visible parts to neon yellow -- which was the right
		-- call when the body was left unshifted, but a brainrot only has a handful of
		-- parts, so "the smallest" is most of it: measured on Tung it repainted every
		-- visible part #FFE94A and buried the pack's near-black chrome entirely.
		-- The arcs are carried by arcBolts below, which is where they belong.
		trimNeon = false,
		-- 2026-08-15 (owner: "make the electric and aurora mutation look way
		-- better"). Electric was the quietest body on the row and every part of it
		-- was under-scaled: the two limb arcs were 0.12 studs wide -- a hairline on
		-- a 9-stud body -- and were strung between part CENTRES, so most of them ran
		-- INSIDE the model where nothing shows; trimNeon lit four soap suds and a
		-- glasses hook; and a 0.85 fill over an unshifted body left only a faint rim.
		-- The arcs now bow OUTSIDE the silhouette (see MutationMotionClient), the
		-- static bolt cage below means he still reads in stills and in viewport
		-- thumbnails where no motion driver runs, and the light/sparks carry.
		-- The fill stays FAINT on purpose: pushed opaque it floods the body yellow
		-- and the neon trim, which is also yellow, stops reading against it -- the
		-- exact failure Diamond had. Body normal, trim hot, arcs cool, rim crisp.
		highlight = { fill = c3("FFE94A"), fillTransparency = 0.88, outline = c3("35D6FF"), outlineTransparency = 0 },
		particles = { { kind = "spark", rate = 55, speed = 26, lifetime = 0.45, size = 0.55 } },
		light = { color = c3("35D6FF"), brightness = 3.4, range = 20 },
		arcBolts = { count = 5, color = c3("35D6FF"), core = c3("FFE94A") },
		motion = { lightFlicker = 0.22, limbBeams = 6, beamRestep = 0.06, plate = "flicker" },
		plate = { stops = { "FFE94A", "35D6FF" }, animation = "flicker" },
	},
	Frozen = {
		palette = { primary = c3("DFF7FF"), secondary = c3("6FC8EC"), accent = c3("2A7BA8") },
		medallion = c3("6FC8EC"),
		-- ENCASED IN ice, not MADE OF glass (2026-08-18). Glass at 0.5 reflectance turned
		-- the body itself half see-through and mirrored the skybox over whatever colour
		-- was left, so the creature dissolved and only the shell read. Ice is opaque and
		-- frosted: the body stays the creature, and iceShell below is what encases it --
		-- which is the division of labour the shell was added for in the first place.
		-- PACK SAYS Glass T.32 R.2; SHIPPED VALUE RESTORED (2026-08-19). Transparency
		-- 0.32 left the brainrot half see-through -- a pale ghost inside its own
		-- outline, which is the owner's "these are not the models". Ice is opaque and
		-- frosted: the creature stays the creature and iceShell encases it.
		material = { material = Enum.Material.Ice, reflectance = 0.18 },
		shift = "pFrozen", pippo = "frozen",
		highlight = { fill = c3("DFF7FF"), fillTransparency = 0.82, outline = c3("6FC8EC") },
		particles = { { kind = "snow", rate = 8, speed = 2, lifetime = 2.5, drag = 2 } },
		-- Dimmed 1.0 -> 0.45 (2026-08-18). MutationFX now lifts the lamp clear of the
		-- head, but range still covers the whole creature, and a PALE body has no
		-- headroom -- it clips to white long before a dark or neon one would. The loud
		-- rungs (Electric, Demon, Angel, Aurora, Celestial, Rainbow) keep their tuned
		-- brightness on purpose: charred, neon and saturated bodies all survive it.
		-- Only Frozen and Diamond are pale enough to be destroyed by their own light.
		light = { color = c3("6FC8EC"), brightness = 0.45, range = 10 },
		iceShell = true,
		plate = { stops = { "DFF7FF", "4AA8D8" } },
	},
	Aurora = {
		palette = { primary = c3("7CFFB2"), secondary = c3("35D6FF"), accent = c3("C08BFF") },
		medallion = c3("7CFFB2"),
		-- PACK: cls `metal` -> Metal, Reflectance .25, over a very dark body.
		material = { material = Enum.Material.Metal, reflectance = 0.25 },
		-- 2026-08-15 (same owner note as Electric). Aurora was a BROWN BLOCK: all
		-- three ribbons were built on one flat plane at +Z and models front -Z, so
		-- the entire light show sat directly behind the body and was invisible from
		-- the only angle a player ever walks up from -- leaving nothing on screen but
		-- a body darkened to 55% value with a half-transparent outline. The ribbons
		-- now WRAP (see MutationFX.addAuroraRibbons) so they read from the front,
		-- which in turn means the body no longer has to be crushed dark to let them
		-- show: darken18 keeps it legible while the curtain still pops.
		shift = "pAurora", pippo = "aurora",
		highlight = { fill = c3("35D6FF"), fillTransparency = 0.82, outline = c3("7CFFB2"), outlineTransparency = 0.1 },
		particles = { { kind = "star", rate = 9, speed = 1.4, lifetime = 2.4 } },
		light = { color = c3("7CFFB2"), brightness = 2.2, range = 18 },
		auroraRibbons = { colors = { c3("7CFFB2"), c3("35D6FF"), c3("C08BFF") }, count = 5, arc = 210 },
		motion = { ribbonDrift = 0.2 },
		plate = { stops = { "7CFFB2", "35D6FF", "C08BFF" }, angle = 120 },
	},
	Celestial = {
		palette = { primary = c3("1B1146"), secondary = c3("9C7BFF"), accent = c3("FFE9A3") },
		medallion = c3("9C7BFF"),
		-- SurfaceAppearance needs MeshParts, which the voxel bodies aren't; the
		-- spec's "texture scroll 0.05" intent ships as tiled Texture instances on
		-- the largest parts, scrolled by the motion driver.
		-- PACK: cls `metal` -> Metal, Reflectance .25, over a night-sky body.
		material = { material = Enum.Material.Metal, reflectance = 0.25 },
		shift = "pCelestial", pippo = "celestial",
		galaxyTex = { faces = 5, maxParts = 8, transparency = 0.35 },
		highlight = { fill = c3("1B1146"), fillTransparency = 0.82, outline = c3("9C7BFF") },
		particles = { { kind = "star", rate = 12, speed = 2, lifetime = 1.5 } },
		light = { color = c3("9C7BFF"), brightness = 2, range = 14 },
		orbitRing = { tilt = 20, seconds = 9, color = c3("9C7BFF") },
		motion = { ringSpin = 9, galaxyScroll = 0.05 },
		plate = { stops = { "9C7BFF", "1B1146" }, glow = "9C7BFF" },
	},
	Demon = {
		palette = { primary = c3("FF3B2F"), secondary = c3("8A1008"), accent = c3("1A0505") },
		medallion = c3("FF3B2F"),
		-- PACK: cls `metal` -> Metal, Reflectance .25, over a charred body.
		material = { material = Enum.Material.Metal, reflectance = 0.25 },
		shift = "pDemon", pippo = "demon",
		neonEyes = true, -- best-effort: small near-black/white upper parts go Neon red
		highlight = { fill = c3("8A1008"), fillTransparency = 0.80, outline = c3("FF3B2F") },
		particles = { { kind = "ember", rate = 18, speed = 4, lifetime = 1.8, rise = 6 } },
		light = { color = c3("FF3B2F"), brightness = 3, range = 16 },
		motion = { lightFlicker = 0.3 },
		plate = { stops = { "FF3B2F", "4A0A0A" }, glow = "FF3B2F" },
	},
	Angel = {
		palette = { primary = c3("FFF6D6"), secondary = c3("FFD24A"), accent = c3("FFFFFF") },
		medallion = c3("FFE9A3"),
		-- PACK: cls `metal` -> Metal, Reflectance .25, over a bleached-gold body.
		material = { material = Enum.Material.Metal, reflectance = 0.25 },
		shift = "pAngel", pippo = "angel",
		highlight = { fill = c3("FFF6D6"), fillTransparency = 0.80, outline = c3("FFD24A") },
		-- phase 2 terminal-tier boost (owner-flagged: the spec under-dressed the
		-- game's rarest mutation vs Demon): gold dust joins the feathers, god
		-- rays join the halo, and the light steps up. Angel now clearly outranks.
		particles = {
			{ kind = "feather", rate = 5, speed = 1.5, lifetime = 2.2, drag = 3, rotation = 40 },
			{ kind = "star", rate = 7, speed = 1, lifetime = 1.8 },
		},
		light = { color = c3("FFF6D6"), brightness = 2.4, range = 20 },
		halo = { lift = 1.2, bobSeconds = 3.2 },
		godRays = { count = 4, color = c3("FFE9A3") },
		motion = { haloBob = 3.2 },
		plate = { stops = { "FFFDF3", "FFD24A" }, glow = "FFF6D6" },
	},
	Golden = {
		palette = { primary = c3("FFD34D"), secondary = c3("E39B0C"), accent = c3("8A5A06") },
		medallion = c3("FFB200"),
		-- PACK: cls `metal` -> Metal, Reflectance .25 (was .55).
		material = { material = Enum.Material.Metal, reflectance = 0.25 },
		shift = "pGold", pippo = "gold",
		highlight = { fill = nil, fillTransparency = 1, outline = c3("E39B0C") },
		particles = { { kind = "sparkle", rate = 4, speed = 1, lifetime = 0.6 } }, -- sparse: the reflection is the read
		light = nil,
		motion = { sheenSweep = 3.4, plate = nil }, -- phase-1 sheen = outline shimmer; texture sweep is phase 2
		plate = { stops = { "FFE87A", "FFC531", "E08A0C" } }, -- UIKit T.gradient.gold, verbatim per spec
	},
	Diamond = {
		palette = { primary = c3("EAFBFF"), secondary = c3("8FE3FF"), accent = c3("3C9FD1") },
		medallion = c3("8FE3FF"),
		-- GLASS DROPPED ENTIRELY (2026-08-18). Reflectance came down first, from 0.7 to
		-- 0.25, and the body colour was loosened to keep the creature's hue -- and it was
		-- STILL a pale ghost on screen, because the wash was never the reflectance: the
		-- Glass material itself frosts over whatever colour sits under it. Measured on
		-- Tung, whose body is #e0813d: the shift produced #f2b991, a clearly warm peach,
		-- and Glass rendered it as cream.
		--
		-- Diamond's identity is SHINE, not whiteness -- so a polished surface keeps the
		-- creature's colour and lets the glint particles and the icy outline carry the
		-- tier. It also keeps Diamond clearly apart from Frozen, which now owns the
		-- frosted Ice look plus the shell.
		--
		-- Reflectance is kept LOW on purpose, and this is the third thing that had to
		-- come down before the body finally read. Reflectance mirrors the SKYBOX, and
		-- this is a bright daytime map -- so 0.35 was still painting most of the creature
		-- with pale sky, the same failure as Glass by a different route. On a dark map
		-- this could go back up; here it cannot.
		-- PACK SAYS Glass T.32 R.2; SHIPPED VALUE RESTORED (2026-08-19), same reason as
		-- Frozen. Diamond's identity is SHINE, not translucency -- a see-through
		-- creature is not a diamond one, it is a missing one.
		material = { material = Enum.Material.SmoothPlastic, reflectance = 0.12 },
		shift = "pDiamond", pippo = "diamond",
		-- 2026-08-15 (owner: "the diamond mutation looks weird, its like a box
		-- around them"). fillTransparency was 0.25 -- a 75%-OPAQUE #EAFBFF wash,
		-- the heaviest fill of all twelve -- laid over a body the "white" shift had
		-- ALREADY desaturated to near-white. The two stacked, every part collapsed
		-- to the same value, and the model read as one featureless pale block with
		-- an outline round it: a box. Golden, the rung below, is outline-only
		-- (fillTransparency = 1) and reads perfectly, which is the tell.
		-- Diamond's identity is Glass + 0.7 reflectance + stillness, NOT the wash,
		-- so the fill drops to a faint icy bloom that still separates it from
		-- Golden's bare outline without erasing the body underneath.
		highlight = { fill = c3("EAFBFF"), fillTransparency = 0.85, outline = c3("8FE3FF") },
		particles = { { kind = "glint", rate = 3, speed = 0.5, lifetime = 0.5 } },
		-- Dimmed 1.5 -> 0.6; same reasoning as Frozen above. This was THE thing keeping
		-- Diamond looking like a white blob across several rounds of recolouring -- the
		-- body was already #e89f6a and the lamp was painting over it.
		light = { color = c3("8FE3FF"), brightness = 0.6, range = 12 },
		-- DIAMOND IS STILL, GOLDEN MOVES -- that contrast is the differentiator.
		-- No motion table on purpose.
		plate = { stops = { "EAFBFF", "3C9FD1" }, glow = "8FE3FF" },
	},
	Rainbow = {
		palette = { primary = c3("FF5252"), secondary = c3("3FA9F5"), accent = c3("A855F7") },
		medallion = c3("FF4D9E"),
		-- PACK SAYS Plastic; SHIPPED VALUE RESTORED (2026-08-19). Neon is what makes
		-- the spectrum carry at pad distance, and unlike the three above it costs the
		-- creature nothing -- the body is opaque either way.
		material = { material = Enum.Material.Neon },
		-- 2026-08-15 (owner: "fix up rainbow too its kinda bad"). shift was "rainbow",
		-- which flattened EVERY part to one #FF5252 -- a single glowing red silhouette
		-- with all its internal detail erased -- and left the actual rainbow to a
		-- highlight the motion driver cycled at 65% opacity on top. One colour at a
		-- time, and plain red anywhere the driver does not run. rainbowBody paints the
		-- whole spectrum down the body instead (MutationFX.applyRainbowBody) and the
		-- client scrolls it, so it is multi-coloured even in a still.
		shift = "none", pippo = "rainbow",
		-- rainbowBody is now redundant -- the pack's own hue ramp does the same job
		-- through PippoSkin, at its own numbers -- but it stays as the fallback for
		-- when the pack module is missing.
		rainbowBody = true,
		highlight = { fill = nil, fillTransparency = 1, outline = c3("FF5252") },
		particles = { { kind = "confetti", rate = 26, speed = 9, lifetime = 1.4 } },
		light = { color = c3("FF4D9E"), brightness = 1.8, range = 16 },
		groundRing = { seconds = 4 },
		-- ramp = the game's own tile-ring ramp (UIKit.Builders.rainbowRing), NOT
		-- the spec's drifted hexes -- ring parity is the spec's own rule #done
		motion = { hueCycle = 4, ringSpin = 4, plate = "hue" },
		plate = { stops = { "FF5252", "FFB200", "7CE04A", "3FA9F5", "A855F7" }, angle = 90, animation = "hue" },
	},
	Glitched = {
		palette = { primary = c3("00FF9C"), secondary = c3("FF00E5"), accent = c3("0B0B0B") },
		medallion = c3("00FF9C"),
		-- FORCEFIELD IS DELIBERATE -- do not "fix" it again. It renders as a near-
		-- invisible energy shell, so a Glitched brainrot is mostly not there, and that
		-- is the intended look: the scanlines, the magenta outline and the static burst
		-- draw the shape instead of the body. It was swapped to nil on 2026-08-18 on the
		-- reasoning that vanishing must be a bug (0 of the 192 models carry a Decal now,
		-- and Secret Pete's face decal had been the only thing masking it until his v3
		-- rebuild made the face geometry) -- and the owner put it straight back. The
		-- ghost IS the mutation. Same for the heavy 0.3 fill: on every other rung that
		-- much wash flattens the body, but here there is barely a body to flatten and
		-- the fill is most of what you actually see.
		-- PACK SAYS Plastic; SHIPPED VALUE RESTORED (2026-08-19). ForceField was an
		-- explicit owner call -- "the ghost IS the mutation" -- and it is the one rung
		-- where vanishing is the intended read rather than the failure.
		material = { material = Enum.Material.ForceField },
		shift = "pGlitched", pippo = "glitched",
		highlight = { fill = c3("00FF9C"), fillTransparency = 0.3, outline = c3("FF00E5") },
		particles = { { kind = "static", rate = 30, speed = 6, lifetime = 0.15, size = 0.2 } },
		light = nil,
		scanShell = true, -- spec: horizontal scanline bars sliding down the model
		-- CFrame tic belongs to BrainrotIdleClient's motion ownership -- phase 2
		-- coordination; phase 1 carries the glitch via highlight strobing.
		motion = { glitchStrobe = 2.2, scanSlide = 1.6, plate = "jitter" },
		plate = { stops = { "00FF9C", "0B0B0B" }, animation = "jitter", extraShadow = true },
	},
}

-- Sanity: every mutation MutationConfig knows must have a look, and vice versa.
-- A missing row would silently render as unmutated, which is exactly the class
-- of drift this assert exists to catch on the next roster change.
local Mutations = require(game:GetService("ReplicatedStorage").Modules.MutationConfig)
for name in pairs(Mutations.ByName) do
	assert(Visuals.ByName[name], "MutationVisuals: no look for mutation '" .. name .. "'")
end
for name in pairs(Visuals.ByName) do
	assert(Mutations.ByName[name], "MutationVisuals: look for unknown mutation '" .. name .. "'")
end

function Visuals.For(name)
	return name and Visuals.ByName[name] or nil
end

-- Plate gradient as a ColorSequence (top->bottom render; the pill's UIGradient
-- sets Rotation from `angle`, default 90 = vertical).
function Visuals.PlateSequence(name)
	local v = Visuals.For(name)
	if not v then return nil end
	local stops = v.plate.stops
	local kp = {}
	for i, hex in ipairs(stops) do
		kp[#kp + 1] = ColorSequenceKeypoint.new((i - 1) / math.max(#stops - 1, 1), c3(hex))
	end
	return ColorSequence.new(kp), (v.plate.angle or 90)
end

return Visuals
