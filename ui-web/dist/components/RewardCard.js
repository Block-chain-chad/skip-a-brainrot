import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { cx } from '../cx';
/**
 * One rung of the Season Pass ladder: a 178x186 card with its tier medallion
 * overhanging the top edge.
 *
 * The ladder runs two tracks — `free` and `pass` — in the 3-column layout the
 * Pass panel shipped 2026-08-08.
 *
 * @example
 * <RewardCard tier={7} track="pass" label="Golden Crate" claimable>
 *   <Icon name="eggs" />
 * </RewardCard>
 */
export function RewardCard({ tier, label, track = 'free', claimed = false, locked = false, claimable = false, className, children, ...rest }) {
    return (_jsxs("div", { className: cx('sb-reward-card', track === 'pass' && 'sb-reward-card--pass', claimed && 'sb-reward-card--claimed', className), ...rest, children: [_jsx("span", { className: "sb-reward-card__tier", children: tier }), _jsx("div", { className: "sb-reward-card__art", children: children }), _jsx("span", { className: "sb-reward-card__label", children: label }), locked && _jsx("span", { className: "sb-reward-card__lock" }), claimable && !claimed && _jsx("span", { className: "sb-claim-ring" })] }));
}
