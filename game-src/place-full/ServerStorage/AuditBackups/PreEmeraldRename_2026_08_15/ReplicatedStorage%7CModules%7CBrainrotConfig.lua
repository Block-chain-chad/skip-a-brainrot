-- ReplicatedStorage.Modules.BrainrotConfig
-- 161 authored entries. Format: { Name, Rarity, CashPerSecond, Weight }
-- plus the optional { Origin } -- provenance only, read by nothing.
-- plus the optional { FixedChance } -- see the Secret Pete note at the bottom.
--
-- OPTIONAL: VoiceId = "rbxassetid://..."
--   The creature's own voice line -- the thing that makes it a brainrot rather
--   than a coloured cube with a number. Read by PullCeremony (layered UNDER the
--   tier sound on reveal) and by BrainrotIdleClient (occasional, positional,
--   only while placed on a pad).
--   ABSENT OR EMPTY IS FULLY SUPPORTED and is the current state of all 161: a
--   nil VoiceId behaves exactly as before, no sound, no cost, no warning. Fill
--   these in per-creature; nothing else has to change when you do.
--   One id per entry, and it must be an id you have verified loads in this
--   place -- an unresolvable id costs a silent voice, never an error.
--
-- REBUILT 2026-07-25: the original 213 Italian-language roster was replaced with
-- the 148-model pack, tiered by a 5-agent pass. Old saves are carried across by
-- PlayerDataManager.RENAMES -- never delete a name from here without adding a
-- rename entry, or existing player items become unspawnable.
--
-- Weights sum to exactly 100000 per tier, so per-name odds within a tier are
-- Weight / 1000 percent. RarityRoll re-sums over OBTAINABLE names only, so the
-- live odds move with the Vault & Tide schedule -- that is intended.
return {
	-- COMMON (30)
	{ Name = "Antonio", Rarity = "Common", CashPerSecond = 1, Weight = 15325 },
	{ Name = "Carloo", Rarity = "Common", CashPerSecond = 1.06, Weight = 12994 },
	{ Name = "Alessio", Rarity = "Common", CashPerSecond = 1.12, Weight = 11016 },
	{ Name = "Chachechi", Rarity = "Common", CashPerSecond = 1.18, Weight = 9340 },
	{ Name = "Lerulerulerule", Rarity = "Common", CashPerSecond = 1.25, Weight = 7919 },
	{ Name = "Avocadini Guffo", Rarity = "Common", CashPerSecond = 1.32, Weight = 6714 },
	{ Name = "Avocadorilla", Rarity = "Common", CashPerSecond = 1.4, Weight = 5692 },
	{ Name = "Cacto Hipopotamo", Rarity = "Common", CashPerSecond = 1.47, Weight = 4826 },
	{ Name = "Chihuanini Taconini", Rarity = "Common", CashPerSecond = 1.56, Weight = 4091 },
	{ Name = "Gattito Tacoto", Rarity = "Common", CashPerSecond = 1.65, Weight = 3469 },
	{ Name = "Salamino Penguino", Rarity = "Common", CashPerSecond = 1.74, Weight = 2941 },
	{ Name = "Noobini Pizzanini", Rarity = "Common", CashPerSecond = 1.84, Weight = 2493 },
	{ Name = "Fluriflura", Rarity = "Common", CashPerSecond = 1.95, Weight = 2114 },
	{ Name = "Svinina Bombardino", Rarity = "Common", CashPerSecond = 2.06, Weight = 1792 },
	{ Name = "Talpa Di Fero", Rarity = "Common", CashPerSecond = 2.17, Weight = 1519 },
	{ Name = "Tim Cheese", Rarity = "Common", CashPerSecond = 2.3, Weight = 1288 },
	{ Name = "Tric Trac Baraboom", Rarity = "Common", CashPerSecond = 2.43, Weight = 1092 },
	{ Name = "Trippi Troppi", Rarity = "Common", CashPerSecond = 2.57, Weight = 926 },
	{ Name = "Dug dug dug", Rarity = "Common", CashPerSecond = 2.72, Weight = 785 },
	{ Name = "Dul Dul Dul", Rarity = "Common", CashPerSecond = 2.87, Weight = 666 },
	{ Name = "Sigma Boy", Rarity = "Common", CashPerSecond = 3.03, Weight = 564 },
	{ Name = "Sigma Girl", Rarity = "Common", CashPerSecond = 3.21, Weight = 478 },
	{ Name = "Pipi Avocado", Rarity = "Common", CashPerSecond = 3.39, Weight = 406 },
	{ Name = "Pipi Corni", Rarity = "Common", CashPerSecond = 3.58, Weight = 344 },
	{ Name = "Pipi Kiwi", Rarity = "Common", CashPerSecond = 3.79, Weight = 292 },
	{ Name = "Pipi Potato", Rarity = "Common", CashPerSecond = 4, Weight = 247 },
	{ Name = "Ta Ta Ta Ta Sahur", Rarity = "Common", CashPerSecond = 4.23, Weight = 210 },
	{ Name = "Te Te Te Sahur", Rarity = "Common", CashPerSecond = 4.47, Weight = 178 },
	{ Name = "Ti Ti Ti Sahur", Rarity = "Common", CashPerSecond = 4.73, Weight = 151 },
	{ Name = "To to to Sahur", Rarity = "Common", CashPerSecond = 5, Weight = 128 },
	-- UNCOMMON (26)
	{ Name = "Avocadini Antilopini", Rarity = "Uncommon", CashPerSecond = 6, Weight = 17548 },
	{ Name = "Bambini Crostini", Rarity = "Uncommon", CashPerSecond = 6.4, Weight = 14490 },
	{ Name = "Bananita Dolphinita", Rarity = "Uncommon", CashPerSecond = 6.82, Weight = 11965 },
	{ Name = "Caramello Filtrello", Rarity = "Uncommon", CashPerSecond = 7.28, Weight = 9880 },
	{ Name = "Carrotini Brainini", Rarity = "Uncommon", CashPerSecond = 7.76, Weight = 8158 },
	{ Name = "Crabbo Limonetta", Rarity = "Uncommon", CashPerSecond = 8.28, Weight = 6736 },
	{ Name = "Fragola La La La", Rarity = "Uncommon", CashPerSecond = 8.83, Weight = 5562 },
	{ Name = "Frigo Camelo", Rarity = "Uncommon", CashPerSecond = 9.42, Weight = 4593 },
	{ Name = "Gattatino Nyanino", Rarity = "Uncommon", CashPerSecond = 10, Weight = 3792 },
	{ Name = "Ketupat Kepat", Rarity = "Uncommon", CashPerSecond = 11, Weight = 3131 },
	{ Name = "Penguino Cocosino", Rarity = "Uncommon", CashPerSecond = 11, Weight = 2586 },
	{ Name = "Perochello Lemonchello", Rarity = "Uncommon", CashPerSecond = 12, Weight = 2135 },
	{ Name = "Pot Hotspot", Rarity = "Uncommon", CashPerSecond = 13, Weight = 1763 },
	{ Name = "Rhino Toasterino", Rarity = "Uncommon", CashPerSecond = 14, Weight = 1456 },
	{ Name = "Sammyni Spyderini", Rarity = "Uncommon", CashPerSecond = 15, Weight = 1202 },
	{ Name = "Spaghetti Tualetti", Rarity = "Uncommon", CashPerSecond = 16, Weight = 993 },
	{ Name = "Tipi Topi Taco", Rarity = "Uncommon", CashPerSecond = 17, Weight = 820 },
	{ Name = "Tukanno Bananno", Rarity = "Uncommon", CashPerSecond = 18, Weight = 677 },
	{ Name = "Orangutini Ananassini", Rarity = "Uncommon", CashPerSecond = 19, Weight = 559 },
	{ Name = "Pandaccini Bananini", Rarity = "Uncommon", CashPerSecond = 20, Weight = 461 },
	{ Name = "Strawberrelli Flamingelli", Rarity = "Uncommon", CashPerSecond = 22, Weight = 381 },
	{ Name = "Tigrilini Watermelini", Rarity = "Uncommon", CashPerSecond = 23, Weight = 315 },
	{ Name = "Urubini Flamenguini", Rarity = "Uncommon", CashPerSecond = 25, Weight = 260 },
	{ Name = "Lionel Cactuseli", Rarity = "Uncommon", CashPerSecond = 26, Weight = 214 },
	{ Name = "Celularcini Viciosini", Rarity = "Uncommon", CashPerSecond = 28, Weight = 177 },
	{ Name = "Blueberrinni Octopusini", Rarity = "Uncommon", CashPerSecond = 30, Weight = 146 },
	-- RARE (24)
	{ Name = "67", Rarity = "Rare", CashPerSecond = 35, Weight = 18921 },
	{ Name = "Bandito Axolito", Rarity = "Rare", CashPerSecond = 38, Weight = 15364 },
	{ Name = "Bandito Bobritto", Rarity = "Rare", CashPerSecond = 40, Weight = 12477 },
	{ Name = "Brr es Teh Patipum", Rarity = "Rare", CashPerSecond = 43, Weight = 10132 },
	{ Name = "Burbaloni Loliloli", Rarity = "Rare", CashPerSecond = 46, Weight = 8228 },
	{ Name = "Cacasito Satalito", Rarity = "Rare", CashPerSecond = 50, Weight = 6682 },
	{ Name = "Esok Sekolah", Rarity = "Rare", CashPerSecond = 53, Weight = 5426 },
	{ Name = "Espresso Signora", Rarity = "Rare", CashPerSecond = 57, Weight = 4407 },
	{ Name = "Ganganzelli Trulala", Rarity = "Rare", CashPerSecond = 61, Weight = 3579 },
	{ Name = "Gangster Footera", Rarity = "Rare", CashPerSecond = 66, Weight = 2906 },
	{ Name = "Job Job Job Sahur", Rarity = "Rare", CashPerSecond = 70, Weight = 2360 },
	{ Name = "Karkerkar Kurkur", Rarity = "Rare", CashPerSecond = 76, Weight = 1917 },
	{ Name = "La Cucaracha", Rarity = "Rare", CashPerSecond = 81, Weight = 1556 },
	{ Name = "Pakrahmatmamat", Rarity = "Rare", CashPerSecond = 87, Weight = 1264 },
	{ Name = "Piccione Macchina", Rarity = "Rare", CashPerSecond = 93, Weight = 1026 },
	{ Name = "Quivioli Ameleonni", Rarity = "Rare", CashPerSecond = 100, Weight = 834 },
	{ Name = "Trulimero Trulicina", Rarity = "Rare", CashPerSecond = 110, Weight = 677 },
	{ Name = "Unclito Samito", Rarity = "Rare", CashPerSecond = 120, Weight = 550 },
	{ Name = "Bisonte Giuppitere", Rarity = "Rare", CashPerSecond = 120, Weight = 446 },
	{ Name = "Dragon Cannelloni", Rarity = "Rare", CashPerSecond = 130, Weight = 363 },
	{ Name = "Torrtuginni Dragonfrutini", Rarity = "Rare", CashPerSecond = 140, Weight = 294 },
	{ Name = "Tigroligre Frutonni", Rarity = "Rare", CashPerSecond = 150, Weight = 239 },
	{ Name = "Zibra Zubra Zibralini", Rarity = "Rare", CashPerSecond = 160, Weight = 194 },
	{ Name = "Gorillo Watermelondrillo", Rarity = "Rare", CashPerSecond = 180, Weight = 158 },
	-- EPIC (22)
	{ Name = "Ballerino Lololo", Rarity = "Epic", CashPerSecond = 200, Weight = 20413 },
	{ Name = "Bombombini Gusini", Rarity = "Epic", CashPerSecond = 220, Weight = 16255 },
	{ Name = "Boneca Ambalabu", Rarity = "Epic", CashPerSecond = 230, Weight = 12942 },
	{ Name = "Cavallo Virtuoso", Rarity = "Epic", CashPerSecond = 250, Weight = 10303 },
	{ Name = "Chef Crabracadabra", Rarity = "Epic", CashPerSecond = 270, Weight = 8203 },
	{ Name = "Glorbo Fruttodrillo", Rarity = "Epic", CashPerSecond = 290, Weight = 6531 },
	{ Name = "Lirilì Larilà", Rarity = "Epic", CashPerSecond = 310, Weight = 5200 },
	{ Name = "Orcalero Orcala", Rarity = "Epic", CashPerSecond = 340, Weight = 4140 },
	{ Name = "Spioniro Golubiro", Rarity = "Epic", CashPerSecond = 360, Weight = 3296 },
	{ Name = "Strawberry Elephant", Rarity = "Epic", CashPerSecond = 390, Weight = 2624 },
	{ Name = "Brr Brr Patapim", Rarity = "Epic", CashPerSecond = 420, Weight = 2089 },
	{ Name = "Chicleteira Bicicleteira", Rarity = "Epic", CashPerSecond = 450, Weight = 1663 },
	{ Name = "Blackhole Goat", Rarity = "Epic", CashPerSecond = 490, Weight = 1324 },
	{ Name = "Brri Brri Bicus Dicus Bombicus", Rarity = "Epic", CashPerSecond = 520, Weight = 1054 },
	{ Name = "Bulbito Bandito Traktorito", Rarity = "Epic", CashPerSecond = 570, Weight = 839 },
	{ Name = "Garama and Madundung", Rarity = "Epic", CashPerSecond = 610, Weight = 668 },
	{ Name = "Ketchuru and Musturu", Rarity = "Epic", CashPerSecond = 660, Weight = 532 },
	{ Name = "Guerriro Digitale", Rarity = "Epic", CashPerSecond = 710, Weight = 423 },
	{ Name = "Nuclearo Dinossauro", Rarity = "Epic", CashPerSecond = 760, Weight = 337 },
	{ Name = "Trippi Troppi Troppa Trippa", Rarity = "Epic", CashPerSecond = 820, Weight = 268 },
	{ Name = "Tralaledon", Rarity = "Epic", CashPerSecond = 880, Weight = 213 },
	{ Name = "Trenostruzzo Turbo 3000", Rarity = "Epic", CashPerSecond = 950, Weight = 170 },
	-- LEGENDARY (20) -- income flattened 2026-08-06 for late-game grind (top ~3k, was 6k); weights unchanged
	{ Name = "Ballerina Cappuccina", Rarity = "Legendary", CashPerSecond = 1100, Weight = 22295 },
	{ Name = "Cappuccino Assassino", Rarity = "Legendary", CashPerSecond = 1160, Weight = 17328 },
	{ Name = "Tralalita Tralala", Rarity = "Legendary", CashPerSecond = 1220, Weight = 13469 },
	{ Name = "Agarrini la Palini", Rarity = "Legendary", CashPerSecond = 1290, Weight = 10468 },
	{ Name = "La Karkerkar Combinasion", Rarity = "Legendary", CashPerSecond = 1360, Weight = 8138 },
	{ Name = "Las Capuchinas", Rarity = "Legendary", CashPerSecond = 1430, Weight = 6325 },
	{ Name = "Las Sis", Rarity = "Legendary", CashPerSecond = 1510, Weight = 4916 },
	{ Name = "Los Bombinitos", Rarity = "Legendary", CashPerSecond = 1590, Weight = 3821 },
	{ Name = "Los Bros", Rarity = "Legendary", CashPerSecond = 1680, Weight = 2971 },
	{ Name = "Los Chicleteiras", Rarity = "Legendary", CashPerSecond = 1770, Weight = 2307 },
	{ Name = "Los Hotspotsitos", Rarity = "Legendary", CashPerSecond = 1870, Weight = 1793 },
	{ Name = "Los Nooo My Hotspotsitos", Rarity = "Legendary", CashPerSecond = 1970, Weight = 1394 },
	{ Name = "Los Noobinis", Rarity = "Legendary", CashPerSecond = 2080, Weight = 1083 },
	{ Name = "Los Orcalitos", Rarity = "Legendary", CashPerSecond = 2190, Weight = 842 },
	{ Name = "Los Spyderinis", Rarity = "Legendary", CashPerSecond = 2310, Weight = 655 },
	{ Name = "Los Tacoritas", Rarity = "Legendary", CashPerSecond = 2430, Weight = 509 },
	{ Name = "Los Tipi Tacos", Rarity = "Legendary", CashPerSecond = 2560, Weight = 395 },
	{ Name = "Los Crocodillitos", Rarity = "Legendary", CashPerSecond = 2700, Weight = 307 },
	{ Name = "Los Matteos", Rarity = "Legendary", CashPerSecond = 2850, Weight = 238 },
	{ Name = "Los Tungtungtungcitos", Rarity = "Legendary", CashPerSecond = 3000, Weight = 185 },
	-- MYTHIC (15) -- income flattened 2026-08-06 (top ~14k, was 35k); weights unchanged
	{ Name = "Bombardiro Crocodilo", Rarity = "Mythic", CashPerSecond = 3300, Weight = 28925 },
	{ Name = "Chimpanzini Bananini", Rarity = "Mythic", CashPerSecond = 3650, Weight = 20547 },
	{ Name = "Cocofanto Elefanto", Rarity = "Mythic", CashPerSecond = 4050, Weight = 14595 },
	{ Name = "Girafa Celestre", Rarity = "Mythic", CashPerSecond = 4500, Weight = 10368 },
	{ Name = "Graipuss Medussi", Rarity = "Mythic", CashPerSecond = 5000, Weight = 7365 },
	{ Name = "Tung Tung Tung Sahur", Rarity = "Mythic", CashPerSecond = 5530, Weight = 5232 },
	{ Name = "Las Tralaleritas", Rarity = "Mythic", CashPerSecond = 6130, Weight = 3717 },
	{ Name = "La Sahur Combinasion", Rarity = "Mythic", CashPerSecond = 6800, Weight = 2640 },
	{ Name = "Tracoducotulu Delapeladustuz", Rarity = "Mythic", CashPerSecond = 7540, Weight = 1875 },
	{ Name = "Extinct Tralalero", Rarity = "Mythic", CashPerSecond = 8350, Weight = 1332 },
	{ Name = "Extinct Matteo", Rarity = "Mythic", CashPerSecond = 9260, Weight = 946 },
	{ Name = "Extinct Ballerina", Rarity = "Mythic", CashPerSecond = 10270, Weight = 672 },
	{ Name = "La Extinct Grande", Rarity = "Mythic", CashPerSecond = 11400, Weight = 477 },
	{ Name = "Mythic Lucky Block", Rarity = "Mythic", CashPerSecond = 12600, Weight = 339 },
	{ Name = "Taco Lucky Block", Rarity = "Mythic", CashPerSecond = 14000, Weight = 241 },
	-- SECRET (11) -- income flattened 2026-08-06 (top ~66k, was 200k); weights unchanged
	{ Name = "Tralalero Tralala", Rarity = "Secret", CashPerSecond = 16000, Weight = 38120 },
	{ Name = "Los Tralaleritos", Rarity = "Secret", CashPerSecond = 18400, Weight = 23618 },
	{ Name = "La Vacca Saturno Saturnita", Rarity = "Secret", CashPerSecond = 21200, Weight = 14633 },
	{ Name = "Las Vaquitas Saturnitas", Rarity = "Secret", CashPerSecond = 24500, Weight = 9066 },
	{ Name = "La Grande Combinasion", Rarity = "Secret", CashPerSecond = 28200, Weight = 5618 },
	{ Name = "Los Combinasionas", Rarity = "Secret", CashPerSecond = 32500, Weight = 3479 },
	{ Name = "Matteo", Rarity = "Secret", CashPerSecond = 37500, Weight = 2156 },
	{ Name = "Odin Din Din Dun", Rarity = "Secret", CashPerSecond = 43000, Weight = 1335 },
	{ Name = "Secret Lucky Block", Rarity = "Secret", CashPerSecond = 49700, Weight = 827 },
	{ Name = "Brainrot God Lucky Block", Rarity = "Secret", CashPerSecond = 57300, Weight = 512 },
	{ Name = "Admin Lucky Block", Rarity = "Secret", CashPerSecond = 66000, Weight = 317 },

	-- GOD (1)
	-- Pete is rolled on his OWN absolute probability, before and independently of
	-- the weighted pool, so "1 in a million" stays literally true no matter how the
	-- roster grows. His Weight is never summed. LimitedStock caps him at 5 mints ever.
	{ Name = "Secret Pete", Rarity = "God", CashPerSecond = 9999999999, Weight = 0, FixedChance = 0.000001 },
	-- QUESTLINE EXCLUSIVE: Gianluca's Secret Chim. Kept down here next to Pete so the
	-- two special-cased entries sit together, but its Rarity IS "Mythic" -- RarityRoll
	-- groups by the Rarity field, never by position in this file.
	--
	-- Weight = 0 IS LOAD-BEARING. DO NOT "FIX" IT. It keeps Chim out of the weighted
	-- pool entirely, which is what delivers two separate requirements:
	--   1. No throw can EVER drop Chim, at any distance or luck. The only source is
	--      GianlucaQuest, which refuses to grant unless the player has already accepted
	--      the quest (data.ChimQuest == 1). That gate is the whole point.
	--   2. Mythic's odds stay untouched. This file authors 100000 total weight per tier,
	--      so any real weight here would hand Chim a share of every Mythic catch.
	--
	-- Historical warning: this was once changed to 100000 on the mistaken belief that a
	-- zero-weight God tier was a bug. It is not. God is Pete-only by design, and Pete is
	-- FixedChance -- rolled independently BEFORE the weighted pool -- so God having no
	-- weighted entries is correct and intended.
	--
	-- cps was 1000000 while it sat in the God tier. At Mythic that was 28x the top of
	-- the band and ~1.5x the entire 12-pad Secret income from a single pad, which made
	-- REFUSING the handover strictly better than taking the Key. 35000 pins Chim to the
	-- top of Mythic -- still the strongest brainrot in its tier, fitting for a
	-- one-of-a-kind quest item, but inside the band so it cannot distort the economy.
	-- Side effect worth knowing: sell value is cps * 40, so Chim is worth 1.4M if sold
	-- instead of handed over (was 40M). The Key is now the better prize, as intended.
	-- Uses the fallback neon cube visual (no model in ServerStorage.BrainrotModels).
	-- Unique = true caps you at ONE, ever, across every route in: the quest grant, a
	-- trade, and a booth purchase all refuse to give you a second. Enforced in
	-- BrainrotMover.WithinUniqueCap and checked PRE-FLIGHT by each caller -- see the
	-- note on BrainrotMover.Give for why it cannot be enforced inside Give itself.
	-- Fusion needs 5 identical copies, so a cap of 1 makes a Golden Chim unreachable
	-- by construction rather than by a special case.
	-- NO LONGER QuestOnly. Chim can now also be CAUGHT by skipping: FixedChance rolls it
	-- independently before the Mythic weighted pool, so it is a rare find on a genuine
	-- Mythic-distance throw and its odds cannot be diluted by future roster changes.
	-- Weight stays 0 -- FixedChance entries never touch the pool.
	--
	-- LOOSENED 2026-08-15 (owner: "the secret chim is super hard to get"): 0.002 -> 0.005,
	-- i.e. 1 in 500 -> 1 in 200. FixedChance is the tuning knob and this is the only line
	-- to change. Read it as "per MYTHIC-TIER roll", not per throw: RarityRoll.PickInTier
	-- calls rollFixed only for the tier the throw actually landed on, so a player who
	-- cannot reach Mythic distance never gets a ticket at all -- which is why the number
	-- feels far rarer in play than 1-in-200 sounds.
	--
	-- The other route is unchanged and is NOT the bottleneck: Gianluca's questline hands
	-- one over for finding the glowing SecretChim in the valley, but the hand-over that
	-- pays the cellar key CONSUMES it -- so catching one is the only way to KEEP one, and
	-- Unique = true still caps you at exactly one either way.
	--
	-- Unique = true still caps you at ONE. That cap is now enforced on the CATCH path too
	-- (ThrowHandler's reveal), which it never had to be before -- Chim is the first Unique
	-- name a throw can produce.
	{ Name = "Chim", Rarity = "Mythic", CashPerSecond = 35000, Weight = 0, Unique = true, FixedChance = 0.005 },

	-- QUESTLINE EXCLUSIVE: Maxwell the cat's reward (see MaxwellQuest). Weight = 0 AND
	-- QuestOnly = true -- BrainrotWaves.IsObtainable returns false for QuestOnly items,
	-- so Maxwell is dropped from the roll pool ENTIRELY (no throw can ever produce it)
	-- and the Index shows it as not-catchable. The ONLY source is completing Maxwell's
	-- questline (collect every Secret in the index, then reach Rebirth 25).
	-- Rarity is "God": Pete is FixedChance and rolled independently, so God's
	-- weighted total stays 0 and PickInTier still falls through it exactly as before.
	-- No model yet -- falls back to the neon-cube visual, like Chim. Unique = true
	-- caps you at one, ever (BrainrotMover.WithinUniqueCap, checked pre-flight).
	-- cps is tunable. LuckMult buffs your throw (rarity) luck WHILE THIS PET IS PLACED
	-- on your base -- read identically by ThrowHandler (real rolls) and LuckHUDClient
	-- (the displayed luck). Unique, so exactly one copy => x5.
	{ Name = "Maxwell", Rarity = "God", CashPerSecond = 1500000, Weight = 0, Unique = true, QuestOnly = true, LuckMult = 5 },

	-- QUESTLINE EXCLUSIVE: Michael the eagle's reward (see MichelQuest and
	-- MichelQuestConfig.RewardBrainrot). Same shape as Maxwell above: Weight = 0 AND
	-- QuestOnly = true, so BrainrotWaves.IsObtainable returns false, RarityRoll drops him
	-- from the pool entirely -- no throw, egg, wave or supply window can EVER produce him
	-- -- and the Index still lists him under Epic, flagged quest-only instead of catchable.
	-- The one and only source is finishing Michael's questline (five MUTATED Tung Tung Tung
	-- Sahurs), which grants him on the same hand-over that pays the darrels.
	--
	-- cps 1000 sits deliberately in the GAP between the top of the weighted Epic band
	-- (Trenostruzzo Turbo 3000 at 950) and the bottom of Legendary (1100): the best Epic in
	-- the game, which is what a questline reward should be, without reaching into the tier
	-- above and distorting the ladder -- the same reasoning as the Chim note above.
	--
	-- NOT Unique, deliberately, unlike Chim and Maxwell: the quest is the only way to MINT
	-- one, but he stays freely tradeable. Add Unique = true here AND a pre-flight
	-- WithinUniqueCap check in MichelQuest if that should ever change (Give is total and
	-- cannot refuse -- see the note on BrainrotMover.Give).
	{ Name = "Pippo Olivardino", Rarity = "Epic", CashPerSecond = 1000, Weight = 0, QuestOnly = true },

	-- ══ FOREST EGG EXCLUSIVES (World 1) ═══════════════════════════════════
	-- Weight = 0 IS LOAD-BEARING (same pattern as Chim/Secret Pete/Maxwell):
	-- throws can NEVER roll these. They enter the game only via EggHandler ->
	-- BrainrotMover.Give. Source tag drives the Index "FOREST EGG" badge.
	{ Name = "Cervolino Antlerino", Rarity = "Epic", CashPerSecond = 800, Weight = 171, Origin = "Forest" },
	{ Name = "Fanghetto Palunko", Rarity = "Epic", CashPerSecond = 870, Weight = 171, Origin = "Forest" },
	{ Name = "Strigolino Hootini", Rarity = "Epic", CashPerSecond = 950, Weight = 171, Origin = "Forest" },
	{ Name = "Rospino Bavaglio", Rarity = "Legendary", CashPerSecond = 2600, Weight = 187, Origin = "Forest" },
	{ Name = "Corvacchio Beccarino", Rarity = "Legendary", CashPerSecond = 2800, Weight = 187, Origin = "Forest" },
	{ Name = "Ceppone Zampalunga", Rarity = "Legendary", CashPerSecond = 3000, Weight = 187, Origin = "Forest" },
	{ Name = "Alcione Trombettone", Rarity = "Mythic", CashPerSecond = 10000, Weight = 243, Origin = "Forest" },
	{ Name = "Lucciolone Pantanini", Rarity = "Mythic", CashPerSecond = 11600, Weight = 243, Origin = "Forest" },
	{ Name = "Gufocervo Stiltini", Rarity = "Mythic", CashPerSecond = 13200, Weight = 243, Origin = "Forest" },
	{ Name = "Muschione Cornaluna", Rarity = "Secret", CashPerSecond = 23000, Weight = 319, Origin = "Forest" },
}
