# Throw pacing + reward reveal + audio pass — report (2026-09-21)

Branch `claude/skip-rocks-reward-pacing-27e78a`. Presentation, pacing and sound only:
no reward odds, distance thresholds, grant rules, inventory, cash/gem or cut routing
changes. Live in Studio (place 78783087742939) since 2026-09-21; every touched script is
backed up in `ServerStorage.AuditBackups.PreRewardPacing_2026_09_21`. Mirrors are byte-exact
in `game-src/place-full/` (see the README entry there for the per-file list).

## 1. Exact cause of the long camera waits

Three things stacked, in `StarterPlayerScripts.ClientMain`'s "Stone tracking camera" block
(now retired) and `ServerScriptService.Modules.ThrowHandler.spawnSkippingStone`:

1. **The server flight was long and uniform.** `totalTime = clamp(0.9 + distance/360, 1.15, 4.2)`
   — 3.4 s at the 900-stud cap — with every hop the same length, so a far throw was a
   long, evenly-paced tour of the lake.
2. **The camera followed all of it, then dwelt.** `camera.CameraType = Scriptable` was
   held for the whole `flightTime`, the RenderStepped chase lerped the camera along the
   full lane, and a hard `task.delay(flightTime + 1.4)` kept it parked at the landing
   point for another 1.4 s. The throw bar (`unlockThrow`) was gated on that same timer.
   Worst case ≈ 4.8 s of forced spectating per throw, on every throw past 60 studs.
3. **The reveal did not wait for the camera.** `ThrowResult` lands at the landing, so the
   pop (`CatchPop`) opened while the camera was still out over the water, `CatchFX`'s
   burst fired around a character that was off-screen, and 1.4 s later
   `camera.CameraType = prevType` snapped the view home mid-pop — the "abrupt result →
   brainrot appears → hard snap" sequence in the recording. Mythic+ cuts then took the
   camera from that parked pose (after a one-frame snap home via the
   `CinematicCameraInbound` handshake) and Mythic's 0.2 s handoff beat ended the run
   before its own 0.8 s camera blend finished, so the cut's return was also a snap.

## 2. New camera / flight presentation

- `ReplicatedStorage.Modules.SkipArc` (new) is the one arc clock for server flight, client
  ghost, skip counter and camera: `totalTime = clamp(0.9 + d/500, 1.15, 2.7)`; hop k
  lasts `HopRatio(d)` × hop k−1, uniform up to 200 studs and ramping to 0.86 at 900, so
  the opening skips stay readable and the distant travel accelerates away. Distance,
  rarity, the grant at landing and every splash **position** are unchanged.
- `ReplicatedStorage.Modules.ThrowCam` (new, on `CatchCinematic.CameraRig`):
  chase behind the stone for `min(1.6 s desktop / 1.15 s touch, 62 % of the flight)`,
  then **glide** (forward speed decays, eye stays on the stone as it accelerates off),
  0.30 s on the landing splash, then an eased blend home (0.55–0.80 s by distance).
  Publishes `ThrowCamBusy`; `RevealRouter` starts the pop only once it clears.
- Measured (desktop, 60 fps, real throws): 72 studs → 1.98 s Scriptable total; 317 studs →
  2.36 s; 899 studs → 3.55 s (2.7 flight + 0.3 + 0.55), pop opening at +0.03 s after the
  camera was home. Old worst case for the same 899-stud throw: 4.8 s + a snap.
- A cut inbound (Mythic+) **claims** the throw camera in place (`CameraRig.offerHandoff` /
  any-live-rig adoption in `takeover()`): no snap home, the cut flies from the parked
  pose, and the cut's restore target is the player's real pre-throw camera.

## 3. Quick Throw

Settings › Gameplay › "Quick Throw (no rock camera)" → `SettingsService` whitelist key
`quickThrow` → player attribute `QuickThrow`, read by `ThrowCam` on every throw: no takeover
at all, the reward pop opens the moment the server confirms the catch. Cuts still play.

