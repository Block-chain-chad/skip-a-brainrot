# Handoff: Chunky Cartoon Game HUD (Roblox)

## Overview
A complete, original HUD/menu system in the "chunky cartoon" arcade style: thick near-black outlines, glossy top-lit gradients, hard offset drop shadows, heavy stroked display type. It covers six panels plus the persistent HUD:

| Panel | Purpose |
|---|---|
| Season Pass | Two-track (Free / Season Pass) tier reward ladder with XP progress, tier skip, purchase CTA |
| Backpack | Inventory grid with rarity frames, category tabs, item detail + equip |
| Settings | Audio sliders, graphics quality segmented control, gameplay toggles, code redeem / reset |
| Daily Rewards | 7-day login streak with claimed / today / locked states and a "grand" day 7 |
| Index | Collection/discovery grid with completion progress and a 100% reward |
| Goals (Quests) | Daily / Weekly / Season objective rows with progress bars and claim buttons |
| HUD | Currency cluster (top-left) + right-side vertical nav rail with notification badges |

**This is an original design, not a copy of any existing game's assets, artwork, wordmarks, or icons.** All artwork positions are labelled empty slots for the studio's own art.

## About the design files
The files in this bundle are **design references authored in HTML/CSS** — they show intended look, geometry, states and behaviour. They are **not** production code to port literally.

The task is to **recreate these designs in the game's Roblox environment** (ScreenGui + Luau, or the project's existing UI framework such as Roact/React-lua/Fusion if one already exists), using this document's measurements and tokens as the source of truth.

`tokens.lua`, `ui_builders.lua` and `data_schema.lua` in this folder ARE meant to be used directly (or adapted) — they are Luau, not HTML.

## Fidelity
**High-fidelity.** Every colour, gradient stop, stroke weight, corner radius, size, gap and font size below is final and should be reproduced exactly. Only the artwork inside the labelled slots is missing.

---

## 1. Canvas, scaling and layering

Design canvas: **1350 × 775 px** (the reference resolution — everything below is in these px).

Roblox setup:

```lua
local gui = Instance.new("ScreenGui")
gui.Name = "HUD"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- Root frame is exactly the design canvas, centred, then uniformly scaled.
local root = Instance.new("Frame")
root.Size = UDim2.fromOffset(1350, 775)
root.Position = UDim2.fromScale(0.5, 0.5)
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.BackgroundTransparency = 1

local scale = Instance.new("UIScale", root)
local function fit()
    local vp = workspace.CurrentCamera.ViewportSize
    scale.Scale = math.min(vp.X / 1350, vp.Y / 775)
end
```

Build every child in **offset** units against that canvas so the px numbers in this document transfer 1:1. Recompute `fit()` on viewport resize. On phones the same layout scales down; if you need a portrait variant, treat it as a separate pass (not specified here).

Z layers (`ZIndex`): world 0 · HUD currency 20 · nav rail 30 · modal scrim + panel 25 (rail deliberately sits **above** the scrim so nav stays usable) · toast/reward-fly 80.

The currency cluster is **hidden while any panel is open** (the panel header would otherwise cut through it). Currency is instead communicated inside panels by price chips (e.g. "Buy Pass 799 ◆").

### Style primitives Roblox has no direct equivalent for

| Design property | Roblox implementation |
|---|---|
| `border: 4px solid #16170F` | `UIStroke` — `Thickness = 4`, `Color = #16170F`, `ApplyStrokeMode = Border` |
| Text outline | `UIStroke` on the `TextLabel` — `ApplyStrokeMode = Contextual`, thickness per type scale below |
| `linear-gradient(180deg, …)` | `UIGradient` — `Rotation = 90`, `ColorSequence` with the listed stops |
| Top gloss `inset 0 5px 0 rgba(255,255,255,.5)` | child Frame, height 5–6, top-anchored, white, `BackgroundTransparency ≈ 0.45`, same `UICorner`, `ZIndex` +1 |
| Bottom shade `inset 0 -6px 0 rgba(0,0,0,.18)` | same trick, bottom-anchored, black, transparency 0.82 |
| Hard drop shadow `0 5px 0 #16170F` | duplicate Frame behind, `Position` +5 px Y, filled `#16170F`, identical `UICorner` (**not** an ImageLabel shadow) |
| Modal soft shadow `0 14px 22px rgba(0,0,0,.35)` | 9-slice shadow ImageLabel behind the panel, or omit — it reads fine without on small screens |
| Inset track shadow | child Frame at the top inside the track, height 4, black, transparency 0.55 |
| Conic rainbow border | 5 px `ImageLabel` frame using a pre-baked rainbow ring texture (cheaper than animating) |

