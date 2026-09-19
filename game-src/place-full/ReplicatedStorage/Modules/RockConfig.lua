-- RockConfig: the progression ladder. 21 rocks -- the top 7 are end-game "cosmic"
-- rocks past BrainrotCore, all pinned at the 900m reach cap, that sell pure LUCK.
-- Buying is SEQUENTIAL: ShopHandler requires you to own the previous rock first, and
-- MerchantClient shows the shop in pages. Order below = ladder order; keep it ascending.
--
-- ============================ HOW A ROCK GATES A TIER ============================
-- MaxDistance ONLY matters where it crosses a RarityConfig band edge. The edges are
--
--     Common 0 | Uncommon 100 | Rare 220 | Epic 360 | Legendary 500 |
--     Mythic 640 | Secret 780 | God 900
--
-- so a rock reaching 150 and one reaching 200 both roll Uncommon and nothing else.
-- Extra reach INSIDE a band buys literally nothing. That is why this ladder
-- alternates what each purchase sells:
--
--   REACH rocks unlock a higher tier band AND raise your odds inside it.
--   LUCK  rocks raise Luck instead. Luck now shifts the whole RarityCurve toward the
--         top (ReplicatedStorage.Modules.RarityCurve) -- distance no longer GUARANTEES
--         a tier, it weights the odds, so both reach and luck pull their weight.
--
-- The shop row already prints "Up to Nm - x luck" (MerchantClient), so a LUCK rock
-- reads as an upgrade rather than looking like a no-op purchase.
--
-- Under the RarityCurve, Luck has a SMOOTH (un-clamped) effect on the odds, so the
-- end-game LUCK rocks below stay meaningful all the way up. Do not over-inflate them:
-- luck also multiplies with the Lucky Charm upgrade, Offerings and the Maxwell pet, so
-- the product climbs fast -- the top rock plus maxed upgrades is what the Secret odds
-- are tuned around.
--
-- ============================== WHY THESE PRICES ==============================
-- Tier income grows ~5.8x per band (weighted-average cash/sec over obtainable
-- names). The old ladder grew prices only ~4.6x per band, so every gate was CHEAPER
-- in real terms than the last and progression accelerated: time-to-next-rock fell
-- 59s -> 49 -> 34 -> 30 -> 25 -> 21 and the whole ladder was under 4 minutes.
--
-- Prices step ~3.5x per rock, i.e. ~12.2x per band against ~5.8x income, so each band
-- takes ~2.1x longer than the one before and the curve genuinely rises.
--
-- The short-then-long rhythm within a band is deliberate: crossing a band edge is a
-- ~6x income jump, so the LUCK rock right after it lands quickly as a reward, then
-- the next REACH rock is the real climb.
--
-- SLOWED 2026-08-15 ("its easy to progress and get far"). The step was ~3.2x/rock,
-- which included a WORLD-1 EASING pass from 2026-08-07 that had discounted the early
-- and mid ladder ~35% at the bottom tapering to ~8% by BrainrotCore. Both were undone
-- by one multiplier applied to every price: 1.15 x 1.06^(rung-2).
--
-- The SHAPE of that multiplier is the point. It is deliberately near-1 at the bottom
-- (SmoothStone 250 -> 300) so a brand-new player still gets their first two purchases
-- quickly and the hook survives, and it compounds up the ladder (VoidHeart 2T -> 7T)
-- where "getting far too easily" is what actually needed fixing. Per-rung it reads as
-- a small nudge; end to end the ladder costs ~3.4x what it did.
--
-- Re-tune by changing that one multiplier and re-deriving, not by editing rows: the
-- ~3.5x step between neighbours is what the band pacing above depends on.
--
-- ============================== DO NOT RENAME IDS ==============================
-- data.OwnedRocks and data.EquippedRock are keyed by Id string. ThrowHandler line
-- ~343 falls back to `rockById["Pebble"]` when an Id is missing, so deleting or
-- renaming an entry does not error -- it SILENTLY demotes every owner of that rock
-- to Pebble. All 8 original Ids are preserved below for exactly that reason; the 6
-- new rocks are inserted around them. Add, never rename.
return {
	-- COMMON (0+)
	{ Id = "Pebble", Name = "Creek Pebble",            Price = 0,          MaxDistance = 25,  Luck = 1.00, Color = Color3.fromRGB(140, 140, 140) },
	{ Id = "SmoothStone", Name = "Rivertumble",       Price = 12000,        MaxDistance = 70,  Luck = 1.15, Color = Color3.fromRGB(160, 160, 170) },
	-- UNCOMMON (100+)
	{ Id = "FlatSkipper", Name = "Sevenskip",       Price = 23900,       MaxDistance = 110, Luck = 1.30, Color = Color3.fromRGB(120, 150, 160) },
	{ Id = "SlateDisc", Name = "Skiprazor",         Price = 3400, Retired = true,       MaxDistance = 200, Luck = 1.42, Color = Color3.fromRGB(105, 115, 125) },
	-- RARE (220+)
	{ Id = "GraniteChunk", Name = "Boulderfang",      Price = 287000,      MaxDistance = 160, Luck = 1.50, Color = Color3.fromRGB(110, 90, 90) },
	{ Id = "RiverGlass", Name = "Rivermirror",        Price = 44000, Retired = true,      MaxDistance = 340, Luck = 1.72, Color = Color3.fromRGB(150, 205, 195) },
	-- EPIC (360+)
	{ Id = "ObsidianShard", Name = "Nightglass",     Price = 502000,     MaxDistance = 215, Luck = 1.72, Color = Color3.fromRGB(30, 30, 35) },
	{ Id = "BasaltPlate", Name = "Emberplate",       Price = 540000, Retired = true,     MaxDistance = 480, Luck = 2.05, Color = Color3.fromRGB(62, 58, 66) },
	-- LEGENDARY (500+)
	{ Id = "MeteoriteFragment", Name = "Skyfall Cinder", Price = 4620000,    MaxDistance = 275, Luck = 1.95, Color = Color3.fromRGB(90, 60, 40) },
	{ Id = "StarcastIron", Name = "Starcast Ingot",      Price = 6800000, Retired = true,    MaxDistance = 620, Luck = 2.40, Color = Color3.fromRGB(140, 152, 170) },
	-- MYTHIC (640+)
	{ Id = "GoldenRock", Name = "Midas Bullion",        Price = 7130000,   MaxDistance = 340, Luck = 2.20, Color = Color3.fromRGB(255, 215, 60) },
	{ Id = "PrismaticGeode", Name = "Prismheart Geode",    Price = 82000000, Retired = true,   MaxDistance = 770, Luck = 2.85, Color = Color3.fromRGB(170, 120, 255) },
	-- SECRET (780+) -- previously only BrainrotCore reached this band at all
	{ Id = "VoidstoneShard", Name = "Voidglass Fang",    Price = 10500000,  MaxDistance = 410, Luck = 2.50, Color = Color3.fromRGB(40, 28, 70) },
	-- GOD (900) -- 900 is both ThrowHandler's MAX_TOTAL_DISTANCE clamp and the God
	-- floor, so this rock alone can reach base-tier God on a literally maxed throw.
	-- Unchanged from before. NOTE: the God tier currently has totalWeight = 0, so
	-- RarityRoll cannot actually roll it -- see the separate note about that.
	{ Id = "BrainrotCore", Name = "Brainrot Core",      Price = 97400000, MaxDistance = 485, Luck = 2.85, Color = Color3.fromRGB(255, 60, 200) },
	-- === END-GAME: cosmic LUCK rocks (2026-07-27) ===
	-- All pinned at the 900m cap (reach can go no higher), so each sells pure Luck to push
	-- your RarityCurve odds up. Priced in the billions+ so a stocked base finally has a
	-- real grind past BrainrotCore. Each has a RockDesign entry (faceted mesh + neon aura,
	-- 2026-08-06), so they render as glowing cosmic stones. Prices ~3.3x/step, Luck 3.7 -> 5.4.
	{ Id = "CometCore", Name = "Cometfall",         Price = 544000000,    MaxDistance = 560, Luck = 3.20, Color = Color3.fromRGB(120, 200, 255) },
	{ Id = "QuasarStone", Name = "Quasar Ember",       Price = 13000000000, Retired = true,   MaxDistance = 900, Luck = 3.90, Color = Color3.fromRGB(180, 100, 255) },
	{ Id = "NebulaCore", Name = "Nebula Bloom",        Price = 761000000,   MaxDistance = 640, Luck = 3.60, Color = Color3.fromRGB(255, 100, 200) },
	{ Id = "PulsarShard", Name = "Pulsar Needle",       Price = 160000000000, Retired = true,  MaxDistance = 900, Luck = 4.40, Color = Color3.fromRGB(90, 240, 230) },
	{ Id = "GalaxyCore", Name = "Spiralcore",        Price = 4380000000,  MaxDistance = 720, Luck = 4.05, Color = Color3.fromRGB(120, 70, 200) },
	{ Id = "CosmosHeart", Name = "Starforge Heart",       Price = 5990000000, MaxDistance = 805, Luck = 4.60, Color = Color3.fromRGB(255, 240, 180) },
	{ Id = "VoidHeart", Name = "Singularity",         Price = 7380000000, MaxDistance = 900, Luck = 5.40, Color = Color3.fromRGB(45, 25, 70) },
}
