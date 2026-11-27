# Armadarr

Full-stack media management service meant to replace the \*arr stack and Autoscan.

## Layout

- `app/backend/` is the Go server. `app/backend/cmd/armadarr/main.go` is the entry and composition root; `app/backend/internal/` holds every other Go package, and `internal/server` composes the HTTP surface. `go.mod` sits at the repository root so the module also covers `app/frontend/embed.go`.
- `app/frontend/` is the Svelte 5 client and a self-contained pnpm project: run pnpm and `vp` commands from that folder, or with `pnpm --dir app/frontend`. `app/frontend/embed.go` embeds the build output `app/frontend/dist/client` into the binary.
- `proto/armadarr/v1/` is the Connect RPC contract shared by both apps. Change it there, then run `buf generate` from the repository root; never edit `app/backend/internal/gen` or `app/frontend/src/gen` by hand.
- Client imports use the `@/*` alias rooted at `app/frontend/src`. Tests sit beside the code: `_test.go` for Go, `*.test.ts` for the client.
- The design lives in `docs/project_foundation.spec.md` and the specs next to the code (`*.spec.md`).

## Toolchain

- **The dev shell provides every tool.** Run commands inside `nix develop` (direnv loads it): Go, golangci-lint, buf, Node.js and pnpm.
- **Go is the server.** `go run ./app/backend/cmd/armadarr` listens on `PORT` (default 3000). Lint and format with `golangci-lint run ./...` and `golangci-lint fmt ./...` from the root; config lives in `.golangci.yml`, and `depguard` enforces the import boundaries.
- **Vite+ (`vp`) builds, tests, formats and lints the client**, with pnpm as package manager. In `app/frontend`, `pnpm dev` serves the client with hot reload and proxies `/api` to the Go server. `pnpm build` writes `dist/client`; build it before `go build` or the binary serves no client. Config lives in `app/frontend/vite.config.ts`, with shared settings from `@antoine-bouteiller/devkit`.
- **Svelte components need `pnpm run check:svelte`** (`svelte-check --tsgo`) on top of `vp check`, which does not type-check `.svelte` files.
- **Nix pins dependency hashes.** After changing `app/frontend/pnpm-lock.yaml` or `go.sum`, run `scripts/update_nix_hashes.sh` and commit `flake.nix`. CI does it on pushes if you forget.

## Review Checklist for Agents

- [ ] Run `pnpm --dir app/frontend install` after pulling remote changes and before getting started.
- [ ] After changing `proto/`, run `buf lint` and `buf generate`.
- [ ] From the root, run `golangci-lint run ./...` and `go test ./...`.
- [ ] From `app/frontend`, run `pnpm exec vp check`, `pnpm run check:svelte`, `pnpm test`, `pnpm knip` and `pnpm knip:production`.
