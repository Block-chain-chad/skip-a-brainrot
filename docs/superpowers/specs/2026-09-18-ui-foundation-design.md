# UI Foundation v2 + BrainrotCard — design spec (UI system round 1)

**Date:** 2026-09-18
**Status:** approved in brainstorm (2026-09-17/18), awaiting written-spec review
**Source of creative truth:** `Roblox_UI_System_Handoff.md` (the owner's UI system brief, 23 sections + priority order). It is treated the way the reward-reveal round treated its blueprint: it is the brief, reconciled against what already exists rather than rebuilt from zero.
**Source of code truth:** Roblox Studio (place 78783087742939, Team Create). `game-src/place-full/` is a commit-time mirror and has drifted before; it is never edited against, only re-synced from Studio.
**Round:** 1 of the handoff's priority list (items 1–4: universal window system, button components, Brainrot card, Brainrot preview renderer), with the Bag brainrot inventory grid as the first real consumer. Later rounds: Bag redesign (item 5), Quest system (6), main-nav cleanup (7), Worlds (8), Shop (9), remaining interactable interfaces (10).

---

## 1. Goal

One reusable component system that every later screen is built from, proven on one real surface. After this round:

- `ReplicatedStorage.Modules.UIKit` carries the handoff's semantic colour grammar, spacing scale, and the missing §17 components (semantic buttons, TabBar, SearchBar, SortButton, Modal, Toast, BrainrotCard, preview culling).
- `BrainrotCard` is the single component for a collectible card, data-driven, with rarity as its primary identity.
- `BrainrotThumb` frames every brainrot to the same perceived size regardless of silhouette.
- The Bag's brainrot inventory grid runs on `BrainrotCard` + culling, per UID.
- A Studio-only Gallery panel shows every component in every state — a living style guide and the verification surface for this and every later round.

Nothing else in the Bag, no other panel, and no legacy surface (`UITheme` Camp/Bazaar packs, the collaborator's `UIStyle`, Wheel, Egg Shop, Merchant, Trade, Booth, Fusion, legacy Rebirth shell, the four quest clients) changes in this round.

## 2. Facts this design depends on (read live, 2026-09-17)

**What already exists and is kept:**
- `UIKit.SpecTheme` — the PS99 white-chrome token set (2026-08-16): white shell, coloured bubble titles, pink-red close, candy-green CTAs, `S.Rarity` ramps for the 8 tiers, `S.Chrome` geometry in 1920×1080 spec px, `S.Tween`/`S.Scale`, rail art ids.
- `UIKit.PanelChrome` — `plate, shout, read, bindPressFeedback, shell (+addHeaderTabs), pill, statePlate, row, bar, toggle, slider, segmented, chip, sectionHead, tooltip, ribbon`. Every label it builds carries `NoPolish`.
- `UIKit.Builders` (`UI.*`) — `corner, stroke, gradient, gloss, hardShadow, label, surface, panel, button, track, setFill, artSlot, rarityFrame, claimRing, rainbowRing, touchMin, badge, ribbon`.
- `GameHUDClient` — the HUD shell and de-facto UI manager: `openPanel(id) / closePanel() / setBadge / pillAnchor`, single-open (also through the legacy `SideRail` registry), shared `HUDPanelBlur`, `glidePanel` entrance, ESC/B close, panel registration by dropping `{ Id, Build }` modules into `GameHUDPanels`.
- `Modules.BrainrotThumb` — cached, stripped, unparented masters cloned per viewport; `master / petMaster / eggMaster`, `framing(model, fov)` (bounding-sphere), `add / addPet / addMaster`, `isPale`, `FACING` overrides, the ice-fishing facing rule, the `RenderFidelity` Plugin-capability guard.
- `Modules.Platform` — `IsPhone/IsTablet/IsDesktop`, `Watch`, `Fit`, `PrepareGui`, the `PlatformOverride` attribute for deterministic device tests.
- `Modules.SoundKit` — `play(name)`; ids include `uiClick`, `panelOpen`, `panelClose`.
- `Modules.NumberFormat` — `Short(n)`, `Cash(n)`, `Rate(cps)`.
- `Modules.MutationConfig` — `Mutations.Color(name)` for the 12 mutations.
- `GameHUDPanels.IndexPanel.updateVisible` — a working on-screen-position viewport culler (`fillTile/clearTile`).
- `GameHUDPanels.BackpackPanel` (220 KB, 5,263 lines) — the Bag. The inventory grid is built by `fillBag()` (≈ line 3518): `groupBrainrots` stacks, `buildCard` (plateless pastel "splash" card, hash-cycled hue, rarity edge hidden), `buildFavBadge`, `buildStarBadge`, `wireCardHit` (hover lift, tooltip, touch release-anywhere guard), three sort chips, a search `TextBox`, an in-panel `flash()` toast. A dormant `buildJuiceTile` (2026-08-10) already implements the dark-tile style: dark plate, 3 px rarity edge, pips, tier band, foil, aura, holo ring, shared Heartbeat fx registry. The grid does **not** cull viewports today.
- `ToastClient` — server-driven result toasts (`push(success, message)`), a dormant item toast, and the measured stack anchor `UDim2.new(0.5, 0, 0.78, -140)` that clears the throw cluster.
- Rarity ladder: Common, Uncommon, Rare, Epic, Legendary, Mythic, Secret, God (no "Divine").
- The Bag's category tabs are a **vertical** column of six icon-over-label tiles (`tabsCol`, 74 px tiles).
- The save field `Fav` on a brainrot entry is the sell/delete **protection** flag (the fav badge is a lock).

**Engine/place constraints every component obeys (from the project's gotcha bank):**
- `TweenService` only animates `Size`/`Position` here; `UIScale`, `BackgroundTransparency`, `NumberValue`, `Sound.Volume` tweens silently no-op. Anything else animates from a shared Heartbeat driver.
- `UIPolish` restyles every text object without a `NoPolish` attribute; the kit sets it on everything it builds.
- The HUD runs at ≈0.72 cumulative `UIScale`; never position from `AbsolutePosition` deltas.
- `MeshPart.RenderFidelity` (and any `Plugin`-capability property) is writable in Studio but throws on a live client; `BrainrotThumb.ForcePrecise` already guards it — no new writes of that class.
- `openPanel` wraps `Build` in a `pcall`; a broken panel simply never opens (see §11 for the logging fix).
- Luau's 200-local ceiling: `BackpackPanel.Build` is one enormous function; new `require`s go at module top level, never inside `Build`. Every edited script is compile-gated with `loadstring(script.Source)`.
- Rotated GuiObjects are never clipped by their parent; a `UIGradient` on a `TextButton` multiplies its glyphs.
- `execute_luau` cannot write a `Source` over 200k characters (BackpackPanel is 220 KB) — whole-file restores go through `multi_edit` seams.
- Never preview on shared surfaces (`StarterGui`/`Workspace`) — Team Create collaborators see them. Never foreground Studio without asking.
- `PlatformOverride` is place state: set it for a phone test, remove it, confirm nil.

## 3. Decisions (user, 2026-09-17/18)

1. **Round 1 scope:** foundation (handoff items 1–4) + BrainrotCard/BrainrotPreview + Gallery panel + the Bag brainrot inventory grid as the first consumer. No wider Bag redesign.
2. **Colour rules: the handoff's §4, in full.** Green = positive, Red = destructive, Blue/navy = neutral utility and navigation (including the active tab), Gold = coins/rewards/value (Robux prices stay gold but always carry the Robux mark), Purple = gems/premium, Grey = inactive/secondary/disabled, rarity colours = collectibles only. This supersedes the 2026-08-17 rulings "gold = Robux only", "neutral = light grey", and the cyan quest-progress / violet reward-chip recolours. In this round the grammar lands through the new tokens, the rebuilt kit components, and an explicit sweep of the existing active-tab/filter paint sites (§5.1); other surfaces adopt it when their own round rebuilds them.
3. **Approach: evolve `UIKit` in place**, one new module per new component, old keys kept as aliases. Not a parallel `UIKit2`, not a framework rewrite.
4. **BrainrotCard base treatment: C — dark well tile** (chosen from three mockups in the visual companion; the plateless splash and the light rarity plate were rejected).
5. **Rarity is the primary visual identity of a collectible card.** Equipped / locked / selected / mutation / size are secondary indicators layered on top and must never overpower the rarity treatment (never recolour plate, edge, band or aura).
6. First real consumer = the **Bag brainrot inventory grid** (not Index); Index and other consumers migrate in later rounds once the Bag proves the component.
7. TabBar supports `orientation = "horizontal" | "vertical"` from day one.
8. `shell.primaryAction` accepts a button `kind` (default `positive`); footer groups accept any kind — "destructive on the right" is a visual rule, not an API restriction.
9. A shared **busy** button state (`setBusy`) exists for server-backed actions, distinct from disabled.
10. Modal backdrop = dark translucent scrim, no click-through; ESC / gamepad Back cancel when allowed; singleton; world blur optional and separate.
11. `UIKit.Toast` is the **only** toast renderer; `ToastClient` becomes remote wiring only. Two stacks never coexist.
12. Preview fit = **projected bounding-box corners against the viewport aspect**; sphere fit is a fallback only.
13. Card structure = layout-owned `CellRoot` + animated `VisualRoot`; selection ring and shadow live outside the clipped plate.
14. Badge priority/caps apply (§7.5); persistent badges never take over the art well.
15. `count` is optional; the **Bag inventory is per-UID** — no stacking in the grid. Aggregation is consumer-specific.
16. At most **two continuously animated decorative layers** per mounted card, whatever the tier allows.
17. Mutation badges carry the mutation's own colour; size badges use one neutral secondary treatment and never red.
18. `ViewportCuller`'s live cap is per-platform and adaptive; the Gallery stress test sets the defaults.
19. The card's protection control is a **lock/padlock toggle**, never "favourite"; `Fav` is normalised to `locked` at the panel boundary. A true favourite system, if ever added, is a separate state.
20. Every caught build error is **logged** with component/panel identity and traceback; fail-soft never means silent.
21. Rollback uses a **fresh pre-edit checkpoint** of every touched live file, committed before implementation starts.
22. Verification includes repeated open/close + scroll cycles for leaks (viewports, culler connections, Heartbeat driver).

## 4. Architecture & module layout

All paths under `ReplicatedStorage.Modules.UIKit` unless noted.

| Module | Status | Role in this round |
|---|---|---|
| `SpecTheme` | extend in place | `S.Role`, `S.Space`, `S.Card`, `S.Sound`; `S.Scale` retuned; old keys aliased; changed hex values recorded inline. |
| `PanelChrome` | extend in place | `shell` gains optional `stat`, `primaryAction`, `footer`; new `button`, `setEnabled`, `setBusy`; `bindPressFeedback` honours disabled/busy and plays the click sound; `addHeaderTabs` repaints to the new grammar. |
| `BrainrotCard` | new | Style-C collectible card, data-driven; owns mount/unmount of its viewport and its animation registration. |
| `ViewportCuller` | new | IndexPanel's on-screen culler lifted out; per-platform, adaptive live cap. |
| `TabBar` | new | Body-level tabs, horizontal or vertical. |
| `SearchBar` | new | Search input with clear-×, debounce. |
| `SortButton` | new | Segmented sort group over `PanelChrome.segmented`. |
| `Modal` | new | `Modal.confirm` only (§19 of the handoff). |
| `Toast` | new | The one notification stack. |
| `FxDriver` | new (internal) | The shared Heartbeat driver used by `BrainrotCard`, `setBusy` and any future kit animation; stands down when its registry is empty. |
| `Modules.BrainrotThumb` | extend in place | `fill` option + box-corner framing; sphere framing kept as fallback. |
| `StarterPlayerScripts.GameHUDPanels.GalleryPanel` | new | `Id = "gallery"`, Studio-only, no rail button. |
| `StarterPlayerScripts.GameHUDPanels.BackpackPanel` | edit one seam | `fillBag()` grid → `BrainrotCard` + `ViewportCuller`; search box → `SearchBar`; sort chips → `SortButton`; `flash` → `Toast`. |
| `StarterPlayerScripts.ToastClient` | edit | Its stack UI is removed; `push` calls `Toast.show`. |
| `StarterPlayerScripts.GameHUDClient` | edit (small) | `require`/`Build` pcalls gain warnings; Gallery trigger watcher. |
| `GameHUDPanels.GoalsPanel`, `IndexPanel`, `CharmsPanel` | edit (one expression each) | The grammar sweep: active tab/filter colour `Go` → `Role.Neutral` (§5.1). |

**Boundaries.** Components are pure builders: data in, instances plus a small API out (`set`, `setState`, `mount`, `unmount`, `destroy`, signals). They never require remotes, `BrainrotConfig`, `PlayerDataManager` or any gameplay module. Panels map raw entries to component data and wire remotes. `UITheme`, `UIStyle` and `Builders` are not modified.

**Data flow (unchanged).** Server → remotes (`DataUpdated`, `EquipBrainrot`, …) → panel state → component `set()` calls. No new remotes, no new client authority.

## 5. Tokens (`SpecTheme`)

### 5.1 `S.Role` — the colour grammar

| Role | Ramp (top → bottom) | Meaning | Notes |
|---|---|---|---|
| `Positive` | `63DE43 → 31A824` (= `S.Action.Go`) | equip, claim, confirm, teleport, buy with coins | white shout + dark stroke |
| `Destructive` | `FF5D80 → E02454` (= `S.Action.Danger`) | delete, remove, unequip-all where appropriate, close | one red for close and delete |
| `Neutral` | `4AA8FF → 1E7BE0` (**new**) | sort, filter, search, view, utility; **active** tab/nav | white shout + dark stroke |
| `Gold` | `FFCF40 → F09A0C` (= old `S.Action.Robux`) | coins, rewards, value, prices | dark ink via the >0.82 luminance gate; coin prices carry the coin glyph, Robux prices the Robux glyph |
| `Purple` | `C14CFF → 7D19E8` (= `S.Action.Premium`) | gems, premium | |
| `Disabled` | `D3DCE6 → B7C4D3` (= old `S.Action.Neutral`) | inactive tabs, secondary chips | dark ink, full contrast |
| `DisabledButton` | `B9C2CC → 96A1AD` (**new**) | a disabled button's fill | label at 0.45 transparency, no hover |
| `Selection` | `29C5FF` (= `Tokens.activeRing`) | selected card/tab ring | blue = navigation, so selection is blue |

Aliases kept for one round: `S.Action.Go/Danger/Premium/Robux/Gold/Neutral/Inert/Pale/Warn/GreenFill/Knob/Violet/VioletRow` keep working with their **current values**. `S.Action.Neutral` stays the light grey (it becomes an alias of `Role.Disabled`) — every existing paint closure pairs it as the *inactive* colour with `S.Action.Go` as active, so re-pointing it to blue would have turned inactive tabs blue and left active ones green, the opposite of the grammar. Old hex values are recorded inline next to every changed key.

**Grammar sweep (explicit, small):** the "active = green" tab/filter paint sites switch to active = `Role.Neutral` (blue), inactive = `Role.Disabled`: `PanelChrome.addHeaderTabs`, `PanelChrome.segmented`, `PanelChrome.toggle`'s on-state stays green (it is a positive state, not navigation), `GoalsPanel.updateTabVisuals` (≈ line 1242), `IndexPanel.updateWorldVisuals` / `updateFilterVisuals` (≈ 831 / 861), `CharmsPanel.setFilter` (≈ 1073). Each is a one-expression change inside an existing paint function; each panel is opened live afterwards. Action buttons that are green today (claim, equip, buy) stay green; gold/violet reward surfaces outside this round's seams are left for their own rounds.

Inactive header/body tabs use `Role.Disabled`; the ink rules of `pill()` (luminance gate) stay.

### 5.2 `S.Space`

`{ micro = 8, small = 12, std = 16, section = 24, large = 32 }` in spec px (the 1920×1080 sheet, same as `S.Chrome`). Every new component uses only these values; existing chrome numbers are untouched.

### 5.3 `S.Scale` and `S.Sound`

- `S.Scale = { Hover = 1.03, Press = 0.97 }` (was 1.06 / 0.94) per handoff §12. `bindPressFeedback` reads it, so every existing pill follows.
- `S.Sound = { Click = "uiClick", PanelOpen = "panelOpen", PanelClose = "panelClose" }` — SoundKit ids that already exist.

### 5.4 `S.Card`

Geometry as proportions of the card so one component fits the Bag's current cell (~100×132 panel px) and any later cell:

```
Plate      = { 3A4656, 2A3543 }     Radius = 14      Edge = 3
BandFrac   = 0.20  BandMin = 24     ArtInset = 4     Fill = 0.70
Pip = 7 (diamond)  Badge = 22       BadgeSmall = 14  MutationStar = 16
ArtWell    = white radial, 0.90 transparency at centre → 1 at edge
Light      = { Ambient 205/210/220, LightColor 255/248/232, Dir (0.18, 0.32, -1), LightDir = -Dir }   -- the Bag's relit rig, moved here
MaxAnimatedLayers = 2
MaxLive    = { Desktop = 48, Tablet = 32, Phone = 20 }   -- PROVISIONAL; replaced by the Gallery stress test (§10)
Variants   = { grid = {}, compact = { bandMin = 20, leftBadges = false }, hero = { title = true } }
Ladder     = see §7.4
```

## 6. Foundation components

### 6.1 WindowShell — `PanelChrome.shell` slots

Three optional props; every existing caller is unchanged.

- `stat = { text, icon? }` — summary stat right of the title (Fredoka, `S.Surface.ReadInk`). `shell.setStat(text)` updates it.
- `primaryAction = { kind = "positive" (default) | any role, text, onActivated? }` — one `button` in the header, left of the close. Exposed as `shell.primaryAction`.
- `footer` via `shell.addFooter({ left = { buttonSpec... }, right = { buttonSpec... } })` — a 72 px band under the body, no plate, `S.Space.std` gaps, left group left-aligned, right group right-aligned. **Rule:** destructive actions go in `right`; secondary/advanced in `left`. The API accepts any kind in either group. When a footer exists the body shrinks by `72 + S.Space.std`. `shell.footer` exposes the holder.
- `addHeaderTabs` repaint: active = `Role.Neutral` + white shout, inactive = `Role.Disabled` + dark ink.

### 6.2 Buttons — `PanelChrome.button`, `setEnabled`, `setBusy`

`button({ kind, text, size?, icon?, enabled?, sound?, parent, zIndex?, layoutOrder?, name? })` → `TextButton`, implemented on `pill` (same geometry: `CtaRadius` 22, `CtaOutline` 6, gloss, LuckiestGuy label with stroke, luminance ink gate).

- `kind` ∈ `positive | neutral | destructive | gold | purple` → `S.Role` ramp. Stored on the button as attributes (`UIKind`, `UIRampTop`, `UIRampBottom`) so runtime repaints never guess.
- `size`: default `S.Chrome.CtaSize` (230×76); `"small"` = 64 tall; or any `UDim2`.
- `icon`: optional 40 px image left of the label.
- Feel: hover 1.03 / press 0.97 (Size tween on the button — unchanged mechanism), `SoundKit.play(S.Sound.Click)` on `Activated` unless `sound = false`.
- `PanelChrome.setEnabled(btn, on)`: off → fill `Role.DisabledButton`, label 0.45 transparency, `Active = false`, `UIEnabled = false` attribute (read by `bindPressFeedback` to skip hover/press/sound). On → the stored ramp and label restored. Replaces `pill`'s build-time-only `enabled = false` (kept for compatibility, now implemented via `setEnabled`).
- `PanelChrome.setBusy(btn, on, { timeout = 10 }?)`: keeps size and ramp; sets `UIBusy = true`; input/hover/press/sound suppressed; label dimmed to 0.35 transparency; a `BusyDots` label ("· · ·") pulses via `FxDriver`. After `timeout` seconds busy auto-clears and `warn`s with the button's full name. `setBusy(btn, false)` clears immediately. Busy and disabled compose: a busy button that is then disabled shows disabled; clearing busy leaves it disabled.
- `pill`, `statePlate`, `close` are unchanged; the close button already wears `Role.Destructive`.

### 6.3 TabBar — `UIKit/TabBar`

`TabBar.new({ tabs = { { id, text, icon? } }, selected, onChanged(id), orientation = "horizontal" | "vertical", parent, zIndex?, size? })` → `{ root, set(id), get(), setBadge(id, n), destroy() }`.

- Horizontal: `UIListLayout` horizontal, chips 64 tall, width from text (min 120). Vertical: `UIListLayout` vertical, icon-over-label tiles 74 tall (the Bag's current tile size), full column width.
- Paint: active `Role.Neutral` + white shout (+ `Selection` ring), inactive `Role.Disabled` + dark ink. Hover pops the glyph/icon only, never the tile (tiles are layout children). `UI.touchMin(44)` on every hit.
- `setBadge` draws `UI.badge` at the tile's top-right.
- Same paint rules as `addHeaderTabs` so the two levels read as one family; header tabs stay senior (72 tall, in the header).

### 6.4 SearchBar — `UIKit/SearchBar`

`SearchBar.new({ placeholder, width, onChanged(query), parent, zIndex? })` → `{ root, box, get(), set(text), clear(), focus(), destroy() }`.
White well (`RowTop/RowBottom`), `OutlineSoft` edge, 64 tall, magnifier glyph left, Fredoka `ReadInk` text, `ClearTextOnFocus = false`, `NoPolish`; a clear-× (`Role.Disabled` chip) appears when non-empty. `onChanged` fires 80 ms after the last keystroke (debounced), and immediately on `clear()`.

### 6.5 SortButton — `UIKit/SortButton`

`SortButton.new({ modes = { { id, label } }, selected, onChanged(id), parent, zIndex? })` → `{ root, set(id), get(), destroy() }`. A segmented group built on `PanelChrome.segmented` with the new paint (active `Role.Neutral`, others `Role.Disabled`), 64 tall, `S.Space.small` gaps.

### 6.6 Modal — `UIKit/Modal`

`Modal.confirm({ title, body, loss?, confirmText, confirmKind = "destructive" | "positive", cancelText = "CANCEL", cancelable = true, onConfirm, onCancel?, parent? })` → `{ close() }`.

- A small white shell (radius 32, 7 px dark edge, 560×380 spec px, centred), coloured bubble title (`S.TitleInk.default` unless `titleInk` given), Fredoka body text, an optional `loss` line in `Role.Destructive` ink ("You will lose …"), Cancel (`Role.Disabled`) left, Confirm (`confirmKind`) right, both `button`s.
- Backdrop: a full-screen scrim at `BackgroundColor3 = 0,0,0`, `BackgroundTransparency = 0.45`, `Active = true` — it swallows every input; nothing behind can be clicked. A scrim click cancels only when `cancelable`.
- ESC and gamepad `ButtonB` cancel when `cancelable`. Gamepad selection lands on Cancel when the modal opens.
- **Singleton:** opening a second modal closes the first (its `onCancel` runs).
- World blur is not part of the modal; a caller that wants it uses the existing `HUDPanelBlur` machinery.
- Parent: the HUD host's screen gui at a zIndex band above every panel (`PanelChrome.zBase + 60`).
- Only dangerous actions use it (handoff §19). First consumer is the Gallery; Bag delete, Sell confirm and Rebirth confirm adopt it in their own rounds.

### 6.7 Toast — `UIKit/Toast`

`Toast.show({ text, tone = "info" | "success" | "error" | "reward", icon?, hold = 3.2 })`.

- One stack, bottom-centre, bottom pinned at `UDim2.new(0.5, 0, 0.78, -140)` (ToastClient's measured anchor that clears the throw cluster), lines growing upward, max 4 lines, oldest dismissed first.
- Plateless shout text with dark stroke (the PS99 field-study language): info white, success `Role.Positive[1]`, error `Role.Destructive[1]`, reward `Role.Gold[1]`. Slide-in/out via `Position` tweens.
- `ToastClient` keeps its remote subscriptions and the dormant item-toast code path, but its own stack UI is **removed**; `push(success, message)` becomes `Toast.show({ text = message, tone = success and "success" or "error" })`. There is exactly one renderer.

### 6.8 Kept as they are

`PC.tooltip` (BrainrotCard raises hover signals; the panel shows it — touch = tap, as today), `PC.bar` (the thick quest bar variant comes with the quest round), `sectionHead`, `chip`, `toggle`, `slider`, `segmented`, `row`, `ribbon`.

## 7. BrainrotCard — `UIKit/BrainrotCard`

### 7.1 Contract

```lua
local card = BrainrotCard.new({
    kind      = "brainrot" | "pet",
    name      = "Tung Tung",              -- display name; the model key for brainrots
    model     = "pet_01_mosslarva",       -- pets only (PetConfig.Model)
    rarity    = "Legendary",              -- one of the 8 tier names
    income    = 9500,                     -- number; rendered with NumberFormat.Rate
    mutation  = "Golden"?,                -- MutationConfig name
    sizeTag   = "Huge" | "Massive"?,
    count     = 3?,                       -- optional stack count; the Bag never passes it
    state     = { equipped = false | padIndex, locked = boolean, selected = boolean, new = boolean },
    lock      = { onToggle = function(nextLocked: boolean) }?,   -- shows the padlock toggle
    title     = "Golden Huge Tung Tung"?, -- hero variant only
    variant   = "grid" | "compact" | "hero",
    parent, zIndex?, layoutOrder?, name?,
})
-- card.root (CellRoot), card.set(patch), card.setState(patch), card.mount(), card.unmount(),
-- card.destroy(), card.Activated, card.HoverStart, card.HoverEnd  (signals)
```

The card never reads `BrainrotConfig`, `RarityConfig`, remotes or save data. The panel maps. Unknown `rarity` → the Common ladder plus one `warn` per unknown name.

### 7.2 Structure

```
CellRoot (Frame, transparent, Size 1,1 — owned by the consumer's UIGridLayout; never animated)
└─ VisualRoot (Frame, transparent, AnchorPoint 0.5,0.5, Position 0.5,0.5, Size 1,1 — hover/press tween Position/Size HERE)
   ├─ Shadow        (Frame under the plate, offset +4 px, outside the clip)
   ├─ SelectionRing (Frame, Size 1,+8 / 1,+8, Selection-coloured 3 px stroke, outside the clip, hidden unless selected)
   └─ Plate         (Frame, ClipsDescendants = true, S.Card.Plate gradient, radius 14, 3 px rarity edge)
      ├─ Aura, Foil, ArtWell, ContactShadow, ArtHolder (viewport mounts here), HoloRing
      ├─ Pips, Band (TierName, Count), Rate pill, Sparkles
      └─ BadgesRight (stack), BadgesLeft (row under the pips)
```

`UIGridLayout` sizes `CellRoot`; nothing the layout owns ever changes size. Nothing that must extend past the card (ring, shadow) lives inside the clipped plate.

### 7.3 Anatomy, bottom → top

1. **Plate** `3A4656 → 2A3543`, radius 14; **3 px edge in the tier's `S.Rarity[...][2]`**.
2. **Aura** (Legendary+): tier-coloured vertical gradient rising from the band to 45 % height.
3. **Foil** (Epic+): white sheet at the tier's alpha with a static rainbow `UIGradient` at 25°.
4. **ArtWell**: soft white radial behind the model so near-black bodies separate from the plate; **ContactShadow** oval at the feet.
5. **ArtHolder**: inset `ArtInset`, full width, from the top to `Band + 8`. The viewport mounts here.
6. **HoloRing** (Mythic+): `UI.rainbowRing` around the art holder.
7. **Pips** (top-left): diamonds, count by tier (§7.4), lit in the tier's light colour, unlit `39414F`.
8. **Band** (bottom, `BandFrac` of the card, min `BandMin`): tier ramp; **tier name** (shout, white, left) and `count` (right) when given. Common's band sits at 0.75 transparency so the ladder starts quiet; Mythic+ is the animated rainbow with dark ink `12060C`.
9. **Rate pill**: `NumberFormat.Rate(income)` in shout white with dark stroke on a dark pill, centred just above the band.
10. **Sparkles** (Secret, God): three "✦" labels at the art's top corners.

The dormant `buildJuiceTile` is the reference implementation for 1–3 and 7–8; it is lifted into the component, not called.

### 7.4 Tier ladder — `S.Card.Ladder`

| Tier | edge / band ramp | pips | band | foil α | aura | holo ring | sparkles | **animated layers (max 2)** |
|---|---|---|---|---|---|---|---|---|
| Common | `S.Rarity.COM` | 1 | muted (0.75) | — | — | — | — | none |
| Uncommon | `UNC` | 1 | 0.35 | — | — | — | — | none |
| Rare | `RARE` | 2 | 0.35 | — | — | — | — | none |
| Epic | `EPIC` | 3 | 0.35 | 0.87 | — | — | — | none |
| Legendary | `LEG` | 4 | 0.35 | 0.80 | breathing | — | — | aura |
| Mythic | `MYTH` | 5 | rainbow | 0.70 | breathing | static | — | band drift, aura |
| Secret | `SEC` | 5 | rainbow | 0.70 | strong, static | static | twinkle | band drift, sparkles |
| God | `GOD` | 5 | rainbow | 0.70 | strong, static | static | twinkle | band drift, sparkles |

Foil never drifts. "Strong" aura = 0.35 transparency held. The ladder is one table; the card reads it and nothing is hard-coded per tier elsewhere.

### 7.5 Secondary indicators, priority and caps (Decision 5 made concrete)

Indicators never recolour plate, edge, band or aura. They are corner-anchored and small.

- **Top-right stack** (persistent, `Badge` 22 px, 4 px gap), priority **Locked > Equipped > NEW**, capped per variant: grid **2**, compact **1**, hero 3.
  - Locked: grey padlock badge (`Role.Disabled` ramp, dark glyph). With `lock.onToggle` it is a button. Desktop: visible on hover when unlocked, always when locked. Touch (no hover): always visible, drawn subdued (outline glyph, 0.5 transparency) when unlocked and solid when locked — it is the card's only interactive badge, so it must stay reachable. It counts toward the stack cap either way. Toggling calls `onToggle(not locked)`; the panel confirms the new state through `setState` when the server answers.
  - Equipped: `Role.Positive` badge, "✓" plus the pad number when `equipped` is a number.
  - NEW: `BadgeSmall` (14 px tall) red tag — the smallest of the three; dropped first when the cap is hit.
- **Top-left**: the pip row; beneath it one row shared by the **mutation star** (16 px, filled with `Mutations.Color(mutation)`, dark outline) and the **size chip** (dark navy `S.Surface.Track` plate, white shout `HUGE` / `MASSIVE`, never a red). Compact hides this row (mutation/size live in the tooltip).
- **Selected** = `SelectionRing` outside the edge + the hover lift. The old full-card pulsing green "equipped" ring is gone.
- Combined persistent badge area on a grid card ≤ 15 % of the art well; the caps above guarantee it at every cell size ≥ 90×120.
- A future favourite system is a separate `state.favourite` with its own badge; it is not this lock.

### 7.6 Feel and motion

- Hover: `VisualRoot` position −3 px (0.12 s Back out) and `HoverStart`; leave restores and raises `HoverEnd`. Press: +1 px sink; release → hover or rest. Touch: no hover; tap = `Activated`.
- The touch **release-anywhere guard** (one `UserInputService.InputEnded` connection at module level tracking the single pressed card) moves into the component from `BackpackPanel`.
- All decorative animation (aura breathe, band drift, sparkle twinkle, busy dots) registers with `FxDriver`: one `Heartbeat` connection for the whole client, per-frame work proportional to registered entries; the connection is disconnected when the registry empties and re-created on the next registration. A card registers on `mount()` and unregisters on `unmount()`/`destroy()`; a card whose ancestor is not visible is skipped by the driver.

### 7.7 Missing art and errors

`BrainrotThumb.master(name)` nil → the existing "?" placeholder tile inside the art holder; the rest of the card renders normally. A model that fails to clone logs a `warn` with the card name and traceback and shows the same placeholder.

## 8. BrainrotPreview — `BrainrotThumb` + `ViewportCuller`

### 8.1 Framing: projected box corners (Decision 12)

`BrainrotThumb.framing(model, fov, opts?)` gains `opts = { aspect, fill, dir }` and a new default path:

1. Take the model's oriented bounding box (`GetBoundingBox` — the existing pivot-frame convention, `FACING` and the ice-fishing rule applied first) and its 8 corners in world space.
2. Camera basis from `dir` (the view direction, default `DEFAULT_DIR`), look-at initially the box centre. Express each corner in camera space: lateral `x`, vertical `y`, depth `c` along the view axis (positive = farther than the look-at).
3. Half-angles: `tanV = tan(fov/2)`, `tanH = tanV × aspect`. For each corner and axis the smallest distance that keeps it inside the target fill is closed-form:
   `d = |lateral| / (fill × tanAxis) − c`. Camera distance = the max over all corners and both axes (floor `MIN_DIST`).
4. **Re-centre once:** with that distance, project the corners, take the midpoint of the projected extents on each axis, and shift the look-at laterally by the corresponding world offset; recompute the distance. The Gallery's framing set prints the residual off-centre error and fill per model; a second pass is added only if any roster model measures above 2 %.
5. Return `centre, dist` exactly as before, so `add`/`addMaster`/`CatchReveal` keep their call shape.

`fill` defaults to `S.Card.Fill` (0.70) for cards; `aspect` comes from the viewport's `AbsoluteSize` at mount (falls back to 1 when unrendered). The bounding-sphere path stays as `framingSphere` and is used (a) when `opts.spin` is true — CatchReveal's orbiting camera needs every angle to fit — and (b) when the model has no bounding box. Equal perceived fill for tall, wide, grouped and odd silhouettes is verified in the Gallery against the extreme set (§10).

### 8.2 Mount / unmount

`card.mount()` calls `BrainrotThumb.add` / `addPet` into the art holder with `S.Card.Light` and `fill`; `card.unmount()` destroys the viewport. Plate, band, badges and rate always exist, so a scrolling grid shows finished cards with art streaming in. `destroy()` unmounts first.

### 8.3 `ViewportCuller` — `UIKit/ViewportCuller`

`ViewportCuller.attach(scroll: ScrollingFrame, cards: { BrainrotCard }, { margin = 0.5, maxLive = nil, budgetMs = 22 }?)` → `{ refresh(), setCards(cards), detach() }`.

- On `CanvasPosition` / `AbsoluteSize` change (coalesced to one pass per frame) it computes each card's on-screen rectangle from `CellRoot.AbsolutePosition/AbsoluteSize` against the scroll's rectangle ± `margin × viewport height` (the IndexPanel test), mounts intersecting cards nearest-to-centre first up to the live cap, and unmounts the rest. `mount`/`unmount` are idempotent.
- **Live cap:** `maxLive` if given, else `S.Card.MaxLive[Platform.Class]` (Console counts as Desktop). **Adaptive:** while cards are mounted the culler samples `Heartbeat` dt; 30 consecutive frames over `budgetMs` step the cap down 25 % (floor 12) and trigger a pass; the cap never climbs back within one attach — a fresh `attach` (panel reopen) starts from the platform default again.
- `detach()` disconnects everything and unmounts every card; the consumer calls it on every rebuild and on panel close.

### 8.4 Pale and dark models

The dark plate solves the 2026-08-25 white-on-white bug structurally (no per-card art mat, `isPale` is no longer consulted by the card). Near-black bodies are separated by the `ArtWell` radial and the relit rig from the camera side.

## 9. First consumer — the Bag brainrot inventory grid

One seam in `BackpackPanel`: the Brainrots tab's `fillBag()` grid plus its two controls. Equipped bay (`buildRackSlot/buildBaySlot`, still on `buildCard`), header, counter, Pets / Charms / Keys / Tags / Index tabs, the replace picker and the tooltip are untouched.

- **Per UID (Decision 15):** `fillBag` iterates `ownedBrainrots` directly; `groupBrainrots` is no longer called for the grid. Search matches name / mutation / size. Sorts: Rarity (tier rank, then income), Newest (snapshot order), A–Z (name, then income). Counter text: `N shown / M owned`.
- **Mapping** (in the panel):
  ```lua
  BrainrotCard.new({
      kind = "brainrot", name = e.Name,
      rarity = infoByName[e.Name] and infoByName[e.Name].Rarity or "Common",
      income = valueOf(e.Name, e.Mutation, e.Size),
      mutation = e.Mutation, sizeTag = e.Size,
      state = { equipped = held[e.Uid] or false, locked = e.Fav == true, new = newUids[e.Uid] == true, selected = false },
      lock = { onToggle = function(next) remotes.ToggleLock:FireServer({ e.Uid }) end },  -- the remote buildFavBadge fires today (capacity-gated, plot-synced)
      variant = "grid", parent = cell, zIndex = 15, layoutOrder = i,
  })
  ```
  `Fav` is read here and nowhere else; the card only ever sees `locked` (Decision 19).
- **Wiring:** `card.Activated` → the existing equip path (clear `newUids`, free-slot check, `remotes.EquipBrainrot:FireServer(uid)`); "NO FREE SLOTS — UNLOCK ONE" goes through `Toast.show({ tone = "error" })`. `HoverStart/HoverEnd` → the existing `showCardTip(entry, card.root)` / `hideCardTip()`.
- **Culling:** after building the cells, `culler = ViewportCuller.attach(scroll, cards)`; `fillBag` calls `culler.detach()` before rebuilding; the panel's close/hide path (`wrapper.Visible` false) also detaches. The keep-scroll restore stays.
- **Controls:** the search `TextBox` → `SearchBar` (same `searchQuery`/`fillBag` handler); the three sort chips → `SortButton` (same `sortMode`/`fillBag` handler).
- **Untouched old code:** `buildCard`, `buildFavBadge`, `buildStarBadge`, `wireCardHit` stay for the bay; the grid's dead splash branch and `groupBrainrots` are left for the Bag round's cleanup. New `require`s (`BrainrotCard`, `ViewportCuller`, `SearchBar`, `SortButton`, `Toast`) at module top level; compile-gate after every edit.

## 10. Gallery panel — `GameHUDPanels/GalleryPanel`

- `Id = "gallery"`. The module returns `{ Id, Build }` only when `RunService:IsStudio()`; in the live game it returns an empty table and is skipped by registration — it can never appear for players.
- **Trigger:** `Players.LocalPlayer:SetAttribute("HudGallery", true)` from the client command bar during Play. A watcher in `GameHUDClient` opens `openPanel("gallery")` when the attribute turns true and clears it on close. Player attributes never persist into the place file (unlike `PlatformOverride`).
- Opens through `openPanel`, so it inherits blur, single-open, glide and ESC. No rail button.
- **Sections** on a **vertical `TabBar`** (proving that orientation):
  1. *Tokens* — every `S.Role` ramp as a swatch with its name and meaning; the `S.Space` ruler; the type sizes.
  2. *Buttons* — every kind × normal / hover-hint / disabled / busy, both sizes, with and without icon; a "trip busy" button that times out.
  3. *Shell slots* — a mini shell showing `stat`, `primaryAction` (each kind), and a footer with left/right groups.
  4. *Tabs* — header tabs, horizontal TabBar, vertical TabBar, with badges.
  5. *Inputs* — SearchBar, SortButton, segmented, toggle, slider, bar.
  6. *Modal + Toast* — buttons that open destructive/positive confirms (cancelable and not) and fire each toast tone.
  7. *Cards* — `BrainrotCard` for every tier × every state (equipped, locked, new, selected, mutation, size, count, missing art), all three variants, and the **framing set**: a tall model (narwhal), a wide one (hammerhead), a two-character group, the tadpole, a pale Tundra model, a near-black model — each with its projected-fill percentage printed under it.
  8. *Stress* — a scrolling grid of N cards (N = 100 / 250 / 500 selectable) on the culler, with a live readout of mounted viewports, the current cap, and average frame time. **This is what replaces the provisional `S.Card.MaxLive` numbers**, per platform (desktop, and phone via `PlatformOverride`).
  9. *Legacy* — an old `pill` and old tab beside the new `button` and `TabBar` for the migration audit.
- Every section is built from `S` and the components — no bespoke styling — so the Gallery is the living style guide. A section whose build throws renders a red error tile with the message in place of the section (and the warning goes to the console, §11).

## 11. Error handling and logging (Decision 20)

- Every component validates its props; a bad or missing value degrades (Common ladder, "?" art, default kind) and `warn`s **once per distinct problem** with the component name and the offending value.
- Every `pcall` in the kit and in this round's edits reports on failure with `warn(("[UIKit] %s: %s\n%s"):format(identity, err, debug.traceback()))`. This includes `GameHUDClient`'s panel `require` pcall (module name) and its `Build` pcall (panel id) — fail-soft behaviour is unchanged, silence is not.
- `setBusy` timeouts warn with the button's full name. `ViewportCuller` warns once when the adaptive cap steps down (with the measured dt).
- The Gallery shows failures inline (§10). A broken component never disappears behind a bare `pcall`.

## 12. Performance budget (handoff §20)

- Viewports: only mounted cards hold one; the cap is per-platform and adaptive (§8.3). Masters stay cached and stripped (`BrainrotThumb`).
- Per-frame work: one `FxDriver` Heartbeat for the whole client; each mounted animated card registers at most two layers; the driver skips entries whose ancestor is hidden and disconnects when empty.
- No particles, lights or beams in cards (viewports cannot render them anyway).
- No per-card `InputEnded` connections; one shared guard.
- Rebuilds: `fillBag` rebuilds cells (as today); the culler makes the mount cost proportional to the visible window, not the bag.

## 13. Verification

- **Checkpoint first** (§14), then compile-gate every edited script with `loadstring(script.Source)` in Edit mode after each edit.
- **Gallery pass** in Play: every section opens and renders; captures per section (I ask before any foreground capture); the framing set shows equal perceived fill across the six extremes; the stress section establishes `MaxLive` for desktop and phone (`PlatformOverride = "Phone"` set in Edit, removed after, confirmed nil).
- **Bag pass** on the 404-item save: grid renders per UID with the right counts; mounted viewports ≤ cap while scrolling top-to-bottom-to-top; hover lift + tooltip, press feedback, lock toggle round-trip, equip round-trip, "NO FREE SLOTS" toast; search and sort still filter/sort; keep-scroll survives a rebuild.
- **Repeated-cycle leak check** (Decision 22): 10 × (open Bag → scroll to bottom → scroll to top → close), then 10 × (open Gallery → Stress 500 → close). After the last close: zero `ViewportFrame`s under the Bag/Gallery trees, the culler reports detached, `FxDriver` reports no connection and an empty registry, and the count of `Instance`s under `PlayerGui` is flat across cycles (± the panel's own build).
- **Grammar audit** of every swept paint site (§5.1): header tabs, segmented controls, Goals tabs, Index world/filter chips, Charms filter chips — active is blue with white shout, inactive grey with dark ink, nothing else moved; Settings' rarity-keyed chips and every green action button unchanged.
- Console clean through all of the above. Mirror re-synced byte-exact for every touched file; spec + plan + `game-src/README.md` note committed.

## 14. Rollout, checkpoint and rollback (Decision 21)

- **Before the first edit:** `script_read` the live source of every existing file this round touches — `UIKit.SpecTheme`, `UIKit.PanelChrome`, `Modules.BrainrotThumb`, `GameHUDPanels.BackpackPanel`, `GameHUDPanels.GoalsPanel`, `GameHUDPanels.IndexPanel`, `GameHUDPanels.CharmsPanel`, `ToastClient`, `GameHUDClient` — write each to its mirror path and commit as `checkpoint: pre UI-foundation round live sources` with byte counts in the message. The mirror is otherwise stale (BackpackPanel: 140 KB on disk vs 220 KB live; CharmsPanel has never been mirrored) and must not be trusted as a rollback source.
- **Rollback:** new modules are additive (delete them); token changes carry the old hex inline (one-line reverts); the Bag seam is restored from the checkpoint via `multi_edit` on the `fillBag` region and the module-top requires (whole-file writes are impossible above 200k chars); `ToastClient`'s stack is restored from the checkpoint file. Each rollback step is a documented anchor pair in the plan.
- All edits happen in Studio (Team Create persists them; the owner publishes). Two sessions may edit this place: every `multi_edit` anchors on a line read live in the same round, never on the mirror.

## 15. Out of scope (later rounds)

Bag redesign (header stat/Equip Best/footer utilities/equipped section/bay migration/dead-code cleanup), Quest system (HUD tracker + Quests window, QuestCard, thick bar), main-nav cleanup, Worlds, Shop, Index migration onto BrainrotCard, Sell/Trade/Egg/Booth/Fusion cards, Modal adoption by Bag delete / Sell / Rebirth, the legacy packs (`UITheme`, `UIStyle`) and every surface built on them, `ui-web/` mirror sync, production art, a favourite system.

## 16. Risks

- **The grammar sweep touches three more panels** (Goals, Index, Charms) for a one-expression change each. Mitigation: checkpointed, live-anchored, opened live after the edit; the old expression is the revert.
- **Per-UID grid on a 400+ bag** is 4× the cards the stacked grid drew. Mitigation: the culler is the point of the round; the stress section proves the cap before the Bag migration is enabled.
- **Concurrent editing** of `BackpackPanel`/`GameHUDClient` by another session. Mitigation: live anchors only, checkpoint commit, compile gate, and a live open after each step.
- **`openPanel`'s pcall** hides a broken Bag. Mitigation: §11 logging lands before the Bag seam is touched, and every step ends with a real open.
- **Box-corner framing** on models with a pivot far from the body (authored pivots on limbs were seen on plot models). Mitigation: framing uses the bounding box, not the pivot position; the framing set in the Gallery includes the known offenders.
