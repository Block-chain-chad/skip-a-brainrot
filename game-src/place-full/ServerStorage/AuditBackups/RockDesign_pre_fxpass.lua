--[[ ==========================================================================
RockDesign -- the single source of truth for what every rock LOOKS like.
---------------------------------------------------------------------------
MESH-BASED (2026-08-06). Each rock's core is one of a few AI-generated FACETED
rock meshes (ReplicatedStorage.RockMeshes), scaled to the rock's Size and tinted
by its Material + Colour. The meshes' baked textures were stripped, so the Roblox
Material (its surface grain) and the per-rock Colour show through -- that is what
lets ONE mesh serve many differently-coloured rocks, and what replaced the old
Block/Ball + stuck-on-chips look ("box with bumps") with real odd shapes + texture.

Colour lives in RockConfig next to Price/Luck (balance data). This module is
presentation only, keyed by RockConfig Id (never renamed). Build(id, colour)
returns a Model used by the shop preview, the shelf display and the thrown rock
alike, so all three always agree.

Mesh keys -> ReplicatedStorage.RockMeshes children:
  rounded  water-worn boulder        angular  chunky sharp-faceted boulder
  crystal  jagged crystalline shard   flat     flat skipping stone
  chunk    faceted cut-stone chunk
========================================================================== ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local V = Vector3.new
local Mat = Enum.Material

local RockDesign = {}

RockDesign.Default = {
	Mesh = "angular", Size = V(2.0, 1.4, 1.7), Material = Mat.Slate,
	Reflectance = 0, Archetype = "rough",
}

-- Archetype "core" adds a soft neon aura (glowing end-game rocks). Every other
-- archetype is just the tinted, materialled mesh -- the mesh carries the shape.
RockDesign.ById = {
	Pebble            = { Mesh = "rounded", Size = V(1.8, 0.9, 1.4),  Material = Mat.Pebble,        Reflectance = 0,    Archetype = "rough"   },
	SmoothStone       = { Mesh = "rounded", Size = V(2.0, 1.2, 1.6),  Material = Mat.Sandstone,     Reflectance = 0.03, Archetype = "smooth"  },
	FlatSkipper       = { Mesh = "flat",    Size = V(2.5, 0.45, 1.9), Material = Mat.Slate,         Reflectance = 0,    Archetype = "smooth"  },
	SlateDisc         = { Mesh = "flat",    Size = V(2.7, 0.4, 2.1),  Material = Mat.Slate,         Reflectance = 0.05, Archetype = "smooth"  },
	GraniteChunk      = { Mesh = "angular", Size = V(2.0, 1.7, 1.8),  Material = Mat.Granite,       Reflectance = 0,    Archetype = "rough"   },
	RiverGlass        = { Mesh = "flat",    Size = V(2.2, 0.55, 1.8), Material = Mat.Glass,         Reflectance = 0.4,  Archetype = "smooth"  },
	ObsidianShard     = { Mesh = "chunk",   Size = V(2.2, 1.3, 1.4),  Material = Mat.Glass,         Reflectance = 0.3,  Archetype = "crystal" },
	BasaltPlate       = { Mesh = "chunk",   Size = V(2.5, 0.7, 2.0),  Material = Mat.Basalt,        Reflectance = 0,    Archetype = "rough"   },
	MeteoriteFragment = { Mesh = "angular", Size = V(1.9, 1.5, 1.8),  Material = Mat.Rock,          Reflectance = 0.05, Archetype = "rough"   },
	StarcastIron      = { Mesh = "chunk",   Size = V(2.0, 1.4, 1.6),  Material = Mat.Metal,         Reflectance = 0.35, Archetype = "metal"   },
	GoldenRock        = { Mesh = "chunk",   Size = V(1.9, 1.6, 1.7),  Material = Mat.Metal,         Reflectance = 0.4,  Archetype = "metal"   },
	PrismaticGeode    = { Mesh = "crystal", Size = V(1.8, 2.0, 1.6),  Material = Mat.Glass,         Reflectance = 0.5,  Archetype = "crystal" },
	VoidstoneShard    = { Mesh = "crystal", Size = V(1.9, 2.1, 1.4),  Material = Mat.Glass,         Reflectance = 0.25, Archetype = "crystal" },
	BrainrotCore      = { Mesh = "chunk",   Size = V(1.9, 1.9, 1.9),  Material = Mat.Neon,          Reflectance = 0,    Archetype = "core"    },
	CometCore         = { Mesh = "chunk",   Size = V(1.9, 1.7, 1.8),  Material = Mat.Glass,         Reflectance = 0.4,  Archetype = "core"    },
	QuasarStone       = { Mesh = "crystal", Size = V(1.8, 2.1, 1.6),  Material = Mat.Neon,          Reflectance = 0,    Archetype = "core"    },
	NebulaCore        = { Mesh = "chunk",   Size = V(1.9, 1.9, 1.9),  Material = Mat.Neon,          Reflectance = 0,    Archetype = "core"    },
	PulsarShard       = { Mesh = "crystal", Size = V(2.0, 2.0, 1.5),  Material = Mat.Glass,         Reflectance = 0.35, Archetype = "core"    },
	GalaxyCore        = { Mesh = "chunk",   Size = V(1.9, 1.9, 1.9),  Material = Mat.Neon,          Reflectance = 0,    Archetype = "core"    },
	CosmosHeart       = { Mesh = "rounded", Size = V(1.9, 1.8, 1.8),  Material = Mat.Neon,          Reflectance = 0,    Archetype = "core"    },
	VoidHeart         = { Mesh = "crystal", Size = V(2.0, 2.0, 1.6),  Material = Mat.Glass,         Reflectance = 0.3,  Archetype = "core"    },

	-- === WORLD 2: the Frozen Tundra shelf (RockConfigTundra) ===
	-- Ice and glacier surfaces rather than the valley's stone and cosmic neon, so a
	-- tundra rock reads as tundra loot the moment it is on the shelf or in the air.
	-- Without an entry here a rock silently falls back to RockDesign.Default -- a grey
	-- angular stone -- which is exactly what these are not.
	GlacierShard      = { Mesh = "crystal", Size = V(2.0, 2.1, 1.5),  Material = Mat.Glacier,       Reflectance = 0.3,  Archetype = "crystal" },
	FrostbiteCore     = { Mesh = "chunk",   Size = V(1.9, 1.8, 1.8),  Material = Mat.Ice,           Reflectance = 0.35, Archetype = "core"    },
	RimeGeode         = { Mesh = "crystal", Size = V(1.8, 2.2, 1.7),  Material = Mat.Glass,         Reflectance = 0.5,  Archetype = "crystal" },
	PermafrostHeart   = { Mesh = "chunk",   Size = V(2.0, 1.9, 1.9),  Material = Mat.Glacier,       Reflectance = 0.2,  Archetype = "core"    },
	AuroraStone       = { Mesh = "crystal", Size = V(1.9, 2.2, 1.6),  Material = Mat.Neon,          Reflectance = 0,    Archetype = "core"    },
	BlizzardCore      = { Mesh = "rounded", Size = V(2.0, 1.9, 1.9),  Material = Mat.Snow,          Reflectance = 0.1,  Archetype = "core"    },
	GlacialMonolith   = { Mesh = "chunk",   Size = V(1.8, 2.3, 1.6),  Material = Mat.Glacier,       Reflectance = 0.15, Archetype = "rough"   },
	AbsoluteZero      = { Mesh = "crystal", Size = V(2.0, 2.1, 1.7),  Material = Mat.Neon,          Reflectance = 0,    Archetype = "core"    },
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

--[[ Build(id, colour) -> Model. Core is the PrimaryPart (the faceted mesh); "core"
	archetype rocks also get a soft neon aura so the cosmic end-game stones glow. ]]
function RockDesign.Build(id, colour)
	local spec = RockDesign.For(id)
	colour = colour or Color3.fromRGB(120, 120, 120)

	local model = Instance.new("Model")
	model.Name = id or "Rock"

	local core = meshCore(model, spec.Mesh or "angular", spec.Size, colour, spec.Material, spec.Reflectance)
	model.PrimaryPart = core

	if (spec.Archetype or "") == "core" then
		local halo = Instance.new("Part")
		halo.Name = "Halo"
		halo.Shape = Enum.PartType.Ball
		halo.Size = spec.Size * 1.25
		halo.CFrame = CFrame.new()
		halo.Color = colour:Lerp(Color3.fromRGB(255, 255, 255), 0.5)
		halo.Material = Mat.Neon
		halo.Transparency = 0.76
		halo.Anchored, halo.CanCollide, halo.CanQuery, halo.CastShadow = true, false, false, false
		halo.Parent = model
	end

	return model
end

return RockDesign
