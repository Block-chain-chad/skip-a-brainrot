import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { cx } from '../cx';
import { Icon } from './Icon';
/**
 * The 54px currency chip in the HUD's top strip: dark row gradient, pill radius,
 * the currency icon overhanging the left end.
 *
 * @example
 * <CurrencyPill currency="coin" value="12.4K" />
 */
export function CurrencyPill({ currency = 'coin', value, className, ...rest }) {
    return (_jsxs("div", { className: cx('sb-currency', className), ...rest, children: [_jsx("span", { className: "sb-currency__icon", children: _jsx(Icon, { name: currency }) }), _jsx("span", { className: "sb-currency__value", children: String(value) })] }));
}
