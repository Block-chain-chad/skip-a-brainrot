-- RockConfigTundra: World 2's rock ladder. Same FORMAT as RockConfig --
-- { Id, Price, MaxDistance, Luck, Color } -- and read through WorldProgression, so no
-- gameplay code names a world.
--
-- SOLD AND USED ONLY IN WORLD 2. Rocco keeps a stall in both worlds and they stock
-- different shelves: the valley stall lists RockConfig, the Frozen Tundra stall lists
-- this file. ShopHandler enforces it server-side against the buyer's ACTUAL region, so
-- firing BuyRock from the valley cannot buy a tundra rock.
--
-- AND THE OTHER WAY TOO (2026-08-15). These are the only rocks that can be THROWN in
-- the tundra, exactly as valley rocks are the only ones throwable in the valley. Walking
-- in holding VoidHeart no longer skips world 2 -- ThrowHandler resolves the stone against
-- the shelf of the world you are standing in. Anything that merely LOOKS UP an owned rock
-- (the bag, the luck HUD, the rock's looks) still reads the MERGED list via
-- WorldProgression.RockById, because a tundra rock has to render while its owner is in
-- the valley; if it read only RockConfig, every owner of one would show as Pebble.
--
-- A SELF-CONTAINED LADDER, CLIMBED FROM ITS OWN BOTTOM. The sequential-unlock rule
-- applies WITHIN a world, so the first rock here needs no valley rock first -- reaching
-- world 2 is the gate.
--
-- GLACIERSHARD IS THIS WORLD'S PEBBLE. Priced 0 and granted the moment a player first
-- stands in the Tundra (ShopHandler.SyncRockToWorld). It has to be free and it has to be
-- first: since a valley rock cannot be thrown here, an arriving player who owned nothing
-- on this shelf would have nothing to throw at all.
--
-- ONE ROCK PER BAND. These used to be pinned at 900m and sell pure luck, which only made
-- sense while you arrived already holding a 900m valley rock. Now that you do not, reach
-- is the ladder again: each rung clears the next of RarityConfigTundra's bands
-- (0/110/220/340/460/580/700/820), so World 2 is a full second progression rather than a
-- victory lap. RarityCurve treats distance as a HARD gate -- a tier below your reach has
-- weight zero and no amount of luck promotes into it -- so a rung really is a tier.
--
-- PRICES were re-spread with the reach (2026-08-15). GlacierShard's old 6.5T moved up to
-- FrostbiteCore, which is now the first thing you actually buy here, and the rest step
-- ~4x to the SAME 26,000T ceiling AbsoluteZero always had. The step is a little steeper
-- than the old ~3.3x because a rung now buys a whole rarity band as well as luck. The
-- entry price of progress in world 2 is therefore unchanged: 6.5T, the same number it
-- has always been, just attached to the second rock instead of the first.
--
-- LUCK IS UNCHANGED (5.80 -> 10.00), still starting just above the valley's top rock.
-- On GlacierShard it is nearly inert -- at 90m only the Common band has any weight, and
-- a normalised roll over one tier is 100% Common whatever the luck figure says.
--
-- DO NOT RENAME IDS: data.OwnedRocks and data.EquippedRock are keyed by Id string, and
-- a missing Id silently demotes its owner to Pebble. Add, never rename.
return {
	-- COMMON (0+) -- free, granted on arrival. World 2's Pebble.
	{ Id = "GlacierShard", Name = "Icebite",     Price = 0,                 MaxDistance = 160,  Luck = 5.80, Color = Color3.fromRGB(150, 205, 235) },
	-- UNCOMMON (110+)
	{ Id = "FrostbiteCore", Name = "Chillheart",    Price = 10000000000,     MaxDistance = 200, Luck = 6.20, Color = Color3.fromRGB(90, 165, 220) },
	-- RARE (220+)
	{ Id = "RimeGeode", Name = "Hoarfrost Geode",        Price = 14000000000,    MaxDistance = 280, Luck = 6.70, Color = Color3.fromRGB(200, 235, 245) },
	-- EPIC (340+)
	{ Id = "PermafrostHeart", Name = "Deepfreeze Heart",  Price = 20000000000,   MaxDistance = 360, Luck = 7.20, Color = Color3.fromRGB(60, 120, 175) },
	-- LEGENDARY (460+)
	{ Id = "AuroraStone", Name = "Auroraglass",      Price = 90000000000,   MaxDistance = 450, Luck = 7.80, Color = Color3.fromRGB(120, 255, 200) },
	-- MYTHIC (580+)
	{ Id = "BlizzardCore", Name = "Whiteout Core",     Price = 185000000000,  MaxDistance = 580, Luck = 8.50, Color = Color3.fromRGB(235, 250, 255) },
	-- SECRET (700+)
	{ Id = "GlacialMonolith", Name = "Iceborn Monolith",  Price = 400000000000,  MaxDistance = 700, Luck = 9.20, Color = Color3.fromRGB(70, 100, 140) },
	-- GOD (820+) -- 900 is ThrowHandler's MAX_TOTAL_DISTANCE clamp, so this is the ceiling.
	{ Id = "AbsoluteZero", Name = "Absolute Zero",     Price = 950000000000, MaxDistance = 900, Luck = 10.00, Color = Color3.fromRGB(180, 240, 255) },
}
