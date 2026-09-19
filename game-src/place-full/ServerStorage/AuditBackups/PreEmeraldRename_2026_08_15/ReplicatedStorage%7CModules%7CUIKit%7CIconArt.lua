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
  ring   cx, cy, radius, t      -- circular band; add `clip` to cut it to an arc
  tri    cx, cy, h, dir         -- right-isoceles triangle (arrowhead), apex `h`
                                   from the base in direction `dir`, base 2h wide
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

	--[[ Gem -- the premium currency icon. 2026-08-13: the currency was renamed
	from "darrels" to GEMS, and the owner picked an EMERALD over a diamond, so
	the mascot-face drawing that lived here (Darrel, transcribed off the
	DarrelBust model) is replaced by a step-cut emerald. The KEY stays
	"darrel": every call site -- GameHUDClient's pill, EggShopClient's wallet
	and price rows, ShopPanel's pack cards, GoalsPanel/PassPanel/DailyPanel
	reward chips -- asks IconArt for "darrel", and renaming the key would
	touch seven scripts for zero visual gain.

	Emerald-cut read: a fat rounded octagon (rect with a heavy corner radius)
	with a lighter inner step -- the two-mass rectangle-in-rectangle is what
	says "emerald" rather than "diamond" at the pill's 38px. ]]
	darrel = {
		-- PORTRAIT, bevel-cornered, stepped: the tall rectangle-in-rectangle is
		-- the emerald-cut read. Corner bevels are 45-degree squares shaved off by
		-- the diagonal edge pieces below rather than a big corner radius -- heavy
		-- rounding made the first pass read as a green gummy, not a cut stone.
		{ type = "rect", x = 17, y = 12, w = 30, h = 40, r = 4, gradTop = "#4FE487", gradBottom = "#0C9447", outline = true, note = "emerald body" },
		{ type = "rect", x = 20.5, y = 15.5, w = 23, h = 33, r = 2.5, gradTop = "#2FCB6E", gradBottom = "#12A855", outline = false, note = "crown facet ring" },
		{ type = "rect", x = 24, y = 19, w = 16, h = 26, r = 2, gradTop = "#A9F5C4", gradBottom = "#41D883", outline = false, note = "table (inner step)" },
		{ type = "bar", x1 = 21, y1 = 17.5, x2 = 28, y2 = 16.5, t = 3, fill = "#FFFFFF", opacity = 0.55, outline = false, note = "gloss" },
		{ type = "circle", cx = 45, cy = 10.5, radius = 2.6, fill = "#FFFFFF", outline = false, note = "sparkle" },
	},

	--[[ Gem CLUSTER -- the currency counter's hero art, from the owner's
	reference (2026-08-14). A SEPARATE key from `darrel` on purpose: `darrel`
	is what the 34px reward chips, shop rows and price rows still ask for, and
	this much layering turns to mush at that size (the same reason the backpack
	category marks below are single silhouettes). Only the HUD counter draws
	this one, at 76px, where the satellites and sparkles still read.

	Two deliberate departures from the reference art, both learned by rendering
	it rather than by argument:

	NO LEAVES. The reference paints foliage behind the stones. Every attempt
	here read as a green caterpillar laid across the gems -- a capsule is the
	only primitive available and it cannot make a leaf's point -- so they are
	dropped rather than shipped badly.

	SPARKLES ARE STARS, not two crossed capsules. Crossed capsules are exactly
	a PLUS SIGN, and the buy button a few pixels to the right of this art is a
	plus; the first pass had the counter wearing three of them. ]]
	gemCluster = {
		{ type = "rect", x = 4, y = 10, w = 9, h = 9, r = 1.8, rot = 45, gradTop = "#9CF3B4", gradBottom = "#35BE70", gradFixed = true, outline = true, note = "chip upper left" },
		{ type = "rect", x = 3, y = 43, w = 10, h = 10, r = 1.8, rot = 45, gradTop = "#8CEAA6", gradBottom = "#2CAE64", gradFixed = true, outline = true, note = "chip lower left" },
		-- Satellites: a crown over a SHALLOW pavilion, and kept clearly smaller
		-- than the hero. Sized to match it, the cluster read as four competing
		-- blobs instead of one stone with company.
		{ type = "rect", x = 44, y = 14, w = 13, h = 7, r = 1.5, gradTop = "#7FE79C", gradBottom = "#2BB265", outline = true, note = "gem TR crown" },
		{ type = "tri", h = 6.5, cx = 50.5, cy = 21, dir = "down", gradTop = "#54CF83", gradBottom = "#14904F", outline = true, note = "gem TR pavilion" },
		{ type = "rect", x = 42, y = 40, w = 12, h = 6.5, r = 1.5, gradTop = "#7FE79C", gradBottom = "#2BB265", outline = true, note = "gem BR crown" },
		{ type = "tri", h = 6, cx = 48, cy = 46.5, dir = "down", gradTop = "#54CF83", gradBottom = "#14904F", outline = true, note = "gem BR pavilion" },
		-- Hero crystal, drawn AFTER the satellites so it owns the middle
		{ type = "tri", h = 12, cx = 25, cy = 23, dir = "up", gradTop = "#A8F5A0", gradBottom = "#4FD07A", outline = true, note = "crystal apex" },
		{ type = "rect", x = 13, y = 22, w = 24, h = 26, r = 1.5, gradTop = "#6DEB8E", gradBottom = "#23A85E", outline = true, note = "crystal body" },
		{ type = "tri", h = 12, cx = 25, cy = 47, dir = "down", gradTop = "#3FC978", gradBottom = "#158F4C", outline = true, note = "crystal base" },
		-- Facets, no keyline. The bright band starts INSIDE the apex triangle and
		-- runs the body's full height, which is what makes the point read as lit
		-- rather than as a separate triangle stuck on top.
		{ type = "rect", x = 13.5, y = 22.5, w = 6.5, h = 25, r = 1, gradTop = "#46CE80", gradBottom = "#17904E", outline = false, note = "facet left" },
		{ type = "rect", x = 30, y = 22.5, w = 6.5, h = 25, r = 1, gradTop = "#3AC275", gradBottom = "#0F7A44", outline = false, note = "facet right" },
		{ type = "rect", x = 21.5, y = 14.5, w = 7, h = 33, r = 1, gradTop = "#EAFFA8", gradBottom = "#74E464", outline = false, note = "facet centre (lit edge)" },
		{ type = "bar", x1 = 18.5, y1 = 26, x2 = 18.5, y2 = 35, t = 2.6, fill = "#FFFFFF", opacity = 0.5, outline = false, note = "gloss" },
		{ type = "star", cx = 41.5, cy = 5, outerRadius = 4.5, fill = "#FFFFFF", outline = false, note = "sparkle upper" },
		{ type = "star", cx = 17.5, cy = 54.5, outerRadius = 3.4, fill = "#FFFFFF", outline = false, note = "sparkle lower" },
	},

	--[[ Plus -- the gem counter's buy button glyph. Both bars carry `outline`,
	so the shared keyline pass fuses them into ONE chunky outlined plus; giving
	either one its own UIStroke instead would draw a seam across the join. ]]
	plus = {
		{ type = "rect", x = 25, y = 11, w = 14, h = 42, r = 4, gradTop = "#FFFFFF", gradBottom = "#E4EFE6", outline = true, note = "plus vertical" },
		{ type = "rect", x = 11, y = 25, w = 42, h = 14, r = 4, gradTop = "#FFFFFF", gradBottom = "#E4EFE6", outline = true, note = "plus horizontal" },
	},

	--[[ Egg -- the Eggs Shop header mark, transcribed from the egg-shop handoff's
	icons/eggs.svg (speckled forest egg). The kit's true egg outline is a bezier
	(narrow crown into a 21-radius base); the closest primitive union is a tall
	capsule, which at the 62px header size keeps the read -- pale shell, three
	green spots, gloss -- without the bezier. Spot geometry is the SVG's own. ]]
	egg = {
		{ type = "rect", x = 11.5, y = 4, w = 41, h = 52, r = 20.5, gradTop = "#F7FBE6", gradBottom = "#BFCF8E", outline = true, note = "shell" },
		{ type = "circle", cx = 40, cy = 22, radius = 5, gradTop = "#A6EE72", gradBottom = "#3E9E22", strokeColor = "#16170F", strokeWidth = 2.5, outline = false, note = "spot" },
		{ type = "circle", cx = 24, cy = 34, radius = 4, gradTop = "#A6EE72", gradBottom = "#3E9E22", strokeColor = "#16170F", strokeWidth = 2.5, outline = false, note = "spot" },
		{ type = "circle", cx = 39, cy = 41, radius = 6, gradTop = "#A6EE72", gradBottom = "#3E9E22", strokeColor = "#16170F", strokeWidth = 2.5, outline = false, note = "spot" },
		{ type = "bar", x1 = 23, y1 = 13, x2 = 31.5, y2 = 6.5, t = 4, fill = "#FFFFFF", opacity = 0.5, outline = false, note = "gloss" },
	},

	--[[ Backpack CATEGORY marks -- pet / charm / tag. Like the keys below, no kit
	SVG exists for any of these; they are drawn to a game need in the same
	vocabulary. The Backpack's tab column shows them at 34px, which is small, so
	each one is a single flat silhouette with no interior detail below ~4 units --
	at that size the darrel icon's kind of layering turns to mush. Distinct
	SILHOUETTES again rather than three recolours: round-lobed paw, four-lobed
	clover, hard-cornered plate. ]]
	pet = {
		-- Toes before the pad: the pad is the larger mass and reads better
		-- overlapping them than being overlapped.
		{ type = "circle", cx = 13, cy = 28, radius = 6.5, gradTop = "#FFD1A0", gradBottom = "#E89A4C", outline = true, note = "toe outer left" },
		{ type = "circle", cx = 25.5, cy = 17.5, radius = 7, gradTop = "#FFD1A0", gradBottom = "#E89A4C", outline = true, note = "toe inner left" },
		{ type = "circle", cx = 38.5, cy = 17.5, radius = 7, gradTop = "#FFD1A0", gradBottom = "#E89A4C", outline = true, note = "toe inner right" },
		{ type = "circle", cx = 51, cy = 28, radius = 6.5, gradTop = "#FFD1A0", gradBottom = "#E89A4C", outline = true, note = "toe outer right" },
		{ type = "rect", x = 18, y = 31, w = 28, h = 24, r = 12, gradTop = "#FFC078", gradBottom = "#D97F2E", outline = true, note = "pad" },
		{ type = "bar", x1 = 24, y1 = 38, x2 = 30, y2 = 36, t = 3.5, fill = "#FFFFFF", opacity = 0.45, outline = false, note = "gloss" },
	},

	charm = {
		-- Stem first so the leaves cover where it meets them.
		{ type = "bar", x1 = 32, y1 = 38, x2 = 36, y2 = 59, t = 5, fill = "#2E7D32", outline = true, note = "stem" },
		{ type = "circle", cx = 22, cy = 19, radius = 11.5, gradTop = "#9CF08A", gradBottom = "#37A03F", outline = true, note = "leaf NW" },
		{ type = "circle", cx = 42, cy = 19, radius = 11.5, gradTop = "#9CF08A", gradBottom = "#37A03F", outline = true, note = "leaf NE" },
		{ type = "circle", cx = 22, cy = 38, radius = 11.5, gradTop = "#8BE479", gradBottom = "#2E8F36", outline = true, note = "leaf SW" },
		{ type = "circle", cx = 42, cy = 38, radius = 11.5, gradTop = "#8BE479", gradBottom = "#2E8F36", outline = true, note = "leaf SE" },
		{ type = "bar", x1 = 16, y1 = 14, x2 = 22, y2 = 11, t = 3.5, fill = "#FFFFFF", opacity = 0.5, outline = false, note = "gloss" },
	},

	tag = {
		-- A name PLATE rather than the usual angled price tag: these are the
		-- name-plate titles that hang over a player's head, and a plate squares up
		-- to the tile instead of leaving two empty corners on the diagonal.
		{ type = "rect", x = 8, y = 20, w = 48, h = 28, r = 8, gradTop = "#9FE2FF", gradBottom = "#3D9BD4", outline = true, note = "plate" },
		{ type = "circle", cx = 17.5, cy = 34, radius = 4, fill = "#3F4038", outline = false, note = "punch hole" },
		{ type = "bar", x1 = 27, y1 = 29.5, x2 = 48, y2 = 29.5, t = 4.5, fill = "#1C4C6B", outline = false, note = "name line" },
		{ type = "bar", x1 = 27, y1 = 39, x2 = 41, y2 = 39, t = 4.5, fill = "#1C4C6B", outline = false, note = "name line short" },
		{ type = "bar", x1 = 14, y1 = 25, x2 = 22, y2 = 25, t = 3, fill = "#FFFFFF", opacity = 0.45, outline = false, note = "gloss" },
	},

	--[[ The two quest KEYS, for the Backpack's Keys tab. No kit SVG exists for
	either -- they are the first icons here drawn to a game need rather than
	transcribed from the handoff -- so they are built from the same vocabulary and
	palette as everything above, and are deliberately different SILHOUETTES rather
	than two recolours: at tile size a player has to tell them apart at a glance,
	and colour alone does not survive the greyed state the tab uses.

	Both read left-to-right (bow left, teeth right) rather than on the diagonal a
	key is usually drawn at: the tile is square, and a diagonal key leaves two
	empty corners while shortening the shaft that carries the read. ]]
	keyGianluca = {
		-- Gianluca's: a plain round-bow key in the same gold as the coin icon
		{ type = "circle", cx = 21, cy = 32, radius = 14, gradTop = "#FFE87A", gradBottom = "#E8930F", outline = true, note = "bow" },
		{ type = "circle", cx = 21, cy = 32, radius = 6, fill = "#3F4038", outline = false, note = "bow hole" },
		{ type = "bar", x1 = 33, y1 = 32, x2 = 59, y2 = 32, t = 9, fill = "#FFC531", outline = true, note = "shaft" },
		{ type = "bar", x1 = 49, y1 = 33, x2 = 49, y2 = 43, t = 7, fill = "#FFC531", outline = true, note = "tooth" },
		{ type = "bar", x1 = 58, y1 = 33, x2 = 58, y2 = 45, t = 7, fill = "#FFC531", outline = true, note = "tooth" },
		{ type = "bar", x1 = 15, y1 = 25, x2 = 21, y2 = 21.5, t = 4, fill = "#FFFFFF", opacity = 0.5, outline = false, note = "gloss" },
	},

	keyCellar = {
		-- Elder Tung's: an old skeleton key -- DIAMOND bow, collar on the shaft --
		-- in the wood-brown his dialogue card already uses. gradFixed because the
		-- 45-degree spin is our way of drawing a diamond, not the artwork tilting.
		{ type = "rect", x = 11, y = 22, w = 20, h = 20, r = 4, rot = 45, gradTop = "#D8B48A", gradBottom = "#7A4A20", gradFixed = true, outline = true, note = "bow" },
		{ type = "circle", cx = 21, cy = 32, radius = 5, fill = "#3F4038", outline = false, note = "bow hole" },
		{ type = "bar", x1 = 30, y1 = 32, x2 = 59, y2 = 32, t = 8, fill = "#A9743C", outline = true, note = "shaft" },
		{ type = "rect", x = 39, y = 24, w = 5.5, h = 16, r = 2, fill = "#6E4522", strokeColor = "#16170F", strokeWidth = 2.5, outline = true, note = "collar" },
		{ type = "bar", x1 = 53, y1 = 33, x2 = 53, y2 = 44, t = 6.5, fill = "#A9743C", outline = true, note = "tooth" },
		{ type = "bar", x1 = 59, y1 = 33, x2 = 59, y2 = 40, t = 6.5, fill = "#A9743C", outline = true, note = "tooth" },
		{ type = "bar", x1 = 16, y1 = 28, x2 = 20, y2 = 24, t = 3.5, fill = "#FFFFFF", opacity = 0.45, outline = false, note = "gloss" },
	},

	--[[ Rebirth -- no kit SVG exists (the 7th rail button is ours, not the
	handoff's), so it is drawn to a game need in the kit's own vocabulary.

	2026-08-06, to a user reference: the two-arrow cycle ring everyone already
	reads as "rebirth" -- a magenta arc over the top, an ice-white one under it,
	each ending in a chunky arrowhead so the eye follows it clockwise. This
	replaced a purple arc curling over a gold star, which was fine but did not
	say "reset" at a glance and shared the pass icon's star.

	The old note here said a broken recycle ring was not drawable. It is now:
	`ring` (a stroked circle, clipped to an arc) and `tri` (an arrowhead) were
	added to the renderer for exactly this, and both are general -- the next
	icon that needs an arc or a pointer does not have to fake one out of bars. ]]
	rebirth = {
		-- ONE ARC, NOT TWO (2026-08-07, user: "the rebirth icon looks kinda funky").
		--
		-- The previous pair of EQUAL arcs split the circle across the horizontal
		-- midline -- magenta on top, ice underneath -- and at rail size that
		-- silhouette reads as a POKEBALL, not as anything rotational. The two
		-- arrowheads meant to sell the rotation were 9 units on a 64 grid and were
		-- the first thing to disappear in the downscale, leaving just the two-tone
		-- ball. Splitting a circle in half is the problem, however the halves are
		-- coloured; the fix is to stop splitting it.
		--
		-- Now: ONE continuous magenta band of 270 degrees with a single big ice
		-- arrowhead. A whole quadrant of missing ring is a shape no ball has, so it
		-- reads as a cycle at any size, and one head at twice the visual weight
		-- survives where two small ones did not.
		--
		-- Two `ring` pieces rather than one because `clip` is an AXIS-ALIGNED RECT
		-- and cannot cut an L-shape on its own. Both carry the same fill, so they
		-- meet at 6 o'clock and read as one unbroken arc:
		--   left half        12 o'clock -> 9 -> 6
		--   bottom-right      6 o'clock -> 3
		-- leaving the gap in the top-right quadrant, 3 o'clock round to 12.
		{ type = "ring", cx = 32, cy = 32, radius = 20, t = 9, fill = "#FF4FA6",
		  clip = { 2, 2, 32, 62 }, outline = true, note = "arc: left half" },
		{ type = "ring", cx = 32, cy = 32, radius = 20, t = 9, fill = "#FF4FA6",
		  clip = { 32, 32, 62, 62 }, outline = true, note = "arc: bottom-right quadrant" },
		-- Sits ON the 12 o'clock cut end and points INTO the gap, so the eye runs
		-- round the band and off the end clockwise. Ice-white keeps the magenta+ice
		-- identity the plate colour was picked against, and puts the one high
		-- contrast detail exactly where the motion reads.
		{ type = "tri", cx = 32, cy = 12, h = 9, dir = "right", fill = "#EAF6FF",
		  outline = true, note = "arrowhead" },
		{ type = "bar", x1 = 15, y1 = 23, x2 = 21, y2 = 17, t = 3, fill = "#FFFFFF",
		  opacity = 0.5, outline = false, note = "gloss" },
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

	elseif kind == "ring" then
		-- A circular band, same trick as `arch`: a transparent rounded frame
		-- carrying a UIStroke. UIStroke draws entirely OUTSIDE the frame, so the
		-- frame is inset by half the band to land the band centred on `radius`.
		-- A `clip` on the shape cuts the ring down to an arc.
		local t = sh.t + 2 * e
		local r = sh.radius - t * 0.5
		if r > 0 then
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundTransparency = 1
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.fromOffset(px(sh.cx) - ox, px(sh.cy) - oy)
			f.Size = UDim2.fromOffset(len(r * 2), len(r * 2))
			f.ZIndex = z
			f.Parent = host
			corner(f, len(r))
			local st = Instance.new("UIStroke")
			st.Color = dark and KEYLINE or Color3.fromHex(sh.fill or "#FFFFFF")
			st.Thickness = math.max(len(t), 1)
			st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			st.LineJoinMode = Enum.LineJoinMode.Round
			st.Parent = f
		end

	elseif kind == "tri" then
		-- No polygon primitive in Roblox GUI. A square turned 45 degrees has its
		-- corners at up/down/left/right; clip away the half behind the apex and
		-- what is left is a right-isoceles triangle -- the kit's arrowhead.
		-- Expanding for the keyline pass: the flat base grows with the clip
		-- window, and offsetting the two 45-degree edges outward by e pushes the
		-- apex out by e*sqrt(2).
		local SQRT2 = 1.4142135623730951
		local h = sh.h + e * SQRT2
		local cx, cy = sh.cx, sh.cy
		local x1, y1, x2, y2
		local dir = sh.dir or "up"
		if dir == "down" then
			x1, y1, x2, y2 = cx - h, cy - e, cx + h, cy + h
		elseif dir == "up" then
			x1, y1, x2, y2 = cx - h, cy - h, cx + h, cy + e
		elseif dir == "right" then
			x1, y1, x2, y2 = cx - e, cy - h, cx + h, cy + h
		else -- "left"
			x1, y1, x2, y2 = cx - h, cy - h, cx + e, cy + h
		end
		local saveHost, saveOx, saveOy = host, ox, oy
		openClip(x1, y1, x2, y2)
		local f = place(cx, cy, h * SQRT2, h * SQRT2, 45)
		paint(f, sh, dark, scale)
		host, ox, oy = saveHost, saveOx, saveOy

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
