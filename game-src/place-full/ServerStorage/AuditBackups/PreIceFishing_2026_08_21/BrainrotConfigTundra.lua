-- ReplicatedStorage.Modules.BrainrotConfigTundra
-- World 2 (Frozen Tundra) roster.
--
-- CROSS-OVER LADDER (2026-08-07, owner's design). World 2 is a step UP, so the valley's
-- mid-game becomes the tundra's chaff:
--
--     World 1 Epic      ->  Tundra Common
--     World 1 Legendary ->  Tundra Uncommon
--     World 1 Mythic    ->  Tundra Rare
--
-- These are the SAME creatures, carrying their World 1 CashPerSecond unchanged -- a
-- Bombardiro Crocodilo is a Bombardiro Crocodilo in either world; the tundra just treats
-- it as common. No new art is needed: every model already exists in
-- ReplicatedStorage.BrainrotModels, so icons render everywhere for free via BrainrotThumb.
--
-- World 1's SECRET and GOD tiers deliberately do NOT cross over. They stay valley-exclusive
-- so they retain their value.
--
-- DELIBERATELY EXCLUDED from the cross-over (World 1 only):
--   * Chim -- Unique + FixedChance. A one-off jackpot; a second catch route would halve
--     the rarity that makes it worth having.
--   * The 10 Origin = "Forest" brainrots. They are ordinary weighted World 1 catches now
--     (they used to carry Source = "ForestEgg" from a scrapped egg route and were, for a
--     while, obtainable by nothing at all), and the owner's call is that they stay in the
--     valley. Origin is the marker that keeps them out of here.
--
-- STILL EMPTY, BY DESIGN: Epic, Legendary, Mythic, Secret and God. Those tiers need NEW
-- brainrots. Until they exist, RarityRoll.PickInTier walks DOWN from whatever tier a throw
-- rolls to the nearest populated one, so a long throw lands a Rare rather than nothing --
-- no dead throws (that walk-down is why an empty tier is safe, but an empty WORLD is not).
--
-- WHEN ADDING THE UPPER TIERS: World 1's Mythic tops out at 35,000/s and is Tundra Rare
-- here, and World 1's Secret tops at 66,000/s. So Tundra Epic must start ABOVE 66,000/s,
-- or a mid-tier tundra catch out-earns a valley Secret and the exclusivity above is
-- worth nothing.
--
-- FORMAT: { Name, Rarity, CashPerSecond, Weight }; weights sum to exactly 100000 per tier,
-- so per-name odds are Weight / 1000 percent.
return {
	-- Common (22) -- was World 1 Epic
	{ Name = "Ballerino Lololo", Rarity = "Common", CashPerSecond = 200, Weight = 20518 },
	{ Name = "Bombombini Gusini", Rarity = "Common", CashPerSecond = 220, Weight = 16338 },
	{ Name = "Boneca Ambalabu", Rarity = "Common", CashPerSecond = 230, Weight = 13008 },
	{ Name = "Cavallo Virtuoso", Rarity = "Common", CashPerSecond = 250, Weight = 10356 },
	{ Name = "Chef Crabracadabra", Rarity = "Common", CashPerSecond = 270, Weight = 8245 },
	{ Name = "Glorbo Fruttodrillo", Rarity = "Common", CashPerSecond = 290, Weight = 6564 },
	{ Name = "Lirilì Larilà", Rarity = "Common", CashPerSecond = 310, Weight = 5226 },
	{ Name = "Orcalero Orcala", Rarity = "Common", CashPerSecond = 340, Weight = 4161 },
	{ Name = "Spioniro Golubiro", Rarity = "Common", CashPerSecond = 360, Weight = 3312 },
	{ Name = "Strawberry Elephant", Rarity = "Common", CashPerSecond = 390, Weight = 2637 },
	{ Name = "Brr Brr Patapim", Rarity = "Common", CashPerSecond = 420, Weight = 2100 },
	{ Name = "Chicleteira Bicicleteira", Rarity = "Common", CashPerSecond = 450, Weight = 1672 },
	{ Name = "Blackhole Goat", Rarity = "Common", CashPerSecond = 490, Weight = 1331 },
	{ Name = "Brri Brri Bicus Dicus Bombicus", Rarity = "Common", CashPerSecond = 520, Weight = 1060 },
	{ Name = "Bulbito Bandito Traktorito", Rarity = "Common", CashPerSecond = 570, Weight = 844 },
	{ Name = "Garama and Madundung", Rarity = "Common", CashPerSecond = 610, Weight = 672 },
	{ Name = "Ketchuru and Musturu", Rarity = "Common", CashPerSecond = 660, Weight = 535 },
	{ Name = "Guerriro Digitale", Rarity = "Common", CashPerSecond = 710, Weight = 426 },
	{ Name = "Nuclearo Dinossauro", Rarity = "Common", CashPerSecond = 760, Weight = 339 },
	{ Name = "Trippi Troppi Troppa Trippa", Rarity = "Common", CashPerSecond = 820, Weight = 270 },
	{ Name = "Tralaledon", Rarity = "Common", CashPerSecond = 880, Weight = 215 },
	{ Name = "Trenostruzzo Turbo 3000", Rarity = "Common", CashPerSecond = 950, Weight = 171 },

	-- Uncommon (20) -- was World 1 Legendary
	{ Name = "Ballerina Cappuccina", Rarity = "Uncommon", CashPerSecond = 1100, Weight = 22420 },
	{ Name = "Cappuccino Assassino", Rarity = "Uncommon", CashPerSecond = 1160, Weight = 17425 },
	{ Name = "Tralalita Tralala", Rarity = "Uncommon", CashPerSecond = 1220, Weight = 13544 },
	{ Name = "Agarrini la Palini", Rarity = "Uncommon", CashPerSecond = 1290, Weight = 10527 },
	{ Name = "La Karkerkar Combinasion", Rarity = "Uncommon", CashPerSecond = 1360, Weight = 8183 },
	{ Name = "Las Capuchinas", Rarity = "Uncommon", CashPerSecond = 1430, Weight = 6360 },
	{ Name = "Las Sis", Rarity = "Uncommon", CashPerSecond = 1510, Weight = 4943 },
	{ Name = "Los Bombinitos", Rarity = "Uncommon", CashPerSecond = 1590, Weight = 3842 },
	{ Name = "Los Bros", Rarity = "Uncommon", CashPerSecond = 1680, Weight = 2987 },
	{ Name = "Los Chicleteiras", Rarity = "Uncommon", CashPerSecond = 1770, Weight = 2321 },
	{ Name = "Los Hotspotsitos", Rarity = "Uncommon", CashPerSecond = 1870, Weight = 1804 },
	{ Name = "Los Nooo My Hotspotsitos", Rarity = "Uncommon", CashPerSecond = 1970, Weight = 1402 },
	{ Name = "Los Noobinis", Rarity = "Uncommon", CashPerSecond = 2080, Weight = 1090 },
	{ Name = "Los Orcalitos", Rarity = "Uncommon", CashPerSecond = 2190, Weight = 847 },
	{ Name = "Los Spyderinis", Rarity = "Uncommon", CashPerSecond = 2310, Weight = 659 },
	{ Name = "Los Tacoritas", Rarity = "Uncommon", CashPerSecond = 2430, Weight = 512 },
	{ Name = "Los Tipi Tacos", Rarity = "Uncommon", CashPerSecond = 2560, Weight = 398 },
	{ Name = "Los Crocodillitos", Rarity = "Uncommon", CashPerSecond = 2700, Weight = 309 },
	{ Name = "Los Matteos", Rarity = "Uncommon", CashPerSecond = 2850, Weight = 240 },
	{ Name = "Los Tungtungtungcitos", Rarity = "Uncommon", CashPerSecond = 3000, Weight = 187 },

	-- Rare (15) -- was World 1 Mythic
	{ Name = "Bombardiro Crocodilo", Rarity = "Rare", CashPerSecond = 3300, Weight = 29137 },
	{ Name = "Chimpanzini Bananini", Rarity = "Rare", CashPerSecond = 3650, Weight = 20697 },
	{ Name = "Cocofanto Elefanto", Rarity = "Rare", CashPerSecond = 4050, Weight = 14702 },
	{ Name = "Girafa Celestre", Rarity = "Rare", CashPerSecond = 4500, Weight = 10444 },
	{ Name = "Graipuss Medussi", Rarity = "Rare", CashPerSecond = 5000, Weight = 7419 },
	{ Name = "Tung Tung Tung Sahur", Rarity = "Rare", CashPerSecond = 5530, Weight = 5270 },
	{ Name = "Las Tralaleritas", Rarity = "Rare", CashPerSecond = 6130, Weight = 3744 },
	{ Name = "La Sahur Combinasion", Rarity = "Rare", CashPerSecond = 6800, Weight = 2660 },
	{ Name = "Tracoducotulu Delapeladustuz", Rarity = "Rare", CashPerSecond = 7540, Weight = 1889 },
	{ Name = "Extinct Tralalero", Rarity = "Rare", CashPerSecond = 8350, Weight = 1342 },
	{ Name = "Extinct Matteo", Rarity = "Rare", CashPerSecond = 9260, Weight = 953 },
	{ Name = "Extinct Ballerina", Rarity = "Rare", CashPerSecond = 10270, Weight = 677 },
	{ Name = "La Extinct Grande", Rarity = "Rare", CashPerSecond = 11400, Weight = 481 },
	{ Name = "Mythic Lucky Block", Rarity = "Rare", CashPerSecond = 12600, Weight = 342 },
	{ Name = "Taco Lucky Block", Rarity = "Rare", CashPerSecond = 14000, Weight = 243 },
	-- ================= UPPER TIERS -- authored World 2 content =================
	-- 30 brainrots from the owner's voxel handoff (2026-08-07), built as Parts (mesh
	-- upload is impossible from code in this place, so every model here is real Parts
	-- recovered from the OBJ voxel shells -- same pipeline as the forest brainrots).
	--
	-- CASH OPENS AT 75,000/s, deliberately ABOVE World 1's Secret ceiling of 66,000/s.
	-- World 1's Mythic tops at 35,000/s and is this world's RARE, so anything less here
	-- would let a mid-tier tundra catch out-earn a valley Secret and make the
	-- valley-exclusivity of Secret/God worthless.
	--
	-- Weights sum to exactly 100000 per tier, as everywhere else.

	-- Epic (10)
	{ Name = "Pinguino Trombettino", Rarity = "Epic", CashPerSecond = 75000, Weight = 18182 },
	{ Name = "Gelatoni Vulcanico", Rarity = "Epic", CashPerSecond = 80000, Weight = 16364 },
	{ Name = "Slittino Bombardino", Rarity = "Epic", CashPerSecond = 86000, Weight = 14545 },
	{ Name = "Morsa Baffuta", Rarity = "Epic", CashPerSecond = 92000, Weight = 12727 },
	{ Name = "Fiocco Ballerino", Rarity = "Epic", CashPerSecond = 98000, Weight = 10909 },
	{ Name = "Termosino Fumante", Rarity = "Epic", CashPerSecond = 105000, Weight = 9091 },
	{ Name = "Ghiacciolo Sbarazzino", Rarity = "Epic", CashPerSecond = 112000, Weight = 7273 },
	{ Name = "Renna Discotecca", Rarity = "Epic", CashPerSecond = 119000, Weight = 5455 },
	{ Name = "Iglu Mangione", Rarity = "Epic", CashPerSecond = 127000, Weight = 3636 },
	{ Name = "Scarpone Saltellante", Rarity = "Epic", CashPerSecond = 135000, Weight = 1818 },

	-- Legendary (8)
	{ Name = "Orso Frigorifero", Rarity = "Legendary", CashPerSecond = 150000, Weight = 22222 },
	{ Name = "Tricheco Sommozzatore", Rarity = "Legendary", CashPerSecond = 163000, Weight = 19444 },
	{ Name = "Valanga Ruggente", Rarity = "Legendary", CashPerSecond = 176000, Weight = 16667 },
	{ Name = "Yeti Cappuccino", Rarity = "Legendary", CashPerSecond = 190000, Weight = 13889 },
	{ Name = "Aurora Serpentina", Rarity = "Legendary", CashPerSecond = 205000, Weight = 11111 },
	{ Name = "Pattinatore Fantasma", Rarity = "Legendary", CashPerSecond = 221000, Weight = 8333 },
	{ Name = "Mammuto Lanoso", Rarity = "Legendary", CashPerSecond = 240000, Weight = 5556 },
	{ Name = "Nave Rompighiaccio", Rarity = "Legendary", CashPerSecond = 265000, Weight = 2778 },

	-- Mythic (6)
	{ Name = "Regina Brinata", Rarity = "Mythic", CashPerSecond = 300000, Weight = 28571 },
	{ Name = "Colosso Glaciale", Rarity = "Mythic", CashPerSecond = 335000, Weight = 23810 },
	{ Name = "Balena Polare", Rarity = "Mythic", CashPerSecond = 375000, Weight = 19048 },
	{ Name = "Cristallo Vivente", Rarity = "Mythic", CashPerSecond = 420000, Weight = 14286 },
	{ Name = "Lupo Tempesta", Rarity = "Mythic", CashPerSecond = 475000, Weight = 9524 },
	{ Name = "Trono Ghiacciato", Rarity = "Mythic", CashPerSecond = 540000, Weight = 4761 },

	-- Secret (4)
	{ Name = "Kraken Congelato", Rarity = "Secret", CashPerSecond = 650000, Weight = 40000 },
	{ Name = "Cuore della Tundra", Rarity = "Secret", CashPerSecond = 740000, Weight = 30000 },
	{ Name = "Ombra Bianca", Rarity = "Secret", CashPerSecond = 850000, Weight = 20000 },
	{ Name = "Titano Sepolto", Rarity = "Secret", CashPerSecond = 1000000, Weight = 10000 },

	-- God (2) -- a normal weighted top tier here, not a one-inhabitant jackpot
	{ Name = "Inverno Eterno", Rarity = "God", CashPerSecond = 1400000, Weight = 66667 },
	{ Name = "Zero Assoluto", Rarity = "God", CashPerSecond = 2000000, Weight = 33333 },
}
