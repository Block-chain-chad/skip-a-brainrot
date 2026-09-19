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
		-- offsets are PLACEHOLDERS on a crocodile-plane stand-in (body 4x2.2x6 at the origin, snout to -Z,
		-- left wing at -X, tail to +Z, ~7 studs long); E-13 replaces them with the real template's bounds
		{ part = "WingSplint",   shape = "Block",    size = Vector3.new(0.18, 0.18, 2.20), color = WALNUT, bone = "WingL",  boneFallback = "Body", offset = CFrame.new(-4.2, 1.15, -0.3) * CFrame.Angles(0, 0, math.rad(-4)) },
		{ part = "WingStrap",    shape = "Block",    size = Vector3.new(0.90, 0.10, 0.60), color = SOOT,   bone = "WingL",  boneFallback = "Body", offset = CFrame.new(-3.4, 1.08, 0.0) },
		{ part = "HarnessPlate", shape = "Block",    size = Vector3.new(1.60, 1.20, 0.16), color = IRON,   bone = "Body",   offset = CFrame.new(0, 0.35, -3.05) * CFrame.Angles(0, 0, math.rad(6)) },
		{ part = "HarnessStrap", shape = "Block",    size = Vector3.new(0.35, 1.40, 0.10), color = SOOT,   bone = "Body",   offset = CFrame.new(0.55, 0.95, -2.95) * CFrame.Angles(0, 0, math.rad(-30)) },
		{ part = "GoggleBand",   shape = "Cylinder", size = Vector3.new(0.12, 2.00, 2.00), color = SOOT,   bone = "Head",   boneFallback = "Body", offset = CFrame.new(0, 1.05, -3.7) * CFrame.Angles(0, 0, math.rad(90)) },
		{ part = "GoggleLens",   shape = "Block",    size = Vector3.new(0.90, 0.28, 0.22), color = SMOKED, material = Enum.Material.SmoothPlastic, bone = "GoggleBand", offset = CFrame.new(0, 1.15, -4.75) },
		{ part = "Medal",        shape = "Cylinder", size = Vector3.new(0.06, 0.32, 0.32), color = BRASS,  material = Enum.Material.SmoothPlastic, bone = "HarnessPlate", offset = CFrame.new(-0.45, 0.15, -3.2) * CFrame.Angles(0, math.rad(90), 0) },
		{ part = "SnoutChip",    shape = "Block",    size = Vector3.new(0.34, 0.20, 0.10), color = SCORCH, bone = "Snout",  boneFallback = "Head", offset = CFrame.new(-0.55, 0.55, -5.85) },
	},

	-- seated, weight off the bound wing, sunk into the rubble, watching the tunnel
	stance = { pitch = -12, roll = 6, yaw = 30, sink = -0.4 },

	pack = "Creature",
	profile = "Veteran",
	collider = false,          -- a seated creature in a corner; players cannot stand inside a plinth anyway
}
