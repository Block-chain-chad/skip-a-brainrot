import * as React from 'react';

/**
 * Toast — from @skip-a-brainrot/ui@1.0.0.
 */
export interface ToastProps {
  tone?: "neutral" | "success" | "warn" | "error";
  /** Optional leading icon. */
  icon?: "bag" | "coin" | "daily" | "eggs" | "gem" | "goals" | "index" | "pass" | "plot" | "settings" | "shops" | "skip";
  children?: React.ReactNode;
  className?: string;
  id?: string;
  style?: CSSProperties;
}

export declare const Toast: React.ComponentType<ToastProps>;
