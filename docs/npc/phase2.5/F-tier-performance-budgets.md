# F — Tier Performance Budgets (designed for many NPCs)

**Lane:** NPC-01 · Phase 2.5 · 2026-09-19. These are the numbers `NpcBudget.review` enforces (per model) and `NpcLodProfiles` encodes (per runtime). Calibration point: the brainrot pack median is 11 BaseParts / 57 descendants per body, max 39 `[doc: build standard]`; a full server already runs 6 camps × 16 plot bodies through one client Heartbeat at 54.9 Hz `[doc]`. NPCs must sit *under* that curve, not beside it.

## F1. Per-model budgets (build-time gate)

| Row | Tier 1 — background | Tier 2 — quest / shopkeeper | Tier 3 — story |
|---|---|---|---|
| BaseParts total (human) | ≤ 30 (16 body + 7 face + ≤ 7) | ≤ 38 (+ ≤ 15) | ≤ 50 (+ ≤ 27) |
| BaseParts total (creature) | template + ≤ 4 | template + ≤ 6 | template + ≤ 8 (≤ 14 pack / ≤ 20 forge) |
| Bespoke (non-library) meshes | 0 | ≤ 3 | ≤ 8 |
| Triangles (at scale 1 / plot fit) | ≤ 5k (target 3.5k) | ≤ 9k (target 4.5k) | ≤ 16k (target 8k) |
| Motor6D | 22 | 22 | ≤ 27 |
| WeldConstraints | ≤ 8 | ≤ 14 | ≤ 24 |
| Attachments | ≤ 16 | ≤ 18 | ≤ 20 |
| Emitters / particles alive | 0 / 0 | ≤ 2 / ≤ 30 (only if the concept is the emitter) | ≤ 6 / ≤ 80 (`BrainrotFX` kits only) |
| Lights | 0 | ≤ 1 (`PointLight`, range ≤ 18) | ≤ 1 |
| Highlights / Beams / Trails / Unions | 0 | 0 | 0 |
| Textures / Decals / SurfaceAppearance | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / ≤ 1 (creature face only) |
| Neon parts | 0 | ≤ 1 (a lens, a gem) | ≤ 2 |
| Scripts / Humanoid / constraints / physics | 0 / none / 0 / none | same | same |
| Descendants | ≤ 90 | ≤ 110 | ≤ 140 |
| CanCollide parts | 0 | ≤ 1 (Collider) | ≤ 1 |
| CanQuery / CanTouch parts | 0 / 0 | 0 / 0 | 0 / 0 |
| Anchored parts | HRP (+ Collider) only | same | same (+ creature RootPart) |
| ModelStreamingMode | Atomic | Atomic | Atomic |

## F2. Runtime budgets (`NpcLodProfiles`)

| Row | Tier 1 | Tier 2 | Tier 3 |
|---|---|---|---|
| **Active animation distance** (procedural evaluated) | ≤ 90 studs | ≤ 140 | ≤ 160 |
| full-rate band | ≤ 30 | ≤ 40 | ≤ 50 |
| half-rate band (every 2nd frame) | 30–60 | 40–90 | 50–100 |
| quarter-rate band (every 4th frame) | 60–90 | 90–140 | 100–160 |
| **Face update distance** (blink/gaze) | ≤ 20 (blink only) | ≤ 40 | ≤ 50 |
| **Idle update frequency** | 60 → 30 → 15 Hz by band | same | same |
| gesture scheduling | ≤ 30 studs only | ≤ 90 | ≤ 100 |
| **Dialogue activation distance** (prompt `MaxActivationDistance`) | — (ambient; optional prompt 8) | 10 standard (existing prompts keep their authored 8–18) | 12 |
| talk-state range (walk-away) | — | 24 (the dialogue's own rule) | 24 |
| head-tracking range (prompt shown / near) | — | ≤ 24 | ≤ 24 |
| light enabled | — | ≤ 70 studs | ≤ 70 |
| **Offscreen behaviour** | pose held, no writes, lights off | same | same; a Tier 3 in a cutscene is force-near |
| **Max simultaneous animated NPCs** | shared pool: **12 per client**, nearest first; Tier 3 in conversation/cutscene reserves a slot | | |
| per-body per-frame ceiling | ≤ 6 `C0` writes | ≤ 8 | ≤ 10 |
| server per-frame cost | **0** | 0 | 0 |

Offscreen test: `Camera:WorldToViewportPoint(pivot)` on-screen flag **or** `(pivot − camPos).Unit:Dot(camLook) > −0.2`; hysteresis 0.5 s so heads turning at the frame edge do not flicker.

## F3. Per-world and per-server envelopes

| Envelope | Value | Why |
|---|---|---|
| NPC bodies per world (live at once) | ≤ 24 (Tier 1 ≤ 14, Tier 2 ≤ 8, Tier 3 ≤ 2 talking + statues) | 24 × 38 parts worst case ≈ 900 parts — under one plot camp |
| NPC BaseParts per world | ≤ 1,200 | |
| NPC lights per world | ≤ 8 | plus the world's own lighting budget (tundra already runs 88 lights `[doc]`) |
| registry size the driver tolerates | 200 bodies (all worlds streamed in on a big client) — ranking every 10 frames is O(n log n) on 200 = negligible | streaming keeps the real number far lower |
| animated per client | 12 | measured headroom from the plot idle client (80 bodies budget, 54.9 Hz full server) — NPCs get 12 because each does joint work, not a single `PivotTo` |
| replication | 0 bytes/frame for NPC motion | client-only driver |
| memory per human | ≈ 15 shared meshes + ≤ 8 library meshes; no per-NPC textures | |

## F4. Designing for "many NPCs" (rules the driver must implement now, not later)

1. **One Heartbeat, one registry** — no per-NPC connections, ever (the lesson `BrainrotIdleClient` and the Cove driver already encode `[code]`).
2. **Rank, then work**: every 10 frames sort by camera distance, assign bands, choose the animated 12; per frame only the animated set is touched.
3. **World bucketing**: bodies carry `NpcWorld`; the ranking skips bodies whose world is not the player's current world (from the same attribute the teleport system stamps, or by distance > 2,000 studs) before sorting.
4. **No allocation per frame**: layer outputs are written into preallocated per-joint tables; `CFrame` construction only for joints that changed this frame.
5. **Faces are event-driven**: blink/talk are timers, gaze runs at 10 Hz, expressions on attribute change — zero per-frame face cost at rest.
6. **Props cost nothing**: welded; no per-frame prop code (retires `NpcPropLife`'s pattern).
7. **Streaming-safe**: adopt on tag-added, drop on `AncestryChanged`; never cache a part reference across a stream-out.
8. **Tier 1 is cheap by construction**: Background pack = 3 layers on 3 joints; no gestures beyond 30 studs; no face beyond 20.
9. **Budget report on every build**; nothing enters a world folder on WARN without a written reason, never on FAIL.
10. **Measure at the full-server condition** (six players, six camps, blizzard rig) before the merchant batch ships — the same test the World 2 masterplan uses `[doc]`.

## F5. Existing live scripts' cost, for the record (what migration removes)

| Script | Today | After migration |
|---|---|---|
| `NpcRigLife` | 15 server-side physics rigs, catalog idles, welds by distance | retired |
| `NpcBodyLife` | ~15 root CFrames replicated every frame, ungated | retired |
| `NpcPropLife` | ~50 prop parts replicated every frame, ungated | retired |
| `NpcIdle` | ~70 parts replicated every frame near the valley elder | retired (Tung's rock re-implemented client-side when he is upgraded — not now) |
