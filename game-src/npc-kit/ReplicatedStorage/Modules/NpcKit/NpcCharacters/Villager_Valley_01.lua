-- NpcCharacters.Villager_Valley_01 -- the reference Tier 1 recipe: everything
-- a background NPC needs in ten lines. Distinctness comes from family, hair,
-- one overlay and the world theme; nothing here is bespoke.
return {
	id = "Villager_Valley_01", rootName = "NPC", tier = 1, world = "Valley", kind = "human",
	bodyType = "standard", family = "village", face = "friendly",
	hair = "HairCrop",
	overlays = { "Vest", "Belt" },
	pack = "Background",
}
