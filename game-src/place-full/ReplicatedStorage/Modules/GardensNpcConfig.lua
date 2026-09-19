-- GardensNpcConfig: every World 3 voice except the Keeper's questline, as data.
--
-- ROLE IDS, NOT NAMES. Balkan has not locked the cast's names (board P6): code, prompts
-- and save data use the role id ("Elder", "Guard", ...), and the display name is one
-- string per role below, so renaming is a content change. The placeholder names sit in
-- the game's register (Rocco, Enzo, Gino, Marco, Gianluca) until he replaces them.
--
-- LINES ARE BUCKETED BY THE ARC, not by NPC state: nobody down here has their own
-- questline, they react to how far the player is through the Keeper's pages. Five
-- buckets plus the red night. Each bucket is 1-3 short lines; the lore is in the
-- DISAGREEMENTS between roles, never in one speech.
--
-- HOLDS: nobody explains why the war was lost (the Guard and the Soldier disagree; the
-- Deserter says "I know what I saw" and nothing else), nobody says what happened to the
-- twelve, nobody states a number of years, and the Ancient never speaks of what Tung heard.
-- All copy is DRAFT.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Quest = require(ReplicatedStorage.Modules.GardensQuestConfig)

local M = {}

-- WeatherHandler publishes the live event name here; the red-night bucket keys on it.
M.WeatherAttr = "WeatherName"
M.BloodMoonName = "Blood Moon"

-- Arc state -> bucket. Boundaries are stage ids, so reordering the arc cannot move
-- a line to the wrong moment.
local MID_FROM  = Quest.IndexOfId.Mural   -- the wall has been seen
local LATE_FROM = Quest.IndexOfId.Crypt   -- the crypt is in play
function M.BucketFor(state, done)
	if done then return "After" end
	if state == Quest.NONE then return "Before" end
	if state >= LATE_FROM then return "Late" end
	if state >= MID_FROM then return "Mid" end
	return "Early"
end

local HUMAN = "human"
local BRAINROT = "brainrot"

