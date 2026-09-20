-- NpcCharacters.Gianluca_v1 -- the Step 0 prototype recipe, kept ONLY for the V1 | V2 | V2.5
-- comparison renders and the cube-face/blockout regression tests. Not a live candidate.
-- Data only. NpcForge.Build("Gianluca") turns this into the model; nothing
-- here is code. The root name is the live code contract (GianlucaClient waits
-- for GameWorld.StupidGianluca > HumanoidRootPart > TalkPrompt); the prompt
-- itself is never created here -- it is MOVED at the gated live swap.

return {
	id = "Gianluca_v1",
	rootName = "Gianluca_v1_Preview",
	tier = 2,
	world = "Valley",
	kind = "human",

	bodyType = "standard",
	scale = 1.0,
	family = "ranger",
	colors = {
		hair = Color3.fromRGB(92, 58, 36),
		accent = Color3.fromRGB(168, 58, 86),     -- berry scarf
		hat = Color3.fromRGB(108, 160, 80),       -- leaf
		walnut = Color3.fromRGB(74, 50, 30),
		metal = Color3.fromRGB(196, 150, 72),     -- brass buckle + bell
	},
	face = "worried",

	hair = "HairTousled",
	hat = "HatFloppyPinned",

	overlays = {
		"TunicHem",
		"CloakYoke",
		{ id = "ScarfTail", color = "accent" },
		"ToolBeltCollar",          -- the empty Chim collar: the story in one prop (bespoke)
		"Bracer",                  -- sided: BracerR + BracerL
	},
	props = {
		{ id = "Cane", grip = "RightHand" },
		{ id = "Bell", grip = "Cane" },   -- welds onto the cane's knob
	},

	-- baked into the rest C0 (semantic axes, degrees): always leaning into a search
	restPose = {
		Waist = { bend = 4 },
		RightShoulder = { spread = 10 }, LeftShoulder = { spread = 10 },
		RightElbow = { swing = 6 }, LeftElbow = { swing = 6 },
	},
	collider = true,             -- D-1: Tier 2 talking NPC

	pack = "Villager",
	packOverrides = {
		["idle.breathe.period"] = 2.9, ["idle.breathe.amp"] = 1.8,
		["idle.weightShift.amp"] = 4, ["idle.weightShift.period"] = 7, ["idle.weightDip.period"] = 3.5,
		["idle.look.amp"] = 28, ["idle.look.period"] = 5.0,
		["gestures.handsOnHips.weight"] = 0,
		["gestures.adjustCollar.weight"] = 0,
		["gestures.scratchBrim.weight"] = 2,
		["gestures.ringBell.weight"] = 3,
		greet = "ringBell",
	},

	contracts = {
		promptPart = "HumanoidRootPart",
		keepChildren = { "TalkPrompt" },
		moveChildrenTo = "GianlucaCamp",   -- D-2: scenery out of the character model (only if E-2 finds it inside)
	},
}