## 4. Trail / beam

`RockDesign` `Wake` Trail: lifetime `0.11 × kit.Trail` (was `0.55×` → 150–300 stud ribbon),
width ±0.16 of the core (was ±0.42), `FaceCamera`, transparency 0.45→0.75→1, width thinning
to zero. `ThrowHandler` further clamps the lifetime to ≈40 studs of ribbon by the throw's
average speed. The thrower's hidden server stone now has its Trail / motes / light disabled
locally — it was drawing a second, 20 Hz-stepped wake over the ghost's smooth one.

## 5–11. Reward flow by rarity

| tier | path | length | what changed |
|---|---|---|---|
| Common | pop | 0.90 s (+0.16 fade) | opens after the camera is home; tiny halo (3 soft layers, no disc); name, then rarity 0.09 s later |
| Uncommon | pop | 1.00 s | as Common, richer cue |
| Rare | pop | 1.10 s | +1.5° FOV emphasis, music to 0.88, shimmer layer joins the cue |
| Epic | pop | 1.35 s | +2.5° FOV, dim 0.08, music 0.72, slam text |
| Legendary | pop | 1.55 s (+0.14 s anticipation glow) | +3.5° FOV, dim 0.14, music 0.45 (short), impact + shimmer under the sting, orbiting dots |
| Mythic | cut | 2.12 s | rebuilt (§12): energy point → upward pulse → creature framed by sparkles → MYTHIC → 0.4 s handoff |
| Secret | cut | 3.0 s | music to 0.03 in `nothing`, hard silence under the fake-out, signature ice-shatter at launch |
| God | cut | 5.0 s | music fully yields (silence now actually mutes), world back as a whisper under the choir, 0.45 s handoff |
| Huge / Massive / Massive God | cut | 4.8 / 10.6 / 12 s | shared fixes only: spout instead of the tube, particle rings, HUD back under the camera's return, music duck 0.35 / 0 |

Order in every path: result → camera settles → (anticipation) → creature → name → rarity →
accent → return. Golden/Diamond are a material (`MutationFX`) + a chip line ("GOLDEN ×2") in
the pop and the mutation prefix in a cut's name text; they never change the path.

## 12. Mythic before / after

Before: bonk → ripple → `WaterFX:erupt` (a Glass **column** 2.6× the creature's height,
0.55× its width, the creature rising inside it) + a filled red Neon **disc** 2.2× its width
→ the model simply at full rise → banner → 0.2 s handoff (camera blend cut short = snap).

After (`Cuts/Mythic.lua`): bonk 0–0.22 (music to 0.25, cool tint, camera settles from the
parked chase pose) → gather 0.22–0.62 (`WaterFX:energyPoint`: sparkles converging on a point
at the surface, a light growing, a glow under the water, the bass) → burst 0.62–0.92
(`pulseUp`: a fountain of sparks and foam straight up, a particle ring across the water, the
creature rises through it with an ease-out, one short flash, shake 0.7) → settle → banner
1.02–1.72 (MYTHIC + name, red rim, orbiting sparkles framing it — `AuraFX` with no disc) →
handoff 1.72–2.12 (HUD back under the camera's glide, streak into the bag, blend fits the
beat). Nothing covers the creature at any point.

## 6–7. Secret / God audio

- Secret: `nothing` ducks ambience to 0.05 and music to 0.03; `fakeout` is a hard
  `silence()` (the Twinkling placeholder that used to play there is now an intentional
  rest, slot `secretHum = ""`); `launch` plays the Secret signature (`kit:catchSecret`, the
  ear-picked ice-shatter) over the water hit and keeps the music at 0.15 through the
  banner; the handoff ramps it back. `RareCatchClient` no longer plays the Secret/God
  sting at grant time for your own catch (it spoiled the fake-out by a full second).
- God: `bonk` registers the music duck at 0 and then hard-silences the world (the old
  `silence()` never snapshotted, so it muted nothing); `rumble` 0.3 s; the beam; `choir`
  brings the ambience back to 0.25 with the music still gone; the arrival ring is a particle
  ring; `linger` shortened so the handoff has 0.45 s for the camera to come home.

