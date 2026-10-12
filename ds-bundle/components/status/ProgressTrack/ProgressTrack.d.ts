import * as React from 'react';

/**
 * ProgressTrack — from @skip-a-brainrot/ui@1.0.0.
 */
export interface ProgressTrackProps {
  /** 0–1. Values outside the range are clamped, matching `UI.setFill`. */
  progress: number;
  /** Gradient family for the fill. */
  fill?: unknown;
  /** Track height in px. */
  height?: number;
  className?: string;
  id?: string;
  style?: CSSProperties;
  children?: React.ReactNode;
}

export declare const ProgressTrack: React.ComponentType<ProgressTrackProps>;
