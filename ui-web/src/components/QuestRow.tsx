import type { HTMLAttributes, ReactNode } from 'react'
import { cx } from '../cx'
import { ProgressTrack } from './ProgressTrack'

export interface QuestRowProps extends Omit<HTMLAttributes<HTMLDivElement>, 'title'> {
  /** What the player has to do. */
  title: ReactNode
  /** 0–1. Drives the inset bar. */
  progress: number
  /** Progress caption, e.g. "4 / 10". Rendered in the unstroked meta step. */
  caption?: ReactNode
  /** Art or icon at the left end. */
  art?: ReactNode
  /** Usually a `Button` — or a `Ribbon` once the quest is done. */
  action?: ReactNode
}

/**
 * An 88px goal row: art, title over an inset progress bar, and an action at the
 * right end. This is the Goals panel's repeating unit.
 *
 * @example
 * <QuestRow title="Catch 10 brainrots" progress={0.4} caption="4 / 10"
 *           action={<Button variant="green" size="sm">CLAIM</Button>} />
 */
export function QuestRow({
  title,
  progress,
  caption,
  art,
  action,
  className,
  ...rest
}: QuestRowProps) {
  return (
    <div className={cx('sb-quest-row', className)} {...rest}>
      {art}
      <div className="sb-quest-row__body">
        <span className="sb-quest-row__title">{title}</span>
        <ProgressTrack progress={progress} height={18} fill="green" />
      </div>
      {caption && (
        <span className="sb-text sb-text--meta" style={{ color: 'var(--sb-text-muted)' }}>
          {caption}
        </span>
      )}
      {action}
    </div>
  )
}
