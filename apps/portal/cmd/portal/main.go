package main

import (
	"context"
	"html/template"
	"log"
	"net/http"
	"os"
	"sort"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/rest"
)

var appGVR = schema.GroupVersionResource{Group: "argoproj.io", Version: "v1alpha1", Resource: "applications"}

type appRow struct {
	Name   string
	Health string
	Sync   string
}

var homeTmpl = template.Must(template.New("home").Parse(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <meta name="robots" content="noindex"/>
  <title>k8s.michaelj43.dev</title>
  <link rel="stylesheet" href="https://static.michaelj43.dev/v1/m43-tokens.css"/>
  <link rel="stylesheet" href="https://static.michaelj43.dev/v1/m43-shell.css"/>
  <link rel="stylesheet" href="https://static.michaelj43.dev/v1/m43-primitives.css"/>
</head>
<body class="m43 m43-page">
  <div data-m43-auth-header></div>
  <div class="m43-page__body m43">
    <header class="m43-site-header">
      <h1>Portfolio cluster</h1>
      <p class="m43-intro">Gateway host for the mono-app stack (Terraform + EKS + Argo CD).</p>
    </header>
    <main class="m43-main">
      <p class="m43-section-title">Sample API (HTTPS)</p>
      <ul class="m43-intro" style="margin-top:0">
        <li><a href="{{.APIBase}}/health"><code>/health</code></a> — liveness</li>
        <li><a href="{{.APIBase}}/ready"><code>/ready</code></a> — readiness (Postgres + Redis)</li>
        <li><a href="{{.APIBase}}/version"><code>/version</code></a> — build/version</li>
        <li><a href="{{.APIBase}}/items"><code>/items</code></a> — DB-backed list</li>
        <li><a href="{{.APIBase}}/cache-demo"><code>/cache-demo</code></a> — Redis cache demo</li>
        <li><a href="{{.APIBase}}/v1/sample-protected"><code>/v1/sample-protected</code></a> — requires shared-platform login (<code>sap_session</code>); server delegates to <code>api.michaelj43.dev/v1/auth/me</code></li>
      </ul>
      <nav class="m43-nav" aria-label="Site">
        <a href="/status">Argo CD application status</a>
      </nav>
    </main>
  </div>
  <script src="https://static.michaelj43.dev/v1/m43-analytics.js" defer
    data-m43-app="k8s-portal-home"
    data-m43-api="https://api.michaelj43.dev"></script>
  <script src="https://static.michaelj43.dev/v1/m43-auth-header.js" defer
    data-m43-auth
    data-m43-api="https://api.michaelj43.dev"
    data-m43-auth-origin="https://auth.michaelj43.dev"
    data-m43-home-url="https://k8s.michaelj43.dev/"></script>
</body>
</html>`))

var statusTmpl = template.Must(template.New("status").Parse(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <meta name="robots" content="noindex"/>
  <title>Argo CD status · k8s.michaelj43.dev</title>
  <link rel="stylesheet" href="https://static.michaelj43.dev/v1/m43-tokens.css"/>
  <link rel="stylesheet" href="https://static.michaelj43.dev/v1/m43-shell.css"/>
  <link rel="stylesheet" href="https://static.michaelj43.dev/v1/m43-primitives.css"/>
</head>
<body class="m43 m43-page">
  <div data-m43-auth-header></div>
  <div class="m43-page__body m43">
    <header class="m43-site-header">
      <h1>Argo CD applications</h1>
      <p class="m43-intro">Namespaced Applications in <code>argocd</code> — application name, health, and sync status (via Kubernetes API).</p>
      <nav class="m43-nav" aria-label="Site">
        <a href="/">Home</a>
      </nav>
    </header>
    <main class="m43-main">
      <table class="m43-table">
        <thead><tr><th>Name</th><th>Health</th><th>Sync</th></tr></thead>
        <tbody>
          {{range .Rows}}
          <tr><td>{{.Name}}</td><td>{{.Health}}</td><td>{{.Sync}}</td></tr>
          {{else}}
          <tr><td colspan="3" class="m43-intro">No applications found.</td></tr>
          {{end}}
        </tbody>
      </table>
    </main>
  </div>
  <script src="https://static.michaelj43.dev/v1/m43-analytics.js" defer
    data-m43-app="k8s-portal-status"
    data-m43-api="https://api.michaelj43.dev"></script>
  <script src="https://static.michaelj43.dev/v1/m43-auth-header.js" defer
    data-m43-auth
    data-m43-api="https://api.michaelj43.dev"
    data-m43-auth-origin="https://auth.michaelj43.dev"
    data-m43-home-url="https://k8s.michaelj43.dev/"></script>
</body>
</html>`))

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func main() {
	apiBase := getenv("PUBLIC_API_BASE", "https://api.k8s.michaelj43.dev")
	addr := getenv("HTTP_ADDR", ":8080")

	cfg, err := rest.InClusterConfig()
	if err != nil {
		log.Fatalf("in-cluster config: %v", err)
	}
	dc, err := dynamic.NewForConfig(cfg)
	if err != nil {
		log.Fatalf("dynamic client: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		_ = homeTmpl.Execute(w, struct{ APIBase string }{APIBase: apiBase})
	})
	mux.HandleFunc("/status", func(w http.ResponseWriter, r *http.Request) {
		statusPage(w, r, dc)
	})

	srv := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
	}
	log.Printf("listening %s", addr)
	log.Fatal(srv.ListenAndServe())
}

func statusPage(w http.ResponseWriter, r *http.Request, dc dynamic.Interface) {
	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
	defer cancel()

	list, err := dc.Resource(appGVR).Namespace("argocd").List(ctx, metav1.ListOptions{})
	if err != nil {
		http.Error(w, "could not list Argo CD applications", http.StatusBadGateway)
		log.Printf("list applications: %v", err)
		return
	}

	rows := make([]appRow, 0, len(list.Items))
	for _, item := range list.Items {
		name := item.GetName()
		health, _, _ := unstructured.NestedString(item.Object, "status", "health", "status")
		syncSt, _, _ := unstructured.NestedString(item.Object, "status", "sync", "status")
		if health == "" {
			health = "—"
		}
		if syncSt == "" {
			syncSt = "—"
		}
		rows = append(rows, appRow{Name: name, Health: health, Sync: syncSt})
	}
	sort.Slice(rows, func(i, j int) bool { return rows[i].Name < rows[j].Name })

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_ = statusTmpl.Execute(w, struct{ Rows []appRow }{Rows: rows})
}
