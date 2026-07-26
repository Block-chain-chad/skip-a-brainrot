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
- **Architecture** (revised at implementation, 2026-07-25): bodies are
  generated as **server-side Models in `ServerStorage.BrainrotModels`**,
  consumed by the spawner's EXISTING authored-model path. Idle motion runs
  client-side on tagged models.

## Why the existing model path (architecture revision)

The spec originally proposed client-built bodies over invisible anchors, to
protect three integration points that assumed a brainrot is a single Part.
Reading the live code killed that premise: `BrainrotSpawner` already has a
complete authored-model path — "if ServerStorage.BrainrotModels holds a model
whose name matches the config entry, it is cloned" (its own header calls a
new model "a content drop, not a code change"), with height normalization,
base seating, Model-aware billboard/prompt/mutation-VFX — and `IncomeLoop` /
`BrainrotMover` find brainrots by the `PadIndex` ATTRIBUTE, not by class.
Secret Pete (47 parts, hand-authored, presumably the collaborator's) is live
proof. So we generate 213 Models into that folder at server start and change
ZERO battle-tested server code. Trade-off accepted vs. the client-side idea:
placed bodies replicate (~1,400 parts at full plots) — normal for the genre
and far cheaper than maintaining a parallel rendering path.

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

### 4. `ServerScriptService.BrainrotModelFactory` (new)
At server start: builds every BrainrotLooks recipe into a Model inside
`ServerStorage.BrainrotModels` (pcall per name — a bad recipe skips, never
blocks), SKIPPING names that already have hand-authored models (Secret Pete
must never be overwritten). Templates carry the CollectionService tag
"BrainrotBody" and a `Motion` attribute; clones inherit both. The existing
spawner then finds the templates naturally — no spawner changes.

### 5. `StarterPlayer.StarterPlayerScripts.BrainrotIdleClient` (new)
Client-side idle motion for models tagged "BrainrotBody": one Heartbeat loop
for all bodies, motion preset per the model's `Motion` attribute (bob / sway /
hover / spin / shiver / none), phases staggered by name-hash (never
math.random — looks must be stable), distance-gated beyond ~120 studs, and
capped at the nearest 80 bodies. Server parts are anchored, so client-local
CFrame writes never replicate back.

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

- **Body removed mid-animation** → animator cleanup is driven by the
  "BrainrotBody" tag-removed signal / AncestryChanged, never polled.
- **Player joins with plots already full** → animator starts from
  `CollectionService:GetTagged`, then listens for additions.
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
