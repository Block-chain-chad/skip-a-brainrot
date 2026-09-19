# World 3 Story Spine Implementation Plan (Plan 1 of the World 3 roadmap)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Author the World 3 questline "The Old Orders" and its NPC dialogue data as lane-owned Lua files on disk, plus the exact shared-file deltas they need — everything that can be written without Studio.

**Architecture:** A structural copy of the tundra trio: one shared config (`GardensQuestConfig`) read by a server state machine (`GardensQuest`), a Keeper conversation client (`GardensQuestClient`) and the tracker row; plus a data-only NPC config (`GardensNpcConfig`) drawn by one generic walk-up client (`GardensNpcClient`). Shared files (`ThrowHandler`, `Main`, `PlayerDataManager`, `DevQuest`, `QuestTrackerClient`) get additive splices documented as patches and applied **live through the bridge** at the Studio window, never from the mirror.

**Tech Stack:** Roblox Luau (ModuleScripts / Scripts / LocalScripts), the existing `MerchantDialog` shell, `ProximityPrompt`s (auto-styled by the Round-3 kit prompt), `RemoteEvent`s, `PlayerDataManager` profiles.

## Roadmap (which plan does what, and what gates it)

| Plan | Scope | Needs Studio? |
|---|---|---|
| **1 (this)** | Quest config + server + Keeper client, NPC dialogue config + client, dev verbs, shared-file delta patches | No — apply at the window |
| 0 | Opening blockers: `NAV.Gardens`, `campWorld`, return-portal label, per-world respawn coordination | Yes (live edits) |
| 2 | NPC placement: rigs, `PromptPart`s, `NpcIdle` profiles for the three brainrot NPCs, `LushGardens.Npcs` folder | Yes (inspection items 1–2 first) |
| 3 | `BuildStory.lua`: arrival breakthrough, Town re-dress, Keep interior (banners, mural, war table, crypt, doors, lever, horn), region dressing; `Optimize.run()` | Yes (items 1, 3, 4) |
| 4 | `SentinelHour` service + client FX, Rootway `ThrowZone` + `ZoneLuck`, escape tunnel + rockfall, `GardensCaches` pickups | Yes (item 3) |
| 5 | `StoryCinematic` + the six beats | Yes (items 1, 5) |
| 6 | `BuildLaunch.lua`, the Launch cut, the `Moon` portal seam | Yes |
| 7 | Economy (report-first, P19-mod): ladder / roster / rocks | Balkan's decision first |

## Global Constraints

- **Nothing in Studio is touched by this plan.** Files are authored under `game-src/place-full/` in the `world3-refinement` worktree; they become live only at the Studio window, where they are created in Studio and pushed back through `tools/studio-bridge/bridge.py` byte-exact (team rule in `game-src/place-full/README.md`).
- **Shared files are never edited from the mirror.** Every splice in Task 7 is applied to the *live* Source at the window; the mirror is then re-pushed so the branch carries only the World 3 delta.
- **Locked Round-3 surfaces** (`MerchantDialog`, `UIKit.QuestCard`, `InteractionPrompt`, `InteractionPromptClient`, `QuestTrackerClient`, `QuestBarClient`) are not modified except the one additive `QuestTrackerClient` row in Task 7, which needs Balkan's OK before it is applied.
- **Holds** (board Part D): no crescent/moon sigil anywhere; NPC display names are placeholders (`Name` strings only, role ids in code); no line states why the war was lost; no line ties the Ancient to Tung's listening; no line states a number of years; nobody says what happened to the twelve.
- **Rewards are placeholders**: the tundra arc's own numbers copied verbatim, marked `PLACEHOLDER`, for Balkan to set.
- **No local Luau toolchain exists** on this machine: each task ends with a static check (grep) and a commit; Task 8 is the Studio verification, gated on the inspection window.
- Mirror files are byte-exact (`*.lua -text`); write them with LF line endings and a trailing newline, tabs for indentation, matching the codebase.
- Lines addressed to the player are **1–3 sentences**; the Keeper's stage lines may be up to 3 sentences.

---

### Task 1: `GardensQuestConfig` — the arc's shape and the Keeper's words

**Files:**
- Create: `game-src/place-full/ReplicatedStorage/Modules/GardensQuestConfig.lua`

**Interfaces:**
- Consumes: nothing (pure data).
- Produces: `M.NpcRole`, `M.PromptName`, `M.WorldName`, `M.NONE`, `M.Stages[i] = { Id, Kind, Title, Track, Say, Nag?, Ready?, Done, Reward, Counter?, Target?, Gated?, Flag?, Cutscene?, Unlock? }`, `M.Count`, `M.DONE`, `M.ByIndex`, `M.IndexOfId`, `M.Relics`, `M.RelicById`, `M.RelicTotal`, `M.RelicChance`, `M.RelicPity`, `M.CachesForKey`, `M.KeyFlag`, `M.RewardFlag`, `M.KeyAttribute`, `M.SentinelAttr`, `M.CutsceneWait`, `M.Intro`, `M.Finished`, `M.Locked`, `M.Accent`.

- [ ] **Step 1: Write the module**

