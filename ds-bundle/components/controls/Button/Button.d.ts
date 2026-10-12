import * as React from 'react';

/**
 * Button — from @skip-a-brainrot/ui@1.0.0.
 * @replaces button
 */
export interface ButtonProps {
  /** Gradient family. `disabled` drops the gloss and shadow so it cannot read as pressable. */
  variant?: "disabled" | "gold" | "goldSmall" | "green" | "purple" | "red" | "blue" | "tab";
  /** Height and type step: sm 44px, md 60px, lg 72px. */
  size?: "sm" | "md" | "lg";
  disabled?: boolean;
  children?: React.ReactNode;
  className?: string;
  id?: string;
  style?: CSSProperties;
}

export declare const Button: React.ComponentType<ButtonProps>;
