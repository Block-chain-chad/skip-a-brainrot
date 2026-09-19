-- IconForge: Pet-Sim-quality UI icons WITHOUT uploaded assets. Each icon is a
-- tiny primitive MODEL rendered in static ViewportFrames -- which is how Pet
-- Sim's own icons are made (they are 3D renders). Three stacked viewports per
-- icon, all showing clones of the same model:
--   Outline -- ImageColor3 = ink, camera pulled ~10% closer, so the render is a
--             slightly LARGER black silhouette: the chunky cartoon outline.
--   Icon    -- the real render, bright ambient so colours stay candy.
-- No animation anywhere: cameras are fixed, models are anchored. (The rail's
-- old 3D icons were removed for their idle sway, not for being 3D.)

local UITheme = require(script.Parent.UITheme)
local CF = UITheme.Camp

local M = {}

local V = Vector3.new
local RAD = math.rad

--============================= part helpers ================================--
local function P(model, class, size, cf, color, material)
	local part
	if class == "Wedge" then
		part = Instance.new("WedgePart")
	else
		part = Instance.new("Part")
		part.Shape = Enum.PartType[class]
	end
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

-- cylinders lie along X natively; stand them up (Y) or face the camera (Z)
local AXIS = {
	X = CFrame.new(),
	Y = CFrame.Angles(0, 0, RAD(90)),
	Z = CFrame.Angles(0, RAD(90), 0),
}
local function Cyl(model, dia, len, cf, axis, color, material)
	return P(model, "Cylinder", V(len, dia, dia), cf * AXIS[axis], color, material)
end

--=============================== palettes ==================================--
local RED1 = Color3.fromRGB(232, 64, 78)
local RED2 = Color3.fromRGB(196, 44, 58)
local GOLD1 = Color3.fromRGB(255, 199, 44)
local GOLD2 = Color3.fromRGB(226, 158, 22)
local CREAM = Color3.fromRGB(248, 240, 218)
local PAGE = Color3.fromRGB(236, 224, 196)
local TEAL1 = Color3.fromRGB(38, 166, 154)
local TEAL2 = Color3.fromRGB(24, 122, 112)
local WHITE = Color3.fromRGB(245, 245, 245)
local PINE1 = Color3.fromRGB(84, 168, 92)
local PINE2 = Color3.fromRGB(52, 122, 62)
local STONE1 = Color3.fromRGB(148, 160, 172)

--============================ icon model kit ===============================--
-- Every builder returns a Model centred near the origin, FACING +Z (the
-- camera side), roughly 2.2 studs across. Chunky beats detailed: these render
-- at ~64px, so every feature must survive that.
local BUILDERS = {}

BUILDERS.gift = function(model)
	-- box + slightly wider lid + ribbon cross + three-ball bow
	P(model, "Block", V(1.55, 1.15, 1.15), CFrame.new(0, -0.25, 0), RED1)
	P(model, "Block", V(1.8, 0.42, 1.4), CFrame.new(0, 0.42, 0), RED2)
	P(model, "Block", V(0.34, 1.16, 1.17), CFrame.new(0, -0.25, 0.01), GOLD1)  -- front/back ribbon
	P(model, "Block", V(0.36, 0.44, 1.42), CFrame.new(0, 0.42, 0), GOLD2)      -- ribbon over lid
	P(model, "Ball", V(0.42, 0.42, 0.42), CFrame.new(-0.22, 0.75, 0), GOLD1)
	P(model, "Ball", V(0.42, 0.42, 0.42), CFrame.new(0.22, 0.75, 0), GOLD1)
	P(model, "Ball", V(0.3, 0.3, 0.3), CFrame.new(0, 0.82, 0), GOLD2)
end

BUILDERS.target = function(model)
	-- three rings + gold bull + arrow at a jaunty angle
	Cyl(model, 2.15, 0.22, CFrame.new(0, 0, -0.15), "Z", RED1)
	Cyl(model, 1.5, 0.26, CFrame.new(0, 0, -0.1), "Z", WHITE)
	Cyl(model, 0.85, 0.3, CFrame.new(0, 0, -0.05), "Z", RED2)
	P(model, "Ball", V(0.34, 0.34, 0.34), CFrame.new(0, 0, 0.1), GOLD1)
	local shaft = CFrame.new(0.42, 0.42, 0.42) * CFrame.Angles(RAD(-38), RAD(40), 0)
	Cyl(model, 0.11, 1.5, shaft, "Z", CREAM)
	P(model, "Wedge", V(0.1, 0.34, 0.42), shaft * CFrame.new(0, 0.1, 0.72) * CFrame.Angles(RAD(180), 0, 0), RED2)
	P(model, "Wedge", V(0.1, 0.34, 0.42), shaft * CFrame.new(0, -0.1, 0.72) * CFrame.Angles(0, 0, 0), RED2)
