-- PetConfig (Forest Egg Shop, Task 11) -- pet boosts, slots, gamepass.
--
-- ENABLED gates the bag's Pets tab (the only route to PetEquip, so also the only route
-- to a pet ever following you) and the LuckMult/IncomeMult boost seams. It is ON as of
-- 2026-07-31 -- see the note on the flag itself below. Hatching, Grant, the PetEquip
-- handler and the follow rig were never gated and ran even while it was off.
--
-- Every consumer (PetHandler.LuckMult/IncomeMult) reads ENABLED and returns a neutral 1x
-- instantly when it is false, so the ThrowHandler/IncomeLoop seams are safe to leave wired
-- live: there is no way for a disabled pet system to move a number until this flips.

local PetConfig = {}

PetConfig.ENABLED = true
-- ON since 2026-07-31 (user decision, this time deliberate -- the earlier
-- unknown-editor toggle was reverted before this).
--
-- The original reason to ship disabled is gone: all 15 pets the five forest
-- eggs can roll now have models in ReplicatedStorage.PetModels (verified, zero
-- gaps). What this unlocks, and nothing else -- everything else about pets was
-- always live:
--   * the bag's Pets tab renders owned pets instead of "Pets hatch soon!"
--     (GameHUDPanels.BackpackPanel.renderPets), which is also the ONLY path to
--     the PetEquip remote, so this is what lets a pet be equipped and follow.
--   * PetHandler.LuckMult/IncomeMult stop returning a neutral 1, so equipped
--     pets finally move throw luck and income.

-- === FOLLOW SLOTS: 3 free, 2 for cash, 3 for Robux (owner spec, 2026-08-20) ===
--
-- How many of your pets may follow you at once. NOT the same limit as how many
-- you can OWN -- that is BagConfig's pet bag (25 and up), and the two are
-- deliberately independent: a full bag never stops you re-arranging a loadout.
--
--   slots 1-3   free, every player, from the first hatch
--   slots 4-5   bought with in-game CASH, and priced to be a genuine late-game
--               goal (owner: "these should be very expensive") -- $100M and
--               $500M, against a rock ladder that tops out at $2T
--   slots 6-8   bought with ROBUX. PLACEHOLDER TODAY: every ProductId is the
--               0 sentinel, so SlotUnlock reports Live = false, PetHandler
--               refuses the purchase and the Bag draws the card as "coming
--               soon" rather than offering a sale that cannot complete.
--
-- Purchases persist as two counters on the profile, data.PetSlotsBought (cash)
-- and data.PetSlotsRobux, rather than as a set of slot numbers: they are only
-- ever bought in order, so a count is the whole truth and it cannot desync into
-- "owns slot 7 but not 6".
PetConfig.SLOTS_FREE = 3
PetConfig.SLOTS_MAX = 8
PetConfig.CASH_SLOTS = 2   -- slots 4-5
PetConfig.ROBUX_SLOTS = 3  -- slots 6-8

-- [slot number] = cash price. Keyed by the slot it opens, not by purchase index,
-- so the Bag's card can print its own price without knowing how many you own.
PetConfig.SLOT_PRICES = {
	[4] = 100000000,
	[5] = 500000000,
}

-- [slot number] = { ProductId, Robux }. ProductId == 0 is the game-wide
-- not-created-yet sentinel (same one WheelConfig.PAID_SPIN and
-- EmeraldPackConfig use).
--
-- >>> TO ACTIVATE <<<  (identical to WheelConfig.PAID_SPIN -- see its notes)
--   1. Creator Dashboard: Creations > this game > Monetization >
--      Developer Products > Create a Developer Product, one per slot.
--   2. Set each price to the Robux figure below. Roblox charges what the
--      PRODUCT says, not what this file says -- this number is only what the UI
--      DISPLAYS, so if the two disagree the button is lying about the price.
--   3. Paste each Product ID over its 0, and register them in ProductRegistry
--      so ProcessReceipt can grant the slot.
-- It MUST be a developer product, not a game pass: a pass fires no
-- ProcessReceipt and would take the Robux and grant nothing.
-- GAMEPASSES since 2026-08-19, not developer products. The block above is kept
-- for the history it explains, but the "MUST be a developer product" rule in it
-- applied to a CONSUMABLE grant routed through ProcessReceipt. A follow slot is a
-- permanent, once-per-account unlock, which is precisely what a game pass is for:
-- ownership is the record, so there is nothing to persist and nothing to replay if
-- a receipt is lost. The grant path is therefore UserOwnsGamePassAsync (cached by
-- GamepassService), never ProcessReceipt.
--
-- GamepassId == 0 would still mean "not created yet" -- SlotUnlock reports
-- Live = false and the Bag draws the card as "coming soon" rather than offering a
-- sale that cannot complete. All three are live.
PetConfig.SLOT_ROBUX = {
	-- Robux figures verified against GetProductInfo on 2026-08-19. Keys name the
	-- EXTRA slot (how the passes are listed on Roblox); the table key is the follow
	-- slot each one opens.
	[6] = { GamepassKey = "PetSlotExtra1", GamepassId = 1955658646, Robux = 200 },
	[7] = { GamepassKey = "PetSlotExtra2", GamepassId = 1955322608, Robux = 350 },
	[8] = { GamepassKey = "PetSlotExtra3", GamepassId = 1954536668, Robux = 500 },
}

-- LEGACY, and inert. The pet-slots gamepass predates the purchase model above
-- and was never configured (id 0 = no pass, so PetHandler never calls
-- UserOwnsGamePassAsync with a bogus id). Kept as a FLOOR rather than deleted:
-- if a pass is ever configured, PetHandler takes the larger of the two, so
-- turning it on can only ever give a player more slots, never fewer.
PetConfig.SLOTS_PREMIUM = 5
PetConfig.PET_SLOTS_GAMEPASS_ID = 0

