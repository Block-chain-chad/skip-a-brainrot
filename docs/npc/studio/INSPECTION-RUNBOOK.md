# NPC-01 — Studio Inspection Runbook

**Status: PREPARED, NOT RUN.** Executes only inside an explicitly granted NPC-01 Studio window. Everything is read-only against the saved place; the three sandbox tests (§5) run in Play mode, where nothing persists.
**Tools:** the Studio MCP (`get_studio_state`, `search_game_tree`, `inspect_instance`, `execute_luau` print-only, `screen_capture`, `start_stop_play`). No `multi_edit`, no `insert_asset`, no property writes.
**Output:** results go to `docs/npc/studio/INSPECTION-<date>.md` + `captures/` on this branch.

Paths marked *(probable)* are inferred from the scripts (`StallPrompt.Bind` looks stalls up as direct children of `GameWorld`; `NpcBodyLife/PropLife` key bodies by their parent model's name); the first sweep confirms them.

## 0. At a glance

| | |
|---|---|
| **Total estimated time** | **≈ 60 min core** (Batches 1–4) · **+ 20 min** optional sandbox tests (§5) · worst case 90 min |
| **Edit-mode only** | Batches 1, 2, 3 (all data reads + composition screenshots), E-12 (Game Settings, human) |
| **Play mode required** | Batch 4: E-10 (Chim jitter), the *animated-state* screenshots (`NpcRigLife` only wakes rigs on server start); §5 sandbox tests E-11 and E-18-proxy |
| **Batched** | Batch 1 is **one** read-only `execute_luau` sweep (§6) that answers E-1, E-2 (counts), E-3, E-4, E-5, E-6, E-7, E-8, E-9, E-13 (counts), E-16, E-17 and the E-18 measurement in one print — ≈ 3 min runtime. Batch 2 is targeted follow-ups on the four priority objects only |
| **Priority order** | **E-2 → E-13 → E-17 → E-18**, then the rest |
| **Human-only item** | E-12 (which account can upload animations) — the owner checks Game Settings / Creator Dashboard; no MCP action |

## 1. Batch 1 — the read-only sweep (Edit mode, ≈ 5 min incl. reading the print)

Run the script in §6 once. It only prints. Then:

| # | Object | Studio path | Question it answers | Action | Measurement / capture | Phase 3 decision that depends on it |
|---|---|---|---|---|---|---|
| **E-2** | Gianluca | `Workspace.GameWorld.StupidGianluca` | Is he a complete R15 rig (≥ 11 bones → woken by `NpcRigLife`)? Which of his 37 parts are body vs crates/stall/cane? Are the props *inside* his model? Where does he face? | sweep + `inspect_instance` on the model (Batch 2) | part list with sizes; `HumanoidRootPart.CFrame` + `LookVector`; `TalkPrompt` `HoldDuration`/`MaxActivationDistance`/`RequiresLineOfSight`; attributes `RigLife*`, `BodyLife`, `PropLife` | **Swap plan for Prototype 1:** what stays (crates/stall re-parented to a sibling model), where the new HRP lands, whether the old scripts must be told anything (they must not: no Humanoid) |
| **E-13** | Bombardiro Crocodilo template | `ReplicatedStorage.BrainrotModels["Bombardiro Crocodilo"]` | Is the head / wing / tail its **own MeshPart**? Which part carries the face `SurfaceAppearance`? `HeightScale`? Which emitters to strip? | sweep + `inspect_instance` (Batch 2) | MeshPart names, sizes, colours, `MeshId`s; Motor6D list; `HeightScale`; emitter count | **Veteran Path A go/no-go** (owner condition): separate head/wing → glance + splinted-wing sag are possible; single mesh → breathe only, and the World 3 lane may prefer a forge species (Path B) |
| **E-17** | valley lodge counters | `Workspace.GameWorld.{SellStall,ShopStall,UpgradeStall,EggStall,CharmStall}` → parts `Counter` / `CounterTop`; keepers `…Stall.NPC` (Lil Miss: the HRP-owning model in `CharmStall`) | Counter-top height above the keeper's floor vs the new base's hand height (1.85 studs) | sweep | per stall: `topY − (HRP.Y − 3.0)` and the keeper's current hand Y | **Merchant batch (2c):** `stout` body on the existing floor vs a 0.4-stud riser vs counter change (counters are the shop lane's — if that is the answer, it becomes a request, not an NPC-01 change) |
| **E-18** | portrait framing (measurement half) | `ReplicatedStorage.Modules.MerchantDialog` (constants known: `RISE 0.50`, `SPAN 4.6`, fov 26); keepers as above | Do today's rigs put the head centre ≈ 1.45–1.50 above the HRP centre with a 2-stud-tall HRP? (SR-Rig is authored to 1.45 / 2.0) | sweep | `Head.Y − HRP.Y` and `HRP.Size.Y` for every keeper + Gianluca | **Confirms the kit's proportion table as-is**; if the live offset differs by > 0.15, `NpcRigSpec` moves the head, not the portrait. Visual proof is the §5 proxy |
| E-1 | Maxwell | `Workspace.Maxwell` → part `maxwell` › `PetPrompt` | Where is he; is he the roster's static mesh? | sweep | pivot; `MeshId` equality with `BrainrotModels.Maxwell` | his later upgrade only |
| E-3 | the five valley keepers | `Workspace.GameWorld.<Stall>.NPC` | body package, `Shirt/Pants`, accessories, `FaceControls`, loose-clothing part counts | sweep + Batch 3 screenshots | HD ids; clothing template ids; part counts | merchant batch (2c) |
| E-4 | tundra keepers + prompt models | `Workspace.GameWorld.FrozenTundra.Hub.Stalls.{Frost Eggs, Rime Charms, Stone Cache, Thaw Works, Frozen Haul}` *(probable)* and `Workspace.GameWorld.Tundra{Shop,Sell,Egg,Upgrade,Charm}Stall` | which body pairs with which prompt model; clones of the valley five or re-dressed? | sweep | hierarchy two levels deep; HD id comparison with E-3 | winter-cut batch (3a); nothing moves (Beast's lane) |
| E-5 | Gardens keepers | `Workspace.GameWorld.Gardens{Shop,Sell,Egg,Upgrade,Charm}Stall` *(probable; world folder is `GameWorld.LushGardens`)* | 4 vs 5 rig-complete keepers — egg-stall keeper present? | sweep | bone counts | patched-cut batch (3a) |
| E-6 | every rig with attribute `RigLifeIdle` | (sweep) | which public idle each keeper resolved | sweep | id list | evidence for the interim one-line pool change (owner decision, not Phase 3) |
| E-7 | valley Elder Tung + chair | `Workspace.GameWorld.ElderTung`, `Workspace.GameWorld.RockingChair` | part list, `Rocker` segment count/tilts, beard part names | sweep | list only | none now (deferred) |
| E-8 | tundra Elder Tung | `Workspace.GameWorld.FrozenTundra.ElderTungTundra`, `…FrozenTundra.ElderHut` | 66-part structure, no PrimaryPart, pivot | sweep | list only | none now (deferred) |
| E-9 | Michael | `Workspace.GameWorld.FrozenTundra.Michel` | the 20 named groups, PrimaryPart `Body`, perch CFrame | sweep | list only | none now (Beast's move first) |
| E-16 | hubs at rest | valley lodge (0, 9.5, −260) · Warmhouse hub (−8000, 2005, −8305) · Gardens (8000, 1000, −8000) · Cove (8000, 2002, 8000) | live `Highlight` / `Light` counts within 200 studs of each | sweep | four counts each | NPC lantern budget (≤ 8 lights/world) |

## 2. Batch 2 — priority follow-ups (Edit mode, ≈ 10 min)

| # | Action | Capture |
|---|---|---|
| E-2 | `inspect_instance` on `StupidGianluca` (full descendant list); `search_game_tree` for any other model named like `Gianluca*` (crates/stall siblings) | paste the tree; note `PrimaryPart` |
| E-13 | `inspect_instance` on the Bombardiro template; if the template has a `BrainrotFxHost/Crown/Base`, list emitters per host | paste the tree; one `screen_capture` of the template posed in a ViewportFrame is *not* needed — the plot instance at any base will do in Batch 3 |
| E-14 *(only if E-13 says single-mesh)* | list `ReplicatedStorage.BrainrotModels` children with a `FxVersion`/forge origin whose MeshPart names include a wing/limb role; cross-check `ServerStorage.AuditBackups.*_PreForge_2026-09-17` | names only |

## 3. Batch 3 — composition screenshots (Edit mode, ≈ 15 min)

`screen_capture` with Studio in the foreground (render counters and captures freeze when it is minimised — the forge audit's rule). Camera moves in Edit mode are not saved content. Front and ¾ at **20 studs**, and one at **60 studs**:

| Subject | Path | Why |
|---|---|---|
| Gianluca | `GameWorld.StupidGianluca` | the "before" of Prototype 1 |
| Marco, Rocco, Enzo, Gino, Lil Miss | `GameWorld.<Stall>.NPC` | merchant batch reference; counter height visible in the 20-stud shot |
| one tundra keeper, one Gardens keeper | E-4 / E-5 paths | are they visibly re-dressed |
| a placed Bombardiro Crocodilo | any plot holding one (`search_game_tree` name match under `PlayerBases`), else the Cove statue at r138 | species read for the Veteran |
| Elder Tung ×2, Michael, Maxwell, Darrel bust, Chim | paths above | the global "visually belongs" baseline (not for redesign) |

Saved as `docs/npc/studio/captures/<subject>-<dist>-<angle>.png`.

## 4. Batch 4 — Play mode (≈ 10 min)

`start_stop_play` → Play. No edits; Play-mode state is discarded on stop.

| # | Object | Question | Action | Capture |
|---|---|---|---|---|
| E-10 | `GameWorld.SecretChim` | do the server (`NpcIdle`) and client (`GianlucaClient`) drivers visibly fight? | stand within 90 studs; watch 10 s; read `chim.CFrame` twice 1 s apart on the server console and on the client | note jitter yes/no; two CFrames |
| E-6 (live) | the five valley keepers | which stock idle is actually playing (the zombie/levitation evidence, moving) | 10-s watch; `RigLifeIdle` already printed by Batch 1 | one 5-s capture of the lodge row |
| animated "before" | Gianluca, the lodge row | how the current root motion + stock idle read in motion | watch | one capture each |

Stop Play.

## 5. Sandbox tests (Play mode, temporary, ≈ 20 min — optional this window)

Nothing persists after Stop. Requires `execute_luau` to reach the Play DataModel; if it cannot, these slip to the start of Phase 3 with no cost to any decision today.

| # | Test | Question | What is created (Play mode only, discarded on stop) | Decision |
|---|---|---|---|---|
| E-18 proxy | a 16-block proxy at the kit's sizes (C1.2) parented to `workspace` in Play, cloned into a ViewportFrame with the portrait's own numbers (`RISE 0.50`, `SPAN 4.6`, fov 26, camera off the root's `LookVector`) | does an SR-Rig body frame head-and-shoulders exactly as the current rigs do? | 16 Parts + 1 ScreenGui | confirms `NpcRigSpec` before any mesh is baked |
| E-11 | a 2-part rig with an `AnimationController`, a 1-s `KeyframeSequence` built in code, `KeyframeSequenceProvider:RegisterKeyframeSequence` on the client, `Animator:LoadAnimation`, check `track.Length > 0` and motion | does the in-place no-upload track path work in this place (kit C7.7)? | 2 Parts + 1 KeyframeSequence + 1 LocalScript | only the *future* track migration; **not** required for the procedural prototypes |
| E-15 | *(Edit mode, needs the file dialog)* import a tiny 15-box test GLB from the forge exporter with the `npc` profile, inspect under `workspace.AuxScene`, **delete it** | does a multi-object GLB import as one Model with 15 named MeshParts? | one temporary import (a real write, then removed) — **ask before doing it** | Phase 3 base-mesh build; can be the first act of Phase 3 instead |

## 6. The Batch 1 sweep (read-only; paste into `execute_luau`)

```lua
-- NPC-01 Batch 1 sweep -- PRINT ONLY. Reads properties; writes nothing.
local RS, WS, SS = game:GetService("ReplicatedStorage"), workspace, game:GetService("ServerStorage")
local R15 = { Head=1, UpperTorso=1, LowerTorso=1, HumanoidRootPart=1, LeftUpperArm=1, LeftLowerArm=1, LeftHand=1,
	RightUpperArm=1, RightLowerArm=1, RightHand=1, LeftUpperLeg=1, LeftLowerLeg=1, LeftFoot=1, RightUpperLeg=1, RightLowerLeg=1, RightFoot=1 }
local function v3(v) return v and ("(%.1f, %.1f, %.1f)"):format(v.X, v.Y, v.Z) or "nil" end
local function report(m, tag)
	if not m then print(tag, "MISSING") return end
	local c = { parts=0, mesh=0, motor=0, weld=0, acc=0, bones=0, lights=0, emit=0, hl=0, prompts=0, sa=0 }
	local hum, anim, hd, fc, ac
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then c.parts += 1; if R15[d.Name] then c.bones += 1 end end
		if d:IsA("MeshPart") then c.mesh += 1 end
		if d:IsA("Motor6D") then c.motor += 1 end
		if d:IsA("WeldConstraint") or d:IsA("Weld") then c.weld += 1 end
		if d:IsA("Accessory") then c.acc += 1 end
		if d:IsA("Light") then c.lights += 1 end
		if d:IsA("ParticleEmitter") then c.emit += 1 end
		if d:IsA("Highlight") then c.hl += 1 end
		if d:IsA("ProximityPrompt") then c.prompts += 1 end
		if d:IsA("SurfaceAppearance") then c.sa += 1 end
		if d:IsA("Humanoid") then hum = d elseif d:IsA("Animator") then anim = d elseif d:IsA("HumanoidDescription") then hd = d
		elseif d:IsA("FaceControls") then fc = d elseif d:IsA("AnimationController") then ac = d end
	end
	local attrs = {}
	for k, val in pairs(m:GetAttributes()) do attrs[#attrs+1] = k .. "=" .. tostring(val) end
	local hrp, head = m:FindFirstChild("HumanoidRootPart", true), m:FindFirstChild("Head", true)
	print(("[%s] %s | parts %d mesh %d bones %d motor6d %d welds %d acc %d prompts %d SA %d lights %d emit %d hl %d | hum %s anim %s HD %s FC %s AC %s | pivot %s | primary %s | attrs {%s}")
		:format(tag, m:GetFullName(), c.parts, c.mesh, c.bones, c.motor, c.weld, c.acc, c.prompts, c.sa, c.lights, c.emit, c.hl,
			tostring(hum ~= nil), tostring(anim ~= nil), tostring(hd ~= nil), tostring(fc ~= nil), tostring(ac ~= nil),
			v3(m:IsA("Model") and m:GetPivot().Position or m.Position), tostring(m:IsA("Model") and m.PrimaryPart), table.concat(attrs, ", ")))
	if hd then print("   HD head/torso/face/shirt/pants/hair/hat:", hd.Head, hd.Torso, hd.Face, hd.Shirt, hd.Pants, hd.HairAccessory, hd.HatAccessory) end
	if hrp and head then print(("   E-18: head.Y - hrp.Y = %.2f | hrp size %s | look %s"):format(head.Position.Y - hrp.Position.Y, v3(hrp.Size), v3(hrp.CFrame.LookVector))) end
end
local function parts(m, tag) if not m then return end; local t = {}
	for _, d in ipairs(m:GetDescendants()) do if d:IsA("BasePart") then t[#t+1] = ("%s%s %s"):format(d.Name, d:IsA("MeshPart") and "*" or "", v3(d.Size)) end end
	print(("   %s parts (%d): %s"):format(tag, #t, table.concat(t, " | "))) end
local gw = WS:FindFirstChild("GameWorld"); local ft = gw and gw:FindFirstChild("FrozenTundra"); local lg = gw and gw:FindFirstChild("LushGardens")

print("===== E-2 Gianluca"); report(gw and gw:FindFirstChild("StupidGianluca"), "E-2"); parts(gw and gw:FindFirstChild("StupidGianluca"), "E-2")
do local g = gw and gw:FindFirstChild("StupidGianluca"); local p = g and g:FindFirstChild("TalkPrompt", true)
	if p then print(("   TalkPrompt parent %s hold %.2f dist %.0f los %s"):format(p.Parent.Name, p.HoldDuration, p.MaxActivationDistance, tostring(p.RequiresLineOfSight))) end end

print("===== E-13 Bombardiro template"); local bm = RS:FindFirstChild("BrainrotModels"); local bomb = bm and bm:FindFirstChild("Bombardiro Crocodilo")
report(bomb, "E-13"); parts(bomb, "E-13")
if bomb then for _, d in ipairs(bomb:GetDescendants()) do
	if d:IsA("MeshPart") then print(("   mesh %s size %s color %s id %s SA %s"):format(d.Name, v3(d.Size), tostring(d.Color), d.MeshId, tostring(d:FindFirstChildOfClass("SurfaceAppearance") ~= nil))) end
	if d:IsA("Motor6D") then print(("   motor %s : %s -> %s"):format(d.Name, d.Part0 and d.Part0.Name or "?", d.Part1 and d.Part1.Name or "?")) end
	if d:IsA("ParticleEmitter") then print(("   emitter %s on %s rate %.1f"):format(d.Name, d.Parent.Name, d.Rate)) end end end

print("===== E-3 / E-17 / E-18 valley keepers + counters")
for _, s in ipairs({ "SellStall", "ShopStall", "UpgradeStall", "EggStall", "CharmStall" }) do
	local stall = gw and gw:FindFirstChild(s); if not stall then print(s, "MISSING") continue end
	local npc = stall:FindFirstChild("NPC")
	if not npc then for _, d in ipairs(stall:GetDescendants()) do if d:IsA("Model") and d:FindFirstChild("HumanoidRootPart") then npc = d break end end end
	report(npc, "E-3 " .. s)
	local hrp = npc and npc:FindFirstChild("HumanoidRootPart"); local hand = npc and (npc:FindFirstChild("RightHand") or npc:FindFirstChild("LeftHand"))
	for _, d in ipairs(stall:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "CounterTop" or d.Name == "Counter") and hrp and (d.Position - hrp.Position).Magnitude <= 12 then
			local top = d.Position.Y + d.Size.Y / 2
			print(("   E-17 %s: counter top %.2f | floor(hrp-3) %.2f | counter above floor %.2f | hand.Y %s"):format(s, top, hrp.Position.Y - 3, top - (hrp.Position.Y - 3), hand and ("%.2f"):format(hand.Position.Y) or "?")) end end end

print("===== E-4 tundra"); if ft then local hub = ft:FindFirstChild("Hub"); local stalls = hub and hub:FindFirstChild("Stalls")
	if stalls then for _, m in ipairs(stalls:GetChildren()) do print("   Hub.Stalls child:", m.Name, m.ClassName); local npc = m:FindFirstChild("NPC") or m; report(npc, "E-4 " .. m.Name) end else print("   Hub.Stalls not found -- search_game_tree for 'Frost Eggs'") end
	for _, s in ipairs({ "TundraShopStall", "TundraSellStall", "TundraEggStall", "TundraUpgradeStall", "TundraCharmStall" }) do local m = gw:FindFirstChild(s); print("   prompt model", s, m and v3(m:GetPivot().Position) or "MISSING", m and #m:GetDescendants() or 0, "descendants") end end

print("===== E-5 gardens"); for _, s in ipairs({ "GardensShopStall", "GardensSellStall", "GardensEggStall", "GardensUpgradeStall", "GardensCharmStall" }) do
	local m = gw and gw:FindFirstChild(s) or (lg and lg:FindFirstChild(s, true)); if not m then print("  ", s, "MISSING") continue end
	local npc = m:FindFirstChild("NPC"); if not npc then for _, d in ipairs(m:GetDescendants()) do if d:IsA("Model") and d:FindFirstChild("HumanoidRootPart") then npc = d break end end end
	report(npc, "E-5 " .. s) end

print("===== E-6 RigLifeIdle sweep"); for _, m in ipairs(WS:GetDescendants()) do if m:IsA("Model") and m:GetAttribute("RigLifeIdle") then print("   ", m:GetFullName(), m:GetAttribute("RigLifeIdle")) end end

print("===== E-1 / E-7 / E-8 / E-9 / E-10"); report(WS:FindFirstChild("Maxwell"), "E-1")
do local mx = WS:FindFirstChild("Maxwell"); local body = mx and mx:FindFirstChild("maxwell"); local tpl = bm and bm:FindFirstChild("Maxwell")
	if body and tpl then local tm = tpl:FindFirstChildWhichIsA("MeshPart", true); print("   E-1 mesh match:", body:IsA("MeshPart") and tm and (body.MeshId == tm.MeshId)) end end
report(gw and gw:FindFirstChild("ElderTung"), "E-7"); parts(gw and gw:FindFirstChild("ElderTung"), "E-7 Tung")
do local ch = gw and gw:FindFirstChild("RockingChair"); report(ch, "E-7 chair"); if ch then for _, d in ipairs(ch:GetDescendants()) do if d:IsA("BasePart") and d.Name == "Rocker" then print(("   Rocker up.Y %.3f pos %s"):format(d.CFrame.UpVector.Y, v3(d.Position))) end end end end
report(ft and ft:FindFirstChild("ElderTungTundra"), "E-8"); report(ft and ft:FindFirstChild("ElderHut"), "E-8 hut")
report(ft and ft:FindFirstChild("Michel"), "E-9"); parts(ft and ft:FindFirstChild("Michel"), "E-9")
report(gw and gw:FindFirstChild("SecretChim"), "E-10")

print("===== E-16 highlights / lights within 200 studs of each hub")
local hubs = { Valley = Vector3.new(0, 9.5, -260), Warmhouse = Vector3.new(-8000, 2005, -8305), Gardens = Vector3.new(8000, 1000, -8000), Cove = Vector3.new(8000, 2002, 8000) }
local hls, lights = {}, {}
for _, d in ipairs(WS:GetDescendants()) do
	if d:IsA("Highlight") and d.Enabled then local a = d.Adornee or d.Parent; local p = a and (a:IsA("Model") and a:GetPivot().Position or a:IsA("BasePart") and a.Position); if p then hls[#hls+1] = p end
	elseif d:IsA("Light") and d.Enabled then local par = d.Parent; local p = par:IsA("BasePart") and par.Position or par:IsA("Attachment") and par.WorldPosition; if p then lights[#lights+1] = p end end end
for name, c in pairs(hubs) do local h, l = 0, 0
	for _, p in ipairs(hls) do if (p - c).Magnitude <= 200 then h += 1 end end
	for _, p in ipairs(lights) do if (p - c).Magnitude <= 200 then l += 1 end end
	print(("   %s: highlights %d lights %d"):format(name, h, l)) end
print("===== sweep done (nothing written)")
```

## 7. Exit conditions for the window

- Every Batch 1–4 line answered or marked "not found" with the `search_game_tree` result that replaced the probable path.
- Captures saved; `INSPECTION-<date>.md` committed on `npc-01-character-overhaul`.
- Play mode stopped; no instance left behind (E-15 only if you approved it in the window, and then deleted).
- The place is byte-identical to how it was found — `_MANIFEST.txt`-style check on the four NPC scripts is not needed because no script was opened for editing.
