import * as React from 'react';

/**
 * RarityTile — from @skip-a-brainrot/ui@1.0.0.
 */
export interface RarityTileProps {
  /** Colours the 4px inner frame. */
  rarity?: "common" | "rare" | "epic" | "legend";
  /** Square edge length in px. The backpack grid uses 118. */
  size?: number;
  /** Adds the pulsing green claimable ring. */
  claimable?: boolean;
  /** Adds the cycling rainbow ring used for mutations. */
  rainbow?: boolean;
  children?: React.ReactNode;
  className?: string;
  id?: string;
  style?: CSSProperties;
}

export declare const RarityTile: React.ComponentType<RarityTileProps>;
