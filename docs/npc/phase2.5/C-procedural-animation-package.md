# C — Procedural Animation Package v1 (Villager pack + Gianluca)

**Lane:** NPC-01 · Phase 2.5 · 2026-09-19 · spec for `NpcMotionConfig` / `NpcMotion` / `NpcLifeClient` (kit C7). No uploaded assets anywhere. Subtle by design: nothing here exceeds 40° on a limb except the one signature gesture, and nothing loops as a visible cycle.

This package **supersedes the keyframe sign convention in Phase 2 spec A §A9** — values are restated below in semantic axes so authors never think about CFrame signs.

## C1. Semantic joint axes (the authoring vocabulary) and their CFrame mapping

Authors write degrees on semantic axes; `NpcMotion` maps them per joint and side. `side = +1` for Right*, `−1` for Left*, `+1` for spine joints. Character space: front −Z, right +X, up +Y (`CFrame.Angles(rx, ry, rz)` order X, Y, Z).

| Joint class | Axis | Meaning (+) | CFrame mapping |
|---|---|---|---|
| limb (Shoulder, Elbow, Wrist, Hip, Knee, Ankle) | `swing` | limb end moves **forward** (and up) | `Angles(+swing, 0, 0)` |
| limb | `spread` | limb end moves **away from the body** | `Angles(0, 0, side × spread)` |
| limb | `twist` | rotation about the limb's own axis, outward | `Angles(0, side × twist, 0)` |
| spine (Root, Waist, Neck) | `bend` | **forward / nod down** | `Angles(−bend, 0, 0)` |
| spine | `turn` | **to the character's right** | `Angles(0, −turn, 0)` |
| spine | `tilt` | top moves **toward the right shoulder** | `Angles(0, 0, −tilt)` |
| any | `x / y / z` | translation in studs (pivot space) | `CFrame.new(x, y, z)` |
| face joints | `browOuterUp`, `y`, `x`, `rotZ` | brow outer end up; offsets | `BrowR: Angles(0,0,+a)`, `BrowL: Angles(0,0,−a)` |

Composition per joint: `offset = CFrame.new(x,y,z) * Angles(rx, ry, rz)` from the summed semantic values, and the driver writes `joint.C0 = rest[joint] * offset`. Every value is **absolute from the captured rest** — never accumulated.

## C2. Randomness and determinism

- No `math.random`. Every phase, hold target and gesture pick comes from `hash(model.Name, pivot.Position, salt)` (the `BrainrotIdleClient.phaseFor` rule) so all clients see the same performance with zero network traffic.
- "Occasional" = a cooldown drawn from a `[min, max]` range by hash, re-drawn after each firing.
- Snap-and-hold targets (`kind = "snap"`) use `hash01(step)` exactly as `NpcIdle.snapYaw` does `[code]`.

## C3. Layer kinds (what `NpcMotion` evaluates)

| kind | Parameters | Output over time |
|---|---|---|
| `sine` | `amp`, `period`, `phase` (0–1 of period) | `amp · sin(2π t / period + phase)` |
| `sineAbs` | same | `amp · |sin(...)|` (dips only one way — bobs that never sink below rest) |
| `snap` | `amp`, `period`, `ease` (fraction of the period spent moving), `min` (fraction of amp always exceeded, optional) | snap-and-hold between hashed targets in `[−amp, amp]` |
| `pulse` | `amp`, `every = {min,max}`, `duration`, `curve` | one bump per cooldown |
| `follow` | `source = "Neck.turn"`, `gain` | a fraction of another layer's current value |
| `counter` | `source = "Root.tilt"`, `gain = −1` | cancels a parent's motion (planted feet / planted prop) |
| `track` (target) | `target = "player"`, `maxTurn`, `maxBend`, `smooth` (time constant, s) | exponential smoothing toward the aim angles |
| `keys` (gesture) | `duration`, `keys = { {t, Joint = {axis = v, …}}, … }`, `hold`, `easing` | smoothstep between keys; unspecified joints hold previous |

Blend weights: every layer and gesture has a **weight ramp** (0.25 s in, 0.35 s out) so nothing pops.

## C4. IDLE — Villager base, with Gianluca's overrides in **bold**

