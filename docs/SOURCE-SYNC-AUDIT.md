# Source sync audit — live Studio vs `game-src/place-full/`

**Owner:** Balkan · **Audit run:** 2026-09-18 23:09 (America/Phoenix) = 2026-09-19 06:09 UTC · **Status: audit (§0–§10) approved by Balkan 2026-09-18 23:2x; sync executed on branch `source-sync-audit` — result in §11. Nothing in Studio was changed.**

Scope is `LuaSourceContainer`s only (Script / LocalScript / ModuleScript). This is a source-sync / completeness audit, not a full-place backup — see §10. §0–§10 are the pre-sync audit as shown to Balkan; §11 records what was then done.

## 0. Read this first

| | |
|---|---|
| Live place | `78783087742939` (universe `10549950910`), PlaceVersion **2353**, Studio in **Edit** mode at snapshot time |
| Live LuaSourceContainers | **488** (ReplicatedStorage 103, ServerScriptService 71, StarterPlayer 86, StarterGui 1, Workspace 3, ServerStorage **224**) |
| Repo mirror files | **244** tracked at `HEAD` (`ui-foundation` @ `3e0275b`); 248 in the working tree (4 untracked); 230 on `origin/ui-foundation` (`4c52187`); **0** on `origin/master` (the mirror only exists on the `ui-foundation` lineage) |
| `_MANIFEST.txt` | 181 entries, generated 2026-08-01 — stale (§7) |
| IDENTICAL | **165** |
| DIFFERENT | **74** |
| MISSING FROM REPO | **247** (77 game scripts + 170 under `ServerStorage`) |
| REPO ONLY / STALE | **3** |
| CLASS MISMATCH | **0** |
| PATH MISMATCH | **2** (byte-identical code mirrored under a flattened filename) |

