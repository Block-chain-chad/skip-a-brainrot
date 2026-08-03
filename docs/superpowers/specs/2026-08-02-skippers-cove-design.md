# Skipper's Cove — Trading World Rebuild (2026-08-02)

Approved in-session by the user. Goal: rebuild the trading island at (8000, 2000, 8000)
with the structural lessons of Pet Simulator 99's Trading Plaza (dense circular plaza,
water ring, zoned landmarks, big readable signage, reward chests) expressed entirely in
our own beach / skip-rock / brainrot identity. Explicitly NOT a visual copy — the user
does not want to be seen as a copycat.

## Scope

**Today (this session): the look.** World geometry, landmarks, signage, decor.
**Next pass: backend.** Chest claim logic, board data feeds, Index gate prompt, mailbox/gifting.
Chests are unmissable props with signs today; claiming is wired later.

**Owner-blocked items** (BigFrogTerryBruh must create; ids wired next pass):
- Roblox group → Group Rewards chest claims
- VIP gamepass → VIP chest claims

## Layout (all coords absolute; island centre C = (8000, ~2000, 8000))

Vertical datums: Deck (seabed) top y2000 · water ring top y2002.0 · land top y2002.4.
South (−Z) = cove mouth / arrival; north (+Z) = cliff cove.

- **Central plaza**: sand disc r62 at C. Trade gazebo + TradeZone at centre.
- **Water ring**: annulus r62–88, translucent teal part-water (16 chord boxes), deck as bed.
- **Outer ring**: sand annulus r88–118 (16 chord boxes), zones on it.
- **Bridges** N/S/E/W spanning r60–90, arched planks + rope rails.
- **Cliff cove**: sandstone cliff masses arc 40°–140° at r126–150, green caps, palms,
  2 waterfalls (visual sheets + splash pools at ring's outer edge).
- **Market cove (N)**: driftwood + surfboard arch "MARKET" at north bridge; 12 booths
  re-skinned in an arc (r103, 35°–145°, facing centre).
- **Boards (W, r103)**: 3 upright surfboards — TOP SALES / TOP TRADERS / RECENT SALES
  (placeholder text today; PriceIndex + LeaderboardHandler feed later).
- **Index gate (E, r103)**: coral ring-gate, part named `IndexGate` for later prompt wiring.
- **Chests**: Group Rewards = half-buried treasure chest + "JOIN THE CREW!" sign at
  plaza NW rim (7966, 8034); Social Rewards = giant message-in-a-bottle + "FOLLOW US!"
  at plaza SW rim (7966, 7966); VIP = crowned chest on islet r9 at (8055, 7945) in the
  water ring, stepping stones from both shores.
- **Eternal Skip**: glowing stone perpetually skipping around the water ring at r68
  (clears VIP islet), splash rings on touchdown. Server Script inside its model.
- **Wave portal (S)**: curling-wave arch rebuilt around the EXISTING
  `HubPortal.PortalTouch` (Dest="Hub") at (8000, ~2006, 7895). Boardwalk connector to
  the south bridge. Arrival stays TRADE_POS (8000, 2006, 7905) — lands on outer ring.
- **Decor**: chunky palms, tiki torches, umbrellas, shells, coin piles at chests,
  lily pads in the ring. CoveBarrier: invisible wall ring r~121.

## Functional contracts (MUST survive)

- `TradingCenter.Booths.Booth1–12`: keep `BoothIndex` attr; keep/rebuild children named
  `Counter` (with `StandPrompt` ProximityPrompt inside), `Display1–3` (listing cubes
  spawn at anchor CFrame × (0,1.7,0)), `SignBoard` (SurfaceGui with a TextLabel —
  BoothHandler.setSign writes it). Other booth parts are free-form decor.
- `TradingCenter.TradeZone`: keep name + box coverage of the gazebo (both TradeHandler
  and TradeClient do box math on CFrame/Size).
- `HubPortal.PortalTouch` with `Dest` attribute: reuse the existing instance.
- `TeleportService.TRADE_POS` (8000,2006,7905) unchanged; ground must exist beneath it.
- StreamingEnabled place: new builds live inside TradingWorld / TradingCenter
  (both ModelStreamingMode = Persistent).
- Do NOT touch Lighting globals or Terrain (shared with the main map). Local lights only.

## Palette / style

Chunky low-poly, SmoothPlastic + sparing Neon. Sand (238,214,166) / dark sand
(216,186,130) / coral (255,116,96) / water teal (0,170,185, Tr .35) / neon turquoise
(54,224,214) / driftwood (168,144,110) / dark wood (124,96,66) / foam white (245,250,250)
/ gold (255,196,64) / leaf (108,198,92) / sandstone (226,190,140). Billboard text:
stud-sized (UDim2 scale = studs) + MaxDistance ≤ 260 — no distance-scaling monster signs.

## Verification

Structure agent: 12 valid booths, TradeZone, PortalTouch Dests, ground under TRADE_POS,
no default-grey parts, Persistent streaming modes. Visual agent: aerial + 4 player-angle
captures graded against this spec. Fix round in main loop. User playtests + saves.
