# Onboarding — First 10 Minutes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the fresh-player first session of Skip Rocks for Brainrots so a new player skips within 30 s, sees no popup wall, never hits an unaffordable tutorial step, and knows their next target by minute 10.

**Architecture:** Roblox Studio is the runtime and source of truth; `game-src/place-full/` is the byte-exact mirror committed to git. Every code task edits the mirror file on disk (LF endings), loads it into the matching Studio script through a local HTTP bridge, compile-checks it, and — after the Play verification — pushes the live `Source` back over the mirror so the two are byte-identical. Server-side changes are small (auto-claim, goal progress, price, test seam); the bulk is a rewrite of `TutorialClient` plus a hold in `GameHUDClient`'s join sequence.

**Tech Stack:** Luau (Roblox), Roblox Studio via the `roblox-studio` MCP (`execute_luau`, `script_read`, `multi_edit`, `start_stop_play`, `get_console_output`), `tools/studio-bridge/bridge.py` (Python, local HTTP), git.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-09-21-onboarding-first-10-min-design.md`. Inspection: `docs/onboarding/PHASE1-INSPECTION.md`.
- Do not touch: Trading World, World 1 environment, egg hatch / catch reveal presentation (`CatchPop`, `RevealRouter`), DataStore/save architecture beyond the Studio-only key suffix, brainrot models, the wider economy.
- Economy values that change: `RockConfig` `SmoothStone.Price` 12000 → 2000. Nothing else. `TUTORIAL_REWARD` stays 3000.
- Currency word in player-facing copy is **cash** (`$`) for coins and **Gems** for the premium currency; never "darrels"/"emeralds" in UI text.
- Mirror files are LF-only (`.gitattributes` marks `*.lua -text`). Never `git add -A` (the tree carries other sessions' work); add files by name.
- Never call `PlayerDataManager.Load` by hand in Studio; never Play/Stop faster than ~100 s on the same profile key (SessionLock 90 s stale window) — use a fresh `ProfileKeySuffix` per fresh-profile run instead.
- Studio is shared with other sessions: check `get_studio_state` before any Studio action; never stop a Play session you did not start.
- Backups before editing any live script: `ServerStorage.AuditBackups.PreOnboarding_2026_09_21.<ScriptName>_pre` (ModuleScript stub, `Source` copied).
- Every Studio script edit must end with the mirror file updated from the live `Source` (bridge `/save`) and `_MANIFEST.txt` line regenerated (`h31` hash: `h = (h*31 + byte) mod 2^32`, seed 5381, 8 hex digits).

---

## File structure

| file (mirror path under `game-src/place-full/`) | responsibility in this plan |
|---|---|
| `ServerScriptService/Modules/SessionLock.lua` | Task 1: Studio-only `ProfileKeySuffix` on the DataStore key |
| `ReplicatedStorage/Modules/RockConfig.lua` | Task 2: Rivertumble $2,000 + dated note |
| `ServerScriptService/Modules/QuestHandler.lua` | Task 3: tier goals report binary progress |
| `ServerScriptService/Modules/PlayerDataManager.lua` | Task 4: `ClaimPlotFor(player, plot, quiet)` |
| `ServerScriptService/Main.server.lua` | Task 4: auto-claim a valley base for fresh profiles; comment fix |
| `StarterPlayer/StarterPlayerScripts/MerchantClient.client.lua` | Task 5: rock card reach line |
| `StarterPlayer/StarterPlayerScripts/GameHUDClient.client.lua` | Task 6: hold the calendar while onboarding |
| `StarterPlayer/StarterPlayerScripts/TutorialClient.client.lua` | Task 7: the new ladder (rewrite) |
| `StarterPlayer/StarterPlayerScripts/QuestBarClient.client.lua` | Task 8: READY! bar opens Goals (from LIVE source) |
| `tools/studio-bridge/bridge.py` (unchanged) + scratchpad `bridge2.py` | Task 0: local bridge on port 8732 serving the worktree |
| `docs/onboarding/*` | Task 11: test log + final report |

---

## Task 0: Tooling — bridge, backups folder, compile-check recipe

**Files:**
- Create (scratchpad only, not committed): `<scratchpad>/bridge2.py`
- Studio: `ServerStorage.AuditBackups.PreOnboarding_2026_09_21` (Folder)

**Interfaces:**
- Produces: `http://127.0.0.1:8732/game-src/place-full/<path>` (GET a worktree file), `POST /save?path=<abs path under worktree/game-src>` (write bytes verbatim); the Luau snippets `LOAD(path)`, `PUSH(inst, absPath)`, `COMPILE(src)` used by every later task.

- [ ] **Step 1: Write the worktree bridge (port 8732, serves the worktree root)**

`<scratchpad>/bridge2.py`:

```python
"""Worktree bridge: GET /<path under worktree>, POST /save?path=<abs path under worktree/game-src>."""
import os, sys, hashlib
from http.server import SimpleHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

ROOT = r"C:\Users\m\Coding\skip-a-brainrot\.claude\worktrees\onboarding-first-10-min-b8f4dc"
ALLOWED = [os.path.join(ROOT, "game-src")]
PORT = 8732

class H(SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write("%s\n" % (fmt % args))
    def do_POST(self):
        u = urlparse(self.path)
        if u.path != "/save":
            self.send_response(404); self.end_headers(); return
        path = os.path.abspath(parse_qs(u.query).get("path", [""])[0])
        if not any(path.startswith(r + os.sep) for r in ALLOWED):
            self.send_response(403); self.end_headers(); self.wfile.write(b"path not allowed"); return
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(body)
        out = ("saved %d bytes sha1=%s" % (len(body), hashlib.sha1(body).hexdigest())).encode()
        self.send_response(200); self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(out))); self.end_headers(); self.wfile.write(out)

if __name__ == "__main__":
    os.chdir(ROOT)
    print("worktree bridge on http://127.0.0.1:%d serving %s" % (PORT, ROOT))
    HTTPServer(("127.0.0.1", PORT), H).serve_forever()
```

- [ ] **Step 2: Start it in the background and verify**

Run (Bash, background): `python "<scratchpad>/bridge2.py"`
Then: `curl -s http://127.0.0.1:8732/game-src/place-full/ReplicatedStorage/Modules/RockConfig.lua | head -3`
Expected: the first three lines of RockConfig.

- [ ] **Step 3: The three Luau recipes (Edit-mode `execute_luau`)**

`LOAD` — pull a mirror file into a live script (HttpEnabled flipped for the call only; the place ships with it OFF):

```lua
local HS = game:GetService("HttpService")
local SES = game:GetService("ScriptEditorService")
local function load(instPath, relPath)
	local inst = game
	for seg in instPath:gmatch("[^%.]+") do inst = inst[seg] end
	local was = HS.HttpEnabled; HS.HttpEnabled = true
	local ok, src = pcall(HS.GetAsync, HS, "http://127.0.0.1:8732/game-src/place-full/" .. relPath)
	HS.HttpEnabled = was
	assert(ok, src)
	src = src:gsub("\r\n", "\n")
	if #src < 190000 then inst.Source = src else SES:UpdateSourceAsync(inst, function() return src end) end
	return #src
end
return load("StarterPlayer.StarterPlayerScripts.TutorialClient", "StarterPlayer/StarterPlayerScripts/TutorialClient.client.lua")
```

`PUSH` — mirror a live script's Source back to disk byte-exact:

```lua
local HS = game:GetService("HttpService")
local function push(instPath, absPath)
	local inst = game
	for seg in instPath:gmatch("[^%.]+") do inst = inst[seg] end
	local was = HS.HttpEnabled; HS.HttpEnabled = true
	local ok, res = pcall(HS.PostAsync, HS, "http://127.0.0.1:8732/save?path=" .. HS:UrlEncode(absPath), inst.Source, Enum.HttpContentType.TextPlain, false)
	HS.HttpEnabled = was
	return ok and res or ("ERR " .. tostring(res))
end
return push("StarterPlayer.StarterPlayerScripts.TutorialClient", [[C:\Users\m\Coding\skip-a-brainrot\.claude\worktrees\onboarding-first-10-min-b8f4dc\game-src\place-full\StarterPlayer\StarterPlayerScripts\TutorialClient.client.lua]])
```

`COMPILE` — syntax-check a source without running it (temp ModuleScript wrapped in a never-called function; nothing executes, no requires fire):

```lua
local src = game.StarterPlayer.StarterPlayerScripts.TutorialClient.Source
local m = Instance.new("ModuleScript")
m.Name = "__compileCheck"
m.Source = "local function __neverCalled()\n" .. src .. "\nend\nreturn true"
m.Parent = game:GetService("ServerStorage")
local ok, err = pcall(require, m)
m:Destroy()
return ok and "COMPILES" or ("SYNTAX ERROR: " .. tostring(err))
```

- [ ] **Step 4: Create the backups folder + a stub per script this plan edits** (use `multi_edit` with `className = "ModuleScript"` and an empty-`old_string` first edit to create each stub, then copy the live Source in one exec):

```lua
local SS = game:GetService("ServerStorage")
local folder = SS.AuditBackups.PreOnboarding_2026_09_21
local map = {
	SessionLock_pre = game.ServerScriptService.Modules.SessionLock,
	RockConfig_pre = game.ReplicatedStorage.Modules.RockConfig,
	QuestHandler_pre = game.ServerScriptService.Modules.QuestHandler,
	PlayerDataManager_pre = game.ServerScriptService.Modules.PlayerDataManager,
	Main_pre = game.ServerScriptService.Main,
	MerchantClient_pre = game.StarterPlayer.StarterPlayerScripts.MerchantClient,
	GameHUDClient_pre = game.StarterPlayer.StarterPlayerScripts.GameHUDClient,
	TutorialClient_pre = game.StarterPlayer.StarterPlayerScripts.TutorialClient,
	QuestBarClient_pre = game.StarterPlayer.StarterPlayerScripts.QuestBarClient,
}
local out = {}
for name, live in pairs(map) do
	local stub = folder:FindFirstChild(name)
	if stub then stub.Source = live.Source; out[#out+1] = name .. "=" .. #stub.Source end
end
return table.concat(out, "\n")
```

Expected: nine `name=bytes` lines matching the live `#Source` values from the inspection (TutorialClient 30021, GameHUDClient 145732, MerchantClient 39111, QuestBarClient 20374, Main 12193, QuestHandler 13948, PlayerDataManager 51669, RockConfig 7924, SessionLock — read it).

---

## Task 1: Studio-only profile-key suffix (test seam)

**Files:**
- Modify: `game-src/place-full/ServerScriptService/Modules/SessionLock.lua:16-36` (services + `key()`)

**Interfaces:**
- Consumes: `ServerStorage` attribute `ProfileKeySuffix` (string, Studio only).
- Produces: every SessionLock DataStore access (`Claim`, `Save`, `Release`, heartbeat) keyed `Player_<uid><suffix>` in Studio when the attribute is a non-empty string; unchanged otherwise and always unchanged on live servers.

- [ ] **Step 1: Edit the mirror file**

Replace

```lua
local DataStoreService = game:GetService("DataStoreService")
```

with

```lua
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
```

and replace

```lua
local function key(userId) return KEY_PREFIX .. userId end
```

with

```lua
-- STUDIO-ONLY TEST SEAM (2026-09-21, onboarding round). A Studio playtest always
-- loads the Studio account's REAL profile, so a truly fresh profile -- and a
-- rejoin against it -- could not be tested without touching the real save. In
-- Studio only, a non-empty string in the ServerStorage attribute
-- `ProfileKeySuffix` is appended to the key (`Player_<uid>_qa1`), which is a
-- separate row in the same store: fresh when it does not exist, persistent
-- across Play sessions, and never the owner's real row. Live servers never read
-- the attribute (IsStudio() is false there), and an empty/absent attribute is
-- the unchanged key. CLEAR THE ATTRIBUTE (set it to nil) when a test session is
-- over: it lives in the place file, and a leftover suffix would quietly load the
-- wrong profile in the owner's next playtest.
local function keySuffix()
	if not RunService:IsStudio() then return "" end
	local s = ServerStorage:GetAttribute("ProfileKeySuffix")
	return (type(s) == "string") and s or ""
end
local function key(userId) return KEY_PREFIX .. userId .. keySuffix() end
```

- [ ] **Step 2: Load into Studio + compile-check**

Run `LOAD("ServerScriptService.Modules.SessionLock", "ServerScriptService/Modules/SessionLock.lua")` then `COMPILE` on that script. Expected: `COMPILES`.

- [ ] **Step 3: Verify the seam in a Play session**

Edit mode: `game:GetService("ServerStorage"):SetAttribute("ProfileKeySuffix", "_qa0")`. `start_stop_play(true)`, wait 15 s, Server exec:

```lua
local ls = game.Players:GetPlayers()[1]:FindFirstChild("leaderstats")
return ("cash=%s rebirths=%s"):format(ls and ls.Cash.Value, ls and ls.Rebirths.Value)
```

Expected: `cash=0 rebirths=0` (a fresh profile, not the owner's). Stop. Edit exec:

```lua
local ds = game:GetService("DataStoreService"):GetDataStore("BrainrotSkip_PlayerData_v1")
local row = ds:GetAsync("Player_478963763_qa0")
return row and ("row exists; Cash=" .. tostring(row.Cash) .. " TutorialDone=" .. tostring(row.TutorialDone)) or "no row"
```

Expected: `row exists; Cash=0 TutorialDone=false`. Then `ServerStorage:SetAttribute("ProfileKeySuffix", nil)`.

- [ ] **Step 4: Push + manifest + commit**

`PUSH` SessionLock to its mirror path; regenerate its `_MANIFEST.txt` line (Task 9 script); commit:

```bash
git add game-src/place-full/ServerScriptService/Modules/SessionLock.lua game-src/place-full/_MANIFEST.txt
git commit -m "test(profile): Studio-only ProfileKeySuffix seam on the DataStore key"
```

---

## Task 2: Rivertumble → $2,000

**Files:**
- Modify: `game-src/place-full/ReplicatedStorage/Modules/RockConfig.lua` (SmoothStone row + header note)

- [ ] **Step 1: Edit the mirror file**

Replace the row

```lua
	{ Id = "SmoothStone", Name = "Rivertumble",       Price = 12000,        MaxDistance = 70,  Luck = 1.15, Color = Color3.fromRGB(160, 160, 170) },
```

with

```lua
	-- FIRST RUNG REPRICED 12,000 -> 2,000 (owner, 2026-09-21, first-10-minutes round).
	-- The header's own intent is "a brand-new player still gets their first
	-- purchase quickly"; at 12,000 the tutorial's rock step was ~10x what a fresh
	-- profile holds and "Skip This Step" was the only way past. 2,000 is the own5
	-- goal reward (2,400) minus a little: earned by five catches, bought at ~4 min.
	-- Still 100% Common (70 studs < the 100-stud Uncommon band): what it sells is
	-- 3x the reach, 4 skips and the tracking camera. Sevenskip (23,900) stays the
	-- first tier unlock and is the post-tutorial target the finish card names.
	{ Id = "SmoothStone", Name = "Rivertumble",       Price = 2000,         MaxDistance = 70,  Luck = 1.15, Color = Color3.fromRGB(160, 160, 170) },
```

- [ ] **Step 2: Load, compile-check, verify the value**

`LOAD("ReplicatedStorage.Modules.RockConfig", "ReplicatedStorage/Modules/RockConfig.lua")`, `COMPILE`, then Edit exec:

```lua
local m = game.ReplicatedStorage.Modules.RockConfig:Clone(); m.Parent = game.ServerStorage
local rocks = require(m); m:Destroy()
return rocks[2].Id .. "=" .. rocks[2].Price
```

Expected: `SmoothStone=2000`.

- [ ] **Step 3: Push + manifest + commit**

```bash
git add game-src/place-full/ReplicatedStorage/Modules/RockConfig.lua game-src/place-full/_MANIFEST.txt
git commit -m "balance(onboarding): Rivertumble 12,000 -> 2,000 so the first rock is earned in the first minutes"
```

---

## Task 3: Tier goals report binary progress

**Files:**
- Modify: `game-src/place-full/ServerScriptService/Modules/QuestHandler.lua` (after the `QUESTS` table, before the state builder)

**Interfaces:**
- Produces: `QuestState` rows for `uncommon/rare/epic/legendary/mythic/secret/god` carry `Cur = 0` until `Met`, then `Cur = Target`. `Met`, `Claimed`, `Reward`, `Id` unchanged. `QuestBarClient.pick` therefore leads with `own5` after the first catch.

- [ ] **Step 1: Edit the mirror file**

Directly after the closing `}` of `local QUESTS = { ... }` insert:

```lua

-- TIER GOALS ARE ALL-OR-NOTHING (2026-09-21, first-10-minutes round). `cur =
-- bestRarity` reported a single Common as "1 of 2" toward "Catch an Uncommon+",
-- so QuestBarClient's nearest-to-complete pick led every fresh player with a goal
-- they cannot reach on Pebble (100% Common under 100 studs; 4% Uncommon on the
-- $23,900 rock) -- ahead of "Own 5 brainrots", which five throws finish. A tier
-- is not half-caught: report 0 until it is met, then the full target. `met` is
-- untouched, so nothing about what pays out changes.
for _, q in ipairs(QUESTS) do
	if q.cur == bestRarity then
		local target = q.target
		q.cur = function(d) return bestRarity(d) >= target and target or 0 end
	end
end
```

- [ ] **Step 2: Load, compile-check, verify**

`LOAD("ServerScriptService.Modules.QuestHandler", "ServerScriptService/Modules/QuestHandler.lua")`, `COMPILE`. Behavioural check happens in Task 10 (fresh join: Goals bar shows `Own 5 brainrots` after the first catch).

- [ ] **Step 3: Push + manifest + commit**

```bash
git add game-src/place-full/ServerScriptService/Modules/QuestHandler.lua game-src/place-full/_MANIFEST.txt
git commit -m "fix(goals): tier goals report 0 until met so a fresh player's lead goal is reachable"
```

---

## Task 4: Auto-claim a valley base at first join

**Files:**
- Modify: `game-src/place-full/ServerScriptService/Modules/PlayerDataManager.lua:1029-1046` (`ClaimPlotFor`)
- Modify: `game-src/place-full/ServerScriptService/Main.server.lua` (PlayerAdded, the already-in-game loop, the `TUTORIAL_REWARD` comment)

**Interfaces:**
- Produces: `PlayerDataManager.ClaimPlotFor(player, plot, quiet: boolean?)` — `quiet == true` suppresses the "Base claimed!" toast only. `Main.autoClaimFirstBase(player)` (local).

- [ ] **Step 1: `ClaimPlotFor` quiet flag**

Replace

```lua
function PlayerDataManager.ClaimPlotFor(player, plot)
	if not plot or plot:GetAttribute("Claimed") then return false end
```

with

```lua
-- `quiet` (2026-09-21): the first-join auto-claim in Main passes true so the
-- "Base claimed!" toast does not fire over the tutorial's first card, which says
-- the same thing in its own words. Every other caller omits it and is unchanged.
function PlayerDataManager.ClaimPlotFor(player, plot, quiet)
	if not plot or plot:GetAttribute("Claimed") then return false end
```

and replace

```lua
	local result = ReplicatedStorage.Remotes:FindFirstChild("PurchaseResult")
	if result then
		result:FireClient(player, { Success = true, Message = "Base claimed!" })
	end
	return true
end
```

with

```lua
	local result = (not quiet) and ReplicatedStorage.Remotes:FindFirstChild("PurchaseResult")
	if result then
		result:FireClient(player, { Success = true, Message = "Base claimed!" })
	end
	return true
end
```

- [ ] **Step 2: `Main` auto-claim**

Insert directly above `Players.PlayerAdded:Connect(function(player)`:

```lua
-- FIRST-JOIN BASE (owner, 2026-09-21, first-10-minutes round). A throw is refused
-- until the player owns a plot, so a brand-new player used to walk to a camp
-- BEFORE the game could show them its one core action. For a profile that has
-- not finished the tutorial and owns no valley camp on this server, claim the
-- free valley plot nearest the spawn the moment the profile lands -- no
-- teleport, no toast (the tutorial's first card names it). Returning players
-- keep walk-to-claim exactly as before; a full server simply claims nothing and
-- the tutorial falls back to its CLAIM A BASE step.
local function autoClaimFirstBase(player)
	local data = PlayerDataManager.Get(player)
	if not data or data.TutorialDone then return end
	if PlayerDataManager.GetPlot(player, "Valley") then return end
	local bases = workspace:FindFirstChild("PlayerBases")
	if not bases then return end
	local spawn = workspace:FindFirstChildOfClass("SpawnLocation", true)
	local origin = spawn and spawn.Position or Vector3.zero
	local best, bestD
	for _, plot in ipairs(bases:GetChildren()) do
		if plot:IsA("Model") and not plot:GetAttribute("Claimed") and plot:GetAttribute("World") == "Valley" then
			local d = (plot:GetPivot().Position - origin).Magnitude
			if not bestD or d < bestD then best, bestD = plot, d end
		end
	end
	if best then PlayerDataManager.ClaimPlotFor(player, best, true) end
end

```

Replace

```lua
Players.PlayerAdded:Connect(function(player)
	PlayerDataManager.Load(player)
	PlayerDataManager.PushUpdate(player)
	OfflineEarningsHandler.OnJoin(player)
end)
```

with

```lua
Players.PlayerAdded:Connect(function(player)
	PlayerDataManager.Load(player)
	PlayerDataManager.PushUpdate(player)
	OfflineEarningsHandler.OnJoin(player)
	autoClaimFirstBase(player)
end)
```

and the tail loop

```lua
	if not PlayerDataManager.Get(player) then
		PlayerDataManager.Load(player)
		PlayerDataManager.PushUpdate(player)
		OfflineEarningsHandler.OnJoin(player)
	end
```

with

```lua
	if not PlayerDataManager.Get(player) then
		PlayerDataManager.Load(player)
		PlayerDataManager.PushUpdate(player)
		OfflineEarningsHandler.OnJoin(player)
		autoClaimFirstBase(player)
	end
```

Replace the stale sentence in the `TUTORIAL_REWARD` comment

```lua
-- ladder just showed them. For reference the cheapest paid rock is 300, and a
-- freshly-placed Common earns 0.9/s. Drop this to 300 if the grant should only
-- cover a rock rather than an upgrade.
```

with

```lua
-- ladder just showed them. For reference the cheapest paid rock is 2,000
-- (Rivertumble, repriced 2026-09-21 -- the tutorial's BUY A BETTER ROCK step
-- expects it bought BEFORE this grant, out of the own5 goal reward), and a
-- freshly-placed Common earns ~1.3/s.
```

- [ ] **Step 3: Load both, compile-check both**

`LOAD` PlayerDataManager and Main; `COMPILE` each. Expected: `COMPILES` ×2.

- [ ] **Step 4: Verify in a fresh-profile Play session**

`ServerStorage:SetAttribute("ProfileKeySuffix", "_qa1")`, Play, wait 8 s, Server exec:

```lua
local p = game.Players:GetPlayers()[1]
local out = {}
for _, plot in ipairs(workspace.PlayerBases:GetChildren()) do
	if plot:GetAttribute("OwnerUserId") == p.UserId then out[#out+1] = plot.Name .. " " .. tostring(plot:GetAttribute("World")) end
end
return #out > 0 and table.concat(out, ",") or "NO PLOT"
```

Expected: one valley plot (`Plot3` or `Plot4`). Client exec: `return #game.Players.LocalPlayer.PlayerGui.ToastGui:GetChildren()` — no "Base claimed!" toast line present (0 toast children, or none whose Text contains "Base claimed"). Stop. Do NOT clear the suffix yet if the next task's test reuses `_qa1` after ≥100 s; otherwise set it to nil.

- [ ] **Step 5: Regression: a returning profile does not auto-claim**

With the suffix cleared (real profile, TutorialDone true), Play, wait 8 s, run the same Server exec. Expected: `NO PLOT` until the player walks onto one (unchanged behaviour). Stop.

- [ ] **Step 6: Push + manifest + commit**

```bash
git add game-src/place-full/ServerScriptService/Modules/PlayerDataManager.lua game-src/place-full/ServerScriptService/Main.server.lua game-src/place-full/_MANIFEST.txt
git commit -m "feat(onboarding): auto-claim the nearest valley base for a first-join profile"
```

---

## Task 5: Rock shop cards say what a rock reaches

**Files:**
- Modify: `game-src/place-full/StarterPlayer/StarterPlayerScripts/MerchantClient.client.lua` (`INFO_H`, the rock branch of `rebuild`, a new `reachLine` helper above `makeCard`)

**Interfaces:**
- Consumes: `WorldProgression.Resolve(world).Rarities` (per-world ladder, `MinDistance`/`MaxDistance`), `currentWorld` (already tracked by `openMerchant`).
- Produces: rock card info text on two lines: `Skips up to 70m  •  1.15x luck` / `Catches COMMON  •  Uncommon from 100m`.

- [ ] **Step 1: Grow the info band**

Replace

```lua
local ART_H, NAME_H, INFO_H, BTN_H = 118, 26, 34, 46
```

with

```lua
-- INFO_H 34 -> 50 (2026-09-21): rock cards now carry a second line saying what
-- the rock reaches. The band sits at 158..208 against the button's top at 213, so
-- the card height and the grid are untouched; upgrade cards top-align their one
-- line in the same band as before.
local ART_H, NAME_H, INFO_H, BTN_H = 118, 26, 50, 46
```

- [ ] **Step 2: The reach line**

Insert directly above `local function makeCard(`:

```lua
-- WHAT A ROCK IS FOR, in the player's terms (2026-09-21, first-10-minutes round).
-- "Up to 70m . 1.15x luck" told a new player nothing they could act on. The
-- ladder's own header says reach only matters where it crosses a RarityConfig
-- band edge, so say exactly that: the highest tier this rock's own reach covers
-- and the next band edge. Rebirth/upgrade/pet power multiply on top, so a rock
-- "5 short" of a band can still cross it -- this is the honest floor, not a cap.
-- The apex tier (infinite band) is quest-only and never named here.
local function reachLine(rock, worldName)
	local ladder = WorldProgression.Resolve(worldName).Rarities
	local reach, nextTier
	for i, t in ipairs(ladder) do
		if t.MaxDistance ~= math.huge and rock.MaxDistance >= t.MinDistance then
			reach, nextTier = t, ladder[i + 1]
		end
	end
	if not reach then return nil end
	local s = ("Catches %s"):format(string.upper(reach.Name))
	if nextTier and nextTier.MaxDistance ~= math.huge then
		s ..= ("  \u{2022}  %s from %dm"):format(nextTier.Name, nextTier.MinDistance)
	end
	return s
end

```

- [ ] **Step 3: Use it in the rock branch**

Replace

```lua
				local desc = ("Up to %dm  \u{2022}  %.2fx luck"):format(rock.MaxDistance, rock.Luck)
```

with

```lua
				local desc = ("Skips up to %dm  \u{2022}  %.2fx luck"):format(rock.MaxDistance, rock.Luck)
				local reach = reachLine(rock, currentWorld)
				if reach then desc ..= "\n" .. reach end
```

(`makeCard` joins `statLine` with a bullet; rocks pass `nil` there already, so the newline inside `desc` is what makes the second line.)

- [ ] **Step 4: Load, compile-check, look at it**

`LOAD` + `COMPILE`. Play (any profile), walk to Rocco (`character_navigation` to `(24, 8, -290)` then `Humanoid:MoveTo` into the prompt range; trigger `ShopPrompt` via `InputHoldBegin/End` from the Client exec as the Studio memory describes), Client exec:

```lua
local pg = game.Players.LocalPlayer.PlayerGui
local out = {}
for _, d in ipairs(pg.MerchantShopUI:GetDescendants()) do
	if d:IsA("TextLabel") and d.Name == "Info" then out[#out+1] = d.Text:gsub("\n", " / ") .. " fits=" .. tostring(d.TextFits) end
end
return table.concat(out, "\n")
```

Expected: first three rows read `Skips up to 25m • 1.00x luck / Catches COMMON • Uncommon from 100m`, `Skips up to 70m • 1.15x luck / Catches COMMON • Uncommon from 100m`, `Skips up to 110m • 1.30x luck / Catches UNCOMMON • Rare from 220m`, all `fits=true`. Capture the shop (`tools/studio-bridge/capture-studio.ps1 -Mode print`) into `docs/onboarding/captures/rock-shop-desktop.jpg` (JPEG q90).

- [ ] **Step 5: Push + manifest + commit**

```bash
git add game-src/place-full/StarterPlayer/StarterPlayerScripts/MerchantClient.client.lua game-src/place-full/_MANIFEST.txt docs/onboarding/captures/rock-shop-desktop.jpg
git commit -m "ui(rock-shop): cards say what a rock catches and where the next tier starts"
```

---

## Task 6: Hold the Daily Calendar while onboarding

**Files:**
- Modify: `game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDClient.client.lua` (the join-time `GetInitialData` pull ~line 1373; the join sequence ~lines 2876-2990)

**Interfaces:**
- Consumes: join snapshot `TutorialDone`; player attribute `OnboardingActive` (Task 7 sets true on start, false on finish/skip).
- Produces: `DailyState` join push deferred while `onboardingHold`; identical behaviour for `TutorialDone == true` profiles.

- [ ] **Step 1: Decide the hold from the join snapshot**

Replace

```lua
task.spawn(function()
	local ok, snap = pcall(function() return remotes.GetInitialData:InvokeServer() end)
	if ok and typeof(snap) == "table" then applyCash(snap.Cash) end
end)
```

with

```lua
-- ONBOARDING HOLD (2026-09-21, first-10-minutes round). The calendar's join
-- push (see the join sequence at the foot of this file) waits while a fresh
-- profile is in the tutorial, so the game's first screen is the one core
-- action rather than a modal over it. Decided HERE from the snapshot rather
-- than from TutorialClient's attribute, so the decision cannot lose a race with
-- that script's own start; released by that attribute dropping (finish or
-- skip) or by the ceiling below. `nil` = not decided yet: the DailyState
-- handler parks its payload until this resolves.
local onboardingHold = nil
local ONBOARDING_HOLD_CEILING = 600
local releaseOnboardingHold   -- assigned in the join sequence below
task.spawn(function()
	local ok, snap = pcall(function() return remotes.GetInitialData:InvokeServer() end)
	if ok and typeof(snap) == "table" then
		applyCash(snap.Cash)
		onboardingHold = (snap.TutorialDone == false)
	else
		onboardingHold = false
	end
	if not onboardingHold and releaseOnboardingHold then releaseOnboardingHold() end
end)
```

- [ ] **Step 2: Park the push while held**

In the join sequence, replace

```lua
remotes.DailyState.OnClientEvent:Connect(function(s)
	if typeof(s) ~= "table" then return end
	dailyClaimable = (s.Claimable == true)
	if sequenceOver then return end

	if not introOpened then
```

with

```lua
-- The join push, held while onboardingHold is true or still undecided; the
-- latest payload is kept so the release replays exactly what would have shown.
local heldState = nil
local handleDailyState   -- forward: the body below, so the release can call it

releaseOnboardingHold = function()
	if onboardingHold == true then return end
	local s = heldState
	heldState = nil
	if s then handleDailyState(s) end
end
player:GetAttributeChangedSignal("OnboardingActive"):Connect(function()
	if player:GetAttribute("OnboardingActive") == false and onboardingHold then
		onboardingHold = false
		releaseOnboardingHold()
	end
end)
-- Ceiling: a tutorial that never signals must not cost the day's claim.
task.delay(ONBOARDING_HOLD_CEILING, function()
	if onboardingHold ~= false then
		onboardingHold = false
		releaseOnboardingHold()
	end
end)

remotes.DailyState.OnClientEvent:Connect(function(s)
	if typeof(s) ~= "table" then return end
	dailyClaimable = (s.Claimable == true)
	if sequenceOver then return end
	if not introOpened and onboardingHold ~= false then
		heldState = s
		return
	end
	handleDailyState(s)
end)

handleDailyState = function(s)
	if sequenceOver then return end
	dailyClaimable = (s.Claimable == true)

	if not introOpened then
```

and close the moved body: the handler's original final `end)` (after the `if s.JustClaimed then ... end` block) becomes `end`.

Result shape (for orientation):

```lua
handleDailyState = function(s)
	if sequenceOver then return end
	dailyClaimable = (s.Claimable == true)

	if not introOpened then
		if not dailyClaimable then endSequence() return end
		introOpened = true
		openPanel("daily")
		task.spawn(function() ... end)
		return
	end

	if s.JustClaimed then
		task.delay(CLAIM_HOLD, function()
			if currentPanelId == "daily" then closePanel() end
		end)
	end
end
```

- [ ] **Step 3: Load, compile-check**

`LOAD` GameHUDClient (145 KB: the `LOAD` recipe uses `Source =` under 190 KB), `COMPILE`. Expected `COMPILES`.

- [ ] **Step 4: Verify both paths**

(a) Real profile (suffix nil), Play: calendar opens at join exactly as before (or no panel on a same-day rejoin) — Client exec after 4 s: `return game.Players.LocalPlayer:GetAttribute("HudOpenPanel")` → `daily` when claimable today, else `nil` with `IntroDailyDone == true`.
(b) Fresh profile (`_qa2`), Play: after 6 s `HudOpenPanel` is `nil` and the Goals/Tutorial are visible; then Client exec `game.Players.LocalPlayer:SetAttribute("OnboardingActive", false)` (Task 7 not in yet, so simulate) → within 1 s `HudOpenPanel == "daily"`. Stop.

- [ ] **Step 5: Push + manifest + commit**

```bash
git add game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDClient.client.lua game-src/place-full/_MANIFEST.txt
git commit -m "ui(join): hold the Daily Calendar until a fresh profile finishes or skips the tutorial"
```

---

## Task 7: The new tutorial ladder (`TutorialClient` rewrite)

**Files:**
- Rewrite: `game-src/place-full/StarterPlayer/StarterPlayerScripts/TutorialClient.client.lua`

**Interfaces:**
- Consumes: remotes `GetInitialData`, `DataUpdated`, `StoneThrown`, `ThrowResult`, `CampfireCollected`, `QuestState`, `TutorialComplete`; player attribute `HudOpenPanel` (`"bag"` when the Bag is open); rail tiles `GameHUD → NavRail → bagItem / goalsItem`; `Workspace.GameWorld.ThrowZone`, `GameWorld.ShopStall.PromptPart`, `Workspace.PlayerBases.<Plot>{EquipBestPad, Campfire}`; modules `UITheme`, `SoundKit`, `Platform`, `RarityConfig`, `RockConfig`, `UIKit.Toast`.
- Produces: player attribute `OnboardingActive` (true while the ladder runs, false on finish/skip; never set for done profiles); `TutorialComplete:FireServer(true|false)`.

- [ ] **Step 1: Write the file** (full source; LF endings)

```lua
-- First-join onboarding (rewritten 2026-09-21, "first 10 minutes" round). Shows
-- once ever (TutorialDone saves with player data). ONE card at a time, bottom-left,
-- a beacon + ground chevrons on the current target, and every step gated on a real
-- event or on the profile SNAPSHOT -- never on a timer, never on standing near a
-- thing, and never on something a fresh profile with Pebble cannot do. There is no
-- "Skip This Step" any more: the step that used to need it (a 12,000 rock against
-- ~1,700 in hand) was repriced instead. "Skip Tutorial" ends the whole ladder.
--
-- The ladder, and what each step is FOR:
--   1 SKIP YOUR FIRST ROCK    the core action, first
--   2 IT'S IN YOUR BAG        where a catch goes + distance -> rarity, then repeat x5
--   3 GOAL COMPLETE           the Goals board pays (own5), and the player sees it
--   4 OPEN YOUR BAG           "my brainrots are collected here"
--   5 PUT THEM ON YOUR BASE   the walk-over pad; placed brainrots earn
--   6 COLLECT YOUR CASH       the campfire
--   7 BUY A BETTER ROCK       Rivertumble, 2,000 -- affordable from the goal reward
--   (0 CLAIM A BASE           only when the server could not auto-claim one at join)
--
-- REJOIN RESUMES. Steps read durable facts where they exist (brainrot count, PadIndex,
-- OwnedRocks, TotalEarned, the goal's Claimed flag), so a player who leaves mid-ladder
-- comes back to the first step that is actually open, not to the start.
--
-- CALENDAR HANDSHAKE. The player attribute OnboardingActive is true while this runs
-- and false the moment it ends (finish or skip); GameHUDClient's join sequence holds
-- the Daily Calendar's auto-open on it (and decides the hold from the join snapshot
-- itself, so a late start here cannot lose the race).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("MainUI")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UITheme = require(Modules.UITheme)
local SoundKit = require(Modules.SoundKit)
local Platform = require(Modules.Platform)
local RarityConfig = require(Modules.RarityConfig)
local RockConfig = require(Modules.RockConfig)

local ONBOARDING_ATTR = "OnboardingActive"
local GOAL_ID = "own5"          -- QuestHandler's "Own 5 brainrots" -- the first goal
local GOAL_COUNT = 5

-- The game's panel entrance is a HAND-LERPED glide, not a tween: see
-- GameHUDClient.glidePanel (its openPanel drives every HUD panel through it)
-- and its header note that TweenService entrances on a panel wrapper proved
-- unreliable in this place. glidePanel is a local there, so this is the same
-- pattern inlined, with a local generation counter instead of closeGen.
-- PANEL_OPEN is UIKit.Tokens' T.tween.panelOpen, value-for-value.
local PANEL_OPEN = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local cardGen = 0
local function glideCard(fr, from, to, info, gen)
	fr.Position = from
	task.spawn(function()
		RunService.RenderStepped:Wait()   -- let the first paint land before the clock starts
		if cardGen ~= gen or not fr.Visible then return end
		local t0 = os.clock()
		while true do
			RunService.RenderStepped:Wait()
			if cardGen ~= gen then return end
			local a = math.clamp((os.clock() - t0) / info.Time, 0, 1)
			fr.Position = from:Lerp(to, TweenService:GetValue(a, info.EasingStyle, info.EasingDirection))
			if a >= 1 then return end
		end
	end)
end

-- os.clock() of the last step completion; drives the beacon's victory flare.
local beaconHitAt = -99

-- Forward declarations: finish() tears the listeners down, and the listener block
-- assigns into this further down.
local stopListening

local BLACK = Color3.fromRGB(0, 0, 0)
local GOLD1, GOLD2 = Color3.fromRGB(255, 220, 100), Color3.fromRGB(240, 150, 24)
local FONT = UITheme.Font

-- FACTS: everything a step can be gated on. Durable ones come from the join
-- snapshot and every DataUpdated after it; session ones from events this client
-- sees. A step's done() reads these and nothing else.
local facts = {
	-- session
	threw = false, revealed = false, collected = false, bagOpened = false,
	lastDistance = nil, lastRarity = nil,
	-- durable (snapshot)
	brainrots = 0, placed = false, secondRock = false, totalEarned = 0, unlockedSpots = 12,
	-- the brainrot count on the JOIN snapshot only: the first step's durable proxy.
	-- A live first catch must advance through `revealed` (after the pop), never
	-- through the DataUpdated that lands a frame after ThrowResult.
	startBrainrots = 0,
	-- Goals board (QuestState)
	goalKnown = false, goalMet = false, goalClaimed = false, goalReward = 2400,
}
-- os.clock() of the last ThrowResult: a snapshot that lands inside the catch pop
-- (0.9 s, top-centre) waits the pop out before it may change the card.
local lastResultAt = -99
local POP_GRACE = 1.2
local active, stepIndex = false, 1
local completedSteps = 0   -- numbered steps finished, for the progress track

local function readSnapshot(snap)
	if type(snap) ~= "table" then return end
	if type(snap.Brainrots) == "table" then
		facts.brainrots = #snap.Brainrots
		local placed = false
		for _, e in ipairs(snap.Brainrots) do
			if type(e) == "table" and e.PadIndex ~= nil then placed = true break end
		end
		facts.placed = placed
	end
	if type(snap.OwnedRocks) == "table" then
		local second = false
		for id in pairs(snap.OwnedRocks) do
			if id ~= "Pebble" then second = true break end
		end
		facts.secondRock = second
	end
	if type(snap.TotalEarned) == "number" then facts.totalEarned = snap.TotalEarned end
	if type(snap.UnlockedSpots) == "number" then facts.unlockedSpots = snap.UnlockedSpots end
end

local function blackRim(o, t)
	for _, s in ipairs(o:GetChildren()) do
		if s:IsA("UIStroke") and s.ApplyStrokeMode ~= Enum.ApplyStrokeMode.Contextual then
			s.Color = BLACK; s.Thickness = t or 3; s.Transparency = 0
		end
	end
end
local function inkText(o, t)
	local st = Instance.new("UIStroke")
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	st.Color = BLACK; st.Thickness = t or 2; st.Transparency = 0.05; st.Parent = o
	return st
end
local function withCommas(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

---------------------------------------------------------------- beacon
local beacon = Instance.new("Model")
beacon.Name = "TutorialBeacon"

local function bpart(props)
	local p = Instance.new(props.Class or "Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = props.Color or GOLD1
	p.Size = props.Size
	p.Transparency = props.Transparency or 0
	p.Parent = beacon
	return p
end

-- ground pillar of light
local pillar = bpart({ Size = Vector3.new(46, 6, 6), Transparency = 0.86 })
pillar.Shape = Enum.PartType.Cylinder
-- arrow: shaft + downward point (two mirrored wedges)
local shaft = bpart({ Size = Vector3.new(0.85, 3.2, 0.85) })
local headA = bpart({ Class = "WedgePart", Size = Vector3.new(2.8, 2.1, 1.35) })
local headB = bpart({ Class = "WedgePart", Size = Vector3.new(2.8, 2.1, 1.35) })

local glow = Instance.new("PointLight")
glow.Color = GOLD1; glow.Range = 26; glow.Brightness = 3
glow.Parent = shaft

local tagGui = Instance.new("BillboardGui")
tagGui.Size = UDim2.fromOffset(190, 42)
tagGui.StudsOffset = Vector3.new(0, 4.2, 0)
tagGui.AlwaysOnTop = true
-- Deliberately the most generous cap in the game (everything else is 90-160). This is
-- a wayfinding beacon whose whole job is to be seen from far enough away to walk
-- toward, so capping it like a sign would defeat it. It only exists during the
-- first-join tutorial and only one is ever active.
tagGui.MaxDistance = 400
tagGui.Parent = shaft
local tag = Instance.new("TextLabel")
tag.Size = UDim2.fromScale(1, 1)
tag.BackgroundTransparency = 1
tag.Font = FONT
tag.TextScaled = true
tag.TextColor3 = Color3.fromRGB(255, 236, 160)
tag.Text = ""
tag.Parent = tagGui
inkText(tag, 2.5)

local function setBeacon(pos, label)
	if not pos then
		beacon.Parent = nil
		return
	end
	beacon.Parent = Workspace
	tag.Text = label or ""
	beacon:SetAttribute("BaseX", pos.X)
	beacon:SetAttribute("BaseY", pos.Y)
	beacon:SetAttribute("BaseZ", pos.Z)
end

---------------------------------------------------------------- rail ring
-- Some steps point at a HUD tile rather than a place in the world: a gold ring
-- pulsing around the Bag or Goals tile on the nav rail. Found by name
-- (GameHUD -> NavRail -> <id>Item, see GameHUDClient's RAIL_ORDER loop); if the
-- tile is not there within 5 s the ring is simply skipped -- the copy names the
-- tile anyway.
local ring = Instance.new("Frame")
ring.Name = "TutorialRing"
ring.AnchorPoint = Vector2.new(0.5, 0.5)
ring.Position = UDim2.fromScale(0.5, 0.5)
ring.Size = UDim2.fromScale(1.34, 1.34)
ring.BackgroundTransparency = 1
ring.ZIndex = 60
local ringCorner = Instance.new("UICorner")
ringCorner.CornerRadius = UDim.new(0, 22)
ringCorner.Parent = ring
local ringStroke = Instance.new("UIStroke")
ringStroke.Color = GOLD1
ringStroke.Thickness = 4
ringStroke.Transparency = 0
ringStroke.Parent = ring
local ringGen = 0
local function setRing(tileId)
	ringGen += 1
	ring.Parent = nil
	if not tileId then return end
	local gen = ringGen
	task.spawn(function()
		local hud = playerGui:WaitForChild("GameHUD", 5)
		local rail = hud and hud:FindFirstChild("NavRail", true)
		local item = rail and rail:FindFirstChild(tileId .. "Item")
		if gen ~= ringGen or not item then return end
		ring.Parent = item
	end)
end

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	if ring.Parent then
		local pulse = (math.sin(t * 5.0) + 1) * 0.5
		ringStroke.Thickness = 3 + pulse * 3
		ringStroke.Transparency = 0.05 + pulse * 0.35
	end
	if beacon.Parent == nil then return end
	local bx = beacon:GetAttribute("BaseX")
	if not bx then return end
	local base = Vector3.new(bx, beacon:GetAttribute("BaseY"), beacon:GetAttribute("BaseZ"))
	local bob = math.sin(t * 2.2) * 0.8
	local spin = t * 1.6
	local tip = base + Vector3.new(0, 7.5 + bob, 0)

	-- BEAT. Same 2.2 rad/s as the bob, so the flare lands at the top of every rise.
	local pulse = (math.sin(t * 2.2) + 1) * 0.5              -- 0..1
	glow.Brightness = 2.2 + pulse * 2.6
	pillar.Transparency = 0.90 - pulse * 0.10
	-- victory flare: the beacon itself acknowledges the step you just finished
	local flare = math.max(0, 1 - (os.clock() - beaconHitAt) / 0.45)
	if flare > 0 then
		glow.Brightness += flare * 9
		pillar.Transparency = math.max(0.35, pillar.Transparency - flare * 0.45)
	end

	pillar.CFrame = CFrame.new(base + Vector3.new(0, 23, 0)) * CFrame.Angles(0, 0, math.rad(90))
	shaft.CFrame = CFrame.new(tip + Vector3.new(0, 3.4, 0)) * CFrame.Angles(0, spin, 0)
	local headCF = CFrame.new(tip + Vector3.new(0, 1.05, 0)) * CFrame.Angles(0, spin, 0)
	headA.CFrame = headCF * CFrame.new(0, 0, 0.675) * CFrame.Angles(math.rad(180), 0, 0)
	headB.CFrame = headCF * CFrame.new(0, 0, -0.675) * CFrame.Angles(math.rad(180), math.rad(180), 0)
end)

---------------------------------------------------------------- guide chevrons
-- The beacon marks WHERE the step is. This marks the WAY there: a run of chevrons laid on
-- the ground from the player toward that beacon, flowing outward so it reads as "follow
-- me" rather than as scenery. It reads the beacon's own BaseX/Y/Z attributes, so there is
-- exactly one definition of where the current step is (no beacon = no chevrons).
local GUIDE_N     = 7      -- chevrons in the run
local GUIDE_STEP  = 5.0    -- studs between them
local GUIDE_START = 6.0    -- studs ahead of the player the run begins
local GUIDE_NEAR  = 16     -- inside this, the beacon is plainly visible; stop leading

local guide = Instance.new("Model")
guide.Name = "TutorialGuide"
local chevrons = {}
for i = 1, GUIDE_N do
	local pair = {}
	for k = 1, 2 do
		local b = Instance.new("Part")
		b.Name = ("Chevron%d_%d"):format(i, k)
		b.Size = Vector3.new(0.42, 0.42, 2.6)
		b.Anchored = true
		b.CanCollide = false
		b.CanQuery = false
		b.CanTouch = false
		b.CastShadow = false
		b.Material = Enum.Material.Neon
		b.Color = GOLD1
		b.Transparency = 1
		b.TopSurface = Enum.SurfaceType.Smooth
		b.BottomSurface = Enum.SurfaceType.Smooth
		b.Parent = guide
		pair[k] = b
	end
	chevrons[i] = pair
end

local guideParams = RaycastParams.new()
guideParams.IgnoreWater = true
guideParams.FilterType = Enum.RaycastFilterType.Exclude

local function hideGuide()
	if guide.Parent then guide.Parent = nil end
end

RunService.RenderStepped:Connect(function()
	local bx = beacon.Parent and beacon:GetAttribute("BaseX")
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (bx and hrp) then hideGuide() return end

	local target = Vector3.new(bx, beacon:GetAttribute("BaseY"), beacon:GetAttribute("BaseZ"))
	local flat = Vector3.new(target.X - hrp.Position.X, 0, target.Z - hrp.Position.Z)
	local dist = flat.Magnitude
	if dist < GUIDE_NEAR then hideGuide() return end

	guide.Parent = Workspace
	local dir = flat.Unit
	guideParams.FilterDescendantsInstances = { char, guide, beacon }
	local t = os.clock()
	for i, pair in ipairs(chevrons) do
		local along = GUIDE_START + (i - 1) * GUIDE_STEP
		if along > dist - 5 then
			pair[1].Transparency = 1
			pair[2].Transparency = 1
		else
			local p = hrp.Position + dir * along
			-- sit on whatever is actually underfoot: the valley floor, a plot deck, the dock
			local hit = Workspace:Raycast(p + Vector3.new(0, 14, 0), Vector3.new(0, -70, 0), guideParams)
			local y = hit and (hit.Position.Y + 0.35) or (hrp.Position.Y - 2.6)
			local at = Vector3.new(p.X, y, p.Z)
			local face = CFrame.lookAt(at, at + dir)
			pair[1].CFrame = face * CFrame.Angles(0, math.rad(34), 0) * CFrame.new(0, 0, -1.15)
			pair[2].CFrame = face * CFrame.Angles(0, math.rad(-34), 0) * CFrame.new(0, 0, -1.15)
			-- a pulse travelling outward along the run, so the eye is pulled toward the goal
			local phase = (t * 1.5 - (i - 1) * 0.16) % 1
			local a = 0.18 + math.abs(phase - 0.5) * 1.25
			pair[1].Transparency = a
			pair[2].Transparency = a
		end
	end
end)

---------------------------------------------------------------- card UI
-- DESKTOP: 340x184 bottom-left, x 92 clears the nav rail column (13..77) with a
-- 15px gap (measured 2026-08-20). PHONE: a 300x120 card with smaller type, parked
-- top-left under the currency cluster -- the only lane on a handset that is clear
-- of the rail row, the throw cluster (bottom-centre) and the catch pop (top-centre,
-- x from ~40% of the width). Sizes below are the desktop set; layoutCard() swaps.
local card = Instance.new("Frame")
card.Name = "TutorialCard"
card.AnchorPoint = Vector2.new(0, 1)
card.Position = UDim2.new(0, 92, 1, -16)
card.Size = UDim2.fromOffset(340, 184)
card.Visible = false
card.ZIndex = 9
card.Parent = gui
UITheme.stylePanel(card)
UITheme.corner(card, 16)
blackRim(card, 3)
-- UIPolish sweeps every TextLabel under PlayerGui and force-sets Font =
-- FredokaOne + TextColor3 = white on anything not opted out (see its apply()).
-- NoPolish on the card covers every descendant (UIPolish walks ancestors), so the
-- three text tiers read as three tiers. bodyLbl gets its own ink stroke below
-- because an exempt label no longer receives UIPolish's.
card:SetAttribute("NoPolish", true)

local stepLbl = Instance.new("TextLabel")
stepLbl.Size = UDim2.new(1, -20, 0, 20)
stepLbl.Position = UDim2.new(0, 14, 0, 10)
stepLbl.BackgroundTransparency = 1
stepLbl.Font = FONT
stepLbl.TextSize = 14
stepLbl.TextXAlignment = Enum.TextXAlignment.Left
stepLbl.TextColor3 = Color3.fromRGB(255, 220, 110)
stepLbl.ZIndex = 10
stepLbl.Parent = card
inkText(stepLbl, 1.8)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -20, 0, 26)
titleLbl.Position = UDim2.new(0, 14, 0, 30)
titleLbl.BackgroundTransparency = 1
titleLbl.Font = FONT
titleLbl.TextSize = 20
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLbl.ZIndex = 10
titleLbl.Parent = card
inkText(titleLbl, 2.2)

local bodyLbl = Instance.new("TextLabel")
bodyLbl.Size = UDim2.new(1, -24, 0, 44)
bodyLbl.Position = UDim2.new(0, 14, 0, 58)
bodyLbl.BackgroundTransparency = 1
bodyLbl.Font = Enum.Font.GothamMedium
bodyLbl.TextSize = 13
bodyLbl.TextWrapped = true
bodyLbl.TextXAlignment = Enum.TextXAlignment.Left
bodyLbl.TextYAlignment = Enum.TextYAlignment.Top
bodyLbl.TextColor3 = Color3.fromRGB(196, 206, 226)
bodyLbl.ZIndex = 10
bodyLbl.Parent = card
inkText(bodyLbl, 1.6)

-- CUE LINE: names the thing the tutorial is waiting for, or the last skip's
-- distance -> rarity. Without it a gated step is indistinguishable from a frozen one.
local cueLbl = Instance.new("TextLabel")
cueLbl.Name = "Cue"
cueLbl.AnchorPoint = Vector2.new(0, 1)
cueLbl.Position = UDim2.new(0, 14, 1, -60)
cueLbl.Size = UDim2.new(1, -28, 0, 16)
cueLbl.BackgroundTransparency = 1
cueLbl.Font = Enum.Font.GothamMedium
cueLbl.TextSize = 12
cueLbl.TextXAlignment = Enum.TextXAlignment.Left
cueLbl.TextColor3 = Color3.fromRGB(150, 162, 186)
cueLbl.Text = ""
cueLbl.ZIndex = 10
cueLbl.Parent = card
inkText(cueLbl, 1.4)

-- PROGRESS: fills per finished step.
local track = Instance.new("Frame")
track.Name = "Track"
track.AnchorPoint = Vector2.new(0, 1)
track.Position = UDim2.new(0, 14, 1, -46)
track.Size = UDim2.new(1, -28, 0, 8)
track.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
track.BorderSizePixel = 0
track.ZIndex = 10
track.Parent = card
UITheme.corner(track, 4)
UITheme.stroke(track, BLACK, 2)

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = GOLD1
fill.BorderSizePixel = 0
fill.ZIndex = 11
fill.Parent = track
UITheme.corner(fill, 4)
UITheme.gradient(fill, GOLD1, GOLD2, 90)

-- Hand-lerped for the same reason glideCard is (GameHUDClient.glidePanel header).
local fillGen = 0
local function setProgress(done, total)
	fillGen += 1
	local gen = fillGen
	local from = fill.Size
	local to = UDim2.fromScale(math.clamp(done / math.max(total, 1), 0, 1), 1)
	local dur = 0.35
	task.spawn(function()
		local t0 = os.clock()
		while true do
			RunService.RenderStepped:Wait()
			if fillGen ~= gen then return end
			local a = math.clamp((os.clock() - t0) / dur, 0, 1)
			fill.Size = from:Lerp(to, TweenService:GetValue(a, Enum.EasingStyle.Quart, Enum.EasingDirection.Out))
			if a >= 1 then return end
		end
	end)
end

local skipBtn = Instance.new("TextButton")
skipBtn.Size = UDim2.fromOffset(126, 32)
skipBtn.Position = UDim2.new(1, -138, 1, -40)
skipBtn.Text = "Skip Tutorial"
skipBtn.ZIndex = 10
skipBtn.Parent = card
UITheme.styleHudButton(skipBtn, Color3.fromRGB(150, 156, 170), Color3.fromRGB(94, 100, 114), 10)
skipBtn.TextSize = 13
blackRim(skipBtn, 2.5)

-- Where the card rests, per platform. Phone numbers were measured in the iPhone 16
-- simulator (733x371 viewport): the currency cluster ends at y~62, the tab bar is
-- centred, the rail row and the throw cluster own the bottom band.
local CARD_REST = UDim2.new(0, 92, 1, -16)
local function layoutCard()
	if Platform.IsPhone then
		card.AnchorPoint = Vector2.new(0, 0)
		CARD_REST = UDim2.new(0, 8, 0, 70)
		card.Size = UDim2.fromOffset(300, 120)
		stepLbl.TextSize = 11; stepLbl.Position = UDim2.new(0, 10, 0, 6); stepLbl.Size = UDim2.new(1, -16, 0, 14)
		titleLbl.TextSize = 15; titleLbl.Position = UDim2.new(0, 10, 0, 20); titleLbl.Size = UDim2.new(1, -16, 0, 20)
		bodyLbl.TextSize = 11; bodyLbl.Position = UDim2.new(0, 10, 0, 40); bodyLbl.Size = UDim2.new(1, -20, 0, 42)
		cueLbl.TextSize = 10; cueLbl.Position = UDim2.new(0, 10, 1, -30); cueLbl.Size = UDim2.new(1, -20, 0, 12)
		track.Position = UDim2.new(0, 10, 1, -18); track.Size = UDim2.new(1, -108, 0, 6)
		skipBtn.Size = UDim2.fromOffset(88, 22); skipBtn.Position = UDim2.new(1, -96, 1, -28); skipBtn.TextSize = 11
	else
		card.AnchorPoint = Vector2.new(0, 1)
		CARD_REST = UDim2.new(0, 92, 1, -16)
		card.Size = UDim2.fromOffset(340, 184)
	end
	card.Position = CARD_REST
end
layoutCard()
Platform.Watch(function() layoutCard() end)

---------------------------------------------------------------- helpers
local gw = Workspace:WaitForChild("GameWorld")
local plots = Workspace:WaitForChild("PlayerBases")

local function myPlot()
	for _, p in ipairs(plots:GetChildren()) do
		if p:GetAttribute("OwnerUserId") == player.UserId then return p end
	end
	return nil
end
local function nearestFreePlot()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local best, bestD
	for _, p in ipairs(plots:GetChildren()) do
		if p:IsA("Model") and not p:GetAttribute("Claimed") and p:GetAttribute("World") == "Valley" and p.PrimaryPart then
			local d = hrp and (p.PrimaryPart.Position - hrp.Position).Magnitude or 0
			if not bestD or d < bestD then best, bestD = p, d end
		end
	end
	return best
end
local function stallPos(name)
	local stall = gw:FindFirstChild(name)
	local part = stall and stall:FindFirstChild("PromptPart")
	return part and part.Position
end
-- a named part/model inside my plot (EquipBestPad, Campfire), else the plot itself
local function plotPos(childName)
	local p = myPlot()
	if not p then return nil end
	local c = childName and p:FindFirstChild(childName, true)
	if c and c:IsA("BasePart") then return c.Position end
	if c and c:IsA("Model") then return c:GetPivot().Position end
	return p.PrimaryPart and p.PrimaryPart.Position or p:GetPivot().Position
end
local function dockPos()
	local z = gw:FindFirstChild("ThrowZone")
	return z and z.Position
end

local uncommonAt = (RarityConfig[2] and RarityConfig[2].MinDistance) or 100
local firstRock = RockConfig[2] or { Name = "Rivertumble", Price = 2000, MaxDistance = 70 }
local starterReach = (RockConfig[1] and RockConfig[1].MaxDistance) or 25
local reachMult = math.max(2, math.floor(firstRock.MaxDistance / math.max(starterReach, 1) + 0.5))

---------------------------------------------------------------- steps
-- Title / Body / Tag (beacon label) / Cue (string or function) / Target (world
-- position or nil) / Ring (rail tile id or nil) / Done. Every Done reads `facts`.
local steps = {
	{
		Id = "skip",
		Title = "SKIP YOUR FIRST ROCK",
		Body = "Follow the arrows to the dock. HOLD the button, let go to skip.",
		Tag = "SKIP HERE",
		Cue = "Waiting for your first skip...",
		Target = dockPos,
		Done = function() return facts.revealed or facts.startBrainrots >= 1 end,
	},
	{
		Id = "bag",
		Title = "IT'S IN YOUR BAG",
		Body = ("Every catch goes to your Bag. Farther skips find rarer brainrots -- Uncommon from %dm. Catch %d!"):format(uncommonAt, GOAL_COUNT),
		Tag = "SKIP AGAIN",
		Cue = function()
			local n = math.min(facts.brainrots, GOAL_COUNT)
			if facts.lastDistance then
				return ("%d / %d caught  \u{2022}  last skip %dm \u{2192} %s"):format(n, GOAL_COUNT, facts.lastDistance, string.upper(facts.lastRarity or "Common"))
			end
			return ("%d / %d caught"):format(n, GOAL_COUNT)
		end,
		Target = dockPos,
		Ring = "bag",
		RingFor = 4,
		Done = function() return facts.brainrots >= GOAL_COUNT end,
	},
	{
		Id = "goal",
		Title = "GOAL COMPLETE!",
		Body = function() return ("Open GOALS on the left and claim your $%s."):format(withCommas(facts.goalReward)) end,
		Cue = "Waiting for you to claim it...",
		Target = function() return nil end,
		Ring = "goals",
		Done = function() return facts.goalClaimed end,
	},
	{
		Id = "openbag",
		Title = "OPEN YOUR BAG",
		Body = "Your brainrots are collected here. Take a look.",
		Cue = "Waiting for you to open the Bag...",
		Target = function() return nil end,
		Ring = "bag",
		Done = function() return facts.bagOpened end,
	},
	{
		Id = "place",
		Title = "PUT THEM ON YOUR BASE",
		Body = "Walk onto the green pad at your camp and confirm. Placed brainrots earn cash while you play.",
		Tag = "YOUR BASE",
		Cue = "Waiting for a brainrot on a pad...",
		Target = function() return plotPos("EquipBestPad") end,
		Done = function() return facts.placed end,
	},
	{
		Id = "collect",
		Title = "COLLECT YOUR CASH",
		Body = "Stand in the campfire to collect what they've earned.",
		Tag = "COLLECT",
		Cue = "Waiting for a collect...",
		Target = function() return plotPos("Campfire") end,
		Done = function() return facts.collected or facts.totalEarned > 0 end,
	},
	{
		Id = "rock",
		Title = "BUY A BETTER ROCK",
		Body = ("Rocco's %s skips %dx farther than your pebble. $%s -- you've earned it."):format(firstRock.Name or "Rivertumble", reachMult, withCommas(firstRock.Price)),
		Tag = "ROCCO - ROCKS",
		Cue = "Waiting for a rock purchase...",
		Target = function() return stallPos("ShopStall") end,
		Done = function() return facts.secondRock end,
	},
}
-- Only when the server could not auto-claim a camp at join (a full server).
local CLAIM_STEP = {
	Id = "claim",
	Title = "CLAIM A BASE",
	Body = "Walk onto a free camp. It's yours.",
	Tag = "CLAIM HERE",
	Cue = "Waiting for you to step onto a camp...",
	Target = function()
		local p = nearestFreePlot()
		return p and p.PrimaryPart and p.PrimaryPart.Position
	end,
	Done = function() return myPlot() ~= nil end,
}

local stepShownAt = 0
local function textOf(v)
	if type(v) == "function" then
		local ok, res = pcall(v)
		return ok and tostring(res or "") or ""
	end
	return v or ""
end

local function showStep(i)
	local s = steps[i]
	if not s then return end
	stepShownAt = os.clock()
	stepLbl.Text = ("STEP %d / %d"):format(i, #steps)
	titleLbl.Text = s.Title
	bodyLbl.Text = textOf(s.Body)
	cueLbl.Text = textOf(s.Cue)
	skipBtn.Visible = true
	setProgress(i - 1, #steps)
	setBeacon(s.Target(), s.Tag)
	setRing(s.Ring)
	if s.Ring and s.RingFor then
		local gen = ringGen
		task.delay(s.RingFor, function() if ringGen == gen then setRing(nil) end end)
	end
	-- MOTION: a new step ARRIVES. Same 26px rise + Back/Out curve that every HUD
	-- panel opens with (GameHUDClient openPanel -> glidePanel).
	cardGen += 1
	glideCard(card, CARD_REST + UDim2.fromOffset(0, 26), CARD_REST, PANEL_OPEN, cardGen)
	pcall(SoundKit.play, "panelOpen", nil, { volume = 0.14 })
end

local function refreshCue()
	if not active then return end
	local s = steps[stepIndex]
	if s and type(s.Cue) == "function" then cueLbl.Text = textOf(s.Cue) end
end

local FINISH_HOLD = 6
local function finish(completed)
	if not active then return end
	active = false
	setBeacon(nil)
	setRing(nil)
	hideGuide()
	if stopListening then stopListening() end
	if completed then
		-- The ladder ends ON SCREEN, and says what comes next.
		cardGen += 1
		stepLbl.Text = "COMPLETE"
		titleLbl.Text = "YOU'RE SET"
		bodyLbl.Text = ("Skip, catch, place, collect -- that's the loop. Next: fill all %d pads, sell spares to Marco, and save for Sevenskip -- it reaches UNCOMMON."):format(facts.unlockedSpots)
		cueLbl.Text = "Tap SKIP at the top to jump back to the dock."
		skipBtn.Visible = false
		setProgress(1, 1)
		beaconHitAt = os.clock()
		-- The kit already layers these two for a top-tier catch (see SoundKit.Ids
		-- catchBigHit / catchSparkle): impact to land it, shimmer over the top.
		pcall(SoundKit.play, "catchBigHit", nil, { volume = 0.32 })
		pcall(SoundKit.play, "catchSparkle", nil, { volume = 0.30 })
		glideCard(card, CARD_REST + UDim2.fromOffset(0, 26), CARD_REST, PANEL_OPEN, cardGen)
		task.delay(FINISH_HOLD, function()
			card.Visible = false
			-- the calendar (held by GameHUDClient) comes AFTER the finish beat, not over it
			player:SetAttribute(ONBOARDING_ATTR, false)
		end)
	else
		pcall(SoundKit.play, "panelClose", nil, { volume = 0.12 })
		card.Visible = false
		player:SetAttribute(ONBOARDING_ATTR, false)
	end
	-- the boolean is what gates the completion reward server-side
	remotes.TutorialComplete:FireServer(completed == true)
end

skipBtn.Activated:Connect(function() finish(false) end)

-- Completion is EVENT-shaped: every listener calls this, and the 0.4 s poll only
-- catches what the listeners did not see. Advances through every already-done step
-- in one go (rejoin resume, or a fact that satisfies two steps at once).
local function tryAdvance()
	if not active then return end
	local advanced = false
	while true do
		local s = steps[stepIndex]
		if not s or not s.Done() then break end
		advanced = true
		stepIndex += 1
		if stepIndex > #steps then finish(true) return end
	end
	if advanced then
		beaconHitAt = os.clock()                                      -- beacon flares
		pcall(SoundKit.play, "catchSparkle", nil, { volume = 0.26 })   -- step-complete ping
		showStep(stepIndex)
	else
		refreshCue()
	end
end

local function start()
	if active then return end
	active = true
	-- fast-forward: the first step that is genuinely open
	stepIndex = 1
	while steps[stepIndex] and steps[stepIndex].Done() do stepIndex += 1 end
	if stepIndex > #steps then
		-- everything the ladder teaches is already on the profile: just close it out
		finish(true)
		return
	end
	card.Visible = true
	showStep(stepIndex)
	-- first appearance comes in from further away. Bumping the gen supersedes the
	-- 26px glide showStep just started.
	cardGen += 1
	local from = Platform.IsPhone and (CARD_REST + UDim2.fromOffset(0, -40)) or UDim2.new(0, 92, 1, 60)
	glideCard(card, from, CARD_REST, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), cardGen)
end

---------------------------------------------------------------- listeners
-- Every listener this file opens goes in here, so a player who has finished -- or
-- skipped, or who arrived with TutorialDone already set -- is not signing snapshot
-- tables for the rest of the session.
local conns = {}
local function listen(signal, fn) conns[#conns + 1] = signal:Connect(fn) end
stopListening = function()
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	table.clear(conns)
end

-- StoneThrown fires for EVERY throw; ThrowResult only when a catch is revealed.
-- The first step waits for the REVEAL (+1.2 s so the catch pop, top-centre, has
-- finished before the card changes underneath it), not for the throw.
listen(remotes.StoneThrown.OnClientEvent, function() facts.threw = true end)
-- Advance, but not over a catch pop: anything that lands inside POP_GRACE of the
-- last ThrowResult waits the remainder out first.
local function advanceAfterPop()
	local left = POP_GRACE - (os.clock() - lastResultAt)
	if left > 0 then task.delay(left, tryAdvance) else tryAdvance() end
end
listen(remotes.ThrowResult.OnClientEvent, function(res)
	lastResultAt = os.clock()
	if type(res) == "table" then
		if type(res.Distance) == "number" then facts.lastDistance = res.Distance end
		if type(res.Rarity) == "string" then facts.lastRarity = res.Rarity end
	end
	task.delay(POP_GRACE, function()
		facts.revealed = true
		tryAdvance()
	end)
end)
listen(remotes.CampfireCollected.OnClientEvent, function() facts.collected = true; tryAdvance() end)
listen(remotes.DataUpdated.OnClientEvent, function(snap)
	readSnapshot(snap)
	advanceAfterPop()
end)
-- The Goals board: QuestHandler pushes the whole list every 3 s and on every claim.
listen(remotes.QuestState.OnClientEvent, function(list)
	if type(list) ~= "table" then return end
	local found = nil
	for _, q in ipairs(list) do
		if type(q) == "table" and q.Id == GOAL_ID then found = q break end
	end
	facts.goalKnown = true
	if found then
		facts.goalReward = tonumber(found.Reward) or facts.goalReward
		facts.goalMet = (found.Met == true)
		if found.Claimed == true then facts.goalClaimed = true end
	else
		-- the board no longer carries this goal: nothing to claim, the step stands down
		facts.goalClaimed = true
	end
	tryAdvance()
end)
-- "Open your Bag" means opening it: GameHUDClient mirrors the open panel's id here.
listen(player:GetAttributeChangedSignal("HudOpenPanel"), function()
	if player:GetAttribute("HudOpenPanel") == "bag" then
		facts.bagOpened = true
		tryAdvance()
	end
end)

-- The poll does not own advance: it keeps the beacon parked on a live target (a stall
-- can stream in late, a plot can change hands) and catches any Done() whose event
-- this file did not see.
task.spawn(function()
	while true do
		task.wait(0.4)
		if active then
			local s = steps[stepIndex]
			if s then
				if s.Done() then
					tryAdvance()
				else
					setBeacon(s.Target(), s.Tag)
				end
			end
		end
	end
end)

---------------------------------------------------------------- post-tutorial hint
-- ONE hint, once per session, after a completed ladder: the first snapshot that
-- shows every unlocked pad filled AND a spare in the bag. Selling is the early
-- game's real income (a Common sells for ~15 minutes of its own earnings) and
-- nothing else in the game says so at the moment it first matters.
local function armSpareHint()
	local Toast = require(Modules.UIKit.Toast)
	local conn
	conn = remotes.DataUpdated.OnClientEvent:Connect(function(snap)
		if type(snap) ~= "table" or type(snap.Brainrots) ~= "table" then return end
		local placed, spare = 0, 0
		for _, e in ipairs(snap.Brainrots) do
			if type(e) == "table" then
				if e.PadIndex ~= nil then placed += 1 else spare += 1 end
			end
		end
		local spots = tonumber(snap.UnlockedSpots) or facts.unlockedSpots
		if placed >= spots and spare >= 1 then
			conn:Disconnect()
			pcall(Toast.show, { text = "Base full -- spare brainrots sell for cash at Marco's stall (SHOPS)", tone = "info", hold = 5 })
		end
	end)
end

---------------------------------------------------------------- boot
task.spawn(function()
	local ok, snap = pcall(function() return remotes.GetInitialData:InvokeServer() end)
	if ok and type(snap) == "table" and not snap.TutorialDone then
		player:SetAttribute(ONBOARDING_ATTR, true)
		readSnapshot(snap)
		facts.startBrainrots = facts.brainrots
		-- The server auto-claims a valley camp for a first-join profile (Main). Give
		-- that attribute a moment to replicate; if nothing arrives, lead with CLAIM.
		local waited = 0
		while not myPlot() and waited < 3 do
			task.wait(0.25); waited += 0.25
		end
		if not myPlot() then table.insert(steps, 1, CLAIM_STEP) end
		task.wait(1.0)
		start()
		-- the hint only makes sense after a ladder that taught placing; a skipped one
		-- is the player saying "I know", and the toast would be noise
		local watch
		watch = player:GetAttributeChangedSignal(ONBOARDING_ATTR):Connect(function()
			if player:GetAttribute(ONBOARDING_ATTR) == false then
				watch:Disconnect()
				if stepIndex > #steps then armSpareHint() end
			end
		end)
	else
		-- already done (or the fetch failed): nothing will ever read these flags
		stopListening()
	end
end)
```

- [ ] **Step 2: Load into Studio + compile-check**

`LOAD("StarterPlayer.StarterPlayerScripts.TutorialClient", ".../TutorialClient.client.lua")`, `COMPILE`. Expected `COMPILES`. Fix any syntax error in the mirror file first, then re-LOAD.

- [ ] **Step 3: Fresh-profile walk (desktop) — the Task 10 protocol, steps 1–6**

Run the Task 10 walk with suffix `_qa3`. Every step must advance on the real action; note timestamps.

- [ ] **Step 4: Push + manifest + commit**

```bash
git add game-src/place-full/StarterPlayer/StarterPlayerScripts/TutorialClient.client.lua game-src/place-full/_MANIFEST.txt
git commit -m "feat(onboarding): one-card, event-gated first-session ladder -- skip first, goal, bag, base, collect, rock"
```

---

## Task 8: READY! Goals bar opens the Goals panel (LIVE source)

**Files:**
- Modify: `StarterPlayer/StarterPlayerScripts/QuestBarClient.client.lua` — **pull the live Source first** (`PUSH` it to the mirror path; the mirror on this branch is the pre-round-3 file), then edit the mirror, then `LOAD`.

**Interfaces:**
- Consumes: the bar's `root` frame and its `count` label (reads "READY!" when the picked goal is met); `HudPanelRequest` attribute idiom.
- Produces: tapping the bar while READY opens the Goals panel.

- [ ] **Step 1: Pull the live file to the mirror**

`PUSH("StarterPlayer.StarterPlayerScripts.QuestBarClient", "<worktree>\game-src\place-full\StarterPlayer\StarterPlayerScripts\QuestBarClient.client.lua")`. Expected: `saved 20374 bytes ...`. `git diff --stat` shows the file changed (round-3 version now mirrored).

- [ ] **Step 2: Read the live file around the READY! branch** (`grep -n "READY" ...`), identify the frame that holds the count label (`root`) and the dismiss button's name/ZIndex.

- [ ] **Step 3: Add the tap-to-open**

After `root` is created and styled (right after the `HOME_POS` / `dismissBar` block), add:

```lua
-- TAP WHEN READY (2026-09-21, first-10-minutes round). The bar said READY! and the
-- claim lived two clicks away on a rail tile a new player has never opened; the
-- tutorial's GOAL COMPLETE step points at that tile, and this makes the bar itself
-- the shortcut. A full-size transparent button UNDER the dismiss glyph (lower
-- ZIndex, so the X keeps its own hit), active only while the shown goal is met.
local readyHit = Instance.new("TextButton")
readyHit.Name = "ReadyHit"
readyHit.Size = UDim2.fromScale(1, 1)
readyHit.BackgroundTransparency = 1
readyHit.Text = ""
readyHit.AutoButtonColor = false
readyHit.ZIndex = root.ZIndex
readyHit.Parent = root
local shownMet = false
readyHit.Activated:Connect(function()
	if shownMet then player:SetAttribute("HudPanelRequest", "goals") end
end)
```

and in the `QuestState` handler, where the bar is repainted for the picked goal `q`, set `shownMet = (q.Met == true)` (next to the line that writes `count.Text = "READY!"` / the progress text). Make sure the dismiss glyph's button has a higher ZIndex than `readyHit` (bump it by 2 if equal).

- [ ] **Step 4: Load, compile-check, verify**

`LOAD` + `COMPILE`. In the Task 10 fresh walk, at GOAL COMPLETE tap the bar: `HudOpenPanel` becomes `goals`. Tap the X: the bar dismisses, the panel does not open.

- [ ] **Step 5: Push + manifest + commit**

```bash
git add game-src/place-full/StarterPlayer/StarterPlayerScripts/QuestBarClient.client.lua game-src/place-full/_MANIFEST.txt
git commit -m "ui(goals-bar): mirror the live round-3 bar and make READY! tap open the Goals panel"
```

---

## Task 9: Manifest line regeneration (tool, scratchpad)

**Files:**
- Create (scratchpad): `<scratchpad>/manifest_update.py`

- [ ] **Step 1: Write it**

```python
import sys, os, re
ROOT = r"C:\Users\m\Coding\skip-a-brainrot\.claude\worktrees\onboarding-first-10-min-b8f4dc\game-src\place-full"
MAN = os.path.join(ROOT, "_MANIFEST.txt")
CLASS = {".server.lua": "Script", ".client.lua": "LocalScript", ".lua": "ModuleScript"}

def h31(data):
    h = 5381
    for b in data:
        h = (h * 31 + b) & 0xFFFFFFFF
    return "%08x" % h

def entry(rel):
    for ext, cls in CLASS.items():
        if rel.endswith(ext):
            path = rel[:-len(ext)].replace("/", ".").replace("\\", ".")
            break
    data = open(os.path.join(ROOT, rel), "rb").read()
    return "%s|%d|%s|%s" % (h31(data), len(data), cls, path), path

lines = open(MAN, encoding="utf-8").read().split("\n")
for rel in sys.argv[1:]:
    line, path = entry(rel)
    found = False
    for i, l in enumerate(lines):
        if l.endswith("|" + path):
            lines[i] = line; found = True
    if not found:
        lines.append(line)
    print(line)
body = "\n".join(sorted([l for l in lines if l], key=lambda l: l.split("|")[3])) + "\n"
open(MAN, "w", encoding="utf-8", newline="\n").write(body)
```

- [ ] **Step 2: Sanity-check against an unchanged file**

Run: `python manifest_update.py ReplicatedStorage/Modules/BagConfig.lua` → prints `7ef6c502|6387|ModuleScript|ReplicatedStorage.Modules.BagConfig` (the existing line, unchanged). `git diff --stat game-src/place-full/_MANIFEST.txt` shows no change (or only ordering, which must not happen — if it does, the file was not sorted by path before; keep the original order instead by replacing in place only).

---

## Task 10: Fresh-player verification (desktop + phone + rejoin + returning)

**Files:**
- Create: `docs/onboarding/TEST-LOG-2026-09-21.md`, `docs/onboarding/captures/*.jpg`

Protocol (Studio must be free: `get_studio_state` = Edit and no other session mid-run; the owner minimises Studio, so captures use `tools/studio-bridge/capture-studio.ps1 -Mode print` with the no-activate show/restore documented in the project memory):

- [ ] **Step 1: Fresh join (desktop)** — suffix `_qa3` (new). Play. Client exec at t+3 s:

```lua
local P = game.Players.LocalPlayer
local card = P.PlayerGui.MainUI:FindFirstChild("TutorialCard")
local bar = P.PlayerGui:FindFirstChild("QuestBarUI")
local goalTxt = ""
for _, d in ipairs(bar and bar:GetDescendants() or {}) do if d:IsA("TextLabel") and d.Text ~= "" then goalTxt ..= d.Text .. " | " end end
return ("panel=%s onboarding=%s card=%s title=%s goals=%s"):format(tostring(P:GetAttribute("HudOpenPanel")), tostring(P:GetAttribute("OnboardingActive")), tostring(card and card.Visible), card and card:FindFirstChildOfClass("TextLabel").Text or "-", goalTxt)
```

Expected: `panel=nil onboarding=true card=true`, title `SKIP YOUR FIRST ROCK`, goals text contains `Own 5 brainrots` (not `Uncommon`). Capture → `captures/01-join-desktop.jpg`.

- [ ] **Step 2: First throw** — `character_navigation` to `(0, 6, 22)`; Client exec: hold the throw button (`throwButton` InputBegan/InputEnded are connected to Mouse/Touch; drive the same path by firing `remotes.ThrowRequest:FireServer(0.6, false, false)` from the Client exec, which is what release does). Expected within 4 s: card title `IT'S IN YOUR BAG`, cue `1 / 5 caught • last skip 25m → COMMON`, Bag tile carries `TutorialRing` for ~4 s. Capture the pop + card → `captures/02-first-catch.jpg` (burst capture 120 ms while the pop is up).

- [ ] **Step 3: Four more throws** (respect the 1.05 s cooldown + flight: one `ThrowRequest` every 3.5 s). Expected: card → `GOAL COMPLETE!` with `$2,400`; Goals tile ring; Goals bar reads READY!. Tap the bar (`readyHit` Activated via `HudPanelRequest = "goals"`) → Goals panel; claim `own5` via `remotes.QuestClaim:FireServer("own5")` (the panel's own button does this) → cash 2,400 → card `OPEN YOUR BAG`.

- [ ] **Step 4: Bag** — `P:SetAttribute("HudPanelRequest", "bag")` → card `PUT THEM ON YOUR BASE`, beacon on `EquipBestPad`. Close (`HudPanelCloseRequest`).

- [ ] **Step 5: Place + collect** — navigate to the pad (`myPlot().EquipBestPad`); confirm through the EquipPadUI (or `remotes.EquipBest:FireServer()` which the confirm fires) → card `COLLECT YOUR CASH`; navigate into the campfire ring (Campfire pivot, stand 2.5 s) → card `BUY A BETTER ROCK`.

- [ ] **Step 6: Rock** — navigate to Rocco, open the shop (prompt via `InputHoldBegin/End`), verify the Rivertumble card reads `$2K` BUY and the two info lines; `remotes.BuyRock:FireServer("SmoothStone")` (what BUY fires) → toast `Bought and equipped SmoothStone!`, card `YOU'RE SET`, cash ≥ 3,000 after the grant, `OnboardingActive` false after 6 s, calendar opens (`HudOpenPanel == "daily"`), closing it auto-claims (+$500). Record the wall-clock per step in the test log. Capture → `captures/03-rock-shop.jpg`, `captures/04-youre-set.jpg`, `captures/05-calendar-after.jpg`.

- [ ] **Step 7: Rejoin mid-ladder** — new suffix `_qa4`: Play, do steps 1–3 up to (not including) the goal claim, Stop. Wait 100 s. Play again with `_qa4`. Expected: base auto-claimed again (fresh server), card opens directly at `GOAL COMPLETE!` (5 brainrots on the profile, goal unclaimed), no calendar. Stop.

- [ ] **Step 8: Skip Tutorial** — suffix `_qa5`: Play, click Skip Tutorial on the first card with `user_mouse_input` at the button's absolute centre (`card.AbsolutePosition + skipBtn.AbsolutePosition + AbsoluteSize/2`, read from the Client exec). If Play input wedges (it can after 1–3 clicks per session), exercise the same path by hand from the Client exec: `remotes.TutorialComplete:FireServer(false)` then `P:SetAttribute("OnboardingActive", false)`. Expected: `TutorialDone == true` on the `_qa5` row, cash unchanged (no reward), the calendar opens at once (`HudOpenPanel == "daily"`), and a second join on `_qa5` (after 100 s) shows no card.

- [ ] **Step 9: Phone** — `StudioDeviceSimulatorService:SetDeviceAsync("iphone_16")` BEFORE Play, suffix `_qa6`. At join and at the dock (`HudPanelRequest` opens panels; `PlatformOverride` not needed in the simulator), run `HudAudit.Run({})` from the Client exec and read its overlap list: zero rows naming `TutorialCard`. Capture → `captures/06-phone-join.jpg`, `captures/07-phone-dock.jpg`. `StopSimulationAsync()` after.

- [ ] **Step 10: Returning profile** — suffix nil (real account). Play: calendar behaviour unchanged, no tutorial card, no auto-claim, Goals bar unchanged except tier-goal fractions. Stop.

- [ ] **Step 11: Clear the seam** — `ServerStorage:SetAttribute("ProfileKeySuffix", nil)` and confirm `GetAttribute` returns nil. Write `docs/onboarding/TEST-LOG-2026-09-21.md` with the timestamps, outcomes and capture names; commit.

```bash
git add docs/onboarding/TEST-LOG-2026-09-21.md docs/onboarding/captures
git commit -m "docs(onboarding): fresh-player verification log + captures"
```

---

## Task 11: Final sync + report

- [ ] **Step 1: Byte-exact mirror check** — Edit exec: for each of the nine scripts, compute `#Source` and the h31 hash and compare with `_MANIFEST.txt`; any mismatch → `PUSH` again and rerun `manifest_update.py`.
- [ ] **Step 2: Console sweep** — `get_console_output` after the last Play: no `[TutorialClient]`, `[GameHUDClient]`, `QuestHandler` or `Main` errors; the known harmless `[UIKit] panel module PetAbilityHelp` warning may appear.
- [ ] **Step 3: Write `docs/onboarding/REPORT-2026-09-21.md`** with the eight sections the brief asks for (previous flow, new flow, tutorial changes, UI sequencing changes, economy values changed and why, files touched, fresh-player test results, open progression decisions) and commit.
- [ ] **Step 4: Stop and report to the owner** (no push, no publish — the owner publishes).
