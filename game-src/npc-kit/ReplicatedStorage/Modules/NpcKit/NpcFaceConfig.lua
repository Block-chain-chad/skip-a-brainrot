-- NpcFaceConfig -- the 7-part cube face ("VoxelFace-H") and its expressions.
--
-- Parts are plain Parts on a Motor6D ("FaceJoint", Part0 = Head) so an
-- expression is a C0 offset + a size, applied once on change -- zero per-frame
-- cost at rest. Blink / gaze / talk are the driver's timers (NpcLife) reading
-- the numbers at the bottom of this file.
--
-- Rules carried over from VoxelFace on the creatures: cube eyes, recessed so
-- only the front sliver is proud of the head, sized off the head, never spheres.
--
-- PUBLIC INTERFACE (decision D-3): the ONLY supported way to change an NPC's
-- face from outside NPC-01 is the root model's `NpcFace` attribute
-- (model:SetAttribute("NpcFace", "worried")). Nothing outside this kit may
-- touch the face parts. The driver applies the table on change.

-- V2.5 (approved D-17): the same seven driven parts may come from an Import 3D shell
-- batch (NpcShells) instead of the cube recipe below. A mesh face carries its rest
-- offset / size / side as attributes on each part (RestC0, RestSize, Side, set by
-- NpcForge) and its expressions use RELATIVE fields (scaleX / scaleY) instead of the
-- absolute sizeX / sizeY the cube face uses. Resolve() takes the rests explicitly so
-- both faces share one table of expressions. The upper eyelid is geometry on the Head
-- mesh and the lash line is part of the Brow mesh, so opening / closing the eye is the
-- brow's lift plus the eye's scaleY -- no extra driven part.

local NpcFaceConfig = {}
NpcFaceConfig.Version = 2

local function V(x, y, z) return Vector3.new(x, y, z) end
local WHITE = Color3.fromRGB(252, 252, 252)
local INK = Color3.fromRGB(16, 14, 20)
local MOUTH = Color3.fromRGB(60, 34, 30)

-- offsets are from the HEAD centre; the head's front face is at z = -0.675.
-- `color = "hair"` means "paint with the character's hair colour role".
NpcFaceConfig.Parts = {
	{ name = "EyeR",   size = V(0.30, 0.32, 0.16), offset = V( 0.33,  0.10, -0.645), color = WHITE, material = "SmoothPlastic", side = 1 },
	{ name = "EyeL",   size = V(0.30, 0.32, 0.16), offset = V(-0.33,  0.10, -0.645), color = WHITE, material = "SmoothPlastic", side = -1 },
	{ name = "PupilR", size = V(0.14, 0.16, 0.06), offset = V( 0.33,  0.08, -0.740), color = INK,   material = "SmoothPlastic", side = 1 },
	{ name = "PupilL", size = V(0.14, 0.16, 0.06), offset = V(-0.33,  0.08, -0.740), color = INK,   material = "SmoothPlastic", side = -1 },
	{ name = "BrowR",  size = V(0.36, 0.09, 0.08), offset = V( 0.33,  0.36, -0.680), color = "hair", material = "Plastic", side = 1 },
	{ name = "BrowL",  size = V(0.36, 0.09, 0.08), offset = V(-0.33,  0.36, -0.680), color = "hair", material = "Plastic", side = -1 },
	{ name = "Mouth",  size = V(0.34, 0.07, 0.06), offset = V( 0.00, -0.30, -0.680), color = MOUTH, material = "Plastic", side = 0 },
}
-- optional parts a recipe may add (faceExtras)
NpcFaceConfig.Extras = {
	Scar = { size = V(0.06, 0.40, 0.04), offset = V(0.44, 0.02, -0.690), color = Color3.fromRGB(150, 96, 84), material = "Plastic", side = 1 },
	Nose = { size = V(0.16, 0.16, 0.16), offset = V(0.00, -0.06, -0.720), color = "skin", material = "Plastic", side = 0 },
}

