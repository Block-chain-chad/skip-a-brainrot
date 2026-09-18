# Charm Codex Panel — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Charm Codex screen — slot row, filterable charm grid, and detail column — as its own panel opened from the Bag, rendered entirely in the Pet-Sim HUD style, driven by a placeholder `CharmConfig` that can be swapped when the real charms are designed.

**Architecture:** A new `GameHUDPanels` module registered under id `charms`, mounted into the existing panel host. All content — charm count, names, copy, categories, slot rules — comes from a new `ReplicatedStorage.Modules.CharmConfig`. **The layout derives its grid from the data, never the reverse**, so a 12- or 24-charm roster re-flows without touching layout code.

**Tech Stack:** Roblox Luau · `UIKit.Tokens` (`T`) + `.Builders` (`UI`) · `Platform` · `GameHUDClient`'s panel registration contract.

---

## Global Constraints

- **This is a layout build. No charm changes any stat.** Do not touch `ThrowHandler`, `IncomeLoop`, `SellHandler`, `MutationConfig`, `RarityCurve`, `EggHandler` or `QuestHandler`. The charm system does not exist and is not in scope.
- **`CharmConfig` is placeholder data and must say so at the top of the file.** Content is taken verbatim from the design video so real text lengths are exercised. The real roster is undecided.
- **Panel is 1120 x 700**, registered as `T.size.panelWidth.charms = 1120`. Canvas is 1350x775 (`T.size.canvas`), header height 92.
- **Pet-Sim HUD style only** — window `T.gradient.panel`, red header `T.color.headerTop`/`headerBottom`, dark slots `T.gradient.slot`, `T.font.display`, `T.radius.panel = 8`, `T.stroke.panel = 4`, `T.pad.panel = 16`.
- **Drop every Industry signature detail** from the source design: no square corners, no 1px hairlines, no blueprint "+" registration marks. Same ruling the user gave for the egg shop.
- **EQUIP is inert** — renders, harmless to press, does nothing. Same pattern as the egg shop's BUY DARRELS.
- **The four Round C charms render as LOCKED cards.** The spec states they are structurally blocked: rarity is rolled at `ThrowHandler:559-626` but `nContacts` is not computed until `:380`, so the outcome is decided before the rock is thrown. Showing them as available would promise what the code cannot do.
- **Grid dimensions are computed from `#CharmConfig.Charms`**, never hard-coded to 4x4.

### Naming collision — decide once, in Task 1

