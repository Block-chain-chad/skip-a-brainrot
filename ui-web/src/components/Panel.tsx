import type { HTMLAttributes, ReactNode } from 'react'
import { cx } from '../cx'
import { CloseButton } from './CloseButton'
import { Icon, type IconName } from './Icon'
import { Label } from './Label'

export interface PanelHeaderProps extends Omit<HTMLAttributes<HTMLDivElement>, 'title'> {
  /** Header copy, set in the panelTitle step. */
  title: ReactNode
  /** Optional 64px icon at the left end. */
  icon?: IconName
  /** Renders the close control and wires it. Omit for a header with no close. */
  onClose?: () => void
}

/**
 * The single red header bar. The 2026-08-04 guide allows exactly ONE per panel —
 * it is the only red surface in the window, which is what makes it read as the
 * title bar against the gray body.
 *
 * @example
 * <PanelHeader icon="pass" title="Season Pass" onClose={close} />
 */
export function PanelHeader({ title, icon, onClose, className, ...rest }: PanelHeaderProps) {
  return (
    <div className={cx('sb-panel-header', className)} {...rest}>
      {icon && (
        <span className="sb-panel-header__icon">
          <Icon name={icon} />
        </span>
      )}
      <Label variant="panelTitle" className="sb-panel-header__title">
        {title}
      </Label>
      {onClose && <CloseButton onClick={onClose} />}
    </div>
  )
}

export interface PanelProps extends Omit<HTMLAttributes<HTMLDivElement>, 'title'> {
  /** Renders a `PanelHeader` above the body. */
  title?: ReactNode
  /** Header icon — only used when `title` is set. */
  icon?: IconName
  /** Close handler for the header. */
  onClose?: () => void
  /** Fixed panel width. The game's panels run 700–960px on a 1350px canvas. */
  width?: number
  children?: ReactNode
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
export function Panel({
  title,
  icon,
  onClose,
  width,
  className,
  style,
  children,
  ...rest
}: PanelProps) {
  const headed = title != null
  return (
    <div
      className={cx(
        'sb-surface',
        'sb-surface--panel',
        'sb-surface--shadowed',
        'sb-surface--keyline',
        'sb-panel',
        headed && 'sb-panel--headed',
        className,
      )}
      style={width ? { width, ...style } : style}
      {...rest}
    >
      {headed && <PanelHeader title={title} icon={icon} onClose={onClose} />}
      {headed ? <div className="sb-panel__body">{children}</div> : children}
    </div>
  )
}
