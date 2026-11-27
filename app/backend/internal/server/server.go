// Package server composes the HTTP surface: the Connect API under /api and the client at /.
package server

import (
	"io/fs"
	"net/http"
	"path"
	"strings"

	"github.com/antoine-bouteiller/armadarr/app/backend/internal/gen/armadarr/v1/armadarrv1connect"
)

// Handler serves the Connect API under /api and the files of client at /.
func Handler(client fs.FS) http.Handler {
	api := http.NewServeMux()
	api.Handle(armadarrv1connect.NewHealthServiceHandler(healthServer{}))

	mux := http.NewServeMux()
	mux.Handle("/api/", http.StripPrefix("/api", api))
	mux.Handle("/", clientHandler(client))
	return mux
}

// clientHandler serves files only: http.FileServerFS would list any directory without an index.html.
func clientHandler(client fs.FS) http.Handler {
	files := http.FileServerFS(client)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		name := strings.TrimPrefix(path.Clean(r.URL.Path), "/")
		if name == "" {
			name = "index.html"
		}
		if info, err := fs.Stat(client, name); err != nil || info.IsDir() {
			http.NotFound(w, r)
			return
		}
		files.ServeHTTP(w, r)
	})
}
