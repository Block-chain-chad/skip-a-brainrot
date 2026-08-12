import { CurrencyPill } from '@skip-a-brainrot/ui'

export const Currencies = () => (
  <div style={{ display: 'flex', gap: 14, alignItems: 'center' }}>
    <CurrencyPill currency="coin" value="12.4K" />
    <CurrencyPill currency="gem" value="318" />
  </div>
)

export const HudStrip = () => (
  <div
    style={{
      background: 'linear-gradient(160deg, #5B8C3E, #2F4A22)',
      padding: 16,
      display: 'flex',
      gap: 12,
      alignItems: 'center',
    }}
  >
    <CurrencyPill currency="coin" value="1.28M" />
    <CurrencyPill currency="gem" value="4,109" />
  </div>
)
