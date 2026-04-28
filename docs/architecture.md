# Architecture

## End-to-end flow

```text
Internet → Route 53 (k8s.michaelj43.dev) → ALB (TLS via ACM)
        → AWS Load Balancer Controller → Ingress `api`
        → Service `api` (ClusterIP) → Pods (Go API)
        → CloudNativePG `Cluster` `portfolio-db` (PostgreSQL)
        → Bitnami Redis (cache, in-cluster)
```

Git is the **source of truth** for the workload: Argo CD reads `deploy/gitops/` and applies child `Application` objects, which in turn sync Helm/Kustomize paths in this mono-repo.

GitHub Actions builds and publishes the **container image** (`ci.yaml` on `main`). Argo CD deploys that image tag via Kustomize (**`deploy/overlays/aws-prod`**, which includes **`deploy/base/api`**).

## Failure domains

| Domain | Impact | Mitigation / note |
|--------|--------|-------------------|
| Single EKS node | Pod eviction / node loss | HPA / second replica (optional); Postgres operator failover if `instances > 1` |
| EKS control plane | Regional AWS outage | Not mitigated in a single-cluster portfolio; document backups |
| GitOps desync | Drift between Git and cluster | Argo CD sync status, `selfHeal` (use carefully) |
| ALB / ACM | TLS or routing break | ACM auto-renewal; validate Ingress annotations |

## Related docs

- `docs/aws-domain-tls.md` — DNS + certificates
- `docs/gitops.md` — Argo application tree
- `plan.md` — Full blueprint
