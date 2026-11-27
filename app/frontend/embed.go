// Package frontend embeds the built Svelte client.
package frontend

import (
	"embed"
	"io/fs"
)

// dist/.gitkeep is tracked so the pattern matches before the client is built.
//
//go:embed all:dist
var dist embed.FS

// Client returns the files `pnpm build` writes to dist/client.
func Client() (fs.FS, error) {
	return fs.Sub(dist, "dist/client")
}
