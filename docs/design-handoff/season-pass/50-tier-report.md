# Season pass: 25 → 50 tiers

**Date:** 2026-08-07
**File changed:** `game.ReplicatedStorage.Modules.SeasonConfig` (live Studio datamodel only)
**Studio state:** Edit mode, **NOT saved, NOT published**. Team Create is live.
**Nothing else was touched.** No other script edited, no `game-src/` mirror change, no git.

---

## 1. What changed

Six edits, all inside `SeasonConfig`:

| # | Change |
|---|---|
| 1 | Header comment: 25 → 50 tiers; Kinds list corrected (see §7); season-length note added |
| 2 | `1.38` growth rate → named constant `CASH_GROWTH = 1.28` |
| 3 | `M.TAGS`: 4 new non-exclusive titles added |
| 4 | `BOOST_FREE_LONG, BOOST_PASS_LONG = 60, 120` added alongside the existing `30, 60` |
| 5 | `FREE_SPECIALS`: 16 new entries, tiers 27–50 |
| 6 | `PASS_SPECIALS`: 16 new entries, tiers 27–50 |
| 7 | `buildTrack`: `for i = 1, 25` → `for i = 1, TIER_COUNT` with `local TIER_COUNT = 50` |

`M.XP_PER_TIER` was **left at 250** — see §6.

---

## 2. The cash curve: why 1.28

### The problem with extending at 1.38

The old rate was tuned so the curve **ended** at tier 25. Run it to 50 and `1.38^49 ≈ 7.1 million`:

| tier | old (1.38) | new (1.28) | change |
|---|---|---|---|
| 1 | $800 | **$800** | ×1.000 |
| 25 | $3,641,000 | **$598,600** | ×0.164 |
| 50 | **$11,433,921,800** | **$286,687,400** | ×0.025 |

