--!strict
-- SpecTheme -- every visual constant from the 2026-08-09 HUD upgrade build
-- sheet (design_handoff_hud_upgrade/README.md + HUD_SPEC.html). High fidelity:
-- these numbers are final; derive anything unspecified from the six rules in
-- the README rather than inventing new values.
--
-- PANELS are authored in the sheet's own 1920x1080 px and scaled as a whole
-- by GameHUDClient's per-panel host fit, so the Chrome/TextSize numbers here
-- are used RAW by panel code. HUD chrome (rail slots, counters) lives on the
-- 1350x775 canvas instead, so .Hud carries those numbers pre-scaled by 0.703.
--
-- OWNER DECISION (2026-08-09): the premium counter does NOT use the handoff's
-- new darrel face. The uploaded premiumCounter asset is the pill rebuilt with
-- the face and gems removed; UIKit.IconArt's drawn darrel face is placed over
-- its left end at runtime. Keep it that way.

local S = {}

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

--------------------------------------------------------------------- palette
-- 2026-08-13 LEMONPOP RETINT (spec docs/superpowers/specs/2026-08-13-lemonpop-
-- theme-design.md): the sheet's slate families go warm. Identity colours
-- (rail plates, rarity tiers, premium violet, action green/gold) stay; the
-- gray/slate grounds, neutrals and inks move to LemonPop. Old values inline.
S.Outline = hex("241F14") -- every interactive surface wears this edge (was slate 071323)

S.Plate = {
	bag      = { hex("7DE86A"), hex("28B93C") },
	goals    = { hex("FFC21A"), hex("FF8A00") },
	worlds   = { hex("27D7FF"), hex("078DEB") },
	shop     = { hex("FFD83D"), hex("FFB900") },
	settings = { hex("C2A878"), hex("8A7350") }, -- LemonPop warm tan (was slate 5B7086/28394E)
	rebirth  = { hex("7DE86A"), hex("28B93C") },
}

S.Action = {
	Go      = { hex("8FE3A0"), hex("28B93C") },  -- travel / claim / buy: ONE green per region
	Neutral = { hex("C2A878"), hex("8A7350") },  -- inactive tab, in progress (LemonPop tab tan; was slate 8FA2B6/5A6E82)
	Inert   = { hex("8A7C5E"), hex("5C5138") },  -- "you are here", locked (LemonPop disabled taupe; was slate 4A5B6E/2A3B4F)
	Danger  = { hex("FF6B6B"), hex("D83E3E") },  -- close button (LemonPop red; was FF7A6B/D6281B)
	Gold    = { hex("FFE9A8"), hex("FFC53D") },  -- selected tab, tier plate
	Premium = { hex("C14CFF"), hex("7D19E8") },  -- darrels
	Warn    = { hex("FFF0C2"), hex("FFD866") },
	GreenFill = { hex("8FE86A"), hex("3FB63B") }, -- slider fill / free track / toggle-on
	Knob    = { hex("FFE07A"), hex("FFB300") },   -- slider knob
	Violet  = { hex("E4CCFF"), hex("B981F0") },   -- reward chips (darrels are violet everywhere)
	VioletRow = { hex("F6EDFF"), hex("DCC6F5") }, -- shop darrel-family rows
}