```lua
-- GardensQuestConfig: "THE OLD ORDERS" -- Elder Tung's World 3 arc, run by proxy.
--
-- NOT TundraQuestConfig. That is the World 2 arc (the trials and the drill), and it is
-- finished the moment a player comes down the shaft. This is what waits at the bottom.
-- Tung is not down here (design §1, board P5): the KEEPER of the Keep holds the orders
-- Tung left the night the town fell, and reads them a page at a time to whoever came
-- down with the machine. The player is identified by THE DRILL, not by any token
-- (board P1-mod) -- the auger through the chamber roof is the whole introduction.
--
-- SHARED because three places have to agree on the same numbers -- the server state
-- machine (ServerScriptService.Modules.GardensQuest), the Keeper's dialogue on the
-- client (GardensQuestClient), and the quest tracker row. Same rule as the tundra: a
-- quota stated twice is a quota that will eventually disagree.
--
-- HOLDS HONOURED HERE (docs/WORLD3-CURRENT-STATE-AND-REFINEMENT.md Part D): no emblem,
-- no count of years, nobody explains why the war was lost, nobody says what the Ancient
-- is, nobody says what happened to the twelve. Every player-facing line is DRAFT copy.
-- Every Reward number is the tundra arc's own, copied as a PLACEHOLDER for Balkan.
local M = {}

M.NpcRole = "Keeper"            -- role id; the display name lives in GardensNpcConfig
M.PromptName = "KeeperPrompt"   -- ProximityPrompt under Workspace.GameWorld.LushGardens
M.WorldName = "Gardens"         -- BoundsGuard region: the only world whose skips count here

-- The Keeper's accent pair (moss and old bronze) -- the card and the ribbon share it.
M.Accent = { Color3.fromRGB(156, 178, 136), Color3.fromRGB(88, 118, 86) }

-- === STATE ===================================================================
-- data.GardensQuest is an INDEX INTO M.Stages, 0 = never spoken to. Counters live in
-- data.GardensProgress and data.GardensRelics and only ever count UP -- "150 catches"
-- has to survive selling all 150, exactly as the tundra's trials do.
M.NONE = 0

-- Kinds:
--   "count"  a counter on data.GardensProgress reaching Target, ticked by the catch
--            hook. A stage with Gated = <attribute name> ticks ONLY while
--            ReplicatedStorage carries that attribute == true (the bell).
--   "gather" the data.GardensRelics quota below; relics surface while skipping
--   "talk"   a beat that advances purely by talking to the Keeper
--   "flag"   like "talk", but the Keeper will not clear it until data[Flag] == true
M.Stages = {
	{
		Id = "Orders", Kind = "talk",
		Title = "Report to the Keeper",
		Track = "Find the Keeper in the Keep",
		Say = "The old orders. He wrote them the night the town fell and told me the first " ..
		      "page was for whoever came through the roof. Nobody ever did. Until the machine.",
		Done = "The first page is a count. It is always a count.",
		Reward = {},
	},
	{
		Id = "Muster", Kind = "count", Counter = "Catches", Target = 150,
		Title = "The count",
		Track = "Catch %d/%d brainrots in the Gardens",
		Say = "One hundred and fifty, out of the river. From the causeway -- it is the only " ..
		      "water down here that still takes a stone.",
		Nag = "The count is not done. He would not have skipped it, and I will not either.",
		Done = "One hundred and fifty. Page two.",
		Reward = { Cash = 5000000 },          -- PLACEHOLDER (tundra Trial1)
	},
	{
		Id = "Relics", Kind = "gather",
		Title = "Turn up the relics",
		Track = "Skip rocks to turn up the captains' relics",
		Say = "Six things the captains carried, lost in the river the day the town fell. " ..
		      "Three banner scraps, two helms, one signal horn. Your stones will turn them up.",
		Nag = "Still short. The river gives back what it is hit hard enough.",
		Done = "All six. Do not hand them to me. Carry them in -- you will want to see where they go.",
		Reward = {},
	},
	{
		Id = "Mural", Kind = "talk",
		Title = "Bring the relics to the Keep",
		Track = "Take the relics to the Keeper",
		Say = "Stand where I stand. Look up.",
		Done = "That is them. That WAS them. Page three.",
		Reward = { Cash = 50000000 },         -- PLACEHOLDER (tundra Build)
		Cutscene = "Mural",
	},
	{
		Id = "Bell", Kind = "count", Counter = "BellCatches", Target = 3, Gated = "SentinelActive",
		Title = "Skip under the bell",
		Track = "Land %d/%d catches while the bell rings",
		Say = "Page three is not a page. It is the bell. When it rings, the walls remember " ..
		      "they are walls and they defend the river against whatever is on it. Three " ..
		      "catches, under the bell. Do not stand still.",
		Nag = "Wait for the bell. Then do not wait.",
		Done = "Three, under the bell. Either you are lucky, or you are the kind he sends.",
		Reward = { Darrels = 300 },           -- PLACEHOLDER (tundra Fuel)
	},
	{
		Id = "Crypt", Kind = "flag", Flag = "CryptKey",
		Title = "The first door",
		Track = "Find who holds the crypt key",
		Say = "Page four wants a key. I have never had it. Someone took it the day he left " ..
		      "-- the trader in the mushrooms knows who. She will want paying.",
		Nag = "No key, no door. Two of her caches and she will tell you where he hides.",
		Ready = "You have it. No -- keep it in your hand. Stand back.",
		Done = "That key. I never thought I would see it again.",
		Reward = { Darrels = 150 },           -- PLACEHOLDER (tundra Trial2's gems)
		Cutscene = "SecondDoor",
	},
	{
		Id = "Launch", Kind = "talk",
		Title = "The last page",
		Track = "Return to the Keeper",
		Say = "One page left. I have read it a hundred times and understood none of it. " ..
		      "We read it together.",
		Done = "It is done. I do not know what I have done.",
		Reward = { Cash = 100000000, Keys = 1 }, -- PLACEHOLDER (tundra Activate)
		Cutscene = "Launch",
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

-- === RELICS ==================================================================
-- Order matters: this is the order the tracker lists them in. Same idiom as the drill
-- salvage (TundraQuestConfig.Parts): a quota per kind, surfaced by skipping, bounded
-- by a pity streak so an unlucky player is never stranded on this stage.
M.Relics = {
	{ Id = "Banner", Label = "Banner scrap", Plural = "Banner scraps", Count = 3 },
	{ Id = "Helm",   Label = "Helm",         Plural = "Helms",         Count = 2 },
	{ Id = "Horn",   Label = "Signal horn",  Plural = "Signal horns",  Count = 1 },
}
M.RelicById = {}
M.RelicTotal = 0
for _, r in ipairs(M.Relics) do
	M.RelicById[r.Id] = r
	M.RelicTotal += r.Count
end
M.RelicChance = 0.20   -- per landed skip in the Gardens while the Relics stage is live
M.RelicPity   = 8      -- a relicless streak this long makes the next skip a certainty

-- === THE KEY =================================================================
-- Stage 6 is cleared by a flag, not a counter: the Deserter grants data.CryptKey once
-- the player has found CachesForKey of the Scavenger's caches (data.GardensCaches, a set
-- of cache ids written by the cache pickups -- a later plan; until then the dev verb
-- `/tq gardens caches <n>` stands in).
M.KeyFlag = "CryptKey"
M.CachesForKey = 2

-- === REWARD ==================================================================
-- The flag World 4 gates on. Nothing reads it yet -- like CaveUnlocked was before the
-- shaft existed, this is the seam the launch pad will hang off.
M.RewardFlag = "RocketUnlocked"
-- Set on the player (runtime only, re-granted on join), the way HasCaveAccess is.
M.KeyAttribute = "HasRocketAccess"

-- ReplicatedStorage attribute the Sentinel Hour service (a later plan) sets while the
-- bell rings. The Bell stage reads it through the stage's own Gated field.
M.SentinelAttr = "SentinelActive"

-- How long the Keeper's box waits after a cutscene note before speaking again --
-- matches TundraQuestClient's 6.5 s; the cuts here are 8-20 s, so the client reads
-- the real length from StoryCinematic when that module exists and falls back to this.
M.CutsceneWait = 6.5

-- === DIALOGUE THAT IS NOT PER-STAGE ==========================================
M.Intro = "You came down with the machine. I know that engine -- there has not been one " ..
	"like it down here since the war. Whoever came down with it, he said, gets the orders. " ..
	"Nobody ever did. Until you."
M.Finished = "The orders are finished. I have nothing left to read you, and I would not if I had."
M.Locked = "You did not come down with the machine. Then I have nothing for you."

return M
```

- [ ] **Step 2: Static check**

Run:
```bash
cd C:/Users/m/Coding/skip-a-brainrot-world3/game-src/place-full && f=ReplicatedStorage/Modules/GardensQuestConfig.lua && echo "stages=$(grep -c 'Id = "' $f)" && grep -c 'Kind = "count"' $f && grep -c 'Gated = "SentinelActive"' $f && grep -c 'Cutscene = "' $f && (grep -qiE 'crescent|sigil|warship|forty' $f && echo "HOLD VIOLATION" || echo "holds ok") && file $f | grep -q CRLF && echo "CRLF!" || echo "LF ok"
```
Expected: `stages=10` (7 stages + 3 relics), `2`, `1`, `3`, `holds ok`, `LF ok`.

- [ ] **Step 3: Commit**

```bash
cd C:/Users/m/Coding/skip-a-brainrot-world3 && git add game-src/place-full/ReplicatedStorage/Modules/GardensQuestConfig.lua && git commit -m "feat(world3): GardensQuestConfig -- The Old Orders (7 stages, relics, Keeper lines; rewards placeholder)"
```

---

### Task 2: `GardensNpcConfig` — every other World 3 voice, as data

**Files:**
- Create: `game-src/place-full/ReplicatedStorage/Modules/GardensNpcConfig.lua`

**Interfaces:**
- Consumes: `GardensQuestConfig.IndexOfId`, `.DONE` (to bucket lines by arc state).
- Produces: `M.Roles[roleId] = { Name, Kind, PromptName, Accent, Lines = { Before, Early, Mid, Late, After, BloodMoon }, Final?, Ask? }`, `M.Order`, `M.BucketFor(state, done)`, `M.WeatherAttr`, `M.BloodMoonName`.

- [ ] **Step 1: Write the module**

```lua
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
```

- [ ] **Step 2: Static check**

Run:
```bash
cd C:/Users/m/Coding/skip-a-brainrot-world3/game-src/place-full && f=ReplicatedStorage/Modules/GardensNpcConfig.lua && for r in Elder Guard Youth Scavenger Soldier Veteran Deserter Ancient; do n=$(awk -v r="$r" 'index($0, "\t" r " = {")==1{f=1} f{print} f && $0=="\t},"{f=0}' $f | grep -cP '^\t\t\t(Before|Early|Mid|Late|After|BloodMoon)\s+= \{'); echo "$r buckets=$n"; done && (grep -qiE 'crescent|sigil|warship|forty|listen' $f && echo "HOLD VIOLATION" || echo "holds ok") && (grep -q $'\r' $f && echo "CRLF!" || echo "LF ok")
```
Expected: every role `buckets=6`, `holds ok`, `LF ok`. (`listen` is grepped so the P9 hold cannot creep in through a rewrite.)

- [ ] **Step 3: Commit**

```bash
cd C:/Users/m/Coding/skip-a-brainrot-world3 && git add game-src/place-full/ReplicatedStorage/Modules/GardensNpcConfig.lua && git commit -m "feat(world3): GardensNpcConfig -- eight roles, bucketed draft lines, placeholder names"
```

---

### Task 3: `GardensQuest` — the server state machine

**Files:**
- Create: `game-src/place-full/ServerScriptService/Modules/GardensQuest.lua`

**Interfaces:**
- Consumes: `GardensQuestConfig` (Task 1); `PlayerDataManager.Get/GrantCash/PushUpdate/Save`; `EmeraldService.Award(player, n, reason)`; `ReplicatedStorage.Remotes` (`PurchaseResult` for toasts).
- Produces: `GardensQuest.Init()`, `GardensQuest.Interact(player, role)`, `GardensQuest.NotifyCatch(player, tierName, world)`, `GardensQuest.AddCache(player, cacheId) -> boolean`, `GardensQuest.SendState(player, note?, extra?)`, remotes `GardensTalk` (C→S, `role: string`) and `GardensState` (S→C payload `{ State, Step, Of, StageId, Kind, Title, Track, Met, Parts, Stages, Done, Unlocked, Caches, CryptKey, Note, Cleared?, Salvage? }`).

- [ ] **Step 1: Write the module**

