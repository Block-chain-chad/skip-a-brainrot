import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { cx } from '../cx';
/**
 * The kit's primary control: gradient fill, 3px outline, hard offset shadow, and
 * a gloss strip — lifting 2px on hover and sinking 2px on press.
 *
 * Port of `UI.button`. A `disabled` button keeps its outline but loses the shadow
 * and gloss, matching the Luau builder, which skips both for that variant.
 *
 * @example
 * <Button variant="green" size="md">CLAIM</Button>
 */
export function Button({ variant = 'gold', size = 'md', disabled, className, children, ...rest }) {
    const dead = disabled || variant === 'disabled';
    return (_jsxs("button", { type: "button", className: cx('sb-button', `sb-button--${dead ? 'disabled' : variant}`, `sb-button--${size}`, !dead && 'sb-gloss', className), disabled: dead, ...rest, children: [!dead && _jsx("span", { className: "sb-gloss__top" }), _jsx("span", { className: "sb-button__label", children: children }), !dead && _jsx("span", { className: "sb-gloss__shade" })] }));
}
