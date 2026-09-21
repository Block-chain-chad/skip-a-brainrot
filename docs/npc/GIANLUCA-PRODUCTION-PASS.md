# NPC-01 — Gianluca production pass (disk-side; no Studio)

**Lane:** NPC-01 · **Branch:** `npc-01-character-overhaul` · 2026-09-20
**Scope honoured:** Gianluca only. No Trading World, no other NPCs, no unrelated systems, no Studio (the dedicated window has not been opened), no live script edited, nothing pushed or merged. The approved V2.5 model is untouched — this pass adds the behaviour and voice around it.

## 1. What was inspected

**The character the kit builds** (`NpcForge.Build("Gianluca")` from `NpcShells/Gianluca_V25` on the `p2` profile): root `StupidGianluca` (the live name contract), anchored `HumanoidRootPart` at y 3.0 with the feet on y 0, 15 slot MeshParts on 15 Motor6Ds, mesh face (7 parts on `FaceJoint`s), `Hair` / `Outfit` / `Props` folders (spear gripped and planted in the right hand), tight `Collider` in the `NpcBody` group, tag `NpcBody`, attributes `NpcId NpcRig NpcTier=3 NpcPack=Veteran NpcFace=serious NpcShells NpcHeadOffset=1.575 NpcBodyType=p2`. 43 parts / 19 welds / 22 Motor6D / 7 bespoke / 4,188 tris, PASS vs Tier 3. Forward is −Z; the portrait line is the HRP (unchanged) with the head centre 0.13 higher than v1.

**Live scripts that touch him** (read from the `source-sync-audit` mirror, not modified):

| Live file | What it does today | Status after this pass |
|---|---|---|
| `StarterPlayerScripts/GianlucaClient` | waits for `GameWorld.StupidGianluca › HumanoidRootPart › TalkPrompt`; on trigger shows **hardcoded shouting lines** ("ARRRGGGGHHHH!!!!! IM SO STUPID!!", "GRAZIE, bambino!!") through `MerchantDialog.Show`; drives the Secret Chim quest over `GianlucaTalk` / `GianlucaState` remotes; hides the Chim on "found"; bobs the Chim collectible | **drop-in replacement authored in the kit** (`game-src/npc-kit/StarterPlayer/StarterPlayerScripts/GianlucaClient.client.lua`): identical remotes, state machine, Chim hide and bob; every line now comes from data through `NpcTalk`; installed only at the live swap |
| `ServerScriptService/Modules/GianlucaQuest` | server quest: `data.ChimQuest` 0–3, `startQuest` on a bare `GianlucaTalk`, `handOver` on `"handover"`, notes `key / found / hint` | untouched; the new client speaks the same protocol (tested) |
| `ReplicatedStorage/Modules/MerchantDialog` | the game's single NPC dialogue box: `Show(name, lines, accent, onDone, anchor, label, opts)`, typewriter, the NPC's own model as portrait framed on `HRP + 0.5×HRP.Size.Y`, walk-away at 24 studs, respawn/death failsafes | **reused as the UI** (per the brief); nothing new built |
| `StarterPlayerScripts/NpcFocusClient` | one shared `Highlight` outline on whatever prompt you walk up to (targets the model owning the `HumanoidRootPart`) | reused as-is — it will outline the V2.5 body |
| `ReplicatedStorage/Modules/DialogueConfig` | `NPCS.Gianluca = { Name = "stupid gianluca", Lines = {"AAARGGGHHH!!! I CANT FIND MY CHIM!!!"} }` — no live consumer found in the mirror | leave; note the stale name for the swap-day cleanup |
| `ServerScriptService/NpcBodyLife` (server) | **keyed by name** `["StupidGianluca"]`: drives the anchored HRP through a ±28° yaw sine + a 0.05 bob every frame near players ("Gianluca is bored") | **must skip the V2.5 body** (see §5) |
| `ServerScriptService/NpcPropLife` (server) | **keyed by name** `["StupidGianluca"]`: spawns a **coin** prop and tosses it from his hand every frame | **must skip the V2.5 body** (see §5) |
| `ServerScriptService/NpcIdle`, `NpcRigLife` | explicitly exclude Gianluca / only touch Humanoid rigs | no effect on the kit body (no Humanoid) |