## 17. Music ducking

`ReplicatedStorage.Modules.MusicDuck` (new): named requests, smoothstep ramps, minimum wins,
`clear()` ramps back and forgets. `MusicClient` is the ONLY writer of the track's Volume
(`VOLUME × slider × fade envelope × MusicDuck.level()`, 20 Hz while a track plays); the
`BaseVolume` attribute path in `SoundKit.SetCategoryVolume` no longer reaches the track.
`AudioBus` routes the music through it (`duckAmbient(level, secs, musicLevel?)`,
`silence`/`unsilence`, `restoreAmbient`, and a 0.8 s ramp on `cleanup`). Ladder:
Common/Uncommon none, Rare 0.88, Epic 0.72, Legendary 0.45, Mythic 0.25, Huge/Massive 0.35,
Secret 0.03, God/Massive God 0 (`CatchPop` presets + `Config.MUSIC_DUCK`).

## 20. Throw / water sound

`ThrowHandler.playSplashSound`: taps decay along the sequence (0.32 → ~0.19), read their
own hop speed (fast late hops are lighter/brighter), ±6 % pitch and ±8 % level jitter; the
landing is weighted by distance (0.52–0.74, pitched 0.99 → 0.90); roll-off 460 studs for
skips (the far skips are heard as far) and 900 for the landing. `ClientMain`: the release
whoosh is pitched 0.92–1.08 by power with a hair of random variation.

## 21. HUD / popup budget

Pops never hide the HUD. Cuts hide it (Takeover) and now bring it back at the START of the
handoff, under the camera's motion (`run.restoreHud`; the trove still guarantees it).
Priority during a reveal: cut > pop > everything else — `PityThrowClient` retracts when a
pop or cut starts, `RareCatchClient` holds your own banner until camera/cut/pop are done
(bounded 20 s) and skips its sting when a cut voices the catch, the tutorial card
(onboarding lane) gates on `ThrowCamBusy` / `RevealPopActive`.

## 22–23. Camera return and failure safety

Return is always a blend (`CameraRig:returnToPlayer`, HRP-relative). `ThrowCam`: kill
switches on `CharacterAdded` / `Humanoid.Died` (hard restore), a wall-clock backstop past
the longest flight, `ThrowCamBusy` cleared on every path, `CameraWatchdog` behind it.
`Takeover`'s watchdogs, cancel and kill paths are unchanged; the HUD-restore step is
idempotent. `CameraRig` restores FOV only if it punched it, and adopts any live rig at
takeover so two rigs can never both own the camera.

## 10. Scripts changed

See `game-src/README.md` "Throw pacing + reward reveal + audio pass" for the per-file list
(27 scripts: 3 new modules, 24 edited).

## 13. Test results

All on the live place with the pushed scripts, desktop client, Studio "Average Laptop
1366x768" emulation, fresh scratch profile row (`ProfileKeySuffix = "_rp"`) with a VoidHeart
equipped for the 900-stud throws; every test grant reverted afterwards
(`__RevealServerRunner.revertUids`) and the rock removed. No script errors or warnings in
any run (LogService watched throughout).

**Real throws (timeline from the client, seconds from the throw; `Scriptable` = camera away from the player)**

