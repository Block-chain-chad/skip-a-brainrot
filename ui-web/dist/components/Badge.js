import { jsx as _jsx } from "react/jsx-runtime";
import { cx } from '../cx';
/**
 * The red notification pill that rides on a nav-rail item or a tab.
 *
 * Port of `UI.badge` — pill radius, red gradient, 3.5px outline, 30px minimum
 * so a single digit stays circular.
 *
 * @example
 * <Badge value="9+" />
 */
export function Badge({ value, className, ...rest }) {
    return (_jsx("span", { className: cx('sb-badge', className), ...rest, children: String(value) }));
}
