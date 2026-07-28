# Wheel Candy Restyle — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the daily spin wheel look like the candy/Pet-Sim reference instead of "too basic" — per `docs/specs/2026-07-27-wheel-candy-restyle-design.md`. Phase 1 only: client-side visuals, per-segment odds, a details panel and a Fast Spin toggle.

**Architecture:** A new `UITheme.Candy` token table plus additive helpers sits beside the existing `Camp` tokens; nothing currently on screen changes. `WheelClient` opts in. The existing wheel is **enhanced, not rewritten** — it is already server-authoritative and already draws its wedges correctly; what it lacks is a pointer, depth, odds, and a satisfying landing.

**Tech Stack:** Roblox Luau, live Studio place via roblox-studio MCP (`multi_edit` to install, `execute_luau` to drive, `screen_capture` to judge), repo mirrors in `game-src/`.

## Global Constraints

- **Phase 1 touches no server file, no remote, and no `WheelConfig` value.** Odds, payouts, cooldown and boosts are unchanged.
- **The result stays server-authoritative.** `WheelHandler` rolls and pays; the client animates *to* the broadcast slot. The client must never choose the landing segment. `WheelClient`'s own header says "This script decides NOTHING" — keep that true.
- **Displayed odds must be derived, never hardcoded:** `SLOTS[i].Weight / WheelConfig.TOTAL_WEIGHT`. `TOTAL_WEIGHT` is 100 today, so weights read as percentages, but do the division anyway so it survives a re-weighting.
- **`UITheme.Camp` and every existing caller must be untouched.** Candy is additive. This is what makes "just revert it back" a one-file revert.
- The candy display font token lives in `UITheme.Candy`, **not** `UITheme.Font` (which is `Cartoon`, the cafe face). Never hardcode `Enum.Font.*` at a call site.
- `Rotation` on a `GuiObject` pivots about its **centre, not its AnchorPoint** — every radial piece is centred at half its length along its own ray. This is why the existing wedge fan works; do not "simplify" it.
- **Pixel values from the handoff are starting points, not targets.** They come from a 1920-wide web mockup; a 6px `UIStroke` at Roblox scale is heavy. Tune by eye. The relationships must hold: thick outline, hard unblurred shadow, generous radius.
- Studio may be in Play mode. `multi_edit` needs **Edit**; seeing anything needs **Play**. Leave Studio in Edit. Never save or publish.
- **In Play mode `script_read`/`script_grep` silently address the Client DataModel** and the Edit datamodel is unavailable. Check `get_studio_state` first.
- **`script_grep` line numbers do not match `script_read`'s.** Locate edits by exact anchor string only.
- Verification is **visual**. Two bugs in the previous feature had entirely correct numbers while the screen was wrong.

## File Structure

| File | Responsibility |
|---|---|
| `ReplicatedStorage.Modules.UITheme` (modify, additive) | New `M.Candy` token table + `M.chunkyShadow`, `M.candyPanel`, `M.candyButton`. No existing member changes. |
| `StarterPlayer.StarterPlayerScripts.WheelClient` (modify) | Opts into candy: panel shell, pointer, icon chips, odds, spin easing, details panel, Fast Spin. |
| `game-src/UITheme.lua`, `game-src/WheelClient.lua` (mirrors) | Commit-time mirrors; both already exist. |

---

### Task 1: `UITheme.Candy` tokens and helpers

**Files:**
- Modify: `ReplicatedStorage.Modules.UITheme` (additive only)
- Mirror: `game-src/UITheme.lua`

**Interfaces produced** (relied on by Tasks 2–3):
- `M.Candy` — table with at least: `ink`, `panelTop`, `panelBot`, `shadow`, `green1/green2`, `red1/red2`, `gold1/gold2`, `font`, `radius`, `stroke`
- `M.chunkyShadow(guiObject, offsetY) -> Frame` — solid, unblurred offset shadow behind the object
- `M.candyPanel(frame)` — panel shell: gradient, radius, ink stroke, shadow
- `M.candyButton(btn, c1, c2)` — gradient button with ink stroke, shadow and press feel

- [ ] **Step 1: Confirm Edit mode**

`get_studio_state` → expect `Edit`. If Play, tell the user before stopping it.