end

BUILDERS.star = function(model)
	-- A REAL five-point star: each point is two mirrored wedges forming an
	-- isoceles triangle, planted around a pentagon-ish core. (The first version
	-- was three crossed bars, which renders as a gear/flower, not a star.)
	-- Wedge geometry: a WedgePart's triangular profile lives in its LOCAL YZ
	-- plane (tall edge at -Z, sloping to zero height at +Z), extruded along X.
	-- Rotating +-90 about Y swings that profile into the SCREEN plane and makes
	-- the extrusion the thickness. Two mirrored halves share the tall edge at
	-- x=0, so together they read as one isoceles point. (Rotating about X
	-- instead -- the first attempt -- leaves the profile edge-on: blocky rays.)
	local CORE_R, PH, PW = 0.5, 0.92, 0.62
	for i = 0, 4 do
		local spin = CFrame.Angles(0, 0, RAD(72 * i))
		local center = spin * CFrame.new(0, CORE_R + PH / 2, 0)
		P(model, "Wedge", V(0.3, PH, PW), center * CFrame.new(PW / 2, 0, 0) * CFrame.Angles(0, RAD(90), 0), GOLD1)
		P(model, "Wedge", V(0.3, PH, PW), center * CFrame.new(-PW / 2, 0, 0) * CFrame.Angles(0, RAD(-90), 0), GOLD1)
	end
	Cyl(model, CORE_R * 2.15, 0.3, CFrame.new(0, 0, 0), "Z", GOLD1)
	Cyl(model, CORE_R * 1.5, 0.36, CFrame.new(0, 0, 0.05), "Z", GOLD2)
	P(model, "Ball", V(0.26, 0.26, 0.26), CFrame.new(-0.16, 0.18, 0.2), CREAM)   -- gloss dot
end

BUILDERS.book = function(model)
	-- Open book seen from the FRONT-ABOVE: the pages must present their broad
	-- face to the camera or the whole icon collapses to a sliver. Two page
	-- slabs tilted like an open V, teal covers underneath, spine down the middle.
	local L = CFrame.new(-0.62, 0, -0.02) * CFrame.Angles(RAD(-64), 0, RAD(13))
	local R = CFrame.new(0.62, 0, -0.02) * CFrame.Angles(RAD(-64), 0, RAD(-13))
	P(model, "Block", V(1.32, 1.5, 0.16), L * CFrame.new(0, -0.06, -0.14), TEAL2)   -- covers
	P(model, "Block", V(1.32, 1.5, 0.16), R * CFrame.new(0, -0.06, -0.14), TEAL2)
	P(model, "Block", V(1.22, 1.4, 0.14), L, PAGE)                                  -- page block
	P(model, "Block", V(1.22, 1.4, 0.14), R, PAGE)
	P(model, "Block", V(1.14, 1.3, 0.06), L * CFrame.new(0, 0.02, 0.1), CREAM)      -- top sheet
	P(model, "Block", V(1.14, 1.3, 0.06), R * CFrame.new(0, 0.02, 0.1), CREAM)
	for i = 1, 3 do                                                                 -- text lines
		local y = 0.34 - (i - 1) * 0.3
		P(model, "Block", V(0.72, 0.09, 0.04), L * CFrame.new(-0.04, y, 0.15), TEAL1)
		P(model, "Block", V(0.72, 0.09, 0.04), R * CFrame.new(0.04, y, 0.15), TEAL1)
	end
	P(model, "Block", V(0.2, 1.52, 0.44), CFrame.new(0, -0.1, -0.3) * CFrame.Angles(RAD(-64), 0, 0), TEAL1)  -- spine
end

