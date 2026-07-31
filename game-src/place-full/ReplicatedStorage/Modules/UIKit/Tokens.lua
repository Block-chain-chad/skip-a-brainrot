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

------------------------------------------------------------------- colours
T.color = {
	outline        = hex("#16170F"),

	panelTop       = hex("#414E36"),
	panelBottom    = hex("#2B3423"),
	subPanelTop    = hex("#4A5840"),
	subPanelBottom = hex("#2E3825"),
	rowTop         = hex("#4E5C3B"),
	rowBottom      = hex("#333E24"),
	tabTop         = hex("#7A8A66"),
	tabBottom      = hex("#4E5C3B"),
	trackTop       = hex("#1B2114"),
	trackBottom    = hex("#26301C"),
	slotTop        = hex("#37432D"),
	slotBottom     = hex("#232C1C"),

	white          = hex("#FFFFFF"),
	textMuted      = hex("#C9D6B4"),
	textAccent     = hex("#FFD84D"),
	textOnLight    = hex("#1E2317"),
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
	green     = seq({ { pos = 0, hex = "#A6EE72" }, { pos = 0.52, hex = "#5FC22F" }, { pos = 1, hex = "#317F16" } }),
	purple    = seq({ { pos = 0, hex = "#DE93FF" }, { pos = 0.52, hex = "#B04CEC" }, { pos = 1, hex = "#7C1CC0" } }),
	red       = seq({ { pos = 0, hex = "#FF8A7A" }, { pos = 0.52, hex = "#E23A2C" }, { pos = 1, hex = "#A8140F" } }),
	blue      = seq({ { pos = 0, hex = "#6FD8FF" }, { pos = 0.52, hex = "#2A93E0" }, { pos = 1, hex = "#125FA8" } }),
	gem       = seq({ { pos = 0, hex = "#D98BFF" }, { pos = 0.52, hex = "#A93FE6" }, { pos = 1, hex = "#7A1CB8" } }),

	panel     = seq({ { pos = 0, hex = "#414E36" }, { pos = 1, hex = "#2B3423" } }),
	subPanel  = seq({ { pos = 0, hex = "#4A5840" }, { pos = 1, hex = "#2E3825" } }),
	row       = seq({ { pos = 0, hex = "#4E5C3B" }, { pos = 1, hex = "#333E24" } }),
	tab       = seq({ { pos = 0, hex = "#7A8A66" }, { pos = 1, hex = "#4E5C3B" } }),
	track     = seq({ { pos = 0, hex = "#1B2114" }, { pos = 1, hex = "#26301C" } }),
	slot      = seq({ { pos = 0, hex = "#37432D" }, { pos = 1, hex = "#232C1C" } }),

	freeCard  = seq({ { pos = 0, hex = "#F7F7F1" }, { pos = 0.55, hex = "#DEDED4" }, { pos = 1, hex = "#B2B4A8" } }),
	passCard  = seq({ { pos = 0, hex = "#FFE066" }, { pos = 0.55, hex = "#F7B62C" }, { pos = 1, hex = "#D8860E" } }),
	lockBadge = seq({ { pos = 0, hex = "#F2F2EC" }, { pos = 1, hex = "#C2C4B8" } }),
	knob      = seq({ { pos = 0, hex = "#FFF0A8" }, { pos = 1, hex = "#FFC531" } }),
	disabled  = seq({ { pos = 0, hex = "#6A7757" }, { pos = 1, hex = "#454F33" } }),
	ownedCta  = seq({ { pos = 0, hex = "#8FA378" }, { pos = 1, hex = "#54643C" } }),
	freeLabel = seq({ { pos = 0, hex = "#7A8A66" }, { pos = 1, hex = "#55643F" } }),
	passLabel = seq({ { pos = 0, hex = "#FFD84D" }, { pos = 1, hex = "#E0912A" } }),
}

------------------------------------------------------------------- geometry
T.stroke = { panel = 5, control = 4, chip = 3.5, hairline = 3 }

T.radius = {
	panel = 22, control = 16, inner = 14, small = 12, chip = 11, slot = 10, art = 9, pill = 999,
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
	panelWidth    = { pass = 960, backpack = 960, settings = 700, daily = 900, index = 940, goals = 860, eggs = 860 },
	panelRightGutter = 132, -- reserves the nav rail
}

------------------------------------------------------------------- type
T.font = {
	display = Font.fromEnum(Enum.Font.FredokaOne),
	ui      = Font.fromEnum(Enum.Font.GothamBlack),
}

-- { size, textStrokeThickness }
T.text = {
	panelTitle = { 44, 5 },
	buttonL    = { 32, 4 },
	buttonM    = { 24, 3.5 },
	value      = { 26, 3.5 },
	cardLabel  = { 20, 3 },
	chip       = { 14, 2.5 },
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
