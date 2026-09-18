# Egg Shop UI Rebuild — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the egg shop's browse/buy panel with the "Industry" handoff layout (3+2 card grid, hover hatch-odds, ×1/×3/×10 buy row, ACQUIRED stamp, receipt ticket) rendered entirely in the game's Pet-Sim HUD style, on desktop and phone.

**Architecture:** Rebuild in place inside `StarterPlayer.StarterPlayerScripts.EggShopClient`, replacing only lines ~221–1002 (ScreenGui/panel/header/egg-rows/odds-strip/affordability). The hatch ceremony (~1033–2252), Darrel state pull, `setOpen`, and the EggStall ProximityPrompt binding are **not touched**. Layout is data-driven off `EggConfig.WORLDS.Forest.Eggs`, so odds shown can never drift from odds rolled.

**Tech Stack:** Roblox Luau · `ReplicatedStorage.Modules.UIKit.Tokens` (`T`) + `.Builders` (`UI`) · `ReplicatedStorage.Modules.Platform` · `EggConfig` · `PetConfig` · TweenService.

---

## Global Constraints

- **Panel width is 940**, not the handoff's 1120. `T.size.panelWidth.eggs = 940` is already reserved. Design canvas is 1350×775 (`Platform.DESIGN_X/Y`).
- **Style is Pet-Sim HUD only.** Window `T.gradient.panel`, red header `T.color.headerTop/headerBottom`, dark slots `T.gradient.slot`, `T.font.display` (GothamSSm Bold), `T.radius.panel = 8`, `T.stroke.panel = 4`, `T.pad.panel = 16`, `T.pad.gridGap = 11`.
- **Drop every Industry signature detail**: no square corners, no 1px hairlines, no blueprint "+" registration marks. User decision, explicit.
- **BUY DARRELS button renders but is wired to nothing.** No dev product, no prompt. It must not error when clicked.
- **Spec strip middle slot shows discovery progress** (`N / 15 PETS DISCOVERED`), not the handoff's restock countdown. There is no restock mechanic and none is being built.
- **Egg art is a ViewportFrame of the real model** (`addEggViewport`, existing, line ~145), never an ImageLabel placeholder.
- **Odds come from `EggConfig` at runtime.** Never hard-code a percentage. Paid random items require published odds.
- **Bundle prices come from `EggConfig.BundleCost(egg, qty)`.** Never recompute `Price × qty` — that is the bug fixed on 2026-08-06.
- Each egg has exactly **3 pets, worst→best**; the last row is both rarest and strongest.
- Client never decides cost or outcome. Buy still fires `remotes.EggBuy(worldId, eggId, qty)`; the server re-derives everything.

### Known traps in this codebase — read before writing any UI code

1. **`UI.button` and `UI.panel` parent their `hardShadow` as a SIBLING**, not a child (`UI.hardShadow` line ~85; `sh.Parent = frame.Parent`). Dropping three buttons straight into a `UIListLayout` gives the layout **six** children — the shadows become phantom list items. **Always wrap each button in its own plain Frame slot.** `EggShopClient` line ~726 already documents this as the codebase-wide pattern. This is also the exact bug class that produced the stray black square fixed earlier today.
2. **`UIListLayout` owns child `Position`.** A hover that tweens `Position` on a list child fights the layout. Put the hover on a wrapper one level down (the existing `CardHolder` pattern, line ~471).
3. **`ClipsDescendants` must be false** on anything whose child renders outside its bounds.
4. **Verify tween targets before relying on them.** A prior session recorded that tweens on `UIScale`, `NumberValue`, `Sound.Volume` and possibly `BackgroundTransparency` silently no-op in this place, while `Size`/`Position`/`Rotation` work. **Task 1 verifies this directly** rather than trusting the note — the handoff leans on opacity fades throughout, and if they no-op the fades must be driven by a `RenderStepped` setter instead.
5. **Studio's device emulator latches** — `TouchEnabled`/`MouseEnabled` read true for every device after the first switch. Test phone layout with `game.ReplicatedStorage:SetAttribute("PlatformOverride", "Phone")` instead.
6. **`require()` caches by Instance, not Source.** After editing a module, restart the playtest; do not trust a warm require.

### Verification model