BUILDERS.trophy = function(model)
	-- cup + flared rim + bowl bottom + stem + two-step base + curled handles
	Cyl(model, 1.1, 0.85, CFrame.new(0, 0.42, 0), "Y", GOLD1)
	Cyl(model, 1.3, 0.16, CFrame.new(0, 0.9, 0), "Y", GOLD2)
	P(model, "Ball", V(1.08, 0.72, 1.08), CFrame.new(0, -0.05, 0), GOLD1)
	Cyl(model, 0.26, 0.5, CFrame.new(0, -0.55, 0), "Y", GOLD2)
	P(model, "Block", V(0.85, 0.2, 0.6), CFrame.new(0, -0.88, 0), GOLD2)
	P(model, "Block", V(1.15, 0.18, 0.8), CFrame.new(0, -1.06, 0), RED2)        -- plinth
	for _, s in ipairs({ -1, 1 }) do
		Cyl(model, 0.15, 0.75, CFrame.new(s * 0.78, 0.45, 0) * CFrame.Angles(0, 0, RAD(-s * 28)), "Y", GOLD2)
		P(model, "Ball", V(0.24, 0.24, 0.24), CFrame.new(s * 0.62, 0.06, 0), GOLD2)
	end
	P(model, "Ball", V(0.3, 0.3, 0.3), CFrame.new(-0.28, 0.55, 0.45), CREAM)    -- gloss dot
end

-- Triangle helper: an isoceles point of height h and base width w, centred on
-- `cf`, standing in the SCREEN plane. Two mirrored wedges sharing their tall
-- edge -- see the note in BUILDERS.star for why the +-90 Y rotation matters.
local function triangle(model, cf, h, w, thick, color)
	P(model, "Wedge", V(thick, h, w / 2), cf * CFrame.new(w / 4, 0, 0) * CFrame.Angles(0, RAD(90), 0), color)
	P(model, "Wedge", V(thick, h, w / 2), cf * CFrame.new(-w / 4, 0, 0) * CFrame.Angles(0, RAD(-90), 0), color)
end

BUILDERS.tent = function(model)
	-- plot: a pine A-frame tent -- big triangle, dark doorway triangle, ground bar
	triangle(model, CFrame.new(0, 0.12, 0), 1.75, 2.05, 0.85, PINE1)
	triangle(model, CFrame.new(0, 0.02, 0.45), 1.35, 1.5, 0.12, PINE2)   -- shaded face
	triangle(model, CFrame.new(0, -0.24, 0.55), 0.85, 0.62, 0.1, CF.ink) -- doorway
	P(model, "Block", V(2.35, 0.2, 1.0), CFrame.new(0, -0.86, 0), PINE2) -- ground
	P(model, "Ball", V(0.16, 0.16, 0.16), CFrame.new(0, 1.05, 0), GOLD1) -- pole finial
end

BUILDERS.bag = function(model)
	-- shops: candy shopping bag, fold-over top, twin handle ARCS, big gold coin.
	-- Handles are three short segments each -- a single straight cylinder read as
	-- a stick and vanished at icon size.
	P(model, "Block", V(1.45, 1.5, 0.85), CFrame.new(0, -0.2, 0), TEAL1)
	P(model, "Block", V(1.56, 0.36, 0.92), CFrame.new(0, 0.63, 0), TEAL2)
	for _, s in ipairs({ -1, 1 }) do
		local hx = s * 0.36
		Cyl(model, 0.13, 0.42, CFrame.new(hx, 0.95, 0) * CFrame.Angles(0, 0, RAD(-s * 34)), "Y", GOLD2)
		Cyl(model, 0.13, 0.34, CFrame.new(s * 0.19, 1.16, 0) * CFrame.Angles(0, 0, RAD(-s * 68)), "Y", GOLD2)
		P(model, "Ball", V(0.14, 0.14, 0.14), CFrame.new(hx, 0.78, 0), GOLD2)
	end
	Cyl(model, 0.72, 0.14, CFrame.new(0.02, -0.24, 0.5), "Z", GOLD1)             -- coin face
	Cyl(model, 0.46, 0.16, CFrame.new(0.02, -0.24, 0.53), "Z", GOLD2)            -- coin inset
end

