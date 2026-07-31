-- Merchants that use the shared shop panel. Marco (SellStall) keeps his own sell menu.
return {
	{
		Id = "RockDealer",
		Stall = "ShopStall",
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
}