**Kit architecture already covering the brief:** `NpcLifeClient` (one Heartbeat for every kit NPC, inert with no tag) → `NpcLife` (registry from `CollectionService`, LOD bands per tier, idle layers, gestures, prompt hooks from `ProximityPromptService`, dialogue hook from `MerchantDialogUI.DialogRoot.Visible`, face timers, reactions) → `NpcMotionConfig.Packs.Veteran` (slow breathe 3.8 s, weight shift 9 s / 3°, deliberate looks 7 s / 18°, `slowLook`, `shoulderRoll`, restrained talk gestures, greet `nodGreet`, reaction `warMemory`) → `NpcFaceConfig` (eight states, blink, gaze, talk mouth). Tracking is client-local: each player's client turns the head toward *that* player, so with several players nearby nothing spins — the server-side body never moves.

## 2. What was complete before this pass

Model, rig, materials data, budgets, the Veteran idle (breathing, weight shifts, head movement, blinking, posture adjustment, left-hand sway while the right rests on the spear), prompt-driven greet + head tracking with a 30° cap and smoothing, talking state (mouth, restrained gestures, eye contact), walk-away/timeout, the `warMemory` reaction, the Chim quest server logic.

## 3. What this pass added (smallest clean set)

| File | Role |
|---|---|
| `ReplicatedStorage/Modules/NpcKit/NpcDialogue/Gianluca.lua` — **NPC DATA** | name, role, accent (tarnished brass / iron), prompt values to verify, 3 greetings · 3 returning · 4 lore · 2 guidance lines with tags (`war` → `warMemory` reaction, `clasp` = the Elder Tung clue, `mentor`), the existing Chim quest re-voiced (offer / searching / holding / done + the server notes), future-quest hooks (`veteranChallenge trainingObjective warRelic tungStory secretHint`, `persistMet`) and an empty `sets` table a quest fills per stage |
| `ReplicatedStorage/Modules/NpcKit/NpcTalk.lua` — **NPC LOGIC** (pure) | `Next(dialogue, memory, ctx)` → one conversation (`lines`, `label`, `action`, `reaction`, `kind`); deterministic: a stable greeting per player, returning lines in turn, lore heard once each before any repeat, guidance every third visit, the Chim stages first; `Note()` for server notes; `Remember()` per shown conversation |
| `StarterPlayer/StarterPlayerScripts/GianlucaClient.client.lua` — glue (drop-in) | the live client with the dialogue branch replaced by `NpcTalk`; sets `NpcReaction` on the model when a war line is spoken; ignores repeat presses while the box is open; one prompt connection |
| `NpcLife.lua` | **approach acknowledgement**: inside the tier's track range but before the prompt the head turns a third of the way (`track.approachWeight`), with 2 studs of hysteresis at the range edge; prompt → 0.7, talking → 1.0, always eased (`smooth`) and capped (`maxTurn` 30°) — no snap, no 180° |
| `NpcMotionConfig.lua` | Veteran `track.smooth` 0.35 → 0.6 s, `approachWeight` 0.35 |
| `tools/npc_kit/lint.py` | the "kit never requires MerchantDialog" rule now exempts the one live drop-in that already did |
| `tools/npc_kit/tests/test_gianluca_production.py` | 8 tests (§6) |

**Dialogue (first pass, for owner review):**

- Greetings — "You carry yourself like someone who hasn't learned fear yet." · "New face. This valley gets a few. Most don't stay long enough to be worth knowing." · "Don't stand behind me. Old habit. Nothing personal."
- Returning — "Back again? Good. Means you survived something." · "Still in one piece. That puts you ahead of most." · "The river's louder today. Stay if you like. I'm not going anywhere."
- Lore — "Tung and I once stood where no sane man would have stayed. We stayed anyway." (war) · "People remember the victory. They rarely remember what it cost." (war) · "This clasp? Older than you. It meant something, once. Maybe it still does." (clasp) · "The old army marched through here. You'd never know it now. Grass forgets faster than men." (war)
- Guidance — "Keep your eyes open. The world usually warns you before it hurts you." · "Skip your rocks with intent. A throw with no purpose teaches you nothing."
- Chim quest, re-voiced (mechanics unchanged) — offer: "I lost something. A Chim. Small, quick, too clever for its own good. It slipped its collar somewhere along the shore." / "Find it and bring it here. I'll make it worth your while." → **I'LL LOOK ▶**; searching: "Still out there. Check the water's edge. It never strayed far from the sound of the river."; holding: "That's him. Hand him over. Gently." / "Take this key for the trouble. It opens something I no longer need." → **HAND OVER THE CHIM ▶**; done: "You brought him back when you didn't have to. I don't forget that."; key note: "The key. It's old, and it's yours now. What it opens is your business."

