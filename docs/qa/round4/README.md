# Round 4 QA — Bag / Inventory performance + UX refinement

Branch `ui-foundation`, on top of the locked Round 3 (`7e44a98`); the code is commit `f547891`.
Measured 2026-09-19 in Studio
Play on the owner's profile (52 brainrots, 16 placed, 80 pets; Team Create place 78783087742939),
with synthetic 25 / 50 / 100 / 250-item bags pushed to the client as `DataUpdated` snapshots by a
Server-side relay (nothing is written to the profile; the real snapshot is restored at the end of
every run). The audit that preceded the change is [`AUDIT.md`](AUDIT.md) (commit `c68e17b`).
Every number below says which build and which client state it came from: a Studio client that
does not have focus throttles to ~15 fps (66 ms frames), so only *focused* runs (≥ 50 fps idle)
give real frame times; throttled runs are only used for hitch frames (> 67 ms) and Lua timings.

## 1. Bottleneck(s)

**The Bag never updated — it rebuilt.** Every open, every server snapshot (equip, store, lock,
catch, sell, plot purchase), every sort, every search keystroke and every return from another tab
ran `clearChildren(contentHost)`, destroyed every card and rebuilt the whole tab (chrome + cards,
≈4 ms of Lua + engine and ≈66 instances per card), then re-cloned up to 32 viewport models. Measured
before the change (focused, round 2.5 / audit): warm re-open of the 52-item bag **283 ms** in one
frame; a snapshot on 250 items **402 / 506 / 429 ms** frames and 1.65 s until every card existed;
Pets → Brainrots **600 ms**; fast scroll of 250 cards ~30 fps with 132 ms hitches, slow scroll
259 ms hitches.

Secondary: the culler mounted a whole window of viewport clones in one frame (the 100–260 ms hitches
on open and after a fast scroll); the Pets tab built a live `ViewportFrame` for every pet (83
viewports / 5,528 BaseParts for 80 pets, ~15 of them near the screen); nothing preloaded the bag's
mesh assets, so a big bag popped in over most of a minute (`before-01-bag250-popin.jpg`); the
adaptive live cap fed back on itself under scroll load (a long frame lowered the cap under the
visible window, the nearest-to-centre plan then churned mounts every step, which made frames
longer).

Found while verifying: re-parenting the kept tab (the Index / Charms "detach" pattern the audit
proposed) cost a **900 ms** frame on a 250-card bag — every one of ~17,000 descendants re-registers
with the engine and UIPolish's `DescendantAdded` pass re-runs — so the tab is hidden in place
instead (see below); and the culler's adaptive cap read the Bag's own card-build frames as device
weakness (64 → 48 → 36 → 27 over three 250-card fills, for the rest of the session), so the build
now declares itself busy.

## 2. Exact changes

**`BackpackPanel.lua` (Brainrots tab)**

