# E — Studio Inspection Checklist (prepared; NOT run)

**Lane:** NPC-01 · 2026-09-19 · **Waits for an explicit NPC-01 Studio window.** Nothing here has been executed; other lanes hold the shared Studio session.

Ground rules for the window when it comes: **Edit mode, read-only** — every snippet below only reads properties and prints; no `SetAttribute`, no parenting, no property writes, no Play-mode toggles except E-10 (Play mode, still no edits). Results are pasted into `docs/npc/studio/INSPECTION-<date>.md` on this branch.

Blocking legend — **D** = blocks a prototype *design* decision · **I** = blocks *final implementation* only (design proceeds on the stated assumption) · **N** = evidence / calibration, blocks nothing.

## E0. Shared helper (paste once, read-only)

```lua
-- read-only dumper: class, name, part count, attributes, and the things NPC-01 cares about
local function npcReport(m)
	local parts, meshes, motors, welds, acc, hum, anim, hd, fc, lights, emit, hl = 0,0,0,0,0,nil,nil,nil,nil,0,0,0
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then parts += 1 end
		if d:IsA("MeshPart") then meshes += 1 end
		if d:IsA("Motor6D") then motors += 1 end
		if d:IsA("WeldConstraint") or d:IsA("Weld") then welds += 1 end
		if d:IsA("Accessory") then acc += 1 end
		if d:IsA("Humanoid") then hum = d end
		if d:IsA("Animator") then anim = d end
		if d:IsA("HumanoidDescription") then hd = d end
		if d:IsA("FaceControls") then fc = d end
		if d:IsA("Light") then lights += 1 end
		if d:IsA("ParticleEmitter") then emit += 1 end
		if d:IsA("Highlight") then hl += 1 end
	end
	local attrs = {}
	for k, v in pairs(m:GetAttributes()) do attrs[#attrs+1] = k .. "=" .. tostring(v) end
	print(("%s | parts %d meshParts %d motor6d %d welds %d accessories %d humanoid %s animator %s HD %s FaceControls %s lights %d emitters %d highlights %d | pivot %s | attrs %s")
		:format(m:GetFullName(), parts, meshes, motors, welds, acc, tostring(hum ~= nil), tostring(anim ~= nil),
			tostring(hd ~= nil), tostring(fc ~= nil), lights, emit, hl, tostring(m:GetPivot().Position), table.concat(attrs, ",")))
	if hd then print("  HD: Head", hd.Head, "Torso", hd.Torso, "Shirt", hd.Shirt, "Pants", hd.Pants, "Face", hd.Face, "Hair", hd.HairAccessory, "Hat", hd.HatAccessory) end
end
```

## E1. Inspections

