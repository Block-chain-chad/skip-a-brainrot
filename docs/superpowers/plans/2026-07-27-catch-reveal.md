# Catch Reveal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the text result card with the caught brainrot itself, appearing on screen and spinning slowly, escalating over four bands from Common to God — per the approved spec `docs/specs/2026-07-27-catch-reveal-design.md`.

**Architecture:** One new client module (`CatchReveal`) owns the whole reveal — band selection, render, spin, teardown — and knows nothing about remotes or Robux. A thin new LocalScript (`CatchRevealClient`) subscribes to the existing `ThrowResult` remote and calls it, and is the single seam where the phase-2 Robux skip plugs in. `ClientMain` loses the old card. Bands 1–3 render into a `ViewportFrame`; band 4 (Secret/God) spawns a real world model behind a locked camera, because `MutationFX` is built from ParticleEmitters and `Highlight`, neither of which renders inside a viewport.

**Tech Stack:** Roblox Luau, live Studio place via roblox-studio MCP (`multi_edit` to install and patch, `execute_luau` to drive and verify), repo mirrors in `game-src/`.

## Global Constraints

- **No server changes at all.** Nothing in `ServerScriptService` is edited, including comments. The place is shared with collaborator `yeep1234`. `ThrowResult` already carries every needed field.
- **No new remotes, no new player-data fields, no schema change.**
- Reveal never blocks a catch: any failure inside it must be caught and swallowed, never propagated to the throw path.
- **`Model:ScaleTo()` is ABSOLUTE, not relative.** Always `m:ScaleTo(m:GetScale() * factor)`. Re-measuring an already-scaled model and calling `ScaleTo` again resets it to authored size.
- Models live in **`ReplicatedStorage.BrainrotModels`** (150, client-readable). `ServerStorage.BrainrotModels` no longer exists.
- On these imported packs the **`PrimaryPart` is an arbitrary limb** sitting anywhere inside the body — never rotate or frame a model about its PrimaryPart. Use `GetBoundingBox()` and set `WorldPivot` to the box centre.
- **Strip scripts from any world clone.** `ReplicatedStorage.BrainrotModels` is currently verified 0 scripts, but the imported pack has carried embedded free-model scripts before, and they only run outside Studio. Defensive strip, cheap.
- Client-created instances parented to `Workspace` do **not** replicate — the band-4 model is local to the catching player by construction.
- `UITheme.Font` is the single-source font face; never hardcode `Enum.Font.*` in new UI.
- `UITheme.inkText(label, thickness)` **returns the UIStroke** it created; collect them to fade, because a UIStroke carries its own `Transparency` and does not follow `TextTransparency`.
- Studio may be in Play mode (the owner plays regularly). All `multi_edit` installs require **Edit** mode — stop Play only with a heads-up, never silently. **In Play mode, `script_read` and `script_grep` silently address the Client DataModel**, so server scripts read as "not found" and greps come back empty. That is not a missing file — check `get_studio_state` first.
- **`script_grep`'s line numbers do not match `script_read`'s** in this place (observed ~50 lines apart in `ThrowHandler`). Use grep to find *whether* something exists; use `script_read` and exact anchor strings to locate an edit. Never drive a `multi_edit` from a grep line number.
- Testing is Studio-side: there is no test framework. Each task's test step is an `execute_luau` script whose printed assertions must all read `OK`. Reveal UI must be driven from the **Client** VM (it lives in PlayerGui).

## File Structure

| File | Responsibility |
|---|---|
| `ReplicatedStorage.Modules.CatchReveal` (new ModuleScript) | The reveal: band selection, viewport + world render paths, spin driver, teardown, camera restore. Public API only: `play`, `isPlaying`. |
| `StarterPlayer.StarterPlayerScripts.CatchRevealClient` (new LocalScript) | Subscribes to `ThrowResult`, decides whether to reveal, calls `CatchReveal.play`. Holds the phase-2 `shouldReveal` seam. |
| `StarterPlayer.StarterPlayerScripts.ClientMain` (modify) | Stop showing `resultFrame`; suppress `celebrateCatch` for band 4. |
| `game-src/CatchReveal.lua`, `game-src/CatchRevealClient.lua` (new mirrors) | Commit-time mirrors. Studio stays the source of truth. |
| `game-src/ClientMainCatchPatch.txt` (new) | Records the two `ClientMain` edits, following the `IndexPatch.txt` precedent for patches to shared files. |

**Why the flair is written inside `CatchReveal` rather than reusing `RarityFX.attach`:** `RarityFX`'s API is tile-shaped (`outer` border frame + `inner` content frame, with the rainbow cycling `outer.BackgroundColor3`) and its sizes are tuned against 112×136 grid cells. A 380px full-screen moment needs its own sizes, and coupling a reveal to a grid-tile module would make both harder to change. The visual vocabulary — halo, shimmer, sparkle, rainbow — stays shared by convention, not by code.

---

### Task 1: `CatchReveal` module — bands 1–3 (viewport), spin, teardown, fallback

Band 4 deliberately renders as band 3 for now; Task 2 gives it the world path. This keeps Task 1 a complete, shippable reveal for all eight tiers.

**Files:**
- Modify: `ReplicatedStorage.Modules.BrainrotThumb` (additive — extract the framing maths)
- Create: `ReplicatedStorage.Modules.CatchReveal` (ModuleScript)
- Mirror: `game-src/BrainrotThumb.lua`, `game-src/CatchReveal.lua`

**Interfaces:**
- Consumes:
  - `ReplicatedStorage.Modules.BrainrotThumb` → `master(name) -> Model?` (cached, stripped, unparented master; clone it, never parent the master), plus the two members added in Step 2 below
  - `ReplicatedStorage.Modules.UITheme` → `.Camp` palette table, `.Font`, `corner(inst, radius)`, `inkText(label, thickness) -> UIStroke`
- Produces (relied on by Tasks 2, 3, 4):
  - `M.play(info: {Name: string, Rarity: string?, RarityColor: Color3?, Mutation: string?}) -> handle?`
  - `handle:skip()` — tear down immediately; safe to call more than once; safe after natural completion
  - `M.isPlaying() -> boolean`
  - Internal names Task 2 and 3 patch against: `BAND_OF`, `SPEC`, `SPIN`, `teardown(rec)`, `buildViewport(rec, spec, info)`

- [ ] **Step 1: Confirm Studio is in Edit mode and the bridge is live**

Run `get_studio_state`. Expected: `Current Studio Mode: Edit`. If it reports Play, tell the user before stopping it.

- [ ] **Step 2: Extract the framing maths into `BrainrotThumb`**

`CatchReveal` must ORBIT the viewport camera, which `BrainrotThumb.add` never exposes — it sets the camera once and returns only the ViewportFrame. Rather than copy the six-line bounding-box calculation into a second module where the two would drift apart, extract it. Additive and pure: `add`'s behaviour is unchanged and its two existing callers (`BackpackClient`, and `IndexClient`'s own copy) are untouched.

