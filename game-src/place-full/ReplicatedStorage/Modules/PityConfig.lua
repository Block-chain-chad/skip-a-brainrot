-- PityConfig: dry-streak protection for the top tiers. Each throw that REACHES a tier's
-- distance without catching it (or higher) ticks that tier's counter up; once the counter
-- passes Threshold, every further reaching throw gets a big boosted -- never guaranteed --
-- Chance to bump the roll up to that tier. Counters reset when you catch the tier or higher
-- (ThrowHandler.revealCatch). Only the HIGHEST eligible tier fires per throw.
--
-- Ordered low -> high. Tunable: raise Chance for a stronger safety net, raise Threshold to
-- make players wait longer.
return {
	{ Tier = "Legendary", Threshold = 50,  Chance = 0.35 },
	{ Tier = "Mythic",    Threshold = 150, Chance = 0.30 },
	{ Tier = "Secret",    Threshold = 500, Chance = 0.25 },
}
