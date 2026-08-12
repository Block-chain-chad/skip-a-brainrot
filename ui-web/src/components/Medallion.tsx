import type { HTMLAttributes, ReactNode } from 'react'
import { cx } from '../cx'

export interface MedallionProps extends HTMLAttributes<HTMLDivElement> {
  /** Diameter in px. The Pass ladder's tier badge is 58. */
  size?: number
  /** Background fill. Defaults to the small-gold gradient. */
  color?: string
  children?: ReactNode
}

/**
 * The small round token that carries a tier number, a day index or a count.
 *
 * Port of `UITheme.medallion` — a half-transparent white hairline stroke and a
 * gloss cap, rather than the heavy outline the buttons use.
 *
 * @example
 * <Medallion size={58}>7</Medallion>
 */
export function Medallion({ size = 58, color, className, style, children, ...rest }: MedallionProps) {
  return (
    <div
      className={cx('sb-medallion', 'sb-gloss', className)}
      style={{ width: size, height: size, ...(color ? { backgroundImage: 'none', background: color } : null), ...style }}
      {...rest}
    >
      <span className="sb-gloss__top" />
      <span className="sb-medallion__value">{children}</span>
    </div>
  )
}
