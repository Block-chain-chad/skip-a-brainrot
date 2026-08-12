import { Icon, RewardCard } from '@skip-a-brainrot/ui'

export const Tracks = () => (
  <div style={{ display: 'flex', gap: 18, paddingTop: 18 }}>
    <RewardCard tier={4} track="free" label="500 Coins">
      <Icon name="coin" />
    </RewardCard>
    <RewardCard tier={5} track="pass" label="Golden Crate">
      <Icon name="eggs" />
    </RewardCard>
  </div>
)

export const States = () => (
  <div style={{ display: 'flex', gap: 18, paddingTop: 18 }}>
    <RewardCard tier={1} track="pass" label="50 Gems" claimed>
      <Icon name="gem" />
    </RewardCard>
    <RewardCard tier={2} track="pass" label="Lucky Charm" claimable>
      <Icon name="goals" />
    </RewardCard>
    <RewardCard tier={3} track="pass" label="Mystery Pet" locked>
      <Icon name="bag" />
    </RewardCard>
  </div>
)

export const LadderRow = () => (
  <div style={{ display: 'flex', gap: 14, paddingTop: 18 }}>
    <RewardCard tier={6} track="free" label="250 Coins" claimed>
      <Icon name="coin" />
    </RewardCard>
    <RewardCard tier={7} track="free" label="1 Key" claimable>
      <Icon name="index" />
    </RewardCard>
    <RewardCard tier={8} track="free" label="Forest Egg" locked>
      <Icon name="eggs" />
    </RewardCard>
    <RewardCard tier={9} track="free" label="Grand Prize" locked>
      <Icon name="skip" />
    </RewardCard>
  </div>
)
