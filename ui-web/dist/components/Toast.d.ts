import type { HTMLAttributes, ReactNode } from 'react';
import { type IconName } from './Icon';
/** Tone picks the gradient — neutral is the dark row fill. */
export type ToastTone = 'neutral' | 'success' | 'warn' | 'error';
export interface ToastProps extends HTMLAttributes<HTMLDivElement> {
    tone?: ToastTone;
    /** Optional leading icon. */
    icon?: IconName;
    children?: ReactNode;
}
/**
 * The transient message that flies into the top of the HUD — a reward landing,
 * a purchase confirming, an error.
 *
 * @example
 * <Toast tone="success" icon="coin">+2,500 Coins</Toast>
 */
export declare function Toast({ tone, icon, className, children, ...rest }: ToastProps): import("react").JSX.Element;
