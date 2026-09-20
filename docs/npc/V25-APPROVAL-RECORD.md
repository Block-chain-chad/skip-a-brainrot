# NPC-01 — V2.5 Visual Approval Record (locked decisions + Studio-window sequence)

**Lane:** NPC-01 · **Branch:** `npc-01-character-overhaul` · approved 2026-09-19 at study commit `eb0463f`
**State:** the visual study is **FROZEN** at V2.5. No further offline Gianluca versions, no additional NPCs, no Studio until the dedicated post-delta-sync NPC-01 window is explicitly opened. Nothing pushed or merged.

## Locked decisions

| # | Decision | Locked value |
|---|---|---|
| D-16 | Gianluca V2.5 | **APPROVED** as the current hero-character direction. Preserve: old-veteran identity · swept-back gray hair · short gray beard · mature/heavy face · worn layered ranger/veteran clothing · asymmetric silhouette · cracked/aged shoulder armour remnant · scarf · pouch/belt details · reinforced boots · veteran posture · shortened war spear used as a staff. He fought alongside Elder Tung and visually carries that history. |
| D-17 | Global face language | **APPROVED WITH STRUCTURE.** V2.5 face system is the global language with at least three families that clearly share one Skip Rocks style: **YOUNG** (more open eyes, softer brows, cleaner face) · **MATURE** (more controlled eye shape, stronger brows, slightly more angular cues) · **VETERAN / OLD** (heavier lids, age lines, mature brows, optional beard/moustache/sideburn systems). No NPC shares Gianluca's exact face. |
| D-18 | Elder Tung war clue | **APPROVED:** the scarf clasp / small war-era insignia. Understated — a new player may notice it without understanding it; later lore recontextualises it. **No moon imagery.** |
| D-19 | Prop | **APPROVED:** the shortened war spear / spear-staff. Old weapon first, walking support second. Never a generic elderly cane. |
| D-20 | Tier | **Gianluca = Tier 3** (story character via his Elder Tung history); use the Tier 3 budget. Not every named NPC is Tier 3. |
| D-21 | Hair / beard | **APPROVED:** swept-back gray hair, short gray beard, moustache/sideburn integration where visually appropriate; silhouette must stay strong at gameplay distance. |
| D-22 | BodyProfile | **P2 is the DEFAULT human BodyProfile** — a starting profile, not a mandatory identical body. NpcForge must support character-level proportion overrides: height, head scale, shoulder width, torso mass, limb thickness, leg length, posture. One rig system, not one body shape. |

**Art-direction rule (locked):** SHARED TECHNICAL SKELETON + CHARACTER-SPECIFIC VISIBLE SILHOUETTE. Tier 1 mostly reusable assets · Tier 2 reusable assets + a stronger character shell · Tier 3 bespoke story silhouette on the same technical system. Never regress toward "default Roblox body + accessories".

## What is frozen where

- Visual study: `docs/npc/V25-CHARACTER-ART-STUDY.md` + `docs/npc/previews/v25/` (commit `eb0463f`). Study kit: `tools/npc_kit/v2/` (kit25 / characters25 / study25). Import 3D batches regenerate to `tools/out/npc_v25_study/*.glb` (41 nodes for Gianluca).
- Approved framework: every Lua module under `game-src/npc-kit/` is unchanged since Step 0 (`155c85b`); `game-src/place-full/` mirror untouched; live Gianluca, Elder Tung, World 3, Trading World untouched.
- Earlier approvals still stand: Phase 1/2/2.5 decisions D-1…D-10, the inspection runbook scope (`docs/npc/studio/INSPECTION-RUNBOOK.md`: read-only Edit-mode checks, E-11/E-18 proxy Play-mode only, **E-15 not approved**, no Edit-mode write/delete/import during inspection), and the Phase 3 STOP gates (`docs/npc/phase2.5/H-phase3-execution-plan.md`).

## The Studio-window sequence (owner's order, mapped onto the Phase 3 plan)

