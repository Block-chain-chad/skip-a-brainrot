--[[
	BrainrotBodyBuilder — turns a BrainrotLooks recipe into a Model of anchored
	primitives. PURE and DETERMINISTIC: the same (name, recipe) must produce an
	identical Model on every server, forever — looks are owned, so math.random
	is banned from this file.

	Constraints this module lives under:
	- Primitives only: Part (Block/Ball/Cylinder), WedgePart, CornerWedgePart.
	  No MeshParts, no unions, no uploaded assets — the art style depends on it.
	- A bad recipe must NEVER block a spawn: unknown keys warn() and fall back
	  (blob body / happy face / no accessory) instead of erroring.
	- Built standing on Y=0, centered at the origin, FACING -Z. The spawner
	  scales and seats via bounding box, so proportion matters, absolute size
	  doesn't.
	- Eyes are always white sclera + black pupil at every tier — that is the
	  "alive" signal and is never tinted, glowed, or made transparent.
	- Preset keys may carry a variant after a colon ("pot:pan", "flame:rear",
	  "cape:necktie") so BrainrotLooks stays flat data; unknown variants just
	  render the base preset.
]]

local CollectionService = game:GetService("CollectionService")

local M = {}

local DEFAULT_BODY_COLOR = Color3.fromHex("#C8C2B8")
local DEFAULT_ACCENT = Color3.fromHex("#F5F0E6")
local WHITE = Color3.fromHex("#FFFFFF")
local BLACK = Color3.fromHex("#111111")
local MOUTH = Color3.fromHex("#1E1E1E")
local TONGUE = Color3.fromHex("#E8788A")
local GOLD = Color3.fromHex("#D4AF37")
local STEEL = Color3.fromHex("#9FA6AD")
local BRASS = Color3.fromHex("#B08D57")
local WOOD = Color3.fromHex("#8B5A2B")
local TIRE = Color3.fromHex("#2E2A28")

local MOTIONS = { bob = true, sway = true, hover = true, spin = true, shiver = true, none = true }

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

-- "pot:pan" -> "pot", "pan". Variant is matched by substring so authored keys
-- can combine tokens ("flame:steam-rear") without a grammar.
local function splitKey(key)
	if type(key) ~= "string" or key == "" then
		return nil, ""
	end
	local base, variant = string.match(key, "^([^:]+):?(.*)$")
	return base, variant or ""
end

local function hasToken(variant, token)
	return string.find(variant, token, 1, true) ~= nil
end

-- Recipes normally carry "#RRGGBB" strings, but the original spec showed raw
-- Color3 values — accept both so hand-tweaked data never breaks a spawn.
local function resolveColor(value, fallback, name, slot)
	if typeof(value) == "Color3" then
		return value
	end
	if type(value) == "string" then
		local ok, color = pcall(Color3.fromHex, value)
		if ok then
			return color
		end
	end
	if value ~= nil then
		warn(("[BrainrotBodyBuilder] %s: bad %s %q — using fallback color"):format(name, slot, tostring(value)))
	end
	return fallback
end

-- Single part factory so the Anchored/CanCollide contract cannot be missed on
-- any of the ~200 part placements below.
local function P(model, partName, class, size, cf, color, material)
	local part
	if class == "Wedge" then
		part = Instance.new("WedgePart")
	elseif class == "CornerWedge" then
		part = Instance.new("CornerWedgePart")
	else
		part = Instance.new("Part")
		part.Shape = Enum.PartType[class]
	end
	part.Name = partName
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material or Enum.Material.Plastic
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

-- Roblox cylinders lie along X natively; AXIS_ROT stands them up (Y) or rolls
-- them forward (Z) so builders can think in "diameter x length along axis".
local AXIS_ROT = {
	X = CFrame.new(),
	Y = CFrame.Angles(0, 0, math.rad(90)),
	Z = CFrame.Angles(0, math.rad(90), 0),
}

local function Cyl(model, partName, dia, length, cf, axis, color, material)
	return P(model, partName, "Cylinder", Vector3.new(length, dia, dia), cf * AXIS_ROT[axis], color, material)
end

-- Face frames sit ON the surface with LookVector pointing OUT of the body, so
-- feature offsets are (x right, y up, -z outward) for every body shape.
local function faceFrame(pos, outDir)
	return CFrame.lookAt(pos, pos + outDir)
end

local FRONT = Vector3.new(0, 0, -1)

--------------------------------------------------------------------------------
-- Bodies. Every builder returns the same anchor bundle so faces and
-- accessories can mount on any body without knowing which one it is:
--   primary (Part), face (CFrame), faceScale, top/backPos/rearPos/rightArm
--   (Vector3, world space — valid because every body faces -Z), halfWidth,
--   halfDepth, bottomY (underside of the torso mass, not the feet), feet
--   (parts spring-legs may destroy and replace).
--------------------------------------------------------------------------------

local function bodyLoaf(model, c, variant, accent)
	-- Crust dome doubles as the topping/fat-fleck read, so it leans toward the
	-- accent instead of plain lightening.
	local crustColor = c:Lerp(accent, 0.3)
	local feet = {}
	for i, off in ipairs({
		Vector3.new(-0.5, 0, -0.95), Vector3.new(0.5, 0, -0.95),
		Vector3.new(-0.5, 0, 0.95), Vector3.new(0.5, 0, 0.95),
	}) do
		feet[i] = Cyl(model, "Leg", 0.35, 0.45, CFrame.new(off.X, 0.225, off.Z), "Y", c)
	end
	local core, coreY, coreTop
	if hasToken(variant, "sausage") then
		coreY = 1.1
		coreTop = coreY + 0.65
		core = Cyl(model, "Core", 1.3, 2.6, CFrame.new(0, coreY, 0), "Z", c)
	else
		coreY = 1.05
		coreTop = coreY + 0.6
		core = P(model, "Core", "Block", Vector3.new(1.4, 1.2, 2.6), CFrame.new(0, coreY, 0), c)
	end
	P(model, "Crust", "Ball", Vector3.new(1.3, 0.9, 2.4), CFrame.new(0, coreTop, 0), crustColor)
	return {
		primary = core,
		face = faceFrame(Vector3.new(0, coreY, -1.3), FRONT),
		faceScale = 0.85,
		top = Vector3.new(0, coreTop + 0.45, 0),
		backPos = Vector3.new(0, coreY + 0.4, 1.15),
		rearPos = Vector3.new(0, coreY, 1.3),
		rightArm = Vector3.new(0.8, coreY, -0.2),
		halfWidth = 0.7,
		halfDepth = 1.3,
		bottomY = coreY - 0.6,
		feet = feet,
	}
end

