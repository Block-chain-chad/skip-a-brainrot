# World 2 (Frozen Tundra): functional fixes and art pass (2026-09-21)

BEAST seat. Branch `world2-overhaul`. It was built in place in the shared Team Create place and is
**not published**. The publish hold from the greybox round still stands: nothing publishes until
Balkan signs off, or until the rollback (§10) has been run.

The pass continues [WORLD2-BLOCKOUT-LOG.md](WORLD2-BLOCKOUT-LOG.md). The layout is the one Balkan
approved. Nothing was restarted, and routes were not redrawn.

Screenshots at player eye level:

- `docs/qa/world2/before/` and `docs/qa/world2/after/` hold the same 13 viewpoints, from `_qa_views`.
- `docs/qa/world2/play/` holds the functional round's in-game shots.
- `docs/qa/world2/play_after/` holds the in-game shots from the final QA.

---

## 1. What survived (step 1, checked before any change)

- The whole greybox layout is intact:
  - Frostgate
  - Warming Circle
  - the Avenue and its six camps
  - the Warmhouse
  - the lake and dock
  - Elder's Dig
  - Nico's Point
  - the Squeeze
  - the Blue Hollow
  - Eagle's Crag
  - the lookout
- No other lane had touched World 2's objects or scripts.
- The lake, dock, `LakeBarrier` and `ThrowZone` are untouched.
  - The fingerprint is identical after every terrain write of this pass (79,394 water voxels, checksum 3,732,629.8).
  - Paint and props stay out of the lake guard. They also keep 8 studs clear of the dock and ThrowZone.

## 2. Functional fixes (step 2)

| Problem | Fix | Where |
|---|---|---|
| Dying or resetting in World 2 respawned the player in the valley | Tracks where each death happened; a death in the Tundra region respawns at the Tundra arrival | `TeleportService` (`watchDeath`, `RESPAWN_DEST`) |
| After travelling in, the camera kept its old heading, so some players faced the portal home | Tundra arrivals (portal and fast travel) send the arrival's look. The client turns a Custom camera to it and keeps zoom and pitch. The valley is unchanged | `TeleportService` (`aim`), `TeleportFadeClient` (`aimCamera`) |
| Birds flew through cliffs and terrain edges | They fly at 2170–2210 and pick a heading whose whole crossing is clear of terrain (8 headings, 3 lanes); if none is clear, the flock is skipped | `TundraBirds` |
| Michael's prompt never showed (he perched above the camera, and a prompt only shows while its parent is on screen) | Moved to a nest at eye level at the lookout gallery's west end, facing the approach | `Art.BuildNest` / `MoveMichael` |
| Peak, north wall and falls were invisible from town (StreamingEnabled: terrain 1,500+ studs away is never sent) | The Sundered Peak is now a Persistent part model (89 parts, no collision, no shadows). The terrain peak is removed | `Art.BuildPeak` |
| Rock intruding into the Warmhouse's back corners (279 voxels from the cliff dressing) | Hall interior kept clear of terrain, out to the side walls' outer faces | `Art.ClearWarmhouseInterior` |
| Hairline of sky around the Warmhouse ceiling (roof slab 0.05 above the walls) | Shell walls raised 0.1 (once) | `Art.BuildWarmhouse` |
| No path led from Nico's door to the Squeeze (the canyon opens behind his lodge) | A painted trail around the lodge's south side, with the BLUE HOLLOW sign beside it | `Art.PATHS.NicoToSqueeze` |

Elder Tung is unchanged: character, lore, dialogue and quest logic. His station is now his original
hut from the old tundra, in the same footprint, with the door where the greybox door was (§4). Both drill
cutscene camera paths were raycast after the art went in, and all five lines are clear.

## 3. Layout (step 3): targeted corrections only

- **Michael:** moved to the nest (above).
- **Sundered Peak:** now a part model. It sits in the same place, is larger, and carries the falls.
- **Paths:** the greybox strips are replaced by paint (§4). Added:
  - a spur from the Avenue up each camp's ramp (6)
  - the Nico's → Squeeze link
- **Lake cliffs:** relief was cut back into the cliff faces (setbacks, gullies, skyline steps, cornices). Nothing was added toward the water.
- **Elder's station:** the greybox box was swapped for Tung's hut on the same spot.

## 4. Art and polish (step 4)

All of it is built by `ServerStorage.World2Blockout.Art` (repo: `game-src/world2/World2Art.lua`). Every
step rebuilds its own folder under `FrozenTundra.Art`. Every art part is anchored and has CanTouch off,
CanQuery off unless it collides, collision only where people walk into it, and shadows only for big
pieces. Each is stamped `WorldArt`.

