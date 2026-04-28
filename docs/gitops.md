# GitOps (Argo CD)

## What Argo manages

Argo CD is the **continuous reconciler** for everything under the application stack:

- CloudNativePG **operator** (`deploy/gitops/apps/cnpg-operator.yaml`)
- **Postgres cluster** CR (`deploy/base/postgres`)
- **Redis** (Bitnami Helm via `deploy/gitops/apps/redis.yaml`)
- **API** Deployment / Service / `Ingress` (`deploy/base/api`)
- Additional Ingress / TLS wiring (same tree)

Bootstrap-time installs (`infra/argocd/`) are **not** auto-synced from this repo unless you choose to manage Argo itself via Argo—that is intentionally out of scope for the first pass.

## App of apps

1. **Manual / CI step:** `kubectl apply -f deploy/gitops/root-app.yaml` (also run by `argocd-bootstrap` workflow).
2. Root `Application` watches **`deploy/gitops/apps/`** and creates one `Application` CR per file (cnpg, postgres, redis, api).

Sync waves (see annotations):

- `-2` — CNPG operator (CRDs / controller)
- `0` — Redis (namespace + cache)
- `1` — Postgres `Cluster`
- `2` — API (expects DB secret `portfolio-db-app` and Redis service)

## Replacing `repoURL`

All `Application` manifests use:

`https://github.com/michaelj43/kubernetes-mono-app.git`

Fork or rename the repo → **search-replace** that URL (and image `ghcr.io/...`) to match your GitHub org/user.

## Sync policy

Child apps use **automated sync** with **prune** and **selfHeal** for portfolio convenience. Tighten for production (manual sync, approval, or `Application` projects with RBAC).

## Rollback

Use Git revert + push; Argo CD reconciles to the previous commit. For emergencies, you can `argocd app rollback` **after** aligning Git or accepting drift—prefer Git as source of truth.
