import { jsx as _jsx } from "react/jsx-runtime";
import { cx } from '../cx';
/**
 * The segment control panels use to switch sections. The selected tab swaps to
 * the gold gradient and gains the `activeRing` outline.
 *
 * @example
 * <TabBar value="pets" tabs={[{ id: 'pets', label: 'Pets' }, { id: 'keys', label: 'Keys' }]} />
 */
export function TabBar({ tabs, value, onSelect, className, ...rest }) {
    return (_jsx("div", { className: cx('sb-tabs', className), role: "tablist", ...rest, children: tabs.map((tab) => (_jsx("button", { type: "button", role: "tab", "aria-selected": tab.id === value, className: cx('sb-tab', tab.id === value && 'sb-tab--active'), onClick: () => onSelect?.(tab.id), children: tab.label }, tab.id))) }));
}
