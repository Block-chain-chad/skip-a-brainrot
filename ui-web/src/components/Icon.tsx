/**
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
  | 'bag'
  | 'coin'
  | 'daily'
  | 'eggs'
  | 'gem'
  | 'goals'
  | 'index'
  | 'pass'
  | 'plot'
  | 'settings'
  | 'shops'
  | 'skip'

export const iconNames: readonly IconName[] = [
  'bag',
  'coin',
  'daily',
  'eggs',
  'gem',
  'goals',
  'index',
  'pass',
  'plot',
  'settings',
  'shops',
  'skip',
]

const PATHS: Record<IconName, { viewBox: string; body: JSX.Element }> = {
  'bag': {
    viewBox: '-5 -5 74 74',
    body: (
      <>
        <defs><linearGradient id="bag-a" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#FF7F5F" /><stop offset="1" stopColor="#C22B18" /></linearGradient><linearGradient id="bag-b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#E8543A" /><stop offset="1" stopColor="#A02010" /></linearGradient></defs><path d="M23 25 C23 9 41 9 41 25" fill="none" stroke="#16170F" strokeWidth="16" strokeLinejoin="round" strokeLinecap="round" /><rect x="9" y="22" width="46" height="34" rx="10" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><path d="M9 32 v-2 a10 10 0 0 1 10-10 h26 a10 10 0 0 1 10 10 v2 z" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="26" y="34" width="12" height="9" rx="3" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><path d="M23 25 C23 9 41 9 41 25" fill="none" stroke="#3F4038" strokeWidth="7" strokeLinecap="round" strokeLinejoin="round" /><rect x="9" y="22" width="46" height="34" rx="10" fill="url(#bag-a)" /><path d="M9 32 v-2 a10 10 0 0 1 10-10 h26 a10 10 0 0 1 10 10 v2 z" fill="url(#bag-b)" /><rect x="26" y="34" width="12" height="9" rx="3" fill="#FFD84D" stroke="#16170F" strokeWidth="3" /><rect x="14" y="26" width="12" height="5" rx="2.5" fill="#FFFFFF" opacity="0.4" />
      </>
    ),
  },
  'coin': {
    viewBox: '-5 -5 74 74',
    body: (
      <>
        <defs><linearGradient id="coin-a" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#FFE87A" /><stop offset="1" stopColor="#E8930F" /></linearGradient><linearGradient id="coin-b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#FFF3C4" /><stop offset="1" stopColor="#F5C13A" /></linearGradient></defs><circle cx="32" cy="32" r="25" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><circle cx="32" cy="32" r="18" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><polygon points="32,25 33.9,29.6 38.8,30 35.1,33.2 36.2,38 32,35.5 27.8,38 28.9,33.2 25.2,30 30.1,29.6" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><circle cx="32" cy="32" r="25" fill="url(#coin-a)" /><circle cx="32" cy="32" r="18" fill="url(#coin-b)" stroke="#16170F" strokeWidth="3.5" /><polygon points="32,25 33.9,29.6 38.8,30 35.1,33.2 36.2,38 32,35.5 27.8,38 28.9,33.2 25.2,30 30.1,29.6" fill="#E8930F" /><path d="M17 25 A19 19 0 0 1 30 14" fill="none" stroke="#FFFFFF" strokeWidth="5" strokeLinecap="round" strokeLinejoin="round" />
      </>
    ),
  },
  'daily': {
    viewBox: '-5 -5 74 74',
    body: (
      <>
        <defs><linearGradient id="daily-a" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#FAFAF4" /><stop offset="1" stopColor="#BFC1B5" /></linearGradient><linearGradient id="daily-b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#FF6B5A" /><stop offset="1" stopColor="#C8231C" /></linearGradient></defs><rect x="8" y="13" width="48" height="45" rx="9" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="18" y="6" width="7" height="14" rx="3.5" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="39" y="6" width="7" height="14" rx="3.5" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><path d="M8 27 v-5 a9 9 0 0 1 9-9 h30 a9 9 0 0 1 9 9 v5 z" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="15" y="33" width="8" height="7" rx="2" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="28" y="33" width="8" height="7" rx="2" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="41" y="33" width="8" height="7" rx="2" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="15" y="45" width="8" height="7" rx="2" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="28" y="45" width="8" height="7" rx="2" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="41" y="45" width="8" height="7" rx="2" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="8" y="13" width="48" height="45" rx="9" fill="url(#daily-a)" /><rect x="18" y="6" width="7" height="14" rx="3.5" fill="#3F4038" /><rect x="39" y="6" width="7" height="14" rx="3.5" fill="#3F4038" /><path d="M8 27 v-5 a9 9 0 0 1 9-9 h30 a9 9 0 0 1 9 9 v5 z" fill="url(#daily-b)" /><rect x="15" y="33" width="8" height="7" rx="2" fill="#8D9C79" /><rect x="28" y="33" width="8" height="7" rx="2" fill="#8D9C79" /><rect x="41" y="33" width="8" height="7" rx="2" fill="#8D9C79" /><rect x="15" y="45" width="8" height="7" rx="2" fill="#8D9C79" /><rect x="28" y="45" width="8" height="7" rx="2" fill="#FFC531" stroke="#16170F" strokeWidth="2.5" /><rect x="41" y="45" width="8" height="7" rx="2" fill="#8D9C79" />
      </>
    ),
  },
  'eggs': {
    viewBox: '-5 -5 74 74',
    body: (
      <>
        <defs><linearGradient id="eggs-a" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#F7FBE6" /><stop offset="1" stopColor="#BFCF8E" /></linearGradient><linearGradient id="eggs-b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#A6EE72" /><stop offset="1" stopColor="#3E9E22" /></linearGradient></defs><path d="M32 4 C45 4 53 22 53 35 A21 21 0 0 1 11 35 C11 22 19 4 32 4 Z" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><path d="M32 4 C45 4 53 22 53 35 A21 21 0 0 1 11 35 C11 22 19 4 32 4 Z" fill="url(#eggs-a)" /><path d="M32 4 C24 12 20 26 22 40 C24 50 29 55 33 56 A21 21 0 0 1 11 35 C11 22 19 4 32 4 Z" fill="#FFFFFF" opacity="0.5" /><circle cx="40" cy="22" r="5" fill="url(#eggs-b)" stroke="#16170F" strokeWidth="2.5" /><circle cx="24" cy="34" r="4" fill="url(#eggs-b)" stroke="#16170F" strokeWidth="2.5" /><circle cx="39" cy="41" r="6" fill="url(#eggs-b)" stroke="#16170F" strokeWidth="2.5" /><path d="M23 13 C25 8 29 6 32 6" fill="none" stroke="#FFFFFF" strokeWidth="4" strokeLinecap="round" strokeLinejoin="round" />
      </>
    ),
  },
  'gem': {
    viewBox: '-5 -5 74 74',
    body: (
      <>
        <defs><linearGradient id="gem-a" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#E9B4FF" /><stop offset="1" stopColor="#7A1CB8" /></linearGradient></defs><polygon points="32,7 55,25 32,58 9,25" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><polygon points="32,7 42,25 32,58 22,25" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><path d="M9 25 H55" fill="none" stroke="#16170F" strokeWidth="12" strokeLinejoin="round" strokeLinecap="round" /><polygon points="32,7 55,25 32,58 9,25" fill="url(#gem-a)" /><polygon points="32,7 42,25 32,58 22,25" fill="#FFFFFF" opacity="0.22" /><path d="M9 25 H55" fill="none" stroke="#4E0F78" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" /><polygon points="24,12 30,10 26,22 20,22" fill="#FFFFFF" opacity="0.5" />
      </>
    ),
  },
  'goals': {
    viewBox: '-5 -5 74 74',
    body: (
      <>
        <defs><linearGradient id="goals-a" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#F7F7F1" /><stop offset="1" stopColor="#B4B6AC" /></linearGradient><linearGradient id="goals-b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#DE93FF" /><stop offset="1" stopColor="#8B2FD6" /></linearGradient></defs><rect x="10" y="12" width="44" height="46" rx="9" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="23" y="5" width="18" height="13" rx="5" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><path d="M20 37 l7 8 l17 -19" fill="none" stroke="#16170F" strokeWidth="17" strokeLinejoin="round" strokeLinecap="round" /><rect x="10" y="12" width="44" height="46" rx="9" fill="url(#goals-a)" /><rect x="23" y="5" width="18" height="13" rx="5" fill="url(#goals-b)" /><path d="M20 37 l7 8 l17 -19" fill="none" stroke="#4FBE28" strokeWidth="8" strokeLinecap="round" strokeLinejoin="round" /><rect x="15" y="17" width="12" height="4" rx="2" fill="#FFFFFF" opacity="0.55" />
      </>
    ),
  },
  'index': {
    viewBox: '-5 -5 74 74',
    body: (
      <>
        <defs><linearGradient id="index-a" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#6FD8FF" /><stop offset="1" stopColor="#125FA8" /></linearGradient><linearGradient id="index-b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#3AA7E8" /><stop offset="1" stopColor="#0D4A85" /></linearGradient></defs><rect x="9" y="10" width="46" height="44" rx="7" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="19" y="15" width="31" height="34" rx="4" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="9" y="10" width="11" height="44" rx="5" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><polygon points="40,10 51,10 51,32 45.5,26 40,32" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="24" y="21" width="20" height="3.5" rx="1.75" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="24" y="29" width="20" height="3.5" rx="1.75" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="24" y="37" width="13" height="3.5" rx="1.75" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="9" y="10" width="46" height="44" rx="7" fill="url(#index-a)" /><rect x="19" y="15" width="31" height="34" rx="4" fill="#FFF6D2" stroke="#16170F" strokeWidth="3.5" /><rect x="9" y="10" width="11" height="44" rx="5" fill="url(#index-b)" stroke="#16170F" strokeWidth="3.5" /><polygon points="40,10 51,10 51,32 45.5,26 40,32" fill="#E23A2C" stroke="#16170F" strokeWidth="3.5" /><rect x="24" y="21" width="20" height="3.5" rx="1.75" fill="#C2B98E" /><rect x="24" y="29" width="20" height="3.5" rx="1.75" fill="#C2B98E" /><rect x="24" y="37" width="13" height="3.5" rx="1.75" fill="#C2B98E" />
      </>
    ),
  },
  'pass': {
    viewBox: '-5 -5 74 74',
    body: (
      <>
        <defs><linearGradient id="pass-a" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#DE93FF" /><stop offset="1" stopColor="#7C1CC0" /></linearGradient><linearGradient id="pass-b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#FFE066" /><stop offset="1" stopColor="#E8930F" /></linearGradient></defs><rect x="5" y="17" width="54" height="30" rx="9" transform="rotate(-7 32 32)" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><polygon points="32,20 35.2,27.6 43.4,28.3 37.2,33.7 39.1,41.7 32,37.5 24.9,41.7 26.8,33.7 20.6,28.3 28.8,27.6" transform="rotate(-7 32 32)" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="5" y="17" width="54" height="30" rx="9" transform="rotate(-7 32 32)" fill="url(#pass-a)" /><polygon points="32,20 35.2,27.6 43.4,28.3 37.2,33.7 39.1,41.7 32,37.5 24.9,41.7 26.8,33.7 20.6,28.3 28.8,27.6" transform="rotate(-7 32 32)" fill="url(#pass-b)" stroke="#16170F" strokeWidth="3.5" /><rect x="11" y="21" width="20" height="5" rx="2.5" transform="rotate(-7 32 32)" fill="#FFFFFF" opacity="0.38" />
      </>
    ),
  },
  'plot': {
    viewBox: '-5 -5 74 74',
    body: (
      <>
        <defs><linearGradient id="plot-a" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#FFF6DF" /><stop offset="1" stopColor="#E0CFA6" /></linearGradient><linearGradient id="plot-b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#FF8A7A" /><stop offset="1" stopColor="#B4241A" /></linearGradient><linearGradient id="plot-c" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#A6EE72" /><stop offset="1" stopColor="#3E9E22" /></linearGradient><linearGradient id="plot-d" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#8C5F3A" /><stop offset="1" stopColor="#4A2F1A" /></linearGradient></defs><rect x="3" y="50" width="58" height="11" rx="5.5" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="43" y="6" width="8.5" height="14" rx="2.5" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="13" y="26" width="38" height="26" rx="2" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><polygon points="32,3 59,26.5 5,26.5" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="3" y="50" width="58" height="11" rx="5.5" fill="url(#plot-c)" /><rect x="43" y="6" width="8.5" height="14" rx="2.5" fill="url(#plot-d)" /><rect x="13" y="26" width="38" height="26" rx="2" fill="url(#plot-a)" /><polygon points="32,3 59,26.5 5,26.5" fill="url(#plot-b)" /><path d="M27.5 52 v-9.5 a4.5 4.5 0 0 1 9 0 V52 z" fill="url(#plot-d)" stroke="#16170F" strokeWidth="3.5" /><circle cx="35" cy="46" r="1.4" fill="#FFE066" /><rect x="16.5" y="33" width="9" height="9" rx="2" fill="#7FDBFF" stroke="#16170F" strokeWidth="3.5" /><rect x="38.5" y="33" width="9" height="9" rx="2" fill="#7FDBFF" stroke="#16170F" strokeWidth="3.5" /><path d="M8 51 H56" fill="none" stroke="#2F7A16" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" /><polygon points="32,8 36,11.5 15,24 8,24" fill="#FFFFFF" opacity="0.28" />
      </>
    ),
  },
  'settings': {
    viewBox: '-5 -5 74 74',
    body: (
      <>
        <defs><linearGradient id="settings-a" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#FCFCF6" /><stop offset="1" stopColor="#9AA28E" /></linearGradient></defs><rect x="26.5" y="3" width="11" height="20" rx="4" transform="rotate(0 32 32)" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="26.5" y="3" width="11" height="20" rx="4" transform="rotate(45 32 32)" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="26.5" y="3" width="11" height="20" rx="4" transform="rotate(90 32 32)" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="26.5" y="3" width="11" height="20" rx="4" transform="rotate(135 32 32)" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="26.5" y="3" width="11" height="20" rx="4" transform="rotate(180 32 32)" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="26.5" y="3" width="11" height="20" rx="4" transform="rotate(225 32 32)" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="26.5" y="3" width="11" height="20" rx="4" transform="rotate(270 32 32)" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="26.5" y="3" width="11" height="20" rx="4" transform="rotate(315 32 32)" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><circle cx="32" cy="32" r="19" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><circle cx="32" cy="32" r="7.5" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><rect x="26.5" y="3" width="11" height="20" rx="4" transform="rotate(0 32 32)" fill="url(#settings-a)" /><rect x="26.5" y="3" width="11" height="20" rx="4" transform="rotate(45 32 32)" fill="url(#settings-a)" /><rect x="26.5" y="3" width="11" height="20" rx="4" transform="rotate(90 32 32)" fill="url(#settings-a)" /><rect x="26.5" y="3" width="11" height="20" rx="4" transform="rotate(135 32 32)" fill="url(#settings-a)" /><rect x="26.5" y="3" width="11" height="20" rx="4" transform="rotate(180 32 32)" fill="url(#settings-a)" /><rect x="26.5" y="3" width="11" height="20" rx="4" transform="rotate(225 32 32)" fill="url(#settings-a)" /><rect x="26.5" y="3" width="11" height="20" rx="4" transform="rotate(270 32 32)" fill="url(#settings-a)" /><rect x="26.5" y="3" width="11" height="20" rx="4" transform="rotate(315 32 32)" fill="url(#settings-a)" /><circle cx="32" cy="32" r="19" fill="url(#settings-a)" /><circle cx="32" cy="32" r="7.5" fill="#5A6350" stroke="#16170F" strokeWidth="4" /><path d="M20 24 A16 16 0 0 1 32 18" fill="none" stroke="#FFFFFF" strokeWidth="4.5" strokeLinecap="round" strokeLinejoin="round" />
      </>
    ),
  },
  'shops': {
    viewBox: '-5 -5 74 74',
    body: (
      <>
        <defs><linearGradient id="shops-a" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#FCFCF6" /><stop offset="1" stopColor="#9AA28E" /></linearGradient><linearGradient id="shops-b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#FFE066" /><stop offset="1" stopColor="#E8930F" /></linearGradient></defs><path d="M4 9 H13 L17 21" fill="none" stroke="#16170F" strokeWidth="16" strokeLinejoin="round" strokeLinecap="round" /><polygon points="15,21 58,21 51,41 23,41" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><path d="M24 41 L27 48 M48 41 L46 48" fill="none" stroke="#16170F" strokeWidth="14" strokeLinejoin="round" strokeLinecap="round" /><circle cx="27" cy="53" r="6" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><circle cx="47" cy="53" r="6" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><path d="M4 9 H13 L17 21" fill="none" stroke="#4A4B41" strokeWidth="7" strokeLinecap="round" strokeLinejoin="round" /><polygon points="15,21 58,21 51,41 23,41" fill="url(#shops-a)" /><path d="M24 41 L27 48 M48 41 L46 48" fill="none" stroke="#4A4B41" strokeWidth="5" strokeLinecap="round" strokeLinejoin="round" /><circle cx="27" cy="53" r="6" fill="url(#shops-b)" /><circle cx="47" cy="53" r="6" fill="url(#shops-b)" /><path d="M18 30 H55 M27 21 L29 41 M37 21 L37 41 M47 21 L45 41" fill="none" stroke="#7C8570" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" /><rect x="19" y="23.5" width="14" height="4" rx="2" fill="#FFFFFF" opacity="0.55" />
      </>
    ),
  },
  'skip': {
    viewBox: '-5 -5 74 74',
    body: (
      <>
        <defs><linearGradient id="skip-a" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#6FD8FF" /><stop offset="1" stopColor="#125FA8" /></linearGradient><linearGradient id="skip-b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#3AA7E8" /><stop offset="1" stopColor="#0D4A85" /></linearGradient><linearGradient id="skip-c" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#FF8A7A" /><stop offset="1" stopColor="#C8231C" /></linearGradient></defs><circle cx="33" cy="29" r="24" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><path d="M13 52 L29 33" fill="none" stroke="#16170F" strokeWidth="16" strokeLinejoin="round" strokeLinecap="round" /><polygon points="5,60 6,45 21,59" fill="#16170F" stroke="#16170F" strokeWidth="9" strokeLinejoin="round" strokeLinecap="round" /><circle cx="33" cy="29" r="24" fill="url(#skip-a)" /><circle cx="33" cy="29" r="17.5" fill="#FAFAF4" stroke="#16170F" strokeWidth="3.5" /><circle cx="33" cy="29" r="11" fill="url(#skip-b)" stroke="#16170F" strokeWidth="3.5" /><circle cx="33" cy="29" r="4.5" fill="url(#skip-c)" stroke="#16170F" strokeWidth="3" /><path d="M13 52 L29 33" fill="none" stroke="#4A4B41" strokeWidth="7" strokeLinecap="round" strokeLinejoin="round" /><polygon points="5,60 6,45 21,59" fill="url(#skip-c)" /><path d="M9 47 A20 20 0 0 1 14 43" fill="none" stroke="#FFFFFF" strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round" /><path d="M18 16 A22 22 0 0 1 31 9" fill="none" stroke="#FFFFFF" strokeWidth="5" strokeLinecap="round" strokeLinejoin="round" />
      </>
    ),
  },
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