`ui_builders.lua` wraps all of the above.

---

## 2. Design tokens

### Structure / neutrals
| Token | Hex | Use |
|---|---|---|
| outline | `#16170F` | every stroke and hard shadow |
| panelTop / panelBottom | `#414E36` → `#2B3423` | panel body gradient (180°) |
| subPanelTop / subPanelBottom | `#4A5840` → `#2E3825` | detail column, inner cards |
| rowTop / rowBottom | `#4E5C3B` → `#333E24` | list rows, day cards |
| tabTop / tabBottom | `#7A8A66` → `#4E5C3B` | inactive tabs / chips |
| trackTop / trackBottom | `#1B2114` → `#26301C` | inset progress tracks |
| scrim | `rgba(10,14,6,0.50)` | modal background dim |

### Action gradients (all 180°)
| Token | Stops |
|---|---|
| gold (header, primary) | `#FFE87A` 0% → `#FFC531` 55% → `#E08A0C` 100% |
| goldSmall (badges, pills) | `#FFE066` 0% → `#FFC531` 52% → `#E8930F` 100% |
| green (confirm/claim) | `#A6EE72` 0% → `#5FC22F` 52% → `#317F16` 100% |
| purple (feature/quests) | `#DE93FF` 0% → `#B04CEC` 52% → `#7C1CC0` 100% |
| red (danger/close) | `#FF8A7A` 0% → `#E23A2C` 52% → `#A8140F` 100% |
| blue (info) | `#6FD8FF` 0% → `#2A93E0` 52% → `#125FA8` 100% |
| freeCard | `#F7F7F1` 0% → `#DEDED4` 55% → `#B2B4A8` 100% |
| passCard | `#FFE066` 0% → `#F7B62C` 55% → `#D8860E` 100% |
| disabled | `#6A7757` → `#454F33`, label `#B8C4A4` |
| ownedCta | `#8FA378` → `#54643C` |

### Text
| Token | Hex |
|---|---|
| textOnDark | `#FFFFFF` (+ outline stroke) |
| textMuted | `#C9D6B4` |
| textAccent | `#FFD84D` |
| textOnLightCard | `#1E2317` with `#FFFFFF` stroke 3 |
| textOnGoldCard | `#3A2A05` with `#FFE9A8` stroke 3 |
| textOnGoldChrome | `#5A4A12` (no stroke — meta text on gold headers) |

### Rarity
common `#C9CCC2` · rare `#3FA9F5` · epic `#A855F7` · legendary `#FFB200` · mythic = rainbow ring.
Frame = 4 px inner stroke inset 0, radius 10, plus inner glow 12 px at 35–60% alpha of the same hue.

### Geometry
- **Stroke:** 5 px on panels/headers · 4 px on controls, cards, tabs · 3–3.5 px on chips and badges ≤ 44 px.
- **Radius:** panel & header 22 · control/card 16 · inner 14 · small 12 · art slot 9–10 · chip 8–11 · pill 999.
- **Hard shadow offset:** stroke + 1 (so 4 px stroke → `0 5px 0`; 5 px stroke → `0 6px 0`).
- **Gloss:** top strip 5–6 px at 45–70% white; bottom shade 6 px at 18% black.
- **Spacing scale:** 6 · 8 · 10 · 11 · 12 · 14 · 16 · 18 (panel padding 16–18, grid gap 11, row gap 10).

### Type scale
Display face: **Fredoka One** (Roblox: `Enum.Font.FredokaOne`). UI face: **Nunito 900** (Roblox: `Enum.Font.GothamBlack`, or upload Nunito for an exact match).

| Style | Face | Size | Text stroke | Use |
|---|---|---|---|---|
| Panel title | Fredoka One | 44 | 5 | "Season Pass", "Backpack" |
| Button L | Fredoka One | 30–34 | 4–4.5 | Quests, Buy Pass |
| Button M | Fredoka One | 22–26 | 3.5 | Claim, Equip, Skip |
| Value | Fredoka One | 24–28 | 3.5 | counters, tier numbers, currency |
| Card label | Fredoka One | 19–21 | 3 | reward names, row titles |
| Chip | Fredoka One | 14–15 | 2.5 | EQUIPPED, GRAND, NEW, ON/OFF |
| Meta | Nunito 900 | 13–15, +0.04em | none | "RESETS IN", stat keys, hints |

