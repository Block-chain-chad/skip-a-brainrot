# UI round 2 — visual QA review (2026-09-18)

Branch `ui-foundation` @ `40fe7ee`. Everything below was captured from a real Studio **Play**
session on the owner's profile (`prohacks_sorry`: 52 brainrots, 16/16 on plot, 11 pass rewards
ready) unless a screenshot says "synthetic". Desktop = Studio maximised on a 1080p monitor,
game viewport **1891×793**. Phone = Studio Device Simulator **iPhone 16, landscape**
(852×393 pt screen, 733×371 game viewport, HUD scale 0.48).

No source was changed for this review. The captures are the PNGs next to this file; the
self-contained page `round2-visual-qa.html` (sent in chat) embeds downscaled copies.

## Screenshots

| # | File | What it shows |
|---|------|---------------|
| 1 | `01-bag-desktop.png` | Bag, desktop, real profile: rarity-tinted cards, foil GOD/SECRET plates, pad pips, income bands |
| 2 | `02-bag-mixed.png` | Bag with a **synthetic** 50-item snapshot (1 God · 2 Secret · 4 Mythic · 5 Legendary · 7 Epic · 8 Rare · 9 Uncommon · 12 Common · 2 retired ghosts), 9 placed, locks + NEW tags |
| 3 | `02b-bag-plot-open.png` | Same snapshot with the plot fold-out open: 9 pad cards, 3 free slots, 4 locked slots with UNLOCK prices |
| 4 | `03-bag-iphone16.png` | Bag on the iPhone 16 simulator (6-column grid, 44 px controls, panel clear of the thumbstick and jump button) |
| 5 | `04-season-pass.png` | Season Pass tab: tier plate 30/50, XP bar, 11 READY / 19 CLAIMED, FREE / PREMIUM columns, UNLOCK 699 |
| 6 | `04b-season-pass-claim.png` | Ladder scrolled to a CLAIM row (tier 16) above CLAIMED rows |
| 7 | `04c-season-pass-next.png` | Current tier 30 (CLAIM) with the blue NEXT ring on tier 31 and unreached TIER tags |
| 8 | `05-goals-claimable.png` | Goals tab with two claimable rows floated to the top (**synthetic**: the real profile has no claimable goal, so `rocks20` and `discover150` were marked Met for the shot). The GOALS nav item shows the "!" badge |
| 9 | `06-luck.png` | Luck flyout: RARITY (gold) / MUTATION (purple) / BEST THROW (blue) sections, permanent vs temporary rows |
| 10 | `07-rock-shop.png` | Rock Shop (merchant) on the white shell: 3D rock previews, EQUIP buttons, kit close |
| 11 | `08-egg-shop-desktop.png` | Egg Shop desktop: pink title, wallet chip, BUY GEMS, rarity chips, x1/x3/x10 with unclipped discount pips |
| 12 | `09-egg-shop-iphone16.png` | Egg Shop on the iPhone 16 simulator — **see finding 1** |

## Checks

| Check | Result | How it was verified |
|-------|--------|---------------------|
| Text overlap | **Pass** — 0 overlaps on all 9 screens (desktop + phone) | Glyph-rect scan of every visible label inside each panel (TextBounds + alignment, clipped-away labels excluded). Bag desktop 96/115 labels, Bag phone 91, Progress/Goals 19, Pass 38, Luck 33, Rock Shop 21, Egg Shop 82 (desktop) / 17 (phone). 0 labels with text larger than their box. |
| Panel / HUD overlap | **Pass on desktop for Bag, Progress, Luck** (0 painted HUD elements under the panel). **Minor on desktop shops**, **fail on phone Egg Shop** — findings 1–2 | Painted-leaf scan of every other ScreenGui against the panel rect, plus DisplayOrder check for what actually draws on top |
| Close buttons | **Pass** — Bag `Header.Close`, Progress (Goals + Pass) `Header.Close`, Luck `Headline.Close`, Rock Shop `Panel.Header.CloseButton`, Egg Shop `…CloseSlot.Close` all clicked and read back hidden. Bag close also verified in the phone layout | Real clicks through the Studio input tool, then `Visible` / `HudOpenPanel` read back |
| Open / close animation | **Structurally correct, smoothness not measurable this session** — finding 6 | Per-frame sampling of `PopScale` + `Position`: open 0.94 → 1.006 → 1.00 with the slide from +26 px, close 1.00 → 0.97 with an 18 px slide |
| 400-item Bag | **Pass on structure and per-card cost; wall-clock not measurable this session** — finding 6 | 400-item synthetic snapshot built and scrolled top→bottom→top (canvas 5097 px); `CullerLive` never exceeded 32 of the 64 cap; construction bench: `BrainrotCard.new` 1.0–1.5 ms/card, mount 0.6–1.3 ms/card, so the chunked build is ≈100 ms for the first screen then ≈30 ms per Heartbeat for 15 frames (round 1 measured 277–332 ms in one frame) |
| Gems terminology | **Pass** — 0 of 2560 runtime labels contain "Emerald"/"Darrel" | Runtime sweep of every TextLabel/TextButton/TextBox in PlayerGui in both sessions; the only world hits are the DARREL bust at the egg stall (the character) and a leaderboard player named "darreltvv". Source sweep of client scripts and shared configs: only identifiers and comments remain |

