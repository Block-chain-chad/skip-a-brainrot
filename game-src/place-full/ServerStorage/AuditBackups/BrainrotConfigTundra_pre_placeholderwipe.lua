-- ReplicatedStorage.Modules.BrainrotConfigTundra
-- World 2 (Frozen Tundra) roster -- 67 entries. Same FORMAT as BrainrotConfig:
-- { Name, Rarity, CashPerSecond, Weight } plus the optional { FixedChance }.
--
-- EVERY ENTRY IS A PLACEHOLDER, flagged Placeholder = true. Swapping in final content
-- means editing this table and adding a model of the same name to
-- ReplicatedStorage.BrainrotModels -- no gameplay code changes. Icons need nothing at
-- all: BrainrotThumb renders the model in a ViewportFrame, so a real model produces a
-- real icon everywhere (bag, index, reveal, trade) automatically.
--
-- Weights sum to exactly 100000 per tier, matching World 1's convention, so per-name
-- odds within a tier are Weight / 1000 percent.
--
-- Glitched entries carry Weight = 0 and a FixedChance instead. That is the Secret Pete
-- pattern: they are rolled independently BEFORE the weighted pool, so their odds stay
-- literally true no matter what else is added to the tier later.
--
-- CashPerSecond starts above World 1's Secret ceiling (200,000) so the Tundra reads as a
-- genuine next stage rather than an alternative to the valley.
return {
	-- COMMON (6)
	{ Name = "Glacini Orsetto", Rarity = "Common", CashPerSecond = 250000, Weight = 25862, World = "Tundra", Placeholder = true },
	{ Name = "Frostini Trichecco", Rarity = "Common", CashPerSecond = 297839, Weight = 21207, World = "Tundra", Placeholder = true },
	{ Name = "Nevito Lupetto", Rarity = "Common", CashPerSecond = 354833, Weight = 17390, World = "Tundra", Placeholder = true },
	{ Name = "Gelatini Renna", Rarity = "Common", CashPerSecond = 422733, Weight = 14260, World = "Tundra", Placeholder = true },
	{ Name = "Ventoso Foca", Rarity = "Common", CashPerSecond = 503626, Weight = 11693, World = "Tundra", Placeholder = true },
	{ Name = "Cristallo Gufetto", Rarity = "Common", CashPerSecond = 600000, Weight = 9588, World = "Tundra", Placeholder = true },
	-- UNCOMMON (6)
	{ Name = "Brinato Volpino", Rarity = "Uncommon", CashPerSecond = 700000, Weight = 25862, World = "Tundra", Placeholder = true },
	{ Name = "Polaro Alcino", Rarity = "Uncommon", CashPerSecond = 845537, Weight = 21207, World = "Tundra", Placeholder = true },
	{ Name = "Artico Narvalo", Rarity = "Uncommon", CashPerSecond = 1021334, Weight = 17390, World = "Tundra", Placeholder = true },
	{ Name = "Bufera Yetino", Rarity = "Uncommon", CashPerSecond = 1233680, Weight = 14260, World = "Tundra", Placeholder = true },
	{ Name = "Ghiaccio Mammuto", Rarity = "Uncommon", CashPerSecond = 1490176, Weight = 11693, World = "Tundra", Placeholder = true },
	{ Name = "Tormenta Stambecco", Rarity = "Uncommon", CashPerSecond = 1800000, Weight = 9588, World = "Tundra", Placeholder = true },
	-- RARE (6)
	{ Name = "Iceberghi Sahur", Rarity = "Rare", CashPerSecond = 2200000, Weight = 25862, World = "Tundra", Placeholder = true },
	{ Name = "Fiocco Tralala", Rarity = "Rare", CashPerSecond = 2688861, Weight = 21207, World = "Tundra", Placeholder = true },
	{ Name = "Valanga Bombardino", Rarity = "Rare", CashPerSecond = 3286352, Weight = 17390, World = "Tundra", Placeholder = true },
	{ Name = "Zero Crocodilo", Rarity = "Rare", CashPerSecond = 4016611, Weight = 14260, World = "Tundra", Placeholder = true },
	{ Name = "Algido Saturnita", Rarity = "Rare", CashPerSecond = 4909141, Weight = 11693, World = "Tundra", Placeholder = true },
	{ Name = "Nivoso Combinasion", Rarity = "Rare", CashPerSecond = 6000000, Weight = 9588, World = "Tundra", Placeholder = true },
	-- EPIC (6)
	{ Name = "Glacini Trichecco", Rarity = "Epic", CashPerSecond = 7500000, Weight = 25862, World = "Tundra", Placeholder = true },
	{ Name = "Frostini Lupetto", Rarity = "Epic", CashPerSecond = 9301083, Weight = 21207, World = "Tundra", Placeholder = true },
	{ Name = "Nevito Renna", Rarity = "Epic", CashPerSecond = 11534687, Weight = 17390, World = "Tundra", Placeholder = true },
	{ Name = "Gelatini Foca", Rarity = "Epic", CashPerSecond = 14304678, Weight = 14260, World = "Tundra", Placeholder = true },
	{ Name = "Ventoso Gufetto", Rarity = "Epic", CashPerSecond = 17739868, Weight = 11693, World = "Tundra", Placeholder = true },
	{ Name = "Cristallo Volpino", Rarity = "Epic", CashPerSecond = 22000000, Weight = 9588, World = "Tundra", Placeholder = true },
	-- LEGENDARY (6)
	{ Name = "Brinato Alcino", Rarity = "Legendary", CashPerSecond = 26000000, Weight = 25862, World = "Tundra", Placeholder = true },
	{ Name = "Polaro Narvalo", Rarity = "Legendary", CashPerSecond = 32553424, Weight = 21207, World = "Tundra", Placeholder = true },
	{ Name = "Artico Yetino", Rarity = "Legendary", CashPerSecond = 40758669, Weight = 17390, World = "Tundra", Placeholder = true },
	{ Name = "Bufera Mammuto", Rarity = "Legendary", CashPerSecond = 51032087, Weight = 14260, World = "Tundra", Placeholder = true },
	{ Name = "Ghiaccio Stambecco", Rarity = "Legendary", CashPerSecond = 63894968, Weight = 11693, World = "Tundra", Placeholder = true },
	{ Name = "Tormenta Sahur", Rarity = "Legendary", CashPerSecond = 80000000, Weight = 9588, World = "Tundra", Placeholder = true },
	-- MYTHIC (6)
	{ Name = "Iceberghi Tralala", Rarity = "Mythic", CashPerSecond = 95000000, Weight = 25862, World = "Tundra", Placeholder = true },
	{ Name = "Fiocco Bombardino", Rarity = "Mythic", CashPerSecond = 119564743, Weight = 21207, World = "Tundra", Placeholder = true },
	{ Name = "Valanga Crocodilo", Rarity = "Mythic", CashPerSecond = 150481345, Weight = 17390, World = "Tundra", Placeholder = true },
	{ Name = "Zero Saturnita", Rarity = "Mythic", CashPerSecond = 189392246, Weight = 14260, World = "Tundra", Placeholder = true },
	{ Name = "Algido Combinasion", Rarity = "Mythic", CashPerSecond = 238364581, Weight = 11693, World = "Tundra", Placeholder = true },
	{ Name = "Nivoso Pinguino", Rarity = "Mythic", CashPerSecond = 300000000, Weight = 9588, World = "Tundra", Placeholder = true },
	-- SECRET (6)
	{ Name = "Glacini Lupetto", Rarity = "Secret", CashPerSecond = 360000000, Weight = 25862, World = "Tundra", Placeholder = true },
	{ Name = "Frostini Renna", Rarity = "Secret", CashPerSecond = 458013469, Weight = 21207, World = "Tundra", Placeholder = true },
	{ Name = "Nevito Foca", Rarity = "Secret", CashPerSecond = 582712049, Weight = 17390, World = "Tundra", Placeholder = true },
	{ Name = "Gelatini Gufetto", Rarity = "Secret", CashPerSecond = 741361020, Weight = 14260, World = "Tundra", Placeholder = true },
	{ Name = "Ventoso Volpino", Rarity = "Secret", CashPerSecond = 943203702, Weight = 11693, World = "Tundra", Placeholder = true },
	{ Name = "Cristallo Alcino", Rarity = "Secret", CashPerSecond = 1200000000, Weight = 9588, World = "Tundra", Placeholder = true },
	-- GOD (15)
	{ Name = "Brinato Narvalo", Rarity = "God", CashPerSecond = 1500000000, Weight = 18966, World = "Tundra", Placeholder = true },
	{ Name = "Polaro Yetino", Rarity = "God", CashPerSecond = 1690517767, Weight = 15553, World = "Tundra", Placeholder = true },
	{ Name = "Artico Mammuto", Rarity = "God", CashPerSecond = 1905233548, Weight = 12753, World = "Tundra", Placeholder = true },
	{ Name = "Bufera Stambecco", Rarity = "God", CashPerSecond = 2147220776, Weight = 10458, World = "Tundra", Placeholder = true },
	{ Name = "Ghiaccio Sahur", Rarity = "God", CashPerSecond = 2419943249, Weight = 8575, World = "Tundra", Placeholder = true },
	{ Name = "Tormenta Tralala", Rarity = "God", CashPerSecond = 2727304706, Weight = 7032, World = "Tundra", Placeholder = true },
	{ Name = "Iceberghi Bombardino", Rarity = "God", CashPerSecond = 3073704708, Weight = 5766, World = "Tundra", Placeholder = true },
	{ Name = "Fiocco Crocodilo", Rarity = "God", CashPerSecond = 3464101615, Weight = 4728, World = "Tundra", Placeholder = true },
	{ Name = "Valanga Saturnita", Rarity = "God", CashPerSecond = 3904083552, Weight = 3877, World = "Tundra", Placeholder = true },
	{ Name = "Zero Combinasion", Rarity = "God", CashPerSecond = 4399948408, Weight = 3179, World = "Tundra", Placeholder = true },
	{ Name = "Algido Pinguino", Rarity = "God", CashPerSecond = 4958793973, Weight = 2607, World = "Tundra", Placeholder = true },
	{ Name = "Nivoso Orsetto", Rarity = "God", CashPerSecond = 5588619545, Weight = 2138, World = "Tundra", Placeholder = true },
	{ Name = "Glacini Renna", Rarity = "God", CashPerSecond = 6298440425, Weight = 1753, World = "Tundra", Placeholder = true },
	{ Name = "Frostini Foca", Rarity = "God", CashPerSecond = 7098416964, Weight = 1437, World = "Tundra", Placeholder = true },
	{ Name = "Nevito Gufetto", Rarity = "God", CashPerSecond = 8000000000, Weight = 1178, World = "Tundra", Placeholder = true },
	-- GLITCHED (10)
	{ Name = "Gelatini Volpino", Rarity = "Glitched", CashPerSecond = 12000000000, Weight = 0, FixedChance = 0.0016000, World = "Tundra", Placeholder = true },
	{ Name = "Ventoso Alcino", Rarity = "Glitched", CashPerSecond = 15011022479, Weight = 0, FixedChance = 0.0011520, World = "Tundra", Placeholder = true },
	{ Name = "Cristallo Narvalo", Rarity = "Glitched", CashPerSecond = 18777566322, Weight = 0, FixedChance = 0.0008294, World = "Tundra", Placeholder = true },
	{ Name = "Brinato Yetino", Rarity = "Glitched", CashPerSecond = 23489205847, Weight = 0, FixedChance = 0.0005972, World = "Tundra", Placeholder = true },
	{ Name = "Polaro Mammuto", Rarity = "Glitched", CashPerSecond = 29383083082, Weight = 0, FixedChance = 0.0004300, World = "Tundra", Placeholder = true },
	{ Name = "Artico Stambecco", Rarity = "Glitched", CashPerSecond = 36755843387, Weight = 0, FixedChance = 0.0003096, World = "Tundra", Placeholder = true },
	{ Name = "Bufera Sahur", Rarity = "Glitched", CashPerSecond = 45978565943, Weight = 0, FixedChance = 0.0002229, World = "Tundra", Placeholder = true },
	{ Name = "Ghiaccio Tralala", Rarity = "Glitched", CashPerSecond = 57515440577, Weight = 0, FixedChance = 0.0001605, World = "Tundra", Placeholder = true },
	{ Name = "Tormenta Bombardino", Rarity = "Glitched", CashPerSecond = 71947130950, Weight = 0, FixedChance = 0.0001156, World = "Tundra", Placeholder = true },
	{ Name = "Iceberghi Crocodilo", Rarity = "Glitched", CashPerSecond = 90000000000, Weight = 0, FixedChance = 0.0000832, World = "Tundra", Placeholder = true },
}
