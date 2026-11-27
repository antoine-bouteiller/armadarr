package server_test

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"testing/fstest"

	"connectrpc.com/connect"

	armadarrv1 "github.com/antoine-bouteiller/armadarr/app/backend/internal/gen/armadarr/v1"
	"github.com/antoine-bouteiller/armadarr/app/backend/internal/gen/armadarr/v1/armadarrv1connect"
	"github.com/antoine-bouteiller/armadarr/app/backend/internal/server"
)

func newServer(t *testing.T) *httptest.Server {
	t.Helper()
	client := fstest.MapFS{
		"index.html":      {Data: []byte(`<div id="app"></div>`)},
		"assets/index.js": {Data: []byte(`console.log("client")`)},
		"assets/icon.svg": {Data: []byte(`<svg></svg>`)},
	}
	srv := httptest.NewServer(server.Handler(client))
	t.Cleanup(srv.Close)
	return srv
}

func get(t *testing.T, srv *httptest.Server, path string) (status int, body string) {
	t.Helper()
	req, err := http.NewRequestWithContext(t.Context(), http.MethodGet, srv.URL+path, http.NoBody)
	if err != nil {
		t.Fatal(err)
	}
	res, err := srv.Client().Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	raw, err := io.ReadAll(res.Body)
	if err != nil {
		t.Fatal(err)
	}
	return res.StatusCode, string(raw)
}

func TestServesClientPageAtRoot(t *testing.T) {
	srv := newServer(t)

	if _, body := get(t, srv, "/"); !strings.Contains(body, `<div id="app"></div>`) {
		t.Fatalf("GET / = %q, want the client page", body)
	}
}

func TestDoesNotListClientDirectories(t *testing.T) {
	srv := newServer(t)

	if status, body := get(t, srv, "/assets/"); status != http.StatusNotFound {
		t.Fatalf("GET /assets/ = %d %q, want 404", status, body)
	}
}

func TestAnswersHealthCheckThroughContract(t *testing.T) {
	srv := newServer(t)
	client := armadarrv1connect.NewHealthServiceClient(srv.Client(), srv.URL+"/api")

	res, err := client.Check(t.Context(), connect.NewRequest(&armadarrv1.CheckRequest{}))
	if err != nil {
		t.Fatal(err)
	}

	if got := res.Msg.GetStatus(); got != armadarrv1.Status_STATUS_OK {
		t.Fatalf("status = %v, want STATUS_OK", got)
	}
}
