import { CloseButton, PanelHeader, Surface } from '@skip-a-brainrot/ui'

export const Standalone = () => (
  <div style={{ padding: 8 }}>
    <CloseButton />
  </div>
)

export const InHeader = () => (
  <Surface kind="panel" shadowed keyline style={{ width: 480, overflow: 'hidden' }}>
    <PanelHeader icon="settings" title="Settings" onClose={() => {}} />
  </Surface>
)
