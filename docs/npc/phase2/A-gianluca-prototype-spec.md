# A — Gianluca Prototype Spec (Prototype 1: the global human style)

**Lane:** NPC-01 · Phase 2 design package · 2026-09-19 · design only. Built on the base kit (C). Nothing placed, no live replacement.

## A0. Who he is (unchanged) and what must not move

| | |
|---|---|
| Role | World 1 quest NPC — "find the Secret Chim, bring it back, get a Key" (`GianlucaQuest`) |
| Voice | flustered, Italian-camp comic energy ("ARRRGGGGHHHH!!!!! IM SO STUPID!!", "GRAZIE, bambino!!") `[code]` |
| Tier | 2 |
| Code contracts kept | model name `StupidGianluca` under `Workspace.GameWorld`; a part named `HumanoidRootPart` that contains `TalkPrompt` (hold 0.5) `[code: GianlucaClient]`; dialogue name "Gianluca", gold accent (255,216,96)/(238,148,24); `RightHand` present. Quest logic and prompt untouched |
| What he replaces | a catalog-pipeline R15 avatar, 37 parts including stall, crates and a cane, stock idle from the public pool + root "bored" motion + a coin flip `[code]` |
| Design intent | **the friendly Skip Rocks human**: warm, chunky, hand-carved; one big shape (the pinned floppy hat) + one prop (the bell-cane); a face that is worried in a lovable way |

## A1. Proportions

- Body type **`standard`**, `NpcScale 1.0` → 5.23 studs, 3.4 heads (kit C1.2).
- Rest pose override: Waist pitched **+4° forward** (he is always leaning into a search), shoulders rolled 10° out (a little more open than the base 8°), feet 0.2 apart, left foot 0.1 ahead.
- Head centre 1.45 above the HRP centre — the portrait line holds.

## A2. Silhouette

- **Front:** a wide floppy hat brim with the **left side pinned up** breaks the round head into an asymmetric shape; a **scarf tail** hangs off the right shoulder to mid-torso; the **bell-cane** is planted at the right hand with the bell hanging outside the body line.
- **Back:** hat brim + scarf tail down the back + cane tip. Three reads, all outside the torso silhouette.
- **At 60 studs:** hat + scarf + cane — a person with a hat and a stick, distinct from every merchant (aprons, no hats).
- **At 20 studs:** the pinned brim, the empty Chim collar on his belt, the bell.

## A3. Body construction (one colour per MeshPart — kit C2)

| Part | Mesh | Colour (RGB) | Note |
|---|---|---|---|
| Head | `Head` | skin tan (214,176,138) | |
| UpperTorso | `UpperTorso_standard` | moss (98,140,70) — tunic | |
| LowerTorso | `LowerTorso_standard` | leather (134,96,58) — waist/belt band | |
| L/R UpperArm | `UpperArm_standard` | moss — tunic sleeves | |
| L/R LowerArm | `LowerArm` | skin tan — rolled sleeves | |
| L/R Hand | `Hand` | skin tan | |
| L/R UpperLeg | `UpperLeg` | walnut (74,50,30) — trousers | |
| L/R LowerLeg | `LowerLeg` | boot leather (110,78,46) | boot colour on the whole shin, no overlay needed |
| L/R Foot | `Foot` | dark boot (86,60,36) | |
| HumanoidRootPart | — | invisible | contains `TalkPrompt` |

Mesh route for the prototype: **forge-voxel** (kit C2.1) — his segments are the shared `standard` set; nothing bespoke in the body.

## A4. Face (kit C3)

- Default expression **`worried`** (brows inner-up −16/−16 at y +0.40, eyes tall 0.34, mouth small and low 0.24 × 0.10). It reads as "lost something", not sad.
- Talking variant while in dialogue (mouth oscillates).
- Brow colour = hair chestnut (92,58,36). Optional later beat: `excited` when the Chim is handed over — needs one attribute write (`NpcFace = "excited"`) in `GianlucaClient` on `Note == "key"`; **not in this phase** (quest client untouched), listed for approval.
- Gaze follows the player within 20 studs; blink every 3–6 s. He looks *at* you, worried — that is most of his charm.