Never below 13 px; touch targets never below 44 px.

---

## 3. Screens

Common shell for all six panels: full-canvas scrim → centred column, `padding-right: 132` (reserves the nav rail) and `padding-left: 24`.
**Header bar:** height 92, radius 22, stroke 5, gold gradient, padding 0 12, gap 14 — section icon 62×62 (no plate, `drop-shadow(0 3px 2px rgba(0,0,0,.35))`) · title 44 · flexible spacer · optional action button · close button 74×66 (radius 16, red).
**Body:** `margin-top: 12`, radius 22, stroke 5, panel gradient, padding 16 (18 on Daily).

### 3.1 Season Pass — panel width 960 (+ 196 side column, gap 14)
Header: pass icon · title "Season Pass" · **Quests** button (height 66, padding 0 30, radius 16, purple) · close.

Progress row (height 56, gap 12):
- ticket icon 62×56, radius 12, goldSmall
- XP bar `flex:1`, height 56, radius 14, stroke 4, inset track; fill = gold gradient, width = `xp / xpNeed`; centred label `12 / 25` at 26/stroke 3.5
- level badge 58×56, radius 14, goldSmall, value 28
- **Skip N** button height 56, padding 0 18, green, label 26 + 26×26 gem chip

Track area (`margin-top: 14`, gap 10):
- Label column width 40 — "Free" block height 186 (`#7A8A66`→`#55643F`), "Season Pass" block height 252 (`#FFD84D`→`#E0912A`); text rotated bottom-to-top (`writing-mode: vertical-rl` + 180° ⇒ in Roblox a `TextLabel` with `Rotation = -90`), 22–24 px.
- One horizontal scroll region (native scrollbar hidden; a decorative 10 px track sits under it — thumb 190 px, `#9FAE8B` on `rgba(0,0,0,.45)`) containing three rows, gap 8, all items 178 wide:
  1. Free reward cards 178×186
  2. Tier number badges — 58×58, radius 14, goldSmall, value 28, centred in each 178 column
  3. Season Pass reward cards 178×186

**Reward card** (radius 16, stroke 4, padding 7/8/6): name label 20 centred at top · art slot fills the rest (radius 10) · quantity `x25` bottom-right 24/stroke 3.5 (**hidden in the claimable state** so the CLAIM pill has room).

Bottom CTA (`margin-top: -14`, i.e. overlapping the panel edge): height 74, padding 0 36, radius 18, stroke 5, gold; label 34/stroke 4.5 + 30×30 gem chip. Owned variant: `ownedCta` gradient, label "Pass Active ✓", non-interactive.

Side column (width 196, "Max Rewards" label 26): two tier-50 preview cards — 5 px rainbow ring, inner height 212, radius 15, stroke 4, panel gradient; art slot; tier badge 54×54 at top −12 / right −12; `x1` above the footer label ("Free" white / "Season Pass" `#FFD84D`).

### 3.2 Backpack — panel width 960, body height 566
Header adds "28 / 60 slots" (Fredoka One 22, `#5A4A12`) after the title.
Three columns, gap 14:
- **Tabs** width 152, rows height 60, radius 14, gap 9, `tabTop/tabBottom`, icon 34 + label 19; active = 4 px `#FFD84D` inner ring (inset 0, radius 10). "+ Slots" green button height 56 pinned to the bottom.
- **Grid** `flex:1`, 5 columns, row height 118, gap 11, scroll-y. Slot: radius 14, stroke 4, `#37432D`→`#232C1C`; art slot inset 6, radius 9; rarity frame overlay (see Rarity); quantity bottom-right 17; "EQUIPPED" ribbon height 24 at left −3 / top −9 (green, chip type). Unowned capacity = dashed `rgba(255,255,255,.13)` slots, no fill.
- **Detail** width 224, radius 16, stroke 4, `subPanel` gradient, padding 12, gap 10: hero art 150 tall (radius 12, stroke 4) · name 26 · rarity chip height 28 (colour per rarity, label COMMON/RARE/EPIC/LEGENDARY) · stat rows height 34, radius 10, `rgba(0,0,0,.3)`, key Nunito 14 `#C9D6B4` / value 18 · **Equip** green button height 56, label 24.

