import { TabBar } from '@skip-a-brainrot/ui'

export const Backpack = () => (
  <TabBar
    value="brainrots"
    tabs={[
      { id: 'brainrots', label: 'Brainrots' },
      { id: 'pets', label: 'Pets' },
      { id: 'keys', label: 'Keys' },
      { id: 'tags', label: 'Tags' },
    ]}
  />
)

export const SelectionMoves = () => (
  <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
    <TabBar
      value="free"
      tabs={[
        { id: 'free', label: 'Free' },
        { id: 'pass', label: 'Pass' },
      ]}
    />
    <TabBar
      value="pass"
      tabs={[
        { id: 'free', label: 'Free' },
        { id: 'pass', label: 'Pass' },
      ]}
    />
  </div>
)
