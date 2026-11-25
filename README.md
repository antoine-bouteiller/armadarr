<div align="center">

<img src=".github/logo.svg" width="128" alt="Armadarr logo">

# Armadarr

</div>

Full-stack media management meant to replace the \*arr stack and Autoscan. The server uses Bun and Effect, and the client uses React.

## Setup

Requires Bun 1.4.5 (pinned by the `bun-flake` input in `flake.nix`).

```bash
bun install
bun run dev
```

The server listens on port **3000**; set `PORT` to change it. It serves the web app at `/` and the API under `/api`.

For Nix, run `nix build`. `nix develop` (or direnv with the bundled `.envrc`) provides the pinned Bun and Node; the flake also exports a [NixOS module](flake.nix) under `nixosModules.default` with `services.armadarr` options.

## Development

```bash
bun run dev     # Watch mode, hot-reloaded client
bun run test    # Tests
bun fmt         # Format
bun run lint    # Auto-fix lint findings
bun check       # Type-check
```

`bun install` regenerates `nix/deps.json` (production dependencies for the Nix build); commit it with `bun.lock` when dependencies change.