-- How a given slot is unlocked. Returns a table, never nil for 1..SLOTS_MAX, so
-- the Bag can draw any card off one call:
--   { Kind = "free" }
--   { Kind = "cash",  Price = 100000000 }
--   { Kind = "robux", ProductId = 0, Robux = 199, Live = false }
function PetConfig.SlotUnlock(slot)
	slot = tonumber(slot) or 0
	if slot <= PetConfig.SLOTS_FREE then return { Kind = "free" } end
	local cash = PetConfig.SLOT_PRICES[slot]
	if cash then return { Kind = "cash", Price = cash } end
	local rb = PetConfig.SLOT_ROBUX[slot]
	if rb then
		return { Kind = "gamepass", GamepassKey = rb.GamepassKey, GamepassId = rb.GamepassId,
			Robux = rb.Robux,
			Live = type(rb.GamepassId) == "number" and rb.GamepassId > 0 }
	end
	return { Kind = "none" }
end

-- The player's REAL follow-slot cap, from their profile alone. Server-side this
-- is the number PetEquip enforces; PetHandler republishes it as the "PetSlotCap"
-- attribute because the client cannot read another player's profile (and, for
-- the legacy pass above, cannot ask MarketplaceService about ownership either).
-- Clamped at both ends so a corrupt counter can neither shrink a player below
-- the free three nor mint a ninth slot.
-- `gamepassSlots` is how many of the slot 6-8 PASSES the player owns. It is a
-- second argument rather than something read off `data` because pass ownership
-- lives with Roblox, not in the profile -- only the server can resolve it, and it
-- passes the count in (PetHandler.slotCap). Omitting it yields the profile-only
-- cap, which is exactly what any client-side caller should get.
function PetConfig.CapFor(data, gamepassSlots)
	local bought = 0
	if type(data) == "table" then
		bought = math.clamp(tonumber(data.PetSlotsBought) or 0, 0, PetConfig.CASH_SLOTS)
			+ math.clamp(tonumber(data.PetSlotsRobux) or 0, 0, PetConfig.ROBUX_SLOTS)
	end
	local passes = math.clamp(tonumber(gamepassSlots) or 0, 0, PetConfig.ROBUX_SLOTS)
	bought += passes
	local cap = PetConfig.SLOTS_FREE + bought

	-- A SLOT PASS ALWAYS OPENS A SLOT IN THE 6-8 BAND (2026-08-22).
	--
	-- Without this floor the pass count simply added to whatever the player had, so
	-- someone who bought "Pet Slot 1" from the Roblox STORE PAGE without first buying
	-- the two cash slots landed on cap 4 -- the pass silently stood in for the $100M
	-- slot, which is both cheaper than intended and not the slot the listing names.
	-- In-game that path is unreachable (the Bag only offers cap+1, and onBuyPetSlot
	-- rejects anything else), but the store page bypasses both.
	--
	-- The floor costs the cash slots as a gate for pass holders -- deliberate: the
	-- listing promises an extra slot, and a player who paid Robux for it should not
	-- have to also grind $600M before it appears. Owning N passes therefore always
	-- means at least slot 5+N, never less.
	if passes > 0 then
		cap = math.max(cap, PetConfig.SLOTS_FREE + PetConfig.CASH_SLOTS + passes)
	end
	return math.clamp(cap, PetConfig.SLOTS_FREE, PetConfig.SLOTS_MAX)
end

-- === Rarity ladder ============================================================
-- MULTIPLIERS, not bonuses: Luck = 5 means 5x. PetHandler converts these into the
-- additive amounts its boost sum works in, so the numbers here read the way the design
-- was specified rather than the way the maths happens to be stored.
--
-- DEMOTED TO FALLBACK 2026-08-06. The 15 roster pets below now carry their OWN
-- Luck/Income (see the roster loop), because each egg holds exactly THREE pets and
-- the third one has to be genuinely stronger than the first, not merely rarer.
-- Equal-within-a-tier was fine while eggs spanned tiers; with three same-tier pets
-- in an egg it made every pull mechanically identical and the "rarest" row a lie.
--
-- This table is STILL LIVE as the fallback for entries with no per-pet numbers:
-- TestAcorn and the ten retired stand-ins further down. Deleting it would turn
-- anyone holding one of those into a boost-less orphan -- see the NEVER DELETE note.
--
-- The per-pet ladder is bracketed by these bands and never crosses them
-- (Rare 1.05-1.25, Epic 1.40-1.75, Legendary 2.00-2.85, Mythic 3.20-4.45,
-- Secret 5.00), so a tier colour still tells a player roughly how strong a pet is.
PetConfig.RARITY_BOOSTS = {
	Rare      = { Luck = 1.15, Income = 1.35 },
	Epic      = { Luck = 1.50, Income = 2.00 },
	Legendary = { Luck = 2.25, Income = 3.50 },
	Mythic    = { Luck = 3.25, Income = 6.00 },
	Secret    = { Luck = 5.00, Income = 10.00 },
}

-- Display order + colours for the bag's Pets tab, rarest first.
PetConfig.RARITY_ORDER = { "Secret", "Mythic", "Legendary", "Epic", "Rare" }
PetConfig.RARITY_COLOUR = {
	Secret    = Color3.fromRGB(255, 86, 86),
	Mythic    = Color3.fromRGB(198, 142, 255),
	Legendary = Color3.fromRGB(255, 196, 62),
	Epic      = Color3.fromRGB(126, 170, 255),
	Rare      = Color3.fromRGB(120, 214, 168),
}