local function bodyBall(model, c, variant)
	local flat = hasToken(variant, "flat")
	local feet = {
		P(model, "Foot", "Block", Vector3.new(0.6, 0.35, 0.8), CFrame.new(-0.45, 0.175, -0.35), c),
		P(model, "Foot", "Block", Vector3.new(0.6, 0.35, 0.8), CFrame.new(0.45, 0.175, -0.35), c),
	}
	local size = flat and Vector3.new(2.2, 1.2, 2.2) or Vector3.new(2, 2, 2)
	local coreY = flat and 0.85 or 1.25
	local core = P(model, "Core", "Ball", size, CFrame.new(0, coreY, 0), c)
	-- Rotating about Z drops the outer end: stub arms pitched 30 deg down.
	Cyl(model, "Arm", 0.25, 0.55, CFrame.new(size.X / 2 + 0.05, coreY - 0.1, 0) * CFrame.Angles(0, 0, math.rad(-30)), "X", c)
	Cyl(model, "Arm", 0.25, 0.55, CFrame.new(-size.X / 2 - 0.05, coreY - 0.1, 0) * CFrame.Angles(0, 0, math.rad(30)), "X", c)
	local faceDir = flat and Vector3.new(0, 0.25, -0.97) or Vector3.new(0, 0.5, -0.87)
	local facePos = Vector3.new(faceDir.X * size.X / 2, coreY + faceDir.Y * size.Y / 2, faceDir.Z * size.Z / 2)
	return {
		primary = core,
		face = faceFrame(facePos, faceDir),
		faceScale = 1,
		top = Vector3.new(0, coreY + size.Y / 2, 0),
		backPos = Vector3.new(0, coreY + size.Y * 0.3, size.Z * 0.4),
		rearPos = Vector3.new(0, coreY, size.Z / 2),
		rightArm = Vector3.new(size.X / 2 + 0.25, coreY - 0.1, 0),
		halfWidth = size.X / 2,
		halfDepth = size.Z / 2,
		bottomY = coreY - size.Y / 2 + 0.1,
		feet = feet,
	}
end

local function bodySlab(model, c, variant)
	local horizontal = hasToken(variant, "flat") or hasToken(variant, "horizontal")
	local feet = {
		P(model, "Foot", "Block", Vector3.new(0.7, 0.4, 0.9), CFrame.new(-0.55, 0.2, 0), c),
		P(model, "Foot", "Block", Vector3.new(0.7, 0.4, 0.9), CFrame.new(0.55, 0.2, 0), c),
	}
	if horizontal then
		-- Cushion/mattress/bench read: same slab lying on the feet; the face
		-- lives on the thin front edge so the scale drops with it.
		local slab = P(model, "Slab", "Block", Vector3.new(2.2, 0.35, 2.2), CFrame.new(0, 0.575, 0), c)
		return {
			primary = slab,
			face = faceFrame(Vector3.new(0, 0.6, -1.1), FRONT),
			faceScale = 0.45,
			top = Vector3.new(0, 0.75, 0),
			backPos = Vector3.new(0, 0.7, 0.9),
			rearPos = Vector3.new(0, 0.575, 1.1),
			rightArm = Vector3.new(1.15, 0.6, 0),
			halfWidth = 1.1,
			halfDepth = 1.1,
			bottomY = 0.4,
			feet = feet,
		}
	end
	-- Tilted back 12 deg so the flat face catches light and reads at distance.
	local slabCF = CFrame.new(0, 1.45, 0) * CFrame.Angles(math.rad(12), 0, 0)
	local slab = P(model, "Slab", "Block", Vector3.new(2.2, 2.2, 0.35), slabCF, c)
	-- Yaw 180 puts the wedge slope descending away from the slab: a kickstand.
	P(model, "Kickstand", "Wedge", Vector3.new(0.6, 1, 0.4), CFrame.new(0, 0.5, 0.55) * CFrame.Angles(0, math.rad(180), 0), c)
	Cyl(model, "Arm", 0.25, 0.5, CFrame.new(1.2, 1.5, 0.15) * CFrame.Angles(0, 0, math.rad(-20)), "X", c)
	Cyl(model, "Arm", 0.25, 0.5, CFrame.new(-1.2, 1.5, 0.15) * CFrame.Angles(0, 0, math.rad(20)), "X", c)
	return {
		primary = slab,
		face = slabCF * CFrame.new(0, 0.25, -0.19),
		faceScale = 1.1,
		top = (slabCF * CFrame.new(0, 1.12, 0)).Position,
		backPos = (slabCF * CFrame.new(0, 0.5, 0.2)).Position,
		rearPos = Vector3.new(0, 1, 0.5),
		rightArm = Vector3.new(1.35, 1.5, 0.15),
		halfWidth = 1.1,
		halfDepth = 0.5,
		bottomY = 0.4,
		feet = feet,
	}
end

local function bodyNoodle(model, c, variant)
	if hasToken(variant, "tube") or hasToken(variant, "flare") then
		local feet = {
			P(model, "Foot", "Block", Vector3.new(0.6, 0.35, 0.8), CFrame.new(-0.4, 0.175, 0.2), c),
			P(model, "Foot", "Block", Vector3.new(0.6, 0.35, 0.8), CFrame.new(0.4, 0.175, 0.2), c),
		}
		local shaft, face, faceScale
		if hasToken(variant, "flare") then
			-- Megafono: literal 0.5/0.8/1.1 flare stack at the mouth end — the
			-- pinch-then-flare silhouette is the horn joke.
			shaft = Cyl(model, "Shaft", 0.85, 1.8, CFrame.new(0, 0.675, 0.35), "Z", c)
			Cyl(model, "Flare", 0.5, 0.2, CFrame.new(0, 0.675, -0.6), "Z", c)
			Cyl(model, "Flare", 0.8, 0.2, CFrame.new(0, 0.675, -0.8), "Z", c)
			Cyl(model, "Flare", 1.1, 0.2, CFrame.new(0, 0.675, -1), "Z", c)
			face = faceFrame(Vector3.new(0, 0.675, -1.12), FRONT)
			faceScale = 0.55
		else
			shaft = Cyl(model, "Shaft", 0.85, 2.6, CFrame.new(0, 0.675, 0), "Z", c)
			face = faceFrame(Vector3.new(0, 0.675, -1.3), FRONT)
			faceScale = 0.6
		end
		return {
			primary = shaft,
			face = face,
			faceScale = faceScale,
			top = Vector3.new(0, 1.1, 0),
			backPos = Vector3.new(0, 1, 0.9),
			rearPos = Vector3.new(0, 0.675, 1.3),
			rightArm = Vector3.new(0.6, 0.7, -0.3),
			halfWidth = 0.45,
			halfDepth = 1.3,
			bottomY = 0.25,
			feet = feet,
		}
	end
	local feet = {
		P(model, "Foot", "Block", Vector3.new(0.6, 0.35, 0.8), CFrame.new(-0.4, 0.175, -0.05), c),
		P(model, "Foot", "Block", Vector3.new(0.6, 0.35, 0.8), CFrame.new(0.4, 0.175, -0.05), c),
	}
	-- Negative X rotation leans the top toward -Z: a slight forward, curious lean.
	local shaftCF = CFrame.new(0, 1.65, 0) * CFrame.Angles(math.rad(-8), 0, 0)
	local shaft = Cyl(model, "Shaft", 0.85, 2.7, shaftCF, "Y", c)
	if hasToken(variant, "tool") then
		P(model, "ToolHead", "Block", Vector3.new(0.9, 0.5, 0.5), shaftCF * CFrame.new(0, 1.5, 0), STEEL)
	else
		P(model, "Cap", "Ball", Vector3.new(0.95, 0.95, 0.95), shaftCF * CFrame.new(0, 1.6, 0), c)
	end
	Cyl(model, "Arm", 0.22, 0.5, shaftCF * CFrame.new(0.55, -0.1, 0) * CFrame.Angles(0, 0, math.rad(-25)), "X", c)
	Cyl(model, "Arm", 0.22, 0.5, shaftCF * CFrame.new(-0.55, -0.1, 0) * CFrame.Angles(0, 0, math.rad(25)), "X", c)
	return {
		primary = shaft,
		face = shaftCF * CFrame.new(0, 0.8, -0.44),
		faceScale = 0.6,
		top = (shaftCF * CFrame.new(0, 2.05, 0)).Position,
		backPos = (shaftCF * CFrame.new(0, 0.6, 0.45)).Position,
		rearPos = Vector3.new(0, 1.2, 0.5),
		rightArm = Vector3.new(0.75, 1.55, 0),
		halfWidth = 0.45,
		halfDepth = 0.45,
		bottomY = 0.35,
		feet = feet,
	}
