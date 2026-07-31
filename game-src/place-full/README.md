# place-full — complete script export

Every `LuaSourceContainer` in the live place, exported 2026-08-01 and verified
byte-identical against Studio.

- **Place:** 78783087742939 (universe 10549950910), PlaceVersion 798
- **Experience owner:** UserId 1583162960 (BigFrogTerryBruh) — note this is *not*
  the `prohacks_sorry` account Studio logs in as, so Team Create access here can
  be revoked by someone else. That is the reason this export exists.
- **Coverage:** 181/181 scripts, all hash-verified.

## Layout

Path mirrors the DataModel; the class is encoded in the extension so the tree
can be reconstructed unambiguously.

| extension     | class         |
|---------------|---------------|
| `.lua`        | ModuleScript  |
| `.server.lua` | Script        |
| `.client.lua` | LocalScript   |

## `_MANIFEST.txt` — tamper tripwire

`hash|bytes|class|path`, one line per script. The hash is
`h = (h * 31 + byte) mod 2^32`, seeded 5381.

Deliberately **not** FNV-1a: FNV's 16777619 multiplier pushes the intermediate
product past 2^53, and Lua numbers are doubles, so a Luau FNV implementation
silently loses precision and disagrees with every other language's. Multiplier
31 keeps `h * 31` inside the mantissa, so Studio and Python agree exactly.

Re-run the export later and diff `_MANIFEST.txt` to see precisely which scripts
changed, without needing to read any of them.

## What this does NOT cover

Scripts only. **Models, terrain, the built world, and GUI instances authored in
StarterGui are not here** — including `ReplicatedStorage.BrainrotModels` (160
models) and the egg models, which cannot be reconstructed from source.

For those, use Studio's **File → Save to File As…** and keep a `.rbxl`/`.rbxlx`
somewhere off Roblox. That is the only complete restore point.
