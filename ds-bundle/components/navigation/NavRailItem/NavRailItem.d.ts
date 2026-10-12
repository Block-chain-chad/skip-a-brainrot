import * as React from 'react';

/**
 * NavRailItem — from @skip-a-brainrot/ui@1.0.0.
 */
export interface NavRailItemProps {
  /** Icon for this destination. */
  icon: "bag" | "coin" | "daily" | "eggs" | "gem" | "goals" | "index" | "pass" | "plot" | "settings" | "shops" | "skip";
  /** Label under the icon, set in the railLabel step (20px, 4px stroke). */
  label: string;
  /** Lights the 88px radial gold glow behind the icon. */
  active?: boolean;
  /** Renders a notification pill on the icon's top-right. */
  badge?: string | number;
  className?: string;
  id?: string;
  style?: CSSProperties;
}

export declare const NavRailItem: React.ComponentType<NavRailItemProps>;
