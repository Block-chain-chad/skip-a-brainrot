import * as React from 'react';

/**
 * Panel — from @skip-a-brainrot/ui@1.0.0.
 */
export interface PanelProps {
  /** Renders a `PanelHeader` above the body. */
  title?: React.ReactNode;
  /** Header icon — only used when `title` is set. */
  icon?: "bag" | "coin" | "daily" | "eggs" | "gem" | "goals" | "index" | "pass" | "plot" | "settings" | "shops" | "skip";
  /** Close handler for the header. */
  onClose?: () => void;
  /** Fixed panel width. The game's panels run 700–960px on a 1350px canvas. */
  width?: number;
  children?: React.ReactNode;
  className?: string;
  id?: string;
  style?: CSSProperties;
}

export declare const Panel: React.ComponentType<PanelProps>;
