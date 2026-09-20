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
| 4. build Gianluca V2.5 in an isolated Studio staging area | Step 7 (`ServerStorage.NpcStaging`, never `GameWorld`) | Edit-mode write, gated by STOP 1(c) |
| 5. apply real Roblox materials/lighting | Step 7 (material/colour pass from the recipe palette; lighting checked in the staging scene) | Edit |
| 6. test procedural idle/talk animations | Step 8 (driver installed inert, staged body tagged; `Veteran` pack, `warMemory` reaction) | Play |
| 7. inspect at gameplay camera distance · 8. inspect portrait close-up | Step 9 (captures at ~40 / ~20 studs; MerchantDialog portrait) | Play |
| 9. measure performance | Step 10 (NpcBudget review vs Tier 3 caps; frame cost with the driver on) | Play |
| 10. compare live old Gianluca vs staged V2.5 | Step 9 side-by-side captures | Play |
| 11. **STOP for approval before replacing the live NPC** | **STOP 3** (prototype review). The live swap itself stays behind STOP 5 (plan) and STOP 6 (result) with one-call rollback; **never automatic**. | gate |

Standing rules through the window: do not replace Gianluca automatically; do not touch Elder Tung; do not begin the global rollout.

## Disk-side prerequisites the window depends on (NOT started — frozen; need an explicit go)

Step 4 cannot assemble V2.5 with the kit as it stands: `NpcForge` today builds the Step 0 voxel body + blockout accessories. Before the window, or else inside it, the kit needs:

1. `NpcRigSpec`: `BodyTypes.p2` from the study's P2 numbers, plus the D-22 override resolver (height, head scale, shoulder width, torso mass, limb thickness, leg length; posture = the existing `restPose`).
2. `NpcLibrary`: `kind = "shell"` entries with a `slot` bone, and the V2.5 pieces (hair styles, beard/moustache, age lines, hood down, shoulder plate, clasp, sleeve patch, belt bell, four-part spear) — bespoke ones flagged.
3. `NpcForge.AssembleHuman`: take each bone's MeshPart from the import root by node name (`<recipe>__<piece>`), weld the rest by their `Bone`, grip the spear at `RightGripAttachment` with the planted offset; sizes/pivots from the profile, never from mesh bounds.
4. `NpcFaceConfig`: the eight states as C0 offsets/scales on the seven driven parts. Brow lift/tilt, eye height scale and iris scale map directly; the mouth stays one part — smile = the curved mesh, worried/angry = the same mesh rotated 180°, shocked = scaled to a short tall blob, neutral/serious = flattened by scale. Lids are geometry on the Head mesh; the lash line rides with the Brow part (no new Motor6D).
5. `NpcMotionConfig`: pack `Veteran` and the `warMemory` reaction keyed by dialogue tags through the existing `NpcLife` dialogue hook (numbers in the study §4).
6. `NpcCharacters/Gianluca.lua`: `tier = 3`, `face = "serious"`, V2.5 hair/beard/outfit/prop ids, the veteran `restPose`; root name, prompt and dialogue contracts unchanged.
7. Harness tests for the assembly (slot coverage, welds, budget vs Tier 3, portrait line) and a lint pass.

## Order of events

NPC-01 stays frozen → Duck + Pete finish → delta sync → combined QA → the owner opens the dedicated NPC-01 Studio window (and says whether the prerequisites above are done before it or inside it) → the sequence above → STOP 3.
