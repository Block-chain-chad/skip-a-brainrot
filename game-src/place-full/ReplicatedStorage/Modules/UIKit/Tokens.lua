--!strict
-- tokens.lua — design tokens for the chunky cartoon HUD.
-- Design canvas: 1350 x 775. All numbers are offset px at that canvas size.

local T = {}

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

-- Two- or three-stop vertical gradient (top -> bottom). Use with UIGradient (Rotation = 90).
local function seq(stops: { { pos: number, hex: string } }): ColorSequence
	local kp = {}
	for i, s in ipairs(stops) do
		table.insert(kp, ColorSequenceKeypoint.new(s.pos, hex(s.hex)))
	end
	return ColorSequence.new(kp)
end

T.hex = hex

-- ============================================================================
-- 2026-08-04 STYLE REPLACEMENT -- "Roblox Simulator UI Style Guide" (user
-- .docx): Pet-Simulator-inspired. This REPLACES the olive/cream families that
-- came before it; the tokens keep their names so every panel inherits the new
-- look without a rewrite, and the old hexes are recorded inline so any single
-- surface can be walked back.
--   window  #D6D6D6 -> #A9A9A9   (was cream #FFF9EC -> #FFEDCD)
--   header  #F96B57 -> #C84535   (was per-panel accents)
--   slots   #4A4A4A -> #363636   (was white cards / olive rows)
--   outline #202020 4px + a 1-2px white inner keyline
-- ============================================================================
------------------------------------------------------------------- colours
T.color = {
	outline        = hex("#202020"), -- guide "outer stroke 4px dark gray" (was #16170F)
	innerKeyline   = hex("#FFFFFF"), -- guide "inner stroke 1-2px white"

	-- the window itself + its darker furniture (guide: light gray window,
	-- dark gray slots -- the inversion of the cream sweep it replaces)
	panelTop       = hex("#D6D6D6"),
	panelBottom    = hex("#A9A9A9"),
	subPanelTop    = hex("#C4C4C4"),
	subPanelBottom = hex("#9C9C9C"),
	rowTop         = hex("#4A4A4A"),
	rowBottom      = hex("#363636"),
	tabTop         = hex("#BEBEBE"),
	tabBottom      = hex("#9C9C9C"),
	trackTop       = hex("#2E2E2E"),
	trackBottom    = hex("#3A3A3A"),
	slotTop        = hex("#4A4A4A"),
	slotBottom     = hex("#363636"),
	headerTop      = hex("#F96B57"),
	headerBottom   = hex("#C84535"),

	white          = hex("#FFFFFF"),
	textMuted      = hex("#D8D8D8"), -- was olive #C9D6B4; muted white reads on both the gray window and the dark slots
	textAccent     = hex("#FFD84D"),
	textOnLight    = hex("#2A2A2A"), -- was #1E2317; ink for text sitting on the light gray window
	textOnWindow   = hex("#2A2A2A"), -- explicit alias for the above, for new code
	textOnGoldCard = hex("#3A2A05"),
	textOnGoldChrome = hex("#5A4A12"),
	textDisabled   = hex("#B8C4A4"),
	textClaimed    = hex("#9FAE8B"),

	claimRing      = hex("#7CE04A"),
	activeRing     = hex("#FFD84D"),
	activeGlow     = hex("#FFE87A"), -- v2 NEW: nav rail active-state radial glow (README 3.7 "rgba(255,232,122,.75)") -- distinct from activeRing (#FFD84D), which other panels' tab/segment rings still use
	scrollThumb    = hex("#9FAE8B"),

	rarityCommon   = hex("#C9CCC2"),
	rarityRare     = hex("#3FA9F5"),
	rarityEpic     = hex("#A855F7"),
	rarityLegend   = hex("#FFB200"),
}

-- Modal scrim: BackgroundColor3 = scrim, BackgroundTransparency = scrimAlpha
T.scrim = hex("#0A0E06")
T.scrimAlpha = 0.50

------------------------------------------------------------------- gradients
T.gradient = {
	gold      = seq({ { pos = 0, hex = "#FFE87A" }, { pos = 0.55, hex = "#FFC531" }, { pos = 1, hex = "#E08A0C" } }),
	goldSmall = seq({ { pos = 0, hex = "#FFE066" }, { pos = 0.52, hex = "#FFC531" }, { pos = 1, hex = "#E8930F" } }),
	green     = seq({ { pos = 0, hex = "#83E34A" }, { pos = 1, hex = "#4FB42E" } }), -- guide green
	purple    = seq({ { pos = 0, hex = "#DE93FF" }, { pos = 0.52, hex = "#B04CEC" }, { pos = 1, hex = "#7C1CC0" } }),
	red       = seq({ { pos = 0, hex = "#FF6B6B" }, { pos = 1, hex = "#D83E3E" } }), -- guide red
	blue      = seq({ { pos = 0, hex = "#56B7FF" }, { pos = 1, hex = "#2E81D8" } }), -- guide blue
	gem       = seq({ { pos = 0, hex = "#D98BFF" }, { pos = 0.52, hex = "#A93FE6" }, { pos = 1, hex = "#7A1CB8" } }),

	-- guide: light gray window, dark gray slots/rows, red header bar
	panel     = seq({ { pos = 0, hex = "#D6D6D6" }, { pos = 1, hex = "#A9A9A9" } }),
	subPanel  = seq({ { pos = 0, hex = "#C4C4C4" }, { pos = 1, hex = "#9C9C9C" } }),
	row       = seq({ { pos = 0, hex = "#4A4A4A" }, { pos = 1, hex = "#363636" } }),
	tab       = seq({ { pos = 0, hex = "#BEBEBE" }, { pos = 1, hex = "#9C9C9C" } }),
	track     = seq({ { pos = 0, hex = "#2E2E2E" }, { pos = 1, hex = "#3A3A3A" } }),
	slot      = seq({ { pos = 0, hex = "#4A4A4A" }, { pos = 1, hex = "#363636" } }),
	-- the guide's red header bar, and the window gradient under its own name
	header    = seq({ { pos = 0, hex = "#F96B57" }, { pos = 1, hex = "#C84535" } }),
	window    = seq({ { pos = 0, hex = "#D6D6D6" }, { pos = 1, hex = "#A9A9A9" } }),

	freeCard  = seq({ { pos = 0, hex = "#F7F7F1" }, { pos = 0.55, hex = "#DEDED4" }, { pos = 1, hex = "#B2B4A8" } }),
	-- LEGACY ALIAS. Was the 1d/1e cream body (#FFF9EC -> #FFEDCD); now points
	-- at the guide's window gray so any surface still asking for "cream"
	-- inherits the new style instead of standing out as the last cream panel
	-- in the game. New code should ask for "window".
	cream     = seq({ { pos = 0, hex = "#D6D6D6" }, { pos = 1, hex = "#A9A9A9" } }),
	passCard  = seq({ { pos = 0, hex = "#FFE066" }, { pos = 0.55, hex = "#F7B62C" }, { pos = 1, hex = "#D8860E" } }),
	lockBadge = seq({ { pos = 0, hex = "#F2F2EC" }, { pos = 1, hex = "#C2C4B8" } }),
	knob      = seq({ { pos = 0, hex = "#FFF0A8" }, { pos = 1, hex = "#FFC531" } }),
	disabled  = seq({ { pos = 0, hex = "#6A7757" }, { pos = 1, hex = "#454F33" } }),
	ownedCta  = seq({ { pos = 0, hex = "#8FA378" }, { pos = 1, hex = "#54643C" } }),
	freeLabel = seq({ { pos = 0, hex = "#7A8A66" }, { pos = 1, hex = "#55643F" } }),
	passLabel = seq({ { pos = 0, hex = "#FFD84D" }, { pos = 1, hex = "#E0912A" } }),
}

------------------------------------------------------------------- geometry
-- guide: "outer stroke 4px dark gray, inner stroke 1-2px white"
T.stroke = { panel = 4, control = 3, chip = 3, hairline = 2, inner = 2 }

-- guide: "Panels 8px, Buttons 10-14px, Slots 8px" -- the whole family tightens
-- from the old 22/16/14 chunky-cartoon radii
T.radius = {
	panel = 8, control = 12, inner = 10, small = 10, chip = 10, slot = 8, art = 8, pill = 999,
}

-- Hard offset shadow = stroke + 1
T.shadowOffset = { panel = 6, control = 5, chip = 4 }

T.gloss = { height = 5, alpha = 0.45, alphaLight = 0.30, shadeHeight = 6, shadeAlpha = 0.82 }

T.pad = { panel = 16, panelWide = 18, gap = 12, gapTight = 8, gridGap = 11, rowGap = 10 }

T.size = {
	canvas        = Vector2.new(1350, 775),
	headerHeight  = 92,
	headerIcon    = 64,
	closeButton   = Vector2.new(74, 66),
	-- kit deviation: tokens.lua shipped stale v1 rail values; v2 README §3.7
	-- + capture are authoritative (pixel-adjudicated). v1 was a 98x88
	-- goldSmall button-plate rail with a 42px icon slot; v2 floats a bare
	-- 66px icon in a 106px-wide column with a label underneath -- no plate.
	railItem      = 106,  -- v2: item column width (was Vector2(98,88) plate size)
	railIcon      = 66,   -- v2: floating icon size (was 42, sized for the old plate's icon slot)
	railGap       = 6,    -- v2: vertical gap between rail items (was 10)
	railInset     = 10,   -- v2: inset of the rail from its canvas edge, whichever edge that is (was 16, was described as "right" before the left-side move)
	railGlow      = 88,   -- v2 NEW: diameter of the active-state radial gold glow behind the icon (v1 had no glow -- it used a stroked ring around the plate instead)
	railSide      = "left", -- kit deviation: tokens.lua shipped stale v1 rail; v2 README §3.7 + capture authoritative (pixel-adjudicated); railSide = user decision 2026-07-30.
	currencyPill  = 54,
	rewardCard    = Vector2.new(178, 186),
	tierBadge     = 58,
	lockBadge     = 46,
	claimPill     = 38,
	bagSlot       = 118,
	dayCard       = 196,
	questRow      = 88,
	-- eggs = 860, NOT the kit README 3.1 figure of 1080. That budget assumed a 296
	-- side column (balance + quests) and a x1/x3/x10 quantity segment, none of
	-- which this game has: quests moved to the Goals panel and the server takes no
	-- quantity. 1080 also COLLIDES with the nav rail -- the rail is 2 columns on
	-- the LEFT ending at x=228 (railItem 106 x2 + railGap 6 + railInset 10), and a
	-- 1080 panel centred on the 1350 canvas starts at x=135, overlapping it by 93px.
	-- 860 leaves a 245px gutter and clears the rail by 17px, and is derived from the
	-- row itself: art 64 + gap 12 + name 196 + gap 12 + action 132, plus the odds column.
	-- daily = 800 (2026-08-04, mock 1e; was 900 pre-restyle)
	panelWidth    = { pass = 960, backpack = 960, settings = 700, daily = 800, index = 940, goals = 860, eggs = 940 },
	panelRightGutter = 132, -- reserves the nav rail
}

------------------------------------------------------------------- type
-- guide: "GothamBold" for everything. NOTE: StarterPlayerScripts.UIPolish
-- force-sets the legacy .Font property on EVERY TextLabel in the game and
-- would overwrite these FontFaces on the next frame -- its own FONT constant
-- was moved in lockstep with this one. Changing one without the other is a
-- silent no-op.
T.font = {
	display = Font.fromEnum(Enum.Font.GothamBold),
	ui      = Font.fromEnum(Enum.Font.GothamBold),
}

-- { size, textStrokeThickness }
-- guide: "Titles 28-34, Buttons 18-24, Labels 14-18" -- everything steps down
-- from the old 44/32/24 display sizes. Stroke weights drop with them.
T.text = {
	panelTitle = { 32, 3 },
	buttonL    = { 24, 2.5 },
	buttonM    = { 20, 2 },
	value      = { 22, 2 },
	cardLabel  = { 17, 2 },
	chip       = { 14, 1.5 },
	railLabel  = { 20, 4 }, -- v2 NEW (README 3.7 "Fredoka One 20 / stroke 4") -- v1 rail labels reused the smaller "chip" style (14/2.5), sized for the button-plate design
	meta       = { 14, 0 },   -- Nunito/Gotham, no stroke
}

------------------------------------------------------------------- motion
T.tween = {
	hover      = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	press      = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	panelOpen  = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	panelClose = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	scrim      = TweenInfo.new(0.15, Enum.EasingStyle.Linear),
	pop        = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	fly        = TweenInfo.new(0.38, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	bar        = TweenInfo.new(0.40, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	pulsePeriod = 1.6,
	bobPeriod   = 1.4,
	claimStagger = 0.06,
}

T.zindex = { world = 0, currency = 20, panel = 25, rail = 30, kit = 50, toast = 80 }

------------------------------------------------------------------ icons
-- IMPORTED 2026-08-01. These are the kit's own 512px PNGs
-- (docs/design-handoff/ui-kit/captures/icons/*_512.png), uploaded from the
-- prohacks_sorry account and now live.
--
-- How, for whenever they need re-uploading: AssetService:CreateAssetAsync is
-- still unavailable in this Studio session, and the Studio MCP's upload_image
-- rejects local file paths -- it only accepts http/https. The route that works
-- is to serve the folder locally (`python -m http.server 8731 --bind
-- 127.0.0.1` inside the icons directory) and hand it the resulting
-- http://127.0.0.1:8731/<name>_512.png URLs. No Asset Manager step needed.
--
-- Every consumer treats a non-empty string here as authoritative and only
-- falls back to UIKit.IconArt's hand-drawn vector versions when it is empty,
-- so clearing an entry cleanly reverts that one icon to the drawn art.
T.icons = {
	coin     = "rbxassetid://120939757686142",
	gem      = "rbxassetid://74999666659461",
	bag      = "rbxassetid://77577521462882",
	pass     = "rbxassetid://130523141580395",
	daily    = "rbxassetid://83042393142430",
	goals    = "rbxassetid://108696772678645",
	index    = "rbxassetid://111712046264165",
	settings = "rbxassetid://85088540596145",
}

return T
