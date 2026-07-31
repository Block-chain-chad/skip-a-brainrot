return {
	{ Name = "Common",    MinDistance = 0,   MaxDistance = 100, Color = Color3.fromRGB(190, 190, 190) },
	{ Name = "Uncommon",  MinDistance = 100, MaxDistance = 220, Color = Color3.fromRGB(80, 220, 90) },
	{ Name = "Rare",      MinDistance = 220, MaxDistance = 360, Color = Color3.fromRGB(60, 140, 255) },
	{ Name = "Epic",      MinDistance = 360, MaxDistance = 500, Color = Color3.fromRGB(180, 60, 255) },
	{ Name = "Legendary", MinDistance = 500, MaxDistance = 640, Color = Color3.fromRGB(255, 170, 30) },
	{ Name = "Mythic",    MinDistance = 640, MaxDistance = 780, Color = Color3.fromRGB(255, 50, 50) },
	{ Name = "Secret",    MinDistance = 780, MaxDistance = 900, Color = Color3.fromRGB(255, 90, 220) },
	-- GOD: the apex tier, added 2026-07-25 for Secret Pete. Its floor is the same
	-- 900 that ThrowHandler clamps total distance to, so base-tier God requires a
	-- literally maxed throw; every other route in is a luck promotion off Secret.
	-- Deliberately brutal -- Pete is the only inhabitant and is capped at 5 mints.
	{ Name = "God",       MinDistance = 900, MaxDistance = math.huge, Color = Color3.fromRGB(255, 226, 120) },
}