- Module-level `gridUi` gained `shell` (the tab's built chrome and the geometry it was built for),
  `byUid` (`[uid] = { card, entry, applied }`), `petCuller`, `petSelect`, and `teardownGrid()`.
- `renderBrainrots` no longer tears anything down. The tab lives in one `BrainrotsTab` frame under
  `contentHost`, built once. While another tab shows it stays **parented and hidden**
  (`Visible = false`; `clearChildren` spares it; its culler is suspended and its cards' FX paused
  exactly as on a close) and a return is a `Visible` flip + FX resume; it is rebuilt only when the
  geometry class changes (phone ↔ desktop columns, card width). The bay strip (16 pads, counts,
  income) is rebuilt every render because it *is* the snapshot; the inventory header (search,
  sorts, count) and the well + `ScrollingFrame` are built once and repositioned. The two deferred
  `CanvasPosition` restores are gone — the scroll is the same instance, so the position survives
  by itself.
- `fillBag` **diffs by UID**: (1) cards whose UID left the save are destroyed; (2) search misses
  are hidden, not destroyed (the culler treats a hidden root as off screen, the grid layout skips
  it); (3) every existing card is updated in place — `LayoutOrder` for the sort, `setState` only
  when equipped / locked / NEW actually changed; a name / rarity / mutation / size change is an
  identity change and rebuilds that one card; (4) only never-seen UIDs are built: 8 now, 8 per
  Heartbeat for the first 32, then 4 per Heartbeat (was 32 + 24 per frame), and the chunk loop
  declares the culler **busy** for its duration so those frames are not counted against the
  adaptive cap. The click / hover handlers read `rec.entry`, which every render updates, so a card
  built while benched STORES once it is placed. `instanceName` is `BagCell_<uid>` (was the grid
  index).
- The culler gets a dense, ordered list of the cards that exist (`syncCuller`): `resume()` +
  `setCards()` on an existing handle, `attach()` only when there is none.
- `wrapper.Visible = false` **suspends** the culler (was: detach + destroy every viewport), pauses
  every card's FX, detaches the Pets culler and unmounts the fold-out plot's hand-mounted cards;
  `Visible = true` resumes the FX of the tab that is showing and renders.
- `preloadOwnedModels()` after every applied snapshot (join and `DataUpdated`): 3 s later, a
  background `ContentProvider:PreloadAsync` of the MeshId / TextureID content ids of the owned
  brainrot and pet masters, 8 ids per batch with a Heartbeat between batches, each name warmed
  once. Fire-and-forget.

**`BackpackPanel.lua` (Pets tab)**

- `buildPetTile` builds its 3D art **lazily**: it returns a cullable (`root / mount / unmount /
  isMounted`); the `ArtSlot` (viewport or swatch) is built on first mount and `Visible`-flipped after
  that. `renderPets` keeps `tiles[uid]`, attaches a `ViewportCuller` to the pet grid and defines
  `gridUi.petSelect(uid)`: selection repaints the tile that lost the ring and the one that gained it,
  updates the culler's list and the detail column — not all 80 tiles. Tile clicks call it (fallback:
  the old full `renderPets`).
- Two non-contractual probe seams on `player` attributes, inert unless something writes them (the
  exec VM cannot synthesise a GuiButton click and `user_mouse_input` wedges after a few): 
  `HudBagPetSelect` → `gridUi.petSelect`, `HudBagTab` → `switchTab`. Same class as `_applySnapshot`.

**`UIKit/ViewportCuller.lua`**

- Mounts are **sliced**: at most `mountsPerPass` (8) nearest-to-centre cards per pass, the pass
  re-schedules itself on the next Heartbeat while any remain (`task.delay(0)`); unmounts still run
  in full. `Options.mountsPerPass`, `Options.flingPx`.
- **Fling gate**: while the canvas moves faster than `flingPx` per pass (default a quarter of the
  window) nothing is mounted — the rows racing past get their art the frame the scroll slows.
- **Moving floor** on the adaptive cap: it never drops below the number of cards intersecting the
  viewport; frames in which the culler itself mounted cards, and frames the consumer declared
  **busy** (`Handle.setBusy`), are not counted against the budget.
- `Handle.suspend()` / `resume()`: the scroll signals and the Heartbeat let go while a panel is
  hidden; what is mounted stays mounted (a hidden `ViewportFrame` draws nothing). `detach()` is
  unchanged (unmounts everything). Roots that are not `Visible` count as off screen.

**`UIKit/BrainrotCard.lua`**

- A card **keeps its viewport**: `unmount()` hides it (and clears FX) instead of destroying the
  clone; a re-mount is a `Visible` flip + FX re-registration. `freeArt()` (called from `destroy()`)
  destroys it. `pauseFx()` / `resumeFx()` for the hidden-panel case. The kit card's visuals, props
  and API are otherwise unchanged.

Nothing else was touched: no server script, remote, save field, equip / store / lock / swap flow,
reward, rarity, mutation or size rule; Round 3's scripts are untouched.

## 3. Files changed

