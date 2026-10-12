import * as React from 'react';

/**
 * Label — from @skip-a-brainrot/ui@1.0.0.
 */
export interface LabelProps {
  /** Which step of the type ramp to render. */
  variant?: "value" | "panelTitle" | "buttonL" | "buttonM" | "cardLabel" | "chip" | "railLabel" | "meta";
  /** Which surface the label sits on. `dark` (default) — white text with the outline stroke, for `row`/`slot`/`track` surface */
  on?: "dark" | "light";
  /** Overrides the colour picked by `on`. Does not change the stroke. */
  color?: string;
  children?: React.ReactNode;
  className?: string;
  id?: string;
  style?: CSSProperties;
}

export declare const Label: React.ComponentType<LabelProps>;
