# Brainrot Visual System — "Every Name Gets a Body"

**Game:** Skip a Brainrot (Roblox)
**Date:** 2026-07-25
**Status:** Approved design, pending implementation plan
**Depends on / feeds:** `2026-07-25-bounded-supply-design.md` (guest debuts use its SEASONS machinery)

## Goal

Brainrots are currently 2.5-stud Neon cubes. Give every roster name a fixed,
recognizable, owned-forever body built from primitives, without touching the
server systems that make brainrots earn, trade, and persist.

## Decisions (settled with the user)

- **Roster**: the 213 originals stay the backbone (verified collision-free by
  the 2026-07-25 provenance research — zero overlaps with real memes or other
  games). **~12 verified-safe guest memes** join over time, drip-fed as
  seasonal `Debut`s per the bounded-supply spec.
- **Guest curation rule**: only names classified MEME with a documented
  outside creator AND no enforcement signals. Excluded explicitly:
  Tung Tung Tung Sahur, Ballerina Cappuccina, Brr Brr Patapim (rights-holder
  activity: Fortnite licenses / Mementum filings / C&D), and Cappuccino
  Assassino (near-duplicate of our Ammazzacaffe Nerissimo). Candidate pool
  (final 12 picked at implementation): Lirilì Larilà, Tim Cheese, Trippi
  Troppi, Boneca Ambalabu, Bandito Bobritto, Glorbo Fruttodrillo, Chimpanzini
  Bananini, Bombombini Gusini, Frigo Camelo, La Vacca Saturno Saturnita,
  Trulimero Trulicina, Bombardiro Crocodilo. Verdict data:
  https://claude.ai/code/artifact/76704d76-76a8-435d-9764-405c850c6e89
  Standing caveat: "no enforcement found" ≠ "no risk" — guests must always be
  individually removable (vaultable) without touching anything else.
- **Look language** (settled last session): goofy creature WITH a face —
  body shape + two eyes + sometimes mouth + stubby limbs + one accessory,
  ~10–16 primitives (Block/Ball/Cylinder/Wedge/CornerWedge only; no uploads,
  no MeshParts, no CSG). One fixed look per name, forever, derived from the
  name — never randomized, identical for every player on every server.
- **Architecture**: bodies are built **client-side** over the existing
  server anchor Part, which becomes invisible. Server stays authoritative for
  everything that matters (Uid, StorePrompt, billboard, income); the client
  owns rendering and idle motion.

## Why client-side bodies

The three fragile integration points identified last session —
`IncomeLoop` filtering pads with `model:IsA("BasePart")`,
`BrainrotMover.RemovePadVisual`, and the billboard lookup — all assume the
brainrot is a single Part. Building bodies client-side keeps all three
untouched: the anchor Part IS still the brainrot as far as the server is
concerned. Bonus: ~1,400 parts (full plots) never replicate, and idle motion
costs the server nothing. Trade-off accepted: bodies only exist at runtime on
clients, so Studio Edit mode shows anchors only; verification happens in Play
mode.

## Components

### 1. `ReplicatedStorage.Modules.BrainrotLooks` (new, data)
One explicit recipe per name (all 214 authored entries + guests as they
debut):
```lua
["Scarpa Volante"] = {
  Body = "shoe", BodyColor = <Color3>, Accent = <Color3>,
  Size = 1.0,                 -- scale factor; tier nudges presence
  Face = "happy",             -- eye/mouth preset key
  Accessory = "wings",        -- one accessory key, may be nil
  Motion = "hover",           -- idle animation preset
},
```
Recipes are explicit data — reviewable, hand-tweakable, diffable. They are
GENERATED at authoring time via the lexicon (below), then frozen.

### 2. The Italian lexicon (authoring tool + doc, not runtime code)
~70 word→visual rules mapping the roster's Italian vocabulary to body
shapes, accessories, palettes, and motions (scarpa→shoe body, caffè→cup +
espresso brown, torpedo→long tapered body, volante→wings + hover,
mandolino→instrument accessory…). Applied by the authoring fleet to draft
all 213 recipes; ships as `docs/brainrot-lexicon.md` so future waves inherit
the rules. The name/look joke is the product: "Scarpa Volante" must BE a
flying shoe.

### 3. `ReplicatedStorage.Modules.BrainrotBodyBuilder` (new, pure)
`Build(recipe) → Model` of welded, anchored primitives. Deterministic, no
random calls. Body presets (~12 shapes), face presets (~6), accessory presets
(~15), each a small part-list function. Also used by the Index for
ViewportFrame thumbnails, so the roster UI finally shows creatures.
Budget: ≤16 parts standard, ≤24 for Secrets.

### 4. `StarterPlayer.StarterPlayerScripts.BrainrotBodyClient` (new)
Watches for brainrot anchor Parts appearing on plot pads (existing folder
structure / names — exact hook chosen at implementation after reading
`BrainrotSpawner`), builds the body at the anchor, runs the idle motion
preset (bob/sway/hover via RenderStepped-lite or a single Heartbeat loop with
staggered phases), destroys the body when the anchor goes. Distance-gated:
full motion near, static beyond ~120 studs.

### 5. Server-side change (minimal)
`BrainrotSpawner` makes the anchor invisible (Transparency = 1, keep size and
Neon removal) — the cube era ends. Nothing else changes server-side.

### 6. Bespoke tiers
The 11 Secrets + Secret Pete get hand-authored bespoke recipes (still
primitives, up to 24 parts) — they are the trophies and get the extra care.
Guest memes get bespoke primitive INTERPRETATIONS of their canonical look —
always our own build from scratch, never imported assets.

## Quality gates

1. **Uniqueness check (automated)**: no two recipes may share
   (Body, Accessory, quantized BodyColor) — a script over BrainrotLooks
   fails loudly on collision.
2. **Coverage check (automated)**: every name in BrainrotConfig has a recipe;
   every recipe key exists in BrainrotConfig (no orphans).
3. **Part-budget check (automated)**: Build() each recipe once in Studio,
   count parts, assert ≤16 (≤24 bespoke).
4. **Visual sampling (manual + screenshots)**: Play-mode screenshots of a
   spread of tiers from the player's actual viewpoint (standing rule:
   verify from the user's angle, measure real footprints — see
   verify-spatial-fix memory).
5. **Regression**: income still ticks, store/trade prompts still work, and
   billboards still track with bodies rendered (the 3 integration points).

## Edge cases

- **Anchor destroyed mid-animation** → body cleanup is connection-driven
  (AncestryChanged), never polled.
- **Player joins with plots already full** → renderer does an initial sweep,
  then listens.
- **Unknown name (future wave before recipes ship)** → fallback recipe (the
  classic cube, as a wink) + warn once; never error.
- **Index thumbnails for locked names** → silhouette-only render (black
  body, eyes visible) to preserve the reveal.
- **Low-end devices** → bodies are static beyond distance gate; motion loop
  budget capped (single loop, staggered phases, no per-body connections).

## Testing

- Studio Play mode: spawn a spread of tiers on a plot, screenshot from
  player viewpoint, verify silhouettes read at gameplay distance.
- Automated gates 1–3 run as a Studio command script before ship.
- Trade/store/income smoke test with bodies live.
