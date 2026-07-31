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
-- Prices now step ~3.2x per rock, i.e. ~10.4x per band against ~5.8x income, so each
-- band takes ~1.8x longer than the one before. Full ladder on bare 12-pad income is
-- ~1.3 hours instead of 3.9 minutes, and the curve finally rises.
--
-- The short-then-long rhythm within a band is deliberate: crossing a band edge is a
-- ~6x income jump, so the LUCK rock right after it lands quickly as a reward, then
-- the next REACH rock is the real climb.
--
-- ============================== DO NOT RENAME IDS ==============================
-- data.OwnedRocks and data.EquippedRock are keyed by Id string. ThrowHandler line
-- ~343 falls back to `rockById["Pebble"]` when an Id is missing, so deleting or
-- renaming an entry does not error -- it SILENTLY demotes every owner of that rock
-- to Pebble. All 8 original Ids are preserved below for exactly that reason; the 6
-- new rocks are inserted around them. Add, never rename.
return {
	-- COMMON (0+)
	{ Id = "Pebble",            Price = 0,          MaxDistance = 25,  Luck = 1.00, Color = Color3.fromRGB(140, 140, 140) },
	{ Id = "SmoothStone",       Price = 400,        MaxDistance = 70,  Luck = 1.10, Color = Color3.fromRGB(160, 160, 170) },
	-- UNCOMMON (100+)
	{ Id = "FlatSkipper",       Price = 1300,       MaxDistance = 150, Luck = 1.25, Color = Color3.fromRGB(120, 150, 160) },
	{ Id = "SlateDisc",         Price = 4200,       MaxDistance = 200, Luck = 1.42, Color = Color3.fromRGB(105, 115, 125) },
	-- RARE (220+)
	{ Id = "GraniteChunk",      Price = 13500,      MaxDistance = 260, Luck = 1.55, Color = Color3.fromRGB(110, 90, 90) },
	{ Id = "RiverGlass",        Price = 44000,      MaxDistance = 340, Luck = 1.72, Color = Color3.fromRGB(150, 205, 195) },
	-- EPIC (360+)
	{ Id = "ObsidianShard",     Price = 140000,     MaxDistance = 400, Luck = 1.88, Color = Color3.fromRGB(30, 30, 35) },
	{ Id = "BasaltPlate",       Price = 450000,     MaxDistance = 480, Luck = 2.05, Color = Color3.fromRGB(62, 58, 66) },
	-- LEGENDARY (500+)
	{ Id = "MeteoriteFragment", Price = 1450000,    MaxDistance = 560, Luck = 2.22, Color = Color3.fromRGB(90, 60, 40) },
	{ Id = "StarcastIron",      Price = 4700000,    MaxDistance = 620, Luck = 2.40, Color = Color3.fromRGB(140, 152, 170) },
	-- MYTHIC (640+)
	{ Id = "GoldenRock",        Price = 15000000,   MaxDistance = 740, Luck = 2.60, Color = Color3.fromRGB(255, 215, 60) },
	{ Id = "PrismaticGeode",    Price = 48000000,   MaxDistance = 770, Luck = 2.85, Color = Color3.fromRGB(170, 120, 255) },
	-- SECRET (780+) -- previously only BrainrotCore reached this band at all
	{ Id = "VoidstoneShard",    Price = 155000000,  MaxDistance = 820, Luck = 3.10, Color = Color3.fromRGB(40, 28, 70) },
	-- GOD (900) -- 900 is both ThrowHandler's MAX_TOTAL_DISTANCE clamp and the God
	-- floor, so this rock alone can reach base-tier God on a literally maxed throw.
	-- Unchanged from before. NOTE: the God tier currently has totalWeight = 0, so
	-- RarityRoll cannot actually roll it -- see the separate note about that.
	{ Id = "BrainrotCore",      Price = 500000000,  MaxDistance = 900, Luck = 3.50, Color = Color3.fromRGB(255, 60, 200) },
	-- === END-GAME: cosmic LUCK rocks (2026-07-27) ===
	-- All pinned at the 900m cap (reach can go no higher), so each sells pure Luck to push
	-- your RarityCurve odds up. Priced in the billions+ so a stocked base finally has a
	-- real grind past BrainrotCore. No RockDesign entries yet -> they throw as a coloured
	-- generic rock (fine as a placeholder). Prices ~3.3x/step, Luck 3.7 -> 5.4. Tune freely.
	{ Id = "CometCore",         Price = 1500000000,    MaxDistance = 900, Luck = 3.70, Color = Color3.fromRGB(120, 200, 255) },
	{ Id = "QuasarStone",       Price = 5000000000,    MaxDistance = 900, Luck = 3.90, Color = Color3.fromRGB(180, 100, 255) },
	{ Id = "NebulaCore",        Price = 16000000000,   MaxDistance = 900, Luck = 4.15, Color = Color3.fromRGB(255, 100, 200) },
	{ Id = "PulsarShard",       Price = 55000000000,   MaxDistance = 900, Luck = 4.40, Color = Color3.fromRGB(90, 240, 230) },
	{ Id = "GalaxyCore",        Price = 180000000000,  MaxDistance = 900, Luck = 4.70, Color = Color3.fromRGB(120, 70, 200) },
	{ Id = "CosmosHeart",       Price = 600000000000,  MaxDistance = 900, Luck = 5.00, Color = Color3.fromRGB(255, 240, 180) },
	{ Id = "VoidHeart",         Price = 2000000000000, MaxDistance = 900, Luck = 5.40, Color = Color3.fromRGB(45, 25, 70) },
}
