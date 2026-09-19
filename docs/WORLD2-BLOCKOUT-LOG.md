# World 2 — Greybox Blockout Log

**For:** Balkan (walk-through and sign-off) · **By:** BEAST · **Branch:** `world2-overhaul` · **Date:** 2026-09-19
**Status:** the greybox is **built in Studio**, in the shared Team Create place (place `78783087742939`). It is **not published**. Work stopped before art and polish, as instructed.
**Plan:** [`WORLD2-MASTERPLAN.md`](WORLD2-MASTERPLAN.md) (updated with the as-built notes) · **Quest audit:** [`WORLD2-QUEST-AUDIT.md`](WORLD2-QUEST-AUDIT.md)

Compass as in the masterplan: **N = +Z** (up-lake), **E = −X**, **W = +X**. Heights are absolute Y; the town/lake datum is **2002**.

---

## 1. Read this first

1. **Publish freeze.** The greybox lives in the Team Create place itself (see §2). **Any publish, by anyone, ships it to players.** Hold publishes until Balkan signs off (tell Duck), or run the rollback (§8) first.
2. **Blocker, as Balkan ruled.** World 2 still has **no respawn or checkpoint**. Dying, resetting or leaving the BoundsGuard box sends a player to the valley spawn. The cliffs and drops stay, but they are not final until that separate fix lands.
3. Four real problems turned up during the review and are **fixed** (§5). Eight things are **open** and need a decision or their own task (§6).

## 2. How it was built

- **In place, not in a staging folder.** The approval did not settle the staging question, so this was announced at the start. The regression checks need the real plots, stalls, NPCs and portals at their new positions, which a staging copy cannot give.
- **Backed up first.**
  - `ServerStorage.World2Backups_2026_09_19` holds `FrozenTundra_Original`, the stall prompt models, the wheel and the leaderboards, both Tundra portals, plots 7–12 and the Tundra terrain region.
  - `ServerStorage.AuditBackups.PreWorld2Blockout_2026_09_19` holds the six scripts as they were before any edit.
- **Nothing deleted.** The replaced geometry is reparented to `World2Backups_2026_09_19.RemovedFromWorkspace`.
- **Generator.** [`game-src/world2/World2Blockout.lua`](../game-src/world2/World2Blockout.lua) is a build-time module, installed at `ServerStorage.World2Blockout.Generator`.
  - The repo file and the Studio module are byte-identical: 42,312 bytes, checksum 820434564.
  - Steps: `Floor → Massifs → Features → Carves → HollowAndFalls → Ramps → Outside`, then `BuildParts` and a one-time `Relocate`.
  - `ClearAll()` wipes everything the generator can write, so `ClearAll` plus the steps rebuilds the terrain from scratch.
  - No game script requires it.
- **Terrain calibration, measured in this place.**
  - A `FillBlock` whose top is at y T walks at **T + 2**, so solids are written to (surface − 2).
  - Wedges come out about a stud high, so a ramp is written from (low − 2) to (high − 1.5).
  - A terrain wedge rises toward its local +Z.
- **Lake protection.**
  - Every write stays **16 studs** outside a copy of `IceFishingConfig.LAKE_PROFILE`. The first pass used 8, and a rebuild nibbled two water cells: the real water overshoots the stepped bands by up to 7 studs at their corners.
  - A voxel fingerprint of the lake (water count plus a weighted checksum) is compared after every write.

## 3. What is in the world now

Coordinates are as built.