`multi_edit` on `game.ReplicatedStorage.Modules.BrainrotThumb`. Replace:

```lua
-- front-quarter, slightly above; bodies stand on Y=0 facing -Z
local DEFAULT_DIR = Vector3.new(0.9, 0.45, -1).Unit
```

with:

```lua
-- front-quarter, slightly above; bodies stand on Y=0 facing -Z
local DEFAULT_DIR = Vector3.new(0.9, 0.45, -1).Unit
M.DEFAULT_DIR = DEFAULT_DIR

-- Where to put a camera so a model of any size fills the frame: the point it
-- looks at, and how far back to stand. Extracted so CatchReveal can ORBIT the
-- camera using the same numbers add() uses to place it once -- two copies of
-- this calculation would drift.
function M.framing(model, fov)
	fov = fov or 30
	local cf, ext = model:GetBoundingBox()
	local dist = math.max(ext.X, ext.Y, ext.Z) / (2 * math.tan(math.rad(fov / 2))) + ext.Z * 0.5
	return cf.Position, dist
end
```

Then replace `add`'s inlined copy:

```lua
	local fov = opts.fov or 30
	local cf, ext = m:GetBoundingBox()
	local dist = math.max(ext.X, ext.Y, ext.Z) / (2 * math.tan(math.rad(fov / 2))) + ext.Z * 0.5
	local cam = Instance.new("Camera")
	cam.FieldOfView = fov
	cam.CFrame = CFrame.lookAt(cf.Position + (opts.dir or DEFAULT_DIR) * dist, cf.Position)
```

with:

```lua
	local fov = opts.fov or 30
	local centre, dist = M.framing(m, fov)
	local cam = Instance.new("Camera")
	cam.FieldOfView = fov
	cam.CFrame = CFrame.lookAt(centre + (opts.dir or DEFAULT_DIR) * dist, centre)
```

Leave the comment above that block in place — it explains *why* the box drives the distance, and it is still true.

- [ ] **Step 3: Create the module**

Install with `multi_edit`, `file_path = "game.ReplicatedStorage.Modules.CatchReveal"`, `className = "ModuleScript"`, `datamodel_type = "Edit"`, first edit `old_string = ""`:

```lua
-- CatchReveal: the catch moment.
--
-- When you catch a brainrot, the brainrot ITSELF appears on screen and spins
-- slowly. Four bands over the eight tiers, each adding a NEW KIND of thing
-- rather than more of the last -- the rule that makes the RarityFX and
-- MutationFX ladders readable at a glance:
--
--   1  Common/Uncommon   small viewport, no backdrop
--   2  Rare/Epic         bigger + a coloured halo
--   3  Legendary/Mythic  large + shimmer + sparkles, screen darkened
--   4  Secret/God        a REAL world model, camera locked, full MutationFX
--
-- Why band 4 is not a viewport: ParticleEmitters and Highlight DO NOT RENDER
-- inside a ViewportFrame (BrainrotThumb says as much in its own header), and
-- MutationFX is built entirely from those two. A viewport reveal structurally
-- cannot show a mutation. Secret and God are exactly the catches where a
-- mutation is most worth seeing, so those two get a real model instead.
--
-- This module knows nothing about remotes and nothing about Robux. It is given
-- a catch and it shows it. CatchRevealClient decides whether to call it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local BrainrotThumb = require(ReplicatedStorage.Modules.BrainrotThumb)
local UITheme = require(ReplicatedStorage.Modules.UITheme)

local M = {}

local CF = UITheme.Camp
local player = Players.LocalPlayer

local BAND_OF = {
	Common = 1, Uncommon = 1,
	Rare = 2, Epic = 2,
	Legendary = 3, Mythic = 3,
	Secret = 4, God = 4,
}

-- size    viewport square in px
-- hold    seconds fully on screen, excluding the fades
-- dark    how black the backdrop goes, as OPACITY (0 = no backdrop)
-- halo    coloured ring behind the model
-- shimmer seconds per shine sweep, or false
-- sparkle how many twinkles
local SPEC = {
	{ size = 180, hold = 1.4, dark = 0.00, halo = false, shimmer = false, sparkle = 0 },
	{ size = 280, hold = 2.0, dark = 0.15, halo = true,  shimmer = false, sparkle = 0 },
	{ size = 380, hold = 2.8, dark = 0.45, halo = true,  shimmer = 2.4,   sparkle = 4 },
	-- Band 4 is filled in by the world path. Until that exists it renders as
	-- band 3, so every tier already has a working reveal.
	{ size = 380, hold = 3.8, dark = 0.80, halo = true,  shimmer = 1.8,   sparkle = 5 },
}

local SPIN = 70     -- degrees per second, identical in every band
local FADE = 0.22   -- seconds, in and out
local FOV  = 30     -- viewport camera, matches BrainrotThumb

-- fixed sparkle spots so a reveal looks composed rather than random
local SPARKLE_AT = {
	Vector2.new(0.14, 0.22), Vector2.new(0.85, 0.28), Vector2.new(0.24, 0.74),
	Vector2.new(0.78, 0.70), Vector2.new(0.50, 0.10),
}

local gui             -- ScreenGui, built on first use
local live            -- the running reveal's record, or nil
local token = 0

local function ensureGui()
	if gui and gui.Parent then return gui end
	gui = Instance.new("ScreenGui")
	gui.Name = "CatchRevealUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- above the rare-catch banner (8) and every panel (9)
	gui.DisplayOrder = 12
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

-- Safe to call twice, and safe after a natural finish. Everything that can
-- outlive the reveal is torn down here and nowhere else, so there is exactly
-- one path out.
local function teardown(rec)
	if not rec or rec.dead then return end
	rec.dead = true
	if rec.conn then rec.conn:Disconnect(); rec.conn = nil end
	if rec.restore then pcall(rec.restore) end
	if rec.root then rec.root:Destroy(); rec.root = nil end
	if live == rec then live = nil end
end

-- The model, framed and spinning. Returns the per-frame updater, or nil when
-- there is no model for that name (caller falls back to text only).
local function buildViewport(rec, spec, info, parent)
	local master = BrainrotThumb.master(info.Name)
	if not master then return nil end

	local vp = Instance.new("ViewportFrame")
	vp.Name = "Model"
	vp.AnchorPoint = Vector2.new(0.5, 0)
	vp.Position = UDim2.fromScale(0.5, 0)
	vp.Size = UDim2.fromOffset(spec.size, spec.size)
	vp.BackgroundTransparency = 1
	vp.ZIndex = 3
	vp.Parent = parent

	local m = master:Clone()
	m.Parent = vp

	-- Frame from the REAL bounding box: these models run from under 5 studs to
	-- over 30, so one fixed distance would crop the big ones and shrink the
	-- small ones to a dot. Shared with BrainrotThumb.add so the grids and the
	-- reveal cannot disagree about how a model is framed.
	local centre, dist = BrainrotThumb.framing(m, FOV)

	local cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	cam.Parent = vp
	vp.CurrentCamera = cam

	rec.viewport = vp

	-- Spin the CAMERA around the model, not the model. Rotating the model would
	-- need its pivot moved to the bounding-box centre first, because on these
	-- packs the PrimaryPart is an arbitrary limb sitting anywhere inside the
	-- body -- it would wobble around an off-centre point. Orbiting the camera
	-- is identical on screen and cannot disturb the model at all.
	local base = BrainrotThumb.DEFAULT_DIR
	return function(t)
		local dir = CFrame.Angles(0, math.rad(SPIN) * t, 0) * base
		cam.CFrame = CFrame.lookAt(centre + dir * dist, centre)
	end
end

function M.isPlaying()
	return live ~= nil and not live.dead
end

-- info = { Name, Rarity, RarityColor, Mutation }
-- Returns a handle with :skip(), or nil if nothing could be shown.
function M.play(info)
	if type(info) ~= "table" or type(info.Name) ~= "string" then return nil end

	-- newest wins, matching the resultToken behaviour the old card had
	if live then teardown(live) end
	token += 1
	local myToken = token

	local band = BAND_OF[info.Rarity] or 1
	local spec = SPEC[band]
	local accent = typeof(info.RarityColor) == "Color3" and info.RarityColor
		or Color3.fromRGB(190, 190, 190)

	local rec = { dead = false, band = band, token = myToken }

	local root = Instance.new("Frame")
	root.Name = "Reveal"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.ZIndex = 1
	root.Parent = ensureGui()
	rec.root = root

	local fades = {}   -- {inst, prop, to}

	-- backdrop. Stated as OPACITY in SPEC, so invert it here -- "dark 0.8" read
	-- as a transparency would mean the opposite of what is intended.
	if spec.dark > 0 then
		local dim = Instance.new("Frame")
		dim.Name = "Dim"
		dim.Size = UDim2.fromScale(1, 1)
		dim.BackgroundColor3 = Color3.new(0, 0, 0)
		dim.BackgroundTransparency = 1
		dim.BorderSizePixel = 0
		dim.ZIndex = 1
		dim.Parent = root
		table.insert(fades, { dim, "BackgroundTransparency", 1 - spec.dark })
	end

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.42)   -- above centre, clear of the hotbar
	holder.Size = UDim2.fromOffset(spec.size, spec.size + 92)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 2
	holder.Parent = root

	-- halo: an oversized ring behind the model carrying a coloured stroke
	local haloStroke
	if spec.halo then
		local halo = Instance.new("Frame")
		halo.Name = "Halo"
		halo.AnchorPoint = Vector2.new(0.5, 0.5)
		halo.Position = UDim2.new(0.5, 0, 0, spec.size / 2)
		halo.Size = UDim2.fromOffset(spec.size * 0.86, spec.size * 0.86)
		halo.BackgroundTransparency = 1
		halo.ZIndex = 2
		halo.Parent = holder
		local hc = Instance.new("UICorner")
		hc.CornerRadius = UDim.new(1, 0)
		hc.Parent = halo
		haloStroke = Instance.new("UIStroke")
		haloStroke.Color = accent
		haloStroke.Thickness = 6
		haloStroke.Transparency = 1
		haloStroke.LineJoinMode = Enum.LineJoinMode.Round
		haloStroke.Parent = halo
		table.insert(fades, { haloStroke, "Transparency", 0.35 })
	end

	local spin = buildViewport(rec, spec, info, holder)
	if rec.viewport then
		rec.viewport.ImageTransparency = 1
		table.insert(fades, { rec.viewport, "ImageTransparency", 0 })
	end

	-- shimmer lives on its OWN empty frame, never on anything holding text: a
	-- UIGradient tints its parent's glyphs too, which has bitten this codebase.
	local shimmerGrad
	if spec.shimmer then
		local shim = Instance.new("Frame")
		shim.Name = "Shimmer"
		shim.Size = UDim2.fromOffset(spec.size, spec.size)
		shim.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		shim.BackgroundTransparency = 0
		shim.BorderSizePixel = 0
		shim.ZIndex = 4
		shim.Parent = holder
		shimmerGrad = Instance.new("UIGradient")
		shimmerGrad.Rotation = 24
		shimmerGrad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.44, 1),
			NumberSequenceKeypoint.new(0.50, 0.62),
			NumberSequenceKeypoint.new(0.56, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		shimmerGrad.Parent = shim
	end

	local sparkles = {}
	for i = 1, spec.sparkle do
		local at = SPARKLE_AT[i] or SPARKLE_AT[1]
		local s = Instance.new("TextLabel")
		s.Name = "Sparkle"
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.Position = UDim2.new(at.X, 0, 0, at.Y * spec.size)
		s.Size = UDim2.fromOffset(40, 40)
		s.BackgroundTransparency = 1
		s.Font = Enum.Font.GothamBold
		s.Text = "\u{2726}"
		s.TextColor3 = Color3.fromRGB(255, 255, 255)
		s.TextSize = 26
		s.TextTransparency = 1
		s.ZIndex = 5
		s.Parent = holder
		sparkles[i] = s
	end

	-- name, then rarity. No panel behind either -- that is the whole point.
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "BrainrotName"
	nameLabel.AnchorPoint = Vector2.new(0.5, 0)
	nameLabel.Position = UDim2.new(0.5, 0, 0, spec.size + 6)
	nameLabel.Size = UDim2.fromOffset(spec.size + 160, 40)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = UITheme.Font
	nameLabel.TextSize = 30
	nameLabel.TextColor3 = CF.onDark
	nameLabel.TextScaled = false
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = info.Name
	nameLabel.TextTransparency = 1
	nameLabel.ZIndex = 6
	nameLabel.Parent = holder
	local nameInk = UITheme.inkText(nameLabel, 3)
	nameInk.Transparency = 1

	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Name = "Rarity"
	rarityLabel.AnchorPoint = Vector2.new(0.5, 0)
	rarityLabel.Position = UDim2.new(0.5, 0, 0, spec.size + 48)
	rarityLabel.Size = UDim2.fromOffset(spec.size + 160, 32)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Font = UITheme.Font
	rarityLabel.TextSize = 23
	rarityLabel.TextColor3 = accent
	rarityLabel.Text = string.upper(tostring(info.Rarity or "?"))
	rarityLabel.TextTransparency = 1
	rarityLabel.ZIndex = 6
	rarityLabel.Parent = holder
	local rarityInk = UITheme.inkText(rarityLabel, 2.6)
	rarityInk.Transparency = 1
	rec.rarityLabel = rarityLabel

	table.insert(fades, { nameLabel, "TextTransparency", 0 })
	table.insert(fades, { rarityLabel, "TextTransparency", 0 })
	table.insert(fades, { nameInk, "Transparency", 0 })
	table.insert(fades, { rarityInk, "Transparency", 0 })

	-- fade in
	for _, f in ipairs(fades) do
		TweenService:Create(f[1], TweenInfo.new(FADE), { [f[2]] = f[3] }):Play()
	end

	-- One driver for this reveal, disconnected in teardown. Nothing per-frame
	-- survives the reveal.
	local t = 0
	rec.conn = RunService.RenderStepped:Connect(function(dt)
		t += dt
		if spin then spin(t) end
		if haloStroke then
			haloStroke.Transparency = 0.35 + 0.22 * (0.5 + 0.5 * math.sin(t * 2.1))
		end
		if shimmerGrad then
			shimmerGrad.Offset = Vector2.new(((t / spec.shimmer) % 1) * 2.6 - 1.3, 0)
		end
		for i = 1, #sparkles do
			local k = 0.5 + 0.5 * math.sin(t * 3.1 + i * 1.9)
			sparkles[i].TextTransparency = 1 - k
			sparkles[i].TextSize = 14 + 14 * k
		end
	end)

	live = rec

	-- hold, fade out, tear down
	task.delay(FADE + spec.hold, function()
		if rec.dead or rec.token ~= token then return end
		for _, f in ipairs(fades) do
			local back = (f[2] == "ImageTransparency" or f[2] == "TextTransparency"
				or f[2] == "Transparency" or f[2] == "BackgroundTransparency") and 1 or 0
			TweenService:Create(f[1], TweenInfo.new(FADE), { [f[2]] = back }):Play()
		end
		task.delay(FADE, function()
			if rec.token == token then teardown(rec) end
		end)
	end)

	return {
		skip = function()
			teardown(rec)
		end,
	}
end

return M
```