| File (mirror, byte-exact from Studio, LF) | Before | After |
|---|---|---|
| `game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDPanels/BackpackPanel.lua` | 211,159 B | 226,251 B |
| `game-src/place-full/ReplicatedStorage/Modules/UIKit/ViewportCuller.lua` | 6,845 B | 11,267 B |
| `game-src/place-full/ReplicatedStorage/Modules/UIKit/BrainrotCard.lua` | 30,418 B | 31,451 B |

Pre-round copies of all three live in `ServerStorage.AuditBackups.PreUIRound4_2026_09_19`
(`BackpackPanel_pre`, `ViewportCuller_pre`, `BrainrotCard_pre`). Docs and captures:
`docs/qa/round4/`.

## 4. Performance optimisations (what changed, in one line each)

1. Persistent tab chrome + UID diff instead of destroy-and-rebuild (open, snapshot, sort, search,
   tab return).
2. Re-open = resume: the culler is suspended, not detached; mounted viewports stay mounted while
   hidden; FX paused. The same for a tab switch (hidden in place, never re-parented).
3. Viewport clones are kept per card (hide / show), so scrolling back over a card is a `Visible`
   flip.
4. Sliced mounts (≤ 8 clones per frame) and a fling gate (no clones while the canvas moves faster
   than a quarter window per frame).
5. Adaptive cap with a moving floor; the culler's own mount frames and the panel's card-build
   frames are excluded from its budget (no feedback churn, no permanent step-downs).
6. New cards land 8 + 8/frame near the fold, 4/frame below it (was 32 + 24/frame).
7. Pets tab on the culler (only the visible window holds live viewports) and in-place selection.
8. Background preload of the owned models' mesh / texture ids after each snapshot, paced.

## 5. UX changes

Deliberately none to the composition — the brief asked for cleanup, not a redesign, and the audit
put the whole cost in the rebuilds. What the player feels:

- Re-opening the Bag is instant (the panel glide is the only thing between click and content) and
  it opens **where it was left**: scroll position, search text and sort choice survive close/open,
  snapshots and tab switches.
- Equip / store / lock no longer flash the grid: only the badge that changed repaints.
- Sorting and searching reorder / hide the same cards instead of rebuilding them; a search
  keystroke keeps its focus.
- Previews stay put: no pop-in on big bags (`after-01-bag250-desktop.jpg`,
  `after-03-bag250-mid-scroll.jpg` — every card in view has its art, against
  `before-01-bag250-popin.jpg`), no re-clone when scrolling back, nothing animates or renders while
  the Bag is closed or another tab shows.
- Pets: picking a pet repaints two tiles and the detail column instead of the whole tab.
- Card spacing, names, rarity bands, equipped / locked / NEW badges, hover / press feedback, sort
  pills, close button, tabs, empty states, the Brainrots / Pets / Charms / Keys / Tags / Index
  categories: unchanged (Round 2 / 2.5 work).

## 6. Large-inventory results

Final bytes, fresh Play sessions, **focused** client (≥ 50 fps idle), desktop viewport 929×784;
synthetic bags on top of the real profile snapshot. `live/cap` = viewports mounted / adaptive cap.

