# World 2 (Frozen Tundra) — upper-tier roster brief

**30 new brainrots** to fill the five empty Tundra tiers. Names, colours and all config
numbers are settled here; the only missing thing is the models.

**Nothing below is live yet.** Adding entries with no model would let a player catch a
brainrot that cannot render, so this stays a document until the art exists. Wiring it in
afterwards is a copy-paste of the block at the bottom plus one band change (see the end).

Tier shape is deliberately leaner than World 1 (which runs 22/20/15/11/2). Depth matters
much less than a tier simply *existing* — the bug that started this was empty tiers, not
thin ones. 30 also happens to match the 30-character pack size if you buy rather than build.

---

## The cash ladder, and why it starts at 75,000

World 1's Mythic tops out at **35,000/s** and is now the Tundra's *Rare*. World 1's Secret
tops at **66,000/s** and stays valley-exclusive.

So Tundra Epic has to open **above 66,000/s** — otherwise a mid-tier tundra catch out-earns
a valley Secret and the exclusivity you kept them for is worth nothing. It opens at 75,000.

The top (2,000,000/s) is the number to argue with. For scale: a full 12-pad camp of World
1's best is roughly 792,000/s; a full camp of Tundra Gods would be ~24,000,000/s, about
30x. That funds VoidHeart (the $2T rock) in ~23 hours of perfect play, which reads as a
real endgame rather than a wall. Move this if you want the grind longer or shorter — it is
one column and nothing else depends on it.

---

## EPIC — 10 · "frost oddities"

The tier where the tundra stops being a colder valley and starts being strange.

| # | Name | Cash/s | Weight | Colours / look |
|---|---|---|---|---|
| 1 | Pinguino Trombettino | 75,000 | 18182 | Tuxedo black & white, brass trumpet for a beak |
| 2 | Gelatoni Vulcanico | 80,000 | 16364 | Mint-green ice cream cone, magma-pink drip down one side |
| 3 | Slittino Bombardino | 86,000 | 14545 | Cherry-red sled, dark grey bomb payload, wooden runners |
| 4 | Morsa Baffuta | 92,000 | 12727 | Muddy brown hide, cream tusks, enormous walrus moustache |
| 5 | Fiocco Ballerino | 98,000 | 10909 | White crystal snowflake body, pale pink tutu |
| 6 | Termosino Fumante | 105,000 | 9091 | Steel-blue thermos, copper cap, white steam plume |
| 7 | Ghiacciolo Sbarazzino | 112,000 | 7273 | Electric-blue popsicle, bare wooden stick legs |
| 8 | Renna Discotecca | 119,000 | 5455 | Brown fur, mirrorball antlers, magenta glow |
| 9 | Iglu Mangione | 127,000 | 3636 | Packed-snow white blocks, dark cavernous mouth |
| 10 | Scarpone Saltellante | 135,000 | 1818 | Mustard leather boot, red laces, steel crampon teeth |

## LEGENDARY — 8 · "the deep freeze"

Bigger, colder, less funny. The tier should start to feel dangerous.

| # | Name | Cash/s | Weight | Colours / look |
|---|---|---|---|---|
| 11 | Orso Frigorifero | 150,000 | 22222 | White enamel fridge body, chrome handle, black bear nose |
| 12 | Tricheco Sommozzatore | 163,000 | 19444 | Slate hide, yellow scuba tank, round glass mask |
| 13 | Valanga Ruggente | 176,000 | 16667 | Churning white and grey, ice-blue shadow in the folds |
| 14 | Yeti Cappuccino | 190,000 | 13889 | Cream foam fur, espresso-brown streaks, sugar-white flecks |
| 15 | Aurora Serpentina | 205,000 | 11111 | Translucent, green-to-violet gradient, faint glow |
| 16 | Pattinatore Fantasma | 221,000 | 8333 | Pale translucent blue, silver skate blades, no face |
| 17 | Mammuto Lanoso | 240,000 | 5556 | Rust-orange wool, ivory tusks, frost on the shoulders |
| 18 | Nave Rompighiaccio | 265,000 | 2778 | Red hull, black smokestack, white ice spray at the bow |

## MYTHIC — 6 · "the frozen court"

Regal. These should look like they own the place.

| # | Name | Cash/s | Weight | Colours / look |
|---|---|---|---|---|
| 19 | Regina Brinata | 300,000 | 28571 | Deep sapphire gown, silver crown, white hair |
| 20 | Colosso Glaciale | 335,000 | 23810 | Blue-white ice slabs, deep crevasse cracks |
| 21 | Balena Polare | 375,000 | 19048 | Pearl white, pale blue underbelly, frost breath |
| 22 | Cristallo Vivente | 420,000 | 14286 | Clear prismatic crystal, rainbow refraction |
| 23 | Lupo Tempesta | 475,000 | 9524 | Charcoal fur, lightning-white eyes, static-blue crackle |
| 24 | Trono Ghiacciato | 540,000 | 4761 | Deep glacial blue throne, gold inlay, empty seat |

## SECRET — 4 · "beneath the ice"

Only four. They should feel like something that was buried on purpose.

| # | Name | Cash/s | Weight | Colours / look |
|---|---|---|---|---|
| 25 | Kraken Congelato | 650,000 | 40000 | Abyssal teal, frost-rimed tentacles, one pale eye |
| 26 | Cuore della Tundra | 740,000 | 30000 | Molten gold core inside a blue ice shell |
| 27 | Ombra Bianca | 850,000 | 20000 | Pure white silhouette, void-black eye sockets |
| 28 | Titano Sepolto | 1,000,000 | 10000 | Ancient grey stone, blue glacial veins, moss at the joints |

## GOD — 2 · "the two that made the cold"

| # | Name | Cash/s | Weight | Colours / look |
|---|---|---|---|---|
| 29 | Inverno Eterno | 1,400,000 | 66667 | Swirling white and silver, star-flecked, no fixed edge |
| 30 | Zero Assoluto | 2,000,000 | 33333 | Matte void black, hairline white frost fractures |

---

## Notes for modelling

- **Name the model EXACTLY as the Name column**, drop it in `ReplicatedStorage.BrainrotModels`,
  and icons appear everywhere for free — bag, index, reveal, trade — because `BrainrotThumb`
  renders the model itself in a ViewportFrame. No icon art, no uploads.
- Size does not matter: `BrainrotSpawner` normalises every model to 6 studs on spawn.
- Parts are fine. Nothing here needs to be a mesh — 10 of your existing brainrots are
  plain Parts rebuilt from voxel data, and they render identically.
- Avoid recycled prefix/suffix naming. The 67 placeholders failed partly because
  "Glacini Orsetto" / "Glacini Trichecco" / "Glacini Lupetto" read as one creature three
  times. Every name above is its own character.

## Wiring it in, when the models exist

1. Paste the rows into `ReplicatedStorage.Modules.BrainrotConfigTundra` in the existing
   format: `{ Name = "...", Rarity = "...", CashPerSecond = N, Weight = N },`
   Weights already sum to exactly 100000 per tier.
2. **Re-spread all eight bands across 0..900** in `RarityConfigTundra`. The five upper tiers
   are currently PARKED at MinDistance 9000+ so they cannot be rolled while empty. Leaving
   them parked makes this content unreachable; leaving Common/Uncommon/Rare stretched over
   0-300-600-900 makes it trivial. Both halves move together.
   A sensible eight-tier spread: 0 / 110 / 220 / 340 / 460 / 580 / 700 / 820.
3. Nothing else changes. No new reward Kind, no code edits, no Index edits — though note the
   Index is still World-1 only, so these will not appear there until it is made world-aware.
