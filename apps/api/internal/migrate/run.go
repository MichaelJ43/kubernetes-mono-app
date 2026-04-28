package migrate

import (
	"context"
	"database/sql"
	"embed"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"
)

//go:embed sql/*.sql
var embedded embed.FS

// Up applies embedded SQL migrations using goose.
func Up(ctx context.Context, pool *pgxpool.Pool) error {
	db := stdlib.OpenDBFromPool(pool)
	defer func() { _ = db.Close() }()

	if err := ping(ctx, db); err != nil {
		return err
	}

	goose.SetBaseFS(embedded)
	if err := goose.SetDialect("postgres"); err != nil {
		return err
	}
	if err := goose.Up(db, "sql"); err != nil {
		return fmt.Errorf("goose up: %w", err)
	}
	return nil
}

func ping(ctx context.Context, db *sql.DB) error {
	return db.PingContext(ctx)
}
