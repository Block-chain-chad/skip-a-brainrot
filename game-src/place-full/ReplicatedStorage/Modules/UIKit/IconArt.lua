--!strict
--[[ =========================================================================
IconArt -- the design kit's nav icons, rebuilt from Roblox GUI primitives.
---------------------------------------------------------------------------
WHY THIS EXISTS. The kit ships each icon as an SVG (docs/design-handoff/
ui-kit/design_handoff_game_ui/icons/*.svg) plus a 512px PNG. Turning those
PNGs into Roblox image assets is still a pending user step -- and
AssetService:CreateAssetAsync is not available in this Studio session -- so
until real asset ids exist the rail would show empty slots. Rather than a
placeholder, this module redraws the SAME artwork out of Frames, straight
from the SVG geometry, so the rail matches captures/hud.png today.

The SHAPES table below is a transcription of those SVGs, in SVG user units,
in paint order. When real ids do land, nothing here needs deleting: the rail
prefers T.icons[id] whenever it is a non-empty string and only falls back to
IconArt.draw.

HOW THE KIT DRAWS. Every icon SVG paints twice. Pass 1 repeats each shape in
#16170F with stroke-width 9 (16/17 on stroked paths), which fattens it by 4.5
units on every side and produces the chunky dark keyline the style depends on.
Pass 2 paints the same shapes in colour on top. draw() reproduces exactly
that: every shape flagged `outline` is drawn once expanded by EXPAND in
keyline black, then all shapes are drawn again in colour. Doing it as a
separate pass -- rather than a UIStroke per shape -- is what keeps the keyline
on the icon's OUTER silhouette instead of drawing a seam between every pair of
touching shapes (e.g. the bag's flap against its body).

COORDINATES. Every icon uses viewBox "-5 -5 74 74": the drawable area spans
-5..69 on both axes, so a coordinate maps to pixels as (v + 5) * size / 74.
Y grows downward, matching both SVG and Roblox.
========================================================================= ]]

local IconArt = {}

local VB_MIN = -5   -- viewBox origin on both axes
local VB_SPAN = 74  -- viewBox width/height
local EXPAND = 4.5  -- half the kit's stroke-width 9 keyline, in SVG units
local KEYLINE = Color3.fromHex("#16170F")

--[[ Shape types the renderer understands:
  rect   x, y, w, h, r          -- r = corner radius, 0 = square
  circle cx, cy, radius
  bar    x1, y1, x2, y2, t      -- straight stroked segment, round caps
  arch   x1, x2, yTop, yBottom, t -- upside-down U, e.g. the bag handle
  star   cx, cy, outerRadius    -- 5-pointed star (drawn as a glyph)
Shared optional fields:
  rot / pivotX / pivotY   degrees clockwise, about a point (SVG rotate(a px py));
                          without a pivot the shape spins about its own centre
  fill                    flat colour
  gradTop / gradBottom    vertical gradient (used instead of fill)
  gradFixed               keep the gradient vertical on screen even though the
                          shape is rotated. Needed when the rotation is OUR
                          implementation detail rather than the kit's: the kit
                          rotates a gradient along with its shape (the pass
                          ticket), but a diamond we happen to build out of a
                          rotated square must still shade top-to-bottom.
  strokeColor/strokeWidth an inner stroke the COLOURED shape itself carries
  opacity                 0..1, default 1
  clip {x1,y1,x2,y2}      render inside this window -- how a rect gets two
                          rounded and two square corners, as several kit paths do
  outline                 true if the shape had a pass-1 dark duplicate
]]
IconArt.SHAPES = {
	bag = {
		{ type = "arch", x1 = 23, x2 = 41, yTop = 13, yBottom = 25, t = 7, fill = "#3F4038", outline = true, note = "handle" },
		{ type = "rect", x = 9, y = 22, w = 46, h = 34, r = 10, gradTop = "#FF7F5F", gradBottom = "#C22B18", outline = true, note = "body" },
		-- kit path "M9 32 v-2 a10 10 0 0 1 10-10 h26 a10 10 0 0 1 10 10 v2 z":
		-- a band with rounded TOP corners and square bottom -> tall rounded rect, clipped at y32
		{ type = "rect", x = 9, y = 20, w = 46, h = 24, r = 10, gradTop = "#E8543A", gradBottom = "#A02010", clip = { 9, 20, 55, 32 }, outline = true, note = "flap" },
		{ type = "rect", x = 26, y = 34, w = 12, h = 9, r = 3, fill = "#FFD84D", strokeColor = "#16170F", strokeWidth = 3, outline = true, note = "clasp" },
		{ type = "rect", x = 14, y = 26, w = 12, h = 5, r = 2.5, fill = "#FFFFFF", opacity = 0.4, outline = false, note = "gloss" },
	},

	pass = {
		{ type = "rect", x = 5, y = 17, w = 54, h = 30, r = 9, rot = -7, pivotX = 32, pivotY = 32, gradTop = "#DE93FF", gradBottom = "#7C1CC0", outline = true, note = "ticket" },
		-- kit polygon spans y20..41.7 about x32; for a regular 5-point star that
		-- solves to centre (32,32), outer radius 12.
		{ type = "star", cx = 32, cy = 32, outerRadius = 12, rot = -7, pivotX = 32, pivotY = 32, gradTop = "#FFE066", gradBottom = "#E8930F", outline = true, note = "star" },
		{ type = "rect", x = 11, y = 21, w = 20, h = 5, r = 2.5, rot = -7, pivotX = 32, pivotY = 32, fill = "#FFFFFF", opacity = 0.38, outline = false, note = "gloss" },
	},

	daily = {
		{ type = "rect", x = 8, y = 13, w = 48, h = 45, r = 9, gradTop = "#FAFAF4", gradBottom = "#BFC1B5", outline = true, note = "body" },
		{ type = "rect", x = 18, y = 6, w = 7, h = 14, r = 3.5, fill = "#3F4038", outline = true, note = "left ring" },
		{ type = "rect", x = 39, y = 6, w = 7, h = 14, r = 3.5, fill = "#3F4038", outline = true, note = "right ring" },
		{ type = "rect", x = 8, y = 13, w = 48, h = 23, r = 9, gradTop = "#FF6B5A", gradBottom = "#C8231C", clip = { 8, 13, 56, 27 }, outline = true, note = "header band" },
		{ type = "rect", x = 15, y = 33, w = 8, h = 7, r = 2, fill = "#8D9C79", outline = true },
		{ type = "rect", x = 28, y = 33, w = 8, h = 7, r = 2, fill = "#8D9C79", outline = true },
		{ type = "rect", x = 41, y = 33, w = 8, h = 7, r = 2, fill = "#8D9C79", outline = true },
		{ type = "rect", x = 15, y = 45, w = 8, h = 7, r = 2, fill = "#8D9C79", outline = true },
		{ type = "rect", x = 28, y = 45, w = 8, h = 7, r = 2, fill = "#FFC531", strokeColor = "#16170F", strokeWidth = 2.5, outline = true, note = "today" },
		{ type = "rect", x = 41, y = 45, w = 8, h = 7, r = 2, fill = "#8D9C79", outline = true },
	},

	goals = {
		{ type = "rect", x = 10, y = 12, w = 44, h = 46, r = 9, gradTop = "#F7F7F1", gradBottom = "#B4B6AC", outline = true, note = "board" },
		{ type = "rect", x = 23, y = 5, w = 18, h = 13, r = 5, gradTop = "#DE93FF", gradBottom = "#8B2FD6", outline = true, note = "clip" },
		-- kit path "M20 37 l7 8 l17 -19", coloured stroke-width 8, round caps
		{ type = "bar", x1 = 20, y1 = 37, x2 = 27, y2 = 45, t = 8, fill = "#4FBE28", outline = true, note = "tick short leg" },
		{ type = "bar", x1 = 27, y1 = 45, x2 = 44, y2 = 26, t = 8, fill = "#4FBE28", outline = true, note = "tick long leg" },
		{ type = "rect", x = 15, y = 17, w = 12, h = 4, r = 2, fill = "#FFFFFF", opacity = 0.55, outline = false, note = "gloss" },
	},

	index = {
		{ type = "rect", x = 9, y = 10, w = 46, h = 44, r = 7, gradTop = "#6FD8FF", gradBottom = "#125FA8", outline = true, note = "cover" },
		{ type = "rect", x = 19, y = 15, w = 31, h = 34, r = 4, fill = "#FFF6D2", strokeColor = "#16170F", strokeWidth = 3.5, outline = true, note = "page" },
		{ type = "rect", x = 9, y = 10, w = 11, h = 44, r = 5, gradTop = "#3AA7E8", gradBottom = "#0D4A85", strokeColor = "#16170F", strokeWidth = 3.5, outline = true, note = "spine" },
		-- kit polygon "40,10 51,10 51,32 45.5,26 40,32" = a rectangle with a V
		-- notched out of its bottom edge. Rect first, then the notch is carved by
		-- two 45-degree squares (dark one slightly larger, giving the V its
		-- keyline) clipped to the ribbon's own column so they cannot spill.
		{ type = "rect", x = 40, y = 10, w = 11, h = 22, r = 0, fill = "#E23A2C", strokeColor = "#16170F", strokeWidth = 3.5, outline = true, note = "ribbon" },
		{ type = "rect", x = 39.5, y = 25.8, w = 12, h = 12, r = 0, rot = 45, fill = "#16170F", clip = { 40, 10, 51, 32 }, outline = false, note = "notch keyline" },
		{ type = "rect", x = 41.25, y = 27.55, w = 8.5, h = 8.5, r = 0, rot = 45, fill = "#FFF6D2", clip = { 40, 10, 51, 32 }, outline = false, note = "notch" },
		{ type = "rect", x = 24, y = 21, w = 20, h = 3.5, r = 1.75, fill = "#C2B98E", outline = true },
		{ type = "rect", x = 24, y = 29, w = 20, h = 3.5, r = 1.75, fill = "#C2B98E", outline = true },
		{ type = "rect", x = 24, y = 37, w = 13, h = 3.5, r = 1.75, fill = "#C2B98E", outline = true },
	},

	coin = {
		{ type = "circle", cx = 32, cy = 32, radius = 25, gradTop = "#FFE87A", gradBottom = "#E8930F", outline = true, note = "rim" },
		{ type = "circle", cx = 32, cy = 32, radius = 18, gradTop = "#FFF3C4", gradBottom = "#F5C13A", strokeColor = "#16170F", strokeWidth = 3.5, outline = true, note = "face" },
		-- kit polygon spans y25..38 about x32 -> centre (32,32.2), outer radius 7.2
		{ type = "star", cx = 32, cy = 32.2, outerRadius = 7.2, fill = "#E8930F", outline = true, note = "star" },
		{ type = "bar", x1 = 17.6, y1 = 24.2, x2 = 29.2, y2 = 14.6, t = 5, fill = "#FFFFFF", outline = false, note = "shine" },
	},

	gem = {
		-- The kit draws a kite -- (32,7) (55,25) (32,58) (9,25) -- taller below
		-- its waist than above it, which no Roblox GUI primitive expresses. A
		-- 45-degree square gives a true diamond of the same 46-unit width; at the
		-- 38px this renders at, the only difference is a slightly shorter bottom
		-- point. gradFixed keeps the shading vertical despite the spin.
		{ type = "rect", x = 15.75, y = 15.75, w = 32.5, h = 32.5, r = 0, rot = 45, gradTop = "#E9B4FF", gradBottom = "#7A1CB8", gradFixed = true, outline = true, note = "body" },
		{ type = "bar", x1 = 11, y1 = 32, x2 = 53, y2 = 32, t = 3, fill = "#4E0F78", outline = false, note = "waist facet" },
		{ type = "bar", x1 = 26, y1 = 13.5, x2 = 22.5, y2 = 21, t = 4, fill = "#FFFFFF", opacity = 0.5, outline = false, note = "gloss" },
	},

	--[[ The three teleport-tab icons (Skip / Shops / Plot). Unlike everything
	else in here these have NO SVG in the kit -- the user supplied a reference
	image only, with no colour values -- so they are drawn to match it as closely
	as the shape vocabulary allows, reusing kit palette colours throughout so
	they sit in the same family as the rail icons. ]]
	skip = {
		{ type = "circle", cx = 32, cy = 30, radius = 24, gradTop = "#FCFCF6", gradBottom = "#C6CFBC", outline = true, note = "outer ring" },
		{ type = "circle", cx = 32, cy = 30, radius = 18, gradTop = "#6FD8FF", gradBottom = "#2A93E0", outline = true, note = "blue ring" },
		{ type = "circle", cx = 32, cy = 30, radius = 11.5, gradTop = "#FCFCF6", gradBottom = "#C6CFBC", outline = true, note = "inner white ring" },
		{ type = "circle", cx = 32, cy = 30, radius = 5.5, gradTop = "#3AA7E8", gradBottom = "#0D4A85", outline = true, note = "bullseye" },
		-- Dart driven into the bullseye from the lower left. Two lessons are baked
		-- into these numbers. Deliberately SLIM: at tab size a thick shaft coming
		-- off a ringed circle at a diagonal reads as a magnifying-glass handle,
		-- which is exactly how the first attempt came out. And the head is the two
		-- BARBS, not a diamond -- a diamond big enough to see swallowed the barbs
		-- and turned the arrow back into a stick with a blob on it. Barb angles are
		-- the shaft's reverse direction rotated +/-35 degrees, so the head reads as
		-- an arrow at any size; round caps butt them cleanly into the shaft tip.
		{ type = "bar", x1 = 13, y1 = 51, x2 = 32, y2 = 30, t = 5, gradTop = "#E23A2C", gradBottom = "#A8140F", outline = true, note = "shaft" },
		{ type = "bar", x1 = 32, y1 = 30, x2 = 22.3, y2 = 32.2, t = 4.5, fill = "#E23A2C", outline = true, note = "barb" },
		{ type = "bar", x1 = 32, y1 = 30, x2 = 30.8, y2 = 39.9, t = 4.5, fill = "#E23A2C", outline = true, note = "barb" },
		{ type = "rect", x = 7, y = 46.5, w = 11, h = 11, r = 1.5, rot = 45, gradTop = "#FF8A7A", gradBottom = "#C8231C", gradFixed = true, outline = true, note = "flight" },
	},

	shops = {
		{ type = "bar", x1 = 8, y1 = 15, x2 = 16, y2 = 15, t = 6, fill = "#5A6350", outline = true, note = "handle" },
		{ type = "bar", x1 = 16, y1 = 15, x2 = 22, y2 = 25, t = 6, fill = "#5A6350", outline = true, note = "handle stem" },
		{ type = "rect", x = 21, y = 23, w = 35, h = 21, r = 5, gradTop = "#FCFCF6", gradBottom = "#9AA28E", outline = true, note = "basket" },
		{ type = "bar", x1 = 24, y1 = 30, x2 = 53, y2 = 30, t = 3, fill = "#8D9C79", outline = false, note = "basket rail" },
		{ type = "bar", x1 = 31, y1 = 26, x2 = 31, y2 = 41, t = 3, fill = "#8D9C79", outline = false, note = "wire" },
		{ type = "bar", x1 = 39, y1 = 26, x2 = 39, y2 = 41, t = 3, fill = "#8D9C79", outline = false, note = "wire" },
		{ type = "bar", x1 = 47, y1 = 26, x2 = 47, y2 = 41, t = 3, fill = "#8D9C79", outline = false, note = "wire" },
		{ type = "bar", x1 = 30, y1 = 44, x2 = 30, y2 = 48, t = 4, fill = "#5A6350", outline = true, note = "axle" },
		{ type = "bar", x1 = 48, y1 = 44, x2 = 48, y2 = 48, t = 4, fill = "#5A6350", outline = true, note = "axle" },
		{ type = "circle", cx = 30, cy = 51, radius = 5.5, gradTop = "#FFE066", gradBottom = "#E8930F", outline = true, note = "wheel" },
		{ type = "circle", cx = 48, cy = 51, radius = 5.5, gradTop = "#FFE066", gradBottom = "#E8930F", outline = true, note = "wheel" },
	},

	plot = {
		-- The roof is a triangle, which no primitive gives us: it is a 45-degree
		-- square clipped to the half above its own horizontal diagonal. Half
		-- diagonal 22 puts the apex at y8 and the eaves corners at x10 and x54.
		{ type = "rect", x = 16.45, y = 14.45, w = 31.1, h = 31.1, r = 0, rot = 45, gradTop = "#FF6B5A", gradBottom = "#C8231C", gradFixed = true, clip = { 10, 8, 54, 30 }, outline = true, note = "roof" },
		{ type = "rect", x = 11, y = 28, w = 42, h = 6, r = 2, gradTop = "#E8543A", gradBottom = "#A02010", outline = true, note = "eaves" },
		{ type = "rect", x = 15, y = 33, w = 34, h = 22, r = 3, gradTop = "#FAFAF4", gradBottom = "#BFC1B5", outline = true, note = "walls" },
		{ type = "rect", x = 19, y = 37, w = 9, h = 8, r = 2, gradTop = "#6FD8FF", gradBottom = "#2A93E0", outline = true, note = "window" },
		{ type = "rect", x = 36, y = 37, w = 9, h = 8, r = 2, gradTop = "#6FD8FF", gradBottom = "#2A93E0", outline = true, note = "window" },
		{ type = "rect", x = 27, y = 43, w = 11, h = 12, r = 2, gradTop = "#3AA7E8", gradBottom = "#0D4A85", outline = true, note = "door" },
		{ type = "circle", cx = 35, cy = 49, radius = 1.6, fill = "#FFD84D", outline = false, note = "door knob" },
	},

	--[[ Darrel -- the egg-shop currency is named after the mascot, so his face IS
	the currency icon. Colours are lifted straight off the ReplicatedStorage
	"DarrelBust" model the retired DarrelHUDClient used to render in a 30px
	ViewportFrame: skin rgb(150,99,64), cap rgb(32,32,35), strap rgb(92,86,76),
	buckle rgb(150,148,145), glass frames rgb(12,12,12), lenses rgb(228,222,206),
	locs/mustache rgb(24,19,17), grin rgb(248,244,235), ear stud rgb(212,175,55).

	Deliberately COARSE. This renders at 38px in the currency pill -- less than
	two thirds the rail's 66px -- so the bust's finer parts (chin beard, mustache
	tips, individual locs, teeth split) are merged or dropped. What has to survive
	at that size is the silhouette: cap, big dark glasses, mustache, locs. ]]
	darrel = {
		-- Locs stop at the jaw rather than running the full height of the head:
		-- carried lower they merge with the cap into one black mass, which is what
		-- the first pass looked like.
		{ type = "bar", x1 = 15, y1 = 29, x2 = 13, y2 = 45, t = 8, fill = "#181311", outline = true, note = "locs left" },
		{ type = "bar", x1 = 49, y1 = 29, x2 = 51, y2 = 45, t = 8, fill = "#181311", outline = true, note = "locs right" },
		{ type = "rect", x = 14.5, y = 31, w = 4.5, h = 7, r = 2, fill = "#96633F", outline = true, note = "ear left" },
		{ type = "rect", x = 45, y = 31, w = 4.5, h = 7, r = 2, fill = "#96633F", outline = true, note = "ear right" },
		-- skin lifted a shade off the model's rgb(150,99,64): at icon size the true
		-- value goes muddy between the black cap and the black mustache
		{ type = "rect", x = 17, y = 15, w = 30, h = 35, r = 10, gradTop = "#B8825C", gradBottom = "#85583A", outline = true, note = "head" },
		{ type = "circle", cx = 16.7, cy = 37.5, radius = 1.8, fill = "#D4AF37", outline = false, note = "ear stud" },
		-- cap: rounded on top, cut flat where it meets the brow
		{ type = "rect", x = 15, y = 10, w = 34, h = 19, r = 9, gradTop = "#3A3A42", gradBottom = "#1E1E22", clip = { 15, 10, 49, 24 }, outline = true, note = "cap dome" },
		{ type = "rect", x = 15, y = 21.5, w = 34, h = 4.5, r = 2, fill = "#5C564C", outline = true, note = "cap strap" },
		{ type = "rect", x = 30, y = 22, w = 4, h = 3.5, r = 1, fill = "#96948F", outline = false, note = "strap buckle" },
		-- the glasses are the single most recognisable feature, so they get the
		-- most area: widened until the pair nearly spans the face
		{ type = "rect", x = 18, y = 29, w = 12.5, h = 11, r = 3.5, fill = "#E4DECE", strokeColor = "#0C0C0C", strokeWidth = 3.5, outline = true, note = "lens left" },
		{ type = "rect", x = 33.5, y = 29, w = 12.5, h = 11, r = 3.5, fill = "#E4DECE", strokeColor = "#0C0C0C", strokeWidth = 3.5, outline = true, note = "lens right" },
		{ type = "bar", x1 = 30.5, y1 = 34.5, x2 = 33.5, y2 = 34.5, t = 3, fill = "#0C0C0C", outline = false, note = "bridge" },
		{ type = "bar", x1 = 26.5, y1 = 43.5, x2 = 37.5, y2 = 43.5, t = 5, fill = "#181311", outline = true, note = "mustache" },
		{ type = "rect", x = 29, y = 46.5, w = 6, h = 2.6, r = 1.3, fill = "#F8F4EB", outline = false, note = "grin" },
	},

	settings = {
		-- 8 teeth: the kit repeats one rect at rotate(N 32 32) for N in 0..315 step 45
		{ type = "rect", x = 26.5, y = 3, w = 11, h = 20, r = 4, rot = 0, pivotX = 32, pivotY = 32, gradTop = "#FCFCF6", gradBottom = "#9AA28E", outline = true },
		{ type = "rect", x = 26.5, y = 3, w = 11, h = 20, r = 4, rot = 45, pivotX = 32, pivotY = 32, gradTop = "#FCFCF6", gradBottom = "#9AA28E", outline = true },
		{ type = "rect", x = 26.5, y = 3, w = 11, h = 20, r = 4, rot = 90, pivotX = 32, pivotY = 32, gradTop = "#FCFCF6", gradBottom = "#9AA28E", outline = true },
		{ type = "rect", x = 26.5, y = 3, w = 11, h = 20, r = 4, rot = 135, pivotX = 32, pivotY = 32, gradTop = "#FCFCF6", gradBottom = "#9AA28E", outline = true },
		{ type = "rect", x = 26.5, y = 3, w = 11, h = 20, r = 4, rot = 180, pivotX = 32, pivotY = 32, gradTop = "#FCFCF6", gradBottom = "#9AA28E", outline = true },
		{ type = "rect", x = 26.5, y = 3, w = 11, h = 20, r = 4, rot = 225, pivotX = 32, pivotY = 32, gradTop = "#FCFCF6", gradBottom = "#9AA28E", outline = true },
		{ type = "rect", x = 26.5, y = 3, w = 11, h = 20, r = 4, rot = 270, pivotX = 32, pivotY = 32, gradTop = "#FCFCF6", gradBottom = "#9AA28E", outline = true },
		{ type = "rect", x = 26.5, y = 3, w = 11, h = 20, r = 4, rot = 315, pivotX = 32, pivotY = 32, gradTop = "#FCFCF6", gradBottom = "#9AA28E", outline = true },
		{ type = "circle", cx = 32, cy = 32, radius = 19, gradTop = "#FCFCF6", gradBottom = "#9AA28E", outline = true, note = "body" },
		{ type = "circle", cx = 32, cy = 32, radius = 7.5, fill = "#5A6350", strokeColor = "#16170F", strokeWidth = 4, outline = true, note = "hub" },
		-- kit arc "M20 24 A16 16 0 0 1 32 18"; at icon size its sagitta is under a
		-- pixel, so its chord stands in for it
		{ type = "bar", x1 = 20.4, y1 = 23.4, x2 = 31.4, y2 = 18.2, t = 4.5, fill = "#FFFFFF", outline = false, note = "shine" },
	},
}

---------------------------------------------------------------- helpers
local function rotAbout(pivotX: number, pivotY: number, x: number, y: number, deg: number): (number, number)
	if deg == 0 then return x, y end
	local rad = math.rad(deg)
	local c, s = math.cos(rad), math.sin(rad)
	local dx, dy = x - pivotX, y - pivotY
	-- y grows downward here, so this is a clockwise rotation for positive deg --
	-- matching both SVG's rotate() and Roblox's GuiObject.Rotation.
	return pivotX + dx * c - dy * s, pivotY + dx * s + dy * c
end

local function corner(inst: GuiObject, radiusPx: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, math.max(radiusPx, 0))
	c.Parent = inst
end

local function paint(f: GuiObject, sh, dark: boolean, scale: number)
	if dark then
		f.BackgroundColor3 = KEYLINE
		f.BackgroundTransparency = 0
		return
	end
	if sh.gradTop and sh.gradBottom then
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(Color3.fromHex(sh.gradTop), Color3.fromHex(sh.gradBottom))
		-- 90 = top -> bottom. A UIGradient rotates with its frame, which is what
		-- the kit wants for a rotated shape -- unless the rotation is ours, in
		-- which case cancel it back out.
		g.Rotation = if sh.gradFixed then 90 - (sh.rot or 0) else 90
		g.Parent = f
	else
		f.BackgroundColor3 = Color3.fromHex(sh.fill or "#FFFFFF")
	end
	if sh.opacity then
		f.BackgroundTransparency = 1 - sh.opacity
	end
	if sh.strokeColor and sh.strokeWidth then
		local st = Instance.new("UIStroke")
		st.Color = Color3.fromHex(sh.strokeColor)
		-- SVG centres a stroke on the edge; UIStroke draws it entirely outside,
		-- so half the nominal width reproduces the outer half we can see.
		st.Thickness = math.max(sh.strokeWidth * 0.5 * scale, 1)
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.LineJoinMode = Enum.LineJoinMode.Round
		st.Parent = f
	end
end

---------------------------------------------------------------- renderer
-- Draws one shape. `e` is the outward expansion in SVG units: EXPAND for the
-- keyline pass, 0 for the colour pass.
local function drawShape(root: GuiObject, scale: number, sh, e: number, dark: boolean, z: number)
	local function px(v: number): number return (v - VB_MIN) * scale end
	local function len(v: number): number return v * scale end

	-- A clipped shape lives inside its own ClipsDescendants frame, so positions
	-- inside it are relative to that frame's top-left.
	local host, ox, oy = root, 0, 0
	local function openClip(x1: number, y1: number, x2: number, y2: number)
		local c = Instance.new("Frame")
		c.Name = "Clip"
		c.BackgroundTransparency = 1
		c.BorderSizePixel = 0
		c.ClipsDescendants = true
		c.Position = UDim2.fromOffset(px(x1), px(y1))
		c.Size = UDim2.fromOffset(len(x2 - x1), len(y2 - y1))
		c.ZIndex = z
		c.Parent = root
		host, ox, oy = c, px(x1), px(y1)
	end

	if sh.clip then
		-- widen the window with the shape, so the keyline pass is not shaved
		openClip(sh.clip[1] - e, sh.clip[2] - e, sh.clip[3] + e, sh.clip[4] + e)
	end

	local function place(cx: number, cy: number, w: number, h: number, rot: number): Frame
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5) -- Rotation pivots on the anchor, so centre it
		f.Position = UDim2.fromOffset(px(cx) - ox, px(cy) - oy)
		f.Size = UDim2.fromOffset(len(w), len(h))
		f.Rotation = rot
		f.ZIndex = z
		f.Parent = host
		return f
	end

	local kind = sh.type

	if kind == "rect" then
		local x, y = sh.x - e, sh.y - e
		local w, h = sh.w + 2 * e, sh.h + 2 * e
		local cx, cy = x + w * 0.5, y + h * 0.5
		local rot = sh.rot or 0
		if sh.pivotX then
			cx, cy = rotAbout(sh.pivotX, sh.pivotY, cx, cy, rot)
		end
		local f = place(cx, cy, w, h, rot)
		local r = sh.r or 0
		if r > 0 then corner(f, len(r + e)) end
		paint(f, sh, dark, scale)

	elseif kind == "circle" then
		local radius = sh.radius + e
		local f = place(sh.cx, sh.cy, radius * 2, radius * 2, 0)
		corner(f, len(radius))
		paint(f, sh, dark, scale)

	elseif kind == "bar" then
		local t = sh.t + 2 * e
		local dx, dy = sh.x2 - sh.x1, sh.y2 - sh.y1
		local length = math.sqrt(dx * dx + dy * dy)
		-- round caps overhang each end by t/2, so the capsule is length + t long
		local f = place((sh.x1 + sh.x2) * 0.5, (sh.y1 + sh.y2) * 0.5, length + t, t, math.deg(math.atan2(dy, dx)))
		corner(f, len(t * 0.5))
		paint(f, sh, dark, scale)

	elseif kind == "arch" then
		-- An upside-down U: a capsule outline whose bottom half is clipped away.
		-- The ring is inset by t/2 so its OUTSIDE-drawn UIStroke lands centred on
		-- the path, the way an SVG stroke would.
		local t = sh.t + 2 * e
		local ringX, ringW = sh.x1 + t * 0.5, (sh.x2 - sh.x1) - t
		local ringTop = sh.yTop + t * 0.5
		local ringH = 2 * (sh.yBottom - ringTop)
		if ringW > 0 and ringH > 0 then
			local saveHost, saveOx, saveOy = host, ox, oy
			openClip(sh.x1 - t * 0.5, sh.yTop - t * 0.5, sh.x2 + t * 0.5, sh.yBottom)
			local ring = Instance.new("Frame")
			ring.BorderSizePixel = 0
			ring.BackgroundTransparency = 1
			ring.Position = UDim2.fromOffset(px(ringX) - ox, px(ringTop) - oy)
			ring.Size = UDim2.fromOffset(len(ringW), len(ringH))
			ring.ZIndex = z
			ring.Parent = host
			corner(ring, len(math.min(ringW, ringH) * 0.5))
			local st = Instance.new("UIStroke")
			st.Color = dark and KEYLINE or Color3.fromHex(sh.fill or "#FFFFFF")
			st.Thickness = math.max(len(t), 1)
			st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			st.LineJoinMode = Enum.LineJoinMode.Round
			st.Parent = ring
			host, ox, oy = saveHost, saveOx, saveOy
		end

	elseif kind == "star" then
		-- No polygon primitive in Roblox GUI, so the star is a glyph. The keyline
		-- pass draws a larger black star behind the gold one, which reads as the
		-- same outline the other shapes get.
		local radius = sh.outerRadius + e
		local cx, cy = sh.cx, sh.cy
		local rot = sh.rot or 0
		if sh.pivotX then
			cx, cy = rotAbout(sh.pivotX, sh.pivotY, cx, cy, rot)
		end
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = UDim2.fromOffset(px(cx) - ox, px(cy) - oy)
		l.Size = UDim2.fromOffset(len(radius * 2), len(radius * 2))
		l.Rotation = rot
		l.Text = "\u{2605}" -- BLACK STAR: a plain dingbat, not an emoji
		l.TextScaled = true
		l.RichText = false
		l.TextColor3 = if dark then KEYLINE else Color3.fromHex(sh.gradTop or sh.fill or "#FFFFFF")
		l.ZIndex = z
		l.Parent = host
		if not dark and sh.gradTop and sh.gradBottom then
			local g = Instance.new("UIGradient")
			g.Color = ColorSequence.new(Color3.fromHex(sh.gradTop), Color3.fromHex(sh.gradBottom))
			g.Rotation = 90
			g.Parent = l
		end
	end
end

--[[ Draws `name` into `parent` at `size` px square, based at ZIndex `zBase`.
Returns the container Frame, or nil for an unknown name. The container is
inert -- transparent, no input -- so callers keep owning hit-testing. ]]
function IconArt.draw(parent: GuiObject, name: string, size: number, zBase: number): Frame?
	local shapes = IconArt.SHAPES[name]
	if not shapes then return nil end

	local scale = size / VB_SPAN
	local root = Instance.new("Frame")
	root.Name = "IconArt_" .. name
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromOffset(size, size)
	root.ZIndex = zBase
	root.Parent = parent

	-- pass 1: the dark keyline, every outlined shape fattened by EXPAND
	for _, sh in ipairs(shapes) do
		if sh.outline then
			drawShape(root, scale, sh, EXPAND, true, zBase + 1)
		end
	end
	-- pass 2: colour, in the kit's paint order (later shapes above earlier ones)
	for i, sh in ipairs(shapes) do
		drawShape(root, scale, sh, 0, false, zBase + 1 + i)
	end

	return root
end

function IconArt.has(name: string): boolean
	return IconArt.SHAPES[name] ~= nil
end

return IconArt
