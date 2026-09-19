# NPC-01 — Phase 2.5 Implementation Prep

**Lane:** NPC-01 · **Branch:** `npc-01-character-overhaul` · 2026-09-19
**Status:** disk-side documentation/spec only. **No Studio control, no live replacement, Bombardiro template untouched, Elder Tung locked, no quest/prompt/MerchantDialog/world edits, nothing pushed or merged.**
Previous checkpoints: [Phase 1 report](NPC-01-GLOBAL-CHARACTER-REPORT.md) · [Phase 2 package](PHASE2-DESIGN-PACKAGE.md) · [Inspection runbook](studio/INSPECTION-RUNBOOK.md) (approved scope recorded).

## The package

| # | Doc | What it fixes for Phase 3 |
|---|---|---|
| 1 | [A — Gianluca build manifest](phase2.5/A-gianluca-build-manifest.md) | the exact hierarchy, every part with size/offset, all 22 Motor6D `C0/C1`, attachments, materials, face data, collision/query/touch/anchoring rules, LOD, prompt + portrait compatibility; every component classified KIT / GIANLUCA / OPTIONAL; 34 parts, ≈ 3.7k tris |
| 2 | [B — Human modular kit](phase2.5/B-human-modular-kit.md) | the starter library in two waves (34 + 37 meshes) that makes the first ten NPCs intentionally different; slots, grips, kit rules; a distinctness matrix |
| 3 | [C — Procedural animation package](phase2.5/C-procedural-animation-package.md) | semantic joint axes with the exact CFrame mapping, layer kinds, the Villager idle (+ Gianluca overrides), talking layers, the `ringBell` signature, blend/stop rules, dialogue hooks, the authored-track hook. **Supersedes Phase 2 A §A9's sign convention** |
| 4 | [D — Brainrot Veteran build manifest](phase2.5/D-brainrot-veteran-build-manifest.md) | BASE (untouched clone) vs VETERAN LAYER (≤ 8 parts, ≤ 600 tris, 0 emitters); attachment-by-recipe; wear/scorch rules; stance; the Path B fallback; what the Deserter/Ancient reuse — all conditional on E-13 |
| 5 | [E — NpcForge config architecture](phase2.5/E-npcforge-config-architecture.md) | the data modules, Luau type definitions, three example recipes (Gianluca, a 10-line Tier 1 villager, the Veteran), the `Build` algorithm, the runtime contract (attributes only), `NpcBudget` rows, extension rules, tooling deltas |
| 6 | [F — Tier performance budgets](phase2.5/F-tier-performance-budgets.md) | per-model and runtime budgets for Tiers 1–3 (parts, triangles, distances, frequencies, 12-animated cap, offscreen), per-world envelopes, the ten "many NPCs" rules |
| 7 | [G — Trading World character matrix](phase2.5/G-trading-world-character-matrix.md) | the eight provisional roles × tier / silhouette / family / face / prop / profile / reusable assets; no placement |
| 8 | [H — Phase 3 execution plan](phase2.5/H-phase3-execution-plan.md) | 14 steps, STOP 0–6, every Edit-mode write named in a gate; live swap only at Step 13 behind STOP 5/6 |

## Decisions still needed from you (D-1 … D-10)

| # | Decision | Recommendation | Where it lands |
|---|---|---|---|
| **D-1** | **Collider**: should talking NPCs (Tier 2/3) block the player with an invisible 2.2×5×1.4 collider, or stay walk-through like today's rigs (`[studio]` whether they collide now)? | collider on Tier 2/3, none on Tier 1 (background NPCs are often behind counters) | A §A2/A9, E `recipe.collider` |
| **D-2** | **Gianluca's crates/stall**: if E-2 shows they live inside `StupidGianluca`, move them to a sibling `GianlucaCamp` model (portrait/outline then frame the person only) or leave them inside (today's behaviour) | move them | A §A12, E `contracts.moveChildrenTo` |
| **D-3** | **Story-beat faces**: allow one attribute write (`NpcFace`) in quest clients (e.g. `GianlucaClient` on `Note == "key"` → `excited`) — a quest-client edit, so it is yours to allow | allow in Phase 3, one line, after the swap is stable | A §A5, C §C9 |
| **D-4** | **Bell sound**: reuse an existing short `SoundKit` cue at ≤ 0.15 volume, or silent (no new audio; audio is account-locked like animations) | silent for the prototype; pick a cue in the window if one is short enough | A §A13 |
| **D-5** | **Same merchants in three worlds**: keep the five people and give them world cuts (winter / patched) via `NpcWorldThemes`, or make them different people per world | same people, world cuts | B, E `WorldTheme.replaceOverlay` |
| **D-6** | **Mouth**: 1-part bar (no smile/frown curvature; brows carry emotion) or 3-part mouth (+2 parts everywhere) | 1-part now; revisit after the Gianluca review | C3 (Phase 2), A §A5 |
| **D-7** | **Driver install timing** (Step 8): install `NpcLifeClient` + `NpcKit` into the place *inert* right after the staged build, or only at the live swap | inert install at Step 8 — it lets the Play-mode comparison run against the real driver | H Step 8 |
| **D-8** | **Prompt standard for new NPCs**: talk prompts at 10 studs / hold 0.3 (existing prompts untouched) | yes | F §F2 |
| **D-9** | **Wave 2 priority** once Wave 1 ships: World 3 cast (Vespa, Ines, Ottavio + Veteran) or Cove Wave 3 (after TW-01) | World 3 first (its lane is active; TW-01 has not replied) | B, G |
| **D-10** | **Veteran fallback**: if E-13 fails the safety check, NPC-01 asks the World 3 lane for a forge-baked species (Path B) — or you pick one | let the World 3 lane pick from the E-14 list | D §D8 |

None of D-1…D-10 blocks Step 0 (disk-side authoring) except D-1 and D-6, which change part counts; both default to the recommendation until you say otherwise.

## What Step 0 would produce next (on your go — still no Studio)

The data modules, `NpcMotion`, `NpcLifeClient`, `NpcForge`, `NpcBudget` as sources on this branch under `game-src/place-full/…`, the forge `npc` profile and the `standard` body lattice with rendered previews — everything Step 7 pushes into Studio, reviewable on disk first (STOP 0).