- [ ] **Step 4: Verify it compiles and every tier renders**

Studio may have cached a stale copy of the module. Run this in the **Client** VM (`datamodel_type = "Client"`, requires Play mode — start Play first with `start_stop_play`):

```lua
local RS = game:GetService("ReplicatedStorage")
local CR = require(RS.Modules.CatchReveal)
local Cfg = require(RS.Modules.BrainrotConfig)
local Rar = require(RS.Modules.RarityConfig)
local plr = game:GetService("Players").LocalPlayer

-- one real brainrot name per tier, taken from the live config
local byTier = {}
for _, e in ipairs(Cfg) do byTier[e.Rarity] = byTier[e.Rarity] or e.Name end

local fails = 0
for _, tier in ipairs(Rar) do
	local nm = byTier[tier.Name]
	if not nm then
		print(("FAIL %s: no brainrot in config"):format(tier.Name)); fails += 1
	else
		local h = CR.play({ Name = nm, Rarity = tier.Name, RarityColor = tier.Color })
		task.wait(0.3)
		local root = plr.PlayerGui:FindFirstChild("CatchRevealUI")
		local rev = root and root:FindFirstChild("Reveal")
		local holder = rev and rev:FindFirstChild("Holder")
		local vp = holder and holder:FindFirstChild("Model")
		local nameOk = holder and holder:FindFirstChild("BrainrotName")
			and holder.BrainrotName.Text == nm
		local rarOk = holder and holder:FindFirstChild("Rarity")
			and holder.Rarity.Text == string.upper(tier.Name)
		if vp and nameOk and rarOk and CR.isPlaying() then
			print(("OK   %-9s %-28s viewport=%dpx"):format(tier.Name, nm, vp.AbsoluteSize.X))
		else
			print(("FAIL %-9s vp=%s name=%s rarity=%s"):format(
				tier.Name, tostring(vp ~= nil), tostring(nameOk), tostring(rarOk)))
			fails += 1
		end
		h.skip()
		task.wait(0.1)
	end
end

-- the spin must actually move the camera
local h = CR.play({ Name = byTier["Rare"], Rarity = "Rare", RarityColor = Color3.new(1,1,1) })
task.wait(0.25)
local vp = plr.PlayerGui.CatchRevealUI.Reveal.Holder:FindFirstChild("Model")
local a = vp.CurrentCamera.CFrame.Position
task.wait(0.6)
local b = vp.CurrentCamera.CFrame.Position
print(((a - b).Magnitude > 0.05) and "OK   spin moves the camera"
	or "FAIL spin is static"); if (a-b).Magnitude <= 0.05 then fails += 1 end
h.skip()

-- missing model must fall back to text, not error
task.wait(0.2)
local ok = pcall(function()
	local h2 = CR.play({ Name = "NoSuchBrainrot_XYZ", Rarity = "Rare", RarityColor = Color3.new(1,1,1) })
	task.wait(0.25)
	local hd = plr.PlayerGui.CatchRevealUI.Reveal.Holder
	assert(hd:FindFirstChild("Model") == nil, "viewport should be absent")
	assert(hd.BrainrotName.Text == "NoSuchBrainrot_XYZ", "name should still show")
	h2.skip()
end)
print(ok and "OK   missing model falls back to text" or "FAIL missing-model fallback")
if not ok then fails += 1 end

-- teardown must leave nothing behind
task.wait(0.3)
local leftover = plr.PlayerGui.CatchRevealUI:FindFirstChild("Reveal")
print((leftover == nil and not CR.isPlaying()) and "OK   teardown leaves nothing"
	or "FAIL teardown leaked"); if leftover then fails += 1 end

print(fails == 0 and "ALL OK" or (fails .. " FAILURES"))
```

Expected: ten `OK` lines and `ALL OK`. Then `get_console_output` and confirm no errors or warnings from `CatchReveal`.

- [ ] **Step 5: Confirm the backpack grid still renders**

`BrainrotThumb.add` was refactored in Step 2, and `BackpackClient` depends on it. In the **Client** VM, open the backpack and count tiles against viewports:

```lua
local plr = game:GetService("Players").LocalPlayer
local bp = plr.PlayerGui:FindFirstChild("BackpackUI")
	or plr.PlayerGui:FindFirstChild("BackpackPanel")
if not bp then print("SKIP no backpack gui found -- open it and re-run") return end
local vp, tiles = 0, 0
for _, d in ipairs(bp:GetDescendants()) do
	if d:IsA("ViewportFrame") then vp += 1 end
	if d:IsA("Frame") and d.Name == "Tile" then tiles += 1 end
end
print(("%s viewports=%d tiles=%d"):format(vp > 0 and "OK  " or "FAIL", vp, tiles))
```

Expected: a non-zero viewport count, matching what the grid showed before the change. If the panel's ScreenGui or tile names differ from the guesses above, find them with `search_game_tree` on `PlayerGui` rather than assuming.

- [ ] **Step 6: Mirror and commit**

Read both installed modules back with `script_read` and write them verbatim to `game-src/CatchReveal.lua` and `game-src/BrainrotThumb.lua`, so the mirrors match what actually shipped rather than what was intended. Add a line to `game-src/README.md` recording both, following the format of the entries already there.

```bash
git add game-src/CatchReveal.lua game-src/BrainrotThumb.lua game-src/README.md
git commit -m "CatchReveal: spinning viewport reveal for bands 1-3"
```

---

### Task 2: Band 4 — real world model behind a locked camera

**Files:**
- Modify: `ReplicatedStorage.Modules.CatchReveal`
- Mirror: `game-src/CatchReveal.lua`

