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
-- terrain: NEVER call A.RebuildTerrain() on the live place -- see §12. Run the steps
--   individually instead. (It starts with ClearAll and times out at ~60 s; a second call
--   RESTARTS from ClearAll rather than resuming, so a timeout can wipe completed work.)
-- parts: G.BuildParts(); then
A.BuildPeak(); A.BuildNest(); A.BuildTown(); A.BuildFrostgate(); A.BuildWarmhouse()
A.BuildWarmhouseInterior(); A.BuildDig(); A.BuildNico(); A.BuildSqueeze(); A.BuildHollow()
A.BuildCrag(); A.TuneRuins(); A.RetireGreybox()
-- identity pass (2026-09-23), in this order:
A.BuildSkyline()          -- terrain only
A.BuildWarmhouseHero()    -- edits Greybox.Warmhouse roof/chimneys + Art.WarmhouseHero
A.BuildArrivalApproach()  -- relights CellarPass lanterns + Art.ArrivalApproach + terrain rock
A.BuildLakeShore()        -- raises the near-shore bed; see §13 for the fingerprint
A.BuildDockApproach()     -- C3
A.BuildDigCamp()          -- C4
-- visual pass (2026-09-24, ITEM 8), in this order:
A.BuildArrivalApproach()  -- (re-run) tunnel reskin Glacier->Slate, Glass+Neon-core lamps, crystals
A.BuildCampDressing()     -- CampSpire prisms -> crystal meshes; unclaimed pads -> frosted Slate
A.BuildRuinRubble()       -- floating rubble cubes -> terrain piles on the gallery floor
A.BuildDockSnow()         -- dock snow tiles -> low terrain drifts (above y2000.5, no water touched)
A.BuildCampVariation()    -- tent colours + hearth turn per camp (Campfire/CampStand NOT moved)
A.BuildSpurDrifts()       -- terrain drift ridges between the spur paths
A.BuildIceCamp()          -- two fishing huts on the lake banks
A.BuildWarmhouseFront()   -- AFTER BuildWarmhouse + BuildWarmhouseHero: gable, bays, crest, glass
-- dusk/night pass (2026-09-24, ITEM 9): re-run A.BuildArrivalApproach() for the cool tunnel
-- lamps and crystal fills; the rest is runtime (TundraAtmosphere) or IceFishingEvent.buildHole
-- (the ice-field markers live in IceFishingEvent.buildHole and only exist during a freeze)
```

Each step rebuilds its own folder. Terrain steps refuse any write that would reach the lake zone, and
the fingerprint was compared after each. The exceptions are `BuildLakeShore` and the C3 boulders in
`BuildDockApproach`, which write inside the lake margin on purpose (the lake bed is their subject);
each bounds its own writes and was fingerprint-checked, see §13.

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

---

## 12. QA tips (added 2026-09-23, after the ice-fishing re-run)

Two things cost a full session each. Read this before QAing World 2 again.

**Force the ice-fishing event with an attribute, not `ForceStart`.** `IceFishingEvent.Init()` listens for
`ReplicatedStorage:SetAttribute("IceFishingForce", <seconds>)` and starts a freeze of that length
(clamped to `Cfg.FREEZE_SECONDS`, cleared as it fires, so it is single-use). Use that:

```lua
game:GetService("ReplicatedStorage"):SetAttribute("IceFishingForce", 240)
```

Calling `IceFishingEvent.ForceStart()` from the MCP bridge or the command bar does nothing visible,
because each of those gets its **own `require` cache** — you get a second, inert copy of the module
while the live server keeps running the one it loaded. An attribute is an Instance, so it crosses that
boundary. The event is NOT un-forceable; the 2026-09-21 note saying otherwise was wrong.

**`RodService.IsEquipped()` lies to the bridge.** Same require-cache split: called from `execute_luau`
it reads an empty `equipped` table and returns `false` even while the rod is visibly welded to the
character. Don't chase it as a bug — check `character:FindFirstChild("FishingRod")` instead. The same
caution applies to any module that keeps per-player state in a table rather than on an Instance.

**Screenshots must be taken in Play, not Edit.** The L2 grade (`TundraGrade`) and the atmosphere are
applied at runtime by client scripts, so Edit renders the tundra flat and blue and misrepresents the
pass. Two Play-mode gotchas: `CameraWatchdog` reverts a Scriptable camera after ~6 s, so park the
character (anchor the HumanoidRootPart) and shoot through the normal camera instead; and the
`DayNightCycle` plus any live weather event will change the light between shots — pin `ClockTime` and
hold the clear-weather Lighting values on `Heartbeat` for the duration of the shoot.

**Never run `RebuildTerrain()` on the live place — only individual steps.** It opens with
`ClearAll()`, and it times out at ~60 s. A second call does not resume: it starts again from
`ClearAll()`, so a timeout can wipe everything the first call finished.

**Aim arrival shots down `TUNDRA_LOOK`, not at the town.** The portal faces `(0.386, 0, 0.922)` —
north down the CellarPass tunnel. Aiming "toward the town" (west) photographs a tunnel wall.

**The Warmhouse encloses the hub.** It is a 222×133 lodge (x −8111…−7889, z −8384…−8251) with its
roof at y2040. Any hub sample inside that box is roof, not ground — a "flat empty plaza" there is the
roof snow. The real hub, the Warming Circle, is north of the door.

**Raycasts that start inside solid terrain return nothing.** Mapping the arrival tunnel from y2048
reported "void" through solid rock. Start just below the ceiling you expect, or you will read rock as
an open shaft.

**Pasting code into Studio through a long-bracket string:** Lua already drops the newline straight
after `[==[`, so do not also trim the first character — that ate a `-` and turned a comment into a
syntax error. Checksum Studio's `Source` against the repo file before running anything; that is how
it was caught.

**Dock-throw tests need a claimed plot.** `ThrowHandler` refuses with "Claim a base first!" when the
profile owns none. Claims don't persist between Play sessions, and a CFrame teleport onto the pad
doesn't fire `Touched` — walk onto `Platform` with `Humanoid:MoveTo`.

**`Humanoid:MoveTo` gives up after 8 s.** A long walk that "stops short" is usually the timeout, not
a blockage. Walk in short legs and read `MoveToFinished`.

**Never place terrain on a raycast that can hit your own earlier terrain.** A re-run of
`BuildArrivalApproach` raycast onto the rock the previous run had left and stacked new lumps on top
(to y2052, with the lit posts floating 15 studs up). Every ITEM 8 step places on a MEASURED floor
constant instead: arrival shelf 2030, town apron 2002, drill shelf 2022, lookout gallery 2048. Run a
new terrain step twice and compare heights before calling it done.

**Re-probe terrain in a new call.** A raycast in the same `execute_luau` call right after a terrain
write reads the OLD collision. Measure in a separate call.

**A blurry Play capture is the HUD panel, not the lens.** An open panel (the Daily panel opens on
join) adds `Lighting.HUDPanelBlur`. Hide `PlayerGui.GameHUD…PanelHost`, then destroy the blur and
disable the ScreenGuis. Don't force the Atmosphere for a shot: the real Tundra haze (~1.05–1.09) is
what players see. Check `ReplicatedStorage:GetAttribute("WeatherName") == "Clear"` first.

**Camera for Play shots:** re-assert a Scriptable camera every frame with
`RunService:BindToRenderStep(..., Camera + 1, ...)` at `head − look × 12.5 + (0, 3.4, 0)` (the default
camera's offset). That outlasts `CameraWatchdog`, which only reverts a camera set once.

**Neon behind Glass still reads as a sticker.** A lit window is SmoothPlastic in a warm colour plus a
`SurfaceLight`, with a Glass pane in front (see `BuildWarmhouseFront`).

**Triggering weather for a test:** `WeatherHandler.ApplyByName("Thunderstorm", secs)` from the
bridge reaches real clients, because it fires the shared `WeatherState` remote. Play-mode only.

## 13. Identity pass (2026-09-23, ITEM 6)

Terrain is used wherever the thing is natural (cliff tops, rock, spoil, shallows); Parts only for
man-made objects and anything floating on the water. Parts in `FrozenTundra`: **2,664 → 2,739**
(cap 4,500).

| Chunk | What | Parts |
|---|---|---|
| A | `BuildSkyline`: the wall tops varied ±10–25, 18 notches, 12 crags. East top went from 74/74 samples at exactly y2110 to 2/74 | 0 |
| B | `BuildWarmhouseHero`: darker roof, inset snow, fascia + ridge, chimneys 14→30 with smoke, lit east wall | 17 |
| C | `BuildArrivalApproach`: 3 new tunnel lamps, 3 relit (1.0 / 20 / 255,190,120), 7 terrain rock lumps, 2 lit posts | 7 |
| D | `BuildLakeShore`: near-shore bed raised 1978→~1996 with ramps, 13 glacier rim lumps, 10 disc floes, 4 terrain shore rocks | 23 |
| E | `BuildDockApproach` (C3: sled, drying rack, lamp, 3 terrain boulders) and `BuildDigCamp` (C4: 6 terrain spoil heaps, winch, crates, 2 lamps) | 28 |

**Lake fingerprint around chunk D** (box x −8200…−7800, y 1980…2012, z −7820…−6860, 4-stud voxels;
checksum = Σ occupancy × (i + 3j + 7k); not the same box as the older 79,394 figure):

| | before | after |
|---|---|---|
| water voxels | 76,368 | 75,337 |
| weighted checksum | 68,402,202.8 | 68,237,658.1 |
| water surface | 2000.00 | 2000.00 |
| far north edge (x −8000) | z −6880 | z −6880 |
| dock-to-far-shore | 924.0 | 924.0 |

The count falls because raising the bed and the ice rim displace water; the outline, surface and
throw reach are unchanged. It was still 75,337 after chunk E.

Backups: `ServerStorage._BACKUP_BEAST_identity_pre` — TerrainRegions `EastWall_S/N`,
`WestWall_S/M/N`, `SouthWall`, `LakeShore`, `LakeShore_Out`, `DrillShelf`, plus clones of
`Greybox.Warmhouse` and `Art.Warmhouse`.

## 14. Visual pass (2026-09-24, ITEM 8)

Parts in `FrozenTundra`: **2,739 → 2,802** (budget ~2,900). `PlayerBases.Plot7–12`: 630 → 662.
Lake water is still exactly 75,337 voxels, surface 2000.00.

| Step | What | Parts |
|---|---|---|
| 1 | Tunnel: CellarPass bore reskinned Glacier→Slate with a region-limited `ReplaceMaterial` (no `SetMaterialColor`); every lamp is a Glass body with a small Neon core; tunnel pools 0.85 / r14; 6 ice-blue Glass crystal meshes. Also fixed the re-run stacking bug (§12) | +14 |
| 2 | Hard edges: 30 `CampSpire` prisms → 62 `crystal`-mesh clusters (rebuilt from recorded positions); 26 floating rubble cubes → 6 terrain piles; 3 dock snow tiles → 6 terrain drifts; 96 unclaimed pads → frosted Slate (claimed pads keep `PlayerDataManager`'s repaint) | −29 (camps +32) |
| 3 | Camps: per-camp tent colour, crystal count (5/3/4 east, 4/5/3 west) and hearth angle; 16 terrain drift ridges along the spurs. The functional `Campfire` and `CampStand` are NOT moved (collect ring r5.6 keys off them); the hearth turn is stored in the `HearthYaw` attribute so a re-run turns 0 parts | 0 |
| 4 | Ice field: 2 fishing huts with lit windows on the banks (`BuildIceCamp`). In `IceFishingEvent.buildHole`, each hole also gets a `TipUpPole` with an orange `TipUpFlag` and a two-block snow `Windbreak`: +40 parts and no lights, during a freeze only, all cleaned up on thaw | +24 |
| 5 | Warmhouse front (`BuildWarmhouseFront`): a 56-wide cross gable over the door (barge boards, ridge cap, diamond window), two canted Glass bays flanking the porch, a crest cap on the lean-to's top edge, the four warm panes turned from Neon to SmoothPlastic + SurfaceLight, Glass on the outer two. It removes WarmhouseHero's hidden `RidgeBeam` and the flat frames on the two bay windows. Door, porch, name board, lamps and signpost are untouched | +54 |

Backups: `ServerStorage._BACKUP_BEAST_item8_pre` — TerrainRegions `Tunnel`, `CampsEast`,
`CampsWest`, `Watchtower`, `DockDeck`; clones of `Greybox.CellarPass`, `Art.ArrivalApproach`,
`Ruins.BrokenWatchtower`, `SkipArea.Dock`, `Greybox.Warmhouse`, `Art.Warmhouse`,
`Art.WarmhouseHero`, and `Plot7–12` `TundraCamp` + `Pads`; the pre-change `IceFishingEvent` source
as a StringValue.

## 15. Dusk and night (2026-09-24, ITEM 9)

Shot clocks: dusk = 17:48 (the Sunny Day sky is already dark by 18:00), night = 21:30.

| Area | Change | Where |
|---|---|---|
| Tunnel | The 10 bore lamps went warm 255,190,120 → cool 206,212,222, with Neon cores dimmed to 150,162,180. A bright cool core blew out white. 6 new `CrystalFill` PointLights (180,196,218, 0.3 / r14) sit inside the existing wall crystals. The Slate (blue-grey 110,122,128) now reads as rock, not tan. No material change, 0 parts | `BuildArrivalApproach` |
| Dusk/night grade | Two curves on `Lighting.Daylight`: *blue* (0 at daylight ≥ 0.62, 1 at ≤ 0.30) and *night* (1 at 0). Tint 238,244,255 → 208,222,255 → 198,214,255. Contrast 0.12 → 0.17. Saturation −0.05 → +0.04 at the blue hour. Extra exposure cut −0.22 at full night. Night haze mix 0.25 → 0, so Tundra Haze at night = 0.30, the valley base (MASTER's cap) | `TundraAtmosphere` |
| Hole lanterns | Existing light 1.1 / r15 → 1.8 / r26. After the night grade the pool vanished into the ice and a hole read only as a flag; now each hole sits in a warm pool | `IceFishingEvent.buildHole` |
| Night push (9b) | Night tint 198,214,255 → 156,180,248, night exposure cut −0.22 → −0.50 (Tundra total at 21:30: −0.08 → −0.36), and the −0.03 night saturation dip removed (it greyed the warm windows). Tuned by shot so the snow and the ice sheet go moonlight blue instead of near-daytime white; the dock, the Warmhouse door and a hole at ~55 studs stay findable, so no light was changed. Dusk (17:48, Daylight 0.44) and day are unaffected: the night curve starts below Daylight 0.30 | `TundraAtmosphere` |

Scope: `TundraAtmosphere` writes only the private `TundraGrade`, `ExposureCompensation` and (while Clear)
`Atmosphere`, all faded by the Tundra region blend. Checked in the valley at 21:30: TundraGrade off,
exposure 0.14 (base), Atmosphere 0.22 / 0.30 (base). Brightness, Ambient, OutdoorAmbient, ClockTime,
Lighting.ColorCorrection, Bloom, WeatherCC, HUDPanelBlur and NightLights are not touched.

NightLights registers every light's brightness when it first sees it, as its base (outdoor names → 45 % at noon,
others → 55 %). So a light's night value is what the builder sets, and a Play-mode preview has to
*replace* the light, not set Brightness on it.

Backups: `ServerStorage._BACKUP_BEAST_item9_pre` holds the TundraAtmosphere, IceFishingEvent and World2Art sources,
clones of `Greybox.CellarPass`, `Art.ArrivalApproach` and `SkipArea.Dock`, and copies of `TundraGrade`
and `Atmosphere`.

## 16. Sign-off tour (2026-09-24, ITEM 10)

The new-player route was shot at noon, dusk (17:48) and night (21:30) at twelve stops:
- arrival (the spawn view), the Cellar Pass looking toward the portal, the shelf / Frostgate
- the hub, the Warmhouse front and inside, a camp on each side of the Avenue
- the dock, the ice field mid-freeze, Elder's Dig and the High Ledge

The hub and the ice field were then shot in every weather state (Clear plus the eight events).
All shots were taken in Play with the rig in §12. A 14 px marker in the viewport corner tells an
external PrintWindow watcher which shot is framed and settled, so a whole set runs unattended, and
the client's Lighting, TundraGrade, WeatherCC and Atmosphere values are logged per frame.

**Route walk.** `Humanoid:MoveTo` in legs of 40 studs or less. The loop runs arrival → Frostgate
→ descent → Circle → Warmhouse (in and out) → Avenue → Plot 7 and Plot 11 terraces → dock →
promenade → east shore → Dig ramp → Tung's porch → High Ledge → ledge ramp → Frostgate east →
arrival. Result: 34 legs, 0 blocks, 284 s. The only fault was the shelf (below).

| Fix | What was wrong | Change | Where |
|---|---|---|---|
| Frostgate path | Two of the ITEM 6 shelf lumps and one drift sat ON the painted path from the tunnel mouth to the descent. They were laid either side of `AP_LOOK`, but the walked line runs east of it. The route climbed an 8.5-stud rock pile, and the walk peaked at y 2041.5 | Lumps 4 and 6 and the (58, 14) drift are skipped; their random draws are kept, so every other lump rebuilds identically. New step 5 empties the terrain from 2028 up along the path (7-stud half-width) and over their footprints, then repaints the 2024 cell: Sandstone on the path, Snow beside it. The path is now 2030.0 Sandstone end to end. 5 lumps remain | `BuildArrivalApproach` |
| Snow indoors | The camera-following snow hosts ride 50–82 studs above the player, and particles don't collide, so snow fell through the Warmhouse roof | One upward ray every 0.25 s. Under a roof, the fall and the ground drift switch off and the flakes in the air are cleared | `TundraWeatherFX` |
| Dig lamps | The two camp lamps were solid Neon blocks, glaring right beside the camera even at noon | Glass body with a small Neon core, like the shelf and tunnel lamps (+2 parts) | `BuildDigCamp` |
| Floating icicles | Tung's stash hut: five icicles hung in the air, 0.5 studs out from the eave | After `placeStash`, each icicle is walked in under the eave and hung from it (upward ray against Roof/RoofSnow) | `BuildDig` |
| Floating fish | The four drying fish hung 0.2–0.5 studs under the rack pole with nothing holding them | A short `FishLine` for each fish (+4 parts) | `BuildDockApproach` |
| Weather × grade | `TundraGrade` took its time of day from the server's `Daylight`, which follows the SERVER clock (frozen during an event), while every weather kit sets its own client `ClockTime`. Night kits that started by day got the −0.40 white-out cut. Day kits that started at night got the night tint (156,180,248) and −0.50 on top of their own blue: navy/violet, the double blue. The tint also stacked on the blue kits by day | The phase is read from the client's own clock, on DayNightCycle's curve (dawn 5, dusk 20). While an event runs, the tint, contrast, saturation and night cut ease out over `FADE`, leaving `WeatherCC` the colour; only the daylight snow cut stays. Clear weather is unchanged (checked: Clear night before and after are the same frame) | `TundraAtmosphere` |

All builder steps were re-run twice: parts identical, voxels identical. The lake is still exactly
75,337 water voxels. A floating-prop scan checks every visible part in FrozenTundra and Plots
7–12 (3,280): AABB contact with another part, or terrain or water within the cell below. It
found 0 floating parts after the fixes (5 before). FrozenTundra went from 2,802 to 2,808 parts.

**Measured, not built (listed for MASTER):**
- `TundraAtmosphere` overwrites `Lighting.ExposureCompensation` every frame, inside the Tundra and
  OUTSIDE it too (outside it pins the join-time 0.14). So no weather kit's exposure has ever applied,
  in the valley either. Golden Hour in the valley reads 0.140 (the kit wants 0.30); Blizzard's +0.24,
  Shooting Star's +0.22 and Thunderstorm's −0.10 are all lost. Fixing it changes World 1's weather
  looks.
- The aurora ribbons (z 1250–2100) and the Blood Moon (0, 1500, 2200) are built at valley
  coordinates. In the Tundra those two events have no centrepiece. `WeatherClient` is not BEAST's.
- Blizzard in the Tundra is capped by `EVENT_CAP` (Haze 1.2): a sunny blue sky with big flakes, not
  a white-out. Aurora at +0.5 saturation on white snow reads royal blue.
- `NightLights` scales lamps by the server's `Daylight`, so during a night kit started by day the
  lamps stay at their daytime level.

**Gotchas learned:**
- `require` in an Edit-mode `execute_luau` is cached for the session, and `UpdateSourceAsync` does
  not reset it. Re-running a builder after a source push silently runs the OLD code. Require a fresh
  clone (`art:Clone()`, parented beside it) and destroy it afterwards.
- Terrain floors on this shelf are a full cell under an EMPTY cell, which renders a surface 2 studs
  above the cell boundary (2030 from a full 2024–2028 cell). A half-full cell above rides 2 studs
  higher.
- PowerShell variables are case-insensitive (`$Names`/`$names`, `$H`/`$h` are one variable), and
  Python on Windows writes CRLF in text mode. Both broke the shot pipeline once.

Backups: `ServerStorage._BACKUP_BEAST_item10_pre` holds:
- the `TundraWeatherFX`, `TundraAtmosphere` and World2Art sources
- clones of `Art.DigCamp`, `Art.EldersDig`, `Art.DockApproach` and `Art.ArrivalApproach`
- TerrainRegion `Terrain_Shelf`, restored with `Terrain:PasteRegion(tr, Vector3int16.new(-2060, 505, -2066), true)`
