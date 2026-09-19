# World 3 refinement — design (post-approval)

**Lane:** `world3-refinement` · **Date:** 2026-09-19 · **Status:** design for Balkan's review; nothing here is built in Studio.
**Inputs:** `docs/WORLD3-CURRENT-STATE-AND-REFINEMENT.md` (Parts A–D) and Balkan's Lore Approval Board decisions of 2026-09-19.

This document supersedes the proposal sections (§21–§36) of the phase-1 report wherever they differ. Every story element below carries one of three marks:

- **[CANON]** — Balkan's locked canon.
- **[GAME]** — already true in the shipped place (verified in the mirror).
- **[P#]** — approved proposal, by board number; **[P#-mod]** approved with Balkan's modification, applied here.

Anything on HOLD (P2 crescent sigil, P6 names, P8 "Tung caused the loss", P9 "the Ancient is what he listened to") is **absent** from this design except where it says how the hold is honoured.

---

## 1. Story structure

**The world.** [P4] The Gardens were a settlement before the war — a walled town on the skirt of a hill, a river, a great hall on the plateau — and the war shaped everything about them since: [CANON] the people of the surface were driven underground here after Elder Tung and his Brainrots lost to Bacon Head. The survivors' descendants call the great hall **the Keep** (the "castle" of the brief) and the town simply **the Town**; the older names the build uses (Verdant Court, Aelunmyr, the Sanctum) survive only as what the Keeper calls "the old names". [GAME] Nothing is rebuilt: every district stands where `GardensBuild` put it.

**The arrival.** [CANON] The player drills down. [P1-mod] The recognisable connection to Tung is **the drill itself** — no new token. The auger's bit hangs through the ceiling of the arrival chamber; the survivors know that make of machine ("I have not seen an engine like that since the war"). The player is identified by *what brought them*, not by an object they carry. [GAME] The existing `Activate.Done` line ("It is open. Whatever is down there -- it knows you are coming.") is left exactly as it is; it already does the work.

**The timeline.** [P3-mod] The survivors believe Tung died or disappeared "a long time ago" / "before I was born" / "in the old war". Nobody in World 3 ever states a number of years; Tung's own "forty years" [GAME] stays his number alone. One NPC may doubt it ("Forty? He said forty? It felt longer.") — doubt, not confirmation.

**The engine.** [P5] Tung never appears in World 3. The **Keeper** holds "the old orders" — instructions Tung left the night the town fell — and, once he has seen the drill, executes them page by page, reluctantly. The **Elder** opposes; the **Guard** obeys; the others watch. Every NPC holds a different Tung (§2).

**What the player is made to wonder, and what is never answered.**
- [P12] The twelve brainrots Tung "keeps" [GAME] are raised sinisterly — the Guard remembers "he always asked for twelve"; the Elder asks what the player thinks happened to theirs — and **nobody says what happened to them**.
- [P7-mod] The Veteran implies the player is not the first person Tung has involved ("Another one?" energy). **Nobody explains who the others were or what became of them.**
- [P8 HOLD] The war's loss is **argued, never explained**: the Guard says Tung held the line; the Soldier says he saw him leave it; the Deserter says "I know what I saw" and will not say what. No NPC line and no environmental object establishes the truth.
- [P9 HOLD] The Ancient in the Whisperdeep is **not** tied to Tung's listening. It is old, it remembers the Keep being sealed, it speaks in questions, and it says nothing about what Tung heard.
- [P10] The forty-year listening involved **a machine**: the Keeper's chamber holds "the Elder's ear" — a brass listening horn that still hums faintly — and no one explains what it hears.
- [P11] The **mural** in the Keep's apse shows Tung and his captains; one figure has been chiselled out. The Guard: vandals. The Elder: "we did that the day we understood." The Keeper: nothing. **Never identified in World 3.**
- [P13] Under the Keep's altar: a **first door** the Deserter's key opens, and a **sealed second door** — warm light under it, a hum behind it, never opened. The Keeper: "He said never to open the second door."
- [P14-mod] The launch uses the Keep's geometry (§7) and shows **an old rocket**. No markings, no insignia, no interior, nothing military — nothing that exposes the moon-warship truth.
- [P15] [CANON] The rocket rises; the player believes it goes to the moon. The Elder's line has the energy of **"He kept it."** — kept *what* is left open.

**Tonal contract.** Every reveal answers one question and opens two. Nobody lies on purpose. Nobody is proven right.

## 2. NPC role design

[P6 HOLD] Names below are **placeholders** in the game's register and are marked `TBD`; code and config use the **role id** (`Keeper`, `Elder`, `Guard`, `Youth`, `Scavenger`, `Soldier`, `Veteran`, `Deserter`, `Ancient`), and the display name is a single string in `GardensNpcConfig` so renaming is a content change. [CANON] Humans tell the survivors' side; Brainrot NPCs hold the deeper secrets.

| Role id | Kind | Placeholder | Where (local coords) | Stance on Tung | Knows / never says | Gameplay function | Rig / motion |
|---|---|---|---|---|---|---|---|
| `Keeper` | human | Aldo | the Keep, apse, by the altar (30,−880 plateau, apse z −100) | Follows the orders; trusts neither them nor himself | Knows the crypt; says the least of anyone | **Main quest-giver** ("The Old Orders") | R15 rig (`NpcRigLife` idles it for free) |
| `Elder` | human | Nonna Ines | the Town square, by the well (−70,−232) | Blames him; runs the survivors | Remembers the flight; asks what happened to "his twelve" | Stance + the launch line; Blood Moon variant | R15 rig |
| `Guard` | human | Sgt Ottavio | the Keep's great stair, gate end | Hero-worship; keeps the banners | Says Tung held the line; blocks the crypt stair until stage 6 | Stance; contradicts Soldier | R15 rig |
| `Youth` | human | Tino | Verdant Court, fountain (0,700) | Born underground; curious, no grudge | Asks what the sky is like; repeats what he was told (badly) | Flavour; asks about the drill | R15 rig |
| `Scavenger` | human | Vespa | Fungal Hollow camp (1060,650) | Indifferent; pragmatic | Knows where the caches and the Deserter are | **Stage-6 gate**: two of her caches buy the Deserter's location | R15 rig |
| `Soldier` | human | Cpl Dario | Rootway landing (700,−300) | Bitter; disagrees with the Guard | "I saw him leave the line." (belief, not proof) | Stance; optional | R15 rig |
| `Veteran` | brainrot | Il Vecchio Bombardiro (species TBD) | Whisperdeep mouth (≈1050,−975) | Flew for him; tired | "Another one?" — nothing more | Cutscene beat 4; guards the tunnel | part-built, `NpcIdle` profile |
| `Deserter` | brainrot | Il Disertore (species TBD) | chamber behind Weeping fall #4 | Left him mid-war; unrepentant | "I know what I saw." Holds the crypt key | **Stage-6 key** after the Scavenger's caches | part-built, `NpcIdle` profile |
| `Ancient` | brainrot | Il Sussurro (species TBD) | Whisperdeep shrine end | None; older than the town | Remembers the Keep being sealed; speaks in questions | Optional discovery; one relic; Blood Moon line | part-built, `NpcIdle` profile |

Dialogue budget (P16-mod): every walk-up is **1–3 lines**, bucketed by arc state (`Before`, `Early`, `Mid`, `Late`, `After`) plus a `BloodMoon` variant; no NPC ever delivers a paragraph. Lore lives in the *differences* between them, not in any one speech. Conversations use `MerchantDialog.Show` unchanged.

## 3. Quest structure — "The Old Orders" (MAIN row)

[P16-mod] Seven stages, three of them skipping, one exploration, three short talks; no stage is a reading assignment. Structural copy of `TundraQuest` (stage kinds, one world-gated catch hook, bounded pity, cutscene notes on talk stages).

| # | Id | Kind | Objective | Gameplay | Beat |
|---|---|---|---|---|---|
| 1 | `Orders` | talk | Report to the Keeper | the walk teaches the world: gorge → plaza → causeway → town → spiral → Keep | The Keeper has heard the machine. He opens the orders. Guard salutes, Elder objects (one line each, in their own prompts) |
| 2 | `Muster` | count | 150 catches in the Gardens | the causeway lane | "He always started with a count." |
| 3 | `Relics` | gather | 6 relics turn up while skipping (3 banner scraps, 2 helms, 1 signal horn; 20% per landed skip, pity 8) | the causeway lane; the bell rings for the first time during this stage | each relic names a captain on a plinth (optional walk-up) |
| 4 | `Mural` | talk | Bring the relics to the Keep | walk | **Cut 3: the Mural** |
| 5 | `Bell` | count | 3 catches landed **while the bell rings** (Sentinel Hour) | the risk lane, on purpose | the defences target the player |
| 6 | `Crypt` | flag | Find who holds the crypt key | Scavenger → 2 caches → the Deserter's chamber → key; **Cut 4: the Veteran** plays at the Whisperdeep mouth on the way | **Cut 5: the Second Door** when the Keeper opens the first |
| 7 | `Launch` | talk | The last page | walk | **Cut 6: Launch**; `RocketUnlocked` stamped |

Rewards: proposed at the tundra arc's shape and roughly ×10 its scale (cash on 2/3/4, gems on 5/6, cash + key + one quest-only brainrot on 7). **Numbers are Balkan's** and sit in one config table.

Side content (SIDE rows, later plans): the **Scavenger's caches** (8 relic pickups in the discovery regions, the `SecretChim` pickup pattern) and the **Youth's errand** (talk-only in the first pass).

Data (all new, all backfilled on load): `GardensQuest` (stage index 0..8), `GardensProgress = { Catches, BellCatches }`, `GardensRelics = { Banner, Helm, Horn }`, `GardensDry`, `GardensCaches = {}` (set of cache ids), `CryptKey = false`, `RocketUnlocked = false`. Runtime attribute `HasRocketAccess`.

Remotes: `GardensTalk` (client → server, one string: the role id being spoken to), `GardensState` (server → client, the tracker's `State/Step/Of` shape plus `StageId, Kind, Title, Track, Met, Parts, Stages, Done, Unlocked, Note, Cleared, Salvage`).

Seams other plans fill: `ReplicatedStorage:GetAttribute("SentinelActive")` (the Bell stage counts only while it is true; set by the Sentinel Hour service), `GardensCaches` (written by the cache pickups), the `StoryCinematic` module (the client plays a cut when it exists and simply waits when it does not).

## 4. Cutscene structure

[P20] Six beats, camera only, each site-relative and skipped silently if its anchor has not streamed in. One shared client module `StoryCinematic` (Scriptable camera, HUD stand-down, hold-to-skip, timed restore, Humanoid.Died / CharacterAdded failsafes — the discipline `CatchCinematic.Takeover` already proves) plays a beat list; the quest client triggers it from `GardensState.Note`.

| # | Beat | Trigger | Anchor | Length | Shows | Withholds |
|---|---|---|---|---|---|---|
| 1 | **Descent** | `DepthsPortal` touch, first time | `FrozenTundra.DrillSite` (World 2, site-relative) | ~8 s | the camera drops into the shaft with the player; strata rush past a client-built tube under the curtain | — |
| 2 | **Arrival** | first `GARDENS_POS` placement | `LushGardens.Story.ArrivalAnchor` | ~15 s | dust settles; the auger's bit in the ceiling; the camera pulls back up the gorge to three survivors with lanterns at the slot mouth, staring; one steps back | any explanation |
| 3 | **Mural** | stage 4 cleared | `LushGardens.Story.MuralAnchor` (apse wall) | ~12 s | the camera rises along the relief and holds on the chiselled patch | who it was |
| 4 | **Veteran** | first approach to the Whisperdeep mouth during stage 6 | `LushGardens.Npcs.Veteran` | ~8 s | he looks at the player, then past them up the gorge: "Another one?" | who, what happened |
| 5 | **Second Door** | stage 6 cleared | `LushGardens.Story.CryptAnchor` | ~10 s | the first door opens; warm light and a hum under the second; the Keeper stops | the second door |
| 6 | **Launch** | stage 7 cleared | `LushGardens.Story.LaunchAnchor` (the crossing) | ~20 s | the Dial splits, the floor sinks, the crossing spire lifts with the rocket's nose, the dead west beacon lights, the survivors on the great stair, the Elder's "He kept it.", the rocket through the fissure; cut to black on faces | the destination beyond "the moon"; any marking on the rocket |

## 5. Devious gameplay layout

[P17] All readable, all learnable, **none lethal** (there is no per-world respawn yet). Rock skipping stays the centre: each mechanic changes where and when you skip.

| Mechanic | Where (local) | How it reads | Consequence | Reward |
|---|---|---|---|---|
| **Sentinel Hour** (hourly, ~12 min, on `IceFishingEvent`'s real-clock pattern) | bell in the Town's tallest tower (−150,−352); emplacements = the four Town tower beacons + the Keep's twin-tower beacons; targets = the causeway deck (x 0, z 250–430) and the Rootway decks | the bell rings 20 s ahead; beacons turn red; each bolt telegraphs with a light and a tone 1.5 s before its impact ring on the deck; warning signs at both causeway gates say what the bell means | a hit knocks the player into the Silverwend: the current throw is lost, they swim back | `WeatherLuck`-style luck spike for the hour (the "one seam to raise a Luck above 1"); stage 5 needs 3 catches under it |
| **The Rootway lane** | a second `ThrowZone` on root bridge #2 (≈844,−488), skipping along the ravine | a narrow plank deck, gappy rope rails, 46 studs above flooded water | falling = a swim out; it is the sentinels' first target | new `ZoneLuck` attribute on the zone (one additive read in `ThrowHandler`): the best lane in the world |
| **The escape tunnel** | from the Town's north tower (190,−420) under the hill to the crypt antechamber (30,−880 plateau, below the altar) — inside `Field.CAVE_ZONES` "the hill (grottoes)" | a bunker door, a collapsed passage, dust falling from the ceiling before the trigger | a rockfall part seals the way behind for 3 min; you arrive at the crypt, not the great door — further from the Keeper the first time | skips the 1,900-stud spiral once learned |
| **The broken span** | the causeway's middle span (x 0, z ≈340) | a plank gap you can see from the hub | a fall = a swim | the long way round is the Rootway |
| **Relic caches** (8) | Colonnade swim pocket (−1000,1010); behind fall #4; Whisperdeep end (≈1150,−1050 −210); Rootway landings ×2; Hollow shrine (1060,650); spiral overlook u≈0.46; the Keep's moat inlet | `SecretChim`-style prompt pickups in places the world already hides | none | Scavenger currency (2 buy the Deserter's location) + Index/Goals credit |
| **The wrong lever** | crypt antechamber | an obvious lever labelled for the great doors | closes them for 2 min and rings the bell early — once | knowledge |
| **The covered stair** | the Keep's great stair (lamps both sides) vs the Sanctum Overflow road bridge (55°) | the lit way is the sentinels' lane during the hour; the dark way is safe | time | route choice |

## 6. Environmental storytelling plan

Built by a new `GardensBuild.BuildStory` module writing **only** into `LushGardens.Story`, `LushGardens.Npcs`, `LushGardens.Caches` (so district re-runs never wipe it), followed by `Optimize.run()`. [P2 HOLD] **No moon or crescent device anywhere.** Banners carry the survivors' colours and the Keep's existing root motif; Tung is present only as a figure in the mural and as the make of his machines.

| District | Tier 1 (cheap, high signal) | Tier 2 | Tier 3 (optional) |
|---|---|---|---|
| Arrival chamber + gorge | rubble ring; the auger bit in the ceiling (static, `CaveDrillClient` palette); dust burst on first arrival; return portal re-skinned as the shaft lift ("The Shaft — up"); barricade + lantern posts at the slot mouth | survivors' footprints/lantern route | — |
| Verdant Court | one plinth toppled, one empty; relic names on the plinths as each turns up | vendors' lore lines | memorial tablet at the causeway gate |
| The Town | 4 of 12 houses repaired/makeshift (tarps, planked windows, crates, rugs, a stovepipe); 1 house ruined (fallen blocks, scorch); the well = Muster Well with a names carving; the bell in the tallest tower; warning signs at the causeway gates; dark lanterns at the far edge | supply room in the ruined house; bunker door under the north tower | a child's sky drawing in a window |
| The Keep | torn war banners; the **mural** with the chiselled figure; the altar as a war table with an old map (route drawn *up*); the **crypt** stair, antechamber, first door, sealed second door (hum), the lever; the Keeper's chamber with the **listening horn**; the west beacon dead | scorch/dent on the great door; barricaded transept | — |
| Rootway | barricades on the landings; the second lane | — | — |
| Weeping Cliffs | the Deserter's hideout behind fall #4 (bedroll, crates, a stolen banner) | — | — |
| Whisperdeep | the Veteran at the mouth; sound stones at the shrine (no explanation) | — | — |
| Drowned Colonnade | one island statue toppled; fallen drums re-read as engine parts; a relic in the swim pocket | — | siege wreck |
| Fungal Hollow | the Scavenger's camp; cache markers | — | — |

Foreshadowing items are deliberately few: the hum, the map, the horn, the dead beacon, the second door. [P18-mod] Blood Moon: the Town rings the bell and every NPC's line swaps to its `BloodMoon` variant ("Not tonight. Inside."); lanterns go dark. The Dial does nothing. Nothing says "machine".

## 7. Rocket-launch setup

[P14-mod] The existing Keep geometry maps onto the launch without a rebuild: the 24-segment **floor rune at the crossing** is the hatch ring ("the Dial"), the **crossing lantern + spire** is the rocket's nose, the **cathedral fissure** above (`Field.FISSURES[2]`, 205×165) is the exit. The rocket itself is "an old rocket" [CANON]: iron, rivets, a wooden gantry, no paint, no markings — and it is never seen from inside. Before stage 7 nothing on the surface of the Keep is different; the only tells are the hum under the altar, the map, the horn and the dead beacon. After stage 7 the Dial stays open as **a launch pad portal** `Dest = "Moon"` with `RequiresFlag = "RocketUnlocked"` and a `WorldTravelConfig` row `ComingSoon = true` — the same seam World 3 hangs off today. The moon-warship truth is not in World 3.

## 8. Economy — REPORT FIRST (P19-mod), not implemented

[GAME] Gardens skip on the Valley ladder and pool. A player who cleared 300 tundra catches, 20 Mythics and 10 Secrets arrives to 0.9 cash/s Commons. Two options, both preserve the rarity structure and modifiers exactly:

- **A. Full step-up** (recommended): `RarityConfigGardens` (bands slightly tighter than the tundra's), `BrainrotConfigGardens` = tundra crossover one rung up (Tundra Epic → Gardens Common, Legendary → Uncommon, Mythic → Rare; same creatures, same cash; Tundra Secret/God and Ice Fishing exclusives excluded) + 30 authored originals for Epic→God opening above 2,000,000/s, `RockConfigGardens` with a free starter. Content-drop art per `docs/brainrot-build-standard.md`. Changes the top of the economy by the same ratio World 2 did to World 1.
- **B. Interim**: keep the Valley alias, ship World 3 with the questline and mechanics, and accept that the lane is a story world until A lands.

Nothing from A is written until Balkan picks; the questline (§3) does not depend on the choice.

## 9. Technical architecture

**Files the lane owns (authored on disk now, applied in Studio at the window):**
`ReplicatedStorage/Modules/GardensQuestConfig.lua`, `GardensNpcConfig.lua`, `StoryCinematic.lua` (+ `StoryCuts/*`), `ServerScriptService/Modules/GardensQuest.lua`, `SentinelHour.lua`, `GardensCaches.lua`, `StarterPlayer/StarterPlayerScripts/GardensQuestClient.client.lua`, `GardensNpcClient.client.lua`, `SentinelClient.client.lua`, `GardensArrivalClient.client.lua`, `ServerStorage/GardensBuild/BuildStory.lua`, `BuildLaunch.lua`.

**Shared-file deltas (live from Studio via the bridge at edit time; only the World 3 delta is mirrored back):**
- `ThrowHandler.revealCatch`: one line after the tundra hook — `pcall(GardensQuest.NotifyCatch, player, tier.Name, throwWorld)` + one `require`; later one read of `ZoneLuck`.
- `Main.server.lua`: one `require` + one `GardensQuest.Init()` after `TundraQuest.Init()`.
- `PlayerDataManager`: seven default fields + seven backfill lines; `Snapshot` exports `RocketUnlocked`.
- `DevQuest`: a `gardens` verb family (`/tq gardens <status|reset|stage|fill|catch|relic>`).
- `TeleportService`: `NAV.Gardens` (Throw/Shops), `campWorld` for Gardens, the return-portal label, the launch-pad portal dest (Plan 6).
- `WorldTravelConfig`: the `Moon` row (Plan 6). `BoundsGuard`: unchanged.
- **Locked Round-3 file, additive only, needs Balkan's OK:** `QuestTrackerClient` — one `NPC.Keeper` identity + one `QUESTS` entry built from `GardensQuestConfig.Stages` (the same shape as the `TundraCave` entry) + one `require`.

**Instance contracts (Studio window):** prompts named `<Role>Prompt` under `GameWorld.LushGardens.Npcs.<Role>.PromptPart`; anchors `LushGardens.Story.{ArrivalAnchor, MuralAnchor, CryptAnchor, LaunchAnchor}`; the Bell stage reads `ReplicatedStorage.SentinelActive`; cache pickups are `LushGardens.Caches.<Id>` with a `CachePrompt`.

**Re-run hazard:** `BuildStory` and `BuildLaunch` clear and rebuild only their own folders; district modules are never re-run by this lane without Balkan's OK (they would wipe hand-placed stalls, plots and the zone).

## 10. Verification

There is no local Luau toolchain on this machine, so disk-authored code is verified by (1) static review against the tundra pattern and (2) Studio at the inspection window: `require()` every new module from the command bar, `/tq gardens stage <id>` to stand on each stage, `/tq gardens catch <tier> <n>` to drive the hook, a full playthrough of the seven stages, the six cuts framed with the real anchors, and a perf capture after `Optimize.run()` (parts / lights / emitters against the phase-1 baseline).

## 11. What needs the Studio window

Plans 2–6 place instances and run build modules; they cannot start until the five inspection items in the phase-1 report are answered (stall names/rigs, plots/zone/return-portal live state, `Optimize` state + perf baseline, the blockout's `Relocate()` state, a screenshot pass). Plan 1 (this design's story spine) and the design documents need nothing from Studio.