end

local function bodyShoe(model, c, variant)
	-- Sole darker than the upper: the two-tone is what makes it read "shoe"
	-- instead of "loaf with a bump".
	local soleColor = c:Lerp(Color3.new(0, 0, 0), 0.25)
	local sole = P(model, "Sole", "Block", Vector3.new(1.2, 0.45, 2.4), CFrame.new(0, 0.225, 0), soleColor)
	P(model, "ToeCap", "Ball", Vector3.new(1.15, 1.15, 1.15), CFrame.new(0, 0.5, -0.7), c)
	P(model, "Heel", "Block", Vector3.new(0.9, 0.85, 0.9), CFrame.new(0, 0.875, 0.7), c)
	Cyl(model, "Collar", 0.95, 0.55, CFrame.new(0, 1.45, 0.7), "Y", c)
	P(model, "Tongue", "Wedge", Vector3.new(0.5, 0.4, 0.6), CFrame.new(0, 0.62, -0.1) * CFrame.Angles(math.rad(-25), 0, 0), c)
	return {
		primary = sole,
		face = faceFrame(Vector3.new(0, 0.65, -1.24), Vector3.new(0, 0.2, -0.98)),
		faceScale = 0.75,
		-- Headgear mounts over the toe cap: that is where the character lives.
		top = Vector3.new(0, 1.1, -0.7),
		backPos = Vector3.new(0, 1.15, 0.9),
		rearPos = Vector3.new(0, 0.7, 1.2),
		rightArm = Vector3.new(0.65, 0.5, -0.3),
		halfWidth = 0.6,
		halfDepth = 1.2,
		bottomY = 0,
		feet = {},
	}
end

local function bodyBoat(model, c, variant, accent)
	local hull = P(model, "Hull", "Block", Vector3.new(1.3, 0.7, 2.8), CFrame.new(0, 0.35, 0), c)
	-- Default wedge: vertical face aft (against the hull), ramp rising from the
	-- waterline tip — a prow. The stern mirrors it with a 180 yaw.
	P(model, "Bow", "Wedge", Vector3.new(1.3, 0.7, 1), CFrame.new(0, 0.35, -1.9), c)
	P(model, "Stern", "Wedge", Vector3.new(1.3, 0.7, 0.8), CFrame.new(0, 0.35, 1.8) * CFrame.Angles(0, math.rad(180), 0), c)
	P(model, "Deck", "Block", Vector3.new(1, 0.2, 2), CFrame.new(0, 0.8, 0), c:Lerp(accent, 0.35))
	P(model, "Cabin", "Block", Vector3.new(0.8, 0.6, 0.8), CFrame.new(0, 1.2, 0.5), c)
	return {
		primary = hull,
		face = faceFrame(Vector3.new(0, 0.62, -1.72), Vector3.new(0, 0.3, -0.95)),
		faceScale = 0.8,
		top = Vector3.new(0, 1.5, 0.5),
		backPos = Vector3.new(0, 1.1, 1.3),
		rearPos = Vector3.new(0, 0.45, 2.15),
		rightArm = Vector3.new(0.8, 0.6, -0.5),
		halfWidth = 0.65,
		halfDepth = 1.4,
		bottomY = 0,
		feet = {},
	}
end

local function bodyCart(model, c, variant)
	local sled = hasToken(variant, "sled")
	local cable = hasToken(variant, "cable")
	local chassisY
	if sled then
		chassisY = 0.7
		P(model, "Skid", "Wedge", Vector3.new(0.3, 0.3, 1.8), CFrame.new(-0.6, 0.15, 0) * CFrame.Angles(0, math.rad(180), 0), STEEL)
		P(model, "Skid", "Wedge", Vector3.new(0.3, 0.3, 1.8), CFrame.new(0.6, 0.15, 0) * CFrame.Angles(0, math.rad(180), 0), STEEL)
	elseif cable then
		-- Cable car: nothing underneath; the hover motion sells the suspension.
		chassisY = 0.75
	else
		chassisY = 0.8
		for _, x in ipairs({ -0.72, 0.72 }) do
			for _, z in ipairs({ -0.75, 0.75 }) do
				Cyl(model, "Wheel", 0.8, 0.28, CFrame.new(x, 0.4, z), "X", TIRE)
			end
		end
	end
	local chassis = P(model, "Chassis", "Block", Vector3.new(1.4, 0.8, 2.3), CFrame.new(0, chassisY, 0), c)
	P(model, "Cab", "Block", Vector3.new(1.3, 0.9, 1), CFrame.new(0, chassisY + 0.85, 0.55), c)
	return {
		primary = chassis,
		face = faceFrame(Vector3.new(0, chassisY, -1.15), FRONT),
		faceScale = 0.85,
		top = Vector3.new(0, chassisY + 1.3, 0.55),
		backPos = Vector3.new(0, chassisY + 1, 1.05),
		rearPos = Vector3.new(0, chassisY, 1.15),
		rightArm = Vector3.new(0.85, chassisY + 0.1, -0.4),
		halfWidth = 0.7,
		halfDepth = 1.15,
		bottomY = chassisY - 0.4,
		feet = {},
	}
end

local function bodyPot(model, c, variant)
	local pan = hasToken(variant, "pan")
	local bottle = hasToken(variant, "bottle")
	local dia, height
	if pan then
		dia, height = 1.8, 0.7
	elseif bottle then
		dia, height = 1.2, 2.2
	else
		dia, height = 1.8, 1.6
	end
	local bodyY = height / 2
	local radius = dia / 2
	local body = Cyl(model, "Body", dia, height, CFrame.new(0, bodyY, 0), "Y", c)
	local topY = height
	if bottle then
		Cyl(model, "Cork", 0.5, 0.3, CFrame.new(0, height + 0.15, 0), "Y", WOOD)
		topY = height + 0.3
	elseif not pan then
		Cyl(model, "Lid", 1.9, 0.22, CFrame.new(0, height + 0.11, 0), "Y", c)
		P(model, "Knob", "Ball", Vector3.new(0.35, 0.35, 0.35), CFrame.new(0, height + 0.36, 0), c)
		topY = height + 0.5
	end
	-- Rotating about Z by +40 tips the outer (+X) end of the spout upward.
	Cyl(model, "Spout", 0.4, 0.7, CFrame.new(radius + 0.15, bodyY + height * 0.2, 0) * CFrame.Angles(0, 0, math.rad(40)), "X", c)
	P(model, "Handle", "Block", Vector3.new(0.15, 0.8, 0.15), CFrame.new(-(radius + 0.12), bodyY, 0) * CFrame.Angles(0, 0, math.rad(8)), c)
	local faceScale = pan and 0.55 or (bottle and 0.7 or 0.95)
	return {
		primary = body,
		face = faceFrame(Vector3.new(0, bodyY + height * 0.1, -radius), FRONT),
		faceScale = faceScale,
		top = Vector3.new(0, topY, 0),
		backPos = Vector3.new(0, bodyY + height * 0.25, radius - 0.05),
		rearPos = Vector3.new(0, bodyY, radius),
		rightArm = Vector3.new(radius + 0.1, bodyY, -0.2),
		halfWidth = radius,
		halfDepth = radius,
		bottomY = 0,
		feet = {},
	}
