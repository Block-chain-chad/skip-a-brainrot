# Reward Reveal System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every confirmed brainrot grant (throw or ice-fishing) plays exactly one reveal chosen by rarity and size — Common–Legendary screen-space pops, Mythic/Secret/God/Huge/Massive/MassiveGod camera-takeover cuts at the water — on one shared takeover/restore framework, following `docs/superpowers/specs/2026-09-17-reward-reveal-design.md` (the spec) and the owner's blueprint exactly.

**Architecture:** The Massive `Sequencer` is split into `Takeover` (framework: clock, result hold, cancel, skip, watchdogs, camera+HUD takeover/restore, Bridge plumbing, beat dispatch) and one `Cuts/<Name>` module per cut that supplies a beat table, handlers and rig construction. A client `RevealRouter` normalises throw/fish results and picks exactly one path via `Config.CUT_FOR`. `CatchPop` is the pop layer built from `CatchReveal`'s viewport machinery and `PullCeremony`'s stamp.

**Tech Stack:** Roblox Luau (`--!strict` on new modules), Roblox Studio via the `roblox-studio` MCP (`script_read`, `multi_edit`, `execute_luau`), existing modules: CameraRig, ScreenShake, PostFX, AudioBus, WaterFX, RockRig, BrainrotRig, HypeUI, Bridge, BrainrotThumb, MutationFX, SoundKit, SizeConfig, RockDesign. Git holds the mirror under `game-src/place-full/`.

## Global Constraints

- **Studio is the source of truth.** Every edit is made in Studio through the MCP. Call `list_roblox_studios` first and use the returned id for every call; if a call reports no instance, re-list rather than retrying a stale id. Fetch fresh `.Source` (`script_read`) immediately before every edit; the place is Team Create.
- **Two write styles only:** whole-module writes via `execute_luau` (`inst.Source = [==[ ... ]==]`) in Edit mode for new modules and rewrites; `multi_edit` for small anchored diffs. After every write: `loadstring(inst.Source)` must compile (`assert(loadstring(src))`) AND, for a deletion edit, a `local`-declaration diff against the pre-edit backup must show zero new implicit globals (the Task 9 lesson from the sell-shop build).
- **Backups before every edit of an existing script:** `ServerStorage.AuditBackups.PreReveal_2026_09_17.<ScriptName>_pre<TaskN>` (a clone). Never edit without one.
- **Long-lived `execute_luau` VMs cache `require()`**; verify an edited module with `loadstring(inst.Source)()` or a clone-reparent-require, never a bare `require` of the live instance.
- **`--!strict` on every NEW module.** Do not add strict to existing files.
- **TweenService is allowed on BasePart Color/Size/Transparency/CFrame and GuiObject Size/Position/Rotation ONLY.** Hand-lerp on RenderStepped for camera FOV, Sound.Volume, ColorCorrection/Bloom/Blur values, UIScale, BackgroundTransparency, anything else (place-specific gotcha, verified).
- `task.wait`/`task.delay`/`task.spawn` + `RunService.RenderStepped` only — no `wait()`, `spawn()`, `delay()`.
- **One takeover path.** Only `Takeover` (through `CameraRig`) writes `Camera.CameraType`/`CFrame` during a cut, `ScreenGui.Enabled`, or `Lighting` (through `PostFX`). A cut module that does any of those directly is a plan violation. `CatchPop` writes none of them ever.
- **No absolute cinematic times inside a handler.** Handlers use beat-relative `p` or `CutKit.beatT0(run, name)`.
- Every cinematic world instance parents into `Workspace.CatchCinematicStage` (per run, destroyed in cleanup). Model clones: Anchored, CanCollide/CanQuery/CanTouch false, Massless true, Sounds neutered, Scripts/ProximityPrompts/BillboardGuis destroyed (BrainrotRig already does this).
- **Tunables:** framework-wide numbers live in `Config`; each cut's beat table and its own numbers live at the TOP of its cut module. All sound ids go through `Config.ASSETS` slots (`kit:<name>` or `rbxassetid://`), `-- TODO: replace` on true placeholders. No new raw asset ids.
- The reveal is 100% cosmetic and fails soft everywhere: any decline → the pop plays; a cut must never eat a catch.
- **Studio Play sessions write the REAL datastore.** Tests grant nothing; every harness uses fabricated payloads with `__debugNoBridge = true` unless the step says otherwise.
- Player-visible copy: banners are exactly `MYTHIC`, `SECRET`, `GOD`, `HUGE`, `MASSIVE`, `MASSIVE GOD`; the name line is `Sizes.Label(mutation, size, name)`; the header is `NEW BRAINROT!` iff `IsNew == true`, else `YOU GOT!`.
- **Routing (locked, spec §4):** Massive+God → MassiveGod; Massive → Massive; Huge → Huge; God → God; Secret → Secret; Mythic → Mythic; else Pop(rarity). Mutation never influences routing.
- **Mirror + commit at the end of every task:** for each touched script, `script_read` its Source and write it to the matching path under `game-src/place-full/` (new modules get new files; deleted scripts get their mirror deleted), then `git add` those paths and commit with the task's message. Keep LF line endings in the mirror files.
- **Owner is token-cost sensitive.** Do not read whole 50KB modules when a `script_grep` will do; do not re-verify what the previous step already proved.
- **Roster state (2026-09-17 forge conversion, commit 278988d):** `ReplicatedStorage.BrainrotModels` holds 218 models — 148 rigged-mesh pack bodies, 68 forge-baked MeshPart bodies (2–12 MeshParts + RootPart + FX hosts, per-vertex colours), `Chim`, `Maxwell`. `BrainrotModelsPlot` is empty. Consequences: `BrainrotRig:angryEyes()` returns false on every forge body (no part named "eye"), so the aura-rim fallback is the normal path, not the exception; `stageBelow`/`revealColors` still work (MeshPart.Color multiplies the vertex colours); the Harness's default model `Kraken Congelato` is a pack body — confirm it still exists before Task 1 Step 1, else pick another pack name from the folder.

## File Structure

Studio paths (mirror path = `game-src/place-full/<Service>/...`):

| Studio instance | Responsibility | Task |
|---|---|---|
| `ReplicatedStorage.Modules.CatchCinematic.Types` (modify) | `Run`, `Beat`, `BeatHandlers`, `Cut` types | 1 |
| `…CatchCinematic.CutKit` (new) | helpers shared by framework and cuts: trove, beat lookup, framing, geometry | 1 |
| `…CatchCinematic.Takeover` (new) | the framework (from `Sequencer`) | 1 |
| `…CatchCinematic.Cuts` (new Folder) + `Cuts.Registry` (new) | cut lookup by name, fail-soft | 1 |
| `…CatchCinematic.Cuts.Massive` (new) | Massive beat table + handlers + build | 1, 2 |
| `…CatchCinematic.Cuts.Huge` (new) | Huge beat table reusing Massive's handlers | 1, 2 |
| `…CatchCinematic.Sequencer` (delete) | superseded by Takeover + Cuts | 1 |
| `…CatchCinematic.Harness` (new, Studio-only) | structural harness used by every later task | 1 |
| `…CatchCinematic.Config` (modify) | beats removed, CUT_FOR, ASSETS slots | 1, 2, 3 |
| `…CatchCinematic.RockRig` (rewrite) | final skip → sink; no ricochet | 2 |
| `…CatchCinematic.HypeUI` (modify) | meme fly-ins, confetti, speed lines removed | 2 |
| `…CatchCinematic.Bridge` (modify) | arm/adopt keyed on cut name, not size | 3 |
| `StarterPlayerScripts.CinematicClient` (modify) | plays `Takeover` with the payload's cut | 1, 3 |
| `ServerScriptService.CinematicCommand` (modify) | `/cinematic <name> <cut>` for six cuts | 1, 3 |
| `ServerScriptService.Modules.ThrowHandler` (modify) | broadcast on `CUT_FOR`, `Cut` + `IsNew` fields | 3 |
| `ReplicatedStorage.Remotes.MassiveCinematic` → `CatchCinematic` (rename) | | 3 |
| `StarterPlayerScripts.RevealRouter` (new) / `CatchRevealClient` (delete) | one path per grant, FIFO, adopt | 3, 4 |
| `ReplicatedStorage.Modules.CatchPop` (new) | Common–Legendary pops | 4 |
| `ReplicatedStorage.Modules.PullCeremony`, `MassiveEmergence` (delete); `CatchReveal` (delete after CatchPop absorbs bands 1–3) | retired | 4 |
| `StarterPlayerScripts.ClientMain` (modify) | throw input refuses while `RevealActive` | 3 |
| `…CatchCinematic.Cuts.Mythic` (new) | | 5 |
| `…CatchCinematic.Cuts.Secret`, `…CatchCinematic.AuraFX` (new), `WaterFX:glowBelow` (modify) | | 6 |
| `…CatchCinematic.Cuts.God`, `…CatchCinematic.BeamFX` (new), `PostFX:tint`, `BrainrotRig:descend` (modify) | | 7 |
| `…CatchCinematic.Cuts.MassiveGod` (new) | | 8 |
| `ServerScriptService.Modules.IceFishingEvent` (modify, Studio-only), fishing client cast input (modify) | | 9 |
| `game-src/README.md` (docs) | | 10 |

---

### Task 1: Extract `Takeover` + `Cuts/Massive` + `Cuts/Huge` from `Sequencer` (behaviour-preserving)

**Files:**
- Modify: `ReplicatedStorage.Modules.CatchCinematic.Types`
- Create: `ReplicatedStorage.Modules.CatchCinematic.CutKit`
- Create: `ReplicatedStorage.Modules.CatchCinematic.Takeover`
- Create: `ReplicatedStorage.Modules.CatchCinematic.Cuts` (Folder), `Cuts.Registry`, `Cuts.Massive`, `Cuts.Huge`
- Create: `ReplicatedStorage.Modules.CatchCinematic.Harness`
- Modify: `ReplicatedStorage.Modules.CatchCinematic.Config` (move beat tables out)
- Modify: `StarterPlayer.StarterPlayerScripts.CinematicClient`
- Delete: `ReplicatedStorage.Modules.CatchCinematic.Sequencer` (after the harness passes on Takeover)

**Interfaces:**
- Consumes: `Sequencer` (mirror `game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/Sequencer.lua`, 54,645 B — the mirror is byte-exact with Studio as of 2026-08-09; re-verify size in Studio before starting), `Config`, `Bridge`, the eight rigs.
- Produces: `Takeover.play(cut: Cut, payload, opts: {spectator: boolean?, bridgeGen: number?, onCommit: (() -> ())?}): boolean`, `Takeover.isActive(): boolean`, `Takeover.debugState()`, `Takeover.debugHold(down: boolean)`; `Registry.get(name: string): Cut?`; `CutKit` (API below); `Harness.run(cutName: string, mode: string, opts?): Report`.

- [ ] **Step 1: Baseline the current Massive cut with the harness (written first, against `Sequencer`).** In Studio Edit mode create `ReplicatedStorage.Modules.CatchCinematic.Harness` (ModuleScript) with this source. It plays a fabricated payload through whatever conductor is passed in and asserts the restore invariants. It is Studio-only by construction.

```lua
--!strict
-- CatchCinematic.Harness -- STUDIO-ONLY structural harness for the reveal cuts.
-- Plays a fabricated payload (no grant, no Bridge unless asked) through a conductor
-- and asserts that every exit path restores the client: stage gone, PlayerGui
-- Enabled flags identical, camera restored, Lighting untouched, RevealActive nil.
-- Returns a report table; never throws (a harness that throws hides the failure).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Harness = {}

export type Report = { ok: boolean, cut: string, mode: string, seconds: number, failures: { string } }

local HUB_SURFACE_Y = 1.5

local function snapshot(): { [string]: any }
	local player = Players.LocalPlayer
	local pg = player and player:FindFirstChildOfClass("PlayerGui")
	local guis: { [string]: boolean } = {}
	if pg then
		for _, g in ipairs(pg:GetChildren()) do
			if g:IsA("ScreenGui") then
				guis[g.Name] = g.Enabled
			end
		end
	end
	local cam = Workspace.CurrentCamera
	local lightNames = {}
	for _, c in ipairs(Lighting:GetChildren()) do
		table.insert(lightNames, c.Name)
	end
	table.sort(lightNames)
	return {
		guis = guis,
		cameraType = cam and cam.CameraType or nil,
		cameraSubject = cam and cam.CameraSubject or nil,
		fov = cam and cam.FieldOfView or nil,
		lightChildren = table.concat(lightNames, ","),
		ambient = Lighting.Ambient,
		brightness = Lighting.Brightness,
		waveSize = Workspace.Terrain.WaterWaveSize,
		waveSpeed = Workspace.Terrain.WaterWaveSpeed,
	}
end

local function diff(before: { [string]: any }, after: { [string]: any }, failures: { string })
	for name, enabled in pairs(before.guis) do
		if after.guis[name] ~= nil and after.guis[name] ~= enabled then
			table.insert(failures, "ScreenGui " .. name .. " Enabled " .. tostring(enabled) .. " -> " .. tostring(after.guis[name]))
		end
	end
	for _, k in ipairs({ "cameraType", "cameraSubject", "fov", "lightChildren", "ambient", "brightness", "waveSize", "waveSpeed" }) do
		if before[k] ~= after[k] then
			table.insert(failures, k .. " changed: " .. tostring(before[k]) .. " -> " .. tostring(after[k]))
		end
	end
end

-- opts.endPos / opts.surfaceY override the hub defaults; opts.brainrot picks the model.
-- opts.spectator plays the world-only variant. opts.bridge = true arms the Bridge and
-- never adopts a result, which exercises the cancel path.
-- opts.skipAfter (real seconds) holds the skip input from that moment.
-- opts.killAfter (real seconds) sets Humanoid.Health = 0 (respawn follows -- Studio only).
function Harness.run(conductorName: string, cutName: string, mode: string, opts: { [string]: any }?): Report
	local o = opts or {}
	local report: Report = { ok = false, cut = cutName, mode = mode, seconds = 0, failures = {} }
	if not RunService:IsStudio() then
		table.insert(report.failures, "not Studio")
		return report
	end
	local player = Players.LocalPlayer
	local folder = ReplicatedStorage.Modules.CatchCinematic
	local okC, conductor = pcall(require, folder:FindFirstChild(conductorName))
	if not okC then
		table.insert(report.failures, "conductor require failed: " .. tostring(conductor))
		return report
	end
	local Bridge = require(folder.Bridge)

	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local endPos: Vector3 = o.endPos
		or (hrp and (hrp :: BasePart).Position + (hrp :: BasePart).CFrame.LookVector * 45)
		or Vector3.new(0, HUB_SURFACE_Y, 60)
	local surfaceY: number = o.surfaceY or HUB_SURFACE_Y
	endPos = Vector3.new(endPos.X, surfaceY, endPos.Z)

	local size: string? = (cutName == "Massive" or cutName == "MassiveGod") and "Massive"
		or (cutName == "Huge") and "Huge" or nil
	local rarity: string = (cutName == "God" or cutName == "MassiveGod") and "God"
		or (cutName == "Secret") and "Secret" or (cutName == "Mythic") and "Mythic" or "Epic"
	local payload: { [string]: any } = {
		UserId = o.spectator and -1 or player.UserId,
		BrainrotName = o.brainrot or "Kraken Congelato",
		Rarity = rarity,
		RarityColor = Color3.fromRGB(255, 226, 120),
		Mutation = o.mutation,
		Size = size,
		Cut = cutName,
		RockId = "stone", RockColor = Color3.fromRGB(105, 100, 96),
		Seed = 7,
		EndPos = endPos, SurfaceY = surfaceY,
		TotalTime = 0, NContacts = 2, SegTime = 0.5,
		__debugNoBridge = not o.bridge,
	}

	local bridgeGen: number? = nil
	if o.bridge then
		bridgeGen = Bridge.arm(payload, 30)
	end

	local before = snapshot()
	local t0 = os.clock()
	local committed = false
	local returned: boolean? = nil
	task.spawn(function()
		local okP, res = pcall(function()
			-- Sequencer.play(payload, opts) vs Takeover.play(cut, payload, opts)
			if conductorName == "Sequencer" then
				return conductor.play(payload, {
					spectator = o.spectator == true,
					variant = (cutName == "Huge") and "trimmed" or "full",
					bridgeGen = bridgeGen,
					onCommit = function() committed = true end,
				})
			end
			local Registry = require(folder.Cuts.Registry)
			local cut = Registry.get(cutName)
			assert(cut, "no cut " .. cutName)
			return conductor.play(cut, payload, {
				spectator = o.spectator == true,
				bridgeGen = bridgeGen,
				onCommit = function() committed = true end,
			})
		end)
		if not okP then
			table.insert(report.failures, "play errored: " .. tostring(res))
			returned = false
		else
			returned = res
		end
	end)

	if o.skipAfter then
		task.delay(o.skipAfter, function()
			if conductor.debugHold then conductor.debugHold(true) end
		end)
	end
	if o.killAfter then
		task.delay(o.killAfter, function()
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum then hum.Health = 0 end
		end)
	end

	local deadline = os.clock() + (o.timeout or 90)
	while returned == nil and os.clock() < deadline do
		task.wait(0.1)
	end
	if returned == nil then
		table.insert(report.failures, "play did not return within timeout")
	end
	if o.skipAfter and conductor.debugHold then conductor.debugHold(false) end
	report.seconds = os.clock() - t0

	task.wait(o.settle or 4) -- SoundKit's Debris anchors live up to 3.5s
	local after = snapshot()
	diff(before, after, report.failures)
	if Workspace:FindFirstChild("CatchCinematicStage") then
		table.insert(report.failures, "stage folder leaked")
	end
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg and (pg:FindFirstChild("CatchCinematicUI") or pg:FindFirstChild("CatchCinematicFade")) then
		table.insert(report.failures, "cinematic gui leaked")
	end
	if player:GetAttribute("RevealActive") ~= nil then
		table.insert(report.failures, "RevealActive not cleared")
	end
	if conductor.isActive and conductor.isActive() then
		table.insert(report.failures, "conductor still active")
	end
	if mode == "normal" and returned ~= true and not o.spectator then
		table.insert(report.failures, "expected play() == true, got " .. tostring(returned))
	end
	if mode == "cancel" and committed and returned ~= true then
		-- cancel still returns true (it committed); the Bridge settles false
	end
	if o.bridge then Bridge.reset() end
	report.ok = #report.failures == 0
	return report
end

-- Runs the standard matrix for one cut and prints one line per mode.
function Harness.matrix(conductorName: string, cutName: string, opts: { [string]: any }?): { Report }
	local base = opts or {}
	local function with(extra: { [string]: any }): { [string]: any }
		local t = {}
		for k, v in pairs(base) do t[k] = v end
		for k, v in pairs(extra) do t[k] = v end
		return t
	end
	local reports = {
		Harness.run(conductorName, cutName, "normal", with({})),
		Harness.run(conductorName, cutName, "spectator", with({ spectator = true })),
		Harness.run(conductorName, cutName, "skip", with({ skipAfter = 1.6 })),
		Harness.run(conductorName, cutName, "cancel", with({ bridge = true })),
	}
	for _, r in ipairs(reports) do
		print(string.format("[Harness] %s/%s %s %.1fs %s", r.cut, r.mode, r.ok and "OK" or "FAIL", r.seconds, table.concat(r.failures, " | ")))
	end
	return reports
end

return Harness
```

Then, in **Play mode** with the character standing on the hub dock facing the lake, run via `execute_luau` (client):

```lua
workspace:SetAttribute("CinematicTimescale", 4)
local H = require(game.ReplicatedStorage.Modules.CatchCinematic.Harness)
local r = H.matrix("Sequencer", "Massive")
local r2 = H.matrix("Sequencer", "Huge")
workspace:SetAttribute("CinematicTimescale", nil)
```

Expected: 8 lines, all `OK`. Record the 8 `seconds` values in the task report — Task 1's Takeover must reproduce them within ±0.3s. (`Huge` via `Sequencer` runs the trimmed variant even though `Config.SIZES.Huge == "none"`, because the harness passes `variant` explicitly.)

- [ ] **Step 2: Extend `Types`.** Backup, then replace `Types`' Source with:

```lua
--!strict
-- CatchCinematic.Types -- shared types for the framework and the cut modules.
export type CinematicPayload = {
	UserId: number, BrainrotName: string, Rarity: string, RarityColor: Color3,
	Mutation: string?, Size: string?, Cut: string?,
	RockId: string?, RockColor: Color3?, Seed: number,
	EndPos: Vector3, SurfaceY: number, TotalTime: number, NContacts: number, SegTime: number,
}

-- Private per-play state bag. Loose on purpose: the framework fills the shared
-- fields (see Takeover's RUN FIELDS header) and a cut may add its own.
export type Run = { [string]: any }

export type Beat = { name: string, t0: number, t1: number }

export type BeatHandlers = {
	enter: ((Run) -> ())?,
	update: ((Run, number) -> ())?,   -- p = 0..1 progress through the beat
	exit: ((Run) -> ())?,
}

export type Cut = {
	name: string,
	beats: { Beat },                       -- cinematic seconds; t=0 = final skip / hook-set
	handlers: { [string]: BeatHandlers },  -- keyed by beat name
	revealBeat: string,                    -- the clock parks before this beat until the grant lands
	skippable: boolean,
	skipTo: string?,                       -- beat a skip jumps to (required when skippable)
	onSkip: ((Run) -> ())?,                -- force the end-state of the skipped beats
	onCancel: ((Run) -> ())?,              -- tear down cut-built rigs on a grant that never came
	everyFrame: ((Run) -> ())?,            -- runs each frame before beat dispatch (pure in run.t)
	build: (Run) -> boolean,               -- construct cut rigs into run.stage; false = decline
	bannerText: string,
}

return {}
```

Compile-check: `assert(loadstring(inst.Source))`.

- [ ] **Step 3: Create `CutKit`.** New ModuleScript `ReplicatedStorage.Modules.CatchCinematic.CutKit`:

```lua
--!strict
-- CatchCinematic.CutKit -- helpers shared by Takeover (the framework) and every
-- Cuts/<Name> module. Pure functions over the run bag; no instances of its own.
local Players = game:GetService("Players")

local folder = script.Parent
local Config = require(folder:WaitForChild("Config"))
local Types = require(folder:WaitForChild("Types"))
type Run = Types.Run

local CutKit = {}

CutKit.VIEW_DIST_PAD = 10        -- MassiveEmergence's viewDist pad: max(X,Z)*mult + 10
CutKit.TRAVEL_BACK_STUDS = 24    -- how far short of the splash the low fly-out parks

-- ============================== trove ==============================
function CutKit.track(run: Run, fn: () -> ())
	table.insert(run.trove, fn)
end

-- LIFO drain. Construction order is stage -> cut rigs -> audio -> camera -> post ->
-- ui -> skip conns -> kill-switch conns -> render bind -> [overlay], so draining
-- backwards restores the camera before the world is torn out from under it and
-- destroys the stage folder last, as the catch-all for anything a rig leaked.
function CutKit.drain(run: Run, tag: string)
	if run.cleaned then
		return
	end
	run.cleaned = true
	for i = #run.trove, 1, -1 do
		local ok, err = pcall(run.trove[i])
		if not ok then
			warn("[" .. tag .. "] cleanup step failed: " .. tostring(err))
		end
	end
	run.trove = {}
end

-- ============================== beats ==============================
function CutKit.beatIndexOf(run: Run, name: string): number?
	for i, b in ipairs(run.beats) do
		if b.name == name then
			return i
		end
	end
	return nil
end

function CutKit.beatT0(run: Run, name: string, fallback: number): number
	local i = CutKit.beatIndexOf(run, name)
	if i then
		return run.beats[i].t0
	end
	return fallback
end

-- Wall-clock seconds the CURRENT beat lasts (cinematic length x stretch).
function CutKit.beatSeconds(run: Run): number
	local beat = run.beats[run.beatIdx]
	if not beat then
		return 0
	end
	return (beat.t1 - beat.t0) * run.stretch
end

function CutKit.mergeHandlers(base: { [string]: any }, extra: { [string]: any }): { [string]: any }
	local out: { [string]: any } = {}
	for k, v in pairs(base) do
		out[k] = v
	end
	for k, v in pairs(extra) do
		out[k] = v
	end
	return out
end

-- ============================== tables ==============================
function CutKit.shallowMerge(base: { [string]: any }, extra: { [string]: any }): { [string]: any }
	return CutKit.mergeHandlers(base, extra)
end

-- Shallow copy with ONLY the named duration fields multiplied by `stretch` -- how the
-- debug timescale reaches durations that live inside a module's cfg.
function CutKit.scaleDurations(base: { [string]: any }, fields: { string }, stretch: number): { [string]: any }
	local out: { [string]: any } = {}
	for k, v in pairs(base) do
		out[k] = v
	end
	if stretch == 1 then
		return out
	end
	for _, k in ipairs(fields) do
		local v = out[k]
		if type(v) == "number" then
			out[k] = v * stretch
		end
	end
	return out
end

-- ============================== geometry ==============================
function CutKit.localHRP(): BasePart?
	local player = Players.LocalPlayer
	local char = player and player.Character
	return (char and char:FindFirstChild("HumanoidRootPart")) :: BasePart?
end

-- Unit horizontal direction from the player toward the surface point; +Z fallback.
function CutKit.horizToward(surface: Vector3): Vector3
	local hrp = CutKit.localHRP()
	if hrp then
		local flat = Vector3.new(surface.X - hrp.Position.X, 0, surface.Z - hrp.Position.Z)
		if flat.Magnitude > 1e-3 then
			return flat.Unit
		end
	end
	return Vector3.new(0, 0, 1)
end

-- Refreshed after a swapModel, which replaces both.
function CutKit.refreshGeometry(run: Run)
	local brain = run.brain
	if not brain then
		return
	end
	run.model = brain:model()
	run.extents = brain:extents() or Vector3.new(4, 6, 4)
end

-- Eye/focus for the close "hero" framing at the surface, from Config.CAMERA.
function CutKit.heroFraming(run: Run): (Vector3, Vector3)
	local cam = Config.CAMERA
	local ext = run.extents :: Vector3
	local width = math.max(ext.X, ext.Z)
	local dist = width * (cam.hoverDistMult or 1.15) + CutKit.VIEW_DIST_PAD
	local focus = run.surface + Vector3.new(0, ext.Y * (cam.hoverHeightFrac or 0.42), 0)
	local eye = focus - run.horiz * dist + Vector3.new(0, ext.Y * (cam.heroHeightFrac or 0.18), 0)
	return eye, focus
end

-- Eye/focus for the pulled-WAY-back framing that sells scale: distance scales with
-- the creature's largest extent (Config.CAMERA.farDistMult) and the eye sits at
-- Config.CAMERA.farHeightFrac of its height, so a 36-stud Kraken and a 9-stud
-- Huge both fill roughly the same fraction of the frame.
function CutKit.farFraming(run: Run): (Vector3, Vector3)
	local cam = Config.CAMERA
	local ext = run.extents :: Vector3
	local size = math.max(ext.X, ext.Y, ext.Z)
	local dist = size * (cam.farDistMult or 2.4) + CutKit.VIEW_DIST_PAD
	local focus = run.surface + Vector3.new(0, ext.Y * 0.5, 0)
	local eye = focus - run.horiz * dist + Vector3.new(0, ext.Y * (cam.farHeightFrac or 0.35), 0)
	return eye, focus
end

return CutKit
```

