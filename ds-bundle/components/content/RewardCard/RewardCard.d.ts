import * as React from 'react';

/**
 * RewardCard — from @skip-a-brainrot/ui@1.0.0.
 */
export interface RewardCardProps {
  /** Tier number in the medallion at the card's top edge. */
  tier: string | number;
  /** Reward name under the art. */
  label: React.ReactNode;
  /** `pass` uses the gold pass-card gradient; `free` uses the pale free-card one. */
  track?: "pass" | "free";
  /** Desaturates the card and drops the claim ring. */
  claimed?: boolean;
  /** Dims the card behind a scrim — the tier is not reached yet. */
  locked?: boolean;
  /** Pulsing green ring: this reward is claimable right now. */
  claimable?: boolean;
  /** The reward art — usually an `ArtSlot` or `Icon`. */
  children?: React.ReactNode;
  className?: string;
  id?: string;
  style?: CSSProperties;
}

export declare const RewardCard: React.ComponentType<RewardCardProps>;
