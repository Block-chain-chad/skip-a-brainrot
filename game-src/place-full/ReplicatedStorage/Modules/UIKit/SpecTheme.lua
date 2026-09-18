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
-- new emerald face. The uploaded premiumCounter asset is the pill rebuilt with
-- the face and gems removed; UIKit.IconArt's drawn emerald face is placed over
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
-- 2026-08-16 PS99 RESTYLE (user reference: Pet Simulator 99, chosen from their
-- Continue row): WHITE unified chrome. Panels are one clean white shell -- no
-- coloured header slabs -- the TITLE carries panel identity (coloured bubble
-- letters, white stroke), close is a pink-red rounded square overlapping the
-- corner, CTAs are candy green, interiors use SOFT grey-blue edges while
-- buttons keep the chunky dark edge that matches the nav-rail stickers.
S.Outline = hex("313D4F") -- chunky edge for BUTTONS/close (PS99 cool navy; was warm 241F14)
S.OutlineSoft = hex("D8E0EA") -- NEW: soft interior edge for rows/tiles/body wells

-- PS99 restyle: every header plate is WHITE -- identity moved to S.TitleInk.
-- (pre-restyle plates: bag 7DE86A/28B93C, goals FFC21A/FF8A00, worlds
-- 27D7FF/078DEB, shop FFD83D/FFB900, settings C2A878/8A7350, rebirth green)
S.Plate = {
	bag      = { hex("FFFFFF"), hex("EFF3F9") },
	goals    = { hex("FFFFFF"), hex("EFF3F9") },
	worlds   = { hex("FFFFFF"), hex("EFF3F9") },
	shop     = { hex("FFFFFF"), hex("EFF3F9") },
	settings = { hex("FFFFFF"), hex("EFF3F9") },
	rebirth  = { hex("FFFFFF"), hex("EFF3F9") },
}

-- NEW (PS99 restyle): per-panel title colour -- the old plate hues live on as
-- bubble-lettered titles on the white shell. White-stroked via PanelChrome.
S.TitleInk = {
	bag      = hex("2FBE4F"),
	goals    = hex("FF9F1C"),
	daily    = hex("FF9F1C"), -- daily gift orange (2026-08-18 DailyPanel re-shell)
	worlds   = hex("29C5FF"),
	shop     = hex("FFB300"),
	settings = hex("4AA8FF"),
	rebirth  = hex("FF5DA0"),
	default  = hex("29C5FF"),
}

S.Action = {
	Go      = { hex("63DE43"), hex("31A824") },  -- travel / claim / buy: PS99 candy green (was 8FE3A0/28B93C)
	Neutral = { hex("D3DCE6"), hex("B7C4D3") },  -- inactive tab, in progress (PS99 light grey; was mid grey-blue B9C6D6/8B9DB3)
	Inert   = { hex("93A1B4"), hex("6E7E94") },  -- "you are here", locked (cool; was taupe 8A7C5E/5C5138)
	Pale    = { hex("EBF1F7"), hex("DEE6EF") },  -- inert STATE fill (statePlate default): barely off the ground -- PS99 grammar, chrome means clickable, so a non-button never wears a saturated ramp
	Danger  = { hex("FF5D80"), hex("E02454") },  -- close button (PS99 pink-red; was FF6B6B/D83E3E)
	Gold    = { hex("FFE9A8"), hex("FFC53D") },  -- selected tab, tier plate
	Robux   = { hex("FFCF40"), hex("F09A0C") },  -- REAL-MONEY price pills ONLY (PS99 grammar: gold = Robux, nothing else; white shout + dark stroke stays legible on this saturation)
	Premium = { hex("C14CFF"), hex("7D19E8") },  -- emeralds
	Warn    = { hex("FFF0C2"), hex("FFD866") },
	GreenFill = { hex("6EE04E"), hex("35A82A") }, -- slider fill / free track / toggle-on (PS99 green)
	Knob    = { hex("FFE07A"), hex("FFB300") },   -- slider knob
	Violet  = { hex("E4CCFF"), hex("B981F0") },   -- reward chips (emeralds are violet everywhere)
	VioletRow = { hex("F6EDFF"), hex("DCC6F5") }, -- shop emerald-family rows
}

