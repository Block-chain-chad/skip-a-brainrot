-- WheelConfig: the free daily spin.
--
-- Shared deliberately. The client draws the wheel from this exact table and the server
-- rolls from it, so a segment can never show one prize and pay another. The client is
-- told WHICH slot won and animates to it; it never decides the outcome.
--
-- Weights are whole percents and must total 100 -- see the assertion at the bottom.
-- To retune, change the numbers and keep the sum at 100; nothing else needs touching.

local WheelConfig = {}

WheelConfig.COOLDOWN   = 24 * 60 * 60   -- rolling 24h from the last spin, not calendar midnight
WheelConfig.BOOST_TIME = 10 * 60        -- seconds a boost lasts
WheelConfig.BOOST_MULT = 1.30           -- +30%

-- === PAID SPIN (Robux) =====================================================
-- Buying a spin SKIPS the cooldown and deliberately does NOT touch LastSpinAt:
-- paying for an extra spin must not cost you the free daily one you had banked.
--
-- >>> TO ACTIVATE <<<  (identical to EmeraldPackConfig -- see that file's notes)
--   1. Creator Dashboard: Creations > this game > Monetization >
--      Developer Products > Create a Developer Product
--   2. Set its price to RobuxPrice below. Roblox charges what the PRODUCT says,
--      not what this file says -- this number is only what the UI DISPLAYS, so if
--      the two disagree the button is lying about the price.
--   3. Paste the Product ID over the 0.
--
-- It MUST be a developer product, not a game pass. A pass is a one-time
-- entitlement and fires no ProcessReceipt, so it would take the Robux and grant
-- nothing -- the exact mistake documented at length in EmeraldPackConfig.
--
-- ProductId == 0 is the not-created-yet sentinel used game-wide: ProductRegistry
-- refuses to register it and the wheel hides the button rather than offering a
-- purchase that cannot complete.
-- >>> LIVE <<< (2026-08-18). Verified against Roblox before being pasted here,
-- which is the check EmeraldPackConfig's notes exist to demand:
--   3708787359  "Wheel Spin"  R$29  productType "Developer Product"
--   InfoType.Product resolves / InfoType.GamePass errors -- so it is a real
--   product and ProcessReceipt will fire for it.
-- The price was read back off Roblox and matches RobuxPrice below; change one and
-- you must change the other or the button lies about the cost.
WheelConfig.PAID_SPIN = {
	ProductId  = 3708787359,
	RobuxPrice = 29,
	Name       = "Wheel Spin",
}

function WheelConfig.IsPaidSpinLive(): boolean
	local p = WheelConfig.PAID_SPIN
	return type(p.ProductId) == "number" and p.ProductId > 0
end

-- === WORLD -> EGG WORLD ====================================================
-- The loot crate pays eggs "from the world it was spun in", and the two systems
-- name worlds differently: PlayerDataManager.PlayerWorld answers Valley/Tundra
-- (WorldProgression's names) while EggConfig.WORLDS is keyed Forest.
--
-- TUNDRA HAS NO EGGS. EggConfig.WORLDS contains exactly one entry today, so a
-- crate won in world 2 has nothing of its own to pay. Rather than silently give
-- nothing, WheelHandler falls back to FALLBACK_EGG_WORLD and warns. Authoring a
-- Tundra egg table in EggConfig and adding its key here is the whole fix -- no
-- other code has to change.
WheelConfig.EGG_WORLD_BY_WORLD = {
	Valley = "Forest",
	-- Tundra = "<add once EggConfig.WORLDS has a tundra table>",
}
WheelConfig.FALLBACK_EGG_WORLD = "Forest"

-- Order here is the order around the wheel, clockwise from the top. The two boosts sit
-- opposite each other and the 1% jackpot sits between two commons, so the pointer is
-- never parked next to two big prizes at once.
-- Each slot carries three separate display strings because the wedge shows all three at
-- different radii, the way a real prize wheel does:
--   Name   big, curved along the outer arc
--   Value  what you actually get, under the icon
--   Short  the compact form, used where space is tight (the world wheel)
--
-- OddsStyle tiers the LETTERING by how rare the wedge is -- rainbow on the 1%,
-- diamond on the 9%, gold on the two 15%s, plain white on the common rungs, across
-- the name, the payout and the odds alike. It is a property of the slot rather than
-- a lookup on the weight, so a re-weighting cannot silently hand the jackpot's
-- rainbow to a common prize.
--
--   Icon      a GLYPH, and what every surface actually draws: the full-screen
--             wheel, the prize list and the world board. Chosen so each is
--             unmistakable at ~50px and no two share a silhouette -- worth more
--             here than bespoke art, because nothing on this wheel is ever drawn
--             big enough for detail to survive.
--   Art       a UIKit.IconArt key -- the game's own DRAWN artwork, built out of
--             GUI frames rather than rendered in a viewport. This is the one
--             icon route that survives the wedge chip, because a drawn icon is
--             just nested Frames: it is resolution-independent and anti-aliased
--             by the same renderer the rest of the HUD uses, where a
--             ViewportFrame model is not (see IconKind below). A slot with Art
--             draws it INSTEAD of Icon; a slot without one keeps its glyph.
--             ALL SIX wedges carry one now (2026-08-19). Three reuse drawings
--             the kit already had -- emerald, coin, charm (the clover) -- and
--             three were drawn for this wheel: crown, bolt, crate. The emeralds
--             wedge went first, to stop showing a blue diamond emoji for a
--             currency that is a green stone everywhere else in the game; the
--             other five followed so the wheel is one set of pictures rather
--             than one drawing sitting among five emoji.
--             Icon below is still the fallback and must stay filled in: it is
--             what draws if UIKit.IconArt ever fails to load.
--   IconKind  an IconForge builder name. Currently UNUSED by the wheel. Those
--             builders (crown / clover / coins / crate / bolt / gem) are nicer art
--             and were wired in for two rounds, but a ViewportFrame renders at its
--             own pixel size with no anti-aliasing and 50px is not enough for a
--             multi-part 3D model -- see the long note at the icon chip in
--             WheelClient. Kept on the rows so a bigger surface (a reveal card, a
--             shop tile) can pick them up without re-deriving them.
-- Colours are deliberately saturated and high-contrast against white outlined text;
-- muted tones read as grey mush at wheel scale.
-- PAYOUTS ARE A LIST (2026-08-18). Slots used to carry one Kind/Amount pair, which
-- could not express the loot crate -- cash AND emeralds AND eggs from one wedge.
-- Every slot now carries `Grants`, an ordered list of reward rows in exactly the
-- shape SeasonPassHandler.GrantReward already understands, and WheelHandler hands
-- each row to that function. Nothing about payouts is reimplemented here: the tag's
-- already-owned fallback, the egg hatch + reveal and the boost EXTEND rule are all
-- that function's existing, tested behaviour.
WheelConfig.SLOTS = {
	-- 35%: the title. Kind="Tag" pays FallbackCash when the player already owns it,
	-- which is what makes this wedge repeatable -- otherwise every spin after the
	-- first would land on an empty prize. $1,000 is what this wedge paid before the
	-- title existed, so a repeat win is exactly the old reward.
	{ Id = "ProSpinnerTag", Weight = 35, FallbackCash = 1000, RepeatLabel = "+$1,000",
	  Grants = { { Kind = "Tag", Id = "ProWheelSpinner" } },
	  -- The wedge advertises the TITLE only. FallbackCash is what a repeat win
	  -- silently pays once you already own it -- real behaviour, but not a second
	  -- prize to promise on the face of the wheel.
	  Name = "PRO SPINNER", Value = "TITLE", Label = "PRO SPINNER TITLE", Short = "TITLE",
	  Colour = Color3.fromRGB(214, 219, 226), Text = Color3.fromRGB(52, 58, 68),
	  Art = "crown",
	  IconKind = "crown", Icon = "\u{1F451}" },

	{ Id = "LuckBoost", Weight = 15,
	  Grants = { { Kind = "Boost", Stat = "Luck", Minutes = 10 } },
	  Name = "LUCK BOOST",  Value = "+30%  10 MIN", Label = "30% LUCK",   Short = "LUCK",
	  Colour = Color3.fromRGB(64, 206, 227), Text = Color3.fromRGB(255, 255, 255),
	  OddsStyle = "gold",
	  -- the kit's four-leaf clover. It is filed under `charm` because the backpack's
	  -- charm tab asked for it first; it is the same plant, and a second drawing of
	  -- it would just be a second thing to keep in step.
	  Art = "charm",
	  IconKind = "clover", Icon = "\u{1F340}" },

	{ Id = "Cash10k",   Weight = 25,
	  Grants = { { Kind = "Cash", Amount = 10000 } },
	  Name = "BIG CASH",    Value = "+$10,000",    Label = "$10,000",    Short = "$10K",
	  Colour = Color3.fromRGB(88, 214, 62),  Text = Color3.fromRGB(255, 255, 255),
	  -- one coin, not the money bag: at chip size a bag is a brown lump, and the
	  -- kit's coin is already the game's cash mark
	  Art = "coin",
	  IconKind = "coins", Icon = "\u{1F4B0}" },

	-- 1%: the loot crate. EggSet is the one Kind WheelHandler expands itself --
	-- "one of every egg in the world this was spun in" cannot be written as fixed
	-- ids here, because the ids differ per world and the world is only known at
	-- spin time. See WheelConfig.EGG_WORLD_BY_WORLD above for the Tundra gap.
	{ Id = "LootCrate", Weight = 1,
	  Grants = {
		{ Kind = "Cash",     Amount = 2500000 },
		{ Kind = "Emeralds", Amount = 200 },
		{ Kind = "EggSet" },
	  },
	  -- THE CRATE DOES NOT LIST ITS CONTENTS. It is the 1% -- the wedge sells the
	  -- mystery, and spelling out "$2.5M + 200 emeralds + 5 eggs" both gave the game
	  -- away and needed three lines of text to do it. What is inside is still fully
	  -- defined by Grants above; it is just not printed on the wheel.
	  Name = "LOOT CRATE",  Value = "???", Label = "LOOT CRATE", Short = "CRATE",
	  Colour = Color3.fromRGB(255, 199, 26), Text = Color3.fromRGB(255, 255, 255),
	  OddsStyle = "rainbow",
	  -- Marks this wedge as the one that opens a CHEST instead of firing a toast.
	  -- Read by WheelHandler (which builds the reveal manifest only for a Crate
	  -- slot) and by WheelClient (which plays CrateCeremony only for one). It is a
	  -- flag rather than an `Id == "LootCrate"` test in two files so that a second
	  -- multi-prize wedge is a one-line change here and nothing else.
	  Crate = true,
	  Art = "crate",
	  IconKind = "crate", Icon = "\u{1F381}" },

	{ Id = "PowerBoost", Weight = 15,
	  Grants = { { Kind = "Boost", Stat = "Power", Minutes = 10 } },
	  Name = "POWER BOOST", Value = "+30%  10 MIN", Label = "30% POWER",  Short = "POWER",
	  Colour = Color3.fromRGB(240, 74, 74),  Text = Color3.fromRGB(255, 255, 255),
	  OddsStyle = "gold",
	  -- a BOLT, not the flexed arm this used to be: at 50px the arm is an
	  -- unreadable skin-coloured blob, and the bolt is the clearer "power" symbol
	  Art = "bolt",
	  IconKind = "bolt", Icon = "\u{26A1}" },

	{ Id = "Emeralds150", Weight = 9,
	  Grants = { { Kind = "Emeralds", Amount = 150 } },
	  -- "+150", not a bare "150": Short is what the physical wheel prints under the
	  -- icon, and a lone number there read as a quantity of nothing in particular.
	  Name = "GEMS",        Value = "+150",        Label = "150 GEMS",     Short = "+150", -- player-facing: the currency is Gems (2026-09-18); Kind stays the internal key
	  Colour = Color3.fromRGB(178, 96, 232), Text = Color3.fromRGB(255, 255, 255),
	  OddsStyle = "diamond",
	  Art = "emerald",
	  IconKind = "gem", Icon = "\u{1F48E}" },
}

WheelConfig.TOTAL_WEIGHT = 0
for _, s in ipairs(WheelConfig.SLOTS) do
	WheelConfig.TOTAL_WEIGHT += s.Weight
end

-- Loud on purpose: a wheel whose odds silently stop summing to 100 is the kind of bug
-- nobody notices until players do the maths for you.
assert(WheelConfig.TOTAL_WEIGHT == 100,
	("WheelConfig weights must total 100, got %d"):format(WheelConfig.TOTAL_WEIGHT))

function WheelConfig.SlotById(id)
	for i, s in ipairs(WheelConfig.SLOTS) do
		if s.Id == id then return s, i end
	end
	return nil
end

-- Weighted pick. Server-only in practice, but it lives here so the odds and the labels
-- can never drift apart.
function WheelConfig.Roll(rng)
	local r = (rng and rng:NextNumber() or math.random()) * WheelConfig.TOTAL_WEIGHT
	local cum = 0
	for i, s in ipairs(WheelConfig.SLOTS) do
		cum += s.Weight
		if r <= cum then return i, s end
	end
	return #WheelConfig.SLOTS, WheelConfig.SLOTS[#WheelConfig.SLOTS]
end

-- Compact odds, for the places with no room for "(1 in 100)": the wheel's rim
-- chips and the world plaque's 70px column. DERIVED from the weights rather than
-- typed, so a re-weighting can never make a displayed number lie -- the same rule
-- OddsText below follows, and the reason both live here instead of at the call
-- sites that used to compute their own.
function WheelConfig.OddsShort(slot)
	local pct = (slot.Weight / WheelConfig.TOTAL_WEIGHT) * 100
	if pct >= 1 then return ("%d%%"):format(pct + 0.5) end
	return ("%.2f%%"):format(pct)
end

-- "1 in 100" reads better than "1%" for the jackpot; used on the prize list.
function WheelConfig.OddsText(slot)
	if slot.Weight >= 10 then return slot.Weight .. "%" end
	return ("%g%%  (1 in %d)"):format(slot.Weight, math.floor(100 / slot.Weight + 0.5))
end

return WheelConfig
