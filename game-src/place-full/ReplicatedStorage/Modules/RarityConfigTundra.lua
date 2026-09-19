-- ReplicatedStorage.Modules.RarityConfigTundra
-- World 2 (Frozen Tundra) rarity ladder. Same FORMAT as RarityConfig, and read through
-- WorldProgression rather than being required directly by gameplay code.
--
-- SHAPE MATTERS. Tiers with a finite MaxDistance form the probability curve; a tier with
-- MaxDistance == math.huge would be an APEX, deliberately outside the curve and reached
-- only through its entries' FixedChance. RarityCurve derives TopTier / ApexIndex from
-- exactly that property. World 1 uses it for Secret Pete.
--
-- WORLD 2 HAS NO APEX TIER. The ladder ends at God, and God is a normal top-of-curve tier
-- with a real weighted roster (Inverno Eterno, Zero Assoluto) rather than a
-- one-inhabitant jackpot. Every tier here has a finite MaxDistance, so RarityCurve sets
-- TopTier = 8 and ApexIndex = 9 -- one past the end -- and ThrowHandler's top-of-curve
-- routing calls PickInTier(9). That is SAFE and deliberate: PickInTier clamps the index to
-- the ladder length and then walks DOWN to the nearest populated tier, so the roll lands on
-- God. The clamp is load-bearing -- it is what makes "no apex" a valid shape here instead
-- of a nil catch.
--
-- A NINTH TIER NAMED "Glitched" WAS REMOVED HERE on 2026-08-07. It was placeholder-era,
-- and it collided with MutationConfig's Glitched, which is a MUTATION (terminal fusion,
-- x50) -- two different things sharing one name across SoundKit, MutationFX,
-- RareCatchClient and FusionHandler. World 2's ladder runs Common..God, matching World 1's
-- tier names exactly.
--
-- ============================ BANDS: WHY THESE NUMBERS ============================
-- Throws clamp at ThrowHandler's MAX_TOTAL_DISTANCE = 900, so the whole ladder has to fit
-- inside 0..900 or the top of it is unreachable.
--
-- These eight bands were re-spread on 2026-08-07 when the upper tiers were authored. They
-- had briefly been in a stopgap shape (three live tiers stretched over 0-300-600-900, the
-- other five PARKED at MinDistance 9000 so they could not be rolled while empty) -- that
-- existed only because an empty tier makes PickInTier walk back DOWN, which had made a
-- 200-stud throw and a 900-stud throw give identical results. All eight tiers are populated
-- now, so the ladder is a real ladder again and distance means something at every step.
--
-- Bands are slightly tighter than World 1's (which runs 0/100/220/360/500/640/780/900),
-- because World 2 is the later stage: the same throw reaches one tier higher here.
return {
	{ Name = "Common",    MinDistance = 0,   MaxDistance = 110, Color = Color3.fromRGB(176, 192, 208) },
	{ Name = "Uncommon",  MinDistance = 110, MaxDistance = 220, Color = Color3.fromRGB(96, 208, 176) },
	{ Name = "Rare",      MinDistance = 220, MaxDistance = 340, Color = Color3.fromRGB(70, 150, 250) },
	{ Name = "Epic",      MinDistance = 340, MaxDistance = 460, Color = Color3.fromRGB(168, 88, 246) },
	{ Name = "Legendary", MinDistance = 460, MaxDistance = 580, Color = Color3.fromRGB(255, 164, 52) },
	{ Name = "Mythic",    MinDistance = 580, MaxDistance = 700, Color = Color3.fromRGB(255, 72, 82) },
	{ Name = "Secret",    MinDistance = 700, MaxDistance = 820, Color = Color3.fromRGB(255, 104, 226) },
	-- Top of the curve. Its 900 ceiling IS MAX_TOTAL_DISTANCE, so this is the last band a
	-- throw can reach -- base-tier God needs a near-maxed throw, and most players will
	-- arrive here via luck promotion instead.
	{ Name = "God",       MinDistance = 820, MaxDistance = 900, Color = Color3.fromRGB(255, 226, 120) },
}
