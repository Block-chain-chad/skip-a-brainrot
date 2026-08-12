import { Badge, NavRailItem } from '@skip-a-brainrot/ui'

export const Counts = () => (
  <div style={{ display: 'flex', gap: 14, alignItems: 'center' }}>
    <Badge value={1} />
    <Badge value={7} />
    <Badge value={12} />
    <Badge value="9+" />
    <Badge value="NEW" />
  </div>
)

export const OnARailItem = () => (
  <div style={{ background: 'linear-gradient(160deg, #5B8C3E, #2F4A22)', padding: 12, display: 'flex' }}>
    <NavRailItem icon="daily" label="Daily" badge={3} />
    <NavRailItem icon="goals" label="Goals" badge="9+" />
  </div>
)
