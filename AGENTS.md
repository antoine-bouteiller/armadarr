# Armadarr

Full-stack media management service meant to replace the \*arr stack and Autoscan.

## Layout

- `app/backend/` is the Go server. `app/backend/cmd/armadarr/main.go` is the entry and composition root; `app/backend/internal/` holds every other Go package, and `internal/server` composes the HTTP surface. `go.mod` sits at the repository root so the module also covers `app/frontend/embed.go`.
- `app/frontend/` is the Svelte 5 client and a self-contained pnpm project: run pnpm and `vp` commands from that folder, or with `pnpm --dir app/frontend`. `app/frontend/embed.go` embeds the build output `app/frontend/dist/client` into the binary.
- `proto/armadarr/v1/` is the Connect RPC contract shared by both apps. Change it there, then run `buf generate` from the repository root; never edit `app/backend/internal/gen` or `app/frontend/src/gen` by hand.
- Client imports use the `@/*` alias rooted at `app/frontend/src`. Tests sit beside the code: `_test.go` for Go, `*.test.ts` for the client.
- The design lives in `docs/project_foundation.spec.md` and the specs next to the code (`*.spec.md`).

## Toolchain

- **The dev shell provides every tool.** Run commands inside `nix develop` (direnv loads it): Go, golangci-lint, buf, Node.js, pnpm and just.
- **`just` is the entry point.** The `justfile` at the root wraps every command below; `just` lists the recipes. CI calls the same recipes, so prefer them over the raw commands.
- **Go is the server.** `go run ./app/backend/cmd/armadarr` listens on `PORT` (default 3000). golangci-lint config lives in `.golangci.yml`, and `depguard` enforces the import boundaries.
- **Vite+ (`vp`) builds, tests, formats and lints the client**, with pnpm as package manager. `app/frontend` is a self-contained pnpm project; `just dev` runs its dev server, which proxies `/api` to the Go server. The client build goes to `app/frontend/dist/client`; build it before `go build` or the binary serves no client (`just build` does both). Config lives in `app/frontend/vite.config.ts`, with shared settings from `@antoine-bouteiller/devkit`.
- **Svelte components need `svelte-check`** on top of `vp check`, which does not type-check `.svelte` files. `just check` runs both.
- **The Nix build needs no dependency hash.** Go modules are committed in `vendor/`: `just fix` runs `go mod vendor`, and Renovate updates it in its PRs. Never edit `vendor/` by hand. The client build reads `app/frontend/pnpm-lock.yaml` directly through `nix/pnpm-lock.nix`.

## Review Checklist for Agents

- [ ] Run `just install` after pulling remote changes and before getting started.
- [ ] After changing `proto/`, run `just generate`.
- [ ] Run `just fix`, then `just check`, `just test` and `just knip` to validate changes.