### 3.3 Settings — panel width 700
Body padding 16, gap 8. Section headers: Fredoka One 18, `#FFD84D`, stroke 3 ("AUDIO", "GRAPHICS", "GAMEPLAY").
- **Slider row** height 54, radius 14, `rowTop/rowBottom`, stroke 4: label column 150 at 21 · track `flex:1` height 26, radius 999, stroke 4, inset; fill green; knob 34×34 circle, stroke 4, `#FFF0A8`→`#FFC531`, hard shadow 0 3 · value column 56, right-aligned, 21. Click-to-set on the track; drag = same math on `InputChanged`.
- **Segmented quality**: three equal buttons height 54, radius 14, `tabTop/tabBottom`; active = 4 px `#FFD84D` ring inset −4 (radius 16) + 12 px glow.
- **Toggle row** height 52: label 21 left, switch 86×38 right. ON = green gradient, 36 px white knob at the right, "ON" chip label at left inset 11. OFF = `#5A6748`→`#3A452C` with inset shadow, `#C9CCC2`→`#9AA28E` knob at the left, "OFF" label right, colour `#C9D6B4`.
- Footer: **Redeem Code** (blue) and **Reset Data** (red), each `flex:1`, height 58, label 23.

### 3.4 Daily Rewards — panel width 900
Header adds a timer chip (height 58, radius 14, `#3B4731`→`#26301F`): "RESETS IN" Nunito 14 `#C9D6B4` + value 24.
Body padding 18. Streak row: "Login streak" 24 · "Day 4" chip height 44 goldSmall · right-aligned hint Nunito 15 `#C9D6B4`.
Row of cards, gap 12: days 1–6 `flex:1`, day 7 `flex:1.45`. Card height 196, radius 16, stroke 4, `rowTop/rowBottom`, padding 8, gap 6 — "Day N" 19 (nowrap) · art slot fills · reward label 14, `#FFD84D`, centred.
Day 7 is wrapped in the 5 px rainbow ring (radius 20) with a "GRAND" purple ribbon at top −10 / left −6.

### 3.5 Index — panel width 940
Body padding 16. Discovery bar height 48, radius 14, stroke 4, inset track, **blue** fill, centred label "19 / 50 discovered" at 22. Beside it a 100%-reward chip (height 48, radius 12, `#3B4731`→`#26301F`, Nunito 13 label + 30 px art slot).
Filter chips height 44, radius 12, gap 9, `tabTop/tabBottom`, label 18; active = `#FFD84D` ring inset −4.
Grid: 6 columns, gap 11, tile height 122 (radius 14, stroke 4, `subPanel`), art slot fills, name 14. Undiscovered = overlay `rgba(8,12,5,.72)` + "?" 40 px in `#7A8A66`. "NEW" red ribbon height 24 at top −8 / left −6. Viewport height 392, scroll-y.

### 3.6 Goals — panel width 860
Header uses the **purple** gradient (this is the quests surface) with icon slot on `#F0D2FF`→`#DDB2F6`, plus a refresh timer chip (`#5B1D8C`→`#3A0F5C`, label `#E7C8FF`).
Tabs: Daily / Weekly / Season — three equal buttons height 56, radius 14, active gold ring.
Quest rows height 88, radius 16, stroke 4, `rowTop/rowBottom`, gap 10, padding 0 12:
icon slot 60×60 (radius 12, stroke 4) · centre column (title 22 + progress bar height 24, radius 999, stroke 3.5, green fill, centred Nunito 14 label `2 / 3`) · reward chip height 52, radius 12 (30 px currency icon + value 20) · action button 136×60: **Claim** (green, label 24, idle bob animation) / **In progress** (disabled gradient, label 20 `#B8C4A4`) / **Claimed ✓** (`#4A5840`→`#2E3825`, label 20 `#9FAE8B`).

### 3.7 HUD
- **Currency cluster** top 18 / left 18, gap 12. Pill height 54, radius 999, stroke 4, padding 0 18 0 6 — 38 px circular icon slot (stroke 3) + value 24. Coin pill = goldSmall, gem pill = `#D98BFF`→`#A93FE6`→`#7A1CB8`. Hidden while a panel is open.
- **Nav rail** right 10, vertically centred, gap 6. No button plate — the icon floats on the world (matches the reference). Item column width 106: icon 66×66 with `drop-shadow(0 5px 4px rgba(0,0,0,.5))` · label directly under it, Fredoka One 20 / stroke 4 / white + `text-shadow 0 3px 0 rgba(0,0,0,.3)`. Order: **Bag · Pass · Daily · Goals · Index · Settings**. Active = 88 px radial gold glow behind the icon (`rgba(255,232,122,.75)` centre → transparent at 72%). Notification badge = red circle, min-width 34, height 34, stroke 4, hard shadow 0 3, at top −6 / right 12, value 19. Hover: `translateY(-3) scale(1.05)`; press: `translateY(+2) scale(.99)`.

