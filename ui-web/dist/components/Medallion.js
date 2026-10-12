import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { cx } from '../cx';
/**
 * The small round token that carries a tier number, a day index or a count.
 *
 * Port of `UITheme.medallion` — a half-transparent white hairline stroke and a
 * gloss cap, rather than the heavy outline the buttons use.
 *
 * @example
 * <Medallion size={58}>7</Medallion>
 */
export function Medallion({ size = 58, color, className, style, children, ...rest }) {
    return (_jsxs("div", { className: cx('sb-medallion', 'sb-gloss', className), style: { width: size, height: size, ...(color ? { backgroundImage: 'none', background: color } : null), ...style }, ...rest, children: [_jsx("span", { className: "sb-gloss__top" }), _jsx("span", { className: "sb-medallion__value", children: children })] }));
}
