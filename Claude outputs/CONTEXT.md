# Skip Rocks for Brainrots - full project context

Roblox game by Terra. This bundle is the complete source mirror of the live place plus design docs.
Generated 2026-09-17 from C:\Users\m\Coding\skip-a-brainrot

## How to read this
- game-src/place-full/ mirrors the Roblox place tree exactly: ReplicatedStorage/Modules (shared config + modules), ServerScriptService (server logic), StarterPlayer/StarterPlayerScripts (client), StarterGui, Workspace.
- *.server.lua = Script, *.client.lua = LocalScript, plain .lua = ModuleScript.
- game-src/place-full/_MANIFEST.txt lists every instance in the place.
- docs/ holds the design specs, brainrot lexicon/build standard, the full brainrot data dump (brainrot-dump.json) and handoff notes.
- Old AuditBackups and retired files were left out on purpose.

## File tree
```
CONTEXT.md
docs/HANDOFF-2026-08-04.md
docs/brainrot-build-standard.md
docs/brainrot-dump.json
docs/brainrot-lexicon.md
docs/cove-rebuild-woah-2026-08-09.md
docs/monetization-plan-2026-08-04.md
docs/ps99-restyle-recovery-2026-08-16.md
docs/specs/2026-07-25-bounded-supply-design.md
docs/specs/2026-07-25-brainrot-visuals-design.md
docs/specs/2026-07-25-cafe-restyle-design.md
docs/specs/2026-07-27-catch-reveal-design.md
docs/specs/2026-07-27-sell-list-and-close-button-design.md
docs/specs/2026-07-27-wheel-candy-restyle-design.md
docs/specs/2026-07-28-forest-egg-shop-design.md
docs/specs/2026-07-30-ui-overhaul-design.md
game-src/README.md
game-src/eggs/models-build-log.md
game-src/place-full/README.md
game-src/place-full/ReplicatedStorage/Modules/BrainrotBodyBuilder.lua
game-src/place-full/ReplicatedStorage/Modules/BrainrotConfig.lua
game-src/place-full/ReplicatedStorage/Modules/BrainrotConfigTundra.lua
game-src/place-full/ReplicatedStorage/Modules/BrainrotLooks.lua
game-src/place-full/ReplicatedStorage/Modules/BrainrotThumb.lua
game-src/place-full/ReplicatedStorage/Modules/BrainrotWaves.lua
game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/AudioBus.lua
game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/BrainrotRig.lua
game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/Bridge.lua
game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/CameraRig.lua
game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/Config.lua
game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/HypeUI.lua
game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/PostFX.lua
game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/RockRig.lua
game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/ScreenShake.lua
game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/Sequencer.lua
game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/Types.lua
game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/WaterFX.lua
game-src/place-full/ReplicatedStorage/Modules/CatchFX.lua
game-src/place-full/ReplicatedStorage/Modules/CatchReveal.lua
game-src/place-full/ReplicatedStorage/Modules/DialogueConfig.lua
game-src/place-full/ReplicatedStorage/Modules/EggConfig.lua
game-src/place-full/ReplicatedStorage/Modules/GamepassConfig.lua
game-src/place-full/ReplicatedStorage/Modules/IconForge.lua
game-src/place-full/ReplicatedStorage/Modules/MassiveEmergence.lua
game-src/place-full/ReplicatedStorage/Modules/MerchantConfig.lua
game-src/place-full/ReplicatedStorage/Modules/MerchantDialog.lua
game-src/place-full/ReplicatedStorage/Modules/MutationConfig.lua
game-src/place-full/ReplicatedStorage/Modules/MutationFX.lua
game-src/place-full/ReplicatedStorage/Modules/NumberFormat.lua
game-src/place-full/ReplicatedStorage/Modules/OfferingConfig.lua
game-src/place-full/ReplicatedStorage/Modules/PetConfig.lua
game-src/place-full/ReplicatedStorage/Modules/PityConfig.lua
game-src/place-full/ReplicatedStorage/Modules/PullCeremony.lua
game-src/place-full/ReplicatedStorage/Modules/RarityConfig.lua
game-src/place-full/ReplicatedStorage/Modules/RarityCurve.lua
game-src/place-full/ReplicatedStorage/Modules/RarityFX.lua
game-src/place-full/ReplicatedStorage/Modules/RebirthConfig.lua
game-src/place-full/ReplicatedStorage/Modules/RockConfig.lua
game-src/place-full/ReplicatedStorage/Modules/RockDesign.lua
game-src/place-full/ReplicatedStorage/Modules/SeasonConfig.lua
game-src/place-full/ReplicatedStorage/Modules/SideRail.lua
game-src/place-full/ReplicatedStorage/Modules/SoundKit.lua
game-src/place-full/ReplicatedStorage/Modules/SupplySchedule.lua
game-src/place-full/ReplicatedStorage/Modules/TungQuestConfig.lua
game-src/place-full/ReplicatedStorage/Modules/UIKit/Builders.lua
game-src/place-full/ReplicatedStorage/Modules/UIKit/IconArt.lua
game-src/place-full/ReplicatedStorage/Modules/UIKit/SpecTheme.lua
game-src/place-full/ReplicatedStorage/Modules/UIKit/Tokens.lua
game-src/place-full/ReplicatedStorage/Modules/UIStyle.lua
game-src/place-full/ReplicatedStorage/Modules/UITheme.lua
game-src/place-full/ReplicatedStorage/Modules/UpgradeConfig.lua
game-src/place-full/ReplicatedStorage/Modules/WheelConfig.lua
game-src/place-full/ServerScriptService/CellarDoor.server.lua
game-src/place-full/ServerScriptService/CenterpieceSpinner.server.lua
game-src/place-full/ServerScriptService/CinematicCommand.server.lua
game-src/place-full/ServerScriptService/EggStallIdle.server.lua
game-src/place-full/ServerScriptService/ItemStatsService.server.lua
game-src/place-full/ServerScriptService/Main.server.lua
game-src/place-full/ServerScriptService/Modules/BoothHandler.lua
game-src/place-full/ServerScriptService/Modules/BoundsGuard.lua
game-src/place-full/ServerScriptService/Modules/BrainrotMover.lua
game-src/place-full/ServerScriptService/Modules/BrainrotSpawner.lua
game-src/place-full/ServerScriptService/Modules/CodeConfig.lua
game-src/place-full/ServerScriptService/Modules/DailyRewardHandler.lua
game-src/place-full/ServerScriptService/Modules/DarrelService.lua
game-src/place-full/ServerScriptService/Modules/DevWeather.lua
game-src/place-full/ServerScriptService/Modules/EggHandler.lua
game-src/place-full/ServerScriptService/Modules/FusionHandler.lua
game-src/place-full/ServerScriptService/Modules/GamepassService.lua
game-src/place-full/ServerScriptService/Modules/GianlucaQuest.lua
game-src/place-full/ServerScriptService/Modules/IncomeLoop.lua
game-src/place-full/ServerScriptService/Modules/InventoryHandler.lua
game-src/place-full/ServerScriptService/Modules/LeaderboardBoards.lua
game-src/place-full/ServerScriptService/Modules/LeaderboardHandler.lua
game-src/place-full/ServerScriptService/Modules/LimitedStock.lua
game-src/place-full/ServerScriptService/Modules/MaxwellQuest.lua
game-src/place-full/ServerScriptService/Modules/MintRegistry.lua
game-src/place-full/ServerScriptService/Modules/OfferingHandler.lua
game-src/place-full/ServerScriptService/Modules/OfflineEarningsHandler.lua
game-src/place-full/ServerScriptService/Modules/PetHandler.lua
game-src/place-full/ServerScriptService/Modules/PlayerDataManager.lua
game-src/place-full/ServerScriptService/Modules/PlotBoardHandler.lua
game-src/place-full/ServerScriptService/Modules/PriceIndex.lua
game-src/place-full/ServerScriptService/Modules/ProductRegistry.lua
game-src/place-full/ServerScriptService/Modules/QuestHandler.lua
game-src/place-full/ServerScriptService/Modules/RarityRoll.lua
game-src/place-full/ServerScriptService/Modules/RebirthHandler.lua
game-src/place-full/ServerScriptService/Modules/SeasonPassHandler.lua
game-src/place-full/ServerScriptService/Modules/SellHandler.lua
game-src/place-full/ServerScriptService/Modules/SessionLock.lua
game-src/place-full/ServerScriptService/Modules/SettingsService.lua
game-src/place-full/ServerScriptService/Modules/ShopHandler.lua
game-src/place-full/ServerScriptService/Modules/ThrowHandler.lua
game-src/place-full/ServerScriptService/Modules/TradeHandler.lua
game-src/place-full/ServerScriptService/Modules/TungQuest.lua
game-src/place-full/ServerScriptService/Modules/UpgradeHandler.lua
game-src/place-full/ServerScriptService/Modules/WeatherHandler.lua
game-src/place-full/ServerScriptService/Modules/WheelBoard.lua
game-src/place-full/ServerScriptService/Modules/WheelHandler.lua
game-src/place-full/ServerScriptService/TeleportService.server.lua
game-src/place-full/StarterGui/ScreenGui/Model/Model/Script.server.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/BackpackClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/BoothClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/BrainrotHoldClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/BrainrotIdleClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/BrainrotPlaceClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/CampfireBankClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/CatDialogueClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/CatchRevealClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/CinematicClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/ClientMain.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/DailyRewardClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/DarrelHUDClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/DevWeatherClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/EggShopClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/FootstepClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/FusionClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDPanels/BackpackPanel.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDPanels/DailyPanel.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDPanels/GoalsPanel.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDPanels/IndexPanel.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDPanels/PassPanel.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDPanels/SettingsPanel.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDPanels/ShopPanel.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/GianlucaClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/IndexClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/InventoryClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/LakeAmbience.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/LuckHUDClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/MerchantClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/MusicClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/OfflineEarningsClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/PityThrowClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/PlotBillboardVisibility.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/PlotSignClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/QuestBarClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/QuestClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/QuestTrackerClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/RareCatchClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/RebirthClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/SeasonClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/ToastClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/TradeClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/TutorialClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/UIPolish.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/WeatherClient.client.lua
game-src/place-full/StarterPlayer/StarterPlayerScripts/WheelClient.client.lua
game-src/place-full/Workspace/GameWorld/TradingWorld/CoveDressing.CoveDriver.server.lua
game-src/place-full/Workspace/GameWorld/TradingWorld/EternalSkip.SkipLoop.server.lua
game-src/place-full/Workspace/TitleScaler.server.lua
game-src/place-full/_MANIFEST.txt
game-src/ui/icon-assets.md
```

