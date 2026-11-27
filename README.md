<div align="center">

<img src=".github/logo.svg" width="128" alt="Armadarr logo">

# Armadarr

</div>

Full-stack media management meant to replace the \*arr stack and Autoscan. The server is written in Go, the client in Svelte, and they share a Connect RPC contract defined in `proto/`.

## Setup

Requires Nix. `nix develop` (or direnv with the bundled `.envrc`) provides Go, golangci-lint, buf, Node.js and pnpm.

```bash
pnpm --dir app/frontend install
pnpm --dir app/frontend build   # Builds the client that the server embeds
go run ./app/backend/cmd/armadarr
```

The server listens on port **3000**; set `PORT` to change it. It serves the web app at `/` and the API under `/api`.

For Nix, run `nix build`. The flake also exports a [NixOS module](flake.nix) under `nixosModules.default` with `services.armadarr` options.

## Layout

- `app/backend/`: Go server (`cmd/armadarr`, `internal/`)
- `app/frontend/`: Svelte client, a self-contained pnpm project
- `proto/`: Connect RPC contract shared by both

## Development

```bash
go run ./app/backend/cmd/armadarr   # Server on port 3000
pnpm --dir app/frontend dev         # Client with hot reload, proxying /api to the server
buf generate                        # Regenerate Go and TypeScript code after editing proto/
go test ./...                       # Server tests
pnpm --dir app/frontend test        # Client tests
golangci-lint run ./...             # Lint the server
pnpm --dir app/frontend run check   # Format, lint and type-check the client
```

After changing `app/frontend/pnpm-lock.yaml` or `go.sum`, run `scripts/update_nix_hashes.sh` and commit the updated `flake.nix`.