-- [petId] = { Name, Rarity, Model }. petId is the creature's name with spaces stripped,
-- so a pet record's Id stays stable and readable in a save file.
--
-- NEVER DELETE AN ENTRY. Owned pet records store only Uid + Id; boosts are looked up
-- from here at read time (see PetHandler.boostFor) precisely so a rebalance reaches pets
-- players already own -- but that also means a removed Id turns an owned pet into a
-- boost-less orphan. Retire by dropping it from EggConfig's roll tables instead.

-- === ABILITIES: the third axis (2026-08-22) ===================================
-- Before this, a pet was TWO numbers -- Luck and Income -- so every pet did the
-- same two things and differed only in how much. The ten retired stand-ins were
-- worse than that: they carried no per-pet numbers at all and fell through to
-- RARITY_BOOSTS, so all three Epics were byte-identical, and so were the three
-- Legendaries and the three Mythics. Owning five of one pet and three of another
-- gave you one stat line.
--
-- Every pet now also carries ONE SIGNATURE ABILITY: a named effect on a stat that
-- Luck and Income do not touch. No two pets in the game share a (Kind, Amount)
-- pair, so no two pets are mechanically identical any more.
--
-- Kind names a seam that is REALLY WIRED -- see ABILITY_KINDS below for where each
-- one lands. Amount is the BONUS (0.30 = +0.30), never the multiplier, because
-- abilities stack additively exactly the way Luck and Income already do: three
-- +0.30 pets give +0.90, not x2.20. That rule lives in StackedMult and is the
-- only place it is written down.
--
-- ADDING A PET -- the four rules, all enforced by PetConfig.Audit() at the bottom
-- of this file, which RUNS AUTOMATICALLY ON EVERY LOAD and warns to the output:
--   1. give it an Ability
--   2. whose Kind is a key of ABILITY_KINDS (a real, wired seam)
--   3. whose (Kind, Amount) pair no other pet already uses
--   4. with a Luck and an Income that no other pet already uses
-- Copy-pasting another pet's stat line therefore cannot ship quietly: the first
-- boot after the edit says exactly which two pets collide and on what.
-- Order is the order the in-game "What abilities do" list draws them in, so it
-- reads catch -> quality -> reach -> money -> event rather than alphabetically.
PetConfig.ABILITY_ORDER = { "RarityLuck", "MutationLuck", "SizeLuck", "Power", "SellBonus", "FishLuck" }
PetConfig.ABILITY_KINDS = {
	-- Label  the row heading in the Bag
	-- Blurb  four-word gist, for tight spaces
	-- Detail ONE SHORT sentence for the abilities help screen. Keep it blunt and
	--        keep it under ~60 characters: this is read by a new player deciding
	--        which pet to equip, and the first cut was long enough that the help
	--        sheet turned into a wall of text (owner, 2026-08-22). No stat names,
	--        no module names -- say what happens, not where it is wired.
	-- Seam   where it is actually applied, for whoever maintains this file
	RarityLuck   = { Label = "Rarity Luck",   Blurb = "better brainrot tiers",
		Detail = "Better chance of catching rarer brainrots.",
		Seam = "ThrowHandler.personalAccess" },
	MutationLuck = { Label = "Mutation Luck", Blurb = "better mutations",
		Detail = "Better chance your catch is mutated, like Golden or Rainbow.",
		Seam = "ThrowHandler.mutBoost" },
	SizeLuck     = { Label = "Size Luck",     Blurb = "bigger catches",
		Detail = "Better chance your catch is big. Big brainrots earn more.",
		Seam = "ThrowHandler / Sizes.Roll" },
	Power        = { Label = "Throw Power",   Blurb = "longer throws",
		Detail = "Throw the rock further. Longer throws reach rarer brainrots.",
		Seam = "ThrowHandler.distance" },
	SellBonus    = { Label = "Sell Value",    Blurb = "more cash when selling",
		Detail = "Sell brainrots and pets for more cash.",
		Seam = "SellHandler / PetHandler.Sell" },
	FishLuck     = { Label = "Fishing Luck",  Blurb = "better ice-fishing hauls",
		Detail = "Better catches while ice fishing in the Frozen Tundra.",
		Seam = "IceFishingEvent.RollCatch" },
}

PetConfig.Pets = {
	-- TEST-ONLY placeholder, kept so the command-bar probes in PetHandler's header still
	-- work. Not in any egg table, so it is unobtainable in normal play. It carries real
	-- numbers rather than falling through to RARITY_BOOSTS so that the fallback table is
	-- purely defensive -- nothing reachable depends on it.
	-- Hidden = true keeps it OFF the abilities help sheet: that screen is a
	-- shopping list ("which pet gives me this"), and a pet nobody can obtain is
	-- noise on it. It stays in Pets so the command-bar probes still resolve.
	TestAcorn = { Name = "Test Acorn", Rarity = "Epic", Hidden = true, Luck = 1.52, Income = 2.05,
		Ability = { Kind = "SizeLuck", Amount = 0.05, Name = "Test Sprout",
			Desc = "A nudge on size rolls. Test pet -- not obtainable." } },
}

