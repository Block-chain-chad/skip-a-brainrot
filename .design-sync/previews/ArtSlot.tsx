import { ArtSlot, Icon, Label } from '@skip-a-brainrot/ui'

const cell = { display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6 } as const

export const WithArt = () => (
  <div style={{ display: 'flex', gap: 14 }}>
    <ArtSlot size={104}>
      <Icon name="eggs" size={68} />
    </ArtSlot>
    <ArtSlot size={104}>
      <Icon name="coin" size={68} />
    </ArtSlot>
    <ArtSlot size={104}>
      <Icon name="gem" size={68} />
    </ArtSlot>
  </div>
)

/**
 * The kit deviation `UI.artSlot` documents: an empty-string image must render the
 * placeholder, not an invisible slot — so a missing upload reads as pending art
 * rather than a broken panel. Shown against a filled slot so the difference is
 * the point.
 */
export const EmptyPlaceholder = () => (
  <div style={{ display: 'flex', gap: 20, alignItems: 'flex-start' }}>
    <div style={cell}>
      <ArtSlot size={104}>
        <Icon name="skip" size={68} />
      </ArtSlot>
      <Label variant="meta" on="light">
        art present
      </Label>
    </div>
    <div style={cell}>
      <ArtSlot size={104} src="" />
      <Label variant="meta" on="light">
        src="" — placeholder
      </Label>
    </div>
  </div>
)
