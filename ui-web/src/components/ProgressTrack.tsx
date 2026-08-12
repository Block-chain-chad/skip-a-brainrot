import type { HTMLAttributes } from 'react'
import { cx } from '../cx'
import type { GradientName } from '../tokens'
import { gradientCss } from '../tokens'

export interface ProgressTrackProps extends HTMLAttributes<HTMLDivElement> {
  /** 0–1. Values outside the range are clamped, matching `UI.setFill`. */
  progress: number
  /** Gradient family for the fill. */
  fill?: GradientName
  /** Track height in px. */
  height?: number
}

/**
 * The inset progress bar: a dark recessed track with an inner top shadow and a
 * gradient fill that animates over 400ms.
 *
 * Port of `UI.track` + `UI.setFill`.
 *
 * @example
 * <ProgressTrack progress={0.62} fill="gold" height={22} />
 */
export function ProgressTrack({
  progress,
  fill = 'gold',
  height = 22,
  className,
  style,
  ...rest
}: ProgressTrackProps) {
  const pct = Math.max(0, Math.min(1, progress))
  return (
    <div
      className={cx('sb-track', className)}
      style={{ height, ...style }}
      role="progressbar"
      aria-valuenow={Math.round(pct * 100)}
      aria-valuemin={0}
      aria-valuemax={100}
      {...rest}
    >
      <div
        className="sb-track__fill"
        style={{ width: `${pct * 100}%`, backgroundImage: gradientCss(fill) }}
      />
    </div>
  )
}