S.Surface = {
	Shell     = hex("FFFFFF"), -- PS99: the shell IS white (was warm dark rim 302A1F)
	Body      = hex("F5F8FC"), -- soft cool inset ground (was lemon FFF6CF)
	RowTop    = hex("FFFFFF"), -- white cards, soft-stroked (unchanged)
	RowBottom = hex("F4F7FB"), -- (was FFF4D9)
	Track     = hex("2E3A4C"), -- cool navy track so white bar labels stay legible (was 302A1F)
	ReadInk   = hex("33414F"),  -- body text (cool navy; was warm 33261A)
	ReadSub   = hex("7C8CA0"),  -- subtitles / meta (was 7A6A52)
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
	ShellOutline  = 7,  -- PS99: white shell wears a slimmer edge (was 12)
	ShellPadding  = 18,

	HeaderHeight  = 112,
	HeaderRadius  = 30,
	HeaderOutline = 0,  -- PS99: header merges into the white shell (was 8)
	HeaderPadding = 26,

	CloseSize     = 84,
	CloseOutline  = 5,  -- white-stroked pink square (was 7 dark)

	BodyRadius    = 32,
	BodyOutline   = 2,  -- soft grey-blue seam only (was 8 dark)
	BodyPadding   = 22,

	RowHeight     = 112,
	RowGap        = 16,
	RowRadius     = 24,
	RowOutline    = 3,  -- soft-stroked (was 6 dark)

	IconTile      = 78,
	IconRadius    = 20,
	IconOutline   = 3,  -- soft-stroked (was 5 dark)

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
	PanelIn  = TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), -- PS99 restyle: bouncier entrance (was 0.22)
	PanelOut = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
}
S.Scale = { Hover = 1.03, Press = 0.97 } -- 2026-09-18 UI foundation (handoff §12): subtle; was 1.06/0.94 (PS99 restyle), 1.05/0.95 before that

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
	EmeraldsW    = 162,                   -- 231 @1920
	CounterGap  = 10,                    -- 14 @1920
	-- Counter value overlays, in scale units of each counter image --
	-- MEASURED against the pill pixels inside the PNGs, not the sheet's
	-- nominal (0.66, 0.5): the pill's middle sits at ~0.61 of the image
	-- height in both arts, and the cash pill's number area starts right of
	-- the painted coin stack.
	ValuePosCash    = Vector2.new(0.71, 0.61),
	ValuePosEmeralds = Vector2.new(0.66, 0.62),
	ValueSize   = Vector2.new(0.50, 0.38),
}

------------------------------------------------------------------------- art
-- Uploaded 2026-08-09 from design_handoff_hud_upgrade/assets (served via
-- python -m http.server + upload_image, same route as Tokens.icons).
-- premiumCounter is the REBUILT pill: baked emerald face + gems removed
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

