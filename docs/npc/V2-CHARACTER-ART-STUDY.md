# NPC-01 — V2 Character Art Study (visual study only)

**Lane:** NPC-01 · **Branch:** `npc-01-character-overhaul` · 2026-09-19
**Status:** study for approval. **Nothing is frozen.** No Studio access, no live NPC, no change to the approved Step 0 framework (SR-Rig, Motor6D, NpcForge, NpcLife, LOD, face-state interface, animation axes, budgets, recipes, attachments). Nothing pushed or merged.

**Why:** the Step 0 prototype read as *a generic low-poly Roblox NPC wearing accessories*. This study keeps the system and changes the skin: the rig becomes an underlying skeleton, and every visible mesh on a Tier 2/3 character is an authored low-poly shell. D-11 (v1.1 proportions) is **not** applied — see the F sheet for why.

All renders are harness renders of the study kit (`tools/npc_kit/v2/`), not Studio captures.

---

## 1. The sheets (`docs/npc/previews/v2/`)

| Brief item | Sheet | What it shows |
|---|---|---|
| A · base skeleton | [v2-A-skeleton.png](previews/v2/v2-A-skeleton.png) | the 15-joint SR-Rig (R15 names, Motor6D pivots) under the P2 body, posed and unposed, with the Tier 1 kit ghosted |
| A · proportions | [v2-A2-proportion-studies.png](previews/v2/v2-A2-proportion-studies.png) | v1 reference and three V2 candidates P1 / P2 / P3 on the same skeleton |
| B · Tier 1 shell | [v2-B-tier1-villager.png](previews/v2/v2-B-tier1-villager.png) | Valley Villager: the common body kit is allowed to show |
| C · Tier 2 shell | [v2-C-tier2-merchant.png](previews/v2/v2-C-tier2-merchant.png) | Valley Merchant: reusable shells hide the base body, zero bespoke meshes |
| D · Tier 3 shell | [v2-D-tier3-gianluca.png](previews/v2/v2-D-tier3-gianluca.png) | Gianluca V2: reusable kit + bespoke meshes + asymmetry |
| B/C/D together | [v2-BCD-tier-ladder.png](previews/v2/v2-BCD-tier-ladder.png) | skeleton → T1 → T2 → T3 in one row, with front silhouettes |
| E · Gianluca V2 | [v2-E-gianluca-turnaround.png](previews/v2/v2-E-gianluca-turnaround.png) | front / back / left ¾ / right ¾, three solid silhouettes, ~40- and ~20-stud gameplay views |
| E · head | [v2-E2-gianluca-head.png](previews/v2/v2-E2-gianluca-head.png) | head close-up ×3 and the expression strip (neutral / happy / worried / surprised / angry) |
| F · comparison | [v2-F-gianluca-v1-v11-v2.png](previews/v2/v2-F-gianluca-v1-v11-v2.png) | current v1 · proposed v1.1 · V2 — same camera, same 60 px/stud; v1 and v1.1 are the real NpcForge builds |
| G · ownership | [v2-G-piece-ownership.png](previews/v2/v2-G-piece-ownership.png) | shared skeleton (grey) · reusable mesh (blue) · character-specific mesh (orange), with the piece list |
| H · budgets | [v2-H-budgets.png](previews/v2/v2-H-budgets.png) | parts / welds / Motor6D / bespoke / triangles against the NpcBudget tier caps |
| contact sheet | [v2-study-sheet.png](previews/v2/v2-study-sheet.png) | ladder + Gianluca turnaround + comparison |
| data | `v2-summary.json` | profiles, budgets, piece lists, GLB export sizes |

Regenerate with `cd tools && python -m npc_kit.v2.study` (≈10 s). The shells also export as an Import 3D batch to `tools/out/npc_v2_study/<character>.glb` through the forge's own `write_glb` (one node per piece) — the same door the brainrot pipeline uses.

---

## 2. Keep the system, change the skin — how V2 sits on the approved framework

| Approved (unchanged) | V2 |
|---|---|
| SR-Rig skeleton: 15 parts, 15 Motor6Ds, R15 names, `C0`/`C1` from pivots, HRP anchored at y = 3.0 | same skeleton; a **BodyProfile** is just a different table of sizes/pivots (candidate `P2`) |
| NpcForge builds bones from `NpcRigSpec` + library entries | a bone's visible mesh comes from the **slot piece** chosen by the recipe: kit block (Tier 1) or shell (sleeve, bracer, boot shaft, coat body…). The shell **is** the MeshPart named `RightUpperArm` — no hidden limb, no extra part, no extra weld, same Motor6D. |
| Overlays welded to bones (`Bone` attribute) | unchanged for hair, hat, scarf, mantle, coat tails, belt, pouch, collar, props |
| Face: 7 parts on `FaceJoint` Motor6Ds driven by `NpcFaceConfig`; `NpcFace` attribute is the public API | same seven part names (`EyeL/R`, `PupilL/R`, `BrowL/R`, `Mouth`) and roles; only the shapes change (egg eyes with a fixed highlight, tapered brows, small curved mouth, no nose) |
| NpcLife, motion packs, LOD, prompts, dialogue hooks | untouched — shells move because their bones move |
| NpcBudget tiers | untouched; V2 characters are measured against the real `NpcBudget.Limits.human` caps (the study reads them through the harness) |

