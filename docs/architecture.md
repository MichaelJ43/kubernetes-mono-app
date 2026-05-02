# Architecture

## End-to-end flow

```text
Internet → Route 53 → ALB(s) (TLS via ACM)
        → Ingress `portal` (apex `k8s.michaelj43.dev`) → Service `portal` → landing + `/status` (reads Argo Application CRs)
        → Ingress `api` (`api.k8s…`) → Service `api` → Go API
        → CloudNativePG `Cluster` `portfolio-db` (PostgreSQL)
        → Redis — Docker Official image (`deploy/base/redis`)
```

Git is the **source of truth** for the workload: Argo CD reads `deploy/gitops/` and applies child `Application` objects, which in turn sync Helm/Kustomize paths in this mono-repo.

GitHub Actions builds and publishes **API** and **portal** images (`ci.yaml` on `main`). Argo CD deploys tags via Kustomize (**`deploy/base/api`**, **`deploy/base/portal`**; optional **`deploy/overlays/aws-prod`** wraps the API base).

## Failure domains

| Domain | Impact | Mitigation / note |
|--------|--------|-------------------|
| Single EKS node | Pod eviction / node loss | HPA / second replica (optional); Postgres operator failover if `instances > 1` |
| EKS control plane | Regional AWS outage | Not mitigated in a single-cluster portfolio; document backups |
| GitOps desync | Drift between Git and cluster | Argo CD sync status, `selfHeal` (use carefully) |
| ALB / ACM | TLS or routing break | ACM auto-renewal; cert **discovery** matches Ingress host; optional explicit ARN only outside public Git |

## Related docs

- `docs/aws-domain-tls.md` — DNS + certificates
- `docs/gitops.md` — Argo application tree
- `plan.md` — Full blueprint
