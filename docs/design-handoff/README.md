# Handoff: Skip Rock Brainrots — Roblox Game UI

## Overview
Full-screen HUD + shop/inventory/upgrade/rebirth/gamepass/daily/hatch UI for a "skip rocks to collect brainrots" idle-clicker Roblox game. Core loop: hold-charge a skip meter, release in the green zone for a perfect skip, earn cash, buy/hatch brainrot characters, upgrade multipliers, rebirth to reset-and-boost, unlock worlds via quests.

## About the Design Files
The three `.dc.html` files in this bundle are **design references built in HTML/CSS/JS** (React-like component syntax) — they are prototypes demonstrating layout, visual style, copy, and interaction/animation timing. They are **not Roblox code** and are not meant to be shipped as-is. The task is to **recreate these designs in Roblox Studio** using Lua/Luau, `ScreenGui`/`Frame`/`TextButton` instances, `UIStroke`, `UIGradient`, `UICorner`, and `TweenService` for animation — following the visual system documented below.

## Fidelity
**High-fidelity.** Exact colors, fonts, spacing, corner radii, shadows, and animation timings are specified below and in the files — recreate pixel-for-pixel where Roblox's UI system allows equivalents (e.g. `UIStroke` for the black outline instead of CSS `-webkit-text-stroke`).

## Versions in this bundle
- **v1** — original dark/navy treatment, left icon rail, no hatch loop.
- **v2** — "juicier" iteration: bottom icon dock, top-earners strip, egg/hatch loop, coin-fly-to-counter effect. Still dark/navy.
- **v3 (recommended/final)** — same layout and mechanics as v2, re-skinned bright/candy (sky-blue background, white comic-outline panels) to read closer to genre peers like Pet Simulator / Fisch. **Build from v3.**

## Screens / Views (v3)

### 1. Main HUD (always visible, layered over the 3D game viewport)
- **Top-left stack**: Cash counter pill (white rounded rect, 6px black outline `#10131f`, `border-radius:22px`, drop shadow `0 9px 0 #0a0d16`), gold "$" icon chip (`linear-gradient(160deg,#ffe680,#e08c00)`), value in **Luckiest Guy** 32px with 5px black text-stroke. Below: Gems pill (teal `#7dffd6`→`#0f9e88` chip, ◆ glyph) and Rebirths pill (pink `#ff8ac2`→`#a3247a` chip, "R" glyph) side by side. Below that: a small dark translucent chip showing `×N EARNINGS / N/SEC`.
- **Top-center**: World/quest card, 440px wide (shrinks via `min(440px, 34vw)` on narrow screens). Header bar purple gradient (`#3a2a6b`→`#1d1740`) with world name + "NEXT: LAVA LAKE". Body lists 3 quests, each a label + count (JetBrains Mono, 11px) + a 13px-tall pill progress bar (green gradient `#a3ff4f`→`#3ecf5b` fill on dark track).
- **Top-right**: "FREE DAILY READY!" pill button — orange gradient (`#ffb055`→`#d2600b`), 6px black outline, `animation: bob 2.4s ease-in-out infinite` (bounces ±9px vertically, sine ease). Below it, a "TOP EARNERS" card showing your 3 highest-cps equipped brainrots as small thumbnail tiles.
- **Bottom-center**: Charge/skip control — a 36px pill meter with a repeating tick pattern, a green "perfect zone" band at 70–92%, filled with a 3-stop gradient (`#a3ff4f`→`#ffd93b`→`#ff8ac2`) tracking charge %. Below it, the big "HOLD TO SKIP ROCK" button (34px Luckiest Guy, green gradient `#b6ff6a`→`#3d9e18`, 7px outline, pulsing glow `pulseGlow` keyframe, press = translateY(8px) + shadow collapse).
- **Bottom-left**: Live activity feed — 3–4 rows of dark/light pill chips with a colored left border, most recent on top.
- **Bottom dock (bottom-center, full width)**: 7 square icon buttons (100×100px, `border-radius:24px`, 6px outline) for SHOP / HATCH / BAG / UPGRADE / REBIRTH / PASSES / DAILY, each a single-letter glyph + label, with an optional red badge counter top-right. Hover = lift + scale (`translateY(-9px) scale(1.07)`), press = drop.

### 2. Shop panel (modal)
1080px card, green header (`#1d8a3a`→`#0f5c26`), 4-column grid of brainrot cards. Each card: 132px art placeholder (rarity badge top-left, drop-odds badge top-right), name (Luckiest Guy 18px), cps value, one-line flavor text, full-width buy button showing price, greyed out if unaffordable.