| Test | Result |
|---|---|
| Idle, 52 real | 60–62 fps, mean 16.3–16.7 ms, p90 ≤ 18.2, live 32/64 |
| Close → re-open ×3, 52 real | visible after **15 / 16 / 17 ms**; worst frames 25–67 (close), 28–31 (open) — was 283 ms |
| Fill 25 / 50 / 100 / 250 (snapshot) | all cells after 2 / 422 / 636 / 1,549 ms; worst frame **133 / 97 / 131 / 120 ms**, 2–4 frames > 40 ms — was 199 / 289 / 452 / 402–506 ms frames (1.65 s). A later run of the 250 fill: 2,863 ms, worst 177, 15 frames > 40 (variance between sessions) |
| Idle, 250 | 60 fps, mean 16.5, live 32/64 |
| Fast scroll 250, 63 px/frame, top→bottom→top ×2 | **62 / 65 fps**, mean 16.2 / 15.3, max 72 / 26 — was 30–32 fps, max 132 |
| Medium scroll 250, 32 px/frame | 45 fps, mean 22.3, p90 28.6, max 75, 1 frame > 70 |
| Slow scroll 250, 13 px/frame | **53 fps**, mean 18.8, p90 22.7, max 74, 2 frames > 70 — was 42 fps / max 259 |
| Very slow scroll 250, 6 px/frame | 56 fps, mean 17.8, p90 21.3 |
| Jump to the middle of 250 | art for ≥ 16 cards after **3 frames (51 ms)**; 48/64 live at rest, 62 fps |
| Repaint 250 after equip + lock (snapshot) | all cells after 2 ms; worst frame 82 ms (setState on 2 cards + bay strip) — was 402–506 |
| Close → re-open ×2, 250 | visible after 45 / 46 ms; worst 66 / 65 (close), 75 / 82 (open) |
| 5 quick close/open cycles, 250 | panel descendants **20,600 → 20,600**, no growth |
| Search "golden" on 250 / clear | worst frame 69 / 32 ms, hidden cards kept (children 252 → 252) — was a full rebuild |
| Tab: Brainrots → Pets | 52: switched after 261 ms (worst frame 267–277); 250: 295–326 ms (worst 307–353) — the Pets tab's own build (80 tiles), pre-existing, see limitations |
| Tab: Pets → Brainrots | 52: **56–59 ms** (worst 72–80); 250: **56–69 ms** (worst 81–94) — was 237 (52) / **900 ms** (250) with the re-parent, 600 before the round |
| Tab: Brainrots → Charms → Brainrots | 5 ms / 144 ms (worst 141 / 153) — the Charms Codex's own cost |
| Pet selection (seam, 80 pets) | worst frame 65–194 ms (first pick) / 94–250 ms (second) — two tiles + detail column; was a full `renderPets` (~260 ms) |
| Adaptive cap after three 250 fills | **64 / 64 / 64** — was 64 → 48 → 36 → 27 (three `[UIKit] ViewportCuller … cap` warnings) before the busy fix |
| Close on Pets, reopen | Pets still showing, Brainrots shell hidden, 0 FX entries, 44 viewport frames visible (32 of them under the hidden shell, not drawn) |
| Restore real bag | 52 cells, 4,641–4,778 descendants, 64 FX entries, live 32/64 |

Earlier runs of the same code paths on other viewports agree: laptop 1365×768 focused — fills 121 /
93 / 98 / 109 ms, fast scroll 62–67 fps, jump-to-middle 2 frames (75 ms), close/reopen 250 in 49 ms
(worst 84–118); desktop 1891×793 focused, pre-fling-gate build — fills 131 / 95 / 109 / 119 ms, slow
scroll 42 fps, close/reopen 52 in 16–20 ms.

No leak: separate sessions of fills, repaints, searches and close/open cycles all end at the same
descendant count after the real bag is restored (4,641 across three sessions; 4,778 in the last one,
which had also visited the Pets tab and keeps its hidden detail column; 4,497 at a session's cold
open — the difference is the NEW badge the restore puts on the 36 benched real UIDs, which the
synthetic snapshot in between had made "unseen": a relay artefact, deterministic, not cumulative).
The FxDriver reads 0 entries while the Bag is closed or another tab shows and 64 when the
Brainrots tab is open (its `Heartbeat` disconnects at 0); the culler publishes `CullerLive = 0` on
detach.

Preload cost, measured: after a snapshot that brings **250 distinct models** the decode of their
meshes lands on the main thread from +3 s for ~4 s — 100–170 ms frames, 28–36 fps in that window
(was 114–272 ms frames with 16-id batches back to back at +1.5 s). A real bag (52 items, ~30
distinct names) is ~19 batches, ~1 s, 3 s after join. Before the round the same decode happened on
demand while scrolling, as pop-in.

Pets tab (80 pets, same build): **8 live viewports / 1,165 BaseParts** in the panel — was 83 /
5,528 — 11–12 viewport frames exist in total (the mounted window); selecting a pet rebuilds exactly
the two tiles involved (`cell5 rebuilt, cell9 same, cell12 same`, then the reverse) and refreshes
the detail column. Idle with the Pets tab open: 60–62 fps, no work beyond the culler's pass.