The game **already** uses "Charm": a **Lucky Charm** item appears in `LuckHUDClient`, `UpgradeConfig`, `RockConfig` and `MerchantConfig`. Two unrelated things called charms will confuse players and future greps. Task 1 must pick one and apply it consistently: either the new system takes a distinct in-fiction name (the video's own kicker says **TALISMANS**, which is available and unused), or the existing Lucky Charm is explicitly acknowledged as separate in `CharmConfig`'s header. **Do not leave this ambiguous.**

### Known traps in this codebase — all have already broken a build

1. **`EggShopClient` sits at ~115 top-level locals with a peak of 193 against Luau's hard limit of 200.** This is a NEW file so it starts clean, but the same discipline applies: crossing 200 is a **compile error whose symptom is "the panel does nothing"**, not an error at the offending line. Keep top-level locals minimal.
2. **`UIPolish` force-whitens every text object under `PlayerGui`** and re-asserts on `TextColor3` change. Every coloured label needs `:SetAttribute("NoPolish", true)` — set on a card root it covers descendants — then re-assert the colour *after* `UI.label` returns, and verify after UIPolish's deferred second pass, which runs late.
3. **`UI.button` and `UI.panel` parent their hard shadow as a SIBLING** (`UI.hardShadow`: `sh.Parent = frame.Parent`). Controls dropped straight into a `UIListLayout`/`UIGridLayout` turn their shadows into phantom cells. **Wrap every button in its own plain Frame slot.**
4. **Layouts own their children's `Position`.** Anything animated needs a wrapper one level below the layout child.
5. **`GameHUDClient.openPanel` wraps `Build` in a pcall**, so a panel that throws mid-build fails **silently** and leaves a bare window. Test the failure path.
6. **`x and nil or y` is always `y` in Lua.** A prior task shipped that bug in a toggle that could only ever open. Test toggles both ways.
7. **`script_grep` and `script_read` disagree on line numbers** (grep resolves a different copy in Play mode). Grep to find *whether* a name is referenced, `script_read` to find *where*.
8. **`multi_edit` has silently no-opped in this codebase.** For large blocks use a line-indexed `Source` splice via `execute_luau` with anchor assertions, and read every region back.
9. **Studio's client can silently stop rendering** (`RenderStepped` 0/s while Heartbeat is 60/s) — every tween freezes and `screen_capture` times out. Window focus does not fix it; **sending real mouse input into the viewport does.** Restore `CameraType = Fixed` after any posed capture.

### Verification model

No test framework exists here. "Test" means `execute_luau` against the **Client** datamodel in a live playtest, asserting on real instances, then `get_console_output`. Probes must **measure the composite `UIScale` fresh** — it read 0.9704 in one session and 1.0215 in another. Never hardcode it.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `ReplicatedStorage.Modules.CharmConfig` | All charm data + slot rules. Single source of placeholder truth. | **Create** |
| `StarterPlayer.StarterPlayerScripts.GameHUDPanels.CharmsPanel` | The panel: shell, slots, grid, detail column | **Create** |
| `ReplicatedStorage.Modules.UIKit.Tokens` | Add `panelWidth.charms = 1120` | Modify, 1 line |
| `GameHUDPanels.BackpackPanel` | Add the button that opens the charms panel | Modify, small |

The panel is its own file rather than a section of `BackpackPanel` — `BackpackPanel` is already ~1,300 lines, and the egg shop rebuild is a standing lesson in what a file this size costs to work in.

---

### Task 1: `CharmConfig` — the data contract

**Files:** Create `ReplicatedStorage.Modules.CharmConfig`

**Interfaces:** Produces `CharmConfig.Charms` (array), `.Slots` (array), `.Categories` (array), `.CharmById(id)`, `.Filter(categoryKey)`.

- [ ] **Step 1:** Header comment states, unmissably: this is **placeholder content transcribed from the 2026-08-07 design video**, the real roster is undecided, and editing this file is the whole job of changing the roster. Also resolve the Lucky Charm naming collision here (see Global Constraints) and state the ruling.

- [ ] **Step 2:** Shape, with all 16 entries:

```lua
export type Charm = {
    Id: string,            -- "CHARM_GOLDEN_YOLK"
    Name: string,          -- "The Gilded Yolk"
    WasCalled: string?,    -- "Golden Yolk" -- the detail panel shows this
    Category: string,      -- "MILESTONE" | "QUEST" | "WORLD" | "SEASON"
    Effect: string,        -- the short grid label, e.g. "EGG LUCK"
    Flavour: string,       -- italic line
    Gain: string,          -- GAIN row
    Trade: string?,        -- TRADE row; nil = no downside
    TradeProposed: boolean?,
    Config: string,        -- CONFIG row, e.g. "EggTailBias = 0.5, SellAdd = -0.10"
    Source: string,        -- SOURCE row
    Hook: string,          -- HOOK row
    Note: string?,         -- the blue note box
    Locked: boolean?,      -- true for the four Round C charms
    Sigil: string,         -- glyph key: "square" | "diamond" | "circle" | "ring"
}
```

- [ ] **Step 3:** Slots, exactly as the video shows: `1 = FIRST RARE CATCH`, `2 = REBIRTH 1`, `3 = FIRST MYTHIC CATCH`, `4 = GAMEPASS · OPEN DECISION` (locked).

- [ ] **Step 4: Verify** — require it and assert: 16 charms, unique ids, every `Category` present in `.Categories`, exactly 4 with `Locked = true`, and `.Filter("QUEST")` returns only quest charms. Print the counts.

- [ ] **Step 5:** Record the combination count as **derived** (`C(n,3)`), not the literal 560 — it must follow the roster.

---

### Task 2: Panel shell — window, header, stacking-rule box, slot row

**Files:** Create `GameHUDPanels.CharmsPanel`; modify `UIKit.Tokens` (add `panelWidth.charms = 1120`)

**Interfaces:** Produces the module's `{ Id = "charms", Build = function(ctx) -> Frame }`, plus `slotRow`, `leftColumn`, `rightColumn` for Tasks 3 and 4.

- [ ] **Step 1:** Register per the contract in `GameHUDClient`'s header: the module returns `{ Id = "charms", Build = function(ctx) -> Frame }` and parents its panel into `ctx.host`. Read that header before writing — a module with no `Build`/`Id`, or one whose `require` errors, is **skipped silently**.

- [ ] **Step 2:** 1120 x 700 panel via `UI.panel`, one red header bar (`T.size.headerHeight = 92`) with the title left and a 44x44 close right. Kicker line above the title, as the video has it.

- [ ] **Step 3:** `STACKING RULE` box pinned top-right of the body: `final = base × (1 + a + b + c)` and the line "Additive within the charm layer, applied once. Never chain." This is a real invariant from the spec — render it verbatim.

- [ ] **Step 4:** Slot row — 4 cards across, each showing slot number, occupant (`Empty` for now) and its unlock condition. Slot 4 renders **Locked**. Cards come from `CharmConfig.Slots`; do not hard-code four.

- [ ] **Step 5:** Split the body into left (~55%) and right (~45%) columns with a gap. Both are empty frames this task.

- [ ] **Step 6: Verify** — panel is 1120x700 pre-scale, opens via `ctx.openPanel("charms")`, closes, and reopens without duplicating. `get_console_output` clean. **Also deliberately make `Build` throw once** and confirm you can see the failure — trap 5 means a broken panel looks like an empty one.

---

### Task 3: Filter tabs + charm grid

**Files:** Modify `CharmsPanel`

**Interfaces:** Produces `cards[charmId] = { root, sigil }` and `setSelected(charmId)`. Task 4 consumes both.

- [ ] **Step 1:** Filter tab row from `CharmConfig.Categories`, plus an `ALL` tab. Right-aligned status line `N SHOWN · 0/3 SLOTS USED`, both numbers derived.

- [ ] **Step 2:** Grid via `UIGridLayout` with **columns computed from the column width and card width**, and rows from `math.ceil(#shown / columns)`. Hard-coding 4x4 is a defect — the roster is explicitly undecided.

- [ ] **Step 3:** Card = sigil glyph + name + effect label. Locked cards are visibly locked and not selectable. Selected card gets the accent ring your kit already uses.

- [ ] **Step 4:** Filtering re-flows the grid without rebuilding cards from scratch where avoidable, and **must not** leave stale selection pointing at a hidden card.

- [ ] **Step 5: Verify** — every category filter shows the right subset (print counts per filter against `CharmConfig.Filter`), selecting a card then filtering it away clears selection cleanly, locked cards reject selection, and the grid re-flows correctly when you temporarily stub the roster to 8 and to 24 entries. **That stub test is the point of the task** — it proves the layout is data-driven.

---

### Task 4: Detail column

**Files:** Modify `CharmsPanel`

- [ ] **Step 1:** Sigil figure on a dark slot surface (the video's striped plate is an Industry motif — replaced by your slot gradient), with the charm's code caption.
- [ ] **Step 2:** Tag row — category tag, `LIVE`/`LOCKED` state, and `NN/16` index derived from the roster.
- [ ] **Step 3:** Name, `CHARM_ID · was "Old Name"` line, italic flavour.
- [ ] **Step 4:** Spec rows: **GAIN / TRADE / CONFIG / SOURCE / HOOK**. Omit TRADE entirely when `Trade` is nil rather than rendering an empty row. When `TradeProposed`, show the PROPOSED marker.
- [ ] **Step 5:** Note box when `Note` is present. Full-width **EQUIP TO SLOT N** button — **inert**, with a comment saying so and a toast on press, matching the egg shop's BUY DARRELS precedent.
- [ ] **Step 6: Verify** — select all 16 in turn and confirm every field matches `CharmConfig` exactly (print the comparison); confirm charms without a `Trade` omit the row; confirm a locked charm shows LOCKED and its EQUIP button is disabled. Colours sampled after UIPolish's late pass.

---

### Task 5: Open from the Bag, and full verification

**Files:** Modify `GameHUDPanels.BackpackPanel`

- [ ] **Step 1:** Add a button in the Backpack panel that calls `ctx.openPanel("charms")`. Follow `GoalsPanel:869`'s `ctx.openPanel("pass")` as the working precedent.
- [ ] **Step 2:** Confirm the rail's active-glow and close behaviour treat `charms` like any other panel — `openPanel` hides every other panel unconditionally.
- [ ] **Step 3: Full pass** — open from the Bag, filter every category, select several charms including a locked one, press EQUIP (toast, no error), close, reopen, confirm no duplicated instances via a descendant census before/after.
- [ ] **Step 4:** Phone check with `ReplicatedStorage:SetAttribute("PlatformOverride", "Phone")` — 1120 is wider than any existing panel, so **confirm what `Platform.FitPanel` does to it on a handset** and report the numbers. If it is unusable, say so with measurements rather than redesigning; a phone layout is a separate decision.
- [ ] **Step 5:** Reset the override, restore `CameraType = Fixed`, leave Studio in **Edit** mode, console clean.

---

## Post-plan notes

- **Nothing here is saved or published.** Same standing caveat as all of 2026-08-06/07's work.
- **The mirror repo cannot receive this.** `game-src/` is hundreds of lines behind live. Syncing it is its own job.
- **Deliberately out of scope:** the charm *system* (effects, equip persistence, server validation), the 6 consumables from the spec, and the slot-unlock conditions actually being checked. The panel shows unlock text; nothing evaluates it.
- **Known risk, accepted:** building the screen before the roster is decided locks the layout around placeholder content. Mitigated by the data-driven grid and the 8/24 stub test in Task 3, but if the real charm list changes shape substantially — different detail rows, very different name lengths — the detail column will need revisiting.
