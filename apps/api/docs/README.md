# API

Go HTTP service for the portfolio mono-repo. Exposes `/health`, `/ready`, `/version`, `/items`, `/cache-demo`.

## Environment variables

| Variable | Required | Description |
|----------|----------|-------------|
| `HTTP_ADDR` | no | Listen address (default `:8080`) |
| `DATABASE_URL` | for `/items`, migrations | PostgreSQL URL (`postgresql://…`) |
| `REDIS_ADDR` | for cache demo | `host:6379` |
| `REDIS_PASSWORD` | no | Redis password if auth enabled |
| `APP_VERSION` | no | Shown on `/version` (CI injects Git SHA) |

## Migrations

SQL lives in `internal/migrate/sql/` and runs automatically at startup when `DATABASE_URL` is set (via [goose](https://github.com/pressly/goose)).

Local example after Postgres is up:

```bash
export DATABASE_URL="postgresql://app:app@localhost:5432/app?sslmode=disable"
go run ./cmd/api
```

## Container

```bash
docker build -t api:local -f Dockerfile .
docker run --rm -e DATABASE_URL=... -e REDIS_ADDR=... -p 8080:8080 api:local
```
