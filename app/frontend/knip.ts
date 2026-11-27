import { defineKnipConfig } from '@antoine-bouteiller/devkit'
import { svelte2tsx } from 'svelte2tsx'

export default defineKnipConfig({
  // The default Svelte compiler only reads <script> blocks; svelte2tsx keeps template references and type-only imports.
  compilers: { svelte: (text: string, filename: string) => svelte2tsx(text, { filename, isTsFile: true, mode: 'ts' }).code },
  entry: ['index.html', 'src/**/*.test.ts'],
  ignore: ['src/gen/**'],
  // Root tooling runs these: buf.gen.yaml calls protoc-gen-es, and the format hook in flake.nix calls oxfmt.
  ignoreDependencies: ['@typescript/native', '@bufbuild/protoc-gen-es', 'oxfmt'],
  project: ['src/**/*.{ts,svelte}!'],
})
