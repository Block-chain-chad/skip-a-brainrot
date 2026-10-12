import type { HTMLAttributes, ReactNode } from 'react';
/** The type ramp from `T.text` — each entry carries its own stroke weight. */
export type LabelStyle = 'panelTitle' | 'buttonL' | 'buttonM' | 'value' | 'cardLabel' | 'chip' | 'railLabel' | 'meta';
export interface LabelProps extends HTMLAttributes<HTMLSpanElement> {
    /** Which step of the type ramp to render. */
    variant?: LabelStyle;
    /**
     * Which surface the label sits on.
     *
     * `dark` (default) — white text with the outline stroke, for `row`/`slot`/`track`
     * surfaces and anything over the world.
     *
     * `light` — dark ink with **no stroke**, for the gray window, tabs and pale
     * cards. The stroke is dropped deliberately: it is near-black, so around
     * near-black ink it merges with the fill and smears the glyphs shut.
     */
    on?: 'dark' | 'light';
    /** Overrides the colour picked by `on`. Does not change the stroke. */
    color?: string;
    children?: ReactNode;
}
/**
 * Display text with the heavy outline stroke.
 *
 * Port of `UI.label`. `meta` is the only step that is unstroked at any setting —
 * it is body copy set in Nunito; every other step is Fredoka One with the stroke
 * weight the guide pairs to its size.
 *
 * @example
 * <Label variant="panelTitle">Season Pass</Label>
 * <Label variant="cardLabel" on="light">Golden Crate</Label>
 */
export declare function Label({ variant, on, color, className, style, children, ...rest }: LabelProps): import("react").JSX.Element;
