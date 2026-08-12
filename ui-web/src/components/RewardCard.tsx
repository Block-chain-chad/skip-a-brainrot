import type { HTMLAttributes, ReactNode } from 'react'
import { cx } from '../cx'

export interface RewardCardProps extends HTMLAttributes<HTMLDivElement> {
  /** Tier number in the medallion at the card's top edge. */
  tier: number | string
  /** Reward name under the art. */
  label: ReactNode
  /** `pass` uses the gold pass-card gradient; `free` uses the pale free-card one. */
  track?: 'free' | 'pass'
  /** Desaturates the card and drops the claim ring. */
  claimed?: boolean
  /** Dims the card behind a scrim — the tier is not reached yet. */
  locked?: boolean
  /** Pulsing green ring: this reward is claimable right now. */
  claimable?: boolean
  /** The reward art — usually an `ArtSlot` or `Icon`. */
  children?: ReactNode
}

/**
 * One rung of the Season Pass ladder: a 178x186 card with its tier medallion
 * overhanging the top edge.
 *
 * The ladder runs two tracks — `free` and `pass` — in the 3-column layout the
 * Pass panel shipped 2026-08-08.
 *
 * @example
 * <RewardCard tier={7} track="pass" label="Golden Crate" claimable>
 *   <Icon name="eggs" />
 * </RewardCard>
 */
export function RewardCard({
  tier,
  label,
  track = 'free',
  claimed = false,
  locked = false,
  claimable = false,
  className,
  children,
  ...rest
}: RewardCardProps) {
  return (
    <div
      className={cx(
        'sb-reward-card',
        track === 'pass' && 'sb-reward-card--pass',
        claimed && 'sb-reward-card--claimed',
        className,
      )}
      {...rest}
    >
      <span className="sb-reward-card__tier">{tier}</span>
      <div className="sb-reward-card__art">{children}</div>
      <span className="sb-reward-card__label">{label}</span>
      {locked && <span className="sb-reward-card__lock" />}
      {claimable && !claimed && <span className="sb-claim-ring" />}
    </div>
  )
}
