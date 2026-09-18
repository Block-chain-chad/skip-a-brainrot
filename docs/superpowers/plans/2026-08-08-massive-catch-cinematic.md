# Massive Catch Cinematic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A ~10.7s kaiju-buildup-into-brainrot-chaos cinematic that plays when a throw rolls a MASSIVE size mutation, with a trimmed Huge variant, spectator broadcast, skip, quality tiers, and clean camera round-trip — replacing (comparison pending) the existing short `MassiveEmergence` for Massives.

**Architecture:** Server (`ThrowHandler`) moves the size roll to throw time and broadcasts a `MassiveCinematic` payload at flight start so every client can stage the final skip as "the bonk"; the grant still happens at landing, fully independent of the cutscene. Client is a folder of strict-Luau modules under `ReplicatedStorage.Modules.CatchCinematic` (Config + 8 rigs + Sequencer) conducted by a new `StarterPlayerScripts.CinematicClient`, coordinating with `CatchRevealClient` through a small Bridge module so the ordinary reveal chain stays untouched for every other catch.

**Tech Stack:** Roblox Luau (`--!strict` on new modules), Studio MCP (`execute_luau` Source writes), existing modules: RockDesign, SizeConfig, SoundKit, BrainrotModels, MassiveEmergence (kept), PullCeremony (kept).

## Global Constraints

