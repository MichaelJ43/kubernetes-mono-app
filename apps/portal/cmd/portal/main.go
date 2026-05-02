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
  <title>k8s.michaelj43.dev</title>
  <style>
    :root { color-scheme: dark light; font-family: system-ui, sans-serif; }
    body { max-width: 42rem; margin: 2rem auto; padding: 0 1rem; line-height: 1.5; }
    h1 { font-size: 1.35rem; }
    ul { padding-left: 1.2rem; }
    a { color: #2563eb; }
    @media (prefers-color-scheme: dark) { a { color: #93c5fd; } }
    .muted { color: #64748b; font-size: 0.9rem; }
    nav { margin-top: 1.5rem; }
  </style>
</head>
<body>
  <h1>Portfolio cluster</h1>
  <p class="muted">Gateway host for the mono-app stack (Terraform + EKS + Argo CD).</p>
  <p>Sample API (HTTPS):</p>
  <ul>
    <li><a href="{{.APIBase}}/health"><code>/health</code></a> — liveness</li>
    <li><a href="{{.APIBase}}/ready"><code>/ready</code></a> — readiness (Postgres + Redis)</li>
    <li><a href="{{.APIBase}}/version"><code>/version</code></a> — build/version</li>
    <li><a href="{{.APIBase}}/items"><code>/items</code></a> — DB-backed list</li>
    <li><a href="{{.APIBase}}/cache-demo"><code>/cache-demo</code></a> — Redis cache demo</li>
  </ul>
  <nav>
    <a href="/status">Argo CD application status</a>
  </nav>
</body>
</html>`))

var statusTmpl = template.Must(template.New("status").Parse(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Argo CD status</title>
  <style>
    :root { color-scheme: dark light; font-family: system-ui, sans-serif; }
    body { max-width: 52rem; margin: 2rem auto; padding: 0 1rem; line-height: 1.5; }
    h1 { font-size: 1.35rem; }
    table { border-collapse: collapse; width: 100%; margin-top: 1rem; font-size: 0.95rem; }
    th, td { text-align: left; padding: 0.45rem 0.6rem; border-bottom: 1px solid #cbd5e1; }
    th { font-weight: 600; }
    .muted { color: #64748b; font-size: 0.9rem; }
    a { color: #2563eb; }
    @media (prefers-color-scheme: dark) {
      th, td { border-color: #334155; }
      a { color: #93c5fd; }
    }
  </style>
</head>
<body>
  <h1>Argo CD applications</h1>
  <p class="muted">Namespaced Applications in <code>argocd</code> — only application name, health, and sync status (via Kubernetes API).</p>
  <p><a href="/">← Home</a></p>
  <table>
    <thead><tr><th>Name</th><th>Health</th><th>Sync</th></tr></thead>
    <tbody>
      {{range .Rows}}
      <tr><td>{{.Name}}</td><td>{{.Health}}</td><td>{{.Sync}}</td></tr>
      {{else}}
      <tr><td colspan="3" class="muted">No applications found.</td></tr>
      {{end}}
    </tbody>
  </table>
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