There is no test framework in this place. "Test" means: run `mcp__roblox-studio__execute_luau` against the **Client** datamodel in a live playtest and assert on real instances, then read `get_console_output` for errors. Every task ends with a probe that fails loudly.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `StarterPlayer.StarterPlayerScripts.EggShopClient` | Shop panel + hatch ceremony | Modify lines ~221–1002 only |
| `ReplicatedStorage.Modules.EggConfig` | Egg data, odds, bundle price | Read-only (already correct) |
| `ReplicatedStorage.Modules.PetConfig` | Pet boosts, tiers, colours | Read-only (already correct) |
| `ReplicatedStorage.Modules.UIKit.Tokens` / `.Builders` | Style tokens + builders | Read-only |
| `ReplicatedStorage.Modules.Platform` | Device class, panel fit, safe insets | Read-only |

Nothing new is created. The shop stays one file because the ceremony below it shares `new()`, `comma()`, `addEggViewport`, `addPetViewport`, `tierColor` and the `revealGen`/`revealSkip` closures; splitting it would mean threading all of that through a module boundary for no gain this round.

---

### Task 1: Panel shell — window, header, spec strip

**Files:**
- Modify: `EggShopClient:221-346` (ScreenGui + panel + `recentre` + `relayout` + header)

**Interfaces:**
- Produces: `shopGui: ScreenGui`, `panel: Frame` (940 wide, `UI.panel`), `cardArea: Frame` (the region Task 3 fills), `balanceLabel: TextLabel`, `discoveryLabel: TextLabel`, `relayout(): ()`.
- Consumes: `T`, `UI`, `Platform`, existing `setOpen` (line ~2281) — do not change its signature.

- [ ] **Step 1: Verify the tween-target trap before building on it**

Run against **Client** in a playtest:

```lua
local f = Instance.new("Frame")
f.Size, f.BackgroundTransparency = UDim2.fromOffset(50,50), 0
f.Parent = game:GetService("Players").LocalPlayer.PlayerGui:WaitForChild("EggShopUI")
local TS = game:GetService("TweenService")
TS:Create(f, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
task.wait(0.4)
local bg = f.BackgroundTransparency
local s = Instance.new("UIScale"); s.Scale = 1; s.Parent = f
TS:Create(s, TweenInfo.new(0.2), { Scale = 2 }):Play()
task.wait(0.4)
local sc = s.Scale
f:Destroy()
return ("BackgroundTransparency tween -> %.2f (want 1.00) | UIScale tween -> %.2f (want 2.00)"):format(bg, sc)
```

Record both answers in a comment at the top of the rebuilt section. If `BackgroundTransparency` did **not** reach 1.00, every fade in Tasks 4–5 must be driven by a `RunService.RenderStepped` setter instead of `TweenService`.

- [ ] **Step 2: Build the shell**

Replace the old ScreenGui/panel/header block. Header is one red bar, per the Pet-Sim style:

```lua
local PANEL_W = T.size.panelWidth.eggs           -- 940, reserved for this panel
local PANEL_H = 660

shopGui = new("ScreenGui", {
    Name = "EggShopUI", ResetOnSpawn = false, IgnoreGuiInset = true,
    DisplayOrder = T.zindex.panel, Enabled = false,
}, playerGui)
Platform.PrepareGui(shopGui)                     -- notch / safe-area

local scale = new("UIScale", {}, shopGui)
local panel = UI.panel(shopGui, UDim2.fromOffset(PANEL_W, PANEL_H))
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.ZIndex = T.zindex.panel

-- ONE red header bar (Pet-Sim style), title left, wallet + BUY DARRELS + X right
local header = UI.surface(panel, UDim2.new(1, 0, 0, T.size.headerHeight), "panel",
    T.radius.panel, T.stroke.panel)
UI.gradient(header, ColorSequence.new(T.color.headerTop, T.color.headerBottom))
local title = UI.label(header, "EGG SHOP", "panelTitle", T.color.white)
title.AnchorPoint = Vector2.new(0, 0.5)
title.Position = UDim2.new(0, 18, 0.5, 0)
```

