package server_test

import (
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/michaelj43/kubernetes-mono-app/apps/api/internal/server"
)

func TestHealth(t *testing.T) {
	t.Parallel()
	srv := server.New(slog.New(slog.NewTextHandler(os.Stderr, nil)), server.Config{Version: "test"})
	ts := httptest.NewServer(srv.Router())
	t.Cleanup(ts.Close)

	res, err := http.Get(ts.URL + "/health")
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("status %d", res.StatusCode)
	}
}
