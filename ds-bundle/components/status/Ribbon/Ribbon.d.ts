import * as React from 'react';

/**
 * Ribbon — from @skip-a-brainrot/ui@1.0.0.
 */
export interface RibbonProps {
  /** Picks the gradient: EQUIPPED green, GRAND purple, NEW red. */
  variant?: "EQUIPPED" | "GRAND" | "NEW";
  /** Defaults to the variant name, which is how the game uses it. */
  children?: React.ReactNode;
  className?: string;
  id?: string;
  style?: CSSProperties;
}

export declare const Ribbon: React.ComponentType<RibbonProps>;