---

## 4. Interactions, motion, feedback

| Event | Behaviour |
|---|---|
| Rail item hover | `translateY(-3)` + `scale(1.03)`, brightness 1.05, 120 ms ease-out |
| Button hover | `translateY(-2)`, brightness 1.06, 120 ms |
| Button press | `translateY(+2)`, hard shadow shrinks to `0 2px`, 80 ms |
| Panel open | scale 0.92 → 1 + fade in, 180 ms, `Enum.EasingStyle.Back` / `Out`; scrim fades 150 ms linear |
| Panel close | scale → 0.95 + fade out, 120 ms, `Quad` / `In` |
| Claimable pulse | ring glow spread 0 → 6 px, alpha 0.85 → 0, 1.6 s loop, ease-in-out |
| Claim button idle bob (Goals) | ±5 px Y, 1.4 s loop |
| Claim resolve | scrim fades in 120 ms → ✓ badge pops 220 ms `Back/Out` → reward icon flies to the matching currency pill 380 ms `Quint/Out`, then the counter tweens |
| Progress bar change | tween `Size` 400 ms `Quad/Out`; XP gain plays after the panel opens, not during |
| Tab / filter switch | instant content swap, ring moves with a 100 ms fade |
| Slider drag | live value update, no tween |
| Purchase | `MarketplaceService:PromptProductPurchase`; on success re-fetch pass state, then flip every eligible pass tier to CLAIMABLE with a 60 ms stagger |

Scroll: horizontal reward track and vertical grids use `ScrollingFrame` with `ScrollBarThickness = 10`, `ScrollBarImageColor3 = #9FAE8B`, `AutomaticCanvasSize` on the scrolling axis, `ElasticBehavior = Never`.

---

## 5. State

### Pass tier state machine (per tier, per track)
```
LOCKED     -- tier > player.level, OR track == "pass" and not player.passOwned
CLAIMABLE  -- tier <= player.level and not claimed[track][tier] and track unlocked
CLAIMED    -- claimed[track][tier] == true
```
Transitions: `level` increase → re-evaluate all tiers · `passOwned` true → every pass tier ≤ level becomes CLAIMABLE · successful claim → CLAIMED (server-confirmed only).
Visuals: LOCKED = lock badge 46×46 (radius 13) at top −8 / right −8 · CLAIMABLE = 5 px `#7CE04A` ring inset −4 (radius 19) + pulse + full-width CLAIM pill (height 38, radius 11, inset 8) · CLAIMED = `rgba(12,18,8,.58)` overlay + 62 px green ✓ circle (stroke 4).

### Daily
`day < streakDay` → CLAIMED (overlay .62 + 56 px ✓) · `day == streakDay and not claimedToday` → TODAY (green ring + CLAIM at bottom −16) · else LOCKED (overlay .42 + centred 44 px lock). Missing a day resets `streakDay` to 1.

### Quest
`progress < goal` → IN_PROGRESS · `progress >= goal and not claimed` → CLAIMABLE · `claimed` → CLAIMED. Daily set clears on the day rollover, weekly on the week rollover, season persists.

### Index entry
HIDDEN → (discovered) NEW → (panel opened & seen) FOUND. Completion % drives the blue bar; 100% grants the milestone reward once.

### Client state shape
```
screen: "none" | "pass" | "backpack" | "settings" | "daily" | "index" | "goals"
pass:      { level, xp, xpNeed, passOwned, claimedFree = {}, claimedPass = {} }
backpack:  { tab, selectedUid, items = {} }
settings:  { music, sfx, quality, toggles = {} }
daily:     { streakDay, claimedToday }
goals:     { tab, quests = {} }
index:     { filter, entries = {} }
```
All reward-bearing mutations are **server-authoritative**: the client sends intent, the server validates level/ownership/cooldown and replicates the new state. Never let the client decide a tier is claimable. See `data_schema.lua` for the table shapes and the remote contract.

---

## 6. Assets

### 6.1 Icon set — shipped, ready to use (`icons/`)
Eight original icons are included as clean SVG (128×128 export, `viewBox="-5 -5 74 74"`, no external refs, no fonts):

