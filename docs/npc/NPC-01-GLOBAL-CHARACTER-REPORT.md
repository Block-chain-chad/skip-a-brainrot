# NPC-01 — Global Character Report (Phase 1)

**Lane:** NPC-01 — global NPC character overhaul · **Branch / worktree:** `npc-01-character-overhaul` at `C:\Users\m\Coding\skip-a-brainrot-npc` (base `ui-foundation` @ `86c6cf5`) · **Date:** 2026-09-19
**Status:** Phase 1 — audit + design only. **Nothing in Studio was touched. No live NPC, prompt, quest or model name was changed.** Studio control was not taken.

**How this was inspected.** The repo is a script-only mirror of the place (models, rigs, accessories and animation assets live only in Studio). Every claim below comes from one of four sources and is tagged:

| Tag | Source |
|---|---|
| `[code]` | a live script, read from the `source-sync-audit` branch (byte-exact resync of Studio at 2026-09-19 06:09 UTC — 298 game scripts; the `ui-foundation` mirror is stale for 74 of them) or from `ui-foundation` where identical |
| `[doc]` | a prior measured audit in the repo (`ROUND3-QUEST-INTERACTION-AUDIT.md`, `brainrot-build-standard.md`, `WORLD2-QUEST-AUDIT.md` / `WORLD2-MASTERPLAN.md` on `origin/world2-overhaul`, `WORLD3-CURRENT-STATE-AND-REFINEMENT.md` on `world3-refinement`, `eggs/models-build-log.md`) |
| `[infer]` | inferred from code + docs together; stated as such |
| `[studio]` | cannot be settled from the mirror — listed in §30 as an exact Studio inspection item |

Other lanes were read **read-only** (`world3-refinement`, `source-sync-audit`, `origin/world2-overhaul`). Nothing was merged, moved or edited in them.

---

## PART A — WHAT EXISTS TODAY

### 1. Current complete NPC roster

"NPC" here = any character-like model a player walks up to, talks to, or is meant to read as a person/creature. Props with prompts (Cellar padlock, Daily Wheels, market stands, plot pads, egg displays) are excluded except where they carry a character.

#### 1.1 Talking characters (11 identities, 20 bodies) — all live

