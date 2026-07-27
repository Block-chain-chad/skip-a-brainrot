# game-src — mirrors of Studio scripts (visual system, shipped 2026-07-25)

The live source of truth is Roblox Studio. These are commit-time mirrors:
- BrainrotLooks.lua -> ReplicatedStorage.Modules.BrainrotLooks (213 recipes)
- BrainrotBodyBuilder.lua -> ReplicatedStorage.Modules.BrainrotBodyBuilder
- BrainrotModelFactory.lua -> ServerScriptService.BrainrotModelFactory (runtime safety net; models are also baked into ServerStorage.BrainrotModels)
- BrainrotIdleClient.lua -> StarterPlayer.StarterPlayerScripts.BrainrotIdleClient
- IndexPatch.txt -> applied to IndexClient (viewport thumbnails + silhouettes)

Also in Studio but not mirrored: a 7-line HeightScale patch in BrainrotSpawner.buildModelVisual (size ladder on plots, clamped 0.7-1.5).

## Vault & Tide (installed 2026-07-25, DORMANT until launch)
- SupplySchedule.lua -> ReplicatedStorage.Modules.SupplySchedule (clock brain; SET SEASONS[1].Starts AT LAUNCH)
- BrainrotWaves.lua -> ReplicatedStorage.Modules.BrainrotWaves (adapter + FORCE_ON/VAULTED + OverrideKey)
- RarityRoll.lua -> ServerScriptService.Modules.RarityRoll (period-keyed pool cache)
- LimitedStock.lua -> ServerScriptService.Modules.LimitedStock (12-name cap ladder; collaborator's file, config-only change)
- Not mirrored: ThrowHandler mid-flight recheck (9 lines before the IsLimited claim block), Main's GetSupplySnapshot wiring, IndexClient badge patch (availabilityOf/status copy/refreshAvailability/refreshSupplySnap).

## Perfect-throw fix (2026-07-25)
- ThrowHandler: GetSweetSpot RemoteFunction (single-use band, 30s age), perfect judged server-side vs thrown power; clientPerfect arg deliberately unread.
- ClientMain.randomizeSweetSpot: fetches and DRAWS the server band (token-guarded, sentinel -1 until answered).
- Verified via ThrowResult.Perfect: spoof (0.01,true)->false; in-band claiming false->true; out-of-band with fresh band->false.

## IconForge (2026-07-25)
- IconForge.lua -> ReplicatedStorage.Modules.IconForge: 3D primitive icon models rendered as stacked static ViewportFrames (shadow + ink outline + icon), bounding-box camera fit. Rail-ready kinds: gift/target/star/book/trophy. Draft kinds needing another pass before use: tent, bag (stone is decent).
- SideRail now calls IconForge.Mount instead of drawing an emoji.

## CatchReveal (2026-07-27, Task 1 of 5)
- CatchReveal.lua -> ReplicatedStorage.Modules.CatchReveal: the catch moment -- brainrot model spinning in a ViewportFrame instead of a text card. Bands 1-3 of 4 (size/halo/shimmer/sparkle ladder over the eight rarity tiers); band 4 (Secret/God) deliberately renders as band 3 until Task 2 adds the world-model + MutationFX path.
- BrainrotThumb.lua -> ReplicatedStorage.Modules.BrainrotThumb: additive change. Extracted M.framing(model, fov) -> centre, dist and exposed M.DEFAULT_DIR, so CatchReveal can orbit a camera using the same maths add() uses to place one. add()'s own behaviour and its two callers (BackpackClient, IndexClient) are unchanged.

## CatchReveal review fixes (2026-07-27, Task 1 review round)
- UITheme.lua -> ReplicatedStorage.Modules.UITheme (first mirror): additive. Added M.GlyphFont = Enum.Font.GothamBold beside M.Font, for decorative dingbats (the cafe face M.Font may not carry glyphs like the sparkle character). Nothing else in UITheme changed.
- CatchReveal.lua updated: sparkle glyph now reads UITheme.GlyphFont instead of a hardcoded Enum.Font.GothamBold. M.play's construction (root-parenting through the RenderStepped connect and hold/fade scheduling) now runs inside one pcall; on failure it warns, tears down whatever was already built, and returns nil instead of letting the error -- and any already-parented Frame or live connection -- escape the module.