| File | Used for | Silhouette | Fill (top → bottom) |
|---|---|---|---|
| `bag.svg` | Backpack section | rounded body + flap + carry loop + gold buckle | `#FF7F5F`→`#C22B18`, flap `#E8543A`→`#A02010` |
| `pass.svg` | Season Pass section, XP row | ticket rotated −7° + 5-point star | ticket `#DE93FF`→`#7C1CC0`, star `#FFE066`→`#E8930F` |
| `daily.svg` | Daily Rewards section | calendar, red header, two rings, 6 cells (one gold = today) | body `#FAFAF4`→`#BFC1B5`, header `#FF6B5A`→`#C8231C` |
| `goals.svg` | Goals section | clipboard + purple clip + green check | board `#F7F7F1`→`#B4B6AC`, clip `#DE93FF`→`#8B2FD6`, check `#4FBE28` |
| `index.svg` | Index section | book: cover, cream pages, spine, red bookmark | cover `#6FD8FF`→`#125FA8`, spine `#3AA7E8`→`#0D4A85` |
| `settings.svg` | Settings section | 8-tooth gear + hub hole | `#FCFCF6`→`#9AA28E`, hole `#5A6350` |
| `coin.svg` | coin currency, quest rewards | outer disc + inner face + small star | `#FFE87A`→`#E8930F`, face `#FFF3C4`→`#F5C13A` |
| `gem.svg` | gem currency, prices | 4-point diamond + facet split + gloss wedge | `#E9B4FF`→`#7A1CB8` |

**Construction rule — use it for any new icon.** Build the silhouette from rects / circles / polygons only, then draw it **twice**: pass 1 filled *and* stroked `#16170F` at width 9 with round joins (this fuses the parts into one fat union outline), pass 2 the real gradient fills on top, with inner detail edges getting a 2.5–4 px `#16170F` stroke. Finish with one white gloss shape at 22–55% opacity in the top-left. That is the entire style, and it holds from 28 px to 128 px.

Rendered sizes in the UI: nav rail 66 · panel header 62 · pass XP row 58 · currency pill 40–42 · price / reward chip 30–34.

**In Roblox:** rasterise each SVG to a 256×256 transparent PNG, upload as an Image asset, and use `ImageLabel` with `ScaleType = Fit`. If you later want the fully-lit 3D look, treat these SVGs as the modelling brief — same silhouette, same palette, add a soft contact shadow — and swap the PNGs 1:1 without touching layout code. Keep the file names.

### 6.2 Still placeholders (studio art required)
Every remaining image position is an explicit labelled slot (diagonal stripes + monospace filename in the reference). Replace each with an `ImageLabel` (`ScaleType = Fit`).

| Slot label | Where | Rendered size |
|---|---|---|
| `gem_small/gem_large/crate_supply/crate_elite/tag_*/boost_coin2x/banner_01/skin_base_01/coin_stack` | reward cards | 162×120 |
| `tier50_free`, `tier50_pass` | Max Rewards previews | 180×150 |
| `item_01…15` | backpack slots | 106×106 |
| `selected_item` | backpack detail hero | 208×150 |
| `day1…7` | daily cards | ~110×90 |
| `idx_01…18` | index tiles | 130×80 |
| `quest ico` | goal rows | 60×60 |

Delete every monospace slot label in production — it exists only to mark intent.

## 7. Files in this bundle
| File | What it is |
|---|---|
| `game-ui-reference.html` | Standalone interactive reference — open in a browser. Nav rail switches panels; claims, tabs, toggles and sliders work. "STYLE KIT ↗" (bottom-left) opens the palette / button / state / rarity sheet. |
| `Game UI Kit.dc.html` | Source of the reference (same design, needs `support.js` beside it) |
| `tokens.lua` | Palette, gradients, geometry, type scale, tween presets as a Luau module |
| `ui_builders.lua` | Helper constructors: stroke, corner, gradient, gloss, hard shadow, panel, button, display text, inset track |
| `data_schema.lua` | Reward / tier / quest / daily / index / item table shapes, default season data, remote contract |
| `icons/*.svg` | The eight section / currency icons, production-ready vector |
| `states.md` | State machines and motion timings in checklist form |

Suggested implementation order: `tokens.lua` + `ui_builders.lua` → HUD shell (root scaling, rail, currency) → Season Pass (the most component-dense panel) → Goals → Daily → Backpack → Index → Settings.
