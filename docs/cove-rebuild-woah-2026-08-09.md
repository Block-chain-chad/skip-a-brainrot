# Skipper's Cove — rebuild + woah pass, 2026-08-09

> **The round brief (`skippers-cove-woah-round-brief.md`) assumed the Cove existed. It did not.**
> The Section 0 audit found ZERO BaseParts within 1,000 studs of (8000, y, 8000) — no plaza,
> booths, TradeZone, gazebo, EternalSkip, IndexGate, chests, boards, and not even the old
> pre-cove island. The nearest part in the whole place was 10,047 studs away. The round was
> therefore re-scoped with the user's "go": rebuild the island from the 2026-08-02 spec
> (functional recovery), then apply the woah pass on top.

Place: Skip Rocks For Brainrots (`78783087742939`). **Nothing was saved or published — saving
is the user's call.** Team Create was live during the round; Play sessions were started and
stopped at the machine several times mid-build.

## How the island was lost

`BoothHandler` carries a comment dated 2026-08-09 (another session, same day) that found the
server boot HUNG on `WaitForChild` for the missing booths and patched it to stand down. Its
diagnosis matches the evidence: the 2026-08-02 demolition of the old island made it into a
save, the cove rebuild itself did not. Everything code-side survived; the world did not.
`ServerStorage.PreCove_Backup_2026_08_02` (the OLD island backup) also survived — it is the
seed this rebuild used for the booths, gazebo, TradeZone and HubPortal.

## What exists now

### Functional recovery (new containers, ~520 parts)

- `GameWorld.TradingWorld` (Model, Persistent) — island geometry: seabed r120, plaza r62
  (top y2002.4), Glass water ring r62–88 (top y2002.0, 16 chords, anti-z-fight height jitter),
  outer sand ring r88–118, CoveBarrier r121 (south gap for the causeway), 4 arched bridges
  (r58–92), MARKET arch (pillars z7942), cliff cove N 40–140° with 2 waterfalls, palms,
  tiki torches, SaleBoards (W, placeholder rows), IndexGate ring + `IndexGatePrompt` (E),
  GroupChest / SocialBottle / VIP islet chests with `ClaimSpot` parts, arrival deck
  (r150–192 S) + causeway, and **EternalSkip** (Stone + Ring1–3 + `SkipLoop` restored
  byte-exact from the repo mirror — 26°/s untouched).
- `GameWorld.TradingCenter` (Model, Persistent) — restored from the backup: gazebo recentred,
  `TradeZone` 26³ at (8000, 2007, 8000), `Booths` folder with all 12 booths re-arced to r103,
  35°–145°, facing centre. All BoothIndex / Counter.StandPrompt / Display1–3 / SignBoard
  contracts verified 12/12.
- `GameWorld.Portals.HubPortal` — restored from backup onto the deck's west side
  (7981, 2006, 7830), rotated to face the walkway; `Dest=Hub` attribute intact. TeleportService
  wires it via its existing ChildAdded scan.
- **`TeleportService.TRADE_POS` moved** (8000, 2006, 7905) → **(8000, 2004.6, 7818)** so
  arrivals land on the deck off-island and walk in (brief T2). Script backed up first to
  `ServerStorage.AuditBackups.TeleportService_pre_coverebuild`; mirror resynced byte-exact
  (19,214 bytes; it had drifted to 5,713).

### Woah pass — `GameWorld.TradingWorld.CoveDressing` (327 parts, cap 1,800)

Revert = `CoveDressing:Destroy()` plus deleting the five `Cove*`-named children of
`EternalSkip.Stone` (trail attachments/Trail, PointLight, rumble Sound). The WakePool folder
is created at runtime by the driver and never saved.

- **T1 driver** — ONE server Heartbeat (`CoveDriver`), tag registry (CoveOrbit / CoveSpin /
  CoveBreatheT / CoveBreatheH / CoveBob / CoveFallScroll / CoveAmbience), WAKE_RADIUS 400
  sleep gate, `WorkCount`/`Awake` attributes for probes. Two bugs fixed pre-run: world-Y spin
  (local-Y would tumble axis-rotated cylinders) and wake-ring settle on sleep.
- **T2 arch** — colossal crossed stone tusks straddling the causeway at z7878, apex P+62,
  ball-jointed chunky silhouette, ink shells offset north, neon gloss sliver, gold foot caps.
- **T3 spire** — 6-drum tapering spire rising from the north cliff line at (8000, 8140),
  crown skip-stone d17 at P+148 rotating 6°/s with turquoise neon rim, sky beam to P+900
  breathing on 3.2s + soft halo beam.
- **T4 guardians** — six brainrot statues (Tralalero Tralala, La Vacca Saturno Saturnita,
  Bombardiro Crocodilo, Tung Tung Tung Sahur, Brr Brr Patapim, Ballerina Cappuccina) cloned
  from `ReplicatedStorage.BrainrotModels`, scripts/humanoids/sounds stripped, scaled to
  36–42 studs, placed by bounding box on 8-stud plinths at r138 (angles 0/60/120/180/240/300 —
  none in the south sightline), Highlights breathing 2.4s. Rarity colours assigned as a
  tier ladder 8→3 (BrainrotConfig lookup returned nothing usable) — every colour byte-matches
  a RarityConfig entry (V9 pass).
- **T5 water** — 32 neon underglow chords (shallow `#6ADEE0` inner ring, deep `#2078B2`
  outer), 8 bobbing float-stones. Splash rings on skip contact come from the restored
  SkipLoop; the driver adds a pooled 8-ring wake trail. The rotating caustic plane was CUT
  (no textures allowed; gradient chosen instead — brief allowed this).
