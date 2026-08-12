import { Button } from '@skip-a-brainrot/ui'

export const Variants = () => (
  <div style={{ display: 'flex', flexWrap: 'wrap', gap: 18, alignItems: 'center' }}>
    <Button variant="gold">BUY NOW</Button>
    <Button variant="green">CLAIM</Button>
    <Button variant="red">SELL ALL</Button>
    <Button variant="blue">EQUIP</Button>
    <Button variant="purple">FUSE</Button>
  </div>
)

export const Sizes = () => (
  <div style={{ display: 'flex', gap: 18, alignItems: 'center' }}>
    <Button variant="gold" size="sm">
      SKIP
    </Button>
    <Button variant="gold" size="md">
      OPEN EGG
    </Button>
    <Button variant="gold" size="lg">
      UNLOCK PASS
    </Button>
  </div>
)

export const Disabled = () => (
  <div style={{ display: 'flex', gap: 18, alignItems: 'center' }}>
    <Button variant="green">CLAIM</Button>
    <Button variant="green" disabled>
      CLAIMED
    </Button>
    <Button variant="disabled">NOT ENOUGH COINS</Button>
  </div>
)
