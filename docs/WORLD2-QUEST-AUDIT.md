# World 2 — Quest Audit (live Studio)

**Audited:** 2026-09-19 by BEAST (branch `world2-overhaul`), in live Studio: *Skip Rocks For Brainrots! [ALPHA!]*, PlaceId `78783087742939`, Team Create, Edit mode.
**Read-only.** Nothing in the place was changed, saved or published.
**Companions:** `docs/WORLD2-MASTERPLAN.md` (environment plan) and `docs/world2-topdown.svg` (map).

**Source-of-truth note.** The repo mirror (`game-src/place-full`) does **not** contain `TundraQuest`, `TundraQuestConfig`, `TundraQuestClient`, `CaveDrillClient`, `MichelQuest`, `MichelQuestConfig`, `MichelQuestClient`, `DevQuest`, `WorldProgression`, `WorldTravelConfig`, `IceFishingConfig` or `RodService`. Its copies of `TungQuest`, `TungQuestConfig`, `PlayerDataManager`, `Main`, `TeleportService` and `QuestTrackerClient` are stale (Jul 31 – Aug 9). Everything below was read from live Studio. Conflicts between live and older comments or mirrors are listed in §5.

---

## 0. The three quest identities, as found

| | **Elder Tung — World 2 arc** | **Eagle quest (Michael)** | **Nico the Angler** |
|---|---|---|---|
| Player-facing | Elder Tung | Michael the eagle, "EAGLES QUEST" | — (proposal, §3) |
| Code | `TundraQuest`, `TundraQuestConfig`, `TundraQuestClient`, `CaveDrillClient` | `MichelQuest`, `MichelQuestConfig`, `MichelQuestClient` | none exists |
| Role | Main story; gates World 3 | Side errand | Optional fishing / collection / exploration |
| Uses | Skipping (catch counts, tier counts, salvage), talk beats, two cutscenes | Mutations + a destructive hand-over | Ice fishing (proposed) |
| Tracker row | `TundraCave`, kind MAIN | `Michel`, kind ERRAND | `Nico`, kind SIDE (proposed) |
| State | Live, complete, 7 stages | Live, complete | Not built |

They already exercise different parts of the game. The Nico proposal keeps it that way: fishing only — no drill, no salvage, no World 3.

---

## 1. ELDER TUNG

### 1.1 One elder, two arcs