```lua
-- GardensQuest: "The Old Orders" -- Elder Tung's World 3 arc, read by the Keeper.
--
-- The shape lives in ReplicatedStorage.Modules.GardensQuestConfig; this module is the
-- authority on where a given player IS in it. Read that file first, then this one. It is
-- a structural copy of TundraQuest, with three additions: a stage kind that waits on a
-- FLAG (the crypt key), a count stage that only ticks while an attribute is set (the
-- bell), and a talk remote that names WHICH World 3 character was spoken to.
--
-- STATE. data.GardensQuest is an INDEX into GardensQuestConfig.Stages:
--   0                  not accepted (the Keeper has not been spoken to)
--   1..Config.Count    working on that stage
--   Config.DONE        finished; RocketUnlocked stamped, rocket access granted
--
--   data.GardensProgress = { Catches = n, BellCatches = n }
--   data.GardensRelics   = { Banner = n, Helm = n, Horn = n }
--   data.GardensDry      = relicless skips in a row, for the pity
--   data.GardensCaches   = { [cacheId] = true }  written by the cache pickups
--   data.CryptKey        = true once the Deserter has handed it over
--
-- Counters tick only while THEIR OWN stage is live and are never rebuilt from the
-- inventory -- the same rule the tundra learned the hard way.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local EmeraldService = require(ServerScriptService.Modules.EmeraldService)
local Config = require(ReplicatedStorage.Modules.GardensQuestConfig)

local remotes = ReplicatedStorage.Remotes

local GardensQuest = {}

local function getRemote(name, class)
	local r = remotes:FindFirstChild(name)
	if not r then r = Instance.new(class); r.Name = name; r.Parent = remotes end
	return r
end
local talkRemote  = getRemote("GardensTalk", "RemoteEvent")
local stateRemote = getRemote("GardensState", "RemoteEvent")

local function notify(player, ok, msg)
	local r = remotes:FindFirstChild("PurchaseResult")
	if r then r:FireClient(player, { Success = ok, Message = msg }) end
end

-- === DATA ====================================================================
local function stageIndex(data)
	local n = math.floor(tonumber(data.GardensQuest) or 0)
	if n < 0 then n = 0 end
	if n > Config.DONE then n = Config.DONE end
	if data.GardensQuest ~= n then data.GardensQuest = n end
	return n
end

local function progress(data)
	local p = data.GardensProgress
	if type(p) ~= "table" then p = {}; data.GardensProgress = p end
	for _, s in ipairs(Config.Stages) do
		if s.Counter then p[s.Counter] = math.max(0, math.floor(tonumber(p[s.Counter]) or 0)) end
	end
	return p
end

local function relics(data)
	local t = data.GardensRelics
	if type(t) ~= "table" then t = {}; data.GardensRelics = t end
	for _, r in ipairs(Config.Relics) do
		t[r.Id] = math.clamp(math.floor(tonumber(t[r.Id]) or 0), 0, r.Count)
	end
	return t
end

local function caches(data)
	local c = data.GardensCaches
	if type(c) ~= "table" then c = {}; data.GardensCaches = c end
	return c
end

local function cacheCount(data)
	local n = 0
	for _ in pairs(caches(data)) do n += 1 end
	return n
end

-- === STAGE MATHS =============================================================
-- One shape for every stage kind: Cur/Of is always the bar, Met is always the gate.
local function stageView(data, index)
	local s = Config.ByIndex[index]
	if not s then return nil end
	if s.Kind == "count" then
		local cur = math.min(progress(data)[s.Counter] or 0, s.Target)
		return { Cur = cur, Of = s.Target, Met = cur >= s.Target }
	elseif s.Kind == "gather" then
		local have, all = relics(data), true
		local cur = 0
		local list = {}
		for _, r in ipairs(Config.Relics) do
			local n = have[r.Id] or 0
			cur += n
			if n < r.Count then all = false end
			list[#list + 1] = { Id = r.Id, Label = r.Label, Plural = r.Plural, Have = n, Need = r.Count }
		end
		return { Cur = cur, Of = Config.RelicTotal, Met = all, Parts = list }
	elseif s.Kind == "flag" then
		local has = data[s.Flag] == true
		return { Cur = has and 1 or 0, Of = 1, Met = has, Talk = true }
	end
	-- "talk": nothing to grind, met the moment it is the Keeper's turn to speak
	return { Cur = 0, Of = 1, Met = true, Talk = true }
end

local function payReward(player, data, reward)
	if type(reward) ~= "table" then return end
	if reward.Cash and reward.Cash > 0 then
		PlayerDataManager.GrantCash(data, reward.Cash)
	end
	if reward.Keys and reward.Keys > 0 then
		data.Keys = (tonumber(data.Keys) or 0) + reward.Keys
	end
	-- Gems go through EmeraldService: it owns that balance and pushes its own HUD
	-- update, so paying them by hand here would desync the gem pill.
	if reward.Darrels and reward.Darrels > 0 then
		pcall(EmeraldService.Award, player, reward.Darrels, "gardensquest")
	end
end

-- === ROCKET ACCESS ===========================================================
-- Runtime-only attribute, re-granted on every join for anyone already finished --
-- exactly like HasCaveAccess, and for the same reason.
local ROCKET_ATTR = Config.KeyAttribute or "HasRocketAccess"
local function grantRocketAccess(player) player:SetAttribute(ROCKET_ATTR, true) end

-- === STATE PUSH ==============================================================
local function buildPayload(data)
	local index = stageIndex(data)
	local done = index >= Config.DONE
	local view = (not done) and stageView(data, index) or nil
	local stage = Config.ByIndex[index]
	-- FIELD NAMES ARE THE TRACKER'S: State / Step / Of are what QuestTrackerClient reads
	-- for every questline; the rest is for the World 3 clients.
	return {
		State = index,
		Step = view and view.Cur or 0,
		Of = view and view.Of or 0,
		StageId = stage and stage.Id or (done and "Done" or "None"),
		Kind = stage and stage.Kind or nil,
		Title = stage and stage.Title or nil,
		Track = stage and stage.Track or nil,
		Met = view and view.Met or false,
		Parts = view and view.Parts or nil,
		Stages = Config.Count,
		Done = done,
		Unlocked = data[Config.RewardFlag] and true or false,
		Caches = cacheCount(data),
		CryptKey = data[Config.KeyFlag] == true,
	}
end

local function sendState(player, note, extra)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local payload = buildPayload(data)
	payload.Note = note
	if type(extra) == "table" then
		for k, v in pairs(extra) do payload[k] = v end
	end
	stateRemote:FireClient(player, payload)
end
GardensQuest.SendState = sendState

-- === ADVANCING ===============================================================
-- Finishing a stage pays its reward and moves the index on. Loops, because clearing a
-- count stage can leave the player on the next one already satisfied.
--
-- "talk" AND "flag" stages are NEVER auto-completed: they are the story beats, and they
-- only happen with the Keeper in the room. allowTalk is spent on the FIRST completion --
-- one press of E is one beat.
local function completeStage(player, data, index)
	local stage = Config.ByIndex[index]
	if not stage then return end
	payReward(player, data, stage.Reward)
	data.GardensQuest = index + 1
	if stage.Unlock then
		data[Config.RewardFlag] = true
		grantRocketAccess(player)
	end
end

local function advance(player, data, allowTalk)
	local moved, cutscene = false, nil
	while true do
		local index = stageIndex(data)
		if index == Config.NONE or index >= Config.DONE then break end
		local stage = Config.ByIndex[index]
		local view = stageView(data, index)
		if not view.Met then break end
		if view.Talk and not allowTalk then break end
		completeStage(player, data, index)
		if stage.Cutscene then cutscene = stage.Cutscene end
		moved = true
		allowTalk = false
	end
	if moved then PlayerDataManager.PushUpdate(player) end
	return moved, cutscene
end

-- === TALKING =================================================================
-- The Keeper: the arc itself.
local function interactKeeper(player, data)
	-- The only way into the Gardens is the shaft the tundra arc opens, so this can only
	-- fail for a player teleported here by a test hook -- but a half-started arc would be
	-- worse than a refusal.
	if not data.CaveUnlocked then
		notify(player, false, Config.Locked)
		sendState(player, "locked")
		return
	end

	local index = stageIndex(data)
	if index >= Config.DONE then
		sendState(player, "finished")
		return
	end

	if index == Config.NONE then
		data.GardensQuest = 1
		progress(data)
		relics(data)
		PlayerDataManager.PushUpdate(player)
		sendState(player, "accept")
		return
	end

	local before = Config.ByIndex[index]
	local moved, cutscene = advance(player, data, true)
	if moved then
		sendState(player, cutscene and ("cutscene:" .. cutscene) or "advance", { Cleared = before.Id })
		if stageIndex(data) >= Config.DONE then
			-- The arc ends by creating a permanent unlock, so the write is audited rather
			-- than left to the autosave.
			if not PlayerDataManager.Save(player) then
				warn(("[GardensQuest] SAVE FAILED after rocket unlock: %s uid=%d")
					:format(player.Name, player.UserId))
			end
		end
	else
		sendState(player, "nag")
	end
end

-- The Deserter: hands over the crypt key once the Scavenger's price has been paid.
-- Everything else about him is client-side flavour; this is the one thing that has to
-- be true on the server.
local function interactDeserter(player, data)
	local index = stageIndex(data)
	local cryptIndex = Config.IndexOfId.Crypt
	if index ~= cryptIndex then
		sendState(player, "deserter")
		return
	end
	if data[Config.KeyFlag] == true then
		sendState(player, "key")
		return
	end
	if cacheCount(data) < Config.CachesForKey then
		sendState(player, "deserternag")
		return
	end
	data[Config.KeyFlag] = true
	PlayerDataManager.PushUpdate(player)
	notify(player, true, "\u{1F5DD} The Deserter hands you the crypt key.")
	sendState(player, "key")
end

local function interact(player, role)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	if role == nil or role == Config.NpcRole then
		interactKeeper(player, data)
	elseif role == "Deserter" then
		interactDeserter(player, data)
	else
		-- every other role is client-only flavour; a stray call is answered with the
		-- current state so a client that asked never waits on nothing
		sendState(player, "state")
	end
end
GardensQuest.Interact = interact

-- === HOOKS ===================================================================
-- Called from ThrowHandler.revealCatch for EVERY landed skip (pcall'd there, so nothing
-- in here can cost a player their catch).
local function bumpCounter(data, stage, n)
	local p = progress(data)
	p[stage.Counter] = math.min(stage.Target, (p[stage.Counter] or 0) + n)
	return p[stage.Counter] >= stage.Target
end

-- Which relic to hand over: weighted by what is still OUTSTANDING, so the single horn
-- is not three times rarer than a banner scrap just because there is one of it.
local function rollRelic(have)
	local pool, total = {}, 0
	for _, r in ipairs(Config.Relics) do
		local left = r.Count - (have[r.Id] or 0)
		if left > 0 then
			pool[#pool + 1] = { id = r.Id, w = left }
			total += left
		end
	end
	if total == 0 then return nil end
	local roll = math.random() * total
	for _, e in ipairs(pool) do
		roll -= e.w
		if roll <= 0 then return e.id end
	end
	return pool[#pool].id
end

function GardensQuest.NotifyCatch(player, tierName, world)
	if world ~= Config.WorldName then return end
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local index = stageIndex(data)
	if index == Config.NONE or index >= Config.DONE then return end
	local stage = Config.ByIndex[index]
	if not stage then return end

	local note, extra = nil, nil

	if stage.Kind == "count" then
		-- The bell: a gated counter only ticks while the attribute the Sentinel Hour
		-- service publishes is true. Read at reveal time, so a catch that LANDS as the
		-- bell stops does not count -- the player was told not to stand still.
		if stage.Gated and ReplicatedStorage:GetAttribute(stage.Gated) ~= true then return end
		bumpCounter(data, stage, 1)
		note = "progress"
	elseif stage.Kind == "gather" then
		local have = relics(data)
		local dry = math.floor(tonumber(data.GardensDry) or 0)
		local lucky = (math.random() < Config.RelicChance) or (dry + 1 >= Config.RelicPity)
		local got = lucky and rollRelic(have) or nil
		if got then
			have[got] = math.min(Config.RelicById[got].Count, (have[got] or 0) + 1)
			data.GardensDry = 0
			note = "salvage"
			extra = { Salvage = got }
			local def = Config.RelicById[got]
			notify(player, true, ("\u{1F3F7} Your stone turned up a %s! (%d/%d)")
				:format(def.Label, have[got], def.Count))
		else
			data.GardensDry = dry + 1
			return   -- nothing changed worth a push
		end
	else
		return   -- a talk or flag stage: skipping does not move it
	end

	-- A finished counter rolls straight into the next stage without the Keeper. Only
	-- the story beats need him.
	local moved = advance(player, data, false)
	if moved then
		notify(player, true, (stage.Done or "Done.") .. "  \u{2014} go and see the Keeper.")
	end
	PlayerDataManager.PushUpdate(player)
	sendState(player, moved and "stagedone" or note, extra)
end

-- Called by the cache pickups (a later plan) and by the dev verb. Returns true if the
-- cache was new. Caches are a SET keyed by id, so a pickup can fire twice safely.
function GardensQuest.AddCache(player, cacheId)
	if type(cacheId) ~= "string" or cacheId == "" then return false end
	local data = PlayerDataManager.Get(player)
	if not data then return false end
	local c = caches(data)
	if c[cacheId] then return false end
	c[cacheId] = true
	PlayerDataManager.PushUpdate(player)
	notify(player, true, ("\u{1F4E6} You found one of the trader's caches. (%d)"):format(cacheCount(data)))
	sendState(player, "cache")
	return true
end

function GardensQuest.Init()
	-- one action per quarter second per player, matching every other questline's guard
	local lastAction = {}
	talkRemote.OnServerEvent:Connect(function(player, role)
		local now = os.clock()
		if now - (lastAction[player] or 0) < 0.25 then return end
		lastAction[player] = now
		if role ~= nil and typeof(role) ~= "string" then return end
		interact(player, role)
	end)

	local function onJoin(player)
		task.spawn(function()
			local tries = 0
			while not PlayerDataManager.Get(player) and tries < 60 do task.wait(0.1); tries += 1 end
			local data = PlayerDataManager.Get(player)
			if data then
				progress(data); relics(data); caches(data)
				if stageIndex(data) >= Config.DONE then grantRocketAccess(player) end
				-- catch up anything that completed while they were away (a lowered quota)
				advance(player, data, false)
				task.wait(1)
				sendState(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, p in ipairs(Players:GetPlayers()) do onJoin(p) end
	Players.PlayerRemoving:Connect(function(player) lastAction[player] = nil end)

	print(("GardensQuest online (%d stages, %d relics)"):format(Config.Count, Config.RelicTotal))
end

return GardensQuest
```