A conversation is two or three lines. First meeting = greeting + the Chim offer (so the live quest still starts by talking to him); while searching = returning line + the reminder; holding the Chim = handover; after the quest he becomes the lorekeeper: returning line + lore (war lines make him stop, tighten his grip and look away for a beat), guidance every third visit.

## 4. Behaviour, end to end (what a player gets)

1. **40 studs out:** idle only — slow breathing, weight onto the spear side, an occasional deliberate look, blinks, the left hand sways, the plated shoulder rolls now and then.
2. **24 studs (Tier 3 track range):** he notices — the head eases a third of the way toward you over about a second; standing on the edge does not flicker it.
3. **10 studs (the live TalkPrompt's range to verify):** the prompt appears, `NpcFocusClient` outlines him, he nods once (8 s cooldown per approach) and turns most of the way (30° cap, waist follows at 30 %).
4. **Interact:** `MerchantDialog` opens with his portrait, name and accent; he tracks fully, mouth moves in bursts, restrained gestures; a war line triggers the reaction. Repeat presses while the box is open do nothing. Walking past 24 studs (MerchantDialog) / the driver's talk range closes it.
5. **Leave:** tracking eases back to the idle; nothing accumulates (the 60-second drift test).

## 5. Requires Roblox Studio (manual review at the window)

1. **Exclude the V2.5 body from `NpcBodyLife` and `NpcPropLife`** before the live swap — both scripts match `StupidGianluca` by name and would yaw the anchored root ±28° and toss a coin in a veteran's hand. Smallest patch, either script: skip any model carrying the `NpcRig` attribute (or delete the two `["StupidGianluca"]` entries). Live-script edit → part of the STOP 5 swap plan, not this pass.
2. Replace `StarterPlayerScripts.GianlucaClient` with the kit's drop-in at the same swap (STOP 5/6), never before the body is live.
3. Verify the live `TalkPrompt`: `MaxActivationDistance` (~10), `HoldDuration` (~0.3), `RequiresLineOfSight` false, `ActionText` "Talk" — the prompt is kept, not recreated.
4. Portrait framing (E-18) with the V2.5 head at +1.575; the hood/spear must not crowd the frame.
5. Mobile: the prompt's touch button and MerchantDialog's tap-to-advance (existing systems; unchanged).
6. `DialogueConfig.NPCS.Gianluca.Name` still says "stupid gianluca" — no consumer found; rename or leave.
7. Performance in Play mode with the driver on (NpcLife is one Heartbeat for all kit NPCs; the client adds no loops).

## 6. Tests performed (harness, `python -m pytest npc_kit/tests` → **80 passed**; lint OK; forge fidelity 0.9999)

`test_gianluca_production.py`: dialogue shape and voice (counts, ≤ 120 chars, no shouting, banned words, no moon imagery, Tung + clasp referenced, prompt values, quest actions, hooks) · first meeting = stable greeting + Chim offer · the whole relationship walk (searching → handover → thanks once → lore rotation with guidance every third visit, war lines → `warMemory`, clasp/guidance → none, earlier-session players not greeted as strangers) · server notes → popups · approach: no tracking at 40 studs, a third at 14 studs eased in (first frame < 10 % of the settled turn), capped at 30°, hysteresis 24/26 · prompt: one nod per approach despite prompt flicker, 0.7 tracking with the prompt, 1.0 talking, walk-away ends talking · adopt/drop/re-adopt never leaks connections (2 attribute connections, cleared and re-made) · the drop-in client keeps every live contract string and never creates a prompt. Existing suites still cover idle drift, budgets, contracts, blink/talk, reactions.

Not testable off-line (listed in §5): Studio import, real prompt distances, portrait pixels, mobile input, frame timing.
