# World 3 — shared-file deltas (apply LIVE through the bridge; never from the mirror)

**Status:** documented, NOT applied. Every splice below is additive. At the Studio window: re-read the
anchor line live in Studio before each edit; if it has moved or changed, stop and re-anchor. After
applying, push the whole file back to the mirror with `tools/studio-bridge/bridge.py` so the branch
carries exactly this delta and nothing else. Anchors are quoted from the live source as of the
2026-09-19 re-sync (`source-sync-audit@b29c541`) and, for `QuestTrackerClient`, from the Round-3-final
copy on `ui-foundation` (`7e44a98`, byte-identical at `86c6cf5`).

The lane-owned files these deltas wire in (already authored on `world3-refinement`):
`ReplicatedStorage.Modules.GardensQuestConfig`, `.GardensNpcConfig`,
`ServerScriptService.Modules.GardensQuest`, `.GardensQuestDev`,
`StarterPlayer.StarterPlayerScripts.GardensQuestClient`, `.GardensNpcClient`.

## 1. `ServerScriptService.Modules.ThrowHandler` — the catch hook (2 lines + 3 comment lines)

Anchor (live, ~line 29):
```lua
local TundraQuest = require(ServerScriptService.Modules.TundraQuest)
```
Insert after it:
```lua
local GardensQuest = require(ServerScriptService.Modules.GardensQuest)
```

Anchor (live, ~line 1266, inside `revealCatch`):
```lua
			pcall(TundraQuest.NotifyCatch, player, tier.Name, throwWorld)
```
Insert after it:
```lua
			-- World 3's arc: counts the Keeper's stages and rolls the relics, gated on
			-- throwWorld == "Gardens" exactly as the tundra's is on "Tundra".
			pcall(GardensQuest.NotifyCatch, player, tier.Name, throwWorld)
```

## 2. `ServerScriptService.Main` — boot (2 lines)

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

## 3. `ServerScriptService.Modules.PlayerDataManager` — profile fields (7 defaults, 7 backfills, 1 snapshot line)

Anchor (live, `defaultData`):
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

Anchor (live, `Load` backfill):
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

Anchor (live, `Snapshot`):
```lua
		CaveUnlocked = data.CaveUnlocked,
```
Insert after it:
```lua
		-- One world on again: finishing the Keeper's orders opens the launch pad for good.
		RocketUnlocked = data.RocketUnlocked,
```

Note: the `ui-foundation` working tree holds an uncommitted 2026-08-04 hand patch of this file that is
neither live nor HEAD (source-sync audit §3). This delta is written against the LIVE source; it does not
touch that patch and must not be merged into it.

## 4. `ServerScriptService.Modules.DevQuest` — the `gardens` verb (1 require, 4 lines, 1 usage edit)

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

## 5. `StarterPlayer.StarterPlayerScripts.QuestTrackerClient` — LOCKED (Round 3). Additive row only.

**Approved by Balkan 2026-09-19, narrowly:** add only the Gardens entry; no refactor, no rename or reorder of
existing entries, no change to Round 3 quest/HUD behaviour, no touch on layout / animation / visibility
logic. **Re-run the Round 3 regression checks (`docs/qa/round3/README.md`) after it is applied live.**

The exact delta is `docs/world3/patches/QuestTrackerClient.gardens-row.patch`: a unified diff against the
Round-3-final copy, **34 lines added, 0 removed, 0 modified**, verified with `git apply --check` against the
mirror. It consists of exactly three insertions:

1. one `require` after `MichelQuestConfig`'s (line 62);
2. one `NPC.Keeper` identity after `NPC.Michel` (line 121) — no `icon` (IconArt has no fitting key, so
   the card draws the initial, which `QuestCard` already supports);
3. one `QUESTS` entry `GardensOrders` after the Michel entry (after line 212), built from
   `GardensQuestConfig.Stages` in the same shape as `TundraCave` (talk/flag → "return", count/gather →
   "objective" with a bar; `Objective` composes the relic list; `KindOf` flips a met bar to "return").

The mirror copy on the lane is deliberately left untouched until the live edit is pushed back.