- [ ] **Step 2: Static check**

Run:
```bash
cd C:/Users/m/Coding/skip-a-brainrot-world3/game-src/place-full && f=ServerScriptService/Modules/GardensQuest.lua && grep -c "^function GardensQuest\." $f && grep -c 'getRemote("Gardens' $f && echo "Config fields used but not exported (must be empty):" && comm -23 <(grep -o "Config\.[A-Za-z]*" $f | sed 's/Config\.//' | sort -u) <(grep -oP "^M\.[A-Za-z]+(?=\s*=)" ReplicatedStorage/Modules/GardensQuestConfig.lua | sed 's/M\.//' | sort -u) && (grep -q $'\r' $f && echo "CRLF!" || echo "LF ok")
```
Expected: `3` functions (`NotifyCatch`, `AddCache`, `Init`; `SendState`/`Interact` are assignments), `2` remotes, and every `Config.X` used by the module appears in the config's exported names (`ByIndex Count DONE IndexOfId KeyAttribute KeyFlag CachesForKey Locked NONE NpcRole Relics RelicById RelicChance RelicPity RelicTotal RewardFlag Stages WorldName`), `LF ok`.

- [ ] **Step 3: Commit**

```bash
cd C:/Users/m/Coding/skip-a-brainrot-world3 && git add game-src/place-full/ServerScriptService/Modules/GardensQuest.lua && git commit -m "feat(world3): GardensQuest server module -- stage machine, gated bell count, relic pity, crypt key, caches"
```

---

### Task 4: `GardensQuestDev` — the `/tq gardens` verbs

**Files:**
- Create: `game-src/place-full/ServerScriptService/Modules/GardensQuestDev.lua`

**Interfaces:**
- Consumes: `GardensQuest.NotifyCatch/AddCache/SendState` (Task 3), `GardensQuestConfig` (Task 1), `PlayerDataManager.Get/PushUpdate`.
- Produces: `GardensQuestDev.Handle(player, rest: string)`; called from the 3-line `DevQuest` splice in Task 7 as `/tq gardens <verb>`.

- [ ] **Step 1: Write the module**

