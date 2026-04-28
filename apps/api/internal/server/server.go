package server

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
)

type Config struct {
	Version   string
	Pool      *pgxpool.Pool
	RedisAddr string
	RedisPass string
}

type Server struct {
	log          *slog.Logger
	version      string
	pool         *pgxpool.Pool
	redis        *redis.Client
	redisEnabled bool
}

func New(log *slog.Logger, cfg Config) *Server {
	s := &Server{log: log, version: cfg.Version, pool: cfg.Pool}

	if cfg.RedisAddr != "" {
		s.redisEnabled = true
		s.redis = redis.NewClient(&redis.Options{
			Addr:     cfg.RedisAddr,
			Password: cfg.RedisPass,
		})
	}

	return s
}

func (s *Server) Close() {
	if s.pool != nil {
		s.pool.Close()
	}
	if s.redis != nil {
		_ = s.redis.Close()
	}
}

func (s *Server) Router() *chi.Mux {
	r := chi.NewRouter()
	r.Use(middleware.RequestID, middleware.RealIP, middleware.Recoverer)

	r.Get("/health", s.health)
	r.Get("/ready", s.ready)
	r.Get("/version", s.versionH)
	r.Get("/items", s.items)
	r.Get("/cache-demo", s.cacheDemo)

	return r
}

func (s *Server) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) ready(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	if s.pool != nil {
		if err := s.pool.Ping(ctx); err != nil {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "not_ready", "component": "postgres"})
			return
		}
	}
	if s.redisEnabled && s.redis != nil {
		if err := s.redis.Ping(ctx).Err(); err != nil {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "not_ready", "component": "redis"})
			return
		}
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

func (s *Server) versionH(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"version": s.version})
}

type item struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
}

func (s *Server) items(w http.ResponseWriter, r *http.Request) {
	if s.pool == nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "database not configured"})
		return
	}
	rows, err := s.pool.Query(r.Context(), `SELECT id, name FROM items ORDER BY id ASC`)
	if err != nil {
		s.log.Error("items query", "err", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "query failed"})
		return
	}
	defer rows.Close()

	var out []item
	for rows.Next() {
		var it item
		if err := rows.Scan(&it.ID, &it.Name); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "scan failed"})
			return
		}
		out = append(out, it)
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": out})
}

func (s *Server) cacheDemo(w http.ResponseWriter, r *http.Request) {
	if !s.redisEnabled || s.redis == nil || s.pool == nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "redis or database not configured"})
		return
	}
	ctx := r.Context()
	key := "cache-demo:items-count"

	cached, err := s.redis.Get(ctx, key).Result()
	if err == nil && cached != "" {
		writeJSON(w, http.StatusOK, map[string]any{"source": "redis", "value": cached})
		return
	}

	var count int
	if err := s.pool.QueryRow(ctx, `SELECT COUNT(*) FROM items`).Scan(&count); err != nil {
		s.log.Error("cache-demo count", "err", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "db count failed"})
		return
	}
	countStr := strconv.Itoa(count)
	if err := s.redis.Set(ctx, key, countStr, 30*time.Second).Err(); err != nil {
		s.log.Error("cache set", "err", err)
	}
	writeJSON(w, http.StatusOK, map[string]any{"source": "postgres", "cached": true, "item_count": count})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