$11.4B is more than VoidHeart ($2T aside, it exceeds every purchasable rock through the cosmic ladder's mid-point) — a ~3,100× jump over tier 25 in a single track.

### How 1.28 was chosen — measured, not guessed

The old curve's real anchor, read off the data: **the top tier pays for roughly the next rock you are reaching for.**

- Old tier 25 = **$3.64M** ≈ `StarcastIron` ($3.7M) — exactly what a ~13-day player is buying.
- So tier 50 should equal what a **~26-day** player is buying.

Measured anchors from the live configs:

```
rock FlatSkipper      $800            <- tier 1 matches this exactly, unchanged
rock StarcastIron     $3,700,000      <- old tier-25 endpoint
rock GoldenRock       $12,000,000
rock PrismaticGeode   $40,000,000
rock VoidstoneShard   $135,000,000    <-\  new tier 50 ($287M)
rock BrainrotCore     $460,000,000    <-/  lands between these
rock CometCore        $1,500,000,000  <- first cosmic rock; pass must NOT fund this
```

`RockConfig` states explicitly that the cosmic rocks (1.5B → 2T) are "where the real grind now lives". Tier 50 must stay well under CometCore.

Bare 12-pad camp income, for scale (no rebirth/upgrade/pet multipliers):

```
Legendary   24,245/sec    87,281,280/hr
Mythic     115,061/sec   414,218,880/hr
Secret     417,300/sec  1,502,280,000/hr
```

$287M ≈ **3.3 minutes** of a bare Mythic camp. Real money, not economy-breaking.

### Rates considered

| rate | tier 25 | tier 50 | verdict |
|---|---|---|---|
| 1.38 (old) | $3,641,000 | $11,433,921,800 | broken |
| 1.24 | $279,400 | $60,503,800 | finale under-delivers after a month |
| 1.26 | $410,200 | $132,518,600 | still short of the ladder top |
| **1.28** | **$598,600** | **$286,687,400** | **chosen** |
| 1.30 | $868,400 | $612,836,000 | exceeds BrainrotCore |
| 1.32 | $1,252,800 | $1,294,919,000 | ≈ CometCore — eats the cosmic grind |

### The unavoidable trade-off

**Tier 25 drops $3.64M → $598.6k (a 6.1× cut).** This cannot be avoided: any single exponential from base $800 that holds tier 25 at $3.64M *is* 1.38, which forces tier 50 into the billions. Preserving tier 25 and fixing tier 50 are mutually exclusive with one rate.

It is also the correct call — tier 25 is no longer the finale, it is the **midpoint** of a ~26-day track.

**Already-claimed tiers are unaffected**: the grant has happened and `data.SeasonClaimed` only records *that* it did. This changes unclaimed tiers only.

---

## 3. Verification results

All run in a **fresh Play VM** (the Edit-mode `require` cache was stale and still reported 25 — worth knowing for future work on this file).

### Track length, no nils

```
Tiers      #=50  present 1..50=50  nils=[]  over50=0  badXP=[]
PassTiers  #=50  present 1..50=50  nils=[]  over50=0  badXP=[]
```

### `M.DescribeReward` over all 100 tier definitions

```
100 defs checked. unexpected fall-through to Cash: 0 (none)
malformed / errored / empty-text:                  0 (none)
```

Every non-cash reward returns non-empty `text`; every cash reward returns a non-nil `amount`.

### Id resolution (the file's own comment warns a typo degrades to cash silently, so this was checked explicitly)

```
20 Egg rewards -> unresolved: 0 (all resolve in EggConfig)
 8 Tag rewards -> bad:        0 (all resolve in M.TAGS, none Exclusive)
Tiers      duplicate tag grants: 0 (none)
PassTiers  duplicate tag grants: 0 (none)
```

Duplicate tags were checked because `data.Tags[Id] = true` is idempotent — re-granting an owned title would be a dud tier.

### Cash curve at 1 / 10 / 25 / 40 / 50

Tiers 10, 25, 40 and 50 are **milestone egg tiers**, so the cash figure is the underlying `cashFor` backbone, not the payout. The reconstruction was proven against the live tables: **0 mismatches** across all realized cash tiers.

| tier | FREE | PASS | ratio | actual reward on track |
|---|---|---|---|---|
| 1 | $800 | $1,200 | 1.500 | free $800 / pass $1,200 |
| 10 ★ | $14,800 | $22,200 | 1.500 | Drip Egg / Horned Egg |
| 25 ★ | $598,600 | $897,900 | 1.500 | Crown Egg / Crown Egg ×2 |
| 40 ★ | $24,283,400 | $36,425,100 | 1.500 | Crown Egg ×4 / Crown Egg ×6 |
| 50 ★ | $286,687,400 | $430,031,100 | 1.500 | Crown Egg ×8 / Crown Egg ×12 |

Across all 18 realized cash tiers the pass/free ratio is **1.500 – 1.538** (the spread is $100 rounding at low tiers).

**Smoothness — no kink:** backbone step ratio over 49 steps, milestone doubling removed, ranges **1.2353 – 1.3077** against a target of 1.28; the spread is $100 rounding at low tiers only. Strictly increasing across 1..50: **yes**.

Total cash across 50 tiers: free **$223,597,800**, pass **$335,397,200**.

### Non-cash cadence per 10-tier band

| track | 1–10 | 11–20 | 21–30 | 31–40 | 41–50 |
|---|---|---|---|---|---|
| Tiers | 6 | 7 | 6 | 7 | 6 |
| PassTiers | 6 | 7 | 6 | 7 | 6 |

Kind mix per band (D=Darrels, B=Boost, E=Egg, T=Tag) — identical on both tracks:

```
 1-10  D2 B2 E2
11-20  D2 B2 E2 T1
21-30  D2 B1 E2 T1
31-40  D2 B2 E2 T1
41-50  D2 B1 E2 T1
```

**Longest consecutive cash-only run: 1** on both tracks. No two cash tiers are ever adjacent, so the "one long number going up" failure the header describes cannot recur.

The special tiers in 26–50 are literally the first half's plus 25 (27, 29, 30, 32, 33, 35, 37, 38, 39, 40, 42, 43, 45, 47, 48, 50), so the rhythm is identical by construction.

### Escalation with depth

```
Darrels  free  20 -> 30 -> 45 -> 60 -> 80 -> 105 -> 140 -> 185 -> 245 -> 320
Darrels  pass  35 -> 55 -> 80 -> 105 -> 140 -> 160 -> 210 -> 280 -> 370 -> 480
Boost    free  30m x4, then 60m x4
Boost    pass  60m x4, then 120m x4
Egg      free  Shard -> Drip -> Horned -> Rune -> Crown -> x2 -> x3 -> x4 -> x6 -> x8
Egg      pass  Drip -> Horned -> Rune -> Crown -> x2 -> x3 -> x5 -> x6 -> x9 -> x12
```

Every sequence non-decreasing; the egg ladder is **strictly** better each time on both tracks.

Eggs climb by quantity in the back half because the ladder tops out at Crown — following the precedent the file already set at pass tier 25 (Crown ×2).

### Free / premium relationship, all 50 tiers one-to-one

```
kind mismatch / pass-worse-than-free violations: 0 (none)
scalar (cash+darrel) pass/free ratio over 28 tiers: min 1.500  avg 1.552  max 1.833
boost ratio: exactly 2.0x throughout
totals -> free: 1230 darrels, 28 eggs | pass: 1915 darrels, 41 eggs
```

Kind, boost Stat and tier numbers line up one-to-one at every tier; the two tracks never share a tag id.

### `claimTier` Kind coverage

Checked against the actual branches in `SeasonPassHandler`:

| Kind | uses | branch |
|---|---|---|
| Cash | 36 | YES (final `else`) |
| Darrels | 20 | YES (explicit) |
| Egg | 20 | YES (explicit) |
| Boost | 16 | YES (explicit) |
| Tag | 8 | YES (explicit) |

**5 distinct kinds, all within the 5 `claimTier` supports. No new Kind introduced.**

### Console after Play restart

Clean. `SeasonPassHandler online`, full server boot chain, **no errors and no warnings**.

The only two non-standard lines are unrelated to this change:

```
[PlayerDataManager] prohacks_sorry: profile held by another live server -- read-only session
[PlayerDataManager] load failed for prohacks_sorry; session is read-only
```

That is SessionLock doing its job — a live server holds the profile. Side effect: no live claim smoke-test was possible (and no datastore writes occurred from this session). Claim-path correctness was established statically instead, via the Kind-coverage and id-resolution checks above.

---

## 4. Readers audited — none hard-codes 25

Every reader was scanned for literal tier counts and for use of `M.Tiers` / `M.PassTiers` / `M.TierFor` / `M.ThresholdFor` / `M.DescribeReward`:

| reader | how it gets the count | hard-coded? |
|---|---|---|
| `SeasonClient` | `#SeasonConfig.Tiers`, `ThresholdFor(i)`, `ipairs(Tiers)` | no |
| `GameHUDPanels.PassPanel` | `#SeasonConfig.Tiers` (×3), `ipairs(Tiers)`, `TierFor`, `ThresholdFor` | no |
| `SeasonPassHandler` | `TierFor(track, tier)`, `ThresholdFor(tier)` | no |
| `GameHUDPanels.GoalsPanel` | `PoolById` only (quests, not tiers) | n/a |
| `GameHUDPanels.BackpackPanel` | `TAGS` only | n/a |
| `GamepassConfig` | comment reference only | n/a |

`TIER_COUNT = 50` in `buildTrack` is now the single place the length lives.

**UI scaling confirmed** — no layout change needed:
- `PassPanel`: `ScrollingFrame` with `AutomaticCanvasSize = X` + horizontal `UIListLayout`; `renderTrack` loops `ipairs(SeasonConfig.Tiers)`.
- `SeasonClient`: same pattern (`AutomaticCanvasSize = X`).
- `BackpackPanel` Tags tab: `AutomaticCanvasSize = Y`, draws only **owned** tags — new tag ids stay invisible until earned.

Client confirmed live: `#Tiers=50  #PassTiers=50  ThresholdFor(50)=12500 XP`, and PassPanel's top-tier preview card now resolves to `Crown Egg x8` / `Crown Egg x12` with badge `50` and a real model (`ForestEgg5`).

---

## 5. New tag ids

All four existing non-exclusive titles were already spent at tiers 13 and 23. Since re-granting an owned tag is a no-op, tiers 38 and 48 needed new ids (same `Tag` Kind — no new reward Kind):

| tier | free | pass |
|---|---|---|
| 38 | `SkipMaster` — "Skip Master" | `RockLegend` — "Rock Legend" |
| 48 | `SeasonVeteran` — "Season Veteran" | `EternalSkipper` — "Eternal Skipper" |

All non-exclusive, so `claimTier`'s Exclusive refusal never fires. `Admin` is untouched and still on no track.

---

## 6. `M.XP_PER_TIER` left at 250 — with the reasoning

Derived from the live quest pool rather than assumed:

```
7 quests, XP mean 157.1 (min 50, max 250)
3 quests/day -> 471.4 XP/day at 100% daily completion
25 tiers x 250 =  6,250 XP -> 13.3 days
50 tiers x 250 = 12,500 XP -> 26.5 days
```

Doubling the tier count moves the season from **13.3 days to 26.5 days** — a calendar month, which is a standard season length. The old 25-tier track was arguably *too short* for something called a season. The doubled grind lands the track where it should have been, so 250 stays.

This also means the tier-50 target had a defensible basis: a ~26-day player, not a guess.

---

## 7. Concerns and notes

1. **Tier 25 nerf (the one real judgement call).** $3.64M → $598.6k for players mid-track on the free column. Unavoidable with a single rate (§2). Flagging it because it is a live economy change that existing players can notice. If it is unacceptable, the alternative is a piecewise curve (hold 1.38 to tier 25, then a lower rate) — that keeps tier 25 intact but puts a visible kink in the track, which is why it was not chosen.

2. **Stale comments in other files** — reported, not fixed, per instruction. All are comments only; no code hard-codes 25:
   - `SeasonClient` line 1 — "25-tier track"
   - `SeasonPassHandler` line 1 — "25-tier reward track"
   - `PassPanel` line 452 — "the kit mockup's '50' … this game ships 25" (the badge now genuinely renders 50)
   - `PassPanel` line 715 — "pass tier 25 gives two Crown eggs" (still true, now no longer the top)
   - `PassPanel` line 810 — "SeasonConfig.Tiers (currently 25)"

3. **Header comment corrected — a real latent trap.** The old block documented `Rock` and `Pet` kinds. `claimTier` has **never** had a branch for either; they would fall into the final `else` and grant `r.Amount`, which on a Rock/Pet reward is `nil` → **0 cash, a silent dud tier**. Neither track ever listed one, so nothing was actually broken, but the comment was inviting someone to add one. The block now lists only the 5 real kinds and says so explicitly.

4. **Pass tier 50 hatches 12 eggs in one claim.** `claimTier` loops `hatchOne` `Qty` times synchronously. This is the largest single-claim burst on either track. `PetHandler.Grant` caps *equipped* slots, not ownership, so 12 pets landing at once is fine — but it is the deepest untested path. Worth one live claim once the datastore session is free.

5. **The paid track has never been claimable** — `GamepassConfig` still has `GamepassId = 0`, so `GamepassService.Owns` is false for everyone and `claimTier` rejects `track == "pass"` server-side. All `PassTiers` changes are therefore zero-risk to live players today.

6. **Edit-mode `require` cache is stale after editing this module.** `require` in Edit mode kept returning the old 25-tier table. Verification must run in a fresh Play VM.

---

## 8. Outstanding

- **Not saved, not published.** Team Create is live with other editors connected — saving is the user's call.
- One live claim of a deep egg tier (note 4) once `PlayerDataManager` can load a writable profile.
