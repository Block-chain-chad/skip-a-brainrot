--[[ ==========================================================================
RockDesign -- the single source of truth for what every rock LOOKS like.
---------------------------------------------------------------------------
There were three copies of this data before: a private ROCK_DESIGN in
ThrowHandler (8 of 14 rocks), a ROCK_PREVIEW in MerchantClient (14, but
different shapes and materials from the thrown rock), and nothing at all for
Rocco's shelf. A rock could therefore look like three different objects
depending on whether you were buying it, throwing it, or looking at it.

Now: ById holds the base spec, and Build(id) returns a detailed multi-part
Model used by the shop preview, the shelf display and the thrown rock alike.

Colour lives in RockConfig next to Price/Luck (balance data). This module is
presentation only. Keyed by RockConfig Id, which is never renamed.

Build() is DETERMINISTIC -- the chip layout is driven by a seed derived from the
rock's Id, so the same rock is always the same rock, in every surface.
========================================================================== ]]

local V = Vector3.new
local Mat = Enum.Material
local Shape = Enum.PartType

local RockDesign = {}

RockDesign.Default = {
	Shape = Shape.Block, Size = V(2.2, 0.4, 1.5), Material = Mat.Slate,
	Reflectance = 0, Archetype = "rough",
}

-- Archetypes drive the DETAIL pass in Build():
--   rough   chipped angular stone      smooth  water-worn, few soft bumps
--   crystal jutting facets             metal   flat facets + bright specks
--   core    neon heart + orbiting shards
RockDesign.ById = {
	Pebble            = { Shape = Shape.Block, Size = V(1.8, 0.8, 1.4),  Material = Mat.Pebble,        Reflectance = 0,    Archetype = "rough"   },
	SmoothStone       = { Shape = Shape.Ball,  Size = V(2.0, 1.2, 1.6),  Material = Mat.SmoothPlastic, Reflectance = 0.05, Archetype = "smooth"  },
	FlatSkipper       = { Shape = Shape.Block, Size = V(2.4, 0.35, 1.8), Material = Mat.Slate,         Reflectance = 0,    Archetype = "smooth"  },
	SlateDisc         = { Shape = Shape.Block, Size = V(2.6, 0.28, 2.1), Material = Mat.Slate,         Reflectance = 0.05, Archetype = "smooth"  },
	GraniteChunk      = { Shape = Shape.Block, Size = V(1.9, 1.3, 1.7),  Material = Mat.Granite,       Reflectance = 0,    Archetype = "rough"   },
	RiverGlass        = { Shape = Shape.Block, Size = V(2.1, 0.5, 1.7),  Material = Mat.Glass,         Reflectance = 0.45, Archetype = "smooth"  },
	ObsidianShard     = { Shape = Shape.Block, Size = V(2.6, 0.5, 1.0),  Material = Mat.Glass,         Reflectance = 0.3,  Archetype = "crystal" },
	BasaltPlate       = { Shape = Shape.Block, Size = V(2.5, 0.6, 2.0),  Material = Mat.Basalt,        Reflectance = 0,    Archetype = "rough"   },
	MeteoriteFragment = { Shape = Shape.Block, Size = V(1.9, 1.4, 1.8),  Material = Mat.Rock,          Reflectance = 0,    Archetype = "rough"   },
	StarcastIron      = { Shape = Shape.Block, Size = V(2.0, 1.0, 1.6),  Material = Mat.Metal,         Reflectance = 0.35, Archetype = "metal"   },
	GoldenRock        = { Shape = Shape.Ball,  Size = V(1.9, 1.5, 1.7),  Material = Mat.Metal,         Reflectance = 0.4,  Archetype = "metal"   },
	PrismaticGeode    = { Shape = Shape.Ball,  Size = V(1.8, 1.7, 1.8),  Material = Mat.Glass,         Reflectance = 0.5,  Archetype = "crystal" },
	VoidstoneShard    = { Shape = Shape.Block, Size = V(2.4, 0.6, 1.1),  Material = Mat.Glass,         Reflectance = 0.2,  Archetype = "crystal" },
	BrainrotCore      = { Shape = Shape.Ball,  Size = V(1.9, 1.9, 1.9),  Material = Mat.Neon,          Reflectance = 0,    Archetype = "core"    },
}

function RockDesign.For(id)
	return RockDesign.ById[id] or RockDesign.Default
end

local function seedOf(id)
	local n = 0
	for i = 1, #id do n = (n * 31 + string.byte(id, i)) % 2147483647 end
	return n
end

local function newPart(parent, name, size, cf, colour, material, reflectance, shape)
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color = name, size, cf, colour
	p.Material = material
	p.Reflectance = reflectance or 0
	if shape then p.Shape = shape end
	p.Anchored, p.CanCollide, p.CanQuery, p.CastShadow = true, false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Evenly spread directions (Fibonacci sphere) instead of pure random. Random
-- directions clustered -- an early build put all three swells on the +X side and
-- left the stone visibly lopsided.
local GOLDEN = math.pi * (3 - math.sqrt(5))
local function spreadDir(i, n, rng)
	local y = 1 - (i - 0.5) / n * 2
	local r = math.sqrt(math.max(0, 1 - y * y))
	local t = GOLDEN * i + rng:NextNumber(-0.25, 0.25)
	return Vector3.new(math.cos(t) * r, y * rng:NextNumber(0.75, 1.0), math.sin(t) * r).Unit