| throw | flight | camera away | pop / cut starts | notes |
|---|---|---|---|---|
| short, 72 studs, Common | 1.15 s | 1.98 s (0.45 → 2.43) | pop at 2.50, 1.03 s long | chase + 0.3 dwell + 0.55 blend |
| medium, 317 studs, Uncommon | 1.53 s | 2.36 s | pop at 7.40 (+0.07 after home) | |
| long, 899 studs, Legendary | 2.70 s | 3.55 s (chase to ~390 studs by 1.6 s, glide to ~570, splash, blend) | pop at +0.03 after home; FOV 70→66→70 over 0.5 s; 1.84 s long | old code: 4.8 s + snap |
| long, 900, **Mythic** (forced) | 2.70 s | throw cam claimed by the cut at the bonk (no snap home, camera flew from 550 → 915) | cut 3.15 → 5.22 (2.07 s), FOV 70→62→70, `RevealActive` 3.15 → 5.26 | real Bridge path |
| long, 900, **Legendary + Huge** (forced) | 2.70 s | claimed by the Huge cut at the bonk | cut 3.15 → 7.80 (4.65 s), FOV punch 95→70 at emergence, blend home 7.10→7.80 | |
| long, 900, **Quick Throw** (Uncommon **Diamond**) | 2.70 s | **none** (camera never left Custom) | pop at ThrowResult (12.93 → 12.95), 1.15 s, mutation chip | throw bar back to HOLD TO SKIP |

Common pops on a Pebble profile (22-stud throws, no camera): 1.05 s each, one Golden Common
showed the chip; music duck stayed 1.0 for Commons (observed on the onboarding lane's run of
the pushed code).

**Structural harness** (`CatchCinematic.Harness`, `CinematicTimescale = 4`, asserts stage
empty / PlayerGui Enabled flags identical / camera type+subject+FOV restored / Lighting
untouched / `RevealActive` cleared after every exit path):

- `checkBeats`: Mythic 2.12 s, Secret 3 s, God 5 s, Huge 4.8 s, Massive 10.6 s, Massive God 12 s — all contiguous, all handlers present.
- `matrix` normal / spectator / skip / cancel: **24/24 OK** across the six cuts (Secret run with Mutation = Golden, God with Diamond).
- `routingMatrix`: OK (24 cells + 2 edges; mutation never changes the path).

**Pops**: `popMatrix` (Common..Legendary × plain / Golden / Diamond = 15 pops in 21.1 s):
OK — no PlayerGui growth, camera type / subject / FOV and Lighting identical before and after.

**iPhone 16 device sim (733x371, `Platform.IsPhone`/`IsTouch` true)**: real 900-stud throw →
chase 1.15 s (to ~280 studs), glide to ~390, landing at 2.93, blend home 0.71 s
(distance-scaled), camera away 3.71 s total, Legendary pop opened 0.03 s after the camera
was home (1.83 s long), no errors. Geometry audit of the pop against every enabled
ScreenGui found two collisions in the first layout — the luck chip (top-centre on phones,
true y 130–174) under the creature, and the AUTO SKIP button (257–291) under a
serial+odds stamp — fixed and re-pushed: on phones the pop is 0.28 of the viewport
height from y = 0.10 (37–141), serial + odds share one line (stamp ends ≈ 245), and
`LuckHUDClient` hides its chip while `RevealPopActive` is set (same yield it already does
for an open panel). Rarity text never clips (`TextFits` true on every stamp line; the long
name label reads `TextFits=false` only as the known AutomaticSize artifact — it is
376 px wide inside a 376 px stamp).

**Not run**: the Massive real-throw handoff (the Massive cut passed the harness in all
four modes; the ThrowCam→cut handoff was verified on the real Mythic and Huge throws).
**Visual captures**: PrintWindow returned a stale frame for the whole session (a peer lane
had the Studio window enlarged behind another window), so the by-eye sign-off of the new
Mythic / Legendary look and the trail is still the owner's.

## 14. Audio assets that still need a human

All flagged `TODO` in `CatchCinematic.Config.ASSETS`: `godChoir` (currently the kit choir,
2.58 s — wants a longer angelic "AAAAH"), `beamRise` (Twinkling — wants a rising shimmer),
`godRumble` / `massiveRumble` (APM noise build — wants a sub rumble), `mythicBass` (bling
BIG — wants a real sub hit), `massiveRoar` (choir — wants a creature roar), `secretHum`
(silent — wants a low eerie hum). A purpose-made eight-sting family on one synth patch would
replace `CatchCue`'s shared-spine recipe outright.
