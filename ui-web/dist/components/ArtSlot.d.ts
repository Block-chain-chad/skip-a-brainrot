import type { HTMLAttributes, ReactNode } from 'react';
export interface ArtSlotProps extends HTMLAttributes<HTMLDivElement> {
    /** Image URL. An empty string renders the placeholder, not an invisible slot. */
    src?: string;
    alt?: string;
    /** Square edge length in px. */
    size?: number;
    /** Rendered when there is no `src` — e.g. an `<Icon>` standing in for the art. */
    children?: ReactNode;
}
/**
 * The square art well a brainrot render, pet or reward image sits in.
 *
 * Port of `UI.artSlot`. The kit deviation it documents is preserved: an empty
 * string is treated as "no art" and shows the placeholder fill, because an
 * un-uploaded icon rendering as an invisible slot reads as a broken panel.
 *
 * @example
 * <ArtSlot size={92}><Icon name="eggs" /></ArtSlot>
 */
export declare function ArtSlot({ src, alt, size, className, style, children, ...rest }: ArtSlotProps): import("react").JSX.Element;
