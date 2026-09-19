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
	{ Name = "Antonio", Rarity = "Common", CashPerSecond = 0.9, Weight = 15325 },
	{ Name = "Carloo", Rarity = "Common", CashPerSecond = 0.954, Weight = 12994 },
	{ Name = "Alessio", Rarity = "Common", CashPerSecond = 1.01, Weight = 11016 },
	{ Name = "Chachechi", Rarity = "Common", CashPerSecond = 1.06, Weight = 9340 },
	{ Name = "Lerulerulerule", Rarity = "Common", CashPerSecond = 1.13, Weight = 7919 },
	{ Name = "Avocadini Guffo", Rarity = "Common", CashPerSecond = 1.19, Weight = 6714 },
	{ Name = "Avocadorilla", Rarity = "Common", CashPerSecond = 1.26, Weight = 5692 },
	{ Name = "Cacto Hipopotamo", Rarity = "Common", CashPerSecond = 1.32, Weight = 4826 },
	{ Name = "Chihuanini Taconini", Rarity = "Common", CashPerSecond = 1.4, Weight = 4091 },
	{ Name = "Gattito Tacoto", Rarity = "Common", CashPerSecond = 1.49, Weight = 3469 },
	{ Name = "Salamino Penguino", Rarity = "Common", CashPerSecond = 1.57, Weight = 2941 },
	{ Name = "Noobini Pizzanini", Rarity = "Common", CashPerSecond = 1.66, Weight = 2493 },
	{ Name = "Fluriflura", Rarity = "Common", CashPerSecond = 1.76, Weight = 2114 },
	{ Name = "Svinina Bombardino", Rarity = "Common", CashPerSecond = 1.85, Weight = 1792 },
	{ Name = "Talpa Di Fero", Rarity = "Common", CashPerSecond = 1.95, Weight = 1519 },
	{ Name = "Tim Cheese", Rarity = "Common", CashPerSecond = 2.07, Weight = 1288 },
	{ Name = "Tric Trac Baraboom", Rarity = "Common", CashPerSecond = 2.19, Weight = 1092 },
	{ Name = "Trippi Troppi", Rarity = "Common", CashPerSecond = 2.31, Weight = 926 },
	{ Name = "Dug dug dug", Rarity = "Common", CashPerSecond = 2.45, Weight = 785 },
	{ Name = "Dul Dul Dul", Rarity = "Common", CashPerSecond = 2.58, Weight = 666 },
	{ Name = "Sigma Boy", Rarity = "Common", CashPerSecond = 2.73, Weight = 564 },
	{ Name = "Sigma Girl", Rarity = "Common", CashPerSecond = 2.89, Weight = 478 },
	{ Name = "Pipi Avocado", Rarity = "Common", CashPerSecond = 3.05, Weight = 406 },
	{ Name = "Pipi Corni", Rarity = "Common", CashPerSecond = 3.22, Weight = 344 },
	{ Name = "Pipi Kiwi", Rarity = "Common", CashPerSecond = 3.41, Weight = 292 },
	{ Name = "Pipi Potato", Rarity = "Common", CashPerSecond = 3.6, Weight = 247 },
	{ Name = "Ta Ta Ta Ta Sahur", Rarity = "Common", CashPerSecond = 3.81, Weight = 210 },
	{ Name = "Te Te Te Sahur", Rarity = "Common", CashPerSecond = 4.02, Weight = 178 },
	{ Name = "Ti Ti Ti Sahur", Rarity = "Common", CashPerSecond = 4.26, Weight = 151 },
	{ Name = "To to to Sahur", Rarity = "Common", CashPerSecond = 4.5, Weight = 128 },
	-- UNCOMMON (26)
	{ Name = "Avocadini Antilopini", Rarity = "Uncommon", CashPerSecond = 5.4, Weight = 17548 },
	{ Name = "Bambini Crostini", Rarity = "Uncommon", CashPerSecond = 5.76, Weight = 14490 },
	{ Name = "Bananita Dolphinita", Rarity = "Uncommon", CashPerSecond = 6.14, Weight = 11965 },
	{ Name = "Caramello Filtrello", Rarity = "Uncommon", CashPerSecond = 6.55, Weight = 9880 },
	{ Name = "Carrotini Brainini", Rarity = "Uncommon", CashPerSecond = 6.98, Weight = 8158 },
	{ Name = "Crabbo Limonetta", Rarity = "Uncommon", CashPerSecond = 7.45, Weight = 6736 },
	{ Name = "Fragola La La La", Rarity = "Uncommon", CashPerSecond = 7.95, Weight = 5562 },
	{ Name = "Frigo Camelo", Rarity = "Uncommon", CashPerSecond = 8.48, Weight = 4593 },
	{ Name = "Gattatino Nyanino", Rarity = "Uncommon", CashPerSecond = 9, Weight = 3792 },
	{ Name = "Ketupat Kepat", Rarity = "Uncommon", CashPerSecond = 9.9, Weight = 3131 },
	{ Name = "Penguino Cocosino", Rarity = "Uncommon", CashPerSecond = 9.9, Weight = 2586 },
	{ Name = "Perochello Lemonchello", Rarity = "Uncommon", CashPerSecond = 10.8, Weight = 2135 },
	{ Name = "Pot Hotspot", Rarity = "Uncommon", CashPerSecond = 11.7, Weight = 1763 },
	{ Name = "Rhino Toasterino", Rarity = "Uncommon", CashPerSecond = 12.6, Weight = 1456 },
	{ Name = "Sammyni Spyderini", Rarity = "Uncommon", CashPerSecond = 13.5, Weight = 1202 },
	{ Name = "Spaghetti Tualetti", Rarity = "Uncommon", CashPerSecond = 14.4, Weight = 993 },
	{ Name = "Tipi Topi Taco", Rarity = "Uncommon", CashPerSecond = 15.3, Weight = 820 },
	{ Name = "Tukanno Bananno", Rarity = "Uncommon", CashPerSecond = 16.2, Weight = 677 },
	{ Name = "Orangutini Ananassini", Rarity = "Uncommon", CashPerSecond = 17.1, Weight = 559 },
	{ Name = "Pandaccini Bananini", Rarity = "Uncommon", CashPerSecond = 18, Weight = 461 },
	{ Name = "Strawberrelli Flamingelli", Rarity = "Uncommon", CashPerSecond = 19.8, Weight = 381 },
	{ Name = "Tigrilini Watermelini", Rarity = "Uncommon", CashPerSecond = 20.7, Weight = 315 },
	{ Name = "Urubini Flamenguini", Rarity = "Uncommon", CashPerSecond = 22.5, Weight = 260 },
	{ Name = "Lionel Cactuseli", Rarity = "Uncommon", CashPerSecond = 23.4, Weight = 214 },
	{ Name = "Celularcini Viciosini", Rarity = "Uncommon", CashPerSecond = 25.2, Weight = 177 },
	{ Name = "Blueberrinni Octopusini", Rarity = "Uncommon", CashPerSecond = 27, Weight = 146 },
	-- RARE (24)
	{ Name = "67", Rarity = "Rare", CashPerSecond = 31.5, Weight = 18921 },
	{ Name = "Bandito Axolito", Rarity = "Rare", CashPerSecond = 34.2, Weight = 15364 },
	{ Name = "Bandito Bobritto", Rarity = "Rare", CashPerSecond = 36, Weight = 12477 },
	{ Name = "Brr es Teh Patipum", Rarity = "Rare", CashPerSecond = 38.7, Weight = 10132 },
	{ Name = "Burbaloni Loliloli", Rarity = "Rare", CashPerSecond = 41.4, Weight = 8228 },
	{ Name = "Cacasito Satalito", Rarity = "Rare", CashPerSecond = 45, Weight = 6682 },
	{ Name = "Esok Sekolah", Rarity = "Rare", CashPerSecond = 47.7, Weight = 5426 },
	{ Name = "Espresso Signora", Rarity = "Rare", CashPerSecond = 51.3, Weight = 4407 },
	{ Name = "Ganganzelli Trulala", Rarity = "Rare", CashPerSecond = 54.9, Weight = 3579 },
	{ Name = "Gangster Footera", Rarity = "Rare", CashPerSecond = 59.4, Weight = 2906 },
	{ Name = "Job Job Job Sahur", Rarity = "Rare", CashPerSecond = 63, Weight = 2360 },
	{ Name = "Karkerkar Kurkur", Rarity = "Rare", CashPerSecond = 68.4, Weight = 1917 },
	{ Name = "La Cucaracha", Rarity = "Rare", CashPerSecond = 72.9, Weight = 1556 },
	{ Name = "Pakrahmatmamat", Rarity = "Rare", CashPerSecond = 78.3, Weight = 1264 },
	{ Name = "Piccione Macchina", Rarity = "Rare", CashPerSecond = 83.7, Weight = 1026 },
	{ Name = "Quivioli Ameleonni", Rarity = "Rare", CashPerSecond = 90, Weight = 834 },
	{ Name = "Trulimero Trulicina", Rarity = "Rare", CashPerSecond = 99, Weight = 677 },
	{ Name = "Unclito Samito", Rarity = "Rare", CashPerSecond = 108, Weight = 550 },
	{ Name = "Bisonte Giuppitere", Rarity = "Rare", CashPerSecond = 108, Weight = 446 },
	{ Name = "Dragon Cannelloni", Rarity = "Rare", CashPerSecond = 117, Weight = 363 },
	{ Name = "Torrtuginni Dragonfrutini", Rarity = "Rare", CashPerSecond = 126, Weight = 294 },
	{ Name = "Tigroligre Frutonni", Rarity = "Rare", CashPerSecond = 135, Weight = 239 },
	{ Name = "Zibra Zubra Zibralini", Rarity = "Rare", CashPerSecond = 144, Weight = 194 },
	{ Name = "Gorillo Watermelondrillo", Rarity = "Rare", CashPerSecond = 162, Weight = 158 },
	-- EPIC (22)
	{ Name = "Ballerino Lololo", Rarity = "Epic", CashPerSecond = 180, Weight = 20413 },
	{ Name = "Bombombini Gusini", Rarity = "Epic", CashPerSecond = 198, Weight = 16255 },
	{ Name = "Boneca Ambalabu", Rarity = "Epic", CashPerSecond = 207, Weight = 12942 },
	{ Name = "Cavallo Virtuoso", Rarity = "Epic", CashPerSecond = 225, Weight = 10303 },
	{ Name = "Chef Crabracadabra", Rarity = "Epic", CashPerSecond = 243, Weight = 8203 },
	{ Name = "Glorbo Fruttodrillo", Rarity = "Epic", CashPerSecond = 261, Weight = 6531 },
	{ Name = "Lirilì Larilà", Rarity = "Epic", CashPerSecond = 279, Weight = 5200 },
	{ Name = "Orcalero Orcala", Rarity = "Epic", CashPerSecond = 306, Weight = 4140 },
	{ Name = "Spioniro Golubiro", Rarity = "Epic", CashPerSecond = 324, Weight = 3296 },
	{ Name = "Strawberry Elephant", Rarity = "Epic", CashPerSecond = 351, Weight = 2624 },
	{ Name = "Brr Brr Patapim", Rarity = "Epic", CashPerSecond = 378, Weight = 2089 },
	{ Name = "Chicleteira Bicicleteira", Rarity = "Epic", CashPerSecond = 405, Weight = 1663 },
	{ Name = "Blackhole Goat", Rarity = "Epic", CashPerSecond = 441, Weight = 1324 },
	{ Name = "Brri Brri Bicus Dicus Bombicus", Rarity = "Epic", CashPerSecond = 468, Weight = 1054 },
	{ Name = "Bulbito Bandito Traktorito", Rarity = "Epic", CashPerSecond = 513, Weight = 839 },
	{ Name = "Garama and Madundung", Rarity = "Epic", CashPerSecond = 549, Weight = 668 },
	{ Name = "Ketchuru and Musturu", Rarity = "Epic", CashPerSecond = 594, Weight = 532 },
	{ Name = "Guerriro Digitale", Rarity = "Epic", CashPerSecond = 639, Weight = 423 },
	{ Name = "Nuclearo Dinossauro", Rarity = "Epic", CashPerSecond = 684, Weight = 337 },
	{ Name = "Trippi Troppi Troppa Trippa", Rarity = "Epic", CashPerSecond = 738, Weight = 268 },
	{ Name = "Tralaledon", Rarity = "Epic", CashPerSecond = 792, Weight = 213 },
	{ Name = "Trenostruzzo Turbo 3000", Rarity = "Epic", CashPerSecond = 855, Weight = 170 },
	-- LEGENDARY (20) -- income flattened 2026-08-06 for late-game grind (top ~3k, was 6k); weights unchanged
	{ Name = "Ballerina Cappuccina", Rarity = "Legendary", CashPerSecond = 990, Weight = 22295 },
	{ Name = "Cappuccino Assassino", Rarity = "Legendary", CashPerSecond = 1044, Weight = 17328 },
	{ Name = "Tralalita Tralala", Rarity = "Legendary", CashPerSecond = 1098, Weight = 13469 },
	{ Name = "Agarrini la Palini", Rarity = "Legendary", CashPerSecond = 1161, Weight = 10468 },
	{ Name = "La Karkerkar Combinasion", Rarity = "Legendary", CashPerSecond = 1224, Weight = 8138 },
	{ Name = "Las Capuchinas", Rarity = "Legendary", CashPerSecond = 1287, Weight = 6325 },
	{ Name = "Las Sis", Rarity = "Legendary", CashPerSecond = 1359, Weight = 4916 },
	{ Name = "Los Bombinitos", Rarity = "Legendary", CashPerSecond = 1431, Weight = 3821 },
	{ Name = "Los Bros", Rarity = "Legendary", CashPerSecond = 1512, Weight = 2971 },
	{ Name = "Los Chicleteiras", Rarity = "Legendary", CashPerSecond = 1593, Weight = 2307 },
	{ Name = "Los Hotspotsitos", Rarity = "Legendary", CashPerSecond = 1683, Weight = 1793 },
	{ Name = "Los Nooo My Hotspotsitos", Rarity = "Legendary", CashPerSecond = 1773, Weight = 1394 },
	{ Name = "Los Noobinis", Rarity = "Legendary", CashPerSecond = 1872, Weight = 1083 },
	{ Name = "Los Orcalitos", Rarity = "Legendary", CashPerSecond = 1971, Weight = 842 },
	{ Name = "Los Spyderinis", Rarity = "Legendary", CashPerSecond = 2079, Weight = 655 },
	{ Name = "Los Tacoritas", Rarity = "Legendary", CashPerSecond = 2187, Weight = 509 },
	{ Name = "Los Tipi Tacos", Rarity = "Legendary", CashPerSecond = 2304, Weight = 395 },
	{ Name = "Los Crocodillitos", Rarity = "Legendary", CashPerSecond = 2430, Weight = 307 },
	{ Name = "Los Matteos", Rarity = "Legendary", CashPerSecond = 2565, Weight = 238 },
	{ Name = "Los Tungtungtungcitos", Rarity = "Legendary", CashPerSecond = 2700, Weight = 185 },
	-- MYTHIC (15) -- income flattened 2026-08-06 (top ~14k, was 35k); weights unchanged
	{ Name = "Bombardiro Crocodilo", Rarity = "Mythic", CashPerSecond = 2970, Weight = 28925 },
	{ Name = "Chimpanzini Bananini", Rarity = "Mythic", CashPerSecond = 3285, Weight = 20547 },
	{ Name = "Cocofanto Elefanto", Rarity = "Mythic", CashPerSecond = 3645, Weight = 14595 },
	{ Name = "Girafa Celestre", Rarity = "Mythic", CashPerSecond = 4050, Weight = 10368 },
	{ Name = "Graipuss Medussi", Rarity = "Mythic", CashPerSecond = 4500, Weight = 7365 },
	{ Name = "Tung Tung Tung Sahur", Rarity = "Mythic", CashPerSecond = 4977, Weight = 5232 },
	{ Name = "Las Tralaleritas", Rarity = "Mythic", CashPerSecond = 5517, Weight = 3717 },
	{ Name = "La Sahur Combinasion", Rarity = "Mythic", CashPerSecond = 6120, Weight = 2640 },
	{ Name = "Tracoducotulu Delapeladustuz", Rarity = "Mythic", CashPerSecond = 6786, Weight = 1875 },
	{ Name = "Extinct Tralalero", Rarity = "Mythic", CashPerSecond = 7515, Weight = 1332 },
	{ Name = "Extinct Matteo", Rarity = "Mythic", CashPerSecond = 8334, Weight = 946 },
	{ Name = "Extinct Ballerina", Rarity = "Mythic", CashPerSecond = 9243, Weight = 672 },
	{ Name = "La Extinct Grande", Rarity = "Mythic", CashPerSecond = 10260, Weight = 477 },
	{ Name = "Mythic Lucky Block", Rarity = "Mythic", CashPerSecond = 11340, Weight = 339 },
	{ Name = "Taco Lucky Block", Rarity = "Mythic", CashPerSecond = 12600, Weight = 241 },
	-- SECRET (11) -- income flattened 2026-08-06 (top ~66k, was 200k); weights unchanged
	{ Name = "Tralalero Tralala", Rarity = "Secret", CashPerSecond = 14400, Weight = 38120 },
	{ Name = "Los Tralaleritos", Rarity = "Secret", CashPerSecond = 16560, Weight = 23618 },
	{ Name = "La Vacca Saturno Saturnita", Rarity = "Secret", CashPerSecond = 19080, Weight = 14633 },
	{ Name = "Las Vaquitas Saturnitas", Rarity = "Secret", CashPerSecond = 22050, Weight = 9066 },
	{ Name = "La Grande Combinasion", Rarity = "Secret", CashPerSecond = 25380, Weight = 5618 },
	{ Name = "Los Combinasionas", Rarity = "Secret", CashPerSecond = 29250, Weight = 3479 },
	{ Name = "Matteo", Rarity = "Secret", CashPerSecond = 33750, Weight = 2156 },
	{ Name = "Odin Din Din Dun", Rarity = "Secret", CashPerSecond = 38700, Weight = 1335 },
	{ Name = "Secret Lucky Block", Rarity = "Secret", CashPerSecond = 44730, Weight = 827 },
	{ Name = "Brainrot God Lucky Block", Rarity = "Secret", CashPerSecond = 51570, Weight = 512 },
	{ Name = "Admin Lucky Block", Rarity = "Secret", CashPerSecond = 59400, Weight = 317 },

	-- GOD (1)
	-- Pete is rolled on his OWN absolute probability, before and independently of
	-- the weighted pool, so "1 in a million" stays literally true no matter how the
	-- roster grows. His Weight is never summed. LimitedStock caps him at 5 mints ever.
	{ Name = "Secret Pete", Rarity = "God", CashPerSecond = 8999999999, Weight = 0, FixedChance = 0.000001 },
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
	--[[ ANY TIER, FLAT 1 IN 250 (2026-08-19, owner: "it seems a little impossible to
	catch"). The number was never the problem -- the GATE was.

	The previous note here spelled the trap out without fixing it: FixedChance read as
	"per MYTHIC-TIER roll", not per throw, because RarityRoll.PickInTier only rolls a
	tier's fixed entries once the walk actually reaches that tier. A player who could
	not throw Mythic distance was not on long odds, they were on ZERO -- no rock, no
	luck and no amount of patience bought them a single ticket. Loosening 0.002 ->
	0.005 in 2026-08-15 did nothing for exactly those players, which is why it still
	felt impossible after being made "easier".

	AnyTier = true takes it out of the tier walk entirely. ThrowHandler rolls it ONCE
	PER THROW, before the tier pick, at these odds -- any distance, any rock, any
	world region, whatever the throw would otherwise have landed on. 1 in 250 throws
	is now literally true rather than true-given-a-Mythic-throw.

	Rarity stays "Mythic": the reveal, the pad band, the mutation roll and the index
	all read that field, and this changes how you REACH Chim, not what it is.

	LUCK ONLY EVER HELPS. ThrowHandler multiplies these odds by the throw's access
	luck and clamps that multiplier to >= 1, so no rock, weather, pet or AFK penalty
	can push the chance below the flat floor -- see the cap note there for why the
	upside is bounded too. ]]
	--
	-- The other route is unchanged and is NOT the bottleneck: Gianluca's questline hands
	-- one over for finding the glowing SecretChim in the valley, but the hand-over that
	-- pays the cellar key CONSUMES it -- so catching one is the only way to KEEP one, and
	-- Unique = true still caps you at exactly one either way.
	--
	-- Unique = true still caps you at ONE. That cap is now enforced on the CATCH path too
	-- (ThrowHandler's reveal), which it never had to be before -- Chim is the first Unique
	-- name a throw can produce.
	--[[ RETIRED BY THE HANDOVER. RetiredBy/RetiredAt name a numeric field on the
	player's save and the value at which this entry stops being obtainable FOR THAT
	PLAYER: GianlucaQuest's data.ChimQuest reaches 3 the moment Chim is handed over
	for the cellar key, and from then on no throw can roll it again, ever.

	Per-player, and it has to be: RarityRoll's pools are cached per WORLD and shared
	by every player on the server, so a retirement that lives in there would vanish
	the Chim for everyone the moment one person finished the quest. ThrowHandler
	applies this at roll time, where the thrower's own profile is in hand.

	The fields are generic on purpose -- any future one-and-done name can retire
	against its own quest counter without another special case in ThrowHandler. ]]
	{ Name = "Chim", Rarity = "Mythic", CashPerSecond = 31500, Weight = 0, Unique = true,
	  AnyTier = true, FixedChance = 0.004, RetiredBy = "ChimQuest", RetiredAt = 3 },

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
	{ Name = "Maxwell", Rarity = "God", CashPerSecond = 1350000, Weight = 0, Unique = true, QuestOnly = true, LuckMult = 5 },

	-- QUESTLINE EXCLUSIVE: Michael the eagle's reward (see MichelQuest and
	-- MichelQuestConfig.RewardBrainrot). Same shape as Maxwell above: Weight = 0 AND
	-- QuestOnly = true, so BrainrotWaves.IsObtainable returns false, RarityRoll drops him
	-- from the pool entirely -- no throw, egg, wave or supply window can EVER produce him
	-- -- and the Index still lists him under Epic, flagged quest-only instead of catchable.
	-- The one and only source is finishing Michael's questline (five MUTATED Tung Tung Tung
	-- Sahurs), which grants him on the same hand-over that pays the emeralds.
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
	{ Name = "Pippo Olivardino", Rarity = "Epic", CashPerSecond = 900, Weight = 0, QuestOnly = true },

	-- ══ FOREST EGG EXCLUSIVES (World 1) ═══════════════════════════════════
	-- Weight = 0 IS LOAD-BEARING (same pattern as Chim/Secret Pete/Maxwell):
	-- throws can NEVER roll these. They enter the game only via EggHandler ->
	-- BrainrotMover.Give. Source tag drives the Index "FOREST EGG" badge.
	{ Name = "Cervolino Antlerino", Rarity = "Epic", CashPerSecond = 720, Weight = 171, Origin = "Forest" },
	{ Name = "Fanghetto Palunko", Rarity = "Epic", CashPerSecond = 783, Weight = 171, Origin = "Forest" },
	{ Name = "Strigolino Hootini", Rarity = "Epic", CashPerSecond = 855, Weight = 171, Origin = "Forest" },
	{ Name = "Rospino Bavaglio", Rarity = "Legendary", CashPerSecond = 2340, Weight = 187, Origin = "Forest" },
	{ Name = "Corvacchio Beccarino", Rarity = "Legendary", CashPerSecond = 2520, Weight = 187, Origin = "Forest" },
	{ Name = "Ceppone Zampalunga", Rarity = "Legendary", CashPerSecond = 2700, Weight = 187, Origin = "Forest" },
	{ Name = "Alcione Trombettone", Rarity = "Mythic", CashPerSecond = 9000, Weight = 243, Origin = "Forest" },
	{ Name = "Lucciolone Pantanini", Rarity = "Mythic", CashPerSecond = 10440, Weight = 243, Origin = "Forest" },
	{ Name = "Gufocervo Stiltini", Rarity = "Mythic", CashPerSecond = 11880, Weight = 243, Origin = "Forest" },
	{ Name = "Muschione Cornaluna", Rarity = "Secret", CashPerSecond = 20700, Weight = 319, Origin = "Forest" },
}