| Arc | World | Module | Ends with |
|---|---|---|---|
| 1 — "the cellar" (context; World 1 is Duck's) | Valley | `TungQuest` + `TungQuestConfig` | Cellar key → the way into World 2 |
| 2 — "the trials and the drill" | Frozen Tundra | `TundraQuest` + `TundraQuestConfig` | `CaveUnlocked` → the way into World 3 |

Two NPC models: `Workspace.GameWorld.ElderTung` (valley, sitting in the separate `GameWorld.RockingChair` model by the fishing hut, ~(−96, 7, 71), prompt `TungTalkPrompt`) and `Workspace.GameWorld.FrozenTundra.ElderTungTundra` (World 2).

### 1.2 Arc 1 (valley) — how a player earns World 2 (context only)

- **Ask:** hand over **12** brainrots — 5 Epic, 5 Legendary, 2 Mythic — picked from a grid, a few at a time. Items are destroyed. Only unplaced brainrots can be handed over.
- **State:** `data.TungQuest` = 0 not accepted / 1 collecting / 3 done (2 = "the rest is in your bag", derived live, never stored). Progress = `data.TungGiven {Epic, Legendary, Mythic}`, only counts up. `data.TungCatch` is vestigial.
- **Remotes:** `TungTalk` (C→S; `"offer"` / `"claim"` / anything else = accept), `TungState` (S→C).
- **Completion:** `data.TungPortalUnlocked = true` plus the runtime player attribute `HasCellarKey` (re-granted on join).
- **The door:** the cellar hatch (`CellarDoor` server + `CellarDoorClient`, drawn per player) needs `HasCellarKey` **and** one of Stupid Gianluca's keys (`data.Keys`, spent once). Behind it is `GameWorld.Portals.TundraPortal` at (−146, −16, 52), `Dest = "Tundra"`, which drops the player at `TeleportService.TUNDRA_POS` (−8000, 2006, −7975).
- **Tracker:** row `Tung`, kind SIDE ("Deliver brainrots to Tung 0/12").

### 1.3 Arc 2 (World 2) — stage table, exactly as authored

`data.TundraQuest` is an **index** into `TundraQuestConfig.Stages`: 0 = never spoken to, 1–7 = working on that stage, **8 = DONE** (`Config.DONE = Count + 1`).

| # | Id | Kind | Objective (live text) | Counter / target | Reward (paid on clearing) | Extra |
|---|---|---|---|---|---|---|
| 1 | `Trial1` | count | "Prove yourself: 300 catches" — *Catch %d/%d brainrots in the Frozen Tundra* | `Catches` → 300 | Cash 5,000,000 | |
| 2 | `Trial2` | count | "Prove yourself: 20 Mythics" — *Catch %d/%d Mythic brainrots* | `Mythics` → 20 | Cash 25,000,000 + 150 Darrels | |
| 3 | `Greeting` | talk | "Speak with Elder Tung" — the reveal (the cave, the drill) | — | — | talk beat |
| 4 | `Parts` | gather | "Salvage the drill parts" — *Skip rocks to salvage drill parts* | 5 Cog, 2 Gear, 1 Drill head (8) | — | salvage (§1.5) |
| 5 | `Build` | talk | "Bring the parts to Elder Tung" | — | Cash 50,000,000 | cutscene `DrillBuild` |
| 6 | `Fuel` | count | "Fuel the drill" — *Catch %d/%d Secret brainrots to fuel the drill* | `Secrets` → 10 | 300 Darrels | |
| 7 | `Activate` | talk | "Start the drill" | — | Cash 100,000,000 + 1 Key | cutscene `DrillStart`, **`Unlock = true`** |

**Arc totals:** 180,000,000 cash · 450 Darrels · 1 Key · `CaveUnlocked`.

"Darrels" is the code name of the emerald currency, paid through `EmeraldService.Award(player, n, "tundraquest")`; players read it as **Gems** (UI rename 2026-09-18, per `MichelQuestConfig`). "Key" is `data.Keys`, Gianluca's spendable key currency.

Dialogue lives in the config per stage (`Say`, `Nag`, `Done`) plus `Intro`, `Finished` and `Locked`.

### 1.4 What "trial tiers" are

Stages 1, 2 and 6 are **count** stages. One hook feeds them:
`ThrowHandler.revealCatch → pcall(TundraQuest.NotifyCatch, player, tier.Name, throwWorld)`.

- Only **skip-rock catches** count. Ice-fishing catches, egg hatches and quest grants never call the hook.
- Only catches with `throwWorld == "Tundra"` count (the BoundsGuard region the player threw from).
- `Catches` takes every tier; `Mythics` only `tier.Name == "Mythic"`; `Secrets` only `"Secret"` — tier names on the **Tundra** ladder (`RarityConfigTundra`: Mythic 580–700 studs, Secret 700–820).
- Counters **tick only while their own stage is live** and only go up. Catches made before accepting, or during another stage, never count; selling the brainrots never un-counts them.
- A finished count stage pays and advances **without** a visit (toast: "<Done line> — go and see Elder Tung."). Talk stages never auto-complete.

### 1.5 What "drill salvage" is

Stage 4 (`Parts`, kind `gather`), fed by the same `NotifyCatch` Tundra-skip hook:

- Each landed Tundra skip while stage 4 is live rolls `math.random() < PartChance` (**0.18**).
- **Pity:** `data.TundraDry` counts partless skips in a row; at `PartPity` (**10**) the next skip is a guaranteed part.
- The part is weighted by what is **still owed** (`rollPart`), so the single Drill head is not rarer than a Cog.
- Toast: "⚙ Your stone turned up a <Part>! (n/m)". Payload note `salvage`, extra `Salvage = <id>`.
- Expected ≈ 44 skips for all 8 parts; worst case bounded at 80.
- No world object is involved: parts are data only (`data.TundraParts`). The drill model that displays them is client-side (§1.8).

### 1.6 Talking to him (`TundraQuest.interact`)

1. If `data.TungPortalUnlocked` is not set → refuse with `Locked` ("Hmph. Come back when you have finished with my cellar.").
2. If DONE → `finished`.
3. If 0 → start stage 1 (`accept`).
4. Otherwise run `advance(allowTalk = true)`: completes the current stage if met; **one E-press clears at most one talk beat**; a cleared count stage can roll straight into a satisfied next one. Sends `advance` or `cutscene:<name>` with `Cleared = <stageId>`, else `nag`.
5. On reaching DONE the save is written immediately; a failure is `warn`ed.

Throttle: one talk per 0.25 s per player. On join: counters are normalised, `HasCaveAccess` is re-granted if DONE, `advance(false)` catches up retuned quotas, and state is pushed after 1 s.

### 1.7 Data fields (persisted; `PlayerDataManager` defaultData + Load backfill)

| Field | Type | Meaning |
|---|---|---|
| `TundraQuest` | number | stage index 0–8 |
| `TundraProgress` | `{Catches, Mythics, Secrets}` | count-stage counters |
| `TundraParts` | `{Cog, Gear, Drillhead}` | salvage, clamped to quota |
| `TundraDry` | number | partless streak (salvage pity) |
| `CaveUnlocked` | bool | `Config.RewardFlag`; also sent in `Snapshot` |
| `WorldsVisited.Tundra` | bool | back-filled true for anyone with `TundraQuest > 0` |

Runtime attribute (not saved): `HasCaveAccess` (`Config.KeyAttribute`).

### 1.8 Remotes, client, tracker

- **`TundraTalk`** (C→S, no payload) · **`TundraState`** (S→C). Both are created at runtime by the module.
- `TundraState` payload: `State, Step, Of, StageId, Kind, Title, Track, Met, Parts[{Id, Label, Plural, Have, Need}], Stages, Done, Unlocked, Note` (+ `Cleared`, `Salvage`). Notes: `accept, advance, cutscene:DrillBuild, cutscene:DrillStart, nag, finished, locked, progress, salvage, stagedone`.
- **`TundraQuestClient`** — conversation only (via `MerchantDialog`, wood-brown accent). Binds any `ProximityPrompt` named **`TungCavePrompt`** under `GameWorld.FrozenTundra` via `DescendantAdded` (streaming-aware). After a cutscene note it waits 6.5 s before speaking.
- **`CaveDrillClient`** — draws the drill **per client** from the pushed state, anchored on `FrozenTundra.DrillSite`:
  - stage ≥ 4 → *salvage* look (ice pad, one leaning upright, crate, scrap, tarp);
  - stage ≥ 6 → *built* (15-stud derrick, engine, the 5 cogs + 2 gears mounted, auger);
  - DONE → *running* (auger spins, steam, chips, a pitched-down hum `rbxassetid://3763470680`) **plus the shaft**: a green `PortalColumn`/`PortalPool`, ice shards and a "LUSH GARDENS" billboard at site-local **Z +12**. All of it is non-colliding, non-touching and non-querying — it is the *look* of the way down, not the way down.
  - Cutscenes take the camera for 6.4 s and shoot from the "seaward" side (site-local +Z, up to 26 studs out) back toward the rig with the hut behind it. **They need `DrillSite` streamed in** (`if not site then return end`).
- **Tracker:** `QuestTrackerClient` row `TundraCave`, kind MAIN, steps built from the config titles; the objective shows the parts list or the formatted `Track` line.
- **Dev:** `DevQuest` (`/tq …`, server-allowlisted) jumps stages without paying skipped rewards.

### 1.9 World objects and positions

| Object | Path | Position / notes |
|---|---|---|
| Hut | `FrozenTundra.ElderHut` (Model, 113 parts) | centre (−8162.7, 2011.6, −7735.2), 37 × 19 × 36; hearth, chimney, `SmokeAnchor`, lantern |
| NPC | `FrozenTundra.ElderTungTundra` (Model, 66 parts, node-built `torso_rig`) | (−8170.9, 2007.8, −7736.4); no PrimaryPart |
| Prompt | `ElderTungTundra.PromptPart.TungCavePrompt` | "Talk" / "Elder Tung", hold 0.3 s, range 12 |
| Drill anchor | `FrozenTundra.DrillSite` (invisible 2×1×2 Part) | (−8154.7, 2002.0, −7763.3), look (−0.3, 0, 1.0). Must stay a **direct child** of `FrozenTundra` |
| Shaft trigger | `GameWorld.Portals.DepthsPortal.PortalTouch` (11×14×11, invisible) | (−8151, 2003, −7775) = DrillSite local Z +12 |

`DepthsPortal.PortalTouch` attributes: `Dest = "Gardens"`, `RequiresFlag = "CaveUnlocked"`, `PlaceName = "the Lush Gardens"`, `LockedMessage = "🔒 The ice is solid here — Elder Tung's drill has not opened the way yet."`, `ComingSoonMessage = "🌿 The Lush Gardens are coming soon!"`, `RefuseX/Y/Z = (−8151.34, 2005, −7758.86)` (where a refused player is put back).

`NpcIdle` deliberately does **not** animate the tundra Elder Tung.

### 1.10 World 3 relationship (live)

- `TeleportService.passesLock` checks **ComingSoon first**, then `RequiresFlag`. `WorldTravelConfig` marks Gardens `ComingSoon = true` ("World 3 is BUILT but not open", 2026-08-19). **Today nobody can enter World 3**, including players who finished the arc: touching the shaft shows the coming-soon toast and moves them to the Refuse point. Their `CaveUnlocked` is kept for opening day.
- World 3 arrival: `GARDENS_POS` (8000, 1031, −6676). Return: `Portals.GardensReturnPortal` → `Dest = "Tundra"` → `TUNDRA_POS`.
- World 3 geometry exists (`GameWorld.LushGardens`, 42,902 parts) with its own plots 13–18. `WorldProgression` aliases Gardens to the Valley ladder.
- `TeleportService.WORLD_PLACE_IDS.Gardens = 0` ("entry is the Depths shaft").

### 1.11 Hardcoded coordinates

- None in `TundraQuest` / `TundraQuestConfig` / `TundraQuestClient`.
- `CaveDrillClient` is fully site-relative (`HOLE_Z = 12`; camera offsets up to 26 studs seaward, 18 sideways, 14 up).
- `DepthsPortal`'s `RefuseX/Y/Z` are absolute and must move with the site.

### 1.12 Observations

1. **Co-location is load-bearing.** The prompt (`TungCavePrompt`), `DrillSite` and `DepthsPortal` must stay together: the Build/Start cutscenes play at the site right after the talk and fail silently if the site has not streamed in.
2. The camera shots need about 30 studs of open space on the DrillSite's local +Z side, with the hut on its −Z side.
3. The Greeting beat promises "a CAVE, older than the ice" — the current hut site shows no hint of it. This is the biggest environmental-story opportunity in World 2.
4. The arc is pure skipping + talking — no fishing, no hand-over. Keep it that way.
5. The last stage pays `Keys = 1` (Gianluca's key currency), which is spent at the valley cellar; for a player already past World 2 it has no obvious next use. Design note, not a bug.

---

## 2. EAGLE QUEST — Michael

### 2.1 Identity

"Michael" to the player; `Michel*` in every identifier (`data.MichelQuest` and `data.MichelGiven` are persisted keys and deliberately never renamed). Quest label **"EAGLES QUEST"**, highlight gold (240, 200, 96), card accent gold (226, 176, 62) → (196, 146, 48). Personality: a shady bird stage-whispering a deal ("Psst." / "We never spoke. Forget my face.").

### 2.2 Objective, states, rules

- **Ask:** 5 × **"Tung Tung Tung Sahur"**, every one **MUTATED** (`entry.Mutation` any non-empty string — Golden through Angel, and any future mutation).
- **State:** `data.MichelQuest` = 0 not accepted / 1 collecting / 3 done. 2 ("you are carrying the rest") is derived live and never stored.
- **Progress:** `data.MichelGiven` (0–5), only counts up.
- **Hand-over:** the client sends exact **Uids** from a picker. The server re-validates: unplaced copies only (`PadIndex == nil`), accepted entries only, no duplicates, never more than is still owed, at most 5 per offer. No selection = auto-pick cheapest first (cash/sec × mutation multiplier). Banked income is drained to the player, then the items are destroyed.
- **Accept / offer:** `MichelTalk` with `"offer", {uids}`; any other action means accept. One action per 0.25 s.

### 2.3 Reward (on the hand-over that completes the fifth)

- **1,000 emeralds** via `EmeraldService.Award(player, 1000, "michel")` (players read "Gems").
- **"Pippo Olivardino"** via `BrainrotMover.Give` (placed on a free pad if there is one, else into the bag). The entry lives in the **valley** roster `BrainrotConfig` with `Weight = 0, QuestOnly = true`; this questline is its only source.
- Paid only after the items are gone and the state is 3, so a double click cannot pay twice. The save is written after **every** hand-over.

### 2.4 Remotes, client, tracker

- **`MichelTalk`** (C→S) · **`MichelState`** (S→C: `State, Step, Of, Have, Need, Left, Held, Placed, Ready, Done, Darrels, Note`). Notes: `quota` (fires once, on the false→true edge of "you have them all"), `gave`, `reward`.
- A server **watcher** recomputes a held/placed signature every 2 s and pushes state when it changes. That is how a fresh catch lights the quest up without `ThrowHandler` knowing about Michael.
- **`MichelQuestClient`** (649 lines): dialogue + picker panel; binds prompts named **`MichelPrompt`** under `GameWorld.FrozenTundra` (streaming-aware).
- **Tracker:** row `Michel`, kind ERRAND ("Bring Michael mutated Sahurs", "Finish the EAGLES QUEST").
- **Dev:** `/tq michel` in `DevQuest`.

### 2.5 World objects

| Object | Path | Position / notes |
|---|---|---|
| NPC | `FrozenTundra.Michel` (57-part voxel eagle, PrimaryPart `Body`) | (−7853.7, 2014.3, −8194.0), perched on the `Ruins.AbandonedOutpost` rubble in the far corner behind the hub dome |
| Prompt | `Michel.PromptPart.MichelPrompt` | "Talk" / "Michael", hold 0, range 18 |
| Idle motion | `ServerScriptService.NpcIdle` | animates him by the **path** `{"GameWorld", "FrozenTundra", "Michel"}` |

### 2.6 World dependencies and coordinates

- No world gate in the logic: nothing checks where the player is. Only talking needs his prompt.
- No hardcoded coordinates. The one path contract is `NpcIdle`'s.
- The source brainrot is a **valley Mythic / Tundra Rare** (Tundra weight 5,270 of 100,000 in Rare). Its mutation comes from the normal catch roll.

### 2.7 Observations

1. His spot is a dead-end corner walled in by ice cubes — the weakest location of any NPC in World 2.
2. The reward creature lives in the valley roster, so it shows on the Valley Index tab, not the Tundra one.
3. Currency naming is split three ways: `Darrels` in data and payloads, `EmeraldService` in code, "Gems" in UI.
4. This is the only quest that consumes the **mutation** system. Keep that identity.

---

## 3. NICO THE ANGLER — proposal

Nothing named Nico exists in the place (checked scripts, instances and remotes). Everything below is a proposal for Balkan's approval. **No code has been written.**

### 3.1 What he can build on (live)

- `IceFishingEvent`: a real-clock blizzard on the :00 every hour, **20-minute freeze**, 25 s warning. An ice sheet (CSG strips) over the Frozen Lake, **10 holes** (`HOLE_RADIUS 9`, walk-up reach 17), charge-to-cast with a server-issued **perfect band** (2× luck), a multi-step reel minigame (Common/Uncommon 1 click … Secret 4), and a real grant through `IceFishingConfig.RollCatch`.
- **23 Ice Fishing exclusives** in `BrainrotConfigTundra` (`Origin = "IceFishing"`, `Weight = 0`, `FishWeight` within rarity): Common 4, Uncommon 4, Rare 4, Epic 4, Legendary 2, Mythic 2, Secret 3. All 23 have models.
- Bite rarity weights at luck 1: Common 1000 · Uncommon 600 · Rare 340 · Epic 170 · Legendary 66 · Mythic 20 · Secret 5.
- **FishLuck pets** exist (Waddlebert, Blubberton, Tuskwald and Narwhalini Tuskarino from the Frost Eggs; Reed Duck, Elder Stag and Lucciolone Pantanini elsewhere). Pets are enabled.

### 3.2 Gaps he exposes (live)

1. **A landed fish notifies nothing.** `IceFishingEvent`'s grant calls no quest, season-pass, emerald or daily-quest hook. Nico needs one new hook — `pcall(NicoQuest.NotifyFish, player, fishEntry)` right after the grant, mirroring `TundraQuest.NotifyCatch`.
2. **Fishing exists 20 minutes per real hour.** A fishing questline can stall for up to 40 minutes. See §3.6.

### 3.3 Character

**Nico the Angler** — a small, wiry old ice-fisher in a patched parka with one enormous mitten and an ear-flap hat with a lure pinned to it. Forty winters on this lake. Talks to his tackle box. Treats every catch like a sea monster and every miss like a conspiracy. Has a nemesis: the lake's rarest fish, which he calls **"Big Balenone"**. Warm and funny, never an exposition robot. His tics are whispering about *what lives under the ice* and ending lines with a fishing "fact" he clearly made up.

Sample lines (draft):

- **Intro:** "SHH. You hear that? …No? The ice heard it. Something down there just rolled over in its sleep."
- **First Bite:** "Name's Nico. Forty winters, never once caught what I was fishing for. When the blizzard freezes the lake, the holes open. Bring me three. Any three!"
- **Nag:** "Fish don't come to people who stand still. Unless it's ice fishing. Then that's exactly what they do."
- **The Deep Hole:** "There's a place the ice forgot. Under the west glacier the water never freezes shut. I left lanterns. Light them, follow them — and don't tell the bird."
- **The One That Got Away:** "Big as a boat. Smiles like it knows your name. Land me a Secret — any Secret — and I'll finally sleep."

### 3.4 Questline (structure for approval — rewards are placeholders for Balkan)

| # | Title | Objective | Teaches | Mechanic (proposed) | Reward (Balkan decides) |
|---|---|---|---|---|---|
| 1 | **FIRST BITE** | Land 3 ice-fishing catches | blizzard timing, holes, charge, perfect band, reel | count, ticked by `NotifyFish` while the stage is live | small (e.g. gems) |
| 2 | **WHAT'S UNDER THERE?** | Land 5 **different** ice-fishing species | the exclusive pool, rarity = more reel clicks, FishLuck pets | species set recorded while the stage is live | small–medium |
| 3 | **THE DEEP HOLE** | Follow Nico's old lanterns to the hidden basin: light 3 lanterns in the canyon, reach the basin, read his note at the abandoned shanty | exploration | 3 walk-up lantern prompts (per-player state) + a note prompt in the basin | the basin itself; if approved, its permanent hole (§3.6) |
| 4 | **THE ONE THAT GOT AWAY** | Land any **Secret** fish | mastery (luck, perfect casts, FishLuck pets) | count of Secret-rarity fish reaches 1 | something memorable (options below) |

Q4 odds for Balkan (live weights): a Secret bite is ≈ 0.23 % per cast at luck 1, ≈ 0.85 % with a max rock (luck 10), ≈ 1.5 % with a perfect cast on top (luck 20), and higher with FishLuck pets — roughly 70–400 casts, one to several blizzards. If that is too hard, "Mythic or better" (Mythic weight 20) roughly quadruples the odds.

Q4 reward options: a **QuestOnly** fish brainrot (like Pippo Olivardino for Michael), a permanent fishing-luck bonus, a title/tag, a cosmetic rod, or permanent access to the basin hole. **No numbers are proposed** — that is Balkan's call.

### 3.5 Implementation shape (after approval)

- `NicoQuestConfig` (shared) + `NicoQuest` (server), the same shape as `TundraQuestConfig`/`TundraQuest`: a stage table with kinds `count`, `species`, `visit` and `talk`; counters count up, and only while their own stage is live.
- Data (proposed): `data.NicoQuest` (stage index), `data.NicoProgress {Fish, Secrets}`, `data.NicoSpecies {[name] = true}`, `data.NicoLanterns {[1..3] = true}`, `data.NicoHollow` (flag).
- Remotes: `NicoTalk`, `NicoState` (+ `NicoLantern` if lanterns are server-validated).
- Hook: one `pcall` in `IceFishingEvent`'s grant path. Nothing else in the fishing code changes for Q1, Q2 and Q4.
- Client: `NicoQuestClient` via `MerchantDialog`; tracker row `Nico` (kind SIDE); prompts bound by name under `GameWorld.FrozenTundra` (streaming-aware, like the other two).
- Dev: `/tq nico` verbs in `DevQuest`.

### 3.6 Open questions for Balkan

1. **The 20-minutes-per-hour problem.** Options: (a) accept it — the blizzard is an event; (b) the hidden basin's **permanent hole** works outside the blizzard for players who finished Q3 (needs an `IceFishingEvent` extension: a persistent hole registry gated by a player flag; today `startFishing` exits whenever the event is not active); (c) a Commons-only "stove hole" at Nico's lodge. **Recommendation: (b)** — it gives the hidden basin a gameplay reason to exist and turns Q3 into a real unlock.
2. Q2 counting: species caught **while the stage is live** (recommended; matches the "a trial is something you go and do" rule) versus anything already in the index.
3. Should fish **also** feed the season pass, the emerald "Catch" notify or daily quests? Today they feed none. Recommend a separate ticket, and keep Nico the only fish-quest consumer.
4. Rewards for all four quests.

---

## 4. Cross-quest checks

| Check | Elder Tung | Michael | Nico (proposed) |
|---|---|---|---|
| Counts skips | yes (Tundra only) | no | no |
| Counts fish | no | no | yes |
| Destroys items | no | yes (5 mutated Sahurs) | no |
| Needs a place | hut + drill site + shaft | his perch | lodge + canyon lanterns + hidden basin |
| Talk beats / cutscenes | 3 beats, 2 cutscenes | dialogue + picker | dialogue + lantern/note prompts |
| Gates progression | World 3 | nothing | the hidden basin only |

Three distinct identities: **skip mastery (Tung) · mutation trade (Michael) · fishing collection (Nico).**

---

## 5. Conflicts found (live vs comments and mirror)

| Where | Says | Live truth |
|---|---|---|
| `ThrowHandler` (`worldHasCatches` comment) | "World 2's roster is deliberately EMPTY" | 113 entries (87 throwable) |
| `BrainrotConfigTundra`, fish header | "ART: the 23 models are NOT imported yet" | all 113 Tundra entries have models (0 missing) |
| `IceFishingConfig.RollBite` comment | "STUB … when the exclusive fishing brainrots land" | `RollCatch` grants real fish since 2026-08-21 |
| `TundraQuestConfig.RewardFlag` comment | "Nothing reads it yet" | `DepthsPortal` gates on it (`RequiresFlag`) |
| `TungQuestConfig.RewardFlag` comment | "The portal and World 2 do not exist yet" | both exist |
| `TeleportService` header (Gardens) | World 3 is reached from a gate in the valley meadow | entry is the Depths shaft in the Tundra; no valley gate exists |
| `BoundsGuard` header | `TUNDRA_POS` is (−8000, 2006, −8000) | (−8000, 2006, −7975) |
| `EggConfig` (Tundra) | Frost Eggs keeper "has no name yet" (`Keeper = "Frozen Tundra Eggs"`) | its prompt reads "Gino the Egg Keeper" |
| Region boxes | `TundraAtmosphere` and `TundraBirds` reach z −6700 | `TundraWeatherFX` and `SnowFootprints` stop at z −7400: no snowfall or footprints over the north half of the lake |
| Repo mirror | `TungQuest` counts catches; `Main` has no Tundra modules | live `TungQuest` is a hand-over; live `Main` inits `TundraQuest`, `MichelQuest`, `DevQuest`, `RodService`, `IceFishingEvent` and more |
| BEAST memory (Aug) | "Frozen Haul = rock shop, Stone Cache = sell"; "no Bloom" | **Stone Cache = Rocco (rocks), Frozen Haul = Marco (sell)**; `Lighting.Bloom` is on (0.45, threshold 1.05) |