## File sizes
```
     12381  CONTEXT.md
     14937  docs/HANDOFF-2026-08-04.md
     26461  docs/brainrot-build-standard.md
   1537993  docs/brainrot-dump.json
     22064  docs/brainrot-lexicon.md
     10342  docs/cove-rebuild-woah-2026-08-09.md
      8747  docs/monetization-plan-2026-08-04.md
      3458  docs/ps99-restyle-recovery-2026-08-16.md
      8559  docs/specs/2026-07-25-bounded-supply-design.md
      7989  docs/specs/2026-07-25-brainrot-visuals-design.md
      9469  docs/specs/2026-07-25-cafe-restyle-design.md
     12316  docs/specs/2026-07-27-catch-reveal-design.md
      7247  docs/specs/2026-07-27-sell-list-and-close-button-design.md
     10169  docs/specs/2026-07-27-wheel-candy-restyle-design.md
     10868  docs/specs/2026-07-28-forest-egg-shop-design.md
      7854  docs/specs/2026-07-30-ui-overhaul-design.md
     13899  game-src/README.md
     36756  game-src/eggs/models-build-log.md
      1795  game-src/place-full/README.md
     48282  game-src/place-full/ReplicatedStorage/Modules/BrainrotBodyBuilder.lua
     20432  game-src/place-full/ReplicatedStorage/Modules/BrainrotConfig.lua
     16010  game-src/place-full/ReplicatedStorage/Modules/BrainrotConfigTundra.lua
     33962  game-src/place-full/ReplicatedStorage/Modules/BrainrotLooks.lua
      3242  game-src/place-full/ReplicatedStorage/Modules/BrainrotThumb.lua
      2263  game-src/place-full/ReplicatedStorage/Modules/BrainrotWaves.lua
      9234  game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/AudioBus.lua
     21013  game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/BrainrotRig.lua
      9523  game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/Bridge.lua
     17524  game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/CameraRig.lua
      6842  game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/Config.lua
     35508  game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/HypeUI.lua
      6407  game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/PostFX.lua
      7778  game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/RockRig.lua
      2632  game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/ScreenShake.lua
     54645  game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/Sequencer.lua
       487  game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/Types.lua
     26290  game-src/place-full/ReplicatedStorage/Modules/CatchCinematic/WaterFX.lua
      7144  game-src/place-full/ReplicatedStorage/Modules/CatchFX.lua
     36740  game-src/place-full/ReplicatedStorage/Modules/CatchReveal.lua
      1257  game-src/place-full/ReplicatedStorage/Modules/DialogueConfig.lua
      3137  game-src/place-full/ReplicatedStorage/Modules/EggConfig.lua
      2802  game-src/place-full/ReplicatedStorage/Modules/GamepassConfig.lua
     12860  game-src/place-full/ReplicatedStorage/Modules/IconForge.lua
      9630  game-src/place-full/ReplicatedStorage/Modules/MassiveEmergence.lua
      1890  game-src/place-full/ReplicatedStorage/Modules/MerchantConfig.lua
      5435  game-src/place-full/ReplicatedStorage/Modules/MerchantDialog.lua
      8145  game-src/place-full/ReplicatedStorage/Modules/MutationConfig.lua
      4829  game-src/place-full/ReplicatedStorage/Modules/MutationFX.lua
      2377  game-src/place-full/ReplicatedStorage/Modules/NumberFormat.lua
      1332  game-src/place-full/ReplicatedStorage/Modules/OfferingConfig.lua
      7350  game-src/place-full/ReplicatedStorage/Modules/PetConfig.lua
       750  game-src/place-full/ReplicatedStorage/Modules/PityConfig.lua
     16825  game-src/place-full/ReplicatedStorage/Modules/PullCeremony.lua
      1146  game-src/place-full/ReplicatedStorage/Modules/RarityConfig.lua
      2975  game-src/place-full/ReplicatedStorage/Modules/RarityCurve.lua
      5867  game-src/place-full/ReplicatedStorage/Modules/RarityFX.lua
      2153  game-src/place-full/ReplicatedStorage/Modules/RebirthConfig.lua
      6513  game-src/place-full/ReplicatedStorage/Modules/RockConfig.lua
      9416  game-src/place-full/ReplicatedStorage/Modules/RockDesign.lua
      1980  game-src/place-full/ReplicatedStorage/Modules/SeasonConfig.lua
     24665  game-src/place-full/ReplicatedStorage/Modules/SideRail.lua
     20094  game-src/place-full/ReplicatedStorage/Modules/SoundKit.lua
      8267  game-src/place-full/ReplicatedStorage/Modules/SupplySchedule.lua
      1437  game-src/place-full/ReplicatedStorage/Modules/TungQuestConfig.lua
     18758  game-src/place-full/ReplicatedStorage/Modules/UIKit/Builders.lua
     32557  game-src/place-full/ReplicatedStorage/Modules/UIKit/IconArt.lua
      8105  game-src/place-full/ReplicatedStorage/Modules/UIKit/SpecTheme.lua
     16220  game-src/place-full/ReplicatedStorage/Modules/UIKit/Tokens.lua
     24087  game-src/place-full/ReplicatedStorage/Modules/UIStyle.lua
     39304  game-src/place-full/ReplicatedStorage/Modules/UITheme.lua
      3819  game-src/place-full/ReplicatedStorage/Modules/UpgradeConfig.lua
      4136  game-src/place-full/ReplicatedStorage/Modules/WheelConfig.lua
      4241  game-src/place-full/ServerScriptService/CellarDoor.server.lua
       854  game-src/place-full/ServerScriptService/CenterpieceSpinner.server.lua
     12528  game-src/place-full/ServerScriptService/CinematicCommand.server.lua
     12396  game-src/place-full/ServerScriptService/EggStallIdle.server.lua
      5194  game-src/place-full/ServerScriptService/ItemStatsService.server.lua
      6852  game-src/place-full/ServerScriptService/Main.server.lua
     17593  game-src/place-full/ServerScriptService/Modules/BoothHandler.lua
      6450  game-src/place-full/ServerScriptService/Modules/BoundsGuard.lua
      5477  game-src/place-full/ServerScriptService/Modules/BrainrotMover.lua
     12764  game-src/place-full/ServerScriptService/Modules/BrainrotSpawner.lua
       333  game-src/place-full/ServerScriptService/Modules/CodeConfig.lua
      4571  game-src/place-full/ServerScriptService/Modules/DailyRewardHandler.lua
      4888  game-src/place-full/ServerScriptService/Modules/DarrelService.lua
      3715  game-src/place-full/ServerScriptService/Modules/DevWeather.lua
      5676  game-src/place-full/ServerScriptService/Modules/EggHandler.lua
      6007  game-src/place-full/ServerScriptService/Modules/FusionHandler.lua
      4163  game-src/place-full/ServerScriptService/Modules/GamepassService.lua
      8901  game-src/place-full/ServerScriptService/Modules/GianlucaQuest.lua
      8213  game-src/place-full/ServerScriptService/Modules/IncomeLoop.lua
     16429  game-src/place-full/ServerScriptService/Modules/InventoryHandler.lua
     13399  game-src/place-full/ServerScriptService/Modules/LeaderboardBoards.lua
      9701  game-src/place-full/ServerScriptService/Modules/LeaderboardHandler.lua
      4561  game-src/place-full/ServerScriptService/Modules/LimitedStock.lua
      7964  game-src/place-full/ServerScriptService/Modules/MaxwellQuest.lua
     18569  game-src/place-full/ServerScriptService/Modules/MintRegistry.lua
      5054  game-src/place-full/ServerScriptService/Modules/OfferingHandler.lua
      2886  game-src/place-full/ServerScriptService/Modules/OfflineEarningsHandler.lua
     20797  game-src/place-full/ServerScriptService/Modules/PetHandler.lua
     39944  game-src/place-full/ServerScriptService/Modules/PlayerDataManager.lua
     15684  game-src/place-full/ServerScriptService/Modules/PlotBoardHandler.lua
     12835  game-src/place-full/ServerScriptService/Modules/PriceIndex.lua
      3702  game-src/place-full/ServerScriptService/Modules/ProductRegistry.lua
      5562  game-src/place-full/ServerScriptService/Modules/QuestHandler.lua
      5324  game-src/place-full/ServerScriptService/Modules/RarityRoll.lua
      3014  game-src/place-full/ServerScriptService/Modules/RebirthHandler.lua
      3554  game-src/place-full/ServerScriptService/Modules/SeasonPassHandler.lua
      4281  game-src/place-full/ServerScriptService/Modules/SellHandler.lua
      6154  game-src/place-full/ServerScriptService/Modules/SessionLock.lua
     10269  game-src/place-full/ServerScriptService/Modules/SettingsService.lua
      2360  game-src/place-full/ServerScriptService/Modules/ShopHandler.lua
     56016  game-src/place-full/ServerScriptService/Modules/ThrowHandler.lua
     18283  game-src/place-full/ServerScriptService/Modules/TradeHandler.lua
      5234  game-src/place-full/ServerScriptService/Modules/TungQuest.lua
      1469  game-src/place-full/ServerScriptService/Modules/UpgradeHandler.lua
      7005  game-src/place-full/ServerScriptService/Modules/WeatherHandler.lua
     17221  game-src/place-full/ServerScriptService/Modules/WheelBoard.lua
      6572  game-src/place-full/ServerScriptService/Modules/WheelHandler.lua
     19214  game-src/place-full/ServerScriptService/TeleportService.server.lua
        22  game-src/place-full/StarterGui/ScreenGui/Model/Model/Script.server.lua
     27554  game-src/place-full/StarterPlayer/StarterPlayerScripts/BackpackClient.client.lua
     27300  game-src/place-full/StarterPlayer/StarterPlayerScripts/BoothClient.client.lua
      3363  game-src/place-full/StarterPlayer/StarterPlayerScripts/BrainrotHoldClient.client.lua
     11255  game-src/place-full/StarterPlayer/StarterPlayerScripts/BrainrotIdleClient.client.lua
      4725  game-src/place-full/StarterPlayer/StarterPlayerScripts/BrainrotPlaceClient.client.lua
     23390  game-src/place-full/StarterPlayer/StarterPlayerScripts/CampfireBankClient.client.lua
      3598  game-src/place-full/StarterPlayer/StarterPlayerScripts/CatDialogueClient.client.lua
      9802  game-src/place-full/StarterPlayer/StarterPlayerScripts/CatchRevealClient.client.lua
     14872  game-src/place-full/StarterPlayer/StarterPlayerScripts/CinematicClient.client.lua
    125083  game-src/place-full/StarterPlayer/StarterPlayerScripts/ClientMain.client.lua
      9578  game-src/place-full/StarterPlayer/StarterPlayerScripts/DailyRewardClient.client.lua
      8464  game-src/place-full/StarterPlayer/StarterPlayerScripts/DarrelHUDClient.client.lua
      3560  game-src/place-full/StarterPlayer/StarterPlayerScripts/DevWeatherClient.client.lua
    207910  game-src/place-full/StarterPlayer/StarterPlayerScripts/EggShopClient.client.lua
      6739  game-src/place-full/StarterPlayer/StarterPlayerScripts/FootstepClient.client.lua
     19677  game-src/place-full/StarterPlayer/StarterPlayerScripts/FusionClient.client.lua
     72612  game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDClient.client.lua
    140437  game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDPanels/BackpackPanel.lua
     36342  game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDPanels/DailyPanel.lua
     48949  game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDPanels/GoalsPanel.lua
     51906  game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDPanels/IndexPanel.lua
     39005  game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDPanels/PassPanel.lua
     53183  game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDPanels/SettingsPanel.lua
     26350  game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDPanels/ShopPanel.lua
      4718  game-src/place-full/StarterPlayer/StarterPlayerScripts/GianlucaClient.client.lua
     34936  game-src/place-full/StarterPlayer/StarterPlayerScripts/IndexClient.client.lua
       724  game-src/place-full/StarterPlayer/StarterPlayerScripts/InventoryClient.client.lua
      3918  game-src/place-full/StarterPlayer/StarterPlayerScripts/LakeAmbience.client.lua
     14414  game-src/place-full/StarterPlayer/StarterPlayerScripts/LuckHUDClient.client.lua
     26712  game-src/place-full/StarterPlayer/StarterPlayerScripts/MerchantClient.client.lua
      6396  game-src/place-full/StarterPlayer/StarterPlayerScripts/MusicClient.client.lua
      3716  game-src/place-full/StarterPlayer/StarterPlayerScripts/OfflineEarningsClient.client.lua
      2607  game-src/place-full/StarterPlayer/StarterPlayerScripts/PityThrowClient.client.lua
      1785  game-src/place-full/StarterPlayer/StarterPlayerScripts/PlotBillboardVisibility.client.lua
     15491  game-src/place-full/StarterPlayer/StarterPlayerScripts/PlotSignClient.client.lua
      5288  game-src/place-full/StarterPlayer/StarterPlayerScripts/QuestBarClient.client.lua
      6222  game-src/place-full/StarterPlayer/StarterPlayerScripts/QuestClient.client.lua
     13675  game-src/place-full/StarterPlayer/StarterPlayerScripts/QuestTrackerClient.client.lua
      9472  game-src/place-full/StarterPlayer/StarterPlayerScripts/RareCatchClient.client.lua
     13107  game-src/place-full/StarterPlayer/StarterPlayerScripts/RebirthClient.client.lua
     12159  game-src/place-full/StarterPlayer/StarterPlayerScripts/SeasonClient.client.lua
      6181  game-src/place-full/StarterPlayer/StarterPlayerScripts/ToastClient.client.lua
     30596  game-src/place-full/StarterPlayer/StarterPlayerScripts/TradeClient.client.lua
      9873  game-src/place-full/StarterPlayer/StarterPlayerScripts/TutorialClient.client.lua
      8340  game-src/place-full/StarterPlayer/StarterPlayerScripts/UIPolish.client.lua
     52607  game-src/place-full/StarterPlayer/StarterPlayerScripts/WeatherClient.client.lua
     48911  game-src/place-full/StarterPlayer/StarterPlayerScripts/WheelClient.client.lua
      7706  game-src/place-full/Workspace/GameWorld/TradingWorld/CoveDressing.CoveDriver.server.lua
      1615  game-src/place-full/Workspace/GameWorld/TradingWorld/EternalSkip.SkipLoop.server.lua
       878  game-src/place-full/Workspace/TitleScaler.server.lua
     13070  game-src/place-full/_MANIFEST.txt
      3807  game-src/ui/icon-assets.md
```
