# Chunky-Cartoon UI Overhaul — Integration Spec (Phase 1)

Date: 2026-07-30 · Status: for user review · Visual authority: `docs/design-handoff/ui-kit/design_handoff_game_ui/` (README.md + tokens.lua + ui_builders.lua + data_schema.lua + states.md + interactive reference). The kit's numbers are FINAL; this spec adds only the game-side integration the kit cannot know.

## User decisions (2026-07-30)

| Decision | Choice |
|---|---|
| Currency pills while panel open | HIDE (kit behavior) |
| Scope | Kit's 6 panels + HUD shell only; other surfaces unchanged until Phase 2 |
| Goals mapping | CONSOLIDATE all three quest systems into the one Goals panel |
| Settings "Reset Data" | EXCLUDED — rebirth is the only reset mechanic |
| PNG visual targets | Requested from the design tool; build proceeds from README numbers + interactive reference meanwhile |
| Palette (2026-07-30) | Kit colors CONFIRMED as-is ("style kit" clarified: structure is law; user accepted the kit palette). Tokens still split structure-vs-theme for future re-theming |
| Icons (2026-07-30) | Kit v2 ships 8 SVGs (`icons/`). Pipeline: browser-rasterize → PNG → CreateAssetAsync upload PILOT (real account assets — natively persistent, unlike EditableMesh place content); fallback = user bulk-import. Rail + currency use real icons Phase 1. Backpack tab icons (pet/charm/egg) + brainrot icon requested from the design tool |

## What ships (Phase 1)

New ScreenGui `GameHUD` (kit's 1350×775 UIScale canvas) containing: currency cluster (top-left: coin pill = Cash, gem pill = Darrels), right-side nav rail (Bag · Pass · Daily · Goals · Index · Settings), and the six kit panels rebuilt to spec.

## Replacement map

| Kit surface | Replaces | Data source (existing, unchanged) |
|---|---|---|
| Currency cluster | ClientMain cash pill + DarrelHUDClient chip | DataUpdated (cash) + DarrelUpdate/DarrelState (darrels) |
| Nav rail (right) | SideRail's visual rail (left) | — |
| Season Pass panel | SeasonClient panel | SeasonState/SeasonClaim remotes, SeasonPassHandler |
| Backpack panel | BackpackClient panel | DataUpdated + EquipBrainrot remote, BrainrotThumb renders |
| Daily Rewards panel | DailyRewardClient panel | DailyState/DailyClaim remotes |
| Index panel | IndexClient panel | existing index pipeline + vault badges + FOREST EGG badge + mint counts (kit tile EXTENDED to carry these — see Index notes) |
| Goals panel | QuestClient (milestones) + the shop-panel daily-quest list + season-quest surface | see Goals consolidation |
| Settings panel | NEW | see Settings notes |

**Retire (Enabled=false, kept for rollback):** SeasonClient/BackpackClient/DailyRewardClient/IndexClient/QuestClient panel guis, SideRail's visual rail, DarrelHUDClient. Their SCRIPTS survive as data/wiring references until Phase 2 cleanup.

**Single-open registry:** SideRail's `registerPanel` mechanics are load-bearing for 11 existing surfaces (wheel, egg shop, fusion, shop/sell...). The new HUD adopts the SAME registry: SideRail module keeps its registry/quest-tracker-hide logic; its visual rail is hidden; the new nav rail and panels register through it. Anything that single-opened before still does.

## HUD collision resolutions

- Nav rail (right-center) collides with QuestTrackerUI's right-middle card band → **quest tracker moves to the LEFT edge**, below the currency cluster (its hide-while-panel-open behavior unchanged).
- LuckChip + SprintButton (bottom-right) sit below the rail's bottom edge at reference scale; verify at 1366×768 and 1920×1080 in Play; nudge rail gap if grazing.
- TeleportBar (top-center) untouched.

## Panel-by-panel integration notes

**Season Pass** — Free track = existing free tiers. "Buy Pass 799◆" CTA = the premium gamepass (ID placeholder; button shows "COMING SOON" disabled variant until the user creates it). "Skip N" tier-skip = dev product via ProductRegistry (placeholder id, hidden until real). XP/level = SeasonXP pipeline unchanged. Two-track claimed state maps to SeasonClaimed (free) + new SeasonClaimedPass table (schema add + migration, inert until pass exists).

**Backpack** — kit's Equip = existing hold system (EquipBrainrot). Category tabs (USER DECISION 2026-07-30): **Brainrots / Pets / Charms / Eggs**. Brainrots = current inventory grid (richest-first, held ribbons, tier sub-filter chips above the grid). Pets = the dormant pet system: while `PetConfig.ENABLED == false`, a friendly empty state ("Pets hatch soon!" + art slot); when enabled, `data.Pets` grid + equip through PetEquip. Charms = owned upgrade/charm items (read UpgradeHandler's data shape at build time; if the game stores no discrete charm items yet, empty state "Visit Enzo the Upgrader!"). Eggs = empty-state teaser pointing at Gino's stall (eggs are open-on-purchase today, not held items). "28/60 slots" counter → "N brainrots · M/6 held". "+ Slots" omitted. Rarity mapping: Common/Uncommon→common, Rare→rare, Epic→epic, Legendary→legendary, Mythic/Secret/God→mythic rainbow ring. Tab icons: bag.svg for Brainrots now; pet/charm/egg icons REQUESTED from the design tool per the README §6.1 construction rule (placeholder slots until then).