## 7. Desktop — 1891×793 / 1891×785 (Studio window 1936×1040 on monitor 2)

Cold open (first `Build`) visible after 147 ms, worst frame 159 ms (focused). Panel 549,74 793×528
inside the screen; grid window 650×270, 75×96 cards, 2.6 rows visible, 32 live. No button outside
the panel; previews all inside their plates; 0 HUD elements overlapping the panel; `HudAudit
MeasurePanels({"bag"})`: 0 problems. Smallest controls on the glass: sort pills 62×26, HIDE PLOT
86×26, UNEQUIP ALL 95×26 (pre-existing sizes). Captures with the final bytes and a 250-card bag:
`after-01-bag250-desktop.jpg` (top of the list) and `after-03-bag250-mid-scroll.jpg` (jumped to
the middle, 1.5 s later) — every card in view carries its preview.

## 8. Laptop — 1365×768 (`average_laptop` device sim, focused)

Cold open visible after 205 ms, worst frame 214 ms. Panel 298,92 767×511 inside the screen; grid
window 629×261, 73×93 cards, 2.6 rows visible. No button outside the panel; sort pills 60×25, HIDE
PLOT 83×25, UNEQUIP ALL 92×25; previews inside their plates: 0 outside; 0 overlaps; HudAudit 0
problems. Scrolling the real bag to the bottom and back: 60 frames, live 32.

## 9. Mobile — iPhone 16, 733×371 logical