| # | District | As built |
|---|---|---|
| 1 | **Cellar Pass + Frostgate** | Diagonal ice tunnel from (−8272, −8352) to (−8236, −8266), floor 2030, walkable about ±7 wide and 14 high. It has three timber ribs with dim lanterns and a timber gate frame at the mouth. **Arrival (−8243, 2034, −8283)**, look (0.386, 0, 0.922), a few steps inside the mouth. The return portal is in a chamber at the tunnel's back, **91 studs behind the arrival**. The Frostgate overlook sits at 2030 (+28). Two ramp legs (≈ 14° and ≈ 12°) descend to the Circle. |
| 2 | **Warming Circle** | A 90-wide disc at (−8000, −8195) with a bonfire and a signpost. The **daily wheel** is at (−7955, −8128) and the **leaderboards** at (−8045, −8128). They face each other across the Avenue's mouth. |
| 3 | **Avenue + Six Camps** | The Avenue runs along x −8000, from z −8150 to the Shore Promenade (z −7832), lined with 8 lanterns. Camps sit on 84 × 80 terraces at **2007** (+5), 3 + 3. Plot7/8/9 are at x −8125 and z −8065/−7975/−7885; Plot12/11/10 are at x −7875 and the same z values. Every PlotBoard faces the Avenue. East and West Roads plus the shore paths connect them. |
| 4 | **Warmhouse** | A market hall cut into the south cliff: x −8112…−7888, z −8385…−8250, floor 2002, 36 high, with a 28 × 20 north door. It holds the **five kept stall models** (shifted 215 studs south with their prompt models), a hearth, 8 lamps and window glow. The Shops button lands at (−8000, 2005, −8305). |
| 5 | **Frozen Lake, dock, `LakeBarrier`, `ThrowZone`** | **Untouched.** The fingerprint is identical after every write: 79,394 water voxels, checksum 3,732,629.8. |
| 6 | **Nico's Point** | A clearing cut into the west ledge (x −7762…−7690, z −7502…−7438, snow floor at 2002) holding the lodge (door facing the lake), a stove chimney, the jetty, a trophy board and a rod rack. **Nico himself is not placed**, because his NPC and quests are separate work. |
| 7 | **The Squeeze + Blue Hollow** | The Squeeze is a 12-wide crack in seven legs, falling 2002 → 1984, with three of Nico's lanterns. Its last leg is a roofed ice arch. The Blue Hollow is at x −7615…−7445, z −7265…−7095, **floor 1982 (−20)**. It has a snow floor, glacier walls, an overhanging glacier face, a frozen waterfall, a frozen pond (r 26), Nico's shanty and five crystals. **The Warm Eye is a marker only** (a dark disc at (−7525, −7165)); the permanent-hole mechanics are approved but not built. |
| 8 | **Elder's Dig** | A shelf at **2022** (x −8424…−8200, z −7704…−7556) plus a **nook** cut into the glacier (x −8420…−8330, z −7764…−7700). There is a ramp up from the east shore path, and the High Ledge runs in from the south. It holds Elder's Station (door toward the lake), a porch, a chimney, the Listening Horn, the Crack and the ancient stone. **The rigid Elder unit:** `DrillSite` (−8345, 2022, −7722) faces **+Z**. Elder Tung stands on his porch at (−8353, 2022, −7692), and `TungCavePrompt` reaches 12. The Depths shaft trigger is at (−8345, 2023, −7734) inside the nook, with refuse point (−8325, 2025, −7710). |
| — | **High Ledge** | 2022 (+20), x −8334…−8245, z −8216…−7696, with a ramp from the Frostgate and a path strip to the Dig. |
| 9 | **Eagle's Crag** | The summit is at **2048** (+46), x −7759…−7636, z −8050…−7960. The route runs West Road → ramp A → west ledge (2022) → ramp B → rope bridge over a crevasse → summit, marked by trail strips on the flat stretches. The Broken Watchtower's base is at 2048 and its top at **2080.6**. **Michael** stands on it at (−7694, 2082.5, −7999). A **timber lookout ramp** (x −7662, 2048 → 2074) climbs the tower's east side to a **gallery at 2074** along its north face, with rails and posts. |
| 10 | **Sundered Peak + Frozen Falls** | Outside the bounds, north. Two halves split at x −8000 rise to 2688, with the Frozen Falls up the split. An ice curtain and an apron run from the lake tip up to 2030. |
| — | **Caldera walls + rim** | South wall 2090/2140, east and west walls 2110, north wall 2150 (notched for the falls). The rim massifs outside the bounds reach 2230–2250 with snow lumps. |

**Stashed** (in `RemovedFromWorkspace`, not deleted): `Ground`, `Decor`, `Icebergs`, `Village`, `Relief`, `Floes`, `ShelfEdge`, `IceSpikes`, `ElderHut`, `Hub` except `Hub.Stalls`, `Ruins.RuinedHamlet` and `Ruins.AbandonedOutpost`.

**Parts:** `FrozenTundra` went from **6,317** to **1,809**: 1,641 kept, plus 168 greybox parts in `FrozenTundra.Greybox`. Each district has a billboard label that shows within 450 studs; the peak's label shows within 6,000.

**Name and path contracts kept:**
- `FrozenTundra.Michel`, `MichelPrompt` and `TungCavePrompt` stay under `FrozenTundra`.
- `FrozenTundra.DrillSite` stays a direct child.
- The `Tundra*Stall` and `Hub.Stalls` models keep their names.
- The `SkipArea` folder and the portals' `PortalTouch` attributes are unchanged.

## 4. Code changed

These are live Studio edits, backed up first. Each one is **mirrored byte-exact** in `game-src/place-full/`.

