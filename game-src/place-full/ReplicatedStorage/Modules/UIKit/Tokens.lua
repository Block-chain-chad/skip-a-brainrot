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
-- ============================================================================
-- 2026-08-10 SPEC SWEEP (design_handoff_hud_upgrade): the Pet-Sim grays are
-- REPLACED by the HUD-upgrade sheet's families so every legacy surface (egg
-- shop, daily, charms, wheel, luck chip, toasts, trade...) inherits the new
-- game-wide look through these tokens with no per-file edits -- the same
-- one-edit lever the 2026-08-04 style replacement used. Names keep their
-- meanings: window = light body ground, row/slot = white cards, tab = the
-- sheet's Neutral control, track = the sheet's dark track, header = the
-- sheet's slate (rail panels carry their own per-panel plate colours).
-- WHITE LABELS STAY LEGIBLE on the light cards because UIPolish gives every
-- unexempted label a dark ink stroke -- bubble text reads on any ground.
-- ============================================================================
-- ============================================================================
-- 2026-08-13 STYLE REPLACEMENT -- "LemonPop" (Downloads/LemonPop-Theme.lua +
-- docs/superpowers/specs/2026-08-13-lemonpop-theme-design.md): warm
-- lemon-cream windows, gold furniture, warm near-black outlines, ONE red
-- surface per panel (the header). REPLACES the 2026-08-10 slate sweep above;
-- that sweep's hexes are recorded inline ("was") so any surface can be
-- walked back. Light surfaces carry dark UNSTROKED ink; dark surfaces keep
-- white/gold stroked type -- see the NEW textMutedOnDark / textAccentOnDark
-- split tokens, and note row/track flip back to DARK (warm) grounds.
-- ============================================================================
T.color = {
	outline        = hex("#241F14"), -- LemonPop warm near-black (was slate #071323)
	innerKeyline   = hex("#FFFFFF"),

	panelTop       = hex("#FFFBE2"), -- (was #DCE6F0)
	panelBottom    = hex("#FFD977"), -- (was #C9D6E4)
	subPanelTop    = hex("#FFF6CF"), -- (was #FFFFFF)
	subPanelBottom = hex("#F7C95C"), -- (was #E4EDF7)
	rowTop         = hex("#4A4030"), -- DARK FLIP: currency pills / buy strips (was white card #FFFFFF)
	rowBottom      = hex("#302A1F"), -- (was #E4EDF7)
	tabTop         = hex("#C2A878"), -- (was #8FA2B6)
	tabBottom      = hex("#8A7350"), -- (was #5A6E82)
	trackTop       = hex("#302A1F"), -- (was #2A3B4F)
	trackBottom    = hex("#3D3527"), -- (was #22303F)
	slotTop        = hex("#FFFFFF"), -- art wells stay light so renders read (was #F2F7FC)
	slotBottom     = hex("#FFF4D9"), -- (was #DCE6F0)
	headerTop      = hex("#FF6B5C"), -- the ONE red surface per panel (was slate #5B7086)
	headerBottom   = hex("#D8342C"), -- (was #28394E)

	white          = hex("#FFFFFF"),
	textMuted      = hex("#7A6A52"), -- LIGHT surfaces ONLY (was #4D6480; dark surfaces take textMutedOnDark)
	textMutedOnDark = hex("#E8DCBE"), -- NEW 2026-08-13: muted text on row/track/dark pills
	textAccent     = hex("#C2410C"), -- LIGHT surfaces ONLY (was #E8930F; dark surfaces take textAccentOnDark)
	textAccentOnDark = hex("#FFD84D"), -- NEW 2026-08-13: values on dark surfaces
	textOnLight    = hex("#33261A"), -- dark ink, NO text stroke on light surfaces (was #12283D)
	textOnWindow   = hex("#33261A"), -- explicit alias for the above (was #12283D)
	textOnGoldCard = hex("#3A2A05"),
	textOnGoldChrome = hex("#5A4A12"),
	textDisabled   = hex("#A79A7C"), -- warm taupe (was #8FA2B6)
	textClaimed    = hex("#9C8F6E"), -- (was #6DA35E)

	claimRing      = hex("#7CE04A"),
	activeRing     = hex("#FFD84D"),
	activeGlow     = hex("#FFE87A"), -- v2 NEW: nav rail active-state radial glow (README 3.7 "rgba(255,232,122,.75)") -- distinct from activeRing (#FFD84D), which other panels' tab/segment rings still use
	scrollThumb    = hex("#C2A878"), -- tab tan (was sage #9FAE8B)

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
	gold      = seq({ { pos = 0, hex = "#FFF08A" }, { pos = 0.55, hex = "#FFC531" }, { pos = 1, hex = "#E08A0C" } }), -- LemonPop: top stop was #FFE87A
	goldSmall = seq({ { pos = 0, hex = "#FFE066" }, { pos = 0.52, hex = "#FFC531" }, { pos = 1, hex = "#E8930F" } }),
	green     = seq({ { pos = 0, hex = "#83E34A" }, { pos = 1, hex = "#4FB42E" } }), -- guide green
	purple    = seq({ { pos = 0, hex = "#DE93FF" }, { pos = 0.52, hex = "#B04CEC" }, { pos = 1, hex = "#7C1CC0" } }),
	red       = seq({ { pos = 0, hex = "#FF6B6B" }, { pos = 1, hex = "#D83E3E" } }), -- guide red
	blue      = seq({ { pos = 0, hex = "#56B7FF" }, { pos = 1, hex = "#2E81D8" } }), -- guide blue
	gem       = seq({ { pos = 0, hex = "#D98BFF" }, { pos = 0.52, hex = "#A93FE6" }, { pos = 1, hex = "#7A1CB8" } }),

	-- LemonPop 2026-08-13: lemon-cream body, warm dark rows, red header
	-- (was spec sweep 2026-08-10: light body, white cards, slate header --
	-- panel #DCE6F0->#C9D6E4, subPanel/row #FFFFFF->#E4EDF7, tab #8FA2B6->#5A6E82,
	-- track #2A3B4F->#22303F, slot #F2F7FC->#DCE6F0, header #5B7086->#28394E)
	panel     = seq({ { pos = 0, hex = "#FFFBE2" }, { pos = 1, hex = "#FFD977" } }),
	subPanel  = seq({ { pos = 0, hex = "#FFF6CF" }, { pos = 1, hex = "#F7C95C" } }),
	row       = seq({ { pos = 0, hex = "#4A4030" }, { pos = 1, hex = "#302A1F" } }),
	tab       = seq({ { pos = 0, hex = "#C2A878" }, { pos = 1, hex = "#8A7350" } }),
	track     = seq({ { pos = 0, hex = "#302A1F" }, { pos = 1, hex = "#3D3527" } }),
	slot      = seq({ { pos = 0, hex = "#FFFFFF" }, { pos = 1, hex = "#FFF4D9" } }),
	header    = seq({ { pos = 0, hex = "#FF6B5C" }, { pos = 1, hex = "#D8342C" } }),
	window    = seq({ { pos = 0, hex = "#FFFBE2" }, { pos = 1, hex = "#FFD977" } }),

	freeCard  = seq({ { pos = 0, hex = "#FFFDEE" }, { pos = 0.55, hex = "#F5E7C0" }, { pos = 1, hex = "#D9BC82" } }), -- LemonPop (was gray-whites #F7F7F1/#DEDED4/#B2B4A8)
	-- LEGACY ALIAS. Was the 1d/1e cream body (#FFF9EC -> #FFEDCD); now points
	-- at the guide's window gray so any surface still asking for "cream"
	-- inherits the new style instead of standing out as the last cream panel
	-- in the game. New code should ask for "window".
	cream     = seq({ { pos = 0, hex = "#FFFBE2" }, { pos = 1, hex = "#FFD977" } }), -- LemonPop: tracks window (was #DCE6F0 -> #C9D6E4)
	passCard  = seq({ { pos = 0, hex = "#FFE066" }, { pos = 0.55, hex = "#F7B62C" }, { pos = 1, hex = "#D8860E" } }),
	lockBadge = seq({ { pos = 0, hex = "#FFF6DC" }, { pos = 1, hex = "#D8C494" } }), -- LemonPop (was #F2F2EC -> #C2C4B8)
	knob      = seq({ { pos = 0, hex = "#FFF0A8" }, { pos = 1, hex = "#FFC531" } }),
	disabled  = seq({ { pos = 0, hex = "#8A7C5E" }, { pos = 1, hex = "#5C5138" } }), -- LemonPop warm taupe (was slate #4A5B6E -> #2A3B4F)
	ownedCta  = seq({ { pos = 0, hex = "#A98F5C" }, { pos = 1, hex = "#6E5A34" } }), -- LemonPop (was olive #8FA378 -> #54643C)
	freeLabel = seq({ { pos = 0, hex = "#B89B5E" }, { pos = 1, hex = "#7C6438" } }), -- LemonPop (was olive #7A8A66 -> #55643F)
	passLabel = seq({ { pos = 0, hex = "#FFD84D" }, { pos = 1, hex = "#E0912A" } }),
}

------------------------------------------------------------------- geometry
-- guide: "outer stroke 4px dark gray, inner stroke 1-2px white"
T.stroke = { panel = 6, control = 4, chip = 4, hairline = 2, inner = 2 }

-- guide: "Panels 8px, Buttons 10-14px, Slots 8px" -- the whole family tightens
-- from the old 22/16/14 chunky-cartoon radii
-- spec sweep 2026-08-10: "rounded, not round" -- the whole family steps up
T.radius = {
	panel = 24, control = 18, inner = 14, small = 12, chip = 12, slot = 12, art = 10, pill = 999,
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
	-- charms = 1120 (2026-08-07, Charm Codex) -- the WIDEST panel in the game;
	-- next is pass/backpack at 960. Justified by the design's two-column body
	-- (charm grid ~55% + detail column ~45%) sitting under a full-width slot
	-- row. Fits the 1350 canvas with a 115px gutter each side, which clears the
	-- nav rail's 228px left column ONLY because the rail moved to its own
	-- non-letterboxed chrome layer (see GameHUDClient "HUD RESCUE") -- on the
	-- centred canvas a 1120 panel starts at x=115 and the rail would still be
	-- drawn over it if it had stayed here. Do not widen further without
	-- re-checking that.
	-- worlds = 1080 (2026-08-09 HUD upgrade, design_handoff_hud_upgrade): the
	-- first panel on the sheet's PanelChrome shell, authored in the sheet's own
	-- 1920-canvas px and fitted via the paired panelHeight entry below.
	panelWidth    = { pass = 960, backpack = 1080, settings = 1000, daily = 800, index = 940, goals = 1140, eggs = 940, charms = 1120, worlds = 1080, shop = 1180 },
	-- Per-panel fit HEIGHT for spec-shell panels (2026-08-09 HUD upgrade).
	-- A panel with no entry keeps GameHUDClient's 700 floor exactly.
	panelHeight   = { worlds = 660, shop = 830, goals = 800, settings = 1090, backpack = 720 },
	panelRightGutter = 132, -- reserves the nav rail
}

------------------------------------------------------------------- type
-- guide: "GothamBold" for everything. NOTE: StarterPlayerScripts.UIPolish
-- force-sets the legacy .Font property on EVERY TextLabel in the game and
-- would overwrite these FontFaces on the next frame -- its own FONT constant
-- was moved in lockstep with this one. Changing one without the other is a
-- silent no-op.
-- spec sweep 2026-08-10: FredokaOne is the sheet's READ face. Moves in
-- LOCKSTEP with UIPolish's FONT constant (see that file's header) -- the
-- sweep there force-sets .Font on every unexempted label.
T.font = {
	display = Font.fromEnum(Enum.Font.FredokaOne),
	ui      = Font.fromEnum(Enum.Font.FredokaOne),
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
