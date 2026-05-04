# Repository guide for coding agents

Use this file along with `plan.md` (authoritative product/architecture blueprint).

## Boundaries

- **Terraform** (see `infra/aws/`) owns **account/region** resources. Split roots:
  - **`github_deploy`** — GitHub OIDC + IAM roles for Actions (persists across cluster teardown).
  - **`foundation`** — VPC, EKS, addons, IRSA for AWS Load Balancer Controller.
  - **`k8s_platform`** — Helm `aws-load-balancer-controller`, ExternalDNS, etc.
  - **`parked_site`** — S3 + CloudFront “cluster offline” static site (`static/cluster-offline`), optional Route53.
- **Argo CD** owns **Kubernetes application** state under `deploy/gitops/`.
- See **`docs/github-actions.md`** for secrets, state keys, and which workflows are **manual** vs **default on push**.

**GitHub Actions**

- **Default on push to `main`**: **`static-site-deploy.yaml`** when **`static/cluster-offline/**` or **`infra/aws/parked_site/**`** change (S3 sync + CloudFront invalidation; Terraform **`parked_site`**).
- **CI tests**: **`ci.yaml`** on push/PR (Go only; no container build).
- **Manual**: **`terraform-apply.yaml`** (EKS + **`github_deploy`** + Argo bootstrap), **`kubernetes-images.yaml`** (GHCR images + Kustomize pin + optional rollout), destroy / soft-destroy / full-destroy workflows — see **`docs/github-actions.md`**.
- **Secrets** must not be committed in plaintext; patterns in docs and **`plan.md`** (e.g. §4.4).

## Layout (high signal)

| Path | Purpose |
|------|---------|
| `apps/api` | Go HTTP API, Dockerfile, OpenAPI |
| `infra/aws/github_deploy` | Terraform: GitHub OIDC trust + `gha-terraform` / `gha-bootstrap` IAM roles |
| `infra/aws/foundation` | Terraform: VPC, EKS; reads **`github_deploy`** remote state for role ARNs |
| `infra/aws/k8s_platform` | Terraform: Helm `aws-load-balancer-controller`, ExternalDNS |
| `infra/aws/parked_site` | Terraform: S3 + CloudFront + `/status` → `status.html` function |
| `static/cluster-offline` | Static HTML + mock JSON for parked mode (synced by **`static-site-deploy`**) |
| `deploy/gitops` | Root `Application` + app-of-apps children |
| `deploy/base/api` | API Deployment/Service/Ingress; Argo **api** app; ALB **certificate discovery** |
| `deploy/base/portal` | Portal Ingress **`k8s.michaelj43.dev`** + **`/status`**; Argo **portal** app |
| `apps/portal` | Go HTTP server for landing links + status page |
| `deploy/overlays/aws-prod` | Optional Kustomize overlay for prod-only patches |
| `deploy/base/postgres` | CloudNativePG `Cluster` + namespace |
| `deploy/base/redis` | Redis Deployment + Service `redis-master` |
| `infra/argocd` | Helm values for **bootstrap** only |
| `tests/component` | `docker-compose` integration |
| `docs/` | Architecture, TLS, GitOps, **`github-actions.md`**, runbooks |

## Conventions

- Go **module**: `github.com/michaelj43/kubernetes-mono-app/apps/api` — if the GitHub org/user changes, update `go.mod` **import paths** and all imports consistently.
- **`docs/post-merge-runbook.md`**: bring-up order; ensure **`github_deploy`** precedes **`foundation`** on greenfield.
- **Ingress** targets `api.k8s.michaelj43.dev`; ACM **must** be in the same region as the ALB. Prefer **certificate discovery** so ARNs are not in Git (`docs/aws-domain-tls.md`). **CloudFront** viewer cert must be **us-east-1** — reuse **`TF_ACM_CERTIFICATE_ARN`** when it is already that regional ARN.
- **Postgres**: operator first (`cnpg-operator` app), then `Cluster` CR; API expects Secret `portfolio-db-app` key **`uri`**.
- After the **first** push to **`main`**, use **feature branches** for subsequent work.

## Testing expectations

- Run `go test ./...` under `apps/api` before declaring API work done.
- For end-to-end local validation, prefer `tests/component/docker-compose.yaml`.

## Security

- Avoid exposing Argo CD on a public hostname without strong auth (`plan.md` §10).
- Treat **`argocd-teardown`**, **`soft-destroy`**, **`aws-full-destroy`**, and cluster-admin kubeconfigs as destructive capability.