M.Roles = {
	Elder = {
		Name = "Nonna Ines",                       -- PLACEHOLDER
		Kind = HUMAN, PromptName = "ElderPrompt",
		Accent = { Color3.fromRGB(214, 168, 120), Color3.fromRGB(150, 96, 62) },
		Lines = {
			Before = {
				"You came down through the roof. On his machine.",
				"Do you know what that machine did up there? No. Nobody who rides one ever does.",
			},
			Early = {
				"The Keeper is reading you his pages. He read them to me once. I told him to burn them.",
				"He asked us for twelve, in the old days. Twelve, every time. Ask yourself where twelve of anything goes.",
			},
			Mid = {
				"You saw the wall. Ask the Sergeant who scratched it out. Then ask me.",
				"You will get two answers, and one of them is mine: we did it the day we understood.",
			},
			Late = {
				"Whatever is under that altar has hummed since before my mother.",
				"Do not open the second one. He said it too, once. It is the only thing we ever agreed on.",
			},
			After = {
				"He kept it. All this time, under our feet. He kept it.",
			},
			BloodMoon = {
				"Not tonight. Inside. Everyone, inside.",
			},
		},
	},

	Guard = {
		Name = "Sergeant Ottavio",                 -- PLACEHOLDER
		Kind = HUMAN, PromptName = "GuardPrompt",
		Accent = { Color3.fromRGB(190, 190, 176), Color3.fromRGB(108, 112, 104) },
		Lines = {
			Before = {
				"That machine. That ENGINE. I have not heard one since the war.",
				"Go up to the Keep. The Keeper will want to see you. Go.",
			},
			Early = {
				"He held the line. Whatever they tell you in the square, he held it until there was no line left to hold.",
				"A count. Of course a count. He always started with a count.",
			},
			Mid = {
				"The wall? Kids. Vandals. However many years of bored children with chisels. It was not us.",
			},
			Late = {
				"The crypt stair is behind me until the Keeper says otherwise. That is the one order I still have.",
			},
			After = {
				"I would have followed him up. He did not ask.",
			},
			BloodMoon = {
				"Off the walls. Nobody on the walls tonight.",
			},
		},
	},

	Youth = {
		Name = "Tino",                             -- PLACEHOLDER
		Kind = HUMAN, PromptName = "YouthPrompt",
		Accent = { Color3.fromRGB(150, 205, 96), Color3.fromRGB(86, 140, 60) },
		Lines = {
			Before = {
				"Is that yours? The thing in the roof? Does it go UP?",
				"Everything goes up. Nobody ever says what is there.",
			},
			Early = {
				"Nonna says he was bad. The Sergeant says he was the best of them. I say he was probably a person.",
			},
			Mid = {
				"The wall in the Keep has a hole in it where a person was. I used to think it was a window.",
			},
			Late = {
				"The Keeper keeps going down under the altar with a lamp. He comes up looking like he did not sleep.",
			},
			After = {
				"It went UP. I saw it go up. What is up there? Is HE up there?",
			},
			BloodMoon = {
				"Nonna says inside. I am not scared. I am going inside, though.",
			},
		},
	},

	Scavenger = {
		Name = "Vespa",                            -- PLACEHOLDER
		Kind = HUMAN, PromptName = "ScavengerPrompt",
		Accent = { Color3.fromRGB(198, 168, 104), Color3.fromRGB(134, 104, 52) },
		-- Her Late bucket is decided by the payload (caches found), see GardensNpcClient.
		Lines = {
			Before = {
				"Machines fall out of the roof, people fall out of the roof. I sell what the river gives back.",
			},
			Early = {
				"You want something? Bring me something. There are caches out there older than the town.",
			},
			Mid = {
				"Two of the old caches and I will tell you where the one who ran off hides. He owes me a helmet.",
			},
			Late = {
				"Two. Fine. Behind the fourth fall on the weeping cliff. Tell him the trader still wants her helmet.",
			},
			LateShort = {
				"Empty-handed? Two caches. I keep my prices.",
			},
			After = {
				"It went up. Things that go up come down. I will be here when it does.",
			},
			BloodMoon = {
				"I do not go out on the red nights. Nothing that fell from up there ever came down on a quiet one.",
			},
		},
	},

	Soldier = {
		Name = "Corporal Dario",                   -- PLACEHOLDER
		Kind = HUMAN, PromptName = "SoldierPrompt",
		Accent = { Color3.fromRGB(160, 150, 130), Color3.fromRGB(96, 86, 70) },
		Lines = {
			Before = {
				"You came down with a machine. The last time one of his came near me I lost a boot and a brother.",
			},
			Early = {
				"The Sergeant will tell you he held the line. I was on the line. I saw him leave it.",
			},
			Mid = {
				"I do not know what happened after he left. Nobody does. That is the part nobody says out loud.",
			},
			Late = {
				"Do what the Keeper reads you. Then leave. That is my advice, and I am the only one down here who gives it.",
			},
			After = {
				"There it goes. Up. Same as him.",
			},
			BloodMoon = {
				"Red night. Inside, or on the water. Never on the wall.",
			},
		},
	},

	Veteran = {
		Name = "Il Vecchio Bombardiro",            -- PLACEHOLDER (species TBD)
		Kind = BRAINROT, PromptName = "VeteranPrompt",
		Accent = { Color3.fromRGB(120, 140, 110), Color3.fromRGB(60, 80, 56) },
		-- Board P7-mod: implies the player is not the first; NEVER explains.
		Lines = {
			Before = { "...Another one?" },
			Early  = { "...Another one?", "He has a way of finding people who will go where he will not." },
			Mid    = { "Another one. And this one has seen the wall." },
			Late   = { "The tunnel is open. It was always open. I sit here so people ask before they go in." },
			After  = { "Tell him we are still here." },
			BloodMoon = { "..." },
		},
	},

	Deserter = {
		Name = "Il Disertore",                     -- PLACEHOLDER (species TBD)
		Kind = BRAINROT, PromptName = "DeserterPrompt",
		Accent = { Color3.fromRGB(140, 120, 150), Color3.fromRGB(80, 62, 96) },
		-- Late is the key hand-over; the client asks the server (GardensTalk "Deserter")
		-- and the server answers with note "key" or "deserternag" (see GardensQuest).
		Ask = "ASK FOR THE KEY \u{25B6}",
		Lines = {
			Before = { "You are a long way from the Keep. Did the trader send you? She still wants her helmet." },
			Early  = { "You are a long way from the Keep. Did the trader send you? She still wants her helmet." },
			Mid    = { "I know what I saw. I saw enough to leave. That is all anyone gets." },
			Late   = { "So you want the key. Everyone who comes down here eventually wants the key." },
			Key    = { "Take it. Open his door. Then ask yourself why a man who left us here left us a key." },
			NoKey  = { "The trader sent you empty-handed? Two of her caches, then the key. I keep my prices too." },
			After  = { "It went up. He always did like a way out." },
			BloodMoon = { "Red night. Nothing comes behind the falls on a red night. Except you, apparently." },
		},
	},

	Ancient = {
		Name = "Il Sussurro",                      -- PLACEHOLDER (species TBD)
		Kind = BRAINROT, PromptName = "AncientPrompt",
		Accent = { Color3.fromRGB(158, 234, 238), Color3.fromRGB(70, 128, 130) },
		-- Board P9 HOLD: speaks in questions, remembers the sealing, says nothing about
		-- what Tung heard or who heard whom.
		Lines = {
			Before = { "Do you know how old this stone is? Do you? Nobody who comes down the tunnel knows." },
			Early  = { "Do you know how old this stone is? Do you? Nobody who comes down the tunnel knows." },
			Mid    = { "Did they show you the wall? Did they tell you who is missing from it? Did they agree?" },
			Late   = { "When they sealed the room under the hall, did anyone ask what they were sealing in -- or out?" },
			After  = { "Did it go up? Did you watch it? Did anyone wave?" },
			BloodMoon = { "Why are you out tonight? Do you not feel it?" },
		},
	},
}

-- Stable iteration order for anything that lists them (dev output, audits).
M.Order = { "Elder", "Guard", "Youth", "Scavenger", "Soldier", "Veteran", "Deserter", "Ancient" }

return M
