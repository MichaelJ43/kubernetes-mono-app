package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/michaelj43/kubernetes-mono-app/apps/api/internal/migrate"
	"github.com/michaelj43/kubernetes-mono-app/apps/api/internal/server"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))

	addr := getenv("HTTP_ADDR", ":8080")
	databaseURL := os.Getenv("DATABASE_URL")
	redisAddr := getenv("REDIS_ADDR", "localhost:6379")
	ver := getenv("APP_VERSION", "dev")

	// Migrations + pool (before serving)
	baseCtx, cancelBase := context.WithTimeout(context.Background(), 60*time.Second)
	var pool *pgxpool.Pool
	if databaseURL != "" {
		var err error
		pool, err = pgxpool.New(baseCtx, databaseURL)
		if err != nil {
			logger.Error("db connect", "err", err)
			os.Exit(1)
		}
		if err := pool.Ping(baseCtx); err != nil {
			logger.Error("db ping", "err", err)
			os.Exit(1)
		}
		if err := migrate.Up(baseCtx, pool); err != nil {
			logger.Error("migrate", "err", err)
			os.Exit(1)
		}
	}
	cancelBase()

	srv := server.New(logger, server.Config{
		Version:   ver,
		Pool:      pool,
		RedisAddr: redisAddr,
		RedisPass: os.Getenv("REDIS_PASSWORD"),
	})

	httpServer := &http.Server{
		Addr:              addr,
		Handler:           srv.Router(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	go func() {
		logger.Info("listening", "addr", addr)
		if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Error("http serve", "err", err)
			os.Exit(1)
		}
	}()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	<-ctx.Done()

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	_ = httpServer.Shutdown(shutdownCtx)
	srv.Close()
	logger.Info("shutdown complete")
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