### 3. Inventory ("MY BRAINROTS") panel (modal)
1080px card, blue header. 6-column grid of owned + undiscovered brainrots (undiscovered = "???" name, "UNDISCOVERED" label, dimmed/greyscale art, "LOCKED" badge). Click a card to equip it (badge shows "ON" when equipped, "×N" for owned count otherwise).

### 4. Upgrades panel (modal)
800px card, purple header. Vertical list of 4 upgrade rows (Throw Power, Rot Luck, Wrist Flick, Pond Greed), each: icon chip, name + level/25 + effect text, progress bar, buy button with scaling cost (`base × 1.6^level`), "MAXED" state at level 25.

### 5. Rebirth panel (modal)
660px card, dark pink/magenta theme. Two stat cards side-by-side (current × multiplier vs. after-rebirth × multiplier), explanatory copy, progress bar toward rebirth cost, big CTA button (disabled/grey state shows "NEED $X" when short).

### 6. Gamepasses panel (modal)
980px card, gold header, countdown "SALE ENDS IN…". 4-column grid of pass cards (2× Cash, Auto Skipper, Ultra Luck, +50 Bag Slots) each with a colored tag (HOT/BEST/NEW/SALE), description, R$ price button.

### 7. Daily rewards panel (modal)
900px card, orange header, streak counter. 7-column grid of day cards: claimed (dimmed, "CLAIMED"), next-up (green highlight, "TAP TO CLAIM", clickable), locked (dark, "LOCKED"). Footer warning about streak reset.

### 8. Hatch (egg) panel (modal) — the core gacha loop
1000px card, purple header "HATCH EGGS". Left column: 3 selectable egg tiers (Pebble/Pond/Void) each showing price + odds text, selected egg gets a green ring outline. Right stage area (dark inset panel):
- **Idle state**: egg art bobbing (`bobSlow` keyframe, ±14px + slight rotation, 3.2s loop), egg name below.
- **Spinning state** (triggered on hatch button press, 1.5s): egg shakes violently (`eggShake` keyframe — rapid rotation + small vertical kick), "CRACKING…" text in green, full-bleed white radial flash pulsing (`flash` keyframe, 0.9s loop) for gacha-reveal tension.
- **Done state**: "YOU GOT" header + up to 8 result cards animating in one-by-one (`cardPop` keyframe — scale/rotate entrance, staggered via `animation-delay` in ~110ms increments), each card showing art placeholder, name, rarity label in that rarity's color.
- Bottom row: 3 hatch buttons (HATCH 1 / HATCH 3 / HATCH 8) each showing total cost, disabled behavior (toast "NOT ENOUGH CASH") if unaffordable.

## Interactions & Behavior
- **Charge-and-release skip**: press-and-hold (mouse or Space bar) fills a 0–100 meter that auto-oscillates up/down (`+4` per 24ms tick, direction flips at 0/100). On release: reward scales with charge amount and upgrade levels; releasing while charge is 70–92% is a "PERFECT" (2.5× multiplier + a bigger floating-text celebration + more flying coins).
- **Floating combo text**: on skip release, a large outlined number (`+$1,234` or `PERFECT! +$…`) floats up and fades over ~1.5s (`floatUp` keyframe) from the skip point; a expanding-ring ripple (`ripple` keyframe) plays under it; N small coin sprites fly from the skip point to the top-left cash counter along a curved path (`coinFly` keyframe, staggered ~55ms apart) ending near the cash pill's icon position.
- **Toasts**: transient cards slide in from the right (`toastIn` keyframe) whenever cash is spent/gained meaningfully, an item is purchased, a brainrot is found/hatched, an upgrade completes, or rebirth completes. Auto-dismiss after ~2.8s.
- **Modals**: any dock button opens its panel with a `popIn` scale-bounce entrance; a full-screen scrim (blurred dark overlay) sits behind all modals and closing the modal is click-to-dismiss on the scrim or the "X" button.
- **Idle income**: cash accrues automatically every 1 second based on total owned brainrots' combined cps × rebirth multiplier × greed-upgrade bonus — this should tick continuously even while a panel/modal is open.
- **Responsive HUD width guard**: the top-center quest card, top-right stack, bottom feed, and skip control all use `min(px, vw%)` widths so they compress rather than overlap each other on narrower viewports. Preserve this behavior — do not use fixed pixel widths for these clusters.

