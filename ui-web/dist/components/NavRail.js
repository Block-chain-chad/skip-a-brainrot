import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { cx } from '../cx';
import { Badge } from './Badge';
import { Icon } from './Icon';
/**
 * One nav-rail destination: a bare 66px icon floating in a 106px column with its
 * label underneath.
 *
 * The v2 rail has **no button plate** — v1's 98x88 gold plate was dropped, and the
 * active state became a radial glow rather than a stroked ring. `Tokens.lua` flags
 * its own shipped v1 numbers as stale; these follow the pixel-adjudicated v2 spec.
 *
 * @example
 * <NavRailItem icon="pass" label="Pass" active badge={3} />
 */
export function NavRailItem({ icon, label, active = false, badge, className, ...rest }) {
    return (_jsxs("button", { type: "button", className: cx('sb-rail-item', className), ...rest, children: [active && _jsx("span", { className: "sb-rail-item__glow" }), _jsx("span", { className: "sb-rail-item__icon", children: _jsx(Icon, { name: icon }) }), _jsx("span", { className: "sb-rail-item__label", children: label }), badge != null && (_jsx("span", { className: "sb-rail-item__badge", children: _jsx(Badge, { value: badge }) }))] }));
}
/**
 * The HUD's destination rail — two columns of three on the LEFT edge of the
 * canvas, ending at x=228 so the widest panel (960px, centred) still clears it.
 *
 * @example
 * <NavRail>
 *   <NavRailItem icon="shops" label="Shops" />
 *   <NavRailItem icon="pass" label="Pass" active />
 * </NavRail>
 */
export function NavRail({ rows = 3, className, children, ...rest }) {
    return (_jsx("div", { className: cx('sb-rail', className), style: { gridTemplateRows: `repeat(${rows}, auto)`, gridAutoFlow: 'column' }, ...rest, children: children }));
}
