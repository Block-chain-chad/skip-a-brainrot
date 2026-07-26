# game-src — mirrors of Studio scripts (visual system, shipped 2026-07-25)

The live source of truth is Roblox Studio. These are commit-time mirrors:
- BrainrotLooks.lua -> ReplicatedStorage.Modules.BrainrotLooks (213 recipes)
- BrainrotBodyBuilder.lua -> ReplicatedStorage.Modules.BrainrotBodyBuilder
- BrainrotModelFactory.lua -> ServerScriptService.BrainrotModelFactory (runtime safety net; models are also baked into ServerStorage.BrainrotModels)
- BrainrotIdleClient.lua -> StarterPlayer.StarterPlayerScripts.BrainrotIdleClient
- IndexPatch.txt -> applied to IndexClient (viewport thumbnails + silhouettes)

Also in Studio but not mirrored: a 7-line HeightScale patch in BrainrotSpawner.buildModelVisual (size ladder on plots, clamped 0.7-1.5).
