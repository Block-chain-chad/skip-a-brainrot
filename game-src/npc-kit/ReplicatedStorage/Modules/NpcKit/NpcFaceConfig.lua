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

local NpcFaceConfig = {}
NpcFaceConfig.Version = 1

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
}
NpcFaceConfig.Default = "friendly"

-- Variants the driver derives from any base expression.
NpcFaceConfig.Talking = { mouthSizeYRange = { 0.07, 0.16 }, hz = { 6, 8 }, burst = { 1.5, 2.5 }, rest = 0.5, mouthSizeXScale = 1.05 }
NpcFaceConfig.Closed  = { eyeSizeY = 0.05, pupilSize = 0.01 }
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

-- Resolve(exprId) -> { [partName] = { c0 = CFrame (offset from rest, head space), size = Vector3 } }
-- Pure; no instances touched. NpcForge and NpcLife both use it.
function NpcFaceConfig.Resolve(exprId)
	local expr = NpcFaceConfig.Expressions[exprId] or NpcFaceConfig.Expressions[NpcFaceConfig.Default]
	local out = {}
	for _, p in ipairs(NpcFaceConfig.Parts) do
		local row = expr[p.name] or expr[groupOf(p.name)] or {}
		local x, y = (row.x or 0), (row.y or 0)
		if p.side ~= 0 and row.x then x = row.x * p.side end   -- "pupils toward the nose" mirrors per side
		local rotZ = 0
		if row.browOuterUp then rotZ = row.browOuterUp * p.side end
		if row.rotZ then rotZ = rotZ + row.rotZ end
		local size = V(row.sizeX or p.size.X, row.sizeY or p.size.Y, p.size.Z)
		out[p.name] = {
			c0 = CFrame.new(p.offset.X + x, p.offset.Y + y, p.offset.Z) * CFrame.Angles(0, 0, math.rad(rotZ)),
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
	local resolved = NpcFaceConfig.Resolve(exprId)
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