```lua
-- GardensQuestDev: developer shortcuts for "The Old Orders", reached as
-- `/tq gardens <verb>` through DevQuest (which owns the allowlist -- nothing here checks
-- who is asking, so it must only ever be called from there).
--
-- Same reasoning as DevQuest's own verbs: the arc is 150 catches, six relic drops, three
-- catches under a bell that rings once an hour, a key behind an exploration chain -- so
-- every stage needs a way to be stood in front of directly. A jump does NOT pay the
-- rewards of the stages it skips.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local GardensQuest = require(ServerScriptService.Modules.GardensQuest)
local Config = require(ReplicatedStorage.Modules.GardensQuestConfig)

local remotes = ReplicatedStorage.Remotes

local M = {}

local function reply(player, ok, msg)
	local r = remotes:FindFirstChild("PurchaseResult")
	if r then r:FireClient(player, { Success = ok, Message = msg }) end
end

local function cacheCount(data)
	local n = 0
	for _ in pairs(data.GardensCaches or {}) do n += 1 end
	return n
end

local function statusLine(data)
	local i = tonumber(data.GardensQuest) or 0
	if i == 0 then return "stage 0 -- not accepted" end
	if i >= Config.DONE then return "DONE -- rocket unlocked" end
	local s = Config.ByIndex[i]
	local p = data.GardensProgress or {}
	if s.Kind == "count" then
		return ("stage %d (%s): %d/%d%s"):format(i, s.Id, p[s.Counter] or 0, s.Target,
			s.Gated and (" [gated on " .. s.Gated .. "]") or "")
	elseif s.Kind == "gather" then
		local have, bits = data.GardensRelics or {}, {}
		for _, def in ipairs(Config.Relics) do
			bits[#bits + 1] = ("%s %d/%d"):format(def.Id, have[def.Id] or 0, def.Count)
		end
		return ("stage %d (%s): %s"):format(i, s.Id, table.concat(bits, ", "))
	elseif s.Kind == "flag" then
		return ("stage %d (%s): %s=%s, caches %d/%d"):format(i, s.Id, s.Flag,
			tostring(data[s.Flag] == true), cacheCount(data), Config.CachesForKey)
	end
	return ("stage %d (%s): talk to the Keeper"):format(i, s.Id)
end

local function resolveStage(word)
	local n = tonumber(word)
	if n then return math.clamp(math.floor(n), 0, Config.DONE) end
	if type(word) ~= "string" then return nil end
	local want = word:lower()
	if want == "done" then return Config.DONE end
	for id, index in pairs(Config.IndexOfId) do
		if id:lower() == want then return index end
	end
	return nil
end

-- Fill whatever the CURRENT stage is asking for, so the next press of E advances it.
local function fill(data)
	local i = tonumber(data.GardensQuest) or 0
	local s = Config.ByIndex[i]
	if not s then return false end
	if s.Kind == "count" then
		data.GardensProgress = data.GardensProgress or {}
		data.GardensProgress[s.Counter] = s.Target
		return true
	elseif s.Kind == "gather" then
		data.GardensRelics = data.GardensRelics or {}
		for _, def in ipairs(Config.Relics) do data.GardensRelics[def.Id] = def.Count end
		return true
	elseif s.Kind == "flag" then
		data[s.Flag] = true
		return true
	end
	return false   -- a talk stage is already "full"; it needs the Keeper
end

local function usage()
	return "[tq gardens] usage: /tq gardens | status | stage <n|id|done> | fill | " ..
		"catch <tier> <n> [bell] | caches <n> | key | reset"
end

function M.Handle(player, rest)
	local data = PlayerDataManager.Get(player)
	if not data then reply(player, false, "your profile has not loaded yet") return end

	local verb, tail = (rest or ""):match("^(%S*)%s*(.*)$")
	verb = (verb or ""):lower()

	if verb == "" or verb == "status" then
		reply(player, true, "[tq gardens] " .. statusLine(data))

	elseif verb == "reset" then
		data.GardensQuest = 0
		data.GardensProgress = { Catches = 0, BellCatches = 0 }
		data.GardensRelics = { Banner = 0, Helm = 0, Horn = 0 }
		data.GardensDry = 0
		data.GardensCaches = {}
		data[Config.KeyFlag] = false
		data[Config.RewardFlag] = false
		player:SetAttribute(Config.KeyAttribute, nil)
		PlayerDataManager.PushUpdate(player)
		reply(player, true, "[tq gardens] reset to stage 0")

	elseif verb == "stage" or verb == "goto" then
		local index = resolveStage(tail:match("^%S*"))
		if not index then
			local ids = {}
			for _, s in ipairs(Config.Stages) do ids[#ids + 1] = s.Id end
			reply(player, false, "[tq gardens] stage <0-" .. Config.DONE .. "|" .. table.concat(ids, "|") .. "|done>")
			return
		end
		data.GardensQuest = index
		data.CaveUnlocked = true   -- the arc refuses to start without the shaft
		-- Land ON the stage: its counters start empty, everything before it is satisfied.
		data.GardensProgress = data.GardensProgress or {}
		for _, s in ipairs(Config.Stages) do
			if s.Counter then
				data.GardensProgress[s.Counter] = (Config.IndexOfId[s.Id] < index) and s.Target or 0
			end
		end
		data.GardensRelics = data.GardensRelics or {}
		local relicsIndex = Config.IndexOfId.Relics
		for _, def in ipairs(Config.Relics) do
			data.GardensRelics[def.Id] = (index > relicsIndex) and def.Count or 0
		end
		data[Config.KeyFlag] = (index > Config.IndexOfId.Crypt)
		if index >= Config.DONE then
			data[Config.RewardFlag] = true
			player:SetAttribute(Config.KeyAttribute, true)
		else
			data[Config.RewardFlag] = false
			player:SetAttribute(Config.KeyAttribute, nil)
		end
		PlayerDataManager.PushUpdate(player)
		reply(player, true, "[tq gardens] " .. statusLine(data))

	elseif verb == "fill" then
		if fill(data) then
			PlayerDataManager.PushUpdate(player)
			reply(player, true, "[tq gardens] filled -- " .. statusLine(data))
		else
			reply(player, false, "[tq gardens] nothing to fill on a talk stage; go and see the Keeper")
		end

	elseif verb == "catch" then
		-- Fires the REAL hook, so this exercises the counting and the relic roll exactly
		-- as a landed Gardens skip would -- including the pity streak. `bell` raises the
		-- Sentinel attribute for the duration of the call only.
		local word, count, flag = tail:match("^(%S*)%s*(%S*)%s*(%S*)$")
		local tier = (word ~= "" and word) or "Common"
		tier = tier:sub(1, 1):upper() .. tier:sub(2):lower()
		local n = math.clamp(tonumber(count) or 1, 1, 200)
		local bell = (flag or ""):lower() == "bell"
		local attr = Config.SentinelAttr
		local was = ReplicatedStorage:GetAttribute(attr)
		if bell then ReplicatedStorage:SetAttribute(attr, true) end
		for _ = 1, n do
			GardensQuest.NotifyCatch(player, tier, Config.WorldName)
		end
		if bell then ReplicatedStorage:SetAttribute(attr, was) end
		reply(player, true, ("[tq gardens] %d x %s%s -- %s"):format(n, tier, bell and " (bell)" or "", statusLine(data)))

	elseif verb == "caches" then
		local n = math.clamp(tonumber(tail:match("^%S*")) or 1, 1, 8)
		for i = 1, n do GardensQuest.AddCache(player, "dev" .. i) end
		reply(player, true, ("[tq gardens] caches now %d"):format(cacheCount(data)))

	elseif verb == "key" then
		data[Config.KeyFlag] = true
		PlayerDataManager.PushUpdate(player)
		reply(player, true, "[tq gardens] crypt key granted")

	else
		reply(player, false, usage())
		return
	end

	GardensQuest.SendState(player)
end

return M
```

- [ ] **Step 2: Static check**

Run:
```bash
cd C:/Users/m/Coding/skip-a-brainrot-world3/game-src/place-full && f=ServerScriptService/Modules/GardensQuestDev.lua && grep -c 'verb == "' $f && grep -c "GardensQuest\.\(NotifyCatch\|AddCache\|SendState\)" $f && file $f | grep -q CRLF && echo "CRLF!" || echo "LF ok"
```
Expected: `7` lines carrying a verb test (`""`/status share one line, stage/goto share one), `3`, `LF ok`.

- [ ] **Step 3: Commit**

```bash
cd C:/Users/m/Coding/skip-a-brainrot-world3 && git add game-src/place-full/ServerScriptService/Modules/GardensQuestDev.lua && git commit -m "feat(world3): GardensQuestDev -- /tq gardens status|stage|fill|catch [bell]|caches|key|reset"
```

---

### Task 5: `GardensQuestClient` — the Keeper's conversation

**Files:**
- Create: `game-src/place-full/StarterPlayer/StarterPlayerScripts/GardensQuestClient.client.lua`

**Interfaces:**
- Consumes: `GardensQuestConfig` (Task 1), `GardensNpcConfig.Roles.Keeper`? — no: the Keeper's display name and accent live in `GardensQuestConfig` (`Accent`) and the tracker; the display name string is read from `GardensNpcConfig` only if present (`Roles.Keeper` is not defined there; the client uses `KEEPER_NAME` below, a placeholder). Remotes `GardensTalk`/`GardensState`. `MerchantDialog.Show(npcName, lines, accent, onDone, anchor, finalLabel)` unchanged. Optional `ReplicatedStorage.Modules.StoryCinematic` with `StoryCinematic.Play(name) -> seconds` (Plan 5; absent today).
- Produces: nothing other modules consume.

- [ ] **Step 1: Write the script**