-- Expression rows. Keys are part GROUPS (Brow / Eye / Pupil apply to both
-- sides) or exact part names. Fields:
--   y, x        translation from the rest offset (studs)
--   sizeX/sizeY absolute part size on that axis
--   browOuterUp brow rotation in degrees, OUTER end up (+); mirrored per side
--   rotZ        raw Z rotation in degrees (mouth smirk)
NpcFaceConfig.Expressions = {
	friendly    = { Brow = { browOuterUp = 8,  y = 0.00 },                   Eye = { sizeY = 0.32 }, Pupil = { y = 0.00 }, Mouth = { sizeX = 0.44, y = 0.02, sizeY = 0.07 } },
	worried     = { Brow = { browOuterUp = -16, y = 0.04 },                  Eye = { sizeY = 0.34 }, Pupil = { y = -0.02 }, Mouth = { sizeX = 0.24, y = -0.03, sizeY = 0.10 } },
	stern       = { Brow = { browOuterUp = 14, y = -0.06 },                  Eye = { sizeY = 0.26 }, Pupil = { y = 0.00 }, Mouth = { sizeX = 0.36, y = -0.01, sizeY = 0.06 } },
	suspicious  = { BrowR = { browOuterUp = -4, y = 0.04 }, BrowL = { browOuterUp = 16, y = -0.08 },
	                EyeR = { sizeY = 0.30 }, EyeL = { sizeY = 0.22 }, Pupil = { x = -0.04 }, Mouth = { sizeX = 0.30, y = -0.01, sizeY = 0.06, rotZ = 8 } },
	old         = { Brow = { browOuterUp = 0, y = -0.04, sizeY = 0.12 },     Eye = { sizeY = 0.22 }, Pupil = { y = -0.02 }, Mouth = { sizeX = 0.30, y = -0.04, sizeY = 0.07 } },
	tired       = { Brow = { browOuterUp = 2, y = -0.06 },                   Eye = { sizeY = 0.20 }, Pupil = { y = -0.04 }, Mouth = { sizeX = 0.28, y = -0.04, sizeY = 0.06 } },
	excited     = { Brow = { browOuterUp = 6, y = 0.08 },                    Eye = { sizeY = 0.36 }, Pupil = { sizeX = 0.16, sizeY = 0.16 }, Mouth = { sizeX = 0.46, y = 0.03, sizeY = 0.14 } },
	["battle-worn"] = { Brow = { browOuterUp = 14, y = -0.06 },              Eye = { sizeY = 0.26 }, Pupil = { y = 0.00 }, Mouth = { sizeX = 0.36, y = -0.01, sizeY = 0.06 } },
	-- ===== V2.5 states (mesh faces; relative scales; the mouth mesh is a mild smile, rotZ 180 turns it into a frown) =====
	neutral     = { Brow = { browOuterUp = 3, y = 0.00 },                   Eye = { scaleY = 1.00 }, Pupil = { scaleX = 1.00, scaleY = 1.00 }, Mouth = { scaleX = 0.95, scaleY = 0.85 } },
	happy       = { Brow = { browOuterUp = 1, y = 0.03 },                   Eye = { scaleY = 0.90 }, Pupil = { scaleX = 1.00, scaleY = 1.00 }, Mouth = { scaleX = 1.30, scaleY = 1.10 } },
	worried     = { Brow = { browOuterUp = -14, y = 0.05 },                 Eye = { scaleY = 1.00 }, Pupil = { scaleX = 0.95, scaleY = 0.95 }, Mouth = { rotZ = 180, scaleX = 0.90, scaleY = 1.00 } },
	angry       = { Brow = { browOuterUp = 17, y = -0.07 },                 Eye = { scaleY = 0.80 }, Pupil = { scaleX = 1.00, scaleY = 1.00 }, Mouth = { rotZ = 180, scaleX = 1.05, scaleY = 1.00 } },
	suspicious  = { BrowR = { browOuterUp = 14, y = -0.09 }, BrowL = { browOuterUp = -6, y = 0.09 },
	                Eye = { scaleY = 0.72 }, Pupil = { x = -0.03, scaleX = 0.95, scaleY = 0.95 }, Mouth = { scaleX = 0.80, scaleY = 0.70 } },
	tired       = { Brow = { browOuterUp = -4, y = -0.05 },                 Eye = { scaleY = 0.62 }, Pupil = { scaleX = 1.00, scaleY = 1.00 }, Mouth = { rotZ = 180, scaleX = 0.90, scaleY = 0.70 } },
	shocked     = { Brow = { browOuterUp = -2, y = 0.19 },                  Eye = { scaleY = 1.15 }, Pupil = { scaleX = 0.78, scaleY = 0.78 }, Mouth = { scaleX = 0.55, scaleY = 2.40 } },
	serious     = { Brow = { browOuterUp = 9, y = -0.035 },                 Eye = { scaleY = 0.88 }, Pupil = { scaleX = 1.00, scaleY = 1.00 }, Mouth = { scaleX = 1.05, scaleY = 0.70 } },
}
NpcFaceConfig.Default = "friendly"
NpcFaceConfig.MeshStates = { "neutral", "happy", "worried", "angry", "suspicious", "tired", "shocked", "serious" }
-- legacy state names a mesh face maps onto (a recipe or lane may still ask for them)
NpcFaceConfig.MeshAlias = { friendly = "happy", stern = "serious", old = "tired", excited = "shocked", ["battle-worn"] = "serious" }

-- Variants the driver derives from any base expression.
NpcFaceConfig.Talking = { mouthSizeYRange = { 0.07, 0.16 }, hz = { 6, 8 }, burst = { 1.5, 2.5 }, rest = 0.5, mouthSizeXScale = 1.05,
	mouthScaleYRange = { 1.0, 2.4 } }                          -- mesh faces: relative to the rest height