## A5. Hair / headwear

| Slot | Module | Colour | Notes |
|---|---|---|---|
| Hair | `messy: tousled` | chestnut (92,58,36) | shows under the brim at the sides and nape |
| Hat | `hats: floppy brim, one side pinned` | leaf (108,160,80); pin/band baked into the mesh as geometry, single colour | brim 2.3 wide, crown 1.6; the pinned left side lifts 35° |

## A6. Outfit (family **ranger**, kit C5)

| Overlay | `Bone` | Size (approx) | Colour | Purpose |
|---|---|---|---|---|
| tunic hem | LowerTorso | 2.10 × 0.60 × 1.15 ring | moss | tunic reads as a garment, not a painted torso |
| cloak yoke | UpperTorso | 2.40 × 0.55 × 1.25 cap over the shoulders | cream (238,226,200) | the light shape that lifts the silhouette |
| scarf tail | UpperTorso (right collar) | 0.45 × 1.60 × 0.20 | berry (168,58,86) | the accent; hangs to mid-torso |
| tool belt **with the empty Chim collar** | LowerTorso | 2.15 × 0.30 × 1.20 band + a 0.30 collar loop with a brass buckle | leather; buckle brass (196,150,72) baked as geometry | the story in one prop — bespoke mesh |
| bracer ×2 | L/R LowerArm | 0.80 × 0.50 × 0.80 | leather | reads "ranger" at distance |

Boot tops are not overlays here (the shin colour does the work). Five overlay meshes, six overlay parts — within the Tier 2 cap of six.

## A7. Prop — the bell-cane

| Part | Construction | Size | Colour | Mount |
|---|---|---|---|---|
| `Cane` | one forge/prop mesh: shaft + knob | shaft 0.22 ⌀ × 1.75, knob 0.38 sphere-ish | walnut (74,50,30); knob darker (58,40,24) if a second role is worth it | `Grip = "RightHand"`, pivot at the knob = the palm; tip touches the ground at rest |
| `Bell` | one part (a small cup shape; a cylinder is acceptable for the prototype) | 0.30 ⌀ × 0.28 | brass (196,150,72) | welded to the cane knob on a 0.12 loop; hangs outside the fist |

The coin flip is retired with `NpcPropLife`. The cane is welded, never written per frame; when the arm lifts, the cane lifts (kit C6).

## A8. Idle behaviour (pack **Villager** with Gianluca overrides)

| Layer | Villager default | Gianluca | Why |
|---|---|---|---|
| breathe (Waist pitch) | ±1.5°, 3.4 s | ±1.8°, **2.9 s** | anxious, slightly quick |
| weight shift (Root roll + y, hips counter) | ±2.5°, 9 s | **±5°**, 7 s | he can't stand still — the "bored turn" the current root motion already does, moved into the joints `[code: NpcBodyLife]` |
| look around (Neck yaw snap-and-hold, Waist follows 30 %) | ±22°, 6.5 s | **±28°, 5.0 s** | scanning for the Chim |
| minor gesture | 12–20 s | scratch under the hat brim (LeftShoulder −40, LeftElbow −110, 1.4 s), 12–18 s | keeps the pinned hat in the eye |
| hands on hips | 20–40 s | **off** | reads too settled for him |

Rest lean +4° is part of the pose, not a layer. All layers write `C0` from the captured rest (kit C7.3); deterministic phase from name + position.

## A9. Gesture behaviour

**`ringBell`** — signature, 2.4 s, weight 3, cooldown 14–26 s, also the **greet** on `PromptShown`. Degrees; `pitch < 0` raises the arm forward; smoothstep between keys.

