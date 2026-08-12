import {
  Button,
  CurrencyPill,
  Icon,
  Label,
  Panel,
  ProgressTrack,
  QuestRow,
  RarityTile,
  TabBar,
} from '@skip-a-brainrot/ui'

export const GoalsPanel = () => (
  <Panel title="Goals" icon="goals" width={620} onClose={() => {}}>
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
  </Panel>
)

export const BackpackPanel = () => (
  <Panel title="Backpack" icon="bag" width={560} onClose={() => {}}>
    <TabBar
      value="brainrots"
      tabs={[
        { id: 'brainrots', label: 'Brainrots' },
        { id: 'pets', label: 'Pets' },
        { id: 'keys', label: 'Keys' },
      ]}
    />
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, auto)', gap: 11 }}>
      <RarityTile rarity="legend" size={104}>
        <Icon name="coin" size={62} />
      </RarityTile>
      <RarityTile rarity="epic" size={104}>
        <Icon name="gem" size={62} />
      </RarityTile>
      <RarityTile rarity="rare" size={104}>
        <Icon name="eggs" size={62} />
      </RarityTile>
      <RarityTile rarity="common" size={104}>
        <Icon name="skip" size={62} />
      </RarityTile>
    </div>
    <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
      <Label variant="meta" on="light">
        Storage 24 / 60
      </Label>
      <ProgressTrack progress={0.4} height={20} style={{ flex: 1 }} />
    </div>
  </Panel>
)

export const Unheaded = () => (
  <Panel width={420}>
    <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
      <CurrencyPill currency="coin" value="12.4K" />
      <CurrencyPill currency="gem" value="318" />
    </div>
  </Panel>
)