## Findings, most important first

1. **Phone Egg Shop: the HIDE UI pill draws over the close button.** `HudToggleUI` (DisplayOrder 30)
   sits above `EggShopUI` (25) and covers **41–53 % of the X** on the iPhone 16 layout; the scooter
   tab / VIP / Sprint chrome also crowd the panel's right edge (`09-egg-shop-iphone16.png`). The
   merchant panel (order 24) has the same exposure. This is the known "legacy shop ScreenGuis vs HUD
   chrome" item, but it now lands on the one control the player needs. Fix options for the next
   round: hide `HudToggleUI` / `ScooterUI` / the sprint button while a shop is open (the GameHUD
   panels already hide the rail on phone), or raise the two shops above order 30.
2. **Desktop shops clip the gem "+" button by 2 px.** Both 961-px shop panels are centred, so their
   left edge (x = 464) lands on the `GemPill.Bar.Buy` button (ends at x = 466). Visible as a shaved
   right edge on the "+" in `07`/`08`. Cosmetic at 1891 px wide, worse on narrower laptop viewports.
   The shops also cover the top-centre SKIP / SHOPS / PLOT tab bar, which is under them by
   DisplayOrder (hidden, not colliding).
3. **Luck flyout has no visible close control.** `Headline.Close` is an invisible hit area over the
   green ×14.97 plate; the Luck chip toggles the panel. It works, but nothing tells the player where
   to tap. Suggest the kit X in the title row.
4. **Pass ladder is short on desktop.** The ladder window is 259 px inside the 587-px panel, so only
   three tiers show at once out of 50 (`04b`). Long reward names truncate in the FREE column
   ("Heartwood Egg…") while the PREMIUM column fits "Heartwood Egg." — same string, different room.
5. **Foil sparkle under the pad pip.** On GOD/SECRET cards `Sparkle3` (anchored at 0.88, 0.42) sits
   under the equipped pip and peeks around its corner (`02-bag-mixed.png`, cards 1–3). Cosmetic;
   the pip draws on top.
6. **Frame-time numbers from this session are not usable.** A fullscreen game had the GPU and
   Studio was unfocused, so the client rendered at ~15 fps with 150–700 ms stalls *even with every
   panel closed* (idle baseline p50 66 ms, max 470 ms). The animation and 400-item checks above are
   therefore structural + micro-benchmarked, not felt. They should be re-run on a focused client
   before sign-off; the synthetic snapshot seam and the samplers are ready to go.

Also noted, no action needed: frost-themed brainrots (`Inverno Eterno`, `Zero Assoluto`) render as
white silhouettes in cards on both platforms — that is the models' own colouring, not the card.

## Not covered in this pass

- Sell panel close (its walk-up prompt did not show for the scripted character; not in the
  requested list).
- Phone layouts for Season Pass, Goals, Luck and Rock Shop (not requested).
- Anything under real 60 fps rendering (finding 6).

## Repro notes

- Captures: `tools/studio-bridge/capture-studio.ps1 -Mode print` (PrintWindow, works while the Studio
  window is covered). Desktop viewport crop = window-relative `-Left 10 -Top 174 -Width 1891 -Height 793`
  with Studio filling the 1080p monitor; iPhone 16 screen crop = `-Left 227 -Top 239 -Width 1445 -Height 666`.
- Synthetic bags: Server `execute_luau` builds a snapshot from `BrainrotConfig` and fires
  `Remotes.DataUpdated:FireClient`; the profile is restored by echoing the current `fastSpin`
  preference through `SettingsSave` (the server answers with a real `PushUpdate`).
- Claimable goals: capture the live `QuestState` list on the client, relay it to a Server exec via a
  temporary RemoteEvent, flip `Met`/`Claimed`, and re-fire it at 10 Hz so it outruns the 3 s server
  refresh. Everything synthetic was cleared before the session ended (device simulator stopped,
  `HttpEnabled` still false).