```lua
-- GardensQuestClient: "The Old Orders", front end -- the Keeper's conversation only.
--
-- The tracker row is QuestTrackerClient's (it reads GardensState like every other
-- questline), the toasts are ToastClient's (PurchaseResult), the other World 3 voices are
-- GardensNpcClient's, and the cutscenes belong to StoryCinematic when that module exists.
-- All of them listen to the same GardensState push independently.
--
-- Nothing here decides anything: the server sends a stage index, this file looks up what
-- the Keeper says at that index, and pressing the button tells the server the player
-- spoke to him. Structural copy of TundraQuestClient with one difference: accepting the
-- orders opens the first page straight away, so the first beat is read once, not twice.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local modules = ReplicatedStorage:WaitForChild("Modules")

local MerchantDialog = require(modules:WaitForChild("MerchantDialog"))
local Config = require(modules:WaitForChild("GardensQuestConfig"))

local talkRemote = remotes:WaitForChild("GardensTalk")
local stateRemote = remotes:WaitForChild("GardensState")

-- PLACEHOLDER display name (board P6): the role is "Keeper"; Balkan names him.
local KEEPER_NAME = "The Keeper"
local ACCENT = Config.Accent

-- Optional: the story cinematic module (Plan 5). Absent today, so every use is guarded.
local StoryCinematic = nil
do
	local m = modules:FindFirstChild("StoryCinematic")
	if m then
		local ok, mod = pcall(require, m)
		if ok and type(mod) == "table" and type(mod.Play) == "function" then StoryCinematic = mod end
	end
end

---------------------------------------------------------------- state
local state = {
	State = 0, Step = 0, Of = 0, Met = false, Done = false,
	StageId = "None", Kind = nil, Parts = nil, Caches = 0, CryptKey = false,
}
local anchorPart

local function progressLine()
	local stage = Config.ByIndex[state.State]
	if not stage then return nil end
	if type(state.Parts) == "table" and #state.Parts > 0 then
		local bits = {}
		for _, p in ipairs(state.Parts) do
			bits[#bits + 1] = ("%s %d/%d"):format(p.Plural or p.Label, p.Have or 0, p.Need or 0)
		end
		return "Still short: " .. table.concat(bits, ", ") .. "."
	end
	if stage.Kind == "count" then
		return ("So far: %d of %d."):format(state.Step or 0, state.Of or 0)
	end
	if stage.Kind == "flag" then
		return ("The trader's caches: %d of %d."):format(state.Caches or 0, Config.CachesForKey)
	end
	return nil
end

local function push(lines, text)
	if type(text) == "string" and text ~= "" then lines[#lines + 1] = text end
end

local function fireTalk()
	talkRemote:FireServer(Config.NpcRole)
end

---------------------------------------------------------------- the conversation
local function speak()
	local lines = {}

	if state.Done then
		push(lines, Config.Finished)
		MerchantDialog.Show(KEEPER_NAME, lines, ACCENT, nil, anchorPart, "OK \u{25B6}")
		return
	end

	if state.State == Config.NONE then
		-- The offer is the introduction alone; the first page arrives on the "accept"
		-- note below, so the player reads it once.
		push(lines, Config.Intro)
		MerchantDialog.Show(KEEPER_NAME, lines, ACCENT, fireTalk, anchorPart, "READ THE ORDERS \u{25B6}")
		return
	end

	local stage = Config.ByIndex[state.State]
	if not stage then
		MerchantDialog.Show(KEEPER_NAME, { Config.Intro }, ACCENT, nil, anchorPart, "OK \u{25B6}")
		return
	end

	if stage.Kind == "talk" then
		push(lines, stage.Say)
		MerchantDialog.Show(KEEPER_NAME, lines, ACCENT, fireTalk, anchorPart,
			stage.Cutscene and "STAND BACK \u{25B6}" or "CONTINUE \u{25B6}")
		return
	end

	if stage.Kind == "flag" then
		if state.Met then
			-- the key is in hand: a line for THAT, so Done is read once, after the press
			push(lines, stage.Ready or stage.Done)
			MerchantDialog.Show(KEEPER_NAME, lines, ACCENT, fireTalk, anchorPart, "STAND BACK \u{25B6}")
		else
			push(lines, (state.Caches or 0) > 0 and (stage.Nag or stage.Say) or stage.Say)
			push(lines, progressLine())
			MerchantDialog.Show(KEEPER_NAME, lines, ACCENT, nil, anchorPart, "OK \u{25B6}")
		end
		return
	end

	-- A grind stage already SATISFIED (a lowered quota, a dev jump): never nag for
	-- something already done.
	if state.Met then
		push(lines, stage.Done)
		MerchantDialog.Show(KEEPER_NAME, lines, ACCENT, fireTalk, anchorPart, "CONTINUE \u{25B6}")
		return
	end

	-- A grind stage in progress: the briefing on the first visit, the nag after.
	push(lines, (state.Step or 0) > 0 and (stage.Nag or stage.Say) or stage.Say)
	push(lines, progressLine())
	MerchantDialog.Show(KEEPER_NAME, lines, ACCENT, nil, anchorPart, "OK \u{25B6}")
end

---------------------------------------------------------------- the prompt
-- STREAMING: the Keep is 16,000 studs from spawn, so the prompt is created, destroyed
-- and created again as the player comes and goes. Scan once, then watch the folder.
local function bindPrompt(prompt)
	local host = prompt.Parent
	if not host then return end
	anchorPart = host:IsA("BasePart") and host or host:FindFirstChildWhichIsA("BasePart")
	prompt.Triggered:Connect(function(who)
		if who == player then speak() end
	end)
end

task.spawn(function()
	local gw = Workspace:WaitForChild("GameWorld", 60)
	local lg = gw and gw:WaitForChild("LushGardens", 60)
	if not lg then
		warn("[GardensQuestClient] no GameWorld.LushGardens -- is World 3 in the place?")
		return
	end
	for _, d in ipairs(lg:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == Config.PromptName then bindPrompt(d) end
	end
	lg.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") and d.Name == Config.PromptName then bindPrompt(d) end
	end)
end)

---------------------------------------------------------------- state in
stateRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end
	for _, k in ipairs({ "State", "Step", "Of", "Met", "Done", "StageId", "Kind", "Parts", "Title", "Track", "Caches", "CryptKey" }) do
		state[k] = payload[k]
	end
	state.State = tonumber(payload.State) or 0

	local note = payload.Note
	local isCut = type(note) == "string" and note:sub(1, 9) == "cutscene:"

	if note == "accept" then
		-- The orders were accepted: read the first page now, in the same breath.
		local first = Config.ByIndex[1]
		if first then
			task.delay(0.15, function()
				MerchantDialog.Show(KEEPER_NAME, { first.Say }, ACCENT, fireTalk, anchorPart, "CONTINUE \u{25B6}")
			end)
		end
		return
	end

	if note == "advance" or isCut then
		local cleared = payload.Cleared and Config.ByIndex[Config.IndexOfId[payload.Cleared]]
		local nextStage = Config.ByIndex[state.State]
		local lines = {}
		push(lines, cleared and cleared.Done)
		if payload.Done then
			push(lines, Config.Finished)
		else
			push(lines, nextStage and nextStage.Say)
		end
		-- A cutscene owns the screen: play it if the module exists, and wait for it
		-- either way before the Keeper speaks again.
		local wait = 0.15
		if isCut then
			wait = Config.CutsceneWait
			if StoryCinematic then
				local ok, seconds = pcall(StoryCinematic.Play, note:sub(10))
				if ok and type(seconds) == "number" then wait = seconds + 0.5 end
			end
		end
		if #lines > 0 then
			task.delay(wait, function()
				MerchantDialog.Show(KEEPER_NAME, lines, ACCENT, nil, anchorPart, "OK \u{25B6}")
			end)
		end
	end
end)
```

- [ ] **Step 2: Static check**

Run:
```bash
cd C:/Users/m/Coding/skip-a-brainrot-world3/game-src/place-full && f=StarterPlayer/StarterPlayerScripts/GardensQuestClient.client.lua && grep -c "MerchantDialog.Show(" $f && grep -c 'WaitForChild("Gardens\(Talk\|State\)")' $f && grep -c "StoryCinematic" $f && file $f | grep -q CRLF && echo "CRLF!" || echo "LF ok"
```
Expected: `10` Show calls, `2` remotes, `6` StoryCinematic references (all guarded), `LF ok`.

- [ ] **Step 3: Commit**

```bash
cd C:/Users/m/Coding/skip-a-brainrot-world3 && git add game-src/place-full/StarterPlayer/StarterPlayerScripts/GardensQuestClient.client.lua && git commit -m "feat(world3): GardensQuestClient -- the Keeper's conversation, cutscene-note handling, optional StoryCinematic hook"
```

---

### Task 6: `GardensNpcClient` — every other walk-up

**Files:**
- Create: `game-src/place-full/StarterPlayer/StarterPlayerScripts/GardensNpcClient.client.lua`

**Interfaces:**
- Consumes: `GardensNpcConfig` (Task 2), `GardensQuestConfig` (Task 1), remotes `GardensTalk`/`GardensState`, `MerchantDialog.Show`, `ReplicatedStorage:GetAttribute("WeatherName")`.
- Produces: nothing other modules consume. Requires (Plan 2) one `ProximityPrompt` named `<Role>Prompt` per role under `GameWorld.LushGardens`.

- [ ] **Step 1: Write the script**