| # | NPC (player-facing) | World | Location | Role | Rig / construction | Body model (exact) | Prompt (exact) | Idle today | Tier rec. |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **Elder Tung** (valley) | 1 | by the fishing hut, ≈(−96, 7, 71), seated in `GameWorld.RockingChair` `[doc]` | Main story quest-giver (Arc 1: 12 brainrots → cellar key). Tutorial target ("TALK TO ELDER TUNG") | Part-built, node-built `torso_rig`, ~66 parts (same builder as the tundra copy) `[doc][infer]`; beard parts `beard_jaw/mid/fall/tip` + mustache; `PromptPart`, `NameAnchor` `[code]` | `Workspace.GameWorld.ElderTung` `[code]` | `TungTalkPrompt` (found **by name anywhere in Workspace**), hold 0.3 `[code][doc]` | `NpcIdle` server rock profile (rides the chair, beard lags), proximity-gated 90 studs `[code]` | **3** |
| 2 | **Elder Tung** (tundra) | 2 | Elder's hut, east shore; hut centre (−8162.7, 2011.6, −7735.2) `[doc]` | Main story quest-giver (Arc 2: trials + drill → World 3). Hands over World 3's premise | Part-built, node-built `torso_rig`, **66 parts, no PrimaryPart** `[doc]` | `Workspace.GameWorld.FrozenTundra.ElderTungTundra` (in/next to `FrozenTundra.ElderHut`, 113 parts) `[code][doc]` | `ElderTungTundra.PromptPart.TungCavePrompt` — "Talk"/"Elder Tung", hold 0.3, range 12; must stay under `FrozenTundra` `[code][doc]` | **None** — profile deliberately cut ("one sine read as mechanical") `[code]` | **3** |
| 3 | **Michael** the eagle (`Michel*` in all code/data) | 2 | perched on `Ruins.AbandonedOutpost` rubble behind the hub dome, (−7853.7, 2014.3, −8194.0) `[doc]` | Named side quest ("EAGLES QUEST": 5 mutated Tung Tung Tung Sahurs → 1,000 gems + Pippo Olivardino) | **57-part voxel eagle**, PrimaryPart `Body`; part names `Head Crown Nape Neck Cere BeakUpper BeakHook BeakLower Brow Eye Pupil Nostril WingUpper Covert Secondary WingMid WingTip ShoulderHump TailFeather TailTip` `[code][doc]` | `Workspace.GameWorld.FrozenTundra.Michel` (path hard-coded in `NpcIdle`) `[code]` | `Michel.PromptPart.MichelPrompt` — "Talk"/"Michael", hold 0, range 18 `[code][doc]` | `NpcIdle` server profile: bob/yaw/roll + snap-and-hold head yaw, wing settle every 15 s, tail yaw; gated 90 `[code]` | **2+** (named, lore-adjacent) |
| 4 | **Gianluca** ("stupid gianluca") | 1 | the valley camp `[code]` (exact spot `[studio]`) | Quest NPC (find the Secret Chim → Key) | **R15 Humanoid rig** (has `HumanoidRootPart` + `RightHand`) `[code]`; 37 parts incl. "stall, crates and cane", no `NPC` child `[code]` | `Workspace.GameWorld.StupidGianluca` `[code]` | `StupidGianluca.HumanoidRootPart.TalkPrompt`, hold 0.5 `[code][doc]` | `NpcRigLife` stock idle (if rig-complete `[studio]`) + `NpcBodyLife` "bored: 28° turn" + `NpcPropLife` coin flip `[code]` | **2** |
| 5 | **Maxwell** the cat | 1 (assumed) | `[studio]` — model sits **directly under `Workspace`**, not `GameWorld` | Secret questline (Rebirth ≥ 3; every Secret + Rebirth 25 → GOD Maxwell) | **Static mesh** (one part named `maxwell`; the roster's `Maxwell` template is also "1 static mesh") `[code][doc]` | `Workspace.Maxwell` → part `maxwell` `[code]` | `Maxwell.maxwell.PetPrompt`, hold 0.5 `[code][doc]` | **None** (cut) `[code]` | **2** |
| 6 | **Marco the Buyer** | 1 / 2 / 3 | valley lodge (shops at (0, 9.5, −260)); tundra Warmhouse hub; Gardens hub | Sell merchant (own sell panel, not `MerchantConfig`) | **R15 constraint rig** (`NPC` child model, 33 of 223 parts; 17 loose clothing parts welded at runtime) `[code]` | `GameWorld.SellStall.NPC` · tundra body keyed **"Frozen Haul"** (`FrozenTundra.Hub.Stalls`) · `GameWorld.GardensSellStall` `[code][infer]` | `SellStall/TundraSellStall/GardensSellStall › PromptPart › SellPrompt` `[code]` | `NpcRigLife` + `NpcBodyLife` (lean & count) + `NpcPropLife` (money) `[code]` | **2** |
| 7 | **Rocco the Rock Dealer** | 1 / 2 / 3 | same three hubs | Rock shop (`MerchantConfig` "RockDealer") | R15 constraint rig, `NPC` child 33/181 `[code]` | `ShopStall.NPC` · "Stone Cache" · `GardensShopStall` | `ShopPrompt` under `PromptPart` | RigLife + BodyLife (surveys shelf 24°) + PropLife (rock) | **2** |
| 8 | **Enzo the Upgrader** | 1 / 2 / 3 | same | Upgrades (`MerchantConfig` "Upgrader"); tutorial target (`UpgradePrompt`) | R15 constraint rig, `NPC` child 31/109 `[code]` | `UpgradeStall.NPC` · "Thaw Works" · `GardensUpgradeStall` | `UpgradePrompt` | RigLife + BodyLife (tinkers) + PropLife (gear) | **2** |
| 9 | **Gino** (eggs) | 1 / 2 / 3 | same | Egg shop (`EggShopClient`) | R15 constraint rig, `NPC` child **35 of 2,020** parts (the stall holds the five voxel egg displays) `[code]` | `EggStall.NPC` · "Frost Eggs" · `GardensEggStall` (Gardens keeper presence `[studio]`) | `EggPrompt` | RigLife + BodyLife (watches egg) + PropLife (egg toss) | **2** |
| 10 | **Lil Miss** (charms — *Coming Soon*) | 1 / 2 / 3 | same | Charm shop (`MerchantConfig` "CharmSeller", `ComingSoon = true`) | R15 rig, **no `NPC` child** — character owns the HRP, 53 of 131 parts `[code]` | `CharmStall` · "Rime Charms" · `GardensCharmStall` | `CharmPrompt` | RigLife + BodyLife (hip sway) + PropLife (charm) | **2** (dormant) |
| 11 | **Secret Chim** | 1 | hidden on the shore `[code]` | Quest pickup (a creature, reads as a character) | Root `Part` + 31 anchored parts (ears, whiskers, tail, eyes), particle + PointLight `[code]` | `GameWorld.SecretChim` (root part) | `SecretChim.ChimPrompt`, hold 0.6 | **Two drivers at once**: `NpcIdle` (server) *and* `GianlucaClient` Heartbeat bob+spin (client) `[code]` | **1** (prop-character) |

Body count: Tung ×2, Michael, Gianluca, Maxwell, Chim = 6 unique bodies; 5 merchants × 3 worlds = 15 bodies (Gardens egg keeper unverified) → **~20–21 character bodies live**.

#### 1.2 Non-talking character props (live)

| NPC | World | Where | What it is | Rig | Tier |
|---|---|---|---|---|---|
| **DARREL bust** ("he watches the gems") | 1 | mounted on `GameWorld.EggStall.ShelfCap`; canonical copy `ReplicatedStorage.DarrelBust` `[doc]` | 65-part voxel bust of the gem mascot (cap, glasses, mustache, locs, ear stud); BillboardGui label | none (static) | 1 |
| **Six guardian statues** | Trading | 8-stud plinths at r138 around Skipper's Cove `[doc]` | clones of roster brainrots (Tralalero Tralala, La Vacca Saturno Saturnita, Bombardiro Crocodilo, Tung Tung Tung Sahur, Brr Brr Patapim, Ballerina Cappuccina) scaled 36–42 studs, scripts/humanoids stripped, breathing Highlights | none | 1 (scenery) |

#### 1.3 Planned, not live (other lanes — for coordination only)

| NPC | World | Lane | State |
|---|---|---|---|
| **Nico the Angler** (+ lodge, 4 fishing quests) | 2 | Beast (paused) | proposed in `WORLD2-QUEST-AUDIT.md` §3 / masterplan §9; no model, no code |
| Michael → **Eagle's Crag** summit perch; Tung → rebuilt **Elder's Station** lodge; five keepers moved into the **Warmhouse** | 2 | Beast (paused) | masterplan; explicitly keeps every model/prompt name |
| **Keeper** (role `Keeper`, working name Aldo) | 3 | World 3 lane | `GardensQuestConfig` written; `KeeperPrompt` under `GameWorld.LushGardens`; no body |
| **Nonna Ines** (Elder) · **Sergeant Ottavio** (Guard) · **Tino** (Youth) · **Vespa** (Scavenger) · **Corporal Dario** (Soldier) — humans | 3 | World 3 lane | `GardensNpcConfig` written (role ids are the code keys; names are **placeholders pending Balkan, board P6**); prompts `ElderPrompt GuardPrompt YouthPrompt ScavengerPrompt SoldierPrompt`; planned as "R15 rigs so `NpcRigLife`/`NpcBodyLife` animate them for free"; no bodies |
| **Il Vecchio Bombardiro** (Veteran) · **Il Disertore** (Deserter) · **Il Sussurro** (Ancient) — brainrots, species TBD | 3 | World 3 lane | same config; prompts `VeteranPrompt DeserterPrompt AncientPrompt`; planned "forge-baked or part-built; `NpcIdle` profiles"; no bodies |
| **Bacon Head** faction | — | canon | **zero references anywhere** in scripts, configs, rosters or docs (`[doc]` World 3 audit §14). New canon, from zero |
| Trading World NPCs | Trading | TW-01 | **none exist** — the Cove has player booths, boards, chests, the Eternal Skip and six statues; no character `[code][doc]` |

### 2. World-by-world breakdown

| World | Folder | Characters live | Visual state (from code/docs) |
|---|---|---|---|
| **World 1 — the valley / camp** | `Workspace.GameWorld` (stalls are *direct children*: `ShopStall UpgradeStall SellStall EggStall CharmStall`; `StupidGianluca`; `ElderTung` + `RockingChair`; `SecretChim`; `Cellar`; `DailyWheel`; `TradingCenter`; `Portals`; `PlayerBases`) | Elder Tung, Gianluca, Maxwell (parent `Workspace`), Chim, 5 shopkeepers, Darrel bust | Mixed: one wooden-log elder, one voxel bust, one static-mesh cat, one primitive chim, six catalog-style R15 avatars |
| **World 2 — Frozen Tundra** | `GameWorld.FrozenTundra` (hub `Hub.Stalls` with themed stall models; prompt models `GameWorld.Tundra{Shop,Sell,Egg,Upgrade,Charm}Stall`; `ElderHut`; `Michel`; `DrillSite`; `Ruins`) | Elder Tung (tundra), Michael, 5 shopkeeper copies | Same five merchants as the valley (cold body language + frost-tinted props in code; whether their *bodies* are re-dressed for the cold is `[studio]`) |
| **World 3 — Lush Gardens** (built, `ComingSoon = true`) | `GameWorld.LushGardens` (42,902 parts) | 4 rig-complete shopkeeper copies (Sell/Shop/Upgrade/Charm) + Gardens egg stall | "Shopkeepers only. No lore NPCs, no humans, no brainrot characters" `[doc]`; the World 3 lane's cast is config-only |
| **Trading World — Skipper's Cove** | `GameWorld.TradingWorld` + `GameWorld.TradingCenter` (island centre (8000, 2002, 8000)) | none | six oversized brainrot statues; palette sand/coral/turquoise/gold, "chunky low-poly, SmoothPlastic + sparing Neon" `[doc]` |

### 3. Current rig types

| Family | Who | Construction | Notes |
|---|---|---|---|
| **R15 avatar, constraint rig** | 15 shopkeepers (5 valley, 5 tundra, 4 Gardens + Gardens egg `[studio]`), Lil Miss variants, very likely Gianluca `[infer]` | Roblox's newer rig: `AnimationConstraint` + `BallSocket`, 54 Attachments, **zero Motor6D**, live `Animator`, `HumanoidDescription`, `FaceControls` `[code]`. Body parts + loose clothing parts (Marco: jacket, tie, lapels, cuffs, sleeves, trousers, shoes = 17 parts held by nothing but `Anchored`) | Reads as **catalog-derived** avatars (a `HumanoidDescription` is what the avatar/catalog pipeline emits). Woken at runtime by `NpcRigLife`, which welds each loose part to its nearest bone by distance, plays a stock idle, then unanchors every limb |
| **Node-built part rig** (`torso_rig`) | Elder Tung ×2 (~66 parts) | Plain anchored Parts grouped by a builder script; no joints, no PrimaryPart (tundra) | Only procedural motion possible (`NpcIdle`) |
| **Voxel part creature** | Michael (57), Darrel bust (65) | Anchored Parts, flat colours, the pre-forge voxel style | Procedural only |
| **Primitive creature** | Secret Chim (32) | Root part + anchored riders | Procedural only |
| **Static mesh** | Maxwell (1 part) | One MeshPart | The cheapest character in the game |
| **Roster brainrot templates** (for reference) | 218 in `ReplicatedStorage.BrainrotModels` | 148 pack (`RootPart` + `FakeRootPart` + `VfxInstance` + N MeshParts on Motor6D — import residue, **0 animations**) + 68 forge-baked (≤ 12 MeshParts) + Chim + Maxwell `[doc]` | The standard every new brainrot must meet (`brainrot-build-standard.md` §2) |

**No NPC anywhere has a Motor6D skeleton with authored animation. No `Animate` script exists in the place (Workspace holds exactly three scripts, none in an NPC).** `[code]`

### 4. Current animation systems

| System | Where it runs | Drives | Gate / LOD | Verdict |
|---|---|---|---|---|
| `NpcRigLife` (Script) | server, once + `DescendantAdded` | 15 R15 rigs: runtime welds, **stock idle from a 27-id pool of Roblox's public package idles** (default, zombie, ninja, robot, superhero, stylish, mage, levitation, elder, pirate, knight, astronaut, cowboy, confident, sneaky, bubbly), chosen by a hash of the stall name; then unanchors limbs (HRP stays anchored); a 3-s watchdog restarts stopped tracks | none (Animator replicates) | **Root cause of "generic Roblox quest character"**: merchants can be running a *zombie* or *levitation* idle. Limbs are physics-simulated on the server (BallSocket) — measured drift of 2–17 studs/s and one NPC 1,200 studs below the world before a guard was added `[code]` |
| `NpcBodyLife` (Script) | server **Heartbeat, every frame, no proximity gate** | one hand-authored root-CFrame "body language" per stall key (turn 10–28°, bob ≤ 0.1) on top of the stock idle | none | Reads well but **replicates ~15 root CFrames per frame to every client forever** |
| `NpcPropLife` (Script) | server **Heartbeat, every frame, no proximity gate** | one procedural hand prop per stall key (egg, money ×5 notes, rock, pebbles ×3, gear + 6 teeth, charm, coin), built at boot, positioned from the hand each frame | none | Nice idea, wrong tier: up to ~7 anchored part CFrames per NPC per frame, server-side, replicated |
| `NpcIdle` (Script) | server Heartbeat | valley Tung (rock + beard lag, measured off `Rocker` parts), Michael (bird head snap, wings, tail), Chim | proximity 90 studs, re-resolve every 120 frames | Well-crafted; but ~70 replicated CFrames/frame in the **starting area** whenever anyone is near the elder |
| `GianlucaClient` (LocalScript) | client Heartbeat | Chim bob + spin | none | **Duplicates `NpcIdle`'s Chim profile** — two writers on the same parts |
| `MerchantDialog` portrait | client Heartbeat during a conversation | copies every BasePart CFrame from the live NPC to a ViewportFrame clone (paired by name+position) | only while talking | Works with any rig whose parts move in world space; clone allowlist **strips `SurfaceAppearance`, `SurfaceGui`, `Attachment`, joints** (keeps `Decal`, `Texture`, `SpecialMesh`, `Accessory`, `Shirt`, `Pants`, `BodyColors`) |
| `BrainrotIdleClient` (LocalScript) | client, **one Heartbeat for all bodies**, tag `BrainrotBody` | `hover/bob/sway/spin/shiver` presets, phase hashed from name+pad | `RANGE 120`, `BUDGET 80` nearest, FX off > 70 | **The model to copy for NPCs** |
| `EggStallIdle`, `CoveDriver` | server Heartbeat | egg displays; Cove dressing (tag registry) | 60 / 400 studs | fine |
| Cutscenes | `CaveDrillClient` (client, camera-only, 6.4 s), `CatchCinematic` (brainrot reveal, `BrainrotRig` clones a template and poses by pivot) | camera + prop staging | — | No NPC ever moves in a cutscene today; "cutscene-ready" is a new requirement |

### 5. Quest dependencies

| Questline | Server | Remotes | NPC body needed | Prompt name the client binds |
|---|---|---|---|---|
| Elder Tung Arc 1 (valley) | `TungQuest` + `TungQuestConfig` (`NpcName = "Tung Tung Tung Sahur"`, display "Elder Tung") | `TungTalk` / `TungState` | `GameWorld.ElderTung` | `TungTalkPrompt` (any parent, found by name) |
| Elder Tung Arc 2 (tundra) | `TundraQuest` + `TundraQuestConfig` (`NpcModel = "ElderTungTundra"`, `HutName = "ElderHut"`, `PromptName = "TungCavePrompt"`) | `TundraTalk` / `TundraState`; notes `cutscene:DrillBuild`, `cutscene:DrillStart` | `FrozenTundra.ElderTungTundra`; co-located with `FrozenTundra.DrillSite` + `Portals.DepthsPortal` (rigid unit) | `TungCavePrompt` under `FrozenTundra` |
| Eagles Quest | `MichelQuest` + `MichelQuestConfig` (`NpcName = "Michael"`) | `MichelTalk` / `MichelState` | `FrozenTundra.Michel` | `MichelPrompt` under `FrozenTundra` |
| Secret Chim | `GianlucaQuest` | `GianlucaTalk` / `GianlucaState` | `GameWorld.StupidGianluca` (+ `GameWorld.SecretChim`) | `TalkPrompt` **inside `HumanoidRootPart`**; `ChimPrompt` |
| Maxwell | `MaxwellQuest` | `MaxwellTalk` / `MaxwellState` | `Workspace.Maxwell` | `PetPrompt` inside part `maxwell` |
| World 3 "The Old Orders" (not live) | `GardensQuest` + `GardensQuestConfig`; `GardensNpcConfig` | `GardensTalk` / `GardensState` | none yet | `KeeperPrompt`, `<Role>Prompt` under `LushGardens` |
| Goals board | `QuestHandler` | `QuestState` / `QuestClaim` | none | — |
| Tutorial | `TutorialClient` | — | — | `TungTalkPrompt`, `UpgradePrompt` (flags `talked`, `upgraded`) |

### 6. Dialogue dependencies

- **One shell for everything**: `MerchantDialog.Show(npcName, lines, accent, onDone, anchor, finalLabel, opts)` — the first six positional args are frozen `[code]`. Callers: `GianlucaClient`, `CatDialogueClient`, `TungQuestClient`, `TundraQuestClient`, `MichelQuestClient`, `ClientMain` (Marco), `MerchantClient` (Rocco/Enzo/Lil Miss), `EggShopClient` (Gino), and (World 3 lane) `GardensNpcClient` / `GardensQuestClient`.
- **Identity in the shell = accent pair + live portrait.** Accents: Gianluca gold (255,216,96)/(238,148,24); Tung wood (198,150,96)/(146,98,54) both arcs; Michael beak-gold (226,176,62)/(196,146,48); Maxwell berry; Marco amber; Rocco gold; Enzo violet (198,142,255)/(116,46,208); Lil Miss pink (232,150,176)/(176,62,110); Keeper moss/bronze; each World 3 role has its own pair `[code]`.
- **The portrait is the NPC's own world model** (`portraitSubject`: child `Model` named `NPC` → else a model owning a `Humanoid`/`HumanoidRootPart` → else the whole model), framed on `HumanoidRootPart` (or the anchor part), camera placed off the root's `LookVector`, head height assumed ≈ `HRP.Size.Y × PORTRAIT_RISE` above the root `[code]`.
- Lines live in each quest config (`TungQuestConfig`, `TundraQuestConfig.Stages[].Say/Nag/Done`, `MichelQuestConfig`, `MerchantConfig.Dialogue`, `GardensNpcConfig.Roles[].Lines`) — **none of them depend on the body**. `DialogueConfig` (keyed by an `NpcId` attribute, one entry: "stupid gianluca") is **dead code — nothing requires it** `[code]`.
- Round 3 (2026-09-19) locked `MerchantDialog`, `UIKit.QuestCard`, `UIKit.InteractionPrompt`, `InteractionPromptClient`, `QuestTrackerClient`, `QuestBarClient` `[doc]`. NPC-01 must plug into them, never edit them.

### 7. Exact-name / code dependencies (the "do not rename" list)

| Name | Type | Read by | Why it matters to a rebuild |
|---|---|---|---|
| `NPC` | child `Model` inside a stall | `MerchantDialog.portraitSubject`, `NpcFocusClient.targetOf`, `NpcRigLife.poolStart`, `NpcBodyLife/PropLife.keyOf` | The portrait and the walk-up outline find *the person* by this name; without it they light up the whole shop (Gino's is 2,020 parts) |
| `HumanoidRootPart` | part | portrait framing, focus fallback, `NpcRigLife` (kept anchored), `NpcBodyLife` (driven), Gianluca's prompt parent, `TungQuestClient`/`Tundra`/`Michel`/`Gardens` anchor resolution | Must exist on every human; must stay the character's root |
| `RightHand` / `LeftHand` + the 15 R15 part names | parts | `NpcRigLife` (bone count ≥ 11 = "rig"), `NpcPropLife` (hand) | Any replacement rig must keep R15 part names or these scripts silently skip it (which is fine once they are retired — see §13) |
| `PromptPart` | part | `StallPrompt.Bind` (stall → `PromptPart` → prompt), `EggHandler`, `NpcIdle` (excluded from motion) | The prompt's home in every stall and in `ElderTungTundra`, `Michel` |
| `ShopStall UpgradeStall SellStall EggStall CharmStall`, `Tundra*Stall`, `Gardens*Stall` | models **directly under `GameWorld`** | `StallPrompt.Bind` looks them up as `GameWorld:FindFirstChild(stallName)`; `MerchantConfig.StallWorld`; `EggShopClient.EGG_STALLS`; `ClientMain` | Stall models must keep name and parent |
| `ShopPrompt UpgradePrompt CharmPrompt SellPrompt EggPrompt TalkPrompt TungTalkPrompt TungCavePrompt MichelPrompt PetPrompt ChimPrompt` + World 3 `KeeperPrompt`/`<Role>Prompt` | ProximityPrompts | every client; tutorial; `InteractionPromptClient` verb map | Never rename; never move `TungCavePrompt`/`MichelPrompt` out of `FrozenTundra` |
| `Frost Eggs`, `Rime Charms`, `Stone Cache`, `Thaw Works`, `Frozen Haul` | tundra stall models (parents of the tundra `NPC` bodies) `[infer]` | `NpcBodyLife`, `NpcPropLife` keys | Renaming loses that keeper's body language + prop |
| `GameWorld.ElderTung`, `GameWorld.RockingChair` (+ parts named `Rocker`), beard part names, `NameAnchor` | models/parts | `NpcIdle` (the rock geometry is *measured off the `Rocker` parts*) | A rebuilt chair without five `Rocker` segments stops the rock |
| `FrozenTundra.Michel` + the 20 eagle part names | model/parts | `NpcIdle` head/wing/tail groups | A rebuilt eagle must keep the group names or lose the head snap |
| `Workspace.Maxwell` → `maxwell` | model/part | `CatDialogueClient` | Note the lowercase body part |
| `StupidGianluca` | model | `GianlucaClient`, `NpcBodyLife/PropLife` keys | |
| Attributes `RigLife`, `RigLifeIdle`, `BodyLife`, `PropLife`, `NpcProp`; child model `PropLife`; weld name `RigLifeWeld` | runtime | the three shopkeeper scripts | Any new NPC driver must either honour or retire these (recommended: retire, §13) |
| `BrainrotBody` tag; `Motion`/`HeightScale` attributes | brainrot templates | `BrainrotIdleClient`, spawner | Story brainrots must **not** carry the tag (they are not plot bodies) |

### 8. NPCs unsafe to replace (without a specific approval or lane sign-off)

| NPC | Why |
|---|---|
| **Elder Tung (valley + tundra)** | Owner asked for an identity audit before any redesign; he is the game's lore spine (both arcs, the tutorial, World 3's premise); his species is a roster brainrot ("Tung Tung Tung Sahur" — `TungQuestConfig.NpcName`; Los Tungtungtungcitos and Michael's quest reference him); the valley rock is measured geometry; the tundra body sits in a rigid co-location contract Beast's lane is about to move |
| **Michael** | Beast's lane moves him to Eagle's Crag (keeps path + prompt); `NpcIdle` binds 20 part names; a redesign has to be handed to that lane or wait for it |
| **Everything under `LushGardens`** | World 3 refinement is active; the lane already wrote the cast config and assumes "R15 rigs so `NpcRigLife` animates them for free" — NPC-01's rig standard changes that assumption and must be agreed there first |
| **Any Trading World character** | TW-01 owns placement, roles and social spaces; nothing is placed until they hand over role requirements |
| **The tundra hub keepers** (as *placed objects*) | Beast moves `Hub.Stalls` + the prompt models into the Warmhouse as one rigid move. Their *bodies* can be swapped in place later, but not moved |
| **Secret Chim** | A pickup with hide/show logic on its root part + descendants (`GianlucaClient`), two motion drivers — restructure only together with a code change |

### 9. NPCs easiest to upgrade (lowest risk, highest visibility)

1. **Gianluca** — standalone, one model, three contracts (`StupidGianluca`, `HumanoidRootPart › TalkPrompt`, `RightHand` for the coin), no stall to re-fit, no lane owns him, first human most players talk to after Tung. Also the most visibly "generic avatar + cane".
2. **The five valley shopkeepers** as one batch — they share one rig family, sit in one lodge, and every contract is "keep `NPC` child + `HumanoidRootPart` + R15 part names + `PromptPart`/prompt untouched". One base body fixes five characters; the tundra and Gardens copies then become outfit variants of the same five people.
3. **Maxwell** — a single static mesh; swapping the mesh keeps everything (`Maxwell`/`maxwell`/`PetPrompt`).
4. **Darrel bust** — decorative, no code.
5. **Michael** — only *after* Beast's move; group part names make a like-for-like rebuild straightforward.

### 10. Most generic-looking NPCs

- **All 15 shopkeepers + Lil Miss + Gianluca**: `HumanoidDescription` R15 avatars, clothing as loose parts, faces from `FaceControls` dynamic heads `[code]`, idles from Roblox's public animation packages chosen by hash. Prior audits called the whole cast "vendors", "the only humans are vendors" `[doc]`. Whether they also wear catalog accessories is `[studio]`.
- The **same five merchants appear in all three worlds** with the same dialogue — the cold/underground variation exists only in code (body language, prop tint), not (as far as the mirror can show) in the bodies.
- **Maxwell** as a single static mesh reads as a prop, not a character.

### 11. Current style inconsistencies

1. **Three unrelated character languages side by side** in the starting camp: catalog R15 avatars (merchants, Gianluca), a hand-built wooden-log elder, a voxel bust, a static-mesh cat, a primitive chim. None share proportions, face treatment or material rules.
2. **Idle personality is random**: a merchant's whole body attitude comes from whichever public package idle his stall name hashes to (a "robot" or "levitation" idle behind a counter); then `NpcBodyLife` layers a second, hand-authored motion on top. Two motions, neither designed for the character.
3. **World variation is code-only**: tundra keepers "shiver", "hunch", get frost-tinted props — but nothing in the mirror shows winter clothing; Gardens keepers are "brighter and busier" by root motion alone.
4. **Faces**: the R15 cast uses dynamic heads (`FaceControls`) that nothing drives; the part-built cast has authored cube faces. The game's own face language (`VoxelFace`, the pack's one-overlay faces, Darrel's grin) is on the *creatures*, not on the *humans*.
5. **Naming register drift**: "stupid gianluca" (dead `DialogueConfig`) vs "Gianluca"; "Tung Tung Tung Sahur" (`TungQuestConfig.NpcName`) vs "Elder Tung" (every client); `Michel` vs "Michael" (deliberate, persisted keys).
6. **Scale**: an NPC is ~5–6 studs tall next to plot brainrots fitted to 6.0 × HeightScale and Trading World statues at 36–42 studs; nothing states the intended human:brainrot ratio.
7. **Prop language** is procedural primitives (a Neon gear, five green notes, a sphere egg) while the world's props are chunky low-poly meshes.

### 12. Current performance concerns

| # | Concern | Evidence | Severity |
|---|---|---|---|
| 1 | `NpcBodyLife` + `NpcPropLife` are **server Heartbeat writers with no proximity gate**; every root and prop CFrame replicates to every client every frame, in every world at once | `[code]` (compare `NpcIdle`, `EggStallIdle`, `CoveDriver`, which all gate) | High — constant replication for ~15 roots + ~50 prop parts |
| 2 | **Server-side physics rigs**: 15 R15 constraint rigs run unanchored limbs on `BallSocket`/`AnimationConstraint` on the server; a race between `NpcRigLife` and `NpcPropLife` (both `task.defer`) previously threw NPCs across the map | `[code]` header of `NpcRigLife` | High (fragility) + medium (physics cost, replication of unanchored parts) |
| 3 | **Runtime welding by nearest bone** for 17+ loose clothing parts per NPC — silently wrong when a part is nearer the wrong bone | `[code]` | Medium (correctness) |
| 4 | `NpcIdle` valley Tung: ~66 + chair parts written server-side every frame while anyone is within 90 studs of the **spawn-side elder** — effectively always | `[code]` | Medium |
| 5 | Secret Chim: **two drivers** (server `NpcIdle`, client `GianlucaClient`) on the same parts | `[code]` | Low–medium (jitter risk; verify `[studio]`) |
| 6 | Gino's `EggStall` is **2,020 parts** (five voxel egg displays); the portrait had to be cut down to the `NPC` child to survive | `[code]` | Medium (belongs to the egg lane, but every Gino conversation clones from inside it) |
| 7 | Portrait clones the whole subject and copies **every** BasePart CFrame per frame during dialogue (33–53 parts today) | `[code]` | Low now; scales linearly with body part count — a hard argument for ≤ 40-part NPC bodies |
| 8 | `ElderTungTundra` has **no PrimaryPart** | `[doc]` | Low (fragile for the rigid move Beast's lane plans) |
| 9 | Boot scans: `NpcRigLife`, `NpcBodyLife`, `NpcPropLife` each walk `workspace:GetDescendants()` (58k+) once | `[code]` | Low (once) |
| 10 | `Highlight` cap 16 rendered: `NpcFocusClient` uses 1; the Cove's six statues use 6 breathing Highlights; mutation FX add more | `[code][doc]` | Low — but Tier 3 "character VFX" must not be Highlights |

### 13. Recommended global rig standard

**"SR-Rig" — one skeleton for every human and creature NPC, animated on the client, physics-free.**

| Element | Standard | Why |
|---|---|---|
| Joints | **Motor6D** skeleton (server-authored in the model), **R15 joint and part names** (`HumanoidRootPart`, `LowerTorso`, `UpperTorso`, `Head`, `L/R UpperArm LowerArm Hand UpperLeg LowerLeg Foot`) | Any Animation-Editor clip made on an R15 rig plays on it; every existing script that looks for `HumanoidRootPart`/R15 names keeps working; the portrait frames on the HRP |
| Controller | **`AnimationController` + `Animator`** — *not* `Humanoid` | No Humanoid state machine or health/physics behaviour per NPC; an Animator under an AnimationController plays the same clips; the portrait code already deletes Humanoids from clones because they re-pose rigs |
| Physics | **HRP anchored; every other part unanchored but held only by Motor6D** (kinematic assembly). `CanCollide/CanQuery/CanTouch = false`, `CastShadow = false` on all but the torso/head, `Massless = true` | Zero physics simulation, zero drift, no welds-by-distance, no constraints. This is exactly the failure mode `NpcRigLife` fought |
| Where animation runs | **Client only** — a single `NpcLifeClient` LocalScript (tag `NpcBody`) loads and throttles tracks (§24–25). The server never animates an NPC; `NpcRigLife`, `NpcBodyLife`, `NpcPropLife`, `NpcIdle` are **retired** once their NPCs are on the new rig | Server pays nothing; each client throttles by its own camera |
| Body geometry | **MeshParts**, flat `Color`, `Plastic`/`SmoothPlastic` only, `RenderFidelity Automatic`, `CollisionFidelity Box`; shared limb meshes across all humans; ≤ 1 `Decal` face (§22) | The brainrot standard's construction rule, applied to people: silhouette in the mesh, not in the instance count |
| Grouping | The person is a child `Model` named **`NPC`** inside the stall/scene model; `PrimaryPart = HumanoidRootPart`; standalone characters (Tung, Gianluca, the World 3 cast) are the `NPC` model itself under their own root model | Portrait + outline contracts |
| Portrait line | Head centre **≈ 1.5 studs above the HRP centre** (R15 at scale 1); HRP `2 × 2 × 1`. Taller/shorter characters scale the whole `NPC` model with `Model:ScaleTo`, never the offset | `MerchantDialog` frames head-and-shoulders from `HRP.Size.Y × PORTRAIT_RISE` |
| Attachments | Standard R15 names on the standard parts: `HatAttachment`, `HairAttachment`, `FaceFrontAttachment` (Head); `RightGripAttachment`/`LeftGripAttachment` (Hands); `BodyBackAttachment`, `LeftCollarAttachment`, `RightCollarAttachment`, `NeckAttachment` (UpperTorso); `WaistBackAttachment`, `WaistFrontAttachment`, `RootAttachment` (LowerTorso/HRP) | Props, hats, packs and satchels mount by name; tools work |
| Prompt | Under a dedicated `PromptPart` (invisible, anchored, in the root model, *not* inside `NPC`) except where a script already binds elsewhere (Gianluca's `TalkPrompt` stays in the HRP; Maxwell's `PetPrompt` stays in `maxwell`) | `StallPrompt` convention; `NpcIdle` exclusion |
| Tags / attributes | Tag `NpcBody`; attributes `NpcTier` (1/2/3), `NpcPack` (animation pack id), `NpcWorld` | The one client driver keys on these |
| Brainrot characters | **No skeleton by default** — pack/forge template + procedural pose driver (client), exactly like plot brainrots; optional 2–5 Motor6D (head, one arm/wing, jaw) only for a Tier 3 with a gesture that needs it | Keeps story brainrots on the plot-body cost curve |

**Two decisions this standard forces (both need your yes):**

1. **Retire the three server shopkeeper scripts and `NpcIdle`** as NPCs migrate, replacing them with one client driver. Until every NPC has migrated, both systems coexist by *tag*: the old scripts only touch Humanoid rigs, the new driver only touches `NpcBody`-tagged models — no NPC is ever in both.
2. **Animation asset path.** Authored clips uploaded from an account that does not own the experience will not play in the live game. The place is owned by `BigFrogTerryBruh` (UserId 1583162960) while Studio logs in as `prohacks_sorry` `[doc: place-full/README]`. Options, in order: (a) upload animations from the owner account (or move the experience to a group); (b) store `KeyframeSequence`s in `ReplicatedStorage.NpcAnimations` and register them per client with `KeyframeSequenceProvider:RegisterKeyframeSequence` — no upload, works for client-played tracks, must be spot-tested in a published build before we bet on it; (c) procedural joint motion (`Motor6D.Transform` written by the client driver) for the breathing/weight-shift/look layer, which needs no assets at all. **Recommendation: (c) for the Tier 1 layer now, (b) validated in a 10-minute test, (a) for Tier 2/3 gestures.**

---

## PART B — THE GLOBAL NPC SYSTEM

### 14. Global NPC art direction — "Skip Rocks people"

**One sentence:** chunky, warm, hand-carved toy-like people who live in the same material world as the brainrots — the brainrots are the *flat-colour low-poly pack*, so the humans are cut from the same block.

- **Proportions (human base):** 2.9–3.1 heads tall. Head 1.2 × the R15 default; hands and feet 1.3 ×; forearms and shins short; torso a rounded slab wider at the shoulders than the hips (or the reverse for the elder/nonna silhouette). Neck almost absent. Reads at 60 studs as a head-and-body blob with a hat.
- **Surfaces:** flat colours, 5–8 per character, `Plastic` matte (never `SmoothPlastic` on skin — it goes shiny under the tundra wash), one darker "seam" colour for the outline-like breaks between garment layers. No textures on the body. No gradients.
- **Faces:** one flat face plate with a `Decal` (§22) — big simple eyes, thick brows, a mouth shape. Expression = which decal. The creatures' cube-eye rule (`VoxelFace`) is the sibling of this: **same eye spacing and brow weight** so a human and a brainrot in one shot look drawn by one hand.
- **Silhouette rule:** every Tier 2+ character owns **one big shape** (hat, hair, pack, beard, collar) and **one prop** readable from behind. Tier 1 owns one or the other.
- **Layering:** base body → outfit overlay (1–4 mesh pieces: coat skirt, collar, belt, apron, hood) → headwear/hair (1–2) → prop (1–3). Never accessory spam: max **6 add-on meshes** on a Tier 2, 9 on a Tier 3.
- **Colour per world** (§26) is a *palette*, not a filter: the same base body, different overlay colours and one world-specific material accent (tundra fur trim, gardens patch cloth, cove gem gold).
- **Motion:** slow, weighty, large — the game already learned that "0.02-stud stock idles read as statues" and that "10–25° of turn reads as alive" `[code]`. Breathing is visible; gestures are few and big; nothing twitches.
- **Not this:** realistic anatomy, catalog clothing textures, dynamic heads, per-NPC particle auras, Highlights, tiny straps/buckles/badges under 0.25 studs.

### 15. Tier 1 standard — background NPC

| | Standard |
|---|---|
| Body | SR-Rig human base, **shared limb/torso meshes**, only head/hair/overlay/colours vary |
| Face | one of the 8 stock face decals (§22) |
| Hair/head | one module from the hair set (§21) |
| Outfit | one clothing family (§20), ≤ 2 overlay meshes |
| Prop | 0–1 from the prop kit, static in the grip |
| Animation | **Background pack** only (§24): breathing + weight shift + look-around, procedural or one shared clip; no unique clips |
| Dialogue | optional; if present, one accent pair and lines in a config table, never a bespoke client |
| Budget | ≤ 22 BaseParts · ≤ 3 unique meshes beyond the base set · ≤ 5k triangles · 0 emitters · 0 lights |
| Cost target | "dozens per world": 12 within 120 studs animated, the rest frozen (§25) |

### 16. Tier 2 standard — quest NPC / shopkeeper / named side character

| | Standard |
|---|---|
| Body | SR-Rig human base (or a brainrot template for a creature) with **one bespoke torso overlay** (the signature garment) |
| Face | a stock decal **plus one bespoke expression decal** (the "talking" face swapped in during dialogue) |
| Hair/head | one module, may be a bespoke colour/variant |
| Outfit | a clothing family with 1–2 bespoke pieces |
| Prop | **one signature prop** (bespoke mesh allowed), animated by the Merchant/Villager/Guard pack |
| Animation | a pack (§24) + **1–2 unique gestures** (greet, hand-over) — the only per-character clips |
| Dialogue | accent pair + portrait (existing shell) |
| Budget | ≤ 32 BaseParts · ≤ 6 unique meshes · ≤ 9k triangles · ≤ 2 emitters (only if the concept is the emitter — a lantern, a forge) · ≤ 1 `PointLight` |

### 17. Tier 3 standard — story / lore NPC

| | Standard |
|---|---|
| Body | SR-Rig with **bespoke torso + head meshes**; limbs may be bespoke; brainrot Tier 3 = template + up to 6 damage/armour parts + optional 2–5 Motor6D |
| Face | bespoke decal set: neutral, talking, one emotional beat (worry/anger/grief), eyes-closed |
| Silhouette | must be identifiable as a black shape at 100 studs |
| Costume | fully bespoke, but built from the same overlay slots so the modular animation still fits |
| Animation | custom idle + **3–5 custom gestures** + one cutscene pose set (`Sit`, `Stand`, `Point`, `Reveal`); rig carries jaw/brow via face-decal swaps, not bones |
| Cutscene readiness | `PrimaryPart` set; whole-model `PivotTo`/`ScaleTo` safe (no welds to scenery); a `CameraAnchor` attachment on the head; every prop welded to a hand, never to the world |
| VFX | one static emitter kit on an invisible host (the `BrainrotFX` pattern), off beyond 70 studs, **never a Highlight** |
| Budget | ≤ 45 BaseParts · ≤ 10 unique meshes · ≤ 16k triangles (the pack maximum) · ≤ 6 emitters · ≤ 1 light |

### 18. Human base rig spec

```
NPC (Model)                         PrimaryPart = HumanoidRootPart; tag NpcBody; attrs NpcTier, NpcPack, NpcWorld
├─ HumanoidRootPart   Part 2×2×1, Transparency 1, Anchored TRUE, CanCollide false
│    └─ RootAttachment
├─ LowerTorso         MeshPart  (Root Motor6D: HRP → LowerTorso)      WaistFront/WaistBack attachments
├─ UpperTorso         MeshPart  (Waist)                                Neck, L/R Collar, BodyBack, BodyFront attachments
├─ Head               MeshPart  (Neck)                                 Hat, Hair, FaceFront attachments; child FacePlate MeshPart (welded) + Decal "Face"
├─ LeftUpperArm / LeftLowerArm / LeftHand      (LeftShoulder / LeftElbow / LeftWrist)   LeftGripAttachment on the hand
├─ RightUpperArm / RightLowerArm / RightHand   (…)                                        RightGripAttachment on the hand
├─ LeftUpperLeg / LeftLowerLeg / LeftFoot      (LeftHip / LeftKnee / LeftAnkle)
├─ RightUpperLeg / RightLowerLeg / RightFoot
├─ AnimationController → Animator
├─ Outfit (Folder)     overlay MeshParts, each welded (WeldConstraint) to the part named in its attribute `Bone`
├─ Hair (Folder)       1–2 MeshParts welded to Head
└─ Props (Folder)      MeshParts welded to a Hand/Torso part; attribute `Grip = "Right" | "Left" | "Back" | "Waist"`
```

- **Proportion values (scale 1):** total height 5.0 studs; head 1.35 wide; HRP centre at 3.0 studs off the ground, head centre at 4.5 (the 1.5-stud portrait line); shoulder width 2.2; hands 0.7 cube-ish; feet 0.9 long.
- **Shared meshes** across every human: both hands, both feet, both lower arms, both lower legs, upper legs (7 unique meshes). **Per-body-type** (3 types: *standard*, *stout*, *slight*): torso pair + upper arms (3 unique meshes each). **Per-character**: head shape only if Tier 3.
- **Body types** are only mesh swaps on the same skeleton; the same animation plays on all three.
- **Scale ladder:** child 0.78 · standard 1.0 · elder/stooped 0.95 with a `stooped` overlay torso · big guard 1.12. Scaling is `Model:ScaleTo` on the whole `NPC`.
- **Faces** live on a `FacePlate` MeshPart welded to the head (§22) so the portrait clone keeps it (`Decal` survives the allowlist; `SurfaceAppearance`/`SurfaceGui` do not).
- **What the base does not do:** walk, path, collide, take damage, wear catalog `Shirt`/`Pants` textures, use `Accessory` instances.

### 19. Brainrot character spec (story brainrots)

Governing rule: **a story brainrot is a roster template plus a story layer, never a new construction style.** It must pass `BrainrotBudget` (§3 of the build standard) with the story layer counted.

| Element | Spec |
|---|---|
| Base | clone the character's own species template from `ReplicatedStorage.BrainrotModels` (pack or forge-baked), keep the geometry and colours so the species is recognised at a glance |
| Story layer (≤ 6 parts) | pick from: **armour remnant** (one dented plate/harness strap, `Plastic`, world-metal colour), **scar/chip** (a darker inset mesh or a re-coloured face overlay), **bandage/patch** (cloth-colour band), **missing piece** (delete one mesh part — a wing, an ear, a horn — and cap the stump with one small part), **badge/medal/lantern** (one prop), **age** (desaturate 15–25 %, one grey streak part) |
| Pose | unique: seated, leaning on a prop, slumped, perched — set by the model's authored CFrames; one `PoseAnchor` attachment so the client driver knows the up axis |
| Idle | procedural, client-side, from the same preset table as `BrainrotIdleClient` (`bob/sway/shiver`) plus two new presets: `breathe` (torso-only scale-less bob 0.04) and `glance` (snap-and-hold yaw, the Michael pattern) |
| Rig | none by default. Tier 3 only: ≤ 5 Motor6D (head, jaw, one limb, prop) for a gesture, animated by the same client driver |
| Face | swap the species' one face overlay for a *worn* variant (the pack: one ColorMap `SurfaceAppearance`; forge bodies: repaint the face role) — expression changes are the biggest identity lever at the lowest cost |
| Scale | story brainrots stand at the **plot fit** (6 × HeightScale) unless the beat needs otherwise; a Veteran seated should still top out near a human's head so the two converse in one portrait frame |
| Never | tag `BrainrotBody`, add a Humanoid, add a Highlight, exceed the template's emitter kit, or put the model in `BrainrotModels` (it is a Workspace character, not a catchable) |
| Budget | template parts + ≤ 6 = ≤ 26 BaseParts · ≤ 80 descendants · triangles within the template's own measure + 2k |

### 20. Clothing modular system

Every garment is an **overlay mesh welded to one named bone**, cut to sit 0.05–0.1 studs proud of the base body so it never z-fights and the base under it can stay plain. Families are palettes + a fixed slot list; a character is a family + colour set + 0–2 bespoke pieces.

| Slot (attribute `Bone`) | Pieces available |
|---|---|
| `UpperTorso` | vest, jacket body, tunic, cuirass plate, apron bib, cloak yoke, scarf, collar, sash |
| `LowerTorso` | coat skirt (front/back), belt, tool belt, kilt, apron skirt, satchel strap |
| `UpperArm` L/R | sleeve cuff, pauldron, arm wrap, rolled sleeve |
| `LowerArm` L/R | bracer, glove cuff, bandage |
| `UpperLeg` L/R | knee pad, trouser patch |
| `Foot` L/R | boot top, sandal strap |
| `Head` | hood (also a headwear module), goggles-on-brow, headlamp band |

| Family | Base palette (skin/base cloth/accent/seam) | Slots typically used | World |
|---|---|---|---|
| **village** | warm tan / cream / berry or leaf / walnut | vest, belt, rolled sleeve, sandal strap | 1 |
| **ranger** | tan / moss green / leather brown / dark bark | tunic, cloak yoke, bracer, boot top, tool belt | 1 |
| **merchant** | tan / rich colour per shop (Rocco gold, Enzo violet, Marco amber, Gino cream, Lil Miss pink) / ivory / walnut | apron bib + skirt, sleeve cuff, sash | 1 (base), 2, 3, Trading |
| **winter** | pale / deep blue-grey / fur cream / charcoal | jacket body + fur collar, coat skirt, glove cuff, boot top, hood | 2 |
| **castle** | pale / slate / brass / iron | cuirass plate, pauldron, kilt, bracer | 3 (Keep) |
| **underground survivor** | pale-grey / patched greys & ochres / rust / soot | tunic with patches, arm wrap, knee pad, satchel strap, headlamp band | 3 |
| **miner** | pale-grey / ochre / lamp-brass / soot | apron skirt (leather), bracer, boot top, headlamp band | 3 |
| **scavenger** | pale-grey / mismatched (two accents) / rust / soot | jacket body (torn hem variant), tool belt, bandage, goggles-on-brow | 3 |
| **engineer** | tan / oil-blue / brass / charcoal | apron bib, bracer, tool belt, goggles-on-brow | 2, 3 |
| **noble** | pale / deep jewel / gold / midnight | cloak yoke, sash, collar (high), coat skirt (long) | Trading, 3 (Keeper) |
| **trader** | tan / cream & turquoise / gold / coral | vest (gem-studded variant), sash, satchel strap, sleeve cuff | Trading |

Rule of thumb: **≤ 4 overlay pieces on Tier 1, ≤ 6 on Tier 2, ≤ 9 on Tier 3**; a "patched" look is one mesh with the patches modelled in, not extra parts.

### 21. Hair / headwear modular system

All mount on `HairAttachment` / `HatAttachment` and are welded to `Head`; one mesh each; hair meshes are cut to sit over the base head with the face plate exposed.

| Module | Variants (mesh) | Colour | Notes |
|---|---|---|---|
| **short** | crop, side-part, curls | any hair colour | default for most Tier 1 |
| **long** | straight-back, braid (side), bun-with-fall | | braid/bun read as a silhouette |
| **messy** | tousled, wind-swept (directional) | | tousled = Gianluca's family |
| **tied** | ponytail, top-knot, headscarf-tied (hair under scarf) | | |
| **old / grey** | thinning, swept-back grey, long beard (chest), chin beard, mustache | grey / white | beards are a **separate module** on the same attachment so any head can age |
| **helmets** | round miner's helm (+ lamp), open-face guard helm, dented kettle helm (survivor), pilot cap | world metal | Sergeant/Guard family |
| **hats** | wide ranger brim, floppy brim (one side pinned), knit cap (tundra), fur-trim hood, merchant's flat cap, straw trader's hat, jeweller's visor (Trading) | family accent | one big shape per Tier 2 |

Budget: 1 hair + 1 hat max per NPC (hood counts as hat). Total unique hair/hat meshes for launch: ~20.

### 22. Face system

- **Mechanism:** a `FacePlate` MeshPart (flat, 0.05 thick, slightly curved) welded to `Head`, carrying one `Decal` named `Face`. Expression = the decal's texture id. Swapping is one property write; the portrait clone keeps it. Decals are the game's own drawn faces (one 256² sheet per expression, ≤ 12 uploads total).
- **Stock set (8):** `friendly`, `worried`, `stern`, `suspicious`, `old` (heavy lids, brow lines), `tired`, `excited`, `battle-worn` (one scar, set jaw). Each in two eye colours by tint (`Decal.Color3`).
- **Drawing rules** (shared with `VoxelFace` on the creatures): eyes = large flat ovals with a single highlight dot, spacing ⅓ of face width; brows thick and expressive (brows carry 70 % of the emotion); mouth a simple curve/line; no noses except the elder/nonna set (a small bump).
- **Talking:** Tier 2+ get a `talking` variant of their expression; the dialogue caller sets `Face` on `MerchantDialog.Show` and restores on `Hide` via one attribute (`NpcTalking`) the client driver watches — **no change to `MerchantDialog`**.
- **Blink:** the client driver flips to an `eyes-closed` decal for 0.12 s every 3–6 s on NPCs within 40 studs only. Nothing else animates the face.
- **Brainrot characters** keep their species face; the "worn" variant is a recolour/overlay of the same face.

### 23. Prop system

One kit, one construction (a MeshPart or ≤ 3 parts, `Plastic`/`SmoothPlastic`, chunky, ≥ 0.4 studs at the thinnest), mounted by a `Grip` attribute to `RightGripAttachment` / `LeftGripAttachment` / `BodyBackAttachment` / `WaistBackAttachment`. Props are **welded, never anchored** — the arm carries them, so no per-frame prop code (retiring `NpcPropLife`'s approach).

| Prop | Grip | Families | Animated by |
|---|---|---|---|
| lantern (3 sizes; one `PointLight` on Tier 2+ only) | Right / Waist | ranger, survivor, miner, scavenger | Survivor pack "raise lantern" |
| sword (short, sheathed variant) | Right / Waist | castle, guard | Guard pack "weapon idle" |
| spear / pike | Right (planted) | castle | Guard "posture shift" |
| book / ledger | Left | noble, merchant, Keeper | Villager "inspect item" |
| pickaxe | Right / Back | miner, scavenger | Survivor "inspect gear" |
| backpack (patched / trader) | Back | ranger, scavenger, trader | — (silhouette) |
| map / scroll | Left | ranger, trader | Villager "glance at landmark" |
| staff / walking cane (+ bell variant for Gianluca) | Right (planted) | village, elder | Villager "hands on hips" alt |
| wrench / hammer | Right / Waist | engineer | Villager "inspect item" |
| satchel | Waist | merchant, scavenger, trader | — |
| telescope / spyglass | Right | ranger, trader | Merchant "inspect merchandise" |
| gem pouch (+ loose gems on a tray) | Left / Waist | merchant, trader | Merchant "count gems" |
| **shop-specific**: rock (Rocco), potion vial (Enzo), coin stack (Marco), egg (Gino), charm (Lil Miss) | Right | merchant | Merchant pack |

### 24. Animation system

**Packs** are named sets of clips (or procedural layers) assigned by the `NpcPack` attribute; a character plays **one base idle + timed gestures from its pack**, never a random stock idle.

| Pack | Base idle (loop) | Gestures (timed, 8–25 s apart, weighted) | Delivery |
|---|---|---|---|
| **Background** | `breathe` (chest 2 %, 3.4 s), `weightShift` (hip 6°, 9 s) | `lookAround` (head yaw ±25° snap-and-hold), `minorGesture` (scratch/adjust, 1.2 s) | **procedural** (client writes `Motor6D.Transform` on Waist, Neck, one shoulder) — no assets |
| **Villager** | Background + `handsOnHips` hold | `talkGesture` (one arm, 1.5 s), `inspectItem` (raise prop to eye line), `glanceAtLandmark` (turn torso 30°, hold 3 s) | procedural base + 3 clips |
| **Guard** | `weaponIdle` (planted prop, shoulders square) | `alertGlance` (fast head snap + hold), `postureShift` (stamp + re-plant) | 1 loop + 2 clips |
| **Merchant** | Background + lean-on-counter | `countGems` (both hands at waist, 2.5 s), `inspectMerchandise` (raise prop, tilt head), `wave`, `beckon` (Tier 2 greet on `PromptShown`) | 1 loop + 4 clips |
| **Underground survivor** | hunched Background (torso pitched 8°) | `nervousGlance` (quick yaw, both directions), `warmHands` (hands together at chest, 2 s), `inspectGear` (lantern raise), `lookUpward` (head pitch 25°, hold — the ceiling) | 1 loop + 4 clips |
| **Major story** (per character) | custom loop | 3–5 custom gestures + cutscene pose set | clips |
| **Creature (brainrot)** | `bob/sway/shiver/breathe/glance` presets | none (or Tier 3 mini-rig) | procedural |

- **Greet on approach:** on `ProximityPromptService.PromptShown` for a prompt whose root model is tagged `NpcBody`, the driver plays the pack's greet (wave/beckon/alert) once and sets the `talking`-ready face; on `PromptHidden` it returns to idle. This piggybacks the event `NpcFocusClient` already uses — no edits to locked files.
- **Dialogue:** while `NpcTalking` is set, gestures come from a small "talk" subset (nod, one-arm gesture) every 4–7 s so the portrait breathes.
- **Determinism:** phase and gesture timing hashed from the model name + position (the `BrainrotIdleClient` rule) so every client sees the same performance.
- **Clip authoring:** on the one SR-Rig template in Studio; a clip made for the `standard` body plays on `stout`/`slight` unchanged (same skeleton).

### 25. Animation performance / culling rules

One LocalScript, `NpcLifeClient`, one `Heartbeat`, a registry from `CollectionService:GetTagged("NpcBody")`, priorities computed every 10 frames from the camera:

| Band (distance from camera) | Behaviour |
|---|---|
| in conversation / prompt shown | full rate, gestures on, blink on |
| ≤ 40 studs | full rate; procedural layer every frame; blink on |
| 40–90 | full rate tracks; procedural layer every 2nd frame; no blink |
| 90–140 | tracks `AdjustSpeed(0.5)`, procedural every 4th frame, no gestures |
| > 140 or behind the camera (dot < −0.2 with `WorldToViewportPoint` off-screen) | tracks `AdjustSpeed(0)` (paused, pose held), procedural off, lights off |
| streamed out | entry dropped on `AncestryChanged`; re-adopted by the tag signal |
| **Budget** | at most **12 NPCs animated per frame**; past that only the nearest 12 move (the `BUDGET` rule) |
| Server | **never** animates an NPC; never writes NPC CFrames per frame |
| Per-NPC cost ceiling | ≤ 1 running `AnimationTrack` + ≤ 1 gesture track; procedural layer ≤ 4 `Motor6D.Transform` writes |
| Lights | one `PointLight` per lantern, `Enabled` only ≤ 70 studs (the brainrot FX rule) |
| Highlights | 0 on NPCs (the focus outline is the only one, reused) |
| Portrait | unchanged: it copies CFrames only during a conversation |

Migration rule: while old and new coexist, the old server scripts only ever see Humanoid rigs and the new driver only `NpcBody` — an NPC is one or the other, never both.

### 26. World-specific visual standards

| | World 1 — valley | World 2 — tundra | World 3 — Gardens | Trading — Skipper's Cove |
|---|---|---|---|---|
| Mood | friendly, adventurous, clean | harsh, cold, survival, worn | underground, war aftermath, patched, serious | prestige, flashy, social |
| Families | village, ranger, merchant | winter, engineer, merchant (winter cut) | survivor, miner, scavenger, castle, merchant (patched cut), noble (Keeper) | trader, noble, merchant (cove cut) |
| Palette accent | leaf green, berry, walnut, cream | ice blue, fur cream, charcoal, lantern amber | soot, rust, ochre, moss, bronze; **one** cyan crystal accent per district | sand (238,214,166), coral (255,116,96), turquoise (54,224,214), gold (255,196,64) `[doc]` |
| Faces | friendly / excited / worried (Gianluca) | tired / stern / worried | worried / tired / stern / battle-worn / old; no "excited" adults | friendly / suspicious (appraisers) / excited (crowd) |
| Signature material | leather | fur trim + frost on props (the existing tint idea, moved into the mesh colour) | patched cloth, old iron, lantern brass | gem gold, polished shell, turquoise glass |
| Motion | Villager / Merchant packs, upright | Survivor "warmHands" layer on everyone; slower gestures | Survivor pack; heads down; `lookUpward` reserved for Tino/Vespa beats | Merchant pack, faster, `countGems`/`beckon` heavy |
| Light | none | lantern on every Tier 2 | lantern or headlamp on every human; the only light in the frame | tiki-torch bounce only; gem props catch it (one Neon sliver max) |
| Same-merchant rule | base outfit | **winter cut** of the same five people | **patched cut**; Rocco's line "down here we call them ammunition" `[doc]` fits | not present (TW-01 roles instead) |

### 27. Trading World NPC style standard

- **Who they are:** appraisers, exchange clerks, collectors, harbour staff — people with money, not adventurers. Posture upright, chins up; the `Merchant` pack at 1.15 × speed.
- **Look:** `trader`/`noble` families; **one** gem accent per character (a brooch, a ring of gems on a visor, a gem-studded sash) — flashier than other worlds by *one* item, not three; polished-shell whites and turquoise glass; gold used as trim, never as the base cloth.
- **Props:** gem pouch on a tray, jeweller's loupe (a visor module), ledger, brass scale (a Tier 2 bespoke), spyglass for the harbour role.
- **Faces:** friendly for greeters, `suspicious` for appraisers (the squint reads as "checking your goods").
- **Scale:** standard 1.0; no giants — the six statues are the giants.
- **Placement, count and roles: TW-01's** (see answer E). NPC-01 delivers bodies into `ServerStorage.NpcStaging.Trading`, never into `TradingWorld`.

### 28. Recommended asset / performance budgets

| Scope | Budget |
|---|---|
| Human base (shared) | 7 shared limb meshes + 3 body types × 3 meshes = **16 unique meshes** for every human in the game |
| Hair/hat modules | ~20 meshes |
| Clothing overlays | ~45 meshes across 11 families |
| Props | ~20 meshes |
| Face decals | ≤ 12 sheets (8 stock + talking/closed + 2 Tier 3 bespoke) |
| Per NPC (Tier 1 / 2 / 3) | BaseParts ≤ 22 / 32 / 45 · unique meshes ≤ 3 / 6 / 10 · triangles ≤ 5k / 9k / 16k · emitters 0 / 2 / 6 · lights 0 / 1 / 1 · scripts **0 / 0 / 0** |
| Per brainrot character | template + 6 parts · ≤ 80 descendants |
| Per world (live at once) | ≤ 24 NPC bodies · ≤ 12 animated per frame · ≤ 1,200 NPC BaseParts total · ≤ 8 NPC lights |
| Animation | ≤ 40 uploaded clips total for launch (5 packs × ~5 + Tier 3 sets); Background layer procedural |
| Replication | 0 per-frame server writes; NPC models `ModelStreamingMode = Atomic` so a body never streams in half-dressed |
| Gate | every NPC runs a `NpcBudget.report` (the `BrainrotBudget` pattern, same fields + `motor6d`, `animationController`, `decals`) before it enters a world folder |

### 29. Recommended implementation order

| Phase | Work | Needs Studio? | Touches other lanes? |
|---|---|---|---|
| **1 (done)** | this report | no | read-only |
| **2a** | SR-Rig human base template (3 body types) + face plate + 8 face decals + `NpcLifeClient` + `NpcBudget` — all in `ServerStorage.NpcKit` / `ReplicatedStorage.NpcAnimations`; nothing placed | **yes** (a Studio window, asset import, decal upload) | no |
| **2b** | **Prototype 1 — Gianluca** on the new base, swapped in place behind his existing prompt; `StupidGianluca` name, `HumanoidRootPart › TalkPrompt` kept; old scripts skip him (no Humanoid) | yes | no |
| **2c** | The **five valley shopkeepers** on the base (merchant family, five signature garments/props); swapped inside their `NPC` child models; `NpcRigLife/BodyLife/PropLife` lose five rigs each | yes | Pete's shop UI lane reads nothing from the bodies — confirm |
| **2d** | **Prototype 5 — Trading merchant** built into `ServerStorage.NpcStaging.Trading` for TW-01 to place | yes | handoff to TW-01 |
| **3a** | Tundra + Gardens keeper **outfit variants** (winter cut, patched cut) — bodies only, stalls untouched | yes | Beast (paused) — swap inside `Hub.Stalls.*` after their move, or before with their ok; World 3 lane — Gardens copies |
| **3b** | **World 3 cast**: Prototype 3 (Vespa) then Ines, Ottavio, Keeper, Tino, Dario from the survivor/castle/noble families; Prototype 4 (Veteran) then Deserter, Ancient as brainrot characters | yes | World 3 lane owns placement + prompts; NPC-01 delivers bodies to `ServerStorage.NpcStaging.Gardens` |
| **4** | Tier 3: **Prototype 2 — Elder Tung (tundra)** after approval, then the valley Tung (keeping the chair + `Rocker` contract), Michael (after Beast's move), Bacon Head characters when canon exists | yes | approvals + Beast |
| **5** | Retire `NpcRigLife`, `NpcBodyLife`, `NpcPropLife`, `NpcIdle`, delete dead `DialogueConfig`; resolve the Chim double driver | yes | code review with the owner |

Every phase after 1 needs shared Studio time; none is started until you allocate a window.

---

## PART C — PROTOTYPES

### Prototype 1 — World 1 quest NPC: **Gianluca** (existing `GameWorld.StupidGianluca`)

| | Design |
|---|---|
| Existing / role | existing Tier 2 quest NPC (Secret Chim → Key); the flustered camp ranger who lost his pet |
| Tier | 2 |
| Proportions | `standard` body, scale 1.0; slightly forward-pitched torso (he is always mid-panic) |
| Silhouette | **floppy wide-brim ranger hat with one side pinned up** + an oversized scarf tail + the cane. From behind: hat + scarf + cane tip — unmistakable |
| Face | `worried` (big eyes, brows up-and-in) · talking variant · `excited` when the Chim is handed over (the dialogue's `Note == "key"` moment) |
| Hair / headwear | `messy: tousled` (dark chestnut) under the `hat: floppy brim (pinned)`, leaf green with a berry band |
| Outfit | **ranger** family: moss tunic, cloak yoke (short, cream), leather bracers, boot tops, tool belt; a **pocket with a Chim-sized empty collar hanging off it** (one small mesh — the story in one prop) |
| Prop | **walking cane with a bell** (his current cane, kept as an idea): `Right` grip, planted; the bell is the "Chim-caller". Coin flip retired |
| Idle personality | Villager pack, but the `weightShift` amplitude doubled and `lookAround` every 5 s instead of 12 — he is scanning for the Chim |
| Unique gesture | `ringBell`: lifts the cane, shakes it twice, peers left then right (2.4 s) — on `PromptShown` and once every ~20 s |
| Material / colour | moss (98,140,70), cream (238,226,200), leather (134,96,58), walnut seams (74,50,30); skin warm tan; hat leaf (108,160,80) |
| Asset needs | base body (shared), 5 overlay meshes (tunic, cloak yoke, bracer ×1 shared, boot top ×1 shared, tool belt), hat mesh, tousled hair mesh, cane+bell prop (2 parts), collar-on-belt (1), 3 decals; clips: `ringBell` + Villager pack |
| Performance | ~27 BaseParts · 8 unique meshes (5 reusable) · ≈ 6k tris · 0 emitters · 0 lights |
| Reusable | everything but the collar and the bell-cane: the ranger family, floppy hat, tousled hair, `worried` face, Villager pack |
| Contracts kept | `StupidGianluca` model name, `HumanoidRootPart` (anchored) with `TalkPrompt` inside, model stays under `GameWorld`; `RightHand` present (harmless once old scripts skip him) |

### Prototype 2 — World 2 important NPC: **Elder Tung (tundra)** — identity-preserving upgrade, **gated on your approval**

**Identity audit (what he *is* today):** the elder of the species "Tung Tung Tung Sahur" (a wooden log creature — the Mythic in the roster is "his own namesake"; the Legendary "Los Tungtungtungcitos" are his kin `[code][doc]`); wood-brown accent in both arcs; a **beard** (jaw/mid/fall/tip parts) and a mustache; sits in a rocking chair in the valley; in the tundra he lives in a 113-part hut, is "too old to go and look", has "listened to it for forty years", **hates brainrots**, builds a drill, and is the man whose sealed rocket World 3 reveals. He is never on screen in World 3 (survivors argue about him). Beast's lane keeps his body and moves it. World 3 audit: "No new Tung body" `[doc]`.

**Identity locks (unchanged in any redesign):** log body and bark colour; the beard and mustache; the wood-brown accent; seated in the valley (chair + `Rocker` geometry); the hut; the name; the voice.

| | Design (proposal) |
|---|---|
| Tier | 3 |
| Proportions | keep the log body's height (converse with a standard human in one portrait); widen the base — an old log settles |
| Silhouette | log + **long beard falling to the lap** + a **heavy fur-lined coat draped over the shoulders like a cape** (tundra only) + a **listening horn** on a strap (brass; the World 3 lane's "Elder's ear" relic is literally his) |
| Face | his own bark face, worn variant: heavier lids, one bark crack across the brow (`old` + `stern` reading); talking variant; one `grief` beat for the "forty years" line |
| Hair / headwear | beard module (grey-streaked bark-brown), a knit cap pulled over the top of the log (tundra) |
| Outfit | winter family cut for a log: fur-lined cape (1 mesh), a scarf, one **dented iron shoulder plate** (an armour remnant — he fought a war nobody in World 2 mentions) |
| Prop | the listening horn (`Left` waist grip) + his bat leaning against the chair/stool (species prop, on the floor, not held) |
| Idle personality | seated in the tundra too (a stool by the hearth) — `breathe` slow (4.2 s), head pitched down, a `warmHands`-like beard stroke every ~15 s; **no sine bob** (the reason his last idle was cut) |
| Unique gestures | `listen` (turns head, raises the horn to the ear, holds 2 s — before "There is a cave under us"); `standBack` (one arm out, for the drill Build beat); `pointDown` (cutscene pose) |
| Material / colour | bark (120,86,52) / dark bark seams (70,46,26) / beard (146,120,96) / fur (226,214,196) / iron (96,98,104) / brass (196,150,72) |
| Asset needs | rebuilt log body as ≤ 8 MeshParts on a 5-joint mini-rig (root, torso, head, two arms) so the beard/coat/horn can gesture; 3 face decals; 6 overlay/prop meshes; 3 clips + custom idle |
| Performance | ~24 BaseParts · ≤ 9k tris · 1 emitter (hearth-side breath vapour, off > 70 studs) · 0 lights (the hut's lantern already exists) |
| Reusable | the **beard module**, **fur cape**, **knit cap**, **stool** and the `listen` gesture (a Keeper/Ancient beat) |
| Contracts | model name `ElderTungTundra`, `PromptPart › TungCavePrompt` under `FrozenTundra`, **PrimaryPart added**, the DrillSite/DepthsPortal co-location untouched; body swapped in place only after Beast's move |
| Alternate if not approved | **Michael the eagle** (Tier 2+) — same treatment: species kept, voxel body re-baked to ≤ 10 MeshParts with a 4-joint mini-rig, the "borrowed things" nest as props, `alertGlance` head snaps kept from `NpcIdle`; after Beast's Eagle's Crag move |

### Prototype 3 — World 3 human survivor: **Vespa** (role `Scavenger`, name placeholder)

| | Design |
|---|---|
| Existing / role | proposed by the World 3 lane: relic trader, camps in the Fungal Hollow / Drowned Colonnade, knows where the Deserter hides, "still wants her helmet" |
| Tier | 2 |
| Proportions | `slight` body, scale 1.0, torso pitched 8° (survivor stance) |
| Silhouette | **no helmet** (every other survivor wears one — her running gag becomes her outline): a **headlamp on a bandana** + a **tall patched backpack with a pickaxe and rolled map lashed on** + a lantern low in the right hand. From behind: pack + pick handle + lantern glow |
| Face | `suspicious` (one brow low, a smirk) · talking · `tired` for red nights |
| Hair / headwear | `tied: headscarf-tied` (soot-black hair under an ochre bandana) + `headlamp band` module (brass lamp, no light — the lantern is the light) |
| Outfit | **scavenger** family: torn-hem jacket in two mismatched accents (rust left sleeve, grey right), arm wrap, knee pads, tool belt with three pouches, boot tops; **one cyan crystal shard** on the belt (the Gardens accent, her stock-in-trade) |
| Prop | lantern (`Right`, low, one `PointLight` ≤ 70 studs) + pickaxe on the back + rolled map on the pack |
| Idle personality | Underground survivor pack: `nervousGlance` frequent, `inspectGear` = lifts the lantern to look at *you*, never `lookUpward` (she stopped looking up years ago) |
| Unique gesture | `appraise`: sets the lantern down (one hand), turns a relic over in the other, sniffs, hands it back (3 s) — on hand-over beats |
| Material / colour | soot (52,50,48) / rust (150,74,44) / ochre (190,146,72) / patched grey (118,118,112) / brass (196,150,72) / crystal cyan (158,234,238) at ≤ 0.3 studs |
| Asset needs | base `slight` body; 6 overlays (jacket, arm wrap, knee pad ×1 shared, tool belt, boot top shared, bandana); headlamp band; backpack (bespoke, 1 mesh) with pick + map (2 shared props); lantern (shared); 3 decals; Survivor pack + `appraise` |
| Performance | ~31 BaseParts · 9 unique meshes (6 reusable) · ≈ 8k tris · 0 emitters · 1 light |
| Reusable | the entire **scavenger family**, headlamp band, backpack, lantern, `suspicious` face, Survivor pack — Ines/Ottavio/Dario/Tino are colour + hat + prop swaps on the same kit |
| Contracts | body delivered to `ServerStorage.NpcStaging.Gardens`; World 3 lane places it under `LushGardens.Npcs` with `ScavengerPrompt` in a `PromptPart`; display name stays theirs (`GardensNpcConfig.Roles.Scavenger.Name`) |

### Prototype 4 — World 3 brainrot veteran: **Il Vecchio Bombardiro** (role `Veteran`, name placeholder)

| | Design |
|---|---|
| Existing / role | proposed by the World 3 lane as "a one-winged old bomber crocodile who flew for Tung"; sits at the Whisperdeep mouth; "…Another one?" |
| Tier | 3 (brainrot) |
| Base | the game's own **Bombardiro Crocodilo** pack template (6 parts, 4,291 tris `[doc]`) — species instantly read |
| Silhouette | **one wing deleted**, the stump capped with a strut/splint; a **dented pilot's harness plate** across the chest; sits **low on a rubble plinth**, tail wrapped forward — a crocodile-plane that will never fly again |
| Face | the species face overlay, worn variant: cracked goggles pushed up (one part), heavier lids, jaw set (recolour + one goggle part) |
| Damage / age | desaturate 20 %; one **chipped snout** inset (dark), a **scorch** stripe on the tail (recoloured mesh role), a **medal** on the harness (tiny but ≥ 0.3 studs, brass) |
| Prop | a tin cup on the rubble (floor prop, not held); the strut |
| Pose | seated, weight on the wingless side, head turned to the tunnel — authored CFrames + `PoseAnchor` |
| Idle | procedural `breathe` (slow, 4.6 s) + `glance` snap toward the player on `PromptShown`; nothing else moves — stillness is the character |
| Unique gesture | a single **slow head turn + one-word exhale** (the `…Another one?` beat) — a 2-joint mini-rig (neck, jaw-goggle) or a pre-authored second pose swapped by the driver |
| Material / colour | species greens desaturated (90,110,86) / harness leather (112,84,52) / iron (96,98,104) / scorch (60,52,48) / brass (196,150,72) |
| Asset needs | template clone; 6 story parts (strut, harness plate, goggles, medal, snout chip, cup); worn face overlay; optional 2-joint rig |
| Performance | 6 + 6 = 12 BaseParts · ≈ 5k tris · emitters: the species' own kit at Legendary rate (or none) · 0 lights — **cheaper than a plot Mythic** |
| Reusable | the **veteran layer** (strut/splint, harness plate, goggles, medal, chip inset) fits any winged/limbed species — the Deserter (a different species) uses the same six-part vocabulary in a stolen-banner colourway; the Ancient uses only the age treatment + one crystal growth |
| Contracts | not in `BrainrotModels`, no `BrainrotBody` tag; placed by the World 3 lane with `VeteranPrompt`; species choice is theirs/Balkan's ("species TBD") — this is the treatment, applied to whichever species is chosen |

### Prototype 5 — Trading World merchant / exchange NPC: **the Appraiser** (new role, working name "Lorenzo", placeholder in the Italian register)

| | Design |
|---|---|
| Role | exchange clerk at the trade gazebo / market arc — values what you bring, runs the boards' "recent sales" patter. **Placement and final role: TW-01** |
| Tier | 2 |
| Proportions | `stout` body, scale 1.0, chest out, chin up |
| Silhouette | a **jeweller's visor with a fold-down loupe** + a **wide gem-studded sash** across a white vest + a **gem tray with a brass scale** held at the waist. From behind: visor + sash knot + tray edge |
| Face | `suspicious` at rest (the appraising squint) → `friendly` talking variant (he likes what you brought) → `excited` on a big trade |
| Hair / headwear | `short: side-part` (silver) under the visor module (turquoise glass) |
| Outfit | **trader** family: white vest (polished-shell), turquoise sash with **five** gem studs (the one flashy item), gold sleeve cuffs, coral neckerchief, cream trousers, sandal straps |
| Prop | gem tray + brass scale (`Left`, bespoke 3-part), gem pouch on the sash (`Waist`); a ledger tucked under the right arm |
| Idle personality | Merchant pack at 1.15 ×: `countGems` (picks gems off the tray one by one), `inspectMerchandise` (flips the loupe down, leans in), `beckon` on `PromptShown` |
| Unique gesture | `weighIt`: drops a gem on the scale, watches it settle, nods (2.8 s) — on trade-complete beats |
| Material / colour | shell white (245,250,250) / turquoise (54,224,214) / coral (255,116,96) / gold trim (255,196,64) / sand (238,214,166) / silver hair (200,204,210); ≤ 1 Neon sliver (the loupe glass) |
| Asset needs | base `stout` body; 5 overlays (vest, sash, cuff shared, neckerchief, sandal strap shared); visor module; tray+scale (bespoke); pouch + ledger (shared); 3 decals; Merchant pack + `weighIt` |
| Performance | ~30 BaseParts · 8 unique meshes (4 reusable) · ≈ 8k tris · 0 emitters · 0 lights |
| Reusable | trader family, visor module, tray/scale for every exchange clerk, `countGems` for every Cove merchant, `suspicious` face |
| Contracts | none yet — delivered to `ServerStorage.NpcStaging.Trading` with a `PromptPart` placeholder; TW-01 assigns the prompt name and position; dialogue lines go in a `TradingNpcConfig` the way `GardensNpcConfig` does |

---

## PART D — ANSWERS

**A. Which current NPC should be upgraded first?**
**Gianluca.** One standalone model, three name contracts (`StupidGianluca`, `HumanoidRootPart › TalkPrompt`, `GameWorld` parent), no stall, no other lane, no quest logic change, and the most obviously generic body in the first camp. He proves the human base, the face plate, the client driver and the "swap behind an existing prompt" migration in one go. The five valley shopkeepers follow immediately as one batch on the same base — that is where the "generic Roblox quest character" problem actually lives.

**B. Which current NPC should NOT be redesigned without another approval?**
**Elder Tung — both bodies.** He is the lore spine of three worlds, a roster species, sits in measured chair geometry in the valley, and his tundra body is in a rigid co-location contract Beast's lane is about to move. Prototype 2 is written as a proposal with identity locks, not a plan. Secondary holds: **Michael** (Beast's move), anything under **`LushGardens`** (active lane), any **Trading World** character (TW-01).

**C. Which prototype should define the global Skip Rocks style?**
**Prototype 1 (Gianluca)** defines the human style — proportions, face plate, overlay layering, prop language, pack-driven motion — because it is the one that ships first and gets seen most; every other human is a family/colour/prop swap on what he proves. **Prototype 4 (the Veteran)** defines the brainrot-character rule ("template + a six-part story layer"). Prototypes 3 and 5 are the world-language proofs; Prototype 2 is the Tier 3 proof.

**D. Which parts should be reusable across dozens of NPCs?**
The SR-Rig skeleton and the 16 base meshes (hands, feet, limbs, three torso types); the face-plate + 8 stock decals; the ~20 hair/hat modules; the 11 clothing families as overlay slots; the ~20-prop kit on standard grip attachments; the five animation packs and the procedural Background layer; the one `NpcLifeClient` driver with its LOD bands; the `NpcBudget` gate; and the unchanged portrait/outline/prompt/dialogue contracts (`NPC` child, `HumanoidRootPart`, `PromptPart`, accent pair). The brainrot "veteran layer" (strut, harness plate, goggles, medal, chip inset, age desaturation) is the reusable creature counterpart.

**E. What Trading World NPC roles should be coordinated with TW-01?**
Proposed for TW-01 to confirm, count and place (NPC-01 designs bodies only):
1. **Exchange appraiser / clerk** at the trade gazebo (Prototype 5).
2. **Market greeter / auctioneer** for the 12-booth arc (Tier 2, `beckon` heavy).
3. **Boards caller** by the three surfboards (TOP SALES / TOP TRADERS / RECENT SALES) — Tier 1 with one line.
4. **Index gatekeeper** at the coral `IndexGate` (the part is already reserved "for later prompt wiring").
5. **Crew recruiter** at the JOIN THE CREW chest and a **bottle-keeper** at the FOLLOW US bottle (Tier 1, social prompts).
6. **Harbourmaster** at the wave-portal arrival deck (Tier 2, spyglass; the first face in the Cove).
7. **Background collectors** (3–6 Tier 1 rich traders on the outer ring — the "prestige/social energy").
8. Whether the **six guardian statues** get a stonemason/curator character or stay pure scenery.
TW-01 owns count, placement and social spaces; NPC-01 needs from them: role list, prompt names, whether roles are one-off or per-booth, and any dialogue hooks (boards/PriceIndex).

---

## 30. What needs Studio inspection (blocked in this phase)

Stop-and-check list — none of these can be settled from the mirror, and none blocks Phase 2a design work:

1. **Maxwell**: world position and whether `Workspace.Maxwell` is the roster's static mesh.
2. **Tundra hub hierarchy**: confirm `FrozenTundra.Hub.Stalls.{Frost Eggs, Rime Charms, Stone Cache, Thaw Works, Frozen Haul}` are the parents of the `NPC` bodies and which `GameWorld.Tundra*Stall` prompt model each pairs with.
3. **Are the tundra/Gardens keepers re-dressed** (winter/patched bodies) or exact clones of the valley five? (`HumanoidDescription` ids, clothing parts.)
4. **What the R15 keepers actually wear**: body package (blocky vs Rthro), `Shirt`/`Pants` textures, catalog `Accessory` instances, dynamic-head `FaceControls` — one screenshot per merchant from gameplay distance.
5. **Which stock idle each keeper resolved** (`RigLifeIdle` attribute) — to show the owner the zombie/levitation problem concretely.
6. **Gianluca**: is he rig-complete (11+ R15 bones → woken by `NpcRigLife`)? Is he the 15th rig?
7. **Gardens egg stall**: keeper present or not.
8. **Valley `ElderTung`** part list + `RockingChair`'s five `Rocker` segments (the rock is measured from them).
9. **Chim**: does the double driver visibly jitter in Play mode?
10. **Animation upload**: which account can upload animations for experience `10549950910` (owner `BigFrogTerryBruh` vs Studio login `prohacks_sorry`) — decides between paths (a)/(b)/(c) in §13.
11. **`RegisterKeyframeSequence` test**: a 10-minute check that a stored `KeyframeSequence` plays on an `AnimationController` rig in a published build.
12. **Highlight and light counts** in each hub at rest (the 16-Highlight cap; NPC lantern budget).

---

## 31. Notes for the owner

- The **quickest visible win before any art exists** is a one-line change: replace `NpcRigLife`'s 27-id public idle pool with the three *default* idles only (`507766666/507766951/507766388`) — removes zombie/robot/levitation idles from merchants today. Not done (lane rule: no live changes); flagged for a yes/no.
- `DialogueConfig` is dead and can be deleted whenever a code pass is open.
- The `source-sync-audit` branch is the accurate mirror; this branch is based on `ui-foundation`. Phase 2 code should start from a fresh resync, not from either.
