-- NpcLibrary -- every reusable asset the kit knows about (Wave 1 + the Wave 2
-- pieces the first recipes need). Data only; NpcForge reads it.
--
-- An entry has ONE of:
--   forge    = "<batch>/<part name>"  a MeshPart produced by File > Import 3D of a
--              forge batch (NpcForge takes it from opts.importRoot by name; it
--              never sets MeshId -- that is not scriptable, and the forge
--              pipeline exists precisely to avoid it)
--   blockout = { parts... }           a primitive recipe NpcForge can build with
--              no meshes at all (the Step 7 blockout, and the fallback when a
--              mesh is not imported yet)
-- Most entries carry BOTH: the blockout is how the prototype stands up on day
-- one; the forge mesh replaces it as a content swap.
--
-- Spaces:  overlays -> the bone's centre;  hair/hat/beard -> the attachment;
--          props -> the grip attachment, pivot = the grip point.
-- `colorRole` names a family colour ("accent", "leather", ...); a recipe may
-- override it with a Color3 or another role. `tris` are estimates until the
-- meshes are measured (estimated = true), used only by the budget WARN row.

local NpcLibrary = {}
NpcLibrary.Version = 1

local function V(x, y, z) return Vector3.new(x, y, z) end
local function CF(x, y, z) return CFrame.new(x, y, z) end
local function ANG(x, y, z) return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z)) end

local E = {}
NpcLibrary.Entries = E

-- ===== BODY (one MeshPart per segment; sizes live in NpcRigSpec) =============
for _, bt in ipairs({ "standard", "stout", "slight" }) do
	for _, seg in ipairs({ "Head", "UpperTorso", "LowerTorso", "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot" }) do
		local shared = (seg == "Head" or seg == "LowerArm" or seg == "Hand" or seg == "UpperLeg" or seg == "LowerLeg" or seg == "Foot")
		local id = "Body_" .. (shared and "shared" or bt) .. "_" .. seg
		if not E[id] then
			E[id] = { id = id, kind = "body", segment = seg, bodyType = shared and "shared" or bt,
				-- node name = "<segment>__body": the forge exporter's "<model>__<role>" convention
				forge = "npc_body_" .. (shared and "standard" or bt) .. "/" .. seg .. "__body", tris = 220, estimated = true }
		end
	end
end

-- ===== HAIR / HAT / BEARD (slot = grip name into NpcRigSpec.Grips) ===========
E.HairTousled = { id = "HairTousled", kind = "hair", slot = "Hair", colorRole = "hair", tris = 260, estimated = true,
	forge = "npc_wave1/HairTousled",
	-- cap and fringe stay ABOVE the brow line (kit rule: nothing crosses y +0.48 on the head)
	blockout = { { name = "HairCap", shape = "Block", size = V(1.62, 0.36, 1.48), offset = CF(0, -0.09, 0.04) },
	             { name = "HairFringe", shape = "Block", size = V(1.30, 0.26, 0.30), offset = CF(0.12, -0.10, -0.62) * ANG(0, 0, 3) } } }
E.HairSidePart = { id = "HairSidePart", kind = "hair", slot = "Hair", colorRole = "hair", tris = 200, estimated = true,
	forge = "npc_wave1/HairSidePart",
	blockout = { { name = "HairCap", shape = "Block", size = V(1.58, 0.42, 1.44), offset = CF(0, -0.22, 0.02) } } }
E.HairCrop = { id = "HairCrop", kind = "hair", slot = "Hair", colorRole = "hair", tris = 140, estimated = true,
	forge = "npc_wave1/HairCrop",
	blockout = { { name = "HairCap", shape = "Block", size = V(1.56, 0.30, 1.42), offset = CF(0, -0.16, 0.02) } } }
E.HairBunFall = { id = "HairBunFall", kind = "hair", slot = "Hair", colorRole = "hair", tris = 320, estimated = true,
	forge = "npc_wave1/HairBunFall",
	blockout = { { name = "HairCap", shape = "Block", size = V(1.58, 0.42, 1.44), offset = CF(0, -0.22, 0.02) },
	             { name = "Bun", shape = "Ball", size = V(0.62, 0.62, 0.62), offset = CF(0, 0.10, 0.70) },
	             { name = "Fall", shape = "Block", size = V(0.40, 1.10, 0.30), offset = CF(0, -0.75, 0.80) } } }
E.BeardMustache = { id = "BeardMustache", kind = "beard", slot = "Beard", colorRole = "hair", tris = 60, estimated = true,
	forge = "npc_wave1/BeardMustache",
	blockout = { { name = "Mustache", shape = "Block", size = V(0.70, 0.12, 0.14), offset = CF(0, 0.26, -0.12) } } }
E.HatFloppyPinned = { id = "HatFloppyPinned", kind = "hat", slot = "Hat", colorRole = "hat", tris = 420, estimated = true,
	forge = "npc_wave1/HatFloppyPinned",
	blockout = { { name = "Crown", shape = "Cylinder", size = V(0.60, 1.60, 1.60), offset = CF(0, 0.30, 0) * ANG(0, 0, 90) },
	             { name = "Brim", shape = "Cylinder", size = V(0.08, 2.30, 2.30), offset = CF(0, 0.02, 0) * ANG(0, 0, 90) },
	             { name = "BrimPinned", shape = "Block", size = V(0.42, 0.08, 1.20), offset = CF(-1.00, 0.34, 0) * ANG(0, 0, -35) } } }
