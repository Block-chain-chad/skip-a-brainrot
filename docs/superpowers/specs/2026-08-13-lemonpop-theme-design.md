# LemonPop Theme — Design Spec

**Date:** 2026-08-13
**Status:** Approved direction (owner/team already signed off on the palette); build to be verified in Studio and left UNSAVED.
**Source palette:** `C:\Users\m\Downloads\LemonPop-Theme.lua` (drop-in for the colour half of `ReplicatedStorage.Modules.UIKit.Tokens`).

## Goal

Replace the current Pet-Sim gray HUD palette (2026-08-04 style guide: gray window, red header, dark slots) with the LemonPop palette: warm lemon-cream windows, gold-tinted furniture, warm near-black outlines. Geometry, type, shadows, motion, icons, and fonts are all unchanged. The one-red-surface-per-panel rule (the header) carries over. Mutations keep their rainbow ring — never a recoloured frame.

## Approach (decided)

Rewrite the colour half of `Tokens.lua` **in place**, in the live Studio session — the same pattern the 2026-08-04 gray swap used:

- Token **names stay identical**, so every panel inherits the new look without a rewrite.
- Old hexes are **recorded inline** next to each replacement, so any single surface can be walked back with a one-line edit.
- Rejected alternative: installing LemonPop as a separate theme module and refactoring Tokens to reference it. Bigger diff, more to break, zero visual difference.

### Source of truth

Studio's live `Tokens.lua` is authoritative — the disk mirror has drifted before (738-byte drift caught 2026-08-08). Procedure:

1. Diff Studio's `Tokens.lua` against `game-src/place-full/ReplicatedStorage/Modules/UIKit/Tokens.lua` before editing; reconcile the mirror first if they differ.
2. Edit in Studio.
3. Re-sync the mirror byte-exact after.

The `ui-web/` React mirror does **not** auto-track Tokens; syncing it (via `/design-sync`) is a follow-up task, not part of this build.

## 1. Direct token adoptions from LemonPop

| Tokens.lua key(s) | New value (top → bottom) | Replaces |
|---|---|---|
| `outline` | `#241F14` | `#202020` |
| `innerKeyline` | `#FFFFFF` (unchanged) | — |
| `panelTop/Bottom`, `gradient.panel`, `gradient.window`, `gradient.cream` (legacy alias) | `#FFFBE2 → #FFD977` | gray `#D6D6D6 → #A9A9A9` |
| `subPanelTop/Bottom`, `gradient.subPanel` | `#FFF6CF → #F7C95C` | `#C4C4C4 → #9C9C9C` |
| `headerTop/Bottom`, `gradient.header` | `#FF6B5C → #D8342C` | `#F96B57 → #C84535` |
| `slotTop/Bottom`, `gradient.slot` | `#FFFFFF → #FFF4D9` (light — art wells so pet renders read) | dark `#4A4A4A → #363636` |
| `rowTop/Bottom`, `gradient.row` | `#4A4030 → #302A1F` (stays dark, warm-tinted) | `#4A4A4A → #363636` |
| `trackTop/Bottom`, `gradient.track` | `#302A1F → #3D3527` | `#2E2E2E → #3A3A3A` |
| `tabTop/Bottom`, `gradient.tab` | `#C2A878 → #8A7350` | `#BEBEBE → #9C9C9C` |
| `gradient.gold` | `#FFF08A → #FFC531 → #E08A0C` (top stop changes) | `#FFE87A → …` |
| `gradient.goldSmall` | `#FFE066 → #FFC531 → #E8930F` (identical to current) | — |
| `gradient.green/red/blue/purple` | LemonPop values (identical to current) | — |
| `gradient.disabled` | `#8A7C5E → #5C5138` (warm taupe) | olive `#6A7757 → #454F33` |
| `rarityCommon/Rare/Epic/Legend` | LemonPop values (identical to current; SECRET keeps borrowing epic) | — |
| `claimRing`, `activeRing`, `activeGlow` | identical to current — no change | — |
| `scrim` / `scrimAlpha` | `#0A0E06` / 0.50 — no change | — |

**Note on `slot`:** this is the one *structural* colour flip — slots/art wells go from dark gray to near-white so pet/brainrot renders read on them. Any slot that renders white/pale art (e.g. discovery-cover silhouettes) must be checked for contrast in the audit.

## 2. Text tokens — the on-light / on-dark split (full fidelity)

LemonPop's rule: **dark unstroked ink on light surfaces; white stroked display type on dark surfaces.** Today several text tokens are used on both surface kinds, so a pure colour swap would strand unreadable text. Changes:

| Token | New value | Usage rule |
|---|---|---|
| `textOnWindow` / `textOnLight` | `#33261A` | On panel/subPanel/slot/freeCard. **No text stroke.** |
| `textMuted` | `#7A6A52` | Light surfaces only (captions, codes, "RAREST"). |
| `textMutedOnDark` (**new**) | `#E8DCBE` | Muted text on row/track/dark pills. |
| `textAccent` | `#C2410C` | Values/highlighted names on light surfaces. |
| `textAccentOnDark` (**new**) | `#FFD84D` (the current yellow) | Values on currency pills, rows, dark strips. |
| `white` (textOnDark) | `#FFFFFF`, stroked | Unchanged on dark surfaces. |

**Implementation obligation:** grep every consumer of `textMuted`, `textAccent`, `textOnLight`, `textOnWindow`, and stroke-setting code in `UIKit` Builders + panel scripts; classify each usage by the surface it sits on; assign the correct variant and stroke behavior. This touches Builders/panel code, not just Tokens.

## 3. Derived extras (not in the LemonPop file — approved in design review)

Warm-lemon derivations replacing olive/gray-era values; everything already warm gold or currency-purple stays put.

| Token | Current | New |
|---|---|---|
| `gradient.freeCard` | gray-whites `#F7F7F1 → #DEDED4 → #B2B4A8` | `#FFFDEE → #F5E7C0 → #D9BC82` |
| `gradient.lockBadge` | `#F2F2EC → #C2C4B8` | `#FFF6DC → #D8C494` |
| `gradient.ownedCta` | olive `#8FA378 → #54643C` | `#A98F5C → #6E5A34` |
| `gradient.freeLabel` | olive `#7A8A66 → #55643F` | `#B89B5E → #7C6438` |
| `scrollThumb` | sage `#9FAE8B` | `#C2A878` (tab tan) |
| `textDisabled` | `#B8C4A4` | `#A79A7C` |
| `textClaimed` | `#9FAE8B` | `#9C8F6E` |
| `gradient.gem`, `gradient.passCard`, `gradient.passLabel`, `gradient.knob`, `textOnGoldCard`, `textOnGoldChrome` | already warm gold / currency purple | **unchanged** |

## 4. Audit sweep

After the token swap, open **every** panel live in a Play test — `openPanel`'s pcall silently hides broken panels, so each must actually be opened and eyeballed:

Bag (new plot-rack inventory), Goals, Pass, Daily, Index, Eggs + discovery covers, Pets, Keys, Tags, Settings, Charm Codex, Wheel, Rebirth, hotbar, HUD chrome (currency pills, quest bar, nav rail + IconArt), toasts.

Hunting for, per panel:
- Hardcoded gray-era hexes that bypass Tokens (fix by pointing at tokens, not new literals).
- Text with the wrong variant or wrong stroke for its surface (per §2).
- Contrast problems from the slot light-flip (§1 note) — especially silhouette/discovery art.

## 5. Verification

- Play-verify in Studio with the window **foregrounded** (backgrounded Studio gives render-throttled/wrong-app captures).
- Screenshot at each visual milestone, not end-of-turn; share progress as it happens.
- If a posed capture is taken, restore `CameraType` (never leave Scriptable).
- Readability check on every panel: muted text on light, values on dark pills, disabled states.

## 6. Out of scope

- `UITheme.lua` world/cafe surfaces: Bazaar shop, merchant panel, campfire style pack, Skipper's Cove boards, plot signs, camp board.
- Fonts (`T.font`) — the UIPolish lockstep constant stays untouched; changing one without the other is a silent no-op.
- Geometry, radii, strokes-widths, shadows, padding, sizes, motion (`T.tween`), zindex, icon asset ids.
- `ui-web/` React mirror sync (follow-up task).
- Rarity *semantics* (8 gameplay tiers still map onto the 4 rarity colours as they do today).

## 7. Risks & rollback

- **Rollback:** every replaced hex is recorded inline in Tokens.lua; single surfaces walk back with one edit, the whole theme walks back by restoring the recorded values.
- **Unsaved cohabitation:** Studio currently holds other UNSAVED work (inventory rework, mutation fixes, Massive StorePrompt fix). This build adds to it and **nothing is saved by this task** — saving is the owner's/user's call.
- **Datastore:** Studio Play tests write the real datastore; audit passes avoid destructive actions (no claiming/spending beyond what's needed to view panels).
- **Team Create:** collaborators have previously reverted/deleted work mid-session; user coordinates saves with the team.
- `execute_luau` runs in a server sandbox — it does not reflect client module state; verify visuals via captures, not just Luau probes.