Add to `Config.CAMERA` (multi_edit, after `returnBlendSeconds = 0.8,`): `farDistMult = 2.4, farHeightFrac = 0.35,   -- CutKit.farFraming: the pulled-back scale shot`.

- [ ] **Step 4: Create the `Cuts` folder, `Registry`, and `Cuts/Massive` by MOVING the Massive-specific code out of `Sequencer`.** Create Folder `ReplicatedStorage.Modules.CatchCinematic.Cuts`. Create `Cuts.Registry`:

```lua
--!strict
-- CatchCinematic.Cuts.Registry -- cut lookup by name. Fail-soft: a cut module that
-- is missing or fails to load returns nil, and the caller falls back (stock landing
-- for the world, a pop for the reveal). Never throws.
local Types = require(script.Parent.Parent:WaitForChild("Types"))
type Cut = Types.Cut

local Registry = {}
local cache: { [string]: Cut } = {}

function Registry.get(name: string): Cut?
	if type(name) ~= "string" or name == "" then
		return nil
	end
	if cache[name] then
		return cache[name]
	end
	local inst = script.Parent:FindFirstChild(name)
	if not inst or not inst:IsA("ModuleScript") then
		return nil
	end
	local ok, cut = pcall(require, inst)
	if not ok or type(cut) ~= "table" or type(cut.beats) ~= "table" or type(cut.handlers) ~= "table" then
		warn("[Cuts.Registry] cut '" .. name .. "' unavailable: " .. tostring(cut))
		return nil
	end
	cache[name] = cut
	return cut
end

Registry.NAMES = { "Mythic", "Secret", "God", "Huge", "Massive", "MassiveGod" }

return Registry
```

Create `Cuts.Massive`. Its body is the Massive-specific code of `Sequencer`, moved, with these exact edits. Work from a fresh `script_read` of `Sequencer`; the line numbers below are the mirror's and are only a guide — anchor on the function names.

```lua
--!strict
-- CatchCinematic.Cuts.Massive -- THE BEAST. The Massive catch cinematic's beat table,
-- handlers and rig construction. Conducted by Takeover; this module never touches
-- Camera.CameraType, ScreenGui.Enabled or Lighting -- it drives run.cam / run.post.
--
-- Task 1 state: the beats and handlers are the shipped 17.9s v2 cut, moved here
-- VERBATIM so the harness proves the framework split before Task 2 re-paces it.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = script.Parent.Parent
local Config = require(folder:WaitForChild("Config"))
local CutKit = require(folder:WaitForChild("CutKit"))
local Types = require(folder:WaitForChild("Types"))
local WaterFX = require(folder:WaitForChild("WaterFX"))
local RockRig = require(folder:WaitForChild("RockRig"))
local BrainrotRig = require(folder:WaitForChild("BrainrotRig"))
type Run = Types.Run

local Massive = {}

-- ===== TUNABLES (this cut's own) =====
Massive.BEATS = {
	{ name = "bonk",     t0 = 0.00, t1 = 0.35 },
	{ name = "travel",   t0 = 0.35, t1 = 1.60 },
	{ name = "dread",    t0 = 1.60, t1 = 5.60 },
	{ name = "silence",  t0 = 5.60, t1 = 6.35 },
	{ name = "eruption", t0 = 6.35, t1 = 7.20 },
	{ name = "rise",     t0 = 7.20, t1 = 13.70 },
	{ name = "hype",     t0 = 13.70, t1 = 16.20 },
	{ name = "handoff",  t0 = 16.20, t1 = 17.90 },
}
Massive.SECOND_BONK_T = 10.6
local PUNCH_HOLD = 0.22

-- ===== helpers moved from Sequencer =====
-- rockTimings: verbatim, except `run.variant == "trimmed"` becomes
-- `run.cut.name == "Huge"` and Config.SECOND_BONK_T becomes Massive.SECOND_BONK_T.
-- calmAngry: verbatim.
-- (paste them here)

-- ===== beat handlers moved from Sequencer =====
-- enterBonk, enterTravel, enterDread, updateDread, enterSilence, exitSilence,
-- enterEruption, enterRise, updateRise, enterHype, updateHype, enterHandoff,
-- updateHandoff, updateEruption: verbatim, with these mechanical substitutions:
--   heroFraming(run)        -> CutKit.heroFraming(run)
--   refreshGeometry(run)    -> CutKit.refreshGeometry(run)
--   TRAVEL_BACK_STUDS       -> CutKit.TRAVEL_BACK_STUDS
--   VIEW_DIST_PAD           -> CutKit.VIEW_DIST_PAD
--   `run.beats[run.beatIdx]` stays (the framework keeps beatIdx on the run).
-- (paste them here)

Massive.handlers = {
	bonk     = { enter = enterBonk },
	travel   = { enter = enterTravel },
	dread    = { enter = enterDread, update = updateDread },
	silence  = { enter = enterSilence, exit = exitSilence },
	eruption = { enter = enterEruption, update = updateEruption },
	rise     = { enter = enterRise, update = updateRise },
	hype     = { enter = enterHype, update = updateHype },
	handoff  = { enter = enterHandoff, update = updateHandoff },
}

-- The rock is pure in t across every beat, and the second bonk is a one-shot on the
-- master clock -- so both live in everyFrame rather than in any one beat.
-- Moved from stepInner's steps (5) and (6), verbatim.
function Massive.everyFrame(run: Run)
	if run.rock then
		local head: Vector3? = nil
		if run.brain then
			head = run.brain:headTop()
		end
		run.rock:update(run.t, head)
	end
	if not run.plinked and run.t >= run.secondBonkT then
		run.plinked = true
		if run.audio then
			local where = run.brain and run.brain:headTop() or run.surface
			run.audio:play("plink", { where = where })
		end
		if run.shake then
			run.shake:add(0.2)
		end
		if run.brain and not run.skipping then
			run.brain:eyeTwitch()
		end
	end
end

-- forceHandoffState from Sequencer, verbatim, renamed.
function Massive.onSkip(run: Run)
	-- (paste forceHandoffState's body here)
end

-- The cut-owned rigs: brain, rock, water. Moved from Sequencer.buildRun (the part
-- between the stage folder and AudioBus). Returns false to decline (no model).
function Massive.build(run: Run): boolean
	local stage = run.stage :: Folder
	local brain = BrainrotRig.new(stage, run.name, run.size or "Massive", run.surface)
	if not brain then
		warn("[Cuts.Massive] declining: no model for '" .. tostring(run.name) .. "'")
		return false
	end
	run.brain = brain
	CutKit.track(run, function()
		brain:cleanup()
	end)
	CutKit.refreshGeometry(run)

	run.plinked = false
	run.domeUp = false
	run.punchFired = {}
	run.punchState = false
	run.secondBonkT = rockTimings(run).secondBonkT

	if run.payload.RockId ~= nil then
		local rock = RockRig.new(
			CutKit.shallowMerge(Config.ROCK, rockTimings(run)),
			stage, run.payload.RockId, run.payload.RockColor, run.surface, run.rng
		)
		run.rock = rock
		CutKit.track(run, function()
			rock:cleanup()
		end)
	end

	local water = WaterFX.new(run.waterCfg, Config.PARTICLES, stage, run.surface, run.quality, run.rng)
	run.water = water
	CutKit.track(run, function()
		water:cleanup()
	end)
	return true
end

Massive.name = "Massive"
Massive.beats = Massive.BEATS
Massive.revealBeat = "eruption"
Massive.skippable = true
Massive.skipTo = "handoff"
Massive.bannerText = "MAX BRAINROT"   -- Task 2 changes this to "MASSIVE"

return Massive
```

The pasted `enterHype` keeps `run.hype:banner("MAX BRAINROT", run.rarityColor)` in Task 1 (Task 2 rewrites the beat). `updateHype` reads `Config.HYPE.zoomPunchTimes` exactly as today (an absolute-time table — Task 2 deletes the beat, so the no-absolute-times rule is satisfied from Task 2 on).

- [ ] **Step 5: Create `Cuts/Huge`** (the trimmed variant as a cut):

```lua
--!strict
-- CatchCinematic.Cuts.Huge -- SCALE. The shortened giant emergence: Massive's
-- handlers on Huge's own bounds (the trimmed-variant mechanism, now a cut).
local folder = script.Parent.Parent
local Types = require(folder:WaitForChild("Types"))
local Massive = require(script.Parent:WaitForChild("Massive"))
type Run = Types.Run

local Huge = {}

-- Task 1 state: the shipped HUGE_TRIM bounds, verbatim (no silence, no hype).
Huge.BEATS = {
	{ name = "bonk",     t0 = 0.00, t1 = 0.30 },
	{ name = "travel",   t0 = 0.30, t1 = 1.00 },
	{ name = "dread",    t0 = 1.00, t1 = 1.80 },
	{ name = "eruption", t0 = 1.80, t1 = 2.40 },
	{ name = "rise",     t0 = 2.40, t1 = 3.60 },
	{ name = "handoff",  t0 = 3.60, t1 = 4.30 },
}

Huge.name = "Huge"
Huge.beats = Huge.BEATS
Huge.handlers = Massive.handlers
Huge.everyFrame = Massive.everyFrame
Huge.onSkip = Massive.onSkip
Huge.build = function(run: Run): boolean
	run.size = run.size or "Huge"
	return Massive.build(run)
end
Huge.revealBeat = "eruption"
Huge.skippable = true
Huge.skipTo = "handoff"
Huge.bannerText = "HUGE"

return Huge
```

- [ ] **Step 6: Create `Takeover`** — `Sequencer` minus everything moved in Steps 4–5, plus the cut parameter. Write the whole module:

```lua
--!strict
-- CatchCinematic.Takeover -- THE FRAMEWORK. Everything a camera-takeover cut needs
-- that is not the cut itself: one run per client, the master clock and timescale,
-- the result hold before the cut's reveal beat, the cancel path, hold-to-skip,
-- watchdogs, kill switches, camera + HUD takeover AND restore, the stage folder,
-- audio/post/shake/ui construction, Bridge plumbing and beat dispatch.
--
-- The CUT (Cuts/<Name>) supplies: beats, handlers keyed by beat name, revealBeat,
-- skippable/skipTo/onSkip, onCancel, everyFrame, build(run), bannerText.
-- A cut NEVER writes Camera.CameraType, ScreenGui.Enabled or Lighting: this module
-- (via CameraRig / PostFX) is the only takeover path and the only restore path.
--
-- ================================ RUN FIELDS ================================
-- Set by play() before build:  payload, cut, trove, stage(after build), spectator,
--   beats, beatIdx, t, realElapsed, speed, stretch, budget, surface, horiz, name,
--   size, mutation, rarity, rarityColor, rng, quality, reducedMotion, waterCfg,
--   postCfg, bridgeGen, usesBridge, resultSeen, result, breached, displayName,
--   revealT0, skipping, cancelling, finished.
-- Set by buildRun:  audio, cam?, shake?, post?, hype?  (thrower only for the last 4)
-- Set by the cut's build:  brain, water, rock?, and anything cut-specific.
--
-- ================================ TIMESCALE ================================
-- run.speed = Config.timescale() (cinematic seconds per real second); run.stretch =
-- 1/speed. The conductor advances run.t by dt*speed. Every wall-clock duration a
-- handler passes to a module is cinematicSeconds * run.stretch. Durations inside a
-- module's cfg (Config.WATER / Config.POSTFX) reach the constructors as scaled
-- shallow copies (run.waterCfg / run.postCfg). Skip hold, the luminance dips and
-- ScreenShake decay are deliberately NOT scaled (input/UX, not choreography).
--
-- ================================ LIFECYCLE ================================
-- ONE run table per play, ONE trove drained LIFO by finish(), ONE render binding.
-- finish() is wired to every exit: normal end, skip-into-skipTo (still ends normally),
-- cancel timeout, Humanoid.Died, CharacterAdded, the conductor's pcall handler, and
-- two watchdogs. play() BLOCKS; false means DECLINED (nothing parented) and the
-- caller stages its stock landing; opts.onCommit fires synchronously on commit.
--
-- SKIP SAFETY: a skip jumps to cut.skipTo, which (for every shipped cut) reveals and
-- awards the creature -- so it is gated on the grant having landed. Held early, the
-- dip goes full dark and WAITS; if the grant never comes, cancel takes over from
-- that same dark frame. A skip can never show a catch the cancel path exists to hide.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local folder = script.Parent
local Config = require(folder:WaitForChild("Config"))
local CutKit = require(folder:WaitForChild("CutKit"))
local Types = require(folder:WaitForChild("Types"))
local CameraRig = require(folder:WaitForChild("CameraRig"))
local ScreenShake = require(folder:WaitForChild("ScreenShake"))
local PostFX = require(folder:WaitForChild("PostFX"))
local AudioBus = require(folder:WaitForChild("AudioBus"))
local HypeUI = require(folder:WaitForChild("HypeUI"))
local Bridge = require(folder:WaitForChild("Bridge"))
local Sizes = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SizeConfig"))

type Run = Types.Run
type Cut = Types.Cut

local TAG = "Takeover"
local STAGE_NAME = "CatchCinematicStage"
local FADE_GUI_NAME = "CatchCinematicFade"
local REVEAL_ATTR = "RevealActive"
local BIND_NAME = "CatchCinematicTakeover"
local BIND_PRIORITY = Enum.RenderPriority.Camera.Value - 1
local runCounter = 0
local VM_SALT: string
do
	local ok, guid = pcall(function()
		return game:GetService("HttpService"):GenerateGUID(false)
	end)
	if ok and type(guid) == "string" then
		VM_SALT = string.sub((string.gsub(guid, "%-", "")), 1, 8)
	else
		VM_SALT = string.format("%08x", math.floor(os.clock() * 1e6) % 0xFFFFFFFF)
	end
end

local DIP_MAX = 0.82
local WATCHDOG_PAD = 8
local CANCEL_DIP_IN, CANCEL_DIP_OUT = 0.15, 0.6
local WATER_DURATION_FIELDS = { "domeRiseSeconds", "columnSeconds", "cascadeSeconds" }
local POSTFX_DURATION_FIELDS = { "flashSeconds", "easeBackSeconds" }

local SPECTATOR_SKIP_IGNORED: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.W] = true, [Enum.KeyCode.A] = true, [Enum.KeyCode.S] = true,
	[Enum.KeyCode.D] = true, [Enum.KeyCode.Space] = true,
	[Enum.KeyCode.LeftShift] = true, [Enum.KeyCode.RightShift] = true,
}

export type PlayOpts = {
	spectator: boolean?,
	bridgeGen: number?,
	onCommit: (() -> ())?,
}

local Takeover = {}
local active: Run? = nil

local track = CutKit.track
local function drain(run: Run)
	CutKit.drain(run, TAG)
end

-- ============================== overlay ==============================
local function ensureOverlay(run: Run): Frame?
	if run.overlay then
		return run.overlay
	end
	local player = Players.LocalPlayer
	local pg = player and player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = FADE_GUI_NAME
	gui.DisplayOrder = 60
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Parent = pg
	local dip = Instance.new("Frame")
	dip.Name = "Dip"
	dip.Size = UDim2.fromScale(1, 1)
	dip.BackgroundColor3 = Color3.new(0, 0, 0)
	dip.BackgroundTransparency = 1
	dip.BorderSizePixel = 0
	dip.Parent = gui
	run.overlay = dip
	track(run, function()
		gui:Destroy()
	end)
	return dip
end

-- ============================== finish ==============================
local function finish(run: Run, ok: boolean)
	if run.finished then
		return
	end
	run.finished = true
	run.ok = ok
	drain(run)
	if active == run then
		active = nil
	end
	if run.usesBridge then
		pcall(Bridge.finish, run.bridgeGen, ok)
	end
end

-- ============================== skip ==============================
local function runExit(run: Run)
	local current = run.beats[run.beatIdx]
	if current then
		local h = run.cut.handlers[current.name]
		if h and h.exit then
			h.exit(run)
		end
	end
end

local function jumpTo(run: Run, beatName: string)
	if run.usesBridge and not run.resultSeen then
		warn("[" .. TAG .. "] jump refused: no result yet")
		return
	end
	local idx = CutKit.beatIndexOf(run, beatName)
	if not idx then
		finish(run, true)
		return
	end
	runExit(run)
	if run.cut.onSkip then
		local okS, err = pcall(run.cut.onSkip, run)
		if not okS then
			warn("[" .. TAG .. "] onSkip errored: " .. tostring(err))
		end
	end
	run.beatIdx = idx - 1
	run.t = run.beats[idx].t0
end

local function beginSkip(run: Run)
	if run.skipping or run.cancelling or run.finished then
		return
	end
	if run.spectator then
		run.skipping = true
		finish(run, true)
		return
	end
	run.skipping = true
	run.skipPhase = "out"
	run.skipClock = 0
	if run.hype then
		run.hype:interrupt()
		run.hype:hideSkipPrompt()
	end
	ensureOverlay(run)
end

local function inputQualifies(input: InputObject, spectator: boolean): boolean
	local t = input.UserInputType
	if t == Enum.UserInputType.Keyboard then
		if spectator and SPECTATOR_SKIP_IGNORED[input.KeyCode] then
			return false
		end
		return true
	end
	if t == Enum.UserInputType.Touch then
		return not spectator
	end
	if t == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.ButtonB then
		return true
	end
	return false
end

local function wireSkipInput(run: Run)
	local holds: { [InputObject]: boolean } = {}
	local function recompute()
		run.holdDown = next(holds) ~= nil
	end
	local c1 = UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe or not inputQualifies(input, run.spectator) then
			return
		end
		holds[input] = true
		recompute()
	end)
	local c2 = UserInputService.InputEnded:Connect(function(input)
		if holds[input] then
			holds[input] = nil
			recompute()
		end
	end)
	local c3 = UserInputService.WindowFocusReleased:Connect(function()
		table.clear(holds)
		run.holdDown = false
		run.holdTime = 0
	end)
	track(run, function()
		c1:Disconnect()
		c2:Disconnect()
		c3:Disconnect()
	end)
end

-- ============================== cancel ==============================
local function defaultCancelTeardown(run: Run)
	if run.water then
		run.water:cleanup()
	end
	if run.brain then
		run.brain:cleanup()
		run.brain = nil
	end
	if run.rock then
		run.rock:cleanup()
		run.rock = nil
	end
end

local function beginCancel(run: Run)
	if run.cancelling or run.finished then
		return
	end
	run.cancelling = true
	run.skipping = false
	warn("[" .. TAG .. "] no result within " .. tostring(Config.CANCEL_TIMEOUT) .. "s -- cancelling " .. run.cut.name)
	if run.hype then
		run.hype:interrupt()
		run.hype:hideSkipPrompt()
	end
	if run.cut.onCancel then
		local okC, err = pcall(run.cut.onCancel, run)
		if not okC then
			warn("[" .. TAG .. "] onCancel errored: " .. tostring(err))
		end
	end
	defaultCancelTeardown(run)
	if run.shake then
		run.shake:setSustain(0)
	end
	if run.post then
		run.post:easeBack(0.25)
	end
	if run.audio then
		run.audio:unsilence()
		run.audio:play("waterExplosion", { where = run.surface })
		run.audio:restoreAmbient(0.35)
	end
	local dip0 = ensureOverlay(run)
	local alpha0 = dip0 and math.clamp((1 - dip0.BackgroundTransparency) / DIP_MAX, 0, 1) or 0
	run.cancelClock = alpha0 * CANCEL_DIP_IN
	run.cancelDeadline = CANCEL_DIP_IN + CANCEL_DIP_OUT + 0.5
	if run.cam then
		run.cam:returnToPlayer((Config.CAMERA.returnBlendSeconds or 0.8) * 0.7, function()
			finish(run, false)
		end)
	end
end

-- ============================== conductor ==============================
local function stepInner(run: Run, dt: number)
	run.realElapsed += dt
	if run.realElapsed > run.budget then
		warn("[" .. TAG .. "] watchdog fired at " .. string.format("%.2f", run.realElapsed) .. "s")
		finish(run, false)
		return
	end

	-- (1) master clock, with the pre-reveal result hold
	local newT = run.t + dt * run.speed
	if not run.spectator and not run.resultSeen and not run.cancelling then
		if newT >= run.revealT0 and run.realElapsed < run.cancelTimeout then
			newT = math.min(newT, run.revealT0 - 1e-3)
		end
	end
	run.t = newT

	-- (2) cancel deadline
	if not run.spectator and not run.resultSeen and not run.cancelling then
		if run.realElapsed >= run.cancelTimeout then
			beginCancel(run)
		end
	end
	if run.cancelling then
		run.cancelClock += dt
		local dip = run.overlay
		if dip then
			local a: number
			if run.cancelClock <= CANCEL_DIP_IN then
				a = run.cancelClock / CANCEL_DIP_IN
			else
				a = math.clamp(1 - (run.cancelClock - CANCEL_DIP_IN) / CANCEL_DIP_OUT, 0, 1)
			end
			dip.BackgroundTransparency = 1 - a * DIP_MAX
		end
		if run.cancelClock >= run.cancelDeadline then
			finish(run, false)
		end
		return
	end

	-- (3) result reconciliation: the server's roll can be superseded at reveal time
	if run.usesBridge and not run.resultSeen then
		local res = Bridge.result(run.bridgeGen)
		if res ~= nil then
			run.resultSeen = true
			run.result = res
			local name = res.BrainrotName
			if type(name) == "string" and name ~= "" and name ~= run.name and not run.breached and run.brain then
				if run.brain:swapModel(name) then
					run.name = name
					CutKit.refreshGeometry(run)
					run.displayName = Sizes.Label(res.Mutation or run.mutation, run.size, name)
				end
			end
		end
	end

	-- (4) skip
	if run.skipEnabled and not run.skipArmed and run.t >= run.skipDelay then
		run.skipArmed = true
		if run.hype then
			run.hype:showSkipPrompt()
		end
	end
	if run.skipArmed and not run.skipping then
		if run.holdDown then
			run.holdTime += dt
		else
			run.holdTime = 0
		end
		local a = math.clamp(run.holdTime / run.skipHold, 0, 1)
		if run.hype then
			run.hype:setSkipProgress(a)
		end
		if a >= 1 then
			beginSkip(run)
		end
	end
	if run.skipping and run.skipPhase ~= "done" then
		run.skipClock += dt
		local half = math.max(run.skipFade * 0.5, 0.02)
		local dip = run.overlay
		local a = math.clamp(run.skipClock / half, 0, 1)
		if run.skipPhase == "out" then
			if dip then
				dip.BackgroundTransparency = 1 - a * DIP_MAX
			end
			if a >= 1 then
				if run.usesBridge and not run.resultSeen then
					run.skipHolding = true
				else
					run.skipHolding = false
					jumpTo(run, run.cut.skipTo or run.beats[#run.beats].name)
					run.skipPhase = "in"
					run.skipClock = 0
				end
			end
		else
			if dip then
				dip.BackgroundTransparency = 1 - (1 - a) * DIP_MAX
			end
			if a >= 1 then
				run.skipPhase = "done"
				if dip then
					dip.BackgroundTransparency = 1
				end
			end
		end
	end
	if run.finished then
		return
	end

	-- (5) the cut's per-frame work (rock, one-shots), pure in run.t
	if run.cut.everyFrame then
		run.cut.everyFrame(run)
	end

	-- (6) beat dispatch
	while run.beatIdx < #run.beats do
		local nextBeat = run.beats[run.beatIdx + 1]
		if run.t < nextBeat.t0 then
			break
		end
		runExit(run)
		run.beatIdx += 1
		local h = run.cut.handlers[nextBeat.name]
		if h and h.enter then
			h.enter(run)
		end
	end
	local beat = run.beats[run.beatIdx]
	if beat then
		local span = math.max(beat.t1 - beat.t0, 1e-3)
		local p = math.clamp((run.t - beat.t0) / span, 0, 1)
		local h = run.cut.handlers[beat.name]
		if h and h.update then
			h.update(run, p)
		end
	end

	-- (7) end of timeline
	if run.t >= run.beats[#run.beats].t1 then
		finish(run, true)
	end
end

local function step(run: Run, dt: number)
	if run.finished then
		return
	end
	local ok, err = pcall(stepInner, run, dt)
	if not ok then
		warn("[" .. TAG .. "] beat error, tearing down: " .. tostring(err))
		finish(run, false)
	end
end

-- ============================== build ==============================
-- Stage folder stays parented to NIL until every constructor has succeeded, so a
-- decline can happen with literally nothing in the world yet.
local function buildRun(run: Run): boolean
	local stage = Instance.new("Folder")
	stage.Name = STAGE_NAME
	run.stage = stage
	track(run, function()
		stage:Destroy()
	end)

	local okB, built = pcall(run.cut.build, run)
	if not okB then
		warn("[" .. TAG .. "] " .. run.cut.name .. " build errored: " .. tostring(built))
		return false
	end
	if built ~= true then
		return false
	end

	local audio = AudioBus.new(Config.ASSETS)
	run.audio = audio
	track(run, function()
		audio:cleanup()
	end)

	if not run.spectator then
		local player = Players.LocalPlayer
		-- The input lock (spec S11): throw/cast input refuses while this is set.
		-- Tracked so every exit path clears it.
		if player then
			player:SetAttribute(REVEAL_ATTR, true)
			track(run, function()
				player:SetAttribute(REVEAL_ATTR, nil)
			end)
		end

		local cam = CameraRig.new(Config.CAMERA)
		if cam:takeover() then
			run.cam = cam
			track(run, function()
				cam:restore()
			end)
			-- HIDE THE GAME HUD. Re-enabled by the trove on EVERY exit path; our own
			-- guis are never touched; a gui that vanishes mid-cut is skipped by the pcall.
			local pg = player and player:FindFirstChildOfClass("PlayerGui")
			if pg then
				local hidden = {}
				for _, g in ipairs(pg:GetChildren()) do
					if g:IsA("ScreenGui") and g.Enabled and g.Name ~= "CatchCinematicUI" and g.Name ~= FADE_GUI_NAME then
						g.Enabled = false
						table.insert(hidden, g)
					end
				end
				track(run, function()
					for _, g in ipairs(hidden) do
						pcall(function()
							g.Enabled = true
						end)
					end
				end)
			end
			local shake = ScreenShake.new(CutKit.shallowMerge(Config.SHAKE, {
				shakeMult = run.reducedMotion and (Config.REDUCED_MOTION.shakeMult or 0.25) or 1,
			}))
			run.shake = shake
			local lastSample = os.clock()
			cam:setShakeSource(function()
				local now = os.clock()
				local d = math.clamp(now - lastSample, 0, 0.1)
				lastSample = now
				return shake:sample(d)
			end)
		else
			warn("[" .. TAG .. "] camera takeover refused -- running without the camera")
		end

		local post = PostFX.new(run.postCfg, run.quality, run.reducedMotion)
		run.post = post
		track(run, function()
			post:cleanup()
		end)

		local hype = HypeUI.new(
			{ HYPE = Config.HYPE, SKIP = Config.SKIP, PARTICLES = Config.PARTICLES },
			run.quality, run.reducedMotion, run.rng, run.stretch
		)
		run.hype = hype
		track(run, function()
			hype:cleanup()
		end)
	end

	wireSkipInput(run)
	stage.Parent = Workspace
	return true
end

local function wireKillSwitches(run: Run)
	local player = Players.LocalPlayer
	if not player then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		local c = hum.Died:Connect(function()
			finish(run, false)
		end)
		track(run, function()
			c:Disconnect()
		end)
	end
	local ca = player.CharacterAdded:Connect(function()
		finish(run, false)
	end)
	track(run, function()
		ca:Disconnect()
	end)
end

-- ============================== public ==============================
function Takeover.isActive(): boolean
	return active ~= nil
end

function Takeover.debugState(): { [string]: any }?
	local run = active
	if not run then
		return nil
	end
	return {
		cut = run.cut.name, t = run.t, beat = run.beats[run.beatIdx] and run.beats[run.beatIdx].name,
		resultSeen = run.resultSeen, skipping = run.skipping, cancelling = run.cancelling,
		spectator = run.spectator, realElapsed = run.realElapsed,
	}
end

-- Studio harness seam: simulate the skip hold without real input.
function Takeover.debugHold(down: boolean)
	local run = active
	if run and RunService:IsStudio() then
		run.holdDown = down == true
		if not down then
			run.holdTime = 0
		end
	end
end

function Takeover.play(cut: Cut, payload: { [string]: any }, opts: PlayOpts?): boolean
	if active ~= nil then
		return false
	end
	if type(cut) ~= "table" or type(cut.beats) ~= "table" or #cut.beats == 0 then
		return false
	end
	if type(payload) ~= "table" or typeof(payload.EndPos) ~= "Vector3" then
		return false
	end
	if type(payload.BrainrotName) ~= "string" or payload.BrainrotName == "" then
		return false
	end
	local o = opts or {}
	local spectator = o.spectator == true
	local bridgeGen = o.bridgeGen
	local usesBridge = (not spectator) and Bridge.isCurrent(bridgeGen)
	local player = Players.LocalPlayer
	if not player then
		return false
	end

	local speed = Config.timescale()
	if type(speed) ~= "number" or speed <= 0 then
		speed = 1
	end
	local stretch = 1 / speed
	local endPos = payload.EndPos :: Vector3
	local surfaceY = tonumber(payload.SurfaceY) or endPos.Y
	local surface = Vector3.new(endPos.X, surfaceY, endPos.Z)
	local beats = cut.beats
	local mutation = (type(payload.Mutation) == "string" and payload.Mutation ~= "" and payload.Mutation ~= "None") and payload.Mutation or nil

	local run: Run = {
		payload = payload, cut = cut, trove = {}, cleaned = false, finished = false, ok = false,
		spectator = spectator, beats = beats, beatIdx = 0, t = 0, realElapsed = 0,
		speed = speed, stretch = stretch,
		budget = beats[#beats].t1 * stretch + WATCHDOG_PAD,
		surface = surface, horiz = CutKit.horizToward(surface),
		name = payload.BrainrotName, size = payload.Size, mutation = mutation,
		rarity = payload.Rarity,
		rarityColor = (typeof(payload.RarityColor) == "Color3") and payload.RarityColor or Color3.fromRGB(255, 220, 120),
		rng = Random.new(tonumber(payload.Seed) or 1),
		quality = Config.qualityFor(player),
		reducedMotion = player:GetAttribute("CinematicReducedMotion") == true,
		waterCfg = CutKit.scaleDurations(Config.WATER, WATER_DURATION_FIELDS, stretch),
		postCfg = CutKit.scaleDurations(Config.POSTFX, POSTFX_DURATION_FIELDS, stretch),
		bridgeGen = bridgeGen, usesBridge = usesBridge, committed = false,
		resultSeen = not usesBridge, breached = false,
		skipEnabled = spectator or cut.skippable == true,
		skipArmed = false, skipping = false, skipPhase = "none", skipClock = 0,
		holdDown = false, holdTime = 0, skipHolding = false,
		skipDelay = Config.SKIP.delay or 1.0,
		skipHold = math.max(Config.SKIP.holdSeconds or 0.45, 0.05),
		skipFade = math.max(Config.SKIP.exitFadeSeconds or 0.18, 0.04),
		cancelling = false, cancelClock = 0,
		cancelDeadline = CANCEL_DIP_IN + CANCEL_DIP_OUT + 0.5,
		cancelTimeout = math.max(tonumber(Config.CANCEL_TIMEOUT) or 3.0, 0.25) * stretch,
	}
	run.displayName = Sizes.Label(mutation, run.size, run.name)
	run.revealT0 = CutKit.beatT0(run, cut.revealBeat, beats[#beats].t1)

	active = run
	local okBuild, buildResult = pcall(buildRun, run)
	if not okBuild then
		warn("[" .. TAG .. "] build errored: " .. tostring(buildResult))
		drain(run)
		active = nil
		return false
	end
	if buildResult ~= true then
		drain(run)
		active = nil
		return false
	end

	if run.usesBridge then
		pcall(Bridge.markRunning, run.bridgeGen, run.budget + 4)
	end
	wireKillSwitches(run)

	runCounter += 1
	run.bindName = BIND_NAME .. VM_SALT .. "_" .. tostring(runCounter)
	local bindOk = pcall(function()
		RunService:BindToRenderStep(run.bindName, BIND_PRIORITY, function(dt: number)
			step(run, dt)
		end)
	end)
	if not bindOk then
		warn("[" .. TAG .. "] could not bind the conductor")
		drain(run)
		active = nil
		return false
	end
	track(run, function()
		pcall(function()
			RunService:UnbindFromRenderStep(run.bindName)
		end)
	end)
	task.delay(run.budget + 2, function()
		if active == run and not run.finished then
			warn("[" .. TAG .. "] backstop watchdog fired")
			finish(run, false)
		end
	end)

	run.committed = true
	if o.onCommit then
		pcall(o.onCommit)
	end
	while not run.finished do
		task.wait()
	end
	return true
end

return Takeover
```

