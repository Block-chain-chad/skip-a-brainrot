# Catch Reveal — Design

**Date:** 2026-07-27
**Status:** Approved (user approved the ladder and the plumbing 2026-07-27)
**Scope:** Client presentation only. Zero server, economy, data-schema or remote changes.

## Goal

When you catch a brainrot, **the brainrot itself appears on your screen and spins slowly**,
escalating with rarity. The user's words: *"I dont want a card I want a 3d brainrot
spinning"* and *"escalate by rarity is also perfect."*

Today a catch produces a small text card — `LEGENDARY` / the name / `Distance: 340m | +$1.2k/s` —
so you never see the thing you caught. The 150 models already sit in
`ReplicatedStorage.BrainrotModels` and `BrainrotThumb` already renders them. This closes the gap.

## Non-goals

- **No card.** The existing `resultFrame` popup is retired, not decorated.
- **No server changes.** `ThrowResult` already carries every field the reveal needs.
  Nothing in `ServerScriptService` is edited in this phase — the place is shared with
  `yeep1234`, and a client-only change cannot collide with their work.
- **The Robux skip / auto-sell upgrade is NOT built here.** See "Phase 2 hooks" below.
  This spec only guarantees the reveal is shaped so that upgrade is a small addition.
- No new remotes, no new player data fields, no changes to what any control *does*.

## Phase split

The user asked for two things: the reveal, and a purchasable Robux upgrade that skips the
animation and auto-sells a chosen rarity. They chose **"reveal now, upgrade next"**.

Phase 2 is genuinely separate: it needs a product created on the Creator Dashboard (which
Claude cannot do, and which has blocked work on this project before), server-verified
ownership checks, a per-player "which rarities to auto-sell" setting, and a settings UI.
Half of it ("skip the animation") cannot exist until the animation does.

## Reference points in the live code

| Thing | Where | Why it matters |
|---|---|---|
| Catch payload | `ThrowHandler.revealCatch` → `remotes.ThrowResult:FireClient` | Carries `BrainrotName`, `Rarity`, `RarityColor`, `Mutation`, `CashPerSecond`, `Serial`, `Distance`, `Perfect`. Complete for our needs. |
| Old card | `ClientMain`, `remotes.ThrowResult.OnClientEvent` (~line 602) | `resultFrame` + `resultToken`. Retired by this change. |
| World FX | `ClientMain.celebrateCatch` | FOV punch at Rare+, light pillar + camera shake at Epic+. Kept for bands 1–3, suppressed for band 4. |
| 3D thumbnails | `ReplicatedStorage.Modules.BrainrotThumb` | `master(name)` cached stripped model, `add(parent, name, opts)` ViewportFrame with bounding-box-framed camera. |
| UI rarity flair | `ReplicatedStorage.Modules.RarityFX` | Existing vocabulary: halo stroke, shine sweep, sparkles, rainbow cycle. One shared `Heartbeat` driver. |
| 3D mutation FX | `ReplicatedStorage.Modules.MutationFX` | `apply(model, mutationName)` / `clear(host)`. 12 rungs in 4 bands. **World-only.** |
| Tiers | `ReplicatedStorage.Modules.RarityConfig` | 8 tiers, Common → God, each with a `Color`. |
| Mutation colour | `MutationConfig.Color(name)`, `.Rarity(name)` | 12 rungs, Golden(1) → Angel(12). |

### The constraint that shapes the whole design

**ParticleEmitters and `Highlight` do not render inside a `ViewportFrame`.**
`BrainrotThumb` already states this in its own header comment: *"Viewports only draw
BaseParts… Those render nothing."*

`MutationFX` is built entirely from those two instance types. So a viewport reveal
structurally cannot show mutations, and a world reveal can. That is the sole reason the
design is hybrid rather than one render path.

## The ladder

Four bands over the eight tiers, grouped to match how `RarityFX` and `MutationFX` already
band things. Each band adds a **new kind** of effect rather than more of the last — the
rule that made the `MutationFX` and `RarityFX` ladders readable.

