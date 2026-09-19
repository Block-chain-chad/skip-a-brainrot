# Trading World NPC roles — handoff from TW-01 to NPC-01

**From:** TW-01 (Trading World rework) · **To:** NPC-01 (Global NPC Character Overhaul) · **Date:** 2026-09-19 · **Status:** Phase 1 requirements — nothing placed yet.

TW-01 owns *which roles, how many, where, why*. NPC-01 owns *the characters* (rigs, outfits, faces, hair, props, animation standard). This file is the contract between the two lanes. Full context: `docs/TRADING-WORLD-REWORK-PHASE1.md` §B.1 (the Brainrot Grand Exchange) and its layout `grand-exchange-layout.svg`.

## Ground rules

- Every interaction listed is an **existing** behaviour: the round-3 dialogue shell, walk-up prompts styled by `UIKit.InteractionPrompt`. A new prompt *name* needs a `VERB_BY_NAME` entry from the UI lane; the safe default is the existing `TalkPrompt` → "TALK". No quests, no new remotes, no new systems.
- NPCs are anchored R15 rigs on NPC-01's standard (`NpcRigLife` / `NpcBodyLife` / `NpcPropLife` / `NpcIdle`, proximity-gated at 90 studs). Nothing here asks for walking NPCs.
- Nothing may stand on the promenade lane stripe (r58 around C), on the causeway axis (x 7988–8012, z 7846–7930), or inside the `TradeZone` box (46×46 centred on C).
- Compass: N = +Z, S = −Z, E = −X, W = +X. Heights are relative to P = y2002.4 (the promenade); "+6" = the Vault plateau, "+12" = the balcony, "−0.8" = the exchange-floor step.
- Highlights: the world budgets 7 (six colossi + the God statue) plus `NpcFocusClient`'s one. NPCs must not add their own Highlights.

## Placement contract (what TW-01's generator will leave for NPC-01)

For each mark below the Phase 2 generator places an invisible anchor part `GameWorld.TradingWorld.NpcPosts.NpcPost_<Role>` (4×0.2×4, `Anchored`, `CanCollide false`, `Transparency 1`) whose `CFrame` is the standing spot and facing, with attributes `Role` (string), `Tier` (1–3), `Prompt` (`"TalkPrompt"` or `"none"`), `Note` (one line). NPC-01 pivots the finished rig onto the post (`Model:PivotTo(post.CFrame)`) and parents it under `GameWorld.TradingWorld.NPCs`. TW-01 never edits an NPC model; NPC-01 never moves a post — ask, and TW-01 regenerates.

## Roles

| # | Role (working name) | Tier | Standing spot (x, y, z) · facing | Personality | Required interaction | Visual needs | Prop ideas |
|---|---|---|---|---|---|---|---|
| 1 | **Exchange Host** ("Ledger") | T1 — must ship | (8000, P, 7948), just inside the Great Arch on the axis, facing S toward arrivals | Warm, brisk, floor-manager energy; an auctioneer who has seen everything | `TalkPrompt` → dialogue: how a stand works (claim / list / price / buy), where the Vault is, where the prices board is. Dialogue only. | Formal exchange uniform in cream + gold; a sash in the eight rarity colours (`RarityConfig`); must read from 40 studs | Clipboard/ledger, gold gavel, a bell on a stand beside him |
| 2 | **Gem Broker** | T1 — must ship (monetisation tie-in) | (8032, P, 7952), at the Ticker Wall on the +X side of the arch, facing the axis | Smooth, fast, counts on his fingers | `TalkPrompt` → dialogue with an "OPEN SHOP" action that opens the existing Gems shop (`HudPanelRequest` seam). **UI lane must confirm the dialogue shell supports an action button** — otherwise dialogue only. | Sharp suit, gem monocle, teal/gold matching the HUD's Gems pill | Gem scale, velvet tray of gems, abacus |
| 3 | **Rare Brainrot Curator** | T2 | (8000, +6, 8148), Reliquary end of the Vault, facing S down the nave | Hushed, reverent, slightly unhinged collector | `TalkPrompt` → dialogue: what Secret / God / Golden / Diamond / Huge / Massive mean; points at the alcoves | Dark robe with pink + gold trim, white gloves, museum-guard cap | Magnifying glass, velvet-rope stanchions, a display case |
| 4 | **Booth Attendant (West)** | T2 | (8036, P, 8062), north end of the West Arcade, facing the lane | Cheerful, helpful — "stands are free!" | `TalkPrompt` → dialogue: claiming a stand, the 3-listing cap, that leaving the game releases it | Arcade apron in teal, name tag | Broom, stack of blank price plates, a VACANT sign under one arm |
| 5 | **Booth Attendant (East)** | T2 | (7964, P, 8062), mirror of #4 | Grumpier twin | same | same, mirrored colours | Mop bucket, ledger |
| 6 | **Collector** | T3 | (7972, +12, 7972), SE balcony, leaning on the balustrade looking down at the floor | Cryptic, always "looking for one more" | `TalkPrompt` → flavour dialogue about the market (no quest) | Long coat, travel bag covered in brainrot patches | Binoculars, a want-list poster |
| 7 | **Ambient Trader pair** | T3 | Exchange-floor step, (7988, −0.8, 8012) and (8012, −0.8, 8012), facing each other | Mid-haggle, animated | none (idle only) | Two contrasting merchant outfits | Contract scroll, gem pouch |
| 8 | **Ambient Pier Angler** | T3 — optional | Skipper's Pier end (8120, P, 8000), facing the moat | Sleepy | none | Fisher hat; the game's own rod | Rod, bucket, a skip stone |
| 9 | **Vault Guards ×2** | T3 — optional | (7986, +6, 8092) and (8014, +6, 8092) flanking the Vault portal, facing S | Statue-still | none | Armoured, gem visors, symmetrical pair | Halberds with gem heads |

**Recommended v1 count: 7** (roles 1–7; roles 8–9 optional). Keep the crowd light — the brief says "avoid overly heavy NPC crowds", and every NPC here is proximity-gated anyway.

## Open questions for NPC-01

1. Does the current dialogue shell support an action button (role 2)? If not, TW-01 will list the Gem Broker as dialogue-only and the Gems tie-in becomes signage.
2. Preferred rig scale for the Host so the sash reads at 40 studs — TW-01 can widen the arch landing if a 1.15× rig is wanted.
3. Any NPC-01 naming convention for `GameWorld.TradingWorld.NPCs.<Name>` that TW-01 should mirror in the post names.
