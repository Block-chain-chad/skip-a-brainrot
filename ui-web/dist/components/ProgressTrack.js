import { jsx as _jsx } from "react/jsx-runtime";
import { cx } from '../cx';
import { gradientCss } from '../tokens';
/**
 * The inset progress bar: a dark recessed track with an inner top shadow and a
 * gradient fill that animates over 400ms.
 *
 * Port of `UI.track` + `UI.setFill`.
 *
 * @example
 * <ProgressTrack progress={0.62} fill="gold" height={22} />
 */
export function ProgressTrack({ progress, fill = 'gold', height = 22, className, style, ...rest }) {
    const pct = Math.max(0, Math.min(1, progress));
    return (_jsx("div", { className: cx('sb-track', className), style: { height, ...style }, role: "progressbar", "aria-valuenow": Math.round(pct * 100), "aria-valuemin": 0, "aria-valuemax": 100, ...rest, children: _jsx("div", { className: "sb-track__fill", style: { width: `${pct * 100}%`, backgroundImage: gradientCss(fill) } }) }));
}
