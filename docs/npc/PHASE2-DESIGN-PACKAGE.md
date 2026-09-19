# NPC-01 — Phase 2 Design Package

**Lane:** NPC-01 — global NPC character overhaul · **Branch:** `npc-01-character-overhaul` · 2026-09-19
**Status:** design package for review. **No live NPC replaced, no Studio control taken, no quest/prompt modified, Elder Tung untouched, nothing pushed or merged.**
Phase 1 report: [`NPC-01-GLOBAL-CHARACTER-REPORT.md`](NPC-01-GLOBAL-CHARACTER-REPORT.md) (approved 2026-09-19).

## Decisions recorded from the Phase 1 approval

| # | Decision | Where it lands |
|---|---|---|
| 1 | **Animation path:** procedural / Motor6D-driven joint motion for the prototypes; no uploaded AnimationIds; architecture must accept authored/uploaded clips later without rebuilding the framework | Kit C7: pose-source abstraction (`ProceduralSource` now, `TrackSource` later), packs carry optional `asset`/`sequence` fields, `USE_TRACKS` flag; the procedural layer writes `Motor6D.C0` so authored tracks (which own `Transform`) compose on top; `AnimationController` in every rig from day one |
| 2 | **Prototype order:** 1 = Gianluca (human style), 2 = World 3 Brainrot Veteran (story-brainrot standard); **Elder Tung not redesigned** — species, beard, wood/brown language, rocking chair and lore silhouette are iconic and wait for the human + brainrot standards to be reviewed | A, B; Tung appears only as "deferred" in E |
| 3 | **Studio:** no control yet; exact inspection checklist prepared, each item marked design-blocking vs implementation-blocking | E |
| 4 | **Trading World:** concise role handoff to TW-01 from the eight-role cast; no placement | D |
| 5 | Deliverables A–E before any live replacement | this package |

## The package

| Doc | Contents |
|---|---|
| [A — Gianluca Prototype Spec](phase2/A-gianluca-prototype-spec.md) | proportions, silhouette, body construction, face, hair/headwear, outfit, bell-cane prop, idle layers, `ringBell` gesture (keyframe table), colours, reusable components, part/mesh budget (33 parts, 1 bespoke mesh, ≈ 6k tris) |
| [B — World 3 Brainrot Veteran Spec](phase2/B-world3-brainrot-veteran-spec.md) | base species identity (Bombardiro Crocodilo as proposed by the World 3 lane; species-agnostic treatment), the ≤ 8-part veteran layer in priority order, armour remnants, damage/scarring rules, stance, idle, lore readability by distance, the reusable veteran kit (+ Deserter and Ancient colourways), performance budget (≤ 14 parts on a pack species, 0 emitters) |
| [C — Global NPC Base Kit](phase2/C-global-npc-base-kit.md) | SR-Rig v1 instance tree and proportions, 15 shared meshes + production routes, the 7-part cube face and expression table, hair/hat slots, 11 clothing families as colour sets + overlay slots, prop attachment system, `NpcLifeClient` driver (registry, pose sources, pack data format, scheduler, zero-edit hooks into prompts/dialogue, future track source), LOD/culling bands, build-time `NpcForge` assembler, revised budgets |
| [D — TW-01 NPC Role Handoff](phase2/D-tw01-npc-role-handoff.md) | eight roles × (purpose, tier, personality, visual direction, prop, animation personality, interaction type, dialogue/ambient); what NPC-01 needs from TW-01; what TW-01 receives; out-of-bounds list |
| [E — Studio Inspection Checklist](phase2/E-studio-inspection-checklist.md) | 18 read-only inspection items with the exact objects, unknowns, steps/snippets and a D/I/N blocking flag; screenshot list; a 75-minute ordering for the window |

## What changed since Phase 1 (so the reviewer is not surprised)

- **Face is part-built (7 cube parts), not a decal** — it needs no uploads of any kind, follows `VoxelFace`'s rules on the creatures, survives the dialogue portrait's clone filter, and is *animatable* (blink, gaze, talk, brows). The Tier caps moved accordingly: BaseParts ≤ 30 / 38 / 50.
- **Procedural motion goes through `Motor6D.C0`**, not `Transform`: the game already measured that an Animator overwrites `Transform` everywhere but `Stepped`; `C0` never conflicts and lets authored tracks layer on later.
- **Props are welded to the hand and never written per frame** (the arm carries them) — `NpcPropLife`'s per-frame server writes are not carried forward.
- **Human body meshes can ride the existing Brainrot Forge** (one MeshPart per segment role) with two small gate deltas — no Blender needed for the prototypes; a modelled-mesh pass later is a content swap.

## What is *not* in this package (deliberately)

Any Studio change; the live Gianluca swap (Phase 1 order 2b — a separate approved step after the E-2/E-17/E-18 window); the merchant batch; any Elder Tung work; TW placement; the retirement of `NpcRigLife`/`NpcBodyLife`/`NpcPropLife`/`NpcIdle` (Phase 5); uploads of animations, audio or anything else from the Studio login account.

## Gates to open Phase 3 (build)

1. Your review of A, B, C (the standards) — with any changes to proportions, face rule, or budgets.
2. TW-01's answers to D §D2.
3. An NPC-01 Studio window for E (≈ 75 min; items E-2, E-13, E-17, E-18 first).
4. Then: the forge `npc` profile + `NpcForge.AssembleHuman`, the `standard` body meshes, `NpcLifeClient` v1, Gianluca in `ServerStorage.NpcStaging.Valley` — still not live until you say so.
