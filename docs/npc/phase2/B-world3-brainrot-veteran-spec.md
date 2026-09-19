# B — World 3 Brainrot Veteran Spec (Prototype 2: the story-brainrot standard)

**Lane:** NPC-01 · Phase 2 design package · 2026-09-19 · design only. Species, name and placement belong to the World 3 lane / Balkan (`GardensNpcConfig.Roles.Veteran`: "Il Vecchio Bombardiro — PLACEHOLDER (species TBD)" `[code]`). This spec is the **treatment**, worked on the species the World 3 audit proposes, and written so it applies to whichever species is chosen.

Governing rule (Phase 1 §19): **a story brainrot is a roster template plus a story layer — never a new construction style.** It must pass `BrainrotBudget` with the story layer counted (`docs/brainrot-build-standard.md` §3).

## B1. Base Brainrot identity

| | |
|---|---|
| Proposed species | **Bombardiro Crocodilo** — the World 3 audit's "one-winged old bomber crocodile who flew for Tung" `[doc]` |
| In the roster | Valley **Mythic** (2,970/s), Tundra Rare `[code: BrainrotConfig / BrainrotConfigTundra]` |
| Template | pack model, **6 BaseParts, 4,291 triangles** at the 6-stud fit `[doc: build standard §4]`; pack anatomy = `RootPart` (invisible PrimaryPart) + `FakeRootPart` + `VfxInstance` + visible MeshParts on Motor6D to `FakeRootPart` `[doc]` |
| What must stay recognisable | the crocodile-plane silhouette (snout, the bomber wings/body, the tail), its species colours (desaturated, never replaced), its face overlay |
| What changes | age, damage, a bound wing, a pilot's remnant, a seated stance, a stillness the plot bodies never have |

**Species-dependent branch.** The pack's meshes are third-party imports and cannot be edited in Studio, so on a pack species the veteran layer is **additive only** (Path A). If the World 3 lane picks a **forge-baked species** (one of the 68 in-house bodies, re-bakeable from the Part originals in `ServerStorage.AuditBackups.*_PreForge_2026-09-17` `[doc]`), the layer may also be **subtractive** (Path B: a wing actually missing, a bite out of the tail). Both use the same eight-part story kit below; only "delete a mesh role" differs. The mesh split of the pack Bombardiro (is the head its own MeshPart? the tail?) is Studio item E-13 — it decides how much of him can move.

## B2. Veteran layer (≤ 8 parts, Part-built or forge-baked props, all `Plastic`)

Priority order so the World 3 lane can drop from the bottom if a species needs the budget elsewhere.

| # | Part | Construction | Size (studs, at the 6-stud fit) | Colour | Reads as |
|---|---|---|---|---|---|
| 1 | `WingSplint` slat | one flat slat lashed along the upper edge of the **left** wing | 0.18 × 2.2 × 0.5 | walnut (74,50,30) | the wing that never healed |
| 2 | `WingStrap` | one flat strap band across the slat and wing | 0.9 × 0.10 × 0.6 | soot leather (52,50,48) | bound, not decorative |
| 3 | `HarnessPlate` | chest slab, set **6° askew** so it reads dented without a second part | 1.6 × 1.2 × 0.16 | iron (96,98,104) | the pilot's armour remnant |
| 4 | `HarnessStrap` | one band from the plate over the right shoulder | 0.35 × 1.4 × 0.10 | soot leather | holds the plate on |
| 5 | `GoggleBand` | band around the crown | 1.5 ⌀ × 0.12 | soot leather | goggles pushed up — he stopped flying |
| 6 | `GoggleLens` | one block pair merged as one part (two lenses side by side), tinted dark = "cracked" | 0.9 × 0.28 × 0.22 | smoked glass (70,72,80), `SmoothPlastic` | |
| 7 | `Medal` | small disc on the plate | 0.32 ⌀ × 0.06 | brass (196,150,72) | he was decorated; nobody says for what |
| 8 | `SnoutChip` | dark inset slab flush with the snout tip | 0.34 × 0.20 × 0.10 | (60,52,48) | bitten, burnt or shot — unanswered |

