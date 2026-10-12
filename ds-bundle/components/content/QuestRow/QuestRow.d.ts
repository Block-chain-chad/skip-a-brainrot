import * as React from 'react';

/**
 * QuestRow — from @skip-a-brainrot/ui@1.0.0.
 */
export interface QuestRowProps {
  /** What the player has to do. */
  title: React.ReactNode;
  /** 0–1. Drives the inset bar. */
  progress: number;
  /** Progress caption, e.g. "4 / 10". Rendered in the unstroked meta step. */
  caption?: React.ReactNode;
  /** Art or icon at the left end. */
  art?: React.ReactNode;
  /** Usually a `Button` — or a `Ribbon` once the quest is done. */
  action?: React.ReactNode;
  className?: string;
  id?: string;
  style?: CSSProperties;
  children?: React.ReactNode;
}

export declare const QuestRow: React.ComponentType<QuestRowProps>;
