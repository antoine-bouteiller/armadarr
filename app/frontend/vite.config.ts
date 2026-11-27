import { fileURLToPath } from 'node:url'

import { base, fmt, options, parentImportRestriction, staged, vitePlus } from '@antoine-bouteiller/devkit'
import { svelte } from '@sveltejs/vite-plugin-svelte'
import { defineConfig } from 'vite-plus'

// Written by `buf generate`; edit proto/ instead.
const generated = ['src/gen/**']

// Without the browser condition, Vitest resolves Svelte's server build, which cannot mount components.
const conditions = process.env['VITEST'] === undefined ? undefined : ['browser']

export default defineConfig({
  build: { emptyOutDir: true, outDir: 'dist/client' },
  fmt: { ...fmt, ignorePatterns: [...generated, '.svelte-check/**'], svelte: true },
  lint: {
    extends: [base, vitePlus],
    ignorePatterns: generated,
    options,
    // Replaces Oxlint's default plugins, which add oxc.
    plugins: ['typescript', 'unicorn', 'import'],
    rules: {
      'filename-case': ['error', { cases: { snakeCase: true } }],
      'no-restricted-imports': ['error', { patterns: [parentImportRestriction] }],
    },
  },
  plugins: [svelte()],
  resolve: {
    // Svelte files are outside tsconfig path resolution.
    alias: [{ find: /^@\//, replacement: fileURLToPath(new URL('src/', import.meta.url)) }],
    conditions,
  },
  // The Go server owns /api; `go run ./app/backend/cmd/armadarr` listens on 3000.
  server: { proxy: { '/api': 'http://localhost:3000' } },
  staged,
  test: { environment: 'happy-dom' },
})