Four accent colours in total (walnut, soot leather, iron, brass + one glass tint). No Neon, no emitters on the layer, no textures. Every part `Anchored` (the character is a static Workspace model), `CanCollide/CanQuery/CanTouch = false`, `CastShadow = false`, attribute `NpcStoryLayer = true` so the budget report counts them.

### B2.1 Armour remnants
The plate + strap + medal are the "armour remnants": one plate, not a suit. It sits **askew and low**, strap loosened — worn for forty years, never taken off. The forge-species Path B may additionally recolour one body role to a duller "old paint" on the wing/body where a squadron marking would have been (no marking is drawn: the Bacon Head canon is from zero `[doc]`).

### B2.2 Damage / scarring
- **Age:** every visible MeshPart's `Color` desaturated ~20 % and darkened ~8 % from the template (authored once; Path A and B).
- **Scorch:** if the tail (or any rear role) is its own MeshPart `[studio: E-13]`, recolour it to (60,52,48) — a burnt tail is the cheapest "war" read there is. If the tail shares the body mesh, skip; the snout chip carries the damage read alone.
- **The bound wing:** Path A — splint + strap over the intact wing. Path B — delete the left wing role, cap the stump with the splint. Both read "cannot fly"; B reads harder.
- **Face:** the species' own face overlay stays; "worn" = tint the overlay slightly (`SurfaceAppearance.Color` on pack faces; role repaint on forge faces) and add the goggles pushed up over the brow, which shadows the eyes into "heavy lids" without touching the face at all.

## B3. Stance

