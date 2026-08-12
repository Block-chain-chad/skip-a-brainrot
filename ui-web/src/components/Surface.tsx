import type { HTMLAttributes, ReactNode } from 'react'
import { cx } from '../cx'

/** The six surface families `UI.surface` builds, keyed to their token gradients. */
export type SurfaceKind = 'panel' | 'subPanel' | 'row' | 'slot' | 'tab' | 'track'

export interface SurfaceProps extends HTMLAttributes<HTMLDivElement> {
  /** Which gradient family this surface uses. */
  kind?: SurfaceKind
  /** Adds the hard offset shadow — a copy of the shape pushed down Y in outline colour. */
  shadowed?: boolean
  /** Adds the guide's 2px white inner keyline just under the outer stroke. */
  keyline?: boolean
  /** Adds the top gloss strip and bottom shade. */
  gloss?: boolean
  children?: ReactNode
}

/**
 * The base card surface every other component is built on: vertical gradient,
 * thick outer stroke, and optionally the hard shadow, inner keyline and gloss.
 *
 * Port of `UI.surface` in `UIKit/Builders.lua`.
 *
 * @example
 * <Surface kind="subPanel" shadowed keyline style={{ width: 320, height: 120 }} />
 */
export function Surface({
  kind = 'panel',
  shadowed = false,
  keyline = false,
  gloss = false,
  className,
  children,
  ...rest
}: SurfaceProps) {
  return (
    <div
      className={cx(
        'sb-surface',
        `sb-surface--${kind}`,
        shadowed && 'sb-surface--shadowed',
        keyline && 'sb-surface--keyline',
        gloss && 'sb-gloss',
        className,
      )}
      {...rest}
    >
      {gloss && <span className="sb-gloss__top" />}
      {children}
      {gloss && <span className="sb-gloss__shade" />}
    </div>
  )
}