| Script | Change |
|---|---|
| `ServerScriptService.TeleportService` | `TUNDRA_POS` (−8000, 2006, −7975) → **(−8243, 2034, −8283)**. New `TUNDRA_LOOK` (0.386, 0, 0.922), used by `portalDests.Tundra`. `NAV.Tundra.Shops` now lands inside the Warmhouse. |
| `ServerScriptService.Modules.IceFishingEvent` | `TUNDRA_ARRIVAL` (the thaw fallback drop) moved to the same point. |
| `ServerScriptService.Modules.WheelBoard` | `SITES.DailyWheelTundra` `Pivot`/`LookAt` set to the Avenue mouth, so a layout-version rebuild lands where the wheel now stands. |
| `ServerScriptService.Modules.LeaderboardBoards` | `TUNDRA_AT` / `TUNDRA_LOOKAT` updated the same way. |
| `StarterPlayerScripts.TundraWeatherFX`, `ServerScriptService.SnowFootprints` | The Tundra region box now matches BoundsGuard (z to −6700). |
| `Portals.DepthsPortal.PortalTouch` (attributes) | `RefuseX/Y/Z` = (−8325, 2025, −7710). |

**Not touched:** `BoundsGuard`, `PlayerDataManager`, `SessionLock`, DataStores, place IDs (`WORLD_PLACE_IDS` are still 0), quest logic (`TundraQuest`, `MichelQuest`, configs) and `IceFishingConfig`.

**About the mirror diffs:**
- The repo mirrors of `TeleportService`, `WheelBoard` and `LeaderboardBoards` were **stale**. They predate other people's live edits, so their diffs also bring those earlier live changes into the repo.
- `TundraWeatherFX` and `SnowFootprints` had no mirror before; they are new files.
- `_MANIFEST.txt` is the 2026-08-01 export snapshot and is left as it was.

## 5. Verification, and what the review caught

**Checks**
- **Lake:** the fingerprint was identical after every terrain write, including the last.
- **Bounds:** 19 walkable spots are all inside BoundsGuard's `Tundra` region: arrival, Frostgate, Circle, Avenue, dock, High Ledge, Dig, nook, Nico, Squeeze, Hollow, crag top, rope bridge, west ledge, Warmhouse, portal chamber, falls apron, East Road and West Road.
- **Camps:** the Plot button's landing point on all six camps hits a Platform or a pad.
- **Drill cutscenes:** all five `CaveDrillClient` camera spots have 0 solid voxels and no parts. The shaft (site-local +Z 12) and the `DepthsPortal` trigger coincide.

**Play mode** (the real dev profile; no purchases, claims, quest hand-overs or portal use)

| Test | Result |
|---|---|
| Boot | Every system online. No errors from any changed script. |
| Worlds-tab fast travel → Tundra | Lands at the arrival in **0.63 s**, facing the mouth. No refusal; BoundsGuard stays silent. |
| Arrival → Frostgate overlook | **1.9 s** |
| Arrival → Warming Circle | Walked |
| High Ledge → Elder Tung, and Dig ramp → Elder Tung | **No shaft bounce.** His prompt is 7.7–7.9 studs away (reach 12). |
| Nico's clearing → the Squeeze → Blue Hollow | ≈ 413 studs in **21.0 s**, lands on the floor at 1982 |
| West Road → Eagle's Crag summit | ≈ 249 studs in **12.7 s** |
| Rope bridge → lookout gallery | **5.9 s.** Michael's prompt is **12.4 studs** away (reach 18). |

**Problems the review caught, all fixed and re-verified**

