import type { HTMLAttributes, ReactNode } from 'react';
/**
 * Derives a card interior from an accent hue — the port of `UITheme.accentFill`.
 *
 * Keeps the hue, collapses saturation and pushes value up, so each card reads in
 * its own colour while staying pale enough for dark body text to sit on it.
 */
export declare function accentFill(accent: string): {
    top: string;
    bottom: string;
};
export interface AccentCardProps extends HTMLAttributes<HTMLDivElement> {
    /** Hex accent. The border takes it neat; the interior takes a pale tint of it. */
    accent: string;
    /** Outer corner radius. The inner content frame sits 3px inside it. */
    radius?: number;
    children?: ReactNode;
}
/**
 * A card whose border is one accent colour and whose interior is a pale tint of
 * that same colour — the "one accent per card" read the panels are built around.
 *
 * Port of `UITheme.accentCard`. Note the rays that used to back these cards are
 * retired: `UITheme.sunburst` now paints a flat accent wash, so this component is
 * where that per-card colour lives.
 *
 * @example
 * <AccentCard accent="#3FA9F5" style={{ width: 240, height: 120 }}>
 *   <Label variant="cardLabel" color="var(--sb-text-on-window)">Rare</Label>
 * </AccentCard>
 */
export declare function AccentCard({ accent, radius, className, style, children, ...rest }: AccentCardProps): import("react").JSX.Element;
