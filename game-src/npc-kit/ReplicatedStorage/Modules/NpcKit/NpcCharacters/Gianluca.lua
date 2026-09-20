-- NpcCharacters.Gianluca -- V2.5 recipe (approved 2026-09-19: D-16..D-22).
-- OLD VETERAN: fought alongside Elder Tung; ranger / survivor. Data only.
-- NpcForge.Build("Gianluca") assembles him from the generated shell manifest
-- (NpcShells.Gianluca_V25: every visible mesh, the face parts, the props) on the
-- p2 BodyProfile; nothing here is code. The root name is the live code contract
-- (GianlucaClient waits for GameWorld.StupidGianluca > HumanoidRootPart > TalkPrompt);
-- the prompt itself is never created here -- it is MOVED at the gated live swap.

return {
	id = "Gianluca",
	rootName = "StupidGianluca",
	tier = 3,                    -- D-20: a story character (Elder Tung history); Tier 3 budget
	world = "Valley",
	kind = "human",

	-- the visible character: one generated manifest = body shells + face + hair/beard + gear + spear
	shells = "Gianluca_V25",
	bodyType = "p2",             -- D-22 default profile; per-character shape tweaks go in bodyOverrides
	bodyOverrides = {},          -- e.g. { height = 0.97, limbThickness = 1.05, posture = { Waist = { bend = 10 } } }
	scale = 1.0,
	family = "ranger",
	colors = {                   -- the manifest carries every piece colour; these stay for the legacy roles
		hair = Color3.fromRGB(182, 178, 170),
		accent = Color3.fromRGB(150, 84, 96),
		walnut = Color3.fromRGB(70, 52, 34),
		metal = Color3.fromRGB(150, 122, 70),
	},
	face = "serious",            -- default state; the war beat goes "tired" (NpcMotionConfig.Packs.Veteran.reactions)

	-- veteran posture, baked into the rest C0 (semantic axes, degrees): forward lean over the
	-- planted spear, torso tipped to the staff side, plated left arm hanging back, weight right
	restPose = {
		Waist = { bend = 9, turn = 4, tilt = 3 },
		Neck = { bend = 4, turn = -8, tilt = 4 },
		RightShoulder = { swing = 40, spread = 12 }, RightElbow = { swing = 34 },
		LeftShoulder = { swing = -12, spread = 9 }, LeftElbow = { swing = 22 },
		RightHip = { spread = 2 }, LeftHip = { spread = 9 }, LeftKnee = { swing = 10 },
		LeftAnkle = { swing = -10, spread = -9 },   -- sole stays flat under the bent knee
	},
	collider = true,             -- D-1: talking NPC, tight collider in its own group

	pack = "Veteran",
	packOverrides = {
		["idle.breathe.period"] = 3.8, ["idle.breathe.amp"] = 1.2,
		["idle.weightShift.amp"] = 3, ["idle.weightShift.period"] = 9,
		["idle.look.amp"] = 18, ["idle.look.period"] = 7.0,
		greet = "nodGreet",
	},

	contracts = {
		promptPart = "HumanoidRootPart",
		keepChildren = { "TalkPrompt" },
		moveChildrenTo = "GianlucaCamp",   -- D-2: scenery out of the character model (only if E-2 finds it inside)
	},
}