| # | Object / NPC | What the mirror cannot tell | What to inspect (read-only) | Blocks |
|---|---|---|---|---|
| **E-1** | `Workspace.Maxwell` (+ part `maxwell`, `PetPrompt`) | world position; whether the body is the roster's static mesh (`ReplicatedStorage.BrainrotModels.Maxwell`) or a different asset; part count | `npcReport(workspace.Maxwell)`; compare `MeshId` of `maxwell` with the template's; note `PetPrompt` parent and `MaxActivationDistance` | I (his own later upgrade) |
| **E-2** | `Workspace.GameWorld.StupidGianluca` | exact composition of the 37 parts (which are body, which are crates/stall/cane); whether he is a complete R15 rig (11+ bones) and therefore woken by `NpcRigLife`; his `HumanoidDescription` / clothing / accessories; his pivot and `LookVector`; whether the crates/stall are *inside* his model (they would be lost on a swap) | `npcReport(...)`; list every BasePart name + size; `RigLife`, `RigLifeIdle`, `BodyLife`, `PropLife` attributes; `HumanoidRootPart.CFrame`; the `TalkPrompt` properties (`HoldDuration`, `MaxActivationDistance`, `RequiresLineOfSight`) | **I** for Prototype 1 (the swap must keep his facing, keep or re-parent the crates, and land the HRP where the prompt already works). Design assumption: body only is replaced; scene props stay |
| **E-3** | the five valley stalls `GameWorld.{ShopStall,UpgradeStall,SellStall,EggStall,CharmStall}` → child `NPC` (Lil Miss: HRP-owning model) | body package (blocky vs Rthro), `Shirt`/`Pants` textures, catalog `Accessory` instances, dynamic-head `FaceControls`, the 17-part loose clothing sets, counter-top heights vs hand height | `npcReport` on each `NPC`; print `Shirt.ShirtTemplate`/`Pants.PantsTemplate`; list parts named `CounterTop`/`Counter` with `Position.Y + Size.Y/2`; screenshot each from 20 and 60 studs | I (Phase 2c merchant batch) |
| **E-4** | `GameWorld.FrozenTundra.Hub.Stalls.{Frost Eggs, Rime Charms, Stone Cache, Thaw Works, Frozen Haul}` and `GameWorld.Tundra{Shop,Sell,Egg,Upgrade,Charm}Stall` | the exact pairing between the themed stall models (bodies) and the prompt models; whether the tundra keepers are clones of the valley five (same `HumanoidDescription` ids / same clothing) or re-dressed | print the hierarchy two levels down from `Hub.Stalls`; `npcReport` each keeper; compare HD ids with E-3 | I (Phase 3a winter cut) |
| **E-5** | `GameWorld.LushGardens` keepers (`GardensShopStall/UpgradeStall/CharmStall/SellStall/EggStall`) | 4 vs 5 rig-complete keepers — is the egg-stall keeper missing, incomplete, or not a rig | `npcReport` each; count R15 bone names | I (Phase 3a) |
| **E-6** | every NPC with attribute `RigLifeIdle` | which public-package idle each shopkeeper actually resolved (zombie / levitation / robot…) | `for _, m in ipairs(workspace:GetDescendants()) do if m:GetAttribute("RigLifeIdle") then print(m:GetFullName(), m:GetAttribute("RigLifeIdle")) end end` | N (owner evidence for the interim one-line pool change) |
| **E-7** | `GameWorld.ElderTung` + `GameWorld.RockingChair` | part list, the `Rocker` segments (count, tilt), beard part names, `NameAnchor`, `PromptPart`, PrimaryPart | `npcReport` both; list parts named `Rocker` with `CFrame.UpVector.Y` | N now (Tung deferred); I later |
| **E-8** | `FrozenTundra.ElderTungTundra` (+ `ElderHut`) | the 66-part `torso_rig` structure, no PrimaryPart, exact pivot; hearth/stool positions for a seated pose | `npcReport`; list top-level children | N now; I later |
| **E-9** | `FrozenTundra.Michel` | the 20 named groups, PrimaryPart `Body`, current perch CFrame | `npcReport`; list part names | N (Beast's move first) |
| **E-10** | `GameWorld.SecretChim` | whether the two drivers (`NpcIdle` server + `GianlucaClient` client) visibly fight | Play mode, stand within 90 studs, watch for jitter; `print(chim.CFrame)` twice 1 s apart from the server console vs the client | N (bug evidence) |
| **E-11** | *(test rig, in `ServerStorage`)* `KeyframeSequenceProvider:RegisterKeyframeSequence` | whether an in-place `KeyframeSequence` plays on an `AnimationController` rig from a LocalScript (the no-upload track path, kit C7.7) | build a 2-part test rig in `ServerStorage` (not Workspace), a 1-second `KeyframeSequence`, register on the client, `Animator:LoadAnimation`, check `track.Length > 0` and visible motion in Play mode; note that a *published* server test is a later step | N for the prototypes (procedural is the path); D for the future track migration |
| **E-12** | experience `10549950910` ownership | which account can upload animations (owner `BigFrogTerryBruh` vs Studio login `prohacks_sorry`); whether the experience is or can be group-owned | Game Settings › Basic Info (read); Creator Dashboard (owner) | N for the prototypes; D for the future track migration |
| **E-13** | `ReplicatedStorage.BrainrotModels["Bombardiro Crocodilo"]` | the visible MeshPart split (is the head its own part? the wings? the tail?), Motor6D structure to `FakeRootPart`, which part carries the `SurfaceAppearance` face, `HeightScale`, the emitter kit to strip, triangle budget headroom | `npcReport`; list MeshParts with `Name`, `Size`, `Color`, `MeshId`, `SurfaceAppearance` presence; `GetAttribute("HeightScale")` | **D** for the Veteran's *motion detail* (glance/sag need separate head/wing parts) and the Path A/B call; the treatment itself stands either way |
| **E-14** | forge-baked species with a separable wing/limb role (only if the World 3 lane prefers Path B) | which in-house bodies have a wing/limb as its own colour role | for each model with attribute `FxVersion`/forge origin: list MeshPart names; cross-check the Part originals in `ServerStorage.AuditBackups.*_PreForge_2026-09-17` | I (Path B only) |
| **E-15** | `File › Import 3D` round trip for a 15-object GLB | that a multi-object GLB imports as one Model with 15 named MeshParts (names preserved), scale 1 stud = 1 unit, `RenderFidelity Automatic` | import a tiny 15-box test GLB produced by the forge exporter with the `npc` profile; inspect the result under `workspace.AuxScene`; delete the test import afterwards (this is the one write: removing our own test object) | I (Phase 3 build of the base meshes) |
| **E-16** | each hub at rest (valley lodge, Warmhouse, Gardens hub, Cove) | live `Highlight` count (16 rendered cap) and `Light` count, so NPC lantern budgets are real | `#CollectionService`-free scan: count `Highlight` and `Light` descendants of `workspace` with `Enabled` | N (budget calibration) |
| **E-17** | valley lodge counters (`SellStall`, `ShopStall`, `UpgradeStall`, `EggStall`, `CharmStall`) | counter-top height relative to the floor the keepers stand on (the tundra measurement was 8.58 vs shoulder 8.62 `[code: NpcPropLife]`) — the new base has hands at 1.85 studs above its feet | print `CounterTop`/`Counter` top Y minus the keeper's `HumanoidRootPart.Position.Y − 3` | I (Phase 2c: whether merchants get a `stout` body on a riser, or the counters are the fix) |
| **E-18** | `MerchantDialog` portrait against an SR-Rig proxy | that a body with head centre 1.45 above the HRP frames head-and-shoulders exactly as today's rigs do | first-window test: a 16-block proxy at the kit's sizes in `ServerStorage`, cloned into a ViewportFrame with the portrait's own numbers (`PORTRAIT_RISE 0.50`, `SPAN 4.6`, fov 26 `[code]`) — no live NPC touched | I (Prototype 1 swap) |

## E2. Screenshots to take in the same window (N — the "visually belongs" check)

Every talking NPC from **20 studs** and **60 studs**, front and 3/4, in Play mode: Elder Tung ×2, Michael, Gianluca, Maxwell, the five valley keepers, one tundra keeper, one Gardens keeper, the Darrel bust, one Cove statue. Saved to `docs/npc/studio/captures/`. These are the "before" column for every prototype review.

## E3. Ordering (so the window is short)

1. E-2, E-3, E-17, E-18 (Prototype 1 implementation set) — ≈ 15 min.
2. E-13, E-14 (Veteran design set) — ≈ 10 min.
3. E-4, E-5, E-6, E-16 (batch/evidence set) — ≈ 10 min.
4. E-11, E-15 (pipeline tests) — ≈ 15 min.
5. E-1, E-7, E-8, E-9, E-10, E-12 (deferred characters + account) — ≈ 10 min.
6. E2 screenshots — ≈ 15 min.

Nothing in this list changes the place. The only object created is the E-11/E-15/E-18 test rig in `ServerStorage`/`AuxScene`, removed at the end of the window.