end

local function bodyTower(model, c, variant, accent)
	local dome = hasToken(variant, "dome")
	local obelisk = hasToken(variant, "obelisk")
	local shop = hasToken(variant, "shop")
	P(model, "Base", "Block", Vector3.new(2, 0.6, 2), CFrame.new(0, 0.3, 0), c)
	if obelisk then
		-- Taper via two stacked blocks; no cornice, no roof — the silhouette IS
		-- the monument.
		local shaft = P(model, "Shaft", "Block", Vector3.new(1.1, 1.1, 1.1), CFrame.new(0, 1.15, 0), c)
		P(model, "ShaftTop", "Block", Vector3.new(0.7, 1.1, 0.7), CFrame.new(0, 2.25, 0), c)
		return {
			primary = shaft,
			face = faceFrame(Vector3.new(0, 2.25, -0.37), FRONT),
			faceScale = 0.55,
			top = Vector3.new(0, 2.85, 0),
			backPos = Vector3.new(0, 2.2, 0.37),
			rearPos = Vector3.new(0, 1.3, 0.57),
			rightArm = Vector3.new(0.6, 1.5, 0),
			halfWidth = 1,
			halfDepth = 1,
			bottomY = 0,
			feet = {},
		}
	end
	local shaft, shaftTopY, facePos, faceScale
	if shop then
		shaft = P(model, "Shaft", "Block", Vector3.new(1.8, 1.2, 1.6), CFrame.new(0, 1.2, 0), c)
		shaftTopY = 1.8
		facePos = Vector3.new(0, 1.35, -0.82)
		faceScale = 0.8
		-- Negative X tilt dips the awning's front edge over the face.
		P(model, "Awning", "Block", Vector3.new(1.6, 0.1, 0.5), CFrame.new(0, 1.62, -1.02) * CFrame.Angles(math.rad(-12), 0, 0), accent)
	else
		shaft = P(model, "Shaft", "Block", Vector3.new(1.3, 2.2, 1.3), CFrame.new(0, 1.7, 0), c)
		shaftTopY = 2.8
		facePos = Vector3.new(0, 2.35, -0.67)
		faceScale = 0.85
	end
	local corniceY = shaftTopY + 0.125
	P(model, "Cornice", "Block", Vector3.new(1.6, 0.25, 1.6), CFrame.new(0, corniceY, 0), c)
	local roofBaseY = corniceY + 0.125
	local topY
	if dome then
		-- Half-sunk ball on the cornice = duomo.
		P(model, "Dome", "Ball", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, roofBaseY, 0), c:Lerp(accent, 0.3))
		topY = roofBaseY + 0.6
	else
		-- Two wedges vertical-face-to-vertical-face form the roof ridge.
		P(model, "Roof", "Wedge", Vector3.new(1.3, 0.7, 0.65), CFrame.new(0, roofBaseY + 0.35, -0.325), c:Lerp(accent, 0.25))
		P(model, "Roof", "Wedge", Vector3.new(1.3, 0.7, 0.65), CFrame.new(0, roofBaseY + 0.35, 0.325) * CFrame.Angles(0, math.rad(180), 0), c:Lerp(accent, 0.25))
		topY = roofBaseY + 0.7
	end
	return {
		primary = shaft,
		face = faceFrame(facePos, FRONT),
		faceScale = faceScale,
		top = Vector3.new(0, topY, 0),
		backPos = Vector3.new(0, shaftTopY - 0.5, -facePos.Z),
		rearPos = Vector3.new(0, 1.5, -facePos.Z + 0.03),
		rightArm = Vector3.new(-facePos.Z + 0.1, 1.7, 0),
		halfWidth = 1,
		halfDepth = 1,
		bottomY = 0,
		feet = {},
	}
end

local function bodyCritter(model, c, variant)
	local headless = hasToken(variant, "headless")
	local feet = {}
	local i = 0
	for _, x in ipairs({ -0.35, 0.35 }) do
		for _, z in ipairs({ -0.65, 0.65 }) do
			i += 1
			feet[i] = Cyl(model, "Leg", 0.3, 0.55, CFrame.new(x, 0.275, z), "Y", c)
		end
	end
	local torso = P(model, "Torso", "Block", Vector3.new(1, 1, 1.9), CFrame.new(0, 1, 0), c)
	local face, top
	if headless then
		face = faceFrame(Vector3.new(0, 1.05, -0.96), FRONT)
		top = Vector3.new(0, 1.5, 0)
	else
		P(model, "Head", "Ball", Vector3.new(1.05, 1.05, 1.05), CFrame.new(0, 1.55, -0.85), c)
		face = faceFrame(Vector3.new(0, 1.6, -1.32), Vector3.new(0, 0.15, -0.99))
		top = Vector3.new(0, 2.1, -0.85)
	end
	return {
		primary = torso,
		face = face,
		faceScale = 0.7,
		top = top,
		backPos = Vector3.new(0, 1.4, 0.85),
		rearPos = Vector3.new(0, 1.05, 0.96),
		rightArm = Vector3.new(0.6, 1, -0.3),
		halfWidth = 0.5,
		halfDepth = 0.95,
		bottomY = 0.5,
		feet = feet,
	}
end

local function bodyOrb(model, c, variant, accent)
	-- Secrets-only body: SmoothPlastic core, Neon ring/chunks, shimmer allowed
	-- on ring and chunks ONLY (eyes stay plain — palette rule).
	local core = P(model, "Core", "Ball", Vector3.new(2.2, 2.2, 2.2), CFrame.new(0, 1.6, 0), c, Enum.Material.SmoothPlastic)
	local ring = Cyl(model, "Ring", 3.3, 0.12, CFrame.new(0, 1.6, 0) * CFrame.Angles(math.rad(18), 0, 0), "Y", accent, Enum.Material.Neon)
	ring.Transparency = 0.1
	P(model, "Chunk", "Ball", Vector3.new(0.5, 0.5, 0.5), CFrame.new(1.5, 2, -0.9), accent, Enum.Material.Neon)
	P(model, "Chunk", "Ball", Vector3.new(0.35, 0.35, 0.35), CFrame.new(-1.45, 1.15, 0.7), accent, Enum.Material.Neon)
	P(model, "Chunk", "Ball", Vector3.new(0.3, 0.3, 0.3), CFrame.new(0.75, 2.55, 0.95), accent, Enum.Material.Neon)
	return {
		primary = core,
		face = faceFrame(Vector3.new(0, 1.85, -1.03), Vector3.new(0, 0.22, -0.97)),
		faceScale = 1,
		top = Vector3.new(0, 2.72, 0),
		backPos = Vector3.new(0, 2.2, 0.8),
		rearPos = Vector3.new(0, 1.6, 1.05),
		rightArm = Vector3.new(1.15, 1.6, 0),
		halfWidth = 1.1,
		halfDepth = 1.1,
		bottomY = 0.55,
		feet = {},
	}
