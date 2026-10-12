import type { ButtonHTMLAttributes } from 'react';
export type CloseButtonProps = ButtonHTMLAttributes<HTMLButtonElement>;
/**
 * The 74x66 red close control that sits at the right end of every panel header.
 *
 * Port of `UITheme.styleClose` / `closeGlyph` — the X is drawn as two stroked
 * bars rather than a glyph, so it keeps its weight at any size.
 *
 * @example
 * <CloseButton onClick={close} />
 */
export declare function CloseButton({ className, ...rest }: CloseButtonProps): import("react").JSX.Element;