**Interfaces:**
- Consumes: `rec`, `teardown(rec)`, `SPEC`, `SPIN`, `FADE` from Task 1.
- Produces (relied on by Task 3): `buildWorld(rec, spec, info) -> updater?` — spawns the model, locks the camera, returns the per-frame updater or nil if the spot is blocked. Sets `rec.worldModel` (the live Model) and `rec.restore` (called by `teardown`).

- [ ] **Step 1: Add the world path**

`multi_edit` on `game.ReplicatedStorage.Modules.CatchReveal`. Insert before `function M.isPlaying()`:

```lua
-- === Band 4: a real model in the world ===
--
-- The camera does NOT move -- it only stops taking input. Moving it risks
-- landing inside terrain or a building, and a reveal that ruins your view is
-- worse than one that is merely close. A black backdrop part behind the model
-- does the darkening, because a full-screen UI dim would darken the model too:
-- UI always renders above the 3D world.
local WORLD_DIST   = 13   -- studs ahead of the camera
local WORLD_HEIGHT = 7    -- studs tall, whatever the model was authored at
local BACKDROP_AT  = 26   -- studs ahead, behind the model
local BACKDROP_SIZE = 260

local function stripScripts(model)
	-- ReplicatedStorage.BrainrotModels is verified 0 scripts today, but this
	-- pack has carried embedded free-model scripts before and they only run
	-- OUTSIDE Studio, so they can never be caught by testing here.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then d:Destroy() end
	end
end

local function buildWorld(rec, spec, info)
	local cam = workspace.CurrentCamera
	local folder = ReplicatedStorage:FindFirstChild("BrainrotModels")
	local src = folder and folder:FindFirstChild(info.Name)
	if not cam or not src then return nil end

	local origin = cam.CFrame
	local spot = origin * CFrame.new(0, 0, -WORLD_DIST)

	-- If real geometry sits between the camera and the reveal spot the model
	-- would be hidden behind a wall. Rather than shove the camera somewhere it
	-- might not fit, fall back to the viewport path -- a Secret that looks like
	-- a Legendary beats a Secret you cannot see.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local hit = workspace:Raycast(origin.Position, (spot.Position - origin.Position), params)
	if hit then return nil end

	local m = src:Clone()
	stripScripts(m)
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
		end
	end

	-- ScaleTo is ABSOLUTE. Re-measuring an already-scaled model and calling it
	-- again resets to authored size, so always multiply the CURRENT scale.
	local _, ext = m:GetBoundingBox()
	if ext.Y > 0 then
		m:ScaleTo(m:GetScale() * (WORLD_HEIGHT / ext.Y))
	end

	-- Pivot about the bounding-box centre. On these packs the PrimaryPart is an
	-- arbitrary limb, so pivoting on it makes the model wobble off-axis.
	local bcf = m:GetBoundingBox()
	m.PrimaryPart = nil
	m.WorldPivot = CFrame.new(bcf.Position)
	m.Parent = workspace          -- client-created: never replicates
	rec.worldModel = m

	local backdrop = Instance.new("Part")
	backdrop.Name = "CatchRevealBackdrop"
	backdrop.Size = Vector3.new(BACKDROP_SIZE, BACKDROP_SIZE, 1)
	backdrop.CFrame = origin * CFrame.new(0, 0, -BACKDROP_AT)
	backdrop.Anchored = true
	backdrop.CanCollide = false
	backdrop.CanQuery = false
	backdrop.CanTouch = false
	backdrop.CastShadow = false
	backdrop.Material = Enum.Material.SmoothPlastic
	backdrop.Color = Color3.new(0, 0, 0)
	backdrop.Transparency = 1
	backdrop.Parent = workspace
	rec.backdrop = backdrop
	TweenService:Create(backdrop, TweenInfo.new(FADE),
		{ Transparency = 1 - spec.dark }):Play()

	-- Freeze the camera where it already is.
	local savedType = cam.CameraType
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = origin

	rec.restore = function()
		if rec.worldModel then rec.worldModel:Destroy(); rec.worldModel = nil end
		if rec.backdrop then rec.backdrop:Destroy(); rec.backdrop = nil end
		local c = workspace.CurrentCamera
		if c then c.CameraType = savedType end
	end

	-- A camera left Scriptable is unrecoverable without rejoining, so it gets a
	-- second, independent guard on top of teardown -- the same belt-and-braces
	-- as ThrowHandler's flight watchdog.
	task.delay(FADE * 2 + spec.hold + 3, function()
		if not rec.dead then teardown(rec) end
	end)

	return function(t)
		if rec.worldModel and rec.worldModel.Parent then
			rec.worldModel:PivotTo(spot * CFrame.Angles(0, math.rad(SPIN) * t, 0))
		end
	end
end
```

- [ ] **Step 2: Route band 4 through it**

In `M.play`, replace:

```lua
	local spin = buildViewport(rec, spec, info, holder)
```

with:

```lua
	-- Band 4 tries the world first and falls back to the viewport when the spot
	-- is blocked, so a Secret always reveals as SOMETHING.
	local spin
	if band == 4 then
		spin = buildWorld(rec, spec, info)
	end
	if not spin then
		spin = buildViewport(rec, spec, info, holder)
	end
```

And because the world path draws its own backdrop, the UI dim must not double up. Replace:

```lua
	if spec.dark > 0 then
```

with:

```lua
	if spec.dark > 0 and band ~= 4 then
```

- [ ] **Step 3: Give band 4 its own numbers**

Replace the band-4 row of `SPEC`:

```lua
	{ size = 380, hold = 3.8, dark = 0.80, halo = true,  shimmer = 1.8,   sparkle = 5 },
```

with:

```lua
	-- world path: size is the viewport FALLBACK size, used only when the spot
	-- ahead of the camera is blocked
	{ size = 380, hold = 3.8, dark = 0.80, halo = false, shimmer = false, sparkle = 0, world = true },
```

- [ ] **Step 4: Verify camera lock, restore, and cleanup**

Run in the **Client** VM:

```lua
local RS = game:GetService("ReplicatedStorage")
local CR = require(RS.Modules.CatchReveal)
local Cfg = require(RS.Modules.BrainrotConfig)
local fails = 0

local secret
for _, e in ipairs(Cfg) do if e.Rarity == "Secret" then secret = e.Name break end end

local function countLeftovers()
	local n = 0
	for _, d in ipairs(workspace:GetChildren()) do
		if d.Name == "CatchRevealBackdrop" or d.Name == secret then n += 1 end
	end
	return n
end

local cam = workspace.CurrentCamera
local before = cam.CameraType

local h = CR.play({ Name = secret, Rarity = "Secret", RarityColor = Color3.fromRGB(255,90,220) })
task.wait(0.4)
local lockedOk = (cam.CameraType == Enum.CameraType.Scriptable)
local modelOk = workspace:FindFirstChild(secret) ~= nil
local backOk = workspace:FindFirstChild("CatchRevealBackdrop") ~= nil
print(lockedOk and "OK   camera locked" or "FAIL camera not locked")
print(modelOk and "OK   world model spawned" or "FAIL no world model (spot blocked? face open water)")
print(backOk and "OK   backdrop spawned" or "FAIL no backdrop")
if not (lockedOk and modelOk and backOk) then fails += 3 end

-- spin must move the model
local mdl = workspace:FindFirstChild(secret)
local p1 = mdl and mdl:GetPivot().LookVector or Vector3.zero
task.wait(0.5)
local p2 = mdl and mdl.Parent and mdl:GetPivot().LookVector or p1
print(((p1 - p2).Magnitude > 0.02) and "OK   world model spins" or "FAIL world model static")
if (p1 - p2).Magnitude <= 0.02 then fails += 1 end

-- skip mid-reveal must restore everything at once
h.skip()
task.wait(0.2)
print((cam.CameraType == before) and "OK   camera restored on skip" or "FAIL camera stuck")
print((countLeftovers() == 0) and "OK   world cleaned on skip" or "FAIL world leaked")
if cam.CameraType ~= before or countLeftovers() > 0 then fails += 2 end

-- and a full natural run must restore too
local h2 = CR.play({ Name = secret, Rarity = "Secret", RarityColor = Color3.fromRGB(255,90,220) })
task.wait(4.6)
print((cam.CameraType == before) and "OK   camera restored naturally" or "FAIL camera stuck after run")
print((countLeftovers() == 0) and "OK   world cleaned naturally" or "FAIL world leaked after run")
if cam.CameraType ~= before or countLeftovers() > 0 then fails += 2 end
h2.skip()

print(fails == 0 and "ALL OK" or (fails .. " FAILURES"))
```

Expected: eight `OK` lines and `ALL OK`. Stand on the dock facing open water for this — facing the lodge exercises the raycast fallback instead, which is a separate check in Task 5.

- [ ] **Step 5: Mirror and commit**

Read the module back and rewrite `game-src/CatchReveal.lua`.

```bash
git add game-src/CatchReveal.lua
git commit -m "CatchReveal: band 4 world model, locked camera, watchdog restore"
```

---

### Task 3: Mutations across both paths

**Files:**
- Modify: `ReplicatedStorage.Modules.CatchReveal`
- Mirror: `game-src/CatchReveal.lua`

**Interfaces:**
- Consumes: `MutationConfig.Color(name) -> Color3?`, `MutationConfig.Rarity(name) -> number`, `MutationFX.apply(model, mutationName) -> boolean`, plus `rec`, `accent`, `haloStroke`, `rarityLabel` from Tasks 1–2.
- Produces: no new public API. Band 4 gains real `MutationFX`; bands 1–3 gain a tinted halo and a mutation-prefixed name.

- [ ] **Step 1: Require the two mutation modules**

`multi_edit`, after the `UITheme` require:

```lua
local UITheme = require(ReplicatedStorage.Modules.UITheme)
```
→
```lua
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)
local MutationFX = require(ReplicatedStorage.Modules.MutationFX)

-- "None" and "" both mean no mutation in this codebase; normalise once.
local function mutationOf(info)
	local m = info.Mutation
	if type(m) ~= "string" or m == "" or m == "None" then return nil end
	return m
end
```

- [ ] **Step 2: Apply MutationFX on the world model**

In `buildWorld`, after `rec.worldModel = m`, insert:

```lua
	-- The payoff for the hybrid. pcall because a bad mutation must never cost
	-- the player the reveal -- showing the creature matters more than tinting it.
	local mut = mutationOf(info)
	if mut then pcall(MutationFX.apply, m, mut) end
```

- [ ] **Step 3: Tint the halo and prefix the name on bands 1–3**

In `M.play`, replace:

```lua
	local accent = typeof(info.RarityColor) == "Color3" and info.RarityColor
		or Color3.fromRGB(190, 190, 190)
```

with:

```lua
	local accent = typeof(info.RarityColor) == "Color3" and info.RarityColor
		or Color3.fromRGB(190, 190, 190)

	-- Bands 1-3 are viewports, where ParticleEmitters and Highlight render
	-- nothing, so MutationFX cannot appear. The mutation is carried by the halo
	-- colour and the name prefix instead.
	local mut = mutationOf(info)
	local haloColour = accent
	if mut then
		local mc = Mutations.Color(mut)
		if typeof(mc) == "Color3" then haloColour = mc end
	end
```

Then in the halo block replace `haloStroke.Color = accent` with `haloStroke.Color = haloColour`.

And replace `nameLabel.Text = info.Name` with:

```lua
	nameLabel.Text = mut and (mut .. " " .. info.Name) or info.Name
```

- [ ] **Step 4: Cycle the rarity label for Secret and God**

The spec's "rainbow" for band 4. In the `RenderStepped` handler, before `end)`, insert:

```lua
		-- Band 4's rainbow. There is no card or border in a world reveal for a
		-- cycling colour to live on, so the rarity label carries it -- the same
		-- one-property technique RarityFX uses on Secret/God tiles.
		if band == 4 then
			rarityLabel.TextColor3 = Color3.fromHSV((t * 0.3) % 1, 0.82, 1)
		end
```

- [ ] **Step 5: Verify**

Run in the **Client** VM:

```lua
local RS = game:GetService("ReplicatedStorage")
local CR = require(RS.Modules.CatchReveal)
local Cfg = require(RS.Modules.BrainrotConfig)
local Mut = require(RS.Modules.MutationConfig)
local plr = game:GetService("Players").LocalPlayer
local fails = 0

local rare, secret
for _, e in ipairs(Cfg) do
	if e.Rarity == "Rare" and not rare then rare = e.Name end
	if e.Rarity == "Secret" and not secret then secret = e.Name end
end

-- band 2: name prefixed, halo takes the MUTATION colour not the tier colour
local h = CR.play({ Name = rare, Rarity = "Rare",
	RarityColor = Color3.fromRGB(60,140,255), Mutation = "Angel" })
task.wait(0.4)
local holder = plr.PlayerGui.CatchRevealUI.Reveal.Holder
local nameOk = holder.BrainrotName.Text == ("Angel " .. rare)
local halo = holder:FindFirstChild("Halo")
local stroke = halo and halo:FindFirstChildOfClass("UIStroke")
local want = Mut.Color("Angel")
local tintOk = stroke and (stroke.Color - want).Magnitude < 0.02
print(nameOk and "OK   name carries the mutation prefix" or "FAIL name prefix")
print(tintOk and "OK   halo takes the mutation colour" or "FAIL halo colour")
if not (nameOk and tintOk) then fails += 2 end
h.skip(); task.wait(0.2)

-- band 4: real MutationFX instances on the real model
local h2 = CR.play({ Name = secret, Rarity = "Secret",
	RarityColor = Color3.fromRGB(255,90,220), Mutation = "Angel" })
task.wait(0.5)
local mdl = workspace:FindFirstChild(secret)
local fx = 0
if mdl then
	for _, d in ipairs(mdl:GetDescendants()) do
		if d.Name == "MutationLight" or d.Name == "MutationAura"
		or d.Name == "MutationMotes" or d.Name == "MutationGlow" then fx += 1 end
	end
end
print((fx > 0) and ("OK   MutationFX applied (" .. fx .. " instances)")
	or "FAIL no MutationFX on the world model")
if fx == 0 then fails += 1 end

-- and the rainbow rarity label must actually cycle
local lbl = plr.PlayerGui.CatchRevealUI.Reveal.Holder.Rarity
local c1 = lbl.TextColor3; task.wait(0.5); local c2 = lbl.TextColor3
print(((c1 - c2).Magnitude > 0.05) and "OK   rarity label cycles on band 4"
	or "FAIL rarity label static")
if (c1 - c2).Magnitude <= 0.05 then fails += 1 end
h2.skip()

-- an unknown mutation must not break the reveal
task.wait(0.2)
local ok = pcall(function()
	local h3 = CR.play({ Name = rare, Rarity = "Rare",
		RarityColor = Color3.new(1,1,1), Mutation = "NotARealMutation" })
	task.wait(0.3); h3.skip()
end)
print(ok and "OK   unknown mutation survives" or "FAIL unknown mutation threw")
if not ok then fails += 1 end

print(fails == 0 and "ALL OK" or (fails .. " FAILURES"))
```