-- === THE 15-PET FOREST ROSTER (2026-08-01, abilities added 2026-08-22) =======
-- Model = the child name expected in ReplicatedStorage.PetModels, which is the
-- .glb basename the art was delivered under, so importing the files and leaving
-- their names alone is enough to wire a pet up. PetHandler falls back to a
-- placeholder for any pet whose model is missing, so the roster is playable
-- before the import lands.
--
-- Tier shape is 3 Rare / 3 Epic / 4 Legendary / 4 Mythic / 1 Secret. Secret is
-- deliberately a party of ONE -- Heartwood Guardian -- because the tier is the
-- 5x luck / 10x income ceiling and three of them would stop it reading as the
-- chase. Order follows the art's own 01..15 numbering, which already ascends.
--
-- The fourth column is the pet's GAIT (see PET_GAITS below), read only by
-- PetVisualsClient. It is a property of the creature, not of the art: a frog
-- hops, a moth never touches the ground, a snail has no legs to swing. Anything
-- unset falls back to "walk", so a new pet is playable before anyone tunes it.
--
-- Columns five and six are LUCK and INCOME multipliers, PER PET (2026-08-06).
-- The roster is ordered so both ascend monotonically across all fifteen, and
-- EggConfig hands each egg a consecutive run of THREE of them -- so within any
-- egg the third pet is strictly the strongest AND the rarest, which is exactly
-- what the shop card's "RAREST" row claims. Changing an egg's membership without
-- keeping its three rows consecutive here breaks that promise; keep the two in
-- step. Secret stays pinned at the long-standing 5x luck / 10x money ceiling, so
-- nothing above it moves and the top of the economy is unchanged.
--
-- LUCK AND INCOME ARE DELIBERATELY UNCHANGED by the 2026-08-22 ability pass. The
-- ability is ADDED ON TOP of the ladder rather than carved out of it, so no pet
-- anybody already owns got weaker, and the egg-ordering promise above still holds.
-- The last three columns are the ability: KIND, AMOUNT, NAME.
for _, row in ipairs({
	--  name                  rarity       model                        gait      luck  income  ability kind    amt   ability name
	{ "Moss Larva",         "Rare",      "pet_01_mosslarva",          "crawl",   1.05,  1.18, "SizeLuck",     0.10, "Slow Bloom"      },
	{ "Pebble Snout",       "Rare",      "pet_02_pebblesnout",        "walk",    1.16,  1.35, "Power",        0.04, "Rock Nose"       },
	{ "Leaf Frog",          "Rare",      "pet_03_leaffrog",           "hop",     1.28,  1.62, "RarityLuck",   0.12, "Lucky Leap"      },
	{ "Reed Duck",          "Epic",      "pet_04_reedduck",           "waddle",  1.40,  1.95, "FishLuck",     0.25, "Riverborn"       },
	{ "Toad Pup",           "Epic",      "pet_05_toadpup",            "hop",     1.58,  2.16, "MutationLuck", 0.20, "Warty Bloom"     },
	{ "Acornel",            "Epic",      "pet_06_acornel",            "scamper", 1.76,  2.62, "SellBonus",    0.15, "Cheek Hoard"     },
	{ "Sap Snail",          "Legendary", "pet_07_sapsnail",           "glide",   2.06,  3.02, "SizeLuck",     0.30, "Amber Swell"     },
	{ "Bramble Bear",       "Legendary", "pet_08_bramblebear",        "stomp",   2.28,  3.58, "Power",        0.10, "Bramble Hurl"    },
	{ "Mossback",           "Legendary", "pet_09_mossback",           "walk",    2.56,  4.24, "SellBonus",    0.35, "Old Growth"      },
	{ "Glow Moth",          "Legendary", "pet_10_glowmoth",           "flit",    2.92,  4.85, "MutationLuck", 0.45, "Moonlit Dust"    },
	{ "Hollow Owl",         "Mythic",    "pet_11_hollow_owl",         "flit",    3.24,  5.66, "RarityLuck",   0.60, "Night Eyes"      },
	{ "Vine Coil",          "Mythic",    "pet_12_vinecoil",           "glide",   3.65,  6.55, "Power",        0.18, "Whipcrack"       },
	{ "Spirit Fawn",        "Mythic",    "pet_13_spirit_fawn",        "prance",  4.02,  7.68, "SizeLuck",     0.70, "Wildgrowth"      },
	{ "Elder Stag",         "Mythic",    "pet_14_elder_stag",         "stomp",   4.52,  8.64, "FishLuck",     1.10, "Frostcaller"     },
	{ "Heartwood Guardian", "Secret",    "pet_15_heartwood_guardian", "stomp",   5.20, 10.40, "MutationLuck", 1.50, "Heartwood Bloom" },
}) do
	local name, rarity, model, gait, luck, income, aKind, aAmt, aName =
		row[1], row[2], row[3], row[4], row[5], row[6], row[7], row[8], row[9]
	PetConfig.Pets[(name:gsub("%s+", ""))] = {
		Name = name, Rarity = rarity, Model = model, Gait = gait, Luck = luck, Income = income,
		Ability = { Kind = aKind, Amount = aAmt, Name = aName },
	}
end

