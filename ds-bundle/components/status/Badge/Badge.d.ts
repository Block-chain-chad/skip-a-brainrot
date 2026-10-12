import * as React from 'react';

/**
 * Badge — from @skip-a-brainrot/ui@1.0.0.
 */
export interface BadgeProps {
  /** Coerced to a string, so `3` and `"9+"` both work. */
  value: string | number;
  className?: string;
  id?: string;
  style?: CSSProperties;
  children?: React.ReactNode;
}

export declare const Badge: React.ComponentType<BadgeProps>;
