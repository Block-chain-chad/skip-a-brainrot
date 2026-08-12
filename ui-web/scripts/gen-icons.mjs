// Generates src/components/Icon.tsx from the design handoff kit's own SVGs.
// The art is copied verbatim; only two things change:
//   1. attributes are camelCased for JSX
//   2. gradient/filter ids are namespaced per icon — every source file declares
//      id="a", id="b", so inlining two icons on one page would make the second
//      one's url(#a) resolve to the first one's gradient.
import { readFileSync, writeFileSync, readdirSync } from 'node:fs'
import { join, basename } from 'node:path'

const SRC = process.argv[2]
const OUT = process.argv[3]

const ATTR = {
  'stroke-width': 'strokeWidth',
  'stroke-linejoin': 'strokeLinejoin',
  'stroke-linecap': 'strokeLinecap',
  'stroke-dasharray': 'strokeDasharray',
  'stroke-opacity': 'strokeOpacity',
  'fill-opacity': 'fillOpacity',
  'fill-rule': 'fillRule',
  'clip-rule': 'clipRule',
  'clip-path': 'clipPath',
  'stop-color': 'stopColor',
  'stop-opacity': 'stopOpacity',
  'text-anchor': 'textAnchor',
  'font-size': 'fontSize',
  'font-family': 'fontFamily',
  'paint-order': 'paintOrder',
  'gradientUnits': 'gradientUnits',
  'xmlns:xlink': 'xmlnsXlink',
}

const files = readdirSync(SRC).filter((f) => f.endsWith('.svg')).sort()
const icons = []

for (const file of files) {
  const name = basename(file, '.svg')
  let svg = readFileSync(join(SRC, file), 'utf8').trim()

  // inner markup only — the <svg> wrapper is re-emitted by the component
  const viewBox = /viewBox="([^"]+)"/.exec(svg)?.[1] ?? '0 0 64 64'
  let inner = svg.replace(/^<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '')

  // namespace every id this file declares, and every reference to one
  const ids = [...inner.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1])
  for (const id of ids) {
    const ns = `${name}-${id}`
    inner = inner.replaceAll(` id="${id}"`, ` id="${ns}"`)
    inner = inner.replaceAll(`url(#${id})`, `url(#${ns})`)
    inner = inner.replaceAll(`xlink:href="#${id}"`, `xlink:href="#${ns}"`)
  }

  for (const [from, to] of Object.entries(ATTR)) inner = inner.replaceAll(`${from}=`, `${to}=`)
  inner = inner.replace(/><\/(circle|path|polygon|rect|ellipse|line|polyline|stop|use)>/g, ' />')

  icons.push({ name, viewBox, inner })
}

const names = icons.map((i) => i.name)

const out = `/**
 * Icon — the game's HUD icon set.
 *
 * GENERATED from docs/design-handoff/ui-kit/design_handoff_game_ui/icons/*.svg,
 * the same art whose 512px PNG exports are uploaded as the live rbxassetid icons
 * in Tokens.lua. Do not hand-edit: re-run scripts/gen-icons.mjs after changing an SVG.
 *
 * These predate the 2026-08-04 restyle, so their outline is the older #16170F
 * rather than Tokens.lua's current #202020. That is deliberate — this is the
 * shipped art, matching what the game renders today.
 */
import type { SVGProps } from 'react'

/** Every icon in the kit. */
export type IconName =
${names.map((n) => `  | '${n}'`).join('\n')}

export const iconNames: readonly IconName[] = [
${names.map((n) => `  '${n}',`).join('\n')}
]

const PATHS: Record<IconName, { viewBox: string; body: JSX.Element }> = {
${icons
  .map(
    (i) => `  '${i.name}': {
    viewBox: '${i.viewBox}',
    body: (
      <>
        ${i.inner.trim()}
      </>
    ),
  },`,
  )
  .join('\n')}
}

export interface IconProps extends Omit<SVGProps<SVGSVGElement>, 'name'> {
  /** Which icon to render. */
  name: IconName
  /** Width and height in px. Defaults to filling its container. */
  size?: number
}

/**
 * Renders one of the kit's icons as inline SVG.
 *
 * @example
 * <Icon name="coin" size={42} />
 */
export function Icon({ name, size, className, style, ...rest }: IconProps) {
  const icon = PATHS[name]
  return (
    <svg
      viewBox={icon.viewBox}
      width={size}
      height={size}
      className={['sb-icon', className].filter(Boolean).join(' ')}
      style={size ? { width: size, height: size, ...style } : style}
      role="img"
      aria-label={name}
      {...rest}
    >
      {icon.body}
    </svg>
  )
}
`

writeFileSync(OUT, out)
console.log(`${icons.length} icons -> ${OUT}`)
console.log(`  ${names.join(', ')}`)