-- === WORLD 2 -- THE FIFTEEN TUNDRA PETS (2026-08-23) =========================
-- Built from the owner's "Tundra pets" handoff. The models are real geometry in
-- ReplicatedStorage.PetModels (pet_t01..pet_t15), transliterated from the handoff's
-- pets.js by ServerStorage.TundraPetBuilders through ServerStorage.TundraPetKit.
--
-- RARITY: the handoff ships its own four-tier spread (5 common / 4 rare / 3 epic /
-- 3 legend). This game's PET ladder has no Common and no God -- it is
-- Rare < Epic < Legendary < Mythic < Secret -- so the handoff's spread is mapped up
-- one full step: common->Epic, rare->Legendary, epic->Mythic, legend->Secret. That
-- keeps the designer's own ordering intact AND raises the world-2 floor, which is
-- the point: the Tundra set starts where the Forest set's second tier starts.
--
-- STRENGTH: "better than the 1st world pets" is applied tier-for-tier, not just by
-- the tier shift. Every Tundra pet out-earns EVERY Forest pet of the same tier:
--   Epic       Forest 1.95-2.62  ->  Tundra 3.10-4.65
--   Legendary  Forest 3.02-4.85  ->  Tundra 6.00-8.55
--   Mythic     Forest 5.66-8.64  ->  Tundra 11.00-14.30
--   Secret     Forest 10.40      ->  Tundra 18.50-25.00
-- The ceiling lands at 2.4x world 1, which is a world step for a MULTIPLIER. Note
-- the brainrot ladder steps 17-237x between the same two worlds -- that is the right
-- number for an income SOURCE and completely the wrong one to copy here, since a
-- pet multiplies whatever the brainrots already earn.
--
-- Luck tracks income on the Forest curve's own relationship, ~1 + (income-1)*0.45.
-- Ability amounts sit roughly 2x the Forest amount for the same kind, so the ability
-- is a real upgrade too rather than a world-1 perk on a world-2 pet.
--
-- TWO NUMBERS BELOW ARE DELIBERATELY OFF THE OBVIOUS GRID. PetConfig.Audit requires
-- Luck, Income and (Ability Kind, Amount) to each be unique across EVERY pet, retired
-- ones included -- two pets sharing one would draw an identical stat row in the Bag.
-- Both of these first drafts collided with a RETIRED stand-in, and a retired pet is
-- still owned by whoever hatched it, so the Tundra side moved rather than theirs:
--   Blubberton's luck is 2.45, not 2.44    -- 2.44 is Corvacchio Beccarino's
--   Sir Chunkers' Power is 0.25, not 0.22  -- 0.22 is Alcione Trombettone's
-- Neither move disturbs its ladder: Blubberton still sits between Snowpuff (2.26) and
-- Mr. Frostbite (2.64), and Chunkers' Power still sits above every Forest Power value
-- and below Grumblehorn's 0.38. Do not "tidy" either back -- the audit warns on every
-- boot, and it warns for a reason.
for _, row in ipairs({
	--  name                     rarity       model                  gait       luck   income  ability kind    amt   ability name
	{ "Waddlebert",            "Epic",      "pet_t01_waddlebert",  "waddle",   1.95,   3.10, "FishLuck",     0.45, "Ice Skipper"     },
	{ "Frostnip",              "Epic",      "pet_t02_frostnip",    "scamper",  2.10,   3.45, "RarityLuck",   0.30, "Snow Scent"      },
	{ "Snowpuff",              "Epic",      "pet_t03_snowpuff",    "hop",      2.26,   3.80, "SizeLuck",     0.38, "Powder Puff"     },
	{ "Blubberton",            "Epic",      "pet_t04_blubberton",  "glide",    2.45,   4.20, "FishLuck",     0.50, "Belly Flop"      },
	{ "Mr. Frostbite",         "Epic",      "pet_t05_frostbite",   "hop",      2.64,   4.65, "SellBonus",    0.32, "Cold Trade"      },
	{ "Sir Chunkers",          "Legendary", "pet_t06_chunkers",    "walk",     3.25,   6.00, "Power",        0.25, "Cub Swipe"       },
	{ "Hootsicle",             "Legendary", "pet_t07_hootsicle",   "flit",     3.61,   6.80, "RarityLuck",   0.75, "Frost Sight"     },
	{ "Tuskwald",              "Legendary", "pet_t08_tuskwald",    "crawl",    3.99,   7.65, "FishLuck",     0.95, "Tusk Dredge"     },
	{ "Jinglehoof",            "Legendary", "pet_t09_jinglehoof",  "prance",   4.40,   8.55, "MutationLuck", 0.80, "Jingle Charm"    },
	{ "Grumblehorn",           "Mythic",    "pet_t10_grumblehorn", "stomp",    5.50,  11.00, "Power",        0.38, "Horn Charge"     },
	{ "Narwhalini Tuskarino",  "Mythic",    "pet_t11_narwhalini",  "glide",    6.22,  12.60, "FishLuck",     1.90, "Spiral Hunter"   },
	{ "Yetini Snowlini",       "Mythic",    "pet_t12_yetini",      "stomp",    6.99,  14.30, "SizeLuck",     1.40, "Avalanche Grip"  },
	{ "Glacio Frostalini",     "Secret",    "pet_t13_glacio",      "stomp",    8.88,  18.50, "MutationLuck", 2.40, "Aurora Core"     },
	{ "Mammothini Woolarino",  "Secret",    "pet_t14_mammothini",  "stomp",   10.25,  21.50, "SellBonus",    2.20, "Tundra Hoard"    },
	{ "Aurora Serpentini",     "Secret",    "pet_t15_aurora",      "glide",   11.80,  25.00, "RarityLuck",   3.00, "Borealis Gaze"   },
}) do
	local name, rarity, model, gait, luck, income, aKind, aAmt, aName =
		row[1], row[2], row[3], row[4], row[5], row[6], row[7], row[8], row[9]
	PetConfig.Pets[(name:gsub("%s+", ""))] = {
		Name = name, Rarity = rarity, Model = model, Gait = gait, Luck = luck, Income = income,
		World = "Tundra",
		Ability = { Kind = aKind, Amount = aAmt, Name = aName },
	}
end

