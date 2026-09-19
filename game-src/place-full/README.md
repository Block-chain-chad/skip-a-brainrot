# place-full — complete script export

Every `LuaSourceContainer` in the live place, mirrored **byte-for-byte** from the
Studio `Source` property. First exported 2026-08-01 (181 scripts); fully
re-synced 2026-09-19 against PlaceVersion 2353 — see `docs/SOURCE-SYNC-AUDIT.md`
for the audit, the method, and the exceptions open at that time.

- **Place:** 78783087742939 (universe 10549950910)
- **Experience owner:** UserId 1583162960 (BigFrogTerryBruh) — note this is *not*
  the `prohacks_sorry` account Studio logs in as, so Team Create access here can
  be revoked by someone else. That is the reason this export exists.
- **Coverage at the 2026-09-19 sync:** 493 mirror files; 490 of the 496 live
  scripts byte-identical. The 6 exceptions were the round-3 quest / dialogue /
  prompt scripts another session was editing at that moment (listed in the audit);
  they are synced by that work when it lands.

## Team rule — GitHub is canonical for Lua

> Any task that creates or changes a Script, LocalScript, or ModuleScript in live
> Roblox Studio is **not complete** until the corresponding file under
> `game-src/place-full/` is updated and committed.

- Push the file *from Studio* with `tools/studio-bridge/bridge.py` (byte-exact).
  Never retype or reformat a mirror file by hand, and never "clean up" what Studio
  holds — the mirror is a copy, not a style pass.
- Regenerate `_MANIFEST.txt` with the same change (see below).
- Code written against the mirror on disk is not live until it has been applied in
  Studio *and* pushed back — an edited mirror file alone is drift in the other
  direction.
- Studio is where the code runs; GitHub is where it lives.

## Layout

Path mirrors the DataModel; the class is encoded in the extension so the tree
can be reconstructed unambiguously.

| extension     | class         |
|---------------|---------------|
| `.lua`        | ModuleScript  |
| `.server.lua` | Script        |
| `.client.lua` | LocalScript   |

Instance names that cannot be a Windows filename component — `< > : " / \ | ? *`,
control characters, a trailing `.` or space — and `%` itself are percent-encoded
per path component, e.g. `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.`
`ReplicatedStorage|Modules|BrainrotConfig` is stored as
`ServerStorage/AuditBackups/PreEmeraldRename_2026_08_15/ReplicatedStorage%7CModules%7CBrainrotConfig.lua`.
The encoding is reversible; `_MANIFEST.txt` carries the decoded (real) names.

Only `Source` is mirrored. `Enabled`, `RunContext` and other properties are not
(e.g. `StarterPlayer.StarterPlayerScripts.DailyRewardClient` is disabled live and
`Workspace.TitleScaler` is a `Script` with `RunContext = Client`); a rebuild from
this tree would have to restore those by hand.

## `_MANIFEST.txt` — tamper tripwire

`hash|bytes|class|path`, one line per script, sorted by path. The hash is
`h = (h * 31 + byte) mod 2^32`, seeded 5381, printed as 8 hex digits; `bytes` is
the file size, which equals `#Source` in Studio.

Deliberately **not** FNV-1a: FNV's 16777619 multiplier pushes the intermediate
product past 2^53, and Lua numbers are doubles, so a Luau FNV implementation
silently loses precision and disagrees with every other language's. Multiplier
31 keeps `h * 31` inside the mantissa, so Studio and Python agree exactly.

Re-run the export later and diff `_MANIFEST.txt` to see precisely which scripts
changed, without needing to read any of them.

## Line endings

`.gitattributes` here marks `*.lua` and `_MANIFEST.txt` as `-text`: git never
converts line endings for the mirror on any platform, so the committed blob, the
checked-out file and the Studio `Source` are the same bytes. (Without it,
`core.autocrlf=true` on Windows stripped CRs on commit and wrote CRLF on
checkout, and "byte-identical" was silently false on every fresh clone.)

## What this does NOT cover

Scripts only. **Models, terrain, the built world, and GUI instances authored in
StarterGui are not here** — including `ReplicatedStorage.BrainrotModels` (160
models) and the egg models, which cannot be reconstructed from source.

For those, use Studio's **File → Save to File As…** and keep a `.rbxl`/`.rbxlx`
somewhere off Roblox. That is the only complete restore point.