BUILDERS.stone = function(model)
	-- skip: the stone skipping OFF water -- the splash rings are what make it
	-- read as "skip" rather than "a rock". Stone up-left, three shrinking rings
	-- trailing down-right along the bounce path.
	local LAKE = Color3.fromRGB(86, 176, 214)
	P(model, "Ball", V(1.15, 0.42, 0.95), CFrame.new(-0.32, 0.62, 0) * CFrame.Angles(0, 0, RAD(-16)), STONE1)
	P(model, "Ball", V(0.38, 0.12, 0.3), CFrame.new(-0.45, 0.78, 0.3), WHITE)    -- sheen
	local rings = { { 0.15, -0.28, 1.15 }, { 0.72, -0.6, 0.85 }, { 1.2, -0.85, 0.58 } }
	for _, r in ipairs(rings) do
		Cyl(model, r[3], 0.14, CFrame.new(r[1], r[2], 0) * CFrame.Angles(RAD(74), 0, 0), "Y", LAKE)
		Cyl(model, r[3] * 0.6, 0.16, CFrame.new(r[1], r[2] + 0.02, 0) * CFrame.Angles(RAD(74), 0, 0), "Y", Color3.fromRGB(140, 208, 236))
	end
end

--======================== daily wheel icons (2026-08-18) ===================--
-- One per wedge, all six distinct in SILHOUETTE as well as colour. The wheel
-- previously used emoji, which render at whatever size and style the player's
-- device decides and read as clip-art next to the rest of this HUD. These render
-- at ~76px inside the wedge chips, so the same "chunky beats detailed" rule as
-- every icon above applies.
local EM1 = Color3.fromRGB(52, 214, 132)
local EM2 = Color3.fromRGB(26, 152, 94)
local EM3 = Color3.fromRGB(168, 248, 208)
local WOOD1 = Color3.fromRGB(178, 122, 66)
local WOOD2 = Color3.fromRGB(132, 86, 44)
local SKY1 = Color3.fromRGB(96, 206, 232)

BUILDERS.gem = function(model)
	-- emeralds: ONE SOLID MASS -- a square turned 45 degrees, flat-topped.
	--
	-- Two rebuilds got here. A `triangle` rotated 180 to make the pavilion does not
	-- flip the point downward (rotating the shared CFrame swaps which side each
	-- mirrored half sits on) and rendered as an arch. Replacing it with six stacked
	-- blocks narrowing to a culet fixed the shape but made the SILHOUETTE a
	-- staircase, and the outline pass traces every step -- which is precisely the
	-- "choppy" edge. A single rotated block has one clean diagonal edge; the facets
	-- go INSIDE it, where they cannot break the outline.
	P(model, "Block", V(1.46, 1.46, 0.72), CFrame.new(0, -0.12, 0) * CFrame.Angles(0, 0, RAD(45)), EM1)
	P(model, "Block", V(1.34, 0.46, 0.78), CFrame.new(0, 0.5, 0), EM1)      -- flat table on top
	P(model, "Block", V(1.16, 0.12, 0.82), CFrame.new(0, 0.68, 0), EM3)     -- table highlight
	P(model, "Block", V(0.56, 0.62, 0.84), CFrame.new(-0.3, 0.06, 0), EM2)  -- interior facet
	P(model, "Block", V(0.34, 0.34, 0.86), CFrame.new(0.34, -0.2, 0), EM3)  -- interior facet
end

BUILDERS.clover = function(model)
	-- luck: four lobes on a stem. Balls squashed on Z so they stay round from the
	-- front without bulging toward the camera.
	for i = 0, 3 do
		local a = RAD(90 * i + 45)
		P(model, "Ball", V(0.95, 0.95, 0.5),
			CFrame.new(math.cos(a) * 0.46, math.sin(a) * 0.46 + 0.18, 0), PINE1)
	end
	Cyl(model, 0.42, 0.28, CFrame.new(0, 0.18, 0.16), "Z", PINE2)                 -- centre knot
	Cyl(model, 0.16, 0.85, CFrame.new(0.16, -0.72, 0) * CFrame.Angles(0, 0, RAD(16)), "Y", PINE2)
	P(model, "Ball", V(0.26, 0.26, 0.14), CFrame.new(-0.42, 0.62, 0.26), Color3.fromRGB(196, 244, 200))
end

