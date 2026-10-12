# Season Pass reformat — layout notes (2026-08-07)

Source: `season-pass.html` beside this file (copy of `C:\Users\m\Downloads\Season Pass (standalone).html`).
Reference recording: `C:\Users\m\Videos\Screen Recordings\Screen Recording 2026-08-07 162120.mp4`
(12s, 1160x842). Frames were extracted with ffmpeg at 1fps; re-extract if needed.

**The HTML cannot be read statically** — 440KB in 361 lines, a JS bundle that builds
its markup at runtime, with copy inside a compressed payload. The Claude Code preview
pane renders it as a static snapshot and cannot execute it. Use a real browser, or
work from the recording.

## Design system

Palette extracted from the bundle: `#5980a6`, `#f2f2f3`, `#416180`, `#1d2d3d`,
`#e9e9ea`, `#1d1f20` — **identical to the egg shop handoff and the charm codex.**
Same "Industry" system: steel blue on a light technical ground, square corners,
hairlines, blueprint corner marks.

**Standing user ruling for all three:** take the LAYOUT, render it in the Pet-Sim HUD
theme (`UIKit.Tokens`/`.Builders`), and drop the light ground, square corners,
hairlines and corner marks.

## The layout

**Header** — kicker `SEASON 01 · STILL WATER · 50 TIERS`; title `SEASON PASS`;
top-right two buttons: `SKIP TIER · 79 R$` (secondary) and
`UNLOCK PREMIUM · 799 R$` (primary).

**Progress row** — `TIER 14 / 50` · `SEASON XP  1,240 / 2,000 to tier 15` with a
progress bar; right-aligned status items `18 DAYS LEFT`, `0 CLAIMED · 14 READY`,
`XP FROM QUESTS · REBIRTHS · DAILY LOGIN`.

**The ladder** — three columns, vertically scrolling to tier 50:

| FREE TRACK · EVERYONE | TIER | PREMIUM TRACK · 799 R$ · RETROACTIVE |
|---|---|---|

- Row = reward card, centre tier-number pill, reward card.
- Reward card: icon on a striped plate + reward name (`1,450 Cash`, `Shard Egg ×1`,
  `75 Darrels`, `Season XP ×2`, `Egg Bundle ×3`, `Title · Stillwater`) + a subtitle
  (`INSTANT PAYOUT`, `HATCHERY`, `PREMIUM CURRENCY`, `60 MINUTES`,
  `SEASON 01 EXCLUSIVE`) + either a `CLAIM` button or a greyed `TIER 46` marker.
- Claimable rows carry an accent border; future/locked rows are greyed.
- A `MILESTONE · TIER 50` divider sits before the final row.

**After buying premium** (frame 9): header flips to `PREMIUM TRACK UNLOCKED`, the
counter goes `14 READY` -> `28 READY`, premium rows un-grey.

**Footer** — left: "Buying premium unlocks every tier you have already passed —
nothing is missed." Right: `SEASON_01_STILL_WATER · ENDS 04 SEP`.

The recording's window is narrower than the layout, so the premium column is cut off
and a horizontal scrollbar appears. **That is the recording, not necessarily the
intent** — see open question 3.

## Data situation — CHECKED 2026-08-07, this is current

**Question 1 is ANSWERED: both tracks already exist and are fully populated.**
`SeasonConfig.Tiers` (free) and `.PassTiers` (premium) are generated from
`FREE_SPECIALS` / `PASS_SPECIALS`; unlisted tiers fall through to cash. Premium is
deliberately "the same track tuned up" — next egg up the ladder, ~1.5x cash and
darrels, double-length boosts, its own tags, tier numbers lining up one-to-one.

**So this is a REFORMAT, not a system build.** The reward data, both tracks, and the
claim path all exist.

**`SeasonConfig.DescribeReward(def)` is the seam to build the reward cards on.** Its
own comment calls it "ONE place that turns a tier into something displayable, so
SeasonClient and PassPanel cannot drift apart on it." Returns
`{ kind, icon, text, amount?, id?, qty?, model?, glyph? }`. Five kinds: `Cash`,
`Darrels`, `Egg`, `Boost`, `Tag`. `TierFor(track, i)` gets either track without the
caller branching.

**Extended to 50 tiers on 2026-08-07** (see `50-tier-report.md` beside this file):
`CASH_GROWTH` 1.38 -> 1.28 (at 1.38, tier 50 would have paid $11.4 BILLION), 32 new
specials across tiers 27-50, 4 new tags, `TIER_COUNT = 50`. `XP_PER_TIER` stayed 250
= 26.5 days at the quest pool's real XP rate. **Tier 25 dropped 6.1x** as a
consequence — unavoidable with any single exponential, and defensible now that 25 is
the midpoint rather than the finale.

**No reader hard-codes 25** — all derive from `#SeasonConfig.Tiers`. But five *stale
comments* still say 25 in `SeasonClient`, `SeasonPassHandler` and `PassPanel`.

## Open questions — STILL UNANSWERED

1. **Do `SKIP TIER` (79 R$) and `UNLOCK PREMIUM` (799 R$) exist as products?**
   `SeasonConfig:3` and `PassPanel:52-63` both say the premium track is gated on a
   **gamepass id that does not exist yet** — that is the ONLY thing blocking premium,
   not data. PassPanel's comment claiming there is no premium reward table is now
   **stale**; `PassTiers` exists.
   Precedent if the ids are still missing: render both buttons inert, exactly like
   the egg shop's BUY DARRELS and the charm codex's EQUIP.
2. **Width / fit.** The recording's window is narrower than the layout, so the
   premium column is cut off behind a horizontal scrollbar. Unknown whether that is
   intended. Options put to the user: fit both tracks with no h-scroll; keep it wide
   and scroll; or free/premium as switchable tabs. **Not answered.** Note h-scroll is
   poor on touch, and see the PassPanel width bug below.
3. **`Season XP ×2` appears in the design but has no home** — the only Boost stats
   are `Luck` and `Power`. Either add an XP boost kind (which means a `claimTier`
   branch — it currently handles only Cash/Darrels/Egg/Boost/Tag and an unknown kind
   silently pays 0) or drop it from the layout.

## Scale of the build

Comparable to the egg shop rebuild, which took 7 tasks plus a review and a fix wave.
Two-track ladder of 50 rows, per-row claim state, premium lock/unlock states,
milestone dividers, live progress header. **Write a plan first** — see
`docs/superpowers/plans/2026-08-06-egg-shop-ui-rebuild.md` and
`2026-08-07-charm-codex-panel.md` for the shape that worked.

## Carry this into the build

**`PassPanel` is the panel with the tablet bug.** Its `T.size.panelWidth.pass` says
**960**, but it actually builds a **1170x712** Group (960 `PanelColumn` + a visible
196px `SideColumn`) and **clips 90px on a 4:3 tablet** — worse than the Charms bug
fixed the same day. A reformat is the right moment to make it register its real
width. Fixing it via the token alone would shrink Pass ~18% on 4:3, which the user
rejected for the other panels; reflowing or hiding the side column at that size is
the alternative. See `.superpowers/sdd/2026-08-07-charm-codex-panel/tablet-fit-fix-report.md`.

Also unfixed and pre-existing: `BackpackPanel:562` adds `headerTitle.AbsoluteSize.X`
(screen px) to design-px offsets, so the Bag counter drifts at any non-1.0 scale.