Expected: five `OK` lines and `ALL OK`.

- [ ] **Step 6: Mirror and commit**

```bash
git add game-src/CatchReveal.lua
git commit -m "CatchReveal: mutations - MutationFX on band 4, tinted halo on 1-3"
```

---

### Task 4: Wire it to real catches and retire the card

**Files:**
- Create: `StarterPlayer.StarterPlayerScripts.CatchRevealClient` (LocalScript)
- Modify: `StarterPlayer.StarterPlayerScripts.ClientMain` (two edits)
- Mirror: `game-src/CatchRevealClient.lua`, `game-src/ClientMainCatchPatch.txt`

**Interfaces:**
- Consumes: `CatchReveal.play`, and the existing `ReplicatedStorage.Remotes.ThrowResult` payload — `{Distance, BrainrotName, Rarity, RarityColor, CashPerSecond, Mutation, MutationMult, Perfect, Serial, MintedAt, Exists}`.
- Produces: `shouldReveal(result) -> boolean`, the phase-2 seam.

- [ ] **Step 1: Create the client script**

`multi_edit`, `file_path = "game.StarterPlayer.StarterPlayerScripts.CatchRevealClient"`, `className = "LocalScript"`:

```lua
-- CatchRevealClient: turns a catch into a reveal.
--
-- Deliberately thin. All the presentation lives in CatchReveal; this only
-- decides WHETHER to show one, which is exactly the decision the phase-2 Robux
-- upgrade needs to change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CatchReveal = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CatchReveal"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local throwResult = remotes:WaitForChild("ThrowResult")

-- PHASE 2 SEAM: the purchasable "skip the animation" upgrade replaces this body
-- with a gamepass-ownership check plus the player's chosen rarities.
--
-- Skipping an ANIMATION is a pure presentation choice, so the client may own it
-- -- a client that lies about it gains nothing. The auto-sell half of that
-- upgrade is NOT the same and must never live here: a client that can say "sell
-- this catch" can say it about anything. Auto-sell belongs server-side in
-- ThrowHandler.revealCatch behind a verified MarketplaceService check.
local function shouldReveal(_result)
	return true
end

throwResult.OnClientEvent:Connect(function(result)
	if type(result) ~= "table" or type(result.BrainrotName) ~= "string" then return end
	if not shouldReveal(result) then return end

	-- pcall: a broken reveal must never break the catch that produced it.
	pcall(CatchReveal.play, {
		Name = result.BrainrotName,
		Rarity = result.Rarity,
		RarityColor = result.RarityColor,
		Mutation = result.Mutation,
	})
end)
```

- [ ] **Step 2: Re-read `ClientMain` before editing it**

`ClientMain` is shared and the collaborator has live-edited it before. Run `script_read` on `game.StarterPlayer.StarterPlayerScripts.ClientMain` around the `ThrowResult` handler and `celebrateCatch` and confirm the two anchor strings below still match exactly. Do not trust line numbers from this plan.

- [ ] **Step 3: Stop showing the old card**

`multi_edit` on `ClientMain`. Replace:

```lua
	rarityLabel.Text = string.upper(result.Rarity)
	rarityLabel.TextColor3 = result.RarityColor
	nameLabel.Text = result.BrainrotName
	infoLabel.Text = ("Distance: %dm  |  +%s/s"):format(result.Distance, formatNumber(result.CashPerSecond))

	celebrateCatch(result.Rarity, result.Mutation)

	resultFrame.Visible = true
```

with:

```lua
	-- The card is retired: CatchRevealClient now shows the caught brainrot
	-- itself, spinning, instead of describing it in text. The frame and its
	-- styling are left in place so this is a one-block revert.
	celebrateCatch(result.Rarity, result.Mutation)
	if true then return end

	rarityLabel.Text = string.upper(result.Rarity)
	rarityLabel.TextColor3 = result.RarityColor
	nameLabel.Text = result.BrainrotName
	infoLabel.Text = ("Distance: %dm  |  +%s/s"):format(result.Distance, formatNumber(result.CashPerSecond))

	resultFrame.Visible = true
```

- [ ] **Step 4: Suppress the world FX under a band-4 takeover**

Replace in `celebrateCatch`:

```lua
	local idx = rarityIndexByName[rarityName] or 1
```

with:

```lua
	local idx = rarityIndexByName[rarityName] or 1
	-- Band 4 locks the camera onto a world model, so the pillar spawned around
	-- the character would be off-screen and a shake would fight the lock.
	if rarityName == "Secret" or rarityName == "God" then return end
```

- [ ] **Step 5: Verify against real throws**

Enter Play mode, walk onto the dock (inside `Workspace.GameWorld.ThrowZone`, and a plot must be claimed or `ThrowRequest` is silently refused), and throw. Then run in the **Client** VM:

```lua
local plr = game:GetService("Players").LocalPlayer
local gui = plr.PlayerGui
print(gui:FindFirstChild("CatchRevealUI") and "OK   reveal gui installed" or "FAIL no reveal gui")
local main = gui:FindFirstChild("MainUI")
local rf = main and main:FindFirstChild("ResultFrame")
print((rf == nil or rf.Visible == false) and "OK   old card stays hidden" or "FAIL card still showing")
```

Expected: both `OK`, a spinning brainrot on every throw, and `get_console_output` clean.

- [ ] **Step 6: Mirror and commit**

Write `game-src/CatchRevealClient.lua` from the installed source, and record the two `ClientMain` edits in `game-src/ClientMainCatchPatch.txt` following the `IndexPatch.txt` precedent.

