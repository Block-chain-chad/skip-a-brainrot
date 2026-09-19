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
