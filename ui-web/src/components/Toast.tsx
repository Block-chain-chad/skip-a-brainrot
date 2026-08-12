import type { HTMLAttributes, ReactNode } from 'react'
import { cx } from '../cx'
import { Icon, type IconName } from './Icon'

/** Tone picks the gradient — neutral is the dark row fill. */
export type ToastTone = 'neutral' | 'success' | 'warn' | 'error'

export interface ToastProps extends HTMLAttributes<HTMLDivElement> {
  tone?: ToastTone
  /** Optional leading icon. */
  icon?: IconName
  children?: ReactNode
}

/**
 * The transient message that flies into the top of the HUD — a reward landing,
 * a purchase confirming, an error.
 *
 * @example
 * <Toast tone="success" icon="coin">+2,500 Coins</Toast>
 */
export function Toast({ tone = 'neutral', icon, className, children, ...rest }: ToastProps) {
  return (
    <div className={cx('sb-toast', tone !== 'neutral' && `sb-toast--${tone}`, className)} {...rest}>
      {icon && <Icon name={icon} size={28} />}
      {children}
    </div>
  )
}
