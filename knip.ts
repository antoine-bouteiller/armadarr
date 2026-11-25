import { defineKnipConfig } from '@antoine-bouteiller/devkit'

export default defineKnipConfig({
  entry: ['tests/**/*.spec.ts', 'src/client/main.tsx!'],
  project: ['src/**/*.{ts,tsx}!', 'tests/**/*.ts'],
})
