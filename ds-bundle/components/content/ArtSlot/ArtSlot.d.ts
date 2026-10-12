import * as React from 'react';

/**
 * ArtSlot — from @skip-a-brainrot/ui@1.0.0.
 */
export interface ArtSlotProps {
  /** Image URL. An empty string renders the placeholder, not an invisible slot. */
  src?: string;
  alt?: string;
  /** Square edge length in px. */
  size?: number;
  /** Rendered when there is no `src` — e.g. an `<Icon>` standing in for the art. */
  children?: React.ReactNode;
  className?: string;
  id?: string;
  style?: CSSProperties;
}

export declare const ArtSlot: React.ComponentType<ArtSlotProps>;