- [ ] **Step 2: Add the token table and helpers**

`multi_edit` on `game.ReplicatedStorage.Modules.UITheme`. Add near the existing `Camp` block — **read the file first and match its comment style**. Values from the spec's token table:

```lua
-- ===================================================================
-- CANDY style pack (2026-07-27). A SECOND palette living beside Camp,
-- from the user's design handoff (docs/design-handoff, build from v3):
-- bright Pet-Sim treatment -- white panels, comic-thick ink outlines,
-- and hard unblurred offset shadows.
--
-- Deliberately ADDITIVE. Camp and all 12 of its callers are untouched,
-- so nothing on screen changes until something opts in. That is what
-- makes reverting this a one-file revert rather than unpicking the
-- five-stage cafe restyle.
-- ===================================================================
local CANDY = {
	ink       = Color3.fromRGB(16, 19, 31),      -- #10131f, on everything
	panelTop  = Color3.fromRGB(255, 255, 255),
	panelBot  = Color3.fromRGB(207, 224, 245),   -- #cfe0f5
	shadow    = Color3.fromRGB(10, 13, 22),      -- #0a0d16, SOLID, never blurred
	green1    = Color3.fromRGB(163, 255, 79),
	green2    = Color3.fromRGB(61, 158, 24),
	red1      = Color3.fromRGB(255, 92, 122),
	red2      = Color3.fromRGB(163, 18, 58),
	gold1     = Color3.fromRGB(255, 230, 128),
	gold2     = Color3.fromRGB(224, 140, 0),
	onDark    = Color3.fromRGB(255, 255, 255),
	-- The handoff specifies Luckiest Guy, which Roblox does not have.
	-- FredokaOne is the nearest chunky rounded face. Kept HERE rather than
	-- on M.Font so the cafe face (Cartoon) is unaffected.
	font      = Enum.Font.FredokaOne,
	radius    = 26,    -- panels; chips use ~16
	stroke    = 4,     -- starting point -- the handoff's 6px is from a
	                   -- 1920-wide web mockup and reads heavy at Roblox scale
}
M.Candy = CANDY
```

Then the three helpers. `chunkyShadow` is the load-bearing one — Roblox has no `box-shadow`, so it is a solid offset Frame *behind* the object:

```lua
-- The detail that makes the reference read as a toy: a HARD offset shadow,
-- no blur. Drawn as a plain Frame behind the object, matching its corner
-- radius. Parented to the object's PARENT (not the object) so it cannot be
-- clipped by ClipsDescendants and cannot inherit a gradient.
function M.candyShadow(o, offsetY, radius)
	offsetY = offsetY or 8
	local sh = Instance.new("Frame")
	sh.Name = "CandyShadow"
	sh.BackgroundColor3 = CANDY.shadow
	sh.BorderSizePixel = 0
	sh.Size = o.Size
	sh.Position = o.Position + UDim2.fromOffset(0, offsetY)
	sh.AnchorPoint = o.AnchorPoint
	sh.ZIndex = math.max(1, o.ZIndex - 1)
	sh.Parent = o.Parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or CANDY.radius)
	c.Parent = sh
	return sh
end

function M.candyPanel(f, radius)
	f.BackgroundColor3 = CANDY.panelTop
	f.BorderSizePixel = 0
	M.corner(f, radius or CANDY.radius)
	M.gradient(f, CANDY.panelTop, CANDY.panelBot, 90)
	local s = Instance.new("UIStroke")
	s.Color = CANDY.ink
	s.Thickness = CANDY.stroke
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = f
	return f
end

function M.candyButton(b, c1, c2, radius)
	b.BackgroundColor3 = c1
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.TextColor3 = CANDY.onDark
	b.Font = CANDY.font
	M.corner(b, radius or 18)
	M.gradient(b, c1, c2, 90)
	local s = Instance.new("UIStroke")
	s.Color = CANDY.ink
	s.Thickness = CANDY.stroke
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = b
	-- a gradient multiplies TEXT as well as background and multiply can only
	-- darken, so a light label needs its own ink outline to survive
	M.inkText(b, 2.5)
	return b
end
```