Panel 148,10 436×290, inside the screen (bottom 301 of 313 usable); close button 46×46 at 536,14;
tabs 32×29 each on the left rail; grid 358×142 with 57×72 cards on the glass; every button inside
the panel; previews inside their plates: 0 outside; 0 HUD elements overlapping the panel; HudAudit
0 problems. Capture: `after-02-phone-bag.jpg` (the same fit as round 2.5's `before-02-phone-bag.jpg`
— nothing moved). The controls under 30 px on the glass (sort pills 40×17, SHOW PLOT 56×17, UNEQUIP
ALL 64×17, tab tiles 32×29, EQUIP BEST 92×25) are the panel's authored 1080×720 shell at 0.40 —
the density decision recorded in `BackpackPanel.lua` on 2026-08-25 ("TOUCH FLOOR: KNOWN SHORT,
DELIBERATELY NOT PATCHED") — unchanged by this round; see limitations.

## 10. Console

Zero errors across every Play session of the round (fresh sessions after each build, ~12 in
total). One warning from the changed code fired during verification and was fixed before the
commit: `[UIKit] ViewportCuller: 30 frames over 22ms with 32 live viewports -- cap 64 -> 48`
(then `48 -> 36`, `36 -> 27`) — the adaptive cap counting the Bag's own chunked card build; after
the busy-frame fix, six 250-card fills in the final sessions produced none. The only warning
present in the final sessions is the pre-existing `[UIKit] panel module PetAbilityHelp did not
return { Id, Build } (got table)`.

## 11. Remaining limitations

- **New cards still cost the engine ~3–4 ms each** in the frame they first appear (layout, text
  fitting, strokes — round 2.5 measurement, unchanged): a snapshot that *adds* many cards at once
  (a first open of a 250-item bag, a mass catch) still shows 100–180 ms frames while the first
  window lands, then 4 cards a frame under the fold (1.5–2.9 s for 250). Hidden behind the panel's
  open glide on a real open; visible as a short stutter on a live bulk change. Cutting it further
  means a lighter card (56 instances) or building off-screen, both beyond "smallest safe change".
- **The model preload trades pop-in for decode hitches** in the seconds after a big snapshot (the
  numbers above). For a real player that is 3 s after join, on top of the world's own streaming;
  it never repeats for a name already warmed.
- **Close / re-open with 250 cards is 65–82 ms** (the panel's own glide over a 20,600-instance tree),
  against 25–31 ms for a real 52-item bag.
- **Medium-speed scrolling** of 250 cards sits at ~45 fps (each new row mounts up to 8 viewports a
  frame); fast flings and slow reads are at 53–65 fps.
- **The Pets tab still rebuilds its chrome and all 80 tiles on entry** (260–330 ms focused) and on
  every `renderPets` (snapshot, equip); only the 3D art is lazy and only selection is in place
  (65–250 ms: two tiles + the detail column's viewport). A persistent Pets shell like the Brainrots
  one is the next step if it matters; it is a larger change to a 700-line renderer.
- **Phone density**: the sub-30 px controls above are the authored panel at 0.40 scale — a real
  phone reflow of the Bag (fewer columns, taller bands, a bottom tab bar) is a layout change the
  brief's "not a redesign" rule and the owner's 2026-08-25 note both put out of scope here.
- Slow-scroll / fill numbers vary 20–50 % between sessions on the owner's machine (the same code:
  fill 250 in 1.5 s and 2.9 s); the ordering of every before/after pair above holds in every run.
- The `HudBagPetSelect` / `HudBagTab` attribute seams and the `__qa` relay are test-only; the relay
  is created by a Server `execute_luau` per session and does not exist in the saved place.

## 12. Round 3 regression (locked behaviour, re-checked after the change)

Desktop 1891×793: tracker at 1573,264 (right edge 1873), Goals bar at 1573,165, `+2 MORE` pill;
both `QuestTrackerUI` and `QuestBarUI` disabled while the Bag is open and re-enabled after close,
same positions; `J` slides the stack off (right edge 2231 vs 1891) and folds the Goals bar; `J`
again brings both back (1573,264 / 1573,165, enabled); the chevron compacts the cards (117 → 67)
**with the Goals bar staying visible at 165**, and expands them again; `questsHidden` ends the
session `false`. HIDE UI untouched. At 929×784 the same stack shows one whole card and `+2 MORE`
(the whole-card fit of Round 3). Nothing in Round 3's scripts changed (`git diff 7e44a98` lists
only the three Bag files and this folder).

## Repro notes

- Snapshots: Server `execute_luau` creates `ReplicatedStorage.__qa` (RemoteEvent) + `__qaStore`;
  the client sends its real `GetInitialData` JSON (`snap`), then `fire { count, placed, equip?,
  lock? }` builds `qa-<i>` entries from `ReplicatedStorage.BrainrotModels` names (218 models) with
  Golden / Diamond / Demon mutations and Huge / Massive sizes mixed in and fires the real
  `DataUpdated`; `restore` fires the stored real snapshot. Nothing touches the profile.
- The suite is armed as a client `task.spawn` that waits for two 1-second samples ≥ 50 fps before
  it runs and writes to `PlayerGui.__qaReport` / `__qaState`, so it measures a focused client
  whenever the window happens to be in front. Frame times are `RenderStepped` deltas.
- Probes across the exec VM boundary: `Grid` attributes `CullerLive` / `CullerCap` /
  `CullerDetached`, `FxDriver` attributes `FxEntries` / `FxRunning`, `HudPanelRequest` /
  `HudPanelCloseRequest` player attributes to open / close, `HudBagTab` / `HudBagPetSelect`.
- Byte-exact mirrors: Edit-mode `HttpService:PostAsync("http://127.0.0.1:8731/save?path=…",
  inst.Source)` to `tools/studio-bridge/bridge.py`, `HttpEnabled` restored to `false` in the same
  chunk; sizes and sha1 checked against `#inst.Source`. Every live Source is LF (a CRLF disk patch
  of `ViewportCuller` that had gone in through `Source =` was normalised first; every other script
  in the place is LF).
- Captures: `r3win.ps1 show` (`SW_SHOWNOACTIVATE` + `SetWindowPos` behind the Claude window at
  1912,-59 1936×1040), `r3cap.ps1 -Crop desktop` (11,175 1891×785 of the 1920×1001 client),
  `r3win.ps1 restore`. The client stays throttled while shown this way; only a focused window
  gives the frame times above.
