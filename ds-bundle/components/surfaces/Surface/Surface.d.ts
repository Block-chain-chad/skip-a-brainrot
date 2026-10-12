import * as React from 'react';

/**
 * Surface — from @skip-a-brainrot/ui@1.0.0.
 */
export interface SurfaceProps {
  /** Which gradient family this surface uses. */
  kind?: "slot" | "tab" | "panel" | "subPanel" | "row" | "track";
  /** Adds the hard offset shadow — a copy of the shape pushed down Y in outline colour. */
  shadowed?: boolean;
  /** Adds the guide's 2px white inner keyline just under the outer stroke. */
  keyline?: boolean;
  /** Adds the top gloss strip and bottom shade. */
  gloss?: boolean;
  children?: React.ReactNode;
  className?: string;
  id?: string;
  style?: CSSProperties;
}

export declare const Surface: React.ComponentType<SurfaceProps>;
