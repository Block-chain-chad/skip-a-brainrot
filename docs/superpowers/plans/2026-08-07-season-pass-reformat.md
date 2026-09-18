# Season Pass panel — reformat to the ladder layout (2026-08-07)

Source design: `docs/design-handoff/season-pass/season-pass.html` + `LAYOUT-NOTES.md`.
Target: `game.StarterPlayer.StarterPlayerScripts.GameHUDPanels.PassPanel` (live Studio, 935 lines).

**This is a reformat, not a system build.** `SeasonConfig` already ships both 50-tier
tracks, `DescribeReward` already turns a tier into display fields, and `SeasonClaim`
already works. Nothing server-side changes.

## Decisions taken (user, 2026-08-07)

1. **960 wide, both tracks side by side, vertical scroll only.** No h-scroll.
2. **Side column dropped, Quests button kept.** The `MILESTONE · TIER 50` row already
   shows both tracks' top reward, so the two "Max Rewards" previews are redundant.
3. **Both purchase buttons drawn but inert** — precedent: egg shop `BUY DARRELS`,
   Codex `EQUIP`.

## Why 960 is the right number now

`GameHUDClient:165-180` was changed after the Codex shipped: `openPanel` writes the
open panel's own width into `panelFitW`, floored at 960. So:

- `T.size.panelWidth.pass` is **already 960** — dropping the 196px side column makes
  that token TRUE for the first time (the panel currently builds 1170 and clips 90px
  on a 4:3 tablet).
- 960 is exactly the floor, so no other panel's scale moves at all.

Height budget is `PANEL_FIT_H = 700`. Today's panel is 712 — over. The new one targets 700.

## Geometry (960 × 700)

```
HEADER_H      92     header, y=0
BODY_TOP     102
BODY_H       560     pad 16/side -> inner 928 × 528
FOOTER_H      30     y = 670
  progress row      60
  column headers    28
  ladder scroll    424   (ROW_H 80 + ROW_GAP 8 -> ~4.8 rows visible, 50 tiers scroll)
```

Ladder columns inside 928: `FREE 404 | gap 16 | TIER 88 | gap 16 | PREMIUM 404`.

Card internals (404 × 80): 60px art plate left, name + subtitle stacked, CLAIM right.
~210px of text width — measured, not assumed (see acceptance).

## Build order

1. **Back up** current source to `ServerStorage.AuditBackups.PassPanel_pre_reformat`.
2. `SeasonConfig`: add an identity block (below). Additive only — no new reward Kind.
3. Rewrite `PassPanel` section by section via `multi_edit`, reading back after each
   batch (multi_edit has silently no-opped before — see the ThrowHandler note).
4. Verify in a **fresh Play VM** (the Edit-mode `require` cache still returns the old
   25-tier table — documented in `50-tier-report.md` §6 and reproduced today).

## The one data gap the handoff notes missed

`SeasonConfig` has **no season name and no end date**, so the design's `STILL WATER`,
`18 DAYS LEFT` and `ENDS 04 SEP` have nothing behind them. `SupplySchedule.SEASONS[1]`
is *not* the same concept (brainrot supply) and its `Starts` is an explicit far-future
placeholder with the schedule deliberately dormant — deriving a countdown from it
would print nonsense.

Adding to `SeasonConfig`:

```lua
M.SEASON = { Number = 1, Name = "Still Water", Id = "SEASON_01_STILL_WATER", Ends = nil }
```

`Number`/`Name`/`Id` are display-only and come straight from the design. **`Ends` stays
`nil`** — the countdown chip and the footer date render only when it is a real
timestamp. No invented dates. Setting it later is a one-line flip.

## Kept exactly as-is

Remotes and the claim path, `SeasonClaim:FireServer(tier, track)` as the single call
site, server-confirmed-only state writes, the `hasServerState` badge gate, the
`PassPanelBlur` watchers, `shortCash`, `Quests -> goals` navigation.

## Bug this fixes on the way past

Free reward cards are currently **invisible text**: line 619 flips the card gradient to
flat white, then line 631 asks for `CARD_TEXT` — an undefined global left behind by the
2026-08-04 repair, which declared `CARD_BORDER` and `BODY_INK` but not this one.
`UI.label` falls back to `T.color.white`, so it is white-on-white. The rewrite deletes
that whole code path.

## Acceptance

- Panel builds at exactly 960 × ≤700; no `SideColumn`; `panelFitW` fit clean at 1024×768.
- 50 rows × 2 tracks render, tier pills 1..50, milestone divider before tier 50.
- Every reward label resolves from `DescribeReward` — 0 empty, 0 clipped (measure with
  `TextService:GetTextSize` against each card's real text box).
- Free track: locked / claimable / claimed all reachable and visually distinct.
- Premium column reads locked for everyone (gamepass id is 0) and un-greys the moment
  ownership flips — verified by forcing `PassOwned` true in a Play VM.
- `SKIP TIER` / `UNLOCK PREMIUM` clickable but do nothing; no console errors.
- Reopen 3× — descendant count identical, no orphans, no leaked BlurEffect.
