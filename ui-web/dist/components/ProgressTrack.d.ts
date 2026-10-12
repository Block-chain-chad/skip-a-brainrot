import type { HTMLAttributes } from 'react';
import type { GradientName } from '../tokens';
export interface ProgressTrackProps extends HTMLAttributes<HTMLDivElement> {
    /** 0–1. Values outside the range are clamped, matching `UI.setFill`. */
    progress: number;
    /** Gradient family for the fill. */
    fill?: GradientName;
    /** Track height in px. */
    height?: number;
}
/**
 * The inset progress bar: a dark recessed track with an inner top shadow and a
 * gradient fill that animates over 400ms.
 *
 * Port of `UI.track` + `UI.setFill`.
 *
 * @example
 * <ProgressTrack progress={0.62} fill="gold" height={22} />
 */
export declare function ProgressTrack({ progress, fill, height, className, style, ...rest }: ProgressTrackProps): import("react").JSX.Element;