E.HatFlatCap = { id = "HatFlatCap", kind = "hat", slot = "Hat", colorRole = "accent", tris = 180, estimated = true,
	forge = "npc_wave1/HatFlatCap",
	blockout = { { name = "Cap", shape = "Block", size = V(1.66, 0.28, 1.56), offset = CF(0, 0.10, 0.05) },
	             { name = "Peak", shape = "Block", size = V(1.10, 0.08, 0.50), offset = CF(0, 0.00, -0.95) * ANG(-8, 0, 0) } } }

-- ===== CLOTHING OVERLAYS (slot = bone name; offset from the bone centre) =====
E.TunicHem = { id = "TunicHem", kind = "overlay", slot = "LowerTorso", colorRole = "base", tris = 120, estimated = true,
	forge = "npc_wave1/TunicHem", offset = CF(0, -0.20, 0),
	blockout = { { name = "TunicHem", shape = "Block", size = V(2.10, 0.60, 1.15), offset = CF(0, 0, 0) } } }
E.CloakYoke = { id = "CloakYoke", kind = "overlay", slot = "UpperTorso", colorRole = "light", tris = 160, estimated = true,
	forge = "npc_wave1/CloakYoke", offset = CF(0, 0.35, 0),
	blockout = { { name = "CloakYoke", shape = "Block", size = V(2.40, 0.55, 1.25), offset = CF(0, 0, 0) } } }
E.ScarfTail = { id = "ScarfTail", kind = "overlay", slot = "UpperTorso", colorRole = "accent", tris = 90, estimated = true,
	forge = "npc_wave1/ScarfTail", offset = CF(0.85, -0.45, -0.62), sidedOffset = true,
	blockout = { { name = "ScarfTail", shape = "Block", size = V(0.45, 1.60, 0.20), offset = CF(0, 0, 0) * ANG(0, 0, -6) } } }
E.ToolBelt = { id = "ToolBelt", kind = "overlay", slot = "LowerTorso", colorRole = "leather", tris = 200, estimated = true,
	forge = "npc_wave1/ToolBelt", offset = CF(0, 0.20, 0),
	blockout = { { name = "Belt", shape = "Block", size = V(2.15, 0.30, 1.20), offset = CF(0, 0, 0) },
	             { name = "Pouch", shape = "Block", size = V(0.40, 0.36, 0.26), offset = CF(0.70, -0.16, -0.62) } } }
E.ToolBeltCollar = { id = "ToolBeltCollar", kind = "overlay", slot = "LowerTorso", colorRole = "leather", tris = 260, estimated = true,
	forge = "npc_wave1/ToolBeltCollar", offset = CF(0, 0.20, 0), bespokeFor = "Gianluca",
	blockout = { { name = "Belt", shape = "Block", size = V(2.15, 0.30, 1.20), offset = CF(0, 0, 0) },
	             { name = "Pouch", shape = "Block", size = V(0.40, 0.36, 0.26), offset = CF(0.70, -0.16, -0.62) },
	             { name = "Collar", shape = "Cylinder", size = V(0.08, 0.34, 0.34), offset = CF(-0.95, -0.28, -0.40) * ANG(0, 90, 0), colorRole = "metal" } } }
E.Belt = { id = "Belt", kind = "overlay", slot = "LowerTorso", colorRole = "leather", tris = 60, estimated = true,
	forge = "npc_wave1/Belt", offset = CF(0, 0.22, 0),
	blockout = { { name = "Belt", shape = "Block", size = V(2.05, 0.24, 1.14), offset = CF(0, 0, 0) },
	             { name = "Buckle", shape = "Block", size = V(0.30, 0.26, 0.08), offset = CF(0, 0, -0.60), colorRole = "metal" } } }
E.Bracer = { id = "Bracer", kind = "overlay", slot = "LowerArm", sided = true, colorRole = "leather", tris = 70, estimated = true,
	forge = "npc_wave1/Bracer", offset = CF(0, 0.08, 0),
	blockout = { { name = "Bracer", shape = "Block", size = V(0.80, 0.50, 0.80), offset = CF(0, 0, 0) } } }
E.Vest = { id = "Vest", kind = "overlay", slot = "UpperTorso", colorRole = "accent", tris = 160, estimated = true,
	forge = "npc_wave1/Vest", offset = CF(0, 0, 0),
	blockout = { { name = "VestL", shape = "Block", size = V(0.80, 1.34, 0.16), offset = CF(-0.62, 0, -0.60) },
	             { name = "VestR", shape = "Block", size = V(0.80, 1.34, 0.16), offset = CF(0.62, 0, -0.60) },
	             { name = "VestBack", shape = "Block", size = V(2.28, 1.34, 0.12), offset = CF(0, 0, 0.58) } } }
