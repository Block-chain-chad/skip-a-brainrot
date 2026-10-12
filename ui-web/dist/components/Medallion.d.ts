import type { HTMLAttributes, ReactNode } from 'react';
export interface MedallionProps extends HTMLAttributes<HTMLDivElement> {
    /** Diameter in px. The Pass ladder's tier badge is 58. */
    size?: number;
    /** Background fill. Defaults to the small-gold gradient. */
    color?: string;
    children?: ReactNode;
}
/**
 * The small round token that carries a tier number, a day index or a count.
 *
 * Port of `UITheme.medallion` — a half-transparent white hairline stroke and a
 * gloss cap, rather than the heavy outline the buttons use.
 *
 * @example
 * <Medallion size={58}>7</Medallion>
 */
export declare function Medallion({ size, color, className, style, children, ...rest }: MedallionProps): import("react").JSX.Element;