- **T6 Eternal Skip** — Trail + PointLight + pitched-down `ambienceLake1` rumble on the
  Stone (3D rolloff 12→110). Four shore ambience anchors + spire wind, all SoundKit ids only,
  volumes stepped by the driver (never tweened). Orbit rate untouched.
- **T7 edge (REWORKED after the visual pass)** — the brief's premise was wrong: the island
  does not float in sky, it sits in a **terrain ocean** (water surface measured y1999.5,
  confirmed by voxel read + raycast). The cloud sea and rim waterfall sheets were built,
  found to be permanently underwater/invisible, and REMOVED (47 parts). Kept: 12 rim bulbs +
  core bulb (they read as the island's hull through the water). Added: a 16-part white foam
  collar at the real waterline (r119, y1999.7). Net T7 = hull + foam; CoveDressing now
  296 parts. The guardians at r138 stand in open sea on their plinths — colossi rising from
  the water, which reads better than the plan.
- **T8 islets** — 7 chunky islets, band r50–92, heights P+64…P+112, orbiting 0.9°/s; two
  carry props (mini palm, gold lantern). Not walkable (CanCollide false).
- **T9 monuments** — IndexGate got colossal coral pillars, crossbar, gloss and an ink halo;
  chests got 2-step podiums + colour beams (Group blue / Social green / VIP gold) with
  PointLights; boards got a coral-slat shade pavilion.

## Probe results

| Probe | Result |
|---|---|
| V1 part budget | **PASS** — 296 ≤ 1,800 after the T7 rework (whole rebuild: ~816 parts incl. TradingCenter + HubPortal) |
| V2 one driver | **PASS by construction** — CoveDriver is the only script under CoveDressing (V3), no other loops. The restored SkipLoop (base island, pre-round convention) keeps its own Heartbeat. |
| V3 no stray scripts / all anchored | **PASS** — 0 / 0 |
| V4 no ThrowZone | **PASS** — 0 anywhere in the new build |
| V5 BoundsGuard containment | **PASS** — every walkable (deck, causeway, bridges) centre+corners inside the Trading region |
| V6 sleep gate | **PASS (live)** — WorkCount delta 0 over 3s with the player in the valley; also observed asleep during the user's own playtest |
| V7 islet drift | **PASS (final run)** — 79.5s window: max radius drift 0.0003 studs, height drift 0.000, angular-rate error 0.014° across all 7 islets |
| V8 wake-ring cleanup | **PASS (final run)** — after leaving: Awake=false, 8/8 pooled rings at Transparency 1, WorkCount delta 0 over 2s |
| V9 rarity colour byte-match | **PASS** — 6/6 |
| V10 revert | **NOT RUN** — destroy+rebuild cycle skipped deliberately: Team Create live and the user was in and out of Play; revert is one Destroy + AuditBackups restore as designed |

**End-to-end arrival was proven live:** touching the valley TradePortal delivered the test
character to exactly (8000, 2004.6, 7818) on the deck; the driver woke within 1.2s and ran
~60 frames/s; 12 booths adopted by BoothHandler with no boot hang.

## Five shots (camera positions — visual pass still owed)

Captures came back once Studio was foregrounded. **Seen and confirmed by the builder:** the
arrival frame (arch + sky beam + islets + guardians + gate + chest beams all composing), the
guardian line (Tralalero over the boards pavilion, underglow reading), and the sea panorama
(Patapim rising from the water, spire + all three chest beams). The user also walked the
island live and approved. Viewpoints for reference:

1. Arrival: cam (8000, 2007.6, 7812) → (8000, 2012, 8000)
2. Under the arch: cam (8000, 2006, 7852) → (8000, 2030, 8000)
3. Plaza centre: cam (8000, 2008, 7990) → (8000, 2006, 8103)
4. Guardian line: cam (7950, 2006, 7920) → (7862, 2030, 8000)
5. The edge: cam (7920, 2008, 7915) → (7885, 1950, 7885)

Composition was verified numerically: from arrival, gazebo/spire/arch all sit on the x=8000
axis; arch apex ~41° elevation, spire crown ~23°, sky beam 24°–70°; spire clears the nearest
booth by 38 studs.

## Deltas from the brief

- The brief's five project docs (`skip-a-brainrot-README/-systems/-ui/-gotchas/-open-decisions.md`)
  do not exist anywhere on the machine; substitutes used: the 2026-08-02 cove spec,
  HANDOFF-2026-08-04, and session memory.
- No `SkippersCove` container exists or ever did — the live contract is `TradingWorld` +
  `TradingCenter`; CoveDressing lives under TradingWorld.
- Booths were MOVED (restored from backup and re-arced) — unavoidable in a rebuild; contracts
  preserved and verified. The fence against touching them presumed they existed.
- TRADE_POS moved to the new deck (T2's "land off-island" requires it).
- Cut for budget/rules: caustic pattern plane (kept gradient), booth-arc promenade ring
  (outer ring already reads as one), causeway rope-rail dressing. Add back first: promenade.

## Open items

1. **User: look at it** — every acceptance that needs eyes. Then **save** (owner's call).
2. V7 60s drift window + V8 runtime cleanup probe — one quiet 2-minute Play session.
3. V10 revert drill if wanted before saving.
4. `BoothHandler`'s 2026-08-09 comment block about the missing stands is now stale — it can be
   updated to note the stands are back (left untouched this round: not our file, not required
   for function).
5. Chest claim wiring, board feeds, IndexGate prompt action — same next-pass list as the
   2026-08-02 spec; owner still blocks Group/VIP ids.