## State Management
- `cash`, `gems`, `rebirths` (numbers)
- `owned` — map of brainrot id → count owned
- `equippedId` — currently equipped brainrot id (drives Top Earners + equipped display)
- `levels` — map of upgrade id → level (0–25), resets to 0 on rebirth
- `panel` — which modal is open (`null | 'shop' | 'inv' | 'upg' | 'reb' | 'pass' | 'daily' | 'hatch'`)
- `charge`, `charging`, `dir` — skip-meter state
- `skips`, `perfects` — lifetime counters, drive quest progress
- `dayClaimed` — daily-streak day number claimed so far
- `eggId`, `hatchPhase` (`idle|spin|done`), `results` — hatch-flow state
- transient arrays: `toasts`, `floaters`, `ripples`, `coins`, `feed` — each entry auto-removes itself after its animation duration via a timer

## Design Tokens

**Colors**
- Outline / ink: `#10131f` (used on every element as a 4–7px border)
- Sky background: `radial-gradient(125% 95% at 50% 6%, #bff0ff 0%, #6ecdf7 42%, #2b93d4 100%)`
- Panel shell: `linear-gradient(180deg,#ffffff,#cfe0f5)` (white → pale blue)
- Cash gold: `#ffd93b` / chip gradient `#ffe680`→`#e08c00`
- Gems teal: `#7dffd6` / chip `#7dffd6`→`#0f9e88`
- Rebirth pink: `#ff8ac2` / chip `#ff8ac2`→`#a3247a`
- Positive green (buttons/progress): `#a3ff4f`→`#3d9e18` / `#3ecf5b`, `#4be072`
- Danger/close red: `#ff5c7a`→`#a3123a`
- Purple (upgrades/hatch): `#c07bff`→`#6b26c4`
- Rarity colors: Common `#6b7c96`, Rare `#4da3ff`, Epic `#c07bff`, Legendary `#d18f00`, Mythic `#ff5c7a`, Secret `#0fae94`

**Typography**
- Display/headers/buttons: **Luckiest Guy** (Google Font), with a thick outline effect done via `-webkit-text-stroke: 3–7px #10131f; paint-order: stroke fill;` — in Roblox, recreate with `UIStroke` (Thickness 2–3, Color black) on a bold rounded font (e.g. Roblox's "Fredoka One" or "Gotham Black" as nearest equivalent) since custom web fonts aren't available client-side.
- Body/labels: **Nunito**, weight 700–900
- Numeric/mono readouts (quest counts, timers): **JetBrains Mono**, weight 700

**Shape & shadow**
- Corner radius: 14–32px depending on element size (small chips ~14–18px, cards ~20–24px, modals ~28–32px)
- "Chunky" drop shadow convention used everywhere instead of blur-shadows: a solid offset shadow matching the outline color, e.g. `box-shadow: 0 6–16px 0 #0a0d16` (hard, no blur) — this is what gives the toylike/3D-button feel; press states animate `translateY` down while shrinking this offset to near-zero.

**Animation timings**
- `bob` (daily button bounce): 2.4s ease-in-out infinite, ±9px
- `bobSlow` (egg/equipped idle): 3.2–3.4s ease-in-out infinite, ±12–14px + slight rotate
- `pulseGlow` (skip button idle glow): 2.6s ease-in-out infinite
- `popIn` (modal open): 0.28s cubic-bezier(.34,1.56,.64,1)
- `cardPop` (hatch result reveal): 0.4s cubic-bezier(.34,1.56,.64,1), staggered ~110ms per card
- `eggShake` (hatching): 0.45s ease-in-out infinite during the ~1.5s hatch delay
- `floatUp` (combo text): 1.5s ease-out
- `coinFly`: 0.78s cubic-bezier per coin, staggered ~55ms
- `toastIn`: 0.35s cubic-bezier(.34,1.56,.64,1)

## Assets
No real art is included — every character/egg/pass render is a placeholder colored block with monospace "IMG"/"CHARACTER RENDER" text. Replace these with actual 3D character renders/icons before shipping; keep the placeholder's rounded-rect frame, rarity-colored border/background, and badge overlay positions as the layout contract.

## Files
- `Skip Rock Brainrots v3.dc.html` — **build from this one.** Final bright/candy visual treatment.
- `Skip Rock Brainrots v2.dc.html` — same mechanics, dark/navy skin (reference only, superseded by v3's palette).
- `Skip Rock Brainrots v1.dc.html` — earlier iteration without the hatch loop, top-earners strip, or bottom dock (reference only).
