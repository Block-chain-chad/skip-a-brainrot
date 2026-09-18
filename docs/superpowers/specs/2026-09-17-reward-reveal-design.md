# Reward Reveal System — design spec

**Date:** 2026-09-17
**Source of creative truth:** `Skip_Rocks_for_Brainrots_Reward_Reveal_Blueprint.txt` v1.0 (the owner's blueprint).
Where this spec and the blueprint describe the same beat, the blueprint wins.
**Supersedes:** the reveal parts of `2026-07-27-catch-reveal-design.md` and
`2026-08-08-massive-catch-cinematic` (the Massive cut is kept, re-paced and re-homed).
**Source of code truth:** Roblox Studio. `game-src/place-full/` is a commit-time mirror.

## 1. Goal

Every confirmed brainrot grant — from a throw or from ice fishing — plays exactly one
reveal, chosen by the grant's rarity and size, following the blueprint's beat sheets
exactly. Common–Legendary are quick screen-space pops. Mythic, Secret, God, Huge, Massive
and Massive God are camera-takeover cuts at the water. Every cut runs on one shared
takeover/restore framework; no cut owns a camera or UI restore path of its own.

Players should recognise what they got from the animation before the text appears.

## 2. Facts this design depends on

- Rarity tiers (`RarityConfig`): Common, Uncommon, Rare, Epic, Legendary, Mythic, Secret,
  God — in that order, each with a colour. God is an independent fixed-chance shot outside
  the curve (Secret Pete).
- Mutations (`MutationConfig`): 12 on one ladder — Golden, Diamond (natural throw drops);
  Wet, Sandy, Electric, Frozen, Aurora, Celestial, Demon, Angel (weather-event only);
  Rainbow, Glitched (fusion only). `Mutations.Color(name)` gives each its colour.
  `MutationFX.apply(model, name)` is the 3D presentation (bespoke per-mutation rewrite of
  2026-08-13): it shifts each part's own colours/materials — which DO render inside a
  `ViewportFrame` — and adds emitters, lights, beams and highlights, which do not.
- Size (`SizeConfig`, Studio-only): an independent axis rolled beside Mutation. Two values
  matter here: Huge and Massive. `Sizes.Label(mutation, size, name)` builds the display
  name ("Golden Massive Tralalero").
- `ThrowHandler` rolls rarity AND size at throw time, before the stone flies, and
  re-checks at landing (limited stock, obtainability). The grant itself happens at landing.
- Exactly one brainrot is granted per throw and per fishing catch. There is no
  simultaneous multi-grant; "multiple rewards" only ever means back-to-back grants.
- Ice fishing (`IceFishingEvent`, Studio-only) grants on its LANDED-IT branch, rolls
  mutation/size with the same formula as a throw, and already fires `RareCatch` on the
  same terms.

## 3. Decisions (owner, 2026-09-17)

1. The blueprint is the spec. Existing code is reused where it already satisfies it and
   changed where it does not.
2. Scope of grant sources: throws and ice fishing. Egg hatching, fusion, offerings and
   trades are out of scope (§14); they never routed through `CatchRevealClient`.
3. Every water cut broadcasts its world FX to players within `SPECTATOR_RADIUS`; camera
   takeover, UI hide and banner are the catcher's only.
4. Throw and cast input are locked for the duration of a takeover cut. Hold-to-skip on
   every cut ≥ 4s (God, Huge, Massive, Massive God). Mythic and Secret are not skippable.
5. Architecture #1: one shared takeover framework, one module per cut, a router that
   picks exactly one path, a pop layer for Common–Legendary.
6. Massive is re-paced to the blueprint (≈10–11s). The meme/hype layer, the second-bonk
   joke and the "MAX BRAINROT" banner are removed. Massive is intimidating, not comedic.
7. Massive God is one cohesive ≈12s cut, not two cuts played back to back. The beam
   originates from the Massive God rig, not from the water.
8. Golden/Diamond — and every other mutation — are visual variants only. No mutation may
   create a reveal path, a cut module, or duplicated cinematic logic. The displayed
   brainrot must show the confirmed mutation during the reveal whenever the existing
   rendering path supports it; where the viewport cannot, the smallest performant
   representation is used (§9).
9. The reveal system is brainrot-agnostic: it receives confirmed grant data and presents
   it. No per-brainrot cinematic implementations.

## 4. Routing rules (locked)

Evaluated top to bottom on the **confirmed** grant; the first match wins.

| condition | path |
|---|---|
| Size == Massive and Rarity == God | Cut `MassiveGod` |
| Size == Massive | Cut `Massive` |
| Size == Huge | Cut `Huge` |
| Rarity == God | Cut `God` |
| Rarity == Secret | Cut `Secret` |
| Rarity == Mythic | Cut `Mythic` |
| otherwise (Common–Legendary) | `Pop(rarity)` |

Mutation never appears in this table. `Config.CUT_FOR(rarity, size)` implements it as a
literal if-chain in that order and is the only place the mapping lives; server and client
`require` the same module (as they already do for `Config.SIZES`).

## 5. Architecture

```
ThrowResult / FishResult ──► RevealRouter (client) ──► exactly one of:
                                │                      ├─ CatchPop.play(grant)          Common…Legendary
                                │                      └─ (adopted by a running Takeover)  Mythic…MassiveGod
                                └─ FIFO queue + RevealActive input lock
CatchCinematic broadcast (server, at flight start / hook-set) ──► CinematicClient ──► Takeover.play(cut, payload, opts)
```

### 5.1 `Takeover` (ReplicatedStorage.Modules.CatchCinematic.Takeover)

The framework, extracted from today's `Sequencer` with behaviour preserved. It owns:

- the per-run state bag and trove (LIFO drain on every exit path);
- the master clock, timescale (`Config.timescale()`, speed/stretch rules unchanged), the
  scaled shallow copies of duration-bearing cfgs;
- the result hold: the clock parks just before the cut's `revealBeat` until
  `Bridge.result(gen)` arrives or the scaled `CANCEL_TIMEOUT` expires;
- the cancel path (luminance dip, `finish(false)`);
- the hold-to-skip state machine (prompt, hold poll, dip, gated on the result), which
  jumps to `cut.skipTo` after calling `cut.onSkip(run)`;
- both watchdogs, the kill switches (Humanoid.Died, CharacterAdded), the pcall'd
  conductor bound at `Camera.Value - 1` with the VM-salted bind name;
- **camera takeover and restore** (`CameraRig`), **HUD hide and restore** (every
  `ScreenGui` except the cinematic's own), the stage folder, `AudioBus`, `PostFX`,
  `ScreenShake`, and the banner/card/skip-prompt UI;
- Bridge plumbing (`markRunning`, `result`, `finish(gen, ok)`);
- beat dispatch: enter/update/exit by beat name from `cut.handlers`.

Only `Takeover` (through `CameraRig`) ever writes `Camera.CameraType`, `Camera.CFrame`
during a cut, `ScreenGui.Enabled`, or `Lighting` (through `PostFX`). A cut that needs an
environment change asks `PostFX` (e.g. `PostFX:tint(color, seconds)`, added for the gold
beam) so the restore stays on the one path.

Public API:

```lua
Takeover.play(cut: Cut, payload, opts: { spectator: boolean?, bridgeGen: number?, onCommit: (() -> ())? }): boolean
Takeover.isActive(): boolean
Takeover.debugState()
```

`play` keeps `Sequencer.play`'s contract: blocking, one active run per client, `false`
means declined (nothing parented), `onCommit` fires synchronously on commit.

### 5.2 Cut modules (ReplicatedStorage.Modules.CatchCinematic.Cuts.<Name>)

One module per cut: `Mythic`, `Secret`, `God`, `Huge`, `Massive`, `MassiveGod`.

```lua
export type Beat = { name: string, t0: number, t1: number }
export type Handlers = { [string]: { enter: ((Run) -> ())?, update: ((Run, number) -> ())?, exit: ((Run) -> ())? } }
export type Cut = {
    name: string,
    beats: { Beat },                 -- cinematic seconds from t=0 (final skip contact / hook-set)
    handlers: Handlers,
    revealBeat: string,              -- the clock parks before this beat until the grant is confirmed
    skippable: boolean,
    skipTo: string?,                 -- beat the skip jumps to (required when skippable)
    onSkip: ((Run) -> ())?,          -- sets the end-state of every skipped beat (never a hard cut)
    build: (Run) -> boolean,         -- constructs this cut's rigs into run.stage; false = decline
    bannerText: string,
    assets: { [string]: string }?,   -- extra AudioBus slots this cut uses (resolved via Config.ASSETS)
}
```

Rules for cut modules:

- Handlers are written against `run` fields and beat-relative progress `p`, or look up
  times by beat name (`beatT0(run, name)`). **No absolute cinematic times inside a
  handler** — the `zoomPunchTimes` gotcha from the Massive build must not recur.
- A cut never touches `Camera.CameraType`, `ScreenGui.Enabled`, or `Lighting` directly.
  It drives the camera only through `run.cam` (`flyTo`, `lookHover`, `orbit`, `punchFOV`).
- Handler sharing is by `require`: `Cuts/Huge` reuses `Cuts/Massive`'s handlers on its
  own bounds; `Cuts/MassiveGod` composes handlers from `Cuts/Massive` and `Cuts/God` plus
  its own unique beats. There is one copy of the emergence code and one of the heaven code.
- `build` constructs only rigs specific to the cut (`BrainrotRig`, `WaterFX`, `RockRig`
  when a rock exists, `BeamFX`, `AuraFX`). Camera, HUD, audio, post-FX and UI are built by
  `Takeover`.
- `run.rock` may be nil (fishing). Every rock use is guarded, as today.

### 5.3 `RevealRouter` (StarterPlayerScripts.RevealRouter, replaces `CatchRevealClient`'s handler)

- Subscribes to `Remotes.ThrowResult` and `IceFishingEvent`'s existing client result
  remote (Studio-only module; its remote name is confirmed during planning). Both
  normalise to one grant record:
  `{ Name, Rarity, RarityColor, Mutation, Size, Serial, Exists, IsNew, Anchor, Source }`
  (`Source` = "throw" | "fish"; `Anchor` = splash position or hole surface point).
- Per grant, in order:
  1. `SkipReveal<Rarity>` gamepass attribute (existing seam, unchanged meaning — §11).
  2. `Config.CUT_FOR(rarity, size)`.
  3. If a cut: `Bridge.tryAdopt(result)` exactly as today. Adopted → the running
     `Takeover` owns the reveal; `onDone(false)` (cinematic died) falls back to a pop of
     that grant. Not adopted (no run, superseded gen) → pop.
  4. Otherwise enqueue `CatchPop.play(grant)`.
- FIFO: one reveal at a time. A pop never starts while `Takeover.isActive()`; a takeover
  never starts while a pop is on screen (it waits at most the pop's length, ≤ 1.5s).
- Input lock: sets player attribute `RevealActive = true` while a takeover is running for
  this player (thrower runs only, never spectators). `ClientMain`'s throw input and the
  fishing cast input refuse while it is set. Client-side by design: it protects the
  local camera round-trip and nothing else.
- Keeps `buildPayload` / the tier-cue logic from `CatchRevealClient` where still used;
  the `CatchFX` world burst still plays first on every grant (§7).

### 5.4 `CatchPop` (ReplicatedStorage.Modules.CatchPop, from `CatchReveal` bands 1–3 + `PullCeremony`'s stamp)

The screen-space pop for Common–Legendary. §7.

### 5.5 Server

- `ThrowHandler`: the broadcast condition changes from `CinematicConfig.SIZES[size]` to
  `Config.CUT_FOR(tier.Name, sizeVariant) ~= nil`; the payload gains `Cut = <name>`. The
  timing fields (`EndPos`, `SurfaceY`, `TotalTime`, `NContacts`, `SegTime`) and the
  fire-at-flight-start moment are unchanged. `ThrowResult` gains `IsNew` (true iff the
  name was not in the player's index before this grant, computed server-side at grant).
- The remote `Remotes.MassiveCinematic` is renamed `Remotes.CatchCinematic`
  (creator in `ThrowHandler`, consumers `CinematicClient` and `CinematicCommand`).
- `IceFishingEvent`: at hook-set (the LANDED-IT branch, before the grant is written) it
  fires the same broadcast with `EndPos` = the hole's surface point, `SurfaceY`, `Cut`,
  `BrainrotName`, `Rarity`, `RarityColor`, `Mutation`, `Size`, `Seed`, `UserId`, and no
  rock fields. Its existing client result payload gains the grant fields the router
  normalises (`Serial`, `Exists`, `IsNew`, `Anchor`). Grant order (roll → `__noSave`
  guard → insert → `PushUpdate`) is unchanged.
- No other server change. Grant authority, `MintRegistry`, `RareCatch`, `SeasonPass`
  notifications are untouched.

### 5.6 New helpers (all inside `ReplicatedStorage.Modules.CatchCinematic`)

| helper | what | why not an existing module |
|---|---|---|
| `BeamFX.lua` | the water→sky / rig→sky gold beam: tall neon column + `Beam` instances + `WaterFX.godrays` at the base; fade in/out; anchored on a world point or a rig | God and Massive God share it; nothing today draws a beam |
| `AuraFX.lua` | a large rift/aura plane + orbiting emitters behind a rig (Secret's pink rift, God's descent glow) | new kind of effect; shared by two cuts |
| `PostFX:tint(color, seconds)` | environment colour shift through the module that already snapshots and restores `Lighting` | keeps every `Lighting` write on the one restore path |
| `WaterFX:glowBelow(color, seconds)` | an under-surface glow next to the existing dome/shadow parts | Secret's fake-out and God's glow beat |
| `BrainrotRig:descend(from: Vector3, to: Vector3, seconds, yawPerSec)` | a hand-lerped pose path (sky → water), reversible for the ascension | the rig already owns pose math; a second pose helper elsewhere would duplicate it |

### 5.7 Reuse inventory

| Reused as-is | Extracted / re-homed | New | Retired |
|---|---|---|---|
| `CameraRig`, `ScreenShake`, `PostFX` (+`tint`), `AudioBus`, `WaterFX` (+`glowBelow`), `RockRig`, `BrainrotRig` (+`descend`), `Bridge`, `Config` (timescale, quality, SKIP, SPECTATOR_RADIUS, CANCEL_TIMEOUT), `CinematicClient` (broadcast receipt, three outcomes, stock landing, `CinematicCameraInbound` handshake), `CinematicCommand` (extended to six cut names), `CatchFX`, `SoundKit`, `MutationFX`, `BrainrotThumb`, `HypeUI` banner / nameText / cardArrive / bagTarget / skip prompt | `Sequencer` → `Takeover` + `Cuts/Massive` + `Cuts/Huge`; `CatchReveal` bands 1–3 + `PullCeremony` stamp & shards → `CatchPop`; `CatchRevealClient` handler → `RevealRouter` | `Cuts/Mythic`, `Cuts/Secret`, `Cuts/God`, `Cuts/MassiveGod`, `BeamFX`, `AuraFX`, `RevealRouter`, `CatchPop`, `Config.CUT_FOR` | `PullCeremony` (black-void takeover + odds climb), `MassiveEmergence`, `CatchReveal` band 4, `HypeUI` memeFlyIns / confetti / speedLines (no caller), the second-bonk one-shot and `RockRig`'s ricochet/plink timings that only served it |

## 6. The cuts

Times are cinematic seconds from t = 0 (final skip contact for throws, hook-set for
fishing). **Bold** = `revealBeat`. Spectator runs execute the world beats only: no camera,
no HUD change, no banner, no card. Every cut ends in a `handoff` beat that streaks the
creature into the bag (`BrainrotRig:compressAndStreak` → `HypeUI:bagTarget`) and then
restores; the restore itself is `Takeover`'s trove drain, never a beat.

### 6.1 Mythic — POWER — 1.7s — not skippable

| t0 | t1 | beat | handler |
|---|---|---|---|
| 0.00 | 0.15 | bonk | UI hidden by Takeover; "gameplay slows" rendered locally as an FOV tighten (`cam:punchFOV` toward a narrower FOV) + ambient duck (`audio:duckAmbient`). The world does not slow. |
| 0.15 | 0.25 | ripple | deep bass (`mythicBass`), `water:rippleTrain` expanding |
| 0.25 | 0.50 | **eruption** | `water:erupt`, creature breaches in 0.25s (`brain:setRise` 0→1), red energy ring (`water` ring in tier red) + `post:flash`, `shake:add(1.0)` |
| 0.50 | 0.60 | settle | creature to hover pose; `cam:lookHover` |
| 0.60 | 1.50 | banner | "MYTHIC" (`hype:banner`, tier red); red rim Highlight + particles on the rig; slow float (rig bob) |
| 1.50 | 1.70 | handoff | streak into bag |

### 6.2 Secret — SUSPENSE — 3.0s — not skippable

| t0 | t1 | beat | handler |
|---|---|---|---|
| 0.00 | 0.10 | bonk | UI hidden, final skip |
| 0.10 | 0.60 | nothing | no creature, no card; `water:rippleTrain` continues slowly; ambient to near-silence (`audio:duckAmbient(0.05)`) |
| 0.60 | 1.00 | fakeout | ripples die off; then a pink/purple glow appears under the surface (`water:glowBelow(color)`) |
| 1.00 | 1.20 | **launch** | `water:erupt` (pink column), `shake:add(0.8)`; creature launches out and stops in front of the camera (`brain:setRise` with overshoot to a hover point, `cam:lookHover`) |
| 1.20 | 1.50 | spiral | pink energy spirals around the creature (orbiting emitters, `_orbitForever` pattern) |
| 1.50 | 2.50 | banner | "SECRET" (tier pink); giant pink rift behind the creature (`AuraFX`), slow rotation, droplets (`water:cascade`, short) |
| 2.50 | 3.00 | handoff | effects fade, streak into bag |

The 0.10–1.00 dead air is where any grant latency lands; the clock parks before `launch`.

### 6.3 God — HEAVEN — 5.0s — skippable → `arrival`

| t0 | t1 | beat | handler |
|---|---|---|---|
| 0.00 | 0.30 | bonk | UI hidden; world goes quiet (`audio:silence`) |
| 0.30 | 0.50 | rumble | `godRumble` |
| 0.50 | 0.80 | glow | water glows gold/white from below (`water:glowBelow(gold)`), one massive ripple |
| 0.80 | 1.00 | tilt | golden particles rise; camera begins tilting up to a skyward framing (`cam:flyTo`) |
| 1.00 | 1.30 | beam | `BeamFX` fires: gold-white beam water→sky, godrays, environment gold via `post:tint`, sun rays react, water reflects |
| 1.30 | 2.00 | choir | the exclusive `godChoir` slot; beam holds |
| 2.00 | 3.50 | **descent** | creature appears inside the beam and descends slowly (`brain:descend`), slow rotation, gold light, falling particles |
| 3.50 | 3.80 | arrival | `post:flash`, "GOD" in huge gold text, massive gold shockwave ring across the water |
| 3.80 | 4.80 | linger | float; beam fades; particles fade; choir tails naturally |
| 4.80 | 5.00 | handoff | streak into bag |

`onSkip`: beam faded, `post:easeBack`, rig at the arrival pose, water calm.

### 6.4 Huge — SCALE — 4.8s — skippable → `banner`

Massive's handlers on Huge's bounds (the existing trimmed-variant mechanism), plus the
pull-back framing and the banner the trimmed cut lacked.

| t0 | t1 | beat | handler (from `Cuts/Massive`) |
|---|---|---|---|
| 0.00 | 0.30 | bonk | final skip, UI hidden |
| 0.30 | 0.80 | ripple | water moves strangely (0.30), large ripple (0.70) |
| 0.80 | 1.20 | splash | water starts splashing |
| 1.20 | 1.50 | silhouette | massive silhouette visible below the surface |
| 1.50 | 2.00 | **emergence** | bursts out, large splash, shake, droplets |
| 2.00 | 3.40 | scale | camera pulls back to establish size |
| 3.40 | 4.00 | banner | "HUGE"; creature remains in the water; water settles |
| 4.00 | 4.80 | handoff | streak into bag |

### 6.5 Massive — THE BEAST — 10.6s — skippable → `banner`

Re-paced to the blueprint. Intimidating, no comedy beats. Dread (still → silhouette)
≈ 2.6s, emergence + pull-back ≈ 3.4s.

| t0 | t1 | beat | blueprint act | handler |
|---|---|---|---|---|
| 0.00 | 0.50 | bonk | I The Rock | final skip contact; UI hidden; camera begins the low fly-out toward the water |
| 0.50 | 1.00 | still | II | nothing — glassy-still water (`water:stillWater`) |
| 1.00 | 2.00 | ripple | II | tiny ripple at 1.0, bigger at 1.5 (`water:rippleTrain` progress) |
| 2.00 | 2.50 | disturbed | II | water moves violently (ripple train accelerates, `water:suctionAndShadow` begins); deep rumble (`massiveRumble` → existing `rumbleLoop`) |
| 2.50 | 3.10 | silhouette | III | water darkens; gigantic silhouette below (`brain:stageBelow` + shadow); brief eyes/outline tease (`brain:angryEyes` read as glowing eyes under the surface, calmed before the reveal) |
| 3.10 | 4.10 | **emergence** | IV | slow physical rise begins (`brain:setRise` 0→0.5), huge splash column (`water:erupt`), waves, `shake:add(1.0)`, droplets. Never a pop-in. |
| 4.10 | 6.50 | scale | V | camera pulls WAY back (`cam:flyTo` to a far framing computed from `brain:extents`), creature keeps rising to full (`setRise`→1), `water:cascade` |
| 6.50 | 7.20 | banner | VI | "MASSIVE" in huge text; creature stands in the water; water still moving |
| 7.20 | 9.50 | aftermath | VII | camera settles (slow `cam:orbit`), water calms, creature remains |
| 9.50 | 10.60 | handoff | VII | streak into bag; restore |

`onSkip`: rig at full rise in the standing pose, eyes calm, water calm, camera at the far
framing, audio unsilenced, post eased back.

### 6.6 Massive God — ULTIMATE — 12.0s — skippable → `finalReveal`

One beat table; handlers from `Cuts/Massive` (emergence) and `Cuts/God` (heaven), plus
three unique beats. The beam is anchored on the rig.

| t0 | t1 | beat | act | handler source |
|---|---|---|---|---|
| 0.00 | 0.40 | bonk | I The Beast | Massive |
| 0.40 | 1.20 | ripple | I | Massive (still + ripple compressed) |
| 1.20 | 1.80 | silhouette | I | Massive |
| 1.80 | 2.80 | **emergence** | I | Massive |
| 2.80 | 4.50 | scale | I | Massive (camera pulls back, full rise) |
| 4.50 | 5.50 | hush | II Something is different | unique: everything goes silent (`audio:silence`), creature stops moving, camera tilts up, a tiny gold light appears above the creature and grows |
| 5.50 | 6.50 | beam | III Heaven opens | God's beam handler with `BeamFX` anchored on `brain:headTop()`; clouds lit, environment gold (`post:tint`); `godChoir` at beat start |
| 6.50 | 8.00 | ascend | IV Ascension | unique: creature rises into the beam and vanishes (`brain:descend` reversed), camera looks up, a beat of emptiness |
| 8.00 | 10.00 | descent | V Descent | God's `descent` handler at full Massive scale (the rig keeps `Sizes.Scale(size)`) |
| 10.00 | 10.80 | finalReveal | VI | flash, gold shockwave, water explodes outward (`water:erupt` at max radius), "MASSIVE GOD" |
| 10.80 | 12.00 | return | VII | Massive's aftermath + handoff: beam fades, water settles, streak into bag, restore |

`onSkip`: rig at the water in the standing pose at full scale, beam faded, `post:easeBack`,
water calm, choir left to tail.

### 6.7 Fishing anchoring

Same tables. t = 0 is hook-set. `run.rock` is nil, `EndPos` is the hole's surface point,
the "final skip" beats play their water/camera parts only. Spectator radius is measured
from the hole.

## 7. The pop layer — Common–Legendary

`CatchPop.play(grant)` runs one beat sequence — `appear → bounce+burst → text → float →
close` — parameterised by a preset per tier:

| tier | length | appear | bounce / burst | extras |
|---|---|---|---|---|
| Common | 0.8–1.0s | small scale-up | small bounce, tiny burst | subtle glow, tiny idle float; "COMMON" + name at 0.30 |
| Uncommon | 1.0s | same | stronger bounce, more particles, small green burst | green glow; slightly stronger cue |
| Rare | 1.0–1.2s | pops to centre, slight overshoot | blue burst | blue glow expands; small circular shockwave; "RARE" |
| Epic | 1.2–1.5s | stronger scale-up, slight rotation | larger burst, quick purple ring | UI bump; "EPIC" slams; purple particles linger |
| Legendary | 1.3s | rapid appear at 0.10 | orange/gold burst at 0.20, slight overshoot | slight environmental dim from 0.00; UI bump at 0.30; "LEGENDARY" at 0.40; orange particles orbit, glow pulse, float 0.40–1.00 |

Built from existing pieces: the model is `CatchReveal`'s viewport + `BrainrotThumb`
framing; glow/halo, shimmer and sparkles are `CatchReveal`'s band effects driven by the
preset; the radial burst is `PullCeremony`'s shards recipe; the shockwave is a UI ring
tween; the text is `PullCeremony`'s stamp recipe — header ("NEW BRAINROT!" / "YOU GOT!"),
name via `Sizes.Label`, rarity chip, and "#serial · ONLY n EXIST" plus the honest
"1 in N" odds line where the catch is mint-tracked (no climbing counter).

`CatchFX`'s world-space burst around the player stays as the "it landed" cue on every
grant; it is already tier-coloured.

**Pops never write to the camera or `Lighting`.** The Epic/Legendary "camera/UI bump" is a
`UIScale` kick on the pop's own gui; Legendary's "environmental dim" is a low-alpha overlay
inside the pop's gui. A pop therefore has nothing to restore and cannot strand the camera.

## 8. What is retired, and why

- `PullCeremony`: its black-void TAKEOVER and odds CLIMB are takeovers, which the blueprint
  forbids below Mythic ("no cinematic takeover" for Epic; "gameplay remains visible" for
  Legendary), and Mythic+ now have cuts. Stamp and shards move into `CatchPop`; the module
  is deleted once nothing requires it.
- `MassiveEmergence`: superseded by the Huge cut (the Massive build already parked it).
- `CatchReveal` band 4 (Secret/God black-backdrop world model): superseded by the cuts.
  Bands 1–3 machinery lives on inside `CatchPop`.
- `HypeUI` memeFlyIns / confetti / speedLines, the second-bonk one-shot, `RockRig`'s
  ricochet apex / plink pause: comedy beats removed per decision 6. `RockRig` keeps the
  final-skip staging the bonk beat needs.

## 9. Mutations in the reveal

- Cuts: the rig is a real world model; `MutationFX.apply(model, mutation)` exactly as the
  Massive cut does today. All twelve mutations, one path.
- Pops: `MutationFX.apply` is called on the throwaway viewport clone — the SAME call the
  world uses. Since the 2026-08-13 rewrite `MutationFX` shifts each part's own colours and
  materials, and those render inside a `ViewportFrame`; its emitters, lights, beams and
  highlights do not, and are simply inert there. The halo takes the mutation colour and
  the name reads `Sizes.Label(mutation, size, name)`. One mutation path for pops and
  cuts alike; no new rendering system, no mutation-specific modules. (Earlier draft of
  this section proposed a viewport `LightColor` tint; superseded once the live
  `MutationFX` was read at build start.)
- Display names and the "YOU GOT!"/"NEW BRAINROT!" header carry the mutation everywhere.

## 10. Copy and audio

- `IsNew` is server-authoritative (§5.5). `IsNew == true` → "NEW BRAINROT!"; anything else
  → "YOU GOT!". Pops show it as the stamp header; cuts show it on the end card.
- Pops reuse the eight per-tier catch cues and the existing volume ladder. No new sounds.
- Cut slots in `Config.ASSETS`, resolved through `AudioBus`/`SoundKit`:
  `mythicBass` → existing `bassDrop`; `massiveRumble` and `godRumble` → existing
  `rumbleLoop`; `secretLaunch` → `kit:splashBig`; `goldShockwave` → `kit:catchBigHit`;
  `massiveRoar` (emergence) → existing `roar`; `beamRise` and `godChoir` → new placeholder
  slots the owner fills. The placeholders from the Massive build that survive
  (`rumbleLoop`, `roar`) stay flagged in the same list; `bonkClonk`, `plink` and
  `memeAudio` go with the beats that used them. The final skip contact at t = 0 uses the
  stock landing's own splash cue (the one `CinematicClient.stockLanding` already plays),
  so a cut's opening sounds like every other throw's last skip.
- `godChoir` is exclusive by construction: only `Cuts/God` and `Cuts/MassiveGod` name the
  slot, and the slot's comment says so.
- No raw asset ids are added anywhere; every new sound is a named slot.

## 11. Queue, lock, skip, gamepass

- One reveal at a time per client (router FIFO). Spectator world FX are ambient and are
  not queued.
- `RevealActive` player attribute is set for the catcher for the life of a takeover run;
  throw and cast input refuse while set. Cleared by the trove on every exit path.
- Skip: `Config.SKIP` unchanged (prompt after 1.0s, hold 0.45s, exit fade 0.18s). Only
  cuts with `skippable = true` arm it. Skip remains gated on the grant having landed.
- `SkipReveal<Rarity>` (gamepass seam): for a pop tier, the pop is replaced by the ~3s
  corner text as today; for a cut tier, the catcher's own client runs the spectator
  (world-only) version of the cut plus the corner text. The server broadcast is unaffected.

## 12. Failure behaviour (shared by every cut)

| situation | behaviour |
|---|---|
| grant never confirms | cancel from the dark hold before `revealBeat`; nothing revealed; the throw's stock landing already played |
| camera takeover refused | run continues world-only (degrade, don't decline) |
| no model for the name | `build` returns false before anything is parented; router falls back to a pop |
| character dies / respawns mid-cut | kill switch → `finish(false)` → trove drains → camera, HUD, Lighting, audio restored |
| conductor error | pcall handler → `finish(false)` → same drain |
| stalled beat | in-conductor watchdog, then the `task.delay` backstop |
| cinematic module missing | `RevealRouter` requires it fail-soft and runs pops only |

The Studio-only `/cinematic <name> <cut>` test hook accepts all six cut names.

## 13. Verification plan

Code lives in Studio; verification is by harness and by eye, as in the Massive build.

1. **Structural harness per cut** at `CinematicTimescale = 4`: normal end, skip, cancel,
   death, spectator. Assert after each: stage empty; PlayerGui `Enabled` flags identical
   before/after; `CameraType` restored; zero leaked Sounds; `Lighting` children and
   properties identical; `RevealActive` cleared.
2. **Camera invariants on the real path**: throw during a cut (must be refused by the
   lock), a cut arriving while the stone-tracking camera is live (the
   `CinematicCameraInbound` handshake), hook-set while walking.
3. **Router matrix**: 8 tiers × {none, Huge, Massive} × {plain, Golden, Diamond, Angel} ×
   {throw, fish} → exactly one path per cell, equal to §4. Mutation must never change the
   path.
4. **Pop performance**: 20 back-to-back Commons; frame time within budget; no growth in
   gui children; no camera or `Lighting` writes (assert by snapshot).
5. **Mutation representation**: a Golden and a Diamond pop and cut, screenshotted,
   visibly different from the plain reveal.
6. **Visual sign-off per cut** with Studio foregrounded and the owner watching.
   Massive and Massive God timed against §6.5/§6.6.

## 14. Build order (for the implementation plan)

Each step leaves the game playable and the harness green before the next starts.

1. **Extract `Takeover` + `Cuts/Massive` + `Cuts/Huge`** from `Sequencer`, behaviour-
   preserving at the *current* 17.9s pacing; the Massive harness from the last build must
   pass unchanged. Then re-pace Massive to §6.5, remove the comedy beats, add Huge's
   `splash`/`banner` beats and switch Huge on.
2. **`Config.CUT_FOR`, the `CatchCinematic` remote rename, `IsNew`, `RevealRouter`, the
   `RevealActive` lock, `CatchPop`** (§7, §9 pops) — pops replace the ordinary chain;
   `PullCeremony`, `MassiveEmergence` and `CatchReveal` band 4 retire here.
3. **`Cuts/Mythic`, `Cuts/Secret`** (+ `WaterFX:glowBelow`, `AuraFX`).
4. **`Cuts/God`** (+ `BeamFX`, `PostFX:tint`, `BrainrotRig:descend`, `godChoir` slot).
5. **`Cuts/MassiveGod`**.
6. **Fishing wiring** (`IceFishingEvent` broadcast + result fields; cast-input lock).
7. Router matrix, leak audit and visual sign-off across all six cuts.

## 15. Out of scope

- Egg hatching, fusion, offering and trade reveals.
- Any change to grant rules, odds, mint tracking, bag caps or economy.
- Sound asset creation (slots are provided; the owner supplies ids).
- Dead-instance cleanup unrelated to the reveal (`ShopPanelCentre`).

## 16. Build notes (2026-09-17, recorded during implementation; decisions above unchanged)

- **`BrainrotRig:descend` shipped as `setDescent(alpha, fromHeight)`** — pure in alpha, in
  `setRise`'s house style (hand-lerped, reversible), so Massive God's ascension is the same
  function run backwards. God calls it forward from `descentHeight = ext.Y * 6`.
- **§9 "exactly as the Massive cut does today" was not true**: the old `Sequencer`/
  `BrainrotRig` never applied `MutationFX`; only the retired `PullCeremony` and `CatchReveal`
  band 4 did. The build adds it in `BrainrotRig` for every cut: `MutationFX.apply` runs on
  the display clone after the rig geometry is read (a halo or ground ring never changes the
  framing extents), its colour/material shifts become the silhouette's stored originals, and
  everything it ADDS (emitters, lights, highlight, beams, halo/ring/shell parts, textures)
  plus the `MutationBody` tag is held back until `revealColors()` — so a Secret's "nothing"
  beat stays dark and a creature in the water never glows early. A confirmed grant whose
  mutation differs from the flight-time roll restages the model (`setMutation`, same
  pre-breach rule as the name swap).
- **Hero framing pad now scales with the creature** (`CutKit.heroFraming`): MassiveEmergence's
  flat 10-stud pad doubled the distance on a 9-stud Mythic and left the hero shot small; the
  pad is a quarter of the width, clamped 1.5–10, so a Massive frames exactly as before.
- **`Harness` death mode is respawn-aware** (the camera subject is legitimately a new Humanoid
  after a respawn) and gained `Harness.pop(rarity, mutation, name)` for single-pop captures.
- **Studio must be RENDERING for any Play verification.** A minimized Studio stops
  `RenderStepped`; `CatchPop` (RenderStepped) and `Takeover` (BindToRenderStep) both freeze,
  pops queue forever and cuts never advance. Only an environment effect (a real client always
  renders), but simulated keys only reach the game while it renders too.
- **Fishing cut verification used `ReplicatedStorage.WeatherMut = 300` for the session** to
  make `Sizes.Roll` certain (no fishing force hook exists); the pop path used real rolls.
- **Pop placement**: `CatchPop` keeps CatchReveal's `TOP_Y = 78` anchor, so the spinning model
  sits behind the SKIP/SHOPS/PLOT tab row — inherited, flagged for the owner's sign-off.
- **`godChoir`, `beamRise`, `secretHum`, `massiveRumble`, `roar`/`massiveRoar` are placeholder
  ids** (TODO in `Config.ASSETS`), and the God real-throw test consumed one of Secret Pete's
  five mint serials (MintRegistry does not roll back on entry deletion).
