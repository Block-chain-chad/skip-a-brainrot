import { Toast } from '@skip-a-brainrot/ui'

export const Tones = () => (
  <div style={{ display: 'flex', flexDirection: 'column', gap: 12, alignItems: 'flex-start' }}>
    <Toast tone="success" icon="coin">
      +2,500 Coins
    </Toast>
    <Toast tone="warn" icon="bag">
      Backpack almost full
    </Toast>
    <Toast tone="error">Not enough gems</Toast>
    <Toast icon="daily">Daily reward ready</Toast>
  </div>
)

export const Stacked = () => (
  <div style={{ display: 'flex', flexDirection: 'column', gap: 10, alignItems: 'center' }}>
    <Toast tone="success" icon="gem">
      +50 Gems
    </Toast>
    <Toast tone="success" icon="eggs">
      Forest Egg hatched
    </Toast>
  </div>
)
