import * as React from 'react';

/**
 * NavRail — from @skip-a-brainrot/ui@1.0.0.
 */
export interface NavRailProps {
  /** How many items stack vertically before wrapping into the next column. */
  rows?: number;
  /** `NavRailItem` children. */
  children?: React.ReactNode;
  className?: string;
  id?: string;
  style?: CSSProperties;
}

export declare const NavRail: React.ComponentType<NavRailProps>;
