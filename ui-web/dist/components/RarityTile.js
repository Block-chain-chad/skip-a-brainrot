import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { cx } from '../cx';
/**
 * A backpack / index tile: dark slot surface with a 4px rarity-coloured inner
 * frame, plus the two attention rings the game layers on top of it.
 *
 * Port of `UI.rarityFrame` + `UI.claimRing` + `UI.rainbowRing`.
 *
 * @example
 * <RarityTile rarity="legend" size={118} rainbow>
 *   <Icon name="skip" size={64} />
 * </RarityTile>
 */
export function RarityTile({ rarity = 'common', size = 118, claimable = false, rainbow = false, className, style, children, ...rest }) {
    return (_jsxs("div", { className: cx('sb-rarity-tile', `sb-rarity-tile--${rarity}`, className), style: { width: size, height: size, ...style }, ...rest, children: [children, _jsx("span", { className: "sb-rarity-tile__frame" }), rainbow && _jsx("span", { className: "sb-rainbow-ring" }), claimable && _jsx("span", { className: "sb-claim-ring" })] }));
}
