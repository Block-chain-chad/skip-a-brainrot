# NPC-01 — Step 0 Report (disk-side authoring)

**Lane:** NPC-01 · **Branch:** `npc-01-character-overhaul` · 2026-09-19
**Scope honoured:** disk-side only. No Studio control, no live Gianluca, Bombardiro template untouched, Elder Tung locked, no quest/prompt/MerchantDialog/world edits, no active behaviour installed anywhere, nothing pushed or merged. Decisions D-1…D-10 applied as approved.

## 1. Files authored (29 new, 3 touched)

**Kit sources — `game-src/npc-kit/` (staging, like `game-src/eggs/`; `game-src/place-full/` stays the byte-exact live mirror)**

| File | Lines | Role |
|---|---|---|
| `ReplicatedStorage/Modules/NpcKit/NpcRigSpec.lua` | 170 | SR-Rig v1: 3 body types, 15 parts + 15 joints (pivots → `C0/C1` derived, never hand-typed), attachments, grips, joint classes/sides, D-1 collider spec |
| `…/NpcFaceConfig.lua` | 130 | 7-part cube face, 8 expressions + talking/closed/blink/gaze numbers, `Resolve`/`Apply`; **`NpcFace` attribute = the public interface (D-3)** |
| `…/NpcLibrary.lua` | 150 | Wave-1 library: body segments (forge refs), 7 hair/hat/beard, 12 overlays, 7 props — every non-body entry has a primitive `blockout` |
| `…/NpcFamilies.lua` | 80 | 11 clothing families as colour sets + body roles + default overlays |
| `…/NpcWorldThemes.lua` | 75 | Valley/Tundra/Gardens/Trading: palette shift, accent, overlay swaps, per-family world cuts (D-5) |
| `…/NpcMotionConfig.lua` | 230 | packs Background/Villager/Merchant/Guard/Survivor/Creature, 20 gestures in semantic axes, per-joint amplitude limits, `Resolve` with dot-path overrides, `USE_TRACKS` hook |
| `…/NpcLodProfiles.lua` | 60 | tier bands, 12-animated cap, off-screen hysteresis, world radius, new-prompt defaults (D-8) |
| `…/NpcMotion.lua` | 170 | pure: hashing, curves, snap-and-hold, gesture evaluation, semantic-axis → CFrame, aim angles |
| `…/NpcLife.lua` | 560 | driver core with injected services: tag-tracked registry, ranking/bands, `C0` writes from captured rest, gestures/greet/talk/tracking, face timers, prompt + dialogue hooks |
| `…/NpcCharacters/Gianluca.lua` · `VeteranBombardiro.lua` · `Villager_Valley_01.lua` | 60 / 45 / 10 | the three recipes |
| `StarterPlayer/StarterPlayerScripts/NpcLifeClient.client.lua` | 80 | wiring only; **inert without the `NpcBody` tag (D-7)**; hooks `MerchantDialogUI` whenever it appears |
| `ServerStorage/NpcForge.lua` | 470 | `Build(recipe, opts)` humans + creatures from data; blockout or Import-3D meshes; collision group (D-1); `SwapLive` hard-gated (`STOP5` + `SWAP-LIVE`) |
| `ServerStorage/NpcBudget.lua` | 190 | `report` / `review` gate per doc F; declared blockout allowance |
| `README.md` | — | DataModel path map, invariants, install order |

**Validation tooling — `tools/npc_kit/`**

| File | Role |
|---|---|
| `rbx_stub.lua` (≈ 520) | Roblox API stub in plain Lua: Vector3/CFrame with real rotation math, Color3+HSV, Enum, Instances (parenting, attributes, signals, Clone with joint remapping, PivotTo/ScaleTo/extents, camera projection), CollectionService, PhysicsService, RunService, Players, ProximityPromptService, script loading with `require` by instance |
| `harness.py` | builds the DataModel tree for the kit, loads the real modules under Lua 5.1 (lupa), helpers |
| `lint.py` | compile check, Luau-only-syntax check, forbidden APIs per file, header check, data cross-references |
| `tests/` (6 files, 31 tests) | see §3 |
| `tools/README.md` (+ section) | how to run |

## 2. Architecture summary

- **Data-driven end to end.** An NPC is a recipe (`NpcCharacters/<Id>`) referencing library ids, a family, a theme, a pack and overrides. `NpcForge.Build` has no per-character code paths; the runtime reads only attributes the forge stamped on the model.
- **SR-Rig v1** as approved: R15 part/joint names on Motor6D, `AnimationController` present, HRP anchored (+ a tight D-1 collider in its own `NpcBody` collision group on Tier 2/3), every other part jointed/welded — kinematic, no physics, no Humanoid.
- **Procedural motion writes `Motor6D.C0`** from a captured rest, in semantic axes mapped per joint side; authored tracks later own `Transform` and compose on top (`USE_TRACKS` + `asset`/`sequence` fields, no framework change).
- **Client-only driver**, one Heartbeat, tag-driven registry, ranked every 10 frames into tier bands, ≤ 12 animated, off-screen hold with hysteresis, face timers event-driven. Zero server cost.
- **Zero edits to locked files**: greet on `PromptShown`, talking from `PromptTriggered` + `MerchantDialogUI.DialogRoot.Visible`.
- **Two build modes**: `blockout` (primitives, no meshes — the Step 7 preview) and `importRoot` (Import-3D meshes by name; `MeshId` is never assigned by script).

