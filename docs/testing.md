# Testing

## Matrix

| Layer | Command | When |
|-------|---------|------|
| Unit | `cd apps/api && go test ./...` | Every PR (`ci.yaml`) |
| Component | `cd tests/component && docker compose -f docker-compose.yaml up --build` | Local / optional CI |
| Contract | See `tests/contract/README.md` | Stretch |
| Live | See `tests/live/README.md` | After deploy |
| Perf | `.github/workflows/perf-smoke.yaml` (`workflow_dispatch`) | Manual |

## Local API only

```bash
cd apps/api
export DATABASE_URL="postgresql://app:app@localhost:5432/app?sslmode=disable"
export REDIS_ADDR=localhost:6379
go run ./cmd/api
```

## Component stack (Postgres + Redis + API)

```bash
cd tests/component
docker compose -f docker-compose.yaml up --build
curl -s localhost:8080/items | jq .
```

## CI

`.github/workflows/ci.yaml` runs Go tests on PR + `main`, and pushes **`ghcr.io/<owner>/kubernetes-mono-app/api`** on pushes to `main`.