end

local function onSurface(size, dir, inset)
	return Vector3.new(dir.X * size.X / 2, dir.Y * size.Y / 2, dir.Z * size.Z / 2) * (inset or 1)
end

--[[ True axis-aligned size of a built rock.
	Model:GetBoundingBox() is NOT reliable here: for Ball parts it reports the
	inscribed extent, and measured 1.59 wide on a stone whose core alone is 2.0.
	Callers that fit a rock into a shelf cell must use this instead. ]]
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

--[[ Build(id, colour) -> Model
	Core is the PrimaryPart and carries the base spec. Detail parts are kept well
	under the core's size and half-buried in its surface, so they add texture
	without inflating the silhouette or turning the rock lopsided. ]]
function RockDesign.Build(id, colour)
	local spec = RockDesign.For(id)
	colour = colour or Color3.fromRGB(120, 120, 120)
	local rng = Random.new(seedOf(id or "rock"))

	local model = Instance.new("Model")
	model.Name = id or "Rock"
	local core = newPart(model, "Core", spec.Size, CFrame.new(), colour,
		spec.Material, spec.Reflectance, spec.Shape)
	model.PrimaryPart = core

	local dark  = colour:Lerp(Color3.fromRGB(0, 0, 0), 0.32)
	local light = colour:Lerp(Color3.fromRGB(255, 255, 255), 0.28)
	local md = math.min(spec.Size.X, spec.Size.Y, spec.Size.Z)
	local A = spec.Archetype or "rough"
	local function spin() return CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28)) end

	if A == "rough" then
		for i = 1, 7 do
			local s = md * rng:NextNumber(0.20, 0.34)
			newPart(model, "Chip" .. i,
				Vector3.new(s, s * rng:NextNumber(0.65, 1.05), s * rng:NextNumber(0.75, 1.15)),
				CFrame.new(onSurface(spec.Size, spreadDir(i, 7, rng), 0.80)) * spin(),
				(i % 2 == 0) and dark or light, spec.Material, spec.Reflectance)
		end
	elseif A == "smooth" then
		for i = 1, 4 do
			local s = md * rng:NextNumber(0.28, 0.42)
			newPart(model, "Swell" .. i, Vector3.new(s * 1.6, s * 0.8, s * 1.35),
				CFrame.new(onSurface(spec.Size, spreadDir(i, 4, rng), 0.62)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
				light, spec.Material, spec.Reflectance, Enum.PartType.Ball)
		end
		newPart(model, "Sheen", Vector3.new(spec.Size.X * 0.5, spec.Size.Y * 0.26, spec.Size.Z * 0.34),
			CFrame.new(0, spec.Size.Y * 0.30, 0), light, spec.Material,
			math.max(spec.Reflectance, 0.16), Enum.PartType.Ball)
	elseif A == "crystal" then
		for i = 1, 6 do
			local len = md * rng:NextNumber(0.75, 1.25)
			newPart(model, "Facet" .. i, Vector3.new(md * 0.28, len, md * 0.24),
				CFrame.new(onSurface(spec.Size, spreadDir(i, 6, rng), 0.55))
					* CFrame.Angles(rng:NextNumber(-0.9, 0.9), rng:NextNumber(0, 6.28), rng:NextNumber(-0.9, 0.9)),
				(i % 2 == 0) and light or dark, spec.Material, math.max(spec.Reflectance, 0.25))
		end
	elseif A == "metal" then
		for i = 1, 6 do
			local s = md * rng:NextNumber(0.30, 0.48)
			newPart(model, "Facet" .. i, Vector3.new(s, s * 0.26, s * rng:NextNumber(0.85, 1.2)),
				CFrame.new(onSurface(spec.Size, spreadDir(i, 6, rng), 0.78)) * spin(),
				light, spec.Material, math.min(0.6, spec.Reflectance + 0.2))
		end
		for i = 1, 3 do
			local s = md * 0.11
			newPart(model, "Speck" .. i, Vector3.new(s, s, s),
				CFrame.new(onSurface(spec.Size, spreadDir(i * 2, 6, rng), 0.9)),
				light, Mat.Foil, 0.5, Enum.PartType.Ball)
		end
	elseif A == "core" then
		local halo = newPart(model, "Halo", spec.Size * 1.12, CFrame.new(),
			colour:Lerp(Color3.fromRGB(255, 255, 255), 0.5), Mat.Neon, 0, Enum.PartType.Ball)
		halo.Transparency = 0.72
		for i = 1, 7 do
			local s = md * rng:NextNumber(0.13, 0.22)
			newPart(model, "Frag" .. i, Vector3.new(s, s * 1.8, s * 0.7),
				CFrame.new(onSurface(spec.Size, spreadDir(i, 7, rng), 0.86)) * spin(),
				colour:Lerp(Color3.fromRGB(0, 0, 0), 0.55), Mat.SmoothPlastic, 0.1)
		end
	end

	return model
end

return RockDesign
