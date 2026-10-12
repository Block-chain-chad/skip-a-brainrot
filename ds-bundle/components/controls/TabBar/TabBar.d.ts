import * as React from 'react';

/**
 * TabBar — from @skip-a-brainrot/ui@1.0.0.
 */
export interface TabBarProps {
  tabs: TabItem[];
  /** `id` of the selected tab. */
  value: string;
  onSelect?: (id: string) => void;
  className?: string;
  id?: string;
  style?: CSSProperties;
  children?: React.ReactNode;
}

export declare const TabBar: React.ComponentType<TabBarProps>;