-- RETIRED 2026-08-01, definitions intentionally kept: these ten were the forest
-- BRAINROTS doubling as stand-in pets before the real pet art existed. They are
-- gone from every EggConfig table, so they are no longer obtainable, but the
-- entries must stay or anyone who hatched one during testing would be holding a
-- boost-less orphan (see the NEVER DELETE note above).
--
-- THEY NOW CARRY THEIR OWN NUMBERS (2026-08-22). They used to be built by a
-- helper that set Name and Rarity ONLY, so all three Epics resolved through
-- RARITY_BOOSTS to exactly 1.50 luck / 2.00 income -- identical pets with
-- different faces, which is precisely the complaint that started this pass.
-- Each one is now placed inside its own tier's band (Epic 1.40-1.75, Legendary
-- 2.00-2.85, Mythic 3.20-4.45, Secret 5.00) so the tier colour still tells you
-- roughly how strong it is, and no value is LOWER than the tier fallback it
-- replaced -- retiring a pet must not quietly nerf someone who owns one.
--
-- Muschione Cornaluna keeps the full Secret 5.00/10.00 ceiling it already had,
-- so it is not weakened; what separates it from Heartwood Guardian now is the
-- ABILITY -- sight versus mutation -- rather than one being a copy of the other.
for _, row in ipairs({
	--  name                     rarity       luck  income  ability kind    amt   ability name
	{ "Cervolino Antlerino",   "Epic",      1.45,  1.98, "SellBonus",    0.18, "Antler Barter" },
	{ "Fanghetto Palunko",     "Epic",      1.62,  2.24, "Power",        0.12, "Mudslinger"    },
	{ "Strigolino Hootini",    "Epic",      1.71,  2.45, "RarityLuck",   0.28, "Hoot Sight"    },
	{ "Rospino Bavaglio",      "Legendary", 2.12,  3.26, "MutationLuck", 0.38, "Croakspill"    },
	{ "Corvacchio Beccarino",  "Legendary", 2.44,  3.85, "RarityLuck",   0.44, "Beak Pick"     },
	{ "Ceppone Zampalunga",    "Legendary", 2.74,  4.46, "SizeLuck",     0.50, "Longshank"     },
	{ "Alcione Trombettone",   "Mythic",    3.42,  6.08, "Power",        0.22, "Fanfare"       },
	{ "Lucciolone Pantanini",  "Mythic",    3.86,  7.05, "FishLuck",     0.85, "Marshlight"    },
	{ "Gufocervo Stiltini",    "Mythic",    4.25,  8.10, "SizeLuck",     0.90, "Stiltgrowth"   },
	{ "Muschione Cornaluna",   "Secret",    5.00, 10.00, "RarityLuck",   1.20, "Moonmoss Sight"},
}) do
	local name, rarity, luck, income, aKind, aAmt, aName =
		row[1], row[2], row[3], row[4], row[5], row[6], row[7]
	PetConfig.Pets[(name:gsub("%s+", ""))] = {
		Name = name, Rarity = rarity, Luck = luck, Income = income, Retired = true,
		Ability = { Kind = aKind, Amount = aAmt, Name = aName },
	}
end

-- Id for a creature name, so EggHandler never has to duplicate the strip-spaces rule.
function PetConfig.IdFor(creatureName)
	if typeof(creatureName) ~= "string" then return nil end
	local id = (creatureName:gsub("%s+", ""))
	return PetConfig.Pets[id] and id or nil
end

-- Multipliers for a petId, or a neutral 1x pair if the id is unknown. Callers on the hot
-- throw/income paths must never be able to turn a lookup miss into a 0.
function PetConfig.BoostsFor(petId)
	local def = PetConfig.Pets[petId]
	if not def then return 1, 1 end
	-- Per-pet numbers win (the roster above). RARITY_BOOSTS is the fallback for
	-- entries that carry none. Since 2026-08-22 every entry in this file carries
	-- its own numbers, so this branch is purely defensive -- it exists for a pet
	-- added in a hurry with only a Name and a Rarity, and for the legacy record
	-- shape handled in StackedMult. Testing both fields rather than Luck alone
	-- means a future income-only pet still resolves through here.
	if def.Luck or def.Income then
		return def.Luck or 1, def.Income or 1
	end
	local b = PetConfig.RARITY_BOOSTS[def.Rarity]
	if not b then return 1, 1 end
	return b.Luck or 1, b.Income or 1
end

-- The pet's signature ability, or nil. UI-facing: the Bag's pet detail draws its
-- name and effect line off this, so a pet with no ability simply shows no row
-- rather than showing an empty one.
function PetConfig.AbilityFor(petId)
	local def = PetConfig.Pets[petId]
	local a = def and def.Ability
	if type(a) ~= "table" or type(a.Kind) ~= "string" then return nil end
	if not PetConfig.ABILITY_KINDS[a.Kind] then return nil end
	return a
end

-- One line of readable English for an ability, used by the Bag and by any audit.
-- Returns nil for a pet with no ability so callers can skip the row entirely.
function PetConfig.AbilityText(petId)
	local a = PetConfig.AbilityFor(petId)
	if not a then return nil end
	local kind = PetConfig.ABILITY_KINDS[a.Kind]
	return ("%s  \u{2022}  +%.2f %s"):format(a.Name or kind.Label, a.Amount or 0, kind.Label)
end

-- THE ONE STAT RESOLVER. Returns the MULTIPLIER a single pet contributes for
-- `kind`, always >= 1 and never nil.
--
--   "Luck" / "Income"   the two ladder columns, from BoostsFor
--   anything in ABILITY_KINDS   the pet's signature ability, if its Kind matches
--
-- A pet contributes to an ability kind ONLY if that is its own ability's Kind, so
-- one pet moves exactly one ability seam. That is what keeps a loadout a real
-- choice: eight pets cannot cover all six abilities at full strength.
function PetConfig.StatFor(petId, kind)
	if kind == "Luck" then
		local luck = PetConfig.BoostsFor(petId)
		return luck
	elseif kind == "Income" then
		local _, income = PetConfig.BoostsFor(petId)
		return income
	end
	local a = PetConfig.AbilityFor(petId)
	if a and a.Kind == kind then
		return 1 + (tonumber(a.Amount) or 0)
	end
	return 1
end

