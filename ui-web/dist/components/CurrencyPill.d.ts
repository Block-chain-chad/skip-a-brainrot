import type { HTMLAttributes } from 'react';
import { type IconName } from './Icon';
export interface CurrencyPillProps extends HTMLAttributes<HTMLDivElement> {
    /** Which currency this pill shows. */
    currency?: Extract<IconName, 'coin' | 'gem'>;
    /** Pre-formatted amount — the HUD abbreviates large values ("1.2M"). */
    value: string | number;
}
/**
 * The 54px currency chip in the HUD's top strip: dark row gradient, pill radius,
 * the currency icon overhanging the left end.
 *
 * @example
 * <CurrencyPill currency="coin" value="12.4K" />
 */
export declare function CurrencyPill({ currency, value, className, ...rest }: CurrencyPillProps): import("react").JSX.Element;
