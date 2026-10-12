--[[ ==========================================================================
RockDesign -- the single source of truth for what every rock LOOKS like.
---------------------------------------------------------------------------
MESH-BASED. Each rock's core is one of five AI-generated FACETED meshes
(ReplicatedStorage.RockMeshes: rounded / angular / crystal / flat / chunk),
scaled to the rock's Size and tinted by its Material + Colour. The meshes'
baked textures were stripped, so the Roblox Material's grain and the per-rock
Colour show through -- that is what lets ONE mesh serve many rocks.

Colour lives in RockConfig / RockConfigTundra next to Price/Luck (balance
data). This module is presentation only, keyed by rock Id (never renamed).

--------------------------- THE FX LADDER (2026-08-06) ---------------------
Every rock now names an Fx KIT. A kit is a named bundle of effects, so the
per-rock table stays readable and the ladder escalates on purpose instead of
each rock inventing its own look:

  (none)    bare stone. The first four rocks are meant to feel like rocks.
  dust      faint grit motes. First hint that a rock is worth money.
  gleam     polished: reflectance + a slow sparkle.
  charged   a PointLight and sparkles -- the rock is now clearly powered.
  crystal   charged + orbiting shards.
  cosmic    aura shell + ring + trail + dense motes. End-game valley rocks.
  frost     cold light + frost motes + icy trail. World 2's lower shelf.
  aurora    frost + ring + trail, in aurora colours.
  absolute  everything, turned up. Exactly one rock wears this.

WHERE THE EFFECTS DO AND DO NOT SHOW:
  * thrown rock (ThrowHandler) and Rocco's shelf -- real Workspace parts, so
    lights, particles and trails all render. This is where the kits pay off.
  * the shop card preview -- a ViewportFrame, which renders BaseParts ONLY.
    Lights/emitters/trails are silently ignored there, so every kit keeps a
    PART-BASED component (aura shell, ring, shards) and never relies on
    particles alone to read as special. Costs nothing extra to build.

Particle textures are ENGINE-SHIPPED rbxasset paths, not uploaded ids: an
invented rbxassetid either fails to load or renders something unrelated.
========================================================================== ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local V = Vector3.new
local Mat = Enum.Material
local C3 = Color3.fromRGB

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE   = "rbxasset://textures/particles/smoke_main.dds"

local RockDesign = {}

RockDesign.Default = {
	Mesh = "angular", Size = V(2.0, 1.4, 1.7), Material = Mat.Slate,
	Reflectance = 0, Archetype = "rough",
}

RockDesign.ById = {
	-- ============================ WORLD 1: THE VALLEY ============================
	-- EVERY ROCK NAMES ITS OWN KIT (2026-08-22). They used to share five kits, so
	-- NebulaCore and GalaxyCore were the same spec but for colour, and all seven
	-- cosmic rocks were one look. A kit per rock is what makes the shelf worth
	-- scrolling: each rung is a different SILHOUETTE, not a different tint.
	--
	-- COMMON -- deliberately plain. A pebble that glowed would flatten the ladder.
	Pebble            = { Mesh = "rounded", Size = V(1.8, 0.9, 1.4),  Material = Mat.Pebble,    Reflectance = 0,    Archetype = "rough"   },
	SmoothStone       = { Mesh = "rounded", Size = V(2.0, 1.2, 1.6),  Material = Mat.Sandstone, Reflectance = 0.04, Archetype = "smooth"  },
	-- UNCOMMON -- shape starts doing the talking: proper flat skipping stones.
	FlatSkipper       = { Mesh = "flat",    Size = V(2.8, 0.36, 2.1), Material = Mat.Slate,     Reflectance = 0.02, Archetype = "smooth", Fx = "skim"   },
	SlateDisc         = { Mesh = "flat",    Size = V(3.0, 0.32, 2.3), Material = Mat.Slate,     Reflectance = 0.12, Archetype = "smooth", Fx = "dust"   },
	-- RARE
	GraniteChunk      = { Mesh = "angular", Size = V(2.2, 1.9, 2.0),  Material = Mat.Granite,   Reflectance = 0.02, Archetype = "rough",  Fx = "grit"   },
	RiverGlass        = { Mesh = "flat",    Size = V(2.3, 0.55, 1.9), Material = Mat.Glass,     Reflectance = 0.45, Archetype = "smooth", Fx = "glint"  },
	-- EPIC -- the first rocks with structure hung on them.
	ObsidianShard     = { Mesh = "chunk",   Size = V(2.2, 1.5, 1.5),  Material = Mat.Glass,     Reflectance = 0.35, Archetype = "crystal", Fx = "edge",  Glow = C3(150, 110, 255) },
	BasaltPlate       = { Mesh = "chunk",   Size = V(2.6, 0.75, 2.1), Material = Mat.Basalt,    Reflectance = 0.03, Archetype = "rough",  Fx = "ember", Glow = C3(255, 120, 40) },
	-- LEGENDARY -- from here every rock is visibly powered.
	MeteoriteFragment = { Mesh = "angular", Size = V(2.0, 1.6, 1.9),  Material = Mat.Rock,      Reflectance = 0.06, Archetype = "rough",  Fx = "meteor", Glow = C3(255, 138, 60) },
	StarcastIron      = { Mesh = "chunk",   Size = V(2.1, 1.5, 1.7),  Material = Mat.Metal,     Reflectance = 0.45, Archetype = "metal",  Fx = "forge",  Glow = C3(255, 210, 150) },
	-- MYTHIC
	GoldenRock        = { Mesh = "chunk",   Size = V(2.0, 1.7, 1.8),  Material = Mat.Metal,     Reflectance = 0.55, Archetype = "metal",  Fx = "regal",  Glow = C3(255, 226, 120) },
	PrismaticGeode    = { Mesh = "crystal", Size = V(1.9, 2.1, 1.7),  Material = Mat.Glass,     Reflectance = 0.55, Archetype = "crystal", Fx = "prism" },
	-- SECRET
	VoidstoneShard    = { Mesh = "crystal", Size = V(2.0, 2.2, 1.5),  Material = Mat.Glass,     Reflectance = 0.30, Archetype = "crystal", Fx = "voidfang", Glow = C3(150, 90, 255) },
	-- GOD -- the landmark rock; the only one wearing the brainrot kit.
	BrainrotCore      = { Mesh = "chunk",   Size = V(2.0, 2.0, 2.0),  Material = Mat.Neon,      Reflectance = 0,    Archetype = "core",   Fx = "brainrot" },
	-- END-GAME cosmic ladder: all sell pure luck, so the LOOK is the reward. Each
	-- one is a different astronomical object rather than a differently tinted ball:
	-- a comet has a tail, a quasar has polar jets, a nebula is a cloud with no hard
	-- edge, a pulsar is crossed rings, a galaxy is a flat disc, the singularity is
	-- a caged dark core.
	CometCore         = { Mesh = "rounded", Size = V(1.9, 1.7, 1.8),  Material = Mat.Glass,     Reflectance = 0.45, Archetype = "core",   Fx = "comet",       Glow = C3(140, 210, 255) },
	QuasarStone       = { Mesh = "crystal", Size = V(1.8, 2.3, 1.6),  Material = Mat.Neon,      Reflectance = 0,    Archetype = "core",   Fx = "quasar",      Glow = C3(200, 120, 255) },
	NebulaCore        = { Mesh = "rounded", Size = V(2.1, 2.0, 2.1),  Material = Mat.Neon,      Reflectance = 0,    Archetype = "core",   Fx = "nebula",      Glow = C3(255, 120, 205) },
	PulsarShard       = { Mesh = "crystal", Size = V(2.1, 2.1, 1.6),  Material = Mat.Glass,     Reflectance = 0.40, Archetype = "core",   Fx = "pulsar",      Glow = C3(90, 240, 230) },
	GalaxyCore        = { Mesh = "chunk",   Size = V(2.0, 1.9, 2.0),  Material = Mat.Neon,      Reflectance = 0,    Archetype = "core",   Fx = "galaxy",      Glow = C3(160, 110, 255) },
	CosmosHeart       = { Mesh = "rounded", Size = V(2.0, 1.9, 1.9),  Material = Mat.Neon,      Reflectance = 0,    Archetype = "core",   Fx = "cosmos",      Glow = C3(255, 240, 180) },
	VoidHeart         = { Mesh = "crystal", Size = V(2.1, 2.1, 1.7),  Material = Mat.Glass,     Reflectance = 0.30, Archetype = "core",   Fx = "singularity", Glow = C3(120, 60, 220) },

	-- ========================= WORLD 2: THE FROZEN TUNDRA =========================
	-- FROZEN, NEVER SCI-FI. Ice, glacier and snow surfaces, and the linear detail
	-- (spikes, needles, standing slabs) is Ice rather than Neon so it reads as
	-- frost rather than as a glowing gadget. Only the two top rocks emit at all.
	GlacierShard      = { Mesh = "crystal", Size = V(2.1, 2.2, 1.6),  Material = Mat.Glacier,   Reflectance = 0.35, Archetype = "crystal", Fx = "icebite" },
	FrostbiteCore     = { Mesh = "chunk",   Size = V(2.0, 1.9, 1.9),  Material = Mat.Ice,       Reflectance = 0.40, Archetype = "core",   Fx = "chill"      },
	RimeGeode         = { Mesh = "crystal", Size = V(1.9, 2.3, 1.8),  Material = Mat.Glass,     Reflectance = 0.55, Archetype = "crystal", Fx = "rime"      },
	PermafrostHeart   = { Mesh = "chunk",   Size = V(2.1, 2.0, 2.0),  Material = Mat.Glacier,   Reflectance = 0.25, Archetype = "core",   Fx = "permafrost" },
	AuroraStone       = { Mesh = "crystal", Size = V(2.0, 2.3, 1.7),  Material = Mat.Neon,      Reflectance = 0,    Archetype = "core",   Fx = "auroraveil", Glow = C3(120, 255, 200) },
	BlizzardCore      = { Mesh = "rounded", Size = V(2.1, 2.0, 2.0),  Material = Mat.Snow,      Reflectance = 0.15, Archetype = "core",   Fx = "whiteout"   },
	GlacialMonolith   = { Mesh = "chunk",   Size = V(1.9, 2.5, 1.7),  Material = Mat.Glacier,   Reflectance = 0.20, Archetype = "core",   Fx = "monolith"   },
	AbsoluteZero      = { Mesh = "crystal", Size = V(2.1, 2.2, 1.8),  Material = Mat.Neon,      Reflectance = 0,    Archetype = "core",   Fx = "absolute",  Glow = C3(190, 245, 255) },
}

-- ================================ THE FX KITS ================================
-- Aura / Rings / Shards / Spikes / Belt / Cage are PARTS, so they show in the
-- shop's ViewportFrame too; Light / Motes / Trail only render on the real thrown
-- rock and on Rocco's shelf. EVERY KIT KEEPS AT LEAST ONE PART-BASED COMPONENT
-- from Epic upward -- a kit that is only particles looks identical to a bare
-- stone on the shop card, which is where players actually compare rocks.
--
-- KEEP DECORATION TIGHT. MerchantClient and the shelf FIT the preview to
-- RockDesign.Extents, so anything that flies wide shrinks the stone inside its
-- own card. Orbits and ring radii stay at or under ~0.8 of the core's width;
-- measured, an early 2.1 ring rendered AbsoluteZero ~40% smaller.
--
-- Fields:
--   Aura        scale of the neon rim shell (a RIM, not a shell -- see below)
--   Light       { b = brightness, r = range } PointLight on the core
--   Motes       { tex, rate, size, speed, life, transp } particle emitter
--   Trail       lifetime multiplier for the skip-arc wake
--   Ring        one flat orbital disc, scale of the core's width
--   Rings       several discs { scale, tilt, thick, transp } -- crossed rings
--   Shards      n orbiting chips; ShardSize / ShardOrbit reshape them
--   Spikes      { n, len, thick, transp, axis } radiating FROM the core
--   Belt        { n, radius, size, transp, spread } a ring of small chunks
--   Cage        { n, scale, thick, transp } vertical bars enclosing the core
local KITS = {
	-- ---- bare / near-bare: the first rungs are meant to feel like rocks --------
	skim     = { Motes = { tex = SMOKE,   rate = 2,  size = 0.28, speed = 0.3, life = 0.6, transp = 0.82 } },
	dust     = { Motes = { tex = SMOKE,   rate = 3,  size = 0.35, speed = 0.4, life = 0.7, transp = 0.75 } },
	grit     = { Motes = { tex = SMOKE,   rate = 6,  size = 0.42, speed = 0.5, life = 0.9, transp = 0.68 } },
	glint    = { Motes = { tex = SPARKLE, rate = 5,  size = 0.30, speed = 0.5, life = 0.9, transp = 0.35 } },

	-- ---- EPIC: structure arrives ---------------------------------------------
	-- razor chips lying flat against the stone, not orbiting it
	edge     = { Light = { b = 0.9, r = 8 }, Spikes = { n = 3, len = 0.45, thick = 0.15, transp = 0.15 },
	             Motes = { tex = SPARKLE, rate = 6,  size = 0.30, speed = 0.5, life = 0.9, transp = 0.4 } },
	-- volcanic: warm light, embers drifting UP, a low belt of cooling clinker
	ember    = { Light = { b = 1.6, r = 10 }, Belt = { n = 7, radius = 0.68, size = 0.24, transp = 0.1, spread = 0.10 },
	             Motes = { tex = SMOKE,   rate = 11, size = 0.44, speed = 0.7, life = 1.2, transp = 0.35 } },

	-- ---- LEGENDARY -----------------------------------------------------------
	-- an actual falling rock: the tail is the whole identity, so no ring, no shards
	meteor   = { Aura = 1.08, AuraTransp = 0.90, Light = { b = 2.0, r = 13 }, Trail = 1.5,
	             Motes = { tex = SMOKE,   rate = 16, size = 0.50, speed = 1.1, life = 1.3, transp = 0.30 } },
	-- forged metal: four blunt studs and a shower of sparks
	forge    = { Light = { b = 1.8, r = 12 }, Spikes = { n = 4, len = 0.40, thick = 0.22, transp = 0.05 },
	             Motes = { tex = SPARKLE, rate = 14, size = 0.34, speed = 1.2, life = 0.8, transp = 0.2 } },

	-- ---- MYTHIC --------------------------------------------------------------
	-- one clean gold halo, worn flat like a coin's edge
	regal    = { Aura = 1.09, AuraTransp = 0.90, Light = { b = 2.4, r = 14 }, Ring = 1.14,
	             Motes = { tex = SPARKLE, rate = 13, size = 0.40, speed = 0.7, life = 1.1, transp = 0.2 } },
	-- a geode's interior turned outward: many long thin needles
	prism    = { Aura = 1.10, AuraTransp = 0.90, Light = { b = 2.1, r = 13 },
	             Shards = 7, ShardSize = V(0.13, 0.66, 0.13), ShardOrbit = 0.52,
	             Motes = { tex = SPARKLE, rate = 14, size = 0.42, speed = 0.9, life = 1.1, transp = 0.18 } },

	-- ---- SECRET --------------------------------------------------------------
	-- four heavy fangs, low orbit, violet light
	voidfang = { Aura = 1.12, AuraTransp = 0.88, Light = { b = 2.6, r = 15 },
	             Shards = 4, ShardSize = V(0.26, 0.58, 0.26), ShardOrbit = 0.60,
	             Motes = { tex = SPARKLE, rate = 15, size = 0.46, speed = 0.9, life = 1.2, transp = 0.18 } },

	-- ---- GOD: the landmark ----------------------------------------------------
	brainrot = { Aura = 1.16, AuraTransp = 0.86, Light = { b = 3.4, r = 19 }, Ring = 1.12, Trail = 1.1,
	             Belt = { n = 9, radius = 0.66, size = 0.20, transp = 0.1, spread = 0.16 },
	             Motes = { tex = SPARKLE, rate = 24, size = 0.55, speed = 1.3, life = 1.3, transp = 0.15 } },

	-- ---- END-GAME COSMIC: one astronomical object each ------------------------
	-- COMET: head + tail. No ring and no orbiters on purpose -- the wake is it.
	comet    = { Aura = 1.10, AuraTransp = 0.88, Light = { b = 3.0, r = 17 }, Trail = 2.0,
	             Motes = { tex = SPARKLE, rate = 20, size = 0.48, speed = 1.6, life = 1.5, transp = 0.18 } },
	-- QUASAR: twin polar JETS along one axis, plus a tight equatorial ring.
	quasar   = { Aura = 1.12, AuraTransp = 0.86, Light = { b = 4.2, r = 21 }, Ring = 1.05,
	             Spikes = { n = 2, len = 0.55, thick = 0.16, transp = 0.15, axis = "y" },
	             Motes = { tex = SPARKLE, rate = 22, size = 0.46, speed = 1.4, life = 1.2, transp = 0.15 } },
	-- NEBULA: a CLOUD. Biggest, softest aura in the game; no hard edges at all.
	nebula   = { Aura = 1.34, AuraTransp = 0.82, Light = { b = 3.0, r = 20 },
	             Motes = { tex = SMOKE,   rate = 40, size = 0.95, speed = 0.35, life = 2.6, transp = 0.42 } },
	-- PULSAR: crossed rings and a needle spray -- a lighthouse, not a ball.
	pulsar   = { Aura = 1.10, AuraTransp = 0.88, Light = { b = 4.6, r = 22 },
	             Rings = { { scale = 1.22, tilt = 14, thick = 0.06, transp = 0.40 },
	                       { scale = 1.10, tilt = 82, thick = 0.05, transp = 0.55 } },
	             Shards = 6, ShardSize = V(0.10, 0.60, 0.10), ShardOrbit = 0.50,
	             Motes = { tex = SPARKLE, rate = 26, size = 0.40, speed = 1.5, life = 1.0, transp = 0.12 } },
	-- GALAXY: a flat DISC. One wide shallow ring plus a broad scattered belt.
	galaxy   = { Aura = 1.10, AuraTransp = 0.88, Light = { b = 3.6, r = 20 }, Trail = 1.0,
	             Rings = { { scale = 1.26, tilt = 8, thick = 0.05, transp = 0.42 } },
	             Belt = { n = 14, radius = 0.70, size = 0.17, transp = 0.15, spread = 0.10 },
	             Motes = { tex = SPARKLE, rate = 26, size = 0.50, speed = 0.9, life = 1.6, transp = 0.15 } },
	-- COSMOS: an armillary sphere -- three rings on three different tilts.
	cosmos   = { Aura = 1.14, AuraTransp = 0.86, Light = { b = 4.0, r = 21 }, Trail = 1.1,
	             Rings = { { scale = 1.18, tilt = 10,  thick = 0.06, transp = 0.42 },
	                       { scale = 1.08, tilt = 62,  thick = 0.05, transp = 0.50 },
	                       { scale = 1.12, tilt = 118, thick = 0.05, transp = 0.50 } },
	             Motes = { tex = SPARKLE, rate = 24, size = 0.52, speed = 1.0, life = 1.4, transp = 0.15 } },
	-- SINGULARITY: a DARK core inside a cage, with an accretion ring and a long
	-- wake. The cage is what makes it read as contained rather than as a lamp.
	singularity = { Aura = 1.06, AuraTransp = 0.94, Light = { b = 3.0, r = 18 }, Trail = 1.8,
	             Rings = { { scale = 1.18, tilt = 22, thick = 0.07, transp = 0.35 } },
	             Cage = { n = 6, scale = 1.22, thick = 0.09, transp = 0.25 },
	             Motes = { tex = SPARKLE, rate = 20, size = 0.44, speed = 1.1, life = 1.5, transp = 0.2 } },

	-- ---- WORLD 2: THE FROZEN TUNDRA -------------------------------------------
	-- ICE, NOT NEON, for the linear detail on the lower shelf: these kits pass
	-- ShardMat/SpikeMat so the chips read as frost even though the accent colour
	-- is bright. Only auroraveil and absolute emit real light.
	icebite  = { Light = { b = 1.2, r = 9 },
	             Shards = 2, ShardSize = V(0.20, 0.52, 0.20), ShardOrbit = 0.58, ShardMat = Mat.Ice,
	             Motes = { tex = SPARKLE, rate = 10, size = 0.34, speed = 0.5, life = 1.5, transp = 0.35 } },
	-- ICICLES: five spikes hanging off it, Ice material, no orbit at all
	chill    = { Light = { b = 1.6, r = 11 },
	             Spikes = { n = 5, len = 0.42, thick = 0.16, transp = 0.10, mat = Mat.Ice },
	             Motes = { tex = SPARKLE, rate = 13, size = 0.38, speed = 0.6, life = 1.6, transp = 0.30 } },
	-- HOARFROST: a dense crown of fine needles
	rime     = { Aura = 1.08, AuraTransp = 0.92, Light = { b = 1.9, r = 12 },
	             Shards = 8, ShardSize = V(0.10, 0.58, 0.10), ShardOrbit = 0.54, ShardMat = Mat.Ice,
	             Motes = { tex = SPARKLE, rate = 16, size = 0.36, speed = 0.6, life = 1.7, transp = 0.28 } },
	-- PERMAFROST: heavy, slow, buried. Thick aura, one low ring, drifting motes.
	permafrost = { Aura = 1.22, AuraTransp = 0.84, Light = { b = 2.2, r = 14 },
	             Rings = { { scale = 1.18, tilt = 6, thick = 0.09, transp = 0.45 } },
	             Motes = { tex = SMOKE,   rate = 20, size = 0.62, speed = 0.30, life = 2.4, transp = 0.45 } },
	-- AURORA: one wide steeply-tilted veil and a long ribbon wake
	auroraveil = { Aura = 1.16, AuraTransp = 0.84, Light = { b = 3.4, r = 19 }, Trail = 1.6,
	             Rings = { { scale = 1.22, tilt = 34, thick = 0.05, transp = 0.38 } },
	             Motes = { tex = SPARKLE, rate = 24, size = 0.55, speed = 1.0, life = 1.9, transp = 0.15 } },
	-- WHITEOUT: no light of its own -- a squall. Snow chunks and a blizzard of motes.
	whiteout = { Aura = 1.14, AuraTransp = 0.88,
	             Belt = { n = 12, radius = 0.64, size = 0.22, transp = 0.05, spread = 0.34, mat = Mat.Snow },
	             Motes = { tex = SPARKLE, rate = 46, size = 0.44, speed = 2.0, life = 0.9, transp = 0.22 } },
	-- MONOLITH: four tall standing slabs around a tall core. Deliberately static.
	monolith = { Light = { b = 2.4, r = 15 },
	             Shards = 4, ShardSize = V(0.30, 1.05, 0.30), ShardOrbit = 0.66, ShardMat = Mat.Glacier,
	             Motes = { tex = SPARKLE, rate = 14, size = 0.42, speed = 0.5, life = 2.0, transp = 0.30 } },
	-- ABSOLUTE ZERO: everything, turned up. Exactly one rock wears this.
	absolute = { Aura = 1.22, AuraTransp = 0.80, Light = { b = 5.0, r = 26 }, Trail = 1.6,
	             Rings = { { scale = 1.20, tilt = 16, thick = 0.07, transp = 0.32 },
	                       { scale = 1.06, tilt = 74, thick = 0.06, transp = 0.45 } },
	             Spikes = { n = 2, len = 0.50, thick = 0.14, transp = 0.12, axis = "y" },
	             Shards = 6, ShardSize = V(0.16, 0.62, 0.16), ShardOrbit = 0.62,
	             Motes = { tex = SPARKLE, rate = 34, size = 0.70, speed = 1.5, life = 2.0, transp = 0.08 } },
}

function RockDesign.For(id)
	return RockDesign.ById[id] or RockDesign.Default
end

--[[ True axis-aligned size of a built rock. Model:GetBoundingBox() is NOT reliable
	for shelf-fit callers, so measure the real extent from each part's oriented box. ]]
function RockDesign.Extents(model)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local cf, s = p.CFrame, p.Size
			local R, U, L = cf.RightVector, cf.UpVector, cf.LookVector
			local e = Vector3.new(
				math.abs(R.X) * s.X / 2 + math.abs(U.X) * s.Y / 2 + math.abs(L.X) * s.Z / 2,
				math.abs(R.Y) * s.X / 2 + math.abs(U.Y) * s.Y / 2 + math.abs(L.Y) * s.Z / 2,
				math.abs(R.Z) * s.X / 2 + math.abs(U.Z) * s.Y / 2 + math.abs(L.Z) * s.Z / 2)
			lo = Vector3.new(math.min(lo.X, cf.X - e.X), math.min(lo.Y, cf.Y - e.Y), math.min(lo.Z, cf.Z - e.Z))
			hi = Vector3.new(math.max(hi.X, cf.X + e.X), math.max(hi.Y, cf.Y + e.Y), math.max(hi.Z, cf.Z + e.Z))
		end
	end
	return hi - lo, (hi + lo) / 2
end

local function decor(parent, name, size, cf, colour, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = material
	p.Transparency = transparency or 0
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Locked = true
	p.Parent = parent
	return p
end

-- Clone the faceted mesh for `key`, scaled + tinted. Falls back to a plain block so a
-- missing RockMeshes folder can never break a rock (or the throw that rides on it).
local function meshCore(parent, key, size, colour, material, reflectance)
	local folder = ReplicatedStorage:FindFirstChild("RockMeshes")
	local template = folder and folder:FindFirstChild(key)
	local p
	if template and template:IsA("BasePart") then
		p = template:Clone()
		p:ClearAllChildren()
	else
		p = Instance.new("Part")
		p.Shape = Enum.PartType.Block
	end
	p.Name = "Core"
	p.Size = size
	p.CFrame = CFrame.new()
	p.Color = colour
	p.Material = material
	p.Reflectance = reflectance or 0
	p.Anchored, p.CanCollide, p.CanQuery, p.CastShadow = true, false, false, false
	p.Parent = parent
	return p
end

--[[ Build(id, colour) -> Model. Core is the PrimaryPart (the faceted mesh); the
	rock's Fx kit adds the rest. Signature is unchanged, so ThrowHandler,
	MerchantClient and the shelf all keep working untouched. ]]
function RockDesign.Build(id, colour)
	local spec = RockDesign.For(id)
	colour = colour or C3(120, 120, 120)

	local model = Instance.new("Model")
	model.Name = id or "Rock"

	local size = spec.Size or RockDesign.Default.Size
	local core = meshCore(model, spec.Mesh or "angular", size, colour, spec.Material, spec.Reflectance)
	model.PrimaryPart = core

	local kit = KITS[spec.Fx or ""]
	if not kit then return model end

	-- the accent every effect is tinted with: the rock's own colour, pushed bright
	local accent = spec.Glow or colour:Lerp(C3(255, 255, 255), 0.45)

	if kit.Aura then
		local halo = decor(model, "Halo", size * kit.Aura, CFrame.new(),
			accent, Mat.Neon, kit.AuraTransp or 0.8)
		halo.Shape = Enum.PartType.Ball
	end

	-- ONE ring (`Ring`) and MANY rings (`Rings`) share a builder so a kit may say
	-- either. Cylinders are modelled on the X axis, so each disc is rotated 90
	-- degrees about Z to lie flat, then tilted -- a tilt is what stops a ring
	-- reading as a flat decal painted on the card.
	local function buildRing(scale, tilt, thick, transp, idx)
		local r = math.max(size.X, size.Z) * scale
		local ring = decor(model, "Ring" .. tostring(idx or ""), V(thick, r, r),
			CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(math.rad(tilt), 0, 0),
			accent, Mat.Neon, transp)
		ring.Shape = Enum.PartType.Cylinder
		return ring
	end

	if kit.Ring then
		buildRing(kit.Ring, 18, 0.07, 0.45)
	end
	if kit.Rings then
		for i, r in ipairs(kit.Rings) do
			buildRing(r.scale or 1.2, r.tilt or 18, r.thick or 0.06, r.transp or 0.45, i)
		end
	end

	if kit.Shards then
		local n = kit.Shards
		-- kept tight on purpose: MerchantClient and Rocco's shelf FIT the preview to
		-- RockDesign.Extents, so decoration that flies wide shrinks the actual stone in
		-- its card. Measured: an early pass at 0.78 orbit + 2.1 ring put AbsoluteZero at
		-- 5.6 studs against a 2.1-stud core, i.e. the rock rendered ~40% smaller.
		-- ShardSize/ShardOrbit/ShardMat are what let one loop serve a geode's fine
		-- needle crown, a Secret's four heavy fangs and the tundra's Ice slabs.
		local shardSize = kit.ShardSize or V(0.20, 0.46, 0.20)
		local orbit = math.max(size.X, size.Z) * (kit.ShardOrbit or 0.58)
		local shardMat = kit.ShardMat or Mat.Neon
		for i = 1, n do
			local a = (i / n) * math.pi * 2
			local h = math.sin(a * 2) * size.Y * 0.28
			decor(model, "Shard" .. i, shardSize,
				CFrame.new(math.cos(a) * orbit, h, math.sin(a) * orbit)
					* CFrame.Angles(math.rad(28 * math.cos(a)), a, math.rad(28 * math.sin(a))),
				accent, shardMat, 0.2)
		end
	end

	-- SPIKES GROW OUT OF THE CORE AND TOUCH IT, which is the whole difference
	-- between them and the orbiting shards above: an obsidian razor and an icicle
	-- have to look attached. Length is measured from the core's surface outward.
	--   axis = "y"  two opposed POLAR spikes -- the quasar's jets
	--   otherwise   n spikes spread evenly round the equator
	-- The part's long axis is Z (V(thick, thick, len)) so a single CFrame.lookAt
	-- aims it; the polar case is built from CFrame.Angles instead because lookAt
	-- has no valid up-vector when the direction is straight up.
	if kit.Spikes then
		local sp = kit.Spikes
		local n = sp.n or 3
		local len = math.max(size.X, size.Z) * (sp.len or 0.6)
		local thick = sp.thick or 0.16
		local spikeMat = sp.mat or Mat.Neon
		local transp = sp.transp or 0.15
		if sp.axis == "y" then
			for i = 1, n do
				local dir = (i % 2 == 1) and 1 or -1
				decor(model, "Jet" .. i, V(thick, thick, len),
					CFrame.new(0, dir * (size.Y * 0.30 + len * 0.5), 0) * CFrame.Angles(math.rad(90), 0, 0),
					accent, spikeMat, transp)
			end
		else
			for i = 1, n do
				local a = (i / n) * math.pi * 2
				local dir = Vector3.new(math.cos(a), 0, math.sin(a))
				local centre = dir * (size.X * 0.30 + len * 0.5)
				decor(model, "Spike" .. i, V(thick, thick, len),
					CFrame.lookAt(centre, centre + dir), accent, spikeMat, transp)
			end
		end
	end

	-- A BELT is a scattered ring of small chunks -- an asteroid belt, a galaxy's
	-- arms, cooling clinker round a basalt plate, snow tumbling round a squall.
	-- The offsets are deterministic (fixed irrationals, not math.random) so a rock
	-- looks the SAME every time it is built: the shop card, the shelf copy and the
	-- thrown stone are three separate Build calls and must agree.
	if kit.Belt then
		local b = kit.Belt
		local n = b.n or 8
		local radius = math.max(size.X, size.Z) * (b.radius or 0.72)
		local beltMat = b.mat or Mat.Neon
		for i = 1, n do
			local a = (i / n) * math.pi * 2 + i * 0.37
			local h = math.sin(i * 2.399) * size.Y * (b.spread or 0.12)
			local s = (b.size or 0.2) * (0.7 + 0.6 * ((i * 7 % 5) / 5))
			decor(model, "Belt" .. i, V(s, s, s),
				CFrame.new(math.cos(a) * radius, h, math.sin(a) * radius)
					* CFrame.Angles(a, a * 1.7, a * 0.5),
				accent, beltMat, b.transp or 0.1)
		end
	end

	-- A CAGE is vertical bars enclosing the core. Exactly one rock uses it: it is
	-- what makes the Singularity read as something CONTAINED rather than as one
	-- more glowing ball at the top of the ladder.
	if kit.Cage then
		local c = kit.Cage
		local n = c.n or 6
		local scale = c.scale or 1.2
		local radius = math.max(size.X, size.Z) * 0.5 * scale
		local barH = size.Y * scale
		for i = 1, n do
			local a = (i / n) * math.pi * 2
			decor(model, "CageBar" .. i, V(c.thick or 0.09, barH, c.thick or 0.09),
				CFrame.new(math.cos(a) * radius, 0, math.sin(a) * radius),
				accent, Mat.Neon, c.transp or 0.25)
		end
	end

	if kit.Light then
		local pl = Instance.new("PointLight")
		pl.Name = "Glow"
		pl.Color = accent
		pl.Brightness = kit.Light.b
		pl.Range = kit.Light.r
		pl.Shadows = false
		pl.Parent = core
	end

	if kit.Motes then
		local m = kit.Motes
		local pe = Instance.new("ParticleEmitter")
		pe.Name = "Motes"
		pe.Texture = m.tex
		pe.Rate = m.rate
		pe.Lifetime = NumberRange.new(m.life * 0.7, m.life)
		pe.Speed = NumberRange.new(m.speed * 0.5, m.speed)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.35, m.size),
			NumberSequenceKeypoint.new(1, 0),
		})
		pe.Transparency = NumberSequence.new(m.transp)
		pe.Color = ColorSequence.new(accent)
		pe.LightEmission = 0.8
		pe.LockedToPart = false
		pe.Parent = core
	end

	if kit.Trail then
		-- Attachments ride the Core, and ThrowHandler flies the rock with PivotTo, so
		-- the trail draws itself along the skip arc for free.
		--
		-- A WAKE, NOT A LASER (2026-09-21). At 0.55-1.1s of lifetime and ~1.8 studs of
		-- width, a stone crossing the lake at 300 studs/s dragged a 150-300 stud neon
		-- ribbon from the dock to wherever it was -- the trail was bigger than the throw.
		-- Now: a third of the width, a fifth of the life (ThrowHandler clamps it further
		-- by the throw's actual speed to ~40 studs of ribbon), softer at the root, camera-
		-- facing so it never disappears edge-on, and it thins to nothing behind the stone
		-- instead of holding its width. kit.Trail still ranks the kits against each other
		-- (a Comet's tail is longer than a Meteor's), just on a sane scale.
		local a0 = Instance.new("Attachment"); a0.Name = "TrailTop"
		a0.Position = V(0, size.Y * 0.16, 0); a0.Parent = core
		local a1 = Instance.new("Attachment"); a1.Name = "TrailBottom"
		a1.Position = V(0, -size.Y * 0.16, 0); a1.Parent = core
		local tr = Instance.new("Trail")
		tr.Name = "Wake"
		tr.Attachment0, tr.Attachment1 = a0, a1
		tr.Lifetime = 0.11 * kit.Trail
		tr.MinLength = 0.1
		tr.FaceCamera = true
		tr.LightEmission = 0.6
		tr.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1):Lerp(accent, 0.55)),
			ColorSequenceKeypoint.new(1, accent),
		})
		tr.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(0.5, 0.75),
			NumberSequenceKeypoint.new(1, 1),
		})
		tr.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.35, 0.55),
			NumberSequenceKeypoint.new(1, 0),
		})
		tr.Parent = core
	end

	return model
end

return RockDesign
