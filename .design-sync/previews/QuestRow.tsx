import { Button, Icon, QuestRow, Ribbon } from '@skip-a-brainrot/ui'

export const Lifecycle = () => (
  <div style={{ display: 'flex', flexDirection: 'column', gap: 12, width: 620 }}>
    <QuestRow
      title="Catch 10 brainrots"
      progress={0.4}
      caption="4 / 10"
      art={<Icon name="skip" size={56} />}
      action={
        <Button variant="disabled" size="sm">
          CLAIM
        </Button>
      }
    />
    <QuestRow
      title="Open 3 Forest Eggs"
      progress={1}
      caption="3 / 3"
      art={<Icon name="eggs" size={56} />}
      action={
        <Button variant="green" size="sm">
          CLAIM
        </Button>
      }
    />
    <QuestRow
      title="Skip 25 rocks"
      progress={1}
      caption="25 / 25"
      art={<Icon name="goals" size={56} />}
      action={<Ribbon variant="EQUIPPED">DONE</Ribbon>}
    />
  </div>
)

export const Minimal = () => (
  <div style={{ width: 520 }}>
    <QuestRow title="Reach level 20" progress={0.65} caption="13 / 20" />
  </div>
)
