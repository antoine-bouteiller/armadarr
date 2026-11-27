<div align="center">

<img src=".github/logo.svg" width="128" alt="Armadarr logo">

# Armadarr

</div>

Full-stack media management meant to replace the \*arr stack and Autoscan. The server is written in Go, the client in Svelte, and they share a Connect RPC contract defined in `proto/`.

## Setup

Requires Nix. `nix develop` (or direnv with the bundled `.envrc`) provides Go, golangci-lint, buf, Node.js, pnpm and just.

```bash
just install
just dev
```

`just dev` starts the Go server on port **3000** and the Vite dev server with hot reload, which proxies `/api` to it. Open the URL Vite prints. Ctrl-C stops both. Restart it after a Go change; the client reloads by itself.

`just build` writes a single `armadarr` binary that serves the web app at `/` and the API under `/api`. Set `PORT` to change its port.

For Nix, run `nix build`. The flake also exports a [NixOS module](flake.nix) under `nixosModules.default` with `services.armadarr` options.

## Layout

- `app/backend/`: Go server (`cmd/armadarr`, `internal/`)
- `app/frontend/`: Svelte client, a self-contained pnpm project
- `proto/`: Connect RPC contract shared by both

## Development

Run `just` to list the recipes:

```bash
just generate   # Regenerate Go and TypeScript code after editing proto/
just test       # Server and client tests
just fix        # Format and apply safe lint fixes
just check      # Format, lint and type checks, without changing files
just knip       # Unused files, exports and dependencies in the client
```
