import { jsx as _jsx } from "react/jsx-runtime";
import { cx } from '../cx';
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
export function Label({ variant = 'cardLabel', on = 'dark', color, className, style, children, ...rest }) {
    return (_jsx("span", { className: cx('sb-text', `sb-text--${variant}`, on === 'light' && 'sb-text--on-light', className), style: color ? { color, ...style } : style, ...rest, children: children }));
}
