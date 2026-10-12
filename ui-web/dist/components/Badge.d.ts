import type { HTMLAttributes } from 'react';
export interface BadgeProps extends HTMLAttributes<HTMLSpanElement> {
    /** Coerced to a string, so `3` and `"9+"` both work. */
    value: string | number;
}
/**
 * The red notification pill that rides on a nav-rail item or a tab.
 *
 * Port of `UI.badge` — pill radius, red gradient, 3.5px outline, 30px minimum
 * so a single digit stays circular.
 *
 * @example
 * <Badge value="9+" />
 */
export declare function Badge({ value, className, ...rest }: BadgeProps): import("react").JSX.Element;