- **Seated / sunk:** the whole model pitched **back 12°**, rolled **6° toward the bound wing** (weight off it), and sunk **0.4 studs** into the rubble/plinth so the underside is hidden and he reads as sat, not placed.
- **Facing:** 30° off the tunnel axis — he watches the tunnel mouth, not the path; a player approaching enters his gaze from the side.
- **Scale:** the plot fit (6.0 × the species' `HeightScale`), so a standard human (5.23) and he share one portrait frame when the Keeper's arc brings them together.
- A `PoseAnchor` attachment on `RootPart` gives the driver the authored up axis, so the breathe layer moves him along *his* tilted axis, not the world's.
- The tin cup, the rubble, the plinth are **scene props (World 3 lane)**, not part of the character budget.

## B4. Prop

None held — a crocodile-plane has no hands, and "nothing in his claws any more" is the point. The splint *is* his prop in silhouette terms. (The Deserter, by contrast, carries something: B7.)

## B5. Idle behaviour (kit C7, pack **Creature**, profile `Veteran`)

| Layer | Value | Notes |
|---|---|---|
| `breathe` | whole-model rise/fall 0.03 studs, **4.6 s** (slow), along `PoseAnchor` up | the only motion at rest — stillness is the character |
| `glance` (head) | if the head is its own MeshPart `[studio]`: snap-and-hold yaw ±14°, period 11 s, ease 0.3 on the head's Motor6D `C0`; else none | Michael's bird rule `[code: NpcIdle]`, slowed to an old man |
| `sag` (bound wing) | if the wing is its own MeshPart: roll +1.5° drifting over 6 s and back | the splint carries it |
| on `PromptShown` | the **slow turn**: head (or whole model if rigid) yaws toward the player over **2.2 s**, ease 0.3, then holds | he noticed you a while ago |
| on `PromptHidden` | holds 4 s, then returns | he keeps looking |
| talking | mouth does **not** animate on a pack face; the talking beat is a 3° head tilt every 5–8 s | "…Another one?" — he barely speaks |
| LOD | Creature rules: full ≤ 40 studs, every 2nd frame to 90, paused beyond 140 (kit C8) | |

No `BrainrotBody` tag (he is not a plot body and must never enter `BrainrotIdleClient`'s hover preset); tag `NpcBody`, `NpcPack = "Creature"`, `NpcTier = 3`.

## B6. Lore readability (what a player gets, and when)

| Distance | Reads |
|---|---|
| 60 studs | a crocodile-plane, seated low, one wing held stiff by something pale; a glint on the chest |
| 20 studs | the splint and strap, the askew plate, goggles up on the head, the medal, the chip out of the snout — five facts, no text |
| walk-up | he turns to you slowly; the outline lands on a creature, not a prop |
| portrait | the species face under pushed-up goggles, tinted older; the head tilt when he says the one line |
| never | why the war was lost, what happened to the others, a squadron mark, a number of years — all board holds `[code: GardensNpcConfig header]` |

## B7. Reusable veteran components (the story-brainrot kit)

| Component | Also used by |
|---|---|
| `WingSplint` + `WingStrap` | any winged/limbed species — a bound limb is the universal "wounded" |
| `HarnessPlate` + `HarnessStrap` + `Medal` | the "served under Tung" set; the Deserter gets the plate **without** the medal and with the strap cut |
| `GoggleBand` + `GoggleLens` | pilots, drivers, miners (lens tint = crystal for the Ancient) |
| `SnoutChip` inset rule | any species: one dark inset flush with a surface = damage |
| age recolour rule (−20 % sat, −8 % val) | the Veteran, the Deserter, the Ancient (−35 % for the Ancient) |
| scorch role recolour | forge species only |
| sunk/askew stance rule | every seated story brainrot |
| **Deserter** (`Il Disertore`) | same kit, different colourway: **stolen banner as a cloak** (one draped part, faded dye), plate without medal, strap cut, goggles down over the eyes (he hides), holds the crypt key on a cord (one prop) |
| **Ancient** (`Il Sussurro`) | age rule at −35 %, **≤ 3 crystal growths** (cyan 158,234,238 — the Gardens accent, `SmoothPlastic`, never Neon), no armour, eyes shadowed by an overhang part; motion = breathe at 7 s only |

## B8. Performance budget

| Item | Path A (pack species) | Path B (forge species) |
|---|---|---|
| Template BaseParts | 6 (Bombardiro) | ≤ 12 |
| Story layer parts | ≤ 8 | ≤ 8 |
| **BaseParts total** | **≤ 14** | **≤ 20** — both inside the pack p90 and the standard's own Max (20) |
| Triangles | 4,291 + ≤ 300 (Part props are ≤ 12 tris each; a forge-baked splint ≈ 100) | template + ≤ 300 |
| Emitters | **0** — the pack Mythic aura is removed (`BrainrotFX.stripAll` pattern): an aura on a war veteran reads wrong and he is not a catch | 0 |
| Lights / Highlights / scripts / Humanoid | 0 / 0 / 0 / none | same |
| Motor6D | the template's own (import residue); optionally used for `glance`/`sag` via `C0` | ≤ 5 if a Tier 3 gesture needs them |
| Descendants | ≤ 40 | ≤ 60 |
| Replication | static model; all motion client-side | same |
| Gate | `BrainrotBudget.review` PASS on every row **plus** `NpcBudget` (story-layer rows) | same |

Cheaper than a plot Mythic at rest, and unlike a plot Mythic he never enters the spawner, the index, the bag or the reveal — he is a Workspace character parented by the World 3 lane, never in `ReplicatedStorage.BrainrotModels`.

## B9. What the World 3 lane decides (not NPC-01)

Species (and therefore Path A/B), the display name, the placement at the Whisperdeep mouth or bell tower, the `VeteranPrompt` `PromptPart` position and range, and whether the tin cup / rubble scene props ship. NPC-01 delivers the finished character to `ServerStorage.NpcStaging.Gardens` after the budget gate.
