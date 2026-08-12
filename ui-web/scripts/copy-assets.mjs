// tsc only emits .js/.d.ts — the stylesheet and font binaries are copied verbatim
// so dist/ is the complete, self-contained artifact the converter consumes.
import { cpSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
mkdirSync(join(root, 'dist'), { recursive: true })

for (const asset of ['styles.css', 'fonts.css', 'index.css', 'fonts']) {
  cpSync(join(root, 'src', asset), join(root, 'dist', asset), { recursive: true })
}
console.log('copied styles.css, fonts.css, index.css, fonts/')
