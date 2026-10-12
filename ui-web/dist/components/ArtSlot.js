import { jsx as _jsx } from "react/jsx-runtime";
import { cx } from '../cx';
/**
 * The square art well a brainrot render, pet or reward image sits in.
 *
 * Port of `UI.artSlot`. The kit deviation it documents is preserved: an empty
 * string is treated as "no art" and shows the placeholder fill, because an
 * un-uploaded icon rendering as an invisible slot reads as a broken panel.
 *
 * @example
 * <ArtSlot size={92}><Icon name="eggs" /></ArtSlot>
 */
export function ArtSlot({ src, alt = '', size, className, style, children, ...rest }) {
    const has = typeof src === 'string' && src !== '';
    return (_jsx("div", { className: cx('sb-art-slot', !has && 'sb-art-slot--empty', className), style: size ? { width: size, height: size, ...style } : style, ...rest, children: has ? _jsx("img", { src: src, alt: alt }) : children }));
}
