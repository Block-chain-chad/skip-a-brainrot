# H — Phase 3 Execution Plan (exact order, with STOP gates)

**Lane:** NPC-01 · Phase 2.5 · 2026-09-19. Executes only after the NPC-01 Studio window is granted. Every **STOP** is a point where NPC-01 halts, reports, and waits for the owner's explicit approval. Nothing live changes before STOP 6.

Legend: **[D]** disk-side (this branch, no Studio) · **[R]** Studio read-only · **[P]** Play mode, nonpersistent · **[W]** Edit-mode write (needs the gate that names it).

## Step 0 — Before the window [D]  *(can start now, on approval of this package)*
- 0.1 Author the data modules on disk: `NpcRigSpec`, `NpcFaceConfig`, `NpcLibrary` (Wave 1 entries, meshes as `forge` refs), `NpcFamilies`, `NpcWorldThemes`, `NpcMotionConfig` (Villager + Background + Creature/Veteran), `NpcLodProfiles`, `NpcCharacters/Gianluca`, `NpcCharacters/VeteranBombardiro`.
- 0.2 Author `NpcMotion`, `NpcLifeClient`, `NpcForge`, `NpcBudget` on disk under `game-src/place-full/…` on this branch.
- 0.3 Forge tooling deltas (doc E8); design the `standard` body lattice; bake + export `npc_body_standard_batch.glb`; render previews (`render.py`) for a look check **without Studio**.
- 0.4 Disk-side tests: `NpcMotion` unit tests (Python-side or a Luau harness) for the semantic-axis mapping and blend rules; a static lint of every recipe against the library.
- **STOP 0 — owner reviews the body previews and the module sources. Approval to enter the Studio window with them.**

## Step 1 — Inspection sweep [R]
- 1.1 `get_studio_state`; confirm Edit mode; confirm no other lane is mid-operation (ask before proceeding if unsure).
- 1.2 Run the Batch 1 sweep (`INSPECTION-RUNBOOK.md` §6). Save the print.

## Step 2 — Validate Gianluca structure [R]  (E-2)
- 2.1 `inspect_instance` on `Workspace.GameWorld.StupidGianluca`; record HRP CFrame, part list, which parts are props/scene, `TalkPrompt` properties, attributes.
- 2.2 Decide (with the recorded facts) how `contracts.moveChildrenTo` applies.

## Step 3 — Validate Bombardiro structure [R]  (E-13)
- 3.1 `inspect_instance` on the template; record MeshPart names/bounds, joints, face part, `HeightScale`, emitters.
- 3.2 Run the D8 safety check on paper → **Path A / Path B**.

## Step 4 — Validate shopkeeper contracts [R]  (E-3, E-4, E-5, E-17)
- 4.1 Counter heights, keeper HD ids, `NPC` child presence, tundra/Gardens pairing.

## Step 5 — Validate portrait framing [R → P]  (E-18)
- 5.1 Read-only: head-above-HRP and HRP size on every keeper.
- 5.2 Play mode: the 16-block proxy in a ViewportFrame with the portrait's numbers (nonpersistent). Capture.

## Step 6 — Remaining read-only + Play-mode checks [R / P]
- 6.1 E-1, E-6, E-7, E-8, E-9, E-16 (from the sweep); Batch 3 captures.
- 6.2 Play: E-10 (Chim), E-11 (KeyframeSequence registration on an `AnimationController` rig). Stop Play.
- **STOP 1 — Inspection findings report (`docs/npc/studio/INSPECTION-<date>.md`). Owner approves: (a) the Gianluca swap plan facts, (b) Veteran Path A or B, (c) the Edit-mode writes needed for Step 7 (import + staging folders + kit modules). Nothing built until this approval.**