```lua
-- GardensNpcClient: the eight World 3 voices that are not the Keeper.
--
-- ONE client for all of them, driven by GardensNpcConfig: bind every prompt named
-- <Role>Prompt under GameWorld.LushGardens, and when it fires, show that role's lines for
-- the arc's current bucket. The Deserter is the only one with a server-side effect (the
-- crypt key); everyone else is flavour and never fires a remote.
--
-- The bucket comes from GardensState (the Keeper's arc), so a player who has never met
-- the Keeper gets the "Before" lines everywhere, and the whole town moves on together as
-- the pages are read. On a red night (WeatherName == "Blood Moon") every role swaps to
-- its BloodMoon bucket -- board P18-mod: subtle, no machine talk.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local modules = ReplicatedStorage:WaitForChild("Modules")

local MerchantDialog = require(modules:WaitForChild("MerchantDialog"))
local Npc = require(modules:WaitForChild("GardensNpcConfig"))
local Quest = require(modules:WaitForChild("GardensQuestConfig"))

local talkRemote = remotes:WaitForChild("GardensTalk")
local stateRemote = remotes:WaitForChild("GardensState")

---------------------------------------------------------------- state
local arc = { State = 0, Done = false, Caches = 0, CryptKey = false }
local anchorByRole = {}       -- [roleId] = BasePart the portrait frames
local promptToRole = {}       -- [promptName] = roleId
for roleId, def in pairs(Npc.Roles) do promptToRole[def.PromptName] = roleId end

local function isRedNight()
	return ReplicatedStorage:GetAttribute(Npc.WeatherAttr) == Npc.BloodMoonName
end

-- Which lines a role speaks right now. The Scavenger and the Deserter have extra
-- buckets that depend on the payload rather than the stage.
local function linesFor(roleId)
	local def = Npc.Roles[roleId]
	if not def then return nil, nil end
	if isRedNight() and def.Lines.BloodMoon then
		return def.Lines.BloodMoon, nil
	end
	local bucket = Npc.BucketFor(arc.State, arc.Done)
	if roleId == "Scavenger" and bucket == "Late" and (arc.Caches or 0) < Quest.CachesForKey then
		return def.Lines.LateShort or def.Lines.Late, nil
	end
	if roleId == "Deserter" and bucket == "Late" then
		if arc.CryptKey then return def.Lines.Key or def.Lines.Late, nil end
		-- the ask: the primary button sends the role to the server, which answers with
		-- note "key" or "deserternag" (handled below)
		return def.Lines.Late, def.Ask
	end
	return def.Lines[bucket] or def.Lines.Before, nil
end

local function speak(roleId)
	local def = Npc.Roles[roleId]
	if not def then return end
	local lines, ask = linesFor(roleId)
	if not lines or #lines == 0 then return end
	local onDone = nil
	if ask then
		onDone = function() talkRemote:FireServer(roleId) end
	end
	MerchantDialog.Show(def.Name, lines, def.Accent, onDone, anchorByRole[roleId], ask or "OK \u{25B6}")
end

---------------------------------------------------------------- prompts
local function bindPrompt(prompt)
	local roleId = promptToRole[prompt.Name]
	if not roleId then return end
	local host = prompt.Parent
	if not host then return end
	anchorByRole[roleId] = host:IsA("BasePart") and host or host:FindFirstChildWhichIsA("BasePart")
	prompt.Triggered:Connect(function(who)
		if who == player then speak(roleId) end
	end)
end

task.spawn(function()
	local gw = Workspace:WaitForChild("GameWorld", 60)
	local lg = gw and gw:WaitForChild("LushGardens", 60)
	if not lg then
		warn("[GardensNpcClient] no GameWorld.LushGardens -- is World 3 in the place?")
		return
	end
	for _, d in ipairs(lg:GetDescendants()) do
		if d:IsA("ProximityPrompt") and promptToRole[d.Name] then bindPrompt(d) end
	end
	lg.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") and promptToRole[d.Name] then bindPrompt(d) end
	end)
end)

---------------------------------------------------------------- state in
stateRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end
	arc.State = tonumber(payload.State) or 0
	arc.Done = payload.Done == true
	arc.Caches = tonumber(payload.Caches) or 0
	arc.CryptKey = payload.CryptKey == true

	-- The Deserter's answer to the ask, in his own words.
	local def = Npc.Roles.Deserter
	if payload.Note == "key" and def then
		task.delay(0.15, function()
			MerchantDialog.Show(def.Name, def.Lines.Key or def.Lines.Late, def.Accent, nil, anchorByRole.Deserter, "OK \u{25B6}")
		end)
	elseif payload.Note == "deserternag" and def then
		task.delay(0.15, function()
			MerchantDialog.Show(def.Name, def.Lines.NoKey or def.Lines.Late, def.Accent, nil, anchorByRole.Deserter, "OK \u{25B6}")
		end)
	end
end)
```

- [ ] **Step 2: Static check**

Run:
```bash
cd C:/Users/m/Coding/skip-a-brainrot-world3/game-src/place-full && f=StarterPlayer/StarterPlayerScripts/GardensNpcClient.client.lua && grep -c "MerchantDialog.Show(" $f && grep -c "FireServer(roleId)" $f && grep -c '"deserternag"\|"key"' $f && file $f | grep -q CRLF && echo "CRLF!" || echo "LF ok"
```
Expected: `3`, `1`, `3` (two branches plus the comment naming them), `LF ok`.

- [ ] **Step 3: Commit**

```bash
cd C:/Users/m/Coding/skip-a-brainrot-world3 && git add game-src/place-full/StarterPlayer/StarterPlayerScripts/GardensNpcClient.client.lua && git commit -m "feat(world3): GardensNpcClient -- one walk-up client for the eight roles, red-night variants, the Deserter's ask"
```

---

### Task 7: Shared-file deltas, as patches (applied live at the window)

**Files:**
- Create: `docs/world3/SHARED-FILE-DELTAS.md`

**Interfaces:**
- Consumes: Tasks 1–6 (names: `GardensQuest`, `GardensQuestDev`, `GardensQuestConfig`, remotes `GardensState`).
- Produces: the exact splices for `ThrowHandler`, `Main`, `PlayerDataManager`, `DevQuest`, `QuestTrackerClient`. Anchors are quoted from the live source as of the 2026-09-19 re-sync; at the window each anchor is re-read live before splicing (handoff rule: "anchor every edit on a line you have just read live").

- [ ] **Step 1: Write the patch document**

````markdown
# World 3 — shared-file deltas (apply LIVE through the bridge; never from the mirror)

Every splice below is additive. Re-read the anchor line live in Studio before each
edit; if it has moved or changed, stop and re-anchor. After applying, push the whole
file back to the mirror with the bridge so the branch carries exactly this delta.

## 1. `ServerScriptService.Modules.ThrowHandler` (the catch hook)

Anchor (live, ~line 29):
```lua
local TundraQuest = require(ServerScriptService.Modules.TundraQuest)
```
Insert after it:
```lua
local GardensQuest = require(ServerScriptService.Modules.GardensQuest)
```

Anchor (live, ~line 1266, inside revealCatch):
```lua
			pcall(TundraQuest.NotifyCatch, player, tier.Name, throwWorld)
```
Insert after it:
```lua
			-- World 3's arc: counts the Keeper's stages and rolls the relics, gated on
			-- throwWorld == "Gardens" exactly as the tundra's is on "Tundra".
			pcall(GardensQuest.NotifyCatch, player, tier.Name, throwWorld)
```

## 2. `ServerScriptService.Main` (boot)

Anchor (live, line 47):
```lua
local TundraQuest = require(ServerScriptService.Modules.TundraQuest)
```
Insert after it:
```lua
local GardensQuest = require(ServerScriptService.Modules.GardensQuest)
```

Anchor (live, line 189):
```lua
TundraQuest.Init()
```
Insert after it:
```lua
GardensQuest.Init()
```
(`DevQuest.Init()` already runs after both, so `/tq gardens` is live from boot.)

## 3. `ServerScriptService.Modules.PlayerDataManager` (profile fields)

Anchor (live, defaultData, the line):
```lua
		CaveUnlocked = false,        -- TundraQuestConfig.RewardFlag: the seam Area 3 gates on
```
Insert after it:
```lua

		-- "The Old Orders" -- Elder Tung's World 3 arc, run by the Keeper (see
		-- GardensQuest / GardensQuestConfig): an INDEX into GardensQuestConfig.Stages,
		-- 0 = never spoken to. Counters are write-only tallies, never rebuilt from the
		-- inventory. GardensCaches is a SET of cache ids; CryptKey is the Deserter's.
		GardensQuest = 0,
		GardensProgress = { Catches = 0, BellCatches = 0 },
		GardensRelics = { Banner = 0, Helm = 0, Horn = 0 },
		GardensDry = 0,
		GardensCaches = {},
		CryptKey = false,
		RocketUnlocked = false,      -- GardensQuestConfig.RewardFlag: the seam World 4 gates on
```

Anchor (live, Load backfill, the line):
```lua
		if data.CaveUnlocked == nil then data.CaveUnlocked = false end
```
Insert after it:
```lua
		if data.GardensQuest == nil then data.GardensQuest = 0 end
		if type(data.GardensProgress) ~= "table" then data.GardensProgress = { Catches = 0, BellCatches = 0 } end
		if type(data.GardensRelics) ~= "table" then data.GardensRelics = { Banner = 0, Helm = 0, Horn = 0 } end
		if type(data.GardensDry) ~= "number" then data.GardensDry = 0 end
		if type(data.GardensCaches) ~= "table" then data.GardensCaches = {} end
		if data.CryptKey == nil then data.CryptKey = false end
		if data.RocketUnlocked == nil then data.RocketUnlocked = false end
```

Anchor (live, Snapshot, the line):
```lua
		CaveUnlocked = data.CaveUnlocked,
```
Insert after it:
```lua
		-- One world on again: finishing the Keeper's orders opens the launch pad for good.
		RocketUnlocked = data.RocketUnlocked,
```

