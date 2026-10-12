import * as React from 'react';

/**
 * CurrencyPill — from @skip-a-brainrot/ui@1.0.0.
 */
export interface CurrencyPillProps {
  /** Which currency this pill shows. */
  currency?: "coin" | "gem";
  /** Pre-formatted amount — the HUD abbreviates large values ("1.2M"). */
  value: string | number;
  className?: string;
  id?: string;
  style?: CSSProperties;
  children?: React.ReactNode;
}

export declare const CurrencyPill: React.ComponentType<CurrencyPillProps>;