-- The ONE definition of how equipped pets stack. Lives in ReplicatedStorage rather than
-- in PetHandler because BOTH sides need it: the server for the real multiplier, and
-- LuckHUDClient to display it. The HUD previously had no pet term at all, so the moment
-- pets went live it under-reported the player's real mutation luck by the entire pet
-- multiplier -- and a second copy of this rule on the client is exactly how the two
-- would drift apart again.
--
-- ADDITIVE on the bonus portion, not multiplicative: one 5x Secret gives 5x, two give
-- 9x, not 25x. Multiplying would make a third Secret worth more than the first two
-- combined and put luck somewhere no clamp could sensibly follow. The same rule governs
-- the ability kinds added 2026-08-22 -- three +0.30 Size pets are +0.90, not x2.20.
--
-- DUPLICATES STACK, AND THAT IS ON PURPOSE. petSlots holds UIDS, and five copies of one
-- pet are five distinct uids, so equipping all five sums five times. Verified end to end
-- 2026-08-22 (three Moss Larvas equipped at once -> 9.15x luck). The only limit on it is
-- the follow-slot cap, PetConfig.CapFor.
--
-- kind: "Luck" | "Income" | any key of ABILITY_KINDS. Unknown uids in petSlots are
-- skipped rather than treated as 1x, so an orphaned slot cannot silently dilute or
-- inflate the total.
function PetConfig.StackedMult(pets, petSlots, kind)
	if not PetConfig.ENABLED then return 1 end
	if type(pets) ~= "table" or type(petSlots) ~= "table" then return 1 end

	local byUid = {}
	for _, p in ipairs(pets) do byUid[p.Uid] = p end

	local sum = 0
	for _, uid in ipairs(petSlots) do
		local pet = byUid[uid]
		if pet then
			if kind == "Luck" or kind == "Income" then
				local luck, income = PetConfig.BoostsFor(pet.Id)
				-- Legacy single-type record (a pre-2026-08-01 Grant shape). Honoured as a
				-- fallback so a pet granted under the old shape keeps working; current
				-- records store Uid+Id only and resolve through BoostsFor above.
				if luck == 1 and income == 1 and pet.Boost and pet.Boost.Type then
					local amt = 1 + (pet.Boost.Amount or 0)
					if pet.Boost.Type == "Luck" then luck = amt else income = amt end
				end
				sum += math.max(0, ((kind == "Luck") and luck or income) - 1)
			else
				sum += math.max(0, PetConfig.StatFor(pet.Id, kind) - 1)
			end
		end
	end
	return 1 + sum
end

-- === Selling a pet ============================================================
-- Pets go IN faster than they come out -- an egg bundle is ten hatches -- so the
-- pet bag needs a drain, and selling is it (owner, 2026-08-20). Fired from the
-- Bag's pet detail column; PetHandler.Sell is the only thing that may act on it.
--
-- PRICE = a rarity base TIMES the pet's own income multiplier, which makes the
-- ladder monotone across all fifteen roster pets for free: within an egg the
-- third pet is both the rarest and the strongest, so it is also worth the most
-- to sell. Reading `income` rather than a hand-typed price per pet also means a
-- rebalance of the roster carries the sell values with it -- the same reason
-- BoostsFor resolves at read time instead of baking numbers into owned records.
--
-- Retired stand-ins and TestAcorn have no per-pet income and fall through
-- BoostsFor to RARITY_BOOSTS, so they price off their tier and still sell.
PetConfig.RARITY_SELL = {
	Rare      = 3000,
	Epic      = 10000,
	Legendary = 30000,
	Mythic    = 90000,
	Secret    = 300000,
}
-- Anything whose rarity is missing from the table above (never today; a guard
-- against a future tier landing in the roster before it lands here).
PetConfig.SELL_FALLBACK = 1000

-- Cash a single pet sells for. Always a positive integer -- the sell path pays
-- this straight into a balance, so a nil or a fraction here would be a silent
-- economy bug rather than an error.
function PetConfig.SellValue(petId)
	local def = PetConfig.Pets[petId]
	if not def then return PetConfig.SELL_FALLBACK end
	local _, income = PetConfig.BoostsFor(petId)
	local base = PetConfig.RARITY_SELL[def.Rarity] or PetConfig.SELL_FALLBACK
	return math.max(1, math.floor(base * (income or 1)))
end

-- === Follow behaviour =========================================================
-- Read by PetVisualsClient (the rig is client-side; see the header there for why).
-- The old BOB_HEIGHT/BOB_PERIOD/BOB_PHASE_STEP/SPIN_PERIOD constants are gone with
-- the server rig they drove -- a single sine on a dragged model was the whole of
-- the old "aliveness", and every one of those numbers is now a gait term below.

-- Attribute the server writes on the Player, read by every client to know what to
-- build. Pipe-separated pet Ids in slot order, "" for nothing equipped. Named here
-- so the writer and the reader can never disagree about the spelling.
PetConfig.LOADOUT_ATTR = "PetLoadout"

-- Studs on the model's largest axis after scaling. The art imports at glTF's
-- real-world metre scale (~1.2 studs on the long axis), so this is an UPscale for
-- every pet. 3.2 against a ~5-stud character reads as a companion; the old 4.0 was
-- sized for a pet that floated behind you, and looks oversized now that they stand
-- on the ground next to you.
PetConfig.PET_SIZE = 3.2

-- Where each slot walks, as a distance BACK along the path the player actually
-- walked (not a rigid offset from the player's current facing -- see the trail in
-- PetVisualsClient) and a lateral shift off it. Slots 1-2 walk abreast, 3 trails
-- them, and 4-8 continue the same alternating pattern as they are bought.
--
-- THERE MUST BE ONE ENTRY PER SLOTS_MAX (8 since 2026-08-20). PetVisualsClient
-- indexes this table by slot number and stops at #FOLLOW_SLOTS, so a table
-- shorter than the cap does not error -- it silently drops the last pets from
-- the parade, which reads as "my 7th pet does not exist" rather than as a bug
-- here. Raise SLOTS_MAX and you must add rows.
-- Back distances are spaced by more than PET_SIZE so a full eight never overlaps.
PetConfig.FOLLOW_SLOTS = {
	{ Back = 4.8,  Side = -1.8 },
	{ Back = 4.8,  Side =  1.8 },
	{ Back = 8.2,  Side =  0.0 },
	{ Back = 11.4, Side = -2.1 },
	{ Back = 11.4, Side =  2.1 },
	{ Back = 14.8, Side =  0.0 },
	{ Back = 18.0, Side = -2.4 },
	{ Back = 18.0, Side =  2.4 },
}

