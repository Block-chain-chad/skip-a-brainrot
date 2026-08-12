import { Label, Surface } from '@skip-a-brainrot/ui'

export const TypeRamp = () => (
  <Surface kind="row" style={{ padding: 20, display: 'flex', flexDirection: 'column', gap: 12, width: 460 }}>
    <Label variant="panelTitle">Season Pass</Label>
    <Label variant="buttonL">UNLOCK PASS</Label>
    <Label variant="buttonM">CLAIM</Label>
    <Label variant="value">12,480</Label>
    <Label variant="cardLabel">Golden Crate</Label>
    <Label variant="chip">x3</Label>
    <Label variant="railLabel">Bag</Label>
    <Label variant="meta" color="var(--sb-text-muted)">
      Resets in 4 days. Rewards not claimed by then are lost.
    </Label>
  </Surface>
)

export const OnLightAndDark = () => (
  <div style={{ display: 'flex', gap: 16 }}>
    <Surface kind="panel" style={{ padding: 18, width: 230 }}>
      <Label variant="cardLabel" on="light">
        On the window
      </Label>
    </Surface>
    <Surface kind="slot" style={{ padding: 18, width: 230 }}>
      <Label variant="cardLabel">On a slot</Label>
    </Surface>
  </div>
)