**Daily Rewards** — direct 1:1 (existing 7-day streak). Reward art slots show existing reward amounts as coin-stack text until art exists.

**Index** — kit grid + filters, EXTENDED per tile with the game's badges: FOREST EGG source badge, vault BACK IN/LAST CHANCE, N/CAP MINTED (kit "NEW" ribbon slot reused for these; layout in plan). Discovery % = existing discovered/catchable counts. 100%-reward chip = placeholder (no milestone reward wired yet — visible, "?" label).

**Goals (consolidation)** — Daily tab = DarrelService daily slate (progress live via DarrelUpdate; claims are auto-granted server-side today → rows render as auto-claiming: CLAIMABLE state flashes then CLAIMED, no claim button needed Phase 1). Weekly tab → renamed "Goals": the one-time QuestHandler milestones (QuestState/QuestClaim). Season tab = season-pass quests (SeasonState quest slice). Refresh timer chip = darrel daily UTC rollover.

**Settings** — AUDIO: Music + SFX sliders (0–100). NEW plumbing: SoundKit gains `SetCategoryVolume("music"|"sfx", 0..1)` scaling its play() volumes + SoundService Music folder; persisted per player in a new `Settings = {}` schema field (client-writable via new `SettingsSave` remote, server-validated, clamped). GRAPHICS: quality segmented control maps client-side to Lighting effect toggles (bloom/sunrays off at Low) — client-local only. GAMEPLAY toggles Phase 1: "Fast Spin" (existing wheel pref, migrates), "Hide own catch banners". Redeem Code = working UI stub → server remote validating against an EMPTY code table (extension point). NO Reset Data.

## Out of scope (Phase 1)

Egg Shop, Wheel, Merchant, Fusion, Rebirth, Shop/Sell, Offline, trade UIs (collaborator's UIStyle — NEVER touched), CatchReveal, toasts, mobile portrait pass, production art (all slots ship as labeled placeholder fills per kit).

## Acceptance (Phase 1)

1. All six panels open from the rail, match README geometry/tokens (spot-verified against reference/PNGs), single-open holds incl. legacy surfaces.
2. Currency pills live-update, hide on panel open, reappear on close; old cash pill + darrel chip gone.
3. Every claim/equip/toggle round-trips through existing server remotes; zero new client-authority.
4. Quest tracker relocated left; no HUD rect overlaps at 1366×768 and 1920×1080 (Play-measured).
5. Retired guis disabled not deleted; one-flag rollback per surface.
6. Zero red console errors through a full open-every-panel, claim-something, change-settings Play session.
