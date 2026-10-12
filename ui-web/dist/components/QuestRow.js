import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { cx } from '../cx';
import { ProgressTrack } from './ProgressTrack';
/**
 * An 88px goal row: art, title over an inset progress bar, and an action at the
 * right end. This is the Goals panel's repeating unit.
 *
 * @example
 * <QuestRow title="Catch 10 brainrots" progress={0.4} caption="4 / 10"
 *           action={<Button variant="green" size="sm">CLAIM</Button>} />
 */
export function QuestRow({ title, progress, caption, art, action, className, ...rest }) {
    return (_jsxs("div", { className: cx('sb-quest-row', className), ...rest, children: [art, _jsxs("div", { className: "sb-quest-row__body", children: [_jsx("span", { className: "sb-quest-row__title", children: title }), _jsx(ProgressTrack, { progress: progress, height: 18, fill: "green" })] }), caption && (_jsx("span", { className: "sb-text sb-text--meta", style: { color: 'var(--sb-text-muted)' }, children: caption })), action] }));
}
