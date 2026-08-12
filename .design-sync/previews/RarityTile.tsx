import { Icon, RarityTile, Ribbon } from '@skip-a-brainrot/ui'

export const Rarities = () => (
  <div style={{ display: 'flex', gap: 14 }}>
    <RarityTile rarity="common">
      <Icon name="skip" size={70} />
    </RarityTile>
    <RarityTile rarity="rare">
      <Icon name="eggs" size={70} />
    </RarityTile>
    <RarityTile rarity="epic">
      <Icon name="gem" size={70} />
    </RarityTile>
    <RarityTile rarity="legend">
      <Icon name="coin" size={70} />
    </RarityTile>
  </div>
)

export const Rings = () => (
  <div style={{ display: 'flex', gap: 22, padding: 8 }}>
    <RarityTile rarity="legend" claimable>
      <Icon name="daily" size={70} />
    </RarityTile>
    <RarityTile rarity="epic" rainbow>
      <Icon name="gem" size={70} />
    </RarityTile>
  </div>
)

export const InBagGrid = () => (
  <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, auto)', gap: 11 }}>
    <div style={{ position: 'relative' }}>
      <RarityTile rarity="legend" size={96}>
        <Icon name="coin" size={58} />
      </RarityTile>
      <span style={{ position: 'absolute', bottom: -8, left: 8 }}>
        <Ribbon variant="EQUIPPED" />
      </span>
    </div>
    <RarityTile rarity="epic" size={96}>
      <Icon name="gem" size={58} />
    </RarityTile>
    <RarityTile rarity="rare" size={96}>
      <Icon name="eggs" size={58} />
    </RarityTile>
    <RarityTile rarity="common" size={96}>
      <Icon name="bag" size={58} />
    </RarityTile>
  </div>
)