1. **Elder Tung, the Listening Horn and the Crack were buried in the glacier.** The wall behind the High Ledge ran on to z −7700. Fix: the Dig nook, and Elder Tung grounded (he had stood on his old hut's floor, 1.9 studs up).
2. **Walking to Elder Tung bounced players.** The Depths shaft trigger is live before the drill runs, and it sat on the walking line. Players were thrown to the refuse point with "That way is sealed". Fix: the rigid unit (site, NPC and shaft moved together, which the cutscenes require) now faces north. The shaft and every cutscene camera sit in the dead-end nook.
3. **Michael was unreachable.** The ruin is taller than planned (top 2080.6, not ≈ 2074), which put his prompt 31+ studs above the summit against a reach of 18. Fix: the lookout ramp and gallery. The first version ran its foot into the glacier wall, so the character met its underside and could not get on; it was reworked and walked again.
4. **The arrival sat 33 studs in front of the return portal.** The travel curtain does not re-aim the camera, so a player who arrived looking backwards and pressed forward walked straight home. Fix: the arrival moved a few steps from the mouth, with the portal now 91 studs back.

Visual fixes from the same review:
- The tunnel ribs were buried in the rock. They now stand inside the measured ±7 × 14 section.
- The rib lanterns were changed to near-white light, because warm light turned the cyan glacier green.
- The Warmhouse was pitch dark. It now has 8 lamps and a hearth light (SmoothPlastic plus PointLight, no Neon).
- Nico's clearing and the Blue Hollow had basalt floors, and the Hollow had 34-stud basalt walls, so it read as a pit. Both now have snow floors, and the Hollow has glacier walls and arch.
- The crag route had no trail. Stepping off the west ledge next to the route dropped the character to the road, so trail strips now mark it.

## 6. Open issues

These need a decision or their own task.

1. **Respawn/checkpoint (BLOCKER, Balkan).** Covered in §1. The cliffs and drops are not final until it is fixed.
2. **Camera heading after travel.** `TeleportFadeClient` lifts the curtain without turning the camera to the arrival's look direction, so players arrive facing wherever they faced before the hop. This affects every world. The suggested fix is to snap the camera behind the character before the curtain lifts, in shared travel code. That is Balkan's call; this blockout only moved the arrival away from the portal.
3. **`TundraBirds` fly at 2080–2120**, and the new caldera walls (2090–2150) cut through that band, so flocks will fly through cliffs. It is a one-constant fix in the ambience pass: raise the band above about 2160.
4. **`PathfindingService` finds no route through the Squeeze.** Players walk it fine; this only matters if a quest guide ever uses pathfinding.
5. **Studio Play side effect.** Every Play session on the dev profile credited the capped offline camp earnings (≈ 472.79 B each). That profile's cash went from 46.62 T to 47.56 T during testing. This is not caused by the blockout, and nothing was collected or claimed by hand. It is noted so testers know Studio playtests on a real profile inflate cash.
6. **Not built yet** (approved, but separate work): Nico's NPC and his four quests, the Warm Eye's permanent fishing hole (needs an `IceFishingEvent` extension gated by the Quest 3 flag), and the relit-lantern state in the Squeeze.
7. **For the art pass, not now:**
   - the long straight "ruler" walls;
   - the peak reads weakly through the haze from the Circle;
   - the Warmhouse is big and empty for five stalls;
   - the station and lodge are plain boxes;
   - Michael's nest and telescope props;
   - the descent ramps are steeper than the planned 7°;
   - the greybox labels come out.
8. **Full route timings** (masterplan Appendix B) were only measured by segment. Timing the whole routes is part of Balkan's walk-through.

## 7. Suggested walk for Balkan

Worlds tab → **Tundra**. Then:

1. Walk out of the Cellar Pass to the Frostgate. This frame is the reveal.
2. Descend to the Warming Circle and go into the Warmhouse.
3. Walk up the Avenue to the dock.
4. Follow the east shore to Elder's Dig, then take the High Ledge back.
5. Follow the west shore to Nico's Point, then go through the Squeeze to the Blue Hollow.
6. Go back to the West Road, climb Eagle's Crag and take the lookout up to Michael.

The labels name each district as you get close.

## 8. Rollback (one command, Edit mode)

```lua
loadstring(game:GetService("ServerStorage").World2Backups_2026_09_19.Rollback.Source)().Restore()
```

It restores:
- `FrozenTundra` (from `FrozenTundra_Original`), the stall prompt models, the wheel and the leaderboards, both Tundra portals and plots 7–12;
- the Tundra terrain (it clears everything the generator can write, then pastes the saved region back);
- the six scripts, to their pre-blockout sources.

**Check first:** if anyone has edited those scripts since, restoring overwrites their edits, so restore those scripts by hand. Source: [`game-src/world2/World2Rollback.lua`](../game-src/world2/World2Rollback.lua).

## 9. Files

| File | What |
|---|---|
| `game-src/world2/World2Blockout.lua` | the generator (byte-identical to Studio) |
| `game-src/world2/World2Rollback.lua` | the rollback (byte-identical to Studio) |
| `game-src/place-full/ServerScriptService/TeleportService.server.lua`, `…/Modules/IceFishingEvent.lua`, `…/Modules/WheelBoard.lua`, `…/Modules/LeaderboardBoards.lua`, `…/SnowFootprints.server.lua`, `StarterPlayer/StarterPlayerScripts/TundraWeatherFX.client.lua` | mirrors of the six changed scripts, byte-exact with live |
| `docs/WORLD2-BLOCKOUT-LOG.md` | this log |
| `docs/WORLD2-MASTERPLAN.md` | updated: Balkan's decisions, as-built notes |