- **Read `scratchpad/cinematic/RECON-NOTES.md` first.** It is the recon digest: pipeline map, interfaces, and the full gotcha list. Everything there is binding.
- The place is live Team Create. **Fetch fresh `.Source` immediately before every edit**; write whole modules via `.Source = [==[ ... ]==]` from `execute_luau` (Edit datamodel). `multi_edit` only in Edit mode, and only for small anchored diffs.
- `--!strict` on every NEW module. Do not add strict to existing files.
- **TweenService is allowed on BasePart Color/Size/Transparency/CFrame and GuiObject Size/Position/Rotation ONLY.** Hand-lerp on RenderStepped: camera FOV, Sound.Volume, ColorCorrection/Bloom/Blur values, UIScale, anything else. (Known place-specific gotcha.)
- `task.wait`/`task.delay`/`task.spawn` and `RunService.RenderStepped` only — no `wait()`, `spawn()`, `delay()`.
- Camera restore is non-negotiable: save CameraType, CameraSubject, FieldOfView, CFrame before touching; restore in a pcall-guarded `cleanup()` wired to EVERY exit path (complete, skip, death, respawn, error).
- Never mutate shared Lighting effects — create own ColorCorrection/Bloom/Blur instances named `CinematicCC`/`CinematicBloom`/`CinematicBlur`, destroy in cleanup.
- No Terrain sculpting. Client-local writes to `workspace.Terrain.WaterWaveSize/WaterWaveSpeed` are allowed for the glassy-still beat but MUST be saved+restored in cleanup.
- All cinematic world instances parent into ONE stage folder `Workspace.CatchCinematicStage` (created per run, destroyed in cleanup). Model clones: Anchored, CanCollide/CanQuery/CanTouch false, Massless true, Sounds neutered (Looped=false, Playing=false), Scripts/ProximityPrompts/BillboardGuis destroyed (copy PullCeremony's neuter loop).
- Every timing/color/sound/curve lives in `Config` — no magic numbers in sequence code. All sound ids go in `Config.ASSETS` with `-- TODO: replace` on true placeholders; prefer existing SoundKit ids (prefix `kit:`) as placeholders.
- The cinematic is 100% cosmetic. It must fail soft at every step: any decline → the ordinary reveal chain runs exactly as today. A cutscene must never eat a catch.
- Studio Play sessions write the REAL datastore. Any test that grants an item must record a baseline first, revert by DELTA, and verify the revert in a fresh session.
- HypeUI: own ScreenGui, `DisplayOrder = 55` (above PullCeremony's 50), `IgnoreGuiInset = true`, font FredokaOne.
- Tundra note: World 2's surface is sea ice (SurfaceY 1999). V1 plays the same water FX at the zone's SurfaceY in both worlds — accepted; ice-crack variant is future polish.
- Player-visible copy: the banner says "MASSIVE" (or "HUGE"); the name line uses `Sizes.Label(mutation, size, name)` so colour mutations show.

---

### Task 1: Config + Types + folder scaffolding

**Files:**
- Create: `ReplicatedStorage.Modules.CatchCinematic` (Folder)
- Create: `ReplicatedStorage.Modules.CatchCinematic.Config` (ModuleScript)
- Create: `ReplicatedStorage.Modules.CatchCinematic.Types` (ModuleScript)

**Interfaces:**
- Consumes: nothing.
- Produces: `Config` table consumed by every later task — field names below are the contract. `Types.CinematicPayload` type used by Sequencer/CinematicClient/ThrowHandler comment.

- [ ] **Step 1: Write the verification snippet first** (run via `execute_luau`, Edit): requires the module fresh (clone-reparent-require to dodge the stale cache), asserts every top-level key listed below exists with the right type, asserts every `BEATS` boundary is contiguous (`beat[i].t1 == beat[i+1].t0`), asserts `HUGE_TRIM` total < 6s, asserts every `ASSETS` value matches `^kit:%w+$` or `^rbxassetid://%d+$`. Expect: FAIL (module missing).
- [ ] **Step 2: Create the folder + both ModuleScripts** with full content. Config (strict) must contain exactly:

```lua
--!strict
-- CatchCinematic.Config — every tunable for the Massive catch cinematic.
-- DEBUG: set workspace attribute "CinematicTimescale" (number) during Play to
-- rescale every duration live (0.25 = quarter speed); read at sequence start.
local Config = {}

Config.DEBUG_TIMESCALE = 1.0

-- Which sizes trigger the cinematic from a REAL catch. Server reads this too.
-- "full" = 10.7s sequence, "trimmed" = HUGE_TRIM variant, "none" = existing behavior.
-- Huge stays "none" until the owner picks after the side-by-side demo.
Config.SIZES: { [string]: string } = { Massive = "full", Huge = "none" }

-- After the handoff beat: run the existing PullCeremony too? (comparison pending)
-- Live override for the demo: workspace attribute "CinematicCeremonyAfter" (boolean).
Config.RUN_PULL_CEREMONY_AFTER = false

Config.SPECTATOR_RADIUS = 250          -- studs from EndPos; beyond = ignore entirely
Config.SKIP = { delay = 1.0, holdSeconds = 0.45, exitFadeSeconds = 0.18 }

-- Beat boundaries in seconds from the bonk (t=0 = the final skip contact).
Config.BEATS = {
	{ name = "bonk",     t0 = 0.00, t1 = 0.35 },
	{ name = "travel",   t0 = 0.35, t1 = 1.60 },
	{ name = "dread",    t0 = 1.60, t1 = 3.20 },
	{ name = "silence",  t0 = 3.20, t1 = 3.65 },  -- DO NOT shorten or soften
	{ name = "eruption", t0 = 3.65, t1 = 4.50 },
	{ name = "rise",     t0 = 4.50, t1 = 6.50 },
	{ name = "hype",     t0 = 6.50, t1 = 9.00 },
	{ name = "handoff",  t0 = 9.00, t1 = 10.70 },
}
Config.SECOND_BONK_T = 5.6

-- Trimmed Huge cut (~4.3s): no silence, no hype. Same beat names, new bounds.
Config.HUGE_TRIM = {
	{ name = "bonk",     t0 = 0.00, t1 = 0.30 },
	{ name = "travel",   t0 = 0.30, t1 = 1.00 },
	{ name = "dread",    t0 = 1.00, t1 = 1.80 },
	{ name = "eruption", t0 = 1.80, t1 = 2.40 },
	{ name = "rise",     t0 = 2.40, t1 = 3.60 },
	{ name = "handoff",  t0 = 3.60, t1 = 4.30 },
}

Config.CAMERA = {
	fovBase = 70, fovPunchHi = 95, fovPunchSettle = 78, fovPunchDur = 0.5,
	outboundHeight = 6,            -- studs above surface on the low fly-out
	hoverDistMult = 1.15,          -- x max(model width, depth), same as MassiveEmergence
	hoverHeightFrac = 0.42,        -- eye height as fraction of model height
	heroDistMult = 0.95, heroHeightFrac = 0.18, orbitDegrees = 45,
	returnBlendSeconds = 0.8,
	zoomPunchScale = 0.86,         -- hype-beat punch: dist multiplier per punch
}
Config.SHAKE = {
	dreadRampTo = 0.4, eruption = 1.0, riseSustain = 0.35,
	traumaDecayPerSec = 1.4, maxOffset = 0.9, maxRollDeg = 1.2,
}
Config.ROCK = {
	ricochetApex = 120,            -- absurdly high, on purpose. Do not "fix".
	ricochetLateral = 6, spinRadPerSec = 9.0,
	plinkPauseSeconds = 0.35,      -- hang above the head before the second bonk
	tumbleSeconds = 0.8,
}
Config.WATER = {
	stillWater = true,             -- glassy-still: zero local WaterWaveSize/Speed
	rippleTrainCount = 5, rippleMaxRadiusMult = 3.2, rippleAccel = 1.6,
	suctionDipStuds = 1.1, shadowMaxMult = 1.4,
	domeHeightFrac = 0.35, domeRiseSeconds = 0.42,
	columnHeightMult = 2.6, columnSeconds = 0.7,
	cascadeSeconds = 2.0, debrisBurst = 24,
}
Config.PARTICLES = {          -- rate multiplier + live-particle budget per tier
	high = { mult = 1.0, budget = 1200 },
	low  = { mult = 0.25, budget = 300 },
}
Config.POSTFX = {
	hypeSaturation = 0.35, hypeContrast = 0.12, hypeBloomIntensity = 0.9,
	blurSizeHigh = 8, blurSizeLow = 0,          -- blur dropped entirely on low
	flashSeconds = 0.08, easeBackSeconds = 1.2,
}
Config.REDUCED_MOTION = { shakeMult = 0.25, allowFlash = false }
Config.HYPE = {
	bannerScalePop = 1.35,
	zoomPunchTimes = { 6.9, 7.5, 8.2 },         -- absolute cinematic seconds
	memeTexts = { "NO SHOT", "ABSOLUTE UNIT", "HE'S REAL", "W CATCH", "SHEEEESH", "CAUGHT LIVE" },
	confettiBurst = 90, speedLineCount = 14,
}
-- Sound slots. "kit:<name>" resolves through SoundKit.play; raw ids through SoundKit.playId.
Config.ASSETS = {
	bonkClonk      = "kit:catchCommon",   -- TODO: replace — needs a dry stone-on-skull clonk
	rumbleLoop     = "kit:catchDrama",    -- TODO: replace — sub-bass riser, loopable
	bassDrop       = "kit:catchBigHit",
	waterExplosion = "kit:splashBig",
	roar           = "kit:catchGod",      -- TODO: replace — creature roar, ~2-3s
	plink          = "kit:catchCommon",   -- the second bonk: tiny, comically quiet
	memeAudio      = "kit:catchSecret",   -- TODO: replace — the heel-turn meme track (owner upload)
	cardWhoosh     = "kit:catchSparkle",
	VOLUMES = {
		bonkClonk = 0.85, rumbleLoop = 0.45, bassDrop = 0.9, waterExplosion = 0.8,
		roar = 0.7, plink = 0.18, memeAudio = 0.6, cardWhoosh = 0.4,
	},
}

-- Quality tier: "low" on touch devices or when the player opted down; else "high".
function Config.qualityFor(player: Player): string
	local UIS = game:GetService("UserInputService")
	if player:GetAttribute("CinematicLowQuality") == true then return "low" end
	if UIS.TouchEnabled and not UIS.KeyboardEnabled then return "low" end
	return "high"
end

function Config.timescale(): number
	local o = workspace:GetAttribute("CinematicTimescale")
	return (type(o) == "number" and o > 0) and o else Config.DEBUG_TIMESCALE
end

return Config
```

  (Fix the deliberate syntax check: `and o or Config.DEBUG_TIMESCALE` — the implementer writes valid Luau; strict-check by requiring it.)
  Types: `export type CinematicPayload = { UserId: number, BrainrotName: string, Rarity: string, RarityColor: Color3, Mutation: string?, Size: string, RockId: string?, RockColor: Color3?, EndPos: Vector3, SurfaceY: number, TotalTime: number, NContacts: number, SegTime: number, Seed: number }`.
- [ ] **Step 3: Re-run the verification snippet.** Expect: PASS on every assertion.
- [ ] **Step 4: Record** file sizes + assertion counts in the task report.

---

### Task 2: Server — ThrowHandler roll move + cinematic broadcast + splash suppression

**Files:**
- Modify: `ServerScriptService.Modules.ThrowHandler` (fetch fresh Source first; anchor by TEXT, never line numbers)

**Interfaces:**
- Consumes: `Config.SIZES` (requires `ReplicatedStorage.Modules.CatchCinematic.Config`).
- Produces: RemoteEvent `ReplicatedStorage.Remotes.MassiveCinematic`, `FireAllClients(payload: CinematicPayload)` at flight start; final-contact splash suppressed for cinematic throws; server stone destroyed at final contact for cinematic throws; `ForceNextSize` ServerStorage attribute test hook. Grant path unchanged.

- [ ] **Step 1: Write the failing verification** (Play mode, server VM via injected Script + BindableFunction bridge — see RECON-NOTES): assert `remotes.MassiveCinematic` exists; arm `ForceNextSize = "Massive"` + `ForceNextCatch = "<any Common name>"`, fire a real client throw (Client VM: `remotes.ThrowRequest:FireServer(0.55, false, false)` with the character walked into the hub ThrowZone via `character_navigation`), capture the client-received payload via a temporary `OnClientEvent` listener writing to a StringValue. Expect: FAIL (no remote).
- [ ] **Step 2: Apply the four edits** (small anchored `multi_edit` diffs, Edit mode):

  **(a) Module top, next to the `pityRemote` block** — create the remote the same way:
```lua
-- fired to EVERY client at flight start when a throw has already rolled a
-- cinematic-worthy size: the thrower stages the takeover, nearby players the
-- spectator variant. Fired from spawnSkippingStone because only it knows the
-- arc's timing and end point.
local cinematicRemote = remotes:FindFirstChild("MassiveCinematic")
if not cinematicRemote then
	cinematicRemote = Instance.new("RemoteEvent")
	cinematicRemote.Name = "MassiveCinematic"
	cinematicRemote.Parent = remotes
end
local CinematicConfig = require(ReplicatedStorage.Modules.CatchCinematic.Config)
```

  **(b) After `local mutation = Mutations.Roll(...)`** (anchor: that exact line) insert:
```lua
		-- SIZE ROLLED AT THROW TIME (2026-08-08, cinematic build). It rolled in
		-- revealCatch at landing before; the cinematic needs the answer while the
		-- stone is still airborne so the FINAL skip can play as the bonk. Every
		-- input to the roll (weatherMut) was already read above at this moment,
		-- so the odds are byte-identical -- the roll just happens 1-4s earlier.
		local sizeVariant = Sizes.Roll(weatherMut)
		-- TEST HOOK, mirror of ForceNextCatch above: consumed exactly once.
		do
			local wantSize = ServerStorage:GetAttribute("ForceNextSize")
			if type(wantSize) == "string" and Sizes.ByName[wantSize] then
				ServerStorage:SetAttribute("ForceNextSize", nil)
				sizeVariant = wantSize
				warn("[ThrowHandler] TEST override consumed: next catch is " .. wantSize)
			end
		end
		local cinMode = sizeVariant and CinematicConfig.SIZES[sizeVariant] or nil
		local cinematic = (cinMode == "full" or cinMode == "trimmed") and {
			UserId = player.UserId,
			BrainrotName = brainrotEntry.Name,   -- may be superseded by reveal-time
			Rarity = tier.Name,                  -- fallback swaps; client prefers
			RarityColor = tier.Color,            -- ThrowResult's name if it differs
			Mutation = mutation,
			Size = sizeVariant,
			RockId = rock.Id, RockColor = rock.Color,
			Seed = math.random(1, 2 ^ 30),
		} or nil
```
  **(c) In `revealCatch`, delete** `local sizeVariant = Sizes.Roll(weatherMut)` and its comment lines (keep the "Rolled on the SAME catch..." comment, rewording its first line to note the roll moved to throw time). `sizeVariant` remains in scope as an upvalue — verify by searching the closure for other references (`caught.Size`, `Size = sizeVariant`, `SizeMult`).

  **(d) `spawnSkippingStone`:** add trailing param `cinematic` (signature `(player, distance, rock, onLand, zone, cinematic)`; existing other call sites unaffected — verify this is the only caller). Next to the `StoneThrown:FireClient` line:
```lua
	if cinematic then
		cinematic.EndPos = Vector3.new(points[#points].X, surfaceY, points[#points].Z)
		cinematic.SurfaceY = surfaceY
		cinematic.TotalTime = totalTime
		cinematic.NContacts = nContacts
		cinematic.SegTime = segTime
		cinematicRemote:FireAllClients(cinematic)
	end
```
  In the flight loop replace the two splash lines with:
```lua
			local isLast = k == #points - 1
			-- A cinematic throw's FINAL contact is the bonk: clients stage it
			-- themselves (dry clonk, ricochet), so the server plays no splash
			-- and hands the stone off by destroying its copy at the contact.
			if not (isLast and cinematic) then
				spawnSplash(b, isLast, surfaceY)
				playSplashSound(b, isLast, k, #points - 1, surfaceY)
			end
```
  And the settle block becomes:
```lua
		local last = points[#points]
		if cinematic then
			stone:Destroy()
		else
			stone:PivotTo(CFrame.new(last.X, surfaceY, last.Z) * CFrame.Angles(math.rad(6), 0, 0))
			Debris:AddItem(stone, 1.3)
		end
```
  (`onLand` still fires unconditionally — the grant must never depend on the cutscene.)
  Pass `cinematic` at the call site: `spawnSkippingStone(player, distance, rock, function(splashPos) ... end, throwZone, cinematic)`.
- [ ] **Step 3: Re-run Step 1's verification.** Expect: payload arrives at flight start with all 13 fields, `EndPos.Y == 1.5` (hub), `TotalTime` in [1.15, 4.2]; the final contact produces NO `SkipSplash`/`SplashAudio` parts (poll workspace during the last segment); server `ThrownRock` is gone at landing; ThrowResult still arrives with `Size == "Massive"`; a SECOND throw with no ForceNextSize behaves exactly as today (final splash present, no remote fire).
- [ ] **Step 4: Revert the test grant.** The forced throw granted a real brainrot: baseline `#data.Brainrots` + Cash before, delete the granted entry by its Uid after (server VM), `PushUpdate`, stop Play, restart Play, verify count restored. Record baseline + revert evidence in the task report.
- [ ] **Step 5: Regression sweep:** 5 ordinary throws (varied power) — splashes, sounds, reveals identical to before; console clean; `inFlight` never sticks.

---

### Task 3: CameraRig + ScreenShake

**Files:**
- Create: `ReplicatedStorage.Modules.CatchCinematic.CameraRig` (ModuleScript, strict)
- Create: `ReplicatedStorage.Modules.CatchCinematic.ScreenShake` (ModuleScript, strict)

**Interfaces:**
- Consumes: `Config.CAMERA`, `Config.SHAKE`, `Config.REDUCED_MOTION`.
- Produces (exact signatures — later tasks call these):
  - `CameraRig.new(cfg: {}) -> Rig`
  - `Rig:takeover(): boolean` — saves CameraType/CameraSubject/FieldOfView/CFrame, sets Scriptable, binds ONE RenderStepped (`RenderPriority.Camera.Value + 1`). False if no camera.
  - `Rig:flyTo(targetCF: CFrame, seconds: number, easeOutHard: boolean)` — async start, cubic ease-in/quint ease-out path from current CFrame.
  - `Rig:lookHover(eye: Vector3, focus: Vector3)` — hold with ±0.15 stud drift.
  - `Rig:orbit(focus: Vector3, degrees: number, seconds: number, dist: number, height: number)`
  - `Rig:punchFOV(hi: number, settle: number, seconds: number)` — hand-lerped, never tweened.
  - `Rig:setShakeSource(fn: () -> (Vector3, number))` — offset + roll applied AFTER the base CFrame each frame (single camera writer lives here).
  - `Rig:returnToPlayer(seconds: number, done: () -> ())` — blend to `HRP.CFrame * savedOffset` (offset = saved CFrame relative to HRP at takeover), THEN restore CameraType/Subject/FOV. If character dead/missing: skip blend, hard restore.
  - `Rig:restore()` — idempotent, pcall-guarded full restore + unbind. Safe to call twice.
  - `ScreenShake.new(cfg) -> Shake`; `Shake:add(trauma: number)` (clamped 0..1); `Shake:sample(dt: number) -> (Vector3, number)` — offset = trauma² × maxOffset × perlin-ish noise (use `math.noise(t*13, seed)` per axis), roll = trauma² × maxRollDeg; trauma decays `traumaDecayPerSec × dt`; `Shake:setSustain(level: number)` for the rise beat's floor.

- [ ] **Step 1: Write the failing harness** (Play, Client VM): requires both, `takeover()`, flies to a fixed CFrame over the hub lake, punches FOV 70→95→78, adds 0.8 trauma, then `returnToPlayer(0.8, cb)`; asserts after cb: CameraType/FOV/Subject restored to saved values, RenderStepped unbound (no residual drift over 20 frames), calling `restore()` again does not error. Expect: FAIL (modules missing).
- [ ] **Step 2: Implement both modules.** CameraRig's render loop: `cam.CFrame = baseCF * CFrame.new(shakeOffset) * CFrame.Angles(0, 0, rollRad)` where baseCF comes from the active motion (fly/hover/orbit state machine). FOV writes every frame from the punch lerp. Reduced motion: multiply sampled trauma by `REDUCED_MOTION.shakeMult` inside `sample`.
- [ ] **Step 3: Run the harness.** Expect: PASS all assertions + visually smooth in a `screen_capture` at mid-flight. Restore CameraType after captures.
- [ ] **Step 4: Kill-path test:** call `takeover()`, then error inside a pcall'd sequence stub, confirm `restore()` from the error handler leaves the live camera identical to pre-test (compare all four saved fields).

---

### Task 4: WaterFX + RockRig

**Files:**
- Create: `ReplicatedStorage.Modules.CatchCinematic.WaterFX` (ModuleScript, strict)
- Create: `ReplicatedStorage.Modules.CatchCinematic.RockRig` (ModuleScript, strict)

**Interfaces:**
- Consumes: `Config.WATER`, `Config.ROCK`, `Config.PARTICLES`, stage Folder, `RockDesign.Build` (ReplicatedStorage.Modules.RockDesign), a shared deterministic RNG (`Random.new(seed)` passed in).
- Produces:
  - `WaterFX.new(cfg, particlesCfg, stage: Folder, surfacePos: Vector3, quality: string, rng: Random) -> Fx`
  - `Fx:bonkRing()` — one tiny impact ring (reuse ThrowHandler's ripple recipe: thin cylinder, starts half-faded).
  - `Fx:stillWater()` / private restore in `Fx:cleanup()` — zero `Terrain.WaterWaveSize/Speed` locally, save originals.
  - `Fx:rippleTrain(progress: number)` — call each frame in dread; emits accelerating concentric rings up to `rippleTrainCount` live.
  - `Fx:suctionAndShadow(progress: number)` — dark disc part growing under the surface (Transparency 0.35→0.15, Color rgb(8,10,14)) + a slight visible dip: a surface-tinted disc lowered `suctionDipStuds × progress`. Plus scattered debris burst once at progress 0.3 (`debrisBurst × mult` particles).
  - `Fx:dome(radius: number)` — water-coloured hemisphere (use a Ball part half-sunk, Glass material, Transparency 0.45) taut over the silhouette; `Fx:burstDome()` destroys it with the eruption.
  - `Fx:erupt(modelExtents: Vector3)` — vertical column (columnHeightMult × extents.Y), radial splash ring, foam sheet ParticleEmitter one-shot; rates × quality mult.
  - `Fx:cascade(model: Model, seconds: number)` — waterfall ParticleEmitters attached to the model's upper parts, auto-fading.
  - `Fx:godrays(pos: Vector3, height: number)` — 5 long translucent Neon wedges fanned behind, slow rotation.
  - `Fx:cleanup()` — destroys everything it made, restores Terrain wave props.
  - `RockRig.new(cfg, stage, rockId: string?, rockColor: Color3?, bonkPos: Vector3, rng: Random) -> Rock`
  - `Rock:update(t: number, headPos: Vector3?)` — the whole choreography is a pure function of cinematic time: ricochet arc up to `ricochetApex` (0→~3.2s, absurd hang via flattened-apex curve `h = apex * (1 - (1-p)^2.4)` up, slow sine hover at top), descent to `headPos` arriving at `SECOND_BONK_T`, plink pause, tumble into water over `tumbleSeconds`, then hidden. Spin `spinRadPerSec × t`.
  - `Rock:cleanup()`.

- [ ] **Step 1: Failing harness** (Play, Client VM): stage folder at the hub lake (`Vector3.new(<lane X>, 1.5, 200)`), run bonkRing → rippleTrain sweep → suction → dome → erupt(Vector3.new(10,12,10)) → godrays on a scripted clock; RockRig full 10.7s clock with a fake headPos. Assert: stage child count returns to 0 after `cleanup()`, Terrain wave props restored, live particle estimate (sum of emitter `Rate × Lifetime` + burst counts) ≤ budget for both quality tiers. Expect: FAIL.
- [ ] **Step 2: Implement both.** Deterministic randomness ONLY through the passed `rng` (spectators must see the same scatter). No `math.random` in these modules.
- [ ] **Step 3: Run harness both qualities.** Expect: PASS; `screen_capture` at dome + eruption moments for the report (restore camera after).
- [ ] **Step 4: Tundra smoke test:** rerun at a tundra position (SurfaceY 1999 — read a tundra ThrowZone's attribute live). Everything must stage at the right height; no water-level assumptions of 1.5 anywhere.

---

### Task 5: BrainrotRig + PostFX + AudioBus

**Files:**
- Create: `ReplicatedStorage.Modules.CatchCinematic.BrainrotRig` (ModuleScript, strict)
- Create: `ReplicatedStorage.Modules.CatchCinematic.PostFX` (ModuleScript, strict)
- Create: `ReplicatedStorage.Modules.CatchCinematic.AudioBus` (ModuleScript, strict)

**Interfaces:**
- Consumes: `Config.POSTFX`, `Config.ASSETS`, `Config.REDUCED_MOTION`, SoundKit, SizeConfig, BrainrotModels folder.
- Produces:
  - `BrainrotRig.new(stage, name: string, size: string, splashPos: Vector3) -> Rig?` — nil if no model (caller fails soft). Clone + neuter (PullCeremony's loop verbatim), scale with MassiveEmergence's exact fit math (`min((6.0*hs)/extents.Y, 9.5/max(width,0.01)) * Sizes.Scale(size)` — Massive Kraken lands ~36 studs tall; camera framing scales from measured extents, never constants).
  - `Rig:stageBelow()` — silhouette (store colours, paint rgb(6,8,12)), pivot fully below splashPos.
  - `Rig:setRise(alpha: number)` — pure function of alpha: pivot lerp below→breach-height + slow yaw (reuse MassiveEmergence's placeAt math).
  - `Rig:breachPose()` — head/upper-third above surface for the eruption instant.
  - `Rig:revealColors(seconds: number)` — tween stored colours back.
  - `Rig:eyeTwitch()` — find a part whose name matches `eye` (case-insensitive); briefly scale it 1.15× and back; no-op if absent.
  - `Rig:headTop(): Vector3` — current bounding-box top center (RockRig's second-bonk target).
  - `Rig:compressAndStreak(target2D: Vector2, seconds: number, done)` — scale model down while lerping toward the camera-ray of target2D, then hide.
  - `Rig:swapModel(newName: string): boolean` — pre-eruption only; rebuild at same alpha (covers the reveal-time fallback swap).
  - `Rig:cleanup()`.
  - `PostFX.new(cfg, quality, reducedMotion) -> Fx`; `Fx:flash()` (skip when reduced motion), `Fx:hypeOn(seconds)` (hand-lerped Saturation/Contrast/Bloom up + blur per quality), `Fx:easeBack(seconds)`, `Fx:cleanup()` (Destroy all three instances, always).
  - `AudioBus.new(cfg) -> Bus`; `Bus:play(slot: string, opts?)` resolves `kit:`→`SoundKit.play` / id→`SoundKit.playId` with `ASSETS.VOLUMES[slot]`; `Bus:duckAmbient(toLevel: number, seconds: number)` — hand-lerp: every playing Sound NOT ours under SoundService + Workspace.SFX (snapshot originals); `Bus:silence()` — hard-cut OURS to 0 AND ducked set to 0 (the 0.45s dead-air beat); `Bus:unsilence()`; `Bus:restoreAmbient(seconds)`; `Bus:cleanup()` — stop ours, restore every snapshotted volume. Never tween Sound.Volume.

- [ ] **Step 1: Failing harness:** BrainrotRig on "Kraken Congelato" size Massive at the hub lake: stage → rise sweep 0→1 → reveal → headTop sanity (above surface, within extents) → compressAndStreak to (0.9, 0.1) → cleanup leaves zero stage children. PostFX: apply hype, assert Lighting has exactly the 3 tagged instances, easeBack, cleanup leaves zero. AudioBus: play each slot (audition pass — flag any that error), duck→silence→restore, assert every snapshotted Sound back at its original volume. Expect: FAIL.
- [ ] **Step 2: Implement all three.**
- [ ] **Step 3: Run harness; screenshot the silhouette + revealed poses.** Expect: PASS, console clean.
- [ ] **Step 4: Model-swap test:** stage "Kraken Congelato", `swapModel("Zero Assoluto")` at alpha 0, assert new extents differ and stage still has exactly one model.

---

### Task 6: HypeUI

**Files:**
- Create: `ReplicatedStorage.Modules.CatchCinematic.HypeUI` (ModuleScript, strict)

**Interfaces:**
- Consumes: `Config.HYPE`, `Config.SKIP`, `Config.PARTICLES`, SizeConfig.Label, rarity/size colors from payload.
- Produces:
  - `HypeUI.new(cfg, quality, reducedMotion, rng) -> Ui` — own ScreenGui "CatchCinematicUI", DisplayOrder 55, IgnoreGuiInset, ResetOnSpawn false.
  - `Ui:showSkipPrompt()` / `Ui:setSkipProgress(alpha)` / `Ui:hideSkipPrompt()` — subtle bottom-right "HOLD TO SKIP" + radial/linear fill.
  - `Ui:banner(text: string, color: Color3)` — "MASSIVE" slam with impact scale-bounce (UIScale set per-frame, NOT tweened).
  - `Ui:nameText(label: string)` — `Sizes.Label(mutation, size, name)` in wobbling rainbow: per-character TextLabels in a UIListLayout, per-frame sine Y-offset + hue rotation via TextColor3 (gradient-rotation gotcha: animate color, not UIGradient.Rotation).
  - `Ui:confetti()` / `Ui:speedLines()` — 2D frames, counts × quality mult.
  - `Ui:memeFlyIns(t: number)` — texts from Config enter from alternating edges on the zoom-punch beats.
  - `Ui:bagTarget(): Vector2` — AbsolutePosition center of the Bag rail button (search `GameHUD.Chrome.NavRail` children for a name matching `bag` or `backpack`, `Hit` descendant preferred; fallback: bottom-center of screen). Used by BrainrotRig:compressAndStreak.
  - `Ui:cardArrive(color)` — small card pop at bagTarget with cardWhoosh.
  - `Ui:cleanup()` — destroy the ScreenGui.

- [ ] **Step 1: Failing harness** (Play, Client VM): build UI, run banner+name ("Golden Massive Kraken Congelato" — the long case)+confetti+speed lines+3 fly-ins on a scripted clock; assert every TextLabel `TextFits` AND no label's AbsolutePosition+AbsoluteSize overlaps the banner's rect (the sibling-overlap check TextFits misses — Season Pass lesson); `bagTarget()` returns an on-screen point; cleanup removes the gui. Expect: FAIL.
- [ ] **Step 2: Implement.** All motion per-frame from a clock — no tweens on UIScale.
- [ ] **Step 3: Run harness + screenshot the peak-hype frame** (banner + name + confetti + fly-ins all live). Expect: PASS, everything legible over a busy background.

---

### Task 7: Sequencer + CinematicClient + Bridge + CatchRevealClient integration

**Files:**
- Create: `ReplicatedStorage.Modules.CatchCinematic.Sequencer` (ModuleScript, strict)
- Create: `ReplicatedStorage.Modules.CatchCinematic.Bridge` (ModuleScript, strict)
- Create: `StarterPlayer.StarterPlayerScripts.CinematicClient` (LocalScript)
- Modify: `StarterPlayer.StarterPlayerScripts.CatchRevealClient` (fetch fresh Source first)

**Interfaces:**
- Consumes: everything above.
- Produces:
  - `Sequencer.play(payload: CinematicPayload, opts: { spectator: boolean, variant: string }) -> boolean` — BLOCKING (caller wraps in task.spawn); false = declined (caller falls back). Top of file: the commented beat map (each beat → the function that runs it). One conductor loop stepping `t` on RenderStepped × `Config.timescale()`, dispatching beat enter/exit + per-frame updates. All state in one `run` table; ONE `cleanup()` in the run's trove wired to: normal end, skip, `Humanoid.Died`, `LocalPlayer.CharacterAdded`, and the conductor's pcall handler.
  - `Sequencer.isActive(): boolean` — debounce: a second `play` while active returns false immediately (never stack rigs).
  - Skip: after `SKIP.delay`, any KeyCode / gamepad ButtonB / touch held `holdSeconds` → `exitFadeSeconds` luminance dip → jump `t` to handoff.t0 with world state force-set to post-rise (model surfaced+revealed, water calm, post normal-ish) → handoff plays normally. Never a hard cut.
  - Spectator run: same world beats (water, rock, model, audio positional at EndPos) with NO camera takeover, NO PostFX, NO HypeUI, NO shake; skip = just stop rendering its world FX.
  - ThrowResult name reconciliation: Bridge hands the sequencer the authoritative name if it differs pre-eruption → `BrainrotRig:swapModel`.
  - `Bridge.arm(payload)` / `Bridge.tryAdopt(result: {}) -> boolean` — true iff an armed/active cinematic matches (`result.Size` non-nil and equals armed Size, and cinematic not failed); records the authoritative result. / `Bridge.onDone(cb: (ok: boolean) -> ())` / `Bridge.reset()`.
  - CinematicClient: `MassiveCinematic.OnClientEvent` → debounce → thrower? (`payload.UserId == LocalPlayer.UserId`) : spectator radius check (own HRP vs EndPos ≤ `SPECTATOR_RADIUS`, else STOCK-SPLASH FALLBACK) → `Bridge.arm` (thrower only) → preload (`ContentProvider:PreloadAsync` model template + our Sound instances, task.spawn) → schedule `Sequencer.play` at `receiptClock + payload.TotalTime` (the bonk moment; latency cancels per StoneThrown's precedent).
  - **STOCK-SPLASH FALLBACK (Task 2 review finding):** the server suppresses the final splash for EVERYONE, but only nearby clients play the bonk — so any client that does not run a cinematic for this throw (outside radius, debounced, declined, or the sequencer errors) MUST stage a minimal stock landing itself at the bonk moment: one big ripple ring at EndPos + `kit:splashBig` positional sound. Without it a Massive throw reads as the rock silently vanishing. This fallback is the catch-all `else` of the OnClientEvent handler, not an optional path.
  - **CANCEL PATH (Task 2 review finding):** `revealCatch` can grant NOTHING (player left; vaulted/unique/limited fallback pools empty). The thrower's sequencer must therefore cancel gracefully if ThrowResult has not arrived by `Config.CANCEL_TIMEOUT` (new Config key, default 3.0s — Task 7 adds it plus a value assert): wind down with a quick fade + camera restore + the stock splash sound, before the eruption ever shows a creature. Spectators need no cancel (their variant is cosmetically harmless either way). Exit-path matrix gains case (e): ThrowResult never arrives → cancel path → full restore assertions.
- CatchRevealClient edit — insert ABOVE the `CatchFX.play` call (so no burst/tier cue pollutes the bonk):
```lua
	-- A cinematic-owned catch: the takeover IS the reveal. Adopt hands the
	-- authoritative result to the sequencer (covers reveal-time fallback swaps)
	-- and defers/replaces the ordinary chain. Fail-soft: if the cinematic dies,
	-- onDone(false) reruns this exact ordinary path.
	local CinBridge = require(ReplicatedStorage:WaitForChild("Modules")
		:WaitForChild("CatchCinematic"):WaitForChild("Bridge"))
	if CinBridge.tryAdopt(result) then
		CinBridge.onDone(function(ok)
			if not ok then ordinaryReveal(result) return end
			local after = workspace:GetAttribute("CinematicCeremonyAfter")
			if after == nil then after = CinConfig.RUN_PULL_CEREMONY_AFTER end
			if after then pcall(PullCeremony.play, buildPayload(result)) end
		end)
		return
	end
```
  This requires refactoring the existing handler body into `local function ordinaryReveal(result)` + `local function buildPayload(result)` (pure extraction — byte-identical behavior for non-cinematic catches; keep every existing comment).

- [ ] **Step 1: Failing harness:** Play, Client VM: hand-craft a payload at the hub lake, `Sequencer.play` full run at `CinematicTimescale = 1`; assert true return, camera four-field restore, zero stage children, zero CatchCinematicUI, Lighting effect count restored, Terrain waves restored. Expect: FAIL.
- [ ] **Step 2: Implement Sequencer + Bridge + CinematicClient; refactor CatchRevealClient.** Beat map comment mandatory.
- [ ] **Step 3: Full-run pass at timescale 1** — screenshot each beat (8 captures: bonk, travel, dread, silence, eruption, rise+second-bonk, hype, handoff). All assertions PASS, console clean.
- [ ] **Step 4: Exit-path matrix**, each followed by the full restore assertion set: (a) skip at t=2.0; (b) `Humanoid.Health = 0` at t=5 (server VM); (c) forced Lua error injected into a beat fn (temporarily, via a test hook wrapper); (d) two overlapping `play` calls — second returns false, first unharmed.
- [ ] **Step 5: Ordinary-catch regression:** 3 normal throws — reveal chain byte-identical behavior (burst, cue, emergence for non-cinematic Huge if rolled, ceremony), proving the CatchRevealClient refactor is pure.

---

### Task 8: /cinematic command + SettingsPanel reduced-motion toggle + demo variants

**Files:**
- Create: `ServerScriptService.CinematicCommand` (Script)
- Modify: `StarterPlayer.StarterPlayerScripts.GameHUDPanels.SettingsPanel` (fetch fresh; follow the SkipReveal* row pattern exactly)
- Modify: `StarterPlayer.StarterPlayerScripts.CinematicClient` (variant handling)

**Interfaces:**
- Consumes: AdminAnnouncements' `Chatted` + allowlist pattern; `MassiveCinematic` remote; MassiveEmergence (for the `hugeold` variant).
- Produces: chat commands, Studio/admin only (`RunService:IsStudio() or isAllowed(player)`):
  - `/cinematic <name...> [massive|huge|hugeold|spectator]` — last token = variant if it matches, else defaults `massive`; remaining tokens joined = brainrot name (spaces!), defaulting `Kraken Congelato`; unknown name → warn, no fire. Fabricates a payload: EndPos = player's HRP + lookVector×60 snapped to their zone's SurfaceY (fallback: hub 1.5), TotalTime 0.1 (bonk almost immediately), plausible Rarity/color from the entry, RockId "Pebble". Fires to THAT player only (`FireClient`). **Grants nothing, touches no data.**
  - `hugeold` variant: CinematicClient routes it to `pcall(MassiveEmergence.play, {...})` instead of the Sequencer — the side-by-side comparator.
  - `spectator` variant: runs the sequencer with `spectator = true` on the requesting client (the solo-Studio way to eyeball it).
  - `/cinceremony on|off` — sets `workspace` attribute `CinematicCeremonyAfter` (server-side so it persists across respawns in the session) for the after-flow comparison.
  - SettingsPanel: new toggle row "Reduced Motion (cinematics)" writing player attribute `ReducedMotion` (boolean), persisted via the existing SettingsSave flow exactly like SkipReveal*; Sequencer reads it at run start.
- [ ] **Step 1: Failing check:** in Play, chat `/cinematic` via real chat (TextChatService default channel `SendAsync` from Client VM, plus one REAL typed test with `user_keyboard_input`); expect nothing (script missing).
- [ ] **Step 2: Implement all three files' changes.**
- [ ] **Step 3: Verify:** `/cinematic` default → full massive run fires for the sender; `/cinematic Zero Assoluto huge` → trimmed variant; `... hugeold` → old 2.5s emergence; `... spectator` → no camera movement, world FX visible; `/cinceremony on` then a massive run → PullCeremony plays after handoff; toggle Reduced Motion in Settings (real click) → next run has no flash and 0.25× shake (assert via a debug counter on PostFX/Shake). Non-admin non-Studio path unreachable (code review the gate).
- [ ] **Step 4: SettingsPanel regression:** open Settings via rail (real click), toggle 2 unrelated rows, confirm attributes + no layout overlap (panel fits at 960).

---

### Task 9: Full verification suite, leak audit, end-to-end Massive, docs + mirror

**Files:**
- Create: `C:\Users\m\Coding\skip-a-brainrot\game-src\place-full\...` mirrors for every new/modified script (byte-exact copies of final Sources)
- Create: task report + updated memory (main session does memory)

- [ ] **Step 1: 10-consecutive-plays leak audit** (timescale 4× for speed, then ONE at 1×): after each run assert — stage folder gone, CatchCinematicUI gone, Lighting effects baseline, Terrain wave props baseline, camera four-field baseline, our Sound instances gone, `#getconnections`-proxy: RenderStepped callback count via a wrapper counter returns to baseline. Any drift = fail the task.
- [ ] **Step 2: End-to-end REAL Massive:** baseline snapshot (Brainrots count, Cash, XP) → arm `ForceNextSize = "Massive"` → real mouse-input throw at the hub dock → full cinematic on a real catch → ThrowResult reconciliation exercised (arm `ForceNextCatch` to a DIFFERENT name than the payload will guess? No — payload carries the same entry; instead verify the swap path with the Task 5 harness and note it) → then revert by delta: delete granted entry by Uid, PushUpdate, fresh-session verify. Repeat once in the TUNDRA (walk through the portal, throw at the ice dock, SurfaceY 1999 staging correct).
- [ ] **Step 3: Mobile/low pass:** set `CinematicLowQuality = true` attribute → full run → particle budget assertions, no blur instance, banner legible at 1280×720 capture.
- [ ] **Step 4: The definition-of-done checklist from the design doc**, item by item, each with evidence (capture or assertion output) in the report:
  Massive-only trigger · bonk reads solid · camera round-trip no hard cuts + provable restore on every exit path · second bonk lands ~5.6s · skip works after 1.0s into handoff · spectator never loses camera · zero leaks after 10 plays · low-tier holds frame rate (Studio proxy: `RunService.RenderStepped` dt spikes < 33ms during eruption on low) · every timing/color in Config alone.
- [ ] **Step 5: Write the game-src mirrors** (new folder `game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/`, plus updated ThrowHandler.lua, CatchRevealClient.lua, SettingsPanel.lua, new CinematicCommand.lua, CinematicClient.lua) — byte-exact from final live Sources.
- [ ] **Step 6: Final report:** what shipped, both pending user decisions and exactly how to demo each (`/cinematic` command lines), the sound-placeholder list (every `-- TODO: replace`), known quirks (throw button active during cinematic; ice-world water FX; spectator radius), and the SAVE reminder (work is unsaved until the user or a session saves to cloud).

## Self-review notes
- Spec coverage: every beat-sheet row → Tasks 4-7; camera round-trip → Task 3; rock → Task 4; architecture/remote → Task 2; config → Task 1; constraints 1-12 → global constraints + per-task assertions; testing hooks → Task 8; placeholders → Config.ASSETS; DoD → Task 9 Step 4. The prompt's "preload on wind-up" is deliberately "preload at flight start" (the roll happens at release; documented deviation).
- Types used consistently: `CinematicPayload` fields match Task 2's payload construction and Task 7's consumption; `Sequencer.play(payload, opts)` matches CinematicClient and the /cinematic variants; `Bridge.tryAdopt/onDone` match the CatchRevealClient diff.
- Both open user decisions (Huge fate, after-flow) are explicitly demo-able, not hard-coded.