## 3. Validation results

| Check | Result |
|---|---|
| `python -m npc_kit.lint` | **OK** — 15 files compile under Lua 5.1; no Luau-only syntax; no forbidden APIs (`math.random`, `Instance.new`, `Transform =`, workspace scans, server remotes in the driver; `MeshId =` in the forge); headers present; recipes ↔ library/families/themes/packs cross-reference; gesture amplitudes within per-joint limits |
| `python -m pytest npc_kit/tests -q` | **31 passed** in < 1 s |
| Rig arithmetic | joint frames equal the manifest (Neck `C0 (0,0.6,0) / C1 (0,−0.45,0)` …), height 5.225, head offset 1.45, 15/15 per body type, mirrored left sides |
| Motion signs (real CFrame math) | swing +90 → hand forward (−Z); spread outward on both sides; spine turn + → faces +X; bend + → nose down; tilt + → top toward right shoulder; brow outer-up mirrors per side; `ringBell` keys at 0.45 s / 1.45 s / 2.4 s; smoothstep half-way = 37.5°; snap bounded; hashes deterministic; aim angles exact |
| Forge — Gianluca (blockout) | 22 Motor6D, 7 face parts, 1 `AnimationController`, 0 Humanoid, **0 ProximityPrompt**, HRP + Collider the only anchored parts, `CanQuery/CanTouch` false everywhere, `CanCollide` only on the collider, tag + attributes stamped, staged under `ServerStorage.NpcStaging.Valley`, budget PASS (with the declared blockout allowance), collision group registered, cane welded to `RightHand` with `Planted`, bell welded to the cane, `BracerR/L`, rest lean baked into the Waist `C0`, no orphan parts |
| Forge — Tier 1 villager | builds from the 10-line recipe, no collider, ≤ 30 parts |
| Forge — Veteran (on a stub species) | source template unchanged (descendant count, parentage, emitters intact); clone has 0 emitters/sounds, 8 story parts welded to the requested bones (`WingSplint → WingL`, `Medal → HarnessPlate`), root anchored, no orphans, plot-fit scaling applied, stance tilt applied, no `BrainrotBody` tag |
| Budget gate | FAILs on a Humanoid; FAILs on an orphan part |
| SwapLive | refuses without `gate="STOP5"` + `confirm="SWAP-LIVE"`; `Build` never calls it (tripwire) |
| Driver | inert with nothing tagged (0 ranks, 0 writes over 120 frames); adopts a tagged body when it enters Workspace; animates from rest; **60-second run: root within amplitude, no drift**; prompt shown → `ringBell` greet lifts the cane; trigger + dialogue visible → talking (mouth oscillates) → dialogue hidden → mouth restored; `NpcFace` attribute changes the brows; far body holds, animated set ≤ 12 of 17; dropped when removed from Workspace |
| Client script | runs inert with a legacy Humanoid rig present (its parts untouched over 300 frames, no warnings); picks up a body tagged later; hooks a `MerchantDialogUI` created after startup and starts/stops talking from `DialogRoot.Visible` |

## 4. Bugs the harness caught before Studio (and fixed)

1. **Lifecycle:** a model tagged while parked in `ServerStorage.NpcStaging` (exactly what the forge does) was never adopted when later parented into Workspace — the tag signal had already fired. The driver now *tracks* every tagged model across re-parenting (adopt on entering Workspace, drop on leaving).
2. **Talk cadence:** the mouth burst/rest state machine was inverted (rested through the burst window).
3. **Dialogue hook:** a timed `WaitForChild` on a GUI that `MerchantDialog` only creates on the first conversation would have silently expired in quiet sessions — replaced by a `ChildAdded` watch.
4. **Budget vs blockout:** primitive pieces (2–3 parts where a mesh has one) overshot the Tier 2 caps; blockout builds now declare themselves and get a bounded allowance with a WARN row, while mesh builds keep the strict caps.

## 5. Deviations from the Phase 2.5 docs (all deliberate)

- Collider tightened to **1.6 × 4.4 × 1.2** in its own `NpcBody` collision group (D-1 guardrails); doc A updated.
- Gesture amplitude caps are **per joint** (shoulder 60, elbow 110, wrist 30, spine 40, signature 90) instead of a flat 40 — an elbow bend is not a broad silhouette move; the wave was toned down to a 50° shoulder.
- Sources live in `game-src/npc-kit/` (staging), not `game-src/place-full/`, so the live mirror stays byte-exact; the README maps each file to its install path.
- The first part of a multi-part piece carries the piece id (`Props.Cane`, `Cane_Shaft`) so lookups are stable.

## 6. Still to do inside Step 0 (Python-side, no Studio)

- ~~Forge `npc` profile and the `standard` body lattice + rendered previews~~ — **done in the final Step 0 pass: see [STEP0-VISUAL-PROTOTYPE.md](STEP0-VISUAL-PROTOTYPE.md)** (`tools/npc_kit/forge_npc.py`, `preview.py`, `build.py`; 11 tests; `docs/npc/previews/`). Test count is now 42.
- `NpcLifeClient` in-Studio smoke test needs the window (Step 8) — nothing else in this package does.

## 7. Dependency note

The harness uses `lupa` (embedded Lua 5.1 in Python, installed with `pip install lupa` on this machine — the repo's forge tooling already relies on Python + pytest). No Roblox toolchain is required for any check above.
