# Run `just` with no recipe to list them. Every recipe runs from the repository root.

frontend := "pnpm --dir app/frontend"
oxfmt := "app/frontend/node_modules/.bin/oxfmt -c app/frontend/node_modules/@antoine-bouteiller/devkit/dist/fmt.json"
# Files outside app/frontend, which `vp` does not format.
root_fmt := "'**/*.{md,yml,yaml,json5}' '!app/frontend/**'"

[private]
default:
    @just --list

# Install the client dependencies
install:
    {{ frontend }} install --frozen-lockfile

# Run the Go server on port 3000 and the Vite dev server, which proxies /api to it
dev:
    #!/usr/bin/env bash
    set -euo pipefail
    bin=$(mktemp -d)
    go build -o "$bin/armadarr" ./app/backend/cmd/armadarr
    "$bin/armadarr" &
    server=$!
    trap 'kill "$server" 2>/dev/null; wait "$server" 2>/dev/null; rm -rf "$bin"' EXIT
    {{ frontend }} dev

# Lint the API contract and regenerate the Go and TypeScript code
generate:
    buf lint
    buf generate

# Build the client, then the server binary that embeds it
build:
    {{ frontend }} build
    CGO_ENABLED=0 go build -ldflags="-s -w" -o armadarr ./app/backend/cmd/armadarr

# Run the server and client tests
test:
    go test ./...
    {{ frontend }} test

# Check formatting, lint and types without changing files
check:
    golangci-lint fmt --diff ./...
    golangci-lint run ./...
    go mod tidy -diff
    {{ frontend }} exec vp check
    {{ frontend }} run check:svelte
    {{ oxfmt }} --check {{ root_fmt }}

# Fail when the generated code is out of date with proto/
check-generated: generate
    git diff --exit-code -- app/backend/internal/gen app/frontend/src/gen

# Report unused files, exports and dependencies in the client
knip:
    {{ frontend }} knip
    {{ frontend }} knip:production

# Apply formatting and the lint fixes that are safe
fix:
    golangci-lint fmt ./...
    golangci-lint run --fix ./...
    go mod tidy
    {{ frontend }} exec vp check --fix
    {{ oxfmt }} {{ root_fmt }}

# Recompute the dependency hashes in flake.nix after a lockfile changes
hashes:
    scripts/update_nix_hashes.sh