BUILDERS.bolt = function(model)
	-- power: a zigzag of three slanted bars.
	--
	-- TWO bars, parallel, offset along the diagonal. The OFFSET between them is the
	-- bolt's kink and it is the only feature that survives at 68px.
	--
	-- Two earlier tries failed differently and are worth not repeating: capping the
	-- ends with `triangle` scattered loose shapes everywhere, and three alternating
	-- bars read as a hook rather than a zigzag.
	-- The two bars must FUSE, not merely sit near each other. The outline pass shows
	-- ink through any gap BETWEEN parts, so a bolt whose halves meet only at a
	-- corner renders with a black seam across its middle and reads as two separate
	-- gold sticks. Tight offsets plus an explicit connector at the kink give the
	-- union one unbroken silhouette.
	P(model, "Block", V(0.86, 0.86, 0.36), CFrame.new(0, 0, 0), GOLD1)   -- fills the join
	for _, s in ipairs({ { 0.2, 0.42 }, { -0.2, -0.42 } }) do
		P(model, "Block", V(0.86, 1.4, 0.36),
			CFrame.new(s[1], s[2], 0) * CFrame.Angles(0, 0, RAD(30)), GOLD1)
	end
	-- brighter core, inset so it never reaches the silhouette
	for _, s in ipairs({ { 0.2, 0.42 }, { -0.2, -0.42 } }) do
		P(model, "Block", V(0.3, 1.0, 0.12),
			CFrame.new(s[1], s[2], 0.2) * CFrame.Angles(0, 0, RAD(30)), CREAM)
	end
end

BUILDERS.crate = function(model)
	-- the 1% loot crate. Deliberately NOT BUILDERS.gift: the jackpot wants weight,
	-- so this is a banded chest with a domed lid rather than a bow.
	P(model, "Block", V(1.6, 1.0, 1.05), CFrame.new(0, -0.34, 0), WOOD1)
	P(model, "Block", V(1.68, 0.2, 1.12), CFrame.new(0, 0.2, 0), WOOD2)           -- lid lip
	Cyl(model, 1.0, 1.66, CFrame.new(0, 0.26, 0), "X", WOOD1)                     -- domed lid
	for _, s in ipairs({ -1, 1 }) do
		P(model, "Block", V(0.2, 1.05, 1.1), CFrame.new(s * 0.6, -0.32, 0), GOLD2)   -- corner bands
		Cyl(model, 0.98, 0.2, CFrame.new(s * 0.6, 0.26, 0), "X", GOLD2)
	end
	P(model, "Block", V(0.34, 0.46, 0.16), CFrame.new(0, -0.02, 0.56), GOLD1)     -- clasp
	P(model, "Ball", V(0.2, 0.2, 0.2), CFrame.new(0, -0.06, 0.66), GOLD2)
	P(model, "Ball", V(0.26, 0.26, 0.16), CFrame.new(-0.38, 0.62, 0.3), CREAM)    -- gloss
end

BUILDERS.coins = function(model)
	-- cash: three coins seen FACE ON, overlapping up the diagonal.
	--
	-- The first version stacked them on their edges (axis "Y"). This camera is
	-- nearly front-on, so a flat-stacked coin presents its RIM -- three of them read
	-- as a bundle of tubes, not as money. Face-on discs are unmistakable.
	-- SPACING matters as much as the facing. The first face-on attempt put three
	-- 1.3-wide coins 0.46 apart, so each one covered all but a crescent of the one
	-- behind and the icon read as three yellow slivers. Two behind, one big in
	-- front, far enough apart that all three silhouettes are whole.
	local function coin(x, y, z, dia)
		Cyl(model, dia, 0.2, CFrame.new(x, y, z), "Z", GOLD1)
		Cyl(model, dia * 0.7, 0.24, CFrame.new(x, y, z + 0.04), "Z", GOLD2)
	end
	coin(-0.62, -0.5, 0.0, 1.02)
	coin(0.5, -0.66, 0.14, 1.02)
	coin(0.02, 0.44, 0.34, 1.36)
	-- a $ on the front coin: a bar and two crossbars is all that survives at 68px
	P(model, "Block", V(0.17, 0.74, 0.12), CFrame.new(0.02, 0.44, 0.54), CREAM)
	P(model, "Block", V(0.5, 0.16, 0.12), CFrame.new(0.02, 0.64, 0.54), CREAM)
	P(model, "Block", V(0.5, 0.16, 0.12), CFrame.new(0.02, 0.24, 0.54), CREAM)
end

