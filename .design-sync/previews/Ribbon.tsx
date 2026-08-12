import { Icon, RarityTile, Ribbon } from '@skip-a-brainrot/ui'

export const Variants = () => (
  <div style={{ display: 'flex', gap: 14, alignItems: 'center' }}>
    <Ribbon variant="EQUIPPED" />
    <Ribbon variant="GRAND" />
    <Ribbon variant="NEW" />
  </div>
)

export const CustomText = () => (
  <div style={{ display: 'flex', gap: 14, alignItems: 'center' }}>
    <Ribbon variant="GRAND">GRAND PRIZE</Ribbon>
    <Ribbon variant="NEW">x3</Ribbon>
    <Ribbon variant="EQUIPPED">BEST</Ribbon>
  </div>
)

export const OnATile = () => (
  <div style={{ display: 'flex', gap: 20, padding: '0 0 12px' }}>
    <div style={{ position: 'relative' }}>
      <RarityTile rarity="legend" size={104}>
        <Icon name="coin" size={62} />
      </RarityTile>
      <span style={{ position: 'absolute', bottom: -8, left: 10 }}>
        <Ribbon variant="EQUIPPED" />
      </span>
    </div>
    <div style={{ position: 'relative' }}>
      <RarityTile rarity="epic" size={104}>
        <Icon name="gem" size={62} />
      </RarityTile>
      <span style={{ position: 'absolute', bottom: -8, left: 22 }}>
        <Ribbon variant="NEW" />
      </span>
    </div>
  </div>
)
