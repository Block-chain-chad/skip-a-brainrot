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
- CatchReveal.lua -> ReplicatedStorage.Modules.CatchReveal: the catch moment -- brainrot model spinning in a ViewportFrame instead of a text card. Bands 1-3 of 4 (size/halo/shimmer/sparkle ladder over the eight rarity tiers); band 4 (Secret/God) at this point in the branch deliberately rendered as band 3, pending Task 2's world-model + MutationFX path (see below -- that path has since shipped).
- BrainrotThumb.lua -> ReplicatedStorage.Modules.BrainrotThumb: additive change. Extracted M.framing(model, fov) -> centre, dist and exposed M.DEFAULT_DIR, so CatchReveal can orbit a camera using the same maths add() uses to place one. add()'s own behaviour and its two callers (BackpackClient, IndexClient) are unchanged.

## CatchReveal review fixes (2026-07-27, Task 1 review round)
- UITheme.lua -> ReplicatedStorage.Modules.UITheme (first mirror): additive. Added M.GlyphFont = Enum.Font.GothamBold beside M.Font, for decorative dingbats (the cafe face M.Font may not carry glyphs like the sparkle character). Nothing else in UITheme changed.
- CatchReveal.lua updated: sparkle glyph now reads UITheme.GlyphFont instead of a hardcoded Enum.Font.GothamBold. M.play's construction (root-parenting through the RenderStepped connect and hold/fade scheduling) now runs inside one pcall; on failure it warns, tears down whatever was already built, and returns nil instead of letting the error -- and any already-parented Frame or live connection -- escape the module.

## CatchReveal Tasks 2-4 (2026-07-27, world model, mutations, wiring)
- CatchReveal.lua updated: band 4 (Secret/God) now renders the REAL path described in the module header -- a real world model in front of a locked camera with a black backdrop Part, MutationFX applied to the live model, a line-of-sight raycast that falls back to the band-3-style viewport when the spot is blocked, and a camera-restore watchdog. No longer falls through to band 3 by default.
- CatchRevealClient.lua -> StarterPlayer.StarterPlayerScripts.CatchRevealClient (new LocalScript): subscribes to remotes.ThrowResult and calls CatchReveal.play. Deliberately thin -- `shouldReveal` is the seam Phase 2's gamepass skip plugs into later.
- ClientMainCatchPatch.txt -> applied to ClientMain (two patches, not mirrored as a full file since ClientMain is collaborator-live-edited and the repo copy was already stale at patch time -- see the file's own NOTES for how the anchors were verified): (1) retires the old resultFrame text card behind `if true then return end`, one-block-revertible; (2) celebrateCatch early-returns for Secret/God so band 4's camera lock never fights the pillar/shake FX.

## CatchReveal Task 5 final fix wave (2026-07-27)
- CatchReveal.lua updated: band-4 model scaling now bounds the CONTINUOUSLY-SPINNING model's horizontal half-diagonal sweep (not height alone) against both the camera and the backdrop, following the min(height, width) clamp pattern BrainrotSpawner/InventoryHandler use for their static displays, adapted for a rotating one; MIN_MODEL_DIST is now a real floor (bails to the viewport instead of computing a non-positive distance when charDist collapses); the model opens front-quarter (BrainrotThumb.DEFAULT_DIR's yaw folded into the start pose) instead of facing away; the spin axis is world Y instead of the camera's own (pitch-tilted) up vector; the backdrop now fades out with the rest of the reveal instead of snapping; and the one-frame placement flash at the model's authored map coordinates is gone (posed before parenting).

## Sell-list thumbnails + close-button X fix (2026-07-27, design doc: docs/specs/2026-07-27-sell-list-and-close-button-design.md)
Two independent client-UI bug fixes, zero server/remote/economy change.

- UITheme.lua updated: `M.styleClose` no longer sets `btn.Text` (was `"\u{2715}"`, U+2715, which does not render in this Roblox build -- every close button drew as a bare red circle, confirmed by a live 5-candidate proof board). The X is now drawn as two rotated `Frame`s ("CloseXBar"), sized relative to the button (UDim2 Scale, not Offset, so the same code is correct at UITheme's 30px and UIStyle's 34px), white-on-red, idempotent (any previous call's bars are destroyed before redraw). ZIndex is NOT set once at draw time and left alone -- it tracks the button's own ZIndex live via `GetPropertyChangedSignal("ZIndex")`, because MainUI's Global ZIndexBehavior compares ZIndex across the whole tree rather than cascading a parent's Z to its children; `IndexClient` deliberately sets `closeBtn.ZIndex = 18` AFTER calling `styleClose` (which forces ZIndex 6), and a bar frozen at the old Z would end up UNDER the button's own now-higher-Z opaque fill, reproducing the same invisible-X bug in a new form. Verified live: bars tracked 6->7 and 18->19 correctly across that exact sequence. 7 call sites / 9 panels inherit the fix automatically (no per-panel edits): RebirthClient, QuestClient (Goals), DailyRewardClient, FusionClient, IndexClient, MerchantClient, and ClientMain's shared loop (Shop + Sell).
- UIStyle.lua -> ReplicatedStorage.Modules.UIStyle (NEW mirror, first time this file is tracked in game-src/): `UIStyle.styleClose` had its own identical `"\u{2715}"` bug (used only by SeasonClient). Given its own independent copy of the same bar-drawing fix rather than a `require(UITheme)` -- UIStyle is a collaborator's module (see its own header comment), and making it depend on UITheme is an architectural call for them to make, not something a bug fix should decide. User explicitly approved fixing this module too.
- IndexClient: one stale comment corrected (`IndexPatch.txt` ADDENDUM section) -- `-- keep GothamBold from styleClose: FredokaOne has no U+2715 glyph` blamed the font and claimed pinning GothamBold fixed the missing glyph. It never did: the proof board rendered in GothamBold and was still blank, because U+2715 is simply absent from the build, not font-specific. No behavior change, comment only.
- ClientMainSellThumbPatch.txt -> applied to ClientMain (not mirrored as a full file; collaborator-live-edited, same caveat as `ClientMainCatchPatch.txt`): `buildSellList`'s icon tile swaps its flat 34px rarity-coloured circle for a real 3D model via `BrainrotThumb.add(icon, name, opts)` (the same shared module the backpack grid and catch reveal use), sunburst backdrop kept. The tier colour that circle used to carry moves to the icon tile's own border stroke (`UITheme.stroke` in place of the old hardcoded-black `UITheme.ink`), matching how the backpack grid carries rarity on its tile border. Falls back to the old flat circle when `BrainrotThumb.master(name)` returns nil -- `Maxwell` is the only such case of 151 at patch time; verified live that its row shows the coloured circle (with a matching border) rather than an empty tile.
- Verified live in Play mode: all 9 panels' close buttons showed a visible X and still closed on click (Index, Sell, Rebirth, Goals, Daily, Merchant confirmed via real open + real click-to-close; Shop and Fusion confirmed via a briefly forced `Visible = true` since their normal open paths need an owned plot/campfire or are superseded by MerchantClient in current gameplay -- disclosed, then reverted). Sell panel verified with a real mixed 66-name inventory (walked to the stall, pressed E, went through Marco the Buyer's dialogue) showing real spinning-free 3D thumbnails with tier-coloured borders, plus the Maxwell no-model fallback. Console stayed clean throughout. Collaborator `yeep1234` joined the live session partway through verification; only the files listed above were touched.