## 4. `ServerScriptService.Modules.DevQuest` (the `gardens` verb)

Anchor (live, ~line 28):
```lua
local MichelConfig = require(ReplicatedStorage.Modules.MichelQuestConfig)
```
Insert after it:
```lua
local GardensQuestDev = require(ServerScriptService.Modules.GardensQuestDev)
```

Anchor (live, line 155):
```lua
	elseif verb == "michel" then
```
Insert BEFORE it:
```lua
	elseif verb == "gardens" then
		-- World 3's arc has its own verb family; it sends its own state push.
		GardensQuestDev.Handle(player, rest)
		return

```

Anchor (live, ~line 235, the usage string):
```lua
			.. " | /tq michel <status|reset|give [n]>")
```
Replace with:
```lua
			.. " | /tq michel <status|reset|give [n]> | /tq gardens <...>")
```

## 5. `StarterPlayer.StarterPlayerScripts.QuestTrackerClient` — LOCKED (Round 3). Additive row only. NEEDS BALKAN'S OK BEFORE APPLYING.

Anchor (live, line 62):
```lua
local MichelQuestConfig = require(modules:WaitForChild("MichelQuestConfig"))
```
Insert after it:
```lua
local GardensQuestConfig = require(modules:WaitForChild("GardensQuestConfig"))
```

Anchor (live, the `NPC` table's last entry):
```lua
	Michel   = { name = "Michael",    initial = "M", accent = { Color3.fromRGB(226, 176, 62),  Color3.fromRGB(196, 146, 48) },  icon = "tag" },
```
Insert after it (no icon: IconArt has no fitting key, so the card draws the initial):
```lua
	Keeper   = { name = "The Keeper", initial = "K", accent = { Color3.fromRGB(156, 178, 136), Color3.fromRGB(88, 118, 86) } },
```

Anchor (live, the `QUESTS` table's closing `}` after the Michel entry):
```lua
			[2] = { Title = "Eagles Quest", Objective = "You are holding the rest \u{2014} finish the hand-over", Kind = "return", Step = 0, Of = MichelQuestConfig.Count },
		},
	},
```
Insert after it (before the table's final `}`):
```lua
	{
		Id = "GardensOrders", Npc = NPC.Keeper, Remote = "GardensState",
		-- built FROM the config, exactly like TundraCave: talk and flag stages are a
		-- visit away; count and gather stages carry a bar
		Steps = (function()
			local t = {}
			for i, s in ipairs(GardensQuestConfig.Stages) do
				local grind = (s.Kind == "count" or s.Kind == "gather")
				t[i] = {
					Title = s.Title, Objective = s.Track or s.Title,
					Kind = grind and "objective" or "return",
					HasProgress = grind,
					Step = 0, Of = (s.Kind == "count" and s.Target) or (s.Kind == "gather" and GardensQuestConfig.RelicTotal) or 1,
				}
			end
			return t
		end)(),
		Objective = function(payload, step)
			if type(payload.Parts) == "table" and #payload.Parts > 0 then
				local bits = {}
				for _, p in ipairs(payload.Parts) do
					bits[#bits + 1] = ("%s %d/%d"):format(p.Plural or p.Label or p.Id, p.Have or 0, p.Need or 0)
				end
				return table.concat(bits, "  \u{00B7}  ")
			end
			return nil
		end,
		KindOf = function(payload, step)
			if step.Kind == "objective" and payload.Met == true then return "return" end
			return step.Kind
		end,
	},
```
````

- [ ] **Step 2: Static check** — every name the patches reference exists in Tasks 1–6.

Run:
```bash
cd C:/Users/m/Coding/skip-a-brainrot-world3 && for n in GardensQuest.NotifyCatch GardensQuest.Init GardensQuestDev.Handle GardensQuestConfig.RelicTotal GardensQuestConfig.Stages '"GardensState"'; do grep -q "$n" docs/world3/SHARED-FILE-DELTAS.md && echo "ref ok: $n"; done && grep -c "RocketUnlocked\|GardensCaches\|CryptKey\|GardensDry\|GardensRelics\|GardensProgress\|GardensQuest = 0" docs/world3/SHARED-FILE-DELTAS.md
```
Expected: six `ref ok` lines and a count ≥ 14 (the seven fields appear in defaults and backfill).

- [ ] **Step 3: Commit**

```bash
cd C:/Users/m/Coding/skip-a-brainrot-world3 && git add docs/world3/SHARED-FILE-DELTAS.md && git commit -m "docs(world3): shared-file deltas for the story spine -- ThrowHandler, Main, PlayerDataManager, DevQuest, tracker row (locked, needs OK)"
```

---

### Task 8: Studio verification (GATED — needs the inspection window)

**Files:** none new. Uses `tools/studio-bridge/bridge.py` and the Studio MCP.

- [ ] **Step 1: Create the six lane-owned scripts in Studio** at their DataModel paths (`ReplicatedStorage.Modules.GardensQuestConfig`, `.GardensNpcConfig`, `ServerScriptService.Modules.GardensQuest`, `.GardensQuestDev`, `StarterPlayer.StarterPlayerScripts.GardensQuestClient` (LocalScript), `.GardensNpcClient` (LocalScript)) by pulling each file from the bridge (`HS:GetAsync("http://127.0.0.1:8731/<file>")`) into the new instance's `Source`. Then push each back and confirm the mirror bytes are unchanged (`git status` clean for those six paths).

- [ ] **Step 2: Apply the five splices of Task 7 live** (re-reading each anchor first), push the five files back, and commit the mirror with `chore(world3): mirror shared-file deltas from Studio`.

- [ ] **Step 3: Command-bar smoke test**

```lua
local RS = game:GetService("ReplicatedStorage")
local C = require(RS.Modules.GardensQuestConfig)
local N = require(RS.Modules.GardensNpcConfig)
print(C.Count, C.DONE, C.RelicTotal, C.IndexOfId.Crypt, N.BucketFor(0, false), N.BucketFor(6, false), N.BucketFor(8, true))
```
Expected output: `7 8 6 6 Before Late After`.

- [ ] **Step 4: Play-mode arc walk** (a temporary `KeeperPrompt` ProximityPrompt on a part under `GameWorld.LushGardens` if Plan 2 has not placed the real one):
`/tq gardens reset` → talk (Intro, READ THE ORDERS) → the first page opens by itself → CONTINUE → Muster briefing appears · `/tq gardens catch Common 150` → toast "One hundred and fifty. Page two. — go and see the Keeper" and the tracker bar fills · talk → Relics briefing · `/tq gardens catch Common 40` → six relic toasts within the pity bound (worst case 48 skips) → stage advances · talk → STAND BACK → (no StoryCinematic yet) after 6.5 s the Keeper says "That is them…" and briefs the bell · `/tq gardens catch Common 3` → no progress (not gated) · `/tq gardens catch Common 3 bell` → progress 3/3, stage advances · talk → Crypt briefing shows "caches 0 of 2" · `/tq gardens caches 2` · `/tq gardens key` (or the Deserter's prompt once placed) → talk → STAND BACK → SecondDoor note → Launch briefing · talk → STAND BACK → Launch note → "It is done…" → `Finished` on the next talk; `player:GetAttribute("HasRocketAccess") == true`; the tracker row moves to DONE.

- [ ] **Step 5: Red night check**: `/bloodmoon` (DevWeather) → every placed role's prompt shows its BloodMoon line; `/clear` restores.

- [ ] **Step 6: Perf sanity**: no new Heartbeat loops were added by this plan (both clients are event-driven); confirm with the microprofiler that `GardensNpcClient`/`GardensQuestClient` show no per-frame cost.

---

## Self-review

- **Spec coverage:** §3 (stage table, data, remotes, seams) → Tasks 1, 3, 7. §2 (roles, buckets, Blood Moon, placeholders) → Tasks 2, 6. §9 shared deltas + locked tracker row → Task 7. §10 verification → Task 8. §4/§5/§6/§7 (cutscenes, mechanics, dressing, launch) are Plans 2–6 by design; the only hooks this plan leaves for them are `SentinelActive`, `GardensCaches`/`AddCache`, `StoryCinematic.Play`, `RocketUnlocked`/`HasRocketAccess` — all defined here.
- **Placeholder scan:** the only intentional placeholders are the display names and the reward numbers, both marked and both Balkan's by decision; no step says "add later".
- **Type consistency:** `Interact(player, role)` / `talkRemote:FireServer(Config.NpcRole)` / `FireServer(roleId)` agree; payload keys `Caches`, `CryptKey`, `Parts`, `Cleared`, `Salvage`, notes `accept | advance | cutscene:<Id> | nag | finished | locked | progress | salvage | stagedone | key | deserternag | deserter | cache | state` are produced in Task 3 and consumed in Tasks 5–6; `Config.KeyFlag == "CryptKey"` matches the `PlayerDataManager` field; stage ids `Orders Muster Relics Mural Bell Crypt Launch` match `IndexOfId` uses in Tasks 2–4 and the cutscene names `Mural SecondDoor Launch` match the spec's beats 3, 5, 6.
