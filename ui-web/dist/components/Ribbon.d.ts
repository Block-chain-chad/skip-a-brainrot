import type { HTMLAttributes, ReactNode } from 'react';
/** The three tags the kit ships, each with its own gradient. */
export type RibbonVariant = 'EQUIPPED' | 'GRAND' | 'NEW';
export interface RibbonProps extends HTMLAttributes<HTMLSpanElement> {
    /** Picks the gradient: EQUIPPED green, GRAND purple, NEW red. */
    variant?: RibbonVariant;
    /** Defaults to the variant name, which is how the game uses it. */
    children?: ReactNode;
}
/**
 * The small pill tag that sits on a card corner.
 *
 * Port of `UI.ribbon`.
 *
 * @example
 * <Ribbon variant="EQUIPPED" />
 */
export declare function Ribbon({ variant, className, children, ...rest }: RibbonProps): import("react").JSX.Element;
