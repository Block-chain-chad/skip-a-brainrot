import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { cx } from '../cx';
import { CloseButton } from './CloseButton';
import { Icon } from './Icon';
import { Label } from './Label';
/**
 * The single red header bar. The 2026-08-04 guide allows exactly ONE per panel —
 * it is the only red surface in the window, which is what makes it read as the
 * title bar against the gray body.
 *
 * @example
 * <PanelHeader icon="pass" title="Season Pass" onClose={close} />
 */
export function PanelHeader({ title, icon, onClose, className, ...rest }) {
    return (_jsxs("div", { className: cx('sb-panel-header', className), ...rest, children: [icon && (_jsx("span", { className: "sb-panel-header__icon", children: _jsx(Icon, { name: icon }) })), _jsx(Label, { variant: "panelTitle", className: "sb-panel-header__title", children: title }), onClose && _jsx(CloseButton, { onClick: onClose })] }));
}
/**
 * The game's window: light gray vertical gradient, 4px outline, white inner
 * keyline and a hard offset shadow. With `title` set it grows the red header bar.
 *
 * Port of `UI.panel`.
 *
 * @example
 * <Panel title="Goals" icon="goals" width={860} onClose={close}>
 *   <QuestRow title="Catch 10 brainrots" progress={0.4} />
 * </Panel>
 */
export function Panel({ title, icon, onClose, width, className, style, children, ...rest }) {
    const headed = title != null;
    return (_jsxs("div", { className: cx('sb-surface', 'sb-surface--panel', 'sb-surface--shadowed', 'sb-surface--keyline', 'sb-panel', headed && 'sb-panel--headed', className), style: width ? { width, ...style } : style, ...rest, children: [headed && _jsx(PanelHeader, { title: title, icon: icon, onClose: onClose }), headed ? _jsx("div", { className: "sb-panel__body", children: children }) : children] }));
}
