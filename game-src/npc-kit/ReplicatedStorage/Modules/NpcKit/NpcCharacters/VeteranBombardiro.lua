-- NpcCharacters.VeteranBombardiro -- Prototype B recipe (Phase 2.5 doc D).
-- CONDITIONAL on Studio item E-13: the species is a proposal; `species` is the
-- only field that changes if the World 3 lane picks a forge-baked body (D-10).
-- NpcForge builds this on a CLONE of ReplicatedStorage.BrainrotModels[species];
-- the collectible template is never modified. Bone names / offsets below are
-- placeholders until E-13 reports the real part names and bounds; `bone`
-- falls back to `boneFallback`, then to the root, so the build never fails on
-- a name -- it just parks the part on the body.

local function C(r, g, b) return Color3.fromRGB(r, g, b) end
local WALNUT, SOOT, IRON, BRASS, SMOKED, SCORCH = C(74, 50, 30), C(52, 50, 48), C(96, 98, 104), C(196, 150, 72), C(70, 72, 80), C(60, 52, 48)

return {
	id = "VeteranBombardiro",
	rootName = "VeteranBombardiro",
	tier = 3,
	world = "Gardens",
	kind = "creature",

	species = "Bombardiro Crocodilo",
	stripFx = true,                              -- no Mythic aura on a war veteran
	wear = { sat = -0.20, val = -0.08 },         -- worn materials, identity colours kept
	recolorRoles = { Tail = SCORCH },            -- applied only if a part named Tail exists (E-13)

	-- the veteran layer, priority order; drop from the bottom if a species needs the budget
	storyLayer = {
		{ part = "WingSplint",   shape = "Block",    size = Vector3.new(0.18, 2.20, 0.50), color = WALNUT, bone = "WingL",  boneFallback = "Body", offset = CFrame.new(-2.1, 1.1, 0.2) * CFrame.Angles(0, 0, math.rad(-8)) },
		{ part = "WingStrap",    shape = "Block",    size = Vector3.new(0.90, 0.10, 0.60), color = SOOT,   bone = "WingL",  boneFallback = "Body", offset = CFrame.new(-2.0, 1.2, 0.2) },
		{ part = "HarnessPlate", shape = "Block",    size = Vector3.new(1.60, 1.20, 0.16), color = IRON,   bone = "Body",   offset = CFrame.new(0, 0.6, -1.4) * CFrame.Angles(0, 0, math.rad(6)) },
		{ part = "HarnessStrap", shape = "Block",    size = Vector3.new(0.35, 1.40, 0.10), color = SOOT,   bone = "Body",   offset = CFrame.new(0.6, 1.3, -1.3) * CFrame.Angles(0, 0, math.rad(-30)) },
		{ part = "GoggleBand",   shape = "Cylinder", size = Vector3.new(0.12, 1.50, 1.50), color = SOOT,   bone = "Head",   boneFallback = "Body", offset = CFrame.new(0, 2.4, -0.6) * CFrame.Angles(0, 0, math.rad(90)) },
		{ part = "GoggleLens",   shape = "Block",    size = Vector3.new(0.90, 0.28, 0.22), color = SMOKED, material = Enum.Material.SmoothPlastic, bone = "GoggleBand", offset = CFrame.new(0, 2.5, -1.35) },
		{ part = "Medal",        shape = "Cylinder", size = Vector3.new(0.06, 0.32, 0.32), color = BRASS,  material = Enum.Material.SmoothPlastic, bone = "HarnessPlate", offset = CFrame.new(-0.45, 0.3, -1.5) * CFrame.Angles(0, math.rad(90), 0) },
		{ part = "SnoutChip",    shape = "Block",    size = Vector3.new(0.34, 0.20, 0.10), color = SCORCH, bone = "Snout",  boneFallback = "Body", offset = CFrame.new(-0.3, 0.2, -2.6) },
	},

	-- seated, weight off the bound wing, sunk into the rubble, watching the tunnel
	stance = { pitch = -12, roll = 6, yaw = 30, sink = -0.4 },

	pack = "Creature",
	profile = "Veteran",
	collider = false,          -- a seated creature in a corner; players cannot stand inside a plinth anyway
}
