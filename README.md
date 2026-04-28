# kubernetes-mono-app

Portfolio mono-repo: **Go API**, **GitOps (Argo CD)**, **EKS-oriented manifests** (ALB Ingress, CloudNativePG, Redis), and **GitHub Actions** for CI plus Argo bootstrap/teardown.

> **Costs:** EKS control plane, NAT gateways, ALB, and EBS volumes are not free. Tear down or scale down when not demoing.

## Overview

| Area | Path | Notes |
|------|------|--------|
| API | `apps/api` | HTTP `/health`, `/ready`, `/version`, `/items`, `/cache-demo`; goose migrations |
| GitOps | `deploy/gitops` | App-of-apps + per-stack `Application` CRs |
| Manifests | `deploy/base`, `deploy/overlays/aws-prod` | Kustomize; optional ACM patch |
| Argo install | `infra/argocd/values.yaml` | Used only by bootstrap (Actions or Helm CLI) |
| CI | `.github/workflows/ci.yaml` | `go test`, image push to GHCR on `main` |
| Runbooks | `docs/runbooks` | Bootstrap & teardown |

Full design: **`plan.md`**.

```mermaid
flowchart LR
  GH[GitHub repo] --> CI[Actions CI]
  CI --> GHCR[GHCR image]
  GH --> Argo[Argo CD]
  Argo --> EKS[EKS workloads]
  GHCR --> EKS
```

## Replace placeholders

1. **`repoURL` in `deploy/gitops/**/*.yaml`** — defaults to `https://github.com/michaelj43/kubernetes-mono-app.git`.
2. **Container image** — `deploy/base/api` uses `ghcr.io/michaelj43/kubernetes-mono-app/api:latest`; CI publishes `ghcr.io/<github-owner>/kubernetes-mono-app/api` on `main`.
3. **Ingress TLS** — set `alb.ingress.kubernetes.io/certificate-arn` (see `docs/aws-domain-tls.md`).

## Quick start (local)

```bash
cd apps/api && go test ./...
cd ../../tests/component && docker compose -f docker-compose.yaml up --build
```

## Docs

- [`docs/architecture.md`](docs/architecture.md)
- [`docs/aws-domain-tls.md`](docs/aws-domain-tls.md)
- [`docs/gitops.md`](docs/gitops.md)
- [`docs/testing.md`](docs/testing.md)

## License

Private / personal portfolio — add a license if you open-source the repo.
