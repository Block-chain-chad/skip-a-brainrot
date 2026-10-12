import { jsx as _jsx } from "react/jsx-runtime";
import { cx } from '../cx';
/**
 * The small pill tag that sits on a card corner.
 *
 * Port of `UI.ribbon`.
 *
 * @example
 * <Ribbon variant="EQUIPPED" />
 */
export function Ribbon({ variant = 'EQUIPPED', className, children, ...rest }) {
    return (_jsx("span", { className: cx('sb-ribbon', `sb-ribbon--${variant}`, className), ...rest, children: children ?? variant }));
}