So the recipe shape the brief asked for — **BodyProfile + OutfitShell + Hair + Face + Props** — maps onto the existing recipe with one addition: a `shells` table (bone → library shell id + params) next to `hair` / `hat` / `overlays` / `props`. Nothing else in the data architecture moves.

---

## 3. Proportions — studies, not a decision

| | v1 (Step 0) | P1 | **P2 (recommended)** | P3 |
|---|---|---|---|---|
| height | 5.23 | 5.37 | **5.44** | 5.35 |
| heads tall | 3.4 | 3.35 | **3.16** | 2.74 |
| head | 1.50 × 1.55 × 1.35 | 1.60 | **1.72 × 1.72 × 1.58** | 1.95 |
| lower leg | 0.90 | 0.85 | **0.80** | 0.68 |
| forearm / upper arm width | 0.70 / 0.75 | 0.78 / 0.78 | **0.82 / 0.80** (forearm thicker) | 0.88 / 0.85 |
| hand width | 0.75 | 0.84 | **0.90** | 0.98 |
| boot length | 1.10 | 1.18 | **1.20** | 1.25 |
| shoulder span (kit) | 3.65 | 3.81 | **3.80** (+ shells: mantle 5.0, sleeves 4.2) | 3.95 |
| head centre above HRP | 1.45 | 1.57 | **1.58** | 1.37 |

Notes: V2 adds a short visible neck (0.16) so scarves, collars and the chin line read; v1 sat the head inside the torso. Character-dependent shoulder width comes from the shells (mantle/coat/sleeves), not from the skeleton. The portrait line moves from +1.45 to +1.58 above the HRP — MerchantDialog's frame (`HRP + 1.0`, span 4.6) still holds the head and hat; the number would be re-checked in the Studio window. P3 crowds the hat/hair slot; P1 is safe but barely different from v1.

---

## 4. The V2 kit (`tools/npc_kit/v2/kit.py`)

**Face** (reusable): eyes 26 % of head width, 30 % of head height, egg outline, inner gap ≈ 0.7 eye; iris 56 % of the eye with a fixed highlight; tapered brows angled by expression; mouth 19 % of head width, curved by expression; six expressions in the study. Reads at the ~20-stud pixel scale (E2 strip).

**Hair** (reusable styles): `crop` (Tier 1 dome), `tousled` (swept crown, 5 fringe shards, side locks, nape tufts — Gianluca), `side` (parted, under a cap — merchant), `bob` (crown + jaw-length back mass). The hairline sits at the brow top (kit rule kept: nothing crosses the brows — now a test).

**Shells** (reusable, parameterised by the profile): coat body (shoulders 1.16× the torso), shirt, tunic hem block, sleeve (`puff`, `rolled`), bracer (`flare`), mitten hands with a thumb, boot shaft + oversized boot with heel (`cuff`, `oversize`), shoes, coat tails (back + split front), apron (bib + skirt), mantle (`reach`, `drop`, `front_point`, `collar`), scarf with knot and tail (`tail_side`), neckerchief, belt + buckle, pouch (`side`), satchel with a cross strap (`side`), flat cap, rope belt, planted cane + bell, coin sack.

**Character-specific** (count against `bespokeMeshes`): Gianluca's pinned ranger hat (crown + brim), its band + feather, the empty Chim collar.

**Asymmetry vocabulary used:** rolled left sleeve · scarf tail on the left · pouch on the left hip · Chim collar on the right · cane in the right hand · brim pinned up on the left, feather on the right · hat cocked · head turned and tilted · weight on one leg (merchant: satchel on one hip, strap over the opposite shoulder, one wrist cuff, one hand raised).

---

## 5. Gianluca V2 — design notes

Silhouette in solid black (E, bottom row): the cocked hat with the feather spike, the mantle's shoulder line, the scarf tail, the split coat tails over big cuffed boots, the planted cane — recognisable front, ¾ and back. The face reads as *his* (worried brows, small frown) at 20 studs; the hat, scarf and cane read at 40.

Gameplay identity untouched: `StupidGianluca` root name, `TalkPrompt`, GianlucaClient / MerchantDialog contracts, quest, dialogue — the study module never touches `NpcCharacters/Gianluca.lua`.

What I would still push in a mesh pass (not done here): a stitched seam on the boot cuff, a strap for the pouch, a buckle on the mantle, a proper tunic V under the scarf, and a second `tousled` variant so villagers do not share his exact hair.

---

## 6. Budgets (H)

