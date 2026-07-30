# States & motion checklist

Build order per component: **idle → hover → press → the panel's own states**. Nothing in this UI has a hidden state; if a card can be in it, it is drawn in `game-ui-reference.html` (Season Pass free track shows all three tier states; open **STYLE KIT ↗** for them side by side).

## Reward card (Season Pass)

| State | Rule | Visual |
|---|---|---|
| LOCKED | `tier > level`, or pass track without ownership | lock badge 46×46, radius 13, at top −8 / right −8 (light gradient, 4 px outline, hard shadow 0 4) |
| CLAIMABLE | `tier <= level` and not claimed and track unlocked | 5 px `#7CE04A` ring, inset −4, radius 19, pulsing 1.6 s; full-width CLAIM pill (inset 8, height 38, radius 11, green); quantity label hidden |
| CLAIMED | `claimed[track][tier]` | `rgba(12,18,8,.58)` overlay + 62 px green ✓ circle (4 px outline, hard shadow 0 4) |

Claim sequence: press → server round-trip → overlay fades 120 ms → ✓ pops 220 ms Back/Out → reward icon flies to the currency pill 380 ms Quint/Out → counter tweens. On failure: shake the card ±6 px, 3 cycles, 240 ms, and show the reason.

Buying the pass: every pass tier ≤ level flips LOCKED → CLAIMABLE with a 60 ms stagger left-to-right; the CTA swaps to the "Pass Active ✓" variant in the same frame.

## Daily card

| State | Rule | Visual |
|---|---|---|
| CLAIMED | `day < streakDay`, or today and already claimed | overlay `rgba(8,12,5,.62)` + 56 px ✓ |
| TODAY | `day == streakDay` and not claimed | green ring + CLAIM button (height 44) hanging 16 px below the card |
| LOCKED | future day | overlay `rgba(8,12,5,.42)` + centred 44 px lock badge |

Day 7 always carries the rainbow ring and GRAND ribbon regardless of state.

## Quest row

| State | Rule | Action button (136×60) |
|---|---|---|
| IN_PROGRESS | `progress < goal` | "In progress", disabled gradient, no shadow, label `#B8C4A4` |
| CLAIMABLE | `progress >= goal` | "Claim", green, idle bob ±5 px / 1.4 s |
| CLAIMED | claimed | "Claimed ✓", `#4A5840`→`#2E3825`, label `#9FAE8B` |

Progress bar fills to `progress / goal`, tween 400 ms Quad/Out when the value changes while the panel is open.

## Index tile
HIDDEN (`rgba(8,12,5,.72)` overlay + "?" 40 px `#7A8A66`) → NEW (art visible + red NEW ribbon) → FOUND (art + name). Clearing NEW happens when the panel closes, not on hover. Completion bar is blue; hitting 100% fires the milestone reward once.

## Backpack slot
OWNED (rarity frame + quantity) · EQUIPPED (adds the green ribbon at top-left; only one per category) · EMPTY CAPACITY (dashed `rgba(255,255,255,.13)` outline, no fill, not clickable). Selecting a slot updates the detail column instantly — no transition.

## Settings
Sliders write on drag, persist on release. Quality is a 3-way segmented control (gold ring marks the active option). Toggles animate the 36 px knob across the 86 px pill in 120 ms Quad/Out and swap the ON/OFF label at the midpoint. "Reset Data" must open a confirm dialog (not designed here — reuse the panel shell at 480 px wide with a red primary).

## Panels & rail
Open: scale 0.92 → 1 + fade, 180 ms Back/Out; scrim fades 150 ms. Close: scale → 0.95 + fade, 120 ms Quad/In.
Only one panel is open at a time; the rail stays interactive above the scrim and switches panels directly (no close-then-open). The active rail item wears a 4 px white ring (inset −6, radius 22) plus a 14 px white glow. Notification badges show unclaimed counts and clear when the panel's claimables are gone.
The top-left currency cluster hides while a panel is open.

## Accessibility / feel notes
- Every interactive target is ≥ 44 px; the smallest is the 38 px CLAIM pill inside a card, which sits inside a 178 px card that is itself clickable — make the whole card the button.
- Text is never below 13 px, and all display text carries the outline stroke, so it survives on bright world backgrounds.
- Gamepad: rail is a vertical focus loop; inside a panel, focus enters the first claimable element.
