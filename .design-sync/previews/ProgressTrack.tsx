import { Label, ProgressTrack } from '@skip-a-brainrot/ui'

export const Steps = () => (
  <div style={{ display: 'flex', flexDirection: 'column', gap: 12, width: 380 }}>
    <ProgressTrack progress={0} />
    <ProgressTrack progress={0.25} />
    <ProgressTrack progress={0.62} />
    <ProgressTrack progress={1} />
  </div>
)

export const FillColours = () => (
  <div style={{ display: 'flex', flexDirection: 'column', gap: 12, width: 380 }}>
    <ProgressTrack progress={0.7} fill="gold" />
    <ProgressTrack progress={0.7} fill="green" />
    <ProgressTrack progress={0.7} fill="blue" />
    <ProgressTrack progress={0.7} fill="purple" />
  </div>
)

export const Labelled = () => (
  <div style={{ display: 'flex', alignItems: 'center', gap: 12, width: 420 }}>
    <Label variant="meta" on="light">
      Level 12
    </Label>
    <ProgressTrack progress={0.45} height={26} style={{ flex: 1 }} />
    <Label variant="meta" on="light">
      4,500 / 10,000
    </Label>
  </div>
)