end

local function bodyBlob(model, c, variant, accent)
	local feet = {
		P(model, "Foot", "Block", Vector3.new(0.65, 0.35, 0.85), CFrame.new(-0.5, 0.175, -0.3), c),
		P(model, "Foot", "Block", Vector3.new(0.65, 0.35, 0.85), CFrame.new(0.5, 0.175, -0.3), c),
	}
	local core = P(model, "Core", "Ball", Vector3.new(2.1, 1.7, 1.9), CFrame.new(0, 1.05, 0), c)
	P(model, "Tuft", "Ball", Vector3.new(0.35, 0.35, 0.35), CFrame.new(0, 2, 0), c:Lerp(accent, 0.6))
	Cyl(model, "Arm", 0.25, 0.5, CFrame.new(1.05, 1, 0) * CFrame.Angles(0, 0, math.rad(-25)), "X", c)
	Cyl(model, "Arm", 0.25, 0.5, CFrame.new(-1.05, 1, 0) * CFrame.Angles(0, 0, math.rad(25)), "X", c)
	return {
		primary = core,
		face = faceFrame(Vector3.new(0, 1.2, -0.92), Vector3.new(0, 0.1, -0.99)),
		faceScale = 1,
		top = Vector3.new(0, 2.1, 0),
		backPos = Vector3.new(0, 1.5, 0.8),
		rearPos = Vector3.new(0, 1.05, 0.93),
		rightArm = Vector3.new(1.15, 1, 0),
		halfWidth = 1.05,
		halfDepth = 0.95,
		bottomY = 0.2,
		feet = feet,
	}
end

local BODIES = {
	loaf = bodyLoaf,
	ball = bodyBall,
	slab = bodySlab,
	noodle = bodyNoodle,
	shoe = bodyShoe,
	boat = bodyBoat,
	cart = bodyCart,
	pot = bodyPot,
	tower = bodyTower,
	critter = bodyCritter,
	orb = bodyOrb,
	blob = bodyBlob,
}

--------------------------------------------------------------------------------
-- Faces. Contract sizes assume a 1.0-scale face; everything multiplies by the
-- body's faceScale so eyes never dwarf a noodle or vanish on a slab.
-- Eye parts are named Sclera/Pupil so downstream code (ghost transparency,
-- silhouette thumbnails) can find them without tags.
--------------------------------------------------------------------------------

local function addEyes(model, faceCF, s, opts)
	opts = opts or {}
	local scleraD = (opts.sclera or 0.34) * s
	local pupilD = (opts.pupil or 0.15) * s
	for _, side in ipairs({ -1, 1 }) do
		local shift = (side < 0 and opts.shiftL or opts.shiftR) or Vector2.new(0, 0)
		P(model, "Sclera", "Ball", Vector3.new(scleraD, scleraD, scleraD),
			faceCF * CFrame.new(side * 0.26 * s, 0.08 * s, -0.02 * s), WHITE, Enum.Material.SmoothPlastic)
		P(model, "Pupil", "Ball", Vector3.new(pupilD, pupilD, pupilD),
			faceCF * CFrame.new(side * 0.26 * s + shift.X * s, 0.08 * s + shift.Y * s, -0.02 * s - scleraD * 0.42),
			BLACK, Enum.Material.SmoothPlastic)
	end
end

local FACES = {}

function FACES.happy(model, faceCF, s, bodyColor, accent)
	addEyes(model, faceCF, s)
	P(model, "Mouth", "Block", Vector3.new(0.46 * s, 0.09 * s, 0.06 * s), faceCF * CFrame.new(0, -0.26 * s, -0.04 * s), MOUTH)
end

function FACES.derp(model, faceCF, s, bodyColor, accent)
	-- Mismatched pupils are the whole joke.
	addEyes(model, faceCF, s, { shiftL = Vector2.new(0, 0.06), shiftR = Vector2.new(0.02, -0.05) })
	P(model, "Mouth", "Block", Vector3.new(0.4 * s, 0.09 * s, 0.06 * s),
		faceCF * CFrame.new(0.04 * s, -0.26 * s, -0.03 * s) * CFrame.Angles(0, 0, math.rad(10)), MOUTH)
	P(model, "Tongue", "Block", Vector3.new(0.16 * s, 0.14 * s, 0.06 * s), faceCF * CFrame.new(0.08 * s, -0.37 * s, -0.03 * s), TONGUE)
end

function FACES.angry(model, faceCF, s, bodyColor, accent)
	addEyes(model, faceCF, s)
	-- Brows take the ACCENT color (palette rule) and angle inner-end-down.
	for _, side in ipairs({ -1, 1 }) do
		P(model, "Brow", "Block", Vector3.new(0.32 * s, 0.09 * s, 0.06 * s),
			faceCF * CFrame.new(side * 0.24 * s, 0.3 * s, -0.05 * s) * CFrame.Angles(0, 0, side * math.rad(20)), accent)
	end
	P(model, "Mouth", "Block", Vector3.new(0.34 * s, 0.09 * s, 0.06 * s), faceCF * CFrame.new(0, -0.3 * s, -0.04 * s), MOUTH)
end

function FACES.sleepy(model, faceCF, s, bodyColor, accent)
	addEyes(model, faceCF, s, { shiftL = Vector2.new(0, -0.04), shiftR = Vector2.new(0, -0.04) })
	-- Lids in the body color read as skin folding over the eye.
	for _, side in ipairs({ -1, 1 }) do
		P(model, "Lid", "Block", Vector3.new(0.38 * s, 0.16 * s, 0.08 * s),
			faceCF * CFrame.new(side * 0.26 * s, 0.19 * s, -0.04 * s), bodyColor)
	end
	P(model, "Mouth", "Block", Vector3.new(0.18 * s, 0.08 * s, 0.06 * s), faceCF * CFrame.new(0, -0.28 * s, -0.04 * s), MOUTH)
end

function FACES.shocked(model, faceCF, s, bodyColor, accent)
	addEyes(model, faceCF, s, { sclera = 0.42, pupil = 0.12 })
	P(model, "Mouth", "Ball", Vector3.new(0.2 * s, 0.2 * s, 0.2 * s), faceCF * CFrame.new(0, -0.32 * s, -0.03 * s), MOUTH)
end

function FACES.smug(model, faceCF, s, bodyColor, accent)
	addEyes(model, faceCF, s)
	-- Heavy diagonal lids, outer-end-down, plus an off-center smirk.
	for _, side in ipairs({ -1, 1 }) do
		P(model, "Lid", "Block", Vector3.new(0.38 * s, 0.14 * s, 0.08 * s),
			faceCF * CFrame.new(side * 0.26 * s, 0.2 * s, -0.04 * s) * CFrame.Angles(0, 0, side * math.rad(-15)), bodyColor)
	end
	P(model, "Mouth", "Block", Vector3.new(0.3 * s, 0.08 * s, 0.06 * s),
		faceCF * CFrame.new(0.1 * s, -0.26 * s, -0.04 * s) * CFrame.Angles(0, 0, math.rad(12)), MOUTH)
end