⚠️ `M.candyShadow` sizes and positions itself from the object **at call time**. If a caller resizes the object afterwards the shadow will not follow — call it last, or reposition the shadow too. Note this at the call sites.

- [ ] **Step 3: Prove it is additive**

Run in the **Edit** VM:

```lua
local T = require(game:GetService("ReplicatedStorage").Modules.UITheme)
local want = {"Palette","Camp","Font","GlyphFont","corner","stroke","gradient","gloss",
	"medallion","styleButton","stylePanel","styleHeader","styleClose","campPanel",
	"campButton","ink","inkText","sunburst","accentCard","accentFill","headerBar",
	"ribbon","closeGlyph"}
local missing = {}
for _, k in ipairs(want) do if T[k] == nil then table.insert(missing, k) end end
local campWant = {"ink","panelTop","panelBot","cardTop","cardBot","cream","muted",
	"onDark","wood1","wood2","amber1","pine1","pine2"}
local campMissing = {}
for _, k in ipairs(campWant) do
	if T.Camp == nil or T.Camp[k] == nil then table.insert(campMissing, k) end
end
local newOk = T.Candy and T.candyPanel and T.candyButton and T.candyShadow
print(("old members missing: [%s]  camp keys missing: [%s]  candy present: %s")
	:format(table.concat(missing, ","), table.concat(campMissing, ","), tostring(newOk ~= nil)))
print(("Camp.ink still %s | Candy.ink %s | Font %s | Candy.font %s")
	:format(tostring(T.Camp.ink), tostring(T.Candy.ink), tostring(T.Font), tostring(T.Candy.font)))
```

Expected: both "missing" lists empty, candy present true, `Font` still `Cartoon` and `Candy.font` `FredokaOne`. **If any existing member is missing, stop — the change was not additive.**

- [ ] **Step 4: Mirror and commit**

Read the module back and rewrite `game-src/UITheme.lua`.

```bash
git add game-src/UITheme.lua
git commit -m "UITheme: additive Candy token set and helpers"
```

---

### Task 2: The wheel face — pointer, depth, icon chips, odds

**Files:**
- Modify: `StarterPlayer.StarterPlayerScripts.WheelClient`
- Mirror: `game-src/WheelClient.lua`

**Interfaces consumed:** `UITheme.Candy`, `M.candyPanel`, `M.candyButton`, `M.candyShadow` from Task 1; `WheelConfig.SLOTS`, `.TOTAL_WEIGHT`.

- [ ] **Step 1: Read the file first**

`script_read` the whole of `WheelClient` (557 lines). It is **already server-authoritative and already draws its wedges correctly** as a fan of bars inside a circular mask — do not rewrite that. Identify: the shell/root construction, the wedge builder, the spin routine, and the result toast. Match every edit by exact anchor string.

- [ ] **Step 2: Candy shell**

Apply `UITheme.candyPanel` to the wheel's main panel and `candyShadow` behind it. Restyle the title to `Candy.font` with an ink outline. Keep the existing proximity open/close behaviour, `DisplayOrder`, and the dim behind the wheel — only appearance changes.

- [ ] **Step 3: Add the pointer**

The wheel has **none**, and its absence is a large part of why it reads flat — nothing marks where the result lands. Add a downward-pointing marker at the top of the wheel, above the rim, in `Candy.gold1/gold2` with an ink stroke and its own shadow. It must sit above the wedges in ZIndex and must line up with the angle the spin routine treats as "landed" — **read the spin maths before choosing the angle rather than assuming 12 o'clock**.

- [ ] **Step 4: Icon chips and odds per segment**

Each slot currently shows a bare emoji. Put it in a rounded gradient chip (radius ~16, ink stroke) so it reads as an object rather than loose text. Under the value, add the odds:

```lua
local pct = (slot.Weight / WheelConfig.TOTAL_WEIGHT) * 100
local oddsText = (pct >= 10 and ("%d%%"):format(pct + 0.5))
	or (pct >= 1 and ("%.0f%%"):format(pct))
	or ("%.2f%%"):format(pct)
```

Derived, never hardcoded, so a re-weighting cannot make the display lie. Expect 35 / 25 / 15 / 15 / 9 / 1 percent today.

