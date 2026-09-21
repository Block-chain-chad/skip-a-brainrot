-- NpcDialogue.Gianluca -- everything Gianluca SAYS, and how he says it. Data only.
--
-- Old veteran, lorekeeper, field mentor. Fought alongside Elder Tung in the old war.
-- Concise, calm, observant, a little stern, reflective. He knows more than he says.
-- NpcTalk turns this table into a conversation for MerchantDialog (the game's one
-- NPC box); GianlucaClient is the glue. Nothing here is code.
--
-- Line entries: a string, or { text, tag = "war" | "clasp" | "mentor" }. A tag maps to a
-- reaction id in `reactions` -- NpcLife plays it on the body through the NpcReaction
-- attribute when the line is spoken (the Elder Tung / war / old-army beat: he stops,
-- tightens his grip, looks away). Keep every line short: one breath, one thought.

return {
	id = "Gianluca",
	name = "Gianluca",                       -- the name ribbon on the box (was "stupid gianluca")
	role = "Old veteran · lorekeeper · field mentor",
	-- MerchantDialog accent (name ribbon gradient): tarnished brass over iron, not gold
	accent = { Color3.fromRGB(196, 170, 118), Color3.fromRGB(122, 104, 72) },
	-- the live TalkPrompt is kept (contract); these are the values to VERIFY on it at the
	-- window, and the defaults for any NEW prompt the kit ever makes for him
	prompt = { actionText = "Talk", objectText = "Gianluca", maxActivationDistance = 10, holdDuration = 0.3, requiresLineOfSight = false },
	-- attribute the body driver listens to (NpcLife); tags below resolve through it
	reactions = { war = "warMemory" },

	-- ===== the voice ========================================================================
	-- first meeting: one greeting is chosen per player and stays theirs
	greetings = {
		"You carry yourself like someone who hasn't learned fear yet.",
		"New face. This valley gets a few. Most don't stay long enough to be worth knowing.",
		"Don't stand behind me. Old habit. Nothing personal.",
	},
	-- every later conversation opens with one of these, in turn
	returning = {
		"Back again? Good. Means you survived something.",
		"Still in one piece. That puts you ahead of most.",
		"The river's louder today. Stay if you like. I'm not going anywhere.",
	},
	-- lore rotates: every line is heard once before any repeats
	lore = {
		{ "Tung and I once stood where no sane man would have stayed. We stayed anyway.", tag = "war" },
		{ "People remember the victory. They rarely remember what it cost.", tag = "war" },
		{ "This clasp? Older than you. It meant something, once. Maybe it still does.", tag = "clasp" },
		{ "The old army marched through here. You'd never know it now. Grass forgets faster than men.", tag = "war" },
	},
	-- one of these instead of lore every third conversation
	guidance = {
		{ "Keep your eyes open. The world usually warns you before it hurts you.", tag = "mentor" },
		{ "Skip your rocks with intent. A throw with no purpose teaches you nothing.", tag = "mentor" },
	},
	guidanceEvery = 3,

	-- ===== the existing Chim quest, in his voice (mechanics unchanged) ============================
	-- Stages mirror data.ChimQuest on the server: 0 not started, 1 searching, 2 holding, 3 done.
	-- `action` is what the client fires on the primary button (GianlucaTalk remote):
	-- nil = just close, "start" = begin the hunt, "handover" = give the Chim back.
	quest = {
		offer = {                          -- state 0: folded into the first conversation
			lines = { "I lost something. A Chim. Small, quick, too clever for its own good. It slipped its collar somewhere along the shore.",
			          "Find it and bring it here. I'll make it worth your while." },
			label = "I'LL LOOK ▶", action = "start",
		},
		searching = {                      -- state 1
			lines = { "Still out there. Check the water's edge. It never strayed far from the sound of the river." },
			label = "KEEP LOOKING ▶",
		},
		holding = {                        -- the player has an unplaced Chim (any state)
			lines = { "That's him. Hand him over. Gently.", "Take this key for the trouble. It opens something I no longer need." },
			label = "HAND OVER THE CHIM ▶", action = "handover",
		},
		done = {                           -- state 3: the collar on his belt stays empty on purpose
			lines = { "You brought him back when you didn't have to. I don't forget that." },
			label = "OK ▶",
		},
		-- server notes (GianlucaState.Note); the SECRET CHIM popups are system messages, not his voice
		notes = {
			key   = { name = "Gianluca", lines = { "The key. It's old, and it's yours now. What it opens is your business." }, label = "TAKE THE KEY ▶" },
			found = { name = "✨ SECRET CHIM ✨", lines = { "You found the Secret Chim. A Mythic brainrot, the only one of its kind. Gianluca will trade you a key for it." }, label = "AWESOME! ▶" },
			hint  = { name = "✨ Secret Chim", lines = { "Someone must be looking for this shiny thing... maybe ask around the camp?" }, label = "OK ▶" },
		},
	},

	-- ===== hooks for later content (no logic here; NpcTalk reads `sets` if a quest adds them) ====
	hooks = {
		-- future quest ids a lane may switch on; each would add a `sets[<id>] = { [stage] = {lines, label, action} }` table
		veteranChallenge = false,
		trainingObjective = false,
		warRelic = false,
		tungStory = false,
		secretHint = false,
		-- the persistent "met before" flag lives in PlayerDataManager once a lane adds it; until then
		-- the client remembers within a session and the Chim state stands in for "returning"
		persistMet = "GianlucaMet",
	},
	sets = {},
}