| Owner's step | Phase 3 mapping | Mode |
|---|---|---|
| 1. run the approved read-only inspection checklist | Steps 1–6 (Batches 1–4 of the runbook) | read-only Edit / nonpersistent Play |
| 2. verify Gianluca's live contracts | Step 2 (E-2: `GameWorld.StupidGianluca › HumanoidRootPart › TalkPrompt`, GianlucaClient, scenery) | read-only |
| 3. verify portrait/dialogue framing | Step 5 (E-18: MerchantDialog `HRP + 0.5×HRP.Size.Y`, span 4.6, fov 26 — V2.5 head centre is +1.58 above the HRP vs v1's +1.45) | read-only + Play proxy |
| — | **STOP 1** — findings report; owner approves the Edit-mode writes for the staging build (import + staging folders + kit modules). The V2.5 shells are Import 3D meshes, so this approval must now cover the GLB import that E-15 excluded from the inspection scope. | gate |
| 4. build Gianluca V2.5 in an isolated Studio staging area | Step 7 (`ServerStorage.NpcStaging`, never `GameWorld`): File › Import 3D of `Gianluca_V25.glb` (41 nodes) → install the kit modules → `NpcForge.Build("Gianluca", { importRoot = <the import> })` | Edit-mode write, gated by STOP 1(c) |
| 5. apply real Roblox materials/lighting | Step 7 (material/colour pass from the recipe palette; lighting checked in the staging scene) | Edit |
| 6. test procedural idle/talk animations | Step 8 (driver installed inert, staged body tagged; `Veteran` pack, `warMemory` reaction) | Play |
| 7. inspect at gameplay camera distance · 8. inspect portrait close-up | Step 9 (captures at ~40 / ~20 studs; MerchantDialog portrait) | Play |
| 9. measure performance | Step 10 (NpcBudget review vs Tier 3 caps; frame cost with the driver on) | Play |
| 10. compare live old Gianluca vs staged V2.5 | Step 9 side-by-side captures | Play |
| 11. **STOP for approval before replacing the live NPC** | **STOP 3** (prototype review). The live swap itself stays behind STOP 5 (plan) and STOP 6 (result) with one-call rollback; **never automatic**. | gate |

Standing rules through the window: do not replace Gianluca automatically; do not touch Elder Tung; do not begin the global rollout.

## Disk-side prerequisites the window depends on — DONE 2026-09-19 (owner: "ok to continue"), still no Studio

The kit now assembles Gianluca V2.5 from data; `python -m npc_kit.v2.forge_check` renders the NpcForge build next to the approved study at a silhouette overlap of 0.9998 / 0.9998 / 1.000 (front / ¾ / back) — [v25-K-forge-vs-study.png](previews/v25/v25-K-forge-vs-study.png). Budget from `NpcBudget`: 43 parts / 19 welds / 22 Motor6D / 7 bespoke / 4,188 tris, PASS against the Tier 3 caps. What each item became:

1. `NpcRigSpec` v2 — `Profiles.p2` (the study numbers) built bottom-up by `BuildProfile`; `BodyTypes.p2` is the default; `Resolve(bodyType, overrides)` applies `height / headScale / shoulderWidth / torsoMass / limbThickness / legLength` multipliers (posture rides on `restPose`); `JointFrames` takes per-bone mesh centres so pivots stay put under bbox-centred MeshParts; `HeadOffset(bodyType)` gives the portrait line (p2: +1.575).
2. Shell manifests instead of library entries — `NpcShells/Gianluca_V25.lua` is **generated** by `tools/npc_kit/v2/export_kit.py` from the study character: 41 pieces (bone, slot flag, bbox-centre offset in bone space, size, tris, colour, bespoke) plus the Import 3D batch `tools/out/npc_v25_kit/Gianluca_V25.glb` (41 nodes named `Gianluca_V25__<piece>`; regenerate before the window — `tools/out` is git-ignored). A test asserts the checked-in manifest equals a fresh export.
3. `NpcForge` v2 — a recipe with `shells` assembles every bone from the manifest's slot piece (the imported MeshPart by node name, or a box without an import root), welds the rest by bone, builds the mesh face on `FaceJoint`s with `RestC0 / RestSize / Side` attributes, grips the spear pieces on the right hand (`Planted`), scales meshes and offsets per bone when `bodyOverrides` change the profile, and never stacks family/theme default overlays on a shell. Attributes added: `NpcShells`, `NpcHeadOffset`, `NpcBodyOverrides`.
4. `NpcFaceConfig` v2 — `Resolve(exprId, rests)`; the eight V2.5 states in relative scales (`neutral happy worried angry suspicious tired shocked serious`); the mouth stays one part (the exported mesh is a mild smile, `rotZ = 180` makes the frown, `scaleY 2.4` the shocked O); legacy names alias on mesh faces; blink and talk scale from the rest sizes.
5. `NpcMotionConfig` v2 — pack `Veteran` (slow breathe, weight onto the staff side, `slowLook`, `shoulderRoll`, restrained `pointRestrained` / `dismissWave` / `gazeLock` when talking, greet `nodGreet`) and `reactions.warMemory` (straighten, freeze 1.5 s, tighten the grip, look away 30°, face `tired` for 3 s). `NpcLife` plays a reaction when a lane sets the root's **`NpcReaction`** attribute (consumed and cleared) — the same attribute discipline as `NpcFace`.
6. `NpcCharacters/Gianluca.lua` — V2.5: `tier = 3`, `shells = "Gianluca_V25"`, `bodyType = "p2"`, `face = "serious"`, veteran `restPose`, `pack = "Veteran"`; `rootName`, `contracts` untouched. The Step 0 recipe survives as `Gianluca_v1` for the comparison renders and regression tests.
7. Tests: 11 new (`tests/test_forge_v25.py`) — 72 pass in total; lint OK.

## Order of events

NPC-01 stays frozen (kit ready on disk) → Duck + Pete finish → delta sync → combined QA → the owner opens the dedicated NPC-01 Studio window → the sequence above → STOP 3.
