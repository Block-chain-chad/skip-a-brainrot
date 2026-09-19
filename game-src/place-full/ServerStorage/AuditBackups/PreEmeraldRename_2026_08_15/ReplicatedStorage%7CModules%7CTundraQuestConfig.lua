-- TundraQuestConfig: Elder Tung's SECOND questline -- the World 2 trials, and the dig
-- down to the ancient cave that becomes Area 3.
--
-- NOT TungQuestConfig. That one is the VALLEY questline (hand him twelve brainrots, get
-- the cellar key that opens the way here) and it is finished the moment a player reaches
-- the tundra. Same elder, a second hut on the western ice, a second arc: this one gates
-- World 3 exactly the way that one gated World 2.
--
-- SHARED because three places have to agree on the same numbers -- the server state
-- machine (ServerScriptService.Modules.TundraQuest), the dialogue/tracker on the client,
-- and the quest log. A quota stated twice is a quota that will eventually disagree.
local M = {}

M.NpcName = "Elder Tung"
M.HutName = "ElderHut"          -- Workspace.GameWorld.FrozenTundra.ElderHut
M.NpcModel = "ElderTungTundra"  -- the tundra copy of him; the valley one is ElderTung
M.PromptName = "TungCavePrompt"

-- === STATE ===================================================================
-- data.TundraQuest is an INDEX INTO M.Stages, 0 = not accepted. Storing the index rather
-- than a name means a stage can be retitled without touching a single save, and the
-- ordering below is the only place the arc's shape is written down.
--
-- Progress counters live in data.TundraProgress and data.TundraParts. Both only ever
-- count UP and are never rebuilt from inventory: "catch 300" has to survive selling all
-- 300, and a delivered part must not un-deliver itself.
M.NONE = 0

-- Kinds:
--   "count"  a counter on data.TundraProgress reaching Target; ticked by a catch hook
--   "gather" the data.TundraParts quota below; parts surface while skipping
--   "talk"   a beat that advances purely by talking to him (the story moments)
M.Stages = {
	{
		Id = "Trial1", Kind = "count", Counter = "Catches", Target = 300,
		Title = "Prove yourself: 300 catches",
		Track = "Catch %d/%d brainrots in the Frozen Tundra",
		-- He does not explain the cave yet. The trials are him deciding whether the
		-- player is worth telling.
		Say = "You made it through my cellar, and now you want to know what is FURTHER? " ..
		      "Prove yourself for the journey ahead. Three hundred brainrots out of this ice. " ..
		      "Then we talk.",
		Nag = "Three hundred. I am not counting for you -- well. I am. But keep skipping.",
		Done = "Three hundred. Your arms must hate you. Good.",
		Reward = { Cash = 5000000 },
	},
	{
		Id = "Trial2", Kind = "count", Counter = "Mythics", Target = 20,
		Title = "Prove yourself: 20 Mythics",
		Track = "Catch %d/%d Mythic brainrots",
		Say = "Quantity proves patience. Now prove your ARM. Twenty Mythics -- the red ones, " ..
		      "far out past the floes. Nothing less counts.",
		Nag = "Twenty Mythics. Throw HARDER, that is the whole secret.",
		Done = "Twenty. Nobody has done that in front of me before.",
		Reward = { Cash = 25000000, Darrels = 150 },
	},
	{
		Id = "Greeting", Kind = "talk",
		Title = "Speak with Elder Tung",
		Track = "Return to Elder Tung's hut",
		-- The pivot of the whole arc: the congratulation IS the reveal.
		Say = "You made it through. Sit. Warm your hands.\n\n" ..
		      "There is a cave under us. Not a hole in the ice -- a CAVE, older than the ice, " ..
		      "and something down there is still awake. I have listened to it for forty years " ..
		      "and I am too old to go and look.\n\n" ..
		      "You are not. But you will not claw through a mile of ice with your hands. " ..
		      "We are going to build a DRILL.",
		Done = "Then go. The ice gives up its scrap when you hit it hard enough.",
		Reward = {},
	},
	{
		Id = "Parts", Kind = "gather",
		Title = "Salvage the drill parts",
		Track = "Skip rocks to salvage drill parts",
		Say = "Five cogs, two gears, and one drill head. They are all out there in the ice -- " ..
		      "the wrecks left them. Your stones will turn them up. Skip, and keep your eyes open.",
		Nag = "Still short. Skip more. The ice is not going anywhere and neither am I.",
		Done = "That is everything. Give it here.",
		Reward = {},
	},
	{
		Id = "Build", Kind = "talk",
		Title = "Bring the parts to Elder Tung",
		Track = "Take the salvage to Elder Tung",
		Say = "Stand back.",
		Done = "There. One drill. It will chew through anything -- once we can START it.",
		Reward = { Cash = 50000000 },
		Cutscene = "DrillBuild",
	},
	{
		Id = "Fuel", Kind = "count", Counter = "Secrets", Target = 10,
		Title = "Fuel the drill",
		Track = "Catch %d/%d Secret brainrots to fuel the drill",
		-- Why Secrets are the fuel: it is the only resource in World 2 rare enough that
		-- ten of them is a real ask, and it keeps the last stage on the skip loop.
		Say = "It runs on the loud ones. The SECRETS -- the pink ones that scream. Ten of them, " ..
		      "and do not ask me how I know.",
		Nag = "Ten Secrets. Farthest throws you have got in you.",
		Done = "Ten. Feed them in.",
		Reward = { Darrels = 300 },
	},
	{
		Id = "Activate", Kind = "talk",
		Title = "Start the drill",
		Track = "Tell Elder Tung the drill is fuelled",
		Say = "Then we find out what I have been listening to.",
		Done = "It is open. Whatever is down there -- it knows you are coming.",
		Reward = { Cash = 100000000, Keys = 1 },
		Cutscene = "DrillStart",
		Unlock = true,   -- the stage that stamps M.RewardFlag
	},
}

