-- Merchants that use the shared shop panel. Marco (SellStall) keeps his own sell menu.
-- WHICH WORLD EACH STALL STANDS IN.
-- A merchant can keep a stall in more than one world (Stall + AltStalls), and those
-- stalls no longer stock the same shelf -- Rocco sells RockConfig in the valley and
-- RockConfigTundra in world 2. The shop panel needs to know which shelf to draw the
-- moment you press E, so the mapping is declared here rather than guessed from the
-- stall's name or its coordinates. Anything not listed is treated as the default world.
-- The SERVER does not trust this: ShopHandler re-derives the buyer's world from their
-- actual region before allowing a purchase.
local StallWorld = {
	ShopStall           = "Valley",
	TundraShopStall     = "Tundra",
	UpgradeStall        = "Valley",
	TundraUpgradeStall  = "Tundra",
	CharmStall          = "Valley",
	TundraCharmStall    = "Tundra",
	-- World 3 skips on the valley ladder (WorldProgression aliases Gardens -> Valley),
	-- so these stock the valley shelf. Listed explicitly rather than left to the
	-- default so the mapping is readable rather than inferred.
	GardensShopStall    = "Gardens",
	GardensUpgradeStall = "Gardens",
	GardensCharmStall   = "Gardens",
}

local Merchants = {
	{
		Id = "RockDealer",
		Stall = "ShopStall",
		-- Rocco also keeps a stall in the Frozen Tundra hub. Listing it here rather
		-- than hardcoding it in the client means adding a third world is config-only.
		AltStalls = { "TundraShopStall", "GardensShopStall" },
		Prompt = "ShopPrompt",
		Npc = "Rocco the Rock Dealer",
		Title = "\u{1F48E} ROCK SHOP",
		Blurb = "Better rocks skip farther and roll luckier.",
		Kind = "Rock",
		Accent = { Color3.fromRGB(255, 216, 96), Color3.fromRGB(238, 148, 24) },
		Dialogue = { "Finest stones around \u{2014} have a look!" },
		-- Walk-in cue. This is a SoundKit NAME, not an asset id -- SoundKit owns
		-- every id in the game so a call site never carries one. shopBell is the
		-- CLOSE-MIC store entry bell: the Distant takes of the same bell read as one
		-- ringing in another room, and it is the shortest of that set at 3.80s, so it
		-- finishes under Rocco's line instead of ringing on over the shop panel.
		-- Omit these two fields to give a merchant no walk-in sound at all.
		EnterSound = "shopBell",
		EnterVolume = 0.35,
	},
	{
		Id = "Upgrader",
		Stall = "UpgradeStall",
		AltStalls = { "TundraUpgradeStall", "GardensUpgradeStall" },
		Prompt = "UpgradePrompt",
		Npc = "Enzo the Upgrader",
		Title = "\u{2728} UPGRADES",
		Blurb = "Permanent boosts. Each level costs more.",
		Kind = "Upgrade",
		Accent = { Color3.fromRGB(198, 142, 255), Color3.fromRGB(116, 46, 208) },
		Dialogue = { "Ready to power up? Let's see..." },
		-- Potion pour for the upgrade bench. shopPour is a bottle emptying into a
		-- glass and ending on a glass clink -- that clink is what sells it as a
		-- potion being poured rather than a tap running. Longest of the three shop
		-- cues at 4.44s, which is fine: a pour is inherently a slow sound.
		EnterSound = "shopPour",
		EnterVolume = 0.40,
	},
	{
		Id = "CharmSeller",
		Stall = "CharmStall",
		AltStalls = { "TundraCharmStall", "GardensCharmStall" },
		Prompt = "CharmPrompt",
		Npc = "Lil Miss",
		Title = "\u{1F340} CHARMS",
		Blurb = "Little trinkets. They bring their own luck.",
		Kind = "Charm",
		-- NOT SHIPPING YET (2026-08-19, owner). CharmConfig's own header says the
		-- real charms do not exist -- every name and number in it is a stand-in --
		-- and there is no charm remote anywhere in the game, so nothing here could
		-- be bought even if the shelf drew. MerchantClient reads this flag and shows
		-- COMING SOON! in place of the grid; without it the panel opened onto six
		-- empty cells, which reads as broken rather than as unfinished.
		--
		-- Delete this one line to bring the shop back. `Kind = "Charm"` still needs
		-- a branch in MerchantClient's item builder before it will draw anything.
		ComingSoon = true,
		Accent = { Color3.fromRGB(232, 150, 176), Color3.fromRGB(176, 62, 110) },
		-- Shown before the shop opens. MerchantDialog typewrites these and only
		-- offers the buttons once the last line finishes.
		-- One line on purpose: hers used to run four pages (three Next clicks) while every
		-- other merchant greets you in one, so this now opens straight to the shop like theirs.
		Dialogue = {
			"Oh, a customer! Every charm here's got a bit of luck in it, dear \u{2014} have a look at what old Lil Miss has for you.",
		},
		EnterSound = "shopBell",
		EnterVolume = 0.30,
	},
}

-- Attached to the same table the module already returned, so every existing
-- `for _, m in ipairs(MerchantConfig)` call site is untouched.
Merchants.StallWorld = StallWorld

return Merchants
