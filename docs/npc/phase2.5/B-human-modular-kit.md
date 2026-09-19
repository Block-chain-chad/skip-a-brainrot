# B — Human NPC Modular Kit: starter library

**Lane:** NPC-01 · Phase 2.5 · 2026-09-19 · inventory only; no assets created.
Goal: the **minimum** set that makes the first ten NPCs look intentionally different — Gianluca, the five valley merchants (Marco, Rocco, Enzo, Gino, Lil Miss), Vespa, Nonna Ines, Sergeant Ottavio, the Cove Appraiser. Two waves; Wave 1 alone covers Gianluca + the merchants.

Every entry is one mesh (one colour role) unless noted. Meshes are forge-voxel for the prototypes (kit C2.1) and can be swapped for modelled meshes later without touching rigs, data or driver.

## B1. BODY (SR-Rig segments; one colour role each)

| Segment | Meshes | Wave | Notes |
|---|---|---|---|
| Head | `Head` (1, shared by everyone) | 1 | 1.50×1.55×1.35; rounded box; face parts sit on it |
| Torso | `UpperTorso_standard`, `LowerTorso_standard` | 1 | `_stout` (+2), `_slight` (+2) |
| Upper arms | `UpperArm_standard` (symmetric, both sides) | 1 | `_stout`, `_slight` (+2) |
| Lower arms | `LowerArm` (shared) | 1 | |
| Hands | `Hand` (mitt, symmetric, shared) | 1 | "subtle hand motion" is wrist/elbow motion; no fingers |
| Upper legs | `UpperLeg` (shared) | 1 | trouser colour lives here |
| Lower legs | `LowerLeg` (shared) | 1 | boot colour lives here when the character wears boots |
| Feet | `Foot` (shared) | 1 | shoe colour; `BootTop` overlay only when the boot must read as a separate shape |

Wave 1: **9 meshes** (`standard` set). Wave 2: **+6** (`stout` + `slight` torso/arm sets) → 15 body meshes for every human in the game.

Body-type assignment for the first ten: Gianluca standard · Marco stout · Rocco stout · Enzo standard · Gino stout · Lil Miss slight · Vespa slight · Ines slight (scale 0.95) · Ottavio stout (scale 1.08) · Appraiser stout.

## B2. HAIR / HEADWEAR (slots + attachment standard)

