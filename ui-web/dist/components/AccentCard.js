import { jsx as _jsx } from "react/jsx-runtime";
import { cx } from '../cx';
/**
 * Derives a card interior from an accent hue — the port of `UITheme.accentFill`.
 *
 * Keeps the hue, collapses saturation and pushes value up, so each card reads in
 * its own colour while staying pale enough for dark body text to sit on it.
 */
export function accentFill(accent) {
    const { h, s } = hexToHsv(accent);
    return {
        top: hsvToCss(h, Math.min(s * 0.3, 1), 0.98),
        bottom: hsvToCss(h, Math.min(s * 0.46, 1), 0.9),
    };
}
function hexToHsv(hex) {
    const n = hex.replace('#', '');
    const full = n.length === 3 ? n.split('').map((c) => c + c).join('') : n;
    const r = parseInt(full.slice(0, 2), 16) / 255;
    const g = parseInt(full.slice(2, 4), 16) / 255;
    const b = parseInt(full.slice(4, 6), 16) / 255;
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    const d = max - min;
    let h = 0;
    if (d !== 0) {
        if (max === r)
            h = ((g - b) / d) % 6;
        else if (max === g)
            h = (b - r) / d + 2;
        else
            h = (r - g) / d + 4;
    }
    h = (h * 60 + 360) % 360;
    return { h, s: max === 0 ? 0 : d / max, v: max };
}
function hsvToCss(h, s, v) {
    return `hsl(${h.toFixed(1)} ${(s * 100).toFixed(1)}% ${((v * (2 - s)) / 2 * 100).toFixed(1)}%)`;
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
export function AccentCard({ accent, radius = 14, className, style, children, ...rest }) {
    const fill = accentFill(accent);
    return (_jsx("div", { className: cx('sb-accent-card', className), style: { background: accent, borderRadius: radius, ...style }, ...rest, children: _jsx("div", { className: "sb-accent-card__content", style: {
                borderRadius: radius - 3,
                backgroundImage: `linear-gradient(180deg, ${fill.top}, ${fill.bottom})`,
            }, children: children }) }));
}