--------------------------------------------------------------------------------
-- Accessories. Signature: fn(model, anchors, accent, variant, bodyColor,
-- bodyKey). All mount math is world-space (every body faces -Z), except the
-- face-relative pieces (moustache, necktie, instrument) which use the face
-- frame so they follow tilted faces.
--------------------------------------------------------------------------------

local ACCESSORIES = {}

ACCESSORIES.wings = function(model, a, accent, variant)
	local scale = hasToken(variant, "small") and 0.6 or 1
	local color = hasToken(variant, "black") and Color3.fromHex("#26222A") or WHITE
	for _, side in ipairs({ -1, 1 }) do
		-- Left wing yaws 180 so the wedge slope mirrors; roll then lifts the
		-- outer edge on both sides.
		local mirror = side < 0 and CFrame.Angles(0, math.rad(180), 0) or CFrame.new()
		P(model, "Wing", "Wedge", Vector3.new(1.2 * scale, 0.16 * scale, 0.7 * scale),
			CFrame.new(a.backPos + Vector3.new(side * 0.75 * scale, 0.1, 0.15)) * mirror * CFrame.Angles(0, 0, math.rad(15)), color)
		P(model, "WingTip", "Wedge", Vector3.new(0.7 * scale, 0.16 * scale, 0.45 * scale),
			CFrame.new(a.backPos + Vector3.new(side * 0.5 * scale, 0, 0.15 + 0.42 * scale)) * mirror * CFrame.Angles(0, 0, math.rad(15)), color)
	end
end

ACCESSORIES.hat = function(model, a, accent, variant)
	if hasToken(variant, "hex") then
		Cyl(model, "Bolt", 0.85, 0.35, CFrame.new(a.top + Vector3.new(0, 0.18, 0)), "Y", STEEL, Enum.Material.Metal)
		return
	end
	local hatCF = CFrame.new(a.top) * CFrame.Angles(0, 0, math.rad(8))
	Cyl(model, "Brim", 1.35, 0.1, hatCF * CFrame.new(0, 0.05, 0), "Y", accent)
	local crownH = hasToken(variant, "naval") and 0.3 or 0.6
	Cyl(model, "HatCrown", 0.85, crownH, hatCF * CFrame.new(0, 0.12 + crownH / 2, 0), "Y", accent)
end

ACCESSORIES.crown = function(model, a, accent, variant)
	Cyl(model, "CrownBand", 1, 0.28, CFrame.new(a.top + Vector3.new(0, 0.14, 0)), "Y", GOLD, Enum.Material.Metal)
	for _, off in ipairs({
		Vector3.new(0.36, 0.31, 0), Vector3.new(-0.36, 0.31, 0),
		Vector3.new(0, 0.31, 0.36), Vector3.new(0, 0.31, -0.36),
	}) do
		P(model, "CrownTip", "Ball", Vector3.new(0.14, 0.14, 0.14), CFrame.new(a.top + off), GOLD, Enum.Material.Metal)
	end
end

ACCESSORIES.moustache = function(model, a, accent, variant)
	local s = a.faceScale
	for _, side in ipairs({ -1, 1 }) do
		P(model, "Moustache", "Block", Vector3.new(0.5 * s, 0.13 * s, 0.1 * s),
			a.face * CFrame.new(side * 0.24 * s, -0.16 * s, -0.06 * s)
				* CFrame.Angles(0, side * math.rad(-18), 0) * CFrame.Angles(0, 0, side * math.rad(-15)), BLACK)
	end
end

ACCESSORIES.umbrella = function(model, a, accent, variant)
	-- Pitched 15 deg off the top-back per contract.
	local poleCF = CFrame.new(0, a.top.Y + 0.55, 0.3) * CFrame.Angles(math.rad(15), 0, 0)
	Cyl(model, "Pole", 0.09, 1.4, poleCF, "Y", STEEL)
	P(model, "PoleTip", "Ball", Vector3.new(0.14, 0.14, 0.14), poleCF * CFrame.new(0, 0.77, 0), accent)
	local canopyCF = poleCF * CFrame.new(0, 0.45, 0)
	for k = 0, 3 do
		-- Each wedge's slope descends toward its own outward -Z: a shallow pyramid.
		P(model, "Canopy", "Wedge", Vector3.new(0.7, 0.35, 0.7),
			canopyCF * CFrame.Angles(0, math.rad(90 * k), 0) * CFrame.new(0, 0, -0.26), accent)
	end
end

ACCESSORIES.wheels = function(model, a, accent, variant, bodyColor, bodyKey)
	if bodyKey == "cart" then
		-- Cart bodies build their own rolling stock (contract: skip).
		return
	end
	if hasToken(variant, "skid") then
		P(model, "Skid", "Wedge", Vector3.new(0.3, 0.3, 1.6), CFrame.new(-a.halfWidth * 0.8, a.bottomY - 0.15, 0) * CFrame.Angles(0, math.rad(180), 0), STEEL)
		P(model, "Skid", "Wedge", Vector3.new(0.3, 0.3, 1.6), CFrame.new(a.halfWidth * 0.8, a.bottomY - 0.15, 0) * CFrame.Angles(0, math.rad(180), 0), STEEL)
		return
	end
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			Cyl(model, "Wheel", 0.75, 0.25, CFrame.new(sx * a.halfWidth * 0.85, a.bottomY, sz * a.halfDepth * 0.6), "X", TIRE)
		end
	end
end

ACCESSORIES.propeller = function(model, a, accent, variant)
	if hasToken(variant, "rear") then
		Cyl(model, "PropHub", 0.3, 0.2, CFrame.new(a.rearPos + Vector3.new(0, 0, 0.18)), "Z", STEEL)
		for k = 0, 2 do
			P(model, "PropBlade", "Block", Vector3.new(0.85, 0.18, 0.06),
				CFrame.new(a.rearPos + Vector3.new(0, 0, 0.28)) * CFrame.Angles(0, 0, math.rad(120 * k)) * CFrame.new(0.5, 0, 0), accent)
		end
	else
		Cyl(model, "PropHub", 0.3, 0.2, CFrame.new(a.top + Vector3.new(0, 0.12, 0)), "Y", STEEL)
		for k = 0, 2 do
			P(model, "PropBlade", "Block", Vector3.new(0.85, 0.06, 0.18),
				CFrame.new(a.top + Vector3.new(0, 0.26, 0)) * CFrame.Angles(0, math.rad(120 * k), 0) * CFrame.new(0.5, 0, 0), accent)
		end
	end
end

