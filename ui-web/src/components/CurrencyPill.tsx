import type { HTMLAttributes } from 'react'
import { cx } from '../cx'
import { Icon, type IconName } from './Icon'

export interface CurrencyPillProps extends HTMLAttributes<HTMLDivElement> {
  /** Which currency this pill shows. */
  currency?: Extract<IconName, 'coin' | 'gem'>
  /** Pre-formatted amount — the HUD abbreviates large values ("1.2M"). */
  value: string | number
}

/**
 * The 54px currency chip in the HUD's top strip: dark row gradient, pill radius,
 * the currency icon overhanging the left end.
 *
 * @example
 * <CurrencyPill currency="coin" value="12.4K" />
 */
export function CurrencyPill({ currency = 'coin', value, className, ...rest }: CurrencyPillProps) {
  return (
    <div className={cx('sb-currency', className)} {...rest}>
      <span className="sb-currency__icon">
        <Icon name={currency} />
      </span>
      <span className="sb-currency__value">{String(value)}</span>
    </div>
  )
}
