import type { ButtonHTMLAttributes, ReactNode } from 'react';
/** The gradient families `UI.button` accepts. */
export type ButtonVariant = 'gold' | 'goldSmall' | 'green' | 'purple' | 'red' | 'blue' | 'tab' | 'disabled';
export type ButtonSize = 'sm' | 'md' | 'lg';
export interface ButtonProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'disabled'> {
    /** Gradient family. `disabled` drops the gloss and shadow so it cannot read as pressable. */
    variant?: ButtonVariant;
    /** Height and type step: sm 44px, md 60px, lg 72px. */
    size?: ButtonSize;
    disabled?: boolean;
    children?: ReactNode;
}
/**
 * The kit's primary control: gradient fill, 3px outline, hard offset shadow, and
 * a gloss strip — lifting 2px on hover and sinking 2px on press.
 *
 * Port of `UI.button`. A `disabled` button keeps its outline but loses the shadow
 * and gloss, matching the Luau builder, which skips both for that variant.
 *
 * @example
 * <Button variant="green" size="md">CLAIM</Button>
 */
export declare function Button({ variant, size, disabled, className, children, ...rest }: ButtonProps): import("react").JSX.Element;