| # | Layer | Joints | Range | Timing | Randomness | Notes |
|---|---|---|---|---|---|---|
| I1 | breathe | Waist `bend` +1.5° (**+1.8°**) · Neck `bend` −0.5° (same phase) · Shoulders `spread` +0.4° | ±1.5° / ±0.5° / ±0.4° | period 3.4 s (**2.9 s**) | phase hashed | chest lifts, head stays level, arms ride the ribs |
| I2 | weight shift | Root `tilt` ±2.5° (**±4°**) · Root `y` `sineAbs` −0.03 · LeftHip/RightHip `tilt` = `counter(Root.tilt)` · RightShoulder `spread` = `counter(Root.tilt)` **when the right hand holds a `Planted` prop** | as stated | period 9.0 s (**7.0 s**) | phase hashed | legs stay vertical; the planted cane keeps its tip on the ground (≤ 0.03 stud slide) |
| I3 | occasional look | Neck `turn` `snap` ±22° (**±28°**), `ease 0.18` · Neck `tilt` `snap` ±3° · Waist `turn` = `follow(Neck.turn, 0.3)` | ≤ 28° | hold period 6.5 s (**5.0 s**) | targets hashed per hold | snap-and-hold reads as *deciding* to look; a sine reads as a fan |
| I4 | subtle hand motion | LeftWrist `swing` ±3° + LeftElbow `swing` ±2° (`sine`, period 4.1 s) · **RightWrist/RightElbow: 0 (cane hand)** · every 12–20 s (**12–18 s**) a `minorGesture` | ≤ 3° continuous; gesture ≤ 40° | see G-minor below | cooldown hashed | mitt hands can't finger-fidget; the wrist sway is what "resting hands" look like from 10 studs |
| I5 | hands on hips (Villager only) | both Shoulders `spread` +35 `swing` +20 · Elbows `swing` +95 · hold 6 s | | every 20–40 s | **off for Gianluca** | reads settled; wrong for him |

