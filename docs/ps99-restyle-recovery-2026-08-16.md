# PS99 restyle — recovery map (2026-08-16)

Everything below was built in ONE Studio session on 2026-08-16 and left **UNSAVED** per project
convention. Studio was closed at end of day with save-state **unconfirmed**. If the work is
gone, this file is the complete restoration map.

## First check on reopening the place

Open the Bag (rail, top icon) in Play:
- **White panel, red backpack sticker by the title** → the work SURVIVED. Nothing to do.
- **Green header bar (old style)** → the session was lost. Restore per below.

## What was built (in order)

1. **PS99 white-chrome retint** — SpecTheme, PanelChrome, Tokens, UITheme (Bazaar), UIPolish
   (readability floor RETIRED), + 13 per-panel fix files. Entrance glide hand-lerp in
   GameHUDClient (UIScale pop was a proven no-op).
2. **Sticker pass** — rail art tilted in all 6 shell headers; interior icons ~35% bigger,
   alternating ±6° lean; Bag tab hover-pops.
3. **Field-study deltas 1–10** (from 120 live PS99 frames): title-on-edge, plateless quest log,
   bare currencies, splash grids, doodle watermark, hairline section heads, green active tabs,
   state-tile vocabulary, plateless toasts (+dormant item-toast), PC.tooltip.
4. **Blocker fixes** (from grading 120 frames of our own game): QuestBar DisplayOrder 20→4 +
   hide-on-panel + naked restyle; GameHUDClient top-clearance gate; Pets tab + detail column
   ported light; orphaned-item "?" placeholder; watermark-out-of-listLayout.

## Restoration assets (all durable)

- **Uploaded art (permanent on Roblox, account prohacks_sorry):**
  - crayon splash: `rbxassetid://111764682902637`
  - doodle watermark tile: `rbxassetid://106223454313706`
  - (PIL generator scripts for both are in the session transcript if regeneration is wanted)
- **Full transcripts** (every multi_edit's exact old/new text):
  `C:\Users\m\.claude\projects\C--Users-m-Coding\` — sessions
  `e3936277-9828-48a8-9ebb-ee79b3ca32cb` and `edf6d5c2-3f17-4496-b5e6-89f8ded37ef6` (JSONL).
- **Re-runnable agent workflow scripts** (self-contained briefs; run with
  `Workflow({scriptPath})` and agents re-derive exact edits against fresh reads):
  `...\e3936277-...\workflows\scripts\` → `ps99-retint-audit`, `ps99-panel-fixes`
  `...\edf6d5c2-...\workflows\scripts\` → `ps99-icon-juice`, `ps99-live-study`,
  `quest-log-plateless`, `bag-grid-debox`, `ps99-deltas-8-9-10`, `ourgame-grade`,
  `blocker-fixes`
- **Memory files** (design decisions + gotchas):
  `C:\Users\m\.claude\projects\C--Users-m-Coding\memory\roblox-ps99-white-chrome.md` and
  `roblox-ps99-field-study.md`
- **Design reference:** the PS99 field study artifact —
  https://claude.ai/code/artifact/7a8b1341-737a-47af-add5-b5569ce2d886

## Restoration order (if lost)

Shared modules first (Tokens → SpecTheme → PanelChrome → UITheme → UIPolish), then GameHUDClient,
then the per-panel workflows, then blockers. Compile-gate each file with
`loadstring(script.Source)` before moving on. Expect roughly 2–3 hours of agent time versus the
original day — all decisions are already made.

## Standing flags for the owner (regardless of save-state)

- premiumCounter pill art retired (reverses the 2026-08-09 owner call) — user-approved.
- Season Pass olive palette retired for cool navy — user-directed, owner should be told.
- UIPolish readability floor retired (the 08-14 "all text white" rule) — required by the
  white theme; one edit to restore if contested.
