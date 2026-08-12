import { PanelHeader, Surface } from '@skip-a-brainrot/ui'

export const WithIconAndClose = () => (
  <Surface kind="panel" shadowed keyline style={{ width: 560, overflow: 'hidden' }}>
    <PanelHeader icon="pass" title="Season Pass" onClose={() => {}} />
  </Surface>
)

export const TitleOnly = () => (
  <Surface kind="panel" shadowed keyline style={{ width: 560, overflow: 'hidden' }}>
    <PanelHeader title="Settings" onClose={() => {}} />
  </Surface>
)

export const NoClose = () => (
  <Surface kind="panel" shadowed keyline style={{ width: 560, overflow: 'hidden' }}>
    <PanelHeader icon="index" title="Brainrot Index" />
  </Surface>
)
