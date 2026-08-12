import { Label, Surface } from '@skip-a-brainrot/ui'

const box = { width: 190, height: 96, display: 'grid', placeItems: 'center' } as const

export const Kinds = () => (
  <div style={{ display: 'flex', flexWrap: 'wrap', gap: 16 }}>
    <Surface kind="panel" style={box}>
      <Label variant="cardLabel" on="light">
        panel
      </Label>
    </Surface>
    <Surface kind="subPanel" style={box}>
      <Label variant="cardLabel" on="light">
        subPanel
      </Label>
    </Surface>
    <Surface kind="row" style={box}>
      <Label variant="cardLabel">row</Label>
    </Surface>
    <Surface kind="slot" style={box}>
      <Label variant="cardLabel">slot</Label>
    </Surface>
    <Surface kind="tab" style={box}>
      <Label variant="cardLabel" on="light">
        tab
      </Label>
    </Surface>
    <Surface kind="track" style={box}>
      <Label variant="cardLabel">track</Label>
    </Surface>
  </div>
)

export const Treatments = () => (
  <div style={{ display: 'flex', gap: 22, paddingBottom: 10 }}>
    <Surface kind="panel" style={box}>
      <Label variant="cardLabel" on="light">
        plain
      </Label>
    </Surface>
    <Surface kind="panel" shadowed style={box}>
      <Label variant="cardLabel" on="light">
        shadowed
      </Label>
    </Surface>
    <Surface kind="panel" shadowed keyline style={box}>
      <Label variant="cardLabel" on="light">
        + keyline
      </Label>
    </Surface>
    <Surface kind="row" gloss style={box}>
      <Label variant="cardLabel">+ gloss</Label>
    </Surface>
  </div>
)
