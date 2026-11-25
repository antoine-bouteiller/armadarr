import { base, effect, options, react } from '@antoine-bouteiller/devkit'
import { recommended } from '@effect/tsgo/oxlint-presets'
import { defineConfig } from 'oxlint'

export default defineConfig({
  extends: [recommended, base, effect, react],
  options,
  ignorePatterns: ['oxlint.config.ts'],
  overrides: [
    {
      files: ['src/client/**'],
      env: { browser: true },
    },
  ],
  plugins: ['typescript', 'unicorn', 'import', 'node', 'react', 'effecttsgo'],
  rules: {
    'unicorn/filename-case': ['error', { cases: { snakeCase: true } }],
    'no-this-alias': 'off',
  },
})
