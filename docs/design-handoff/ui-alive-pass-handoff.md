# UI "Alive" Pass — 5 micro-animations (handoff)

An animation audit (done in a separate session, from the committed script backup) found that the UI's
*transitional* motion is solid — panels, toasts, hover/press all tween — but its *ambient/attention*
motion is missing. Five gated changes below fix that. Nothing else should be animated; several
candidates were deliberately rejected (currency-pill idle breathing, quest-tracker motion, extra
per-gain flourish) because they'd read as noise.

**Ground rules**
- Edit the LIVE scripts in Studio. Line numbers below come from the backup and are approximate —
  anchor by function name, not line.
- Reuse the existing tween vocabulary: `ReplicatedStorage.Modules.UIKit.Tokens` (`T.tween.pop`,
  `T.tween.fly`, `T.tween.pulsePeriod`) where the script already imports it; otherwise raw
  `TweenInfo.new` with the same values. Do NOT invent new timing constants.
- Every infinite (repeat -1) tween MUST be cancelled when its element hides — no leaked loops.
- Known gotcha: Studio MCP multi-edits can fail silently. After each edit, read the script back and
  confirm the change landed before moving on.
- Verify each item in Play mode, then SAVE (publish/commit to cloud) — unsaved work has been lost
  before on this project.

---

## 1. Breathing claim glow (HIGHEST impact — do this one first)

**File:** `ReplicatedStorage.Modules.SideRail` — `handle.setReady` (~line 337), `readyGlow` built ~line 218.

**Today:** `setReady(on)` just flips `readyGlow.Visible`. The gold halo then sits frozen. All four
claimables (Daily, Quests, Rebirth, Season) route through this one function.

**Change:**
- On `setReady(true)` (only if not already on):
  - Pop the glow in: parent a `UIScale` to `readyGlow` (create once), set `Scale = 0`, tween to 1
    with `TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)` — same values the
    badge appear already uses in this file.
  - Start the breathe loop: tween `readyGlow.BackgroundTransparency` from its resting 0.35 to 0.62,
    mirroring `UIKit.Builders.claimRing`'s loop exactly: `TweenInfo.new(T.tween.pulsePeriod / 2,
    Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)`. SideRail doesn't import Tokens —
    read `pulsePeriod` from `UIKit.Tokens` or copy its literal value; do not guess a new period.
- On `setReady(false)`: `Cancel()` both tweens, reset `BackgroundTransparency = 0.35`, hide.
- Keep a per-tile reference to the running loop tween so repeated `setReady(true)` calls don't stack.

**Verify:** in Play mode with a claimable daily reward, the Daily tile's halo visibly breathes
(~1–2s cycle). Claim it → halo stops and disappears cleanly. Toggle repeatedly → no double-speed
pulsing (stacked tweens).

## 2. Money / gem count-up ticker

**File:** `StarterPlayer.StarterPlayerScripts.GameHUDClient` — `applyCash` (~line 434) and
`applyDarrels` (~line 444).

**Today:** `coinValueLabel.Text = shortNumber(n)` — digits teleport. The pill pop (`playPop`) is good; keep it.

**Change:** one shared ticker helper used by both currencies:
- On **increase**: animate the displayed number from the currently-displayed value to the new value
  over 0.35s with Quint/Out easing. Cleanest Roblox pattern: a `NumberValue`, tween its `Value` with
  `TweenService`, and on its `Changed` update `label.Text = shortNumber(math.floor(v))` and call
  `sizePillToValue(pill, label)` (the pill has no AutomaticSize — see the "Bug A" comment; the width
  must track digit-count changes during the count).
- On **decrease** (spending): snap instantly, no animation. Spending should feel immediate;
  counting down reads as slow loss.
- **Retarget:** if a new value arrives mid-count, cancel the running tween and start from the
  currently-displayed value, never from the stale target.
- Keep `playPop` firing exactly as it does now (on increase, after load).

**Verify:** collect campfire money → number rolls up over ~a third of a second and the pill width
tracks it. Buy something → number snaps down instantly. Two rapid gains → no flicker or jump-back.

## 3. Coin fly on campfire collect

**Files:** `StarterPlayer.StarterPlayerScripts.CampfireBankClient` — `playCollect` (~line 485);
target pill lives in GameHUDClient's ScreenGui.

**Today:** collect has sparks, the cash-register sound, and a floating "+$X" at the fire — but the
money then just appears in the HUD. The gain never travels to the counter.

**Change:** in `playCollect`, after the existing effects:
- Resolve the coin pill's on-screen position: find GameHUDClient's ScreenGui in PlayerGui and locate
  the coin pill frame (inspect the live hierarchy for its name; it's the pill built by `buildPill`
  with the `goldSmall` icon). Use its `AbsolutePosition + AbsoluteSize/2`. If not found, skip the
  fly entirely (silent no-op fallback).
- Get the campfire's screen point via `Camera:WorldToViewportPoint`.
- Spawn 3 small coin sprites (copy the coin-image approach from `GameHUDPanels.DailyPanel`'s
  existing claim fly — search `flyTween`, ~line 671 — same asset, same sizing) in a
  ScreenGui, staggered 60ms apart, each tweening Position from the campfire point to the pill with
  `T.tween.fly` (0.38s, Quint, Out — DailyPanel imports this; reuse the same literal). Destroy each
  on completion.
- Do NOT add an arrival pop — the cash update already pops the pill; doubling it reads as spam.

**Verify:** collect at the campfire → coins arc from the fire to the HUD pill and vanish; number
rolls up (item 2) as they land. Camera facing away from the fire → no errors, effects skip cleanly.

## 4. Egg shop "now affordable" pop

**File:** `StarterPlayer.StarterPlayerScripts.EggShopClient` — `refreshAffordability` (~line 704).

**Today:** when the player's balance crosses an egg's price, the buy button silently snaps from the
disabled grey gradient to green (`grad.Color = ok and T.gradient.green or T.gradient.disabled`).

**Change:**
- Track each row's previous `ok` in a table keyed by row.
- Only on a **false→true transition** (and not on the first paint after open): pop the buy button —
  `UIScale` on the button (create once), set `Scale = 0.9`, tween to 1 with `T.tween.pop`
  (0.22s, Back, Out; this script already imports Tokens).
- true→false and initial paint stay exactly as they are (silent color swap).

**Verify:** open the shop just under an egg's price, earn past it while the shop is open → that
row's button pops once as it turns green. Re-opening the shop → no pop storm on paint.

## 5. Badge re-pop on count change

**File:** `ReplicatedStorage.Modules.SideRail` — `handle.setBadge` (~line 340).

**Today:** the badge pops in (scale 0→1, Back/Out) only when first appearing. If it's already
visible and the count changes (2→3), the text swaps silently.

**Change:** in the `wasVisible == true` branch, if the rendered text actually changed:
set `bscale.Scale = 1.25` and tween to 1 with `TweenInfo.new(0.25, Enum.EasingStyle.Back,
Enum.EasingDirection.Out)`. Cancel any running badge tween first so rapid updates retarget
instead of stacking.

**Verify:** with the Season tile showing a count badge, make a second reward claimable → badge bumps.
Same count re-sent → no bump (text unchanged).

---

**Order:** 1 → 2 → 4 → 5 → 3 (3 is last: it's the only cross-script one).
**After all five:** full Play-mode pass, then SAVE/publish. Confirm with the user before touching
anything outside the five functions named above.
