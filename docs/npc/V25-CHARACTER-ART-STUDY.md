# NPC-01 — Global NPC V2.5 Visual Study + Gianluca V2.5 (old veteran)

**Lane:** NPC-01 · **Branch:** `npc-01-character-overhaul` · 2026-09-19
**Status:** visual study for approval. Art direction is **not** frozen. No Studio access, no live NPC, no Elder Tung, no World 3, no mass production, nothing pushed or merged. The approved technical framework (SR-Rig, Motor6D skeleton, NpcForge, NpcLife, LOD, procedural animation, modular face states, data-driven recipes, attachments/props, the three tiers) is untouched — every Lua module under `game-src/npc-kit/` is byte-identical to Step 0.

Supersedes the V2 study's Gianluca (young ranger — wrong canon). The V2 kit stays in the repo only for the comparison sheet.

All renders are harness renders of the study kit (`tools/npc_kit/v2/`), not Studio captures.

---

## 1. Deliverables (`docs/npc/previews/v25/`)

| Brief item | Sheet | What it shows |
|---|---|---|
| A · skeleton underneath | [v25-A-skeleton.png](previews/v25/v25-A-skeleton.png) | the 15-joint SR-Rig in Gianluca's veteran rest pose and unposed, with the body kit ghosted |
| B · Tier 1 | [v25-B-tier1-villager.png](previews/v25/v25-B-tier1-villager.png) | background villager — polished, all reusable |
| C · Tier 2 | [v25-C-tier2-merchant.png](previews/v25/v25-C-tier2-merchant.png) | named quest NPC — unique silhouette, custom face combination, signature prop |
| D · Tier 3 | [v25-D-tier3-gianluca.png](previews/v25/v25-D-tier3-gianluca.png) | major story NPC — Gianluca V2.5 |
| B/C/D ladder | [v25-BCD-tier-ladder.png](previews/v25/v25-BCD-tier-ladder.png) | skeleton → T1 → T2 → T3 on one skeleton, with front silhouettes |
| E · turnaround | [v25-E1-gianluca-turnaround.png](previews/v25/v25-E1-gianluca-turnaround.png) | front / back / left ¾ / right ¾, three black silhouettes, ~40 and ~20-stud gameplay views |
| E · face | [v25-E2-face-expressions.png](previews/v25/v25-E2-face-expressions.png) | three close-ups + eight expressions close and at ~20-stud pixel scale |
| E · hair | [v25-E3-hair-study.png](previews/v25/v25-E3-hair-study.png) | 3 gray hair treatments × 3 facial-hair treatments, the chosen head front/back, hat-on variant |
| E · outfit | [v25-E4-outfit-layers.png](previews/v25/v25-E4-outfit-layers.png) | eight-step layer breakdown on the skeleton |
| E · war remnant | [v25-E5-war-remnant.png](previews/v25/v25-E5-war-remnant.png) | the Elder Tung clue (clasp), the armour remnant (plate), the Chim collar + bell |
| E · prop | [v25-E6-prop-study.png](previews/v25/v25-E6-prop-study.png) | spear-staff (chosen) vs broken sword vs iron-shod cane, silhouettes, spear-head close-up |
| E · posture / idle | [v25-E7-posture-beats.png](previews/v25/v25-E7-posture-beats.png) | four procedural beats: idle rest, weight shift, talking point, war reaction |
| comparison | [v25-F-v1-v2-v25.png](previews/v25/v25-F-v1-v2-v25.png) | Gianluca V1 · V2 young ranger · V2.5 old veteran, same camera |
| asset breakdown | [v25-G-piece-ownership.png](previews/v25/v25-G-piece-ownership.png) | shared kit (grey) · reusable (blue) · character-specific (orange) with the piece list |
| budgets | [v25-H-budgets.png](previews/v25/v25-H-budgets.png) | parts / welds / Motor6D / bespoke / reusable / triangles per tier vs the NpcBudget caps |
| contact sheet · data | [v25-study-sheet.png](previews/v25/v25-study-sheet.png) · `v25-summary.json` | ladder + turnaround + comparison; profiles, budgets, piece lists, beats, GLB sizes |

