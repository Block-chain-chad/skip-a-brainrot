import type { HTMLAttributes } from 'react';
export interface TabItem {
    /** Stable key, returned by `onSelect`. */
    id: string;
    label: string;
}
export interface TabBarProps extends Omit<HTMLAttributes<HTMLDivElement>, 'onSelect'> {
    tabs: TabItem[];
    /** `id` of the selected tab. */
    value: string;
    onSelect?: (id: string) => void;
}
/**
 * The segment control panels use to switch sections. The selected tab swaps to
 * the gold gradient and gains the `activeRing` outline.
 *
 * @example
 * <TabBar value="pets" tabs={[{ id: 'pets', label: 'Pets' }, { id: 'keys', label: 'Keys' }]} />
 */
export declare function TabBar({ tabs, value, onSelect, className, ...rest }: TabBarProps): import("react").JSX.Element;
