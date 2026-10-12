import * as React from 'react';

/**
 * AccentCard — from @skip-a-brainrot/ui@1.0.0.
 */
export interface AccentCardProps {
  /** Hex accent. The border takes it neat; the interior takes a pale tint of it. */
  accent: string;
  /** Outer corner radius. The inner content frame sits 3px inside it. */
  radius?: number;
  children?: React.ReactNode;
  className?: string;
  id?: string;
  style?: CSSProperties;
}

export declare const AccentCard: React.ComponentType<AccentCardProps>;
