import { Icon, Label, iconNames } from '@skip-a-brainrot/ui'

export const EveryIcon = () => (
  <div style={{ display: 'grid', gridTemplateColumns: 'repeat(6, 84px)', gap: 14 }}>
    {iconNames.map((name) => (
      <div key={name} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}>
        <Icon name={name} size={62} />
        <Label variant="meta" on="light">
          {name}
        </Label>
      </div>
    ))}
  </div>
)

export const Sizes = () => (
  <div style={{ display: 'flex', gap: 18, alignItems: 'flex-end' }}>
    <Icon name="coin" size={28} />
    <Icon name="coin" size={42} />
    <Icon name="coin" size={64} />
    <Icon name="coin" size={92} />
  </div>
)