| Band | Tiers | Render | Length | Backdrop | Adds |
|---|---|---|---|---|---|
| 1 | Common, Uncommon | ViewportFrame, small (~180px) | 1.4s | none | model + name/rarity |
| 2 | Rare, Epic | ViewportFrame, ~280px | 2.0s | 15% dark | coloured halo in tier colour |
| 3 | Legendary, Mythic | ViewportFrame, ~380px | 2.8s | 45% dark | rays behind + sparkles |
| 4 | Secret, God | **real world model** | 3.8s | 80% dark | camera lock, full `MutationFX`, rainbow name |

"n% dark" is a full-screen black `Frame` at `BackgroundTransparency = 1 - n`, fading in over
0.2s and out with the reveal. Stated as opacity because "dim 0.8" read as a transparency
value would mean the opposite of what is intended.

All pixel sizes, durations and dim values are **starting points to be tuned by eye in
Studio**, the way the trees, the font, the terrain palette and the SFX kit were. The
structure is fixed; the numbers are not.

### The spin

One identity across all four bands: **constant angular velocity around world Y**, no
easing, starting from `BrainrotThumb`'s existing front-quarter `DEFAULT_DIR` so the model
faces the player on arrival.

Default **70°/second** — a full turn every ~5.1s. Band 1 therefore shows ~98°, band 4
~266°. Deliberately not "one full turn per band": a shared rate makes every reveal feel
like the same object, which is what "smooth slow spin" asks for. Per-band override allowed
but expected to stay unused.

Driven by a **single connection that exists only while a reveal is playing** and disconnects
on teardown — `RarityFX`'s one-driver pattern, not a connection per reveal.

`RenderStepped`, not `Heartbeat`: band 4 moves the camera, and camera work done on
`Heartbeat` lands a frame late and judders. `RarityFX` uses `Heartbeat` because it only
tints UI, where a frame of latency is invisible.

### Text

Name and rarity only, as floating outlined labels beneath the model. **No panel, no
background** — that is the point of the change. Rarity in `RarityColor`, name in
`UITheme.Camp` ink with `UITheme.inkText` outlining, `UITheme.Font` for the face.

A mutated catch shows the mutation as a name prefix (`Angel Tralalero Tralala`), matching
what `RareCatchClient` already does.

**Band 4's "rainbow" is the rarity label cycling hue**, `Color3.fromHSV((t * 0.3) % 1, 0.82, 1)`
— the same one-property technique `RarityFX` uses for Secret/God tiles. It is called out
because bands 1–3 carry rarity in a static tier colour and there is no card or border in
band 4 for a rainbow to live on.

Distance and cash/s are **dropped**. Distance is already displayed live while the stone
flies; cash/s is visible in the backpack grid.

### Mutations by band

- **Bands 1–3 (viewport):** particles cannot render. The mutation shows as the name prefix
  plus the halo retinted to `MutationConfig.Color(name)` instead of the tier colour.
- **Band 4 (world):** `MutationFX.apply()` runs on the real model — all 12 rungs, real
  lights, sparkles, motes and `Highlight`. This is the payoff for the hybrid, and it lands
  exactly where it matters: Secret and God are the catches where a mutation is most worth seeing.

### Interaction with existing world FX

`celebrateCatch` keeps firing for bands 1–3. For band 4 it is suppressed: the camera is
locked on the model, so the pillar spawned around the player's character would be
off-screen, and a camera shake would fight the lock.

## Architecture

Two new files, one edited file, nothing on the server.

### `ReplicatedStorage.Modules.CatchReveal` (new ModuleScript)

Owns the reveal and nothing else. Knows nothing about remotes, and nothing about Robux.

```
CatchReveal.play(info) -> handle     -- info = {Name, Rarity, RarityColor, Mutation}
handle:skip()                        -- tear down immediately; safe to call twice
CatchReveal.isPlaying() -> boolean
```

A module rather than loose code inside the client script because fusion results, wheel wins
and egg hatches are all plausible future callers of the same reveal, and because it can then
be exercised in isolation from a real throw.