| character | tier | parts | welds | Motor6D | bespoke | triangles | verdict |
|---|---|---|---|---|---|---|---|
| Gianluca v1 (Step 0) | 2 | 41 | 17 | 22 | 0 (collar was a Part) | 2,860 body + primitives | PASS with blockout allowance |
| Gianluca v1.1 (D-11) | 2 | 41 | 17 | 22 | 0 | 2,948 body + primitives | PASS with blockout allowance |
| Tier 1 Villager | 1 | 25 | 2 | 22 | 0 | 1,608 | PASS (caps 30 / 8 / 22 / 0 / 5,000) |
| Tier 2 Merchant | 2 | 34 | 11 | 22 | 0 | 2,572 | PASS (38 / 14 / 22 / 3 / 9,000) |
| Tier 3 Gianluca V2 | 3 | 37 | 14 | 22 | 3 | 3,468 | PASS (50 / 24 / 27 / 8 / 16,000) |
| Gianluca V2 vs Tier 2 caps | 2 | 37 | 14 | 22 | 3 | 3,468 | **fits** — 1 part and 0 welds of slack |

V2 is cheaper in triangles than the v1 voxel body because shells are authored lofts (8–14 sides) rather than greedy-merged 0.05-stud lattices, and it needs no blockout allowance (every piece is a MeshPart). Parts = pieces + HumanoidRootPart + collider; welds = welded pieces + collider; Motor6D = 15 rig + 7 face.

---

## 7. Brainrot story NPCs (principle only — not rendered)

Same rule: the veteran layer must **alter the silhouette and the read** (worn harness, asymmetric armour, a splint and bandages on one side, an altered stance, medals, a story expression) while the base Brainrot stays recognisable. A V2 veteran render needs the real Bombardiro Crocodilo bounds from E-13; on the stand-in it would only be another placeholder, so it is deferred to after the inspection window.

---

## 8. What changes in the framework if V2 is approved (not done in this pass)

1. `NpcRigSpec`: add the approved BodyProfile as a `BodyTypes` entry (P2 numbers, neck gap, new pivots); keep `standard` for the transition.
2. `NpcLibrary`: `kind = "shell"` entries with a `slot` (bone) and the shell parameters; hair styles; the Gianluca-specific entries flagged `bespoke = true`.
3. `NpcForge.AssembleHuman`: take the bone's MeshPart from the recipe's shell when present (size/pivot from the profile, mesh from the import), otherwise from the body kit. No other assembly change.
4. `NpcFaceConfig`: new part shapes and expression tables from `kit.EXPRESSIONS` (same seven parts, same API).
5. Forge: the NPC profile gains a *low-poly* path (`lowpoly.py` → `write_glb`) beside the voxel path; the Import 3D batch is one GLB per character with one node per piece.
6. Gianluca recipe: `shells` table + the V2 hair/hat/scarf/mantle ids; name, role, prompt and dialogue contracts untouched.
7. Tests: the 10 study tests move under the kit tests; the brow-line, slot-coverage and tier-envelope checks stay as gates.

---

## 9. Decisions for the owner (nothing applied until you say so)

- **D-11 (v1.1 proportions): recommend superseding** with a V2 BodyProfile. Candidate **P2** recommended; P1 if you want to stay closer to v1; P3 if you want a rounder cast.
- **D-12 — face language:** approve the V2 egg-eye / tapered-brow / small-mouth language as the standard (same seven driven parts).
- **D-13 — shell-as-slot architecture:** a shell replaces the bone's visible MeshPart (no hidden limb). Alternative (hidden kit limb + welded shell) costs +1 part and +1 weld per shell and would push Gianluca V2 out of Tier 2.
- **D-14 — Gianluca's envelope:** he fits Tier 2 with zero weld slack; lift him to the Tier 3 envelope (story NPC) or keep Tier 2 and drop one welded piece (buckle merged into the belt colour) for headroom.
- **D-15 — Gianluca V2 as the human style test:** approve the direction (hat, scarf, mantle, coat, boots, cane) so the mesh pass and the Lua changes in §8 can be planned.

---

## 10. Files in this pass

New: `tools/npc_kit/v2/{__init__,lowpoly,profiles,kit,characters,render,study}.py`, `tools/npc_kit/tests/test_v2_study.py` (10 tests), `docs/npc/previews/v2/*` (12 sheets + `v2-summary.json`), this document.
Modified: `tools/npc_kit/preview.py` (optional depth-buffer return), `tools/README.md`, `game-src/npc-kit/README.md` (pointer only).
Untouched: every Lua module under `game-src/npc-kit/`, `tools/brainrot_forge/`, `game-src/place-full/`, all live NPCs, quests, prompts, worlds.

Validation: `python -m npc_kit.lint` OK · `python -m pytest npc_kit/tests -q` → **52 passed** (42 Step 0 + 10 study) · `python -m npc_kit.v2.study` exit 0.
