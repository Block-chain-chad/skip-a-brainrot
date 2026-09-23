# TRADE Item 2: stall counter guards (2026-09-23)

MASTER's ask: stop players climbing the 18 counters, without changing how they look or the booth
interaction range; back up first; part-count rise under 50; play-test claim/release on 3 stalls.

## What changed

- New generator section `GameWorld.TradingWorld.CounterGuards` (SettlementGenerator **v15**, `G.CounterGuards()`,
  also in `SECTIONS` so `G.BuildAll()` rebuilds it). 20 invisible parts: one per stall, two at #13 and #15.
- Each guard covers exactly the CounterTop footprint (8.5 x 2.9), from +3.2 (0.06 into the CounterTop) up to its
  `top`. `Transparency 1, CanCollide true, CanTouch false, CastShadow false, Locked true`, the same recipe as `G.Barrier`.
- Nothing inside the Booth models changed. The guards are kept out of them on purpose: `NpcFocusClient` outlines the
  whole booth model when a StandPrompt shows, and a part inside it would draw a floating box.
- Untouched: `Counter.Position` (BoothHandler's `BUY_RADIUS` 26 centre), StandPrompt (range 8), BuyPrompt (range 10).
  Both prompts are `RequiresLineOfSight = false`, so the guards can't hide them.
- Part count +20. Studio generator source is byte-identical to this repo file.

## Why the heights are what they are

The original complaint is real and worse than "climb": an R15 avatar with a tall HipHeight (Terra's is 2.94)
**walks** onto a 3.26 counter from the storefront step without jumping (the Humanoid step-up). Measured with the
guard switched off client-side: the root ended at local z 0.50, on the counter.

The first build used 10-stud guards and Terra's avatar got on top of one from the street. The root part rides
HipHeight above the feet and R15 legs don't collide, so a jump clears a ledge at standing height + HipHeight + 7.2.
Guards are sized for HipHeight up to 3.5 and a sprint (33.8) jump arc from every standable prop or walkway near the
stall, plus 0.8. Where a solid balcony, lean-to, stair landing or arcade floor covers the counter, the guard is sealed
to its underside instead, so there's no top to stand on and nothing pokes through a walkable surface.

| Stall | Top (studs above counter foot) | Driven by |
|---|---|---|
| 1 | 16.5 | Gateway open post (12, 18 off); the gate-post cap is now boxed in |
| 2, 5, 12 | 14 (default) | street, 2.2 plinths, crates/baskets |
| 3 | 8.55 | sealed under the B4 balcony |
| 4 | 8.45, left end only | sealed under the B5 landing (see findings) |
| 6 | 15 | tree trunk (10, 18 off) |
| 7 | 22 | B5 stair balusters (9.7) and landing (9.0) in front |
| 8 | 23.5 | the stone arch is walkable from the piers (crown 11.9) |
| 9 | 9.05 | sealed under the Curio House arcade floor |
| 10 | 20 | canopy post tops (8.2) |
| 11 | 17 | causeway parapet (5.2, 9 off) |
| 13, 15 | front 7.6 / back 20 | front sealed under the lean-to; back clear of the lean-to roof (8.4) |
| 14 | 9.35 | sealed under the S4 balcony |
| 16, 17 | 18.5 | lamp posts (6.6, 4.5 to 5.5 off) |
| 18 | 23 | north stub ramp (9.4) and parapet (10.6), 8 off |

## Tests (Play in the shared place, 2026-09-23)

- **Poke-through:** a ray straight down from +40 over every counter first hits the guard top (open stalls) or the
  balcony / landing / arcade / lean-to (sealed ones). `G.Contracts()`: OK 18/18 stalls.
- **Jumping at the counters**, Humanoid.Jump held every frame + moving at the counter, with Terra's avatar
  (HipHeight 2.94) and again with HipHeight forced to 3.5: street run-ups at #2, #8, #18; #17 from the lamp-post
  top. Nobody got onto a counter, and nobody got onto a guard top straight from the street or a stall prop.
  Closest calls: #2 root bottom peaked 13.4 against 14 (HipHeight 3.5); #17 17.4 against 18.5.
- **Two runs did reach a guard top, both by way of a building (finding 2):** #12 crate -> boat-shed wall top (11.8,
  1.75 behind the counter) -> guard top, with Terra's own avatar; #13 lean-to roof -> S3 body (10.8) -> back guard
  (HipHeight 3.5). The crate -> wall hop needs HipHeight >= ~2.6, so default-size avatars can't.
- **Walking in:** the root stops 3.6 from the Counter centre (StandPrompt reach 8). A tall avatar stops ~0.4 further
  out than before because its head can no longer lean over the top.
- **Claim / release on #2, #13, #17:** StandPrompt shown at 4.7 studs, held (`InputHoldBegin`, the same path as the
  touch UI) -> server set "Manage Stand"; `BoothList {Action = "Unclaim"}` (what the Unclaim button fires) -> back to
  "Claim Stand". 3/3.
- **Walk-up outline:** screenshot at #2 shows NpcFocus outlining only the booth (counter, step, shutters), no box.

## Findings (not fixed here)

1. **Stall #4 is buried.** Phase 5's solid stair treads (`steps()` builds each tread down to the flight's foot) put
   the B5 external stair right through it: counter, displays, sign and crate are inside the blocks. Only the left
   1.2 studs is open, under the landing. The StandPrompt still works because it skips line of sight. Needs a layout
   fix (move the stall or make the stair open) before launch.
2. **Rooftop parkour.** Every roof in the settlement is non-collidable over a solid building body or wall. Players
   can walk the tops of those bodies (visibly inside the roofs), and from there any guard beside a building is
   reachable. Seen in testing: #12 crate -> boat-shed wall top (11.8); #13 lean-to -> S3 body (10.8). Guards
   deliberately don't chase this (they'd need 25 to 35 studs). The real fix is settlement-wide: stop people
   standing on building tops.
3. **VIP scooter** sets JumpPower 105 (about a 28-stud jump), so a rider can reach any guard top, as they can any
   roof. Only a script could stop that; not done without MASTER's OK.

## Backup and rollback

`ServerStorage._BACKUP_TRADE_counters`: untouched clones of every Counter and CounterTop (36 parts), the v14
generator (`SettlementGenerator_v14`) and a README. Rollback: delete `GameWorld.TradingWorld.CounterGuards` and put
`SettlementGenerator_v14` back as `ServerStorage.TradingWorldBuild.SettlementGenerator`.