Internal responsibilities: pick the band from `Rarity`, build the UI (dim + viewport +
labels) or the world model + locked camera, run the spin driver, tear everything down.

### `StarterPlayerScripts.CatchRevealClient` (new LocalScript)

Subscribes to `remotes.ThrowResult`, decides whether to reveal, calls `CatchReveal.play`.
Deliberately thin — it is the seam where phase 2 plugs in.

### `ClientMain` (edited)

- Stop showing `resultFrame` on `ThrowResult`. The frame and its styling block are left in
  place but unused, so the change is a one-line revert if the user wants the card back.
- `celebrateCatch` gains an early return for Secret/God (band 4 suppression).

**Collision risk:** `ClientMain` is a shared file the collaborator has live-edited before.
Both edits are small and localised; re-read the file immediately before editing rather than
trusting line numbers from this spec.

## Phase 2 hooks

Two hooks, in two different places, for two different reasons.

**Skip — client-side, and that is correct.** `CatchRevealClient` gets:

```lua
local function shouldReveal(result)  -- phase 2: check gamepass + chosen rarities
    return true
end
```

Skipping an animation is a pure presentation choice. A client lying about it costs nothing,
so the client may own it.

**Auto-sell — server-side, and this is not negotiable.** It belongs in
`ThrowHandler.revealCatch`, where the catch is granted, behind a server-verified
`MarketplaceService:UserOwnsGamePassAsync` check and a server-stored per-player rarity
selection.

A client that can say "sell this catch" can say it about anything, which is a free-money
exploit.

**No server file is touched in this phase, including by comment** — the extension point is
recorded here in the spec, not marked in `ThrowHandler`, so that "nothing on the server"
stays literally true and there is no chance of colliding with the collaborator over a
comment. Recording it explicitly because the two features were requested in one sentence,
and building auto-sell into the reveal would be the natural — and wrong — reading.

## Failure modes

| Failure | Handling |
|---|---|
| No model for that name (`BrainrotThumb.master` returns nil) | Fall back to a text-only reveal: name + rarity, no viewport. A missing model must never cost the player their catch or throw an error. |
| **Camera left locked after band 4** | Restore inside `pcall`, plus a watchdog `task.delay(duration + 3)` that force-restores if teardown never ran. Same belt-and-braces as `ThrowHandler`'s existing flight watchdog. A stuck camera is unrecoverable without rejoining, so it gets two independent guards. |
| A catch lands mid-reveal | Newest wins, token-guarded so a stale teardown cannot kill a newer reveal. Matches the existing `resultToken` behaviour in `ClientMain`. |
| Character dies / resets mid-reveal | Tear down, restore camera, disconnect the driver. |
| Character or camera missing when a reveal starts | Skip the reveal silently. Never error. |
| World model leaks | Client-created so it never replicates to other players. Anchored, `CanCollide = false`, `CanQuery = false`. Explicitly destroyed on teardown, with `Debris:AddItem` as a backstop. |
| `MutationFX.apply` errors on an odd model | `pcall`. The reveal must survive a bad mutation far more than it must show one. |

## Verification

- **All eight tiers.** `ThrowHandler` already has a `forcedCatch` override — force one catch
  per tier and confirm each band renders with the right size, dim and effects.
- **Band 4 with a mutation.** Confirm real `MutationFX` particles appear on the world model —
  this is the specific thing the hybrid exists to deliver, so it must be seen, not assumed.
- **Fallback path.** Force a catch with a name that has no model; confirm text-only and no error.
- **Camera restore.** After every band-4 reveal, and after a mid-reveal `skip()`, and after a
  death during a reveal.
- **Rapid catches.** Two catches close together; confirm the newer reveal survives and the
  older teardown does not kill it.
- **Zero console errors** across the whole sweep.
- **FPS A/B in a single session** — Studio's absolute FPS numbers drift between sessions
  (measured 15.1 and 29.0 minutes apart on an unchanged scene), so only same-session
  comparisons count.

Verification is by looking at the real thing in Studio, not by reading the code back.