S.Surface = {
	Shell     = hex("302A1F"), -- warm dark shell rim (was navy 25384F)
	Body      = hex("FFF6CF"), -- lemon-cream body ground (was slate-blue DCE6F0)
	RowTop    = hex("FFFFFF"), -- spec rows stay LIGHT cards = LemonPop slot family
	RowBottom = hex("FFF4D9"), -- (was #E4EDF7)
	Track     = hex("302A1F"), -- (was 2A3B4F)
	ReadInk   = hex("33261A"),  -- body text (LemonPop ink; was 12283D)
	ReadSub   = hex("7A6A52"),  -- subtitles / meta (was 4D6480)
}

S.Rarity = {
	COM  = { hex("C3CEDA"), hex("8195A8") },
	UNC  = { hex("8FE86A"), hex("3FB63B") },
	RARE = { hex("7FD4FF"), hex("0A7BD4") },
	EPIC = { hex("C14CFF"), hex("7D19E8") },
	LEG  = { hex("FFD83D"), hex("FFB900") },
	MYTH = { hex("FF8A8A"), hex("D6281B") },
	SEC  = { hex("FF54DD"), hex("E52ACF") },
	GOD  = { hex("FFF3B0"), hex("E9A400") },
}

------------------------------------------------------------------------ type
-- Two typefaces, no more. LuckiestGuy shouts (titles, prices, states);
-- FredokaOne reads (names, descriptions, values) -- the closest built-in to
-- the mock's Baloo 2 Bold. Spec components set NoPolish and own their text.
S.Font = {
	Shout = Enum.Font.LuckiestGuy,
	Read  = Enum.Font.FredokaOne,
}

S.TextSize = {
	PanelTitle  = 52,
	HeroAction  = 46,
	SectionHead = 34,
	RowTitle    = 34,
	Cta         = 30,
	RowSub      = 24,
	ChipState   = 24,
	Meta        = 22,
	BarLabel    = 20,
	Chip        = 20,
	StatValue   = 40,
}

-- UIStroke thickness for a given text size (4px at 46-52, 3 at 26-40, 2 below)
function S.strokeFor(textSize: number): number
	if textSize >= 42 then return 4 end
	if textSize >= 26 then return 3 end
	return 2
end

---------------------------------------------------------------------- chrome
-- Raw spec px (1920x1080 sheet). Panel code uses these numbers as-is.
S.Chrome = {
	ShellSize     = Vector2.new(1180, 760),
	ShellRadius   = 44,
	ShellOutline  = 12,
	ShellPadding  = 18,

	HeaderHeight  = 112,
	HeaderRadius  = 30,
	HeaderOutline = 8,
	HeaderPadding = 26,

	CloseSize     = 84,
	CloseOutline  = 7,

	BodyRadius    = 32,
	BodyOutline   = 8,
	BodyPadding   = 22,

	RowHeight     = 112,
	RowGap        = 16,
	RowRadius     = 24,
	RowOutline    = 6,

	IconTile      = 78,
	IconRadius    = 20,
	IconOutline   = 5,

	CtaSize       = Vector2.new(230, 76),
	CtaRadius     = 22,
	CtaOutline    = 6,

	TrackHeight   = 38,
	TrackRadius   = 19,
	KnobSize      = 52,

	ToggleSize    = Vector2.new(150, 62),
	ChipHeight    = 64,
	ChipRadius    = 18,
}

-- Per-panel shell size (spec px). Keys are openPanel screen names.
S.ShellFor = {
	worlds   = Vector2.new(1080, 660),
	shop     = Vector2.new(1180, 830),
	settings = Vector2.new(1000, 1090),
	goals    = Vector2.new(1140, 800),  -- Progress: Goals + Season Pass tabs
	rebirth  = Vector2.new(900, 740),
	backpack = Vector2.new(1080, 720),  -- Bag
}

---------------------------------------------------------------------- motion
S.Tween = {
	HoverIn  = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	HoverOut = TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Press    = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	PanelIn  = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	PanelOut = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
}
S.Scale = { Hover = 1.05, Press = 0.95 }

------------------------------------------------------------------------- hud
-- HUD chrome numbers, pre-scaled from the sheet's 1920 canvas onto this
-- game's 1350x775 chrome layer (x0.703, rounded). The rail art is 128x146
-- slots at 1920; uniform Fit letterboxes at most ~4px here -- do NOT size
-- each button to its own aspect (README, asset pipeline).
S.Hud = {
	Slot        = Vector2.new(90, 103),  -- menu button slot (128x146 @1920)
	SlotGap     = 7,                     -- 10 @1920
	EdgePad     = 18,                    -- shared with the currency cluster
	CounterH    = 70,                    -- 100 @1920
	CashW       = 155,                   -- 221 @1920
	DarrelsW    = 162,                   -- 231 @1920
	CounterGap  = 10,                    -- 14 @1920
	-- Counter value overlays, in scale units of each counter image --
	-- MEASURED against the pill pixels inside the PNGs, not the sheet's
	-- nominal (0.66, 0.5): the pill's middle sits at ~0.61 of the image
	-- height in both arts, and the cash pill's number area starts right of
	-- the painted coin stack.
	ValuePosCash    = Vector2.new(0.71, 0.61),
	ValuePosDarrels = Vector2.new(0.66, 0.62),
	ValueSize   = Vector2.new(0.50, 0.38),
}

------------------------------------------------------------------------- art
-- Uploaded 2026-08-09 from design_handoff_hud_upgrade/assets (served via
-- python -m http.server + upload_image, same route as Tokens.icons).
-- premiumCounter is the REBUILT pill: baked darrel face + gems removed
-- (owner keeps the game's own drawn face), digits removed from both counters.
S.Art = {
	bag            = "rbxassetid://135692251028443",
	goals          = "rbxassetid://127815184058475",
	worlds         = "rbxassetid://104435201453712",
	shop           = "rbxassetid://70809477172227",
	settings       = "rbxassetid://113408853914683",
	rebirth        = "rbxassetid://120595875472045",
	coinsCounter   = "rbxassetid://118605863327022",
	premiumCounter = "rbxassetid://101228590660547",
}

return S
