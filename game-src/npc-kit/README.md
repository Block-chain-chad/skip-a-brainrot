# game-src/npc-kit — NPC-01 kit sources (Step 0, disk-side)

Staging folder for the NPC-01 system, mirroring the DataModel paths the files
will occupy once installed (Phase 3, behind its STOP gates). Nothing here is in
Studio yet; `game-src/place-full/` stays the byte-exact mirror of the live place.

Extension convention (as `place-full`): `.lua` ModuleScript · `.client.lua` LocalScript · `.server.lua` Script.

| File | DataModel path when installed | Kind | Role |
|---|---|---|---|
| `ReplicatedStorage/Modules/NpcKit/NpcRigSpec.lua` | `ReplicatedStorage.Modules.NpcKit.NpcRigSpec` | data | SR-Rig v1: parts, joints (pivots → C0/C1), attachments, grips, body types, joint classes |
| `…/NpcFaceConfig.lua` | `…NpcKit.NpcFaceConfig` | data + `Resolve/Apply` | the 7-part cube face, expression table, blink/gaze/talk numbers; **`NpcFace` attribute is the public interface (D-3)** |
| `…/NpcLibrary.lua` | `…NpcKit.NpcLibrary` | data | Wave-1 assets: body segments (forge refs), hair/hat/beard, overlays, props — every non-body entry has a primitive `blockout` |
| `…/NpcFamilies.lua` | `…NpcKit.NpcFamilies` | data | clothing families = colour sets + body roles + default overlays |
| `…/NpcWorldThemes.lua` | `…NpcKit.NpcWorldThemes` | data | per-world palette shift / accent / overlay swaps (D-5 recurring merchants, world cuts) |
| `…/NpcMotionConfig.lua` | `…NpcKit.NpcMotionConfig` | data + `Resolve` | animation packs in semantic axes; gestures; `USE_TRACKS` hook for authored clips |
| `…/NpcLodProfiles.lua` | `…NpcKit.NpcLodProfiles` | data | tier bands, animated cap (12), off-screen rules, new-prompt defaults (D-8) |
| `…/NpcMotion.lua` | `…NpcKit.NpcMotion` | pure functions | hashing, curves, gesture evaluation, semantic-axis → CFrame, aim angles |
| `…/NpcLife.lua` | `…NpcKit.NpcLife` | driver core | registry (tag-driven), ranking/bands, pose writes (`C0`), face timers, prompt/dialogue hooks — services injected |
| `…/NpcCharacters/Gianluca.lua` | `…NpcKit.NpcCharacters.Gianluca` | recipe | Prototype A |
| `…/NpcCharacters/VeteranBombardiro.lua` | `…NpcKit.NpcCharacters.VeteranBombardiro` | recipe | Prototype B (conditional on E-13) |
| `…/NpcCharacters/Villager_Valley_01.lua` | `…NpcKit.NpcCharacters.Villager_Valley_01` | recipe | the 10-line Tier 1 reference |
| `StarterPlayer/StarterPlayerScripts/NpcLifeClient.client.lua` | `StarterPlayer.StarterPlayerScripts.NpcLifeClient` | LocalScript | wires NpcLife to the real services; **inert with no `NpcBody` tag (D-7)** |
| `ServerStorage/NpcForge.lua` | `ServerStorage.NpcForge` | build-time | `Build(recipeId, opts)` → staged model; `SwapLive` hard-gated (`STOP5` + `SWAP-LIVE`) |
| `ServerStorage/NpcBudget.lua` | `ServerStorage.NpcBudget` | build-time | `report` / `review` gate (doc F); blockout allowance declared by `NpcBlockout` |

## Invariants the tests enforce (tools/npc_kit)

- Plain Lua 5.1 syntax (Luau superset) so the whole kit runs under the harness; no `+=`, `continue`, type annotations, backtick strings.
- The runtime driver never scans the workspace, never creates instances, never writes `Transform`, never uses `math.random`, never talks to the server; one `Heartbeat` in the client.
- `NpcForge.Build` never creates a `ProximityPrompt`, never calls `SwapLive`, never modifies a `BrainrotModels` template (creatures are clones; the source is asserted unchanged), stages only under `ServerStorage.NpcStaging.<World>`.
- Every non-anchored part reaches an anchored root through joints/welds (`orphans == 0`); only the HRP (+ Collider) is anchored; no Humanoid; `CanQuery`/`CanTouch` false everywhere.
- Motion is absolute from the captured rest — a 60-second run leaves the root within its layer amplitude.

## Running the checks (no Studio)

    cd tools
    python -m pip install lupa pytest        # once
    python -m npc_kit.lint                   # compile + syntax subset + forbidden APIs + data cross-refs
    python -m pytest npc_kit/tests -q        # 42 tests: rig math, motion signs, forge builds, budget, driver, inert client, NPC forge profile
    python -m npc_kit.build                  # bake the standard body (tools/out/npc_body_standard, git-ignored) + render docs/npc/previews
    python -m npc_kit.v2.study               # V2 character art study (shells on the same skeleton; study data only, no Lua change) -> docs/npc/previews/v2
    python -m npc_kit.v2.study25             # V2.5 study: global tiers + old-veteran Gianluca (study data only, no Lua change) -> docs/npc/previews/v25

## Install order (Phase 3, gated — see docs/npc/phase2.5/H-phase3-execution-plan.md)

Step 7 (STOP 1c): `NpcKit` folder + modules, `ServerStorage.NpcForge/NpcBudget`, `ServerStorage.NpcStaging`, first `Build("Gianluca", { blockout = true })`.
Step 8 (STOP 2): `NpcLifeClient` — inert until a tagged body enters Workspace.
Step 13 (STOP 5/6): `NpcForge.SwapLive(staged, live, { gate = "STOP5", confirm = "SWAP-LIVE" })` — the only live change, with backup and one-call rollback.
