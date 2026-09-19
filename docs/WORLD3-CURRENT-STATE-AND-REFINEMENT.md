# World 3 — current state + refinement report

**Lane:** World 3 refinement · **Branch:** `world3-refinement` (worktree `../skip-a-brainrot-world3`, off `ui-foundation@c68e17b`) · **Date:** 2026-09-19
**Status:** PHASE 1 — inspection and proposal only. Nothing in Studio was touched, nothing was built, nothing was merged. Waiting on Balkan's approval before any implementation.

## How this was inspected (and what it could not see)

Everything below comes from the repo, not from Studio. The other session owns the live Studio session (Bag / Round 4), so I stayed out of it.

- **World 3 scripts.** The `ui-foundation` mirror does not contain World 3 at all (it predates the 2026-09-19 re-sync). The byte-exact mirror on `source-sync-audit` (`../skip-a-brainrot-source-sync`, 493/496 live scripts as of 06:43 UTC today) does: `ServerStorage.GardensBuild.*` (22 build modules), `WorldProgression`, `WorldTravelConfig`, `WorldTravelService`, `CaveDrillClient`, `GardensAtmosphere`, `WorldsPanel`, plus the World 2 blockout generator. All World 3 facts below are read from those files.
- **World 3 geometry is script-generated**, so the layout can be read from code: `GardensBuild.Field` is the single height field every module stands on, and each `Build*` module is a district. That is why this report can describe the village, the castle and the caves without Studio.
- **World 2 context** comes from `docs/WORLD2-MASTERPLAN.md` and `docs/WORLD2-QUEST-AUDIT.md` on `origin/world2-overhaul` (live audit of 2026-09-19).

**What needs Studio, and why I stopped short of it.** These cannot be read from the mirror because they are hand-placed instances or measurements, not source. I will need the live session (or a saved `.rbxl`) for them before implementation — not before this report:

1. A screenshot pass of the Gardens as it renders today (hub, town, cathedral, each discovery region, the arrival chamber). Composition is readable from code; how it actually *looks* is not.
2. The five hand-placed Gardens stalls (`GardensShopStall / UpgradeStall / CharmStall / SellStall / EggStall`): their positions, their keeper models' names, and whether the four rig-complete keepers are the same rigs as the valley's.
3. Plots 13–18 (hand-placed; the build scripts do not create them), the Gardens `ThrowZone` (position, `SurfaceY`, `SkipDirX/Z`, whether it stands on the causeway), and `GardensReturnPortal`'s live `Dest` (build script says `Hub`, the World 2 audit says `Tundra`).
4. Whether `GardensBuild.Optimize.run()` has been applied to the current build (live light count under `GameWorld.LushGardens`), plus one performance capture with a player standing in the Verdant Court (parts streamed, memory, frame time).
5. Whether the World 2 blockout workstream has already run `Generator.Relocate()` (it moves Elder Tung + `DrillSite` + `DepthsPortal` to Elder's Dig). The descent sequence proposed below hangs off that site.

---

# PART A — WHAT EXISTS TODAY

## 1. Exactly what currently exists in World 3

World 3 is **the Lush Gardens**: a sealed underground cavern **2,960 studs square** (playable to ±1,230) centred on **(8000, 1000, −8000)**, built entirely by `ServerStorage.GardensBuild` (Terra writes a terrain shell — floor, ceiling, perimeter wall — from one height field; the districts are Parts on top). It is **BUILT and HELD BACK**: `WorldTravelConfig` marks Gardens `ComingSoon = true` (2026-08-19, "delete this one line to ship it"). Today nobody can enter it — the Depths shaft refuses everyone with a "🌿 The Lush Gardens are coming soon!" toast and puts them back on the shelf, and the Worlds board row draws COMING SOON.

Compass used below: **north = −Z** (the direction of progression, "walk north through the slot"), **east = +X**. Local coordinates are relative to the world origin above.

| District | Local centre | What it is |
|---|---|---|
| Arrival gorge + chamber | (0, 1280) → (0, 946) | A narrow winding slot cut through a 300-stud rock mass; the chamber at its far end holds the return portal and is where players land |
| **Verdant Court** (hub) | (0, 700), r 235 | Circular market plaza: fountain, ~14 stalls, 8 tents, 46 pieces of clutter, 12 banner poles, a ring canal with 4 bridges, a garden ring, 8 creature statues, a root arcade and 8 carved menhirs |
| The Silverwend | west→east across z≈380…176 | The river; the hub is south of it, the town north; crossed by the **Silverwend Causeway** at x=0 (arched span, 3 piers, gate arches at both ends) |
| **Aelunmyr** (town) | (−40, −250) | 12 gothic-elven houses on one climbing street, 4 beacon towers, a square with a roofed well, 2 streams with 4 footbridges, scattered roots/mushrooms/crystals |
| **Pilgrim Way** | spiral round the hill, r 470→300 | 360° climb (~1,900 studs, ~230 studs of height) with 8 stations: 3 overlooks, 2 shrines, 2 statues (stag, wolf), 1 ruin |
| **Verdant Sanctum** (cathedral) | (30, −880) on a plateau at ~y 340 | 200×300 footprint, 104-stud nave, twin west towers (196 tall, merlons, spires, beacons), crossing spire (tip ~610 studs above the cavern floor), polygonal apse, transept arms with rose windows, flying buttresses, a great stair cut into the hill, a **foundation moat**, interior columns, altar, hanging banners, a 24-segment glowing floor rune at the crossing |
| Great Cascade | (−1120, 380), west | A 108-wide waterfall out of a roof fissure, fed by a reservoir on top of the roof; plunge basin |
| Drowned Colonnade | (−930, 930), south-west | A flooded plaza with 22 (mostly broken) columns, fallen drums, 4 islands with statues (2 owls, 2 does); one deep pocket you must swim |
| Fungal Hollow | (1060, 650), south-east | A sunken bowl inside a raised rim; a 6-column ringed shrine among 10 giant mushrooms; spore particles |
| Rootway | (700, −300)→(1060, −770), north-east | A flooded ravine crossed by 4 giant-root bridges with plank decks, rope rails, lanterns, landings |
| Weeping Cliffs | (−1010, −620), north-west | A shelf with a tarn on top feeding 7 falls down a ~67° face; a **hidden chamber behind fall #4** (cat statue on a pedestal, pink crystals, a ledge in) |
| Whisperdeep | (1150, −1050), far north-east | A 210-stud crystal-lit tunnel driven back into the cavern wall, with a shrine, a green "DeepLight" and two green braziers at the end |
| Sanctum Overflow | 55° round the hill | The cathedral moat brimming over and stepping down the hill in 6 carved basins; the Pilgrim Way bridges it |
| Wildlife / effects | scattered | 17 animals (5 deer, 2 stags, 3 rabbits, 2 wolves, 2 cats, 3 owls on stumps), ≤34 firefly swarms, 7 pollen fields, ≤14 leaf-fall zones, 5 spore clouds, 8 butterfly emitters |
| Lighting | 6 roof fissures | Daylight falls through fissures over the hub, the cathedral, the cascade chimney, the hollow, a river bend and the ravine; everything else is lantern/crystal/Neon |

Live-only (Studio-placed, not in the build scripts — per the 2026-09-19 World 2 audit): `GameWorld.LushGardens` totals **42,902 parts**; **plots 13–18**; the five **Gardens merchant stalls** with rigged shopkeepers; a Gardens `ThrowZone`; `Portals.DepthsPortal` (World 2 side) and `LushGardens.Portals.GardensReturnPortal`.

## 2. Current village layout/content — Aelunmyr

`BuildTown`: **deliberately sparse** ("architecture set into nature, not a dense city"; about a third of the footprint is built on). One cobbled street climbs from the causeway (local (0, 40)) to the foot of the Pilgrim Way ((−16, −452)), gaining ~110 studs; lamps every 12 samples, flower patches between. **12 houses** on levelled stone podiums, alternating sides, set 44–70 studs back from the kerb, four stone/trim/roof palettes, curved or pitched roofs, some balconies, glowing coloured windows, each with 2–4 trees/bushes. **4 octagonal towers** (54–70 studs, cyan/gold beacons) at the town's corners. **A square** at (−70, −232): 4 rings of slabs, a roofed well with a lit water disc, 6 benches, 6 planters. **2 streams** carved into terrain with stepping stones and 4 arched footbridges. 26 pieces of nature scatter. Houses are **closed shells** (four full walls; the enclosure contract in `House`) — no enterable interiors, no doors that open, no furniture, no signage, no inhabitants.

## 3. Current castle layout/content — the Verdant Sanctum

There is no castle. There is a **cathedral**, and it is the world's primary landmark (built "to read from the hub 1,600 studs away"). `BuildCathedral`: stepped terrace + moat; a 70-step great stair with balustrades and lamps, cut into the hill; aisle walls with tracery windows and buttresses topped by spirelets and blob "gargoyles"; nave arcade + clerestory; lean-to aisle roofs; pitched nave roof with cresting; a five-sided apse with half-cone roof and spire; two closed transept arms with rose windows; a crossing lantern and 118-stud spire with a cyan beacon; a west front with a 30×44 iron-banded **GreatDoor**, a glowing tympanum sigil, a great rose window, a gable; **twin towers with string courses, merlons and gold-finial spires** (one cyan beacon, one gold); flying buttresses; **interior**: 14 fluted columns, altar step, altar with a gold "AltarLight", two cyan braziers, 14 hanging banners (pink/teal, gold trim), a 24-segment cyan **floor rune** at the crossing; 46 pieces of planting and 26 vines as weathering. Nothing inside can be interacted with. Nothing is damaged, defaced, sealed or hidden.

The castle-like bones are already there — moat, merlons, twin towers, an iron great door — which is what makes the reframing in Part B cheap.

## 4. Current underground content

The whole world is underground, but the parts that are *caves within the cave* are the discovery set (`BuildRegions`): the **Whisperdeep** tunnel + shrine, the **chamber behind the Weeping Cliffs falls**, the **Drowned Colonnade**, the **Rootway** ravine and the **Fungal Hollow** shrine. `Field.CAVE_ZONES` reserves **solid rock depth for tunnelling** under six areas — including **"the hill (grottoes)" (r 500, depth 150)** — but no grotto or tunnel has been cut under the hill. None of the discovery content has any reward, prompt, pickup, NPC or text; they are places to look at.

## 5. Current drill entrance

**World 2 side (Elder's Dig, east shore of the tundra lake):** the drill is drawn **per client** by `CaveDrillClient` off `TundraState`, anchored on the invisible `FrozenTundra.DrillSite` — salvage heap (stage ≥ Parts) → 17-stud derrick with the 5 cogs + 2 gears mounted (stage ≥ Fuel) → running rig with spinning auger, steam, chips, a pitched-down hum, **and the shaft**: a green Neon `PortalColumn` + `PortalPool` with ice shards and a "LUSH GARDENS" billboard at site-local Z+12. It is "the *look* of the way down, not the way down". The real trigger is `GameWorld.Portals.DepthsPortal.PortalTouch` (11×14×11, invisible) at that same spot with `Dest = "Gardens"`, `RequiresFlag = "CaveUnlocked"`, `LockedMessage = "🔒 The ice is solid here — Elder Tung's drill has not opened the way yet."`, `ComingSoonMessage`, and `RefuseX/Y/Z` (where a refused player is put back). Touching it runs `TeleportService.passesLock` (ComingSoon first, then the flag), then `teleportCharacter` with the **black curtain** (`TeleportFade`, world hops ≥ 400 studs) and a `RequestStreamAroundAsync` wait, then a `PivotTo` to `GARDENS_POS = (8000, 1031, −6676)` facing −Z. **There is no descent**: it is a portal touch, a fade, and a placement.

**World 3 side:** the player appears in the arrival chamber a few studs in front of `GardensReturnPortal` — an "arch of pale elven stone and living root" with a cyan veil, spire-topped piers, braziers, flowers and a "Return to the Valley" billboard — facing up a gorge lit by alternating cyan/green crystals and pink mushrooms. Nobody is there. The first thing the player reads is a sign pointing back the way they came.

Note: `BuildPortals` also knows how to build a **valley-side gate at (160, 4, 60)**; it is opt-in and was deliberately removed ("the way into World 3 is to come from WORLD 2, not from the valley"). The comment in `TeleportService` describing that meadow gate is stale.

## 6. Current NPC roster (World 3)

- **Shopkeepers only.** `MerchantConfig` gives Rocco (rocks), Enzo (upgrades) and Lil Miss (charms) an `AltStall` each in the Gardens; `ClientMain` binds `GardensSellStall`; `EggShopClient` binds `GardensEggStall`. `NpcRigLife` reports **four rig-complete R15 keepers in the Gardens** (auto-detected, each on its own idle from the public pool); `NpcBodyLife` and `NpcPropLife` give the four (Sell/Shop/Upgrade/Charm) their own body language and hand props ("Gardens: brighter and busier than the tundra"; the rock seller "tosses low and fast").
- **No lore NPCs, no humans, no brainrot characters.** `BuildLife` places animals only. `NpcIdle` animates the valley Elder Tung, Michael and the Secret Chim — nothing in the Gardens.
- Elder Tung is **not** in World 3. He has two bodies: `GameWorld.ElderTung` in the valley (rocking chair by the fishing hut) and `FrozenTundra.ElderTungTundra` in World 2.

For reference, the game's talking NPCs today: Elder Tung ×2, Stupid Gianluca, Maxwell the cat, Michael the eagle, Marco, Rocco, Enzo, Gino, Lil Miss — all through the one `MerchantDialog` shell.

## 7. Current quests (World 3)

**None.** No `GardensQuest*` module, no tracker row, no remote. The Goals board (`QuestHandler`) is world-agnostic. The only World 3 quest surface in the game is the *end* of Elder Tung's tundra arc: stage 7 `Activate` stamps `CaveUnlocked`, and his `Finished` line is "The shaft is open -- but what is down there is not ready for you yet. Soon. I have said everything I know."

## 8. Current Brainrot roster (World 3)

**None of its own.** `WorldProgression.Worlds.Gardens = { Alias = "Valley" }`: the Gardens skip on the **valley** ladder, roll the **valley** pool (161 entries), stock the **valley** rock shelf, and the Gardens egg stall has no `EggConfig` world so it reads "Coming Soon". No `RarityConfigGardens`, no `RockConfigGardens`, no Gardens Index tab (`IndexPanel` keys on worlds that own a pool). The comment on the alias says: "Give it its own Rarities/Pool/Rocks later and this alias is the only line that changes."

For comparison: World 1 = 161 (30/26/24/26/23/19/12/2 + quest-only Chim, Maxwell, Secret Pete, Pippo; 10 Forest-origin), World 2 = 110 (57 valley crossovers as Common/Uncommon/Rare, 30 authored Epic→God originals 75,000–2,000,000/s, 23 Ice Fishing exclusives, 4 forge).

## 9. Current progression (World 3)

Arrive → (no direction) → walk 600 studs of gorge → hub → shops on the valley shelf → skip on the valley ladder at the causeway zone (if it exists live) → walk onto a plot 13–18 to claim it → explore → leave by the return portal to the tundra arrival. No gate inside the world, no unlock, no goal, no reason to climb the hill. The Worlds board unlocks fast travel once the region has been stood in.

Three routing bugs will surface the day it opens: `TeleportService.NAV` has no `Gardens` entry, so the HUD's **Skip** and **Shops** buttons eject a Gardens player to the valley dock/lodge; `campWorld()` only knows Valley/Tundra, so **Plot** sends them to their *valley* camp (or claims a valley plot); and a **death or reset anywhere in the Gardens respawns at the valley SpawnLocation** (the World 2 blockout logged the same blocker for the tundra — "being fixed separately").

## 10. Current gameplay mechanics (World 3)

- **Rock skipping** on the shared engine: any `ThrowZone` part carries `SurfaceY`, `SkipStartZ`, and — added *for* the Gardens — `SkipDirX/Z`, because "the Silverwend causeway is crossed by open water 2,300 studs wide, and the point of standing on it is to skip off EITHER side". Throws clamp at 900 studs; luck is additive game-wide; weather events (global) add mutation odds.
- **Shops**: rocks, upgrades (valley shelf), sell; charms and eggs are "Coming Soon" (charms game-wide).
- **Camps**: plots 13–18, one per world, claimed by touching the platform.
- **Traversal**: swimming (the Silverwend, the flooded basin's deep pocket, the ravine), plank bridges, the 1,900-stud spiral, the 70-step stair. No damage, no fall damage, no traps, no timers, no events, no pickups.
- **Ambient**: wildlife and particles are non-interactive.

## 11. Current environmental storytelling

The fiction encoded in the build is **"ancient elven ruin, overgrown and serene"**: statues that "look like they have stood there for a thousand years", a colonnade where "the deeper it stood, the more of it has come down", shrines, menhirs with glowing carvings, a "pilgrim" way, a "sanctum". It is atmospheric and coherent — and it has **no relationship to brainrots, Elder Tung, Bacon Head, a war, or anyone living here**. The only in-world text is three portal/sign labels ("LUSH GARDENS", "The Lush Gardens", "Return to the Valley").

## 12. Existing cutscenes

- **`DrillBuild`** (6.4 s): camera arcs seaward-to-rig while the derrick's parts drop in bottom-up with ticks.
- **`DrillStart`** (6.4 s camera; ~3.4 s spin-up then the shaft reveal ~3.7 s): snow burst, a shockwave ring across the ice, the green column and sign fade in. Camera work is `CaveDrillClient.withCamera` — a Scriptable camera with a timed restore. Shots need `DrillSite` streamed in and ~30 studs clear on its lake side.
- **`TeleportFade`** curtain (0.22 s in) on every world hop.
- Not story: the catch reveal cuts (`CatchCinematic` Mythic/Secret/God/Huge/Massive/MassiveGod) and the egg ceremonies. `CatchCinematic.Takeover` is a serious framework — one run per client, timescale, hold-to-skip, cancel path, watchdogs, camera + HUD takeover *and restore* — but it is bound to the catch payload and Bridge.
- **World 3 has no cutscene at all**, including no arrival.

## 13. Existing Elder Tung references

- Valley NPC (`GameWorld.ElderTung` in `RockingChair`, prompt `TungTalkPrompt`; `NpcIdle` rocks him and lets his beard lag). `TungQuestConfig.NpcName = "Tung Tung Tung Sahur"` — he *is* one of the brainrot species (the Mythic "Tung Tung Tung Sahur" and the Legendary "Los Tungtungtungcitos" are in the valley roster; Michael's quest wants five mutated Sahurs).
- His valley lines: "Those brainrots... I HATE them. Bring me twelve … and I'll open the portal in my cellar." · "choose carefully, **I keep what you hand over**." · "The portal is open. What lies beyond is your problem now." · "It opens the cellar -- YOUR cellar. It will not turn for anyone else."
- Tundra NPC (`ElderTungTundra` in `ElderHut`, prompt `TungCavePrompt`, not idle-animated). His tundra lines are the closest thing to lore the game has: "There is a **cave under us**. Not a hole in the ice -- a CAVE, **older than the ice**, and **something down there is still awake**. **I have listened to it for forty years** and I am too old to go and look." · "It runs on the loud ones. The SECRETS … Ten of them, and **do not ask me how I know**." · "Then we find out what I have been listening to." · "It is open. **Whatever is down there -- it knows you are coming.**"
- Systems: `TungPortalUnlocked` / `HasCellarKey` (cellar hatch, drawn per player), `CaveUnlocked` / `HasCaveAccess`, the drill, the shaft sign, `DevQuest` `/tq` verbs.
- In World 3 itself: **none**.

## 14. Existing Bacon Head references

**None anywhere** — not in scripts, configs, rosters, docs or comments. Bacon Head is new canon and needs establishing from zero.

## 15. What already works well (keep)

- **One height field.** `Field.ground()` is the single truth; roads, podiums, water, props and scatter all sit on it. The hill spiral, the stair trench and the cathedral terrace are cut *into* terrain with backfill. This is why the world is not full of floating rocks, and it is the reason the additions below can be script-authored and re-run.
- **A landmark hierarchy** that already tells a route: arrival slot → plaza → river crossing → town → spiral → the building on the hill. Fissure daylight over exactly the places that matter.
- **Discovery content** that is genuinely hidden (behind a waterfall, at the end of a tunnel, on islands you swim to) — the bones of "secrets" are built.
- **Watertight builders** (`Arch.wall` slices, gable fills, `House` enclosure contract, `Water` source/clearance/rim rules) and a **prototype-and-clone** flora pass.
- **`Optimize.run()`**: kills ~2,400 decorative lights down to named hosts, turns shadows off on foliage and small parts, drops CanQuery on decoration. Re-runnable.
- **`GardensAtmosphere`**: a private colour grade + an `AtmoClaim` handshake with the tundra so the two worlds never fight over `Lighting.Atmosphere`; cave haze that does not follow the sun.
- **World plumbing that is one-line-per-world**: `WorldProgression` (pool/ladder/rocks), `WorldTravelConfig` (board + ComingSoon switch that the portals also obey), `BoundsGuard` regions, `MerchantConfig.StallWorld`, `EggHandler.STALL_WORLDS`, attribute-driven `ThrowZone`s, table-driven `QuestTrackerClient`.
- **The drill arc's discipline**: config-only dialogue, one catch hook (`NotifyCatch` gated on `throwWorld`), bounded pity, client-drawn per-player state, streaming-aware adoption, `DevQuest` shortcuts, "co-location is load-bearing" for cutscenes. This is the pattern a World 3 questline should copy.

## 16. What feels unfinished

No roster, ladder, rocks, eggs or Index tab. No quests, no NPCs, no arrival moment, no text. No Daily Wheel or leaderboards (`WheelBoard.SITES` / `LeaderboardBoards` have valley + tundra sets only). The three routing bugs and the valley respawn. The return portal says "Return to the Valley" while (live) sending players to the tundra. Hill grottoes reserved but never cut. The discovery regions have nothing to find. Houses are shells with no doors. The travel-board blurb ("Overgrown terraces down the gorge") is the only description a player ever reads.

## 17. What feels generic

The vocabulary — "elven stone", Aelunmyr, Verdant Court/Sanctum, Pilgrim Way, menhirs, runes, crystals, a dragon statue, glowing mushrooms, fireflies, a fountain plaza with pink/teal/gold tents — is competent fantasy-asset-pack language. It could be the third world of any game. Twelve houses from one recipe. Shrines that honour nothing. Wildlife that belongs to no ecosystem the story cares about. "Sparkly garden" is the exact opposite of "this game is starting to mess with me."

## 18. What conflicts with the new lore direction

1. **A paradise, not a refuge.** Pristine, serene, nobody home. The brief needs a war-scarred underground where people were *driven*.
2. **No people.** Survivors, descendants, the village, the castle garrison — none exist. The only humans are vendors.
3. **A cathedral, not a castle.** Fixable by reframing (see §27); the geometry already has a moat, merlons and a great door.
4. **Names.** Lush Gardens / Verdant Court / Aelunmyr / Verdant Sanctum / Pilgrim Way carry no Tung, no war, no fear. Some can stay as the *old* names of the place (what the ruin was called); the survivors need their own words.
5. **"I HATE them."** The valley Tung despises brainrots and destroys the twelve he takes; the brief has him *leading* Brainrots in a war. This is not a rewrite problem — it is a **devious hook** if handled as "he keeps what you hand over" (§21).
6. **The promise vs the place.** The tundra arc promises "a CAVE, older than the ice… something down there is still awake… it knows you are coming." The built Gardens deliver nothing awake and nothing that knows. That promise must be paid in World 3.
7. **The transition.** "Physically descend through the earth" vs. a portal touch + curtain. And on arrival the first readable object points home.
8. **Valley gate remnants.** A stale `TeleportService` comment and an opt-in build path for a valley→Gardens gate that the story forbids.
9. **The arc's tone.** "Prove yourself: 300 catches" is transactional; it needs the World 3 side to make the transactions look, in hindsight, like something else.

## 19. Performance concerns

- **42,902 parts** in `LushGardens` plus a 2,960²×~900 terrain shell, before any additions. `NpcRigLife` already avoids "rescanning 58k descendants on a timer" for the whole workspace.
- **Lights and shadows** are the dominant cost by the build's own measurement (~2,400 lights pre-optimise). Whether `Optimize.run()` was applied to the *current* live build is unknown (Studio item #4). Every addition proposed below must end with re-running it.
- **~68 ParticleEmitters** in `Effects` (fireflies, pollen, leaves, spores, butterflies) — "every emitter costs GPU whether anyone is looking at it or not"; already sparse, but new FX (sentinel bolts, dust, launch) must be budgeted against these.
- **Streaming**: an 8,000+-stud hop pages the whole world in; the curtain hides pop-in. Anything that must be *seen* on arrival (survivors, rubble, the auger) has to be within the streamed radius of `GARDENS_POS` or drawn client-side like the drill.
- **Re-run hazard**: every `Build*.run()` starts with `folder:ClearAllChildren()`. Any hand-placed object *inside* `Hub/Town/Cathedral/HillPath/Roads/Water/Regions/Caves/Wildlife/Effects` is wiped by a re-run. New story content must live in **its own folders** (`LushGardens.Story`, `LushGardens.Npcs`, …) or be authored into the build modules.
- **Per-world cost of NPCs**: rig-complete R15 keepers animate for free (`NpcRigLife`, one idle track each, root-driven body language). Part-built brainrot NPCs need procedural idles (`NpcIdle` profiles). Both are cheap; humanoid pathing/walking is not and is not proposed.

## 20. Technical limitations

1. **No per-world respawn.** Death/reset → valley spawn. Any "consequence" design that ends in death is off the table until the shared fix lands; consequences in §25 are all *soft*.
2. **No damage system** exists anywhere; "traps" must be knockbacks, resets, timers, closed doors and lost throws.
3. **No story-cinematic framework.** The drill scenes are ad-hoc `withCamera` takeovers; `CatchCinematic.Takeover` is catch-specific. Story cuts need a small shared module (§30) rather than five copies of `withCamera`.
4. **Dialogue is linear**: `MerchantDialog.Show(lines…)` with one primary and one decline. Conflicting *opinions* are easy (different NPCs); player *choices* are not, without extending the shell — and the Round 3 dialogue/quest/prompt surfaces are **locked** (`MerchantDialog`, `UIKit.QuestCard`, `InteractionPrompt`, `QuestTrackerClient`, `QuestBarClient`). World 3 plugs into them; it does not change them.
5. **Custom NPC gestures need the Animation Editor** (human upload). Procedural root motion and props are what the code can do.
6. **Cutscene co-location**: shots need their anchors streamed in; the `DrillSite` contract ("if not site then return end") applies to anything new.
7. **Mirror drift**: World 3's scripts exist only on `source-sync-audit`; `ui-foundation` does not know World 3. The lane branch is off `ui-foundation`, so before code edits the mirror has to be brought over (recommendation in §36).
8. **World 2 is being rebuilt** (blockout in flight; Elder's Dig, `DrillSite` and `DepthsPortal` move as one rigid unit). The descent scene must be authored site-relative, exactly like `CaveDrillClient`.
9. **Weather is global** and `GardensAtmosphere` only owns the atmosphere while weather is Clear — a valley Sandstorm can tint the cavern. Small extension needed if weather is used underground (§32 uses Blood Moon deliberately).
10. **Throw clamp 900 studs**; the causeway's "2,300 studs of open water" is scenery.
11. The build is **deterministic from seeds**; hand edits inside build folders do not survive a re-run (see §19).

---

# PART B — PROPOSAL

Guiding rule: **reuse the built world, change what it *means*.** Every district already exists; the refinement re-dresses, names, populates and gates it. No district is rebuilt.

## 21. Refined World 3 story structure

**The reframe.** Forty years ago Elder Tung and his Brainrots lost the war against Bacon Head on the surface. The people of the castle town fled *down* — into a cavern nobody knew was there, "older than the ice", already full of ruins of something that lived here first. They dug in. The Gardens are what forty years of survivors made of an ancient ruin: the plaza became their market, the elven town their village, the great building on the hill their **Keep**. Their children were born under a stone sky and know the surface only as a story.

**The arrival.** The player does not come through a gate. They come through the ceiling of the gorge, in the wake of a drill — and they carry **Elder Tung's Seal** (given at the end of the tundra arc: a crescent over three notches, which players will read as "a moon over a log"). The survivors thought Tung died in the war. The Seal says otherwise. Every reaction in the world keys off that: *you came from HIM.*

**The engine of the chapter.** Tung is absent, which is the point. His will reaches the player through the **Keeper of the Keep**, who holds the "old orders" Tung left the night the town fell, and who executes them — reluctantly — once the Seal is shown. The **Underground Elder** opposes. The **Old Guard** worships. The **Veteran** brainrot mutters "Another one?" and will not say what happened to the others. The **Deserter** knows why the war was really lost. The **Ancient** in the Whisperdeep is what Tung was "listening to" — and it has been listening back.

**The turn.** The orders end at a door under the Keep's altar that the Keeper was told never to open. Behind it is machinery that should not exist down here. The Elder recognises it before the player does: **"He kept it."** The Keep was never a chapel; the spire is a fairing; the hill is a silo. The rocket launches toward what looks like the moon. World 3 ends with the survivors watching the sky through the fissure — and not one of them cheering.

**Tonal contract:** every reveal answers one question and opens two. Nothing here says "warship". Nothing here says Tung is a villain. Everyone is a little bit right.

## 22. NPC changes/additions

**Reuse and expand first.**
- The five Gardens vendors become **survivors' market vendors** with a walk-up lore line each (their `Dialogue` is per-merchant across worlds today; a per-stall override line is a small `MerchantConfig` addition). Rocco: "Rocks? Down here we call them *ammunition*." Lil Miss (Coming Soon anyway): a charm "for the day the bell rings".
- **Elder Tung (tundra)**: two config-only additions — the `Activate.Done` line hands over the Seal ("Take this. Show it to whoever is left. They will know it."), and `Finished` changes after World 3 begins (see §31). No new Tung body.
- **Michael the eagle** (optional, one line): why *he* collects mutated Sahurs. Not required.

**New humans (R15 rigs, so `NpcRigLife`/`NpcBodyLife` animate them for free):**

| NPC (working name) | Archetype | Where | Function |
|---|---|---|---|
| **Keeper Aldo** | Castle Keeper | Keep apse, by the altar | **Main quest-giver by proxy**: reads the Seal, runs "the Old Orders", refuses the second door. Knows the most, says the least. |
| **Nonna Ines** | Underground Elder | Town square, at the well | Runs the survivors. Blames Tung. Delivers "He kept it." Side errands. |
| **Sergeant Ottavio** | Old Guard | Keep great stair / gatehouse | Believes Tung was a hero; keeps the banners; blocks the crypt until the orders say otherwise. |
| **Tino** | Young Survivor | Verdant Court fountain | Born underground; asks what the sky is like; side quest ("bring me something from up there" — any valley-origin catch, hand-over pattern). |
| **Vespa** | Scavenger | Fungal Hollow / Drowned Colonnade | Trades in relics; the map to the discovery regions; the only one who knows where the Deserter hides. |
| **Corporal Dario** | Former Soldier | Rootway landing / a town tower | Witnessed the Colonnade fall; his memory contradicts Ottavio's. Optional. |

**New brainrot NPCs (unique, non-catchable, forge-baked or part-built; `NpcIdle` profiles):**

| NPC | Archetype | Where | Function |
|---|---|---|---|
| **Il Vecchio Bombardiro** | Wounded Veteran | Whisperdeep mouth (or the bell tower) | A one-winged old bomber crocodile who flew for Tung. Recognises the Seal: the "Another one?" beat. Never says what happened to the others. |
| **Il Disertore** | Deserter | The chamber behind the Weeping Cliffs falls | Left Tung during the war. Knows why it was lost. Holds the key to the first crypt door. Found only through Vespa. |
| **Il Sussurro** | Hidden / Ancient | Whisperdeep shrine (the green DeepLight) | What Tung "listened to for forty years". Speaks in questions. Opens the last beat. Its identity is withheld. |

**Priority:** Aldo, Ines, Ottavio, the Veteran, the Ancient are the core five; Tino, Vespa, Dario, the Deserter are the second wave (the Deserter is needed for the crypt beat; Dario is the most droppable). Names are placeholders in the game's naming register (Rocco/Enzo/Gino/Marco/Gianluca; Italian-brainrot for creatures) — Balkan's call, as with Nico.

## 23. Human vs Brainrot NPC roles

- **Humans tell the human war**: the flight underground, who died, who blames whom, what the town lost, what the children were told. They *disagree with each other* (Ottavio vs Ines vs Dario) and none of them lies on purpose.
- **Brainrots hold the secrets**: the Veteran knows there were *others before you*; the Deserter knows *why the war was lost* (something Tung did, not something Bacon Head did); the Ancient knows what the Keep really is. Each brainrot beat is short, uncomfortable, and unanswerable in World 3.
- **Vendors are texture**, one line each, never exposition.

## 24. Quest progression

One main arc (**"The Old Orders"**, MAIN row, run by Keeper Aldo) copied structurally from `TundraQuest` — a shared `GardensQuestConfig`, stage kinds `count`/`gather`/`talk`, one `NotifyCatch` hook gated on `throwWorld == "Gardens"`, bounded pity, cutscene notes on talk stages — plus two SIDE rows (Tino, Vespa). Stage table:

| # | Id | Kind | Objective | Beat / reward |
|---|---|---|---|---|
| 1 | `Seal` | talk | Show the Seal to the Keeper | Ines objects on the spot; Ottavio salutes. **Cutscene: Arrival** has already played. |
| 2 | `Muster` | count | 200 catches in the Gardens ("Prove the surface still skips") | Cash. Ottavio: "He always started with a count." — the first hint this arc *rhymes* with the last one on purpose. |
| 3 | `Relics` | gather | 8 Captains' relics surface while skipping (salvage/pity pattern) | Each relic lights a plinth story on the eight hub statues; the 8th is the Deserter's, and the Keeper does not want it found. |
| 4 | `Mural` | talk | Bring the relics to the Keep | **Cutscene: the Mural.** Cash + gems. |
| 5 | `Bell` | count | 3 catches landed during Sentinel Hour ("Wake the sentinels") | The devious stage: the player powers the defences and the defences target the causeway (§25). Gems. |
| 6 | `Whisper` | talk | Find what the Elder listened to (Whisperdeep) | The Ancient. **Cutscene: Veteran** plays on the way in (he guards the mouth). The Deserter's key opens the first crypt door. |
| 7 | `Contingency` | talk | Open the orders' last page | **Cutscene: the Second Door**, then **Cutscene: Launch**. Cash + key + the arc's quest-only brainrot. `Unlock = true` stamps `RocketUnlocked`. |

Side rows: **Tino** (hand-over: one valley-origin brainrot; reward gems + a line that lands later), **Vespa** (relic caches in the five discovery regions; reward: the map to the Deserter + a charm when charms ship). Rewards scale ×10 on the tundra arc (which paid 180M cash / 450 gems / 1 key) — numbers are Balkan's.

## 25. Devious gameplay mechanics

All readable, all learnable, none lethal (no respawn in-world yet):

1. **Sentinel Hour** (hourly, ~12 min, the mirror-image of Ice Fishing): the bell in the town's top tower rings, the four tower beacons turn red, and the Keep's old defences — built to stop Bacon Head's army — wake and "defend" the Silverwend against the only thing moving on it: the player. Slow tracer bolts arc onto the causeway on a fixed rhythm (light + tone 1.5 s before impact, impact ring on the deck). A hit knocks the player into the river: lost throw, swim back, nothing else. During the hour the lane is *worth it*: the `WeatherLuck` seam ("the one seam to raise a Luck above 1") gives the hour a real luck spike. Warning signs at both causeway gates say exactly what the bell means.
2. **The Rootway lane**: a second `ThrowZone` on the widest root bridge — narrow plank deck, rope rails with gaps, the flooded ravine 46 studs below. New `ZoneLuck` attribute (one small `ThrowHandler` read) makes it the best lane in the world, and it is the sentinels' first target.
3. **The escape tunnel**: cut the reserved hill grotto — a collapsed passage from the town's top tower to the Keep's crypt that skips the 1,900-stud spiral. A rockfall trigger seals it behind you for 3 minutes (dust falls from the ceiling first; the trigger part is fixed, so it is learnable) and drops you at the crypt, not the great door — which is *further* from the Keeper the first time.
4. **The broken span**: the causeway's middle span is planked over a gap; the safe route is the long way round by the Rootway. Both are visible from the hub.
5. **Relic caches**: eight pickups (the `SecretChim` prompt-pickup pattern) in exactly the places the world already hides — the swim pocket in the Colonnade, behind fall #4, the far end of the Whisperdeep, the Rootway landings, the Hollow shrine, an overlook on the spiral. Exploration pays; nothing is invisible.
6. **The wrong lever**: in the crypt antechamber, an obvious lever "opens" the great doors — it actually closes them for two minutes and rings the bell early. Once. Then you know.
7. **Misleading defensive route**: the Keep's two flanking stairs; the lit one is the sentinel-covered one. The dark one is the safe one. The lamps were placed by soldiers, not for pilgrims.

Rock skipping stays the centre: every mechanic above changes *where and when* you skip, not what skipping is.

## 26. Village improvements (Aelunmyr → "the Town")

Re-dress, not rebuild, in a new `BuildStory` module (own folders; survives `BuildTown` re-runs): 4 of 12 houses become **repaired/makeshift** (tarps, planks over windows, crates, rugs, a stove pipe — all existing `Props`); 1 house **ruined** (collapsed roof of fallen blocks + a scorch); the square's well becomes the **Muster Well** with a names carving; the top tower gets the **bell** and the Old Guard's banner; lanterns near the Keep carry the Seal's crescent, lanterns at the far edge are *dark* (they ration light — a quiet tell); **warning signs** at the causeway gates; a **bunker door** under the top tower (the grotto mouth); an old **supply room** in the ruined house (crates, empty). Ines at the well, Tino at the fountain, Dario on a tower. Optional: one house gets a door that opens onto a one-room interior for the Keeper's records if we want a reading spot outside the Keep.

## 27. Castle improvements (Verdant Sanctum → "the Keep")

Keep the geometry, change the reading, all in the interior and on the west front: **war banners** with the crescent-and-notches sigil, half of them torn (`P.banner` variant); the **mural** on the apse wall (a 40×20 relief of Tung and eight captains under a crescent, one figure **chiselled out** — never identified in World 3); the altar becomes a **war table with an old map** whose route is drawn *up*, not across; the crossing rune becomes **the Dial** (24 segments already) that brightens at night under the fissure; **battle damage** on the great door (a dent, scorch, a missing band) and the west tower's beacon **dead** ("hasn't lit since the war" — it lights for the launch); the **crypt**: a stair under the altar step to an antechamber with the **first door** (Deserter's key), the **second door** (sealed, humming — the drill's hum pitched down — bearing the sigil), and the wrong lever; the **Keeper's chamber** in a transept arm with the **listening horn** (a brass relic; "the Elder's ear"). NPCs call it the Keep; folder names stay `Cathedral`.

## 28. Underground improvements

- **Arrival chamber → the breakthrough**: rubble ring, the auger's bit protruding from the ceiling (static prop matching `CaveDrillClient`'s palette), a settling dust burst on first arrival, and the return portal re-skinned as a **lift cage/rope ladder up the shaft** labelled "The Shaft — up", not an elven gate. Lantern posts and a hastily built **barricade** at the slot mouth: they were afraid of what came down.
- **Whisperdeep → the Ancient's lair**: the shrine stays; add sound stones and the Veteran at the mouth.
- **Behind the falls → the Deserter's hideout**: bedroll, crates, a stolen banner; the cat statue stays as his only company.
- **Drowned Colonnade → "where the Colonnade fell"** (the first battle): one island statue toppled, a broken siege thing in the water (fallen drums re-read as engine parts), a relic in the swim pocket.
- **Rootway → the crossing they held**: barricades on the landings, Dario, the second lane.
- **Fungal Hollow → Vespa's field**: her camp, relic caches, the "wrong" mushrooms marked.
- **Hill grottoes → the escape tunnel** (§25.3), cut with `Terra.reseal` after.

## 29. Environmental storytelling (the full list, prioritised)

Tier 1 (cheap, high signal): Seal sigil on banners/lanterns/the crypt door; the mural with the chiselled figure; the empty/toppled plinth; makeshift homes; warning signs; the dead west beacon; the barricade at the gorge; the Muster Well names. Tier 2: the war table map; the listening horn; the ruined house + supply room; battle damage on the great door; the Deserter's hideout; Vespa's camp. Tier 3 (optional): a memorial on the causeway gate, a children's drawing of the sky in a house window, the Colonnade's siege wreck. All built from `Props`/`Arch`/`Creature` primitives already in `GardensBuild`, followed by `Optimize.run()`.

## 30. Cutscene sequence (all short; camera only, dialogue via the existing shell before/after)

A small shared `StoryCinematic` client module (borrowing `CaveDrillClient.withCamera`'s restore discipline and `CatchCinematic`'s HUD stand-down + skip-hold) so each cut is a beat list, not a copy of camera code. Every cut is anchored site-relative and bails if its anchor is not streamed.

1. **Descent** (World 2 side, extends `DrillStart`, ~8 s): after the ice gives way the camera drops into the shaft with the player; strata rush past a client-built tube while the curtain and the Gardens stream. Pays "physically descend" without moving worlds.
2. **Arrival** (World 3, first arrival only, ~15 s): dust settles; the camera pulls back up the gorge to find **three survivors with lanterns at the slot mouth**, staring. One sees the Seal on the player and steps *back*. Ines's line lands (direction: "You came from him?" — not that wording). Cut to the player. The three stay as walk-up NPCs.
3. **The Mural** (Keep apse, ~12 s): the camera rises along the relief — Tung, the captains, the crescent — and holds on the chiselled patch long enough to be noticed. Ottavio and Ines give different one-line answers afterwards.
4. **The Veteran** (Whisperdeep mouth, ~8 s): Il Vecchio Bombardiro looks at the Seal, then at the player, then past them up the gorge: the "Another one?" beat. No explanation.
5. **The Second Door** (crypt, ~10 s): the first door opens on the Deserter's key; warm light and a hum from the second; the Keeper stops at it. "He said never to open the second door." He does not.
6. **Launch** (~20 s, the one long cut): the Dial splits, the crossing floor sinks, the spire fairing folds, the west beacon lights, the survivors gather on the great stair, Ines: **"He kept it."** The rocket rises through the cathedral fissure toward the moon; the fissure frames it; cut to black on the survivors' faces, not the sky. Destination reads as the moon. Nothing else is shown.

## 31. Elder Tung foreshadowing (he is never on screen)

- The **Seal** hand-off line in the tundra (config-only) and his `Finished` line changing once World 3 starts: "Did they still talk about me?" — the first time he asks a question.
- Retroactive re-reads with zero new content: "**I keep what you hand over**" (what did he do with the twelve brainrots?), "**do not ask me how I know**" (the fuel), "**it knows you are coming**", "**forty years**" (= the war).
- Every human account contradicts another: hero (Ottavio), the reason they are down here (Ines), the one who told them to *wait* (Dario), the one who left orders for a day he never said would come (Aldo).
- The Veteran's "Another one?" — he has sent people before. Nobody says what happened to them.
- The Deserter: the war was lost because of something Tung *did*, not something Bacon Head did. He will not say what.
- The Ancient: "He listened. Did you think he was listening to *me*?"

## 32. Moon/warship foreshadowing (subtle, none conclusive)

- The **sigil**: a crescent over three notches — reads as "moon over a log" (he is a log). It is on the Seal, the banners, the crypt door, and (one brass plate) on the drill.
- **The Dial** under the cathedral fissure brightens at night and pulses **red during Blood Moon** (`GardensAtmosphere` extension: claim the atmosphere for that one event).
- The **listening horn** — his forty years of listening were done by a machine.
- The **war table map** with a route drawn *up*; Tino's question about the sky; Ottavio: "He always said the answer was above us."
- The **second door**: machinery, warmth, a hum, no explanation. Never opened in World 3.
- The **launch** through a fissure that was "always there". The destination is the moon. Nothing artificial is shown.
- **Not** done: no "moon is a ship" hints, no hangars, no engines, no insignia on the moon. The rhyme is structural — the player has just learned a chapel was a silo — and the game leaves it at that.

## 33. Brainrot improvements

- **The regression problem is real**: aliased to the valley, a player who paid 300 tundra catches + 20 Mythics + 10 Secrets to get here would catch 0.9 cash/s Commons. World 3 needs its own ladder and pool *before* it opens, or opening it demotes the player.
- **Recipe = the tundra crossover, one rung up**: Tundra Epic → Gardens Common, Tundra Legendary → Gardens Uncommon, Tundra Mythic → Gardens Rare (same creatures, same cash, no new art); Tundra Secret/God stay tundra-exclusive; Ice Fishing exclusives excluded (like Forest-origin was). **30 authored originals** for Epic→God in the tundra's 10/8/6/4/2 shape, cash opening above the tundra God ceiling (2,000,000/s), on a `RarityConfigGardens` ladder slightly tighter than the tundra's. Theme: **war-touched and stranger** — Epic "the rank and file", Legendary "the siege engines", Mythic "the captains", Secret "the deserters and ghosts", God "the ones who never surfaced". Names via the same handoff doc process as `WORLD2-UPPER-TIERS.md`, placeholders until then.
- **Construction**: forge-baked MeshPart templates per `docs/brainrot-build-standard.md` (≤ 12 colour roles, Neon ≤ 3, no scripts, no animation data, one FX host) — the pack profile, not the 270-part voxel style. A content drop: model in `BrainrotModels`, `HeightScale`, `PrimaryPart`.
- **One quest-only brainrot** for the arc (the audit flagged the tundra arc has none), Unique + `QuestOnly`, granted at stage 7.
- **`RockConfigGardens`** (first entry free, rule of the shelf) so Rocco has something to sell; a Gardens egg set is optional and can stay Coming Soon.
- Rarity structure, Golden/Diamond and Huge/Massive: **unchanged**.

## 34. Rocket quest progression

The rocket *is* stage 7 of "The Old Orders" (§24); it is not a separate quest. Gating: stage 6 (the Ancient + the Deserter's key) → the first crypt door → the orders' last page → the Launch cut → `RocketUnlocked` stamped on the profile (`GardensQuestConfig.RewardFlag`) + `HasRocketAccess` runtime attribute, exactly mirroring `CaveUnlocked`/`HasCaveAccess`. The launch pad (the Dial) becomes a portal `Dest = "Moon"` with `RequiresFlag = "RocketUnlocked"` and a `WorldTravelConfig` row with `ComingSoon = true` — the same seam World 3 hangs off today, so World 4 gates on it with no code.

## 35. Final World 3 story beat

The survivors on the great stair, the rocket gone, the fissure empty, the west beacon lit for the first time in forty years. Ines does not look up. Tino does. Ottavio salutes. The Keeper closes the second door without ever having opened it. The tracker reads COMPLETE, the pad reads COMING SOON, and the last line the player gets is the Veteran's: "Tell him we are still here." Then Tung's `Finished` line in the tundra, if they go back: "Did they still talk about me?"

## 36. Recommended implementation order

0. **Lane hygiene** (decision): bring the World 3 mirror onto `world3-refinement` (merge `source-sync-audit`, which the audit says merges into the `ui-foundation` lineage without conflict) so the branch can edit `GardensBuild` and `World*` files. Studio items 1–5 above.
1. **Opening blockers** (small, shared): `NAV.Gardens`, `campWorld` for Gardens, the return portal label, the stale valley-gate comment; coordinate on the per-world respawn fix (do not duplicate the tundra's).
2. **Economy**: `RarityConfigGardens`, `BrainrotConfigGardens` (crossover + 30 originals as art lands), `RockConfigGardens`, the `WorldProgression` line, Index tab falls out.
3. **Story config + quest module**: `GardensQuestConfig` / `GardensQuest` / `GardensQuestClient` copied from the tundra trio; tracker row; `DevQuest` verbs; the Seal hand-off in the tundra config.
4. **NPCs**: the core five, dialogue in config, prompts under `GameWorld.LushGardens` (streaming-aware bind), `NpcIdle` profiles for the brainrots.
5. **Environmental pass**: `BuildStory.lua` in `GardensBuild` (own folders), then `Optimize.run()`, then a part/light count.
6. **Devious mechanics**: Sentinel Hour service (modelled on `IceFishingEvent`'s clock), the Rootway zone + `ZoneLuck`, the grotto cut + trap, relic pickups.
7. **Cutscenes**: `StoryCinematic` module; Descent, Arrival, Mural, Veteran, Second Door.
8. **Rocket set piece** + Launch cut + the World 4 seam.
9. **Flip `ComingSoon`** for Gardens. World 4 is not started.

Each step is its own commit on the lane; nothing merges to `ui-foundation` until Balkan says so, and steps 1–2 are the only ones that touch shared files.

---

# PART C — THE FOUR QUESTIONS

**A. What should the player FEEL during their first 10 minutes in World 3?**
Wonder that curdles. The drop is loud and fast; the cavern opening past the gorge is the biggest space they have seen in the game — and the first people they meet are not glad to see them. The feeling to hit is *"this place is beautiful and I am not welcome, and it is because of who sent me."* Then agency: a market that will trade with them, a lane they can skip, a hill with a building on it that everyone keeps glancing at. And one small "the game is messing with me" beat inside those ten minutes — the bell rings for the first time while they are on the causeway.

**B. What should the player THINK about Elder Tung when they first arrive?**
That he is exactly what he has been for two worlds: gruff, generous, right. He paid them 180 million, built a drill for them, opened a world for them. The only puzzle should be why he did not come. Their confidence in him should be at its highest at the moment the first survivor steps back from the Seal.

**C. What should the player QUESTION about Elder Tung when they leave World 3?**
Whether he lost the war or left it. What he did with the twelve brainrots he "keeps". Who the *others* were, and where they are. Why the town's elder said "he kept it" like an accusation. Why a village elder's contingency is a rocket, and why the people he led were never told. What is behind the second door, and why he was listening to something for forty years through a machine. And the one they will not be able to phrase yet: why does everyone down here know his sigil, and why is it a moon?

**D. What information should be deliberately withheld until the moon/warship world?**
That the moon is the warship — and whether Tung built it, found it, or was given it. Who was chiselled out of the mural. What happened to the "others" he sent. Whether Bacon Head is dead, defeated, or waiting. What the Ancient in the Whisperdeep actually is. What the twelve brainrots were for. Whether the survivors were left behind by accident or by design. What is behind the second door. And the meaning of "he kept it" — kept the ship, or kept the war.

---

*End of report. Waiting on approval before Phase 2.*

---

# PART D — WORLD 3 LORE APPROVAL BOARD (added 2026-09-19 after Balkan's direction review)

Balkan approved the emotional/story direction (trust → doubt → suspicion; moon/warship withheld until World 4) but not the specific hooks. This board is the source of truth for what may be built on. **Nothing in the PROPOSED table is built until it is moved up.**

## LOCKED CANON (Balkan)

Elder Tung exists in World 2 · the player completes his World 2 quest · the player drills DOWN into World 3 · World 3 already contains a village and a castle · Elder Tung and his Brainrots fought Bacon Head and LOST · the people of this area were driven underground · World 3 is significantly more lore-driven · NPCs hold conflicting opinions of Tung · humans tell the survivors' side; important surviving Brainrot NPCs reveal deeper war secrets · World 3 is more devious in gameplay and tone · completing the major Tung/World 3 progression eventually gives access to a rocket · the player believes it goes to the moon · the moon is secretly Tung's warship · the full reveal belongs to the NEXT world; World 3 only foreshadows · cutscenes are short, cinematic, mysterious, devious · presentation target: denser, more intentional, Anime-Expeditions-level, original to Skip Rocks.

## ALREADY EXISTS IN GAME (verified in the mirror; may be built on freely)

| Fact | Where |
|---|---|
| Tung has two bodies: valley (`GameWorld.ElderTung`, rocking chair) and tundra (`ElderTungTundra`, `ElderHut`); none in World 3 | `NpcIdle`, `TundraQuestConfig`, World 2 audit |
| Tung's species is Tung Tung Tung Sahur (Mythic roster entry; Legendary "Los Tungtungtungcitos"; Michael collects 5 mutated Sahurs) | `TungQuestConfig.NpcName`, `BrainrotConfig`, `MichelQuestConfig` |
| Valley quest: hand over **twelve** brainrots (5 Epic, 5 Legendary, 2 Mythic); they are destroyed; lines "Those brainrots... I HATE them", "choose carefully, **I keep what you hand over**", "What lies beyond is your problem now" | `TungQuestConfig`, `TungQuest` |
| Tundra arc pays **180,000,000 cash, 450 gems, 1 key** across 7 stages and stamps `CaveUnlocked` | `TundraQuestConfig.Stages[*].Reward` |
| Tundra lines: "a CAVE, older than the ice… **something down there is still awake**. **I have listened to it for forty years**", "It runs on the loud ones… **do not ask me how I know**", "**Whatever is down there -- it knows you are coming**", `Finished`: "not ready for you yet. Soon." | `TundraQuestConfig` |
| The drill (salvage → built → running) and the green shaft are drawn per client; the way down is `DepthsPortal` (`RequiresFlag = "CaveUnlocked"`, `ComingSoonMessage`, `RefuseX/Y/Z`); entry is a portal touch + black curtain, not a descent | `CaveDrillClient`, `TeleportService` |
| World 3 = the Lush Gardens: gorge → Verdant Court → Silverwend causeway → Aelunmyr (12 houses, 4 towers, square/well) → Pilgrim Way → Verdant Sanctum (cathedral with moat, merlons, twin towers, great door, altar, banners, 24-segment floor rune) + Great Cascade, Drowned Colonnade, Fungal Hollow, Rootway, Weeping Cliffs (hidden chamber behind fall #4), Whisperdeep (tunnel + shrine); 8 creature statues in the hub; hill grottoes reserved but uncut | `GardensBuild.*` |
| World 3 has no roster (aliased to Valley), no quests, no lore NPCs (4–5 shopkeepers only), no cutscenes, no in-world text beyond three labels; held back by `ComingSoon = true` | `WorldProgression`, `WorldTravelConfig`, `BuildLife` |
| Return portal in the arrival chamber (built as "Return to the Valley"; live `Dest` reportedly Tundra) | `BuildPortals`, World 2 audit |
| Weather events include **Blood Moon** and **Shooting Star** (global) | `WeatherHandler` |
| The World 2 respawn/checkpoint blocker (death → valley spawn) | `World2Blockout.Generator` header, `TeleportService` |
| Zero Bacon Head references anywhere | grep of the full mirror |

## PROPOSED — NEEDS APPROVAL

| # | Proposal | Why it improves the story |
|---|---|---|
| P1 | **The Seal** — a token Tung hands over at the end of the tundra arc; survivors recognise it | Gives every "you came from HIM" reaction a visible, diegetic cause; one object carries the whole arrival tension |
| P2 | **The Seal's sigil is a crescent over three notches** ("a moon over a log") | Plants the moon in plain sight with an innocent in-world reading, so World 4 recontextualises something the player has looked at for an hour |
| P3 | **The survivors believed Tung died in the war; "forty years" = the war's date** | Makes his existing "forty years" line the war's timestamp for free and makes "he is alive" a real shock |
| P4 | **The Gardens are an ancient pre-war ruin the survivors fled into and fortified; the cathedral is their Keep (the castle); its defences were built against pursuit by Bacon Head** | Reconciles the built world with canon without rebuilding a district, and pays "a cave older than the ice" |
| P5 | **Tung never appears in World 3; the Castle Keeper executes his "old orders" as proxy** | Keeps him mysterious and morally open while preserving one main questline; his absence is the tension |
| P6 | **Cast + stances** — Keeper Aldo (proxy), Nonna Ines (blames him), Sgt Ottavio (hero-worship), Tino (born below, asks about the sky), Vespa (scavenger), Cpl Dario (contradicting witness); brainrots Il Vecchio Bombardiro (veteran), Il Disertore (deserter), Il Sussurro (the ancient in the Whisperdeep) | Covers every required archetype with the smallest cast; each holds a different Tung. Names are placeholders |
| P7 | **"Another one?"** — the Veteran implies Tung has sent others before; nobody says what became of them | The most devious line available: implies a pattern without stating a fact; deliberately unresolved |
| P8 | **The Deserter knows the war was lost because of something Tung DID** (not something Bacon Head did); he does not say what | The "deeper war secret" the brief assigns to brainrot NPCs, and it keeps Bacon Head from being the whole answer |
| P9 | **The Ancient is what Tung "listened to" — and it has been listening back** | Pays the "something down there is still awake" promise inside World 3 while withholding what it is |
| P10 | **The listening horn** — his forty years of listening were done by a machine | The first "technology too advanced for this setting" tell, built on an existing line |
| P11 | **The mural** in the Keep with one figure chiselled out, never identified in World 3; NPCs give conflicting answers | The brief's castle-cutscene beat; "conflicting memories" delivered by one object |
| P12 | **The sinister reading of the twelve** — NPCs make the player ask what he did with them | Turns existing text into suspicion with zero new content |
| P13 | **The crypt: a first door (Deserter's key) and a sealed, humming SECOND door that is never opened** | A physical withheld answer the player can stand in front of; the World 4 seam |
| P14 | **The Keep is the silo** — the floor rune is the hatch, the spire the fairing, the launch goes through the existing cathedral fissure | Uses existing geometry; "the thing you thought was X is a machine" rhymes with the moon reveal structurally instead of verbally |
| P15 | **"He kept it."** (Ines) and the dead west beacon lighting for the launch | The finale's emotional button; the beacon is a cheap, readable visual tell |
| P16 | **"The Old Orders"** questline shape (7 stages: Seal → Muster → Relics → Mural → Bell → Whisper → Contingency), rewards ~×10 tundra, one quest-only brainrot | Plugs into the proven `TundraQuest` pattern; every stage is a story beat, not a fetch |
| P17 | **Sentinel Hour** (hourly: the Keep's old defences wake and "defend" the causeway against the player), the Rootway lane, the escape tunnel + rockfall, relic caches, the wrong lever | Devious gameplay rooted in the war; all consequences soft (no death) until the respawn fix lands |
| P18 | **Blood Moon → the Dial pulses red** under the fissure | Moon foreshadowing through an existing weather, once per rare event |
| P19 | **Roster recipe**: tundra crossover one rung up + 30 "war-touched" originals; own ladder and rocks before opening | Fixes the economic regression and sets the tone; content drop, not code |
| P20 | **The six cutscene beats** (Descent, Arrival, Mural, Veteran, Second Door, Launch) at 8–20 s | Covers the brief's four required moments within the time budget |

P1–P15 are lore; P16–P20 are structure. Approving P4, P5 and P13/P14 unlocks the most; P7/P8/P9 are the ones to weigh carefully because they set what World 4 must answer.
