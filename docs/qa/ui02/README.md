# UI-02 — pre-sync mobile / responsive QA pass (2026-09-19)

Lane UI-02 (Pete), branch `ui-02-polish` off Balkan's finished Bag checkpoint `86c6cf5`.
Narrow QA + polish pass over the non-Bag interfaces. **The Bag is not touched** — `BackpackPanel`,
`ViewportCuller` and `BrainrotCard` are byte-identical to `86c6cf5` (hash-checked live at the end of
the session), as are Round 3's quest surfaces.

Measured in Studio Play on the owner's profile (place `78783087742939`), Studio focused, game viewport
**1530×576**, plus every entry of `Platform.TEST_SIZES` through `Platform.SetViewportOverride`.
Tooling: the repo's own `ReplicatedStorage.Modules.HudAudit` (`RunPanels`, `RunModals`) plus a
session-only probe (text fit, touch targets, sibling overlap, scrolling, safe-area) that lived in the
Play client and is gone with the session.

**What an override can and cannot say:** a device override recomputes every size that reads
`Platform.Viewport`, so sizes, fits and touch targets are honest. It does **not** move the real Studio
window, so absolute positions under an override are the desktop window's — position claims below come
either from the real viewport or from arithmetic on the layout rule.

## Result

| Surface | Desktop | Phone profiles | Verdict |
|---|---|---|---|
| Season Pass (Progress → SEASON PASS tab) | 609×427, 403 labels, 0 clipped, 0 overlaps, ladder scrolls (canvas 2418 / window 193) | fits, 0 clipped | pass |
| Goals (Progress → GOALS tab) | 609×427, 20 labels, 0 clipped, rows scroll | 473×332, fits, 0 clipped | pass |
| Luck flyout | **was broken — fixed** (below) | **was broken — fixed** | fixed |
| Rock Shop (merchant) | 698×520, 45 labels, 0 clipped, card grid scrolls (1044 / 390), close 41×41 | `RunModals` clean | pass |
| Sell panel | 607×427, 4 scroll regions, **5 clipped labels** (known issue below) | same 5 | known issue |
| Egg Shop | 698×520, 82 labels, close 32×32 | `RunModals` clean | pass |
| `HudAudit.RunPanels` | 0 problems across Phone short / Phone tall / Phone portrait / Laptop 768p+720p / Desktop | | pass |
| `HudAudit.RunModals` | 1 problem, `MichelOfferUI` (not this lane — see below) | | reported |

Console across the session: no errors, and the only warning is the pre-existing
`[UIKit] panel module PetAbilityHelp did not return { Id, Build }`.

## Fixed — the Luck flyout ran off the top of the screen

`LuckHUDClient` is anchored bottom-right and lifted 118px clear of its chip, but its height budget was
`min(560, max(240, vp.Y - 60))` — which counted neither that lift nor the topbar. Measured at
1530×576 before the fix: panel top **−76**, i.e. the whole title row (title, ×N headline **and the
close button**) rendered above the screen, so the flyout could not be dismissed by its own X
(`luck-before-desktop-1530x576.png`). By the same arithmetic it lost that row on a 1280×720 laptop and
on every phone profile.

Two things were wrong, and both are fixed in `LuckHUDClient.client.lua`:

1. **The budget.** Height and lift are now taken from what the screen actually has
   (`vp.Y - Insets().Top`), the lift giving way first on a short screen, and the X offset is clamped so
   a narrow portrait screen cannot push the card off the left edge either. The list inside scrolls, so
   a shorter card shows fewer rows rather than losing any.
2. **The scale.** `PlatformClient.fitPanels` *grows* a panel that carries no `UIScale` of its own on
   touch screens (measured ×1.16–×1.35 here), which silently multiplied the pixel budget. The flyout
   now declares its own `UIScale`, which puts it in that pass's rescue-only branch.
3. **The first fit of a session.** `GetGuiInset()` answers 0 until the topbar initialises, so the
   startup fit was computed against a 58px-taller screen (card 446 instead of 388, title row off-screen
   again until something else moved). The fit now also re-runs on `GuiService.TopbarInset`.

After: top **+12**, close button on screen, list scrolling, **all 15 device profiles on screen**
(`luck-after-desktop-1530x576.png`). Desktop 1920×1080 is unchanged (560 tall, lift 118, top 344).

## Known issue, not fixed — Sell panel mutation pill

The mutation/size pill ("GOLDEN HUGE", "DIAMOND HUGE") clips: `PanelChrome.shout(scaled = true)` sets
`TextScaled`, which forces `TextWrapped`, so a two-word label wraps to two lines inside a pill one line
tall and the second line is cut. 5 tiles in the live bag, desktop and phone alike.

Three fixes were tried and **all reverted** — the file is byte-identical to `86c6cf5`:

- unwrapping alone turns `TextScaled` off with it (the engine ties them), and the line then overflows;
- sizing the text from `TextService:GetTextSize` fails because it under-reports this font by ~30%
  (LuckiestGuy at 14 measures 96px, renders 124), so labels truncated instead;
- letting the pill hug its text (AutomaticSize + cap) pushed 60 of 110 pills past their cap on a phone.

It needs a decision that is the owner's, not a polish-pass call: a taller two-line pill (eats 8px of
the art well), a shorter label (drop the size word, which is the only place the tile shows it), or a
wider tile. Recorded here rather than guessed at.

## Also found, other lanes

- `MichelOfferUI.OfferPanel` is 120% of usable height on the 700×310 reference handset
  (`HudAudit.RunModals`). Quest/NPC surface — reported, not touched.
- Touch targets under 44px on every audited surface at phone sizes: Progress close 34×34 and its tabs
  29–33 tall; Luck close 40×40; Egg Shop close 32×32; Rock Shop close 41×41; Sell chips 15–19 tall.
  This is the same panel-density decision already recorded for the Bag on 2026-08-25 (a panel authored
  at 1080×720 and scaled to ~0.4 cannot reach 44px by inflating individual controls). Worth its own
  pass with the owner; deliberately not attempted here.