- **Terrain:**
  - The walls were reskinned from Glacier to Slate, keeping the ice where it reads as ice: the Hollow, the Cellar Pass and the falls notch.
  - The walls were dressed with buttresses, bulges, snow shoulders, ledges, icefalls and cornices.
  - The lake cliffs got relief.
  - The Warming Circle, the Avenue and the camp spurs are Cobblestone; every road and trail is Sandstone. The materials were picked against Mud, Ground, Limestone and Pavement in eye-level samples.
  - The town floor has 32 low wind drifts, plough ridges along the Avenue, and snow banked around the tents and Tung's hut.
- **Town (Frostwatch):**
  - The Warming Circle has a stone-ringed fire in the house style (a small Neon ember bed, a `Fire`, one warm light), a cooking tripod and pot, three benches and a woodpile.
  - A signpost at the Circle has six arrows, each turned toward its real destination.
  - A FROSTWATCH timber gate stands over the Avenue's mouth.
  - Five lanterns are staggered down the Avenue.
  - An expedition camp has two of the old village's tents, a cold fire pit, crates and a loaded sled.
- **Frostgate:** a timber fence replaces the flat greybox rails, on the same lines with the same gaps.
- **Warmhouse, outside:**
  - a lean-to roof rising to the cliff it is built into
  - a timber frame and a stone plinth
  - a porch on log posts
  - framed windows with deep-amber panes (a dim Neon that stays under Bloom's threshold)
  - the name board, door lanterns, icicles, and taller chimneys with smoke
- **Warmhouse, inside:**
  - roof beams on wall posts
  - a central hearth under an iron hood, with a rug and four benches
  - the eight hall lamps rebuilt as hanging lanterns (same places, slightly dimmer)
  - banners
- **Elder's Dig:**
  - Tung's hut, turned so its door opens onto the porch
  - a brass listening horn on a stand, aimed at the Crack
  - the Crack as a jagged rift, roped off on stakes
  - the ancient stone as stacked faceted rock with carved glyphs
  - scaffolding against the glacier wall, crates, a pickaxe, and a lit post
- **Nico's Point:**
  - the lodge with log walls, a gable roof, corner posts, a framed door with a lantern, a warm window, and a smoking chimney
  - trophy fish, rods, and two drying racks with fish
  - the jetty on pilings with a lamp at its end, and a punt moored just past it
  - No new systems: it stays environmental.
- **The Squeeze:** six lanterns down the canyon, on alternating sides. Their deep-amber lamps are the waymarks, and they are brighter than street lamps. A sign stands at the mouth. Before this, the slot was black at eye level.
- **Blue Hollow:**
  - seven clusters of ice crystals
  - the Warm Eye: steam off the open water, a low amber glow in it, and broken ice round the rim
  - a lamp at Nico's shanty
- **Eagle's Crag:** the rope bridge has its four posts.
- **Removed:** every greybox label, plus the greybox pieces the art replaced (`Art.RETIRED`: path strips, circle disc, bonfire, signpost, lanterns, Frostgate rails, Warmhouse hearth and lamp boxes, the Dig's station, chimney, horn, crack and stone, Nico's stove glow, the Squeeze placeholders, the Hollow's glacier sticks).

**Lighting (`TundraAtmosphere`, World 2's own client script, with `Lighting.TundraGrade`):**

| Setting | Before | After |
|---|---|---|
| Exposure cut | −0.70 | −0.40 |
| Contrast | 0.26 | 0.12 |
| Saturation | +0.10 | −0.05 |
| Brightness | −0.02 | 0 |
| Haze density | 0.26 | 0.20 |
| Haze | 1.9 | 1.1 |
| Tint | 214,230,255 | 238,244,255 |

Every art capture was taken under this grade, and it is live in Play. The old cut was set for a
white plain and turned the rebuilt town to dusk.

**Unchanged:**

- `Lighting.Brightness`, which WeatherClient owns.
- The atmosphere during weather events, which WeatherClient owns.
- World 3's `AtmoClaim`.

## 5. Performance (step 5), measured in Studio after the pass

| Scope | Parts | MeshParts | Colliding | Shadow casters | Semi-transparent | Neon | Lights | Particles | Fire |
|---|---|---|---|---|---|---|---|---|---|
| FrozenTundra (all) | 2,664 | 230 | 790 | 1,142 | 146 | 146 | 48 | 9 | 6 |
| of which `Art` (this pass + peak + nest) | 941 | 90 | 166 | 83 | 6 | 9 | 34 | 9 | 4 |
| of which `Hub.Stalls` (5 stalls, not mine) | 1,056 | 76 | 221 | 708 | 134 | 127 | 6 | 0 | 0 |
| of which `Ruins` (galleon, watchtower) | 218 | 0 | 122 | 124 | 4 | 1 | 0 | 0 | 0 |
| of which `Greybox` (remaining shells) | 82 | 0 | 76 | 48 | 0 | 4 | 3 | 0 | 0 |
| Plots 7–12, wheel, boards, stall prompts | 729 | | 360 | 574 | | | 24 | 12 | 6 |

- **No light casts shadows.** There are no scripts in `FrozenTundra` and no server-side animation. The peak is the only Persistent model.
- **Net this round:** Art went from 131 to 941 parts and the greybox from 168 to 82. That is about +725 parts in FrozenTundra, and +24 lights: town 8, Warmhouse door 2, Dig 4, Nico 2, Squeeze 6, Hollow 2. The interior's 9 replace the greybox's 9.
- **Terrain paint and the town's snow add no parts.**
- **Trimmed in this pass:**
  - 50 semi-transparent art parts made opaque (crystals, icicles, window panes)
  - 2 crystal lights dropped
  - Ruins: CanTouch off on all 218 parts, shadows off on the 94 under 4 studs, query off on the 96 that don't collide. Nothing scripts against the ruins.
- **Biggest single cost left, for the stall owner:** `Hub.Stalls`. Frost Eggs alone is 657 parts with 109 Neon, and the five stalls have 386 touchable parts and 708 shadow casters. I did not modify them (§9).

## 6. Final QA (all in Play, 2026-09-21)

| # | Check | Result |
|---|---|---|
| 1 | World 1 → 2 travel | **Pass.** The valley Tundra portal lands at (−8243, 2034, −8283) facing the town, with the camera aimed |
| 2 | World 2 spawn | **Pass.** The arrival frames the tunnel mouth and the town (`play_after/a01`) |
| 3 | Respawn / reset | **Pass.** A death on the Warming Circle respawns at the Tundra arrival, not the valley |
| 4 | Main paths | **Pass.** Walked end to end: arrival → descent → Circle → Warmhouse; the east road → Dig ramp → Tung's porch; ramp A → ledge → ramp B → bridge → lookout ramp → gallery; the west road → Nico's → jetty end; Nico's → round the lodge → the Squeeze → the Blue Hollow; the Frostgate → ledge ramp → High Ledge → the Dig; the Avenue → camp spurs → terraces (Plots 7 and 11) |
| 5 | Ice fishing | **Not re-run** after the art (the event is hourly and couldn't be forced from this account). Passed in full earlier this round. Static checks since: holes unchanged, nearest new prop 72 studs away, and the lighter haze helps the holes' dark water. The atmosphere script stands aside during the blizzard |
| 6 | Elder Tung | **Pass.** Prompt shows, dialogue opens, LEAVE closes, camera restored. Both drill cutscenes' camera lines are clear of the new props |
| 7 | Michael | **Pass.** Prompt shows at the nest, dialogue opens, LEAVE closes, camera restored |
| 8 | Nico's Point | **Pass.** Lodge, jetty and the link to the Squeeze walked |
| 9 | Fast travel | **Pass.** Worlds → Valley lands at the hub; Worlds → Tundra lands at the Frostgate with the camera aimed and the grade on |
| 10 | NPC prompts | **Pass.** All five Warmhouse stall prompts show (Eggs, Sell, Shop, Upgrades, Charms), plus Tung and Michael |
| 11 | Cave / later-world gate | **Pass.** The Depths shaft refuses this profile and returns it to (−8325, 2025, −7710), clear of the new props |
| 12 | Mobile traversal | **Not testable** through the Studio tools. Static: paths 6–22 wide, snow bumps under ~2.5 studs, ramps unchanged, the hut step is 1 stud |
| 13 | Collision | **Pass** on every route above; no snags. The only stops were Roblox's 8 s MoveTo timeout and each camp's own PlotBoard |
| 14 | Camera restore | **Pass.** Custom camera following the Humanoid after both dialogues and after every travel |
| 15 | Return travel | **Pass.** The return portal lands at the valley cellar, grade off |

- No World 2 script errors in the output during the session.
- The nav buttons also land correctly in World 2:
  - Shops puts you inside the Warmhouse facing the counters.
  - Skip puts you on the ice dock facing up the lake.

## 7. Remaining problems

- **Ice fishing:** needs one live check during a blizzard (see QA 5).
- **Mobile:** needs a device test.
- **Pathfinding:** still cannot route the Squeeze. It walks fine by hand, leg by leg.
- **Nav buttons (Skip/Shops/Plot):** these don't turn the camera on short hops (under 400 studs) in any world. It's shared `TeleportService` / `TeleportFadeClient` behaviour, left alone. After "Shops" in the tundra the camera can still face the door.
- **High Ledge path:** the Sandstone reads greenish-grey in the ledge's blue shade.
- **Generator:** `Outside()` still builds the terrain peak. `Art.RebuildTerrain` clears it straight after, so use that order (§8).
- **Studio only:** thin cyan outlines in Edit-mode captures inside the Warmhouse are a Team Create collaborator's selection outline. They are not in the game; Play captures are clean.
- **Rejoin:** a rejoin still starts in the valley. A persisted last world is a player-data decision.

## 8. Build order (how to reproduce)

```
local G = loadstring(ServerStorage.World2Blockout.Generator.Source)()
local A = loadstring(ServerStorage.World2Blockout.Art.Source)()
-- terrain: A.RebuildTerrain() does ClearAll + every greybox step + every art terrain step
--   (~60 s: run it in two calls, as done here, or it times out)
-- parts: G.BuildParts(); then
A.BuildPeak(); A.BuildNest(); A.BuildTown(); A.BuildFrostgate(); A.BuildWarmhouse()
A.BuildWarmhouseInterior(); A.BuildDig(); A.BuildNico(); A.BuildSqueeze(); A.BuildHollow()
A.BuildCrag(); A.TuneRuins(); A.RetireGreybox()
```

Each step rebuilds its own folder. Terrain steps refuse any write that would reach the lake zone, and
the fingerprint was compared after each.

## 9. Found in other lanes (reported, not changed)

1. **New this round:** `ClientMain` line 142 waits forever on `GameWorld.SellStall:WaitForChild("PromptPart")`. The valley Sell stall has lost its PromptPart (World 1 or the stall owner).
2. **Still present:** `CellarDoorClient` waits on `GameWorld.Cellar.Entrance.Padlock:WaitForChild("Body")` (the World 1 cellar).
3. **Still present:** a stray `Workspace.Script` prints "Hello world!" at startup.
4. `Hub.Stalls` is World 2's largest cost (§5). The Frost Eggs stall's display is egg-lane work, so a flag pass by its owner is recommended: CanTouch off, and shadows off on small parts.
5. **Merge risk:** the `source-sync-audit` mirrors hold pre-greybox versions of TeleportService and the other scripts changed here. The Trading lane's PreGrandExchange backups also cover TeleportService, BoundsGuard and WorldTravelConfig. Live is correct.
6. The DevQuest `/tq` allowlist is UserId 125861722 only, so this account could not force the blizzard. That's the owner's call.
7. **Studio:** the Assistant/MCP plugin logged a version change ("restart Studio to fix").
8. **Test-profile side effects** (LIDL_Beast, this round): +33 emeralds from a daily-quest payout during the final Play session. Earlier this round: about +0.48T offline earnings and one Uncommon fishing catch.

## 10. Rollback (unchanged command, now covers this pass)

```
loadstring(game:GetService("ServerStorage").World2Backups_2026_09_19.Rollback.Source)().Restore()
```

What the rollback covers:

- It restores the pre-greybox FrozenTundra, which removes all of the art: the Art folder, the peak, the nest and Michael's move.
- It clears and repastes the Tundra terrain. Every art terrain write sits inside what `ClearAll` clears: wall faces top out at 2150 plus a few studs of cornice, the reskin stops at 2160, and `ClearAll` goes to 2262 (2760 north of the bounds, where the terrain peak was).
- **New:** before the blockout-era script restore, it puts back `ServerStorage.AuditBackups.PreWorld2Pass_2026_09_21`: TeleportService, TeleportFadeClient, TundraBirds, TundraAtmosphere, and the TundraGrade tint. The blockout-era backups then win for TeleportService.
- It was **not** run. The repo copy and the Studio module are byte-identical.

## 11. Files

| File | What |
|---|---|
| `game-src/world2/World2Art.lua` | NEW. The art pass (= `ServerStorage.World2Blockout.Art`, 102,216 B, byte-identical) |
| `game-src/world2/World2Rollback.lua` | Covers the art pass (= `World2Backups_2026_09_19.Rollback`, 4,264 B) |
| `game-src/place-full/ServerScriptService/TeleportService.server.lua` | Respawn in World 2; camera aim on Tundra arrivals |
| `game-src/place-full/StarterPlayer/StarterPlayerScripts/TeleportFadeClient.client.lua` | NEW mirror. Turns the camera to the arrival look |
| `game-src/place-full/StarterPlayer/StarterPlayerScripts/TundraBirds.client.lua` | NEW mirror. Birds clear of terrain |
| `game-src/place-full/StarterPlayer/StarterPlayerScripts/TundraAtmosphere.client.lua` | NEW mirror. The re-tuned grade |
| `docs/WORLD2-ART-PASS.md` | This file |
| `docs/qa/world2/*` | Before/after and in-game screenshots |

`game-src/world2/World2Blockout.lua` (the generator) is unchanged. All four mirrors are byte-exact from
Studio via the bridge. `_MANIFEST.txt` is not regenerated on this branch (it lives on
`source-sync-audit`).