NpcFaceConfig.Closed  = { eyeSizeY = 0.05, pupilSize = 0.01, eyeScaleY = 0.15, pupilScale = 0.15 }
NpcFaceConfig.Blink   = { every = { 3, 6 }, duration = 0.12 }
NpcFaceConfig.Gaze    = { range = 20, dot = 0.3, x = 0.06, y = 0.04, hz = 10 }

local function rest(partName)
	for _, p in ipairs(NpcFaceConfig.Parts) do if p.name == partName then return p end end
	return NpcFaceConfig.Extras[partName]
end

local function groupOf(partName)
	if partName:sub(1, 4) == "Brow" then return "Brow" end
	if partName:sub(1, 5) == "Pupil" then return "Pupil" end
	if partName:sub(1, 3) == "Eye" then return "Eye" end
	return partName
end

-- The cube face's rests, in the shape Resolve wants: { [name] = { offset, size, side, mesh = false } }
function NpcFaceConfig.CubeRests()
	local rests = {}
	for _, p in ipairs(NpcFaceConfig.Parts) do
		rests[p.name] = { offset = p.offset, size = p.size, side = p.side, mesh = false }
	end
	return rests
end

-- Rests recorded on a built face by NpcForge (RestC0 / RestSize / Side attributes on each part).
function NpcFaceConfig.RestsOf(faceFolder)
	local rests = {}
	local mesh = faceFolder:GetAttribute("NpcFaceMesh") == true
	for _, part in ipairs(faceFolder:GetChildren()) do
		if part:IsA("BasePart") then
			local c0 = part:GetAttribute("RestC0")
			local size = part:GetAttribute("RestSize")
			if c0 and size then
				rests[part.Name] = { offset = c0.Position, size = size, side = part:GetAttribute("Side") or 0, mesh = mesh }
			end
		end
	end
	if next(rests) == nil then return NpcFaceConfig.CubeRests() end
	return rests
end

-- Resolve(exprId, rests) -> { [partName] = { c0 = CFrame (head space), size = Vector3 } }
-- Pure; no instances touched. NpcForge and NpcLife both use it. rests defaults to the
-- cube face. A mesh face maps legacy state names through MeshAlias and ignores the
-- cube face's absolute sizes.
function NpcFaceConfig.Resolve(exprId, rests)
	rests = rests or NpcFaceConfig.CubeRests()
	local anyMesh = false
	for _, r in pairs(rests) do if r.mesh then anyMesh = true end end
	if anyMesh and NpcFaceConfig.MeshAlias[exprId] then exprId = NpcFaceConfig.MeshAlias[exprId] end
	local expr = NpcFaceConfig.Expressions[exprId] or NpcFaceConfig.Expressions[anyMesh and "neutral" or NpcFaceConfig.Default]
	local out = {}
	for name, rest in pairs(rests) do
		local row = expr[name] or expr[groupOf(name)] or {}
		local side = rest.side or 0
		local x, y = (row.x or 0), (row.y or 0)
		if side ~= 0 and row.x then x = row.x * side end   -- "pupils toward the nose" mirrors per side
		local rotZ = 0
		if row.browOuterUp then rotZ = row.browOuterUp * side end
		if row.rotZ then rotZ = rotZ + row.rotZ end
		local size
		if rest.mesh then
			size = V(rest.size.X * (row.scaleX or 1), rest.size.Y * (row.scaleY or 1), rest.size.Z)
		else
			size = V(row.sizeX or rest.size.X * (row.scaleX or 1), row.sizeY or rest.size.Y * (row.scaleY or 1), rest.size.Z)
		end
		out[name] = {
			c0 = CFrame.new(rest.offset.X + x, rest.offset.Y + y, rest.offset.Z) * CFrame.Angles(0, 0, math.rad(rotZ)),
			size = size,
		}
	end
	return out
end

-- Apply(model, exprId): writes the resolved table into a built face. The head
-- joint C0 for each face part is the resolved c0 (rest offset already inside).
-- Returns the number of parts written; 0 means the model has no NPC-01 face.
function NpcFaceConfig.Apply(model, exprId)
	local face = model and model:FindFirstChild("Face")
	if not face then return 0 end
	local resolved = NpcFaceConfig.Resolve(exprId, NpcFaceConfig.RestsOf(face))
	local n = 0
	for name, r in pairs(resolved) do
		local part = face:FindFirstChild(name)
		local joint = part and part:FindFirstChild("FaceJoint")
		if part and joint then
			joint.C0 = r.c0
			part.Size = r.size
			n = n + 1
		end
	end
	return n
end

function NpcFaceConfig.RestOf(partName) return rest(partName) end

return NpcFaceConfig
