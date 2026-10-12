/**
 * Icon — the game's HUD icon set.
 *
 * GENERATED from docs/design-handoff/ui-kit/design_handoff_game_ui/icons/*.svg,
 * the same art whose 512px PNG exports are uploaded as the live rbxassetid icons
 * in Tokens.lua. Do not hand-edit: re-run scripts/gen-icons.mjs after changing an SVG.
 *
 * These predate the 2026-08-04 restyle, so their outline is the older #16170F
 * rather than Tokens.lua's current #202020. That is deliberate — this is the
 * shipped art, matching what the game renders today.
 */
import type { SVGProps } from 'react';
/** Every icon in the kit. */
export type IconName = 'bag' | 'coin' | 'daily' | 'eggs' | 'gem' | 'goals' | 'index' | 'pass' | 'plot' | 'settings' | 'shops' | 'skip';
export declare const iconNames: readonly IconName[];
export interface IconProps extends Omit<SVGProps<SVGSVGElement>, 'name'> {
    /** Which icon to render. */
    name: IconName;
    /** Width and height in px. Defaults to filling its container. */
    size?: number;
}
/**
 * Renders one of the kit's icons as inline SVG.
 *
 * @example
 * <Icon name="coin" size={42} />
 */
export declare function Icon({ name, size, className, style, ...rest }: IconProps): import("react").JSX.Element;