**Bottom line:** the mirror is far behind the live place. Only 165 of 488 live scripts are byte-identical to their mirror; 74 mirrored scripts have drifted (several by 10–30 KB), and 247 live scripts have no mirror at all (plus 2 mirrored under the wrong path) — 77 of them are real game code (`Platform`, `HudLayout`, `EmeraldService`, `StealService`, `PlotEquipPad`, the whole Tundra/Gardens atmosphere client set, …), the other 170 are `ServerStorage` build tools and `AuditBackups` pre-edit copies (which the 2026-08-01 export *did* include, so by the repo's own convention they count).

### Blockers / decisions needed before any sync

1. **Another session is live on this checkout right now.** During the audit Studio flipped Edit → Play three times, and round-3 files (`QuestCard`, `InteractionPrompt`, `InteractionPromptClient`, `MerchantDialog`, `QuestBarClient`, `QuestTrackerClient`) were pushed to `game-src/place-full/` and `tools/studio-bridge/round3/` at 22:55–23:10, i.e. while this report was being built. `QuestTrackerClient` changed live between my two reads (27,403 B → 27,923 B). The round-3 scope (quests, dialogue, prompts — see `docs/ROUND3-QUEST-INTERACTION-AUDIT.md`) is therefore **in flight**; those rows are marked ⚡ below and should be synced last, after round 3 lands, or by that session itself.
2. **Branch.** `ui-foundation` is 15 commits ahead of `origin/ui-foundation` and carries all previous `chore(mirror): re-sync …` commits; `master` predates the mirror by 141 commits. The working tree is dirty (8 modified + 4 untracked mirror files, §3). Proposal: branch `source-sync-audit` from `ui-foundation` @ `3e0275b`, worked in a **separate git worktree** so the round-3 checkout is never touched. Pushing it will carry the 15 unpushed `ui-foundation` commits as ancestors — say if that is not acceptable.
3. **Six-week-old uncommitted hand patches on disk** (Aug 4 / Aug 9) to `DarrelService`, `PlayerDataManager`, `ProductRegistry`, `SettingsPanel` were never applied to Studio and match neither HEAD nor live; `DarrelService` no longer exists live (renamed to `EmeraldService` on 2026-08-15). A sync would overwrite them. Keep (move to a patch file / branch), or discard?
4. **`ServerStorage` scope.** 170 unmirrored scripts: 7 build/dev modules, 22 `GardensBuild` world-builder modules, 141 `AuditBackups` pre-edit copies. The original export included backups. Mirror all (convention), or exclude `AuditBackups` going forward (and document it)?
5. **59 backup scripts have `|` in their instance name** (`ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ReplicatedStorage|Modules|BrainrotConfig` etc.). `|` is illegal in Windows filenames, so they cannot be mirrored with the exact name. Options: encode `|` as `%7C` (documented, reversible), or skip those two backup folders.
6. **Line endings.** `core.autocrlf=true` and no `.gitattributes`. Three live scripts contain CR characters (`MerchantDialog` 878, `QuestTrackerClient` 648, `QuestBarClient` 416). Git will normalise CRLF→LF on commit, so the committed blob will *not* be byte-identical to Studio for those, and any fresh Windows checkout gets CRLF for *every* file. Proposal: add `.gitattributes` with `*.lua -text` (store bytes verbatim, no conversion) — needs approval because it is a repo-wide policy.
7. **Path-mismatch fix** for the two Workspace scripts (`git mv` to folder layout) and the two renamed Darrel→Emerald files (delete the stale `Darrel*` mirrors, add `Emerald*`) — both are deletions, so explicit approval per §6/§7 of the brief.

## 1. Method

**Live side** — one `execute_luau` chunk in the Edit DataModel walked `game:GetChildren()` → `GetDescendants()` (every service, none errored) and recorded for each `LuaSourceContainer`: the full name path (as an array, so names containing `.` or `|` are unambiguous), ClassName, `#Source` (bytes), the repo's documented hash `h = (h*31 + byte) mod 2^32, seed 5381` (`game-src/place-full/README.md`), count of `\r` bytes, `Enabled` and `RunContext` for BaseScripts, `Archivable`, and whether `ScriptEditorService:GetEditorSource()` differs from `Source` (unsaved editor text). The 70 KB result was POSTed to a private local HTTP bridge (port 8732, writes only into a temp folder) using the same `HttpEnabled` flip-and-restore pattern documented in `tools/studio-bridge/bridge.py`; `HttpEnabled` was confirmed back to `false` afterwards.

**Repo side** — every `*.lua` under `game-src/place-full/` at `HEAD` (via `git ls-tree`/`cat-file`, i.e. the blob bytes), in the working tree, and at `origin/ui-foundation`; extension → class per the README (`.lua` ModuleScript, `.server.lua` Script, `.client.lua` LocalScript); directory path → DataModel path.

**IDENTICAL** = same path, same class, same 32-bit hash **and** same byte count. Validation: the 8 mirror files the round-3 session pushed byte-exact from Studio in the last hour (including the three CR-bearing ones) match the live hash+size in this snapshot, so the Luau and Python hash implementations agree on real data.

## 2. Counts

Per service, live vs `HEAD` (`3e0275b`):

| Service | live | IDENTICAL | DIFFERENT | MISSING FROM REPO | REPO ONLY | notes |
|---|---:|---:|---:|---:|---:|---|
| ReplicatedStorage | 103 | 54 | 23 | 26 | 0 |  |
| ServerScriptService | 71 | 21 | 29 | 21 | 1 | REPO ONLY = DarrelService (renamed live → EmeraldService) |
| StarterPlayer | 86 | 35 | 22 | 29 | 1 | REPO ONLY = DarrelHUDClient (renamed live → EmeraldHUDClient) |
| StarterGui | 1 | 0 | 0 | 1 | 1 | REPO ONLY = hello-world template junk, moved live into AuditBackups |
| Workspace | 3 | 1 | 0 | 2 | 2 | 2 × PATH MISMATCH counted as MISSING + REPO ONLY here |
| ServerStorage | 224 | 54 | 0 | 170 | 0 | 170 missing = 7 top-level + 22 GardensBuild + 141 AuditBackups |
| **total** | **488** | **165** | **74** | **249** | **5** | |

Against other refs (same live snapshot):

| compared to | mirror files | IDENTICAL | DIFFERENT | MISSING FROM REPO | REPO ONLY |
|---|---:|---:|---:|---:|---:|
| `HEAD` = local `ui-foundation` @ `3e0275b` | 244 | 165 | 74 | 249 | 5 |
| working tree (dirty) | 248 | 173 | 70 | 245 | 5 |
| `origin/ui-foundation` @ `4c52187` (what GitHub has) | 230 | 131 | 94 | 263 | 5 |
| `origin/master` @ `0cc37d0` | 0 | 0 | 0 | 488 | 0 |

Live source volume: 12.40 MB total, 4.69 MB excluding `ServerStorage`.

## 3. Branch and working-tree state

```
branch: ui-foundation @ 3e0275b   (origin/ui-foundation: 4c52187, local is 15 ahead, 0 behind)
master: 0cc37d0 = merge-base; ui-foundation is 141 commits ahead of master; master has no game-src/place-full/
worktrees: none;  .gitignore: none;  core.autocrlf=true;  .gitattributes: none
```

Uncommitted changes touching the mirror (at 23:12):

| file | state | what it is | vs live |
|---|---|---|---|
| `ReplicatedStorage/Modules/MerchantDialog.lua` | modified 23:03 | ⚡ round-3 bridge push | = live (at snapshot) |
| `StarterPlayer/StarterPlayerScripts/QuestBarClient.client.lua` | modified 23:08 | ⚡ round-3 bridge push | = live |
| `StarterPlayer/StarterPlayerScripts/QuestTrackerClient.client.lua` | modified 23:10 | ⚡ round-3 bridge push | live changed again after snapshot |
| `ReplicatedStorage/Modules/UIKit/QuestCard.lua` | untracked 22:55 | ⚡ round-3 bridge push | = live |
| `ReplicatedStorage/Modules/UIKit/InteractionPrompt.lua` | untracked 23:01 | ⚡ round-3 bridge push | = live |
| `StarterPlayer/StarterPlayerScripts/InteractionPromptClient.client.lua` | untracked 23:01 | ⚡ round-3 bridge push | = live |
| `ServerScriptService/Modules/SessionLock.lua` | untracked | earlier bridge push | = live |
| `ServerScriptService/Modules/SettingsService.lua` | modified 2026-08-09 | on-disk edit, never committed | = live |
| `ServerScriptService/Modules/DarrelService.lua` | modified 2026-08-04 | hand patch on disk (receipt money invariant) | **file no longer exists live** |
| `ServerScriptService/Modules/PlayerDataManager.lua` | modified 2026-08-04 | hand patch on disk (+164 lines) | ≠ live, ≠ HEAD |
| `ServerScriptService/Modules/ProductRegistry.lua` | modified 2026-08-04 | hand patch on disk (receipt pcall) | ≠ live, ≠ HEAD |
| `StarterPlayer/StarterPlayerScripts/GameHUDPanels/SettingsPanel.lua` | modified 2026-08-09 | hand patch on disk | ≠ live, ≠ HEAD |

The last four are the drift the brief is about, in the other direction: code written against the mirror that never reached Studio. They are not touched by this audit; Balkan decides (§0 item 3).

## 4. Every non-identical entry

Legend: ⚡ = round-3 in-flight scope (another session is editing this right now). Byte counts are `#Source`.

### 4.1 DIFFERENT — 74 scripts (same path & class, source differs)

| # | DataModel path | class | live bytes / hash | HEAD bytes / hash | Δ bytes | note |
|--:|---|---|---|---|---:|---|
| 1 | `ReplicatedStorage.Modules.BrainrotBodyBuilder` | ModuleScript | 50,771 / `e9b3ea5c` | 48,282 / `806ef56c` | +2,489 |  |
| 2 | `ReplicatedStorage.Modules.BrainrotConfig` | ModuleScript | 24,628 / `b94b12a3` | 20,432 / `418be44b` | +4,196 |  |
| 3 | `ReplicatedStorage.Modules.BrainrotWaves` | ModuleScript | 2,518 / `b4720b2e` | 2,263 / `1e22e461` | +255 |  |
| 4 | `ReplicatedStorage.Modules.EggConfig` | ModuleScript | 12,288 / `0939bdad` | 3,137 / `61ef8717` | +9,151 |  |
| 5 | `ReplicatedStorage.Modules.GamepassConfig` | ModuleScript | 8,211 / `93eab534` | 2,802 / `8cf2ab10` | +5,409 |  |
| 6 | `ReplicatedStorage.Modules.IconForge` | ModuleScript | 20,153 / `bd9c02a7` | 12,860 / `bd7a9075` | +7,293 |  |
| 7 | `ReplicatedStorage.Modules.MerchantConfig` | ModuleScript | 4,762 / `d141ac65` | 1,890 / `92bf0fab` | +2,872 |  |
| 8 | `ReplicatedStorage.Modules.MerchantDialog` | ModuleScript | 37,388 / `ce3a572c` | 35,270 / `2c39a10d` | +2,118 | ⚡; working tree already = live (uncommitted); live has 878 CR bytes |
| 9 | `ReplicatedStorage.Modules.MutationConfig` | ModuleScript | 8,848 / `82e1a34a` | 8,145 / `46bf9749` | +703 |  |
| 10 | `ReplicatedStorage.Modules.MutationFX` | ModuleScript | 48,035 / `5a806e66` | 4,829 / `5de7e885` | +43,206 |  |
| 11 | `ReplicatedStorage.Modules.NumberFormat` | ModuleScript | 2,685 / `9704db44` | 2,377 / `03252a49` | +308 |  |
| 12 | `ReplicatedStorage.Modules.PetConfig` | ModuleScript | 41,329 / `4889398d` | 7,350 / `a6047409` | +33,979 |  |
| 13 | `ReplicatedStorage.Modules.RarityCurve` | ModuleScript | 7,659 / `6e7a290a` | 2,975 / `d21019fd` | +4,684 |  |
| 14 | `ReplicatedStorage.Modules.RebirthConfig` | ModuleScript | 2,082 / `ca5f7f18` | 2,153 / `0d9c6d7c` | -71 |  |
| 15 | `ReplicatedStorage.Modules.RockConfig` | ModuleScript | 7,924 / `fe335fed` | 6,513 / `780f3778` | +1,411 |  |
| 16 | `ReplicatedStorage.Modules.RockDesign` | ModuleScript | 29,525 / `26e8ccfb` | 9,416 / `c70b5126` | +20,109 |  |
| 17 | `ReplicatedStorage.Modules.SeasonConfig` | ModuleScript | 19,531 / `1321b0bc` | 1,980 / `3e6df348` | +17,551 |  |
| 18 | `ReplicatedStorage.Modules.SoundKit` | ModuleScript | 22,464 / `348b3c60` | 20,094 / `5c718b8d` | +2,370 |  |
| 19 | `ReplicatedStorage.Modules.UIKit.IconArt` | ModuleScript | 50,270 / `060561d3` | 32,557 / `69205183` | +17,713 |  |
| 20 | `ReplicatedStorage.Modules.UIKit.Tokens` | ModuleScript | 18,367 / `f365ee40` | 16,220 / `d7575210` | +2,147 |  |
| 21 | `ReplicatedStorage.Modules.UIStyle` | ModuleScript | 25,188 / `686cedf8` | 24,087 / `2d173e3a` | +1,101 |  |
| 22 | `ReplicatedStorage.Modules.UITheme` | ModuleScript | 42,357 / `fcaf3a49` | 39,304 / `069fca81` | +3,053 |  |
| 23 | `ReplicatedStorage.Modules.UpgradeConfig` | ModuleScript | 7,708 / `85af0081` | 3,819 / `55b56b74` | +3,889 |  |
| 24 | `ServerScriptService.CellarDoor` | Script | 7,780 / `b4048982` | 4,241 / `f15acc29` | +3,539 |  |
| 25 | `ServerScriptService.EggStallIdle` | Script | 13,694 / `71cf8771` | 12,396 / `4a8c4f3f` | +1,298 |  |
| 26 | `ServerScriptService.Main` | Script | 12,193 / `aaeb3c06` | 6,852 / `65b9441f` | +5,341 |  |
| 27 | `ServerScriptService.Modules.BoothHandler` | ModuleScript | 20,288 / `f95dbd9f` | 17,593 / `7e87ef3f` | +2,695 |  |
| 28 | `ServerScriptService.Modules.BoundsGuard` | ModuleScript | 7,566 / `e45e2980` | 6,450 / `2f7be72b` | +1,116 |  |
| 29 | `ServerScriptService.Modules.BrainrotMover` | ModuleScript | 6,910 / `865aafef` | 5,477 / `0097bba0` | +1,433 |  |
| 30 | `ServerScriptService.Modules.BrainrotSpawner` | ModuleScript | 23,296 / `4caa228a` | 12,764 / `1ccc4b0a` | +10,532 |  |
| 31 | `ServerScriptService.Modules.DailyRewardHandler` | ModuleScript | 7,751 / `b3a647e6` | 4,571 / `01bb0388` | +3,180 |  |
| 32 | `ServerScriptService.Modules.EggHandler` | ModuleScript | 11,133 / `e0718947` | 5,676 / `0bb5d94c` | +5,457 |  |
| 33 | `ServerScriptService.Modules.FusionHandler` | ModuleScript | 6,342 / `ebdef59c` | 6,007 / `1a0bec95` | +335 |  |
| 34 | `ServerScriptService.Modules.GamepassService` | ModuleScript | 8,358 / `b902bc57` | 4,163 / `f4ce7215` | +4,195 |  |
| 35 | `ServerScriptService.Modules.IncomeLoop` | ModuleScript | 12,323 / `d5c3b6af` | 8,213 / `407accca` | +4,110 |  |
| 36 | `ServerScriptService.Modules.InventoryHandler` | ModuleScript | 19,274 / `ad043a77` | 16,429 / `f9e3644b` | +2,845 |  |
| 37 | `ServerScriptService.Modules.LeaderboardBoards` | ModuleScript | 18,641 / `9f011e11` | 13,399 / `b18cc843` | +5,242 |  |
| 38 | `ServerScriptService.Modules.PetHandler` | ModuleScript | 30,268 / `ba8255b8` | 20,797 / `cbdd0a4b` | +9,471 |  |
| 39 | `ServerScriptService.Modules.PlayerDataManager` | ModuleScript | 51,669 / `7f09e949` | 34,189 / `d0273cb0` | +17,480 | 2026-08-04 hand patch on disk (+164 lines); matches neither HEAD nor live |
| 40 | `ServerScriptService.Modules.PlotBoardHandler` | ModuleScript | 16,601 / `5ff7096c` | 15,684 / `70ae7969` | +917 |  |
| 41 | `ServerScriptService.Modules.ProductRegistry` | ModuleScript | 5,735 / `389fe421` | 3,008 / `46421c88` | +2,727 | 2026-08-04 hand patch on disk (receipt pcall); matches neither HEAD nor live |
| 42 | `ServerScriptService.Modules.RarityRoll` | ModuleScript | 8,134 / `21ae61fc` | 5,324 / `5c4ff130` | +2,810 |  |
| 43 | `ServerScriptService.Modules.RebirthHandler` | ModuleScript | 3,144 / `3a9cd541` | 3,014 / `04ba9a31` | +130 |  |
| 44 | `ServerScriptService.Modules.SeasonPassHandler` | ModuleScript | 24,267 / `ead1e68c` | 3,554 / `b6f30e23` | +20,713 |  |
| 45 | `ServerScriptService.Modules.SellHandler` | ModuleScript | 7,798 / `324c2830` | 4,281 / `6addd955` | +3,517 |  |
| 46 | `ServerScriptService.Modules.SettingsService` | ModuleScript | 10,269 / `e0b8bc08` | 6,981 / `7f869c0b` | +3,288 | 2026-08-09 on-disk edit; IS byte-identical to live (never committed) |
| 47 | `ServerScriptService.Modules.ShopHandler` | ModuleScript | 5,724 / `aef9c5e2` | 2,360 / `b6274c82` | +3,364 |  |
| 48 | `ServerScriptService.Modules.TradeHandler` | ModuleScript | 19,566 / `0429f8d4` | 18,283 / `814497d5` | +1,283 |  |
| 49 | `ServerScriptService.Modules.WeatherHandler` | ModuleScript | 7,261 / `eeef267b` | 7,005 / `28f78d4a` | +256 |  |
| 50 | `ServerScriptService.Modules.WheelBoard` | ModuleScript | 24,197 / `9429ab2d` | 17,221 / `3fe71320` | +6,976 |  |
| 51 | `ServerScriptService.Modules.WheelHandler` | ModuleScript | 16,101 / `c847d65d` | 6,572 / `8f78802f` | +9,529 |  |
| 52 | `ServerScriptService.TeleportService` | Script | 26,676 / `2e6cb107` | 19,214 / `55ce8ca7` | +7,462 |  |
| 53 | `StarterPlayer.StarterPlayerScripts.BackpackClient` | LocalScript | 294 / `375554a5` | 27,554 / `1112a388` | -27,260 | live is a stub (old code kept in `ServerStorage.AuditBackups.*_pre_invrework`) |
| 54 | `StarterPlayer.StarterPlayerScripts.BoothClient` | LocalScript | 28,403 / `52c720f7` | 27,300 / `c7f1de83` | +1,103 |  |
| 55 | `StarterPlayer.StarterPlayerScripts.BrainrotHoldClient` | LocalScript | 200 / `c0db0b98` | 3,363 / `8882e0df` | -3,163 | live is a stub (old code kept in `ServerStorage.AuditBackups.*_pre_invrework`) |
| 56 | `StarterPlayer.StarterPlayerScripts.BrainrotIdleClient` | LocalScript | 19,152 / `6c4266af` | 11,255 / `0528f169` | +7,897 |  |
| 57 | `StarterPlayer.StarterPlayerScripts.BrainrotPlaceClient` | LocalScript | 280 / `2ad89da3` | 4,725 / `bb72da42` | -4,445 | live is a stub (old code kept in `ServerStorage.AuditBackups.*_pre_invrework`) |
| 58 | `StarterPlayer.StarterPlayerScripts.CampfireBankClient` | LocalScript | 24,054 / `3647e1ee` | 23,390 / `edee066e` | +664 |  |
| 59 | `StarterPlayer.StarterPlayerScripts.DailyRewardClient` | LocalScript | 10,077 / `5f710b0c` | 9,578 / `29f1a345` | +499 | **live Enabled=false** |
| 60 | `StarterPlayer.StarterPlayerScripts.FusionClient` | LocalScript | 20,746 / `30a8fb65` | 19,677 / `4d5a965c` | +1,069 |  |
| 61 | `StarterPlayer.StarterPlayerScripts.GameHUDPanels.DailyPanel` | ModuleScript | 42,780 / `81ff4275` | 36,342 / `08506b6f` | +6,438 |  |
| 62 | `StarterPlayer.StarterPlayerScripts.GameHUDPanels.SettingsPanel` | ModuleScript | 33,390 / `072ca21e` | 51,054 / `b71de8cf` | -17,664 | 2026-08-09 hand patch on disk; matches neither HEAD nor live |
| 63 | `StarterPlayer.StarterPlayerScripts.InventoryClient` | LocalScript | 257 / `6f847d12` | 724 / `05f7695e` | -467 |  |
| 64 | `StarterPlayer.StarterPlayerScripts.OfflineEarningsClient` | LocalScript | 14,392 / `96f65ab7` | 3,716 / `59358469` | +10,676 |  |
| 65 | `StarterPlayer.StarterPlayerScripts.PityThrowClient` | LocalScript | 2,980 / `d2de4f4b` | 2,607 / `a8230f34` | +373 |  |
| 66 | `StarterPlayer.StarterPlayerScripts.QuestBarClient` | LocalScript | 19,340 / `af16e0a8` | 19,762 / `86487ef9` | -422 | ⚡; working tree already = live (uncommitted); live has 416 CR bytes |
| 67 | `StarterPlayer.StarterPlayerScripts.QuestTrackerClient` | LocalScript | 27,403 / `8965d0d6` | 59,456 / `1e8a8c17` | -32,053 | ⚡; working tree already = live (uncommitted); live has 648 CR bytes |
| 68 | `StarterPlayer.StarterPlayerScripts.RareCatchClient` | LocalScript | 10,977 / `2ef715b5` | 9,472 / `7ecc07c3` | +1,505 |  |
| 69 | `StarterPlayer.StarterPlayerScripts.RebirthClient` | LocalScript | 17,743 / `6617ff73` | 13,107 / `baf5be63` | +4,636 |  |
| 70 | `StarterPlayer.StarterPlayerScripts.SeasonClient` | LocalScript | 12,596 / `6329001b` | 12,159 / `6ec7d8b8` | +437 |  |
| 71 | `StarterPlayer.StarterPlayerScripts.TradeClient` | LocalScript | 33,232 / `7edf18ca` | 30,596 / `2c95b071` | +2,636 |  |
| 72 | `StarterPlayer.StarterPlayerScripts.TutorialClient` | LocalScript | 30,021 / `3691c3b9` | 9,873 / `e14f45f0` | +20,148 |  |
| 73 | `StarterPlayer.StarterPlayerScripts.UIPolish` | LocalScript | 13,366 / `3ed9d260` | 8,340 / `cf0df599` | +5,026 |  |
| 74 | `StarterPlayer.StarterPlayerScripts.WheelClient` | LocalScript | 79,643 / `776d74ed` | 48,911 / `6a0566c5` | +30,732 |  |

### 4.2 MISSING FROM REPO — 77 game scripts (outside `ServerStorage`)

| # | DataModel path | class | live bytes / hash | would be written to | note |
|--:|---|---|---|---|---|
| 1 | `ReplicatedStorage.Modules.BagConfig` | ModuleScript | 6,387 / `7ef6c502` | `game-src/place-full/ReplicatedStorage/Modules/BagConfig.lua` |  |
| 2 | `ReplicatedStorage.Modules.BrainrotFX` | ModuleScript | 20,088 / `0fd4e339` | `game-src/place-full/ReplicatedStorage/Modules/BrainrotFX.lua` |  |
| 3 | `ReplicatedStorage.Modules.CatchCue` | ModuleScript | 3,356 / `73bfdcd1` | `game-src/place-full/ReplicatedStorage/Modules/CatchCue.lua` |  |
| 4 | `ReplicatedStorage.Modules.CharmConfig` | ModuleScript | 31,081 / `2869546d` | `game-src/place-full/ReplicatedStorage/Modules/CharmConfig.lua` |  |
| 5 | `ReplicatedStorage.Modules.DailyRewardConfig` | ModuleScript | 6,384 / `b7cf4943` | `game-src/place-full/ReplicatedStorage/Modules/DailyRewardConfig.lua` |  |
| 6 | `ReplicatedStorage.Modules.EggPalettes` | ModuleScript | 3,194 / `483ae53c` | `game-src/place-full/ReplicatedStorage/Modules/EggPalettes.lua` |  |
| 7 | `ReplicatedStorage.Modules.GamepadHint` | ModuleScript | 4,056 / `e6115dc3` | `game-src/place-full/ReplicatedStorage/Modules/GamepadHint.lua` |  |
| 8 | `ReplicatedStorage.Modules.HudAudit` | ModuleScript | 35,787 / `3516657c` | `game-src/place-full/ReplicatedStorage/Modules/HudAudit.lua` |  |
| 9 | `ReplicatedStorage.Modules.HudLayout` | ModuleScript | 48,703 / `a77af6c0` | `game-src/place-full/ReplicatedStorage/Modules/HudLayout.lua` |  |
| 10 | `ReplicatedStorage.Modules.IceFishingConfig` | ModuleScript | 25,996 / `2d5971fb` | `game-src/place-full/ReplicatedStorage/Modules/IceFishingConfig.lua` |  |
| 11 | `ReplicatedStorage.Modules.MutationSkin` | ModuleScript | 32,798 / `09a3abbf` | `game-src/place-full/ReplicatedStorage/Modules/MutationSkin.lua` |  |
| 12 | `ReplicatedStorage.Modules.MutationVisuals` | ModuleScript | 23,976 / `6388fe2e` | `game-src/place-full/ReplicatedStorage/Modules/MutationVisuals.lua` |  |
| 13 | `ReplicatedStorage.Modules.PippoMutations` | ModuleScript | 29,781 / `879577a2` | `game-src/place-full/ReplicatedStorage/Modules/PippoMutations.lua` |  |
| 14 | `ReplicatedStorage.Modules.PippoSkin` | ModuleScript | 13,819 / `5bb85f3b` | `game-src/place-full/ReplicatedStorage/Modules/PippoSkin.lua` |  |
| 15 | `ReplicatedStorage.Modules.Platform` | ModuleScript | 31,026 / `613dd8a7` | `game-src/place-full/ReplicatedStorage/Modules/Platform.lua` |  |
| 16 | `ReplicatedStorage.Modules.RarityConfigTundra` | ModuleScript | 3,544 / `2a15ee0d` | `game-src/place-full/ReplicatedStorage/Modules/RarityConfigTundra.lua` |  |
| 17 | `ReplicatedStorage.Modules.RockConfigTundra` | ModuleScript | 5,163 / `a462288b` | `game-src/place-full/ReplicatedStorage/Modules/RockConfigTundra.lua` |  |
| 18 | `ReplicatedStorage.Modules.SellValue` | ModuleScript | 5,017 / `12fa1091` | `game-src/place-full/ReplicatedStorage/Modules/SellValue.lua` |  |
| 19 | `ReplicatedStorage.Modules.SizeConfig` | ModuleScript | 3,542 / `bb352fd5` | `game-src/place-full/ReplicatedStorage/Modules/SizeConfig.lua` |  |
| 20 | `ReplicatedStorage.Modules.StealConfig` | ModuleScript | 3,754 / `bcbd80fe` | `game-src/place-full/ReplicatedStorage/Modules/StealConfig.lua` |  |
| 21 | `ReplicatedStorage.Modules.UIKit.InteractionPrompt` | ModuleScript | 11,318 / `364bebf6` | `game-src/place-full/ReplicatedStorage/Modules/UIKit/InteractionPrompt.lua` | ⚡; working tree already = live (uncommitted) |
| 22 | `ReplicatedStorage.Modules.UIKit.QuestCard` | ModuleScript | 14,393 / `475a4b60` | `game-src/place-full/ReplicatedStorage/Modules/UIKit/QuestCard.lua` | ⚡; working tree already = live (uncommitted) |
| 23 | `ReplicatedStorage.Modules.VoxelEgg` | ModuleScript | 5,503 / `6947ae4e` | `game-src/place-full/ReplicatedStorage/Modules/VoxelEgg.lua` |  |
| 24 | `ReplicatedStorage.Modules.VoxelEggAura` | ModuleScript | 6,278 / `6bc0e574` | `game-src/place-full/ReplicatedStorage/Modules/VoxelEggAura.lua` |  |
| 25 | `ReplicatedStorage.Modules.WorldProgression` | ModuleScript | 8,870 / `8992521b` | `game-src/place-full/ReplicatedStorage/Modules/WorldProgression.lua` |  |
| 26 | `ReplicatedStorage.Modules.WorldTravelConfig` | ModuleScript | 5,571 / `2ec1f5d9` | `game-src/place-full/ReplicatedStorage/Modules/WorldTravelConfig.lua` |  |
| 27 | `ServerScriptService.AdminAnnouncements` | Script | 3,613 / `3f283aed` | `game-src/place-full/ServerScriptService/AdminAnnouncements.server.lua` |  |
| 28 | `ServerScriptService.DayNightCycle` | Script | 2,629 / `4319b30f` | `game-src/place-full/ServerScriptService/DayNightCycle.server.lua` |  |
| 29 | `ServerScriptService.GearBlocker` | Script | 3,548 / `3ed1dc12` | `game-src/place-full/ServerScriptService/GearBlocker.server.lua` |  |
| 30 | `ServerScriptService.Modules.DevQuest` | ModuleScript | 10,454 / `301e1a0f` | `game-src/place-full/ServerScriptService/Modules/DevQuest.lua` |  |
| 31 | `ServerScriptService.Modules.EmeraldService` | ModuleScript | 20,194 / `c5e8e009` | `game-src/place-full/ServerScriptService/Modules/EmeraldService.lua` |  |
| 32 | `ServerScriptService.Modules.GiftService` | ModuleScript | 10,541 / `a951ed86` | `game-src/place-full/ServerScriptService/Modules/GiftService.lua` |  |
| 33 | `ServerScriptService.Modules.PlotEquipPad` | ModuleScript | 18,424 / `750f16a0` | `game-src/place-full/ServerScriptService/Modules/PlotEquipPad.lua` |  |
| 34 | `ServerScriptService.Modules.PlotFavoriteService` | ModuleScript | 10,193 / `f17904da` | `game-src/place-full/ServerScriptService/Modules/PlotFavoriteService.lua` |  |
| 35 | `ServerScriptService.Modules.RockSlingService` | ModuleScript | 15,567 / `9086ebcf` | `game-src/place-full/ServerScriptService/Modules/RockSlingService.lua` |  |
| 36 | `ServerScriptService.Modules.RodService` | ModuleScript | 15,607 / `9f86ed75` | `game-src/place-full/ServerScriptService/Modules/RodService.lua` |  |
| 37 | `ServerScriptService.Modules.ScooterService` | ModuleScript | 14,595 / `3118d228` | `game-src/place-full/ServerScriptService/Modules/ScooterService.lua` |  |
| 38 | `ServerScriptService.Modules.SessionLock` | ModuleScript | 6,154 / `562e70d5` | `game-src/place-full/ServerScriptService/Modules/SessionLock.lua` | working tree already = live (uncommitted) |
| 39 | `ServerScriptService.Modules.ShopService` | ModuleScript | 4,844 / `b3b9eb36` | `game-src/place-full/ServerScriptService/Modules/ShopService.lua` |  |
| 40 | `ServerScriptService.Modules.StealService` | ModuleScript | 13,583 / `bc8b89e3` | `game-src/place-full/ServerScriptService/Modules/StealService.lua` |  |
| 41 | `ServerScriptService.Modules.WorldTravelService` | ModuleScript | 7,345 / `d6eb74e0` | `game-src/place-full/ServerScriptService/Modules/WorldTravelService.lua` |  |
| 42 | `ServerScriptService.NightLights` | Script | 3,186 / `d8f58a16` | `game-src/place-full/ServerScriptService/NightLights.server.lua` |  |
| 43 | `ServerScriptService.NpcBodyLife` | Script | 6,768 / `c640a773` | `game-src/place-full/ServerScriptService/NpcBodyLife.server.lua` |  |
| 44 | `ServerScriptService.NpcIdle` | Script | 15,282 / `8877e203` | `game-src/place-full/ServerScriptService/NpcIdle.server.lua` |  |
| 45 | `ServerScriptService.NpcPropLife` | Script | 13,021 / `eeb120c6` | `game-src/place-full/ServerScriptService/NpcPropLife.server.lua` |  |
| 46 | `ServerScriptService.NpcRigLife` | Script | 10,583 / `e023646f` | `game-src/place-full/ServerScriptService/NpcRigLife.server.lua` |  |
| 47 | `ServerScriptService.SnowFootprints` | Script | 5,312 / `a301c330` | `game-src/place-full/ServerScriptService/SnowFootprints.server.lua` |  |
| 48 | `StarterGui.Messages.MessageHandler` | LocalScript | 2,180 / `400f87da` | `game-src/place-full/StarterGui/Messages/MessageHandler.client.lua` |  |
| 49 | `StarterPlayer.StarterPlayerScripts.CameraWatchdog` | LocalScript | 3,642 / `fb32b39c` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/CameraWatchdog.client.lua` |  |
| 50 | `StarterPlayer.StarterPlayerScripts.CaveDrillClient` | LocalScript | 23,081 / `32372ec6` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/CaveDrillClient.client.lua` |  |
| 51 | `StarterPlayer.StarterPlayerScripts.CellarDoorClient` | LocalScript | 6,789 / `0ddc10a5` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/CellarDoorClient.client.lua` |  |
| 52 | `StarterPlayer.StarterPlayerScripts.ChatTagClient` | LocalScript | 1,834 / `840d3d73` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/ChatTagClient.client.lua` |  |
| 53 | `StarterPlayer.StarterPlayerScripts.DevQuestClient` | LocalScript | 1,543 / `ba403ef9` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/DevQuestClient.client.lua` |  |
| 54 | `StarterPlayer.StarterPlayerScripts.EmeraldHUDClient` | LocalScript | 11,513 / `73ca743b` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/EmeraldHUDClient.client.lua` |  |
| 55 | `StarterPlayer.StarterPlayerScripts.EquipPadClient` | LocalScript | 8,034 / `2481ca97` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/EquipPadClient.client.lua` |  |
| 56 | `StarterPlayer.StarterPlayerScripts.FireflyClient` | LocalScript | 5,994 / `c505dd78` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/FireflyClient.client.lua` |  |
| 57 | `StarterPlayer.StarterPlayerScripts.GameHUDPanels.PetAbilityHelp` | ModuleScript | 6,989 / `16c01080` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDPanels/PetAbilityHelp.lua` |  |
| 58 | `StarterPlayer.StarterPlayerScripts.GameHUDPanels.ProgressPanel` | ModuleScript | 3,673 / `5c4ecbd7` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDPanels/ProgressPanel.lua` |  |
| 59 | `StarterPlayer.StarterPlayerScripts.GameHUDPanels.WorldsPanel` | ModuleScript | 9,257 / `f56c5f5e` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDPanels/WorldsPanel.lua` |  |
| 60 | `StarterPlayer.StarterPlayerScripts.GardensAtmosphere` | LocalScript | 5,274 / `7c187304` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/GardensAtmosphere.client.lua` |  |
| 61 | `StarterPlayer.StarterPlayerScripts.GiftClient` | LocalScript | 317 / `c156019d` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/GiftClient.client.lua` |  |
| 62 | `StarterPlayer.StarterPlayerScripts.InteractionPromptClient` | LocalScript | 5,454 / `87261c64` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/InteractionPromptClient.client.lua` | ⚡; working tree already = live (uncommitted) |
| 63 | `StarterPlayer.StarterPlayerScripts.MutationMotionClient` | LocalScript | 15,583 / `0edab2d6` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/MutationMotionClient.client.lua` |  |
| 64 | `StarterPlayer.StarterPlayerScripts.PetVisualsClient` | LocalScript | 30,386 / `5d7eea6a` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/PetVisualsClient.client.lua` |  |
| 65 | `StarterPlayer.StarterPlayerScripts.PippoMotionClient` | LocalScript | 3,382 / `4539387e` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/PippoMotionClient.client.lua` |  |
| 66 | `StarterPlayer.StarterPlayerScripts.PlatformClient` | LocalScript | 33,109 / `d11016f0` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/PlatformClient.client.lua` |  |
| 67 | `StarterPlayer.StarterPlayerScripts.PlayerTagClient` | LocalScript | 2,941 / `6adcda71` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/PlayerTagClient.client.lua` |  |
| 68 | `StarterPlayer.StarterPlayerScripts.PlotFavoriteClient` | LocalScript | 9,057 / `de266797` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/PlotFavoriteClient.client.lua` |  |
| 69 | `StarterPlayer.StarterPlayerScripts.PlotFlagVisibility` | LocalScript | 4,705 / `4ff4ee31` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/PlotFlagVisibility.client.lua` |  |
| 70 | `StarterPlayer.StarterPlayerScripts.RaidClient` | LocalScript | 2,674 / `c7c9be1b` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/RaidClient.client.lua` |  |
| 71 | `StarterPlayer.StarterPlayerScripts.RodFxClient` | LocalScript | 4,253 / `abb816eb` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/RodFxClient.client.lua` |  |
| 72 | `StarterPlayer.StarterPlayerScripts.ShopPanelCentre` | LocalScript | 1,870 / `cc54efba` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/ShopPanelCentre.client.lua` |  |
| 73 | `StarterPlayer.StarterPlayerScripts.TeleportFadeClient` | LocalScript | 7,161 / `78176afb` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/TeleportFadeClient.client.lua` |  |
| 74 | `StarterPlayer.StarterPlayerScripts.TundraAtmosphere` | LocalScript | 6,946 / `634c87ee` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/TundraAtmosphere.client.lua` |  |
| 75 | `StarterPlayer.StarterPlayerScripts.TundraBirds` | LocalScript | 5,998 / `2a6115b3` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/TundraBirds.client.lua` |  |
| 76 | `StarterPlayer.StarterPlayerScripts.TundraWeatherFX` | LocalScript | 5,878 / `e23266c5` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/TundraWeatherFX.client.lua` |  |
| 77 | `StarterPlayer.StarterPlayerScripts.ValleyAmbience` | LocalScript | 8,803 / `5ed4eb7a` | `game-src/place-full/StarterPlayer/StarterPlayerScripts/ValleyAmbience.client.lua` |  |

### 4.3 MISSING FROM REPO — 170 scripts under `ServerStorage`

**ServerStorage.AuditBackups (flat)** — 24 scripts

| DataModel path | class | live bytes / hash | flags |
|---|---|---|---|
| `ServerStorage.AuditBackups.BackpackClient_pre_invrework` | LocalScript | 27,554 / `1112a388` | Enabled=false |
| `ServerStorage.AuditBackups.BrainrotBodyBuilder_pre_perfflags` | ModuleScript | 48,282 / `806ef56c` |  |
| `ServerStorage.AuditBackups.BrainrotBodyBuilder_pre_styleredo` | ModuleScript | 48,817 / `d1ddf979` |  |
| `ServerStorage.AuditBackups.BrainrotConfigTundra_pre_placeholderwipe` | ModuleScript | 10,234 / `cad3af75` |  |
| `ServerStorage.AuditBackups.BrainrotHoldClient_pre_invrework` | LocalScript | 3,363 / `8882e0df` | Enabled=false |
| `ServerStorage.AuditBackups.BrainrotIdleClient_pre_fxlod` | LocalScript | 16,801 / `87b8b511` | Enabled=false |
| `ServerStorage.AuditBackups.BrainrotIdleClient_pre_lod` | LocalScript | 13,953 / `367a5b2a` |  |
| `ServerStorage.AuditBackups.BrainrotPlaceClient_pre_invrework` | LocalScript | 5,071 / `8d86efb2` | Enabled=false |
| `ServerStorage.AuditBackups.BrainrotSpawner_pre_weld` | ModuleScript | 21,057 / `dd33dc40` |  |
| `ServerStorage.AuditBackups.EggConfig_pre_world2open` | ModuleScript | 12,382 / `228dd6eb` |  |
| `ServerStorage.AuditBackups.EggShopClient_pre_hatchredesign` | ModuleScript | 197,114 / `b6d04a94` |  |
| `ServerStorage.AuditBackups.EggShopClient_pre_retime` | LocalScript | 211,636 / `6167ec3d` |  |
| `ServerStorage.AuditBackups.GiftClient_pre_invrework` | LocalScript | 7,856 / `1fa3dfa0` | Enabled=false |
| `ServerStorage.AuditBackups.InventoryClient_pre_invrework` | LocalScript | 2,590 / `274f3975` | Enabled=false |
| `ServerStorage.AuditBackups.PassPanel_pre_reformat` | ModuleScript | 42,796 / `61b84572` |  |
| `ServerStorage.AuditBackups.PetHandler_preFinalFix` | ModuleScript | 24,039 / `525bed61` |  |
| `ServerStorage.AuditBackups.QuestTrackerClient_pre_bazaar` | LocalScript | 38,395 / `89ddeafc` |  |
| `ServerStorage.AuditBackups.QuestTrackerClient_pre_questlog` | LocalScript | 21,880 / `3a4de63c` | Enabled=false |
| `ServerStorage.AuditBackups.RockDesign_pre_fxpass` | ModuleScript | 9,027 / `35bd2cb5` |  |
| `ServerStorage.AuditBackups.SellHandler_preFinalFix` | ModuleScript | 4,881 / `7bd444a0` |  |
| `ServerStorage.AuditBackups.SellPanel_preFinalFix` | ModuleScript | 42,182 / `06c708ef` |  |
| `ServerStorage.AuditBackups.SellPanel_preHandoffLayout` | ModuleScript | 47,705 / `a8d158e6` |  |
| `ServerStorage.AuditBackups.TeleportService_pre_coverebuild` | Script | 19,159 / `6bcdd9b5` | Enabled=false |
| `ServerStorage.AuditBackups.Tokens_preFinalFix` | ModuleScript | 17,658 / `66f829eb` |  |

**ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15** — 37 scripts — **37 names contain `|` (not writable on Windows verbatim)**

| DataModel path | class | live bytes / hash | flags |
|---|---|---|---|
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ReplicatedStorage\|Modules\|BrainrotConfig` | ModuleScript | 22,794 / `0fd67f34` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ReplicatedStorage\|Modules\|CharmConfig` | ModuleScript | 31,066 / `59bc2e48` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ReplicatedStorage\|Modules\|DailyRewardConfig` | ModuleScript | 6,376 / `a70b9371` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ReplicatedStorage\|Modules\|DarrelPackConfig` | ModuleScript | 4,148 / `7e557e77` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ReplicatedStorage\|Modules\|EggConfig` | ModuleScript | 4,838 / `16a4f0d7` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ReplicatedStorage\|Modules\|MichelQuestConfig` | ModuleScript | 5,789 / `6b7accd7` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ReplicatedStorage\|Modules\|SeasonConfig` | ModuleScript | 18,914 / `857351c4` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ReplicatedStorage\|Modules\|TundraQuestConfig` | ModuleScript | 7,284 / `e6213a5e` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ReplicatedStorage\|Modules\|UIKit\|IconArt` | ModuleScript | 42,619 / `925d4502` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ReplicatedStorage\|Modules\|UIKit\|PanelChrome` | ModuleScript | 31,016 / `0a29a2aa` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ReplicatedStorage\|Modules\|UIKit\|SpecTheme` | ModuleScript | 8,105 / `bba69499` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ServerScriptService\|Main` | Script | 9,329 / `0a58cc95` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ServerScriptService\|Modules\|BoothHandler` | ModuleScript | 19,758 / `9f07e880` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ServerScriptService\|Modules\|DailyRewardHandler` | ModuleScript | 5,583 / `a3780f73` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ServerScriptService\|Modules\|DarrelService` | ModuleScript | 15,964 / `0a2f2a2e` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ServerScriptService\|Modules\|EggHandler` | ModuleScript | 7,346 / `ec117f31` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ServerScriptService\|Modules\|FusionHandler` | ModuleScript | 6,337 / `49ffca8a` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ServerScriptService\|Modules\|IncomeLoop` | ModuleScript | 12,318 / `e50be0e1` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ServerScriptService\|Modules\|MichelQuest` | ModuleScript | 13,997 / `cd195123` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ServerScriptService\|Modules\|PlayerDataManager` | ModuleScript | 45,261 / `e386c911` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ServerScriptService\|Modules\|ProductRegistry` | ModuleScript | 4,324 / `9eba4717` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ServerScriptService\|Modules\|QuestHandler` | ModuleScript | 10,306 / `f8881a64` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ServerScriptService\|Modules\|SeasonPassHandler` | ModuleScript | 18,518 / `6faec2fe` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ServerScriptService\|Modules\|ShopService` | ModuleScript | 4,837 / `55b93aca` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ServerScriptService\|Modules\|ThrowHandler` | ModuleScript | 61,710 / `bcaeaea7` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ServerScriptService\|Modules\|TundraQuest` | ModuleScript | 14,559 / `57353c81` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.StarterPlayer\|StarterPlayerScripts\|DarrelHUDClient` | LocalScript | 8,464 / `23c84a72` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.StarterPlayer\|StarterPlayerScripts\|EggShopClient` | LocalScript | 232,405 / `662a477c` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.StarterPlayer\|StarterPlayerScripts\|GameHUDClient` | LocalScript | 102,431 / `dbf61338` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.StarterPlayer\|StarterPlayerScripts\|GameHUDPanels\|CharmsPanel` | ModuleScript | 91,752 / `86e22f2d` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.StarterPlayer\|StarterPlayerScripts\|GameHUDPanels\|DailyPanel` | ModuleScript | 40,434 / `9ff8d17c` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.StarterPlayer\|StarterPlayerScripts\|GameHUDPanels\|GoalsPanel` | ModuleScript | 64,492 / `16adc598` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.StarterPlayer\|StarterPlayerScripts\|GameHUDPanels\|PassPanel` | ModuleScript | 42,570 / `bdf8a9ec` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.StarterPlayer\|StarterPlayerScripts\|GameHUDPanels\|ShopPanel` | ModuleScript | 10,675 / `19c98d39` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.StarterPlayer\|StarterPlayerScripts\|HudToggleClient` | LocalScript | 29,159 / `479f2889` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.StarterPlayer\|StarterPlayerScripts\|MichelQuestClient` | LocalScript | 24,022 / `62934cbd` | `|` in name |
| `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.StarterPlayer\|StarterPlayerScripts\|SeasonClient` | LocalScript | 12,595 / `eecbee47` | `|` in name |

**ServerStorage.AuditBackups.PreFeedback_2026_08_19** — 22 scripts — **22 names contain `|` (not writable on Windows verbatim)**

| DataModel path | class | live bytes / hash | flags |
|---|---|---|---|
| `ServerStorage.AuditBackups.PreFeedback_2026_08_19.ReplicatedStorage\|Modules\|MerchantDialog` | ModuleScript | 34,150 / `45f9369e` | `|` in name |
| `ServerStorage.AuditBackups.PreFeedback_2026_08_19.ReplicatedStorage\|Modules\|UIKit\|Builders` | ModuleScript | 21,040 / `6f0a54a2` | `|` in name |
| `ServerStorage.AuditBackups.PreFeedback_2026_08_19.ReplicatedStorage\|Modules\|UIKit\|Tokens` | ModuleScript | 17,179 / `2481f491` | `|` in name |
| `ServerStorage.AuditBackups.PreFeedback_2026_08_19.ReplicatedStorage\|Modules\|UITheme` | ModuleScript | 41,312 / `ba104b28` | `|` in name |
| `ServerStorage.AuditBackups.PreFeedback_2026_08_19.ServerScriptService\|Main` | Script | 9,919 / `bb03017a` | Enabled=false, `|` in name |
| `ServerStorage.AuditBackups.PreFeedback_2026_08_19.ServerScriptService\|Modules\|PlayerDataManager` | ModuleScript | 46,169 / `e93083f4` | `|` in name |
| `ServerStorage.AuditBackups.PreFeedback_2026_08_19.ServerScriptService\|Modules\|PlotBoardHandler` | ModuleScript | 16,601 / `5ff7096c` | `|` in name |
| `ServerStorage.AuditBackups.PreFeedback_2026_08_19.ServerScriptService\|Modules\|PlotEquipPad` | ModuleScript | 13,973 / `1999ea78` | `|` in name |
| `ServerStorage.AuditBackups.PreFeedback_2026_08_19.ServerScriptService\|Modules\|SellHandler` | ModuleScript | 5,440 / `8dfd3250` | `|` in name |
| `ServerStorage.AuditBackups.PreFeedback_2026_08_19.StarterPlayer\|StarterPlayerScripts\|ClientMain` | LocalScript | 137,853 / `c2a52873` | Enabled=false, `|` in name |
| `ServerStorage.AuditBackups.PreFeedback_2026_08_19.StarterPlayer\|StarterPlayerScripts\|EggShopClient` | LocalScript | 234,274 / `7789dde9` | Enabled=false, `|` in name |
| `ServerStorage.AuditBackups.PreFeedback_2026_08_19.StarterPlayer\|StarterPlayerScripts\|FusionClient` | LocalScript | 20,746 / `30a8fb65` | Enabled=false, `|` in name |
| `ServerStorage.AuditBackups.PreFeedback_2026_08_19.StarterPlayer\|StarterPlayerScripts\|GameHUDClient` | LocalScript | 115,118 / `6e893aef` | Enabled=false, `|` in name |
| `ServerStorage.AuditBackups.PreFeedback_2026_08_19.StarterPlayer\|StarterPlayerScripts\|GameHUDPanels\|ShopPanel` | ModuleScript | 13,811 / `92360088` | `|` in name |
| `ServerStorage.AuditBackups.PreFeedback_2026_08_19.StarterPlayer\|StarterPlayerScripts\|HudToggleClient` | LocalScript | 35,996 / `9ac305b1` | Enabled=false, `|` in name |
| `ServerStorage.AuditBackups.PreFeedback_2026_08_19.StarterPlayer\|StarterPlayerScripts\|IceFishingClient` | LocalScript | 28,489 / `144d1ac3` | Enabled=false, `|` in name |
| `ServerStorage.AuditBackups.PreFeedback_2026_08_19.StarterPlayer\|StarterPlayerScripts\|MerchantClient` | LocalScript | 28,822 / `a9523344` | Enabled=false, `|` in name |
| `ServerStorage.AuditBackups.PreFeedback_2026_08_19.StarterPlayer\|StarterPlayerScripts\|PetVisualsClient` | LocalScript | 30,386 / `5d7eea6a` | Enabled=false, `|` in name |
| `ServerStorage.AuditBackups.PreFeedback_2026_08_19.StarterPlayer\|StarterPlayerScripts\|QuestTrackerClient` | LocalScript | 51,621 / `cc5e4679` | Enabled=false, `|` in name |
| `ServerStorage.AuditBackups.PreFeedback_2026_08_19.StarterPlayer\|StarterPlayerScripts\|TeleportFadeClient` | LocalScript | 7,161 / `78176afb` | Enabled=false, `|` in name |
| `ServerStorage.AuditBackups.PreFeedback_2026_08_19.StarterPlayer\|StarterPlayerScripts\|TutorialClient` | LocalScript | 15,048 / `c2ed2395` | Enabled=false, `|` in name |
| `ServerStorage.AuditBackups.PreFeedback_2026_08_19.StarterPlayer\|StarterPlayerScripts\|WheelClient` | LocalScript | 69,920 / `d6da024e` | Enabled=false, `|` in name |

**ServerStorage.AuditBackups.PreIceFishing_2026_08_21** — 4 scripts

| DataModel path | class | live bytes / hash | flags |
|---|---|---|---|
| `ServerStorage.AuditBackups.PreIceFishing_2026_08_21.BrainrotConfigTundra` | ModuleScript | 10,920 / `adb2e3f5` |  |
| `ServerStorage.AuditBackups.PreIceFishing_2026_08_21.IceFishingClient` | LocalScript | 28,489 / `144d1ac3` |  |
| `ServerStorage.AuditBackups.PreIceFishing_2026_08_21.IceFishingConfig` | ModuleScript | 21,494 / `8ae1efc1` |  |
| `ServerStorage.AuditBackups.PreIceFishing_2026_08_21.IceFishingEvent` | ModuleScript | 51,632 / `07aa3d4f` |  |

**ServerStorage.AuditBackups.PreMechanics_2026_09_03** — 5 scripts

| DataModel path | class | live bytes / hash | flags |
|---|---|---|---|
| `ServerStorage.AuditBackups.PreMechanics_2026_09_03.RebirthClient` | LocalScript | 17,758 / `8c15361f` |  |
| `ServerStorage.AuditBackups.PreMechanics_2026_09_03.RebirthConfig` | ModuleScript | 2,153 / `0d9c6d7c` |  |
| `ServerStorage.AuditBackups.PreMechanics_2026_09_03.RebirthHandler` | ModuleScript | 3,014 / `04ba9a31` |  |
| `ServerStorage.AuditBackups.PreMechanics_2026_09_03.RockConfigTundra` | ModuleScript | 4,577 / `bdc84549` |  |
| `ServerStorage.AuditBackups.PreMechanics_2026_09_03.SellValue` | ModuleScript | 4,612 / `9d35a796` |  |

**ServerStorage.AuditBackups.PreSellPrice_2026_08_20** — 2 scripts

| DataModel path | class | live bytes / hash | flags |
|---|---|---|---|
| `ServerStorage.AuditBackups.PreSellPrice_2026_08_20.ClientMain` | LocalScript | 137,853 / `c2a52873` |  |
| `ServerStorage.AuditBackups.PreSellPrice_2026_08_20.SellHandler` | ModuleScript | 6,684 / `b20602c7` |  |

**ServerStorage.AuditBackups.PreSellShop_2026_08_20** — 13 scripts

| DataModel path | class | live bytes / hash | flags |
|---|---|---|---|
| `ServerStorage.AuditBackups.PreSellShop_2026_08_20.ClientMain_preAutoClose` | LocalScript | 132,724 / `5cf944e4` |  |
| `ServerStorage.AuditBackups.PreSellShop_2026_08_20.ClientMain_preFrameDelete` | LocalScript | 134,460 / `b1c6b174` |  |
| `ServerStorage.AuditBackups.PreSellShop_2026_08_20.ClientMain_preTask9` | LocalScript | 141,588 / `a97de4a8` |  |
| `ServerStorage.AuditBackups.PreSellShop_2026_08_20.GameHUDClient` | LocalScript | 122,543 / `884cd947` |  |
| `ServerStorage.AuditBackups.PreSellShop_2026_08_20.GameHUDClient_preAutoClose` | LocalScript | 123,170 / `70e3984e` |  |
| `ServerStorage.AuditBackups.PreSellShop_2026_08_20.PetHandler` | ModuleScript | 23,005 / `b36866fd` |  |
| `ServerStorage.AuditBackups.PreSellShop_2026_08_20.SellHandler` | ModuleScript | 9,066 / `2f9a7df6` |  |
| `ServerStorage.AuditBackups.PreSellShop_2026_08_20.SellHandler_preOneFix` | ModuleScript | 4,295 / `e0a2e80a` |  |
| `ServerStorage.AuditBackups.PreSellShop_2026_08_20.SellPanel_preTask6` | ModuleScript | 10,635 / `ad56c833` |  |
| `ServerStorage.AuditBackups.PreSellShop_2026_08_20.SellPanel_preTask7` | ModuleScript | 20,510 / `3f02a893` |  |
| `ServerStorage.AuditBackups.PreSellShop_2026_08_20.SellPanel_preTask8` | ModuleScript | 32,839 / `8df162b9` |  |
| `ServerStorage.AuditBackups.PreSellShop_2026_08_20.SellValue` | ModuleScript | 2,764 / `8054f166` |  |
| `ServerStorage.AuditBackups.PreSellShop_2026_08_20.SellValue_preOneFix` | ModuleScript | 3,932 / `2e9a2d92` |  |

**ServerStorage.AuditBackups.PreTutorial_2026_08_20** — 2 scripts

| DataModel path | class | live bytes / hash | flags |
|---|---|---|---|
| `ServerStorage.AuditBackups.PreTutorial_2026_08_20.Main` | Script | 9,919 / `bb03017a` |  |
| `ServerStorage.AuditBackups.PreTutorial_2026_08_20.TutorialClient` | LocalScript | 15,048 / `c2ed2395` |  |

**ServerStorage.AuditBackups.PreUIFoundation_2026_09_18** — 17 scripts

| DataModel path | class | live bytes / hash | flags |
|---|---|---|---|
| `ServerStorage.AuditBackups.PreUIFoundation_2026_09_18.BackpackPanel_pre13` | ModuleScript | 220,878 / `d0e84960` |  |
| `ServerStorage.AuditBackups.PreUIFoundation_2026_09_18.BackpackPanel_preFix` | ModuleScript | 222,066 / `eb21de19` |  |
| `ServerStorage.AuditBackups.PreUIFoundation_2026_09_18.BrainrotCard_preFix` | ModuleScript | 27,502 / `b71624bd` |  |
| `ServerStorage.AuditBackups.PreUIFoundation_2026_09_18.BrainrotThumb_pre8` | ModuleScript | 14,596 / `52caa1b1` |  |
| `ServerStorage.AuditBackups.PreUIFoundation_2026_09_18.CharmsPanel_pre12` | ModuleScript | 94,833 / `56e7b6eb` |  |
| `ServerStorage.AuditBackups.PreUIFoundation_2026_09_18.FxDriver_preFix` | ModuleScript | 2,996 / `6f23e8bd` |  |
| `ServerStorage.AuditBackups.PreUIFoundation_2026_09_18.GameHUDClient_pre11` | LocalScript | 142,809 / `e14fec91` |  |
| `ServerStorage.AuditBackups.PreUIFoundation_2026_09_18.GameHUDClient_preFix` | LocalScript | 143,521 / `0db189be` |  |
| `ServerStorage.AuditBackups.PreUIFoundation_2026_09_18.GoalsPanel_pre12` | ModuleScript | 68,790 / `c16d1498` |  |
| `ServerStorage.AuditBackups.PreUIFoundation_2026_09_18.IndexPanel_pre12` | ModuleScript | 70,346 / `c1bbb821` |  |
| `ServerStorage.AuditBackups.PreUIFoundation_2026_09_18.Modal_preFix` | ModuleScript | 5,535 / `da3d1647` |  |
| `ServerStorage.AuditBackups.PreUIFoundation_2026_09_18.PanelChrome_pre4` | ModuleScript | 44,979 / `eef503ff` |  |
| `ServerStorage.AuditBackups.PreUIFoundation_2026_09_18.PanelChrome_pre5` | ModuleScript | 54,669 / `9b92c948` |  |
| `ServerStorage.AuditBackups.PreUIFoundation_2026_09_18.PanelChrome_preFix` | ModuleScript | 59,228 / `6092aee3` |  |
| `ServerStorage.AuditBackups.PreUIFoundation_2026_09_18.SpecTheme_pre11` | ModuleScript | 14,522 / `f5e528cf` |  |
| `ServerStorage.AuditBackups.PreUIFoundation_2026_09_18.ToastClient_pre7` | LocalScript | 13,844 / `a2695b7d` |  |
| `ServerStorage.AuditBackups.PreUIFoundation_2026_09_18.ViewportCuller_preFix` | ModuleScript | 6,664 / `7d89f406` |  |

**ServerStorage.AuditBackups.PreUIFoundation_2026_09_18_Task2** — 2 scripts

| DataModel path | class | live bytes / hash | flags |
|---|---|---|---|
| `ServerStorage.AuditBackups.PreUIFoundation_2026_09_18_Task2.GameHUDClient_pre2` | LocalScript | 142,049 / `218e2680` |  |
| `ServerStorage.AuditBackups.PreUIFoundation_2026_09_18_Task2.SpecTheme_pre2` | ModuleScript | 10,069 / `972dfcbb` |  |

**ServerStorage.AuditBackups.PreUIRound2_2026_09_18** — 9 scripts

| DataModel path | class | live bytes / hash | flags |
|---|---|---|---|
| `ServerStorage.AuditBackups.PreUIRound2_2026_09_18.BackpackPanel_pre` | ModuleScript | 222,167 / `3a165702` |  |
| `ServerStorage.AuditBackups.PreUIRound2_2026_09_18.BrainrotCard_pre` | ModuleScript | 28,201 / `c8d4da90` |  |
| `ServerStorage.AuditBackups.PreUIRound2_2026_09_18.EggShopClient_pre` | LocalScript | 246,896 / `5c4a71fe` | Enabled=false |
| `ServerStorage.AuditBackups.PreUIRound2_2026_09_18.GameHUDClient_pre` | LocalScript | 143,791 / `7af6e337` | Enabled=false |
| `ServerStorage.AuditBackups.PreUIRound2_2026_09_18.GoalsPanel_pre` | ModuleScript | 68,832 / `60d83de5` |  |
| `ServerStorage.AuditBackups.PreUIRound2_2026_09_18.LuckHUDClient_pre` | LocalScript | 37,206 / `9caf08a1` | Enabled=false |
| `ServerStorage.AuditBackups.PreUIRound2_2026_09_18.MerchantClient_pre` | LocalScript | 34,514 / `4a7df953` | Enabled=false |
| `ServerStorage.AuditBackups.PreUIRound2_2026_09_18.PassPanel_pre` | ModuleScript | 43,373 / `8e62e1a3` |  |
| `ServerStorage.AuditBackups.PreUIRound2_2026_09_18.SpecTheme_pre` | ModuleScript | 14,938 / `01e35300` |  |

**ServerStorage.AuditBackups.PreUIRound3_2026_09_19** — 3 scripts

| DataModel path | class | live bytes / hash | flags |
|---|---|---|---|
| `ServerStorage.AuditBackups.PreUIRound3_2026_09_19.MerchantDialog_pre` | ModuleScript | 35,270 / `2c39a10d` |  |
| `ServerStorage.AuditBackups.PreUIRound3_2026_09_19.QuestBarClient_pre` | LocalScript | 19,762 / `86487ef9` | Enabled=false |
| `ServerStorage.AuditBackups.PreUIRound3_2026_09_19.QuestTrackerClient_pre` | LocalScript | 59,456 / `1e8a8c17` | Enabled=false |

**ServerStorage.AuditBackups.ScreenGui_helloworld_template_junk** — 1 scripts

| DataModel path | class | live bytes / hash | flags |
|---|---|---|---|
| `ServerStorage.AuditBackups.ScreenGui_helloworld_template_junk.Model.Model.Script` | Script | 22 / `995ff584` |  |

**ServerStorage (top-level)** — 7 scripts

| DataModel path | class | live bytes / hash | flags |
|---|---|---|---|
| `ServerStorage.BrainrotBudget` | ModuleScript | 12,027 / `f2200582` |  |
| `ServerStorage.BrainrotForge` | ModuleScript | 9,162 / `287ff294` |  |
| `ServerStorage.PeteV3Build` | ModuleScript | 4,930 / `9da43f2e` |  |
| `ServerStorage.PeteV3Pipeline` | ModuleScript | 10,256 / `db80c228` |  |
| `ServerStorage.PlotLODBuilder` | ModuleScript | 16,262 / `873a76ff` |  |
| `ServerStorage.TundraPetBuilders` | ModuleScript | 17,640 / `35867672` |  |
| `ServerStorage.TundraPetKit` | ModuleScript | 8,856 / `426f94c9` |  |

**ServerStorage.GardensBuild** — 22 scripts

| DataModel path | class | live bytes / hash | flags |
|---|---|---|---|
| `ServerStorage.GardensBuild.Arch` | ModuleScript | 17,839 / `5212be38` |  |
| `ServerStorage.GardensBuild.BuildCathedral` | ModuleScript | 22,270 / `2ac10baa` |  |
| `ServerStorage.GardensBuild.BuildFlora` | ModuleScript | 11,548 / `671cb8ad` |  |
| `ServerStorage.GardensBuild.BuildHillPath` | ModuleScript | 12,904 / `0a0734e8` |  |
| `ServerStorage.GardensBuild.BuildHub` | ModuleScript | 15,368 / `15cc0456` |  |
| `ServerStorage.GardensBuild.BuildLife` | ModuleScript | 9,232 / `e37b8a90` |  |
| `ServerStorage.GardensBuild.BuildPortals` | ModuleScript | 7,064 / `9e6ed262` |  |
| `ServerStorage.GardensBuild.BuildRegions` | ModuleScript | 11,787 / `8b1597c0` |  |
| `ServerStorage.GardensBuild.BuildRoads` | ModuleScript | 5,250 / `494736bc` |  |
| `ServerStorage.GardensBuild.BuildTown` | ModuleScript | 13,906 / `d5c8def3` |  |
| `ServerStorage.GardensBuild.BuildTundraCamps` | ModuleScript | 10,861 / `72190cf4` |  |
| `ServerStorage.GardensBuild.BuildTundraUpgrade` | ModuleScript | 22,157 / `a7d72cc6` |  |
| `ServerStorage.GardensBuild.BuildWater` | ModuleScript | 13,252 / `1dfebd29` |  |
| `ServerStorage.GardensBuild.Creature` | ModuleScript | 20,265 / `a18db05e` |  |
| `ServerStorage.GardensBuild.Field` | ModuleScript | 15,507 / `724fefd0` |  |
| `ServerStorage.GardensBuild.Flora` | ModuleScript | 15,524 / `3d61f524` |  |
| `ServerStorage.GardensBuild.House` | ModuleScript | 14,964 / `7de4f9cc` |  |
| `ServerStorage.GardensBuild.Lib` | ModuleScript | 11,941 / `8cb60138` |  |
| `ServerStorage.GardensBuild.Optimize` | ModuleScript | 3,697 / `5e1e4139` |  |
| `ServerStorage.GardensBuild.Props` | ModuleScript | 23,293 / `da375c56` |  |
| `ServerStorage.GardensBuild.Terra` | ModuleScript | 18,728 / `ccdc114e` |  |
| `ServerStorage.GardensBuild.Water` | ModuleScript | 11,220 / `4943dae3` |  |

### 4.4 REPO ONLY / STALE — 3 files (no live script at that path)

| repo file | class | bytes / hash | determination | evidence |
|---|---|---|---|---|
| `game-src/place-full/ServerScriptService/Modules/DarrelService.lua` | ModuleScript | 4,279 / `99bdb2f4` | **renamed/moved → `ServerScriptService.Modules.EmeraldService`** (live, 20,194 B, unmirrored); mirror is the pre-rename version and is stale | live has no `DarrelService` anywhere outside backups; `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.ServerScriptService\|Modules\|DarrelService` (15,964 B) is the pre-rename copy; live `EmeraldService` exists. Also carries an uncommitted Aug-4 hand patch on disk (§3). |
| `game-src/place-full/StarterGui/ScreenGui/Model/Model/Script.server.lua` | Script | 22 / `995ff584` | **genuinely removed from `StarterGui`** (moved live to `ServerStorage.AuditBackups.ScreenGui_helloworld_template_junk.Model.Model.Script`); stale mirror artifact | identical bytes (22 B, hash `995ff584`) at the backup path; nothing at the StarterGui path |
| `game-src/place-full/StarterPlayer/StarterPlayerScripts/DarrelHUDClient.client.lua` | LocalScript | 8,464 / `23c84a72` | **renamed/moved → `StarterPlayer.StarterPlayerScripts.EmeraldHUDClient`** (live, 11,513 B, unmirrored); stale | mirror bytes are identical (hash `23c84a72`) to `ServerStorage.AuditBackups.PreEmeraldRename_2026_08_15.StarterPlayer\|StarterPlayerScripts\|DarrelHUDClient` |

No repo-only file is a historical backup or an intentionally retained helper; none should be deleted without Balkan's approval (§0 item 7).

### 4.5 PATH MISMATCH — 2

| live path | mirrored as | should be | content |
|---|---|---|---|
| `Workspace.GameWorld.TradingWorld.CoveDressing.CoveDriver` | `game-src/place-full/Workspace/GameWorld/TradingWorld/CoveDressing.CoveDriver.server.lua` | `game-src/place-full/Workspace/GameWorld/TradingWorld/CoveDressing/CoveDriver.server.lua` | byte-identical (7,706 B, `8414e863`) |
| `Workspace.GameWorld.TradingWorld.EternalSkip.SkipLoop` | `game-src/place-full/Workspace/GameWorld/TradingWorld/EternalSkip.SkipLoop.server.lua` | `game-src/place-full/Workspace/GameWorld/TradingWorld/EternalSkip/SkipLoop.server.lua` | byte-identical (1,615 B, `73841159`) |

The original export flattened these two Workspace scripts as `<Parent>.<Name>.server.lua` instead of creating the parent folder. Fix is a `git mv` (no content change).

### 4.6 CLASS MISMATCH — 0

No path has a different class live vs repo.

## 5. Live state the mirror format cannot express

The `.lua` / `.server.lua` / `.client.lua` mapping carries class only. Everything below is live truth that a rebuild from the mirror would lose; recorded here so it is at least written down.

- **Disabled scripts outside backups:** `StarterPlayer.StarterPlayerScripts.DailyRewardClient` is `Enabled=false` live (and DIFFERENT). `ServerStorage.BrainrotModelFactory_RETIRED`, `ServerStorage._DistanceMarkers_Backup.BuoyBob` and 40 `AuditBackups` scripts are disabled, as expected for parked code.
- **RunContext:** `Workspace.TitleScaler` is a `Script` with `RunContext=Client` (mirrored as `.server.lua` by the class rule — correct per the rule, misleading to a reader). `ServerStorage._DistanceMarkers_Backup.BuoyBob` likewise.
- **CR bytes:** `ReplicatedStorage.Modules.MerchantDialog` (878), `StarterPlayer.StarterPlayerScripts.QuestTrackerClient` (648), `StarterPlayer.StarterPlayerScripts.QuestBarClient` (416) — all three are ⚡ round-3 files being pushed byte-exact by the bridge; with `core.autocrlf=true` git will strip the CRs on commit (§0 item 6).
- **Unsaved editor text:** `ScriptEditorService:GetEditorSource()` equals `Source` for all 488 — no open-editor draft differs from what the DataModel holds.
- **Archivable:** all 488 are `Archivable=true`, so all would be saved with the place.
- **Cloud-unsaved edits:** PlaceVersion is 2353. The API does not expose which scripts changed since the last cloud save, so 'live' here means the Studio session's DataModel, which is what the round-3 session is editing.

## 6. Scripts that could not be read / tool limitations

- **Nothing failed to read.** All 488 `Source` properties were readable; no service errored on `GetDescendants()`.
- **Play-mode interruptions:** the Edit DataModel was unavailable three times during the audit because the other session was playtesting; the snapshot was taken in one uninterrupted Edit window (06:07–06:09 UTC). A planned second, byte-level pull of all 488 sources (to compare bytes rather than hashes) could not run before this report because Studio stayed in Play mode; the hash+size comparison is validated as described in §1.
- **`DraftsService:GetDrafts()`** is not callable from `execute_luau` (`lacking capability RobloxScript`), so Team Create drafts cannot be enumerated. Editor-vs-Source was checked instead (§5).
- **`execute_luau` result cap (~100 KB)** — worked around with the local bridge; it required flipping `HttpService.HttpEnabled` on for one call (restored to `false`, verified).
- **59 instance names contain `|`**, illegal in Windows filenames — cannot be mirrored verbatim (§0 item 5).
- **`git ls-tree` of `origin/master`** shows no mirror; the comparison against master is therefore trivially 'all missing' and not meaningful.

## 7. `_MANIFEST.txt` state

181 entries dated 2026-08-01. Against `HEAD`: 46 entries have a different hash/size, 2 entries no longer have a file (`ReplicatedStorage.Modules.CatchReveal`, `StarterPlayer.StarterPlayerScripts.CatchRevealClient`), and 65 tracked mirror files are not in the manifest at all. Against live: 95 entries differ and 5 are not live (`ReplicatedStorage.Modules.CatchReveal`, `ServerScriptService.Modules.DarrelService`, `StarterGui.ScreenGui.Model.Model.Script`, `StarterPlayer.StarterPlayerScripts.CatchRevealClient`, `StarterPlayer.StarterPlayerScripts.DarrelHUDClient`). The manifest has not been regenerated since the original export and no longer serves as a tripwire; it must be regenerated after the sync (brief §8).

## 8. Proposed sync (NOT executed — needs approval)

1. Create branch `source-sync-audit` from `ui-foundation` @ `3e0275b` in a separate worktree.
2. Add `.gitattributes` (`*.lua -text`) so mirror bytes are stored verbatim (if approved).
3. For every DIFFERENT (74) and MISSING (77 game + `ServerStorage` per decision) script: re-read `Source` from Studio **at sync time** via the bridge (byte-exact, no formatting changes) and write to the mapped path. ⚡ rows are re-read last / or left to the round-3 session — Balkan's call.
4. `git mv` the two PATH MISMATCH files into folder layout.
5. REPO ONLY: delete the two `Darrel*` pre-rename mirrors and the `StarterGui` template junk only on explicit approval.
6. Regenerate `_MANIFEST.txt` (`hash|bytes|class|path`, same h31 method) from the live DataModel; verify every live script has exactly one mirror entry.
7. Final verification: re-read all live scripts, compare again, document any exception (e.g. `|` names).
8. Commit as `chore: resync live Studio scripts into source mirror`; push only `source-sync-audit`.
9. Add the team rule (§9) to `game-src/place-full/README.md` and the root README.

The stale on-disk hand patches (§3) are **not** part of this sync; whatever Balkan decides for them happens separately so this commit stays a pure mirror operation.

## 9. Team rule to add (draft)

> Any task that creates or changes a Script, LocalScript, or ModuleScript in live Roblox Studio is **not complete** until the corresponding file under `game-src/place-full/` is updated (byte-exact — push it from Studio with `tools/studio-bridge/bridge.py`, do not retype it) and committed. `_MANIFEST.txt` is regenerated with the sync. GitHub is the canonical source for all Lua; Studio is where it runs.

## 10. What this audit does not cover

Lua source only. The repo is **not** a full-place backup: Terrain, Workspace geometry, models (`ReplicatedStorage.BrainrotModels`, egg models), placed instances, Studio-authored GUI instances, Lighting and world state are not mirrored and cannot be rebuilt from `game-src/`. The place still needs a periodic `.rbxl` / `.rbxlx` save kept off Roblox (File → Save to File As…). The mirror's own README says the same.

---
*Generated from a live snapshot taken 2026-09-19T06:09:02Z (PlaceVersion 2353); raw enumeration and comparison data are in the session scratchpad, not committed.*

## 11. Sync result (executed after approval)

**Decisions taken (Balkan, 2026-09-18 ~23:25):** sync now but skip the ⚡ round-3 files · branch `source-sync-audit` from
`ui-foundation` @ `3e0275b` in a separate worktree (`../skip-a-brainrot-source-sync`) · mirror all of `ServerStorage`
with `|` percent-encoded as `%7C` · `.gitattributes` (`*.lua -text`) as its own commit · delete the 3 stale repo-only
files and `git mv` the 2 path-mismatch files.

**How the sources were read.** The other session ran back-to-back playtests with Edit windows of 2–54 s, so the bulk
pull could not be done from the Edit DataModel. It was taken from the **Server DataModel of the running playtest**
(a copy of the Edit DataModel as of play start) at 06:39 UTC, filtered to paths present in the 06:09 Edit-mode
enumeration plus the runtime-filtered verification read below (Roblox's injected `PlayerModule` /
`PlayerScriptsLoader` / `RbxCharacterSounds` and the test character's `Health` / `Animate` were dropped as
runtime-only). Every staged source was checked against its own enumeration hash+size before placement
(0 mismatches). Placement compared bytes, not hashes.

**What was written** (`game-src/place-full/`, worktree): 8 new files,
1 updated (byte-exact, no formatting changes), 3 deletions
(`DarrelService.lua`, `DarrelHUDClient.client.lua`, `StarterGui/ScreenGui/Model/Model/Script.server.lua`), 2 renames
(`CoveDressing.CoveDriver.server.lua` → `CoveDressing/CoveDriver.server.lua`, `EternalSkip.SkipLoop.server.lua` →
`EternalSkip/SkipLoop.server.lua`), 59 files under the two `|`-named backup folders stored with `%7C`.
`_MANIFEST.txt` regenerated (493 lines, same h31 method, decoded names, sorted by path) and independently
cross-checked against every file's bytes (0 mismatches). README updated with the team rule (§9), the encoding rule
and the line-ending policy.

**Between the audit snapshot (06:09) and the pull (06:39) nine scripts changed live:** the round-3 files
`MerchantDialog`, `UIKit.QuestCard`, `QuestTrackerClient` (skipped, as decided) and six touched by a **second
concurrent workstream, "World2 blockout"** — `TeleportService`, `IceFishingEvent`, `WheelBoard`,
`LeaderboardBoards`, `TundraWeatherFX`, `SnowFootprints` — which also created
`ServerStorage.AuditBackups.PreWorld2Blockout_2026_09_19` (6 pre-edit copies), `ServerStorage.World2Blockout.Generator`
and `ServerStorage.World2Backups_2026_09_19.Rollback`. That workstream does not push to the mirror, so its current
state was mirrored (the 8 new scripts pulled by path at 06:44); if it keeps editing, those files will need a follow-up
push when it lands — the same rule as for round 3.

### Final verification

Read from the Server DataModel of the playtest that started 06:42:19 UTC (= Edit DataModel at that instant; the Edit
DataModel itself was never available long enough), runtime-only scripts filtered as above:

Live re-read 2026-09-19T06:43:57Z (PlaceVersion 0): **496 live scripts, 493 mirror files.** IDENTICAL 490 · DIFFERENT 3 · MISSING FROM REPO 3 · REPO ONLY 0 · CLASS MISMATCH 0.

| DataModel path | status | live bytes / hash | mirror bytes / hash | why |
|---|---|---|---|---|
| `ReplicatedStorage.Modules.MerchantDialog` | DIFFERENT | 37,889 / `a125ab6b` | 35,270 / `2c39a10d` | ⚡ round-3 in flight — deliberately not written (another session owns it) |
| `ReplicatedStorage.Modules.UIKit.InteractionPrompt` | MISSING FROM REPO | 11,318 / `364bebf6` | — | ⚡ round-3 in flight — deliberately not written (another session owns it) |
| `ReplicatedStorage.Modules.UIKit.QuestCard` | MISSING FROM REPO | 15,829 / `67e20767` | — | ⚡ round-3 in flight — deliberately not written (another session owns it) |
| `StarterPlayer.StarterPlayerScripts.InteractionPromptClient` | MISSING FROM REPO | 5,454 / `87261c64` | — | ⚡ round-3 in flight — deliberately not written (another session owns it) |
| `StarterPlayer.StarterPlayerScripts.QuestBarClient` | DIFFERENT | 19,340 / `af16e0a8` | 19,762 / `86487ef9` | ⚡ round-3 in flight — deliberately not written (another session owns it) |
| `StarterPlayer.StarterPlayerScripts.QuestTrackerClient` | DIFFERENT | 30,450 / `33b65804` | 59,456 / `1e8a8c17` | ⚡ round-3 in flight — deliberately not written (another session owns it) |

Live count 496 vs mirror 493: the difference is exactly the 3 round-3 scripts not yet in the mirror
(`UIKit.QuestCard`, `UIKit.InteractionPrompt`, `InteractionPromptClient`); the 3 DIFFERENT rows are the other
round-3 files. **Every other live LuaSourceContainer has exactly one byte-identical mirror file.** The round-3 session
already holds byte-exact copies of all six in the `ui-foundation` working tree (bridge pushes, §3), so they land with
that work — merging `source-sync-audit` into `ui-foundation` will not conflict on them because this branch did not
touch those paths.

### Still open after this sync

- The Aug 4 / Aug 9 uncommitted hand patches in the `ui-foundation` working tree (§3) were left untouched; they are
  Balkan's call and are not part of this branch.
- `docs/SOURCE-SYNC-AUDIT.md` was first written as an untracked file in the `ui-foundation` checkout for review; the
  committed copy is on `source-sync-audit`. The untracked copy was removed after the commit so it cannot be swept into
  another session's commit.
- Round-3 and World2-blockout files: re-run the manifest diff (`_MANIFEST.txt` vs a fresh export) once those land.
