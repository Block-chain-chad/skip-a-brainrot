import type { HTMLAttributes, ReactNode } from 'react';
/** The four rarity strokes in `T.color`. */
export type Rarity = 'common' | 'rare' | 'epic' | 'legend';
export interface RarityTileProps extends HTMLAttributes<HTMLDivElement> {
    /** Colours the 4px inner frame. */
    rarity?: Rarity;
    /** Square edge length in px. The backpack grid uses 118. */
    size?: number;
    /** Adds the pulsing green claimable ring. */
    claimable?: boolean;
    /** Adds the cycling rainbow ring used for mutations. */
    rainbow?: boolean;
    children?: ReactNode;
}
/**
 * A backpack / index tile: dark slot surface with a 4px rarity-coloured inner
 * frame, plus the two attention rings the game layers on top of it.
 *
 * Port of `UI.rarityFrame` + `UI.claimRing` + `UI.rainbowRing`.
 *
 * @example
 * <RarityTile rarity="legend" size={118} rainbow>
 *   <Icon name="skip" size={64} />
 * </RarityTile>
 */
export declare function RarityTile({ rarity, size, claimable, rainbow, className, style, children, ...rest }: RarityTileProps): import("react").JSX.Element;
