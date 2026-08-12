import type { ButtonHTMLAttributes, HTMLAttributes, ReactNode } from 'react'
import { cx } from '../cx'
import { Badge } from './Badge'
import { Icon, type IconName } from './Icon'

export interface NavRailItemProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'children'> {
  /** Icon for this destination. */
  icon: IconName
  /** Label under the icon, set in the railLabel step (20px, 4px stroke). */
  label: string
  /** Lights the 88px radial gold glow behind the icon. */
  active?: boolean
  /** Renders a notification pill on the icon's top-right. */
  badge?: string | number
}

/**
 * One nav-rail destination: a bare 66px icon floating in a 106px column with its
 * label underneath.
 *
 * The v2 rail has **no button plate** — v1's 98x88 gold plate was dropped, and the
 * active state became a radial glow rather than a stroked ring. `Tokens.lua` flags
 * its own shipped v1 numbers as stale; these follow the pixel-adjudicated v2 spec.
 *
 * @example
 * <NavRailItem icon="pass" label="Pass" active badge={3} />
 */
export function NavRailItem({
  icon,
  label,
  active = false,
  badge,
  className,
  ...rest
}: NavRailItemProps) {
  return (
    <button type="button" className={cx('sb-rail-item', className)} {...rest}>
      {active && <span className="sb-rail-item__glow" />}
      <span className="sb-rail-item__icon">
        <Icon name={icon} />
      </span>
      <span className="sb-rail-item__label">{label}</span>
      {badge != null && (
        <span className="sb-rail-item__badge">
          <Badge value={badge} />
        </span>
      )}
    </button>
  )
}

export interface NavRailProps extends HTMLAttributes<HTMLDivElement> {
  /** How many items stack vertically before wrapping into the next column. */
  rows?: number
  /** `NavRailItem` children. */
  children?: ReactNode
}

/**
 * The HUD's destination rail — two columns of three on the LEFT edge of the
 * canvas, ending at x=228 so the widest panel (960px, centred) still clears it.
 *
 * @example
 * <NavRail>
 *   <NavRailItem icon="shops" label="Shops" />
 *   <NavRailItem icon="pass" label="Pass" active />
 * </NavRail>
 */
export function NavRail({ rows = 3, className, children, ...rest }: NavRailProps) {
  return (
    <div
      className={cx('sb-rail', className)}
      style={{ gridTemplateRows: `repeat(${rows}, auto)`, gridAutoFlow: 'column' }}
      {...rest}
    >
      {children}
    </div>
  )
}