**Slots:** `Hair` (1 mesh, welded to Head at `HairAttachment`), `Hat` (1 mesh, `HatAttachment`; hoods are hats), `Beard` (1 mesh, welded to Head at a `BeardAttachment` (0, −0.45, −0.55) — added to the kit's attachment list). Meshes are authored with their origin at the attachment so the same mesh drops onto any head.

| Module | Wave | First worn by |
|---|---|---|
| `HairTousled` | 1 | Gianluca |
| `HairSidePart` | 1 | Enzo, Appraiser (silver) |
| `HairCrop` | 1 | Rocco, Ottavio |
| `HairBunFall` | 1 | Lil Miss |
| `HairHeadscarfTied` (hair under a tied scarf, one mesh) | 2 | Vespa |
| `HairThinningGrey` | 2 | Ines (with `BeardChin` variants for male elders) |
| `HairSweptBackGrey` | 2 | Ottavio |
| `BeardMustache` | 1 | Marco |
| `BeardChin` | 2 | Ottavio |
| `HatFloppyPinned` | 1 | Gianluca |
| `HatFlatCap` | 1 | Marco |
| `HatKnitCap` | 2 | tundra merchant cuts |
| `HatStrawTrader` | 2 | Cove Greeter |
| `HatJewellerVisor` (loupe modelled folded up) | 2 | Appraiser, Curator |
| `HatKettleHelm` (dented) | 2 | Ottavio |
| `BandHeadlamp` (Hat slot; lamp modelled, no light on Tier 1) | 2 | Vespa |

Wave 1: **7** · Wave 2: **+9** → 16.

## B3. FACES (reusable expression system)

One system (7 parts, kit C3), **no meshes** — data only: 8 expressions + `talking-` and `eyes-closed` variants, blink, gaze, mouth cadence. Per-character choices are two attributes (`NpcFace`, brow colour = hair colour). Optional parts `Scar` (battle-worn) and `Nose` (elder set) are plain Parts made by the forge, not assets.

First-ten faces: Gianluca worried · Marco friendly · Rocco excited · Enzo friendly (+ goggles-on-brow overlay) · Gino friendly · Lil Miss friendly · Vespa suspicious · Ines old · Ottavio stern (+ `Scar`) · Appraiser suspicious.

## B4. CLOTHING (overlay layers; colour roles on the body do most of the work)

| Layer | Module | Bone | Wave | First worn by |
|---|---|---|---|---|
| shirt / jacket | `Vest` | UpperTorso | 1 | Appraiser, Rocco |
| | `ApronBib` | UpperTorso | 1 | Marco, Gino, Enzo |
| | `JacketBody` (open front) | UpperTorso | 2 | Vespa (torn-hem variant = same mesh family), tundra cuts |
| | `CloakYoke` | UpperTorso | 1 | Gianluca; Ines (as a shawl colour) |
| | `Sash` (diagonal) | UpperTorso | 2 | Appraiser (gem-studded variant = geometry studs, one colour) |
| | `CollarHigh` | UpperTorso | 2 | Keeper / noble |
| pants | — (colour role on `UpperLeg`/`LowerLeg`) | | 1 | everyone |
| | `ApronSkirt` | LowerTorso | 1 | Marco, Gino |
| | `TunicHem` | LowerTorso | 1 | Gianluca |
| | `CoatSkirt` | LowerTorso | 2 | tundra cuts, noble |
| boots | — (colour role on `LowerLeg`/`Foot`) | | 1 | everyone |
| | `BootTop` | LowerLeg | 2 | Ottavio, tundra cuts |
| belts | `Belt` | LowerTorso | 1 | Rocco, Enzo |
| | `ToolBelt` (pouches) / `ToolBeltCollar` (Gianluca) | LowerTorso | 1 | Gianluca, Vespa |
| scarves | `ScarfTail` | UpperTorso | 1 | Gianluca; Lil Miss (pink) |
| | `Neckerchief` | UpperTorso | 2 | Appraiser, Greeter |
| | `FurCollar` | UpperTorso | 2 | tundra cuts |
| armour / accessory | `SleeveCuff` | UpperArm | 1 | Enzo, Appraiser |
| | `Bracer` | LowerArm | 1 | Gianluca, Vespa |
| | `ArmWrap` | LowerArm/UpperArm | 2 | Vespa |
| | `Pauldron` | UpperArm | 2 | Ottavio |
| | `CuirassPlate` | UpperTorso | 2 | Ottavio |
| | `KneePad` | UpperLeg | 2 | Vespa |
| | `GogglesOnBrow` | Head | 2 | Enzo, Vespa |

Wave 1: **12** · Wave 2: **+13** → 25. Families (kit C5.2) are colour sets that select from these; no family needs all of them.

## B5. PROPS (grip standard)

Grips = attachments: **hand** `RightGripAttachment` / `LeftGripAttachment` (palm centre, +Z out of the fist); **back** `BodyBackAttachment`; **belt** `WaistBackAttachment` / `WaistFrontAttachment`; **shoulder** `LeftCollarAttachment` / `RightCollarAttachment`. A prop's pivot is its grip point; the forge places the pivot on the attachment and welds to that bone. Planted props (cane, staff, spear) get attribute `Planted = true` so the driver counters root tilt on that arm (doc C).

| Prop | Grip | Wave | First carried by |
|---|---|---|---|
| `Cane` (+ `Bell` part variant) | RightHand, planted | 1 | Gianluca |
| `CoinStack` | RightHand | 1 | Marco |
| `Rock` (reuse `ReplicatedStorage.RockMeshes.rounded` if present `[code: NpcPropLife]`) | RightHand | 1 | Rocco |
| `PotionVial` | RightHand | 1 | Enzo |
| `Egg` | RightHand | 1 | Gino |
| `Charm` (reuse `RockMeshes.crystal` if present) | LeftHand | 1 | Lil Miss |
| `Lantern` | RightHand / Waist | 2 | Vespa |
| `Backpack` | Back | 2 | Vespa |
| `Pickaxe` | Back | 2 | Vespa |
| `Ledger` | LeftHand | 2 | Appraiser, Ines |
| `GemTrayScale` (3-part assembly) | LeftHand | 2 | Appraiser |
| `Spear` | RightHand, planted | 2 | Ottavio |
| `Spyglass` | RightHand | 2 | Harbourmaster |
| `Satchel` | Waist | 2 | Vespa, Curator |
| `RopeCoil` | ShoulderL | 2 | Harbourmaster |

Wave 1: **6** · Wave 2: **+9** → 15.

## B6. Totals

| | Wave 1 (Gianluca + 5 merchants) | Wave 2 (World 3 + Cove starters) | Total |
|---|---|---|---|
| Body | 9 | +6 | 15 |
| Hair / headwear | 7 | +9 | 16 |
| Faces | data | data | 0 assets |
| Clothing | 12 | +13 | 25 |
| Props | 6 | +9 | 15 |
| **Meshes** | **34** | **+37** | **71** |

Wave 1 is the smallest set that makes six people look like six people. Nothing beyond Wave 2 is authored until a third wave of characters exists.

## B7. Distinctness matrix — the first ten

| NPC | Body | Hair / hat | Family | Signature overlay | Prop | Face | Pack |
|---|---|---|---|---|---|---|---|
| Gianluca | standard | tousled + floppy pinned | ranger | cloak yoke + scarf | bell-cane | worried | Villager (anxious) |
| Marco | stout | flat cap + mustache | merchant (amber) | apron bib + skirt | coin stack | friendly | Merchant (counts) |
| Rocco | stout | crop | merchant (gold) | vest + belt | rock | excited | Merchant (surveys) |
| Enzo | standard | side-part + goggles-on-brow | merchant (violet) → engineer accents | apron bib + sleeve cuffs | potion vial | friendly | Merchant (tinkers) |
| Gino | stout | crop (cream cap in Wave 2) | merchant (cream) | apron bib + skirt | egg | friendly | Merchant (watches egg) |
| Lil Miss | slight | bun-with-fall | merchant (pink) | scarf tail (pink) + belt | charm | friendly | Merchant (sways) |
| Vespa | slight | headscarf-tied + headlamp band | scavenger | jacket (torn) + tool belt + bracers | lantern + backpack + pickaxe | suspicious | Survivor |
| Nonna Ines | slight ×0.95 | thinning grey | survivor | cloak yoke (shawl) + apron skirt | ledger | old | Survivor (stooped) |
| Sgt. Ottavio | stout ×1.08 | swept-back grey + chin beard + kettle helm | castle | cuirass + pauldron + boot tops | spear | stern + scar | Guard |
| Appraiser | stout | side-part (silver) + jeweller's visor | trader | vest + gem sash + neckerchief | gem tray + ledger | suspicious | Merchant 1.15× |

Ten characters, every column different from its neighbours, 34 + 37 meshes total.

## B8. Kit rules (so it stays a kit)

1. One colour role per mesh; two-tone overlays are two meshes, and are rare.
2. Overlays are cut 0.05–0.10 proud of the body and never intersect each other (hem clears belt, yoke clears scarf).
3. Every mesh is authored at scale 1 on the `standard` body; `stout`/`slight` fit by the forge's per-body offset table, not by re-authoring.
4. A new NPC that needs a new mesh must first try: a colour change, a different existing overlay, a different hat. New meshes are added to the wave list, not to the character.
5. Props: pivot at the grip point, thinnest dimension ≥ 0.4, no more than 3 parts per prop.
