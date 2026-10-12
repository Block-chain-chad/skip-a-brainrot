import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { cx } from '../cx';
/**
 * The base card surface every other component is built on: vertical gradient,
 * thick outer stroke, and optionally the hard shadow, inner keyline and gloss.
 *
 * Port of `UI.surface` in `UIKit/Builders.lua`.
 *
 * @example
 * <Surface kind="subPanel" shadowed keyline style={{ width: 320, height: 120 }} />
 */
export function Surface({ kind = 'panel', shadowed = false, keyline = false, gloss = false, className, children, ...rest }) {
    return (_jsxs("div", { className: cx('sb-surface', `sb-surface--${kind}`, shadowed && 'sb-surface--shadowed', keyline && 'sb-surface--keyline', gloss && 'sb-gloss', className), ...rest, children: [gloss && _jsx("span", { className: "sb-gloss__top" }), children, gloss && _jsx("span", { className: "sb-gloss__shade" })] }));
}
