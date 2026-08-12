import type { ButtonHTMLAttributes } from 'react'
import { cx } from '../cx'

export type CloseButtonProps = ButtonHTMLAttributes<HTMLButtonElement>

/**
 * The 74x66 red close control that sits at the right end of every panel header.
 *
 * Port of `UITheme.styleClose` / `closeGlyph` — the X is drawn as two stroked
 * bars rather than a glyph, so it keeps its weight at any size.
 *
 * @example
 * <CloseButton onClick={close} />
 */
export function CloseButton({ className, ...rest }: CloseButtonProps) {
  return (
    <button type="button" className={cx('sb-close', className)} aria-label="Close" {...rest}>
      <svg width="30" height="30" viewBox="0 0 30 30" aria-hidden="true">
        <g
          stroke="#202020"
          strokeWidth="11"
          strokeLinecap="round"
          fill="none"
        >
          <path d="M7 7 L23 23" />
          <path d="M23 7 L7 23" />
        </g>
        <g stroke="#FFFFFF" strokeWidth="6" strokeLinecap="round" fill="none">
          <path d="M7 7 L23 23" />
          <path d="M23 7 L7 23" />
        </g>
      </svg>
    </button>
  )
}