E.ApronBib = { id = "ApronBib", kind = "overlay", slot = "UpperTorso", colorRole = "light", tris = 90, estimated = true,
	forge = "npc_wave1/ApronBib", offset = CF(0, -0.10, -0.62),
	blockout = { { name = "ApronBib", shape = "Block", size = V(1.30, 1.10, 0.10), offset = CF(0, 0, 0) } } }
E.ApronSkirt = { id = "ApronSkirt", kind = "overlay", slot = "LowerTorso", colorRole = "light", tris = 90, estimated = true,
	forge = "npc_wave1/ApronSkirt", offset = CF(0, -0.45, -0.55),
	blockout = { { name = "ApronSkirt", shape = "Block", size = V(1.60, 1.30, 0.10), offset = CF(0, 0, 0) } } }
E.SleeveCuff = { id = "SleeveCuff", kind = "overlay", slot = "UpperArm", sided = true, colorRole = "accent", tris = 60, estimated = true,
	forge = "npc_wave1/SleeveCuff", offset = CF(0, -0.36, 0),
	blockout = { { name = "SleeveCuff", shape = "Block", size = V(0.86, 0.26, 0.86), offset = CF(0, 0, 0) } } }

-- ===== PROPS (grip = NpcRigSpec.Grips key; pivot at the grip point) ==========
E.Cane = { id = "Cane", kind = "prop", grip = "RightHand", planted = true, colorRole = "walnut", tris = 140, estimated = true,
	forge = "npc_wave1/Cane",
	blockout = { { name = "Knob", shape = "Ball", size = V(0.38, 0.38, 0.38), offset = CF(0, 0, 0) },
	             { name = "Shaft", shape = "Cylinder", size = V(1.75, 0.22, 0.22), offset = CF(0, -0.98, 0) * ANG(0, 0, 90) } } }
E.Bell = { id = "Bell", kind = "prop", grip = "Cane", colorRole = "metal", material = "SmoothPlastic", tris = 40, estimated = true, bespokeFor = "Gianluca",
	blockout = { { name = "Bell", shape = "Cylinder", size = V(0.28, 0.30, 0.30), offset = CF(0.22, -0.20, -0.10) * ANG(0, 0, 90) },
	             { name = "Loop", shape = "Block", size = V(0.04, 0.14, 0.04), offset = CF(0.22, -0.02, -0.10) } } }
E.CoinStack = { id = "CoinStack", kind = "prop", grip = "RightHand", colorRole = "metal", material = "SmoothPlastic", tris = 60, estimated = true,
	blockout = { { name = "Coins", shape = "Cylinder", size = V(0.40, 0.64, 0.64), offset = CF(0, -0.05, -0.30) * ANG(0, 0, 90) } } }
E.Rock = { id = "Rock", kind = "prop", grip = "RightHand", colorRole = "stone", tris = 80, estimated = true, reuseMesh = "RockMeshes/rounded",
	blockout = { { name = "Rock", shape = "Ball", size = V(0.60, 0.55, 0.60), offset = CF(0, -0.05, -0.32) } } }
E.PotionVial = { id = "PotionVial", kind = "prop", grip = "RightHand", colorRole = "accent", material = "SmoothPlastic", tris = 80, estimated = true,
	blockout = { { name = "Vial", shape = "Cylinder", size = V(0.62, 0.30, 0.30), offset = CF(0, 0.05, -0.30) * ANG(0, 0, 90) },
	             { name = "Cork", shape = "Cylinder", size = V(0.14, 0.18, 0.18), offset = CF(0, 0.43, -0.30) * ANG(0, 0, 90), colorRole = "walnut" } } }
E.Egg = { id = "Egg", kind = "prop", grip = "RightHand", colorRole = "light", material = "SmoothPlastic", tris = 60, estimated = true,
	blockout = { { name = "Egg", shape = "Ball", size = V(0.62, 0.82, 0.62), offset = CF(0, 0.05, -0.30) } } }
E.Charm = { id = "Charm", kind = "prop", grip = "LeftHand", colorRole = "accent", material = "SmoothPlastic", tris = 60, estimated = true, reuseMesh = "RockMeshes/crystal",
	blockout = { { name = "Charm", shape = "Block", size = V(0.34, 0.50, 0.34), offset = CF(0, 0.10, -0.30) * ANG(0, 45, 0) } } }

-- Lookups
function NpcLibrary.Get(id)
	local e = E[id]
	if not e then error("NpcLibrary: unknown entry " .. tostring(id)) end
	return e
end

function NpcLibrary.BodyEntry(bodyType, segment)
	local shared = (segment == "Head" or segment == "LowerArm" or segment == "Hand" or segment == "UpperLeg" or segment == "LowerLeg" or segment == "Foot")
	return E["Body_" .. (shared and "shared" or bodyType) .. "_" .. segment]
end

-- Segment name for an R15 part name ("LeftUpperArm" -> "UpperArm").
function NpcLibrary.SegmentOf(partName)
	local s = partName:gsub("^Left", ""):gsub("^Right", "")
	return s
end

return NpcLibrary
