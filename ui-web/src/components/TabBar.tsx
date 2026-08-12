import type { HTMLAttributes } from 'react'
import { cx } from '../cx'

export interface TabItem {
  /** Stable key, returned by `onSelect`. */
  id: string
  label: string
}

export interface TabBarProps extends Omit<HTMLAttributes<HTMLDivElement>, 'onSelect'> {
  tabs: TabItem[]
  /** `id` of the selected tab. */
  value: string
  onSelect?: (id: string) => void
}

/**
 * The segment control panels use to switch sections. The selected tab swaps to
 * the gold gradient and gains the `activeRing` outline.
 *
 * @example
 * <TabBar value="pets" tabs={[{ id: 'pets', label: 'Pets' }, { id: 'keys', label: 'Keys' }]} />
 */
export function TabBar({ tabs, value, onSelect, className, ...rest }: TabBarProps) {
  return (
    <div className={cx('sb-tabs', className)} role="tablist" {...rest}>
      {tabs.map((tab) => (
        <button
          key={tab.id}
          type="button"
          role="tab"
          aria-selected={tab.id === value}
          className={cx('sb-tab', tab.id === value && 'sb-tab--active')}
          onClick={() => onSelect?.(tab.id)}
        >
          {tab.label}
        </button>
      ))}
    </div>
  )
}