Compile-check. Note the one intentional behaviour difference from `Sequencer`: `payload.Size` is optional (rarity cuts have none). Everything else is a move.

- [ ] **Step 7: Re-point `CinematicClient` at `Takeover`.** Backup, then `multi_edit`:
  1. `local Sequencer = softRequire("Sequencer")` → `local Takeover = softRequire("Takeover")`, followed by the fail-soft Registry require (a Folder cannot go through `softRequire`, which `require`s its argument):
     ```lua
     -- Cuts.Registry, fail-soft like the two above: nil means no cut can be looked up,
     -- so every broadcast collapses to the stock landing.
     local Registry = nil
     do
     	local cuts = cinFolder:WaitForChild("Cuts", 5)
     	local inst = cuts and cuts:WaitForChild("Registry", 5)
     	if inst then
     		local ok, mod = pcall(require, inst)
     		if ok then
     			Registry = mod
     		else
     			warn("[CinematicClient] Cuts.Registry failed to load (" .. tostring(mod) .. ") -- stock landings only")
     		end
     	else
     		warn("[CinematicClient] Cuts.Registry missing -- stock landings only")
     	end
     end
     ```
  2. Every `Sequencer` reference → `Takeover` (`Sequencer ~= nil`, `Sequencer.isActive()`, the `Sequencer.play` call, the warn strings).
  3. Replace the variant block:
     ```lua
     local variant = (Config.SIZES :: any)[payload.Size]
     if RunService:IsStudio() and (payload.__variantOverride == "trimmed" or payload.__variantOverride == "full") then
     	variant = payload.__variantOverride
     end
     local wants = (variant == "full" or variant == "trimmed") and Sequencer ~= nil
     ```
     with
     ```lua
     -- Task 1: the cut is still chosen from Config.SIZES (Task 3 moves this to
     -- payload.Cut / Config.CUT_FOR). "full" -> Massive, "trimmed" -> Huge.
     local variant = (Config.SIZES :: any)[payload.Size]
     if RunService:IsStudio() and (payload.__variantOverride == "trimmed" or payload.__variantOverride == "full") then
     	variant = payload.__variantOverride
     end
     local cutName: string? = (variant == "full") and "Massive" or (variant == "trimmed") and "Huge" or nil
     local cut = (cutName and Registry) and Registry.get(cutName) or nil
     local wants = cut ~= nil and Takeover ~= nil
     ```
  4. The play call becomes `pcall(Takeover.play, cut, payload, { spectator = spectator, bridgeGen = bridgeGen, onCommit = function() committed = true end })`.

  Compile-check. Local-declaration diff vs backup: expect only `Takeover`, `Registry`, `cutName`, `cut` added and `Sequencer`, `variant`-uses changed.

- [ ] **Step 8: Move the beat tables out of `Config`.** `multi_edit` `Config`: delete `Config.BEATS = {...}`, `Config.SECOND_BONK_T = 10.6`, `Config.HUGE_TRIM = {...}` and their comments (they now live in `Cuts.Massive.BEATS` / `Cuts.Huge.BEATS`). Then `script_grep` the whole place for `Config.BEATS`, `HUGE_TRIM`, `SECOND_BONK_T` — expected hits: none outside `Sequencer` (which Step 10 deletes). If `CinematicCommand` reads any, edit it to stop.

- [ ] **Step 9: Run the harness against `Takeover` and compare with Step 1.** Play mode, same spot:

```lua
workspace:SetAttribute("CinematicTimescale", 4)
local H = require(game.ReplicatedStorage.Modules.CatchCinematic.Harness)
H.matrix("Takeover", "Massive")
H.matrix("Takeover", "Huge")
workspace:SetAttribute("CinematicTimescale", nil)
```

Expected: 8 `OK` lines; each `seconds` within ±0.3s of the Step 1 baseline for the same cut/mode. Then one **real** Massive throw (`ServerStorage:SetAttribute("ForceNextSize", "Massive")` from a server `execute_luau`, then throw from the hub dock) — confirm the cut plays, the creature streaks into the bag, the camera returns, and `ThrowResult` was adopted (no duplicate pop). Revert the granted catch by exact Uid afterwards (Global Constraints: real datastore).

- [ ] **Step 10: Delete `Sequencer`, mirror, commit.** Back up `Sequencer` to `AuditBackups.PreReveal_2026_09_17.Sequencer_final`, then destroy the live instance. `script_grep` for `Sequencer` across the place: expected only comments in `Bridge`/`CinematicCommand` headers (edit those comments to say `Takeover`). Mirror: write `Takeover.lua`, `CutKit.lua`, `Types.lua`, `Config.lua`, `Harness.lua`, `Cuts/Registry.lua`, `Cuts/Massive.lua`, `Cuts/Huge.lua`, `CinematicClient.client.lua`; delete `game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/Sequencer.lua`.

```bash
git add game-src/place-full/ReplicatedStorage/Modules/CatchCinematic game-src/place-full/StarterPlayer/StarterPlayerScripts/CinematicClient.client.lua
git commit -m "refactor(cinematic): split Sequencer into Takeover framework + Cuts/Massive + Cuts/Huge (behaviour-preserving)"
```

---

### Task 2: Re-pace Massive to the blueprint, remove the comedy layer, switch Huge on

**Files:**
- Modify: `Cuts.Massive` (beats + handlers), `Cuts.Huge` (beats + `splash` handler)
- Rewrite: `ReplicatedStorage.Modules.CatchCinematic.RockRig`
- Modify: `HypeUI` (remove memeFlyIns/confetti/speedLines), `Config` (HYPE, ROCK, ASSETS, SIZES)

**Interfaces:**
- Consumes: Task 1's `CutKit.farFraming`, `Takeover`.
- Produces: `Massive.handlers` = `{ bonk, still, ripple, disturbed, silhouette, emergence, scale, banner, aftermath, handoff }` (Huge and MassiveGod reuse them); `RockRig.new(cfg, stage, rockId, rockColor, surface, rng)` unchanged signature, `RockRig:update(t)`, `RockRig:cleanup()`.

- [ ] **Step 1: Write the timing assertion first.** Add to `Harness`:

```lua
-- Asserts a cut's beat table is contiguous, starts at 0, and ends within [lo, hi].
function Harness.checkBeats(cutName: string, lo: number, hi: number): { string }
	local Registry = require(ReplicatedStorage.Modules.CatchCinematic.Cuts.Registry)
	local cut = Registry.get(cutName)
	local f: { string } = {}
	if not cut then
		table.insert(f, "no cut")
		return f
	end
	local beats = cut.beats
	if beats[1].t0 ~= 0 then table.insert(f, "does not start at 0") end
	for i = 1, #beats - 1 do
		if math.abs(beats[i].t1 - beats[i + 1].t0) > 1e-6 then
			table.insert(f, "gap between " .. beats[i].name .. " and " .. beats[i + 1].name)
		end
	end
	local total = beats[#beats].t1
	if total < lo or total > hi then table.insert(f, "total " .. total .. " outside [" .. lo .. "," .. hi .. "]") end
	for _, b in ipairs(beats) do
		if not cut.handlers[b.name] then table.insert(f, "no handler for beat " .. b.name) end
	end
	if not cut.handlers[cut.revealBeat] then table.insert(f, "revealBeat missing") end
	if cut.skippable and not (cut.skipTo and cut.handlers[cut.skipTo]) then table.insert(f, "skipTo missing") end
	return f
end
```

Run `Harness.checkBeats("Massive", 10.0, 11.0)` — expected FAIL (`total 17.9 outside`).

- [ ] **Step 2: Rewrite `RockRig` as a sink, not a ricochet.** Backup, then replace its Source:

```lua
--!strict
-- CatchCinematic.RockRig -- the thrown rock during a cut. The server destroys its
-- own stone for every client on a cinematic throw, so this stages the final skip
-- contact: the rock sits on the surface at t=0, sinks over cfg.sinkSeconds with a
-- slow tumble, then hides. No ricochet, no second bonk (removed 2026-09-17 with the
-- comedy layer -- spec S8).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RockDesign = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RockDesign"))

export type RockRigCfg = { sinkSeconds: number?, sinkDepth: number?, spinRadPerSec: number? }
export type Rig = typeof(setmetatable({} :: { [string]: any }, {} :: { __index: any }))

local RockRig = {}
RockRig.__index = RockRig

function RockRig.new(cfg: RockRigCfg, stage: Folder, rockId: string?, rockColor: Color3?, surface: Vector3, rng: Random): Rig
	local self = setmetatable({}, RockRig)
	self.cfg = cfg
	self.surface = surface
	self.rng = rng
	self._destroyed = false
	local model = RockDesign.Build(rockId, rockColor or Color3.fromRGB(105, 100, 96))
	model.Name = "CinematicRock"
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	model:PivotTo(CFrame.new(surface + Vector3.new(0, 0.4, 0)))
	model.Parent = stage
	self.model = model
	self.hidden = false
	return self
end

-- Pure in t (cinematic seconds). Sink from the surface to -sinkDepth over sinkSeconds
-- with a slow tumble, then hide.
function RockRig:update(t: number)
	if self._destroyed or self.hidden then
		return
	end
	local secs = math.max(self.cfg.sinkSeconds or 0.8, 0.05)
	local depth = self.cfg.sinkDepth or 2.0
	local spin = self.cfg.spinRadPerSec or 2.0
	local p = math.clamp(t / secs, 0, 1)
	local y = 0.4 - depth * p * p
	local cf = CFrame.new(self.surface + Vector3.new(0, y, 0)) * CFrame.Angles(spin * t, spin * 0.7 * t, 0)
	self.model:PivotTo(cf)
	if p >= 1 then
		self.hidden = true
		for _, d in ipairs(self.model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Transparency = 1
			end
		end
	end
end

function RockRig:cleanup()
	if self._destroyed then
		return
	end
	self._destroyed = true
	if self.model then
		self.model:Destroy()
		self.model = nil
	end
end

return RockRig
```

`Config.ROCK` becomes `Config.ROCK = { sinkSeconds = 0.8, sinkDepth = 2.0, spinRadPerSec = 2.0 }` (multi_edit, replacing the ricochet fields and their comments).

- [ ] **Step 3: Rewrite `Cuts.Massive`'s beats and handlers to the blueprint (spec §6.5).** Replace the module's beat table, handlers, `everyFrame`, `onSkip` and `bannerText`; `build` keeps Task 1's shape minus `plinked/domeUp/punch*/secondBonkT` and minus `rockTimings` (delete that helper; `RockRig.new` now takes `Config.ROCK` directly). Full replacement of everything below the requires:

```lua
local Massive = {}

-- ===== TUNABLES (this cut's own; spec S6.5) =====
-- t = 0 is the final skip contact. Dread (still -> silhouette) ~2.6s; emergence +
-- pull-back ~3.4s; total 10.6s. Intimidating, not comedic.
Massive.BEATS = {
	{ name = "bonk",       t0 = 0.00, t1 = 0.50 },  -- I   the rock; camera starts toward the water
	{ name = "still",      t0 = 0.50, t1 = 1.00 },  -- II  nothing
	{ name = "ripple",     t0 = 1.00, t1 = 2.00 },  -- II  tiny ripple, then bigger
	{ name = "disturbed",  t0 = 2.00, t1 = 2.50 },  -- II  violent water, rumble
	{ name = "silhouette", t0 = 2.50, t1 = 3.10 },  -- III darkens; silhouette, eyes
	{ name = "emergence",  t0 = 3.10, t1 = 4.10 },  -- IV  slow rise, huge splash
	{ name = "scale",      t0 = 4.10, t1 = 6.50 },  -- V   camera pulls WAY back
	{ name = "banner",     t0 = 6.50, t1 = 7.20 },  -- VI  MASSIVE
	{ name = "aftermath",  t0 = 7.20, t1 = 9.50 },  -- VII settle
	{ name = "handoff",    t0 = 9.50, t1 = 10.60 }, -- VII streak into bag; restore
}
Massive.EMERGENCE_RISE_TO = 0.5     -- fraction of the rise done by the end of `emergence`
Massive.RIPPLE_SLOW_FRAC = 0.35     -- ripple beat: how far the train gets by its end
Massive.SHADOW_AT_SILHOUETTE = 1.0  -- suctionAndShadow progress reached by the silhouette's end

-- ===== helpers =====
local function calmAngry(run: Run)
	if run.brain then
		run.brain:calmEyes()
	end
	if run.model then
		local rim = run.model:FindFirstChild("CinematicAura")
		if rim and rim:IsA("Highlight") then
			rim.OutlineColor = run.rarityColor
		end
	end
end

-- Aim the creature so the rise's slow turn (0.6*pi inside setRise) lands square on
-- the camera. Moved from the old enterEruption.
local function faceCamera(run: Run)
	if not run.brain then
		return
	end
	if run.heroEye == nil then
		local eye, focus = CutKit.heroFraming(run)
		run.heroEye, run.heroFocus = eye, focus
	end
	local aim = (run.heroEye or (run.surface + run.horiz * -40)) - run.surface
	run.brain:setFacing(math.atan2(aim.X, aim.Z) - math.pi * 0.6)
end

-- ===== beat handlers =====
local function enterBonk(run: Run)
	if run.water then
		run.water:stillWater()
		run.water:bonkRing()
	end
	if run.audio then
		run.audio:play("finalSkip", { where = run.surface })
		if not run.spectator then
			run.audio:duckAmbient(0.35, 0.25 * run.stretch)
		end
	end
	if run.shake then
		run.shake:add(0.35)
	end
	if run.cam then
		local c = Config.CAMERA
		local eye = run.surface - run.horiz * CutKit.TRAVEL_BACK_STUDS + Vector3.new(0, c.outboundHeight or 6, 0)
		run.travelEye = eye
		-- the fly-out spans bonk + still: both beats' seconds
		local secs = (CutKit.beatT0(run, "ripple", 1.0)) * run.stretch
		run.cam:flyTo(CFrame.lookAt(eye, run.surface), secs, true)
	end
end

local function enterStill(run: Run)
	-- Nothing. Glassy water is the beat.
end

local function updateRipple(run: Run, p: number)
	if run.water then
		run.water:rippleTrain(p * Massive.RIPPLE_SLOW_FRAC)
	end
end

local function enterDisturbed(run: Run)
	if run.audio then
		-- speed = run.speed so a debug timescale pitches the build instead of letting
		-- a 1x clip bleed over the silhouette.
		run.audio:play("massiveRumble", { where = run.surface, speed = run.speed })
	end
	if run.cam then
		local eye = run.travelEye or (run.surface - run.horiz * CutKit.TRAVEL_BACK_STUDS + Vector3.new(0, 6, 0))
		run.cam:lookHover(eye, run.surface)
	end
end

local function updateDisturbed(run: Run, p: number)
	if run.water then
		run.water:rippleTrain(Massive.RIPPLE_SLOW_FRAC + p * (1 - Massive.RIPPLE_SLOW_FRAC))
		run.water:suctionAndShadow(p * 0.5)
	end
	if run.shake then
		run.shake:setSustain((Config.SHAKE.dreadRampTo or 0.4) * p)
	end
end

local function enterSilhouette(run: Run)
	if run.brain then
		run.brain:stageBelow()
		faceCamera(run)
		-- glowing eyes under the surface where the model has eye parts; the aura rim
		-- carries the read for the 170/191 models that don't (enterEmergence).
		run.eyesApplied = run.brain:angryEyes()
	end
end

local function updateSilhouette(run: Run, p: number)
	if run.water then
		run.water:suctionAndShadow(0.5 + p * 0.5 * Massive.SHADOW_AT_SILHOUETTE)
	end
	if run.shake then
		run.shake:setSustain((Config.SHAKE.dreadRampTo or 0.4) + 0.2 * p)
	end
end

local function enterEmergence(run: Run)
	if run.water then
		run.water:erupt(run.extents)
	end
	if run.brain then
		run.brain:markBreached()
		run.breached = true
	end
	if run.model then
		pcall(function()
			local rim = Instance.new("Highlight")
			rim.Name = "CinematicAura"
			rim.FillTransparency = 1
			rim.OutlineColor = run.eyesApplied and run.rarityColor or Color3.fromRGB(255, 45, 25)
			rim.OutlineTransparency = 0.25
			rim.DepthMode = Enum.HighlightDepthMode.Occluded
			rim.Parent = run.model
		end)
	end
	if run.post then
		run.post:flash()
	end
	if run.audio then
		run.audio:play("bassDrop", { where = run.surface })
		run.audio:play("waterExplosion", { where = run.surface })
		run.audio:play("massiveRoar", { where = run.surface })
	end
	if run.shake then
		run.shake:add(Config.SHAKE.eruption or 1.0)
	end
	if run.cam then
		local c = Config.CAMERA
		run.cam:punchFOV(c.fovPunchHi or 95, c.fovBase or 70, 0.45 * run.stretch)
		local eye, focus = CutKit.heroFraming(run)
		run.heroEye, run.heroFocus = eye, focus
		run.cam:lookHover(eye, focus)
	end
end

local function updateEmergence(run: Run, p: number)
	if run.brain and not run.skipping then
		run.brain:setRise(p * Massive.EMERGENCE_RISE_TO)
	end
end

local function enterScale(run: Run)
	if run.brain then
		run.brain:revealColors(0.6 * run.stretch)
	end
	if run.water and run.model then
		run.water:cascade(run.model, run.waterCfg.cascadeSeconds or 2.0)
	end
	if run.shake then
		run.shake:setSustain(Config.SHAKE.riseSustain or 0.10)
	end
	if run.cam then
		-- THE PULL-BACK: fly from the hero framing to the far framing over the whole
		-- beat, so the creature keeps growing in the frame as the camera retreats.
		local eye, focus = CutKit.farFraming(run)
		run.farEye, run.farFocus = eye, focus
		run.cam:flyTo(CFrame.lookAt(eye, focus), CutKit.beatSeconds(run), false)
	end
end

local function updateScale(run: Run, p: number)
	if run.brain and not run.skipping then
		run.brain:setRise(Massive.EMERGENCE_RISE_TO + p * (1 - Massive.EMERGENCE_RISE_TO))
	end
end

local function enterBanner(run: Run)
	calmAngry(run)
	if run.hype then
		run.hype:banner(run.cut.bannerText, run.rarityColor)
		run.hype:nameText(run.displayName)
	end
	if run.audio then
		run.audio:play("bannerHit", { where = run.surface })
	end
	if run.shake then
		run.shake:add(0.3)
	end
	if run.cam and run.farEye then
		run.cam:lookHover(run.farEye, run.farFocus)
	end
end

local function enterAftermath(run: Run)
	if run.shake then
		run.shake:setSustain(0.04)
	end
	if run.cam and run.farFocus then
		local ext = run.extents :: Vector3
		local dist = (run.farEye - run.farFocus).Magnitude
		run.cam:orbit(run.farFocus, 18, CutKit.beatSeconds(run), dist, ext.Y * (Config.CAMERA.farHeightFrac or 0.35))
	end
end

local function enterHandoff(run: Run)
	calmAngry(run)
	if run.shake then
		run.shake:setSustain(0)
	end
	if run.hype then
		run.hype:hideSkipPrompt()
	end
	if run.post then
		run.post:easeBack(run.postCfg.easeBackSeconds or 1.2)
	end
	if run.audio then
		run.audio:play("cardWhoosh", run.spectator and { where = run.surface } or nil)
		run.audio:restoreAmbient(0.6 * run.stretch)
	end
	local seconds = CutKit.beatSeconds(run) * 0.42
	if run.spectator then
		return
	end
	if run.brain then
		local target = Vector2.new(0.86, 0.92)
		if run.hype then
			local px = run.hype:bagTarget()
			local cam = Workspace.CurrentCamera
			local vs = cam and cam.ViewportSize or Vector2.new(1280, 720)
			if vs.X > 0 and vs.Y > 0 then
				target = Vector2.new(math.clamp(px.X / vs.X, 0, 1), math.clamp(px.Y / vs.Y, 0, 1))
			end
		end
		run.brain:compressAndStreak(target, seconds, function()
			if run.hype then
				run.hype:cardArrive(run.rarityColor)
			end
		end)
	end
	if run.cam then
		run.cam:returnToPlayer((Config.CAMERA.returnBlendSeconds or 0.8) * run.stretch, nil)
	end
end

local function updateHandoff(run: Run, p: number)
	if run.spectator and run.brain then
		run.brain:setRise(1 - p)
	end
end

Massive.handlers = {
	bonk       = { enter = enterBonk },
	still      = { enter = enterStill },
	ripple     = { update = updateRipple },
	disturbed  = { enter = enterDisturbed, update = updateDisturbed },
	silhouette = { enter = enterSilhouette, update = updateSilhouette },
	emergence  = { enter = enterEmergence, update = updateEmergence },
	scale      = { enter = enterScale, update = updateScale },
	banner     = { enter = enterBanner },
	aftermath  = { enter = enterAftermath },
	handoff    = { enter = enterHandoff, update = updateHandoff },
}

function Massive.everyFrame(run: Run)
	if run.rock then
		run.rock:update(run.t)
	end
end

-- Skip lands on `banner`: everything the skipped beats would have left behind, set
-- directly under the darkest frame of the dip. Never a hard cut.
function Massive.onSkip(run: Run)
	if run.hype then
		run.hype:interrupt()
		run.hype:hideSkipPrompt()
	end
	if run.water then
		run.water:cleanup()
	end
	calmAngry(run)
	if run.brain then
		run.brain:markBreached()
		run.breached = true
		run.brain:setRise(1)
		run.brain:revealColors(0.05)
	end
	if run.shake then
		run.shake:setSustain(0)
	end
	if run.audio then
		run.audio:unsilence()
	end
	if run.post then
		run.post:easeBack(0.2)
	end
	if run.cam then
		local eye, focus = CutKit.farFraming(run)
		run.farEye, run.farFocus = eye, focus
		run.cam:lookHover(eye, focus)
	end
end

function Massive.build(run: Run): boolean
	local stage = run.stage :: Folder
	local brain = BrainrotRig.new(stage, run.name, run.size or "Massive", run.surface)
	if not brain then
		warn("[Cuts.Massive] declining: no model for '" .. tostring(run.name) .. "'")
		return false
	end
	run.brain = brain
	CutKit.track(run, function()
		brain:cleanup()
	end)
	CutKit.refreshGeometry(run)
	if run.payload.RockId ~= nil then
		local rock = RockRig.new(Config.ROCK, stage, run.payload.RockId, run.payload.RockColor, run.surface, run.rng)
		run.rock = rock
		CutKit.track(run, function()
			rock:cleanup()
		end)
	end
	local water = WaterFX.new(run.waterCfg, Config.PARTICLES, stage, run.surface, run.quality, run.rng)
	run.water = water
	CutKit.track(run, function()
		water:cleanup()
	end)
	return true
end

Massive.calmAngry = calmAngry
Massive.faceCamera = faceCamera
Massive.name = "Massive"
Massive.beats = Massive.BEATS
Massive.revealBeat = "emergence"
Massive.skippable = true
Massive.skipTo = "banner"
Massive.bannerText = "MASSIVE"

return Massive
```

- [ ] **Step 4: Rewrite `Cuts.Huge`'s beats (spec §6.4) and add its `splash` handler.**

```lua
Huge.BEATS = {
	{ name = "bonk",       t0 = 0.00, t1 = 0.30 },
	{ name = "ripple",     t0 = 0.30, t1 = 0.80 },  -- water moves strangely (0.30), large ripple (0.70)
	{ name = "splash",     t0 = 0.80, t1 = 1.20 },  -- water starts splashing
	{ name = "silhouette", t0 = 1.20, t1 = 1.50 },
	{ name = "emergence",  t0 = 1.50, t1 = 2.00 },
	{ name = "scale",      t0 = 2.00, t1 = 3.40 },
	{ name = "banner",     t0 = 3.40, t1 = 4.00 },  -- HUGE; remains in the water; settles
	{ name = "handoff",    t0 = 4.00, t1 = 4.80 },
}

local function updateSplash(run: Run, p: number)
	if run.water then
		run.water:rippleTrain(0.35 + p * 0.65)
		run.water:suctionAndShadow(p * 0.5)
	end
	if run.shake then
		run.shake:setSustain(0.25 * p)
	end
end

Huge.handlers = CutKit.mergeHandlers(Massive.handlers, {
	splash = { update = updateSplash },
})
```

