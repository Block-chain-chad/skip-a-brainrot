import type { HTMLAttributes, ReactNode } from 'react';
export interface QuestRowProps extends Omit<HTMLAttributes<HTMLDivElement>, 'title'> {
    /** What the player has to do. */
    title: ReactNode;
    /** 0–1. Drives the inset bar. */
    progress: number;
    /** Progress caption, e.g. "4 / 10". Rendered in the unstroked meta step. */
    caption?: ReactNode;
    /** Art or icon at the left end. */
    art?: ReactNode;
    /** Usually a `Button` — or a `Ribbon` once the quest is done. */
    action?: ReactNode;
}
/**
 * An 88px goal row: art, title over an inset progress bar, and an action at the
 * right end. This is the Goals panel's repeating unit.
 *
 * @example
 * <QuestRow title="Catch 10 brainrots" progress={0.4} caption="4 / 10"
 *           action={<Button variant="green" size="sm">CLAIM</Button>} />
 */
export declare function QuestRow({ title, progress, caption, art, action, className, ...rest }: QuestRowProps): import("react").JSX.Element;
