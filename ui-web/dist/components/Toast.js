import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { cx } from '../cx';
import { Icon } from './Icon';
/**
 * The transient message that flies into the top of the HUD — a reward landing,
 * a purchase confirming, an error.
 *
 * @example
 * <Toast tone="success" icon="coin">+2,500 Coins</Toast>
 */
export function Toast({ tone = 'neutral', icon, className, children, ...rest }) {
    return (_jsxs("div", { className: cx('sb-toast', tone !== 'neutral' && `sb-toast--${tone}`, className), ...rest, children: [icon && _jsx(Icon, { name: icon, size: 28 }), children] }));
}