```bash
git add game-src/CatchRevealClient.lua game-src/ClientMainCatchPatch.txt
git commit -m "Wire catch reveal to ThrowResult; retire the result card"
```

---

### Task 5: Live verification sweep and tuning

The spec is explicit that the numbers are starting points and that verification is by looking, not by reading code back. This task is where the reveal actually gets judged.

**Files:**
- Modify: `ReplicatedStorage.Modules.CatchReveal` (tuning constants only)
- Mirror: `game-src/CatchReveal.lua`

- [ ] **Step 1: Force one catch per tier through the real throw path**

`ThrowHandler` carries an attribute-driven test hook — **no server code change is needed, which is why this respects the no-server-changes constraint.** Arm it from the **Server** VM, then throw:

```lua
local ServerStorage = game:GetService("ServerStorage")
ServerStorage:SetAttribute("ForceNextCatch", "Secret Pete")   -- any BrainrotConfig name
ServerStorage:SetAttribute("ForceNextCatchFor", "prohacks_sorry")  -- optional; blank = anyone
```

It is **consumed exactly once** — the attribute clears the instant it fires, so re-arm before each throw. An unknown name warns and falls through to a normal catch rather than failing loudly, so read the output: `[ThrowHandler] TEST override consumed: <player> caught <name> (<tier>)` is the confirmation it actually fired.

Throwing requires standing in `Workspace.GameWorld.ThrowZone` **and** having a claimed plot — otherwise `ThrowRequest` is silently refused and nothing happens at all.

Watch each of the eight reveals and judge: is the model framed well, is the spin speed right, is the text readable against the world behind it.

- [ ] **Step 1b: Fix the band-4 framing so the takeover actually reads**

Added 2026-07-27 after live screenshots. Two problems, both consequences of this plan's "the camera does not move, the backdrop sits behind the model" design — neither is an implementation defect, and neither shows up in any measurement:

1. **The player's own character stands between the camera and the model.** The model is placed at camera→character distance plus clearance, so the avatar is always nearer the camera than the reveal. On this account the `Tarantula` accessory (7.99 × 4.77 × 7.74 studs) covers the model's middle.
2. **The backdrop darkens nothing.** It sits *behind* the model, so all scenery nearer than the model stays fully lit. Standing near the shop, the reveal reads as a bright ordinary scene with a creature in it — not the takeover the spec approved.

The approved spec says Secret and God "dim harder" and take over the screen. The current build does not deliver that, so this is finishing the approved design, not changing it.

**Fix to implement and then judge by eye:** invert the arrangement. Put the model **nearer the camera than the character** (~6 studs) and the backdrop **between the model and the character** (~10 studs). The backdrop then occludes the player *and* the world in one move, the camera still never moves, and nothing can stand in front of the reveal.

Constraints that must survive the change:
- The line-of-sight check still runs, still excludes the character, still fails closed.
- Model height must scale with its distance so on-screen size is unchanged.
- The backdrop must stay between the model and the character at every distance.
- Teardown, camera restore and the watchdog are untouched.

**Verify visually, not numerically** — the numbers were right the whole time this was broken. Take a screenshot of a Secret reveal before and after and compare them.

- [ ] **Step 2: Check the band-4 raycast fallback rate**

Stand where a player actually stands — on the dock, facing the lake — and force several Secret catches. Then repeat facing the lodge and the shop. Record how often `buildWorld` returns nil and drops to the viewport. If it fires from normal dock positions, raise `WORLD_DIST` or move the spot upward before accepting the design.

- [ ] **Step 3: Rapid catches**

Force two catches within a second. The newer reveal must survive and the older teardown must not kill it. On a band-4 → band-4 overlap, confirm the camera still ends up restored.

- [ ] **Step 4: Death during a reveal**

Force a Secret catch, then reset the character mid-reveal (`plr.Character.Humanoid.Health = 0` from the Client VM). Camera must restore and no model or backdrop may survive in `workspace`.

- [ ] **Step 5: FPS A/B in one session**

Measure FPS with no reveal, then during a band-3 and a band-4 reveal, all within the same Studio session — absolute numbers drift badly between sessions (the same unchanged scene has measured 15.1 and 29.0 minutes apart), so only same-session comparisons mean anything.

- [ ] **Step 6: Tune and commit**

Adjust `SPIN`, the `hold` values, `size`, `dark`, `WORLD_HEIGHT` and `WORLD_DIST` by eye against the real thing. Then re-run the Task 1–3 verification scripts to confirm nothing regressed.

```bash
git add game-src/CatchReveal.lua
git commit -m "Tune catch reveal timings and framing against live play"
```

- [ ] **Step 7: Report to the user**

Screenshots of a low-tier and a Secret reveal, the FPS A/B numbers, and an explicit list of anything left unresolved — particularly the raycast fallback rate, since that is the one number that could send the band-4 design back for a rethink.

---

## Self-Review

**Spec coverage.** Every section of `docs/specs/2026-07-27-catch-reveal-design.md` maps to a task: the ladder → Tasks 1–3; viewport bands → Task 1; world band → Task 2; mutations by band → Task 3; the retired card and suppressed world FX → Task 4; the `shouldReveal` seam → Task 4 Step 1; every row of the failure-mode table → Task 1 (missing model, newest-wins), Task 2 (camera restore, watchdog, world cleanup), Task 3 (`pcall` on `MutationFX`); the whole Verification section → Task 5.

**Deviations from the spec, both deliberate:**
1. The spec says band 3 adds "rays behind + sparkles". The plan uses **shimmer + sparkles** instead — `RarityFX`'s established vocabulary, already tuned and already what the backpack does for Legendary and Mythic. Rays would have been a new visual idea invented at implementation time. Flagged rather than silently substituted.
2. The spec says band 4 dims the screen. The plan uses a **black backdrop part in the world**, not a UI dim, because UI always renders above the 3D world and a full-screen dim frame would darken the reveal model along with everything else. This is a correctness fix, not a preference.
3. The spec says the reveal touches no shared module. Task 1 Step 2 makes a small **additive change to `BrainrotThumb`** — extracting the bounding-box framing into `M.framing()` and exposing `M.DEFAULT_DIR` — rather than copying six lines into `CatchReveal` where the two copies would drift. User decision, taken at pre-flight on 2026-07-27. `add`'s behaviour is unchanged, and Task 1 Step 5 verifies the backpack grid still renders.

**Placeholder scan:** none. Every code step carries the real source; every test step carries a runnable script with explicit expected output.

**Type consistency:** `M.play(info)` takes `{Name, Rarity, RarityColor, Mutation}` in Tasks 1, 3 and 4 alike. `handle:skip()` is used in every verification script as defined in Task 1. `teardown(rec)` is defined in Task 1 and called from Task 2's watchdog. `rec.restore` is set in Task 2 and consumed by Task 1's `teardown`, which already calls it — that ordering is why `teardown` was written with the `restore` hook in Task 1 rather than added later. `buildWorld` returns an updater with the same `(t)` signature as `buildViewport`'s, so `M.play` treats them interchangeably.
