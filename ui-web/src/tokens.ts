/**
 * Design tokens for the Skip a Brainrot HUD — a direct port of
 * `ReplicatedStorage/Modules/UIKit/Tokens.lua`. Names and values match the Luau
 * source one-for-one so a change on either side is a visible diff on the other.
 *
 * Current style: the 2026-08-04 "Roblox Simulator UI Style Guide" pass —
 * Pet-Simulator-inspired. Light gray window, ONE red header, dark gray slots,
 * 4px near-black outer stroke with a 2px white inner keyline.
 *
 * Design canvas: 1350 x 775. Every number below is offset px at that size.
 */

/** Vertical gradient stops, top -> bottom. Roblox `UIGradient` at Rotation 90. */
export type GradientStops = readonly string[]

export const canvas = { width: 1350, height: 775 } as const

export const color = {
  outline: '#202020',
  innerKeyline: '#FFFFFF',

  panelTop: '#D6D6D6',
  panelBottom: '#A9A9A9',
  subPanelTop: '#C4C4C4',
  subPanelBottom: '#9C9C9C',
  rowTop: '#4A4A4A',
  rowBottom: '#363636',
  tabTop: '#BEBEBE',
  tabBottom: '#9C9C9C',
  trackTop: '#2E2E2E',
  trackBottom: '#3A3A3A',
  slotTop: '#4A4A4A',
  slotBottom: '#363636',
  headerTop: '#F96B57',
  headerBottom: '#C84535',

  white: '#FFFFFF',
  textMuted: '#D8D8D8',
  textAccent: '#FFD84D',
  textOnLight: '#2A2A2A',
  textOnWindow: '#2A2A2A',
  textOnGoldCard: '#3A2A05',
  textOnGoldChrome: '#5A4A12',
  textDisabled: '#B8C4A4',
  textClaimed: '#9FAE8B',

  claimRing: '#7CE04A',
  activeRing: '#FFD84D',
  /** Nav-rail active radial glow. Distinct from `activeRing`, which panels' tabs use. */
  activeGlow: '#FFE87A',
  scrollThumb: '#9FAE8B',

  rarityCommon: '#C9CCC2',
  rarityRare: '#3FA9F5',
  rarityEpic: '#A855F7',
  rarityLegend: '#FFB200',
} as const

/** Modal scrim. Roblox sets BackgroundTransparency 0.50, i.e. 50% opaque. */
export const scrim = { color: '#0A0E06', alpha: 0.5 } as const

export const gradient = {
  gold: ['#FFE87A', '#FFC531', '#E08A0C'],
  goldSmall: ['#FFE066', '#FFC531', '#E8930F'],
  green: ['#83E34A', '#4FB42E'],
  purple: ['#DE93FF', '#B04CEC', '#7C1CC0'],
  red: ['#FF6B6B', '#D83E3E'],
  blue: ['#56B7FF', '#2E81D8'],
  gem: ['#D98BFF', '#A93FE6', '#7A1CB8'],

  panel: ['#D6D6D6', '#A9A9A9'],
  subPanel: ['#C4C4C4', '#9C9C9C'],
  row: ['#4A4A4A', '#363636'],
  tab: ['#BEBEBE', '#9C9C9C'],
  track: ['#2E2E2E', '#3A3A3A'],
  slot: ['#4A4A4A', '#363636'],
  header: ['#F96B57', '#C84535'],
  window: ['#D6D6D6', '#A9A9A9'],

  freeCard: ['#F7F7F1', '#DEDED4', '#B2B4A8'],
  /** Legacy alias — the pre-2026-08-04 cream body, now pointing at the window gray. */
  cream: ['#D6D6D6', '#A9A9A9'],
  passCard: ['#FFE066', '#F7B62C', '#D8860E'],
  lockBadge: ['#F2F2EC', '#C2C4B8'],
  knob: ['#FFF0A8', '#FFC531'],
  disabled: ['#6A7757', '#454F33'],
  ownedCta: ['#8FA378', '#54643C'],
  freeLabel: ['#7A8A66', '#55643F'],
  passLabel: ['#FFD84D', '#E0912A'],
} as const satisfies Record<string, GradientStops>