BUILDERS.crown = function(model)
	-- the PRO WHEEL SPINNER title. A crown reads as RANK at a glance; the hanging
	-- name-plate this replaces rendered as a blank white card with two grey dashes
	-- on it -- accurate to the idea, and completely unreadable as a picture.
	P(model, "Block", V(1.95, 0.5, 0.72), CFrame.new(0, -0.52, 0), GOLD2)         -- band
	P(model, "Block", V(2.02, 0.17, 0.78), CFrame.new(0, -0.24, 0), GOLD1)        -- band lip
	-- three points, centre tallest. `triangle` pointing UP -- the direction it is
	-- known good in (BUILDERS.tent builds its A-frame the same way).
	for _, s in ipairs({ { -0.66, 0.6 }, { 0, 0.95 }, { 0.66, 0.6 } }) do
		triangle(model, CFrame.new(s[1], -0.16 + s[2] / 2, 0), s[2], 0.66, 0.68, GOLD1)
	end
	P(model, "Ball", V(0.26, 0.26, 0.2), CFrame.new(-0.66, 0.46, 0.3), RED1)      -- jewels
	P(model, "Ball", V(0.32, 0.32, 0.24), CFrame.new(0, 0.8, 0.32), TEAL1)
	P(model, "Ball", V(0.26, 0.26, 0.2), CFrame.new(0.66, 0.46, 0.3), RED1)
	P(model, "Ball", V(0.22, 0.22, 0.16), CFrame.new(0, -0.52, 0.38), CREAM)
end

--=============================== mounting ==================================--
-- Camera direction is fixed (three-quarter view from upper right); the DISTANCE
-- is fitted per icon from its real bounding box, so a tall trophy and a wide
-- gift both fill the frame instead of one cropping and the other floating in
-- space. Hand-tuned distances were exactly the bug that cropped the gift.
local CAM_DIR = V(0.42, 0.62, 3).Unit
local FOV = 32
local FIT = 1.28   -- >1 leaves breathing room so the outline pass cannot clip

local function fitDistance(model)
	local _, size = model:GetBoundingBox()
	local radius = math.max(size.X, size.Y, size.Z) * 0.5
	return (radius * FIT) / math.tan(RAD(FOV) * 0.5)
end

local function makeViewport(parent, model, zindex, dist)
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.AnchorPoint = Vector2.new(0.5, 0.5)
	vp.Position = UDim2.fromScale(0.5, 0.5)
	vp.ZIndex = zindex
	vp.Ambient = Color3.fromRGB(205, 205, 205)
	vp.LightColor = Color3.fromRGB(255, 252, 240)
	vp.LightDirection = V(-0.35, -0.7, -0.45)
	vp.Parent = parent
	local m = model:Clone()
	m.Parent = vp
	local center = model:GetBoundingBox()
	local cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	cam.CFrame = CFrame.lookAt(center.Position + CAM_DIR * dist, center.Position)
	cam.Parent = vp
	vp.CurrentCamera = cam
	return vp
end

-- Mount a finished icon into `parent` (an empty square Frame/button). Returns
-- the holder so callers can scale or hide the whole stack as one thing.
function M.Mount(parent, kind)
	local build = BUILDERS[kind]
	if not build then
		warn("[IconForge] unknown icon kind " .. tostring(kind))
		build = BUILDERS.star
	end
	local model = Instance.new("Model")
	build(model)

	local holder = Instance.new("Frame")
	holder.Name = "ForgedIcon"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1.16, 1.16)
	holder.ZIndex = parent.ZIndex or 1
	holder.Parent = parent

	local z = holder.ZIndex
	local dist = fitDistance(model)
	-- (drop shadow removed: on a white sticker card the glyph's own shadow
	-- read as smudge rather than depth. The ink outline below still gives the
	-- silhouette its definition.)
	-- Chunky outline: the same render pulled closer, pure ink, so a black silhouette
	-- peeks out around the icon on top of it.
	--
	-- 1.06, down from 1.12 (2026-08-18). This is a full ink render of the WHOLE
	-- model sitting behind the real one, so it does not only outline the outer
	-- silhouette -- it also shows through every gap BETWEEN parts. At 12% those
	-- internal seams were thick enough that a multi-part icon read as several
	-- pieces stacked on top of each other rather than as one object. Halving it
	-- keeps the cartoon outline and closes the seams.
	local outline = makeViewport(holder, model, z + 2, dist / 1.06)
	outline.ImageColor3 = CF.ink
	-- the icon itself
	makeViewport(holder, model, z + 3, dist)

	model:Destroy()   -- clones live in the viewports; the master is scaffolding
	return holder
end

return M