`relayout()` must set `scale.Scale = Platform.FitPanel(PANEL_W, PANEL_H)` — **not** `Platform.Fit()`. `FitPanel` is what makes the panel usable on a handset (0.307 → 0.571 on a 896×414 phone). Register it with `Platform.Watch(relayout)` so rotation and window resize re-run it; delete any bespoke `ViewportSize` listener the old code had.

- [ ] **Step 3: Wallet chip, BUY DARRELS, close**

Right-aligned cluster, 10px gaps. Each button wrapped in its own Frame slot (trap #1).

```lua
local buyDarrels = UI.button(slot, "BUY DARRELS", "green", UDim2.fromOffset(168, 44), "buttonM")
-- Deliberately inert: no dev product exists yet (user decision 2026-08-06).
-- It must still be harmless to press, so it gets a handler that does nothing
-- visible rather than no handler at all -- an unwired button that also fails
-- silently is indistinguishable from a broken one during QA.
buyDarrels.Activated:Connect(function() showToast("Darrel packs are coming soon!") end)
```

- [ ] **Step 4: Spec strip**

Three items, `"meta"` style, `T.color.textOnWindow` at reduced alpha:
1. `05 EGGS IN ROTATION`
2. `N / 15 PETS DISCOVERED` — count from the existing discovered snapshot (`applyDiscovered`, line ~935) over `EggConfig.ObtainablePetIds()`. **Not** a restock countdown.
3. `HOVER A CARD FOR FULL HATCH ODDS` — on touch, `TAP A CARD FOR FULL HATCH ODDS`.

- [ ] **Step 5: Verify**

Playtest, then against **Client**:

```lua
local pg = game:GetService("Players").LocalPlayer.PlayerGui
local gui = pg:FindFirstChild("EggShopUI"); assert(gui, "no EggShopUI")
local panel = gui:FindFirstChild("Panel", true) or gui:FindFirstChildWhichIsA("Frame")
local sc = gui:FindFirstChildWhichIsA("UIScale")
return ("panel %dx%d (want 940x660 pre-scale) | scale %.3f | header children %d")
  :format(panel.AbsoluteSize.X, panel.AbsoluteSize.Y, sc.Scale, #panel:GetChildren())
```

Then `get_console_output` — must be clean. Confirm the panel still opens from the EggStall prompt and ESC/X still closes it.

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/plans/2026-08-06-egg-shop-ui-rebuild.md
git commit -m "feat(eggshop): panel shell in Pet-Sim style, 940w, FitPanel scaling"
```

---

### Task 2: Egg card component

**Files:**
- Modify: `EggShopClient` — replace the egg-row builder (~471–804)

**Interfaces:**
- Produces: `buildCard(egg, index) -> Frame` and a `cards[eggId] = { root, figure, oddsPanel, buyButtons, stampHost }` registry that Tasks 4 and 5 drive.
- Consumes: `panel`, `cardArea` from Task 1; `addEggViewport` (line ~145, unchanged).

Card is **295 × 300** (940 − 32 padding = 908 inner; (908 − 2×11) / 3 = 295.3).

- [ ] **Step 1: Card skeleton**

`UI.surface(parent, UDim2.fromOffset(295, 300), "subPanel", T.radius.panel, T.stroke.control)`. Stack top→bottom with a `UIListLayout` (`Padding = 8`):

1. **Meta row** — tier ribbon left (`UI.ribbon`, tinted by `PetConfig.RARITY_COLOUR` of the egg's *best* pet), `EGG-0N · 0N/05` right in `"meta"`.
2. **Figure** — full width × 148, `UI.surface(..., "slot", T.radius.slot)`, `ClipsDescendants = true`. Egg model via `addEggViewport`. **No striped plate** — that is an Industry motif; the dark slot gradient replaces it.
3. **Name row** — egg name `"cardLabel"` left; price right as Darrel icon + `comma(egg.Price)` in `"value"`, `T.color.textAccent`.
4. **Rarest row** — `RAREST` in `"meta"` muted, then `egg.Table[3][1]` tinted by its tier colour, chance right-aligned. Read from `EggConfig`; never hard-code.
5. **Buy row** — three buttons, built in Task 2 Step 2.

- [ ] **Step 2: Buy row — three wrapped slots**

```lua
-- Each button gets its own Frame slot. UI.button parents its hard shadow as a
-- SIBLING, so three bare buttons in a UIListLayout become SIX list items and the
-- real buttons get shoved off the row. This is the codebase-wide pattern; see the
-- QtySlot note at the old line ~726.
for i, qty in ipairs({ 1, 3, 10 }) do
    local slot = new("Frame", {
        Name = "BuySlot" .. qty, Size = UDim2.fromOffset(88, 46),
        BackgroundTransparency = 1, LayoutOrder = i,
    }, buyRow)
    local cost = EggConfig.BundleCost(egg, qty)      -- NEVER egg.Price * qty
    local btn = UI.button(slot, "", (qty == 10) and "gold" or "tab",
        UDim2.fromOffset(88, 46), "buttonM")
    -- quantity over subtotal, two lines
    local q = UI.label(btn, "x" .. qty, "buttonM", T.color.white)
    local sub = UI.label(btn, comma(cost), "meta", T.color.textMuted)
    ...
end
```

Discount pips: `-5%` on ×3, `-12%` on ×10, derived from `EggConfig.BUNDLE_DISCOUNT` so the label can never disagree with the price. Pip sits half outside the button's top-right; its parent must not clip.

- [ ] **Step 3: Verify one card in isolation**

```lua
local RS = game:GetService("ReplicatedStorage")
local Egg = require(RS.Modules.EggConfig)
local pg = game:GetService("Players").LocalPlayer.PlayerGui
local card = pg.EggShopUI:FindFirstChild("Card_ForestCrown", true)
assert(card, "Crown card missing")
local bad = {}
for _, qty in ipairs({1,3,10}) do
  local slot = card:FindFirstChild("BuySlot" .. qty, true)
  if not slot then table.insert(bad, "missing BuySlot" .. qty)
  elseif #slot:GetChildren() ~= 2 then                 -- button + its sibling shadow
    table.insert(bad, ("BuySlot%d has %d children"):format(qty, #slot:GetChildren())) end
end
local e = select(1, Egg.GetEgg("Forest", "ForestCrown"))
return ("card %dx%d | x10 should read %d | issues: %s"):format(
  card.AbsoluteSize.X, card.AbsoluteSize.Y, Egg.BundleCost(e, 10),
  #bad == 0 and "none" or table.concat(bad, ", "))
```

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(eggshop): egg card with wrapped buy slots and bundle pricing"
```

---

### Task 3: 3 + 2 grid

**Files:** Modify: `EggShopClient` — the card area container

**Interfaces:** Consumes `buildCard` (Task 2). Produces the filled `cardArea`.

- [ ] **Step 1:** Row 1 — `UIGridLayout`, `CellSize = UDim2.fromOffset(295, 300)`, `CellPadding = UDim2.fromOffset(11, 11)`, 3 across.
- [ ] **Step 2:** Row 2 — separate Frame, `UIListLayout`, `FillDirection = Horizontal`, `HorizontalAlignment = Center`, `Padding = 11`, holding cards 4 and 5 so they centre under the top row.
- [ ] **Step 3: Verify** all five cards exist, row 2 is horizontally centred within ±2px, and no card overlaps another:

```lua
local pg = game:GetService("Players").LocalPlayer.PlayerGui
local ids = {"ForestShard","ForestDrip","ForestHorned","ForestRune","ForestCrown"}
local seen, boxes = {}, {}
for _, id in ipairs(ids) do
  local c = pg.EggShopUI:FindFirstChild("Card_" .. id, true)
  seen[#seen+1] = id .. (c and " OK" or " MISSING")
  if c then boxes[#boxes+1] = { c.AbsolutePosition, c.AbsoluteSize, id } end
end
local overlaps = 0
for i = 1, #boxes do for j = i+1, #boxes do
  local a, b = boxes[i], boxes[j]
  if a[1].X < b[1].X + b[2].X and b[1].X < a[1].X + a[2].X
  and a[1].Y < b[1].Y + b[2].Y and b[1].Y < a[1].Y + a[2].Y then overlaps += 1 end
end end
return table.concat(seen, " | ") .. ("  overlaps=%d (want 0)"):format(overlaps)
```

- [ ] **Step 4: Commit** — `git commit -am "feat(eggshop): 3+2 card grid with centred bottom row"`

---

### Task 4: Hover lift + hatch-odds panel

**Files:** Modify: `EggShopClient` — replaces the old odds strip (~805–953)

**Interfaces:** Consumes `cards` registry. Produces `setHovered(eggId | nil)`.

- [ ] **Step 1:** Hover state on a **wrapper** frame, not the list child (trap #2). On enter, over 180ms Quad Out: lift −5px, stroke → `T.color.activeRing`, egg viewport scales to 1.06 over 250ms.
- [ ] **Step 2:** Odds panel fills the figure box exactly (inset 0), `UI.surface(..., "row", T.radius.slot)`. Header `HATCH ODDS` / `CHANCE`, then **3 rows** from `egg.Table` in order — worst first. Last row uses its tier colour and is visually heavier; it is both rarest and strongest by construction.
- [ ] **Step 3:** Only one card hovered at a time. On touch (`Platform.IsTouch`), the odds panel toggles on tap of the RAREST row and the trailing label flips `ODDS` ↔ `HIDE`; there is no hover path at all.
- [ ] **Step 4: Verify** — hover each card via `setHovered`, assert exactly one odds panel visible, its row count is 3, and its percentages equal `EggConfig`'s:

```lua
local RS = game:GetService("ReplicatedStorage")
local Egg = require(RS.Modules.EggConfig)
local pg = game:GetService("Players").LocalPlayer.PlayerGui
local out = {}
for _, e in ipairs(Egg.WORLDS.Forest.Eggs) do
  local card = pg.EggShopUI:FindFirstChild("Card_" .. e.Id, true)
  local odds = card and card:FindFirstChild("OddsPanel", true)
  local rows = 0
  if odds then for _, c in ipairs(odds:GetDescendants()) do
    if c.Name == "OddsRow" then rows += 1 end end end
  out[#out+1] = ("%s rows=%d (want %d)"):format(e.Id, rows, #e.Table)
end
return table.concat(out, " | ")
```

- [ ] **Step 5: Commit** — `git commit -am "feat(eggshop): hover lift and hatch-odds panel"`

---

### Task 5: Buy flow — debit, ACQUIRED stamp, receipt ticket

**Files:** Modify: `EggShopClient` — `fireBuy` (~525) and `refreshAffordability` (~964)

**Interfaces:** Consumes `cards`, `currentDarrels`. Produces `showStamp(eggId, qty)`, `showReceipt(eggId, qty, cost)`.

- [ ] **Step 1:** Affordability — a button is disabled when `EggConfig.BundleCost(egg, qty) > currentDarrels`. Swap the variant to `"disabled"` (which also makes it silent and non-interactive, per `UI.button`). Re-run on every `DarrelUpdate`.
- [ ] **Step 2:** On press, fire `remotes.EggBuy:FireServer("Forest", egg.Id, qty)` — unchanged contract. **Do not** decrement the balance locally as truth; apply the server's `DarrelUpdate`. An optimistic flash is fine, the number is not.
- [ ] **Step 3:** ACQUIRED stamp — scrim the figure, land `x{qty} ACQUIRED` centred, rotated −8°, `scale 1.5 → 0.94 → 1` over 350ms. Clears after 1100ms. **Cancel any in-flight stamp timer before starting a new one**, or a fast second purchase leaves a stale stamp on the previous card.
- [ ] **Step 4:** Receipt ticket — bottom-right of the panel, inset 26, 250 wide. `ORDER CONFIRMED` / `x{qty} {Egg Name}` / `◆ −{cost}` / `SENT TO HATCH QUEUE`, with a 2px bar draining left→right over 2800ms, then dismiss. A new purchase replaces it and restarts both timers.
- [ ] **Step 5: Verify** — **do not award Darrels**; Studio playtests can write to the live DataStore. Instead assert the disabled-state logic against the real balance:

```lua
local RS = game:GetService("ReplicatedStorage")
local Egg = require(RS.Modules.EggConfig)
local pg = game:GetService("Players").LocalPlayer.PlayerGui
local out = {}
for _, e in ipairs(Egg.WORLDS.Forest.Eggs) do
  for _, q in ipairs({1,3,10}) do
    local slot = pg.EggShopUI:FindFirstChild("BuySlot" .. q, true)
    out[#out+1] = ("%s x%d cost=%d"):format(e.Id, q, Egg.BundleCost(e, q))
  end
end
return table.concat(out, "\n")
```

Then buy one Shard Egg ×1 for real in the playtest and confirm: balance drops by exactly 60, stamp appears then clears, ticket appears then drains, and the existing hatch ceremony still plays untouched.

- [ ] **Step 6: Commit** — `git commit -am "feat(eggshop): buy flow with acquired stamp and receipt ticket"`

---

### Task 6: Phone layout (one column)

**Files:** Modify: `EggShopClient` — `relayout`, `buildCard`

- [ ] **Step 1:** Branch on `Platform.IsPhone`. Panel insets 10px from the screen edge and fills the rest; body scrolls (`ScrollingFrame`, 12px padding, 12px between cards).
- [ ] **Step 2:** Card becomes horizontal — 104×118 figure left; tier ribbon, name, price and a 34-high tappable `RAREST … ODDS` row right. Odds panel expands **below** that row inside the card rather than covering the figure. Buy buttons full-width beneath at **48 high** (Roblox's 44px minimum touch target is a floor, not a target).
- [ ] **Step 3:** No hover states anywhere on this path. Every hover affordance has a tap equivalent.
- [ ] **Step 4: Verify** with the override, since Studio's emulator latches (trap #5):

```lua
game:GetService("ReplicatedStorage"):SetAttribute("PlatformOverride", "Phone")
task.wait(1)
local Platform = require(game:GetService("ReplicatedStorage").Modules.Platform)
local pg = game:GetService("Players").LocalPlayer.PlayerGui
local card = pg.EggShopUI:FindFirstChild("Card_ForestShard", true)
local smallest = math.huge
for _, d in ipairs(pg.EggShopUI:GetDescendants()) do
  if d:IsA("GuiButton") and d.Visible then
    smallest = math.min(smallest, math.min(d.AbsoluteSize.X, d.AbsoluteSize.Y)) end
end
return ("class=%s card=%dx%d smallest touch target=%.0fpx (want >= 44)")
  :format(Platform.Class, card.AbsoluteSize.X, card.AbsoluteSize.Y, smallest)
```

Reset with `SetAttribute("PlatformOverride", nil)` when done.

- [ ] **Step 5: Commit** — `git commit -am "feat(eggshop): one-column phone layout"`

---

### Task 7: Retire dead code, full-pass verification

- [ ] **Step 1:** Delete anything from the old panel now unreferenced — `kitButton` if unused, the old odds strip, `selectRow`, `popAffordable`, `rowCards`, the old `qtyByEgg` picker. Confirm with `script_grep` that each name has zero remaining hits before deleting it.
- [ ] **Step 2:** Confirm the ceremony is untouched: `playReveal` and `playMultiReveal` byte-identical to their pre-rebuild state.
- [ ] **Step 3:** Full playtest — open from the stall, hover all 5 cards, buy ×1 on the cheapest, watch the ceremony, close, reopen. Console clean throughout.
- [ ] **Step 4:** Re-run the Task 1/3/4/6 probes as a suite; all must pass on desktop **and** with the Phone override.
- [ ] **Step 5: Commit** — `git commit -am "chore(eggshop): retire superseded panel code"`

---

## Post-plan notes

- **Nothing here is saved or published.** All edits live in the Studio session only; the place owner must publish. Same standing caveat as the 2026-08-06 economy change.
- **The mirror repo cannot receive this.** `game-src/eggs/*.lua` is many hundreds of lines behind live (its `EggConfig.lua` predates the 15-pet roster entirely), so patching it would write files that misrepresent the game. Syncing the mirror is its own job.
- **Deliberately deferred, not missing.** Two items are in the handoff but have no task here:
  - **Keyboard/gamepad focus** — the handoff specifies a 2px `#5980a6` outline at 2px offset, walking card-to-card then across the three buy buttons. Dropped from this round because the user scoped it to "shop panel + mobile layout"; the game has no focus-navigation convention to follow yet, so inventing one here would set a precedent for every other panel. Worth its own pass across the whole HUD.
  - **Buy-remote error state** — the handoff flags this as undesigned on its own side. `showToast` already exists and `EggResult` already carries `{ Ok = false, Message = ... }`, so the interim behaviour is a toast; a designed failure state is a separate ask.