M.Count = #M.Stages
M.DONE = M.Count + 1   -- stored state once the last stage is cleared

M.ByIndex = {}
M.IndexOfId = {}
for i, s in ipairs(M.Stages) do
	M.ByIndex[i] = s
	M.IndexOfId[s.Id] = i
end

-- === SALVAGE =================================================================
-- Order matters: this is the order the picker and the tracker list them in.
M.Parts = {
	{ Id = "Cog",       Label = "Cog",        Plural = "Cogs",  Count = 5 },
	{ Id = "Gear",      Label = "Gear",       Plural = "Gears", Count = 2 },
	{ Id = "Drillhead", Label = "Drill head", Plural = "Drill heads", Count = 1 },
}
M.PartById = {}
M.PartTotal = 0
for _, p in ipairs(M.Parts) do
	M.PartById[p.Id] = p
	M.PartTotal += p.Count
end

-- How salvage surfaces. A flat per-throw chance alone can strand an unlucky player on a
-- stage with no other way forward, so a dry streak is tracked and forced through: the
-- worst case is bounded at PART_PITY throws per part rather than unbounded.
M.PartChance = 0.18   -- per landed skip in the tundra while the Parts stage is live
M.PartPity   = 10     -- a partless streak this long makes the next skip a certainty

-- === REWARD ==================================================================
-- The flag Area 3 gates on. Nothing reads it yet -- like TungQuestConfig.RewardFlag was
-- before the cellar existed, this is the seam World 3 will hang off.
M.RewardFlag = "CaveUnlocked"
-- Set on the player (runtime only, re-granted on join) so a client-side hatch/shaft can
-- draw itself for the holder alone, the way CellarDoorClient does.
M.KeyAttribute = "HasCaveAccess"

-- === DIALOGUE THAT IS NOT PER-STAGE ==========================================
M.Intro = "You again. Come in, shut the door, you are letting the cold in."
M.Finished = "The shaft is open. Go down if you are going down -- I have said everything I know."
M.Locked = "Hmph. Come back when you have finished with my cellar."

return M