ACCESSORIES.utensil = function(model, a, accent, variant)
	-- Rolled 30 deg outward at the right arm per contract.
	local toolCF = CFrame.new(a.rightArm + Vector3.new(0.15, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(-30))
	Cyl(model, "UtensilHandle", 0.14, 1.2, toolCF, "Y", STEEL, Enum.Material.Metal)
	if hasToken(variant, "spoon") then
		P(model, "SpoonBowl", "Ball", Vector3.new(0.5, 0.15, 0.35), toolCF * CFrame.new(0, 0.68, 0), STEEL, Enum.Material.Metal)
	else
		P(model, "ForkHead", "Block", Vector3.new(0.42, 0.3, 0.07), toolCF * CFrame.new(0, 0.7, 0), STEEL, Enum.Material.Metal)
		for _, x in ipairs({ -0.14, 0, 0.14 }) do
			P(model, "ForkTine", "Block", Vector3.new(0.07, 0.35, 0.06), toolCF * CFrame.new(x, 0.98, 0), STEEL, Enum.Material.Metal)
		end
	end
end

ACCESSORIES.instrument = function(model, a, accent, variant)
	local s = a.faceScale
	-- Chest mount hangs off the face frame so it follows tilted faces.
	local chestCF = a.face * CFrame.new(0, -(0.55 * s + 0.35), -0.1)
	if hasToken(variant, "drum") then
		Cyl(model, "Drum", 0.7, 0.3, chestCF, "Z", accent)
	else
		P(model, "MandolinBowl", "Ball", Vector3.new(0.7, 0.55, 0.25), chestCF, accent)
		local neckCF = chestCF * CFrame.new(0.05, 0.1, -0.03) * CFrame.Angles(0, 0, math.rad(40))
		P(model, "MandolinNeck", "Block", Vector3.new(0.14, 0.75, 0.08), neckCF * CFrame.new(0, 0.55, 0), WOOD)
		P(model, "Headstock", "Block", Vector3.new(0.2, 0.15, 0.1), neckCF * CFrame.new(0, 0.98, 0), WOOD)
	end
	P(model, "Strap", "Block", Vector3.new(0.08, 0.9, 0.06),
		a.face * CFrame.new(-0.25, -0.15, -0.08) * CFrame.Angles(0, 0, math.rad(-40)), Color3.fromHex("#4A3B2A"))
end

ACCESSORIES.cape = function(model, a, accent, variant)
	if hasToken(variant, "tie") or hasToken(variant, "neck") then
		local s = a.faceScale
		P(model, "Necktie", "Block", Vector3.new(0.35, 1.2, 0.07), a.face * CFrame.new(0, -(0.4 * s + 0.65), -0.03), accent)
		return
	end
	local pin = a.backPos + Vector3.new(0, 0.25, 0.08)
	-- Negative X tilt kicks the bottom hem out behind the body.
	P(model, "Cape", "Block", Vector3.new(1.4, 1.6, 0.07),
		CFrame.new(pin) * CFrame.Angles(math.rad(-12), 0, 0) * CFrame.new(0, -0.78, 0), accent)
	P(model, "Clasp", "Ball", Vector3.new(0.12, 0.12, 0.12), CFrame.new(pin + Vector3.new(-0.45, 0.02, -0.12)), GOLD, Enum.Material.Metal)
	P(model, "Clasp", "Ball", Vector3.new(0.12, 0.12, 0.12), CFrame.new(pin + Vector3.new(0.45, 0.02, -0.12)), GOLD, Enum.Material.Metal)
end

ACCESSORIES["spring-legs"] = function(model, a, accent, variant, bodyColor)
	-- Replaces the body's feet — destroy, don't hide, to protect part budget.
	for _, foot in ipairs(a.feet) do
		foot:Destroy()
	end
	table.clear(a.feet)
	local tentacle = hasToken(variant, "tentacle")
	local gap = hasToken(variant, "rigid") and 0 or 0.07
	local mounts
	if tentacle then
		mounts = {
			Vector3.new(-a.halfWidth * 0.55, 0, -a.halfDepth * 0.5), Vector3.new(a.halfWidth * 0.55, 0, -a.halfDepth * 0.5),
			Vector3.new(-a.halfWidth * 0.55, 0, a.halfDepth * 0.5), Vector3.new(a.halfWidth * 0.55, 0, a.halfDepth * 0.5),
		}
	else
		mounts = { Vector3.new(-a.halfWidth * 0.55, 0, 0), Vector3.new(a.halfWidth * 0.55, 0, 0) }
	end
	for _, m in ipairs(mounts) do
		local y0 = a.bottomY - 0.05
		Cyl(model, "Coil", 0.5, 0.1, CFrame.new(m.X, y0, m.Z), "Y", tentacle and accent or STEEL)
		Cyl(model, "Coil", 0.5, 0.1, CFrame.new(m.X, y0 - 0.1 - gap, m.Z), "Y", tentacle and accent or STEEL)
		if not tentacle then
			P(model, "SpringFoot", "Block", Vector3.new(0.55, 0.2, 0.7), CFrame.new(m.X, y0 - 0.25 - 2 * gap, m.Z), bodyColor)
		end
	end
end

ACCESSORIES.tail = function(model, a, accent, variant)
	local r = a.rearPos
	if hasToken(variant, "fin") then
		-- Yaw 180 puts the wedge's high edge forward: a dorsal/tail fin.
		P(model, "TailFin", "Wedge", Vector3.new(0.15, 0.6, 0.5), CFrame.new(r + Vector3.new(0, 0.3, 0.1)) * CFrame.Angles(0, math.rad(180), 0), accent)
		P(model, "DorsalFin", "Wedge", Vector3.new(0.12, 0.5, 0.4), CFrame.new(a.top + Vector3.new(0, 0.12, 0.1)) * CFrame.Angles(0, math.rad(180), 0), accent)
		return
	end
	if hasToken(variant, "sting") then
		-- Arc curls up and forward over the body top.
		P(model, "Tail", "Ball", Vector3.new(0.4, 0.4, 0.4), CFrame.new(r + Vector3.new(0, 0.25, 0.3)), accent)
		P(model, "Tail", "Ball", Vector3.new(0.3, 0.3, 0.3), CFrame.new(r + Vector3.new(0, 0.75, 0.3)), accent)
		P(model, "Tail", "Ball", Vector3.new(0.22, 0.22, 0.22), CFrame.new(r + Vector3.new(0, 1.15, 0.05)), accent)
		P(model, "Stinger", "Wedge", Vector3.new(0.25, 0.3, 0.2), CFrame.new(r + Vector3.new(0, 1.35, -0.2)) * CFrame.Angles(math.rad(-60), 0, 0), accent)
		return
	end
	P(model, "Tail", "Ball", Vector3.new(0.4, 0.4, 0.4), CFrame.new(r + Vector3.new(0, 0.05, 0.25)), accent)
	P(model, "Tail", "Ball", Vector3.new(0.3, 0.3, 0.3), CFrame.new(r + Vector3.new(0, 0.32, 0.55)), accent)
	P(model, "Tail", "Ball", Vector3.new(0.22, 0.22, 0.22), CFrame.new(r + Vector3.new(0, 0.55, 0.78)), accent)
	P(model, "TailTip", "Wedge", Vector3.new(0.25, 0.3, 0.2), CFrame.new(r + Vector3.new(0, 0.75, 0.95)) * CFrame.Angles(math.rad(35), 0, 0), accent)
end

ACCESSORIES.antenna = function(model, a, accent, variant)
	local needle = hasToken(variant, "needle")
	local tipD = hasToken(variant, "bell") and 0.2 or 0.13
	local glow = hasToken(variant, "glow")
	local stalkColor = needle and BRASS or accent
	local sides = needle and { 0 } or { -1, 1 }
	for _, side in ipairs(sides) do
		-- -side*20 about Z splays each stalk's top outward.
		local antCF = CFrame.new(a.top + Vector3.new(side * 0.14, 0.28, 0)) * CFrame.Angles(0, 0, -side * math.rad(20))
		Cyl(model, "Antenna", 0.06, 0.6, antCF, "Y", stalkColor, needle and Enum.Material.Metal or nil)
		P(model, "AntennaTip", "Ball", Vector3.new(tipD, tipD, tipD), antCF * CFrame.new(0, 0.36, 0),
			glow and accent or stalkColor, glow and Enum.Material.Neon or nil)
	end
end

ACCESSORIES.flame = function(model, a, accent, variant)
	local scale = hasToken(variant, "small") and 0.6 or 1
	local colors
	if hasToken(variant, "steam") then
		colors = { "#E8E8E8", "#CFCFCF", "#E8E8E8" }
	elseif hasToken(variant, "reactor") then
		colors = { "#39FF88", "#39FF88", "#39FF88" }
	else
		colors = { "#E25822", "#F5A623", "#FFD75E" }
	end
	local dias = { 0.5, 0.34, 0.2 }
	local offsets
	if hasToken(variant, "rear") then
		offsets = { Vector3.new(0.05, 0.05, 0.32), Vector3.new(-0.06, 0.02, 0.66), Vector3.new(0.03, 0.08, 0.92) }
	else
		offsets = { Vector3.new(0.05, 0.16, 0.02), Vector3.new(-0.06, 0.5, -0.03), Vector3.new(0.03, 0.78, 0.02) }
	end
	local base = hasToken(variant, "rear") and a.rearPos or a.top
	for i = 1, 3 do
		local d = dias[i] * scale
		P(model, "Flame", "Ball", Vector3.new(d, d, d), CFrame.new(base + offsets[i] * scale), Color3.fromHex(colors[i]), Enum.Material.Neon)
	end
end

ACCESSORIES["halo-ring"] = function(model, a, accent, variant)
	local cosmic = hasToken(variant, "cosmic")
	local lamp = hasToken(variant, "lamp")
	local dia = cosmic and 1.6 or 1.1
	-- Lamp variant sits ON the cap (it IS the lamp head); halo floats 0.35 up.
	local cf = CFrame.new(a.top + Vector3.new(0, lamp and 0.06 or 0.39, 0))
	if cosmic then
		cf = cf * CFrame.Angles(math.rad(15), 0, 0)
	end
	Cyl(model, "Halo", dia, 0.07, cf, "Y", accent, Enum.Material.Neon)
end

--------------------------------------------------------------------------------
-- Assembly
--------------------------------------------------------------------------------

local function applyAccessory(model, anchors, key, accent, bodyColor, bodyKey, name, slot)
	if key == nil then
		return
	end
	local base, variant = splitKey(key)
	local fn = base and ACCESSORIES[base]
	if not fn then
		warn(("[BrainrotBodyBuilder] %s: unknown %s %q — skipping accessory"):format(name, slot, tostring(key)))
		return
	end
	fn(model, anchors, accent, variant, bodyColor, bodyKey)
end

-- Model:GetBoundingBox() is pivot-oriented, and the slab/noodle primaries are
-- deliberately tilted — so seat the model with a hand-built world-aligned box:
-- per part, world half-extents of an oriented box are |R| * size/2.
local function worldAabb(model)
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local cf, size = part.CFrame, part.Size
			local hx = 0.5 * (math.abs(cf.XVector.X) * size.X + math.abs(cf.YVector.X) * size.Y + math.abs(cf.ZVector.X) * size.Z)
			local hy = 0.5 * (math.abs(cf.XVector.Y) * size.X + math.abs(cf.YVector.Y) * size.Y + math.abs(cf.ZVector.Y) * size.Z)
			local hz = 0.5 * (math.abs(cf.XVector.Z) * size.X + math.abs(cf.YVector.Z) * size.Y + math.abs(cf.ZVector.Z) * size.Z)
			local p = cf.Position
			minV = Vector3.new(math.min(minV.X, p.X - hx), math.min(minV.Y, p.Y - hy), math.min(minV.Z, p.Z - hz))
			maxV = Vector3.new(math.max(maxV.X, p.X + hx), math.max(maxV.Y, p.Y + hy), math.max(maxV.Z, p.Z + hz))
		end
	end
	return minV, maxV
end

function M.Build(name, recipe)
	local displayName = tostring(name)
	if type(recipe) ~= "table" then
		warn(("[BrainrotBodyBuilder] %s: recipe is %s, not a table — building the fallback blob"):format(displayName, typeof(recipe)))
		recipe = {}
	end

	local model = Instance.new("Model")
	model.Name = displayName

	local bodyColor = resolveColor(recipe.BodyColor, DEFAULT_BODY_COLOR, displayName, "BodyColor")
	local accent = resolveColor(recipe.Accent, DEFAULT_ACCENT, displayName, "Accent")

	local bodyBase, bodyVariant = splitKey(recipe.Body)
	local bodyFn = bodyBase and BODIES[bodyBase]
	if not bodyFn then
		if recipe.Body ~= nil then
			warn(("[BrainrotBodyBuilder] %s: unknown Body %q — falling back to blob"):format(displayName, tostring(recipe.Body)))
		end
		bodyBase, bodyVariant, bodyFn = "blob", "", BODIES.blob
	end
	local anchors = bodyFn(model, bodyColor, bodyVariant, accent)
	model.PrimaryPart = anchors.primary

	local faceFn = FACES[recipe.Face]
	if not faceFn then
		if recipe.Face ~= nil then
			warn(("[BrainrotBodyBuilder] %s: unknown Face %q — falling back to happy"):format(displayName, tostring(recipe.Face)))
		end
		faceFn = FACES.happy
	end
	faceFn(model, anchors.face, anchors.faceScale, bodyColor, accent)

	applyAccessory(model, anchors, recipe.Accessory, accent, bodyColor, bodyBase, displayName, "Accessory")
	applyAccessory(model, anchors, recipe.Accessory2, accent, bodyColor, bodyBase, displayName, "Accessory2")

	local motion = recipe.Motion
	if motion ~= nil and not MOTIONS[motion] then
		warn(("[BrainrotBodyBuilder] %s: unknown Motion %q — using none"):format(displayName, tostring(motion)))
		motion = nil
	end
	model:SetAttribute("Motion", motion or "none")
	CollectionService:AddTag(model, "BrainrotBody")

	-- Optional (fantasma rule): body shimmer never touches the eyes — white
	-- sclera + black pupil is the alive signal at every tier.
	if type(recipe.Transparency) == "number" then
		local t = math.clamp(recipe.Transparency, 0, 0.9)
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and part.Name ~= "Sclera" and part.Name ~= "Pupil" then
				part.Transparency = math.max(part.Transparency, t)
			end
		end
	end

	if type(recipe.Size) == "number" and recipe.Size > 0 then
		if recipe.Size ~= 1 then
			model:ScaleTo(recipe.Size)
		end
	elseif recipe.Size ~= nil then
		warn(("[BrainrotBodyBuilder] %s: bad Size %q — using 1"):format(displayName, tostring(recipe.Size)))
	end

	-- Contract: standing on Y=0, centered at the origin. Accessories (wheels,
	-- spring-legs) may extend below the built feet, so seat by bounding box
	-- instead of trusting each builder's ground math.
	local minV, maxV = worldAabb(model)
	local delta = Vector3.new(-(minV.X + maxV.X) / 2, -minV.Y, -(minV.Z + maxV.Z) / 2)
	if delta.Magnitude > 1e-4 then
		model:PivotTo(model:GetPivot() + delta)
	end

	return model
end

return M
