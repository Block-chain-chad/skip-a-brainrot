import * as React from 'react';

/**
 * PanelHeader — from @skip-a-brainrot/ui@1.0.0.
 */
export interface PanelHeaderProps {
  /** Header copy, set in the panelTitle step. */
  title: React.ReactNode;
  /** Optional 64px icon at the left end. */
  icon?: "bag" | "coin" | "daily" | "eggs" | "gem" | "goals" | "index" | "pass" | "plot" | "settings" | "shops" | "skip";
  /** Renders the close control and wires it. Omit for a header with no close. */
  onClose?: () => void;
  className?: string;
  id?: string;
  style?: CSSProperties;
  children?: React.ReactNode;
}

export declare const PanelHeader: React.ComponentType<PanelHeaderProps>;