-- === Gaits ====================================================================
-- One entry per movement personality, keyed by the Gait column of the roster.
--   Kind    which locomotion solver runs: walk | hop | fly | slide
--   Stride  stride-length multiplier -- HIGHER means shorter, faster steps
--   Bounce  studs the body rises at the top of a step (a hop's arc height)
--   Roll    radians the body rocks side to side at full speed
--   Lean    radians the body pitches nose-down at full speed
--   Hover   studs the body floats above the ground at rest (0 = feet down)
--   Flap    wingbeats per second, for anything with a wings group
PetConfig.PET_GAITS = {
	walk    = { Kind = "walk",  Stride = 1.00, Bounce = 0.12, Roll = 0.09, Lean = 0.16, Hover = 0,    Flap = 0   },
	scamper = { Kind = "walk",  Stride = 1.55, Bounce = 0.17, Roll = 0.06, Lean = 0.22, Hover = 0,    Flap = 0   },
	prance  = { Kind = "walk",  Stride = 1.15, Bounce = 0.20, Roll = 0.05, Lean = 0.10, Hover = 0,    Flap = 0   },
	stomp   = { Kind = "walk",  Stride = 0.70, Bounce = 0.09, Roll = 0.13, Lean = 0.09, Hover = 0,    Flap = 0   },
	waddle  = { Kind = "walk",  Stride = 0.95, Bounce = 0.13, Roll = 0.26, Lean = 0.05, Hover = 0,    Flap = 1.4 },
	hop     = { Kind = "hop",   Stride = 0.70, Bounce = 0.85, Roll = 0.00, Lean = 0.24, Hover = 0,    Flap = 0   },
	crawl   = { Kind = "slide", Stride = 1.70, Bounce = 0.05, Roll = 0.03, Lean = 0.05, Hover = 0,    Flap = 0   },
	glide   = { Kind = "slide", Stride = 1.00, Bounce = 0.06, Roll = 0.05, Lean = 0.07, Hover = 0.15, Flap = 0   },
	flit    = { Kind = "fly",   Stride = 1.00, Bounce = 0.20, Roll = 0.10, Lean = 0.20, Hover = 1.7,  Flap = 7.5 },
}

function PetConfig.GaitFor(petId)
	local def = PetConfig.Pets[petId]
	return PetConfig.PET_GAITS[def and def.Gait] or PetConfig.PET_GAITS.walk
end

-- === THE NO-TWO-PETS-ALIKE AUDIT ============================================
-- THIS RUNS AUTOMATICALLY ON EVERY LOAD (see the call below) and warns to the
-- output. That is the point: a pet added later with a copy-pasted stat line is
-- caught the first time the game boots, instead of shipping as a duplicate
-- nobody notices. Call it by hand any time with:
--   print(require(game.ReplicatedStorage.Modules.PetConfig).Audit())
--
-- FOUR RULES, and a new pet has to pass all four:
--   1. it has an Ability
--   2. that Ability's Kind is a REAL seam (a key of ABILITY_KINDS) -- otherwise
--      the pet advertises a power that StatFor resolves to nothing
--   3. its (Kind, Amount) pair is not already taken by another pet
--   4. its Luck is unique, and its Income is unique, across every pet
--
-- Rule 4 is what makes each pet's numbers its own rather than a tier default.
-- It is deliberately per-COLUMN, not per-pair: two pets sharing a luck value
-- while differing on income would still show an identical LUCK row in the Bag,
-- which is exactly the thing this is here to prevent.
function PetConfig.Audit()
	local problems = {}
	local byAbility, byLuck, byIncome = {}, {}, {}
	local n = 0
	for id, def in pairs(PetConfig.Pets) do
		n += 1
		local luck, income = PetConfig.BoostsFor(id)
		local a = def.Ability
		if type(a) ~= "table" then
			table.insert(problems, id .. ": has no Ability")
		elseif not PetConfig.ABILITY_KINDS[a.Kind] then
			table.insert(problems, ("%s: Ability Kind %q is not a real seam"):format(id, tostring(a.Kind)))
		else
			local key = a.Kind .. "/" .. tostring(a.Amount)
			if byAbility[key] then
				table.insert(problems, ("%s and %s share the ability %s"):format(byAbility[key], id, key))
			end
			byAbility[key] = id
		end
		local lk = ("%.4f"):format(luck)
		if byLuck[lk] then
			table.insert(problems, ("%s and %s share a Luck of %s"):format(byLuck[lk], id, lk))
		end
		byLuck[lk] = id
		local ik = ("%.4f"):format(income)
		if byIncome[ik] then
			table.insert(problems, ("%s and %s share an Income of %s"):format(byIncome[ik], id, ik))
		end
		byIncome[ik] = id
	end
	table.sort(problems)
	if #problems == 0 then
		return ("PetConfig audit clean: %d pets, no two alike."):format(n), true
	end
	return ("PetConfig audit found %d problem(s) across %d pets:\n  %s")
		:format(#problems, n, table.concat(problems, "\n  ")), false
end

-- The automatic run. warn() rather than error(): a duplicated stat line is a
-- CONTENT bug, and refusing to load PetConfig over one would take the throw
-- path, the income loop and the whole Bag down with it. A warning in the output
-- on the very first boot after the edit is enough to catch it.
do
	local ok, message, clean = pcall(PetConfig.Audit)
	if ok and not clean then
		warn("[PetConfig] " .. tostring(message))
	end
end

return PetConfig
