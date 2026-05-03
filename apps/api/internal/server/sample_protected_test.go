package server_test

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/michaelj43/kubernetes-mono-app/apps/api/internal/server"
)

func TestSampleProtectedUnauthorized(t *testing.T) {
	t.Parallel()
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/auth/me" {
			t.Fatalf("path %s", r.URL.Path)
		}
		if r.Header.Get("Cookie") != "sap_session=test" {
			t.Fatalf("cookie not forwarded: %q", r.Header.Get("Cookie"))
		}
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer upstream.Close()

	srv := server.New(slog.New(slog.NewTextHandler(io.Discard, nil)), server.Config{
		Version:           "test",
		SharedAuthAPIBase: upstream.URL,
	})
	ts := httptest.NewServer(srv.Router())
	t.Cleanup(ts.Close)

	req, err := http.NewRequest(http.MethodGet, ts.URL+"/v1/sample-protected", nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Cookie", "sap_session=test")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("status %d", res.StatusCode)
	}
}

func TestSampleProtectedOK(t *testing.T) {
	t.Parallel()
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"user":{"email":"a@b.dev","id":"u1","role":"user"}}`))
	}))
	defer upstream.Close()

	srv := server.New(slog.New(slog.NewTextHandler(io.Discard, nil)), server.Config{
		Version:           "test",
		SharedAuthAPIBase: upstream.URL,
	})
	ts := httptest.NewServer(srv.Router())
	t.Cleanup(ts.Close)

	req, err := http.NewRequest(http.MethodGet, ts.URL+"/v1/sample-protected", nil)
	if err != nil {
		t.Fatal(err)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("status %d", res.StatusCode)
	}
	body, _ := io.ReadAll(res.Body)
	if !strings.Contains(string(body), `"ok":true`) || !strings.Contains(string(body), "a@b.dev") {
		t.Fatalf("body %s", body)
	}
}

func TestSampleProtectedCORSPreflight(t *testing.T) {
	t.Parallel()
	srv := server.New(slog.New(slog.NewTextHandler(os.Stderr, nil)), server.Config{Version: "test"})
	ts := httptest.NewServer(srv.Router())
	t.Cleanup(ts.Close)

	req, err := http.NewRequest(http.MethodOptions, ts.URL+"/v1/sample-protected", nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Origin", "https://k8s.michaelj43.dev")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusNoContent {
		t.Fatalf("status %d", res.StatusCode)
	}
	if res.Header.Get("Access-Control-Allow-Origin") != "https://k8s.michaelj43.dev" {
		t.Fatalf("cors origin %q", res.Header.Get("Access-Control-Allow-Origin"))
	}
	if res.Header.Get("Access-Control-Allow-Credentials") != "true" {
		t.Fatal("missing credentials cors")
	}
}