- [ ] **Step 5: Verify visually**

Enter Play, walk into the wheel's ring so it opens by its real proximity trigger, and `screen_capture`. Confirm: pointer visible and aligned, six segments each showing value and odds, chips reading as objects, panel showing the hard offset shadow. **Judge by eye — this task's whole purpose is appearance.**

- [ ] **Step 6: Mirror and commit**

```bash
git add game-src/WheelClient.lua
git commit -m "Wheel: candy shell, pointer, icon chips, per-segment odds"
```

---

### Task 3: Spin feel, details panel, Fast Spin

**Files:**
- Modify: `StarterPlayer.StarterPlayerScripts.WheelClient`
- Mirror: `game-src/WheelClient.lua`

- [ ] **Step 1: Spin easing and landing pop**

The current spin uses `SPIN_T = 6.2`, `TURNS = 9`. Replace the motion with a long **ease-out that decelerates and settles** onto the pointer, then a **landing pop** on the winning wedge (brief scale/brightness kick). ⚠️ **Do not change which slot wins** — the server broadcasts it and the animation must land on that slot. Verify the landed wedge equals the broadcast slot across several spins.

- [ ] **Step 2: Details panel**

A panel **beside the wheel** listing all six slots **rarest-first**, each row: icon chip, payout, exact odds. Built from `WheelConfig`, never hardcoded. On a narrow viewport it must **collapse below the wheel rather than overlap it** — size with scale-relative widths, not fixed pixels.

- [ ] **Step 3: Fast Spin toggle**

A candy toggle that shortens the spin. **Client-local only — no server call, no data field.** It resets on rejoin, which is acceptable for a comfort setting and avoids a schema migration in a shared file.

- [ ] **Step 4: Verify**

Screenshots of: mid-spin, a landed result, the details panel, Fast Spin off and on. Plus:

```lua
-- odds shown must equal the config
local W = require(game:GetService("ReplicatedStorage").Modules.WheelConfig)
for i, s in ipairs(W.SLOTS) do
	print(("%-12s weight=%3d -> %.2f%%"):format(s.Name, s.Weight, s.Weight / W.TOTAL_WEIGHT * 100))
end
```

Confirm every figure on screen matches, `get_console_output` is clean, and the landed segment matched the server across at least 3 spins.

- [ ] **Step 5: Mirror and commit**

```bash
git add game-src/WheelClient.lua
git commit -m "Wheel: settle-and-pop spin, details panel, Fast Spin toggle"
```

---

### Task 4: Tune by eye

- [ ] **Step 1** — With the whole thing on screen, tune `Candy.stroke`, `candyShadow` offsets and radii. The handoff's 6px stroke is from a 1920-wide web mockup and will likely read heavy; trust the screenshot over the number.
- [ ] **Step 2** — Check the wheel at a narrow viewport (`resize_window` or a small Studio window): details panel must not overlap the wheel.
- [ ] **Step 3** — Confirm the candy panel does not clash badly against the cafe world behind it. If it does, say so plainly — that is exactly the risk the user accepted with "if we don't like it just revert it back", and it is better reported than hidden.
- [ ] **Step 4** — Re-run Task 1 Step 3's additive check to confirm nothing regressed, mirror, commit.

## Self-Review

**Spec coverage.** Tokens and helpers → Task 1. Panel shell, pointer, icon chips, per-segment odds → Task 2. Spin feel, details panel, Fast Spin → Task 3. Tuning and the responsive rule → Task 4. Server-authority, derived-odds and additive-Candy constraints appear in Global Constraints and are re-asserted at the steps that could violate them. Phase 2 (buyable spins, `ProcessReceipt` registry, `WheelSpins`) is deliberately **not** in this plan — it is a separate phase in the spec and is blocked on a product id.

**Placeholder scan:** none. Every code step carries real source; every verification step carries a runnable check with expected output.

**Type consistency:** `M.candyShadow` is the name used in Task 1's code, Task 1's verification, Task 2 Step 2 and Task 4 — the spec's prose called it "chunkyShadow", and **`candyShadow` is the name that ships**. `M.Candy` (capital) is the table; `CANDY` is the module-local. `UITheme.Candy.font` is the only font source for this work.
