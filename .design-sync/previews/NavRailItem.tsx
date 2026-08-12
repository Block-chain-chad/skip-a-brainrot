import { NavRailItem } from '@skip-a-brainrot/ui'

const world = { background: 'linear-gradient(160deg, #5B8C3E, #2F4A22)', padding: 12, display: 'flex', gap: 4 } as const

export const States = () => (
  <div style={world}>
    <NavRailItem icon="pass" label="Pass" />
    <NavRailItem icon="pass" label="Pass" active />
    <NavRailItem icon="pass" label="Pass" badge={3} />
    <NavRailItem icon="pass" label="Pass" active badge="9+" />
  </div>
)

export const EveryDestination = () => (
  <div style={world}>
    <NavRailItem icon="shops" label="Shops" />
    <NavRailItem icon="bag" label="Bag" />
    <NavRailItem icon="index" label="Index" />
    <NavRailItem icon="goals" label="Goals" />
    <NavRailItem icon="daily" label="Daily" />
  </div>
)
