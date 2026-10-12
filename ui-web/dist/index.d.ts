/**
 * @skip-a-brainrot/ui — the web mirror of the game's in-game UI kit.
 *
 * Every component here is a port of a builder in
 * `ReplicatedStorage/Modules/UIKit/Builders.lua` or `UITheme.lua`, styled from
 * `src/tokens.ts` — a one-for-one port of `UIKit/Tokens.lua`.
 *
 * Import the stylesheet once at the root of your app:
 *   import '@skip-a-brainrot/ui/styles.css'
 */
export { Surface, type SurfaceProps, type SurfaceKind } from './components/Surface';
export { Panel, PanelHeader, type PanelProps, type PanelHeaderProps } from './components/Panel';
export { Button, type ButtonProps, type ButtonVariant, type ButtonSize } from './components/Button';
export { CloseButton, type CloseButtonProps } from './components/CloseButton';
export { Label, type LabelProps, type LabelStyle } from './components/Label';
export { Badge, type BadgeProps } from './components/Badge';
export { Ribbon, type RibbonProps, type RibbonVariant } from './components/Ribbon';
export { ProgressTrack, type ProgressTrackProps } from './components/ProgressTrack';
export { ArtSlot, type ArtSlotProps } from './components/ArtSlot';
export { RarityTile, type RarityTileProps, type Rarity } from './components/RarityTile';
export { CurrencyPill, type CurrencyPillProps } from './components/CurrencyPill';
export { Icon, iconNames, type IconProps, type IconName } from './components/Icon';
export { NavRail, NavRailItem, type NavRailProps, type NavRailItemProps } from './components/NavRail';
export { TabBar, type TabBarProps, type TabItem } from './components/TabBar';
export { RewardCard, type RewardCardProps } from './components/RewardCard';
export { QuestRow, type QuestRowProps } from './components/QuestRow';
export { Toast, type ToastProps, type ToastTone } from './components/Toast';
export { AccentCard, accentFill, type AccentCardProps } from './components/AccentCard';
export { Medallion, type MedallionProps } from './components/Medallion';
export * as tokens from './tokens';
export { gradientCss, type GradientName, type TextStyle } from './tokens';