Regenerate with `cd tools && python -m npc_kit.v2.study25` (≈25 s). Each character also exports as an Import 3D batch (`tools/out/npc_v25_study/<id>.glb`, one node per piece) through the forge's own `write_glb`.

---

## 2. Global NPC V2.5 — the rules as built

**Construction chain (every character):** Skeleton (SR-Rig, P2 BodyProfile) → OutfitShell (slot pieces that *are* the bone's visible MeshPart: head, torso, sleeves, bracers/forearms, hands/gloves, hips, boot shafts, boots) → Hair (welded masses) → Face (seven driven parts) → Props (grip-placed) → character-specific details (welded). Tier 2/3 characters show the base body only where the design wants skin (hands, forearms) — 4 of Gianluca's 41 pieces are kit meshes, and one of them is his head.

**Tiers, as the three examples demonstrate**

| | Tier 1 — background | Tier 2 — named / quest | Tier 3 — major story |
|---|---|---|---|
| example | Valley Villager | Valley Merchant | Gianluca V2.5 |
| shells | reusable tunic, plain sleeves, simple boots | reusable shirt, rolled puff sleeves, work boots, apron, satchel, cap | reusable ranger set (coat, tunic front, tails, hood down, scarf, bracers, gloves, reinforced boots, belt/pouch) |
| hair / face | cropped hair; moderate face, happy | side-swept under a cap; moustache + happy + lids | gray swept-back + short beard + sideburns; veteran face, age lines |
| prop | a skipping stone (low cost) | coin sack (signature) | shortened war spear as a staff |
| asymmetry | — | satchel one hip, strap over the other shoulder, one cuff, one hand raised | plate left, patch left, pouch left; scarf tail, clasp, collar + bell, spear right |
| bespoke meshes | 0 | 0 | 7 (clasp, collar, plate, spear ×4) |
| posture | neutral, head turned | presenting, weight forward | forward lean, weight on the staff side, one shoulder back |

**Face language V2.5** (E2): moderate almond eyes (21 % of head width, 20–26 % of head height by age), a skin-coloured **upper eyelid built into the Head mesh** (young 16 % cover, veteran 32 %, sloping outward), a dark **lash line that belongs to the Brow part** and follows the brow's lift/tilt at 30 % — that coupling is what opens and closes the eye across states; shaped or heavy brows; iris with one fixed highlight; small mouth; nose wedge only on mature faces; age lines as one static welded piece. Eight states: neutral, happy, worried, angry, suspicious (asymmetric brows), tired, shocked, serious. Same seven driven parts and `NpcFace` API as Step 0; no default Roblox face, nothing realistic.

**Hair:** low-poly masses with crown, fringe or hairline, side masses, back mass, nape clumps, combed-back clumps, sideburns joined to facial hair; the hat-on variant shows the hair stays visible under headwear (E3).

**Animation personality:** all Tier 2/3 characters keep the procedural layer (breathe, weight shift, look, prop rest, conversation gestures). Gianluca's beats are specified in §4 and shown as stills (E7). No generic Roblox emotes.

---

## 3. Gianluca V2.5 — canon-corrected design

**Read at a glance:** OLD VETERAN + FORMER ELDER TUNG SOLDIER / ALLY + RANGER / SURVIVOR. Experienced, worn, capable; not helpless.

**Face (E2):** older proportions — eyes narrower (20 % of head height) under heavy sloped lids, bushy brows with a broken top edge sitting low over the eyes, nose wedge, under-eye forms, crow's feet, forehead crease; short gray beard with moustache and sideburns leaves the mouth readable. Default state `serious`; the war beat uses `tired`.

**Hair (E3):** gray, swept back, receding at the temples with the forehead exposed, side masses over the ears, back mass and nape clumps, combed-back clumps on the crown. Chosen over `cropped` (helmet-like at distance) and `tiedback` (younger read). Hat is optional: the old ranger hat pushed back keeps the hair visible.

**Posture (E7):** waist bend 9°, turn 4°, tilt 3° toward the staff; chin down 4°, head turned 8° and cocked 4°; right hand high on the spear (shoulder swing 40°, elbow 34°); left (plated) arm hanging back; weight on the right leg, left knee soft. Old but dangerous.

**Outfit (E4), designed as one set:** worn coat (faded olive) over a layered tunic front, frayed split coat tails below the waist, hood pushed down (collar volume, hair visible), faded rose scarf worn loose with the tail on his right, old leather belt with brass buckle, pouch on the left hip, patched left sleeve, leather bracers, worn gloves with cuffs, reinforced strapped boots slightly oversized, **one** armour remnant: a notched, dented iron shoulder plate strapped over his left shoulder. No full armour.

**Elder Tung connection (E5):** ONE subtle clue — the tarnished brass **unit clasp** that pins his scarf: a small shield with a twin-notch chevron in relief. It reads as "a worn fastener" now; later lore names the unit. No moon imagery. (Alternatives considered: a medal — too loud; the plate — reads as equipment, so it stays equipment.)

**Prop (E6):** a shortened war spear used as a walking staff — leather-wrapped grip at the hand, chipped leaf blade riding above his head, a faded cloth strip tied under the head. Reads "still carries something from the war". Rejected: broken sword (hides in the silhouette, reads relic), iron-shod cane (reads walking aid). The old **bell moves to the belt** beside the empty Chim collar, so the quest prop and the `ringBell` greet survive (silent, D-4).

**Silhouette (E1):** the spear line above the head, the gray swept head shape, hood + scarf volume, the plated left shoulder against the bare right, coat tails over heavy boots — OLD VETERAN in solid black, front, ¾ and back.

---

## 4. Gianluca animation personality (spec for `NpcMotionConfig`, not yet authored)

Pack **`Veteran`** derived from `Survivor`: `idle.breathe.period 3.8, amp 1.2` · `idle.weightShift.amp 3, period 9` (biased to the staff side) · `idle.look.amp 18, period 7` (slow, deliberate) · `propRest`: right hand keeps the spear grip; every 20–40 s a small left-shoulder roll (old injury) · **talking:** `point` (left hand, small), `dismissWave` (low), `gazeLock` on emphasised lines; no big gestures · **reaction `warMemory`** (fired by the dialogue hook when a line is tagged Elder Tung / the war / Bacon Head / the old army): straighten (waist bend 9 → 3), freeze the idle layer 1.5 s, tighten the grip (elbow +8°), turn the head away 30°, face `tired`, then ease back over 3 s. Understated; no emote.

---

## 5. Comparison (F)

| | V1 (Step 0) | V2 (young ranger) | **V2.5 (old veteran)** |
|---|---|---|---|
| history | none | none | clasp, plate, spear, collar + bell |
| age | ageless block | young | old, gray, lined |
| silhouette | box + hat | hat + mantle + cane | spear line, hood, plated shoulder, tails, boots |
| emotional weight | blank | wide-eyed | lidded, serious, leaning |
| story readability | "NPC with hat" | "ranger" | "veteran who fought" |
| presentation | blockout | authored shells | authored shells + head treatment |

---

## 6. Budgets (H) and reusable-vs-custom breakdown (G)

| character | tier | parts | welds | Motor6D | bespoke | reusable | kit | triangles | caps (parts / welds / bespoke / tris) |
|---|---|---|---|---|---|---|---|---|---|
| Gianluca V1 (Step 0) | 2 | 41 | 17 | 22 | 0 | — | — | 2,860 body + primitives | 38 / 14 / 3 / 9,000 (passed with the blockout allowance) |
| Gianluca V2 (young, rejected) | 2 | 37 | 14 | 22 | 3 | 26 | 6 | 3,468 | fits Tier 2 |
| **Tier 1 Villager** | 1 | 26 | 3 | 22 | 0 | 18 | 7 | 2,192 | 30 / 8 / 0 / 5,000 — PASS |
| **Tier 2 Merchant** | 2 | 35 | 12 | 22 | 0 | 25 | 8 | 2,676 | 38 / 14 / 3 / 9,000 — PASS |
| **Tier 3 Gianluca V2.5** | 3 | 43 | 20 | 22 | 7 | 30 | 4 | 4,188 | 50 / 24 / 8 / 16,000 — PASS |

Parts = pieces + HumanoidRootPart + collider (T2/T3); welds = welded pieces + collider; Motor6D = 15 rig + 7 face. The Tier 3 increase over V2 (+6 parts, +6 welds, +720 triangles) buys the beard, age lines, hood, plate, patch, bell and a four-part spear — all under the Tier 3 caps with 7 parts / 4 welds / 1 bespoke / ~12k triangles of headroom. Gianluca V2.5 **needs the Tier 3 envelope** (43 parts > Tier 2's 38); his recipe currently says `tier = 2`.

Reusable library after this study (all parameterised by the BodyProfile): body kit · head shell (lids, nose) · faces YOUNG / MATURE / VETERAN × 8 states · age lines · hair `crop, tousled, side, bob, cropped, sweptback, tiedback` · beard `short, stubble, moustache, goatee`, moustache · shirt, coat body, tunic front, tunic hem, coat tails (frayed option), apron, hood down, mantle, scarf, neckerchief · sleeve (puff/rolled), bracer, forearm + cuff, gloves, hands · boots (cuff/straps/oversize), shoes · belt + buckle, rope belt, pouch, satchel, belt bell · props: cane + bell, coin sack, rock; the three staff candidates are bespoke to Gianluca.

---

## 7. What would change in the framework after approval (not done)

Same list as the V2 study §8 (BodyProfile P2 as a `BodyTypes` entry, `kind = "shell"` library entries with a `slot`, `NpcForge.AssembleHuman` taking the slot mesh, low-poly export beside the voxel path) plus:
1. `NpcFaceConfig`: V2.5 shapes; lids live in the head mesh; the lash line moves with the brow (the expression tables map straight onto the existing `Expressions` entries, eight states).
2. `NpcLibrary`: `AgeLines`, `Beard`, `HoodDown`, `ShoulderPlate`, `Clasp`, `SleevePatch`, `BeltBell`, the spear as a four-part prop with a grip attachment.
3. `NpcMotionConfig`: pack `Veteran` and the `warMemory` reaction keyed by dialogue tags through the existing dialogue hook in `NpcLife`.
4. Gianluca recipe: `tier = 3`, `face = "serious"`, hair/beard/outfit ids, `restPose` from §3; root name, prompt and dialogue contracts unchanged.

---

## 8. Art-direction decisions still needed

- **D-16** Approve Gianluca V2.5 as the human hero test (age, outfit, posture, silhouette) — or name what to change.
- **D-17** Face language V2.5 (moderate eyes + built-in lids + brow-coupled lash line) as the global standard, with YOUNG / MATURE / VETERAN as the three base styles.
- **D-18** The Elder Tung clue = the scarf clasp (twin-notch chevron). Alternatives rendered: none needed; a medal or plate marking would be louder.
- **D-19** Prop = spear-staff (A). B and C are rendered for the record.
- **D-20** Gianluca moves to the **Tier 3 envelope** (43 parts). If you want him kept at Tier 2, the plate, patch and spear cloth go and the spear merges to two parts (−5 parts, −4 welds).
- **D-21** Hair/beard = swept back + short beard (E3); hat off by default, hat-on variant allowed for the World 1 cold-weather variant if wanted.
- **D-22** P2 proportions stay as the global BodyProfile (unchanged from the V2 study; still not applied to `NpcRigSpec`).
- Veteran V2.5 for the World 3 Brainrot story NPC remains deferred until E-13 gives the real Bombardiro bounds.

---

## 9. Files and validation

New: `tools/npc_kit/v2/kit25.py`, `characters25.py`, `study25.py`, `tools/npc_kit/tests/test_v25_study.py` (9 tests), `docs/npc/previews/v25/*` (16 sheets + `v25-summary.json`), this document. Modified: `tools/npc_kit/v2/study.py` (ladder framing), `tools/README.md`, `game-src/npc-kit/README.md` (pointers). Untouched: every Lua module, `tools/brainrot_forge/`, `game-src/place-full/`, all live NPCs, quests, prompts, worlds.

`python -m npc_kit.lint` OK · `python -m pytest npc_kit/tests -q` → **61 passed** · `python -m npc_kit.v2.study25` exit 0.
