import { Medallion } from '@skip-a-brainrot/ui'

export const Tiers = () => (
  <div style={{ display: 'flex', gap: 14, alignItems: 'center' }}>
    <Medallion>1</Medallion>
    <Medallion>7</Medallion>
    <Medallion>25</Medallion>
    <Medallion size={46}>3</Medallion>
    <Medallion size={72}>50</Medallion>
  </div>
)

export const Colours = () => (
  <div style={{ display: 'flex', gap: 14, alignItems: 'center' }}>
    <Medallion>1</Medallion>
    <Medallion color="#3FA9F5">2</Medallion>
    <Medallion color="#A855F7">3</Medallion>
    <Medallion color="#7CE04A">4</Medallion>
  </div>
)
