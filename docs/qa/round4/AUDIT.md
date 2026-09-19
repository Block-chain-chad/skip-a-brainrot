# Round 4 — Bag / Inventory performance audit

Measured 2026-09-19 in Studio Play on the owner's profile (52 brainrots, 16 placed, 80 pets),
desktop viewport 1891×793, **client unfocused and throttled to 15 fps** (every frame ≥ 66 ms), so
the numbers below are the *hitch* frames (anything above the 66 ms floor is real work) plus Lua
timings from `os.clock`, which the throttle does not touch. The focused-client numbers from round
2.5 (`docs/qa/round2/README.md`) are quoted where they apply. Nothing was changed for this file.

## What the Bag does today (BackpackPanel.lua, 4862 lines; BrainrotCard, ViewportCuller, BrainrotThumb)

| Path | What happens | Measured |
|---|---|---|
| Open (cold, first time) | `require` + `Build(ctx)` builds the whole panel, then `renderActiveTab()` → `renderBrainrots()` builds the tab chrome (bay strip, inventory header, search, sorts, well, scroll) **and every card** (32 synchronously, then 24 per Heartbeat), then the culler mounts 32 viewports | visible after **951 ms**, one **957 ms** frame + 72/81/85/115 ms; 4,496 instances in the panel |
| Close | culler detaches (all viewports destroyed), FX entries released; the built tree stays (4,050 instances) | 184 ms, frames 83/75 |
| Re-open (warm) | `wrapper.Visible` → `renderActiveTab()` → **full rebuild**: `clearChildren(contentHost)`, every card destroyed and rebuilt, chrome rebuilt, culler re-attached, 32 viewports cloned again | one **260 ms** frame + 123/100 (round 2.5 focused: 283 ms) |
| Any `DataUpdated` while open (equip, store, lock, catch, sell, plot purchase…) | `scheduleRender` (0.25 s debounce) → the same full rebuild, scroll position restored by two deferred writes | 25 items → 199 ms frame; 50 → 289+100; 100 → 452+116; 250 → **402, 506, 429** ms frames, 1.65 s until every card exists |
| Sort change / search keystroke | `fillBag()` destroys every card and rebuilds it — a sort is a full rebuild just to reorder | same cost as a snapshot rebuild |
| Tab switch | every tab renderer starts with `clearChildren(contentHost)`; coming back to Brainrots is another full rebuild | Brainrots→Pets 106/114 ms; Pets→Brainrots one **600 ms** frame |
| Scrolling (250 cards) | culler passes mount/unmount viewports as rects enter the margin; a pass mounts up to the cap in one frame | fast: max 132 ms, 5 frames > 70; slow: max **259 ms**, 19 frames > 70 (round 2.5 focused: 29 fps average) |
| Pets tab | 80 pet tiles built with a live `ViewportFrame` each, **no culler**: 83 viewports / 5,528 BaseParts in the panel, ~15 within the screen rect and a 158 px scroll window | 14,366 instances for the tab (~175 per tile) |
| Closed | culler detached, viewports gone, FxDriver 0 entries and its Heartbeat disconnected, the panel's own rarity-FX Heartbeat stands down | ✓ nothing runs; 10 close/open cycles leave the instance census identical (no leak) |

Per-card costs (24 cards, Lua only): build **1.0 ms / card** (56 instances, 5.5 text objects) —
of which ~0.5 ms is UIPolish's `DescendantAdded` work on every instance parented under PlayerGui
(0.49 ms/card when built detached); viewport mount 0.43 ms; `setState` 0.33 ms; destroy 0.5 ms.
Round 2.5 attributed a further **~3.3 ms of engine layout / text-fitting / stroke work per new
card** in the frame it lands (identical off-screen), which is why 24 new cards cost ~100 ms of frame
and 250 cost half a second in three frames.

Card pop-in: with 250 distinct models the first capture showed most art wells empty; a minute later
every one had rendered. Models are cloned from stripped masters correctly (5–22 parts each, framed);
the blanks are mesh assets still streaming in — nothing preloads the bag's models.

## The bottleneck, in one sentence

**The Bag never updates — it rebuilds.** Every open, every server snapshot, every sort, every search
keystroke and every return from another tab destroys the whole card grid and its chrome and builds
it again from scratch (≈4 ms of Lua + engine per card, ≈66 instances per card), then re-clones up to
32 viewport models; the Pets tab additionally keeps a live viewport for every pet it owns.

Secondary: the culler mounts a whole window of viewports in one frame; nothing preloads models, so
big bags pop in; the per-card instance count (56) and the UIPolish per-instance tax make every new
card expensive.

## The fix (smallest safe change)

1. **Persistent Brainrots tab + diff by UID.** Build the tab chrome once (kept as a cached frame,
   detached instead of destroyed when another tab renders — the pattern the Index and Charms tabs
   already use). `fillBag` keeps a `[uid] = card` map: existing cards are updated in place
   (`card.set` only when a field actually changed), reordered by `LayoutOrder` for sorts, hidden for
   search misses, destroyed only when the UID leaves the save; only *new* UIDs build cards, in
   time-budgeted chunks. The card's click / tooltip read the *current* entry, not the one it was
   built with. Scroll position survives naturally.
2. **Re-open = re-attach.** `wrapper.Visible` → refresh, not rebuild: the culler re-attaches to the
   kept cards and mounts the visible window.
3. **Culler mounts in slices** (≤ 8 viewport clones per frame, self-rescheduling) so an open or a
   fast scroll never lands a whole window of clones in one frame.
4. **Pets tab on the culler**: pet tiles build their viewport lazily through the same
   `ViewportCuller` (mount/unmount), so only the visible window holds live viewports; a hidden or
   closed Bag holds none.
5. **Model preload**: after each snapshot, `ContentProvider:PreloadAsync` the owned brainrot / pet
   masters once, in the background, so a big bag does not pop in.
6. Leave alone: save format, remotes, equip / store / lock flows, rarity ladder, the card's visual
   identity, the panel family's canvas fit.

None of this changes data, ownership, gameplay or the Round 3 HUD.