## Step 7 — Build the prototype in the sandbox [W, gated by STOP 1(c)]
- 7.1 `File › Import 3D` of the body GLB (user-driven) → parked under `workspace.AuxScene` — the E-15 write, now approved for real use.
- 7.2 Create `ServerStorage.NpcStaging.{Valley,Gardens,Trading}`, `ServerStorage.NpcForge`, `ServerStorage.NpcBudget`, `ReplicatedStorage.Modules.NpcKit.*` from the disk sources (`multi_edit`/script push through the existing studio-bridge).
- 7.3 `NpcForge.Build("Gianluca")` → `ServerStorage.NpcStaging.Valley.StupidGianluca` (no prompt). `NpcBudget.review` must PASS.
- 7.4 `NpcForge.Build("VeteranBombardiro")` (Path A) or wait for the World 3 lane's species (Path B) → `NpcStaging.Gardens`.
- 7.5 Clean `AuxScene` of the import residue (our own objects only).
- **STOP 2 — Owner sees the staged models (captures, budget reports). Approval to install the runtime driver.**

## Step 8 — Install the driver, inert [W, gated by STOP 2]
- 8.1 Push `StarterPlayer.StarterPlayerScripts.NpcLifeClient` and the `NpcKit` modules. The driver only touches `NpcBody`-tagged models; **no live model carries the tag**, so the live game is unaffected.
- 8.2 Edit-mode sanity: `NpcLifeClient` source present, disabled = false, no errors on Play with zero tagged bodies.

## Step 9 — Compare against the old NPC [P]
- 9.1 Play mode: clone the staged Gianluca next to the live one (Play-only), tag it, watch idle/greet/talk against the live prompt of the *staged* clone (a temporary `TalkPrompt` copy on the clone, Play-only) — captures at 20/60 studs, front/¾, portrait open.
- 9.2 Same for the Veteran at a rubble spot in the Gardens (Play-only).
- 9.3 Note every visual delta against specs A/D and the identity locks.

## Step 10 — Performance check [P]
- 10.1 Play mode, 12 tagged clones of the staged Gianluca in the valley lodge + the normal plot load; MicroProfiler / `Stats` frame time vs the same scene with 0 clones; confirm 0 server per-frame cost (server Heartbeat unchanged) and the animated-set cap engages at 13+.
- 10.2 Record numbers in the findings doc. Stop Play; delete nothing (nothing persisted).
- **STOP 3 — Prototype review: the human standard (Gianluca) and, if built, the brainrot standard (Veteran). Owner approves the standards, requests changes, or rejects. Iterate 7.3–10 on request.**

## Step 11 — Merchant contract dry run [R / P]  *(only if the owner wants the merchant batch queued)*
- 11.1 Build Marco (Wave 1 recipe) into staging; Play-mode side-by-side behind the live `SellStall` counter (E-17 answer applied).
- **STOP 4 — Owner approves the merchant treatment (or defers the batch).**

## Step 12 — Live Gianluca replacement plan [D]
- 12.1 Write `docs/npc/studio/SWAP-GIANLUCA.md`: the exact `NpcForge.SwapLive` call, the backup path, the verification list (prompt binds, dialogue opens, portrait frames, tutorial `talked` flag still fires, `NpcFocusClient` outlines the person, old scripts print no warnings), the rollback (restore from `AuditBackups`).
- **STOP 5 — Owner approves the live swap plan.**

## Step 13 — Live swap [W, gated by STOP 5]
- 13.1 Backup live model → `ServerStorage.AuditBackups.NPC01_StupidGianluca_<date>`.
- 13.2 `NpcForge.SwapLive(staged, live)`; verify the list in 12.1 in Play mode; capture.
- 13.3 Mirror the touched scripts/models to this branch; commit.
- **STOP 6 — Owner reviews the live result. Approve to keep, or `Rollback` (one call) and report.**

## Step 14 — Report and next batch [D]
- 14.1 Findings + captures + budget numbers → `docs/npc/`. Propose the next batch (merchants Wave 1 / Veteran placement handoff to the World 3 lane / Cove Wave 3 once TW-01 answers).

## Rules that hold through every step
- No Elder Tung work. No quest, prompt, `MerchantDialog`, World 1/2/3 or Trading World live edits except the single approved swap in Step 13.
- Every Edit-mode write is named in a gate before it happens; the runbook's read-only scope applies to Steps 1–6.
- Nothing pushed or merged; everything committed on `npc-01-character-overhaul`.
- Any unexpected state in Studio (another lane mid-edit, a Play session running, a dirty `AuxScene`) → stop and ask.