(`Huge` now also requires `CutKit`; the `bonk` handler's fly-out reads `beatT0(run, "ripple")` = 0.30 here, which is the intended shorter approach.) Keep `everyFrame`, `onSkip`, `build`, `revealBeat = "emergence"`, `skipTo = "banner"`, `bannerText = "HUGE"`. Set `Config.SIZES = { Massive = "full", Huge = "trimmed" }` — Huge is ON.

- [ ] **Step 5: Strip the comedy layer from `HypeUI` and `Config`.** Backup `HypeUI`. In `HypeUI` delete the `confetti`, `speed lines` and `meme fly-ins` sections (`HypeUI:confetti`, `HypeUI:speedLines`, `HypeUI:memeFlyIns`) and every reference to their state in `HypeUI.new`, `HypeUI:interrupt` and `HypeUI:cleanup` (`script_grep` for `confetti`, `speedLine`, `memeFly`, `memeTexts`, `confettiBurst`, `speedLineCount` — zero hits after). Update the header comment (it names the MAX BRAINROT hype beat). In `Config`: `Config.HYPE = { bannerScalePop = 1.35 }` with the comment block about `zoomPunchTimes` deleted; in `Config.ASSETS` remove `bonkClonk`, `plink`, `memeAudio` (and their VOLUMES) and add:

```lua
	finalSkip      = "kit:splashBig",      -- the last skip contact: same cue as every other throw's landing
	massiveRumble  = "rbxassetid://1837834264", -- was rumbleLoop; TODO: replace with a 2.5s low build
	massiveRoar    = "kit:catchGod",       -- TODO: replace -- creature roar, ~2-3s
	bannerHit      = "kit:catchBigHit",
```

with `VOLUMES` entries `finalSkip = 0.68, massiveRumble = 0.8, massiveRoar = 0.7, bannerHit = 0.6`. Keep `rumbleLoop`, `bassDrop`, `waterExplosion`, `roar`, `cardWhoosh`. Compile-check both; local-declaration diff on `HypeUI` vs backup: zero implicit globals. `CinematicClient`'s `SOUND_SLOTS` preload list: replace with `{ "finalSkip", "massiveRumble", "bassDrop", "waterExplosion", "massiveRoar", "bannerHit", "cardWhoosh" }`.

- [ ] **Step 6: Verify.** Play mode:

```lua
local H = require(game.ReplicatedStorage.Modules.CatchCinematic.Harness)
print(table.concat(H.checkBeats("Massive", 10.0, 11.0), " | "))   -- expected: empty
print(table.concat(H.checkBeats("Huge", 4.0, 5.0), " | "))        -- expected: empty
workspace:SetAttribute("CinematicTimescale", 4)
H.matrix("Takeover", "Massive")
H.matrix("Takeover", "Huge")
workspace:SetAttribute("CinematicTimescale", nil)
```

Expected: both `checkBeats` empty; 8 `OK` lines; Massive normal ≈ 10.6/4 + settle, Huge ≈ 4.8/4 + settle. Then, Studio foregrounded, owner watching: one real Massive throw and one real Huge throw (`ForceNextSize`), at 1x. Confirm by eye against spec §6.5/§6.4: quiet → ripples → violent → silhouette/eyes → slow rise with splash → camera pulls far back → "MASSIVE" → settle → streak. No rock ricochet, no meme text, no plink. Revert both grants by Uid.

- [ ] **Step 7: Mirror + commit.** Mirror `Cuts/Massive.lua`, `Cuts/Huge.lua`, `RockRig.lua`, `HypeUI.lua`, `Config.lua`, `Harness.lua`, `CinematicClient.client.lua`.

```bash
git add game-src/place-full/ReplicatedStorage/Modules/CatchCinematic game-src/place-full/StarterPlayer/StarterPlayerScripts/CinematicClient.client.lua
git commit -m "feat(cinematic): Massive re-paced to the blueprint (10.6s, no comedy beats); Huge trimmed cut switched on with splash + banner"
```

---

### Task 3: `Config.CUT_FOR`, Bridge on cut name, server `Cut`/`IsNew`, remote rename, `RevealRouter`, input lock

**Files:**
- Modify: `Config` (CUT_FOR replaces SIZES), `Bridge`, `CinematicClient`, `CinematicCommand`
- Modify: `ServerScriptService.Modules.ThrowHandler`
- Rename: `ReplicatedStorage.Remotes.MassiveCinematic` → `CatchCinematic`
- Create: `StarterPlayer.StarterPlayerScripts.RevealRouter` (LocalScript); Delete: `CatchRevealClient`
- Modify: `StarterPlayer.StarterPlayerScripts.ClientMain` (`startCharge` gate)

**Interfaces:**
- Consumes: `Takeover`, `Registry`, `Bridge`, `PullCeremony`/`CatchFX`/`MassiveEmergence` (still the ordinary chain until Task 4).
- Produces: `Config.CUT_FOR(rarity: string?, size: string?): string?`; `Bridge.arm(payload, seconds)` stores `armedCut = payload.Cut`; `Bridge.tryAdopt(res)` adopts iff `Config.CUT_FOR(res.Rarity, res.Size) == armedCut`; `ThrowResult.IsNew: boolean`; broadcast payload field `Cut`; player attribute `RevealActive`; `RevealRouter`'s grant record `{ Name, Rarity, RarityColor, Mutation, Size, Serial, Exists, IsNew, Anchor, Source }`.

- [ ] **Step 1: Routing test first.** Add to `Harness`:

```lua
-- Spec S4, locked. Every cell must match; mutation must never change the answer.
function Harness.routingMatrix(): { string }
	local Config = require(ReplicatedStorage.Modules.CatchCinematic.Config)
	local f: { string } = {}
	local tiers = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret", "God" }
	local sizes = { nil, "Huge", "Massive" }
	local expect = function(r: string, s: string?): string?
		if s == "Massive" and r == "God" then return "MassiveGod" end
		if s == "Massive" then return "Massive" end
		if s == "Huge" then return "Huge" end
		if r == "God" then return "God" end
		if r == "Secret" then return "Secret" end
		if r == "Mythic" then return "Mythic" end
		return nil
	end
	for _, r in ipairs(tiers) do
		for si = 1, 3 do
			local s = sizes[si]
			local got = Config.CUT_FOR(r, s)
			if got ~= expect(r, s) then
				table.insert(f, r .. "/" .. tostring(s) .. " -> " .. tostring(got) .. " expected " .. tostring(expect(r, s)))
			end
		end
	end
	if Config.CUT_FOR(nil, nil) ~= nil then table.insert(f, "nil/nil must be nil") end
	if Config.CUT_FOR("Bogus", "Massive") ~= "Massive" then table.insert(f, "unknown rarity + Massive must still be Massive") end
	return f
end
```

Run: expected FAIL (`CUT_FOR` is nil → error caught as a failure line).

- [ ] **Step 2: `Config.CUT_FOR`.** Replace the `Config.SIZES` block and `RUN_PULL_CEREMONY_AFTER` with:

```lua
-- THE ROUTING TABLE (spec S4, locked). Evaluated top to bottom on the CONFIRMED
-- grant; the first match wins; nil means "no cut -- play a pop". Mutation never
-- appears here: Golden/Diamond and the other ten are visual variants only (S3.8).
-- Server (ThrowHandler, IceFishingEvent) and client (RevealRouter, CinematicClient,
-- Bridge) all read this one function.
function Config.CUT_FOR(rarity: string?, size: string?): string?
	if size == "Massive" and rarity == "God" then return "MassiveGod" end
	if size == "Massive" then return "Massive" end
	if size == "Huge" then return "Huge" end
	if rarity == "God" then return "God" end
	if rarity == "Secret" then return "Secret" end
	if rarity == "Mythic" then return "Mythic" end
	return nil
end
```

`script_grep` the place for `Config.SIZES`, `CinematicConfig.SIZES`, `RUN_PULL_CEREMONY_AFTER`, `CinematicCeremonyAfter` — every hit is edited in the steps below; none may remain at the end of this task. Run `Harness.routingMatrix()` → expected empty.

- [ ] **Step 3: `Bridge` keys on the cut name.** Backup. `multi_edit`: replace the `armedSize` local and its three uses:
  - declaration: `local armedCut: string? = nil`
  - in `arm`: `armedCut = (type(payload) == "table" and type(payload.Cut) == "string") and payload.Cut or nil`
  - in `tryAdopt`, replace the `res.Size == nil` and `armedSize` checks with:
    ```lua
    -- The cut the RESULT routes to must be the cut that was armed. A pop-tier result
    -- (CUT_FOR == nil) is by definition an ordinary catch and is never adopted.
    local Config = require(script.Parent:WaitForChild("Config"))
    local routed = Config.CUT_FOR(res.Rarity, res.Size)
    if routed == nil or routed ~= armedCut then
    	return false
    end
    ```
    (move the `Config` require to the module top.) Update the header comment's mention of size. Compile-check.

- [ ] **Step 4: Rename the remote + `ThrowHandler` broadcast + `IsNew`.** Backup `ThrowHandler`. `multi_edit`:
  - `cinematicRemote` creation: `remotes:FindFirstChild("MassiveCinematic")` → `"CatchCinematic"` and `cinematicRemote.Name = "CatchCinematic"`. In Edit mode, rename the live instance `ReplicatedStorage.Remotes.MassiveCinematic` to `CatchCinematic` (if it exists as an authored instance).
  - the `cinMode`/`cinematic` block (mirror lines ~921–933) becomes:
    ```lua
    -- Which cut, if any, this throw will play (spec S4). nil on the overwhelmingly
    -- common throw, which is exactly the "no cutscene" case.
    local cutName = CinematicConfig.CUT_FOR(tier.Name, sizeVariant)
    local cinematic = cutName and {
    	UserId = player.UserId,
    	BrainrotName = brainrotEntry.Name,   -- may be superseded by reveal-time
    	Rarity = tier.Name,                  -- fallback swaps; client prefers
    	RarityColor = tier.Color,            -- ThrowResult's name if it differs
    	Mutation = mutation,
    	Size = sizeVariant,
    	Cut = cutName,
    	RockId = rock.Id, RockColor = rock.Color,
    	Seed = math.random(1, 2 ^ 30),
    } or nil
    ```
  - `IsNew`: immediately BEFORE `liveData.Discovered = liveData.Discovered or {}` (in `revealCatch`), insert `local wasDiscovered = liveData.Discovered ~= nil and liveData.Discovered[brainrotEntry.Name] == true`; in the `remotes.ThrowResult:FireClient(player, {` table add `IsNew = not wasDiscovered,   -- server-authoritative "NEW BRAINROT!" (spec S10)`.
  Compile-check; local-declaration diff: only `cutName` and `wasDiscovered` added, `cinMode` removed.

- [ ] **Step 5: `CinematicClient` reads `payload.Cut`; `CinematicCommand` takes cut names.** In `CinematicClient` replace Task 1's variant block with:

```lua
-- The server names the cut (payload.Cut). The client re-derives it from the same
-- Config.CUT_FOR as a guard against a mid-session Config edit or an older server,
-- and a Studio override can force any registered cut for the demo command.
local cutName: string? = Config.CUT_FOR(payload.Rarity, payload.Size)
if type(payload.Cut) == "string" and payload.Cut ~= cutName then
	cutName = nil -- server and client disagree: no cut is safer than the wrong cut
end
if RunService:IsStudio() and type(payload.__cutOverride) == "string" then
	cutName = payload.__cutOverride
end
local cut = (cutName and Registry) and Registry.get(cutName) or nil
local wants = cut ~= nil and Takeover ~= nil
```

Delete the `hugeold` block (MassiveEmergence comparator) and the `MassiveEmergence` require. `remotes:WaitForChild("MassiveCinematic")` → `"CatchCinematic"`. In `CinematicCommand`: the `/cinematic <name> massive|huge` parser becomes `/cinematic <brainrot> <Mythic|Secret|God|Huge|Massive|MassiveGod>`, sets `payload.__cutOverride = <cut>`, `payload.Cut = <cut>`, `payload.Rarity` per the Harness's rule (God/MassiveGod → "God", Secret → "Secret", Mythic → "Mythic", else "Epic"), `payload.Size` ("Massive" for Massive/MassiveGod, "Huge" for Huge, nil otherwise); remove `__variantOverride`; fire on the renamed remote. Compile-check both.

- [ ] **Step 6: Create `RevealRouter` (replaces `CatchRevealClient`).** Backup `CatchRevealClient` to `AuditBackups.PreReveal_2026_09_17.CatchRevealClient_pre3`. Create LocalScript `StarterPlayer.StarterPlayerScripts.RevealRouter`:

```lua
-- RevealRouter: turns a CONFIRMED grant (throw or ice-fishing) into exactly one
-- reveal. Spec S5.3. Deliberately thin: presentation lives in CatchPop (Task 4;
-- until then the ordinary chain below) and in the cuts; this only decides WHICH.
--
--   grant -> SkipReveal<Rarity> gamepass seam
--         -> Config.CUT_FOR(rarity, size)
--         -> cut?  Bridge.tryAdopt (the running Takeover owns it; onDone(false) falls back)
--         -> else  queue a pop
-- One reveal at a time (FIFO). Fail-soft end to end: a broken module costs a catch
-- nothing -- the grant already happened on the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local BrainrotConfig = require(Modules:WaitForChild("BrainrotConfig"))
local CatchFX = require(Modules:WaitForChild("CatchFX"))
local SoundKit = require(Modules:WaitForChild("SoundKit"))
-- Task 3 state: the ordinary chain is still PullCeremony (+ MassiveEmergence for a
-- Huge that fell back). Task 4 replaces both with CatchPop.
local PullCeremony = require(Modules:WaitForChild("PullCeremony"))
local MassiveEmergence = require(Modules:WaitForChild("MassiveEmergence"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Fail-soft cinematic stack (same shape as CinematicClient): nil means pops only.
local Config, Bridge, Takeover
do
	local ok, cfg, br, tk = pcall(function()
		local folder = Modules:WaitForChild("CatchCinematic", 5)
		return require(folder:WaitForChild("Config", 5)), require(folder:WaitForChild("Bridge", 5)), require(folder:WaitForChild("Takeover", 5))
	end)
	if ok then Config, Bridge, Takeover = cfg, br, tk
	else warn("[RevealRouter] CatchCinematic unavailable (" .. tostring(cfg) .. ") -- pops only") end
end

local weightByName, voiceByName = {}, {}
for _, e in ipairs(BrainrotConfig) do
	weightByName[e.Name] = e.Weight
	if type(e.VoiceId) == "string" and e.VoiceId ~= "" then voiceByName[e.Name] = e.VoiceId end
end

-- The catcher's own per-tier cue (Common..Mythic; Secret/God are carried by RareCatch).
local TIER_SFX = {
	Common = { "catchCommon", 0.13 }, Uncommon = { "catchUncommon", 0.17 }, Rare = { "catchRare", 0.21 },
	Epic = { "catchEpic", 0.25 }, Legendary = { "catchLegend", 0.30 }, Mythic = { "catchMythic", 0.34 },
}
local function isBroadcast(g)
	return g.Rarity == "Secret" or g.Rarity == "God" or g.Mutation == "Rainbow" or g.Mutation == "Glitched"
end
local function playTierCue(g)
	local s = TIER_SFX[g.Rarity]
	if s then SoundKit.play(s[1], nil, { volume = s[2] }) end
end

-- ============================== normalise ==============================
-- One grant record for both sources (spec S5.3).
local function fromThrow(r)
	return {
		Name = r.BrainrotName, Rarity = r.Rarity, RarityColor = r.RarityColor,
		Mutation = r.Mutation, Size = r.Size, Serial = r.Serial, Exists = r.Exists,
		IsNew = r.IsNew == true, Anchor = r.SplashPos, Source = "throw",
		CashPerSecond = r.CashPerSecond, Perfect = r.Perfect,
	}
end
local function fromFish(r)
	local c = r.Catch or {}
	return {
		Name = c.Name, Rarity = c.Rarity, RarityColor = r.RarityColor, Mutation = c.Mutation,
		Size = c.Size, Serial = r.Serial, Exists = r.Exists, IsNew = r.IsNew == true,
		Anchor = r.Anchor, Source = "fish", CashPerSecond = c.CashPerSecond,
	}
end

local function ceremonyPayload(g, tierCuePlayed)
	local weight = weightByName[g.Name]
	return {
		Name = g.Name, Rarity = g.Rarity, RarityColor = g.RarityColor, Mutation = g.Mutation,
		Size = g.Size, SplashPos = g.Anchor, Serial = g.Serial, Exists = g.Exists, IsNew = g.IsNew,
		OddsN = weight and math.max(2, math.floor(100000 / weight + 0.5)) or nil,
		TierCuePlayed = tierCuePlayed == true, VoiceId = voiceByName[g.Name],
	}
end

-- ============================== queue ==============================
local queue = {}
local draining = false

local function playPop(g)
	-- Task 3: the ordinary chain, exactly as CatchRevealClient ran it.
	pcall(CatchFX.play, { Rarity = g.Rarity, Color = g.RarityColor, Mutation = g.Mutation })
	local tierCuePlayed = false
	if not isBroadcast(g) then
		pcall(playTierCue, g)
		tierCuePlayed = TIER_SFX[g.Rarity] ~= nil
	end
	if player:GetAttribute("SkipReveal" .. tostring(g.Rarity)) == true then return end
	local p = ceremonyPayload(g, tierCuePlayed)
	pcall(MassiveEmergence.play, p)
	pcall(PullCeremony.play, p) -- BLOCKS for the ceremony's length
end

local function drainQueue()
	if draining then return end
	draining = true
	task.spawn(function()
		while #queue > 0 do
			-- never over a takeover (spec S11): wait for it, bounded by its own watchdog
			while Takeover and Takeover.isActive() do task.wait(0.1) end
			local g = table.remove(queue, 1)
			local ok, err = pcall(playPop, g)
			if not ok then warn("[RevealRouter] pop failed: " .. tostring(err)) end
		end
		draining = false
	end)
end

local function enqueuePop(g)
	table.insert(queue, g)
	drainQueue()
end

-- ============================== route ==============================
local function route(raw, g)
	if type(g.Name) ~= "string" then return end
	local cutName = Config and Config.CUT_FOR(g.Rarity, g.Size) or nil
	if cutName and Bridge then
		-- The running Takeover owns this reveal. Adopt hands it the authoritative
		-- result (reveal-time fallback swaps); onDone(false) means the cinematic died,
		-- so the grant gets a pop after all. pcall'd end to end.
		local okAdopt, adopted = pcall(Bridge.tryAdopt, raw)
		if not okAdopt then warn("[RevealRouter] adopt errored: " .. tostring(adopted)) end
		if okAdopt and adopted == true then
			local okHook = pcall(Bridge.onDone, function(ok)
				if not ok then enqueuePop(g) end
			end)
			if okHook then return end
		end
	end
	enqueuePop(g)
end

remotes:WaitForChild("ThrowResult").OnClientEvent:Connect(function(result)
	if type(result) ~= "table" or type(result.BrainrotName) ~= "string" then return end
	route(result, fromThrow(result))
end)

-- Ice fishing (Task 9 wires the server side; the remote name is confirmed there).
local fishResult = remotes:FindFirstChild("IceFishingResult")
if fishResult then
	fishResult.OnClientEvent:Connect(function(result)
		if type(result) ~= "table" or type(result.Catch) ~= "table" then return end
		local raw = { BrainrotName = result.Catch.Name, Rarity = result.Catch.Rarity, Size = result.Catch.Size, Mutation = result.Catch.Mutation }
		route(raw, fromFish(result))
	end)
end
```

Then destroy the live `CatchRevealClient` (its remaining logic — `TIER_SFX`, `isBroadcast`, `buildPayload`, the ordinary chain — is now here). `script_grep` for `CatchRevealClient` — expected: comments only (edit them to `RevealRouter`).

- [ ] **Step 7: Input lock in `ClientMain`.** Backup. In `startCharge`, after `if cooldown or charging then return end` insert:

```lua
	-- A takeover cut is playing (Takeover sets RevealActive for the catcher; spec S11):
	-- no throws until the camera is back. Client-side on purpose -- it only guards
	-- the local camera round-trip.
	if player:GetAttribute("RevealActive") == true then return end
```

Compile-check; top-level local count unchanged (the 200-local ceiling).

- [ ] **Step 8: Verify.** Play mode: `Harness.routingMatrix()` empty. Then, real throws with Studio foregrounded:
  1. `ForceNextSize = "Massive"`: cut plays; during the cut press the throw key — nothing happens (lock); after restore, throws work again.
  2. `ForceNextCatch = <a Mythic name>` (existing hook): with `Cuts.Mythic` not yet existing, `Registry.get("Mythic")` is nil → `wants = false` → stock landing + the ordinary chain runs (pop path). No error in the console.
  3. Ordinary throw: `ThrowResult.IsNew` — check with a `print` in a temporary client `execute_luau` listener that a first-time name gives `true`, a repeat gives `false`. Revert grants by Uid.

- [ ] **Step 9: Mirror + commit.** Mirror `Config.lua`, `Bridge.lua`, `Harness.lua`, `CinematicClient.client.lua`, `CinematicCommand.server.lua`, `ThrowHandler.lua`, `ClientMain.client.lua`, new `RevealRouter.client.lua`; delete `CatchRevealClient.client.lua` from the mirror.

```bash
git add game-src/place-full
git commit -m "feat(reveal): Config.CUT_FOR routing, Bridge keyed on cut, ThrowHandler Cut+IsNew, CatchCinematic remote, RevealRouter with FIFO + RevealActive lock"
```

---

### Task 4: `CatchPop` (Common–Legendary) + retire PullCeremony / MassiveEmergence / CatchReveal

**Files:**
- Create: `ReplicatedStorage.Modules.CatchPop`
- Modify: `RevealRouter` (`playPop` → `CatchPop.play`)
- Delete: `ReplicatedStorage.Modules.PullCeremony`, `MassiveEmergence`, `CatchReveal`
- Modify: `Config.ASSETS` (no change), `SoundKit` (no change)

**Interfaces:**
- Consumes: `BrainrotThumb.master(name)`, `BrainrotThumb.framing(model, fov)`, `BrainrotThumb.DEFAULT_DIR`, `Mutations.Color(name)`, `Sizes.Label(mutation, size, name)`, `UITheme.Font`/`GlyphFont`, `SoundKit.play`.
- Produces: `CatchPop.play(grant): boolean` — BLOCKS for the pop's length; `CatchPop.isPlaying(): boolean`. Grant = the router's record plus `OddsN`, `TierCuePlayed`.

- [ ] **Step 1: Test first.** Add to `Harness`:

```lua
-- Pops never touch the camera or Lighting and leave nothing behind.
function Harness.popMatrix(): { string }
	local CatchPop = require(ReplicatedStorage.Modules.CatchPop)
	local f: { string } = {}
	local tiers = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
	local colours = { Color3.fromRGB(190,190,190), Color3.fromRGB(80,220,90), Color3.fromRGB(60,140,255), Color3.fromRGB(180,60,255), Color3.fromRGB(255,170,30) }
	local before = snapshot()
	local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local guiBefore = pg and #pg:GetDescendants() or 0
	local t0 = os.clock()
	for i, tier in ipairs(tiers) do
		for _, mut in ipairs({ false, "Golden", "Diamond" }) do
			local ok, err = pcall(CatchPop.play, {
				Name = "Kraken Congelato", Rarity = tier, RarityColor = colours[i],
				Mutation = mut or nil, IsNew = (i % 2 == 0), Serial = 47, Exists = 12, OddsN = 1200,
			})
			if not ok then table.insert(f, tier .. "/" .. tostring(mut) .. " errored: " .. tostring(err)) end
		end
	end
	local elapsed = os.clock() - t0
	if elapsed > 15 * 1.6 then table.insert(f, "15 pops took " .. elapsed .. "s (> 1.6s each)") end
	task.wait(0.5)
	diff(before, snapshot(), f)
	local guiAfter = pg and #pg:GetDescendants() or 0
	if guiAfter > guiBefore + 2 then table.insert(f, "PlayerGui grew by " .. (guiAfter - guiBefore)) end
	return f
end
```

Run: expected FAIL (`CatchPop` missing).

- [ ] **Step 2: Create `CatchPop`.**

```lua
--!strict
-- CatchPop: the Common..Legendary reward reveal (spec S7). ONE beat structure --
-- appear -> bounce+burst -> text -> float -> close -- parameterised by a preset per
-- tier. Screen-space only: this module NEVER writes the camera, Lighting or another
-- gui's Enabled, so it has nothing to restore and cannot strand the camera.
-- Built from CatchReveal's viewport machinery and PullCeremony's stamp recipe.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local BrainrotThumb = require(Modules:WaitForChild("BrainrotThumb"))
local Mutations = require(Modules:WaitForChild("MutationConfig"))
local Sizes = require(Modules:WaitForChild("SizeConfig"))
local UITheme = require(Modules:WaitForChild("UITheme"))
local SoundKit = require(Modules:WaitForChild("SoundKit"))

local player = Players.LocalPlayer

export type Grant = {
	Name: string, Rarity: string?, RarityColor: Color3?, Mutation: string?, Size: string?,
	Serial: number?, Exists: number?, IsNew: boolean?, OddsN: number?, TierCuePlayed: boolean?,
}

type Preset = {
	length: number, size: number, scaleFrom: number, overshoot: number, bounce: number,
	burst: number, burstSpread: number, glow: number, shockwave: boolean, rotation: number,
	uiBump: number, dim: number, orbit: number, textAt: number, textSlam: boolean, floatAmp: number,
	glowPulse: boolean,
}

-- ===== PRESETS (spec S7 table). Times in seconds, sizes in px. =====
local PRESETS: { [string]: Preset } = {
	Common    = { length = 0.90, size = 110, scaleFrom = 0.70, overshoot = 1.04, bounce = 0.06, burst = 6,  burstSpread = 40, glow = 0.20, shockwave = false, rotation = 0,  uiBump = 0,    dim = 0,    orbit = 0,  textAt = 0.30, textSlam = false, floatAmp = 2, glowPulse = false },
	Uncommon  = { length = 1.00, size = 116, scaleFrom = 0.65, overshoot = 1.08, bounce = 0.10, burst = 10, burstSpread = 50, glow = 0.35, shockwave = false, rotation = 0,  uiBump = 0,    dim = 0,    orbit = 0,  textAt = 0.30, textSlam = false, floatAmp = 2, glowPulse = false },
	Rare      = { length = 1.10, size = 124, scaleFrom = 0.55, overshoot = 1.14, bounce = 0.12, burst = 14, burstSpread = 60, glow = 0.50, shockwave = true,  rotation = 0,  uiBump = 0,    dim = 0,    orbit = 0,  textAt = 0.30, textSlam = false, floatAmp = 3, glowPulse = false },
	Epic      = { length = 1.35, size = 136, scaleFrom = 0.45, overshoot = 1.20, bounce = 0.14, burst = 20, burstSpread = 75, glow = 0.65, shockwave = true,  rotation = 8,  uiBump = 0.03, dim = 0,    orbit = 0,  textAt = 0.32, textSlam = true,  floatAmp = 3, glowPulse = false },
	Legendary = { length = 1.30, size = 144, scaleFrom = 0.40, overshoot = 1.18, bounce = 0.12, burst = 24, burstSpread = 85, glow = 0.80, shockwave = true,  rotation = 0,  uiBump = 0.03, dim = 0.12, orbit = 10, textAt = 0.40, textSlam = true,  floatAmp = 3, glowPulse = true },
}
local SPIN = 70          -- deg/s, same as the old CatchReveal
local FOV = 30
local TOP_Y = 78         -- just under the top bar, same anchor CatchReveal used
local FADE_OUT = 0.16
local CATCH_SOUND = { Common = "catchCommon", Uncommon = "catchUncommon", Rare = "catchRare", Epic = "catchEpic", Legendary = "catchLegend" }
local CATCH_VOLUME = { Common = 0.13, Uncommon = 0.17, Rare = 0.21, Epic = 0.25, Legendary = 0.30 }

local M = {}
local gui: ScreenGui? = nil
local live: { [string]: any }? = nil
local token = 0

local function ensureGui(): ScreenGui
	if gui and gui.Parent then
		return gui
	end
	local g = Instance.new("ScreenGui")
	g.Name = "CatchPopUI"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 12
	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
	return g
end

local function label(parent: Instance, text: string, size: number, color: Color3, strokeT: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = UITheme.Font
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.TextStrokeTransparency = 0
	l.TextStrokeColor3 = Color3.new(0, 0, 0)
	l.Size = UDim2.fromOffset(10, size + 6)
	l.AutomaticSize = Enum.AutomaticSize.X
	l.ZIndex = 5
	local s = Instance.new("UIStroke")
	s.Thickness = strokeT
	s.Color = Color3.new(0, 0, 0)
	s.Parent = l
	l.Parent = parent
	return l
end

local function teardown(rec: { [string]: any })
	if rec.dead then
		return
	end
	rec.dead = true
	if rec.conn then
		rec.conn:Disconnect()
		rec.conn = nil
	end
	if rec.root then
		rec.root:Destroy()
		rec.root = nil
	end
	if live == rec then
		live = nil
	end
end

function M.isPlaying(): boolean
	return live ~= nil and not live.dead
end

-- Builds the spinning model. Returns the per-frame updater or nil (no model).
-- MUTATION (spec S9): a viewport cannot render MutationFX's light/emitter/Highlight,
-- so the tint rides the viewport's own lighting -- one property write.
local function buildViewport(rec: { [string]: any }, preset: Preset, grant: Grant, parent: Instance, tint: Color3?): ((number) -> ())?
	local master = BrainrotThumb.master(grant.Name)
	if not master then
		return nil
	end
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Model"
	vp.AnchorPoint = Vector2.new(0.5, 0.5)
	vp.Position = UDim2.fromScale(0.5, 0.5)
	vp.Size = UDim2.fromScale(1, 1)
	vp.BackgroundTransparency = 1
	vp.ZIndex = 3
	if tint then
		vp.LightColor = tint
		vp.Ambient = tint:Lerp(Color3.new(0.3, 0.3, 0.3), 0.5)
	end
	vp.Parent = parent
	local m = master:Clone()
	m.Parent = vp
	local centre, dist = BrainrotThumb.framing(m, FOV)
	local cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	cam.Parent = vp
	vp.CurrentCamera = cam
	rec.viewport = vp
	local base = BrainrotThumb.DEFAULT_DIR
	return function(t: number)
		local dir = CFrame.Angles(0, math.rad(SPIN) * t, 0) * base
		cam.CFrame = CFrame.lookAt(centre + dir * dist, centre)
	end
end

local function burst(parent: Frame, count: number, spread: number, colour: Color3, rng: Random)
	for i = 1, count do
		local sh = Instance.new("Frame")
		sh.AnchorPoint = Vector2.new(0.5, 0.5)
		sh.Position = UDim2.fromScale(0.5, 0.5)
		sh.Size = UDim2.fromOffset(6, 18)
		sh.BackgroundColor3 = colour
		sh.BorderSizePixel = 0
		sh.Rotation = i * (360 / count) + rng:NextNumber(-8, 8)
		sh.ZIndex = 2
		sh.Parent = parent
		local ang = math.rad(sh.Rotation - 90)
		local d = spread * rng:NextNumber(0.7, 1.2)
		TweenService:Create(sh, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, math.cos(ang) * d, 0.5, math.sin(ang) * d),
			Size = UDim2.fromOffset(3, 8),
		}):Play()
		task.delay(0.42, function() sh:Destroy() end)
	end
end

local function shockwave(parent: Frame, colour: Color3, size: number)
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(size * 0.5, size * 0.5)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 2
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = ring
	local s = Instance.new("UIStroke")
	s.Color = colour
	s.Thickness = 4
	s.Parent = ring
	ring.Parent = parent
	TweenService:Create(ring, TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(size * 1.9, size * 1.9),
	}):Play()
	-- UIStroke.Transparency is not on the Tween allow-list: hand-lerp it in the updater
	return s
end

-- grant -> blocks for preset.length (+ fade). Returns false when nothing was shown.
function M.play(grant: Grant): boolean
	if type(grant) ~= "table" or type(grant.Name) ~= "string" then
		return false
	end
	local preset = PRESETS[grant.Rarity or ""] or PRESETS.Common
	if live then
		teardown(live)
	end
	token += 1
	local rec: { [string]: any } = { dead = false, token = token }
	live = rec
	local accent = typeof(grant.RarityColor) == "Color3" and grant.RarityColor or Color3.fromRGB(190, 190, 190)
	local mut = (type(grant.Mutation) == "string" and grant.Mutation ~= "" and grant.Mutation ~= "None") and grant.Mutation or nil
	local tint: Color3? = nil
	if mut then
		local ok, mc = pcall(Mutations.Color, mut)
		if ok and typeof(mc) == "Color3" then
			tint = mc
		end
	end
	local haloColour = tint or accent
	local rng = Random.new(token)

	local okBuild, err = pcall(function()
		local root = Instance.new("Frame")
		root.Name = "Pop"
		root.Size = UDim2.fromScale(1, 1)
		root.BackgroundTransparency = 1
		root.Parent = ensureGui()
		rec.root = root

		if preset.dim > 0 then
			local dim = Instance.new("Frame")
			dim.Name = "Dim"
			dim.Size = UDim2.fromScale(1, 1)
			dim.BackgroundColor3 = Color3.new(0, 0, 0)
			dim.BackgroundTransparency = 1 - preset.dim
			dim.BorderSizePixel = 0
			dim.ZIndex = 1
			dim.Parent = root
			rec.dim = dim
		end

		local holder = Instance.new("Frame")
		holder.Name = "Holder"
		holder.AnchorPoint = Vector2.new(0.5, 0)
		holder.Position = UDim2.new(0.5, 0, 0, TOP_Y)
		holder.Size = UDim2.fromOffset(preset.size, preset.size)
		holder.BackgroundTransparency = 1
		holder.ZIndex = 2
		holder.Parent = root
		rec.holder = holder
		local scale = Instance.new("UIScale")
		scale.Scale = preset.scaleFrom
		scale.Parent = holder
		rec.scale = scale

		local halo = Instance.new("Frame")
		halo.Name = "Halo"
		halo.AnchorPoint = Vector2.new(0.5, 0.5)
		halo.Position = UDim2.fromScale(0.5, 0.5)
		halo.Size = UDim2.fromScale(0.86, 0.86)
		halo.BackgroundColor3 = haloColour
		halo.BackgroundTransparency = 1
		halo.ZIndex = 2
		halo.Parent = holder
		local hc = Instance.new("UICorner")
		hc.CornerRadius = UDim.new(1, 0)
		hc.Parent = halo
		rec.halo = halo

		rec.spin = buildViewport(rec, preset, grant, holder, tint)

		local stamp = Instance.new("Frame")
		stamp.Name = "Stamp"
		stamp.AnchorPoint = Vector2.new(0.5, 0)
		stamp.Position = UDim2.new(0.5, 0, 0, TOP_Y + preset.size + 8)
		stamp.Size = UDim2.fromOffset(10, 10)
		stamp.AutomaticSize = Enum.AutomaticSize.XY
		stamp.BackgroundTransparency = 1
		stamp.ZIndex = 5
		stamp.Parent = root
		local list = Instance.new("UIListLayout")
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Padding = UDim.new(0, 2)
		list.Parent = stamp
		local header = label(stamp, grant.IsNew and "NEW BRAINROT!" or "YOU GOT!", 20, Color3.fromRGB(255, 240, 200), 2.5)
		header.LayoutOrder = 1
		local nameL = label(stamp, string.upper(Sizes.Label(mut, grant.Size, grant.Name)), 34, Color3.new(1, 1, 1), 4)
		nameL.LayoutOrder = 2
		local tierL = label(stamp, string.upper(grant.Rarity or ""), 22, accent, 3)
		tierL.LayoutOrder = 3
		if grant.Serial then
			local ex = grant.Exists and (" · ONLY " .. tostring(grant.Exists) .. " EXIST") or ""
			label(stamp, "#" .. tostring(grant.Serial) .. ex, 18, Color3.fromRGB(255, 216, 77), 2.5).LayoutOrder = 4
		end
		if grant.OddsN then
			label(stamp, "1 in " .. tostring(grant.OddsN) .. " of its tier", 15, Color3.fromRGB(200, 208, 200), 2).LayoutOrder = 5
		end
		local sScale = Instance.new("UIScale")
		sScale.Scale = 0
		sScale.Parent = stamp
		rec.stampScale = sScale
		rec.stamp = stamp
	end)
	if not okBuild then
		warn("[CatchPop] build failed: " .. tostring(err))
		teardown(rec)
		return false
	end

	if not grant.TierCuePlayed and CATCH_SOUND[grant.Rarity or ""] then
		pcall(SoundKit.play, CATCH_SOUND[grant.Rarity], nil, { volume = CATCH_VOLUME[grant.Rarity] })
	end

	-- ===== the timeline: appear -> bounce+burst -> text -> float -> close =====
	local L = preset.length
	local burstAt = 0.15
	local t = 0
	local burstDone, textDone = false, false
	local strokeRef: UIStroke? = nil
	rec.conn = RunService.RenderStepped:Connect(function(dt)
		if rec.dead then
			return
		end
		t += dt
		local scale = rec.scale :: UIScale
		-- appear: scaleFrom -> overshoot by burstAt, then settle to 1 with a bounce
		if t < burstAt then
			local p = t / burstAt
			scale.Scale = preset.scaleFrom + (preset.overshoot - preset.scaleFrom) * (1 - (1 - p) * (1 - p))
		else
			local q = math.clamp((t - burstAt) / 0.25, 0, 1)
			local bounce = math.sin(q * math.pi) * preset.bounce
			scale.Scale = preset.overshoot + (1 - preset.overshoot) * q - bounce
		end
		if preset.rotation ~= 0 then
			(rec.holder :: Frame).Rotation = math.sin(t * 6) * preset.rotation * math.max(0, 1 - t / L)
		end
		-- glow
		local halo = rec.halo :: Frame
		local glow = preset.glow * math.clamp(t / 0.3, 0, 1)
		if preset.glowPulse then
			glow = glow * (0.85 + 0.15 * math.sin(t * 9))
		end
		halo.BackgroundTransparency = 1 - glow
		-- burst + shockwave + UI bump, once
		if not burstDone and t >= burstAt then
			burstDone = true
			burst(rec.holder, preset.burst, preset.burstSpread, haloColour, rng)
			if preset.shockwave then
				strokeRef = shockwave(rec.holder, haloColour, preset.size)
			end
			if preset.uiBump > 0 then
				rec.bumpUntil = t + 0.12
			end
		end
		if strokeRef then
			strokeRef.Transparency = math.clamp((t - burstAt) / 0.38, 0, 1)
		end
		if rec.bumpUntil then
			local b = math.clamp((rec.bumpUntil - t) / 0.12, 0, 1)
			scale.Scale = scale.Scale * (1 + preset.uiBump * b)
		end
		-- text
		if not textDone and t >= preset.textAt then
			textDone = true
		end
		if textDone then
			local q = math.clamp((t - preset.textAt) / (preset.textSlam and 0.10 or 0.22), 0, 1)
			local s = preset.textSlam and (1.25 - 0.25 * q) or q
			(rec.stampScale :: UIScale).Scale = s
		end
		-- float
		if t > 0.3 then
			(rec.holder :: Frame).Position = UDim2.new(0.5, 0, 0, TOP_Y + math.sin(t * 3) * preset.floatAmp)
		end
		-- orbiting particles (Legendary)
		if preset.orbit > 0 and not rec.orbiters then
			rec.orbiters = {}
			for i = 1, preset.orbit do
				local d = Instance.new("Frame")
				d.AnchorPoint = Vector2.new(0.5, 0.5)
				d.Size = UDim2.fromOffset(6, 6)
				d.BackgroundColor3 = haloColour
				d.BorderSizePixel = 0
				d.ZIndex = 4
				local c = Instance.new("UICorner")
				c.CornerRadius = UDim.new(1, 0)
				c.Parent = d
				d.Parent = rec.holder
				table.insert(rec.orbiters, { d, i * (2 * math.pi / preset.orbit) })
			end
		end
		if rec.orbiters then
			for _, o in ipairs(rec.orbiters) do
				local a = o[2] + t * 2.2
				o[1].Position = UDim2.new(0.5 + math.cos(a) * 0.55, 0, 0.5 + math.sin(a) * 0.55, 0)
			end
		end
		if rec.spin then
			rec.spin(t)
		end
		-- close: fade the viewport and stamp out over FADE_OUT
		if t >= L then
			local f = math.clamp((t - L) / FADE_OUT, 0, 1)
			if rec.viewport then
				(rec.viewport :: ViewportFrame).ImageTransparency = f
			end
			(rec.stampScale :: UIScale).Scale = 1 - f
			halo.BackgroundTransparency = 1 - glow * (1 - f)
			if rec.dim then
				(rec.dim :: Frame).BackgroundTransparency = 1 - preset.dim * (1 - f)
			end
			if f >= 1 then
				teardown(rec)
			end
		end
	end)

	while not rec.dead and rec.token == token do
		task.wait(0.05)
	end
	return true
end

return M
```

- [ ] **Step 3: Route pops through `CatchPop`; retire the old chain.** In `RevealRouter`: replace the `PullCeremony`/`MassiveEmergence` requires with `local CatchPop = require(Modules:WaitForChild("CatchPop"))`; `playPop` becomes:

```lua
local function playPop(g)
	pcall(CatchFX.play, { Rarity = g.Rarity, Color = g.RarityColor, Mutation = g.Mutation })
	local tierCuePlayed = false
	if not isBroadcast(g) then
		pcall(playTierCue, g)
		tierCuePlayed = TIER_SFX[g.Rarity] ~= nil
	end
	if player:GetAttribute("SkipReveal" .. tostring(g.Rarity)) == true then return end
	local p = ceremonyPayload(g, tierCuePlayed)
	pcall(CatchPop.play, p) -- BLOCKS for the pop's length
end
```

Then `script_grep` the place for `PullCeremony`, `MassiveEmergence`, `CatchReveal` (the module, not `CatchRevealUI`). Expected hits after the router edit: `SettingsPanel` (if it has a "ceremony after" row from the Massive build — delete that row and its `SettingsService` whitelist entry), `CinematicCommand` (`/cinceremony` — delete the command), comments. Back up all three modules to `AuditBackups.PreReveal_2026_09_17.<Name>_final`, then destroy `PullCeremony`, `MassiveEmergence`, `CatchReveal`. Compile-check every edited script; `script_grep` again — zero hits.

- [ ] **Step 4: Verify.** Play mode: `Harness.popMatrix()` → expected empty (15 pops, no camera/Lighting diff, PlayerGui not growing). Then with the owner watching at 1x: `ForceNextCatch` for one name per tier Common→Legendary, plain; then one Golden Common and one Diamond Epic — the pop must visibly read gold-lit / ice-lit with the halo in the mutation colour and the name "GOLDEN …"/"DIAMOND …". If the tint does not read on a dark model, apply spec §9's fallback: in `buildViewport`, after cloning, `for _, p in ipairs(m:GetDescendants()) do if p:IsA("BasePart") then p.Color = p.Color:Lerp(tint, 0.35) end end` (viewport clone only). Revert grants by Uid.

- [ ] **Step 5: Mirror + commit.** Mirror `CatchPop.lua`, `RevealRouter.client.lua`, `Harness.lua`, `SettingsPanel.lua`, `SettingsService.lua`, `CinematicCommand.server.lua` as touched; delete `PullCeremony.lua`, `MassiveEmergence.lua`, `CatchReveal.lua` and the stale `game-src/CatchReveal.lua`, `game-src/CatchRevealClient.lua` top-level mirrors.

```bash
git add -A game-src
git commit -m "feat(reveal): CatchPop pop layer for Common-Legendary; retire PullCeremony, MassiveEmergence, CatchReveal"
```

---

### Task 5: `Cuts/Shared` (handoff + build shared by every cut), `WaterFX:shockRing`, `Cuts/Mythic`

**Files:**
- Create: `…CatchCinematic.Cuts.Shared`
- Modify: `…Cuts.Massive` (imports Shared instead of owning handoff/build/calmAngry/faceCamera), `…Cuts.Huge` (no change needed — it reads `Massive.handlers`)
- Modify: `…CatchCinematic.WaterFX` (add `shockRing`, colour param on `godrays`)
- Create: `…CatchCinematic.Cuts.Mythic`
- Modify: `Config.ASSETS`, `CinematicClient` `SOUND_SLOTS`

**Interfaces:**
- Consumes: Task 2's `Massive.handlers`, `CutKit`, `Takeover`.
- Produces: `Shared.handoff: BeatHandlers`, `Shared.build(run, defaultSize: string?): boolean` (brain + optional rock + water), `Shared.calmAngry(run)`, `Shared.faceCamera(run)`, `Shared.rimHighlight(run, color: Color3)`; `WaterFX:shockRing(color: Color3, maxRadius: number, life: number)`, `WaterFX:godrays(pos, height, color: Color3?)`; `Cuts.Mythic`.

- [ ] **Step 1: Beat test first.** Play mode: `Harness.checkBeats("Mythic", 1.6, 1.8)` → expected FAIL (`no cut`).

- [ ] **Step 2: Extract `Cuts/Shared` from `Cuts/Massive`.** Create `Cuts.Shared`:

```lua
--!strict
-- CatchCinematic.Cuts.Shared -- handlers and construction every cut needs and no
-- cut owns: the handoff beat (streak into the bag + camera return), the standard
-- build (brain + optional rock + water), and the angry/calm rim helpers. Not a cut.
local Workspace = game:GetService("Workspace")
local folder = script.Parent.Parent
local Config = require(folder:WaitForChild("Config"))
local CutKit = require(folder:WaitForChild("CutKit"))
local Types = require(folder:WaitForChild("Types"))
local WaterFX = require(folder:WaitForChild("WaterFX"))
local RockRig = require(folder:WaitForChild("RockRig"))
local BrainrotRig = require(folder:WaitForChild("BrainrotRig"))
type Run = Types.Run

local Shared = {}

function Shared.calmAngry(run: Run)
	if run.brain then
		run.brain:calmEyes()
	end
	if run.model then
		local rim = run.model:FindFirstChild("CinematicAura")
		if rim and rim:IsA("Highlight") then
			rim.OutlineColor = run.rarityColor
		end
	end
end

-- A rarity/mutation-coloured outline on the creature for the rest of the cut.
-- Parented to the model inside the stage, so every teardown path destroys it.
function Shared.rimHighlight(run: Run, color: Color3)
	if not run.model then
		return
	end
	pcall(function()
		local old = run.model:FindFirstChild("CinematicAura")
		if old then
			old:Destroy()
		end
		local rim = Instance.new("Highlight")
		rim.Name = "CinematicAura"
		rim.FillTransparency = 1
		rim.OutlineColor = color
		rim.OutlineTransparency = 0.25
		rim.DepthMode = Enum.HighlightDepthMode.Occluded
		rim.Parent = run.model
	end)
end

function Shared.faceCamera(run: Run)
	if not run.brain then
		return
	end
	if run.heroEye == nil then
		local eye, focus = CutKit.heroFraming(run)
		run.heroEye, run.heroFocus = eye, focus
	end
	local aim = (run.heroEye or (run.surface + run.horiz * -40)) - run.surface
	run.brain:setFacing(math.atan2(aim.X, aim.Z) - math.pi * 0.6)
end

local function enterHandoff(run: Run)
	Shared.calmAngry(run)
	if run.shake then
		run.shake:setSustain(0)
	end
	if run.hype then
		run.hype:hideSkipPrompt()
	end
	if run.post then
		run.post:easeBack(run.postCfg.easeBackSeconds or 1.2)
	end
	if run.audio then
		run.audio:play("cardWhoosh", run.spectator and { where = run.surface } or nil)
		run.audio:restoreAmbient(0.6 * run.stretch)
	end
	local seconds = CutKit.beatSeconds(run) * 0.42
	if run.spectator then
		return
	end
	if run.brain then
		local target = Vector2.new(0.86, 0.92)
		if run.hype then
			local px = run.hype:bagTarget()
			local cam = Workspace.CurrentCamera
			local vs = cam and cam.ViewportSize or Vector2.new(1280, 720)
			if vs.X > 0 and vs.Y > 0 then
				target = Vector2.new(math.clamp(px.X / vs.X, 0, 1), math.clamp(px.Y / vs.Y, 0, 1))
			end
		end
		run.brain:compressAndStreak(target, seconds, function()
			if run.hype then
				run.hype:cardArrive(run.rarityColor)
			end
		end)
	end
	if run.cam then
		run.cam:returnToPlayer((Config.CAMERA.returnBlendSeconds or 0.8) * run.stretch, nil)
	end
end

local function updateHandoff(run: Run, p: number)
	if run.spectator and run.brain then
		run.brain:setRise(1 - p)
	end
end

Shared.handoff = { enter = enterHandoff, update = updateHandoff }

-- brain (declines when no model) + rock (only when the payload has one -- fishing
-- has none) + water. Cut-specific rigs are built by the cut after this returns.
function Shared.build(run: Run, defaultSize: string?): boolean
	local stage = run.stage :: Folder
	local brain = BrainrotRig.new(stage, run.name, run.size or defaultSize or "Normal", run.surface)
	if not brain then
		warn("[Cuts.Shared] declining: no model for '" .. tostring(run.name) .. "'")
		return false
	end
	run.brain = brain
	CutKit.track(run, function()
		brain:cleanup()
	end)
	CutKit.refreshGeometry(run)
	if run.payload.RockId ~= nil then
		local rock = RockRig.new(Config.ROCK, stage, run.payload.RockId, run.payload.RockColor, run.surface, run.rng)
		run.rock = rock
		CutKit.track(run, function()
			rock:cleanup()
		end)
	end
	local water = WaterFX.new(run.waterCfg, Config.PARTICLES, stage, run.surface, run.quality, run.rng)
	run.water = water
	CutKit.track(run, function()
		water:cleanup()
	end)
	return true
end

function Shared.everyFrameRock(run: Run)
	if run.rock then
		run.rock:update(run.t)
	end
end

return Shared
```

Then in `Cuts.Massive`: delete its local `calmAngry`, `faceCamera`, `enterHandoff`, `updateHandoff`, `Massive.build` and `Massive.everyFrame` bodies; add `local Shared = require(script.Parent:WaitForChild("Shared"))`; replace uses with `Shared.calmAngry`, `Shared.faceCamera`; the rim creation in `enterEmergence` becomes `Shared.rimHighlight(run, run.eyesApplied and run.rarityColor or Color3.fromRGB(255, 45, 25))`; `handoff = Shared.handoff` in the handler table; `Massive.build = function(run) return Shared.build(run, "Massive") end`; `Massive.everyFrame = Shared.everyFrameRock`; drop the `Massive.calmAngry/faceCamera` exports. `BrainrotRig`'s `size` argument must accept `"Normal"`: check `SizeConfig.Scale("Normal")`/`Sizes.ByName["Normal"]` in Studio — if the config has no such name, use `nil` and confirm `BrainrotRig.buildModel` treats a nil/unknown size as scale 1 (read its `Sizes.Scale` call; if it errors on nil, guard it there with `Sizes.Scale(size or "")` returning 1 for unknown). Compile-check; `Harness.matrix("Takeover", "Massive")` and `("Takeover", "Huge")` still 8 `OK`.

- [ ] **Step 3: `WaterFX:shockRing` + coloured godrays.** `multi_edit` `WaterFX`: change `function WaterFX:godrays(pos: Vector3, height: number)` to `function WaterFX:godrays(pos: Vector3, height: number, color: Color3?)` and `w.Color = GODRAY_COLOR` to `w.Color = color or GODRAY_COLOR`. Add after `bonkRing`:

```lua
-- A single expanding neon ring in an arbitrary colour -- the tier-coloured energy
-- ring of the Mythic eruption, the gold shockwave of God's arrival. Same recipe as
-- _ring (which stays the water-coloured one).
function WaterFX:shockRing(color: Color3, maxRadius: number, life: number)
	if self._destroyed then
		return
	end
	local ring = Instance.new("Part")
	ring.Name = "ShockRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.14, 1.5, 1.5)
	ring.CFrame = CFrame.new(self._surfacePos + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))
	decorPart(ring)
	ring.Parent = self._stage
	table.insert(self._parts, ring)
	local tw = TweenService:Create(ring, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.14, maxRadius * 2, maxRadius * 2), Transparency = 1,
	})
	table.insert(self._tweens, tw)
	tw:Play()
end
```

Compile-check.

- [ ] **Step 4: `Cuts/Mythic`** (spec §6.1):

```lua
--!strict
-- CatchCinematic.Cuts.Mythic -- POWER. 1.7s, not skippable. The water erupts and
-- the creature explodes out of the splash in a red energy burst.
local folder = script.Parent.Parent
local Config = require(folder:WaitForChild("Config"))
local CutKit = require(folder:WaitForChild("CutKit"))
local Types = require(folder:WaitForChild("Types"))
local Shared = require(script.Parent:WaitForChild("Shared"))
type Run = Types.Run

local Mythic = {}

-- ===== TUNABLES (spec S6.1) =====
Mythic.BEATS = {
	{ name = "bonk",     t0 = 0.00, t1 = 0.15 },  -- UI hidden; local "slow" = FOV tighten + duck
	{ name = "ripple",   t0 = 0.15, t1 = 0.25 },  -- deep bass, ripple expands
	{ name = "eruption", t0 = 0.25, t1 = 0.50 },  -- REVEAL: erupt, breach, red ring, flash, shake
	{ name = "settle",   t0 = 0.50, t1 = 0.60 },
	{ name = "banner",   t0 = 0.60, t1 = 1.50 },  -- MYTHIC; red rim + particles; float
	{ name = "handoff",  t0 = 1.50, t1 = 1.70 },
}
Mythic.RED = Color3.fromRGB(255, 50, 50)
Mythic.TIGHT_FOV = 58
Mythic.RING_RADIUS_MULT = 2.2   -- x the creature's largest horizontal extent

local function enterBonk(run: Run)
	if run.water then
		run.water:stillWater()
		run.water:bonkRing()
	end
	if run.audio then
		run.audio:play("finalSkip", { where = run.surface })
		if not run.spectator then
			run.audio:duckAmbient(0.25, 0.12 * run.stretch)
		end
	end
	if run.cam then
		-- the "gameplay slows" read, done locally: a tighten toward the water
		run.cam:punchFOV(Mythic.TIGHT_FOV, Config.CAMERA.fovBase or 70, 0.5 * run.stretch)
		local eye, focus = CutKit.heroFraming(run)
		run.heroEye, run.heroFocus = eye, focus
		run.cam:flyTo(CFrame.lookAt(eye, focus), 0.25 * run.stretch, true)
	end
end

local function enterRipple(run: Run)
	if run.audio then
		run.audio:play("mythicBass", { where = run.surface })
	end
end

local function updateRipple(run: Run, p: number)
	if run.water then
		run.water:rippleTrain(p)
	end
end

local function enterEruption(run: Run)
	if run.brain then
		Shared.faceCamera(run)
		run.brain:markBreached()
		run.breached = true
		run.brain:revealColors(0.15 * run.stretch)
	end
	if run.water then
		run.water:erupt(run.extents)
		local ext = run.extents :: Vector3
		run.water:shockRing(Mythic.RED, math.max(ext.X, ext.Z) * Mythic.RING_RADIUS_MULT, 0.45 * run.stretch)
	end
	Shared.rimHighlight(run, Mythic.RED)
	if run.post then
		run.post:flash()
	end
	if run.audio then
		run.audio:play("waterExplosion", { where = run.surface })
	end
	if run.shake then
		run.shake:add(1.0)
	end
	if run.cam and run.heroEye then
		run.cam:lookHover(run.heroEye, run.heroFocus)
	end
end

local function updateEruption(run: Run, p: number)
	if run.brain and not run.skipping then
		run.brain:setRise(p)
	end
end

local function enterSettle(run: Run)
	if run.brain then
		run.brain:setRise(1)
	end
	if run.shake then
		run.shake:setSustain(0.08)
	end
end

local function enterBanner(run: Run)
	if run.hype then
		run.hype:banner(run.cut.bannerText, Mythic.RED)
		run.hype:nameText(run.displayName)
	end
	if run.audio then
		run.audio:play("bannerHit", { where = run.surface })
	end
	if run.shake then
		run.shake:add(0.25)
	end
end

local function updateBanner(run: Run, p: number)
	-- small float on the creature; the rim stays red for the whole beat
	if run.brain and not run.skipping then
		run.brain:setRise(1 - 0.02 * math.sin(p * math.pi * 2))
	end
end

Mythic.handlers = {
	bonk     = { enter = enterBonk },
	ripple   = { enter = enterRipple, update = updateRipple },
	eruption = { enter = enterEruption, update = updateEruption },
	settle   = { enter = enterSettle },
	banner   = { enter = enterBanner, update = updateBanner },
	handoff  = Shared.handoff,
}
Mythic.everyFrame = Shared.everyFrameRock
Mythic.build = function(run: Run): boolean
	return Shared.build(run, nil)
end
Mythic.name = "Mythic"
Mythic.beats = Mythic.BEATS
Mythic.revealBeat = "eruption"
Mythic.skippable = false
Mythic.bannerText = "MYTHIC"

return Mythic
```

Add to `Config.ASSETS`: `mythicBass = "kit:catchBigHit",` with `VOLUMES.mythicBass = 0.9`; add `"mythicBass"` to `CinematicClient.SOUND_SLOTS`.

- [ ] **Step 5: Verify.** `Harness.checkBeats("Mythic", 1.6, 1.8)` empty; `Harness.matrix("Takeover", "Mythic")` → 4 `OK` (skip mode: `skippable = false`, so the run simply completes — the harness only asserts restore). Real throw with `ForceNextCatch = <a Mythic name>` at 1x, owner watching, against §6.1. Revert by Uid.

- [ ] **Step 6: Mirror + commit.** Mirror `Cuts/Shared.lua`, `Cuts/Massive.lua`, `Cuts/Mythic.lua`, `WaterFX.lua`, `Config.lua`, `CinematicClient.client.lua`.

```bash
git add game-src/place-full
git commit -m "feat(reveal): Cuts/Shared (handoff+build), WaterFX.shockRing, Mythic cut"
```

---

### Task 6: `Cuts/Secret` + `AuraFX` + `WaterFX:glowBelow`

**Files:**
- Modify: `…CatchCinematic.WaterFX` (add `glowBelow`)
- Create: `…CatchCinematic.AuraFX`, `…CatchCinematic.Cuts.Secret`
- Modify: `Config.ASSETS`, `CinematicClient` `SOUND_SLOTS`

**Interfaces:**
- Produces: `WaterFX:glowBelow(color: Color3, seconds: number)` (fades a disc of light in under the surface; `:cleanup` removes it); `AuraFX.new(stage: Folder, pos: Vector3, color: Color3, radius: number, quality: string, rng: Random): Aura`, `Aura:update(t)`, `Aura:setPos(pos)`, `Aura:fade(seconds)`, `Aura:cleanup()`; `Cuts.Secret`.

- [ ] **Step 1: Beat test first.** `Harness.checkBeats("Secret", 2.9, 3.1)` → FAIL.

- [ ] **Step 2: `WaterFX:glowBelow`.** Add after `dome`:

```lua
-- A glowing disc just UNDER the surface, fading in over `seconds`: Secret's
-- "something is down there" fake-out and God's gold water. Idempotent per colour.
function WaterFX:glowBelow(color: Color3, seconds: number)
	if self._destroyed then
		return
	end
	local disc = Instance.new("Part")
	disc.Name = "GlowBelow"
	disc.Shape = Enum.PartType.Cylinder
	disc.Material = Enum.Material.Neon
	disc.Color = color
	disc.Transparency = 1
	disc.Size = Vector3.new(0.3, 6, 6)
	disc.CFrame = CFrame.new(self._surfacePos - Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	decorPart(disc)
	disc.Parent = self._stage
	table.insert(self._parts, disc)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 0
	light.Range = 30
	light.Parent = disc
	local tw = TweenService:Create(disc, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Transparency = 0.35, Size = Vector3.new(0.3, 18, 18),
	})
	table.insert(self._tweens, tw)
	tw:Play()
	-- PointLight.Brightness is not on the Tween allow-list: hand-lerp it.
	task.spawn(function()
		local t0 = os.clock()
		while not self._destroyed and light.Parent do
			local a = math.clamp((os.clock() - t0) / seconds, 0, 1)
			light.Brightness = 3 * a
			if a >= 1 then
				break
			end
			task.wait()
		end
	end)
end
```

- [ ] **Step 3: `AuraFX`.**

```lua
--!strict
-- CatchCinematic.AuraFX -- a large rift/aura plane behind a creature plus orbiting
-- emitters: Secret's pink rift, God's descent glow. Owns its parts; cleanup()
-- destroys them. Rotation is driven by update(t) from the conductor's clock.
local AuraFX = {}
AuraFX.__index = AuraFX

export type Aura = typeof(setmetatable({} :: { [string]: any }, AuraFX))

local function decor(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Locked = true
end

function AuraFX.new(stage: Folder, pos: Vector3, color: Color3, radius: number, quality: string, rng: Random): Aura
	local self = setmetatable({}, AuraFX)
	self._pos = pos
	self._radius = radius
	self._destroyed = false
	self._parts = {}
	self._emitters = {}
	self._alpha = 0

	local disc = Instance.new("Part")
	disc.Name = "AuraRift"
	disc.Shape = Enum.PartType.Cylinder
	disc.Material = Enum.Material.Neon
	disc.Color = color
	disc.Transparency = 1
	disc.Size = Vector3.new(0.2, radius * 2, radius * 2)
	decor(disc)
	disc.Parent = stage
	self._disc = disc
	table.insert(self._parts, disc)

	local ring = Instance.new("Part")
	ring.Name = "AuraRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.new(1, 1, 1):Lerp(color, 0.5)
	ring.Transparency = 1
	ring.Size = Vector3.new(0.25, radius * 2.3, radius * 2.3)
	decor(ring)
	ring.Parent = stage
	self._ring = ring
	table.insert(self._parts, ring)

	local count = (quality == "low") and 1 or 3
	for i = 1, count do
		local a = Instance.new("Attachment")
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(color)
		e.Rate = (quality == "low") and 12 or 30
		e.Lifetime = NumberRange.new(0.6, 1.1)
		e.Speed = NumberRange.new(2, 5)
		e.Size = NumberSequence.new(0.6, 0)
		e.Transparency = NumberSequence.new(0.2, 1)
		e.LightEmission = 1
		e.Enabled = false
		e.Parent = a
		a.Parent = disc
		table.insert(self._emitters, { a, e, i * (2 * math.pi / count) + rng:NextNumber(0, 1) })
	end
	self:_place(0)
	return (self :: any) :: Aura
end

function AuraFX:_place(t: number)
	local cam = workspace.CurrentCamera
	local look = cam and (cam.CFrame.Position - self._pos).Unit or Vector3.new(0, 0, -1)
	-- cylinder axis is X: rotate so the flat face looks at the camera, then spin
	local base = CFrame.lookAt(self._pos, self._pos + look) * CFrame.Angles(0, math.rad(90), 0)
	self._disc.CFrame = base * CFrame.Angles(t * 0.6, 0, 0)
	self._ring.CFrame = base * CFrame.Angles(-t * 0.9, 0, 0)
	for _, rec in ipairs(self._emitters) do
		local ang = rec[3] + t * 1.4
		rec[1].Position = Vector3.new(0, math.cos(ang) * self._radius * 0.8, math.sin(ang) * self._radius * 0.8)
	end
end

-- alpha 0..1: how present the aura is. Hand-set (Transparency is on the allow-list,
-- but the aura tracks the clock, so it is written per frame rather than tweened).
function AuraFX:update(t: number, alpha: number?)
	if self._destroyed then
		return
	end
	if alpha then
		self._alpha = math.clamp(alpha, 0, 1)
	end
	self._disc.Transparency = 1 - 0.45 * self._alpha
	self._ring.Transparency = 1 - 0.7 * self._alpha
	for _, rec in ipairs(self._emitters) do
		rec[2].Enabled = self._alpha > 0.2
	end
	self:_place(t)
end

function AuraFX:setPos(pos: Vector3)
	self._pos = pos
end

function AuraFX:fade(seconds: number)
	if self._destroyed then
		return
	end
	local a0 = self._alpha
	task.spawn(function()
		local t0 = os.clock()
		while not self._destroyed do
			local a = math.clamp((os.clock() - t0) / math.max(seconds, 0.05), 0, 1)
			self._alpha = a0 * (1 - a)
			self._disc.Transparency = 1 - 0.45 * self._alpha
			self._ring.Transparency = 1 - 0.7 * self._alpha
			if a >= 1 then
				for _, rec in ipairs(self._emitters) do
					rec[2].Enabled = false
				end
				break
			end
			task.wait()
		end
	end)
end

function AuraFX:cleanup()
	if self._destroyed then
		return
	end
	self._destroyed = true
	for _, p in ipairs(self._parts) do
		pcall(function()
			p:Destroy()
		end)
	end
	self._parts = {}
end

return AuraFX
```

- [ ] **Step 4: `Cuts/Secret`** (spec §6.2):

```lua
--!strict
-- CatchCinematic.Cuts.Secret -- SUSPENSE. 3.0s, not skippable. The first rarity
-- with a genuine fake-out: nothing happens, it almost feels like the reveal failed,
-- then a pink glow under the water, then it launches.
local folder = script.Parent.Parent
local Config = require(folder:WaitForChild("Config"))
local CutKit = require(folder:WaitForChild("CutKit"))
local Types = require(folder:WaitForChild("Types"))
local AuraFX = require(folder:WaitForChild("AuraFX"))
local Shared = require(script.Parent:WaitForChild("Shared"))
type Run = Types.Run

local Secret = {}

-- ===== TUNABLES (spec S6.2) =====
Secret.BEATS = {
	{ name = "bonk",    t0 = 0.00, t1 = 0.10 },
	{ name = "nothing", t0 = 0.10, t1 = 0.60 },  -- no creature, no card; ripples; near-silence
	{ name = "fakeout", t0 = 0.60, t1 = 1.00 },  -- ripples die; pink glow UNDER the water
	{ name = "launch",  t0 = 1.00, t1 = 1.20 },  -- REVEAL: splash, pink column, creature launches
	{ name = "spiral",  t0 = 1.20, t1 = 1.50 },  -- stops in front of the camera; pink spirals
	{ name = "banner",  t0 = 1.50, t1 = 2.50 },  -- SECRET; giant pink rift; slow rotation
	{ name = "handoff", t0 = 2.50, t1 = 3.00 },
}
Secret.PINK = Color3.fromRGB(255, 90, 220)
Secret.VIOLET = Color3.fromRGB(150, 60, 255)
Secret.HUSH_LEVEL = 0.05

local function enterBonk(run: Run)
	if run.water then
		run.water:stillWater()
		run.water:bonkRing()
	end
	if run.audio then
		run.audio:play("finalSkip", { where = run.surface })
	end
	if run.cam then
		local eye, focus = CutKit.heroFraming(run)
		run.heroEye, run.heroFocus = eye, focus
		run.cam:flyTo(CFrame.lookAt(eye, run.surface), 0.6 * run.stretch, false)
	end
end

local function enterNothing(run: Run)
	if run.audio and not run.spectator then
		run.audio:duckAmbient(Secret.HUSH_LEVEL, 0.4 * run.stretch)
	end
end

local function updateNothing(run: Run, p: number)
	if run.water then
		run.water:rippleTrain(p * 0.4)
	end
end

local function enterFakeout(run: Run)
	if run.water then
		run.water:glowBelow(Secret.VIOLET, CutKit.beatSeconds(run))
	end
	if run.audio then
		run.audio:play("secretHum", { where = run.surface })
	end
end

local function enterLaunch(run: Run)
	if run.brain then
		Shared.faceCamera(run)
		run.brain:markBreached()
		run.breached = true
		run.brain:revealColors(0.1 * run.stretch)
	end
	if run.water then
		run.water:erupt(run.extents)
		run.water:godrays(run.surface, (run.extents :: Vector3).Y * 1.6, Secret.PINK)
	end
	if run.audio then
		run.audio:unsilence()
		run.audio:play("secretLaunch", { where = run.surface })
		if not run.spectator then
			run.audio:restoreAmbient(0.3 * run.stretch)
		end
	end
	if run.shake then
		run.shake:add(0.8)
	end
	if run.post then
		run.post:flash()
	end
	if run.cam and run.heroEye then
		run.cam:lookHover(run.heroEye, run.heroFocus)
	end
end

local function updateLaunch(run: Run, p: number)
	if run.brain and not run.skipping then
		run.brain:setRise(p)
	end
end

local function enterSpiral(run: Run)
	Shared.rimHighlight(run, Secret.PINK)
	if run.brain then
		run.brain:setRise(1)
	end
	local ext = run.extents :: Vector3
	local centre = run.surface + Vector3.new(0, ext.Y * 0.5, 0)
	local aura = AuraFX.new(run.stage, centre, Secret.PINK, math.max(ext.X, ext.Y, ext.Z) * 0.9, run.quality, run.rng)
	run.aura = aura
	CutKit.track(run, function()
		aura:cleanup()
	end)
end

local function updateSpiral(run: Run, p: number)
	if run.aura then
		run.aura:update(run.t, p * 0.35)
	end
end

local function enterBanner(run: Run)
	if run.hype then
		run.hype:banner(run.cut.bannerText, Secret.PINK)
		run.hype:nameText(run.displayName)
	end
	if run.audio then
		run.audio:play("bannerHit", { where = run.surface })
	end
	if run.water and run.model then
		run.water:cascade(run.model, 0.8 * run.stretch)
	end
	if run.shake then
		run.shake:add(0.3)
	end
end

local function updateBanner(run: Run, p: number)
	if run.aura then
		run.aura:update(run.t, 1)
	end
	if run.brain and not run.skipping then
		-- slow rotation: setRise's yaw is alpha-driven, so drift alpha a hair for the turn
		run.brain:setRise(1 - 0.03 * math.sin(p * math.pi))
	end
end

local function exitBanner(run: Run)
	if run.aura then
		run.aura:fade(0.4 * run.stretch)
	end
end

Secret.handlers = {
	bonk    = { enter = enterBonk },
	nothing = { enter = enterNothing, update = updateNothing },
	fakeout = { enter = enterFakeout },
	launch  = { enter = enterLaunch, update = updateLaunch },
	spiral  = { enter = enterSpiral, update = updateSpiral },
	banner  = { enter = enterBanner, update = updateBanner, exit = exitBanner },
	handoff = Shared.handoff,
}
Secret.everyFrame = Shared.everyFrameRock
Secret.build = function(run: Run): boolean
	return Shared.build(run, nil)
end
Secret.onCancel = function(run: Run)
	if run.aura then
		run.aura:cleanup()
		run.aura = nil
	end
end
Secret.name = "Secret"
Secret.beats = Secret.BEATS
Secret.revealBeat = "launch"
Secret.skippable = false
Secret.bannerText = "SECRET"

return Secret
```

Add to `Config.ASSETS`: `secretHum = "kit:catchSparkle",   -- TODO: replace -- low eerie hum, ~0.5s` and `secretLaunch = "kit:splashBig",` with volumes `secretHum = 0.35, secretLaunch = 0.9`; add both to `SOUND_SLOTS`.

- [ ] **Step 5: Verify.** `checkBeats("Secret", 2.9, 3.1)` empty; `matrix("Takeover", "Secret")` 4 `OK` — the cancel mode is the important one here: cancel lands during `nothing`/`fakeout` (the clock parks before `launch`), so the fake-out must wind down to nothing with the water calm. Real throw `ForceNextCatch = <a Secret name>` at 1x, owner watching, against §6.2 — confirm the 0.10–1.00 dead air reads as a fake-out and NOT as lag. Revert by Uid.

- [ ] **Step 6: Mirror + commit.** Mirror `WaterFX.lua`, `AuraFX.lua`, `Cuts/Secret.lua`, `Config.lua`, `CinematicClient.client.lua`.

```bash
git add game-src/place-full
git commit -m "feat(reveal): Secret cut with fake-out; AuraFX; WaterFX.glowBelow"
```

---

### Task 7: `Cuts/God` + `BeamFX` + `PostFX:tint`/`sunRays` + `BrainrotRig:setDescent` + the exclusive choir slot

**Files:**
- Modify: `…CatchCinematic.PostFX` (add `tint`, `sunRays`; `easeBack` restores both; `new` creates a tagged `SunRaysEffect`)
- Modify: `…CatchCinematic.BrainrotRig` (add `setDescent`)
- Create: `…CatchCinematic.BeamFX`, `…CatchCinematic.Cuts.God`
- Modify: `Config.ASSETS` (`godRumble`, `beamRise`, `godChoir`, `goldShockwave`), `CinematicClient` `SOUND_SLOTS`

**Interfaces:**
- Produces: `PostFX:tint(color: Color3, seconds: number)`, `PostFX:sunRays(intensity: number, seconds: number)` (both eased back by `easeBack`, destroyed by `cleanup`); `BrainrotRig:setDescent(alpha: number, fromHeight: number)` (pure in alpha: 0 = `fromHeight` studs above the rise pose, 1 = the rise pose; yaw turns 0.75 of a revolution); `BeamFX.new(stage, basePos, color, height, radius, quality): Beam`, `Beam:setBase(pos)`, `Beam:fire(seconds)`, `Beam:fade(seconds)`, `Beam:cleanup()`; `Cuts.God` with `God.handlers.beam`, `God.handlers.choir`, `God.handlers.descent`, `God.handlers.arrival` reusable by MassiveGod; run fields `run.beam`, `run.beamBase`, `run.descentHeight`.

- [ ] **Step 1: Beat test first.** `Harness.checkBeats("God", 4.9, 5.1)` → FAIL.

- [ ] **Step 2: `PostFX:tint` + `sunRays`.** `multi_edit` `PostFX`: in `new`, after the blur block add

```lua
	local rays = Instance.new("SunRaysEffect")
	rays.Name = "CinematicSunRays"
	rays.Intensity = 0
	rays.Spread = 0.8
	rays.Parent = Lighting
	CollectionService:AddTag(rays, CINEMATIC_TAG)
```

store it as `_rays = rays` (add to the type and the constructor table), destroy it in `cleanup` (same pcall pattern), and add two methods before `cleanup`:

```lua
-- Environment tint via OUR ColorCorrection's TintColor (white = none). Hand-lerped
-- like every other value here; easeBack() returns it to white.
function PostFX:tint(color: Color3, seconds: number)
	if self._destroyed then
		return
	end
	seconds = math.max(seconds, 0.05)
	self._tintGen = (self._tintGen or 0) + 1
	local myGen = self._tintGen
	local cc = self._cc
	local from = cc.TintColor
	task.spawn(function()
		local t0 = os.clock()
		while self._tintGen == myGen and not self._destroyed do
			local a = math.clamp((os.clock() - t0) / seconds, 0, 1)
			cc.TintColor = from:Lerp(color, a * a * (3 - 2 * a))
			if a >= 1 then
				break
			end
			task.wait()
		end
	end)
end

function PostFX:sunRays(intensity: number, seconds: number)
	if self._destroyed then
		return
	end
	seconds = math.max(seconds, 0.05)
	self._raysGen = (self._raysGen or 0) + 1
	local myGen = self._raysGen
	local rays = self._rays
	local from = rays.Intensity
	task.spawn(function()
		local t0 = os.clock()
		while self._raysGen == myGen and not self._destroyed do
			local a = math.clamp((os.clock() - t0) / seconds, 0, 1)
			rays.Intensity = from + (intensity - from) * a
			if a >= 1 then
				break
			end
			task.wait()
		end
	end)
end
```

In `easeBack`, at its start, add `self:tint(Color3.new(1, 1, 1), seconds)` and `self:sunRays(0, seconds)`. Compile-check.

- [ ] **Step 3: `BrainrotRig:setDescent`.** Add after `setRise`:

```lua
-- Pure function of alpha, the sky path: 0 = `fromHeight` studs ABOVE the rise pose,
-- 1 = the rise pose itself, with a 0.75-turn yaw and a sine ease-in-out. Used
-- forward for God's descent and backward (1 - alpha) for Massive God's ascension.
-- Reveals the colours on first use: a creature in a beam of light is never a
-- silhouette.
function BrainrotRig:setDescent(alpha: number, fromHeight: number)
	if self._destroyed then
		return
	end
	alpha = math.clamp(alpha, 0, 1)
	if not self._descentStarted then
		self._descentStarted = true
		self:revealColors(0.05)
	end
	self._riseAlpha = 1
	self._breached = true
	local e = 0.5 - 0.5 * math.cos(math.pi * alpha)
	local top = self._risePos + Vector3.new(0, fromHeight, 0)
	local pos = top:Lerp(self._risePos, e)
	self:_placeAt(pos, math.pi * 0.6 + alpha * math.pi * 1.5)
end
```

Compile-check.

- [ ] **Step 4: `BeamFX`.**

```lua
--!strict
-- CatchCinematic.BeamFX -- the heavenly beam: a neon core column + a wide translucent
-- outer column + a base light, from a base point straight up. fire() grows it from
-- nothing; fade() takes it away; setBase() re-anchors it (Massive God: on the rig).
local BeamFX = {}
BeamFX.__index = BeamFX

export type Beam = typeof(setmetatable({} :: { [string]: any }, BeamFX))

local function decor(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Locked = true
end

function BeamFX.new(stage: Folder, basePos: Vector3, color: Color3, height: number, radius: number, quality: string): Beam
	local self = setmetatable({}, BeamFX)
	self._base = basePos
	self._height = height
	self._radius = radius
	self._color = color
	self._quality = quality
	self._destroyed = false
	self._alpha = 0
	self._parts = {}

	local core = Instance.new("Part")
	core.Name = "BeamCore"
	core.Shape = Enum.PartType.Cylinder
	core.Material = Enum.Material.Neon
	core.Color = Color3.new(1, 1, 1):Lerp(color, 0.35)
	core.Transparency = 1
	decor(core)
	core.Parent = stage
	self._core = core
	table.insert(self._parts, core)

	local outer = Instance.new("Part")
	outer.Name = "BeamOuter"
	outer.Shape = Enum.PartType.Cylinder
	outer.Material = Enum.Material.ForceField
	outer.Color = color
	outer.Transparency = 1
	decor(outer)
	outer.Parent = stage
	self._outer = outer
	table.insert(self._parts, outer)

	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 0
	light.Range = 60
	light.Parent = core
	self._light = light

	self:_apply()
	return (self :: any) :: Beam
end

function BeamFX:_apply()
	local a = self._alpha
	local h = math.max(self._height * a, 0.1)
	local mid = self._base + Vector3.new(0, h / 2, 0)
	local cf = CFrame.new(mid) * CFrame.Angles(0, 0, math.rad(90))
	self._core.Size = Vector3.new(h, self._radius * 2 * a, self._radius * 2 * a)
	self._core.CFrame = cf
	self._core.Transparency = 1 - 0.85 * a
	self._outer.Size = Vector3.new(h, self._radius * 5 * a, self._radius * 5 * a)
	self._outer.CFrame = cf
	self._outer.Transparency = 1 - 0.35 * a
	self._light.Brightness = 6 * a
end

function BeamFX:setBase(pos: Vector3)
	self._base = pos
	self:_apply()
end

local function ramp(self: any, to: number, seconds: number)
	local from = self._alpha
	self._gen = (self._gen or 0) + 1
	local myGen = self._gen
	task.spawn(function()
		local t0 = os.clock()
		while not self._destroyed and self._gen == myGen do
			local a = math.clamp((os.clock() - t0) / math.max(seconds, 0.05), 0, 1)
			self._alpha = from + (to - from) * (a * a * (3 - 2 * a))
			self:_apply()
			if a >= 1 then
				break
			end
			task.wait()
		end
	end)
end

-- Direct level, no ramp: Massive God's "tiny gold light grows" beat drives this per
-- frame from the conductor's clock.
function BeamFX:setAlpha(a: number)
	if self._destroyed then
		return
	end
	self._gen = (self._gen or 0) + 1 -- cancels any in-flight ramp
	self._alpha = math.clamp(a, 0, 1)
	self:_apply()
end

function BeamFX:fire(seconds: number)
	if self._destroyed then
		return
	end
	ramp(self, 1, seconds)
end

function BeamFX:fade(seconds: number)
	if self._destroyed then
		return
	end
	ramp(self, 0, seconds)
end

function BeamFX:cleanup()
	if self._destroyed then
		return
	end
	self._destroyed = true
	for _, p in ipairs(self._parts) do
		pcall(function()
			p:Destroy()
		end)
	end
	self._parts = {}
end

return BeamFX
```

- [ ] **Step 5: `Cuts/God`** (spec §6.3):

```lua
--!strict
-- CatchCinematic.Cuts.God -- HEAVEN. 5.0s, skippable to `arrival`. The water glows
-- gold, a beam shoots into the sky, the EXCLUSIVE choir hits, and the creature
-- descends from the light. The beam/choir/descent/arrival handlers are reused by
-- Cuts.MassiveGod, anchored on run.beamBase when it is set.
local folder = script.Parent.Parent
local Config = require(folder:WaitForChild("Config"))
local CutKit = require(folder:WaitForChild("CutKit"))
local Types = require(folder:WaitForChild("Types"))
local BeamFX = require(folder:WaitForChild("BeamFX"))
local AuraFX = require(folder:WaitForChild("AuraFX"))
local Shared = require(script.Parent:WaitForChild("Shared"))
type Run = Types.Run

local God = {}

-- ===== TUNABLES (spec S6.3) =====
God.BEATS = {
	{ name = "bonk",    t0 = 0.00, t1 = 0.30 },  -- UI hidden; world goes quiet
	{ name = "rumble",  t0 = 0.30, t1 = 0.50 },
	{ name = "glow",    t0 = 0.50, t1 = 0.80 },  -- water glows gold/white; one massive ripple
	{ name = "tilt",    t0 = 0.80, t1 = 1.00 },  -- gold particles rise; camera tilts up
	{ name = "beam",    t0 = 1.00, t1 = 1.30 },  -- beam water->sky; environment gold
	{ name = "choir",   t0 = 1.30, t1 = 2.00 },  -- the exclusive choir; beam holds
	{ name = "descent", t0 = 2.00, t1 = 3.50 },  -- REVEAL: creature descends inside the beam
	{ name = "arrival", t0 = 3.50, t1 = 3.80 },  -- flash, GOD, gold shockwave
	{ name = "linger",  t0 = 3.80, t1 = 4.80 },  -- float; beam fades; choir tails
	{ name = "handoff", t0 = 4.80, t1 = 5.00 },
}
God.GOLD = Color3.fromRGB(255, 226, 120)
God.WHITE_GOLD = Color3.fromRGB(255, 245, 210)
God.BEAM_HEIGHT = 400
God.BEAM_RADIUS_MULT = 0.6     -- x the creature's largest horizontal extent
God.DESCENT_HEIGHT_MULT = 6    -- x the creature's height: where the descent starts
God.TINT = Color3.fromRGB(255, 236, 190)
God.SUNRAYS = 0.35

local function beamBase(run: Run): Vector3
	return run.beamBase or run.surface
end

local function enterBonk(run: Run)
	if run.water then
		run.water:stillWater()
		run.water:bonkRing()
	end
	if run.audio then
		run.audio:play("finalSkip", { where = run.surface })
		if not run.spectator then
			run.audio:silence()
		end
	end
	if run.cam then
		local eye, focus = CutKit.heroFraming(run)
		run.heroEye, run.heroFocus = eye, focus
		run.cam:flyTo(CFrame.lookAt(eye, run.surface), 0.8 * run.stretch, false)
	end
end

local function enterRumble(run: Run)
	if run.audio then
		run.audio:play("godRumble", { where = run.surface, speed = run.speed })
	end
	if run.shake then
		run.shake:setSustain(0.15)
	end
end

local function enterGlow(run: Run)
	if run.water then
		run.water:glowBelow(God.WHITE_GOLD, CutKit.beatSeconds(run))
		run.water:rippleTrain(1)
	end
end

local function enterTilt(run: Run)
	if run.cam then
		-- skyward framing: low eye, looking up the beam line
		local ext = run.extents :: Vector3
		local eye = run.surface - run.horiz * (math.max(ext.X, ext.Z) * 1.6 + CutKit.VIEW_DIST_PAD) + Vector3.new(0, 3, 0)
		local focus = run.surface + Vector3.new(0, ext.Y * 2.5, 0)
		run.skyEye, run.skyFocus = eye, focus
		run.cam:flyTo(CFrame.lookAt(eye, focus), 0.9 * run.stretch, false)
	end
	if run.audio then
		run.audio:play("beamRise", { where = run.surface })
	end
end

local function enterBeam(run: Run)
	local ext = run.extents :: Vector3
	local beam = BeamFX.new(run.stage, beamBase(run), God.GOLD, God.BEAM_HEIGHT, math.max(ext.X, ext.Z) * God.BEAM_RADIUS_MULT, run.quality)
	run.beam = beam
	CutKit.track(run, function()
		beam:cleanup()
	end)
	beam:fire(CutKit.beatSeconds(run))
	if run.water then
		run.water:godrays(beamBase(run), ext.Y * 2.0, God.GOLD)
	end
	if run.post then
		run.post:tint(God.TINT, 0.6 * run.stretch)
		run.post:sunRays(God.SUNRAYS, 0.6 * run.stretch)
		run.post:hypeOn(0.6 * run.stretch)
	end
	if run.shake then
		run.shake:add(0.4)
	end
end

local function enterChoir(run: Run)
	-- THE EXCLUSIVE SLOT. Only Cuts.God and Cuts.MassiveGod may play godChoir.
	if run.audio then
		run.audio:unsilence()
		run.audio:play("godChoir")
	end
end

local function enterDescent(run: Run)
	local ext = run.extents :: Vector3
	run.descentHeight = ext.Y * God.DESCENT_HEIGHT_MULT
	if run.brain then
		Shared.faceCamera(run)
		run.brain:markBreached()
		run.breached = true
		run.brain:setDescent(0, run.descentHeight)
	end
	Shared.rimHighlight(run, God.GOLD)
	local centre = run.surface + Vector3.new(0, ext.Y * 0.5, 0)
	local aura = AuraFX.new(run.stage, centre, God.GOLD, math.max(ext.X, ext.Y, ext.Z) * 0.7, run.quality, run.rng)
	run.aura = aura
	CutKit.track(run, function()
		aura:cleanup()
	end)
	if run.cam and run.skyEye then
		run.cam:lookHover(run.skyEye, run.skyFocus)
	end
end

local function updateDescent(run: Run, p: number)
	if run.brain and not run.skipping then
		run.brain:setDescent(p, run.descentHeight or 30)
	end
	if run.aura then
		local ext = run.extents :: Vector3
		local y = (run.descentHeight or 30) * (1 - (0.5 - 0.5 * math.cos(math.pi * p)))
		run.aura:setPos(run.surface + Vector3.new(0, ext.Y * 0.5 + y, 0))
		run.aura:update(run.t, 0.6)
	end
	if run.cam and run.skyEye then
		-- follow the creature down: focus slides from the sky point to the hero focus
		local eye, focus = CutKit.heroFraming(run)
		local f = (run.skyFocus :: Vector3):Lerp(focus, p)
		local e = (run.skyEye :: Vector3):Lerp(eye, p * p)
		run.cam:lookHover(e, f)
	end
end

local function enterArrival(run: Run)
	if run.brain then
		run.brain:setDescent(1, run.descentHeight or 30)
	end
	if run.post then
		run.post:flash()
	end
	if run.hype then
		run.hype:banner(run.cut.bannerText, God.GOLD)
		run.hype:nameText(run.displayName)
	end
	if run.water then
		local ext = run.extents :: Vector3
		run.water:shockRing(God.GOLD, math.max(ext.X, ext.Z) * 6, 1.2 * run.stretch)
	end
	if run.audio then
		run.audio:play("goldShockwave", { where = run.surface })
	end
	if run.shake then
		run.shake:add(0.9)
	end
end

local function enterLinger(run: Run)
	if run.beam then
		run.beam:fade(CutKit.beatSeconds(run))
	end
	if run.aura then
		run.aura:fade(CutKit.beatSeconds(run) * 0.8)
	end
	if run.post then
		run.post:easeBack(CutKit.beatSeconds(run))
	end
	if run.shake then
		run.shake:setSustain(0)
	end
end

local function updateLinger(run: Run, p: number)
	if run.brain and not run.skipping then
		run.brain:setDescent(1 - 0.01 * math.sin(p * math.pi * 2), run.descentHeight or 30)
	end
	if run.aura then
		run.aura:update(run.t)
	end
end

God.handlers = {
	bonk    = { enter = enterBonk },
	rumble  = { enter = enterRumble },
	glow    = { enter = enterGlow },
	tilt    = { enter = enterTilt },
	beam    = { enter = enterBeam },
	choir   = { enter = enterChoir },
	descent = { enter = enterDescent, update = updateDescent },
	arrival = { enter = enterArrival },
	linger  = { enter = enterLinger, update = updateLinger },
	handoff = Shared.handoff,
}
God.everyFrame = Shared.everyFrameRock
God.build = function(run: Run): boolean
	return Shared.build(run, nil)
end
function God.onSkip(run: Run)
	if run.hype then
		run.hype:interrupt()
		run.hype:hideSkipPrompt()
	end
	if run.water then
		run.water:cleanup()
	end
	if not run.beam then
		enterBeam(run)
	end
	if run.beam then
		run.beam:fade(0.1)
	end
	if not run.aura then
		enterDescent(run)
	end
	if run.brain then
		run.brain:setDescent(1, run.descentHeight or 30)
	end
	if run.post then
		run.post:easeBack(0.2)
	end
	if run.audio then
		run.audio:unsilence()
	end
	if run.shake then
		run.shake:setSustain(0)
	end
	if run.cam then
		local eye, focus = CutKit.heroFraming(run)
		run.cam:lookHover(eye, focus)
	end
end
function God.onCancel(run: Run)
	if run.beam then
		run.beam:cleanup()
		run.beam = nil
	end
	if run.aura then
		run.aura:cleanup()
		run.aura = nil
	end
end
God.name = "God"
God.beats = God.BEATS
God.revealBeat = "descent"
God.skippable = true
God.skipTo = "arrival"
God.bannerText = "GOD"

return God
```

Add to `Config.ASSETS` (with a comment block):

```lua
	-- ===== GOD-ONLY SLOTS. godChoir is EXCLUSIVE: only Cuts.God and Cuts.MassiveGod may
	-- play it (spec S10) so players learn the sound means God. Do not reuse elsewhere.
	godRumble      = "rbxassetid://1837834264", -- same clip as massiveRumble; TODO: replace with a low sub-rumble
	beamRise       = "kit:catchSparkle",   -- TODO: replace -- rising shimmer, ~1s
	godChoir       = "kit:catchGod",       -- TODO: replace -- the angelic "AAAAAH" choir, ~3s (owner upload)
	goldShockwave  = "kit:catchBigHit",
```

volumes `godRumble = 0.8, beamRise = 0.5, godChoir = 0.9, goldShockwave = 0.9`; add the four to `SOUND_SLOTS`. `script_grep` the place for `godChoir` — expected hits: `Config`, `CinematicClient` (preload), `Cuts.God` only (MassiveGod joins in Task 8).

- [ ] **Step 6: Verify.** `checkBeats("God", 4.9, 5.1)` empty; `matrix("Takeover", "God")` 4 `OK` — after each run assert `Lighting.ColorCorrection`-class children are only the pre-existing ones (the harness's `lightChildren` diff covers it) and that no `TintColor` lingers (our CC is destroyed with the run). Real throw: `ForceNextCatch = "Secret Pete"` (the only God) at 1x, owner watching, against §6.3: quiet → rumble → gold water → camera tilts → beam + gold environment → choir at 1.3 → descent → flash + "GOD" + shockwave → linger → streak. Revert by Uid (and note the mint serial burned).

- [ ] **Step 7: Mirror + commit.** Mirror `PostFX.lua`, `BrainrotRig.lua`, `BeamFX.lua`, `Cuts/God.lua`, `Config.lua`, `CinematicClient.client.lua`.

```bash
git add game-src/place-full
git commit -m "feat(reveal): God cut with sky beam, exclusive choir and descent; BeamFX; PostFX tint/sunRays; BrainrotRig.setDescent"
```

---

### Task 8: `Cuts/MassiveGod` — one cohesive ultimate cut

**Files:**
- Create: `…CatchCinematic.Cuts.MassiveGod`

**Interfaces:**
- Consumes: `Massive.handlers.{bonk, silhouette, emergence, scale}`, `God.handlers.{beam, choir, descent, arrival}` and `God.onCancel`, `Shared.*`, `BeamFX:setBase`, `BrainrotRig:setDescent`.
- Produces: `Cuts.MassiveGod`.

- [ ] **Step 1: Beat test first.** `Harness.checkBeats("MassiveGod", 11.9, 12.1)` → FAIL.

- [ ] **Step 2: `Cuts/MassiveGod`** (spec §6.6):

```lua
--!strict
-- CatchCinematic.Cuts.MassiveGod -- ULTIMATE. ~12s, skippable to `finalReveal`. ONE
-- cohesive cinematic: the Massive emergence (Massive's handlers, compressed bounds)
-- flows into the God heaven sequence (God's handlers) through three beats only this
-- cut has: hush, ascend, and the final reveal at the water. The beam is anchored on
-- the creature (run.beamBase), never on the water. No second copy of either code path.
local folder = script.Parent.Parent
local Config = require(folder:WaitForChild("Config"))
local CutKit = require(folder:WaitForChild("CutKit"))
local Types = require(folder:WaitForChild("Types"))
local Shared = require(script.Parent:WaitForChild("Shared"))
local Massive = require(script.Parent:WaitForChild("Massive"))
local God = require(script.Parent:WaitForChild("God"))
type Run = Types.Run

local MassiveGod = {}

-- ===== TUNABLES (spec S6.6) =====
MassiveGod.BEATS = {
	{ name = "bonk",        t0 = 0.00, t1 = 0.40 },   -- I   Massive
	{ name = "ripple",      t0 = 0.40, t1 = 1.20 },   -- I   still + ripple compressed (own handler)
	{ name = "silhouette",  t0 = 1.20, t1 = 1.80 },   -- I   Massive
	{ name = "emergence",   t0 = 1.80, t1 = 2.80 },   -- I   REVEAL -- Massive
	{ name = "scale",       t0 = 2.80, t1 = 4.50 },   -- I   Massive (pull back, full rise)
	{ name = "hush",        t0 = 4.50, t1 = 5.50 },   -- II  unique: silence, stillness, tiny gold light grows
	{ name = "beam",        t0 = 5.50, t1 = 6.50 },   -- III God's beam, anchored on the rig; choir
	{ name = "ascend",      t0 = 6.50, t1 = 8.00 },   -- IV  unique: rises into the beam, vanishes, emptiness
	{ name = "descent",     t0 = 8.00, t1 = 10.00 },  -- V   God's descent at full Massive scale
	{ name = "finalReveal", t0 = 10.00, t1 = 10.80 }, -- VI  flash, gold shockwave, water explodes, MASSIVE GOD
	{ name = "return",      t0 = 10.80, t1 = 12.00 }, -- VII beam fades, water settles, streak, restore
}
MassiveGod.ASCEND_HEIGHT_MULT = 5   -- x creature height: how far it rises into the beam

local function updateRipple(run: Run, p: number)
	if p < 0.05 and not run.rumbleStarted then
		run.rumbleStarted = true
		if run.audio then
			run.audio:play("massiveRumble", { where = run.surface, speed = run.speed })
		end
		if run.cam then
			local eye = run.travelEye or (run.surface - run.horiz * CutKit.TRAVEL_BACK_STUDS + Vector3.new(0, 6, 0))
			run.cam:lookHover(eye, run.surface)
		end
	end
	if run.water then
		run.water:rippleTrain(p)
		run.water:suctionAndShadow(p * 0.5)
	end
	if run.shake then
		run.shake:setSustain((Config.SHAKE.dreadRampTo or 0.4) * p)
	end
end

local function enterHush(run: Run)
	if run.audio then
		run.audio:silence()
	end
	if run.shake then
		run.shake:setSustain(0)
	end
	Shared.calmAngry(run)
	if run.brain then
		run.brain:setRise(1)
	end
	local ext = run.extents :: Vector3
	-- the beam will come FROM the creature: anchor on its head
	run.beamBase = run.brain and run.brain:headTop() or (run.surface + Vector3.new(0, ext.Y, 0))
	if run.water then
		run.water:glowBelow(God.WHITE_GOLD, CutKit.beatSeconds(run))
	end
	if run.cam then
		-- slow tilt up from the far framing toward the sky above the creature
		local eye = run.farEye or select(1, CutKit.farFraming(run))
		run.skyEye = eye
		run.skyFocus = (run.beamBase :: Vector3) + Vector3.new(0, ext.Y * 2.0, 0)
		run.cam:flyTo(CFrame.lookAt(eye, run.skyFocus), CutKit.beatSeconds(run), false)
	end
end

local function updateHush(run: Run, p: number)
	-- a tiny gold light above the creature grows: the beam itself, at a whisper,
	-- driven per frame from the clock. God's beam handler builds it (and the
	-- godrays/tint that come with it); setAlpha(0) immediately cancels its ramp so
	-- nothing shows until this beat says so.
	if p > 0.4 and not run.beam then
		God.handlers.beam.enter(run)
		if run.beam then
			run.beam:setAlpha(0)
		end
	end
	if run.beam then
		run.beam:setAlpha(0.06 * math.clamp((p - 0.4) / 0.6, 0, 1))
	end
end

local function enterBeam(run: Run)
	if run.beam then
		run.beam:fire(CutKit.beatSeconds(run))
	else
		God.handlers.beam.enter(run)
	end
	God.handlers.choir.enter(run)
	if run.post then
		run.post:tint(God.TINT, 0.6 * run.stretch)
		run.post:sunRays(God.SUNRAYS, 0.6 * run.stretch)
	end
end

local function enterAscend(run: Run)
	local ext = run.extents :: Vector3
	run.descentHeight = ext.Y * MassiveGod.ASCEND_HEIGHT_MULT
	Shared.rimHighlight(run, God.GOLD)
	if run.cam and run.skyEye then
		run.cam:lookHover(run.skyEye, run.skyFocus)
	end
end

local function updateAscend(run: Run, p: number)
	if run.brain and not run.skipping then
		-- reverse of the descent: alpha 1 (at the water) -> 0 (high in the beam)
		run.brain:setDescent(1 - p, run.descentHeight or 40)
		-- the last third: gone into the light
		if p > 0.66 and run.model then
			local f = (p - 0.66) / 0.34
			for _, d in ipairs(run.model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Transparency = f
				end
			end
		end
	end
end

local function exitAscend(run: Run)
	-- a beat of emptiness: the creature is not in the world
	if run.model then
		for _, d in ipairs(run.model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Transparency = 1
			end
		end
	end
end

local function enterDescent(run: Run)
	-- reappear above the player, then God's descent handler drives it down
	if run.model then
		for _, d in ipairs(run.model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "CinematicAura" then
				d.Transparency = 0
			end
		end
	end
	God.handlers.descent.enter(run)
	if run.cam then
		local eye, focus = CutKit.farFraming(run)
		run.skyEye = eye
		run.skyFocus = focus + Vector3.new(0, (run.descentHeight or 40), 0)
		run.cam:lookHover(run.skyEye, run.skyFocus)
	end
end

local function enterFinalReveal(run: Run)
	God.handlers.arrival.enter(run)
	if run.water then
		run.water:erupt(run.extents)
	end
	if run.audio then
		run.audio:play("waterExplosion", { where = run.surface })
	end
	if run.cam then
		local eye, focus = CutKit.farFraming(run)
		run.cam:lookHover(eye, focus)
	end
end

local function enterReturn(run: Run)
	if run.beam then
		run.beam:fade(CutKit.beatSeconds(run) * 0.6)
	end
	if run.aura then
		run.aura:fade(CutKit.beatSeconds(run) * 0.5)
	end
	Shared.handoff.enter(run)
end

MassiveGod.handlers = {
	bonk        = Massive.handlers.bonk,
	ripple      = { update = updateRipple },
	silhouette  = Massive.handlers.silhouette,
	emergence   = Massive.handlers.emergence,
	scale       = Massive.handlers.scale,
	hush        = { enter = enterHush, update = updateHush },
	beam        = { enter = enterBeam },
	ascend      = { enter = enterAscend, update = updateAscend, exit = exitAscend },
	descent     = { enter = enterDescent, update = God.handlers.descent.update },
	finalReveal = { enter = enterFinalReveal },
	["return"]  = { enter = enterReturn, update = Shared.handoff.update },
}
MassiveGod.everyFrame = Shared.everyFrameRock
MassiveGod.build = function(run: Run): boolean
	return Shared.build(run, "Massive")
end
function MassiveGod.onSkip(run: Run)
	Massive.onSkip(run)
	if run.model then
		for _, d in ipairs(run.model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "CinematicAura" then
				d.Transparency = 0
			end
		end
	end
	if run.beam then
		run.beam:fade(0.1)
	end
	if run.aura then
		run.aura:fade(0.1)
	end
	if run.brain then
		run.brain:setDescent(1, run.descentHeight or 40)
	end
end
MassiveGod.onCancel = God.onCancel
MassiveGod.name = "MassiveGod"
MassiveGod.beats = MassiveGod.BEATS
MassiveGod.revealBeat = "emergence"
MassiveGod.skippable = true
MassiveGod.skipTo = "finalReveal"
MassiveGod.bannerText = "MASSIVE GOD"

return MassiveGod
```

The `Massive.handlers.bonk` fly-out reads `beatT0(run, "ripple")` = 0.40 here, which is the intended faster approach.

- [ ] **Step 3: Verify.** `checkBeats("MassiveGod", 11.9, 12.1)` empty; `matrix("Takeover", "MassiveGod")` 4 `OK` (skip lands on `finalReveal` with the creature visible at full scale at the water, the beam fading). Real throw: `ForceNextSize = "Massive"` AND `ForceNextCatch = "Secret Pete"` at 1x, owner watching, against §6.6 — it must read as one story: beast → pause → light → beam from the beast → choir → ascends and vanishes → emptiness → descends enormous → flash/shockwave/"MASSIVE GOD" → calm. Revert by Uid.

- [ ] **Step 4: Mirror + commit.** Mirror `Cuts/MassiveGod.lua`, `BeamFX.lua`.

```bash
git add game-src/place-full
git commit -m "feat(reveal): MassiveGod — one cohesive cut composing Massive emergence and God heaven"
```

---

### Task 9: Ice fishing — broadcast at hook-set, result fields, cast-input lock

**Files:**
- Modify: `ServerScriptService.Modules.IceFishingEvent` (Studio-only; not mirrored — mirror it for the first time this task)
- Modify: `ReplicatedStorage.Modules.IceFishingConfig` only if the client result remote name is defined there
- Modify: the fishing client script that starts a cast (name confirmed by `script_grep` — see Step 1)
- Modify: `RevealRouter` (remote name), `CinematicClient` (no change expected)

**Interfaces:**
- Consumes: `Config.CUT_FOR`, `Remotes.CatchCinematic`, `RevealRouter.fromFish` (expects `result.Catch = {Name, Rarity, CashPerSecond, Mutation, Size}` plus `RarityColor`, `Serial`, `Exists`, `IsNew`, `Anchor`).
- Produces: the fishing broadcast (same shape as the throw's, no rock fields, `TotalTime = 0`) and the enriched fishing result.

- [ ] **Step 1: Recon in Studio (read-only).** `script_grep` `IceFishingEvent` for: `RollCatch(`, `table.insert(liveData.Brainrots`, `__noSave`, `FireClient`, `Catch = {`, `hole`, `Hole`, `SurfaceY`, `Position`. Record: (a) the local name of the per-player state table (the report calls it `st`) and the field holding the hole part or its position; (b) the client result remote's name and where it fires; (c) the name of the LocalScript that handles the cast input (`script_grep` the place for the remote that starts a cast, then its client sender). Write these three facts into the task report before editing.

- [ ] **Step 2: Broadcast at hook-set.** Backup. In the LANDED-IT branch, immediately AFTER the `Cfg.RollCatch(...)` result is known and the Mutation/Size are rolled (i.e. after the size roll, BEFORE the `__noSave` guard and the insert), insert — using the state-table and hole names from Step 1:

```lua
		-- REVEAL BROADCAST (spec S5.5): the same CatchCinematic payload a throw sends at
		-- flight start, fired at hook-set so nearby players see the world FX and the
		-- catcher's client can stage the cut at the hole. No rock, no flight: TotalTime 0
		-- means the client plays it on receipt. The grant below is unaffected.
		do
			local CinematicConfig = require(ReplicatedStorage.Modules.CatchCinematic.Config)
			local cutName = CinematicConfig.CUT_FOR(caught.Rarity, caught.Size)
			local remote = ReplicatedStorage.Remotes:FindFirstChild("CatchCinematic")
			if cutName and remote then
				local holePos = <hole surface point from Step 1>  -- Vector3 on the ice surface
				local tierColor = <RarityColor for caught.Rarity: RarityConfig lookup by Name>
				remote:FireAllClients({
					UserId = player.UserId,
					BrainrotName = caught.Name,
					Rarity = caught.Rarity,
					RarityColor = tierColor,
					Mutation = caught.Mutation,
					Size = caught.Size,
					Cut = cutName,
					Seed = math.random(1, 2 ^ 30),
					EndPos = holePos, SurfaceY = holePos.Y,
					TotalTime = 0, NContacts = 0, SegTime = 0,
				})
			end
		end
```

(`caught` is whatever the branch names the entry it inserts; use that name.) `RarityColor`: `for _, t in ipairs(require(ReplicatedStorage.Modules.RarityConfig)) do if t.Name == caught.Rarity then tierColor = t.Color end end` — hoist the require to the module top.

- [ ] **Step 3: Enrich the fishing result.** In the same branch's `FireClient` payload add `IsNew = not wasDiscovered` (compute `local wasDiscovered = liveData.Discovered ~= nil and liveData.Discovered[caught.Name] == true` BEFORE the insert), `Anchor = holePos`, `RarityColor = tierColor`, and `Serial`/`Exists` if the fishing path mints (if it does not, leave them nil — the pop omits the line). Confirm the remote name matches `RevealRouter`'s `remotes:FindFirstChild("IceFishingResult")`; if the real name differs, change the router's string to the real name (one edit) rather than renaming the remote. Compile-check; local-declaration diff vs backup: only `wasDiscovered`, `tierColor`, `holePos`, `cutName`, `remote` added inside the branch.

- [ ] **Step 4: Cast-input lock.** In the client cast script from Step 1, at the top of the function that sends the cast, add:

```lua
	if player:GetAttribute("RevealActive") == true then return end -- a takeover cut is playing (spec S11)
```

- [ ] **Step 5: Verify.** Play mode in the Tundra at an ice hole (Studio foregrounded): force a Mythic fish (`IceFishingConfig`/`IceFishingEvent` test hook if one exists — else temporarily set the bite table to Mythic for one cast, restore after) — the Mythic cut plays at the hole with no rock, spectators (a second Studio client via Test → Clients and Servers, 2 players) see the world FX; the pop for a Common fish shows "NEW BRAINROT!" on the first catch of a name. Cancel path: cast with `__debugNoBridge`-free real bite and confirm normal completion. Casting during a cut is refused. Revert all grants by Uid.

- [ ] **Step 6: Mirror + commit.** Mirror `IceFishingEvent.lua` (new mirror file), the cast client script, `RevealRouter.client.lua`.

```bash
git add game-src/place-full
git commit -m "feat(reveal): ice fishing broadcasts CatchCinematic at hook-set, result carries IsNew/Anchor; cast input locked during cuts"
```

---

### Task 10: Whole-system verification, docs, mirror sync

**Files:**
- Modify: `game-src/README.md`
- Modify: `docs/superpowers/specs/2026-09-17-reward-reveal-design.md` only to record deviations discovered during the build (append a "Build notes" section; never rewrite decisions)

- [ ] **Step 1: Router matrix live.** `Harness.routingMatrix()` empty. Then the live check: for each of the six cuts, `Registry.get(name)` non-nil and `checkBeats` empty with the §6 bounds (Mythic 1.6–1.8, Secret 2.9–3.1, God 4.9–5.1, Huge 4.0–5.0, Massive 10.0–11.0, MassiveGod 11.9–12.1).

- [ ] **Step 2: Leak audit, all cuts × all modes** at timescale 4:

```lua
workspace:SetAttribute("CinematicTimescale", 4)
local H = require(game.ReplicatedStorage.Modules.CatchCinematic.Harness)
for _, n in ipairs({ "Mythic", "Secret", "God", "Huge", "Massive", "MassiveGod" }) do H.matrix("Takeover", n) end
workspace:SetAttribute("CinematicTimescale", nil)
print(table.concat(H.popMatrix(), " | "))
```

Expected: 24 `OK` lines, `popMatrix` empty. Then one death-mode run per skippable cut (`H.run("Takeover", n, "death", { killAfter = 1.0 })`) — `OK` (respawn restores; the kill switch drained the trove).

- [ ] **Step 3: Camera invariants on the real path** (the two ship-blockers from the Massive build, re-checked for six cuts): (a) a real Massive throw, then press throw during the cut → refused; (b) a real Mythic throw at a distance > `TRACK_MIN_DISTANCE` (stone-tracking camera live at landing) → cut plays and the camera returns to the player, `CameraType == Custom` after; (c) hook-set while walking away from the hole → cut plays, camera returns. Console clean throughout.

- [ ] **Step 4: Mutation representation.** One Golden Common pop, one Diamond Epic pop, one Golden Mythic cut, one Angel Secret cut — screenshots via Studio's own capture with Studio foregrounded; the plain equivalents beside them. Each mutated reveal must be visibly different (tint/halo/rim + name) with no separate code path (`script_grep` for `Golden`/`Diamond` under `CatchCinematic` and `CatchPop` → expected: comments only).

- [ ] **Step 5: Visual sign-off** with the owner watching at 1x: every cut once, throw and (for Mythic) fish, each judged against its §6 table and the blueprint's "Identity" line. Record the owner's notes per cut in the task report; any retune is a numbers-only change to that cut's TUNABLES block, re-run `checkBeats` + `matrix` after.

- [ ] **Step 6: Docs.** Append to `game-src/README.md`:

```markdown
## Reward reveal system (2026-09-17, spec docs/superpowers/specs/2026-09-17-reward-reveal-design.md)
- CatchCinematic/Takeover.lua -> the ONE takeover/restore framework (from Sequencer, now deleted).
- CatchCinematic/Cuts/{Massive,Huge,Mythic,Secret,God,MassiveGod}.lua -> one module per cut; Cuts/Shared.lua holds the handoff beat + standard build; Cuts/Registry.lua looks cuts up by name.
- CatchCinematic/{CutKit,BeamFX,AuraFX,Harness}.lua -> helpers, God's beam, Secret/God auras, the Studio-only structural harness.
- Config.CUT_FOR(rarity, size) -> the locked routing table (server + client).
- StarterPlayerScripts/RevealRouter.client.lua -> replaces CatchRevealClient: one path per grant, FIFO, RevealActive lock.
- Modules/CatchPop.lua -> Common..Legendary pops (replaces PullCeremony + CatchReveal bands 1-3; MassiveEmergence retired).
- Remotes.CatchCinematic (was MassiveCinematic). ThrowResult/IceFishingResult carry IsNew.
- Sound slots with TODO in Config.ASSETS are placeholders awaiting owner uploads (godChoir is God-exclusive).
```

- [ ] **Step 7: Final mirror sync + commit + save reminder.** Re-mirror EVERY script touched in Tasks 1–9 (`script_read` each, byte-compare against the mirror, rewrite any that drifted — Team Create editors may have touched neighbours). Then:

```bash
git add -A game-src docs/superpowers/specs/2026-09-17-reward-reveal-design.md game-src/README.md
git commit -m "chore(mirror): full re-sync after the reward reveal build; README + spec build notes"
```

Tell the owner explicitly which scripts are unsaved in Studio (everything from Tasks 1–9 until they publish) and that publishing co-publishes any Team Create work in progress by other editors.

---

## Self-review (done while writing)

**Spec coverage:** §4 routing → Task 3 (`CUT_FOR`, Bridge, harness matrix). §5.1 Takeover → Task 1. §5.2 cut contract → Task 1 (`Types.Cut`, `Registry`), handler-sharing → Tasks 2/5/8. §5.3 router/FIFO/lock/gamepass → Task 3 (+ Task 4 pops). §5.4/§7/§9 pops + mutation tint → Task 4. §5.5 server/remote/IsNew → Task 3; fishing → Task 9. §5.6 helpers → Tasks 5 (`shockRing`), 6 (`glowBelow`, `AuraFX`), 7 (`BeamFX`, `tint`, `setDescent`). §6.1–6.6 → Tasks 5, 6, 7, 2, 2, 8. §8 retirements → Tasks 2 (comedy), 4 (modules). §10 copy/audio → Tasks 3 (IsNew), 4 (header), 2/5/6/7 (slots; `godChoir` exclusivity grep in 7). §11 queue/lock/skip → Tasks 1 (skip per cut), 3 (FIFO, lock). §12 failure → inherited framework paths, exercised by every `matrix` run; `onCancel` for cut-specific rigs in 6/7/8. §13 verification → Task 10 plus per-task steps. §14 build order → task order.

**Deviation from the spec worth recording:** the spec's `BrainrotRig:descend(from, to, seconds, yawPerSec)` is implemented as the pure-in-alpha `setDescent(alpha, fromHeight)` to match `setRise`'s house style (hand-lerp, reversible for the ascension). Task 10 Step 6's "Build notes" records this.

**Type consistency:** `Takeover.play(cut, payload, opts)` — Tasks 1, 3, Harness. `Registry.get(name)` — Tasks 1, 3, Harness. `Shared.handoff`/`Shared.build(run, defaultSize)`/`Shared.rimHighlight(run, color)`/`Shared.faceCamera(run)`/`Shared.everyFrameRock` — Tasks 5–8. `WaterFX:shockRing(color, maxRadius, life)` — Tasks 5, 7, 8; `glowBelow(color, seconds)` — 6, 7, 8; `godrays(pos, height, color?)` — 5, 6, 7. `BeamFX.new(stage, basePos, color, height, radius, quality)`, `:fire/:fade/:setBase/:setAlpha/:cleanup` — 7, 8. `AuraFX.new(stage, pos, color, radius, quality, rng)`, `:update(t, alpha?)/:setPos/:fade/:cleanup` — 6, 7, 8. `PostFX:tint/:sunRays` — 7, 8. `BrainrotRig:setDescent(alpha, fromHeight)` — 7, 8. Run fields `heroEye/heroFocus/farEye/farFocus/skyEye/skyFocus/beam/beamBase/aura/descentHeight/travelEye/eyesApplied` — consistent across 2, 5, 6, 7, 8. Sound slots: `finalSkip, massiveRumble, massiveRoar, bannerHit, mythicBass, secretHum, secretLaunch, godRumble, beamRise, godChoir, goldShockwave, bassDrop, waterExplosion, cardWhoosh` — every slot a handler plays is declared in a task before it is used.
