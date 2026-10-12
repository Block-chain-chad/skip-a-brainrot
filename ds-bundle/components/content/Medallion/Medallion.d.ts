import * as React from 'react';

/**
 * Medallion — from @skip-a-brainrot/ui@1.0.0.
 */
export interface MedallionProps {
  /** Diameter in px. The Pass ladder's tier badge is 58. */
  size?: number;
  /** Background fill. Defaults to the small-gold gradient. */
  color?: string;
  children?: React.ReactNode;
  className?: string;
  id?: string;
  style?: CSSProperties;
}

export declare const Medallion: React.ComponentType<MedallionProps>;