**G-minor `scratchBrim` (Gianluca's I4 gesture):** 1.4 s; LeftShoulder `swing` +40 `spread` +25, LeftElbow `swing` +110, LeftWrist `twist` −20 → hand at the hat brim; hold 0.5 s; return. Villager default `adjustCollar` is the same shape at half amplitude with the hand at the collar.

Amplitude ceiling for idle layers: **spine ≤ 4°, limbs ≤ 40° in gestures, ≤ 3° continuous.**

## C5. TALKING (active while `talking` is set — kit C7.6 hook)

| # | Layer | Joints | Range | Timing | Notes |
|---|---|---|---|---|---|
| T1 | head tracking / attention | Neck `turn`, `bend` → `track(player head)`, clamps ±35° / ±15°, `smooth 0.25 s` · Waist `turn` = `follow(Neck.turn, 0.3)` | ≤ 35° | continuous | replaces I3 on the same axes (priority 2 over 1, 0.3 s crossfade). Also runs at **0.6 weight while a prompt is shown** (he notices you before you press E). Beyond 24 studs (the dialogue's own walk-away) it releases |
| T2 | conversational hand gesture | one of: `emphasis` — RightShoulder `swing` +30, RightElbow `swing` +55, 1.2 s (the cane lifts a little: emphasis) · `openHand` — LeftShoulder `swing` +25 `spread` +20, LeftElbow `swing` +70, LeftWrist `twist` +25, 1.4 s | ≤ 55° | every 4–7 s, hashed pick | no arm ever rises above the shoulder while talking |
| T3 | nod | Neck `bend` `pulse` +3°, 0.5 s | 3° | every 3–5 s | reads as agreeing with himself |
| T4 | mouth / face | `Mouth.Size.Y` 0.07 ↔ 0.16 at 6–8 Hz in bursts of 1.5–2.5 s with 0.5 s rests; expression `talking-<current>` | — | while talking | approximates the typewriter cadence without reading the locked UI |
| T5 | gaze | pupils toward the player's head, x ±0.06 / y ±0.04, 10 Hz | — | while near/talking | the cheapest "alive" signal |

Idle layers I1, I2, I4 keep running underneath talking; I3 and I5 are suppressed.

## C6. SIGNATURE — `ringBell` (Gianluca) — restated in semantic axes

2.4 s · weight 3 · cooldown 14–26 s (hashed) · also the **greet** on `PromptShown` · suppressed while talking (T2 handles gestures then).

| t (s) | RightShoulder | RightElbow | RightWrist | Neck | Waist |
|---|---|---|---|---|---|
| 0.00 | 0 | 0 | 0 | 0 | 0 |
| 0.45 | swing +75, spread +8 | swing +25 | 0 | 0 | 0 |
| 0.65 | | | twist +22 | | |
| 0.85 | | | twist −22 | | |
| 1.05 | | | twist +22 | | |
| 1.25 | | | twist 0 | | |
| 1.45 | | | | turn −38, bend −4 | turn −10 |
| 1.85 | | | | turn +38 | turn +10 |
| 2.15 | | | | turn 0, bend 0 | turn 0 |
| 2.40 | swing 0, spread 0 | swing 0 | | | |

Read: cane to chest height, three bell shakes, look left, look right, plant. It is the one gesture above 40°, and it is his.

Non-Gianluca greets in the same pack: `wave` (RightShoulder `swing` +60 `spread` +30, RightElbow `swing` +80, RightWrist `twist` ±20 ×2, 1.6 s) and `nodGreet` (Neck `bend` +8, 0.6 s) for Tier 1.

## C7. Blend behaviour

- All layers produce semantic values per joint; values on the **same joint axis** are **summed** unless a higher-priority layer claims that axis (T1 over I3; a running gesture over I4/I5 on its joints); claimed axes crossfade over 0.3 s.
- Gestures run one at a time per body; a gesture never starts while another is above 10 % weight.
- Talking start: T-layers ramp in over 0.25 s; talking end: ramp out over 0.4 s and the `talking-` face reverts.
- Band change (near ↔ mid): update *rate* changes, values do not jump; the last written pose holds between updates.

## C8. When animation stops

| Condition | Behaviour |
|---|---|
| > 140 studs or off-screen | driver stops writing; joints **hold the last pose** (no snap to rest); lights off |
| re-entering ≤ 140 | resume from the held pose with a 0.5 s crossfade toward the live evaluation |
| model streams out | entry dropped; on stream-in the rig arrives in its authored rest and is re-adopted |
| `NpcBody` tag removed / model destroyed | entry dropped, no writes |
| > 12 animated bodies in view | only the nearest 12 evaluate; the rest hold |
| conversation ends by walk-away | same as talking end |
| local player dead / respawning | T1 releases (no target); idle continues |

Nothing ever writes from the server; nothing ever accumulates; a body left alone forever is exactly at its authored rest plus the current frame's offsets.

## C9. Interaction with dialogue (zero edits to locked files)

1. `ProximityPromptService.PromptShown(prompt)` → if the prompt's root model is `NpcBody`: greet once (`ringBell` for Gianluca), T1 at 0.6 weight, gaze on.
2. `PromptTriggered` on that prompt **and** `PlayerGui.MerchantDialogUI.DialogRoot.Visible` turns true within 1 s → `talking` on that model: T1–T5, face `talking-`.
3. `DialogRoot.Visible` false, or player > 24 studs from the anchor, or 180 s → `talking` off.
4. The portrait copies live CFrames each frame, so the conversation gestures play in the portrait for free.
5. **[OPT, decision D-3]** quest clients may set `NpcFace` on the model for story beats; the driver applies it on change.

## C10. Interaction with later authored tracks (the swap hook)

- Any layer or gesture may carry `asset = "rbxassetid://…"` or `sequence = "<KeyframeSequence name in ReplicatedStorage.NpcAnimations>"`.
- With `NpcMotionConfig.USE_TRACKS = true`, entries that have an asset play as `AnimationTrack`s (they own `Transform`); entries without one keep evaluating procedurally (they own `C0`). Both compose in the same joint.
- A pack may declare `layersWithTracks = false` to silence I1–I4 once an authored idle exists, or keep them (procedural breathing over an authored idle is allowed and usually better).
- Gesture scheduling, cooldowns, priorities, bands and the talking hooks are identical in both modes — the migration is data, not code.

## C11. Authoring checklist (per new pack or gesture)

1. Name it, give it `weight`, `cooldown`, `duration`, `priority`.
2. Write keys in semantic axes; keep limbs ≤ 40° unless it is the character's one signature.
3. Check the planted-prop rule if the gesture moves a planted hand.
4. Verify the last key returns to zero unless `hold`.
5. Play it at 60 studs: if you can name what he is doing, it is too big; if you can tell he is alive, it is right.