-------------------------------------------------------------------- 2026-09-18
-- UI FOUNDATION ROUND 1 (spec docs/superpowers/specs/2026-09-18-ui-foundation-
-- design.md). Semantic colour grammar (handoff §4), spacing scale (§16), sound
-- names, and the BrainrotCard ladder (§5). S.Action.* keep their values as
-- aliases -- S.Action.Neutral stays the light grey because every existing
-- paint closure pairs it as the INACTIVE colour with S.Action.Go.
S.Role = {
	Positive       = S.Action.Go,                       -- equip / claim / confirm / teleport / buy with coins
	Destructive    = S.Action.Danger,                   -- delete / remove / close (one red)
	Neutral        = { hex("4AA8FF"), hex("1E7BE0") },  -- utility, filters, sort, ACTIVE tab (blue = navigation)
	Gold           = S.Action.Robux,                    -- coins, rewards, value, prices (Robux prices carry the Robux mark)
	Purple         = S.Action.Premium,                  -- gems, premium
	Disabled       = S.Action.Neutral,                  -- inactive tabs, secondary chips (dark ink)
	DisabledButton = { hex("B9C2CC"), hex("96A1AD") },  -- a disabled button's fill (label at 0.45 transparency)
	Selection      = hex("29C5FF"),                     -- selected ring (= Tokens.activeRing)
}
S.Space = { micro = 8, small = 12, std = 16, section = 24, large = 32 } -- spec px, same sheet as S.Chrome
S.Sound = { Click = "uiClick", PanelOpen = "panelOpen", PanelClose = "panelClose" } -- SoundKit ids
S.Card = {
	Plate     = { hex("3A4656"), hex("2A3543") },
	Radius    = 14,
	Edge      = 3,
	BandFrac  = 0.20,
	BandMin   = 24,
	ArtInset  = 4,
	Fill      = 0.88,           -- projected-box fill of the ART HOLDER (~76% of the card), i.e. ~67% of the card: handoff §6's 65-75%. 0.70 read small (Task 8/11, 2026-09-18)
	Pip       = 7,
	Badge     = 22,
	BadgeSmall = 14,
	MutationStar = 16,
	ArtWellAlpha = 0.90,        -- white radial behind the model (transparency at centre)
	MaxAnimatedLayers = 2,
	Light = {                   -- the Bag's relit rig (BackpackPanel build3DOrSwatch, 2026-08-17)
		Dir = Vector3.new(0.18, 0.32, -1).Unit,
		Ambient = Color3.fromRGB(205, 210, 220),
		LightColor = Color3.fromRGB(255, 248, 232),
		LightDirection = Vector3.new(-0.18, -0.32, 1),
	},
	-- 2026-09-18 Gallery stress test: the dev desktop stayed at the 16.7ms vsync floor
	-- up to 96 live viewports, and the "phone" run was the same machine under
	-- PlatformOverride -- so these are CONSERVATIVE defaults, not measured ceilings.
	-- ViewportCuller steps a cap down 25% whenever 30 frames run over budget, which
	-- is the real guard on weaker hardware. Re-measure Phone on a real device.
	MaxLive = { Desktop = 64, Tablet = 40, Phone = 24 },
	Variants = {
		grid    = { bandMin = 24, leftBadges = true,  rightCap = 2, title = false },
		compact = { bandMin = 20, leftBadges = false, rightCap = 1, title = false },
		hero    = { bandMin = 32, leftBadges = true,  rightCap = 3, title = true },
	},
	-- rarity tier name -> S.Rarity key
	TIER_KEY = { Common = "COM", Uncommon = "UNC", Rare = "RARE", Epic = "EPIC",
		Legendary = "LEG", Mythic = "MYTH", Secret = "SEC", God = "GOD" },
	-- spec §7.4: one table drives every layer. foil = white-sheet transparency or nil,
	-- aura = nil | "breathe" | "strong", band = "muted" | "solid" | "rainbow",
	-- animated = the continuously animated layers (max 2), holo/sparkles booleans.
	Ladder = {
		COM  = { pips = 1, band = "muted",   foil = nil,  aura = nil,       holo = false, sparkles = false, animated = {} },
		UNC  = { pips = 1, band = "solid",   foil = nil,  aura = nil,       holo = false, sparkles = false, animated = {} },
		RARE = { pips = 2, band = "solid",   foil = nil,  aura = nil,       holo = false, sparkles = false, animated = {} },
		EPIC = { pips = 3, band = "solid",   foil = 0.87, aura = nil,       holo = false, sparkles = false, animated = {} },
		LEG  = { pips = 4, band = "solid",   foil = 0.80, aura = "breathe", holo = false, sparkles = false, animated = { "aura" } },
		MYTH = { pips = 5, band = "rainbow", foil = 0.70, aura = "breathe", holo = true,  sparkles = false, animated = { "band", "aura" } },
		SEC  = { pips = 5, band = "rainbow", foil = 0.70, aura = "strong",  holo = true,  sparkles = true,  animated = { "band", "sparkles" } },
		GOD  = { pips = 5, band = "rainbow", foil = 0.70, aura = "strong",  holo = true,  sparkles = true,  animated = { "band", "sparkles" } },
	},
	Rainbow = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, hex("FF2D6F")), ColorSequenceKeypoint.new(0.17, hex("FF9B2F")),
		ColorSequenceKeypoint.new(0.33, hex("F5F24A")), ColorSequenceKeypoint.new(0.50, hex("58F06A")),
		ColorSequenceKeypoint.new(0.67, hex("3FE0FF")), ColorSequenceKeypoint.new(0.83, hex("C93AFF")),
		ColorSequenceKeypoint.new(1.00, hex("FF2D6F")),
	}),
}

return S