| t (s) | RightShoulder | RightElbow | RightWrist | Neck | Waist |
|---|---|---|---|---|---|
| 0.00 | 0 | 0 | 0 | 0 | 0 |
| 0.45 | pitch −75, roll −8 | pitch −25 | 0 | 0 | 0 |
| 0.65 | | | roll +22 | | |
| 0.85 | | | roll −22 | | |
| 1.05 | | | roll +22 | | |
| 1.25 | | | roll 0 | | |
| 1.45 | | | | yaw −38, pitch +4 | yaw −10 |
| 1.85 | | | | yaw +38 | yaw +10 |
| 2.15 | | | | yaw 0, pitch 0 | yaw 0 |
| 2.40 | pitch 0, roll 0 | 0 | | | |

Read: lifts the cane to chest height, shakes the bell three times, peers left, peers right, plants the cane. Sound: **no new audio** (audio assets are account-locked like animations); optionally an existing short `SoundKit` cue at ≤ 0.15 volume, chosen in Studio — or silent.

**Talk set** (while `talking`, kit C7.6): nod (Neck pitch ±3°, irregular), one-arm gesture every 4–7 s (RightShoulder −30 / RightElbow −60, 1.2 s — the cane comes up a little with it, which reads as emphasis), mouth oscillation, `worried` brows.

**Future hook:** `ringBell.asset` / `.sequence` fields are empty; when uploaded clips exist the same gesture plays as a track (kit C7.7).

## A10. Material / colour direction

| Role | RGB | Material |
|---|---|---|
| skin | 214,176,138 | Plastic |
| hair / brows | 92,58,36 | Plastic |
| tunic (moss) | 98,140,70 | Plastic |
| yoke (cream) | 238,226,200 | Plastic |
| scarf (berry) | 168,58,86 | Plastic |
| leather (belt, bracers, lower torso) | 134,96,58 | Plastic |
| trousers (walnut) | 74,50,30 | Plastic |
| boots | 110,78,46 / 86,60,36 | Plastic |
| hat (leaf) | 108,160,80 | Plastic |
| brass (buckle, bell) | 196,150,72 | SmoothPlastic |
| eyes | 252,252,252 / 16,14,20 | SmoothPlastic |
| mouth | 60,34,30 | Plastic |

Eleven colours, no textures, no Neon, no gradients; seams come from the overlay layering, not paint.

## A11. Reusable components (what Gianluca proves for everyone)

- The whole **`standard` base body** and the **face system**.
- **Ranger family** colour set + tunic hem, cloak yoke, scarf tail, bracer, tool belt (the collar variant is his; the plain belt is the library piece).
- **Floppy-brim hat** (pinned variant; the unpinned brim is the same mesh family) and **tousled hair**.
- **Walking cane** prop (bell is the variant).
- **Villager pack** with the override mechanism (any NPC can retune amplitudes/periods without new data shapes).
- The **greet-on-PromptShown** and **talk** hooks, proven against the live prompt and the locked dialogue shell.
- Bespoke to him: the collar-on-belt mesh, the `ringBell` gesture, his layer overrides.

## A12. Part / mesh budget

| Item | Count |
|---|---|
| Base body parts (15 MeshParts + HRP) | 16 |
| Face parts | 7 |
| Overlay parts (hem, yoke, scarf, belt, bracer ×2) | 6 |
| Hair + hat | 2 |
| Prop parts (cane, bell) | 2 |
| **BaseParts total** | **33** (Tier 2 cap 38 ✓) |
| Unique meshes beyond the shared base | 9 (hem, yoke, scarf, belt+collar, bracer, hat, hair, cane, bell) — **1 bespoke** (belt+collar), 8 library |
| Motor6D | 22 |
| Triangles (forge-voxel estimate) | ≈ 6k (Tier 2 cap 9k ✓) |
| Emitters / lights / scripts | 0 / 0 / 0 |
| Descendants (with attachments, welds, joints) | ≈ 75 |

Gate: `NpcBudget.report` must PASS before he leaves `ServerStorage.NpcStaging.Valley`; the live swap itself is a separate, approved step (Phase 1 order 2b) and is **not** part of this package.