export type GradientName = keyof typeof gradient

/** Outer stroke widths. Guide: "outer stroke 4px dark gray, inner stroke 1-2px white". */
export const stroke = { panel: 4, control: 3, chip: 3, hairline: 2, inner: 2 } as const

/** Guide: "Panels 8px, Buttons 10-14px, Slots 8px". */
export const radius = {
  panel: 8,
  control: 12,
  inner: 10,
  small: 10,
  chip: 10,
  slot: 8,
  art: 8,
  pill: 999,
} as const

/** Hard offset shadow distance = stroke + 1. */
export const shadowOffset = { panel: 6, control: 5, chip: 4 } as const

/**
 * Top white gloss strip and bottom dark shade.
 * `alpha`/`alphaLight` are opacities; `shadeAlpha` is Roblox BackgroundTransparency,
 * so the shade renders at `1 - shadeAlpha` opacity.
 */
export const gloss = {
  height: 5,
  alpha: 0.45,
  alphaLight: 0.3,
  shadeHeight: 6,
  shadeAlpha: 0.82,
} as const

export const pad = { panel: 16, panelWide: 18, gap: 12, gapTight: 8, gridGap: 11, rowGap: 10 } as const

export const size = {
  headerHeight: 92,
  headerIcon: 64,
  closeButton: { width: 74, height: 66 },
  /** v2 rail: a bare floating icon in a 106px column, no button plate. */
  railItem: 106,
  railIcon: 66,
  railGap: 6,
  railInset: 10,
  railGlow: 88,
  railSide: 'left',
  currencyPill: 54,
  rewardCard: { width: 178, height: 186 },
  tierBadge: 58,
  lockBadge: 46,
  claimPill: 38,
  bagSlot: 118,
  dayCard: 196,
  questRow: 88,
  panelWidth: {
    pass: 960,
    backpack: 960,
    settings: 700,
    daily: 800,
    index: 940,
    goals: 860,
    eggs: 940,
  },
  /** Reserves the nav rail column. */
  panelRightGutter: 132,
} as const

/**
 * Type ramp as `[size, textStrokeThickness]`, matching `T.text` in the Luau source.
 * Guide: "Titles 28-34, Buttons 18-24, Labels 14-18".
 */
export const text = {
  panelTitle: [32, 3],
  buttonL: [24, 2.5],
  buttonM: [20, 2],
  value: [22, 2],
  cardLabel: [17, 2],
  chip: [14, 1.5],
  railLabel: [20, 4],
  /** Body copy — no stroke. */
  meta: [14, 0],
} as const satisfies Record<string, readonly [number, number]>

export type TextStyle = keyof typeof text

/**
 * Display face is Fredoka One, body is Nunito — the families the design handoff
 * kit uses. In Roblox both fall back to GothamBold, which is what the engine has.
 */
export const font = {
  display: "'Fredoka One', system-ui, sans-serif",
  ui: "'Nunito', system-ui, sans-serif",
} as const

/** Durations in ms; Roblox `TweenInfo` seconds x1000. */
export const tween = {
  hover: 120,
  press: 80,
  panelOpen: 180,
  panelClose: 120,
  scrim: 150,
  pop: 220,
  fly: 380,
  bar: 400,
  pulsePeriod: 1600,
  bobPeriod: 1400,
  claimStagger: 60,
} as const

export const zIndex = { world: 0, currency: 20, panel: 25, rail: 30, kit: 50, toast: 80 } as const

/** CSS `linear-gradient` for a named token gradient, top -> bottom. */
export function gradientCss(name: GradientName): string {
  const stops = gradient[name]
  if (stops.length === 3) return `linear-gradient(180deg, ${stops[0]} 0%, ${stops[1]} 52%, ${stops[2]} 100%)`
  return `linear-gradient(180deg, ${stops.join(', ')})`
}
