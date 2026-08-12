import { NavRail, NavRailItem } from '@skip-a-brainrot/ui'

export const TwoByThree = () => (
  <div style={{ background: 'linear-gradient(160deg, #5B8C3E, #2F4A22)', padding: 12 }}>
    <NavRail rows={3}>
      <NavRailItem icon="shops" label="Shops" />
      <NavRailItem icon="bag" label="Bag" badge={3} />
      <NavRailItem icon="index" label="Index" />
      <NavRailItem icon="pass" label="Pass" active />
      <NavRailItem icon="goals" label="Goals" />
      <NavRailItem icon="daily" label="Daily" badge="9+" />
    </NavRail>
  </div>
)

export const SingleColumn = () => (
  <div style={{ background: 'linear-gradient(160deg, #5B8C3E, #2F4A22)', padding: 12 }}>
    <NavRail rows={3}>
      <NavRailItem icon="plot" label="Plot" />
      <NavRailItem icon="eggs" label="Eggs" active />
      <NavRailItem icon="settings" label="Settings" />
    </NavRail>
  </div>
)
