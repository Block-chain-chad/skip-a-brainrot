import { AccentCard, Icon, Label } from '@skip-a-brainrot/ui'

const card = { width: 176, height: 150 } as const

export const RarityAccents = () => (
  <div style={{ display: 'flex', gap: 14 }}>
    <AccentCard accent="#C9CCC2" style={card}>
      <Icon name="skip" size={54} />
      <Label variant="cardLabel" on="light">
        Common
      </Label>
    </AccentCard>
    <AccentCard accent="#3FA9F5" style={card}>
      <Icon name="eggs" size={54} />
      <Label variant="cardLabel" on="light">
        Rare
      </Label>
    </AccentCard>
    <AccentCard accent="#A855F7" style={card}>
      <Icon name="gem" size={54} />
      <Label variant="cardLabel" on="light">
        Epic
      </Label>
    </AccentCard>
    <AccentCard accent="#FFB200" style={card}>
      <Icon name="coin" size={54} />
      <Label variant="cardLabel" on="light">
        Legendary
      </Label>
    </AccentCard>
  </div>
)

export const CopyOnCard = () => (
  <AccentCard accent="#7CE04A" style={{ width: 320, height: 140 }}>
    <Label variant="cardLabel" on="light">
      Daily streak kept
    </Label>
    <Label variant="meta" on="light">
      Come back tomorrow for day 4. Missing a day resets the streak to day 1.
    </Label>
  </AccentCard>
)
