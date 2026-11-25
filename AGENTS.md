# Armadarr

Full-stack media management service meant to replace the \*arr stack and Autoscan.

## Layout

- `src/index.ts` is the server entry. `src/server/` holds the Effect HTTP server and API handlers.
- `src/api/` holds the `HttpApi` contract shared by the server and the browser. Change it there, never fork it per side.
- `src/client/` is the React app. `index.html` is imported by `src/server/server.ts`, and Bun bundles it.
- Imports use the `@/*` alias rooted at `src` and `@tests/*` rooted at `tests`. Tests mirror source paths under `tests/`.

## Runtime & packaging

- **Bun is the runtime, bundler, and package manager.** Run the app with `bun src/index.ts`
  (`bun run dev` for watch mode) and manage dependencies with `bun install` / `bun add` / `bun remove`.
  The server is `BunHttpServer` from `@effect/platform-bun`. Bun's `routes` option serves the HTML
  import, and Effect's `HttpRouter` serves `/api`. There is no Vite.
- **Hot reload comes from Bun's dev server.** It is on unless `NODE_ENV=production`.
- **React Compiler handles memoization.** The production build passes `--react-compiler`, and
  oxlint forbids `useMemo` and `useCallback`.
- **Lint, format, and type-check are separate commands** — `bun run lint` (oxlint with
  `--fix`), `bun fmt` (Bun's built-in formatter), and `bun check` (Bun's built-in type
  checker). Config lives in `oxlint.config.ts`, the `[fmt]` section of `bunfig.toml`, and
  `tsconfig.json`. Do not add `fmt` or `check` scripts: they would shadow the built-ins.
  Oxlint and `oxlint-tsgolint` come through `@antoine-bouteiller/devkit` and are patched
  in `node_modules` by `effect-tsgo patch --oxlint`.
- **Tests run on Bun's native runner (`bun test`), not vitest.** Use `bun run test`.
  Import test APIs from `bun:test`.
- **Nix packaging fetches production dependencies only.** `scripts/nix_deps.ts`
  writes `nix/deps.json` (tarball URL, hash, and install path of each package in the
  production closure of `bun.lock`); the flake unpacks them into `node_modules` and
  runs `bun build --compile --production --react-compiler`. The `postinstall` script regenerates it; commit it
  alongside `bun.lock`.

## Review Checklist for Agents

- [ ] Run `bun install` after pulling remote changes and before getting started.
- [ ] Run `bun fmt --check`, `bun run lint`, `bun check`, `bun run test`, `bun run knip`, and `bun run knip:production` to validate changes.
